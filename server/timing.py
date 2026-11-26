"""Grade Level 4, the Timing Lab: waveform diagrams, then pipelining, following the lectures on
timing analysis, pipelining, and the five-stage CPU.

Wave rooms (kind "wave") show a small circuit and a timing grid. Time is cut into ticks (a room's
`tick` and `unit` say how long one is, such as 10 ps). The inputs' waveforms are given; the player
draws the waveform of each signal in `draw`, one level (0 or 1) per tick:

    {"waves": {"C": [1, 1, 1, 1, 0, 0], "Y": [1, 1, 1, 1, 1, 1]}}

The server simulates the circuit and the drawing must match it tick for tick.

- A gate (`not`, `and`, `or`, `xor`, `nand`, `nor`) with a propagation delay of d ticks shows at
  tick t what its inputs were at tick t - d. Before that it shows what its inputs at tick 0 give:
  the circuit starts settled, as in the lectures' diagrams.
- A positive-edge-triggered D flip-flop (`dff`) takes the value D had just before each rising edge
  of its clock, and shows it d ticks later (its clk-to-q delay). Until then it holds `start`.

Table rooms (kind "table") are the pipelining half. A room shows a circuit and any of: a
pipeline diagram to fill in (`chart`: a row per operation, a column per cycle), a table with
blanks (a longest path, a clock period, a forwarding mux setting), and questions under it
(`asks`). A diagram comes in two forms. With `starts`, the player places each operation's first
stage and the rest follow. With `stalls`, instructions are fetched as early as they can be and
the player holds each one in decode for some cycles, which repeats the held stage in the diagram
the way the lectures draw a stall. A room can also have `clocks` to tune: each lists the `path` a
signal has to cross between two clock ticks (a clk-to-q delay, then the logic), and its key is the
shortest period that fits, the path's total. The answer is one string per blank: a number for
each chart row (its start cycle, or its stall cycles), each clock's period, then the table's
blanks in reading order, then the questions:

    {"cells": ["0", "1", "2", "980", "500"]}

A cell is right when it holds the blank's key as a number (or the same text). The keys are part of
the room, like every puzzle's goal.
"""

from fastapi import HTTPException

GATES = {
    "not": lambda a: 1 - a[0],
    "and": lambda a: int(all(a)),
    "or": lambda a: int(any(a)),
    "xor": lambda a: sum(a) % 2,
    "nand": lambda a: 1 - int(all(a)),
    "nor": lambda a: 1 - int(any(a)),
}
MOST_TICKS = 80  # The longest timing grid a room may have.


def level(transitions: list, ticks: int) -> list[int]:
    """A waveform given as [[tick, value], ...] (the value it takes from each tick on), as one
    level per tick."""
    wave, value = [], 0
    changes = dict((int(at), int(to)) for at, to in transitions)
    for t in range(ticks):
        value = changes.get(t, value)
        wave.append(value)
    return wave


def clock(spec: dict, ticks: int) -> list[int]:
    """A clock: high for the first half of each period, with a rising edge at tick `rise`."""
    return [int((t - spec["rise"]) % spec["period"] < spec["period"] // 2) for t in range(ticks)]


def simulate(payload: dict) -> dict[str, list[int]]:
    """Every signal of a wave room, one level per tick: its inputs, its clock, and each gate's
    output. Gates are listed inputs first, so one pass settles them."""
    ticks = payload["ticks"]
    waves = {name: level(changes, ticks) for name, changes in payload["signals"].items()}
    if "clock" in payload:
        waves[payload["clock"]["name"]] = clock(payload["clock"], ticks)
    delays = payload.get("delays", {})
    for gate in payload["circuit"]["gates"]:
        op, delay = gate["op"], delays.get(gate["op"], 0)
        if op == "dff":
            data, clk = waves[gate["in"][0]], waves[gate["clk"]]
            value, wave = payload.get("start", {}).get(gate["out"], 0), []
            for t in range(ticks):
                edge = t - delay
                if edge >= 1 and clk[edge] and not clk[edge - 1]:
                    value = data[edge - 1]
                wave.append(value)
        else:
            sources = [waves[name] for name in gate["in"]]
            wave = [GATES[op]([source[max(t - delay, 0)] for source in sources]) for t in range(ticks)]
        waves[gate["out"]] = wave
    return waves


def edges(wave: list[int]) -> list[tuple[int, int]]:
    """Where a waveform changes: (tick, new value) for each edge."""
    return [(t, wave[t]) for t in range(1, len(wave)) if wave[t] != wave[t - 1]]


def grade_wave(payload: dict, response: dict) -> bool:
    drawn = response.get("waves")
    names, ticks = payload["draw"], payload["ticks"]
    if (set(response) != {"waves"} or not isinstance(drawn, dict) or set(drawn) != set(names)
            or any(not isinstance(wave, list) or len(wave) != ticks or any(type(v) is not int or v not in (0, 1) for v in wave)
                   for wave in drawn.values())):
        raise HTTPException(422, f"Draw each of this room's signals as {ticks} levels of 0 or 1.")
    waves = simulate(payload)
    return all(drawn[name] == waves[name] for name in names)


def table_keys(payload: dict) -> list[str]:
    """A table room's blanks, in the order they are answered: for each row of its pipeline diagram
    the cycle it starts in (or, in a diagram with hazards, the cycles it is held in decode), the
    period of each clock to tune (the time its signal's trip takes), the table's blanks row by
    row, then the questions under it."""
    chart = payload.get("chart", {})
    keys = [str(count) for count in chart.get("starts", chart.get("stalls", []))]
    keys += [str(sum(time for _, time in clock["path"])) for clock in payload.get("clocks", [])]
    keys += [str(cell["blank"]) for row in payload.get("rows", []) for cell in row if isinstance(cell, dict)]
    return keys + [str(ask["blank"]) for ask in payload.get("asks", [])]


def tidy(text: str) -> str:
    """What a cell says, however it was typed: spaces and commas dropped, any run of question
    marks as "??", and a number without leading zeros or trailing decimal zeros (1.20 is 1.2)."""
    text = text.replace(" ", "").replace(",", "")
    if text and set(text) == {"?"}:
        return "??"
    whole, dot, part = text.partition(".")
    if not (whole + part).isascii() or not (whole + part).isdigit() or (dot and not part):
        return text.lower()
    part = part.rstrip("0")
    return str(int(whole or "0")) + ("." + part if part else "")


def grade_table(payload: dict, response: dict) -> bool:
    keys = table_keys(payload)
    cells = response.get("cells")
    if (set(response) != {"cells"} or not isinstance(cells, list) or len(cells) != len(keys)
            or any(not isinstance(cell, str) or not cell.strip() or len(cell) > 16 for cell in cells)):
        raise HTTPException(422, "Fill in every blank.")
    return [tidy(cell) for cell in cells] == [tidy(key) for key in keys]
