"""Staff reporting, player nicknames and visibility preferences, and weekly level standings."""

from collections import Counter
from datetime import datetime, time, timedelta, timezone
import json
import os
import re
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from psycopg.errors import UniqueViolation

from .call_stack import moments
from .database import connect
from .puzzles import REGISTERS

COURSE_TIMEZONE = ZoneInfo("America/New_York")
# A player's name on the leaderboard (SQL on aa.players p): their nickname, or "Player <number>"
# until they pick one. Nobody can pick a name of that form, so no two entries share a name.
BOARD_NAME = "coalesce(p.nickname,('Player '||p.player_number)::citext)"
NICKNAME = re.compile(r"[A-Za-z0-9 _-]{3,20}")
RESERVED = re.compile(r"player[ _-]*\d+", re.IGNORECASE)


def is_staff(onyen: str) -> bool:
    return onyen.casefold() in {name.strip().casefold()
                               for name in os.environ.get("AA_STAFF_ONYENS", "").split(",") if name.strip()}


def require_staff(onyen: str) -> None:
    if not is_staff(onyen):
        raise HTTPException(403, "This page is available to course TAs and professors only.")


def _player(conn, onyen: str) -> dict:
    who = conn.execute("SELECT id,onyen,leaderboard_visible FROM aa.players WHERE onyen=%s", (onyen,)).fetchone()
    if not who:
        raise HTTPException(401, "Please sign in again to create your saved profile.")
    return who


def preferences(onyen: str, leaderboard_visible: bool) -> dict:
    with connect() as conn:
        who = _player(conn, onyen)
        conn.execute("UPDATE aa.players SET leaderboard_visible=%s WHERE id=%s", (leaderboard_visible, who["id"]))
    return {"leaderboard_visible": leaderboard_visible}


def nickname_text(text: str) -> str | None:
    """The nickname to save, with spacing tidied, or None for a blank one, which goes back to Player <number>."""
    name = " ".join(text.split())
    if not name:
        return None
    if not NICKNAME.fullmatch(name) or not any(c.isalnum() for c in name):
        raise HTTPException(422, "A nickname is 3 to 20 letters, numbers, spaces, hyphens, or underscores.")
    if RESERVED.fullmatch(name):
        raise HTTPException(422, "Names like Player 12 belong to players without a nickname. Try another.")
    return name


def names(conn, player_id: UUID) -> dict:
    row = conn.execute(f"SELECT p.nickname,{BOARD_NAME} AS leaderboard_name FROM aa.players p WHERE p.id=%s",
                       (player_id,)).fetchone()
    return {"nickname": None if row["nickname"] is None else str(row["nickname"]),
            "leaderboard_name": str(row["leaderboard_name"])}


def set_nickname(onyen: str, text: str) -> dict:
    name = nickname_text(text)
    taken = HTTPException(409, "That nickname is taken. Try another.")
    with connect() as conn:
        who = _player(conn, onyen)
        # Another player's Onyen counts as taken, so nobody can pose as a classmate.
        if name and conn.execute("SELECT 1 FROM aa.players WHERE (nickname=%s OR onyen=%s) AND id<>%s",
                                 (name, name, who["id"])).fetchone():
            raise taken
        try:
            conn.execute("UPDATE aa.players SET nickname=%s WHERE id=%s", (name, who["id"]))
        except UniqueViolation:
            raise taken from None  # Someone saved the same nickname a moment earlier.
        return names(conn, who["id"])


def weekly_window(week_offset: int = 0, now: datetime | None = None) -> tuple[datetime, datetime]:
    """Calendar weeks, including the 167/169-hour weeks around Eastern DST changes."""
    today = (now or datetime.now(timezone.utc)).astimezone(COURSE_TIMEZONE).date()
    monday = today - timedelta(days=today.weekday()) + timedelta(weeks=week_offset)
    start = datetime.combine(monday, time.min, tzinfo=COURSE_TIMEZONE)
    return start, datetime.combine(monday + timedelta(days=7), time.min, tzinfo=COURSE_TIMEZONE)


