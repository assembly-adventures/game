"""Integration tests against the isolated PostgreSQL database (TEST_DATABASE_URL)."""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient
from itsdangerous import URLSafeTimedSerializer

from server.app import create_app, SESSION_COOKIE
from server.database import connect, migrate
from server.gameplay import register_player, replay


# One winning sequence of button presses per Level 1 gate, keyed by ordinal
# (db/migrations/0005_level1_puzzles.sql).
REFERENCE = {
    1: {"moves": [0]},
    2: {"moves": [0, 0, 0]},
    3: {"moves": [1, 0]},
    4: {"moves": [0, 1, 0]},
    5: {"moves": [2, 0]},
    6: {"moves": [0, 1]},
    7: {"moves": [0, 1]},
    8: {"moves": [0, 1]},
    9: {"moves": [0, 0, 1]},
    10: {"moves": [1, 1, 1]},
}


class ReplayTests(unittest.TestCase):
    """Solved state and strikes come from replaying attempts and setbacks in time order."""

    def log(self, *entries):
        return [{"question_id": gate, "is_correct": correct, "answered_at": at} for at, gate, correct in entries]

    def test_a_setback_reopens_the_gate_until_it_is_solved_again(self):
        attempts = self.log((0, "a", True), (1, "b", False), (2, "b", False), (3, "b", False))
        self.assertEqual(replay(["a", "b"], attempts, {}), ({"a"}, {"a": 0, "b": 3}))
        self.assertEqual(replay(["a", "b"], attempts, {"a": 3.5}), (set(), {"a": 0, "b": 3}))
        attempts += self.log((4, "a", False), (5, "a", True))
        self.assertEqual(replay(["a", "b"], attempts, {"a": 3.5}), ({"a"}, {"a": 1, "b": 0}))

    def test_strikes_count_only_since_the_player_arrived(self):
        attempts = self.log((0, "a", False), (1, "a", False), (2, "a", True), (3, "b", True))
        self.assertEqual(replay(["a", "b"], attempts, {"a": 3.5})[1]["a"], 0)


