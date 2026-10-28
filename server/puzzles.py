"""Grade puzzle gates by replaying what the player did, so any valid solution passes.

Level 1 gates (kind "moves") run straight-line instructions on registers. Level 2 has two kinds
of room. Maze rooms (kind "maze") are memory the robot walks through: the player's actions are
RISC-V lines (steps, loads, stores, and a loop: label that branches jump back to), and the
response is that program as text. Code rooms (kind "code") are short programs with blank lines
to fill: the response is the line picked for each blank, and the program must pass every one of
the room's tests. Level 3's walkthroughs (kind "walk") are graded in call_stack.py.

Registers go by their ABI names (a0, t1, sp, ra; x0 stays x0, as the course writes it), and the
x-names are accepted too.
"""

import re

from fastapi import HTTPException

R_TYPE = {"add", "sub", "and", "or", "xor", "sll", "srl", "sra", "slt", "sltu", "mul", "div", "rem"}
BRANCHES = {"beq", "bne", "blt", "bge", "bltu", "bgeu"}
MASK = 0xFFFFFFFF
STEP_LIMIT = 200  # Instructions a maze program may execute before it counts as an endless loop.
REGISTERS = ["x0", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6",
             "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"]
NUMBERS = {name: number for number, name in enumerate(REGISTERS)} | {f"x{n}": n for n in range(32)} | {"zero": 0, "fp": 8}
REG = r"(x\d+|zero|ra|sp|gp|tp|fp|t[0-6]|s1[01]|s\d|a[0-7])"
LABEL_LINE = re.compile(r"(\w+):")
MEMORY_LINE = re.compile(rf"(lw|sw) {REG}, (-?\d+)?\({REG}\)")  # (sp) means 0(sp).
BRANCH_LINE = re.compile(rf"(beq|bne|blt|bge|bltu|bgeu) {REG}, {REG}, (\w+)")
JAL_LINE = re.compile(rf"jal {REG}, (\w+)")
JUMP_LINE = re.compile(r"j (\w+)")
JALR_LINE = re.compile(rf"jalr {REG}, (-?\d+)?\({REG}\)")
JR_LINE = re.compile(rf"jr {REG}")
LA_LINE = re.compile(rf"la {REG}, (\w+)")
REGISTER_LINE = re.compile(rf"([a-z]+) {REG}, {REG}, {REG}")
IMMEDIATE_LINE = re.compile(rf"([a-z]+) {REG}, {REG}, (-?\d+)")
CODE_BASE = 0x100  # A code room's first instruction.
EXIT = 0x400  # Where main's caller (the OS) waits: returning here ends a code room's program.
JUNK = 0xDEADBEEF  # What a stack word holds before anything is saved in it.
CODE_STEP_LIMIT = 500


class Fault(Exception):
    """The program would crash: the robot walks into a wall, a load misses memory, or it never ends."""


def reg(name: str) -> int:
    return NUMBERS[name]


def signed(value: int, width: int = 32) -> int:
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value


def execute(op: str, a: int, b: int, width: int = 32) -> int:
    """Apply one ALU operation to width-bit operands; the immediate forms share the register ones."""
    op = "sltu" if op == "sltiu" else op if op in R_TYPE else op.removesuffix("i")
    if op in ("mul", "div", "rem"):
        return multiply_divide(op, a, b, width)
    shift = b & 31
    result = {
        "add": a + b, "sub": a - b, "and": a & b, "or": a | b, "xor": a ^ b,
        "sll": a << shift, "srl": a >> shift, "sra": signed(a, width) >> shift,
        "slt": int(signed(a, width) < signed(b, width)), "sltu": int(a < b),
    }[op]
    return result & ((1 << width) - 1)


