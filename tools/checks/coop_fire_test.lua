-- coop_fire_test.lua <mod dir> <work dir> (run by tools/checks/coop_fire_test.sh): Survival COOP's weapon, gear and
-- afterburner sync (sv_coop.lua's sync, tools/re/COOP.md 8; the user, 2026-10-29: "can you please work out aircraft
-- syncing, such as missiles being fired", "their gear doesn't deploy on my screen, nor do I see their afterburners"), on
-- the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_rounds, sv_tactical, sv_stats, sv_tells,
-- sv_director and sv_coop (M exposed), the game and the runtime (SV_CoopFire, SV_InputNow, SV_Ammo, ...) stubbed:
--   detection: your missiles in flight (FiredExplosiveWeapons: an address that wasn't there last tick is a shot; the
--     first read after your plane changes only learns; a pooled one coming back is a shot again), their kind by class
--     (the gun's and the flares' never sent), their target's stream id (the host's own enemy; a joiner's copy of it);
--   the "fx" batch: one message a tick, the host's to every joiner as slot 0, a joiner's to the host;
--   the host: a joiner's shots fired from its plane here at the target here, relayed to the other joiners and never
--     back, the ages grown by the link's half round trip;
--   the guards: a slot that isn't another player's, more than 12 shots a second, more than 32 entries a message, stale
--     shots, a shooter whose state is over a second old, unreadable entries, ids not known here (fired with no target),
--     no plane of theirs here;
--   your state bits: gear (16), afterburner (32, ab_throttle), gun (64, read before the refill, held 0.5 s), flares
--     (128), none on the airfield;
--   the others' bits: a gear flip calls EnableLandingGear, the gun fires every 0.2 s at its target ("g"), flares on the
--     rising edge and every second held; nothing from a state gone stale;
--   the stand-ins' damage-0 rows (COOP.syncSetup) and flying them (M.flyRow) in a level loaded after;
--   the joiner's backstop: a stand-in's damage on a copy taken out of what goes to the host ("ht");
--   (0.73.80) the weapon stand-ins: a launch whose weapon another player's real plane here hasn't, or has as another
--     kind, shown as the nearest weapon of its kind it has (M.weaponFor, M.standInPay; SV_PPWeapons stubbed), never a
--     number it hasn't, the relay as sent, standins = false as before;
--   sync off: nothing sent or shown, the airframes' own rows;
--   the hooks by their place in the source.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world and the runtime, stubbed
VERSION = "0.72.1-fire.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance" }
local objects = {}                                -- StaticFindObject's world: the data tables by path
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject(p) return objects[p] end
local grounded = false
function playerOnAirfield() return grounded end
function airfieldTick() end
function bombTick() end
function SV_Event() return 1 end
function SV_UnitAlive() return 0 end
local setAc = {}
function SV_SetAircraft(unit, row) setAc[#setAc + 1] = unit .. "=" .. tostring(row); return 1 end
function SV_SetLevel() return 1 end
function SV_Spawn() return 1 end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
local sent, inbox = {}, {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/b,2/linked/60/10/c" end
local meFlags = 0
function SV_CoopMe(_, flags) meFlags = flags or 0 end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
local peerState = {}
function SV_CoopPeerAt(slot) return peerState[slot] or "" end
local fires, fireR = {}, 1
function SV_CoopFire(a, fcs, t) fires[#fires + 1] = string.format("%d/%d/%d", a, fcs, t or -1); return fireR end
local ammo = { [0] = 1000, 30, 4, 4, 30 }
function SV_Ammo(k) return ammo[k] or -1 end
local input = "0,0,0,500,0,0"
function SV_InputNow() return input end
local target = 0
function SV_PlayerTarget() return target end
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
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_tactical.lua"); part("sv_stats.lua"); part("sv_tells.lua"); part("sv_director.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" } })
local M = _G.M
function playerOnAirfield() return grounded end
function gamePaused() return false end
LB.stat, LB.special = function() end, function() end
presetName = function() return "standard", 3 end
math.randomseed(5)

local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function line(pat, from) for i = #logs, from or 1, -1 do if logs[i]:find(pat) then return logs[i] end end return nil end
local function fx(to)                             -- the "fx" messages sent (to: a slot's, "-1" every one / the host)
    local t = {}
    for _, s in ipairs(sent) do if s:find("^[-%d]+>fx|") and (not to or s:find("^" .. to:gsub("%-", "%%-") .. ">")) then t[#t + 1] = s end end
    return table.concat(t, " ")
end
local function fired() return table.concat(fires, " ") end

-- the scene: your plane, the enemies (by stream id: the host's own, a joiner's copies), the other players' planes
local LEVEL = " /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel."
local function arrOf(list)
    return { ForEach = function(_, fn) for i, w in ipairs(list) do fn(i, { get = function() return w end }) end end }
end
local gear = { addr = 90, vis = false }
function gear:IsVisible() return self.vis end
local pawn = { full = "BP_PlayerPlane_PP1000_f16c_C" .. LEVEL .. "BP_PlayerPlane_PP1000_f16c_C_1", addr = 9, MaxHealth = 100,
               HealthInternal = 800, LandingGearOnMesh = gear }
function pawn:K2_GetActorLocation() return { X = 0, Y = 0, Z = 300000 } end
function pawn:GetAddress() return self.addr end
local inFlight = {}
setmetatable(pawn, { __index = function(_, k) if k == "FiredExplosiveWeapons" then return arrOf(inFlight) end end })
survivalPC = { Pawn = pawn }
local function msl(addr, cls, tgt) return { full = cls .. " /Engine/Transient.Pool_" .. addr, addr = addr, TargetToHome = tgt } end
local E5 = { full = "BP_OP0001_f16c_C" .. LEVEL .. "E5", addr = 505, HealthInternal = 1000 }
local E6 = { full = "BP_OP0001_f16c_C" .. LEVEL .. "E6", addr = 606, HealthInternal = 0 }
local function plane(addr, name)
    local p = { full = "BP_NPC_f16c_C" .. LEVEL .. name, addr = addr, gearCalls = {} }
    function p:EnableLandingGear(down, t) self.gearCalls[#self.gearCalls + 1] = tostring(down) .. "/" .. tostring(t) end
    function p:GetAddress() return self.addr end
    return p
end
-- player N's state as the runtime reports it (flags: 1 in the level, 2 alive, 16 gear, 64 gun, 128 flares; age ms)
local function peer(slot, flags, age) peerState[slot] = string.format("100000,0,300000,0,0,0,800,100,%d,%d", flags, age or 100) end
local function room(role, slot)
    CFG.coop.enabled = true
    COOP.open, COOP.role, COOP.slot = true, role, slot
end
local function tick(dt, refill)                  -- one Lua pass: ammoRead before ammoTick (its refill), then COOP.tick
    clock = clock + (dt or 0.25)
    COOP.ammoRead()
    if refill then for k, v in pairs(refill) do ammo[k] = v end end
    COOP.tick(0)
end
local function fresh(role, slot)                 -- a new level for `role`: the scene above, nothing sent or fired yet
    room(role, slot)
    D = { round = 5, state = "spawning", now = 99, at = 0, up = {}, flown = {}, queue = {}, spare = {}, events = {},
          orders = {}, pressure = "B", wave = 1 }
    inFlight, sent, fires, inbox, setAc = {}, {}, {}, {}, {}
    grounded, target, input, gear.vis = false, 0, "0,0,0,500,0,0", false
    ammo = { [0] = 1000, 30, 4, 4, 30 }
    for s = 0, 23 do peerState[s] = nil end
    M.nextInfo = 0
    tick()                                        -- (the new level's reset: M.byId, M.copies, the stand-ins kept)
    M.roster = { [0] = { row = "f16c_common", ver = VERSION, name = "A" }, [1] = { row = "f16c_common", ver = VERSION, name = "B" },
                 [2] = { row = "f16c_common", ver = VERSION, name = "C" } }
    sent, fires = {}, {}
end
local P0, P1, P2 = plane(1000, "SV_Peer0"), plane(1001, "SV_Peer1"), plane(1002, "SV_Peer2")

---------------------------------------------------------------------------------------------------- detection (host)
print("your missiles: detection and the fx batch (host)")
fresh("host", 0)
M.byId[5] = { obj = E5, unit = "ERA_Unit_01_Dep_Air0", ord = 1, addr = 505 }
M.byId[6] = { obj = E6, unit = "ERA_Unit_01_Dep_Air0", ord = 2, addr = 606, dead = true }
M.linkedPeers = 2
local A = msl(7001, "BP_plwp_msl_f16c_C", E5)
inFlight = { A }
pawn.addr = 10                                   -- (a new plane: its first read)
tick()
check(fx() == "", "the first read after your plane changes only learns (a missile already up isn't sent)")
local B = msl(7002, "BP_plwp_msl_f16c_C", E5)
inFlight = { A, B }
tick()
check(fx() == "-1>fx|0|m:5:0", "a new missile at enemy 5: one fx to every joiner as slot 0 (" .. fx() .. ")")
sent = {}
local C = msl(7003, "BP_plwp_lasm_f16c_C", nil)
local D6 = msl(7004, "BP_plwp_msl_f16c_C", E6)
local G = msl(7005, "BP_plwp_gun_f16c_C", E5)
inFlight = { A, B, C, D6, G }
tick()
check(fx() == "-1>fx|0|s:0:0;m:0:0", "a tick's shots in one message: a special weapon (no target), a missile at a dead enemy (id 0), the gun's never (" .. fx() .. ")")
check(line("coopfire: your weapon BP_plwp_lasm_f16c_C: a special weapon") ~= nil and line("coopfire: your weapon BP_plwp_gun_f16c_C: not sent") ~= nil,
      "each class's kind logged once")
sent = {}
inFlight = { A, C, D6, G }
tick()
inFlight = { A, B, C, D6, G }
tick()
check(fx() == "-1>fx|0|m:5:0", "a pooled missile gone and back is a new shot")
sent = {}
M.linkedPeers = 0
inFlight = { A, B, C, D6, G, msl(7006, "BP_plwp_msl_f16c_C", E5) }
tick()
check(fx() == "", "nobody linked: nothing sent")
M.linkedPeers = 2

---------------------------------------------------------------------------------------------------- the host receives
print("the host: a joiner's shots fired and relayed")
fresh("host", 0)
M.byId[5] = { obj = E5, unit = "ERA_Unit_01_Dep_Air0", ord = 1, addr = 505 }
COOP.peerPlane(P1, 1); COOP.peerPlane(P2, 2)
peer(1, 3); peer(2, 3)
tick()
local from = #logs + 1
inbox[#inbox + 1] = "1|fx|m:5:0;s:0:0;m:99:30"
tick()
check(fired() == "1001/2/505 1001/2/0 1001/2/0", "player 2's plane here fires each: at enemy 5, at none, at none for an unknown id (" .. fired() .. ")")
check(fx() == "2>fx|1|m:5:20;s:0:20;m:99:50", "relayed to player 3 only, ages + half the 40 ms round trip (" .. fx() .. ")")
check(since(from, "^coopfire: player 2's first missiles here") == 1, "the first shot received from player 2 logged once")
fires, sent = {}, {}
inbox[#inbox + 1] = "0|fx|m:5:0"
tick()
check(fired() == "" and fx() == "" and line("coopfire: shots from a slot that isn't another player's dropped", from) ~= nil,
      "\"fx\" from your own slot: dropped (logged)")

print("the guards")
fresh("host", 0)
M.byId[5] = { obj = E5, unit = "ERA_Unit_01_Dep_Air0", ord = 1, addr = 505 }
COOP.peerPlane(P1, 1); COOP.peerPlane(P2, 2)
peer(1, 3); peer(2, 3)
tick()
from = #logs + 1
local t13 = {}
for i = 1, 13 do t13[i] = "m:5:0" end
inbox[#inbox + 1] = "1|fx|" .. table.concat(t13, ";")
tick()
check(#fires == 12 and line("coopfire: player 2's shots dropped: 1 over 12 a second", from) ~= nil, "13 shots in a second: 12 fired, 1 dropped (logged)")
fires, sent = {}, {}
tick(1.1)
local t40 = {}
for i = 1, 40 do t40[i] = "g:5:0" end
inbox[#inbox + 1] = "1|fx|" .. table.concat(t40, ";")
tick()
local relayed = select(2, fx("2"):gsub("g:5:", ""))
check(#fires == 0 and relayed == 32 and line("coopfire: player 2's shots dropped: 8 more than 32 in a message", from) ~= nil,
      "40 entries: 32 taken, 8 dropped; gun-target entries fire nothing (" .. relayed .. " relayed)")
fires, sent = {}, {}
tick(1.1)
inbox[#inbox + 1] = "1|fx|m:5:1490;m:5:1400;x:1:2;m:abc:0;m:5:0:9"
tick()
check(fired() == "1001/2/505" and line("player 2's shots dropped: 1 stale", from) ~= nil and line("player 2's shots dropped: 3 unreadable", from) ~= nil,
      "1490 ms old + 20 ms: stale, 1400: fired, 3 unreadable dropped (" .. fired() .. ")")
fires, sent = {}, {}
peer(1, 3, 1500)
tick(1.1)
inbox[#inbox + 1] = "1|fx|m:5:0"
tick()
check(fired() == "", "player 2's state over a second old: their shots dropped as stale")
peer(1, 3)
-- your landing STORE open (D.musicHold): the game refuses the other planes' fire there, so it isn't asked (the co-op run
-- of 2026-10-30: 1,093 of its 1,094 refused shots came while that game's player was in the STORE)
fires, sent = {}, {}
tick(1.1)
D.musicHold = 1
inbox[#inbox + 1] = "1|fx|m:5:0;m:5:0"
tick()
D.musicHold = 0
local tallyAt = #logs + 1
for _ = 1, 62 do tick(1) end
local tally = line("^coopfire: 60 s:", tallyAt)
check(fired() == "" and has(tally, "2 not shown: you were in the STORE"),
      "your STORE open: their 2 shots not asked of the game, counted in the minute's line (" .. tostring(tally) .. ")")
fires, sent = {}, {}
P1.gone = true
tick()
inbox[#inbox + 1] = "1|fx|m:5:0"
tick()
check(fired() == "" and fx("2") ~= "", "no plane of player 2's here: nothing fired, still relayed to player 3")
P1.gone = nil
COOP.peerPlane(P1, 1)
fireR = -11
fires, sent = {}, {}
tick(1.1)
inbox[#inbox + 1] = "1|fx|m:5:0"
tick()
check(line("coopfire: SV_CoopFire%(player 2's plane, slot 2%) refused: %-11 the game refused it", from) ~= nil,
      "SV_CoopFire's refusal logged with its code and SV_ERR's words")
fireR = 1

---------------------------------------------------------------------------------------------------- electronic specials
-- (the user's co-op run of 2026-10-30: "EA-18G player used his ESM and it didn't show up for any of us": an ESM fires no
-- projectile, so FiredExplosiveWeapons never had it)
print("an electronic special (ESM): sent as e, the stand-in's ECM pod fired")
fresh("host", 0)
M.linkedPeers = 2
pawn.addr = 11
inFlight = {}
tick()                                            -- (the first read: primed)
sent = {}
ammo[2] = 3                                       -- special 1 used, nothing in flight
tick(); tick()
check(fx() == "", "not yet: 0.25 s after the drop it could still be a projectile's (" .. fx() .. ")")
tick()
check(fx() == "-1>fx|0|e:0:500", "nothing in flight 0.5 s after special 1 went down: e, 500 ms old, to every joiner (" .. fx() .. ")")
check(line("coopfire: your special weapon went off with nothing in flight") ~= nil, "logged once")
sent = {}
ammo[2] = 2
inFlight = { msl(7101, "BP_plwp_lasm_f16c_C", nil) }
tick(); tick(); tick()
check(fx() == "-1>fx|0|s:0:0", "a special weapon in flight as its count went down: s only, no e (" .. fx() .. ")")
sent = {}
grounded = true
ammo[3] = 0
tick(); tick(); tick()
grounded = false
check(fx() == "", "special 2 down on the airfield (a rearm or a change): nothing")
-- shown: the host gets player 2's e, fires their EA-18G stand-in's ECM pod (slot 3), relays it to player 3
fresh("host", 0)
COOP.peerPlane(P1, 1); COOP.peerPlane(P2, 2)
peer(1, 3); peer(2, 3)
tick()
M.peers[1].row = "e18g_common"
M.ecmSlot.e18g_common = 3                         -- (as COOP.syncSetup records the pod it adds: the rows' test below)
local fromE = #logs + 1
inbox[#inbox + 1] = "1|fx|e:0:0"
tick()
check(fired() == "1001/3/0" and fx() == "2>fx|1|e:0:20", "player 2's ESM: their EA-18G here fires its ECM pod (slot 3, no target), relayed to player 3 ("
      .. fired() .. ", " .. fx() .. ")")
check(line("coopfire: player 2's first ECM pod here", fromE) ~= nil, "its first ECM pod logged")
fires, sent = {}, {}
tick(1.1)
M.peers[1].row = "f16c_common"
inbox[#inbox + 1] = "1|fx|e:0:0"
tick()
check(fired() == "" and line("coopfire: player 2's electronic special: their plane here %(f16c_common%) has no ECM pod", fromE) ~= nil,
      "an airframe with no ECM pod: nothing fired, logged once")
fires, sent = {}, {}

---------------------------------------------------------------------------------------------------- a joiner
print("a joiner: the host's and the others' shots, its own")
fresh("join", 1)
M.copies[7] = { obj = { full = "BP_OP0001_f16c_C" .. LEVEL .. "C7", addr = 707, HealthInternal = 1000 }, exp = 1000, addr = 707 }
COOP.peerPlane(P0, 0); COOP.peerPlane(P2, 2)
peer(0, 3); peer(2, 3)
M.linkedPeers = 1
tick()
from = #logs + 1
inbox[#inbox + 1] = "0|fx|0|m:7:0"
inbox[#inbox + 1] = "0|fx|2|s:7:25;m:8:0"
tick()
check(fired() == "1000/2/707 1002/2/707 1002/2/0", "the host's shot from its plane, player 3's relayed from theirs, at copy 7 (an unknown id: none) (" .. fired() .. ")")
fires = {}
inbox[#inbox + 1] = "0|fx|99|m:7:0"
inbox[#inbox + 1] = "0|fx|1|m:7:0"
tick()
check(fired() == "", "slot 99, and your own slot: dropped")
sent = {}
inbox = {}
local J = msl(8001, "BP_plwp_msl_f16c_C", M.copies[7].obj)
inFlight = {}
tick()
inFlight = { J }
tick()
check(fx() == "-1>fx|m:7:0", "your missile at copy 7 goes to the host as \"fx|m:7:0\" (" .. fx() .. ")")

---------------------------------------------------------------------------------------------------- your state bits
print("your state bits")
fresh("host", 0)
local function bitOn(b) return math.floor(meFlags / b) % 2 == 1 end
gear.vis = true
tick()
check(bitOn(16), "gear shown: bit 16")
gear.vis = false
tick()
check(not bitOn(16), "gear hidden: no bit 16")
input = "0,0,0,950,0,0"
tick()
check(bitOn(32), "throttle 0.95: afterburner bit 32")
input = "0,0,0,850,0,0"
tick()
check(not bitOn(32), "throttle 0.85: none (ab_throttle 0.9)")
CFG.coop.sync.ab_throttle = 0.8
tick()
check(bitOn(32), "ab_throttle 0.8: bit 32 at 0.85")
CFG.coop.sync.ab_throttle = 0.9
ammo[0] = 950
tick()
check(bitOn(64), "the gun's count dropped: bit 64")
tick()
check(bitOn(64), "... held 0.5 s")
tick(0.5)
check(not bitOn(64), "... then off")
ammo[0] = 900
tick(0.25, { [0] = 1000 })                         -- (Survival's refill after the read)
check(bitOn(64), "a drop read before the refill counts")
tick(0.75)
check(not bitOn(64), "the refill alone (900 -> 1000) is no fire")
ammo[0] = 980
tick()
check(bitOn(64), "fire after the refill counts against the refilled count (1000 -> 980)")
tick(0.75)
ammo[4] = 28
tick()
check(bitOn(128), "flares dropped: bit 128")
tick(0.75)
grounded = true
ammo[0], ammo[4] = 500, 20
tick()
check(not bitOn(64) and not bitOn(128), "on the airfield: a drop is a rearm, no bits")
grounded = false

---------------------------------------------------------------------------------------------------- the others' bits
print("the others' state bits on their planes here")
fresh("host", 0)
M.byId[5] = { obj = E5, unit = "ERA_Unit_01_Dep_Air0", ord = 1, addr = 505 }
P1.gearCalls = {}
COOP.peerPlane(P1, 1)
peer(1, 3)
tick()
check(#P1.gearCalls == 0, "a new plane seen gear up: nothing to call")
peer(1, 3 + 16)
tick()
check(table.concat(P1.gearCalls, " ") == "true/1.0", "gear down: EnableLandingGear(true, 1.0)")
peer(1, 3)
tick()
check(table.concat(P1.gearCalls, " ") == "true/1.0 false/1.0", "gear up: EnableLandingGear(false, 1.0)")
P2.gearCalls = {}
COOP.peerPlane(P2, 2)
peer(2, 3 + 16)
tick()
check(table.concat(P2.gearCalls, " ") == "true/1.0", "a new plane seen gear down: EnableLandingGear(true, 1.0) at once")
fires = {}
inbox[#inbox + 1] = "1|fx|g:5:0"
peer(1, 3 + 64)
tick()
tick()
tick()
check(fired() == "1001/1/505 1001/1/505 1001/1/505", "the gun firing: player 2's plane's gun at their target (\"g\"), every pass (" .. fired() .. ")")
fires = {}
peer(1, 3 + 128)
tick()
tick()
tick(0.5)
check(fired() == "1001/0/0", "flares: fired as the bit comes on, once while held under a second (" .. fired() .. ")")
tick(0.6)
check(fired() == "1001/0/0 1001/0/0", "... again after a second held")
peer(1, 3)
tick()
peer(1, 3 + 128)
tick()
check(fired() == "1001/0/0 1001/0/0 1001/0/0", "... off and on again: fired again")
fires = {}
peer(1, 3 + 64 + 128 + 16, 5000)
tick()
check(fired() == "", "their state 5 s old: nothing shown")

---------------------------------------------------------------------------------------------------- the damage-0 rows
print("the stand-ins' damage-0 rows")
local function DT(name, rows)
    local t = { full = name, rows = rows }
    function t:FindRow(n) return self.rows[n] end
    function t:AddRow(n, r) local c = {}; for k, v in pairs(r) do c[k] = v end; self.rows[n] = c end
    function t:RemoveRow(n) self.rows[n] = nil end
    return t
end
local function npcRow(fcs) local r = {}; for i = 0, 5 do r["NpcFCSId" .. i] = FName(fcs[i] or "None") end; return r end
local mission = DT("DT_SV_NpcMission", { f16c_common = { NpcId = FName("OP_f16c") }, f16c_common_svcp = { NpcId = FName("OP_f16c_SVCP") },
                                         su57_common = { NpcId = FName("OP_su57") },
                                         e18g_common = { NpcId = FName("OP_e18g") }, e18g_common_svcp = { NpcId = FName("OP_e18g_SVCP") } })
local npc = DT("DT_NPC", { OP_f16c = npcRow({ [0] = "FCS_Flr", "FCS_Gun", "FCS_Msl", nil, "FCS_Bad" }),
                           OP_e18g = npcRow({ [0] = "FCS_Flr", "FCS_Gun", "FCS_Msl" }) })
local fcs = DT("DT_NPC_FCS", { FCS_Flr = { NpcWeaponId = FName("W_Flr") }, FCS_Gun = { NpcWeaponId = FName("W_Gun") },
                               FCS_Msl = { NpcWeaponId = FName("W_Msl") }, FCS_Bad = { NpcWeaponId = FName("W_Missing") } })
local wpn = DT("DT_NPC_Weapon", { W_Flr = { damage = 0, AreaOfEffectDamage = 0 }, W_Gun = { damage = 7, AreaOfEffectDamage = 0 },
                                  W_Msl = { damage = 60, AreaOfEffectDamage = 20 } })
objects[PROBE_TABLES[2].path], objects[FCS_TABLE], objects[WEAPON_TABLE] = npc, fcs, wpn
objects["/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"] = mission
M.svcpDone, M.svcpReady, M.ecmSlot = nil, nil, {}
from = #logs + 1
COOP.syncSetup()
-- (the EA-18G's plain campaign row has no ECM pod: its copy gets the stock one in its first free slot, for the ESM)
local ce = npc.rows.OP_e18g_SVCP
check(ce ~= nil and ce.NpcFCSId3:ToString() == "NPC_FCS_ECM000" and ce.NpcFCSId2:ToString() == "FCS_Msl_SVCP" and M.ecmSlot.e18g_common == 3
      and npc.rows.OP_e18g.NpcFCSId3:ToString() == "None" and has(line("^coopfire: the stand%-ins' damage%-0 rows", from), "e18g_common slot 3 (added)"),
      "the EA-18G's copy: the ECM pod added in slot 3 (recorded, logged), the game's own row untouched")
-- every player plane of AC8 (BP_PlayerPlane_PPnnnn_<code>, build/research) on a stand-in row of its own, but the ADFX-02
-- (no AI plane of it): the user, 2026-10-30, "someone who was flying the FA-36 was registering as flying the F-16"
do
    local codes = { "a10c", "f02a", "f04e", "f15c", "f22a", "f35c", "f18c", "j39e", "su34", "e18g", "typn", "f15j", "a06e",
                    "rflm", "su25", "x40a", "mr2k", "fa36", "ea36", "m29a", "su57", "f16c", "f14d", "f18f", "f15e", "su47",
                    "m21b", "su35", "m31b", "su33", "e06b", "f18e", "f14a" }
    local missing = {}
    for _, c in ipairs(codes) do if not CFG.coop.airframes[c] then missing[#missing + 1] = c end end
    check(#missing == 0 and CFG.coop.airframes.fa36 == "fa36_common" and CFG.coop.airframes.adfx02 == nil,
          "every player plane but the ADFX-02 has its own stand-in row; the FA-36 fa36_common (missing: " .. table.concat(missing, " ") .. ")")
    -- (COOP2MP: every player plane's own blueprint, the ADFX-02's with its variant suffix)
    local noPath = {}
    for _, c in ipairs(codes) do if not COOP.planeClassPath(c) then noPath[#noPath + 1] = c end end
    check(#noPath == 0 and COOP.planeClassPath("adfx02") ==
          "/Game/Blueprints/Vehicle/PLAYER/Plane/PP0038_adfx02_L001/BP_PlayerPlane_PP0038_adfx02_L001.BP_PlayerPlane_PP0038_adfx02_L001_C"
          and COOP.planeClassPath("nope") == nil, "every player plane's blueprint path, the ADFX-02's L001 (none for: " .. table.concat(noPath, " ") .. ")")
end
local cp = npc.rows.OP_f16c_SVCP
check(cp ~= nil and cp.NpcFCSId2:ToString() == "FCS_Msl_SVCP" and cp.NpcFCSId1:ToString() == "FCS_Gun_SVCP"
      and cp.NpcFCSId4:ToString() == "None" and cp.NpcFCSId3:ToString() == "None",
      "OP_f16c_SVCP: each slot on its _SVCP fire control, the one whose weapon can't be made harmless emptied")
check(fcs.rows.FCS_Msl_SVCP.NpcWeaponId:ToString() == "W_Msl_SVCP" and wpn.rows.W_Msl_SVCP.damage == 0
      and wpn.rows.W_Msl_SVCP.AreaOfEffectDamage == 0 and wpn.rows.W_Gun_SVCP.damage == 0,
      "their weapons: damage 0, AreaOfEffectDamage 0")
check(wpn.rows.W_Msl.damage == 60 and npc.rows.OP_f16c.NpcFCSId2:ToString() == "FCS_Msl", "the game's own rows untouched")
check(M.svcpReady.f16c_common == "f16c_common_svcp" and M.svcpReady.su57_common == nil, "f16c_common's made, su57_common's not (no mission row)")
check(has(line("^coopfire: the stand%-ins' damage%-0 rows", from), "weapons left off: OP_f16c_SVCP slot 4 (FCS_Bad)")
      and has(line("^coopfire: the stand%-ins' damage%-0 rows", from), "su57_common (no mission row su57_common_svcp"), "logged: the slot left off, the rows not made")
check(M.flyRow("f16c_common") == "f16c_common", "a level loaded before they were made: the airframe's own row")
fresh("host", 0)
check(M.flyRow("f16c_common") == "f16c_common_svcp" and M.flyRow("su57_common") == "su57_common", "a level loaded after: its _svcp row (where made)")
M.peers[2] = {}
peer(2, 3)
for _ = 1, 30 do tick() end
check(has(table.concat(setAc, " "), "SV_Unit_CoopPeerC=f16c_common_svcp"), "player 3's plane spawns on f16c_common_svcp (" .. table.concat(setAc, " ") .. ")")
CFG.coop.sync.enabled = false
check(M.flyRow("f16c_common") == "f16c_common", "sync off: the airframe's own row")
CFG.coop.sync.enabled = true

---------------------------------------------------------------------------------------------------- the backstop
print("a joiner's backstop: a stand-in's damage on a copy never goes to the host")
fresh("join", 1)
COOP.peerPlane(P0, 0); COOP.peerPlane(P2, 2)
peer(0, 3); peer(2, 3)
local hist = {}
local C7 = { full = "BP_OP0001_f16c_C" .. LEVEL .. "C7", addr = 707, HealthInternal = 1000 }
C7.DamageHistoryMap = { ForEach = function(_, fn)
    for k, v in pairs(hist) do fn({ get = function() return k end }, { get = function() return v end }) end
end }
M.copies[7] = { obj = C7, exp = 1000, addr = 707 }
tick()
sent = {}
from = #logs + 1
C7.HealthInternal, hist[P0], hist[pawn] = 800, 5.0, 15.0
tick()
local ht = {}
for _, s in ipairs(sent) do if s:find(">ht|") then ht[#ht + 1] = s end end
check(table.concat(ht, " ") == "-1>ht|7|15.0", "200 lost, 50 of it the host's plane's here: 15.0 sent (" .. table.concat(ht, " ") .. ")")
check(line("coopfire: copy 7 lost 20.0, 5.0 of it another player's stand%-in's here: 15.0 sent", from) ~= nil, "logged")
sent = {}
C7.HealthInternal = 700
tick()
ht = {}
for _, s in ipairs(sent) do if s:find(">ht|") then ht[#ht + 1] = s end end
check(table.concat(ht, " ") == "-1>ht|7|10.0", "the next hit, no stand-in's: all of it sent (" .. table.concat(ht, " ") .. ")")

---------------------------------------------------------------------------------------------------- COOP2MP T4b
print("COOP2MP T4b: launches on the other players' real planes (\"p\"), loadouts in hi / pi")
local shotsOut, ppShots, ppR, loadout, paint = "", {}, 1, "", ""
function SV_CoopShots() local s = shotsOut; shotsOut = ""; return s end
function SV_CoopPPShot(a, t, pay) ppShots[#ppShots + 1] = string.format("%d/%d/%s", a, t, pay); return ppR end
function SV_CoopLoadout() return loadout end
local PAY = "0,1,0,0,96,2,10,-5,0,-15,1800,0,100,-20,0"
-- your launches: each as "p:<target's stream id>:0:<shot>" in the tick's fx, beside the stand-ins' m / s
fresh("host", 0)
M.byId[5] = { obj = E5, unit = "ERA_Unit_01_Dep_Air0", ord = 1, addr = 505 }
M.linkedPeers = 2
pawn.addr = 11
tick()
inFlight = { msl(7101, "BP_plwp_msl_f16c_C", E5) }
shotsOut = PAY .. ",505;3,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
tick()
check(fx() == "-1>fx|0|m:5:0;p:5:0:" .. PAY .. ";p:0:0:3,3,0,0,0,0,0,0,0,0,0,0,0,0,0",
      "your launches out as p entries (target 505 = enemy 5, none = 0) beside the stand-ins' m (" .. fx() .. ")")
-- the host: a joiner's p replayed on their real plane here, m not fired from it, both relayed
fresh("host", 0)
M.byId[5] = { obj = E5, unit = "ERA_Unit_01_Dep_Air0", ord = 1, addr = 505 }
COOP.peerPlane(P1, 1); COOP.peerPlane(P2, 2)
peer(1, 3); peer(2, 3)
tick()
M.peers[1].real = true
ppShots = {}
local from = #logs + 1
inbox[#inbox + 1] = "1|fx|m:5:0;p:5:0:" .. PAY
tick()
check(table.concat(ppShots, " ") == "1001/505/" .. PAY, "their launch replayed on their real plane here at enemy 5 (" .. table.concat(ppShots, " ") .. ")")
check(fired() == "", "their m isn't fired from a real plane (" .. fired() .. ")")
check(fx() == "2>fx|1|m:5:20;p:5:20:" .. PAY, "both relayed to player 3, ages grown (" .. fx() .. ")")
check(line("coopfire: player 2's first launch on their real plane here: queued", from) ~= nil, "the first launch logged")
-- a stand-in: p ignored, m fired as before
fresh("host", 0)
M.byId[5] = { obj = E5, unit = "ERA_Unit_01_Dep_Air0", ord = 1, addr = 505 }
COOP.peerPlane(P1, 1)
peer(1, 3)
tick()
M.peers[1].real = nil
ppShots, fires = {}, {}
inbox[#inbox + 1] = "1|fx|m:5:0;p:5:0:" .. PAY
tick()
check(#ppShots == 0 and fired() == "1001/2/505", "a stand-in: p not replayed, m fired from it (" .. fired() .. ")")
-- the guards: unreadable, stale, over 16 a second, the runtime's refusal counted
fresh("host", 0)
COOP.peerPlane(P1, 1)
peer(1, 3)
tick()
M.peers[1].real = true
ppShots, ppR = {}, -1
local n0 = M.fxS.n
local drop0, bad0 = n0.dropped, n0.pBad or 0
inbox[#inbox + 1] = "1|fx|p:0:0:1,x,2;p:0:2000:" .. PAY .. ";p:0:0:" .. PAY
tick()
check(#ppShots == 1 and M.fxS.n.dropped - drop0 == 2, "an unreadable one and a stale one dropped, the third asked (" .. #ppShots .. ")")
check((M.fxS.n.pBad or 0) - bad0 == 1, "the runtime's refusal counted for the minute's line")
ppR = 1
local many = {}
for i = 1, 20 do many[#many + 1] = "p:0:0:" .. PAY end
ppShots = {}
clock = clock + 1.1
inbox[#inbox + 1] = "1|fx|" .. table.concat(many, ";")
tick()
check(#ppShots == 16, "at most 16 launches a second from a shooter (" .. #ppShots .. ")")
-- the loadout: yours in your hello / the roster, theirs from hi / pi, a bad one left out
fresh("host", 0)
loadout = "1001,2002/3/0,1"
tick()
check(M.roster[0] and M.roster[0].lo == "1001,2002/3/0,1", "the host's own roster entry carries its loadout")
local pi = ""
for _, s in ipairs(sent) do if s:find(">pi|0|") then pi = s end end
check(pi:find("|1001,2002/3/0,1|||%d*$") ~= nil, "and the roster tells every joiner (" .. pi .. ")")
sent = {}
loadout = "1001,2002/4/0,1"
tick()
local again = false
for _, s in ipairs(sent) do if s:find(">pi|0|.*|1001,2002/4/0,1|||%d*$") then again = true end end
check(again, "new weapons (the loadout changed): told again")
inbox[#inbox + 1] = "1|hi|" .. VERSION .. "|0.32.0|f16c_common|B|f16c|5,6/7/1,0"
tick()
check(M.roster[1] and M.roster[1].lo == "5,6/7/1,0", "a joiner's loadout from its hi")
inbox[#inbox + 1] = "1|hi|" .. VERSION .. "|0.32.0|f16c_common|B|f16c|5,x/7"
tick()
check(M.roster[1] and M.roster[1].lo == "", "a bad loadout left out")
loadout = ""
-- the paint (T5): yours in the roster and pi, theirs from hi, a bad one left out, a new one told again
function SV_CoopPaint() return paint end
paint = "12/3/7,8"
sent = {}
tick()
check(M.roster[0].paint == "12/3/7,8", "your paint in the host's roster entry")
local piP = ""
for _, s in ipairs(sent) do if s:find(">pi|0|") then piP = s end end
check(piP:find("|12/3/7,8||%d*$") ~= nil, "and in pi, after the loadout (" .. piP .. ")")
sent = {}
paint = "-1/0/"
tick()
local againP = false
for _, s in ipairs(sent) do if s:find(">pi|0|.*|%-1/0/||%d*$") then againP = true end end
check(againP, "a new paint (its default, no emblems): told again")
inbox[#inbox + 1] = "1|hi|" .. VERSION .. "|0.32.3|f16c_common|B|f16c|5,6/7/1,0|44/1/9"
tick()
check(M.roster[1] and M.roster[1].paint == "44/1/9", "a joiner's paint from its hi")
inbox[#inbox + 1] = "1|hi|" .. VERSION .. "|0.32.3|f16c_common|B|f16c|5,6/7/1,0|x/1/9"
tick()
check(M.roster[1] and M.roster[1].paint == "", "a bad paint left out")
paint = ""
-- the aircraft's name (your plane's GetObjName): in the roster and pi, a joiner's from hi, cleaned
function pawn:GetObjName() return "ADFX-02 Morgan" end
sent = {}
tick()
check(M.roster[0].ac == "ADFX-02 Morgan", "your aircraft's name in the roster (" .. tostring(M.roster[0].ac) .. ")")
local piA = ""
for _, s in ipairs(sent) do if s:find(">pi|0|") then piA = s end end
check(piA:find("|ADFX%-02 Morgan|%d*$") ~= nil, "and last in pi (" .. piA .. ")")
inbox[#inbox + 1] = "1|hi|" .. VERSION .. "|0.32.4|f16c_common|B|f16c|5,6/7/1,0|44/1/9|F-16C Fighting Falcon"
tick()
check(M.roster[1] and M.roster[1].ac == "F-16C Fighting Falcon", "a joiner's aircraft name from hi (" .. tostring(M.roster[1] and M.roster[1].ac) .. ")")
check(M.acClean("X|Y" .. string.char(1) .. "Z" .. string.char(10)) == "XYZ", "a | and control characters stripped")
check(#M.acClean(string.rep("A", 50)) == 32, "32 characters at most")
pawn.GetObjName = nil

---------------------------------------------------------------------------------------------------- (0.73.80) weapon stand-ins
-- (the user, 2026-11-04: "Then do the weapon stand-ins next") a launch whose weapon their real plane here hasn't, or has
-- as another kind, shown as the nearest weapon of the same kind it has (sv_coop.lua M.weaponFor, M.standInPay); the
-- runtime's SV_PPWeapons stubbed: each number -2 not usable, -1 not known, 0-4 seen launched, 10-14 the table's
print("(0.73.80) weapon stand-ins: another player's weapons their plane here hasn't")
local ppw, ppwCalls, ppfx, outOfRange, ppwGiven = {}, {}, {}, {}, {}
function SV_PPWeapons(a, t) ppwCalls[#ppwCalls + 1] = string.format("%d/%d", a, t); ppwGiven[a] = ppw[a] or ""; return ppw[a] or "" end
function SV_CoopPPFx(a, kind, v) ppfx[#ppfx + 1] = string.format("%d/%d/%d", a, kind, v); return 1 end
function SV_CoopPPShot(a, t, pay)               -- (and every number sent checked against the plane's weapons as last read)
    ppShots[#ppShots + 1] = string.format("%d/%d/%s", a, t, pay)
    local w = tonumber(pay:match("^%d+,(%d+),"))
    local k = {}
    for v in (ppwGiven[a] or ""):gmatch("[^,]+") do k[#k + 1] = tonumber(v) end
    if type(SV_PPWeapons) == "function" and #k > 0 and CFG.coop.sync.standins ~= false and (w >= #k or k[w + 1] == -2) then
        outOfRange[#outOfRange + 1] = pay
    end
    return 1
end
local function shot(k, w, s, u, lock) return string.format("%d,%d,%d,%d,96,%d,10,-5,0,-15,1800,0,100,-20,0", k, w, s or 0, u or 0, lock or 0) end
local function realRoom(kinds, lo, spawnLo, fb)  -- the host, player 2 on their real plane here (P1), player 3 too
    fresh("host", 0)
    M.byId[5] = { obj = E5, unit = "ERA_Unit_01_Dep_Air0", ord = 1, addr = 505 }
    COOP.peerPlane(P1, 1); COOP.peerPlane(P2, 2)
    peer(1, 3); peer(2, 3)
    tick()
    local P = M.peers[1]
    P.real, P.code, P.lo, P.fallback, P.wk, P.burstUntil, P.gunOn = true, "f22a", spawnLo or lo or "", fb, nil, nil, nil
    M.roster[1].lo = lo or ""
    ppw[1001] = kinds
    tick(1.1)                                     -- (a new second: no launches-a-second guard left over)
    ppShots, ppfx, ppwCalls, sent, M.said, ppwGiven = {}, {}, {}, {}, {}, {}
    return P
end
local function fire1(pay) inbox[#inbox + 1] = "1|fx|p:5:0:" .. pay; tick() end
local function lastShot() return ppShots[#ppShots] and ppShots[#ppShots]:match("^%d+/%d+/(.*)$") end
local from

-- a player whose weapons all exist here: every launch exactly as sent, the plane's weapons read once and logged
realRoom("-1,0,0,1,3", "1,2//21,33")
from = #logs + 1
fire1(shot(0, 1, 2, 1, 2)); fire1(shot(0, 2, 3, 0, 1)); fire1(shot(1, 3)); fire1(shot(3, 4))
check(table.concat(ppShots, " ") == table.concat({ "1001/505/" .. shot(0, 1, 2, 1, 2), "1001/505/" .. shot(0, 2, 3, 0, 1),
      "1001/505/" .. shot(1, 3), "1001/505/" .. shot(3, 4) }, " "),
      "their weapons all here and of their kinds: each launch as sent (" .. table.concat(ppShots, " ") .. ")")
check(#ppwCalls == 1 and ppwCalls[1] == "1001/0", "the plane's weapons read once (standin_table off: 0) (" .. table.concat(ppwCalls, " ") .. ")")
check(line("^coopfire: player 2's real plane here %(f22a%): its weapons 0 the gun, 1 the standard missile, 2 a missile special, 3 a laser, 4 an ESM / ECM %(SV_PPWeapons %-1,0,0,1,3%)", from) ~= nil,
      "what it has logged once (" .. tostring(line("its weapons", from)) .. ")")
check(M.fxS.n.standIn == nil and since(from, "shown on their real plane here as") == 0, "no stand-in counted or logged")

-- Amia's F-22A (the 31-round test): her weapon 3 (a missile special her plane here hasn't: weapons 0-2) shown as the
-- standard missile while its special isn't known here; as its special once that's been seen launched (2 s on); the
-- relay to player 3 keeps her weapon 3
realRoom("-1,-1,-1", "1,2//21,0")
from = #logs + 1
fire1(shot(0, 3, 2, 1, 2))
check(lastShot() == shot(0, 1, 0, 0, 1), "her weapon 3: their plane's weapon 1, spawn slot 0, byte 0, lock-ons 1 (" .. tostring(lastShot()) .. ")")
check(fx("2") == "2>fx|1|p:5:20:" .. shot(0, 3, 2, 1, 2), "relayed to player 3 as she sent it (weapon 3) (" .. fx("2") .. ")")
check(line("^coopfire: player 2's missile special %(weapon 3%) shown on their real plane here as its weapon 1 %(the standard missile%): it has no weapon 3", from) ~= nil,
      "logged once (" .. tostring(line("shown on their real plane", from)) .. ")")
fire1(shot(0, 3))
check(lastShot() == shot(0, 1) and since(from, "shown on their real plane here as") == 1, "again: the same, not logged again")
ppw[1001] = "-1,0,0"                              -- (its weapon 2 seen launched: an explosive weapon)
fire1(shot(0, 3))
check(lastShot() == shot(0, 1) and #ppwCalls == 1, "under 2 s: what was read kept")
clock = clock + 2.1
fire1(shot(0, 3, 4, 0, 3))
check(lastShot() == shot(0, 2, 0, 0, 1) and #ppwCalls == 2, "2 s on: read again, her weapon 3 as its missile special 2 (" .. tostring(lastShot()) .. ")")
check(line("^coopfire: player 2's missile special %(weapon 3%) shown on their real plane here as its weapon 2 %(a missile special%): it has no weapon 3", from) ~= nil,
      "the new stand-in logged")
check(M.fxS.n.standIn == 4, "4 stand-ins counted (" .. tostring(M.fxS.n.standIn) .. ")")
fire1(shot(0, 2, 1, 0, 1)); fire1(shot(0, 1, 0, 0, 2))
check(ppShots[#ppShots - 1]:find(shot(0, 2, 1, 0, 1), 1, true) and lastShot() == shot(0, 1, 0, 0, 2), "her weapons 2 and 1: as sent")

-- a laser where she has a missile special: never the remote fire onto it; a missile onto a known laser neither
realRoom("-1,0,1", "1,2//21,0")
fire1(shot(0, 3)); fire1(shot(0, 2))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(0, 1) .. " 1001/505/" .. shot(0, 1),
      "weapons 3 (none) and 2 (a laser here): both the standard missile (" .. table.concat(ppShots, " ") .. ")")
realRoom("-1,0,0,1", "1,2//21,33")
fire1(shot(1, 2))
check(lastShot() == shot(1, 3), "a laser as weapon 2, where weapon 2 is a missile special: their laser 3 (" .. tostring(lastShot()) .. ")")
-- a laser on a plane with none: not shown, logged and counted
realRoom("-1,0,0", "1,2//21,0")
from = #logs + 1
local none0 = M.fxS.n.standNone or 0
fire1(shot(1, 3)); fire1(shot(1, 2))
check(#ppShots == 0 and (M.fxS.n.standNone or 0) - none0 == 2, "a laser with no laser there (3: none, 2: a missile special): not shown, counted")
check(line("^coopfire: player 2's laser %(weapon 3%) NOT shown: it has no weapon 3, and their real plane here has no laser %(its weapons: %-1,0,0%)", from) ~= nil
      and line("^coopfire: player 2's laser %(weapon 2%) NOT shown: its weapon 2 is a missile special", from) ~= nil, "each logged once, with why")
-- an ESM / ECM: one of its kind
realRoom("-1,0,3", "1,2//21,0")
fire1(shot(3, 3))
check(lastShot() == shot(3, 2), "an ESM as weapon 3: their plane's ESM 2 (" .. tostring(lastShot()) .. ")")
-- a bullet special with none of its kind: a burst of the plane's gun, standin_gun_s long
realRoom("-1,0,0", "1,2//21,0")
from = #logs + 1
fire1(shot(2, 3))
check(#ppShots == 0 and table.concat(ppfx, " ") == "1001/1/1", "a bullet special with none there: the gun's trigger on (" .. table.concat(ppfx, " ") .. ")")
check(line("^coopfire: player 2's bullet special %(weapon 3%) shown as their real plane's gun here", from) ~= nil and (M.fxS.n.standGun or 0) >= 1,
      "logged, counted")
tick(0.25)
check(table.concat(ppfx, " ") == "1001/1/1", "0.25 s on: still firing")
tick(0.3)
check(table.concat(ppfx, " ") == "1001/1/1 1001/1/0", "0.55 s on: off (" .. table.concat(ppfx, " ") .. ")")
realRoom("-1,0,2", "1,2//21,0")
fire1(shot(2, 3))
check(lastShot() == shot(2, 2) and #ppfx == 0, "a bullet special where it has one: that one, no gun (" .. tostring(lastShot()) .. ")")
-- their loadout changed since their plane here spawned (it keeps its loadout): the same special where it sits here
realRoom("-1,-1,-1,-1", "1,2//21,7", "1,2//7,21")
fire1(shot(0, 3, 2, 1, 4)); fire1(shot(0, 2, 1, 0, 2))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(0, 2, 2, 1, 4) .. " 1001/505/" .. shot(0, 3, 1, 0, 2),
      "specials 7 and 21 swapped: each shown as the same special, slot and lock-ons kept (" .. table.concat(ppShots, " ") .. ")")
realRoom("-1,-1,-1", "1,2//33,0", "1,2//21,0")
fire1(shot(0, 2)); fire1(shot(1, 2))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(0, 1) .. " 1001/505/" .. shot(1, 2),
      "a new special (33) its plane here hasn't, its 21 not known: a missile as the standard missile, a laser tried as sent (" .. table.concat(ppShots, " ") .. ")")
-- nothing known of the plane but how many weapons it has
realRoom("-1,-1,-1", "1,2//21,0")
fire1(shot(0, 2)); fire1(shot(0, 3)); fire1(shot(1, 2)); fire1(shot(1, 3))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(0, 2) .. " 1001/505/" .. shot(0, 1) .. " 1001/505/" .. shot(1, 2),
      "kinds not known: weapons 2 as sent, 3 as the standard missile, a laser 2 as sent, a laser 3 not shown (" .. table.concat(ppShots, " ") .. ")")
-- a special's number is 2 or more: a laser as weapon 1 (AC8WeaponSwap) only as a laser of the plane's
realRoom("-1,-1,1", "1,2//21,0")
fire1(shot(1, 1)); fire1(shot(3, 0))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(1, 2), "a laser as weapon 1: their laser 2; an ESM as weapon 0: not shown (" .. table.concat(ppShots, " ") .. ")")
-- a number the runtime can't use (-2): never sent
realRoom("-1,0,-2,0", "1,2//21,33")
fire1(shot(0, 2))
check(lastShot() == shot(0, 3), "weapon 2 not usable there: the nearest special, 3 (" .. tostring(lastShot()) .. ")")
-- a modded plane on its stock fallback (0.73.80 modsync: its own default loadout, another airframe's numbers)
realRoom("-1,-1,-1,-1", "1,2//21,0", nil, "adfx02")
from = #logs + 1
fire1(shot(0, 2)); fire1(shot(1, 2)); fire1(shot(0, 1))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(0, 1) .. " 1001/505/" .. shot(1, 2) .. " 1001/505/" .. shot(0, 1),
      "a fallback: a missile special not known there as the standard missile, a laser tried as sent, the standard missile as sent ("
      .. table.concat(ppShots, " ") .. ")")
check(line("^coopfire: player 2's missile special %(weapon 2%) shown on their real plane here as its weapon 1 %(the standard missile%): its weapon 2 isn't known yet and it's another airframe", from) ~= nil,
      "logged with why (" .. tostring(line("shown on their real plane", from)) .. ")")
check(line("^coopfire: player 2's real plane here %(f22a, shown as a adfx02%)", from) ~= nil, "its weapons' line names the fallback")
ppw[1001] = "-1,0,1,0"                            -- (seen launched: 2 a laser, 3 a missile special)
clock = clock + 2.1
fire1(shot(0, 3)); fire1(shot(0, 2)); fire1(shot(1, 3))
check(table.concat(ppShots, " ", 4) == "1001/505/" .. shot(0, 3) .. " 1001/505/" .. shot(0, 3) .. " 1001/505/" .. shot(1, 2),
      "its weapons seen: a missile as 3 as sent, as 2 (a laser there) its special 3, a laser as 3 its laser 2 (" .. table.concat(ppShots, " ", 4) .. ")")
-- the table's kinds: used only with standin_table, and then asked for (SV_PPWeapons' second argument)
realRoom("-1,10,11,10", "1,2//21,33")
fire1(shot(1, 3)); fire1(shot(0, 2))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(1, 3) .. " 1001/505/" .. shot(0, 2) and ppwCalls[1] == "1001/0",
      "standin_table off: the table's kinds not used, each as sent (" .. table.concat(ppShots, " ") .. ")")
CFG.coop.sync.standin_table = true
realRoom("-1,10,11,10", "1,2//21,33")
fire1(shot(1, 3)); fire1(shot(0, 2)); fire1(shot(1, 2))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(1, 2) .. " 1001/505/" .. shot(0, 3) .. " 1001/505/" .. shot(1, 2) and ppwCalls[1] == "1001/1",
      "standin_table on: a laser as 3 (a missile special there) its laser 2, a missile as 2 its special 3 (" .. table.concat(ppShots, " ") .. ")")
CFG.coop.sync.standin_table = false
-- the minute's line: the stand-ins by player
from = #logs + 1
for _ = 1, 62 do tick(1) end
local tallySI = line("^coopfire: 60 s:", from)
check(has(tallySI, "; weapon stand-ins: ") and has(tallySI, "by player: 2: "), "the minute's line counts the stand-ins by player (" .. tostring(tallySI) .. ")")
-- nothing read of the plane, or no SV_PPWeapons (a Lua patch on an older runtime), or standins off: as sent, as before
realRoom("", "1,2//21,0")
from = #logs + 1
fire1(shot(0, 3))
check(lastShot() == shot(0, 3) and line("^coopfire: player 2's real plane here: its weapons can't be read", from) ~= nil,
      "SV_PPWeapons gave nothing: as sent (the runtime's own check refuses it), logged")
ppw[1001] = "-1,-1,-1"
fire1(shot(0, 3))
check(lastShot() == shot(0, 3) and #ppwCalls == 1, "under 2 s: not asked again")
clock = clock + 2.1
fire1(shot(0, 3))
check(lastShot() == shot(0, 1) and #ppwCalls == 2, "2 s on: asked again, read, the stand-in (" .. tostring(lastShot()) .. ")")
realRoom("-1,-1,-1", "1,2//21,0")
local savedPPW = SV_PPWeapons
SV_PPWeapons = nil
fire1(shot(0, 3))
check(lastShot() == shot(0, 3), "no SV_PPWeapons (runtime 0.32.23): as sent")
SV_PPWeapons = savedPPW
CFG.coop.sync.standins = false
realRoom("-1,-1,-1", "1,2//21,0")
fire1(shot(0, 3)); fire1(shot(1, 3)); fire1(shot(2, 3))
check(table.concat(ppShots, " ") == "1001/505/" .. shot(0, 3) .. " 1001/505/" .. shot(1, 3) .. " 1001/505/" .. shot(2, 3)
      and #ppwCalls == 0 and #ppfx == 0, "standins = false: every launch as sent, nothing read, no gun burst (as before)")
CFG.coop.sync.standins = true
-- an AI stand-in (not a real plane): nothing of this
realRoom("-1,-1,-1", "1,2//21,0")
M.peers[1].real = nil
fire1(shot(0, 3))
check(#ppShots == 0 and #ppwCalls == 0, "an AI stand-in: p not replayed, its weapons not read")
check(#outOfRange == 0, "never a number the plane here hasn't (or can't use) sent once its weapons are known ("
      .. table.concat(outOfRange, " ") .. ")")
-- the rule alone (M.weaponFor), on a plane of 6 weapons
local c6 = { n = 6, k = { [0] = -1, 0, 0, 1, 0, 3 } }
local function wf(k, w) local x, how = M.weaponFor(k, w, c6, nil, false, true); return tostring(x) .. "/" .. how end
check(wf(0, 2) == "2/own" and wf(0, 6) == "4/near" and wf(0, 9) == "4/near" and wf(0, 3) == "2/near" and wf(1, 2) == "3/near"
      and wf(3, 7) == "5/near" and wf(2, 3) == "nil/gun" and wf(0, 0) == "1/near",
      "M.weaponFor: own, the nearest of its kind (ties to the lower), the gun for a bullet special (" .. table.concat({ wf(0, 2), wf(0, 6),
      wf(0, 9), wf(0, 3), wf(1, 2), wf(3, 7), wf(2, 3), wf(0, 0) }, " ") .. ")")
SV_PPWeapons, SV_CoopPPFx = nil, nil
function SV_CoopPPShot(a, t, pay) ppShots[#ppShots + 1] = string.format("%d/%d/%s", a, t, pay); return ppR end

---------------------------------------------------------------------------------------------------- the host's hunt on real planes
print("the hunt onto real planes: never a player at their airfield or down")
fresh("host", 0)
local orders = {}
local function enemy(id, addr)
    local e = { full = "BP_OP1022_f16c_CP_C" .. LEVEL .. "E" .. id, addr = addr }
    function e:EngagementOrderOverride(o, target, prio) orders[#orders + 1] = string.format("%d>%d", self.addr, target.addr) end
    function e:GetAddress() return self.addr end
    M.byId[id] = { obj = e, unit = "ERA_Unit_01_Dep_Air0", ord = id, addr = addr }
end
enemy(41, 4101); enemy(42, 4102)
M.units["ERA_Unit_01_Dep_Air0"] = { n = 2, gen = 1, planes = { { id = 41 }, { id = 42 } } }
local R1, R2 = plane(2001, "Real1"), plane(2002, "Real2")
M.peers[1] = { real = true, shown = true, obj = R1, addr = 2001, onAirfield = true }
M.peers[2] = { real = true, shown = true, obj = R2, addr = 2002 }
M.huntOn = {}
check(not COOP.realTarget(1) and COOP.realTarget(2) == R2, "a player at their airfield isn't a target; one flying is")
local ok, s, n = COOP.huntReal("ERA_Unit_01_Dep_Air0", 1)
check(ok and s == 2 and n == 2 and table.concat(orders, " ") == "4101>2002 4102>2002",
      "a flight sent onto the landed player goes after the one flying instead (" .. table.concat(orders, " ") .. ")")
M.peers[2].down = true
orders = {}
ok = COOP.huntReal("ERA_Unit_01_Dep_Air0")
check(not ok and #orders == 0, "nobody flying (one landed, one down): no real plane to go after")
M.peers[1].onAirfield, M.peers[2].down = nil, nil
check(COOP.realTarget(1) == R1, "back in the air: a target again")
M.peers[1], M.peers[2], M.huntOn = nil, nil, nil

---------------------------------------------------------------------------------------------------- T5: damage shown
print("their damage on their real plane here: health as their game says, never under 1 HP")
fresh("host", 0)
COOP.peerPlane(P1, 1)
P1.HealthInternal, P1.MinHealth = 1000, 0
peerState[1] = "100000,0,300000,0,0,0,640,100,3,100"       -- (64 of 100 HP, in the level and alive)
tick()
M.peers[1].real = true
tick()
check(P1.HealthInternal == 640 and P1.MinHealth == 1.0, "their 64 % on their real plane here, its floor 1 HP (" .. tostring(P1.HealthInternal) .. ")")
peerState[1] = "100000,0,300000,0,0,0,0,100,3,100"         -- (their game: 0, as it went down)
tick()
check(P1.HealthInternal == 10, "never under 1 HP here (a real plane is never destroyed mid-level)")
peerState[1] = "100000,0,300000,0,0,0,9999,100,3,100"
tick()
check(P1.HealthInternal == 1000, "never over its full health")
CFG.coop.real_damage = false
peerState[1] = "100000,0,300000,0,0,0,500,100,3,100"
tick()
check(P1.HealthInternal == 1000, "real_damage off: left alone")
CFG.coop.real_damage = true
M.peers[1].real = nil
tick()
check(P1.HealthInternal == 1000, "an AI stand-in: left alone (its own damage sync)")
peerState[1] = nil

---------------------------------------------------------------------------------------------------- stray copies (joiner)
print("a joiner's copies never bound to the host's: taken down on a link back, and after 15 s")
local function copyPlane(addr)
    local o = { full = "BP_OP1022_f16c_CP_C" .. LEVEL .. "C" .. addr, addr = addr, HealthInternal = 1000, killed = false }
    function o:GetAddress() return self.addr end
    function o:SetMinHealth() end
    function o:ModifyHealth(d) self.killed = true; self.HealthInternal = 0 end
    return o
end
fresh("join", 1)
local A1, A2 = copyPlane(8001), copyPlane(8002)
M.cunits = { ERA_Unit_01_Dep_Air0 = { gen = 1, n = 2, planes = { A1, A2 }, binds = {}, gbinds = {}, at = clock } }
local from = #logs + 1
inbox[#inbox + 1] = "0|sys|lost"
tick()
inbox[#inbox + 1] = "0|sys|up"
tick()
check(A1.killed and A2.killed and has(line("^coop: 2 copies taken down", from), "2 of them never bound"),
      "the link back: both unbound copies taken down too (" .. tostring(line("^coop: %d+ copies taken down", from)) .. ")")
fresh("join", 1)
local B1, B2 = copyPlane(8101), copyPlane(8102)
M.cunits = { ERA_Unit_02_Dep_Air0 = { gen = 1, n = 2, planes = { B1, B2 }, binds = {}, gbinds = {}, at = clock } }
M.copies[77] = { obj = B1, exp = 1000, addr = 8101 }   -- (B1 bound, B2 never)
M.strayAt = 0
tick(5.0)
check(not B2.killed, "5 s on: not yet")
tick(11.0)
check(B2.killed and not B1.killed and line("^coop: 1 stray enemy copies taken down") ~= nil, "15 s on, still unbound: taken down; the bound one left")
-- any enemy AI plane here that isn't one of the host's (not spawned through the co-op stream): the same after 15 s
local S1, S2, SP = copyPlane(8201), copyPlane(8202), copyPlane(8203)
planes = { { obj = S1, name = "S1", unit = "ERA_Unit_03_Dep_Air0" }, { obj = B1, name = "B1", unit = "ERA_Unit_02_Dep_Air0" },
           { obj = SP, name = "SP", unit = "SV_Unit_CoopPeerB" }, { obj = S2, name = "S2", unit = "ERA_Unit_04_Dep_Air0", down = true } }
M.strayAt = 0
tick(5.0)
check(not S1.killed, "a stray enemy plane: seen, not yet")
tick(16.0)
check(S1.killed and not B1.killed and not SP.killed and not S2.killed and has(line("^coop: %d+ stray enemy copies taken down"), "ERA_Unit_03_Dep_Air0 S1"),
      "15 s on: the stray taken down (named); a bound copy, another player's stand-in and one already down left")
planes = {}
M.copies[77] = nil

---------------------------------------------------------------------------------------------------- binds, the join hold
print("a bind before its flight's spawn is kept; the host's round waits for players joining")
fresh("join", 1)
inbox[#inbox + 1] = "0|bd|ERA_Unit_03_Dep_Air0|5|1|901"          -- (its spawn not queued yet: kept, not dropped)
tick()
check(M.pendBind and M.pendBind.ERA_Unit_03_Dep_Air0 and M.pendBind.ERA_Unit_03_Dep_Air0.binds[1] == 901, "the early bind kept")
inbox[#inbox + 1] = "0|sp|ERA_Unit_03_Dep_Air0|-|-|-1|5"
for _ = 1, 4 do tick(1); roundsTick(clock) end              -- (a joiner's spawns run in the rounds tick)
local cu = M.cunits.ERA_Unit_03_Dep_Air0
check(cu and cu.gen == 5 and cu.binds[1] == 901 and not M.pendBind.ERA_Unit_03_Dep_Air0, "its spawn takes it: plane 1 will be bound to 901")
-- the host: the round waits while a linked player isn't in the mission (each at most join_wait_s)
fresh("host", 0)
M.roster[3] = { row = "f16c_common", ver = VERSION, name = "LATE" }
peer(1, 3); peer(2, 3)
peerState[3] = nil                                           -- (player 4 linked, not in the mission: loading)
tick()
local w = COOP.joinWaiting(clock)
check(w and #w == 1 and w[1]:upper():find("LATE") ~= nil, "a linked player still loading is waited for (" .. tostring(w and w[1]) .. ")")
D.state, D.at, D.round = "spawning", clock, 3
D.queue = { "ERA_Unit_01_Dep_Air0" }
local from = #logs + 1
check(joinHold(clock) == true and D.joinHeld ~= nil and line("^round 3: enemy spawns paused while", from) ~= nil, "the round held, logged")
clock = clock + 91
check(COOP.joinWaiting(clock) == nil and joinHold(clock) == false and line("^round 3: everyone's in the mission", from) ~= nil,
      "after join_wait_s (90): not waited for any more, spawns go on")
peerState[3] = "100000,0,300000,0,0,0,800,100,3,100"
tick()
check(COOP.joinWaiting(clock) == nil, "in the mission: nothing to wait for")
peerState[3] = nil
tick()
check(COOP.joinWaiting(clock) ~= nil, "out again (a restart, a lost link): waited for again")
CFG.coop.join_wait_s = 0
check(COOP.joinWaiting(clock) == nil, "join_wait_s 0: never")
CFG.coop.join_wait_s = 90
-- ((0.73.80, the 31-round test's finding errors2) a player lost in the mission (they quit or crashed: nothing more comes
-- from their game) holds the round [coop] hold_lost_s after their last state, not join_wait_s; one lost while loading in
-- still up to join_wait_s; each hold logged as it starts and ends)
peerState[3] = "100000,0,300000,0,0,0,800,100,3,100"
from = #logs + 1
tick()
check(COOP.joinWaiting(clock) == nil and line("^coop: LATE no longer holds the round: in the mission %(held", from) ~= nil,
      "in the mission again: not held, the last hold's end logged (" .. tostring(line("no longer holds", from)) .. ")")
from = #logs + 1
peerState[3] = nil                                           -- (they quit: their stream stops)
tick(2)
check(COOP.joinWaiting(clock) ~= nil and line("^coop: the round waits for LATE %(not in the mission yet%), up to 90 s", from) ~= nil,
      "their stream stopped: held as one not in the mission, logged")
inbox[#inbox + 1] = "3|sys|lost"
tick(4)
check(line("^coop: player 4's link lost in the mission %(their last state 6 s ago%): they hold the round 15 s after it at most", from) ~= nil,
      "their link lost (6 s on): in the mission, logged (" .. tostring(line("link lost", from)) .. ")")
check(COOP.joinWaiting(clock) ~= nil, "... still held 6 s after their last state")
clock = clock + 10
check(COOP.joinWaiting(clock) == nil and line("^coop: LATE no longer holds the round: their link was lost in the mission, nothing from them for 16 s %(%[coop%] hold_lost_s 15%) %(held 14 s; their link lost in the mission%)", from) ~= nil,
      "16 s after their last state: no longer held (0.73.79: 90 s), logged with how long and why (" .. tostring(line("no longer holds", from)) .. ")")
check(joinHold(clock) == false, "... the round goes on")
-- one linked but never in the mission here, their link lost (loading in: Amia's was lost 26-27 s twice): held to join_wait_s
M.roster[4] = { row = "f16c_common", ver = VERSION, name = "SLOW" }
peerState[4] = nil
tick()
inbox[#inbox + 1] = "4|sys|lost"
tick(); tick(20)
local w2 = COOP.joinWaiting(clock)
check(w2 and #w2 == 1 and w2[1]:upper():find("SLOW") ~= nil and line("^coop: player 5's link lost while not in the mission %(not seen in it here%)", from) ~= nil,
      "a link lost while loading in: still held 21 s on (up to join_wait_s), logged")
CFG.coop.hold_lost_s = -1
w2 = COOP.joinWaiting(clock)
check(w2 and #w2 == 2, "[coop] hold_lost_s -1: the one lost in the mission held up to join_wait_s too (as 0.73.79)")
CFG.coop.hold_lost_s = 15
-- their link back (sys|up) and in the mission: no lost link held for them
inbox[#inbox + 1] = "3|sys|up"
peerState[3] = "100000,0,300000,0,0,0,800,100,3,100"
tick()
check(M.lostAt[3] == nil and #COOP.joinWaiting(clock) == 1, "player 4 back (sys|up) in the mission: their lost link forgotten, not held")
M.roster[4], peerState[4] = nil, nil
from = #logs + 1
COOP.joinWaiting(clock)
check(line("^coop: SLOW no longer holds the round: gone from the room", from) ~= nil, "one gone from the room: their hold's end logged")
M.roster[3], peerState[3] = nil, nil

---------------------------------------------------------------------------------------------------- sync off
print("sync off")
fresh("host", 0)
CFG.coop.sync.enabled = false
M.linkedPeers = 2
COOP.peerPlane(P1, 1)
peer(1, 3 + 16 + 64 + 128)
P1.gearCalls = {}
inFlight = {}
tick()
inFlight = { msl(9001, "BP_plwp_msl_f16c_C", nil) }
gear.vis, input, ammo[0] = true, "0,0,0,1000,0,0", 10
tick()
check(fx() == "" and fired() == "" and #P1.gearCalls == 0, "nothing sent, nothing shown")
check(meFlags == 3, "no sync bits (flags " .. meFlags .. ")")
CFG.coop.sync.enabled = true

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
do
    local sm = readAll(MOD .. "/Scripts/sv_main.lua")
    local a, b = sm:find("timed(\"coop ammo\", COOP.ammoRead)", 1, true), sm:find("timed(\"ammo\", ammoTick, tick, survivalPC)", 1, true)
    check(a and b and a < b, "sv_main: COOP.ammoRead before ammoTick (its refill)")
    check(has(sm, "pcall(COOP.syncSetup)"), "sv_main: COOP.syncSetup at the main menu, with the other rows")
    local bs = readAll(MOD .. "/../../../tools/build_survival.py")
    check(has(bs, "COOP_STANDIN_SUFFIX = ('_svcp', '_SVCP')") and has(bs, "extra.append((src + COOP_STANDIN_SUFFIX[0], src, base + COOP_STANDIN_SUFFIX[1]))"),
          "build_survival: the stand-ins' <row>_svcp mission rows")
end

print(fails == 0 and "co-op fire test: all passed" or ("co-op fire test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
