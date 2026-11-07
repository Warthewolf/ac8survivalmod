# AC8 Survival Mode: build history

Every build's notes, oldest first, moved here verbatim from AGENTS.md on 2026-11-07 so sessions don't load them
(AGENTS.md keeps the rules, the layout and the how-tos). Add each new build at the END. Search it rather than
reading it whole: grep for a version (0.74.4), a feature (ESCORT, VALKA) or a log line.

## Economy review build (Lua 0.70.x, runtime 0.19.0, 2026-10-25; untested in game)
The Claude Docs "Economy, Enemies & Allies Review"'s proposals, all built on branch `feature/economy-review`: waves,
late-round scaling, raids from one direction with escorts, the jammer, more airframes, kill attribution by side
(DamageHistoryMap), WINGMEN, ally orders, repairs between rounds, FULL REARM, upgrades, tactical items, SECOND CHANCE,
a 5-page STORE. tools/re/ECONOMY_REVIEW.md lists every mechanism and the log lines to check. None of it is a hard rule
until a test confirms it. A build without VALKA: `NOVALKA=1 sh tools/package_release.sh online <version>`.
`python -X utf8 -I tools/checks/ini_check.py` checks survival.default.ini against CFG (build_all.sh runs it).

## Enemy behaviour build (Lua 0.72.0, TestBranch_Behavioural; untested in game)
The Claude Docs thesis "AC8 Survival Mode: Enemy Behaviour Reference & Challenge Thesis"'s nine proposals, all built on
branch `TestBranch_Behavioural` (from tag stable-1, 2026-10-29), COOP_TAG -coop.18: fighter roles (P1: the pool split
into Duelists, Lancers, Wolf bait-and-trap pairs and Skirmishers, each its own behaviour set and airframes; 7 new
Scripts/ai scripts), the squad director (P2: cover the tailed, spring the trap, bracket salvos, top cover, pincers,
regroup; Scripts/sv_director.lua), tells (P3: a radio line before each threat, 61 stock lines cloned into DT_SV_Radio,
no HUD callout since the clean up below; Scripts/sv_tells.lua, co-op "tl"), the intensity director (P4: each player's
intensity and comfort, wave holds, pushes, the spikes as a ceiling; co-op "in"), a harder tailed plane (P5: every reaction pick moves, live provoke
60 deg / 1.5 s from Veteran, a 4 Hz tail watch), the learning layer (P6: your habits countered, kept in
config/survival_profile.ini, each game's own), boss phases (P7: MINDRIPPER's pack, AB.L..IN's three phases, a Ladon's
rage, the ALICORN's deck launches), late rounds (P8: +3 aircraft a round from 26 to 60 by 35 in more waves, health
capped at x1.5, the attack throttle's presets) and ace personalities (P9: each squadron's own roles, an opener at first
contact after its tell, Wraith's and Harvest's lead blinking off your six), plus the roadmap's seven measurements
(Scripts/sv_stats.lua: `stats:`, `kill-time:`, `death:`, `tailed:` lines). Every mechanism has its own `enabled` in
survival.ini but two that are build data: P5's reworked reaction trees (LA_SV_ProvokeNear / LA_SV_Escape are packaged
and built at level load, hard rule 20; `[ai] reactions = false` gives the stock 0012_CP ones, not stable-1's; P5's live
provoke has its own, `[ai] tier_provoke`, `provoke_stricter`, `provoke_cone_deg` / `provoke_time_s`) and P1's Lancer
band (the six Lancer units' 9 km in the world data, kept with `[roles] enabled = false`).
tools/re/BEHAVIOUR_DIRECTOR.md has each unit's build, CFG keys, log lines and untested pieces, and one
test checklist for the whole branch (per proposal: what to look at in game, which log lines prove it);
`python -X utf8 -I tools/checks/stats_report.py <log>` tabulates a test log. None of it is a hard rule until a test
confirms it. Checks without the game: the contract's (lua_check on Scripts/*.lua and Scripts/ai/*.lua, shapecheck on
changed behaviour scripts, lua_load_test, menu_test, coop_settings_test, coop_ground_test, ini_check, menu_pages_test),
each unit's own (stats_test, tailed_test, late_rounds_test, tells_test, roles_test, director_test, intensity_test,
profile_test, bosses_test, aces_test, and the code review's coop_landing_test, hud_info_test: tools/README.md's checks
row), coop_test, and a full `sh tools/build_all.sh` (819 triggers, 1588 execs, 721 radio rows). shapecheck isn't in
the repo: `python shapecheck.py <file>` from build/research/ai/survey/ (research output on the build machine with the
stock LA_ scripts it reads, gitignored with build/); build_all.sh doesn't run it.
Code review of 2026-10-29 (fix units F1-F7 on the same branch, no VERSION / COOP_TAG bump; untested in game;
BEHAVIOUR_DIRECTOR.md's last section has each fix, its log lines and what stays open): Bounty's Lancers and Valkyrie's
Wolf pairs are never turned by the director's cover or P4's push (ROLE.ownSet: only Harvest's tier keeps its levers on
a role flight); the ALICORN's railgun and VLS tells, warning, orders and volleys stop once those parts are destroyed;
a joiner's Skirmisher cut is no longer sent to the host as a hit; the learning profile's file is written whole and never
lost (.tmp / .bak / .old); cover and the trap work for joiners past [director] players 4; a host down at the airfield no
longer holds the room while another player flies (the co-op section above); and, at the user's request, the HUD info
key: I ([hud.info]) keeps the CO-OP, ALLIES and ITEMS rows hidden until pressed, each shown peek_s 5 when its news
changes, open the CO-OP row has a line a player (tools/re/HUD_LAYOUT.md; a release key, not a test key; keyboard only).
Clean up of 2026-10-29 for the next build (user, playing 0.72.0: "remove the hud warnings that we added, it's too much,
keep the Voice lines though", "keep the bomber direction warnings"; not yet run in game; BEHAVIOUR_DIRECTOR.md's "Clean
up of 2026-10-29" section): every tell is a radio line only (CFG.tells' hud / urgent / text and the HUD's urgent path
gone, the HUD-only lancer / skirm / split tells and [roles] tells too, the ALICORN's deck and a Ladon's rage callouts),
one gap (radio_gap_s) between any two tells, a `sure` tell (a boss's phase, a squadron's first call) said through the
gap and its cooldown; "tl" carries one number. stable-1's callouts stay (ROUND, the specials', BOMBER RAID FROM THE
<DIRECTION> and the NEXT row's raid line), as do the stock RAILGUN WARNING and the I key. Quieter logs: `[log] verbose =
false` (CFG.log, logVerbose()) keeps out the `ai:` lines, the flags line on every counter's change, the enemies alive /
nearest and the intensity scores every 10 s; `ammo: now` comes at most once a minute, `perf:` every 5 minutes; true
brings them all back.

0.72.1-coop.19 (runtime 0.28.4; the user's requests while playing 0.72.0, 2026-10-29; none of it run in game yet): that
clean up; the music player's pause hold from Survival's spawner's game instance (it never engaged before: every log's
"clock held 0 ms"; tools/re/MUSIC_RADIO_CAMERA.md); SV_Version() the build's own version (was a fixed "0.27.0"); the
heavy bombers' routes over the runway and figure-8s across it (tools/re/AIRFIELD_SUPPLY.md 2); the jammer's ECM pod
fired every 14 s (RE_SV_JamEcm_NN); the Ladons' VLS missiles 10 damage, half the turn rate, also on pooled ones in
flight; co-op stand-ins wait up to 5 s for their player's airframe (COOP.md 5); stronger AA guns / SAM sites and a STORE
CIWS at four spots by the runway on a new DEFENCES page (AIRFIELD_SUPPLY.md 4). Planned next (researched, not built):
co-op weapon / gear / afterburner sync and a co-op revive with a spectator camera.
0.72.2 (runtime 0.28.5; the user's co-op requests of 2026-10-29; not yet run in game): each player's missiles, gun,
flares, gear and afterburner shown on their stand-in on the other games (tools/re/COOP.md 8: "fx" shots relayed by the
host, state bits 16 / 32 / 64 / 128, SV_CoopFire / SV_InputNow; the stand-ins fly damage-0 `<row>_svcp` rows, a
joiner's "ht" backstop; [coop.sync]; tools/checks/coop_fire_test.sh); co-op revives (Scripts/sv_down.lua, COOP.md 9):
held at a 0.1 HP floor, a shot-down player is DOWN (hidden, flown round the airfield by SV_Down, watching another
player's plane through a camera added to it, O the next), any other player at their airfield buys them back from the
STORE's AIRFIELD page (REVIVE <NAME>, 5000 x 1.5 a revive (2500 x 1.25 since the user's "lower the cost for reviving", 2026-10-30), checked by the host: dw / rv / rb / rx / ro / rc), everyone
down ends the run (RE_SV_RunOver, Mission 15's MissionFailed); [coop.revive]; tools/checks/coop_revive_test.sh.
After 0.72.3 (the user's co-op run of 2026-10-30, not yet a build): the revives' floor never held, because the game's
SetMinHealth keeps whole health points only (0.1 -> 0; tools/re/KILLS_HEALTH_DEATH.md 1): the host was shot down from
40 HP in round 8 and the run restarted at round 1. INS.tick now writes the MinHealth field. The shuttle's whole pad
is taken off after liftoff (its objects recorded as spawned; the 1.5 km sweep missed the control centre).
0.72.4 in game (the user's co-op run of 2026-10-30, 13 players): the floor held and revives worked (VERDA DOWN at
13:38:56, revived by the host from the STORE at 13:41:22), but VERDA had crashed into the ground, so the loiter never
lifted the plane and respawn loiter brought them back where it lay. Since then (not yet a build): a DOWN plane slower
than 40 m/s (or under the sea) for 3 s comes back the native way (SV_Respawn 4 km out from the runway, 500 m up).
The same run, the host DOWN in round 6 (runtime 0.28.6): the loiter flew the plane upside down at 15 m over the sea out
of the combat zone (its roll probe read -3 / +2 deg/s as a sign: wrong), the mission failed and restarted in round 7 in
the same level with the SAME plane, which stayed hidden (no third-person view) with its weapons off. Runtime 0.28.7 (not
yet run in game): longer probes, DN_MIN_DIFF 10, an in-flight sign check (rates against the inputs flip a sign) and a
dive backstop (tools/checks/flight_test.c's late plane and wrong-signs runs); sv_down.lua puts the plane and view back
after a restart while down (restoreAfter), remembers your own view as you go down, and puts a DOWN plane 8 km from the
combat zone's edge back over the airfield (edgeGuard, SV_Respawn).
The same run's logs (the host and 7 joiners, 0.72.4-coop.22 / runtime 0.28.6; report: Claude Docs "AC8 Survival Mode:
Co-op Play Session Report, 30 Oct 2026"): enemy copies never failed a move; Shazzy's DOWN probe read -2 / +1 deg/s as a
roll sign too (inverted); reliable resends tracked the round trip (fixed 250 ms timer: 4-7 % resent past 290 ms); a lost
link was flooded (20,892 resends a minute); the host streamed planes and enemies to players in menus or loading (one on
Stable 1 for 14 minutes); joiners kept their money and upgrades through the host's restart; 1,093 of 1,094 refused
remote shots came while that player was in the STORE; the Lua tick averaged 9-30 ms (worst 86-493 ms), "shop" / "icons"
/ "ammo panel" walking every object down at the airfield. Changed since (not yet a build, not yet run in game): runtime
0.28.7's coop.c (CoRto: resend after the round trip x 1.5 + 100 ms, backing off; a lost link gets its oldest reliable
message only; CoWantsState: Q and E only to a joiner whose plane is in the level; CoTrackOffset / CoRenderDelay: each
sender's interpolation delay follows its lateness, CO.delay to 300 ms; new log lines `enemies drawn N ms behind the host
(lateness N ms)` and `coop: planes here ...`), sv_coop.lua (a joiner's run starts over on the host's new run:
newRunHere; others' shots not asked of the game while your STORE is open; the afterburner flip logged once),
sv_core / sv_shop / sv_main (landingWindows once a tick; the relabel reads the STORE rows' TextBlocks only, at once after
a press, else every 2 s; shop texts every 0.5 s at the airfield; an ammo panel looked for 3 times at most; the perf line
names every part by its share and the untimed rest).
0.72.5-coop.23 (runtime 0.28.7; the user, 2026-10-30, after that run: "EA-18G player used his ESM and it didn't show up
for any of us"): an ESM / jamming pod fires no projectile, so the weapon sync never saw it; now a special weapon's count
dropping with nothing new in flight is sent as `e` and fires the stand-in's ECM pod (tools/re/COOP.md 8). Not yet run.
0.72.6-coop.24: a new DOWN clears the last revive's 15 s guard (a player down again within 15 s of a revive was refused
"ALREADY BEING REVIVED"); the revive test now has a joiner reviving the host (never run in game: in the run of
2026-10-30 nobody bought the host back).
Since 0.72.6 (not yet a build or run): the user, "someone who was flying the FA-36 was registering as flying the F-16"
(it was gloom, and xX_spagooterpoop_Xx): 12 of AC8's 34 player planes (BP_PlayerPlane_PPnnnn_<code>, build/research)
weren't in CFG.coop.airframes, so their stand-ins flew the default F-16C. Now all but the ADFX-02 (no AI plane): 10 new
stand-in rows from the plain campaign enemy rows (build_survival.py POOL_EXTRA: OP1018_fa36_01 ...), the F-14A on the
F-14D; an unlisted plane is logged; a hello sent with no plane is followed by the airframe (sendHi keeps M.myRow).
The plain EA-18G row (OP1010_e18g_01) has NO ECM pod (only the named aces' rows carry NPC_FCS_ECM000): the stand-ins'
copies of the EA-18G / EA-36 / E-6B get it in their first free slot (the ESM display), and the enemy jammer's rows get
the held-up pod in slot 3, which RE_SV_JamEcm fires (it fired the random special weapon there before).
0.72.7-coop.25 (runtime 0.28.7) = all of the above: built, packaged (build hash 73655d02...4c760f) and INSTALLED
2026-10-30 (0.72.4 backed up in build/backup/install_before_coop25_0727). Not yet run in game.
AC8's Online Mode syncs player weapons with Strix messages (exe strings, jp.co.soft_gear.strix...game.FLiveMessage*):
ExplosiveWeaponFire (WeaponData: WeaponNumber, WeaponNetworkId, SpawnSlotIndex, InitialLocation / Rotation / Velocity,
TargetNetworkId, LockonNum, RandSeed), BulletWeaponFire, HoldingMachineGunButton, InstantWeaponFire,
ElectronicMeasureFire / Effect (ESM / ECM), SpecialWeaponArmed, LockedTarget, PushFlare, EscapeByFlare, LandingGear,
FlightEngineInput, Damage, RespawnRescueTry / Result; the remote player is a real ALivePlayerPlane firing its own
weapons (COOP.md 6). Every message name is referenced from one function, 0x1452a5010 (likely their registration). Research
only, nothing built on it.

## COOP2MP (branch COOP2MP, from 0.72.7-coop.25, 2026-10-30; nothing new run in game)
The user: "everyone is using their player aircraft and not an AI stand in", "Start a new build called COOP2MP". The
other players as real player planes (ALivePlayerPlane, as AC8's Online Mode shows them) with their own weapons, instead
of AI stand-ins. VERSION 0.73.x, COOP_TAG -coop2mp.N, zips `BUILD_NAME=COOP2MP COOP=1 NOVALKA=1 sh
tools/package_release.sh online <version>`. tools/re/COOP2MP.md has Online Mode's research (its Strix weapon messages)
and the tests T1-T5. T1 / T2 (0.73.0, test of 2026-10-30): a role-2 player plane with its tick off and moved every
frame holds formation but has no animations, afterburner, HUD box or enemy attacks. T1c (0.73.1-coop2mp.2, runtime
0.29.1; not yet run in game): its tick left on and its own RemoteUpdate (0x147d6f0c0, kSigRemoteUpdate) fed each frame:
SV_CoopFeed writes a pose, speed, State and stick into its network object's physics message and input (COOP2MP.md). T1c in game
(2026-10-30): it flew beside you on all three airframes, control surfaces working, but no afterburner glow and no enemy
attacks. T1d (0.73.2-coop2mp.3, runtime 0.29.2; not yet run): the glow from your plane's afterburner amount
(plane+0x39d0, written before the surface update reads it) and half the enemies ordered onto the copy
(EngagementOrderOverride TargetFirst; Survival's orders name "Player", which is your plane only). T1d in game: the
glow and the ordered attacks worked (a missile exploded on the copy) but its health never moved, and Quit Mission
crashed: N+0x170 is a TSharedPtr to the input message, and the feed wrote the stick over its controller. T1e
(0.73.3-coop2mp.4, runtime 0.29.3; not yet run): the input through the pointer, and the hits on the copy logged at the
player plane's damage (0x147d5a430). T1e in game: the copy took your stick, the hits reached the
damage and were refused (40 asked, 0 taken), Restart and Quit Mission ran clean (hard rule 53). T3 (0.73.4-coop2mp.5,
runtime 0.30.0, co-op protocol 4; not yet run in game): the other players as their real planes in co-op ([coop]
real_planes, the AI stand-in as the fallback), fed from their stream with a flight block (stick, afterburner, speed,
State); the host's split hunt and the director's joiner tactics order flights onto a real plane (COOP.huntReal); their
weapons and gear on real planes wait for T4; damage as 0.72 (each game's own). COOP2MP.md "T3 build". Online Mode's
weapons research (COOP2MP.md): AI shots are decided on the target's game, a player's on the shooter's (CanBeDamagedBy);
a player's shot is shown elsewhere by the remote plane fire 0x147d71ea0 launching it from their plane's own weapons.
T4a (0.73.5-coop2mp.6, runtime 0.31.0; not yet run): solo, the Ctrl+F11 copy replays your launches, flares and gun that
way; the friends' zip 0.73.5 replaces 0.73.4. T4a in game: missiles, flares and gun replayed, the laser not (not
an explosive weapon). T4a.2 (0.73.6-coop2mp.7, runtime 0.31.1; not yet run): specials (laser, bullet, ESM / ECM) the
handlers' way (select, arm), the gear; SV_CoopPPFx gives co-op's real planes their gear, gun and flares from the flag
bits; zip 0.73.6 replaces 0.73.5. T4a.2 in game: the laser armed but didn't fire, the gear didn't come down
(State bit 9 is gear down, and the feed cleared it). T4a.3 (0.73.7-coop2mp.8, runtime 0.31.2; not yet run): bit 9 sent,
the laser launched from the copy's own weapons; zip 0.73.7. T4a.3 in game: the laser fires from the copy; the ECM / ESM and the gear
not. T4a.4 (0.73.8-coop2mp.9, runtime 0.31.4; not yet run): the ECM / ESM launched as the laser; the gear moved as
RemoteUpdate's own check does (FlGear: the copy's own State never keeps the gear bit sent); zip 0.73.8. T4a.4 in game: the
ECM launched (not seen), the gear raised again every frame: a remote plane's second flight engine (+0x3c60, loaded from
the message and simulated) makes the State's gear bits from its own gear. T4a.5 (0.73.9-coop2mp.10, runtime 0.31.5):
both engines' gear moved; zip 0.73.9. T4a.5 in game: the gear still lowered and raised again every frame. The
check's flag (engine +0x34 bit 0x10) is the input's flags byte (input message +0x20 = BuildFlightInput's out+0x18:
0x10 = State bit 9), and the feed wrote it as a fixed 4; State bit 9 is the engine's gear state +0x710 != 0. T4a.6
(0.73.10-coop2mp.11, runtime 0.31.6): your input's flags byte fed (co-op's real planes: 4 | gear from State bit 9),
a log line a second with both engines' flags and gear state; zip 0.73.10. T4a.6 in game (2026-10-30): the copy's gear
came down and went up again, each moved once (flags 0x10 on both engines while down; own engine's gear state 1-3, then
0); the solo copy (T4a) now replays missiles, flares, gun, laser and gear. ECM / ESM still not seen on it.
T4b (0.73.11-coop2mp.12, runtime 0.32.0; not yet run in game): the other players' launches on their real planes in
co-op. Each game's own launches (PlaneWeaponsFired on its plane while co-op is open: kind, weapon number, spawn slot,
seed, lock-ons, start against the plane, rotation, velocity, target) come out of SV_CoopShots and go in "fx" as
`p:<target id>:<age>:<shot>`, relayed by the host; a game replays them from that player's real plane (SV_CoopPPShot:
the remote fire for missiles, FwLaunchDirect for the laser and ESM / ECM, a bullet special armed), the AI stand-ins
keep m / s / e. Each player's loadout (SV_CoopLoadout, "a,b/c/x,y") rides in hi / pi (a 7th field) and their real
plane is spawned with it (SV_CoopSpawnPP's 8th argument), again when it changes; so their weapon numbers mean the
same weapons here. tools/checks/coop_fire_test.sh covers the Lua side; zip 0.73.11.
T4b in game (2026-10-30, the user and a friend, 2 players): it worked (the ADFX-02's loadout given, its laser, missiles
locked and not, and flares from its real plane). Two problems: (1) the friend changed specials at the airfield, their
loadout changed, and the user's game replaced their live real plane: it crashed a frame on (access violation reading
the destroyed plane +8, in game code 0x147443726 that checks a held object's flags; the crash report's call stack runs
through 0x1474703c0 / 0x147434e50 / vfunc +0x60). Never destroy a live real plane mid-level. (2) The spectator camera
on a real plane showed its cockpit: a player plane carries cameras of its own and the view takes the first active one.
0.73.12-coop2mp.13 (runtime 0.32.0; not yet run in game): a changed loadout is kept for the next level's plane (logged,
no respawn); the watched plane's own cameras are switched off while you watch it and back on after (sv_down.lua hush,
logged once a plane; tools/checks/coop_revive_test.sh); zip 0.73.12.
0.73.22-coop2mp.23 (runtime 0.32.4; built and installed 2026-10-31, not yet run in game; zip 0.73.22, hash b7d19c51...0590e0):
the co-op run of 2026-10-30 on 0.73.20, round 8: both Ladons shot down (their bodies "down") but the round never ended
("it still says both LADONs are alive"): SV_UnitAlive counts the unit's AliveChildAIGameObjects (body + 24 parts) and
the parts lived on; MISHKA's VLS fired on after its body was gone (four players down 0-4 s after it, the host from 100 HP
in one hit, all of it from BP_OP0045_ladn_VLS_L_Base: a sure kill, never toned since its own fire control fires it
pooled, outside Survival's volleys). Now (sv_ladon.lua) each Ladon's parts are recorded as SV_Spawn makes them
(LADON_PARTS, spawningUnit: host and joiners' copies), finished off when its body goes down (ladonPartsDown, from the
round probe: `special: <unit>'s body down: N of its M parts still up finished off`), the round counts a Ladon down when
its body is (`special: Ladon X's body is down, N of its unit still up (its parts): counted down`), and while a Ladon is
up (+40 s) every Ladon missile is toned every 0.5 s (`hits: a Ladon's sure-kill missile caught at damage N`).
tools/checks/bosses_test.sh covers it. Not yet known why the parts lived (a kill with no attacker since 0.73.20?).
0.73.23-coop2mp.24 (runtime 0.32.4; built and installed 2026-10-31, not yet run in game; zip 0.73.23, hash 6bc1a200...6d28bc;
replaces 0.73.22): the joiners' STORE allies and defences (user, 2026-10-31: "some people spawned AI aircraft in from
the shop, as well as Anti Air etc at the airfield and none of it was syncing with the other players"; the logs: a
joiner's WINGMEN, MOONCHILD, AEGIS, AA guns, SAM sites and CIWS only ever in their own game, since only the host's
SV_Spawn is mirrored, and a joiner could take a unit name the host built later). Now (sv_shop.lua, sv_coop.lua,
sv_allies.lua) a joiner's purchase of an allied flight or ship or a defence goes to the host ("ab|id|item|price|kind"),
paid on their game at once; the host builds it (shopBuildFor: the unit picked there, nothing charged there; its spawn
goes to every game as its enemies' do) and answers "ak" or "ax" (refunded), "ar" later for a flight that never took off
(refunded to that player); no answer in 30 s: refunded. A joiner's flight takes off once that player is airborne
(COOP.airborne), else 90 s on. The allies' orders are the room's: a joiner's change goes to the host ("ao"), the host's
to everyone ("ag"). On a joiner's game the host's allies' copies (ALLY.unit and the defences' units, c.ally at bind time)
send no hits: what they take isn't sent, and their hits on enemy copies are taken off what is (the stand-ins'
backstop), so the host's allies' fight is dealt once, on the host. Log lines: `shop: player N's <item> (<price>): built:
...` / `refused: ...` (host), `shop: asked the host to build ...`, `shop: the host built your ...`, `... refunded`
(joiner). Not yet: a joiner's HUD ALLIES row shows the defences but not the room's flights and ships; COVER still
covers the host. tools/checks/defences_test.sh and coop_ground_test.sh cover it.
0.73.23 in game (2026-10-31, gloom hosting dukka, Kalash and Saint Alessia, to round 15; report: Claude Docs "AC8
Survival Mode: Co-op Session Report, 31 Oct 2026"): the joiners' purchases built by the host (12 of 12) and the aircraft
names on the boxes worked; no Ladon round. Three joiners crashed, the same stack each time (access violation in UE4SS's
UObject property lookup, UStruct::FindProperty -> FField::GetClass, from a Lua read), each 4-9 s after a resync ("rs")
took every copy down and the host's defences were spawned again at the same count: sv_allies.lua defenceHealth kept its
cached defence actors (rebuilt every 30 s or on a count change) and read HealthInternal / MaxHealth every 2 s with no
valid(), so freed actors were read. Also: the host answered 71 "jn" in 63 minutes (strays -> jn -> rs tears everything
down -> re-spawned flights often unbound -> the next strays; 57 partly bound flights on one joiner), and each teardown
paid the joiner for the copies it took down itself (5-14 kills, 750-2,230 zollars). 0.73.24-coop2mp.25 (runtime 0.32.4;
built and installed 2026-10-31, not yet run in game; zip 0.73.24, hash 6a5ca5dd...63eb54; replaces 0.73.23): the defence
list checked and pruned (valid, health > 0; ALLY.forgetActors on a joiner's teardown); copies a joiner takes down itself
(killCopy's torn: rs, strays, a flight's last copies) not paid (COOP.tornDown, `round probe: ... taken down here (co-op,
not a kill ...)`); the "planes bound" line names the generation spawned and the host's last ids for it (why the binds go
missing after a resync is still open); a joiner's ALLIES row shows the room's flights and ships (ALLY.roomCode, "rnd"
field 10: "m<n>w<n>s<n>"); COVER on a joiner's flight guards that joiner while their real plane flies (its area the
hunt's, each plane onto the enemies nearest them, COOP.coverFor; else the host as before). Untested in game: whether
EngagementOrderOverride works on an allied plane onto an enemy. Lesson (not yet a hard rule, unconfirmed): any Lua list
of game objects kept between ticks must check valid() before each read and drop what's gone at once; a pcall doesn't
catch a freed object's access violation.
0.73.25-coop2mp.26 (runtime 0.32.4; built and installed 2026-10-31, not yet run in game; zip 0.73.25, hash
98a359a9...ecd30d4; replaces 0.73.24): the info wall (user, 2026-10-31: "an information wall that appears in the center of
the screen on a button press and hides on a button press. Similar to how the end of round information screen works";
with more than 3 players the corner's CO-OP lines had no room). The I key opens and shuts a centred panel styled as the
run's summary: every co-op player (name, HOST / YOU / LOST, aircraft, FLYING / AT THE AIRFIELD / DOWN / NOT IN THE
MISSION, health; two columns from 9, all 24 fit), then ALLIES, ITEMS and the run's kills (sv_hud.lua wallBuild /
wallRows / wallTick, sv_coop.lua COOP.wallInfo, CFG.hud.wall, CFG.hud.text.wall_*). The corner keeps NEXT always and
ALLIES / ITEMS / CO-OP as peeks (no player lines any more), hidden while the wall is open; each level starts with it shut
(start_open: open). tools/re/HUD_LAYOUT.md has the layout, log lines and checklist; hud_info_test.sh 79 checks.
0.73.25 in game (2026-10-31, the user hosting dukka, Shazzy, Saint Alessia): Shazzy's link was lost, the host dropped
them at 90 s ("po" to everyone, which Shazzy's game, cut off, never got) and their link came back 29 s later as a "link
back" on their side, not a new pairing; their game still listed itself on the host's roster so never said hello again,
the host had their plane's stream and no hello, and after AIRFRAME_WAIT_S spawned the default F-16C AI stand-in, which
stays for the level (an AI plane up can't change airframe; nothing is replaced mid-level). Since (not yet a build or run):
the host asks a player whose plane streams with no hello for one every 3 s ("hq"; `coop: player N's plane streams here
but no hello from them: asked for it (hq)`), the default waits HELLO_WAIT_S (30) with no hello at all (5 with an empty
one, as before), and a joiner says hello on "hq" (once a second at most) and whenever its link comes back.
coop_landing_test.sh covers it. Built as 0.73.26-coop2mp.27 (runtime 0.32.4; installed 2026-10-31, not yet run in game;
zip 0.73.26, hash 294ad410...d428122; replaces 0.73.25).
0.73.26 in game (2026-10-31, five players): the host crashed 400 s in (09:22:24), access violation reading -1 at
0x147f7c340, the stack RemoteUpdate's call (0x147d646dc) -> main.dll's detour -> the remote fire 0x147d71ea0 (+0x50b) ->
the spawn slot's lookup 0x147f7c300, replaying a joiner's launch on their real plane (player 5's first, an FA-36 that had
joined 35 s before). 0x147f7c300(launcher, weapon, spawn slot) indexes the launcher's weapon table ([launcher +0xb0]
+0x28, 0xa0-byte entries, count +0x30: the game's loop at 0x147f7bbc4) by the weapon number with no bounds check and
reads the entry's slot list +0x78: a weapon number that plane hasn't read garbage. Runtime 0.32.5 (0.73.27-coop2mp.28;
built and installed 2026-10-31, not yet run in game; zip 0.73.27, hash f0c27640...69feba0; replaces 0.73.26): every
replayed weapon (T4b's FnFlush, T4a's copy, FwLaunchDirect) is checked first (flight.c FwWeaponOk); one not on the plane
is dropped and logged (`coop2mp: T4b: player N's shot (weapon W) NOT replayed on their real plane ... here: it has M
weapons`, and the minute line's `not a weapon of their plane here`). The cause (user, 2026-10-31; their logs): that player
(Twelve) ran SPWeaponCustomizer 2.3 (UseHighestCapacity=1, the FA-36 given special slots 19, 21 and 27) and AC8WeaponSwap
1.1.0 (a native library, ac8weaponlib_011.dll); their first shot, a SAAM (BP_plwp_saam_a0_C), went as weapon 2, which
the stock FA-36 spawned from their loadout (specials 23, 21) hasn't. Their other mods (AC8UnitHealth, AC8WeaponValues,
HangarModelFix, SkipIntro) only display or skip menus.
0.73.27 in game (2026-10-31, 8 players): at 10:01 the host and at least five joiners went down within 30 s. The host's,
dukka's and player 5's crash reports are one stack, all game code: an AI unit's per-frame update (0x147cb2850, slot 279
of its class's vtable 0x14c51df10; the class's constructor 0x147cb2430 makes a MainMesh beside the fire control and the
damage state, over a parent shared by 36 classes, so not an AI plane) moving an effect component it holds at +0x2690
(spawned on a sea-plane test, 0x147cb3a23) and checking only its garbage flag; the component had been freed, and the
call through its vtable (0x1442c3e9b) faulted. Which unit isn't known (two AEGIS ships had just been bought; MISHKA had
left one part alive, `1 NOT (still up)`). Shazzy's report (09:43) was the replay again: 0x147f7c300 writes the spawn slot
through the entry's list pointer (+0x78) even when its count is 0, and 0.32.5's FwWeaponOk only checked the list when it
had entries. Runtime 0.32.6 (0.73.28-coop2mp.29; built and installed 2026-10-31, not yet run in game; zip 0.73.28, hash
9b2b218f...abe00e73; replaces 0.73.27): FwWeaponOk checks the list writable and the slot array (+0x58, count +0x60)
whatever the counts; flight.c OnUnitFxFrame hooks that vtable slot (sigs.h kSigUnitFxFrame) and lets go of a +0x2690
component the moment it's marked destroyed (`guard: an AI unit's effect ... let go before it's freed`); and another
build is refused (the user: "add the refuse mismatched builds"): the host's hello answers a joiner of another version
with yourSlot 0xFD and no link (`coop: refused <name>: their Survival is <v>`, Lua "sys|refused" -> REFUSED <NAME>
callout), a joiner on another build than the host's links to nothing and says so ("sys|badver" -> CO-OP: THE HOST HAS
<v>), both ways (an older host doesn't refuse, the newer joiner does). coop_test.sh's 4-player run has a joiner of
another build (refused, never a slot); coop_landing_test covers the Lua side.
0.73.28 in game (2026-10-31, 7 players): the host crashed at 10:44:43, in UE4SS's UObject::ProcessEvent called from Lua
(a method on a freed object), right after every joiner asked for the whole picture at once and a plane of a flight the
director kept aimed died: sv_stats.lua's tail watch KEPT each plane's blackboard (p.bb) between its 4 Hz reads, and the
director's aimsTick wrote TargetActor through p.obj.AIStateComponent.BlackboardComponent with only the plane checked.
0.73.29-coop2mp.30 (runtime 0.32.6; built and installed 2026-10-31, not yet run in game; zip 0.73.29, hash
1dfccdea...0ab2f; replaces 0.73.28): sv_ai.lua aiBlackboard(p) reads the blackboard fresh, valid() at each step (the
plane, its AIStateComponent, the blackboard), none for a plane at 0 health, never kept; aiWatch, ACE.hunt, the
director's aims and the tail watch all go through it (tailed_test covers it). Rule kept since: a game object a Lua part
keeps between ticks is dropped the first time it's invalid, and a component reached through it is checked too. Players on other mods can
make the games disagree elsewhere too: a session should run the same mod set.
0.73.30-coop2mp.31 (runtime 0.32.7; built 2026-10-31, NOT yet installed (AC8 was running), not yet run in game; zip
0.73.30, hash 88faf384...bd23cd; replaces 0.73.29): host migration (user, 2026-10-31: "if the Host does leave, it
automatically tries to find the next best host"; their choices: the round in play starts again, the allies and defences
are built again, the best connection takes over). sv_coop.lua's "host migration" block, [coop.migration] (enabled,
after_s 30, link_s 20, wait_s 60, break_s 15; Steam only). The host ranks its joiners by link (round trip + 2000 x the
share resent, +10000 out of the mission; SV_CoopPeerIds: each link's slot, Steam ID, rtt, sent, resent) and sends the
line with each Steam ID ("sq|<host sid>|slot:sid,..."), the allies and defences up ("al|item:buyer sid,..."), and "hl|120"
before its level reloads at a run's end (DOWN.runOver); "pi" carries each player's Steam ID last. A joiner whose host is
silent after_s (or the host's "hl" time) goes down the line: the first in line reopens as host looking for everyone's
Steam ID (SV_CoopOpen's partner list, now 640 chars / 24 names), takes the copies down (torn, not paid), sets the old
host's plane aside (hidden, never destroyed), starts the round in play again break_s on (a new D; between rounds the
next), holds it while the others aren't back (joinWaiting, wait_s), and builds the allies and defences again 5 s on
(shopBuildFor, free, retried every 3 s up to 10); the others join it, the next after link_s, the old host again when
nobody answers. A host by migration that nobody joined and hears another host joins it again (samerole, migStepBack).
Each real plane carries its owner's Steam ID (P.sid): one back in another slot moves with them (M.slotFix,
SV_CoopSwapPP swaps the native plane refs), one in a slot that's another player's is set aside, one left in this game's
own slot is hidden at once and set aside 10 s on (AI stand-ins stay their slot's unit). Log lines `coop: migration: ...`.
tools/checks/coop_migration_test.sh covers it (the host's line, the takeover, the others, slots, hl, off). Open: whether
Steam P2P links a new host fast enough, the new host's run state beyond D (RUN, AF, specials mid-fight), stand-ins.
0.73.30 in game (2026-10-31, 6-7 players, the user hosting): the user's game crashed at 12:07 and host migration took
over (user: "host migrate worked", "reset the round they were on, allies stayed"): the first in line hosted, round 10
started again, the allies were back. The same session's crashes (none of Survival's own code on the stacks):
- 11:24 (the host, 0.73.29, the Alicorn round) and 12:07 (the host, 0.73.30, round 10's start while Survival recycled
  the flights flown before, destroying their planes): worker threads in a weapon's target search (ParallelFor
  0x1474703c0 -> 0x147434e50 -> 0x147435060, slot +0x60 (obj, query, a, b) -> bool on a family of 151 classes over one
  base): 11:24 in class 0x14cb78378's 0x147443690 (IsA on its +0x18 game object, freed: class NULL), 12:07 in class
  0x14cb77dc8's 0x1474515a0 (its +0x20 weak actor NULL, used unchecked at 0x147450468); the T4b replaced-plane crash was
  the first class too (+0x28).
- 11:57 (gloom, after the Ladon round) and 12:03 (another joiner, round 9's Tu-95 raid): the AI unit effect move
  (+0x2690) past 0.32.6's guard: the effect freed (and its memory reused) while the unit's update wasn't running, so its
  garbage flag was never seen.
0.73.31-coop2mp.32 (runtime 0.32.8; built and installed 2026-10-31, zip 0.73.31, hash 2d0260bd...727735;
replaces 0.73.30): runtime/uobj.h UObjLive / UWeakLive answer from GUObjectArray as the game's own
weak-pointer lookup does (found in 0x147443cb0, which kSigTargetCheck's function calls; tools/checks/uobj_test.sh); the
effect guard lets go of a component no longer in GUObjectArray; flight.c TgtInstall hooks slot +0x60 of the first class
(kSigTargetCheck: +0x18 / +0x28 live) and of every class of the family whose check reads +0x20 through the game's
FWeakObjectPtr::Get (11 of them), answering "not a target" when that weak actor was set and is gone. Log lines:
`guard: GUObjectArray chunks at ...`, `guard: N target entry classes guarded (...)`, `guard: a weapon's target search
skipped a gone unit's entry ...`, `guard: an AI unit's effect ... was freed already (not in GUObjectArray): let go`.
Not yet run in game; watch that targets stay selectable (a wrong "gone" would hide them).
0.73.31 in game (2026-10-31, the user hosting 5 players to an Alicorn round): no crash; the guards loaded on every game
(GUObjectArray found, 10 classes); every skip (14 lines on the host, 4096+ entries in 5 minutes) was one class,
0x147447050, which tests its weak actor itself, so 0.32.8 changed its answers for nothing. Two joiners couldn't target
the Alicorn at all (user: "players go reported the alicorn as untargettable"): on a joiner the Alicorn's 131 parked
pools (put away invincible) were counted as its copies though the host gives them no ids (hostPlane skips
SPC.alcnPool; clientPlane didn't), so 15 s on they were "strays", couldn't be finished ("health 1000 after"), the "jn"
resync's teardown took the Alicorn's tanks and core down there, and the host's fresh one was refused (the old unit
still up: "its last flight is still up (212 alive)"), leaving a hull with no live parts.
0.73.32-coop2mp.33 (runtime 0.32.9; built and installed 2026-10-31, zip 0.73.32, hash dc54b9e5...3fdc5; replaces
0.73.31): clientPlane skips the parked pools (as hostPlane, so the ordinals agree); a
joiner's doSpawn takes a stuck Alicorn copy off whole (RE_SV_AlcnRemove, once) before the host's fresh one
(`coop: the Alicorn's last copy here is still up (N alive): taken off whole for the host's`; coop_ground_test); the
target guard tests the weak actor only in classes that use it unchecked (TcWeakUnchecked: no `test rax, rax` after
the Get, no inline `bts r32, 21` before it: 0x1474515a0, 0x147439690, 0x14743a4c0) and, in the first class, only its
raw +0x18 / +0x28 (it tests the weak itself): 4 classes. Not yet run in game.
0.73.33-coop2mp.34 (runtime 0.32.9; built and installed 2026-10-31, zip 0.73.33, hash 864bda51...712225; not yet run in
game): VOID WATCHER 1 and SNIPER (user, 2026-10-31: Mission 28's AWACS
"Take off from the airfield as a purchasable ally", "Rename it too VOID WATCHER 1", "give it's ESM a huge boost in range
and have it orbit around the airfield"; "rename VIPER to SNIPER and change their standard missiles to LAAM's", "I want
the stock aircraft files touched but for Survival Mode"). VOID WATCHER 1: the E-767 Magnolia (OP0005_e767_MS28: flares,
MS28ESM000 -> BP_FCS_ESM_MS28 -> BP_wp_esm_MS28, class LiveElectronicSupportMeasures) as Survival's row SV_Ally_VoidWatcher
(DT_SV_NpcRows, name key SV_VoidWatcher) on its own world-data unit SV_Unit_VoidWatcher (one AI object copied from
MOONCHILD's lead at Comona Airport, its desc naming sv_ally_voidwatcher on Mission 22's e767_common, so its NLID_1000
behaviour is built at level load; callsign on its box), MOONCHILD's lead's scramble (hold, taxi, roll, climb), airborne:
gear up, not invincible, engagement None, SV_AwacsAir 1, then SV_Path_VoidWatcherOrbit (12 points, 7 km round the
airfield, 4.5 km up, 650 km/h; each lap's end starts it again; tools/survival_events.py AWACS_*, build_awacs). Lua
(sv_allies.lua ALLY.awacsTick, CFG.allies.awacs): the STORE's DEFENCES page row VoidWatcher (12000 Z, one at a time),
takeoff once you're airborne (a joiner's purchase built by the host), its ESM fired every esm.every_s 20 while airborne
(RE_SV_AwacsEsm: WN_WEAPON_2 by Mission 19's LiveFireOneShotWeapon, forwarded in co-op), its ESM fire control
(MS28ESM000_SVA) reaching capture_m 60 km and ready again in 0.5 s, and each new ESM field of class BP_wp_esm_MS28_C
(NotifyOnNewObject LiveElectronicSupportMeasures; an instance, never the class) set to SupportEffectRangeMeter /
EffectRangeMeter range_m 25000 (stock 3200), LifeTime life_s 24; the ALLIES row by name, co-op room code "v<n>",
migration's rebuild item VoidWatcher. SNIPER (was VIPER): name in CFG; its row (Survival's copy of OP1022_f16c_01)
carries NPC_FCS_PlaneLAAM000 where the stock row has NPC_FCS_PlaneMsl000, written at build time
(survival_events.ALLY_WINGMEN_MISSILE, build_npc_rows; the stock row as shipped), then boosted as every ally weapon.
Log lines: `allies: VOID WATCHER 1's ESM on <row>: within N m`, `... taxiing out`, `... ESM fired`, `... ESM field <name>:
support range A -> B m, range A -> B m, life A -> B s`, `... lost N s after it spawned`. Not yet known in game: whether an
E-767 follows the fighter scramble's taxi / roll / climb paths (it's invincible until airborne), whether its ESM fires on
command (as the jammer's ECM does) and whether the field's range takes from an instance set at construction.
tools/checks/defences_test.sh's "VOID WATCHER 1 and SNIPER" and coop_ground_test's room code cover the Lua.
A joiner's crash of 2026-10-31 16:08 (0.73.33, round 11, right after buying WEAPON BAYS' last tier; the machine of
the 12:03 crash): an access violation reading 0xffffffffffffffff inside UE4SS, a recursion of its own (an outer-chain
walk, "...ameInstance_C" and "...etText" on the stack) from Survival's Lua tick: a STORE press relabels the rows at once
(sv_shop.lua relabel: FindAllOf("TextBlock"), nameOf -> GetFullName on each), and a TextBlock whose page was going away
had a freed outer; valid() (UE4SS's IsValid) checks only the object, and a pcall doesn't catch it. 0.73.34-coop2mp.35
(runtime 0.32.10; built and installed 2026-10-31, zip 0.73.34, hash 305a5df9...778a85): uobj.h UObjChainLive (the object and every outer, +0x20, live in GUObjectArray, 64 levels at most;
uobj_test), SV_ObjChain(address) for Lua, and sv_core.lua nameOf answers "?" without asking UE4SS when the chain isn't
live (every name read goes through it; the shore marker's trace-hit name too). Not yet run in game. Lesson (not a hard
rule yet): UE4SS's GetFullName on a FindAllOf result isn't safe in a frame where widgets are being torn down.
0.73.35-coop2mp.36 (runtime 0.32.10; built and installed 2026-10-31, zip 0.73.35, hash 4e9083c3...dbda76; not yet
run in game): (1) raid pings (user, 2026-10-31: "an alert that pings the
aircraft via the minimap that are attacking the airfield"): RE_SV_RaidPing_NN, Mission 22's own LiveBattleNavigationExecution
(its shuttle / control-centre "look here", template Default_PreRadioEvent_28: {tag, unit, Quadruple, false}) on bomber
flight NN's unit; sv_flights.lua raidPings (from bombTick, once a second, the host's or solo: forwarded) fires it every
[bombers.ping] every_s 12 while a flight up and not sent at an allied ship has an aircraft within within_km 40 of the
airfield (`bombers: <unit> pinged on the minimap ...` once a flight; heavy_test). (2) VOID WATCHER 1's ESM never came on
(reported by players on 0.73.33): OP0005_e767_MS28's fire control is NpcFCSId0 PlaneFlr100, 1 and 2 empty, NpcFCSId3
MS28ESM000 (the compact research table had dropped the empty slots), so the ESM is WN_WEAPON_4, not 0.73.33's
WN_WEAPON_2. (3) its box read MAGNOLIA (user: "Delete the MAGNOLIA tag from the EW aircraft"): the model row
OP0005_e767_Ally_Magnolia's GameObjectDisplayName01 is ContainerAllyCallsign_Name_Magnolia; Survival's copy
SV_Model_VoidWatcher (DT_SV_ModelRows, from the campaign's DT_NPC_Model) keeps its blueprint and paint under
ContainerAircraft_Name_e767, the NPC row names it, and sv_allies.lua adds it to DT_NPC_Model at the main menu (not
sold without it). defences_test covers both.
0.73.36-coop2mp.37 (runtime 0.32.10; built and installed 2026-10-31, zip 0.73.36, hash 98898b0f...0defa0; not yet
run in game): VOID WATCHER 1 "just seems to not loiter around the
airfield space" (user, 2026-10-31; no log yet): its orbit was 7 km at 650 km/h (~25 deg of bank all the way round, more
than an E-767 holds), now 12 km at 550 km/h (~12 deg) on 16 points; and its orbit started only at the end of the
fighters' climb-out path, which a big E-767 may never reach (no orbit, no SV_AwacsAir, so no ESM either): Lua's backstop
(ALLY.awacsTick, CFG.allies.awacs.orbit) fires RE_SV_AwacsOrbit (gear up, not invincible, engagement None, SV_AwacsAir 1,
the orbit path) when the climb-out hasn't ended climb_s 60 after takeoff, and again when it's lost_km 18 or more off
(`allies: VOID WATCHER 1 put on its orbit (<why>)`; defences_test). Players' own ESM / ECM affecting only their own game
in co-op (user, the same day): research under way (Online Mode's ElectronicMeasureEffect fills the sender plane's
+0xd88 enemies / +0xd98 allies lists of {weak ptr, flag} through 0x147d27c00; nothing sends those in Survival).
0.73.37-coop2mp.38 (runtime 0.32.11; built and installed 2026-10-31, zip 0.73.37, hash 4ef765fd...f30d98; not yet run in
game): the other players' ESM / ECM fields count on every game. Each plane pulls its electronic effects every tick
(0x147d27d50, sigs.h kSigPlaneEw) from every electronic weapon in the world but skips one whose owner is a remote plane
(role byte +0xED8 == 2, at 0x147d27f34), which co-op's real planes are; flight.c OnPlaneEw sets every OTHER live real plane
to role 1 around that call and back to 2 after, so the stock range / team / time rules apply (`coop2mp: the other
players' ESM / ECM fields count on this game ...`, once). tools/re/COOP2MP.md "ESM / ECM effects across games".
0.73.38-coop2mp.39 (runtime 0.32.11; built 2026-10-31, never installed (0.73.39 has it all), not yet run in game; zip
0.73.38, hash e52b0e3a...e9d3ec): the Spaceport Assault, round 1 (user's special of 2026-10-31; tools/re/SPACEPORT_ASSAULT.md
"Build 0.73.38"): an enemy fleet of 27 one-ship units west of the spaceport (the Ford, 4 Wasps, 14 Aegis, 8 missile boats:
allied descs flipped to Faction 2 on the enemy DT_NPC rows, tools/build_survival.py spaceport_units / enemy_unit), each
Wasp's waves of two LCACs to its beach, their invincible troops driving to the spaceport's capture meter, the Ford's deck
launches, SPACEPORT HELD / CAPTURED, and a first retake (the garrison and the ships left; Mission 19's rockets not yet).
Scripts/sv_spaceport.lua (SPORT), CFG.specials.spaceport, [specials.spaceport*]; SPC.kinds gained ready / busy / over /
row (sv_rounds.lua, sv_hud.lua) and specialFor a special's from_round. Not in the rotation until tested: Ctrl+END /
Ctrl+INS force it (test only). 1211 triggers, 2262 execs. tools/checks/spaceport_test.sh.
0.73.39-coop2mp.40 (runtime 0.32.11; built and installed 2026-10-31, zip 0.73.39, hash 7135b5db...4be518; not yet run in
game) = 0.73.38 + the enemy weapons log (user, 2026-10-31: "a logger that checks what enemy missiles are being fired, I
have a feeling that none of the special weapons we gave the enemies are working"): Scripts/sv_weaponlog.lua (WLOG,
CFG.log.weapons, [log.weapons], on by default). The native LaunchWeapon hook can't see them (0x147f7a880's three callers
are the player weapon system and Online Mode's remote fire) and FiredExplosiveWeapons is LivePlayerPlane's alone, so Lua
reads each enemy plane's FireControlSystemComponent.AllArms 2 s after it's created (each system's name and its projectile
module's WeaponClass(es), `weapons: <unit> (<row>, <airframe>) carries: ...`, once an airframe and loadout) and every
0.5 s every LiveExplosiveWeapon / LiveAttachedInstantWeapon / LiveElectronicWeaponBase: pooled, so a launch is one shown
(bHidden false) that was hidden the look before, or shown with a new OwningGameObject (the first look only primes);
`weapons: first launch of <weapon> by <airframe> (<unit>, <row>) at <target>` once each, and every 60 s `weapons: last
N s: <weapon> xN (<shooters>) ...; carried by enemies but never fired this run: ...`. Guns and flares are listed, not
watched. tools/checks/weaponlog_test.sh. Unverified: that idle pool items are hidden (logged if bHidden can't be read).
0.73.39 in game (the user's solo Spaceport test, 2026-10-31 17:51): the fleet, waves and landings worked, but "only some
of the ships are firing, none of their Anti Air": no ship launched anything in 5 minutes (the weapons log). A hull's
engagement order doesn't reach its turrets (stock missions order each by name; the Ladon's CIWS needed theirs).
0.73.40-coop2mp.41 (built and installed 2026-10-31, zip 0.73.40, hash a3f8e7c2...477dec; not yet run in game): each of the
fleet's 68 turrets its own order (Mission 16's Default_RemoteEvent_20: Normal, PlayerFirst; survival_events.sp_parts,
asserted against the world data). The STORE's allied Aegis (ally_units / build_allies) still have the hull's order only:
likely why they "didn't seem to fire all that much" (2026-10-23). The same log: the fighters carried their specials
(2AAM, HCAA) and never fired one in 5 minutes, their standard missiles 21 times.
0.73.41-coop2mp.42 (built 2026-10-31, zip 0.73.41, hash d268bffd...e5ef4d; installed when AC8 was closed; not yet run in
game): the same test's capture never ended the round (six fighters still up: a round ends only with its aircraft
down): the capture now despawns the round's pool flights (RE_SV_FlightOff_NN, Mission 22's LiveSetActiveGameObject false,
and off D.up: a despawned unit can still read alive) and drops its queue and later waves, so the break and the retake
follow; the missile boats patrol their lanes (4-9 km ahead of their Wasp and back, Mission 22 ship lane shape, 90 km/h).
0.73.40 in game (the user's solo test, 2026-10-31 18:04): the turrets fired (the weapons log: the Aegis mk41 VLS 6 a
minute, the boats' SAMs 4), so a turret's own order is what they needed.
0.73.42-coop2mp.43 (runtime 0.32.12; built 2026-10-31, not yet run in game):
- The fleet's weapons (user: "up the Activation Range and Targetting Range and Lifetime of ALL Ships currently at the
  Spaceport"): each turret on Survival's own mission row and DT_NPC copy (tools/survival_events.py SP_TURRETS:
  sv_fleet_* -> SV_Fleet_*, copies of the stock VE002 / VE004 / VE011 rows; sv_spaceport.lua SPORT.FLEET_ROWS), which
  sv_allies.lua ALLY.setup puts into DT_NPC at the main menu on fire control of its own as the STORE ships' (key
  "Fleet", CFG.specials.spaceport.fcs: search module 25 km, lock-on x2, guns' rounds out to it, homing missiles 20 km /
  30 s; their stock rate of fire); `allies: the Spaceport fleet's turrets: 9 of 9 rows in DT_NPC ...`; without them no
  Spaceport Assault (SPORT.ready, ALLY.fleetReady). Each ship's unit area 40 km. The LCAC waves every 3 minutes (user).
- The enemies' special weapons (user: "I want the Enemies to fire their Special Weapons too"; the weapons log: carried,
  never fired): Scripts/sv_spweapons.lua (SPW, CFG.special.fire, [special.fire]) fires RE_SV_SpecFire_<NN><L> (Mission 19's
  LiveFireOneShotWeapon, WN_WEAPON_4 = slot 3: survival_events.SPEC_SLOT) for an enemy whose row has its special there
  (sv_rows.lua SR.spSlot / spWeapon) with you inside 35 deg of its nose at that weapon's range (QAAM 1-4.5 km, HCAA 2-7,
  2AAM 1.5-6, LAAM 4-12), 10 s after it appears, every 25 s at most, 8 a minute across the sky, not a held Wolf trap;
  the host's (KEEP_EVENTS ^RE_SV_SpecFire_). `specials: <unit> <L> (<row>) fires its <weapon> at you ...`; the weapons
  log's `first launch of` says it launched. tools/checks/spweapons_test.sh.
