-- Level 1 becomes ten puzzle gates on an 8-bit practice register: registers,
-- arithmetic, binary/hex, signed values, overflow, logical operations, and
-- shifts (COMP 311 weeks 1–2). Each gate offers a few fixed instructions as
-- buttons; players press them to make x5 match a target pattern. The response
-- is the sequence of presses, which server/puzzles.py replays to grade, so any
-- valid solution passes. Gate designs are checked by server/test_puzzles.py.
BEGIN;

ALTER TABLE aa.questions DROP CONSTRAINT questions_type_check;
ALTER TABLE aa.questions ADD CONSTRAINT questions_type_check
    CHECK (type IN ('multiple_choice', 'drag_and_drop', 'matching', 'puzzle'));

-- Recreated with a puzzle branch; still written with -> rather than ?& (see 0001).
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
                 payload ->> 'kind' = 'moves'
             AND jsonb_typeof(payload -> 'goal') = 'object'
             AND jsonb_typeof(payload -> 'buttons') = 'array'
             AND jsonb_array_length(payload -> 'buttons') >= 1
        ELSE false
    END
);

-- Retire, never delete: old attempts keep pointing at what students saw.
-- In-progress runs keep their immutable snapshots of the quiz.
UPDATE aa.questions SET is_active = false, retired_at = now()
    WHERE level_id = 1 AND is_active;

INSERT INTO aa.questions (level_id, type, ordinal, prompt, hint, explanation, difficulty, payload) VALUES
(1, 'puzzle', 1,
 'Tap an instruction to run it on register x5. Make x5''s bulbs match the target pattern to open the gate.',
 'Press +1 once.',
 'addi x5, x5, 1 adds an immediate (a constant) to a register. The rightmost bulb is worth 1.', 1,
 '{"kind": "moves", "width": 8, "display": "unsigned", "initial": {"x5": 0}, "goal": {"x5": 1},
   "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": 1}], "max_moves": 2, "par": 1}'),
(1, 'puzzle', 2,
 'New instruction: slli slides every bit one place to the left.',
 'Keep sliding until the light sits under the target.',
 'Each shift left doubles the number: 1 → 2 → 4 → 8. slli is a fast way to multiply by 2.', 1,
 '{"kind": "moves", "width": 8, "display": "unsigned", "initial": {"x5": 1}, "goal": {"x5": 8},
   "buttons": [{"op": "slli", "rd": 5, "rs1": 5, "imm": 1}], "max_moves": 4, "par": 3}'),
(1, 'puzzle', 3,
 'Two buttons now. Line up the pattern, then fill the gap.',
 'Shift first. Which bulb is still dark?',
 'Shifting 0101 left gives 1010 (10), and adding 1 lights the last bulb: 1011 is 11.', 1,
 '{"kind": "moves", "width": 8, "display": "unsigned", "initial": {"x5": 5}, "goal": {"x5": 11},
   "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": 1}, {"op": "slli", "rd": 5, "rs1": 5, "imm": 1}],
   "max_moves": 3, "par": 2}'),
(1, 'puzzle', 4,
 'Register x6 is holding 3. add x5, x5, x6 adds whatever x6 holds to x5.',
 'Try to reach 5 first, then double it.',
 'add reads two registers: 2 + 3 = 5, shifting gives 10, and 10 + 3 = 13.', 2,
 '{"kind": "moves", "width": 8, "display": "unsigned", "initial": {"x5": 2, "x6": 3}, "goal": {"x5": 13},
   "buttons": [{"op": "add", "rd": 5, "rs1": 5, "rs2": 6}, {"op": "slli", "rd": 5, "rs1": 5, "imm": 1}],
   "max_moves": 4, "par": 3}'),
(1, 'puzzle', 5,
 'This gate reads hex. Each hex digit is 4 bulbs, and slli 4 slides a whole digit left.',
 'Move the 3 into the left hex digit first.',
 'Shifting left by 4 moves every bit one hex digit: 0x03 becomes 0x30, and adding 1 gives 0x31.', 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 3}, "goal": {"x5": 49},
   "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": 1}, {"op": "slli", "rd": 5, "rs1": 5, "imm": 1},
               {"op": "slli", "rd": 5, "rs1": 5, "imm": 4}],
   "max_moves": 3, "par": 2}'),
(1, 'puzzle', 6,
 'andi works like a stencil: a bulb stays lit only where the mask also has a 1.',
 'Try using both masks.',
 '0xFF and 0x0F is 0x0F, and 0x0F and 0xAA is 0x0A. With AND, the order doesn''t matter.', 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 255}, "goal": {"x5": 10},
   "buttons": [{"op": "andi", "rd": 5, "rs1": 5, "imm": 15}, {"op": "andi", "rd": 5, "rs1": 5, "imm": 170},
               {"op": "addi", "rd": 5, "rs1": 5, "imm": 1}],
   "max_moves": 3, "par": 2}'),
(1, 'puzzle', 7,
 'New: ori turns bulbs on, and xori 0xFF flips every bulb.',
 'Light the right half first, then flip.',
 '0x00 or 0x0F is 0x0F. Flipping every bit turns 0000 1111 into 1111 0000, which is 0xF0.', 2,
 '{"kind": "moves", "width": 8, "display": "hex", "initial": {"x5": 0}, "goal": {"x5": 240},
   "buttons": [{"op": "ori", "rd": 5, "rs1": 5, "imm": 15}, {"op": "xori", "rd": 5, "rs1": 5, "imm": 255}],
   "max_moves": 3, "par": 2}'),
(1, 'puzzle', 8,
 'Signed gate: now the leftmost bulb is worth -128. Turn 5 into -5.',
 'Flipping 5 gives -6. How do you get from -6 to -5?',
 'To negate in two''s complement, flip every bit and add 1: 5 → -6 → -5.', 2,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": 5}, "goal": {"x5": -5},
   "buttons": [{"op": "xori", "rd": 5, "rs1": 5, "imm": 255}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 1}],
   "max_moves": 3, "par": 2}'),
(1, 'puzzle', 9,
 'Can adding positive numbers make a negative? Reach -96 using only +64 and +32.',
 'The biggest signed 8-bit number is 127. What happens when you go past it?',
 '64 + 64 = 128 doesn''t fit in 8 signed bits, so it overflows to -128. Adding 32 gives -96.', 3,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": 0}, "goal": {"x5": -96},
   "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": 64}, {"op": "addi", "rd": 5, "rs1": 5, "imm": 32}],
   "max_moves": 4, "par": 3}'),
(1, 'puzzle', 10,
 'Two right shifts: srli fills in a 0, srai copies the sign bit. Shrink -64 down to -8.',
 'Watch what each shift does to the leftmost bulb.',
 'srai keeps negatives negative: -64 → -32 → -16 → -8. srli shifts in a 0 and makes the number positive.', 3,
 '{"kind": "moves", "width": 8, "display": "signed", "initial": {"x5": -64}, "goal": {"x5": -8},
   "buttons": [{"op": "srli", "rd": 5, "rs1": 5, "imm": 1}, {"op": "srai", "rd": 5, "rs1": 5, "imm": 1}],
   "max_moves": 4, "par": 3}');

COMMIT;
