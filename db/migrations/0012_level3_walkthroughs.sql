-- Level 3, the Call Stack Tower, becomes a story of eight walkthroughs that
-- students follow along rather than a quiz. Each room is a short program played
-- line by line on the tower, with a caption for every line; at its moments the
-- student makes the move (a call, a stack frame, where to keep a value, a base
-- case). A wrong move plays out in the game, shows what breaks, and rewinds, so
-- only a working set of moves is ever sent. The rooms go in order (no draw):
-- a call, the way back, keeping a value, borrowed registers, recursion down and
-- up, the base case, two calls, and the race against the Chomper.
--
--   walk  `code` is the program: lines (each may carry a `note` for its
--         caption), labels, an epilogue mark, and moments. A moment lists
--         `options`: a block of `lines` ("lines"), or a `frame` whose prologue
--         goes at the moment and whose epilogue goes at the mark ("frame").
--         The answer is {"choices": [the option picked at each moment]}; it
--         passes when the program keeps the contract on every call in `calls`.
--         `watch`, `intro`, and each option's label, `good`, and `why` only
--         drive the screen.
--
-- Every room 0009 inserted is retired, never deleted, so old attempts keep
-- pointing at what students saw; runs already started keep their snapshots,
-- which server/call_stack.py still grades. server/test_call_stack.py checks
-- every walkthrough.
BEGIN;

-- Recreated with the walk kind; still written with -> rather than ?& (see 0001).
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
                WHEN 'walk' THEN
                         jsonb_typeof(payload -> 'code') = 'array'
                     AND jsonb_typeof(payload -> 'calls') = 'array'
                     AND jsonb_array_length(payload -> 'calls') >= 1
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

-- The rooms play in order: no draw.
UPDATE aa.levels SET draw = NULL WHERE id = 3;

UPDATE aa.questions SET is_active = false, retired_at = now()
    WHERE level_id = 3 AND is_active;

INSERT INTO aa.questions (level_id, type, ordinal, prompt, code_snippet, hint, explanation, difficulty, payload) VALUES
(3, 'puzzle', 1,
 'Step through plus1 and make its call to triple.
Press Play, or step one line at a time. Watch ra: it''s every function''s way back.',
 'int plus1(int x) { return triple(x) + 1; }',
 'A call has to leave a way back. Which of the two does?',
 'jal ra, triple does two things: it puts the address of the line after it in ra, then jumps. triple''s jr ra uses that address to come back. j only jumps, so nothing tells triple where to return.', 1,
 '{"kind": "walk",
  "entry": "plus1",
  "code": [{"label": "plus1"},
           {"line": "addi sp, sp, -4", "note": "plus1 makes room for one word on the stack..."},
           {"line": "sw ra, 0(sp)", "note": "...and keeps the Chomper''s address there, since ra is about to change. The next room is all about why."},
           {"moment": "lines", "ask": "plus1 needs triple(x). Make the call:", "options": [{"label": "jal ra, triple", "lines": ["jal ra, triple"], "good": true, "why": "jal put the address of the next line in ra, then jumped: triple knows where to come back."}, {"label": "j triple", "lines": ["j triple"], "good": false, "why": "j jumped without leaving a way back, so ra still held the Chomper''s address. triple''s jr ra went straight back to the Chomper: plus1 never added its 1 or gave back its stack."}]},
           {"line": "addi a0, a0, 1", "note": "Back in plus1, with triple''s answer in a0. Add 1."},
           {"line": "lw ra, 0(sp)", "note": "Get the Chomper''s address back into ra..."},
           {"line": "addi sp, sp, 4", "note": "...give the stack word back..."},
           {"line": "jr ra", "note": "...and return to the Chomper."},
           {"label": "triple"},
           {"line": "slli t0, a0, 1", "note": "triple doubles x into t0..."},
           {"line": "add a0, a0, t0", "note": "...then adds x once more: 3x, in a0, where return values go."},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 4}, "expect": 13}],
  "watch": ["a0", "ra", "sp", "t0"],
  "intro": "The Chomper calls plus1(4): a0 = 4, and ra = 0x400, the Chomper''s own address, so plus1 can come back."}'),
