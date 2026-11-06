-- fishing_test.lua <mod dir> <work dir> <stripped dir> (run by tools/checks/fishing_test.sh): GONE FISHIN''s Lua for the
-- first in-game test (Scripts/sv_fishing.lua; tools/re/FISHING.md 1-4, 7) on the real sv_core, sv_config and sv_fishing,
-- the game stubbed:
--   the main menu: the shoal's DT_NPC row and its model row added from Survival's tables (the model first), its names set;
--   the test key (Ctrl+F10, through sv_core.lua's testKey and KEYQ): nothing outside a run or on a joiner; the first press
--     spawns SV_Unit_FishA at ground A (z shoal_z, a yaw 0-360) and SAL's boat at its spot, each object recorded as the
--     spawner makes it (only while the spawn's list is open), a hit sphere on each shoal (8 m, EnemyPawn), the names set;
--     the second flips the sphere for the next spawn; the third takes everything off (the joiners' copies first in co-op,
--     SPC.cleanUp, SV_Recycle 2 s on); the next spawns without the sphere; test_s takes it off by itself;
--   once a second a line with each shoal's health / MaxHealth and who its DamageHistoryMap names, and the boat's health and
--     MinHealth: the field written back to boat_min_health when it's lower, SetMinHealth never called;
--   a shoal down (its health 0, or its actor gone): who killed it (KILL.read only on a live one, KILL.by) and the splash at
--     the sea's height where it was;
--   a spawn the new-object feed missed: the shoals found by their class near the ground;
--   the level torn down: everything forgotten untouched;
--   a release's copy (strip_test_only.py): no test key or test state left, the rows still added at the main menu.
local MOD, WORK, STRIPPED = arg[1], arg[2], arg[3]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore
VERSION = "0.74.0-fishing.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end

local nextA = 0x10000
local function obj(name, t)
    t = t or {}
    nextA = nextA + 0x100
    t.addr, t.full = nextA, name
    t.IsValid = function(self) return not self.gone end
    t.GetAddress = function(self) return self.addr end
    t.GetFullName = function(self) return self.full end
    return t
end
local notifies, statics, all, binds = {}, {}, {}, {}
function NotifyOnNewObject(cls, fn) notifies[cls] = notifies[cls] or {}; table.insert(notifies[cls], fn) end
function StaticFindObject(p) return statics[p] end
function FindAllOf(cls) return all[cls] end
function FindFirstOf(cls) local l = all[cls]; return l and l[1] end
Key = { F6 = "F6", F10 = "F10", F11 = "F11", F12 = "F12" }
ModifierKey = { CONTROL = "CTRL" }
function RegisterKeyBind(key, mods, fn) binds[key] = fn end
function ExecuteInGameThread(f) f() end

local function part(dir, name, chunk) assert(load(readAll(dir .. "/Scripts/" .. name), chunk or ("=" .. name)))() end
part(MOD, "sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
svLevelOn = true
part(MOD, "sv_config.lua")
local callouts = {}
function hudCallout(a, b) callouts[#callouts + 1] = tostring(a) .. " / " .. tostring(b) end
function nativeReady() return true end
local GI = obj("GameInstance")
function gameInstance() return GI end
function pin() return true end
SV_ERR = { [0] = "the game spawned nothing", [-3] = "its last flight is still up" }

-- the tables: DT_NPC / DT_NPC_Model without our rows, Survival's with them
local adds = {}
local function dt(name, rows)
    local t = obj(name, { rows = rows })
    function t:FindRow(r) return self.rows[tostring(r)] end
    function t:AddRow(r, v) self.rows[tostring(r)] = v; adds[#adds + 1] = name .. ":" .. tostring(r) end
    return t
end
local C = CFG.specials.fishing
local npc, mine = dt("DT_NPC", {}), dt("DT_SV_NpcRows", { [C.shoal_row] = { row = "shoal" } })
local mt, mr = dt("DT_NPC_Model", {}), dt("DT_SV_ModelRows", { [C.shoal_model] = { model = "shoal" } })
statics[PROBE_TABLES[2].path], statics[CFG.specials.shuttle.npc_rows] = npc, mine
statics[ACE.model_table], statics[ACE.model_rows] = mt, mr
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end

part(MOD, "sv_fishing.lua")

print("the main menu")
FISH.setup()
check(npc.rows[C.shoal_row] ~= nil and mt.rows[C.shoal_model] ~= nil, "SV_Shoal in DT_NPC, SV_Model_Shoal in DT_NPC_Model")
check(adds[1] == "DT_NPC_Model:" .. C.shoal_model and adds[2] == "DT_NPC:" .. C.shoal_row, "the model row first (" .. table.concat(adds, ", ") .. ")")
check(FISH.ready == true, "FISH.ready")
check(texts.SV_Shoal_Name == "SHOAL" and texts.SV_SalBoat == "SAL'S BOAT", "the names set: SHOAL, SAL'S BOAT")
check(logs[#logs]:find("fishing: the shoal's rows: SV_Shoal in DT_NPC, SV_Model_Shoal in DT_NPC_Model", 1, true) ~= nil, "logged: " .. logs[#logs])

-- the game: objects the spawner makes, the player, the splash, KILL, the clean-up
local setMin, reads, splashes, spawns, cleaned, recycled, removed = 0, {}, {}, {}, {}, {}, {}
local pawn = obj("/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_PlayerPlane_C_0")
survivalPC = obj("/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PlayerController_0", { Pawn = pawn })
local function hitMap(o)
    return { ForEach = function(_, fn)
        for _, e in ipairs(o.hits) do fn({ get = function() return e[1] end }, { get = function() return e[2] end }) end
    end }
end
local function sphere()
    local c = obj("/Engine/Transient.SphereComponent_0")
    function c:SetSphereRadius(r) self.r = r end
    function c:SetCollisionProfileName(n) self.profile = tostring(n) end
    function c:GetUnscaledSphereRadius() return self.r end
    function c:GetCollisionProfileName() return FName(self.profile) end
    function c:GetCollisionEnabled() return 3 end
    return c
end
local function thing(cls, i, x, y, z, hp, mx, mn)
    local o = obj("/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel." .. cls .. "_" .. i,
        { HealthInternal = hp, MaxHealth = mx, MinHealth = mn, hits = {}, loc = { X = x + i * 20000, Y = y, Z = z } })
    o.DamageHistoryMap = hitMap(o)
    function o:K2_GetActorLocation() return self.loc end
    function o:AddComponentByClass(cls2) self.added = cls2; self.sphere = sphere(); return self.sphere end
    function o:SetMinHealth() setMin = setMin + 1 end
    return o
end
local notifyOn = true
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw, su = spawningUnit }
    local boat = unit == C.boat_unit
    local made = {}
    for i = 1, boat and 1 or 8 do
        local o = boat and thing("VE028_boat2_CP_C", i, x, y, z, 200, 20, 1.0) or thing("BP_GR000_dummy_CP_C", i, x, y, z, 100, 10, 0)
        if boat then o.bIsInvincible, o.bIsInvincibleFromAI = false, true end
        made[#made + 1] = o
        if notifyOn then for _, fn in ipairs(notifies["/Script/Live.LiveAIGameObject"] or {}) do fn(o) end end
    end
    all[boat and "VE028_boat2_CP_C" or "BP_GR000_dummy_CP_C"] = made
    return #made
end
function SV_UnitAlive() return 0 end
function SV_Recycle(u, f) recycled[#recycled + 1] = u .. "/" .. tostring(f); return 1 end
statics["/Script/Engine.SphereComponent"] = obj("/Script/Engine.SphereComponent")
statics["/Script/Niagara.Default__NiagaraFunctionLibrary"] = obj("/Script/Niagara.Default__NiagaraFunctionLibrary", {
    SpawnSystemAtLocation = function(_, wc, sys, at, rot, sc) splashes[#splashes + 1] = { sys = sys, at = at, sc = sc }; return obj("NS") end })
local splashName = C.splash:match("[^/]+$")
statics[C.splash .. "." .. splashName] = obj(C.splash .. "." .. splashName)
KILL = {
    side = function(o, pa) return addrOf(o) == pa and "you" or "other" end,
    read = function(p)
        reads[#reads + 1] = p
        if p.obj.gone then reads.gone = (reads.gone or 0) + 1 end
        local d = {}
        for _, e in ipairs(p.obj.hits) do local s = KILL.side(e[1], addrOf(pawn)); d[s] = (d[s] or 0) + e[2] end
        p.dmg = d
    end,
    by = function(p) return (p.dmg and (p.dmg.you or 0) > 0) and "you" or "allies" end,
}
SPC.CLEAN_OBJ = {}
SPC.cleanUp = function(list, why, mortal)
    local n = 0
    for _, u in ipairs(list) do for _, o in ipairs(SPC.CLEAN_OBJ[u] or {}) do o.gone = true; n = n + 1 end end
    cleaned[#cleaned + 1] = { list = list, why = why, mortal = mortal, n = n }
    return n
end
COOP = { host = function() return false end, client = function() return false end,
         removeNow = function(u) removed[#removed + 1] = u; return 0 end }

local function press(k) assert(binds[k], "no bind for " .. k)(); KEYQ.drain() end
local function tick(s) clock = clock + s; for _, t in ipairs(TEST_TICKS) do t.fn(clock) end end
local function found(pat) for i = #logs, 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end return nil end

print("the key")
check(binds.F10 ~= nil and TEST_KEYS.F10 ~= nil, "Ctrl+F10 bound through testKey")
D = nil
press("F10")
check(#spawns == 0 and found("fishing test: Ctrl+F10 outside a Survival run"), "outside a run: nothing")
D = { now = 10, round = 3, state = "fighting", up = {} }
COOP.client = function() return true end
press("F10")
check(#spawns == 0 and found("the host spawns the shoals"), "a joiner: nothing")
COOP.client = function() return false end

print("the first press: spawned")
press("F10")
check(#spawns == 2, "two spawns (" .. #spawns .. ")")
local s1, s2 = spawns[1], spawns[2]
check(s1.unit == "SV_Unit_FishA" and s1.x == 1803753 and s1.y == -1160858 and s1.z == 700, "SV_Unit_FishA at ground A, 700 cm up")
check(type(s1.yaw) == "number" and s1.yaw >= 0 and s1.yaw < 360, "a random yaw (" .. tostring(s1.yaw) .. ")")
check(s1.su == "SV_Unit_FishA" and s2.su == C.boat_unit and spawningUnit == nil, "spawningUnit set around each spawn, cleared after")
check(s2.unit == "SV_Unit_SalBoat" and s2.x == 1687842 and s2.y == -1191916 and s2.z == 300, "SAL's boat at its spot, 300 cm up")
local T = FISH.test
check(#T.shoals == 8 and T.boat ~= nil, "8 shoals and the boat recorded")
local shoals = all.BP_GR000_dummy_CP_C
local spheres = 0
for _, o in ipairs(shoals) do
    if o.sphere and o.added == statics["/Script/Engine.SphereComponent"] and o.sphere.r == 800 and o.sphere.profile == "EnemyPawn" then spheres = spheres + 1 end
end
check(spheres == 8, "a sphere on each shoal: 8 m, EnemyPawn (" .. spheres .. ")")
check(found("fishing test: shoal 1 BP_GR000_dummy_CP_C_1") and found("radius, profile; reads radius 8.0 m, profile EnemyPawn"), "each shoal's spawn logged")
check(found("right after its spawn: health 200, MaxHealth 20, MinHealth 1.0") ~= nil, "the boat's health and MinHealth right after its spawn")
check(callouts[#callouts]:find("8 SHOALS WITH SPHERES, BOAT UP", 1, true) ~= nil, "callout: " .. callouts[#callouts])
-- an object made under one of our units outside our spawn (a co-op copy's): not recorded
spawningUnit = "SV_Unit_FishA"
for _, fn in ipairs(notifies["/Script/Live.LiveAIGameObject"]) do fn(obj("stray")) end
spawningUnit = nil
check(#FISH.actors.SV_Unit_FishA == 8, "nothing recorded once the spawn's list is shut")

print("once a second")
tick(1)
local line = found("fishing test: +1 s: shoals ")
check(line and line:find("1 100/10 -; 2 100/10 -", 1, true) and line:find("boat 200/20 min 1.0 -", 1, true), "each shoal's health / MaxHealth and the boat: " .. tostring(line))
local boat = all.VE028_boat2_CP_C[1]
boat.MinHealth = 0
tick(1)
check(boat.MinHealth == 1.0 and setMin == 0, "the boat's MinHealth field written back to 1.0, SetMinHealth never called")
check(found("the boat's MinHealth read 0: the field written back to 1.0 (1 times)") ~= nil, "logged once")
boat.hits = { { pawn, 30 } }
boat.HealthInternal = 170
tick(1)
line = found("fishing test: +3 s:")
check(line and line:find("boat 170/20 min 1.0 you/BP_PlayerPlane_C_0 30", 1, true), "the boat's hits named: " .. tostring(line))

print("a shoal down")
shoals[3].hits = { { pawn, 100 } }
shoals[3].HealthInternal = 0
tick(1)
line = found("fishing test: shoal 3 BP_GR000_dummy_CP_C_3 down")
check(line and line:find("by you", 1, true) and line:find("its map named you/BP_PlayerPlane_C_0 100", 1, true) and line:find("the splash played", 1, true),
    "shoal 3 by you, the splash: " .. tostring(line))
check(#splashes == 1 and splashes[1].at.Z == C.sea_z and splashes[1].at.X == shoals[3].loc.X and splashes[1].sc.X == C.splash_scale,
    "the splash at the shoal, at the sea's height")
local readsBefore = reads.gone or 0
shoals[5].gone = true
tick(1)
line = found("fishing test: shoal 5 BP_GR000_dummy_CP_C_5 down")
check(line and line:find("by allies", 1, true), "shoal 5 gone with no hits: KILL.by's answer: " .. tostring(line))
check((reads.gone or 0) == readsBefore, "KILL.read never on a gone shoal")
check(#splashes == 2, "its splash too, where it was last seen")
line = found("fishing test: +5 s:")
check(line and line:find("5 DOWN", 1, true) and not line:find("3 DOWN", 1, true), "a shoal down once: " .. tostring(line))

print("the second and third presses")
press("F10")
check(found("fishing test: next spawn WITHOUT the sphere") ~= nil and T.state == "up", "the second press: the next spawn without the sphere")
press("F10")
check(#cleaned == 1 and cleaned[1].mortal == true and cleaned[1].list[1] == "SV_Unit_FishA" and cleaned[1].list[2] == "SV_Unit_SalBoat",
    "the third: SPC.cleanUp on both units")
check(cleaned[1].n == 7, "the shoals still up and the boat finished off (" .. cleaned[1].n .. ")")
check(#removed == 0, "solo: no co-op removal")
tick(1)
check(#recycled == 0, "not yet recycled 1 s on")
tick(1.5)
check(recycled[1] == "SV_Unit_FishA/1" and recycled[2] == "SV_Unit_SalBoat/1" and T.state == "idle", "SV_Recycle(unit, 1) 2 s on, idle")

print("the next spawn: without the sphere; test_s")
spawns = {}
press("F10")
local without = 0
for _, o in ipairs(all.BP_GR000_dummy_CP_C) do if not o.sphere then without = without + 1 end end
check(#spawns == 2 and without == 8 and found("no sphere (this spawn's without)") ~= nil, "8 shoals without spheres")
COOP.host = function() return true end
tick(C.test_s + 1)
check(#cleaned == 2 and cleaned[2].why:find("300 s after the spawn", 1, true), "taken off test_s after the spawn by itself")
check(removed[1] == "SV_Unit_FishA" and removed[2] == "SV_Unit_SalBoat", "co-op host: the joiners' copies taken down first (COOP.removeNow)")
tick(3)
check(T.state == "idle", "idle again")
COOP.host = function() return false end

print("the feed missed the spawn; the level torn down")
notifyOn = false
spawns = {}
press("F10")
check(#T.shoals == 8 and found("none seen as they were made; 8 BP_GR000_dummy_CP_C found near it") ~= nil, "the shoals found by class near the ground")
check(T.boat ~= nil and found("VE028_boat2_CP_C near its spot: found") ~= nil, "the boat by class")
notifyOn = true
LEVEL_DROPS["fishing"]("test"); LEVEL_DROPS["the fishing test"]("test")
check(next(FISH.actors) == nil and T.state == "idle", "the level torn down: forgotten")
local n0 = #logs
tick(1)
check(#logs == n0, "nothing read after it")

print("a release's copy")
FISH, testKey, TEST_TICKS, TEST_KEYS = nil, nil, nil, nil
local src = readAll(STRIPPED .. "/Scripts/sv_fishing.lua")
check(not src:find("TEST ONLY", 1, true) and not src:find("testKey", 1, true) and not src:find("TEST_TICKS", 1, true), "no test code left in it")
npc.rows, mt.rows, adds = {}, {}, {}
part(STRIPPED, "sv_fishing.lua")
FISH.setup()
check(FISH.test == nil and FISH.ready == true and npc.rows[C.shoal_row] ~= nil, "it loads and still adds the rows at the main menu")

print(fails == 0 and "fishing test: all passed" or ("fishing test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