@unittest.skipUnless(os.environ.get("TEST_DATABASE_URL"), "Set TEST_DATABASE_URL to an isolated test database")
class GameplayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        Path(self.temp.name, "index.html").write_text("game")
        env = patch.dict(os.environ, {"DATABASE_URL": os.environ["TEST_DATABASE_URL"],
            "APP_ORIGIN": "https://game.example", "SESSION_SECRET": "test-secret-" * 5,
            "STATIC_DIR": self.temp.name})
        env.start()
        self.addCleanup(env.stop)
        migrate()
        self.onyen = "test_" + uuid4().hex
        self.other = "test_" + uuid4().hex
        pid = str(100000000 + uuid4().int % 800000000)
        register_player(self.onyen, pid)
        register_player(self.other, str(int(pid) + 1))
        self.addCleanup(self.cleanup_players)
        self.client = TestClient(create_app(), base_url="https://game.example", follow_redirects=False)
        self.addCleanup(self.client.close)
        self.sign_in(self.onyen)

    def cleanup_players(self):
        with connect() as conn:
            conn.execute("DELETE FROM aa.players WHERE onyen IN (%s,%s)", (self.onyen, self.other))

    def sign_in(self, onyen):
        token = URLSafeTimedSerializer("test-secret-" * 5, salt="aa-session-v1").dumps({"uid": onyen, "version": 2})
        self.client.cookies.set(SESSION_COOKIE, token)

    def post(self, path, body=None):
        return self.client.post('/api' + path, json=body or {}, headers={"X-AA-Request": "1", "Origin": "https://game.example"})

    def start(self):
        result = self.post('/runs', {"level_id": 1})
        self.assertEqual(result.status_code, 200, result.text)
        return result.json()

    def solution(self, run_id, question):
        with connect() as conn:
            row = conn.execute("SELECT ordinal FROM aa.run_questions WHERE run_id=%s AND question_id=%s",
                               (run_id, question['id'])).fetchone()
        return REFERENCE[row['ordinal']]

    def answer(self, run_id, question, response, request_id=None):
        return self.post(f'/runs/{run_id}/attempts', {"question_id": question['id'],
                         "request_id": request_id or str(uuid4()), "response": response, "elapsed_ms": 100})

    def test_full_run_retry_resume_badge_and_identity_privacy(self):
        run = self.start()
        self.assertEqual(len(run['questions']), 10)
        serialized = json.dumps(run)
        for private in ('correct_option_ids', 'correct_order', 'solution', '"right"', '"pid"'):
            self.assertNotIn(private, serialized)
        self.assertEqual(self.start()['id'], run['id'])
        self.assertEqual(self.post(f"/runs/{run['id']}/finish").status_code, 409)
        first = run['questions'][0]
        right = self.solution(run['id'], first)
        self.assertFalse(self.answer(run['id'], first, {'moves': [0, 0]}).json()['is_correct'])
        request_id = str(uuid4())
        for _ in range(2):
            self.assertTrue(self.answer(run['id'], first, right, request_id).json()['is_correct'])
        self.assertIn(first['id'], self.start()['solved_question_ids'])
        for question in run['questions'][1:]:
            result = self.answer(run['id'], question, self.solution(run['id'], question))
            self.assertEqual(result.status_code, 200, result.text)
            self.assertTrue(result.json()['is_correct'])
        for _ in range(2):
            result = self.post(f"/runs/{run['id']}/finish")
            self.assertEqual(result.status_code, 200, result.text)
            self.assertEqual(result.json()['badges'][0]['slug'], 'badge_1')
        profile = self.client.get('/api/me').json()
        self.assertEqual(profile['progress_ratio'], 1.0)
        self.assertNotIn('pid', profile)
        with connect() as conn:
            self.assertEqual(conn.execute('SELECT count(*) AS n FROM aa.question_attempts WHERE run_id=%s', (run['id'],)).fetchone()['n'], 11)
            summary = conn.execute('SELECT score,questions_correct FROM aa.level_runs WHERE id=%s', (run['id'],)).fetchone()
            self.assertEqual(summary, {'score': 10, 'questions_correct': 10})
        # Reloading the app and reusing the signed session preserves progress.
        with TestClient(create_app(), base_url='https://game.example') as fresh:
            fresh.cookies.update(self.client.cookies)
            self.assertEqual(fresh.get('/api/me').json()['badges'][0]['slug'], 'badge_1')

    def test_ownership_and_csrf_and_payload_validation(self):
        run = self.start()
        question = run['questions'][0]
        response = self.solution(run['id'], question)
        self.sign_in(self.other)
        self.assertEqual(self.answer(run['id'], question, response).status_code, 404)
        self.assertEqual(self.post(f"/runs/{run['id']}/finish").status_code, 404)
        self.sign_in(self.onyen)
        self.assertEqual(self.client.post('/api/runs', json={'level_id':1}).status_code,403)
        self.assertEqual(self.client.post('/api/runs',json={'level_id':1},headers={'X-AA-Request':'1','Origin':'https://evil.example'}).status_code,403)
        self.assertEqual(self.post('/runs',{'level_id':1,'player_id':str(uuid4())}).status_code,422)
        self.assertEqual(self.post('/runs',{'level_id':5}).status_code,404)
        self.assertEqual(self.answer(run['id'],question,{'moves':[5]}).status_code,422)
        foreign = dict(question, id=str(uuid4()))
        self.assertEqual(self.answer(run['id'],foreign,response).status_code,404)
        self.client.cookies.clear()
        self.assertEqual(self.client.get('/api/me').status_code,401)

    def test_snapshot_survives_question_edit_and_migrations_do_not_reseed(self):
        run = self.start()
        question = run['questions'][0]
        with connect() as conn:
            original = conn.execute('SELECT prompt FROM aa.questions WHERE id=%s',(question['id'],)).fetchone()['prompt']
            conn.execute("UPDATE aa.questions SET prompt='Edited bank question' WHERE id=%s",(question['id'],))
        try:
            migrate()
            resumed = self.start()
            self.assertEqual(resumed['questions'][0]['prompt'], question['prompt'])
            with connect() as conn:
                self.assertEqual(conn.execute('SELECT prompt FROM aa.questions WHERE id=%s',(question['id'],)).fetchone()['prompt'], 'Edited bank question')
        finally:
            with connect() as conn:
                conn.execute('UPDATE aa.questions SET prompt=%s WHERE id=%s',(original,question['id']))

    def test_duplicate_concurrent_answers_award_points_once(self):
        from server.gameplay import attempt
        run = self.start()
        question = run['questions'][0]
        from uuid import UUID
        args = (self.onyen, UUID(run['id']), UUID(question['id']), uuid4(), self.solution(run['id'],question),100)
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: attempt(*args), range(2)))
        self.assertTrue(all(r['is_correct'] for r in results))
        with connect() as conn:
            row = conn.execute('SELECT count(*) AS n,sum(points_awarded) AS points FROM aa.question_attempts WHERE run_id=%s',(run['id'],)).fetchone()
            self.assertEqual(row, {'n':1,'points':1})

    def test_guest_rooms_match_the_database(self):
        # Guest mode plays from a copy of the rooms, so it must not drift from 0005.
        guest = json.loads(Path(__file__).parents[1].joinpath('levels/level_1/guest_rooms.json').read_text())
        with connect() as conn:
            rows = conn.execute("""SELECT ordinal,prompt,hint,explanation,payload FROM aa.questions
                WHERE level_id=1 AND is_active ORDER BY ordinal""").fetchall()
        self.assertEqual(guest, [dict(row) for row in rows])

    def test_gates_accept_any_winning_order_and_reject_bad_presses(self):
        run = self.start()
        overflow, keep_sign = run['questions'][8], run['questions'][9]
        self.assertEqual(overflow['payload']['goal'], {'x5': -96})
        self.assertTrue(overflow['hint'])
        self.assertEqual(self.answer(run['id'], overflow, {'moves': [1, 1, 1, 1, 1]}).status_code, 422)
        self.assertEqual(self.answer(run['id'], overflow, {'moves': [2]}).status_code, 422)
        self.assertFalse(self.answer(run['id'], overflow, {'moves': [1, 1, 1]}).json()['is_correct'])
        self.assertTrue(self.answer(run['id'], overflow, {'moves': [1, 0, 0]}).json()['is_correct'])
        self.assertFalse(self.answer(run['id'], keep_sign, {'moves': [0, 0, 0]}).json()['is_correct'])


    def test_third_strike_drags_the_player_back_a_gate(self):
        run = self.start()
        first, second, third = run['questions'][:3]
        for gate in (first, second):
            self.assertTrue(self.answer(run['id'], gate, self.solution(run['id'], gate)).json()['is_correct'])
        wrong = {'moves': [0, 0, 0]}
        strikes = [self.answer(run['id'], third, wrong).json() for _ in range(2)]
        self.assertEqual([(r['strikes'], r['setback_question_id']) for r in strikes], [(1, None), (2, None)])
        request_id = str(uuid4())
        third_strike = self.answer(run['id'], third, wrong, request_id).json()
        self.assertEqual((third_strike['strikes'], third_strike['setback_question_id']), (3, second['id']))
        # Retrying the same request reports the same setback without adding another.
        self.assertEqual(self.answer(run['id'], third, wrong, request_id).json(), third_strike)
        self.assertEqual(self.start()['solved_question_ids'], [first['id']])
        again = self.answer(run['id'], second, self.solution(run['id'], second)).json()
        self.assertEqual((again['is_correct'], again['strikes']), (True, 0))
        self.assertEqual(self.answer(run['id'], third, wrong).json()['strikes'], 1)
        for question in run['questions'][2:]:
            self.assertTrue(self.answer(run['id'], question, self.solution(run['id'], question)).json()['is_correct'])
        self.assertEqual(self.post(f"/runs/{run['id']}/finish").status_code, 200)
        with connect() as conn:
            summary = conn.execute('SELECT score,questions_correct FROM aa.level_runs WHERE id=%s', (run['id'],)).fetchone()
            setbacks = conn.execute('SELECT count(*) AS n FROM aa.run_setbacks WHERE run_id=%s', (run['id'],)).fetchone()
        # The re-solved gate earns its point only once.
        self.assertEqual((summary, setbacks['n']), ({'score': 10, 'questions_correct': 10}, 1))

    def test_third_strike_on_the_first_gate_restarts_it(self):
        run = self.start()
        first = run['questions'][0]
        results = [self.answer(run['id'], first, {'moves': [0, 0]}).json() for _ in range(3)]
        self.assertEqual(results[-1]['setback_question_id'], first['id'])
        self.assertEqual(self.start()['strikes'], {})
        self.assertEqual(self.answer(run['id'], first, {'moves': [0, 0]}).json()['strikes'], 1)
        self.assertEqual(self.start()['strikes'], {first['id']: 1})

if __name__ == '__main__':
    unittest.main()
