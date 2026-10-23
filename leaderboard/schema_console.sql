CREATE TABLE IF NOT EXISTS runs ( run_id TEXT PRIMARY KEY, pilot TEXT NOT NULL, difficulty TEXT NOT NULL, round INTEGER NOT NULL, score INTEGER NOT NULL, air_kills INTEGER NOT NULL, ground_kills INTEGER NOT NULL, earned INTEGER NOT NULL, spent INTEGER NOT NULL, time_s INTEGER NOT NULL, ended TEXT NOT NULL, mod_version TEXT NOT NULL, submitted INTEGER NOT NULL, ip_hash TEXT NOT NULL );
CREATE INDEX IF NOT EXISTS runs_round ON runs (difficulty, round DESC, score DESC);
CREATE INDEX IF NOT EXISTS runs_score ON runs (difficulty, score DESC);
CREATE INDEX IF NOT EXISTS runs_pilot ON runs (pilot);
CREATE INDEX IF NOT EXISTS runs_ip ON runs (ip_hash, submitted);
CREATE TABLE IF NOT EXISTS specials ( run_id TEXT NOT NULL, kind TEXT NOT NULL, round INTEGER NOT NULL, seconds INTEGER NOT NULL, won INTEGER NOT NULL, pilot TEXT NOT NULL, difficulty TEXT NOT NULL );
CREATE INDEX IF NOT EXISTS specials_fast ON specials (kind, won, seconds);
CREATE TABLE IF NOT EXISTS settings ( key TEXT PRIMARY KEY, value TEXT NOT NULL );