def leaderboard(onyen: str, level_id: int, week_offset: int = 0) -> dict:
    start, end = weekly_window(week_offset)
    with connect() as conn:
        who = _player(conn, onyen)
        level = conn.execute("SELECT id,name FROM aa.levels WHERE id=%s AND is_active", (level_id,)).fetchone()
        if not level:
            raise HTTPException(404, "This level is not available yet.")
        rows = conn.execute(f"""WITH ranked_runs AS (
                SELECT r.player_id,{BOARD_NAME} AS name,p.leaderboard_visible,r.stars_total AS stars,
                    r.questions_total*3 AS max_stars,r.mistakes_total AS mistakes,
                    row_number() OVER (PARTITION BY r.player_id
                        ORDER BY r.stars_total DESC,r.mistakes_total,r.ended_at,r.id) AS best
                FROM aa.level_runs r JOIN aa.players p ON p.id=r.player_id
                WHERE r.level_id=%s AND r.passed AND r.scoring_version=1
                    AND r.stars_total IS NOT NULL AND r.mistakes_total IS NOT NULL
                    AND r.ended_at >= %s AND r.ended_at < %s
            ) SELECT player_id,name,leaderboard_visible,stars,max_stars,mistakes FROM ranked_runs
                WHERE best=1 ORDER BY stars DESC,mistakes,name""", (level_id, start, end)).fetchall()
        entries, mine = [], None
        previous_score, rank = None, 0
        for row in rows:
            entry = {key: row[key] for key in ("name", "stars", "max_stars", "mistakes")}
            entry["name"] = str(entry["name"])
            entry["is_me"] = row["player_id"] == who["id"]
            entry["rank"] = None
            if row["leaderboard_visible"]:
                score = row["stars"], row["mistakes"]
                if score != previous_score:
                    rank = len(entries) + 1
                    previous_score = score
                entry["rank"] = rank
                entries.append(entry)
            if entry["is_me"]:
                mine = entry
        return {"level_id": level_id, "level_name": level["name"], "week_offset": week_offset,
                "week_start": start.date().isoformat(), "week_end": end.date().isoformat(),
                "week_label": f"{start:%b %d} – {end - timedelta(days=1):%b %d, %Y}",
                "starts_at": start.isoformat(), "ends_at": end.isoformat(), "timezone": COURSE_TIMEZONE.key,
                "leaderboard_visible": who["leaderboard_visible"], "entries": entries, "my_entry": mine}


# A walkthrough's successful intermediate choices do not count as completed
# question attempts. Its wrong decisions do: the final submitted answer alone
# would otherwise incorrectly report first-try success. Old walkthrough runs
# lack those decisions and are excluded from the first-try denominator.
ACTIVITY = """
    activity AS (
        SELECT a.id,a.run_id,a.player_id,a.question_id,a.response,a.is_correct,a.answered_at AS at,
            'attempt'::text AS kind,
            NOT (coalesce(rq.public_question->'payload'->>'kind','')='walk' AND r.scoring_version=0) AS reliable
        FROM aa.question_attempts a JOIN aa.level_runs r ON r.id=a.run_id
        JOIN aa.run_questions rq ON rq.run_id=a.run_id AND rq.question_id=a.question_id
        UNION ALL
        SELECT e.id,e.run_id,e.player_id,e.question_id,
            jsonb_build_object('moment',e.moment,'choice',e.choice),false,e.created_at,'walk_choice',true
        FROM aa.question_events e WHERE e.kind='walk_choice' AND NOT e.is_correct
    ), ordered_activity AS (
        SELECT a.*,row_number() OVER (PARTITION BY player_id,question_id ORDER BY at,id) AS seq
        FROM activity a
    ), student_questions AS (
        SELECT player_id,question_id,count(*) AS attempts,count(*) FILTER (WHERE NOT is_correct) AS mistakes,
            bool_or(is_correct) AS solved,min(seq) FILTER (WHERE is_correct) AS attempts_to_solve,
            bool_or(is_correct) FILTER (WHERE seq=1) AS first_correct,
            bool_or(reliable) FILTER (WHERE seq=1) AS first_reliable
        FROM ordered_activity GROUP BY player_id,question_id
    )
"""

