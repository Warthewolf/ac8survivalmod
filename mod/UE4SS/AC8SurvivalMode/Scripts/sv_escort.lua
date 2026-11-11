-- (sv_escort.lua is the first of 2 pieces, split by tools/lua_split_part.py: sv_escort_carriers.lua goes on from where
-- it ends, run by main.lua right after it, in that order.)
-- sv_escort.lua: THE ESCORT (the allied B-1B CHARLENE and her four escorts, flown in and landed at Comona airfield) and
-- its reward, the ZFA-44 carriers in the STORE (docs/re/ESCORT.md; user, 2026-11-06; build contract of 2026-11-06).
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
--           spawn ahead of her (DIR.spawnAt, ahead.share), and waves of 4-12 come at her from a new direction each
--           every every_s until she touches down (waves); in co-op more of both for the room (coop_scale: sv_escort_waves.lua)
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
function ec() return CFG.specials.escort end
function cc() return CFG.allies.carrier end
function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
function now0() return (D and tonumber(D.now)) or 0 end
function client() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local ORDER_NORMAL, PRIO_PLAYER_ONLY_NO_LIMIT, PRIO_TARGET_FIRST, FIRE_BITS = 0, 8, 9, 7   -- (sv_coop.lua's, sv_allies.lua's)
local STEP = { route = "Go", orbit = "Orbit", final = "Final", roll = "Roll", taxi = "Taxi", stop = "Stop" }
ERR = function(r) return tostring(SV_ERR and SV_ERR[r] or r) end

