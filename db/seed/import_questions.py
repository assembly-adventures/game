#!/usr/bin/env python3
"""One-time bootstrap: convert questions.json into seed SQL for aa.questions.

The database is the source of truth for questions. questions.json is a
temporary file that predates it, and this script exists to carry those 18
existing questions across once. After the bootstrap, questions are authored in
the database and this script and questions.json can both be retired.

Usage:
    python3 db/seed/import_questions.py                 # writes db/seed/0003_questions.sql
    python3 db/seed/import_questions.py --check         # validate only, write nothing

Emits SQL rather than talking to Postgres, so the import needs no database
driver and the generated file can be reviewed in a diff before it is applied.
Output is deterministic: the same questions.json always produces the same SQL.

What it fixes on the way through, all documented in Docs/schema.md:
  * the "drap-and-drop" key typo becomes the drag_and_drop question type
  * stray trailing ']' characters in option text are stripped
  * stable ids are generated for options, tiles and match pairs, so grading
    compares ids instead of answer text
  * matching's positional fixed[i]/answer[i] convention becomes explicit pairs
  * where a RISC-V listing sits at the end of a prompt it moves to code_snippet

Questions whose code is interleaved with prose are left alone and reported as
warnings for manual editing — a heuristic that guessed there would be wrong.
"""

from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "questions.json"
OUTPUT = REPO_ROOT / "db" / "seed" / "0003_questions.sql"

# questions.json keys its levels by slug; aa.levels keys by smallint id.
LEVEL_IDS = {
    "level_1": 1,
    "level_2": 2,
    "level_3": 3,
    "level_4": 4,
    "level_5": 5,
    "level_6": 6,
    "level_challenge": 7,
}

# The bank's type keys, including the misspelling, mapped to the DB enum.
TYPE_KEYS = {
    "multiple-choice": "multiple_choice",
    "drap-and-drop": "drag_and_drop",   # typo preserved here so the input still parses
    "drag-and-drop": "drag_and_drop",
    "matching": "matching",
}

# Ordering of types within a level, which determines question ordinals.
TYPE_ORDER = ["multiple_choice", "drag_and_drop", "matching"]

# RISC-V mnemonics appearing in the bank, plus the ones most likely to be added.
MNEMONICS = {
    "add", "addi", "sub", "and", "andi", "or", "ori", "xor", "xori",
    "sll", "slli", "srl", "srli", "sra", "srai",
    "slt", "slti", "sltu", "sltiu",
    "lw", "lh", "lb", "lbu", "lhu", "sw", "sh", "sb",
    "beq", "bne", "blt", "bge", "bltu", "bgeu",
    "jal", "jalr", "lui", "auipc", "ecall", "ebreak", "nop", "li", "mv", "ret",
}

LABEL_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*:\s*$")

warnings: list[str] = []


def looks_like_code(line: str) -> bool:
    """True if the line reads as a RISC-V instruction or a branch label."""
    stripped = line.strip()
    if not stripped:
        return False
    if LABEL_RE.match(stripped):
        return True
    # "loop: add x6, x6, x5" — a label sharing a line with an instruction.
    body = stripped.split(":", 1)[1] if LABEL_RE.match(stripped.split(":", 1)[0] + ":") else stripped
    return body.strip().split()[0].lower().rstrip(",") in MNEMONICS if body.strip() else False


def split_code(text: str, where: str) -> tuple[str, str | None]:
    """Split a trailing block of assembly out of a prompt.

    Only splits when the code lines are contiguous AND run to the end of the
    text. Interleaved code (prose, code, more prose) is left in the prompt and
    reported, because moving it would silently reorder the question.
    """
    lines = text.split("\n")
    flags = [looks_like_code(line) for line in lines]
    if not any(flags):
        return text, None

    first_code = flags.index(True)
    # Contiguous from first_code to the end?
    if all(flags[first_code:]) and first_code > 0:
        prompt = "\n".join(lines[:first_code]).strip()
        code = "\n".join(lines[first_code:]).rstrip()
        return prompt, code

    warnings.append(
        f"{where}: code is interleaved with prose, left in the prompt for manual review\n"
        f"    {text!r}"
    )
    return text, None


def clean_option(text: str) -> str:
    """Strip the stray trailing ']' typos present in two level_1 options."""
    cleaned = text.strip()
    if cleaned.endswith("]") and "[" not in cleaned:
        cleaned = cleaned[:-1].rstrip()
    return cleaned


def sql_str(value: str | None) -> str:
    if value is None:
        return "NULL"
    return "'" + value.replace("'", "''") + "'"


def sql_json(value: dict) -> str:
    return sql_str(json.dumps(value, ensure_ascii=False, sort_keys=True)) + "::jsonb"


def build_multiple_choice(raw: dict, where: str) -> tuple[dict, str, str | None, str | None]:
    options = [clean_option(o) for o in raw["options"]]
    answers = [clean_option(a) for a in raw["answer"]]

    ids = [f"o{i + 1}" for i in range(len(options))]
    by_text: dict[str, str] = {}
    for oid, text in zip(ids, options):
        if text in by_text:
            warnings.append(f"{where}: duplicate option text {text!r}")
        by_text[text] = oid

    correct_ids = []
    for answer in answers:
        if answer not in by_text:
            raise ValueError(
                f"{where}: answer {answer!r} does not match any option. "
                f"Options: {options}"
            )
        correct_ids.append(by_text[answer])

    prompt, code = split_code(raw["question"], where)
    payload = {
        "multi_select": len(correct_ids) > 1,
        "options": [{"id": oid, "text": text} for oid, text in zip(ids, options)],
        "correct_option_ids": correct_ids,
    }
    return payload, prompt, code, raw.get("explanation")


