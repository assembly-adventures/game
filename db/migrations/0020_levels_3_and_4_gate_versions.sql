-- Levels 3 and 4 get three versions of every gate. Each gate becomes a pool:
-- its original room plus two new versions that teach the same idea with a
-- different program, circuit, or waveform. A run draws one version per pool, in
-- story order (Level 3: eight gates, Level 4: ten), and with the draw from 0019 a
-- player sees every version of a gate before any comes back. The new rooms were
-- written to the same rules the tests enforce (server/test_call_stack.py,
-- server/test_timing.py) and are generated from each level's guest_rooms.json by
-- tools/rooms.py.
BEGIN;


-- Level 3: the original rooms join their gates' pools.
UPDATE aa.questions SET pool = 'call' WHERE level_id = 3 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET pool = 'way-back' WHERE level_id = 3 AND ordinal = 2 AND is_active;
UPDATE aa.questions SET pool = 'keep-value' WHERE level_id = 3 AND ordinal = 3 AND is_active;
UPDATE aa.questions SET pool = 'saved-registers' WHERE level_id = 3 AND ordinal = 4 AND is_active;
UPDATE aa.questions SET pool = 'recursion' WHERE level_id = 3 AND ordinal = 5 AND is_active;
UPDATE aa.questions SET pool = 'base-case' WHERE level_id = 3 AND ordinal = 6 AND is_active;
UPDATE aa.questions SET pool = 'two-calls' WHERE level_id = 3 AND ordinal = 7 AND is_active;
UPDATE aa.questions SET pool = 'race' WHERE level_id = 3 AND ordinal = 8 AND is_active;

-- Level 3: the new versions.
INSERT INTO aa.questions (level_id, type, ordinal, pool, prompt, code_snippet, hint, explanation, difficulty, payload, answer) VALUES
(3, 'puzzle', 9, 'call',
 'Step through perim and make its call to sum.
Press Play, or step one line at a time, and watch ra: it''s how sum gets back to perim.',
 'int perim(int w, int h) { return 2 * sum(w, h); }',
 'sum comes back with jr ra. Which of the two blocks tells it where perim is?',
 'A call is a jump that leaves a way back: jal ra puts the address of the next line in ra as it jumps, and the function''s jr ra returns there. j leaves ra as it was, so the function returns wherever ra already pointed.',
 1,
 '{"kind": "walk", "entry": "perim", "code": [{"label": "perim"}, {"line": "addi sp, sp, -4", "note": "perim makes room for one word on the stack..."}, {"line": "sw ra, 0(sp)", "note": "...and saves the Chomper''s address in it, because the call is about to change ra."}, {"moment": "lines", "ask": "perim needs sum(w, h), and w and h are already in a0 and a1. Make the call:", "options": [{"label": "jal ra, sum", "lines": ["jal ra, sum"], "good": true, "why": "jal put the address of the next line in ra, then jumped: sum''s jr ra will come back to perim."}, {"label": "j sum", "lines": ["j sum"], "good": false, "why": "j jumped to sum but left the Chomper''s address in ra, so sum''s jr ra went straight back to the Chomper with 8: perim never doubled it to 16 or gave back its stack word."}]}, {"line": "add a0, a0, a0", "note": "Back in perim with w + h in a0. Doubled, it''s the perimeter of a w by h rectangle."}, {"line": "lw ra, 0(sp)", "note": "Load the Chomper''s address back into ra..."}, {"line": "addi sp, sp, 4", "note": "...hand the stack word back..."}, {"line": "jr ra", "note": "...and return to the Chomper."}, {"label": "sum"}, {"line": "add a0, a0, a1", "note": "sum adds its two arguments, a0 + a1, into a0, where return values go."}, {"line": "jr ra", "note": "sum returns to whatever address ra holds."}], "calls": [{"args": {"a0": 5, "a1": 3}, "expect": 16}], "watch": ["a0", "ra", "sp"], "intro": "The Chomper calls perim(5, 3): w = 5 in a0, h = 3 in a1, and ra = 0x400, the Chomper''s own address."}',
 '{"choices": [0]}'),
(3, 'puzzle', 10, 'call',
 'Step through halfsq and make its call to square.
Press Play, or step one line at a time, and watch ra: it''s every call''s way back.',
 'int halfsq(int x) { return square(x) / 2; }',
 'jal writes the way back into the register it names. Which register does square return through?',
 'jal saves the way back in the register it names, and a function returns through ra, so a call is jal ra, f. jal x0, f is the same as j f: x0 always reads 0, so the way back is thrown away.',
 1,
 '{"kind": "walk", "entry": "halfsq", "code": [{"label": "halfsq"}, {"line": "addi sp, sp, -4", "note": "halfsq makes room for a word on the stack..."}, {"line": "sw ra, 0(sp)", "note": "...and puts the Chomper''s address in it, since making a call will change ra."}, {"moment": "lines", "ask": "halfsq needs square(x), and x is already in a0. Make the call:", "options": [{"label": "jal ra, square", "lines": ["jal ra, square"], "good": true, "why": "jal ra put the address of the next line in ra before jumping, right where square''s jr ra looks."}, {"label": "jal x0, square", "lines": ["jal x0, square"], "good": false, "why": "jal x0 is j: the way back went into x0, which stays 0, and ra kept the Chomper''s address. So square took 36 straight to the Chomper: halfsq never halved it or gave back its stack word."}]}, {"line": "srai a0, a0, 1", "note": "Back in halfsq with x × x in a0. Shifting it right one bit halves it."}, {"line": "lw ra, 0(sp)", "note": "The Chomper''s address goes back into ra..."}, {"line": "addi sp, sp, 4", "note": "...the stack word goes back..."}, {"line": "jr ra", "note": "...and halfsq returns to the Chomper."}, {"label": "square"}, {"line": "mul a0, a0, a0", "note": "square multiplies x by itself..."}, {"line": "jr ra", "note": "...and returns to the address in ra."}], "calls": [{"args": {"a0": 6}, "expect": 18}], "watch": ["a0", "ra", "sp"], "intro": "The Chomper calls halfsq(6): a0 = 6, and ra = 0x400, the Chomper''s own address, so halfsq can return."}',
 '{"choices": [0]}'),
(3, 'puzzle', 11, 'way-back',
 'Step through above and keep its way back safe.
above makes only one call, to max, but one jal is all it takes to change ra.',
 'int above(int a, int b) { return max(a, b) + 1; }',
 'Even one jal writes over ra. Where can the Chomper''s address wait while max runs?',
 'Any call writes over ra, even a function''s only one. So a function that makes a call saves ra in its stack frame before calling, and loads it back just before it returns.',
 1,
 '{"kind": "walk", "entry": "above", "code": [{"label": "above"}, {"moment": "frame", "ask": "above calls max once, and that jal will write over ra, its only way back to the Chomper. Before the call, push:", "options": [{"label": "ra onto the stack", "frame": ["ra"], "good": true, "why": "The Chomper''s address waits at sp+0 while max runs. The matching lw ra goes in just before above returns."}, {"label": "nothing", "frame": [], "good": false, "why": "jal ra, max left ra pointing at above''s own addi, and nothing had kept the Chomper''s address. So jr ra kept jumping back to it (a0 = 10, 11, 12, ...): above never returned."}]}, {"line": "jal ra, max", "note": "The call: ra now points at the next line in above, not at the Chomper."}, {"line": "addi a0, a0, 1", "note": "Back from max with the bigger of a and b in a0. Add 1: the first number above both."}, {"epilogue": true}, {"line": "jr ra"}, {"label": "max"}, {"line": "bge a0, a1, done", "note": "If a ≥ b, a is the bigger one, and it''s already in a0..."}, {"line": "add a0, a1, x0", "note": "...if not, max copies b into a0."}, {"label": "done"}, {"line": "jr ra"}], "calls": [{"args": {"a0": 4, "a1": 9}, "expect": 10}], "watch": ["a0", "ra", "sp"], "intro": "The Chomper calls above(4, 9) with ra = 0x400: a = 4 in a0, b = 9 in a1. Watch ra at the call."}',
 '{"choices": [0]}'),
(3, 'puzzle', 12, 'way-back',
 'Step through pow4 and keep its way back safe.
pow4 squares x, then squares the answer: two calls, and every jal changes ra.',
 'int pow4(int x) { return square(square(x)); }',
 'pow4 never needs x again once square has it. What does it need at the very end?',
 'Every jal writes over ra, so a function that makes calls saves ra in its stack frame before the first one and loads it back just before returning. Saving an argument instead keeps a value, not the way back.',
 1,
 '{"kind": "walk", "entry": "pow4", "code": [{"label": "pow4"}, {"moment": "frame", "ask": "pow4 calls square twice. Each call changes a0, and each jal writes over ra. Before the calls, push:", "options": [{"label": "ra onto the stack", "frame": ["ra"], "good": true, "why": "The Chomper''s address waits at sp+0 through both calls. x needs no saving: pow4 only uses square''s answers."}, {"label": "x (a0) onto the stack", "frame": ["a0"], "good": false, "why": "That kept x (3) at sp+0, but not the Chomper''s address: after the second jal, ra pointed at pow4''s own addi sp. So jr ra kept jumping back there, and pow4 never returned."}]}, {"line": "jal ra, square", "note": "First call: x × x. ra now points back into pow4."}, {"line": "jal ra, square", "note": "Second call squares that answer. ra points into pow4 again."}, {"epilogue": true}, {"line": "jr ra"}, {"label": "square"}, {"line": "mul a0, a0, a0"}, {"line": "jr ra"}], "calls": [{"args": {"a0": 3}, "expect": 81}], "watch": ["a0", "ra", "sp"], "intro": "The Chomper calls pow4(3) with ra = 0x400. Watch ra each time pow4 calls square."}',
 '{"choices": [0]}');
