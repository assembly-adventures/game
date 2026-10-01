-- Assembly Adventures — level and badge seed data
--
-- Apply after 0001_init.sql:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/seed/0002_levels_badges.sql
--
-- Sources, since none of this lives in questions.json:
--   names       — button text in control_center.tscn
--   scene_path  — the level_scenes dictionary in control_center.tscn
--   badge slugs — badge node names in control_center.tscn (badge_1 … challenge_badge)
--   image_path  — images/1.svg … images/7.svg
--
-- Idempotent: safe to re-run.

BEGIN;

-- Levels 2, 3, 4 and the challenge are inactive: their scenes are two-node
-- stubs and the question bank has no entries for them. The level select should
-- render them locked rather than starting an empty run.
INSERT INTO aa.levels (id, slug, name, ordinal, scene_path, completion_rule, is_active) VALUES
    (1, 'level_1',         'Basic RISC-V Commands', 1, 'res://levels/level_1/risc_v_level.tscn',      '{"type":"all_correct"}', true),
    (2, 'level_2',         'Opcode',                2, 'res://levels/level_2/opcode.tscn',            '{"type":"all_correct"}', false),
    (3, 'level_3',         'Pipelining',            3, 'res://levels/level_3/pipelining.tscn',        '{"type":"all_correct"}', false),
    (4, 'level_4',         'The Stack',             4, 'res://levels/level_4/the_stack.tscn',         '{"type":"all_correct"}', false),
    (5, 'level_5',         'Code Tracing',          5, 'res://levels/level_5/code_tracing.tscn',      '{"type":"all_correct"}', true),
    (6, 'level_6',         'Code Writing',          6, 'res://levels/level_6/code_writing.tscn',      '{"type":"all_correct"}', true),
    (7, 'level_challenge', 'Challenge',             7, 'res://levels/level_challenge/challenger.tscn', '{"type":"all_correct"}', false)
ON CONFLICT (id) DO UPDATE SET
    slug            = EXCLUDED.slug,
    name            = EXCLUDED.name,
    ordinal         = EXCLUDED.ordinal,
    scene_path      = EXCLUDED.scene_path,
    is_active       = EXCLUDED.is_active;
    -- completion_rule deliberately not overwritten: it is tuned per level in
    -- the DB and should survive a re-seed.

-- Badge 1's name is the only one that exists in the project today (a hardcoded
-- label in levels/level_1/risc_v_level.tscn). The rest are placeholders derived
-- from level names — replace them with real titles when the levels are built.
INSERT INTO aa.badges (id, slug, name, description, image_path, level_id, is_active) VALUES
    (1, 'badge_1',         'Basic Instructions Master', 'Cleared the basic RISC-V commands level.', 'res://images/1.svg', 1, true),
    (2, 'badge_2',         'Opcode Decoder',            'Cleared the opcode level.',               'res://images/2.svg', 2, true),
    (3, 'badge_3',         'Pipeline Engineer',         'Cleared the pipelining level.',           'res://images/3.svg', 3, true),
    (4, 'badge_4',         'Stack Keeper',              'Cleared the stack level.',                'res://images/4.svg', 4, true),
    (5, 'badge_5',         'Code Tracer',               'Cleared the code tracing level.',         'res://images/5.svg', 5, true),
    (6, 'badge_6',         'Code Writer',               'Cleared the code writing level.',         'res://images/6.svg', 6, true),
    (7, 'challenge_badge', 'System Restored',           'Cleared the final challenge.',            'res://images/7.svg', 7, true)
ON CONFLICT (id) DO UPDATE SET
    slug        = EXCLUDED.slug,
    name        = EXCLUDED.name,
    description = EXCLUDED.description,
    image_path  = EXCLUDED.image_path,
    level_id    = EXCLUDED.level_id,
    is_active   = EXCLUDED.is_active;

COMMIT;
