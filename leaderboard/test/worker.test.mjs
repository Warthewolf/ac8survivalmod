// Local test of the Worker: node test/worker.test.mjs (Node 22+; D1 stood in for by node:sqlite, Discord by a stub)
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { createHmac } from "node:crypto";
import worker, { score, checkRun, boardEmbeds, extraEmbeds, weekStart, pilotEmbed, commandReply, commandFollowUp,
                 coopEmbeds, squadText, COMMANDS } from "../src/index.js";

const db = new DatabaseSync(":memory:");
// (the oldest database: schema_console.sql's runs, specials and settings only, as the first deploys made it; the Worker
// adds the newer columns and tables itself. Both schema files are run on databases of their own below.)
const consoleSql = readFileSync(new URL("../schema_console.sql", import.meta.url), "utf8");
db.exec(consoleSql.split("\n").filter((l) => /\b(runs|specials|settings)\b/.test(l)).join("\n"));
const fresh = new DatabaseSync(":memory:");
fresh.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
new DatabaseSync(":memory:").exec(consoleSql);
const stmt = (sql, args = []) => ({
  sql,
  bind: (...a) => stmt(sql, a),
  all: async () => ({ results: db.prepare(sql).all(...args) }),
  first: async () => db.prepare(sql).get(...args) ?? null,
  run: async () => db.prepare(sql).run(...args),
});
// (D1's batch: each statement's result in order; SELECTs give their rows)
const DB = { prepare: (sql) => stmt(sql), batch: async (list) => {
  const out = [];
  for (const s of list) out.push(s.sql.trimStart().startsWith("SELECT") ? await s.all() : await s.run());
  return out;
} };
const env = { DB, SUBMIT_KEY: "test-key", ADMIN_KEY: "admin", DISCORD_TOKEN: "t", DISCORD_APP_ID: "1",
              RUNS_CHANNEL_ID: "100", BOARD_CHANNEL_ID: "200", DISCORD_PUBLIC_KEY: "00" };
const calls = [], posted = [];
globalThis.fetch = async (url, init) => {
  calls.push(`${init.method} ${url.replace("https://discord.com/api/v10", "")}`);
  if (init.method === "POST") posted.push(init.body);
  return new Response(init.method === "POST" ? JSON.stringify({ id: "999" }) : "{}", { status: 200 });
};

let fails = 0;
const check = (what, ok) => { console.log(`${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) fails++; };
const hmac = (text) => createHmac("sha256", env.SUBMIT_KEY).update(text).digest("hex");
const post = (body, sig, ip = "1.2.3.4") => worker.fetch(new Request("https://x/submit", { method: "POST", body,
  headers: { "X-SV-Signature": sig ?? hmac(body), "CF-Connecting-IP": ip } }), env);
// a 0.72.x run: the build's hash in X-SV-Build, the signature over "<build>\n<body>"
const postBuilt = (body, build, ip, sig) => worker.fetch(new Request("https://x/submit", { method: "POST", body,
  headers: { "X-SV-Build": build, "X-SV-Signature": sig ?? hmac(`${build}\n${body}`), "CF-Connecting-IP": ip } }), env);
const adminCall = async (action, body, ip = "9.9.9.9") => {
  const r = await worker.fetch(new Request(`https://x/admin/${action}`, { method: "POST", body: JSON.stringify(body),
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip } }), env);
  return { status: r.status, j: await r.json() };
};
const count = (sql) => db.prepare(sql).get().n;

const run = { v: 1, run_id: "0123456789abcdef0123", pilot: "Naish", difficulty: "ace", round: 12, mod: "0.47.0", aircraft: "su57",
  kills: { air: 140, ground: 12 }, zollars: { earned: 40000, spent: 30000 }, time_s: 2400, ended: "died",
  specials: [{ kind: "ladon", round: 7, seconds: 212, won: true }, { kind: "amphibious", round: 10, seconds: 300, won: false }] };

check("score: (12000 + 14000 + 600 + 3000) x 1.5 = 44400", score(run) === 44400);
check("a sane run passes", checkRun(run) === null);
{ const newer = { ...run, specials: [...run.specials, { kind: "wormhole", round: 11, seconds: 90, won: true }] };
  check("a special this Worker doesn't know is left out, not the run", checkRun(newer) === null && newer.specials.length === 2); }
check("a bad special kind is refused", checkRun({ ...run, specials: [{ kind: "<x>", round: 3, seconds: 90, won: true }] }) !== null);
check("too many kills is refused", checkRun({ ...run, kills: { air: 9999, ground: 0 } }) !== null);
check("a too-short run is refused", checkRun({ ...run, time_s: 10 }) !== null);
check("a bad pilot name is refused", checkRun({ ...run, pilot: "<script>" }) !== null);
// mod 0.50.0's fields (optional: the run above, from an older mod, has none)
const more = { how: "restart", tier: "Elite", aces: 3, allies: 1, af_down: 2, captured: 1 };
check("a run with 0.50.0's fields passes", checkRun({ ...run, ...more }) === null);
check("more ace kills than air kills is refused", checkRun({ ...run, ...more, aces: 141 }) !== null);
check("a bad ending is refused", checkRun({ ...run, ...more, how: "won" }) !== null);
check("a bad tier is refused", checkRun({ ...run, ...more, tier: "<i>" }) !== null);
check("weekStart is a Monday 00:00 UTC", new Date(weekStart(Date.UTC(2026, 9, 23, 15) / 1000) * 1000).toISOString() === "2026-10-19T00:00:00.000Z");

let r = await post(JSON.stringify(run));
let j = await r.json();
check(`submit: ${r.status} ${JSON.stringify(j)}`, r.status === 200 && j.ok && j.score === 44400);
check("the run was posted", calls.some((c) => c === "POST /channels/100/messages"));
r = await post(JSON.stringify(run));
j = await r.json();
check("the same run again is a duplicate", j.duplicate === true);
r = await post(JSON.stringify({ ...run, run_id: "aaaaaaaaaaaaaaaa1" }), "00");
check("a bad signature is refused", r.status === 401);
for (let i = 0; i < 30; i++)
  await post(JSON.stringify({ ...run, ...more, run_id: `bbbbbbbbbbbbbbbb${i}`, aces: i, aircraft: i % 2 ? "f22a" : "su57",
                              round: 12 + (i % 5), time_s: 2400 + i * 10 }));
r = await post(JSON.stringify({ ...run, run_id: "cccccccccccccccc" }));
check("the 31st run within the hour is refused", r.status === 429);
r = await worker.fetch(new Request("https://x/setup?key=admin"), env);
j = await r.json();
check(`setup: ${JSON.stringify(j.done)}`, j.ok && calls.includes("PUT /applications/1/commands"));
check("both pinned messages were edited", calls.filter((c) => c === "PATCH /channels/200/messages/999").length >= 2);
check("the third (CO-OP) pinned message was made and pinned", j.done.some((d) => d === "co-op message made and pinned")
  && db.prepare("SELECT value FROM settings WHERE key = 'board_message_3'").get()
  && calls.filter((c) => c === "PATCH /channels/200/messages/999").length >= 3);
