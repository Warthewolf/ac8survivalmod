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
  aircraft    TEXT,                      -- the player's aircraft code (su57, f22a, ...)
  -- from mod 0.50.0 (null for older runs); the Worker adds these columns to an older database itself
  how         TEXT,                      -- died | restart | left
  tier        TEXT,                      -- the enemy skill tier at the end (Rookie ... Reaper)
  aces        INTEGER,                   -- ace squadron aircraft shot down
  allies      INTEGER,                   -- allies bought (MOONCHILD flights, ships)
  af_down     INTEGER,                   -- times the airfield went down
  captured    INTEGER,                   -- times the airfield was captured
  -- from mod 0.72.x (null / 0 for older runs; the Worker adds these too)
  build       TEXT,                      -- the build hash the run came with (X-SV-Build), null from an older mod
  verified    INTEGER                    -- 1: from a registered build; 0: an older mod's, taken while verification was off
);
CREATE INDEX IF NOT EXISTS runs_round ON runs (difficulty, round DESC, score DESC);
CREATE INDEX IF NOT EXISTS runs_score ON runs (difficulty, score DESC);
CREATE INDEX IF NOT EXISTS runs_pilot ON runs (pilot);
CREATE INDEX IF NOT EXISTS runs_ip ON runs (ip_hash, submitted);
CREATE INDEX IF NOT EXISTS runs_week ON runs (submitted);

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

-- the leaderboard messages the Worker keeps up to date (made by /setup), and verify_builds (/admin)
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- From 2026-10-30 (the admin page, GET /admin). The Worker makes these itself on a database that hasn't them.
-- The builds runs are taken from (registered on /admin from a release's .buildhash.txt)
CREATE TABLE IF NOT EXISTS builds (mod TEXT NOT NULL, build TEXT NOT NULL, note TEXT, added INTEGER NOT NULL,
  PRIMARY KEY (mod, build));
-- Builds runs came from that weren't registered (shown on /admin)
CREATE TABLE IF NOT EXISTS builds_seen (mod TEXT NOT NULL, build TEXT NOT NULL, first INTEGER NOT NULL, last INTEGER NOT NULL,
  n INTEGER NOT NULL, pilot TEXT, PRIMARY KEY (mod, build));
-- Each reset of the boards, and what it took off (so it can be undone)
CREATE TABLE IF NOT EXISTS resets (reset_id TEXT PRIMARY KEY, at INTEGER NOT NULL, runs INTEGER NOT NULL,
  specials INTEGER NOT NULL, restored INTEGER);
CREATE TABLE IF NOT EXISTS runs_archive (reset_id TEXT NOT NULL, reset_at INTEGER NOT NULL, run_id TEXT NOT NULL, pilot TEXT,
  difficulty TEXT, round INTEGER, score INTEGER, air_kills INTEGER, ground_kills INTEGER, earned INTEGER, spent INTEGER,
  time_s INTEGER, ended TEXT, mod_version TEXT, submitted INTEGER, ip_hash TEXT, aircraft TEXT, how TEXT, tier TEXT,
  aces INTEGER, allies INTEGER, af_down INTEGER, captured INTEGER, build TEXT, verified INTEGER);
CREATE INDEX IF NOT EXISTS runs_archive_reset ON runs_archive (reset_id);
CREATE INDEX IF NOT EXISTS runs_archive_run ON runs_archive (run_id);
CREATE TABLE IF NOT EXISTS specials_archive (reset_id TEXT NOT NULL, reset_at INTEGER NOT NULL, run_id TEXT NOT NULL,
  kind TEXT, round INTEGER, seconds INTEGER, won INTEGER, pilot TEXT, difficulty TEXT);
CREATE INDEX IF NOT EXISTS specials_archive_reset ON specials_archive (reset_id);
-- Wrong admin keys (the lock-out)
CREATE TABLE IF NOT EXISTS admin_fails (ip_hash TEXT NOT NULL, at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS admin_fails_ip ON admin_fails (ip_hash, at);
