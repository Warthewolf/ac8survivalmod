-- festival_test.lua <mod dir> <work dir> <stripped dir> (run by tools/checks/festival_test.sh): THE FESTIVAL's Lua for the
-- first in-game test (Scripts/sv_festival.lua; tools/re/FISHING.md 6, 7) on the real sv_core, sv_config and sv_festival,
-- the game stubbed:
--   the geometry: the launch points 25 km north, west and south of the runway, the yaw that faces it from each, the
--     distance and height to it;
--   the test key (Ctrl+F12): nothing outside a run or on a joiner; a press spawns SV_Unit_FestCM_N1 at the north launch
--     point (launch_z up, facing the runway), each missile recorded in the spawner's order, the siren posted on an actor of
--     ours over the runway (PostEventAtActorByName), RE_SV_FestCM_N1 0.5 s on;
--   once a second each missile's distance, height and speed; within impact_m the host fires RE_SV_FestCMHit_N1_<i>, its
--     plane taken off the round's list first (no pay), and 1.5 s on which missile went down; one shot down: KILL.by;
--   the siren stopped siren_s on through the Wwise component on its actor, the actor destroyed;
--   taken off: a press while it's up, every missile over (5 s on), or test_s: the joiners' copies first, SPC.cleanUp,
--     SV_Recycle 2 s on; the level torn down: forgotten;
--   a release's copy: no test code, the siren and geometry still there.
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
VERSION = "0.74.0-festival.test"
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
local function arr(list) return { list = list, ForEach = function(self, fn) for i, x in ipairs(self.list) do fn(i, { get = function() return x end }) end end } end
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
SV_ERR = { [0] = "the game spawned nothing" }
local C = CFG.specials.festival

