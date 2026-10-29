// AC8 Survival Mode leaderboard: a Cloudflare Worker (README.md has the setup).
//
//   POST /submit        a finished run from the game (Survival's native runtime), signed with SUBMIT_KEY; from mod
//                       0.72.x with the build's hash in X-SV-Build (signed with the run): a run counts only from a build
//                       registered on /admin
//   POST /interactions  Discord's slash commands (/leaderboard, /pilot), signed by Discord
//   GET  /setup?key=..  after deploying: registers the slash commands and makes the leaderboard messages (two pinned:
//                       rounds / scores / specials, and records / aircraft / this week)
//   GET  /admin         the admin page (the user only: ADMIN_KEY): reset the boards (archived, so it can be undone),
//                       restore the last reset, the builds runs are accepted from, build verification on / off;
//                       its actions are POST /admin/<action> with the key in the JSON body, never in the address
//
// Bindings (wrangler.toml / dashboard): DB (D1), and as variables / secrets DISCORD_TOKEN, DISCORD_PUBLIC_KEY,
// DISCORD_APP_ID, RUNS_CHANNEL_ID, BOARD_CHANNEL_ID, SUBMIT_KEY, ADMIN_KEY.
// Nothing here ever talks to Bandai Namco's services: only Discord's API and this Worker's own database.
// The database's newer tables and columns are made here the first time they're needed (ensureSchema): no SQL to run.

const DIFFICULTIES = ["casual", "standard", "ace"];
const DIFF_NAME = { casual: "Casual", standard: "Standard", ace: "Ace" };
const DIFF_X = { casual: 0.75, standard: 1.0, ace: 1.5 };        // score multiplier
const SPECIALS = { shuttle: "Comona Defense", anomaly: "The Anomaly", amphibious: "Amphibious Assault",
                   ladon: "The Ladons", alicorn: "The Alicorn", glitch: "AB.L..IN" };
// The player's aircraft (its blueprint's code, e.g. su57 from BP_PlayerPlane_PP0021_su57) by its in-game name
const AIRCRAFT = { a10c: "A-10C Thunderbolt II", f02a: "F-2A", f04e: "F-4E Phantom II", f15c: "F-15C Eagle",
  f22a: "F-22A Raptor", f35c: "F-35C Lightning II", f18c: "F/A-18C Hornet", j39e: "Gripen E", su34: "Su-34 Fullback",
  e18g: "EA-18G Growler", typn: "Typhoon", f15j: "F-15J Eagle", a06e: "A-6E Intruder", rflm: "Rafale M",
  su25: "Su-25SM Frogfoot", x40a: "X-40 Nightmare", mr2k: "Mirage 2000-5", ea36: "EA-36 Barricader", fa36: "FA-36 Game",
  m29a: "MiG-29A Fulcrum", su57: "Su-57 Felon", f16c: "F-16C Fighting Falcon", f14d: "F-14D Super Tomcat",
  f18f: "F/A-18F Super Hornet", f15e: "F-15E Strike Eagle", su47: "Su-47 Berkut", m21b: "MiG-21bis Fishbed",
  su35: "Su-35S Flanker-E", m31b: "MiG-31B Foxhound", su33: "Su-33 Flanker-D", e06b: "EA-6B Prowler",
  f18e: "F/A-18E Super Hornet", f14a: "F-14A Tomcat", adfx: "ADFX-02" };
// (own keys only: "constructor" passes the code check and would name Object's constructor, its source on the boards;
// security review of 2026-10-26)
const own = (table, key) => (Object.hasOwn(table, key) ? table[key] : undefined);
const jet = (code) => (code ? own(AIRCRAFT, code) || code.toUpperCase() : null);
const RATE_PER_HOUR = 30;                     // runs one IP may submit in an hour (every ended run is sent, restarts too)
const API = "https://discord.com/api/v10";
// The mod's VERSION: "0.72.2", or a Survival COOP build's with its tag, "0.72.2-coop.20" (tools/coop_edition.py
// COOP_TAG; every co-op build's runs were refused as "bad mod version" before, user's run summary of 2026-10-30)
const MOD_RE = /^[0-9.]{1,16}(-coop\.[0-9]{1,4})?$/;
const BUILD_RE = /^[0-9a-f]{64}$/;            // a build hash (runtime/build_hash.c, tools/build_hash.py): SHA-256, hex

// The score, worked out here from the run (the game shows the same number; Scripts/main.lua runScore):
// 1000 a round reached, 100 an aircraft, 50 a ground or sea target, 3000 a special beaten, x the difficulty.
function score(run) {
  const won = (run.specials || []).filter((s) => s.won).length;
  const raw = run.round * 1000 + run.kills.air * 100 + run.kills.ground * 50 + won * 3000;
  return Math.floor(raw * DIFF_X[run.difficulty]);
}

// ------------------------------------------------------------------------------------------------- checks
const isInt = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;
const HOWS = ["died", "restart", "left"];

// A run as the game sends it, or the reason it's refused. Generous limits: they catch typing in numbers, not play.
function checkRun(run) {
  if (!run || typeof run !== "object") return "not a run";
  if (run.v !== 1) return "unknown format";
  if (typeof run.run_id !== "string" || !/^[0-9a-f]{16,64}$/.test(run.run_id)) return "bad run id";
  if (typeof run.pilot !== "string" || !/^[A-Za-z0-9 _.\-]{1,24}$/.test(run.pilot)) return "bad pilot name";
  if (!DIFFICULTIES.includes(run.difficulty)) return "bad difficulty";
  if (!isInt(run.round, 1, 1000)) return "bad round";
  if (!run.kills || !isInt(run.kills.air, 0, run.round * 70)) return "too many air kills for the rounds";
  if (!isInt(run.kills.ground, 0, run.round * 40 + 100)) return "too many ground kills for the rounds";
  if (!run.zollars || !isInt(run.zollars.earned, 0, 100000000) || !isInt(run.zollars.spent, 0, 100000000)) return "bad zollars";
  if (!isInt(run.time_s, Math.max(0, (run.round - 1) * 25), 48 * 3600)) return "run time doesn't fit the rounds";
  if (!["died", "quit"].includes(run.ended)) return "bad ending";
  if (typeof run.mod !== "string" || !MOD_RE.test(run.mod)) return "bad mod version";
  // (from mod 0.72.x: the build hash the game started with, and what it found edited: a run that says it was edited
  // isn't taken, its first edited setting named back)
  if (run.build !== undefined && (typeof run.build !== "string" || !BUILD_RE.test(run.build))) return "bad build";
  if (run.edited !== undefined) {
    if (!Array.isArray(run.edited) || run.edited.length > 16
        || !run.edited.every((e) => typeof e === "string" && e.length >= 1 && e.length <= 80)) return "bad edited list";
    if (run.edited.length) return `edited run (${run.edited[0].replace(/[^A-Za-z0-9_. +\-]/g, "").slice(0, 40)})`;
  }
  if (run.aircraft !== undefined && (typeof run.aircraft !== "string" || !/^[a-z0-9]{2,12}$/.test(run.aircraft))) return "bad aircraft";
  // (from mod 0.50.0; older runs leave them out)
  if (run.how !== undefined && !HOWS.includes(run.how)) return "bad ending";
  if (run.tier !== undefined && (typeof run.tier !== "string" || !/^[A-Za-z]{1,16}$/.test(run.tier))) return "bad tier";
  if (run.aces !== undefined && !isInt(run.aces, 0, run.kills.air)) return "bad ace kills";
  if (run.allies !== undefined && !isInt(run.allies, 0, run.round * 10)) return "bad allies";
  if (run.af_down !== undefined && !isInt(run.af_down, 0, run.round)) return "bad airfield losses";
  if (run.captured !== undefined && !isInt(run.captured, 0, run.round)) return "bad captures";
  const sp = run.specials || [];
  if (!Array.isArray(sp) || sp.length > run.round) return "too many specials";
  for (const s of sp) {
    if (typeof s.kind !== "string" || !/^[a-z]{1,16}$/.test(s.kind) || !isInt(s.round, 1, run.round)
        || !isInt(s.seconds, 5, 3600) || typeof s.won !== "boolean")
      return "bad special";
  }
  // a special this Worker doesn't know yet (a newer mod than the deployed Worker) is left out, not the whole run
  run.specials = sp.filter((s) => own(SPECIALS, s.kind));
  return null;
}