INSERT INTO aa.questions (level_id, type, ordinal, pool, prompt, code_snippet, hint, explanation, difficulty, payload, answer) VALUES
(3, 'puzzle', 13, 'keep-value',
 'Step through cubeplus and keep y safe across a call.
cube takes only x, but cubeplus needs y again after calling it.',
 'int cubeplus(int x, int y) { return cube(x) + y; }',
 'Any function may change a and t registers, even ones it takes no argument in. What can''t cube touch?',
 'A call may change any t or a register, even one the callee takes no argument in, as cube does with a1. A value needed after a call goes in the caller''s own stack frame.',
 2,
 '{"kind": "walk", "entry": "cubeplus", "code": [{"label": "cubeplus"}, {"line": "addi sp, sp, -8", "note": "cubeplus makes room for two words..."}, {"line": "sw ra, 4(sp)", "note": "...keeps ra in the top one, and leaves sp+0 free."}, {"moment": "lines", "ask": "cubeplus needs y after calling cube. cube takes only x, but a call may change any t or a register. Keep y:", "options": [{"label": "where it is, in a1", "lines": ["jal ra, cube", "add a0, a0, a1"], "good": false, "why": "cube used a1 for its own work: when it returned, a1 held x * x (9), not y, so cubeplus returned 36 instead of 31. a registers don''t survive a call either."}, {"label": "on the stack, at sp+0", "lines": ["sw a1, 0(sp)", "jal ra, cube", "lw t0, 0(sp)", "add a0, a0, t0"], "good": true, "why": "sp+0 is cubeplus''s own word: cube can''t touch it, so y was still there after the call."}]}, {"line": "lw ra, 4(sp)"}, {"line": "addi sp, sp, 8"}, {"line": "jr ra"}, {"label": "cube"}, {"line": "mul a1, a0, a0", "note": "cube keeps x * x in a1: any function may use a and t registers for its own work."}, {"line": "mul a0, a1, a0", "note": "x * x, times x again: x cubed."}, {"line": "jr ra"}], "calls": [{"args": {"a0": 3, "a1": 4}, "expect": 31}], "watch": ["a0", "t0", "ra", "sp"], "intro": "The Chomper calls cubeplus(3, 4): x = 3 in a0, y = 4 in a1. cubeplus needs y after its call."}',
 '{"choices": [1]}'),
(3, 'puzzle', 14, 'keep-value',
 'Step through times5 and keep x safe across a call.
quad builds a frame of its own, and times5 needs x again after calling it.',
 'int times5(int x) { return quad(x) + x; }',
 'Everything below sp is free for the next call''s frame. Which words has times5 made room for?',
 'The stack below sp is free for whatever is called next, so the callee''s frame lands right there. A value needed after a call goes in a word the caller made room for in its own frame.',
 2,
 '{"kind": "walk", "entry": "times5", "code": [{"label": "times5"}, {"line": "addi sp, sp, -8", "note": "times5 makes room for two words..."}, {"line": "sw ra, 4(sp)", "note": "...keeps ra in the top one, and leaves sp+0 free."}, {"moment": "lines", "ask": "times5 needs x after calling quad, so x goes on the stack. Keep x in the word at:", "options": [{"label": "sp+0, in times5''s frame", "lines": ["sw a0, 0(sp)", "jal ra, quad", "lw t0, 0(sp)", "add a0, a0, t0"], "good": true, "why": "sp+0 is inside times5''s own frame. quad''s frame went below it, so x was still there after the call."}, {"label": "sp-4, just below the frame", "lines": ["sw a0, -4(sp)", "jal ra, quad", "lw t0, -4(sp)", "add a0, a0, t0"], "good": false, "why": "sp-4 was below times5''s frame, free for the next call: quad''s frame went there and its saved ra (0x110 = 272) replaced x, so times5 returned 16 + 272 = 288 instead of 20."}]}, {"line": "lw ra, 4(sp)"}, {"line": "addi sp, sp, 8"}, {"line": "jr ra"}, {"label": "quad"}, {"line": "addi sp, sp, -4", "note": "quad makes calls too, so it builds a frame of its own, right below sp..."}, {"line": "sw ra, 0(sp)", "note": "...and keeps its ra there."}, {"line": "jal ra, dbl"}, {"line": "jal ra, dbl", "note": "Doubled twice: 4 * x."}, {"line": "lw ra, 0(sp)"}, {"line": "addi sp, sp, 4"}, {"line": "jr ra"}, {"label": "dbl"}, {"line": "add a0, a0, a0"}, {"line": "jr ra"}], "calls": [{"args": {"a0": 4}, "expect": 20}], "watch": ["a0", "t0", "ra", "sp"], "intro": "The Chomper calls times5(4). times5 will need x (4) again after its call to quad."}',
 '{"choices": [0]}'),
(3, 'puzzle', 15, 'saved-registers',
 'Step through grow and keep the Chomper''s s registers safe.
This grow keeps x in s1, a register calls leave alone.',
 'int grow(int x) { return x + half(x); }',
 'A frame protects only the registers it saves. Which s register does grow write?',
 'A function must save each s register it writes, whichever one that is, and put it back before returning: saving a different one protects nothing. It saves ra too when it makes calls.',
 2,
 '{"kind": "walk", "entry": "grow", "code": [{"label": "grow"}, {"moment": "frame", "ask": "grow will keep x in s1 across its call to half. But s1 belongs to whoever called grow, and grow makes a call too. Its frame saves:", "options": [{"label": "ra and s1", "frame": ["s1", "ra"], "good": true, "why": "The Chomper''s s1 waits at sp+0 and ra at sp+4; the matching loads go just before grow returns."}, {"label": "ra and s0", "frame": ["s0", "ra"], "good": false, "why": "This frame saved s0, which grow never touched, and not s1, which it wrote x into: the Chomper got its s1 back changed (s1 = 10). A function saves the s registers it uses."}, {"label": "only s1", "frame": ["s1"], "good": false, "why": "With ra not saved, jal ra, half took grow''s only way back: its jr ra jumped back into grow, which ran its epilogue again and read past the top of the stack."}]}, {"line": "add s1, x0, a0", "note": "x goes in s1, which half promises to leave alone."}, {"line": "jal ra, half"}, {"line": "add a0, a0, s1", "note": "s1 still holds x after the call: x / 2 + x."}, {"epilogue": true}, {"line": "jr ra"}, {"label": "half"}, {"line": "srai a0, a0, 1", "note": "half shifts x right one bit: x / 2."}, {"line": "jr ra"}], "calls": [{"args": {"a0": 10}, "expect": 15}], "watch": ["a0", "s0", "s1", "ra"], "intro": "The Chomper calls grow(10). s0 and s1 hold the Chomper''s own values (0x5A08 and 0x5A09) to start."}',
 '{"choices": [0]}'),
(3, 'puzzle', 16, 'saved-registers',
 'Step through shakes and keep the Chomper''s registers safe.
shakes keeps n in s0 across its call to sq, and works out the rest in t0.',
 'int shakes(int n) { return (sq(n) - n) / 2; }',
 'jal ra, sq writes ra, and shakes writes s0 and t0. Which of those must shakes put back before it returns?',
 'A caller expects its s registers back as they were, so a function saves each one it uses (and ra, if it calls). t registers are the function''s own to change: no caller counts on them.',
 2,
 '{"kind": "walk", "entry": "shakes", "code": [{"label": "shakes"}, {"moment": "frame", "ask": "shakes keeps n in s0 across its call to sq, then works out the rest in t0. Its frame saves two of ra, s0, and t0:", "options": [{"label": "ra and s0", "frame": ["s0", "ra"], "good": true, "why": "The Chomper''s s0 waits at sp+0 and ra at sp+4. t0 needs no saving: no caller counts on getting t0 back."}, {"label": "ra and t0", "frame": ["t0", "ra"], "good": false, "why": "shakes saved t0, which no caller expects back, and not s0, which it changed: the Chomper got its s0 back changed (s0 = 5). The s registers are the ones a function must save."}, {"label": "s0 and t0", "frame": ["s0", "t0"], "good": false, "why": "t0 took ra''s place, so jal ra, sq took shakes''s only way back: its jr ra jumped back into shakes, which ran its epilogue again and read past the top of the stack."}]}, {"line": "add s0, x0, a0", "note": "n goes in s0, which sq promises to leave alone."}, {"line": "jal ra, sq"}, {"line": "sub t0, a0, s0", "note": "n * n - n, worked out in t0: that counts every handshake twice..."}, {"line": "srai a0, t0, 1", "note": "...so shifting right one bit halves it."}, {"epilogue": true}, {"line": "jr ra"}, {"label": "sq"}, {"line": "mul a0, a0, a0"}, {"line": "jr ra"}], "calls": [{"args": {"a0": 5}, "expect": 10}], "watch": ["a0", "s0", "t0", "ra"], "intro": "The Chomper calls shakes(5): the handshakes among 5 people. Watch s0: it holds the Chomper''s 0x5A08."}',
 '{"choices": [0]}'),
