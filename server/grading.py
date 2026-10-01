"""Prepare answer-free questions and grade opaque response IDs server-side."""

from copy import deepcopy
import secrets
from uuid import uuid4

from fastapi import HTTPException

from .puzzles import grade_puzzle


def snapshot(question: dict) -> tuple[dict, dict]:
    """Randomize option IDs as well as order so t1/t2 never reveals a solution."""
    public = {key: question[key] for key in ("type", "prompt", "code_snippet", "hint")}
    public["id"] = str(question["id"])
    payload = deepcopy(question["payload"])
    kind = question["type"]
    if kind in ("multiple_choice", "drag_and_drop"):
        items_key = "options" if kind == "multiple_choice" else "tiles"
        answer_key = "correct_option_ids" if kind == "multiple_choice" else "correct_order"
        mapping = {item["id"]: uuid4().hex for item in payload[items_key]}
        solution = {"ids": [mapping[identifier] for identifier in payload[answer_key]]}
        items = [{"id": mapping[item["id"]], "text": item["text"]} for item in payload[items_key]]
        secrets.SystemRandom().shuffle(items)
        public["payload"] = {items_key: items}
        if kind == "multiple_choice":
            public["payload"]["multi_select"] = bool(payload.get("multi_select"))
        else:
            public["payload"]["orientation"] = payload["orientation"]
    elif kind == "matching":
        choices = []
        rows = []
        answers = {}
        for pair in payload["pairs"]:
            row_id, choice_id = uuid4().hex, uuid4().hex
            rows.append({"id": row_id, "text": pair["left"]})
            choices.append({"id": choice_id, "text": pair["right"]})
            answers[row_id] = choice_id
        choices.extend({"id": uuid4().hex, "text": text} for text in payload.get("distractors", []))
        secrets.SystemRandom().shuffle(choices)
        public["payload"] = {"rows": rows, "choices": choices, "columns": payload["columns"]}
        solution = {"pairs": answers}
    elif kind == "puzzle":
        # Goals are shown to the player; the server grades by replaying the presses.
        public["payload"] = payload
        solution = {"puzzle": payload}
    else:
        raise HTTPException(503, "This question type is not supported.")
    return public, solution


def grade(public: dict, solution: dict, response: dict) -> bool:
    """Reject malformed or foreign IDs before comparing the submitted answer."""
    kind = public["type"]
    payload = public["payload"]
    if kind == "puzzle":
        return grade_puzzle(solution["puzzle"], response)
    if kind == "matching":
        pairs = response.get("pairs")
        row_ids = {item["id"] for item in payload["rows"]}
        choices = {item["id"] for item in payload["choices"]}
        if (set(response) != {"pairs"} or not isinstance(pairs, dict)
                or set(pairs) != row_ids or any(not isinstance(v, str) or v not in choices for v in pairs.values())
                or len(set(pairs.values())) != len(pairs)):
            raise HTTPException(422, "Match every row to a different available choice.")
        return pairs == solution["pairs"]
    key = "selected_option_ids" if kind == "multiple_choice" else "order"
    items_key = "options" if kind == "multiple_choice" else "tiles"
    selected = response.get(key)
    allowed = {item["id"] for item in payload[items_key]}
    if (set(response) != {key} or not isinstance(selected, list) or not selected
            or any(not isinstance(v, str) or v not in allowed for v in selected)
            or len(set(selected)) != len(selected)):
        raise HTTPException(422, "Use each selected answer ID at most once.")
    if kind == "drag_and_drop":
        if set(selected) != allowed:
            raise HTTPException(422, "Arrange every tile exactly once.")
        return selected == solution["ids"]
    if not payload["multi_select"] and len(selected) != 1:
        raise HTTPException(422, "Choose one answer.")
    return set(selected) == set(solution["ids"])
