BEGIN;

-- The leaderboard shows a player's nickname, or "Player <player_number>" until they
-- pick one, never their Onyen. Nobody can pick a name of that form, so no two
-- entries share a name. citext keeps nicknames unique regardless of case.
ALTER TABLE aa.players ADD COLUMN nickname citext UNIQUE CHECK (nickname ~ '^[A-Za-z0-9 _-]{3,20}$');
-- Numbers existing players too.
ALTER TABLE aa.players ADD COLUMN player_number integer GENERATED ALWAYS AS IDENTITY UNIQUE;

COMMIT;
