"""Level 3 (the Call Stack Tower): the machine, grading, and every room's design; needs no database."""

from copy import deepcopy
from itertools import permutations
import json
from pathlib import Path
import unittest

from fastapi import HTTPException

from server.call_stack import (CHOMPER, CODE_BASE, JUNK, STACK_TOP, assemble, audit, chain, frame_lines, junk,
                               restored, run, setup)
from server.grading import snapshot
from server.puzzles import MASK, execute, grade_puzzle, parse_line, reg

BANK = json.loads((Path(__file__).parents[1] / "levels/level_3/guest_rooms.json").read_text())
ROOMS = BANK["rooms"]
ROOM = {room["ordinal"]: room["payload"] for room in ROOMS}
# One winning answer per Level 3 room, by ordinal (db/migrations/0009_level3_call_stack_tower.sql):
# a frame layout from sp+0 up, the typed values, or a verdict.
SOLUTIONS = {
    1: {"frame": ["ra"]},
    2: {"values": [9, 4, 1]},
    3: {"line": 0x100, "clause": "callee-save"},
    4: {"frame": ["s0", "ra"]},
    5: {"frame": ["a0", "ra"]},
    6: {"frame": ["s1", "s0", "ra"]},
    7: {"frame": ["ra"]},
    8: {"frame": []},
    9: {"values": [24, 6, 2, 1]},
    10: {"values": [12, 18, 12, 6, 6, 6, 6]},
    11: {"values": [0x110, 0x13C, 0x13C, 0x13C]},
    12: {"values": [5, 4, 3, 2]},
    13: {"line": 0x100, "clause": "save-ra"},
    14: {"line": 0x118, "clause": "caller-save"},
    15: {"line": 0x128, "clause": "restore-sp"},
    16: {"line": 0x120, "clause": "callee-save"},
    17: {"frame": ["s0", "ra"]},
}
# How each Code Lawyer room's program is put right: its broken lines, replaced. The repaired
# program must pass the Chomper's audit, which shows the verdict named the real problem.
REPAIRS = {
    3: {"add s1, a0, a0": ["add t1, a0, a0"], "add a0, s1, x0": ["add a0, t1, x0"]},
    13: {"jal ra, inc": ["addi sp, sp, -4", "sw ra, 0(sp)", "jal ra, inc"],
         "jr ra": ["lw ra, 0(sp)", "addi sp, sp, 4", "jr ra"]},
    14: {"add t0, x0, a0": ["addi sp, sp, -4", "sw a0, 0(sp)"],
         "mul a0, a0, t0": ["lw t0, 0(sp)", "addi sp, sp, 4", "mul a0, a0, t0"]},
    15: {"addi sp, sp, 4": ["addi sp, sp, 8"]},
    16: {"addi sp, sp, -8": ["addi sp, sp, -12", "sw s1, 8(sp)"],
         "addi sp, sp, 8": ["lw s1, 8(sp)", "addi sp, sp, 12"]},
}

# The lines each verdict accepts, by text, so a moved line can't silently change the answer.
NAMED = {3: {"add s1, a0, a0"}, 13: {"jal ra, inc"}, 14: {"jal ra, fact", "mul a0, a0, t0"}, 15: {"addi sp, sp, 4"},
         16: {"add s1, x0, a0"}}


def answer(ordinal):
    return SOLUTIONS[ordinal]


def repaired(payload, fixes):
    """The payload with each broken line replaced. A line that appears more than once is replaced
    where it first appears (and only once) unless it is a return, which is replaced at the
    function's own return (its first one)."""
    payload = deepcopy(payload)
    done = set()
    code = []
    for entry in payload["code"]:
        line = entry.get("line")
        if line in fixes and line not in done:
            done.add(line)
            code += [{"line": text} for text in fixes[line]]
        else:
            code.append(entry)
    payload["code"] = code
    return payload


def machine(lines, calls, entry="f", **extra):
    payload = {"kind": "frame", "entry": entry, "code": [{"label": entry}] + [{"line": line} for line in lines],
               "calls": calls, "blocks": [], "max_slots": 0}
    payload.update(extra)
    return payload


