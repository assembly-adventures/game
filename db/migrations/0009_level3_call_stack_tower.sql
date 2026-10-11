-- Level 3 becomes the Call Stack Tower: procedures, jal and jalr, the calling
-- convention, stack frames, and recursion (COMP 311 weeks 5-6, Lectures 6-7).
-- The level's slot was a placeholder named "Pipelining"; pipelining moves to a
-- later level (Docs/level-brainstorm.md).
--
-- Every room runs real code on one small machine: instructions from 0x100, and
-- a stack of words below 0x7FF0 holding junk (0xDEADBEEF) until something is
-- saved there. The Chip Chomper is the caller: before each call it fills every
-- register with junk, sets sp to 0x7FF0 and ra to 0x400 (its own code), puts
-- the call's args in a0-a7, and jumps to entry. A call ends when the code
-- returns to 0x400. Three kinds of puzzle room:
--
--   frame     The player lays out the function's stack frame: a list of
--             registers from sp+0 up, from `blocks`, at most `max_slots`. The
--             code's {"prologue": true} and {"epilogue": true} entries become
--             addi sp, sp, -4n and a sw per block, then a lw per ra or s block
--             and addi sp, sp, 4n. Every call must return its `expect` with
--             s0-s11 and sp as the Chomper set them. `par` is the smallest
--             working frame. In the finale, `chomper` eats a stack word every
--             `every` instructions from instruction `start`, from the bottom of
--             the stack (`stack_words` words) up.
--   elevator  One traced call of `entry`; the player types values on the chain
--             of calls to `function` (outermost first): `blanks` names
--             [floor, field] pairs, field one of a0, a1, s0, ra, ret.
--   lawyer    The player names the line (by address) that breaks the calling
--             convention and the rule it breaks, from `clauses`. `verdict` is
--             the answer, and run snapshots leave it out.
--
-- Runs draw their rooms (levels.draw): the three tutorial rooms, two of each
-- room kind at random, and the finale. server/call_stack.py grades every kind,
-- and server/test_call_stack.py checks every room's design.
BEGIN;

-- Recreated with Level 3's kinds; still written with -> rather than ?& (see 0001).
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
                WHEN 'frame' THEN
                         jsonb_typeof(payload -> 'code') = 'array'
                     AND jsonb_typeof(payload -> 'blocks') = 'array'
                     AND jsonb_typeof(payload -> 'calls') = 'array'
                     AND jsonb_array_length(payload -> 'calls') >= 1
                WHEN 'elevator' THEN
                         jsonb_typeof(payload -> 'code') = 'array'
                     AND jsonb_typeof(payload -> 'blanks') = 'array'
                     AND jsonb_array_length(payload -> 'blanks') >= 1
                WHEN 'lawyer' THEN
                         jsonb_typeof(payload -> 'code') = 'array'
                     AND jsonb_typeof(payload -> 'clauses') = 'array'
                     AND jsonb_typeof(payload -> 'verdict') = 'object'
                ELSE false
            END
        ELSE false
    END
);

UPDATE aa.levels SET name = 'Call Stack Tower', scene_path = 'res://levels/level_3/call_stack_tower.tscn',
    completion_rule = '{"type":"all_correct"}', is_active = true,
    draw = '[{"pool": "tutorial"}, {"pool": "frames", "take": 2}, {"pool": "elevator", "take": 2}, {"pool": "lawyer", "take": 2}, {"pool": "finale"}]'
    WHERE id = 3;
UPDATE aa.badges SET name = 'Stack Master', description = 'Escaped the Call Stack Tower.',
    image_path = 'res://images/call_stack_tower.svg', is_active = true
    WHERE level_id = 3;

-- Retire, never delete (none are expected: the old placeholder had no questions).
UPDATE aa.questions SET is_active = false, retired_at = now()
    WHERE level_id = 3 AND is_active;

