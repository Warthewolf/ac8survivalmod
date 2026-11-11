-- coop_revive_test.lua <mod dir> <work dir> (run by tools/checks/coop_revive_test.sh): Survival COOP's revives and the
-- spectator camera (sv_down.lua, docs/re/COOP.md 9; the user, 2026-10-29: "is there a revive option we could possibly
-- add for COOP only? like say if you die, HOST or JOINER, someone could land at the airfield and buy you back ... you
-- get put into a spectator camera and you can switch between the players currently active"), on the real sv_core,
-- sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_rounds, sv_tactical, sv_stats, sv_tells, sv_director,
-- sv_leaderboard, sv_coop (M exposed) and sv_down, the game and the runtime (SV_Down, SV_Respawn, ...) stubbed:
--   the floor: MinHealth held at floor_hp in co-op (set again when the game puts it back), none solo; a SECOND CHANCE
--     held goes first;
--   down: at the floor your plane invincible, hidden, no collision, weapons and flares off, the attackers' limits 0, the
--     loiter (SV_Down round the airfield), state bit 8 (not 2), "dw", the callout; COOP.players() counts you out;
--     another player's bit 8 hides their plane here and counts them out (othersFlying);
--   the camera: the first other player watched, a CameraComponent behind and above their plane, the next on the key, the
--     next by itself when the one watched goes down, the view put back (counted) when the game takes it, the HUD line;
--   a revive by a joiner (the host's checks, "rb" to everyone, the room's count and the next price) and by the host
--     (the STORE row's label, "(+1)", the price); (2026-11-11, the user: "readjust the revive costs") each player's own
--     revives pricing theirs, raise_max's cap (round 50: 9,500 to 28,500), the run's count apart, a late joiner's table
--     in "rc", the host's refusal "rx" putting a joiner's price right, broken counts and tables not taken;
--     the downed game's way back (loiter off, the plane as it was, repaired,
--     safe_s invincible, respawn loiter / native with SV_Respawn's pose; a plane that isn't flying, crashed into the
--     ground with its floor held, native whatever respawn says: the user's co-op run of 2026-10-30);
--   the refusals: not on the airfield, not down, a second revive, a wrong price, a bad request, another player's "dw";
--     a joiner's refund on "rx" and with no answer in 10 s; the row's CO-OP ONLY / NOBODY IS DOWN;
--   everyone down: the host's "ro" after 3 s (a player gone from the mission doesn't count; (0.73.77, A8) a player
--     linked and still loading in holds it, up to [coop] join_wait_s), each game's run over
--     (LB.finish, RE_SV_RunOver); the death check ending nothing in co-op, the run solo as ever;
--   the host down: its own-plane events not fired here, the rest as ever; the round bonus with down_round_bonus off;
--   the settings: the host's [coop.revive] for everyone but each player's key and camera;
--   the hooks by their place in the source (sv_main, sv_hud, sv_shop, the build's STORE row and RE_SV_RunOver).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world and the runtime, stubbed
VERSION = "0.72.2-revive.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance" }
local CAM = { full = "Class /Script/Engine.CameraComponent" }
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject(p) if p == "/Script/Engine.CameraComponent" then return CAM end return nil end
local grounded = false
function playerOnAirfield() return grounded end
function airfieldTick() end
function bombTick() end
local events, eventR = {}, 1
function SV_Event(name) events[#events + 1] = name; return eventR end
function SV_UnitAlive() return 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Spawn() return 1 end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
local sent, inbox = {}, {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
local info = "open=1;state=linked;peers=1/linked/40/10/b,2/linked/60/10/c"
function SV_CoopInfo() return info end
local meFlags = 0
function SV_CoopMe(_, flags) meFlags = flags or 0 end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
local peerState = {}
function SV_CoopPeerAt(slot) return peerState[slot] or "" end
local downCalls, respawns = {}, {}
function SV_Down(a, x, y, alt, r) downCalls[#downCalls + 1] = table.concat({ tostring(a), tostring(x), tostring(y), tostring(alt), tostring(r) }, ","); return 1 end
function SV_Respawn(a, x, y, z, p, yaw, r) respawns[#respawns + 1] = { a, x, y, z, p, yaw, r }; return 1 end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

local function part(name, chunk, edits) PARTS.load(name, chunk, edits) end   -- (the part and its pieces, each edit in the piece with its text)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
part("sv_config.lua")
CFG.coop.enabled = true                           -- (the Survival COOP build's, before sv_down binds its key)
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_tactical.lua"); part("sv_stats.lua"); part("sv_tells.lua"); part("sv_director.lua"); part("sv_leaderboard.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" } })
local M = _G.M
part("sv_down.lua")
local St = DOWN.St
function playerOnAirfield() return grounded end
function gamePaused() return false end
LB.special = function() end
local finished = {}
LB.finish = function(how) finished[#finished + 1] = how end
presetName = function() return "standard", 3 end
math.randomseed(7)

local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function line(pat, from) for i = #logs, from or 1, -1 do if logs[i]:find(pat) then return logs[i] end end return nil end
local function msgs(kind)
    local t = {}
    for _, s in ipairs(sent) do if s:find("^[-%d]+>" .. kind .. "|") then t[#t + 1] = s end end
    return table.concat(t, " ")
end
local function bitOn(f, b) return math.floor(f / b) % 2 == 1 end
local function callout(text) return line("^hud: callout '" .. text:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0") .. "'") ~= nil end

-- the scene: your plane (and its view), the other players' planes here
local LEVEL = " /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel."
local pawn = {}
local function newPawn(addr)
    pawn = { full = "BP_PlayerPlane_PP1000_f16c_C" .. LEVEL .. "Me", addr = addr or 9, MaxHealth = 100, HealthInternal = 800,
             MinHealth = 0, invincible = false, hidden = false, collision = true, bEnableWeaponInput = true,
             bEnableFlareInput = true, bIsWeaponSystemDisabled = false, MaxPlaneAttackerMissiles = 4, MaxPursuitAttackers = 6,
             MaxNonPlaneAttackerMissiles = 2 }
    -- (still unless flySpeed (cm/s) flies it along X from flyFrom; at: where a crashed plane lies)
    function pawn:K2_GetActorLocation()
        if self.at then return self.at end
        return { X = 1609639 + (self.flySpeed or 0) * (clock - (self.flyFrom or clock)), Y = -436414 + 400000, Z = 250000 }
    end
    function pawn:SetIsInvincible(v) self.invincible = v end
    function pawn:SetActorHiddenInGame(v) self.hidden = v end
    function pawn:SetActorEnableCollision(v) self.collision = v end
    -- (the game's SetMinHealth keeps whole health points, up to MaxHealth: its native 0x147d193b0 truncates, so 0.1 is 0;
    -- user's run of 2026-10-30, shot down with the floor "put back" every pass. The floor is the field itself)
    function pawn:SetMinHealth(v) self.minCalls = (self.minCalls or 0) + 1; self.MinHealth = math.min(math.max(0, math.floor(v)), math.floor(self.MaxHealth)) end
    survivalPC.Pawn = pawn
end
survivalPC = { view = nil, views = {} }
function survivalPC:SetViewTargetWithBlend(t, b) self.view = t; self.views[#self.views + 1] = (t.full or "?") .. "/" .. tostring(b) end
function survivalPC:GetViewTarget() return self.view end
newPawn()
local function plane(addr, name)
    local p = { full = "BP_NPC_f16c_C" .. LEVEL .. name, addr = addr, comps = {} }
    local function cam(c)                         -- (a camera: on / off, as UActorComponent's)
        c.active = c.active ~= false
        function c:IsActive() return self.active end
        function c:Deactivate() self.active = false end
        function c:Activate() self.active = true end
        return c
    end
    -- its own camera (a player plane's: COOP2MP's real planes carry cockpit / chase cameras)
    p.ownCam = cam({ addr = addr * 10 + 9, full = "CameraComponent " .. name .. ".CockpitCamera" })
    function p:AddComponentByClass(cls)
        local c = cam({ addr = addr * 10 + #self.comps, cls = cls })
        function c:K2_SetRelativeLocationAndRotation(l, r) self.loc, self.rot = l, r end
        self.comps[#self.comps + 1] = c
        return c
    end
    function p:K2_GetComponentsByClass()
        local l = { self.ownCam }
        for _, c in ipairs(self.comps) do l[#l + 1] = c end
        return { ForEach = function(_, fn) for i, c in ipairs(l) do fn(i, { get = function() return c end }) end end }
    end
    function p:SetActorHiddenInGame(v) self.hidden = v end
    function p:SetActorEnableCollision(v) self.collision = v end
    return p
end
local P0, P1, P2 = plane(1000, "SV_Peer0"), plane(1001, "SV_Peer1"), plane(1002, "SV_Peer2")
-- player N's state (flags: 1 in the level, 2 alive, 4 on the airfield, 8 DOWN; age ms)
local FLY, AIRFIELD_F, DOWNED, DEAD = 3, 7, 9, 1
local function peer(slot, flags, age) peerState[slot] = string.format("100000,0,300000,0,0,0,800,100,%d,%d", flags, age or 100) end
local function tick(dt)                          -- one Lua pass, in sv_main.lua's order: INS.tick, DOWN.tick; then COOP.tick
    clock = clock + (dt or 0.25)
    if D then D.now = clock end                  -- (roundsTick's clock: COOP.me() reads you once a pass by it)
    INS.tick(clock)
    DOWN.tick()
    COOP.tick(0)
end
local function ticks(s) for _ = 1, math.floor(s / 0.25 + 0.5) do tick() end end
local function scene(role, slot, peers)         -- a new level: co-op as `role` with the players `peers` (slot -> flags)
    CFG.coop.enabled = true
    COOP.open, COOP.role, COOP.slot = role ~= nil, role, slot
    D = { round = 5, state = "spawning", now = 99, at = 0, up = {}, flown = {}, queue = {}, spare = {}, events = {},
          orders = {}, pressure = "B", wave = 1 }
    RUN = { credits = 20000, earned = 0, spent = 0, bought = {}, msg = {}, dirty = true, kills = { you = 0 }, items = {},
            ups = {}, insured = false, stats = { started = os.time(), air = 0, ground = 0, aces = 0, allies = 0, af_down = 0,
            captured = 0, specials = {} } }
    DOWN.reset("a new level", true)
    TAC.reset()
    newPawn()
    survivalPC.view, survivalPC.views = pawn, {}
    sent, inbox, events, downCalls, respawns, finished = {}, {}, {}, {}, {}, {}
    grounded = false
    for s = 0, 23 do peerState[s] = nil end
    for s, f in pairs(peers or {}) do peer(s, f) end
    M.nextInfo = 0
    if role then
        tick()
        M.roster = { [0] = { name = "A" }, [1] = { name = "B" }, [2] = { name = "C" } }
        for s, o in pairs({ [0] = P0, [1] = P1, [2] = P2 }) do
            if peers and peers[s] and s ~= slot then o.gone, o.hidden, o.comps = nil, nil, {}; COOP.peerPlane(o, s) end
        end
        tick()
    else
        tick()
    end
    sent = {}
end

---------------------------------------------------------------------------------------------------- the floor
print("the prices")
-- (the user, 2026-10-30: "lower the cost for reviving": 2500, x1.25 a revive, was 5000 x1.5; (0.73.78, economy C6,
-- approved 2026-11-03) 2000 + 150 x the round, x1.25 a revive in the run)
do
    local cr = CFG.coop.revive
    check(cr.price == 2000 and cr.price_per_round == 150 and cr.raise == 1.25, "shipped: 2000 + 150 a round, x1.25 for each one in the run ("
          .. tostring(cr.price) .. " + " .. tostring(cr.price_per_round) .. " x" .. tostring(cr.raise) .. ")")
    local D0 = D
    local function at(round, state, n) D = { round = round, state = state }; local v = DOWN.priceFor(n); D = D0; return v end
    local p = {}
    for n = 0, 2 do p[#p + 1] = at(10, "fighting", n) end
    check(table.concat(p, " ") == "3500 4380 5470", "round 10: the run's first three 3500 4380 5470 (" .. table.concat(p, " ") .. ")")
    check(at(30, "fighting", 0) == 6500 and at(1, "spawning", 0) == 2150, "round 30: 6500; round 1: 2150 (" .. at(30, "fighting", 0) .. ", " .. at(1, "spawning", 0) .. ")")
    check(at(9, "wait", 0) == 3500 and at(0, "wait", 0) == 2150, "in the break after round 9: round 10's 3500; before round 1: round 1's 2150")
    check(DOWN.priceFor(0, 20) == 5000, "another round's price on asking: round 20, 5000")
    -- ((2026-11-11) the user: "readjust the revive costs") n is the revived player's own revives; raise_max 3 at most:
    -- round 50's base 9,500, never over 28,500 (the 50-round run's 13th revive cost 138,240)
    check(cr.raise_max == 3, "shipped: raise_max 3 (" .. tostring(cr.raise_max) .. ")")
    local q = {}
    for _, n in ipairs({ 0, 1, 4, 5, 12, 100000 }) do q[#q + 1] = at(50, "fighting", n) end
    check(table.concat(q, " ") == "9500 11880 23190 28500 28500 28500",
          "round 50: 9500, their 2nd 11880, 5th 23190; the 6th, 13th and 100001st capped at 28500 (" .. table.concat(q, " ") .. ")")
    check(DOWN.priceFor(5, 49) == 28050 and DOWN.priceFor(1, 49) == 11690, "round 49's on asking: capped 28050, the 2nd 11690 ("
          .. DOWN.priceFor(5, 49) .. ", " .. DOWN.priceFor(1, 49) .. ")")
    cr.raise_max = 0
    check(at(50, "fighting", 12) == 138240, "raise_max 0: no cap (round 50's 13th: 138240, as in the 50-round run)")
    cr.raise_max = 0.5
    check(at(50, "fighting", 3) == 9500, "raise_max under 1: never over the base (9500)")
    cr.raise_max = 3
    cr.price, cr.raise, cr.price_per_round = 5000, 1.5, 0   -- (the checks below were written for 5000 x1.5 flat: the logic is the same)
    check(DOWN.priceFor(3) == 15000 and DOWN.priceFor(2) == 11250, "5000 x1.5: the 3rd 11250, the 4th capped at 15000 (x3)")
end

print("the floor")
scene("host", 0, { [1] = FLY, [2] = FLY })
check(pawn.MinHealth == 0.1 and DOWN.floor() == 0.1, "co-op, another game linked: MinHealth 0.1 (floor_hp)")
local setsBefore = pawn.minCalls or 0
ticks(4)
check(pawn.MinHealth == 0.1 and (pawn.minCalls or 0) == setsBefore and line("put back by the game") == nil,
      "it stays 0.1: not set again, nothing \"put back\" (the field written, not SetMinHealth: whole points only)")
pawn.MinHealth = 0
local from = #logs + 1
tick()
check(pawn.MinHealth == 0.1 and line("insurance: your aircraft's floor was put back by the game", from) ~= nil, "the game puts it back to 0: set again (logged)")
scene(nil, nil)
check(pawn.MinHealth == 0 and DOWN.floor() == 0, "solo: no floor (as ever)")
pawn.HealthInternal = 1
ticks(1)
check(not DOWN.me(), "solo at 0.1 HP: never down")
-- ((2026-11-11) SECOND CHANCE solo: its floor read back as co-op's is. The game puts MinHealth back on a restore (an
-- airfield stop), and solo it was set once and never again: a paid item that did nothing after a landing)
RUN.insured = true
pawn.HealthInternal = 1000
tick()
check(pawn.MinHealth == 4, "solo, a SECOND CHANCE held: its floor 4 HP (" .. tostring(pawn.MinHealth) .. ")")
pawn.MinHealth = 0                                   -- (the game's restore at the airfield)
from = #logs + 1
tick()
check(pawn.MinHealth == 4 and line("insurance: your aircraft's floor was put back by the game", from) ~= nil,
      "solo: the game puts it back to 0: set again (logged)")
RUN.insured = false
tick()
check(pawn.MinHealth == 0, "solo, no SECOND CHANCE: no floor again")
scene("host", 0, { [1] = FLY })
RUN.insured = true
tick()
check(pawn.MinHealth == 4, "a SECOND CHANCE held: its own floor (4 HP) over the revives' (" .. tostring(pawn.MinHealth) .. ")")
pawn.HealthInternal = 40
tick()
check(not DOWN.me() and not RUN.insured and pawn.HealthInternal == 1000, "at its floor: SECOND CHANCE used first, not down")
tick()
check(pawn.MinHealth == 0.1, "then the revives' floor again")

---------------------------------------------------------------------------------------------------- down
print("down, and the spectator camera")
scene("host", 0, { [1] = FLY, [2] = FLY })
from = #logs + 1
pawn.HealthInternal = 1
tick()
check(DOWN.me() and pawn.invincible and pawn.hidden and pawn.collision == false, "at the floor: down, invincible, hidden, no collision")
check(pawn.bEnableWeaponInput == false and pawn.bEnableFlareInput == false and pawn.bIsWeaponSystemDisabled == true,
      "weapons and flares off")
check(pawn.MaxPlaneAttackerMissiles == 0 and pawn.MaxPursuitAttackers == 0 and pawn.MaxNonPlaneAttackerMissiles == 0, "the attackers' limits 0")
check(downCalls[1] == "9,1609639.0,-436414.0,2500,4000", "SV_Down(your plane, the airfield, 2500 m, 4000 m) (" .. tostring(downCalls[1]) .. ")")
check(bitOn(meFlags, 8) and not bitOn(meFlags, 2), "state bit 8, not 2 (flags " .. meFlags .. ")")
check(msgs("dw") == "-1>dw|0|0", "the host tells everyone: dw|0|0 (" .. msgs("dw") .. ")")
check(callout("YOU'RE DOWN"), "callout YOU'RE DOWN")
local me = COOP.me()
check(me.down == true and me.alive == false, "COOP.players(): you down, not alive")
check(survivalPC.view == P1 and #P1.comps == 1 and P1.comps[1].loc.X == -3000 and P1.comps[1].loc.Z == 800,
      "watching player 2: a camera 30 m behind and 8 m above their plane, the view on it")
check(DOWN.hudLine() == "DOWN: WATCHING B  [O] NEXT", "the NEXT row: " .. tostring(DOWN.hudLine()))
-- ((2026-11-07) the user: "enemies are attacking my downed aircraft") the host down: never a flight put on you (huntHost),
-- the round's fighter flights sent after a living player's real plane instead (huntReal), every 5 s
do
    local rawReal, rawAny, rawOn, rawHunt, rawUp = COOP.huntReal, COOP.anyReal, COOP.realOn, COOP.huntReal, D and D.up
    check(COOP.huntHost("ERA_Unit_01_Dep_Air0") == 0, "down: COOP.huntHost puts nothing on your plane (0)")
    local hunted = {}
    COOP.realOn, COOP.anyReal = function() return true end, function() return true end
    COOP.huntReal = function(u) hunted[#hunted + 1] = u; return true, 1, 2 end
    D = D or {}
    D.up = { ERA_Unit_01_Dep_Air0 = true, ERA_Unit_02_Dep_Air0 = true }
    local f2 = #logs + 1
    COOP.M.downHuntAt = 0
    tick()
    check(#hunted == 2 and has(line("^coop: you're down: 2 flights %(4 planes%) sent after the other players instead", f2), "sent after"),
          "down: the round's 2 fighter flights sent after a living player's real plane (huntReal), logged")
    COOP.huntReal, COOP.anyReal, COOP.realOn = rawHunt, rawAny, rawOn
    if D then D.up = rawUp end
end
check(P1.ownCam.active == false and P1.comps[1].active == true and line("^spectate: SV_Peer1's own cameras: CockpitCamera %(on%); 1 switched off", from) ~= nil,
      "their plane's own camera switched off while you watch it, ours on (the ADFX-02's view was its cockpit), logged")
DOWN.nextView("key")
check(survivalPC.view == P2 and DOWN.hudLine() == "DOWN: WATCHING C  [O] NEXT", "the key: player 3")
check(P1.ownCam.active == true and P2.ownCam.active == false, "player 2's camera back on as the view leaves, player 3's off")
DOWN.nextView("key")
check(survivalPC.view == P1 and #P1.comps == 1, "again: player 2, their camera kept")
survivalPC.view = pawn
tick()
check(survivalPC.view == P1 and St.reverts == 1 and line("spectate: view put back on B %(the game took it back 1 times%)", from) ~= nil,
      "the game takes the view back: put back, counted")
peer(1, DOWNED)
tick()
check(P1.hidden == true and P1.collision == false, "player 2 down too: their plane hidden here, no collision")
tick()
check(survivalPC.view == P2 and has(line("^spectate: view C", from), "their plane isn't up here now"), "the one watched goes down: the next by itself")
check(othersFlying() == 1, "othersFlying: player 3 only")
DOWN.nextView("key")
check(survivalPC.view == P2, "the only one left: the key keeps it")

---------------------------------------------------------------------------------------------------- the replay-style camera
print("the replay-style camera: a camera actor on a spring arm, your stick swings it, throttle / brake zoom")
local ARMCLS = { full = "Class /Script/Engine.SpringArmComponent" }
local rawSFO = StaticFindObject
function StaticFindObject(p) if p == "/Script/Engine.SpringArmComponent" then return ARMCLS end return rawSFO(p) end
local camActor = { full = "CameraActor" .. LEVEL .. "CameraActor_1", addr = 777, CameraComponent = { bConstrainAspectRatio = true } }
function camActor:K2_AttachToComponent(comp, sock, a, b, c, weld) self.parent, self.sock, self.rules = comp, tostring(sock), a .. b .. c end
local spawned = 0
function SV_SpawnCam() spawned = spawned + 1; return 777 end
local rawFAO = FindAllOf
function FindAllOf(c) if c == "CameraActor" then return { camActor } end return rawFAO(c) end
local stick = "0,0,0,0,0"
function SV_StickNow() return stick end
for _, p in ipairs({ P1, P2 }) do
    function p:K2_GetActorLocation() return { X = 0, Y = 0, Z = 250000 } end
    function p:GetActorBounds(_, o, e) o.X, o.Y, o.Z = 450, 0, 250030; e.X, e.Y, e.Z = 900, 700, 250 end   -- (its middle 4.5 m ahead)
    local add = p.AddComponentByClass
    function p:AddComponentByClass(cls, ...)
        local c = add(self, cls, ...)
        c.isArm = cls == ARMCLS
        function c:K2_SetRelativeRotation(r) self.rot = r end
        function c:K2_SetWorldLocation(l) self.world = l end
        return c
    end
end
St.watch = nil
from = #logs + 1
DOWN.nextView("test")
local w = St.watch
local arm = w and St.arms and St.arms[w.addr]
check(w and survivalPC.view == camActor and w.viewAddr == 777, "the view on our camera actor, not on the plane")
check(arm and arm.isArm and camActor.parent == arm and camActor.sock == "SpringEndpoint" and camActor.rules == "221",
      "at the end of a spring arm on the plane (snapped to it, turned with it)")
check(arm and arm.bDoCollisionTest == false and arm.bEnableCameraLag == true and arm.bEnableCameraRotationLag == true
      and arm.bInheritRoll == false and math.abs(arm.TargetArmLength - 3105) < 2, "the arm: lag on, no collision test, level horizon, 31 m")
check(camActor.CameraComponent.bConstrainAspectRatio == false and spawned == 1, "one camera actor, no letterbox")
check(arm and arm.world and arm.world.X == 450 and arm.world.Z == 250030 and line("^spectate: SV_Peer2's middle is 4.5 m from its root", from) ~= nil,
      "the arm's pivot on the plane's middle (its bounds), not its root, logged")
check(line("^spectate: replay%-style camera on", from) ~= nil, "logged")
check(has(DOWN.hudLine(), "STICK: CAMERA  THROTTLE/BRAKE: ZOOM"), "the NEXT row tells the controls: " .. tostring(DOWN.hudLine()))
local y0, p0, l0 = St.orbit.yaw, St.orbit.pitch, St.orbit.len
stick = "0,0,1000,0,0"
tick(); tick(); tick(); tick()
check(St.orbit.yaw > y0 + 80 and arm.rot and math.abs(arm.rot.Yaw - St.orbit.yaw) < 0.01, "full roll for a second: swung ~110 deg round the plane (" .. string.format("%.0f", St.orbit.yaw - y0) .. ")")
stick = "1000,0,0,0,0"
tick(); tick()
check(St.orbit.pitch > p0, "pitch: the camera tilts")
stick = "0,0,0,1000,0"
ticks(10)
check(St.orbit.len == 1000, "throttle held: zoomed in to 10 m at most (" .. St.orbit.len .. ")")
stick = "0,0,0,0,1000"
ticks(10)
check(St.orbit.len == 15000 and arm.TargetArmLength == 15000, "brake held: out to 150 m at most")
stick = "100,-100,100,0,0"
local y1 = St.orbit.yaw
tick()
check(St.orbit.yaw == y1, "inside the dead zone: still")
stick = "0,0,0,0,0"
survivalPC.view = pawn
tick()
check(survivalPC.view == camActor, "the game takes the view back: put back on the camera actor")
StaticFindObject, FindAllOf, SV_SpawnCam, SV_StickNow = rawSFO, rawFAO, nil, nil
St.camActor, St.watch = nil, nil                 -- (the old camera from here on: the sections below)
DOWN.nextView("test")

---------------------------------------------------------------------------------------------------- the host down: its own-plane events
print("the host down: events at its own plane not fired here")
events = {}
check(SV_Event("RE_SV_WolfTurn_01A") == -20 and SV_Event("RE_SV_Salvo_02B") == -20 and COOP.eventHere("RE_SV_GlitchGun") == -20,
      "a Wolf turn, a salvo, AB.L..IN's gun: not fired (-20)")
check(SV_Event("RE_SV_FlightOrders_01") == 1 and table.concat(events, ",") == "RE_SV_FlightOrders_01", "a flight's orders: fired as ever")

---------------------------------------------------------------------------------------------------- a restart while down
print("a restart while you're down, and the combat zone's edge")
-- (the user's co-op run of 2026-10-30: the host's DOWN plane left the combat zone, the mission failed and restarted in
-- round 7 in the same level with the same plane, refilled by the game: the host could fly it, but it stayed hidden, no
-- third-person view)
local function restartLevel()                    -- sv_main.lua's level-load reset on a restart: the same level and plane
    D = { round = 1, state = "spawning", now = 99, at = 0, up = {}, flown = {}, queue = {}, spare = {}, events = {},
          orders = {}, pressure = "B", wave = 1 }
    DOWN.reset("a new level", true)
    TAC.reset()
end
check(DOWN.me() and pawn.hidden and survivalPC.view == P2, "(down, watching player 3)")
check(line("^spectate: your own view as you went down: BP_PlayerPlane_PP1000_f16c_C .*%(your plane%)") ~= nil,
      "your own view noted as you went down: your plane")
from = #logs + 1
restartLevel()
check(not DOWN.me() and pawn.hidden == true and has(line("^down: a new level", from), "put back once the level's player is in"),
      "the restart's reset: not down, the put-back waits for the level's player")
pawn.HealthInternal = 1000                       -- (the game restores the plane)
tick()
check(pawn.hidden == false and pawn.collision == true and pawn.invincible == false, "the next pass: the same plane shown, collision, mortal")
check(pawn.bEnableWeaponInput == true and pawn.bIsWeaponSystemDisabled == false and pawn.MaxPursuitAttackers == 6,
      "its weapons and its attackers' limits back")
check(survivalPC.view == pawn and has(line("^down: after the restart", from), "the same plane")
      and has(line("^down: after the restart", from), "still on the plane you watched"),
      "the view off the plane you watched, back on yours: " .. tostring(line("^down: after the restart", from)))
ticks(1)
check(since(from, "^down: after the restart") == 1 and not DOWN.me(), "put back once; not down again")
-- down again, and the restart gives another plane with the view on it already: nothing touched
pawn.HealthInternal = 1
tick()
check(DOWN.me() and survivalPC.view ~= pawn, "(down again, watching)")
from = #logs + 1
restartLevel()
newPawn(77)
survivalPC.view = pawn
local nViews = #survivalPC.views
tick()
check(pawn.hidden == false and pawn.invincible == false and #survivalPC.views == nViews
      and has(line("^down: after the restart", from), "another plane (77; down was 9)") and has(line("^down: after the restart", from), "left as it is"),
      "another plane after the restart: nothing on it touched, the game's view left: " .. tostring(line("^down: after the restart", from)))
-- the combat zone's edge
newPawn()
survivalPC.view = pawn
pawn.HealthInternal = 1
tick()
check(DOWN.me(), "(down)")
respawns, from = {}, #logs + 1
local nDown = #downCalls
pawn.at = { X = ZONE.X + ZONE.HALF - 200000, Y = ZONE.Y, Z = 30000 }      -- (5 km from the real edge, 300 m up)
tick()
local er = respawns[1] or {}
check(#respawns == 1 and er[4] == 250000 and er[6] == -23 and math.abs((er[2] or 0) - (1609574 + math.cos(math.rad(-23)) * 400000)) < 1,
      "5 km from the zone's edge: SV_Respawn 4 km out along the runway, at the loiter's 2500 m")
check(pawn.hidden == true and pawn.collision == false and pawn.bEnableWeaponInput == false and #downCalls > nDown
      and (downCalls[#downCalls] or ""):find("^9,") ~= nil, "still out of the fight, the loiter on again the same pass")
check(has(line("^down: your plane was", from), "5.0 km from the combat zone's edge"), "logged: " .. tostring(line("^down: your plane was", from)))
ticks(5)
check(#respawns == 1, "not again within 20 s")
ticks(15.25)
check(#respawns == 2, "again after 20 s while it's still there")
-- drifted far from the airfield, well inside the zone (the user's co-op run of 2026-10-30: 15 -> 38 km out)
pawn.at = nil                                                        -- (back by the airfield while the 20 s run out)
ticks(20.25)
respawns, from = {}, #logs + 1
pawn.at = { X = 1609639 - 1200000, Y = -436414, Z = 250000 }         -- (12 km west of the airfield, nowhere near an edge)
tick()
check(#respawns == 1 and respawns[1][4] == 250000 and has(line("^down: your plane was", from), "12.0 km from the airfield"),
      "12 km from the airfield (drift_km 10): put back over it at the loiter's height, logged: " .. tostring(line("^down: your plane was", from)))
ticks(20.25)
respawns = {}
pawn.at = { X = 1609639 - 600000, Y = -436414, Z = 250000 }          -- (6 km out: within drift_km)
tick()
check(#respawns == 0, "6 km out: left alone")
pawn.at = nil

---------------------------------------------------------------------------------------------------- revives on the host
print("revives: the host's checks")
scene("host", 0, { [1] = FLY, [2] = AIRFIELD_F })
from = #logs + 1
peer(1, DOWNED)
inbox[#inbox + 1] = "1|dw|1"
tick()
check(msgs("dw") == "-1>dw|1|0" and callout("B DOWN"), "player 2's dw: told to everyone, called out")
check(P1.hidden == true, "their plane hidden here")
sent = {}
inbox[#inbox + 1] = "2|rv|1|5000"
tick()
check(msgs("rb") == "-1>rb|1|1|2|1" and St.count == 1 and St.per[1] == 1 and callout("B BACK"),
      "player 3 at their airfield revives player 2: rb|1|1|2|1 to everyone, the run's count 1, theirs 1")
sent = {}
inbox[#inbox + 1] = "2|rv|1|7500"
tick()
check(msgs("rx") == "2>rx|1|ALREADY BEING REVIVED|1|1", "a second revive within 15 s: refused, theirs with it (" .. msgs("rx") .. ")")
sent = {}
clock = clock + 16
inbox[#inbox + 1] = "2|rv|1|5000"
tick()
check(msgs("rx") == "2>rx|1|THE PRICE CHANGED: NOW 7500|1|1", "the old price: refused, the new one said (their second: x1.5)")
sent = {}
peer(2, FLY)
tick()
inbox[#inbox + 1] = "2|rv|1|7500"
tick()
check(msgs("rx") == "2>rx|1|NOT AT THE AIRFIELD|1|1", "the reviver not at the airfield: refused")
sent = {}
peer(1, FLY); peer(2, AIRFIELD_F)
tick()
inbox[#inbox + 1] = "2|rv|1|7500"
inbox[#inbox + 1] = "2|rv|x|7500"
inbox[#inbox + 1] = "1|dw|2"
tick()
check(msgs("rx") == "2>rx|1|NOT DOWN|1|1 2>rx|x|A BAD REQUEST", "not down; a bad request (" .. msgs("rx") .. ")")
check(msgs("dw") == "" and line("revive: player 2 said another player is down; ignored", from) ~= nil, "a dw for another slot: ignored")

print("revives: each player's own count, the run's apart (2026-11-11: \"readjust the revive costs\")")
do
    scene("host", 0, { [1] = FLY, [2] = AIRFIELD_F })
    local function downB() peer(1, DOWNED); inbox[#inbox + 1] = "1|dw|1"; tick(); sent = {} end
    local function upB() peer(1, FLY); tick(); clock = clock + 16 end
    downB()
    inbox[#inbox + 1] = "2|rv|1|5000"; tick()
    upB(); downB()
    check(DOWN.offer().price == 7500, "B's second: 7500")
    inbox[#inbox + 1] = "2|rv|1|7500"; tick()
    check(msgs("rb") == "-1>rb|1|2|2|2" and St.per[1] == 2, "B's second taken: rb with theirs 2")
    upB()
    peer(2, DOWNED); inbox[#inbox + 1] = "2|dw|2"; tick()
    grounded = true
    local o = DOWN.offer()
    check(o.label == "REVIVE C" and o.price == 5000, "C down after B's two: C's first, 5000 (" .. tostring(o.price) .. ")")
    local ok = DOWN.buy(5000)
    check(ok and St.count == 3 and St.per[1] == 2 and St.per[2] == 1, "C revived by the host: the run's count 3, B 2, C 1")
    grounded = false
    peer(2, AIRFIELD_F); tick(); clock = clock + 16
    downB()
    inbox[#inbox + 1] = "2|rv|1|11250"; tick()
    check(msgs("rb") == "-1>rb|1|4|2|3" and St.count == 4 and St.per[1] == 3, "B's third at 11250: the run's revive 4, theirs 3")
    -- a joiner who links now gets the run's count and each player's own
    sent = {}
    DOWN.syncTo(2)
    check(msgs("rc") == "2>rc|4|1:3,2:1", "a late joiner's rc: the run's 4, B 3, C 1 (" .. msgs("rc") .. ")")
end
do
    scene("join", 2, { [0] = FLY, [1] = FLY })
    inbox[#inbox + 1] = "0|rc|4|1:3,2:1"
    tick()
    check(St.count == 4 and St.per[1] == 3 and St.per[2] == 1, "a late joiner: the host's rc taken whole (4; B 3, C 1)")
    peer(1, DOWNED); tick()
    local o = DOWN.offer()
    check(o.price == 15000 and has(o.help, "Their revives this run: 3 of 4") and has(o.help, "x3 at most"),
          "its row: B at their 4th, capped at x3: 15000 (" .. tostring(o.price) .. "; " .. tostring(o.help) .. ")")
    inbox[#inbox + 1] = "0|rc|5|0:1,1:2,99:7,x:1,2:1e9,3:-1,4:1.5,5:100001,6:100000,,7:"
    tick()
    check(St.count == 5 and St.per[0] == 1 and St.per[1] == 2 and St.per[2] == nil and St.per[6] == 100000 and St.per[99] == nil
          and St.per[4] == nil and St.per[5] == nil and St.per[3] == nil, "a broken rc: only whole slots 0-23 and counts 0-100000 taken")
    inbox[#inbox + 1] = "0|rc|5|" .. string.rep("1:1,", 100)
    tick()
    check(St.per[1] == 2, "an rc table too long: kept as it was")
    inbox[#inbox + 1] = "0|rc|5|"
    tick()
    check(next(St.per) == nil, "an empty rc table: nobody's revived")
    inbox[#inbox + 1] = "0|rb|1|6|0|nan"
    tick()
    check(St.per[1] == 1 and St.count == 6, "an rb with a broken count of theirs: one more of theirs here")
    inbox[#inbox + 1] = "0|rx|1|NOT DOWN|6|1e9"
    tick()
    check(St.per[1] == 1, "an rx with a count past 100000: not taken")
end

print("revives: the price by the round (0.73.78, economy C6)")
do
    local cr = CFG.coop.revive
    cr.price, cr.raise, cr.price_per_round = 2000, 1.25, 150
    scene("host", 0, { [1] = FLY, [2] = AIRFIELD_F })
    D.round, D.state = 10, "fighting"
    peer(1, DOWNED); inbox[#inbox + 1] = "1|dw|1"; tick()
    local o = DOWN.offer()
    check(o.price == 3500 and has(o.help, "and 150 more a round"), "round 10: the row's price 3500, its help says 150 more a round ("
          .. tostring(o.price) .. ")")
    sent = {}
    from = #logs + 1
    inbox[#inbox + 1] = "2|rv|1|3500"
    tick()
    check(msgs("rb") == "-1>rb|1|1|2|1" and St.count == 1 and has(line("revive: player 3 revived player 2 for 3500", from), "the run's revive 1, their 1; round 10's price"),
          "round 10: player 3's revive at 3500 taken (round 10's price, logged)")
    peer(1, FLY); tick()
    D.state = "wait"                                  -- (round 10 cleared: the break's prices are round 11's)
    clock = clock + 16
    peer(1, DOWNED); inbox[#inbox + 1] = "1|dw|1"; tick()
    sent = {}
    inbox[#inbox + 1] = "2|rv|1|3500"
    tick()
    check(msgs("rx") == "2>rx|1|THE PRICE CHANGED: NOW 4560|1|1", "the break: their first revive's price again: refused, round 11's 4560 said ("
          .. msgs("rx") .. ")")
    sent = {}
    inbox[#inbox + 1] = "2|rv|1|4380"
    tick()
    check(msgs("rb") == "-1>rb|1|2|2|2" and St.count == 2, "... round 10's price for their second revive (4380), asked as the round changed: taken")
    cr.price, cr.raise, cr.price_per_round = 5000, 1.5, 0
end

print("revives: by the host, the STORE's row")
scene("host", 0, { [1] = FLY, [2] = FLY })
local o = DOWN.offer()
check(o.why == "NOBODY IS DOWN." and o.price == nil, "nobody down: NOBODY IS DOWN.")
peer(1, DOWNED); tick(1); peer(2, DOWNED); tick()
o = DOWN.offer()
check(o.label == "REVIVE B (+1)" and o.price == 5000 and o.slot == 1, "two down: REVIVE B (+1), 5000 (" .. tostring(o.label) .. ")")
local ok, why = DOWN.buy(5000)
check(not ok and why == "NOT AT THE AIRFIELD.", "the host in the air: refused, nothing charged (" .. tostring(why) .. ")")
grounded = true
ok, why = DOWN.buy(5000)
check(ok and why == "REVIVED B." and msgs("rb") == "-1>rb|1|1|0|1", "at the airfield: REVIVED B., rb|1|1|0|1")
peer(1, FLY); tick()
o = DOWN.offer()
check(o.label == "REVIVE C" and o.price == 5000 and has(o.help, "Their revives this run: 0 of 1"),
      "then REVIVE C at 5000: their first (B's revive isn't theirs; 2026-11-11) (" .. tostring(o.price) .. "; " .. tostring(o.help) .. ")")
ok, why = DOWN.buy(7500)
check(not ok and why == "THE PRICE CHANGED: CHECK IT AND PRESS AGAIN.", "an old price: refused")
COOP.open = false
check(DOWN.offer().why == "CO-OP ONLY.", "co-op closed: CO-OP ONLY.")
COOP.open = true

---------------------------------------------------------------------------------------------------- a joiner
print("a joiner: down and back, its revives")
scene("join", 1, { [0] = FLY, [2] = FLY })
pawn.HealthInternal = 1
tick()
check(DOWN.me() and msgs("dw") == "-1>dw|1", "down: dw|1 to the host")
sent = {}
inbox[#inbox + 1] = "0|rb|1|1|2"
from = #logs + 1
tick()
check(not DOWN.me() and (downCalls[#downCalls] or ""):find("^0,nil") and pawn.hidden == false and pawn.collision == true, "rb for you: back, the loiter off, shown")
check(pawn.bEnableWeaponInput == true and pawn.bIsWeaponSystemDisabled == false and pawn.MaxPursuitAttackers == 6, "weapons and the attackers' limits as they were")
check(events[#events] == "RE_SV_RepairAircraft" and pawn.HealthInternal == 1000 and pawn.invincible, "repaired, invincible")
check(survivalPC.view == pawn and callout("BACK IN THE FIGHT"), "the view yours, called out")
check(bitOn(meFlags, 2) and not bitOn(meFlags, 8), "state bit 2 again, 8 off")
ticks(5.25)
check(pawn.invincible == false, "safe_s 5 s on: invincible off")
check(line("^revive: respawn d=0 m", from) ~= nil, "respawn loiter: where the loiter left you (d=0 m)")
-- respawn native
pawn.HealthInternal = 1
tick()
CFG.coop.revive.respawn = "native"
inbox[#inbox + 1] = "0|rb|1|2|0"
tick()
local r = respawns[1] or {}
local y = math.rad(-23)
check(math.abs((r[2] or 0) - (1609574 + math.cos(y) * 400000)) < 1 and math.abs((r[3] or 0) - (-435747 + math.sin(y) * 400000)) < 1
      and r[4] == 50000 and r[6] == -23, "respawn native: SV_Respawn 4 km out along the runway's heading, 500 m up, yaw -23")
CFG.coop.revive.respawn = "loiter"
-- a crashed plane (the floor held, the plane lying on the ground: the user's co-op run of 2026-10-30, VERDA revived where
-- it lay) comes back the native way; a flying one where the loiter left it
respawns = {}
local fromFly = #logs + 1
pawn.flySpeed, pawn.flyFrom = 15000, clock
pawn.HealthInternal = 1
tick()
ticks(10)
from = #logs + 1
inbox[#inbox + 1] = "0|rb|1|2|0"
tick()
check(not DOWN.me() and #respawns == 0 and has(line("^revive: back", from), "where the loiter left you")
      and line("^down: your plane isn't flying", fromFly) == nil, "flying at 150 m/s when revived: where the loiter left it, no SV_Respawn")
pawn.flySpeed, pawn.at = nil, { X = 1609639 + 150000, Y = -436414, Z = 500 }
pawn.HealthInternal = 1
from = #logs + 1
tick()
ticks(5)
check(DOWN.me() and since(from, "^down: your plane isn't flying %(0 m/s, 5 m up, 1%.5 km from the airfield%)") == 1,
      "crashed, lying still: not flying, said once (" .. tostring(line("^down: your plane isn't", from)) .. ")")
check(has(line("^down: loiter", from), "0 m/s"), "the loiter line has its speed: " .. tostring(line("^down: loiter", from)))
inbox[#inbox + 1] = "0|rb|1|2|0"
tick()
r = respawns[1] or {}
check(not DOWN.me() and r[4] == 50000 and r[6] == -23 and has(line("^revive: back", from), "your plane wasn't flying: 0 m/s"),
      "revived: SV_Respawn 4 km out from the runway, 500 m up, not where it lay (" .. tostring(line("^revive: back", from)) .. ")")
-- revived far out (the loiter drifted: near_km 8): back by the runway, not out there
pawn.at = { X = 1609639 + 2000000, Y = -436414, Z = 250000 }
pawn.flySpeed, pawn.flyFrom = 15000, clock
pawn.HealthInternal = 1
tick()
respawns, from = {}, #logs + 1
inbox[#inbox + 1] = "0|rb|1|2|0"
tick()
r = respawns[#respawns] or {}                    -- (the revive's: the drift guard may have put it back first)
check(not DOWN.me() and r[4] == 50000 and has(line("^revive: back", from), "the loiter had left you 20.0 km from the airfield"),
      "revived 20 km out: SV_Respawn by the runway (" .. tostring(line("^revive: back", from)) .. ")")
pawn.at, pawn.flySpeed = nil, nil
-- its revives of another player
sent = {}
peer(2, DOWNED); tick()
o = DOWN.offer()
check(o.label == "REVIVE C" and o.price == 5000, "player 3 down: REVIVE C at their own count 0: 5000, not the room's (" .. tostring(o.price) .. ")")
inbox[#inbox + 1] = "0|rx|2|NOT DOWN|4|2"                -- (the host's refusal of an ask of before: theirs is 2)
tick()
o = DOWN.offer()
check(St.per[2] == 2 and St.count == 4 and o.price == 5000 * 1.5 * 1.5, "the host's rx with theirs (2): the price put right, 11250 (" .. tostring(o.price) .. ")")
ok, why = DOWN.buy(o.price)
RUN.credits = RUN.credits - o.price                      -- (sv_shop.lua's shopBuy charges it)
check(ok and msgs("rv") == "0>rv|2|11250" and St.pending[2] ~= nil, "asked: rv|2|11250 to the host (" .. msgs("rv") .. ")")
check(DOWN.offer().why == "ASKED: WAITING FOR THE HOST.", "the row: waiting for the host")
inbox[#inbox + 1] = "0|rx|2|NOT AT THE AIRFIELD|2"
tick()
check(RUN.credits == 20000 and RUN.msg.Revive == "REFUSED: NOT AT THE AIRFIELD. 11250 REFUNDED.", "rx: refunded, the row says why")
ok = DOWN.buy(11250); RUN.credits = RUN.credits - 11250
ticks(10.25)
check(RUN.credits == 20000 and RUN.msg.Revive == "NO ANSWER FROM THE HOST. 11250 REFUNDED.", "no answer in 10 s: refunded")
ok = DOWN.buy(11250); RUN.credits = RUN.credits - 11250
inbox[#inbox + 1] = "0|rb|2|5|1|3"
tick()
check(RUN.credits == 8750 and RUN.msg.Revive == "REVIVED C." and St.count == 5 and St.per[2] == 3 and callout("C BACK"),
      "rb by you: paid, REVIVED C., the run's count 5, theirs 3")
-- the round bonus while down
pawn.HealthInternal = 1
tick()
local c0 = RUN.credits
inbox[#inbox + 1] = "0|cr|500|round 5 cleared"
tick()
check(RUN.credits == c0 + 500, "down: the host's round bonus paid (down_round_bonus)")
CFG.coop.revive.down_round_bonus = false
inbox[#inbox + 1] = "0|cr|500|round 6 cleared"
tick()
check(RUN.credits == c0 + 500, "down_round_bonus off: not paid")
CFG.coop.revive.down_round_bonus = true
inbox[#inbox + 1] = "0|ro|5"
tick()
check(finished[1] == "died" and events[#events] == "RE_SV_RunOver", "the host's ro: the run's over here (LB.finish, RE_SV_RunOver)")

---------------------------------------------------------------------------------------------------- the host revived
-- (the user's co-op run of 2026-10-30: the host was DOWN for 2.5 minutes and nobody bought it back before the mission
-- failed, so a joiner reviving the host had never run in game)
print("the host down, revived by a joiner")
scene("host", 0, { [1] = AIRFIELD_F, [2] = FLY })
pawn.HealthInternal = 1
tick()
check(DOWN.me() and pawn.hidden and survivalPC.view ~= pawn and msgs("dw") == "-1>dw|0|0", "the host down: hidden, watching, dw|0|0 to everyone")
sent = {}
from = #logs + 1
pawn.HealthInternal = 1                           -- (still at the floor when the joiner buys it back)
inbox[#inbox + 1] = "1|rv|0|5000"
tick()
check(not DOWN.me() and pawn.hidden == false and pawn.collision == true and pawn.bEnableWeaponInput == true and survivalPC.view == pawn,
      "player 2 at their airfield revives the host: back, shown, armed, the view its own")
check(msgs("rb") == "-1>rb|0|1|1|1" and St.count == 1 and line("^revive: player 2 revived player 1 for 5000", from) ~= nil
      and callout("BACK IN THE FIGHT"), "rb|0|1|1 to everyone, the room's count 1, logged, called out (" .. msgs("rb") .. ")")
check(pawn.HealthInternal == 1000 and events[#events] == "RE_SV_RepairAircraft", "repaired")
peer(1, FLY)
pawn.HealthInternal = 1
tick()
sent = {}
inbox[#inbox + 1] = "1|rv|0|7500"
tick()
check(DOWN.me() and msgs("rx") == "1>rx|0|NOT AT THE AIRFIELD|1|1", "down again, the joiner flying: refused, told why (" .. msgs("rx") .. ")")
peer(1, AIRFIELD_F)
tick()                                            -- (their landed state in first)
sent = {}
inbox[#inbox + 1] = "1|rv|0|7500"
tick()
check(not DOWN.me() and msgs("rb") == "-1>rb|0|2|1|2", "down again within 15 s of the last revive, the joiner landed: revived again ("
      .. msgs("rb") .. msgs("rx") .. ")")

---------------------------------------------------------------------------------------------------- the landing's lock
-- (0.73.73, the testers' logs of 0.73.70: Shazzy, A04, down 13:36:53 at 41 m by the airfield with the gear out, revived
-- 13:38:07 and "unable to shoot" until he landed and rearmed; cressendo, A10, gear out 11:26:11, down 11:26:15, his FCS
-- locked after the revive until he lowered and raised the gear. DOWN put back the inputs as it found them: the landing's
-- lock.) The plane's own functions, stubbed: the gear (GetGearDownRate, the gear key), IsOnGround, the weapon system,
-- CancelLanding
local function landingPawn()
    pawn.gearRate, pawn.onGround, pawn.calls, pawn.bEnableChangeTargetInput = 0, false, {}, true
    function pawn:GetGearDownRate() return self.gearRate end
    function pawn:IsOnGround() return self.onGround end
    function pawn:IsWeaponSystemDisabled() return self.bIsWeaponSystemDisabled end
    function pawn:DisableWeaponSystem(b) self.calls[#self.calls + 1] = "DisableWeaponSystem(" .. tostring(b) .. ")"; self.bIsWeaponSystemDisabled = b end
    function pawn:CancelLanding(f) self.calls[#self.calls + 1] = "CancelLanding(" .. tostring(f) .. ")" end
    function pawn:OnGearPressed() self.calls[#self.calls + 1] = "OnGearPressed"; self.gearRate = 1 - self.gearRate end
    function pawn:OnGearReleased() self.calls[#self.calls + 1] = "OnGearReleased" end
end
local function called(what) return has(table.concat(pawn.calls, ","), what) end
print("a revive after going down with the gear out: armed, the landing cancelled, gear up, watched")
scene("join", 1, { [0] = FLY, [2] = FLY })
landingPawn()
pawn.gearRate, pawn.onGround = 1, true                              -- (rolling out at the airfield, the gear out:
pawn.bEnableWeaponInput, pawn.bIsWeaponSystemDisabled = false, true -- the game's landing lock on)
from = #logs + 1
pawn.HealthInternal = 1
tick()
local dl = line("^down: you're down", from)
check(DOWN.me() and has(dl, "bEnableWeaponInput false -> false") and has(dl, "bIsWeaponSystemDisabled true -> true")
      and has(dl, "gear DOWN (1.00), on the ground"), "down: what it found logged (the landing's lock, the gear out, on the ground): " .. tostring(dl))
pawn.gearRate, pawn.onGround = 0, false                             -- (the loiter flies it, the gear raised)
ticks(2)
from = #logs + 1
pawn.calls = {}
inbox[#inbox + 1] = "0|rb|1|1|2"
tick()
check(not DOWN.me() and pawn.bEnableWeaponInput == true and pawn.bEnableFlareInput == true and pawn.bIsWeaponSystemDisabled == false,
      "revived: armed as a flying plane's, not the landing's lock DOWN found")
check(called("CancelLanding(true)") and called("DisableWeaponSystem(false)") and not called("OnGearPressed"),
      "the landing cancelled (down with the gear out), DisableWeaponSystem(false), the gear left up: " .. table.concat(pawn.calls, ","))
local rl = line("^revive: your weapons armed", from)
check(has(rl, "bEnableWeaponInput false -> true") and has(rl, "bIsWeaponSystemDisabled true -> false")
      and has(rl, "the landing cancelled: called") and has(rl, "DOWN found bEnableWeaponInput false") and has(rl, "gear DOWN, on the ground")
      and has(rl, "the gear now up (0.00)"), "logged: " .. tostring(rl))
local bl, ri = nil, nil
for i = from, #logs do if logs[i]:find("^revive: back") then bl = i elseif logs[i]:find("^revive: your weapons armed") then ri = i end end
check(bl and ri and bl < ri, "armed after the plane's placed (SV_Respawn's reset can't undo it)")
pawn.bIsWeaponSystemDisabled = true                                  -- (the game puts its lock back)
tick()
check(pawn.bIsWeaponSystemDisabled == false and has(line("^revive: the game locked your weapons again", from), "bIsWeaponSystemDisabled true"),
      "the game's lock again: taken off, logged")
pawn.calls = {}
pawn.bEnableWeaponInput = false
tick()
check(pawn.bEnableWeaponInput == true and called("CancelLanding(true)")
      and has(line("^revive: the game locked your weapons again", from), "the game's landing cancelled"), "again: armed, the landing cancelled")
ticks(10)
check(line("^revive: your weapons 10 s after the revive: armed %(locked again by the game 2 times%)", from) ~= nil,
      "the watch's end logged: " .. tostring(line("^revive: your weapons 10 s", from)))
pawn.bIsWeaponSystemDisabled = true
tick()
check(pawn.bIsWeaponSystemDisabled == true, "after the watch: the game's own (a landing of yours) left alone")
pawn.bIsWeaponSystemDisabled = false
-- down in the air, the gear up; revived with it still down: the gear key, let go a pass on; no landing to cancel
pawn.HealthInternal = 1
tick()
check(DOWN.me(), "(down again, in the air, the gear up)")
pawn.gearRate = 1
pawn.calls, from = {}, #logs + 1
inbox[#inbox + 1] = "0|rb|1|2|2"
tick()
check(called("OnGearPressed") and pawn.gearRate == 0 and not called("OnGearReleased") and not called("CancelLanding"),
      "revived with the gear still down: the gear key pressed, no landing cancelled: " .. table.concat(pawn.calls, ","))
check(has(line("^revive: your weapons armed", from), ": raised (the gear key)") and has(line("^revive: your weapons armed", from), "the landing cancelled: not needed"),
      "logged: " .. tostring(line("^revive: your weapons armed", from)))
tick()
check(called("OnGearReleased"), "the gear key let go the next pass")
ticks(2)
check(line("^revive: your gear 2 s after the revive: up %(0%.00%)", from) ~= nil, "the gear read 2 s on: up")
-- a landing of yours within the watch: left to the game
grounded = true
pawn.bIsWeaponSystemDisabled = true
tick()
check(pawn.bIsWeaponSystemDisabled == true, "on the airfield within the watch (landing): the game's lock left alone")
ticks(10)
check(has(line("^revive: your weapons 10 s after the revive", from), "you're landing: left to the game"), "logged at the watch's end")
grounded = false

---------------------------------------------------------------------------------------------------- parked
-- (0.73.73: Shazzy, A02, a joiner, left the STORE at 11:24:25 and sat at the airfield, 7 m up, 0 m/s, until an Su-33's
-- missiles took him to the floor, 11:24:37-41; with players linked the world runs on while you're down there)
print("parked at your airfield (co-op): invincible on the ground")
scene("join", 1, { [0] = FLY, [2] = FLY })
landingPawn()
grounded, pawn.at = true, { X = 1609639, Y = -436414, Z = 700 }
from = #logs + 1
ticks(1)
check(pawn.invincible == true and line("^airfield: on the ground at your airfield", from) ~= nil and DOWN.parked(),
      "still at 7 m by the runway: invincible, logged")
pawn.HealthInternal = 1                                    -- (its floor: no hit gets through an invincible plane in game)
pawn.HealthInternal = 800
grounded, pawn.at = false, nil
tick()
check(pawn.invincible == true, "just off the ground: still, for 1 s")
ticks(1.25)
check(pawn.invincible == false and not DOWN.parked() and line("^airfield: off the ground after %d+ s: invincible off$", from) ~= nil,
      "off the ground 1 s: invincible off, logged: " .. tostring(line("^airfield: off the ground", from)))
grounded, pawn.onGround = true, true                       -- (the game's IsOnGround: the takeoff roll at any speed)
tick()
check(pawn.invincible == true, "IsOnGround: on")
grounded, pawn.onGround = false, false
ticks(1.5)
check(pawn.invincible == false, "airborne: off")
CFG.coop.revive.parked_safe = false
grounded, pawn.at = true, { X = 1609639, Y = -436414, Z = 700 }
ticks(1)
check(pawn.invincible == false and not DOWN.parked(), "[coop.revive] parked_safe = false: not protected")
CFG.coop.revive.parked_safe = nil
scene(nil, nil)
landingPawn()
grounded, pawn.at = true, { X = 1609639, Y = -436414, Z = 700 }
ticks(1)
check(pawn.invincible == false and not DOWN.parked(), "solo: not protected (the stock game's STORE freeze as ever)")
-- a revive's invincibility not cut short by leaving the ground
scene("join", 1, { [0] = FLY, [2] = FLY })
landingPawn()
pawn.HealthInternal = 1
tick()
inbox[#inbox + 1] = "0|rb|1|1|2"
tick()
check(not DOWN.me() and pawn.invincible == true, "(revived: safe_s invincible)")
grounded, pawn.at = true, { X = 1609639, Y = -436414, Z = 700 }
ticks(1)
grounded, pawn.at = false, nil
from = #logs + 1
ticks(1.5)
check(pawn.invincible == true and has(line("^airfield: off the ground", from), "left on"), "off the ground within safe_s: its invincibility left on")
ticks(3)
check(pawn.invincible == false, "then safe_s runs out: off")

---------------------------------------------------------------------------------------------------- everyone down
print("everyone down: the run's over")
scene("host", 0, { [1] = FLY, [2] = FLY })
pawn.HealthInternal = 1
tick()
peer(1, DOWNED); peer(2, DOWNED)
ticks(2.5)
check(msgs("ro") == "", "everyone down 2.5 s: not yet")
ticks(1)
check(msgs("ro") == "-1>ro|5" and finished[1] == "died" and events[#events] == "RE_SV_RunOver", "3 s: ro|5 to everyone, the run's over here")
scene("host", 0, { [1] = FLY, [2] = FLY })
pawn.HealthInternal = 1
tick()
peer(1, DOWNED); peer(2, FLY, 6000)
ticks(3.5)
check(msgs("ro") == "-1>ro|5", "a player gone from the mission (6 s unheard) doesn't hold it")
scene("host", 0, { [1] = FLY, [2] = FLY })
pawn.HealthInternal = 1
tick()
peer(1, DOWNED)
ticks(5)
check(msgs("ro") == "" and #finished == 0, "one still flying: no ro")
-- ((0.73.77) plan A8: Saint Alessia's run of 2026-11-03, the run ended with scaraboy13's plane 9 s from arriving)
print("A8: a player still loading in holds the run-over")
scene("host", 0, { [1] = FLY })                 -- (C, slot 2, linked: on the roster, no plane in the mission yet)
pawn.HealthInternal = 1
tick()
peer(1, DOWNED)
local from8 = #logs + 1
ticks(5)
check(msgs("ro") == "" and line("down: run over held: player C still loading in", from8) ~= nil,
      "everyone in the mission down, C linked and loading in: held, logged")
peer(2, FLY)
ticks(5)
check(msgs("ro") == "", "C's plane in the mission, flying: no run-over")
peer(2, DOWNED)
ticks(4)
check(msgs("ro") == "-1>ro|5", "C down too: the run's over (3 s)")
scene("host", 0, { [1] = FLY })
pawn.HealthInternal = 1
tick()
peer(1, DOWNED)
ticks(80)
check(msgs("ro") == "", "C loading 80 s: still held")
ticks(15)
check(msgs("ro") == "-1>ro|5" and line("down: run over no longer held %(C:", from8) ~= nil,
      "C never in the mission past [coop] join_wait_s (90 s): the run's over")
-- the death check
scene("host", 0, { [1] = FLY })
RUN.stats.flying = true
pawn.HealthInternal = 0
LB.deathCheck(survivalPC); LB.deathCheck(survivalPC)
check(#finished == 0, "co-op: your plane at 0 ends no run (the host's ro does)")
scene(nil, nil)
RUN.stats.flying = true
pawn.HealthInternal = 0
LB.deathCheck(survivalPC); LB.deathCheck(survivalPC)
check(finished[1] == "died", "solo: shot down, the run's over (as ever)")

---------------------------------------------------------------------------------------------------- the 50-round run
-- (2026-11-11, Saint Alessia's and Delta's logs of her 50-round co-op run; the user: "the enemy AI followed my corpse
-- plane in its orbit around the base". sv_ai.lua ACE.hunt wrote the host's own plane into every Reaper's TargetActor
-- every 2 s, DOWN or not, undoing the down pass 3 s after it ran; the down pass never checked a flight it had sent once;
-- the stats and the learning profile counted the loiter as her flying)
print("the 50-round run: the enemies never on the DOWN host's hidden plane")
do
    scene("host", 0, { [1] = FLY, [2] = FLY })
    local REAPER = CFG.tiers.list[#CFG.tiers.list]
    check(REAPER.name == "Reaper" and CFG.aces.flight.reaper.hunt == true, "(the top tier, Reaper, hunts: ACE.hunt)")
    local U, U2 = "ERA_Unit_05_Dep_Air2", "ERA_Unit_06_Dep_Air0"
    local function enemy(addr, unit)                -- a Reaper fighter with its blackboard (TargetActor) and orders
        local bb = { writes = 0 }
        function bb:GetValueAsObject() return self.tgt end
        function bb:SetValueAsObject(_, o) self.tgt, self.writes = o, self.writes + 1 end
        function bb:GetValueAsEnum() return 10 end
        local o = { full = "BP_OP1032_f18e_CP_C" .. LEVEL .. "E" .. addr, addr = addr, HealthInternal = 1000,
                    AIStateComponent = { BlackboardComponent = bb } }
        return { obj = o, unit = unit, name = "BP_OP1032_f18e_" .. addr, tier = REAPER, bb = bb }
    end
    local e = enemy(5001, U)
    M.units[U] = { gen = 3, n = 1, planes = { [1] = { id = 9001 } }, ground = {}, at = clock - 60 }   -- (a plane alive: kept)
    local Pe = M.peers[1]
    check(Pe and Pe.obj == P1 and Pe.shown == true and Pe.fresh == true, "(player 2's plane shown here, their state fresh)")
    local tellN, rawTell = 0, TELL.hunted
    TELL.hunted = function() tellN = tellN + 1 end
    -- flying, co-op: a Reaper on another living player's plane stays on it (flow-5: it was pulled back onto the host)
    e.bb.tgt = P1
    from = #logs + 1
    ACE.hunt(e)
    check(e.bb.tgt == P1 and e.bb.writes == 0 and line("^aces: BP_OP1032_f18e_5001 left on player 2's plane %(co%-op: a living player's%)", from) ~= nil,
          "co-op, you flying: a Reaper on player 2's plane left on it, logged once")
    e.bb.tgt = nil
    ACE.hunt(e)
    check(e.bb.tgt == pawn and e.bb.writes == 1 and tellN == 2 and has(line("^aces: BP_OP1032_f18e_5001 back onto you", from), "(was none), 1 times"),
          "... with no target: onto you as ever, the hunt tell asked each time")
    peer(1, DOWNED); tick()
    e.bb.tgt, e.bb.writes = P1, 0
    ACE.hunt(e)
    check(e.bb.tgt == pawn and e.bb.writes == 1, "player 2 down: their hidden plane isn't a living player's: onto you")
    peer(1, FLY); tick()
    -- the host DOWN
    pawn.HealthInternal = 1
    tick()
    check(DOWN.me(), "(the host down)")
    tellN, e.bb.tgt, e.bb.writes = 0, pawn, 0
    from = #logs + 1
    ACE.hunt(e)
    check(e.bb.tgt == pawn and e.bb.writes == 0 and tellN == 0
          and has(line("^aces: BP_OP1032_f18e_5001 not put back onto you: you're down", from), "your hidden plane, left as it is"),
          "down, its flight sent after nobody: never written onto your hidden plane, no hunt tell, logged")
    e.bb.tgt = nil
    ACE.hunt(e)
    check(e.bb.tgt == nil and e.bb.writes == 0, "down, no target: not put onto you either (it was, every 2 s)")
    -- (player 2's plane a real one: a target the hunts can name) its flight not sent yet: the host puts it on the living
    -- player the fewest are sent after (COOP.huntPick), as the down pass would within 5 s; not one holding its Wolf trap
    Pe.real = true
    e.bb.tgt, e.bb.writes = pawn, 0
    local rawW0 = WOLF.holding
    WOLF.holding = function(u) return u == U end
    ACE.hunt(e)
    check(e.bb.tgt == pawn and e.bb.writes == 0, "down, its flight holding its Wolf trap: left to the trap, not written")
    WOLF.holding = rawW0
    ACE.hunt(e)
    check(e.bb.tgt == P1 and e.bb.writes == 1
          and has(line("^aces: BP_OP1032_f18e_5001 onto player 2's plane", from), "you're down: the living player the fewest are sent after"),
          "down, its flight not sent after anyone yet: onto the living player the fewest are sent after (COOP.huntPick)")
    local o0, s0 = COOP.huntPick()
    check(o0 == P1 and s0 == 1, "COOP.huntPick: player 2's real plane")
    e.bb.tgt, e.bb.writes, e.huntDownN = pawn, 0, nil
    M.huntOn = { [U] = { slot = 1, gen = 3 } }       -- (the down pass sent its flight after player 2: COOP.huntReal)
    local o1, s1 = COOP.huntTarget(U)
    check(o1 == P1 and s1 == 1 and COOP.huntTarget(U2) == nil, "COOP.huntTarget: player 2's real plane for the hunted flight, nothing for another")
    e.bb.tgt = pawn
    ACE.hunt(e)
    check(e.bb.tgt == P1 and e.bb.writes == 1 and has(line("^aces: BP_OP1032_f18e_5001 onto player 2's plane", from), "you're down: its flight's hunt"),
          "down, its flight sent after player 2: its TargetActor onto player 2's plane, not back onto your hidden one")
    ACE.hunt(e)
    check(e.bb.writes == 1, "... on it already: not written again")
    M.units[U].gen = 4
    check(COOP.huntTarget(U) == nil, "COOP.huntTarget: a hunt of the flight's last generation names nothing")
    M.units[U].gen = 3
    -- the hunt tell itself: nothing said while you're down, said once you're back
    TELL.hunted = rawTell
    e.dist, D.tellHunt = 1, nil
    TELL.hunted(e)
    check(D.tellHunt == nil, "TELL.hunted: nothing said while you're down (the distance is to your hidden plane)")

    -- the down pass (sv_coop.lua, every 5 s): a flight already sent is checked by its planes' real targets (aiWatch's
    -- p.aiTargetAddr); Wolf and director holds are left to them; a flight up under 3 s waits for its arrival order
    local hunted = {}
    local rawHR, rawAny, rawOn, rawPlanes, rawW = COOP.huntReal, COOP.anyReal, COOP.realOn, planes, WOLF.holding
    COOP.realOn, COOP.anyReal = function() return true end, function() return true end
    COOP.huntReal = function(u) hunted[#hunted + 1] = u; M.huntOn = M.huntOn or {}; M.huntOn[u] = { slot = 1, gen = M.units[u].gen }; return true, 1, 1 end
    D.up = { [U] = true }
    planes = { e }
    M.huntCheckAt = clock + 1e6                     -- (the hunted players' own check left out: player 2 stays huntable)
    e.aiTargetAddr = P1.addr
    M.downHuntAt, from = 0, #logs + 1
    tick()
    check(#hunted == 0, "the down pass: a flight sent after player 2, its plane on them: left alone")
    e.aiTargetAddr = pawn.addr                      -- (the allies' hunt, a Wolf trap's release, its arrival order: "Player")
    M.downHuntAt = 0
    tick()
    check(hunted[1] == U and has(line("^coop: you're down: 1 flight %(1 planes%) sent after the other players instead", from),
          "(1 of them again: 1 plane back on your hidden plane)"),
          "... one of its planes back on your hidden plane: sent after them again (it was never checked again), logged")
    WOLF.holding = function(u) return u == U end
    hunted, M.downHuntAt = {}, 0
    tick()
    check(#hunted == 0 and line("^coop: you're down: " .. U .. " holds its Wolf trap: left to it", from) ~= nil,
          "a flight holding its Wolf trap: left to it (the order would free it), said once")
    WOLF.holding = rawW
    M.units[U2] = { gen = 5, n = 1, planes = { [1] = { id = 9002 } }, ground = {}, at = clock - 1 }
    D.up[U2], e.aiTargetAddr = true, P1.addr
    hunted, M.downHuntAt = {}, 0
    tick()
    check(#hunted == 0, "a flight up 1 s: waits for its arrival order (+2 s, which would undo this one)")
    clock, M.downHuntAt = clock + 3, 0
    tick()
    check(hunted[1] == U2, "... up 3 s: sent after the other players")
    COOP.huntReal, COOP.anyReal, COOP.realOn = rawHR, rawAny, rawOn

    -- the stats and the learning profile: the loiter isn't your flying (flow-4, joiner-8)
    CFG.stats.enabled = true
    local s = enemy(5002, U)
    s.at, s.fwd, s.dist = { X = 100000, Y = 0, Z = 250000 }, { X = 1, Y = 0, Z = 0 }, 1
    local you = { X = 0, Y = 0, Z = 250000 }         -- (1 km behind it: on its six)
    D.rs = { tailEscaped = 0 }
    STATS.track(s, you, 200)
    check(s.engagedAt == nil and s.tailAt == nil and s.youAt ~= nil and D.rs.tailEscaped == 0,
          "down: STATS.track counts no engagement or tail of your hidden plane (p.youAt kept)")
    s.tw = { t0 = 199, last = 199, st = {}, km = 1, off = 0 }
    planes = { s }
    from = #logs + 1
    STATS.tailTick(200)
    check(s.tw == nil and line("^tailed: you're down: 1 open episode dropped", from) ~= nil, "the tail watch: an open episode dropped, logged")
    RUN.habit = nil
    from = #logs + 1
    STATS.sample(200, you)
    check(RUN.habit == nil and line("^stats: you're down: your flying isn't measured", from) ~= nil,
          "STATS.sample: P6's habits not sampled (Saint Alessia's airfield habit went 0.34 -> 0.50 on her loiter), logged")
    PROF.sample(202, you)
    check(RUN.habit == nil, "PROF.sample itself: nothing while you're down")
    planes = rawPlanes
    -- back: measured again
    peer(1, AIRFIELD_F); tick()
    inbox[#inbox + 1] = "1|rv|0|5000"
    tick()
    check(not DOWN.me(), "(revived)")
    planes = { s }
    STATS.track(s, you, 210)
    check(s.engagedAt == 210 and s.tailAt == 210, "revived: STATS.track measures you again")
    STATS.sample(212, you)
    check(RUN.habit and RUN.habit.S == 1, "... and P6's habits sampled again (" .. tostring(RUN.habit and RUN.habit.S) .. ")")
    TELL.hunted(e)
    check(D.tellHunt and D.tellHunt[U] == D.round, "the hunt tell said again once you're back")
    planes = rawPlanes
    M.huntOn, M.huntCheckAt, D.rs = nil, nil, nil
    Pe.real = nil
end

print("a revive sold only to a game heard from now (board-5: Froya's, 22:19:22, 1 s into her outage)")
do
    scene("host", 0, { [1] = FLY, [2] = AIRFIELD_F })
    peer(1, DOWNED); inbox[#inbox + 1] = "1|dw|1"; tick()
    peer(1, DOWNED, 800)                             -- (fresh for the round's checks: under a second; not for a revive)
    tick()
    sent, from = {}, #logs + 1
    inbox[#inbox + 1] = "2|rv|1|5000"
    tick()
    check(msgs("rx") == "2>rx|1|THEIR LINK IS LAGGING: TRY AGAIN|0|0" and St.count == 0 and msgs("rb") == ""
          and has(line("^revive: player 3's revive of player 2 refused", from), "(their last state 800 ms old)"),
          "their last state 800 ms old: refused (refunded there), nothing counted, logged with the age (" .. msgs("rx") .. ")")
    peer(1, DOWNED, 100)
    M.lostAt[1] = { at = clock, from = clock, inMission = true }
    tick()
    sent = {}
    inbox[#inbox + 1] = "2|rv|1|5000"
    tick()
    check(msgs("rx") == "2>rx|1|THEIR LINK IS LAGGING: TRY AGAIN|0|0" and has(line("^revive: player 3's revive of player 2 refused", from), "their link is lost"),
          "their link lost (sys|lost): refused")
    M.lostAt[1] = nil
    sent = {}
    inbox[#inbox + 1] = "2|rv|1|5000"
    tick()
    check(msgs("rb") == "-1>rb|1|1|2|1" and St.count == 1, "heard from now: revived as ever")
end

print("a joiner's host lost: the floor and the run held through a host migration (Delta's log, joiner-5; board-5)")
do
    local LINKED = info
    scene("join", 1, { [0] = FLY, [2] = FLY })
    check(DOWN.floor() == 0.1 and pawn.MinHealth == 0.1, "(linked: the floor 0.1)")
    M.succ, M.hostSid = { { slot = 1, sid = "76561198000000011" }, { slot = 2, sid = "76561198000000012" } }, "76561198000000010"
    info, M.nextInfo = "open=1;state=searching;peers=", 0
    inbox[#inbox + 1] = "0|sys|lost"
    from = #logs + 1
    tick()
    check(COOP.linked() == 0 and COOP.migrating() == true and DOWN.floor() == 0.1 and pawn.MinHealth == 0.1 and DOWN.holdsRun(),
          "the host's link lost, a host migration's line to go down: the floor (0.1) and the run's hold kept (they went to 0)")
    tick()
    check(line("^down: the host's link is gone and a host migration is under way", from) ~= nil, "logged")
    pawn.HealthInternal = 1
    tick()
    check(DOWN.me() and #finished == 0, "a hit to the floor in the migration's wait: DOWN, not dead (Delta: 203 HP at 09:35:11, game over)")
    ticks(12)
    check(not St.ended and #finished == 0, "down, the host's link gone 12 s: the run held (it ended at 10 s, PENDING_S)")
    M.hostLostAt, M.mig = nil, nil                  -- (nextCandidate's end: none of the next hosts answered)
    tick()
    check(St.ended and finished[1] == "died" and line("^down: run over in round 5: .*the host migration found no host", from) ~= nil,
          "the migration found no host: the run's over then (nobody can revive you)")
    -- no migration (no line from the host): until the runtime lets the host's link go
    info, M.hostLostAt, M.mig = LINKED, nil, nil      -- (the last block's lost host forgotten: a new link's "paired" does it)
    scene("join", 1, { [0] = FLY, [2] = FLY })
    pawn.HealthInternal = 1
    tick()
    check(DOWN.me(), "(down, linked)")
    M.succ = nil
    info, M.nextInfo = "open=1;state=searching;peers=", 0
    inbox[#inbox + 1] = "0|sys|lost"
    from = #logs + 1
    ticks(30)
    check(not COOP.migrating() and not St.ended and line("^down: the host's link is gone while you're down: your run waits for it", from) ~= nil,
          "no migration: down, the host's link gone 30 s: held, logged")
    inbox[#inbox + 1] = "0|sys|left"
    tick(); tick()                                  -- (the message in this pass's co-op tick, DOWN's the next)
    check(St.ended and line("^down: run over in round 5: .*the host's gone %(its link let go", from) ~= nil, "the runtime lets it go (sys|left): over")
    info, M.hostLostAt, M.mig = LINKED, nil, nil      -- (the last block's lost host forgotten: a new link's "paired" does it)
    scene("join", 1, { [0] = FLY, [2] = FLY })
    pawn.HealthInternal = 1
    tick()
    M.succ = nil
    info, M.nextInfo = "open=1;state=searching;peers=", 0
    inbox[#inbox + 1] = "0|sys|lost"
    ticks(99)
    check(not St.ended, "nothing from the host 99 s: still held")
    ticks(2)
    check(St.ended and has(line("^down: run over in round 5"), "nothing from it"), "100 s (GONE_S): over")
    -- linked again in time: still down, waiting for a revive; the floor never off as the link comes back (Delta's was 0
    -- for 3 s after the host's "up", 09:34:53-56: the migration's clock reset by it, the link count 5 s late)
    info, M.hostLostAt, M.mig = LINKED, nil, nil      -- (the last block's lost host forgotten: a new link's "paired" does it)
    scene("join", 1, { [0] = FLY, [2] = FLY })
    M.succ, M.hostSid = { { slot = 1, sid = "76561198000000011" } }, "76561198000000010"
    pawn.HealthInternal = 1
    tick()
    info = "open=1;state=searching;peers="
    inbox[#inbox + 1] = "0|sys|lost"
    ticks(17)
    info = LINKED                                    -- (the link count refreshed by the "up" itself, not 5 s on)
    inbox[#inbox + 1] = "0|sys|up"
    from = #logs + 1
    local lowest = 1
    for _ = 1, 24 do tick(); lowest = math.min(lowest, DOWN.floor(), pawn.MinHealth) end
    check(lowest == 0.1, "the host's link back: the floor 0.1 all the while (" .. lowest .. ")")
    check(DOWN.me() and not St.ended and line("^down: the host's link back after %d+ s: still down", from) ~= nil,
          "linked again after 17 s (Froya's outage): still down, the run on, logged")
    inbox[#inbox + 1] = "0|rb|1|1|0"
    tick()
    check(not DOWN.me(), "... and the host's revive then brings you back")
    info = LINKED
end

---------------------------------------------------------------------------------------------------- the settings
print("the settings: the host's revives, each player's key and camera")
do
    local cr = CFG.coop.revive
    COOP.open, COOP.role = true, "host"
    cr.price, cr.key, cr.camera.back_m = 8000, "P", 50
    sent = {}
    M.sendSettings(1)
    local cf = {}
    for _, s in ipairs(sent) do if s:find("^1>cf|") then cf[#cf + 1] = s:sub(3) end end
    cr.price, cr.key, cr.camera.back_m = 5000, "O", 30          -- (the joiner's own)
    COOP.role = "join"
    local function split(s) local t = {}; for f in (s .. "|"):gmatch("([^|]*)|") do t[#t + 1] = f end; return t end
    for _, m in ipairs(cf) do M.onSettings(split(m)) end
    check(CFG.coop.revive == cr and cr.price == 8000, "a joiner plays with the host's price (8000), the same table")
    check(cr.key == "O" and cr.camera.back_m == 30, "its own key (O) and camera (30 m)")
    M.restoreMine()
    check(cr.price == 5000 and cr.key == "O", "co-op closed: its own price back")
end

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
do
    local sm = readAll(MOD .. "/Scripts/sv_main.lua")
    local a, b = sm:find("timed(\"floor\", INS.tick, now)", 1, true), sm:find("timed(\"down\", DOWN.tick)", 1, true)
    check(a and b and a < b, "sv_main: DOWN.tick after INS.tick (its floor)")
    check(has(sm, 'pcall(DOWN.reset, "a new level", true)') and has(sm, 'pcall(DOWN.reset, "the level was left", true)'), "sv_main: reset on a new level and a run left")
    check(has(readAll(MOD .. "/Scripts/sv_hud.lua"), "DOWN.hudLine()"), "sv_hud: the NEXT row while down")
    local sh = readAll(MOD .. "/Scripts/sv_shop.lua")
    check(has(sh, 'o.role == "revive"') and has(sh, "DOWN.buy(price)"), "sv_shop: the REVIVE row's offer and purchase")
    check(has(readAll(MOD .. "/Scripts/sv_leaderboard.lua"), "DOWN.holdsRun()"), "sv_leaderboard: the death check waits for ro in co-op")
    local ml = readAll(MOD .. "/Scripts/main.lua")
    check((ml:find('"sv_coop"', 1, true) or 0) < (ml:find('"sv_down"', 1, true) or 0) and (ml:find('"sv_down"', 1, true) or 1e9) < (ml:find('"sv_main"', 1, true) or 0),
          "main.lua: sv_down after sv_coop, before sv_main")
    local bs = readAll(MOD .. "/../../../tools/build_survival.py")
    check(has(bs, "['RepairAircraft', 'RepairAirfield', 'Revive',"), "build_survival: REVIVE on the AIRFIELD page")
    local se = readAll(MOD .. "/../../../tools/survival_events.py")
    check(has(se, "build_run_over(g, stock_ep)") and has(se, "g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_RunOver')"), "survival_events: RE_SV_RunOver")
end

print(fails == 0 and "co-op revive test: all passed" or ("co-op revive test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