---------------------------------------------------------------------------------------------------- whose unit
-- unit -> "charlene" | "escort" | "cargo" | "zfa" (a carrier's flight: its pose unit or a launcher arm's)
KIND, CARGO_I, ZFA_I = {}, {}, {}
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
function ESC.hullShip(unit) return unit and KIND[unit] == "cargo" and CARGO_I[unit] or nil end   -- (a carrier's hull: its ship)

---------------------------------------------------------------------------------------------------- planes and objects
-- each of these units' planes as logPlane saw them: ESC.planes[unit] = { { obj, addr, name, at }, ... }; the live one
function entryLive(e)                              -- (its name read again at most every 2 s: an address reused)
    if liveAddr(e.obj) ~= e.addr then return false end
    local c = os.clock()
    if c < (e.nameAt or 0) then return true end
    e.nameAt = c + 2
    return nameOf(e.obj) == e.name
end
function hp(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end
function planesOf(unit, since)
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
function locOf(o)
    local ok, l = pcall(function() local v = o:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    return ok and l or nil
end
function d2(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) / 100 end          -- (metres)
local function d3(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) / 100 end
function bearing(from, to) return math.deg(math.atan(to.X - from.X, -(to.Y - from.Y))) % 360 end   -- (compass)
local function angOff(a, b) return math.abs(((a - b + 540) % 360) - 180) end
local function pt(g) return { X = g[1], Y = g[2], Z = g[3] or 0 } end
-- (the build's flags, docs/re/ESCORT.md "Build names") each aircraft's leg (SV_CharLeg / SV_EscLeg<Name>) and taxi
-- slot (SV_TaxiSlotChar / SV_TaxiSlot<Name>), named by its record prefix's tail; a leg's number as a step: hers 1 route,
-- 2 final, 3 roll, 4 taxi, 5 stop; an escort's 1 route, 2 orbit (or its cover, <rec>Guard), 3 final, 4 roll, 5 taxi, 6 stop
local function whoKey(A) return A.her and "Char" or (tostring(A.rec):match("^RE_SV_Esc(%a+)$") or "") end
local function legFlag(A) return A.her and "SV_CharLeg" or ("SV_EscLeg" .. whoKey(A)) end
local function slotFlag(A) return "SV_TaxiSlot" .. whoKey(A) end
local LEGS = { her = { "route", "final", "roll", "taxi", "stop" }, escort = { "route", "orbit", "final", "roll", "taxi", "stop" } }
local RANK = { spawn = 0, route = 1, orbit = 2, inbound = 2.5, final = 3, roll = 4, taxi = 5, stop = 6, landed = 7, lost = 8 }
-- the event package's int flags as svFlags (sv_core.lua) read them, only from a read 2 s or more after this operation's
-- RE_SV_EscortReset (one cached from before it may still hold the last escort's legs); nil: not known
local function flagsNow(S)
    if type(svFlags) ~= "function" then return nil end
    local okF, t = pcall(svFlags)
    if not (okF and type(t) == "table") then return nil end
    local at = type(flagCache) == "table" and tonumber(flagCache.at) or nil
    if not at or at < (S.resetClock or 0) + 2 then return nil end
    return t
end
-- an object switched off without a kill (no pay, no explosion): no box, no lock-on, invincible, inactive, hidden, no
-- collision, no tick (sv_rounds.lua takeDown's "off")
function offObj(o)
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
ESC.offObj = offObj                                      -- (a ZFA-44 that can't be finished: sv_escort_laser.lua ZLAUNCH.finish)

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
    local sp = up and (cc().ship_at or {})[i]
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
    -- ((2026-11-07) dressed settle_s after it's seen, not in its first second: three joiners dropped as a carrier came
    -- on station, one mid-dress of a plane the ship had just made)
    if KIND[unit] == "zfa" and #ESC.dressQ < 32 then
        ESC.dressQ[#ESC.dressQ + 1] = { obj = o, addr = a, unit = unit, due = os.clock() + num((cc().zfa or {}).settle_s, 1.5) }
    end
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
function hullsTick()
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
function fire(ev, why)
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    if r ~= 1 then log(string.format("escort: %s NOT fired (%s): %s", ev, tostring(why or ""), ERR(r))) end
    return r == 1, r
end
function airfield(close, why)
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
-- { unit -> { at, again } }, decided, seen, reinf = { n (waves), at (the next), units, sector (the last's) }, closed, won,
-- lost }; an aircraft A: { name, unit, rec,
-- escort (its CFG entry, nil: CHARLENE), st ("spawn", "route", "orbit", "inbound", "final", "roll", "taxi", "stop", "landed",
-- "lost"), since (S.t at its step), r (its last read), how (landed: "stopped" / "timeout") }
function newOp(now, test)
    local c = ec()
    local S = { test = test, at = now, t = 0, last = now, state = "spawn", ac = {}, attackers = {}, decided = {}, seen = {},
                reinf = { n = 0, at = now + num(c.waves and c.waves.first_s, 20), units = {} }, released = 0,
                lastRelease = -1e9, D = D }
    S.ac[1] = { name = c.name, unit = c.unit, rec = c.rec, st = "spawn", since = 0, her = true }
    if not test then
        for _, e in ipairs(c.escorts or {}) do
            S.ac[#S.ac + 1] = { name = e.name, unit = e.unit, rec = e.rec, st = "spawn", since = 0, escort = e }
        end
    end
    return S
end
function her(S) return S.ac[1] end
function aliveOf(u)
    local ok, n = pcall(SV_UnitAlive, u)
    return (ok and type(n) == "number") and n or -5
end
-- none of it up: 0 alive, not on the spawner's list (-7) or no such unit (-2); never an error (-1 / -5 / -6: not ready)
function noneUp(n) return n == 0 or n == -7 or n == -2 end
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
-- its parking slot (geo.slots A-E in landing order, as the build's Taxi records count them in SV_EscortSlots): the next one
-- as it begins its taxi here; the build's own (SV_TaxiSlot<Who>) once it can be read (stopSpot)
local function taxiSlot(S, A)
    if A.slotN then return end
    S.taxiN = (S.taxiN or 0) + 1
    A.slotN = math.min(math.max(1, #(ec().geo.slots or {})), S.taxiN)
end
-- ((2026-11-07) the landing test T0's final, its slow-downs and its rollout fire their own records, RE_SV_CharT0*: her
-- own path there is SV_Path_CharFinal, as she's spawned before the IAF, not on her route)
local T0_SUFFIX = { Final = true, FinalSlow = true, FinalShort = true, Roll = true }
local function recFor(S, A, suffix)
    if S.test and A.her and T0_SUFFIX[suffix] then return A.rec .. "T0" .. suffix end
    return A.rec .. suffix
end
local function goStep(S, A, st, why)
    local ev = recFor(S, A, STEP[st])
    local ok = fire(ev, A.name)
    A.st, A.since = st, S.t
    if st == "taxi" then taxiSlot(S, A) end
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
function spawnAc(S, A, pose)
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
-- CHARLENE's start (rightM 0, upM 0) or an escort's: rightM to her right across her way and upM above her, as the build's
-- routes start (tools/survival_events.py esc_route_pts: right_km to the right of the start -> IAF line, up_km above it;
-- none behind). The way is the exact one from the start to geo.iaf (the build's), else the start's heading. (Code review
-- of 2026-11-07: the old side / back signs and 250 m steps put every escort on the wrong side and behind her: at Go each
-- crossed her track at the route's 600 km/h to reach its own route.)
local function startPose(rightM, upM)
    local st, g = ec().start, ec().geo or {}
    local hdg = num(st.heading, 55)
    local way = hdg
    if type(g.iaf) == "table" and tonumber(g.iaf[1]) and tonumber(g.iaf[2]) then
        way = bearing({ X = st.x, Y = st.y }, { X = g.iaf[1], Y = g.iaf[2] })
    end
    local h = math.rad(way)
    local rx, ry = math.cos(h), math.sin(h)                -- (her right: compass heading + 90, north being -Y)
    local rm = num(rightM, 0) * 100
    return { x = st.x + rx * rm, y = st.y + ry * rm, z = st.z + num(upM, 0) * 100, yaw = hdg - 90 }
end
ESC.startPose = startPose

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
            local want = attackOk(u) and n < ESC.roomMore(num(a.max, 4)) and (S.reinf.units[u] or math.random() < num(a.share, 0.6))
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
-- ((2026-11-07) the user: "Keep spawning Multiple enemy fighters until she lands, have them range from 4 to 12 aircraft
-- spawning per wave in different directions") While she flies her route and her final, a wave every every_s (the first
-- first_s after her spawn) of min_n .. max_n aircraft: free pool flights (2-, 4- and 6-ships, not up, not one the round
-- still has to send; one shot down flies again: SV_Spawn takes it off the spawner's list first, hard rule 16), all of it
-- from one of eight directions round her (km out, its flights spread_deg apart, alt_m up, facing her), never the last
-- wave's direction nor one next to it. Held while max_up enemy aircraft are up (cut to what's left while min_n still fit);
-- max_waves 0: no limit. Each goes after her (attackTick: a wave's flight always wants her, attack.max at once).
local SECTOR = { "ahead", "ahead right", "right", "behind right", "behind", "behind left", "left", "ahead left" }
local COMPASS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
ESC.SECTOR = SECTOR
local function wavesTick(S, now)
    local w = ec().waves or {}
    if not (w.enabled and D and D.up) or now < S.reinf.at then return end
    local most = math.floor(num(w.max_waves, 0))
    if most > 0 and S.reinf.n >= most then return end
    local A = her(S)
    if not (A.r and A.r.at and A.r.hdg) then S.reinf.at = now + 2; return end
    local up = 0
    for _, p in ipairs(planes or {}) do if not p.down and not KIND[p.unit] then up = up + 1 end end
    local lo = 2 * math.ceil(math.max(2, ESC.roomMore(math.floor(num(w.min_n, 4)))) / 2)   -- (even: (2026-11-11) 2-3 players made it 5, a wave of 6 one over max_up)
    local hi = math.max(lo, ESC.roomMore(math.floor(num(w.max_n, 12))))
    local maxUp = ESC.roomMore(math.floor(num(w.max_up, 24)), "max_up")
    local room = maxUp - up
    if room < lo then
        S.reinf.at = now + 5
        if not S.reinf.fullSaid then
            S.reinf.fullSaid = true
            log(string.format("escort: wave %d held: %d enemy aircraft up (max_up %d)", S.reinf.n + 1, up, maxUp))
        end
        return
    end
    S.reinf.fullSaid = nil
    -- (the flights are 2-, 4- and 6-ships: an even count, at least min_n, at most max_n and the room left)
    local top = math.min(hi, room)
    local want = 2 * math.random(math.ceil(lo / 2), math.max(math.ceil(lo / 2), math.floor(top / 2)))
    local list, got = ESC.waveFlights(want, aliveOf, noneUp)
    if got < lo then
        S.reinf.at = now + 5
        if not S.reinf.noneSaid then
            S.reinf.noneSaid = true
            log(string.format("escort: wave %d held: free flights for only %d aircraft (min_n %d)", S.reinf.n + 1, got, lo))
        end
        return
    end
    S.reinf.noneSaid = nil
    local kmT = type(w.km) == "table" and w.km or { 12, 16 }
    local k0 = num(kmT[1], 12)
    local km = k0 + math.random() * math.max(0, num(kmT[2] or kmT[1], 16) - k0)
    local alt = type(w.alt_m) == "table" and w.alt_m or { 2500, 4000 }
    local aLo = num(alt[1], 2500)
    local aHi = math.max(aLo, num(alt[2] or alt[1], 4000))
    local m = ZONE.HALF - 300000
    -- its direction: of the eight, not the last wave's nor one next to it, and (her start is at the combat zone's corner)
    -- one whose spot is inside the zone (else every flight of it was put on the same spot of the zone's edge); none
    -- of those: one inside but the last one's, then any inside; none at all: the others, put on the edge
    local function inZone(k)
        local b = math.rad(A.r.hdg + (k - 1) * 45)
        local x, y = A.r.at.X + math.sin(b) * km * 100000, A.r.at.Y - math.cos(b) * km * 100000
        return math.abs(x - ZONE.X) <= m and math.abs(y - ZONE.Y) <= m
    end
    local last = S.reinf.sector
    local fresh, other, inside, any = {}, {}, {}, {}
    for k = 1, 8 do
        local new = not last or math.min((k - last) % 8, (last - k) % 8) > 1
        local inn = inZone(k)
        if new and inn then fresh[#fresh + 1] = k end
        if inn and k ~= last then other[#other + 1] = k end
        if inn then inside[#inside + 1] = k end
        if new then any[#any + 1] = k end
    end
    local opts = (#fresh > 0 and fresh) or (#other > 0 and other) or (#inside > 0 and inside) or any
    local sec = opts[math.random(#opts)]
    local base = (A.r.hdg + (sec - 1) * 45) % 360                     -- (the compass bearing from her to the wave)
    S.reinf.n, S.reinf.sector, S.reinf.at = S.reinf.n + 1, sec, now + num(w.every_s, 45)
    S.reinf.dir = COMPASS[math.floor(((base + 22.5) % 360) / 45) + 1]   -- (its subtitle's {dir}: sv_escort_subs.lua)
    local nUp, said = 0, {}
    for i, u in ipairs(list) do
        local b = math.rad(base + (i - (#list + 1) / 2) * num(w.spread_deg, 12))
        local x = A.r.at.X + math.sin(b) * km * 100000
        local y = A.r.at.Y - math.cos(b) * km * 100000
        x, y = math.max(ZONE.X - m, math.min(ZONE.X + m, x)), math.max(ZONE.Y - m, math.min(ZONE.Y + m, y))
        local pose = { x = x, y = y, z = (aLo + math.random() * (aHi - aLo)) * 100,
                       yaw = (bearing({ X = x, Y = y }, A.r.at) - 90) % 360,
                       why = string.format("CHARLENE's wave %d (%s of her)", S.reinf.n, SECTOR[sec]) }
        local r = spawnFlight(u, nil, pose)
        if r > 0 then
            nUp = nUp + r
            S.reinf.units[u] = true
            if D.taken then D.taken[u] = true end
            for j = #(D.spare or {}), 1, -1 do if D.spare[j] == u then table.remove(D.spare, j) end end
            said[#said + 1] = string.format("%s %d", u, r)
        else
            said[#said + 1] = u .. " NOT (" .. ERR(r) .. ")"
        end
    end
    log(string.format("escort: wave %d: %d aircraft (%d asked, %d-%d%s) %s of CHARLENE, from the %s, %.1f km out: %s (%d enemy aircraft were up)",
        S.reinf.n, nUp, want, lo, hi, (maxUp ~= math.floor(num(w.max_up, 24))) and string.format(", max_up %d for the room", maxUp) or "",
        SECTOR[sec], COMPASS[math.floor(((base + 22.5) % 360) / 45) + 1], km, table.concat(said, ", "), up))
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
    local H = her(S)
    for _, A in ipairs(S.ac) do
        -- (before her final only: on its route, its cover, or an orbit its route's end began; at her final they go to
        -- their wait orbits, where nothing takes them off before their release)
        local leg = S.flags and tonumber(S.flags[legFlag(A)])
        local before = A.escort and not S.orbitFired and (A.st == "route" or A.st == "orbit") and not (leg and leg >= 3)
        -- the build's cover (<rec>Guard: off its route, Normal, air search, its unit area onto her at 3 km) from the
        -- first enemy near her on, given again every record_every_s while she flies her route (its area follows her)
        if before and g.records ~= false and H.st == "route" and (#foes > 0 or A.guardOn) and S.t >= (A.guardRecAt or 0) then
            A.guardRecAt = S.t + num(g.record_every_s, 6)
            if fire(A.rec .. "Guard", A.name) and not A.guardOn then
                A.guardOn = true
                log(string.format("escort: %s covers CHARLENE (%sGuard: off its route, its area on her at 3 km, again every %d s); %s",
                    A.name, A.rec, math.floor(num(g.record_every_s, 6)), where(A)))
            end
        end
        if before and #foes > 0 then
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
local function stopSpot(S, A)
    local sl = ec().geo.slots or {}
    local k = S.flags and tonumber(S.flags[slotFlag(A)])
    if k and k >= 1 and k <= #sl and k == math.floor(k) and k ~= A.slotN then
        log(string.format("escort: %s's parking slot %s (the build's %s %d; counted here: %s)", A.name, string.char(64 + k), slotFlag(A),
            k, A.slotN and string.char(64 + A.slotN) or "none"))
        A.slotN = k
    end
    local q = sl[A.slotN or 1] or sl[#sl]
    if not q then return pt(ec().geo.roll_end) end
    return rwPoint(num(q[1], 0), num(q[2], 62.5))
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
    log(string.format("escort: %s landed (%s%s); %s", A.name, how == "timeout" and "the safety timeout: counted as landed"
        or (how == "taxi" and "on the ground, taxiing to its slot" or "stopped"),
        (how == "timeout" and flying) and ", taken off: it was still flying" or "", where(A)))
    if A.her and not S.test then
        local left = 0
        for _, B in ipairs(S.ac) do if B.escort and B.st ~= "landed" and B.st ~= "lost" then left = left + 1 end end
        local t = ec().text
        hudCallout(t.landed, string.format(t.landed_sub, left))
        if RUN.escort then RUN.escort.arrived, RUN.dirty = D.round, true end   -- (the Anomalies may come: ESC.anomalyOk)
    end
end
-- the build's backstops (each path's PathFinish starts the next step while its leg flag says Lua hasn't: hard rules 1,
-- 26) move an aircraft on by themselves: its leg flag ahead of the step here is taken, with what Lua's own step does
local function legSync(S, A, o)
    local leg = S.flags and tonumber(S.flags[legFlag(A)])
    if not leg or leg < 1 or A.st == "landed" or A.st == "lost" or A.st == "spawn" then return end
    local st = (A.her and LEGS.her or LEGS.escort)[math.floor(leg)]
    if not st or RANK[st] <= (RANK[A.st] or 0) then return end
    if st == "orbit" and A.guardOn then return end             -- (an escort's leg 2 is its cover too: Lua's Guard)
    local was = A.st
    A.st, A.since, A.goFired = st, S.t, true
    log(string.format("escort: %s %s (the build's backstop moved it on: %s %d; it was %s here); %s", A.name, st, legFlag(A), leg,
        was, where(A)))
    if RANK[st] >= RANK.final then
        gear(A, o)
        A.finalT = A.finalT or S.t
    end
    if RANK[st] >= RANK.roll and ec().landing.invincible_on_ground then pcall(function() o:SetIsInvincible(true) end) end
    if RANK[st] >= RANK.taxi then taxiSlot(S, A) end
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
    legSync(S, A, o)
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
        -- (her route at its slow speed from cruise_slow_km of the touchdown (600 km/h since 2026-11-08: tools/
        -- survival_events_escort.py ESC_SPEED): the route given again, Mission 14's speed control;
        -- her escorts still on theirs with her)
        local km = num(L.cruise_slow_km, 0)
        if km > 0 and not S.slowFired and d2(r.at, td) <= km * 1000 then
            S.slowFired = true
            local ok, n = fire(A.rec .. "CruiseSlow", A.name), 0
            for _, B in ipairs(S.ac) do
                if B.escort and B.st == "route" and B.goFired and not B.guardOn and fire(B.rec .. "CruiseSlow", B.name) then n = n + 1 end
            end
            log(string.format("escort: %s %.1f km from the touchdown: her route at 600 km/h (%sCruiseSlow %s), %d escorts on their routes with her",
                A.name, d2(r.at, td) / 1000, A.rec, ok and "fired" or "NOT fired", n))
        end
        local passed = prevIaf and A.iafD > prevIaf + 1 and A.iafD <= 4000
        if A.iafD <= num(L.final_at_m, 2000) or passed or S.t - A.since >= num(L.route_max_s, 900) then
            goStep(S, A, "final", A.iafD <= num(L.final_at_m, 2000) and string.format("%.0f m from the approach fix", A.iafD)
                or (passed and "past the approach fix" or string.format("%d s on her route", num(L.route_max_s, 900))))
            gear(A, o)
            A.finalT = S.t
            if L.final_fast ~= false and not S.test then A.fastAt = S.t + 1 end
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
        -- ((2026-11-07, the user: "The Landing for Yorke, Charlene, Rock, Ali and Danielle takes WAY TOO long"; her 18 km
        -- final had flown at 320 km/h) her final at 450 until final_slow_km: her route given again at its 450
        -- (<rec>CruiseSlow) a second after her Final record, the gear left down (final_fast)
        if A.her and A.fastAt and not A.fastDone and not A.finalSlow and S.t >= A.fastAt then
            A.fastDone = true
            local ev = A.rec .. "CruiseSlow"
            log(string.format("escort: %s's final at 600 km/h until %.1f km from the touchdown (%s %s, gear down)", A.name,
                num(L.final_slow_km, 6), ev, fire(ev, A.name) and "fired" or "NOT fired"))
        end
        -- (its final slower near the runway: 280 km/h from final_slow_km, 260 from final_short_km, the path given again)
        local dtd = d2(r.at, td)
        local fh, fs = num(L.final_short_km, 0), num(L.final_slow_km, 0)
        -- ((2026-11-07) an escort's circuit passes 3 km off the runway on its downwind: its slow-downs only once it's on the
        -- final leg, on the centre line heading the runway's way; and (the same day's co-op game: YORKE crossed the
        -- runway's centre line 2.9 km up on its way to the circuit, so its 260 fired there and it flew the whole circuit
        -- at 260) only that low over the runway: escort_slow_up_m for its 280, escort_short_up_m for its 260)
        local onLeg = A.her or ESC.onFinalLeg(A)
        local lowS = A.her or above <= num(L.escort_slow_up_m, 450)
        local lowH = A.her or above <= num(L.escort_short_up_m, 250)
        if onLeg and lowH and fh > 0 and not A.finalShort and dtd <= fh * 1000 then
            A.finalShort, A.finalSlow = true, true
            local ev = recFor(S, A, "FinalShort")
            log(string.format("escort: %s %.1f km from the touchdown: its final at 600 km/h, the last stretch (%s %s)", A.name, dtd / 1000, ev,
                fire(ev, A.name) and "fired" or "NOT fired"))
        elseif onLeg and lowS and fs > 0 and not A.finalSlow and dtd <= fs * 1000 then
            A.finalSlow = true
            local ev = recFor(S, A, "FinalSlow")
            log(string.format("escort: %s %.1f km from the touchdown: its final at 600 km/h, near the runway (%s %s)", A.name, dtd / 1000, ev,
                fire(ev, A.name) and "fired" or "NOT fired"))
        end
        -- ((2026-11-07) her approach watched: farther from the touchdown than she's been by recover_m (and over 2 km out),
        -- her path given again (it goes on along it), at most recover_max times recover_gap_s apart)
        if A.her then
            A.minD = math.min(A.minD or dtd, dtd)
            local again = num(L.recover_max, 3)
            if dtd > 2000 and dtd > A.minD + num(L.recover_m, 800) and (A.recovered or 0) < again
                and S.t - (A.recoverAt or -1e9) >= num(L.recover_gap_s, 20) then
                A.recovered, A.recoverAt = (A.recovered or 0) + 1, S.t
                local ev = recFor(S, A, "Final")
                log(string.format("escort: %s off her approach (%.1f km from the touchdown, %.1f km at the closest, heading %03d): %s %s, "
                    .. "her path given again (%d of %d)", A.name, dtd / 1000, A.minD / 1000, math.floor(r.hdg + 0.5), ev,
                    fire(ev, A.name) and "fired" or "NOT fired", A.recovered, again))
            end
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
            -- ((2026-11-07) landed once it's on the ground and taxiing (landed_at_taxi): its taxi and stop go on by the
            -- build's own path ends (their backstops), and nobody waits on them; the landing test T0 still to its stop)
            if L.landed_at_taxi ~= false and not S.test then landed(S, A, "taxi") end
        end
    elseif A.st == "taxi" then
        local slow = r.kmh <= 3
        A.slowSince = slow and (A.slowSince or S.t) or nil
        local spot = stopSpot(S, A)
        if d2(r.at, spot) <= num(L.stop_at_m, 60) or S.t - A.since >= num(L.taxi_max_s, 90)
            or (S.t - A.since >= 10 and A.slowSince and S.t - A.slowSince >= 3) then
            goStep(S, A, "stop", string.format("%.0f m from its parking slot %s", d2(r.at, spot), string.char(64 + (A.slotN or 1))))
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
-- ((2026-11-07) Alyssa's test: the escorts' wait-circle paths began kilometres round the circle from them, so they never
-- took them and flew off.) An escort's landing: held over CHARLENE (<rec>Orbit: off its path, its area on her at 4 km) from
-- her final until she's off the runway, then, one at a time release_gap_s apart, onto the landing circuit
-- (SV_Path_EscCircuit: downwind WSW north of the runway from geo.circuit_start, the base turn, the final, the rollout) the
-- moment its start is a little ahead of it: circuit_min_m .. circuit_max_m away, within circuit_nose_deg of its nose and it
-- heading within circuit_hdg_deg of the circuit's own (hard rule 2); none lined up in hold_max_s: started anyway.
function ESC.circuitAhead(B)
    local g, L = ec().geo, ec().landing
    if not (B.r and g.circuit_start) then return false, nil end
    local cs = pt(g.circuit_start)
    local d = d2(B.r.at, cs)
    local ok = d >= num(L.circuit_min_m, 800) and d <= num(L.circuit_max_m, 6000)
        and angOff(bearing(B.r.at, cs), B.r.hdg) <= num(L.circuit_nose_deg, 50)
        and angOff(B.r.hdg, num(g.circuit_heading, 247)) <= num(L.circuit_hdg_deg, 75)
    return ok, d
end
-- an escort on the final leg: on the extended centre line (final_leg_m across it) heading the runway's way, short of the
-- rollout's end
function ESC.onFinalLeg(B)
    local g, L = ec().geo, ec().landing
    if not B.r then return false end
    local t, s = rw(B.r.at)
    return math.abs(s) <= num(L.final_leg_m, 700) and angOff(B.r.hdg, num(g.heading, 67)) <= 50 and t <= rw(pt(g.roll_end))
end
local function escortsTick(S)
    local A = her(S)
    if not S.orbitFired and (A.st ~= "route" and A.st ~= "spawn") then
        S.orbitFired = true
        for _, B in ipairs(S.ac) do
            if B.escort and (B.st == "route" or (B.st == "orbit" and B.guardOn)) then
                B.guardOn = nil
                goStep(S, B, "orbit", "CHARLENE on final: holding over her")
            end
        end
    end
    if not S.orbitFired then return end
    local L = ec().landing
    -- ((2026-11-07, the user: "The Landing for Yorke, Charlene, Rock, Ali and Danielle takes WAY TOO long": the escorts
    -- went one at a time, each only once the last was down and the runway clear, up to 120 s waiting to line up, so
    -- the round ran 25 minutes and ended on its cap.) Now they all go onto the circuit while she lands: from release_at
    -- (her "final", her "roll", or "landed") + release_first_s, one every release_gap_s, the circuit's spacing keeping them
    -- apart; each time the first holding one lined up with the circuit's start, else (none in hold_max_s) the first anyway
    if not S.releaseFrom then
        local at, r = tostring(L.release_at or "final"), RANK[her(S).st] or 0
        local go = her(S).st == "landed" or (at == "final" and r >= RANK.final) or (at == "roll" and r >= RANK.roll)
        if not go then return end
        S.releaseFrom = S.t + num(L.release_first_s, 10)
        log(string.format("escort: the escorts' landings begin in %.0f s (CHARLENE %s), one every %.0f s", num(L.release_first_s, 10),
            her(S).st, num(L.release_gap_s, 15)))
    end
    if S.t < S.releaseFrom or S.t - S.lastRelease < num(L.release_gap_s, 15) then S.clearAt = nil; return end
    S.clearAt = S.clearAt or S.t
    local function go(B, how, d)
        S.released, S.lastRelease, S.clearAt = S.released + 1, S.t, nil
        log(string.format("escort: %s released for its landing (%d of %d; %s, the circuit's start %s km %s); %s", B.name, S.released,
            #S.ac - 1, how, d and string.format("%.1f", d / 1000) or "?", how == "lined up" and "ahead" or "off", where(B)))
        goStep(S, B, "final", how == "lined up" and "the landing circuit, its start ahead" or "the landing circuit, started anyway")
        local o = planeOf(B.unit)
        if o then gear(B, o) end
        B.finalT = S.t
    end
    for _, B in ipairs(S.ac) do
        if B.escort and B.st == "orbit" then
            local ahead, d = ESC.circuitAhead(B)
            if ahead then return go(B, "lined up", d) end
        end
    end
    if S.t - S.clearAt < num(L.hold_max_s, 0) then return end
    for _, B in ipairs(S.ac) do
        if B.escort and (B.st == "orbit" or B.st == "route") then
            local _, d = ESC.circuitAhead(B)
            return go(B, string.format("not lined up in %d s: started anyway", math.floor(num(L.hold_max_s, 0))), d)
        end
    end
end
-- ((2026-11-07) every track_s from her final until everyone's down: where each one is, for the next test's log)
local function trackLog(S)
    local L = ec().landing
    if S.t < (S.trackAt or 0) then return end
    S.trackAt = S.t + num(L.track_s, 3)
    local H, parts = her(S), {}
    for _, B in ipairs(S.ac) do
        if B.r and B.st ~= "landed" and B.st ~= "lost" and B.st ~= "spawn" then
            local t, s = rw(B.r.at)
            local extra = ""
            if B.escort and B.st == "orbit" and H.r then extra = string.format(", %.1f km from her", d2(B.r.at, H.r.at) / 1000) end
            parts[#parts + 1] = string.format("%s %s t %.1f s %.1f km, %.0f m, %.0f km/h, hdg %03d%s", B.name, B.st, t / 1000, s / 1000,
                (B.r.at.Z - num(ec().geo.runway_z, 750)) / 100, B.r.kmh or 0, math.floor((B.r.hdg or 0) + 0.5), extra)
        end
    end
    if #parts > 0 then log("escort: track: " .. table.concat(parts, "; ")) end
end
function counts(S)
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
function takeOff(S, why)
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
function reopen(S, why)
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
        if RUN.escort then RUN.escort.lost, RUN.dirty = D.round, true end
        if ESUB and ESUB.finish then pcall(ESUB.finish, S, now, false) end      -- (her last lines: sv_escort_subs.lua)
        log(string.format("escort: round %d, the escort FAILED: %s (%d of %d landed, %d lost, %.0f s in)", D.round, why, landedN, total, lostN, secs))
        return
    end
    local pay = math.floor(num(c.reward, 0) + num(c.reward_per_round, 0) * (D.round or 0))
    addCredits(pay, "the escort: CHARLENE and her escorts landed")
    LB.special("escort", true, secs)
    RUN.zfa = { unlocked = true, round = D.round }
    RUN.dirty = true
    hudCallout(t.won, string.format(t.won_sub, specialPay(pay)))
    -- her line on the subtitle strip, then Comona's (sv_escort_subs.lua ESUB.finish; 2026-11-07); with the strip off,
    -- callouts as before, cut at words to subtitle_chars a callout
    local line, parts, cur = tostring(c.subtitle or ""), {}, ""
    local okSub, onStrip = false, false
    if ESUB and ESUB.finish then okSub, onStrip = pcall(ESUB.finish, S, now, true, line) end
    if not (okSub and onStrip == true) then
        for w in line:gmatch("%S+") do
            if #cur > 0 and #cur + 1 + #w > num(c.subtitle_chars, 90) then parts[#parts + 1] = cur; cur = w
            else cur = (#cur > 0 and (cur .. " ") or "") .. w end
        end
        if #cur > 0 then parts[#parts + 1] = cur end
        for i = 1, math.min(#parts, 3) do hudCallout(c.name, parts[i]) end
    end
    log(string.format("escort: round %d, the escort WON: %d of %d landed (%d lost), %.0f s; +%d zollars; CHARLENE: \"%s\"; the ZFA-44 carriers unlocked in the STORE",
        D.round, landedN, total, lostN, secs, pay, line))
end
-- every tick of the operation (the round's: SPC.kinds.escort.tick; the test's: ESC.tick)
function ESC.step(S, now)
    if S.state == "done" then return end
    local dt = math.max(0, math.min(1, now - (S.last or now)))
    S.last = now
    if not heldNow() then S.t = S.t + dt end
    S.flags = flagsNow(S)                                  -- (the legs and slots the build's records set: legSync, stopSpot)
    local L = ec().landing
    local A = her(S)
    for _, B in ipairs(S.ac) do
        local okA, errA = pcall(stepAc, S, B, now)
        if not okA and not B.errSaid then B.errSaid = true; log("escort: " .. B.name .. "'s step error " .. tostring(errA)) end
    end
    if S.test then testLog(S, now) end
    if ESUB and ESUB.tick and not S.test then pcall(ESUB.tick, S, now) end    -- (what they say: sv_escort_subs.lua)
    if A.st == "lost" then return finish(S, now, false, "CHARLENE is down") end
    if not S.test then pcall(escortsTick, S) end
    if A.st == "final" and S.state == "route" then
        S.state = "landing"
        if S.special then S.special.state = "landing" end
        if not S.test then hudCallout(ec().text.final, ec().text.final_sub) end
    end
    if S.state == "landing" and not S.test then pcall(trackLog, S) end
    -- ((2026-11-07) the airfield was "gone" for the rest of the round: closed at her final, open again only once everyone
    -- was down. Now closed to the players only while one of them is within close_km on the final leg or rolling out,
    -- open again reopen_s after nobody is)
    if L.close_airfield then
        local need, td = false, pt(ec().geo.touchdown)
        for _, B in ipairs(S.ac) do
            if B.st == "roll" or (B.st == "final" and B.r and (B.her or ESC.onFinalLeg(B)) and d2(B.r.at, td) <= num(L.close_km, 5) * 1000) then
                need = true
            end
        end
        if need then
            S.needAt = S.t
            if not S.closed then S.closePending = true end
        else
            S.closePending = false
            if S.closed and S.t - (S.needAt or 0) >= num(L.reopen_s, 5) then
                S.closed = false
                if not (AF and (AF.closed or AF.down)) and not RUN.captured then airfield(false, "nobody on short final or the runway") end
            end
        end
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
            pcall(wavesTick, S, now)
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
    -- ((2026-11-07: CHARLENE climbed away from her taxi, 925 m up at 599 km/h when her stop fired) one landed on the
    -- ground that's flying again (climb_off_m over the runway, or faster than climb_off_kmh): switched off, once)
    for _, B in ipairs(S.ac) do
        if not S.test and B.st == "landed" and B.how ~= "timeout" and not B.climbOff then
            local ob = planeOf(B.unit)
            local rb = ob and readPlane(ob)
            local up = rb and (rb.at.Z - num(ec().geo.runway_z, 750)) / 100
            if rb and (up > num(L.climb_off_m, 60) or (rb.kmh or 0) > num(L.climb_off_kmh, 150)) then
                B.climbOff, B.r = true, rb
                if COOP and COOP.removeNow then pcall(COOP.removeNow, B.unit) end
                local n = 0
                for _, e in ipairs(planesOf(B.unit)) do if offObj(e.obj) then n = n + 1 end end
                log(string.format("escort: %s flying again after it landed (%s): %d planes switched off; %s", B.name, tostring(B.how), n, where(B)))
            end
        end
    end
    local landedN, lostN, total = counts(S)
    if A.st == "landed" and landedN + lostN >= total then return finish(S, now, true, "everyone left landed") end
    -- ((2026-11-07) the round no longer waits on the escorts' landings: after_her_s after CHARLENE's down, each one still
    -- up is counted as landed (switched off if it's flying) and the escort's won)
    if not S.test and A.st == "landed" and num(L.after_her_s, 0) > 0 and S.t - (A.since or S.t) >= num(L.after_her_s, 0) then
        local n = 0
        for _, B in ipairs(S.ac) do if B.st ~= "landed" and B.st ~= "lost" then landed(S, B, "timeout"); n = n + 1 end end
        return finish(S, now, true, string.format("%d s after CHARLENE landed: %d still up counted as landed", math.floor(num(L.after_her_s, 0)), n))
    end
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
    if ESC.rowsOk ~= true then                             -- (its escorts' DT_NPC rows: ESC.setup at the main menu)
        if not ESC.rowsSaid then
            ESC.rowsSaid = true
            log("escort: no ESCORT round: its escorts' DT_NPC rows aren't in (" .. (ESC.rowsOk == false and "not added at the main menu"
                or "the main menu's setup hasn't run") .. ")")
        end
        return false
    end
    return unitsThere()
end
-- whether THE ESCORT can still come in this session (on, its rows not refused, its units not missing): the Anomalies
-- wait for her only then (sv_escort_subs.lua ESC.anomalyOk)
function ESC.possible()
    local c = ec()
    return type(c) == "table" and c.enabled ~= false and ESC.rowsOk ~= false and unitsOk ~= false
end
-- (before an operation's spawns) every leg and slot flag back to 0 (RE_SV_EscortReset): the last escort's (or test's)
-- flags never move this one on, and its parking slots count from A again
function reset(S)
    local ok, r = fire("RE_SV_EscortReset", "a new escort")
    S.resetClock = os.clock()
    log("escort: RE_SV_EscortReset " .. (ok and "fired: every leg and slot flag back to 0" or ("NOT fired (" .. ERR(r) .. ")")))
end
function ESC.spawn(now)
    if not nativeReady() then return false end
    local c = ec()
    local S = newOp(now, nil)
    S.special, S.round = D.special, D.round
    reset(S)
    local ok, r = spawnAc(S, her(S), startPose(0, 0))
    if not ok then
        log(string.format("escort: round %d: CHARLENE can't come (%s): no escort this round", D.round, ERR(r)))
        return false
    end
    for _, A in ipairs(S.ac) do
        if A.escort then spawnAc(S, A, startPose(num(A.escort.right_m, 0), num(A.escort.up_m, 0))) end
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
-- (sv_allies.lua's take-offs) THE ESCORT landing here (from her final until everyone left is down; the test T0 too):
-- MOONCHILD, SNIPER and VOID WATCHER 1 take off from the hold spot its taxi passes, so they wait
function ESC.runwayBusy()
    local S = ESC.S
    if not (S and S.D == D and S.state ~= "done") then return false end
    if S.state == "landing" then return true end
    for _, A in ipairs(S.ac) do
        if A.st == "final" or A.st == "roll" or A.st == "taxi" or A.st == "stop" then return true end
    end
    return false
end
-- its NEXT row: her health, her distance, how many have landed
function hpPct(S)
    local o = planeOf(her(S).unit)
    if not o then return nil end
    local okH, h, mh = pcall(function() return o.HealthInternal, o.MaxHealth end)
    if not (okH and type(h) == "number" and type(mh) == "number" and mh > 0) then return nil end
    return math.max(0, math.min(100, math.floor(h / (mh * 10) * 100 + 0.5)))
end
ESC.hpPct = hpPct                                        -- (her lines when she's hit: sv_escort_subs.lua)
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
end  -- (sv_escort.lua's do block goes on in sv_escort_carriers.lua)