INSERT INTO aa.questions (level_id, type, ordinal, pool, prompt, code_snippet, hint, explanation, difficulty, payload) VALUES
(3, 'puzzle', 1, 'tutorial',
 'Build plus1''s stack frame so all three calls work.
plus1 calls triple, and that jal overwrites ra: the address plus1 needs to get back to the Chomper.',
 'int plus1(int x) { return triple(x) + 1; }',
 'plus1 needs ra after triple returns, so save ra in its frame.',
 'jal ra, triple puts the address after it in ra, so plus1''s own return address is gone unless the prologue saved it. With ra saved at sp+0, the epilogue loads it back and jr ra reaches the Chomper.', 1,
 '{"kind": "frame",
  "entry": "plus1",
  "code": [{"label": "plus1"},
           {"prologue": true},
           {"line": "jal ra, triple"},
           {"line": "addi a0, a0, 1"},
           {"epilogue": true},
           {"line": "jr ra"},
           {"label": "triple"},
           {"line": "slli t0, a0, 1"},
           {"line": "add a0, a0, t0"},
           {"line": "jr ra"}],
  "blocks": ["ra", "s0", "a0"],
  "max_slots": 3,
  "par": 1,
  "calls": [{"args": {"a0": 4}, "expect": 13}, {"args": {"a0": -2}, "expect": -5}, {"args": {"a0": 7}, "expect": 22}]}'),
(3, 'puzzle', 2, 'tutorial',
 'Fill in what each call to sqr returns, then ride to check.
sqr(3) calls sqr(2), which calls sqr(1): one floor down per call.',
 'int sqr(int x) { return x < 2 ? x : sqr(x - 1) + x + x - 1; }',
 'sqr(1) returns 1. On the way up, each floor adds x + x - 1 to what the floor below returned.',
 'sqr(1) is the base case and returns 1. sqr(2) returns 1 + 2 + 2 - 1 = 4, and sqr(3) returns 4 + 3 + 3 - 1 = 9. Each floor waits in its own frame until the floor below returns.', 1,
 '{"kind": "elevator",
  "entry": "sqr",
  "function": "sqr",
  "code": [{"label": "sqr"},
           {"line": "addi sp, sp, -8"},
           {"line": "sw ra, 4(sp)"},
           {"line": "sw s0, 0(sp)"},
           {"line": "slti t0, a0, 2"},
           {"line": "bne t0, x0, done"},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, sqr"},
           {"line": "add a0, a0, s0"},
           {"line": "add a0, a0, s0"},
           {"line": "addi a0, a0, -1"},
           {"label": "done"},
           {"line": "lw s0, 0(sp)"},
           {"line": "lw ra, 4(sp)"},
           {"line": "addi sp, sp, 8"},
           {"line": "jalr x0, 0(ra)"}],
  "calls": [{"args": {"a0": 3}, "expect": 9}],
  "params": ["a0"],
  "columns": ["ret"],
  "floors": 3,
  "blanks": [[0, "ret"], [1, "ret"], [2, "ret"]]}'),
(3, 'puzzle', 3, 'tutorial',
 'Find the line that breaks a rule, then pick that rule.
The rules are the calling convention. The Chomper checks that its s registers come back unchanged.',
 'int double(int x) { return x + x; }',
 's registers belong to the caller. Which line writes one without saving it first?',
 'add s1, a0, a0 overwrites s1, and double never saved it. A callee may use s registers only if it saves them in its frame and restores them before returning; a temporary like t0 needs no saving.', 1,
 '{"kind": "lawyer",
  "entry": "double",
  "code": [{"label": "double"},
           {"line": "add s1, a0, a0"},
           {"line": "add a0, s1, x0"},
           {"line": "ret"}],
  "calls": [{"args": {"a0": 5}, "expect": 10}],
  "clauses": ["caller-save", "callee-save", "save-ra", "restore-sp"],
  "verdict": {"lines": [256], "clause": "callee-save"}}'),
