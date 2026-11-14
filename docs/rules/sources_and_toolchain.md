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
  model"); its cooked container still ships in TANI=1 dev builds only (package_release.sh drops it). Round 30's
  INVINCIBLE FLEET, whose boss it is (docs/design/INVINCIBLE_FLEET.md), is the user's dev install only too (user,
  2026-11-10: "Keep it dev install only"): its Lua in DEV ONLY blocks, never in a release or TESTER zip
  (tools/strip_test_only.py takes them out of every zip; package_dev.sh keeps them; THE TANICORN's test mount too;
  tools/dev_only.py cuts sv_tanicorn (and its pieces _rise, _hits) / sv_fleet / sv_cine to their headers in a TESTER zip). Its live parts' world data
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
  data names; the zip is named ..._TANACORN. TANI=1 is refused without TESTER=1: never in a friends' or Nexus zip.
- Nothing of DISTANT THUNDER (the lightning Anomaly, docs/re/THUNDER.md) or THE TANACORN (and her INVINCIBLE FLEET) goes
  into a release build, friends' or Nexus (user, 2026-11-14: "Anything that has to do with Distant Thunder or Tanacorn
  does not go into the release build"). Their Lua stays in TEST ONLY / DEV ONLY blocks or test-only pieces, their assets
  in their own containers; tools/checks/zip_leak_test.sh opens every release zip and fails on either (no Tanicorn
  container, no DEV ONLY Lua, no Thunder trace in its Lua or ini). TESTER zips stay as the user set them (2026-11-03,
  2026-11-12).
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
