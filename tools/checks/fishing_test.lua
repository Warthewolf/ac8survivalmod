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
Key = { F6 = "F6", F10 = "F10", F11 = "F11", F12 = "F12", HOME = "HOME", PAGE_UP = "PAGE_UP", PAGE_DOWN = "PAGE_DOWN" }
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
check(FISH.rowsReady == true, "FISH.rowsReady")
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

print("the round: the deck, the kg, the grades and the pay")
part(MOD, "sv_subs.lua")
part(MOD, "sv_sky.lua")
levelGoing = function() return false end
local onAirfield = false
function playerOnAirfield() return onAirfield end
local lbs, later = {}, {}
LB = { special = function(k, won) lbs[#lbs + 1] = { k = k, won = won } end }
ALIVE = { spawned = function() end }
SPC.recycleLater = function(list) for _, u in ipairs(list) do later[#later + 1] = u end; return #list end
local geomWpn = "msl"
KILL.geom = function() return { wpn = geomWpn, used = {} } end
local paid = {}
RUN = { credits = 0 }
function addCredits(n2, why) paid[#paid + 1] = { n = n2, why = why }; RUN.credits = RUN.credits + n2 end
local deck = FISH.deck(24)
local cnt = {}
for _, x in ipairs(deck) do cnt[x] = (cnt[x] or 0) + 1 end
check(#deck == 24 and cnt.none == 7 and cnt.junk == 2 and cnt.sardine == 5 and cnt.mackerel == 4 and cnt.tuna == 3
    and cnt.swordfish == 2 and cnt.bigone == 1, "24 shoals: 7 empty, 2 junk, 5 sardines, 4 mackerel, 3 tuna, 2 swordfish, The Big One")
local d2 = FISH.deck(30, { bigone = 50, none = 50 }, 1)
local big = 0
for _, x in ipairs(d2) do if x == "bigone" then big = big + 1 end end
check(#d2 == 30 and big == 1, "The Big One at most once, whatever its weight (" .. big .. ")")
local shuffledOnce = false
for _ = 1, 5 do local a, b = FISH.deck(24), FISH.deck(24); if table.concat(a, ",") ~= table.concat(b, ",") then shuffledOnce = true end end
check(shuffledOnce, "the deck shuffled")
local kgOk = true
for _ = 1, 200 do
    local t = FISH.kgOf("tuna")
    local b1 = FISH.kgOf("bigone")
    if t < 40 or t > 90 or b1 < 250 or b1 > 400 or FISH.kgOf("none") ~= 0 or FISH.kgOf("junk") ~= 0 then kgOk = false end
end
check(kgOk, "each fish's kg in its range, nothing and junk 0")
check(FISH.grade(900, 1) == "S" and FISH.grade(899, 1) == "A" and FISH.grade(650, 1) == "A" and FISH.grade(649, 1) == "B"
    and FISH.grade(400, 1) == "B" and FISH.grade(150, 1) == "C" and FISH.grade(149, 1) == "D", "the grades' thresholds")
check(FISH.grade(225, 4) == "S" and FISH.grade(224, 4) == "A" and FISH.grade(450, 2) == "S", "co-op: each threshold x players ^ -1")
local pA = FISH.payFor(770, 1, 7, true)
local pS = FISH.payFor(1000, 1, 7, true)
local pA2 = FISH.payFor(700, 1, 7, false)
check(pA == 6120 and pS == 9000 and pA2 == 5200, string.format("round 7: an A (770 kg, The Big One) %d, an S (1,000 kg) %d, an A without it %d", pA, pS, pA2))
local p17 = FISH.payFor(1000, 1, 17, true)
check(p17 == 12600, "round 17: x1.4 (" .. p17 .. ")")
check(FISH.payFor(0, 1, 7, false) == 0, "nothing caught: nothing paid")

print("the round: once a run, its start")
RUN = { credits = 0 }
check(FISH.ready(7) == true and FISH.ready(7, true) == true, "ready from the start of a run")
RUN.fished = 7
check(FISH.ready(20) == false and FISH.ready(20, true) == true, "once a run (a test key's forced one still comes)")
RUN = { credits = 0 }
spawns, all = {}, {}
FISH.actors = {}
D = { now = 2000, round = 7, state = "spawning", up = {}, special = { kind = "fishing", state = "pending" } }
clock = 2000
local s = D.special
check(FISH.roundSpawn(2000) == true, "GONE FISHIN' spawns")
check(s.state == "intro" and RUN.fished == 7 and RUN.arcF == 7, "intro; once a run marked; the arc's F is round 7")
check(#spawns == 1 and spawns[1].unit == "SV_Unit_SalBoat" and spawns[1].yaw == 157, "SAL's boat at its spot (yaw 157)")
check(#SUB.q == #CFG.specials.fishing.text.intro and SUB.q[1].who == "COMONA CONTROL" and SUB.q[2].who == "SAL",
    "the intro on the strip (" .. #SUB.q .. " lines, CONTROL then SAL)")
check(s.introEnd >= 2000 + 7 * 4 - 0.01, "the shoals after the intro (" .. (s.introEnd - 2000) .. " s)")
local longest = 0
for _, k in ipairs({ "intro", "start", "none", "junk", "sardine", "mackerel", "tuna", "swordfish", "bigone", "first", "empties",
                     "gun", "ally", "quiet", "landed", "cleared", "boat", "warn", "weigh", "grade_s", "grade_a", "grade_b",
                     "grade_c", "grade_d", "signoff" }) do
    local l = CFG.specials.fishing.text[k]
    for _, x in ipairs(type(l) == "table" and l or { l }) do
        local _, t = FISH.line(x, { kg = "999", fish = "X" })
        longest = math.max(longest, #t)
    end
end
check(longest <= 70, "SAL's lines under 70 characters (the longest " .. longest .. ")")

-- a tick of the round on the round clock, the strip's queue moving as the HUD would
local function rtick(dt)
    clock = clock + dt
    D.now = clock
    FISH.roundTick(clock, s)
    SUB.hudTick(clock, true, false)
end
rtick(s.introEnd - clock + 0.1)
check(s.state == "fishing" and #spawns == 4, "the time starts: the three grounds spawned")
check(spawns[2].unit == "SV_Unit_FishA" and spawns[3].unit == "SV_Unit_FishB" and spawns[4].unit == "SV_Unit_FishC"
    and spawns[3].x == 1866154 and spawns[4].z == 700, "each ground at its spot, 700 cm up")
check(s.total == 24 and #s.deck == 24, "24 shoals, a 24-catch deck")
local sphered = 0
for _, sh in ipairs(s.shoals) do if sh.obj.sphere then sphered = sphered + 1 end end
check(sphered == 24, "a hit sphere on each shoal (" .. sphered .. ")")
check(found("GONE FISHIN' / 3:00 ON THE CLOCK") or callouts[#callouts]:find("3:00 ON THE CLOCK", 1, true), "the clock's callout: " .. tostring(callouts[#callouts]))

-- a fixed deck from here
s.deck = { "tuna", "none", "junk", "none", "sardine", "bigone" }
for i = 7, 24 do s.deck[i] = "mackerel" end
local sh1 = s.shoals[1]
sh1.obj.hits = { { pawn, 100 } }
sh1.obj.HealthInternal = 0
local nSplash = #splashes
rtick(0.5)
check(sh1.down and s.haul[0] and s.haul[0].hits == 1 and s.haul[0].best == "tuna" and s.haul[0].kg >= 40, "your tuna: credited to you")
check(callouts[#callouts]:match("^%+%d+ KG YELLOWFIN TUNA / nil$") ~= nil, "its callout: " .. callouts[#callouts])
check(#splashes == nSplash + 1 and splashes[#splashes].at.Z == 350, "its splash at the sea's height")
local firstLine = false
for _, l in ipairs(SUB.q) do if l.text:find("grandfather", 1, true) then firstLine = true end end
check(firstLine or (SUB.cur and SUB.cur.text:find("grandfather", 1, true)), "SAL's first-catch line")
-- three empties (none, junk, none): his complaint
for i = 2, 4 do s.shoals[i].obj.hits = { { pawn, 100 } }; s.shoals[i].obj.HealthInternal = 0 end
SUB.clear("test")
rtick(0.5)
local said = {}
for _, l in ipairs(SUB.q) do said[#said + 1] = l.text end
check(table.concat(said, " | "):find("aim where the fish are", 1, true) ~= nil, "three empties in a row: SAL's complaint (" .. table.concat(said, " | ") .. ")")
check(s.haul[0].empty == 2 and s.haul[0].junk == 1 and s.haul[0].hits == 4, "the empties and the junk counted")
check(callouts[#callouts - 2]:find("^NOTHING") and callouts[#callouts - 1]:find("^JUNK"), "NOTHING / JUNK callouts")
-- a gun kill (yours, once)
geomWpn = "gun"
s.shoals[5].obj.hits = { { pawn, 100 } }; s.shoals[5].obj.HealthInternal = 0
SUB.clear("test")
rtick(0.5)
local function strip() local o = {}; if SUB.cur then o[1] = SUB.cur.text end; for _, l in ipairs(SUB.q) do o[#o + 1] = l.text end; return o end
check(strip()[1] and strip()[1]:find("little gun", 1, true), "a gun kill: SAL's spear fisherman line")
geomWpn = "msl"
-- an ally's kill (solo: still yours) with The Big One
s.shoals[6].obj.hits = { { obj("BP_Ally"), 100 } }; s.shoals[6].obj.HealthInternal = 0
SUB.clear("test")
rtick(0.5)
check(s.haul[0].bigone == true and s.haul[0].hits == 6, "solo: an ally's catch is yours (The Big One)")
check(strip()[1] == "..." and strip()[2] ~= nil, "The Big One: '...' and its line (" .. table.concat(strip(), " | ") .. ")")
check(splashes[#splashes].sc.X == CFG.specials.fishing.splash_scale * CFG.specials.fishing.splash_big_x, "The Big One's bigger splash")
-- quiet: no catch for quiet_s
SUB.clear("test")
for _ = 1, 62 do rtick(0.5) end
local quiet = false
for _, l in ipairs(SUB.q) do if l.text:find("sightseeing", 1, true) or l.text:find("explode themselves", 1, true) then quiet = true end end
if SUB.cur and (SUB.cur.text:find("sightseeing", 1, true) or SUB.cur.text:find("explode", 1, true)) then quiet = true end
check(quiet, "30 s with no catch: SAL's nudge")
-- you land: his coffee line, once
onAirfield = true
SUB.clear("test")
rtick(0.5); rtick(0.5)
local coffee = 0
for _, l in ipairs(SUB.q) do if l.text:find("coffee", 1, true) then coffee = coffee + 1 end end
if SUB.cur and SUB.cur.text:find("coffee", 1, true) then coffee = coffee + 1 end
check(coffee == 1, "you landed: the coffee line once (" .. coffee .. ")")
onAirfield = false
-- ((code review of 2026-11-07, finding 17) another ally's catch, solo: still yours, and SAL's "your friend" line (it went
-- by the slot, -1 only in co-op, so solo it never played)
check(not s.said.ally, "(The Big One's own lines came first: SAL's ally line not yet said)")
s.shoals[7].obj.hits = { { obj("BP_Ally3"), 100 } }; s.shoals[7].obj.HealthInternal = 0
SUB.clear("test")
rtick(0.5)
local friend = false
for _, t in ipairs(strip()) do if t:find("Your friend is good too", 1, true) then friend = true end end
check(friend and s.said.ally and s.haul[0].hits == 7, "solo: an ally's catch still yours, SAL's 'your friend' line said ("
    .. table.concat(strip(), " | ") .. ")")
-- the boat: a hit here costs you 25 kg (not twice in boat_hit_gap_s)
local boatObj = all.VE028_boat2_CP_C[1]
rtick(0.5)
boatObj.HealthInternal = 150
rtick(0.5)
boatObj.HealthInternal = 140
rtick(0.5)
check(FISH.boat.kg == 25 and FISH.boat.hits == 1, "the boat hit: -25 kg once in its gap (" .. FISH.boat.kg .. ")")
boatObj.MinHealth = 0
rtick(0.5)
check(boatObj.MinHealth == 1.0 and setMin == 0, "the boat's MinHealth field kept at 1, never SetMinHealth")
-- the warnings
local warned = 0
while clock < s.endAt - 0.6 do rtick(0.5) end
for _, l in ipairs(logs) do if l:find("^fishing: %d+ s left") then warned = warned + 1 end end
check(warned == 4, "the four warnings (" .. warned .. ")")
local cleanBefore = #cleaned
rtick(1)
check(s.state == "weigh", "the time's up: the weigh-in")
check(#cleaned == cleanBefore + 1 and #cleaned[#cleaned].list == 3 and cleaned[#cleaned].n == 17, "the 17 shoals left taken off ("
    .. tostring(cleaned[#cleaned] and cleaned[#cleaned].n) .. ")")
check(#later >= 3 and later[1] == "SV_Unit_FishA", "their units off the spawner's list after")
local kgBefore = s.haul[0].kg
while not s.carded do rtick(0.5) end
local last = paid[#paid]
local want = FISH.payFor(kgBefore - 25, 1, 7, true)
check(last and last.n == want and last.why:find("GONE FISHIN' weigh-in", 1, true) and last.why:find("-25 kg the boat", 1, true),
    string.format("paid %s (%s), want %d", tostring(last and last.n), tostring(last and last.why), want))
check(SUB.cardUp and SUB.cardUp.title:find("WEIGH%-IN") and SUB.cardUp.lines[1]:find("7 / 24", 1, true)
    and SUB.cardUp.lines[2]:find("THE BIG ONE", 1, true) and SUB.cardUp.lines[4]:find("-25 KG", 1, true),
    "the card: " .. (SUB.cardUp and table.concat(SUB.cardUp.lines, " | ") or "none"))
check(RUN.fishKg == kgBefore - 25, "the haul kept for THE FESTIVAL's thanks (" .. tostring(RUN.fishKg) .. ")")
for _ = 1, 80 do if s.state ~= "done" then rtick(0.5) end end
check(s.state == "done" and FISH.busy(s) == false, "done once SAL's said it all")
check(lbs[#lbs] and lbs[#lbs].k == "fishing" and lbs[#lbs].won == true, "the leaderboard's special: fishing, won")
check(found("fishing: SAL's boat switched off here (GONE FISHIN' over)") ~= nil and boatObj.bIsInvincible == true
    and boatObj.bShowHUDBox == false, "the boat switched off (no box, invincible)")

print("the round: co-op (the host)")
RUN = { credits = 0 }
paid = {}
spawns, all, FISH.actors = {}, {}, {}
local sent = { fh = {}, fw = {}, fwe = {}, row = {} }
local own = {}
COOP = { open = true, slot = 0, host = function() return true end, client = function() return false end,
         removeNow = function(u) removed[#removed + 1] = u; return 0 end,
         slots = function() return { 0, 2 } end, name = function(sl) return ({ [0] = "Host", [2] = "dukka" })[sl] end,
         fishCatch = function(sl, c, k) sent.fh[#sent.fh + 1] = { sl, c, k } end,
         fishWeigh = function(sl, k) sent.fw[#sent.fw + 1] = { sl, k } end,
         fishWeighEnd = function(p, t) sent.fwe[#sent.fwe + 1] = { p, t } end,
         specialRow = function(...) sent.row[#sent.row + 1] = { ... } end,
         payOwn = function(n2, why) own[#own + 1] = { n = n2, why = why } end }
local byJoiner = nil
local rawBy = KILL.by
KILL.by = function(p)
    if byJoiner and p.obj == byJoiner then p.killer = 2; return "wingmate" end
    return rawBy(p)
end
D = { now = 5000, round = 9, state = "spawning", up = {}, special = { kind = "fishing", state = "pending" } }
clock, s = 5000, nil
s = D.special
FISH.roundSpawn(5000)
rtick(s.introEnd - clock + 0.1)
s.deck = { "swordfish", "tuna" }
for i = 3, 24 do s.deck[i] = "sardine" end
byJoiner = s.shoals[1].obj
s.shoals[1].obj.HealthInternal = 0
rtick(0.5)
check(s.haul[2] and s.haul[2].best == "swordfish" and not s.haul[0], "a joiner's kill: their swordfish, not the host's")
check(sent.fh[1] and sent.fh[1][1] == 2 and sent.fh[1][2] == "swordfish", "the catch sent to everyone (fh)")
check(callouts[#callouts]:find("SWORDFISH / DUKKA", 1, true), "its callout names them: " .. callouts[#callouts])
s.shoals[2].obj.hits = { { pawn, 100 } }; s.shoals[2].obj.HealthInternal = 0
rtick(0.5)
check(s.haul[0] and s.haul[0].best == "tuna", "the host's own tuna")
s.shoals[3].obj.hits = { { obj("BP_Ally2"), 100 } }; s.shoals[3].obj.HealthInternal = 0
rtick(0.5)
check(s.allyKg > 0 and sent.fh[3][1] == -1, "an ally's catch in co-op: the allies' (shared out), sent as -1")
check(#sent.row >= 1 and sent.row[#sent.row][1] == "fishing", "the row's numbers sent once a second (fsx)")
while s.state == "fishing" do rtick(1) end
while not s.carded do rtick(0.5) end
check(#sent.fw == 2 and #sent.fwe == 1 and sent.fwe[1][1] == 2, "each player's weigh-in sent (fw x2, fwe: 2 players)")
local hostKg = s.haul[0].kg + math.floor(s.allyKg / 2 + 0.5)
check(own[1] and own[1].n == FISH.payFor(hostKg, 2, 9, false) and not paid[1], string.format("the host's own pay through COOP.payOwn (%s for %d kg)",
    tostring(own[1] and own[1].n), hostKg))
check(SUB.cardUp and SUB.cardUp.lines[5] == "" and SUB.cardUp.lines[6]:find("FROM 2 PILOTS", 1, true) and SUB.cardUp.lines[7] ~= nil,
    "the card's team total and each player: " .. (SUB.cardUp and table.concat(SUB.cardUp.lines, " | ") or ""))
KILL.by = rawBy

print("the round: co-op (a joiner)")
RUN = { credits = 0 }
own = {}
COOP.host = function() return false end
COOP.client = function() return true end
COOP.slot = 2
D = { now = 6000, round = 9, state = "fighting", up = {}, hostSpecial = { kind = "fishing", state = "fishing" } }
clock = 6000
FISH.clientTick(6000)
FISH.fromHost("fsx", { "fsx", "fishing", "fishing", "95", "17", "321" })
local row = FISH.clientRow(CFG.hud.text)
check(row and row:find("1:35", 1, true) and row:find("SHOALS 17", 1, true) and row:find("HAUL 0 KG", 1, true) and row:find("TEAM 321", 1, true),
    "the joiner's row: " .. tostring(row))
FISH.fromHost("fh", { "fh", "2", "tuna", "60", "1803000", "-1160000" })
FISH.fromHost("fh", { "fh", "2", "shark", "60" })
FISH.fromHost("fh", { "fh", "40", "tuna", "60" })
check(FISH.cl.haul[2] and FISH.cl.haul[2].kg == 60 and FISH.cl.haul[2].hits == 1, "a catch of theirs counted; a bad catch or slot dropped")
row = FISH.clientRow(CFG.hud.text)
check(row:find("HAUL 60 KG", 1, true), "their own haul in the row")
FISH.fromHost("fw", { "fw", "0", "300", "9", "3", "swordfish", "120", "0" })
FISH.fromHost("fw", { "fw", "2", "60", "1", "0", "tuna", "60", "0" })
FISH.fromHost("fwe", { "fwe", "2", "400", "40", "9", "24" })
local wantJ = FISH.payFor(60 + 20, 2, 9, false)
check(#own == 1 and own[1].n == wantJ, string.format("the joiner paid its own haul through COOP.payOwn (%s, want %d)", tostring(own[1] and own[1].n), wantJ))
check(SUB.cardUp and SUB.cardUp.lines[6]:find("400 KG FROM 2 PILOTS", 1, true), "its card: " .. table.concat(SUB.cardUp.lines, " | "))
FISH.fromHost("fwe", { "fwe", "2", "400", "40", "9", "24" })
check(#own == 1, "a second fwe for the round: not paid twice")
-- ((code review of 2026-11-07, finding 8) the host's run started over (newRunHere here: a new RUN): its round 9 pays again
RUN = { credits = 0 }
FISH.fromHost("fw", { "fw", "2", "60", "1", "0", "tuna", "60", "0" })
FISH.fromHost("fwe", { "fwe", "2", "400", "40", "9", "24" })
check(#own == 2 and own[2].n == wantJ, "a new run here (the host's restart): its round 9's weigh-in paid again (" .. #own .. ")")
-- ((code review of 2026-11-07, finding 9) what the host sends kept in bounds: a haul to every shoal's heaviest catch,
-- the round to 1000, one weigh-in's pay to FISH.PAY_MAX
local most = FISH.maxShoals() * FISH.maxKg()
check(FISH.maxShoals() == 24 and FISH.maxKg() == 400, "the most a round holds: 24 shoals, 400 kg the heaviest catch")
FISH.fromHost("fw", { "fw", "2", "99999", "999", "999", "bigone", "4000", "1" })
local w2 = FISH.cl.weigh[2]
check(w2 and w2.kg == most and w2.hits == 24 and w2.empty == 24 and w2.bestKg == 400,
      string.format("fw: the haul clamped (%s kg, %s hits, best %s kg)", tostring(w2 and w2.kg), tostring(w2 and w2.hits), tostring(w2 and w2.bestKg)))
local fromW = #logs + 1
FISH.fromHost("fwe", { "fwe", "2", "999999", "999999", "99999", "999" })
check(#own == 3 and own[3].n == FISH.PAY_MAX, "fwe: the pay at most FISH.PAY_MAX (" .. tostring(own[3] and own[3].n) .. ")")
local wl = nil
for i = fromW, #logs do if logs[i]:find("fishing: the weigh-in here", 1, true) then wl = logs[i] end end
check(wl and wl:find("for round 1000,", 1, true), "fwe: the round clamped to 1000 (" .. tostring(wl) .. ")")
D.hostSpecial = { kind = "fishing", state = "done" }
FISH.clientTick(6001)
check(found("SAL's boat switched off here (the host's GONE FISHIN' is over)") ~= nil, "the host's round over: the boat's copy off here")
COOP = { host = function() return false end, client = function() return false end, removeNow = function(u) removed[#removed + 1] = u; return 0 end }

print("the test key: GONE FISHIN' now (Ctrl+HOME)")
check(binds.HOME ~= nil and TEST_KEYS.HOME ~= nil, "Ctrl+HOME bound through testKey")
D = { now = 100, round = 4, state = "wait", at = 130, up = {}, announced = true }
press("HOME")
check(D.forceSpecial == "fishing" and D.at == 103 and D.announced == false, "in the break: GONE FISHIN' in 3 s")
D = { now = 100, round = 4, state = "fighting", up = {} }
press("HOME")
check(D.forceSpecial == "fishing" and found("round 5 is GONE FISHIN' (after this round)") ~= nil, "in a fight: the next round")
COOP.client = function() return true end
D = { now = 100, round = 4, state = "wait", at = 130, up = {} }
press("HOME")
check(D.forceSpecial == nil, "a joiner: nothing (the host starts the rounds)")
COOP.client = function() return false end

print("a release's copy")
FISH, testKey, TEST_TICKS, TEST_KEYS = nil, nil, nil, nil
local src = readAll(STRIPPED .. "/Scripts/sv_fishing.lua")
check(not src:find("TEST ONLY", 1, true) and not src:find("testKey", 1, true) and not src:find("TEST_TICKS", 1, true), "no test code left in it")
npc.rows, mt.rows, adds = {}, {}, {}
part(STRIPPED, "sv_fishing.lua")
FISH.setup()
check(FISH.test == nil and FISH.rowsReady == true and npc.rows[C.shoal_row] ~= nil, "it loads and still adds the rows at the main menu")

print(fails == 0 and "fishing test: all passed" or ("fishing test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
