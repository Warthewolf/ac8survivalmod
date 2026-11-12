# The log report (tools/log_report.py, 2026-11-11)

One Markdown page from the logs a player sends, so a test run is read in minutes, not hours (the user, 2026-11-11, "Go for
all of them": the log report tool after the investigations of Saint Alessia's 50-round co-op run). Standard library only.

    python -X utf8 -I tools/log_report.py <bundle> [<bundle> ...] [-o page.md]
      --session STAMP   the session to read in a logs folder of several (YYYY-MM-DD_HH-MM-SS; default the newest;
                        `undated` for an older runtime's undated logs next to dated ones)
      --ref N           the bundle whose clock the page uses (default: the host)
      --no-ue4ss        skip UE4SS.log (the slowest file: ~5 s for her 396 MB)
      --check-anchors   the checklist's lines still in the code (and each regex taking its sample); exit 1 if not

## What it reads
A bundle is a folder or a .zip, or a single .log:
- the old layout (runtime 0.32.31 and before): `AC8SurvivalMode_lua.log`, `AC8SurvivalMode.log`,
  `AC8SurvivalMode_crumbs.log` (+ `.prev.log`), `UE4SS.log`, the player's own `report.txt`;
- runtime 0.32.32+ (runtime/logbundle.c): `logs\` with every file named `<prefix>_<stamp>` (the Lua and runtime logs,
  the crumbs, `session_<stamp>.txt`, `UE4SS_<stamp>.log` collapsed by logdedup.h, `UE4SS_stats_<stamp>.txt`) and the
  zips of finished sessions, `AC8Survival_<stamp>_<mod>.zip`, which also hold `bundle.txt`, `Saved/Logs/*.log` (the
  game's own) and `Crashes/UECC-*/`. A folder (or a zip of one) of several sessions gives its newest (or `--session`'s);
  one with only session zips, its newest zip (read in memory when it sits in another zip, up to 1 GB); the others are
  named on the page. Zips are read in place, never extracted. A file that can't be read to its end (a cut zip, a broken
  deflate stream) is said on the page with what came before it; a zip that can't be opened at all (cut short) is said
  as "not a readable zip (cut or damaged)".
- several players' logs in one bundle (`alessia/` and `delta/`, each with its logs or its `logs\` folder): each folder
  is read as a game of its own, as if given as separate bundles, and the page says so (one player's extracted copy of a
  session zip in a subfolder shows as a second game too: give the one wanted alone).
- UE4SS.log is streamed line by line: its lines counted by shape (numbers as N), by source (`[Lua] [<mod>]`), the mods
  it started and its error-looking lines; a collapsed copy's `---- the line above N more times ----` counts N more.

The logs are untrusted: nothing in them is run, and every name or line goes into the page escaped (a table cell can't be
broken by a `|`, a backslash before it included; no tag gets through; `www.` and `://` don't become links; log lines go
in code spans).

## The page
- **Build**: each game's role (host: `co-op run X started: this game hosts it`; joiner: `the host's (the host sends
  it)`; later the host by migration), Lua and runtime versions, build hash, session stamp, files, UE4SS's mods, the
  crumbs' last line (a hang or a crash shows there), crash folders and their `<ErrorMessage>`, `bundle.txt`'s summary,
  and the player's `report.txt` quoted.
- **Clocks** (several bundles): every time is on the reference game's clock (the host's), each other game's own time
  in [brackets]. A joiner's offset is the median of its round clears (`round N cleared (the host's round)`, `ROUND N
  COMPLETE`) minus the host's (`round N clear`), the densest 20 s cluster; with the matches and their spread. The Lua
  logs have no date: a clock going back by over 6 h is the next day (each file starts from the runtime log's first
  time).
- **Who played**: each slot's players as they changed (`coop: player N is ...`, the runtime's `joined:` and minute
  lines), joins, leaves, links lost; refused joins; two hosts (`X is also the host`, with that player's link drop
  before it and their return after); migrations; the host's "left" notice.
- **Rounds**: start (`round N: X aircraft: ...`; a joiner's from its `ROUND N` callouts: a callout belongs to the next
  start line when that's the same round's with no host migration between, however long the wait for players, so a
  joiner that became the host by migration keeps its joiner rounds, then its own), clear, length, kind (normal, bomber
  raid, strike package, `ace squadron: <name>` from `ACE SQUADRONS:`, `special: <name> (<its callout>)`; a joiner's
  VALKA from `the host's VALKA mood on`), the outcome (`run over (...)` from the leaderboard's or DOWN's run over; `not
  cleared (host migration)`), players and kills from `stats: round N` (a cut-short round's too). A new run: a run over,
  a new co-op run, Lua loaded again, or a round number not above the last one but not after a host migration (the new
  host starts the room's round again: the same run). A column per other game: its clear's difference.
- **Lag by round**: a `perf:` line covers the ticks before it (back to the line before when its 250 ms ticks about fill
  the gap, else its ticks back from it), so its numbers go to every round its window overlaps, weighted by the overlap
  (pieces under 5 s left out): the tick avg and SV_UnitAlive a tick and its ms as overlap-weighted means; the heaviest
  line and the worst half only from lines mostly (50%+) in the round; the top three parts from the line most in it; each
  line's share of its window in the round. The runtime's minute lines (0.74.52: `frames:` fps, worst frame, frames over
  100 ms; `units:` us an ask) go to the round their minute was in, and the tick by round kind is weighted the same way
  (her question: "lag during Ace waves").
- **STORE windows**: the music hold (`music: track clock held (landing store)` to `running`; a re-hold within 5 s is the
  same window; else the runtime's `minigame:` lines, co-op's `starts` or solo's `deactivated` to `ends`) and the RE_SV_*
  events a line says ran inside it (`X fired`, `(X 1)`, `X (1)`, `(X: 1)`, `X (fired)`, a bare `(X)`, the host's `X
  here:`, the crumbs' `lua: event X: 1`). A line that says one did NOT run (`not fired`, `dropped`, `held here`,
  `didn't take`, `waits for`, `not ... again`, a result other than 1) shows its first name as `~X (why)`: the names in
  its explanation aren't counted. Bold: fired and not a repeating order (hard rule 64: check it took); (h): forwarded
  from the host; `!`: a special's moment logged inside (the shuttle's liftoff, a rocket's launch). A joiner's windows
  also list what the reference's (the host's) log fired in them, its clock aligned: Delta's 18 windows hold the host's
  RE_SV_StrikeAegis*, AllyDefend/Hunt*, Escort_01/08/19, RadioRaidB. Her shuttle run shows its `lifted off (countdown
  over ...)` inside her STORE at 18:47:43.
- **DOWN and revives**: each player's DOWN (`down: you're down`, `YOU'RE DOWN`, `X DOWN` callouts; one said again within
  30 s is the same), back (`revive: back (revived by X)`, `X BACK`), or left / run over; the price from the host's
  `revive: player N revived player M for P` (matched by the revived slot). Names are matched as sv_down.lua gives them
  (Lua's string.upper, a-z only, cut to 14 characters), so a long or non-ASCII name finds its slot. The revive answers
  and refusals grouped: the host's refusals, a joiner's `the host refused your revive`, `no answer from the host`,
  `revive refunded`, and the STORE's Revive row answers (only those about a revive).
- **Co-op link**: per slot rtt min / median / max (`coop:   player N name: linked, rtt ...`), resends summed over link
  sessions, minutes "link lost", links lost / back / gone; failed enemy moves, bad packets, lateness; the reliable
  queue's drops; every link event in a folded list.
- **ZFA-44s**: carriers, launches, finishes (0.74.52's `finished off` / `could not be finished`; a carrier's end's
  `N parked ZFA-44s of ship S finished off` and the switched-off ones' `N of this game's switched-off ZFA-44s of ship S
  finished off (M tried)`), the old symptom `still has N up after 30 s`, Helios blasts (kills, ZFA-44 down or not, where), positions, and the allies' census (`allies: ...
  at round N's level`): her run's last 24 ZFA-44s were the same objects for 35 rounds.
- **The shuttle**: how it lifted off (event package / countdown over / the 0.74.51 replay), the flags as the round
  probes read them, its lines. **The Spaceport's rockets**, **the Alicorn** (tank and core hits, the core's lines, the
  joiners' hits), **the leaderboard** (sends; one answer each, the run's, a waiting run's or a kept run's: stored,
  stored (replaced), duplicate, NOT stored, on the board already, not sent (network: a negative status like -12007, its
  why in brackets), no answer (429, 5xx), refused; the `co-op run X NOT stored` / `stored: it replaced` / `is on the
  board already` line after an answer refines it, not a second answer), each with its lines.
- **Errors and refusals**: lines with error / FAILED / refused / NOT / not fired / could not / given up / didn't resolve ... grouped by
  shape (numbers and ids as N / X), counts like `0 failed` and routine `can't be said now` left out; the game's own
  `Saved/Logs` errors.
- **UE4SS.log**: lines, size, span, lines by source (her Falken Red Gloss: 99.2%), the most repeated shapes, error-looking
  lines of other mods (Survival's own are in its log).
- **Checklist: 0.74.52's new log lines**: seen N times (first) or not, per game. `yes` every run, `when` only when it
  happens, `no` a sign of trouble.
- **Where the games disagree** (several bundles): round clears more than 5 s apart after the offset, rounds one game
  started that the other has no start of, a player's own DOWN against the reference's, and the event package's flags
  (`round probe: flags`) changing at clearly different times (no overlap of the probes' windows, 30 s slack, narrowed to
  a line's own time where one says it: a rocket's escape, the shuttle's liftoff). Her run: rocket B escaped at 00:11:41
  on her game, by 00:09:43 on Delta's.

## The checklist
`CHECKS` in tools/log_report.py: (fix, area, log, a regex at the line's start, an anchor: a literal of the code that
prints it, a sample line, expect). For the next build's fixes add their lines there; `--check-anchors` (run by
tools/checks/log_report_test.sh) fails when an anchor left the code (a reworded log line) or a regex doesn't take its
sample. The page says when a game's build is older than 0.74.52 (none can be there).

## Tried on (2026-11-11)
Saint Alessia's 50-round host bundle (0.74.36, 5.3 MB Lua log, 396 MB UE4SS.log) with Delta's (joiner): 6 s, offset
+9:00:01 on 29 round clears (spread 1 s). The page has what the investigations found: NotMexi's link lost 22:07:21, gone
22:08:45, `NotMexi is also the host` 22:09:50 and 22:11:28, back as player 3 at 22:11:29; the Spaceport rounds' lag
(heaviest lines 98.9 / 95.8 ms in rounds 49-50, 66.2 in round 21; overlap-weighted 94.0 / 61.7 / 48.6; SV_UnitAlive
~75 ms a tick at the worst, against 8-40 ms in the others; ace rounds 30.8 ms on average, normal 27.7); `{"ok":true,
"duplicate":true}`; her DOWN from 00:02:42 to 00:31:06 (revived by Delta for 138,240); the 24 ZFA-44s and 70 Helios
blasts with 0 kills; rocket B's disagreement; Delta's round 39 as VALKA, as the host's. Her shuttle run: `lifted off
(countdown over)` inside her STORE window.

## Test
tools/checks/log_report_test.sh (Python; Windows Git Bash and Linux): made-up bundles in tools/checks/fixtures/log_report
(invented names, hostile ones among them):
- `host/` (the old layout, its clock over midnight) and `joiner/` (runtime 0.32.32+'s, zipped by the test, 3:00:07
  ahead): each section's key lines on six pages (the host, the joiner's zip, both, a logs folder of two session zips
  and one of them by --session, that folder zipped), the clocks and the disagreements, the joiner's STORE window (what
  ran, what didn't, the host's events in it), a perf line over two rounds, a backslash before a pipe, `www.` / `://`;
- `solo/`: the Lua log starting after the runtime log's midnight, a STORE from solo's minigame lines alone (and the
  crumbs' results in it), bomber raid and strike package rounds, a cut-short round's stats, a second run, a callout 160 s
  before its round's start, DOWN said twice, `still has N up`, the switched-off finish line, the leaderboard's answers
  (a network error, a waiting run, a kept run, a refinement);
- `pair/` (two players' folders: read as a folder and zipped): names over 14 characters and not ASCII (a DOWN on both
  games, the revive price by slot, `left the mission`), a round the joiner shows no start of, the joiner's revive
  refusals and refunds, a STORE answer that isn't a revive's, a joiner's VALKA round;
- `fork/` (link lost, gone, `X is also the host`, back as another slot), `rolecrash/` (a slot's role, then a takeover),
  the joiner with rounds after its host migration (made by the test), a cut session zip and a zip with a broken deflate
  stream;
- every table's rows as wide as its head (a pipe after an even run of backslashes ends a cell), no raw tag from a log,
  the collapsed UE4SS copy counted back, a 200,000-line UE4SS.log streamed (its count, and scan_ue4ss's peak memory
  under 4 MB for a 16 MB file), `--check-anchors`. Pages in build/checks/log_report.