(3, 'puzzle', 2,
 'Step through plus2 and keep its way back safe.
plus2 calls inc twice, and every jal changes ra.',
 'int plus2(int x) { return inc(inc(x)); }',
 'Each jal ra writes over ra. Where can the Chomper''s address wait until plus2 is done?',
 'A function that makes calls loses ra at its first jal, so it saves ra in its stack frame first and loads it back just before returning. That pair (the prologue and the epilogue) is the start of every stack frame.', 1,
 '{"kind": "walk",
  "entry": "plus2",
  "code": [{"label": "plus2"},
           {"moment": "frame", "ask": "plus2 is about to call inc twice, and each jal writes over ra, its only way back to the Chomper. Before the calls, push:", "options": [{"label": "ra onto the stack", "frame": ["ra"], "good": true, "why": "The Chomper''s address is safe at sp+0. The matching lw ra goes just before plus2 returns."}, {"label": "nothing", "frame": [], "good": false, "why": "The first jal overwrote ra with an address inside plus2, and nothing had kept the Chomper''s. So plus2''s jr ra jumped back into plus2 itself, again and again: it never returned."}]},
           {"line": "jal ra, inc", "note": "First call: ra now points back into plus2."},
           {"line": "jal ra, inc", "note": "Second call: ra points into plus2 again. The Chomper''s address is only on the stack now."},
           {"epilogue": true},
           {"line": "jr ra"},
           {"label": "inc"},
           {"line": "addi a0, a0, 1"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 5}, "expect": 7}],
  "watch": ["a0", "ra", "sp"],
  "intro": "The Chomper calls plus2(5) with ra = 0x400. Keep an eye on ra as plus2 makes its calls."}'),
(3, 'puzzle', 3,
 'Step through plusx and keep x safe across a call.
plusx needs x again after calling inc.',
 'int plusx(int x) { return inc(x) + x; }',
 'Any function may change t registers. What can''t inc touch?',
 't registers are temporaries: a function called in between may change them, as inc does here. A value needed after a call goes in the caller''s own stack frame (or in an s register, next room).', 2,
 '{"kind": "walk",
  "entry": "plusx",
  "code": [{"label": "plusx"},
           {"line": "addi sp, sp, -8", "note": "plusx makes room for two words..."},
           {"line": "sw ra, 4(sp)", "note": "...keeps ra in the top one, and leaves sp+0 free."},
           {"moment": "lines", "ask": "plusx needs x after calling inc, but a call may change any t or a register. Keep x:", "options": [{"label": "in t0", "lines": ["add t0, a0, x0", "jal ra, inc", "add a0, a0, t0"], "good": false, "why": "inc used t0 too: when it returned, t0 held inc''s own work (6), not x, so plusx returned 12 instead of 11. t registers don''t survive a call."}, {"label": "on the stack, at sp+0", "lines": ["sw a0, 0(sp)", "jal ra, inc", "lw t0, 0(sp)", "add a0, a0, t0"], "good": true, "why": "sp+0 is plusx''s own word: inc can''t touch it, so x is still there after the call."}]},
           {"line": "lw ra, 4(sp)"},
           {"line": "addi sp, sp, 8"},
           {"line": "jr ra"},
           {"label": "inc"},
           {"line": "addi t0, a0, 1", "note": "inc works in t0: any function may."},
           {"line": "add a0, t0, x0"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 5}, "expect": 11}],
  "watch": ["a0", "t0", "ra", "sp"],
  "intro": "The Chomper calls plusx(5). plusx will need x (5) again after its call."}'),
(3, 'puzzle', 4,
 'Step through plusx and keep the Chomper''s s0 safe.
This plusx keeps x in s0, a register calls leave alone.',
 'int plusx(int x) { return inc(x) + x; }',
 's0 survives calls because every function that uses it puts it back. Is plusx one of them?',
 's registers are saved registers: a function may use them only if it saves the old value first and puts it back before returning. In exchange, every call it makes leaves them alone, which is why x is still in s0 after jal ra, inc.', 2,
 '{"kind": "walk",
  "entry": "plusx",
  "code": [{"label": "plusx"},
           {"moment": "frame", "ask": "plusx will keep x in s0 across its call to inc. But s0 belongs to whoever called plusx, and plusx makes a call too. Its frame saves:", "options": [{"label": "ra and s0", "frame": ["s0", "ra"], "good": true, "why": "The Chomper''s s0 waits at sp+0 and ra at sp+4; the matching loads go just before plusx returns."}, {"label": "only ra", "frame": ["ra"], "good": false, "why": "plusx wrote x into s0 without saving the Chomper''s s0 first, so the Chomper got its s0 back changed (s0 = 5). A function must save every s register it uses."}, {"label": "only s0", "frame": ["s0"], "good": false, "why": "With ra not saved, jal ra, inc took plusx''s only way back: its return jumped back into plusx, which then read past the top of the stack instead of reaching the Chomper."}]},
           {"line": "add s0, x0, a0", "note": "x goes in s0, which inc promises to leave alone."},
           {"line": "jal ra, inc"},
           {"line": "add a0, a0, s0", "note": "s0 still holds x after the call."},
           {"epilogue": true},
           {"line": "jr ra"},
           {"label": "inc"},
           {"line": "addi a0, a0, 1"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 5}, "expect": 11}],
  "watch": ["a0", "s0", "ra", "sp"],
  "intro": "The Chomper calls plusx(5). Watch s0: it holds the Chomper''s own value (0x5A08) to start."}'),