(3, 'puzzle', 4, 'frames',
 'Build sqr''s stack frame so every call works.
sqr keeps x in s0 while it calls itself, but s0 belongs to sqr''s caller.',
 'int sqr(int x) { return x < 2 ? x : sqr(x - 1) + x + x - 1; }',
 'sqr makes a call (so ra) and writes s0 (so s0).',
 'The frame holds ra and s0: addi sp, sp, -8, then sw ra, 4(sp) and sw s0, 0(sp), as in lecture. Without s0, the inner call overwrites the outer call''s x; without ra, sqr never finds its way back.', 2,
 '{"kind": "frame",
  "entry": "sqr",
  "code": [{"label": "sqr"},
           {"prologue": true},
           {"line": "slti t0, a0, 2"},
           {"line": "bne t0, x0, done"},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, sqr"},
           {"line": "add a0, a0, s0"},
           {"line": "add a0, a0, s0"},
           {"line": "addi a0, a0, -1"},
           {"label": "done"},
           {"epilogue": true},
           {"line": "jalr x0, 0(ra)"}],
  "blocks": ["ra", "s0", "s1", "a0"],
  "max_slots": 4,
  "par": 2,
  "calls": [{"args": {"a0": 3}, "expect": 9}, {"args": {"a0": 5}, "expect": 25}, {"args": {"a0": 1}, "expect": 1}]}'),
(3, 'puzzle', 5, 'frames',
 'Build sqr''s stack frame so the word at sp+0 holds x.
This sqr keeps x on the stack: after its call, lw t1, 0(sp) reads x back.',
 'int sqr(int x) { return x < 2 ? x : sqr(x - 1) + x + x - 1; }',
 'x arrives in a0. Put a0 at sp+0, the word lw t1, 0(sp) reads, and keep ra above it.',
 'The prologue stores a0 (x) at sp+0 and ra at sp+4. After the call, a0 holds sqr(x - 1) and lw t1, 0(sp) brings x back. a0 isn''t restored on the way out: it carries the return value.', 2,
 '{"kind": "frame",
  "entry": "sqr",
  "code": [{"label": "sqr"},
           {"prologue": true},
           {"line": "slti t0, a0, 2"},
           {"line": "bne t0, x0, done"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, sqr"},
           {"line": "lw t1, 0(sp)"},
           {"line": "add a0, a0, t1"},
           {"line": "add a0, a0, t1"},
           {"line": "addi a0, a0, -1"},
           {"label": "done"},
           {"epilogue": true},
           {"line": "jr ra"}],
  "blocks": ["ra", "a0", "s0", "t0"],
  "max_slots": 4,
  "par": 2,
  "calls": [{"args": {"a0": 3}, "expect": 9}, {"args": {"a0": 5}, "expect": 25}, {"args": {"a0": 1}, "expect": 1}]}'),
(3, 'puzzle', 6, 'frames',
 'Build fib''s stack frame so every call works.
fib makes two calls, and n and fib(n - 1) must both survive the second one.',
 'int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }',
 'fib keeps n in s0 and fib(n - 1) in s1, and it calls, so it needs ra too.',
 'Three words: ra, s0, and s1. Each call to fib overwrites s0 and s1, so every frame saves its caller''s copies and restores them before returning.', 3,
 '{"kind": "frame",
  "entry": "fib",
  "code": [{"label": "fib"},
           {"prologue": true},
           {"line": "slti t0, a0, 2"},
           {"line": "bne t0, x0, done"},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, s0, -1"},
           {"line": "jal ra, fib"},
           {"line": "add s1, x0, a0"},
           {"line": "addi a0, s0, -2"},
           {"line": "jal ra, fib"},
           {"line": "add a0, a0, s1"},
           {"label": "done"},
           {"epilogue": true},
           {"line": "ret"}],
  "blocks": ["ra", "s0", "s1", "a0", "t0"],
  "max_slots": 5,
  "par": 3,
  "calls": [{"args": {"a0": 4}, "expect": 3}, {"args": {"a0": 6}, "expect": 8}, {"args": {"a0": 1}, "expect": 1}]}'),
(3, 'puzzle', 7, 'frames',
 'Build gcd''s stack frame, saving only what it needs.
gcd''s recursive call is the last thing it does before returning.',
 'int gcd(int a, int b) {
    return a == b ? a : a > b ? gcd(a - b, b) : gcd(a, b - a); }',
 'After its call, gcd just returns what it got. Nothing it needs is lost, except its way back.',
 'Only ra. gcd''s answer comes back in a0 and goes straight up, so there''s nothing else to keep across the call. Saving more still works but wastes stack.', 2,
 '{"kind": "frame",
  "entry": "gcd",
  "code": [{"label": "gcd"},
           {"prologue": true},
           {"line": "beq a0, a1, done"},
           {"line": "blt a0, a1, smaller"},
           {"line": "sub a0, a0, a1"},
           {"line": "jal ra, gcd"},
           {"line": "j done"},
           {"label": "smaller"},
           {"line": "sub a1, a1, a0"},
           {"line": "jal ra, gcd"},
           {"label": "done"},
           {"epilogue": true},
           {"line": "jr ra"}],
  "blocks": ["ra", "a0", "a1", "s0"],
  "max_slots": 4,
  "par": 1,
  "calls": [{"args": {"a0": 12, "a1": 18}, "expect": 6}, {"args": {"a0": 7, "a1": 5}, "expect": 1}, {"args": {"a0": 4, "a1": 4}, "expect": 4}]}'),
