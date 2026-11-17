"""Level 4, the Timing Lab: waveform simulation, table grading, and room design checks; needs no
database."""

import itertools
import json
from pathlib import Path
import re
import unittest

from fastapi import HTTPException

from server.puzzles import grade_puzzle
from server.timing import clock, edges, level, simulate, table_keys, tidy

BANK = json.loads((Path(__file__).parents[1] / "levels/level_4/guest_rooms.json").read_text())
ROOMS = BANK["rooms"]
ROOM = {room["ordinal"]: room["payload"] for room in ROOMS}
# One winning answer per room, by ordinal: the reference answers kept with the rooms (and in
# aa.questions.answer).
SOLUTIONS = {room["ordinal"]: room["answer"] for room in ROOMS}


def wave(gates, signals, ticks=8, **fields):
    return {"kind": "wave", "unit": "ps", "tick": 10, "ticks": ticks, "circuit": {"gates": gates}, "signals": signals,
            "draw": [gates[-1]["out"]], **fields}


def gate(out, op, *inputs, **more):
    return {"out": out, "op": op, "in": list(inputs), **more}


def changes(payload, name):
    """Where a simulated signal starts and each edge after, in the room's own units."""
    signal = simulate(payload)[name]
    return signal[0], [(tick * payload["tick"], value) for tick, value in edges(signal)]



def words(line: str) -> list[str]:
    return line.replace(",", " ").replace("(", " ").replace(")", " ").split()


def operands(line: str) -> list[str]:
    """The registers a line reads, rs1 then rs2. Mirrors PipelineChart.operands."""
    w = words(line)
    if w[0] == "lw":
        return [w[3]]
    if w[0] == "sw":
        return [w[3], w[1]]
    return [x for x in w[1 if w[0].startswith("b") else 2:] if re.fullmatch(r"x\d+", x)]


def target(line: str) -> str:
    w = words(line)
    return "" if w[0] == "sw" or w[0].startswith("b") else w[1]


def stall_plan(stalls: list[int]) -> list[tuple[int, int, int, int]]:
    """Each line's last D, X, M, and W cycle in a stalls diagram, as PipelineChart.schedule lays
    them out: a line decodes once the line ahead has moved into X, and is held there `stalls` more."""
    plan, decode = [], 1
    for row, held in enumerate(stalls):
        if row:
            decode = plan[-1][1]
        plan.append((decode + held, decode + held + 1, decode + held + 2, decode + held + 3))
    return plan


def forwarding(rows: list[str], stalls: list[int]) -> list[list[str | None]]:
    """Each read's mux setting with forwarding: 00 when the register file has the value by decode,
    10 when the writer is in M while the reader is in X (a load's word isn't ready then), 01 when it
    is in W, and None when the value can't arrive in time."""
    plan, result = stall_plan(stalls), []
    for r, line in enumerate(rows):
        codes = []
        for reg in operands(line):
            w = next((w for w in range(r - 1, -1, -1) if target(rows[w]) == reg), None)
            if w is None or plan[r][0] >= plan[w][3]:
                codes.append("00")
            elif plan[r][1] == plan[w][3]:
                codes.append("01")
            elif plan[r][1] == plan[w][2] and not rows[w].startswith("lw"):
                codes.append("10")
            else:
                codes.append(None)
        result.append(codes)
    return result


def arrives(rows: list[str], stalls: list[int], forwarded: bool) -> bool:
    """Whether every value a line reads is there in time: without forwarding, written in W by the
    time the reader decodes."""
    if forwarded:
        return None not in sum(forwarding(rows, stalls), [])
    plan = stall_plan(stalls)
    return all(plan[r][0] >= plan[w][3] for r, line in enumerate(rows) for reg in operands(line)
               for w in [next((w for w in range(r - 1, -1, -1) if target(rows[w]) == reg), None)] if w is not None)