(3, 'puzzle', 5,
 'Ride sqr(3) down the tower and back up.
sqr calls itself: every call adds a floor, and every return takes one away.',
 'int sqr(int x) { return x < 2 ? x : sqr(x - 1) + x + x - 1; }',
 'Every floor runs the same code. What does each one need to keep for after its call?',
 'Recursion works because every call gets its own frame: sqr(3), sqr(2), and sqr(1) each keep their own ra and their own x (in s0) on their own floor. On the way back up, each floor adds x + x - 1 to what the floor below returned: 1, then 4, then 9.', 2,
 '{"kind": "walk",
  "entry": "sqr",
  "code": [{"label": "sqr"},
           {"moment": "frame", "ask": "sqr calls itself, and keeps x in s0 for after the call. Each floor''s frame saves:", "options": [{"label": "ra and s0", "frame": ["s0", "ra"], "good": true, "why": "Every floor will keep its own way back and its caller''s s0."}, {"label": "only ra", "frame": ["ra"], "good": false, "why": "Each inner sqr wrote its own x into s0 and nothing saved the outer one''s, so on the way back up every floor added the wrong x, and the Chomper''s s0 came back changed."}]},
           {"line": "slti t0, a0, 2", "note": "Is x less than 2?"},
           {"line": "bne t0, x0, done", "note": "If so, x is the answer: skip to the end."},
           {"line": "add s0, x0, a0", "note": "Keep x in s0 for after the call."},
           {"line": "addi a0, a0, -1", "note": "The argument for the next floor: x - 1."},
           {"line": "jal ra, sqr", "note": "sqr calls itself: one floor down."},
           {"line": "add a0, a0, s0", "note": "Back up a floor: sqr(x - 1) is in a0, and this floor''s x is in s0 again."},
           {"line": "add a0, a0, s0"},
           {"line": "addi a0, a0, -1"},
           {"label": "done"},
           {"epilogue": true},
           {"line": "jalr x0, 0(ra)"}],
  "calls": [{"args": {"a0": 3}, "expect": 9}],
  "watch": ["a0", "s0", "ra", "sp"],
  "intro": "The Chomper calls sqr(3). Each call to sqr will hang a new floor below the last."}'),
(3, 'puzzle', 6,
 'Give fact a bottom floor.
fact calls itself with x - 1. Something has to make it stop.',
 'int fact(int x) { return x <= 1 ? x : x * fact(x - 1); }',
 'fact(1) is 1. Which check stops there?',
 'Every recursive function needs a base case: an input it answers without calling itself. Without one, each call makes another, every call takes a new frame, and the tower runs off the bottom of the stack.', 2,
 '{"kind": "walk",
  "entry": "fact",
  "code": [{"label": "fact"},
           {"line": "addi sp, sp, -8", "note": "fact''s frame: two words..."},
           {"line": "sw ra, 4(sp)"},
           {"line": "sw s0, 0(sp)", "note": "...for ra and the s0 it will borrow."},
           {"moment": "lines", "ask": "fact is about to call itself with x - 1. Before that, stop when:", "options": [{"label": "x ≤ 1 (return x)", "lines": ["addi t0, x0, 1", "bge t0, a0, done"], "good": true, "why": "fact(1) will skip the call and return 1, and every floor above it will multiply on the way back up."}, {"label": "never", "lines": [], "good": false, "why": "With nothing to stop it, fact kept calling itself (x went 3, 2, 1, 0, -1, ...), and every call took another frame, until the tower ran off the bottom of the stack."}, {"label": "x ≥ 1 (return x)", "lines": ["addi t0, x0, 1", "bge a0, t0, done"], "good": false, "why": "x ≥ 1 was true right away, so fact(3) returned 3 without calling itself at all."}]},
           {"line": "add s0, x0, a0", "note": "Keep x for after the call."},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, fact", "note": "One floor down: fact(x - 1)."},
           {"line": "mul a0, a0, s0", "note": "Back up: x × fact(x - 1)."},
           {"label": "done"},
           {"line": "lw s0, 0(sp)"},
           {"line": "lw ra, 4(sp)"},
           {"line": "addi sp, sp, 8"},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 3}, "expect": 6}],
  "watch": ["a0", "t0", "s0", "sp"],
  "intro": "The Chomper calls fact(3). This stack is short: 12 words.",
  "stack_words": 12}'),