// ------------------------------------------------------------------------------------------------- crypto
const enc = new TextEncoder();
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
const unhex = (s) => new Uint8Array((s.match(/../g) || []).map((h) => parseInt(h, 16)));

async function hmacHex(key, text) {
  const k = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", k, enc.encode(text)));
}

async function sha256Hex(text) { return hex(await crypto.subtle.digest("SHA-256", enc.encode(text))); }

function sameText(a, b) {                  // constant time for equal lengths
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function discordSigned(req, body, publicKey) {
  const sig = req.headers.get("X-Signature-Ed25519"), ts = req.headers.get("X-Signature-Timestamp");
  if (!sig || !ts) return false;
  for (const alg of [{ name: "Ed25519" }, { name: "NODE-ED25519", namedCurve: "NODE-ED25519" }]) {
    try {
      const key = await crypto.subtle.importKey("raw", unhex(publicKey), alg, false, ["verify"]);
      return await crypto.subtle.verify(alg, key, unhex(sig), enc.encode(ts + body));
    } catch (e) { /* the other name on older runtimes */ }
  }
  return false;
}

// ------------------------------------------------------------------------------------------------- Discord
// A rate limit with a short wait (e.g. 429 code 30046, "Maximum number of edits to messages older than 1 hour", 1.4 s
// on the pinned boards; user, 2026-10-23) is waited out and tried again, twice at most.
async function discord(env, method, path, json) {
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(API + path, {
      method,
      headers: { Authorization: `Bot ${env.DISCORD_TOKEN}`, "Content-Type": "application/json" },
      body: json === undefined ? undefined : JSON.stringify(json),
    });
    if (r.ok) return r.status === 204 ? null : r.json();
    const text = await r.text();
    let wait = -1;
    if (r.status === 429) { try { wait = Number(JSON.parse(text).retry_after); } catch (e) { /* not JSON */ } }
    if (attempt < 2 && wait >= 0 && wait <= 10) { await new Promise((ok) => setTimeout(ok, wait * 1000 + 250)); continue; }
    throw new Error(`Discord ${method} ${path}: ${r.status} ${text}`);
  }
}

const fmtTime = (s) => `${Math.floor(s / 3600) ? Math.floor(s / 3600) + "h " : ""}${Math.floor(s / 60) % 60}m ${s % 60}s`;
const num = (n) => n.toLocaleString("en-US");

function runEmbed(run, sc, verified = true) {
  const won = (run.specials || []).filter((s) => s.won);
  return {
    title: `${run.pilot} reached round ${run.round} (${DIFF_NAME[run.difficulty]})`,
    color: run.ended === "died" ? 0xc0392b : 0x2e86c1,
    fields: [
      { name: "Score", value: num(sc), inline: true },
      { name: "Kills", value: `${run.kills.air} air, ${run.kills.ground} ground`, inline: true },
      { name: "Time", value: fmtTime(run.time_s), inline: true },
      ...(run.aircraft ? [{ name: "Aircraft", value: jet(run.aircraft), inline: true }] : []),
      ...(run.tier ? [{ name: "Enemy tier", value: run.tier, inline: true }] : []),
      ...(run.aces ? [{ name: "Ace squadron kills", value: String(run.aces), inline: true }] : []),
      ...(run.allies ? [{ name: "Allies called in", value: String(run.allies), inline: true }] : []),
      ...(run.af_down || run.captured ? [{ name: "Airfield", value: [run.af_down ? `lost ${run.af_down}x` : "",
          run.captured ? `captured ${run.captured}x` : ""].filter(Boolean).join(", "), inline: true }] : []),
      { name: "Specials beaten", value: won.length ? won.map((s) => `${SPECIALS[s.kind]} (round ${s.round}, ${fmtTime(s.seconds)})`).join("\n") : "none" },
    ],
    footer: { text: `${run.ended === "died" ? "Shot down" : run.how === "restart" ? "Restarted" : "Left the run"} · Survival Mode ${run.mod}` +
                    (verified ? "" : " · older mod, build not checked") },
  };
}

// The boards, as embeds: highest round and score per difficulty (best run per pilot), fastest beaten specials.
// Pilots are grouped ignoring case (as /pilot finds them); every query goes to D1 in one batch.
async function boardEmbeds(env, onlyBoard, onlyDiff) {
  await ensureSchema(env);
  const diffs = onlyDiff ? [onlyDiff] : DIFFICULTIES;
  const boards = [["round", "round", "Highest round"], ["score", "score", "Score"]]
    .filter(([board]) => !onlyBoard || onlyBoard === board);
  const kinds = !onlyBoard || onlyBoard === "specials" ? Object.entries(SPECIALS) : [];
  const stmts = [];
  for (const [, col] of boards)
    for (const d of diffs)
      // (one aggregate: SQLite takes the other columns, the aircraft too, from each pilot's best run)
      stmts.push(env.DB.prepare(`SELECT pilot, MAX(${col}) AS best, aircraft FROM runs WHERE difficulty = ?
         GROUP BY pilot COLLATE NOCASE ORDER BY best DESC LIMIT 10`).bind(d));
  for (const [kind] of kinds)
    stmts.push(env.DB.prepare(`SELECT pilot, MIN(seconds) AS best, difficulty FROM specials WHERE kind = ? AND won = 1
       ${onlyDiff ? "AND difficulty = ?" : ""} GROUP BY pilot COLLATE NOCASE ORDER BY best ASC LIMIT 5`)
      .bind(...(onlyDiff ? [kind, onlyDiff] : [kind])));
  const answers = stmts.length ? await env.DB.batch(stmts) : [];
  let n = 0;
  const out = [];
  for (const [board, , title] of boards) {
    const fields = diffs.map((d) => {
      const results = answers[n++].results;
      return { name: DIFF_NAME[d], value: results.length
        ? results.map((r, i) => `${i + 1}. **${r.pilot}** — ${board === "round" ? `round ${r.best}` : num(r.best)}` +
                                (r.aircraft ? ` (${jet(r.aircraft)})` : "")).join("\n")
        : "no runs yet", inline: true };
    });
    out.push({ title: `${title} — top 10`, color: 0xd4ac0d, fields });
  }
  if (kinds.length) {
    const fields = kinds.map(([, name]) => {
      const results = answers[n++].results;
      return { name, value: results.length
        ? results.map((r, i) => `${i + 1}. **${r.pilot}** — ${fmtTime(r.best)} (${DIFF_NAME[r.difficulty]})`).join("\n")
        : "not beaten yet", inline: true };
    });
    out.push({ title: "Fastest specials — top 5", color: 0x8e44ad, fields });
  }
  return out;
}

