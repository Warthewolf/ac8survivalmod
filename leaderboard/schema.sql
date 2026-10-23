-- Survival Mode leaderboard (Cloudflare D1). Paste into the D1 console once (README.md, step 3).

CREATE TABLE IF NOT EXISTS runs (
  run_id      TEXT PRIMARY KEY,          -- random id the game makes per run (duplicates are refused)
  pilot       TEXT NOT NULL,             -- the pilot name from survival.ini
  difficulty  TEXT NOT NULL,             -- casual | standard | ace
  round       INTEGER NOT NULL,          -- the round reached
  score       INTEGER NOT NULL,          -- worked out here, not taken from the game (score() in src/index.js)
  air_kills   INTEGER NOT NULL,
  ground_kills INTEGER NOT NULL,
  earned      INTEGER NOT NULL,          -- zollars earned / spent
  spent       INTEGER NOT NULL,
  time_s      INTEGER NOT NULL,          -- run length, seconds
  ended       TEXT NOT NULL,             -- died | quit
  mod_version TEXT NOT NULL,
  submitted   INTEGER NOT NULL,          -- unix seconds
  ip_hash     TEXT NOT NULL,             -- a hash of the sender's IP, for the rate limit only
  aircraft    TEXT                       -- the player's aircraft code (su57, f22a, ...); older databases get it added
);
CREATE INDEX IF NOT EXISTS runs_round ON runs (difficulty, round DESC, score DESC);
CREATE INDEX IF NOT EXISTS runs_score ON runs (difficulty, score DESC);
CREATE INDEX IF NOT EXISTS runs_pilot ON runs (pilot);
CREATE INDEX IF NOT EXISTS runs_ip ON runs (ip_hash, submitted);

CREATE TABLE IF NOT EXISTS specials (
  run_id   TEXT NOT NULL,
  kind     TEXT NOT NULL,                -- shuttle | anomaly | amphibious | ladon | alicorn
  round    INTEGER NOT NULL,
  seconds  INTEGER NOT NULL,             -- from its start to beaten
  won      INTEGER NOT NULL,             -- 1 beaten, 0 lost
  pilot    TEXT NOT NULL,
  difficulty TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS specials_fast ON specials (kind, won, seconds);

-- the leaderboard messages the Worker keeps up to date (made by /setup)
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
