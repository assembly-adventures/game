-- Registers go by their ABI names, as the course writes them (t0 is x5, t1 is
-- x6); the game shows the x-name beside each one. Only wording changes, so Level
-- 1's gate text is edited in place. Snapshots of runs already started keep the
-- old wording.
BEGIN;

UPDATE aa.questions
    SET prompt = regexp_replace(regexp_replace(prompt, '\mx5\M', 't0', 'g'), '\mx6\M', 't1', 'g'),
        hint = regexp_replace(regexp_replace(hint, '\mx5\M', 't0', 'g'), '\mx6\M', 't1', 'g'),
        explanation = regexp_replace(regexp_replace(explanation, '\mx5\M', 't0', 'g'), '\mx6\M', 't1', 'g')
    WHERE level_id = 1 AND is_active AND type = 'puzzle';

COMMIT;
