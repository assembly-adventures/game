"""Grade Level 3, the Call Stack Tower: procedures, the calling convention, stack frames, and
recursion.

Every room runs real code on one small machine: instructions from CODE_BASE, and a stack of
words below STACK_TOP that hold junk until something is saved there. The Chip Chomper is the
caller. Before each of its calls it fills every register with junk (different for each register
and each call, so a value that wasn't kept shows), sets sp to the top of the stack and ra to
CHOMPER, puts the call's arguments in a0-a7, and jumps to the room's entry; the call ends when
the code returns to CHOMPER. The level's rooms are walkthroughs:

- "walk": the player follows a short program line by line and makes its moves at its moments:
  places in the code with a few options, each a block of lines ("lines") or a stack frame whose
  prologue goes there and whose epilogue goes at the epilogue mark ("frame"). The answer is the
  option picked at each moment; it passes when the program then keeps the contract on every one
  of the Chomper's calls. Any working set of picks passes.
"""

import re

from fastapi import HTTPException

from .puzzles import BRANCHES, MASK, REGISTERS, branch_taken, execute, parse_line, reg

CODE_BASE = 0x100  # The first instruction.
CHOMPER = 0x400  # The Chomper's own code: returning here ends a call.
STACK_TOP = 0x7FF0
JUNK = 0xDEADBEEF  # What a stack word holds before anything is saved in it.
STACK_WORDS = 32  # Words of stack below STACK_TOP, unless a room says otherwise.
STEP_LIMIT = 3000  # Instructions a call may take before it counts as never returning.
SAVED = [reg(f"s{n}") for n in range(12)]


class Fault(Exception):
    """The code would crash: a jump to where there's no code, a load or store off the stack or
    off a word boundary, a stack word the heap already ate, or a call that never returns."""

    def __init__(self, kind: str, at: int = 0):
        super().__init__(kind)
        self.kind = kind
        self.at = at


def restored(name: str) -> bool:
    """ra and the s registers are the caller's, so a callee that saves them puts them back.
    Anything else it saves (an argument, a temporary) is for its own code to read back."""
    return name == "ra" or re.fullmatch(r"s\d+", name) is not None


def frame_lines(frame: list[str]) -> tuple[list[str], list[str]]:
    """The prologue and epilogue a frame layout writes, the way the lectures write them: make
    room, save each register from the top word down, and on the way out restore ra and the s
    registers from sp+0 up and give the room back. An empty frame writes nothing."""
    size = 4 * len(frame)
    if not frame:
        return [], []
    prologue = [f"addi sp, sp, -{size}"] + [f"sw {name}, {4 * k}(sp)" for k, name in reversed(list(enumerate(frame)))]
    epilogue = [f"lw {name}, {4 * k}(sp)" for k, name in enumerate(frame) if restored(name)] + [f"addi sp, sp, {size}"]
    return prologue, epilogue


def moments(payload: dict) -> list[dict]:
    """A walkthrough's moments, in the order they appear in its code."""
    return [entry for entry in payload["code"] if "moment" in entry]


def picked(payload: dict, choices) -> list[dict | None]:
    """The option picked at each moment, or None where nothing is picked yet."""
    choices = list(choices or [])
    return [entry["options"][choices[k]] if k < len(choices) and choices[k] is not None and choices[k] >= 0 else None
            for k, entry in enumerate(moments(payload))]


def assemble(payload: dict, choices=None) -> tuple[list[str], dict]:
    """The room's program, its lines from CODE_BASE 4 bytes apart, with the walkthrough's picked
    moves written in, and the address of each label."""
    options = picked(payload, choices)
    frame = []
    for entry, option in zip(moments(payload), options):
        if entry["moment"] == "frame" and option is not None:
            frame = option["frame"]
    prologue, epilogue = frame_lines(list(frame))
    lines, labels = [], {}
    moment = 0
    for entry in payload["code"]:
        if "label" in entry:
            labels[entry["label"]] = CODE_BASE + 4 * len(lines)
        elif "line" in entry:
            lines.append(entry["line"])
        elif entry.get("epilogue"):
            lines += epilogue
        elif "moment" in entry:
            option = options[moment]
            moment += 1
            if option is not None:
                lines += prologue if entry["moment"] == "frame" else option["lines"]
    return lines, labels


def junk(call: int, number: int) -> int:
    """What the Chomper leaves in register x<number> before its call number <call> (from 0)."""
    return 0x5A00 + 0x100 * call + number


def setup(payload: dict, index: int) -> tuple[list[int], dict]:
    """The registers and stack the Chomper's call number <index> starts with."""
    regs = [0] + [junk(index, n) for n in range(1, 32)]
    regs[reg("sp")] = STACK_TOP
    regs[reg("ra")] = CHOMPER
    for name, value in payload["calls"][index].get("args", {}).items():
        regs[reg(name)] = value & MASK
    words = payload.get("stack_words", STACK_WORDS)
    return regs, {STACK_TOP - 4 * k: JUNK for k in range(1, words + 1)}


