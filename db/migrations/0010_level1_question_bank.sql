-- Level 1 becomes a bank of 22 gates, drawn ten at a time like Levels 2 and 3:
-- the four tutorial gates, then one gate from each topic pool (hex, masks, flips,
-- signed, overflow, shifts), so runs differ while every run still covers every
-- topic of weeks 1-2. Gates 1-10 keep their ids, and with them their attempts;
-- each gets a pool. Gates 11-22 are new. Every prompt now starts with the
-- gate's goal on its own line, followed by the idea it turns on; the game shows
-- the goal large and the rest smaller. Snapshots of runs already started keep
-- the old wording. server/test_puzzles.py checks every gate's par and the draw.
BEGIN;

UPDATE aa.levels SET draw = '[{"pool": "tutorial"}, {"pool": "hex", "take": 1}, {"pool": "masks", "take": 1}, {"pool": "flips", "take": 1}, {"pool": "signed", "take": 1}, {"pool": "overflow", "take": 1}, {"pool": "shifts", "take": 1}]' WHERE id = 1;

UPDATE aa.questions SET pool = 'tutorial',
    prompt = 'Make t0 match the target.
Each key runs its instruction on register t0. The rightmost bulb is worth 1.'
    WHERE level_id = 1 AND ordinal = 1 AND is_active;
UPDATE aa.questions SET pool = 'tutorial',
    prompt = 'Slide t0''s lit bulb under the target''s.
New instruction: slli shifts every bit one place to the left.'
    WHERE level_id = 1 AND ordinal = 2 AND is_active;
UPDATE aa.questions SET pool = 'tutorial',
    prompt = 'Turn 5 into 11.
Two keys now. Line up the pattern, then fill the gap.'
    WHERE level_id = 1 AND ordinal = 3 AND is_active;
UPDATE aa.questions SET pool = 'tutorial',
    prompt = 'Turn 2 into 13.
Register t1 holds 3, and add t0, t0, t1 adds whatever t1 holds to t0.'
    WHERE level_id = 1 AND ordinal = 4 AND is_active;
UPDATE aa.questions SET pool = 'hex',
    prompt = 'Turn 0x03 into 0x31.
This gate reads hex: each hex digit is 4 bulbs, and slli 4 slides a whole digit left.'
    WHERE level_id = 1 AND ordinal = 5 AND is_active;
UPDATE aa.questions SET pool = 'masks',
    prompt = 'Turn 0xFF into 0x0A.
andi works like a stencil: a bulb stays lit only where the mask also has a 1.'
    WHERE level_id = 1 AND ordinal = 6 AND is_active;
UPDATE aa.questions SET pool = 'flips',
    prompt = 'Turn 0x00 into 0xF0.
ori turns bulbs on, and xori 0xFF flips every bulb.'
    WHERE level_id = 1 AND ordinal = 7 AND is_active;
UPDATE aa.questions SET pool = 'signed',
    prompt = 'Turn 5 into -5.
This gate reads signed: the leftmost bulb is worth -128.'
    WHERE level_id = 1 AND ordinal = 8 AND is_active;
UPDATE aa.questions SET pool = 'overflow',
    prompt = 'Reach -96 using only +64 and +32.
This gate reads signed. Can adding positive numbers make a negative?'
    WHERE level_id = 1 AND ordinal = 9 AND is_active;
UPDATE aa.questions SET pool = 'shifts',
    prompt = 'Shrink -64 down to -8.
Two right shifts: srli fills in a 0, and srai copies the sign bit.'
    WHERE level_id = 1 AND ordinal = 10 AND is_active;

INSERT INTO aa.questions (level_id, type, ordinal, pool, prompt, hint, explanation, difficulty, payload) VALUES
(1, 'puzzle', 11, 'hex',
 'Turn 0x3E into 0x50.
This gate reads hex. +16 adds 1 to the left digit, and a right digit past F carries.',
 '0x50 - 0x3E is 0x12: one 16 and two 1s.',
 '0x3E + 1 is 0x3F, and one more rolls the right digit over: 0x40, just as 9 + 1 carries in decimal. Adding 16 (0x10) then adds 1 to the left digit, giving 0x50. Any order of +1, +1, +16 works.', 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 62}, "goal": {"x5": 80}, "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": 1}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 16}], "max_moves": 4, "par": 3}'),
(1, 'puzzle', 12, 'hex',
 'Build 0x5A from 0x00.
This gate reads hex: each digit is 4 bulbs, so build the left digit, then the right one.',
 'Put the 5 in the right digit first, then slide it left.',
 '+5 makes 0x05, slli 4 slides that digit one place left to 0x50, and +10 (A in hex) fills the right digit: 0x5A. Each hex digit is exactly 4 bits.', 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 0}, "goal": {"x5": 90}, "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": 5}, {"op": "slli", "rd": 5, "rs1": 5, "imm": 4}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 10}], "max_moves": 4, "par": 3}'),
(1, 'puzzle', 13, 'masks',
 'Turn 0x9F into 0x93.
andi keeps a bulb lit only where its mask has a 1, so 0xF0 keeps just the left digit.',
 'Clear the right digit first.',
 'andi t0, t0, 0xF0 keeps the left digit and clears the right one: 0x90. Then +3 makes 0x93. Adding first would carry into the left digit (0x9F + 3 = 0xA2).', 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 159}, "goal": {"x5": 147}, "buttons": [{"op": "andi", "rd": 5, "rs1": 5, "imm": 240}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 3}, {"op": "andi", "rd": 5, "rs1": 5, "imm": 15}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 14, 'masks',
 'Turn 77 into 14.
