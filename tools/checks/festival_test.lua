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
Key = { F6 = "F6", F10 = "F10", F11 = "F11", F12 = "F12", PAGE_UP = "PAGE_UP", PAGE_DOWN = "PAGE_DOWN", HOME = "HOME" }
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

SPC.kinds = { spaceport = { ready = function() return true end } }   -- (THE FESTIVAL wraps its ready at load)
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

print("the round: its round, readiness and pay")
part(MOD, "sv_fishing.lua")
part(MOD, "sv_subs.lua")
part(MOD, "sv_sky.lua")
levelGoing = function() return false end
RUN = { arcF = 7 }
check(FEST.roundIs(13) and not FEST.roundIs(12) and not FEST.roundIs(14), "THE FESTIVAL is F + 6 (round 13 after GONE FISHIN' in 7)")
RUN = {}
check(not FEST.roundIs(13), "no GONE FISHIN' this run: no festival")
check(SPC.kinds.spaceport.ready(12) == true, "the Spaceport can come in round 12 with no festival due")
RUN = { arcF = 7 }
check(SPC.kinds.spaceport.ready(12) == false and SPC.kinds.spaceport.ready(11) == true, "not in the round before THE FESTIVAL (its retake would fall on it)")
SPC.festRows = nil
check(FEST.ready(13) == true and FEST.lightsReady() == false, "ready without the searchlights' rows (lights_required false)")
C.lights_required = true
check(FEST.ready(13) == false, "lights_required: not without them")
SPC.festRows = { want = 5, have = 5, lost = {} }
check(FEST.ready(13) == true and FEST.lightsReady() == true, "their rows in: ready, with searchlights")
C.lights_required = false
local fk, fb = FEST.killPay("SV_Unit_FestW")
local mk, mb = FEST.killPay("SV_Unit_FestCM_S3")
check(fk == "heavy" and fb == 400 and mk == "cruise missile" and mb == 150 and FEST.killPay("ERA_Unit_01_Dep_Air0") == nil,
    "a Tu-160 pays pay_bomber, a cruise missile pay_missile, others their own")