-- the game
local pawn = obj("/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_PlayerPlane_C_0")
survivalPC = obj("/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PlayerController_0", { Pawn = pawn })
local spawns, events, cleaned, recycled, removed, posts, stops = {}, {}, {}, {}, {}, {}, {}
local missiles = {}
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw, su = spawningUnit }
    missiles = {}
    for i = 1, 4 do
        local o = obj("/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_OP0039_slcmp_CP_C_" .. i,
            { HealthInternal = 250, loc = { X = x + (i - 1) * 6000, Y = y, Z = z }, hits = {} })
        function o:K2_GetActorLocation() return self.loc end
        missiles[#missiles + 1] = o
        for _, fn in ipairs(notifies["/Script/Live.LiveAIGameObject"] or {}) do fn(o) end
    end
    planes = {}
    for _, o in ipairs(missiles) do planes[#planes + 1] = { obj = o, addr = o.addr, unit = unit, name = o.full } end
    return #missiles
end
function SV_Event(n) events[#events + 1] = n; return 1 end
function SV_UnitAlive() return 0 end
function SV_Recycle(u, f) recycled[#recycled + 1] = u .. "/" .. tostring(f); return 1 end
local akCls, sceneCls, actorCls = obj("/Script/AkAudio.AkComponent"), obj("/Script/Engine.SceneComponent"), obj("/Script/Engine.Actor")
statics["/Script/AkAudio.AkComponent"], statics["/Script/Engine.SceneComponent"], statics["/Script/Engine.Actor"] = akCls, sceneCls, actorCls
local actors = {}
statics["/Script/Engine.Default__GameplayStatics"] = obj("/Script/Engine.Default__GameplayStatics", {
    BeginDeferredActorSpawnFromClass = function(_, wc, cls, t)
        local a = obj("/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.Actor_" .. (#actors + 1), { at = t.Translation })
        function a:AddComponentByClass(c)
            local s = obj("SceneComponent", { AttachChildren = arr({}) })
            function s:IsA(x) return x == c end
            self.RootComponent = s
            return s
        end
        function a:K2_SetActorLocation(l) self.at = l end
        function a:K2_DestroyActor() self.gone = true end
        actors[#actors + 1] = a
        return a
    end,
    FinishSpawningActor = function(_, a) return a end })
statics["/Script/Live.Default__LiveSoundBlueprintLibrary"] = obj("/Script/Live.Default__LiveSoundBlueprintLibrary", {
    PostEventAtActorByName = function(_, name, a)
        posts[#posts + 1] = { name = tostring(name), actor = a }
        local ak = obj("AkComponent_0")
        function ak:IsA(x) return x == akCls end
        function ak:Stop() stops[#stops + 1] = self end
        table.insert(a.RootComponent.AttachChildren.list, ak)
    end })
KILL = {
    side = function(o, pa) return addrOf(o) == pa and "you" or "other" end,
    read = function(p)
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

part(MOD, "sv_festival.lua")
local function press(k) assert(binds[k], "no bind for " .. k)(); KEYQ.drain() end
local function tick(s) clock = clock + s; for _, t in ipairs(TEST_TICKS) do t.fn(clock) end end
local function found(pat) for i = #logs, 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end return nil end
local function near(a, b) return math.abs(a - b) < 1e-6 end

print("the geometry")
local rx, ry = C.rwy[1], C.rwy[2]
for _, g in ipairs({ { "N", 0, -2500000, 90 }, { "W", -2500000, 0, 0 }, { "S", 0, 2500000, -90 } }) do
    local x, y, z = FEST.launchPoint(g[1])
    check(x == rx + g[2] and y == ry + g[3] and z == 200000, g[1] .. ": 25 km out, 2 km up")
    check(near(FEST.yawTo(x, y, rx, ry), g[4]), g[1] .. ": yaw " .. g[4] .. " faces the runway (" .. FEST.yawTo(x, y, rx, ry) .. ")")
    check(FEST.launchYaw(g[1]) == g[4] and math.type(FEST.launchYaw(g[1])) == "integer", g[1] .. ": its spawn yaw exactly " .. g[4])
end
local d, h = FEST.toRunway({ X = rx + 30000, Y = ry + 40000, Z = 10500 })
check(near(d, 500) and near(h, 100), "toRunway: 500 m out, 100 m up")
check(FEST.unit("W", 3) == "SV_Unit_FestCM_W3" and FEST.launchEvent("S", 2) == "RE_SV_FestCM_S2" and FEST.hitEvent("N", 1, 3) == "RE_SV_FestCMHit_N1_3",
    "the contract's names")

print("the key")
check(binds.F12 ~= nil and TEST_KEYS.F12 ~= nil, "Ctrl+F12 bound through testKey")
D = nil
press("F12")
check(#spawns == 0 and found("festival test: Ctrl+F12 outside a Survival run") ~= nil, "outside a run: nothing")
D = { now = 10, round = 3, state = "fighting", up = {} }
COOP.client = function() return true end
press("F12")
check(#spawns == 0 and found("the host launches the missiles") ~= nil, "a joiner: nothing")
COOP.client = function() return false end

print("the launch")
press("F12")
local s = spawns[1]
check(s and s.unit == "SV_Unit_FestCM_N1" and s.x == rx and s.y == ry - 2500000 and s.z == 200000 and s.yaw == 90, "SV_Unit_FestCM_N1 at N, 2 km up, yaw exactly 90")
check(s.su == "SV_Unit_FestCM_N1" and spawningUnit == nil, "spawningUnit around the spawn")
local T = FEST.test
check(#T.ms == 4 and T.ms[1].i == 0 and T.ms[4].i == 3, "4 missiles in the spawner's order, i 0-3")
check(#posts == 1 and posts[1].name == C.siren and actors[1].at.Z == C.rwy_z + C.siren_up_m * 100 and actors[1].at.X == rx,
    "the siren posted on an actor 10 m over the runway")
check(found("the air raid siren AKE_GEN_ENV_OBJ_AirRaid_Map17_Comona_Play at the runway: posted on Actor_1 (its scene root added)") ~= nil, "logged")
check(#events == 0, "the launch record not at once")
tick(0.6)
check(events[1] == "RE_SV_FestCM_N1" and found("festival test: RE_SV_FestCM_N1 fired: 1") ~= nil, "RE_SV_FestCM_N1 0.5 s on")
tick(1)
local line = found("festival test: +2 s: ")
check(line and line:find("0 25.00 km out, 1995 m up", 1, true), "each missile's distance and height: " .. tostring(line))
for _, m in ipairs(missiles) do m.loc = { X = m.loc.X, Y = m.loc.Y + 16667, Z = m.loc.Z } end   -- (600 km/h for 1 s)
tick(1)
line = found("festival test: +3 s: ")
check(line and line:find("km/h", 1, true) and line:find("0 24.83 km out, 1995 m up, 600 km/h", 1, true), "and its speed: " .. tostring(line))

print("an impact")
missiles[3].loc = { X = rx + 20000, Y = ry - 25000, Z = 10500 }   -- (missile 2: 320 m out, 100 m up)
tick(1)
check(events[#events] == "RE_SV_FestCMHit_N1_2", "within 400 m: RE_SV_FestCMHit_N1_2 (" .. tostring(events[#events]) .. ")")
check(planes[3].down == true and planes[3].cleaned == true, "its plane taken off the round's list first (no pay)")
check(found("festival test: missile 2 BP_OP0039_slcmp_CP_C_3 within 320 m of the runway (100 m up)") ~= nil, "logged")
missiles[3].HealthInternal = 0
tick(1)
tick(1)
check(found("festival test: 1.5 s after RE_SV_FestCMHit_N1_2: missiles down: 2 (the record's own, 2, down: it named that missile)") ~= nil,
    "1.5 s on: which missile it took down")
check(found("2 HIT the runway") ~= nil, "counted as a hit")
local nHits = 0
for _, e in ipairs(events) do if e:find("^RE_SV_FestCMHit") then nHits = nHits + 1 end end
check(nHits == 1, "fired once")

print("a missile shot down")
missiles[1].hits = { { pawn, 250 } }
tick(1)
missiles[1].HealthInternal = 0
tick(1)
line = found("festival test: missile 0 BP_OP0039_slcmp_CP_C_1 shot down")
check(line and line:find("by you", 1, true) and line:find("damage: you 250", 1, true), "who shot it down: " .. tostring(line))

print("the siren off")
tick(C.siren_s)
check(#stops == 1 and actors[1].gone == true, "stopped through its actor's Wwise component, the actor destroyed")
check(found("the air raid siren stopped: 1 of 1 Wwise components stopped (found on its root), its actor destroyed") ~= nil, "logged")

print("a press while it's up")
COOP.host = function() return true end
press("F12")
check(removed[1] == "SV_Unit_FestCM_N1" and #cleaned == 1 and cleaned[1].mortal == true and cleaned[1].n == 2, "the joiners' copies first, the 2 left finished off")
check(planes[2].down and planes[2].cleaned and planes[4].down and planes[4].cleaned, "their planes off the round's list (no pay)")
tick(2.5)
check(recycled[1] == "SV_Unit_FestCM_N1/1" and T.state == "idle", "SV_Recycle(unit, 1) 2 s on, idle")
COOP.host = function() return false end

print("every missile over; test_s; the level torn down")
press("F12")
tick(0.6)
for _, m in ipairs(missiles) do m.gone = true end
tick(1)
tick(5)
check(#cleaned == 2 and cleaned[2].why:find("every missile's over", 1, true), "taken off 5 s after every missile's end")
check(#stops == 2 and actors[2].gone == true, "the siren off with it")
tick(3)
press("F12")
tick(C.test_s + 1)
check(#cleaned == 3 and cleaned[3].why:find("300 s after the launch", 1, true), "taken off test_s after the launch")
tick(3)
press("F12")
LEVEL_DROPS["the festival"]("test"); LEVEL_DROPS["the festival test"]("test")
check(FEST.sirenActor == nil and next(FEST.actors) == nil and T.state == "idle", "the level torn down: forgotten")

print("a release's copy")
FEST, testKey, TEST_TICKS, TEST_KEYS = nil, nil, nil, nil
local src = readAll(STRIPPED .. "/Scripts/sv_festival.lua")
check(not src:find("TEST ONLY", 1, true) and not src:find("testKey", 1, true) and not src:find("TEST_TICKS", 1, true), "no test code left in it")
part(STRIPPED, "sv_festival.lua")
check(FEST.test == nil and type(FEST.sirenOn) == "function" and type(FEST.yawTo) == "function", "it loads with the siren and geometry")

print(fails == 0 and "festival test: all passed" or ("festival test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
