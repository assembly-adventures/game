-- Assembly Adventures — initial schema
--
-- Target: PostgreSQL 14+ (UNC cloud apps hosted instance)
-- Apply:  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0001_init.sql
--
-- Design notes live in Docs/schema.md. Two rules this schema assumes of the API
-- tier, because the game is a Godot web export and the browser is untrusted:
--   1. Correct answers are stripped from any question sent to the client.
--   2. Grading and badge awards happen server-side, never on the client's word.

BEGIN;

-- gen_random_uuid() is built in on PG 13+, but pgcrypto is kept for older servers.
-- citext gives case-insensitive onyen matching without LOWER() on every lookup.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS aa;


-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------

-- One row per authenticated UNC person. No password column: Shibboleth SSO is
-- the only credential, and the API upserts this row from the proxy-injected
-- attributes on each request.
CREATE TABLE aa.players (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    onyen        citext NOT NULL UNIQUE,
    -- 9-digit UNC person ID. FERPA-sensitive: never return it from the API,
    -- never log it, and REVOKE it from any reporting role. See Docs/schema.md.
    pid          text UNIQUE,
    -- Hook for a future instructor view. Courses/enrollments are deliberately
    -- not modelled yet; adding them later touches nothing below.
    role         text NOT NULL DEFAULT 'student'
                 CHECK (role IN ('student', 'instructor', 'admin')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz
);

COMMENT ON COLUMN aa.players.pid IS
    'FERPA-sensitive UNC person ID. Do not expose via API or logs.';


-- ---------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------

-- Replaces the level_scenes dictionary hardcoded in an inline SubResource
-- script inside control_center.tscn.
CREATE TABLE aa.levels (
    id              smallint PRIMARY KEY,
    slug            text NOT NULL UNIQUE,       -- 'level_1' … 'level_challenge'
    name            text NOT NULL,
    ordinal         smallint NOT NULL UNIQUE,   -- display order on the control center
    scene_path      text NOT NULL,              -- 'res://levels/level_1/risc_v_level.tscn'
    -- What it takes to pass. Evaluated server-side when a run finishes, so the
    -- rule can change without a migration or a new game build:
    --   {"type": "all_correct"}
    --   {"type": "score_threshold", "min_percent": 80}
    --   {"type": "survive", "lives": 3}
    completion_rule jsonb NOT NULL DEFAULT '{"type":"all_correct"}'::jsonb,
    -- false for levels whose scenes are still stubs and have no questions,
    -- so the level select can render them locked instead of serving empty runs.
    is_active       boolean NOT NULL DEFAULT true,
    CHECK (completion_rule ->> 'type' IN ('all_correct', 'score_threshold', 'survive'))
);

-- Kept separate from levels so progress is earned / count(active badges) rather
-- than the hardcoded / 7 in player_data.gd, and so a non-level achievement can
-- be added without a migration.
CREATE TABLE aa.badges (
    id          smallint PRIMARY KEY,
    -- Matches the badge node names in control_center.tscn ('badge_1',
    -- 'challenge_badge'), which are already the de-facto progress key in game.
    slug        text NOT NULL UNIQUE,
    name        text NOT NULL,
    description text,
    image_path  text NOT NULL,                  -- 'res://images/1.svg'
    -- NULL means the badge is not awarded by completing a level.
    level_id    smallint UNIQUE REFERENCES aa.levels(id),
    is_active   boolean NOT NULL DEFAULT true
);

CREATE TABLE aa.questions (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    level_id     smallint NOT NULL REFERENCES aa.levels(id),
    -- Note the spelling: the source bank's "drap-and-drop" typo is corrected
    -- at import and not carried forward.
    type         text NOT NULL
                 CHECK (type IN ('multiple_choice', 'drag_and_drop', 'matching')),
    ordinal      smallint NOT NULL,             -- fixed presentation order within the level
    prompt       text NOT NULL,
    -- RISC-V listing split out of the prompt, so the UI can monospace the code
    -- and leave the prose alone. NULL when the question has no code.
    code_snippet text,
    hint         text,
    explanation  text,                          -- shown after the player answers
    points       integer NOT NULL DEFAULT 1 CHECK (points >= 0),
    difficulty   smallint CHECK (difficulty BETWEEN 1 AND 5),
    -- Type-specific shape. Every element carries a stable id so grading and
    -- analytics key off ids rather than option text. Shapes in Docs/schema.md.
    payload      jsonb NOT NULL,
    -- Questions are retired, never hard-edited: a substantive change inserts a
    -- new row so old attempts still point at exactly what the student saw.
    is_active    boolean NOT NULL DEFAULT true,
    retired_at   timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CHECK (is_active OR retired_at IS NOT NULL)
);

-- Written with -> rather than the ?& operator on purpose: a bare ? in DDL is
-- treated as a bind placeholder by several drivers (JDBC, some Python/Node
-- clients), which makes the constraint painful to re-emit from an ORM.
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
        ELSE false
    END
);

-- Ordinals only need to be unique among the questions actually in play, so a
-- retired question does not block its replacement from reusing the slot.
CREATE UNIQUE INDEX questions_level_ordinal_active
    ON aa.questions (level_id, ordinal) WHERE is_active;