(3, 'puzzle', 17, 'recursion',
 'Step through sumsq(3), floor by floor.
sumsq calls itself down to sumsq(0), and keeps each floor''s n × n in s0 for the way back up.',
 'int sumsq(int n) { return n == 0 ? 0 : sumsq(n - 1) + n * n; }',
 'Each floor above the bottom makes a call and then has to return. What does it need to keep, for after the call and for its own return?',
 'Every floor of a recursion is a call like any other, so each needs its own frame: the ra its own jal will overwrite, and the s register it uses. The inner floors all return to the same line, which hides a lost ra until the top floor tries to get back to its caller.',
 2,
 '{"kind": "walk", "entry": "sumsq", "code": [{"label": "sumsq"}, {"moment": "frame", "ask": "sumsq calls itself, and keeps n × n in s0 for after the call. Each floor''s frame saves:", "options": [{"label": "ra and s0", "frame": ["s0", "ra"], "good": true, "why": "Every floor will keep its own way back and its caller''s s0, safe from the floors below it."}, {"label": "only s0", "frame": ["s0"], "good": false, "why": "No floor saved ra. The inner floors all return to the same line, so they got back anyway, but the top floor jumped there too, with 14 in a0, and sumsq read past the top of the stack."}]}, {"line": "beq a0, x0, done", "note": "sumsq(0) is 0: the bottom floor answers without a call."}, {"line": "mul s0, a0, a0", "note": "Keep n × n in s0 for after the call."}, {"line": "addi a0, a0, -1", "note": "The argument for the next floor: n - 1."}, {"line": "jal ra, sumsq", "note": "sumsq calls itself: one floor down. ra now points back into sumsq."}, {"line": "add a0, a0, s0", "note": "Back up a floor: sumsq(n - 1) is in a0, and this floor''s n × n is in s0 again."}, {"label": "done"}, {"epilogue": true}, {"line": "jr ra"}], "calls": [{"args": {"a0": 3}, "expect": 14}], "watch": ["a0", "s0", "ra", "sp"], "intro": "The Chomper calls sumsq(3). Watch ra: it holds the way back to the Chomper (0x400) to start."}',
 '{"choices": [0]}'),
(3, 'puzzle', 18, 'recursion',
 'Follow halves(6) down four floors and back up.
halves adds n, n / 2, n / 4, ... down to 0, keeping each floor''s n in an s register.',
 'int halves(int n) { return n == 0 ? 0 : n + halves(n / 2); }',
 'Look at which s register halves writes before its call.',
 'Every floor of a recursion needs a frame that saves ra and each s register the function writes. Saving an s register it never touches costs a word and protects nothing.',
 2,
 '{"kind": "walk", "entry": "halves", "code": [{"label": "halves"}, {"moment": "frame", "ask": "halves calls itself, and keeps n in a saved register for after the call. Each floor''s frame saves:", "options": [{"label": "ra and s0", "frame": ["s0", "ra"], "good": false, "why": "halves writes s1, not s0. s1 went 6, 3, 1 on the way down and nothing put it back, so the way back up added 1 + 1 + 1: halves(6) returned 3, not 10, and the Chomper got s1 back as 1."}, {"label": "ra and s1", "frame": ["s1", "ra"], "good": true, "why": "Every floor will keep its own way back and its caller''s s1, the register halves writes."}]}, {"line": "beq a0, x0, done", "note": "halves(0) is 0: the bottom floor."}, {"line": "add s1, x0, a0", "note": "Keep n in s1 for after the call."}, {"line": "srli a0, a0, 1", "note": "The argument for the next floor: n / 2, a shift right by one."}, {"line": "jal ra, halves", "note": "One floor down: halves(n / 2)."}, {"line": "add a0, a0, s1", "note": "Back up a floor: halves(n / 2) + this floor''s n, in s1 again."}, {"label": "done"}, {"epilogue": true}, {"line": "jr ra"}], "calls": [{"args": {"a0": 6}, "expect": 10}], "watch": ["a0", "s0", "s1", "sp"], "intro": "The Chomper calls halves(6). s0 and s1 both hold the Chomper''s own values (0x5A08, 0x5A09) to start."}',
 '{"choices": [1]}'),
(3, 'puzzle', 19, 'base-case',
 'Find where hop should stop.
hop calls itself with n - 2, so on its way down it skips every other number.',
 'int hop(int n) { return n < 2 ? n : n + hop(n - 2); }',
 'hop(5) visits 5, 3, then 1. Which check stops it at 1?',
 'A base case has to catch the recursion at the right floor. When each call steps down by more than one, a check for one exact value can be stepped right over, and a check that fires a floor too late adds a floor that doesn''t belong.',
 2,
 '{"kind": "walk", "entry": "hop", "code": [{"label": "hop"}, {"line": "addi sp, sp, -8", "note": "hop''s frame: two words..."}, {"line": "sw ra, 4(sp)"}, {"line": "sw s0, 0(sp)", "note": "...for ra and the s0 it will borrow."}, {"moment": "lines", "ask": "hop is about to call itself with n - 2. Before that, stop when:", "options": [{"label": "n == 0 (return n)", "lines": ["beq a0, x0, done"], "good": false, "why": "n == 0 never came: hop stepped from 1 straight to -1 (5, 3, 1, -1, -3, ...), and every call took another frame until the tower ran off the bottom of the stack."}, {"label": "n < 2 (return n)", "lines": ["slti t0, a0, 2", "bne t0, x0, done"], "good": true, "why": "hop(1) will skip the call and return 1, and every floor above it will add its n on the way back up."}, {"label": "n < 1 (return n)", "lines": ["slti t0, a0, 1", "bne t0, x0, done"], "good": false, "why": "n < 1 let hop(1) call itself once more: hop(-1) returned -1, which canceled hop(1)''s own 1 on the way back up, so hop(5) returned 8 instead of 9."}]}, {"line": "add s0, x0, a0", "note": "Keep n for after the call."}, {"line": "addi a0, a0, -2", "note": "Two steps down at once: n - 2."}, {"line": "jal ra, hop", "note": "One floor down: hop(n - 2)."}, {"line": "add a0, a0, s0", "note": "Back up: n + hop(n - 2)."}, {"label": "done"}, {"line": "lw s0, 0(sp)"}, {"line": "lw ra, 4(sp)"}, {"line": "addi sp, sp, 8"}, {"line": "jr ra"}], "calls": [{"args": {"a0": 5}, "expect": 9}], "watch": ["a0", "t0", "s0", "sp"], "intro": "The Chomper calls hop(5). This stack is short: 12 words, room for six floors.", "stack_words": 12}',
 '{"choices": [1]}'),
(3, 'puzzle', 20, 'base-case',
 'Give dprod the right bottom floor.
dprod multiplies the digits of n, peeling one off per floor with n % 10 and n / 10.',
 'int dprod(int n) { return n < 10 ? n : n % 10 * dprod(n / 10); }',
 'A single digit is its own product. Which check stops there?',
 'A recursion needs a base case that fits what it computes: an input it can answer without a call. Without one the calls never stop, and a check that stops a floor too late folds the extra floor''s answer into every floor above it.',
 2,
 '{"kind": "walk", "entry": "dprod", "code": [{"label": "dprod"}, {"line": "addi sp, sp, -8", "note": "dprod''s frame: two words..."}, {"line": "sw ra, 4(sp)"}, {"line": "sw s0, 0(sp)", "note": "...for ra and the s0 it will borrow."}, {"moment": "lines", "ask": "dprod is about to call itself with n / 10. Before that, stop when:", "options": [{"label": "never", "lines": [], "good": false, "why": "With nothing to stop it, dprod kept calling itself: n went 234, 23, 2, 0, 0, ... (0 / 10 is still 0), and every call took another frame until the tower ran off the bottom of the stack."}, {"label": "n ≤ 1 (return n)", "lines": ["addi t0, x0, 1", "bge t0, a0, done"], "good": false, "why": "n ≤ 1 let dprod(2) call itself once more, with 2 / 10 = 0. dprod(0) returned 0, so every floor above multiplied by 0, and dprod(234) returned 0 instead of 24."}, {"label": "n < 10 (return n)", "lines": ["slti t0, a0, 10", "bne t0, x0, done"], "good": true, "why": "dprod(2) will skip the call and return 2, and every floor above it will multiply in its last digit on the way back up."}]}, {"line": "addi t0, x0, 10", "note": "10, for n % 10 and n / 10."}, {"line": "rem s0, a0, t0", "note": "Keep the last digit, n % 10, for after the call."}, {"line": "div a0, a0, t0", "note": "The other digits, n / 10, go one floor down."}, {"line": "jal ra, dprod", "note": "One floor down: dprod(n / 10)."}, {"line": "mul a0, a0, s0", "note": "Back up: the other digits'' product × the last digit."}, {"label": "done"}, {"line": "lw s0, 0(sp)"}, {"line": "lw ra, 4(sp)"}, {"line": "addi sp, sp, 8"}, {"line": "jr ra"}], "calls": [{"args": {"a0": 234}, "expect": 24}], "watch": ["a0", "t0", "s0", "sp"], "intro": "The Chomper calls dprod(234) on a short stack: 12 words.", "stack_words": 12}',
 '{"choices": [2]}'),
