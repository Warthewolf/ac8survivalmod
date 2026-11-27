# tools/autotest: Survival's in-game tests, unattended

An agent installs a staged build, starts the game, runs scripted checks inside it, collects PASS / FAIL, and leaves the
install as it was, with nobody at the controller. The design is another team's, from the user's upload of 2026-11-16
("AC8 automated in-game testing: how ours is built"), built over ~90 gated runs; every rule below came from a failure.
The user's yes (2026-11-16): her installed Survival moved aside for each gated run and put back, the game launched
whenever it's closed.

```
agent --queues--> gate.py (one game run at a time, safety, restore) --runs--> job.py (install, launch, watch, verdict)
                                                                                 |
                                                                                 +- in the game: sv_selftest.lua logs PASS/FAIL
```

## Run one
```
python -I tools/autotest/gate.py run --who claude --label "tanacorn 0.74.72" --max-minutes 25 \
    --cleanup "python -I tools/autotest/kit.py restore" -- \
    python -I tools/autotest/job.py --stage build/release/stage_dev_0.74.72 --suite tanacorn --max-s 900
python -I tools/autotest/gate.py status
python -I tools/autotest/gate.py cancel --who claude      # the only safe stop (never kill the gate: no restore then)
```
Start `run` in the background; it blocks until its turn. Results: the main tree's `build/autotest/runs/<stamp>_<who>/`
(verdict.txt, provenance.txt, job_out.txt, Survival's logs and config, install_diff.txt if anything changed, crash_*),
`build/autotest/gate_log.txt` (START / LAUNCH / END lines).

The stage is a `package_dev.sh` stage (test keys kept: the fast path presses Ctrl+F8). A TANI=1 stage for `tanacorn`.

## The pieces
- **gate.py**: the queue (build/autotest/queue.json; the user playing counts as busy); a snapshot of Win64 + Paks (size,
  mtime; logs skipped); the saves backed up (SaveGames; a copy a killed run left is the true pre-run state and goes back
  first); while the job runs, once a second: the job's launch flag -> the safe launch, a cancel flag, anti-cheat (kill,
  rc 99), free commit < 3 GB (kill, rc 97), the max time (rc 124), the driver-warning dialog (answered No by BM_CLICK:
  no mouse, no focus; any other dialog logged, never clicked). Always after: the cleanup, the changed saves put back
  (new ones moved to the run folder), the snapshot diffed (a difference = rc 4), a new crash folder (rc 3).
- **The safe launch**: never Steam's Play or steam://run with mods in (that path starts Easy Anti-Cheat):
  `AceCombat8.exe -eac-nop-loaded -nosplash`, cwd Win64, SteamAppId / SteamGameId, detached; refused with the game or
  anti-cheat running, Steam not running, UE4SS missing, free commit < 20 GB; good once UE4SS.log names IoStoreLoaderMod
  and AC8SurvivalMode (120 s).
- **kit.py**: the user's Mods/AC8SurvivalMode and IoStoreLoaderMod/SurvivalMode MOVED aside (build/autotest/aside, a
  rename on the same drive), the stage copied in (a marker first, a sha256 manifest), enabled.txt, the overlay:
  `sv_selftest_keys.lua` first in MODULES, `sv_selftest.lua` last, `selftest.txt`, the suite's `survival_config.lua`
  (lua/config_<suite>.lua; a run with one is never ranked), the installed main.lua's MODULES patched (the copy only).
  restore: Survival's logs and config copied out, only folders with this install's marker removed, hers moved back.
- **job.py**: kit install, provenance, the gate's launch, Survival's Lua log followed (the watchdog: 120 s with no line),
  the game closed on `selftest: RESULT`, kit restore, verdict.txt.
- **lua/sv_selftest.lua**: on Survival's MENU.tick (the game thread), nothing touched while the level is going. In:
  the main menu, `menu_wait_s`, Ctrl+F8 pressed (sv_selftest_keys.lua's record: AC8 ignores posted key messages), D and
  your plane; your plane invincible every 2 s and the DOWN autopilot (SV_Down) round the airfield once airborne. Then the
  suite: `selftest: PASS|FAIL <what> (<detail>)`, `selftest: RESULT n/m`. It wraps the global `log` to wait for the lines
  that are the only sign of a step (the Tanacorn's railguns and railcannon).

## Suites
- `smoke`: the main menu, the level, a run, your plane, invincible, 20 s on.
- `tanacorn` (a TANI=1 stage; round 1 an hour away): Ctrl+L's live hull and all its parts; her armour (the parts' death
  blast off; the hull bCanBeDamaged false, bIsInvincible true); one T5 and one VLS block finished off, nothing else
  hurt 4 s later, the hull's health unchanged (the tester's "everything immediately dies"); both railguns deployed,
  ordered, their barrels moving, a first EML round; Ctrl+H: the railcannon deployed, charged (RAILGUN WARNING), its shot,
  its impact on the airfield (AF.bomb up); shot down in its second charge: its cycle over, no impact; the hull's health
  unchanged at the end.

