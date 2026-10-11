"""Puzzle simulation, grading, and gate design checks; needs no database."""

import heapq
from itertools import product
import json
from pathlib import Path
import re
import unittest

from fastapi import HTTPException

from server.puzzles import (BRANCHES, EXIT, JUNK, Fault, branch_taken, code_blanks, code_passes, grade_puzzle, maze_lines,
                            maze_solved, parse_line, reg, run_code, run_maze, run_program)

ROOT = Path(__file__).parents[1]
LEVEL1 = json.loads((ROOT / "levels/level_1/guest_rooms.json").read_text())
GATES = LEVEL1["rooms"]
# One winning answer per Level 1 gate, by ordinal (db/migrations/0005_level1_puzzles.sql, and 0010 for
# gates 11-22): the keys pressed, in order.
GATE_SOLUTIONS = {
    1: [0], 2: [0, 0, 0], 3: [1, 0], 4: [0, 1, 0], 5: [2, 0], 6: [0, 1], 7: [0, 1], 8: [0, 1], 9: [0, 0, 1],
    10: [1, 1, 1], 11: [0, 0, 1], 12: [0, 1, 2], 13: [0, 1], 14: [0, 1], 15: [0, 1], 16: [0, 1], 17: [0, 1],
    18: [0, 1], 19: [0, 0], 20: [0, 0], 21: [1, 1], 22: [0, 0],
}
BANK = json.loads((ROOT / "levels/level_2/guest_rooms.json").read_text())
ROOMS = BANK["rooms"]
ROOM = {room["ordinal"]: room["payload"] for room in ROOMS}
# One winning answer per Level 2 room, by ordinal (db/migrations/0007_level2_memory_maze.sql): the
# program for a maze room, the line picked for each blank of a code room.
SOLUTIONS = {
    1: ["addi a0, a0, 4"] * 4,
    2: ["lw a2, 12(a0)"] + ["addi a0, a0, 4"] * 5,
    3: ["sw t2, 12(a0)"] + ["addi a0, a0, 4"] * 5,
    4: ["loop:", "addi a0, a0, 4", "bne a0, a1, loop"],
    5: ["addi a0, a0, 16"] * 2 + ["addi a0, a0, 4"] * 3,
    6: ["addi a0, a0, 4", "lw t0, 20(a0)", "addi t0, t0, 5", "sw t0, 20(a0)", "addi a0, a0, 16", "addi a0, a0, 4",
        "addi a0, a0, 4", "addi a0, a0, -16"],
    7: ["lw t0, -12(a0)", "lw t1, 28(a0)", "sw t1, -12(a0)", "sw t0, 28(a0)", "addi a0, a0, 4", "addi a0, a0, 4",
        "addi a0, a0, 20", "addi a0, a0, 20"],
    8: ["slli t3, t2, 2", "lw t5, 4(t3)"],
    9: ["beq t0, x0, else", "j done"],
    10: ["loop:", "addi a0, a0, 4", "lw t1, 0(a0)", "bne t1, x0, loop"],
    11: ["loop:", "lw t0, 0(a0)", "sw t0, 28(a0)", "addi a0, a0, 4", "blt a0, a1, loop"],
    12: ["loop:", "lw t1, 0(a0)", "add t2, t2, t1", "addi a0, a0, 4", "addi t0, t0, 1", "blt t0, t6, loop"],
    13: ["sw t4, 0(t3)", "bge t0, x0, loop"],
    14: ["jal ra, func", "jalr x0, 0(ra)"],
    15: ["addi sp, sp, -8", "sw ra, 4(sp)", "sw a0, 0(t1)"],
    16: ["loop:", "lw t0, 0(a0)", "sw t0, -28(a0)", "addi a0, a0, 4", "bne a0, a1, loop"],
}


def answer(ordinal):
    return {"blanks" if ROOM[ordinal]["kind"] == "code" else "program": SOLUTIONS[ordinal]}


def ins(op, rd, rs1, rs2=None, imm=None):
    return {"op": op, "rd": rd, "rs1": rs1, **({"rs2": rs2} if rs2 is not None else {"imm": imm})}


def maze(room_map, **fields):
    return {"kind": "maze", "base": 0x100, "map": room_map, "hands": ["t0"], "goal": {}, "max_moves": 8, "par": 1,
            **fields}


