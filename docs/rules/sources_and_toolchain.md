# Sources allowed, release exclusions and toolchain

Moved verbatim from AGENTS.md (2026-11-14). The exceptions and the user's quotes are unchanged.

## Toolchain
- UE4SS runtime scripts own the state: round counter, credits, shop, landing detection, wave selection.
- IoStore mod loader container: arena map, airfield, spawn points, path sets.
- Config file: wave tables, prices, special rotation, intermission length. Players must be able to edit these without rebuilding.
- Survival Mode is built only from stock game files; nothing from Stonehenge Returns is used or shipped.
  One exception, at the user's request (2026-10-24): the VALKA special may use Ace Combat 7 assets (the X-02S model,
  Mihaly's railgun effects and sounds). Never AC7 voice lines. See docs/re/VALKA.md.
  A second, at the user's request (2026-11-07: "I want the entire weapon from ACE7 to be ported over"): AC7's
  LaserInterceptor (wp_LaserInterceptor: its values, its swing curve CUR_LaserInterceptorSwingRate, its beam effects
  FX_UAV_TLS_Muzzleflash01/02 with their meshes, materials and textures, and its sounds) for the ZFA-44s' anti-missile
  laser, on AC8's native ALiveLaserInterceptor. Never AC7 voice lines. See docs/re/LASER_INTERCEPTOR.md.
- Ace Combat Infinity, at the user's request (2026-11-03: "pull the Satellite Interception Mission from ACI"; again
  2026-11-22: "making the SOLG again but as a custom asset using the Infinity Model, it's animations have to work"):
  the SOLG special may use AC:I's SOLG model, its textures and its animations (the user's own AC:I install, $ACI (.env)
  outside the repo, nothing of it committed). Its sounds too (2026-11-23, the user: "start with the SOLG"): the SOLG's own
  bank (DATA92 #528: SOLG_BREAK_BIG_01/02, SOLG_BREAK_SML_01-04). The Ulysses special too (2026-11-23, the user: "Recreate
  the Ulysses Event from Strangereal", "Yes, use them"): AC:I's meteor models (o_meta, o_metb, o_metc, o_metd, o_metx
  and their debris / shell pieces), their textures (with CONT_METEORITE / CONT_ULYSSES) and the Stardust sounds
  (Stardust_*, EXPLO_STARDUST_*, OBJ_FALL_STARTDUST_*, YUSEI_EXPLO), decoded outside the repo. Never AC:I voice lines, map or cutscene; never a stock AC8 boss under
  it ("the SOLG cannot use any boss from the game"). See docs/re/SOLG.md.
- A third AC7 exception, at the user's request (2026-11-17: "extract some voice lines from Ace Combat 7's WWise Bank,
  particularly the Alicorn's Crew speeches, run them through a voice filter that makes them sound distorted and horrific",
  "Yeah you've got the go ahead", e.g. "Salvation is nigh!" and the crew's oath; "I want to hear each of your custom work on
  the voice lines before they go in"): the Alicorn crew's radio lines (Captain Torres and the Sub crew of AC7's DLC
  missions ex01-ex03), distorted (tools/ac7_voice.py, tools/ac7_voice_fx.py), for THE TANACORN only, and each line heard by
  the user before it goes in. No other AC7 voice line. Where they go (user, 2026-11-18: "The AC7 lines that you created go in
  also"): the dev install and every zip WITH THE TANACORN (TESTER=1 TANI=1, FRIENDS=1 TANI=1, and since 0.75.60 the public
  zip, PUBLIC=1 TANI=1: the user, 2026-11-23, "Everything of hers"); never a zip without her.

