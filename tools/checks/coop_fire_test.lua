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
                                         su57_common = { NpcId = FName("OP_su57") } })
local npc = DT("DT_NPC", { OP_f16c = npcRow({ [0] = "FCS_Flr", "FCS_Gun", "FCS_Msl", nil, "FCS_Bad" }) })
local fcs = DT("DT_NPC_FCS", { FCS_Flr = { NpcWeaponId = FName("W_Flr") }, FCS_Gun = { NpcWeaponId = FName("W_Gun") },
                               FCS_Msl = { NpcWeaponId = FName("W_Msl") }, FCS_Bad = { NpcWeaponId = FName("W_Missing") } })
local wpn = DT("DT_NPC_Weapon", { W_Flr = { damage = 0, AreaOfEffectDamage = 0 }, W_Gun = { damage = 7, AreaOfEffectDamage = 0 },
                                  W_Msl = { damage = 60, AreaOfEffectDamage = 20 } })
objects[PROBE_TABLES[2].path], objects[FCS_TABLE], objects[WEAPON_TABLE] = npc, fcs, wpn
objects["/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"] = mission
M.svcpDone, M.svcpReady = nil, nil
from = #logs + 1
COOP.syncSetup()
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
    local a, b = sm:find("pcall(COOP.ammoRead)", 1, true), sm:find("pcall(ammoTick, tick, survivalPC)", 1, true)
    check(a and b and a < b, "sv_main: COOP.ammoRead before ammoTick (its refill)")
    check(has(sm, "pcall(COOP.syncSetup)"), "sv_main: COOP.syncSetup at the main menu, with the other rows")
    local bs = readAll(MOD .. "/../../../tools/build_survival.py")
    check(has(bs, "COOP_STANDIN_SUFFIX = ('_svcp', '_SVCP')") and has(bs, "extra.append((src + COOP_STANDIN_SUFFIX[0], src, base + COOP_STANDIN_SUFFIX[1]))"),
          "build_survival: the stand-ins' <row>_svcp mission rows")
end

print(fails == 0 and "co-op fire test: all passed" or ("co-op fire test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
