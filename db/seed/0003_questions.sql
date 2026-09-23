-- Assembly Adventures — initial question bank
--
-- GENERATED FILE, one-time bootstrap. Regenerate with:
--     python3 db/seed/import_questions.py
--
-- Apply after 0002_levels_badges.sql:
--     psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/seed/0003_questions.sql
--
-- This carries the questions that predate the database across once. After
-- that the database is the source of truth: author questions there, and
-- retire old ones with is_active = false rather than re-running this file
-- (see Docs/schema.md). The DELETE below refuses to touch any question that
-- already has attempts, so a re-run after launch fails loudly on the unique
-- index instead of destroying history.

BEGIN;

DELETE FROM aa.questions WHERE NOT EXISTS (
    SELECT 1 FROM aa.question_attempts a WHERE a.question_id = aa.questions.id);

INSERT INTO aa.questions
    (level_id, type, ordinal, prompt, code_snippet, explanation, payload)
VALUES
    (1, 'multiple_choice', 1, 'What does this instruction do?', NULL, NULL, '{"correct_option_ids": ["o2"], "multi_select": false, "options": [{"id": "o1", "text": "Adds the contents of x5 and x0"}, {"id": "o2", "text": "Stores the value 12 in x5"}, {"id": "o3", "text": "Stores the value at memory address 12 in x5"}, {"id": "o4", "text": "Adds 12 to the current value of x5"}]}'::jsonb),
    (1, 'multiple_choice', 2, 'What is the final value of x7?', 'addi x5, x0, 9
addi x6, x0, 4
sub  x7, x5, x6', NULL, '{"correct_option_ids": ["o2"], "multi_select": false, "options": [{"id": "o1", "text": "4"}, {"id": "o2", "text": "5"}, {"id": "o3", "text": "9"}, {"id": "o4", "text": "13"}]}'::jsonb),
    (1, 'multiple_choice', 3, 'Suppose x5 contains -2 and x6 contains 4. What value is placed in x7?', 'slt x7, x5, x6', NULL, '{"correct_option_ids": ["o3"], "multi_select": false, "options": [{"id": "o1", "text": "-1"}, {"id": "o2", "text": "0"}, {"id": "o3", "text": "1"}, {"id": "o4", "text": "2"}]}'::jsonb),
    (1, 'multiple_choice', 4, 'Suppose x5 and x6 both contain 7.
bne x5, x6, different
What happens?', NULL, NULL, '{"correct_option_ids": ["o2"], "multi_select": false, "options": [{"id": "o1", "text": "The program branches to different"}, {"id": "o2", "text": "The program continues to the next instruction"}, {"id": "o3", "text": "x5 is changed to 0"}, {"id": "o4", "text": "x6 is changed to 0"}]}'::jsonb),
    (1, 'multiple_choice', 5, 'Suppose x10 contains 1000, and memory address 1008 contains 42.
lw x5, 8(x10)
What is the resulting value of x5?', NULL, NULL, '{"correct_option_ids": ["o2"], "multi_select": false, "options": [{"id": "o1", "text": "8"}, {"id": "o2", "text": "42"}, {"id": "o3", "text": "1000"}, {"id": "o4", "text": "1008"}]}'::jsonb),
    (1, 'multiple_choice', 6, 'What does this instruction do?', 'sw x5, 12(x10)', NULL, '{"correct_option_ids": ["o2"], "multi_select": false, "options": [{"id": "o1", "text": "Stores 12 in x5"}, {"id": "o2", "text": "Stores the value in x5 at address x10 + 12"}, {"id": "o3", "text": "Loads the value at address x10 + 12 into x5"}, {"id": "o4", "text": "Stores the value in x10 at address x5 + 12"}]}'::jsonb),
    (1, 'multiple_choice', 7, 'Register x10 contains the address of the first element of an integer array. Which instruction loads element array[3] into x5?', NULL, NULL, '{"correct_option_ids": ["o4"], "multi_select": false, "options": [{"id": "o1", "text": "lw x5, 3(x10)"}, {"id": "o2", "text": "lw x5, 4(x10)"}, {"id": "o3", "text": "lw x5, 8(x10)"}, {"id": "o4", "text": "lw x5, 12(x10)"}]}'::jsonb),
    (1, 'multiple_choice', 8, 'Which statements are true?', NULL, NULL, '{"correct_option_ids": ["o1", "o2", "o4"], "multi_select": true, "options": [{"id": "o1", "text": "x0 always contains the value 0."}, {"id": "o2", "text": "addi can use a constant as one of its operands."}, {"id": "o3", "text": "lw copies a value from a register into memory."}, {"id": "o4", "text": "sw copies a register value into memory."}, {"id": "o5", "text": "Every arithmetic instruction must access memory."}]}'::jsonb),
    (1, 'drag_and_drop', 9, 'Arrange these tiles to create an instruction that sets x8 to 1 when x5 < x6 and to 0 otherwise:', NULL, NULL, '{"correct_order": ["t1", "t2", "t3", "t4"], "orientation": "horizontal", "tiles": [{"id": "t1", "text": "slt"}, {"id": "t3", "text": "x5"}, {"id": "t4", "text": "x6"}, {"id": "t2", "text": "x8"}]}'::jsonb),
    (1, 'drag_and_drop', 10, 'Arrange the instructions to calculate
x7 = x5 + x6 - 2', NULL, NULL, '{"correct_order": ["t1", "t2"], "orientation": "vertical", "tiles": [{"id": "t2", "text": "addi x7, x7, -2"}, {"id": "t1", "text": "add  x7, x5, x6"}]}'::jsonb),
    (1, 'drag_and_drop', 11, 'Arrange the code blocks so that x5 counts down from 3 to 0.', NULL, NULL, '{"correct_order": ["t1", "t2", "t3", "t4"], "orientation": "vertical", "tiles": [{"id": "t1", "text": "addi x5, x0, 3"}, {"id": "t4", "text": "bne  x5, x0, loop"}, {"id": "t3", "text": "addi x5, x5, -1"}, {"id": "t2", "text": "loop:"}]}'::jsonb),
    (1, 'matching', 12, 'For the instruction
add x7, x5, x6
Drag each register to its role:', NULL, NULL, '{"columns": ["Role", "Register"], "distractors": [], "pairs": [{"id": "p1", "left": "Destination register", "right": "x7"}, {"id": "p2", "left": "First source register", "right": "x5"}, {"id": "p3", "left": "Second source register", "right": "x6"}]}'::jsonb),
    (1, 'matching', 13, 'Match each instruction to its behavior:', NULL, NULL, '{"columns": ["Instruction", "Behavior"], "distractors": [], "pairs": [{"id": "p1", "left": "add x5, x6, x7", "right": "Add two register values"}, {"id": "p2", "left": "addi x5, x6, 7", "right": "Add a constant to a register value"}, {"id": "p3", "left": "lw x5, 4(x6)", "right": "Read a word from memory"}, {"id": "p4", "left": "sw x5, 4(x6)", "right": "Write a word to memory"}, {"id": "p5", "left": "beq x5, x6, label", "right": "Branch when two register values are equal"}]}'::jsonb),
    (5, 'multiple_choice', 1, 'What are the final values of x5 and x6?', 'addi x5, x0, 3
addi x6, x0, 2
add  x6, x6, x5
addi x5, x5, -1', NULL, '{"correct_option_ids": ["o2"], "multi_select": false, "options": [{"id": "o1", "text": "x5 = 2, x6 = 3"}, {"id": "o2", "text": "x5 = 2, x6 = 5"}, {"id": "o3", "text": "x5 = 3, x6 = 5"}, {"id": "o4", "text": "x5 = 4, x6 = 2"}]}'::jsonb),
    (5, 'multiple_choice', 2, 'What is the final value of x6?', 'addi x5, x0, 3
addi x6, x0, 0
loop:
add  x6, x6, x5
addi x5, x5, -1
bne  x5, x0, loop', 'The loop calculates 3 + 2 + 1.', '{"correct_option_ids": ["o4"], "multi_select": false, "options": [{"id": "o1", "text": "0"}, {"id": "o2", "text": "3"}, {"id": "o3", "text": "5"}, {"id": "o4", "text": "6"}]}'::jsonb),
    (6, 'multiple_choice', 1, 'The following instruction is not valid RISC-V syntax:
lw x5, x10, 8
Which replacement is correct?', NULL, NULL, '{"correct_option_ids": ["o1"], "multi_select": false, "options": [{"id": "o1", "text": "lw x5, 8(x10)"}, {"id": "o2", "text": "lw 8, x5(x10)"}, {"id": "o3", "text": "lw x10, x5(8)"}, {"id": "o4", "text": "lw x5, x10(x8)"}]}'::jsonb),
    (6, 'multiple_choice', 2, 'Suppose variable y is stored in x6 and variable x is stored in x5. Which instruction implements:
x = y + 5;', NULL, NULL, '{"correct_option_ids": ["o2"], "multi_select": false, "options": [{"id": "o1", "text": "add x5, x6, 5"}, {"id": "o2", "text": "addi x5, x6, 5"}, {"id": "o3", "text": "addi x6, x5, 5"}, {"id": "o4", "text": "lw x5, 5(x6)"}]}'::jsonb),
    (6, 'multiple_choice', 3, 'Which instruction branches to equal when x5 and x6 contain the same value?', NULL, NULL, '{"correct_option_ids": ["o1"], "multi_select": false, "options": [{"id": "o1", "text": "beq x5, x6, equal"}, {"id": "o2", "text": "bne x5, x6, equal"}, {"id": "o3", "text": "slt x5, x6, equal"}, {"id": "o4", "text": "add x5, x6, equal"}]}'::jsonb);

COMMIT;
