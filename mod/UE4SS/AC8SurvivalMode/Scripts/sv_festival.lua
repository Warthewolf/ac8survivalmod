-- sv_festival.lua: THE FESTIVAL (CFG.specials.festival; FISHING_ROUND_PLAN.md 0; docs/re/FISHING.md 6): the cruise
-- missiles and the air raid siren. Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another
-- part uses is a global of this mod's Lua state, its own helpers stay local.
-- Its geometry, what each spawn makes (FEST.actors), the siren, the round itself (below: "the round") and the test keys
-- (Ctrl+F12 one salvo and the siren, Ctrl+PAGE_UP the festival now; test only).
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
-- (no x: where the world data puts it, SV_Spawn(unit) alone: the formations, the searchlights)
function FEST.spawn(unit, x, y, z, yaw)
    FEST.actors[unit] = { open = true }
    spawningUnit = unit
    local ok, r
    if x == nil then ok, r = pcall(SV_Spawn, unit) else ok, r = pcall(SV_Spawn, unit, x, y, z, yaw) end
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

---------------------------------------------------------------------------------------------------- the round
-- THE FESTIVAL (0.74.0; FISHING_ROUND_PLAN.md 0; SPC.kinds.festival, sv_anomalies.lua): never drawn, it's round
-- F + round_after of the day-night arc (sv_spawn.lua specialFor: FEST.roundIs), at sunset. The host's (or solo):
--   talk     SAL and COMONA CONTROL thank the pilots (text.talk; GONE FISHIN''s team haul in it), ~30 s
--   raid     the air raid siren at the airfield (every game), the four searchlights (their rows in: FEST.lightsReady),
--            the three Tu-160 formations (SV_Spawn with no pose, RE_SV_FestUp_<g> up_after_s on): each launches a salvo
--            as it passes its launch point (within launch_r_km; at the latest its first_launch_<g>, then lap_s, late_s on),
--            the next of its missile units free (hard rule 16: one whose last salvo is off the spawner's list), spawned
--            at the launch point and flown by RE_SV_FestCM_<g><k>; a missile within impact_m of the runway hits it
--            (RE_SV_FestCMHit_<g><k>_<i>, impact_damage off the airfield, unpaid on every game), one shot down pays
--            (sv_main.lua creditKill: FEST.killPay); a salvo all down recycled recycle_after_s on; every bomber down and
--            nothing in the air: the reward; time_limit_s: what's left taken off
--   done     the siren stops, the searchlights go
-- A joiner's (FEST.clientTick): the siren while the host's raid is on (its "rnd" special state), the searchlights'
-- copies switched off at its end, the host's row ("fsx"). Log lines: `festival: ...`.
do
local function cfg() return CFG.specials.festival end
local function tx() return cfg().text or {} end
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local GROUPS = FEST.GROUPS
local function formation(g) return "SV_Unit_Fest" .. g end
FEST.formation = formation
local IS_FORMATION, IS_MISSILE = {}, {}
for _, g in ipairs(GROUPS) do
    IS_FORMATION[formation(g)] = g
    for k = 1, 3 do IS_MISSILE[FEST.unit(g, k)] = g end
end
local function host() return not (COOP and COOP.client and COOP.client()) end
local function fire(ev)
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    return r == 1, r == 1 and "fired" or ("NOT fired: " .. tostring(SV_ERR and SV_ERR[r] or r))
end
-- a line, or one of a list of them ((2026-11-07) more of SAL's and Comona's staff's lines: FISH.pick, never the same
-- twice running under `key`)
local function say(line, vals, key)
    if type(line) == "table" then line = FISH.pick(line, "fest." .. tostring(key or line[1])) end
    if type(line) ~= "string" then return false end
    local who, text = FISH.line(line, vals)
    return SUB.say(who, text)
end
-- every line of text[key], in order: a list of lines, or one of a list of such lists (FISH.seq)
local function sayList(key, vals)
    for _, x in ipairs(FISH.seq(tx()[key], "fest." .. key)) do say(x, vals) end
end
-- ((2026-11-07) the user: "add other Characters like Yorke, Rock, Ali, Danielle into this as well") KMG's lines of
-- text[key], only once CHARLENE has landed at Comona this run (RUN.escort.arrived), an exchange only when nobody in it was
-- shot down in THE ESCORT (RUN.escort.down); nil: none
local function kmgList(key)
    local e = RUN and RUN.escort
    if not (type(e) == "table" and e.arrived) then return nil end
    local down = type(e.down) == "table" and e.down or {}
    local function ok(l) local who = tostring(l):match("^([^|]+)|"); return not (who and down[who]) end
    local out = {}
    for _, x in ipairs(tx()[key] or {}) do
        if type(x) == "table" then
            local all = #x > 0
            for _, l in ipairs(x) do if not ok(l) then all = false end end
            if all then out[#out + 1] = x end
        elseif type(x) == "string" and ok(x) then out[#out + 1] = x end
    end
    return #out > 0 and out or nil
end
local function sayKmg(key)
    local l = kmgList(key)
    if not l then return 0 end
    local n = 0
    for _, x in ipairs(FISH.seq(l, "fest." .. key)) do if say(x) then n = n + 1 end end
    return n
end
local function dirOf(g) return ((tx().dirs or {})[g]) or g end

-- the round THE FESTIVAL is (F + round_after), when the run has a GONE FISHIN'
function FEST.roundIs(round)
    local F = SKY and SKY.arcF and SKY.arcF()
    return F ~= nil and tonumber(round) == F + math.floor(n(cfg().round_after, 6))
end
-- the searchlights' rows in the campaign tables (SPC.alicornSetup: SPC.festRows)
function FEST.lightsReady()
    local fr = SPC and SPC.festRows
    if type(fr) ~= "table" then return false end
    return #fr.lost == 0 and fr.have >= #(cfg().rows or {})
end
-- ((2026-11-07) the user: "Include more Enemy Aircraft in the Festival Mission") fighters with the raid (its kind's budget,
-- sv_anomalies_valka.lua SPC.kinds.festival): fighters_share of the round's aircraft in whole 2-ships, fighters_min ..
-- fighters_max; 0: the bombers alone, as before
function FEST.fighters(budget)
    local c = cfg()
    local share = n(c.fighters_share, 0.7)
    if share <= 0 or not budget then return 0 end
    local k = math.floor(budget * share / 2 + 0.5) * 2
    return math.max(math.floor(n(c.fighters_min, 6)), math.min(math.floor(n(c.fighters_max, 16)), k))
end
function FEST.ready(round, forced)
    local c = cfg()
    if c.enabled == false or not nativeReady() then return false end
    if c.lights_required and not FEST.lightsReady() then return false end
    return true
end
-- (sv_main.lua creditKill) a festival plane's pay: its kind and base, or nil
function FEST.killPay(unit)
    if not unit then return nil end
    if IS_FORMATION[unit] then return "heavy", n(cfg().pay_bomber, 400) end
    if IS_MISSILE[unit] then return "cruise missile", n(cfg().pay_missile, 150) end
    return nil
end
-- (the Spaceport can't come the round before THE FESTIVAL: its retake would fall on it)
do
    local sk = SPC and SPC.kinds and SPC.kinds.spaceport
    if sk and sk.ready then
        local raw = sk.ready
        sk.ready = function(round, ...)
            if round and FEST.roundIs(round + 1) then return false end
            return raw(round, ...)
        end
    end
end

-- the planes of a unit up now (the core's list, its sweep's p.at), and the nearest of them to (x, y) (km)
local function upPlanes(unit)
    local out = {}
    for _, p in ipairs(planes or {}) do if p.unit == unit and not p.down and liveObj(p.obj) then out[#out + 1] = p end end
    return out
end
local function planeOf(addr)
    for _, p in ipairs(planes or {}) do if addr and p.addr == addr then return p end end
    return nil
end

function FEST.roundSpawn(now)
    local s, c = D.special, cfg()
    if not FEST.ready(D.round, true) then log("festival: no festival (" .. (c.enabled == false and "off" or "no native spawner") .. ")"); return false end
    s.state, s.at, s.groups, s.salvos, s.missilesDown, s.impacts, s.said = "talk", now, {}, {}, 0, 0, {}
    local kg = RUN and RUN.fishKg
    for _, line in ipairs(FISH.seq(tx().talk, "fest.talk")) do      -- (one of the talks: FISH.seq)
        if line:find("{kg}", 1, true) and not (kg and kg > 0) then say(tx().talk_nokg or line, { kg = 0 }, "talk_nokg")
        else say(line, { kg = kg and FEST.money(kg) or 0 }) end
    end
    sayKmg("kmg_talk")                                       -- (KMG at the festival, once CHARLENE's landed this run)
    s.talkEnd = now + math.max(5, SUB.left(now))
    pcall(FEST.townUp, "the festival's talk")                -- (the town's boxes: up for the whole festival)
    log(string.format("festival: round %d, THE FESTIVAL at sunset: the pilots thanked (%.0f s; GONE FISHIN''s haul %s kg)",
        D.round, s.talkEnd - now, tostring(kg or "?")))
    return true
end
function FEST.money(x) return (tostring(math.floor(x)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end

local function raidStart(now, s)
    local c, t = cfg(), tx()
    s.state, s.raidAt = "raid", now
    local r0 = c.rwy or {}
    local a, what = FEST.sirenOn({ X = n(r0[1], 0), Y = n(r0[2], 0), Z = n(c.rwy_z, 500) + n(c.siren_up_m, 10) * 100 })
    log("festival: the air raid siren " .. tostring(c.siren) .. ": " .. (a and what or ("NOT on: " .. tostring(what))))
    local lights = {}
    if FEST.lightsReady() then
        for _, u in ipairs(c.lights or {}) do
            if FISH and FISH.clearUnit then FISH.clearUnit(u, "a searchlight") end
            local r = FEST.spawn(u)
            if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, u, r) end
            lights[#lights + 1] = u:match("(%d+)$") .. " " .. (r > 0 and "up" or ("NOT (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")"))
        end
    else
        lights[1] = "none (their rows aren't in)"
    end
    local said = {}
    for _, g in ipairs(GROUPS) do
        local unit = formation(g)
        local r = FEST.spawn(unit)
        if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, unit, r) end
        s.groups[g] = { unit = unit, n = math.max(0, r), up = r > 0, k = 0, launches = 0,
                        due = now + n(c["first_launch_" .. g:lower()], 60), last = nil, downSaid = false }
        if r > 0 and type(queueEvent) == "function" then queueEvent(now + n(c.up_after_s, 2), "RE_SV_FestUp_" .. g, "the festival's " .. g .. " formation") end
        said[#said + 1] = string.format("%s %s", g, r > 0 and (r .. " up") or ("NOT spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")"))
    end
    hudCallout(t.raid_go or "AIR RAID", t.raid_go_sub)
    sayList("raid_town")                                    -- ((2026-11-07) the town as the siren starts)
    sayKmg("kmg_raid")
    s.chatAt = now + n(c.chatter_s, 35)
    log(string.format("festival: the raid: Tu-160s %s; searchlights %s", table.concat(said, ", "), table.concat(lights, ", ")))
end

-- a salvo from group g's next free missile unit; whether it went
local function launch(now, s, G, g, why)
    local c = cfg()
    local free = nil
    for j = 1, 3 do
        local k = (G.k + j - 1) % 3 + 1
        local busy = false
        for _, sl in ipairs(s.salvos) do if sl.g == g and sl.k == k and not sl.freed then busy = true end end
        if not busy and (type(SV_UnitAlive) ~= "function" or SV_UnitAlive(FEST.unit(g, k)) <= 0) then free = k; break end
    end
    if not free then
        if not G.noFreeSaid then                       -- (said once till its next salvo: it's tried again every few seconds)
            G.noFreeSaid = true
            log(string.format("festival: the %s formation's next salvo waits (%s): no missile unit free (all three still up)", g, why))
        end
        return false
    end
    G.noFreeSaid = nil
    local unit = FEST.unit(g, free)
    local x, y, z = FEST.launchPoint(g)
    local r = FEST.spawn(unit, x, y, z, FEST.launchYaw(g))
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, unit, r) end
    G.k, G.launches, G.last = free, G.launches + 1, now
    if r <= 0 then
        log(string.format("festival: the %s formation's salvo %s NOT spawned (%s)", g, unit, tostring(SV_ERR and SV_ERR[r] or r)))
        return false
    end
    local sl = { g = g, k = free, unit = unit, at = now, fireAt = now + 0.5, ms = {} }
    for i, o in ipairs(FEST.actors[unit] or {}) do
        if liveObj(o) then sl.ms[#sl.ms + 1] = { obj = o, addr = addrOf(o), i = i - 1 } end
    end
    s.salvos[#s.salvos + 1] = sl
    local t = tx()
    if G.launches == 1 then say(t.launch or "C|Missile launch from the {dir}!", { dir = dirOf(g) })
    else say(t.launch_again or "C|Another salvo from the {dir}!", { dir = dirOf(g) }) end
    hudCallout(t.launch_callout or "CRUISE MISSILES", string.format(t.launch_callout_sub or "FROM THE %s", dirOf(g):upper()))
    log(string.format("festival: the %s formation's salvo %d (%s, %s): %s, %d missiles seen", g, G.launches, unit, why, r .. " up", #sl.ms))
    return true
end

-- a missile finished off here (its record took another, or it's up too long): no pay
local function finish(m)
    local p = planeOf(m.addr)
    if p and not p.down then p.down, p.cleaned = true, true end
    if COOP and COOP.removeObj then pcall(COOP.removeObj, m.obj) end
    if not liveObj(m.obj) then return end
    pcall(function() m.obj.MinHealth = 0.0 end)
    pcall(function() m.obj:ModifyHealth(-1000, nil, true) end)
end
-- ((code review of 2026-11-07, finding 11) the impact record's i is the spawner's order only if the build's desc order and
-- the spawn's agree (unconfirmed): one naming another missile j destroyed j, which paid as a kill. Now the impacting
-- missile is finished off here at once (the record finds it gone, or takes another), and every other missile of its salvo
-- still up is held unpaid IMPACT_HOLD_S: off the sweep (down and cleaned), its co-op kill sent as a removal (COOP.payHold);
-- one that goes down in the hold was the record's (salvosTick: not counted, not paid), one still up after it is let go
local IMPACT_HOLD_S = 1.5
local function hold(sl, now)
    local n = 0
    for _, m2 in ipairs(sl.ms) do
        if not m2.over and not m2.hitAt and liveObj(m2.obj) then
            local p = planeOf(m2.addr)
            if p and not p.down then p.down, p.cleaned, p.festHeld = true, true, true; m2.p = p end
            if COOP and COOP.payHold then pcall(COOP.payHold, m2.obj, true) end
            m2.holdUntil = now + IMPACT_HOLD_S
            n = n + 1
        end
    end
    return n
end
local function letGo(m)
    m.holdUntil = nil
    local p = m.p
    m.p = nil
    if p and p.festHeld then p.down, p.cleaned, p.festHeld, p.downSeen = false, false, nil, nil end
    if COOP and COOP.payHold then pcall(COOP.payHold, m.obj, false) end
end
FEST.hold, FEST.letGo, FEST.IMPACT_HOLD_S = hold, letGo, IMPACT_HOLD_S
-- one missile on the runway: off the round's list and down on every game unpaid, finished off here, its impact record,
-- the airfield's damage
local function impact(now, s, sl, m, dist, hgt)
    local c = cfg()
    m.hitAt = now
    finish(m)
    local nH = hold(sl, now)
    local ok, said = fire(FEST.hitEvent(sl.g, sl.k, m.i))
    if nH > 0 then said = said .. string.format(" (%d more of its salvo held unpaid %.1f s)", nH, IMPACT_HOLD_S) end
    local dmg = math.floor(n(c.impact_damage, 8))
    if CFG.airfield.enabled and AF and not AF.down and AF.bomb then AF.bomb = AF.bomb + dmg end
    s.impacts = s.impacts + 1
    if now - (s.impactSaidAt or -1e9) >= 20 then
        s.impactSaidAt = now
        local l = tx().impact or {}
        if #l > 0 then say(l[(s.impacts - 1) % #l + 1]) end
    end
    log(string.format("festival: missile %d of %s within %.0f m of the runway (%.0f m up) %.0f s after its launch: %s %s, -%d airfield",
        m.i, sl.unit, dist, hgt, now - sl.at, FEST.hitEvent(sl.g, sl.k, m.i), said, dmg))
end

local function salvosTick(now, s)
    local c = cfg()
    local inAir = 0
    for _, sl in ipairs(s.salvos) do
        if sl.fireAt and now >= sl.fireAt then
            sl.fireAt = nil
            local _, said = fire(FEST.launchEvent(sl.g, sl.k))
            log(string.format("festival: %s: %s", FEST.launchEvent(sl.g, sl.k), said))
        end
        if not sl.over then
            local left = 0
            for _, m in ipairs(sl.ms) do
                if not m.over then
                    local up, h = liveObj(m.obj), nil
                    if up then pcall(function() h = m.obj.HealthInternal end) end
                    if m.hitAt then
                        if now - m.hitAt >= 1.5 then
                            m.over = true
                            if up and not (type(h) == "number" and h <= 0) then
                                finish(m)
                                log(string.format("festival: %s's impact record left missile %d up: finished off here (the record's i may not be "
                                    .. "the spawner's order)", sl.unit, m.i))
                            end
                        else left = left + 1 end
                    elseif m.holdUntil and (not up or (type(h) == "number" and h <= 0)) then
                        -- (down in its salvo's impact hold: the record's, not a kill; its sweep entry stays down, unpaid)
                        m.over, m.holdUntil, m.p = true, nil, nil
                        s.recordTook = (s.recordTook or 0) + 1
                        log(string.format("festival: missile %d of %s went down within %.1f s of its salvo's impact record: the record's "
                            .. "(its i not the spawner's order), not paid", m.i, sl.unit, IMPACT_HOLD_S))
                    elseif not up or (type(h) == "number" and h <= 0) then
                        m.over = true
                        s.missilesDown = s.missilesDown + 1
                        if not s.said.shot then s.said.shot = true; say(tx().shot_first or "S|You shot it!") end
                        log(string.format("festival: missile %d of %s shot down %.0f s after its launch", m.i, sl.unit, now - sl.at))
                    elseif now - sl.at >= n(c.missile_s, 200) then
                        m.over = true
                        if m.holdUntil then letGo(m) end
                        finish(m)
                        log(string.format("festival: missile %d of %s up %d s: taken off", m.i, sl.unit, math.floor(n(c.missile_s, 200))))
                    else
                        if m.holdUntil and now >= m.holdUntil then letGo(m) end   -- (up after its salvo's hold: paid again)
                        local okL, l = pcall(function() local v = m.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
                        if okL and l then
                            local dist, hgt = FEST.toRunway(l)
                            if host() and dist <= n(c.impact_m, 400) and now - sl.at >= 5 then impact(now, s, sl, m, dist, hgt) end
                        end
                        left = left + 1
                    end
                end
            end
            if left == 0 and not sl.fireAt then sl.over, sl.recycleAt = true, now + n(c.recycle_after_s, 3) end
            inAir = inAir + left
        end
        if sl.over and not sl.freed and now >= (sl.recycleAt or now) then
            sl.freed = true
            local n0 = type(SV_UnitAlive) == "function" and SV_UnitAlive(sl.unit) or -5
            local okR, r = false, "no SV_Recycle"
            if type(SV_Recycle) == "function" then crumb("festival: SV_Recycle " .. sl.unit); okR, r = pcall(SV_Recycle, sl.unit, 1) end
            FEST.actors[sl.unit] = nil
            log(string.format("festival: %s off the spawner's list (%d alive): SV_Recycle %s", sl.unit, n0, okR and tostring(r) or ("error " .. tostring(r))))
        end
    end
    local keep = {}
    for _, sl in ipairs(s.salvos) do if not sl.freed then keep[#keep + 1] = sl end end
    s.salvos = keep
    s.inAir = inAir
    return inAir
end

-- the raid's end: the siren off, the searchlights off, what's left taken off (`why`)
local function raidEnd(now, s, why, saved)
    local c, t = cfg(), tx()
    s.state = "done"
    local nS, wS = FEST.sirenOff(why)
    local lightsOff = FEST.lightsOff(why)
    if saved then
        local pay = math.floor(n(c.reward, 0) + n(c.reward_per_round, 0) * (D.round or 0))
        if pay > 0 then addCredits(pay, "the festival saved") end
        sayList("all_down")
        sayList("saved_town")                               -- ((2026-11-07) the town, saved)
        sayKmg("kmg_saved")
        hudCallout(t.saved or "THE FESTIVAL IS SAVED", string.format(t.saved_sub or "+%d ZOLLARS", specialPay and specialPay(pay) or pay))
    else
        sayList("timeout")
        hudCallout(t.over or "THE RAID IS OVER", nil)
    end
    if LB and LB.special then pcall(LB.special, "festival", saved == true, now - (s.at or now)) end
    log(string.format("festival: round %d: the raid over (%s) %.0f s in: %d missiles shot down, %d on the runway; the siren off (%s, %d); %d searchlights off",
        D.round, why, now - (s.raidAt or now), s.missilesDown or 0, s.impacts or 0, tostring(wS), nS or 0, lightsOff))
end
-- the searchlights here switched off (TurnOff, hidden: allies, never finished off); the town's boxes with them
function FEST.lightsOff(why)
    local nOff = 0
    for _, u in ipairs(cfg().lights or {}) do
        for _, o in ipairs((SPC and SPC.CLEAN_OBJ and SPC.CLEAN_OBJ[u]) or {}) do
            if liveObj(o) then
                pcall(function() o:TurnOff() end)
                if FISH and FISH.hide then FISH.hide(o) end
                nOff = nOff + 1
            end
        end
    end
    if FEST.townOff then pcall(FEST.townOff, why) end
    return nOff
end

-- ((2026-11-07) the user: "Add some Allied Target Boxes in the town next to the airfield", VALKA and AUDREY side by side,
-- the concert, market stalls, food trucks and the rest; "they can just be invincible dummies") the build's unit of
-- invisible, invincible allied dummies in the town (cfg().town; tools/survival_events.py FEST_TOWN_*), each box its own
-- callsign key: their names (tx().town) set, up with the festival's talk, off at its end with the searchlights
local function townCfg() local t = cfg().town; return type(t) == "table" and t.enabled ~= false and type(t.unit) == "string" and t or nil end
function FEST.townNames()
    if type(SV_SetText) ~= "function" then return 0 end
    local n = 0
    for key, text in pairs(tx().town or {}) do
        if type(key) == "string" and type(text) == "string" and SV_SetText(key, text) == 1 then n = n + 1 end
    end
    return n
end
function FEST.townUp(why)
    local t = townCfg()
    if not t then return nil end
    local nN = FEST.townNames()
    if FISH and FISH.clearUnit then FISH.clearUnit(t.unit, "the festival's town") end
    local r = FEST.spawn(t.unit)
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, t.unit, r) end
    local inv = 0
    for _, o in ipairs(FEST.actors[t.unit] or {}) do      -- (the build's invincible already; the run's say so too)
        if liveObj(o) then
            pcall(function() o.bIsInvincible = true end)
            if pcall(function() o:SetIsInvincible(true) end) then inv = inv + 1 end
        end
    end
    log(string.format("festival: the town's boxes %s (%s; %d names set, %d made invincible here)",
        r > 0 and (r .. " up") or ("NOT up (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")"), tostring(why), nN, inv))
    return r
end
function FEST.townOff(why)
    local t = townCfg()
    if not t then return 0 end
    local nOff = 0
    for _, o in ipairs((SPC and SPC.CLEAN_OBJ and SPC.CLEAN_OBJ[t.unit]) or {}) do
        if liveObj(o) then
            if FISH and FISH.hide then FISH.hide(o) end
            nOff = nOff + 1
        end
    end
    if nOff > 0 then log(string.format("festival: the town's %d boxes switched off here (%s)", nOff, tostring(why))) end
    return nOff
end

-- ((2026-11-08) the user: "the Enemy Aircraft that spawn in during the Festival Special Round, they need to spawn WITH the
-- TU-160's not beforehand") the round's fighter flights held while the festival's talk is on (its special kind's hold,
-- sv_rounds.lua's spawn loop): they come with the raid; at most hold_max_s, whatever happens
function FEST.hold(now, s)
    return s ~= nil and s.state == "talk" and now - (s.at or now) < n(cfg().hold_max_s, 180)
end
-- ((2026-11-08) "the Festival isn't saved until all Enemy Aircraft are dealt with") the round's enemy aircraft still to
-- come or up: its flights up (D.up, ALIVE.ask) and every flight waiting in its waves (the festival's own units aren't
-- the round's flights)
local function fightersLeft(now)
    local left = 0
    for u in pairs((D and D.up) or {}) do
        local okA, a = pcall(ALIVE.ask, u, now)
        if okA and type(a) == "number" and a > 0 then left = left + a end
    end
    for i = (D and D.wave) or 1, #((D and D.waves) or {}) do
        for _, q in ipairs(D.waves[i] or {}) do
            if type(q) == "string" and q:sub(1, 1) ~= "@" then left = left + (type(flightSize) == "function" and flightSize(q) or 2) end
        end
    end
    return left
end
FEST.fightersLeft = fightersLeft
-- a line of the town's chatter (the raid's, or after it: after_chatter), KMG's among them once CHARLENE's landed
local function chatter(key, kmgKey)
    local pool = tx()[key]
    local k = kmgList(kmgKey)
    if k and type(pool) == "table" then
        local all = {}
        for _, x in ipairs(pool) do all[#all + 1] = x end
        for _, x in ipairs(k) do all[#all + 1] = x end
        pool = all
    end
    return say(pool, nil, key)
end
function FEST.roundTick(now, s)
    if levelGoing() then return end
    local c = cfg()
    if s.state == "talk" then
        if now >= (s.talkEnd or now) then raidStart(now, s) end
    elseif s.state == "done" and D and D.state == "wait" and c.break_chatter ~= false then
        -- ((2026-11-08) the user: "Dialogue from Fesitival Round can run till the end of the 60 second timer") the town
        -- talks on through the break after its round (after_chatter): a line every break_chatter_s once the strip is
        -- clear, the last one done before the next round's start
        local left, busy = (tonumber(D.at) or now) - now, SUB.left(now)
        local line = n((CFG.hud.subs or {}).line_s, 4)
        if now >= (s.chatAt or 0) and busy <= 0.5 and left >= line + 1 then
            s.chatAt = now + n(c.break_chatter_s, 10)
            if chatter("after_chatter", "kmg_after") then s.breakLines = (s.breakLines or 0) + 1 end
        end
    elseif s.state == "raid" and now >= (s.checkAt or 0) then
        s.checkAt = now + 0.5
        s.groups, s.salvos = s.groups or {}, s.salvos or {}
        local bombers = 0
        for _, g in ipairs(GROUPS) do
            local G = s.groups[g]
            if G and G.up then
                local ps = upPlanes(G.unit)
                local alive = type(SV_UnitAlive) == "function" and SV_UnitAlive(G.unit) or #ps
                if alive < 0 then alive = #ps end
                G.alive = alive
                -- ((2026-11-07) the row read 24 with 12 Tu-160s up: SV_UnitAlive counts each plane's parts too; the
                -- planes themselves, when they're known)
                bombers = bombers + ((alive <= 0) and 0 or (#ps > 0 and math.min(#ps, alive) or alive))
                if alive <= 0 and now - s.raidAt >= 5 then
                    if not G.downSaid then
                        G.downSaid = true
                        say(tx().formation_down or "C|The {dir} formation is down.", { dir = dirOf(g) })
                        log(string.format("festival: the %s formation is down (%d salvos)", g, G.launches))
                    end
                else
                    local lx, ly = FEST.launchPoint(g)
                    local near = false
                    for _, p in ipairs(ps) do
                        if p.at and lx then
                            local dx, dy = p.at.X - lx, p.at.Y - ly
                            if math.sqrt(dx * dx + dy * dy) / 100000 <= n(c.launch_r_km, 3) then near = true end
                        end
                    end
                    -- ((2026-11-07) the user: "have the Bombers continually launching Cruise Missiles until the bombers
                    -- are killed": a salvo every salvo_every_s while the formation's up (its first over its launch point,
                    -- or first_launch_<g> on), the next of its three missile units once one is free; none free: again
                    -- retry_s on)
                    local first = G.launches == 0
                    if ((first and near) or now >= G.due) and now - (G.last or -1e9) >= n(c.launch_gap_s, 30) then
                        local ok = launch(now, s, G, g, (not first and "its next salvo") or (near and "over its launch point")
                                                        or "its clock (its pass not seen)")
                        G.due = now + (ok and n(c.salvo_every_s, 30) or n(c.retry_s, 5))
                    end
                end
            end
        end
        s.bombers = bombers
        -- ((2026-11-07) the town now and then: a line of chatter every chatter_s, when the strip has room)
        if now >= (s.chatAt or 0) and SUB.left(now) <= 4 then
            s.chatAt = now + n(c.chatter_s, 35)
            chatter("chatter", "kmg_chatter")
        end
        local inAir = salvosTick(now, s)
        local started = false
        for _, g in ipairs(GROUPS) do if s.groups[g] and s.groups[g].up then started = true end end
        local fighters = c.saved_needs_fighters == false and 0 or fightersLeft(now)
        s.fighters = fighters
        if bombers == 0 and inAir == 0 and fighters > 0 and started and now - s.raidAt >= 5 and not s.fightersSaid then
            s.fightersSaid = true                           -- (the bombers down, their fighters not: not saved yet)
            local t = tx()
            hudCallout(t.bombers_down or "THE BOMBERS ARE DOWN", string.format(t.bombers_down_sub or "SHOOT DOWN THE LAST %d FIGHTERS", fighters))
            log(string.format("festival: round %d: every bomber and missile down, %d enemy aircraft left: not saved until they are", D.round, fighters))
        end
        if (bombers == 0 and inAir == 0 and fighters == 0 and now - s.raidAt >= 5) or not started then
            raidEnd(now, s, started and "every bomber and every enemy aircraft down" or "no bomber came", started)
        elseif now - s.raidAt >= n(c.time_limit_s, 900) then
            local list = {}
            for _, g in ipairs(GROUPS) do
                list[#list + 1] = formation(g)
                for k = 1, 3 do list[#list + 1] = FEST.unit(g, k) end
            end
            for _, u in ipairs(list) do if COOP and COOP.host and COOP.host() and COOP.removeNow then pcall(COOP.removeNow, u) end end
            SPC.cleanUp(list, "the festival's raid timed out", true, now)
            raidEnd(now, s, string.format("%d s: the time limit", math.floor(n(c.time_limit_s, 900))), false)
        end
    end
    if COOP and COOP.specialRow and now >= (s.rowAt or 0) then
        s.rowAt = now + 1
        COOP.specialRow("festival", s.state, s.bombers or 0, s.inAir or 0, s.fighters or 0)
    end
end
function FEST.busy(s) return s.state ~= "done" end
function FEST.roundOver(now, s)
    if s.state ~= "done" then raidEnd(now, s, "the round ended", false) end
end
function FEST.row(s, t)
    local x = tx()
    if s.state == "talk" then return x.row_talk end
    if s.state ~= "raid" then return nil end
    return string.format(x.row or "THE FESTIVAL  BOMBERS: %d  FIGHTERS: %d  MISSILES IN THE AIR: %d", s.bombers or 0, s.fighters or 0, s.inAir or 0)
end

-- A co-op joiner's: the siren with the host's raid, the searchlights' copies off at its end, the host's row
local CL = { siren = false, on = false }
function FEST.clientTick(now)
    if not (COOP and COOP.client and COOP.client() and D) then return end
    local hs = D.hostSpecial
    local raid = hs and hs.kind == "festival" and hs.state == "raid"
    if raid and not CL.siren then
        CL.siren = true
        local c, r0 = cfg(), cfg().rwy or {}
        local a, what = FEST.sirenOn({ X = n(r0[1], 0), Y = n(r0[2], 0), Z = n(c.rwy_z, 500) + n(c.siren_up_m, 10) * 100 })
        log("festival: the host's raid: the air raid siren here: " .. (a and what or ("NOT on: " .. tostring(what))))
    elseif not raid and CL.siren then
        CL.siren = false
        local nS, wS = FEST.sirenOff("the host's raid is over")
        log("festival: the host's raid is over: the siren off here (" .. tostring(wS) .. ", " .. tostring(nS) .. ")")
    end
    local on = hs and hs.kind == "festival" and hs.state ~= "done"
    if on and not CL.on then pcall(FEST.townNames) end     -- (the town's box names here too, as the host's festival starts)
    if on then CL.on = true
    elseif CL.on then
        CL.on = false
        log(string.format("festival: the host's festival is over: %d searchlight copies off here", FEST.lightsOff("the host's festival is over")))
    end
end
function FEST.clientRow(t)
    if not (COOP and COOP.client and COOP.client() and D and FISH and FISH.cl) then return nil end
    local hs, r = D.hostSpecial, FISH.cl.rows.festival
    if not (hs and hs.kind == "festival" and hs.state ~= "done" and r and os.clock() - r.at < 5) then return nil end
    local x = tx()
    if r.state == "talk" then return x.row_talk end
    if r.state ~= "raid" then return nil end
    return string.format(x.row or "THE FESTIVAL  BOMBERS: %d  FIGHTERS: %d  MISSILES IN THE AIR: %d", math.floor(r.a), math.floor(r.c), math.floor(r.b))
end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the festival round"] = function() CL.siren, CL.on = false, false end end
-- ((code review of 2026-11-07, finding 3) a pause-menu restart (sv_main.lua's level-load block): the siren is our own
-- actor, never the mission's, so a restart mid-raid left it looping all the next run, and the searchlights on; both off
-- now, a joiner's watch of the host's raid forgotten. What it did
function FEST.restart(why)
    why = tostring(why or "the run starts over")
    local nS, wS = FEST.sirenOff(why)
    local nL = FEST.lightsOff(why)
    local was = CL.siren or CL.on
    CL.siren, CL.on = false, false
    if wS ~= "no siren" or nL > 0 or was then
        log(string.format("festival: %s: the siren off (%s, %d), %d searchlights off", why, tostring(wS), nS or 0, nL))
    end
    return nS, nL
end
end

-- TEST ONLY BEGIN
-- Ctrl+F12 in a run (the host's or solo): one cruise missile salvo and the siren (docs/re/FISHING.md 7, test 4).
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

-- TEST ONLY BEGIN
-- Ctrl+PAGE_UP in a run (the host's or solo): THE FESTIVAL next (in the break: it starts in 3 s), the arc's F set so that
-- round is F + round_after (the sky blends to the sunset's; GONE FISHIN' counted as done this run)
testKey("PAGE_UP", "sv_festival.lua's THE FESTIVAL now", function()
    if not (D and D.now) or not nativeReady() then log("test: Ctrl+PAGE_UP outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("test: Ctrl+PAGE_UP: the host starts the rounds (you're a joiner)"); return end
    local target = D.round + 1
    local F = target - math.floor(tonumber(CFG.specials.festival.round_after) or 6)
    RUN.fished = RUN.fished or F
    -- ((2026-11-07) an F under 1 was clamped to 1, so an early test round flew at F+1, not the sunset: F may be
    -- under 1 for a test, its round still F + round_after)
    if SKY and SKY.arcSet then SKY.arcSet(math.max(-20, F), "test key Ctrl+PAGE_UP") end
    D.forceSpecial = "festival"
    local soon = D.state == "wait"
    if soon then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
    hudCallout("TEST: THE FESTIVAL", soon and "STARTING NOW" or "NEXT ROUND")
    log(string.format("test: Ctrl+PAGE_UP, round %d is THE FESTIVAL (the arc's F %d; %s)", target, math.max(-20, F),
        soon and "starting in 3 s" or "after this round"))
end)
-- TEST ONLY END
