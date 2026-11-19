# Co-op

Survival COOP: transport, joiners, remote player planes.

Moved verbatim from AGENTS.md (2026-11-14). Rule numbers are unchanged: other notes cite them as "hard rule N".

48. Survival COOP works over Steam P2P with up to 4 players (test of 2026-10-25, coop.4: host + 3 joiners to round 5):
    joiners' copies of the host's enemies, moved every frame through the AI plane's vtable slot 315 (TeleportTo +
    OnReposition), flew with 0 failed moves and attacked the joiners (user: "Enemies attacked them yes"); joiners' hits
    reached the host (16 of its 28 kills "by wingmate"); rounds, callouts, the airfield and the shop ran on every game.

49. A joiner must not spawn while its Survival level is still loading: the level's LiveUnitSpawner has no world yet and
    the game's spawn ends in UWorld::SpawnActor(NULL) (access violation reading +0x30): two joiners crashed the moment
    the host's first flights arrived (coop.3). SpawnerReady answers SV_ERR_LOADING (-6) while GetWorld is null, and a
    joiner holds the host's spawns until its own plane is in the level + 3 s (coop.4, confirmed the same night).

50. A setting players must write into survival.ini can fail silently (a hand-made file, the default ini edited, a
    restart forgotten): three friends set role = join and still hosted (coop.2). Make co-op need no setting: role auto
    (look for a host, host after 20-40 s, step back on meeting one) linked all three at once (coop.3 and coop.4).

51. A second ALivePlayerPlane (Online Mode's remote-player spawn, docs/re/COOP.md 6) is spawned DEFERRED: give it a
    loadout and call AActor::FinishSpawning, or its weapons have no owner and the first teleport crashes. With role 2
    (another player's) and no network data its own tick holds it at the map's centre; with its actor tick off and moved
    on EVERY input-build call (2-3 a frame, not the first only) it flies solid and smooth beside you, ALLY-tagged.
    Its slot 315 fires OnReposition, which resets a player plane's look: move it with AActor::TeleportTo + the flight
    reset only. Confirmed solo 2026-10-25 (runtimes 0.22.2-0.22.7); not yet the co-op stand-in.

53. A remote player plane (role 2) flies itself when its network object's messages are fed each frame before its
    RemoteUpdate (0x147d6f0c0): the physics message *(N+0x98) and the input message *(N+0x170), both pointers (N+0x170
    is a TSharedPtr: writing at N+0x178 hit its reference controller and Quit Mission crashed, test of 2026-10-30). Its
    afterburner glow is plane+0x39d0, reset every frame on a remote plane, so it's written just before the surface
    update (0x147d32b00) reads it. Enemies attack one only when an order names it (Survival's name "Player": your plane),
    and hits on it reach the player plane's damage (0x147d5a430) but are never applied. Confirmed by T1c-T1e
    (docs/re/COOP2MP.md, 2026-10-30).

## Survival COOP (Lua 0.70.6-coop.11, runtime 0.26.0, 2026-10-26; played up to coop.4: hard rules 48-51)
Up to 24 players (protocol 3), host-authoritative (after Double Trigger, the AC7 co-op mod), first built on branch
`feature/survival-coop` (merged; the branch deleted in the cleanup of 2026-11-08). docs/re/COOP.md has the RE (AC8's AI plane teleport: vtable slot 315, called every frame on a
puppet; Steam P2P without callbacks; a real second player plane, section 6), the protocol and the test checklist.
Native half runtime/coop.c (SV_Coop*), Lua half Scripts/sv_coop.lua, world-data units SV_Unit_CoopPeerA-X (each other
player's stand-in, an allied AI plane of their airframe: CFG.coop.airframes), name keys SV_CoopName_A-X.
Untested in game since coop.4 (coop.5-coop.11): every RE_SV_* event forwarded to the joiners but each player's own;
SURVIVAL CO-OP: HOST / JOIN on the main menu (OnMainDecide, SV_MenuChoice); names on the stand-ins' target boxes; an
online-style pause; the host's Q batches for up to 24 players; more enemies per player (COOP.more); the host's settings
for everyone (M.sendSettings: CFG's differences from CFG_DEFAULTS, data only); the main menu's settings rows (SV_Set_*,
SV_MenuSetting, iniSet). Build: `COOP=1 NOVALKA=1 sh tools/package_release.sh online <version>` (bump
tools/coop_edition.py COOP_TAG for every build friends get: from runtime 0.32.6 games with different builds refuse to link (coop.c CoSameVer, both ways); before it they linked with a CO-OP VERSION MISMATCH callout, only a different CO_PROTO refusing: two players on 0.73.26 joined a 0.73.27 host, 2026-10-31).
Guards on what other games send (security review of 2026-10-26; keep them when adding messages): coop.c drops any
state with a non-finite or far-off position or a non-unit rotation before it can reach a teleport (CoSaneState), and
refuses another game's message shaped like its own notices to Lua, "sys" / "sys|..." (CoNetPush, runtime 0.32.34);
sv_coop.lua cuts texts, checks slots, zollars, damage and poses, sets only NPC rows this game's DT_SV_NpcMission has
(knownRow) and stand-in rows of CFG.coop.airframes, and takes a host's settings only where the shipped CFG has that
setting with a value of the same type and size (fits; build data and each player's own sections never); a host's
round state ("rnd") only with whole numbers in range (RND_MAX; a huge wave count froze joiners). New messages: give them a
row in tools/checks/coop_guard_test.lua (hostile values in every field, on a host and a joiner). The main menu:
any entry but HOST / JOIN closes co-op; picking one again retries a failed open (SV_MenuChoice counts the picks).
Checks without the game: `sh tools/checks/coop_test.sh` (the transport, 4 and 12 players over lossy UDP; Linux too),
`sh tools/checks/coop_settings_test.sh` (the settings sync, rows and scaling on the real parts) and
`sh tools/checks/lua_load_test.sh [mod folder]` (every part of main.lua loads). The last two run on a real Lua 5.4.6
that tools/checks/lua_build.sh builds into build/checks (there's no Lua on the build machine otherwise).
Player guide: Claude Docs "Survival COOP: Player Guide".
Since the behaviour branch's code review (2026-10-29, TestBranch_Behavioural; untested in game, not a hard rule): the
host down at the airfield no longer holds the room while another player flies (sv_rounds.lua othersFlying: alive,
fresh, not on the airfield). The spawns go on, a flight's orders fire (RE_SV_FlightOrders_NN every 5 s while the host
is down, not counted as tries), the wave clock runs, the ALICORN's deck launches, a Wolf trap is held after its orders
and the shuttle's countdown runs, the shuttle not invulnerable then (user, 2026-10-29: "Keep it running while others
are flying"); solo, or with nobody else flying, all held until the takeoff as before (user's question of 2026-10-29:
Shazzy's host log had 10-43 s holds). The CO-OP row is behind the HUD's info key (I), with a line a player when open
(docs/re/COOP.md section 7, docs/re/HUD_LAYOUT.md).
