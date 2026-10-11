# Level brainstorm: puzzles, not quizzes

Ideas for turning each level into a puzzle that follows the COMP 311 Fall 2026
calendar ([`311fa26 Schedule - Full Calendar.pdf`](311fa26%20Schedule%20-%20Full%20Calendar.pdf)).
Levels 1 to 3 are implemented as puzzle gates (see [schema.md](schema.md#aaquestions));
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
- **Every gate says plainly what to do.** Its goal comes first, in one line,
  with the idea it turns on underneath; its steps are numbered beside the
  controls they use; and the run button names whatever is still missing.

## Unit 1 — Programming the Machine

### Level 1 — Wake the Registers (weeks 1–2)
Registers, arithmetic, binary/hex, signed/unsigned, overflow, logical operations, shifts.

**Implemented** as a bank of twenty-two gates in the style of *Calculator: The
Game*, ten per run: the four tutorial gates, then one gate drawn from each topic
pool (hex, masks, flips, signed, overflow, shifts), so every run covers every
topic but runs differ. Each gate shows a target pattern of bulbs above an 8-bit
register. The player presses a few instruction keys (`+1`, `<< 1`, `flip all`,
`and 0x0F`, …) with a small move limit. Bits slide for shifts, a carry ripples
for adds, and the gate opens by itself when every column matches. A robot walks
through the gates while the Chip Chomper chases it. Running out of moves is a
strike, and each strike brings the Chomper closer; on the third it bites the
robot and drags it back a gate, which closes and must be opened again. Undo,
restart, and a hint are always available, and stars reward solving at par.
Because a run sees only one gate per topic, each gate's prompt introduces the
idea it needs.

| Gate | Pool | Idea | New concept |
| --- | --- | --- | --- |
| 1 | tutorial | Press `+1` once | `addi`, the rightmost bulb is worth 1 |
| 2 | tutorial | Slide a light from 1 to 8 | `slli` doubles |
| 3 | tutorial | Shift, then fill the gap | combining instructions |
| 4 | tutorial | Use t1 as an operand | `add` reads two registers |
| 5 | hex | Move 0x03 to 0x31 | hex digits are 4 bits; `slli 4` |
| 6 | masks | Stencil 0xFF down to 0x0A | `andi` masks |
| 7 | flips | Build 0xF0 | `ori` and flipping with `xori 0xFF` |
| 8 | signed | Turn 5 into −5 | two's complement: flip, then add 1 |
| 9 | overflow | Reach −96 with only +64 and +32 | signed overflow |
| 10 | shifts | Shrink −64 to −8 | `srai` keeps the sign; `srli` doesn't |
| 11 | hex | Turn 0x3E into 0x50 | a hex digit carries past F, like 9 + 1 |
| 12 | hex | Build 0x5A from 0x00 | one hex digit (4 bulbs) at a time |
| 13 | masks | Turn 0x9F into 0x93 | `andi 0xF0` clears the right digit; adding first carries |
| 14 | masks | Turn 77 into 14 | `andi 0x0F` keeps the remainder after dividing by 16 |
| 15 | flips | Turn 0xAA into 0x55 | `xori` flips only where its mask is 1 |
| 16 | flips | Turn 0x0F into 0x30 | `ori` only turns bulbs on; `xori` can turn them off |
| 17 | signed | Turn −12 into 12 | negating works both ways: flip, then add 1 |
| 18 | signed | Turn 5 into −120 | the leftmost bulb is worth −128 |
| 19 | overflow | Turn 200 into 14 by adding | unsigned sums wrap around past 255 |
| 20 | overflow | Turn −100 into 56 by subtracting | signed overflow going down |
| 21 | shifts | Shrink −100 to −25 | `srai` halves a negative and keeps its sign |
| 22 | shifts | Turn 48 into −64 | shifting left can overflow into the sign bit |

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

**Implemented** as a story of eight walkthroughs students follow along, lined up
with Lectures 6 and 7 (procedures, the calling convention, stack frames,
recursion). The rooms play in order, each building on the last, so the level
doubles as a study tool to replay. (Its first design, a bank of
answer-the-question rooms (Frame Builder, Recursion Elevator, and Code Lawyer),
was replaced; the code stays for runs started before the change.)

Each room is a short program played like a movie. Play runs it a line at a time,
leaving each line up long enough to read its caption (lines repeated on deeper
floors go faster), while a bar under the caption fills until the next line; Step
and Back move by hand. The listing lights the line that just ran, the stack
hangs from the top of memory as a tower of frames (a floor per call, the robot
riding `sp`, each saved word filling in as it's stored), the registers the room
watches sit above the code, and a caption says what the line did with its real
values ("Call triple: ra = 0x10C, the address of the next line, then jump").
Notes on key lines add the why.

When the walk reaches a move, it stops and the student makes it: the call, what
a frame saves, where to keep a value across a call, the base case. A good move
is written into the program (in blue) and the walk goes on. A wrong move plays
out on the tower at speed, so students see exactly what breaks (`ra` lost and
the function returning to itself forever, the Chomper's `s0` changed, the tower
running off the bottom of the stack), then the caption explains why and the room
rewinds to the move. Wrong moves cost a star, never a strike. When the program
returns, the Chip Chomper checks the contract (the right value back in `a0`, the
`s` registers and `sp` as it left them) and the gate opens.

| Room | Title | Program | The student's move | What it shows |
| --- | --- | --- | --- | --- |
| 1 | The call | `plus1` calls `triple` | `jal ra, triple` or `j triple` | `jal` leaves a way back in `ra`; `j` doesn't |
| 2 | The way back | `plus2` calls `inc` twice | push `ra`, or nothing | a function that calls must save `ra` first |
| 3 | Keeping a value | `plusx` needs x after calling `inc` | keep x in `t0`, or on the stack | `t` registers don't survive a call; the frame does |
| 4 | Borrowed registers | `plusx` keeps x in `s0` | save `ra` and `s0`, only `ra`, or only `s0` | a function that uses an `s` register saves it |
| 5 | Down the tower | `sqr(3)` | save `ra` and `s0`, or only `ra` | every call gets its own frame |
| 6 | The bottom floor | `fact(3)` | stop at x ≤ 1, never, or at x ≥ 1 | recursion needs a base case, or the stack runs out |
| 7 | Two calls | `fib(3)` | save `ra`, `s0`, and `s1`, or only `ra` and `s0` | save every `s` register you use |
| 8 | Outrun the Chomper | `fact(6)` while the heap climbs | a 2-word frame, a 3-word one, or only `ra` | every saved word is paid on every floor |

Ideas not built yet:

- **The earlier rooms as practice:** Frame Builder (lay out a frame), Recursion
  Elevator (type each floor's values), and Code Lawyer (find the line that
  breaks a rule) could come back as an optional practice mode after the story.
- **Register Heist:** values needed after a call sit in registers, and the
  callee scrambles every `t` and `a` register. Choose what to save, with stars
  for the fewest saves.
- **Return tickets:** before every step, predict where the PC goes next: PC + 4,
  a branch or `jal` target and the `ra` it writes, or a `jalr` destination.
- **Call-tree scrubber:** `fib(4)` as a tree. Scrub through time, and the stack
  is always the path from the root to the current call, so its depth isn't the
  number of calls.
- **Debugger room:** step into, step over, step out, and watch a stack word to
  find the line where a value goes wrong within a step budget.
- **Too many arguments:** a function with ten arguments: the first eight travel
  in `a0`-`a7`, and the rest go on the stack at the right offsets.
- **Base-case picker:** choose the base case; a wrong one recurses until the
  stack runs into the heap.
- **Smashed stack:** a loop writes one word past a local array and overwrites
  the saved `ra`. Find the off-by-one.
- **Backtrace detective:** rebuild the call chain from a stack dump after a
  crash, using the saved `ra` values (and frame pointers, which Level 3 leaves
  out).
- **Other finales:** an audit boss of twenty calls in a row, climbing out from
  five calls deep with every epilogue on the way, or a relay through `main`,
  `a`, `b`, and `c` with the answer assembled on the way back up.

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
  too, e.g., keys that are `lw`/`sw` with different offsets. Level 3 builds a
  calling machine on it in `server/call_stack.py` (mirrored in
  `levels/level_3/call_machine.gd`, which also records a trace for the tower).
- Levels 5–6 need a gate-level circuit simulator with clocking.
- New puzzle kinds are added as `puzzle` question payloads with a new `kind`, so
  content stays authored in the database. A new room gives the runner its lines
  through `guide()`, so the instruction guide can explain every instruction on
  the gate; a new instruction needs an entry in `ui/instruction_guide.gd`.
- The game currently has six level slots plus a challenge. This plan needs eight
  plus the boss, which means adding `level_7`/`level_8` buttons in
  `control_center.tscn` and renaming the existing scenes.
