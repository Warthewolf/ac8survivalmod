-- defences_test.lua <mod dir> <work dir> (run by tools/checks/defences_test.sh): the stronger airfield defences and the
-- STORE's CIWS (0.72.1; user, 2026-10-29: "make Allied SAMs and Anti Air Guns more effective, increase their lock on
-- range, also increase the lifetime of the missile they fire, increase their abilities and Add CIWS that can be
-- purchased and placed around the airfield"), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn,
-- sv_rounds, sv_flights, sv_shop, sv_allies and sv_tactical, the game's tables stubbed with the stock rows' numbers
-- (DT_NPC_FCS, DT_NPC_Weapon and DT_NPC_AIModule as build/stock has them; DT_NPC and DT_SV_NpcRows):
--   ALLY.setup: each defence's fire control <FCS>_SVA_Defence, before -> after in its log line: the AA guns' lock-on
--     range, flak reach and width, the SAM sites' missile, the CIWS's gun on the ships' Mk 15 fire control all the way
--     round with its rounds' flight, faster turrets, the fire-rate boost kept, the search module, each defence row's
--     health; the Aegis's own as before (its Mk 15 still +-60, its rounds as they were); CIWS fcs_row none or a row the
--     game hasn't; a container without the CIWS row (the rest still sold, the CIWS NOT AVAILABLE);
--   the STORE: the DEFENCES page's CIWS row (its price and raise, its four units in order, ALL BUILT), the old fourth
--     row's turn takes the CIWS;
--   ALLY.tick / hudLine: the CIWS on the ALLIES row, a lost one's callout and line; repairs; KILL.side's "defences";
--   the build in step: build_survival.py's DEFENCES page and model check, sv_flights' SHOP.menuRows and icons.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.72.1-defences.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local nextAddr = 100
local function addr() nextAddr = nextAddr + 1; return nextAddr end
-- a DataTable: FindRow hands back the row itself (edited in place, as UE4SS's), AddRow copies it in
local DTm = {}
DTm.__index = DTm
function DTm:FindRow(n) return self.rows[tostring(n)] end
function DTm:AddRow(n, r)
    n = tostring(n)
    local c = {}
    for k, v in pairs(r) do c[k] = v end
    if not self.rows[n] then self.order[#self.order + 1] = n end
    self.rows[n] = c
end
function DTm:RemoveRow(n)
    n = tostring(n)
    self.rows[n] = nil
    for i, o in ipairs(self.order) do if o == n then table.remove(self.order, i); break end end
end
function DTm:GetRowNames() return self.order end
local function dt(full, rows)
    local t = setmetatable({ full = full, addr = addr(), rows = {}, order = {} }, DTm)
    for _, r in ipairs(rows or {}) do t:AddRow(r[1], r[2]) end
    return t
end
local NONE = FName("None")
local function npcRow(fcs0, extra)                -- a DT_NPC row: NpcFCSId0 (or None) and nothing else of note
    local r = { NpcAIModuleId = NONE, MaxHealthDifference = 0 }
    for i = 0, 5 do r["NpcFCSId" .. i] = NONE end
    if fcs0 then r.NpcFCSId0 = FName(fcs0) end
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end
-- the stock rows' numbers (build/stock: DT_NPC_FCS, DT_NPC_Weapon, DT_NPC_AIModule; tools/re/AIRFIELD_SUPPLY.md 4)
local FCS_ROWS = {
    { "NPC_FCS_VehicleAAGun000", { NpcAIModuleId = FName("NPC_AIModule_GroundVehicle000"), NpcWeaponId = FName("AAGUN_Ground_000"),
      MagazineCapacity = 10, PredictionOffsetTime = 0.8, CaptureDistance = 2200.0, CaptureAngleRange = 30.0, ActivationTime = 0.5,
      TriggeringTime = 2.0, TriggerCount = 1, ShotIntervalTime = 2.0, RestingTime = 1.0, bEnableLostTargetInClouds = true,
      YawSpeed = 30.0, YawAngleMin = -180.0, YawAngleMax = 180.0, PitchSpeed = 30.0, PitchAngleMin = 0.0, PitchAngleMax = 85.0 } },
    { "NPC_FCS_VehicleSAM001", { NpcAIModuleId = FName("NPC_AIModule_Turret000"), NpcWeaponId = FName("SAM_Ground_000"),
      MagazineCapacity = 10, PredictionOffsetTime = 0.0, CaptureDistance = 3000.0, CaptureAngleRange = 30.0, ActivationTime = 2.0,
      TriggeringTime = 5.0, TriggerCount = 1, ShotIntervalTime = 5.0, RestingTime = 10.0, bEnableLostTargetInClouds = true,
      YawSpeed = 30.0, YawAngleMin = -180.0, YawAngleMax = 180.0, PitchSpeed = 30.0, PitchAngleMin = 0.0, PitchAngleMax = 45.0 } },
    { "NPC_FCS_VesselCIWS000", { NpcAIModuleId = FName("NPC_AIModule_Turret000"), NpcWeaponId = FName("CIWS_Vessel_000"),
      MagazineCapacity = 10, PredictionOffsetTime = 0.8, CaptureDistance = 2500.0, CaptureAngleRange = 30.0, ActivationTime = 0.5,
      TriggeringTime = 3.0, TriggerCount = 1, ShotIntervalTime = 3.0, RestingTime = 1.0, bEnableLostTargetInClouds = true,
      YawSpeed = 37.5, YawAngleMin = -60.0, YawAngleMax = 60.0, PitchSpeed = 30.0, PitchAngleMin = 1.0, PitchAngleMax = 60.0 } },
}
local WPN_ROWS = {
    { "AAGUN_Ground_000", { MaxSpawnAngle = 1.0, LifeTime = 3.0, bIsHoming = false, DamageAreaLengthMeters = 2000.0,
      DamageAreaRadiusMeters = 20.0 } },
    { "SAM_Ground_000", { MaxSpawnAngle = 0.0, LifeTime = 7.3, bIsHoming = true, AccelerationKmph = 300.0, SpeedMaxKmph = 3000.0,
      MaxRotationAngle = 15.0, HomingReductionInCloud = 0.5, DamageAreaLengthMeters = 0.0, DamageAreaRadiusMeters = 0.0 } },
    { "CIWS_Vessel_000", { MaxSpawnAngle = 1.0, LifeTime = 3.0, bIsHoming = false, DamageAreaLengthMeters = 0.0,
      DamageAreaRadiusMeters = 0.0 } },
}
local MINE_ROWS = {                               -- DT_SV_NpcRows' allies (tools/build_survival.py build_npc_rows)
    { "SV_Ally_Moonchild", npcRow() }, { "SV_Ally_Wingmen", npcRow() }, { "SV_Ally_Aegis", npcRow() },
    { "SV_Def_Gepa", npcRow("NPC_FCS_VehicleAAGun000") }, { "SV_Def_Avng", npcRow("NPC_FCS_VehicleSAM001") },
    { "SV_Def_Ciws", npcRow() },                  -- (GR033_ciws_01's: no fire control row of its own)
    { "SV_Turret_aegs_mk15_Ally", npcRow("NPC_FCS_VesselCIWS000") }, { "SV_Turret_aegs_mk41_Ally", npcRow() },
    { "SV_Turret_aegs_mk45_Ally", npcRow() }, { "SV_Turret_aegs_artillery_Ally", npcRow() },
}
local T = {}
local function tables(mineRows)
    T.npc, T.mine = dt("DT_NPC"), dt("DT_SV_NpcRows", mineRows or MINE_ROWS)
    T.fcs, T.wpn = dt("DT_NPC_FCS", FCS_ROWS), dt("DT_NPC_Weapon", WPN_ROWS)
    T.mod = dt("DT_NPC_AIModule", { { "NPC_AIModule_Turret000", { Radius = 6000.0, bEnableLostTargetInClouds = true } } })
end
tables()
local GI = { full = "GameInstance", addr = 1 }
local objects = {}                                -- FindAllOf's answers by class
function NotifyOnNewObject() end
function FindAllOf(c) return objects[c] or {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
local paths                                       -- (sv_config / sv_rows' table paths, filled once they're loaded)
function StaticFindObject(p) return paths and paths[p] or nil end
local events, alive, spawned = {}, {}, {}
function SV_Event(name) events[#events + 1] = name; return 1 end
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Spawn(u) spawned[#spawned + 1] = u; alive[u] = 1; return 1 end
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end
local requests = {}
function SV_ShopRequest(probe)
    if probe then return 1 end
    return table.remove(requests, 1) or ""
end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

local function part(name, chunk)
    assert(load(readAll(MOD .. "/Scripts/" .. name), chunk or ("=" .. name)))()
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
part("sv_flights.lua"); part("sv_shop.lua"); part("sv_allies.lua"); part("sv_tactical.lua")
local onAirfield = true
function playerOnAirfield() return onAirfield end
local callouts = {}
function hudCallout(t, sub) callouts[#callouts + 1] = tostring(t) .. " / " .. tostring(sub) end
local function setPaths()
    paths = { [PROBE_TABLES[2].path] = T.npc, [CFG.specials.shuttle.npc_rows] = T.mine, [FCS_TABLE] = T.fcs,
              [WEAPON_TABLE] = T.wpn, [SEARCH_MODULE.path] = T.mod }
end
local function line(pat, from)
    for i = #logs, from or 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end
    return nil
end
local function setup(mineRows)
    tables(mineRows)
    setPaths()
    ALLY.setupDone, ALLY.tries, ALLY.ready, ALLY.ciwsReady, ALLY.wingmenReady = nil, nil, nil, nil, nil
    SR.done = true
    local from = #logs + 1
    ALLY.setup()
    return from
end
local DEF = CFG.shop.items.Airfield.defences
local SHIPCFG = CFG.allies.ships.Aegis

---------------------------------------------------------------------------------------------------- ALLY.setup
print("ALLY.setup: the airfield defences' fire control, search and health")
local from = setup()
local fcsLine = line("allies: the ships' and the airfield's own fire control: ", from)
check(ALLY.ready == true and ALLY.ciwsReady == true and has(line("allies: 8 of 8 rows in DT_NPC", from), "CIWS in"),
      "every ally row in DT_NPC, the CIWS's too (" .. tostring(line("rows in DT_NPC", from)) .. ")")
local mod = T.mod:FindRow("NPC_AIModule_SV_Defence")
check(mod and mod.Radius == DEF.fcs.search_m and mod.bEnableLostTargetInClouds == false
      and has(line("allies: the airfield defences' turrets search 10000 m (NPC_AIModule_SV_Defence, was 6000 m)", from), "not lost in cloud"),
      "the defences' search module: 6000 -> 10000 m, not lost in cloud, logged")
-- the AA guns
local aa = T.fcs:FindRow("NPC_FCS_VehicleAAGun000_SVA_Defence")
local tx = CFG.allies.fcs.time_x
check(T.npc:FindRow("SV_Def_Gepa").NpcFCSId0:ToString() == "NPC_FCS_VehicleAAGun000_SVA_Defence", "SV_Def_Gepa on NPC_FCS_VehicleAAGun000_SVA_Defence")
check(aa and near(aa.CaptureDistance, 2200 * DEF.fcs.range_x) and aa.CaptureDistance == 4400, "AA guns: lock-on 2200 -> 4400 m (was 3520 with the allies' x1.6)")
check(aa and near(aa.ActivationTime, 0.5 * tx * DEF.fcs.lock_x) and near(aa.ShotIntervalTime, 2.0 * tx * DEF.fcs.fire_x)
      and near(aa.RestingTime, 1.0 * tx * DEF.fcs.fire_x) and near(aa.TriggeringTime, 2.0 * tx * DEF.fcs.lock_x),
      string.format("AA guns: the fire-rate boost kept (arm %.3f s, lock %.2f s, %.2f s between, rest %.2f s)", aa.ActivationTime,
                    aa.TriggeringTime, aa.ShotIntervalTime, aa.RestingTime))
check(aa and aa.YawSpeed == 60 and aa.PitchSpeed == 60 and aa.YawAngleMin == -180 and aa.YawAngleMax == 180
      and aa.NpcAIModuleId:ToString() == "NPC_AIModule_SV_Defence" and aa.bEnableLostTargetInClouds == false
      and near(aa.PredictionOffsetTime, 0.8 * CFG.allies.fcs.aa_lead_x),
      "AA guns: turrets 30 -> 60 deg/s, the defences' search, no cloud loss, the AA lead kept")
local aaw = T.wpn:FindRow("AAGUN_Ground_000_SVA_Defence")
check(aa and aa.NpcWeaponId:ToString() == "AAGUN_Ground_000_SVA_Defence" and aaw and aaw.DamageAreaLengthMeters == 4400
      and aaw.DamageAreaRadiusMeters == 30 and near(aaw.MaxSpawnAngle, 0.4) and aaw.LifeTime == 3.0,
      "AA guns' flak: hurts out to 2000 -> 4400 m, 20 -> 30 m round, spread x0.4, its 3 s burst as it was")
check(has(fcsLine, "NPC_FCS_VehicleAAGun000_SVA_Defence (within 2200 -> 4400 m, arm 0.50 -> 0.1")   -- (0.1875: printf's tie)
      and has(fcsLine, " s, lock 2.00 -> 0.75 s, "
                   .. "2.00 -> 0.50 s between, rest 1.00 -> 0.25 s, search NPC_AIModule_SV_Defence, yaw -180..180 at 30.0 -> "
                   .. "-180..180 at 60.0 deg/s, rounds AAGUN_Ground_000_SVA_Defence: hurt out to 2000 -> 4400 m, 20 -> 30 m round)"),
      "the log line: the AA guns' before -> after")
-- the SAM sites
local sam = T.fcs:FindRow("NPC_FCS_VehicleSAM001_SVA_Defence")
local samw = T.wpn:FindRow("SAM_Ground_000_SVA_Defence")
local mc = DEF.fcs.missile
check(sam and sam.CaptureDistance == mc.range_m and mc.range_m == 8000, "SAM sites: lock-on 3000 -> 8000 m (was 4800)")
check(samw and samw.LifeTime == 14 and samw.AccelerationKmph == 600 and samw.SpeedMaxKmph == 3600 and near(samw.MaxRotationAngle, 22.5)
      and samw.HomingReductionInCloud == 0 and sam.NpcWeaponId:ToString() == "SAM_Ground_000_SVA_Defence",
      "SAM missiles: 7.3 -> 14 s, 3000 -> 3600 km/h, +300 -> +600 km/h a second, turns 15 -> 22.5, no cloud loss")
do                                                -- (its reach: from 500 km/h, at that acceleration to that top speed)
    local v0, a, vmax = 500 / 3.6, samw.AccelerationKmph / 3.6, samw.SpeedMaxKmph / 3.6
    local t1 = math.min(samw.LifeTime, (vmax - v0) / a)
    local reach = v0 * t1 + a * t1 * t1 / 2 + vmax * (samw.LifeTime - t1)
    check(reach > 1.4 * sam.CaptureDistance, string.format("SAM missiles reach %.1f km straight out, past the %.0f km lock-on (was %.1f km)",
          reach / 1000, sam.CaptureDistance / 1000, (500 / 3.6 * 7.3 + 300 / 3.6 * 7.3 * 7.3 / 2) / 1000))
end
check(has(fcsLine, "NPC_FCS_VehicleSAM001_SVA_Defence (within 3000 -> 8000 m, arm 2.00 -> 0.75 s, lock 5.00 -> 1.8")
      and has(fcsLine, " s, 5.00 -> 1.25 s between, rest 10.00 -> 2.50 s")
      and has(fcsLine, "missile SAM_Ground_000_SVA_Defence: 7.3 -> 14 s, up to 3000 -> 3600 km/h, +300 -> +600 km/h a second, turns 15.0 -> 22.5"),
      "the log line: the SAM sites' before -> after")
-- the CIWS
local ciwsRow = T.npc:FindRow("SV_Def_Ciws")
local cw = T.fcs:FindRow("NPC_FCS_VesselCIWS000_SVA_Defence")
local cww = T.wpn:FindRow("CIWS_Vessel_000_SVA_Defence")
check(ciwsRow and ciwsRow.NpcFCSId0:ToString() == "NPC_FCS_VesselCIWS000_SVA_Defence"
      and has(line("allies: the CIWS's gun on NPC_FCS_VesselCIWS000: set", from), "boosted"),
      "SV_Def_Ciws: its gun on the Mk 15's fire control (fcs_row), then the airfield's boost; logged")
check(cw and cw.CaptureDistance == 5000 and cw.YawAngleMin == -180 and cw.YawAngleMax == 180 and cw.YawSpeed == 75
      and near(cw.PredictionOffsetTime, 0.8 * CFG.allies.fcs.aa_lead_x) and cw.NpcAIModuleId:ToString() == "NPC_AIModule_SV_Defence",
      "CIWS: lock-on 2500 -> 5000 m, all the way round (a ship mount's +-60 on land), 37.5 -> 75 deg/s, the AA lead, the search")
check(cww and near(cww.LifeTime, 6.0) and cw.NpcWeaponId:ToString() == "CIWS_Vessel_000_SVA_Defence",
      "CIWS rounds: 3.0 -> 6.0 s of flight (x the range's growth)")
check(has(fcsLine, "NPC_FCS_VesselCIWS000_SVA_Defence (within 2500 -> 5000 m") and has(fcsLine, "yaw -60..60 at 37.5 -> -180..180 at 75.0 deg/s")
      and has(fcsLine, "rounds CIWS_Vessel_000_SVA_Defence: 3.0 -> 6.0 s of flight"), "the log line: the CIWS's before -> after")
-- health
for _, c in ipairs({ { "SV_Def_Gepa", "AA GUN" }, { "SV_Def_Avng", "SAM SITE" }, { "SV_Def_Ciws", "CIWS" } }) do
    local r = T.npc:FindRow(c[1])
    check(r and r.MaxHealthDifference == 40 and line(string.format("allies: the airfield's %s +40 HP (%s's MaxHealthDifference now 40)", c[2], c[1]), from),
          c[1] .. ": +40 HP (the game's 20 -> 60), logged")
    check(r and r.NpcAIModuleId:ToString() == "NPC_AIModule_SV_Defence", c[1] .. ": the defences' search module on its row")
end
-- the Aegis: as before
local mk15 = T.fcs:FindRow("NPC_FCS_VesselCIWS000_SVA_Aegis")
local mk15w = T.wpn:FindRow("CIWS_Vessel_000_SVA_Aegis")
check(mk15 and mk15.CaptureDistance == 2500 * SHIPCFG.fcs.range_x and mk15.YawAngleMin == -60 and mk15.YawSpeed == 37.5
      and mk15w and mk15w.LifeTime == 3.0 and T.npc:FindRow("SV_Ally_Aegis").MaxHealthDifference == SHIPCFG.health_add
      and T.mod:FindRow("NPC_AIModule_SV_Aegis") and T.mod:FindRow("NPC_AIModule_SV_Aegis").Radius == SHIPCFG.fcs.search_m,
      "the Aegis's Mk 15 its own row as before (x2 range, +-60, rounds 3 s), its hull +300, its 25 km search")

print("ALLY.setup: the CIWS's fire control choices, a container without its row")
DEF.ciws.fcs_row = "none"
from = setup()
check(T.npc:FindRow("SV_Def_Ciws").NpcFCSId0:ToString() == "None" and T.fcs:FindRow("NPC_FCS_VesselCIWS000_SVA_Defence") == nil
      and line("allies: the CIWS fires on its blueprint's own fire control (fcs_row none", from) and ALLY.ciwsReady,
      "fcs_row none: its blueprint's own fire control, logged")
DEF.ciws.fcs_row = "NPC_FCS_NotThere000"
from = setup()
check(T.npc:FindRow("SV_Def_Ciws").NpcFCSId0:ToString() == "None"
      and line("allies: the CIWS's gun on NPC_FCS_NotThere000: NOT set (no such row in DT_NPC_FCS)", from),
      "a row DT_NPC_FCS hasn't: not set, logged")
DEF.ciws.fcs_row = "NPC_FCS_VesselCIWS000"
local noCiws = {}
for _, r in ipairs(MINE_ROWS) do if r[1] ~= "SV_Def_Ciws" then noCiws[#noCiws + 1] = r end end
from = setup(noCiws)
check(ALLY.ready == true and ALLY.ciwsReady == false and has(line("rows in DT_NPC", from), "CIWS NOT in")
      and has(line("rows in DT_NPC", from), "missing: SV_Def_Ciws"), "a container without the CIWS row: the rest sold, CIWS NOT in")

---------------------------------------------------------------------------------------------------- the STORE
print("the STORE: the DEFENCES page's CIWS row")
D = { round = 3, state = "wait", now = 100, up = {}, flown = {}, queue = {}, events = {}, orders = {} }
RUN.credits, RUN.spent, RUN.bought, RUN.msg, RUN.defences, RUN.offerShown = 100000, 0, {}, {}, nil, nil
local tick = 0
local function shop(...)
    for _, r in ipairs({ ... }) do requests[#requests + 1] = "SV_Buy_" .. r end
    RUN.dirty = true
    tick = tick + 1
    shopTick(tick)
    tick = tick + 1
    RUN.dirty = true
    shopTick(tick)
end
shop()
check(texts.SV_Shop_Ciws == "BUILD CIWS   NOT AVAILABLE." or texts.SV_Shop_Ciws == "BUILD CIWS",
      "the CIWS row while its row isn't in DT_NPC: " .. tostring(texts.SV_Shop_Ciws))
check(has(texts.SV_Shop_Ciws_Help, "Not in this game's tables"), "... its help says why: " .. tostring(texts.SV_Shop_Ciws_Help))
local spent0 = RUN.spent
shop("Ciws")
check(#spawned == 0 and RUN.spent == spent0 and RUN.msg.Ciws == "NOT AVAILABLE.", "... and isn't sold: " .. tostring(RUN.msg.Ciws))
spawned = {}
setup()                                           -- (the CIWS's row in: sold)
shop()
check(texts.SV_Shop_Ciws == "BUILD CIWS   6000 Z" and has(texts.SV_Shop_Ciws_Help, "Builds a CIWS by the runway")
      and has(texts.SV_Shop_Ciws_Help, "CIWS 0 of 4 up"), "the CIWS row: BUILD CIWS 6000 Z (" .. tostring(texts.SV_Shop_Ciws_Help) .. ")")
check(texts.SV_Store_TitleDefences and has(texts.SV_Store_TitleDefences, "AIRFIELD STORE: DEFENCES") and texts.SV_Store_ToDefences == "DEFENCES >"
      and has(texts.SV_Store_ToDefences_Help, "CIWS"), "the DEFENCES page's title and the AIRFIELD page's DEFENCES > row")
local prices = {}
for k = 1, 4 do
    local before = RUN.credits
    shop("Ciws")
    prices[k] = before - RUN.credits
end
check(table.concat(spawned, ",") == "SV_Unit_Ciws_A,SV_Unit_Ciws_B,SV_Unit_Ciws_C,SV_Unit_Ciws_D",
      "four bought: its units in order (" .. table.concat(spawned, ",") .. ")")
check(prices[1] == 6000 and prices[2] == 6720 and prices[3] == math.floor(6000 * 1.12 ^ 2 / 10 + 0.5) * 10
      and prices[4] == math.floor(6000 * 1.12 ^ 3 / 10 + 0.5) * 10, "each dearer by raise 1.12: " .. table.concat(prices, ", "))
check(line("shop: Ciws: CIWS BUILT for 6000 (SV_Unit_Ciws_A).") ~= nil and line("shop: text error") == nil, "a purchase logged: CIWS BUILT for 6000 (SV_Unit_Ciws_A)")
shop("Ciws")
check(#spawned == 4 and RUN.msg.Ciws == "ALL BUILT." and texts.SV_Shop_Ciws == "BUILD CIWS: ALL BUILT", "all four up: ALL BUILT")
check(RUN.defences.bought.ciws == 4 and RUN.defences.built == 4, "counted as defences built")
check(has(texts.SV_Shop_AAGun_Help, "CIWS 4 of 4 up") and texts.SV_Shop_AAGun == "BUILD AA GUN   4000 Z", "the AA gun row's help counts them too")
-- the old fourth row (no STORE pages): its turn order reaches the CIWS
spawned, alive, RUN.defences = {}, {}, { built = 3, bought = {} }
AF.hp, AF.max, AF.down = CFG.airfield.hp, CFG.airfield.hp, false
RUN.acHp = 100
survivalPC = nil
shop()
check(texts.SV_Shop_Airfield == "BUILD CIWS   6000 Z", "the old fourth row, 4th in turn (order[4] = ciws): " .. tostring(texts.SV_Shop_Airfield))
for _, u in ipairs(DEF.ciws.units) do alive[u] = 1 end
shop()
check(texts.SV_Shop_Airfield == "BUILD AA GUN   4000 Z", "... every CIWS up: the next kind (" .. tostring(texts.SV_Shop_Airfield) .. ")")

---------------------------------------------------------------------------------------------------- the ALLIES row, losses, repairs, kills
print("ALLY.tick / hudLine: the CIWS on the ALLIES row; a lost one; repairs; kill credit")
alive = { SV_Unit_AAGun_A = 1, SV_Unit_Ciws_A = 1, SV_Unit_Ciws_B = 1 }
ALLY.run = nil
local R = ALLY.state()
from = #logs + 1
ALLY.tick(200)
check(R.defCount.aa == 1 and R.defCount.sam == 0 and R.defCount.ciws == 2 and ALLY.hudLine():find("AA 1  SAM 0  CIWS 2", 1, true),
      "the ALLIES row: " .. tostring(ALLY.hudLine()))
alive.SV_Unit_Ciws_B = 0
callouts = {}
ALLY.tick(203)
check(callouts[1] == "CIWS LOST / " .. CFG.allies.text.def_lost_sub and line("allies: CIWS (SV_Unit_Ciws_B) lost in round 3", from)
      and has(ALLY.hudLine(), "CIWS 1"), "a CIWS lost: CIWS LOST, logged, the row counts 1")
alive = { SV_Unit_AAGun_A = 1 }
ALLY.tick(206)
check(ALLY.hudLine():find("AA 1  SAM 0", 1, true) and not has(ALLY.hudLine(), "CIWS"), "none up: no CIWS on the row (" .. ALLY.hudLine() .. ")")
local lvl = "/Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel."
local c1 = { full = "BP_GR033_ciws_CP_Ally_C " .. lvl .. "BP_GR033_ciws_CP_Ally_C_1", addr = addr(), HealthInternal = 200, MaxHealth = 60 }
local g1 = { full = "BP_GR002_gepa_CP_C " .. lvl .. "BP_GR002_gepa_CP_C_1", addr = addr(), HealthInternal = 600, MaxHealth = 60 }
objects = { BP_GR033_ciws_CP_Ally_C = { c1 }, BP_GR002_gepa_CP_C = { g1 } }
check(ALLY.repairDefences() == 1 and c1.HealthInternal == 600 and g1.HealthInternal == 600, "repairs: a damaged CIWS back to full (200 -> 600), a whole AA gun left")
-- the defences' health on the row: a defence that's gone or down comes off the cached list at once and is never read
-- again (the co-op runs of 2026-10-30: two joiners crashed reading the host's old defences, taken down and spawned again
-- at the same count, so the list was kept)
do
    local reads = {}
    local function defence(cls, hp)
        local o = { full = cls .. " " .. lvl .. cls .. "_" .. addr(), addr = addr(), hp = hp, MaxHealth = 60 }
        o.K2_GetActorLocation = function() return { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = 0 } end
        return setmetatable(o, { __index = function(t, k)
            if k == "HealthInternal" then reads[t] = (reads[t] or 0) + 1; return rawget(t, "hp") end
        end })
    end
    local d1, d2 = defence("BP_GR033_ciws_CP_Ally_C", 600), defence("BP_GR033_ciws_CP_Ally_C", 300)
    objects = { BP_GR033_ciws_CP_Ally_C = { d1, d2 } }
    alive = { SV_Unit_Ciws_A = 1, SV_Unit_Ciws_B = 1 }
    ALLY.run = nil
    local R = ALLY.state()
    ALLY.tick(700)
    check(R.defHp == 75 and #R.defActors == 2, "the row's defences' health: 75% (600 and 300 of 600): " .. tostring(R.defHp))
    d2.gone = true                                   -- (taken down and spawned again: its old actor gone, the count the same)
    local d3 = defence("BP_GR033_ciws_CP_Ally_C", 600)
    objects = { BP_GR033_ciws_CP_Ally_C = { d1, d3 } }
    reads = {}
    R.checkAt = 0
    ALLY.tick(702)
    check(not reads[d2] and #R.defActors == 1 and R.defActorsAt == 0, "an old actor gone: never read, off the list, the list found again next time")
    R.checkAt = 0
    ALLY.tick(704)
    check(#R.defActors == 2 and R.defActors[1] ~= d2 and R.defActors[2] ~= d2 and R.defHp == 100, "... found again: the new one in, 100%")
    d1.hp = 0
    R.checkAt = 0
    ALLY.tick(706)
    check(#R.defActors == 1 and R.defActors[1] == d3, "one down (health 0): off the list too")
    ALLY.forgetActors()
    check(R.defActors == nil, "ALLY.forgetActors: the cached list dropped (a joiner's teardown)")
    objects, alive = {}, {}
    ALLY.run = nil
end
check(KILL.side({ full = "BP_GR033_ciws_CP_Ally_C_3", addr = addr() }, 9) == "defences"
      and KILL.side({ full = "BP_BA002_alcn_ciws_Base_C_1", addr = addr() }, 9) ~= "defences"
      and KILL.side({ full = "BP_GR002_gepa_CP_C_2", addr = addr() }, 9) == "defences",
      "kill credit: the CIWS's is the defences', the ALICORN's CIWS isn't")

---------------------------------------------------------------------------------------------------- co-op: the host builds a joiner's
print("co-op: a joiner's allies and defences are built by the host (the co-op run of 2026-10-30: none of it synced)")
do
    local asked, refunds, orders = {}, {}, {}
    local airborne = {}
    COOP = { client = function() return true end, host = function() return false end,
             askBuild = function(name, price, kind) asked[#asked + 1] = { name = name, price = price, kind = kind }
                 return true, "ASKED THE HOST: IT BUILDS IT FOR EVERYONE." end,
             refund = function(slot, price, why) refunds[#refunds + 1] = { slot = slot, price = price, why = why }; return true end,
             airborne = function(slot) return airborne[slot] == true end,
             orderChanged = function(o, how) orders[#orders + 1] = o .. "/" .. tostring(how) end }
    -- the joiner: nothing spawned, the host asked, paid now
    D = { round = 3, state = "wait", now = 100, up = {}, flown = {}, queue = {}, events = {}, orders = {} }
    RUN.credits, RUN.spent, RUN.bought, RUN.msg, RUN.defences, RUN.offerShown = 100000, 0, {}, {}, nil, nil
    spawned, alive = {}, {}
    ALLY.run = nil
    setup()
    shop("Ciws")
    check(#spawned == 0 and #asked == 1 and asked[1].name == "Ciws" and asked[1].price == 6000 and asked[1].kind == "ciws"
          and RUN.credits == 94000 and RUN.msg.Ciws == "ASKED THE HOST: IT BUILDS IT FOR EVERYONE.",
          "joiner: BUILD CIWS asks the host (Ciws, 6000, ciws), nothing built here, 6000 paid")
    shop("Wingmen")
    check(#spawned == 0 and asked[2] and asked[2].name == "Wingmen" and asked[2].kind == nil and RUN.credits == 89000
          and next(ALLY.state().up) == nil, "joiner: WINGMEN asks the host too, no flight of its own queued here")
    shop("ShipAegis")
    check(#spawned == 0 and asked[3] and asked[3].name == "ShipAegis", "joiner: the AEGIS asks the host too")
    -- the host: builds it with nothing charged
    COOP.client = function() return false end
    COOP.host = function() return true end
    RUN.credits, RUN.spent = 50000, 0
    spawned, alive = {}, {}
    local ok, msg = shopBuildFor(2, "Ciws", 6000, "ciws")
    check(ok and spawned[1] == "SV_Unit_Ciws_A" and RUN.credits == 50000 and msg == "CIWS BUILT for 6000 (SV_Unit_Ciws_A).",
          "host: player 3's CIWS built here (SV_Unit_Ciws_A), nothing charged: " .. tostring(msg))
    for _, u in ipairs(DEF.ciws.units) do alive[u] = 1 end
    ok, msg = shopBuildFor(2, "Ciws", 6000, "ciws")
    check(not ok and msg == "ALL BUILT.", "host: every CIWS up: refused (" .. tostring(msg) .. ")")
    ok, msg = shopBuildFor(2, "AAGun", 4000, nil)
    check(ok and spawned[#spawned] == DEF.aa.units[1], "host: an AA gun by its row's own kind")
    ok, msg = shopBuildFor(2, "Rearm", 100, nil)
    check(not ok, "host: anything but an ally or a defence refused (" .. tostring(msg) .. ")")
    ok, msg = shopBuildFor(2, "ShipAegis", 20000, nil)
    local R = ALLY.state()
    local ship = SHIPCFG.units[1]
    check(ok and spawned[#spawned] == ship and R.up[ship] and R.up[ship].buyer == 2, "host: player 3's AEGIS at sea, theirs (buyer 3)")
    -- their flight: takes off once they're airborne, whatever the host is doing
    ok, msg = shopBuildFor(2, "Wingmen", 5000, nil)
    local wu
    for u, s in pairs(R.up) do if s.kind == "air" then wu = u end end
    check(ok and wu and R.up[wu].buyer == 2 and R.up[wu].queued, "host: player 3's WINGMEN queued for them")
    onAirfield = false                                    -- (the host flying: not what it waits for)
    R.nextTakeoff, R.up[wu].at = 0, 300
    local n0 = #spawned
    ALLY.tick(300)
    check(#spawned == n0 and R.up[wu].queued, "host: not off while player 3 isn't airborne")
    airborne[2] = true
    ALLY.tick(301)
    check(spawned[#spawned] == wu and not R.up[wu].queued, "host: off once player 3 is airborne")
    R.up[wu] = { kind = "air", ally = "wingmen", queued = true, at = 310, price = 5000, buyer = 2 }
    airborne[2] = false
    R.nextTakeoff = 0
    ALLY.tick(399)
    check(R.up[wu].queued, "host: ... 89 s on, still waiting")
    R.nextTakeoff = 0
    ALLY.tick(400)
    check(not R.up[wu].queued, "host: ... 90 s on, off anyway (they may never take off: a link lost)")
    -- one that never comes: refunded to the joiner, not the host
    R.up[wu] = { kind = "air", ally = "wingmen", queued = true, at = 400, price = 5000, buyer = 2 }
    airborne[2] = true
    local realSpawn = SV_Spawn
    SV_Spawn = function() return -7 end
    local cr = RUN.credits
    for t = 0, 3 do R.nextTakeoff = 0; ALLY.tick(402 + t * 6) end
    SV_Spawn = realSpawn
    check(R.up[wu] == nil and refunds[1] and refunds[1].slot == 2 and refunds[1].price == 5000 and RUN.credits == cr,
          "host: their flight that never took off: 5000 back to player 3, not here")
    -- the orders: told to co-op
    ALLY.nextOrder("store")
    check(orders[1] and orders[1]:find("/store$"), "the orders changed: told to co-op (" .. tostring(orders[1]) .. ")")
    ALLY.nextOrder("coop", "defend")
    check(ALLY.order() == "defend", "an order set from co-op: defend")
    -- the room's allies for the joiners' ALLIES rows (ALLY.roomCode in "rnd"; a joiner's own R.up stays empty)
    R.up = { [wu] = { kind = "air", ally = "wingmen", at = 500, buyer = 2 }, [ship] = { kind = "ship", key = "Aegis", at = 500 } }
    alive[wu], alive[ship] = 2, 1
    check(ALLY.roomCode() == "w2s1", "host: the room's allies summed up: " .. ALLY.roomCode())
    R.up[wu].queued = true
    check(ALLY.roomCode() == "w0s1", "host: a flight waiting to take off counts 0: " .. ALLY.roomCode())
    R.up[wu].queued = nil
    local room
    COOP.roomAllies = function() return room end
    local mine = ALLY.run
    ALLY.run = nil
    room = { w = 2, s = 1 }
    local row = ALLY.hudLine()
    check(has(row, CFG.allies.wingmen.name .. " 2") and has(row, "SHIPS 1") and not has(row, CFG.allies.aircraft.name .. " "),
          "joiner: the ALLIES row shows the host's flights and ships: " .. tostring(row))
    room = nil
    check(ALLY.hudLine() == nil, "joiner: no word from the host, nothing of its own: no row")
    ALLY.run = mine
    COOP.roomAllies = nil
    -- COVER on a joiner's flight: that joiner covered while their real plane flies here, else you
    local covered, real = {}, { [2] = true }
    COOP.realTarget = function(s) return real[s] and { addr = 9 } or nil end
    COOP.coverFor = function(slot, objs) covered[#covered + 1] = { slot = slot, n = #objs }; return #objs, 1.5 end
    local rawFlags = svFlags
    svFlags = function() return { ["SV_AllyAir" .. wu:sub(-1)] = 2 } end
    R.planes = { { obj = { addr = 71 }, unit = wu, name = "w1" }, { obj = { addr = 72 }, unit = wu, name = "w2" },
                 { obj = { addr = 73, gone = true }, unit = wu, name = "w3" } }
    ALLY.nextOrder("coop", "cover")
    events, covered, from = {}, {}, #logs + 1
    R.checkAt = 0
    ALLY.tick(600)
    local x = wu:sub(-1)
    check(events[#events] == "RE_SV_AllyHunt" .. x and covered[1] and covered[1].slot == 2 and covered[1].n == 2
          and line("ordered to cover player 3 (who bought it)", from) and line("covering player 3: 2 of 2 planes", from),
          "cover, player 3 flying: the hunt's area (" .. tostring(events[#events]) .. ") and its 2 planes onto the enemies near them")
    events, covered = {}, {}
    R.checkAt, R.coverAt = 0, 0
    ALLY.tick(610)
    check(#events == 0 and #covered == 1, "... 10 s on: retargeted, no event again (" .. table.concat(events, ",") .. ")")
    real[2] = nil
    events, covered, from = {}, {}, #logs + 1
    R.checkAt, R.coverAt = 0, 0
    ALLY.tick(620)
    check(events[#events] == "RE_SV_AllyCover" .. x and #covered == 0 and line("ordered to cover you (player 3's plane isn't flying here)", from),
          "cover, player 3 down / landed: it covers you (" .. tostring(events[#events]) .. ")")
    events = {}
    R.checkAt, R.coverAt = 0, 0
    ALLY.tick(630)
    check(events[#events] == "RE_SV_AllyCover" .. x, "... and again every cover_every_s, as before")
    R.up[wu].buyer = nil
    real[2] = true
    events, covered = {}, {}
    R.checkAt, R.coverAt = 0, 0
    ALLY.tick(640)
    check(events[#events] == "RE_SV_AllyCover" .. x and #covered == 0, "the host's own flight: covers the host as before")
    svFlags = rawFlags
    R.planes, R.up = {}, {}
    COOP = nil
    onAirfield = true
end

---------------------------------------------------------------------------------------------------- the build in step
print("the build in step")
do
    local bs = readAll(MOD .. "/../../../tools/build_survival.py")
    check(has(bs, "('SV_StoreDefences', 'StoreDefences', 'SV_Store_TitleDefences',") and has(bs, "['AAGun', 'SAM', 'Ciws', 'VoidWatcher', ('SVStoreToDocks', 'SV_Store_ToDocks', '22'), 'takeoff']")
          and has(bs, "('SVStoreToDefences', 'SV_Store_ToDefences', '25')"), "build_survival.py: the DEFENCES page (25, VOID WATCHER 1 its fourth row) and AIRFIELD's DEFENCES > row")
    local last = SHOP.menuRows[#SHOP.menuRows]
    check(#SHOP.menuRows == 6 and last.row == "SVStoreDefences" and last.id == "SV_StoreDefences" and last.index == 25
          and SHOP.icons.Ciws and SHOP.icons["25"], "sv_flights: SHOP.menuRows' sixth page at 25, the CIWS's and its row's icons")
    check(has(bs, "bp[2][1] == 'BP_GR033_ciws_CP_Ally_C'") and has(readAll(MOD .. "/Scripts/sv_allies.lua"), '"BP_GR033_ciws_CP_Ally_C"'),
          "the model row's blueprint the build checks is the class repairs and health look for")
    check(CFG.shop.items.Ciws and CFG.shop.items.Ciws.role == "ciws" and #DEF.ciws.units == 4 and DEF.ciws.price == 6000,
          "CFG: the STORE's Ciws item, 4 units, 6000 Z")
end

---------------------------------------------------------------------------------------------------- VOID WATCHER 1, SNIPER
-- (user, 2026-10-31: Mission 28's AWACS "Take off from the airfield as a purchasable ally", "Rename it too VOID
-- WATCHER 1", "give it's ESM a huge boost in range and have it orbit around the airfield"; "rename VIPER to SNIPER and
-- change their standard missiles to LAAM's")
print("VOID WATCHER 1 and SNIPER")
do
    local AW = CFG.allies.awacs
    LB = LB or {}
    if not LB.stat then LB.stat = function() end end    -- (sv_leaderboard's, not loaded here: an ally bought counts)
    FCS_ROWS[#FCS_ROWS + 1] = { "NPC_FCS_PlaneFlr100", { NpcWeaponId = NONE, MagazineCapacity = 10, CaptureDistance = 1500.0,
        CaptureAngleRange = 60.0, ActivationTime = 0.5, TriggeringTime = 1.0, ShotIntervalTime = 5.0, RestingTime = 5.0 } }
    FCS_ROWS[#FCS_ROWS + 1] = { "NPC_FCS_MS28ESM000", { NpcWeaponId = NONE, MagazineCapacity = 10, CaptureDistance = 6000.0,
        CaptureAngleRange = 60.0, ActivationTime = 2.0, TriggeringTime = 15.0, ShotIntervalTime = 15.0, RestingTime = 30.0 } }
    local rows = {}
    for _, r in ipairs(MINE_ROWS) do rows[#rows + 1] = r end
    -- (its ESM in slot 3, as OP0005_e767_MS28's: NpcFCSId1 and 2 empty; WN_WEAPON_4, hard rule 40)
    rows[#rows + 1] = { AW.row, npcRow("NPC_FCS_PlaneFlr100", { NpcFCSId3 = FName("NPC_FCS_MS28ESM000") }) }
    -- its model row: none in the game's DT_NPC_Model yet, Survival's in DT_SV_ModelRows
    local function setupAwacs(withModel)
        tables(rows)
        setPaths()
        T.mt = dt("DT_NPC_Model")
        T.mr = dt("DT_SV_ModelRows", withModel and { { AW.model, { GameObjectDisplayName01 = "ContainerAircraft_Name_e767" } } } or {})
        paths[ACE.model_table], paths[ACE.model_rows] = T.mt, T.mr
        ALLY.setupDone, ALLY.tries, ALLY.ready, ALLY.ciwsReady, ALLY.wingmenReady, ALLY.awacsReady = nil, nil, nil, nil, nil, nil
        SR.done = true
        local f = #logs + 1
        ALLY.setup()
        return f
    end
    setupAwacs(false)
    check(ALLY.awacsReady == false and line("allies: VOID WATCHER 1's model SV_Model_VoidWatcher NOT added") ~= nil,
          "its model row missing: not sold (its row would name a model the game hasn't)")
    local from = setupAwacs(true)
    local r = T.npc:FindRow(AW.row)
    local esm = T.fcs:FindRow("NPC_FCS_MS28ESM000_SVA")
    check(T.mt:FindRow(AW.model) and has(line("allies: VOID WATCHER 1's model SV_Model_VoidWatcher in DT_NPC_Model", from), "in DT_NPC_Model"),
          "its model row (Magnolia's, the plain E-767 name: no MAGNOLIA tag) into DT_NPC_Model")
    check(ALLY.awacsReady == true and r and r.NpcFCSId3:ToString() == "NPC_FCS_MS28ESM000_SVA" and has(line("rows in DT_NPC", from), "VOID WATCHER 1 in"),
          "its row in DT_NPC, its ESM (slot 3) on fire control of its own (" .. tostring(line("rows in DT_NPC", from)) .. ")")
    check(has(readAll(MOD .. "/../../../tools/survival_events.py"), "AWACS_ESM_SLOT = 'WN_WEAPON_4'"),
          "the build fires its ESM's slot: WN_WEAPON_4 (slot 3; 0.73.33's WN_WEAPON_2 was an empty one)")
    check(esm and esm.CaptureDistance == AW.esm.capture_m and esm.RestingTime == 0.5 and esm.ShotIntervalTime == 0.5
          and esm.CaptureAngleRange == 180 and has(line("allies: VOID WATCHER 1's ESM on NPC_FCS_MS28ESM000_SVA: within 60000 m", from), "ready again"),
          "its ESM's fire control: within 6000 -> 60000 m, all round, ready again in 0.5 s (rest 30 s stock)")
    check(texts[AW.name_key] == "VOID WATCHER 1" and texts[CFG.allies.wingmen.name_key] == "SNIPER", "the names: VOID WATCHER 1, SNIPER (was VIPER)")
    check(has(readAll(MOD .. "/../../../tools/survival_events.py"), "ALLY_WINGMEN_MISSILE = ('NPC_FCS_PlaneMsl000', 'NPC_FCS_PlaneLAAM000')")
          and has(readAll(MOD .. "/../../../tools/build_survival.py"), "if npc == survival_events.ALLY_WINGMEN_NPC:      # SNIPER's LAAMs"),
          "SNIPER's LAAMs written into Survival's copy of the F-16C row at build time (the stock row as shipped)")
    -- the STORE row
    D = { round = 3, state = "wait", now = 100, up = {}, flown = {}, queue = {}, events = {}, orders = {} }
    RUN = RUN or {}
    RUN.credits, RUN.spent, RUN.msg, RUN.bought = 50000, 0, RUN.msg or {}, RUN.bought or {}
    ALLY.run = nil
    alive[AW.unit] = 0
    shop()
    check(has(texts.SV_Shop_VoidWatcher, "VOID WATCHER 1: E-767 AWACS   12000 Z") and has(texts.SV_Shop_VoidWatcher_Help, "orbits it")
          and has(texts.SV_Shop_VoidWatcher_Help, "(25 km)"), "the STORE's row: 12000 Z, its help (" .. tostring(texts.SV_Shop_VoidWatcher) .. ")")
    -- bought: it waits for you to take off
    local spent0 = RUN.spent
    shop("VoidWatcher")
    local R = ALLY.state()
    local msg = RUN.msg.VoidWatcher
    check(has(msg, "TAKES OFF ONCE YOU'RE AIRBORNE") and RUN.spent == spent0 + 12000 and R.up[AW.unit] and R.up[AW.unit].queued,
          "bought for 12000: it waits (" .. tostring(msg) .. ")")
    shop("VoidWatcher")
    check(texts.SV_Shop_VoidWatcher == "VOID WATCHER 1: E-767 AWACS" and RUN.msg.VoidWatcher == "VOID WATCHER 1 IS UP."
          and RUN.spent == spent0 + 12000, "one at a time: no price on its row, a second press says it's up, nothing charged")
    R.nextTakeoff = 0
    onAirfield = true
    local n0 = #spawned
    D.now = 200; ALLY.tick(200)
    check(#spawned == n0, "still at the airfield: on the ground")
    onAirfield = false
    local c0 = #callouts
    D.now = 201; ALLY.tick(201)
    check(spawned[#spawned] == AW.unit and not R.up[AW.unit].queued and has(callouts[#callouts], "VOID WATCHER 1 CLEARED FOR TAKEOFF")
          and has(callouts[#callouts], "ESM OVER THE AIRFIELD"), "you airborne: it taxis out (" .. tostring(callouts[#callouts]) .. ")")
    -- its ESM: only once it's airborne, then every every_s
    local air = 0
    local rawFlags = svFlags
    svFlags = function() return { SV_AwacsAir = air } end
    local function esmCount() local k = 0; for _, e in ipairs(events) do if e == AW.esm.event then k = k + 1 end end; return k end
    local e0 = esmCount()
    D.now = 205; ALLY.tick(205)
    check(esmCount() == e0, "on its takeoff roll: no ESM yet")
    air = 1
    D.now = 206; ALLY.tick(206)
    D.now = 210; ALLY.tick(210)
    check(esmCount() == e0 + 1, "airborne: its ESM fired (RE_SV_AwacsEsm), once")
    D.now = 206 + AW.esm.every_s; ALLY.tick(D.now)
    check(esmCount() == e0 + 2, "every_s (20 s) on: again")
    -- each ESM field of its class: its range and time; another class's left as it is
    local field = { full = "BP_wp_esm_MS28_C /Game/Maps/PL_SurvivalMode:PersistentLevel.BP_wp_esm_MS28_C_1", addr = addr(),
                    SupportEffectRangeMeter = 3200, EffectRangeMeter = 3200, LifeTime = 15 }
    local other = { full = "BP_wp_ecm_a0_C /Game/Maps/PL_SurvivalMode:PersistentLevel.BP_wp_ecm_a0_C_1", addr = addr(),
                    SupportEffectRangeMeter = 3200, EffectRangeMeter = 3200, LifeTime = 15 }
    ALLY.esmNew = { field, other }
    local l0 = #logs
    D.now = D.now + 0.25; ALLY.tick(D.now)
    check(field.SupportEffectRangeMeter == 25000 and field.EffectRangeMeter == 25000 and field.LifeTime == 24
          and has(line("allies: VOID WATCHER 1's ESM field BP_wp_esm_MS28_C_1: support range 3200 -> 25000 m", l0), "life 15 -> 24 s"),
          "its ESM field: 3200 -> 25000 m, 15 -> 24 s (an instance's; logged)")
    check(other.SupportEffectRangeMeter == 3200 and other.LifeTime == 15, "an ECM field of another class: as it was")
    svFlags = rawFlags
    -- the ALLIES row and the room's code
    check(has(ALLY.hudLine() or "", "VOID WATCHER 1") and not has(ALLY.hudLine() or "", "VOID WATCHER 1 1"),
          "the ALLIES row: VOID WATCHER 1 by its name (" .. tostring(ALLY.hudLine()) .. ")")
    check(ALLY.roomCode() == "v1", "co-op: the room's code v1 (" .. tostring(ALLY.roomCode()) .. ")")
    -- shot down
    alive[AW.unit] = 0
    D.now = D.now + 10; R.checkAt = 0; ALLY.tick(D.now)
    check(R.up[AW.unit] == nil and has(callouts[#callouts], "VOID WATCHER 1 FLIGHT LOST"), "shot down: lost, the STORE can send another")
    onAirfield = true                                 -- (the STORE's texts: at the airfield)
    shop()
    check(has(texts.SV_Shop_VoidWatcher, "12000 Z"), "... and sells it again (" .. tostring(texts.SV_Shop_VoidWatcher) .. ")")
    -- co-op: a joiner's purchase, built here by the host, takes off once that joiner is airborne (else 90 s on)
    COOP = COOP or {}
    local rawAir, rawRefund = COOP.airborne, COOP.refund
    local joinerUp = false
    COOP.airborne = function(slot) return slot == 2 and joinerUp end
    COOP.refund = function() end
    local okJ, msgJ = shopBuildFor(2, "VoidWatcher", 12000, nil)
    check(okJ and R.up[AW.unit] and R.up[AW.unit].buyer == 2 and R.up[AW.unit].queued and has(line("bought for player 3", from), "they're airborne"),
          "co-op: player 3's VOID WATCHER 1 built here, for them (" .. tostring(msgJ) .. ")")
    R.nextTakeoff = 0
    local n1 = #spawned
    D.now = D.now + 5; ALLY.tick(D.now)
    check(#spawned == n1, "... it waits while player 3 is at their airfield")
    joinerUp = true
    D.now = D.now + 1; ALLY.tick(D.now)
    check(spawned[#spawned] == AW.unit and not R.up[AW.unit].queued, "... and takes off once they're airborne")
    COOP.airborne, COOP.refund = rawAir, rawRefund
    alive[AW.unit] = 0
    D.now = D.now + 10; R.checkAt = 0; ALLY.tick(D.now)
    -- off: not sold
    AW.enabled = false
    shop("VoidWatcher")
    check(texts.SV_Shop_VoidWatcher == "VOID WATCHER 1: E-767 AWACS" and RUN.msg.VoidWatcher == "NOT AVAILABLE.",
          "[allies.awacs] enabled = false: not sold (" .. tostring(RUN.msg.VoidWatcher) .. ")")
    AW.enabled = true
end

print(fails == 0 and "defences test: all passed" or ("defences test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