class SimulationTests(unittest.TestCase):
    def test_waveforms_and_clocks_are_one_level_per_tick(self):
        self.assertEqual(level([[0, 1], [2, 0], [5, 1]], 7), [1, 1, 0, 0, 0, 1, 1])
        self.assertEqual(level([[3, 1]], 5), [0, 0, 0, 1, 1])  # A signal is 0 until it is set.
        self.assertEqual(clock({"period": 4, "rise": 2}, 9), [0, 0, 1, 1, 0, 0, 1, 1, 0])

    def test_ideal_gates_follow_their_inputs_at_once(self):
        signals = {"A": [[0, 0], [2, 1]], "B": [[0, 1], [4, 0]]}
        expected = {"and": [0, 0, 1, 1, 0, 0], "or": [1, 1, 1, 1, 1, 1], "xor": [1, 1, 0, 0, 1, 1],
                    "nand": [1, 1, 0, 0, 1, 1], "nor": [0, 0, 0, 0, 0, 0]}
        for op, output in expected.items():
            with self.subTest(op=op):
                self.assertEqual(simulate(wave([gate("Y", op, "A", "B")], signals, 6))["Y"], output)
        self.assertEqual(simulate(wave([gate("Y", "not", "A")], signals, 6))["Y"], [1, 1, 0, 0, 0, 0])

    def test_a_gate_shows_its_inputs_one_delay_ago_and_starts_settled(self):
        payload = wave([gate("C", "not", "A"), gate("Y", "or", "C", "B")], {"A": [[0, 0], [3, 1]], "B": [[0, 0]]},
                       delays={"not": 1, "or": 2})
        self.assertEqual(changes(payload, "C"), (1, [(40, 0)]))
        self.assertEqual(changes(payload, "Y"), (1, [(60, 0)]))  # 10 ps + 20 ps after A rises at 30 ps.

    def test_a_flip_flop_takes_d_at_each_rising_edge_only(self):
        payload = wave([gate("Q", "dff", "D", clk="clk")], {"D": [[0, 1], [3, 0], [5, 1], [6, 0], [9, 1]]}, 16,
                       clock={"name": "clk", "period": 4, "rise": 2})
        # Rising edges at ticks 2, 6, 10, 14: D is 1, then 1 (it falls only at the edge), then 1, 1.
        self.assertEqual(simulate(payload)["Q"], [0, 0] + [1] * 14)
        payload["signals"]["D"] = [[0, 1], [3, 0], [9, 1]]
        self.assertEqual(simulate(payload)["Q"], [0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1])
        self.assertEqual(simulate({**payload, "start": {"Q": 1}})["Q"][:2], [1, 1])

    def test_clk_to_q_delays_the_new_value(self):
        payload = wave([gate("Q", "dff", "D", clk="clk")], {"D": [[0, 1]]}, 8, clock={"name": "clk", "period": 4, "rise": 2},
                       delays={"dff": 1})
        self.assertEqual(simulate(payload)["Q"], [0, 0, 0, 1, 1, 1, 1, 1])


