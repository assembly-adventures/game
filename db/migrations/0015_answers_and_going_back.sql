-- Two things players asked for, and the data they need.
--
-- Showing the answer: every question gets a reference answer, one winning
-- response in the form the game submits it ({"moves": [...]}, {"program": [...]},
-- {"blanks": [...]}, {"choices": [...]}). It lives only in aa.questions.answer:
-- it is never copied into a run's snapshot, so the game is sent it only when a
-- player asks, which is recorded as an 'answer' event and caps that gate at one
-- star (server/scoring.py). server/test_puzzles.py and test_call_stack.py check
-- that every reference answer opens its gate.
--
-- Going back to a gate: a player may reopen a gate they already opened. That is
-- recorded in aa.run_setbacks like the Chip Chomper's drag-back, but without a
-- failed attempt behind it, so caused_by_attempt_id becomes optional.
BEGIN;

ALTER TABLE aa.questions ADD COLUMN answer jsonb;

ALTER TABLE aa.question_events DROP CONSTRAINT question_events_kind_check;
ALTER TABLE aa.question_events ADD CONSTRAINT question_events_kind_check
    CHECK (kind IN ('hint', 'walk_choice', 'answer'));
ALTER TABLE aa.question_events DROP CONSTRAINT question_events_check;
ALTER TABLE aa.question_events ADD CONSTRAINT question_events_check
    CHECK ((kind IN ('hint', 'answer') AND moment IS NULL AND choice IS NULL AND is_correct IS NULL)
        OR (kind = 'walk_choice' AND moment IS NOT NULL AND choice IS NOT NULL
            AND moment >= 0 AND choice >= 0 AND is_correct IS NOT NULL));

ALTER TABLE aa.run_setbacks ALTER COLUMN caused_by_attempt_id DROP NOT NULL;

-- Level 1: the keys to press, by index into the gate's buttons.
UPDATE aa.questions SET answer = '{"moves": [0]}' WHERE level_id = 1 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 0, 0]}' WHERE level_id = 1 AND ordinal = 2 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [1, 0]}' WHERE level_id = 1 AND ordinal = 3 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1, 0]}' WHERE level_id = 1 AND ordinal = 4 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [2, 0]}' WHERE level_id = 1 AND ordinal = 5 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 6 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 7 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 8 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 0, 1]}' WHERE level_id = 1 AND ordinal = 9 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [1, 1, 1]}' WHERE level_id = 1 AND ordinal = 10 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 0, 1]}' WHERE level_id = 1 AND ordinal = 11 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1, 2]}' WHERE level_id = 1 AND ordinal = 12 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 13 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 14 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 15 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 16 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 17 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 1]}' WHERE level_id = 1 AND ordinal = 18 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 0]}' WHERE level_id = 1 AND ordinal = 19 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 0]}' WHERE level_id = 1 AND ordinal = 20 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [1, 1]}' WHERE level_id = 1 AND ordinal = 21 AND is_active;
UPDATE aa.questions SET answer = '{"moves": [0, 0]}' WHERE level_id = 1 AND ordinal = 22 AND is_active;

-- Level 2: a maze room's program, or the line for each blank of a code room. Rooms 3, 11 and
-- 15 are replaced in 0017; these are the answers to the rooms as they stand now.
UPDATE aa.questions SET answer = '{"program": ["addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4"]}' WHERE level_id = 2 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["lw a2, 12(a0)", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4"]}' WHERE level_id = 2 AND ordinal = 2 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["loop:", "addi a0, a0, 4", "bne a0, a1, loop"]}' WHERE level_id = 2 AND ordinal = 4 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["addi a0, a0, 16", "addi a0, a0, 16", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4"]}' WHERE level_id = 2 AND ordinal = 5 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["addi a0, a0, 4", "lw t0, 20(a0)", "addi t0, t0, 5", "sw t0, 20(a0)", "addi a0, a0, 16", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, -16"]}' WHERE level_id = 2 AND ordinal = 6 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["lw t0, -12(a0)", "lw t1, 28(a0)", "sw t1, -12(a0)", "sw t0, 28(a0)", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 20", "addi a0, a0, 20"]}' WHERE level_id = 2 AND ordinal = 7 AND is_active;
UPDATE aa.questions SET answer = '{"blanks": ["slli t3, t2, 2", "lw t5, 4(t3)"]}' WHERE level_id = 2 AND ordinal = 8 AND is_active;
UPDATE aa.questions SET answer = '{"blanks": ["beq t0, x0, else", "j done"]}' WHERE level_id = 2 AND ordinal = 9 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["loop:", "addi a0, a0, 4", "lw t1, 0(a0)", "bne t1, x0, loop"]}' WHERE level_id = 2 AND ordinal = 10 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["loop:", "lw t1, 0(a0)", "add t2, t2, t1", "addi a0, a0, 4", "addi t0, t0, 1", "blt t0, t6, loop"]}' WHERE level_id = 2 AND ordinal = 12 AND is_active;
UPDATE aa.questions SET answer = '{"blanks": ["sw t4, 0(t3)", "bge t0, x0, loop"]}' WHERE level_id = 2 AND ordinal = 13 AND is_active;
UPDATE aa.questions SET answer = '{"blanks": ["jal ra, func", "jalr x0, 0(ra)"]}' WHERE level_id = 2 AND ordinal = 14 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["loop:", "lw t0, 0(a0)", "sw t0, -28(a0)", "addi a0, a0, 4", "bne a0, a1, loop"]}' WHERE level_id = 2 AND ordinal = 16 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["sw t2, 12(a0)", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4", "addi a0, a0, 4"]}' WHERE level_id = 2 AND ordinal = 3 AND is_active;
UPDATE aa.questions SET answer = '{"program": ["loop:", "lw t0, 0(a0)", "sw t0, 28(a0)", "addi a0, a0, 4", "blt a0, a1, loop"]}' WHERE level_id = 2 AND ordinal = 11 AND is_active;
UPDATE aa.questions SET answer = '{"blanks": ["addi sp, sp, -8", "sw ra, 4(sp)", "sw a0, 0(t1)"]}' WHERE level_id = 2 AND ordinal = 15 AND is_active;

-- Level 3: the option to pick at each of a walkthrough's moments.
UPDATE aa.questions SET answer = '{"choices": [0]}' WHERE level_id = 3 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET answer = '{"choices": [0]}' WHERE level_id = 3 AND ordinal = 2 AND is_active;
UPDATE aa.questions SET answer = '{"choices": [1]}' WHERE level_id = 3 AND ordinal = 3 AND is_active;
UPDATE aa.questions SET answer = '{"choices": [0]}' WHERE level_id = 3 AND ordinal = 4 AND is_active;
UPDATE aa.questions SET answer = '{"choices": [0]}' WHERE level_id = 3 AND ordinal = 5 AND is_active;
UPDATE aa.questions SET answer = '{"choices": [0]}' WHERE level_id = 3 AND ordinal = 6 AND is_active;
UPDATE aa.questions SET answer = '{"choices": [0]}' WHERE level_id = 3 AND ordinal = 7 AND is_active;
UPDATE aa.questions SET answer = '{"choices": [0]}' WHERE level_id = 3 AND ordinal = 8 AND is_active;

COMMIT;