- No other mod's files, assets, tables, values or text go into Survival's build, mod/, tools/, this repo (docs and
  commit messages included) or a release zip, and nothing here names or credits another mod as the source of an enemy
  change (user, 2026-11-06). Survival's enemy changes are its own: designed from AC8's tables and tuned in Survival's
  own tests.
  One exception, the user's own work (2026-11-06: "Alicorn Special Raid IV is my own mod and I NEED the FA44 that is
  within the files of the Alicorn Special Raid as the Model inside is edited"): the ZFA-44 from the user's AC7 mod
  Alicorn Special Raid IV may be used for a Survival special round: its edited model (the mod's
  Vehicles/Aircraft/uavs/uavs_SM, a CFA-44-based static mesh), its paint (fa44_00_D, fa44_00xMREC, fa44_00_Inst), its
  actor ex_uavs and its weapons, with the AC7 stock assets they use. Source: the user's work folder of
  that mod, Alicorn_Special_Raid_IV (unencrypted; on the user's machine, not in this repo). Never AC7 voice lines.
  The same exception (2026-11-07: "Check this mod out, we fixed the Clouds in this one", "in a previous mod we built,
  this happened and we were able to fix it"): the user's own AC8 mod Orbital Tonitrus Spear Strike (RoGLaser) and its
  cloud fix for the Spear's rods (each rod's blast at the clouds' height, the sky's ExplosionEffect as Mission 30's big
  one, a little wider: Scripts/sv_decoy.lua's clouds). Read only, from the user's upload; none of its files ship.
  One more, a friend's code (user, 2026-11-14: "Inveigh is a friend of ours", "Merge it"): 1nveigh's Add-on API 2.0
  (PR #7: Scripts/sv_plugins.lua + _api + _env, docs/ADDONS.md, docs/ADDONS_MAINTAINING.md, docs/re/PLUGINS.md,
  examples/addons). Add-ons live in Mods/AC8SurvivalAddons, never in Survival's zip; a run with one is never sent to
  the leaderboard (LB.edited) and none runs while co-op is open. Keep the PLUGINS checks in sv_main / sv_stats / sv_sound
  / sv_leaderboard when editing those (ADDONS_MAINTAINING.md). Other people's PRs still need the user's yes, each one.
- THE TANICORN (docs/re/TANICORN.md): the user's Anomaly boss fused from AC8's Alicorn and Sea Power's Iowa (standing in
  for the Tanager). Its model and art are in art/tanicorn at the user's request (2026-11-10: "you are allowed to push the
  model"); its cooked container ships in every zip WITH THE TANACORN, the public one included since 0.75.60 (the user,
  2026-11-23: "tanacorn gets merged into the public release", "Everything of hers": the Iowa hull and the AC7 crew voices
  in the public GitHub / Nexus zip, her decision knowing both are other games' assets). Round 30's INVINCIBLE FLEET, whose
  boss it is (docs/design/INVINCIBLE_FLEET.md), goes with her: its Lua in DEV ONLY blocks, kept in every zip with her
  (tools/strip_test_only.py takes them out of every zip; package_dev.sh keeps them; THE TANICORN's test mount too;
  tools/dev_only.py cuts sv_tanicorn (and its pieces _rise, _hits) / sv_fleet (and its pieces _storm, _round, _lasers, _surface, _capture) / sv_cine to their headers in a TESTER zip). Its live parts' world data
  (child descs importing the container's blueprints) is built with TANI=1 only: such a build leaves build/install/tani_wd.txt,
  and package_release.sh / package_test.sh refuse it (package_dev.sh takes it with TANI=1 only, and TANI=1 only with it).
  Run tools/tanicorn/build.sh to the end BEFORE `TANI=1 build_all.sh`: build_all stages the container it finds, and a
  world data importing blueprints the container lacks must never be packaged (the reviews of 2026-11-12).
  tools/tani_container.py holds that: check_tanicorn_build stops a TANI=1 build whose container lacks a class its world
  data imports (or whose hull doesn't import every part) and pins the container's sha256 in tani_wd.txt; build_all.sh,
  package_dev.sh and package_release.sh refuse a staged copy that isn't that container (a marker older than it too).
  One exception, the TESTER zip (user, 2026-11-12: "nah nah add the tanacorn and the fleet"): `TESTER=1 TANI=1
  package_release.sh` on a TANI=1 build keeps her container, the Tanicorn world data, sv_tanicorn / sv_fleet whole and the
  DEV ONLY blocks (the rise director sv_cine still cut), only when the staged container holds every blueprint the world
  data names; the zip is named ..._TANACORN. Everyone plays round 30 (user, 2026-11-18: "Everyone gets the invincible fleet
  level", "But only alyssa has the keys that activate it for everyone"): `FRIENDS=1 TANI=1 package_release.sh` makes the
  friends' ..._TANACORN zip from the same TANI=1 build as hers, staged as a tester's with its test keys off
  (tools/no_test_keys.py); same build, same version, so they link in co-op. TANI=1 needs TESTER=1, FRIENDS=1 or PUBLIC=1
  (the public zip: packed as the friends', the loggers quiet, the ini's TEST ONLY sections out, her lasers' Laser7 kept,
  the public name; zip_leak_test checks it).
- DISTANT THUNDER's round is retired (user, 2026-11-18: "It was replaced by Invincible Fleet instead"): its round and test
  keys are cut; only its storm pieces stay, for the fleet's night storm (docs/re/THUNDER.md).
- Nothing of DISTANT THUNDER (the lightning Anomaly, docs/re/THUNDER.md) goes into a release build (user, 2026-11-14;
  retired 2026-11-18): no way to start its round, nothing of it in the ini. Its storm pieces (sv_anomalies_dev.lua's
  THUNDER bolts and clouds) ship in every zip with THE TANACORN: the fleet's night storm calls them. THE TANACORN was in
  that rule too until 2026-11-23 (above). tools/checks/zip_leak_test.sh opens every release zip and checks both. TESTER
  zips stay as the user set them (2026-11-03, 2026-11-12).
- Release zips always go to the main tree's build/release (git's main working tree), from any worktree (user,
  2026-11-07): tools/package_release.sh and package_test.sh find it through tools/release_dir.sh (`RELEASE_DIR` in
  `.env` overrides it).
- The runtime's leaderboard address and key come from the main tree's leaderboard/submit.local from any worktree
  (runtime/build.sh: .env's SV_LB_LOCAL, this checkout's, else the main tree's). Every 0.74.0-0.74.8 build was made in a
  worktree without it and could send no run; package_release.sh online and package_dev.sh now refuse a runtime without
  it (build/runtime/submit_cfg.h). A build's log must say "leaderboard: runs go to ...".
- Survival's own build: `tools/build_all.sh` (see tools/README.md). Packages are generated into `mod/Content`
  by `tools/build_survival.py`. Edit that script, not the binaries. The container is `SurvivalMode_P`, packages live under `/Game/Mods/SurvivalMode/`.
- Survival Mode is its own mod: never repoint or override Stonehenge Returns' (or any other mod's) files or mission slot.
- Shared stock tables (DT_LiveMissionTable, DT_LiveMenuMainTopCommands, ...) are never overridden: Survival's rows live in
  its own tables (`/Game/Mods/SurvivalMode/Data/DT_SV_*`) and the Lua runtime adds them with AddRow at run time.
- Native runtime: `runtime/survival_rt.c` (UE4SS C++ mod, plain C + LLVM). It hooks the menu like Stonehenge's main.dll
  (`docs/re/STONEHENGE_MAIN_DLL.md`) and must keep chaining onto Stonehenge's hooks, never replacing them.