(3, 'puzzle', 21, 'two-calls',
 'Step through pair(3) and both of its calls to sq.
pair keeps n in s0, and sq(n) in s1 while it makes the second call.',
 'int pair(int n) { return sq(n) + sq(n + 1); }',
 'List every register pair writes that its caller expects back unchanged, and the one its calls overwrite.',
 'A function that keeps two values across its calls uses two s registers, so it saves both, and it saves ra because it makes calls. Leaving out any one of the three breaks the contract in its own way.',
 2,
 '{"kind": "walk", "entry": "pair", "code": [{"label": "pair"}, {"moment": "frame", "ask": "pair keeps n in s0, then sq(n) in s1 during its second call, and each jal changes ra. Its frame saves:", "options": [{"label": "ra, s0, and s1", "frame": ["s1", "s0", "ra"], "good": true, "why": "Three words: the way back, and both of the Chomper''s s registers."}, {"label": "ra and s1", "frame": ["s1", "ra"], "good": false, "why": "pair returned the right 25, but it wrote n into s0 without saving the s0 it was given, so the Chomper got its s0 back changed (s0 = 3)."}, {"label": "s0 and s1", "frame": ["s1", "s0"], "good": false, "why": "With ra not saved, the second jal left ra pointing back into pair. Its jr ra jumped there, not to the Chomper, ran the epilogue again, and read past the top of the stack."}]}, {"line": "add s0, x0, a0", "note": "Keep n in s0."}, {"line": "jal ra, sq", "note": "First call: sq(n)."}, {"line": "add s1, x0, a0", "note": "Keep sq(n) in s1 for after the second call."}, {"line": "addi a0, s0, 1", "note": "The second argument: n + 1."}, {"line": "jal ra, sq", "note": "Second call: sq(n + 1)."}, {"line": "add a0, a0, s1", "note": "sq(n + 1) + sq(n)."}, {"epilogue": true}, {"line": "jr ra"}, {"label": "sq"}, {"line": "mul a0, a0, a0", "note": "sq squares a0..."}, {"line": "jr ra", "note": "...and returns."}], "calls": [{"args": {"a0": 3}, "expect": 25}], "watch": ["a0", "s0", "s1", "ra"], "intro": "The Chomper calls pair(3). pair will call sq twice: sq(3), then sq(4)."}',
 '{"choices": [0]}'),
(3, 'puzzle', 22, 'two-calls',
 'Step through diff(3), which calls cube twice.
diff keeps x in s0, and cube(x) in s1 while it makes the second call.',
 'int diff(int x) { return cube(x) - cube(x - 1); }',
 'Which kind of register does a function have to give back unchanged: t or s?',
 'A function saves the s registers it uses (and ra, if it calls), because its caller expects them back. t registers are scratch: cube may use t0, and saving t0 in diff''s frame protects nothing anyone expects back.',
 2,
 '{"kind": "walk", "entry": "diff", "code": [{"label": "diff"}, {"moment": "frame", "ask": "diff keeps x in s0, and cube(x) in s1 during its second call. cube works in t0. diff''s frame saves:", "options": [{"label": "ra, s0, and t0", "frame": ["t0", "s0", "ra"], "good": false, "why": "diff saved t0, which nobody expects back, and not s1, which it wrote: it returned the right 19, but the Chomper got its s1 back changed (s1 = 27)."}, {"label": "ra, s0, and s1", "frame": ["s1", "s0", "ra"], "good": true, "why": "Three words: the way back, and both s registers diff borrows."}, {"label": "ra and s0", "frame": ["s0", "ra"], "good": false, "why": "diff wrote cube(x) into s1 without saving the s1 it was given, so the Chomper got its s1 back changed (s1 = 27). Saving s0 isn''t enough when you use s1 too."}]}, {"line": "add s0, x0, a0", "note": "Keep x in s0."}, {"line": "jal ra, cube", "note": "First call: cube(x)."}, {"line": "add s1, x0, a0", "note": "Keep cube(x) in s1 across the next call."}, {"line": "addi a0, s0, -1", "note": "The second argument: x - 1."}, {"line": "jal ra, cube", "note": "Second call: cube(x - 1)."}, {"line": "sub a0, s1, a0", "note": "cube(x) - cube(x - 1)."}, {"epilogue": true}, {"line": "jr ra"}, {"label": "cube"}, {"line": "mul t0, a0, a0", "note": "cube works in t0, as any function may..."}, {"line": "mul a0, t0, a0"}, {"line": "jr ra"}], "calls": [{"args": {"a0": 3}, "expect": 19}], "watch": ["a0", "t0", "s0", "s1"], "intro": "The Chomper calls diff(3): cube(3) is 27, cube(2) is 8."}',
 '{"choices": [1]}'),
(3, 'puzzle', 23, 'race',
 'Build sum''s frame and outrun the Chomper.
The Chomper climbs up from the heap while sum(5) adds 5 + 4 + 3 + 2 + 1.',
 'int sum(int n) { return n <= 0 ? 0 : n + sum(n - 1); }',
 'sum needs ra and the s0 it keeps n in. Anything more makes every floor bigger.',
 'Two words, ra and s0, is the tightest frame that works, so the stack stays ahead of the Chomper. A bigger frame still works here, but every extra word is paid on every floor.',
 2,
 '{"kind": "walk", "entry": "sum", "code": [{"label": "sum"}, {"moment": "frame", "ask": "The Chomper eats a stack word every 4 instructions, and sum(5) needs six floors. sum''s frame saves:", "options": [{"label": "ra, s0, and t0", "frame": ["t0", "s0", "ra"], "good": true, "loose": true, "why": "Three words a floor: sum(5) still finishes first, but by a single word."}, {"label": "only ra", "frame": ["ra"], "good": false, "why": "n lived in s0, and nothing saved it: every floor added the bottom floor''s n (1), so sum returned 5 instead of 15, and the Chomper''s s0 came back changed."}, {"label": "ra and s0", "frame": ["s0", "ra"], "good": true, "why": "Two words a floor: sum(5) has room to spare."}]}, {"line": "bge x0, a0, done", "note": "n <= 0 is the bottom floor: it returns 0."}, {"line": "add s0, x0, a0", "note": "Keep n."}, {"line": "addi a0, a0, -1"}, {"line": "jal ra, sum", "note": "One floor down: sum(n - 1)."}, {"line": "add a0, a0, s0", "note": "Back up: n + sum(n - 1)."}, {"label": "done"}, {"epilogue": true}, {"line": "jr ra"}], "calls": [{"args": {"a0": 5}, "expect": 15}], "watch": ["a0", "s0", "ra", "sp"], "intro": "The Chomper calls sum(5) and starts climbing up from the heap.", "stack_words": 29, "chomper": {"start": 4, "every": 4}}',
 '{"choices": [2]}'),
(3, 'puzzle', 24, 'race',
 'Build mult''s frame and outrun the Chomper.
mult(3, 5) adds 3 five times, one floor per addition, while the Chomper climbs.',
 'int mult(int a, int b) { return b == 0 ? 0 : a + mult(a, b - 1); }',
 'mult keeps a in s0 across its call. What else does every floor need to get back up?',
 'ra and s0 make the tightest frame that works, so the stack stays ahead of the Chomper. Saving more still works, but every extra word costs a word on every floor.',
 2,
 '{"kind": "walk", "entry": "mult", "code": [{"label": "mult"}, {"moment": "frame", "ask": "The Chomper eats a stack word every 4 instructions, and mult(3, 5) needs six floors. mult''s frame saves:", "options": [{"label": "ra and s0", "frame": ["s0", "ra"], "good": true, "why": "Two words a floor: mult(3, 5) has room to spare."}, {"label": "ra, s0, s1, and t0", "frame": ["t0", "s1", "s0", "ra"], "good": true, "loose": true, "why": "Four words a floor: mult(3, 5) still finishes first, but by a single word."}, {"label": "only s0", "frame": ["s0"], "good": false, "why": "With ra not saved, every floor returned to the same line in mult. The inner floors got by, but the top floor jumped there too, not to the Chomper, and read past the top of the stack."}]}, {"line": "add s0, x0, a0", "note": "Keep a in s0."}, {"line": "add a0, x0, x0", "note": "The answer if b is 0..."}, {"line": "beq a1, x0, done", "note": "...and b == 0 is the bottom floor."}, {"line": "addi a1, a1, -1"}, {"line": "add a0, x0, s0", "note": "The argument a again."}, {"line": "jal ra, mult", "note": "One floor down: mult(a, b - 1)."}, {"line": "add a0, a0, s0", "note": "Back up: a + mult(a, b - 1)."}, {"label": "done"}, {"epilogue": true}, {"line": "jr ra"}], "calls": [{"args": {"a0": 3, "a1": 5}, "expect": 15}], "watch": ["a0", "s0", "ra", "sp"], "intro": "The Chomper calls mult(3, 5) and starts climbing up from the heap.", "stack_words": 38, "chomper": {"start": 8, "every": 4}}',
 '{"choices": [0]}');

