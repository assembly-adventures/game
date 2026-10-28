"""Scoring, privacy, staff access and calendar-week reporting against synthetic data."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import os
import unittest
from unittest.mock import patch
from uuid import UUID, uuid4

from psycopg.types.json import Jsonb

from . import test_gameplay
from .call_stack import moments
from .database import connect
from .gameplay import learning_event, register_player
from .grading import snapshot
from .reporting import answer_text, weekly_window
from .scoring import stars_for


class ScoringTests(unittest.TestCase):
    def test_stars_use_solution_par_and_persistent_hints(self):
        gate = {"payload": {"kind": "moves", "par": 2}}
        self.assertEqual(stars_for(gate, {"moves": [0, 1]}, 4, False), 3)
        self.assertEqual(stars_for(gate, {"moves": [0, 1, 0]}, 0, True), 1)
        maze = {"payload": {"kind": "maze", "par": 2}}
        self.assertEqual(stars_for(maze, {"program": ["loop:", "lw t0, 0(a0)", "sw t0, 4(a0)"]}, 0, False), 3)
        self.assertEqual(stars_for({"payload": {"kind": "code"}}, {}, 1, True), 1)

    def test_weeks_use_eastern_monday_midnight_including_dst(self):
        for date, hours in (("2026-03-04T12:00:00+00:00", 167), ("2026-10-28T12:00:00+00:00", 169)):
            start, end = weekly_window(now=datetime.fromisoformat(date))
            self.assertEqual((start.weekday(), start.hour, end.weekday(), end.hour), (0, 0, 0, 0))
            self.assertEqual((end.astimezone(timezone.utc)-start.astimezone(timezone.utc)).total_seconds()/3600, hours)
        sunday = datetime.fromisoformat("2026-10-26T03:59:59+00:00")
        monday = sunday + timedelta(seconds=1)
        self.assertEqual(weekly_window(now=sunday)[1], weekly_window(now=monday)[0])
        self.assertEqual(weekly_window(-1, monday), weekly_window(now=sunday))


class AnswerTextTests(unittest.TestCase):
    WALK = {"kind": "walk", "code": [{"line": "main:"}, {"moment": "call", "ask": "Call triple", "options": [
        {"label": "jal ra, triple", "lines": ["jal ra, triple"], "good": True},
        {"label": "j triple", "lines": ["j triple"], "good": False}]}]}

    def test_answers_read_as_students_saw_them(self):
        options = {"multi_select": True, "options": [{"id": "f3", "text": "Stores the value 12 in x5"},
                                                     {"id": "9a", "text": "Adds 12 to the current value of x5"}]}
        buttons = [{"op": "addi", "rd": 5, "rs1": 5, "imm": -1}, {"op": "add", "rd": 10, "rs1": 10, "rs2": 5},
                   {"op": "andi", "rd": 5, "rs1": 0, "imm": 15}]
        cases = [
            ("multiple_choice", options, {"selected_option_ids": ["f3", "9a"]},
             ["Adds 12 to the current value of x5", "Stores the value 12 in x5"]),
            ("drag_and_drop", {"tiles": [{"id": "a", "text": "loop:"}, {"id": "b", "text": "addi t0, t0, 1"}]},
             {"order": ["b", "a"]}, ["1. addi t0, t0, 1", "2. loop:"]),
            ("matching", {"rows": [{"id": "r", "text": "lw"}], "choices": [{"id": "c", "text": "Loads a word"}]},
             {"pairs": {"r": "c"}}, ["lw → Loads a word"]),
            ("puzzle", {"kind": "moves", "buttons": buttons}, {"moves": [2, 0, 1]},
             ["andi t0, x0, 0x0F", "addi t0, t0, -1", "add a0, a0, t0"]),
            ("puzzle", {"kind": "maze"}, {"program": ["loop:", "lw t0, 0(a0)"]}, ["loop:", "lw t0, 0(a0)"]),
            ("puzzle", {"kind": "code"}, {"blanks": ["slli t3, t2, 2"]}, ["Blank 1: slli t3, t2, 2"]),
            ("puzzle", self.WALK, {"choices": [1]}, ["Move 1: j triple"]),
        ]
        for question_type, payload, response, expected in cases:
            with self.subTest(question_type=question_type, response=response):
                self.assertEqual(answer_text("attempt", question_type, payload, response), expected)
        self.assertEqual(answer_text("walk_choice", "puzzle", self.WALK, {"moment": 0, "choice": 1}),
                         ["Move 1: j triple"])

    def test_unreadable_answers_are_shown_as_recorded(self):
        self.assertEqual(answer_text("attempt", "puzzle", {"kind": "frame"}, {"frame": ["ra"]}), ['{"frame": ["ra"]}'])
        self.assertEqual(answer_text("attempt", "multiple_choice", {"options": []}, {"selected_option_ids": ["gone"]}),
                         ['{"selected_option_ids": ["gone"]}'])


@unittest.skipUnless(os.environ.get("TEST_DATABASE_URL"), "Set TEST_DATABASE_URL to an isolated test database")
class ReportingTests(unittest.TestCase):
    # Reuse the authenticated synthetic-player fixture without rerunning the gameplay test class.
    setUp = test_gameplay.GameplayTests.setUp
    cleanup_players = test_gameplay.GameplayTests.cleanup_players
    sign_in = test_gameplay.GameplayTests.sign_in
    post = test_gameplay.GameplayTests.post
    solution = test_gameplay.GameplayTests.solution
    answer = test_gameplay.GameplayTests.answer

    def start(self, level=1, version=1):
        response = self.post("/runs", {"level_id": level, "telemetry_version": version})
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def event(self, run, question, kind="hint", request_id=None, **detail):
        return self.post(f"/runs/{run['id']}/events", {
            "question_id": question["id"], "request_id": request_id or str(uuid4()), "kind": kind, **detail})

    def finish(self, run):
        for question in run["questions"]:
            response = self.answer(run["id"], question, self.solution(run["id"], question))
            self.assertEqual(response.status_code, 200, response.text)
            self.assertTrue(response.json()["is_correct"])
        response = self.post(f"/runs/{run['id']}/finish")
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def board(self, level=1, offset=0):
        response = self.client.get(f"/api/leaderboard?level_id={level}&week_offset={offset}")
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def stored_run(self, onyen, stars, mistakes, ended=None, version=1):
        # Completed-run fixtures isolate ranking rules from already-tested puzzle graders.
        ended = ended or datetime.now(timezone.utc)
        with connect() as conn:
            conn.execute("""INSERT INTO aa.level_runs
                (player_id,level_id,questions_total,questions_correct,passed,outcome,scoring_version,
                 stars_total,mistakes_total,started_at,ended_at)
                SELECT id,1,10,10,true,'completed',%s,%s,%s,%s,%s FROM aa.players WHERE onyen=%s""",
                (version, stars, mistakes, ended-timedelta(hours=1), ended, onyen))

    def test_staff_apis_require_allowlist_and_never_return_pid(self):
        run = self.start()
        with connect() as conn:
            student = str(conn.execute("SELECT id FROM aa.players WHERE onyen=%s", (self.onyen,)).fetchone()["id"])
        paths = ["/api/admin/overview", "/api/admin/levels/1", f"/api/admin/questions/{run['questions'][0]['id']}",
                 "/api/admin/students", f"/api/admin/students/{student}"]
        with patch.dict(os.environ, {"AA_STAFF_ONYENS": ""}):
            self.assertFalse(self.client.get("/api/me").json()["is_staff"])
            for path in paths:
                self.assertEqual(self.client.get(path).status_code, 403, path)
        with patch.dict(os.environ, {"AA_STAFF_ONYENS": f" {self.onyen.upper()}, professor "}):
            self.assertTrue(self.client.get("/api/me").json()["is_staff"])
            for path in paths:
                response = self.client.get(path)
                self.assertEqual(response.status_code, 200, response.text)
                self.assertNotIn('"pid"', response.text)
        self.client.cookies.clear()
        for path in paths + ["/api/leaderboard?level_id=1"]:
            self.assertEqual(self.client.get(path).status_code, 401)

    def test_events_validate_ownership_shape_and_retry_identity(self):
        run = self.start()
        question = run["questions"][0]
        request_id = str(uuid4())
        hint = self.event(run, question, request_id=request_id)
        self.assertEqual(hint.status_code, 200, hint.text)
        self.assertTrue(hint.json()["question_stats"]["hint_used"])
        self.assertEqual(self.event(run, question, request_id=request_id).json(), hint.json())
        self.assertEqual(self.event(run, question, request_id=request_id, moment=0).status_code, 409)
        self.assertEqual(self.event(run, question, "walk_choice", moment=0, choice=0).status_code, 422)
        self.assertEqual(self.event(run, {"id": str(uuid4())}).status_code, 404)
        self.sign_in(self.other)
        self.assertEqual(self.event(run, question).status_code, 404)
        self.sign_in(self.onyen)
        path = f"/api/runs/{run['id']}/events"
        body = {"question_id": question["id"], "request_id": str(uuid4()), "kind": "hint"}
        self.assertEqual(self.client.post(path, json=body).status_code, 403)
        self.assertEqual(self.client.post(path, json=body, headers={"X-AA-Request": "1", "Origin": "https://other.example"}).status_code, 403)
        self.assertEqual(self.event(run, question, "walk_choice", moment=True, choice=0).status_code, 422)

    def test_walkthrough_mistakes_persist_without_strikes_and_are_counted_once(self):
        run = self.start(3)
        question = run["questions"][0]
        request_id = uuid4()
        args = (self.onyen, UUID(run["id"]), UUID(question["id"]), request_id, "walk_choice", 0, 1)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: learning_event(*args), range(2)))
        self.assertEqual([r["is_correct"] for r in results], [False, False])
        resumed = self.start(3)
        self.assertEqual(resumed["strikes"], {})
        self.assertEqual(resumed["question_stats"][question["id"]]["mistakes"], 1)
        self.event(run, question)
        correct = self.answer(run["id"], question, self.solution(run["id"], question)).json()
        self.assertEqual((correct["stars"], correct["question_stats"]["mistakes"]), (1, 1))
        finished = self.finish(run)
        self.assertEqual((finished["stars"], finished["mistakes"], finished["max_stars"]), (22, 1, 24))
        self.assertTrue(finished["leaderboard_eligible"])
        self.assertEqual(self.post(f"/runs/{run['id']}/finish").json(), finished)
        self.assertEqual(self.event(run, question).status_code, 409)
        retried = self.event(run, question, "walk_choice", str(request_id), moment=0, choice=1)
        self.assertEqual(retried.status_code, 200, retried.text)
        self.assertEqual(self.board(3)["my_entry"]["mistakes"], 1)
        with patch.dict(os.environ, {"AA_STAFF_ONYENS": self.onyen}):
            stats = self.client.get(f"/api/admin/questions/{question['id']}").json()["stats"]
            self.assertEqual((stats["first_try_correct_rate"], stats["eventual_correct_rate"], stats["median_attempts"]), (0, 1, 2))

    def test_scoring_retains_mistakes_and_hint_after_a_setback(self):
        run = self.start()
        first, second = run["questions"][:2]
        self.event(run, first)
        self.answer(run["id"], first, self.solution(run["id"], first))
        for _ in range(3):
            result = self.answer(run["id"], second, {"moves": [0]}).json()
        self.assertEqual(result["setback_question_id"], first["id"])
        resumed = self.start()
        self.assertNotIn(first["id"], resumed["solved_question_ids"])
        self.assertTrue(resumed["question_stats"][first["id"]]["hint_used"])
        self.assertEqual(resumed["question_stats"][second["id"]]["mistakes"], 3)
        correct = self.answer(run["id"], first, self.solution(run["id"], first)).json()
        self.assertEqual(correct["stars"], 2)
        self.assertEqual(self.finish(run)["mistakes"], 3)

    def test_best_run_uses_stars_then_mistakes_from_same_run_with_shared_ranks(self):
        self.stored_run(self.onyen, 30, 5)
        self.stored_run(self.onyen, 29, 0)
        self.stored_run(self.other, 30, 5)
        entries = self.board()["entries"]
        self.assertEqual(len(entries), 2)
        self.assertEqual([(e["rank"], e["stars"], e["mistakes"]) for e in entries], [(1, 30, 5), (1, 30, 5)])
        self.stored_run(self.other, 30, 2)
        entries = self.board()["entries"]
        self.assertEqual([(e["onyen"], e["rank"], e["mistakes"]) for e in entries], [(self.other, 1, 2), (self.onyen, 2, 5)])

    def test_hide_removes_identity_from_current_and_historical_boards_but_not_staff(self):
        self.stored_run(self.onyen, 30, 0)
        self.stored_run(self.other, 29, 2)
        self.stored_run(self.onyen, 30, 0, weekly_window(-1)[0]+timedelta(days=1))
        self.assertEqual(self.post("/preferences", {"leaderboard_visible": False}).status_code, 200)
        self.assertIsNone(self.board()["my_entry"]["rank"])
        self.assertFalse(self.client.get("/api/me").json()["leaderboard_visible"])
        self.sign_in(self.other)
        for offset in (0, -1):
            self.assertNotIn(self.onyen, str(self.board(offset=offset)))
        self.assertEqual(self.board()["entries"][0]["rank"], 1)
        with patch.dict(os.environ, {"AA_STAFF_ONYENS": self.other}):
            response = self.client.get("/api/admin/students", params={"q": self.onyen})
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()["students"][0]["onyen"], self.onyen)
        self.assertEqual(self.post("/preferences", {"leaderboard_visible": True, "onyen": self.onyen}).status_code, 422)
        self.assertEqual(self.post("/preferences", {"leaderboard_visible": "false"}).status_code, 422)

    def test_weekly_rollover_uses_completion_time_and_leaves_old_runs_intact(self):
        start, end = weekly_window()
        self.stored_run(self.onyen, 30, 0, start-timedelta(microseconds=1))
        self.stored_run(self.onyen, 29, 1, start)
        self.stored_run(self.other, 28, 2, end-timedelta(microseconds=1))
        self.stored_run(self.other, 30, 0, end)
        self.assertEqual([(e["stars"], e["mistakes"]) for e in self.board()["entries"]], [(29, 1), (28, 2)])
        self.assertEqual(self.board(offset=-1)["my_entry"]["stars"], 30)
        with patch("server.reporting.weekly_window", return_value=(end, end+timedelta(days=7))):
            self.assertEqual([e["onyen"] for e in self.board()["entries"]], [self.other])
        with connect() as conn:
            self.assertEqual(conn.execute("SELECT count(*) AS n FROM aa.level_runs").fetchone()["n"], 4)

    def test_old_client_runs_are_preserved_but_excluded_from_rankings(self):
        run = self.start(version=0)
        self.assertFalse(run["leaderboard_eligible"])
        self.assertFalse(self.start(version=1)["leaderboard_eligible"])
        self.finish(run)
        self.assertEqual(self.board()["entries"], [])
        self.assertTrue(self.start()["leaderboard_eligible"])
        self.assertEqual(self.client.get("/api/leaderboard?level_id=1&week_offset=1").status_code, 422)

    def test_analytics_separates_initial_understanding_from_repeated_practice(self):
        run = self.start(3)
        question = run["questions"][0]
        self.event(run, question, "walk_choice", moment=0, choice=1)
        self.finish(run)
        self.finish(self.start(3))
        with patch.dict(os.environ, {"AA_STAFF_ONYENS": self.onyen}):
            detail = self.client.get(f"/api/admin/questions/{question['id']}").json()
            wrong = moments(question["payload"])[0]["options"][1]["label"]
            self.assertIn({"answer": [f"Move 1: {wrong}"], "is_correct": False, "kind": "walk_choice", "count": 1},
                          detail["common_answers"])
            stats = detail["stats"]
            self.assertEqual((stats["distinct_players"], stats["first_try_sample_size"], stats["first_try_correct_rate"]), (1, 1, 0))
            self.assertEqual((stats["total_attempts"], stats["median_attempts"]), (3, 2))
            self.sign_in(self.other)
            self.finish(self.start(3, version=0))
            self.sign_in(self.onyen)
            stats = self.client.get(f"/api/admin/questions/{question['id']}").json()["stats"]
            self.assertEqual((stats["distinct_players"], stats["first_try_sample_size"]), (2, 1))

    def test_common_answers_count_option_text_across_runs(self):
        # Every run's snapshot gives the options new random IDs; the same pick must still count once.
        right, wrong = "Stores the value 12 in x5", "Adds 12 to the current value of x5"
        with connect() as conn:
            question = conn.execute("""SELECT * FROM aa.questions WHERE level_id=1
                AND type='multiple_choice' AND code_snippet='addi x5, x0, 12'""").fetchone()
            player = conn.execute("SELECT id FROM aa.players WHERE onyen=%s", (self.onyen,)).fetchone()["id"]
            for picks in ([wrong, right], [wrong]):
                public, solution = snapshot(question)
                run_id = conn.execute("""INSERT INTO aa.level_runs (player_id,level_id,outcome,ended_at)
                    VALUES (%s,1,'abandoned',now()) RETURNING id""", (player,)).fetchone()["id"]
                conn.execute("""INSERT INTO aa.run_questions (run_id,question_id,ordinal,public_question,solution,points)
                    VALUES (%s,%s,1,%s,%s,1)""", (run_id, question["id"], Jsonb(public), Jsonb(solution)))
                ids = {option["text"]: option["id"] for option in public["payload"]["options"]}
                for number, text in enumerate(picks, 1):
                    conn.execute("""INSERT INTO aa.question_attempts
                        (run_id,player_id,question_id,attempt_no,response,is_correct) VALUES (%s,%s,%s,%s,%s,%s)""",
                        (run_id, player, question["id"], number, Jsonb({"selected_option_ids": [ids[text]]}), text == right))
        with patch.dict(os.environ, {"AA_STAFF_ONYENS": self.onyen}):
            detail = self.client.get(f"/api/admin/questions/{question['id']}").json()
            self.assertEqual(detail["question"]["code_snippet"], "addi x5, x0, 12")
            self.assertEqual(detail["common_answers"], [
                {"answer": [wrong], "is_correct": False, "kind": "attempt", "count": 2},
                {"answer": [right], "is_correct": True, "kind": "attempt", "count": 1}])
            attempts = self.client.get(f"/api/admin/students/{player}").json()["attempts"]
            self.assertEqual(sorted(attempt["answer"] for attempt in attempts), [[wrong], [wrong], [right]])
            self.assertFalse(any("response" in attempt or "payload" in attempt for attempt in attempts))


if __name__ == "__main__":
    unittest.main()
