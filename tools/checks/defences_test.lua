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
--   the build in step: build_survival.py's DEFENCES page and model check, sv_flights' SHOP.menuRows and icons;
--   (0.73.78, plan G5) VOID WATCHER 1's limits: its 9 km ESM pulse, x1.25 a purchase (a co-op joiner's ask at the
--     room's price), 3 rounds of service then home (RE_SV_AwacsHome, taken off out of the way, SV_Recycle, sold again),
--     the round's strike flight after it and back on you.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
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
    -- (the Aegis's Mk 45 and Mk 41, and the ground flak gun the ships' AA mounts go on: 0.73.52)
    { "NPC_FCS_VesselAAGun000", { NpcAIModuleId = FName("NPC_AIModule_Turret000"), NpcWeaponId = FName("AAGUN_Vessel_000"),
      MagazineCapacity = 10, PredictionOffsetTime = 0.8, CaptureDistance = 2200.0, CaptureAngleRange = 30.0, ActivationTime = 0.5,
      TriggeringTime = 3.0, TriggerCount = 1, ShotIntervalTime = 3.0, RestingTime = 1.0, bEnableLostTargetInClouds = true,
      YawSpeed = 30.0, YawAngleMin = -110.0, YawAngleMax = 90.0, PitchSpeed = 30.0, PitchAngleMin = 0.0, PitchAngleMax = 85.0 } },
    { "NPC_FCS_FlakGun000", { NpcAIModuleId = FName("NPC_AIModule_Turret100"), NpcWeaponId = FName("FlakGun_000"),
      MagazineCapacity = 10, PredictionOffsetTime = 5.0, CaptureDistance = 15000.0, CaptureAngleRange = 15.0, ActivationTime = 0.2,
      TriggeringTime = 5.0, TriggerCount = 1, ShotIntervalTime = 5.0, RestingTime = 1.0, bEnableLostTargetInClouds = true,
      YawSpeed = 360.0, YawAngleMin = -180.0, YawAngleMax = 180.0, PitchSpeed = 360.0, PitchAngleMin = 0.0, PitchAngleMax = 90.0 } },
    { "NPC_FCS_VesselVLSmk41", { NpcAIModuleId = FName("NPC_AIModule_Turret000"), NpcWeaponId = FName("VLS_Vessel_000"),
      MagazineCapacity = 10, PredictionOffsetTime = 0.0, CaptureDistance = 3000.0, CaptureAngleRange = 180.0, ActivationTime = 2.0,
      TriggeringTime = 5.0, TriggerCount = 1, ShotIntervalTime = 5.0, RestingTime = 10.0, bEnableLostTargetInClouds = true,
      YawSpeed = 0.0, YawAngleMin = 0.0, YawAngleMax = 0.0, PitchSpeed = 0.0, PitchAngleMin = 0.0, PitchAngleMax = 0.0 } },
}
local WPN_ROWS = {
    { "AAGUN_Ground_000", { MaxSpawnAngle = 1.0, LifeTime = 3.0, bIsHoming = false, DamageAreaLengthMeters = 2000.0,
      DamageAreaRadiusMeters = 20.0 } },
    { "SAM_Ground_000", { MaxSpawnAngle = 0.0, LifeTime = 7.3, bIsHoming = true, AccelerationKmph = 300.0, SpeedMaxKmph = 3000.0,
      MaxRotationAngle = 15.0, HomingReductionInCloud = 0.5, DamageAreaLengthMeters = 0.0, DamageAreaRadiusMeters = 0.0 } },
    { "CIWS_Vessel_000", { MaxSpawnAngle = 1.0, LifeTime = 3.0, bIsHoming = false, DamageAreaLengthMeters = 0.0,
      DamageAreaRadiusMeters = 0.0 } },
    { "AAGUN_Vessel_000", { damage = 1.0, MaxSpawnAngle = 1.0, LifeTime = 3.0, bIsHoming = false, DamageAreaLengthMeters = 2200.0,
      DamageAreaRadiusMeters = 20.0 } },
    { "FlakGun_000", { damage = 10.0, MaxSpawnAngle = 0.0, LifeTime = 15.0, bIsHoming = true, ImpactRadiusMeters = 18.0,
      RandRangeMeters = 120.0, HeightLimitRangeMinMeters = 500.0, HeightLimitRangeMaxMeters = 12000.0, DamageAreaLengthMeters = 0.0,
      DamageAreaRadiusMeters = 0.0 } },
    { "VLS_Vessel_000", { damage = 40.0, MaxSpawnAngle = 0.0, LifeTime = 9.0, bIsHoming = true, AccelerationKmph = 300.0,
      SpeedMaxKmph = 3000.0, MaxHomingAngle = 75.0, MaxRotationAngle = 30.0, HomingDelayFromStart = 1.5, HomingReductionInCloud = 0.5,
      AltitudeAboveTargetMeters = 100.0, DistanceFromTargetMeters = 800.0, OmnidirectionalDuration = 2.0, OmnidirectionalAbility = 120.0 } },
    { "EXSAM_Ground_000", { damage = 40.0, MaxSpawnAngle = 0.0, LifeTime = 10.0, bIsHoming = true, AccelerationKmph = 300.0,
      SpeedMaxKmph = 3000.0, MaxHomingAngle = 90.0, MaxRotationAngle = 45.0, HomingDelayFromStart = 0.7, HomingReductionInCloud = 0.5,
      AltitudeAboveTargetMeters = 100.0, DistanceFromTargetMeters = 900.0, OmnidirectionalDuration = 0.95, OmnidirectionalAbility = 360.0 } },
}
local MINE_ROWS = {                               -- DT_SV_NpcRows' allies (tools/build_survival.py build_npc_rows)
    { "SV_Ally_Moonchild", npcRow() }, { "SV_Ally_Wingmen", npcRow() }, { "SV_Ally_Aegis", npcRow() },
    { "SV_Def_Gepa", npcRow("NPC_FCS_VehicleAAGun000") }, { "SV_Def_Avng", npcRow("NPC_FCS_VehicleSAM001") },
    { "SV_Def_Ciws", npcRow() },                  -- (GR033_ciws_01's: no fire control row of its own)
    { "SV_Turret_aegs_mk15_Ally", npcRow("NPC_FCS_VesselCIWS000") }, { "SV_Turret_aegs_mk41_Ally", npcRow("NPC_FCS_VesselVLSmk41") },
    { "SV_Turret_aegs_mk45_Ally", npcRow("NPC_FCS_VesselAAGun000") }, { "SV_Turret_aegs_artillery_Ally", npcRow() },
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
local walked = {}                                 -- ((0.73.77) the walks asked, by class)
function NotifyOnNewObject() end
function FindAllOf(c) walked[#walked + 1] = c; return objects[c] or {} end
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

local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
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
      and has(line(string.format("allies: the airfield defences' turrets search %d m (NPC_AIModule_SV_Defence, was 6000 m)", DEF.fcs.search_m), from), "not lost in cloud"),
      string.format("the defences' search module: 6000 -> %d m, not lost in cloud, logged", DEF.fcs.search_m))
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
-- (2026-10-31, "increase the lock on and firing distance of all SAM sites and Ships": 8 -> 20 km, 14 -> 30 s)
check(sam and sam.CaptureDistance == mc.range_m and mc.range_m == 20000, "SAM sites: lock-on 3000 -> 20000 m (was 8000)")
check(samw and samw.LifeTime == mc.life_s and mc.life_s == 30 and samw.AccelerationKmph == 600 and samw.SpeedMaxKmph == 3600
      and near(samw.MaxRotationAngle, 22.5) and samw.HomingReductionInCloud == 0 and sam.NpcWeaponId:ToString() == "SAM_Ground_000_SVA_Defence",
      "SAM missiles: 7.3 -> 30 s, 3000 -> 3600 km/h, +300 -> +600 km/h a second, turns 15 -> 22.5, no cloud loss")
do                                                -- (its reach: from 500 km/h, at that acceleration to that top speed)
    local v0, a, vmax = 500 / 3.6, samw.AccelerationKmph / 3.6, samw.SpeedMaxKmph / 3.6
    local t1 = math.min(samw.LifeTime, (vmax - v0) / a)
    local reach = v0 * t1 + a * t1 * t1 / 2 + vmax * (samw.LifeTime - t1)
    check(reach > 1.3 * sam.CaptureDistance, string.format("SAM missiles reach %.1f km straight out, past the %.0f km lock-on (was %.1f km)",
          reach / 1000, sam.CaptureDistance / 1000, (500 / 3.6 * 7.3 + 300 / 3.6 * 7.3 * 7.3 / 2) / 1000))
end
check(sam and sam.TriggerCount == mc.salvo_n and near(sam.ShotIntervalTime, mc.salvo_gap_s) and near(sam.TriggeringTime, mc.salvo_n * mc.salvo_gap_s)
      and near(sam.RestingTime, 10.0 * tx * DEF.fcs.fire_x * mc.salvo_x) and sam.MagazineCapacity >= mc.salvo_n,
      string.format("SAM sites: salvos of %s, %s s apart, rest %.2f s (\"increase missile salvos\")", tostring(mc.salvo_n),
          tostring(mc.salvo_gap_s), sam and sam.RestingTime or -1))
check(has(fcsLine, string.format("NPC_FCS_VehicleSAM001_SVA_Defence (within 3000 -> 20000 m, arm 2.00 -> 0.75 s, lock 5.00 -> %.2f s, "
          .. "5.00 -> %.2f s between, rest 10.00 -> %.2f s", mc.salvo_n * mc.salvo_gap_s, mc.salvo_gap_s, 10.0 * tx * DEF.fcs.fire_x * mc.salvo_x))
      and has(fcsLine, string.format(", salvos of %d, %.2f s apart", mc.salvo_n, mc.salvo_gap_s))
      and has(fcsLine, "missile SAM_Ground_000_SVA_Defence: 7.3 -> 30 s, up to 3000 -> 3600 km/h, +300 -> +600 km/h a second, turns 15.0 -> 22.5"),
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
      and mk15w and mk15w.LifeTime == 3.0 * (SHIPCFG.fcs.round_reach and SHIPCFG.fcs.range_x or 1)   -- (its rounds reach its lock-on: 0.73.52)
      and T.npc:FindRow("SV_Ally_Aegis").MaxHealthDifference == SHIPCFG.health_add
      and T.mod:FindRow("NPC_AIModule_SV_Aegis") and T.mod:FindRow("NPC_AIModule_SV_Aegis").Radius == SHIPCFG.fcs.search_m,
      "the Aegis's Mk 15 its own row (x3 range, +-60, rounds out to it), its hull +300, its own search")
-- the Aegis's Mk 45: its AA gun a flak gun (0.73.52: "change the AA to FLAK GUNS", "the same stats as the Boosted AA guns")
do
    local fk, sfc = SHIPCFG.fcs.flak, SHIPCFG.fcs
    local mk45 = T.npc:FindRow("SV_Turret_aegs_mk45_Ally")
    local fl = T.fcs:FindRow("NPC_FCS_VesselAAGun000_SVA_Aegis")
    local fw = T.wpn:FindRow("FlakGun_000_SVA_Aegis")
    check(fk and fk.enabled ~= false and mk45 and mk45.NpcFCSId0:ToString() == "NPC_FCS_VesselAAGun000_SVA_Aegis" and fl
          and fl.NpcWeaponId:ToString() == "FlakGun_000_SVA_Aegis" and T.wpn:FindRow("AAGUN_Vessel_000_SVA_Aegis") == nil,
          "the Mk 45 on its own fire control, which fires the flak's shells (FlakGun_000_SVA_Aegis), no AA rounds")
    local ffx = fk.fire_x or 1
    check(fl and fl.CaptureDistance == fk.range_m and near(fl.ShotIntervalTime, 3.0 * tx * sfc.fire_x * ffx)
          and near(fl.RestingTime, 1.0 * tx * sfc.fire_x * ffx) and ffx < 1
          and near(fl.ActivationTime, 0.5 * tx * sfc.lock_x) and near(fl.TriggeringTime, 3.0 * tx * sfc.lock_x * ffx)
          and fl.YawAngleMin == -110 and fl.YawAngleMax == 90 and fl.PitchAngleMax == 85 and near(fl.CaptureAngleRange, math.min(180, 30 * CFG.allies.fcs.angle_x))
          and fl.YawSpeed == 360 and fl.PredictionOffsetTime == 5.0 and fl.NpcAIModuleId:ToString() == "NPC_AIModule_SV_Aegis",
          string.format("flak: %d m reach, the AA gun's timings x the boosts x flak.fire_x (%.2f s between), the mount's arcs (-110..90), the flak's slew and lead, the search",
              fl and fl.CaptureDistance or -1, fl and fl.ShotIntervalTime or -1))
    check(fw and near(fw.damage, 10 * fk.damage_x) and near(fw.RandRangeMeters, 120 * CFG.allies.fcs.spread_x * sfc.gun_spread_x)
          and near(fw.ImpactRadiusMeters, 18 * sfc.round_width_x) and fw.HeightLimitRangeMinMeters == fk.min_alt_m and fw.LifeTime == 15,
          string.format("flak shells: damage %s, bursts within %s m, %s m round, from %s m up, 15 s of flight (no missile's)",
              tostring(fw and fw.damage), tostring(fw and fw.RandRangeMeters), tostring(fw and fw.ImpactRadiusMeters),
              tostring(fw and fw.HeightLimitRangeMinMeters)))
    check(has(fcsLine, "NPC_FCS_VesselAAGun000_SVA_Aegis (an AA gun on NPC_FCS_FlakGun000's fire control, within 15000 -> 15000 m")
          and has(fcsLine, "flak FlakGun_000_SVA_Aegis: damage 10 -> 20, bursts within 120 -> 24 m, 18 -> 27 m round, from 500 -> 50 m up"),
          "the log line: the Mk 45 on flak")
    -- the Aegis's Mk 41: its missiles home as the EXSAM's
    local mc = sfc.missile
    local vl = T.fcs:FindRow("NPC_FCS_VesselVLSmk41_SVA_Aegis")
    local vw = T.wpn:FindRow("VLS_Vessel_000_SVA_Aegis")
    check(vl and vl.CaptureDistance == mc.range_m and near(vl.RestingTime, 10.0 * tx * sfc.fire_x * mc.salvo_x) and mc.salvo_x < 1
          and vl.TriggerCount == mc.salvo_n and mc.salvo_n > 1 and near(vl.ShotIntervalTime, mc.salvo_gap_s)
          and near(vl.TriggeringTime, mc.salvo_n * mc.salvo_gap_s),
          string.format("Mk 41: lock-on %s m, salvos of %s, %.2f s apart, rest %.2f s (salvo_x %s)", tostring(vl and vl.CaptureDistance),
              tostring(vl and vl.TriggerCount), vl and vl.ShotIntervalTime or -1, vl and vl.RestingTime or -1, tostring(mc.salvo_x)))
    check(mc.homing_from == "EXSAM_Ground_000" and vw and vw.MaxHomingAngle == 90 and near(vw.MaxRotationAngle, 45 * mc.turn_x)
          and vw.HomingDelayFromStart == 0.7 and vw.OmnidirectionalDuration == 0.95 and vw.OmnidirectionalAbility == 360
          and vw.DistanceFromTargetMeters == 900 and vw.damage == 40 and vw.LifeTime == mc.life_s,
          "Mk 41 missiles: the EXSAM's homing (90, turn 45 x turn_x, delay 0.7, 0.95 s / 360 all round, 900 m), then the boosts")
    check(has(fcsLine, "missile VLS_Vessel_000_SVA_Aegis: 9.0 -> 45 s") and has(fcsLine, "turns 30.0 -> 67.5, homing as EXSAM_Ground_000 (6 of 6)"),
          "the log line: the Mk 41's missiles homing as the EXSAM's")
    -- the CIWS isn't an AA gun: as it was
    check(T.wpn:FindRow("CIWS_Vessel_000_SVA_Aegis") and T.fcs:FindRow("NPC_FCS_VesselCIWS000_SVA_Aegis").NpcWeaponId:ToString() == "CIWS_Vessel_000_SVA_Aegis",
          "the Mk 15 (CIWS) not on flak")
    -- flak.enabled = false: the AA gun as before; homing_from none: the missiles' own homing
    fk.enabled, mc.homing_from = false, "none"
    local f2 = setup()
    local fl2 = T.fcs:FindRow("NPC_FCS_VesselAAGun000_SVA_Aegis")
    local vw2 = T.wpn:FindRow("VLS_Vessel_000_SVA_Aegis")
    check(fl2 and fl2.NpcWeaponId:ToString() == "AAGUN_Vessel_000_SVA_Aegis" and fl2.CaptureDistance == 2200 * sfc.range_x
          and T.wpn:FindRow("FlakGun_000_SVA_Aegis") == nil and vw2 and vw2.MaxHomingAngle == 75 and vw2.HomingDelayFromStart == 1.5,
          "flak.enabled = false: an AA gun (x3 reach, AA rounds); homing_from none: the Mk 41's own homing")
    fk.enabled, mc.homing_from = true, "EXSAM_Ground_000"
    -- a game without the flak's row: the AA gun as before, logged
    local keep = fk.fcs
    fk.fcs = "NPC_FCS_NotThere000"
    f2 = setup()
    check(T.fcs:FindRow("NPC_FCS_VesselAAGun000_SVA_Aegis").NpcWeaponId:ToString() == "AAGUN_Vessel_000_SVA_Aegis"
          and line("allies: Aegis's AA gun NPC_FCS_VesselAAGun000 NOT on flak (no row NPC_FCS_NotThere000): an AA gun as before", f2),
          "no flak row in the game's table: the AA gun as before, logged")
    fk.fcs = keep
    setup()
end

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
-- (0.73.77, from claude/coop-fixes 57dce73) the rows on screen are found by their old text (relabel), so a text two items
-- share is left for the page's next opening: the old fourth row's AA offer and the AA GUN row's both "BUILD AA GUN   4000
-- Z"; when both moved on, every TextBlock with it became BUILD SAM SITE (co-op run of 2026-11-01). One only a single row
-- had is rewritten as before.
do
    FText = FText or function(s) return { s = s } end
    local function textBlock(text)
        local t = { full = "TextBlock /Engine/Transient.GameEngine_0:WBP_Menu_Text_Focus_C_" .. addr() .. ".WidgetTree.TextBlock_0",
                    addr = addr(), text = text }
        function t:GetText() local s = self.text; return { ToString = function() return s end } end
        function t:SetText(v) self.text = type(v) == "table" and v.s or tostring(v) end
        return t
    end
    spawned, alive, RUN.defences = {}, {}, { built = 0, bought = {} }
    shop()
    local aaText, ciwsText = texts.SV_Shop_AAGun, texts.SV_Shop_Ciws
    check(texts.SV_Shop_Airfield == aaText and aaText == "BUILD AA GUN   4000 Z" and ciwsText == "BUILD CIWS   6000 Z",
          "(the old fourth row and the AA GUN row both: " .. tostring(aaText) .. "; the CIWS row its own)")
    local tbAA, tbCiws = textBlock(aaText), textBlock(ciwsText)
    objects.TextBlock = { tbAA, tbCiws }
    SH.relabelAt, SH.rowTexts = nil, nil
    for _, u in ipairs(DEF.aa.units) do alive[u] = 1 end
    for _, u in ipairs(DEF.ciws.units) do alive[u] = 1 end
    clock = clock + 5
    shop()
    check(texts.SV_Shop_AAGun ~= aaText and texts.SV_Shop_Airfield ~= aaText and texts.SV_Shop_AAGun ~= texts.SV_Shop_Airfield,
          "(both moved on: " .. tostring(texts.SV_Shop_AAGun) .. " / " .. tostring(texts.SV_Shop_Airfield) .. ")")
    check(tbAA.text == aaText, "the shared text on screen left as it was, not rewritten to either row's new one (" .. tostring(tbAA.text) .. ")")
    check(tbCiws.text == texts.SV_Shop_Ciws, "a text one row had: rewritten as before (" .. tostring(tbCiws.text) .. ")")
    objects.TextBlock, SH.rowTexts = nil, nil
end

-- (0.73.80, findings perf4 / specials8 of 2026-11-04) a STORE press: its page among the landing menu's kept windows (one on
-- screen lists the row pressed): no walk; a page not among them (opened over the one kept): its windows walked for again
-- at once (SHOP.pressPage -> sv_core.lua landingWindowsRefresh), so the labels the press changes reach that page. The
-- relabel's key (SHOP.windowsKey) and the icons read the kept ones, no walk of their own.
do
    local CLS = "WBP_Menu_IngameHangar_Common_000_C"
    local function page(name, rows)
        local cd = {}
        for k, r in ipairs(rows) do cd[k] = { StringArgs = { ToString = function() return r end } } end
        local w = { addr = addr(), vis = true, full = CLS .. " /Engine/Transient.GameEngine_0:LiveGameInstance_0.WBP_Menu_"
                    .. "IngameHangar_" .. name .. "_C_" .. nextAddr .. ".WidgetTree.WBP_Menu_IngameHangar_Common_000",
                    WBP_Menu_Pause_List_000 = { addr = addr(), full = "WBP_Menu_Pause_List_000", CommandDatas = cd } }
        function w:IsVisible() return self.vis end
        return w
    end
    local function walksOf() local n = 0; for _, c in ipairs(walked) do if c == CLS then n = n + 1 end end; return n end
    local supplies = page("Store", { "SV_Buy_TestA", "SV_Buy_TestB", "21" })
    objects[CLS] = { supplies }
    onAirfield = true
    landingWindowsForget()
    SH.pressPageSaid = nil                           -- (the presses above had no landing menu at all: logged then)
    local w0 = walksOf()
    landingWindows(tick)
    check(walksOf() == w0 + 1 and landingVisible(supplies), "the visit's first look: walked for on landing, the page found")
    clock = clock + 1
    local from = #logs + 1
    shop("TestA")
    check(walksOf() == w0 + 1, "a press on a row of the page kept on screen: no walk (" .. (walksOf() - w0 - 1) .. ")")
    check(line("shop: unknown item TestA", from) ~= nil, "(the press reached the shop: " .. tostring(line("shop: unknown item", from)) .. ")")
    local key = SHOP.windowsKey(tick)
    check(walksOf() == w0 + 1 and key == tostring(supplies.addr), "the labels' key: the kept window, no walk (" .. key .. ")")
    local docks = page("StoreDocks", { "SV_Buy_TestC", "SV_Buy_TestD", "20" })
    objects[CLS] = { supplies, docks }               -- (opened over it, the first still on screen)
    clock = clock + 1
    shop("TestC")
    check(walksOf() == w0 + 2 and landingVisible(docks), "a press on a page not among them: walked for at once, the page found ("
          .. (walksOf() - w0 - 1) .. ")")
    check(line("shop: SV_Buy_TestC pressed on a landing menu page not among the windows kept: walked for them again (2 now",
          from) ~= nil, "logged: " .. tostring(line("pressed on a landing menu page not among", from)))
    check(SHOP.windowsKey(tick) ~= key and walksOf() == w0 + 2, "... the labels' key changed with it (the rows found again)")
    clock = clock + 1
    shop("TestD")
    check(walksOf() == w0 + 2, "the next press on it: no walk")
    landingWindowsForget()
    objects[CLS] = nil
end

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
ALLY.tick(205)                                       -- ((0.73.83) its count kept up to 4.5 s: seen at the first check past it)
check(callouts[1] == "CIWS LOST / " .. CFG.allies.text.def_lost_sub and line("allies: CIWS (SV_Unit_Ciws_B) lost in round 3", from)
      and has(ALLY.hudLine(), "CIWS 1"), "a CIWS lost: CIWS LOST, logged, the row counts 1")
alive = { SV_Unit_AAGun_A = 1 }
ALLY.tick(210)
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
    -- ((0.73.77, Workstream B3) the actors are found one class a tick: three ticks for the three classes, the walks
    -- counted; their health read every 2 s)
    local walksBefore = #walked
    ALLY.tick(700)
    check(R.defHp == nil and R.defWalk and R.defWalk.i == 1 and #walked == walksBefore + 1,
          "(0.73.77) the look for the defences' actors: one class a tick (1 walk the first tick, nothing read yet)")
    ALLY.tick(700.25); ALLY.tick(700.5)
    check(#walked == walksBefore + 3 and R.defWalk == nil, "... the third class the third tick: 3 walks in all, the look done")
    check(R.defHp == 75 and #R.defActors == 2, "the row's defences' health: 75% (600 and 300 of 600): " .. tostring(R.defHp))
    check(line("allies: the airfield defences' actors found one class a tick: 2 for 2 up") ~= nil,
          "(0.73.77) logged once: the airfield defences' actors found one class a tick")
    d2.gone = true                                   -- (taken down and spawned again: its old actor gone, the count the same)
    local d3 = defence("BP_GR033_ciws_CP_Ally_C", 600)
    objects = { BP_GR033_ciws_CP_Ally_C = { d1, d3 } }
    reads = {}
    R.checkAt = 0
    local wb = #walked
    ALLY.tick(701)
    check(#walked == wb and not reads[d1], "(0.73.77) a second on: no walk, the health not read again yet (every 2 s)")
    ALLY.tick(703)
    check(not reads[d2] and #R.defActors == 1 and R.defActorsAt == 0, "an old actor gone: never read, off the list, the list found again next time")
    R.checkAt = 0
    ALLY.tick(704); ALLY.tick(704.25); ALLY.tick(704.5)
    check(#R.defActors == 2 and R.defActors[1] ~= d2 and R.defActors[2] ~= d2 and R.defHp == 100, "... found again (three ticks): the new one in, 100%")
    d1.hp = 0
    R.checkAt = 0
    ALLY.tick(707)
    check(#R.defActors == 1 and R.defActors[1] == d3, "one down (health 0): off the list too")
    ALLY.forgetActors()
    check(R.defActors == nil and R.defWalk == nil, "ALLY.forgetActors: the cached list dropped (a joiner's teardown), a look under way too")
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
    -- ((0.73.78) every ally's and defence's price is the room's: a joiner's ask (asked) below it refused, a built one counted)
    local okR, msgR = shopBuildFor(2, "ShipAegis", 1000, nil, true)
    check(not okR and msgR == "THE PRICE IS NOW 20000", "host: a joiner's AEGIS ask under the room's price refused (" .. tostring(msgR) .. ")")
    local aa0 = (RUN.defences and RUN.defences.bought and RUN.defences.bought.aa) or 0
    okR, msgR = shopBuildFor(2, "AAGun", 100, nil, true)
    check(not okR and has(msgR, "THE PRICE IS NOW "), "host: a joiner's AA gun ask under the room's price refused (" .. tostring(msgR) .. ")")
    local aaPrice = math.floor(DEF.aa.price * DEF.aa.raise ^ aa0 / 10 + 0.5) * 10
    okR, msgR = shopBuildFor(2, "AAGun", aaPrice, nil, true)
    check(okR and RUN.defences.bought.aa == aa0 + 1, "host: ... at it: built and counted in the room's (" .. tostring(msgR) .. ")")
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
    AW.enabled = true                                     -- (hotfix4 ships it off; the AWACS is checked here)
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
    -- ((0.73.78, G5) its help: the field's 9 km, its 3 rounds of service and the strike flight after it)
    check(has(texts.SV_Shop_VoidWatcher, "VOID WATCHER 1: E-767 AWACS   12000 Z") and has(texts.SV_Shop_VoidWatcher_Help, "orbits it")
          and has(texts.SV_Shop_VoidWatcher_Help, "(9 km) for 3 rounds, then goes home") and has(texts.SV_Shop_VoidWatcher_Help, "a strike flight goes after it"),
          "the STORE's row: 12000 Z, its help (" .. tostring(texts.SV_Shop_VoidWatcher) .. ": " .. tostring(texts.SV_Shop_VoidWatcher_Help) .. ")")
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
    -- its orbit's backstop: a climb-out that never ends, then a plane that wanders off
    local function orbitCount() local k = 0; for _, e in ipairs(events) do if e == AW.orbit.event then k = k + 1 end end; return k end
    local o0 = orbitCount()
    R.orbitCheckAt, R.orbitAgainAt = 0, 0
    D.now = 230; ALLY.tick(230)
    check(orbitCount() == o0, "30 s after takeoff, still climbing: left to it")
    R.orbitCheckAt = 0
    D.now = 262; ALLY.tick(262)
    check(orbitCount() == o0 + 1 and line("allies: VOID WATCHER 1 taken off its path onto the area orbit (its climb-out didn't end in 60 s)") ~= nil,
          "61 s on, its climb-out never ended: put on its orbit (RE_SV_AwacsOrbit), logged")
    local vw = { full = "BP_OP0005_e767_CP_Ally_C_1", addr = addr() }
    local at = { X = AIRFIELD.X + 2500000, Y = AIRFIELD.Y }
    function vw:K2_GetActorLocation() return at end
    R.planes[#R.planes + 1] = { obj = vw, unit = AW.unit, name = "e767" }
    air = 1
    R.orbitCheckAt = 0
    D.now = 263; ALLY.tick(263)
    check(orbitCount() == o0 + 1, "airborne 25 km out, again_s (60 s) not up: not again yet")
    R.orbitCheckAt = 0
    D.now = 330; ALLY.tick(330)
    check(orbitCount() == o0 + 2 and line("onto the area orbit (25.0 km from the airfield)") ~= nil, "wandered 25 km off: put back on its orbit")
    local onKm = (AW.orbit.lost_km or 18) * 0.6           -- (on its orbit: well inside lost_km, whatever the orbit's size)
    at = { X = AIRFIELD.X + onKm * 100000, Y = AIRFIELD.Y }
    R.orbitCheckAt, R.orbitAgainAt = 0, 0
    D.now = 331; ALLY.tick(331)
    check(orbitCount() == o0 + 2, string.format("on its orbit (%.1f km out, lost_km %s): left alone", onKm, tostring(AW.orbit.lost_km)))
    air = 0
    R.esmAt = nil
    air = 1
    e0 = esmCount()
    D.now = 406; ALLY.tick(406)
    D.now = 410; ALLY.tick(410)
    check(esmCount() == e0 + 1, "airborne: its ESM fired (RE_SV_AwacsEsm), once")
    D.now = 406 + AW.esm.every_s; ALLY.tick(D.now)
    check(esmCount() == e0 + 2, "every_s (20 s) on: again")
    -- each ESM field of its class: its range and time; another class's left as it is
    -- ((0.73.78, G5) 9000 m for 15 s: the stub's other numbers the game's own, 3200 and 10000 s, as the logs had it)
    local RG, LF = AW.esm.range_m, AW.esm.life_s
    check(RG == 9000 and LF == 15 and AW.esm.every_s == 30, string.format("G5: its ESM field %d m for %d s every %d s "
          .. "(was 25000 m for 24 s every 20 s: up all the time over the whole fight)", RG, LF, AW.esm.every_s))
    local field = { full = "BP_wp_esm_MS28_C /Game/Maps/PL_SurvivalMode:PersistentLevel.BP_wp_esm_MS28_C_1", addr = addr(),
                    SupportEffectRangeMeter = 3200, EffectRangeMeter = 3200, LifeTime = 10000 }
    local other = { full = "BP_wp_ecm_a0_C /Game/Maps/PL_SurvivalMode:PersistentLevel.BP_wp_ecm_a0_C_1", addr = addr(),
                    SupportEffectRangeMeter = 3200, EffectRangeMeter = 3200, LifeTime = 10000 }
    ALLY.esmNew = { field, other }
    local l0 = #logs
    D.now = D.now + 0.25; ALLY.tick(D.now)
    check(field.SupportEffectRangeMeter == RG and field.EffectRangeMeter == RG and field.LifeTime == LF
          and has(line("allies: VOID WATCHER 1's ESM field BP_wp_esm_MS28_C_1: support range 3200 -> " .. RG .. " m", l0), "life 10000 -> " .. LF .. " s"),
          "its ESM field: 3200 -> " .. RG .. " m, 10000 -> " .. LF .. " s (an instance's; logged)")
    check(other.SupportEffectRangeMeter == 3200 and other.LifeTime == 10000, "an ECM field of another class: as it was")
    -- (0.73.73) the fields are pooled: the game launches the same two again and again (every tester session of 2026-11-01
    -- logged two fields while the weapons log counted 2-3 launches a minute), so a field launched again from the pool,
    -- with the game's own range and time written on it, is set again; one idle in the pool (hidden) is left alone
    field.bHidden = true
    D.now = D.now + 0.25; ALLY.tick(D.now)
    field.bHidden, field.SupportEffectRangeMeter, field.EffectRangeMeter, field.LifeTime = false, 3200, 3200, 10000
    l0 = #logs
    D.now = D.now + 0.25; ALLY.tick(D.now)
    check(field.SupportEffectRangeMeter == RG and field.EffectRangeMeter == RG and field.LifeTime == LF
          and has(line("allies: VOID WATCHER 1's ESM field BP_wp_esm_MS28_C_1 launched again (pooled; 1 so far)", l0), "life 10000 -> " .. LF .. " s"),
          "its ESM field launched again from the pool (shown, the game's range on it): " .. RG .. " m and " .. LF .. " s again, logged")
    field.LifeTime = LF - 0.5                          -- (its time running down, as the game may count it)
    D.now = D.now + 0.25; ALLY.tick(D.now)
    check(field.LifeTime == LF - 0.5, "... while it's out: left alone (a running time never set back)")
    field.bHidden = true
    D.now = D.now + 0.25; ALLY.tick(D.now)
    field.SupportEffectRangeMeter, field.EffectRangeMeter, field.LifeTime = 3200, 3200, 10000  -- (back in the pool, reset)
    D.now = D.now + 0.25; ALLY.tick(D.now)
    check(field.EffectRangeMeter == 3200 and field.LifeTime == 10000, "... idle in the pool (hidden): left alone")
    field.bHidden = false                              -- (launched again, the range as the pool left it)
    D.now = D.now + 0.25; ALLY.tick(D.now)
    check(field.EffectRangeMeter == RG and field.LifeTime == LF and has(line("launched again (pooled; 2 so far)", l0), "BP_wp_esm_MS28_C_1"),
          "... and its next launch (shown after hidden): set again")
    field.gone = true
    D.now = D.now + 0.25; ALLY.tick(D.now)
    check(R.esmFields and next(R.esmFields) == nil, "a field gone: dropped from the list (never read again)")
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
    -- ((0.73.78, G5) raise 1.25: the second x1.25)
    check(has(texts.SV_Shop_VoidWatcher, "15000 Z"), "... and sells it again, x1.25 dearer (" .. tostring(texts.SV_Shop_VoidWatcher) .. ")")
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

---------------------------------------------------------------------------------------------------- (0.73.78) G5
-- VOID WATCHER 1's limits (plan G5; the user, 2026-11-03: "3 rounds of service, rising price, 8-10 km field, a strike
-- flight after it"; a tester of the 5-player run: it "wins the fight for you", one bought in round 16 lasted 92 minutes)
print("(0.73.78) G5: VOID WATCHER 1 serves 3 rounds and goes home, its price rises x1.25, a strike flight goes after it")
do
    local AW = CFG.allies.awacs
    AW.enabled = true
    local keep = { COOP = COOP, flags = svFlags, rec = SV_Recycle, pc = survivalPC, planes = planes }
    COOP = nil
    ALLY.run, alive, events, callouts = nil, {}, {}, {}
    RUN.credits, RUN.spent, RUN.bought, RUN.msg = 200000, 0, {}, {}
    D = { round = 5, state = "wait", now = 1000, up = {}, flown = {}, queue = {}, events = {}, orders = {} }
    local flags = { SV_AwacsAir = 0 }
    svFlags = function() return flags end
    local recycled = {}
    SV_Recycle = function(u, force) recycled[#recycled + 1] = u .. ":" .. tostring(force); return 1 end
    local function count(name) local k = 0; for _, e in ipairs(events) do if e == name then k = k + 1 end end; return k end
    local function calloutHas(part) for _, c in ipairs(callouts) do if has(c, part) then return c end end; return nil end
    local now = 1000
    local function step(dt, n) for _ = 1, n or 1 do now = now + (dt or 0.25); D.now = now; ALLY.tick(now) end end
    -- its price: 12000, then x1.25 a purchase
    onAirfield = true
    shop()
    check(has(texts.SV_Shop_VoidWatcher, "12000 Z") and CFG.shop.items.VoidWatcher.raise == 1.25, "G5: the first one 12000 Z, raise 1.25 (was 1.0)")
    local c0 = RUN.credits
    shop("VoidWatcher")
    check(c0 - RUN.credits == 12000 and RUN.bought.VoidWatcher == 1, "G5: bought for 12000")
    local R = ALLY.state()
    onAirfield = false
    R.nextTakeoff = 0
    step()
    local s = R.up[AW.unit]
    check(s and not s.queued, "G5: it takes off once you're airborne")
    local vw = { full = "BP_OP0005_e767_CP_Ally_C_77", addr = addr() }
    local at = { X = AIRFIELD.X + 600000, Y = AIRFIELD.Y, Z = 450000 }
    function vw:K2_GetActorLocation() return at end
    function vw:K2_GetActorRotation() return { Yaw = 0 } end
    R.planes[#R.planes + 1] = { obj = vw, unit = AW.unit, name = "e767" }
    flags.SV_AwacsAir = 1
    -- the round's strike flight: a pool flight up 4 s, each plane onto it (Normal, TargetFirst); not an escort's
    local orders = {}
    local function enemy(name) return { full = name, addr = addr(), EngagementOrderOverride = function(self, o, tgt, prio)
        orders[#orders + 1] = { who = self.full, tgt = tgt, prio = prio, order = o } end } end
    local U, ESC = "ERA_Unit_02_Dep_Air1", "ERA_Unit_03_Dep_Air0"
    local e1, e2, e3 = enemy("BP_OP1004_f15c_1"), enemy("BP_OP1004_f15c_2"), enemy("BP_OP1004_f15c_3")
    planes = { { obj = e1, unit = U }, { obj = e2, unit = U }, { obj = e3, unit = ESC } }
    D.up = { [ESC] = true }
    D.escortUnits = { [ESC] = true }
    D.state = "fighting"
    local pawn = { full = "BP_PlayerPlane", addr = addr() }
    survivalPC = { full = "PlayerController", addr = addr(), Pawn = pawn }
    step(0.25, 40)                                      -- (10 s: the escort's up long enough, but it's an escort)
    check(#orders == 0 and line("allies: no fighter flight free to send after VOID WATCHER 1 yet (round 5)") ~= nil,
          "G5: only a raid's escort up: no strike flight (logged once)")
    D.up[U] = true
    step(0.25, 8)                                       -- (2 s: seen, not 4 s up yet)
    check(#orders == 0, "G5: a fighter flight just up: not yet (after_s 4)")
    local l0 = #logs
    step(0.25, 24)
    check(#orders == 2 and orders[1].tgt == vw and orders[2].tgt == vw and orders[1].prio == 9 and orders[1].order == 0
          and has(line("allies: " .. U .. " sent after VOID WATCHER 1: round 5's strike flight (2 of 2 planes", l0), "TargetFirst")
          and calloutHas("HEADING FOR VOID WATCHER 1") ~= nil and R.hunted[U] == true,
          "G5: 4 s up: its 2 planes onto VOID WATCHER 1 (Normal, TargetFirst), logged, called out, the hunt leaves it alone")
    D.up["ERA_Unit_04_Dep_Air0"] = true
    planes[#planes + 1] = { obj = enemy("BP_OP1004_f15c_4"), unit = "ERA_Unit_04_Dep_Air0" }
    local n0 = #orders
    step(0.25, 64)                                      -- (16 s: its order once more at 15 s)
    local again = 0
    for i = n0 + 1, #orders do if orders[i].who == "BP_OP1004_f15c_4" then again = -100 elseif orders[i].tgt == vw then again = again + 1 end end
    check(again == 2, "G5: one strike flight a round (another flight up: not sent); its order given again after again_s (15 s)")
    -- its rounds of service: one counted as it clears with it up 60 s or more of it
    step(0.25, 200)                                     -- (50 s more: up over 60 s)
    D.state = "wait"
    l0 = #logs
    step()
    check(s.served == 1 and has(line("allies: VOID WATCHER 1 has served 1 of its 3 rounds (round 5 clear)", l0), "round 5"),
          "G5: round 5 clear: 1 of 3 served, logged")
    step(0.25, 8)
    check(s.served == 1, "G5: ... counted once")
    -- rounds 6 and 7 (the strike flight left up here across them, kept on it: in a game a round ends with it down)
    for r = 6, 7 do
        D.round, D.state = r, "fighting"
        step(0.25, 8)
        step(30, 3)
        D.state = "wait"
        l0 = #logs
        step()
    end
    local ev0 = count(AW.home.event)
    check(s.served == 3 and s.home ~= nil and count(AW.home.event) == 1
          and line("allies: VOID WATCHER 1 has served 3 rounds: going home (RE_SV_AwacsHome fired; out along its exit", l0) ~= nil
          and calloutHas("VOID WATCHER 1 GOING HOME") and calloutHas("3 ROUNDS SERVED"),
          "G5: round 7 clear: 3 served, sent home (RE_SV_AwacsHome), logged and called out")
    check(has(ALLY.hudLine() or "", "VOID WATCHER 1 (GOING HOME)") and not has(ALLY.roomCode(), "v"),
          "G5: the ALLIES row says it's going home (" .. tostring(ALLY.hudLine()) .. "); the room's code has no v (" .. ALLY.roomCode() .. ")")
    -- going home: no ESM, no backstop (it's meant to leave the orbit), the strike flight back on you
    local e0, o0 = count(AW.esm.event), count(AW.orbit.event)
    at = { X = AIRFIELD.X + 1200000, Y = AIRFIELD.Y, Z = 450000 }   -- (12 km out: past lost_km)
    R.orbitCheckAt, R.orbitAgainAt = 0, 0
    l0 = #logs
    D.round, D.state = 8, "fighting"
    step(0.25, 160)
    local back = 0
    for i = 1, #orders do if orders[i].tgt == pawn and orders[i].prio == 8 then back = back + 1 end end
    check(count(AW.esm.event) == e0 and count(AW.orbit.event) == o0, "G5: going home: no ESM fired, no backstop onto the area orbit")
    check(back == 2 and has(line("allies: " .. U .. " off VOID WATCHER 1 (it's going home): 2 planes back on you", l0), "back on you"),
          "G5: its strike flight back on you (PlayerOnlyNoLimit), logged")
    local strikes0 = #orders
    step(0.25, 40)
    local newStrike = false
    for i = strikes0 + 1, #orders do if orders[i].tgt == vw then newStrike = true end end
    check(not newStrike, "G5: no strike flight sent after it while it's going home (round 8)")
    -- its exit: SV_AwacsOut 1 logged; 20 km out: taken off (RE_SV_AwacsRemove), 2 s on off the spawner's list
    flags.SV_AwacsOut = 1
    l0 = #logs
    step(0.25, 12)
    check(line("allies: VOID WATCHER 1 on its way out (its arc's end took its exit", l0) ~= nil, "G5: its exit begun (SV_AwacsOut 1): logged")
    check(count(AW.home.remove) == 0 and R.up[AW.unit] ~= nil, "G5: 12 km out: not taken off yet")
    at = { X = AIRFIELD.X + 2100000, Y = AIRFIELD.Y, Z = 450000 }
    callouts = {}
    l0 = #logs
    step(0.25, 9)
    check(count(AW.home.remove) == 1 and has(line("allies: VOID WATCHER 1 taken off (21.0 km out): RE_SV_AwacsRemove fired", l0), "fired"),
          "G5: 21 km out: taken off (RE_SV_AwacsRemove), logged")
    alive[AW.unit] = 0                                 -- (despawned: its unit may read 0 or still count it)
    step(0.25, 12)
    check(R.up[AW.unit] == nil and recycled[#recycled] == AW.unit .. ":1"
          and has(line("allies: VOID WATCHER 1 home after 3 rounds (21.0 km out): off the spawner's list (SV_Recycle 1)", l0), "STORE can send another")
          and not calloutHas("FLIGHT LOST"),
          "G5: 2 s on: SV_Recycle(unit, 1), out of the allies, logged; never called lost")
    check(ALLY.hudLine() == nil or not has(ALLY.hudLine(), "VOID WATCHER"), "G5: ... and off the ALLIES row")
    onAirfield = true
    shop()
    check(has(texts.SV_Shop_VoidWatcher, "15000 Z"), "G5: the STORE sells another, x1.25 dearer (" .. tostring(texts.SV_Shop_VoidWatcher) .. ")")
    -- the backstop's area orbit: no arc's end to leave from, taken off area_s after it was sent home
    ALLY.run, events = nil, {}
    R = ALLY.state()
    R.up[AW.unit] = { kind = "air", ally = "awacs", at = now - 500, served = 3, home = now, areaOrbit = true }
    R.planes = { { obj = vw, unit = AW.unit, name = "e767" } }
    at = { X = AIRFIELD.X + 600000, Y = AIRFIELD.Y, Z = 450000 }
    flags.SV_AwacsOut = 0
    alive[AW.unit] = 1                                  -- (up: the last one's taken-off 0 gone)
    step(1, 20)
    check(count(AW.home.remove) == 0, "G5: on the area orbit, sent home: not taken off in 20 s")
    l0 = #logs
    step(1, 12)
    check(count(AW.home.remove) == 1 and line("allies: VOID WATCHER 1 taken off (30 s on the area orbit, no arc to leave from)", l0) ~= nil,
          "G5: ... taken off area_s (30 s) on")
    step(1, 3)
    R.up[AW.unit] = nil
    alive[AW.unit] = 0
    -- co-op: a joiner's ask at the host's price (the room's purchases counted here); a migration's rebuild free
    COOP = { airborne = function() return false end, refund = function() end }
    RUN.bought.VoidWatcher = 1
    l0 = #logs
    local okL, msgL = shopBuildFor(2, "VoidWatcher", 12000, nil, true)
    check(not okL and has(msgL, "THE PRICE IS NOW 15000") and R.up[AW.unit] == nil
          and line("shop: player 3's VoidWatcher at 12000 refused: the room's price is 15000 (bought 1 times this run)", l0) ~= nil,
          "G5: co-op: a joiner's ask under the room's price refused (" .. tostring(msgL) .. ")")
    local okH, msgH = shopBuildFor(2, "VoidWatcher", 15000, nil, true)
    check(okH and R.up[AW.unit] and R.up[AW.unit].buyer == 2 and RUN.bought.VoidWatcher == 2,
          "G5: ... at it: built for them, counted in the room's purchases (2) (" .. tostring(msgH) .. ")")
    R.up[AW.unit] = nil
    local okM = shopBuildFor(nil, "VoidWatcher", 0, nil)
    check(okM and R.up[AW.unit] and RUN.bought.VoidWatcher == 2, "G5: a host by migration building the old room's again: free, not counted")
    R.up[AW.unit] = nil
    -- rounds 0: it serves until it's shot down, as before
    local keepRounds = AW.service.rounds
    AW.service.rounds = 0
    alive[AW.unit] = 1
    R.up[AW.unit] = { kind = "air", ally = "awacs", at = now - 500 }
    D.round, D.state = 9, "fighting"; step()
    D.state = "wait"; step(0.25, 4)
    check(R.up[AW.unit] and not R.up[AW.unit].home and not R.up[AW.unit].served, "G5: [allies.awacs.service] rounds = 0: never sent home")
    AW.service.rounds = keepRounds
    COOP, svFlags, SV_Recycle, survivalPC, planes = keep.COOP, keep.flags, keep.rec, keep.pc, keep.planes
    ALLY.run, alive, D = nil, {}, nil
end

---------------------------------------------------------------------------------------------------- ALLY.scale (0.73.73)
-- An allied plane's health raised by the growth past the most it's had, never again for a round number that comes back:
-- each co-op resync flipped a joiner's D.round to 0 and back and its copy of the host's VOID WATCHER grew x1.56 a time
-- (Shazzy's A02 11:17:51: "health x3.12 (74399 -> 116062)"); and on a joiner, whose allies are all the host's copies,
-- only the rank is set (their health is the host's, "hp").
print("ALLY.scale: an allied plane's health raised once a round's growth; a joiner's copies of the host's left to the host")
do
    local AW = CFG.allies.awacs
    local R = ALLY.state()
    local keep = { planes = R.planes, up = R.up[AW.unit], D = D, client = COOP and COOP.client }
    local function hx(round) local L = ALLY.level({ ally = "awacs" }); return L.hx end
    local pl = { full = "BP_OP0005_e767_CP_Ally_C_9", addr = addr(), HealthInternal = 50000, MaxHealth = 5000, PilotRank = 1 }
    R.planes, R.up[AW.unit] = { { obj = pl, unit = AW.unit, name = "e767" } }, { kind = "air", ally = "awacs" }
    COOP = COOP or {}
    COOP.client = function() return false end
    D = { round = 8, state = "fight", now = 900, up = {}, flown = {}, queue = {}, events = {}, orders = {} }
    local x8 = hx(8)
    ALLY.scale()
    local h8 = pl.HealthInternal
    check(h8 == math.floor(50000 * x8 + 0.5) and pl.PilotRank > 1, string.format("round 8: health x%.2f (50000 -> %d), its rank set", x8, h8))
    local from = #logs + 1
    D.round = 0; ALLY.scale(); D.round = 8; ALLY.scale(); D.round = 0; ALLY.scale(); D.round = 8; ALLY.scale()
    check(pl.HealthInternal == h8 and has(line("not raised: this round's x", from), "e767"),
          "the round number to 0 and back, twice (a joiner's resync): not raised again (" .. pl.HealthInternal .. ")")
    D.round = 9
    local x9 = hx(9)
    ALLY.scale()
    check(math.abs(pl.HealthInternal - math.floor(h8 * x9 / x8 + 0.5)) <= 1, string.format("round 9: raised by its growth only, x%.3f (%d)", x9 / x8, pl.HealthInternal))
    check(R.planes[1].full == math.floor(5000 * 10 * x9 + 0.5), "its full health (the repairs') x" .. string.format("%.2f", x9))
    -- a co-op joiner: the host's copy, its health the host's
    local cp = { full = "BP_OP0005_e767_CP_Ally_C_10", addr = addr(), HealthInternal = 7400, MaxHealth = 5000, PilotRank = 1 }
    R.planes = { { obj = cp, unit = AW.unit, name = "e767" } }
    COOP.client = function() return true end
    from = #logs + 1
    D.round = 8; ALLY.scale(); D.round = 0; ALLY.scale(); D.round = 8; ALLY.scale()
    check(cp.HealthInternal == 7400 and cp.PilotRank > 1 and has(line("is the host's: PilotRank", from), "its health the host's"),
          "a co-op joiner: the host's copy's rank set, its health left to the host's (logged once)")
    R.planes, R.up[AW.unit], D, COOP.client = keep.planes, keep.up, keep.D, keep.client
end

---------------------------------------------------------------------------------------------------- (0.73.77) B3 / B4
print("(0.73.77) Workstream B3 / B4: the allies' unit counts a share a tick; the STORE's texts at the airfield only")
do
    local asks = {}
    local rawUA = SV_UnitAlive
    SV_UnitAlive = function(u) asks[#asks + 1] = u; return rawUA(u) end
    local keepCOOP = COOP
    COOP = nil
    D = { round = 3, state = "fighting", now = 300, up = {}, flown = {}, queue = {}, events = {}, orders = {} }
    ALLY.run = nil
    alive = { SV_Unit_AAGun_A = 1, SV_Unit_SAM_A = 1 }
    ALLY.tick(300)                                   -- (the first: the 2 s checks ask what the share hasn't read yet)
    local most, seen = 0, {}
    for i = 1, 16 do
        asks = {}
        ALLY.tick(300 + i * 0.25)
        most = math.max(most, #asks)
        for _, u in ipairs(asks) do seen[u] = (seen[u] or 0) + 1 end
    end
    local nUnits, every = 0, true
    for _, kind in ipairs(DEF_KINDS) do
        for _, u in ipairs(DEF[kind].units) do
            nUnits = nUnits + 1
            if (seen[u] or 0) ~= ((alive[u] or 0) > 0 and 1 or 0) then every = false end
        end
    end
    -- ((0.73.83) a share a tick of 16, each unit every 4 s: the 0.73.79 run's 12-14 ms a tick of these asks late)
    check(most <= math.ceil(nUnits / 16) and every, string.format("B3: the %d defence units' counts asked %d a tick at most: "
          .. "the two up once every 4 s (16 ticks), the ones not built every 8 s; the 2 s checks from them", nUnits, most))
    asks = {}
    for i = 1, 40 do ALLY.tick(304 + i * 0.25) end
    local idle = 0
    for _, u in ipairs(asks) do if u == DEF.ciws.units[4] then idle = idle + 1 end end
    check(idle >= 1 and idle <= 2, "B3: ... a defence not built asked " .. idle .. " times in 10 s")
    ALLY.forgetAlive(DEF.aa.units[2])
    alive[DEF.aa.units[2]] = 1
    asks = {}
    ALLY.tick(314.25); ALLY.tick(316)
    check(ALLY.state().defCount.aa == 2, "B3: one built (ALLY.forgetAlive from the STORE's spawn): counted at the next check")
    alive[DEF.aa.units[2]] = nil
    alive.SV_Unit_SAM_A = 0
    callouts = {}
    for i = 1, 12 do ALLY.tick(316 + i * 0.25) end
    check(callouts[1] and has(callouts[1], "LOST"), "B3: a defence lost: still seen within 3 s (" .. tostring(callouts[1]) .. ")")
    -- B4: the STORE's texts made down at the airfield only; each unit asked once for all the rows' offers; a text sent
    -- only when it changed
    RUN.credits, RUN.spent, RUN.bought, RUN.msg, RUN.defences, RUN.offerShown = 100000, 0, {}, {}, nil, nil
    local sets, labels = 0, 0
    local rawST = SV_SetText
    SV_SetText = function(k, v)
        sets = sets + 1
        if k:find("^SV_Shop_") and not k:find("_Help$") and not k:find("^SV_Shop_Store") then labels = labels + 1 end
        return rawST(k, v)
    end
    onAirfield = false
    RUN.dirty, sets = true, 0
    tick = tick + 1; shopTick(tick)
    check(sets == 0 and RUN.dirty == true, "B4: in flight: no texts made, they wait (RUN.dirty) for the airfield")
    onAirfield = true
    asks = {}
    tick = tick + 1; shopTick(tick)
    local distinct = {}
    for _, u in ipairs(asks) do distinct[u] = (distinct[u] or 0) + 1 end
    local twice = 0
    for _, n in pairs(distinct) do if n > 1 then twice = twice + 1 end end
    check(sets > 0 and not RUN.dirty and #asks > 0 and twice == 0,
          string.format("B4: down at the airfield: made at once, each unit asked once for all the rows (%d asks, %d texts)", #asks, sets))
    check(SV_UnitAlive ~= nil and SV_UnitAlive(DEF.aa.units[1]) == alive[DEF.aa.units[1]] and asks[#asks] == DEF.aa.units[1],
          "B4: ... the native's own SV_UnitAlive back after them")
    RUN.dirty, sets = true, 0
    tick = tick + 3; shopTick(tick)
    check(sets == 0 and not RUN.dirty, "B4: made again with nothing changed: no text sent (each kept by the runtime)")
    RUN.credits = RUN.credits - 500
    RUN.dirty, sets, labels = true, 0, 0
    tick = tick + 3; shopTick(tick)
    check(sets > 0 and labels == 0, "B4: the zollars changed: the help lines and titles that show them sent (" .. sets
          .. "), no row label (" .. labels .. ")")
    check(line("shop: the STORE's texts made down at the airfield only") ~= nil, "B4: logged once")
    SV_SetText, SV_UnitAlive, COOP = rawST, rawUA, keepCOOP
    alive, D, ALLY.run = {}, nil, nil
end

print(fails == 0 and "defences test: all passed" or ("defences test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