-- Level 3: one version of each gate per run, in order.
UPDATE aa.levels SET draw = '[{"pool": "call", "take": 1}, {"pool": "way-back", "take": 1}, {"pool": "keep-value", "take": 1}, {"pool": "saved-registers", "take": 1}, {"pool": "recursion", "take": 1}, {"pool": "base-case", "take": 1}, {"pool": "two-calls", "take": 1}, {"pool": "race", "take": 1}]' WHERE id = 3;

-- Level 4: the original rooms join their gates' pools.
UPDATE aa.questions SET pool = 'logic' WHERE level_id = 4 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET pool = 'delay' WHERE level_id = 4 AND ordinal = 2 AND is_active;
UPDATE aa.questions SET pool = 'path' WHERE level_id = 4 AND ordinal = 3 AND is_active;
UPDATE aa.questions SET pool = 'flip-flop' WHERE level_id = 4 AND ordinal = 4 AND is_active;
UPDATE aa.questions SET pool = 'clk-to-q' WHERE level_id = 4 AND ordinal = 5 AND is_active;
UPDATE aa.questions SET pool = 'clock' WHERE level_id = 4 AND ordinal = 6 AND is_active;
UPDATE aa.questions SET pool = 'overlap' WHERE level_id = 4 AND ordinal = 7 AND is_active;
UPDATE aa.questions SET pool = 'five-stage' WHERE level_id = 4 AND ordinal = 8 AND is_active;
UPDATE aa.questions SET pool = 'stalls' WHERE level_id = 4 AND ordinal = 9 AND is_active;
UPDATE aa.questions SET pool = 'forwarding' WHERE level_id = 4 AND ordinal = 10 AND is_active;

-- Level 4: the new versions.
INSERT INTO aa.questions (level_id, type, ordinal, pool, prompt, code_snippet, hint, explanation, difficulty, payload, answer) VALUES
(4, 'puzzle', 11, 'logic',
 'Draw D, E, and Y as A, B, and C change.
No delays yet: each gate''s output follows its inputs at once. Click a gold row at the moment its signal changes: it flips from there on. Click an edge again to take it away.',
 NULL,
 'D is 1 while A and B differ. E is the opposite of C. Y is 1 only while D and E are both 1. Look at every moment an input changes, even when two change together.',
 'The XOR gate''s output D is 1 while A and B differ: from 20 ps until B falls at 80 ps. At 60 ps A falls just as B rises, so they still differ and D stays 1. The NOT gate flips C, so E is 1 from 40 to 100 ps. Y is 1 only while both D and E are: from 40 to 80 ps.',
 3,
 '{"kind": "wave", "unit": "ps", "tick": 10, "ticks": 12, "circuit": {"labels": true, "inputs": [{"name": "A", "at": [0, 0]}, {"name": "B", "at": [0, 1]}, {"name": "C", "at": [0, 2]}], "gates": [{"out": "D", "op": "xor", "in": ["A", "B"], "at": [1.2, 0.5]}, {"out": "E", "op": "not", "in": ["C"], "at": [1.2, 2]}, {"out": "Y", "op": "and", "in": ["D", "E"], "at": [2.6, 1.25]}], "outputs": ["Y"]}, "signals": {"A": [[0, 0], [2, 1], [6, 0]], "B": [[0, 0], [6, 1], [8, 0]], "C": [[0, 1], [4, 0], [10, 1]]}, "draw": ["D", "E", "Y"]}',
 '{"waves": {"D": [0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0], "E": [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0], "Y": [0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0]}}'),
(4, 'puzzle', 12, 'logic',
 'Draw D, E, and Y, where B feeds two gates.
No delays yet: each gate''s output follows its inputs at once. Click a gold row at the moment its signal changes: it flips from there on. Click an edge again to take it away.',
 NULL,
 'D is 1 only while A and B are both 0. E is 1 only while B and C are both 1. Y is 1 whenever D or E is 1.',
 'The NOR gate''s output D is 1 only while A and B are both 0: from 20 to 50 ps. The AND gate''s output E is 1 while B and C are both 1: from 50 to 80 ps. B feeds both gates, so when it rises at 50 ps, D falls at the same moment E rises, and Y, which is 1 while either is, stays 1 from 20 to 80 ps.',
 3,
 '{"kind": "wave", "unit": "ps", "tick": 10, "ticks": 11, "circuit": {"labels": true, "inputs": [{"name": "A", "at": [0, 0]}, {"name": "B", "at": [0, 1]}, {"name": "C", "at": [0, 2]}], "gates": [{"out": "D", "op": "nor", "in": ["A", "B"], "at": [1.2, 0.5]}, {"out": "E", "op": "and", "in": ["B", "C"], "at": [1.2, 1.5]}, {"out": "Y", "op": "or", "in": ["D", "E"], "at": [2.6, 1]}], "outputs": ["Y"]}, "signals": {"A": [[0, 1], [2, 0]], "B": [[0, 0], [5, 1]], "C": [[0, 1], [8, 0]]}, "draw": ["D", "E", "Y"]}',
 '{"waves": {"D": [0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0], "E": [0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0], "Y": [0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0]}}'),
(4, 'puzzle', 13, 'delay',
 'Draw D and Y, now that each gate takes time.
A gate''s output changes one propagation delay after its input: 30 ps for AND, 10 ps for NOR. The circuit starts settled.',
 NULL,
 'D changes 30 ps after A does, while B holds the AND open. Y responds 10 ps after C changes, and 10 ps after D changes.',
 'Delays add up along a path. C reaches Y through the NOR gate alone, so when C falls at 20 ps, Y rises at 30 ps. A rises at 50 ps, D rises at 80 ps, and Y falls at 90 ps: 40 ps from A to Y, through both gates.',
 3,
 '{"kind": "wave", "unit": "ps", "tick": 10, "ticks": 12, "circuit": {"labels": true, "inputs": [{"name": "A", "at": [0, 0]}, {"name": "B", "at": [0, 1]}, {"name": "C", "at": [0, 2]}], "gates": [{"out": "D", "op": "and", "in": ["A", "B"], "at": [1, 0.5]}, {"out": "Y", "op": "nor", "in": ["D", "C"], "at": [2.2, 1.25]}], "outputs": ["Y"]}, "delays": {"and": 3, "nor": 1}, "signals": {"A": [[0, 0], [5, 1]], "B": [[0, 1]], "C": [[0, 1], [2, 0]]}, "draw": ["D", "Y"]}',
 '{"waves": {"D": [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1], "Y": [0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0]}}'),
(4, 'puzzle', 14, 'delay',
 'Draw C and Y as each change passes two gates.
A gate''s output changes one propagation delay after its input: 20 ps for XOR, 10 ps for NOT. The circuit starts settled.',
 NULL,
 'C changes 20 ps after A or B does, and is 1 while they differ. Y is the opposite of C, 10 ps later.',
 'Delays add up along a path, and here every change passes both gates: 20 ps through the XOR, then 10 ps through the NOT, 30 ps in all. A rises at 20 ps, so C rises at 40 ps and Y falls at 50 ps. B rises at 70 ps and A and B match again, so C falls at 90 ps and Y rises at 100 ps.',
 3,
 '{"kind": "wave", "unit": "ps", "tick": 10, "ticks": 12, "circuit": {"labels": true, "inputs": [{"name": "A", "at": [0, 0]}, {"name": "B", "at": [0, 1]}], "gates": [{"out": "C", "op": "xor", "in": ["A", "B"], "at": [1, 0.5]}, {"out": "Y", "op": "not", "in": ["C"], "at": [2.2, 0.5]}], "outputs": ["Y"]}, "delays": {"xor": 2, "not": 1}, "signals": {"A": [[0, 0], [2, 1]], "B": [[0, 0], [7, 1]]}, "draw": ["C", "Y"]}',
 '{"waves": {"C": [0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0], "Y": [1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1]}}'),
(4, 'puzzle', 15, 'path',
 'Draw D, E, and Y along a chain of three gates.
NAND takes 20 ps, NOT 10 ps, and NOR 30 ps. A change at A has to pass all three gates before Y sees it.',
 NULL,
 'Follow each change one gate at a time: A to D (20 ps), D to E (10 ps), E to Y (30 ps). C reaches Y through the NOR gate alone.',
 'C only passes the NOR gate, so C falling at 20 ps lifts Y at 50 ps. The path from A to Y is 20 + 10 + 30 = 60 ps: A rising at 50 ps drops D at 70 ps, lifts E at 80 ps, and pulls Y down at 110 ps. The longest path through a circuit is its critical path: it sets how long you must wait for the output.',
 3,
 '{"kind": "wave", "unit": "ps", "tick": 10, "ticks": 14, "circuit": {"labels": true, "inputs": [{"name": "A", "at": [0, 0]}, {"name": "B", "at": [0, 1]}, {"name": "C", "at": [0, 2]}], "gates": [{"out": "D", "op": "nand", "in": ["A", "B"], "at": [1, 0.5]}, {"out": "E", "op": "not", "in": ["D"], "at": [2.2, 0.5]}, {"out": "Y", "op": "nor", "in": ["E", "C"], "at": [3.4, 1.25]}], "outputs": ["Y"]}, "delays": {"nand": 2, "not": 1, "nor": 3}, "signals": {"A": [[0, 0], [5, 1]], "B": [[0, 1]], "C": [[0, 1], [2, 0]]}, "draw": ["D", "E", "Y"]}',
 '{"waves": {"D": [1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0], "E": [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1], "Y": [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0]}}'),
