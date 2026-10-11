"""Level 3 (the Call Stack Tower): the machine, grading, and every walkthrough's design; needs no
database."""

import json
from pathlib import Path
import unittest

from fastapi import HTTPException

from server.call_stack import (CHOMPER, CODE_BASE, JUNK, STACK_TOP, assemble, audit, frame_lines, junk, moments,
                               restored, run, setup)
from server.grading import snapshot
from server.puzzles import MASK, execute, grade_puzzle, parse_line, reg

BANK = json.loads((Path(__file__).parents[1] / "levels/level_3/guest_rooms.json").read_text())
ROOMS = BANK["rooms"]
ROOM = {room["ordinal"]: room["payload"] for room in ROOMS}
# One winning answer per Level 3 walkthrough, by ordinal (db/migrations/0012_level3_walkthroughs.sql):
# the option picked at each moment.
SOLUTIONS = {1: {"choices": [0]}, 2: {"choices": [0]}, 3: {"choices": [1]}, 4: {"choices": [0]},
             5: {"choices": [0]}, 6: {"choices": [0]}, 7: {"choices": [0]}, 8: {"choices": [0]}}
# Runs started before the walkthroughs keep snapshots of three earlier kinds of room (0009), which
# are still graded: one room of each, as 0009 inserted it.
EARLIER = {
    "frame": {"kind": "frame", "entry": "plus1",
              "code": [{"label": "plus1"}, {"prologue": True}, {"line": "jal ra, triple"}, {"line": "addi a0, a0, 1"},
                       {"epilogue": True}, {"line": "jr ra"}, {"label": "triple"}, {"line": "slli t0, a0, 1"},
                       {"line": "add a0, a0, t0"}, {"line": "jr ra"}],
              "blocks": ["ra", "s0", "a0"], "max_slots": 3, "par": 1,
              "calls": [{"args": {"a0": 4}, "expect": 13}, {"args": {"a0": -2}, "expect": -5},
                        {"args": {"a0": 7}, "expect": 22}]},
    "elevator": {"kind": "elevator", "entry": "sqr", "function": "sqr",
                 "code": [{"label": "sqr"}] + [{"line": line} for line in (
                     "addi sp, sp, -8", "sw ra, 4(sp)", "sw s0, 0(sp)", "slti t0, a0, 2", "bne t0, x0, done",
                     "add s0, x0, a0", "addi a0, a0, -1", "jal ra, sqr", "add a0, a0, s0", "add a0, a0, s0",
                     "addi a0, a0, -1")] + [{"label": "done"}] + [{"line": line} for line in (
                     "lw s0, 0(sp)", "lw ra, 4(sp)", "addi sp, sp, 8", "jalr x0, 0(ra)")],
                 "calls": [{"args": {"a0": 3}, "expect": 9}], "params": ["a0"], "columns": ["ret"], "floors": 3,
                 "blanks": [[0, "ret"], [1, "ret"], [2, "ret"]]},
    "lawyer": {"kind": "lawyer", "entry": "double",
               "code": [{"label": "double"}, {"line": "add s1, a0, a0"}, {"line": "add a0, s1, x0"}, {"line": "ret"}],
               "calls": [{"args": {"a0": 5}, "expect": 10}],
               "clauses": ["caller-save", "callee-save", "save-ra", "restore-sp"],
               "verdict": {"lines": [256], "clause": "callee-save"}},
}


def good_choices(payload):
    """The first good option at each of a walkthrough's moments."""
    return [next(k for k, option in enumerate(entry["options"]) if option["good"]) for entry in moments(payload)]


