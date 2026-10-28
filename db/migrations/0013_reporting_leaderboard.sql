BEGIN;

ALTER TABLE aa.players ADD COLUMN leaderboard_visible boolean NOT NULL DEFAULT true;

-- Existing runs lack hint and walkthrough-decision history. Preserve their progress,
-- but only new runs may enter the weekly rankings.
ALTER TABLE aa.level_runs ADD COLUMN scoring_version smallint NOT NULL DEFAULT 0 CHECK (scoring_version IN (0, 1));
ALTER TABLE aa.level_runs ADD COLUMN stars_total integer CHECK (stars_total >= 0);
ALTER TABLE aa.level_runs ADD COLUMN mistakes_total integer CHECK (mistakes_total >= 0);
CREATE INDEX level_runs_weekly_idx ON aa.level_runs(level_id, ended_at)
    WHERE passed AND scoring_version = 1;

CREATE TABLE aa.question_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES aa.level_runs(id) ON DELETE CASCADE,
    question_id uuid NOT NULL REFERENCES aa.questions(id),
    player_id uuid NOT NULL REFERENCES aa.players(id) ON DELETE CASCADE,
    request_id uuid NOT NULL,
    kind text NOT NULL CHECK (kind IN ('hint', 'walk_choice')),
    moment integer,
    choice integer,
    is_correct boolean,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    FOREIGN KEY (run_id, question_id) REFERENCES aa.run_questions(run_id, question_id),
    UNIQUE (run_id, request_id),
    CHECK ((kind = 'hint' AND moment IS NULL AND choice IS NULL AND is_correct IS NULL)
        OR (kind = 'walk_choice' AND moment IS NOT NULL AND choice IS NOT NULL
            AND moment >= 0 AND choice >= 0 AND is_correct IS NOT NULL))
);
CREATE INDEX question_events_question_idx ON aa.question_events(question_id, created_at);
CREATE INDEX question_events_player_idx ON aa.question_events(player_id, created_at);

COMMIT;
