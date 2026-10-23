// Local test of the Worker: node test/worker.test.mjs (Node 22+; D1 stood in for by node:sqlite, Discord by a stub)
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { createHmac } from "node:crypto";
import worker, { score, checkRun } from "../src/index.js";

const db = new DatabaseSync(":memory:");
db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
const stmt = (sql, args = []) => ({
  bind: (...a) => stmt(sql, a),
  all: async () => ({ results: db.prepare(sql).all(...args) }),
  first: async () => db.prepare(sql).get(...args) ?? null,
  run: async () => db.prepare(sql).run(...args),
});
const DB = { prepare: (sql) => stmt(sql), batch: async (list) => { for (const s of list) await s.run(); } };
const env = { DB, SUBMIT_KEY: "test-key", ADMIN_KEY: "admin", DISCORD_TOKEN: "t", DISCORD_APP_ID: "1",
              RUNS_CHANNEL_ID: "100", BOARD_CHANNEL_ID: "200", DISCORD_PUBLIC_KEY: "00" };
const calls = [];
globalThis.fetch = async (url, init) => {
  calls.push(`${init.method} ${url.replace("https://discord.com/api/v10", "")}`);
  return new Response(init.method === "POST" ? JSON.stringify({ id: "999" }) : "{}", { status: 200 });
};

let fails = 0;
const check = (what, ok) => { console.log(`${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) fails++; };
const post = (body, sig) => worker.fetch(new Request("https://x/submit", { method: "POST", body,
  headers: { "X-SV-Signature": sig ?? createHmac("sha256", env.SUBMIT_KEY).update(body).digest("hex"), "CF-Connecting-IP": "1.2.3.4" } }), env);

const run = { v: 1, run_id: "0123456789abcdef0123", pilot: "Naish", difficulty: "ace", round: 12, mod: "0.47.0",
  kills: { air: 140, ground: 12 }, zollars: { earned: 40000, spent: 30000 }, time_s: 2400, ended: "died",
  specials: [{ kind: "ladon", round: 7, seconds: 212, won: true }, { kind: "amphibious", round: 10, seconds: 300, won: false }] };

check("score: (12000 + 14000 + 600 + 3000) x 1.5 = 44400", score(run) === 44400);
check("a sane run passes", checkRun(run) === null);
check("too many kills is refused", checkRun({ ...run, kills: { air: 9999, ground: 0 } }) !== null);
check("a too-short run is refused", checkRun({ ...run, time_s: 10 }) !== null);
check("a bad pilot name is refused", checkRun({ ...run, pilot: "<script>" }) !== null);

let r = await post(JSON.stringify(run));
let j = await r.json();
check(`submit: ${r.status} ${JSON.stringify(j)}`, r.status === 200 && j.ok && j.score === 44400);
check("the run was posted", calls.some((c) => c === "POST /channels/100/messages"));
r = await post(JSON.stringify(run));
j = await r.json();
check("the same run again is a duplicate", j.duplicate === true);
r = await post(JSON.stringify({ ...run, run_id: "aaaaaaaaaaaaaaaa1" }), "00");
check("a bad signature is refused", r.status === 401);
for (let i = 0; i < 6; i++) await post(JSON.stringify({ ...run, run_id: `bbbbbbbbbbbbbbbb${i}` }));
r = await post(JSON.stringify({ ...run, run_id: "cccccccccccccccc" }));
check("the 7th run within the hour is refused", r.status === 429);
r = await worker.fetch(new Request("https://x/setup?key=admin"), env);
j = await r.json();
check(`setup: ${JSON.stringify(j.done)}`, j.ok && calls.includes("PUT /applications/1/commands"));
calls.length = 0;
await post(JSON.stringify({ ...run, run_id: "dddddddddddddddd", pilot: "Other" }), undefined);   // (rate limited: same IP)
const rows = db.prepare("SELECT COUNT(*) AS n FROM runs").get().n;
check(`runs stored: ${rows}`, rows === 6);
const sp = db.prepare("SELECT COUNT(*) AS n FROM specials WHERE won = 1").get().n;
check(`beaten specials stored: ${sp}`, sp === 6);
console.log(fails ? `${fails} FAILED` : "all passed");
process.exit(fails ? 1 : 0);