def build_drag_and_drop(raw: dict, where: str, seed: int) -> tuple[dict, str, str | None, None]:
    # The bank derives the tiles from the answer, so answer order IS the solution.
    steps = [s.strip() for s in raw["answer"]]
    ids = [f"t{i + 1}" for i in range(len(steps))]

    # Present the tiles in a scrambled order so the stored payload does not read
    # as the solution top to bottom. The API must still shuffle per run; this
    # only keeps the seed file from being a giveaway.
    order = list(range(len(steps)))
    random.Random(seed).shuffle(order)

    payload = {
        "orientation": raw.get("orientation", "vertical"),
        "tiles": [{"id": ids[i], "text": steps[i]} for i in order],
        "correct_order": ids,
    }
    prompt, code = split_code(raw["question"], where)
    return payload, prompt, code, None


def build_matching(raw: dict, where: str) -> tuple[dict, str, str | None, None]:
    fixed = raw["fixed"]
    answer = raw["answer"]
    if len(fixed) != len(answer):
        raise ValueError(
            f"{where}: matching has {len(fixed)} fixed items but {len(answer)} answers"
        )
    payload = {
        "columns": raw["columns"],
        "pairs": [
            {"id": f"p{i + 1}", "left": left.strip(), "right": right.strip()}
            for i, (left, right) in enumerate(zip(fixed, answer))
        ],
        "distractors": [],
    }
    prompt, code = split_code(raw["question"], where)
    return payload, prompt, code, None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="validate the bank without writing SQL")
    args = parser.parse_args()

    bank = json.loads(SOURCE.read_text())

    rows: list[str] = []
    counts: dict[str, int] = {}

    for level_slug in sorted(bank, key=lambda s: LEVEL_IDS.get(s, 99)):
        if level_slug not in LEVEL_IDS:
            raise ValueError(f"unknown level key {level_slug!r} in questions.json")
        level_id = LEVEL_IDS[level_slug]
        level = bank[level_slug]
        ordinal = 0

        grouped: dict[str, list[dict]] = {}
        for raw_key, entries in level.get("questions", {}).items():
            if raw_key not in TYPE_KEYS:
                raise ValueError(f"{level_slug}: unknown question type key {raw_key!r}")
            grouped.setdefault(TYPE_KEYS[raw_key], []).extend(entries)

        for qtype in TYPE_ORDER:
            for index, raw in enumerate(grouped.get(qtype, [])):
                ordinal += 1
                where = f"{level_slug}/{qtype}[{index}]"

                if qtype == "multiple_choice":
                    payload, prompt, code, explanation = build_multiple_choice(raw, where)
                elif qtype == "drag_and_drop":
                    payload, prompt, code, explanation = build_drag_and_drop(
                        raw, where, seed=level_id * 100 + index)
                else:
                    payload, prompt, code, explanation = build_matching(raw, where)

                rows.append(
                    "    ({level_id}, '{qtype}', {ordinal}, {prompt}, {code}, "
                    "{explanation}, {payload})".format(
                        level_id=level_id,
                        qtype=qtype,
                        ordinal=ordinal,
                        prompt=sql_str(prompt),
                        code=sql_str(code),
                        explanation=sql_str(explanation),
                        payload=sql_json(payload),
                    )
                )
                counts[f"{level_slug}.{qtype}"] = counts.get(f"{level_slug}.{qtype}", 0) + 1

    for line in warnings:
        print(f"warning: {line}", file=sys.stderr)

    print(f"{len(rows)} questions parsed from {SOURCE.name}:")
    for key in sorted(counts):
        print(f"  {key}: {counts[key]}")
    if warnings:
        print(f"{len(warnings)} question(s) need a manual code_snippet split.")

    if args.check:
        return 0

    sql = "\n".join([
        "-- Assembly Adventures — initial question bank",
        "--",
        "-- GENERATED FILE, one-time bootstrap. Regenerate with:",
        "--     python3 db/seed/import_questions.py",
        "--",
        "-- Apply after 0002_levels_badges.sql:",
        '--     psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/seed/0003_questions.sql',
        "--",
        "-- This carries the questions that predate the database across once. After",
        "-- that the database is the source of truth: author questions there, and",
        "-- retire old ones with is_active = false rather than re-running this file",
        "-- (see Docs/schema.md). The DELETE below refuses to touch any question that",
        "-- already has attempts, so a re-run after launch fails loudly on the unique",
        "-- index instead of destroying history.",
        "",
        "BEGIN;",
        "",
        "DELETE FROM aa.questions WHERE NOT EXISTS (",
        "    SELECT 1 FROM aa.question_attempts a WHERE a.question_id = aa.questions.id);",
        "",
        "INSERT INTO aa.questions",
        "    (level_id, type, ordinal, prompt, code_snippet, explanation, payload)",
        "VALUES",
        ",\n".join(rows) + ";",
        "",
        "COMMIT;",
        "",
    ])
    OUTPUT.write_text(sql)
    print(f"wrote {OUTPUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
