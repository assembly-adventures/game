"""Puzzle simulation, grading, and gate design checks; needs no database."""

from itertools import product
import json
from pathlib import Path
import unittest

from fastapi import HTTPException

from server.puzzles import grade_puzzle, run_program

GATES = json.loads((Path(__file__).parents[1] / "levels/level_1/guest_rooms.json").read_text())


def ins(op, rd, rs1, rs2=None, imm=None):
    return {"op": op, "rd": rd, "rs1": rs1, **({"rs2": rs2} if rs2 is not None else {"imm": imm})}


def matches(gate, moves):
    payload = gate["payload"]
    width = payload["width"]
    regs = run_program([payload["buttons"][move] for move in moves], payload["initial"], width)
    return all(regs[int(name[1:])] == value & ((1 << width) - 1) for name, value in payload["goal"].items())


class InterpreterTests(unittest.TestCase):
    def test_wraps_at_32_bits_and_x0_stays_zero(self):
        regs = run_program([ins("addi", 5, 0, imm=-1), ins("addi", 6, 5, imm=1), ins("addi", 0, 0, imm=7)], {})
        self.assertEqual((regs[5], regs[6], regs[0]), (0xFFFFFFFF, 0, 0))

    def test_arithmetic_vs_logical_right_shift(self):
        regs = run_program([ins("srai", 6, 5, imm=3), ins("srli", 7, 5, imm=3)], {"x5": -64})
        self.assertEqual(regs[6], (-8) & 0xFFFFFFFF)
        self.assertEqual(regs[7], 0xFFFFFFC0 >> 3)

    def test_signed_and_unsigned_comparison(self):
        regs = run_program([ins("slt", 7, 5, 6), ins("sltu", 8, 5, 6), ins("sltiu", 9, 6, imm=-1)],
                           {"x5": -2, "x6": 4})
        self.assertEqual(regs[7:10], [1, 0, 1])

    def test_logical_and_register_shifts(self):
        regs = run_program([ins("xori", 6, 5, imm=0xF), ins("sll", 7, 5, 8), ins("or", 9, 6, 7)],
                           {"x5": 0b1010, "x8": 33})
        self.assertEqual((regs[6], regs[7], regs[9]), (0b0101, 0b10100, 0b10101))

    def test_eight_bit_registers_wrap_and_keep_their_sign(self):
        regs = run_program([ins("addi", 5, 5, imm=64), ins("addi", 5, 5, imm=64), ins("srai", 6, 5, imm=1),
                            ins("srli", 7, 5, imm=1), ins("slli", 8, 5, imm=1), ins("xori", 9, 0, imm=0xFF)], {}, 8)
        self.assertEqual(regs[5:10], [0x80, 0xC0, 0x40, 0x00, 0xFF])


class GradingTests(unittest.TestCase):
    def test_any_order_that_reaches_the_goal_passes(self):
        overflow = GATES[8]["payload"]
        for moves in ([0, 0, 1], [0, 1, 0], [1, 0, 0], [1, 1, 1, 0]):
            self.assertTrue(grade_puzzle(overflow, {"moves": moves}), moves)
        self.assertFalse(grade_puzzle(overflow, {"moves": [1, 1, 1]}))
        keep_sign = GATES[9]["payload"]
        self.assertTrue(grade_puzzle(keep_sign, {"moves": [1, 1, 1]}))
        self.assertFalse(grade_puzzle(keep_sign, {"moves": [0, 0, 0]}))

    def test_registers_other_than_the_goal_are_readable(self):
        self.assertTrue(grade_puzzle(GATES[3]["payload"], {"moves": [0, 1, 0]}))

    def test_rejects_malformed_answers(self):
        payload = GATES[2]["payload"]
        for response in ({"moves": []}, {"moves": [0, 0, 0, 0]}, {"moves": [2]}, {"moves": [-1]},
                         {"moves": [True]}, {"moves": ["0"]}, {"moves": 0}, {"moves": [0], "extra": 1}, {}):
            with self.subTest(response=response), self.assertRaises(HTTPException) as caught:
                grade_puzzle(payload, response)
            self.assertEqual(caught.exception.status_code, 422)

    def test_unknown_puzzle_kinds_are_unsupported(self):
        with self.assertRaises(HTTPException) as caught:
            grade_puzzle({"kind": "bits"}, {"moves": [0]})
        self.assertEqual(caught.exception.status_code, 503)


class GateDesignTests(unittest.TestCase):
    """Every gate must open within its move limit, and par must be the true minimum."""

    def test_every_gate_is_solvable_and_par_is_optimal(self):
        self.assertEqual([gate["ordinal"] for gate in GATES], list(range(1, 11)))
        for gate in GATES:
            payload = gate["payload"]
            with self.subTest(gate=gate["ordinal"]):
                self.assertFalse(matches(gate, []), "the gate starts already open")
                shortest = next((n for n in range(1, payload["max_moves"] + 1)
                                 if any(matches(gate, moves) for moves in product(range(len(payload["buttons"])), repeat=n))),
                                None)
                self.assertEqual(shortest, payload["par"])
                self.assertTrue(gate["prompt"] and gate["hint"] and gate["explanation"])


if __name__ == "__main__":
    unittest.main()
