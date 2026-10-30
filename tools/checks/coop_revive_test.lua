-- coop_revive_test.lua <mod dir> <work dir> (run by tools/checks/coop_revive_test.sh): Survival COOP's revives and the
-- spectator camera (sv_down.lua, tools/re/COOP.md 9; the user, 2026-10-29: "is there a revive option we could possibly
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
--     (the STORE row's label, "(+1)", the price); the downed game's way back (loiter off, the plane as it was, repaired,
--     safe_s invincible, respawn loiter / native with SV_Respawn's pose; a plane that isn't flying, crashed into the
--     ground with its floor held, native whatever respawn says: the user's co-op run of 2026-10-30);
--   the refusals: not on the airfield, not down, a second revive, a wrong price, a bad request, another player's "dw";
--     a joiner's refund on "rx" and with no answer in 10 s; the row's CO-OP ONLY / NOBODY IS DOWN;
--   everyone down: the host's "ro" after 3 s (a player gone from the mission doesn't count), each game's run over
--     (LB.finish, RE_SV_RunOver); the death check ending nothing in co-op, the run solo as ever;
--   the host down: its own-plane events not fired here, the rest as ever; the round bonus with down_round_bonus off;
--   the settings: the host's [coop.revive] for everyone but each player's key and camera;
--   the hooks by their place in the source (sv_main, sv_hud, sv_shop, the build's STORE row and RE_SV_RunOver).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
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

local function part(name, chunk, edits)
    local src = readAll(MOD .. "/Scripts/" .. name)
    for _, e in ipairs(edits or {}) do
        local n
        src, n = src:gsub(e[1], e[2], 1)
        assert(n == 1, name .. ": " .. e[1] .. " not found")
    end
    assert(load(src, chunk or ("=" .. name)))()
end
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
-- (the user, 2026-10-30: "lower the cost for reviving": 2500, x1.25 a revive, was 5000 x1.5)
do
    local cr = CFG.coop.revive
    check(cr.price == 2500 and cr.raise == 1.25, "shipped: 2500 a revive, x1.25 for each one in the run (" .. tostring(cr.price) .. " x" .. tostring(cr.raise) .. ")")
    local p = {}
    for n = 0, 2 do p[#p + 1] = math.floor(cr.price * cr.raise ^ n / 10 + 0.5) * 10 end
    check(table.concat(p, " ") == "2500 3130 3910", "the run's first three: " .. table.concat(p, " "))
    cr.price, cr.raise = 5000, 1.5         -- (the checks below were written for 5000 x1.5: the logic is the same)
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
check(msgs("rb") == "-1>rb|1|1|2" and St.count == 1 and callout("B BACK"), "player 3 at their airfield revives player 2: rb|1|1|2 to everyone, the count 1")
sent = {}
inbox[#inbox + 1] = "2|rv|1|7500"
tick()
check(msgs("rx") == "2>rx|1|ALREADY BEING REVIVED|1", "a second revive within 15 s: refused (" .. msgs("rx") .. ")")
sent = {}
clock = clock + 16
inbox[#inbox + 1] = "2|rv|1|5000"
tick()
check(msgs("rx") == "2>rx|1|THE PRICE CHANGED: NOW 7500|1", "the old price: refused, the new one said")
sent = {}
peer(2, FLY)
tick()
inbox[#inbox + 1] = "2|rv|1|7500"
tick()
check(msgs("rx") == "2>rx|1|NOT AT THE AIRFIELD|1", "the reviver not at the airfield: refused")
sent = {}
peer(1, FLY); peer(2, AIRFIELD_F)
tick()
inbox[#inbox + 1] = "2|rv|1|7500"
inbox[#inbox + 1] = "2|rv|x|7500"
inbox[#inbox + 1] = "1|dw|2"
tick()
check(msgs("rx") == "2>rx|1|NOT DOWN|1 2>rx|x|A BAD REQUEST", "not down; a bad request (" .. msgs("rx") .. ")")
check(msgs("dw") == "" and line("revive: player 2 said another player is down; ignored", from) ~= nil, "a dw for another slot: ignored")

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
check(ok and why == "REVIVED B." and msgs("rb") == "-1>rb|1|1|0", "at the airfield: REVIVED B., rb|1|1|0")
peer(1, FLY); tick()
o = DOWN.offer()
check(o.label == "REVIVE C" and o.price == 7500, "then REVIVE C at 7500 (x1.5)")
ok, why = DOWN.buy(5000)
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
pawn.at = nil
-- its revives of another player
sent = {}
peer(2, DOWNED); tick()
o = DOWN.offer()
check(o.label == "REVIVE C" and o.price == 5000 * 1.5 * 1.5, "player 3 down: REVIVE C at the room's count 2: 11250 (" .. tostring(o.price) .. ")")
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
inbox[#inbox + 1] = "0|rb|2|3|1"
tick()
check(RUN.credits == 8750 and RUN.msg.Revive == "REVIVED C." and St.count == 3 and callout("C BACK"), "rb by you: paid, REVIVED C., the count 3")
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
check(msgs("rb") == "-1>rb|0|1|1" and St.count == 1 and line("^revive: player 2 revived player 1 for 5000", from) ~= nil
      and callout("BACK IN THE FIGHT"), "rb|0|1|1 to everyone, the room's count 1, logged, called out (" .. msgs("rb") .. ")")
check(pawn.HealthInternal == 1000 and events[#events] == "RE_SV_RepairAircraft", "repaired")
peer(1, FLY)
pawn.HealthInternal = 1
tick()
sent = {}
inbox[#inbox + 1] = "1|rv|0|7500"
tick()
check(DOWN.me() and msgs("rx") == "1>rx|0|NOT AT THE AIRFIELD|1", "down again, the joiner flying: refused, told why (" .. msgs("rx") .. ")")
peer(1, AIRFIELD_F)
tick()                                            -- (their landed state in first)
sent = {}
inbox[#inbox + 1] = "1|rv|0|7500"
tick()
check(not DOWN.me() and msgs("rb") == "-1>rb|0|2|1", "down again within 15 s of the last revive, the joiner landed: revived again ("
      .. msgs("rb") .. msgs("rx") .. ")")

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