(3, 'puzzle', 7,
 'Follow fib(3) through both of its calls.
fib calls itself twice, and keeps values in s0 and s1 in between.',
 'int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }',
 'Count the s registers fib writes.',
 'fib keeps n in s0 and fib(n - 1) in s1 while it makes its second call, so its frame saves ra, s0, and s1. A function saves every s register it uses, however many that is.', 2,
 '{"kind": "walk",
  "entry": "fib",
  "code": [{"label": "fib"},
           {"moment": "frame", "ask": "fib calls itself twice. It keeps n in s0, and fib(n - 1) in s1 during the second call. Its frame saves:", "options": [{"label": "ra, s0, and s1", "frame": ["s1", "s0", "ra"], "good": true, "why": "Three words per floor: the way back, and both of the caller''s s registers."}, {"label": "ra and s0", "frame": ["s0", "ra"], "good": false, "why": "fib wrote fib(n - 1) into s1 without saving the s1 it was given, so the Chomper got its s1 back changed. Saving s0 isn''t enough when you use s1 too."}]},
           {"line": "slti t0, a0, 2", "note": "n < 2 is the base case: fib(n) = n."},
           {"line": "bne t0, x0, done"},
           {"line": "add s0, x0, a0", "note": "Keep n."},
           {"line": "addi a0, s0, -1"},
           {"line": "jal ra, fib", "note": "First call: fib(n - 1)."},
           {"line": "add s1, x0, a0", "note": "Keep fib(n - 1) in s1 for after the second call."},
           {"line": "addi a0, s0, -2"},
           {"line": "jal ra, fib", "note": "Second call: fib(n - 2)."},
           {"line": "add a0, a0, s1", "note": "fib(n - 2) + fib(n - 1)."},
           {"label": "done"},
           {"epilogue": true},
           {"line": "ret"}],
  "calls": [{"args": {"a0": 3}, "expect": 2}],
  "watch": ["a0", "s0", "s1", "sp"],
  "intro": "The Chomper calls fib(3). Watch the floors come and go: fib(2) goes down two more, then fib(1)."}'),
(3, 'puzzle', 8,
 'Build fact''s frame and outrun the Chomper.
The Chomper climbs up from the heap while fact(6) runs.',
 'int fact(int x) { return x <= 1 ? x : x * fact(x - 1); }',
 'fact needs ra and the s0 it keeps x in. Anything more makes every floor bigger.',
 'Two words, ra and s0, is the tightest frame that works: each of fact(6)''s floors takes 8 bytes, so the stack stays well ahead of the Chomper. Saving more still works, but every extra word is paid on every floor.', 2,
 '{"kind": "walk",
  "entry": "fact",
  "code": [{"label": "fact"},
           {"moment": "frame", "ask": "The Chomper eats a stack word every 8 instructions, and fact(6) needs six floors. fact''s frame saves:", "options": [{"label": "ra and s0", "frame": ["s0", "ra"], "good": true, "why": "Two words a floor: fact(6) has room to spare."}, {"label": "ra, s0, and t0", "frame": ["t0", "s0", "ra"], "good": true, "why": "Three words a floor: fact(6) still finishes first, but by a single word.", "loose": true}, {"label": "only ra", "frame": ["ra"], "good": false, "why": "x lived in s0, and nothing saved it: every floor multiplied by the wrong x, and the Chomper''s s0 came back changed."}]},
           {"line": "addi t0, x0, 1"},
           {"line": "bge t0, a0, done", "note": "fact(1) is the bottom floor."},
           {"line": "add s0, x0, a0"},
           {"line": "addi a0, a0, -1"},
           {"line": "jal ra, fact"},
           {"line": "mul a0, a0, s0"},
           {"label": "done"},
           {"epilogue": true},
           {"line": "jr ra"}],
  "calls": [{"args": {"a0": 6}, "expect": 720}],
  "watch": ["a0", "s0", "ra", "sp"],
  "intro": "The Chomper calls fact(6) and starts climbing up from the heap.",
  "stack_words": 25,
  "chomper": {"start": 8, "every": 8}}');

COMMIT;
