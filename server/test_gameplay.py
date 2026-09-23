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
from server.gameplay import register_player


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
            row = conn.execute("SELECT solution FROM aa.run_questions WHERE run_id=%s AND question_id=%s",
                               (run_id, question['id'])).fetchone()
        if question['type'] == 'matching':
            return row['solution']
        return {('selected_option_ids' if question['type'] == 'multiple_choice' else 'order'): row['solution']['ids']}

    def answer(self, run_id, question, response, request_id=None):
        return self.post(f'/runs/{run_id}/attempts', {"question_id": question['id'],
                         "request_id": request_id or str(uuid4()), "response": response, "elapsed_ms": 100})

    def test_full_run_retry_resume_badge_and_identity_privacy(self):
        run = self.start()
        self.assertEqual(len(run['questions']), 13)
        serialized = json.dumps(run)
        for private in ('correct_option_ids', 'correct_order', 'solution', '"right"', '"pid"'):
            self.assertNotIn(private, serialized)
        self.assertEqual(self.start()['id'], run['id'])
        self.assertEqual(self.post(f"/runs/{run['id']}/finish").status_code, 409)
        first = run['questions'][0]
        right = self.solution(run['id'], first)
        wrong = next(o['id'] for o in first['payload']['options'] if o['id'] not in right['selected_option_ids'])
        self.assertFalse(self.answer(run['id'], first, {'selected_option_ids': [wrong]}).json()['is_correct'])
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
            self.assertEqual(conn.execute('SELECT count(*) AS n FROM aa.question_attempts WHERE run_id=%s', (run['id'],)).fetchone()['n'], 14)
            summary = conn.execute('SELECT score,questions_correct FROM aa.level_runs WHERE id=%s', (run['id'],)).fetchone()
            self.assertEqual(summary, {'score': 13, 'questions_correct': 13})
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
        self.assertEqual(self.answer(run['id'],question,{'selected_option_ids':['invented']}).status_code,422)
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

    def test_ordering_matching_and_multiselect_require_complete_answers(self):
        run = self.start()
        multi = next(q for q in run['questions'] if q['type'] == 'multiple_choice' and q['payload']['multi_select'])
        right = self.solution(run['id'], multi)['selected_option_ids']
        self.assertFalse(self.answer(run['id'], multi, {'selected_option_ids': right[:1]}).json()['is_correct'])
        ordered = next(q for q in run['questions'] if q['type'] == 'drag_and_drop')
        order = self.solution(run['id'], ordered)['order']
        self.assertFalse(self.answer(run['id'], ordered, {'order': list(reversed(order))}).json()['is_correct'])
        self.assertEqual(self.answer(run['id'], ordered, {'order': order[:-1]}).status_code, 422)
        matching = next(q for q in run['questions'] if q['type'] == 'matching')
        pairs = self.solution(run['id'], matching)['pairs']
        keys = list(pairs)
        swapped = dict(pairs)
        swapped[keys[0]], swapped[keys[1]] = swapped[keys[1]], swapped[keys[0]]
        self.assertFalse(self.answer(run['id'], matching, {'pairs': swapped}).json()['is_correct'])
        self.assertEqual(self.answer(run['id'], matching, {'pairs': {key: pairs[keys[0]] for key in keys}}).status_code, 422)


if __name__ == '__main__':
    unittest.main()