calls.length = 0;
await post(JSON.stringify({ ...run, run_id: "dddddddddddddddd", pilot: "Other" }), undefined);   // (rate limited: same IP)
const rows = db.prepare("SELECT COUNT(*) AS n FROM runs").get().n;
check(`runs stored: ${rows}`, rows === 30);
const sp = db.prepare("SELECT COUNT(*) AS n FROM specials WHERE won = 1").get().n;
check(`beaten specials stored: ${sp}`, sp === 30);
db.prepare(`INSERT INTO runs (run_id, pilot, difficulty, round, score, air_kills, ground_kills, earned, spent, time_s, ended,
  mod_version, submitted, ip_hash, aircraft) VALUES ('lower1', 'naish', 'ace', 50, 99999, 0, 0, 0, 0, 999, 'died', 'x', 0, 'h', 'f22a')`).run();
const e = await boardEmbeds(env);
const ace = e[0].fields.find((f) => f.name.toLowerCase().includes("ace")).value;
check(`'Naish' and 'naish' are one pilot on the boards: ${JSON.stringify(ace)}`, ace.split("\n").length === 1 && ace.includes("round 50"));
check(`the boards: ${e.length} embeds (round, score, specials: ${e[2] && e[2].fields.length} of them)`, e.length === 3 && e[2].fields.length === 8);   // (the Spaceport Assault and Retake since 0.73.38)
const x = await extraEmbeds(env, null, null, Math.floor(Date.now() / 1000));
check(`the second message: ${x.map((m) => m.title.split(" —")[0]).join(", ")}`, x.length === 3 && x[0].fields.length === 5);
check(`records: most ace squadron kills ${JSON.stringify(x[0].fields[3].value)}`, x[0].fields[3].value.includes("— 28 "));   // (the 30th of these was rate limited)
check(`records: most specials beaten ${JSON.stringify(x[0].fields[4].value)}`, x[0].fields[4].value.includes("— 1 "));
check(`per aircraft: ${JSON.stringify(x[1].description)}`, x[1].description.includes("F-22A Raptor") && x[1].description.includes("Su-57 Felon")
  && x[1].description.split("\n")[0].includes("round 50"));
check(`this week: ${JSON.stringify(x[2].fields[0].value)}`, x[2].fields[0].value.includes("round 16") && !x[2].fields[0].value.includes("round 50"));
const newRow = db.prepare("SELECT how, tier, aces, allies, af_down, captured FROM runs WHERE run_id = 'bbbbbbbbbbbbbbbb5'").get();
check(`0.50.0's fields stored: ${JSON.stringify(newRow)}`, newRow.how === "restart" && newRow.tier === "Elite" && newRow.aces === 5
  && newRow.allies === 1 && newRow.af_down === 2 && newRow.captured === 1);
const pe = await pilotEmbed(env, "naish");
const totals = pe.fields.find((f) => f.name === "Totals");
check(`/pilot totals: ${JSON.stringify(totals && totals.value)}`, totals && totals.value.startsWith("31 runs") && totals.value.includes("ace squadron")
  && totals.value.includes("most flown"));
const jetRow = db.prepare("SELECT aircraft FROM runs WHERE run_id = '0123456789abcdef0123'").get();
check(`aircraft stored: ${jetRow && jetRow.aircraft}`, jetRow && jetRow.aircraft === "su57");
check("a bad aircraft code is refused", checkRun({ ...run, aircraft: "<b>" }) !== null);
{ // (security review of 2026-10-26: names of Object's own members are no aircraft or special)
  const r = { ...run, aircraft: "constructor", specials: [{ kind: "constructor", round: 1, seconds: 30, won: true }] };
  check("a special named constructor is left out", checkRun(r) === null && r.specials.length === 0);
}

// ---------------------------------------------------------------------------------------------- the database's upgrade
{
  const cols = (d, t) => d.prepare(`PRAGMA table_info(${t})`).all().map((c) => c.name).sort().join(",");
  for (const t of ["runs", "runs_archive", "specials", "specials_archive", "squads", "squads_archive", "builds", "builds_seen",
                   "resets", "admin_fails"])
    check(`the oldest database upgraded: ${t} as schema.sql has it`, cols(db, t) !== "" && cols(db, t) === cols(fresh, t));
}

// ---------------------------------------------------------------------------------------------- the co-op version
check("a co-op build's version is taken (0.72.2-coop.20)", checkRun({ ...run, mod: "0.72.2-coop.20" }) === null);
check("Stable 1's co-op version is taken (0.71.5-coop.17)", checkRun({ ...run, mod: "0.71.5-coop.17" }) === null);
check("a COOP2MP build's version is taken (0.73.73-coop2mp.74)", checkRun({ ...run, mod: "0.73.73-coop2mp.74" }) === null);
check("a plain version still is (0.72.2)", checkRun({ ...run, mod: "0.72.2" }) === null);
for (const bad of ["0.72.2-coop", "0.72.2-beta.1", "0.72.2-coop.12345", "<b>", "0.72.2 -coop.1"])
  check(`a bad version is refused (${bad})`, checkRun({ ...run, mod: bad }) === "bad mod version");
r = await post(JSON.stringify({ ...run, run_id: "c00b0000000000000001", mod: "0.72.1-coop.19" }), undefined, "2.0.0.1");
j = await r.json();
check(`a co-op build's run is stored: ${r.status} ${JSON.stringify(j)}`, r.status === 200 && j.ok
  && db.prepare("SELECT mod_version FROM runs WHERE run_id = 'c00b0000000000000001'").get().mod_version === "0.72.1-coop.19");
check("an older mod's run (no build hash) is marked unverified",
  db.prepare("SELECT verified, build FROM runs WHERE run_id = 'c00b0000000000000001'").get().verified === 0);
check("its post says the build wasn't checked", posted.some((b) => b.includes("build not checked")));