def multiply_divide(op: str, a: int, b: int, width: int = 32) -> int:
    """RV32M: mul keeps the low bits of the product, and division rounds toward zero. Dividing by
    zero gives all ones (div) or the dividend (rem); the one division that overflows, the most
    negative number divided by -1, gives that number back (div) and 0 (rem)."""
    mask = (1 << width) - 1
    if op == "mul":
        return (a * b) & mask
    x, y = signed(a, width), signed(b, width)
    if y == 0:
        return mask if op == "div" else a & mask
    if x == -(1 << (width - 1)) and y == -1:
        return a & mask if op == "div" else 0
    quotient = abs(x) // abs(y) * (1 if (x < 0) == (y < 0) else -1)
    return (quotient if op == "div" else x - quotient * y) & mask


def branch_taken(op: str, a: int, b: int) -> bool:
    return {"beq": a == b, "bne": a != b, "blt": signed(a) < signed(b), "bge": signed(a) >= signed(b),
            "bltu": a < b, "bgeu": a >= b}[op]


def run_program(program: list[dict], initial: dict, width: int = 32) -> list[int]:
    """Run instructions on width-bit registers; x0 stays 0 and values wrap around."""
    mask = (1 << width) - 1
    regs = [0] * 32
    for name, value in initial.items():
        regs[reg(name)] = value & mask
    for ins in program:
        second = regs[ins["rs2"]] if "rs2" in ins else ins["imm"] & mask
        if ins["rd"]:
            regs[ins["rd"]] = execute(ins["op"], regs[ins["rs1"]], second, width)
    return regs


def grade_moves(payload: dict, response: dict) -> bool:
    """A Level 1 gate's buttons are fixed instructions; the response is which ones were pressed, in order."""
    buttons = payload["buttons"]
    moves = response.get("moves")
    if (set(response) != {"moves"} or not isinstance(moves, list) or not moves
            or len(moves) > payload["max_moves"]
            or any(type(move) is not int or not 0 <= move < len(buttons) for move in moves)):
        raise HTTPException(422, f"Press between 1 and {payload['max_moves']} of this gate's buttons.")
    width = payload.get("width", 32)
    regs = run_program([buttons[move] for move in moves], payload.get("initial", {}), width)
    return all(regs[reg(name)] == value & ((1 << width) - 1) for name, value in payload["goal"].items())


def parse_line(line: str) -> dict:
    """One line of assembly, in the exact form the game writes it."""
    if match := LABEL_LINE.fullmatch(line):
        return {"op": "label", "name": match[1]}
    if match := MEMORY_LINE.fullmatch(line):
        op, register, offset, base = match.groups()
        return {"op": op, "rd" if op == "lw" else "rs2": reg(register), "imm": int(offset or 0), "rs1": reg(base)}
    if match := BRANCH_LINE.fullmatch(line):
        return {"op": match[1], "rs1": reg(match[2]), "rs2": reg(match[3]), "target": match[4]}
    if match := JAL_LINE.fullmatch(line):
        return {"op": "jal", "rd": reg(match[1]), "target": match[2]}
    if match := JUMP_LINE.fullmatch(line):
        return {"op": "jal", "rd": 0, "target": match[1]}
    if match := JALR_LINE.fullmatch(line):
        return {"op": "jalr", "rd": reg(match[1]), "imm": int(match[2] or 0), "rs1": reg(match[3])}
    if match := JR_LINE.fullmatch(line):  # Short for jalr x0, 0(rs1).
        return {"op": "jalr", "rd": 0, "imm": 0, "rs1": reg(match[1])}
    if line == "ret":  # Short for jalr x0, 0(ra).
        return {"op": "jalr", "rd": 0, "imm": 0, "rs1": reg("ra")}
    if match := LA_LINE.fullmatch(line):
        return {"op": "la", "rd": reg(match[1]), "target": match[2]}
    if match := REGISTER_LINE.fullmatch(line):
        return {"op": match[1], "rd": reg(match[2]), "rs1": reg(match[3]), "rs2": reg(match[4])}
    if match := IMMEDIATE_LINE.fullmatch(line):
        return {"op": match[1], "rd": reg(match[2]), "rs1": reg(match[3]), "imm": int(match[4])}
    raise ValueError(f"Not an instruction the game writes: {line!r}")