- Alyssa's crash (a joiner on 0.73.37, 2026-10-31 00:50; tools/re/COOP2MP.md "A weapon's target search and a destroyed
  unit's world"): AceCombat8+0x374cb08 reading NULL + 0x898 on a worker thread, in the weapons' target search: entry
  class 0x147454050's check passes the world getter's answer (0x143fc1ca0: NULL for an object being destroyed) on
  unchecked, seconds after her game took 13 copies down and their flights spawned again (the native Recycle destroys
  a flight's old unit actor). 13 checks of the family do so. runtime/safecall.h (ScCall4: a vectored exception handler
  armed only inside the call puts the thread back, the call answers 0) wraps every guarded check, and TgtInstall guards
  the world-unchecked classes too (sigs.h kSigWorldOf, TcWorldUnchecked; the weak-pointer test only on its own kind):
  `guard: the target search's fault catcher in ...`, `guard: N target entry classes guarded (the first 1, a weak actor
  unchecked 3, the world unchecked M ...)`, `guard: a weapon's target search caught a fault in an entry check ...`.
  tools/checks/safecall_test.sh. Also from her log: the teardown on the host's restart paid her for the copies (290 Z
  "by you"): not yet fixed.
- Lesson (the load test): a new global table is `X = {}`, never `X = X or {}` (the load test's stub answers every
  global, and sv_allies.lua iterated SPORT.FLEET_ROWS at load: lua_load_test hung).
