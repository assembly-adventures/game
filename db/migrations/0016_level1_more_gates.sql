-- Level 1's bank grows from 22 gates to 28: one more gate in each topic pool, so
-- each pool offers four and a replay is less likely to repeat a gate. The draw
-- rule is unchanged (the tutorial, then one gate per topic).
--
--   23 hex       borrowing across hex digits
--   24 masks     shift, then mask: reading a field out of a word
--   25 flips     two xor masks together flip everything; pressing twice undoes
--   26 signed    flipping every bit of x gives -x - 1
--   27 overflow  unsigned subtraction wraps below 0
--   28 shifts    shifts add up, and each place doubles
--
-- Written by tools/rooms.py from levels/level_1/guest_rooms.json;
-- server/test_puzzles.py checks every gate's par.
BEGIN;

INSERT INTO aa.questions (level_id, type, ordinal, pool, prompt, code_snippet, hint, explanation, difficulty, payload, answer) VALUES
(1, 'puzzle', 23, 'hex',
 'Turn 0x40 into 0x2F.
This gate reads hex. Taking 1 from a right digit of 0 borrows from the left digit, like 40 - 1 in decimal.',
 NULL,
 '0x40 - 1 is 0x3F. Then take 1 off the left digit.',
 '0x40 - 1 borrows from the left digit: 0x3F, just as 40 - 1 is 39 in decimal. Subtracting 16 (0x10) then takes 1 off the left digit, giving 0x2F. Either order works.',
 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 64}, "goal": {"x5": 47}, "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": -1}, {"op": "addi", "rd": 5, "rs1": 5, "imm": -16}], "max_moves": 4, "par": 2}',
 '{"moves": [0, 1]}'),
(1, 'puzzle', 24, 'masks',
 'Turn 0xB7 into 0x0D.
This gate reads hex. To pull a few bits out of the middle of a register, slide them to the right end, then mask off the rest.',
 NULL,
 'Shift right by 2 first, then keep only the right digit with andi 0x0F.',
 '0xB7 is 1011 0111. srli by 2 slides the middle bits to the right end (0010 1101, 0x2D), and andi 0x0F keeps only the last four: 1101, 0x0D. Shift, then mask: this is how a field is read out of a word, such as a register number out of an instruction.',
 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 183}, "goal": {"x5": 13}, "buttons": [{"op": "srli", "rd": 5, "rs1": 5, "imm": 2}, {"op": "andi", "rd": 5, "rs1": 5, "imm": 15}, {"op": "andi", "rd": 5, "rs1": 5, "imm": 240}], "max_moves": 4, "par": 2}',
 '{"moves": [0, 1]}'),
(1, 'puzzle', 25, 'flips',
 'Turn 0x69 into 0x96.
This gate reads hex. xori flips only the bulbs under its mask, and pressing the same key twice flips them back.',
 NULL,
 'Every bulb has to flip: one key flips the right digit, the other the left.',
 '0x69 is 0110 1001 and 0x96 is 1001 0110: every bulb is flipped. xori 0x0F flips the right four and xori 0xF0 the left four, so together they do the work of xori 0xFF. Pressing either key a second time undoes it.',
 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 105}, "goal": {"x5": 150}, "buttons": [{"op": "xori", "rd": 5, "rs1": 5, "imm": 15}, {"op": "xori", "rd": 5, "rs1": 5, "imm": 240}], "max_moves": 4, "par": 2}',
 '{"moves": [0, 1]}'),
(1, 'puzzle', 26, 'signed',
 'Turn 100 into -102.
This gate reads signed. Flipping every bulb of x gives -x - 1.',
 NULL,
 'Flip all turns 100 into -101. Then one more step down.',
 'Flipping every bulb of 100 gives -101, because flipping x always gives -x - 1. That is why negating takes a flip and then +1. Here you go the other way: -101 - 1 is -102.',
 2,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": 100}, "goal": {"x5": -102}, "buttons": [{"op": "xori", "rd": 5, "rs1": 5, "imm": 255}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 1}, {"op": "addi", "rd": 5, "rs1": 5, "imm": -1}], "max_moves": 4, "par": 2}',
 '{"moves": [0, 2]}'),
(1, 'puzzle', 27, 'overflow',
 'Turn 5 into 250 by subtracting.
An 8-bit register can''t go below 0. What happens when you try?',
 NULL,
 '250 is 6 below 256, so subtract 11 in all.',
 '5 - 3 is 2, and 2 - 8 would be -6, which doesn''t exist below 0: the register wraps around to 256 - 6 = 250. Unsigned subtraction wraps past 0 just as addition wraps past 255.',
 2,
 '{"kind": "moves", "width": 8, "display": "unsigned", "initial": {"x5": 5}, "goal": {"x5": 250}, "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": -3}, {"op": "addi", "rd": 5, "rs1": 5, "imm": -8}], "max_moves": 4, "par": 2}',
 '{"moves": [0, 1]}'),
(1, 'puzzle', 28, 'shifts',
 'Turn 3 into 96.
Each place a value shifts left doubles it, and shifts add up: 2 places, then 3 more, is 5 places.',
 NULL,
 '96 is 3 × 32, and 32 is five doublings: shift left 5 places in all.',
 'slli by 2 and then by 3 shifts five places in all, and each place doubles: 3 × 32 = 96. Shifting left by n multiplies by 2 to the nth power.',
 2,
 '{"kind": "moves", "width": 8, "display": "unsigned", "initial": {"x5": 3}, "goal": {"x5": 96}, "buttons": [{"op": "slli", "rd": 5, "rs1": 5, "imm": 2}, {"op": "slli", "rd": 5, "rs1": 5, "imm": 3}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 3}], "max_moves": 4, "par": 2}',
 '{"moves": [0, 1]}');

COMMIT;