// The second message's boards: records (best single runs), the best run on each aircraft, and this week's best.
const RECORDS = [["Most kills in a run", "air_kills + ground_kills", (v) => `${num(v)} kills`],
                 ["Longest run", "time_s", (v) => fmtTime(v)],
                 ["Most zollars earned", "earned", (v) => `${num(v)} Z`],
                 ["Most ace squadron kills", "aces", (v) => `${num(v)}`]];
const EXTRA_BOARDS = ["records", "aircraft", "weekly"];

function weekStart(nowS) {                  // Monday 00:00 UTC of this week, unix seconds
  const d = new Date(nowS * 1000);
  return Math.floor(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - (d.getUTCDay() + 6) % 7) / 1000);
}

async function extraEmbeds(env, onlyBoard, onlyDiff, nowS = Math.floor(Date.now() / 1000)) {
  await ensureSchema(env);
  const want = (b) => !onlyBoard || onlyBoard === b;
  const dw = onlyDiff ? "AND difficulty = ?" : "";
  const da = onlyDiff ? [onlyDiff] : [];
  const stmts = [];
  if (want("records")) {
    for (const [, expr] of RECORDS)
      stmts.push(env.DB.prepare(`SELECT pilot, MAX(${expr}) AS best, difficulty FROM runs WHERE ${expr} > 0 ${dw}
         GROUP BY pilot COLLATE NOCASE ORDER BY best DESC LIMIT 5`).bind(...da));
    stmts.push(env.DB.prepare(`SELECT r.pilot AS pilot, MAX(c.n) AS best, r.difficulty AS difficulty
       FROM (SELECT run_id, COUNT(*) AS n FROM specials WHERE won = 1 GROUP BY run_id) c JOIN runs r ON r.run_id = c.run_id
       ${onlyDiff ? "WHERE r.difficulty = ?" : ""} GROUP BY r.pilot COLLATE NOCASE ORDER BY best DESC LIMIT 5`).bind(...da));
  }
  if (want("aircraft"))
    stmts.push(env.DB.prepare(`SELECT aircraft, pilot, MAX(round) AS best, difficulty FROM runs WHERE aircraft IS NOT NULL ${dw}
       GROUP BY aircraft ORDER BY best DESC LIMIT 15`).bind(...da));
  const since = weekStart(nowS);
  if (want("weekly"))
    for (const col of ["round", "score"])
      stmts.push(env.DB.prepare(`SELECT pilot, MAX(${col}) AS best, difficulty, aircraft FROM runs WHERE submitted >= ? ${dw}
         GROUP BY pilot COLLATE NOCASE ORDER BY best DESC LIMIT 5`).bind(since, ...da));
  const answers = stmts.length ? await env.DB.batch(stmts) : [];
  let n = 0;
  const lines = (results, fmt, none) => results.length ? results.map((r, i) => `${i + 1}. ${fmt(r)}`).join("\n") : none;
  const out = [];
  if (want("records")) {
    const fields = RECORDS.map(([name, , show]) => ({ name, inline: true, value: lines(answers[n++].results,
      (r) => `**${r.pilot}** — ${show(r.best)} (${DIFF_NAME[r.difficulty]})`, "no runs yet") }));
    fields.push({ name: "Most specials beaten in a run", inline: true, value: lines(answers[n++].results,
      (r) => `**${r.pilot}** — ${r.best} (${DIFF_NAME[r.difficulty]})`, "none beaten yet") });
    out.push({ title: "Records — top 5", color: 0x16a085, fields });
  }
  if (want("aircraft"))
    out.push({ title: "Best run on each aircraft", color: 0x2980b9, description: lines(answers[n++].results,
      (r) => `**${jet(r.aircraft)}** — ${r.pilot}, round ${r.best} (${DIFF_NAME[r.difficulty]})`, "no runs yet") });
  if (want("weekly")) {
    const day = new Date(since * 1000).toUTCString().slice(0, 11);
    const fields = [["Highest round", (r) => `round ${r.best}`], ["Score", (r) => num(r.best)]].map(([name, show]) => ({
      name, inline: true, value: lines(answers[n++].results,
        (r) => `**${r.pilot}** — ${show(r)} (${DIFF_NAME[r.difficulty]}${r.aircraft ? ", " + jet(r.aircraft) : ""})`, "no runs this week yet") }));
    out.push({ title: `This week — top 5 (since ${day} 00:00 UTC; resets every Monday)`, color: 0xe67e22, fields });
  }
  return out;
}

async function setting(env, key) {
  const r = await env.DB.prepare("SELECT value FROM settings WHERE key = ?").bind(key).first();
  return r ? r.value : null;
}

// The pinned leaderboard messages in BOARD_CHANNEL_ID, edited after every run: board_message (made and pinned by
// /setup) and board_message_2 (records, aircraft, this week: made and pinned here the first time it's missing).
async function pinnedMessage(env, key, content) {
  const id = await setting(env, key);
  if (id) return { id, made: false };
  const m = await discord(env, "POST", `/channels/${env.BOARD_CHANNEL_ID}/messages`, { content });
  await env.DB.prepare("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)").bind(key, m.id).run();
  await env.DB.prepare("DELETE FROM settings WHERE key = ?").bind(key + "_sum").run();   // (its content isn't there yet)
  let pinned = true;
  try { await discord(env, "PUT", `/channels/${env.BOARD_CHANNEL_ID}/pins/${m.id}`); } catch (e) { pinned = false; }
  return { id: m.id, made: true, pinned };
}

// One pinned message brought up to date; a message that's gone (deleted in Discord: 404 Unknown Message, which made
// every update and /setup fail) is forgotten and made again.
async function updatePinned(env, key, placeholder, body, force) {
  let m = await pinnedMessage(env, key, placeholder);
  // unchanged since the last edit: no edit (Discord caps edits to messages older than an hour); /setup always edits, so
  // a message deleted in Discord is found and made again
  const sum = await sha256Hex(JSON.stringify(body));
  if (!force && !m.made && (await setting(env, key + "_sum")) === sum) return m;
  try {
    await discord(env, "PATCH", `/channels/${env.BOARD_CHANNEL_ID}/messages/${m.id}`, body);
  } catch (e) {
    if (m.made || !String(e.message).includes(": 404 ")) throw e;
    await env.DB.prepare("DELETE FROM settings WHERE key = ?").bind(key).run();
    m = await pinnedMessage(env, key, placeholder);
    await discord(env, "PATCH", `/channels/${env.BOARD_CHANNEL_ID}/messages/${m.id}`, body);
    m.remade = true;
  }
  await env.DB.prepare("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)").bind(key + "_sum", sum).run();
  return m;
}

async function refreshBoards(env, force) {
  if (!(await setting(env, "board_message"))) return;
  const one = await updatePinned(env, "board_message", "Leaderboard coming up...",
    { content: "**AC8 Survival Mode — leaderboard** (updated after every run)", embeds: await boardEmbeds(env) }, force);
  const two = await updatePinned(env, "board_message_2", "Records coming up...",
    { content: "**AC8 Survival Mode — records, aircraft and this week**", embeds: await extraEmbeds(env) }, force);
  return { ...two, oneRemade: !!one.remade };
}

// Columns added after the first databases were made (aircraft; how / tier / aces / allies / af_down / captured from
// mod 0.50.0; build / verified from 0.72.x: the build hash a run came with, 1 when that build was registered, 0 for an
// older mod's run taken while verification was off), added to an older database once per Worker instance.
const NEW_COLUMNS = { aircraft: "TEXT", how: "TEXT", tier: "TEXT", aces: "INTEGER", allies: "INTEGER", af_down: "INTEGER",
                      captured: "INTEGER", build: "TEXT", verified: "INTEGER" };