0.73.43-coop2mp.44 (runtime 0.32.12; built 2026-10-31, not yet run in game): the enemies' specials at every player (user:
"it's paramount that Special Weapons target all, HOST and JOINERS"; 0.73.42 fired only on the host, at the host): every
game runs sv_spweapons.lua on its own planes at its own player (the host its enemies, each joiner its copies of them,
as their standard missiles already go: an AI's shots are decided on its target's game), each with its own cap; a joiner
learns each flight's rows from the host's spawn (sv_coop.lua doSpawn -> SPW.noteRows: the flight's row, idx -1, and its
lead's own, idx 0); none while that player is DOWN; RE_SV_SpecFire_ still never forwarded. spweapons_test covers it.
0.73.44-coop2mp.45 (runtime 0.32.13; built and installed 2026-10-31, zip 0.73.44, hash 2ea9dfa9...a433c; not yet run in game): seven loggers (user: "What other loggers
could we add?" ... "All of them"), in the log only:
- crash breadcrumbs: <mod folder>\AC8SurvivalMode_crumbs.log (the session before: AC8SurvivalMode_crumbs.prev.log),
  written at once with milliseconds and the thread: the native runtime's flight recycles (unregister + unit actor
  destroyed), real / second player planes destroyed, the target guard's skips and caught faults, the effect guard's
  let-gos; Lua's (sv_core.lua crumb() -> SV_Crumb) every SV_Spawn, every removal-type event (Remove / Off_ / RunOver /
  Destroy), each copy taken down, teardowns, a joiner's copies of the host's spawns, a joiner's asks answered. After a
  crash, read the crumbs.prev file first.
- targets (sv_audit.lua): every 5 s whom the enemy aircraft aim at (TargetActor: you, each co-op player by name, the
  allies, others, nothing) and each player's damage (health drops), `targets: last 60 s ...` a minute.
- missile outcomes (sv_weaponlog.lua): each enemy missile at you followed to its end (hit: within hit_m 150 m as your
  health dropped; decoyed: it went after a flare; missed), `missiles at you: last 60 s: <weapon> n (h hit, d decoyed,
  m missed; from X km on average); this run: ...`.
- fleet turrets (sv_weaponlog.lua, sv_spaceport.lua SPORT.turrets): per turret class each minute how many fired (their
  missiles; their guns: any of their LiveBullets shown, looked at every turret_s 5), your range at fire, and how many
  stayed silent with you inside their 25 km reach: `fleet: last 60 s: <class>: a of n fired ...`.
- pay audit (sv_audit.lua, wrapping addCredits): `pay audit: last 60 s: +N Z in M pays: kills / round bonuses /
  specials / other`, and on a joiner each kill paid within suspect_s 5 of a teardown here flagged at once (COOP.tornRecently).
- sync health (sv_coop.lua COOP.syncReport, each minute): a joiner's copies (bound to the host's ids or not), strays
  taken down, its asks (jn) and the answers (rs), copies torn down and teardowns; the host's asks answered.
- the Spaceport waves (sv_spaceport.lua): `special: wave <unit>: n craft, x shot down, y landed, z troop vehicles ashore`
  as each is done, and the round's `the Spaceport Assault's waves (...): ... the capture: 5% at +4:10, ...`.
CFG.log.weapons (hit_m, turret_s) and CFG.log.audit ([log.audit]). Tests: audit_test, weaponlog_test, spaceport_test.
0.73.44 in game (the user's solo Spaceport test, 2026-10-31 19:36): "im not being locked on by any of the aegis ships and
the range updates etc we applied don't seem to be working". The new logs: the fleet's 9 rows in DT_NPC on their boosted
fire control (VLS 3 -> 20 km), yet the Aegis VLS fired from 2.1 km on average and the boats' SAMs from 1.5 km (their stock
3 km), none in the first minute: the turrets flew their stock rows. A ship's parts spawn on the rows its HULL's DT_NPC
row names (ChildNPCId), not their world data descs' MissionNpcID (hard rule 38's Ladon pods the same); the hulls were
the stock rows. 0.73.45-coop2mp.46 (built and installed 2026-10-31, zip 0.73.45, hash 2a76d6ef...06b34b; not yet run in game): the armed hulls on Survival's own copies (survival_events.SP_HULLS:
SV_Fleet_AegisHull / BoatHull / FordHull, mission rows sv_fleet_aegishull / sv_sp_boat / sv_sp_ford) whose ChildNPCId
names the fleet's turret rows, as do the turrets' (the gun mount's artillery); build_npc_rows asserts all 9 children
remapped. The STORE's allied Aegis has the same flaw (SV_Ally_Aegis keeps the stock ChildNPCId: its turrets' _SVA
boosts never applied; the user's "aegis ships still don't engage far enough", 2026-10-23).
0.73.46-coop2mp.47 (built and installed 2026-10-31, zip 0.73.46, hash 9f1e962b...034520, not yet run in game; user: "I want it fixed also"): the STORE's Aegis the same way: build_npc_rows remaps
SV_Ally_Aegis's ChildNPCId to SV_Turret_aegs_mk45 / mk15 / mk41_Ally and SV_Turret_aegs_mk45_Ally's to
SV_Turret_aegs_artillery_Ally (asserted, 4), so its turrets fly their own fire control (CFG.allies.ships.Aegis.fcs: 25 km
search, x2 lock-on, 20 km / 30 s missiles) for the first time. Watch its kills and the balance.
0.73.47-coop2mp.48 (built and installed 2026-10-31, zip 0.73.47, hash 55e7367f...40bf32e; not yet run in game): the missiles-at-once cap (user: "is there a hard cap on how
many AI turrets can target the player at once? I've only ever seen 4 missiles launch at me at one time from 4 different
targets"): the game allows MissileNumberLimitPlane 2 missiles from aircraft and MissileNumberLimitNonPlane 2 from
everything else (ships, SAM sites, turrets) in the air at a player at once, on every difficulty (DT_NPC_Difficulty,
Story to Ace), kept on the player's plane (LivePlayerPlane MaxPlaneAttackerMissiles / MaxNonPlaneAttackerMissiles,
MaxPursuitAttackers the chasers). (Mission 10's level has a LiveFCSWorldSubsystemModule_LimitActivator for its MainGun
arms; Survival's level has none.) sv_spweapons.lua ATK sets your plane's own (an instance; the stock table as it is) to
CFG.attackers plane_missiles 4 / nonplane_missiles 6 (pursuers 0: the game's) every 2 s, again when the game puts them
back: `attackers: your plane's missiles-at-once limits: ... (the game's: planes 2, ships / SAMs 2, chasers N)`. Co-op
(user: "make it so that in COOP all players feel the same effects"): each game sets its own player's plane (each
player's missiles are decided on their own game), with the host's [attackers] and [special.fire] (the settings sync:
not PERSONAL; coop_settings_test checks a joiner takes them); the fleet's and the STORE Aegis's boosts are built into
every game's rows at its main menu and the enemies' specials fire at every player (0.73.43).
0.73.48-coop2mp.49 (built and installed 2026-10-31, zip 0.73.48, hash c89317dd...6da429f; user: "I want 6 missiles from aircraft and 14 missiles from ships"): CFG.attackers
plane_missiles 6, nonplane_missiles 14 (survival.ini [attackers]).
0.73.49-coop2mp.50 (built and installed 2026-10-31, zip 0.73.49; user: "set the pursuers to 12"): CFG.attackers.pursuers 12 (MaxPursuitAttackers: the aircraft that may
chase a player at once; the game's own is logged on the attackers: line).
0.73.50-coop2mp.51 (built and installed 2026-10-31, zip 0.73.50; user: "increase the number of ships and sam site targetting to 40"): nonplane_missiles 40; the
attackers: line also logs the plane's attack waits (CooldownPursuit / NonpursuitAttackTimerRange_CP) and the difficulty's
modifiers. The player difficulty table (DT_Difficulty, LiveDifficultyDataTable; LiveDifficultyManager keeps the current
row as CurrentDifficultyDataTableRow), Casual / Easy / Normal / Hard / Ace: PlayerHealthModifier 300 / 200 / 100 / 100 /
100, unlimited gun yes / yes / yes / no / no, unlimited missiles Casual only, ReturnLineRecoveryHealth all but Ace,
FlightAssistOnForNewGame Casual / Easy, MissionClearMRPModifier 100 / 100 / 100 / 120 / 150, CooldownPursuit and
NonpursuitAttackTimeModifier 150 / 120 / 100 / 50 / 25 % (the enemies' waits between attacks).
0.73.51-coop2mp.52 (built and installed 2026-10-31, zip 0.73.51, hash f1199a67...7d77a6; user: "increase the lock on and firing distance of all SAM sites and Ships"): the airfield's SAM sites'
missiles 8 -> 20 km, 14 -> 30 s, the defences' search 10 -> 25 km, their units' area 25 -> 30 km; the STORE's Aegis and
the Spaceport fleet: search 25 -> 40 km, guns' lock-on x2 -> x3, missiles 20 -> 35 km and 30 -> 45 s (the fleet's 3600
km/h), their units' areas 25 -> 45 km (the STORE's) and 40 -> 45 km (the fleet's).
0.73.52-coop2mp.53 (user: "increase Ship AA gun accuracy and increase timing between SAM and SHIP salvos slightly"):
a ship type's guns' spread x gun_spread_x 0.5 on top of the allies' spread_x (sv_allies.lua allyFcs, not homing weapons),
the STORE Aegis's flak out to its lock-on (round_reach, round_width_x 1.5: it locked on 3x out with flak hurting within
2200 m), the fleet's flak round_width_x 1.0 -> 1.5; homing missiles' time between shots and rest x missile.salvo_x 0.8
(the airfield's SAM sites, the STORE Aegis, the fleet; the user: "no I want less waiting between firing"). The ships'
missiles home as the EXSAM's (user: "theres a enemy in the game called EXSAM ... paste them over the ship guns and
missiles"; missile.homing_from EXSAM_Ground_000: homing 90, turn 45 (x turn_x), homing delay the shorter, omnidirectional
0.95 s / 360, 900 m; the game has no EXAA) and the ships' AA guns are flak guns (user: "change the AA to FLAK GUNS",
"give the flak guns the same stats as the Boosted AA guns, I want them to be deadly"; fcs.flak): a ship's AA mount
(NPC_FCS_VesselAAGun*: the Aegis's Mk 45, the Ford's four) on a clone of the ground flak gun's NPC_FCS_FlakGun000 (its
blueprint BP_FCS_FlakGun_00, FlakGun_000's 50-burst shells) with the mount's arcs and the AA gun's timings, then the AA
boosts (lock / fire x, search, slew), 15 km reach, the bursts' scatter x spread_x x gun_spread_x (120 -> 24 m), radius x
round_width_x (18 -> 27 m), damage x2 (10 -> 20), from 50 m up (500). Not yet known: whether a flak fire control fires
from a ship's mount (the log's `an AA gun on NPC_FCS_FlakGun000's fire control`, the weapons log's flak launches);
flak.enabled = false gives the AA guns back. The CIWS (VesselCIWS000) stay as they were.
0.73.53-coop2mp.54 (user: "increase the Carriers aircraft spawn rate, increase Flak firing and increase missile salvos"):
the Ford's deck first_s 45 -> 20, every_s 50 -> 25, max_up 2 -> 4, flights 3 + 0.15 -> 5 + 0.3 a round, at most 8 -> 14;
the flak's waits (triggering, between, rest) x flak.fire_x 0.5; the SAM sites', STORE Aegis's and fleet's missiles in
salvos of missile.salvo_n 3, salvo_gap_s 0.5 apart (a salvo in the game's fire control: TriggerCount shots
ShotIntervalTime apart over TriggeringTime = count x interval, then RestingTime: the stock 2AAM 2 x 0.25 s, rest 7; the
4AAM 4 x 1 s, rest 16; every ship and SAM missile row 1).
0.73.54-coop2mp.55: the revive test keys gone (user: "the same key to test the revive system is being used by the test
spaceport", "we no longer need the revive test"): T1 Ctrl+F6 and T2 Ctrl+END (sv_down.lua DOWN.testFloor / testDown, the
watch list's test planes, the floor's down-test lines); Ctrl+END is the Spaceport Assault's alone, Ctrl+F6 free. A test
key bound twice with Ctrl is logged at load (`test: Ctrl+<key> is bound twice`).
0.73.55-coop2mp.56: a friends' build without the Spaceport (user, 2026-10-31: "build a version for my friends that DOES
NOT include the spaceport retake", "or Spaceport Defense"): CFG.specials.spaceport.enabled (SPORT.ready, the retake kind's
ready and specialFor: none, forced or not); `NOSPACEPORT=1` on package_release.sh / package_dev.sh runs
tools/nospaceport.py on the staged copies (both off, their ini sections gone; zip ..._NoSpaceport). The sources keep it on.
0.73.56-coop2mp.57 (a friend's report of 2026-10-31: "choppy" and stuttering in solo play; their log too short for a perf
line): the Lua tick ran whole on one frame every 250 ms (the user's perf lines: 15-38 ms a tick, worst 160-357 ms; the
weapons log 19 ms of it in Spaceport rounds). Now in two halves 125 ms apart (sv_main.lua probeTick: rounds, HUD, music,
airfield, bombers; probeTickB: the STORE, allies, sounds, hits, loggers, AI parts, ammo, the plane sweep), each part
still once a tick; the perf line a minute in, then every five, with each half's average and worst (`perf: tick avg N ms
(halves A + B), worst half W ms (first a, second b)`). Friends' zips get the weapons log and the audit off
(tools/quiet_logs.py from package_release.sh); the user's dev install keeps them. Not yet run in game.
0.73.57-coop2mp.58 (user, 2026-10-31: "can you please build the rockets this time?"; dev only: friends stay on 0.73.56
without the Spaceport): the Spaceport Retake's rockets, Mission 19's (tools/re/SPACEPORT_ASSAULT.md). Build: its rocket
unit (two objects on the pads, invincible until launched) as SV_Unit_SpRockets / SV_Obj_SpRocket_0/_1 (port_unit
keep_rotation), its climbs copied whole (build_survival.py copy_path: SV_Path_SpRocketA / B, 900 m to 20.2 km), its three
debris units as SV_Unit_SpDebriA-C holding E_Obj_Rocket_Debri_Phase<N>_0/_1 under Mission 19's exact names (port_unit
digit_ok, rows per object), rows copied under Survival names (NPC_IMPORT renames: sv_sp_rocket, sv_sp_debri_a-f). Events
(Mission 19's records, fired from Lua): RE_SV_SpRocketSplitOff / On (LiveSetActiveOnDestroySpawnerEvent; the debris held
at 1 HP), RE_SV_SpRocketLaunch<A|B> (shown, not invincible, TGT; its path at 280 km/h), RE_SV_SpRocketBoost<A|B> (1000
km/h on along it: Mission 19's PathPointReceive record), the climb's PathFinish -> SV_SpRocketEsc<A|B> (escaped: hidden,
invincible, despawned), RE_SV_SpDebriTgt1-3, RE_SV_SpRocketRemove. Lua (sv_spaceport.lua rockets, CFG.specials.spaceport
.retake.rockets): launches at +45 / +110 s, boost 12 s on, 3000 Z a rocket, an escape -5000 Z and no retake reward, the
last one shot down breaks up, each debris stage targetable in turn (400 Z a piece), taken off 120 s after the last change;
the round holds until they're done. Not yet known in game: the split itself (whether the blueprint brings in Survival's
debris objects by those names, from units Lua spawned at the retake's start, 500 m down; Mission 19 spawns them at level
start), where debris falls with no fall-target marks (Survival's world data has no marks yet), the climb's speed and
whether its PathFinish fires. spaceport_test covers the Lua (launches, boost, kill, split, stages, escape, timeout, off).
0.73.58-coop2mp.59 (user, 2026-10-31: "on the spaceport retake, add more enemies around the island", their picks: air
defences, armour, more aircraft, about 30; "do a building check so that no enemies spawn in buildings"; dev only): 30
island enemies in 7 units with the retake's garrison (survival_events.sp_island): Mission 6's EXSAM site whole (radar +
4 launchers in its layout), 4 flak guns, 4 Gecko SAMs, 5 Shilka AA guns (Mission 6's), 8 T-90s (Mission 7's) and 4
BTR-90s, each on Survival's copy of its mission row (NPC_IMPORT renames: sv_isl_*), TGT and boxed, an engagement order as
it appears (SV_SpIslUp<key>), 20 km unit areas; Lua pays island.ad_pay 600 / armour_pay 400 and holds the round until
they're down; the retake's fighters + extra_aircraft 6. The building check: tools/scan_spaceport_buildings.py reads every
StaticMeshActor and mesh instance round the spaceport from the stock level packages (Map17_Env_CityMap001,
Map17_Env_CityHda001_Baked) with each mesh's ExtendedBounds into tools/data/spaceport_buildings.json (1344 oriented boxes);
tools/spaceport_spots.py picks spots on a fixed grid: 20 m or more from every box (the launch complexes' too), buildings
within 300 m in all four quadrants (land: hard rule 27 rules out tracing it), 250 m from the pads and the garrison's spots,
spread farthest-point; the build asserts every spot again (all 24 m or more clear). Not yet run in game: whether ground
units from other missions stand right at z 500, fight on their orders, and how hard 30 more targets make the retake.

## Builds 0.73.59 to 0.73.76 (kept under "How the two agents share the work" until 2026-11-07)

0.73.59-coop2mp.60 (runtime 0.32.14; built 2026-11-01, never installed): hotfixes 1-10 of the testers'
0.73.37 (branch hotfix/0.73.37, HOTFIX_NOTES.md) merged over 0.73.58: Ladon volleys after the first pass off, rage circuit off,
Ladon rounds and VOID WATCHER off, liveAddr() (SV_ObjChain) before reads of objects kept between ticks (now in the loggers,
the specials' fire and the Spaceport too), svLevelOn guarding level-wide checks, FindSpawner not over an unloading level,
co-op's STORE-freeze probes. COOP2MP is the working main; feature/flight-recorder holds the recorder only (6fd01ab).
0.73.60-coop2mp.61 (2026-11-01, user: "turn the Ladon's back on as well as VOID WATCHER" to test them alongside the
STORE freeze): specials.ladon.enabled and allies.awacs.enabled true again; the rage circuit and the volleys after the
first pass stay off (their paths aren't followed: HOTFIX_NOTES open problems 2-3). Not yet run in game.
.
0.73.71-coop2mp.72 (runtime 0.32.19; built and installed 2026-11-02; the menu confirmed in game the same night: user "Survival
Mode in the menu now works", every function found, all hooks in, a co-op host start into the hangar): the AC8 update of 2026-11-02
(exe and main paks replaced at 19:48; SURVIVAL MODE opened Campaign Training: "menu: game functions not found"). 50 of
53 signatures still matched; the main menu decide (0x147b3fa10), the difficulty page's next menu (0x146eb70a0) and set
difficulty (0x147b817c0) moved with only displacements changed: new sigs with those wildcarded (each checked by its
vtable: slot 0xDF the base, slot 0x111 building CampaignFreeMission). kSigDiffNext can't be wildcarded (its string's lea
is all that tells it from ~20 FName builders) and breaks every patch. Of the 1971 stock packages the build pulls, 2 changed
(DT_NPC_Model, EP_Mission015_global); pre-patch copies kept in build/prepatch. UE4SS's FUObjectHashTables /
ProcessConsoleExec warnings predate the patch. Patch diff: Claude Docs "AC8 Patch of 2 Nov 2026: What Changed".
0.73.72-coop2mp.73 (runtime 0.32.20; built and installed 2026-11-02, not yet run in game): the STORE freeze, reverse
engineered (tools/re/STORE_FREEZE.md, the new exe): a minigame's start (the airfield STORE) calls DeactivateForMinigame
(0x1478eb7b0, sigs.h kSigMgDeactivate), which puts every AI object into cinematic mode (+0xdf8; its tick then never
reaches the flight tick) and deactivates the live ones (SetActiveGameObject false: +0x3f4 0, the AI tick flag +0x25d9
off) into the manager's lists; either lock freezes a plane, which is why hotfixes 7-12 (ticks, bMinigameAIObject,
LiveSetActiveGameObject) each cleared at most one. flight.c OnMgDeactivate skips the call while SV_StoreKeepAI(1)
(sv_coop.lua COOP.storeKeepTick: co-op open with players linked, [coop] store_keep_world = true); solo the stock freeze
stays. RestoreForMinigame (kSigMgRestore) hooked log-only. Log lines: `minigame: type N starts; its deactivation of N AI
objects skipped (co-op)`, `minigame: type N deactivated the world's AI ...` (solo, with the first objects' bytes),
`minigame: type N ends: restore ...`, `coop: a STORE opening keeps the world's AI flying (players linked)`. Not yet known:
the minigame type in Survival's flow, whether the parked host plane can be damaged meanwhile.
0.73.73-coop2mp.74 (runtime 0.32.21; built 2026-11-02, not yet run in game): the fixes from the testers' logs of 0.73.70
(20 archives, 2026-11-01: Saint Alessia hosting, Shazzy, cressendo; all on the pre-update game) and the Spaceport in the
rotation (user: "install spaceport into the new patch"; from round 8; novalka.py / nospaceport.py follow the new line).
- Co-op resync loop (every joiner log): a copy the host killed ("dn") stayed in its flight's planes, so strayTick took it
  down again as a stray and sent "jn", and the "rs" answer tore every copy down. Now: dn takes the copy off its flight;
  strays only count copies up; the answer to a joiner's own jn is a repair (rs|j ... rz: copies kept and rebound, only
  what's missing spawned again, what the host has no more taken down); rs|n the host's new run, rs|m a migration's
  level. Every object a joiner spawns is registered (M.objsOf) so a refused or replaced host spawn takes the stale one
  down whatever it is (the ghost VOID WATCHER / MOONCHILD); bd / gd for an unspawned generation wait (pendBind). Ally
  health no longer compounds on joiners (ALLY.scale: a joiner's allies are the host's); no phantom kills (dead on
  arrival = torn); no free revives (DOWN.reset only on rs|n). VOID WATCHER's ESM fields are pooled: range / life applied
  on every launch. tools/checks/resync_test.sh.
- Quitting: levelGoing() (sv_core.lua) from the first sign the level goes (svLevelOn, the spawner gone: SV_UnitAlive -1 /
  -6): no kill paid or counted (up to 26 kills / 4,340 Z were paid on quits), FindAllOf / FindFirstOf held (walkHold:
  also 3 s after a main level's world, and while SV_GcBusy: the engine's purge flags) for crashes 2b / 2c.
  tools/checks/teardown_test.sh.