- ULYSSES (docs/re/ULYSSES.md; each its config_<suite>.lua: round 1 an hour away): `ulysses` (round 2 with the core, its
  pictures), `ulysses2` (both rounds, a minute's break, impacts up close), `ulydawn` (ulysses2 at its real sunrise),
  `ulymany` (round 1 whole at the real heights and speeds: 50 in waves of 2, up to 30 falling, every box though 36 are
  lent, the frame time), `ulysoak` (both rounds played out as shipped, nobody shooting: memory and frame time),
  `ulysound` (its Wwise sounds one by one at set distances, a whistle closing from 12 km, the pause; the camera held
  over the sea 41 km west), `ulycal` (its impact against AC8's own explosions), `ulylines` / `ulytrails` (looks).
  `ulylock` (both rounds back to back, short: round 2 borrows round 1's targets again, every fragment a target, each
  an air object, a lock probe per weapon as a ground and an air object, the sepia wash at 21:9 against the screen,
  the targets handed back after the last round and the KEW unit spawnable again; Saint Alessia's run of 0.75.117).

## Sound levels (2026-11-24)
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/autotest/loudness.ps1 -Seconds N -Out <file>` beside a job: the
default playback device's level every 100 ms by WASAPI loopback (levels only, never the sound; anything else playing on
the PC counts too). `python -I tools/autotest/loudness_report.py <file> <run folder>` matches them to the suite's
"SOUND ..." lines by the game's clock. A suite that measures sound holds round 1 off (enemy missiles and warnings drown
it) and mutes the music (AKE_System_BGM_Mute_On). Two game runs in a row were twice stopped by Claude Code for low
memory as the second loaded (AC8 ~24 GB at its load): run them one at a time in the foreground, or keep the session busy.

## Pictures and settings
- `A.picture(name, atFn, lookFn, fov)` in a suite: a CameraActor of ours at atFn() turned onto lookFn(), your view on it,
  the game's own `HighResShot 1` and a `selftest: SHOT <name>` line; job.py grabs the game's window then (PrintWindow
  with PW_RENDERFULLCONTENT: no focus taken) into the run's `shots/NN_<name>.png` and moves the game's own screenshots
  (its Saved/Screenshots) there after the run (`game_HighresScreenshotNNNNN.png`). The tanacorn suite takes the whole
  ship, a raised railgun, the railcannon charging and its impact; the fleet suite the formation and GEOFON.
- `job.py --conf name=value` (repeatable) adds lines to selftest.txt: `plane=floor` keeps your plane shootable but never
  down (SetMinHealth at 40 % of MaxHealth, not invincible), for tests of what shoots at you.

## Lessons from the first runs (2026-11-16)
- The driver box: a POSTED WM_COMMAND for its No, never a sent BM_CLICK (AGENTS.md hard rule 65).
- No coroutines in the self-test: UE4SS's functions fail there (hard rule 66); suites are step lists.
- The Mod Loader's loadorder.txt can switch Survival's containers off (hard rule 67): kit.py turns it on for the run.
- FindFirstOf("PlayerController") matches only that exact class: GetPlayerController(game instance, 0).
- In Lua patterns "+" is a quantifier: escape it ("Ctrl%+N").

## Rules (adopted as they are)
1. Every game run goes through the gate, with --cleanup. Nothing else starts AC8 for a test.
2. Stop a run with `cancel`, never by killing the gate.
3. A crash stops that test line: don't run it again until the cause is found and written down.
4. UE cooks (tools/tanicorn/build.sh, x02s, laser7) take tens of GB of commit: never while a run is going.
5. Leave the launcher's mode alone.
6. The self-test and its overlay are installed by kit.py only, never in a build or a zip.
7. Each result names its build (provenance.txt), its path (the fast path) and what test-only it used.

## Known limits
- The fast path skips the menu's mission setup (the hangar, the loadout): any mission end into QuitGame crashes, so the
  job closes the game itself. A menu-driven start (real input, idle-only) isn't built.
- Lua input writes are ignored: a plane on the ground can't take off by itself.
- Never FindAllOf per tick in a suite (~10 ms each).
