-- Three failed tries on a puzzle gate let the Chip Chomper drag the player back:
-- the gate before it reopens and must be solved again (a first gate restarts).
-- Solved state and strikes are replayed from attempts and setbacks in time
-- order (server/gameplay.py), so both use clock_timestamp(), which follows the
-- order requests are processed under the player lock, unlike now().
BEGIN;

CREATE TABLE aa.run_setbacks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id uuid NOT NULL REFERENCES aa.level_runs(id) ON DELETE CASCADE,
    -- The gate that closes again.
    question_id uuid NOT NULL REFERENCES aa.questions(id),
    -- The failed attempt that was the third strike; a retried request finds its setback here.
    caused_by_attempt_id uuid NOT NULL UNIQUE REFERENCES aa.question_attempts(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX run_setbacks_run_idx ON aa.run_setbacks(run_id);

ALTER TABLE aa.question_attempts ALTER COLUMN answered_at SET DEFAULT clock_timestamp();

COMMIT;