(3, 'puzzle', 8, 'frames',
 'Build max3''s stack frame, if it needs one at all.
max3 calls no other function and uses only t registers.',
 'int max3(int a, int b, int c);   // the largest of the three',
 'A function that makes no calls keeps ra, and t registers are free to use.',
 'No frame at all. max3 is a leaf: it never calls, so ra is untouched, and it uses only t0, which the caller doesn''t expect to survive. Every saved word would be wasted stack.', 2,
 '{"kind": "frame",
  "entry": "max3",
  "code": [{"label": "max3"},
           {"prologue": true},
           {"line": "add t0, x0, a0"},
           {"line": "bge t0, a1, skip_b"},
           {"line": "add t0, x0, a1"},
           {"label": "skip_b"},
           {"line": "bge t0, a2, skip_c"},
           {"line": "add t0, x0, a2"},
           {"label": "skip_c"},
           {"line": "add a0, x0, t0"},
           {"epilogue": true},
           {"line": "ret"}],
  "blocks": ["ra", "s0", "t0"],
  "max_slots": 3,
  "par": 0,
  "calls": [{"args": {"a0": 3, "a1": 9, "a2": 4}, "expect": 9}, {"args": {"a0": -5, "a1": -2, "a2": -7}, "expect": -2}, {"args": {"a0": 7, "a1": 7, "a2": 1}, "expect": 7}]}'),
(3, 'puzzle', 9, 'elevator',
 'Fill in what each call to fact returns, then ride to check.
fact(4) calls fact(3), and so on down to fact(1).',
 'int fact(int x) { return x <= 1 ? x : x * fact(x - 1); }',
 'fact(1) returns 1. Each floor multiplies its x by what the floor below returned.',
 'fact(1) = 1, fact(2) = 2 × 1 = 2, fact(3) = 3 × 2 = 6, and fact(4) = 4 × 6 = 24. mul runs only after the call returns, which is why x has to wait in s0.', 2,
 '{"kind": "elevator",
  "entry": "fact",
  "function": "fact",
  "code": [{"label": "fact"},
           {"line": "addi sp, sp, -8"},
           {"line": "sw ra, 4(sp)"},
           {"line": "sw s0, 0(sp)"},
           {"line": "addi t0, x0, 1"},
           {"line": "bge t0, a0, done"},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, fact"},
           {"line": "mul a0, a0, s0"},
           {"label": "done"},
           {"line": "lw s0, 0(sp)"},
           {"line": "lw ra, 4(sp)"},
           {"line": "addi sp, sp, 8"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 4}, "expect": 24}],
  "params": ["a0"],
  "columns": ["ret"],
  "floors": 4,
  "blanks": [[0, "ret"], [1, "ret"], [2, "ret"], [3, "ret"]]}'),