// ---------------------------------------------------------------------------------------------- the admin page
{
  const page = await worker.fetch(new Request("https://x/admin"), env);
  const html = await page.text();
  const csp = page.headers.get("Content-Security-Policy") || "";
  const nonce = (csp.match(/'nonce-([0-9a-f]+)'/) || [])[1];
  check("GET /admin: a page", page.status === 200 && html.startsWith("<!doctype html>") && html.includes('type="password"'));
  check("its script and style carry the CSP's nonce, nothing loads from elsewhere", nonce && html.includes(`<script nonce="${nonce}">`)
    && html.includes(`<style nonce="${nonce}">`) && !/<script[^>]+src=|<link |@import|https?:\/\//.test(html)
    && csp.includes("default-src 'none'") && csp.includes("connect-src 'self'"));
  check("the key goes in the body: no key in any address on the page", !/[?&]key=/.test(html) && html.includes("key: KEY"));
  check("no caching, no framing", page.headers.get("Cache-Control") === "no-store" && page.headers.get("X-Frame-Options") === "DENY");
  // the page's own script parses
  const script = html.slice(html.indexOf(`<script nonce="${nonce}">`) + `<script nonce="${nonce}">`.length, html.lastIndexOf("</script>"));
  let parses = true;
  try { new Function(script); } catch (e) { parses = false; console.log(String(e)); }
  check("the page's script parses", parses);
  const t = "mod 0.72.2-coop.20\nbuild " + "Ab".repeat(32) + "\nzip x.zip\n";
  check("its .buildhash.txt parse (the page's regexes)", /^\s*mod\s+(\S+)/im.exec(t)[1] === "0.72.2-coop.20"
    && /^\s*build\s+([0-9a-fA-F]{64})\s*$/im.exec(t)[1] === "Ab".repeat(32) && script.includes("/^\\s*mod\\s+(\\S+)/im"));
}
let a = await adminCall("status", { key: "wrong" }, "5.5.5.5");
check(`a wrong key is refused: ${a.status} ${a.j.error}`, a.status === 401 && !a.j.ok && a.j.status === undefined);
a = await adminCall("reset", { key: "nope", confirm: "RESET" }, "5.5.5.5");
const stored = count("SELECT COUNT(*) AS n FROM runs");
check(`a wrong key resets nothing (${stored} runs)`, a.status === 401 && stored === 32);
for (let i = 0; i < 3; i++) await adminCall("status", { key: "x" + i }, "5.5.5.5");
a = await adminCall("status", { key: "y" }, "5.5.5.5");
check(`the 6th wrong key from one address: locked out (${a.status} ${a.j.error})`, a.status === 429);
a = await adminCall("status", { key: env.ADMIN_KEY }, "5.5.5.5");
check("locked out even with the right key, for 15 minutes", a.status === 429);
r = await worker.fetch(new Request("https://x/setup?key=admin", { headers: { "CF-Connecting-IP": "5.5.5.5" } }), env);
check("/setup from that address too", r.status === 429);
a = await adminCall("status", { key: env.ADMIN_KEY });
check(`the right key from another address: status (${a.j.status && a.j.status.runs} runs)`, a.status === 200 && a.j.ok
  && a.j.status.runs === stored && a.j.status.verify === false && a.j.status.undo === null);
a = await adminCall("status", { key: env.ADMIN_KEY + "x" });
check("a key one character longer is wrong", a.status === 401);
a = await adminCall("frobnicate", { key: env.ADMIN_KEY });
check("an unknown action", a.status === 404);
r = await worker.fetch(new Request("https://x/admin/status", { method: "POST", body: "key=admin", headers: { "CF-Connecting-IP": "9.9.9.9" } }), env);
check("a body that isn't JSON", r.status === 400);

// ---------------------------------------------------------------------------------------------- builds
const BUILD = "b".repeat(64), OTHER = "c".repeat(64), MOD = "0.72.2-coop.20";
a = await adminCall("builds/add", { key: env.ADMIN_KEY, mod: MOD, build: "xyz" });
check("a build hash that isn't 64 hex characters is refused", a.status === 400);
a = await adminCall("builds/add", { key: env.ADMIN_KEY, mod: "0.72.2-beta", build: BUILD });
check("a version the game doesn't send is refused", a.status === 400);
a = await adminCall("builds/add", { key: env.ADMIN_KEY, mod: MOD, build: BUILD.toUpperCase(), note: "COOP NoValka zip\u0007" });
check(`a build registered: ${a.j.done}`, a.j.ok && a.j.status.builds.length === 1 && a.j.status.builds[0].build === BUILD
  && a.j.status.builds[0].note === "COOP NoValka zip");
const built = (id, extra = {}) => JSON.stringify({ ...run, run_id: id, mod: MOD, build: BUILD, edited: [], ...extra });
r = await postBuilt(built("b1000000000000000001"), BUILD, "3.0.0.1");
j = await r.json();
check(`a run from the registered build: ${r.status} ${JSON.stringify(j)}`, r.status === 200 && j.ok);
{ const row = db.prepare("SELECT build, verified FROM runs WHERE run_id = 'b1000000000000000001'").get();
  check("stored with its build, verified", row.build === BUILD && row.verified === 1); }
r = await postBuilt(built("b1000000000000000002"), BUILD, "3.0.0.1", hmac(built("b1000000000000000002")));
check("X-SV-Build signed the old way (the body alone): bad signature", r.status === 401);
r = await postBuilt(built("b1000000000000000003"), OTHER, "3.0.0.1", hmac(`${BUILD}\n${built("b1000000000000000003")}`));
check("another build's hash under a signature made for this one: bad signature", r.status === 401);
r = await postBuilt(built("b1000000000000000004", { build: OTHER }), OTHER, "3.0.0.1");
j = await r.json();
check(`an unknown build: refused (${j.error})`, r.status === 422 && j.error === "edited or unknown build"
  && !db.prepare("SELECT 1 FROM runs WHERE run_id = 'b1000000000000000004'").get());
r = await postBuilt(built("b1000000000000000005", { build: OTHER }), OTHER, "3.0.0.2");
a = await adminCall("status", { key: env.ADMIN_KEY });
check(`builds seen but not registered: ${JSON.stringify(a.j.status.seen.map((s) => [s.build.slice(0, 4), s.n]))}`,
  a.j.status.seen.length === 1 && a.j.status.seen[0].build === OTHER && a.j.status.seen[0].n === 2 && a.j.status.seen[0].pilot === "Naish");
r = await postBuilt(built("b1000000000000000006", { mod: "0.72.1-coop.19" }), BUILD, "3.0.0.3");
check("the right hash under another version: unknown build", r.status === 422);
r = await postBuilt(built("b1000000000000000007", { build: OTHER }), BUILD, "3.0.0.3");
j = await r.json();
check(`a run the game started on other files than it sends from: refused (${j.error})`, r.status === 422 && j.error === "played on other files");
r = await postBuilt(built("b1000000000000000008", { edited: ["specials.chance", "tells.enabled"] }), BUILD, "3.0.0.3");
j = await r.json();
check(`a run that says it was edited: refused (${j.error})`, r.status === 422 && j.error === "edited run (specials.chance)");
check("a bad edited list is refused", checkRun({ ...run, edited: "x" }) === "bad edited list" && checkRun({ ...run, edited: [1] }) === "bad edited list");
r = await postBuilt(built("b1000000000000000009"), "not-a-hash", "3.0.0.3");
check("a header that isn't a hash", r.status === 400);

