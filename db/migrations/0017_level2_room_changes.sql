-- Level 2: rooms that were too much alike are replaced, and the bank grows from
-- 16 rooms to 20. The draw rule is unchanged: ten rooms a run.
--
-- Replaced (the old rows are retired, never deleted, so attempts on them still
-- point at what students saw; runs already started keep their snapshots):
--
--    3 tutorial    stored into arr[3], the same word room 2 loads. Now arr[2],
--                  so the offset has to be worked out again.
--   11 loops       copied a[] into the vault, the same loop as the finale (16).
--                  Now a store-ahead loop that opens a row of doors.
--   15 procedures  called func(6) like room 14. Now twice(7), with its own
--                  numbers, so the two procedure rooms read differently.
--
-- New:
--
--   17 memory      a 2D array in row-major order: grid[1][2]
--   18 branches    if without else: absolute value
--   19 branches    one unsigned comparison checks both array bounds (bgeu)
--   20 loops       a branch inside a loop: the largest int of an array
--
-- Written by tools/rooms.py from levels/level_2/guest_rooms.json;
-- server/test_puzzles.py checks every room's par or its single answer.
BEGIN;

UPDATE aa.questions SET is_active = false, retired_at = now()
    WHERE level_id = 2 AND is_active AND ordinal IN (3, 11, 15);

INSERT INTO aa.questions (level_id, type, ordinal, pool, prompt, code_snippet, hint, explanation, difficulty, payload, answer) VALUES
(2, 'puzzle', 3, 'tutorial',
 'Store 8 in arr[2] to open its door, then reach the exit.
sw writes a register into memory, and t2 holds 8.',
 'arr[2] = 8;',
 'Click arr[2] and store t2 there: sw t2, 8(a0) from where you start.',
 'M[R[rs1] + offset] = R[rs2]: arr[2] is 2 ints × 4 bytes = 8 bytes past a0, so sw t2, 8(a0) writes 8 over the 100 at 0x4008. The array is now 5, 90, 8, 40, 11.',
 2,
 '{"kind": "maze", "base": 16384, "map": ["S.D..E"], "values": {"0x4000": 5, "0x4004": 90, "0x4008": 100, "0x400c": 40, "0x4010": 11}, "doors": {"0x4008": 8}, "hands": ["t2"], "registers": {"t2": 8}, "arrays": [{"name": "arr", "at": "0x4000", "length": 5}], "goal": {}, "max_moves": 8, "par": 6}',
 '{"program": ["sw t2, 8(a0)", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4"]}'),
(2, 'puzzle', 11, 'loops',
 'Open every door: each one needs 9, and t2 holds 9.
Teach the robot one door, then Repeat. A store can reach the word ahead of you.',
 'do { p[1] = 9; p++; } while (p != end);   // p is a0, end is a1',
 'Tap loop:, store t2 one word ahead with sw t2, 4(a0), step right, then Repeat while a0 ≠ a1.',
 'sw t2, 4(a0) writes the word ahead of the robot, so each door is open by the time it steps there. Three lines, written once, run six times: the loop stops when a0 reaches the address in a1.',
 2,
 '{"kind": "maze", "base": 16384, "map": ["SDDDDDE"], "values": {"0x4004": 4, "0x4008": 1, "0x400c": 7, "0x4010": 2, "0x4014": 6}, "doors": {"0x4004": 9, "0x4008": 9, "0x400c": 9, "0x4010": 9, "0x4014": 9}, "hands": ["t2"], "registers": {"t2": 9, "a1": 16408}, "arrays": [{"name": "door", "at": "0x4004", "length": 5}], "loop": true, "repeat": ["bne a0, a1, loop", "beq a0, a1, loop"], "goal": {}, "max_moves": 4, "par": 3}',
 '{"program": ["loop:", "sw t2, 4(a0)", "addi a0, a0, 4", "bne a0, a1, loop"]}'),
