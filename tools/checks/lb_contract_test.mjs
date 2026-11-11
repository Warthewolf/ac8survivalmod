// lb_contract_test.mjs (run by lb_contract_test.sh): what the game sends against what the deployed Worker takes, read
// from the sources so a new special or a renamed build tag can't slip past the leaderboard unseen.
//  - every kind a Lua part passes to LB.special("...") in Scripts/*.lua survives the Worker's checkRun with its score:
//    an unknown kind is dropped from a run without any error, which is how VALKA's wins (until 0.73.83) and THE
//    ESCORT's, THE DECOY's, GONE FISHIN''s and THE FESTIVAL's (until the 0.74.0 review) were scored as nothing;
//  - main.lua's VERSION, alone (a solo zip) and with tools/coop_edition.py's COOP_TAG (a co-op zip), passes its
//    "mod" check (every co-op build's runs were refused as "bad mod version" once, 2026-10-30 and 2026-11-02).
// Run with: node lb_contract_test.mjs <repo root>
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const { checkRun, score } = await import(pathToFileURL(join(root, "leaderboard", "src", "index.js")).href);
let fails = 0;
const check = (what, ok) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) fails++; };

const scripts = join(root, "mod", "UE4SS", "AC8SurvivalMode", "Scripts");
const kinds = new Map();                                      // kind -> the parts that send it
for (const f of readdirSync(scripts).filter((n) => n.endsWith(".lua")).sort()) {
  const src = readFileSync(join(scripts, f), "utf8");
  // LB.special("kind", ...) and pcall(LB.special, "kind", ...)
  for (const m of src.matchAll(/LB\.special(?:\(|\s*,)\s*"([^"]*)"/g)) kinds.set(m[1], [...(kinds.get(m[1]) || []), f]);
  // a kind passed as a variable can't be read here: said, so it's looked at by hand
  for (const m of src.matchAll(/LB\.special(?:\(|\s*,)\s*([^"\s)][^,)]*)/g))
    if (!/^kind$/.test(m[1])) check(`${f}: LB.special(${m[1]}, ...) names its kind by a variable: check it by hand`, false);
}
// (13 in 0.74.49: fewer means a special was taken out, or a call's form this reader doesn't know: look at it)
check(`the specials the game reports, read from Scripts/*.lua: ${kinds.size} (${[...kinds.keys()].join(", ")})`, kinds.size >= 13);

const base = { v: 1, run_id: "0123456789abcdef0123", pilot: "Contract", difficulty: "standard", round: 30, mod: "0.1.0",
  kills: { air: 10, ground: 5 }, zollars: { earned: 1000, spent: 500 }, time_s: 3600, ended: "died", specials: [] };
for (const [kind, parts] of kinds) {
  const r = { ...base, specials: [{ kind, round: 5, seconds: 120, won: true }] };
  const why = checkRun(r);
  check(`special "${kind}" (${[...new Set(parts)].join(", ")}): the Worker keeps it and scores its win`,
        why === null && r.specials.length === 1 && score(r) === score({ ...base, specials: [] }) + 3000);
}

const main = readFileSync(join(scripts, "main.lua"), "utf8");
const version = (main.match(/^(?:local )?VERSION = "([^"]+)"/m) || [])[1];
const tag = (readFileSync(join(root, "tools", "coop_edition.py"), "utf8").match(/^COOP_TAG = '([^']+)'/m) || [])[1];
check(`VERSION read from main.lua (${version}) and COOP_TAG from tools/coop_edition.py (${tag})`, !!version && !!tag);
for (const mod of [version, version + tag]) {
  const r = { ...base, mod };
  const why = checkRun(r);
  check(`a run from mod "${mod}" passes the Worker's version check (${why || "ok"})`, why === null);
}

console.log(fails === 0 ? "lb contract: all passed" : `lb contract: ${fails} FAILED`);
process.exit(fails === 0 ? 0 : 1);