// ---------------------------------------------------------------------------------------------- verification
a = await adminCall("verify", { key: env.ADMIN_KEY, on: "yes" });
check("verify needs true or false", a.status === 400);
a = await adminCall("verify", { key: env.ADMIN_KEY, on: true });
check(`verification on: ${a.j.done}`, a.j.ok && a.j.status.verify === true);
r = await post(JSON.stringify({ ...run, run_id: "d0000000000000000001", mod: "0.72.1-coop.19" }), undefined, "4.0.0.1");
j = await r.json();
check(`verification on: an older mod's run is refused (${j.error})`, r.status === 422 && j.error.startsWith("no build check"));
r = await postBuilt(built("b1000000000000000010"), BUILD, "4.0.0.1");
check("verification on: the registered build's run is taken", r.status === 200);
a = await adminCall("verify", { key: env.ADMIN_KEY, on: false });
r = await post(JSON.stringify({ ...run, run_id: "d0000000000000000002" }), undefined, "4.0.0.1");
check("verification off again: an older mod's run is taken", r.status === 200 && a.j.status.verify === false);
a = await adminCall("builds/remove", { key: env.ADMIN_KEY, mod: MOD, build: BUILD });
check(`a build removed: ${a.j.done}`, a.j.ok && a.j.status.builds.length === 0);
r = await postBuilt(built("b1000000000000000011"), BUILD, "4.0.0.1");
check("its runs are refused from then on", r.status === 422);
a = await adminCall("builds/remove", { key: env.ADMIN_KEY, mod: MOD, build: BUILD });
check("removing it again: no such build", a.status === 404);
await adminCall("builds/add", { key: env.ADMIN_KEY, mod: MOD, build: BUILD });

// ---------------------------------------------------------------------------------------------- co-op runs (Workstream H)
// The host sends one record for the room: kills the squad's sums, "coop": {players, squad: [{pilot, aircraft, air, ground,
// revives, host}, ...]}, host first.
const C2 = "0.73.76-coop2mp.77", C2B = "d".repeat(64);
check("a COOP2MP version is taken (0.73.76-coop2mp.77)", checkRun({ ...run, mod: C2 }) === null);
check("the release's version is taken (1.0.0)", checkRun({ ...run, mod: "1.0.0" }) === null);
a = await adminCall("builds/add", { key: env.ADMIN_KEY, mod: C2, build: C2B, note: "COOP2MP zip" });
check(`a COOP2MP build registered: ${a.j.done}`, a.j.ok);
const sq = (pilot, aircraft, air, ground, revives, host) =>
  ({ pilot, ...(aircraft ? { aircraft } : {}), air, ground, revives, ...(host === undefined ? {} : { host }) });
const team = (id, extra = {}) => ({ ...run, run_id: id, mod: C2, build: C2B, edited: [], pilot: "Naish", difficulty: "ace",
  round: 60, time_s: 7200, aircraft: "su57", kills: { air: 400, ground: 60 }, aces: 20, allies: 30, how: "died", tier: "Reaper",
  specials: [{ kind: "ladon", round: 10, seconds: 200, won: true }, { kind: "alicorn", round: 20, seconds: 400, won: true },
             { kind: "glitch", round: 30, seconds: 90, won: true }],
  coop: { players: 4, squad: [sq("Naish", "su57", 150, 20, 1, true), sq("xX_spagooterpoop_Xx", "fa36", 100, 15, 3),
                              sq("Kalash", "f22a", 90, 15, 0, false), sq("dukka", null, 60, 10, 2)] }, ...extra });
{
  const t = team("cc000000000000000000");
  check("a team run passes", checkRun(t) === null && t.coop.squad.length === 4 && t.coop.squad[3].host === false
    && t.coop.squad[3].aircraft === null);
  check("its score: the solo formula on the squad's totals ((60000 + 40000 + 3000 + 9000) x 1.5)", score(t) === 168000);
  check("the host's name in another case is the same pilot", checkRun(team("cc000000000000000000", { pilot: "NAISH" })) === null);
  const nr = team("cc000000000000000000"); delete nr.coop.squad[2].revives;
  check("revives left out are 0", checkRun(nr) === null && nr.coop.squad[2].revives === 0);
  const solo = { ...run, coop: null };
  check("\"coop\": null is a solo run", checkRun(solo) === null && solo.coop === undefined);
}
// the limits scale with the players (a squad of n, kills split between them, the host first)
const small = (air, ground, n, id = "cc000000000000000001") => team(id, { round: 5, time_s: 600, aces: 0, allies: 0, specials: [],
  kills: { air, ground }, coop: { players: n, squad: Array.from({ length: n }, (_, i) => sq(i ? `Wing ${i}` : "Naish", null,
    Math.floor(air / n) + (i ? 0 : air % n), Math.floor(ground / n) + (i ? 0 : ground % n), 0, i === 0)) } });
check("2 players: 700 air kills in 5 rounds pass (5 x 70 x 2)", checkRun(small(700, 0, 2)) === null);
check("2 players: 701 are too many for its players", checkRun(small(701, 0, 2)) === "too many air kills for the rounds and players");
check("3 players: 701 pass", checkRun(small(701, 0, 3)) === null);
check("2 players: 601 ground kills in 5 rounds are too many ((5 x 40 + 100) x 2)",
  checkRun(small(0, 601, 2)) === "too many ground kills for the rounds and players");
check("2 players: 100 allies in 5 rounds pass (5 x 10 x 2)", checkRun({ ...small(10, 0, 2), allies: 100 }) === null);
check("solo: unchanged, 351 air kills in 5 rounds are too many",
  checkRun({ ...run, round: 5, time_s: 600, specials: [], kills: { air: 351, ground: 0 } }) === "too many air kills for the rounds");
