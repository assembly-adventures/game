# Level brainstorm: puzzles, not quizzes

Ideas for turning each level into a puzzle that follows the COMP 311 Fall 2026
calendar ([`311fa26 Schedule - Full Calendar.pdf`](311fa26%20Schedule%20-%20Full%20Calendar.pdf)).
Levels 1 and 2 are implemented as puzzle gates (see [schema.md](schema.md#aaquestions));
everything else here is a proposal.

## Design principles

- **Players manipulate a system and watch it run.** The simulation is the feedback, not a red X.
- **More than one answer can be correct.** The server simulates the player's
  answer and checks the goal, so any valid solution passes.
- **Stars for efficiency.** Fewest instructions, gates, or cycles against a par
  gives strong students a reason to replay.
- **Story first.** Each level repairs a zone of the processor that the Chip
  Chomper corrupted. Wrong attempts "feed the Chomper" instead of showing a red X.
- **Each room answers the calendar's guiding question** for the day it is taught.

## Unit 1 — Programming the Machine

### Level 1 — Wake the Registers (weeks 1–2)
Registers, arithmetic, binary/hex, signed/unsigned, overflow, logical operations, shifts.

**Implemented** as ten gates in the style of *Calculator: The Game*. Each gate
shows a target pattern of bulbs above an 8-bit register. The player presses a
few instruction keys (`+1`, `<< 1`, `flip all`, `and 0x0F`, …) with a small
move limit. Bits slide for shifts, a carry ripples for adds, and the gate opens
by itself when every column matches. A robot walks through the gates while the
Chip Chomper chases it. Running out of moves is a strike, and each strike brings
the Chomper closer; on the third it bites the robot and drags it back a gate,
which closes and must be opened again. Undo, restart, and a hint are always
available, and stars reward solving at par.

| Gate | Idea | New concept |
| --- | --- | --- |
| 1 | Press `+1` once | `addi`, the rightmost bulb is worth 1 |
| 2 | Slide a light from 1 to 8 | `slli` doubles |
| 3 | Shift, then fill the gap | combining instructions |
| 4 | Use x6 as an operand | `add` reads two registers |
| 5 | Move 0x03 to 0x31 | hex digits are 4 bits; `slli 4` |
| 6 | Stencil 0xFF down to 0x0A | `andi` masks |
| 7 | Build 0xF0 | `ori` and flipping with `xori 0xFF` |
| 8 | Turn 5 into −5 | two's complement: flip, then add 1 |
| 9 | Reach −96 with only +64 and +32 | signed overflow |
| 10 | Shrink −64 to −8 | `srai` keeps the sign; `srli` doesn't |

### Level 2 — Memory Maze (weeks 3–4)
Memory, addresses, `lw`/`sw`, arrays, comparisons, branches, loops, translation from C.

**Implemented** as a bank of sixteen rooms, lined up with Lecture 4 (loads,
stores, accessing memory). Each run plays ten: the four tutorial rooms, then one
memory, one branches, and one loops room drawn at random, both procedure rooms
(stack frames give students the most trouble), and the race.
The draw is the level's `draw` rule in the database, so it can change without
new code.

Maze rooms are small mazes of memory words seen from above, in row-major order
from `0x4000` as in the lecture, so a step right is `+4` and a step down is
`+4 × width`. The player steers the robot with the arrow keys (or WASD, or by
clicking the next cell) and clicks any word to load it into a register or store
one there: base + offset reaches the whole room, and the menu shows the math
(`arr[3] · 0x400C = a0 + 12`). Every action is written into the program as a
real RISC-V line, so the code is the trail the robot leaves. Walls are protected
memory, doors open when their word holds the right code, and glass holds words
you can reach but not stand on. In teaching rooms the player taps `loop:`,
teaches the robot one pass by hand, and taps a Repeat key (a branch) to let it
run the rest. An action that would crash (walking into a wall, glass, or a
locked door; a loop that never ends) plays out to the crash, explains it, and
is taken back without a strike. In the race the Chip Chomper eats an int every
4 instructions, so a sloppy loop loses.

Code rooms are short programs with blank lines. The player clicks a blank (or
presses its number) to pick its line, then runs the room's tests. The robot
plays the PC: it walks the program by address, following branches and jumps,
while the registers, the data words, and the stack (with `sp` pointing at its
word) change beside it. Tests use different inputs, like x = 3 and x = 7, so
the program has to work in general. A run that fails a test is a
strike, and a crash (a misaligned or missing word, or a jump to junk) says
where it happened. Strikes, the drag-back, hints, and stars work as in Level 1.
Registers go by their ABI names, with each x-name in small print.

| Room | Pool | Kind | Idea | New concept (lecture slide) |
| --- | --- | --- | --- | --- |
| 1 | tutorial | maze | Walk to the exit | an int is 4 bytes: each step is +4 |
| 2 | tutorial | maze | Load `arr[3]` of `5 90 100 40 11` | `lw`, R[rd] = M[R[rs1] + offset] (36–41) |
| 3 | tutorial | maze | `arr[3]` is a door that needs 8 | `sw`, M[R[rs1] + offset] = R[rs2] (42–43) |
| 4 | tutorial | maze | Cross a long corridor | `loop:` + `bne a0, a1, loop` |
| 5 | memory | maze | Go down two rows | memory is one line: down is +16 in a 4-word room |
| 6 | memory | maze | A door holds 7 and needs 12 | load/store architecture: `lw`, `addi`, `sw` (21) |
| 7 | memory | maze | Swap two doors' codes | two registers; negative offsets |
| 8 | memory | code | `sum = arr[i] + arr[i+1]` | `slli` by 2 for an int's offset, then base + offset |
| 9 | branches | code | `if (x < 5) … else …` | `slti`, branch to else, jump over it |
| 10 | branches | maze | Walk to the first 0 | a sentinel loop: `bne t1, x0, loop` |
| 11 | loops | maze | Copy `a[]` into the vault below | a loop body relative to `a0`; `blt` vs `bge` |
| 12 | loops | maze | Sum `values[i]` while `i < 6` | the lecture's loop, with `blt t0, t6` (45) |
| 13 | loops | code | `for (i = 3; i >= 0; i--) arr[i] += 2` | a countdown loop: `bge` vs `bne` |
| 14 | procedures | code | `a0 = func(6) + 1` | `jal` saves PC + 4 in `ra`; `jalr` returns |
| 15 | procedures | code | `result = func(6)` from a stack frame | save `ra` before `jal`; store before restoring |
| 16 | finale | maze | Race the Chip Chomper | a loop costs its body times its passes |

Ideas not built yet:

- **Branch railroad:** set branch conditions (`beq`/`bne`/`blt`/`bge`) so a train
  reaches the right station for given inputs (forward branches and if/else).
- **Hidden test arrays:** grade a loop against arrays the player can't see
  (sum, count evens, find max), so it has to work in general.

### Level 3 — Call Stack Tower (weeks 5–6)
Procedures, `jal`/`jalr`, arguments and return values, calling convention, stack frames, recursion.

- **Tower builder:** nested calls stack frames into a tower. Place `ra`, saved
  registers, and locals at the right `sp` offsets, or the tower topples on return.
- **Register heist:** decide who saves what (caller- vs callee-saved) so no
  value gets clobbered. The run shows exactly which value was "stolen".
- **Return-address boomerang:** fix a program where `ra` gets overwritten.
- **Recursion elevator:** predict each `factorial`/`fib` frame going down and
  each return value coming up.

### Level 4 — Decoder Vault (weeks 6–7)
Machine-code encoding, R/I/S/B/U/J formats, wide immediates, assembling, linking, loading.

- **Bit-flip vault:** flip bits in a corrupted 32-bit word until the live
  disassembly reads the target instruction.
- **Format jigsaw:** field pieces only fit their widths, including the scrambled
  S/B immediates.
- **Big-number bridge:** load a 32-bit constant with `lui` + `addi`, including the
  sign-extension trap when the low 12 bits are 0x800 or more.
- **Linker patch-up:** fill a symbol table and fix branch/jump offsets so two
  object fragments link.

## Unit 2 — Inside the Processor

### Level 5 — Circuit Foundry (weeks 6–10)
Transistors and CMOS gates, truth tables, Boolean expressions, muxes, decoders,
adders, ALU, clocks, flip-flops, registers, register files.

- **CMOS switchboard:** wire PMOS pull-up and NMOS pull-down networks to match a
  truth table. Shorts and floating outputs show visually.
- **Gate golf:** match a truth table in the fewest gates, with a NAND-only bonus.
- **Mux/decoder routing:** use select lines to route signals, then build a 4:1
  mux from 2:1 muxes.
- **Build-an-ALU:** chain full adders, add subtraction with invert + carry-in, and
  add an op selector. Test it against the RISC-V operations from Level 1.
- **Clock-tick memory:** draw Q for a D flip-flop from clk and D, then wire a
  register-file write so a value survives the clock edge.

### Level 6 — Datapath Plumber (weeks 10–12)
Register transfer, the single-cycle datapath for R-type, immediate, load, store,
branch, and jump instructions, immediate generation, control, critical path.

- **Plumbing puzzle:** connect the PC, instruction memory, register file, ALU,
  data memory, and muxes so an instruction's data flows correctly.
- **Control panel:** set RegWrite, ALUSrc, MemRead, MemWrite, MemToReg, Branch,
  and ALUOp for each arriving instruction. Wrong settings visibly corrupt state.
- **Critical-path race:** components have delays. Find the slowest path to set
  the clock period.

## Unit 3 — Making Computers Fast

### Level 7 — Pipeline Rush (weeks 12–14)
Performance equation, five-stage pipeline, data hazards, forwarding, stalls,
load-use hazards, control hazards, flushing.

- **Assembly-line traffic:** instructions drive through IF/ID/EX/MEM/WB lanes.
  Insert bubbles, draw forwarding wires, or reorder instructions to avoid crashes
  in the fewest cycles.
- **Load-use trap:** only reordering removes the stall.
- **Branch flush gamble:** mispredictions flush in-flight instructions. Pick a
  strategy that hits a CPI target.
- **Performance tuner:** trade clock rate, CPI, and instruction count to beat a
  runtime target.

### Level 8 — Memory Wall (weeks 15–16)
Locality, memory hierarchy, cache address breakdown, hits and misses, AMAT, and
optionally virtual memory.

- **Cache librarian:** split incoming addresses into tag/index/offset and place
  blocks, scored live on hits and misses. Direct-mapped first, then set-associative.
- **Locality loop tuner:** reorder a traversal (row- vs column-major) to raise the hit rate.
- **AMAT tuner:** spend a budget on cache size, block size, and associativity.

## Final — Boss fight against the Chip Chomper (week 16)
"How does a program become hardware activity, and what determines its speed?"

One program is followed end to end: written (Unit 1), encoded (Level 4), run
through the datapath (Level 6), pipelined (Level 7), and fed data through the
cache (Level 8). The Chomper attacks one layer at a time (flipped bits, a smashed
stack frame, a wrong control signal, an injected hazard, cache thrashing), and
the player repairs each layer before time runs out.

## Syllabus coverage

| Calendar topic | Level |
| --- | --- |
| Abstraction layers, registers, operands, arithmetic | 1 |
| Binary/hex, signed/unsigned, overflow, logical operations, shifts | 1 |
| Memory, `lw`/`sw`, arrays; comparisons, branches, loops, conditionals | 2 |
| Procedures, `jal`/`jalr`, calling convention, stack frames, recursion | 3 |
| Encoding, instruction formats, wide immediates, assembling, linking, loading | 4 |
| Transistors and CMOS gates*, gates, Boolean expressions, muxes, decoders | 5 |
| Adders, ALU, clocks, flip-flops, registers, register files | 5 |
| Register transfer, single-cycle datapath, control, critical path | 6 |
| Performance equation, pipelining, hazards, forwarding, stalls, flushing | 7 |
| Locality, memory hierarchy, caches, AMAT (virtual memory optional) | 8 |
| Whole-course synthesis | Boss |

\* CMOS is on the [course website's schedule](https://www.cs.unc.edu/~kakiryan/teaching/311-fa26/311-fa26.html), not the PDF.

## Implementation notes

- Levels 1–4, 7, and the boss can share one RISC-V interpreter. Level 1 has
  added it as `server/puzzles.py`, mirrored in `levels/level_1/puzzle_room.gd`
  so the game can animate each press. The instruction-key format fits Levels 2–4
  too, e.g., keys that are `lw`/`sw` with different offsets.
- Levels 5–6 need a gate-level circuit simulator with clocking.
- New puzzle kinds are added as `puzzle` question payloads with a new `kind`, so
  content stays authored in the database. A new room gives the runner its lines
  through `guide()`, so the instruction guide can explain every instruction on
  the gate; a new instruction needs an entry in `ui/instruction_guide.gd`.
- The game currently has six level slots plus a challenge. This plan needs eight
  plus the boss, which means adding `level_7`/`level_8` buttons in
  `control_center.tscn` and renaming the existing scenes.
