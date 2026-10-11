-- Level 2 becomes the Memory Maze: a bank of rooms on memory, addresses, lw/sw,
-- arrays, branches, loops, procedures, and translating C (COMP 311 weeks 3-5).
-- The level's slot was a placeholder named "Opcode"; instruction encoding moves
-- to a later level (Docs/level-brainstorm.md).
--
-- Runs draw their rooms. levels.draw lists pools in order; a run takes every
-- question of a pool, or `take` of them at random (secrets.SystemRandom), in
-- ordinal order within the pool. A level with no draw rule plays every active
-- question, as before. Level 2 plays its four tutorial rooms, one memory room,
-- one branches room, one loops room, both procedure rooms, and the race: ten.
--
-- Maze rooms ("kind": "maze") follow Lecture 4 (arrays from 0x4000, its example
-- array and sum loop): a grid of memory words in row-major order, the word at
-- row r, column c at base + 4*(r*width + c). The map marks walls (#), floor (.),
-- the start (S), the exit (E), doors (D), and glass (B: reachable, not
-- walkable). values, doors (the code each door needs), and goal.memory are
-- keyed by hex address. a0 is the robot's address. Players step (addi a0, a0,
-- ±4 or ±4*width), load and store with their hands at any offset that lands in
-- the room, press the room's keys, and teach loops with loop: and the room's
-- repeat branches. In the race, the Chip Chomper zeroes the first `words` words
-- of its row, one every few instructions. arrays and names only label the
-- screen. The response is the program as text.
--
-- Code rooms ("kind": "code") are short programs with blanks: code lists
-- lines, labels, and blanks (each with its choices), assembled from 0x100. data
-- blocks are laid out from data.base; stack gives sp's starting top and the
-- words below it. ra starts at 0x400 (main's caller); a program ends when it
-- returns there or runs past its last line. The response names the line picked
-- for each blank, and every test must pass; names only label the screen.
-- server/puzzles.py grades both, and
-- server/test_puzzles.py checks every room's design.
BEGIN;

ALTER TABLE aa.questions ADD COLUMN pool text;
ALTER TABLE aa.levels ADD COLUMN draw jsonb;

-- Recreated with the maze and code kinds; still written with -> rather than ?& (see 0001).
ALTER TABLE aa.questions DROP CONSTRAINT questions_payload_shape;
ALTER TABLE aa.questions ADD CONSTRAINT questions_payload_shape CHECK (
    CASE type
        WHEN 'multiple_choice' THEN
                 jsonb_typeof(payload -> 'options') = 'array'
             AND jsonb_typeof(payload -> 'correct_option_ids') = 'array'
             AND jsonb_array_length(payload -> 'options') >= 2
             AND jsonb_array_length(payload -> 'correct_option_ids') >= 1
        WHEN 'drag_and_drop' THEN
                 jsonb_typeof(payload -> 'tiles') = 'array'
             AND jsonb_typeof(payload -> 'correct_order') = 'array'
             AND payload ->> 'orientation' IN ('horizontal', 'vertical')
             AND jsonb_array_length(payload -> 'tiles')
                 = jsonb_array_length(payload -> 'correct_order')
        WHEN 'matching' THEN
                 jsonb_typeof(payload -> 'columns') = 'array'
             AND jsonb_typeof(payload -> 'pairs') = 'array'
             AND jsonb_array_length(payload -> 'columns') = 2
             AND jsonb_array_length(payload -> 'pairs') >= 2
        WHEN 'puzzle' THEN
            CASE payload ->> 'kind'
                WHEN 'moves' THEN
                         jsonb_typeof(payload -> 'goal') = 'object'
                     AND jsonb_typeof(payload -> 'buttons') = 'array'
                     AND jsonb_array_length(payload -> 'buttons') >= 1
                WHEN 'maze' THEN
                         jsonb_typeof(payload -> 'goal') = 'object'
                     AND jsonb_typeof(payload -> 'map') = 'array'
                     AND jsonb_array_length(payload -> 'map') >= 1
                WHEN 'code' THEN
                         jsonb_typeof(payload -> 'code') = 'array'
                     AND jsonb_typeof(payload -> 'tests') = 'array'
                     AND jsonb_array_length(payload -> 'tests') >= 1
                ELSE false
            END
        ELSE false
    END
);

UPDATE aa.levels SET name = 'Memory Maze', scene_path = 'res://levels/level_2/memory_maze.tscn',
    completion_rule = '{"type":"all_correct"}', is_active = true,
    draw = '[{"pool": "tutorial"}, {"pool": "memory", "take": 1}, {"pool": "branches", "take": 1}, {"pool": "loops", "take": 1}, {"pool": "procedures"}, {"pool": "finale"}]'
    WHERE id = 2;
UPDATE aa.badges SET name = 'Memory Master', description = 'Escaped the Memory Maze.',
    image_path = 'res://images/memory_maze.svg', is_active = true
    WHERE level_id = 2;

-- Retire, never delete (none are expected: the old placeholder had no questions).
UPDATE aa.questions SET is_active = false, retired_at = now()
    WHERE level_id = 2 AND is_active;

INSERT INTO aa.questions (level_id, type, ordinal, pool, prompt, code_snippet, hint, explanation, difficulty, payload) VALUES
(2, 'puzzle', 1, 'tutorial',
 'a0 holds the robot''s address. An int is 4 bytes, so each step right adds 4. Walk to the exit.',
 NULL,
 'Press → (or click the next cell) four times.',
 'Each step is addi a0, a0, 4: 0x4000 → 0x4004 → 0x4008 → 0x400C → 0x4010.', 1,
 '{"kind": "maze", "base": 16384,
   "map": ["S...E"],
   "hands": [],
   "goal": {},
   "max_moves": 6, "par": 4}'),
(2, 'puzzle', 2, 'tutorial',
 'Base + offset: lw a2, 8(a0) loads the int 8 bytes past a0. Load arr[3] into a2, then exit.',
 'a2 = arr[3];',
 'Click arr[3] and load it: from 0x4000 it''s 3 ints × 4 bytes = 12 bytes on.',
 'R[rd] = M[R[rs1] + offset]: from a0 = 0x4000, lw a2, 12(a0) reads 0x400C, which is arr[3] = 40. (The slides write it lw x12, 12(x10).) After one step, the same int is lw a2, 8(a0).', 1,
 '{"kind": "maze", "base": 16384,
   "map": ["S....E"],
   "values": {"0x4000": 5, "0x4004": 90, "0x4008": 100, "0x400c": 40, "0x4010": 11}, "hands": ["a2"],
   "arrays": [{"name": "arr", "at": "0x4000", "length": 5}],
   "goal": {"registers": {"a2": 40}},
   "max_moves": 8, "par": 6}'),
(2, 'puzzle', 3, 'tutorial',
 'sw writes a register into memory. t2 holds 8, and arr[3] is a door that opens when it holds 8.',
 'arr[3] = 8;',
 'Click arr[3] and store t2 there: sw t2, 12(a0) from where you start.',
 'M[R[rs1] + offset] = R[rs2]: sw t2, 12(a0) writes 8 over the 40 at 0x400C (the slides'' sw x7, 12(x10)), so the array is now 5, 90, 100, 8, 11.', 1,
 '{"kind": "maze", "base": 16384,
   "map": ["S..D.E"],
   "values": {"0x4000": 5, "0x4004": 90, "0x4008": 100, "0x400c": 40, "0x4010": 11}, "doors": {"0x400c": 8}, "hands": ["t2"], "registers": {"t2": 8},
   "arrays": [{"name": "arr", "at": "0x4000", "length": 5}],
   "goal": {},
   "max_moves": 8, "par": 6}'),
(2, 'puzzle', 4, 'tutorial',
 'Too far to walk with 3 instructions. Tap loop:, show the robot one step, then tap Repeat.',
 'while (a0 != a1) a0 += 4;',
 'loop:, then one step right, then Repeat while a0 ≠ a1.',
 'bne a0, a1, loop jumps back to loop: until a0 equals a1: one step written, seven steps taken.', 2,
 '{"kind": "maze", "base": 16384,
   "map": ["S......E"],
   "hands": [], "registers": {"a1": 16412},
   "loop": true, "repeat": ["bne a0, a1, loop"],
   "goal": {},
   "max_moves": 3, "par": 2}'),
(2, 'puzzle', 5, 'memory',
 'Rows sit end to end in memory. This room is 4 words wide, so one row down is 4 × 4 = 16 bytes on.',
 NULL,
 'Go down twice (+16 each), then right three times.',
 'Memory is one long line of bytes: the word below is a whole row later, so a step down is addi a0, a0, 16 here. Any word is at base + 4 × (row × width + column).', 1,
 '{"kind": "maze", "base": 16384,
   "map": ["S.#.",
           ".##.",
           "...E"],
   "hands": [],
   "goal": {},
   "max_moves": 7, "par": 5}'),
(2, 'puzzle', 6, 'memory',
 'Memory can''t do math. This door holds 7 and opens at 12: load it, add 5 in a register, store it back.',
 'door = door + 5;',
 'Load the door into t0, press addi t0, t0, 5, then store t0 back into the door.',
 'RISC-V is a load/store architecture: data is loaded into registers, processed there, and written back with stores. lw, addi, sw is how door = door + 5 really runs.', 2,
 '{"kind": "maze", "base": 16384,
   "map": ["S.#E",
           "#.D."],
   "values": {"0x4018": 7}, "doors": {"0x4018": 12}, "hands": ["t0"], "keys": ["addi t0, t0, 5"],
   "arrays": [{"name": "door", "at": "0x4018", "length": 1}],
   "goal": {},
   "max_moves": 10, "par": 8}'),
(2, 'puzzle', 7, 'memory',
 'Each door holds the code the other one needs. Swap their words; you have two registers, t0 and t1.',
 't = A; A = B; B = t;',
 'Load both doors first (into t0 and t1), then store each register into the other door.',
 'A swap needs two registers: load both words before storing, or the first store overwrites a value you still need. Negative offsets reach backwards: door A is above and behind the robot.', 2,
 '{"kind": "maze", "base": 16384,
   "map": ["##D##",
           "S...#",
           "##D##",
           "##E##"],
   "values": {"0x4008": 3, "0x4030": 5}, "doors": {"0x4008": 5, "0x4030": 3}, "hands": ["t0", "t1"],
   "arrays": [{"name": "A", "at": "0x4008", "length": 1}, {"name": "B", "at": "0x4030", "length": 1}],
   "goal": {"memory": {"0x4008": 5, "0x4030": 3}},
   "max_moves": 10, "par": 8}'),
(2, 'puzzle', 8, 'memory',
 'Array math: fill the blanks so t0 = arr[i] + arr[i+1]. It''s tested with i = 1 and i = 3.',
 'sum = arr[i] + arr[i+1];   // arr is t1, i is t2, sum is t0',
 'arr[i] is at arr + i × 4 (slli by 2), and arr[i+1] is one int, 4 bytes, after it.',
 'Find the address once: t3 = t1 + (i << 2) is &arr[i]. Then arr[i] is 0(t3) and arr[i+1] is 4(t3).', 2,
 '{"kind": "code",
   "code": [{"blank": ["slli t3, t2, 1", "slli t3, t2, 2", "addi t3, t2, 4"]},
            {"line": "add t3, t1, t3"},
            {"line": "lw t4, 0(t3)"},
            {"blank": ["lw t5, 8(t3)", "lw t5, 1(t3)", "lw t5, 4(t3)"]},
            {"line": "add t0, t4, t5"}],
   "data": {"base": 8192, "blocks": [{"label": "arr", "words": [4, 9, 2, 7, 5]}]}, "registers": {"t1": "arr"}, "names": {"t0": "sum", "t1": "arr", "t2": "i"},
   "tests": [{"registers": {"t2": 1}, "expect": {"registers": {"t0": 11}}}, {"registers": {"t2": 3}, "expect": {"registers": {"t0": 12}}}]}'),
(2, 'puzzle', 9, 'branches',
 'If/else: x is a0 and y is a1. If x < 5, y = y + 3; otherwise y doubles. It''s tested with x = 3 and x = 7.',
 'if (x < 5) y = y + 3; else y = y << 1;',
 'slti sets t0 to 1 when x < 5. Branch to else when t0 is 0, and make the if part jump over else.',
 'beq t0, x0, else skips the if part when x ≥ 5 (y: 4 → 8). With x = 3, y becomes 7 and j done jumps over else; without it, the if part falls into else and doubles y too.', 2,
 '{"kind": "code",
   "code": [{"line": "slti t0, a0, 5"},
            {"blank": ["bne t0, x0, else", "beq t0, x0, else"]},
            {"line": "addi a1, a1, 3"},
            {"blank": ["j done", "addi x0, x0, 0", "j else"]},
            {"label": "else"},
            {"line": "slli a1, a1, 1"},
            {"label": "done"}],
   "names": {"a0": "x", "a1": "y"},
   "tests": [{"registers": {"a0": 3, "a1": 4}, "expect": {"registers": {"a1": 7}}}, {"registers": {"a0": 7, "a1": 4}, "expect": {"registers": {"a1": 8}}}]}'),
(2, 'puzzle', 10, 'branches',
 'The exit is the first 0 in this row. Teach a loop that stops when it loads a 0 (x0 always holds 0).',
 'while (*p != 0) p++;   // p is a0',
 'Step, load the new word into t1, then Repeat while t1 ≠ 0.',
 'A sentinel loop stops on the data, not on a count: bne t1, x0, loop goes round again while the word just loaded isn''t 0.', 3,
 '{"kind": "maze", "base": 16384,
   "map": ["S.....E."],
   "values": {"0x4000": 6, "0x4004": 3, "0x4008": 8, "0x400c": 5, "0x4010": 2, "0x4014": 9, "0x401c": 4}, "hands": ["t1"],
   "loop": true, "repeat": ["bne t1, x0, loop", "beq t1, x0, loop"],
   "goal": {},
   "max_moves": 4, "par": 3}'),
(2, 'puzzle', 11, 'loops',
 'Copy a[] into the vault below it. Teach the robot one int, then Repeat. The room is 7 words wide.',
 'for (i = 0; i < 6; i++) vault[i] = a[i];',
 'Tap loop:, load the int under you, store it 28 bytes on (a row down), step right. Then Repeat while a0 < a1.',
 'Everything in the loop is relative to a0, so the same four lines copy every int: lw, sw 28(a0), step 4, and blt back while a0 < a1. bge would jump back only once a0 ≥ a1.', 3,
 '{"kind": "maze", "base": 16384,
   "map": ["S.....E",
           "BBBBBB#"],
   "values": {"0x4000": 3, "0x4004": 1, "0x4008": 4, "0x400c": 1, "0x4010": 5, "0x4014": 9}, "hands": ["t0"], "registers": {"a1": 16408},
   "arrays": [{"name": "a", "at": "0x4000", "length": 6}, {"name": "vault", "at": "0x401c", "length": 6}],
   "loop": true, "repeat": ["blt a0, a1, loop", "bge a0, a1, loop"],
   "goal": {"memory": {"0x401c": 3, "0x4020": 1, "0x4024": 4, "0x4028": 1, "0x402c": 5, "0x4030": 9}},
   "max_moves": 5, "par": 4}'),
(2, 'puzzle', 12, 'loops',
 'The loop from lecture: add up values[0] to values[5] into t2. t0 is i, and t6 holds 6.',
 'for (i = 0; i < 6; i++) sum += values[i];',
 'Tap loop:, load values[i] into t1, add it to t2, step, add 1 to i, then Repeat while i < 6.',
 'Load values[i], add it to the sum, move to the next int, and i++: blt t0, t6 jumps back while i < 6. The lecture finds values[i] with slli t1, t0, 2 (i × 4); stepping a0 by 4 each pass does the same job.', 3,
 '{"kind": "maze", "base": 16384,
   "map": ["S.....E"],
   "values": {"0x4000": 1, "0x4004": 3, "0x4008": 5, "0x400c": 7, "0x4010": 9, "0x4014": 11}, "hands": ["t1"], "registers": {"t0": 0, "t2": 0, "t6": 6}, "names": {"t0": "i", "t2": "sum", "t6": "n"}, "keys": ["add t2, t2, t1", "addi t0, t0, 1"],
   "arrays": [{"name": "values", "at": "0x4000", "length": 6}],
   "loop": true, "repeat": ["blt t0, t6, loop"],
   "goal": {"registers": {"t2": 36}},
   "max_moves": 6, "par": 5}'),
(2, 'puzzle', 13, 'loops',
 'Counting down: this loop should add 2 to every int in arr while i counts down from 3. Fill the blanks; the run shows what''s left in arr and t0.',
 'for (i = 3; i >= 0; i--) arr[i] += 2;',
 'Store the new value back where you loaded it from, and keep looping while i ≥ 0.',
 'The body runs 4 times (i = 3, 2, 1, 0): arr becomes 5, 7, 9, 11 and t0 ends at -1. bne t0, x0 would stop before i = 0 and skip arr[0].', 3,
 '{"kind": "code",
   "code": [{"line": "addi t0, x0, 3"},
            {"line": "la t1, arr"},
            {"label": "loop"},
            {"line": "slli t2, t0, 2"},
            {"line": "add t3, t1, t2"},
            {"line": "lw t4, 0(t3)"},
            {"line": "addi t4, t4, 2"},
            {"blank": ["sw t4, 4(t3)", "lw t4, 0(t3)", "sw t4, 0(t3)"]},
            {"line": "addi t0, t0, -1"},
            {"blank": ["bne t0, x0, loop", "bge t0, x0, loop", "blt t0, x0, loop"]}],
   "data": {"base": 8192, "blocks": [{"label": "arr", "words": [3, 5, 7, 9]}]}, "names": {"t0": "i", "t1": "arr"},
   "tests": [{"expect": {"memory": {"arr[0]": 5, "arr[1]": 7, "arr[2]": 9, "arr[3]": 11}, "registers": {"t0": -1}}}]}'),
(2, 'puzzle', 14, 'procedures',
 'Calling a function: main calls func, then adds 1. jal puts PC + 4 in ra and jumps; jalr jumps back to ra. Make main finish with a0 = 10.',
 'a0 = func(6) + 1;   // func(x) returns x + 3',
 'jal ra, func at 0x104 sets ra = 0x108. func returns with jalr x0, 0(ra).',
 'jal ra, func at 0x104 saves 0x108 (PC + 4) in ra and jumps to func; jalr x0, 0(ra) jumps back to 0x108, which adds the 1. j func jumps without saving a return address, and 4(ra) would skip the add.', 3,
 '{"kind": "code",
   "code": [{"label": "main"},
            {"line": "addi a0, x0, 6"},
            {"blank": ["j func", "jal ra, func", "jal ra, done"]},
            {"line": "addi a0, a0, 1"},
            {"line": "j done"},
            {"label": "func"},
            {"line": "addi a0, a0, 3"},
            {"blank": ["jalr x0, 4(ra)", "j done", "jalr x0, 0(ra)"]},
            {"label": "done"}],
   "tests": [{"expect": {"registers": {"a0": 10}}}]}'),
(2, 'puzzle', 15, 'procedures',
 'Stack frames: main saves ra and a0 on the stack, calls func(6), keeps the answer in result, then restores both and returns. Fill the blanks.',
 'result = func(6);   // func(x) returns x + 3',
 'Make room with addi sp, sp, -8, save ra at 4(sp) before jal overwrites it, and store func''s answer before lw a0, 0(sp) brings back main''s old a0.',
 'main allocates 8 bytes (addi sp, sp, -8). jal ra, func overwrites ra with 0x114, which is why main saved its own return address first. func returns 9 in a0, but lw a0, 0(sp) brings back main''s old a0 (2), so the answer has to be stored before that.', 3,
 '{"kind": "code",
   "code": [{"label": "main"},
            {"blank": ["addi sp, sp, 8", "addi sp, sp, -4", "addi sp, sp, -8"]},
            {"blank": ["sw ra, 4(sp)", "lw ra, 4(sp)", "sw a0, 4(sp)"]},
            {"line": "sw a0, 0(sp)"},
            {"line": "addi a0, x0, 6"},
            {"line": "jal ra, func"},
            {"blank": ["sw a0, 0(sp)", "sw a0, 0(t1)", "lw a0, 0(sp)"]},
            {"line": "lw a0, 0(sp)"},
            {"line": "lw ra, 4(sp)"},
            {"line": "addi sp, sp, 8"},
            {"line": "jalr x0, 0(ra)"},
            {"label": "func"},
            {"line": "addi a0, a0, 3"},
            {"line": "jalr x0, 0(ra)"}],
   "data": {"base": 8192, "blocks": [{"label": "result", "words": [0]}]}, "stack": {"top": 32752, "words": 4}, "registers": {"a0": 2, "t1": "result"}, "names": {"t1": "&result"},
   "tests": [{"expect": {"memory": {"result": 9}, "registers": {"a0": 2, "sp": 32752}, "returned": true}}]}'),
(2, 'puzzle', 16, 'finale',
 'The Chip Chomper is eating a[], one int every 4 instructions. Copy it into the vault before it''s eaten.',
 'for (i = 0; i < 6; i++) vault[i] = a[i];',
 'Tap loop:, then keep the loop to 4 instructions: load, store a row up (-28), step, Repeat. Every extra line slows every pass.',
 'A loop costs its body times its passes: 4 instructions an int kept you just ahead of the Chomper''s 4 instructions an int.', 3,
 '{"kind": "maze", "base": 16384,
   "map": ["BBBBBB#",
           "S.....E"],
   "values": {"0x401c": 7, "0x4020": 2, "0x4024": 9, "0x4028": 4, "0x402c": 8, "0x4030": 1}, "hands": ["t0"], "registers": {"a1": 16436},
   "arrays": [{"name": "vault", "at": "0x4000", "length": 6}, {"name": "a", "at": "0x401c", "length": 6}],
   "loop": true, "repeat": ["bne a0, a1, loop"], "chomper": {"row": 1, "start": 4, "every": 4, "words": 6},
   "goal": {"memory": {"0x4000": 7, "0x4004": 2, "0x4008": 9, "0x400c": 4, "0x4010": 8, "0x4014": 1}},
   "max_moves": 5, "par": 4}');

COMMIT;
