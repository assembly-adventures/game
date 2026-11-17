"""Write the SQL for a migration from a level's room file.

Every level's rooms live in two places that must match: the database, which signed-in runs read,
and levels/level_<n>/guest_rooms.json, which guest mode reads. A gameplay test compares them. So
author a room in the JSON file first, check it with the puzzle tests, then let this tool write the
rows for a new migration:

    python tools/rooms.py insert 2 17 18       # INSERT rooms 17 and 18 of Level 2
    python tools/rooms.py insert 4             # INSERT every room of Level 4
    python tools/rooms.py retire 2 3 11        # retire the active rooms 3 and 11 of Level 2
    python tools/rooms.py answers 1            # UPDATE every Level 1 room's reference answer

Paste the output between BEGIN; and COMMIT; in a new, uniquely numbered file in db/migrations/.
To replace a room, retire it and insert its replacement at the same ordinal in the same migration.
docs/adding-content.md walks through the whole job.
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).parents[1]
COLUMNS = "level_id, type, ordinal, pool, prompt, code_snippet, hint, explanation, difficulty, payload, answer"


def text(value) -> str:
    """A value as a SQL literal: NULL, a number, or a quoted string (JSON for lists and objects)."""
    if value is None:
        return "NULL"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(value)
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False)
    return "'" + value.replace("'", "''") + "'"


def rooms(level: int, ordinals: list[int]) -> list[dict]:
    bank = json.loads((ROOT / f"levels/level_{level}/guest_rooms.json").read_text())
    by_ordinal = {room["ordinal"]: room for room in bank["rooms"]}
    missing = [ordinal for ordinal in ordinals if ordinal not in by_ordinal]
    if missing:
        raise SystemExit(f"Level {level} has no room {missing} in its guest_rooms.json.")
    return [by_ordinal[ordinal] for ordinal in ordinals or sorted(by_ordinal)]


def insert(level: int, ordinals: list[int], difficulty: int | None) -> str:
    rows = []
    for room in rooms(level, ordinals):
        values = [level, "puzzle", room["ordinal"], room.get("pool"), room["prompt"], room.get("code_snippet"),
                  room["hint"], room["explanation"], difficulty, room["payload"], room["answer"]]
        rows.append("(" + ",\n ".join([", ".join(text(value) for value in values[:4])]
                                      + [text(value) for value in values[4:]]) + ")")
    return f"INSERT INTO aa.questions ({COLUMNS}) VALUES\n" + ",\n".join(rows) + ";"


def retire(level: int, ordinals: list[int]) -> str:
    chosen = ", ".join(str(ordinal) for ordinal in ordinals)
    return ("UPDATE aa.questions SET is_active = false, retired_at = now()\n"
            f"    WHERE level_id = {level} AND is_active" + (f" AND ordinal IN ({chosen});" if ordinals else ";"))


def answers(level: int, ordinals: list[int]) -> str:
    return "\n".join(f"UPDATE aa.questions SET answer = {text(room['answer'])} "
                     f"WHERE level_id = {level} AND ordinal = {room['ordinal']} AND is_active;"
                     for room in rooms(level, ordinals))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("command", choices=["insert", "retire", "answers"])
    parser.add_argument("level", type=int)
    parser.add_argument("ordinals", type=int, nargs="*", help="rooms by ordinal; all of the level's rooms if none")
    parser.add_argument("--difficulty", type=int, help="1 to 5, for inserted rooms")
    args = parser.parse_args()
    if args.command == "insert":
        print(insert(args.level, args.ordinals, args.difficulty))
    elif args.command == "retire":
        print(retire(args.level, args.ordinals))
    else:
        print(answers(args.level, args.ordinals))
