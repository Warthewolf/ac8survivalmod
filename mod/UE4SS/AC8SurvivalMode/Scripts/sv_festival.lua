-- sv_festival.lua: THE FESTIVAL (CFG.specials.festival; FISHING_ROUND_PLAN.md 0; tools/re/FISHING.md 6): the cruise
-- missiles and the air raid siren. Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another
-- part uses is a global of this mod's Lua state, its own helpers stay local.
-- The round itself comes later: for now its geometry, what each spawn makes (FEST.actors), the siren and the first
-- in-game test's key (Ctrl+F12, test only).
-- The build data (tools/build_survival.py / survival_events.py, the contract of 2026-11-06): the missiles are Mission 30's
-- path-flown kind (DT_NPC OP0039_slcmp_01, an ordinary AI plane; mission row sv_fest_cm), units SV_Unit_FestCM_<g><k>
-- (g N / W / S, k 1-3) of 4 side by side 60 m apart, boxed and TGT; RE_SV_FestCM_<g><k> flies them from the launch point
-- down to ~100 m and on to the runway at 600 km/h (path SV_Path_FestCM_<g>, engagement None, look-ahead 0); the impact
-- record RE_SV_FestCMHit_<g><k>_<i> (i 0-3) destroys that one object (LiveDestroyUnitExecution). Lua spawns the unit at the
-- launch point (launch_z up, at its group's exact yaw: FEST.LAUNCH_YAW), fires the launch record, and on the host fires
-- the impact record when that missile is within impact_m of the runway, measured flat (they cruise ~100 m up and pass
-- within 90 m of its centre).
FEST = { actors = {}, sirenActor = nil }
do
local function cfg() return CFG.specials.festival end
FEST.GROUPS = { "N", "W", "S" }
function FEST.unit(g, k) return "SV_Unit_FestCM_" .. g .. tostring(k) end
function FEST.launchEvent(g, k) return "RE_SV_FestCM_" .. g .. tostring(k) end
function FEST.hitEvent(g, k, i) return string.format("RE_SV_FestCMHit_%s%d_%d", g, k, i) end
-- the launch point of group g (N, W, S): x, y, z (UE cm)
function FEST.launchPoint(g)
    local p = cfg()["launch_" .. tostring(g):lower()]
    if type(p) ~= "table" then return nil end
    return p[1], p[2], cfg().launch_z
end
-- the UE yaw (degrees, 0 = +X east, 90 = +Y south) from (x, y) to (tx, ty)
function FEST.yawTo(x, y, tx, ty) return math.deg(math.atan(ty - y, tx - x)) end
-- each group's spawn yaw, exactly as the build data's lanes want it (feature/fishing d0fc323: N 90, W 0, S -90; any other
-- yaw turns the unit's four missiles off their lanes), not worked out with atan
FEST.LAUNCH_YAW = { N = 90, W = 0, S = -90 }
function FEST.launchYaw(g) return FEST.LAUNCH_YAW[tostring(g):upper()] end
-- from a location to the runway: the horizontal distance (m) and the height over it (m)
function FEST.toRunway(l)
    local r, c = cfg().rwy, cfg()
    local dx, dy = l.X - r[1], l.Y - r[2]
    return math.sqrt(dx * dx + dy * dy) / 100, (l.Z - (c.rwy_z or 0)) / 100
end

-- What each missile unit's spawn makes: FEST.actors[unit] = { obj, ... } in the spawner's order (desc order, [I]), while a
-- caller has opened the list (FEST.spawn: spawningUnit set around its SV_Spawn)
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    local l = u and FEST.actors[u]
    if l and l.open then l[#l + 1] = o end
end)
function FEST.spawn(unit, x, y, z, yaw)
    FEST.actors[unit] = { open = true }
    spawningUnit = unit
    local ok, r = pcall(SV_Spawn, unit, x, y, z, yaw)
    spawningUnit = nil
    FEST.actors[unit].open = false
    if not ok then log("festival: SV_Spawn " .. unit .. " error " .. tostring(r)); return -5 end
    return r
end

-- The air raid siren (cfg().siren, AKB_GameSe: loops, no stop event of its own): posted on an actor of ours at `at` (a
-- plain actor, a scene root to carry the Wwise component), stopped through that component (FEST.sirenOff). The actor, or
-- nil and why not.
function FEST.sirenOn(at)
    FEST.sirenOff("a new siren")
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local actorCls, sceneCls = StaticFindObject("/Script/Engine.Actor"), StaticFindObject("/Script/Engine.SceneComponent")
    local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
    if not (gs and valid(gs) and actorCls and valid(actorCls) and sceneCls and valid(sceneCls)) then return nil, "engine classes not found" end
    if not (lib and valid(lib)) then return nil, "LiveSoundBlueprintLibrary not found" end
    if not liveObj(survivalPC) then return nil, "no player controller" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okA, a = pcall(function()
        local x = gs:BeginDeferredActorSpawnFromClass(survivalPC, actorCls, t, 1, nil, 1)    -- (AlwaysSpawn, MultiplyWithRoot)
        return gs:FinishSpawningActor(x, t, 1)
    end)
    if not okA or a == nil or not valid(a) then return nil, "no actor (" .. tostring(a) .. ")" end
    local okC = pcall(function()
        return a:AddComponentByClass(sceneCls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
                                     Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    end)
    pcall(function() a:K2_SetActorLocation({ X = at.X, Y = at.Y, Z = at.Z }, false, {}, true) end)
    local okP, errP = pcall(function() lib:PostEventAtActorByName(FName(cfg().siren), a) end)
    if not okP then
        pcall(function() a:K2_DestroyActor() end)
        return nil, "PostEventAtActorByName failed: " .. tostring(errP)
    end
    FEST.sirenActor = a
    return a, string.format("posted on %s (its scene root %s)", (nameOf(a):match("([^%.:]+)$")) or "?", okC and "added" or "NOT added")
end
-- the Wwise components on actor a (its root and what hangs on it; else a walk over every AkComponent by its owner)
local function akComps(a)
    local cls, out, seen = StaticFindObject("/Script/AkAudio.AkComponent"), {}, {}
    local function add(x)
        local ad = addrOf(x)
        if ad and not seen[ad] then seen[ad] = true; out[#out + 1] = x end
    end
    if cls and valid(cls) then
        pcall(function()
            local root = a.RootComponent
            if root ~= nil and valid(root) and root:IsA(cls) then add(root) end
            root.AttachChildren:ForEach(function(_, e) local x = e:get(); if valid(x) and x:IsA(cls) then add(x) end end)
        end)
    end
    if #out > 0 then return out, "on its root" end
    local me = addrOf(a)
    for _, x in ipairs(FindAllOf("AkComponent") or {}) do
        local ok, w = pcall(function() return x:GetOwner() end)
        if ok and valid(w) and addrOf(w) == me then add(x) end
    end
    return out, "by a walk"
end
-- the siren stopped (each Wwise component on its actor: Stop, as sv_alicorn.lua's silence()) and its actor destroyed;
-- how many components were stopped and how they were found
function FEST.sirenOff(why)
    local a = FEST.sirenActor
    FEST.sirenActor = nil
    if a == nil then return 0, "no siren" end
    if not liveObj(a) then return 0, "its actor is gone" end
    local comps, how = akComps(a)
    local n = 0
    for _, x in ipairs(comps) do if pcall(function() x:Stop() end) then n = n + 1 end end
    local okD = pcall(function() a:K2_DestroyActor() end)
    return n, string.format("%d of %d Wwise components stopped (found %s), its actor %s (%s)", n, #comps, how,
        okD and "destroyed" or "NOT destroyed", tostring(why or "?"))
end

-- (the teardown gate's drop, sv_core.lua levelDrop: the level's objects forgotten untouched)
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the festival"] = function() FEST.actors, FEST.sirenActor = {}, nil end end
end

-- TEST ONLY BEGIN
-- Ctrl+F12 in a run (the host's or solo): one cruise missile salvo and the siren (tools/re/FISHING.md 7, test 4).
--   1st press: SV_Unit_FestCM_N1 at the north launch point (launch_z up, facing the runway), RE_SV_FestCM_N1 0.5 s on, the
--     air raid siren posted on an actor over the runway and stopped siren_s later; once a second a line with each
--     missile's distance to the runway, height and speed; within impact_m the host fires its impact record
--     RE_SV_FestCMHit_N1_<i> (logged, and 1.5 s on which missile it took down); a missile shot down: who did it (KILL.by).
--     Everything left is taken off test_s after the launch, or 5 s after the last missile's end.
--   2nd press (while it's up): everything taken off now (the joiners' copies first, SPC.cleanUp, SV_Recycle 2 s on).
do
local G, K = "N", 1
local T = { state = "idle", run = nil, ms = {} }
FEST.test = T
local function c() return CFG.specials.festival end
local function reset() T.state, T.run, T.ms, T.launchAt, T.sirenAt, T.endAt, T.recycleAt, T.doneAt = "idle", nil, {}, nil, nil, nil, nil, nil end
local function host() return not (COOP and COOP.client and COOP.client()) end
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function planeOf(addr)
    for _, p in ipairs(planes or {}) do if addr and p.addr == addr then return p end end
    return nil
end
local function start(now)
    local unit = FEST.unit(G, K)
    local x, y, z = FEST.launchPoint(G)
    local r0 = c().rwy
    local yaw = FEST.launchYaw(G)
    local r = FEST.spawn(unit, x, y, z, yaw)
    local objs = {}
    for _, o in ipairs(FEST.actors[unit] or {}) do if liveObj(o) then objs[#objs + 1] = o end end
    T.ms = {}
    local names = {}
    for i, o in ipairs(objs) do
        local m = { obj = o, addr = addrOf(o), i = i - 1, name = (nameOf(o):match("([^%.:]+)$")) or "?", at = at(o) }
        T.ms[#T.ms + 1] = m
        local h = nil
        pcall(function() h = o.HealthInternal end)
        names[#names + 1] = string.format("%d %s (health %s)", m.i, m.name, tostring(h))
    end
    log(string.format("festival test: %s at the north launch point (%d, %d), %d cm up, yaw %d (the runway's bearing %.1f, %.1f km): %s; "
        .. "missiles in the spawner's order (the impact records' i, unconfirmed): %s", unit, x, y, z, yaw, FEST.yawTo(x, y, r0[1], r0[2]),
        math.sqrt((x - r0[1]) ^ 2 + (y - r0[2]) ^ 2) / 100000, r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")"),
        #names > 0 and table.concat(names, ", ") or "none seen"))
    local up = (tonumber(c().siren_up_m) or 10) * 100
    local a, what = FEST.sirenOn({ X = r0[1], Y = r0[2], Z = (c().rwy_z or 500) + up })
    log(string.format("festival test: the air raid siren %s at the runway: %s", c().siren, a and what or ("NOT posted: " .. tostring(what))))
    T.state, T.run, T.at = "up", D, now
    T.launchAt, T.nextLog = now + 0.5, now + 1
    T.sirenAt = a and (now + (tonumber(c().siren_s) or 20)) or nil
    T.endAt = now + (tonumber(c().test_s) or 300)
    hudCallout("TEST: THE FESTIVAL", string.format("%d MISSILES FROM THE NORTH, SIREN %s", #T.ms, a and "ON" or "NOT ON"))
end
local function takeOff(now, why)
    T.state = "removing"
    local unit = FEST.unit(G, K)
    if COOP and COOP.host and COOP.host() and COOP.removeNow then pcall(COOP.removeNow, unit) end
    local l = { at = os.clock() }
    for _, m in ipairs(T.ms) do
        if not m.over and liveObj(m.obj) then
            l[#l + 1] = m.obj
            local p = planeOf(m.addr)
            if p and not p.down then p.down, p.cleaned = true, true end   -- (no pay, no stats: taken off)
        end
    end
    SPC.CLEAN_OBJ[unit] = l
    local n = SPC.cleanUp({ unit }, "the festival test over (" .. why .. ")", true, D and D.now or 0)
    if FEST.sirenActor then
        local nS, wS = FEST.sirenOff("the test taken off")
        log("festival test: the siren off with it: " .. tostring(wS) .. " (" .. nS .. ")")
    end
    log(string.format("festival test: taken off (%s): %d missiles finished off or switched off", why, n))
    T.recycleAt = now + 2
end
local function recycle()
    local unit = FEST.unit(G, K)
    local n0 = type(SV_UnitAlive) == "function" and SV_UnitAlive(unit) or -5
    local okR, r = false, "no SV_Recycle"
    if type(SV_Recycle) == "function" then crumb("festival test: SV_Recycle " .. unit); okR, r = pcall(SV_Recycle, unit, 1) end
    log(string.format("festival test: %s off the spawner's list: %d alive -> SV_Recycle %s -> %s alive", unit, n0,
        okR and tostring(r) or ("error " .. tostring(r)), tostring(type(SV_UnitAlive) == "function" and SV_UnitAlive(unit) or "?")))
    FEST.actors[unit] = nil
    reset()
end
local function tick(now)
    if T.state == "idle" then return end
    if T.run ~= D or (levelTorn and levelTorn()) then reset(); return end
    if T.state == "removing" then
        if T.recycleAt and now >= T.recycleAt then recycle() end
        return
    end
    if T.launchAt and now >= T.launchAt then
        T.launchAt = nil
        local ev = FEST.launchEvent(G, K)
        local r = type(SV_Event) == "function" and SV_Event(ev) or -5
        log(string.format("festival test: %s fired: %s", ev, r == 1 and "1" or (tostring(r) .. " " .. tostring(SV_ERR and SV_ERR[r] or ""))))
    end
    if T.sirenAt and now >= T.sirenAt then
        T.sirenAt = nil
        local n, what = FEST.sirenOff(string.format("%d s on", math.floor(tonumber(c().siren_s) or 20)))
        log("festival test: the air raid siren stopped: " .. tostring(what) .. " (" .. n .. ")")
    end
    if now >= (T.endAt or math.huge) then takeOff(now, string.format("%d s after the launch", math.floor(tonumber(c().test_s) or 300))); return end
    if T.doneAt and now >= T.doneAt then takeOff(now, "every missile's over"); return end
    if now < (T.nextLog or 0) then return end
    local dt = now - (T.lastLog or now)
    T.nextLog, T.lastLog = now + 1, now
    local parts, left = {}, 0
    for _, m in ipairs(T.ms) do
        if m.hitAt and not m.checked and now >= m.hitAt + 1.5 then
            m.checked = true
            local downs = {}
            for _, o in ipairs(T.ms) do
                local gone = not liveObj(o.obj) or (function() local h; pcall(function() h = o.obj.HealthInternal end); return type(h) == "number" and h <= 0 end)()
                if gone then downs[#downs + 1] = tostring(o.i) end
            end
            log(string.format("festival test: 1.5 s after %s: missiles down: %s (the record's own, %d, %s)", FEST.hitEvent(G, K, m.i),
                #downs > 0 and table.concat(downs, ", ") or "none", m.i,
                (function() for _, d in ipairs(downs) do if d == tostring(m.i) then return "down: it named that missile" end end return "NOT down" end)()))
        end
        if not m.over then
            local up, h = liveObj(m.obj), nil
            if up then pcall(function() h = m.obj.HealthInternal end) end
            local l = up and at(m.obj) or nil
            if not up or (type(h) == "number" and h <= 0) then
                m.over = true
                if m.hitAt then
                    parts[#parts + 1] = string.format("%d HIT the runway", m.i)
                else
                    if up then pcall(KILL.read, m) end
                    local okB, by = pcall(KILL.by, m)
                    local d = m.dmg or {}
                    log(string.format("festival test: missile %d %s shot down at +%.0f s, %.1f km from the runway: by %s%s (damage: you %.0f, "
                        .. "wingmate %.0f, allies %.0f)", m.i, m.name, now - (T.at or now), m.dist and m.dist / 1000 or -1,
                        okB and tostring(by) or "?", type(m.killer) == "number" and (" (player " .. (m.killer + 1) .. ")") or "",
                        d.you or 0, d.wingmate or 0, d.allies or 0))
                    parts[#parts + 1] = string.format("%d SHOT DOWN", m.i)
                end
            elseif l then
                pcall(KILL.read, m)
                local dist, hgt = FEST.toRunway(l)
                local spd = 0
                if m.at and dt > 0 then
                    local dx, dy, dz = l.X - m.at.X, l.Y - m.at.Y, l.Z - m.at.Z
                    spd = math.sqrt(dx * dx + dy * dy + dz * dz) / 100 / dt * 3.6
                end
                m.at, m.dist = l, dist
                left = left + 1
                parts[#parts + 1] = string.format("%d %.2f km out, %.0f m up, %.0f km/h", m.i, dist / 1000, hgt, spd)
                if host() and not m.hitAt and dist <= (tonumber(c().impact_m) or 400) then
                    local p = planeOf(m.addr)
                    if p and not p.down then p.down, p.cleaned = true, true end   -- (its impact pays nothing)
                    local ev = FEST.hitEvent(G, K, m.i)
                    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
                    m.hitAt = now
                    log(string.format("festival test: missile %d %s within %.0f m of the runway (%.0f m up) at +%.0f s: %s fired: %s", m.i, m.name,
                        dist, hgt, now - (T.at or now), ev, tostring(r)))
                end
            end
        end
    end
    log(string.format("festival test: +%.0f s: %s", now - (T.at or now), #parts > 0 and table.concat(parts, "; ") or "no missiles"))
    if left == 0 and not T.doneAt then T.doneAt = now + 5 end
end
testKey("F12", "sv_festival.lua's festival test", function()
    local now = os.clock()
    if not (D and D.now) or not nativeReady() then log("festival test: Ctrl+F12 outside a Survival run"); return end
    if not host() then log("festival test: Ctrl+F12: the host launches the missiles (you're a joiner)"); return end
    if T.run ~= D then reset() end
    if T.state == "idle" then start(now)
    elseif T.state == "up" then takeOff(now, "Ctrl+F12")
    else log("festival test: still being taken off: press again in a moment") end
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "festival test", fn = tick }
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the festival test"] = function() reset() end end
end
-- TEST ONLY END