(2, 'puzzle', 15, 'procedures',
 'Fill the blanks so main stores twice(7) in total and returns.
main saves ra and a0 on the stack before the call and restores both before returning.',
 'total = twice(7);   // twice(x) returns x + x',
 'Make room with addi sp, sp, -8, save ra at 4(sp) before jal overwrites it, and store twice''s answer before lw a0, 0(sp) brings back main''s old a0.',
 'main allocates 8 bytes (addi sp, sp, -8). jal ra, twice overwrites ra with 0x114, which is why main saved its own return address first. twice returns 14 in a0, but lw a0, 0(sp) brings back main''s old a0 (3), so the answer has to be stored before that.',
 2,
 '{"kind": "code", "code": [{"label": "main"}, {"blank": ["addi sp, sp, -4", "addi sp, sp, -8", "addi sp, sp, 8"]}, {"blank": ["sw a0, 4(sp)", "sw ra, 4(sp)", "lw ra, 4(sp)"]}, {"line": "sw a0, 0(sp)"}, {"line": "addi a0, x0, 7"}, {"line": "jal ra, twice"}, {"blank": ["sw a0, 0(t1)", "lw a0, 0(sp)", "sw a0, 0(sp)"]}, {"line": "lw a0, 0(sp)"}, {"line": "lw ra, 4(sp)"}, {"line": "addi sp, sp, 8"}, {"line": "jalr x0, 0(ra)"}, {"label": "twice"}, {"line": "add a0, a0, a0"}, {"line": "jalr x0, 0(ra)"}], "data": {"base": 8192, "blocks": [{"label": "total", "words": [0]}]}, "stack": {"top": 32752, "words": 4}, "registers": {"a0": 3, "t1": "total"}, "names": {"t1": "&total"}, "tests": [{"expect": {"memory": {"total": 14}, "registers": {"a0": 3, "sp": 32752}, "returned": true}}]}',
 '{"blanks": ["addi sp, sp, -8", "sw ra, 4(sp)", "sw a0, 0(t1)"]}'),
(2, 'puzzle', 17, 'memory',
 'Load row 1, column 2 of the grid into a2, then reach the exit.
A 2D array is stored one row after another. This grid is 4 wide, so grid[1][2] is word 1 × 4 + 2 = 6.',
 'a2 = grid[1][2];   // int grid[3][4]',
 'Click the word in row 1, column 2 (the rows count from 0) and load it. From the start it''s 6 words on: lw a2, 24(a0).',
 'C stores a 2D array row by row (row-major order), so grid[r][c] is word r × 4 + c of this 4-wide grid. grid[1][2] is word 6, at 0x4000 + 6 × 4 = 0x4018, which holds 9. After one step right, the same word is lw a2, 20(a0).',
 2,
 '{"kind": "maze", "base": 16384, "map": ["S..E", "BBBB", "BBBB"], "values": {"0x4000": 3, "0x4004": 8, "0x4008": 1, "0x400c": 6, "0x4010": 7, "0x4014": 2, "0x4018": 9, "0x401c": 4, "0x4020": 5, "0x4024": 11, "0x4028": 12, "0x402c": 10}, "hands": ["a2"], "arrays": [{"name": "row0", "at": "0x4000", "length": 4}, {"name": "row1", "at": "0x4010", "length": 4}, {"name": "row2", "at": "0x4020", "length": 4}], "goal": {"registers": {"a2": 9}}, "max_moves": 6, "par": 4}',
 '{"program": ["lw a2, 24(a0)", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4"]}'),
