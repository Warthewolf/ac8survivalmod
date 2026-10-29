// Local test of the Worker: node test/worker.test.mjs (Node 22+; D1 stood in for by node:sqlite, Discord by a stub)
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { createHmac } from "node:crypto";
import worker, { score, checkRun, boardEmbeds, extraEmbeds, weekStart, pilotEmbed, commandReply, commandFollowUp } from "../src/index.js";

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
check(`the boards: ${e.length} embeds (round, score, specials)`, e.length === 3 && e[2].fields.length === 6);
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
  for (const t of ["runs", "runs_archive", "specials_archive", "builds", "builds_seen", "resets", "admin_fails"])
    check(`the oldest database upgraded: ${t} as schema.sql has it`, cols(db, t) !== "" && cols(db, t) === cols(fresh, t));
}

// ---------------------------------------------------------------------------------------------- the co-op version
check("a co-op build's version is taken (0.72.2-coop.20)", checkRun({ ...run, mod: "0.72.2-coop.20" }) === null);
check("Stable 1's co-op version is taken (0.71.5-coop.17)", checkRun({ ...run, mod: "0.71.5-coop.17" }) === null);
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

// ---------------------------------------------------------------------------------------------- reset and restore
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
}
check("the undo is offered", a.j.status.undo && a.j.status.undo.runs === before.runs);
r = await post(JSON.stringify(run), undefined, "6.0.0.1");
j = await r.json();
check("a run from before the reset sent again: a duplicate, not back on the fresh boards", j.duplicate === true && count("SELECT COUNT(*) AS n FROM runs") === 0);
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
