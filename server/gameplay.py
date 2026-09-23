"""Transactional level runs, attempt history, and earned badges."""

from uuid import UUID

from fastapi import HTTPException
from psycopg.types.json import Jsonb

from .database import connect
from .grading import grade, snapshot


def register_player(onyen: str, pid: str) -> None:
    """Store verified roster identifiers; identity never comes from gameplay JSON."""
    with connect() as conn:
        conn.execute("""INSERT INTO aa.players(onyen,pid,last_seen_at) VALUES (%s,%s,now())
            ON CONFLICT (onyen) DO UPDATE SET pid=excluded.pid,last_seen_at=now()""", (onyen, pid))


def player(conn, onyen: str) -> dict:
    # Serialize a player's mutations, including concurrent start/retry/finish calls.
    row = conn.execute("SELECT id,onyen FROM aa.players WHERE onyen=%s FOR UPDATE", (onyen,)).fetchone()
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
    with connect() as conn:
        who = player(conn, onyen)
        return {"onyen": str(who["onyen"]), **profile(conn, who["id"])}


def levels(onyen: str) -> list[dict]:
    with connect() as conn:
        who = player(conn, onyen)
        return conn.execute("""SELECT l.id,l.name,l.slug,l.is_active,
            (SELECT count(*) FROM aa.questions q WHERE q.level_id=l.id AND q.is_active) AS question_count,
            EXISTS(SELECT 1 FROM aa.level_runs r WHERE r.player_id=%s AND r.level_id=l.id AND r.passed) AS completed
            FROM aa.levels l ORDER BY l.ordinal""", (who["id"],)).fetchall()


def run_view(conn, run: dict) -> dict:
    rows = conn.execute("SELECT public_question FROM aa.run_questions WHERE run_id=%s ORDER BY ordinal",
                        (run["id"],)).fetchall()
    solved = conn.execute("SELECT DISTINCT question_id FROM aa.question_attempts WHERE run_id=%s AND is_correct",
                          (run["id"],)).fetchall()
    return {"id": run["id"], "level_id": run["level_id"], "outcome": run["outcome"],
            "questions": [row["public_question"] for row in rows],
            "solved_question_ids": [row["question_id"] for row in solved]}


def start_run(onyen: str, level_id: int) -> dict:
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
        questions = conn.execute("SELECT * FROM aa.questions WHERE level_id=%s AND is_active ORDER BY ordinal",
                                 (level_id,)).fetchall()
        if not questions:
            raise HTTPException(409, "No questions are available for this level.")
        run = conn.execute("""INSERT INTO aa.level_runs(player_id,level_id,questions_total)
            VALUES (%s,%s,%s) RETURNING *""", (who["id"], level_id, len(questions))).fetchone()
        for question in questions:
            public, solution = snapshot(question)
            conn.execute("""INSERT INTO aa.run_questions
                (run_id,question_id,ordinal,public_question,solution,explanation,points)
                VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                (run["id"], question["id"], question["ordinal"], Jsonb(public), Jsonb(solution),
                 question["explanation"], question["points"]))
        return run_view(conn, run)


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
            return {"is_correct": previous["is_correct"], "explanation": question["explanation"]}
        if run["outcome"] != "in_progress":
            raise HTTPException(409, "This run has already finished.")
        history = conn.execute("""SELECT count(*) AS attempts,coalesce(bool_or(is_correct),false) AS solved
            FROM aa.question_attempts WHERE run_id=%s AND question_id=%s""", (run_id, question_id)).fetchone()
        if history["solved"]:
            return {"is_correct": True, "explanation": question["explanation"]}
        if history["attempts"] >= 1000:
            raise HTTPException(429, "Too many attempts on this question.")
        correct = grade(question["public_question"], question["solution"], response)
        conn.execute("""INSERT INTO aa.question_attempts
            (run_id,player_id,question_id,attempt_no,response,is_correct,elapsed_ms,points_awarded,request_id)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (run_id, who["id"], question_id, history["attempts"] + 1, Jsonb(response), correct,
             min(elapsed_ms, 3600000), question["points"] if correct else 0, request_id))
        return {"is_correct": correct, "explanation": question["explanation"]}


def finish_run(onyen: str, run_id: UUID) -> dict:
    with connect() as conn:
        who = player(conn, onyen)
        run = owned_run(conn, who, run_id)
        if run["outcome"] == "in_progress":
            summary = conn.execute("""SELECT count(DISTINCT question_id) AS correct,coalesce(sum(points_awarded),0) AS score
                FROM aa.question_attempts WHERE run_id=%s AND is_correct""", (run_id,)).fetchone()
            if not run["questions_total"] or summary["correct"] != run["questions_total"]:
                raise HTTPException(409, "Answer every question correctly before finishing.")
            conn.execute("""UPDATE aa.level_runs SET outcome='completed',passed=true,ended_at=now(),
                questions_correct=%s,score=%s WHERE id=%s""", (summary["correct"], summary["score"], run_id))
            conn.execute("""INSERT INTO aa.player_badges(player_id,badge_id,awarded_run_id)
                SELECT %s,id,%s FROM aa.badges WHERE level_id=%s AND is_active
                ON CONFLICT (player_id,badge_id) DO NOTHING""", (who["id"], run_id, run["level_id"]))
        elif not run["passed"]:
            raise HTTPException(409, "This run cannot be completed.")
        return {"passed": True, **profile(conn, who["id"])}