(4, 'puzzle', 16, 'path',
 'Draw D, E, and Y as each change ripples through.
XOR and AND take 20 ps each, and NOT takes 10 ps. A change at A has to pass all three gates before Y sees it.',
 NULL,
 'Follow each change one gate at a time: A to D (20 ps), D to E (20 ps), E to Y (10 ps). C joins at the AND gate, so it skips the XOR.',
 'The path from A to Y is 20 + 20 + 10 = 50 ps: A rises at 20 ps, D at 40 ps, E at 60 ps, and Y falls at 70 ps. C skips the XOR, so C falling at 90 ps drops E at 110 ps and lifts Y at 120 ps, 30 ps later. The longest path, from A or B to Y, is the critical path: it sets how long you must wait for the output.',
 3,
 '{"kind": "wave", "unit": "ps", "tick": 10, "ticks": 14, "circuit": {"labels": true, "inputs": [{"name": "A", "at": [0, 0]}, {"name": "B", "at": [0, 1]}, {"name": "C", "at": [0, 2]}], "gates": [{"out": "D", "op": "xor", "in": ["A", "B"], "at": [1, 0.5]}, {"out": "E", "op": "and", "in": ["D", "C"], "at": [2.2, 1.25]}, {"out": "Y", "op": "not", "in": ["E"], "at": [3.4, 1.25]}], "outputs": ["Y"]}, "delays": {"xor": 2, "and": 2, "not": 1}, "signals": {"A": [[0, 0], [2, 1]], "B": [[0, 0]], "C": [[0, 1], [9, 0]]}, "draw": ["D", "E", "Y"]}',
 '{"waves": {"D": [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], "E": [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0], "Y": [1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1]}}'),
(4, 'puzzle', 17, 'flip-flop',
 'Draw Q for this flip-flop as D pulses between the clock edges.
Q takes the value of D only at a rising edge of the clock (the dashed lines), and holds it until the next one.',
 NULL,
 'Ignore D between edges, however busy it gets. At each rising edge (2, 6, 10 ns, and so on), copy what D is at that moment.',
 'Q rises at 2 ns, falls at 6 ns, rises at 14 ns, falls at 22 ns. D''s pulse from 7 to 9 ns falls between two edges, so Q never sees it; the short pulse from 13.5 to 14.5 ns is there at the 14 ns edge, so Q takes it and holds 1 until the edge at 22 ns. Only what D is at a rising edge matters.',
 3,
 '{"kind": "wave", "unit": "ns", "tick": 0.5, "ticks": 56, "circuit": {"labels": true, "inputs": [{"name": "D", "at": [0, 0]}, {"name": "clk", "at": [0, 1]}], "gates": [{"out": "Q", "op": "dff", "in": ["D"], "at": [1.4, 0.5], "clk": "clk"}], "outputs": ["Q"]}, "clock": {"name": "clk", "period": 8, "rise": 4}, "signals": {"D": [[0, 0], [3, 1], [10, 0], [14, 1], [18, 0], [27, 1], [29, 0], [34, 1], [41, 0], [46, 1], [49, 0]]}, "start": {"Q": 0}, "draw": ["Q"]}',
 '{"waves": {"Q": [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}}'),
(4, 'puzzle', 18, 'flip-flop',
 'Draw Q for this flip-flop, whose clock rises at 1, 5, 9 ns, and so on.
Q takes the value of D only at a rising edge of the clock (the dashed lines), and holds it until the next one.',
 NULL,
 'Look only at the dashed lines. At each one, read D and carry that value across to the next dashed line.',
 'Q rises at 1 ns, falls at 9 ns, rises at 17 ns, falls at 21 ns. Between the edges D dips and pulses (at 2.5, 10.5, and 22.5 ns), but none of that is there at a rising edge, so Q ignores it. A flip-flop turns a busy signal into one steady value per clock cycle.',
 3,
 '{"kind": "wave", "unit": "ns", "tick": 0.5, "ticks": 56, "circuit": {"labels": true, "inputs": [{"name": "D", "at": [0, 0]}, {"name": "clk", "at": [0, 1]}], "gates": [{"out": "Q", "op": "dff", "in": ["D"], "at": [1.4, 0.5], "clk": "clk"}], "outputs": ["Q"]}, "clock": {"name": "clk", "period": 8, "rise": 2}, "signals": {"D": [[0, 1], [5, 0], [7, 1], [13, 0], [21, 1], [23, 0], [30, 1], [37, 0], [45, 1], [47, 0]]}, "start": {"Q": 0}, "draw": ["Q"]}',
 '{"waves": {"Q": [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}}'),
(4, 'puzzle', 19, 'clk-to-q',
 'Draw Q with a clk-to-q delay of 0.5 ns.
Q still takes D at each rising edge, but the new value only shows on Q half a nanosecond later.',
 NULL,
 'Do it in two steps: find the value D has at each rising edge, then draw each change on Q 0.5 ns after its edge.',
 'Q rises at 2.5 ns, falls at 14.5 ns, rises at 18.5 ns, falls at 22.5 ns: each change lands 0.5 ns after the rising edge that caused it. The delay doesn''t change what Q takes, only when it shows. Anything reading Q gets 0.5 ns less of the clock period to work with.',
 3,
 '{"kind": "wave", "unit": "ns", "tick": 0.5, "ticks": 56, "circuit": {"labels": true, "inputs": [{"name": "D", "at": [0, 0]}, {"name": "clk", "at": [0, 1]}], "gates": [{"out": "Q", "op": "dff", "in": ["D"], "at": [1.4, 0.5], "clk": "clk"}], "outputs": ["Q"]}, "clock": {"name": "clk", "period": 8, "rise": 4}, "signals": {"D": [[0, 1], [6, 0], [9, 1], [15, 0], [19, 1], [25, 0], [33, 1], [38, 0], [45, 1], [50, 0]]}, "start": {"Q": 0}, "draw": ["Q"], "delays": {"dff": 1}}',
 '{"waves": {"Q": [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}}'),
(4, 'puzzle', 20, 'clk-to-q',
 'Draw Q with a clk-to-q delay of 1.5 ns.
The clock rises at 1, 5, 9 ns, and so on. Each new value of D shows on Q 1.5 ns after the edge that took it.',
 NULL,
 'Read D at each dashed line first. Q only changes where that value differs from Q''s old one, and each change lands 1.5 ns after its edge.',
 'Q rises at 14.5 ns, falls at 18.5 ns, rises at 22.5 ns, falls at 26.5 ns. D is 0 at the first three edges, so Q stays 0 until the edge at 13 ns takes a 1, which shows at 14.5 ns. A long clk-to-q delay eats into every clock period, which is why it counts in the minimum clock period.',
 3,
 '{"kind": "wave", "unit": "ns", "tick": 0.5, "ticks": 56, "circuit": {"labels": true, "inputs": [{"name": "D", "at": [0, 0]}, {"name": "clk", "at": [0, 1]}], "gates": [{"out": "Q", "op": "dff", "in": ["D"], "at": [1.4, 0.5], "clk": "clk"}], "outputs": ["Q"]}, "clock": {"name": "clk", "period": 8, "rise": 2}, "signals": {"D": [[0, 0], [5, 1], [9, 0], [14, 1], [17, 0], [22, 1], [31, 0], [39, 1], [43, 0]]}, "start": {"Q": 0}, "draw": ["Q"], "delays": {"dff": 3}}',
 '{"waves": {"Q": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0]}}'),
(4, 'puzzle', 21, 'clock',
 'Tune each clock for this multiply-add, Y = A x B + C, as fast as it will go.
Every tick, a value leaves one register and has to reach the next before the clock ticks again. The gold pipeline registers cut the trip between the multiplier and the adder. Set both clocks with − and +, then press Race. Every race is a try.',
 NULL,
 'A trip is one clk-to-q delay plus everything between two registers. Without the gold registers that is the multiplier and the adder; with them, the longer of the two pieces.',
 'Without the gold registers a value crosses the multiplier and the adder in one tick: 20 + 600 + 200 = 820 ps. With them the longest trip is the multiplier alone, 20 + 600 = 620 ps. The stages are unequal, so pipelining gains less here: the clock can only be as fast as the slowest stage allows.',
 3,
 '{"kind": "table", "circuit": {"labels": false, "inputs": [{"name": "A", "at": [0, 0]}, {"name": "B", "at": [0, 1]}, {"name": "C", "at": [0, 2]}], "gates": [{"out": "rA", "op": "reg", "in": ["A"], "at": [1, 0]}, {"out": "rB", "op": "reg", "in": ["B"], "at": [1, 1]}, {"out": "rC", "op": "reg", "in": ["C"], "at": [1, 2]}, {"out": "m", "op": "mul", "in": ["rA", "rB"], "at": [2, 0.5]}, {"out": "pm", "op": "reg", "in": ["m"], "at": [3, 0.5], "gold": true}, {"out": "pc", "op": "reg", "in": ["rC"], "at": [3, 2], "gold": true}, {"out": "s", "op": "add", "in": ["pm", "pc"], "at": [4, 1.25]}, {"out": "Y", "op": "reg", "in": ["s"], "at": [5, 1.25]}], "outputs": ["Y"]}, "facts": ["clk-to-q delay = 20 ps  ·  multiplier = 600 ps  ·  adder = 200 ps"], "clocks": [{"name": "Without the gold registers", "gold": false, "path": [["clk-to-q", 20], ["multiplier", 600], ["adder", 200]], "choices": [600, 800, 820, 1000]}, {"name": "With the gold registers", "gold": true, "path": [["clk-to-q", 20], ["multiplier", 600]], "choices": [220, 600, 620, 820]}]}',
 '{"cells": ["820", "620"]}'),
