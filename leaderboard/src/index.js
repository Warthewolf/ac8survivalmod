// AC8 Survival Mode leaderboard: a Cloudflare Worker (README.md has the setup).
//
//   POST /submit        a finished run from the game (Survival's native runtime), signed with SUBMIT_KEY
//   POST /interactions  Discord's slash commands (/leaderboard, /pilot), signed by Discord
//   GET  /setup?key=..  once, after deploying: registers the slash commands and makes the leaderboard messages
//
// Bindings (wrangler.toml / dashboard): DB (D1), and as variables / secrets DISCORD_TOKEN, DISCORD_PUBLIC_KEY,
// DISCORD_APP_ID, RUNS_CHANNEL_ID, BOARD_CHANNEL_ID, SUBMIT_KEY, ADMIN_KEY.
// Nothing here ever talks to Bandai Namco's services: only Discord's API and this Worker's own database.

const DIFFICULTIES = ["casual", "standard", "ace"];
const DIFF_NAME = { casual: "Casual", standard: "Standard", ace: "Ace" };
const DIFF_X = { casual: 0.75, standard: 1.0, ace: 1.5 };        // score multiplier
const SPECIALS = { shuttle: "Comona Defense", anomaly: "The Anomaly", amphibious: "Amphibious Assault",
                   ladon: "The Ladons", alicorn: "The Alicorn" };
const RATE_PER_HOUR = 6;                                            // runs one sender may submit in an hour
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
  const sp = run.specials || [];
  if (!Array.isArray(sp) || sp.length > run.round) return "too many specials";
  for (const s of sp) {
    if (!SPECIALS[s.kind] || !isInt(s.round, 1, run.round) || !isInt(s.seconds, 5, 3600) || typeof s.won !== "boolean")
      return "bad special";
  }
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
      { name: "Specials beaten", value: won.length ? won.map((s) => `${SPECIALS[s.kind]} (round ${s.round}, ${fmtTime(s.seconds)})`).join("\n") : "none" },
    ],
    footer: { text: `${run.ended === "died" ? "Shot down" : "Left the run"} · Survival Mode ${run.mod}` },
  };
}

// The boards, as embeds: highest round and score per difficulty (best run per pilot), fastest beaten specials.
async function boardEmbeds(env, onlyBoard, onlyDiff) {
  const out = [];
  const diffs = onlyDiff ? [onlyDiff] : DIFFICULTIES;
  for (const [board, col, title] of [["round", "round", "Highest round"], ["score", "score", "Score"]]) {
    if (onlyBoard && onlyBoard !== board) continue;
    const fields = [];
    for (const d of diffs) {
      const { results } = await env.DB.prepare(
        `SELECT pilot, MAX(${col}) AS best, MAX(round) AS round, MAX(score) AS score FROM runs WHERE difficulty = ?
         GROUP BY pilot ORDER BY best DESC LIMIT 10`).bind(d).all();
      fields.push({ name: DIFF_NAME[d], value: results.length
        ? results.map((r, i) => `${i + 1}. **${r.pilot}** — ${board === "round" ? `round ${r.best}` : num(r.best)}`).join("\n")
        : "no runs yet", inline: true });
    }
    out.push({ title: `${title} — top 10`, color: 0xd4ac0d, fields });
  }
  if (!onlyBoard || onlyBoard === "specials") {
    const fields = [];
    for (const [kind, name] of Object.entries(SPECIALS)) {
      const { results } = await env.DB.prepare(
        `SELECT pilot, MIN(seconds) AS best, difficulty FROM specials WHERE kind = ? AND won = 1 ${onlyDiff ? "AND difficulty = ?" : ""}
         GROUP BY pilot ORDER BY best ASC LIMIT 5`).bind(...(onlyDiff ? [kind, onlyDiff] : [kind])).all();
      fields.push({ name, value: results.length
        ? results.map((r, i) => `${i + 1}. **${r.pilot}** — ${fmtTime(r.best)} (${DIFF_NAME[r.difficulty]})`).join("\n")
        : "not beaten yet", inline: true });
    }
    out.push({ title: "Fastest specials — top 5", color: 0x8e44ad, fields });
  }
  return out;
}

async function setting(env, key) {
  const r = await env.DB.prepare("SELECT value FROM settings WHERE key = ?").bind(key).first();
  return r ? r.value : null;
}

// The pinned leaderboard message in BOARD_CHANNEL_ID: edited after every run (made and pinned by /setup)
async function refreshBoards(env) {
  const id = await setting(env, "board_message");
  if (!id) return;
  await discord(env, "PATCH", `/channels/${env.BOARD_CHANNEL_ID}/messages/${id}`,
    { content: "**AC8 Survival Mode — leaderboard** (updated after every run)", embeds: await boardEmbeds(env) });
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
  const batch = [env.DB.prepare(
    `INSERT INTO runs (run_id, pilot, difficulty, round, score, air_kills, ground_kills, earned, spent, time_s, ended,
     mod_version, submitted, ip_hash) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(run.run_id, run.pilot, run.difficulty, run.round, sc, run.kills.air, run.kills.ground, run.zollars.earned,
          run.zollars.spent, run.time_s, run.ended, run.mod, now, ipHash)];
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
  return {
    title: `${name} — Survival Mode`,
    color: 0x2e86c1,
    fields: [
      ...runs.results.map((r) => ({ name: DIFF_NAME[r.difficulty],
        value: `best round ${r.round}\nbest score ${num(r.score)}\n${r.n} run${r.n === 1 ? "" : "s"}`, inline: true })),
      { name: "Fastest specials", value: sp.results.length ? sp.results.map((s) => `${SPECIALS[s.kind]}: ${fmtTime(s.best)}`).join("\n") : "none beaten yet" },
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
      return json({ type: 4, data: { embeds: await boardEmbeds(env, opt.board || null, opt.difficulty || null) } });
    if (it.data.name === "pilot")
      return json({ type: 4, data: { embeds: [await pilotEmbed(env, String(opt.name || "").slice(0, 24))] } });
  }
  return json({ type: 4, data: { content: "Unknown command." } });
}

const COMMANDS = [
  { name: "leaderboard", description: "AC8 Survival Mode leaderboards", options: [
    { type: 3, name: "board", description: "Which board", required: false,
      choices: [{ name: "Highest round", value: "round" }, { name: "Score", value: "score" }, { name: "Fastest specials", value: "specials" }] },
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
  await refreshBoards(env);
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

export { score, checkRun };      // (for tests)
