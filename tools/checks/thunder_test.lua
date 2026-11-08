-- thunder_test.lua <mod dir> <work dir> (run by tools/checks/thunder_test.sh): the lightning Anomaly IFF FATAL ERROR /
-- DI..ANT TH..D..R and the storm test (Scripts/sv_anomalies.lua THUNDER, test builds only; tools/re/THUNDER.md) on the real
-- sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies and sv_rounds, the game stubbed (a freed
-- object counts each read or write of it as the crash it would be):
--   the settings: CFG.specials.thunder from survival.ini's [thunder] / [thunder.storm] (INI_ALIAS), never in the rotation;
--     its kind (alone, one aircraft, ready / spawn / tick / over / row), its own throttle (TIER.PRESSURE_OWN), the specials'
--     clean-up's units and label for it (installed at the first tick);
--   the keys (testKey): Ctrl+, and Ctrl+., nothing outside a run, Ctrl+. refused on a joiner, in the break the next round
--     its in 3 s;
--   the storm test: the stock volume spawned deferred at you, its radius set before it begins play, kept on you every tick,
--     your health every tick (a line a second, a move logged), a strike seen by a lightning camera shake (the manager found
--     once, its class default skipped) and by the HUD's hooked call, its follow-up 3.5 s on (your health unchanged, the AI
--     planes inside), the second press's LS_StallTime 3.0, the third press: off, LS_StallTime put back, the storm shrunk to
--     1 cm and destroyed only once nothing's inside it twice running; off by itself after `seconds`;
--   the Anomaly: its spawn (the plain A-10 row on MINDRIPPER's unit, AI level, spawningUnit, from you), its box's callsign
--     (CallsignId, its text set), its camera event, warning and sound, its round's bookkeeping; its health once; its storm
--     on it (the ini's radius) and moved with it; its crackle switched off and destroyed; its row; its death (the storm
--     off, RE_SV_AnomalyEnd, its sound's stop, its pay, its callout, its callsign put back); a spawn it can't make;
--   a co-op joiner: a storm on its live copy while the host's hunts, its copy's MaxHealth, off while you're DOWN and once the
--     host's is over; a host's storm with no fight left taken off;
--   the level torn down: everything forgotten, nothing of it touched.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end

local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local defaultIni = readAll(MOD .. "/config/survival.default.ini")
writeAll(WORK .. "/config/survival.default.ini", defaultIni)
writeAll(WORK .. "/config/survival.ini", defaultIni .. "\r\n[thunder]\r\nreward = 9000\r\n[thunder.storm]\r\nradius_m = 2500\r\n")

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore
VERSION = "0.74.0-thunder.test"

-- the game's objects: LIVE[addr] while the engine holds one; a freed one counts each read / write as a crash
local LIVE, crashes, nextA = {}, 0, 0x10000
local Om = {}
Om.__index = function(t, k)
    if not LIVE[rawget(t, "addr")] then crashes = crashes + 1; return nil end
    return rawget(t, "props")[k]
end
Om.__newindex = function(t, k, v)
    if not LIVE[rawget(t, "addr")] then crashes = crashes + 1; return end
    rawget(t, "props")[k] = v
    local w = rawget(t, "writes")
    w[#w + 1] = k
end
local function obj(full, props)
    nextA = nextA + 0x100
    LIVE[nextA] = true
    return setmetatable({ addr = nextA, full = full, props = props or {}, writes = {} }, Om)
end
local function P(o) return rawget(o, "props") end
local function free(o) LIVE[rawget(o, "addr")] = nil end
function SV_ObjChain(a) return LIVE[a] and 1 or 0 end
function FName(s) return s end

local binds, hooks, notifies, statics, all = {}, {}, {}, {}, {}
Key = { OEM_COMMA = "OEM_COMMA", OEM_PERIOD = "OEM_PERIOD", F11 = "F11", OEM_SIX = "OEM_SIX", OEM_SEVEN = "OEM_SEVEN", OEM_TWO = "OEM_TWO" }
ModifierKey = { CONTROL = "CTRL" }
function RegisterKeyBind(key, mods, fn) binds[key] = fn end
function ExecuteInGameThread(f) f() end
function RegisterHook(path, fn) hooks[path] = fn; return 1, 2 end
function NotifyOnNewObject(cls, fn) notifies[cls] = notifies[cls] or {}; table.insert(notifies[cls], fn) end
function StaticFindObject(p) return statics[p] end
function FindAllOf(c) return all[c] end
function FindFirstOf(c) local l = all[c]; return l and l[1] end
local walks = {}
local alive = {}
function SV_UnitAlive(u) return alive[u] or 0 end

local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
function addrOf(o) return type(o) == "table" and rawget(o, "addr") or nil end
function nameOf(o) if type(o) ~= "table" then return "?" end if SV_ObjChain(rawget(o, "addr")) == 0 then return "?" end return rawget(o, "full") or "?" end
function valid(o)
    if type(o) ~= "table" or rawget(o, "addr") == nil then return false end
    if not LIVE[rawget(o, "addr")] then crashes = crashes + 1; return false end
    return true
end
svLevelOn = true
part("sv_config.lua"); part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_sound.lua"); part("sv_spawn.lua")
part("sv_anomalies.lua"); part("sv_rounds.lua")

local callouts, paid, events, texts, setAc, setLv, spawns, posts = {}, {}, {}, {}, {}, {}, {}, {}
function hudCallout(a, b) callouts[#callouts + 1] = tostring(a) .. " / " .. tostring(b) end
function addCredits(n, why) paid[#paid + 1] = { n = n, why = why } end
function pin() return true end
local eventR = 1
function SV_Event(name) events[#events + 1] = name; return eventR end
function SV_SetText(k, v) texts[k] = v; return 1 end
function SV_SetAircraft(u, row, idx) setAc[#setAc + 1] = { u = u, row = row, idx = idx }; return 1 end
function SV_SetLevel(u, l) setLv[#setLv + 1] = { u = u, l = l }; return 1 end
local planeObjs = {}
local spawnR = 1
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw, su = spawningUnit }
    if spawnR <= 0 then return spawnR end
    local o = obj("BP_OP1001_a10c_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_OP1001_a10c_C_" .. #spawns, {
        HealthInternal = 600, MaxHealth = 60, CallsignId = "", ObjNameID = "SV_Obj_Mindripper", loc = { X = x, Y = y, Z = z },
        K2_GetActorLocation = function(self) return P(self).loc end, GetCallsign = function(self) return P(self).CallsignId end })
    planeObjs[#planeObjs + 1] = o
    for _, fn in ipairs(notifies["/Script/Live.LiveAIPlane"] or {}) do fn(o) end
    alive[unit] = 1
    return 1
end
SV_ERR = SV_ERR or { [0] = "the game spawned nothing" }

local C = CFG.specials.thunder
-- (the sections up to "Survival's own strikes" test the game's own lightning volume, as built on 2026-11-06: stock on,
-- Survival's own strikes off, the test's storm 3 km)
local SHIP = { stock = C.strike.stock, enabled = C.strike.enabled, test_r = C.test.radius_m, storm_r = C.storm.radius_m }
C.strike.stock, C.strike.enabled, C.test.radius_m = true, false, 3000
local function found(pat, from) for i = #logs, from or 1, -1 do if has(logs[i], pat) then return logs[i] end end return nil end
local function press(k) assert(binds[k], "no bind for " .. k)(); KEYQ.drain() end
local TT
for _, t in ipairs(TEST_TICKS) do if t.name == "thunder" then TT = t end end
local function tick(s) clock = clock + (s or 0.25); TT.fn(clock) end

print("the settings and its kind")
check(C ~= nil and C.reward == 9000 and C.storm.radius_m == 2500, "survival.ini's [thunder] / [thunder.storm] read (reward 9000, radius 2500 m)")
check(not found("no section [thunder"), "no 'no section' for its sections")
local inRot = false
for _, k in ipairs(CFG.specials.rotation or {}) do if k == "thunder" then inRot = true end end
check(not inRot, "never in CFG.specials.rotation")
check(C.row == "a10c_common" and C.unit == "SV_Unit_Anomaly", "the plain A-10 row on MINDRIPPER's unit")
local K = SPC.kinds.thunder
check(K and K.alone == true and K.aircraft == 1 and type(K.spawn) == "function" and type(K.tick) == "function" and type(K.over) == "function"
    and type(K.row) == "function" and type(K.ready) == "function" and K.sub() == "IFF FATAL ERROR", "SPC.kinds.thunder: alone, 1 aircraft, its hooks, sub IFF FATAL ERROR")
check(TIER.PRESSURE_OWN.thunder == true, "its own throttle (TIER.PRESSURE_OWN)")
check(#SPC.cleanUnitsOf("thunder") == 0, "the clean-up's units: none before its first tick")
check(TEST_KEYS.OEM_COMMA ~= nil and TEST_KEYS.OEM_PERIOD ~= nil and binds.OEM_COMMA and binds.OEM_PERIOD, "Ctrl+, and Ctrl+. bound through testKey")
check(not found("bound twice"), "no key bound twice")

-- the world
local A = AIRFIELD
local widget = obj("WBP_HUD_Main_C", { vis = 0, op = 1.0, GetVisibility = function(self) return P(self).vis end,
                                       GetRenderOpacity = function(self) return P(self).op end })
local hud = obj("LiveMainHUDParent4K_C", { HudWidget = widget, bShowHUD = true })
local pawn = obj("BP_PlayerPlane_PP0001_a10c_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_PlayerPlane_C_0", {
    HealthInternal = 1500, MaxHealth = 150, LS_MinDebuffTime = 6.0, LS_MaxDebuffTime = 10.0, LS_StallTime = 0.7,
    loc = { X = A.X, Y = A.Y, Z = 300000 }, K2_GetActorLocation = function(self) return P(self).loc end,
    GetVelocity = function(self) return P(self).vel or { X = 20000, Y = 0, Z = 0 } end,
    K2_GetActorRotation = function(self) return { Pitch = P(self).pitch or 2, Yaw = 0, Roll = 0 } end })
survivalPC = obj("PlayerController /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PlayerController_0", { Pawn = pawn, MyHUD = hud })
local cls = obj("BlueprintGeneratedClass " .. C.storm.class)
statics[C.storm.class] = cls
statics[C.storm.curve_table] = obj("CurveTable " .. C.storm.curve_table)
local vols, began = {}, {}
local function newVol()
    local light = obj("PointLightComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.LightningPointLight", { Intensity = 0 })
    local v = obj("BP_LightninigVolume_MS12_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_LightninigVolume_MS12_C_" .. (#vols + 1), {
        Radius = 100000, MinStrikeInterval = 3.0, MaxStrikeInterval = 5.0, WeightCurveName = "MS_12", bEnableCollision = true,
        bTestPlayer = true, bTestEnemy = false, LightningPointLight = light, moves = 0, destroyed = false,
        InsideGameObjects = { n = 1, GetArrayNum = function(self) return self.n end },
        K2_SetActorLocation = function(self, l) P(self).loc = { X = l.X, Y = l.Y, Z = l.Z }; P(self).moves = P(self).moves + 1 end,
        K2_DestroyActor = function(self) P(self).destroyed = true; free(self) end })
    vols[#vols + 1] = v
    return v
end
statics["/Script/Engine.Default__GameplayStatics"] = obj("Default__GameplayStatics", {
    BeginDeferredActorSpawnFromClass = function(self, wc, c, t, how, owner, sc)
        local v = newVol()
        P(v).spawnCls, P(v).loc, P(v).how = c, { X = t.Translation.X, Y = t.Translation.Y, Z = t.Translation.Z }, how
        return v
    end,
    FinishSpawningActor = function(self, v, t, sc) P(v).radiusAtPlay = P(v).Radius; began[#began + 1] = v; return v end })
local fxs = {}
statics["/Script/Niagara.Default__NiagaraFunctionLibrary"] = obj("Default__NiagaraFunctionLibrary", {
    SpawnSystemAtLocation = function(self, wc, sys, at, rot, sc)
        local c = obj("NiagaraComponent", { sys = sys, at = at, sc = sc, off = 0,
                                            Deactivate = function(s2) P(s2).off = P(s2).off + 1 end,
                                            K2_DestroyComponent = function(s2) free(s2) end })
        fxs[#fxs + 1] = c
        return c
    end })
statics[C.fx.system .. "." .. C.fx.system:match("[^/]+$")] = obj("NiagaraSystem " .. C.fx.system)
statics["/Script/Live.Default__LiveSoundBlueprintLibrary"] = obj("Default__LiveSoundBlueprintLibrary", {
    PostEventByName = function(self, who, name) posts[#posts + 1] = name end })
local shakeList = { items = {}, ForEach = function(self, fn) for i, e in ipairs(self.items) do fn(i, { get = function() return e end }) end end }
local mgrCdo = obj("BP_CameraShakeManager_C /Game/Blueprints/Camera/BP_CameraShakeManager.Default__BP_CameraShakeManager_C", { ActiveShakeList = shakeList })
local mgr = obj("BP_CameraShakeManager_C /Engine/Transient.BP_CameraShakeManager_C_0", { ActiveShakeList = shakeList })
all.LiveCameraShakeManager = { mgrCdo, mgr }
local function lightningShake() return { CameraShake = obj("BP_CamShake_Lightning_C /Engine/Transient.BP_CamShake_Lightning_C_0") } end

---------------------------------------------------------------------------------------------------- the storm test
print("the storm test (Ctrl+,)")
D = nil
press("OEM_COMMA")
check(#vols == 0 and found("storm test: Ctrl+, outside a Survival run"), "outside a run: nothing")
D = { round = 7, now = 100, state = "fighting", up = {}, flown = {}, queue = {} }
tick(0.25)
check(#SPC.cleanUnitsOf("thunder") == 1 and SPC.cleanUnitsOf("thunder")[1] == "SV_Unit_Anomaly", "the clean-up's units installed at the first tick: SV_Unit_Anomaly")
check(#SPC.cleanUnitsOf("anomaly") == 1, "the Anomaly's own still answered")
local from = #logs + 1
press("OEM_COMMA")
local v1 = vols[1]
check(v1 ~= nil and P(v1).spawnCls == cls and P(v1).how == 1, "the stock volume spawned deferred (AlwaysSpawn) from its class")
check(v1 and P(v1).radiusAtPlay == 300000, "its Radius 300000 cm (3 km) set before it began play (" .. tostring(v1 and P(v1).radiusAtPlay) .. ")")
check(v1 and P(v1).loc.X == A.X and P(v1).loc.Z == 300000, "at your plane")
check(THUNDER.storm and THUNDER.storm.owner == "test" and THUNDER.test ~= nil, "the test's storm up")
check(found("storm test: Ctrl+,, the storm on you for 60 s, 3.0 km round you", from) and found("LS_MinDebuffTime 6.0, LS_MaxDebuffTime 10.0, LS_StallTime 0.7", from),
    "logged with your plane's LS_ values")
check(found("thunder: storm up for the test", from) and found("reads back Radius 300000 cm", from), "the storm's line: " .. tostring(found("thunder: storm up", from)))
check(hooks["/Script/Live.LiveHUD:BeginHUDDistortionLightning"] and hooks["/Script/Live.LiveHUD:EndHUDDistortionLightning"], "the HUD's lightning calls hooked")
check(found("camera shake manager found (BP_CameraShakeManager_C /Engine/Transient", from), "the shake manager found, its class default skipped")
check(has(callouts[#callouts], "TEST: STORM ON YOU / 60 S, 3.0 KM"), "callout: " .. tostring(callouts[#callouts]))
-- kept on you
P(pawn).loc = { X = A.X + 50000, Y = A.Y, Z = 310000 }
tick(0.25)
check(P(v1).loc.X == A.X + 50000 and P(v1).moves >= 1, "kept on you as you fly")
for _ = 1, 4 do tick(0.25) end
check(found("storm test: +1 s: health 1500 1500 1500 1500", from) or found("storm test: +2 s: health 1500", from), "a line a second with your health each tick: " .. tostring(found("storm test: +", from)))
-- a strike: the lightning shake and the HUD's call
from = #logs + 1
shakeList.items[1] = lightningShake()
hooks["/Script/Live.LiveHUD:BeginHUDDistortionLightning"](nil, { get = function() return 7.5 end })
tick(0.25)
local sl = found("storm test: strike 1 at", from)
check(sl and has(sl, "the HUD's BeginHUDDistortionLightning (noise 7.5 s)") and has(sl, "a lightning camera shake (BP_CamShake_Lightning_C_0)")
    and has(sl, "your health 1500"), "strike 1 seen by the HUD's call and the shake: " .. tostring(sl))
tick(0.25)
check(not found("storm test: strike 2", from), "the same strike not counted twice while its shake plays")
shakeList.items = {}
P(widget).vis = 1                                -- (the HUD widget collapsed: seen as hidden)
tick(0.25)
check(not found("storm test: strike 2", from), "the HUD hidden within 1.5 s of it: the same strike")
P(widget).vis = 0
tick(0.25)
check(found("storm test: the HUD back after", from), "the HUD back: " .. tostring(found("the HUD back", from)))
for _ = 1, 12 do tick(0.25) end
local fl = found("storm test: strike 1, 3.5 s on", from)
check(fl and has(fl, "your health 1500 -> 1500 (unchanged)") and has(fl, "no health moved"), "its follow-up: health unchanged: " .. tostring(fl))
-- your health moves (not a strike: logged as it is)
from = #logs + 1
P(pawn).HealthInternal = 1400
tick(0.25)
check(found("storm test: your health moved 1500 -> 1400", from), "a health move logged")
-- second press: the stall flag
from = #logs + 1
press("OEM_COMMA")
check(P(pawn).LS_StallTime == 3.0 and found("your plane's LS_StallTime 0.7 -> 3.0 (written", from), "second press: LS_StallTime 3.0 on your plane")
-- third press: off; the storm destroyed only once nothing's inside it
from = #logs + 1
press("OEM_COMMA")
check(P(pawn).LS_StallTime == 0.7, "LS_StallTime put back to 0.7")
check(THUNDER.storm == nil and THUNDER.test == nil and P(v1).Radius == 1.0 and not P(v1).destroyed, "off: shrunk to 1 cm, not destroyed yet")
check(found("storm test: over (Ctrl+,)", from) and found("1 strikes seen", from), "its summary: " .. tostring(found("storm test: over", from)))
tick(0.25); tick(0.25); tick(0.25)
check(not P(v1).destroyed, "not destroyed while something's inside it")
P(v1).InsideGameObjects.n = 0
tick(0.25)
check(not P(v1).destroyed, "not on its first empty read")
tick(0.25)
check(P(v1).destroyed and found("thunder: the test's storm destroyed", from), "destroyed on the second empty read")
-- by itself after `seconds`
from = #logs + 1
press("OEM_COMMA")
local v2 = vols[#vols]
check(v2 ~= v1 and THUNDER.storm and THUNDER.storm.owner == "test", "pressed again: a new storm")
for _ = 1, 241 do tick(0.25) end
check(THUNDER.storm == nil and found("storm test: over (60 s up)", from), "off by itself 60 s on")
P(v2).InsideGameObjects.n = 0; tick(0.25); tick(0.25)

---------------------------------------------------------------------------------------------------- the Anomaly
print("the Anomaly (Ctrl+.)")
COOP = { client = function() return true end }
from = #logs + 1
press("OEM_PERIOD")
check(D.forceSpecial == nil and found("thunder: Ctrl+.: the host brings it", from), "a joiner: refused")
COOP = nil
D.state, D.at = "wait", D.now + 15
press("OEM_PERIOD")
check(D.forceSpecial == "thunder" and D.at == D.now + 3 and has(callouts[#callouts], "TEST: IFF FATAL ERROR / STARTING NOW"), "in the break: the next round its, in 3 s")
alive.SV_Unit_Anomaly = 1
check(K.ready() == false, "not ready while its unit is up")
local okC, whyC = SPC.canStart("thunder")
check(okC == false, "SPC.canStart: no (" .. tostring(whyC) .. ")")
alive.SV_Unit_Anomaly = 0
check(K.ready() == true, "ready with its unit free")
-- its spawn
D.special = { kind = "thunder", state = "pending" }
D.state = "spawning"
from = #logs + 1
local cbefore = #callouts
check(K.spawn(D.now) == true, "spawned")
local sp = spawns[#spawns]
check(sp.unit == "SV_Unit_Anomaly" and sp.su == "SV_Unit_Anomaly" and spawningUnit == nil, "on SV_Unit_Anomaly, spawningUnit set around it")
check(setAc[#setAc].u == "SV_Unit_Anomaly" and setAc[#setAc].row == "a10c_common" and setAc[#setAc].idx == nil, "SV_SetAircraft(SV_Unit_Anomaly, a10c_common)")
check(setLv[#setLv].l == 500, "AI level 5")
local dx, dy = sp.x - P(pawn).loc.X, sp.y - P(pawn).loc.Y
local d = math.sqrt(dx * dx + dy * dy) / 100000
check(d >= 7.99 and d <= 12.01, string.format("8-12 km from you (%.1f)", d))
check(sp.z >= CFG.altitude_m[1] * 100 and sp.z <= CFG.altitude_m[2] * 100, "at the pool's heights")
local boss = planeObjs[#planeObjs]
check(P(boss).CallsignId == "SV_Thunder_Name" and texts.SV_Thunder_Name == "DI..ANT TH..D..R", "its box's callsign: SV_Thunder_Name = DI..ANT TH..D..R")
check(P(boss).ObjNameID == "SV_Obj_Mindripper", "its ObjNameID left alone (only logged)")
check(found("thunder: its box", from) and found("ObjNameID 'SV_Obj_Mindripper'", from), "its box's line: " .. tostring(found("its box", from)))
check(D.up.SV_Unit_Anomaly and D.flown.SV_Unit_Anomaly and D.flightTier.SV_Unit_Anomaly == #CFG.tiers.list, "in the round's flights, at the top tier")
check(D.special.state == "hunt" and D.special.at == D.now, "its state hunt")
check(events[#events] == "RE_SV_AnomalyCam_E", "its focus camera (ms22-01: RE_SV_AnomalyCam_E)")
check(has(callouts[cbefore + 1], "WARNING: IFF FATAL ERROR / DI..ANT TH..D..R: ITS STORM BLINDS YOU"), "its warning: " .. tostring(callouts[cbefore + 1]))
check(posts[#posts] == C.start_sound, "its sound posted (" .. tostring(posts[#posts]) .. ")")
-- its first tick: health, storm
from = #logs + 1
local s = D.special
K.tick(D.now + 0.25, s)
local hx = math.min(C.health_max_x, 1 + C.health_per_round * math.max(0, D.round - CFG.specials.first))
check(math.abs(P(boss).MaxHealth - C.health * hx) < 0.01 and P(boss).HealthInternal == math.floor(C.health * hx * 10 + 0.5),
    string.format("its health x%.2f: MaxHealth %s, HealthInternal %s", hx, tostring(P(boss).MaxHealth), tostring(P(boss).HealthInternal)))
local vb = vols[#vols]
check(THUNDER.storm and THUNDER.storm.owner == "boss" and P(vb).radiusAtPlay == 250000, "its storm up on it, the ini's 2.5 km")
check(P(vb).loc.X == P(boss).loc.X and P(vb).loc.Y == P(boss).loc.Y, "at it")
local hpWas = P(boss).HealthInternal
P(boss).loc = { X = P(boss).loc.X + 30000, Y = P(boss).loc.Y, Z = P(boss).loc.Z }
P(boss).HealthInternal = hpWas - 100
K.tick(D.now + 0.5, s)
check(P(vb).loc.X == P(boss).loc.X, "moved with it")
check(P(boss).HealthInternal == hpWas - 100, "its health set once only")
check(#fxs >= 1 and P(fxs[1]).sys == statics[C.fx.system .. ".NS_CloudLightning"], "its cloud lightning crackling on it")
local row = K.row(s, CFG.hud.text)
check(type(row) == "string" and (has(row, "DI..ANT TH..D..R: ") or has(row, "IN ITS STORM")), "its row: " .. tostring(row))
P(pawn).loc = { X = P(boss).loc.X + 100000, Y = P(boss).loc.Y, Z = P(boss).loc.Z }
K.tick(D.now + 0.75, s)
check(K.row(s, CFG.hud.text) == "DI..ANT TH..D..R: IN ITS STORM", "inside its storm: IN ITS STORM")
tick(4)
check(P(fxs[1]).off >= 1, "its crackle switched off life_s on")
tick(2.5)
check(not LIVE[rawget(fxs[1], "addr")], "and destroyed 2 s after")
-- a strike on you in its storm
from = #logs + 1
shakeList.items[1] = lightningShake()
K.tick(D.now + 1, s)
check(found("thunder: strike 1 at", from), "a strike in its storm logged (log_strikes)")
shakeList.items = {}
-- its death
from = #logs + 1
alive.SV_Unit_Anomaly = 0
K.tick(D.now + 3, s)
check(s.state == "done" and THUNDER.storm == nil and P(vb).Radius == 1.0, "down: its storm off (shrunk)")
check(events[#events] == "RE_SV_AnomalyEnd", "RE_SV_AnomalyEnd fired")
check(posts[#posts] == C.stop_sound, "its sound's stop posted")
local pay = 9000 + C.reward_per_round * D.round
check(paid[#paid].n == pay and has(paid[#paid].why, "DI..ANT TH..D..R down"), "paid " .. pay)
check(has(callouts[#callouts], "DI..ANT TH..D..R DOWN / +" .. pay .. " ZOLLARS"), "callout: " .. tostring(callouts[#callouts]))
check(P(boss).CallsignId == "", "its callsign put back")
check(found("thunder: round 7, DI..ANT TH..D..R shot down", from), "logged")
check(SPC.cleanLabel("SV_Unit_Anomaly") == "DI..ANT TH..D..R's unit (SV_Unit_Anomaly)", "the clean-up's label")
P(vb).InsideGameObjects.n = 0
tick(0.25); tick(0.25)
check(P(vb).destroyed, "its storm destroyed once nothing's inside it")
K.over(D.now + 4, s)
-- a spawn it can't make
D.special = { kind = "thunder", state = "pending" }
spawnR = 0
check(K.spawn(D.now) == false and found("not spawned"), "SV_Spawn refusing: false (a normal round instead)")
spawnR = 1
alive.SV_Unit_Anomaly = 1
check(K.spawn(D.now) == false and found("SV_Unit_Anomaly still has 1 up"), "its unit up: false")
alive.SV_Unit_Anomaly = 0

---------------------------------------------------------------------------------------------------- a host's storm left over
print("a host's storm with no fight left")
D.special = { kind = "thunder", state = "hunt", at = D.now }
local okU = THUNDER.stormUp("boss", P(pawn).loc, 3000)
D.special = nil
tick(0.25)
check(okU and THUNDER.storm == nil and found("the boss's storm off (its round is over)"), "taken off by the tick")
P(vols[#vols]).InsideGameObjects.n = 0; tick(0.25); tick(0.25)

---------------------------------------------------------------------------------------------------- a co-op joiner
print("a co-op joiner")
COOP = { client = function() return true end }
DOWN = { me = function() return false end }
local copy = obj("BP_OP1001_a10c_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_OP1001_a10c_C_copy", {
    HealthInternal = 5000, MaxHealth = 60, CallsignId = "", loc = { X = A.X + 200000, Y = A.Y, Z = 300000 },
    K2_GetActorLocation = function(self) return P(self).loc end })
planes[#planes + 1] = { obj = copy, unit = "SV_Unit_Anomaly", name = "BP_OP1001_a10c_C_copy" }
D.hostSpecial = { kind = "thunder", state = "hunt" }
from = #logs + 1
tick(0.25)
local vc = vols[#vols]
check(THUNDER.storm and THUNDER.storm.owner == "copy" and P(vc).loc.X == A.X + 200000, "a storm on this game's copy")
check(P(copy).CallsignId == "SV_Thunder_Name", "its copy's box named here")
check(math.abs(P(copy).MaxHealth - C.health * hx) < 0.01 and P(copy).HealthInternal == 5000, "its copy's MaxHealth set, its health left to the host's")
DOWN.me = function() return true end
tick(0.25)
check(THUNDER.storm == nil and found("the copy's storm off (you're DOWN)", from), "off while you're DOWN")
DOWN.me = function() return false end
tick(0.25)
check(THUNDER.storm and THUNDER.storm.owner == "copy", "back on when you're not")
D.hostSpecial = { kind = "thunder", state = "done" }
tick(0.25)
check(THUNDER.storm == nil and found("the copy's storm off (the host's is over)", from) and P(copy).CallsignId == "", "off once the host's is over, its callsign put back")
P(vc).InsideGameObjects.n = 0; tick(0.25); tick(0.25)
check(P(vc).destroyed, "and destroyed once empty")
D.hostSpecial = nil
COOP, DOWN = nil, nil

---------------------------------------------------------------------------------------------------- Survival's own strikes
-- ((2026-11-08) the user's test of 0.74.34: the stock volume never struck, "this storm needs to be insanely violent")
print("Survival's own strikes (the shipped settings)")
check(SHIP.stock == false and SHIP.enabled == true and SHIP.test_r == 7000 and C.strike.damage_pct == 10, "shipped: no stock volume, "
    .. "Survival's own strikes on, the test's storm 7 km, 10% of your health a strike")
C.strike.stock, C.strike.enabled, C.test.radius_m = SHIP.stock, SHIP.enabled, SHIP.test_r
local GSo = P(statics["/Script/Engine.Default__GameplayStatics"])
local paused, gameT = false, 500
GSo.GetTimeSeconds = function() return gameT end
GSo.IsGamePaused = function() return paused end
local function gtick(sec) clock = clock + sec; if not paused then gameT = gameT + sec end; TT.fn(clock) end
local hudCalls, inv, hurts, shakesOn, attached, atPosts = {}, {}, {}, {}, {}, {}
P(hud).BeginHUDDistortionLightning = function(self, t, info) hudCalls[#hudCalls + 1] = { t = t, info = info } end
P(hud).EndHUDDistortionLightning = function(self) hudCalls[#hudCalls + 1] = { ended = true } end
P(survivalPC).ClientStartCameraShake = function(self, c, sc) shakesOn[#shakesOn + 1] = { cls = c, sc = sc } end
P(statics["/Script/Niagara.Default__NiagaraFunctionLibrary"]).SpawnSystemAttached = function(self, sys, comp, sock, off)
    local c = obj("NiagaraComponent", { sys = sys, off = 0, Deactivate = function(s2) P(s2).off = P(s2).off + 1 end,
                                        K2_DestroyComponent = function(s2) free(s2) end })
    attached[#attached + 1] = { sys = sys, off = off }
    return c
end
P(statics["/Script/Live.Default__LiveSoundBlueprintLibrary"]).PostEventAtActorByName = function(self, name, actor) atPosts[#atPosts + 1] = name end
P(pawn).K2_GetRootComponent = function() return obj("SceneComponent root") end
for _, k in ipairs({ "fx_strike", "fx_miss", "fx_sign" }) do
    local path = C.strike[k]
    statics[path .. "." .. path:match("[^/]+$")] = obj("NiagaraSystem " .. path)
end
statics[C.strike.shake .. "." .. C.strike.shake:match("[^/]+$") .. "_C"] = obj("BlueprintGeneratedClass BP_CamShake_Lightning_C")
function SV_Invert(pp, r, f, a, y, sw, t) inv[#inv + 1] = { p = pp, r = r, a = a, t = t }; return 100 end
DECOY = { hurtMe = function(c) hurts[#hurts + 1] = c; return "-15 HP (10% of your 150), 135 HP left" end }
local keepChance = C.strike.chance
D = { round = 7, now = 100, state = "fighting", up = {}, flown = {}, queue = {} }
P(pawn).loc = { X = A.X, Y = A.Y, Z = 300000 }
from = #logs + 1
local nVols = #vols
press("OEM_COMMA")
check(THUNDER.storm and THUNDER.storm.own and #vols == nVols and found("Survival's own strikes (no stock volume)", from),
    "the test's storm: Survival's own, no stock volume spawned: " .. tostring(found("thunder: storm up", from)))
gtick(0.25)
check(found("lightning: you're inside test's storm (7.0 km round it)", from) and atPosts[#atPosts] == C.strike.sound_inside,
    "inside it: logged, the inside ambience on your plane")
C.strike.chance = { 1.0 }
gtick(3)
local hc = hudCalls[1]
check(hc and hc.t >= 10 and hc.t <= 16 and hc.info.UseHideHUD == true and hc.info.HideHUDTime == 3.5 and hc.info.NeedUpdateDistortion == true
    and hc.info.MaxDistortionScale == 1.0, "a strike: the HUD's own lightning (out 3.5 s, static 10-16 s, its distortion)")
check(hurts[1] and hurts[1].hit.damage_pct == 10 and hurts[1].hit.can_kill == true, "10% of your health (THE DECOY's hurt: a lethal one your death)")
check(shakesOn[1] and has(nameOf(shakesOn[1].cls), "BP_CamShake_Lightning_C") and shakesOn[1].sc == 1.5, "the lightning camera shake x1.5")
check(attached[1] and has(nameOf(attached[1].sys), "NS_ElectricDischargeM001"), "the discharge on your plane")
check(inv[1] and inv[1].r == 1 and inv[1].t == 1 and inv[1].a == addrOf(pawn), "your controls upset: roll inverted, throttle and brake swapped")
local hasStruck = false
for _, n in ipairs(atPosts) do if n == C.strike.sound_strike then hasStruck = true end end
check(hasStruck and posts[#posts] == C.strike.sound_noise, "the struck sound on your plane, the static's noise")
check(found("lightning: strike 1 on you (test's storm, roll 1): HUD out 3.5 s", from), "logged: " .. tostring(found("lightning: strike 1", from)))
C.strike.chance = { 0 }                                   -- (no second strike: its roll may come within the next 1.75 s)
gtick(1.75)
check(inv[#inv].r == 0 and inv[#inv].t == nil, "the upset over 1.5 s on")
C.strike.chance = { 0 }
paused = true
local nHud, nHurt = #hudCalls, #hurts
for _ = 1, 40 do gtick(0.5) end
check(#hudCalls == nHud and #hurts == nHurt, "paused 20 s: no roll, the static not ended (the game's clock stopped)")
paused = false
for _ = 1, 40 do gtick(0.5) end
check(hudCalls[#hudCalls].ended == true and posts[#posts] == C.strike.sound_noise_stop and found("lightning: the static over", from),
    "the static over on time (the HUD's End, the noise stopped)")
local miss, sign = nil, nil
for _, a in ipairs(attached) do
    if has(nameOf(a.sys), "NS_ElectricEvasion001") then miss = a end
    if has(nameOf(a.sys), "NS_ElectricSign001") then sign = a end
end
check(miss and miss.off.X >= 40000 and miss.off.X <= 55000 and sign, "a miss: the evasion bolt 400-550 m ahead, the sparks on you")
check(#hurts == nHurt, "no damage from a miss")
P(pawn).loc = { X = A.X + 900000, Y = A.Y, Z = 300000 }
local keepMove = THUNDER.stormMove
THUNDER.stormMove = function() return true end           -- (the storm left where it was: you fly out of it)
gtick(0.25)
check(found("lightning: you're out of test's storm (1 strikes so far)", from) and atPosts[#atPosts] == C.strike.sound_inside_stop,
    "out of it: logged, the inside ambience stopped")
THUNDER.stormMove = keepMove
DOWN = { me = function() return true end }
P(pawn).loc = { X = A.X, Y = A.Y, Z = 300000 }
C.strike.chance = { 1.0 }
nHurt = #hurts
for _ = 1, 20 do gtick(0.5) end
check(#hurts == nHurt, "DOWN: no strikes")
DOWN = nil
press("OEM_COMMA"); press("OEM_COMMA")
check(THUNDER.storm == nil and found("the test's storm off (Ctrl+,)", from), "Ctrl+, twice more: the storm off")
C.strike.chance, C.strike.stock = keepChance, true      -- (the stock volume again for the test below)

---------------------------------------------------------------------------------------------------- the storm's build-up
-- ((2026-11-08) the user: "have the storm gather for 3 rounds slowly building up until it's literally a typhoon")
print("the storm's build-up (Ctrl+], Ctrl+')")
C.strike.stock = false
part("sv_sky.lua")
local B = C.buildup
-- ((2026-11-08) the user's recording of 0.74.36: every write of the cloud values blacked the whole sky out for a moment)
check(B.sky.clouds == false and B.sky.rain_pillar == false, "shipped: the cloud values and the rain pillar not written (they black the sky out)")
B.sky.clouds, B.sky.rain_pillar = true, true             -- (their writes' own checks below; off again after)
local mine = obj("CloudlySkyParams /Game/Cloudly/CloudlySkyParams/Ingame/Mission004/CSP_ms04_20251218b.CSP_ms04_20251218b", { Data = {
    CloudDensityExtintionBalance = 1.0, EnableClouds = true, SunIntensity = { Factor = 10 },
    CloudLayer0 = { CloudDensity = 0.3, RainCloudEnable = false, StartHeightInKm = 1.5, RainPillarCenterOverride = false,
                    RainPillarCenterInKm = { X = 0, Y = 0 }, RainPillarRadiusOverride = false, RainPillarRadiusInKm = 2 },
    CloudLayer1 = { CloudDensity = 0.2 }, CloudLayer2 = { CloudDensity = 0.1 } } })
statics[B.sky.asset] = obj("CloudlySkyParams " .. B.sky.asset, { Data = {
    CloudDensityExtintionBalance = 1.0, EnableClouds = true,
    CloudLayer0 = { CloudDensity = 0.9, RainCloudEnable = true, StartHeightInKm = 0.8 },
    CloudLayer1 = { CloudDensity = 0.2 }, CloudLayer2 = { CloudDensity = 0.5 } } })
SKY.viewCached = function() return { asset = mine, actor = true, rend = {}, ctrl = {}, ppv = {} } end
statics[B.turbulence.shake .. "." .. B.turbulence.shake:match("[^/]+$") .. "_C"] = obj("BlueprintGeneratedClass BP_CamShake_Turbulence_C")
local ws = obj("ChronicleWorldSettings /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.ChronicleWorldSettings_0",
    { bIsWorldRain = false, bIsRainVolume = false, RainVFXBrightness = 1.0 })
all.ChronicleWorldSettings = { ws }
local function D0(r, st) D.round, D.state = r, st end
D = { round = 6, now = 100, state = "wait", up = {}, flown = {}, queue = {} }
P(pawn).loc = { X = A.X, Y = A.Y + 9000000, Z = 300000 }        -- (far off every cell to start)
C.strike.chance = { 0 }
from = #logs + 1
local nPosts = #posts
press("OEM_SIX")
check(found("storm build-up: on (Ctrl+]): Distant Thunder at round 10, stages 1-3 in rounds 7-9", from), "Ctrl+] in a break: Distant Thunder at round 10")
check(has(callouts[#callouts], "WEATHER WARNING / DISTANT THUNDER IN ROUND 10"), "its callout: " .. tostring(callouts[#callouts]))
gtick(0.25)
local bu = THUNDER.buildup()
check(bu and bu.stage == 1 and #bu.cells == 2 and bu.cells[1].r == 200000 and found("storm build-up: stage 1: 2 storm cells (2.0 km round", from),
    "stage 1 at once: 2 cells of 2 km: " .. tostring(found("storm build-up: stage 1", from)))
local distant = false
for i = nPosts + 1, #posts do if posts[i] == B.sound.distant then distant = true end end
check(distant, "the distant thunder from stage 1")
check(found("storm build-up: 4 of", from) and found("CloudLayer0.CloudDensity 0.3 -> 0.9", from) and found("CloudLayer0.RainCloudEnable false -> true", from),
    "the sky fields that differ from Mission 12's, logged: " .. tostring(found("sky fields differ", from)))
for _ = 1, 100 do gtick(1) end
local d0 = mine.Data.CloudLayer0.CloudDensity
check(math.abs(d0 - (0.3 + 0.6 * 0.3)) < 1e-6 and mine.Data.CloudLayer0.RainCloudEnable == false and math.abs(mine.Data.CloudLayer2.CloudDensity - 0.22) < 1e-6,
    string.format("the sky 30%% of the way after its ramp (cloud density %.3f), a bool not yet switched", d0))
D0(7, "fighting"); gtick(0.25)
check(THUNDER.buildup().stage == 1, "round 7 (N-3): stage 1")
D0(8, "fighting"); gtick(0.25)
bu = THUNDER.buildup()
check(bu.stage == 2 and #bu.cells == 4 and bu.cells[1].r == 300000, "round 8 (N-2): stage 2, 4 cells of 3 km")
check(D.forceSpecial == nil, "no forced round yet")
D0(9, "fighting"); gtick(0.25)
bu = THUNDER.buildup()
check(bu.stage == 3 and #bu.cells == 6 and P(ws).bIsWorldRain == true and P(ws).RainVFXBrightness == 10, "round 9 (N-1): stage 3, 6 cells, the rain on")
check(D.forceSpecial == "thunder" and found("storm build-up: round 10 is Distant Thunder's", from), "round 10 forced to be Distant Thunder's")
-- a strike in a cell, its turbulence
local cl = bu.cells[1]
P(pawn).loc = { X = cl.at.X, Y = cl.at.Y, Z = 300000 }
C.strike.chance = { 1.0 }
local nH, nS = #hurts, #shakesOn
for _ = 1, 30 do gtick(0.25) end
check(found("lightning: you're inside storm cell 1 (stage 3) (4.0 km round it): a roll every 2.5-4.5 s, chance x1.00", from), "inside a cell: logged")
check(#hurts > nH and found("lightning: strike", from) and found("(storm cell 1 (stage 3), roll", from), "a cell's strike: 10% of your health, logged by its cell")
local turb = false
for i = nS + 1, #shakesOn do if has(nameOf(shakesOn[i].cls), "BP_CamShake_Turbulence_C") and math.abs(shakesOn[i].sc - 0.9) < 1e-6 then turb = true end end
check(turb, "the turbulence inside it (x0.9 at stage 3)")
C.strike.chance = { 0 }
P(pawn).loc = { X = A.X, Y = A.Y + 9000000, Z = 300000 }
gtick(0.25)
-- round 10: the typhoon, the rain pillar on the A-10
D0(10, "fighting")
local okT = THUNDER.stormUp("boss", { X = A.X + 500000, Y = A.Y - 300000, Z = 300000 }, 7000)
gtick(1.1)
bu = THUNDER.buildup()
local L0 = mine.Data.CloudLayer0
check(okT and bu.stage == 4 and L0.RainPillarCenterOverride == true and math.abs(L0.RainPillarCenterInKm.X - (A.X + 500000) / 100000) < 1e-6
    and L0.RainPillarRadiusInKm == 6, "round 10: the typhoon, the rain pillar on the A-10 (" .. tostring(found("the rain pillar", from)) .. ")")
THUNDER.stormDown("its round is over")
D0(10, "wait"); gtick(0.25)
check(THUNDER.buildup().clearing and has(callouts[#callouts], "THE STORM CLEARS") and P(ws).bIsWorldRain == false and P(ws).RainVFXBrightness == 1.0
    and L0.RainPillarCenterOverride == false, "round 10 over: the storm clears (the rain and the pillar back)")
for _ = 1, 120 do gtick(1) end
check(THUNDER.buildup() == nil and found("storm build-up: over (cleared)", from) and math.abs(mine.Data.CloudLayer0.CloudDensity - 0.3) < 1e-6
    and mine.Data.CloudLayer0.RainCloudEnable == false and posts[#posts] == B.sound.distant_stop, "cleared: the sky back as it was, the distant thunder stopped")
-- Ctrl+': the stages by hand (the user's look at 0.74.36: "Nothing is happening": the sky at once, cell 1 on you)
check(math.abs(mine.Data.SunIntensity.Factor - 10) < 1e-6, "cleared: the sun's intensity back too")
P(pawn).loc = { X = A.X + 1234567, Y = A.Y - 765432, Z = 300000 }
press("OEM_SEVEN"); gtick(0.25)
bu = THUNDER.buildup()
check(bu and bu.stage == 1 and bu.forced == 1, "Ctrl+': stage 1 by hand")
check(math.abs(mine.Data.CloudLayer0.CloudDensity - 0.48) < 1e-6 and math.abs(mine.Data.SunIntensity.Factor - 10 * (1 - 0.6 * 0.3)) < 1e-6,
    string.format("... its sky at once: 30%% (cloud density %.3f), the sun darkened (%.2f)", mine.Data.CloudLayer0.CloudDensity, mine.Data.SunIntensity.Factor))
check(bu.cells[1].base.X == P(pawn).loc.X and bu.cells[1].base.Y == P(pawn).loc.Y, "... cell 1 on you")
local near = true
for i = 2, #bu.cells do
    local c2 = bu.cells[i]
    if math.sqrt((c2.base.X - P(pawn).loc.X) ^ 2 + (c2.base.Y - P(pawn).loc.Y) ^ 2) > 28 * 0.35 * 100000 + 1 then near = false end
end
check(near, "... the others close round you")
ARC.on = true
press("OEM_SEVEN"); gtick(0.25)
check(math.abs(mine.Data.SunIntensity.Factor - 10 * (1 - 0.6 * 0.3)) < 1e-6 and found("storm build-up: its darkening the night arc owns the light", from),
    "the night arc on: the darkening left to it")
ARC.on = false
press("OEM_SEVEN"); gtick(0.25); press("OEM_SEVEN"); gtick(0.25)
check(THUNDER.buildup().stage == 4 and math.abs(mine.Data.CloudLayer0.CloudDensity - 0.9) < 1e-6, "... 3, 4: the storm's sky at once")
press("OEM_SEVEN"); gtick(0.25)
check(found("storm build-up: the storm clears (Ctrl+')", from) and (THUNDER.buildup() == nil or THUNDER.buildup().clearing), "... then the storm clears")
for _ = 1, 120 do gtick(1) end
check(THUNDER.buildup() == nil, "and is over")
-- the shipped way: the clouds left alone, only the darkening
B.sky.clouds, B.sky.rain_pillar = false, false
press("OEM_SEVEN"); gtick(0.25)
check(math.abs(mine.Data.CloudLayer0.CloudDensity - 0.3) < 1e-6 and math.abs(mine.Data.SunIntensity.Factor - 10 * (1 - 0.6 * 0.3)) < 1e-6,
    "the shipped way (clouds off): the cloud values left alone, the sun darkened")
THUNDER.buEnd("the test")
check(math.abs(mine.Data.SunIntensity.Factor - 10) < 1e-6, "... and put back")

-- Ctrl+/: the sky probe (each group of the storm sky's values written 3 times, then put back as the next is written)
print("the sky probe (Ctrl+/)")
from = #logs + 1
press("OEM_TWO")
check(has(callouts[#callouts], "SKY PROBE 1/9: A SUN VALUE UNCHANGED (THE CONTROL) / WATCH THE SKY: 3 WRITES, 1 S APART")
    and math.abs(mine.Data.SunIntensity.Factor - 10) < 1e-6 and found("sky probe: group 1 of 9 (a sun value unchanged (the control), 1 values): write 1 of 3", from),
    "group 1, the control: a sun value written as it is")
gtick(1.05); gtick(1.05)
check(found("write 3 of 3", from) and not found("write 4", from), "... 3 writes, a second apart")
press("OEM_TWO"); press("OEM_TWO")
check(math.abs(mine.Data.CloudLayer0.CloudDensity - 0.9) < 1e-6 and math.abs(mine.Data.CloudLayer2.CloudDensity - 0.5) < 1e-6
    and has(callouts[#callouts], "SKY PROBE 3/9: THE CLOUDS' DENSITY"), "group 3: the storm's cloud densities")
press("OEM_TWO")
check(math.abs(mine.Data.CloudLayer0.CloudDensity - 0.3) < 1e-6 and math.abs(mine.Data.CloudLayer0.StartHeightInKm - 0.8) < 1e-6
    and found("sky probe: group 3 (the clouds' density) put back", from), "group 4: the heights; group 3 put back first")
for _ = 1, 5 do press("OEM_TWO") end
local you = P(pawn).loc
check(mine.Data.CloudLayer0.RainPillarCenterOverride == true and math.abs(mine.Data.CloudLayer0.RainPillarCenterInKm.X - you.X / 100000) < 1e-6
    and math.abs(mine.Data.CloudLayer0.StartHeightInKm - 1.5) < 1e-6, "group 9: the rain pillar on you; the rest back")
press("OEM_TWO")
check(mine.Data.CloudLayer0.RainPillarCenterOverride == false and has(callouts[#callouts], "SKY PROBE: ALL BACK") and found("sky probe: every group back as it was", from),
    "a press after the last: everything back")

-- a co-op joiner builds the same cells from the host's seed
D0(20, "wait")
press("OEM_SIX"); D0(22, "fighting"); gtick(0.25)
check(THUNDER.buildup().stage == 2 and not THUNDER.buildup().byHand, "a host's build-up at stage 2 (round 22 of N 24)")
local hostCells = THUNDER.buildup().cells
local seed = THUNDER.buildup().seed
local hx, hy = hostCells[1].base.X, hostCells[1].base.Y
THUNDER.buEnd("the test")
COOP = { client = function() return true end }
THUNDER.buFromHost({ "tb", "nan", "5", "0" }); THUNDER.buFromHost({ "tb", "9", "5", "0" }); THUNDER.buFromHost({ "tb", "2", "-4", "0" })
check(THUNDER.buildup() == nil, "a joiner: bad numbers dropped")
THUNDER.buFromHost({ "tb", "2", tostring(seed), "0" })
gtick(0.25)
local jb = THUNDER.buildup()
check(jb and jb.joiner and jb.stage == 2 and #jb.cells == 4 and jb.cells[1].base.X == hx and jb.cells[1].base.Y == hy, "a joiner: the host's stage 2, the same cells from its seed")
press("OEM_SIX")
check(found("storm build-up: Ctrl+]: the host brings it (you're a joiner)"), "a joiner's Ctrl+] refused")
THUNDER.buFromHost({ "tb", "0", tostring(seed), "0" })
check(THUNDER.buildup() == nil, "the host's over: the joiner's too")
COOP = nil
C.strike.stock = true

---------------------------------------------------------------------------------------------------- the level torn down
print("the level torn down")
from = #logs + 1
press("OEM_COMMA")
local vq = vols[#vols]
check(THUNDER.storm and THUNDER.storm.vol == vq, "a storm up")
local writes = #rawget(vq, "writes")
local pc = survivalPC
function SV_LevelGone() return 1 end
check(levelGate() == true and levelTorn(), "the gate closes")
check(THUNDER.storm == nil and THUNDER.test == nil and #THUNDER.parked == 0, "levelDrop: the storm and the test forgotten")
free(vq); free(pawn); free(pc); free(hud)
crashes = 0
tick(0.25)
check(crashes == 0 and not P(vq).destroyed and #rawget(vq, "writes") == writes, "nothing of it touched (" .. crashes .. " touches)")

print(fails == 0 and "thunder test: all passed" or ("thunder test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