(4, 'puzzle', 22, 'clock',
 'Tune each clock for this chain of three adders, Y = ((A + B) + C) + D.
The gold pipeline registers sit after the second adder, so the two stages are not the same length. Set both clocks with − and +, then press Race. Every race is a try.',
 NULL,
 'Without the gold registers a value crosses all three adders between registers. With them, find the longer stage: is it the part before the gold registers or after?',
 'Without the gold registers the trip crosses three adders: 20 + 300 + 300 + 300 = 920 ps. With them, stage 1 has two adders (20 + 600 = 620 ps) and stage 2 only one, so the clock must fit the longer one: 620 ps. Cutting a circuit into equal stages gives the fastest clock.',
 3,
 '{"kind": "table", "circuit": {"labels": false, "inputs": [{"name": "A", "at": [0, 0]}, {"name": "B", "at": [0, 1]}, {"name": "C", "at": [0, 2]}, {"name": "D", "at": [0, 3]}], "gates": [{"out": "rA", "op": "reg", "in": ["A"], "at": [1, 0]}, {"out": "rB", "op": "reg", "in": ["B"], "at": [1, 1]}, {"out": "rC", "op": "reg", "in": ["C"], "at": [1, 2]}, {"out": "rD", "op": "reg", "in": ["D"], "at": [1, 3]}, {"out": "s1", "op": "add", "in": ["rA", "rB"], "at": [2, 0.5]}, {"out": "s2", "op": "add", "in": ["s1", "rC"], "at": [3, 1.25]}, {"out": "p1", "op": "reg", "in": ["s2"], "at": [4, 1.25], "gold": true}, {"out": "p2", "op": "reg", "in": ["rD"], "at": [4, 3], "gold": true}, {"out": "s3", "op": "add", "in": ["p1", "p2"], "at": [5, 2.1]}, {"out": "Y", "op": "reg", "in": ["s3"], "at": [6, 2.1]}], "outputs": ["Y"]}, "facts": ["clk-to-q delay = 20 ps  ·  adder delay = 300 ps"], "clocks": [{"name": "Without the gold registers", "gold": false, "path": [["clk-to-q", 20], ["adder", 300], ["adder", 300], ["adder", 300]], "choices": [620, 900, 920, 1200]}, {"name": "With the gold registers", "gold": true, "path": [["clk-to-q", 20], ["adder", 300], ["adder", 300]], "choices": [320, 600, 620, 920]}]}',
 '{"cells": ["920", "620"]}'),
(4, 'puzzle', 23, 'overlap',
 'Run four products through this three-stage multiplier, one right behind the other.
Each product spends one tick in each stage, M1, M2, then M3. A stage holds one product at a time. Click the cycle each product starts in, as early as it can.',
 NULL,
 'Product 2 can start M1 the moment product 1 moves on to M2. After that, every product follows one cycle behind the one before it.',
 'Once the pipeline is full, all three stages work at once, each on a different product, and one product finishes every tick. One product still takes 3 ticks (its latency), but four take 3 + 3 = 6 cycles instead of 4 x 3 = 12.',
 3,
 '{"kind": "table", "circuit": {"labels": false, "inputs": [], "gates": [{"out": "M1", "op": "box", "in": [], "at": [0, 0], "label": "M1\nstage 1"}, {"out": "g0", "op": "reg", "in": ["M1"], "at": [1, 0], "gold": true}, {"out": "M2", "op": "box", "in": ["g0"], "at": [2, 0], "label": "M2\nstage 2"}, {"out": "g1", "op": "reg", "in": ["M2"], "at": [3, 0], "gold": true}, {"out": "M3", "op": "box", "in": ["g1"], "at": [4, 0], "label": "M3\nstage 3"}], "outputs": []}, "chart": {"rows": ["product 1", "product 2", "product 3", "product 4"], "stages": ["M1", "M2", "M3"], "cycles": 8, "starts": [0, 1, 2, 3]}, "facts": ["M1, M2, M3 = the three stages, with pipeline registers between them", "Two products can never be in the same stage in the same cycle."]}',
 '{"cells": ["0", "1", "2", "3"]}'),
(4, 'puzzle', 24, 'overlap',
 'Do three loads of laundry the pipelined way.
Each load spends one hour in the washer, one in the dryer, then one on the folding table. Each holds one load at a time. Click the hour each load goes in the washer, as early as it can.',
 NULL,
 'As soon as load 1 moves to the dryer, the washer is free for load 2.',
 'This is the lectures'' laundry picture of pipelining: the washer, dryer, and table all work at once on different loads. One load still takes 3 hours, but three loads take 5 hours instead of 9, and every extra load adds just 1 hour.',
 3,
 '{"kind": "table", "circuit": {"labels": false, "inputs": [], "gates": [{"out": "Wash", "op": "box", "in": [], "at": [0, 0], "label": "Wash\n1 hour"}, {"out": "g0", "op": "reg", "in": ["Wash"], "at": [1, 0], "gold": true}, {"out": "Dry", "op": "box", "in": ["g0"], "at": [2, 0], "label": "Dry\n1 hour"}, {"out": "g1", "op": "reg", "in": ["Dry"], "at": [3, 0], "gold": true}, {"out": "Fold", "op": "box", "in": ["g1"], "at": [4, 0], "label": "Fold\n1 hour"}], "outputs": []}, "chart": {"rows": ["load 1", "load 2", "load 3"], "stages": ["Wash", "Dry", "Fold"], "cycles": 7, "starts": [0, 1, 2]}, "facts": ["One column of the diagram is one hour.", "The washer, dryer, and table each hold one load at a time."]}',
 '{"cells": ["0", "1", "2"]}'),
(4, 'puzzle', 25, 'five-stage',
 'Send five instructions down a pipeline with slow fetch and memory, then tune both clocks.
Click the cycle where each instruction is fetched (IF). A single-cycle CPU does a whole instruction in one tick; the pipeline does one stage per tick. Every race is a try.',
 NULL,
 'Fetch a new instruction every cycle, starting in cycle 1. The single-cycle clock must fit lw, which uses every stage; the pipelined clock only the slowest stage. Each trip also starts with the 20 ps clk-to-q delay.',
 'Single-cycle, every tick has to fit lw through all five stages: 20 + 950 = 970 ps. Pipelined, a tick covers the slowest stage, IF or MEM: 20 + 250 = 270 ps. Five instructions take 9 pipelined ticks against 5 single-cycle ones, and each pipelined tick is far shorter.',
 3,
 '{"kind": "table", "circuit": {"labels": false, "inputs": [], "gates": [{"out": "IF", "op": "box", "in": [], "at": [0, 0], "label": "IF\n250 ps"}, {"out": "g0", "op": "reg", "in": ["IF"], "at": [1, 0], "gold": true}, {"out": "ID", "op": "box", "in": ["g0"], "at": [2, 0], "label": "ID\n150 ps"}, {"out": "g1", "op": "reg", "in": ["ID"], "at": [3, 0], "gold": true}, {"out": "EX", "op": "box", "in": ["g1"], "at": [4, 0], "label": "EX\n200 ps"}, {"out": "g2", "op": "reg", "in": ["EX"], "at": [5, 0], "gold": true}, {"out": "MEM", "op": "box", "in": ["g2"], "at": [6, 0], "label": "MEM\n250 ps"}, {"out": "g3", "op": "reg", "in": ["MEM"], "at": [7, 0], "gold": true}, {"out": "WB", "op": "box", "in": ["g3"], "at": [8, 0], "label": "WB\n100 ps"}], "outputs": []}, "chart": {"rows": ["lw x5, 0(x10)", "add x6, x7, x8", "sw x9, 4(x10)", "sub x11, x12, x13", "or x14, x15, x16"], "stages": ["IF", "ID", "EX", "MEM", "WB"], "cycles": 10, "starts": [0, 1, 2, 3, 4]}, "facts": ["clk-to-q delay = 20 ps  ·  lw uses every stage"], "clocks": [{"name": "Single-cycle: a whole instruction per tick", "path": [["clk-to-q", 20], ["IF", 250], ["ID", 150], ["EX", 200], ["MEM", 250], ["WB", 100]], "choices": [770, 950, 970, 1200]}, {"name": "Pipelined: one stage per tick", "path": [["clk-to-q", 20], ["slowest stage", 250]], "choices": [170, 250, 270, 970]}]}',
 '{"cells": ["0", "1", "2", "3", "4", "970", "270"]}'),
