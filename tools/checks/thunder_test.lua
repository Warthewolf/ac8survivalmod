-- thunder_test.lua <mod dir> <work dir> (run by tools/checks/thunder_test.sh): what's left of the lightning Anomaly
-- (Scripts/sv_anomalies_dev.lua THUNDER, test builds only) after the user's call of 2026-11-18 ("The Distant Thunder Round
-- needs to be cut as we're not going to be using it anymore, so you can remove the test keys for it", "It was replaced by
-- Invincible Fleet instead"), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies and
-- sv_rounds, the game stubbed (a freed object counts each read or write of it as the crash it would be):
--   its round cut: no kind "thunder" (nor its throttle), none of its 8 test keys bound, ticks over many rounds never name a
--     round Distant Thunder's;
--   its storm pieces INVINCIBLE FLEET's night storm calls (sv_fleet_storm.lua, sv_fleet_surface.lua) still there;
--   its tick runs in a run and with the level going, its level drop forgets their state; no freed object touched.
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
Key = { OEM_COMMA = "OEM_COMMA", OEM_PERIOD = "OEM_PERIOD", F11 = "F11", OEM_SIX = "OEM_SIX", OEM_SEVEN = "OEM_SEVEN", OEM_TWO = "OEM_TWO", OEM_ONE = "OEM_ONE", OEM_FIVE = "OEM_FIVE" }
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
-- ((2026-11-24) sv_anomalies_dev.lua, where THUNDER lives, is no longer listed right after sv_anomalies_valka in main.lua
-- (VALKA's SOLG parts went in between, 2026-11-22), so it isn't part of its family: loaded by its own name)
part("sv_anomalies.lua"); part("sv_anomalies_dev.lua"); part("sv_rounds.lua")

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


print("Distant Thunder's round cut (the user, 2026-11-18)")
check(SPC.kinds.thunder == nil, "no special kind \"thunder\"")
check(not (TIER and TIER.PRESSURE_OWN and TIER.PRESSURE_OWN.thunder), "no throttle of its own")
local bound = {}
for k in pairs(binds) do bound[#bound + 1] = k end
check(#bound == 0 or (function() for _, k in ipairs({ "OEM_COMMA", "OEM_PERIOD", "OEM_SIX", "OEM_SEVEN", "OEM_TWO", "OEM_ONE", "OEM_FIVE" }) do
    if binds[k] then return false end end return true end)(), "none of its test keys bound (" .. table.concat(bound, ", ") .. ")")
check(THUNDER.ready == nil and THUNDER.spawn == nil and THUNDER.tick == nil and THUNDER.testEnd == nil, "its round's and storm test's functions gone")

print("the storm pieces INVINCIBLE FLEET's night storm calls")
for _, f in ipairs({ "layoutSet", "camFade", "post", "cloudReady", "cloudOff", "cloudFlash", "cloudTick", "bolt", "boltWarm", "boltHide" }) do
    check(type(THUNDER[f]) == "function", "THUNDER." .. f)
end
local TT
for _, t in ipairs(TEST_TICKS) do if t.name == "thunder" then TT = t end end
check(TT ~= nil, "its tick")

print("its tick over a run")
D = { round = 1, now = clock, state = "wait" }
local forced = false
for r = 1, 40 do
    D.round = r
    for _ = 1, 20 do clock = clock + 0.25; D.now = clock; TT.fn(clock); if D.forceSpecial == "thunder" then forced = true end end
end
check(not forced, "40 rounds: no round named Distant Thunder's")
local errs = 0
for _, l in ipairs(logs) do if has(l, "error") then errs = errs + 1 end end
check(errs == 0, "no error from its tick (" .. errs .. ")")

print("the level going and dropped")
levelTorn = function() return true end
clock = clock + 0.25
TT.fn(clock)
levelTorn = nil
if LEVEL_DROPS and LEVEL_DROPS.thunder then LEVEL_DROPS.thunder() end
check(true, "the tick with the level going, the level drop")
check(crashes == 0, "no freed object touched (" .. crashes .. ")")

print(fails == 0 and "thunder test: all passed" or ("thunder test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
