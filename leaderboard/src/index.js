// AC8 Survival Mode leaderboard: a Cloudflare Worker (README.md has the setup).
//
//   POST /submit        a finished run from the game (Survival's native runtime), signed with SUBMIT_KEY
//   POST /interactions  Discord's slash commands (/leaderboard, /pilot), signed by Discord
//   GET  /setup?key=..  after deploying: registers the slash commands and makes the leaderboard messages (two pinned:
//                       rounds / scores / specials, and records / aircraft / this week)
//
// Bindings (wrangler.toml / dashboard): DB (D1), and as variables / secrets DISCORD_TOKEN, DISCORD_PUBLIC_KEY,
// DISCORD_APP_ID, RUNS_CHANNEL_ID, BOARD_CHANNEL_ID, SUBMIT_KEY, ADMIN_KEY.
// Nothing here ever talks to Bandai Namco's services: only Discord's API and this Worker's own database.

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
const jet = (code) => (code ? AIRCRAFT[code] || code.toUpperCase() : null);
const RATE_PER_HOUR = 30;                     // runs one IP may submit in an hour (every ended run is sent, restarts too)
const API = "https://discord.com/api/v10";

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
  if (typeof run.mod !== "string" || !/^[0-9.]{1,16}$/.test(run.mod)) return "bad mod version";
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
  run.specials = sp.filter((s) => SPECIALS[s.kind]);
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
async function discord(env, method, path, json) {
  const r = await fetch(API + path, {
    method,
    headers: { Authorization: `Bot ${env.DISCORD_TOKEN}`, "Content-Type": "application/json" },
    body: json === undefined ? undefined : JSON.stringify(json),
  });
  if (!r.ok) throw new Error(`Discord ${method} ${path}: ${r.status} ${await r.text()}`);
  return r.status === 204 ? null : r.json();
}

const fmtTime = (s) => `${Math.floor(s / 3600) ? Math.floor(s / 3600) + "h " : ""}${Math.floor(s / 60) % 60}m ${s % 60}s`;
const num = (n) => n.toLocaleString("en-US");

function runEmbed(run, sc) {
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
    footer: { text: `${run.ended === "died" ? "Shot down" : run.how === "restart" ? "Restarted" : "Left the run"} · Survival Mode ${run.mod}` },
  };
}

// The boards, as embeds: highest round and score per difficulty (best run per pilot), fastest beaten specials.
// Pilots are grouped ignoring case (as /pilot finds them); every query goes to D1 in one batch.
async function boardEmbeds(env, onlyBoard, onlyDiff) {
  await ensureColumns(env);
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
  await ensureColumns(env);
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
  let pinned = true;
  try { await discord(env, "PUT", `/channels/${env.BOARD_CHANNEL_ID}/pins/${m.id}`); } catch (e) { pinned = false; }
  return { id: m.id, made: true, pinned };
}

async function refreshBoards(env) {
  const id = await setting(env, "board_message");
  if (!id) return;
  await discord(env, "PATCH", `/channels/${env.BOARD_CHANNEL_ID}/messages/${id}`,
    { content: "**AC8 Survival Mode — leaderboard** (updated after every run)", embeds: await boardEmbeds(env) });
  const two = await pinnedMessage(env, "board_message_2", "Records coming up...");
  await discord(env, "PATCH", `/channels/${env.BOARD_CHANNEL_ID}/messages/${two.id}`,
    { content: "**AC8 Survival Mode — records, aircraft and this week**", embeds: await extraEmbeds(env) });
  return two;
}

// Columns added after the first databases were made (aircraft; how / tier / aces / allies / af_down / captured from
// mod 0.50.0), added to an older database once per Worker instance.
const NEW_COLUMNS = { aircraft: "TEXT", how: "TEXT", tier: "TEXT", aces: "INTEGER", allies: "INTEGER", af_down: "INTEGER",
                      captured: "INTEGER" };
let haveColumns = false;
async function ensureColumns(env) {
  if (haveColumns) return;
  const { results } = await env.DB.prepare("PRAGMA table_info(runs)").all();
  const have = new Set(results.map((r) => r.name));
  for (const [col, type] of Object.entries(NEW_COLUMNS))
    if (!have.has(col)) await env.DB.prepare(`ALTER TABLE runs ADD COLUMN ${col} ${type}`).run();
  await env.DB.prepare("CREATE INDEX IF NOT EXISTS runs_week ON runs (submitted)").run();   // (this week's board)
  haveColumns = true;
}