(3, 'puzzle', 10, 'elevator',
 'Fill in each call''s arguments, and the final answer.
Each call subtracts the smaller argument from the bigger one.',
 'int gcd(int a, int b) {
    return a == b ? a : a > b ? gcd(a - b, b) : gcd(a, b - a); }',
 'The bigger argument loses the smaller one each floor down, until the two are equal.',
 'gcd(30, 18) calls gcd(12, 18), then gcd(12, 6), then gcd(6, 6), which returns 6. The answer climbs back up unchanged: every floor returns 6.', 2,
 '{"kind": "elevator",
  "entry": "gcd",
  "function": "gcd",
  "code": [{"label": "gcd"},
           {"line": "addi sp, sp, -4"},
           {"line": "sw ra, 0(sp)"},
           {"line": "beq a0, a1, done"},
           {"line": "blt a0, a1, smaller"},
           {"line": "sub a0, a0, a1"},
           {"line": "jal ra, gcd"},
           {"line": "j done"},
           {"label": "smaller"},
           {"line": "sub a1, a1, a0"},
           {"line": "jal ra, gcd"},
           {"label": "done"},
           {"line": "lw ra, 0(sp)"},
           {"line": "addi sp, sp, 4"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 30, "a1": 18}, "expect": 6}],
  "params": ["a0", "a1"],
  "columns": ["ret"],
  "floors": 4,
  "blanks": [[1, "a0"], [1, "a1"], [2, "a0"], [2, "a1"], [3, "a0"], [3, "a1"], [0, "ret"]]}'),
(3, 'puzzle', 11, 'elevator',
 'Fill in the ra each call to sqr saves, in hex.
main calls sqr(4); jal puts PC + 4 in ra, and each sqr saves the ra it gets.',
 'int sqr(int x) { return x < 2 ? x : sqr(x - 1) + x + x - 1; }',
 'main''s jal is at 0x10C, so the first sqr gets 0x110. Every later call comes from the same jal inside sqr.',
 'The first floor saves 0x110, the address after main''s jal ra, sqr. Every deeper floor saves 0x13C, the address after the jal inside sqr, so each return lands back in the middle of sqr.', 3,
 '{"kind": "elevator",
  "entry": "main",
  "function": "sqr",
  "code": [{"label": "main"},
           {"line": "addi sp, sp, -4"},
           {"line": "sw ra, 0(sp)"},
           {"line": "addi a0, x0, 4"},
           {"line": "jal ra, sqr"},
           {"line": "lw ra, 0(sp)"},
           {"line": "addi sp, sp, 4"},
           {"line": "jr ra"},
           {"label": "sqr"},
           {"line": "addi sp, sp, -8"},
           {"line": "sw ra, 4(sp)"},
           {"line": "sw s0, 0(sp)"},
           {"line": "slti t0, a0, 2"},
           {"line": "bne t0, x0, done"},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, sqr"},
           {"line": "add a0, a0, s0"},
           {"line": "add a0, a0, s0"},
           {"line": "addi a0, a0, -1"},
           {"label": "done"},
           {"line": "lw s0, 0(sp)"},
           {"line": "lw ra, 4(sp)"},
           {"line": "addi sp, sp, 8"},
           {"line": "jalr x0, 0(ra)"}],
  "calls": [{"args": {}, "expect": 16}],
  "params": ["a0"],
  "columns": ["ra"],
  "floors": 4,
  "blanks": [[0, "ra"], [1, "ra"], [2, "ra"], [3, "ra"]]}'),
