"""Grade puzzle gates by replaying the player's button presses, so any valid solution passes."""

from fastapi import HTTPException

R_TYPE = {"add", "sub", "and", "or", "xor", "sll", "srl", "sra", "slt", "sltu"}


def signed(value: int, width: int = 32) -> int:
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value


def execute(op: str, a: int, b: int, width: int = 32) -> int:
    """Apply one ALU operation to width-bit operands; the immediate forms share the register ones."""
    op = "sltu" if op == "sltiu" else op if op in R_TYPE else op.removesuffix("i")
    shift = b & 31
    result = {
        "add": a + b, "sub": a - b, "and": a & b, "or": a | b, "xor": a ^ b,
        "sll": a << shift, "srl": a >> shift, "sra": signed(a, width) >> shift,
        "slt": int(signed(a, width) < signed(b, width)), "sltu": int(a < b),
    }[op]
    return result & ((1 << width) - 1)


def run_program(program: list[dict], initial: dict, width: int = 32) -> list[int]:
    """Run instructions on width-bit registers; x0 stays 0 and values wrap around."""
    mask = (1 << width) - 1
    regs = [0] * 32
    for name, value in initial.items():
        regs[int(name.removeprefix("x"))] = value & mask
    for ins in program:
        second = regs[ins["rs2"]] if "rs2" in ins else ins["imm"] & mask
        if ins["rd"]:
            regs[ins["rd"]] = execute(ins["op"], regs[ins["rs1"]], second, width)
    return regs


def grade_puzzle(payload: dict, response: dict) -> bool:
    """A gate's buttons are fixed instructions; the response is which ones were pressed, in order."""
    if payload["kind"] != "moves":
        raise HTTPException(503, "This puzzle type is not supported.")
    buttons = payload["buttons"]
    moves = response.get("moves")
    if (set(response) != {"moves"} or not isinstance(moves, list) or not moves
            or len(moves) > payload["max_moves"]
            or any(type(move) is not int or not 0 <= move < len(buttons) for move in moves)):
        raise HTTPException(422, f"Press between 1 and {payload['max_moves']} of this gate's buttons.")
    width = payload.get("width", 32)
    regs = run_program([buttons[move] for move in moves], payload.get("initial", {}), width)
    return all(regs[int(name.removeprefix("x"))] == value & ((1 << width) - 1)
               for name, value in payload["goal"].items())
