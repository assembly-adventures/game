-- Shorter prompts. Levels 3 and 4 now explain their controls once, on a
-- "How this level works" card (ui/how_to_play.gd) shown the first time a player
-- opens each level and from the ? button. So the rooms' prompts no longer repeat
-- them ("Press Play, or step one line at a time", "Set both clocks with − and +,
-- then press Race", and so on) and keep to the question. Same rooms otherwise.
BEGIN;

UPDATE aa.questions SET prompt = 'Step through plus1 and make its call to triple.
Watch ra: it''s every function''s way back.' WHERE level_id = 3 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET prompt = 'Step through perim and make its call to sum.
Watch ra: it''s how sum gets back to perim.' WHERE level_id = 3 AND ordinal = 9 AND is_active;
UPDATE aa.questions SET prompt = 'Step through halfsq and make its call to square.
Watch ra: it''s every call''s way back.' WHERE level_id = 3 AND ordinal = 10 AND is_active;
UPDATE aa.questions SET prompt = 'Draw D, E, and Y as the inputs change.
No delays yet: each gate''s output follows its inputs at once.' WHERE level_id = 4 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET prompt = 'Tune each clock as fast as it will go without breaking the adder.
Every tick, a value leaves one register and has to reach the next before the clock ticks again. The gold pipeline registers cut that trip in two.' WHERE level_id = 4 AND ordinal = 6 AND is_active;
UPDATE aa.questions SET prompt = 'Send the lecture''s five instructions down the five-stage pipeline, then tune both clocks.
Click the cycle where each instruction is fetched (IF). A single-cycle CPU does a whole instruction in one tick; the pipeline does one stage per tick.' WHERE level_id = 4 AND ordinal = 8 AND is_active;
UPDATE aa.questions SET prompt = 'Stall this program so no line reads a register before it is written.
No forwarding here: a value written in W can be read in D in that same cycle, and no earlier. Use as few stalls as you can.' WHERE level_id = 4 AND ordinal = 9 AND is_active;
UPDATE aa.questions SET prompt = 'Now with forwarding: stall only where no wire can help.
A result is handed straight into X from a line ahead, so most values arrive without waiting. But a load''s word isn''t out of memory until the end of M. Use as few stalls as you can.' WHERE level_id = 4 AND ordinal = 10 AND is_active;
UPDATE aa.questions SET prompt = 'Draw D, E, and Y as A, B, and C change.
No delays yet: each gate''s output follows its inputs at once.' WHERE level_id = 4 AND ordinal = 11 AND is_active;
UPDATE aa.questions SET prompt = 'Draw D, E, and Y, where B feeds two gates.
No delays yet: each gate''s output follows its inputs at once.' WHERE level_id = 4 AND ordinal = 12 AND is_active;
UPDATE aa.questions SET prompt = 'Tune each clock for this multiply-add, Y = A x B + C, as fast as it will go.
Every tick, a value leaves one register and has to reach the next before the clock ticks again. The gold pipeline registers cut the trip between the multiplier and the adder.' WHERE level_id = 4 AND ordinal = 21 AND is_active;
UPDATE aa.questions SET prompt = 'Tune each clock for this chain of three adders, Y = ((A + B) + C) + D.
The gold pipeline registers sit after the second adder, so the two stages are not the same length.' WHERE level_id = 4 AND ordinal = 22 AND is_active;
UPDATE aa.questions SET prompt = 'Send five instructions down a pipeline with slow fetch and memory, then tune both clocks.
Click the cycle where each instruction is fetched (IF). A single-cycle CPU does a whole instruction in one tick; the pipeline does one stage per tick.' WHERE level_id = 4 AND ordinal = 25 AND is_active;
UPDATE aa.questions SET prompt = 'Send five instructions down a pipeline with a slow EX stage, then tune both clocks.
Click the cycle where each instruction is fetched (IF). A single-cycle CPU does a whole instruction in one tick; the pipeline does one stage per tick.' WHERE level_id = 4 AND ordinal = 26 AND is_active;
UPDATE aa.questions SET prompt = 'Stall this loop body so no line reads a register before it is written.
No forwarding here: a value written in W can be read in D in that same cycle, and no earlier. Use as few stalls as you can.' WHERE level_id = 4 AND ordinal = 27 AND is_active;
UPDATE aa.questions SET prompt = 'Stall these two interleaved calculations so no line reads a register too early.
No forwarding here: a value written in W can be read in D in that same cycle, and no earlier. Use as few stalls as you can.' WHERE level_id = 4 AND ordinal = 28 AND is_active;
UPDATE aa.questions SET prompt = 'Stall this pointer chase only where forwarding can''t help.
A result is handed straight into X from a line ahead, so most values arrive without waiting. But a load''s word isn''t out of memory until the end of M. Use as few stalls as you can.' WHERE level_id = 4 AND ordinal = 29 AND is_active;
UPDATE aa.questions SET prompt = 'Stall this array copy only where forwarding can''t help.
A result is handed straight into X from a line ahead, so most values arrive without waiting. But a load''s word isn''t out of memory until the end of M. Use as few stalls as you can.' WHERE level_id = 4 AND ordinal = 30 AND is_active;

COMMIT;
