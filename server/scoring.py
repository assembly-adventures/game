"""Scores derived from accepted answers and the persistent learning event log."""

from uuid import UUID

from .call_stack import moments


def stars_for(question: dict, response: dict, mistakes: int, hint_used: bool) -> int:
    """Match the room's star rules, using the server's frozen puzzle and answer.

    Mistakes survive retries, reloads and setbacks. Moves/maze rooms use their
    instruction par; code and tower rooms lose a star after a mistake.
    """
    payload = question.get("payload", {})
    kind = payload.get("kind")
    penalty = int(hint_used)
    if kind == "moves":
        penalty += int(len(response["moves"]) > payload["par"])
    elif kind == "maze":
        instructions = sum(line.strip() != "loop:" for line in response["program"])
        penalty += int(instructions > payload["par"])
    else:
        penalty += int(mistakes > 0)
        if kind == "walk":
            penalty += int(any(entry["options"][choice].get("loose", False)
                               for entry, choice in zip(moments(payload), response["choices"])))
    return max(1, 3 - penalty)


def question_stats(conn, run_id: UUID) -> dict[str, dict]:
    questions = conn.execute("SELECT question_id,public_question FROM aa.run_questions WHERE run_id=%s",
                             (run_id,)).fetchall()
    result = {str(row["question_id"]): {"mistakes": 0, "hint_used": False, "stars": None} for row in questions}
    public = {str(row["question_id"]): row["public_question"] for row in questions}
    responses = {}
    for row in conn.execute("""SELECT question_id,response,is_correct FROM aa.question_attempts
            WHERE run_id=%s ORDER BY answered_at,id""", (run_id,)).fetchall():
        key = str(row["question_id"])
        if row["is_correct"]:
            responses[key] = row["response"]
        else:
            result[key]["mistakes"] += 1
    for row in conn.execute("""SELECT question_id,kind,is_correct FROM aa.question_events
            WHERE run_id=%s""", (run_id,)).fetchall():
        stats = result[str(row["question_id"])]
        if row["kind"] == "hint":
            stats["hint_used"] = True
        elif not row["is_correct"]:
            stats["mistakes"] += 1
    for key, response in responses.items():
        stats = result[key]
        stats["stars"] = stars_for(public[key], response, stats["mistakes"], stats["hint_used"])
    return result
