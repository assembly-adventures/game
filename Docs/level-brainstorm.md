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

**Implemented** as a bank of seventeen rooms, lined up with Lectures 6 and 7
(procedures, the calling convention, stack frames, recursion). Each run plays
ten: three tutorial rooms (one of each kind), then two Frame Builder, two
Recursion Elevator, and two Code Lawyer rooms drawn at random, and the finale.
The draw is the level's `draw` rule in the database, like Level 2's.

The stack hangs from the top of memory like a tower: every call adds a floor
below, and the robot rides `sp` like an elevator. The Chip Chomper is the caller
and the contract's enforcer. It calls the room's function, filling every
register with junk before each call, and its audit table checks each one: the
right answer back in `a0`, every `s` register and `sp` as it left them, and no
crash. Following the calling convention is the only way to pass every call, and
any frame that does passes.

- **Frame Builder:** click blocks (`ra`, `s0`, `a0`, …) to lay out a function's
  frame from `sp+0` up, then move or remove them on the tower. The game writes
  the prologue and epilogue the way the lectures do (for two words,
  `addi sp, sp, -8` and an `sw` per block on the way in; an `lw` for `ra` and
  each `s` block and `addi sp, sp, 8` on the way out), and the run plays the
  Chomper's calls on the tower. A frame bigger than it needs to be costs a
  star, so a leaf function's best frame is no frame at all.
- **Recursion Elevator:** type values on the chain of calls of one run (each
  floor's arguments, the `ra` or `s0` it saves, or what it returns), then ride:
  the robot goes down a floor per call and back up a floor per return, and each
  value turns green or red.
- **Code Lawyer:** a function is on trial. Click the line that breaks the
  calling convention and name the rule it breaks: callers save the `t` and `a`
  registers they still need, callees save the `s` registers they use, save `ra`
  before calling again, and put `sp` back before returning. **Watch** runs the
  Chomper's audit for free, so the crime can be seen before objecting.
- **Finale:** a Frame Builder room for `fact` while the Chomper climbs from the
  heap, eating a stack word every 8 instructions. Only a frame that saves just
  what `fact` needs lets `fact(6)` finish before the heap reaches it.

Every gate states its goal in one line, with the idea it turns on underneath,
and numbers its steps beside the controls they use (in a Code Lawyer room,
step 2 is on the code itself). The run button says what is still missing, and
an empty frame's listing marks where its prologue and epilogue will go.
Strikes, the drag-back, hints, and stars work as in Levels 1 and 2; a hint
appears over the tower so the controls never move, and a run that breaks the
contract shows which call broke it and how. Level 2's two procedure rooms stay
as a preview. The instruction guide adds `mul`, `div`, `rem`, `jr`, and `ret`.

| Room | Pool | Kind | Idea | New concept |
| --- | --- | --- | --- | --- |
| 1 | tutorial | frame | `plus1` calls `triple` | `jal` overwrites `ra`, so save it first |
| 2 | tutorial | elevator | `sqr(3)` rides down to `sqr(1)` | each call is a new floor; returns come back up in reverse |
| 3 | tutorial | lawyer | `double` uses `s1` | a callee saves the `s` registers it uses |
| 4 | frames | frame | `sqr` keeps x in `s0` | save the caller's `s0` before borrowing it |
| 5 | frames | frame | `sqr` reads x back with `lw t1, 0(sp)` | a spilled argument is read back, not restored |
| 6 | frames | frame | `fib` makes two calls | two values must survive the second call |
| 7 | frames | frame | `gcd`'s call is the last thing it does | nothing used after the call: only `ra` needs saving |
| 8 | frames | frame | `max3` calls no one | a leaf that uses only `t` registers needs no frame |
| 9 | elevator | elevator | `fact(4)` | return values multiply on the way up |
| 10 | elevator | elevator | `gcd(30, 18)` | arguments change floor by floor; the answer passes straight up |
| 11 | elevator | elevator | `main` calls `sqr(4)` | `jal` puts PC + 4 in `ra`; inner calls return into `sqr` |
| 12 | elevator | elevator | `fact(5)` keeps x in `s0` | each frame saves its caller's `s0` |
| 13 | lawyer | lawyer | `plus2` calls `inc` twice | save `ra` before calling again |
| 14 | lawyer | lawyer | `fact` keeps x in `t0` | `t` registers don't survive a call |
| 15 | lawyer | lawyer | `gcd`'s audit crashes | put `sp` back before returning |
| 16 | lawyer | lawyer | `fib` keeps `fib(n - 1)` in `s1` | a callee saves every `s` register it uses, not just `s0` |
| 17 | finale | frame | Race the Chip Chomper with `fact(6)` | every saved word costs a word per floor |

Ideas not built yet:

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
