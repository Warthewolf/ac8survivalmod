// leaderboard_bodies.mjs <file> (run by tools/checks/leaderboard_test.sh when node is there; 0.73.77, plan H5): every
// run body tools/checks/leaderboard_test.lua had the game send ("<expect>\t<what>\t<json>" a line; expect "ok", or the
// Worker's refusal) put through the Worker's own checkRun (leaderboard/src/index.js), so a co-op run the game sends is one
// the Worker takes: the squad's size, names (the pilot rule, unique ignoring case), the host first and the run's pilot,
// the kills adding up, the limits by players.
import { readFileSync } from "node:fs";
import { checkRun } from "../../leaderboard/src/index.js";

const lines = readFileSync(process.argv[2], "utf8").split("\n").filter((l) => l.trim() !== "");
let fails = 0;
for (const line of lines) {
  const [want, what, ...rest] = line.split("\t");
  const body = rest.join("\t");
  let got;
  try { got = checkRun(JSON.parse(body)) ?? "ok"; } catch (e) { got = "not JSON: " + e.message; }
  const ok = got === want;
  if (!ok) fails++;
  console.log(`  ${ok ? "ok  " : "FAIL"} the Worker's checkRun ${want === "ok" ? "takes" : "refuses"} ${what}${ok ? "" : ` (it said: ${got})`}`);
}
if (!lines.length) { console.log("  FAIL no run bodies to check"); fails++; }
console.log(`leaderboard bodies (the Worker's checkRun): ${fails ? fails + " FAILED" : "all passed"}`);
process.exit(fails ? 1 : 0);