print("the round: the talk, the raid")
local alive, queued, removedObj, paid, lbs = {}, {}, {}, {}, {}
planes = {}
local bombers = {}
local lights = {}
function SV_Spawn(...)
    local unit, x, y, z, yaw = ...
    spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw, su = spawningUnit, n = select("#", ...) }
    local made = {}
    local g = unit:match("^SV_Unit_Fest([NWS])$")
    local nObj = (g and 4) or (unit:find("^SV_Unit_FestLight") and 2) or 4
    for i = 1, nObj do
        local o = obj("/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel." .. unit .. "_" .. i,
            { HealthInternal = 250, loc = { X = (x or 0) + (i - 1) * 6000, Y = y or 0, Z = z or 230000 }, hits = {} })
        function o:K2_GetActorLocation() return self.loc end
        function o:TurnOff() self.off = true end
        made[#made + 1] = o
        for _, fn in ipairs(notifies["/Script/Live.LiveAIGameObject"] or {}) do fn(o) end
        if not unit:find("^SV_Unit_FestLight") then planes[#planes + 1] = { obj = o, addr = o.addr, unit = unit, name = o.full } end
    end
    if g then bombers[g] = made end
    if unit:find("^SV_Unit_FestLight") then lights[unit] = made; SPC.CLEAN_OBJ[unit] = made end
    alive[unit] = #made
    return #made
end
function SV_UnitAlive(u) return alive[u] or 0 end
function queueEvent(at, name) queued[#queued + 1] = { at = at, name = name } end
function addCredits(n, why) paid[#paid + 1] = { n = n, why = why } end
specialPay = function(x) return x end
LB = { special = function(k, won) lbs[#lbs + 1] = { k = k, won = won } end }
ALIVE = { spawned = function() end }
COOP.removeObj = function(o) removedObj[#removedObj + 1] = o; return true end
local holds = {}                                   -- ((code review of 2026-11-07, finding 11) COOP.payHold's calls: obj -> on)
COOP.payHold = function(o, on) holds[o] = on and true or false; return true end
CFG.airfield.enabled = true
AF = { bomb = 0, down = false }
RUN = { arcF = 7, fishKg = 712 }
D = { now = 3000, round = 13, state = "spawning", up = {}, special = { kind = "festival", state = "pending" } }
clock = 3000
local s = D.special
check(FEST.roundSpawn(3000) == true and s.state == "talk", "THE FESTIVAL: the talk first")
local talk = {}
for _, l in ipairs(SUB.q) do talk[#talk + 1] = l.who .. ": " .. l.text end
check(#SUB.q == #C.text.talk and table.concat(talk, " | "):find("712 kilos you caught for us", 1, true), "the pilots thanked, GONE FISHIN''s 712 kg named")
check(s.talkEnd - 3000 >= 25, string.format("about 30 s of it (%.0f s)", s.talkEnd - 3000))
local longest = 0
for _, k in ipairs({ "talk", "impact", "all_down", "timeout" }) do
    for _, x in ipairs(C.text[k]) do local _, t = FISH.line(x, { kg = "9,999" }); longest = math.max(longest, #t) end
end
for _, k in ipairs({ "talk_nokg", "launch", "launch_again", "shot_first", "formation_down" }) do
    local _, t = FISH.line(C.text[k], { dir = "north" }); longest = math.max(longest, #t)
end
check(longest <= 70, "the festival's lines under 70 characters (" .. longest .. ")")
local function ftick(dt) clock = clock + dt; D.now = clock; FEST.roundTick(clock, s); SUB.hudTick(clock, true, false) end
posts, stops, spawns = {}, {}, {}
ftick(s.talkEnd - clock + 0.1)
check(s.state == "raid" and posts[1] and posts[1].name == C.siren, "the raid: the air raid siren at the airfield")
local formations = {}
for _, sp in ipairs(spawns) do if sp.unit:match("^SV_Unit_Fest[NWS]$") then formations[#formations + 1] = sp end end
check(#formations == 3 and formations[1].n == 1 and formations[1].x == nil, "three formations spawned with no pose (SV_Spawn(unit) alone)")
check(lights.SV_Unit_FestLight_1 and lights.SV_Unit_FestLight_4, "the four searchlights (their rows in)")
check(#queued == 3 and queued[1].name == "RE_SV_FestUp_N" and queued[1].at == clock + C.up_after_s, "each formation's orders (RE_SV_FestUp_<g>) up_after_s on")
check(callouts[#callouts] == "AIR RAID / TU-160S FROM THE NORTH, WEST AND SOUTH", "the raid's callout")
-- the north formation over its launch point: a salvo from SV_Unit_FestCM_N1
local nx, ny = FEST.launchPoint("N")
for _, p in ipairs(planes) do if p.unit == "SV_Unit_FestN" then p.at = { X = nx + 100000, Y = ny, Z = 230000 } end end
spawns, events = {}, {}
ftick(0.5)
check(spawns[1] and spawns[1].unit == "SV_Unit_FestCM_N1" and spawns[1].x == nx and spawns[1].y == ny and spawns[1].z == 200000 and spawns[1].yaw == 90,
    "over its launch point: SV_Unit_FestCM_N1 there, 2 km up, yaw 90")
check(#s.salvos == 1 and #s.salvos[1].ms == 4, "its four missiles recorded")
local launchLine = false
for _, l in ipairs(SUB.q) do if l.text:find("Missile launch from the north", 1, true) then launchLine = true end end
check(launchLine or (SUB.cur and SUB.cur.text:find("north", 1, true)), "CONTROL calls the launch")
ftick(0.5)
check(events[1] == "RE_SV_FestCM_N1", "its flight record 0.5 s on")
ftick(0.5)
check(#s.salvos == 1, "no second salvo in launch_gap_s")
-- an impact: missile 2 within 400 m of the runway
local sl = s.salvos[1]
local m2 = sl.ms[2]
for _ = 1, 10 do ftick(0.5) end
m2.obj.loc = { X = C.rwy[1] + 30000, Y = C.rwy[2], Z = 10000 }
events = {}
ftick(0.5)
local mp = nil
for _, p in ipairs(planes) do if p.obj == m2.obj then mp = p end end
check(events[1] == "RE_SV_FestCMHit_N1_1" and mp.down and mp.cleaned and removedObj[1] == m2.obj, "on the runway: its impact record, off the list, down unpaid on every game")
check(AF.bomb == C.impact_damage, "the airfield takes impact_damage (" .. AF.bomb .. ")")
-- ((code review of 2026-11-07, finding 11) the impacting missile finished off here at once; the salvo's others held unpaid
-- 1.5 s (off the sweep, their co-op kill a removal), so one the record takes in its place isn't paid as a kill
local function entry(o) for _, p in ipairs(planes) do if p.obj == o then return p end end return nil end
check(m2.obj.MinHealth == 0.0, "the impacting missile finished off here at once (its floor off, ModifyHealth)")
local heldP = {}
for _, i in ipairs({ 1, 3, 4 }) do
    local m, p = sl.ms[i], entry(sl.ms[i].obj)
    heldP[i] = p
    check(m.holdUntil and p and p.down and p.cleaned and p.festHeld and holds[m.obj] == true,
          string.format("missile %d of the salvo held unpaid %.1f s (off the sweep, COOP.payHold)", m.i, FEST.IMPACT_HOLD_S))
end
m2.obj.HealthInternal = 0
-- the record named missile 0 (its i not the spawner's order): it goes down in the hold: the record's, not counted or paid
sl.ms[1].obj.HealthInternal = 0
ftick(0.5)
check(s.missilesDown == 0 and sl.ms[1].over and heldP[1].down and heldP[1].cleaned
      and found("went down within 1.5 s of its salvo's impact record"), "a missile down in the hold: the record's, not counted, its sweep entry left down (unpaid)")
-- the hold over: the others back on the sweep, their kills paid again
ftick(0.5); ftick(0.5); ftick(0.5)
check(not heldP[3].down and not heldP[3].cleaned and not heldP[4].down and holds[sl.ms[3].obj] == false and not sl.ms[4].holdUntil,
      "1.5 s on: the salvo's others still up let go (back on the sweep, COOP.payHold off)")
-- missile 2 shot down after the hold: the first one's line
sl.ms[3].obj.HealthInternal = 0
ftick(0.5)
check(s.missilesDown == 1, "one shot down counted")
local shotLine = false
for _, l in ipairs(SUB.q) do if l.text:find("grill is safe", 1, true) then shotLine = true end end
if SUB.cur and SUB.cur.text:find("grill is safe", 1, true) then shotLine = true end
check(shotLine, "SAL cheers the first one")
check(s.bombers == 12 and s.inAir == 1, "the row's numbers: 12 bombers, 1 missile still up (" .. tostring(s.bombers) .. ", " .. tostring(s.inAir) .. ")")
check(FEST.row(s, CFG.hud.text) == "THE FESTIVAL  BOMBERS: 12  MISSILES IN THE AIR: 1", "the NEXT row: " .. tostring(FEST.row(s, CFG.hud.text)))
-- the last one down: the salvo over, recycled 3 s on, its unit free again
sl.ms[4].obj.HealthInternal = 0
recycled = {}
ftick(0.5); ftick(0.5)
check(sl.over and not sl.freed, "the salvo's over: its recycle 3 s on")
alive.SV_Unit_FestCM_N1 = 0
for _ = 1, 7 do ftick(0.5) end
check(recycled[1] == "SV_Unit_FestCM_N1/1" and #s.salvos == 0, "SV_Recycle(SV_Unit_FestCM_N1, 1): free to spawn again")
-- the west formation's clock: first_launch_w after the raid's start, its pass not seen
spawns = {}
for _, p in ipairs(planes) do if p.unit == "SV_Unit_FestN" then p.at = { X = nx, Y = ny - 900000, Z = 230000 } end end
while clock < s.raidAt + C.first_launch_w + 0.5 do ftick(0.5) end
local west = nil
for _, sp in ipairs(spawns) do if sp.unit == "SV_Unit_FestCM_W1" then west = sp end end
check(west and west.yaw == 0 and found("its clock (its pass not seen)"), "the west formation's salvo on its clock (yaw 0)")
local south = nil
for _, sp in ipairs(spawns) do if sp.unit == "SV_Unit_FestCM_S1" then south = sp end end
check(south and south.yaw == -90, "the south formation's on its clock too (yaw -90)")
-- the north formation again: its next unit (N2), N1's recycle still to come in this test's spawner
alive.SV_Unit_FestCM_N1 = 4
for _, p in ipairs(planes) do if p.unit == "SV_Unit_FestN" then p.at = { X = nx, Y = ny, Z = 230000 } end end
spawns = {}
while #spawns == 0 and clock < s.raidAt + 600 do ftick(0.5) end
check(spawns[1] and spawns[1].unit == "SV_Unit_FestCM_N2", "the next pass: the next unit (" .. tostring(spawns[1] and spawns[1].unit) .. ")")
-- every bomber down, every missile down: the festival saved
for u in pairs(alive) do alive[u] = 0 end
for _, x in ipairs(s.salvos) do for _, m in ipairs(x.ms) do m.obj.HealthInternal = 0 end end
local nStops = #stops
for _ = 1, 4 do ftick(0.5) end
check(s.state == "done" and FEST.busy(s) == false, "every bomber down and nothing in the air: done")
local want = C.reward + C.reward_per_round * 13
check(paid[#paid] and paid[#paid].n == want and paid[#paid].why == "the festival saved", "the reward (" .. want .. ")")
check(#stops > nStops and FEST.sirenActor == nil, "the siren stopped")
check(lights.SV_Unit_FestLight_2[1].off == true, "the searchlights turned off")
check(lbs[#lbs].k == "festival" and lbs[#lbs].won == true, "the leaderboard's special: festival, won")
check(found("formation is down") ~= nil, "each formation's end called")

print("the round: the time limit")
alive, planes, spawns = {}, {}, {}
D = { now = 9000, round = 13, state = "spawning", up = {}, special = { kind = "festival", state = "pending" } }
clock = 9000
s = D.special
COOP.host = function() return true end
removed = {}
FEST.roundSpawn(9000)
ftick(s.talkEnd - clock + 0.1)
while s.state == "raid" and clock < 9000 + 2000 do ftick(5) end
check(s.state == "done" and found("the raid over (900 s: the time limit)") ~= nil, "time_limit_s: the raid ends whatever's left")
check(#removed >= 12 and removed[1] == "SV_Unit_FestN", "the host takes the joiners' copies down first (COOP.removeNow)")
check(lbs[#lbs].won == false, "not won")
COOP.host = function() return false end

-- ((code review of 2026-11-07, finding 3) a pause-menu restart mid-raid: the siren (our own actor, never the mission's)
-- and the searchlights off, from sv_main.lua's level-load block before the new run's D
print("the round: a restart mid-raid")
alive, planes, spawns = {}, {}, {}
D = { now = 9200, round = 13, state = "spawning", up = {}, special = { kind = "festival", state = "pending" } }
clock = 9200
s = D.special
FEST.roundSpawn(9200)
ftick(s.talkEnd - clock + 0.1)
check(s.state == "raid" and FEST.sirenActor ~= nil, "(the raid on, its siren up)")
local nS0 = #stops
lights.SV_Unit_FestLight_1[1].off = nil
FEST.restart("the run starts over")
check(FEST.sirenActor == nil and #stops > nS0 and lights.SV_Unit_FestLight_1[1].off == true
      and found("festival: the run starts over: the siren off"), "FEST.restart: the siren stopped and its actor gone, the searchlights off, logged")
do
    local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
    local a = mainSrc:find("if levelTick == -1 then", 1, true)
    local b = a and mainSrc:find("local first = SETUP.startRound()", a, true)
    local blk = (a and b) and mainSrc:sub(a, b) or ""
    check(blk:find("FEST.restart", 1, true) and blk:find("FISH.boatOff", 1, true) and blk:find("SUB.cardOff", 1, true)
          and blk:find("ESC.restart", 1, true), "sv_main.lua's level-load block (a restart's): FEST.restart, FISH.boatOff, SUB.cardOff, ESC.restart")
end
D.special = nil

print("the round: a joiner")
COOP.client = function() return true end
posts, stops = {}, {}
D = { now = 9500, round = 13, state = "fighting", up = {}, hostSpecial = { kind = "festival", state = "talk" } }
FEST.clientTick(9500)
check(#posts == 0, "the host's talk: no siren yet")
D.hostSpecial.state = "raid"
FEST.clientTick(9501)
check(#posts == 1 and posts[1].name == C.siren, "the host's raid: the siren here too")
FISH.fromHost("fsx", { "fsx", "festival", "raid", "9", "3", "0" })
check(FEST.clientRow(CFG.hud.text) == "THE FESTIVAL  BOMBERS: 9  MISSILES IN THE AIR: 3", "the host's row: " .. tostring(FEST.clientRow(CFG.hud.text)))
lights.SV_Unit_FestLight_3[1].off = nil
D.hostSpecial = { kind = "festival", state = "done" }
FEST.clientTick(9502)
check(#stops >= 1 and found("the host's raid is over: the siren off here"), "its end: the siren off here")
check(found("searchlight copies off here") ~= nil and lights.SV_Unit_FestLight_3[1].off == true, "the searchlights' copies off here")
COOP.client = function() return false end

print("the test key: THE FESTIVAL now (Ctrl+PAGE_UP)")
check(binds.PAGE_UP ~= nil, "Ctrl+PAGE_UP bound")
RUN = {}
D = { now = 100, round = 9, state = "wait", at = 130, up = {} }
press("PAGE_UP")
check(D.forceSpecial == "festival" and RUN.arcF == 4 and D.at == 103 and FEST.roundIs(10), "the next round (10) is THE FESTIVAL: F = 4, the sky at sunset")

print("a release's copy")
FEST, testKey, TEST_TICKS, TEST_KEYS = nil, nil, nil, nil
local src = readAll(STRIPPED .. "/Scripts/sv_festival.lua")
check(not src:find("TEST ONLY", 1, true) and not src:find("testKey", 1, true) and not src:find("TEST_TICKS", 1, true), "no test code left in it")
part(STRIPPED, "sv_festival.lua")
check(FEST.test == nil and type(FEST.sirenOn) == "function" and type(FEST.yawTo) == "function", "it loads with the siren and geometry")

print(fails == 0 and "festival test: all passed" or ("festival test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