const RUN_COLS = ["run_id", "pilot", "difficulty", "round", "score", "air_kills", "ground_kills", "earned", "spent", "time_s",
                  "ended", "mod_version", "submitted", "ip_hash", ...Object.keys(NEW_COLUMNS)];
const SPECIAL_COLS = ["run_id", "kind", "round", "seconds", "won", "pilot", "difficulty"];
// Tables added with the admin page (2026-10-30), made here on a database that hasn't them (schema.sql has them too):
//   builds            the builds runs are taken from (registered on /admin from a release's .buildhash.txt)
//   builds_seen       builds runs came from that weren't registered (shown on /admin; the newest 100 kept)
//   resets            each reset of the boards; runs_archive / specials_archive hold what it took off, so it can be undone
//   admin_fails       wrong admin keys, for the lock-out
const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS builds (mod TEXT NOT NULL, build TEXT NOT NULL, note TEXT, added INTEGER NOT NULL,
     PRIMARY KEY (mod, build))`,
  `CREATE TABLE IF NOT EXISTS builds_seen (mod TEXT NOT NULL, build TEXT NOT NULL, first INTEGER NOT NULL, last INTEGER NOT NULL,
     n INTEGER NOT NULL, pilot TEXT, PRIMARY KEY (mod, build))`,
  `CREATE TABLE IF NOT EXISTS resets (reset_id TEXT PRIMARY KEY, at INTEGER NOT NULL, runs INTEGER NOT NULL,
     specials INTEGER NOT NULL, restored INTEGER)`,
  `CREATE TABLE IF NOT EXISTS runs_archive (reset_id TEXT NOT NULL, reset_at INTEGER NOT NULL, run_id TEXT NOT NULL, pilot TEXT,
     difficulty TEXT, round INTEGER, score INTEGER, air_kills INTEGER, ground_kills INTEGER, earned INTEGER, spent INTEGER,
     time_s INTEGER, ended TEXT, mod_version TEXT, submitted INTEGER, ip_hash TEXT, aircraft TEXT, how TEXT, tier TEXT,
     aces INTEGER, allies INTEGER, af_down INTEGER, captured INTEGER, build TEXT, verified INTEGER)`,
  "CREATE INDEX IF NOT EXISTS runs_archive_reset ON runs_archive (reset_id)",
  "CREATE INDEX IF NOT EXISTS runs_archive_run ON runs_archive (run_id)",
  `CREATE TABLE IF NOT EXISTS specials_archive (reset_id TEXT NOT NULL, reset_at INTEGER NOT NULL, run_id TEXT NOT NULL,
     kind TEXT, round INTEGER, seconds INTEGER, won INTEGER, pilot TEXT, difficulty TEXT)`,
  "CREATE INDEX IF NOT EXISTS specials_archive_reset ON specials_archive (reset_id)",
  "CREATE TABLE IF NOT EXISTS admin_fails (ip_hash TEXT NOT NULL, at INTEGER NOT NULL)",
  "CREATE INDEX IF NOT EXISTS admin_fails_ip ON admin_fails (ip_hash, at)",
  "CREATE INDEX IF NOT EXISTS runs_week ON runs (submitted)",                                     // (this week's board)
];
let haveSchema = false;
async function ensureSchema(env) {
  if (haveSchema) return;
  // (one round trip for them all: one at a time, 15 of them on each fresh Worker instance, they and the boards' queries
  // took a slash command past Discord's 3 s: "The application did not respond", 2026-10-30)
  await env.DB.batch(SCHEMA.map((sql) => env.DB.prepare(sql)));
  for (const table of ["runs", "runs_archive"]) {
    const { results } = await env.DB.prepare(`PRAGMA table_info(${table})`).all();
    const have = new Set(results.map((r) => r.name));
    for (const [col, type] of Object.entries(NEW_COLUMNS))
      if (!have.has(col)) await env.DB.prepare(`ALTER TABLE ${table} ADD COLUMN ${col} ${type}`).run();
  }
  haveSchema = true;
}

// Build verification (settings "verify_builds", /admin): on, a run without a build hash (a mod from before 0.72.x) is
// refused; off, it's taken and marked unverified. A run with one counts only from a registered build either way.
async function verifyOn(env) { return (await setting(env, "verify_builds")) === "1"; }

// ------------------------------------------------------------------------------------------------- routes
const ipHashOf = (req, env) => sha256Hex((req.headers.get("CF-Connecting-IP") || "?") + (env.SUBMIT_KEY || ""));

async function submit(req, env, ctx) {
  const body = await req.text();
  if (body.length > 16384) return json({ ok: false, error: "too big" }, 413);
  // the build (mod 0.72.x): its hash in X-SV-Build, and the signature over "<build>\n<body>" (runtime/survival_rt.c
  // PostWorker), so a run can't be given another build's hash; without it (an older mod) the body alone is signed
  const build = (req.headers.get("X-SV-Build") || "").trim().toLowerCase();
  if (build && !BUILD_RE.test(build)) return json({ ok: false, error: "bad build" }, 400);
  const sig = (req.headers.get("X-SV-Signature") || "").toLowerCase();
  if (!sameText(sig, await hmacHex(env.SUBMIT_KEY, build ? `${build}\n${body}` : body)))
    return json({ ok: false, error: "bad signature" }, 401);
  let run;
  try { run = JSON.parse(body); } catch (e) { return json({ ok: false, error: "not JSON" }, 400); }
  const why = checkRun(run);
  if (why) return json({ ok: false, error: why }, 422);
  // (the build the game started with against the one it sends from: a run kept from other files, e.g. sent after the
  // mod's files were put back, isn't taken)
  if (build && run.build && run.build !== build) return json({ ok: false, error: "played on other files" }, 422);
  await ensureSchema(env);
  const ipHash = await ipHashOf(req, env);
  const now = Math.floor(Date.now() / 1000);
  // (a run taken off by a reset and sent again isn't put back on the fresh boards: it comes back with the reset's undo)
  if (await env.DB.prepare("SELECT 1 FROM runs WHERE run_id = ? UNION ALL SELECT 1 FROM runs_archive WHERE run_id = ?")
        .bind(run.run_id, run.run_id).first())
    return json({ ok: true, duplicate: true });                    // (the game may resend after a lost reply)
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM runs WHERE ip_hash = ? AND submitted > ?")
    .bind(ipHash, now - 3600).first();
  if (recent.n >= RATE_PER_HOUR) return json({ ok: false, error: "too many runs this hour, try later" }, 429);
  let verified = 0;
  if (build) {
    if (!(await env.DB.prepare("SELECT 1 FROM builds WHERE mod = ? AND build = ?").bind(run.mod, build).first())) {
      // (kept for /admin, so a release that wasn't registered shows up there; the newest 100)
      await env.DB.batch([
        env.DB.prepare(`INSERT INTO builds_seen (mod, build, first, last, n, pilot) VALUES (?, ?, ?, ?, 1, ?)
           ON CONFLICT (mod, build) DO UPDATE SET last = excluded.last, n = n + 1, pilot = excluded.pilot`)
          .bind(run.mod, build, now, now, run.pilot),
        env.DB.prepare(`DELETE FROM builds_seen WHERE rowid NOT IN (SELECT rowid FROM builds_seen ORDER BY last DESC LIMIT 100)`),
      ]);
      return json({ ok: false, error: "edited or unknown build" }, 422);
    }
    verified = 1;
  } else if (await verifyOn(env)) {
    return json({ ok: false, error: "no build check: update or reinstall survival mode" }, 422);
  }
  const sc = score(run);
  const opt = (v) => (v === undefined ? null : v);
  const batch = [env.DB.prepare(
    `INSERT INTO runs (run_id, pilot, difficulty, round, score, air_kills, ground_kills, earned, spent, time_s, ended,
     mod_version, submitted, ip_hash, aircraft, how, tier, aces, allies, af_down, captured, build, verified)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(run.run_id, run.pilot, run.difficulty, run.round, sc, run.kills.air, run.kills.ground, run.zollars.earned,
          run.zollars.spent, run.time_s, run.ended, run.mod, now, ipHash, opt(run.aircraft), opt(run.how), opt(run.tier),
          opt(run.aces), opt(run.allies), opt(run.af_down), opt(run.captured), build || null, verified)];
  for (const s of run.specials || [])
    batch.push(env.DB.prepare("INSERT INTO specials (run_id, kind, round, seconds, won, pilot, difficulty) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .bind(run.run_id, s.kind, s.round, s.seconds, s.won ? 1 : 0, run.pilot, run.difficulty));
  await env.DB.batch(batch);
  // the post and the boards: a Discord hiccup mustn't lose the run (it's stored), so their errors are only logged; they
  // run after the reply (ctx.waitUntil), so a rate-limit wait never holds the game past its 15 s timeout (code review
  // of 2026-10-23)
  const after = (async () => {
    try { await discord(env, "POST", `/channels/${env.RUNS_CHANNEL_ID}/messages`, { embeds: [runEmbed(run, sc, verified === 1)] }); }
    catch (e) { console.log(String(e)); }
    try { await refreshBoards(env); } catch (e) { console.log(String(e)); }
  })();
  if (ctx && ctx.waitUntil) ctx.waitUntil(after); else await after;     // (tests: no ctx)
  return json({ ok: true, score: sc });
}

async function pilotEmbed(env, name) {
  const runs = await env.DB.prepare(
    "SELECT difficulty, MAX(round) AS round, MAX(score) AS score, COUNT(*) AS n FROM runs WHERE pilot = ? COLLATE NOCASE GROUP BY difficulty")
    .bind(name).all();
  if (!runs.results.length) return { title: `No runs from ${name} yet`, color: 0x7f8c8d };
  const sp = await env.DB.prepare(
    "SELECT kind, MIN(seconds) AS best FROM specials WHERE pilot = ? COLLATE NOCASE AND won = 1 GROUP BY kind").bind(name).all();
  const tot = await env.DB.prepare(`SELECT COUNT(*) AS runs, SUM(air_kills) AS air, SUM(ground_kills) AS ground,
     SUM(time_s) AS time_s, SUM(earned) AS earned, SUM(COALESCE(aces, 0)) AS aces FROM runs WHERE pilot = ? COLLATE NOCASE`)
    .bind(name).first();
  const fav = await env.DB.prepare(`SELECT aircraft, COUNT(*) AS n FROM runs WHERE pilot = ? COLLATE NOCASE AND aircraft IS NOT NULL
     GROUP BY aircraft ORDER BY n DESC LIMIT 1`).bind(name).first();
  return {
    title: `${name} — Survival Mode`,
    color: 0x2e86c1,
    fields: [
      ...runs.results.map((r) => ({ name: DIFF_NAME[r.difficulty],
        value: `best round ${r.round}\nbest score ${num(r.score)}\n${r.n} run${r.n === 1 ? "" : "s"}`, inline: true })),
      { name: "Fastest specials", value: sp.results.length ? sp.results.map((s) => `${SPECIALS[s.kind]}: ${fmtTime(s.best)}`).join("\n") : "none beaten yet" },
      { name: "Totals", value: `${num(tot.runs)} runs, ${fmtTime(tot.time_s || 0)} flown\n${num(tot.air || 0)} air / ${num(tot.ground || 0)} ground kills` +
          `${tot.aces ? `, ${num(tot.aces)} ace squadron` : ""}\n${num(tot.earned || 0)} Z earned` +
          (fav ? `\nmost flown: ${jet(fav.aircraft)}` : "") },
    ],
  };
}

// A slash command's answer (a message's data: embeds, or content).
async function commandReply(env, it) {
  const opt = Object.fromEntries((it.data.options || []).map((o) => [o.name, o.value]));
  if (it.data.name === "leaderboard")
    return { embeds: EXTRA_BOARDS.includes(opt.board)
      ? await extraEmbeds(env, opt.board, opt.difficulty || null)
      : await boardEmbeds(env, opt.board || null, opt.difficulty || null) };
  if (it.data.name === "pilot") return { embeds: [await pilotEmbed(env, String(opt.name || "").slice(0, 24))] };
  return { content: "Unknown command." };
}

// ... edited into the "thinking..." answer once it's made (the interaction's own webhook: its token, no bot auth); a
// failure says so there rather than leaving "thinking..." up
async function commandFollowUp(env, it) {
  let data;
  try { data = await commandReply(env, it); } catch (e) {
    console.log(String(e && e.stack || e));
    data = { content: "The leaderboard couldn't be read just now. Try again in a minute." };
  }
  const r = await fetch(`${API}/webhooks/${env.DISCORD_APP_ID}/${it.token}/messages/@original`,
    { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) });
  if (!r.ok) console.log(`interaction follow-up: ${r.status} ${await r.text()}`);
}