check("solo: 51 allies in 5 rounds are too many", checkRun({ ...run, round: 5, time_s: 600, specials: [], allies: 51 }) === "bad allies");
// mismatched squads
const bad = (what, mut, want) => {
  const t = team("cc000000000000000002");
  mut(t);
  const why = checkRun(t);
  check(`${what}: refused (${why})`, why === want);
};
bad("the squad's air kills don't add up", (t) => { t.coop.squad[3].air = 59; }, "squad's kills don't add up to the run's");
bad("the squad's ground kills don't add up", (t) => { t.kills.ground = 61; }, "squad's kills don't add up to the run's");
bad("a squad shorter than its players", (t) => { t.coop.squad.pop(); }, "squad doesn't match its players");
bad("a squad longer than its players", (t) => { t.coop.players = 3; }, "squad doesn't match its players");
bad("a squad that isn't a list", (t) => { t.coop.squad = "Naish"; }, "squad doesn't match its players");
bad("one player is no squad", (t) => { t.coop.players = 1; t.coop.squad = [t.coop.squad[0]]; }, "bad co-op players");
bad("25 players", (t) => { t.coop.players = 25; }, "bad co-op players");
bad("a co-op block that isn't an object", (t) => { t.coop = [4]; }, "bad co-op players");
bad("the same pilot twice (in another case)", (t) => { t.coop.squad[1].pilot = "kalash"; }, "squad pilot named twice");
bad("a bad name in the squad", (t) => { t.coop.squad[1].pilot = "<script>"; }, "bad squad pilot name");
bad("an empty name in the squad", (t) => { t.coop.squad[1].pilot = ""; }, "bad squad pilot name");
bad("a 25-character name in the squad", (t) => { t.coop.squad[1].pilot = "x".repeat(25); }, "bad squad pilot name");
bad("a name left out", (t) => { delete t.coop.squad[1].pilot; }, "bad squad pilot name");
bad("a squad entry that isn't an object", (t) => { t.coop.squad[3] = "dukka"; }, "bad squad entry");
bad("a bad aircraft code in the squad", (t) => { t.coop.squad[1].aircraft = "<b>"; }, "bad squad aircraft");
bad("negative kills in the squad", (t) => { t.coop.squad[1].air = -1; t.coop.squad[0].air = 251; }, "bad squad kills");
bad("kills that aren't whole numbers", (t) => { t.coop.squad[1].air = 99.5; t.coop.squad[0].air = 150.5; }, "bad squad kills");
bad("too many revives for one player (60 x 4 x 2)", (t) => { t.coop.squad[1].revives = 481; }, "bad squad revives");
bad("too many revives for the squad", (t) => { t.coop.squad[1].revives = 300; t.coop.squad[3].revives = 300; },
  "too many revives for the rounds and players");
bad("the host not first", (t) => { t.coop.squad[0].host = false; t.coop.squad[1].host = true; }, "squad's host isn't first");
bad("no host", (t) => { delete t.coop.squad[0].host; }, "squad's host isn't first");
bad("two hosts", (t) => { t.coop.squad[2].host = true; }, "squad's host isn't first");
bad("a host flag that isn't true or false", (t) => { t.coop.squad[1].host = 1; }, "bad squad host");
bad("a host that isn't the run's pilot", (t) => { t.pilot = "Kalash2"; }, "squad's host isn't the run's pilot");
// over HTTP: taken, refused, duplicates
{
  const sumBefore = db.prepare("SELECT value FROM settings WHERE key = 'board_message_3_sum'").get();
  posted.length = 0;
  r = await postBuilt(JSON.stringify(team("cc000000000000000010")), C2B, "7.0.0.1");
  j = await r.json();
  check(`a team run taken: ${r.status} ${JSON.stringify(j)}`, r.status === 200 && j.ok && j.score === 168000);
  const row = db.prepare("SELECT pilot, players, squad, crew, air_kills, ground_kills, earned, score, verified FROM runs WHERE run_id = 'cc000000000000000010'").get();
  check(`stored as one run with its squad: ${JSON.stringify(row)}`, row && row.pilot === "Naish" && row.players === 4
    && row.squad === "Naish,xX_spagooterpoop_Xx,Kalash,dukka" && row.crew === "dukka,kalash,naish,xx_spagooterpoop_xx"
    && row.air_kills === 400 && row.ground_kills === 60 && row.earned === 40000 && row.score === 168000 && row.verified === 1);
  const sqRows = db.prepare("SELECT slot, pilot, aircraft, air_kills, ground_kills, revives, host FROM squads WHERE run_id = 'cc000000000000000010' ORDER BY slot").all();
  check(`its squad's rows: ${sqRows.map((p) => `${p.slot}:${p.pilot}:${p.aircraft}:${p.air_kills}/${p.ground_kills}:${p.revives}:${p.host}`).join(" ")}`,
    sqRows.length === 4 && sqRows[0].host === 1 && sqRows.slice(1).every((p) => p.host === 0) && sqRows[3].aircraft === null
    && sqRows[1].pilot === "xX_spagooterpoop_Xx" && sqRows[1].revives === 3);
  check("its specials marked with its size", db.prepare("SELECT COUNT(*) AS n FROM specials WHERE run_id = 'cc000000000000000010' AND players = 4").get().n === 3);
  const m = posted.map((b) => JSON.parse(b)).find((p) => p.embeds && p.embeds[0].title.includes("squad of"));
  const em = m && m.embeds[0];
  check(`its post in #survival-runs: ${em && em.title}`, em && em.title === "Naish's squad of 4 reached round 60 (Ace)");
  check(`the post lists the squad:\n${em && em.description}`, em && em.description.split("\n").length === 4
    && em.description.split("\n")[0] === "**Naish** (host) · Su-57 Felon · 150 air, 20 ground · 1 revive given"
    && em.description.includes("**xX\\_spagooterpoop\\_Xx** · FA-36 Game · 100 air, 15 ground · 3 revives given")
    && em.description.split("\n")[2] === "**Kalash** · F-22A Raptor · 90 air, 15 ground"
    && em.description.split("\n")[3] === "**dukka** · 60 air, 10 ground · 2 revives given");
  check(`... its squad's kills and revives, no single aircraft: ${em && em.footer.text}`, em
    && em.fields.find((f) => f.name === "Squad kills").value === "400 air, 60 ground"
    && em.fields.find((f) => f.name === "Revives").value === "6" && !em.fields.some((f) => f.name === "Aircraft")
    && em.footer.text === `Every player shot down · Co-op, 4 players · Survival Mode ${C2}`);
  const sumAfter = db.prepare("SELECT value FROM settings WHERE key = 'board_message_3_sum'").get();
  check("the CO-OP pinned message was edited", sumAfter && (!sumBefore || sumAfter.value !== sumBefore.value));
  r = await postBuilt(JSON.stringify(team("cc000000000000000010")), C2B, "7.0.0.1");
  j = await r.json();
  check("the same team run again: a duplicate, its squad not doubled", j.duplicate === true
    && count("SELECT COUNT(*) AS n FROM squads WHERE run_id = 'cc000000000000000010'") === 4);
  r = await postBuilt(JSON.stringify(team("0123456789abcdef0123")), C2B, "7.0.0.1");
  j = await r.json();
  check("a team run under a solo run's id: a duplicate, the solo run left as it was", j.duplicate === true
    && db.prepare("SELECT players FROM runs WHERE run_id = '0123456789abcdef0123'").get().players === null
    && count("SELECT COUNT(*) AS n FROM squads WHERE run_id = '0123456789abcdef0123'") === 0);
  r = await postBuilt(JSON.stringify(small(701, 0, 2, "cc000000000000000011")), C2B, "7.0.0.2");
  j = await r.json();
  check(`a team run with too many kills for its players: refused (${j.error})`, r.status === 422
    && j.error === "too many air kills for the rounds and players"
    && count("SELECT COUNT(*) AS n FROM runs WHERE run_id = 'cc000000000000000011'") === 0
    && count("SELECT COUNT(*) AS n FROM squads WHERE run_id = 'cc000000000000000011'") === 0);
  const off = team("cc000000000000000012");
  off.coop.squad[3].air = 59;
  r = await postBuilt(JSON.stringify(off), C2B, "7.0.0.2");
  j = await r.json();
  check(`a mismatched squad over HTTP: refused (${j.error})`, r.status === 422 && j.error === "squad's kills don't add up to the run's"
    && count("SELECT COUNT(*) AS n FROM squads WHERE run_id = 'cc000000000000000012'") === 0);
}
// a solo run from a COOP2MP build, and more squads: 2 players, 6 players, and the four again under another host
r = await postBuilt(JSON.stringify({ ...run, run_id: "cc000000000000000020", mod: C2, build: C2B, edited: [], pilot: "Soloist",
  difficulty: "standard", round: 13, time_s: 2000, aircraft: "f16c" }), C2B, "7.0.0.3");