class MachineTests(unittest.TestCase):
    def test_multiply_and_divide_follow_rv32m(self):
        negative = lambda n: n & MASK  # noqa: E731
        self.assertEqual(execute("mul", negative(-3), 4), negative(-12))
        self.assertEqual(execute("mul", 0x10000, 0x10000), 0)  # The low 32 bits.
        self.assertEqual(execute("div", 7, negative(-2)), negative(-3))  # Rounds toward zero.
        self.assertEqual(execute("rem", negative(-7), 2), negative(-1))  # Takes the dividend's sign.
        self.assertEqual((execute("div", 5, 0), execute("rem", 5, 0)), (MASK, 5))
        self.assertEqual((execute("div", 0x80000000, MASK), execute("rem", 0x80000000, MASK)), (0x80000000, 0))

    def test_the_forms_the_lectures_write(self):
        ret = {"op": "jalr", "rd": 0, "imm": 0, "rs1": reg("ra")}
        self.assertEqual(parse_line("ret"), ret)
        self.assertEqual(parse_line("jr ra"), ret)
        self.assertEqual(parse_line("jalr x0, 0(ra)"), ret)
        self.assertEqual(parse_line("lw ra, (sp)"), parse_line("lw ra, 0(sp)"))

    def test_a_frame_writes_the_lecture_prologue_and_epilogue(self):
        self.assertEqual(frame_lines(["s0", "ra"]), (["addi sp, sp, -8", "sw ra, 4(sp)", "sw s0, 0(sp)"],
                                                     ["lw s0, 0(sp)", "lw ra, 4(sp)", "addi sp, sp, 8"]))
        # An argument saved for the code to read back isn't restored: a0 carries the result.
        self.assertEqual(frame_lines(["a0", "ra"])[1], ["lw ra, 4(sp)", "addi sp, sp, 8"])
        self.assertEqual(frame_lines([]), ([], []))
        self.assertEqual([restored(name) for name in ("ra", "s0", "s11", "a0", "t0", "sp")],
                         [True, True, True, False, False, False])

    def test_the_chomper_leaves_junk_and_its_own_return_address(self):
        payload = machine(["ret"], [{"args": {"a0": 7}}, {"args": {}}])
        regs, memory = setup(payload, 1)
        self.assertEqual((regs[reg("ra")], regs[reg("sp")], regs[0]), (CHOMPER, STACK_TOP, 0))
        self.assertEqual(regs[reg("s0")], junk(1, 8))
        self.assertNotEqual(setup(payload, 0)[0][reg("s0")], regs[reg("s0")])
        self.assertEqual(setup(payload, 0)[0][reg("a0")], 7)
        self.assertEqual((memory[STACK_TOP - 4], len(memory)), (JUNK, 32))

    def test_calls_record_entry_values_and_returns(self):
        payload = ROOM[11]
        floors = chain(payload)
        self.assertEqual([(floor["a0"], floor["ra"], floor["ret"]) for floor in floors],
                         [(4, 0x110, 16), (3, 0x13C, 9), (2, 0x13C, 4), (1, 0x13C, 1)])
        self.assertEqual([floor["depth"] for floor in floors], [2, 3, 4, 5])  # main is depth 1.

    def test_crashes_are_named(self):
        cases = {
            "memory": ["sw ra, 0(sp)"],  # The word at sp is above the stack.
            "aligned": ["sw ra, -2(sp)"],
            "code": ["jalr x0, 8(ra)"],  # 0x408: nowhere.
            "loop": ["j f"],
        }
        for kind, lines in cases.items():
            with self.subTest(kind=kind):
                payload = machine(lines, [{"args": {}}])
                state = run(payload, *assemble(payload), 0)
                self.assertEqual(state["fault"]["kind"], kind)

    def test_the_heap_eats_the_stack_from_the_bottom_up(self):
        payload = machine(["addi t0, x0, 0", "addi t0, x0, 0", "sw ra, -4(sp)", "ret"], [{"args": {}}],
                          stack_words=1, chomper={"start": 2, "every": 1})
        state = run(payload, *assemble(payload), 0)
        self.assertEqual(state["fault"], {"kind": "overflow", "at": STACK_TOP - 4})


class GradingTests(unittest.TestCase):
    def test_every_reference_answer_passes(self):
        for ordinal, response in SOLUTIONS.items():
            with self.subTest(room=ordinal):
                self.assertTrue(grade_puzzle(ROOM[ordinal], response))

    def test_wrong_answers_fail(self):
        self.assertFalse(grade_puzzle(ROOM[1], {"frame": []}))  # ra lost: plus1 never returns.
        self.assertFalse(grade_puzzle(ROOM[4], {"frame": ["ra"]}))  # s0 clobbered.
        self.assertFalse(grade_puzzle(ROOM[5], {"frame": ["ra", "a0"]}))  # lw t1, 0(sp) reads ra.
        self.assertFalse(grade_puzzle(ROOM[9], {"values": [24, 6, 2, 2]}))
        self.assertFalse(grade_puzzle(ROOM[3], {"line": 0x100, "clause": "caller-save"}))  # Right line, wrong rule.
        self.assertFalse(grade_puzzle(ROOM[3], {"line": 0x104, "clause": "callee-save"}))  # Wrong line.
        self.assertTrue(grade_puzzle(ROOM[14], {"line": 0x11C, "clause": "caller-save"}))  # Either named line.

    def test_rejects_malformed_answers(self):
        cases = [
            (1, {"frame": ["sp"]}), (1, {"frame": ["ra", "ra"]}), (1, {"frame": "ra"}), (1, {"frame": [1]}),
            (1, {"frame": ["ra"], "extra": 1}), (6, {"frame": ["ra", "s0", "s1", "a0", "t0", "ra"]}),
            (2, {"values": [9, 4]}), (2, {"values": [9, 4, "1"]}), (2, {"values": [9, 4, True]}), (2, {"frame": []}),
            (3, {"line": 0x102, "clause": "callee-save"}), (3, {"line": 0x10C, "clause": "callee-save"}),
            (3, {"line": 0x100, "clause": "be-nice"}), (3, {"line": 0x100}), (3, {"line": "0x100", "clause": "save-ra"}),
        ]
        for ordinal, response in cases:
            with self.subTest(response=response), self.assertRaises(HTTPException) as caught:
                grade_puzzle(ROOM[ordinal], response)
            self.assertEqual(caught.exception.status_code, 422)

    def test_snapshots_keep_the_verdict_private(self):
        question = {"id": "q", "type": "puzzle", "prompt": "p", "code_snippet": None, "hint": None, "payload": ROOM[3]}
        public, solution = snapshot(question)
        self.assertNotIn("verdict", public["payload"])
        self.assertEqual(solution["puzzle"]["verdict"], ROOM[3]["verdict"])
        self.assertIn("calls", public["payload"])