def run(payload, lines):
    return run_maze(payload, [parse_line(line) for line in lines])


def outcome(payload, lines):
    try:
        return run(payload, lines)
    except Fault:
        return None


def code(lines, tests=None, **fields):
    entries = [{"label": line[:-1]} if line.endswith(":") else {"line": line} for line in lines]
    return {"kind": "code", "code": entries, "tests": tests or [{"expect": {}}], **fields}


def shortest_walk(payload):
    """The fewest instructions that open a room without loops, by A* search over every line the
    room allows. Each instruction moves the robot one cell or changes one word or register, so the
    steps left to the exit plus the goals still unmet never overestimate what remains."""
    tiles = "".join(payload["map"])
    width = len(payload["map"][0])
    base = payload["base"]
    lines = sorted(maze_lines(payload))
    exit_cell = tiles.find("E")
    distance = {exit_cell: 0} if exit_cell >= 0 else {}
    queue = list(distance)
    for cell in queue:
        r, c = divmod(cell, width)
        for nr, nc in ((r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)):
            n = nr * width + nc
            if 0 <= nr < len(payload["map"]) and 0 <= nc < width and n not in distance and tiles[n] not in "#B":
                distance[n] = distance[cell] + 1
                queue.append(n)
    goal_words = [((int(a, 16) - base) // 4, v) for a, v in payload["goal"].get("memory", {}).items()]
    goal_regs = [(reg(name), v) for name, v in payload["goal"].get("registers", {}).items()]

    def estimate(regs, words):
        steps = distance.get((regs[reg("a0")] - base) // 4, 99) if exit_cell >= 0 else 0
        return steps + sum(words[i] != v for i, v in goal_words) + sum(regs[r] != v for r, v in goal_regs)

    start = outcome(payload, [])
    best = {(tuple(start[0]), tuple(start[1])): 0}
    frontier = [(estimate(*start), 0, [])]
    while frontier:
        _, cost, program = heapq.heappop(frontier)
        if maze_solved(payload, *outcome(payload, program)):
            return cost
        if cost >= payload["max_moves"]:
            continue
        for line in lines:
            result = outcome(payload, program + [line])
            if result is None or best.get(key := (tuple(result[0]), tuple(result[1])), 99) <= cost + 1:
                continue
            best[key] = cost + 1
            heapq.heappush(frontier, (cost + 1 + estimate(*result), cost + 1, program + [line]))
    return None


def loop_solution(payload, limit, solution):
    """Any program of at most `limit` instructions (plus one loop: label, above every branch) that
    opens a room; prefixes that fault are cut, since the game refuses those keys. A loop body's
    offsets are fixed, so loads and stores are tried at the robot's cell, its neighbours, and the
    offsets the room's solution uses: reaching farther can't make a loop shorter."""
    row = 4 * len(payload["map"][0])
    offsets = {0, 4, -4, row, -row} | {parse_line(line)["imm"] for line in solution
                                       if parse_line(line)["op"] in ("lw", "sw")}
    lines = [line for line in sorted(maze_lines(payload))
             if parse_line(line)["op"] not in ("lw", "sw") or parse_line(line)["imm"] in offsets]

    def search(program, count, labelled):
        if program:
            result = outcome(payload, program)
            if result is None:
                return None
            if count and maze_solved(payload, *result):
                return program
        for line in lines:
            op = parse_line(line)["op"]
            if op == "label" and not labelled:
                found = search(program + [line], count, True)
            elif op != "label" and count < limit and (labelled or op not in BRANCHES):
                found = search(program + [line], count + 1, labelled)
            else:
                continue
            if found:
                return found
        return None

    return search([], 0, False)


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

    def test_abi_and_x_register_names_agree(self):
        self.assertEqual([reg(name) for name in ("x0", "zero", "ra", "sp", "t0", "t2", "s0", "fp", "a0", "a7", "s11",
                                                 "t6", "x31")], [0, 0, 1, 2, 5, 7, 8, 8, 10, 17, 27, 31, 31])
        self.assertEqual(parse_line("lw a2, 12(a0)"), parse_line("lw x12, 12(x10)"))


class MazeInterpreterTests(unittest.TestCase):
    def test_steps_follow_row_major_addresses(self):
        regs, _ = run(maze(["S..", "..E"]), ["addi a0, a0, 4", "addi a0, a0, 12", "addi a0, a0, 4"])
        self.assertEqual(regs[reg("a0")], 0x100 + 4 * 5)

    def test_loads_copy_and_stores_overwrite(self):
        room = maze(["S.", ".B"], values={"0x10c": 7}, hands=["t0", "t1"])
        regs, words = run(room, ["addi a0, a0, 4", "lw t0, 8(a0)", "sw t0, 0(a0)", "lw t1, -4(a0)"])
        self.assertEqual((regs[reg("t0")], regs[reg("t1")], words), (7, 0, [0, 7, 0, 7]))

    def test_steps_and_accesses_that_fault(self):
        room = maze(["S#.", ".B."], values={"0x110": 4})
        for program in (["addi a0, a0, 4"], ["addi a0, a0, 12", "addi a0, a0, 4"], ["addi a0, a0, -4"],
                        ["addi a0, a0, -12"], ["lw t0, 4(a0)"], ["sw t0, -4(a0)"], ["lw t0, 24(a0)"],
                        ["addi a0, a0, 12", "addi a0, a0, -4"]):
            with self.subTest(program=program), self.assertRaises(Fault):
                run(room, program)
        # A step right from the end of a row would land on the next row's first word: not a neighbour.
        with self.assertRaises(Fault):
            run(maze(["..S", "..."]), ["addi a0, a0, 4"])

    def test_base_plus_offset_reaches_any_word(self):
        room = maze(["S#.", ".B."], values={"0x110": 4, "0x114": 9})
        self.assertEqual(run(room, ["lw t0, 16(a0)"])[0][reg("t0")], 4)  # Glass, two cells away.
        self.assertEqual(run(room, ["lw t0, 20(a0)"])[0][reg("t0")], 9)  # The far corner.
        # Memory is one line of words: +4 from a row's last word is the next row's first.
        self.assertEqual(run(maze(["..S", "7.."], values={"0x10c": 7}), ["lw t0, 4(a0)"])[0][reg("t0")], 7)

    def test_a_door_opens_when_its_word_holds_the_code(self):
        room = maze(["SDE"], values={"0x100": 9}, doors={"0x104": 9})
        with self.assertRaises(Fault):
            run(room, ["addi a0, a0, 4"])
        regs, _ = run(room, ["lw t0, 0(a0)", "sw t0, 4(a0)", "addi a0, a0, 4", "addi a0, a0, 4"])
        self.assertEqual(regs[reg("a0")], 0x108)

    def test_a_taken_branch_repeats_the_taught_pass(self):
        corridor = ROOM[4]
        self.assertEqual(run(corridor, SOLUTIONS[4])[0][reg("a0")], corridor["registers"]["a1"])
        self.assertEqual(run(corridor, ["loop:", "addi a0, a0, 4", "beq a0, a1, loop"])[0][reg("a0")], corridor["base"] + 4)

    def test_the_chomper_eats_its_row_on_schedule(self):
        race = ROOM[16]
        _, words = run(race, ["addi a0, a0, 4"] * 4)
        self.assertEqual(words[7:13], [0, 2, 9, 4, 8, 1])  # The first bite comes with the fourth instruction.
        _, words = run(race, SOLUTIONS[16])
        self.assertEqual((words[:6], words[7:13]), ([7, 2, 9, 4, 8, 1], [0] * 6))

    def test_signed_and_unsigned_branch_comparisons(self):
        minus_one = 0xFFFFFFFF
        self.assertEqual([branch_taken(op, minus_one, 1) for op in ("beq", "bne", "blt", "bge", "bltu", "bgeu")],
                         [False, True, True, False, False, True])

    def test_endless_loops_and_missing_labels_fault(self):
        room = maze(["S.E"], loop=True, repeat=["bne a0, a1, loop"], registers={"a1": 0x104})
        for program in (["loop:", "addi a0, a0, 4", "addi a0, a0, -4", "bne a0, a1, loop"],
                        ["bne a0, a1, loop", "loop:"]):
            with self.subTest(program=program), self.assertRaises(Fault):
                run(room, program)


class CodeInterpreterTests(unittest.TestCase):
    def test_lines_sit_4_bytes_apart_from_0x100_and_jal_saves_pc_plus_4(self):
        room = code(["addi a0, x0, 6", "jal ra, func", "addi a0, a0, 1", "j done", "func:", "addi a0, a0, 3",
                     "jalr x0, 0(ra)", "done:"])
        state = run_code(room, [], room["tests"][0])
        self.assertEqual((state["regs"][reg("a0")], state["regs"][reg("ra")], state["pc"]), (10, 0x108, 0x118))

    def test_forward_branches_pick_a_path(self):
        room = code(["slti t0, a0, 5", "beq t0, x0, else", "addi a1, a1, 3", "j done", "else:", "slli a1, a1, 1",
                     "done:"])
        self.assertEqual(run_code(room, [], {"registers": {"a0": 3, "a1": 4}})["regs"][reg("a1")], 7)
        self.assertEqual(run_code(room, [], {"registers": {"a0": 7, "a1": 4}})["regs"][reg("a1")], 8)

    def test_data_labels_and_the_stack(self):
        room = code(["la t1, arr", "lw t2, 8(t1)", "addi sp, sp, -8", "sw t2, 4(sp)", "lw t3, 0(sp)"],
                    data={"base": 0x2000, "blocks": [{"label": "arr", "words": [3, 5, 7]}]},
                    stack={"top": 0x7FF0, "words": 2})
        state = run_code(room, [], room["tests"][0])
        self.assertEqual((state["regs"][reg("t1")], state["regs"][reg("t2")], state["memory"][0x7FEC],
                          state["regs"][reg("t3")]), (0x2000, 7, 7, JUNK))

    def test_returning_to_the_caller_ends_the_program(self):
        state = run_code(code(["addi a0, x0, 1", "jalr x0, 0(ra)", "addi a0, x0, 2"]), [], {})
        self.assertEqual((state["pc"], state["regs"][reg("a0")]), (EXIT, 1))

    def test_jumps_and_memory_outside_the_program_fault(self):
        stack = {"top": 0x7FF0, "words": 2}
        for lines in (["jalr x0, 4(x0)"], ["lw t0, 0(sp)"], ["addi sp, sp, -4", "lw ra, 0(sp)", "jalr x0, 0(ra)"],
                      ["loop:", "j loop"], ["sw t0, 1(sp)"]):
            with self.subTest(lines=lines), self.assertRaises(Fault):
                run_code(code(lines, stack=stack), [], {})


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

    def test_maze_rooms_accept_any_working_program(self):
        step = "addi a0, a0, 4"
        # The lecture's two ways to reach arr[3]: 12 bytes from arr[0], or 8 after one step.
        for program in (SOLUTIONS[2], [step, "lw a2, 8(a0)"] + [step] * 4, [step] * 5 + ["lw a2, -8(a0)"]):
            self.assertTrue(grade_puzzle(ROOM[2], {"program": program}), program)
        for program in (SOLUTIONS[3], [step, step, "sw t2, 4(a0)"] + [step] * 3):
            self.assertTrue(grade_puzzle(ROOM[3], {"program": program}), program)
        lecture_order = ["loop:", "lw t1, 0(a0)", "add t2, t2, t1", "addi t0, t0, 1", step, "blt t0, t6, loop"]
        self.assertTrue(grade_puzzle(ROOM[12], {"program": lecture_order}))
        stepped_first = ["loop:", step, "lw t1, 0(a0)", "add t2, t2, t1", "addi t0, t0, 1", "blt t0, t6, loop"]
        self.assertFalse(grade_puzzle(ROOM[12], {"program": stepped_first}))  # Skips values[0].

    def test_maze_goals_check_registers_memory_and_the_exit(self):
        self.assertFalse(grade_puzzle(ROOM[2], {"program": ["lw a2, 8(a0)"] + SOLUTIONS[2][1:]}))  # a2 = 100.
        self.assertFalse(grade_puzzle(ROOM[2], {"program": SOLUTIONS[2][:-1]}))  # Not on the exit.
        # Storing the door's own 7 back without adding leaves it locked.
        self.assertFalse(grade_puzzle(ROOM[6], {"program": [line for line in SOLUTIONS[6] if line != "addi t0, t0, 5"]}))
        stored_first = ["lw t0, -12(a0)", "sw t0, 28(a0)", "lw t1, 28(a0)", "sw t1, -12(a0)", "addi a0, a0, 4",
                        "addi a0, a0, 4", "addi a0, a0, 20", "addi a0, a0, 20"]
        self.assertFalse(grade_puzzle(ROOM[7], {"program": stored_first}))  # Overwrote a code before saving it.

    def test_the_race_needs_a_tight_loop(self):
        slow = ["loop:", "lw t0, 0(a0)", "lw t0, 0(a0)", "sw t0, -28(a0)", "addi a0, a0, 4", "bne a0, a1, loop"]
        self.assertTrue(grade_puzzle(ROOM[16], answer(16)))
        self.assertFalse(grade_puzzle(ROOM[16], {"program": slow}))
        self.assertTrue(grade_puzzle({key: value for key, value in ROOM[16].items() if key != "chomper"}, {"program": slow}))

    def test_programs_that_fault_are_wrong_not_malformed(self):
        self.assertFalse(grade_puzzle(ROOM[5], {"program": ["addi a0, a0, 4", "addi a0, a0, 4"]}))
        self.assertFalse(grade_puzzle(ROOM[4], {"program": ["loop:", "addi a0, a0, 4", "addi a0, a0, -4",
                                                            "bne a0, a1, loop"]}))

    def test_rejects_malformed_maze_answers(self):
        step, repeat = "addi a0, a0, 4", "bne a0, a1, loop"
        for response in ({"program": []}, {"program": ["loop:"]}, {"program": ["loop:", "loop:", step, repeat]},
                         {"program": [repeat, "loop:", step]}, {"program": [step] * 4}, {"program": ["loop:"] + [step] * 4},
                         {"program": ["addi a0, a0, 8"]}, {"program": ["lw t0, 0(a0)"]}, {"program": ["addi x10, x10, 4"]},
                         {"program": [4]}, {"program": step}, {"moves": [0]}, {"program": [step], "extra": 1}):
            with self.subTest(response=response), self.assertRaises(HTTPException) as caught:
                grade_puzzle(ROOM[4], response)
            self.assertEqual(caught.exception.status_code, 422)

    def test_code_rooms_check_every_test(self):
        # If/else: the wrong branch passes x = 7 but not x = 3.
        self.assertTrue(grade_puzzle(ROOM[9], answer(9)))
        self.assertTrue(code_passes(ROOM[9], ["bne t0, x0, else", "j done"], ROOM[9]["tests"][1]) is False)
        self.assertFalse(grade_puzzle(ROOM[9], {"blanks": ["beq t0, x0, else", "addi x0, x0, 0"]}))  # Falls into else.
        # Question 4: restoring a0 before storing func's answer loses it.
        self.assertFalse(grade_puzzle(ROOM[15], {"blanks": ["addi sp, sp, -8", "sw ra, 4(sp)", "lw a0, 0(sp)"]}))
        self.assertFalse(grade_puzzle(ROOM[15], {"blanks": ["addi sp, sp, -8", "lw ra, 4(sp)", "sw a0, 0(t1)"]}))

    def test_rejects_malformed_code_answers(self):
        for response in ({"blanks": []}, {"blanks": ["jal ra, func"]}, {"blanks": ["jal ra, func", "ret"]},
                         {"blanks": ["jal ra, func", 3]}, {"blanks": "jal ra, func"}, {"program": SOLUTIONS[14]},
                         {"blanks": SOLUTIONS[14], "extra": 1}):
            with self.subTest(response=response), self.assertRaises(HTTPException) as caught:
                grade_puzzle(ROOM[14], response)
            self.assertEqual(caught.exception.status_code, 422)

    def test_every_room_line_parses(self):
        for room in ROOMS:
            payload = room["payload"]
            lines = (maze_lines(payload) if payload["kind"] == "maze"
                     else [entry.get("line") or line for entry in payload["code"] if "label" not in entry
                           for line in entry.get("blank", [None])])
            for line in lines:
                self.assertIn("op", parse_line(line), line)


class GateDesignTests(unittest.TestCase):
    """Every gate must open within its move limit, and par must be the true minimum."""

    def test_every_gate_is_solvable_and_par_is_optimal(self):
        self.assertEqual([gate["ordinal"] for gate in GATES], list(range(1, 23)))
        for gate in GATES:
            payload = gate["payload"]
            with self.subTest(gate=gate["ordinal"]):
                self.assertFalse(matches(gate, []), "the gate starts already open")
                shortest = next((n for n in range(1, payload["max_moves"] + 1)
                                 if any(matches(gate, moves) for moves in product(range(len(payload["buttons"])), repeat=n))),
                                None)
                self.assertEqual(shortest, payload["par"])
                solution = GATE_SOLUTIONS[gate["ordinal"]]
                self.assertEqual(len(solution), payload["par"])
                self.assertTrue(grade_puzzle(payload, {"moves": solution}))
                goal, _, detail = gate["prompt"].partition("\n")
                self.assertTrue(goal and detail and gate["hint"] and gate["explanation"])

    def test_every_run_plays_the_tutorial_and_one_gate_of_each_topic(self):
        pools = {}
        for gate in GATES:
            pools.setdefault(gate["pool"], []).append(gate["ordinal"])
        self.assertEqual([slot["pool"] for slot in LEVEL1["draw"]],
                         ["tutorial", "hex", "masks", "flips", "signed", "overflow", "shifts"])
        self.assertEqual(pools["tutorial"], [1, 2, 3, 4])
        for slot in LEVEL1["draw"][1:]:
            with self.subTest(pool=slot["pool"]):
                self.assertEqual(slot["take"], 1)
                self.assertEqual(len(pools[slot["pool"]]), 3)

    def test_every_maze_room_is_solvable_and_par_is_optimal(self):
        for room in ROOMS:
            payload = room["payload"]
            if payload["kind"] != "maze":
                continue
            with self.subTest(room=room["ordinal"]):
                self.assertFalse(maze_solved(payload, *run(payload, [])), "the room starts already open")
                solution = SOLUTIONS[room["ordinal"]]
                self.assertEqual(len([line for line in solution if line != "loop:"]), payload["par"])
                self.assertTrue(grade_puzzle(payload, {"program": solution}))
                if payload.get("loop"):
                    self.assertIsNone(loop_solution(payload, payload["par"] - 1, solution))
                else:
                    self.assertEqual(shortest_walk(payload), payload["par"])
                self.assertTrue(room["prompt"] and room["hint"] and room["explanation"])

    def test_every_code_room_has_exactly_one_answer(self):
        for room in ROOMS:
            payload = room["payload"]
            if payload["kind"] != "code":
                continue
            with self.subTest(room=room["ordinal"]):
                passing = [list(filling) for filling in product(*code_blanks(payload))
                           if all(code_passes(payload, list(filling), test) for test in payload["tests"])]
                self.assertEqual(passing, [SOLUTIONS[room["ordinal"]]])
                self.assertTrue(room["prompt"] and room["code_snippet"] and room["hint"] and room["explanation"])

    def test_the_bank_and_its_draw(self):
        self.assertEqual([room["ordinal"] for room in ROOMS], list(range(1, len(ROOMS) + 1)))
        pools = {}
        for room in ROOMS:
            pools.setdefault(room["pool"], []).append(room["ordinal"])
        self.assertEqual([slot["pool"] for slot in BANK["draw"]], list(pools))
        per_run = sum(slot.get("take", len(pools[slot["pool"]])) for slot in BANK["draw"])
        self.assertEqual(per_run, 10)
        self.assertTrue(all(slot.get("take", 0) <= len(pools[slot["pool"]]) for slot in BANK["draw"]))

    def test_the_instruction_guide_explains_every_instruction(self):
        # The in-game guide (ui/instruction_guide.gd) lists only instructions it has an entry for.
        guide = (ROOT / "ui/instruction_guide.gd").read_text()
        entries = set(re.findall(r'^\t"(\w+)": \{"name"', guide, re.MULTILINE))
        used = {button["op"] for gate in GATES for button in gate["payload"]["buttons"]}
        for room in ROOMS:
            payload = room["payload"]
            lines = (maze_lines(payload) if payload["kind"] == "maze"
                     else [line for entry in payload["code"] for line in entry.get("blank", [entry.get("line")]) if line]
                     + [entry["label"] + ":" for entry in payload["code"] if "label" in entry])
            used |= {"label" if line.endswith(":") else line.split()[0] for line in lines}
        level3 = json.loads((ROOT / "levels/level_3/guest_rooms.json").read_text())["rooms"]
        for room in level3:
            for entry in room["payload"]["code"]:
                used.add("label" if "label" in entry else entry["line"].split()[0] if "line" in entry else "addi")
        self.assertTrue({"mul", "jr", "ret"} <= used)
        self.assertEqual(used - entries, set())
        self.assertGreater(len(entries), 30)


if __name__ == "__main__":
    unittest.main()