j = await r.json();
check(`a solo run from a COOP2MP build: ${r.status} ${JSON.stringify(j)}`, r.status === 200 && j.ok
  && db.prepare("SELECT players, verified FROM runs WHERE run_id = 'cc000000000000000020'").get().players === null);
r = await postBuilt(JSON.stringify(team("cc000000000000000030", { pilot: "Kalash", difficulty: "standard", round: 20, time_s: 3000,
  kills: { air: 100, ground: 10 }, aces: 5, allies: 4, specials: [],
  coop: { players: 2, squad: [sq("Kalash", "f22a", 60, 5, 0, true), sq("Naish", "su57", 40, 5, 1)] } })), C2B, "7.0.0.4");
check("a 2-player run taken", r.status === 200);
const six = ["Shazzy", "Saint Alessia", "cressendo", "mobi118", "gloom", "Twelve"];
r = await postBuilt(JSON.stringify(team("cc000000000000000031", { pilot: "Shazzy", difficulty: "standard", round: 25, time_s: 4000,
  kills: { air: 300, ground: 30 }, aces: 0, allies: 10, specials: [{ kind: "shuttle", round: 5, seconds: 300, won: true }],
  coop: { players: 6, squad: six.map((p, i) => sq(p, "f15c", 50, 5, 0, i === 0)) } })), C2B, "7.0.0.5");
check("a 6-player run taken", r.status === 200);
r = await postBuilt(JSON.stringify(team("cc000000000000000032", { pilot: "Kalash", round: 30, time_s: 3600,
  kills: { air: 200, ground: 20 }, specials: [],
  coop: { players: 4, squad: [sq("Kalash", "f22a", 50, 5, 0, true), sq("dukka", null, 50, 5, 0), sq("Naish", "su57", 50, 5, 0),
                              sq("xX_spagooterpoop_Xx", "fa36", 50, 5, 0)] } })), C2B, "7.0.0.6");
