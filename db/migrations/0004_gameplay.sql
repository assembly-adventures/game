BEGIN;

-- Immutable per-run content: edits to the question bank cannot change an attempt.
CREATE TABLE aa.run_questions (
    run_id uuid NOT NULL REFERENCES aa.level_runs(id) ON DELETE CASCADE,
    question_id uuid NOT NULL REFERENCES aa.questions(id),
    ordinal smallint NOT NULL,
    public_question jsonb NOT NULL,
    solution jsonb NOT NULL,
    explanation text,
    points integer NOT NULL CHECK (points >= 0),
    PRIMARY KEY (run_id, question_id),
    UNIQUE (run_id, ordinal)
);
ALTER TABLE aa.question_attempts ADD COLUMN request_id uuid;
CREATE UNIQUE INDEX question_attempts_request_id
    ON aa.question_attempts(run_id, request_id) WHERE request_id IS NOT NULL;
CREATE UNIQUE INDEX one_active_run_per_level
    ON aa.level_runs(player_id, level_id) WHERE outcome = 'in_progress';

-- This release implements level 1; other scenes are still placeholders.
UPDATE aa.levels SET is_active = (id = 1);
UPDATE aa.badges SET is_active = (level_id = 1);
UPDATE aa.levels SET completion_rule = '{"type":"all_correct"}' WHERE id = 1;
-- Restore the instruction omitted from the original reference bank.
UPDATE aa.questions SET code_snippet = 'addi x5, x0, 12'
    WHERE level_id = 1 AND ordinal = 1 AND code_snippet IS NULL AND is_active;

ALTER TABLE aa.players ADD CONSTRAINT valid_pid
    CHECK (pid IS NULL OR pid ~ '^[0-9]{9}$');

CREATE OR REPLACE VIEW aa.player_progress AS
SELECT p.id AS player_id,
       count(b.id) AS badges_earned,
       (SELECT count(*) FROM aa.badges WHERE is_active) AS badges_total,
       count(b.id)::float8
           / NULLIF((SELECT count(*) FROM aa.badges WHERE is_active), 0) AS progress_ratio
FROM aa.players p
LEFT JOIN aa.player_badges pb ON pb.player_id = p.id
LEFT JOIN aa.badges b ON b.id = pb.badge_id AND b.is_active
GROUP BY p.id;

COMMIT;