def maze_lines(payload: dict) -> set[str]:
    """Every line the player can write in a room: a step in each direction (a row is 4 bytes per
    word), a load or store with each hand at any offset that could land on one of the room's words
    (base + offset reaches anywhere, as a real 12-bit offset would), and the room's keys. The robot
    is a0: its address is the room's base register."""
    row = 4 * len(payload["map"][0])
    lines = {f"addi a0, a0, {step}" for step in (4, -4, row, -row)}
    words = len("".join(payload["map"]))
    for hand in payload.get("hands", []):
        lines |= {f"{op} {hand}, {offset}(a0)" for op in ("lw", "sw") for offset in range(-4 * (words - 1), 4 * words, 4)}
    lines |= set(payload.get("keys", [])) | set(payload.get("repeat", []))
    if payload.get("loop"):
        lines.add("loop:")
    return lines


def run_maze(payload: dict, program: list[dict]) -> tuple[list[int], list[int]]:
    """Run a room's program on 32-bit registers and its words of memory.

    The room's map is memory in row-major order: the word at row r, column c is at
    base + 4*(r*width + c). a0 is the robot's address and starts at S. Writing a0 must move
    the robot one cell, onto floor, the exit, or a door whose word holds its code; lw and sw
    reach any word of the room except a wall (#). Glass cells (B) can be reached but not stood on.
    A taken branch jumps back to the line after loop:. In a race, the Chip Chomper eats the first
    `words` words of its row, one (set to 0) every few instructions. Raises Fault instead of
    finishing when any of that is broken, or after STEP_LIMIT instructions.
    """
    tiles = "".join(payload["map"])
    width = len(payload["map"][0])
    base = payload["base"]
    robot = reg("a0")
    words = [0] * len(tiles)
    for address, value in payload.get("values", {}).items():
        words[(int(address, 16) - base) // 4] = value & MASK
    doors = {(int(address, 16) - base) // 4: code & MASK for address, code in payload.get("doors", {}).items()}
    regs = [0] * 32
    regs[robot] = base + 4 * tiles.index("S")
    for name, value in payload.get("registers", {}).items():
        regs[reg(name)] = value & MASK
    chomper = payload.get("chomper")

    def cell(address: int) -> int:
        offset = address - base
        if offset % 4 or not 0 <= offset < 4 * len(tiles):
            raise Fault(f"No word of this room is at {address:#x}.")
        return offset // 4

    def apart(a: int, b: int) -> int:
        return abs(a // width - b // width) + abs(a % width - b % width)

    label = next((i for i, ins in enumerate(program) if ins["op"] == "label"), None)
    pc = steps = 0
    while pc < len(program):
        ins = program[pc]
        op = ins["op"]
        pc += 1
        if op == "label":
            continue
        steps += 1
        if steps > STEP_LIMIT:
            raise Fault("The loop never ends.")
        here = cell(regs[robot])
        if op in BRANCHES:
            if label is None or label >= pc:
                raise Fault("A branch has no loop: label above it.")
            if branch_taken(op, regs[ins["rs1"]], regs[ins["rs2"]]):
                pc = label + 1
        elif op in ("lw", "sw"):
            target = cell((regs[ins["rs1"]] + ins["imm"]) & MASK)
            if tiles[target] == "#":
                raise Fault("That word is protected memory.")
            if op == "sw":
                words[target] = regs[ins["rs2"]]
            elif ins["rd"]:
                regs[ins["rd"]] = words[target]
        else:
            second = regs[ins["rs2"]] if "rs2" in ins else ins["imm"] & MASK
            value = execute(op, regs[ins["rs1"]], second)
            if ins["rd"] == robot:
                target = cell(value)
                locked = target in doors and words[target] != doors[target]
                if apart(here, target) != 1 or tiles[target] in "#B" or locked:
                    raise Fault("The robot can't step there.")
            if ins["rd"]:
                regs[ins["rd"]] = value
        if chomper and steps >= chomper["start"] and (steps - chomper["start"]) % chomper["every"] == 0:
            bite = (steps - chomper["start"]) // chomper["every"]
            if bite < chomper["words"]:
                words[chomper["row"] * width + bite] = 0
    return regs, words


def maze_solved(payload: dict, regs: list[int], words: list[int]) -> bool:
    """The robot stands on the exit (if the room has one) and every goal word and register holds."""
    tiles = "".join(payload["map"])
    base = payload["base"]
    goal = payload["goal"]
    return (("E" not in tiles or regs[reg("a0")] == base + 4 * tiles.index("E"))
            and all(regs[reg(name)] == value & MASK for name, value in goal.get("registers", {}).items())
            and all(words[(int(address, 16) - base) // 4] == value & MASK
                    for address, value in goal.get("memory", {}).items()))


def grade_maze(payload: dict, response: dict) -> bool:
    """The response is the player's program, one line per action, as the game wrote it. The loop:
    label is a line but not an instruction, and every branch must come after it."""
    lines = response.get("program")
    limit = payload["max_moves"]
    if (set(response) != {"program"} or not isinstance(lines, list) or not lines or len(lines) > limit + 1
            or any(not isinstance(line, str) for line in lines)):
        raise HTTPException(422, f"Send a program of 1 to {limit} instructions.")
    allowed = maze_lines(payload)
    labels = lines.count("loop:")
    above = lines[:lines.index("loop:")] if labels else lines
    if (any(line not in allowed for line in lines) or labels > 1 or not 1 <= len(lines) - labels <= limit
            or any(parse_line(line)["op"] in BRANCHES for line in above)):
        raise HTTPException(422, f"Use only this room's instructions: 1 to {limit} of them, with at most one "
                                 "loop: label above every branch.")
    try:
        regs, words = run_maze(payload, [parse_line(line) for line in lines])
    except Fault:
        return False
    return maze_solved(payload, regs, words)


def code_blanks(payload: dict) -> list[list[str]]:
    """Each blank's choices, in program order."""
    return [entry["blank"] for entry in payload["code"] if "blank" in entry]


def assemble(payload: dict, chosen: list[str]) -> tuple[list[str], dict]:
    """A code room's program with its blanks filled: its lines (the first at CODE_BASE, 4 bytes
    apart) and the address of each label."""
    lines, labels = [], {}
    picks = iter(chosen)
    for entry in payload["code"]:
        if "label" in entry:
            labels[entry["label"]] = CODE_BASE + 4 * len(lines)
        else:
            lines.append(entry["line"] if "line" in entry else next(picks))
    return lines, labels


def data_layout(payload: dict) -> tuple[dict, dict]:
    """A code room's memory: its data blocks laid out from data.base (each label marks its first
    word), plus the stack's words below stack.top, which hold junk until something is saved."""
    memory, labels = {}, {}
    data = payload.get("data")
    if data:
        address = data["base"]
        for block in data["blocks"]:
            labels[block["label"]] = address
            for word in block["words"]:
                memory[address] = word & MASK
                address += 4
    stack = payload.get("stack")
    if stack:
        for k in range(1, stack["words"] + 1):
            memory[stack["top"] - 4 * k] = JUNK
    return memory, labels


def run_code(payload: dict, chosen: list[str], test: dict) -> dict:
    """Run a code room's program on one test's inputs. ra starts at EXIT (main's caller), sp at the
    top of the stack. The program ends when it returns to EXIT or runs past its last line; it
    faults on a jump to where there's no code, a load or store outside the room's memory, or more
    than CODE_STEP_LIMIT instructions."""
    lines, code_labels = assemble(payload, chosen)
    program = [parse_line(line) for line in lines]
    memory, data_labels = data_layout(payload)
    regs = [0] * 32
    regs[reg("ra")] = EXIT
    if payload.get("stack"):
        regs[reg("sp")] = payload["stack"]["top"]
    for name, value in {**payload.get("registers", {}), **test.get("registers", {})}.items():
        regs[reg(name)] = (data_labels[value] if isinstance(value, str) else value) & MASK
    end = CODE_BASE + 4 * len(program)
    pc = CODE_BASE
    steps = 0
    while pc not in (EXIT, end):
        if pc % 4 or not CODE_BASE <= pc < end:
            raise Fault(f"There's no code at {pc:#x}.")
        steps += 1
        if steps > CODE_STEP_LIMIT:
            raise Fault("The program never ends.")
        ins = program[(pc - CODE_BASE) // 4]
        op = ins["op"]
        following = pc + 4
        if op in BRANCHES:
            if branch_taken(op, regs[ins["rs1"]], regs[ins["rs2"]]):
                following = code_labels[ins["target"]]
        elif op == "jal":
            if ins["rd"]:
                regs[ins["rd"]] = pc + 4
            following = code_labels[ins["target"]]
        elif op == "jalr":
            following = (regs[ins["rs1"]] + ins["imm"]) & MASK & ~1
            if ins["rd"]:
                regs[ins["rd"]] = pc + 4
        elif op == "la":
            regs[ins["rd"]] = data_labels[ins["target"]]
        elif op in ("lw", "sw"):
            address = (regs[ins["rs1"]] + ins["imm"]) & MASK
            if address not in memory:
                raise Fault(f"No word of memory at {address:#x}.")
            if op == "sw":
                memory[address] = regs[ins["rs2"]]
            elif ins["rd"]:
                regs[ins["rd"]] = memory[address]
        elif ins["rd"]:
            second = regs[ins["rs2"]] if "rs2" in ins else ins["imm"] & MASK
            regs[ins["rd"]] = execute(op, regs[ins["rs1"]], second)
        regs[0] = 0
        pc = following
    return {"regs": regs, "memory": memory, "pc": pc, "labels": data_labels}


def word_address(labels: dict, where: str) -> int:
    """A data word named like arr[2] (or just result, for its first word)."""
    match = re.fullmatch(r"(\w+)(?:\[(\d+)\])?", where)
    return labels[match[1]] + 4 * int(match[2] or 0)


def code_passes(payload: dict, chosen: list[str], test: dict) -> bool:
    try:
        state = run_code(payload, chosen, test)
    except Fault:
        return False
    expect = test["expect"]
    return (all(state["regs"][reg(name)] == value & MASK for name, value in expect.get("registers", {}).items())
            and all(state["memory"].get(word_address(state["labels"], where)) == value & MASK
                    for where, value in expect.get("memory", {}).items())
            and (not expect.get("returned") or state["pc"] == EXIT))


def grade_code(payload: dict, response: dict) -> bool:
    """The response names the line picked for each blank; every one of the room's tests must pass."""
    options = code_blanks(payload)
    chosen = response.get("blanks")
    if (set(response) != {"blanks"} or not isinstance(chosen, list) or len(chosen) != len(options)
            or any(not isinstance(line, str) or line not in choices for line, choices in zip(chosen, options))):
        raise HTTPException(422, "Fill every blank with one of its lines.")
    return all(code_passes(payload, chosen, test) for test in payload["tests"])


def grade_puzzle(payload: dict, response: dict) -> bool:
    kind = payload["kind"]
    if kind == "moves":
        return grade_moves(payload, response)
    if kind == "maze":
        return grade_maze(payload, response)
    if kind == "code":
        return grade_code(payload, response)
    if kind == "walk":
        from .call_stack import grade_walk  # Imported here: call_stack builds on this module.
        return grade_walk(payload, response)
    raise HTTPException(503, "This puzzle type is not supported.")