class RoomDesignTests(unittest.TestCase):
    """Each room teaches what it says: par is the smallest working frame, elevator answers match the
    functions in C, every verdict names the real crime, and the finale needs a tight frame."""

    def test_the_bank_and_its_draw(self):
        self.assertEqual([room["ordinal"] for room in ROOMS], list(range(1, len(ROOMS) + 1)))
        pools = {}
        for room in ROOMS:
            pools.setdefault(room["pool"], []).append(room["ordinal"])
        self.assertEqual([slot["pool"] for slot in BANK["draw"]], list(pools))
        self.assertEqual(sum(slot.get("take", len(pools[slot["pool"]])) for slot in BANK["draw"]), 10)
        self.assertEqual([ROOM[n]["kind"] for n in pools["tutorial"]], ["frame", "elevator", "lawyer"])
        for room in ROOMS:
            self.assertTrue(room["prompt"] and room["code_snippet"] and room["hint"] and room["explanation"])

    def test_par_is_the_smallest_frame_that_works(self):
        for room in ROOMS:
            payload = room["payload"]
            if payload["kind"] != "frame":
                continue
            with self.subTest(room=room["ordinal"]):
                working = [list(layout) for size in range(payload["max_slots"] + 1)
                           for layout in permutations(payload["blocks"], size)
                           if all(row["passed"] for row in audit(payload, layout))]
                self.assertEqual(min(len(layout) for layout in working), payload["par"])
                self.assertIn(SOLUTIONS[room["ordinal"]]["frame"], working)

    def test_the_finale_needs_a_tight_frame(self):
        finale = ROOM[17]
        free = dict(finale, stack_words=64)
        del free["chomper"]
        for size in range(2, len(finale["blocks"]) + 1):
            for layout in permutations(finale["blocks"], size):
                if all(row["passed"] for row in audit(free, layout)):
                    rows = audit(finale, layout)
                    with self.subTest(layout=layout):
                        if size == 2:
                            self.assertTrue(all(row["passed"] for row in rows))
                        else:
                            self.assertIn(["overflow"], [row["problems"] for row in rows])

    def test_elevator_answers_match_the_c(self):
        def sqr(x):
            return x if x < 2 else sqr(x - 1) + x + x - 1

        def fact(x):
            return x if x <= 1 else x * fact(x - 1)

        def gcd(a, b):
            return a if a == b else gcd(a - b, b) if a > b else gcd(a, b - a)

        self.assertEqual(SOLUTIONS[2]["values"], [sqr(3), sqr(2), sqr(1)])
        self.assertEqual(SOLUTIONS[9]["values"], [fact(4), fact(3), fact(2), fact(1)])
        self.assertEqual(SOLUTIONS[10]["values"][-1], gcd(30, 18))
        for room in ROOMS:
            payload = room["payload"]
            if payload["kind"] == "elevator":
                with self.subTest(room=room["ordinal"]):
                    floors = chain(payload)
                    self.assertEqual(len(floors), payload["floors"])
                    self.assertTrue(all("ret" in floor for floor in floors))
                    self.assertTrue(all(0 <= floor < len(floors) for floor, _ in payload["blanks"]))

    def test_every_verdict_names_the_real_crime(self):
        for room in ROOMS:
            payload = room["payload"]
            if payload["kind"] != "lawyer":
                continue
            with self.subTest(room=room["ordinal"]):
                lines, _ = assemble(payload)
                self.assertFalse(all(row["passed"] for row in audit(payload)), "the crime shows in the audit")
                fixed = repaired(payload, REPAIRS[room["ordinal"]])
                self.assertTrue(all(row["passed"] for row in audit(fixed)), "the repaired program passes")
                named = {lines[(address - CODE_BASE) // 4] for address in payload["verdict"]["lines"]}
                self.assertEqual(named, NAMED[room["ordinal"]])


if __name__ == "__main__":
    unittest.main()