QUESTION_METRICS = """
    count(s.player_id) AS distinct_players,coalesce(sum(s.attempts),0)::int AS total_attempts,
    coalesce(sum(s.mistakes),0)::int AS mistakes,
    count(s.player_id) FILTER (WHERE s.first_reliable) AS first_try_sample_size,
    (avg(s.first_correct::int) FILTER (WHERE s.first_reliable))::double precision AS first_try_correct_rate,
    avg(s.solved::int)::double precision AS eventual_correct_rate,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY s.attempts_to_solve) AS median_attempts
"""


def instruction(button: dict) -> str:
    """A Level 1 button, written the way the game labels it (asm in puzzle_room.gd)."""
    if "rs2" in button:
        last = REGISTERS[button["rs2"]]
    elif button["op"] in ("andi", "ori", "xori"):
        last = f"0x{button['imm']:02X}"
    else:
        last = str(button["imm"])
    return f"{button['op']} {REGISTERS[button['rd']]}, {REGISTERS[button['rs1']]}, {last}"


def answer_text(kind: str, question_type: str, payload: dict, response: dict) -> list[str]:
    """A recorded answer as the lines the student saw. Option IDs are random in every run and
    puzzle answers are indexes, so both are read through that run's own snapshot. An answer this
    cannot read, such as one from a retired room, is shown as it was recorded."""
    try:
        if kind == "walk_choice":
            option = moments(payload)[response["moment"]]["options"][response["choice"]]
            return [f"Move {response['moment'] + 1}: {option['label']}"]
        if question_type == "multiple_choice":
            options = {item["id"]: item["text"] for item in payload["options"]}
            return sorted(options[choice] for choice in response["selected_option_ids"])
        if question_type == "drag_and_drop":
            tiles = {item["id"]: item["text"] for item in payload["tiles"]}
            return [f"{n}. {tiles[tile]}" for n, tile in enumerate(response["order"], 1)]
        if question_type == "matching":
            choices = {item["id"]: item["text"] for item in payload["choices"]}
            return [f"{row['text']} → {choices[response['pairs'][row['id']]]}" for row in payload["rows"]]
        if payload["kind"] == "moves":
            return [instruction(payload["buttons"][move]) for move in response["moves"]]
        if payload["kind"] == "maze":
            return [str(line) for line in response["program"]]
        if payload["kind"] == "code":
            return [f"Blank {n}: {line}" for n, line in enumerate(response["blanks"], 1)]
        if payload["kind"] == "walk":
            return [f"Move {n}: {entry['options'][choice]['label']}"
                    for n, (entry, choice) in enumerate(zip(moments(payload), response["choices"]), 1)]
    except (KeyError, IndexError, TypeError, ValueError):
        pass
    return [json.dumps(response, sort_keys=True)]


def _questions(conn, level_id: int | None = None, question_id: UUID | None = None) -> list[dict]:
    filters, values = [], []
    if level_id is not None:
        filters.append("q.level_id=%s")
        values.append(level_id)
    if question_id is not None:
        filters.append("q.id=%s")
        values.append(question_id)
    where = "WHERE " + " AND ".join(filters) if filters else ""
    return conn.execute(f"""WITH {ACTIVITY}
        SELECT q.id,q.level_id,q.ordinal,q.type,q.prompt,q.code_snippet,q.is_active,{QUESTION_METRICS}
        FROM aa.questions q LEFT JOIN student_questions s ON s.question_id=q.id
        {where} GROUP BY q.id ORDER BY q.level_id,q.ordinal,q.created_at""", values).fetchall()


def _levels(conn) -> list[dict]:
    return conn.execute(f"""WITH {ACTIVITY}, level_metrics AS (
            SELECT q.level_id,sum(s.attempts)::int AS attempts,
                count(*) FILTER (WHERE s.first_reliable) AS first_try_sample_size,
                (avg(s.first_correct::int) FILTER (WHERE s.first_reliable))::double precision AS first_try_correct_rate,
                percentile_cont(0.5) WITHIN GROUP (ORDER BY s.attempts_to_solve) AS median_attempts
            FROM student_questions s JOIN aa.questions q ON q.id=s.question_id GROUP BY q.level_id
        ), runs AS (
            SELECT level_id,count(DISTINCT player_id) AS started_players,
                count(DISTINCT player_id) FILTER (WHERE passed) AS completed_players,
                count(*) FILTER (WHERE passed) AS completed_runs
            FROM aa.level_runs GROUP BY level_id
        ) SELECT l.id,l.name,l.is_active,coalesce(r.started_players,0) AS started_players,
            coalesce(r.completed_players,0) AS completed_players,coalesce(r.completed_runs,0) AS completed_runs,
            coalesce(m.attempts,0) AS attempts,m.first_try_correct_rate,m.median_attempts,
            coalesce(m.first_try_sample_size,0) AS first_try_sample_size
        FROM aa.levels l LEFT JOIN runs r ON r.level_id=l.id LEFT JOIN level_metrics m ON m.level_id=l.id
        WHERE l.is_active ORDER BY l.ordinal""").fetchall()