// Discord gives an interaction 3 s for its first answer, and a fresh Worker instance's ensureSchema plus the boards'
// queries took longer (2026-10-30, after the admin page's deploy: "The application did not respond"): a command is
// answered "thinking..." at once (type 5) and its board edited in by commandFollowUp (Discord allows 15 minutes).
// Without ctx (the local test) it's answered in one go, as before.
async function interactions(req, env, ctx) {
  const body = await req.text();
  if (!(await discordSigned(req, body, env.DISCORD_PUBLIC_KEY))) return new Response("bad signature", { status: 401 });
  const it = JSON.parse(body);
  if (it.type === 1) return json({ type: 1 });                       // Discord's ping
  if (it.type === 2) {
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(commandFollowUp(env, it));
      return json({ type: 5 });
    }
    return json({ type: 4, data: await commandReply(env, it) });
  }
  return json({ type: 4, data: { content: "Unknown command." } });
}

const COMMANDS = [
  { name: "leaderboard", description: "AC8 Survival Mode leaderboards", options: [
    { type: 3, name: "board", description: "Which board", required: false,
      choices: [{ name: "Highest round", value: "round" }, { name: "Score", value: "score" }, { name: "Fastest specials", value: "specials" },
                { name: "Records", value: "records" }, { name: "Best per aircraft", value: "aircraft" }, { name: "This week", value: "weekly" }] },
    { type: 3, name: "difficulty", description: "Which difficulty", required: false,
      choices: DIFFICULTIES.map((d) => ({ name: DIFF_NAME[d], value: d })) }] },
  { name: "pilot", description: "A pilot's best Survival Mode runs", options: [
    { type: 3, name: "name", description: "The pilot name", required: true }] },
];