(2, 'puzzle', 18, 'branches',
 'Fill the blanks so x ends up as its absolute value.
x is a0. It''s tested with x = -5, 3, and 0, so numbers that aren''t negative have to be left alone.',
 'if (x < 0) x = -x;',
 'The branch skips the negation, so it tests the opposite of the C: x ≥ 0. And -x is 0 - x.',
 'An if without an else is one branch over its body: bge a0, x0, done skips the body when x ≥ 0, the opposite of the C condition. sub a0, x0, a0 computes 0 - x, which is how RISC-V negates.',
 2,
 '{"kind": "code", "code": [{"blank": ["blt a0, x0, done", "bge a0, x0, done", "beq a0, x0, done"]}, {"blank": ["sub a0, a0, x0", "addi a0, a0, -1", "sub a0, x0, a0"]}, {"label": "done"}], "names": {"a0": "x"}, "tests": [{"registers": {"a0": -5}, "expect": {"registers": {"a0": 5}}}, {"registers": {"a0": 3}, "expect": {"registers": {"a0": 3}}}, {"registers": {"a0": 0}, "expect": {"registers": {"a0": 0}}}]}',
 '{"blanks": ["bge a0, x0, done", "sub a0, x0, a0"]}'),
(2, 'puzzle', 19, 'branches',
 'Fill the blank so ok is 1 only when i is a valid index: 0 ≤ i < n.
i is a0, n is a1, and ok is a2. It''s tested with i = 2, 4, and -1, all with n = 4.',
 'ok = (i >= 0 && i < n);',
 'Read as an unsigned number, -1 is 0xFFFFFFFF: about 4 billion. One unsigned comparison rejects it along with every i ≥ n.',
 'bgeu compares unsigned, and a negative i read as unsigned is huge (-1 is 0xFFFFFFFF), so it counts as ≥ n. One branch checks both bounds. bge would let i = -1 through, since -1 < 4 as signed numbers.',
 2,
 '{"kind": "code", "code": [{"line": "addi a2, x0, 0"}, {"blank": ["bge a0, a1, done", "bltu a0, a1, done", "bgeu a0, a1, done"]}, {"line": "addi a2, x0, 1"}, {"label": "done"}], "names": {"a0": "i", "a1": "n", "a2": "ok"}, "tests": [{"registers": {"a0": 2, "a1": 4}, "expect": {"registers": {"a2": 1}}}, {"registers": {"a0": 4, "a1": 4}, "expect": {"registers": {"a2": 0}}}, {"registers": {"a0": -1, "a1": 4}, "expect": {"registers": {"a2": 0}}}]}',
 '{"blanks": ["bgeu a0, a1, done"]}'),
(2, 'puzzle', 20, 'loops',
 'Fill the blanks so the loop leaves the largest int of arr in a0.
i is t0, n is t6 (5), and max is a0, which starts at 0. The test checks max and where i ends up.',
 'for (i = 0; i < n; i++) if (arr[i] > max) max = arr[i];',
 'Skip the update when max is already at least arr[i], and loop back while i < n.',
 'The if inside the loop is a branch over one line: bge a0, t4, skip leaves max alone unless arr[i] is bigger. blt t0, t6, loop goes round while i < 5, so max climbs 3, 9, 12 and i ends at 5.',
 2,
 '{"kind": "code", "code": [{"line": "addi t0, x0, 0"}, {"line": "la t1, arr"}, {"label": "loop"}, {"line": "slli t2, t0, 2"}, {"line": "add t3, t1, t2"}, {"line": "lw t4, 0(t3)"}, {"blank": ["blt a0, t4, skip", "bge t4, a0, skip", "bge a0, t4, skip"]}, {"line": "add a0, t4, x0"}, {"label": "skip"}, {"line": "addi t0, t0, 1"}, {"blank": ["bge t0, t6, loop", "blt t0, t6, loop", "bne t0, x0, loop"]}], "data": {"base": 8192, "blocks": [{"label": "arr", "words": [3, 9, 4, 12, 7]}]}, "registers": {"t6": 5, "a0": 0}, "names": {"t0": "i", "t1": "arr", "t6": "n", "a0": "max"}, "tests": [{"expect": {"registers": {"a0": 12, "t0": 5}}}]}',
 '{"blanks": ["bge a0, t4, skip", "blt t0, t6, loop"]}');

COMMIT;
