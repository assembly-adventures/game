"""Transactional level runs, attempt history, setbacks, and earned badges."""

import secrets
from uuid import UUID

from fastapi import HTTPException
from psycopg.types.json import Jsonb

from .database import connect
from .grading import grade, snapshot
from .scoring import question_stats
from .call_stack import moments

STRIKES = 3  # Failed tries on a puzzle gate before the Chip Chomper drags the player back a gate.


def register_player(onyen: str, pid: str) -> None:
    """Store verified roster identifiers; identity never comes from gameplay JSON. Each sign-in
    also starts a new session for the draw: gates played before it may come up again."""
    with connect() as conn:
        # Update first: an upsert would use up a player number, the default leaderboard name, on every sign-in.
        if not conn.execute("UPDATE aa.players SET pid=%s,last_seen_at=now(),signed_in_at=now() WHERE onyen=%s",
                            (pid, onyen)).rowcount:
            # Nicknames can't be checked against Onyens nobody has signed in with yet. Whoever took
            # this one as a nickname goes back to Player <number>.
            conn.execute("UPDATE aa.players SET nickname=NULL WHERE nickname=%s", (onyen,))
            conn.execute("""INSERT INTO aa.players(onyen,pid,last_seen_at,signed_in_at) VALUES (%s,%s,now(),now())
                ON CONFLICT (onyen) DO UPDATE SET pid=excluded.pid,last_seen_at=now(),signed_in_at=now()""", (onyen, pid))


def player(conn, onyen: str) -> dict:
    # Serialize a player's mutations, including concurrent start/retry/finish calls.
    row = conn.execute("SELECT id,onyen,leaderboard_visible FROM aa.players WHERE onyen=%s FOR UPDATE", (onyen,)).fetchone()
    if not row:
        raise HTTPException(401, "Please sign in again to create your saved profile.")
    return row


def profile(conn, player_id: UUID) -> dict:
    progress = conn.execute("SELECT * FROM aa.player_progress WHERE player_id=%s", (player_id,)).fetchone()
    badges = conn.execute("""SELECT b.slug,b.name FROM aa.player_badges pb JOIN aa.badges b ON b.id=pb.badge_id
        WHERE pb.player_id=%s AND b.is_active ORDER BY b.id""", (player_id,)).fetchall()
    return {"badges": badges, "badges_total": progress["badges_total"],
            "progress_ratio": progress["progress_ratio"] or 0.0}


def me(onyen: str) -> dict:
    from .reporting import is_staff, names
    with connect() as conn:
        who = player(conn, onyen)
        return {"onyen": str(who["onyen"]), "is_staff": is_staff(onyen), "leaderboard_visible": who["leaderboard_visible"],
                **names(conn, who["id"]), **profile(conn, who["id"])}


def levels(onyen: str) -> list[dict]:
    """Every level, with the player's progress on it: whether they have completed it, their best
    finished run's stars (`best_stars` out of `max_stars`, null before any), and where a run still
    in progress stands (`in_progress`: gates solved and the run's total, or null)."""
    with connect() as conn:
        who = player(conn, onyen)
        rows = conn.execute("""SELECT l.id,l.name,l.slug,l.is_active,
            (SELECT count(*) FROM aa.questions q WHERE q.level_id=l.id AND q.is_active) AS question_count,
            EXISTS(SELECT 1 FROM aa.level_runs r WHERE r.player_id=%(p)s AND r.level_id=l.id AND r.passed) AS completed,
            best.stars_total AS best_stars, best.questions_total * 3 AS max_stars,
            going.id AS going_id, going.questions_total AS going_total
            FROM aa.levels l
            LEFT JOIN LATERAL (SELECT stars_total, questions_total FROM aa.level_runs r
                WHERE r.player_id=%(p)s AND r.level_id=l.id AND r.passed AND r.stars_total IS NOT NULL
                ORDER BY r.stars_total DESC, r.ended_at LIMIT 1) best ON true
            LEFT JOIN LATERAL (SELECT id, questions_total FROM aa.level_runs r
                WHERE r.player_id=%(p)s AND r.level_id=l.id AND r.outcome='in_progress' LIMIT 1) going ON true
            ORDER BY l.ordinal""", {"p": who["id"]}).fetchall()
        for row in rows:
            going_id, total = row.pop("going_id"), row.pop("going_total")
            row["in_progress"] = {"solved": len(progress(conn, going_id)["solved"]), "total": total} if going_id else None
        return rows