// ------------------------------------------------------------------------------------------------- routes
async function submit(req, env) {
  const body = await req.text();
  if (body.length > 16384) return json({ ok: false, error: "too big" }, 413);
  const sig = (req.headers.get("X-SV-Signature") || "").toLowerCase();
  if (!sameText(sig, await hmacHex(env.SUBMIT_KEY, body))) return json({ ok: false, error: "bad signature" }, 401);
  let run;
  try { run = JSON.parse(body); } catch (e) { return json({ ok: false, error: "not JSON" }, 400); }
  const why = checkRun(run);
  if (why) return json({ ok: false, error: why }, 422);
  const ipHash = await sha256Hex((req.headers.get("CF-Connecting-IP") || "?") + env.SUBMIT_KEY);
  const now = Math.floor(Date.now() / 1000);
  if (await env.DB.prepare("SELECT 1 FROM runs WHERE run_id = ?").bind(run.run_id).first())
    return json({ ok: true, duplicate: true });                    // (the game may resend after a lost reply)
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM runs WHERE ip_hash = ? AND submitted > ?")
    .bind(ipHash, now - 3600).first();
  if (recent.n >= RATE_PER_HOUR) return json({ ok: false, error: "too many runs this hour, try later" }, 429);
  const sc = score(run);
  await ensureColumns(env);
  const opt = (v) => (v === undefined ? null : v);
  const batch = [env.DB.prepare(
    `INSERT INTO runs (run_id, pilot, difficulty, round, score, air_kills, ground_kills, earned, spent, time_s, ended,
     mod_version, submitted, ip_hash, aircraft, how, tier, aces, allies, af_down, captured)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(run.run_id, run.pilot, run.difficulty, run.round, sc, run.kills.air, run.kills.ground, run.zollars.earned,
          run.zollars.spent, run.time_s, run.ended, run.mod, now, ipHash, opt(run.aircraft), opt(run.how), opt(run.tier),
          opt(run.aces), opt(run.allies), opt(run.af_down), opt(run.captured))];
  for (const s of run.specials || [])
    batch.push(env.DB.prepare("INSERT INTO specials (run_id, kind, round, seconds, won, pilot, difficulty) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .bind(run.run_id, s.kind, s.round, s.seconds, s.won ? 1 : 0, run.pilot, run.difficulty));
  await env.DB.batch(batch);
  // the post and the boards: a Discord hiccup mustn't lose the run (it's stored), so their errors are only logged
  try { await discord(env, "POST", `/channels/${env.RUNS_CHANNEL_ID}/messages`, { embeds: [runEmbed(run, sc)] }); }
  catch (e) { console.log(String(e)); }
  try { await refreshBoards(env); } catch (e) { console.log(String(e)); }
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

async function interactions(req, env) {
  const body = await req.text();
  if (!(await discordSigned(req, body, env.DISCORD_PUBLIC_KEY))) return new Response("bad signature", { status: 401 });
  const it = JSON.parse(body);
  if (it.type === 1) return json({ type: 1 });                       // Discord's ping
  if (it.type === 2) {
    const opt = Object.fromEntries((it.data.options || []).map((o) => [o.name, o.value]));
    if (it.data.name === "leaderboard")
      return json({ type: 4, data: { embeds: EXTRA_BOARDS.includes(opt.board)
        ? await extraEmbeds(env, opt.board, opt.difficulty || null)
        : await boardEmbeds(env, opt.board || null, opt.difficulty || null) } });
    if (it.data.name === "pilot")
      return json({ type: 4, data: { embeds: [await pilotEmbed(env, String(opt.name || "").slice(0, 24))] } });
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
  const key = new URL(req.url).searchParams.get("key") || "";
  if (!env.ADMIN_KEY || !sameText(key, env.ADMIN_KEY)) return json({ ok: false, error: "bad key" }, 401);
  const done = [];
  await discord(env, "PUT", `/applications/${env.DISCORD_APP_ID}/commands`, COMMANDS);
  done.push("slash commands registered (they can take a minute to show)");
  if (!(await setting(env, "board_message"))) {
    const m = await discord(env, "POST", `/channels/${env.BOARD_CHANNEL_ID}/messages`, { content: "Leaderboard coming up..." });
    await env.DB.prepare("INSERT OR REPLACE INTO settings (key, value) VALUES ('board_message', ?)").bind(m.id).run();
    try { await discord(env, "PUT", `/channels/${env.BOARD_CHANNEL_ID}/pins/${m.id}`); done.push("leaderboard message made and pinned"); }
    catch (e) { done.push("leaderboard message made (pinning failed: give the bot Manage Messages)"); }
  }
  const two = await refreshBoards(env);
  if (two && two.made) done.push(`records message made${two.pinned ? " and pinned" : " (pinning failed: give the bot Manage Messages)"}`);
  done.push("leaderboard up to date");
  return json({ ok: true, done });
}

const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json" } });

export default {
  async fetch(req, env) {
    const path = new URL(req.url).pathname;
    try {
      if (req.method === "POST" && path === "/submit") return await submit(req, env);
      if (req.method === "POST" && path === "/interactions") return await interactions(req, env);
      if (req.method === "GET" && path === "/setup") return await setup(req, env);
      if (req.method === "GET" && path === "/") return new Response("AC8 Survival Mode leaderboard");
      return new Response("not found", { status: 404 });
    } catch (e) {
      console.log(String(e && e.stack || e));
      return json({ ok: false, error: "server error" }, 500);
    }
  },
};

export { score, checkRun, boardEmbeds, extraEmbeds, weekStart, pilotEmbed };      // (for tests)