CREATE OR REPLACE FUNCTION aa.touch_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER questions_touch_updated_at
    BEFORE UPDATE ON aa.questions
    FOR EACH ROW EXECUTE FUNCTION aa.touch_updated_at();


-- ---------------------------------------------------------------------------
-- Gameplay
-- ---------------------------------------------------------------------------

-- One row per attempt at a level. Groups the answers below so you can say
-- "they failed level 1 twice before passing".
CREATE TABLE aa.level_runs (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id         uuid NOT NULL REFERENCES aa.players(id) ON DELETE CASCADE,
    level_id          smallint NOT NULL REFERENCES aa.levels(id),
    started_at        timestamptz NOT NULL DEFAULT now(),
    ended_at          timestamptz,
    outcome           text NOT NULL DEFAULT 'in_progress'
                      CHECK (outcome IN ('in_progress', 'completed', 'failed', 'abandoned')),
    passed            boolean NOT NULL DEFAULT false,
    score             integer NOT NULL DEFAULT 0,
    lives_remaining   smallint,
    hints_used        smallint NOT NULL DEFAULT 0,
    -- Summaries written when the run finishes. Denormalized so the level-select
    -- screen is one cheap read instead of an aggregate over the attempt log.
    questions_total   smallint NOT NULL DEFAULT 0,
    questions_correct smallint NOT NULL DEFAULT 0,
    CHECK (ended_at IS NULL OR ended_at >= started_at),
    CHECK (questions_correct <= questions_total),
    -- A run cannot be marked passed while it is still going.
    CHECK (NOT passed OR outcome <> 'in_progress')
);

-- The full attempt log: one row per answer submitted, including retries.
CREATE TABLE aa.question_attempts (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id         uuid NOT NULL REFERENCES aa.level_runs(id) ON DELETE CASCADE,
    -- Redundant with run_id -> level_runs.player_id, kept so per-student
    -- analytics skips a join. The API sets it from the run, never from input.
    player_id      uuid NOT NULL REFERENCES aa.players(id) ON DELETE CASCADE,
    question_id    uuid NOT NULL REFERENCES aa.questions(id),
    attempt_no     smallint NOT NULL DEFAULT 1 CHECK (attempt_no >= 1),
    -- What the player submitted, in the payload's id vocabulary:
    --   {"selected_option_ids": ["o3"]}        multiple_choice
    --   {"order": ["t2","t1","t3"]}            drag_and_drop
    --   {"pairs": {"p1":"x5", "p2":"x7"}}      matching
    response       jsonb NOT NULL,
    is_correct     boolean NOT NULL,
    -- Measured client-side, so advisory only: a browser tab can be backgrounded.
    -- The API sanity-caps this before insert.
    elapsed_ms     integer CHECK (elapsed_ms >= 0),
    hints_used     smallint NOT NULL DEFAULT 0,
    points_awarded integer NOT NULL DEFAULT 0,
    answered_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_id, question_id, attempt_no)
);

-- The composite primary key makes re-awarding a no-op, which is the DB-level
-- version of the `if not earned_badges.has(...)` guard in player_data.gd.
CREATE TABLE aa.player_badges (
    player_id      uuid NOT NULL REFERENCES aa.players(id) ON DELETE CASCADE,
    badge_id       smallint NOT NULL REFERENCES aa.badges(id),
    awarded_at     timestamptz NOT NULL DEFAULT now(),
    awarded_run_id uuid REFERENCES aa.level_runs(id),
    PRIMARY KEY (player_id, badge_id)
);


-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX level_runs_player_level_idx
    ON aa.level_runs (player_id, level_id, started_at DESC);
CREATE INDEX question_attempts_question_idx
    ON aa.question_attempts (question_id);
CREATE INDEX question_attempts_player_idx
    ON aa.question_attempts (player_id, answered_at DESC);
CREATE INDEX question_attempts_run_idx
    ON aa.question_attempts (run_id);


-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

-- Replaces get_progress_ratio()'s hardcoded / 7 denominator.
CREATE VIEW aa.player_progress AS
SELECT p.id AS player_id,
       count(pb.badge_id) AS badges_earned,
       (SELECT count(*) FROM aa.badges WHERE is_active) AS badges_total,
       count(pb.badge_id)::float8
           / NULLIF((SELECT count(*) FROM aa.badges WHERE is_active), 0)
           AS progress_ratio
FROM aa.players p
LEFT JOIN aa.player_badges pb ON pb.player_id = p.id
GROUP BY p.id;

-- "Which questions do students actually struggle with?" — the payoff for
-- keeping a full attempt log, without needing instructor tables yet.
CREATE VIEW aa.question_stats AS
SELECT q.id,
       q.level_id,
       q.type,
       q.ordinal,
       q.prompt,
       count(a.id) AS total_attempts,
       count(DISTINCT a.player_id) AS distinct_players,
       avg((a.is_correct)::int) FILTER (WHERE a.attempt_no = 1)
           AS first_try_correct_rate,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY a.elapsed_ms)
           AS median_elapsed_ms,
       coalesce(sum(a.hints_used), 0) AS hints_used
FROM aa.questions q
LEFT JOIN aa.question_attempts a ON a.question_id = q.id
GROUP BY q.id;

COMMIT;