def replay(order: list, attempts: list[dict], reopened: dict) -> tuple[set, dict]:
    """Work out which questions are solved now, and each one's strikes, from the attempt log.

    A setback reopens a question, so it counts as solved only with a correct attempt after its
    latest setback. Strikes are wrong attempts since the player last arrived at a question: when
    the question before it was last solved, or when a setback sent the player back to it.
    """
    solved, strikes = set(), {}
    previous_solve = None
    for question_id in order:
        mine = [row for row in attempts if row["question_id"] == question_id]
        reopened_at = reopened.get(question_id)
        corrects = [row["answered_at"] for row in mine if row["is_correct"]]
        if any(reopened_at is None or at > reopened_at for at in corrects):
            solved.add(question_id)
        arrived = max((at for at in (previous_solve, reopened_at) if at is not None), default=None)
        strikes[question_id] = sum(1 for row in mine if not row["is_correct"]
                                   and (arrived is None or row["answered_at"] > arrived))
        previous_solve = max(corrects, default=None)
    return solved, strikes


def progress(conn, run_id: UUID) -> dict:
    questions = conn.execute("""SELECT question_id,public_question->>'type' AS type FROM aa.run_questions
        WHERE run_id=%s ORDER BY ordinal""", (run_id,)).fetchall()
    attempts = conn.execute("SELECT question_id,is_correct,answered_at FROM aa.question_attempts WHERE run_id=%s",
                            (run_id,)).fetchall()
    setbacks = conn.execute("""SELECT question_id,max(created_at) AS at FROM aa.run_setbacks WHERE run_id=%s
        GROUP BY question_id""", (run_id,)).fetchall()
    order = [row["question_id"] for row in questions]
    solved, strikes = replay(order, attempts, {row["question_id"]: row["at"] for row in setbacks})
    return {"order": order, "types": {row["question_id"]: row["type"] for row in questions},
            "solved": solved, "strikes": strikes}


def run_view(conn, run: dict) -> dict:
    rows = conn.execute("SELECT public_question FROM aa.run_questions WHERE run_id=%s ORDER BY ordinal",
                        (run["id"],)).fetchall()
    state = progress(conn, run["id"])
    return {"id": run["id"], "level_id": run["level_id"], "outcome": run["outcome"],
            "questions": [row["public_question"] for row in rows],
            "solved_question_ids": [question_id for question_id in state["order"] if question_id in state["solved"]],
            "question_stats": question_stats(conn, run["id"]),
            "leaderboard_eligible": run["scoring_version"] == 1,
            "strikes": {str(question_id): count for question_id, count in state["strikes"].items()
                        if count and question_id not in state["solved"]}}


