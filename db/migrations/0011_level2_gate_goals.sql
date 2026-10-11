-- Every Level 2 prompt now starts with the gate's goal on its own line, followed
-- by the idea it turns on; the game shows the goal large and the rest smaller.
-- Only wording changes, so the gates are edited in place, and snapshots of runs
-- already started keep the old wording.
BEGIN;

UPDATE aa.questions SET prompt = 'Walk the robot to the exit.
a0 holds the robot''s address. An int is 4 bytes, so each step right adds 4.'
    WHERE level_id = 2 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET prompt = 'Load arr[3] into a2, then reach the exit.
Base + offset: lw a2, 8(a0) loads the int 8 bytes past a0.'
    WHERE level_id = 2 AND ordinal = 2 AND is_active;
UPDATE aa.questions SET prompt = 'Store 8 in arr[3] to open its door, then reach the exit.
sw writes a register into memory, and t2 holds 8.'
    WHERE level_id = 2 AND ordinal = 3 AND is_active;
UPDATE aa.questions SET prompt = 'Reach the exit with at most 3 instructions.
It''s too far to walk, so teach the robot one step and let it repeat.'
    WHERE level_id = 2 AND ordinal = 4 AND is_active;
UPDATE aa.questions SET prompt = 'Reach the exit, two rows down.
Rows sit end to end in memory. This room is 4 words wide, so one row down is 16 bytes on.'
    WHERE level_id = 2 AND ordinal = 5 AND is_active;
UPDATE aa.questions SET prompt = 'Open the door, then reach the exit.
The door holds 7 and opens at 12. Memory can''t do math: load it, add 5 in a register, store it back.'
    WHERE level_id = 2 AND ordinal = 6 AND is_active;
UPDATE aa.questions SET prompt = 'Swap the two doors'' words, then reach the exit.
Each door holds the code the other one needs. You have two registers, t0 and t1.'
    WHERE level_id = 2 AND ordinal = 7 AND is_active;
UPDATE aa.questions SET prompt = 'Fill the blanks so t0 = arr[i] + arr[i+1].
It''s tested with i = 1 and i = 3, so it has to work for any i.'
    WHERE level_id = 2 AND ordinal = 8 AND is_active;
UPDATE aa.questions SET prompt = 'Fill the blanks to finish this if/else.
x is a0 and y is a1. It''s tested with x = 3 and x = 7, so both paths have to work.'
    WHERE level_id = 2 AND ordinal = 9 AND is_active;
UPDATE aa.questions SET prompt = 'Reach the exit: the first 0 in this row.
Teach a loop that stops when it loads a 0 (x0 always holds 0).'
    WHERE level_id = 2 AND ordinal = 10 AND is_active;
UPDATE aa.questions SET prompt = 'Copy a[] into the vault below it, then reach the exit.
Teach the robot one int, then Repeat. This room is 7 words wide.'
    WHERE level_id = 2 AND ordinal = 11 AND is_active;
UPDATE aa.questions SET prompt = 'Add values[0] through values[5] into t2, then reach the exit.
The loop from lecture: t0 is i, and t6 holds 6.'
    WHERE level_id = 2 AND ordinal = 12 AND is_active;
UPDATE aa.questions SET prompt = 'Fill the blanks so the loop adds 2 to every int in arr.
i is t0 and counts down from 3. The tests check arr and where i ends up.'
    WHERE level_id = 2 AND ordinal = 13 AND is_active;
UPDATE aa.questions SET prompt = 'Fill the blanks so main finishes with a0 = 10.
main calls func, then adds 1. jal puts PC + 4 in ra and jumps; jalr jumps back to ra.'
    WHERE level_id = 2 AND ordinal = 14 AND is_active;
UPDATE aa.questions SET prompt = 'Fill the blanks so main stores func(6) in result and returns.
main saves ra and a0 on the stack before the call and restores both before returning.'
    WHERE level_id = 2 AND ordinal = 15 AND is_active;
UPDATE aa.questions SET prompt = 'Copy a[] into the vault before the Chip Chomper eats it.
The Chomper eats one int every 4 instructions, so keep the loop short.'
    WHERE level_id = 2 AND ordinal = 16 AND is_active;

COMMIT;