(3, 'puzzle', 12, 'elevator',
 'Fill in the s0 each call to fact saves.
fact keeps x in s0, so each call first saves its caller''s s0 on the stack.',
 'int fact(int x) { return x <= 1 ? x : x * fact(x - 1); }',
 'Each floor saves the s0 its caller was using: the caller''s x.',
 'The first floor saves the Chomper''s s0 (0x5A08). Every deeper floor saves its caller''s x: 5, then 4, 3, 2. That''s how each floor gets its own x back after the call.', 3,
 '{"kind": "elevator",
  "entry": "fact",
  "function": "fact",
  "code": [{"label": "fact"},
           {"line": "addi sp, sp, -8"},
           {"line": "sw ra, 4(sp)"},
           {"line": "sw s0, 0(sp)"},
           {"line": "addi t0, x0, 1"},
           {"line": "bge t0, a0, done"},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, fact"},
           {"line": "mul a0, a0, s0"},
           {"label": "done"},
           {"line": "lw s0, 0(sp)"},
           {"line": "lw ra, 4(sp)"},
           {"line": "addi sp, sp, 8"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 5}, "expect": 120}],
  "params": ["a0"],
  "columns": ["s0"],
  "floors": 5,
  "blanks": [[1, "s0"], [2, "s0"], [3, "s0"], [4, "s0"]]}'),
(3, 'puzzle', 13, 'lawyer',
 'Find the line that breaks a rule, then pick that rule.
plus2 calls inc twice, then returns to the Chomper.',
 'int plus2(int x) { return inc(inc(x)); }',
 'What does jal ra, inc do to the address plus2 needs to get back to the Chomper?',
 'jal ra, inc overwrites ra, plus2''s only way back, and plus2 never saved it. jr ra then returns to plus2 itself, forever. A function that makes calls must save ra first.', 2,
 '{"kind": "lawyer",
  "entry": "plus2",
  "code": [{"label": "plus2"},
           {"line": "jal ra, inc"},
           {"line": "jal ra, inc"},
           {"line": "jr ra"},
           {"label": "inc"},
           {"line": "addi a0, a0, 1"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 5}, "expect": 7}],
  "clauses": ["caller-save", "callee-save", "save-ra", "restore-sp"],
  "verdict": {"lines": [256, 260], "clause": "save-ra"}}'),
(3, 'puzzle', 14, 'lawyer',
 'Find the line that breaks a rule, then pick that rule.
This fact keeps x in t0 while it calls itself.',
 'int fact(int x) { return x <= 1 ? x : x * fact(x - 1); }',
 't registers belong to whoever is running. Does fact still have its x after calling itself?',
 'jal ra, fact is a call made while t0 still holds x, and the inner fact overwrites t0. The caller must save any t or a register it needs after a call, or keep the value in an s register.', 3,
 '{"kind": "lawyer",
  "entry": "fact",
  "code": [{"label": "fact"},
           {"line": "addi sp, sp, -4"},
           {"line": "sw ra, 0(sp)"},
           {"line": "addi t0, x0, 1"},
           {"line": "bge t0, a0, done"},
           {"line": "add t0, x0, a0"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, fact"},
           {"line": "mul a0, a0, t0"},
           {"label": "done"},
           {"line": "lw ra, 0(sp)"},
           {"line": "addi sp, sp, 4"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 4}, "expect": 24}],
  "clauses": ["caller-save", "callee-save", "save-ra", "restore-sp"],
  "verdict": {"lines": [280, 284], "clause": "caller-save"}}'),