def start_run(onyen: str, level_id: int, telemetry_version: int = 0) -> dict:
    with connect() as conn:
        who = player(conn, onyen)
        level = conn.execute("SELECT * FROM aa.levels WHERE id=%s AND is_active", (level_id,)).fetchone()
        if not level:
            raise HTTPException(404, "This level is not available yet.")
        if level["completion_rule"] != {"type": "all_correct"}:
            raise HTTPException(503, "This completion rule is not supported yet.")
        active = conn.execute("SELECT * FROM aa.level_runs WHERE player_id=%s AND level_id=%s AND outcome='in_progress'",
                              (who["id"], level_id)).fetchone()
        if active:
            return run_view(conn, active)
        played, last = played_this_session(conn, who["id"], level_id) if level.get("draw") else ({}, set())
        questions = draw(level, conn.execute("SELECT * FROM aa.questions WHERE level_id=%s AND is_active ORDER BY ordinal",
                                             (level_id,)).fetchall(), played, last)
        if not questions:
            raise HTTPException(409, "No questions are available for this level.")
        run = conn.execute("""INSERT INTO aa.level_runs(player_id,level_id,questions_total,scoring_version)
            VALUES (%s,%s,%s,%s) RETURNING *""", (who["id"], level_id, len(questions), telemetry_version)).fetchone()
        # A run's ordinals are its own order, 1 to n, since a drawn run skips some of the bank.
        for position, question in enumerate(questions, 1):
            public, solution = snapshot(question)
            conn.execute("""INSERT INTO aa.run_questions
                (run_id,question_id,ordinal,public_question,solution,explanation,points)
                VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                (run["id"], question["id"], position, Jsonb(public), Jsonb(solution),
                 question["explanation"], question["points"]))
        return run_view(conn, run)


def played_this_session(conn, player_id: UUID, level_id: int) -> tuple[dict, set]:
    """How many times the player has played each of a level's questions since they last signed
    in (every run that hadn't ended before the sign-in counts), and the questions of their latest
    run of the level. Signing in again starts the count over."""
    played = {row["question_id"]: row["plays"] for row in conn.execute("""
        SELECT rq.question_id, count(*) AS plays FROM aa.run_questions rq
        JOIN aa.level_runs r ON r.id=rq.run_id JOIN aa.players p ON p.id=r.player_id
        WHERE r.player_id=%s AND r.level_id=%s
          AND (r.ended_at IS NULL OR r.ended_at >= COALESCE(p.signed_in_at, '-infinity'))
        GROUP BY rq.question_id""", (player_id, level_id)).fetchall()}
    last = {row["question_id"] for row in conn.execute("""
        SELECT question_id FROM aa.run_questions WHERE run_id=(
            SELECT id FROM aa.level_runs WHERE player_id=%s AND level_id=%s ORDER BY started_at DESC LIMIT 1)""",
        (player_id, level_id)).fetchall()}
    return played, last


def draw(level: dict, questions: list[dict], played: dict | None = None, last: set | frozenset = frozenset()) -> list[dict]:
    """The questions a new run plays. Without a draw rule that is every active question, in
    order. A rule lists pools in order; each pool gives all its questions, or `take` of them, kept
    in ordinal order. A pool that takes some picks the ones the player has played least this
    session (`played` counts plays by question ID), so nothing comes back until the player has
    played the whole pool; then a new round starts. Ties avoid the player's previous run (`last`),
    so a new round doesn't open with the question the last one ended on, and then fall at random."""
    if not level.get("draw"):
        return questions
    played = played or {}
    chance = secrets.SystemRandom()
    picked = []
    for slot in level["draw"]:
        pool = [question for question in questions if question["pool"] == slot["pool"]]
        take = min(slot.get("take", len(pool)), len(pool))
        ranked = sorted(pool, key=lambda question: (played.get(question["id"], 0), question["id"] in last, chance.random()))
        chosen = {question["id"] for question in ranked[:take]}
        picked += [question for question in pool if question["id"] in chosen]
    return picked


def owned_run(conn, who: dict, run_id: UUID) -> dict:
    run = conn.execute("SELECT * FROM aa.level_runs WHERE id=%s AND player_id=%s FOR UPDATE",
                       (run_id, who["id"])).fetchone()
    if not run:
        raise HTTPException(404, "Run not found.")
    return run


def attempt(onyen: str, run_id: UUID, question_id: UUID, request_id: UUID,
            response: dict, elapsed_ms: int) -> dict:
    with connect() as conn:
        who = player(conn, onyen)
        run = owned_run(conn, who, run_id)
        question = conn.execute("SELECT * FROM aa.run_questions WHERE run_id=%s AND question_id=%s",
                                (run_id, question_id)).fetchone()
        if not question:
            raise HTTPException(404, "Question does not belong to this run.")
        previous = conn.execute("SELECT * FROM aa.question_attempts WHERE run_id=%s AND request_id=%s",
                                (run_id, request_id)).fetchone()
        if previous:
            if previous["question_id"] != question_id or previous["response"] != response:
                raise HTTPException(409, "A retry must contain the same answer.")
            return outcome(conn, question, previous)
        if run["outcome"] != "in_progress":
            raise HTTPException(409, "This run has already finished.")
        if question_id in progress(conn, run_id)["solved"]:
            stats = question_stats(conn, run_id)[str(question_id)]
            return {"is_correct": True, "explanation": question["explanation"],
                    "stars": stats["stars"], "question_stats": stats}
        history = conn.execute("""SELECT count(*) AS attempts,coalesce(bool_or(is_correct),false) AS solved_before
            FROM aa.question_attempts WHERE run_id=%s AND question_id=%s""", (run_id, question_id)).fetchone()
        if history["attempts"] >= 1000:
            raise HTTPException(429, "Too many attempts on this question.")
        correct = grade(question["public_question"], question["solution"], response)
        # A gate reopened by a setback can be solved again, but it earns its points only once.
        row = conn.execute("""INSERT INTO aa.question_attempts
            (run_id,player_id,question_id,attempt_no,response,is_correct,elapsed_ms,points_awarded,request_id)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id,question_id,is_correct""",
            (run_id, who["id"], question_id, history["attempts"] + 1, Jsonb(response), correct,
             min(elapsed_ms, 3600000), question["points"] if correct and not history["solved_before"] else 0,
             request_id)).fetchone()
        if not correct and question["public_question"]["type"] == "puzzle":
            strike(conn, run_id, question_id, row["id"])
        return outcome(conn, question, row)


def strike(conn, run_id: UUID, question_id: UUID, attempt_id: UUID) -> None:
    """A gate's third strike reopens the gate before it, or restarts a gate with none before it."""
    state = progress(conn, run_id)
    if state["strikes"][question_id] < STRIKES:
        return
    at = state["order"].index(question_id)
    before = state["order"][at - 1] if at else None
    target = before if before in state["solved"] and state["types"][before] == "puzzle" else question_id
    conn.execute("INSERT INTO aa.run_setbacks(run_id,question_id,caused_by_attempt_id) VALUES (%s,%s,%s)",
                 (run_id, target, attempt_id))


def outcome(conn, question: dict, attempted: dict) -> dict:
    """The graded result; puzzle gates also report strikes and any setback the attempt caused."""
    stats = question_stats(conn, question["run_id"])[str(attempted["question_id"])]
    result = {"is_correct": attempted["is_correct"], "explanation": question["explanation"],
              "stars": stats["stars"], "question_stats": stats}
    if question["public_question"]["type"] != "puzzle":
        return result
    setback = conn.execute("SELECT question_id FROM aa.run_setbacks WHERE caused_by_attempt_id=%s",
                           (attempted["id"],)).fetchone()
    result["setback_question_id"] = setback["question_id"] if setback else None
    if setback:
        result["strikes"] = STRIKES
    elif attempted["is_correct"]:
        result["strikes"] = 0
    else:
        result["strikes"] = progress(conn, question["run_id"])["strikes"][attempted["question_id"]]
    return result


def finish_run(onyen: str, run_id: UUID) -> dict:
    with connect() as conn:
        who = player(conn, onyen)
        run = owned_run(conn, who, run_id)
        if run["outcome"] == "in_progress":
            solved = progress(conn, run_id)["solved"]
            if not run["questions_total"] or len(solved) != run["questions_total"]:
                raise HTTPException(409, "Answer every question correctly before finishing.")
            score = conn.execute("SELECT coalesce(sum(points_awarded),0) AS score FROM aa.question_attempts WHERE run_id=%s",
                                 (run_id,)).fetchone()["score"]
            stats = question_stats(conn, run_id)
            stars = sum(row["stars"] or 0 for row in stats.values())
            mistakes = sum(row["mistakes"] for row in stats.values())
            conn.execute("""UPDATE aa.level_runs SET outcome='completed',passed=true,ended_at=now(),
                questions_correct=%s,score=%s,stars_total=%s,mistakes_total=%s WHERE id=%s""",
                (len(solved), score, stars, mistakes, run_id))
            run["stars_total"], run["mistakes_total"] = stars, mistakes
            conn.execute("""INSERT INTO aa.player_badges(player_id,badge_id,awarded_run_id)
                SELECT %s,id,%s FROM aa.badges WHERE level_id=%s AND is_active
                ON CONFLICT (player_id,badge_id) DO NOTHING""", (who["id"], run_id, run["level_id"]))
        elif not run["passed"]:
            raise HTTPException(409, "This run cannot be completed.")
        return {"passed": True, "stars": run["stars_total"], "mistakes": run["mistakes_total"],
                "max_stars": run["questions_total"] * 3, "leaderboard_eligible": run["scoring_version"] == 1,
                **profile(conn, who["id"])}


def reopen(onyen: str, run_id: UUID, question_id: UUID) -> dict:
    """Go back to a gate that is already open: it closes and has to be opened again before the
    run can finish. It is recorded like a setback, without the failed attempt that causes one, so
    strikes at the gate start again from zero and its earlier answers still count toward its best
    stars. Asking again while the gate is closed changes nothing."""
    with connect() as conn:
        who = player(conn, onyen)
        run = owned_run(conn, who, run_id)
        if run["outcome"] != "in_progress":
            raise HTTPException(409, "This run has already finished.")
        state = progress(conn, run_id)
        if question_id not in state["order"]:
            raise HTTPException(404, "Question does not belong to this run.")
        if question_id in state["solved"]:
            conn.execute("INSERT INTO aa.run_setbacks(run_id,question_id) VALUES (%s,%s)", (run_id, question_id))
        return run_view(conn, run)


def reference_answer(conn, question_id: UUID) -> dict | None:
    """One winning answer for a question, in the form the game submits it. It is read from the
    bank, never from a run's snapshot, so it stays out of everything the game is sent up front."""
    return conn.execute("SELECT answer FROM aa.questions WHERE id=%s", (question_id,)).fetchone()["answer"]


def learning_event(onyen: str, run_id: UUID, question_id: UUID, request_id: UUID,
                   kind: str, moment: int | None = None, choice: int | None = None) -> dict:
    """Record a hint, a shown answer, or a walkthrough decision without adding gameplay strikes.
    An "answer" event also returns the gate's reference answer; the gate then earns one star."""
    with connect() as conn:
        who = player(conn, onyen)
        run = owned_run(conn, who, run_id)
        question = conn.execute("SELECT public_question FROM aa.run_questions WHERE run_id=%s AND question_id=%s",
                                (run_id, question_id)).fetchone()
        if not question:
            raise HTTPException(404, "Question does not belong to this run.")
        shown = {"answer": reference_answer(conn, question_id)} if kind == "answer" else {}
        previous = conn.execute("SELECT * FROM aa.question_events WHERE run_id=%s AND request_id=%s",
                                (run_id, request_id)).fetchone()
        if previous:
            if any(previous[key] != value for key, value in
                   (("question_id", question_id), ("kind", kind), ("moment", moment), ("choice", choice))):
                raise HTTPException(409, "A retry must contain the same learning event.")
            return {"is_correct": previous["is_correct"],
                    "question_stats": question_stats(conn, run_id)[str(question_id)], **shown}
        if run["outcome"] != "in_progress":
            raise HTTPException(409, "This run has already finished.")
        if question_id in progress(conn, run_id)["solved"]:
            raise HTTPException(409, "This question is already solved.")
        count = conn.execute("SELECT count(*) AS n FROM aa.question_events WHERE run_id=%s AND question_id=%s",
                             (run_id, question_id)).fetchone()["n"]
        if count >= 1000:
            raise HTTPException(429, "Too many learning events on this question.")
        public = question["public_question"]
        correct = None
        if kind == "hint":
            if moment is not None or choice is not None or not public.get("hint"):
                raise HTTPException(422, "This hint event is not valid for this question.")
        elif kind == "answer":
            if moment is not None or choice is not None or not shown["answer"]:
                raise HTTPException(422, "This question has no answer to show.")
        elif kind == "walk_choice":
            payload = public.get("payload", {})
            if payload.get("kind") != "walk":
                raise HTTPException(422, "This question has no walkthrough decisions.")
            entries = moments(payload)
            if (type(moment) is not int or not 0 <= moment < len(entries)
                    or type(choice) is not int or not 0 <= choice < len(entries[moment]["options"])):
                raise HTTPException(422, "Choose a valid option at this walkthrough's moment.")
            correct = bool(entries[moment]["options"][choice]["good"])
        else:
            raise HTTPException(422, "Unknown learning event.")
        conn.execute("""INSERT INTO aa.question_events
            (run_id,question_id,player_id,request_id,kind,moment,choice,is_correct)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
            (run_id, question_id, who["id"], request_id, kind, moment, choice, correct))
        return {"is_correct": correct, "question_stats": question_stats(conn, run_id)[str(question_id)], **shown}
