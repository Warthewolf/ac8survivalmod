# Online co-op for AC8: feasibility, 2026-10-25

Research only: nothing under mod/, tools/*.py or runtime/ was changed. The user asked whether an AC7 co-op mod can be
learned from and made to work in AC8 (more than two players, and a rented server, came up as well).

Source studied: **Double Trigger** 0.3.1 (`ac7mp`), two-player online co-op for Ace Combat 7's campaign and free
missions. It's public domain (Unlicense), so its code may be copied; credit it anyway. The archive was unpacked into
the session scratchpad only; it is not in this repository.

Tags: **[V]** verified from Double Trigger's source or our own notes, **[I]** inferred, **[T]** needs a check in
AceCombat8.exe or in game. AceCombat8.exe was not available for this note: nothing here was checked against it.

---------------------------------------------------------------------------------------------------------------------
## 0. Summary
- **Possible, as its own large project.** Double Trigger's design carries over; almost none of its game-facing code
  does. [I]
- **The deciding unknown:** whether AC8's Online Mode code (the Emergency Call co-op that the Alicorn's EB_002 belongs
  to, ALICORN.md) can spawn and drive another player's plane for us, as AC7's did for Double Trigger. If yes, the
  hardest piece comes with the game. If not, we build the remote plane ourselves (much harder). [T]
- **Target Survival Mode first, not the campaign.** One map, our own spawner, and main.lua already holds the state
  (round, credits, shop, specials). The campaign needs per-mission and per-boss fixes; about 4,000 of Double Trigger's
  30,000 lines are exactly that (`special/`, 19 files). [I]
- **More than two players: yes, aim for 4.** Double Trigger's limit is one constant plus a "the other player"
  assumption; AC8's own co-op is built for a squad (EB_002's HP is "tuned for an online co-op squad", ALICORN.md). [I]
- **A dedicated server is possible but awkward and not needed.** The game is the server: it would mean a rented GPU
  Windows machine running a second licensed copy of AC8. Design a host-without-plane mode so it stays possible. [I]

---------------------------------------------------------------------------------------------------------------------
## 1. How Double Trigger works [V]
A `dinput8.dll` proxy (C++, MSVC, MinHook, Dear ImGui), pinned to one exe build (`Ace7Game.exe` PE timestamp
0x6362748e). Lines by folder: sync 10,010, mp 4,853, special 4,061, game 3,087, core 2,589, net 1,831, ui 1,538,
diag 1,526, hooks 315.

| Piece | How | Files |
|---|---|---|
| Transport | Steam P2P from inside the game process: `SteamNetworking005` (`SendP2PPacket` / `ReadP2PPacket`), lobbies, invites, through steam_api64.dll exports and the client's interface vtable | `net/steam.cpp`, `net/net.cpp`, `net/protocol.h` |
| Messages | 65 types, each with a scope (lobby / session / world) and who may send it (any, host only, to host only). Host -> clients: AI plane states, object states, mission vars, radio / BGM, phase start / result, drones, barriers, AI locks, sortie / load go. Client -> host: hits, score earned, identified targets, supply report | `net/protocol.h` |
| Remote player plane | AC7's own MP code: `FNimbusNetworkService` session, `APlayerPlane::CreateNetworkPlane` / `SetNetworkPlane`, an `ANetworkDummyController` possessing a deferred-spawned `APlayerPlane`, the way MP's `SpawnRemotePlane` does. The game's online modes are blocked while the mod is in, and its session code is reused for ours | `mp/planes.cpp`, `mp/session.cpp`, `core/online_block.*`, `hooks/fixes.cpp` |
| Host authority | The host's game runs the mission and the AI. On the client, AI planes and ground units become **puppets**: they tick the way the game ticks everything during replay playback (`IsReplaying` answers yes only while a puppet ticks), and are placed at the host's state, extrapolated, just before their tick. Their own launches and lock-ons are refused; the host's locks are applied through the real `SetLockedTarget` | `sync/puppet.*`, `sync/sync.cpp`, `sync/ai_locks.*`, `sync/ground.cpp` |
| Missiles | Each launch is sent; the other side fires a copy that flies from the sent state; the end (hit, miss, explode) is sent too. Hits by an AI at the client are decided by the host | `sync/missiles.cpp`, `sync/interceptions.cpp`, `sync/plane_damage.cpp`, `sync/client_hits.cpp` |
| Mission state | The host sends the mission variable object's changes (`mvar_msNN_C`); the client's script writes are set back to the host's values. Phase changes, mission complete, fail and retry, checkpoints, pause, cutscene skips, resupply go both ways as messages | `sync/mission_vars.cpp`, `sync/mission_flow.cpp`, `sync/fail_retry.cpp`, `sync/cutscenes.cpp`, `sync/supply.cpp` |
| Two players to the game | Hooks on `UObject::ProcessEvent` and the `GetPlayerPlane` / `GetPlayerPawn` thunks: trigger volumes test remote planes too, and while an overlap event about the remote plane runs, the getters return that plane. Distance and overlap checks called from Blueprints answer for the nearest / either player | `sync/triggers.cpp`, `diag/census.cpp` |
| AI target split | Enemies pick the closer player, with a player who already has several chasers counted as farther (`ai_spread`, default 0.3), and stick for about a minute | `README.md`, `mp/units.cpp` |
| Lobby flow | Both press Sortie; the host's mission and difficulty win; both load, report ready, and start on the host's clock. Version and mod-pak lists are compared | `mp/sortie.cpp`, `mp/loadwait.cpp`, `mp/match.cpp`, `mp/mod_paks.cpp` |
| Overlay | ImGui on a D3D11 `IDXGISwapChain::Present` hook (F5 panel: host, invite, join, settings) | `ui/` |

Known gaps it lists: Rage & Scream can desync after a cutscene; replays desync; **UE4SS is incompatible** (its hooks
collide with Double Trigger's).

---------------------------------------------------------------------------------------------------------------------
## 2. What carries over to AC8

### 2.1 Reusable as is, or nearly [I]
- **Steam layer** (`net/steam.cpp`): needs only steam_api64.dll, not game addresses. Works if AC8's Steam build loads
  steam_api64.dll in process. [T] Valve routes `ISteamNetworking` P2P through its relays when a direct connection
  fails, so no relay of our own is needed.
- **Protocol framework**: message scopes, host / client acceptance, heartbeat, reconnect, peer clock, the version and
  mod-pak comparison.
- **Lobby flow**: sortie ready / go, load wait, start on the host's clock.
- **The design**: host authority, puppets keyed by a cross-level key, copy missiles instead of syncing them, decide
  client-side hits on the host, the two-player trigger hooks, the target split.

### 2.2 Must be redone [V] unless marked
- **Every game address.** `game/game_addresses.inc` holds about 270 RVAs and vtable slots of the 2022 Ace7Game.exe.
  AC8's classes are a different family (`ALive*`, `LiveUnit`, `LiveAIPlane`, `ALiveAISubmarine`; ALICORN.md,
  SPAWN_SYSTEM.md), not AC7's `AGameObject` / `AAIPlane` / `UNimbus*`.
- **Engine layouts.** AC7 is UE4; AC8 is UE 5.4, where FVector / FRotator / FQuat are doubles (large world
  coordinates): `game/ue.h`'s offsets and float types are all wrong for it. [I]
- **Mission state.** AC7's missions run on Blueprint level scripts and `mvar` objects. AC8's run on event records,
  event flags, remote events and the game's Lua (EVENT_NOTES.md, GAME_LUA.md, hard rules 17 and 26). Syncing flags and
  remote events instead of a variable object may be simpler. [I]
- **UE4SS.** Survival Mode is a UE4SS mod (`runtime/survival_rt.c`, Scripts/main.lua). A co-op layer must live
  alongside it, best as part of the UE4SS C++ mod: UE4SS gives reflection (classes, properties, UFunctions by name),
  which replaces most of Double Trigger's address table.
- **Overlay.** D3D11 in AC7; check which renderer AC8 runs (D3D12 likely for UE5). [T] Survival's run-time Lua HUD
  (hard rule 18) may be enough for a lobby panel instead.
- **Online block.** AC8 has a live Online Mode. Our co-op must keep players out of the official online modes while it
  is installed, as Double Trigger does, and must not touch Bandai Namco's servers.

### 2.3 Puppets in AC8 [I] / [T]
Double Trigger's puppet trick depends on the game's replay playback path. AC8 has a replay menu (`ReplayMenu`,
`ReplayViewer` rows, AIRFIELD_SHOP_UI.md), so an `IsReplaying`-style switch probably exists. [T] Survival's own
lessons apply: Lua can't move a flying AI plane (hard rule 39), so placing puppets must be native, in the flight
engine, like Double Trigger's `OverwriteFELocationAndRotation`.

---------------------------------------------------------------------------------------------------------------------
## 3. More than two players [V] / [I]
- Double Trigger: `session::kPlayers = 2` sets the session capacity and Steam's lobby limit. Messages are already
  "host -> clients". The limit is in about 17 files that use `planes::RemotePlane()`, the one other player's plane,
  and in `net.cpp`'s peer selection (a third member is left out). [V]
- For AC8: build for N players (lists of remote planes, per-client sends), test with 2 first. Retrofitting N onto a
  two-player design costs far more than allowing for it from the start. [I]
- What scales with N [I]:
  - host upload: every client gets every AI plane's state. Survival rounds are dense; send only planes near each
    client at full rate, far ones slower;
  - target split: Double Trigger's rule works for N; it matters more at 4, so enemies don't all go for one player;
  - balance: round size, credits, specials (VALKA, AB.L..IN) and boss HP scale with players; CFG / survival.ini can
    carry the factors;
  - testing: one copy of the game per player.

---------------------------------------------------------------------------------------------------------------------
## 4. A rented server [I]
- **Relay only** (forward packets): no load taken off the host, and Steam's relays already do it for free.
- **Dedicated host**: no separate server program is possible without rewriting the game's logic, because the AI,
  missiles, event records and main.lua all run inside AceCombat8.exe. So it means:
  - a rented Windows cloud machine, likely with a GPU (UE5 usually wants one even off screen), roughly $0.50-1+ an
    hour;
  - a second copy of AC8 on its own Steam account; Bandai Namco's EULA may not allow running it as a server (check);
  - a mod "host without a plane" mode;
  - running without rendering, which AC8 wasn't built for.
- Not worth it for friends playing; worth keeping possible: keep "the machine that runs the mission" separate from
  "the players" in the design.

---------------------------------------------------------------------------------------------------------------------
## 5. Plan, if we go ahead
1. **Research (AceCombat8.exe, tools/re/exe.py)** [T]
   - AC8's online session service and how Emergency Call spawns a remote player plane (the equivalent of AC7's
     `CreateNetworkPlane` / `SpawnRemotePlane`), and whether it can run in a free mission / Survival level;
   - steam_api64.dll in process; the renderer;
   - the replay-playback check (for puppets) and the flight-engine setter for AI planes.
2. **Two players flying**: each sees the other's plane in Survival's level; nothing else synced.
3. **Host-run enemies**: the host's SV_Spawn flights appear on clients as puppets; missiles copied; hits and kills
   decided on the host.
4. **Survival state**: round, credits, airfield and shop, event flags and remote events, specials (VALKA, AB.L..IN,
   the Alicorn each need their own sync, like Double Trigger's `special/`).
5. **N players and balance**: lists everywhere, per-client send rates, scaling factors in survival.ini.

Open questions:
- Does AC8 have anti-cheat or integrity checks on its online code that a hook would trip? [T]
- Does AC8's game Lua (SingleGameluaContext) behave the same on host and client when fed the same flags? [T]
- Can two machines agree on a unit's identity? Double Trigger uses the actor manager's cross-level key; Survival
  could key on its own spawn records (unit name + spawn count from main.lua). [I]