(3, 'puzzle', 15, 'lawyer',
 'Find the line that breaks a rule, then pick that rule.
The Chomper''s call to gcd crashes. Watch it to see what goes wrong.',
 'int gcd(int a, int b) {
    return a == b ? a : a > b ? gcd(a - b, b) : gcd(a, b - a); }',
 'Compare how much stack gcd takes with how much it gives back.',
 'The prologue takes 8 bytes (addi sp, sp, -8), but addi sp, sp, 4 gives back only 4. Each return leaves sp 4 bytes low, so the caller''s lw ra reads the wrong word and jumps to junk.', 2,
 '{"kind": "lawyer",
  "entry": "gcd",
  "code": [{"label": "gcd"},
           {"line": "addi sp, sp, -8"},
           {"line": "sw ra, 4(sp)"},
           {"line": "beq a0, a1, done"},
           {"line": "blt a0, a1, smaller"},
           {"line": "sub a0, a0, a1"},
           {"line": "jal ra, gcd"},
           {"line": "j done"},
           {"label": "smaller"},
           {"line": "sub a1, a1, a0"},
           {"line": "jal ra, gcd"},
           {"label": "done"},
           {"line": "lw ra, 4(sp)"},
           {"line": "addi sp, sp, 4"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 30, "a1": 18}, "expect": 6}],
  "clauses": ["caller-save", "callee-save", "save-ra", "restore-sp"],
  "verdict": {"lines": [296], "clause": "restore-sp"}}'),
(3, 'puzzle', 16, 'lawyer',
 'Find the line that breaks a rule, then pick that rule.
fib saves ra and s0, then keeps fib(n - 1) somewhere during its second call.',
 'int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }',
 'Which registers does fib''s prologue save? Which ones does fib write?',
 'add s1, x0, a0 writes s1, which fib never saved. Every inner fib overwrites it, and the Chomper gets its s1 back changed. The prologue must save every s register the function uses.', 3,
 '{"kind": "lawyer",
  "entry": "fib",
  "code": [{"label": "fib"},
           {"line": "addi sp, sp, -8"},
           {"line": "sw ra, 4(sp)"},
           {"line": "sw s0, 0(sp)"},
           {"line": "slti t0, a0, 2"},
           {"line": "bne t0, x0, done"},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, s0, -1"},
           {"line": "jal ra, fib"},
           {"line": "add s1, x0, a0"},
           {"line": "addi a0, s0, -2"},
           {"line": "jal ra, fib"},
           {"line": "add a0, a0, s1"},
           {"label": "done"},
           {"line": "lw s0, 0(sp)"},
           {"line": "lw ra, 4(sp)"},
           {"line": "addi sp, sp, 8"},
           {"line": "ret"}],
  "calls": [{"args": {"a0": 4}, "expect": 3}],
  "clauses": ["caller-save", "callee-save", "save-ra", "restore-sp"],
  "verdict": {"lines": [288], "clause": "callee-save"}}'),
(3, 'puzzle', 17, 'finale',
 'Build fact''s stack frame small enough to beat the Chomper.
The Chomper eats a stack word every 8 instructions. fact(6) must finish first.',
 'int fact(int x) { return x <= 1 ? x : x * fact(x - 1); }',
 'fact needs ra and the s0 it keeps x in. Every extra word makes each floor bigger and slower.',
 'Two words, ra and s0, is the tightest frame that works: six floors of two words fit above the Chomper, and short prologues keep the climb back up ahead of it. A bigger frame runs into the heap.', 3,
 '{"kind": "frame",
  "entry": "fact",
  "code": [{"label": "fact"},
           {"prologue": true},
           {"line": "addi t0, x0, 1"},
           {"line": "bge t0, a0, done"},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, fact"},
           {"line": "mul a0, a0, s0"},
           {"label": "done"},
           {"epilogue": true},
           {"line": "jr ra"}],
  "blocks": ["ra", "s0", "s1", "a0", "t0"],
  "max_slots": 5,
  "par": 2,
  "calls": [{"args": {"a0": 4}, "expect": 24}, {"args": {"a0": 6}, "expect": 720}, {"args": {"a0": 1}, "expect": 1}],
  "stack_words": 20,
  "chomper": {"start": 8, "every": 8}}');

COMMIT;