def overview(onyen: str) -> dict:
    require_staff(onyen)
    with connect() as conn:
        summary = conn.execute("""SELECT count(*) AS players,
            count(*) FILTER (WHERE last_seen_at >= now()-interval '7 days') AS active_players,
            (SELECT count(*) FROM aa.level_runs WHERE passed) AS completed_runs,
            (SELECT count(*) FROM aa.question_attempts) +
                (SELECT count(*) FROM aa.question_events WHERE kind='walk_choice' AND NOT is_correct) AS attempts
            FROM aa.players""").fetchone()
        return {"summary": summary, "levels": _levels(conn)}


def level_detail(onyen: str, level_id: int) -> dict:
    require_staff(onyen)
    with connect() as conn:
        level = next((row for row in _levels(conn) if row["id"] == level_id), None)
        if not level:
            raise HTTPException(404, "Level not found.")
        return {"level": level, "questions": _questions(conn, level_id=level_id)}


def question_detail(onyen: str, question_id: UUID) -> dict:
    require_staff(onyen)
    with connect() as conn:
        questions = _questions(conn, question_id=question_id)
        if not questions:
            raise HTTPException(404, "Question not found.")
        stats = questions[0]
        question = {key: stats[key] for key in ("id", "level_id", "ordinal", "type", "prompt", "code_snippet",
                                                "is_active")}
        # Group by what students saw, not the recorded IDs, which differ in every run. Runs that
        # share a snapshot (every run of a puzzle version) are read together.
        snapshots = conn.execute(f"""WITH {ACTIVITY}
            SELECT rq.public_question->>'type' AS type,rq.public_question->'payload' AS payload,
                jsonb_agg(jsonb_build_array(a.response,a.is_correct,a.kind)) AS answers
            FROM activity a JOIN aa.run_questions rq ON rq.run_id=a.run_id AND rq.question_id=a.question_id
            WHERE a.question_id=%s GROUP BY 1,2""", (question_id,)).fetchall()
        counts = Counter((tuple(answer_text(kind, row["type"], row["payload"], response)), correct, kind)
                         for row in snapshots for response, correct, kind in row["answers"])
        common = [{"answer": list(answer), "is_correct": correct, "kind": kind, "count": count}
                  for (answer, correct, kind), count in
                  sorted(counts.items(), key=lambda item: (-item[1], item[0][1], item[0]))[:25]]
        students = conn.execute(f"""WITH {ACTIVITY}
            SELECT p.id,p.onyen,s.attempts,s.solved,s.mistakes,s.attempts_to_solve
            FROM student_questions s JOIN aa.players p ON p.id=s.player_id WHERE s.question_id=%s
            ORDER BY s.mistakes DESC,p.onyen LIMIT 200""", (question_id,)).fetchall()
        return {"question": question, "stats": stats, "common_answers": common, "students": students,
                "students_total": stats["distinct_players"]}


def students(onyen: str, q: str = "", limit: int = 100, offset: int = 0) -> dict:
    require_staff(onyen)
    # Literal substring search: %, _ and backslash in input are not wildcard syntax.
    search = "%" + q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
    # Staff can also find a student by the name the leaderboard shows.
    match = f"p.onyen ILIKE %(search)s OR {BOARD_NAME} ILIKE %(search)s"
    with connect() as conn:
        total = conn.execute(f"SELECT count(*) AS n FROM aa.players p WHERE {match}", {"search": search}).fetchone()["n"]
        rows = conn.execute(f"""SELECT p.id,p.onyen,{BOARD_NAME} AS leaderboard_name,p.last_seen_at,
            (SELECT count(DISTINCT r.level_id) FROM aa.level_runs r WHERE r.player_id=p.id AND r.passed) AS levels_completed,
            (SELECT count(*) FROM aa.question_attempts a WHERE a.player_id=p.id) +
                (SELECT count(*) FROM aa.question_events e WHERE e.player_id=p.id AND e.kind='walk_choice'
                    AND NOT e.is_correct) AS attempts
            FROM aa.players p WHERE {match} ORDER BY p.onyen LIMIT %(limit)s OFFSET %(offset)s""",
                            {"search": search, "limit": limit, "offset": offset}).fetchall()
        return {"students": rows, "total": total, "limit": limit, "offset": offset}


