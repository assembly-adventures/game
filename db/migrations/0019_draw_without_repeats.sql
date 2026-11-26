-- Draws without repeats. A level that draws its gates now gives each player the
-- gates they have played least since they last signed in, so a gate doesn't come
-- back until they have played every gate of its pool (server/gameplay.py, draw).
-- Signing in again starts the count over, so the sign-in time is kept with the
-- player. Existing players get their latest sign-in, which last_seen_at holds.
BEGIN;

ALTER TABLE aa.players ADD COLUMN signed_in_at timestamptz;
UPDATE aa.players SET signed_in_at = last_seen_at;
COMMENT ON COLUMN aa.players.signed_in_at IS
    'When the player last signed in; runs that ended before it no longer count against the draw.';

COMMIT;