class GradingTests(unittest.TestCase):
    def test_every_reference_answer_passes(self):
        for ordinal, response in SOLUTIONS.items():
            with self.subTest(room=ordinal):
                self.assertTrue(grade_puzzle(ROOM[ordinal], response))

    def test_a_waveform_must_match_tick_for_tick(self):
        right = SOLUTIONS[2]["waves"]
        late = {**right, "Y": [1] + right["Y"][:-1]}  # Every edge one tick late.
        self.assertFalse(grade_puzzle(ROOM[2], {"waves": late}))
        self.assertFalse(grade_puzzle(ROOM[2], {"waves": {**right, "C": [1 - v for v in right["C"]]}}))

    def test_rejects_malformed_waveforms(self):
        right = SOLUTIONS[2]["waves"]
        for waves in ({"C": right["C"]}, {**right, "A": right["C"]}, {**right, "Y": right["Y"][:-1]},
                      {**right, "Y": [2] * 14}, {**right, "Y": [True] * 14}, {**right, "Y": "1" * 14}, []):
            with self.subTest(waves=waves), self.assertRaises(HTTPException) as caught:
                grade_puzzle(ROOM[2], {"waves": waves})
            self.assertEqual(caught.exception.status_code, 422)
        with self.assertRaises(HTTPException):
            grade_puzzle(ROOM[2], {"waves": right, "extra": 1})

    def test_cells_are_read_as_numbers_however_they_are_typed(self):
        self.assertEqual([tidy(text) for text in ("980", " 9,800 ", "0980", "?", "???", "X", "1.20", ".5", "2.0", "1.", "1.2.3")],
                         ["980", "9800", "980", "??", "??", "x", "1.2", "0.5", "2", "1.", "1.2.3"])
        table = {"kind": "table", "rows": [["path", {"blank": "960"}, {"blank": "??"}]], "asks": [{"ask": "n", "blank": "9"}]}
        self.assertEqual(table_keys(table), ["960", "??", "9"])
        self.assertTrue(grade_puzzle(table, {"cells": ["960", "?", " 9"]}))
        self.assertFalse(grade_puzzle(table, {"cells": ["960", "0", "9"]}))
        self.assertFalse(grade_puzzle(table, {"cells": ["??", "960", "9"]}))

    def test_a_pipeline_diagram_is_answered_first(self):
        keys = table_keys(ROOM[8])
        self.assertEqual(keys[:5], ["0", "1", "2", "3", "4"])  # A new instruction is fetched every cycle.
        late = ["0", "2", "3", "4", "5"] + keys[5:]
        self.assertFalse(grade_puzzle(ROOM[8], {"cells": late}))
        # A diagram with hazards is answered with the cycles each line is held in decode.
        stalled = table_keys(ROOM[9])
        self.assertFalse(grade_puzzle(ROOM[9], {"cells": ["0", "0", "1"] + stalled[3:]}))

    def test_rejects_malformed_tables(self):
        keys = table_keys(ROOM[6])
        for cells in (keys[:-1], keys + ["1"], [""] + keys[1:], [960] + keys[1:], ["9" * 17] + keys[1:], "960"):
            with self.subTest(cells=cells), self.assertRaises(HTTPException) as caught:
                grade_puzzle(ROOM[6], {"cells": cells})
            self.assertEqual(caught.exception.status_code, 422)