check("the same four under another host taken", r.status === 200);
// the CO-OP boards
check(`a squad on the boards: ${squadText("Naish,xX_spagooterpoop_Xx,Kalash,dukka")}`,
  squadText("Naish,xX_spagooterpoop_Xx,Kalash,dukka") === "**Naish**, xX\\_spagooterpoop\\_Xx, Kalash +1");
{
  const nowS = Math.floor(Date.now() / 1000);
  const ce = await coopEmbeds(env, null, null, nowS);
  check(`the CO-OP message: ${ce.map((m) => m.title.split(" —")[0]).join(", ")}`, ce.length === 4
    && ce[0].title === "Co-op highest round — top 10" && ce[1].title === "Co-op score — top 10"
    && ce[2].title === "Co-op records — top 5" && ce[3].title.startsWith("Co-op this week — top 5 (since "));
  check(`... by squad size: ${ce[0].fields.map((f) => f.name).join(", ")}`, ce[0].fields.map((f) => f.name).join(",") === "2 players,3-4 players,5+ players"
    && ce[1].fields.length === 3);
  const [two, mid, big] = ce[0].fields.map((f) => f.value);
  check(`2 players: ${JSON.stringify(two)}`, two === "1. **Kalash**, Naish — round 20 (2 players, Standard)");
  check(`3-4 players, one line for the four whoever hosted: ${JSON.stringify(mid)}`,
    mid === "1. **Naish**, xX\\_spagooterpoop\\_Xx, Kalash +1 — round 60 (4 players, Ace)");
  check(`5+ players: ${JSON.stringify(big)}`, big === "1. **Shazzy**, Saint Alessia, cressendo +3 — round 25 (6 players, Standard)");
  check(`score, 3-4 players: ${JSON.stringify(ce[1].fields[1].value)}`, ce[1].fields[1].value.includes("— 168,000 (4 players, Ace)"));
  const [longest, specials, revives] = ce[2].fields.map((f) => f.value);
  check(`records, longest run: ${JSON.stringify(longest.split("\n")[0])}`, ce[2].fields.map((f) => f.name).join(",") === "Longest run,Most specials beaten,Most revives"
    && longest.split("\n")[0].endsWith("— 2h 0m 0s (4 players, Ace)") && longest.split("\n").length === 3);
  check(`records, most specials beaten: ${JSON.stringify(specials)}`, specials.split("\n")[0].endsWith("— 3 (4 players, Ace)")
    && specials.split("\n")[1].includes("**Shazzy**") && specials.split("\n").length === 2);
  check(`records, most revives: ${JSON.stringify(revives)}`, revives === "1. **Naish**, xX\\_spagooterpoop\\_Xx, Kalash +1 — 6 (4 players, Ace)\n"
    + "2. **Kalash**, Naish — 1 (2 players, Standard)");
  check(`this week: ${JSON.stringify(ce[3].fields[0].value.split("\n")[0])}`, ce[3].fields[0].value.split("\n").length === 3
    && ce[3].fields[0].value.split("\n")[0].includes("round 60") && !ce[3].fields[0].value.includes("Soloist"));
  const only5 = await coopEmbeds(env, "5+", null, nowS);
  check("/leaderboard coop 5+: that size's boards only", only5[0].fields.length === 1 && only5[0].fields[0].name === "5+ players"
    && only5[2].title === "Co-op records — top 5 (5+ players)" && only5[2].fields[0].value.includes("Shazzy")
    && !only5[2].fields[0].value.includes("Naish") && !only5[3].fields[0].value.includes("Naish"));
  const aceOnly = await coopEmbeds(env, null, "ace", nowS);
  check("... and by difficulty", aceOnly[0].fields[0].value === "no runs yet" && aceOnly[0].fields[1].value.includes("round 60")
    && aceOnly[0].fields[2].value === "no runs yet");
  // solo boards and records never include co-op runs
  const solo = await boardEmbeds(env);
  const aceSolo = solo[0].fields.find((f) => f.name === "Ace").value, stdSolo = solo[0].fields.find((f) => f.name === "Standard").value;
  check(`the solo boards leave co-op runs out: ${JSON.stringify(aceSolo.split("\n")[0])}`, aceSolo.split("\n")[0].includes("round 50")
    && !aceSolo.includes("round 60") && !aceSolo.includes("round 30") && stdSolo.includes("Soloist")
    && !stdSolo.includes("Kalash") && !stdSolo.includes("Shazzy"));
  check("... the solo specials boards too (AB.L..IN and Comona Defense were beaten in co-op only)",
    solo[2].fields.find((f) => f.name === "AB.L..IN").value === "not beaten yet"
    && solo[2].fields.find((f) => f.name === "Comona Defense").value === "not beaten yet");
  const ex = await extraEmbeds(env, null, null, nowS);
  check("... the solo records, aircraft and this week too", !ex[0].fields[0].value.includes("460") && !ex[0].fields[4].value.includes("— 3 ")
    && !ex[1].description.includes("round 60") && !ex[1].description.includes("round 30") && ex[2].fields[0].value.includes("Soloist")
    && !/Kalash|Shazzy|round 60/.test(ex[2].fields[0].value));
  // /leaderboard coop [size]
  const boardOpt = COMMANDS[0].options.find((o) => o.name === "board"), sizeOpt = COMMANDS[0].options.find((o) => o.name === "size");
  check("the slash command has a Co-op board and a size", boardOpt.choices.some((c) => c.value === "coop")
    && sizeOpt && sizeOpt.choices.map((c) => c.value).join(",") === "2,3-4,5+");
  let cr = await commandReply(env, { data: { name: "leaderboard", options: [{ name: "board", value: "coop" }] } });
  check("/leaderboard coop: the CO-OP boards", cr.embeds.length === 4 && cr.embeds[0].fields.length === 3);
  cr = await commandReply(env, { data: { name: "leaderboard", options: [{ name: "board", value: "coop" }, { name: "size", value: "2" }] } });
  check("/leaderboard coop 2", cr.embeds[0].fields.length === 1 && cr.embeds[0].fields[0].value.includes("**Kalash**, Naish"));
  cr = await commandReply(env, { data: { name: "leaderboard", options: [{ name: "size", value: "3-4" }] } });
  check("/leaderboard with a size alone: the co-op board", cr.embeds[0].fields.length === 1 && cr.embeds[0].fields[0].name === "3-4 players");
  // /pilot: the co-op runs they flew in, as host or squad member
  const pk = await pilotEmbed(env, "kalash");
  const kc = pk.fields.find((f) => f.name === "Co-op");
  check(`/pilot of a co-op only pilot:\n${kc && kc.value}`, pk.title === "kalash — Survival Mode" && pk.fields[0].value === "no solo runs yet"
    && kc && kc.value === "3 runs (hosted 2), 3h 50m 0s flown\nbest round 60 (4 players, Ace), best score 168,000\n"
      + "their own kills: 200 air / 25 ground");
  const px = await pilotEmbed(env, "XX_SPAGOOTERPOOP_XX");
  check("/pilot of a squad member: their revives given", px.fields.find((f) => f.name === "Co-op").value.endsWith("\n3 revives given"));
  const pn = await pilotEmbed(env, "naish");
  const soloRuns = count("SELECT COUNT(*) AS n FROM runs WHERE pilot = 'naish' COLLATE NOCASE AND players IS NULL");
  check(`/pilot of a pilot with both: solo totals solo only (${soloRuns} runs), co-op apart`,
    pn.fields.find((f) => f.name === "Totals").value.startsWith(`${soloRuns} runs`)
    && pn.fields.find((f) => f.name === "Co-op").value.startsWith("3 runs (hosted 1)")
    && !pn.fields.find((f) => f.name === "Fastest specials").value.includes("AB.L..IN"));
  check("/pilot of nobody", (await pilotEmbed(env, "nobody")).title === "No runs from nobody yet");
}
// the worst case for Discord's limits: 24-character names (with underscores to escape) on every line of every board
{
  const ins = db.prepare(`INSERT INTO runs (run_id, pilot, difficulty, round, score, air_kills, ground_kills, earned, spent, time_s,
    ended, mod_version, submitted, ip_hash, players, squad, crew) VALUES (?, ?, 'standard', ?, ?, 0, 0, 0, 0, ?, 'died', 'x', ?, 'h', ?, ?, ?)`);
  const nowS = Math.floor(Date.now() / 1000);
  for (let i = 0; i < 36; i++) {
    const n = [2, 4, 24][i % 3];
    const names = Array.from({ length: n }, (_, k) => `${"L_".repeat(10)}L${String(i).padStart(2, "0")}${k % 10}`);
    ins.run(`fit${i}`, names[0], 900 + i, 9000000 + i, 40000 + i, nowS, n, names.join(","), names.map((x) => x.toLowerCase()).sort().join(","));
  }
  const big = await coopEmbeds(env, null, null, nowS);
  const total = big.reduce((t, e) => t + e.title.length + e.fields.reduce((u, f) => u + f.name.length + f.value.length, 0), 0);
  const longest = Math.max(...big.flatMap((e) => e.fields.map((f) => f.value.length)));
  check(`the worst case fits Discord: ${total} characters (6000 at most), the longest field ${longest} (1024 at most), ` +
        `${big[0].fields.map((f) => f.value.split("\n").length).join(" / ")} lines left on the round boards`,
    total <= 6000 && longest <= 1024 && big[0].fields.every((f) => f.value.split("\n").length >= 5));
  db.prepare("DELETE FROM runs WHERE run_id LIKE 'fit%'").run();
}

// ---------------------------------------------------------------------------------------------- reset and restore
const coopBefore = { runs: count("SELECT COUNT(*) AS n FROM runs WHERE players IS NOT NULL"), squads: count("SELECT COUNT(*) AS n FROM squads") };
const before = { runs: count("SELECT COUNT(*) AS n FROM runs"), specials: count("SELECT COUNT(*) AS n FROM specials") };
a = await adminCall("reset", { key: env.ADMIN_KEY, confirm: "reset it" });
check("a reset without the word: refused, nothing gone", a.status === 400 && count("SELECT COUNT(*) AS n FROM runs") === before.runs);
calls.length = 0; posted.length = 0;
a = await adminCall("reset", { key: env.ADMIN_KEY, confirm: " reset " });
check(`reset (typed in any case): ${a.j.done}`, a.j.ok && a.j.status.runs === 0 && a.j.status.specials === 0);
check(`everything archived: ${before.runs} runs, ${before.specials} specials`,
  count("SELECT COUNT(*) AS n FROM runs_archive") === before.runs && count("SELECT COUNT(*) AS n FROM specials_archive") === before.specials
  && count("SELECT COUNT(*) AS n FROM specials") === 0);