async function setup(req, env) {
  const denied = await adminDenied(req, env, new URL(req.url).searchParams.get("key") || "");
  if (denied) return denied;
  const done = [];
  let step = "registering the slash commands";
  try {           // (admin only: a failure says which step and why, not just "server error")
    await discord(env, "PUT", `/applications/${env.DISCORD_APP_ID}/commands`, COMMANDS);
    done.push("slash commands registered (they can take a minute to show)");
    step = "making the leaderboard message";
    if (!(await setting(env, "board_message"))) {
      const m = await pinnedMessage(env, "board_message", "Leaderboard coming up...");
      done.push(`leaderboard message made${m.pinned ? " and pinned" : " (pinning failed: give the bot Manage Messages)"}`);
    }
    step = "updating the leaderboard messages";
    const two = await refreshBoards(env, true);
    if (two && two.oneRemade) done.push("the leaderboard message was gone: made again");
    if (two && two.made) done.push(`records message ${two.remade ? "was gone: made again" : "made"}${two.pinned ? " and pinned" : " (pinning failed: give the bot Manage Messages)"}`);
    done.push("leaderboard up to date");
  } catch (e) {
    console.log(String(e && e.stack || e));
    return json({ ok: false, failed: step, error: String(e && e.message || e), done }, 500);
  }
  return json({ ok: true, done });
}

// ------------------------------------------------------------------------------------------------- admin
// The admin page (user, 2026-10-30: "I need an ability for Me Only, that allows me to reset the entire leaderboard"):
// GET /admin is a page that works from a phone's browser; its actions are POST /admin/<action> with the key in the
// JSON body (never in the address, so it's in no log or browser history), compared in constant time. Five wrong keys
// from one address lock that address out for 15 minutes (/setup's key counts too).
const ADMIN_TRIES = 5, ADMIN_LOCK_S = 900;

// null when the key is right, else the answer to send
async function adminDenied(req, env, key) {
  if (!env.ADMIN_KEY) return json({ ok: false, error: "the Worker has no ADMIN_KEY set" }, 503);
  await ensureSchema(env);
  const ip = await ipHashOf(req, env);
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare("DELETE FROM admin_fails WHERE at < ?").bind(now - 86400).run();
  const tries = await env.DB.prepare("SELECT COUNT(*) AS n FROM admin_fails WHERE ip_hash = ? AND at > ?")
    .bind(ip, now - ADMIN_LOCK_S).first();
  if (tries.n >= ADMIN_TRIES) return json({ ok: false, error: "too many wrong keys: try again in 15 minutes" }, 429);
  // (both sides hashed first: equal lengths, so the comparison takes the same time whatever was typed)
  if (typeof key === "string" && key.length <= 1024 && sameText(await sha256Hex(key), await sha256Hex(env.ADMIN_KEY)))
    return null;
  await env.DB.prepare("INSERT INTO admin_fails (ip_hash, at) VALUES (?, ?)").bind(ip, now).run();
  return json({ ok: false, error: "wrong key" }, 401);
}

