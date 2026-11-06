-- sv_escort.lua: THE ESCORT (the allied B-1B CHARLENE and her four escorts, flown in and landed at Comona airfield) and
-- its reward, the ZFA-44 carriers in the STORE (tools/re/ESCORT.md; user, 2026-11-06; build contract of 2026-11-06).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local.
--
-- The special kind "escort" (SPC.kinds.escort, CFG.specials.escort), the host's (or solo):
--   spawn   CHARLENE at CFG start (her unit SV_Unit_Charlene, SV_Spawn at a pose), the four escorts beside her, each one's
--           route record (<rec>Go) go_delay_s later; once a run (RUN.escort), only when its units are in the world data
--   attack  the round's fighter flights (attack.share of them, at most attack.max at once) each plane's
--           EngagementOrderOverride onto her (Normal, TargetFirst; VOID WATCHER 1's strike flight's way), again every
--           again_s; ESC.holds(unit) keeps them out of the squad director (sv_director.lua busy), co-op's split hunt
--           (sv_coop.lua) and the allies' hunts (sv_allies.lua); back on you at her touchdown or loss. The round's flights
--           spawn ahead of her (DIR.spawnAt, ahead.share) and more come while she flies (reinforce)
--   guard   the escorts' planes onto the enemies nearest her, every guard.every_s
--   landing by distance to CFG geo (Lua fires each step's record): her final within final_at_m of the approach fix (gear
--           down: EnableLandingGear; landing closed to the players), rollout near the touchdown point (invincible), taxi
--           near the rollout's end, stop near her parking spot, landed when stopped; the escorts' orbit at her final, then
--           each one's final one at a time once the runway's clear (release_gap_s apart); safety timeouts count one as landed
--   end     her death: the special failed (no reward, no unlock, the run goes on); everyone left landed: the reward, her
--           subtitle (the big callout), the ZFA-44 carriers unlocked (RUN.zfa: the run's, the room's in co-op); at the
--           round's end every one of them switched off and taken off the spawner's list
-- The ZFA-44 carriers (CFG.allies.carrier, the STORE's ZfaCarrier): ESC.buyCarrier (a joiner's built by the host,
-- sv_shop.lua shopBuildFor), each ship's ZFA-44 flight launched from its container launchers (RE_SV_CargoLaunch_<s>_<n>)
-- or, as a fallback, spawned at a pose off its bow, relaunched when it's down, VOID WATCHER 1's service count, then off.
-- Every game dresses its own planes of those flights as the ZFA-44 (sv_zfa44.lua ZFA.dress).
-- Co-op: the host sends "es" (the escort's state, the unlock, the carriers out, landing closed); a joiner keeps it
-- (ESC.onHost: its NEXT row, STORE and landing). Log lines `escort: ...`, `carrier: ...`.
ESC = { S = nil, R = nil, planes = {}, dressQ = {}, newObjs = {}, hulls = {}, host = nil, recycleQ = {} }

do
local function ec() return CFG.specials.escort end
local function cc() return CFG.allies.carrier end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function now0() return (D and tonumber(D.now)) or 0 end
local function client() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local ORDER_NORMAL, PRIO_PLAYER_ONLY_NO_LIMIT, PRIO_TARGET_FIRST, FIRE_BITS = 0, 8, 9, 7   -- (sv_coop.lua's, sv_allies.lua's)
local STEP = { route = "Go", orbit = "Orbit", final = "Final", roll = "Roll", taxi = "Taxi", stop = "Stop" }
local ERR = function(r) return tostring(SV_ERR and SV_ERR[r] or r) end

---------------------------------------------------------------------------------------------------- whose unit
-- unit -> "charlene" | "escort" | "cargo" | "zfa" (a carrier's flight: its pose unit or a launcher arm's)
local KIND, CARGO_I, ZFA_I = {}, {}, {}
local function mapUnits()
    local c, k = ec(), cc()
    KIND[c.unit] = "charlene"
    for _, e in ipairs(c.escorts or {}) do KIND[e.unit] = "escort" end
    for i, u in ipairs(k.units or {}) do KIND[u], CARGO_I[u] = "cargo", i end
    for i, u in ipairs(k.pose_units or {}) do KIND[u], ZFA_I[u] = "zfa", i end
    for i, arms in ipairs(k.launchers or {}) do
        for _, arm in ipairs(arms) do if type(arm.unit) == "string" then KIND[arm.unit], ZFA_I[arm.unit] = "zfa", i end end
    end
end
mapUnits()
-- every one of them an ally (sv_core.lua logPlane: no kill credit, no enemy skill; sv_coop.lua allyUnit: their copies'
-- hits aren't a joiner's): the escorts and the ZFA-44s as the STORE's allied aircraft ("air": ALLY.run.planes, scaled as
-- MOONCHILD, repaired between rounds, their kills the allies'), CHARLENE and the ships on their own
for u, kd in pairs(KIND) do ALLY.unit[u] = (kd == "escort" or kd == "zfa") and "air" or kd end
function ESC.kindOf(unit) return unit and KIND[unit] or nil end

---------------------------------------------------------------------------------------------------- planes and objects
-- each of these units' planes as logPlane saw them: ESC.planes[unit] = { { obj, addr, name, at }, ... }; the live one
local function entryLive(e)                              -- (its name read again at most every 2 s: an address reused)
    if liveAddr(e.obj) ~= e.addr then return false end
    local c = os.clock()
    if c < (e.nameAt or 0) then return true end
    e.nameAt = c + 2
    return nameOf(e.obj) == e.name
end
local function hp(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end
local function planesOf(unit, since)
    local out = {}
    local l = ESC.planes[unit]
    if not l then return out end
    for i = #l, 1, -1 do
        local e = l[i]
        if not entryLive(e) then table.remove(l, i)
        elseif not since or (e.at or 0) >= since then out[#out + 1] = e end
    end
    return out
end
local function planeOf(unit)
    local l = planesOf(unit)
    for _, e in ipairs(l) do if (hp(e.obj) or 1) > 0 then return e.obj end end
    return l[1] and l[1].obj or nil
end
local function readPlane(o)
    local ok, r = pcall(function()
        local l, v, ro = o:K2_GetActorLocation(), o:GetVelocity(), o:K2_GetActorRotation()
        return { at = { X = l.X, Y = l.Y, Z = l.Z }, kmh = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) * 0.036,
                 pitch = ro.Pitch, roll = ro.Roll, hdg = (ro.Yaw + 90) % 360 }
    end)
    return ok and r or nil
end
local function locOf(o)
    local ok, l = pcall(function() local v = o:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    return ok and l or nil
end
local function d2(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) / 100 end          -- (metres)
local function d3(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) / 100 end
local function bearing(from, to) return math.deg(math.atan(to.X - from.X, -(to.Y - from.Y))) % 360 end   -- (compass)
local function angOff(a, b) return math.abs(((a - b + 540) % 360) - 180) end
local function pt(g) return { X = g[1], Y = g[2], Z = g[3] or 0 } end
-- an object switched off without a kill (no pay, no explosion): no box, no lock-on, invincible, inactive, hidden, no
-- collision, no tick (sv_rounds.lua takeDown's "off")
local function offObj(o)
    if not liveObj(o) then return false end
    for f, v in pairs({ bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }) do
        pcall(function() o[f] = v end)
    end
    pcall(function() o:SetActive(false, false, false) end)
    pcall(function() o:SetActorHiddenInGame(true) end)
    pcall(function() o:SetActorEnableCollision(false) end)
    pcall(function() o:SetActorTickEnabled(false) end)
    return true
end

-- a carrier ship's place: its hull (recorded as its unit spawned, ESC.hulls) or its spot; nil when it isn't up here
local function shipAt(i)
    local u = (cc().units or {})[i]
    local h = u and ESC.hulls[u]
    if h and liveAddr(h.obj) == h.addr then
        local l = locOf(h.obj)
        if l then return l end
    end
    local up = false
    if client() then up = ESC.host ~= nil and (tonumber(ESC.host.carriers) or 0) > 0
    else up = ESC.R ~= nil and ESC.R.D == D and ESC.R.carriers[i] ~= nil end
    local sp = up and (cc().spots or {})[i]
    return sp and { X = sp[1], Y = sp[2], Z = 0 } or nil
end
-- (logPlane, below) a plane of no unit, of a carrier's ship or of one of its flights, within capture_km of a carrier up
-- here: that ship's flight's unit (the host's launched arm, else its first arm's; the pose unit for a pose flight)
local function attribute(o, unit)
    local kd = unit and KIND[unit]
    if unit and kd ~= "cargo" and kd ~= "zfa" then return nil end
    if kd == "zfa" then return nil end                        -- (already a flight's: the pose spawn, a launch named)
    local at = locOf(o)
    if not at then return nil end
    local best, bd = nil, nil
    for i = 1, #(cc().units or {}) do
        local p = shipAt(i)
        if p then
            local d = d2(at, p) / 1000
            if d <= num(cc().capture_km, 4) and (not bd or d < bd) then best, bd = i, d end
        end
    end
    if not best then return nil end
    local C = ESC.R and ESC.R.D == D and ESC.R.carriers[best]
    if C and C.flight then return C.flight.unit end
    local arms = (cc().launchers or {})[best]
    return (arms and arms[1] and arms[1].unit) or (cc().pose_units or {})[best]
end
function ESC.capture(o, unit)
    local a = addrOf(o)
    if not (a and unit and KIND[unit]) then return end
    local l = ESC.planes[unit] or {}
    ESC.planes[unit] = l
    if #l >= 24 then table.remove(l, 1) end
    l[#l + 1] = { obj = o, addr = a, name = nameOf(o), at = now0() }
    if KIND[unit] == "zfa" and #ESC.dressQ < 32 then ESC.dressQ[#ESC.dressQ + 1] = { obj = o, addr = a, unit = unit } end
end
-- (wrapped before sv_coop.lua wraps it: co-op's ids go by the plane's own unit) every plane of these units recorded here;
-- a carrier's launched plane comes with no unit (its launcher spawns it) or its ship's: logged as its flight's
do
    local rawLog = logPlane
    logPlane = function(o, unit, k)
        local u2 = unit
        if next(ESC.hulls) ~= nil or (ESC.R and next(ESC.R.carriers)) or (ESC.host and (tonumber(ESC.host.carriers) or 0) > 0) then
            local okA, a = pcall(attribute, o, unit)
            if okA and a then
                u2 = a
                if not ESC.attribSaid then
                    ESC.attribSaid = true
                    log(string.format("carrier: a plane of %s near a carrier ship taken as its ZFA-44 flight's (%s)", tostring(unit or "no unit"), a))
                end
            end
        end
        rawLog(o, u2, k)
        if u2 and KIND[u2] and valid(o) and inSurvival(o) then
            local okC, err = pcall(ESC.capture, o, u2)
            if not okC then logOnce("escort capture", "escort: plane record error " .. tostring(err)) end
        end
    end
end
-- the carriers' ships' objects as their units spawn (any game: the host's and a joiner's copies, sv_coop.lua sets
-- spawningUnit too): the hull found in the tick (record only here: this runs on the constructing thread)
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    if u and CARGO_I[u] and #ESC.newObjs < 64 then ESC.newObjs[#ESC.newObjs + 1] = { obj = o, unit = u } end
end)
local function hullsTick()
    if #ESC.newObjs == 0 then return end
    local q = ESC.newObjs
    ESC.newObjs = {}
    for _, e in ipairs(q) do
        local a = liveAddr(e.obj)
        if a then
            local n = nameOf(e.obj)
            ESC.shipObjs = ESC.shipObjs or {}
            local l = ESC.shipObjs[e.unit] or {}
            ESC.shipObjs[e.unit] = l
            if #l < 32 then l[#l + 1] = { obj = e.obj, addr = a, name = n } end
            local h = ESC.hulls[e.unit]
            if n:find("ctslf", 1, true) and not n:find("cntus", 1, true) and not (h and liveAddr(h.obj) == h.addr) then
                ESC.hulls[e.unit] = { obj = e.obj, addr = a, name = n }
                log(string.format("carrier: %s's hull %s", e.unit, n:match("([^%.:]+)$") or n))
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- the runway
local function frame()
    local g = ec().geo
    local dx, dy = g.east[1] - g.west[1], g.east[2] - g.west[2]
    local n = math.sqrt(dx * dx + dy * dy)
    return { wx = g.west[1], wy = g.west[2], ux = dx / n, uy = dy / n }
end
-- metres along runway 07 from its west threshold (t) and to its right, south (s)
local function rw(at)
    local F = frame()
    local x, y = at.X - F.wx, at.Y - F.wy
    return (x * F.ux + y * F.uy) / 100, (x * -F.uy + y * F.ux) / 100
end
local function rwPoint(t, s)
    local F = frame()
    return { X = F.wx + (F.ux * t - F.uy * s) * 100, Y = F.wy + (F.uy * t + F.ux * s) * 100, Z = num(ec().geo.runway_z, 750) }
end
ESC.rw, ESC.rwPoint = rw, rwPoint

---------------------------------------------------------------------------------------------------- events
local function fire(ev, why)
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    if r ~= 1 then log(string.format("escort: %s NOT fired (%s): %s", ev, tostring(why or ""), ERR(r))) end
    return r == 1, r
end
local function airfield(close, why)
    local ev = close and "RE_SV_AirfieldClose" or "RE_SV_AirfieldOpen"
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    log(string.format("escort: landing %s for the players (%s): %s %s", close and "closed" or "open again", why, ev,
        r == 1 and "fired" or ("NOT fired: " .. ERR(r))))
    return r == 1
end
-- every plane of flight `unit` (an enemy's, the core's `planes`) onto target with priority prio; how many took it, of how many
local function orderPlanes(unit, target, prio)
    local n, total = 0, 0
    for _, p in ipairs(planes or {}) do
        if p.unit == unit and not p.down and liveAddr(p.obj) then
            total = total + 1
            if pcall(function() p.obj:EngagementOrderOverride(ORDER_NORMAL, target, prio, 0, false, FIRE_BITS, false) end) then n = n + 1 end
        end
    end
    return n, total
end
local function playerPawn()
    if not liveObj(survivalPC) then return nil end
    local ok, p = pcall(function() return survivalPC.Pawn end)
    return (ok and p and liveAddr(p)) and p or nil
end

---------------------------------------------------------------------------------------------------- the operation
-- S: { test, at, t (the world's time running), last, state ("route", "landing", "done"), ac = { aircraft }, attackers =
-- { unit -> { at, again } }, decided, seen, reinf = { n, at, units }, closed, won, lost }; an aircraft A: { name, unit, rec,
-- escort (its CFG entry, nil: CHARLENE), st ("spawn", "route", "orbit", "inbound", "final", "roll", "taxi", "stop", "landed",
-- "lost"), since (S.t at its step), r (its last read), how (landed: "stopped" / "timeout") }
local function newOp(now, test)
    local c = ec()
    local S = { test = test, at = now, t = 0, last = now, state = "spawn", ac = {}, attackers = {}, decided = {}, seen = {},
                reinf = { n = 0, at = now + num(c.reinforce and c.reinforce.every_s, 40), units = {} }, released = 0,
                lastRelease = -1e9, D = D }
    S.ac[1] = { name = c.name, unit = c.unit, rec = c.rec, st = "spawn", since = 0, her = true }
    if not test then
        for _, e in ipairs(c.escorts or {}) do
            S.ac[#S.ac + 1] = { name = e.name, unit = e.unit, rec = e.rec, st = "spawn", since = 0, escort = e }
        end
    end
    return S
end
local function her(S) return S.ac[1] end
local function aliveOf(u)
    local ok, n = pcall(SV_UnitAlive, u)
    return (ok and type(n) == "number") and n or -5
end
-- none of it up: 0 alive, not on the spawner's list (-7) or no such unit (-2); never an error (-1 / -5 / -6: not ready)
local function noneUp(n) return n == 0 or n == -7 or n == -2 end
local function heldNow()                               -- (the world frozen: you down at the airfield, nobody else flying)
    local okA, on = pcall(playerOnAirfield)
    if not (okA and on) then return false end
    local okO, n = pcall(othersFlying)
    return okO and n == 0
end
local function where(A)
    local r = A.r
    if not r then return "not read" end
    local t, s = rw(r.at)
    local g = ec().geo
    return string.format("t %.0f m, s %.0f m, %.0f m up, %.0f km/h, heading %03d, %.1f km from the airfield", t, s,
        (r.at.Z - num(g.runway_z, 750)) / 100, r.kmh, math.floor(r.hdg + 0.5), d2(r.at, AIRFIELD) / 1000)
end
local function goStep(S, A, st, why)
    local ev = A.rec .. STEP[st]
    local ok = fire(ev, A.name)
    A.st, A.since = st, S.t
    log(string.format("escort: %s %s (%s): %s %s; %s", A.name, st, tostring(why), ev, ok and "fired" or "NOT fired", where(A)))
    return ok
end
local function gear(A, o)
    if A.gear then return end
    A.gear = true
    local ok, err = pcall(function() o:EnableLandingGear(true, 0) end)
    -- (the contract's stock way too, when the build has it: <rec>GearDown, LiveEnableLandingGear true)
    local r = type(SV_Event) == "function" and SV_Event(A.rec .. "GearDown") or -5
    log(string.format("escort: %s gear down: EnableLandingGear(true, 0) %s; %s %s", A.name, ok and "done" or ("failed: " .. tostring(err)),
        A.rec .. "GearDown", r == 1 and "fired" or ("not fired (" .. ERR(r) .. ")")))
end
local function spawnAc(S, A, pose)
    if type(SV_SetLevel) == "function" and ALLY.level then
        local okL, L = pcall(ALLY.level, nil)
        if okL and L then pcall(SV_SetLevel, A.unit, L.ai * 100) end
    end
    ESC.planes[A.unit] = {}                               -- (a new spawn: the unit's planes before it are another flight's)
    spawningUnit, spawningIdx = A.unit, nil
    local okS, r = pcall(SV_Spawn, A.unit, pose.x, pose.y, pose.z, pose.yaw)
    spawningUnit = nil
    if not okS then r = -5; log("escort: SV_Spawn error " .. tostring(r)) end
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, A.unit, r) end
    A.spawnAt, A.goAt = S.t, S.t + num(ec().start.go_delay_s, 1)
    if type(r) == "number" and r > 0 then A.st = "route" end
    log(string.format("escort: %s (%s) spawned at (%.1f, %.1f) km, %.1f km up, yaw %.0f: %s", A.name, A.unit, pose.x / 100000,
        pose.y / 100000, pose.z / 100000, pose.yaw, (type(r) == "number" and r > 0) and (r .. " aircraft") or ("NOT spawned (" .. ERR(r) .. ")")))
    return type(r) == "number" and r > 0, r
end
local function startPose(side, back)
    local st = ec().start
    local h = math.rad(num(st.heading, 55))
    local fx, fy, rx, ry = math.sin(h), -math.cos(h), math.cos(h), math.sin(h)
    local sm, bm = num(st.side_m, 250) * 100 * side, num(st.back_m, 250) * 100 * back
    return { x = st.x + rx * sm - fx * bm, y = st.y + ry * sm - fy * bm, z = st.z, yaw = num(st.heading, 55) - 90 }
end

-- the enemy flights after her: chosen, ordered onto her, again now and then, let go
local function release(S, why)
    local pawn = playerPawn()
    for u in pairs(S.attackers) do
        local n = 0
        if D and D.up and D.up[u] then
            n = pawn and orderPlanes(u, pawn, PRIO_PLAYER_ONLY_NO_LIMIT) or 0
            if n == 0 and poolIndex(u) and type(SV_Event) == "function" then SV_Event(string.format("RE_SV_FlightOrders_%02d", poolIndex(u))) end
        end
        log(string.format("escort: %s off CHARLENE (%s): %s", u, why, n > 0 and (n .. " planes back on you") or "its own orders again"))
    end
    S.attackers = {}
end
local function attackOk(u)
    if not poolIndex(u) or (BOMBER_UNIT and BOMBER_UNIT[u]) or (PROBE_OF and PROBE_OF[u]) then return false end
    if (D.aceSquad and D.aceSquad[u]) or D.jammerUnit == u or (D.jammer and D.jammer.unit == u) then return false end
    if D.escortUnits and D.escortUnits[u] then return false end
    if WOLF and WOLF.holding and WOLF.holding(u) then return false end
    return true
end
local function attackTick(S, now, o)
    local a = ec().attack or {}
    if not (a.enabled and D and D.up) then return end
    if now < (S.attackAt or 0) then return end
    S.attackAt = now + 1
    for u in pairs(S.seen) do if not D.up[u] then S.seen[u], S.decided[u] = nil, nil end end
    local n = 0
    for u in pairs(S.attackers) do
        if not D.up[u] then S.attackers[u] = nil else n = n + 1 end
    end
    local units = {}
    for u in pairs(D.up) do units[#units + 1] = u end
    table.sort(units)
    for _, u in ipairs(units) do
        S.seen[u] = S.seen[u] or now
        if S.decided[u] == nil and now - S.seen[u] >= num(a.after_s, 4) then
            local want = attackOk(u) and n < num(a.max, 4) and (S.reinf.units[u] or math.random() < num(a.share, 0.6))
            S.decided[u] = want and true or false
            if want then
                local k, total = orderPlanes(u, o, PRIO_TARGET_FIRST)
                if k > 0 then
                    S.attackers[u] = { at = now, again = now + num(a.again_s, 10) }
                    n = n + 1
                    log(string.format("escort: %s sent after CHARLENE (%d of %d planes, Normal / TargetFirst onto her)", u, k, total))
                end
            end
        end
    end
    for u, e in pairs(S.attackers) do
        if now >= e.again then e.again = now + num(a.again_s, 10); orderPlanes(u, o, PRIO_TARGET_FIRST) end
    end
end
-- a point ahead of her (km along her heading, within side_km of it), inside the combat zone; facing her
local function aheadOf(S, km, sideKm)
    local A = her(S)
    local r = A.r
    if not r then return nil end
    local h = math.rad(r.hdg)
    local fx, fy, rx, ry = math.sin(h), -math.cos(h), math.cos(h), math.sin(h)
    local side = (math.random() * 2 - 1) * sideKm
    local x, y = r.at.X + (fx * km + rx * side) * 100000, r.at.Y + (fy * km + ry * side) * 100000
    local m = ZONE.HALF - 300000
    x, y = math.max(ZONE.X - m, math.min(ZONE.X + m, x)), math.max(ZONE.Y - m, math.min(ZONE.Y + m, y))
    local yaw = (bearing({ X = x, Y = y }, r.at) - 90) % 360
    return { x = x, y = y, yaw = yaw, d = math.sqrt((x - AIRFIELD.X) ^ 2 + (y - AIRFIELD.Y) ^ 2) / 100000,
             b = math.deg(math.atan(y - AIRFIELD.Y, x - AIRFIELD.X)) % 360 }
end
-- (spawnFlight asks DIR.spawnAt, wrapped below) a round flight's spawn point ahead of her while she flies her route
function ESC.spawnAt(unit)
    local S, c = ESC.S, ec()
    local ah = c.ahead or {}
    if not (S and not S.test and S.D == D and S.state == "route" and ah.enabled and her(S).r) then return nil end
    if math.random() >= num(ah.share, 0.5) then return nil end
    local p = aheadOf(S, num(ah.km, 15), num(ah.side_km, 6))
    if p then p.centre = "ahead of " .. c.name end
    return p
end
local function reinforceTick(S, now)
    local rf = ec().reinforce or {}
    if not (rf.enabled and D and D.up) or now < S.reinf.at or S.reinf.n >= num(rf.max, 8) then return end
    S.reinf.at = now + num(rf.every_s, 40)
    local up = 0
    for _, p in ipairs(planes or {}) do if not p.down then up = up + 1 end end
    if up >= num(rf.below, 6) then return end
    local size = math.floor(num(rf.size, 2))
    local opts = {}
    for _, u in ipairs(CFG.pool or {}) do
        if flightSize(u) == size and not D.up[u] and not (D.taken and D.taken[u]) and not (PROBE_OF and PROBE_OF[u])
            and poolIndex(u) and not (ROLE and ROLE.sitsOut and ROLE.sitsOut(u)) and noneUp(aliveOf(u)) then opts[#opts + 1] = u end
    end
    if #opts == 0 then
        if not S.reinfNoneSaid then S.reinfNoneSaid = true; log(string.format("escort: no free %d-ship to send after CHARLENE", size)) end
        return
    end
    local u = opts[math.random(#opts)]
    local p = aheadOf(S, num(rf.ahead_km, 14), num(rf.side_km, 6))
    if not p then return end
    local alt = rf.alt_m or { 2500, 4000 }
    local lo, hi = num(alt[1], 2500), num(alt[2] or alt[1], 4000)
    local pose = { x = p.x, y = p.y, z = (lo + math.random() * math.max(0, hi - lo)) * 100, yaw = p.yaw, why = "ahead of CHARLENE" }
    local r = spawnFlight(u, nil, pose)
    if r > 0 then
        S.reinf.n, S.reinf.units[u] = S.reinf.n + 1, true
        if D.taken then D.taken[u] = true end
        for i = #(D.spare or {}), 1, -1 do if D.spare[i] == u then table.remove(D.spare, i) end end
        log(string.format("escort: more enemies: %s (%d aircraft) %.1f km ahead of CHARLENE (%d of %d this round; %d enemy aircraft were up)",
            u, r, num(rf.ahead_km, 14), S.reinf.n, num(rf.max, 8), up))
    end
end
-- the escorts' planes onto the enemies nearest her
local function guardTick(S, now)
    local g = ec().guard or {}
    if not g.enabled or now < (S.guardAt or 0) then return end
    S.guardAt = now + num(g.every_s, 4)
    local at = her(S).r and her(S).r.at
    if not at then return end
    local foes = {}
    for _, p in ipairs(planes or {}) do
        if not p.down and p.at and liveAddr(p.obj) then
            local d = d2(p.at, at) / 1000
            if d <= num(g.km, 8) then foes[#foes + 1] = { obj = p.obj, d = d, name = p.name } end
        end
    end
    table.sort(foes, function(a, b) return a.d < b.d end)
    local k, said = 0, {}
    for _, A in ipairs(S.ac) do
        if A.escort and (A.st == "route" or A.st == "orbit") and #foes > 0 then
            k = k + 1
            local f = foes[(k - 1) % #foes + 1]
            local n = 0
            for _, e in ipairs(planesOf(A.unit)) do
                if (hp(e.obj) or 1) > 0 and pcall(function() e.obj:EngagementOrderOverride(ORDER_NORMAL, f.obj, PRIO_TARGET_FIRST, 0, false, FIRE_BITS, false) end) then
                    n = n + 1
                end
            end
            if n > 0 and A.guarding ~= f.name then A.guarding = f.name; said[#said + 1] = string.format("%s onto %s (%.1f km from her)", A.name, f.name, f.d) end
        end
    end
    if #said > 0 then log("escort: guarding CHARLENE: " .. table.concat(said, ", ")) end
end

---------------------------------------------------------------------------------------------------- the landing
local function stopSpot(A)
    if A.escort then return rwPoint(num(A.escort.stop_t, 1200), num(A.escort.stop_s, 60)) end
    return pt(ec().geo.hold)
end
local function landed(S, A, how)
    A.st, A.how, A.since = "landed", how, S.t
    local o = planeOf(A.unit)
    local flying = A.r and A.r.kmh > 80
    if how == "timeout" and flying then                     -- (counted as landed: not left circling)
        if COOP and COOP.removeNow then pcall(COOP.removeNow, A.unit) end
        for _, e in ipairs(planesOf(A.unit)) do offObj(e.obj) end
    elseif o and ec().landing.invincible_on_ground then
        pcall(function() o:SetIsInvincible(true) end)
    end
    log(string.format("escort: %s landed (%s%s); %s", A.name, how == "timeout" and "the safety timeout: counted as landed" or "stopped",
        (how == "timeout" and flying) and ", taken off: it was still flying" or "", where(A)))
    if A.her and not S.test then
        local left = 0
        for _, B in ipairs(S.ac) do if B.escort and B.st ~= "landed" and B.st ~= "lost" then left = left + 1 end end
        local t = ec().text
        hudCallout(t.landed, string.format(t.landed_sub, left))
    end
end
-- one aircraft's step: its plane read, lost, the next step by distance, the timeouts
local function stepAc(S, A, now)
    if A.st == "landed" or A.st == "lost" or A.st == "spawn" then
        if A.st == "spawn" and A.spawnAt and S.t - A.spawnAt > 15 then
            A.st = "lost"
            log(string.format("escort: %s never came up (its spawn refused): out", A.name))
        end
        return
    end
    local L = ec().landing
    local o = planeOf(A.unit)
    if not o then
        if A.seen and noneUp(aliveOf(A.unit)) then A.st, A.lostAt = "lost", S.t
        elseif not A.seen and S.t - (A.spawnAt or S.t) > 15 then A.st, A.lostAt = "lost", S.t end
        if A.st == "lost" then log(string.format("escort: %s lost (%s)", A.name, A.seen and "its plane is gone" or "its plane never appeared")) end
        return
    end
    if not A.seen then
        A.seen = true
        if A.her and S.test then pcall(function() o:SetIsInvincible(true) end) end   -- (the test: nothing may end it)
        if A.her and not S.test then
            local x = num(ec().health_x, 1)
            local okH, h0, h1 = pcall(scaleHealth, o, x)
            log(string.format("escort: %s up: her health x%.2f (%s -> %s)", A.name, x, okH and tostring(h0) or "?", okH and tostring(h1) or "?"))
        end
    end
    local h = hp(o)
    if h and h <= 0 then
        A.st, A.lostAt = "lost", S.t
        log(string.format("escort: %s shot down (%s)", A.name, where(A)))
        return
    end
    local r = readPlane(o)
    if not r then return end
    local prevIaf = A.iafD
    A.r = r
    local g = ec().geo
    local iaf, td, re = pt(g.iaf), pt(g.touchdown), pt(g.roll_end)
    A.iafD = d2(r.at, iaf)
    local t = rw(r.at)
    local above = (r.at.Z - num(g.runway_z, 750)) / 100
    if A.st == "route" and A.goAt and S.t >= A.goAt and not A.goFired then
        A.goFired = true
        if S.test then goStep(S, A, "final", "the landing test T0: her final from the approach fix"); gear(A, o)
        else
            local ok = fire(A.rec .. "Go", A.name)
            log(string.format("escort: %s route: %s %s; %s", A.name, A.rec .. "Go", ok and "fired" or "NOT fired", where(A)))
        end
        return
    end
    if A.st == "route" and A.her and A.goFired then
        local passed = prevIaf and A.iafD > prevIaf + 1 and A.iafD <= 4000
        if A.iafD <= num(L.final_at_m, 2000) or passed or S.t - A.since >= num(L.route_max_s, 900) then
            goStep(S, A, "final", A.iafD <= num(L.final_at_m, 2000) and string.format("%.0f m from the approach fix", A.iafD)
                or (passed and "past the approach fix" or string.format("%d s on her route", num(L.route_max_s, 900))))
            gear(A, o)
            A.finalT = S.t
        end
    elseif A.st == "inbound" then
        local ahead = angOff(bearing(r.at, iaf), r.hdg) <= num(L.ahead_deg, 60) and A.iafD > 1500
        if ahead or S.t - A.since >= num(L.inbound_max_s, 120) then
            goStep(S, A, "final", ahead and string.format("the approach fix ahead, %.1f km", A.iafD / 1000)
                or string.format("%d s waiting for the approach fix ahead", num(L.inbound_max_s, 120)))
            gear(A, o)
            A.finalT = S.t
        end
    elseif A.st == "final" then
        local km = num(L.avoid_off_km, 0)
        if km > 0 and not A.avoidOff and d3(r.at, td) <= km * 1000 then
            A.avoidOff = true
            local okV, err = pcall(function() o:EnableAvoidObstacle(false) end)
            log(string.format("escort: %s %.1f km from the touchdown: obstacle avoidance off (%s)", A.name, d3(r.at, td) / 1000,
                okV and "EnableAvoidObstacle(false)" or ("failed: " .. tostring(err))))
        end
        if d3(r.at, td) <= num(L.roll_at_m, 350) or (t >= rw(td) - 150 and above <= 20 and t <= rw(re)) then
            goStep(S, A, "roll", string.format("%.0f m from the touchdown point, %.0f m up", d3(r.at, td), above))
            gear(A, o)
            if L.invincible_on_ground then pcall(function() o:SetIsInvincible(true) end) end
            A.touchT = A.touchT or t
        end
    elseif A.st == "roll" then
        if d2(r.at, re) <= num(L.taxi_at_m, 150) or (r.kmh <= num(L.taxi_kmh, 70) and t >= rw(re) - 300)
            or S.t - A.since >= num(L.roll_max_s, 90) then
            goStep(S, A, "taxi", string.format("%.0f m from the rollout's end at %.0f km/h", d2(r.at, re), r.kmh))
        end
    elseif A.st == "taxi" then
        local slow = r.kmh <= 3
        A.slowSince = slow and (A.slowSince or S.t) or nil
        if d2(r.at, stopSpot(A)) <= num(L.stop_at_m, 60) or S.t - A.since >= num(L.taxi_max_s, 90)
            or (S.t - A.since >= 10 and A.slowSince and S.t - A.slowSince >= 3) then
            goStep(S, A, "stop", string.format("%.0f m from its parking spot", d2(r.at, stopSpot(A))))
        end
    elseif A.st == "stop" then
        local slow = r.kmh <= num(L.landed_kmh, 5)
        A.slowSince = slow and (A.slowSince or S.t) or nil
        if (A.slowSince and S.t - A.slowSince >= num(L.landed_hold_s, 2)) or S.t - A.since >= num(L.stop_max_s, 20) then
            landed(S, A, "stopped")
        end
    end
    if A.finalT and A.st ~= "landed" and A.st ~= "lost" and S.t - A.finalT >= num(L.land_timeout_s, 360) then
        landed(S, A, "timeout")
    end
end
-- the escorts: their orbit once she's on final, then one at a time once the runway's clear
local function escortsTick(S)
    local A = her(S)
    if not S.orbitFired and (A.st ~= "route" and A.st ~= "spawn") then
        S.orbitFired = true
        for _, B in ipairs(S.ac) do if B.escort and B.st == "route" then goStep(S, B, "orbit", "CHARLENE on final") end end
    end
    if not S.orbitFired then return end
    local L = ec().landing
    local busy = false
    for _, B in ipairs(S.ac) do
        if B.st == "route" and B.her or B.st == "final" or B.st == "roll" or B.st == "inbound" then busy = true end
    end
    if busy or S.t - S.lastRelease < num(L.release_gap_s, 45) then return end
    for _, B in ipairs(S.ac) do
        if B.escort and (B.st == "orbit" or B.st == "route") then
            B.st, B.since = "inbound", S.t
            S.released, S.lastRelease = S.released + 1, S.t
            log(string.format("escort: %s released for its landing (%d of %d; the runway's clear); %s", B.name, S.released, #S.ac - 1, where(B)))
            return
        end
    end
end
local function counts(S)
    local landedN, lostN, total = 0, 0, #S.ac
    for _, A in ipairs(S.ac) do
        if A.st == "landed" then landedN = landedN + 1 elseif A.st == "lost" then lostN = lostN + 1 end
    end
    return landedN, lostN, total
end
-- (the test's every log_s) where she is against the runway, how high and fast, her gear
local function gearShown(o)
    local ok, v = pcall(function() local m = o.LandingGearOnMeshComponent; return m ~= nil and m:IsVisible() end)
    if ok and type(v) == "boolean" then return v and "down" or "up" end
    return "?"
end
local function testLog(S, now)
    local tc = ec().test or {}
    if now < (S.logAt or 0) then return end
    S.logAt = now + num(tc.log_s, 0.5)
    local A = her(S)
    local o = planeOf(A.unit)
    if not (o and A.r) then return end
    local t, s = rw(A.r.at)
    log(string.format("escort: T0 +%.1f s: %s %s: t %.0f m, s %.1f m, %.1f m over the runway (z %.0f cm), %.0f km/h, pitch %.1f, roll %.1f, gear %s%s",
        S.t, A.name, A.st, t, s, (A.r.at.Z - num(ec().geo.runway_z, 750)) / 100, A.r.at.Z, A.r.kmh, A.r.pitch, A.r.roll,
        gearShown(o), A.avoidOff and ", avoidance off" or ""))
    if A.touchT and not S.touchSaid then
        S.touchSaid = true
        log(string.format("escort: T0: her rollout began %.0f m past runway 07's west threshold (the test's pass: 150-600 m)", A.touchT))
    end
end

-- the aircraft of an operation switched off and their units taken off the spawner's list (2 s on: ESC.tick)
local function takeOff(S, why)
    local c = ec()
    for _, A in ipairs(S.ac) do
        if COOP and COOP.removeNow then pcall(COOP.removeNow, A.unit) end   -- (a joiner's copies down first, unpaid)
        if c.remove_records then fire(A.rec .. "Remove", A.name) end
        local n = 0
        for _, e in ipairs(planesOf(A.unit)) do if offObj(e.obj) then n = n + 1 end end
        ESC.recycleQ[#ESC.recycleQ + 1] = { unit = A.unit, at = os.clock() + 2, why = why }
        log(string.format("escort: %s taken off (%s): %d planes switched off", A.name, why, n))
    end
end
local function reopen(S, why)
    if S.closed then
        S.closed = false
        if not (AF and (AF.closed or AF.down)) and not RUN.captured then airfield(false, why) end
    end
    S.closePending = false
end
-- the operation's end: lost (her death) or won (everyone left landed)
local function finish(S, now, won, why)
    S.state, S.won, S.lost = "done", won, not won
    release(S, won and "the escort's over" or "CHARLENE is down")
    reopen(S, won and "everyone's down" or "the escort failed")
    local c, t = ec(), ec().text
    local landedN, lostN, total = counts(S)
    local secs = S.t
    if S.special then S.special.state = "done" end
    if S.test then
        log(string.format("escort: T0 over (%s) after %.0f s: %s", why, secs, her(S).how or her(S).st))
        S.endAt = now + num(c.test and c.test.end_s, 30)
        return
    end
    if not won then
        LB.special("escort", false, secs)
        hudCallout(t.lost, t.lost_sub)
        log(string.format("escort: round %d, the escort FAILED: %s (%d of %d landed, %d lost, %.0f s in)", D.round, why, landedN, total, lostN, secs))
        return
    end
    local pay = math.floor(num(c.reward, 0) + num(c.reward_per_round, 0) * (D.round or 0))
    addCredits(pay, "the escort: CHARLENE and her escorts landed")
    LB.special("escort", true, secs)
    RUN.zfa = { unlocked = true, round = D.round }
    RUN.dirty = true
    hudCallout(t.won, string.format(t.won_sub, specialPay(pay)))
    -- her line (the big callout; the subtitle strip may take c.subtitle whole), cut at words to subtitle_chars a callout
    local line, parts, cur = tostring(c.subtitle or ""), {}, ""
    for w in line:gmatch("%S+") do
        if #cur > 0 and #cur + 1 + #w > num(c.subtitle_chars, 90) then parts[#parts + 1] = cur; cur = w
        else cur = (#cur > 0 and (cur .. " ") or "") .. w end
    end
    if #cur > 0 then parts[#parts + 1] = cur end
    for i = 1, math.min(#parts, 3) do hudCallout(c.name, parts[i]) end
    log(string.format("escort: round %d, the escort WON: %d of %d landed (%d lost), %.0f s; +%d zollars; CHARLENE: \"%s\"; the ZFA-44 carriers unlocked in the STORE",
        D.round, landedN, total, lostN, secs, pay, line))
end
-- every tick of the operation (the round's: SPC.kinds.escort.tick; the test's: ESC.tick)
function ESC.step(S, now)
    if S.state == "done" then return end
    local dt = math.max(0, math.min(1, now - (S.last or now)))
    S.last = now
    if not heldNow() then S.t = S.t + dt end
    local L = ec().landing
    local A = her(S)
    for _, B in ipairs(S.ac) do
        local okA, errA = pcall(stepAc, S, B, now)
        if not okA and not B.errSaid then B.errSaid = true; log("escort: " .. B.name .. "'s step error " .. tostring(errA)) end
    end
    if S.test then testLog(S, now) end
    if A.st == "lost" then return finish(S, now, false, "CHARLENE is down") end
    if not S.test then pcall(escortsTick, S) end
    if A.st == "final" and S.state == "route" then
        S.state = "landing"
        if S.special then S.special.state = "landing" end
        if not S.test then hudCallout(ec().text.final, ec().text.final_sub) end
        if L.close_airfield then S.closePending = true end
    end
    if S.closePending and not S.closed then
        local okA, on = pcall(playerOnAirfield)
        if not (okA and on) then
            S.closePending = false
            if not (AF and AF.closed) and not RUN.captured then S.closed = airfield(true, "CHARLENE's landing") end
        end
    end
    local o = planeOf(A.unit)
    if A.st == "route" or A.st == "final" then
        if o and not S.test then
            pcall(attackTick, S, now, o)
            pcall(reinforceTick, S, now)
            pcall(guardTick, S, now)
        end
    elseif next(S.attackers) then
        release(S, "CHARLENE is on the ground")
    end
    -- escorts shot down: said once each
    for _, B in ipairs(S.ac) do
        if B.escort and B.st == "lost" and not B.lostSaid then
            B.lostSaid = true
            local left = 0
            for _, C in ipairs(S.ac) do if C.escort and C.st ~= "lost" then left = left + 1 end end
            hudCallout(string.format(ec().text.escort_down, B.name), string.format(ec().text.escort_down_sub, left))
        end
    end
    local landedN, lostN, total = counts(S)
    if A.st == "landed" and landedN + lostN >= total then return finish(S, now, true, "everyone left landed") end
    if S.t >= num(L.max_s, 1500) then
        for _, B in ipairs(S.ac) do if B.st ~= "landed" and B.st ~= "lost" then landed(S, B, "timeout") end end
        return finish(S, now, true, string.format("%d s: everyone up counted as landed", num(L.max_s, 1500)))
    end
end

---------------------------------------------------------------------------------------------------- the special kind
local unitsAt, unitsOk = -1e9, nil
-- its units in the world data (SV_UnitAlive answers "no such unit", -2, for one that isn't): asked at most every 30 s
local function unitsThere()
    if unitsOk ~= nil and os.clock() - unitsAt < 30 then return unitsOk end
    if not nativeReady() then return false end
    local c, missing, unknown = ec(), {}, false
    local list = { c.unit }
    for _, e in ipairs(c.escorts or {}) do list[#list + 1] = e.unit end
    for _, u in ipairs(list) do
        local n = aliveOf(u)
        if n == -2 then missing[#missing + 1] = u elseif n < 0 and n ~= -7 then unknown = true end
    end
    if unknown and #missing == 0 then return false end      -- (not in Survival's level yet: asked again next time)
    unitsAt, unitsOk = os.clock(), #missing == 0
    if not unitsOk and not ESC.missingSaid then
        ESC.missingSaid = true
        log("escort: no ESCORT special in this build: its units aren't in the world data (" .. table.concat(missing, ", ") .. ")")
    end
    return unitsOk
end
function ESC.ready()
    local c = ec()
    if not (type(c) == "table" and c.enabled ~= false) then return false end
    if c.once ~= false and RUN.escort and RUN.escort.flown then return false end
    return unitsThere()
end
function ESC.spawn(now)
    if not nativeReady() then return false end
    local c = ec()
    local S = newOp(now, nil)
    S.special, S.round = D.special, D.round
    local ok, r = spawnAc(S, her(S), startPose(0, 0))
    if not ok then
        log(string.format("escort: round %d: CHARLENE can't come (%s): no escort this round", D.round, ERR(r)))
        return false
    end
    for _, A in ipairs(S.ac) do
        if A.escort then spawnAc(S, A, startPose(num(A.escort.side, 1), num(A.escort.back, 1))) end
    end
    S.state = "route"
    ESC.S = S
    RUN.escort = { flown = D.round }
    D.special.state, D.special.at = "route", now
    hudCallout(c.text.go, c.text.go_sub)
    log(string.format("escort: round %d, THE ESCORT: CHARLENE and %d escorts from (%.1f, %.1f) km to the airfield (%.1f km)", D.round,
        #S.ac - 1, c.start.x / 100000, c.start.y / 100000, d2({ X = c.start.x, Y = c.start.y }, AIRFIELD) / 1000))
    return true
end
function ESC.roundTick(now, s)
    local S = ESC.S
    if not (S and S.special == s and not S.test) then return end
    return ESC.step(S, now)
end
function ESC.busy(s)
    local S = ESC.S
    return S ~= nil and S.special == s and S.state ~= "done"
end
function ESC.over(now, s)
    local S = ESC.S
    if not (S and S.special == s) then return end
    if S.state ~= "done" then finish(S, now, false, "its round ended first") end
    takeOff(S, "its round over")
    ESC.S = nil
end
function ESC.holds(unit)
    local S = ESC.S
    return S ~= nil and unit ~= nil and S.state ~= "done" and S.attackers[unit] ~= nil
end
-- its NEXT row: her health, her distance, how many have landed
local function hpPct(S)
    local o = planeOf(her(S).unit)
    if not o then return nil end
    local okH, h, mh = pcall(function() return o.HealthInternal, o.MaxHealth end)
    if not (okH and type(h) == "number" and type(mh) == "number" and mh > 0) then return nil end
    return math.max(0, math.min(100, math.floor(h / (mh * 10) * 100 + 0.5)))
end
function ESC.row(s, t)
    local S = ESC.S
    if not (S and S.special == s) then return nil end
    local tx = ec().text
    local landedN, _, total = counts(S)
    if S.state == "done" then return string.format(tx.row_done, landedN, total) end
    local A = her(S)
    if A.st == "route" or A.st == "final" then
        return string.format(tx.row, hpPct(S) or 100, A.r and d2(A.r.at, AIRFIELD) / 1000 or 0, landedN, total)
    end
    return string.format(tx.row_landing, landedN, total)
end
if SPC and SPC.kinds then
    SPC.kinds.escort = {
        sub = function(t) return ec().text.sub end,
        ready = function() return ESC.ready() end,
        budget = function(budget) return math.max(2, math.floor(budget * num(ec().budget_x, 1) / 2 + 0.5) * 2) end,
        spawn = function(now) return ESC.spawn(now) end,
        tick = function(now, s) return ESC.roundTick(now, s) end,
        busy = function(s) return ESC.busy(s) end,
        over = function(now, s) return ESC.over(now, s) end,
        row = function(s, t) return ESC.row(s, t) end,
    }
end
-- (spawnFlight's pincer point first asked here: the round's flights ahead of her)
if type(DIR) == "table" and type(DIR.spawnAt) == "function" then
    local rawAt = DIR.spawnAt
    DIR.spawnAt = function(unit)
        local okE, p = pcall(ESC.spawnAt, unit)
        if okE and p then return p end
        return rawAt(unit)
    end
end

---------------------------------------------------------------------------------------------------- the carriers
function ESC.unlocked() return type(RUN.zfa) == "table" and RUN.zfa.unlocked == true end
local function run()
    if not (ESC.R and ESC.R.D == D) then ESC.R = { D = D, carriers = {} } end
    return ESC.R
end
function ESC.carriersUp()
    if client() then return math.floor(num(ESC.host and ESC.host.carriers, 0)) end
    local n = 0
    for _, C in pairs(run().carriers) do if C.state == "up" then n = n + 1 end end
    return n
end
local function carrierUnitsOk()
    local ok = false
    for _, u in ipairs(cc().units or {}) do if aliveOf(u) ~= -2 then ok = true end end
    return ok
end
-- a free ship: its index and unit (none of it up), or nil
local function freeShip()
    local R = run()
    for i, u in ipairs(cc().units or {}) do
        if not R.carriers[i] then
            local n = aliveOf(u)
            if n == 0 or n == -7 then return i, u end
        end
    end
    return nil
end
-- (sv_shop.lua offer) what the STORE's row says: { label, help, why }
function ESC.offer(borrowed)
    local c, t = cc(), cc().text
    local it = CFG.shop.items.ZfaCarrier or {}
    local up = ESC.carriersUp()
    local o = { label = borrowed and (it.row_label or it.label) or it.label }
    o.help = string.format(t.help, math.floor(num(c.service and c.service.rounds, 3)), up, math.floor(num(c.max_up, 2)))
    if borrowed and RUN.msg and RUN.msg.ZfaCarrier then o.help = RUN.msg.ZfaCarrier .. " " .. o.help end
    if not (c.enabled and CFG.allies.enabled) then o.why = "NOT AVAILABLE."
    elseif not ESC.unlocked() then o.why = t.locked
    elseif not client() and not carrierUnitsOk() then o.why = "NOT AVAILABLE."
    elseif up >= num(c.max_up, 2) then o.why = string.format(t.full, up)
    elseif not client() and not freeShip() then o.why = t.busy end
    return o
end
-- (sv_shop.lua offer) a STORE row the carrier shares while it has nothing to sell itself: the carrier's item, or nil
function ESC.rowItem(name)
    local c = cc()
    if not (c.enabled and name ~= nil and name == c.store_row and ESC.unlocked()) then return nil end
    if name == "Revive" and DOWN and DOWN.offer then
        local okD, r = pcall(DOWN.offer)
        if okD and type(r) == "table" and (r.price or r.slot) then return nil end   -- (someone to revive: the row's own)
    end
    return "ZfaCarrier"
end
-- (the host's or solo; sv_shop.lua shopBuy / shopBuildFor) one sent: true and the row's message, or false and why.
-- slot: a co-op joiner's who paid on their game (nil: this game's, or a host by migration's rebuild)
function ESC.buyCarrier(slot, price)
    local c, t = cc(), cc().text
    if client() then return false, "THE HOST SENDS IT." end
    if not ESC.unlocked() then return false, t.locked end
    if ESC.carriersUp() >= num(c.max_up, 2) then return false, string.format(t.full, ESC.carriersUp()) end
    local i, u = freeShip()
    if not i then return false, t.busy end
    spawningUnit = u
    local okS, r = pcall(SV_Spawn, u)
    spawningUnit = nil
    if not okS then r = -5 end
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, u, r) end
    if r <= 0 then
        log(string.format("carrier: %s (%s) NOT sent: %s", c.name, u, ERR(r)))
        return false, "COULD NOT SEND IT (" .. ERR(r) .. ")."
    end
    local now = now0()
    run().carriers[i] = { idx = i, unit = u, at = now, buyer = slot, price = price, served = 0, state = "up", armI = 0,
                          route = c.launch == "pose" and "pose" or "container", used = {},
                          nextLaunchAt = now + num(c.first_s, 20), name = string.format("%s %d", c.name, i) }
    RUN.dirty = true
    if not slot then hudCallout(string.format(t.on_station, c.name), string.format(t.on_station_sub, math.floor(num(c.first_s, 20)))) end
    log(string.format("carrier: %s %d (%s) on station%s: its ZFA-44s launch in %d s (%s)", c.name, i, u,
        slot and string.format(" for player %d", slot + 1) or "", math.floor(num(c.first_s, 20)), c.launch == "pose" and "by pose" or "from its container launchers"))
    return true, string.format("%s %d ON STATION", c.name, i)
end
-- the carriers up as the host's migration list has them: { "ZfaCarrier:<buyer slot or ->" }
function ESC.carrierList()
    local out = {}
    if client() then return out end
    for _, C in pairs(run().carriers) do if C.state == "up" then out[#out + 1] = C.buyer or false end end
    return out
end
local function hullPose(C)
    local h = ESC.hulls[C.unit]
    if h and liveAddr(h.obj) == h.addr then
        local ok, l, ro = pcall(function() return h.obj:K2_GetActorLocation(), h.obj:K2_GetActorRotation() end)
        if ok and l and ro then return { X = l.X, Y = l.Y, Z = l.Z }, ro.Yaw end
    end
    local sp = (cc().spots or {})[C.idx]
    if not sp then return nil end
    local at = { X = sp[1], Y = sp[2], Z = 0 }
    return at, (bearing(at, AIRFIELD) - 90) % 360
end
local function launch(C, now)
    local c = cc()
    local arms = (c.launchers or {})[C.idx] or {}
    if C.route == "container" and #arms > 0 then
        C.armI = C.armI % #arms + 1
        local arm = arms[C.armI]
        if C.used[arm.unit] and type(SV_Recycle) == "function" and aliveOf(arm.unit) >= 0 then
            crumb("carrier SV_Recycle " .. arm.unit)
            local okR, rr = pcall(SV_Recycle, arm.unit, 1)
            log(string.format("carrier: %s: %s launched before: taken off the spawner's list first (SV_Recycle %s)", C.name, arm.unit,
                okR and tostring(rr) or ("error " .. tostring(rr))))
        end
        C.used[arm.unit] = true
        local ok, r = fire(arm.record, C.name)
        if ok then
            C.flight = { unit = arm.unit, record = arm.record, at = now, route = "container" }
            C.launches = (C.launches or 0) + 1
            if C.launches == 1 then hudCallout(c.text.launch, string.format(c.text.launch_sub, C.name)) end
            log(string.format("carrier: %s launches its ZFA-44s: %s fired (container arm %d, %s)", C.name, arm.record, C.armI, arm.unit))
            return
        end
        C.route = "pose"
        log(string.format("carrier: %s: its launch record %s not fired (%s): launched by pose from now on", C.name, arm.record, ERR(r)))
    end
    local u = (c.pose_units or {})[C.idx]
    local at, yaw = hullPose(C)
    if not (u and at) then C.nextLaunchAt = now + 10; return end
    local y = math.rad(yaw)
    local ahead = num(c.pose and c.pose.ahead_m, 300) * 100
    local pose = { x = at.X + math.cos(y) * ahead, y = at.Y + math.sin(y) * ahead, z = math.max(at.Z, 0) + num(c.pose and c.pose.alt_m, 1100) * 100, yaw = yaw % 360 }
    if type(SV_SetLevel) == "function" and ALLY.level then
        local okL, L = pcall(ALLY.level, nil)
        if okL and L then pcall(SV_SetLevel, u, L.ai * 100) end
    end
    ESC.planes[u] = {}                                    -- (a new spawn: the unit's planes before it are another flight's)
    spawningUnit, spawningIdx = u, nil
    local okS, r = pcall(SV_Spawn, u, pose.x, pose.y, pose.z, pose.yaw)
    spawningUnit = nil
    if not okS then r = -5 end
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, u, r) end
    if r > 0 then
        C.flight = { unit = u, at = now, route = "pose", up = true }
        C.launches = (C.launches or 0) + 1
        if C.launches == 1 then hudCallout(c.text.launch, string.format(c.text.launch_sub, C.name)) end
        log(string.format("carrier: %s launches its ZFA-44s by pose: %s, %d aircraft %.0f m off its bow, %.0f m up", C.name, u, r,
            ahead / 100, pose.z / 100))
    else
        C.nextLaunchAt = now + 10
        log(string.format("carrier: %s: %s NOT spawned (%s); again in 10 s", C.name, u, ERR(r)))
    end
end
local function flightOff(F, why)
    if COOP and COOP.removeNow then pcall(COOP.removeNow, F.unit) end
    local n = 0
    for _, e in ipairs(planesOf(F.unit)) do if offObj(e.obj) then n = n + 1 end end
    ESC.recycleQ[#ESC.recycleQ + 1] = { unit = F.unit, at = os.clock() + 2, why = why }
    return n
end
local function carrierTick(C, now)
    local c, t = cc(), cc().text
    local R = run()
    if C.state == "leaving" then
        if os.clock() >= (C.removeAt or 0) + 2 then
            local rec = "no SV_Recycle in this runtime"
            if type(SV_Recycle) == "function" then
                crumb("carrier SV_Recycle " .. C.unit)
                local okR, r = pcall(SV_Recycle, C.unit, 1)
                rec = "SV_Recycle " .. (okR and tostring(r) or ("error " .. tostring(r)))
            end
            R.carriers[C.idx], RUN.dirty = nil, true
            log(string.format("carrier: %s gone (%s): off the spawner's list (%s); the STORE can call another", C.name, tostring(C.why), rec))
        end
        return
    end
    if now >= (C.checkAt or 0) then
        C.checkAt = now + 2
        if noneUp(aliveOf(C.unit)) and now - C.at > 5 then
            R.carriers[C.idx], RUN.dirty = nil, true
            hudCallout(string.format(t.sunk, C.name), t.sunk_sub)
            log(string.format("carrier: %s sunk %.0f s after it came (%d rounds served)%s", C.name, now - C.at, C.served,
                C.flight and ("; its flight " .. C.flight.unit .. " flies on") or ""))
            return
        end
    end
    -- its rounds of service (VOID WATCHER 1's): one counted as it clears with the ship up min_s of it
    local sv = c.service or {}
    local rounds = math.floor(num(sv.rounds, 3))
    if rounds > 0 and D then
        if D.state ~= "wait" then C.inRound = D.round
        elseif C.inRound == D.round and C.counted ~= D.round then
            C.counted = D.round
            if now - C.at >= num(sv.min_s, 60) then
                C.served = C.served + 1
                log(string.format("carrier: %s has served %d of its %d rounds (round %d clear)", C.name, C.served, rounds, D.round))
            else
                log(string.format("carrier: %s up only %d s of round %d: not counted", C.name, math.floor(now - C.at), D.round))
            end
        end
        if C.served >= rounds and D.state == "wait" then
            C.state, C.removeAt, C.why = "leaving", os.clock(), string.format("%d rounds served", C.served)
            local nf = C.flight and flightOff(C.flight, C.name .. " leaving") or 0
            if COOP and COOP.removeNow then pcall(COOP.removeNow, C.unit) end
            if c.remove_records then fire(string.format("RE_SV_Cargo%dRemove", C.idx), C.name) end
            local n = 0
            for _, e in ipairs((ESC.shipObjs or {})[C.unit] or {}) do if liveAddr(e.obj) == e.addr and offObj(e.obj) then n = n + 1 end end
            RUN.dirty = true
            hudCallout(string.format(t.leaving, C.name), string.format(t.leaving_sub, C.served))
            log(string.format("carrier: %s leaving after %d rounds: %d of its objects and %d ZFA-44s switched off", C.name, C.served, n, nf))
            return
        end
    end
    -- its flight: launched, seen, down, launched again
    local F = C.flight
    if F then
        if not F.up then
            if #planesOf(F.unit, F.at - 1) > 0 or aliveOf(F.unit) > 0 then
                F.up = true
                log(string.format("carrier: %s's ZFA-44s are up (%s, %d planes seen)", C.name, F.unit, #planesOf(F.unit, F.at - 1)))
            elseif now - F.at >= num(c.launch_wait_s, 10) then
                log(string.format("carrier: %s: %s fired %.0f s ago and no plane of %s came: launched by pose from now on", C.name,
                    tostring(F.record), now - F.at, F.unit))
                C.route, C.flight, C.nextLaunchAt = "pose", nil, now
            end
        elseif now >= (F.checkAt or 0) then
            F.checkAt = now + 2
            local live = 0
            for _, e in ipairs(planesOf(F.unit, F.at - 1)) do if (hp(e.obj) or 1) > 0 then live = live + 1 end end
            if live == 0 and noneUp(aliveOf(F.unit)) and now - F.at > 15 then
                C.flight, C.nextLaunchAt = nil, now + num(c.relaunch_s, 30)
                log(string.format("carrier: %s's ZFA-44 flight %s is down: another in %d s", C.name, F.unit, math.floor(num(c.relaunch_s, 30))))
            end
        end
    elseif now >= (C.nextLaunchAt or 0) then
        launch(C, now)
    end
end

---------------------------------------------------------------------------------------------------- co-op
-- (the host) "es|<state>|<landed>|<of>|<her health %>|<km>|<unlocked>|<carriers out>|<landing closed>", on a change
-- (once a second at most) and every 5 s
local function sendState(now)
    if not (COOP and COOP.host and COOP.host() and COOP.msg) then return end
    if now < (ESC.esAt or 0) then return end
    ESC.esAt = now + 1
    local S = ESC.S
    local st, l, n, h, dist, cl = "", 0, 0, -1, 0, 0
    if S and S.D == D and not S.test then
        local lostN
        st = S.state
        l, lostN, n = counts(S)
        h = hpPct(S) or -1
        dist = her(S).r and d2(her(S).r.at, AIRFIELD) / 1000 or 0
        cl = S.closed and 1 or 0
    end
    local key = table.concat({ st, l, n, ESC.unlocked() and 1 or 0, ESC.carriersUp(), cl }, "|")
    if key == ESC.esKey and now < (ESC.esAgain or 0) then return end
    if key ~= ESC.esKey then log("escort: the escort's state sent to the joiners: " .. key) end
    ESC.esKey, ESC.esAgain = key, now + 5
    COOP.msg(nil, "es", st, string.format("%d", l), string.format("%d", n), string.format("%d", h), string.format("%.1f", dist),
        ESC.unlocked() and "1" or "0", string.format("%d", ESC.carriersUp()), string.format("%d", cl))
end
-- (a joiner, sv_coop.lua onJoinerMessage) the host's "es": kept for the NEXT row and the STORE; the unlock is the room's
function ESC.onHost(f)
    local st = tostring(f[2] or ""):match("^%a*$") or ""
    local function n(i, lo, hi) local v = tonumber(f[i]); if not v or v ~= v then return nil end return math.max(lo, math.min(hi, v)) end
    local function w(i, lo, hi, d) return math.floor(n(i, lo, hi) or d) end   -- (whole: the rows format them with %d)
    local h = { state = #st <= 16 and st or "", landed = w(3, 0, 99, 0), total = w(4, 0, 99, 0), hp = w(5, -1, 100, -1),
                km = n(6, 0, 999) or 0, unlocked = f[7] == "1", carriers = w(8, 0, 9, 0), close = f[9] == "1", got = os.clock() }
    local was = ESC.host
    ESC.host = h
    if h.unlocked and not ESC.unlocked() then
        RUN.zfa = { unlocked = true, room = true }
        RUN.dirty = true
        log("escort: the host's escort was won: the ZFA-44 carriers are in the STORE here too (the room's)")
    end
    if not was or was.carriers ~= h.carriers then RUN.dirty = true end
    if h.close ~= (ESC.clientClosed == true) then
        if h.close then
            if not (AF and (AF.closed or AF.down)) then ESC.clientClosed = airfield(true, "the host's CHARLENE landing") end
        else
            if ESC.clientClosed and not (AF and (AF.closed or AF.down)) and not RUN.captured then airfield(false, "the host's escort") end
            ESC.clientClosed = false
        end
    end
end
-- (a joiner, sv_hud.lua) the host's escort's NEXT row, while it's on there (10 s fresh)
function ESC.clientRow(t)
    local h = ESC.host
    if not (client() and h and os.clock() - h.got <= 10 and (h.state == "route" or h.state == "landing")) then return nil end
    local tx = ec().text
    if h.state == "route" then return string.format(tx.row, h.hp >= 0 and h.hp or 100, h.km, h.landed, h.total) end
    return string.format(tx.row_landing, h.landed, h.total)
end
-- (sv_allies.lua's ALLIES row, wrapped) the carriers out
do
    local rawLine = ALLY.hudLine
    if type(rawLine) == "function" then
        ALLY.hudLine = function(...)
            local s, news = rawLine(...)
            local okN, n = pcall(ESC.carriersUp)
            if okN and n and n > 0 then
                s = (s and (s .. "   ") or "") .. string.format("ZFA-44 CARRIERS %d", n)
                news = (news and (news .. " ") or "") .. "ZFA-44"
            end
            return s, news
        end
    end
end

---------------------------------------------------------------------------------------------------- every tick
-- the names on their boxes (once a session, as the allies' at the main menu: sv_allies.lua ALLY.setup)
local function names()
    if ESC.namesSet or type(SV_SetText) ~= "function" then return end
    ESC.namesSet = true
    local c, k, n = ec(), cc(), 0
    local list = { { c.name_key, c.name } }
    for _, e in ipairs(c.escorts or {}) do list[#list + 1] = { e.name_key, e.name } end
    list[#list + 1] = { k.name_key, k.name }
    list[#list + 1] = { k.zfa and k.zfa.name_key, k.zfa and k.zfa.name }
    for _, x in ipairs(list) do
        if type(x[1]) == "string" and type(x[2]) == "string" and SV_SetText(x[1], x[2]) == 1 then n = n + 1 end
    end
    log(string.format("escort: %d of %d name texts set (CHARLENE, her escorts, the carriers, the ZFA-44)", n, #list))
end
local function dressTick()
    local q = ESC.dressQ
    if #q == 0 then return end
    local z = cc().zfa or {}
    local done = 0
    while #q > 0 and done < 2 do
        local e = table.remove(q, 1)
        if liveAddr(e.obj) == e.addr then
            done = done + 1
            if z.dress ~= false and ZFA and ZFA.dress then
                local okD, did, why = pcall(ZFA.dress, e.obj, { paint = z.paint, label = e.unit, hide_s = z.hide_s })
                if not okD then logOnce("zfa dress", "carrier: ZFA-44 dressing error " .. tostring(did)) end
                ESC.dressedN = (ESC.dressedN or 0) + ((okD and did) and 1 or 0)
                if not (okD and did) and not ESC.dressSaid then ESC.dressSaid = true; log("carrier: a ZFA-44 not dressed: " .. tostring(why)) end
            elseif not ESC.noDressSaid then
                ESC.noDressSaid = true
                log("carrier: no ZFA-44 dressing in this build (sv_zfa44.lua cut: no ZFA-44 container): its planes fly as their host airframe")
            end
        end
    end
end
local function recycleTick()
    local q = ESC.recycleQ
    for i = #q, 1, -1 do
        local e = q[i]
        if os.clock() >= e.at then
            table.remove(q, i)
            if type(SV_Recycle) == "function" and aliveOf(e.unit) ~= -2 then
                crumb("escort SV_Recycle " .. e.unit)
                local okR, r = pcall(SV_Recycle, e.unit, 1)
                log(string.format("escort: %s off the spawner's list (%s): SV_Recycle %s", e.unit, tostring(e.why), okR and tostring(r) or ("error " .. tostring(r))))
            end
            return                                         -- (one a tick)
        end
    end
end
-- every tick half (sv_main.lua probeTickB, on the round clock), every game
function ESC.tick(now)
    if not (D and now) then return end
    if ESC.S and ESC.S.D ~= D then ESC.S = nil end          -- (a new run: what it was is the old level's)
    names()
    hullsTick()
    dressTick()
    if ZFA and ZFA.prodTick then
        local okZ, errZ = pcall(ZFA.prodTick)
        if not okZ then logOnce("zfa prod", "carrier: ZFA-44 tick error " .. tostring(errZ)) end
    end
    recycleTick()
    if client() then return end
    local S = ESC.S
    if S and S.test then
        ESC.step(S, now)
        if D.state == "wait" and D.at and D.at < now + 3 then D.at = now + 3 end   -- (the test holds the break)
        if S.state == "done" and S.endAt and now >= S.endAt then
            takeOff(S, "the landing test over")
            ESC.S = nil
        end
    end
    local R = run()
    for _, C in pairs(R.carriers) do
        local okC, errC = pcall(carrierTick, C, now)
        if not okC and not C.errSaid then C.errSaid = true; log("carrier: " .. tostring(C.name) .. " error " .. tostring(errC)) end
    end
    local okS, errS = pcall(sendState, now)
    if not okS then logOnce("escort es", "escort: state send error " .. tostring(errS)) end
end
-- the level's objects forgotten with it, none of them touched (sv_core.lua levelDrop)
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the escort"] = function()
        ESC.S, ESC.R, ESC.planes, ESC.dressQ, ESC.newObjs, ESC.hulls, ESC.shipObjs = nil, nil, {}, {}, {}, {}, nil
        ESC.recycleQ, ESC.clientClosed, ESC.host = {}, nil, nil
    end
end

-- TEST ONLY BEGIN (Ctrl+F1: the landing test T0; Ctrl+F2: the carriers unlocked and one sent now; sv_main.lua's keys)
-- T0 (tools/re/ESCORT.md): CHARLENE alone at the approach fix (heading 067), her final, rollout, taxi and stop with no
-- enemies sent at her and no escorts, her place against the runway, height, speed and gear logged every log_s
-- (`escort: T0 +N s: ...`), the break held while it runs, taken off end_s after she's down
function ESC.testT0()
    if not (D and D.now) then log("test: Ctrl+F1 outside a Survival run"); return end
    if ESC.S then hudCallout("TEST: ESCORT T0", "AN ESCORT IS ALREADY UP"); log("escort: T0: an escort is already up"); return end
    local c = ec()
    local S = newOp(D.now, "t0")
    local g = c.geo
    local ok, r = spawnAc(S, her(S), { x = g.iaf[1], y = g.iaf[2], z = g.iaf[3], yaw = 67 - 90 })
    if not ok then hudCallout("TEST: ESCORT T0", "CHARLENE NOT SPAWNED"); log("escort: T0: CHARLENE not spawned: " .. ERR(r)); return end
    S.state = "route"
    ESC.S = S
    hudCallout("TEST: ESCORT T0", "CHARLENE ON FINAL: WATCH HER LAND")
    log("escort: T0: CHARLENE at the approach fix, heading 067, no enemies at her: her final, rollout, taxi and stop logged")
end
function ESC.testCarrier()
    if not (D and D.now) then log("test: Ctrl+F2 outside a Survival run"); return end
    RUN.zfa = { unlocked = true, test = true }
    RUN.dirty = true
    local ok, msg = ESC.buyCarrier(nil, 0)
    hudCallout("TEST: ZFA-44 CARRIER", ok and "UNLOCKED, ONE SENT" or ("UNLOCKED: " .. tostring(msg)))
    log("escort: test: Ctrl+F2: the ZFA-44 carriers unlocked; " .. tostring(msg))
end
-- TEST ONLY END
end