check(`the pinned boards updated and a note posted: ${JSON.stringify(a.j.discord)}`,
  calls.filter((c) => c === "PATCH /channels/200/messages/999").length >= 2 && calls.includes("POST /channels/100/messages")
  && posted.some((b) => b.includes("was reset")));
{
  const e1 = await boardEmbeds(env), e2 = await extraEmbeds(env);
  check("the boards are empty", e1[0].fields.every((f) => f.value === "no runs yet") && e2[2].fields.every((f) => f.value.startsWith("no runs")));
  const e3 = await coopEmbeds(env);
  check("the CO-OP boards are empty", e3.every((m) => m.fields.every((f) => /^(no runs|none beaten|no revives)/.test(f.value))));
}
check(`co-op runs reset with their squads (${coopBefore.runs} runs, ${coopBefore.squads} squad rows archived): ${a.j.done}`,
  coopBefore.runs === 4 && coopBefore.squads === 16 && a.j.status.coop === 0 && count("SELECT COUNT(*) AS n FROM squads") === 0
  && count("SELECT COUNT(*) AS n FROM squads_archive") === coopBefore.squads && a.j.done.includes(`(${coopBefore.runs} co-op)`));
check("the undo is offered", a.j.status.undo && a.j.status.undo.runs === before.runs);
r = await post(JSON.stringify(run), undefined, "6.0.0.1");
j = await r.json();
check("a run from before the reset sent again: a duplicate, not back on the fresh boards", j.duplicate === true && count("SELECT COUNT(*) AS n FROM runs") === 0);
r = await postBuilt(JSON.stringify(team("cc000000000000000010")), C2B, "6.0.0.2");
j = await r.json();
check("a co-op run from before the reset sent again: a duplicate too", j.duplicate === true && count("SELECT COUNT(*) AS n FROM squads") === 0);
r = await postBuilt(built("e0000000000000000001"), BUILD, "6.0.0.1");
check("a new run after the reset is taken", r.status === 200 && count("SELECT COUNT(*) AS n FROM runs") === 1);
await new Promise((ok) => setTimeout(ok, 1100));                   // (a second reset, a second later)
a = await adminCall("reset", { key: env.ADMIN_KEY, confirm: "RESET" });
check("a second reset: that one run archived", a.j.ok && a.j.status.runs === 0 && a.j.status.undo.runs === 1);
a = await adminCall("restore", { key: env.ADMIN_KEY });
check(`restore: the latest reset undone (${a.j.done})`, a.j.ok && a.j.status.runs === 1 && a.j.status.undo.runs === before.runs);
calls.length = 0; posted.length = 0;
a = await adminCall("restore", { key: env.ADMIN_KEY });
check(`restore again: the first reset undone too (${a.j.status.runs} runs)`, a.j.ok && a.j.status.runs === before.runs + 1
  && count("SELECT COUNT(*) AS n FROM specials") === before.specials + (JSON.parse(built("x")).specials.length));
check("the archive is empty again", count("SELECT COUNT(*) AS n FROM runs_archive") === 0 && count("SELECT COUNT(*) AS n FROM specials_archive") === 0);
check("restore told Discord", posted.some((b) => b.includes("was undone")) && calls.some((c) => c.startsWith("PATCH")));
{
  const back = db.prepare("SELECT pilot, build, verified, how, aces FROM runs WHERE run_id = 'bbbbbbbbbbbbbbbb5'").get();
  check(`a restored run kept every column: ${JSON.stringify(back)}`, back && back.how === "restart" && back.aces === 5 && back.verified === 0);
  const team10 = db.prepare("SELECT players, squad, crew FROM runs WHERE run_id = 'cc000000000000000010'").get();
  check(`co-op runs restored with their squads (${a.j.status.coop} co-op runs): ${JSON.stringify(team10)}`,
    a.j.status.coop === coopBefore.runs && count("SELECT COUNT(*) AS n FROM squads") === coopBefore.squads
    && count("SELECT COUNT(*) AS n FROM squads_archive") === 0 && team10 && team10.players === 4
    && team10.crew === "dukka,kalash,naish,xx_spagooterpoop_xx"
    && count("SELECT COUNT(*) AS n FROM squads WHERE run_id = 'cc000000000000000010' AND host = 1 AND slot = 0") === 1
    && count("SELECT COUNT(*) AS n FROM specials WHERE players IS NOT NULL") === 4);
  const ce = await coopEmbeds(env);
  check("the CO-OP boards are back", ce[0].fields[1].value.includes("round 60") && ce[2].fields[2].value.includes("— 6 "));
}
a = await adminCall("restore", { key: env.ADMIN_KEY });
check("nothing left to undo", a.status === 404 && a.j.status.undo === null);
{
  const e = await boardEmbeds(env);
  const ace = e[0].fields.find((f) => f.name === "Ace").value;
  check(`the boards are back: ${JSON.stringify(ace.split("\n")[0])}`, ace.includes("round 50"));
}
// the slash commands answered late (2026-10-30: "The application did not respond"): the board is made and edited into
// the "thinking..." answer through the interaction's webhook; a failure says so there
{
  const reply = await commandReply(env, { data: { name: "leaderboard", options: [{ name: "board", value: "round" }] } });
  check("/leaderboard round: embeds made", Array.isArray(reply.embeds) && reply.embeds.length > 0);
  const pilot = await commandReply(env, { data: { name: "pilot", options: [{ name: "name", value: "naish" }] } });
  check("/pilot: one embed", Array.isArray(pilot.embeds) && pilot.embeds.length === 1);
  calls.length = 0;
  const seen = [];
  const rawFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => { seen.push({ url, init }); return new Response("{}", { status: 200 }); };
  await commandFollowUp(env, { token: "tok123", data: { name: "leaderboard", options: [] } });
  check("the follow-up edits the interaction's original answer",
        seen.length === 1 && seen[0].init.method === "PATCH" && seen[0].url.endsWith("/webhooks/1/tok123/messages/@original")
        && JSON.parse(seen[0].init.body).embeds.length > 0);
  seen.length = 0;
  const brokenEnv = { ...env, DB: { prepare: () => { throw new Error("D1 down"); }, batch: async () => { throw new Error("D1 down"); } } };
  await commandFollowUp(brokenEnv, { token: "tok9", data: { name: "leaderboard", options: [] } });
  check("a board that can't be read says so instead of hanging",
        seen.length === 1 && /couldn't be read/.test(JSON.parse(seen[0].init.body).content || ""));
  globalThis.fetch = rawFetch;
}
console.log(fails ? `${fails} FAILED` : "all passed");
process.exit(fails ? 1 : 0);