andi 0x0F keeps only the right hex digit: the remainder after dividing by 16.',
 '77 is 0x4D. What''s left after andi 0x0F?',
 '77 is 0x4D, and andi t0, t0, 0x0F keeps the right digit: 0xD, which is 13 (77 = 4 × 16 + 13). One more +1 makes 14. (+1 first works too: 78 is 0x4E, and its right digit is 14.)', 2,
 '{"kind": "moves", "width": 8, "display": "unsigned", "initial": {"x5": 77}, "goal": {"x5": 14}, "buttons": [{"op": "andi", "rd": 5, "rs1": 5, "imm": 15}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 1}, {"op": "andi", "rd": 5, "rs1": 5, "imm": 240}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 15, 'flips',
 'Turn 0xAA into 0x55.
xori flips only the bulbs where its mask has a 1.',
 'Flip each hex digit on its own.',
 '0xAA is 1010 1010 and 0x55 is 0101 0101: every bulb flips. xori 0xF0 flips the left four (0x5A) and xori 0x0F flips the right four (0x55). ori can only turn bulbs on.', 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 170}, "goal": {"x5": 85}, "buttons": [{"op": "xori", "rd": 5, "rs1": 5, "imm": 240}, {"op": "xori", "rd": 5, "rs1": 5, "imm": 15}, {"op": "ori", "rd": 5, "rs1": 5, "imm": 255}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 16, 'flips',
 'Turn 0x0F into 0x30.
ori only turns bulbs on. xori flips the bulbs under its mask, so it can turn them off.',
 'xori 0x0F turns off the four bulbs that are on.',
 'xori t0, t0, 0x0F flips the right four bulbs, turning them all off (0x00), and ori 0x30 turns on the two you need. Either order works: 0x3F xor 0x0F is 0x30 too.', 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 15}, "goal": {"x5": 48}, "buttons": [{"op": "ori", "rd": 5, "rs1": 5, "imm": 48}, {"op": "xori", "rd": 5, "rs1": 5, "imm": 15}, {"op": "xori", "rd": 5, "rs1": 5, "imm": 255}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 17, 'signed',
 'Turn -12 into 12.
This gate reads signed: the leftmost bulb is worth -128.',
 'Flipping every bulb of -12 gives 11.',
 'In two''s complement, -x is ~x + 1: flipping -12 gives 11, and +1 makes 12. It works in both directions, and -1 then flip works too (~(-13) is 12).', 2,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": -12}, "goal": {"x5": 12}, "buttons": [{"op": "xori", "rd": 5, "rs1": 5, "imm": 255}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 1}, {"op": "addi", "rd": 5, "rs1": 5, "imm": -1}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 18, 'signed',
 'Turn 5 into -120.
This gate reads signed: the leftmost bulb is worth -128, so lighting it subtracts 128.',
 'Light the leftmost bulb, then fix the rest.',
 'ori t0, t0, 0x80 lights the -128 bulb: 5 becomes -128 + 5 = -123. +3 makes -120. Either order works (8 with the sign bulb lit is -120).', 2,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": 5}, "goal": {"x5": -120}, "buttons": [{"op": "ori", "rd": 5, "rs1": 5, "imm": 128}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 3}, {"op": "xori", "rd": 5, "rs1": 5, "imm": 255}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 19, 'overflow',
 'Turn 200 into 14 by adding.
An 8-bit register only counts to 255. What happens past that?',
 '200 + 35 + 35 is 270, and 270 doesn''t fit in 8 bits.',
 '8 bits hold 0 to 255, so a sum past 255 wraps around: 200 + 35 + 35 = 270 = 256 + 14, and the 256 falls off the left end. This is an unsigned overflow (a carry out).', 3,
 '{"kind": "moves", "width": 8, "display": "unsigned", "initial": {"x5": 200}, "goal": {"x5": 14}, "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": 35}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 100}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 20, 'overflow',
 'Turn -100 into 56 by subtracting.
This gate reads signed. Can subtracting from a negative make a positive?',
 'The smallest signed 8-bit number is -128. What happens below it?',
 '8 bits reach only -128, so -100 - 50 = -150 wraps around to -150 + 256 = 106, and -50 more is 56. Subtracting a positive from a negative overflowed into a positive.', 3,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": -100}, "goal": {"x5": 56}, "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": -50}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 50}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 21, 'shifts',
 'Shrink -100 down to -25.
Two right shifts: srli fills in a 0, and srai copies the sign bit.',
 'Halve it twice, keeping the sign.',
 'srai t0, t0, 1 halves a signed number and keeps it negative: -100, -50, -25. srli would put a 0 in the sign bulb and turn it into a big positive (-100 srli 1 is 78).', 3,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": -100}, "goal": {"x5": -25}, "buttons": [{"op": "srli", "rd": 5, "rs1": 5, "imm": 1}, {"op": "srai", "rd": 5, "rs1": 5, "imm": 1}], "max_moves": 3, "par": 2}'),
(1, 'puzzle', 22, 'shifts',
 'Turn 48 into -64.
This gate reads signed. slli doubles t0; what happens when a 1 reaches the leftmost bulb?',
 'Shift left until the top 1 reaches the -128 bulb.',
 '48 is 0011 0000. Two slli 1s make 1100 0000, and with the leftmost bulb worth -128 that''s -128 + 64 = -64. Shifting left can overflow into the sign bit, just as adding can.', 3,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": 48}, "goal": {"x5": -64}, "buttons": [{"op": "slli", "rd": 5, "rs1": 5, "imm": 1}, {"op": "srai", "rd": 5, "rs1": 5, "imm": 1}], "max_moves": 3, "par": 2}');

COMMIT;