class RoomDesignTests(unittest.TestCase):
    """The rooms are the lectures' examples: five waveform rooms, then five on pipelining, each
    with the lecture's own answer."""

    def test_the_level_is_half_waveforms_and_half_pipelining(self):
        self.assertNotIn("draw", BANK)
        self.assertEqual([room["ordinal"] for room in ROOMS], list(range(1, 11)))
        self.assertEqual([room["payload"]["kind"] for room in ROOMS], ["wave"] * 5 + ["table"] * 5)
        for room in ROOMS:
            with self.subTest(room=room["ordinal"]):
                goal, _, detail = room["prompt"].partition("\n")
                self.assertTrue(goal and detail and room["hint"] and room["explanation"])

    def test_waveforms_match_the_lecture_slides(self):
        self.assertEqual(changes(ROOM[1], "D"), (0, [(20, 1), (50, 0), (90, 1)]))
        self.assertEqual(changes(ROOM[1], "E"), (0, [(20, 1), (90, 0)]))
        self.assertEqual(changes(ROOM[1], "Y"), (0, [(20, 1)]))
        self.assertEqual(changes(ROOM[2], "C"), (1, [(40, 0)]))
        self.assertEqual(changes(ROOM[2], "Y"), (1, [(60, 0), (110, 1)]))  # 30 ps after A, 20 ps after B.
        self.assertEqual(changes(ROOM[3], "Y"), (1, [(90, 0), (130, 1)]))
        self.assertEqual(changes(ROOM[4], "Q"), (0, [(2, 1), (6, 0), (14, 1), (26, 0)]))
        self.assertEqual(changes(ROOM[5], "Q"), (0, [(7, 1), (15, 0), (23, 1), (27, 0)]))

    def test_every_waveform_room_can_be_drawn_and_read(self):
        for ordinal in range(1, 6):
            payload = ROOM[ordinal]
            waves = simulate(payload)
            with self.subTest(room=ordinal):
                self.assertLessEqual(payload["ticks"], 60)
                self.assertTrue(set(payload["draw"]) <= {gate["out"] for gate in payload["circuit"]["gates"]})
                # Every drawn signal changes at least once, and its last edge fits on the grid.
                self.assertTrue(all(edges(waves[name]) for name in payload["draw"]))
                for part in payload["circuit"]["gates"]:
                    self.assertTrue(all(name in waves for name in part["in"]))
                    if part["op"] == "dff":
                        # D never changes on a rising edge, so what the flip-flop takes is never in doubt.
                        clk, data = waves[part["clk"]], waves[part["in"][0]]
                        rising = [t for t in range(1, payload["ticks"]) if clk[t] and not clk[t - 1]]
                        self.assertTrue(rising and all(data[t] == data[t - 1] for t in rising))

    def test_the_pipelining_rooms_use_the_lecture_numbers(self):
        # Lecture 15's adder: 20 + 480 + 480 without pipeline registers, 20 + 480 with them.
        self.assertEqual(table_keys(ROOM[6]), ["980", "500"])
        self.assertEqual(table_keys(ROOM[7]), ["0", "1", "2"])
        self.assertTrue(grade_puzzle(ROOM[6], {"cells": ["0980", "500.0"]}))
        # Lecture 22: lw needs all five stages single-cycle; the pipeline's clock covers one.
        self.assertEqual(table_keys(ROOM[8]), ["0", "1", "2", "3", "4", "820", "220"])
        # Lecture 23's practice: two stalls without forwarding; with it, only the load-use stall.
        self.assertEqual(table_keys(ROOM[9]), ["0", "0", "2", "0", "0"])
        # With forwarding, only the load-use stall (Lecture 23 Q3).
        self.assertEqual(table_keys(ROOM[10]), ["0", "1", "0", "0", "0", "0", "1"])
        for ordinal in (9, 10):
            chart = ROOM[ordinal]["chart"]
            # The keys are the fewest stalls that let every value arrive...
            self.assertNotIn(None, sum(forwarding(chart["rows"], chart["stalls"]), []))
            for fewer in range(len(chart["stalls"])):
                if chart["stalls"][fewer]:
                    less = chart["stalls"][:fewer] + [chart["stalls"][fewer] - 1] + chart["stalls"][fewer + 1:]
                    self.assertFalse(arrives(chart["rows"], less, chart.get("forwarding", False)))
            # ...and the only way to stall that few: any other placement leaves a hazard.
            stalls = chart["stalls"]
            others = [list(s) for s in itertools.product(range(3), repeat=len(stalls))
                      if sum(s) <= sum(stalls) and list(s) != stalls]
            self.assertFalse(any(arrives(chart["rows"], s, chart.get("forwarding", False)) for s in others))
        # Forwarding leaves only load-use stalls, but the room's note teaches all three mux settings.
        chart = ROOM[10]["chart"]
        self.assertEqual({code for codes in forwarding(chart["rows"], chart["stalls"]) for code in codes}, {"00", "01", "10"})
        for room in ROOMS:
            for clock in room["payload"].get("clocks", []):
                total = sum(time for _, time in clock["path"])
                self.assertIn(total, clock["choices"])
                self.assertEqual(max(clock["choices"]), sorted(clock["choices"])[-1])
                self.assertGreater(max(clock["choices"]), total)  # The slowest setting, where a tuner starts, works.
        for room in ROOMS:
            blanks = [cell for row in room["payload"].get("rows", []) for cell in row if isinstance(cell, dict)]
            for blank in blanks + room["payload"].get("asks", []):
                self.assertIn(blank["blank"], blank.get("choices", [blank["blank"]]))
        for ordinal in (7, 8, 9, 10):
            chart = ROOM[ordinal]["chart"]
            with self.subTest(room=ordinal):
                marks = chart.get("starts", chart.get("stalls"))
                self.assertEqual(len(marks), len(chart["rows"]))
                self.assertLessEqual(len(chart["rows"]) + len(chart["stages"]) - 1 + sum(chart.get("stalls", [])), chart["cycles"])


if __name__ == "__main__":
    unittest.main()
