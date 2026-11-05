-- quit_cdo_test.lua <mod dir> <work dir> (run by tools/checks/quit_cdo_test.sh): 0.73.84, Shazzy's crash on quit of
-- 2026-11-04 19:49:19 (0.73.82, round 24 with GUN tier 2: UE4SS.dll+0x2ab5bd, a Lua property lookup of "damage" on a
-- freed object, 0.1 s after the teardown gate closed). runLeft's TAC.reset wrote the gun's stock damage back into its
-- class default (BP_plwp_gun_x1_C's, loaded with the level) after the level's purge had freed it. On the real sv_core,
-- sv_config, sv_ai, sv_hud and sv_tactical (sv_ladon's and sv_anomalies' text), the game stubbed; a freed object here
-- counts every read or write of it as the crash it would be:
--   the gun: UP.apply keeps the class default and its stock (UP.gunStock, by the class's name, for the session); the
--     gate closing (levelGate: SV_LevelGone 1, levelDrop) then TAC.reset with the class default freed touches nothing
--     and logs it forgotten (the 0.73.83 code touches it: the crash); a live one is put back to stock (a restart, a new
--     run); an address another object took since (same address, another name) isn't touched; the class loaded again
--     (a new class default) takes its stock from UP.gunStock, never from a value left upgraded;
--   VALKA's sky: levelDrop forgets RED.b (its "VALKA's sky" drop) and hudRed's at-once path touches nothing while the
--     level's torn down or its sky actor is gone; with both live it puts the sky back as before;
--   the Ladon missile's class default: HIT.reset forgets it, every use is liveObj (no valid(HIT.cdo)); VALKA's flare's
--     removal liveObj too.
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

-- the game's objects: LIVE[addr] true while the engine holds it; a freed one counts each read / write as a crash
VERSION = "0.73.84-quit.test"
local LIVE, crashes = {}, 0
local Om = {}
Om.__index = function(t, k)
    if not LIVE[rawget(t, "addr")] then crashes = crashes + 1; return nil end
    local p = rawget(t, "props")
    if p[k] ~= nil then return p[k] end
    return nil
end
Om.__newindex = function(t, k, v)
    if not LIVE[rawget(t, "addr")] then crashes = crashes + 1; return end
    rawget(t, "props")[k] = v
end
local function obj(addr, full, props)
    LIVE[addr] = true
    return setmetatable({ addr = addr, full = full, props = props or {} }, Om)
end
function SV_ObjChain(a) return LIVE[a] and 1 or 0 end
function FName(s) return s end
function NotifyOnNewObject() end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function SV_UnitAlive() return 0 end
local activators = {}
function FindAllOf(cls) if cls == "LivePlayerWeaponActivator" then return activators end return {} end

local function part(name, chunk)
    assert(load(readAll(MOD .. "/Scripts/" .. name), chunk or ("=" .. name)))()
end
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
-- (UE4SS's own, as the tests stub them: an object's address and full name without reading it)
function addrOf(o) return type(o) == "table" and rawget(o, "addr") or nil end
function nameOf(o) if type(o) ~= "table" then return "?" end if SV_ObjChain(rawget(o, "addr")) == 0 then return "?" end return rawget(o, "full") or "?" end
-- (UE4SS's IsValid reads the object itself: a freed one is a crash here, as hotfix2 found)
function valid(o)
    if type(o) ~= "table" then return false end
    if not LIVE[rawget(o, "addr")] then crashes = crashes + 1; return false end
    return true
end
local function line(pat, from) for i = #logs, from or 1, -1 do if logs[i]:find(pat) then return logs[i] end end return nil end
part("sv_config.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_tactical.lua")
D = { round = 24 }
RUN = { ups = { gun = 2 } }
CFG.upgrades.enabled, CFG.upgrades.gun_experimental = true, true

local GUN = "/Game/Blueprints/Weapons/Gun/Player/BP_plwp_gun_x1.BP_plwp_gun_x1_C"
local function gunClass(cdo) return { addr = 0x5000, full = GUN, GetCDO = function() return cdo end } end
local cdo1 = obj(0x17A9770DC0, "BP_plwp_gun_x1_C /Game/Blueprints/Weapons/Gun/Player/BP_plwp_gun_x1.Default__BP_plwp_gun_x1_C", { damage = 15 })
local pawn = obj(0x9000, "LivePlayerPlane", { MaxHealth = 100, HealthInternal = 1000 })
local act = obj(0x9100, "LivePlayerWeaponActivator", { MaxFlareCount = 6, MachineGunClass = gunClass(cdo1) })
rawget(act, "props").GetOwner = function() return pawn end
activators[1] = act
LIVE[0x5000] = true

---------------------------------------------------------------------------------------------------- the gun
print("the gun's class default (TAC.reset, UP.apply)")
local step = 0
for _, it in pairs(CFG.shop.items) do if it.role == "upgrade" and it.up == "gun" then step = it.step end end
local want2 = 15 * (1 + step * 2)
UP.apply(pawn)
local g = UP.gunBase[GUN]
check(g and rawget(cdo1, "props").damage == want2 and UP.gunStock[GUN] == 15, string.format(
    "GUN tier 2: the class default kept, its damage 15 -> %.2f, its stock 15 kept for the session", want2))
check(g and g.full == rawget(cdo1, "full"), "kept with its full name")

-- the teardown gate closes (SV_LevelGone 1) as the purge frees the gun's class default with the level
local from = #logs + 1
LIVE[0x17A9770DC0] = nil
function SV_LevelGone() return 1 end
check(levelGate() == true and levelTorn(), "the gate closes: the level torn down")
check(has(line("^level gate: closed", from), "VALKA's sky"), "levelDrop: VALKA's sky among the drops: " .. tostring(line("^level gate: closed", from)))
crashes = 0
TAC.reset()                                      -- (runLeft's, right after the leaderboard's lines)
check(crashes == 0, "TAC.reset: the freed class default not read or written (" .. crashes .. " touches)")
check(next(UP.gunBase) == nil, "UP.gunBase emptied")
check(line("^upgrades: 1 gun class default gone with the level: forgotten, not touched", from) ~= nil, "logged: forgotten, not touched")
do                                               -- (0.73.83's line touches it: the crash this fixes)
    UP.gunBase[GUN] = g
    crashes = 0
    for _, x in pairs(UP.gunBase) do pcall(function() x.cdo.damage = x.damage end) end
    check(crashes > 0, "(the 0.73.83 TAC.reset's line reads the freed class default: the crash)")
    UP.gunBase = {}
end
function SV_LevelGone() return 0 end
levelGate()
LEAVE.reset()

-- a live one (a restart, a new run) back to stock
local cdo2 = obj(0x6000, "BP_plwp_gun_x1_C /Game/Blueprints/Weapons/Gun/Player/BP_plwp_gun_x1.Default__BP_plwp_gun_x1_C", { damage = want2 })
rawget(act, "props").MachineGunClass = gunClass(cdo2)
UP.apply(pawn)
check(UP.gunBase[GUN] and UP.gunBase[GUN].damage == 15 and rawget(cdo2, "props").damage == want2,
      "the class loaded again holding an upgraded value: its stock from UP.gunStock (15), not the " .. want2 .. " it holds")
RUN.ups.gun = 1
UP.apply(pawn)
check(math.abs(rawget(cdo2, "props").damage - 15 * (1 + step)) < 1e-9, "tier 1 on it: 15 x (1 + step), not compounded")
crashes = 0
TAC.reset()
check(crashes == 0 and rawget(cdo2, "props").damage == 15, "TAC.reset with it live: back to 15")

-- an address another object took since: not touched
RUN.ups.gun = 2
UP.apply(pawn)
local g2 = UP.gunBase[GUN]
rawset(cdo2, "full", "SomethingElse /Game/Other.Default__Other_C")
rawget(cdo2, "props").damage = 99
TAC.reset()
check(rawget(cdo2, "props").damage == 99 and next(UP.gunBase) == nil, "the slot holds another object (another name): not written")
rawset(cdo2, "full", g2.full)

-- mid-run, its class loaded again (the kept one gone): taken again, the stock kept
UP.gunBase[GUN] = g2
LIVE[0x6000] = nil
local cdo3 = obj(0x7000, "BP_plwp_gun_x1_C /Game/Blueprints/Weapons/Gun/Player/BP_plwp_gun_x1.Default__BP_plwp_gun_x1_C", { damage = 15 })
rawget(act, "props").MachineGunClass = gunClass(cdo3)
crashes = 0
UP.apply(pawn)
check(crashes == 0 and UP.gunBase[GUN].cdo == cdo3 and rawget(cdo3, "props").damage == want2,
      "a kept class default gone mid-run: the new one taken (" .. crashes .. " touches of the old)")

---------------------------------------------------------------------------------------------------- VALKA's sky
print("VALKA's sky (hudRed at once, levelDrop)")
local sets = 0
local sun = obj(0x8100, "DirectionalLightComponent")
rawget(sun, "props").SetLightColor = function() sets = sets + 1 end
local sky = obj(0x8000, "LiveCloudlyActor")
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
local dropped = 0
for name, fn in pairs(LEVEL_DROPS) do if name == "VALKA's sky" then fn("test"); dropped = dropped + 1 end end
check(dropped == 1 and RED.b == nil, "LEVEL_DROPS[\"VALKA's sky\"] forgets RED.b")
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
LEAVE.gone = true                                -- (levelTorn)
crashes, from = 0, #logs + 1
hudRed(false, nil, true)
check(sets == 0 and crashes == 0 and RED.b == nil and line("^hud: the sky's level is gone: nothing put back", from) ~= nil,
      "hudRed at once while the level's torn down: nothing touched, forgotten")
LEAVE.gone = nil
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
LIVE[0x8000], LIVE[0x8100] = nil, nil
crashes = 0
hudRed(false, nil, true)
check(sets == 0 and crashes == 0 and RED.b == nil, "its sky actor gone (not torn yet): nothing touched")
LIVE[0x8000], LIVE[0x8100] = true, true
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
from = #logs + 1
hudRed(false, nil, true)
check(sets == 1 and RED.b == nil and line("^hud: the sky put back as it was %(at once%)", from) ~= nil, "both live: the sky put back as before")
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
LIVE[0x8100] = nil                               -- (a component freed before its actor)
crashes, sets = 0, 0
hudRed(false, nil, true)
check(crashes == 0 and sets == 0, "a kept sky component gone, its actor not: that one not touched (liveObj, not valid)")

---------------------------------------------------------------------------------------------------- the Ladon, the flare
print("the Ladon missile's class default, VALKA's flare")
local ladon = readAll(MOD .. "/Scripts/sv_ladon.lua")
check(not has(ladon, "valid(HIT.cdo)") and has(ladon, "liveObj(HIT.cdo)"), "sv_ladon: no valid(HIT.cdo), liveObj on every use")
local reset = ladon:match("function HIT%.reset%(%)(.-)\nend")
check(reset and has(reset, "HIT.cdo = nil"), "HIT.reset (the level's drop, runLeft) forgets it")
local an = readAll(MOD .. "/Scripts/sv_anomalies.lua")
local fs = an:match("function SPC%.V%.flareStop%(s%)(.-)\nend")
check(fs and has(fs, "liveObj(a)") and not has(fs, "valid(a)"), "SPC.V.flareStop: liveObj before its K2_DestroyActor")

print(fails == 0 and "quit_cdo_test: all passed" or ("quit_cdo_test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
