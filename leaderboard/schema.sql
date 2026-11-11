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
  verified    INTEGER,                   -- 1: from a registered build; 0: an older mod's, taken while verification was off
  -- from the co-op runs (2026-11-03; null on a solo run, which the solo boards keep to; the Worker adds these too)
  players     INTEGER,                   -- the squad's size, 2-24 (the host sends one run for the room)
  squad       TEXT,                      -- its pilots in squad order, host first, comma-separated (shown on the boards)
  crew        TEXT,                      -- the same names in lower case, sorted: one squad on the CO-OP boards, whoever hosted
  -- (2026-11-11; the Worker adds it too) 1: sent by a game that took the co-op run over by host migration and that
  -- nobody joined (a further copy of the same run replaces the stored one: src/index.js supersedes); 0 other co-op runs
  takeover    INTEGER
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
  difficulty TEXT NOT NULL,
  players  INTEGER                       -- a co-op run's squad size (null solo: the solo specials board keeps to those)
);
CREATE INDEX IF NOT EXISTS specials_fast ON specials (kind, won, seconds);

-- Each co-op run's players (from 2026-11-03; the Worker makes this itself on a database that hasn't it)
CREATE TABLE IF NOT EXISTS squads (
  run_id       TEXT NOT NULL,            -- the co-op run (runs.run_id, the host's)
  slot         INTEGER NOT NULL,         -- 0 the host, then the others in the order the game sent them
  pilot        TEXT NOT NULL,
  aircraft     TEXT,                     -- their aircraft code, if sent
  air_kills    INTEGER NOT NULL,         -- their own kills (the squad's add up to the run's)
  ground_kills INTEGER NOT NULL,
  revives      INTEGER NOT NULL,         -- revives they gave
  host         INTEGER NOT NULL,         -- 1 the host
  PRIMARY KEY (run_id, slot)
);
CREATE INDEX IF NOT EXISTS squads_pilot ON squads (pilot COLLATE NOCASE);

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
-- Each reset of the boards, and what it took off (so it can be undone). (2026-11-11) The archive's rows under a reset_id
-- "superseded:<unix time>" are co-op copies a further copy of the same run replaced (no resets row: restore leaves them)
CREATE TABLE IF NOT EXISTS resets (reset_id TEXT PRIMARY KEY, at INTEGER NOT NULL, runs INTEGER NOT NULL,
  specials INTEGER NOT NULL, restored INTEGER);
CREATE TABLE IF NOT EXISTS runs_archive (reset_id TEXT NOT NULL, reset_at INTEGER NOT NULL, run_id TEXT NOT NULL, pilot TEXT,
  difficulty TEXT, round INTEGER, score INTEGER, air_kills INTEGER, ground_kills INTEGER, earned INTEGER, spent INTEGER,
  time_s INTEGER, ended TEXT, mod_version TEXT, submitted INTEGER, ip_hash TEXT, aircraft TEXT, how TEXT, tier TEXT,
  aces INTEGER, allies INTEGER, af_down INTEGER, captured INTEGER, build TEXT, verified INTEGER, players INTEGER, squad TEXT,
  crew TEXT, takeover INTEGER);
CREATE INDEX IF NOT EXISTS runs_archive_reset ON runs_archive (reset_id);
CREATE INDEX IF NOT EXISTS runs_archive_run ON runs_archive (run_id);
CREATE TABLE IF NOT EXISTS specials_archive (reset_id TEXT NOT NULL, reset_at INTEGER NOT NULL, run_id TEXT NOT NULL,
  kind TEXT, round INTEGER, seconds INTEGER, won INTEGER, pilot TEXT, difficulty TEXT, players INTEGER);
CREATE INDEX IF NOT EXISTS specials_archive_reset ON specials_archive (reset_id);
CREATE TABLE IF NOT EXISTS squads_archive (reset_id TEXT NOT NULL, reset_at INTEGER NOT NULL, run_id TEXT NOT NULL,
  slot INTEGER, pilot TEXT, aircraft TEXT, air_kills INTEGER, ground_kills INTEGER, revives INTEGER, host INTEGER);
CREATE INDEX IF NOT EXISTS squads_archive_reset ON squads_archive (reset_id);
-- Wrong admin keys (the lock-out)
CREATE TABLE IF NOT EXISTS admin_fails (ip_hash TEXT NOT NULL, at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS admin_fails_ip ON admin_fails (ip_hash, at);
