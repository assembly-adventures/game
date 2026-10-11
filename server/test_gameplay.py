"""Integration tests against the isolated PostgreSQL database (TEST_DATABASE_URL)."""

from concurrent.futures import ThreadPoolExecutor
from itertools import product
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
from server.gameplay import draw, register_player, replay
from server.test_call_stack import SOLUTIONS as TOWER_SOLUTIONS
from server.puzzles import grade_puzzle
from server.test_puzzles import BANK, GATE_SOLUTIONS, LEVEL1, SOLUTIONS, answer


# One winning response per gate, keyed by level and bank ordinal: button presses for Level 1
# (db/migrations/0005_level1_puzzles.sql and 0010), programs or filled blanks for Level 2 (0007), and
# the moves made at each moment for Level 3 (0012).
REFERENCE = {
    1: {ordinal: {"moves": moves} for ordinal, moves in GATE_SOLUTIONS.items()},
    2: {ordinal: answer(ordinal) for ordinal in SOLUTIONS},
    3: TOWER_SOLUTIONS,
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

    def test_draws_follow_the_pools_and_vary(self):
        bank = [{"id": room["ordinal"], "ordinal": room["ordinal"], "pool": room["pool"]} for room in BANK["rooms"]]
        level = {"draw": BANK["draw"]}
        runs = [[question["ordinal"] for question in draw(level, bank)] for _ in range(60)]
        for ordinals in runs:
            self.assertEqual(len(ordinals), 10)
            self.assertEqual(ordinals[:4], [1, 2, 3, 4])  # The tutorial, in order.
            self.assertEqual(ordinals[7:], [14, 15, 16])  # Both procedure rooms, then the race.
            self.assertIn(ordinals[4], [5, 6, 7, 8])
            self.assertIn(ordinals[5], [9, 10])
            self.assertIn(ordinals[6], [11, 12, 13])
        self.assertGreater(len({tuple(ordinals) for ordinals in runs}), 5)
        self.assertEqual(draw({"draw": None}, bank), bank)

    def test_level_one_draws_the_tutorial_then_one_gate_of_each_topic(self):
        bank = [{"id": gate["ordinal"], "ordinal": gate["ordinal"], "pool": gate["pool"]} for gate in LEVEL1["rooms"]]
        pools = {}
        for gate in LEVEL1["rooms"]:
            pools.setdefault(gate["pool"], []).append(gate["ordinal"])
        runs = [[question["ordinal"] for question in draw({"draw": LEVEL1["draw"]}, bank)] for _ in range(60)]
        for ordinals in runs:
            self.assertEqual(ordinals[:4], [1, 2, 3, 4])
            topics = ["hex", "masks", "flips", "signed", "overflow", "shifts"]
            self.assertEqual([next(pool for pool in topics if n in pools[pool]) for n in ordinals[4:]], topics)
        self.assertGreater(len({tuple(ordinals) for ordinals in runs}), 5)

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

    def start(self, level_id=1):
        result = self.post('/runs', {"level_id": level_id})
        self.assertEqual(result.status_code, 200, result.text)
        return result.json()

    def solution(self, run_id, question):
        with connect() as conn:
            row = conn.execute("""SELECT q.ordinal,q.level_id FROM aa.questions q WHERE q.id=%s""",
                               (question['id'],)).fetchone()
        return REFERENCE[row['level_id']][row['ordinal']]

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
        # One of the three active badges (levels 1 to 3).
        self.assertEqual((round(profile['progress_ratio'], 4), profile['badges_total']), (0.3333, 3))
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
        # Guest mode plays from copies of the rooms (and the draw rule), so they must not drift
        # from the migrations.
        for level in (1, 2, 3):
            guest = json.loads(Path(__file__).parents[1].joinpath(f'levels/level_{level}/guest_rooms.json').read_text())
            rooms = guest['rooms'] if isinstance(guest, dict) else guest
            with connect() as conn:
                rows = conn.execute("""SELECT ordinal,pool,prompt,code_snippet,hint,explanation,payload FROM aa.questions
                    WHERE level_id=%s AND is_active ORDER BY ordinal""", (level,)).fetchall()
                rule = conn.execute('SELECT draw FROM aa.levels WHERE id=%s', (level,)).fetchone()['draw']
            with self.subTest(level=level):
                self.assertEqual([dict(room, code_snippet=room.get('code_snippet'), pool=room.get('pool')) for room in rooms],
                                 [dict(row) for row in rows])
                self.assertEqual(guest.get('draw') if isinstance(guest, dict) else None, rule)

    def test_drawn_gates_take_any_winning_presses_and_reject_bad_ones(self):
        run = self.start()
        # The last two gates come from the overflow and shifts pools, whichever this run drew.
        for gate in run['questions'][8:]:
            payload = gate['payload']
            limit, keys = payload['max_moves'], len(payload['buttons'])
            self.assertTrue(gate['hint'])
            self.assertEqual(self.answer(run['id'], gate, {'moves': [0] * (limit + 1)}).status_code, 422)
            self.assertEqual(self.answer(run['id'], gate, {'moves': [keys]}).status_code, 422)
            presses = [list(moves) for n in range(1, limit + 1) for moves in product(range(keys), repeat=n)]
            loser = next(moves for moves in presses if not grade_puzzle(payload, {'moves': moves}))
            winner = [moves for moves in presses if grade_puzzle(payload, {'moves': moves})][-1]
            self.assertFalse(self.answer(run['id'], gate, {'moves': loser}).json()['is_correct'])
            self.assertTrue(self.answer(run['id'], gate, {'moves': winner}).json()['is_correct'])


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

    def test_memory_maze_draws_ten_rooms_and_awards_its_badge(self):
        run = self.start(2)
        self.assertNotEqual(run['id'], self.start()['id'])
        self.assertEqual(self.start(2)['id'], run['id'])  # Resuming keeps the rooms it drew.
        rooms = run['questions']
        with connect() as conn:
            bank = {str(row['id']): row['ordinal'] for row in conn.execute(
                'SELECT id,ordinal FROM aa.questions WHERE level_id=2 AND is_active').fetchall()}
        ordinals = [bank[room['id']] for room in rooms]
        self.assertEqual(len(rooms), 10)
        self.assertEqual(ordinals[:4] + ordinals[7:], [1, 2, 3, 4, 14, 15, 16])
        self.assertEqual((rooms[0]['payload']['map'], rooms[1]['code_snippet']), (['S...E'], 'a2 = arr[3];'))
        # A step into a wall is a wrong answer (and a strike); a line the room doesn't offer is malformed.
        result = self.answer(run['id'], rooms[0], {'program': ['addi a0, a0, -4']}).json()
        self.assertEqual((result['is_correct'], result['strikes']), (False, 1))
        self.assertEqual(self.answer(run['id'], rooms[3], {'program': ['addi a0, a0, 8']}).status_code, 422)
        # Stack frames: restoring a0 before storing func's answer is wrong; a missing blank is malformed.
        frame = rooms[8]
        wrong = self.answer(run['id'], frame, {'blanks': ['addi sp, sp, -8', 'sw ra, 4(sp)', 'lw a0, 0(sp)']}).json()
        self.assertFalse(wrong['is_correct'])
        self.assertEqual(self.answer(run['id'], frame, {'blanks': ['addi sp, sp, -8']}).status_code, 422)
        for room in rooms:
            result = self.answer(run['id'], room, self.solution(run['id'], room))
            self.assertEqual(result.status_code, 200, result.text)
            self.assertTrue(result.json()['is_correct'], room['prompt'])
        finished = self.post(f"/runs/{run['id']}/finish")
        self.assertEqual(finished.status_code, 200, finished.text)
        self.assertEqual([badge['slug'] for badge in finished.json()['badges']], ['badge_2'])
        levels = {level['id']: level for level in self.client.get('/api/levels').json()}
        self.assertEqual((levels[2]['name'], levels[2]['completed'], levels[1]['completed']), ('Memory Maze', True, False))
        with connect() as conn:
            saved = conn.execute("""SELECT response FROM aa.question_attempts WHERE run_id=%s AND question_id=%s
                AND is_correct""", (run['id'], frame['id'])).fetchone()
        self.assertEqual(saved['response'], {'blanks': SOLUTIONS[15]})  # Attempts keep what the student chose.

    def test_call_stack_tower_plays_its_story_and_awards_its_badge(self):
        run = self.start(3)
        rooms = run['questions']
        with connect() as conn:
            bank = {str(row['id']): row['ordinal'] for row in conn.execute(
                'SELECT id,ordinal FROM aa.questions WHERE level_id=3 AND is_active').fetchall()}
        # The eight walkthroughs, in order: no draw.
        self.assertEqual([bank[room['id']] for room in rooms], list(range(1, 9)))
        self.assertEqual({room['payload']['kind'] for room in rooms}, {'walk'})
        # The game never sends a wrong move (it plays out and rewinds), but one sent anyway is a miss and
        # a strike, and a move the room doesn't offer is malformed.
        result = self.answer(run['id'], rooms[0], {'choices': [1]}).json()
        self.assertEqual((result['is_correct'], result['strikes']), (False, 1))
        self.assertEqual(self.answer(run['id'], rooms[0], {'choices': [2]}).status_code, 422)
        for room in rooms:
            result = self.answer(run['id'], room, self.solution(run['id'], room))
            self.assertEqual(result.status_code, 200, result.text)
            self.assertTrue(result.json()['is_correct'], room['prompt'])
        finished = self.post(f"/runs/{run['id']}/finish")
        self.assertEqual(finished.status_code, 200, finished.text)
        self.assertEqual([badge['slug'] for badge in finished.json()['badges']], ['badge_3'])
        self.assertEqual([badge['name'] for badge in finished.json()['badges']], ['Stack Master'])
        levels = {level['id']: level for level in self.client.get('/api/levels').json()}
        self.assertEqual((levels[3]['name'], levels[3]['completed']), ('Call Stack Tower', True))

    def test_level_one_reads_abi_register_names(self):
        run = self.start()
        self.assertEqual(run['questions'][3]['prompt'],
                         'Turn 2 into 13.\nRegister t1 holds 3, and add t0, t0, t1 adds whatever t1 holds to t0.')
        for question in run['questions']:
            self.assertNotRegex(question['prompt'] + question['hint'], r'\bx\d+\b')

if __name__ == '__main__':
    unittest.main()