// What the page shows: the boards' size, verification, the builds, builds seen that aren't registered, the resets.
async function adminStatus(env) {
  const [runs, specials, builds, seen, resets] = await env.DB.batch([
    env.DB.prepare("SELECT COUNT(*) AS n FROM runs"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM specials"),
    env.DB.prepare(`SELECT b.mod AS mod, b.build AS build, b.note AS note, b.added AS added,
       (SELECT COUNT(*) FROM runs r WHERE r.build = b.build AND r.mod_version = b.mod) AS runs
       FROM builds b ORDER BY b.added DESC`),
    env.DB.prepare(`SELECT s.mod AS mod, s.build AS build, s.first AS first, s.last AS last, s.n AS n, s.pilot AS pilot
       FROM builds_seen s WHERE NOT EXISTS (SELECT 1 FROM builds b WHERE b.mod = s.mod AND b.build = s.build)
       ORDER BY s.last DESC LIMIT 20`),
    env.DB.prepare("SELECT reset_id, at, runs, specials, restored FROM resets ORDER BY at DESC, rowid DESC LIMIT 10"),
  ]);
  const undo = resets.results.find((r) => r.restored === null) || null;
  return { runs: runs.results[0].n, specials: specials.results[0].n, verify: await verifyOn(env),
           builds: builds.results, seen: seen.results, resets: resets.results, undo };
}

// After a reset or its undo: the pinned boards edited now, and a line in the runs channel. A Discord failure doesn't
// undo the change (it's done); it's said in the answer.
async function adminAnnounce(env, text) {
  const out = [];
  try { await refreshBoards(env, true); out.push("pinned boards updated"); }
  catch (e) { out.push(`pinned boards NOT updated: ${String(e && e.message || e).slice(0, 200)}`); }
  if (env.RUNS_CHANNEL_ID) {
    try { await discord(env, "POST", `/channels/${env.RUNS_CHANNEL_ID}/messages`, { content: text }); out.push("note posted in the runs channel"); }
    catch (e) { out.push(`note NOT posted: ${String(e && e.message || e).slice(0, 200)}`); }
  }
  return out;
}

const word = (v) => String(v === undefined || v === null ? "" : v).trim().toUpperCase();
const plural = (n, one) => `${num(n)} ${one}${n === 1 ? "" : "s"}`;

const ADMIN_ACTIONS = {
  status: async () => ({ done: "unlocked" }),

  // Everything on the boards (runs and specials: the round / score / specials boards, records, aircraft and this week
  // all read those two) moved to the archive under a new reset id, in one batch (D1 runs a batch as one transaction).
  reset: async (env, body, now) => {
    if (word(body.confirm) !== "RESET") return { error: "type RESET in the box to confirm", status: 400 };
    const id = `${now}-${hex(crypto.getRandomValues(new Uint8Array(4)))}`;
    const rc = RUN_COLS.join(", "), sc = SPECIAL_COLS.join(", ");
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO resets (reset_id, at, runs, specials) VALUES (?, ?, (SELECT COUNT(*) FROM runs),
         (SELECT COUNT(*) FROM specials))`).bind(id, now),
      env.DB.prepare(`INSERT INTO runs_archive (reset_id, reset_at, ${rc}) SELECT ?, ?, ${rc} FROM runs`).bind(id, now),
      env.DB.prepare(`INSERT INTO specials_archive (reset_id, reset_at, ${sc}) SELECT ?, ?, ${sc} FROM specials`).bind(id, now),
      env.DB.prepare("DELETE FROM specials"),
      env.DB.prepare("DELETE FROM runs"),
    ]);
    const r = await env.DB.prepare("SELECT runs, specials FROM resets WHERE reset_id = ?").bind(id).first();
    const discordDone = await adminAnnounce(env, `**The Survival Mode leaderboard was reset.** ${plural(r.runs, "run")} ` +
      "went to the archive; the boards start again from zero.");
    return { done: `reset: ${plural(r.runs, "run")} and ${plural(r.specials, "special result")} archived (undo: Restore the last reset)`,
             reset_id: id, discord: discordDone };
  },

  // The last reset not yet undone, moved back (runs sent since stay; a run that's on the boards again already isn't
  // doubled). Several resets: each press undoes the latest one left.
  restore: async (env, body, now) => {
    const last = await env.DB.prepare("SELECT reset_id, at FROM resets WHERE restored IS NULL ORDER BY at DESC, rowid DESC LIMIT 1").first();
    if (!last) return { error: "there's no reset to undo", status: 404 };
    const rc = RUN_COLS.join(", "), sc = SPECIAL_COLS.join(", ");
    const counts = await env.DB.prepare(`SELECT (SELECT COUNT(*) FROM runs_archive WHERE reset_id = ?) AS runs,
       (SELECT COUNT(*) FROM specials_archive WHERE reset_id = ?) AS specials`).bind(last.reset_id, last.reset_id).first();
    await env.DB.batch([
      env.DB.prepare(`INSERT OR IGNORE INTO runs (${rc}) SELECT ${rc} FROM runs_archive WHERE reset_id = ?`).bind(last.reset_id),
      env.DB.prepare(`INSERT INTO specials (${sc}) SELECT ${sc} FROM specials_archive WHERE reset_id = ?
         AND run_id NOT IN (SELECT run_id FROM specials)`).bind(last.reset_id),
      env.DB.prepare("DELETE FROM runs_archive WHERE reset_id = ?").bind(last.reset_id),
      env.DB.prepare("DELETE FROM specials_archive WHERE reset_id = ?").bind(last.reset_id),
      env.DB.prepare("UPDATE resets SET restored = ? WHERE reset_id = ?").bind(now, last.reset_id),
    ]);
    const day = new Date(last.at * 1000).toUTCString().slice(0, 22);
    const discordDone = await adminAnnounce(env, `**The leaderboard reset of ${day} UTC was undone:** ` +
      `${plural(counts.runs, "run")} ${counts.runs === 1 ? "is" : "are"} back on the boards.`);
    return { done: `restored the reset of ${day} UTC: ${plural(counts.runs, "run")} back`, discord: discordDone };
  },

  "builds/add": async (env, body, now) => {
    const mod = String(body.mod || "").trim(), build = String(body.build || "").trim().toLowerCase();
    if (!MOD_RE.test(mod)) return { error: "the mod version isn't one the game sends (e.g. 0.72.2 or 0.72.2-coop.20)", status: 400 };
    if (!BUILD_RE.test(build)) return { error: "the build hash must be 64 hex characters", status: 400 };
    const note = String(body.note || "").replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 80);
    await env.DB.prepare("INSERT OR REPLACE INTO builds (mod, build, note, added) VALUES (?, ?, ?, ?)").bind(mod, build, note, now).run();
    return { done: `build ${build.slice(0, 12)}... registered for ${mod}` };
  },

  "builds/remove": async (env, body) => {
    const mod = String(body.mod || ""), build = String(body.build || "").toLowerCase();
    const r = await env.DB.prepare("DELETE FROM builds WHERE mod = ? AND build = ?").bind(mod, build).run();
    const n = r && r.meta ? r.meta.changes : r && r.changes;
    if (!n) return { error: "no such build", status: 404 };
    return { done: `build ${build.slice(0, 12)}... (${mod}) removed: its runs aren't taken any more` };
  },

  verify: async (env, body) => {
    if (typeof body.on !== "boolean") return { error: "on must be true or false", status: 400 };
    await env.DB.prepare("INSERT OR REPLACE INTO settings (key, value) VALUES ('verify_builds', ?)").bind(body.on ? "1" : "0").run();
    return { done: body.on ? "verification ON: runs from older mods (no build hash) are refused"
                           : "verification OFF: runs from older mods are taken, marked unverified" };
  },
};

async function admin(req, env, action) {
  const text = await req.text();
  if (text.length > 8192) return json({ ok: false, error: "too big" }, 413);
  let body;
  try { body = JSON.parse(text); } catch (e) { return json({ ok: false, error: "not JSON" }, 400); }
  if (!body || typeof body !== "object") return json({ ok: false, error: "not JSON" }, 400);
  const denied = await adminDenied(req, env, body.key);
  if (denied) return denied;
  const fn = Object.hasOwn(ADMIN_ACTIONS, action) ? ADMIN_ACTIONS[action] : null;
  if (!fn) return json({ ok: false, error: "unknown action" }, 404);
  const out = await fn(env, body, Math.floor(Date.now() / 1000));
  if (out.error) return json({ ok: false, error: out.error, status: await adminStatus(env) }, out.status || 400);
  return json({ ok: true, ...out, status: await adminStatus(env) });
}

// The page itself: no external scripts, styles or fonts; its script and style carry this answer's nonce (CSP).
function adminPage() {
  const nonce = hex(crypto.getRandomValues(new Uint8Array(16)));
  return new Response(ADMIN_HTML.replaceAll("__NONCE__", nonce), { headers: {
    "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; ` +
      "connect-src 'self'; form-action 'none'; frame-ancestors 'none'; base-uri 'none'" } });
}

const ADMIN_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Leaderboard Admin</title>
<style nonce="__NONCE__">
:root { color-scheme: light dark; --bg: #f4f5f7; --fg: #1b1f24; --card: #ffffff; --line: #d3d8de; --muted: #5a636e;
  --accent: #1f6feb; --danger: #c62828; --ok: #2e7d32; }
@media (prefers-color-scheme: dark) { :root { --bg: #101317; --fg: #e5e8ec; --card: #191e24; --line: #2c333b;
  --muted: #9aa4af; --accent: #4c8dff; --danger: #ef5350; --ok: #57b45c; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
main { max-width: 640px; margin: 0 auto; padding: 16px; }
h1 { font-size: 1.25rem; margin: 6px 0 14px; }
h2 { font-size: 1.05rem; margin: 0 0 8px; }
h3 { font-size: .95rem; margin: 14px 0 4px; }
section { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 14px; margin: 0 0 14px; }
p { margin: 6px 0; }
.muted { color: var(--muted); font-size: .9rem; }
label { display: block; font-size: .9rem; margin-top: 6px; }
input, textarea, button { font: inherit; width: 100%; padding: 10px 12px; border-radius: 8px; border: 1px solid var(--line);
  background: var(--bg); color: var(--fg); margin: 4px 0; }
textarea { font-family: ui-monospace, Consolas, monospace; font-size: .85rem; }
button { background: var(--accent); color: #fff; border: 0; font-weight: 600; min-height: 44px; cursor: pointer; }
button.danger { background: var(--danger); }
button.plain { background: transparent; color: var(--accent); border: 1px solid var(--line); }
button.small { width: auto; min-height: 36px; padding: 6px 12px; margin: 6px 0 0; }
button:disabled { opacity: .45; cursor: default; }
ul { list-style: none; padding: 0; margin: 6px 0; }
li { border-top: 1px solid var(--line); padding: 8px 0; overflow-wrap: anywhere; }
code { font-family: ui-monospace, Consolas, monospace; font-size: .85rem; }
.pill { display: inline-block; padding: 1px 10px; border-radius: 99px; font-weight: 600; color: #fff; }
.on { background: var(--ok); } .off { background: var(--muted); }
#msg { white-space: pre-wrap; min-height: 1.4em; }
#msg.bad { color: var(--danger); }
.hidden { display: none; }
</style></head>
<body><main>
<h1>Survival Mode leaderboard: admin</h1>
<section id="login">
  <form id="loginForm">
    <label for="key">Admin key (the Worker's ADMIN_KEY)</label>
    <input id="key" name="password" type="password" autocomplete="current-password" required>
    <button type="submit">Unlock</button>
  </form>
  <p class="muted">The key goes in each request's body, never in the address. Five wrong keys lock this address out for 15 minutes.</p>
</section>
<div id="panel" class="hidden">
  <section>
    <h2>Status</h2>
    <p id="counts"></p>
    <p>Build verification: <span id="verify" class="pill"></span></p>
    <button id="verifyBtn" class="plain" type="button"></button>
    <p class="muted">A run from Survival Mode 0.72.x or newer counts only when its build is registered below, whatever this says.
      On: runs from older mods (no build hash) are refused. Off: they're taken, marked unverified.
      Register the build players use first, then turn this on.</p>
  </section>
  <section>
    <h2>Builds runs are taken from</h2>
    <ul id="builds"></ul>
    <label for="paste">Register a build: paste the release's .buildhash.txt (its mod and build lines)</label>
    <textarea id="paste" rows="4" spellcheck="false" autocapitalize="off" autocomplete="off"></textarea>
    <label for="note">Note (optional, e.g. the zip's name)</label>
    <input id="note" maxlength="80" autocomplete="off">
    <button id="addBtn" type="button">Register build</button>
    <h3>Builds seen but not registered</h3>
    <p class="muted">Runs from these were refused. Register one only if you packaged it: an edited build shows up here too.</p>
    <ul id="seen"></ul>
  </section>
  <section>
    <h2>Reset the leaderboard</h2>
    <p>Takes every run off the boards (round, score, specials, records, aircraft and this week) and keeps them in the archive,
      so the reset can be undone. The pinned boards are updated and a note goes to the runs channel.</p>
    <label for="confirm">Type RESET to confirm</label>
    <input id="confirm" autocomplete="off" autocapitalize="characters" spellcheck="false">
    <button id="resetBtn" class="danger" type="button">Reset the leaderboard</button>
    <h3>Undo</h3>
    <p id="undoText" class="muted"></p>
    <button id="undoBtn" class="plain" type="button">Restore the last reset</button>
  </section>
  <p id="msg" role="status" aria-live="polite"></p>
</div>
</main>
<script nonce="__NONCE__">
"use strict";
let KEY = "", STATE = null;
const $ = (id) => document.getElementById(id);
function say(text, bad) { const m = $("msg"); m.textContent = text; m.className = bad ? "bad" : ""; }
function el(tag, text, cls) { const e = document.createElement(tag); if (text !== undefined) e.textContent = text; if (cls) e.className = cls; return e; }
const when = (s) => (s ? new Date(s * 1000).toISOString().slice(0, 16).replace("T", " ") + " UTC" : "");
async function call(action, extra) {
  const r = await fetch("/admin/" + action, { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(Object.assign({ key: KEY }, extra || {})) });
  let j;
  try { j = await r.json(); } catch (e) { j = { ok: false, error: "status " + r.status }; }
  if (j.status && typeof j.status === "object") render(j.status);
  if (!j.ok) throw new Error(j.error || ("status " + r.status));
  return j;
}
async function act(button, action, extra) {
  button.disabled = true;
  try {
    const j = await call(action, extra);
    say([j.done].concat(j.discord || []).filter(Boolean).join("\\n"));
    return j;
  } catch (e) { say(e.message, true); return null; }
  finally { button.disabled = false; }
}
function render(s) {
  STATE = s;
  $("counts").textContent = s.runs + " run" + (s.runs === 1 ? "" : "s") + " and " + s.specials + " special result" +
    (s.specials === 1 ? "" : "s") + " on the boards.";
  const v = $("verify");
  v.textContent = s.verify ? "ON" : "OFF";
  v.className = "pill " + (s.verify ? "on" : "off");
  $("verifyBtn").textContent = s.verify ? "Turn verification off" : "Turn verification on";
  const list = $("builds");
  list.replaceChildren();
  if (!s.builds.length) list.append(el("li", "None yet: no run from 0.72.x or newer is taken until its build is here.", "muted"));
  for (const b of s.builds) {
    const li = el("li");
    li.append(el("strong", b.mod), " ", el("code", b.build.slice(0, 16) + "..."),
      el("div", (b.note ? b.note + " | " : "") + b.runs + " run" + (b.runs === 1 ? "" : "s") + " | added " + when(b.added), "muted"));
    const rm = el("button", "Remove", "plain small");
    rm.type = "button";
    rm.addEventListener("click", () => {
      if (confirm("Remove build " + b.build.slice(0, 16) + "... (" + b.mod + ")? Runs from it are refused from now on.")) act(rm, "builds/remove", { mod: b.mod, build: b.build });
    });
    li.append(rm);
    list.append(li);
  }
  const seen = $("seen");
  seen.replaceChildren();
  if (!s.seen.length) seen.append(el("li", "None.", "muted"));
  for (const b of s.seen) {
    const li = el("li");
    li.append(el("strong", b.mod), " ", el("code", b.build.slice(0, 16) + "..."),
      el("div", b.n + " refused run" + (b.n === 1 ? "" : "s") + ", last " + when(b.last) + (b.pilot ? " from " + b.pilot : ""), "muted"));
    const add = el("button", "Register", "plain small");
    add.type = "button";
    add.addEventListener("click", () => {
      if (confirm("Register " + b.build.slice(0, 16) + "... for " + b.mod + "? Only do this for a build you packaged.")) act(add, "builds/add", { mod: b.mod, build: b.build, note: "from builds seen" });
    });
    li.append(add);
    seen.append(li);
  }
  $("undoText").textContent = s.undo ? ("Last reset: " + when(s.undo.at) + ", " + s.undo.runs + " run" + (s.undo.runs === 1 ? "" : "s") + " archived.") : "No reset to undo.";
  $("undoBtn").disabled = !s.undo;
}
$("loginForm").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  KEY = $("key").value;
  try {
    await call("status");
    $("login").classList.add("hidden");
    $("panel").classList.remove("hidden");
    say("Unlocked.");
  } catch (e) { KEY = ""; say(e.message, true); }
});
$("verifyBtn").addEventListener("click", () => {
  const on = !(STATE && STATE.verify);
  if (confirm(on ? "Turn verification on? Runs from mods older than 0.72.x will be refused." : "Turn verification off? Runs from older mods will be taken again (unverified).")) act($("verifyBtn"), "verify", { on });
});
$("addBtn").addEventListener("click", async () => {
  const t = $("paste").value;
  const mod = (t.match(/^\\s*mod\\s+(\\S+)/im) || [])[1];
  const build = (t.match(/^\\s*build\\s+([0-9a-fA-F]{64})\\s*$/im) || [])[1];
  if (!mod || !build) { say("Paste the whole .buildhash.txt: it needs its mod line and its build line.", true); return; }
  const j = await act($("addBtn"), "builds/add", { mod, build, note: $("note").value });
  if (j) { $("paste").value = ""; $("note").value = ""; }
});
$("resetBtn").addEventListener("click", async () => {
  if ($("confirm").value.trim().toUpperCase() !== "RESET") { say("Type RESET in the box first.", true); return; }
  if (!confirm("Reset the whole leaderboard? Every run goes to the archive (Restore the last reset undoes it).")) return;
  const j = await act($("resetBtn"), "reset", { confirm: $("confirm").value });
  if (j) $("confirm").value = "";
});
$("undoBtn").addEventListener("click", () => {
  if (confirm("Put the runs of the last reset back on the boards?")) act($("undoBtn"), "restore");
});
</script>
</body></html>`;

const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

export default {
  async fetch(req, env, ctx) {
    const path = new URL(req.url).pathname;
    try {
      if (req.method === "POST" && path === "/submit") return await submit(req, env, ctx);
      if (req.method === "POST" && path === "/interactions") return await interactions(req, env, ctx);
      if (req.method === "GET" && path === "/setup") return await setup(req, env);
      if (req.method === "GET" && (path === "/admin" || path === "/admin/")) return adminPage();
      if (req.method === "POST" && path.startsWith("/admin/")) return await admin(req, env, path.slice("/admin/".length));
      if (req.method === "GET" && path === "/") return new Response("AC8 Survival Mode leaderboard");
      return new Response("not found", { status: 404 });
    } catch (e) {
      console.log(String(e && e.stack || e));
      return json({ ok: false, error: "server error" }, 500);
    }
  },
};

export { score, checkRun, boardEmbeds, extraEmbeds, weekStart, pilotEmbed, commandReply, commandFollowUp };      // (for tests)