(4, 'puzzle', 26, 'five-stage',
 'Send five instructions down a pipeline with a slow EX stage, then tune both clocks.
Click the cycle where each instruction is fetched (IF). A single-cycle CPU does a whole instruction in one tick; the pipeline does one stage per tick. Every race is a try.',
 NULL,
 'Fetch a new instruction every cycle, starting in cycle 1. For the clocks, add up every stage for the single-cycle CPU, and take only the slowest stage, EX, for the pipeline; both trips start with 20 ps of clk-to-q.',
 'Single-cycle, every tick has to fit lw through all five stages: 20 + 1000 = 1020 ps. Pipelined, a tick only covers the slowest stage, EX: 20 + 300 = 320 ps. One slow stage sets the pace for the whole pipeline, which is why designers try to balance the stages.',
 3,
 '{"kind": "table", "circuit": {"labels": false, "inputs": [], "gates": [{"out": "IF", "op": "box", "in": [], "at": [0, 0], "label": "IF\n200 ps"}, {"out": "g0", "op": "reg", "in": ["IF"], "at": [1, 0], "gold": true}, {"out": "ID", "op": "box", "in": ["g0"], "at": [2, 0], "label": "ID\n150 ps"}, {"out": "g1", "op": "reg", "in": ["ID"], "at": [3, 0], "gold": true}, {"out": "EX", "op": "box", "in": ["g1"], "at": [4, 0], "label": "EX\n300 ps"}, {"out": "g2", "op": "reg", "in": ["EX"], "at": [5, 0], "gold": true}, {"out": "MEM", "op": "box", "in": ["g2"], "at": [6, 0], "label": "MEM\n200 ps"}, {"out": "g3", "op": "reg", "in": ["MEM"], "at": [7, 0], "gold": true}, {"out": "WB", "op": "box", "in": ["g3"], "at": [8, 0], "label": "WB\n150 ps"}], "outputs": []}, "chart": {"rows": ["add x5, x6, x7", "lw x8, 8(x9)", "or x10, x11, x12", "sw x13, 0(x9)", "and x14, x15, x16"], "stages": ["IF", "ID", "EX", "MEM", "WB"], "cycles": 10, "starts": [0, 1, 2, 3, 4]}, "facts": ["clk-to-q delay = 20 ps  ·  lw uses every stage"], "clocks": [{"name": "Single-cycle: a whole instruction per tick", "path": [["clk-to-q", 20], ["IF", 200], ["ID", 150], ["EX", 300], ["MEM", 200], ["WB", 150]], "choices": [820, 1000, 1020, 1300]}, {"name": "Pipelined: one stage per tick", "path": [["clk-to-q", 20], ["slowest stage", 300]], "choices": [220, 300, 320, 1020]}]}',
 '{"cells": ["0", "1", "2", "3", "4", "1020", "320"]}'),
(4, 'puzzle', 27, 'stalls',
 'Stall this loop body so no line reads a register before it is written.
No forwarding here: a value written in W can be read in D in that same cycle, and no earlier. Press + to hold a line in D one more cycle (the lines behind it wait too). Use as few stalls as you can, then Run it.',
 NULL,
 'Find each line that reads a register written one or two lines above it, and hold that reader in D until its D sits under the writer''s W. Run again after each fix: a stall moves the lines behind it too.',
 'addi writes x10 in W in cycle 5, but lw would decode in cycle 3, so lw waits in D for two cycles. add x12 reads x5 two lines below the load and waits one cycle, reading it in cycle 8 as lw writes it. That stall also lets sub read x11 in cycle 9, when addi x11 writes it. Three stalls stretch the run from 9 cycles to 12.',
 3,
 '{"kind": "table", "chart": {"rows": ["addi x10, x10, 4", "lw x5, 0(x10)", "addi x11, x11, 1", "add x12, x12, x5", "sub x13, x11, x14"], "stages": ["F", "D", "X", "M", "W"], "cycles": 15, "stalls": [0, 2, 0, 1, 0]}, "facts": ["Run plays the program and draws an arrow for each value a line reads:", "green = written in time  ·  red = read too early", "Every stall costs the whole program a cycle."]}',
 '{"cells": ["0", "2", "0", "1", "0"]}'),
(4, 'puzzle', 28, 'stalls',
 'Stall these two interleaved calculations so no line reads a register too early.
No forwarding here: a value written in W can be read in D in that same cycle, and no earlier. Press + to hold a line in D one more cycle (the lines behind it wait too). Use as few stalls as you can, then Run it.',
 NULL,
 'Every value here is read two lines below the line that writes it, so each read is one cycle early, not two. Hold the first red reader in D, then Run again to see which reads that stall fixed.',
 'and would read x5 in D in cycle 4, but add writes it in W in cycle 5, so and waits one cycle. That stall also moves or to cycle 6, when sub writes x6. xor then waits one cycle for x7, written in cycle 8, which carries add x14 to cycle 9, when or writes x8. Two stalls stretch the run from 10 cycles to 12.',
 3,
 '{"kind": "table", "chart": {"rows": ["add x5, x10, x11", "sub x6, x10, x11", "and x7, x5, x12", "or x8, x6, x12", "xor x9, x7, x13", "add x14, x8, x13"], "stages": ["F", "D", "X", "M", "W"], "cycles": 15, "stalls": [0, 0, 1, 0, 1, 0]}, "facts": ["Run plays the program and draws an arrow for each value a line reads:", "green = written in time  ·  red = read too early", "Every stall costs the whole program a cycle."]}',
 '{"cells": ["0", "0", "1", "0", "1", "0"]}'),
(4, 'puzzle', 29, 'forwarding',
 'Stall this pointer chase only where forwarding can''t help.
A result is handed straight into X from a line ahead, so most values arrive without waiting. But a load''s word isn''t out of memory until the end of M. Press + to hold a line in D one more cycle (the lines behind it wait too). Use as few stalls as you can, then Run it.',
 NULL,
 'Only a line that reads what the load right above it loaded has to wait, even when it is a load itself. A loaded word reaches the line two below it in time, and an addi''s result reaches the very next line.',
 'Two lines read what the load right above them loaded, so each waits a cycle in D: lw x6, whose address is x5, and add x9, which needs x8. lw x7 and lw x8 read a load two lines up, so they need no stall, and lw x5 gets x10 from addi at once. Without forwarding, this program would need 9 stalls.',
 3,
 '{"kind": "table", "chart": {"rows": ["addi x10, x10, 16", "lw x5, 0(x10)", "lw x6, 4(x5)", "lw x7, 8(x5)", "lw x8, 0(x6)", "add x9, x7, x8", "sw x9, 12(x5)"], "stages": ["F", "D", "X", "M", "W"], "cycles": 15, "stalls": [0, 0, 1, 0, 0, 1, 0], "forwarding": true}, "facts": ["Run plays the program and draws an arrow for each value a line reads:", "green = forwarded in time  ·  red = not ready yet", "Every stall costs the whole program a cycle."], "solved_note": "The forwarding mux picks where X gets each value, and its setting is now on each arrow: 10 = from EX/MEM (the writer is one cycle ahead, in M, like x9 into sw), 01 = from MEM/WB (the writer is in W, like x6 into lw x8), 00 = the register file (written back in time, like x5 into lw x7). ForwardA is the mux for a line''s first source register, ForwardB for its second."}',
 '{"cells": ["0", "0", "1", "0", "0", "1", "0"]}'),
(4, 'puzzle', 30, 'forwarding',
 'Stall this array copy only where forwarding can''t help.
A result is handed straight into X from a line ahead, so most values arrive without waiting. But a load''s word isn''t out of memory until the end of M. Press + to hold a line in D one more cycle (the lines behind it wait too). Use as few stalls as you can, then Run it.',
 NULL,
 'Only a line that reads what the load right above it loaded has to wait. A store two lines below a load gets the word in time, and an addi''s result reaches the very next line.',
 'add x7 and add x9 each read what the load right above them loaded, so each waits a cycle in D. Both stores read a word loaded two lines up, so they need no stall, and sw x5 takes x11 from addi the cycle after it is made. Without forwarding, this program would need 6 stalls.',
 3,
 '{"kind": "table", "chart": {"rows": ["lw x5, 0(x10)", "addi x11, x10, 64", "sw x5, 0(x11)", "lw x6, 4(x10)", "add x7, x6, x5", "sw x6, 4(x11)", "lw x8, 8(x10)", "add x9, x8, x7"], "stages": ["F", "D", "X", "M", "W"], "cycles": 16, "stalls": [0, 0, 0, 0, 1, 0, 0, 1], "forwarding": true}, "facts": ["Run plays the program and draws an arrow for each value a line reads:", "green = forwarded in time  ·  red = not ready yet", "Every stall costs the whole program a cycle."], "solved_note": "The forwarding mux picks where X gets each value, and its setting is now on each arrow: 10 = from EX/MEM (the writer is one cycle ahead, in M, like x11 into sw x5), 01 = from MEM/WB (the writer is in W, like x5 into that same sw), 00 = the register file (written back in time, like x6 into sw x6). ForwardA is the mux for a line''s first source register, ForwardB for its second."}',
 '{"cells": ["0", "0", "0", "0", "1", "0", "0", "1"]}');

-- Level 4: one version of each gate per run, in order.
UPDATE aa.levels SET draw = '[{"pool": "logic", "take": 1}, {"pool": "delay", "take": 1}, {"pool": "path", "take": 1}, {"pool": "flip-flop", "take": 1}, {"pool": "clk-to-q", "take": 1}, {"pool": "clock", "take": 1}, {"pool": "overlap", "take": 1}, {"pool": "five-stage", "take": 1}, {"pool": "stalls", "take": 1}, {"pool": "forwarding", "take": 1}]' WHERE id = 4;

COMMIT;