def heap_line(payload: dict, steps: int) -> int:
    """The lowest stack address the heap hasn't eaten after <steps> instructions. In the finale
    the Chomper eats one word every `every` instructions from instruction `start`, from the
    bottom of the stack up; other rooms have no Chomper in the heap."""
    bottom = STACK_TOP - 4 * payload.get("stack_words", STACK_WORDS)
    chomper = payload.get("chomper")
    if not chomper or steps < chomper["start"]:
        return bottom
    return bottom + 4 * ((steps - chomper["start"]) // chomper["every"] + 1)


def run(payload: dict, lines: list[str], labels: dict, index: int) -> dict:
    """The Chomper's call number <index>. Returns the registers and stack it ended with, the pc,
    why it crashed if it did ({"kind", "at"}), and its calls in the order they were made: each
    with the function, its depth, a0, a1 and s0 on entry, the ra it was given, and what it
    returned. A call is a jal that links ra; a return is a jump to ra that links nothing."""
    program = [parse_line(line) for line in lines]
    regs, memory = setup(payload, index)
    functions = {address: name for name, address in labels.items()}
    end = CODE_BASE + 4 * len(program)
    entry = payload["entry"]
    calls = [{"function": entry, "depth": 1, "a0": regs[10], "a1": regs[11], "s0": regs[8], "ra": CHOMPER}]
    open_calls = [calls[0]]
    pc = labels[entry]
    steps = 0
    fault = None
    try:
        while pc != CHOMPER:
            if pc % 4 or not CODE_BASE <= pc < end:
                raise Fault("code", pc)
            steps += 1
            if steps > STEP_LIMIT:
                raise Fault("loop")
            ins = program[(pc - CODE_BASE) // 4]
            op = ins["op"]
            following = pc + 4
            if op in BRANCHES:
                if branch_taken(op, regs[ins["rs1"]], regs[ins["rs2"]]):
                    following = labels[ins["target"]]
            elif op == "jal":
                following = labels[ins["target"]]
                if ins["rd"]:
                    regs[ins["rd"]] = pc + 4
                if ins["rd"] == reg("ra"):
                    record = {"function": functions.get(following, ins["target"]), "depth": len(open_calls) + 1,
                              "a0": regs[10], "a1": regs[11], "s0": regs[8], "ra": pc + 4}
                    calls.append(record)
                    open_calls.append(record)
            elif op == "jalr":
                following = (regs[ins["rs1"]] + ins["imm"]) & MASK & ~1
                if ins["rd"]:
                    regs[ins["rd"]] = pc + 4
                elif ins["rs1"] == reg("ra") and open_calls:
                    open_calls.pop()["ret"] = regs[10]
            elif op in ("lw", "sw"):
                address = (regs[ins["rs1"]] + ins["imm"]) & MASK
                if address % 4:
                    raise Fault("aligned", address)
                if address not in memory:
                    raise Fault("memory", address)
                if address < heap_line(payload, steps):
                    raise Fault("overflow", address)
                if op == "sw":
                    memory[address] = regs[ins["rs2"]]
                elif ins["rd"]:
                    regs[ins["rd"]] = memory[address]
            elif ins["rd"]:
                second = regs[ins["rs2"]] if "rs2" in ins else ins["imm"] & MASK
                regs[ins["rd"]] = execute(op, regs[ins["rs1"]], second)
            regs[0] = 0
            pc = following
    except Fault as error:
        fault = {"kind": error.kind, "at": error.at}
    return {"regs": regs, "memory": memory, "pc": pc, "fault": fault, "steps": steps, "calls": calls}


def audit(payload: dict, choices=None) -> list[dict]:
    """Every one of the Chomper's calls, checked against the contract: it must return (no crash),
    with the expected value in a0 if the call names one, and with s0-s11 and sp as the Chomper
    set them. Each row lists what went wrong ("value", a register's name, "sp", or a fault kind)."""
    lines, labels = assemble(payload, choices)
    rows = []
    for index, call in enumerate(payload["calls"]):
        before, _ = setup(payload, index)
        state = run(payload, lines, labels, index)
        regs = state["regs"]
        if state["fault"]:
            problems = [state["fault"]["kind"]]
        else:
            problems = ["value"] if "expect" in call and regs[10] != call["expect"] & MASK else []
            problems += [REGISTERS[n] for n in SAVED if regs[n] != before[n]]
            problems += ["sp"] if regs[reg("sp")] != STACK_TOP else []
        rows.append({"passed": not problems, "problems": problems, "state": state})
    return rows


def grade_walk(payload: dict, response: dict) -> bool:
    choices = response.get("choices")
    entries = moments(payload)
    if (set(response) != {"choices"} or not isinstance(choices, list) or len(choices) != len(entries)
            or any(type(choice) is not int or not 0 <= choice < len(entry["options"])
                   for choice, entry in zip(choices, entries))):
        raise HTTPException(422, "Pick one of the options at each of this walkthrough's moments.")
    return all(row["passed"] for row in audit(payload, choices=choices))