- Revives: DOWN restored the weapon flags it found, so a player downed with the gear out came back with the landing lock
  (couldn't fire); now armed as flying, CancelLanding, the gear raised, re-armed 10 s if the game locks again. Co-op:
  invincible while on the ground at your airfield ([coop.revive] parked_safe).
- Host crash S1 (rip 0 in the EnemyBehind event's Match, a freed AI chaser held by a queued event): the target guard is
  the events' Match family (152 vtables, 119 functions); uobj.h UoEventObjs finds the event fields each Match loads and
  answers "no match" for a freed one (37 classes in 38 slots). SV_GcBusy (GObjPurgeIsRequired /
  GObjIncrementalPurgeIsInProgress from IncrementalPurgeGarbage, kSigPurgeGarbage).
- DOWN loiter (climbed to 10 km, circled 7 km): AC8 holds the nose and speed, so a 40 deg bank barely turns; the circle
  control banks so one pull gives the wanted turn and climb (~90 deg in a level turn), priors roll +1 / pitch -1, harder
  in-flight sign checks. flight_test 67 of 67 with an AC8-like model.
- Ladons leaving after lap 2 and VOID WATCHER's orbit: a path started at a PathFinish is only flown when it begins a
  little ahead of the plane along its way (and ends far off); the 2nd circuit began 1.5 km to the side, so the Ladons
  held the old path's end tangent. Now two arcs of an 8 km circle through the airfield hand over to each other (Mission
  16's chaining), a leash at 22 km (RE_SV_LadonLeash), the appearance gated (SV_LadonDone, not turned on:
  volley_after_pass stays false); VOID WATCHER a lead-in turn then a 6 km two-arc orbit (SV_AwacsLeg, `legs N` in its
  30 s line), the area orbit as backstop. Candidate hard rule once confirmed: the path handover above. The heavy
  bombers' figure-8 likely has the same flaw (not changed).
0.73.74-coop2mp.75 (runtime 0.32.21; built and installed 2026-11-02, not yet run in game; friends' zip hash 92d5cdcf...115f16):
the user's test of 0.73.73 (23:13-23:17, Ctrl+4): the Ladons finished their route over the airfield (pass flag 1) but
never flew arc A (legs 0): they held the route's descending end tangent to 0.2 km, 29 km out, and the leash at 22 km
didn't turn them in 8 s. VOID WATCHER took the same kind of PathFinish handover (climb-out -> lead-in) and flew its 6 km
circle perfectly (6.0 km at every check), so the handover fails at the Ladons' 2500 km/h (arc A 2.5 km ahead = 3.6 s).
Now each Ladon's route path carries LADON_LAPS (15, ~18 min) laps of its circuit after the route, one path from its
appearance, no handover until they run out (arcs A / B as before after that); Lua counts its first pass by distance too.
Candidate hard rule once confirmed: a fast AI plane (2500 km/h) doesn't take a new path at a PathFinish; put what it
must fly into the path started at its appearance.
0.73.75-coop2mp.76 (built and installed 2026-11-02, not yet run in game): the user's test of 0.73.74 (23:22-23:25): the
round's clock never counted down and, back at the main menu, SURVIVAL MODE opened nothing: Survival's Lua tick stopped at
23:24:49, 16 ms after a test key's handler queued its game-thread callback, with UE4SS logging "Error:
[Lua::Registry::get_function_ref] Ref was not function" (no traceback): the loop's queued tick was lost, and the loop
queues the next only once the last has run (queued stayed true), so nothing ticked again (no "run over: left", the run
still on at the main menu, where the menu's code only runs with no run). sv_main.lua's loop now takes a tick queued
TICK_LOST_S (5) ago and not run as lost and queues it again: `tick: the game thread never ran the tick queued N s ago
...: queued again`. Not yet known: why the ref went bad (two callbacks queued at once from different threads?).
0.73.76-coop2mp.77 (built and installed 2026-11-02 for the user only, WITH VALKA: `VALKA=1 sh tools/package_dev.sh <name>`;
never in a friends' zip; not yet run in game): VALKA picked back up (user: "fix valka and add her to a special build for
me only"). Her paint: tools/re/FALKEN_MATERIALS.md (the Falken add-on, another AC7 aircraft whose paint draws in AC8:
its body instances hang off a stock aircraft's GEAR instance, MI_*_Gear -> MP_Gear -> M_Live_Vehicle_Base, which samples
ordinary textures with skinned-mesh shaders; hard rule 44's skin master needs virtual textures). New paint variants 15
(default: MI_PP0016_x40a_Gear at run time, her colour and normal maps, the stock T_Livemap, emissive / turbine / detail
and damage normals off) and 16 (the Falken's exactly, flat normal); Ctrl+9 still cycles them. The screen fades to red as
she shows (her first hunt tick) and back after she dies (sv_hud.lua hudRed: a full-screen Image on the HUD root, under
every text; CFG.specials.valka.red alpha 0.3, in_s 3, out_s 5). Ctrl+8 forces her round again. Also the 0.73.76 log
tidy-ups (the Ladons' pass number, the tick watchdog at 10 s). Log lines: `special: VALKA's paint 15 X-40A GEAR, HER
NORMALS: N slots on MI_PP0016_x40a_Gear, ...`, `hud: the screen fading to red` / `fading back from red`.
0.73.76 VALKA build, later the same night (user's test: paint 15 "looked better but was still bugged out", the portal
bugged, the music player played on, rounds lived too long, bursts): her portal deleted (code and CFG); a red SKY instead
of the red screen (sv_hud.lua hudRed/redTick, SkyLive's way: the level's LiveCloudlyActor's sun light, sky light and
height fog colours and the sky params' SunIntensity.RGB, the renderer's copies too, originals put back exactly, at once
on a cleanup; CFG.specials.valka.red strength / in_s / out_s / colours); the song at 90% with AC8's system mute
(AKE_System_BGM_Mute_On / _Off: the music player's jukebox kept playing past the stale hangar track's _Stop); single-shot
on her own railguns at her reveal and before every shot (the opener's had set s.singleN, so hers kept their bursts);
her rounds live eml_life_s 8 s (was at least 30); MINDRIPPER's gun rounds' life x gun_life_x 4 (was x gun_reach_x 20,
its range unchanged); her health 2000 (was 900); her default paint 16 (the Falken's exact: flat normal). The Spaceport
Assault's capture_per_troop 5 -> 10. All untested in game.
0.73.76 friends' zip WITH VALKA (2026-11-03, user: "package a build for my friends ... set Valka to appear randomly",
"i want them to have the song too"): `BUILD_NAME=COOP2MP COOP=1 SONG=1 sh tools/package_release.sh online 0.73.76`
(no NOVALKA: her X-02S container and AC7 railgun sounds in; SONG=1 copies build/valka_music/*.wav, git-ignored, into
Sounds/valka) = AC8SurvivalMode_COOP2MP_0.73.76_Online_COOP.zip (72 MB, hash 38821dbe...96bf8: register on /admin);
VALKA in the random rotation, her test key stripped. Same session: her red sky set on the scale the log gave (the sky's
values are 1 1 1 white, fog 0: sun / light red, sky params' sun 1.8 / 0.3 / 0.15, a faint red haze, strength 1.0;
the tints left a dark purple sky); her paint's Livemap a flat 4x4 render target cleared to 0 / 0.75 / 1 ("rt:R,G,B":
KismetRenderingLibrary.CreateRenderTarget2D, RTF_RGBA8) as the Falken's, since AC8's T_Livemap isn't flat (111 of 256
DXT1 blocks differ: her black blotches). Not yet run in game.
VALKA in co-op (0.73.76, 2026-11-03, user: "will the red sky sync in coop?" ... "do it"; untested in game): her
round runs on the host alone (a joiner has no D.special), so the host sends "vm|1" / "vm|0" when her mood (red sky,
song) starts and ends (sv_coop.lua COOP.valkaMood, from SPC.V.mood / moodOff) and "vr|<unit>" at her reveal
(COOP.valkaReveal); a joiner (only from the host) turns its own sky red and plays the song, and COOP.valkaTick puts her
X-02S and paint on its copy of her (M.cunits[unit].planes, up to 30 s) and runs its wing sweep; the host's whole
picture (rz) resends both while they're on; runLeft puts the sky back at once on every game. Friends' zip rebuilt with
it: AC8SurvivalMode_COOP2MP_0.73.76_Online_COOP.zip, hash de48331d...7f24e39 (replaces 38821dbe...). Log lines:
`coop: the host's VALKA mood on: the sky red and her song here too`, `coop: VALKA's X-02S on this game's copy of her`.

## 0.73.77-coop2mp.78: the 1.0.0 plan's bug fixes and the co-op leaderboard (runtime 0.32.22; 2026-11-03; not yet run in game)
The cloud session's hand-off of 2026-11-03 (testing/2026-11-03: README, PLAN_desync_lag_compatibility.md = the 1.0.0 plan,
ECONOMY_change_proposal.md, IMPROVEMENTS.md) built by 8 agents in one tree (user: "start working on all the bug fixes
firstly, then start work on the COOP leaderboards with multiple agents"). None of it is a hard rule until a test confirms it.
- Copies (plan A, sv_coop.lua): a joiner's copies held at 1 HP by the MinHealth FIELD (floorOn; SetMinHealth(0.1) kept 0);
  a hit the floor clips is sent whole from the copy's DamageHistoryMap (M.historyOf, trusted once your plane is in one:
  M.ownSeen); a copy put there by something else goes back up; "hp" never touches a copy down here; a refused spawn's
  wrecks are taken down, then SV_Recycle(unit, 1) after 6 tries ([coop] force_recycle); the joiner's sync line counts the
  floor and refusals (A6); the host's run-over ("ro") goes again with the picture to a player who links after it (A9).
  claude/coop-fixes (57dce73) checked: all in or superseded but its STORE relabel fix (ported, defences_test).
- Kill pay (economy C1): each "dn" names the killer (hostKiller: most damage, else the host if it fired in 15 s, else the
  side); every game pays its own kills x1 and a teammate's x min([zollars] team_x 0.5, 1 / (players - 1)); the host's
  tally COOP.killTally(). Log `credits: ... by player N x0.33`.
- Rejoin in another aircraft (C): after sys|left / sys|restart (po / rj on joiners) the old real plane is set aside
  (unbound, hidden, collision and tick off, 30 km up) and moved out of its native slot with SV_CoopSwapPP, since
  SV_CoopSpawnPP DESTROYS what its slot holds (migration's retirePeer had that latent crash; fixed the same way); a new
  plane spawned; stand-ins on a free unit (M.unitSlot); [coop.rejoin]. coop_rejoin_test.sh.
- VALKA's mood (D): M.valkaWatch on the host mirrors her moodOn / reveal to joiners, logs each send, sends off when her
  round ends with it on; joiners drop it on rs, a new run or taking over. gloom's run (no mood on dukka) was likely the
  first 0.73.76 zip (38821dbe, before the sync): check the build hash line. "rnd" field 11 = the host's round special
  (joiners' music), field 12 = the host's special:state (D.hostSpecial).
- Crash on quit (F1): UE4SS.dll+0x2ab5bd is UE4SS's Lua UObject property lookup on a FREED object (not FindAllOf); the
  dump's main.dll+0x1abe8 / +0x68b7 were stale return addresses (map them: build/runtime/main_<ver>_<ts>.map, the
  shipped 0.32.21's main_0.32.21_6ae89927.map). The runtime's teardown gate (g_teardown on the spawner's world: freed,
  garbage, being destroyed, unreachable in a purge or reused) closes at once; SV_LevelGone(); sv_core.lua levelGate /
  levelDrop / LEVEL_DROPS (each part's lists forgotten, none touched; COOP.levelDrop), tick halves held until a new level.
- Bomber-raid crash (F2): AI path tracking (ULiveAIPathTickerSubsystem's tick 0x147dd5120, ParallelFor body
  0x147dd53f0) holding a deleted movement controller (+0x1c0, base vtable 0x14cbf8550); who keeps it isn't found.
  runtime/pathguard.h (kSigPathTrackTick) leaves out a tracker that's freed or faults; a recycled flight's unit actor is
  destroyed [recycle] destroy_after_s 30 later (SV_RecycleWait); SV_Recycle(unit, force 0/1/2); Ctrl+F11 (test only)
  the raid's spawns 20 times. Crash readers tools/checks/mdmp.py / deep.py (--map); the release readmes' crash note.
- Lag (B): every call of the tick halves timed by name, a second `perf: lists:` line (lists, walks by class, natives,
  Lua heap); joiners' `planes` drops downed planes 10 s on (the host's was already pruned at each round start); Ladon
  missiles and weapon objects kept as made, not walked; allied / defence counts a share per tick (ALLY.alive); STORE
  texts only at the airfield, sent on change. perf_test.sh. Lesson: feed a growing object list with NotifyOnNewObject
  and liveAddr, never re-walk it with FindAllOf.
- Specials and gameplay: G1 enemy rows never carry a stock "hit missile" (BP_FCS_HitMSL_*: capture 0, only events fire
  them, but sv_rows' svFcs gave them a capture distance): f18e_common / su33_common on their plain campaign rows, the
  aces' slots emptied, build_survival.py check_no_certain_kill fails the build. G2 UP.healthGuard (sv_tactical.lua, from
  HIT.tick) restores AIRFRAME the same pass the airfield resets it, never a hit. D4 SPC.cleanUp / endTick / clientClean
  (sv_rounds.lua): every special's objects recorded and taken down at its end, checked 2 s later (SV_Recycle); VALKA's
  opener railgun (invincible: RE_SV_ValkaEmlRemove's LiveDestroyUnitExecution never killed it; likely the white minimap
  square, user 2026-11-03) removed 4 s after its shot, her parts at her death. MINDRIPPER's field on joiners
  (ANOM.clientTick) only from a live copy while the host's Anomaly hunts (it lingered round a wreck for rounds, user
  2026-11-03). A7 [waves.tail] RE_SV_LastPing_NN; A8 the run-over held for a player loading in (join_wait_s 90); A10 no
  SV_Invert while DOWN; D5 [specials.valka] flash_size_x 0.5.
- Spaceport (I, economy C2): ships counted by their hull (SPORT.shipObjs: paid and called once, turrets finished off,
  pay.turret 150 alone); "landing craft sunk" / "troop vehicle destroyed" (never " down (", so joiners are paid); the
  escape penalty on every game ("db"); leftover fleets taken off; withdrawn flights recycled; rockets end by timeout or a
  real climb, debris only after a seen split; clocks wait while you're landed solo; "spx" carries the NEXT row and the
  pending retake; deck.reserve 4. tools/re/SPACEPORT_ASSAULT.md's 0.73.77 section has the I9 checklist.
- Co-op leaderboard (H2-H5): [coop] leaderboard on; the host sends one team run ("coop": players, squad [{pilot,
  aircraft, air, ground, revives, host}], host first, sums = kills); every game keeps the squad from lb|r / lb|p / lb|s /
  lb|x (joiners answer lb|n), so a host by migration sends it under the same run id; joiners never send. The Worker
  (leaderboard/, not deployed) checks it (limits x players, unique names ignoring case, host = pilot), stores squads, a
  third pinned CO-OP message (2 / 3-4 / 5+), /leaderboard board:Co-op [size], /pilot's Co-op field; solo boards read
  players IS NULL. Deploy it BEFORE any build that sends co-op runs, then /setup once, then register the build.
- Open (from the agents): sv_audit's damage audit may still count the airfield reset; LiveSetActiveGameObject by unit
  never switched the shuttle off (RE_SV_FlightOff_NN likely the same); a joiner who kills ship turrets may get each as a
  ground kill if GetAttachParentActor doesn't see them attached; set-aside planes pile up one per changed-aircraft rejoin.

## 0.73.78-coop2mp.79: the 1.0.0 plan's balance (runtime 0.32.22 unchanged; 2026-11-03; not yet run in game)
The decisions of 2026-11-03 (economy C3-C6, plan G4-G6), built by 3 agents (user: "Continue"). Not hard rules until tested.
- Economy (C3-C6, G6): a co-op special's pay (every relayed "cr" pay but the round bonus) is reward x players^-special_split
  ([zollars] special_split 0.5), split once in sv_coop.lua's addCredits, the callouts each player's share (specialPay).
  Prices by the round: priceRound() / itemPrice() (sv_ai.lua), `price_per_round` on any STORE item: airstrike 4000 + 300 a
  round (its kills x airstrike_x 0.25), ECM burst / decoy 2500 + 200, revive (2000 + 150 a round) x1.25 a revive (the host
  also takes the previous round's price). The airstrike by key only (no auto), per_round 1, never on an ace squadron's
  flights (D.aceSquad; a joiner reads SPW rows sv_ace_*), max_hit 4 nearest. economy_test.sh.
- Aces (G4): Harvest's ~10,000 was the Reaper tier's health_add 600 in MaxHealthDifference, which counts in MaxHealth HP
  while the log's HealthInternal is x10 (+6,000 in log units on 60-115 HP bodies), not the named-ace bodies. Now health
  per tier ([aces.health.<tier>], MaxHealth HP; ACE.healthFor / ACE.setHealth from enemyLate; a copy is only lowered):
  wing / lead in log units Bounty 1,000 / 2,500, Valkyrie 1,200 / 3,200, Inferno 1,400 / 3,800, Wraith 1,600 / 4,600,
  Harvest 1,800 / 5,400. Ace rounds 12-24 planes, 6-10 up ([aces.round]); from round 28 Harvest every 2nd ace round, the
  squadron met longest ago at Reaper skill between ([aces.rotation]); after 360 s the rest break off (RE_SV_DirHold_NN,
  then RE_SV_FlightOff_NN unpaid 4 km from every player or 12 s on, recycled at the next round: [aces.break_off]). A
  joiner's copies of a flight the host takes off with RE_SV_FlightOff_NN are unpaid.
- VOID WATCHER 1 (G5): serves [allies.awacs.service] rounds 3 (a round counted as it clears with it up 60 s+), then
  RE_SV_AwacsHome: the arc it's on ends into its exit (SV_Path_VoidWatcherOutA/B, 24 km along the tangent; SV_AwacsHome /
  SV_AwacsOut gate the arcs' PathFinish), taken off at gone_km 20 / the exit's end / max_s 360 (RE_SV_AwacsRemove, then
  SV_Recycle 2 s on), sold again; raise 1.25 room-wide (a joiner's ask checked at the host's price, "rnd" field 13 the
  count); ESM range 9 km, 15 s every 30 s; one strike flight a round onto it (EngagementOrderOverride TargetFirst), back
  on you after. Survival has no landing an AI plane can fly (the stock landing nodes are the player's).
- The user's calls of 2026-11-03 ("everything else you have it right"): the Spaceport rocket-escape penalty split as a
  special's reward (SPORT.debit: penalty x COOP.specialShare() on the host, sent as it is); every ally's and defence's
  price room-wide (shopBuildFor checks a joiner's ask at the room's price and counts it; "rnd" field 14
  "<item>:<n>,...;<kind>:<n>,..." = MOONCHILD / SNIPER / AEGIS (M.ROOM_ITEMS) and the defences' counts, VOID WATCHER's
  staying field 13); a co-op leaderboard run is sent when its host quits (a later migrated part isn't recorded).
- Open: decoys may target ace flights (a decoy only draws fire, left so); RE_SV_FlightOff_NN
  (LiveSetActiveGameObject by unit) may not switch a flight off (it never switched the shuttle off): the break-off and the
  capture's withdrawal fall back on the next round's recycle; other despawns may reach joiners as "dn" with no killer.
0.73.78 released (2026-11-03): the friends' zip WITH VALKA and her song, the Spaceport in (`BUILD_NAME=COOP2MP COOP=1 SONG=1
sh tools/package_release.sh online 0.73.78`): AC8SurvivalMode_COOP2MP_0.73.78_Online_COOP.zip (72 MB), hash
bf52dff8...0ac5c5863 (register on /admin); the user's VALKA dev install's hash 957feea9...bf7e9f822 (registered). The Worker
with the co-op boards DEPLOYED the same night (pasted in the dashboard; /setup run: slash commands registered, the CO-OP
message made, pinned by hand: the bot lacks Manage Messages; the live /admin page checked for the new code).
0.73.78 on runtime 0.32.23 (2026-11-03, after the stall above; hard rule 55): VFmt fixed, a "Lua bridge: registering N
functions" line and an "all registered" crumb. The first 0.73.78 friends' zip (hash bf52dff8..., runtime 0.32.22) never
starts Survival: never give it out. Dev install (VALKA) confirmed in game at 23:54, hash eb7b586e...2591e250. The friends' zip
rebuilt on 0.32.23 (same name, with VALKA and her song, the Spaceport): hash 03e468eb...3ccda9341 (register on /admin).

## 0.73.79-coop2mp.80: the lag audit's Tier 1 and the Alicorn fixes (runtime 0.32.24; 2026-11-04; not built, not yet run in game)
Saint Alessia's solo tests of 2026-11-03 on 0.73.78 (testing/logs/2026-11-03/SaintAlessia_valka, _alicorn): a 24 ms tick in a
quiet round 1 (first half 19.8 ms: a dropped frame 4 times a second), 61 ms and a 1.3 s freeze at the Alicorn's spawn, and the
Alicorn diving with its ballast tanks gone. The lag audit (8 areas, 77 findings, each verified: testing/2026-11-03/PERF_PLAN.md,
PERF_AUDIT_findings.json) found the root: this UE4SS can't find AC8's FUObjectHashTables (UE4SS.log "object lookups use
GUObjectArray"), so every StaticFindObject scans every object (~3 ms on her PC) and every FindAllOf costs 35-70 ms. None of it is
a hard rule until a test confirms it.
- The Alicorn (sv_alicorn.lua): no dive once its core is open (one under water surfaces at once); its parts from the spawn
  record (SPC.CLEAN_OBJ) instead of a FindAllOf per class every 2 s, a search only for a class missing there (every 10 s).
- Tier 1 (gameplay unchanged): /Script/ lookups kept (sv_core.lua's StaticFindObject wrapper; the perf line's `finds:`);
  the runtime's Log without a disk flush per line (0.32.24) and SV_LogUnits only with [log] verbose; the menu tables' watches
  every 30-60 s in a run (rows watch, info maps, shop rows), the main menu's pages not looked after in a run; the leave probe
  twice a second; the Ladon missiles' walk once a level (or on a dropped feed item, 60 s backstop), one class a sweep, the
  sure kill first, a pool missile written only when its values differ; the player's position read once a tick half (PLOC);
  the player controller asked of GameplayStatics before a walk; Wolf traps' alive check once a second while held; the
  defences' repair walk only with a STORE defence up (the shuttle pad's guns healed from their record); the shuttle's
  take-off one walk; the difficulty manager kept; VALKA's sounds loaded one a tick before her fight; co-op's pause check
  reusing the round clock's answer. Left out: the boss alive-check shortcut (a boss's end up to 1 s late in an edge case)
  and the ALLIES row from cached counts (up to 2.5 s old).
- To check in the next test: `perf:` first half under ~8 ms in solo round 1, `clock` under 0.5, `rows watch` ~0.1; `perf:
  lists:` no repeated walks of the Alicorn's part classes, PlayerController, the Ladon missiles, LiveAIGroundDummy;
  `finds:` few scans; `special: the Alicorn's ... found by a search` should not appear; no "the Alicorn dives" after
  "its core opens"; `sound: VALKA's N sound files loading` before her round.
- Review of 2026-11-04 (3 reviewers, each finding verified): fixed a Ladon walk that never finished when none existed yet
  (UE4SS answers nil for none found as for a held walk: only WALK.heldWhy means held), the Alicorn's railgun / VLS
  "looked for again" reusing the kept list (parts(cls, fresh)), bought defences unrepaired with [allies] off (the count
  unknown: the walk), a joiner's VALKA preload (the host's special is a table), the menu's first pass after a run; tests
  brought to the new timings. Every Lua test in tools/checks passes (run through lupa's Lua 5.4: `pip install lupa`, and
  build/checks/lua.exe a wrapper running a script with it, when lua.org can't be reached); the C tests need Windows
  headers, the build-side checks build/'s scriptobjs.pkl.

## 0.73.79-coop2mp.80 (same build): joiners couldn't finish enemies (2026-11-04; Lua only, on runtime 0.32.24; not yet run in game)
The 0.73.78 co-op run of 2026-11-03 (Saint Alessia hosting, Shazzy, cressendo, Nada; logs in the user's uploads
"CO-OP_Desync_Invincible_Enemies", "SaintAlessia-logs", "0.73.78_Shazzylog"): the host played normally, every joiner
"dumping into enemies and unable to kill them after 6+ missiles" (Shazzy: "could not damage a single" one). The run's
tally: host 36, Nada 14, cressendo 5, Shazzy 1. Two faults in sv_coop.lua's joiner side, both fixed and covered by
copy_floor_test.lua (its five new checks fail on 0.73.78's sv_coop.lua):
- The floor (plan A1) trusted the copy's DamageHistoryMap alone once your plane had shown up in any map (M.ownSeen):
  a hit that took a copy to 1 HP with nothing new under your plane there was "not yours", so the copy was put back up
  and nothing was sent. Your missiles aren't found under your plane in that map (Nada: two missiles from 0.3 km,
  "damage: you 0"; your gun is, a little): every missile that would have finished a copy was undone here and never
  reached the host. Now each missile's target (FiredExplosiveWeapons' TargetToHome, at launch: M.shotMark; when it's
  gone: M.shotEnd) and the gun's (SV_PlayerTarget while it fires: M.gunMark) are kept by the copy they went for, and
  M.floorLoss sends a floor hit whole when your missile went for that copy in the last 25 s (or the gun is on it, or the
  map has it). A copy already at the floor (its health can't move) whose missile from you is gone sends the host's last
  health as your hit, once a missile, at most every 2 s. A crash or an ally's copy into the floor still sends nothing.
- The "hp" race: the host's health written over a copy between a hit and clientTick's next look set what's expected
  to match, so that hit was never sent at all. "hp" now keeps a hit not yet sent on the copy, and for 1.5 s after a hit
  is sent ignores host health no higher than the copy had before it (the copy flickered back to full on every hit).
- Log lines: `coop: a copy taken to the floor by your missile (its map has ... of yours): sent whole to the host`,
  `coop: copy N held at the floor, your missile at it gone, no kill from the host yet: its last health sent again`;
  the joiner's sync report adds "N your missiles' (0.73.79), N sent again" and "N held after your hit".
- To check in game: a joiner's missile kills go down on every screen and show "by player N" on the host; the host's
  `leaderboard: co-op run ... over` line has the joiners' kills near the host's.
- Lesson (not a hard rule until a test confirms it): don't decide "not this player's hit" from DamageHistoryMap under
  the player's plane alone; a missile's damage isn't keyed there.
- Given out as a patch for the 0.73.78 friends' zip (2026-11-04): testing/builds/AC8SurvivalMode_COOP2MP_0.73.78_KillFix_Patch.zip
  replaces only Scripts/sv_coop.lua (this kill fix on 0.73.78's file, test-only code stripped; no Tier 1 lag fixes), the
  version left at 0.73.78-coop2mp.79 so patched and unpatched players still link (a joiner needs it for their own kills).
  It changes the build hash: register the patched hash on /admin (the log's first "leaderboard: the game started: build
  hash" line). Its sv_coop.lua is e3571c3's minus Tier 1's two co-op lines and the TEST ONLY block: all of it is in 0.73.79.
- 0.73.79 patches (2026-11-04, made in the cloud session: no full build there, the containers and main.dll need the user's
  PC): testing/builds/AC8SurvivalMode_COOP2MP_0.73.79_TESTER_Patch.zip (Saint Alessia: test keys and loggers kept) and
  AC8SurvivalMode_COOP2MP_0.73.79_Patch.zip (her joiners: stripped, quiet logs), each the 29 Scripts/*.lua only, staged as
  package_release.sh does (coop_edition.py, edition.py online; the players' strip_test_only.py + quiet_logs.py), over a
  0.73.78 COOP2MP install: only Scripts/*.lua changed since 294712f. VERSION 0.73.79-coop2mp.80 (everyone in a session
  needs one of them), on runtime 0.32.23 (no new native function; 0.32.24's log flush comes with the next full build).
  Both load in lua_load_test. Their build hashes come from the game's first log line: register them before ranked runs.
- 0.73.79 in game (2026-11-04, 31 rounds, 1:58:44, 6 players: Saint Alessia hosting on the TESTER patch, Amia, Shazzy, dukka,
  cressendo, gloom; logs testing/logs/2026-11-04, the four areas' verified findings R30_FINDINGS.json; report and plan: Claude
  Docs "AC8 Survival Mode: 0.73.79 Co-op Test Report & Plan, 4 Nov 2026"): no crash or Lua error in 2 h; the joiner kill fix
  worked (every joiner's kills paid by the host, all logs agree); Tier 1's lookups 0.3-0.6 ms; VALKA's sounds preloaded. The
  host's tick grew 16 -> 59 ms (r21-30; 117 ms in a 5.6-min STORE stay) and its fps 37 -> 20, which drove the joiners'
  desync (enemy moves past their newest state 1.4% -> 5.5%, r -0.85 with host fps; link lateness flat): SV_UnitAlive costs
  ~75 us per unit ever spawned (0.3 -> 6.6 ms a call, 84 units), asked for every flight once a second; the co-op airfield
  music hold walks the landing windows ~3.5x a second (41 ms each). Bugs: the shuttle's unit never recycled (rounds 17 and 30
  fell back to bombers), the amphibious LCACs / STORE defences / shuttle pad spawned without spawningUnit (no co-op ids:
  each game fights its own), joiners never see DESTROYED (the floor + a Lua kill with no joiner causer), the Falken flies as
  an AI stand-in on joiners, a quitter holds spawns 50-80 s, the host's run refused 422 (TESTER hash unregistered) and deleted
  on the client. Hashes: TESTER patch 6844d4f8a6ae156a216850ca027b29fc7ffe456a96661e3c2332ae4cb1421f87, players' patch
  a1c699475041d986e00fb0b52c20fde71f080557b637802b373950088d39aaa6.

## 0.73.80-coop2mp.81: the 0.73.79 report's Phase 1, modded planes / skins / weapons in co-op (runtime 0.32.24; 2026-11-04; not yet run in game)
From the 31-round co-op test of 0.73.79 (testing/logs/2026-11-04/R30_FINDINGS.json; Claude Docs "AC8 Survival Mode:
0.73.79 Co-op Test Report & Plan, 4 Nov 2026", Phase 1). Built by agents on separate branches, merged, each part
reviewed, then a second independent review of the whole (7 findings kept of 9, each verified by refuters). None of it is
a hard rule until a test confirms it. Every Lua test, fwkind_test, the Worker's test and the native build (online and
offline, clang 18 here) pass.
- Alive checks (perf 1/2): sv_spawn.lua ALIVE keeps each unit's SV_UnitAlive answer (at most ~1 s old) and asks again in
  turn, 8-32 asks a second; a spawn / recycle / a plane seen down asks at once; a unit nobody asks about is forgotten
  after WATCH_S (the tick's own refresh keeps its `want`). `alive: round N: ...` a round. Its reads: the rounds' checks,
  orders, Wolf holds, the ace break-off, the shuttle, the Spaceport's looks (ships by hull every 3 s).
- The shuttle (specials 0): its unit recycled after it's taken off and as its next round is planned (SPC.canStart);
  spawnShuttle retries on -3, then SPC.unplan makes the round a normal one from the start.
- Specials pacing (specials 1; CFG.specials chance_step 0.15, max_gap 4, bag, swap): the chance grows per round without
  one (ace rounds not counted), one sure after max_gap, a shuffle bag (only a kind drawn from it goes back in; a kind
  whose ready() says no is never in it: kindReady), a pick that can't start swapped (specialSwap) or, on an ace slot
  with none to swap, that ace round (called out as one). Every roll logged. Trade-off: ~7.6 ace rounds in 46, not 8.4.
- The landing menu's windows (perf 4): sv_core.lua LANDW keeps them, looked at once a tick, walked for only on landing,
  a page closing, a press on a page not kept, every_s 2 with none shown, a 30-s backstop ([hud.landing]); the STORE
  gates of co-op (inStore: the hold AND a window shown at the last look) and SHOP.decorTick (liveObj) read them.
- VALKA (specials 2 / perf 6): her railgun modules kept as made (NotifyOnNewObject), her round's settings on its class
  default (SPC.V.roundDefaults: "opener" no damage held until s.harmUntil = shot + reveal_s + 3 + eml_life_s, "hers",
  "off"), her rounds kept as made (SPC.V.roundHook) and her damage put back on pooled ones at her charges (roundsHarm),
  her assets loaded one a tick in the break.
- Co-op: the SV_Spawn wrapper names the unit for a host spawn whose caller didn't (the LCAC lanes, the STORE defences,
  the shuttle pad: ids on every game); a dn naming you takes the copy down with your plane as cause ([coop]
  kill_callout); a player lost in the mission leaves the hold after hold_lost_s 15 (state cleared on a new run and a
  rejoin); COOP.takenOff marks what the host takes off without a kill (craft, troops, the fleet, rockets, debris, the
  garrison, the island; only objects still up) as nobody's.
- Modded planes and skins: a plane with no stock code sends its class path and stock base (hi 10-11, pi 11-12); each game
  spawns their class where it has it ([coop.real_paths]: the Falken's), else the base / [coop.real_fallback] / [coop]
  real_default (f16c), the AI stand-in last; a skin this game hasn't (DT_Skin / SkinDataMap_) or a bad id is -1, the
  emblems kept. Any plane code in those two sections from survival.ini (loadIni's open maps). modsync_test.
- Weapon stand-ins (tools/re/COOP2MP.md "Weapon stand-ins"): a launch whose weapon number their real plane here hasn't,
  or has as another kind, goes to the nearest weapon of its kind (M.weaponFor / M.standInPay: the same special where a
  changed loadout put it, its own number when known or trusted, else the nearest missile special or the standard missile,
  a laser / ESM only as one of its kind, a bullet special as one or a gun burst, M.gunOff lets the burst go). Needs
  runtime 0.32.24's SV_PPWeapons (the kinds seen launched, FwLearn, keyed on the plane's address, index, name, class and
  table: runtime/fwkind.h) and its FnFlush gate (a shot onto a weapon known to be another kind refused); on 0.32.23 the
  launches go as sent, as before. [coop.sync] standins, standin_gun_s, standin_table (off: the table kinds, FwkScan,
  observed only). fwkind_test.sh, coop_fire_test.
- Leaderboard: a run refused only as an unknown build is kept in config/refused_runs.txt and resent at later game starts
  for 14 days (one answered "played on other files" kept too). The Worker checks a resent run's own build (run.build,
  under run.mod) when the files it's sent from are a registered release of any version: REDEPLOY the Worker
  (leaderboard/src/index.js) before this matters.
- The fleet watch only in a Spaceport round; the default ini's [specials] comment names the ace trade-off.
- Open, check in the next test: a joiner's bombs and unguided rockets on the now-linked landing craft (the floor sends a
  hit only for a missile / the gun / the map: COOP2MP.md's floorLoss); stand-ins in game (runtime 0.32.24 only).
- Given out as patches (2026-11-04, Scripts/*.lua + config/survival.default.ini over a 0.73.78 COOP2MP install, staged as
  package_release.sh does; on runtime 0.32.23, no SV_PPWeapons): testing/builds/AC8SurvivalMode_COOP2MP_0.73.80_TESTER_Patch.zip
  (Saint Alessia: test keys and loggers kept) and AC8SurvivalMode_COOP2MP_0.73.80_Patch.zip (stripped, quiet logs);
  CHANGELOG_0.73.80.txt. Both load in lua_load_test. Their build hashes come from the game's first log line: register them.

## 0.73.81-coop2mp.82: the Spaceport Assault's Tu-160s (runtime 0.32.24; 2026-11-04; not yet run in game)
The user, 2026-11-04: "In the spaceport assault round, can you please add TU-160's that come from both the North and the
south to target the airfield and bomb it", then "spawn everytime a WASP gets destroyed, have 4 bombers each". Lua only
(no build data), two independent reviews (2 of 2 and 4 of 4 findings kept, each verified and fixed with a failing test).
- sv_spaceport.lua (SPORT.tuPlan / tuWasp / tuTick / tuUp; CFG.specials.spaceport.tu160 / [specials.spaceport.tu160]:
  enabled, aircraft t160_common, group 4, delay_s 6, bearings 0, 180, spread_deg 10, distance_km 28, 34): each Wasp sunk
  in the assault (shipsTick) asks for a group of `group` sent delay_s later, the groups taking `bearings` in turn (the
  first by chance), through sv_spawn.lua spawnBomberFrom (spawnBomber with a bearing, a row and a range): the heavies'
  route over the runway, bomb runs, minimap pings, a heavy's pay, D.up. A group is the heavy flights adding up to `group`
  (tuOptions): the build has only a 2-ship (EA_Unit_01_Air1) and a 4-ship (EA_Unit_01_Air2), so a group of 4 is the
  4-ship and the next waits until it's down (hard rule 16), holding the round (SPORT.busy); a flight up but not this
  round's drops its group. Not in the retake or after a capture; a capture drops groups waiting and withdraws those up
  with the fighters (off D.up / D.heavy / D.heavyPath, planes down and withdrawn, recycled at the next round's plan,
  COOP.takenOff, and "wd" so joiners mark their copies withdrawn: COOP.withdrawn). A group due waits while you're solo at
  the airfield; the Tu-160s don't count in the fighters' wave (sv_rounds.lua); the HUD row and "spx" (5th field) carry
  how many are up. Log lines: `special: the Tu-160s: a group of N for each Wasp sunk ...`, `special: <Wasp> sunk: Tu-160
  group N asked for`, `special: Tu-160 group N (...): 4 from the NORTH (bearing B; EA_Unit_01_Air2: 4 (12 objects))`,
  `... waits: its flights are still up from the last group`, `special: the Tu-160s this assault: ...` at its end.
- sv_flights.lua HEAVY.route / heavyNext (any heavy raid): a fresh spawn's route entry is kept until its planes are seen
  (bombTick dropped it before they reached the plane list in 2 of 4 tick phases, so a lead shot down first left its
  wingmen without the loop: they never bombed; seen in the r30 host log) and only planes born since count.
- 4 Tu-160s for every Wasp at once needs more heavy 4-ships in the world data (survival_events.HEAVY_BOMBERS /
  HEAVY_TRACKS, BOMBERS, the routes' object names from copy_unit rather than the stock package): a full build. Lua uses
  whatever CFG.airfield.bombers.heavy_units lists.
- Patches (2026-11-04, Scripts + default ini over a 0.73.78 COOP2MP install, on runtime 0.32.23):
  testing/builds/AC8SurvivalMode_COOP2MP_0.73.81_TESTER_Patch.zip, AC8SurvivalMode_COOP2MP_0.73.81_Patch.zip,
  CHANGELOG_0.73.81.txt; they replace 0.73.80's (everything in it too). Register their hashes from the game's first log line.

## 0.73.82-coop2mp.83: the crash on launch, Lua kept on the game thread (Lua only, on runtime 0.32.23; 2026-11-04; not yet run in game)
Saint Alessia's crash on launch of 2026-11-04 (12:28:34, logs in the user's upload "crash_on_launch"): the main menu's load
held the game thread 54 s; the crumbs show 0.73.75's watchdog ("tick lost: queued again") every 10 s from UE4SS's async
thread (t28300); the game thread came back, ran the five queued ticks one after another, and the watchdog fired again
inside them; the dump's fault is on the GameThread in UE4SS.dll+0xc634cd (lua_getiuservalue, reading 0xa), 70 ms after the
tick's last log line. UE4SS 3.0.1's source (LuaMod.cpp, v3.0.1): LoopAsync's function runs on its async thread with no
lock (process_delayed_actions; an error from it removes the loop for good); ExecuteInGameThread makes a Lua thread and
two registry references on the CALLING thread, outside its lock; the game thread runs every queued action in one pass
under m_thread_actions_mutex (process_event_hook), so queuing one from inside an action edits the list it goes through,
and a throw in get_function_ref leaves m_is_currently_executing_game_action set (no action of any mod runs again: the
0.73.75 stall); RegisterKeyBind's functions run on UE4SS's input thread; NotifyOnNewObject's callbacks on the thread
that builds the object, with no lock. All in this mod's one Lua state.
- sv_main.lua's loop: the async function reads only its flags and the clock (captured at load) and queues the one job
  made at load, only with none waiting or running and SETTLE_S 0.02 after the last ended (UE4SS lets go of a job's
  references just after it returns); a job holds `waiting` until it ends (doneAt, waiting, running in that order) and
  counts itself in `runs` as it starts, and the async function queues only if `running` is still false and `runs` is
  what it was at its first look; a tick taken as lost is queued again after 10 s, then 20, 40, ... with SV_Crumb's fixed
  text after the queueing (`lua: tick lost: queued again (seen on UE4SS's async thread)`: native, no Lua made); the job
  logs the count on the game thread (`tick: the game thread hadn't run the tick queued 10 s or more before ...: queued
  again N times (M so far)`). The re-queue can't bring back 0.73.75's stall: UE4SS sets its "an action is running" flag
  before it looks the action's function up, and that lookup's throw leaves it set (no game-thread action of any mod
  runs again); the crumbs show it.
- Keys (sv_core.lua KEYQ): every RegisterKeyBind is wrapped; UE4SS gets a function that only does hits[i] = hits[i] + 1
  (96 slots made at load); the job runs the binds' own functions for the presses since, first thing, on the game thread,
  up to KEYQ.MAX (4) a key, with ExecuteInGameThread running its function at once meanwhile. Keys act up to 1/8 s later.
- Review of 2026-11-04 (3 lenses, each finding verified twice; 4 kept of 5): a collectgarbage("step", 0) at the job's
  end was taken out: in Lua 5.4 it drops the pause after a cycle, so the whole heap was collected every tick half
  (1-5 ms more, measured) and collector steps elsewhere came more often, not less. Don't force collector steps. A second
  pass (2 lenses; keys: nothing) kept the test's gaps and led to `runs` (a job run whole between two reads of the async
  function, refuted as unrealistic but closed anyway).
- tools/checks/tick_loop_test.sh (the loop and KEYQ as they are: allocation and calls on every async path, the back-off,
  a job starting inside the async function's clock read, during the lost path's crumb, a look inside the job's end, a
  job run whole at the last check (a line hook), keys before the tick; it fails on the 0.73.75 patterns and on each
  guard taken out, but for the `running` half of the last check, which `runs` covers).
- Candidate hard rule (once a test confirms it): no Lua work off the game thread. A LoopAsync function reads upvalues and
  the clock and queues a job made at load; a key bind only counts; never ExecuteInGameThread from inside a game-thread
  action; no forced collector steps.
- Still open: Survival's NotifyOnNewObject callbacks (World in sv_config / sv_core, LiveAIGameObject, LiveMissile, ...)
  run on the constructing thread with no lock, and the async thread's ExecuteInGameThread (8 a second) makes a Lua thread
  there. Only the native runtime can close it: a game-thread per-frame hook calling the Lua tick and reading the keys
  (no LoopAsync, no RegisterKeyBind): next full build.

## 0.73.83-coop2mp.84: the logs of 2026-11-04 (Lua only, on runtime 0.32.23; 2026-11-05; not yet run in game)
From the second 0.73.79 co-op run (Saint Alessia hosting dukka, OdyDio, Rapt0r, Aquila, 32 rounds; Rapt0r's own log and
notes), her 0.73.81 run (14 rounds), Nada's 0.73.78 solo Casual run to round 44, a short 0.73.78 solo session and
Shazzy's 0.73.82 host log (testing/logs/2026-11-04b). Four analysts, each finding verified twice (the workflow's
journal), and the user's radar report. None of it is a hard rule until a test confirms it.
- The radar (user: "people who leave and rejoin, their plane disappears correctly but not their radar blip"): every
  co-op plane hidden here (left, out of the mission, DOWN, a rejoin waiting for its airframe, set aside) deactivated
  (LiveGameObject.bIsActivated false, put back as it was when shown; kept by address with the object's name, M.radarSt,
  so a rebuilt player table or a reused address can't lose it or hit another object); a set-aside plane also moved
  [coop.rejoin] aside_far_km (1000) off the map, kept off it and deactivated (asideTick every 5 s, said once), forgotten
  with its level (COOP.levelDrop). radar_off = false leaves the flag. Which of the two the minimap heeds isn't known.
  Reviewed (3 of 4 kept). coop_rejoin_test.
- The Alicorn's pools (A1 / B1, Rapt0r's "desync"): SPC.alcnPool kept its 131 parked pools' addresses after its unit
  was gone and hostPlane / clientPlane skipped any later plane at one of them (no co-op id: 18 of 41 hunts on partly bound
  flights, 86 strays torn down on one joiner, a resync wave every ~3 min). Only SV_Unit_Alicorn's planes are skipped now;
  the set goes with its unit, its level and a joiner's fresh copy. coop_ground_test.
- The late-run lag (A2-A4, B5): SV_UnitAlive walks every unit on the spawner's list (~7 ms an ask late in the 0.73.79
  run). airUp reads the allies' kept counts, the allies' share asks each unit every 4 s, the leave probe every 5 s,
  co-op's unlinked check every 10 s, the director through ALIVE; and a special's units come off the list once its round
  is over (sv_rounds.lua SPC.recycleLater / recycleTick / recycleUnitsOf: SV_Recycle(unit, 0), only one with nothing alive,
  only units spawned in this level (SPC.seenUnits), one every 0.5 s from 15 s on: the runtime holds 64 deferred destroys;
  the Spaceport's fleet but a ship carried into the retake, its waves and troops, the retake's, the amphibious round's,
  a boss unit left at 0; host and joiners). The native per-unit walk stays (the next full build: a desc -> unit cache).
- VOID WATCHER 1 going home (B7, R30's ghost): the host sends its copies' 'dn|<id>|r' (unpaid) before RE_SV_AwacsRemove
  (COOP.removeNow); a joiner with a copy left at the event takes it down and recycles the unit 2 s on.
- B4: 'ROUND N KILLS' is each game's own (COOP.localCallout; a joiner's from its RUN.roundKills at the host's "wait").
- A8: the Worker's SPECIALS gains valka (her wins were dropped before the score): REDEPLOY the Worker.
- A9: the pay audit (TESTER logger) logs RUN.earned's change, after co-op's split.
- Shazzy's 0.73.82 run wasn't sent ('edited: coop.aircraft_per_player = 0.25', the host page's CO-OP ENEMIES): the row's
  help and the host's START RUN now say a co-op run off the room's default rules isn't ranked.
- 0.73.82 in game (Shazzy hosting cressendo, 7 rounds): no error, no lost tick, the tick 4-6 ms; key presses not yet seen.
- Review of the whole diff before shipping (2026-11-05, 3 lenses, each finding verified twice): 2 low findings, both
  refuted (the recycle pace against the 64 deferred destroys: a real Spaceport leaves ~31-33 units, the logs never showed
  more than 10 waiting; a joiner's kills callout a sweep early: the host's own has the same timing, display only).
- Given out as patches (2026-11-05, Scripts + default ini over a 0.73.78 COOP2MP install, on runtime 0.32.23):
  testing/builds/AC8SurvivalMode_COOP2MP_0.73.83_TESTER_Patch.zip and AC8SurvivalMode_COOP2MP_0.73.83_Patch.zip,
  CHANGELOG_0.73.83.txt; they replace 0.73.82's. Register their hashes from the game's first log line; redeploy the Worker.
- Left for later (found, not yet fixed): ammo unreadable on Casual (SV_Ammo -1 all run: caps, STORE ammo, WEAPON BAYS,
  FLARE PODS re-apply off), SECOND CHANCE's floor in solo after an airfield stop (INS.tick reads MinHealth back only with
  co-op's floor), a restart's fake 'round 1 clear', enemies aiming at a departed player's hidden plane, VOID WATCHER's ESM
  field list growing, the between-rounds repair walks, the Alicorn's VLS never matched in its spawn record.

## 0.73.84-coop2mp.85: the crash on quit (Lua only, on runtime 0.32.23; 2026-11-05; not yet run in game)
Shazzy's crash on quit of 2026-11-04 19:49:19 (0.73.82, co-op host, round 24, GUN tier 2; logs and dump in
testing/logs/2026-11-04b/r24_host_Shazzy_0.73.82_quitcrash): UE4SS.dll+0x2ab5bd on the GameThread, reading obj+0x10 (its
class) of a freed, unmapped object, 0.1 s after `level gate: closed` and the run's leaderboard lines, before the main
menu's World. The stack held the key "damage" (UE4SS's FName lookup of a Lua property). runLeft's TAC.reset wrote the
gun's stock damage back into the class default UP.apply kept (BP_plwp_gun_x1_C's: the player plane's weapon blueprint,
loaded with the level), after the level's purge had freed it; most quits got there first (Saint Alessia's r14, r30, r32
with the upgrade: a race). The 0.73.77 gate forgot every part's kept objects (LEVEL_DROPS) but this one. The F1 crashes
on quit of 0.73.76 were at the same address; the 2026-11-01 s4 quit crash read "Pawn" (another cause, fixed in 0.73.73).
None of it is a hard rule until a test confirms it.
- sv_tactical.lua: gunLive(g) = liveObj(cdo) and the same full name (SV_ObjChain checks the memory readable, then the
  GUObjectArray slot, not unreachable or garbage: the purge in progress won't free it); TAC.reset writes only then, else
  `upgrades: N gun class default(s) gone with the level: forgotten, not touched`; UP.gunStock[class name] keeps each gun
  class's stock damage for the session (never an upgraded value read as stock); UP.apply takes a class default again
  when the kept one isn't live.
- Same family, found by the reviews (each verified): VALKA's sky (sv_hud.lua: hudRed's at-once path only with its actor
  live and the level not torn down, skyApply's components liveObj, LEVEL_DROPS "VALKA's sky"); the Ladon missile's class
  default (sv_ladon.lua HIT.cdo: liveObj, forgotten in HIT.reset); VALKA's flare (liveObj); the shuttle pad (sv_rounds.lua:
  SHUTTLE.gone / pad / obj outlived a quit and the next run's first shuttle round read the old level's actors with
  valid() and wrote their flags: LEVEL_DROPS "the shuttle pad", each hidden object kept with its name and brought back
  only live under it, the take-off and shuttleHealth liveObj / liveAddr; a restart keeps its pad); VALKA's song (sv_sound.lua:
  a quit during it lost AKE_System_BGM_Mute_Off, which the runtime refuses while the gate is closed; SND.unmuteDue posts it
  again from the next level's sound tick, every 2 s, 15 tries). Only there: the runtime's BgmController reaches the
  game instance through Survival's spawner (SpawnerReady: the gate and g_spawnerLost, cleared by SV_Reset), so the
  main menu, the hangar and other modes may stay muted until the next Survival run (second review, kept low). Next
  full build: BgmController keeps the game instance from its last good lookup and posts through it (UObjLive) when
  the spawner isn't ready, and the retry runs from every tick.
- tools/checks/quit_cdo_test.sh (each guard mutation-checked; its valid() stub counts a freed read as the crash).
- Lesson (candidate hard rule once a test confirms it): a game object kept between ticks, a /Game/ class default
  included, is read only through liveObj / liveAddr (never valid(), which reads it), and every part that keeps one
  registers a LEVEL_DROPS entry; a cleanup at the run's end checks liveObj before it puts anything back.
- Given out as patches (2026-11-05, Scripts + default ini over a 0.73.78 COOP2MP install, on runtime 0.32.23):
  testing/builds/AC8SurvivalMode_COOP2MP_0.73.84_TESTER_Patch.zip and AC8SurvivalMode_COOP2MP_0.73.84_Patch.zip,
  CHANGELOG_0.73.84.txt; they replace 0.73.83's. Register their hashes from the game's first log line.

## 0.74.0-coop2mp.86: GONE FISHIN', the day-night arc, THE FESTIVAL, THE ESCORT, THE DECOY, the ZFA-44 and a lightning Anomaly (runtime 0.32.24; 2026-11-06/07; built, NOT yet run in game)
One night's work (user, 2026-11-06: "start doing everything", then "finish everything off tonight, do a code review and a
clean up, package a build, including one for Alyssa to test. I want all of our stuff we built tonight in this build").
Branches: feature/fishing (research, the build data), feature/fishing-lua, feature/zfa44, feature/decoy (the integration
branch every other was merged into), feature/thunder; worktrees E:\ACE8 SM fishing / fishing-lua / zfa44 / decoy /
thunder (build\ inputs and tools\bin / llvm junctioned to the main tree's). None of it is a hard rule until a test
confirms it. Design and research: FISHING_ROUND_PLAN.md (section 0: the user's decisions), tools/re/FISHING.md,
ESCORT.md, DECOY.md, ZFA44.md, THUNDER.md, COMONA_MAP.md, LASER_INTERCEPTOR.md; build/research/{comona,escort,decoy,
lightning,festival} hold the dumps and scripts (git-ignored).
- Rule (user, 2026-11-06): no other mod's files, assets, tables, values or text in Survival (the Project section above),
  with one exception: the ZFA-44 from the user's OWN AC7 mod Alicorn Special Raid IV ("my own mod and I NEED the FA44
  ... the Model inside is edited": its uavs_SM, paint, actor and weapons).
- GONE FISHIN' (sv_fishing.lua, SPC.kinds.fishing; from round 7, once a run): Comona's festival needs fish, SAL enlists the
  air force; 24 invisible shoals (a Survival copy of the stock invisible turret pawn GR000_dummy, SV_Shoal, + an 8 m
  EnemyPawn hit sphere added at spawn) at three grounds 7.5 km out (North Shoal, Lighthouse Bank, The Deep Hole), one
  random 24-catch deck, 180 s, each catch credited to its shooter (co-op: the host draws, each player's own haul), SAL's
  allied fishing boat (VE027_boat2) with a kg penalty on this game's own hits, a weigh-in card (grade, pay: ~6,000 Z an
  A, ~9,000 Z an S at round 7), SAL's lines on Survival's new subtitle strip (sv_subs.lua SUB.say).
- The day-night arc (sv_sky.lua; F = the fishing round): F+1..F+5 the sun sinks, F+6 sunset, F+7 night (moon, stars at
  Mission 22's maximum), F+8..F+11 the sun rises in the east (+X; north is -Y) to midday, held after; written to the sky
  renderer's working copies + the sun light (the stock CSP_ms04 asset never touched), MPC values each tick, restored on
  run end / quit / restart; co-op "rnd" field 15 = F. The level's clock (10:10) is only a display. VALKA is not ready
  from F until the arc is back at midday (user).
- THE FESTIVAL (sv_festival.lua; round F+6, never drawn): thanks from SAL and COMONA CONTROL, the stock Comona air raid
  siren at the airfield, four Online Mode searchlights (GR053_seli), Tu-160 formations from N / W / S on 15-lap stand-off
  racetracks 25 km out, salvos of Mission 30's path-flown cruise missiles (slcmp, boxed, 25 HP) at the runway; an impact
  costs the airfield 8.
- THE ESCORT (sv_escort.lua; from round 9, once a run): the allied B-1B CHARLENE and YORKE / ROCK (Su-57), ALI (Su-33),
  DANIELLE (Su-35) from the SW corner (-41.1, +31.4 km) to the airfield, enemies ordered onto her (out of the director
  and the hunt), AI landing the stock way (Mission 14's C-130 / Mission 26's carrier landing: glide-slope final, a rollout
  at 50 km/h, MOONCHILD's taxi path reversed to five parking slots), the escorts orbiting 4 km before the IAF and released
  one at a time, safety timeouts; her loss fails the special (the run goes on); the win unlocks VAMPIRES (the ZFA-44 carriers) in the
  STORE for the run (the room's): Mission 17's cargo ship, allied, 15,000 Z, two at most, 3 rounds' service, launching
  ZFA-44s from its container launchers (Mission 17's drone arms: E_Unit_01_drone_* units, user: "launch the ZFA-44 the
  same way those drones launch"), a pose spawn as the fallback; the carrier borrows the AIRFIELD page's Revive row while
  nobody's down (no free STORE row).
- The ZFA-44 (tools/zfa44, sv_zfa44.lua): the user's uavs_SM (a CFA-44-based static mesh with Morgan / TLS parts, 24 m)
  as one skeletal mesh SK_ZFA44 (a static mesh of ours crashed AC8 in SOLG's T0), the user's paint as ordinary textures
  on the x40a's gear material instance, cooked versioned into SurvivalMode_ZFA44_P; ZFA.dress puts it on its host (an
  allied Su-47 row SV_Zfa_Ally) at run time; dev and ZFA=1 zips only.
- THE DECOY (sv_decoy.lua; from round 10, once a run): a Marker UAV (OP0033_uavst, its ALiveAIAirshipLaserPod) far north
  as bait; then up to 35 trap UAVs round the players, each locking its closest player with the Tonitrus Spear guidance
  laser; 8 s to kill it before the Spear (Mission 19's BP_RodsFromGod from its virtual shooter, fired at Player; 200 direct)
  is called on that player; only the locked player's game runs the strike (KEEP_EVENTS ^RE_SV_Decoy).
- IFF FATAL ERROR / DI..ANT TH..D..R (the THUNDER block in sv_anomalies.lua, TEST ONLY: only its test key brings it, user):
  an A-10 (a10c_common on MINDRIPPER's unit) carrying AC8's stock lightning volume (BP_LightninigVolume_MS12): its strikes
  only hide the HUD 2 s, play electronic noise 6-10 s, shake the camera and hold an engine flag 0.7 s (no damage, user);
  AC8's lightning only ever strikes player planes; + a storm test key.
- Keys: tools/README.md's "Ctrl keys" table (every Ctrl key bound once; the test keys stripped from friends' zips).
- Packaging: novalka.py takes "valka" out of the rotation wherever it sits; package_release.sh ZFA=1 keeps the ZFA-44
  (zip suffix _ZFA44) and strips the default ini's test-only sections too; four Lua tests made CRLF-safe.
- Code review of 2026-11-07 (three reviewers, each finding verified; one fix agent): see the fix list below.
  c0c56fd: co-op joiners' own container-launched ZFA-44s count for nobody (stand-in set, the arm recycled before a
  forwarded launch, taken off with their ship by "es" field 10); THE ESCORT's escorts start on the build's sides (they'd
  have crossed her track at Go); a pause-menu restart takes the festival's siren and searchlights, SAL's boat, the card,
  the escort and the carriers off (the siren looped all next run); the arc keeps its sky view while live (it re-walked
  ~100-350 ms every 30 s); GONE FISHIN' once a run across a host migration and only with its rows; SAL's boat out of the
  host's hp batch (every joiner lost kg for the host's hit); a carrier sunk by its hull; a joiner's weigh-in keyed by run
  and clamped; a festival impact record can't pay another missile (COOP.payHold, 1.5 s); kept sky values retried until
  put back; ally copies switched off (not exploded) on "dn|id|r"; the ini rotation in CFG's order; the Worker's SPECIALS
  gain escort / decoy / fishing / festival (REDEPLOY the Worker); package_test.sh's ZFA block and ini strip.
- Still open: none of it run in game (each doc has its checklist; the riskiest: the shoals locked and hit, the renderer
  copies holding the sky, the B-1's landing, a Su-47 launched from a drone rack, the guidance laser on a moving mark, the
  Spear fired at Player, the Online searchlights, a Lua-spawned storm striking, the ZFA-44's paint route); the world data
  is now 937 KB (the largest stock one is 615 KB); the carrier borrows the Revive row (no free STORE row: build data).
- The STORE item renamed VAMPIRES (user, 2026-11-07: "the ZFA-44's store item should be called VAMPIRES"): its row, THE
  ESCORT's win callout ("VAMPIRES IN THE STORE") and the ALLIES row ("VAMPIRES n"); the ships keep "ZFA-44 CARRIER" on
  their boxes and callouts, the item key ZfaCarrier and [shop.zfacarrier] as they were.
- The ZFA-44's TLS pod (user, 2026-11-07: "make sure that the textures for the TLS on the ZFA-44 were ported over from
  ACE7 too"): AC7's w_tls_x1_D / _N were in from the first build; its w_tls_x1_MREC now too (T_ZFA44_Pod_LM_MREC, and the
  fairing's mrgn_00_MREC crop), used by paint 4, which had put the body's MREC on the pod. The default paint 3 (the proven
  route: flat normal, flat Livemap) shows each part's colour map only; Ctrl+9 (test) cycles 1-4. The pod's lens stays on
  AC8's canopy glass, as AC7 had it on glass (w_tls_x1_Glass_Inst: only the generic Glass_N, tiled).
- GONE FISHIN's shoals all round SAL's boat (user, 2026-11-07, after Alyssa's first test: "the shoals need to be more
  numerous and spread around the boat"; her log ran only Ctrl+F10, which has no subtitles, never Ctrl+HOME): six units of
  8 (SV_Unit_FishA-F, 48 shoals; world data 941 KB), A on the boat (its shoals 300-800 m out), B-F on a 1.9 km ring
  turned at random each round (sv_fishing.lua FISH.grounds, CFG ring_m); the three far grounds gone; grades unchanged
  (an S takes about two thirds of the shoals). Her Ctrl+F10 test: shoals spawned, one hit each, splash: confirmed.
  COOP_TAG -coop2mp.87 for it (.86's zips have three grounds and can't link with it); zips in the main tree's
  build/release: dev / TESTER ff6b43e2...416a607, friends d144b111...24dd9f0 (register these; every earlier 0.74.0 hash is
  superseded); installed.
- THE DECOY after Alyssa's test of 0.74.0 (2026-11-07, user: "Tonitrus Spears Missed the Player and were rapid firing",
  "clouds were warping in and out"; her log, sv_decoy.lua, tools/re/DECOY.md). The finding: the stock BP_RodsFromGod has
  no HeightLimitAreas (ALiveMeteoriteImpact flies a rod to the target's X/Y at that area's height, sea level without
  one), so every rod fell to the sea kilometres under her plane (4-7 km up; health 138 -> 138 at all 24 impacts), and
  each landed 1.0-2.3 s after its call, not the 3 s led. Each UAV kept its own lock and locked again 6 s after its
  strike: the Spear every 2-4 s, four at once. Each rod's cloud blast (BlastEffectInfo, Impact at 115.6 km) used
  Comona's unset ExplosionEffect: the clouds warped with every strike. Now (not yet run in game): one lock on a player
  at a time (locks_per_player 1 in .88, 2 from .89), the next lock_gap_s 4 after the last, a UAV relock_s 15 after its own; the lead
  fall_s 1.6, learnt from each impact (lead.learn: the median of the last 7, 0.8-3 s); the hit judged by Lua
  ([specials.decoy.hit]: a strike you didn't fly dodge_m 200 off the line you held at the call hits, RE_SV_DecoyKill);
  a rod that has a height area gets it at your height (the stock one has none: an empty TArray is never grown from Lua);
  the clouds as the user's own mod fixed them ([specials.decoy.clouds] mode hole: the rods' blast at the clouds' height,
  the sky's, blended sky's and key frames' ExplosionEffect set every 5 s while the Spear is about, every value put back
  60 s after it's quiet or at a run's start over; off = no cloud blast). Log lines `decoy: the Spear hits you (judged:
  ...)` / `missed you (judged: ...)`, `the Spear's rod's height area ...`, `the Spear's rod: virtual launcher ...`,
  `the sky's cloud blast (...) set for the Spear`, `put back`. decoy_test.sh covers the pace, the judged hit and the
  learnt fall. Her second log also ran GONE FISHIN' (Ctrl+HOME): SAL's subtitles played.
  COOP_TAG -coop2mp.89 for it, with two locks on a player at a time (user: "Only two UAV's can lock onto a player at
  a time"; locks_per_player 2, each lock_gap_s 4 after the last on them, so their strikes come 4 s apart at least);
  then COOP_TAG -coop2mp.90 with a miss chance (user: "Tonitrus spears should also be able to miss the players
  sometimes"): a judged strike hits with hit.chance 0.6 on the line you held at the call, less the farther off it, none
  from dodge_m 200 (DECOY.hitChance; the log line names the chance and the roll). Zips in the main tree's build/release: dev / TESTER
  259ef65a...4886285, friends f09be8e6...730f5c3 (register these; every earlier 0.74.0 hash superseded); installed.
- THE ESCORT after Alyssa's test of 0.74.0 (2026-11-07, user: "Airfield: gone", "su-57: submersable", "B-1: gear down
  headed south", "other escorts: fucked off"; her log: the route given again at 450 km/h was followed, the separate final
  path started mid-route never was; the escorts' wait-circle paths began 8-12 km round the circle from them; the players'
  landing closed from her final until everyone was down). Reworked (COOP_TAG -coop2mp.91; not yet run in game):
  CHARLENE flies ONE path from the start to the rollout's end (SV_Path_CharRoute: her route, the 3 deg final, the
  rollout), given again at each new speed (her Final / FinalSlow / FinalShort / Roll records: Mission 14's C-130 lands
  on the path it flew in on, its records only change the speed), her approach watched (farther than her closest by
  recover_m: given again, recover_max times); the landing test T0 on its own records (RE_SV_CharT0*, SV_Path_CharFinal:
  the final and the rollout); the escorts hold over her from her final (<rec>Orbit: off their paths, their area on her at
  4 km; no orbit paths any more), then one at a time once she's off the runway onto one landing circuit
  (SV_Path_EscCircuit: downwind WSW 3 km north of the runway at 600 m from geo.circuit_start, a 1.5 km base turn, the
  final, the rollout), started only with its first point 0.8-6 km ahead within 50 deg of the nose (hard rule 2), or after
  hold_max_s anyway; an escort's slow-downs only on the final leg; the players' landing closed only while one of them is
  within close_km 5 on the final leg or rolling out, open again reopen_s 5 after; a track line every track_s 3
  (`escort: track: ...`). World data 857 KB (the orbit paths gone). escort_test.sh covers it (the hold, the circuit, the
  started-anyway, the downwind's no slow-down, the recovery, the airfield closing and opening, T0's records).
- Candidate hard rule once confirmed: an AI plane on a path doesn't take a different path given mid-path; give the same
  path again for a new speed (Mission 14's way), or exit it first and start the new one a little ahead.
- No normal aircraft in GONE FISHIN' or THE DECOY (user, 2026-11-07): GONE FISHIN' flew alone already (alone, aircraft 0);
  THE DECOY's fighter_share 0 (was 0.3: Alyssa's round had 2 fighters). Neither gets a raid, strike package or jammer
  (normal rounds only).
- The Spear's blast (user, 2026-11-07: "that texture file I sent you for the Tonitrus Spear, can you add that into the
  Tonitrus Spear that we're using in this build"; the textures listed were those of Mission 25's cutscene Rods-from-God
  explosion): the stock systems /Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_Explosion001 / ShockWave001 (air: at a
  judged strike, on you or on the line you left) and + SandSmoke001 / RingSmoke001 (ground: the bait's strike on the
  airfield), spawned by Lua ([specials.decoy.blast]); the user's mod's pak itself holds stock overrides (BP_RodsFromGod,
  DT_LiveWeapon, three player planes) and isn't used. The bait's own Spear on the airfield (its laser's mark there: the
  game's strike as it goes down; user: "it does no damage to the airfield") takes bait_strike.damage 40 of the
  airfield's 250 where a rod made after the bait's end stops within 2.5 km of the mark (or at the mark 8 s after one
  showed), the host's or solo (AF), its blast on every game. decoy_test.sh covers it.
- GONE FISHIN' seen in game (the user's screenshots, 2026-11-07, round 1 forced): the shoals round SAL's boat, the
  catches, SAL's and CONTROL's lines and the weigh-in card all work (48 of 48, 1,530 kg, grade S, +12,180 Z). Fixed from
  them: the subtitle text wrapped narrower each line (AutoWrapText on an auto-sized slot wraps at its last width) and ran
  out under the box: AutoWrapText off, WrapTextAt the box less 80, the box grown line_h a wrapped line (SUB.lineCount);
  the weigh-in card sized to its rows; each shoal's box said SHOAL twice: the NPC row's name 02 on its own key
  SV_Shoal_Sub, its text empty. Lesson (not yet a hard rule): a wrapped UMG TextBlock on an auto-sized canvas slot
  needs a fixed WrapTextAt, not AutoWrapText.
- 0.74.0-coop2mp.91 (all of the above since .90): zips in the main tree's build/release, dev / TESTER
  d7e1efbd...e48d9799, friends 9199fc70...24f13db (register these; every earlier 0.74.0 hash superseded); installed.
- The user's .90 session of 2026-11-07 (12:21-12:51; their log and screenshots): GONE FISHIN' 48/48 S; THE FESTIVAL whole
  (16 cruise missiles shot down, 0 on the runway, siren on and off, the searchlights); THE DECOY's pace and judged hits as
  built (most strikes missed off the held line; a hit is a kill: a solo run ends); IFF FATAL ERROR came with its name, warning
  and sound but its Lua-spawned storm NEVER STRUCK (`0 strikes and 0 flashes seen` in 58 s, fought within 5 km for 43 s):
  open (Ctrl+, the storm test, to see whether a strike ever comes); CHARLENE's final as Alyssa's (the .90 path switch). Fixed
  in .91: her box read "sv_charlene" (her callsign key SV_Charlene = her row sv_charlene but for case: an FName keeps its
  first casing; now SV_CharleneCall); THE FESTIVAL's row counted 24 bombers with 12 up (SV_UnitAlive counts each Tu-160's
  parts: the planes counted now); its test key left the sky at F+1 (F clamped to 1; F may be -20..0 for a test now).
  Candidate hard rule once confirmed: a name key must not equal any row's or object's name but for case.
- 0.74.0-coop2mp.92 (the user's asks of 2026-11-07, after the .90 session; not yet run in game): THE FESTIVAL's bombers
  launch salvo after salvo until they're shot down ("have the Bombers continually launching Cruise Missiles until the
  bombers are killed": the first over the launch point or first_launch_<g> on, then one every salvo_every_s 30, launch_gap_s
  30 apart at least, from the next of the formation's three missile units that's free; all three up: tried again retry_s 5
  on, said once; the salvos still spawn at the launch point, their lanes fixed in the build data, and a salvo's unit is busy
  ~160 s, so unhindered a formation fires every ~55 s); THE DECOY's Spear strikes every 10 s ("have the strikes come every
  10 seconds with the UAVs": lock_gap_s 10, relock_s 1; with lock_s 8 one lock on a player at a time in practice, the cap
  of two kept); THE DECOY is called SHOOT DOWN THE RECON DRONE on screen, its bait the RECON DRONE (internal key "decoy"
  kept); CHARLENE's waves ("Keep spawning Multiple enemy fighters until she lands, have them range from 4 to 12 aircraft
  spawning per wave in different directions": [specials.escort.waves] replaces reinforce: until her touchdown a wave every
  every_s 45, first first_s 20, of min_n 4 .. max_n 12 aircraft from free pool flights (2-, 4-, 6-ships; one shot down
  flies again), all from one of eight directions round her, never the last wave's nor one next to it, and only one whose
  spot is inside the combat zone (her start is its corner: a wave there was clamped onto one spot of the edge), km 12-16
  out, spread_deg 12 apart, held while max_up 24 enemies are up, each wave after her; log `escort: wave N: ...`); and the
  leaderboard's builds register themselves (user: "so I don't have to continually register a new version everytime we
  patch"): tools/lb_register.py, run by package_release.sh (online) and package_dev.sh, POSTs /admin/builds/add with the
  admin key from the main tree's leaderboard/keys.secret ADMIN_KEY line (git-ignored, the user's; else an ADMIN line in
  submit.local; one try a build, 401 / 429 stop it; SV_LB_REGISTER=0 skips; no key: said, registered by hand as
  before). Confirmed 2026-11-07: both .92 builds registered by it. The Worker REDEPLOYED by the user the same day
  with this tree's src/index.js (SPECIALS: the
  new rounds, decoy shown as "Shoot Down The Recon Drone"; VALKA; a held run checked against the build it was played on).
  Also a judged Spear hit is heavy damage, not a kill (user, 2026-11-07: "heavy damage", after a run ended on one 5% hit):
  DECOY.hurtMe takes [specials.decoy.hit] damage_pct 50 of your MaxHealth (HealthInternal written, as the STORE's repair:
  ModifyHealth does nothing on the player), RE_SV_DecoyKill only when it would leave nothing (can_kill = false: 1 HP
  left; damage_pct 100: the kill as before). Log `decoy: the Spear hits you (judged: ...): -N HP (50% of your M), K HP
  left` or `...: lethal: RE_SV_DecoyKill fired`.
  Also the subtitle box sized by the line's width (sv_subs.lua SUB.lineCount: a sans serif's advance widths at
  [hud.subs] em_units 50 design units an em, fitted to the user's screenshots, 48.3-49.7; 60 characters a line gave
  a 63-character line that fits on one a two-line box). Built 2026-11-07 (1732 triggers, 3759 execs; all 51 suites):
  dev / TESTER 6a1d65f3...a6df6cb1cb, friends 5fa21d05...c3a16e45, then with the Spear's heavy damage: dev / TESTER
  dce5b521...c426580f, friends 04b50481...7c81a4a6 (each REGISTERED by tools/lb_register.py, the last two by the
  packaging itself); INSTALLED dce5b521 (backups: build/backup/install_before_0.74.0_92 = .91, _92b = 6a1d65f3).
- 0.74.1-coop2mp.93 (2026-11-07, the first build under the version-every-build rule; the same content as dce5b521):
  dev / TESTER 4faabd90...8c42cc37, friends 4b9f05c3...b0549951, both registered by the packaging; INSTALLED (backup
  of dce5b521: build/backup/install_before_0.74.1). Zips AC8SurvivalMode_COOP2MP_0.74.1_[TESTER_]Online_COOP_ZFA44.zip;
  every 0.74.0 zip superseded. Packaging copies build/install,
  so a Lua change needs build_all.sh before package_*.sh (a repackage without it kept the old hash).
  In game 2026-11-07 14:25-16:10 (the user hosting a 15-player co-op to round 23): the day-night arc's sun "isn't moving
  at all" and the night "looks over exposed": the arc wrote the renderer's copies and the light, which Cloudly undoes every
  frame (hard rule 56), while its exposure, sky light and glow did hold, so a full day sky met night exposure. The co-op
  run was unranked by its CO-OP ENEMIES +10% (`[coop] aircraft_per_player = 0.1`, the shipped 0.15), not a fault.
- 0.74.2-coop2mp.94 (2026-11-07; not yet run in game): the arc on the sky asset (CFG.sky.arc.path "asset", the new default;
  "copies" / "custom" kept): sv_sky.lua writes the asset's sun, moon and stars (v.asset), nothing of the sun elsewhere;
  every original put back at the run's end, after a level torn down in the next tick that can (SKY.pending / idleTick:
  the asset found by its path, StaticFindObject; not loaded in 12 tries: it loads again as shipped), the custom sun API's
  moves of the asset kept to be put back too (SKY.keepOrig: sun el / az, moon on / el / az / phase); an asset an earlier
  run or test left changed is put back to its shipped values (CFG.sky.arc.stock.asset, SKY.assetShipped: `sky: arc: the
  sky asset was left changed ...`). The arc checks what's drawn once its sky is off the stock one: the drawn copy's sun
  and the light's intensity a write on (`sky: arc: the drawn sky follows the arc: ...`); 3 checks not following:
  `... does NOT follow ...` and the exposure, sky light and glow kept at the day's (no glare). The sky test's step 2 line
  names the asset and the drawn copy apart; its step 4 (NIGHT) writes the asset too. sky_test 119 checks on a stub game
  that does what the user's test found. Dev b8fc2777...ad169746, friends 998ab9cb...4cb600
  (AC8SurvivalMode_COOP2MP_0.74.2_Online_COOP_ZFA44.zip), both registered by the packaging. Friends need this zip to link
  (another build is refused). Exposure values unchanged: at 16:10 the asset's sun at -2 / -105 under the arc's dawn
  exposure (9 / 14 / -0.9, sky light x0.68) was "very nice" (the user's screenshot). Never installed or given out:
  superseded by 0.74.3.
- 0.74.3-coop2mp.95 (2026-11-07; not yet run in game) = 0.74.2 + the sunset held (user: "slowly get it to transition to
  that sunset"): a step that swaps the sun for the moon or back (SKY.arcAt) holds its own sky through the fight (u up to
  swap_within_x 0.45): THE FESTIVAL's sun sinks 1 -> -3 at -105 at full strength (120000) under the sunset's exposure,
  sky light and glow; the last light fades to dark_factor in the break's first half, the moon at its middle, the night's
  exposure etc. from there (before, the light faded from the fight's start: ~7 at -2 deg). The night's fight holds the
  moon the same way. Dev 9d2036a9...1252e623a, friends 0a7334fc...b1779ae3d
  (AC8SurvivalMode_COOP2MP_0.74.3_Online_COOP_ZFA44.zip), both registered by the packaging. Never installed: superseded
  by 0.74.4.
- The co-op game of 2026-11-07 on 0.74.1 (War hosting 14:25-16:23 ACDT, 18 players, up to 16 at once, round 25; 13
  friends' log sets lined up by the round callouts; report: Claude Docs "AC8 Survival Mode: Co-op Session Report, 7 Nov
  2026 (0.74.1)"): no crash on the host; at least nine on joiners, most within ~3 s of Survival removing or dressing
  objects there: a copy taken down (spagooterpoop ~15:02 and 16:06:52, a Shadow Typhoon), a recycled unit's actor
  destroyed 30 s on (15:30:07 the Recon Drone round's end, ~35 destroys waiting; 15:33:43 Happiness, carrier 2's parked
  units), a carrier's ZFA-44 dress (15:50:27 Aquila mid "setting SK_ZFA44", Saint Alessia and Amia the same second),
  GONE FISHIN''s weigh-in (RNAVtoASPEN 15:32), and three games that left the level (cressendo, dukka at 15:57; Talos,
  who quit from a STORE pause, 16:19) reached the main menu and never ticked Lua again, no clean exit. The path guard
  reported no faults. Every game committed 29-35 GB (PagefileUsage), +0.4-2.6 GB an hour; the crashed ones were at
  ~30 GB, so memory alone doesn't explain them (Happiness reported "out of memory crashes x3"). No dumps came: ask for
  the UECC folders. Also: Happiness's "screen flickering" and "gun tracers and afterburner VFX disappearing" likely the
  arc (the light rewritten every 2 s and undone each frame; VFX EV -2 under a day sky): 0.74.3's arc writes neither the
  light nor a night the sky doesn't show. Host migration after War left: Ozero to OdyDio (Aquila didn't answer), Stahl
  hosting alone; the test keys took THE FESTIVAL's round 19 (the Spaceport forced last), so no festival or storm ran.
- 0.74.4-coop2mp.96 (2026-11-07; not yet run in game) = 0.74.3 + three fixes from that game. Dev 401d514b...9cbb44,
  friends eb0940ce...742b50 (AC8SurvivalMode_COOP2MP_0.74.4_Online_COOP_ZFA44.zip), both registered by the packaging.
  THE ESCORT's landing (user: "The Landing for Yorke, Charlene, Rock, Ali and
  Danielle takes WAY TOO long": War's round 9 ran 25 minutes and ended on max_s) and the ZFA-44 carriers' launches (user:
  "ZFA-44's did not launch from the Cargo Ships"). Escort (sv_escort.lua, CFG.specials.escort.landing): her final at 450
  until final_slow_km (final_fast: her route given again at 450, <rec>CruiseSlow, a second after her Final; 320 for 18 km
  before); each one landed once it's taxiing (landed_at_taxi; its taxi and stop by the build's path ends; T0 unchanged);
  the escorts all onto the circuit from her rollout (release_at "roll", release_first_s 0), one every release_gap_s 15, the
  lined-up one first, else started anyway (hold_max_s 120 -> 0); an escort's 280 / 260 only once it's low on the final leg
  (escort_slow_up_m 450 / escort_short_up_m 250: YORKE fired its 260 crossing the runway 2.9 km up and flew the whole
  circuit at 260); after_her_s 210 after she's landed, any still up counted landed (switched off if flying) and the escort
  won; a landed one flying again (climb_off_m 60 / climb_off_kmh 150: she climbed to 925 m off her taxi) switched off. The
  circuit cut from ~26 to ~15 km (tools/survival_events.py ESC_CIRC_*: start 1.5 km past the origin 2 km north, downwind
  to -5 km, a 1 km base turn, a 4.6 km final; geo.circuit_start {1669669, -678540, 60000}; build_survival.py's circuit
  assert restated). Expect ~6.5-7 min from her final to the round's end (was 20); release_at "final" with
  release_first_s 60 saves about a minute more but leaves her approach unguarded. Carriers: launch() no longer skips an
  arm whose unit reads alive (every try in War's game: "every launcher arm's flight is still up", 322 times, none
  launched: a ship comes with planes of its arms' units of its own): the next arm in turn, its unit taken off the
  spawner's list first (force), then its RE_SV_CargoLaunch_<s>_<n>; the pose fallback as before. ZFA-44 dressing (the
  15:50:28 carrier that dropped players 5, 10 and 13, one mid-"setting SK_ZFA44"): a plane dressed settle_s 1.5 after
  it's seen, per_tick 1 (was 2), not while a level comes or goes; ZFA.preload (sv_zfa44.lua) loads and pins SK_ZFA44 and
  its 6 materials and textures one a tick from the carriers' unlock, every game. Log lines `escort: the escorts' landings
  begin ...`, `escort: <NAME> landed (on the ground, taxiing ...)`, `escort: <NAME> flying again after it landed ...`,
  `carrier: ... had N up that this carrier never launched ...`, `zfa44: the ZFA-44's assets loaded before any carrier
  ...`. escort_test 146 checks.
  STORE flare upgrades kept (user: "purchasing flare upgrades from the store didn't seem to work"; Talos's and
  Happiness's logs: FLARE PODS to 8 / 10, flares bought up to it, then the game's take-off reload on the runway put
  MaxFlareCount and the count back to stock (2 / 6); UP.apply raised the max again, nothing put the count back, and in
  the air ammoTick took the rest for shots: "flares 2/8", "6/10", the money gone). FLARE PODS' full load is now the
  flares' reload target A.bays[4] (sv_tactical.lua UP.apply), as WEAPON BAYS' is for kinds 1-3; sv_flights.lua
  ammoTick's reload detection and on-ground put-back cover kind 4; UP.apply flags a full load it raised back from the
  game's stock (A.reset[k], bays and flares), so a reset its own 2 s pass repaired before ammoTick saw the dip is still
  put back, never taken for shots. Log `ammo: reloaded by the game to its stock load, put back what you had (weapon bays
  / flare pods): flares 6 -> 10`. tools/checks/flares_test.sh. All 45 Lua suites, ini_check and build_all.sh pass.

## 0.74.5-coop2mp.97: the repo for contributors, and the gun pods (2026-11-07; runtime 0.32.24; not yet run in game)
- A contributor's feedback (the user, passing it on: "some file have too much line of code, almost 6k for sv_coop.lua and
  many over 2k not maintainable for humain or AI", "make a file .env so every one can contribute and set their dev
  environement easily"):
  - No source file over 2,000 lines (tools/checks/size_check.py, run by build_all.sh). The Lua parts sv_coop / sv_config /
    sv_anomalies became families (tools/lua_split_part.py: 45 suites, 4,373 checks, the loaded state the same but for
    the new globals and COOP.M); the Python generators survival_events.py / build_survival.py became modules (output
    byte-identical: 67 packages, sv_menu_stock.lua, stdout); the C runtime's survival_rt.c / coop.c / flight.c became
    #included parts of the one translation unit (main.dll identical but for its link timestamp). AGENTS.md "Runtime
    layout" has the layouts.
  - .env (from .env.example; tools/env.sh, tools/env.py --init / --check): the game's folder and AES key, LLVM, the
    release folder, VALKA's and AC7's tools; get_stock.sh, pak_read.py, ac7_sfx.py, x02s/build.sh, release_dir.sh and
    build_all.sh read it instead of this machine's E:/ D:/ paths. CONTRIBUTING.md: the whole setup, the rules, the
    layout, how to report a bug.
  - AGENTS.md slimmed from 193 KB to ~44 KB (the user: "Will this help us with tokens?" ... "Okay, please do that"):
    every build's notes moved verbatim to this file.
- Gun pods keep their stock load (a player, Stargazer: "I was given 28 machine gun pod bullets total"; the user: "the
  Special Weapon Machine Gun Pods should be an exception"): a preset's `special` is a missile count (casual 56, standard
  28, ace 14), so a gun pod got 28 rounds. sv_flights.lua applyAmmoCaps reads the plane's PlaneSpWeaponID1 / 2
  (ELiveWeaponID: WID_mgp 20, WID_pgun 35) and leaves a slot CFG.ammo.uncapped_specials names ("mgp", "pgun";
  survival.ini [ammo] uncapped_specials) without a cap (every reader already takes no cap as none). Log `ammo: preset
  ...; its stock load kept (rounds, not missiles): special 1 (weapon 20)`. flares_test covers it. Not yet known in game:
  whether UE4SS reads the enum property as its number (a name with "wid_mgp" is matched too).
- Dev eb6cd357...dd63009, friends 1f13af90...5420e65 (AC8SurvivalMode_COOP2MP_0.74.5_Online_COOP_ZFA44.zip), both
  registered by the packaging; build_all.sh's counts as 0.74.4's (1732 triggers, 3759 execs). Not installed.

## 0.74.6 (2026-11-07, runtime 0.32.25; the 7 Nov co-op game's reports and the user's requests after 0.74.5; not yet run in game)
- In co-op the game no longer pauses on a lost focus while others are linked (in 0.74.5's commit, not its zip: alt-tab
  restarted Talos's music). COOP.focusPause, sv_coop_migration.lua.
- The airfield bar on joiners (players: "the airbase was at 250 health with the health bar at halfway despite the health
  being set to 250"): a joiner divided the host's health by its own setup's AIRFIELD HEALTH (500 at 200%). The host's
  "af" carries its maximum as field 5; a joiner takes it (logged `coop: the host's airfield maximum ...`); the bar is out
  of max(AF.max, AF.hp). coop_landing_test.
- The EA-18G jammer's ECM (the user: "The Enemy EA-18G Growlers are not using ECM against the players"): JAM.tick's first
  look at a plane logPlane had just added found no position (the sweep's 1-in-8 slot fills it), `on` came out nil and
  `D.jammer = nil` dropped the jammer for the round: 11 of 17 jammer rounds in the logs of 2026-11-04 logged "is up",
  "0 enemies sharpened" and nothing more. Its position read at once; dropped only when it's down or gone; its pod fires
  without a position. heavy_test.
- Crash A of 2026-11-07 (a joiner, 13:00:07, UECC 9139164E: access violation reading 0x8 in AActor::GetWorld from
  ALiveMeteoriteImpact::Tick, THE DECOY's trap over and its Spear launchers taken off while a rod still ticked): runtime
  0.32.25's guard on the game object check 0x147d0ba00 (sigs.h kSigOwnerHostile, flight_guards.c OnOwnerHostile) answers
  "no" for a NULL or freed game object; log `guard: a game object check (a Spear rod's owner) on NULL ...`. Crash B
  (13:36:50, UECC 713C071F) was a GPU crash (no DRED data) on a 16 GB PC with ~30 GB committed: nothing ties it to
  Survival.
- THE ESCORT's people (the user: "Charlene, Yorke, Rock, Ali, Danielle all should have their own unique Subtitles";
  "Give Charlene Unique Lines for Landing, Being Attacked, Being Defended. Charlene is a Wealthy CEO who owns one of the
  worlds largest plane collections, she is from the KOKODA MERCENARY GROUP, based out of Aurelia"; the four escorts KMG
  too, "they should each have a squadron tag KMG"): Scripts/sv_escort_subs.lua (new part, after sv_escort), 124 lines in
  CFG.specials.escort.text.say; their boxes `[KMG] CHARLENE` ... (tag / tag_format); her thanks on the subtitle strip
  (no callouts), then Comona's line on the ZFA-44s; COMONA TOWER and a CREW CHIEF beside COMONA CONTROL.
  tools/re/ESCORT.md's last section.
- The Anomalies wait for CHARLENE (the user: "Anomaly Rounds shouldn't start until Charlene arrives at the airbase btw,
  That Includes, Valka, Mindripper, Abelcain" and the lightning Anomaly; "the round before an Anomaly Round appears, a
  Subtitle from Charlene ... (she will not be able to warn players about VALKA though)"): CFG.specials.anomaly_gate,
  ESC.anomalyOk in sv_spawn.lua specialReady (after_lost: they come anyway once she's shot down; no wait without THE
  ESCORT); ESUB.warnNext at each round's end draws the next round's special then and she warns of MINDRIPPER or AB.L..IN.
- SAL and Comona's staff (the user: "Give SAL and the Comona Airbase Staff some more unique lines"): ~40 more lines in
  GONE FISHIN' and THE FESTIVAL; "T|" COMONA TOWER, "G|" CREW CHIEF; exchanges with alternatives (FISH.pick / FISH.seq).
- THE FESTIVAL's town (the user: "Add some Allied Target Boxes in the town next to the airfield", "Valka" "Audrey" side by
  side, "Concert" "Market Stall" "Food Truck" and the like; "invincible dummies"): SV_Unit_FestTown, 15 objects of
  Mission 22's invisible dummy (Unit_dummyN0 on dummy_common) made allied, invincible and out of every attack, each its
  own callsign key (SV_FestBox_*; names in CFG.specials.festival.text.town), 2.2 km along the runway past its WSW end
  and 0.3 km south (the town's densest houses), VALKA and AUDREY 12 m apart; up with the festival's talk, off with its
  searchlights. The town talks (the user: "there should be some subtitles for the Festival as well"): raid_town as the
  siren starts, chatter every chatter_s during the raid, saved_town after all_down (VALKA, AUDREY, CONCERT MC, FOOD TRUCK,
  MARKET STALL; a longer speaker code, CFG.hud.subs.speakers). festival_test, the build's read-back check.
- Tests: 45 Lua suites pass (escort_test's wave check now against the wave before it, not an older one: it failed at
  random once the subtitles drew more random numbers), the C checks, the size check and the full build.
- The town's couple (the user: "Audrey is the Dominant one in the relationship with Valka"): AUDREY leads, VALKA follows
  in raid_town, chatter and saved_town.
- Crash C of 2026-11-07 (08:35:52 UTC, UECC AC971586, iiBlu's PC: RTX 4060 Laptop, NVIDIA 621.14, a driver UE's
  denylist flags; 86 s after launch, 0.74.1's main.dll): a GPU crash with a DRED page fault, the same handler path as
  crash B; nothing ties it to Survival (no game log came with it: its DRED lines would name the resource). Both dumps
  show ~30 GiB committed even at 86 s in, so that's this setup's baseline, not a leak.

## 0.74.7 (2026-11-07, runtime 0.32.25; the lore and the subtitles after 0.74.6's zip; not yet run in game)
- The town's couple (the user: "Audrey is an Ex-grey man who worked for Grunder Industries. Valka is Audreys girlfriend,
  Valka is a bit of an airhead but she's extremely powerful because she's actually an Anomaly herself, she's what they call
  a Void Watcher, she looks after all the dead who have passed on, however Valka resides on earth with Audrey, the players
  will only be able to loosely connect the dots"): hints only in chatter and saved_town (AUDREY's old maintenance logs,
  Grunder's guidance, counting exits, "the old men in grey"; VALKA looking after the bomber crews, "nobody's ever really
  gone", the crowded sky, VOID WATCHER the radar plane "cute").
- More of the couple (the user: "Valka is prone to being captured and sometimes she has outbursts where she becomes the
  full anomaly version of herself (the X-02S anomaly). Her sister is a girl named War, who they all believe is evil,
  because she actually is evil"): hints in chatter (a lab, the buzzing, "no flying off this time", her sister) and a
  saved_town exchange ("I stayed me the whole time").
- KMG (the user: "Yorke is the Team Leader of their Squadron, Rock is his 2nd in command, Ali and Danielle are dating"; "add
  other Characters like Yorke, Rock, Ali, Danielle into this as well"): THE ESCORT's check-ins and kills say so; each
  escort's loss answered by its partner or its lead (crew.<NAME>.mourn: ROCK takes the lead when YORKE's down, ALI and
  DANIELLE for each other), the loss kept in RUN.escort.down; at THE FESTIVAL, once CHARLENE has landed this run, KMG's
  kmg_talk / kmg_raid / kmg_chatter / kmg_saved, never one shot down in the escort (sv_festival.lua kmgList).
- VALKA's round talks (the user, on AUDREY breaking in: "ADD IT THIS IS GOOD STUFF OMG"): CFG.specials.valka.text.say
  (sv_anomalies_valka.lua SPC.V.subs / subsHealth): COMONA CONTROL at her reveal (CHARLENE too once she's at Comona: she
  can't see VALKA coming), AUDREY under 60% ("Valka? Valka, it's me. Come back to me.") and under 30%, AUDREY taking her
  home at her death. bosses_test (which lines when; ESUB.say stubbed), escort_test (every line's length and colour).
- Dev 8cc0e46a...b16d18c (stage_dev_0.74.7), friends 1695e3d8...4b01a7b554 (AC8SurvivalMode_COOP2MP_0.74.7_Online_COOP_ZFA44.zip),
  both registered by the packaging. 0.74.6 (dev c7f75c5f, friends afbbff90) superseded before it was installed.

## 0.74.8 (2026-11-07, runtime 0.32.25; the ZFA-44 carriers' anti-missile laser; not yet run in game)
- The ZFA-44 carriers' anti-missile laser (2026-11-07; the user's option 1; tools/re/LASER_INTERCEPTOR.md 8):
  - BP_FCS_SV_ZfaTLS: the ships' CIWS arm with AC8's BP_SwingTLS_ForMSL, a LauncherCommon at the gun socket, missiles
    only.
  - Rows: DT_SV_NpcFCS SV_FCS_ZfaTLS, and DT_SV_NpcRows SV_Zfa_AllyTLS (slot 3).
  - Lua, Scripts/sv_escort_laser.lua: ESC.setup's row choice, the `zfa laser:` fire-control line, and the kill count
    SV_ZfaTLSHits from Mission 29's WeaponIntercept trigger. Setting CFG.allies.carrier.zfa.laser (true).
  - build_all.sh passes, check_zfa_laser_build included, and every Lua suite but coop_test passes.
  - Not yet run in game; not versioned, packaged or committed.
- Dev bc2ebae7...1f934a42ff (stage_dev_0.74.8), friends c6c4ccdf...a8b01add26e8e (AC8SurvivalMode_COOP2MP_0.74.8_Online_COOP_ZFA44.zip),
  both registered by the packaging. Not installed (the user was playing 0.74.7, installed 2026-11-07 ~19:55; its backup of 0.74.1:
  build/backup/install_before_0.74.7).

## 0.74.9 (2026-11-07, runtime 0.32.25; the leaderboard address back in the runtime; not yet run in game)
- The user: "leaderboards on the new builds aren't being added for some reason, players are playing ranked but nothing is
  coming through". Every 0.74.x build (from the 0.74.0 night build on: the first built in the E:\ACE8 SM decoy worktree)
  shipped a main.dll with no leaderboard address or submit key: runtime/build.sh read ../leaderboard/submit.local, which
  only the main tree has (it's git-ignored), printed "no leaderboard/submit.local; the runtime can't submit runs" and
  built on. Checked in the DLLs: the 0.73.78 install has the Worker's address; the 0.74.0 (.91 / .92), 0.74.1 and
  0.74.7 installs and every 0.74.1-0.74.8 friends' zip don't. A ranked run on those builds went into the player's
  config/pending_runs.txt ("not sent now (this build has no leaderboard address); kept for later") and is sent at the
  next game start of a build that has it (LB.queueTick), its build hash the one it was played on (registered).
- runtime/build.sh finds the file as .env's SV_LB_LOCAL, else this checkout's, else the main tree's (`git worktree
  list`). package_release.sh online and package_dev.sh refuse a runtime without it (build/runtime/submit_cfg.h, written
  only by a build that found it, and the staged main.dll that build's; LB_OPTIONAL=1 for a dev stage without).
- Dev 5e1d897c...f4702418f (stage_dev_0.74.9), friends 036313b5...49208e575 (AC8SurvivalMode_COOP2MP_0.74.9_Online_COOP_ZFA44.zip),
  both registered by the packaging, both main.dll checked to carry the Worker's address. Everything of 0.74.8 (the
  ZFA-44's laser) in it too. 0.74.8's zips superseded (no address).

## 0.74.10 (2026-11-07, runtime 0.32.25; the carrier launch crash; not yet run in game)
- The user's test of 0.74.9 (21:14:08, Ctrl+DEL): AC8 crashed the moment ZFA-44 CARRIER 1 launched. Its first arm's
  unit (E_Unit_01_drone_5_0) had 2 planes up from the ship's spawn (Mission 17's drones wait parked under the sea until a
  container fires them; 14 "planes of no unit near a carrier ship" were dressed at 21:13:49), 0.74.4's launch took that
  unit off the spawner's list by force (SV_Recycle 1, "its destroy deferred (2 alive)") and fired the arm at once; the
  user: "i did not see any aircraft launch out from the Cargo Ship". No UECC report was written.
- launch(): an arm's unit is taken off the list only with nothing of it up; with planes up the arm is fired as it is
  (log "... has N up that this carrier never launched (the ship's own): fired as it is, never taken off with planes up"),
  its record's orders reaching those planes. The flight's watch counts only planes that weren't up before it fired
  (F.before): none new in launch_wait_s -> by pose, as before. escort_test.
- The user asked "why not just swap the drone model that launches originally with the ZFA-44 model": the next step if
  the container launch still shows nothing: Mission 17's own drone row back on the arm units (the launch exactly
  stock), dressed as the ZFA-44 (a setting, CFG.allies.carrier.zfa host su47 / drone).
- Dev / TESTER 7010ab71..., friends 5c8a94a4... (AC8SurvivalMode_COOP2MP_0.74.10_[TESTER_]Online_COOP_ZFA44.zip), all
  registered; INSTALLED (backup of 0.74.9 with the crash's logs: build/backup/install_before_0.74.10).

## 0.74.11 (2026-11-07, runtime 0.32.25; a joiner's freeze after the host's crash; not yet run in game)
- The user, with a joiner's logs (logs15.zip, 0.74.9): "menu bugged out at the airfield and would not open". That joiner
  was down at the airfield in the user's game when the host crashed (its 18:44:08 = the host's 21:14:08). The host's
  forwarded RE_SV_CargoLaunch_1_1 had made it take E_Unit_01_drone_5_0 off its list by force with 2 up as well (it
  didn't crash there); its STORE was open in co-op's no-freeze mode when the link went (18:44:19: the mode back to stock
  mid-STORE, then a stock restore of 33 AI objects never frozen, 18:44:37); host migration made it the host (18:45:05),
  which built the ZFA-44 carrier again: its cargo ship spawned with the old one's ZFA-44s still in that game, and a second
  later its game thread stopped (the last line 18:45:11; the Lua tick watchdog's "tick lost: queued again" at 18:45:22 and
  18:45:42 from UE4SS's async thread): a freeze, the airfield menu the last thing on screen.
- Never with planes up, anywhere: a joiner's ESC.beforeHostEvent leaves an arm's unit with planes up as it is (only
  nothing up: off the list first); ESC.localOff queues only arms' units with nothing up; recycleTick doesn't force a
  ZFA-44 unit with planes up off the list (looked at again 5 s on, 6 times, then left on it). Host migration doesn't build
  the ZFA-44 carrier again (log `coop: migration: ZfaCarrier NOT built again ...`). escort_test, coop_migration_test.
- The ZFA-44's box (the user's screenshot: "SU-47" over "ZFA-44": "remove that and change its aircraft name to
  ZFA-44"): the box's first line is the MODEL row's name (DT_NPC_Model GameObjectDisplayName01; the NPC table has only 02),
  so the host rows (SV_Zfa_Ally and its laser twin) are on SV_Model_Zfa, Survival's copy of the allied Su-47's model row
  named SV_Zfa44 ("ZFA-44"), which Lua adds to DT_NPC_Model at the main menu before the host row (ZLAS.zfaModel, as the
  shoal's); the rows' 02 SV_ZfaSub ("VAMPIRE", CFG.allies.carrier.zfa sub / sub_key). The build's read-back checks them.
- Enemies on a downed host (the user: "enemies are attacking my downed aircraft"; 0.74.10 log: down 21:25:34 with
  nobody else in the mission yet, the hunt's fallback COOP.huntHost put flights back on the host's plane): COOP.huntHost
  puts nothing on you while you're down, and a pass every 5 s while you're down sends the round's fighter flights after a
  living player's real plane (`coop: you're down: N flights (P planes) sent after the other players instead`); with no
  other player flying, left as they are (logged once). coop_revive_test.
- The carriers' launch, as the user saw it in 0.74.10: the container fired with arm 1's parked planes up launched nothing
  new, so 10 s on the pose fallback spawned a 4-ship 300 m off the bow, 1100 m up: no launch smoke, one flight flying
  together. Mission 17's launch = the container fire + RemoteEvent_FireWeapon_N 1 s later (each drone object's own launch
  path along a PathTube camera path, its TGT box): not in Survival's records yet; under research (the user's idea: the
  stock MARTYR drone dressed as the ZFA-44).
- Crash D (cressendo, a joiner, 0.74.10, the user's 21:28:58; UECC 9810BB5D): access violation reading 0xdb8 in
  ULiveFCSModule_ProjectileSpawnerFromWorldData's launch (vtable +0x2e0, 0x147bf1390: a NULL game object in its weak list
  of units to launch) on the host's forwarded RE_SV_CargoLaunch_1_1, right after this joiner's ESC.beforeHostEvent took
  E_Unit_01_drone_5_0 off its list by force with 2 up: the joiner path 0.74.11 removes. (A native guard on that slot,
  skipping an entry that resolves to NULL, would be the backstop if a recycle ever slips through again: not built.)
- Built 2026-11-07 (build_all exit 0, "leaderboard: runs go to ac8-survival-leaderboard...", every read-back "all there";
  45 suites passed before it). Registered: dev stage_dev_0.74.11 and the TESTER zip d7fb39a4b4f8..., the friends' zip
  AC8SurvivalMode_COOP2MP_0.74.11_Online_COOP_ZFA44.zip b689fab62ec3... (0.74.11-coop2mp.103, runtime 0.32.25). Not
  installed yet (AC8 was running when the build finished).

## 0.74.12 (2026-11-07, runtime 0.32.25; the user's 0.74.10 game of 21:21-22:05; not yet run in game)
- The ZFA-44s' laser (the user: "Make sure that you swap the guns out for the Laser Interceptor. The Laser Interceptor HAS
  to work, no exceptions"; 0.74.10: the arm on every ZFA-44 in slot 3, nothing ever shot down):
  - the arm in the gun's slot (survival_events_escort.py ZFA_TLS_SLOT 1, ZFA_TLS_GUN: SV_Zfa_AllyTLS has no gun; the
    build checks the twin replaced NPC_FCS_PlaneGun000); CFG...zfa.laser_slot for Lua's row check.
  - Survival fires it too (sv_escort_laser.lua ZLAS.drive, every game): each ZFA-44 alive (ESC.planes, kind zfa) at the
    nearest enemy missile (HIT.msl; enemy: its shooter's faction isn't Alpha, else it homes on one of ours) within
    laser_range_m 3000, one every laser_shot_s 1: the TLS's own beam NS_NPC_TLS_Muzleflash01 (User.BeamLength) from the
    plane at the missile; laser_swing_s 0.35 on the missile is shot down: no lock, no damage (the STORE ECM's way, never
    destroyed from Lua), its LifeTime cut to 0.05 (logged whether that ends it), the TLS's air burst NS_airExplosionA_S
    and hit sound SPWP_OTH_TLS_HIT there (Wwise PostEventAtLocation, two signatures tried, logged once if neither works).
    Logs `zfa laser: <plane> (<unit>) fires at <missile> d m off (from <shooter>, at <target>)`, `zfa laser: <missile>
    shot down (by <plane>; N so far)`, and the round's total `carrier: round N: the ZFA-44s' lasers: ...`.
  - The game's own shots (every LiveTLSSwingforMissile of an ally's, NotifyOnNewObject): InterceptPercentage 0.3 ->
    laser_chance 1, InterceptAngle laser_angle 180, its reach 3 km, on the instance only; the missile it's on claimed and
    made harmless at its swing's end. `zfa laser: <plane>'s own fire control fired its laser ...`.
  - laser_drive = false: the game's own only. escort_test (9 new checks: beam, kill, the burst, never an ally's or one out
    of reach, one shot a second, the game's own made sure, drive off).
- The sunset (the user: "the sun does not seem to be setting, it seems to be just moving to the right constantly instead
  of going down"; 0.74.10's log: 15 -> 8.8 deg in 3 rounds while its bearing swung 142 -> -152): it sinks where it is,
  sink_el 12.5 .. 3, sink_az 145 .. 157, the sunset at 1 -> -3 deg, bearing 160 (a real sunset's slant).
- The night (the user's screenshots of round F+7: ground and planes white and noisy under a black sky, "everything was
  working perfectly though until the sun disappeared"): Mission 9's night exposure (min 0.5) let the camera brighten the
  scene ~5,000x, lit by the day's sky light x0.1, and the city glow x10,000 blew out anything with glow. Night and dawn
  take the sunset's way: night exposure 10.5 / 14 / -1.5, glow 100, effects' EV 7; dawn 10 / 14 / -1, glow 100, EV 8.
- The night lasts 3 rounds (the user: "have the night time last for 3 rounds before the sun rises again"):
  CFG.sky.arc.night_rounds 3 (F+7 .. F+9), dawn at F+10, midday from F+14; VALKA's gate to F+13.
- The sunrise's light (the user at F+9: "sun is currently up in the sky but it's not back to normal brightness yet"):
  exposure, sky light, glow and EV back to the day's sunrise_light_x 2 times as fast as the sun climbs (by the sunrise's
  middle). sky_test, arc_rounds_test.
- THE FESTIVAL (the user: "Include more Enemy Aircraft in the Festival Mission and have the ending timer for the next
  round last 60 seconds"): fighters with the raid (SPC.kinds.festival alone false, budget FEST.fighters: fighters_share
  0.7 of the round's aircraft in whole 2-ships, 6 .. 16; round 8's 18 -> 12); the break after its round at least
  break_after_s 60 (sv_rounds.lua). festival_test, arc_rounds_test.
- The EA-18G jammer's ECM (the user: "enemy EA-18G that spawned in just then still doesn't use ECM"; the log had
  RE_SV_JamEcm_20 fired at 22:04:15 and nothing more; that jammer was shot down 31 s on, 14 km from the user):
  ecm_check_s 1.5 after each firing its own ECM pod (LiveElectronicSupportMeasures, kept from NotifyOnNewObject, its owner
  or instigator the jammer) is made to jam: bJammingEnable on, JammingTimeCampaign at least ecm_every_s + 2, its reach x
  ecm_range_x 1.5 (once). Logs `jammer: its ECM pod made to jam: <pod>: jamming false, 2000 m, 5 s -> ...` or `jammer: no
  ECM pod of its own up ...`. heavy_test.
- Built 2026-11-07 (build_all exit 0, "leaderboard: runs go to ac8-survival-leaderboard...", every read-back "all
  there"; 52 suites pass, coop_test not run while the user played). Registered: dev stage_dev_0.74.12 and the TESTER zip
  b30a111878f2..., the friends' zip AC8SurvivalMode_COOP2MP_0.74.12_Online_COOP_ZFA44.zip 8aebfa37b5b5...
  (0.74.12-coop2mp.104). Not installed yet (AC8 running). The carriers' real container launch (Mission 17's allied drone
  dressed as the ZFA-44, its own launch smoke and sound; the research of 2026-11-07 in tools/re/ESCORT.md) is the next build.

## 0.74.13 (2026-11-07, runtime 0.32.25; the carriers' real container launch; not yet run in game)
- The ZFA-44 carriers launch from their containers, Mission 17's way (the user: "i did not see any aircraft launch out
  from the Cargo Ship", "why not just swap the drone model that launches originally with the ZFA-44 model", "i know for a
  fact that there was some launch smoke and VFX, possibly event sound effects", "the drones seem to just fly the same path
  together"). The research (2026-11-07, scratchpad dumps): Mission 17's drones (OP0019_uavcs_01) sit parked under the sea
  until their arm fires; the container's RemoteEvent_SpinUpWeapan sends ToOpen, FireOneShot fires WN_WEAPON_n, each drone
  object gets its own path at 1200 km/h NotSnap on the container's fire trigger, ToClose 2 s on. The smoke, the wing
  opening and the take-off come from the drone's blueprint (ILiveFCSMountedActorInterface NotifyTakeOff,
  NS_UAVLaunch001, A_OP0018_uavc_Open), which a Su-47 hasn't; the hatch and launch sounds from the container. Survival
  gave the arms' planes orders at their appearance (SV_ZfaUp<s><n>), so they took off from their parking as one flight
  and the container had nothing left to launch.
  - The arms' planes fly Mission 16's allied container drone (survival_events_escort.py ZFA_DRONE_*): DT_NPC SV_Zfa_Drone
    (OP0018_uavc_Ally_01, MOONCHILD's set NLID_0003_CP, its gun's slot the laser in its twin SV_Zfa_DroneTLS) on model
    SV_Model_ZfaDrone (OP0018_uavc_Ally named SV_Zfa44, 60 HP: the Su-47's, not the drone's 6), mission row sv_zfa_drone.
    The drone is faster (3000 max) and nimbler than the Su-47. The pose fallback keeps the Su-47 (sv_zfa_ally).
  - RE_SV_CargoLaunch_<s>_<n>: ToOpen on the ship's container (Mission 17's LiveUniqueStateMachineTransitionEvent), the
    arm fired ZFA_OPEN_S 2 s on, ToClose 3 s after; no orders at the planes' appearance (SV_ZfaUp<s><n> gone).
  - RE_SV_ZfaClimb_<s>_<n> (new, one an arm): each object its own climb-out path SV_Path_ZfaClimb_<s>_<k> (k 0-1: off the
    ship's bow 30 deg apart, 150 m -> 3 km out, 60 -> 800 m up; smooth, Mission 16's Ladon path's shape) at Mission 17's
    1200 km/h, their orders 8 / 12 s on.
  - Lua (sv_escort_laser.lua ZLAUNCH, hooked into sv_escort.lua's flight watch; CFG.allies.carrier rise_m -50,
    parked_m -100, launch_wait_s 15, each launcher's `climb`): a ZFA-44 plane within capture_km of the ship that was
    parked (below parked_m) or is new since the record, seen above rise_m: out of the container, the arm's climb record
    fired once (`carrier: <ship>: N ZFA-44s out of its container (<unit>, s after its launch record): RE_SV_ZfaClimb_..
    fired`); none out in launch_wait_s with the arm's planes alive: the climb-out anyway, from where they are (`none of
    <unit> seen out of its container ...`); none alive: by pose as before.
  - Both hosts' rows and models in at the main menu (ZLAS.zfaRow / zfaModel; the row line names SV_Zfa_Drone); the
    lasers skip a parked plane. The build checks the rows, models, twins, paths and the open / close records.
  - [T] The ZFA-44 dressed on the drone (its body a skeletal mesh: placed as on VALKA's x40a); the drone's flight with
    MOONCHILD's set; the container launching it with its smoke; co-op joiners' copies (both records are forwarded).
- 52 suites pass (coop_test not run). Built and packaged: dev / TESTER 93bea0e256d1..., friends'
  AC8SurvivalMode_COOP2MP_0.74.13_Online_COOP_ZFA44.zip b814c569a10a... (0.74.13-coop2mp.105), all registered.
  INSTALLED 2026-11-07 (backup of 0.74.10 with its logs: build/backup/install_before_0.74.13; 79 files compared equal).

## 0.74.14 (2026-11-07, runtime 0.32.25; after the first container launch; not yet run in game)
- The first container launch (0.74.13, the user's run of 22:25-22:29, Ctrl+DEL): the container opened, fired and the
  drones came out (`carrier: ZFA-44 CARRIER 1: 2 ZFA-44s out of its container (E_Unit_01_drone_5_0, 2 s after its launch
  record): RE_SV_ZfaClimb_1_1 fired`); all 12 parked drones dressed on PlaneBodySkelMeshComponent (the dress log names the
  first 4 and every 20th), each with the laser in slot 1 (`0 -; 1 BP_FCS_CIWS BP_SwingTLS_ForMSL (Survival's arm); 2
  BP_FCS_MSL`); their boxes ZFA-44. The user: "there was no launch smoke and the ZFA-44's stuck together".
- The launch smoke: each ZFA-44 seen out of its container gets the drone's own NS_UAVLaunch001 (CFG.allies.carrier
  launch_fx), attached to it for launch_fx_s 4 (ZLAUNCH smoke; the line says `launch smoke on N`).
- Apart: the climb-outs 90 deg apart (ZFA_CLIMB_FAN_DEG; each 45 deg off the bow, the first point 400 m out: 565 m
  apart), each drone its own Normal (t_eng_air by object, ZFA_CLIMB_STAGGER_S 4 s apart, at 8 and 14 s) instead of the
  unit's orders at one moment; the unit's air search at 8 s.
- Followed: the launched ones' place, speed, heading and how far apart at +1, 3, 6, 10, 15 s (`carrier: launched ZFA-44s
  +N s: ...; apart d m`; watch_at). escort_test.
- 52 suites pass (coop_test not run). Built and packaged: dev / TESTER 236939561d23..., friends' b7a282e58da2...
  (0.74.14-coop2mp.106), all registered. INSTALLED 2026-11-07 (backup of 0.74.13: build/backup/install_before_0.74.14).

## 0.74.15 (2026-11-07, runtime 0.32.25; the user's 0.74.14 run of 22:35-22:39; not yet run in game)
- 0.74.14's log: the launch smoke went on both drones (`launch smoke on 2`), but the launched pair flew 3 m apart for all 15
  s, the same heading and speed, 15-29 m over the sea, neither on its climb-out path. The paths were never found: the
  climb records name `SV_Path_ZfaClimb_1_0` by string, which the engine splits at its number tail (hard rule 17), and
  make_path stored the desc's name whole. Now SV_Path_ZfaClimb<s><A|B> (letters); make_path refuses a name with a number tail.
- The box (the user: "the drones say ZFA-44 Twice, where is VAMPIRE?"): line 2 is the object's callsign, which was
  SV_Zfa44 too; the arm units' and the pose flights' callsign is SV_ZfaSub ("VAMPIRE") now.
- The laser (the user: "the Laser Interceptor doesn't swing or go after the missiles, it also isn't attached to the
  aircraft it spawns in mid air"; the log: the ZFA-44's own fire control fired AC8's laser twice, `on BP_wp_msl_r0`, and
  that missile was gone; the 6 others were Survival's stand-in beam, spawned where the plane was, pointed where the
  missile was, left in the air 0.6 s):
  - The ZFA-44's own laser fired on command: RE_SV_ZfaTLS_<s>_<n> (each arm unit's objects) and RE_SV_ZfaTLS<A|B> (the
    pose flights') fire the laser's slot (WN_WEAPON_2, no target: Mission 17's container fire template); ZLAS.drive fires
    the plane's flight's record (a launched plane's arm is recorded as it comes out: ZLAUNCH e.armUnit; a pose plane's by
    its unit) and the laser that comes (NotifyOnNewObject, its owner the plane) is handed the missile (MissileToIntercept)
    and made to hit (chance 1, cone 180, 3 km); the missile made sure laser_stock_swing_s 2.5 on.
  - Survival's beam only when its own laser hasn't come laser_stock_wait_s 0.75 after the record (logged once), or for a
    plane of no known flight: now attached to the plane (spawned KeepWorldPosition at it, turned at the missile) and
    aimed at the missile again every tick for laser_beam_s.
  - Logs: `zfa laser: <plane> (<unit>) fires at <missile> d m off (...): RE_SV_ZfaTLS_1_1 (its own laser)`, `zfa laser:
    <plane>'s own laser fired (..., Survival's record): ... on <missile> (handed to it)`. escort_test.
- 52 suites pass (coop_test not run). Built and packaged: dev / TESTER cb03676665f5..., friends' 2c0062958dc2...
  (0.74.15-coop2mp.107), all registered. INSTALLED 2026-11-07 (backup of 0.74.14: build/backup/install_before_0.74.15).

## 0.74.16 (2026-11-07, runtime 0.32.25; the user's 0.74.15 run of 22:50-22:56; not yet run in game)
- 0.74.15 worked: the launched pair split on their climb-outs (97 m apart at +1 s, 1 km at +3, 5 km at +15), the ZFA-44s'
  own laser fired on command and was handed its missile, and those missiles were gone (real intercepts).
- Escort (the user: "need to make the Vampires Escort the Nearest Player too them"): RE_SV_ZfaCover_<s>_<n> /
  RE_SV_ZfaCover<A|B> (Mission 6's NearPlayer unit move + a 3 km radius, the STORE allies' Cover); ZLAUNCH.coverTick
  every escort_s 6 (the host's or solo): each flight up covers the player nearest it, this game's own by its cover
  record, another's by COOP.coverFor (its planes onto the enemies nearest them). `carrier: VAMPIRES <unit> escort ...`.
- One beam a missile (the user: "they're firing Multiple Beams at once": a flight's record fires every plane's laser, and
  the one that wasn't handed a missile swung at nothing): a laser that comes with nothing handed to it is handed the
  nearest enemy missile within reach that no other laser is on, else hidden (SetActorHiddenInGame, shown again
  laser_hide_s 9 on); one on a missile another laser's on is hidden; its plane's next shot within the second hands that
  idle laser the missile instead of firing again; a wanted missile goes stale once the backstop beam takes over.
  `zfa laser: <plane>'s laser with nothing handed to it: handed / hidden ...`. escort_test.
- 52 suites pass (coop_test not run). Built and packaged: dev / TESTER 255a3bbae140..., friends' bca30ee3a009...
  (0.74.16-coop2mp.108), all registered. INSTALLED 2026-11-07 (backup of 0.74.15: build/backup/install_before_0.74.16).

## 0.74.17 (2026-11-08, runtime 0.32.26; not yet run in game)
- AC7's LaserInterceptor on the ZFA-44s (the user: "I want the entire weapon from ACE7 to be ported over"; AGENTS.md's
  second AC7 exception): tools/laser7 rebuilds AC7's wp_LaserInterceptor in UE 5.4 on AC8's own ALiveLaserInterceptor
  (its swing curve, its two Cascade effects, the beam's meshes, 4 materials, texture; container SurvivalMode_Laser7_P,
  staged with ZFA=1). The materials' SM6 shaders cooked INTO their packages (bShareMaterialShaderCode off for that cook:
  the template project's shared archive never ships). tools/re/LASER_INTERCEPTOR.md 9 (AC8's native class, RE) and 10.
  - Runtime 0.32.26 (runtime/laser.c): the class's tick hooked inline (an ownerless laser not ticked; a swing whose
    missile is gone, pooled or fired again by another shooter given up), SV_LaserBegin / SV_LaserState /
    SV_LaserKills / SV_Intercept (the game's own interceptor kill).
  - The hosts fly gun-less twins (SV_Zfa_AllyLI, SV_Zfa_DroneLI: no gun, no AC8 laser arm). Scripts/sv_escort_li.lua:
    one laser a ZFA-44 at its gun, AC7's fire control (6 s volley when an enemy missile is within 1.2 km, 8 s rest),
    one beam a missile, the class's own swing and kill, SV_Intercept as the backstop, AC7's end flash. Ctrl+[ (test):
    a volley now. `zfa li: ...`. escort_test.
- Mission 9's night (the user at F+9: "waaay to dark", the sea glowing, no stars; research: tools/re/NIGHT_SKY.md and
  NIGHT_SEA_LIGHTS.md): the sea mirrored Mission 4's DAY sky-light cubemaps (x0.1: 20,000-45,000x a stock night) and the
  exposure was held at EV 10.5+ to hide it. Now Mission 9's whole night: exposure 0.5 / 9 / +1 with the sky light x4e-6
  (log-blended with the exposure), the moonlight's specular 0.01 (no glint), its stars (the star catalog and moon texture
  put on the sky actor: Mission 4's had neither, so nothing was ever drawn) and moon (phase 0.143, brightness 1e-5), its
  night sky's multiple scattering 3, the glow 10000 and the effects' EV -2 (the airfield's ~2,000 runway / approach / apron
  lights and the town show), r.MinScreenRadiusForLights 0.008 (far small lights), the cockpit's MFD / gauges dimmed
  (MPC_MEC_EmissiveControl), the planes' navigation / anti-collision / formation lights on, the cockpit view's own exposure
  (BP_PostProcessMisssionBase's CockpitViewPostProcess, min 11) down with the rest. All put back at the arc's end. A sky
  param that can't be read isn't written. sky_test, arc_rounds_test.
- Built and packaged: friends' 70e3ea05bf73..., TESTER 1659204e2d12... (0.74.17-coop2mp.109), both registered. INSTALLED
  2026-11-08 from the TESTER zip (backup of 0.74.16: build/backup/install_before_0.74.17).

## 0.74.18 (2026-11-08, runtime 0.32.26; built and packaged, not installed: 0.74.19 follows)
- Subtitles (the user: "all of the Audrey and Valka subtitles must play One After Other, and they can't be reused, and
  they take priority over everyone elses subtitles"; then "do this for all characters actually have it so none of the
  characters repeat lines"): sv_subs.lua. AUDREY's and VALKA's lines (CFG.hud.subs.priority) go before every other
  speaker's waiting line, after theirs already waiting; lines said in one tick (an exchange) stay together in their order,
  so an exchange with one of theirs goes ahead whole; another's line on the strip gives way after prio_min_s 1; a full
  queue drops another's last line for theirs, never theirs. Every speaker's line once a run (once_a_run; repeat_ok none;
  RUN.subsUsed): one said already is refused, the pickers (FISH.pick, sv_escort_subs.lua's) choose only exchanges with
  none of their lines said (SUB.fresh) and say nothing once all are; a line with values in it repeats only word for word.
  fishing_test.
- The default ini documents 0.74.17's night, stars and AC7 laser settings.
- Packaged: friends' 8eb7ded6dc27..., TESTER ca64c2555843... (0.74.18-coop2mp.110), both registered.

## 0.74.19 (2026-11-08, runtime 0.32.26; not yet run in game)
- THE FESTIVAL (the user: "the Enemy Aircraft that spawn in during the Festival Special Round, they need to spawn WITH the
  TU-160's not beforehand, and the Festival isn't saved until all Enemy Aircraft are dealt with. Dialogue from Fesitival
  Round can run till the end of the 60 second timer"):
  - A special kind's `hold` (sv_rounds.lua's spawn loop): the round's fighter flights wait while it holds (`round N: its
    fighters held until the festival is under way` / `... its fighters come now`). FEST.hold: through the festival's talk
    (at most hold_max_s 180), so they come with the Tu-160s.
  - Saved only once its bombers, their missiles and every enemy aircraft of the round are down (FEST.fightersLeft: the
    round's flights up, ALIVE.ask, and every flight still waiting in its waves; saved_needs_fighters). The bombers down
    with fighters left: `THE BOMBERS ARE DOWN / SHOOT DOWN THE LAST N FIGHTERS` once; the row (and a joiner's, "fsx" c)
    `THE FESTIVAL  BOMBERS: n  FIGHTERS: n  MISSILES IN THE AIR: n`.
  - The break after it: the town talks on (text.after_chatter, KMG's kmg_after once CHARLENE's landed, never one shot
    down), a line every break_chatter_s 10 once the strip is clear, none starting too late to end before the next round.
  festival_test.
- Packaged: friends' 2e14d0713e6a..., TESTER 64a4e4ee225c... (0.74.19-coop2mp.111), both registered. INSTALLED 2026-11-08
  from the TESTER zip (backup of 0.74.17: build/backup/install_before_0.74.19; 0.74.18 was never installed).

## 0.74.20 (2026-11-08, runtime 0.32.26; not yet run in game)
- The Shuttle Launch round's subtitles (the user: "Add enemy character subtitles in the Shuttle Launch Special Round";
  "Kaska is not allowed to talk to the players, make it seem that Kaska doesn't know that the players can see his
  conversations"; the script the user's own, reviewed line by line, CFG.specials.shuttle.subs). KASKA (Emblem Direct,
  launching the CORRIS shuttle the players defend; War's sponsored strike flights trying to stop it) talks with his launch
  controller on an intercepted channel: INTERCEPT: KASKA / INTERCEPT: EMBDIR LAUNCH on the strip (CFG.hud.subs.speakers,
  steel-grey colours). Scripts/sv_kaska.lua (KASKA.tick from sv_rounds.lua specialTick, the host's or solo): the
  countdown's start, War's strike flights up (strike_s at most), the 120 / 90 / 60 / 30 / 10 s marks (one passed while
  away not said late), the shuttle under 75 / 50 / 25 % health, launched or lost, and one line in the break; each moment
  one exchange said whole, none twice in a run, left out while the strip is backed up. `kaska: <moment> (<why>)`.
  fishing_test. Not a priority speaker; War stays offstage.
- Packaged: friends' 58ddf990b3f4..., TESTER 06ea8ec0bd40... (0.74.20-coop2mp.112), both registered. INSTALLED
  2026-11-08 from the TESTER zip (backup of 0.74.19: build/backup/install_before_0.74.20).

## 0.74.21 (2026-11-08, runtime 0.32.26; not yet run in game)
- The special rounds' schedule (the user: "Round 2 always Shuttle Launch. Round 6 always Charlene's Escort Mission. Round 9
  Always Gone Fishin. Then the festival at its usual round ... everything else is free game for the special rounds after
  the festival they can come in any order and in any way"): CFG.specials.schedule ([specials.schedule] in the ini),
  sv_spawn.lua specialFor. Its rounds' kinds for sure (one switched off or not in the build: a normal round, logged), no
  other special before THE FESTIVAL's round (GONE FISHIN''s round + round_after: 15), the dice after it, the scheduled
  kinds never drawn again (fixed_again false). `specials: round N is the schedule's <kind>`, `specials: round N: no special
  (the schedule's part of the run, to round 15)`. rounds_test (its dice tests with the schedule off), coop_rejoin_test.
- The repo cleanup (the user: "clean up the github and delete things we aren't using anymore and organise shit a bit
  better"): main is the working branch (COOP2MP's line fast-forwarded into it); testing/logs (players' Steam IDs) and
  testing/builds (old zips, TESTER ones with the test keys) out of git and ignored, kept on disk; BUILD_PLAN.md and
  TEST_RESULT_2026-10-20.md deleted (finished); archive/* tags for the unmerged branches; the duplicate `github` remote
  gone; a bundle of every ref first (build/backup/repo_before_cleanup_2026-11-08.bundle). The worktrees' build folders
  kept in build/old_worktrees. README's features and the player guide's special rounds brought up to date.
- Packaged: friends' 2dac1757088b..., TESTER 01db8800f1da... (0.74.21-coop2mp.113), both registered. INSTALLED
  2026-11-08 from the TESTER zip (backup of 0.74.20: build/backup/install_before_0.74.21). Built in the main tree.
- The repo cleanup finished (the user: "github has my go as long as nothing that we are currently using in 0.74.21 is
  affected"): testing/logs and testing/builds purged from every commit (git filter-repo, run from a scratch install;
  557 -> 547 commits, 10 that only held logs dropped; main's tree identical before and after, 6fe8b658), main force-pushed,
  the archive/* tags pushed, the rewritten tags force-pushed, 18 old branches deleted on GitHub; the old worktrees removed
  (their build folders kept in build/old_worktrees). GitHub's pull request #1 (refs/pull/1/head, read-only) still pins the
  old commits: a GitHub Support request ("remove sensitive data": the PR's refs and cached views) finishes the purge.

## 0.74.22 (2026-11-08, runtime 0.32.26; not yet run in game)
- The shuttle's pad left up on a joiner's game (the user, a joiner in a host's run on 0.74.21: "check my logs, this space
  centre hasn't despawned"; she came in at round 4, and at 08:55:53 her log bound the host's SV_Unit_PadDummies (9 of 9)
  and AA_Unit_01_Ground0 (11 of 11)). After a shuttle round the host only hides its pad (SPC.shuttleTakeOff; its units
  kept up for the next shuttle round, spawnShuttle -> shuttlePadBack), so the host's picture (M.units) still held them:
  the picture sent to a joiner who came in later spawned the whole pad there, shown, and nothing on a joiner's game ever
  hid its copies (RE_SV_ShuttleRemove switches nothing off; SPC.clientClean takes off the shuttle only). Now the host,
  at each take-off (the pad-only one too), takes the pad's copies off every game (COOP.removeNow on the dummies and the
  pad: an ally's copy is switched off there, not finished off, its unit off that game's spawner list 2 s on) and out of
  its picture (the prune); when the next shuttle round brings the pad back, COOP.hostBack (new, sv_coop.lua) announces
  it again as a spawn would ("sp" with a new generation, a "gd" for each live object in spawn order: keys as a spawn's).
  `coop: <unit> brought back here: announced to the joiners again (gen N), n of its m objects given ids`. pad_test,
  coop_ground_test. A host on an older build still sends the pad to a joiner on this one: the host needs 0.74.22.
- Packaged: friends' 943dca894d83..., TESTER 3294d5d380da... (0.74.22-coop2mp.114), both registered. Built in the
  main tree. Never installed or handed out: 0.74.23 has it too.

## 0.74.23 (2026-11-08, runtime 0.32.27; not yet run in game)
- The crash at a ZFA-44 carrier's launch (Saint Alessia's co-op host log, 0.74.21, 2026-11-07 14:45:02, round 7, 4
  players: ZFA-44 CARRIER 1's container fired and the game stopped; UECC EXCEPTION_ACCESS_VIOLATION reading 0x4). The
  stack, from the minidump and the exe: ULiveUnitLifeItem::NativeTick (0x147291680: a unit's bar in the HUD's unit life
  list) -> ILiveHasHealthInterface Execute_GetDisplayFaction -> ALiveUnit's GetDisplayFaction_Implementation (0x147dbe580),
  which reads the first entry of the unit's objects (TArray<TWeakObjectPtr> at its interface + 0x28, the unit + 0x2c0)
  without checking it has one -> FWeakObjectPtr::Get on a null entry. rax held the interface vtable 0x14cb0ff60:
  ALiveWingmanUnit's (vtable 0x14cb0f670; ALiveUnit and ALiveAIBotUnit share the function). A unit begins with its bar
  when its draw-health flag is set (+0x3dc, 0x147db9610 -> ALiveHUD 0x147236e00 -> ULiveUnitLifeList 0x1472919f0). Which
  wingman unit emptied at the launch isn't known (Survival gives no hangar wingmen; the launched drones are "planes of no
  unit" to Survival's lookup); 0.74.9's crash at a carrier launch (no UECC report) may have been the same.
  - Runtime 0.32.27 (flight_guards.c UfInstall, sigs.h kSigUnitFaction, unique in the exe): every vtable slot holding the
    function (3) points at a guard that answers ELiveFaction None for a unit with no objects or a first one gone, the
    game's own read otherwise (its offsets and Get read from the function). `guard: a unit's side for its health bar
    (...): 3 of 3 vtable slots guarded`; when it steps in: `guard: a unit's health bar asked the side of a unit with no
    objects ...` (the first 4, then every 4096th).
  - Not fixed, seen in the same log: AC7's laser on the launched ZFA-44s read back wrong from Lua (`owner NOT its plane
    (-4097), search every TrivialObject: ... s`): its property reads on the spawned actor didn't resolve as numbers /
    the plane. Its first in-game run; nothing of it is known to work yet (no volley logged before the crash).
- 0.74.22's pad fix is in it (Saint Alessia was that run's host: her pad was hidden at 14:24:35; the user joined at round 4
  and got it shown).
- Packaged: friends' c02e5581a88c..., TESTER 042476c26b46... (0.74.23-coop2mp.115), both registered. Built in the main
  tree.