def student_detail(onyen: str, student_id: UUID) -> dict:
    require_staff(onyen)
    with connect() as conn:
        student = conn.execute(f"""SELECT p.id,p.onyen,p.last_seen_at,p.leaderboard_visible,p.nickname,
            {BOARD_NAME} AS leaderboard_name FROM aa.players p WHERE p.id=%s""", (student_id,)).fetchone()
        if not student:
            raise HTTPException(404, "Student not found.")
        runs = conn.execute("""SELECT r.id,r.level_id,l.name AS level_name,r.outcome,r.started_at,r.ended_at,
            CASE WHEN r.scoring_version=1 THEN r.stars_total END AS stars,r.questions_total,r.scoring_version,
            CASE WHEN r.scoring_version=1 THEN coalesce(r.mistakes_total,
                (SELECT count(*) FROM aa.question_attempts a WHERE a.run_id=r.id AND NOT a.is_correct) +
                (SELECT count(*) FROM aa.question_events e WHERE e.run_id=r.id AND e.kind='walk_choice'
                    AND NOT e.is_correct)) END AS mistakes,
            CASE WHEN r.outcome='in_progress' THEN
                (SELECT count(*) FROM aa.run_questions rq WHERE rq.run_id=r.id AND EXISTS (
                    SELECT 1 FROM aa.question_attempts a WHERE a.run_id=r.id AND a.question_id=rq.question_id
                    AND a.is_correct AND a.answered_at > coalesce((SELECT max(s.created_at) FROM aa.run_setbacks s
                        WHERE s.run_id=r.id AND s.question_id=rq.question_id),'-infinity'::timestamptz)))
                ELSE r.questions_correct END AS questions_correct
            FROM aa.level_runs r JOIN aa.levels l ON l.id=r.level_id
            WHERE r.player_id=%s ORDER BY r.started_at DESC,r.id LIMIT 100""", (student_id,)).fetchall()
        attempts = conn.execute(f"""WITH {ACTIVITY}
            SELECT a.question_id,r.level_id,rq.public_question->>'prompt' AS prompt,
                rq.public_question->>'type' AS type,rq.public_question->'payload' AS payload,
                a.response,a.is_correct,a.at AS answered_at,a.kind
            FROM activity a JOIN aa.level_runs r ON r.id=a.run_id
            JOIN aa.run_questions rq ON rq.run_id=a.run_id AND rq.question_id=a.question_id
            WHERE a.player_id=%s ORDER BY a.at DESC,a.id LIMIT 200""", (student_id,)).fetchall()
        for attempt in attempts:
            attempt["answer"] = answer_text(attempt["kind"], attempt["type"], attempt.pop("payload"),
                                            attempt.pop("response"))
        totals = conn.execute(f"""WITH {ACTIVITY} SELECT count(*) AS attempts_total,
            (SELECT count(*) FROM aa.level_runs WHERE player_id=%s) AS runs_total
            FROM activity WHERE player_id=%s""", (student_id, student_id)).fetchone()
        return {"student": student, "runs": runs, "attempts": attempts, **totals,
                "truncated": totals["attempts_total"] > 200 or totals["runs_total"] > 100}


def clear_nickname(onyen: str, student_id: UUID) -> dict:
    """The one change staff can make: an inappropriate nickname goes, and the student is Player <number> again."""
    require_staff(onyen)
    with connect() as conn:
        if not conn.execute("UPDATE aa.players SET nickname=NULL WHERE id=%s", (student_id,)).rowcount:
            raise HTTPException(404, "Student not found.")
        return names(conn, student_id)