def passes(payload, choices):
    return all(row["passed"] for row in audit(payload, choices=choices))


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
        payload = ROOM[5]  # sqr(3), with ra and s0 saved.
        lines, labels = assemble(payload, choices=[0])
        calls = run(payload, lines, labels, 0)["calls"]
        back = CODE_BASE + 4 * lines.index("jal ra, sqr") + 4
        self.assertEqual([(call["a0"], call["ra"], call["ret"]) for call in calls],
                         [(3, CHOMPER, 9), (2, back, 4), (1, back, 1)])
        self.assertEqual([call["depth"] for call in calls], [1, 2, 3])

    def test_a_walkthrough_writes_each_move_where_it_stands(self):
        plus1, plus2 = ROOM[1], ROOM[2]
        self.assertNotIn("jal ra, triple", assemble(plus1)[0])  # The move isn't made yet.
        lines, _ = assemble(plus1, choices=[0])
        self.assertEqual(lines[:3], ["addi sp, sp, -4", "sw ra, 0(sp)", "jal ra, triple"])
        self.assertEqual(assemble(plus1, choices=[1])[0][2], "j triple")
        # A frame move writes its prologue at the moment and its epilogue at the epilogue mark.
        lines, labels = assemble(plus2, choices=[0])
        self.assertEqual(lines[:2], ["addi sp, sp, -4", "sw ra, 0(sp)"])
        self.assertEqual(lines[labels["inc"] // 4 - CODE_BASE // 4 - 3:labels["inc"] // 4 - CODE_BASE // 4],
                         ["lw ra, 0(sp)", "addi sp, sp, 4", "jr ra"])
        self.assertEqual(assemble(plus2, choices=[1])[0][:2], ["jal ra, inc", "jal ra, inc"])

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

    def test_wrong_moves_fail(self):
        for ordinal, payload in ROOM.items():
            for m, entry in enumerate(moments(payload)):
                for k, option in enumerate(entry["options"]):
                    choices = good_choices(payload)
                    choices[m] = k
                    with self.subTest(room=ordinal, option=option["label"]):
                        self.assertEqual(grade_puzzle(payload, {"choices": choices}), option["good"])

    def test_rejects_malformed_answers(self):
        for response in ({"choices": []}, {"choices": [0, 0]}, {"choices": [5]}, {"choices": [-1]},
                         {"choices": ["0"]}, {"choices": [True]}, {"choices": 0}, {"choices": [0], "extra": 1}, {}):
            with self.subTest(response=response), self.assertRaises(HTTPException) as caught:
                grade_puzzle(ROOM[1], response)
            self.assertEqual(caught.exception.status_code, 422)

    def test_runs_started_earlier_still_grade(self):
        frame, elevator, lawyer = EARLIER["frame"], EARLIER["elevator"], EARLIER["lawyer"]
        self.assertTrue(grade_puzzle(frame, {"frame": ["ra"]}))
        self.assertFalse(grade_puzzle(frame, {"frame": []}))  # ra lost: plus1 never returns.
        self.assertTrue(grade_puzzle(elevator, {"values": [9, 4, 1]}))
        self.assertFalse(grade_puzzle(elevator, {"values": [9, 4, 2]}))
        self.assertTrue(grade_puzzle(lawyer, {"line": 0x100, "clause": "callee-save"}))
        self.assertFalse(grade_puzzle(lawyer, {"line": 0x100, "clause": "caller-save"}))  # Right line, wrong rule.
        self.assertFalse(grade_puzzle(lawyer, {"line": 0x104, "clause": "callee-save"}))  # Wrong line.
        for payload, response in ((frame, {"frame": ["sp"]}), (frame, {"frame": ["ra", "ra"]}),
                                  (elevator, {"values": [9, 4]}), (elevator, {"values": [9, 4, "1"]}),
                                  (lawyer, {"line": 0x102, "clause": "callee-save"}),
                                  (lawyer, {"line": 0x100, "clause": "be-nice"})):
            with self.subTest(response=response), self.assertRaises(HTTPException) as caught:
                grade_puzzle(payload, response)
            self.assertEqual(caught.exception.status_code, 422)

    def test_snapshots_keep_a_verdict_private(self):
        question = {"id": "q", "type": "puzzle", "prompt": "p", "code_snippet": None, "hint": None,
                    "payload": EARLIER["lawyer"]}
        public, solution = snapshot(question)
        self.assertNotIn("verdict", public["payload"])
        self.assertEqual(solution["puzzle"]["verdict"], EARLIER["lawyer"]["verdict"])
        self.assertIn("calls", public["payload"])


class RoomDesignTests(unittest.TestCase):
    """Each walkthrough teaches what it says: its good moves keep the contract, every wrong move
    breaks it (so playing it out shows something real), and every room stays short enough to follow."""

    def test_the_story_plays_in_order(self):
        self.assertNotIn("draw", BANK)
        self.assertEqual([room["ordinal"] for room in ROOMS], list(range(1, 9)))
        for room in ROOMS:
            payload = room["payload"]
            with self.subTest(room=room["ordinal"]):
                self.assertEqual(payload["kind"], "walk")
                goal, _, detail = room["prompt"].partition("\n")
                self.assertTrue(goal and detail and room["code_snippet"] and room["hint"] and room["explanation"])
                self.assertTrue(payload["intro"])
                self.assertTrue(1 <= len(payload["watch"]) <= 4)
                self.assertTrue(all(name in ("a0", "ra", "sp", "t0", "s0", "s1") for name in payload["watch"]))

    def test_every_move_is_marked_by_what_it_does(self):
        for ordinal, payload in ROOM.items():
            for m, entry in enumerate(moments(payload)):
                with self.subTest(room=ordinal, moment=m):
                    self.assertTrue(entry["ask"])
                    self.assertTrue(2 <= len(entry["options"]) <= 3)
                    self.assertTrue(any(option["good"] for option in entry["options"]))
                    for k, option in enumerate(entry["options"]):
                        self.assertTrue(option["label"] and option["why"])
                        choices = good_choices(payload)
                        choices[m] = k
                        self.assertEqual(passes(payload, choices), option["good"], option["label"])

    def test_each_move_waits_where_it_stands_and_walks_stay_short(self):
        for ordinal, payload in ROOM.items():
            with self.subTest(room=ordinal):
                # A line between moments: each stops the walk at its own address.
                kinds = "".join("m" if "moment" in entry else "l" if "line" in entry else "" for entry in payload["code"])
                self.assertNotIn("mm", kinds)
                self.assertFalse(kinds.endswith("m"))
                lines, labels = assemble(payload, choices=good_choices(payload))
                self.assertLessEqual(run(payload, lines, labels, 0)["steps"], 80)

    def test_every_working_frame_wins_the_finale(self):
        finale = ROOM[8]
        self.assertIn("chomper", finale)
        options = moments(finale)[0]["options"]
        self.assertEqual([option["frame"] for option in options if option["good"] and not option.get("loose")],
                         [["s0", "ra"]])
        self.assertTrue(any(option.get("loose") and option["good"] for option in options))
        free = dict(finale, stack_words=64)
        del free["chomper"]
        for k, option in enumerate(options):
            with self.subTest(option=option["label"]):
                self.assertEqual(passes(finale, [k]), passes(free, [k]))


if __name__ == "__main__":
    unittest.main()
