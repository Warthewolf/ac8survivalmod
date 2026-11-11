-- sv_rounds.lua: the shuttle countdown, the specials' tick, starting and running rounds, the airfield.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- The other players flying, for the log (othersFlying's count).
local function flyingText(n) return n == 1 and "1 other player flying" or (n .. " other players flying") end

-- The shuttle's countdown clock (D.shuttleClock: cd seconds run, fired the last second's event): it runs on the game
-- clock except while you're down at the airfield (D.grounded, from roundsTick) with no other co-op player flying (a
-- co-op host's runs on while another player flies, as the spawns do: D.othersFlying, from roundsTick's othersFlying;
-- user, 2026-10-29: "Keep it running while others are flying"), and fires RE_SV_ShuttleT_<s> for each whole second s
-- (tools/survival_events.py build_shuttle: radio, ignition, liftoff at countdown_s, the climb after it) up to
-- countdown_s + 30; it stops when the shuttle is lost. While the countdown is held the shuttle can't be hurt (user,
-- 2026-10-23: "Make the shuttle invulnerable while the countdown is held"; LiveGameObject.SetIsInvincible): running
-- again (your takeoff, or another player flying while you're still down), it can be hit again.
-- (why: what the log says it's for, the countdown's hold by default; SPC.shuttleReplayStart's own)
function SPC.shuttleInvincible(on, why)
    if not liveObj(SHUTTLE.obj) then shuttleHealth() end         -- (finds the shuttle's actor) ((0.73.84) liveObj: kept)
    if not liveObj(SHUTTLE.obj) then return false end
    local ok = pcall(function() SHUTTLE.obj:SetIsInvincible(on) end)
    log(string.format("special: shuttle %s%s", why or (on and "invulnerable while the countdown is held" or "can be hit again"),
        ok and "" or " (SetIsInvincible failed)"))
    return ok
end

function SPC.shuttleClockTick(now)
    local k = D.shuttleClock
    if not k then return end
    local dt = math.max(0, now - k.at)
    k.at = now
    local others = D.grounded and (D.othersFlying or 0) or 0
    local held = D.grounded and others == 0 or false
    if not held then k.cd = k.cd + dt end
    -- (logged when it's held, runs, or runs with you down: not as the number of others flying changes)
    local mode = held and "held" or D.grounded and "down" or "running"
    if mode ~= k.mode then
        k.mode = mode
        log(string.format("special: shuttle countdown %s at %.0f s", held and "held (you're down at the airfield)"
            or D.grounded and string.format("running while you're down at the airfield (%s)", flyingText(others))
            or "running", k.cd))
    end
    local want = (held and not k.s.lost and k.s.state == "countdown") or false   -- (not after liftoff)
    if want ~= (k.inv or false) and SPC.shuttleInvincible(want) then k.inv = want end
    local T = CFG.specials.shuttle.countdown_s
    local last = T + 30
    while k.fired < math.min(math.floor(k.cd), last) do
        k.fired = k.fired + 1
        local name = "RE_SV_ShuttleT_" .. k.fired
        local r
        -- ((2026-11-11) the tail after liftoff while this game's own liftoff is replayed, SPC.shuttleReplayTick: sent
        -- on to the other players, whose shuttles lifted off on time, and not fired here, where the replay fires its
        -- own at their offsets from its liftoff; here the climb's second leg would have flown the shuttle off its pad)
        if D.shuttleReplay and k.fired > T then
            r = COOP and COOP.eventThere and COOP.eventThere(name) or 0
            if not k.tailSaid then
                k.tailSaid = true
                log(string.format("special: shuttle countdown's tail (%s on) %s: this game's liftoff is replayed", name,
                    r == 1 and "sent to the other players, not fired here" or "not fired"))
            end
            r = 1
        else
            r = type(SV_Event) == "function" and SV_Event(name) or -5
        end
        -- (running with you down, your landing menu may be up: the first one not fired is logged, once a clock. A 1 says
        -- it was sent, not that its records ran: the lift-off line's "event package" or "countdown over" tells. They
        -- don't take there: SPC.shuttleReplayTick)
        if r ~= 1 and D.grounded and not k.downErr then
            k.downErr = true
            log(string.format("special: shuttle countdown event RE_SV_ShuttleT_%d not fired (%s) while you're down at the "
                .. "airfield", k.fired, SV_ERR[r] or tostring(r)))
        end
    end
    if k.fired >= last or k.s.lost then
        if k.inv then SPC.shuttleInvincible(false) end
        D.shuttleClock = nil
    end
end
-- (its liftoff replayed when the countdown ran out without it, its removal fired again, the pad watched after it:
-- sv_rounds_shuttle.lua, the next piece)

-- Taking the shuttle and its pad off (with RE_SV_ShuttleRemove). That event's LiveSetActiveGameObjectExecution switches
-- nothing off (a run of 2026-10-24: fired, result 1, and the shuttle, the pad's 9 dummies and its guns were still up
-- every round after), so Lua does it: the shuttle is killed (no longer invincible, MinHealth 0, GameplayStatics.
-- ApplyDamage) so its unit is down and SV_Spawn brings a fresh one next time, and it and everything at the pad
-- (the pad units' objects as spawned, SHUTTLE.pad, and anything else within 1.5 km of SHUTTLE.padAt; not aircraft:
-- the pad reaches 2 km out) is hidden, without collision, target box, lock or targeting, invincible
-- and not ticking. The pad's objects come back as they were at the next shuttle round (spawnShuttle: their units are
-- still up, so they aren't spawned again).
do
-- ((0.73.79, the lag audit's item 7) LiveAIGameObject only: the ground dummies and ground vehicles are its subclasses
-- (the clean-up's LiveAIGameObject feed records both: the shuttle pad's dummies, the Alicorn's turret parts), so the
-- other two walks (35-70 ms each on a tester's PC) only found the same objects again)
local GROUND = { "LiveAIGameObject" }
local FLAGS = { "bShowHUDBox", "bIsNotLockonTarget", "bIsNotFCSTargets", "bIsInvincible" }
local GONE = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }
local function hide(o, keep)
    -- ((0.73.84) with its full name: shuttlePadBack touches it again only while it's live under that name)
    local nm = nameOf(o)
    local was = { obj = o, name = nm ~= "?" and nm or nil }
    for _, f in ipairs(FLAGS) do
        pcall(function() was[f] = o[f] end)
        pcall(function() o[f] = GONE[f] end)
    end
    local n = 0
    for _, f in ipairs({ function() o:SetActorHiddenInGame(true) end, function() o:SetActorEnableCollision(false) end,
                         function() o:SetActorTickEnabled(false) end }) do
        if pcall(f) then n = n + 1 end
    end
    if keep then SHUTTLE.gone[#SHUTTLE.gone + 1] = was end
    return n == 3
end
-- ((0.73.80) padOnly: the pad alone, the shuttle not looked for: a shuttle round whose shuttle never came, SPC.unplan)
function SPC.shuttleTakeOff(padOnly)
    SHUTTLE.gone = SHUTTLE.gone or {}
    local sh, killed, hidden, failed = SHUTTLE.obj, "no shuttle actor", 0, 0
    if padOnly then sh, killed = nil, "never came (the pad only)"
    elseif not liveObj(sh) then shuttleHealth(); sh = SHUTTLE.obj end   -- ((0.73.84) liveObj: kept between ticks)
    local f = svFlags() or {}
    if liveObj(sh) and (f.SV_ShuttleLaunched or 0) < 1 then  -- (a kill now would count as shot down on the pad)
        killed = "not killed (SV_ShuttleLaunched is 0)"
        if hide(sh, false) then hidden = hidden + 1 else failed = failed + 1 end
    elseif liveObj(sh) then
        pcall(function() sh:SetIsInvincible(false) end)
        pcall(function() sh:SetMinHealth(0.0) end)
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local ok = valid(gs) and pcall(function() gs:ApplyDamage(sh, 100000000.0, nil, nil, nil) end)
        killed = ok and "damage applied" or "ApplyDamage failed"
        if hide(sh, false) then hidden = hidden + 1 else failed = failed + 1 end
    end
    -- the pad's own objects, as SV_Spawn made them (spawnShuttle), then anything else near the pad
    local seen, rec = {}, 0
    for _, l in pairs(SHUTTLE.pad or {}) do
        for _, o in ipairs(l) do
            local a = liveAddr(o)                       -- ((0.73.84) kept since its spawn: liveAddr, not valid())
            if a and not seen[a] then
                seen[a], rec = true, rec + 1
                if hide(o, true) then hidden = hidden + 1 else failed = failed + 1 end
            end
        end
    end
    local at = SHUTTLE.padAt
    if at then
        local planeCls = StaticFindObject("/Script/Live.LiveAIPlane")
        for _, cls in ipairs(GROUND) do
            for _, o in ipairs(FindAllOf(cls) or {}) do
                local a = valid(o) and addrOf(o)
                if a and not seen[a] then
                    seen[a] = true
                    -- ((0.73.79) where it is first: the name and class read only for what's near the pad)
                    local okL, l = pcall(function() local v = o:K2_GetActorLocation(); return { X = v.X, Y = v.Y } end)
                    if okL and l and math.sqrt((l.X - at.X) ^ 2 + (l.Y - at.Y) ^ 2) <= 150000
                        and not nameOf(o):find("Default__", 1, true) then
                        local okP, isPlane = pcall(function() return valid(planeCls) and o:IsA(planeCls) end)
                        if not (okP and isPlane) then
                            if hide(o, true) then hidden = hidden + 1 else failed = failed + 1 end
                        end
                    end
                end
            end
        end
    end
    log(string.format("special: shuttle and pad off: the shuttle %s; %d objects hidden (%d of them the pad's own, as spawned)%s%s",
        killed, hidden, rec, failed > 0 and string.format(", %d only partly", failed) or "",
        (at or rec > 0) and "" or " (the pad's spot unknown: the shuttle only)"))
    -- ((0.74.22) the user's co-op run of 2026-11-08, a joiner's log: "this space centre hasn't despawned") the pad is only
    -- hidden here, its units kept up for the next shuttle round, so the host's picture still held them: a joiner who came
    -- in at round 4 got the whole pad, up and shown (9 + 11 objects bound to the host's ids, 08:55:53), and one there for
    -- the round kept its copies shown too (nothing on a joiner's game hides them). The host: the pad's copies off on every game (COOP.removeNow: an ally's copy
    -- is switched off there, not finished off, and its unit taken off that game's spawner list) and out of the picture
    -- the host sends a joiner; spawnShuttle announces them again when the pad comes back (COOP.hostBack)
    local sc = CFG.specials and CFG.specials.shuttle or {}
    if COOP and COOP.removeNow then
        for _, u in ipairs({ sc.dummies or false, sc.pad or false }) do
            if type(u) == "string" and u ~= "" then
                local okR, errR = pcall(COOP.removeNow, u)
                if not okR then log("special: the pad's copies off the joiners' games: error " .. tostring(errR)) end
            end
        end
    end
end
-- the pad's objects back as they were (the next shuttle round)
function SPC.shuttlePadBack()
    local n = 0
    for _, w in ipairs(SHUTTLE.gone or {}) do
        local o = w.obj
        -- ((0.73.84, the review of the crash-on-quit fix) kept since its take-off: touched only while live under the name
        -- it had (valid() reads a freed one; the level's teardown forgets the list: LEVEL_DROPS below)
        if liveObj(o) and (w.name == nil or nameOf(o) == w.name) then
            pcall(function() o:SetActorHiddenInGame(false) end)
            pcall(function() o:SetActorEnableCollision(true) end)
            pcall(function() o:SetActorTickEnabled(true) end)
            for _, f in ipairs(FLAGS) do if w[f] ~= nil then pcall(function() o[f] = w[f] end) end end
            n = n + 1
        end
    end
    if SHUTTLE.gone and #SHUTTLE.gone > 0 then log(string.format("special: the pad's %d objects back", n)) end
    SHUTTLE.gone = {}
end
-- ((0.73.84, the review of the crash-on-quit fix) the pad's objects hidden (SHUTTLE.gone), the pad as spawned (SHUTTLE.pad)
-- and the shuttle (SHUTTLE.obj) are the level's: forgotten untouched as it's torn down (sv_core.lua levelGate). They were
-- kept across a quit, and the next run's first shuttle round (spawnShuttle -> shuttlePadBack) read the old level's freed
-- actors with valid() and wrote their flags back (Shazzy's run of 2026-11-04 hid 20 of them in round 12 before quitting).
-- A restart keeps its level and never closes the gate: its hidden pad still comes back.
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the shuttle pad"] = function()
        SHUTTLE.gone, SHUTTLE.pad, SHUTTLE.obj, SHUTTLE.padSpawning = {}, nil, nil, nil
    end
end
end

---------------------------------------------------------------------------------------------------- the specials' clean-up
-- (0.73.77, plan D4; IMPROVEMENTS.md "Specials and variety" 1: "one clean-up for every special") When a special ends,
-- everything it spawned is taken down. What it left behind killed players rounds later in the 0.73.76 runs: the Ladons'
-- VLS launchers hit mobi118 in rounds 39-46 (Ladons in round 10), VALKA's sure-kill railgun part (RailGunCK) dukka in
-- rounds 26 and 28 (VALKA in round 16), the Alicorn's VLS and AA guns two players in rounds 43 and 46 (round 42); and
-- VALKA's opener railgun SV_Unit_ValkaEml read "1 of 1 alive" to the end of every run: RE_SV_ValkaEmlRemove's
-- LiveDestroyUnitExecution kills through damage, which it never takes (setGone made it invincible, SPC.V.mark kept its
-- target box on: the white square left on the minimap after her fight). So every object SV_Spawn makes for a special's
-- unit is recorded (spawningUnit, as sv_ladon.lua's LADON_PARTS), and at its end each one still up is finished off the
-- way ladonPartsDown does (mortal, MinHealth 0, ModifyHealth / ApplyDamage with no attacker: no pay; a plane of it off
-- the round's list first), else switched off (SetActive false, no box / lock / targeting, hidden, no collision, no tick).
-- CLEAN_CHECK_S later SV_UnitAlive is asked again: a unit still up is taken off the native list (SV_Recycle(unit, 1),
-- when the runtime has it) and logged. The Alicorn's parked pools (put away for good: sv_alicorn.lua) are left to that.
-- A co-op joiner's copies (SPC.clientClean, below): switched off only, never killed there (a copy's kill is the host's),
-- once the host's special is over ("rnd" field 11, sv_coop.lua: D.hostSpecial).
do
local CLEAN_AFTER_S, CLEAN_CHECK_S, CLIENT_AFTER_S, MAX_OBJS = 3, 2, 5, 400
local SHUTTLE_CLIENT_S = 15                      -- ((0.73.80) a joiner's shuttle copy: after the host's own removal ran here)
local POOLED = { "_uavm_ON_", "_rflm_ON_", "_f18f_ON_", "_uavr_" }       -- (the Alicorn's parked pools, sv_alicorn.lua)
local ALICORN_UNIT, LADON_UNITS = "SV_Unit_Alicorn", { "SV_Unit_LadonKot", "SV_Unit_LadonMishka" }
local function str(v) return type(v) == "string" and v ~= "" and v or nil end
-- a special kind's units (each a name its round spawns)
function SPC.cleanUnitsOf(kind)
    local c = CFG.specials or {}
    local function u(t, k) return type(t) == "table" and str(t[k]) or nil end
    local out = {}
    local function add(x) if x then out[#out + 1] = x end end
    if kind == "valka" then add(u(c.valka, "unit")); add(u(c.valka, "eml_unit"))
    elseif kind == "anomaly" then add(u(c.anomaly, "unit"))
    elseif kind == "glitch" then add(u(c.glitch, "unit"))
    elseif kind == "ladon" then for _, x in ipairs(LADON_UNITS) do add(x) end
    elseif kind == "alicorn" then add(ALICORN_UNIT)
    elseif kind == "decoy" and DECOY and DECOY.cleanUnits then for _, x in ipairs(DECOY.cleanUnits()) do add(x) end
    -- ((0.74.0) GONE FISHIN''s shoals, THE FESTIVAL's formations and missiles: finished off at their end; SAL's boat and
    -- the searchlights are allies, switched off by their own parts, never finished off)
    elseif kind == "fishing" and type(c.fishing) == "table" then for _, x in ipairs(c.fishing.units or {}) do add(str(x)) end
    elseif kind == "festival" then
        for _, g in ipairs({ "N", "W", "S" }) do
            add("SV_Unit_Fest" .. g)
            for k = 1, 3 do add("SV_Unit_FestCM_" .. g .. k) end
        end
    end
    return out
end
-- what a unit is called in the log
function SPC.cleanLabel(unit)
    local c = CFG.specials or {}
    if type(c.valka) == "table" and unit == c.valka.eml_unit then return tostring(c.valka.name or "VALKA") .. "'s opener railgun" end
    for _, k in ipairs({ "valka", "anomaly", "glitch" }) do
        if type(c[k]) == "table" and unit == c[k].unit then return tostring(c[k].name or k) .. "'s unit (" .. unit .. ")" end
    end
    local lk = unit:match("^SV_Unit_Ladon(%a+)$")
    if lk then return "Ladon " .. tostring((type(c.ladon) == "table" and c.ladon.names or {})[lk] or lk:upper()) .. "'s unit (" .. unit .. ")" end
    if unit == ALICORN_UNIT then return "the Alicorn's unit (" .. unit .. ")" end
    local dl = DECOY and DECOY.label and DECOY.label(unit)      -- (THE DECOY's: sv_decoy.lua)
    if dl then return dl end
    return unit
end
SPC.CLEAN_OBJ, SPC.cleanQ = {}, {}
-- (the teardown gate's drop, sv_core.lua levelDrop: the objects kept here forgotten with the level, none touched)
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["specials' clean-up"] = function() SPC.CLEAN_OBJ, SPC.cleanQ, SPC.cl = {}, {}, { up = {}, due = {} } end
end
local watched = {}
for _, k in ipairs({ "valka", "anomaly", "glitch", "ladon", "alicorn", "fishing", "festival" }) do
    local okU, list = pcall(SPC.cleanUnitsOf, k)
    for _, x in ipairs(okU and list or {}) do watched[x] = true end
end
do                                       -- ((0.74.0) the allies those rounds bring: their parts switch them off by these lists)
    local sp = CFG.specials or {}
    if type(sp.fishing) == "table" and str(sp.fishing.boat_unit) then watched[sp.fishing.boat_unit] = true end
    for _, x in ipairs(type(sp.festival) == "table" and sp.festival.lights or {}) do if str(x) then watched[x] = true end end
    local town = type(sp.festival) == "table" and type(sp.festival.town) == "table" and sp.festival.town.unit   -- ((2026-11-07) its boxes)
    if str(town) then watched[town] = true end
end
SPC.cleanWatch = watched           -- (a later part's units recorded too: THE DECOY's, sv_decoy.lua)
-- every object made while SV_Spawn spawns a special's unit (the host's, a joiner's copies: sv_coop.lua sets spawningUnit
-- too); a new spawn of the unit (more than 2 s after the last object) starts its list again
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    if u and SPC.seenUnits then SPC.seenUnits[u] = true end   -- ((0.73.83) spawned in this level: SPC.recycleLater)
    if not (u and watched[u]) then return end
    local l = SPC.CLEAN_OBJ[u]
    if not l or os.clock() - (l.at or 0) > 2 then l = { at = os.clock() }; SPC.CLEAN_OBJ[u] = l end
    l.at = os.clock()
    if #l < MAX_OBJS then l[#l + 1] = o end
end)
local function pooled(o)
    local n = nameOf(o)
    for _, p in ipairs(POOLED) do if n:find(p, 1, true) then return true end end
    return false
end
local function healthOf(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end
-- one object of a finished special: nil when it isn't up (gone, or at 0 health), "killed" (finished off), or "off"
-- (switched off). mortal: true kills anything (the host's or solo), "parts" all but planes (a joiner: a copy's plane is
-- the host's to kill, its parts are this game's own, as ladonPartsDown's), false nothing
local planeCls
local function takeDown(o, mortal)
    if not liveObj(o) then return nil end
    local h = healthOf(o)
    if h ~= nil and h <= 0 then return nil end
    local a = addrOf(o)
    local inList = false
    for _, p in ipairs(planes or {}) do                -- (a plane of it: off the round's list first, no pay or stats)
        if not p.down and a and p.addr == a then p.down, p.cleaned, inList = true, true, true end
    end
    if mortal == "parts" then
        planeCls = planeCls or StaticFindObject("/Script/Live.LiveAIPlane")
        local okP, isPlane = pcall(function() return valid(planeCls) and o:IsA(planeCls) end)
        if inList or not okP or isPlane then mortal = false end
    end
    if mortal and h then
        pcall(function() o:SetIsInvincible(false) end)
        pcall(function() o.bIsInvincible = false end)
        pcall(function() o.MinHealth = 0.0 end)         -- (the field: SetMinHealth keeps whole points only)
        pcall(function() o:SetMinHealth(0.0) end)
        pcall(function() o:ModifyHealth(-(h / 10 + 1000), nil, true) end)
        local h1 = healthOf(o)
        if h1 and h1 > 0 then
            local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
            if valid(gs) then pcall(function() gs:ApplyDamage(o, 100000000.0, nil, nil, nil) end) end
            h1 = healthOf(o)
        end
        if h1 and h1 <= 0 then return "killed" end
    end
    for f, v in pairs({ bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }) do
        pcall(function() o[f] = v end)
    end
    pcall(function() o:SetActive(false, false, false) end)   -- (LiveGameObject's own: what LiveSetActiveGameObject calls)
    pcall(function() o:SetActorHiddenInGame(true) end)
    pcall(function() o:SetActorEnableCollision(false) end)
    pcall(function() o:SetActorTickEnabled(false) end)
    return "off"
end
-- Takes down what's left of units `list` (why: the log's reason; mortal: the host's or solo, false on a joiner) and
-- queues each one's check CLEAN_CHECK_S on. How many objects it took down.
function SPC.cleanUp(list, why, mortal, now)
    local total = 0
    for _, u in ipairs(list or {}) do
        local l = SPC.CLEAN_OBJ[u] or {}
        local objs, seen, killed, off, pools = {}, {}, 0, 0, 0
        for _, o in ipairs(l) do objs[#objs + 1] = o end
        for _, p in ipairs(planes or {}) do if p.unit == u and not p.down then objs[#objs + 1] = p.obj end end
        for _, o in ipairs(objs) do
            local a = liveObj(o) and addrOf(o)
            if a and not seen[a] then
                seen[a] = true
                if pooled(o) then pools = pools + 1
                else
                    local okT, r = pcall(takeDown, o, mortal)
                    if okT and r == "killed" then killed = killed + 1 elseif okT and r == "off" then off = off + 1 end
                end
            end
        end
        total = total + killed + off
        local n0 = type(SV_UnitAlive) == "function" and SV_UnitAlive(u) or -5
        log(string.format("special: %s %s: %d alive, %d of its %d recorded objects still up: %d finished off, %d switched off%s",
            SPC.cleanLabel(u), tostring(why), n0, killed + off, #l, killed, off,
            pools > 0 and string.format(" (%d parked pools left to the unit's removal)", pools) or ""))
        crumb(string.format("special clean-up %s: %d killed, %d off (%s)", u, killed, off, tostring(why)))
        SPC.cleanQ[#SPC.cleanQ + 1] = { unit = u, at = now + CLEAN_CHECK_S, mortal = mortal }
    end
    return total
end
-- the checks due: SV_UnitAlive again (a unit still up the host's: SV_Recycle(unit, 1), when the runtime has it)
function SPC.cleanTick(now)
    pcall(SPC.recycleTick, now)                          -- ((0.73.83) the queue of units to take off the list)
    local q = SPC.cleanQ
    if not q or #q == 0 then return end
    for i = #q, 1, -1 do
        local e = q[i]
        if now >= e.at or now < e.at - 60 then       -- (a new run's clock: due now)
            table.remove(q, i)
            local n = type(SV_UnitAlive) == "function" and SV_UnitAlive(e.unit) or -5
            local rec = ""
            if n > 0 and e.mortal == true and type(SV_Recycle) == "function" then
                crumb("special clean-up: SV_Recycle " .. e.unit)
                local okR, r = pcall(SV_Recycle, e.unit, 1)
                n = SV_UnitAlive(e.unit)
                rec = string.format(" (SV_Recycle: %s)", okR and tostring(r) or ("error " .. tostring(r)))
            elseif n > 0 and e.mortal == true then
                rec = " (no SV_Recycle in this runtime)"
            end
            local where = e.mortal == true and "" or " here (a joiner's copies)"
            if n > 0 then log(string.format("special: %s%s NOT removed (%d alive)%s", SPC.cleanLabel(e.unit), where, n, rec))
            else log(string.format("special: %s%s removed%s", SPC.cleanLabel(e.unit), where, rec)) end
            if n <= 0 then SPC.CLEAN_OBJ[e.unit] = nil end  -- (nothing of it kept past its check)
            -- ((0.73.83) still on the spawner's list with nothing of it up (not just recycled here): off the list too
            if n == 0 and rec == "" then SPC.recycleLater({ e.unit }, "its special over, nothing of it up", 0, true) end
            if n <= 0 and e.unit == SPC.alicornUnit then SPC.alcnPool = nil end   -- ((0.73.83) its pools' addresses with it)
        end
    end
end
-- ((0.73.83) the 0.73.79 co-op run of 2026-11-04, verified twice: a special's units stayed on the spawner's list once
-- everything of them was down (SV_Spawn takes a unit off only when it spawns it again), and SV_UnitAlive walks that
-- whole list on every ask: the Spaceport's 27 ships and 5 landing-craft waves took it from 17 units to 49 and each ask
-- from 1.85 to 6 ms, never back, on the host and every joiner. A special's units are taken off the list (SV_Recycle(unit,
-- 0): only one with nothing of it alive, its unit actor destroyed [recycle] destroy_after_s later) RECYCLE_AFTER_S after
-- its end, one every RECYCLE_GAP_S (the runtime holds 64 deferred destroys: a burst past that destroys at once, the
-- bomber-raid crash's pattern); one still up is looked at again RECYCLE_AGAIN_S on, RECYCLE_TRIES times.
local RECYCLE_AFTER_S, RECYCLE_GAP_S, RECYCLE_AGAIN_S, RECYCLE_TRIES = 15, 0.5, 10, 6
SPC.recycleQ, SPC.recycled, SPC.seenUnits = {}, 0, {}   -- (seenUnits: each unit spawned in this level, on this game)
function SPC.sawSpawn(unit) if type(unit) == "string" then SPC.seenUnits[unit] = true end end
-- the units of a special kind to take off the list at its end (what its round spawns; ships carried into the retake
-- left out of the Spaceport's)
function SPC.recycleUnitsOf(kind)
    local out = {}
    local function add(u) if type(u) == "string" and u ~= "" then out[#out + 1] = u end end
    if kind == "spaceport" or kind == "retake" then
        local kept = (kind == "spaceport" and type(RUN) == "table" and type(RUN.sport) == "table" and type(RUN.sport.ships) == "table")
            and RUN.sport.ships or {}
        if SPORT and SPORT.fleet then
            local okF, fl = pcall(SPORT.fleet)
            for _, sh in ipairs(okF and fl or {}) do if not kept[sh.unit] then add(sh.unit) end end
        end
        local G, W, C = SPORT and SPORT.GROUPS or {}, SPORT and SPORT.WAVES or {}, SPORT and SPORT.CRAFT or {}
        for _, g in ipairs(G) do
            for _, w in ipairs(W) do
                add("SV_Unit_SpLcac" .. g .. w)
                for _, c in ipairs(C) do add("SV_Unit_SpTroops" .. g .. w .. c) end
            end
        end
        if kind == "retake" then
            for _, g in ipairs(SPORT and SPORT.GARRISON or {}) do add("SV_Unit_SpGarrison" .. g) end
            for _, u in ipairs(SPORT and SPORT.ISLAND_UNITS or {}) do add(u) end
            for _, u in ipairs({ "SV_Unit_SpRockets", "SV_Unit_SpDebriA", "SV_Unit_SpDebriB", "SV_Unit_SpDebriC" }) do add(u) end
        end
    elseif kind == "amphibious" then
        local c = CFG.specials and CFG.specials.amphibious or {}
        for _, l in ipairs(c.lanes or {}) do
            add("SV_Unit_Lcac" .. l)
            for _, k in ipairs(c.craft or {}) do add("SV_Unit_LcacTroops" .. l .. k) end
        end
    elseif kind == "fishing" or kind == "festival" then      -- ((0.74.0) the shoals; the formations and missile units
        for _, u in ipairs(SPC.cleanUnitsOf(kind)) do add(u) end
    end
    return out
end
-- queue units to take off the list (after: seconds on; why: the log's); only units spawned in this level (a kind's list
-- names every wave and troop unit it could have, most never spawned in a round), but for `known` ones (a special's own,
-- from its clean-up's check)
function SPC.recycleLater(units, why, after, known)
    local q, now = SPC.recycleQ, (D and tonumber(D.now)) or 0
    local seen = {}
    for _, e in ipairs(q) do seen[e.unit] = true end
    local n = 0
    for _, u in ipairs(units or {}) do
        if not seen[u] and (known or SPC.seenUnits[u]) then
            seen[u] = true
            q[#q + 1] = { unit = u, at = now + (tonumber(after) or RECYCLE_AFTER_S), tries = 0, why = why }
            n = n + 1
        end
    end
    return n
end
-- (the round clock, every tick on every game: specialTick's and clientClean's cleanTick) one unit a RECYCLE_GAP_S
function SPC.recycleTick(now)
    local q = SPC.recycleQ
    if #q == 0 or type(SV_Recycle) ~= "function" or type(SV_UnitAlive) ~= "function" then return end
    if SPC.recycleAt and now >= SPC.recycleAt - 60 and now < SPC.recycleAt then return end
    for i, e in ipairs(q) do
        if now >= e.at or now < e.at - 120 then        -- (a new run's clock: due now)
            table.remove(q, i)
            SPC.recycleAt = now + RECYCLE_GAP_S
            local n = SV_UnitAlive(e.unit)
            if n == 0 then
                crumb("special recycle: SV_Recycle " .. e.unit .. " 0")
                local okR, r = pcall(SV_Recycle, e.unit, 0)
                if okR and r == 1 then
                    SPC.recycled = SPC.recycled + 1
                    SPC.seenUnits[e.unit] = nil
                    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, e.unit, -7) end
                end
                log(string.format("special: %s taken off the spawner's list (%s; nothing of it alive): SV_Recycle %s (%d so far)",
                    SPC.cleanLabel(e.unit), tostring(e.why), okR and tostring(r) or ("error " .. tostring(r)), SPC.recycled))
            elseif n > 0 and e.tries + 1 < RECYCLE_TRIES then
                e.tries, e.at = e.tries + 1, now + RECYCLE_AGAIN_S
                q[#q + 1] = e
            end
            return                                        -- (one a RECYCLE_GAP_S)
        end
    end
end
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["specials' recycle"] = function() SPC.recycleQ, SPC.recycleAt, SPC.seenUnits = {}, nil, {} end
end
-- (the host's or solo) the round's special over (its state "done") or its round clear (why): its units cleaned up
-- once, CLEAN_AFTER_S on (VALKA's after her X-02S's fall, wreck_s: her tick still moves the wreck till then; the
-- Alicorn's after RE_SV_AlcnRemove, 20 s after it sank, so the hull isn't taken off as it goes down); force (the next
-- round starting, the special about to be replaced): now
local AFTER_KIND = { alicorn = 25 }
function SPC.endTick(now, s, why, force)
    if not (s and s.kind) or s.cleaned then return end
    if s.state ~= "done" and not why then return end
    if not s.cleanAt then
        local after = AFTER_KIND[s.kind] or CLEAN_AFTER_S
        if s.kind == "valka" and s.wreckUntil then after = math.max(after, (s.wreckUntil - now) + 1) end
        s.cleanAt = now + after
    end
    if force then s.cleanAt = now end
    if now < s.cleanAt then return end
    s.cleaned = true
    local list = SPC.cleanUnitsOf(s.kind)
    if #list > 0 then SPC.cleanUp(list, why or ("at the end of its " .. s.kind .. " fight"), true, now) end
    local rl = SPC.recycleUnitsOf(s.kind)                 -- ((0.73.83) the Spaceport's, the retake's, the amphibious round's)
    if #rl > 0 then
        local nq = SPC.recycleLater(rl, "its " .. s.kind .. " round over")
        log(string.format("special: %d of the %s round's units to be taken off the spawner's list (those with nothing alive, one each %.1f s from %d s on)",
            nq, s.kind, RECYCLE_GAP_S, RECYCLE_AFTER_S))
    end
    if s.kind == "valka" and SPC.V and SPC.V.radarOff then pcall(SPC.V.radarOff) end
end
-- (a co-op joiner, from sv_coop.lua's clientRounds) the host's special: once it's over there, this game's copies of its
-- units are switched off CLIENT_AFTER_S on (the host's "dn" first takes its planes down the normal way); VALKA's
-- opener railgun copy as she shows on the host (its own removal there, eml_remove_s after its shot)
SPC.cl = { up = {}, due = {} }
function SPC.clientClean(now)
    local C = SPC.cl
    if C.now and now < C.now - 60 then C.up, C.due = {}, {} end      -- (a new run's clock)
    C.now = now
    local hs = D and D.hostSpecial
    if hs and hs.kind and hs.state ~= "done" and hs.state ~= "pending" then C.up[hs.kind] = C.up[hs.kind] or now end
    for kind in pairs(C.up) do
        if not (hs and hs.kind == kind and hs.state ~= "done") then
            C.up[kind] = nil
            C.due[#C.due + 1] = { at = now + CLIENT_AFTER_S, list = SPC.cleanUnitsOf(kind), why = "the host's " .. kind .. " over" }
            SPC.recycleLater(SPC.recycleUnitsOf(kind), "the host's " .. kind .. " over")   -- ((0.73.83) this game's copies' units too)
            if kind == "valka" and SPC.V and SPC.V.radarOff then pcall(SPC.V.radarOff) end
            -- ((0.73.80, R30_FINDINGS specials 0) the shuttle's copy here off this game's spawner list once the host's
            -- RE_SV_ShuttleRemove has run here too (remove_s after its liftoff, 30 s after its loss, + SHUTTLE_CLIENT_S): the
            -- joiners' round-4 copies were never taken off, so the host's next shuttle was refused here until [coop]
            -- force_recycle stepped in)
            local sc = CFG.specials and CFG.specials.shuttle
            if kind == "shuttle" and type(sc) == "table" and sc.unit then
                C.due[#C.due + 1] = { at = now + math.max(tonumber(sc.remove_s) or 180, 30) + SHUTTLE_CLIENT_S,
                                      recycle = sc.unit, why = "the host's shuttle taken off" }
            end
        end
    end
    local va = CFG.specials and CFG.specials.valka
    if hs and hs.kind == "valka" and hs.state == "hunt" and type(va) == "table" and va.eml_unit and not C.emlFor then
        C.emlFor = C.up.valka
        C.due[#C.due + 1] = { at = now + (tonumber(va.eml_remove_s) or 4) + 2, list = { va.eml_unit }, why = "her reveal on the host" }
    end
    if not (hs and hs.kind == "valka") then C.emlFor = nil end
    for i = #C.due, 1, -1 do
        local e = C.due[i]
        if now >= e.at and e.recycle then
            table.remove(C.due, i)
            local n0 = SV_UnitAlive(e.recycle)
            local rec = "nothing to take off"
            if n0 > 0 and type(SV_Recycle) == "function" then
                crumb("coop: shuttle copy SV_Recycle " .. e.recycle)
                local okR, r = pcall(SV_Recycle, e.recycle, 1)
                rec = string.format("taken off this game's spawner list (SV_Recycle %s): %d alive after", okR and tostring(r)
                    or ("error " .. tostring(r)), SV_UnitAlive(e.recycle))
            elseif n0 > 0 then
                rec = "no SV_Recycle in this runtime"
            end
            log(string.format("coop: %s: its copy here %s %d alive: %s", e.why, e.recycle, n0, rec))
        elseif now >= e.at then
            table.remove(C.due, i)
            local n = SPC.cleanUp(e.list, e.why, "parts", now)
            log(string.format("coop: %s: %d of its copies' objects still up here, taken off (its planes switched off, its parts finished off)",
                e.why, n))
        end
    end
    SPC.cleanTick(now)
end
end

-- Watches a running special: launched (its flag, or the countdown run out with the shuttle still there) or lost (its
-- flag, or nothing of its unit alive before liftoff). Pays the reward or closes the shop.
local function specialTick(now)
    SPC.shuttleClockTick(now)
    SPC.shuttleReplayTick(now)                      -- ((2026-11-11) this game's liftoff again, its STORE shut: above)
    SPC.shuttleWatchTick(now)
    local okE, errE = pcall(SPC.endTick, now, D.special)          -- ((0.73.77) D4: a finished special's leftovers)
    if not okE and tostring(errE) ~= D.cleanErr then D.cleanErr = tostring(errE); log("special: clean-up error " .. D.cleanErr) end
    local okC, errC = pcall(SPC.cleanTick, now)
    if not okC and tostring(errC) ~= D.cleanErr then D.cleanErr = tostring(errC); log("special: clean-up error " .. D.cleanErr) end
    -- the shuttle killed and hidden first, RE_SV_ShuttleRemove 3 s later: that event sets SV_ShuttleLaunched back to 0,
    -- and a shuttle destroyed while it's 0 counts as shot down on the pad (failure radio, SV_ShuttleLost)
    if D.shuttleRemoveAt and now >= D.shuttleRemoveAt then
        D.shuttleRemoveAt, D.shuttleEventAt, D.shuttleCheckAt = nil, now + 3, now + 5
        D.shuttleReplay = nil                       -- (a replay's tail not fired yet: the shuttle's going)
        if D.shuttleClock and D.shuttleClock.inv then SPC.shuttleInvincible(false); D.shuttleClock.inv = false end
        local okT, errT = pcall(SPC.shuttleTakeOff)
        if not okT then log("special: shuttle and pad off: error " .. tostring(errT)) end
    end
    if D.shuttleEventAt and now >= D.shuttleEventAt then            -- (tools/survival_events.py RE_SV_ShuttleRemove)
        D.shuttleEventAt = nil
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_ShuttleRemove") or "n/a"
        log("special: shuttle and pad taken off (RE_SV_ShuttleRemove " .. tostring(r) .. ")")
        -- its strike flights still up back onto the airfield (they were ordered onto the shuttle alone)
        local back = {}
        for u in pairs(D.up) do
            if BOMBER_UNIT[u] and ALIVE.ask(u, now) > 0 and type(SV_Event) == "function" then
                back[#back + 1] = u .. " " .. tostring(SV_Event(string.format("RE_SV_BomberRetask_%02d", BOMBER_INDEX[u])))
            end
        end
        if #back > 0 then log("special: strike flights back onto the airfield: " .. table.concat(back, ", ")) end
    end
    -- did the kill take its unit down? ((0.73.80, R30_FINDINGS specials 0) it never does: the unit stayed on the spawner's
    -- list ("1 alive 5 s after"), and the next shuttle round's spawn was refused, "its last flight is still up" (rounds 17
    -- and 30 of the test of 2026-11-04, their strike flown as a plain raid): a unit still up is taken off it,
    -- SV_Recycle(unit, 1), as SPC.cleanTick does)
    if D.shuttleCheckAt and now >= D.shuttleCheckAt then
        D.shuttleCheckAt = nil
        SPC.shuttleRemoveCheck(now)                 -- ((2026-11-11) RE_SV_ShuttleRemove lost in your STORE: again, above)
        local u = CFG.specials.shuttle.unit
        local n0 = SV_UnitAlive(u)
        local rec = ""
        if n0 > 0 and type(SV_Recycle) == "function" then
            crumb("special: shuttle SV_Recycle " .. u)
            local okR, r = pcall(SV_Recycle, u, 1)
            rec = string.format("; taken off the spawner's list (SV_Recycle %s): %d alive after", okR and tostring(r)
                or ("error " .. tostring(r)), SV_UnitAlive(u))
        elseif n0 > 0 then
            rec = "; no SV_Recycle in this runtime: the next shuttle round's plan tries again"
        end
        log(string.format("special: shuttle unit %s: %d alive 5 s after it was taken off (0: a fresh one next time)%s", u, n0, rec))
    end
    SPC.shuttleRemoveAgainTick(now)
    local s = D.special
    if #ANOM.fx > 0 then ANOM.cleanFx(now) end                     -- (the Anomaly's systems, even after its round)
    AMPH.runTick(now)                                               -- landed troops, the capture (any round)
    if D.alicornRemoveAt and now >= D.alicornRemoveAt then
        D.alicornRemoveAt = nil
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_AlcnRemove") or "n/a"
        log("special: the Alicorn taken off (RE_SV_AlcnRemove " .. tostring(r) .. ")")
    end
    local sk = s and SPC.kinds[s.kind]
    if sk and sk.tick then return sk.tick(now, s) end
    if s and s.kind == "shuttle" and KASKA and KASKA.tick then      -- ((2026-11-08) Kaska's intercepted channel: sv_kaska.lua)
        local okK, errK = pcall(KASKA.tick, now, s)
        if not okK and tostring(errK) ~= D.kaskaErr then D.kaskaErr = tostring(errK); log("kaska: error " .. D.kaskaErr) end
    end
    if not s or s.state ~= "countdown" then return end
    local c, t = CFG.specials.shuttle, CFG.hud.text
    local f = svFlags() or {}
    local alive = ALIVE.ask(c.unit, now)          -- ((0.73.80) every tick of the countdown: kept, at most ~1 s old)
    local cd = D.shuttleClock and D.shuttleClock.cd or (now - s.at)
    local over = cd >= c.countdown_s + 3
    local launched = (f.SV_ShuttleLaunched or 0) >= 1
    if now >= (s.logAt or 0) then                   -- every 10 s: is anything getting at it (report of 2026-10-23)
        s.logAt = now + 10
        local hp, near, at = shuttleHealth(), nil, nil       -- (finds the shuttle's actor first)
        pcall(function() local v = SHUTTLE.obj:K2_GetActorLocation(); at = { X = v.X, Y = v.Y, Z = v.Z } end)
        if at and cd < c.countdown_s and not SHUTTLE.padAt then SHUTTLE.padAt = at end   -- (on the pad: for its take-off)
        for _, q in ipairs(planes) do
            if D.strikeUnits and D.strikeUnits[q.unit] and valid(q.obj) and at then
                pcall(function()
                    local v = q.obj:K2_GetActorLocation()
                    local d = km({ X = v.X, Y = v.Y, Z = v.Z }, at)
                    if not near or d < near then near = d end
                end)
            end
        end
        log(string.format("special: shuttle %.0f s in: health %s%%, %d hits, nearest strike aircraft %s, %d alive in its unit",
            cd, tostring(hp), f.SV_ShuttleHits or -1, near and string.format("%.1f km", near) or "none",
            alive))
    end
    if (f.SV_ShuttleLost or 0) >= 1 or (alive <= 0 and not launched and not over) or (over and not launched and alive <= 0) then
        s.state, s.lost = "done", true
        D.shuttleRemoveAt = now + 30                    -- the pad's allies (the shuttle is gone)
        RUN.shopClosedUntil = D.round + c.shop_closed_rounds
        RUN.dirty = true
        LB.special("shuttle", false, cd)
        hudCallout(t.shuttle_lost, t.shuttle_lost_sub)
        log(string.format("special: round %d, the shuttle was lost %.0f s into the countdown (%d hits); shop closed through round %d",
            D.round, cd, f.SV_ShuttleHits or -1, RUN.shopClosedUntil))
    elseif launched or over then
        s.state = "done"
        -- ((2026-11-11) "countdown over" with the shuttle still up: its liftoff never took here (Saint Alessia's STORE
        -- ate it): replayed on this game once its STORE is shut, its removal counted from that liftoff
        -- (SPC.shuttleReplayStart, above); the pay, the callout and the round's end as ever, the other players' shuttles
        -- having lifted off on time)
        local replay = not launched and SPC.shuttleReplayStart(now) or false
        if not replay then D.shuttleRemoveAt = now + c.remove_s end   -- it and the pad's allies, once it's well up
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, "shuttle launched")
        LB.special("shuttle", true, cd)
        hudCallout(t.launched, string.format(t.launched_sub, specialPay(pay)))   -- ((0.73.78) C3: each player's share)
        log(string.format("special: round %d, the shuttle lifted off (%s; %d hits, health %s%%; SV_ShuttleLaunched %s, "
            .. "SV_ShuttleRound %s)%s", D.round, launched and "event package" or "countdown over", f.SV_ShuttleHits or -1,
            tostring(shuttleHealth()), tostring(f.SV_ShuttleLaunched or "?"), tostring(f.SV_ShuttleRound or "?"),
            replay and ": not here (its liftoff's events never took): replayed on this game once your STORE is shut" or ""))
    end
end

-- Events Lua fires a little later (a flight's orders after its appearance's): { at, name, why } in D.events, fired by
-- roundsTick. (ALLY.run.events are the allies' own.)
function queueEvent(at, name, why)
    if not D then return end
    D.events = D.events or {}
    D.events[#D.events + 1] = { at = at, name = name, why = why }
end

local function eventsTick(now)
    local q = D.events
    if not q or #q == 0 then return end
    for i = #q, 1, -1 do
        local e = q[i]
        if now >= e.at then
            table.remove(q, i)
            local r = type(SV_Event) == "function" and SV_Event(e.name) or -5
            log(string.format("events: %s (%s) %s", e.name, e.why or "", r == 1 and "fired" or ("not fired: " .. (SV_ERR[r] or tostring(r)))))
        end
    end
end

-- Aircraft shot down before this round come off the plane list (it only grew: 538 entries by round 23 of a friend's
-- run, all walked every tick; economy review of 2026-10-25, "frame-time cost grows with round size").
local function pruneDown()
    local keep = {}
    for _, p in ipairs(planes) do if not p.down then keep[#keep + 1] = p end end
    if #keep < #planes then log(string.format("round probe: %d downed aircraft off the list, %d still up", #planes - #keep, #keep)) end
    planes = keep
end

-- The round's flights in waves (CFG.waves): the first holds the special, the escorts and the bombers (behind their
-- fighters), each wave at most `cap` aircraft; the other fighters follow in the next waves. One wave when it all fits.
local function makeWaves(special, fighters, bombers, cap)
    local function size(u)
        local k = type(u) == "string" and u:sub(1, 1) == "@" and SPC.kinds[u:sub(2)]
        if k then return SPC.kindValue(k.aircraft) or 0 end
        return flightSize(u)
    end
    local total, firstN = 0, 0
    for _, u in ipairs(fighters) do total = total + size(u) end
    for _, u in ipairs(bombers) do total = total + size(u); firstN = firstN + size(u) end
    if special then local n = size("@" .. special); total = total + n; firstN = firstN + n end
    local one = {}
    if special then one[1] = "@" .. special end
    if not (CFG.waves.enabled and cap and total > cap) then
        for _, u in ipairs(fighters) do one[#one + 1] = u end
        for _, u in ipairs(bombers) do one[#one + 1] = u end
        return { one }
    end
    local waves, left, i = { one }, math.max(0, cap - firstN), 1
    while i <= #fighters and size(fighters[i]) <= left do        -- the first wave's fighters (escorts first)
        one[#one + 1] = fighters[i]; left = left - size(fighters[i]); i = i + 1
    end
    -- ((0.73.78) never an empty first wave: a flight bigger than the cap (a 6-ship in an ace round's waves of 4) leads alone)
    if #one == 0 and #bombers == 0 and i <= #fighters then one[1] = fighters[i]; i = i + 1 end
    for _, u in ipairs(bombers) do one[#one + 1] = u end
    local cur, n = nil, 0
    for k = i, #fighters do
        local u = fighters[k]
        if not cur or n + size(u) > cap then cur, n = {}, 0; waves[#waves + 1] = cur end
        cur[#cur + 1] = u; n = n + size(u)
    end
    return waves
end

-- The most aircraft a wave of round `round` holds (CFG.waves.max_up, by the game's difficulty when max_up_by_preset
-- has it; from CFG.late.aircraft_from_round growing to late.max_up_cap: TIER.maxUp), x the menu's ENEMY AIRCRAFT %.
local function waveCap(round)
    local p = presetName()                                         -- (its first value: presetName returns two)
    return math.max(2, math.floor(TIER.maxUp(round, p) * SETUP.enemyX() + 0.5))   -- (the menu's %, sv_menu.lua)
end

-- The game's player-attack throttle for the round (CFG.late.pressure; behaviour roadmap P8 x P4, the critic's gap
-- fill): RE_SV_Pressure<X> (tools/survival_events.py PRESSURE) when the round's preset (TIER.pressure) isn't the one in
-- force, D.pressure. D.pressure is nil in a run's first round (a new D): not known, so that round fires its preset even
-- when it's B, the mission start's ATTACK_BASE. A restart keeps the level (sv_main.lua), and with it an earlier run's C
-- or D on the host and on every joiner (whose "rs" doesn't reset their level either): review of unit 3. An Anomaly or
-- VALKA round (TIER.PRESSURE_OWN) fires none: their own records set their throttle and put B back as they end, so
-- D.pressure is B there, and pressureAfterBoss fires the band's preset again once the boss is down (or the next round
-- does; pressureNoBoss at once when it can't come). Forwarded to co-op joiners (each game's throttle limits attacks on
-- its own player; a joiner who links later gets the one in force from hostSync, sv_coop.lua). The intensity director
-- (P4) turns the same dial: while it has the room's level eased under the spikes, the band's preset a letter gentler
-- (DIR.pressure: never under CFG.intensity.level.pressure_min, B), fired again when its ease changes (pressureNow,
-- below). `why`: the log's reason for a fire outside startRound.
local function roundPressure(special, why)
    local band = TIER.pressure(D.round)
    if not band then return end
    local want = band
    if DIR and DIR.pressure then
        local okE, e = pcall(DIR.pressure, band)
        if okE and type(e) == "string" and #e == 1 and TIER.PRESSURE_PRESETS:find(e, 1, true) then want = e end
    end
    if want ~= band then why = (why and (why .. "; ") or "") .. string.format("the band's %s, a letter gentler", band) end
    local was = D.pressure
    if special and TIER.PRESSURE_OWN[special] then
        D.pressure, D.pressureWas = "B", was                -- (the one in force till its boss comes: pressureNoBoss)
        log(string.format("pressure: round %d is the %s's: its own throttle, then preset B%s", D.round, special,
            want ~= "B" and string.format("; preset %s again once it's down", want) or ""))
        return
    end
    if want == was then return end
    local ev = "RE_SV_Pressure" .. want
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    if r == 1 then D.pressure = want end
    log(string.format("pressure: round %d: preset %s (was %s%s)%s", D.round, want, was or "not known: the run's first round",
        why and (", " .. why) or "", r == 1 and "" or (", " .. ev .. " not fired: " .. (SV_ERR[r] or tostring(r)))))
end

-- An Anomaly or VALKA round, its boss down: its down / end records put ATTACK_BASE back, so the fighters left would fly
-- B for the rest of the round. PRESSURE_AFTER_S after Lua saw it down (those records ran first), the round's band
-- preset again (the critic: "fire it again after those specials end"). Once a special (s.pressureAt false after).
local PRESSURE_AFTER_S = 3
local function pressureAfterBoss(now)
    local s = D.special
    if not (s and TIER.PRESSURE_OWN[s.kind] and s.state == "done" and s.pressureAt ~= false) then return end
    s.pressureAt = s.pressureAt or now + PRESSURE_AFTER_S
    if now < s.pressureAt then return end
    s.pressureAt = false
    local okP, errP = pcall(roundPressure, nil, "the " .. s.kind .. " is down")
    if not okP then log("pressure: error " .. tostring(errP)) end
end

-- An Anomaly or VALKA round whose boss can't come (its spawn refused: a normal round instead): its records never ran,
-- so the throttle in force is still the one before the round (D.pressureWas; D.pressure said B): the band's preset
-- now, as a normal round's (review of unit 3: none fired, and hostSync sent B to a joiner who linked then)
local function pressureNoBoss(kind)
    if not TIER.PRESSURE_OWN[kind] then return end
    D.pressure, D.pressureWas = D.pressureWas, nil
    local okP, errP = pcall(roundPressure, nil, "no " .. kind .. " this round")
    if not okP then log("pressure: error " .. tostring(errP)) end
end

-- (0.73.80) The round's callout again once its special changed after the announce (a swap, or none after all): the
-- special's own, or a normal round's (a disguised one's too: VALKA's)
local function roundCalloutAgain(kind)
    local t = CFG.hud.text
    local k = kind and SPC.kinds and SPC.kinds[kind]
    if k and not SPC.kindValue(k.disguise) then
        hudCallout(string.format(t.special, D.round), type(k.sub) == "function" and k.sub(t) or t[k.sub])
    elseif not kind and D.nextTierRound == D.round and D.nextTier then   -- (an ace round instead: its squadron, as announced)
        local sq = D.nextSquad
        local tn = (sq and type(CFG.aces[sq]) == "table") and sq or CFG.tiers.list[D.nextTier].name:lower()
        local c = CFG.aces[tn] or {}
        hudCallout(string.format(t.start, D.round), string.format(t.aces_round, tostring(c.squadron or tn):upper()))
    else
        hudCallout(string.format(t.start, D.round), t.start_sub)
    end
end

-- (0.73.80, R30_FINDINGS specials 0 / 1) Whether special `kind` can start this round, and why not: a landing craft lane
-- (AMPH.ready), its own ready() (the Spaceport's turrets' rows), and the shuttle's last one off the spawner's list: the
-- one before it, killed and hidden at its liftoff, stayed on it, and the next shuttle round's spawn was refused, "its last
-- flight is still up" (rounds 17 and 30 of the test of 2026-11-04): taken off here (SV_Recycle(unit, 1)) as the round is
-- planned, its strike flights not yet picked.
-- ((0.74.0) forced: a test key's (VALKA's gate and GONE FISHIN''s once a run let it through; ready(round, forced))
function SPC.canStart(kind, forced)
    if kind == "amphibious" and not AMPH.ready() then return false, "no landing craft can come" end
    local rk = SPC.kinds and SPC.kinds[kind]
    if rk and rk.ready and not rk.ready(D and D.round, forced) then return false, "it can't come now" end
    if kind == "shuttle" then
        local u = CFG.specials.shuttle.unit
        local n = ALIVE.fresh(u)
        if n > 0 then
            local rec = "no SV_Recycle in this runtime"
            if type(SV_Recycle) == "function" then
                crumb("special: shuttle SV_Recycle " .. u .. " (its round planned)")
                local okR, r = pcall(SV_Recycle, u, 1)
                rec = "SV_Recycle " .. (okR and tostring(r) or ("error " .. tostring(r)))
                n = ALIVE.fresh(u)
            end
            log(string.format("special: shuttle unit %s still up as round %d is planned: taken off the spawner's list (%s): %s", u,
                D.round, rec, n > 0 and (n .. " still up") or "gone"))
            if n > 0 then return false, "its last shuttle is still on the spawner's list" end
        end
    end
    return true
end

-- (0.73.80, R30_FINDINGS specials 0) The round's special didn't come after the round was planned for it (its spawn
-- refused: spawnShuttle's after a recycle and a second try, or a kind's spawn(now) false, roundsTick): a normal round from
-- the start, not half of one. Its strike flights (D.strikeUnits: the shuttle's, picked from the bombers and ordered at
-- it) come out of the round's waves and as many fighters' aircraft go in (rounds 17 and 30's flew on as a plain raid at
-- the airfield, called out BOMBERS INBOUND); its pick and cooldown are given back (RUN.specialAt, specialUndo: the bag,
-- the run's last special, the gap); the round's callout is a normal one's (not a disguised special's: it had one); the
-- shuttle's pad (brought back for it) is hidden again. How many aircraft were replaced.
function SPC.unplan(kind, now, why)
    local k = SPC.kinds and SPC.kinds[kind]
    local disguised = k and SPC.kindValue(k.disguise)
    D.special = nil
    RUN.specialPick = RUN.specialPick or {}
    RUN.specialPick[D.round] = false
    RUN.specialAt = RUN.specialAt or {}
    local w = D.specialAtWas
    if w and w.kind == kind and RUN.specialAt[kind] == D.round then RUN.specialAt[kind] = w.at end
    D.specialAtWas = nil
    local undone = type(specialUndo) == "function" and specialUndo(D.round, kind)
    pressureNoBoss(kind)
    local out, n, cut = {}, 0, 0
    for u in pairs(D.strikeUnits or {}) do out[u] = true end
    local function strip(list)                      -- (in place: D.queue is the wave's own list)
        for i = #(list or {}), 1, -1 do
            if out[list[i]] then n = n + flightSize(list[i]); cut = cut + 1; table.remove(list, i) end
        end
    end
    strip(D.queue)
    for i = (D.wave or 1), #(D.waves or {}) do if D.waves[i] ~= D.queue then strip(D.waves[i]) end end
    for u in pairs(out) do if D.taken then D.taken[u] = nil end end
    D.strikeUnits = {}
    local f, got = {}, 0
    if n > 0 then
        f, got = pickFlights(CFG.pool, n, function(q) return (D.taken and D.taken[q]) or PROBE_OF[q] or ROLE.sitsOut(q) end)
        for _, q in ipairs(f) do D.queue[#D.queue + 1] = q; if D.taken then D.taken[q] = true end end
    end
    if kind == "shuttle" then
        local okT, errT = pcall(SPC.shuttleTakeOff, true)
        if not okT then log("special: the pad hidden again: error " .. tostring(errT)) end
    end
    if not disguised then roundCalloutAgain(nil) end
    log(string.format("round %d: no %s after all (%s): a normal round; %s%s%s", D.round, kind, tostring(why),
        cut > 0 and string.format("its %d strike flight%s (%d aircraft) out of the round, %d fighters in %d flights instead%s",
            cut, cut == 1 and "" or "s", n, got, #f, #f > 0 and (" (" .. table.concat(f, ", ") .. ")") or "") or "no strike flights to replace",
        undone and "; its pick given back to the dice" or "", (w and w.kind == kind) and "; its cooldown given back" or ""))
    return n
end

-- The intensity director's ease changed (P4, sv_director.lua easeTick): the round's preset again, eased or back
-- (DIR.pressure), when it isn't the one in force. Not while an Anomaly / VALKA fight's own throttle is up: its
-- pressureAfterBoss fires the band's (eased as it is then) once the boss is down. The host's (or solo's) only.
function pressureNow(why)
    if not (D and D.round) or (COOP and COOP.client and COOP.client()) then return end
    local s = D.special
    if s and TIER.PRESSURE_OWN[s.kind] and s.state ~= "done" then
        log(string.format("pressure: round %d: the %s's own throttle is up: the preset after it (%s)", D.round, s.kind,
            tostring(why)))
        return
    end
    roundPressure(nil, why)
end

-- (0.73.78, plan G4) Flight `unit`'s planes taken off without a kill (despawned: an ace squadron's break-off below, the
-- Spaceport's withdrawal): marked down and withdrawn, so the sweep neither pays nor counts them. On every game: the
-- host's (or solo) as it despawns them, a co-op joiner's as the host's RE_SV_FlightOff_NN reaches it (sv_coop.lua
-- hostEvent; before, a joiner's sweep paid the vanished copies as its kills a second on). The planes marked.
function flightWithdrawn(unit)
    local n = 0
    for _, p in ipairs(planes or {}) do
        if p.unit == unit and not p.down then p.down, p.withdrawn, n = true, true, n + 1 end
    end
    return n
end

-- (0.73.78, plan G4; IMPROVEMENTS "Pacing and rounds" 3) The ace rounds' record, their break-off and its flights:
--   aceFlown(sq)       startRound: squadron sq flies this ace round (RUN.aceSinceTop: ace rounds since the top squadron
--                      last flew one, nil until it has; RUN.aceAt[sq]: the round; CFG.aces.rotation, ACE.squadFor)
--   aceGoneRecycle()   startRound, before the picks: the flights a break-off despawned (D.aceGone) still reading up (a
--                      despawned unit does) recycled (SV_Recycle(unit, 1)), else kept out of this round's picks (D.taken),
--                      as the Spaceport's withdrawn ones (sv_spaceport.lua SPORT.planRound)
--   aceBreakTick(now)  roundsTick, the host's (or solo): an ace round's clock (D.aceBreak; not while you're down at the
--                      airfield with nobody else flying), after_s on its squadron's flights up break off (RE_SV_DirHold_NN:
--                      engagement None; no openers, reversals, hunt or specials; its queue and later waves dropped), each
--                      despawned (RE_SV_FlightOff_NN, flightWithdrawn) once all of it is far_km from every player or
--                      leave_s on (CFG.aces.break_off)
local aceFlown, aceGoneRecycle, aceBreakTick
do
local function fire(ev)
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    return r == 1, r == 1 and "fired" or ("not fired: " .. tostring(SV_ERR and SV_ERR[r] or r))
end
local function mmss(s) s = math.max(0, math.floor(s + 0.5)); return string.format("%d:%02d", s // 60, s % 60) end
local function playersAt()                          -- where every player is (COOP.players: you first), else you
    local out = {}
    if COOP and COOP.players then
        local ok, l = pcall(COOP.players)
        if ok and type(l) == "table" then for _, e in ipairs(l) do if e.at and e.alive ~= false then out[#out + 1] = e.at end end end
    end
    if #out == 0 then local at = playerLocation(); if at then out[1] = at end end
    return out
end
local function roundKillsNow()
    local n = 0
    for _, v in pairs(RUN.roundKills or {}) do n = n + (tonumber(v) or 0) end
    return n
end

function aceFlown(sq)
    if not (RUN and sq) then return end
    if sq == ACE.top() then RUN.aceSinceTop = 0
    elseif RUN.aceSinceTop then RUN.aceSinceTop = RUN.aceSinceTop + 1 end
    RUN.aceAt = RUN.aceAt or {}
    RUN.aceAt[sq] = D.round
end

function aceGoneRecycle()
    local g = D.aceGone
    if not (g and next(g)) then return end
    local done, kept, gone = {}, {}, 0
    for u in pairs(g) do
        if ALIVE.ask(u, D.now) <= 0 then
            g[u], gone = nil, gone + 1
        else
            local r = nil
            if type(SV_Recycle) == "function" then
                local okR, x = pcall(SV_Recycle, u, 1)
                r = okR and tonumber(x) or nil
            end
            if r == 1 or (r == 0 and SV_UnitAlive(u) <= 0) then
                g[u] = nil
                done[#done + 1] = u
            else
                if D.taken then D.taken[u] = true end
                kept[#kept + 1] = u .. (r and string.format(" (SV_Recycle %s)", (SV_ERR and SV_ERR[r]) or tostring(r)) or "")
            end
        end
    end
    table.sort(done); table.sort(kept)
    log(string.format("aces: the flights a break-off took off: %d down since, %d recycled (SV_Recycle)%s%s", gone, #done,
        #done > 0 and (": " .. table.concat(done, ", ")) or "", #kept > 0 and string.format("; %d still up kept out of round %d's "
            .. "picks%s: %s", #kept, D.round, type(SV_Recycle) == "function" and "" or " (no SV_Recycle in this runtime)",
            table.concat(kept, ", ")) or ""))
end

local function breakOff(now, B)
    local c = CFG.aces.break_off or {}
    local units, n = {}, 0
    for u in pairs(D.up or {}) do
        if D.aceSquad and D.aceSquad[u] and poolIndex(u) then
            local a = ALIVE.ask(u, now)
            if a > 0 then units[#units + 1] = u; n = n + a end
        end
    end
    table.sort(units)
    local later = 0                                 -- (this wave's flights not up yet and the waves still to come)
    for _, u in ipairs(D.queue or {}) do if type(u) == "string" and u:sub(1, 1) ~= "@" then later = later + flightSize(u) end end
    for w = (D.wave or 1) + 1, #(D.waves or {}) do
        for _, u in ipairs(D.waves[w]) do if type(u) == "string" and u:sub(1, 1) ~= "@" then later = later + flightSize(u) end end
    end
    D.queue, D.spare = {}, {}
    if D.waves then D.wave = #D.waves end
    if D.state == "spawning" or D.state == "wave" then D.state = "fighting" end
    B.state, B.at, B.leaveBy, B.units, B.gone, B.n0 = "leaving", now, now + math.max(0, tonumber(c.leave_s) or 12), {}, 0, n
    local held = {}
    D.aceMoveAt = D.aceMoveAt or {}
    for _, u in ipairs(units) do
        B.units[u] = true
        local ok, why = fire(string.format("RE_SV_DirHold_%02d", poolIndex(u)))   -- (engagement None; forwarded in co-op)
        if not ok then held[#held + 1] = u .. " (" .. why .. ")" end
        if D.squad then D.squad[u] = nil end         -- (no opener or blink of its squadron's now)
        D.aceMoveAt[u] = math.huge                   -- (no reversal, nor the director's cover turn: ACE.movesTick, DIR)
        for _, p in ipairs(planes) do
            if p.unit == u and not p.down then p.leaving, p.spwAt = true, math.huge end   -- (no hunt, no special fired)
        end
    end
    local sq = D.roundSquad and CFG.aces[D.roundSquad]
    local name = tostring(sq and sq.squadron or D.roundSquad or "the squadron")
    log(string.format("aces: round %d: %s breaks off %s in (CFG.aces.break_off after_s %s): %d aircraft in %d flights leave%s, "
        .. "%d more never come; %d shot down this round, paid as they went%s", D.round, name, mmss(B.t), tostring(c.after_s),
        n, #units, #units > 0 and (" (" .. table.concat(units, ", ") .. ")") or "", later, roundKillsNow(),
        #held > 0 and ("; not held: " .. table.concat(held, ", ")) or ""))
    if n > 0 then
        local t = CFG.hud.text
        hudCallout(string.format(t.aces_break or "%s BREAKS OFF", name:upper()), string.format(t.aces_break_sub or "%d OF THEM LEAVING", n))
    end
    if #units == 0 then B.state = "done" end
end

local function leaveTick(now, B)
    local far = tonumber((CFG.aces.break_off or {}).far_km) or 4
    local pls = playersAt()
    local left = 0
    for _, u in ipairs((function() local t = {}; for x in pairs(B.units) do t[#t + 1] = x end; table.sort(t); return t end)()) do
        local go, why = now >= B.leaveBy, "leave_s on"
        if not go then
            local near = nil
            for _, p in ipairs(planes) do
                if p.unit == u and not p.down and p.at then
                    for _, at in ipairs(pls) do
                        local d = km(p.at, at)
                        if not near or d < near then near = d end
                    end
                end
            end
            go, why = (near == nil or near >= far), near and string.format("%.1f km from the nearest player", near) or "none of it seen"
        end
        if go then
            local ok, how = fire(string.format("RE_SV_FlightOff_%02d", poolIndex(u)))
            local m = flightWithdrawn(u)
            D.up[u] = nil
            D.aceGone = D.aceGone or {}
            D.aceGone[u] = true
            B.units[u], B.gone = nil, B.gone + m
            log(string.format("aces: %s gone (%s, %.0f s after the break): %d aircraft, unpaid; RE_SV_FlightOff_%02d %s", u, why,
                now - B.at, m, poolIndex(u), how))
        else
            left = left + 1
        end
    end
    if left == 0 then
        B.state = "done"
        log(string.format("aces: round %d: the break-off is over %.0f s on: %d of the %d leaving shot down meanwhile, %d gone unpaid",
            D.round, now - B.at, math.max(0, B.n0 - B.gone), B.n0, B.gone))
    end
end

function aceBreakTick(now)
    local B = D.aceBreak
    if not B or B.state == "done" or now < (B.checkAt or 0) then return end
    B.checkAt = now + 1
    if B.state == "on" then
        local dt = math.max(0, now - (B.seen or now))
        B.seen = now
        if not (playerOnAirfield() and othersFlying() == 0) then B.t = B.t + dt end
        if B.t >= (tonumber((CFG.aces.break_off or {}).after_s) or 360) then breakOff(now, B) end
    elseif B.state == "leaving" then
        leaveTick(now, B)
    end
end
end

local function startRound()
    D.round = D.round + 1
    pruneDown()
    D.events = {}
    -- the learning layer's counters for this round (P6, sv_stats.lua PROF.weights: your habits, this run's and your saved
    -- profile's): D.counter, read by the strike and jammer picks, the role mix, enemyTier / enemyManeuvers, the Lancers'
    -- height and the squad director's budgets (DIR.roundStart) below
    do
        local okPf, errPf = true, nil
        if PROF and PROF.weights then okPf, errPf = pcall(PROF.weights, D.round) end
        if not okPf then D.counter = nil; log("learning: error " .. tostring(errPf)) end
    end
    -- the round's aircraft (TIER.roundBudget: the spike's aircraft_add within the round's cap, which grows from
    -- CFG.late.aircraft_from_round; the spike level the intensity director's, levelFor, when it's eased under the
    -- spike: P4), then a special's extra, then the menu's ENEMY AIRCRAFT %, then co-op (below): the caps before the %
    -- (CFG.setup's "% of each round's and each wave's aircraft")
    local budget = TIER.roundBudget(D.round, levelFor(D.round))
    local b = CFG.airfield.bombers
    local forced = D.forceSpecial
    local special = D.forceSpecial or specialFor(D.round)          -- (Ctrl+1 .. Ctrl+5: a special next, for testing)
    D.forceSpecial = nil
    -- ((0.73.80) one that can't start (SPC.canStart: no landing craft lane, the Spaceport's rows, the shuttle's last one
    -- still on the spawner's list) swaps to another the dice can give that can (specialSwap, sv_spawn.lua), else a normal
    -- round; a forced one (a test key) or the retake: a normal round)
    if special then
        local okS, why = SPC.canStart(special, forced)
        if not okS then
            local alt = nil
            local roll = RUN.specialRoll                 -- (its gap before the roll: an ace round below doesn't count)
            local gapWas = roll and roll.round == D.round and roll.kind == special and roll.gapWas
            if not forced then alt = specialSwap(D.round, special, why, function(k) return (SPC.canStart(k)) end) end
            -- ((review of 0.73.80) none instead on an ace slot: the ace round it would have been, said so and flown as
            -- one, not counted in the specials' gap)
            local ti, sq, st, wy = nil, nil, nil, nil
            if not alt then ti, sq, st, wy = aceRound(D.round, nil) end
            if ti then
                D.nextTier, D.nextTierRound, D.nextSquad, D.nextStandin, D.nextWhy = ti, D.round, sq, st, wy
                if not forced and gapWas then RUN.specialGap = gapWas end
            end
            log(string.format("round %d: no %s can come (%s); %s", D.round, special, tostring(why),
                alt and ("the " .. alt .. " instead") or (ti and "an ace round") or "a normal round"))
            special = alt
            if D.announced then roundCalloutAgain(alt) end
        end
    end
    if special == "valka" and SND and SND.preloadValka then pcall(SND.preloadValka) end   -- ((0.73.79) at the latest: sv_sound.lua)
    -- ((0.73.77) D4: the last round's special cleaned up now if its clean-up hadn't come yet, before it's replaced)
    if D.special and not D.special.cleaned then pcall(SPC.endTick, D.now or 0, D.special, "the next round's start", true) end
    D.special = special and { kind = special, state = "pending" } or nil
    RUN.specialPick = RUN.specialPick or {}                      -- (as it is: a forced one too; specialFor reads it)
    RUN.specialPick[D.round] = special or false
    D.specialAtWas = nil
    if special then
        RUN.lastSpecial = special
        RUN.specialAt = RUN.specialAt or {}
        D.specialAtWas = { kind = special, at = RUN.specialAt[special] }   -- ((0.73.80) given back if it never comes: SPC.unplan)
        RUN.specialAt[special] = D.round                    -- (its cooldown: specialFor)
    end
    if special == "amphibious" then                  -- a harder round: more escort (user: "make it difficult")
        budget = math.min(budget + (CFG.specials.amphibious.extra_aircraft or 0), TIER.roundCap(D.round))
    end
    -- (after the special's extra: capped first, then the %; before, an amphibious round above 100 % was cut back to 30)
    budget = math.max(1, math.floor(budget * SETUP.enemyX() + 0.5))     -- (the menu's ENEMY AIRCRAFT %, sv_menu.lua)
    -- (user, 2026-10-22: "when an ACE team spawns, no other aircraft other than those special to those levels should
    -- spawn"): an ace round (CFG.aces every) is its tier's squadrons throughout, with no bomber raid
    D.roundTier = nil
    -- ((0.73.78, plan G4) the squadron that flies it, D.roundSquad: the tier's own, or a stand-in for the top one at this
    -- tier's skill, CFG.aces.rotation; its size, D.aceNextAt; its break-off clock, D.aceBreak)
    D.roundSquad, D.aceNextAt, D.aceBreak = nil, nil, nil
    local aceTi, aceSq, aceStandin, aceWhy
    if D.nextTierRound == D.round and D.nextTier then              -- (the one its callout named)
        aceTi, aceSq, aceStandin, aceWhy = D.nextTier, D.nextSquad, D.nextStandin, D.nextWhy
    else
        aceTi, aceSq, aceStandin, aceWhy = aceRound(D.round, special)
    end
    if aceTi then
        local ti = aceTi
        local tn = CFG.tiers.list[ti].name
        if ACE.roster[tn:lower()] then
            D.roundTier = ti
            if not aceSq then aceSq, aceStandin, aceWhy = ACE.squadFor(D.round, ti) end
            if not (aceSq and ACE.roster[aceSq] and type(CFG.aces[aceSq]) == "table") then aceSq, aceStandin = tn:lower(), false end
            D.roundSquad = aceSq
            local c = CFG.aces[aceSq] or {}
            if D.aceRoundSaid ~= D.round then
                D.aceRoundSaid = D.round
                log(string.format("aces: round %d is a %s round (%s squadron only%s)", D.round, tn, tostring(c.squadron),
                    aceStandin and string.format(", standing in at the %s tier's skill: %s", tn, tostring(aceWhy)) or ""))
            end
            aceFlown(aceSq)
        end
    end
    D.nextTier, D.nextTierRound, D.nextSquad, D.nextStandin, D.nextWhy = nil, nil, nil, nil, nil
    -- ((0.73.78, plan G4) an ace round's own size, ACE.roundSize: x the menu's %, then co-op's more within its ceiling)
    local aceN, aceUp, aceNext, aceTop, aceUpTop = nil, nil, nil, nil, nil
    if D.roundTier then aceN, aceUp, aceNext, aceTop, aceUpTop = ACE.roundSize(D.round) end
    if aceN then
        local ex = SETUP.enemyX()
        local was = budget
        budget = math.max(2, math.floor(aceN * ex / 2 + 0.5) * 2)
        if COOP and COOP.more then budget = COOP.more(budget, "max_aircraft", math.max(budget, math.floor(aceTop * ex + 0.5))) end
        log(string.format("aces: round %d's squadron: %d aircraft (CFG.aces.round: %d, at most %d%s; a normal round's %d)",
            D.round, budget, aceN, aceTop, ex ~= 1 and string.format(", x%.2f the menu's", ex) or "", was))
    -- (co-op: more for more players, up to the room's cap, which grows with the late rounds: TIER.coopCap)
    elseif COOP and COOP.more then budget = COOP.more(budget, "max_aircraft", TIER.coopCap(D.round)) end
    D.budget = budget
    local spk = special and SPC.kinds[special]
    local alone = spk and SPC.kindValue(spk.alone)                  -- (a special that flies alone: no fighters)
    local raid = not special and not D.roundTier and CFG.airfield.enabled and D.round >= b.first_raid
        and (D.round - b.first_raid) % math.max(1, math.floor(b.raid_every)) == 0
    local bombers, nBombers = {}, 0
    local taken = {}                                -- (flights already picked this round: one pick never takes them again)
    D.taken = taken                                 -- (and the ALICORN's deck never launches one: sv_alicorn.lua deckFlight)
    local function pick(units, n, skip)
        local out, got = pickFlights(units, n, function(u) return taken[u] or (skip and skip(u)) end)
        for _, u in ipairs(out) do taken[u] = true end
        return out, got
    end
    -- ((0.73.77, the plan's I8 / I4 / I3) the Spaceport's part of the plan, before any flight is picked (sv_spaceport.lua
    -- SPORT.planRound): the Ford's deck flights held back from the round's fighters (S13: round 13's fighters took every
    -- free 2-ship, the deck launched 2 of 8), the fighters withdrawn at a capture recycled or kept out of the picks (S6),
    -- and a retake that didn't come taking its fleet off (S4))
    if SPORT and SPORT.planRound then
        local okSp, errSp = pcall(SPORT.planRound, special, pick)
        if not okSp then log("special: the Spaceport's round plan error " .. tostring(errSp)) end
    end
    do                                              -- ((0.73.78, plan G4) the flights an ace break-off despawned: aceGone)
        local okAg, errAg = pcall(aceGoneRecycle)
        if not okAg then log("aces: the break-off's recycle error " .. tostring(errAg)) end
    end
    local function raidShare()                      -- a raid's bombers: raid_share of the round, whole 2-ships, max_bombers
        return math.min(math.floor(budget * b.raid_share / 2 + 0.5) * 2, b.max_bombers or budget)
    end
    D.raidBearing, D.raidUnits, D.raidBombers, D.strikeAir, D.escortUnits = nil, {}, 0, {}, {}
    if raid then
        bombers, nBombers = pick(b.pool, raidShare(), function(u) return D.round < b.heavy_from_round and HEAVY_UNIT[u] end)
    elseif spk and spk.aircraft then                -- its own aircraft take that many of the round's
        nBombers = SPC.kindValue(spk.aircraft)
    elseif special == "amphibious" and CFG.airfield.enabled and math.random() < CFG.specials.amphibious.bomber_chance then
        raid = true                                   -- a raid on the airfield with the landing (its share of the budget)
        bombers, nBombers = pick(b.pool, raidShare(), function(u) return D.round < b.heavy_from_round and HEAVY_UNIT[u] end)
    elseif special == "shuttle" then             -- strike flights at the shuttle (heavies only bomb the airfield)
        local share = math.floor(budget * CFG.specials.shuttle.strike_share / 2 + 0.5) * 2
        bombers, nBombers = pick(b.pool, share, function(u) return HEAVY_UNIT[u] end)
    end
    if raid and #bombers > 0 then                   -- a raid from one direction (CFG.airfield.bombers.one_bearing)
        for _, u in ipairs(bombers) do D.raidUnits[u] = true end
        D.raidBombers = nBombers
        if b.one_bearing then D.raidBearing = raidBearing(b.distance_km) end
    end
    D.strikeUnits = {}                              -- (for the shuttle's countdown log)
    if special == "shuttle" then for _, u in ipairs(bombers) do D.strikeUnits[u] = true end end
    local normal = not raid and not special and not D.roundTier
    -- a normal round's strike package at the airfield (CFG.strike): one 2-ship, not a heavy
    local st = CFG.strike
    local stChance = st and st.chance or 0           -- (more often against a player who hugs the airfield: PROF, P6)
    if PROF and PROF.chance then
        local okC, x = pcall(PROF.chance, "strike", stChance)
        if okC and type(x) == "number" then stChance = x end
    end
    if normal and CFG.airfield.enabled and st and st.enabled and D.round >= st.from_round and math.random() < stChance then
        local sb, sn = pick(b.pool, 2, function(u) return HEAVY_UNIT[u] end)
        for _, u in ipairs(sb) do bombers[#bombers + 1] = u; D.strikeAir[u] = true end
        nBombers = nBombers + sn
        if #sb > 0 then log(string.format("round %d: a strike package (%s) goes for the airfield", D.round, sb[1])) end
    end
    -- allied ships at sea (CFG.allies): a normal round's strike flights at them, each at one ship (ace rounds are their
    -- squadron only), every ship_strike_every rounds
    D.shipStrike = {}
    local ships = (normal and CFG.allies.enabled and ALLY.shipsAtSea and D.round % math.max(1, CFG.allies.ship_strike_every or 1) == 0)
        and ALLY.shipsAtSea() or {}
    if #ships > 0 then
        local share = math.floor(budget * CFG.allies.strike_share / 2 + 0.5) * 2
        local sb, sn = pick(b.pool, share, function(u) return HEAVY_UNIT[u] end)
        for _, u in ipairs(sb) do bombers[#bombers + 1] = u; D.shipStrike[u] = ships[math.random(#ships)] end
        nBombers = nBombers + sn
        if #sb > 0 then log(string.format("round %d: %d strike aircraft in %d squadrons go for the allied ships", D.round, sn, #sb)) end
    end
    local nWant = alone and 0 or (budget - nBombers)
    if spk and spk.budget then nWant = spk.budget(budget) end      -- (VALKA's decoys: a few of the round's)
    -- a late special that flies alone brings escorts (CFG.specials escort_*)
    local sp = CFG.specials
    if special and alone and D.round >= (sp.escort_from or math.huge) then
        for _, k in ipairs(sp.escort_kinds or {}) do
            if k == special then
                nWant = math.max(sp.escort_min or 0, math.min(sp.escort_max or budget, math.floor(budget * (sp.escort_share or 0) / 2 + 0.5) * 2))
                log(string.format("round %d: the %s brings %d escorts", D.round, special, nWant))
            end
        end
    end
    -- the ALICORN's deck launches (CFG.specials.alicorn.deck, P7; sv_alicorn.lua SPC.alicornDeck): flights +
    -- flights_per_round a round, at most max_flights; its escorts (above) off the deck too, in flights of its size, none
    -- from a spawn point (escorts false: they come as before)
    D.deckLeft = nil
    local dk = special == "alicorn" and sp.alicorn and sp.alicorn.deck
    if type(dk) == "table" and dk.enabled then
        local n = math.min(math.floor(tonumber(dk.max_flights) or 0),
            math.floor(tonumber(dk.flights) or 0) + math.floor(D.round * (tonumber(dk.flights_per_round) or 0)))
        local esc = 0
        if dk.escorts and nWant > 0 then esc, nWant = math.ceil(nWant / math.max(1, math.floor(tonumber(dk.size) or 2))), 0 end
        D.deckLeft = math.max(0, n) + esc
        log(string.format("round %d: the Alicorn's deck launches up to %d flights of %d%s", D.round, D.deckLeft,
            math.floor(tonumber(dk.size) or 2), esc > 0 and string.format(" (%d of them its escorts)", esc) or ""))
    end
    -- (the fighter roles, CFG.roles: each role's share of the round from its own flights, an ace round's by its
    -- squadron's roles, P9's ace personalities (CFG.aces.flight <tier>.roles), else ace_mix; roles off or no level
    -- snapshot (ROLE.live): the whole pool as before)
    local fighters, nFighters
    if ROLE.live and nWant > 0 then
        -- ((0.73.78) the round's squadron's own roles: a stand-in's at a higher tier's skill too, D.roundSquad)
        local aceKey = D.roundTier and (D.roundSquad or (CFG.tiers.list[D.roundTier] and CFG.tiers.list[D.roundTier].name:lower())) or nil
        fighters, nFighters = ROLE.pickRound(nWant, pick, aceKey or D.roundTier ~= nil)
    else
        fighters, nFighters = pick(CFG.pool, nWant, function(u) return PROBE_OF[u] end)
    end
    -- the behaviour probe: round 1's first flight flies the package script, round 2's the run-time one
    local pv = CFG.probe.enabled and CFG.probe.behaviour and ((D.round == 1 and "Pkg") or (D.round == 2 and "Rt"))
    local pu = pv and CFG.probe.units[pv]
    if pu and not D.up[pu] and not taken[pu] and PR.usable[pv] and (pv == "Pkg" or (CFG.probe.runtime and GLS.injected[PROBE_RT_MODULE])) then
        table.insert(fighters, 1, pu)
        if #fighters > 1 then taken[table.remove(fighters)] = nil end
    end
    -- a raid's escorts (CFG.escorts): share of its fighter flights hold over the airfield; first in the queue
    local nEsc = 0
    if raid and CFG.escorts.enabled and #fighters > 0 then
        local n = math.ceil(#fighters * CFG.escorts.share)
        -- (not a Wolf flight: the escort's engagement order would free its held trap; the escorts first in the queue)
        local esc, rest = {}, {}
        for _, u in ipairs(fighters) do
            if #esc < n and poolIndex(u) and ROLE.flight(u) ~= "wolf" then esc[#esc + 1] = u else rest[#rest + 1] = u end
        end
        for _, u in ipairs(esc) do D.escortUnits[u] = true; nEsc = nEsc + 1 end
        for _, u in ipairs(rest) do esc[#esc + 1] = u end
        fighters = esc
    end
    -- the round's jammer (CFG.jammer): one fighter flight led by an EA-18G
    local jc = CFG.jammer
    D.jammerUnit, D.jammer = nil, nil
    local jcChance = jc and jc.chance or 0           -- (more often against a missile-heavy player: PROF, P6)
    if PROF and PROF.chance then
        local okC, x = pcall(PROF.chance, "jammer", jcChance)
        if okC and type(x) == "number" then jcChance = x end
    end
    if normal and jc and jc.enabled and D.round >= jc.from_round and math.random() < jcChance and SR.usable[jc.aircraft] then
        for _, u in ipairs(fighters) do                -- (a duelist or Skirmisher flight with roles on: ROLE.jammerOk)
            if not D.jammerUnit and poolIndex(u) and not PROBE_OF[u] and ROLE.jammerOk(u) then D.jammerUnit = u end
        end
        if D.jammerUnit then log(string.format("round %d: the jammer flies with %s", D.round, D.jammerUnit)) end
    end
    local cap
    if aceN then                                    -- ((0.73.78, plan G4) an ace round: at most `up` at once, CFG.aces.round)
        local ex = SETUP.enemyX()
        local up = math.max(2, math.floor(aceUp * ex + 0.5))
        if COOP and COOP.more then up = COOP.more(up, "max_up", math.max(up, math.floor(aceUpTop * ex + 0.5))) end
        D.aceNextAt = math.max(0, math.min(aceNext, up - 2))   -- (a wave of 2 at least)
        cap = math.max(2, up - D.aceNextAt)
        log(string.format("aces: round %d: at most %d of them up at once: waves of %d, the next when %d or fewer are left",
            D.round, up, cap, D.aceNextAt))
    else
        cap = waveCap(D.round)
        if COOP and COOP.more then cap = COOP.more(cap, "max_up") end       -- (co-op: more for more players)
    end
    D.waves = makeWaves(spk and special or nil, fighters, bombers, cap)
    D.wave, D.queue = 1, D.waves[1]
    D.spare = {}
    for _, u in ipairs(CFG.pool) do                 -- spares: free 2-ship flights, for a flight that fails to spawn
        if not D.up[u] and not taken[u] and not PROBE_OF[u] and not ROLE.sitsOut(u) and flightSize(u) == 2 then D.spare[#D.spare + 1] = u end
    end
    local waveText = ""
    if #D.waves > 1 then
        local sizes = {}
        for _, w in ipairs(D.waves) do
            local n = 0
            for _, u in ipairs(w) do if u:sub(1, 1) ~= "@" then n = n + flightSize(u) end end
            sizes[#sizes + 1] = tostring(n)
        end
        waveText = string.format(", %d waves (%s aircraft)", #D.waves, table.concat(sizes, " + "))
    end
    log(string.format("round %d: %d aircraft: %d fighters in %d squadrons%s%s%s; cap %d, up to %d at once", D.round,
        nFighters + nBombers, nFighters,
        #fighters, raid and string.format(", bomber raid: %d bombers in %d squadrons%s", nBombers, #bombers,
            D.raidBearing and string.format(" from the %s (bearing %d)", compassName(D.raidBearing), D.raidBearing) or "")
        or special and string.format(", special %s: %d strike aircraft in %d squadrons", special, nBombers, #bombers) or "",
        nEsc > 0 and string.format(", %d escort flights", nEsc) or "", waveText, TIER.roundCap(D.round), cap))
    -- (whole 2 / 4 / 6-ships lose an odd budget's last one; more than that is the pool: 22 fighter flights, 86
    -- aircraft, the ones still up skipped; ENEMY AIRCRAFT above 100 % or co-op can ask more of late rounds)
    if nWant - nFighters >= 2 then
        log(string.format("round %d: pool short: %d of %d fighters (%d spare 2-ships)", D.round, nFighters, nWant, #D.spare))
    end
    local okP, errP = pcall(roundPressure, special) -- (the game's attack throttle for the round: CFG.late.pressure)
    if not okP then log("pressure: error " .. tostring(errP)) end
    -- ((0.73.79, the lag audit's item 2) the game's whole unit list, a native log line each: [log] verbose only)
    if logVerbose() and type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " start") end
    D.state, D.at, D.lastAlive, D.waveAt = "spawning", D.now, nil, D.now
    -- ((0.73.78, plan G4) an ace round's clock to its break-off, CFG.aces.break_off: aceBreakTick)
    local bo = CFG.aces.break_off
    if D.roundTier and type(bo) == "table" and bo.enabled then D.aceBreak = { state = "on", t = 0, seen = D.now, n = nFighters } end
    RUN.roundKills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 }
    pcall(STATS.roundStart, D.now)                  -- (the round's measurements, sv_stats.lua)
    if DIR then                                     -- (the squad director, P2: the round's budgets, wave 1's pincer)
        local okDr, errDr = pcall(DIR.roundStart, D.now)
        if okDr then okDr, errDr = pcall(DIR.wave, D.now) end
        if not okDr then log("director: round start error " .. tostring(errDr)) end
    end
end

-- The player on the ground at the airfield (landed, rolling or in the landing menu): within 3 km of the runway and
-- under 100 m, or nowhere to be read (the landing menu may hide the aircraft). Landing isn't closed under a player
-- who may be down there, so they can always take off again. you: where the player is, when already read this tick.
function playerOnAirfield(you)
    you = you or playerLocation()
    if not you then return true end
    local dx, dy = you.X - AIRFIELD.X, you.Y - AIRFIELD.Y
    return math.sqrt(dx * dx + dy * dy) < 300000 and you.Z < 10000
end

-- The other players flying (a co-op host's: alive, in the mission, not down at the airfield themselves; COOP.players()),
-- 0 solo or on a joiner. While you're down at the airfield, the spawns, a flight's orders, the wave clock, the Wolf trap's
-- clock and the ALICORN's deck wait for your takeoff only when it's 0 (user, 2026-10-29: "when the HOST is landed at the
-- airfield that the game isn't paused for the other players"; Shazzy's host log of 2026-10-25: holds of 10-43 s), and so
-- do the shuttle's countdown and its invulnerability (user, the same day: "Keep it running while others are flying").
-- (co-op host) a round held while a linked player isn't in the mission yet (sv_coop.lua COOP.joinWaiting): no round
-- start, no spawns; callout and log once a hold, and when it ends
function joinHold(now)
    local names = COOP and COOP.joinWaiting and COOP.joinWaiting(now)
    if names and #names > 0 then
        local who = table.concat(names, ", ")
        if D.joinHeld ~= who then
            D.joinHeld = who
            hudCallout("WAITING FOR PLAYERS", string.upper(who))
            log(string.format("round %d: enemy spawns paused while %s join%s the mission", D.round or 0, who, #names == 1 and "s" or ""))
        end
        return true
    end
    if D.joinHeld then
        log(string.format("round %d: everyone's in the mission: spawns go on", D.round or 0))
        D.joinHeld = nil
    end
    return false
end

function othersFlying()
    if not (COOP and COOP.host and COOP.host()) then return 0 end
    local n = 0
    for _, e in ipairs(COOP.players()) do
        if not e.isMe and e.alive and e.fresh and not e.onAirfield then n = n + 1 end
    end
    return n
end

local ordersTick
do
-- A fighter flight's orders (player only, air search) come from its appearance trigger, which also sets SV_Up_NN. One
-- that appeared while the landing menu was up never got them (test of 2026-10-22: two F-16 flights attacked the
-- airfield), so a flight still unflagged CFG.orders_check_s after spawning gets them from RE_SV_FlightOrders_NN. Down at
-- the airfield its tries wait for your takeoff; in co-op with another player flying it's fired then too, again every
-- 5 s while you're down and not counted as a try (whether it fires with your landing menu up isn't known), and the
-- tries come after your takeoff as ever.
function ordersTick(now)
    for u, o in pairs(D.orders) do
        if now >= o.at then
            local i, t = poolIndex(u), svFlags()
            local down = t and playerOnAirfield()
            local flying = down and othersFlying() or 0
            if not i or ALIVE.ask(u, now) <= 0 then
                D.orders[u] = nil
            elseif not t or (down and flying == 0) then  -- grounded: the landing menu may be up
                o.at = now + 1
            elseif (t[string.format("SV_Up_%02d", i)] or 0) >= 1 then
                if o.tries > 0 or o.downTries then
                    log("orders: " .. u .. " has its orders now" .. (o.downTries and string.format(" (%d fired while you were "
                        .. "down at the airfield)", o.downTries) or ""))
                end
                D.orders[u] = nil
            elseif down and type(SV_Event) == "function" then  -- (co-op: you down, another player flying)
                o.downTries, o.at = (o.downTries or 0) + 1, now + 5
                local ev = string.format("RE_SV_FlightOrders_%02d", i)
                local r = SV_Event(ev)
                if o.downTries == 1 then
                    log(string.format("orders: %s appeared without its orders while you're down at the airfield (%s); %s %s "
                        .. "(again every 5 s while you're down, not a try)", u, flyingText(flying), ev,
                        r == 1 and "fired" or ("not fired (" .. (SV_ERR[r] or tostring(r)) .. ")")))
                end
            elseif o.tries >= 3 or type(SV_Event) ~= "function" then
                log("orders: " .. u .. " never got its orders (SV_Up_" .. string.format("%02d", i) .. " still 0)")
                D.orders[u] = nil
            else
                o.tries, o.at = o.tries + 1, now + 5
                local ev = string.format("RE_SV_FlightOrders_%02d", i)
                local r = SV_Event(ev)
                log(string.format("orders: %s appeared without its orders; %s %s", u, ev,
                    r == 1 and "fired" or ("not fired (" .. (SV_ERR[r] or tostring(r)) .. ")")))
            end
        end
    end
end
end

-- (0.73.77, plan A7; IMPROVEMENTS.md "End the long tail") The host's (or solo), once a second while a round's fighting:
-- `alive` aircraft of the round up. With max_left or fewer left and no kill (nor a new flight) for quiet_s, each flight
-- still up is pinged on the minimap (RE_SV_LastPing_NN on a pool flight, a bomber flight's own RE_SV_RaidPing_NN: Mission
-- 22's LiveBattleNavigationExecution, forwarded to co-op joiners, whose copies ping too), again every every_s till the
-- next kill, and (release) any of them held back is let go: a Wolf trap freed onto you (WOLF.free, its LastTGT), a top
-- cover diving on the nearest player (DIR.release). The 0.73.76 runs waited up to 9 min 11 s on a round's last enemy
-- (Saint Alessia's round 5); the Spaceport round's last 3 min were one held Wolf trap (S14).
local function tailTick(now, alive)
    local c = CFG.waves and CFG.waves.tail
    if not (type(c) == "table" and c.enabled) then return end
    if D.aceBreak and D.aceBreak.state == "leaving" then return end   -- ((0.73.78) an ace break-off's: none freed, none pinged)
    local T = D.tail
    if not T or T.round ~= D.round or alive ~= T.alive then        -- (a kill, or a new flight: its clock again)
        if T and T.pings and T.round == D.round and alive < T.alive then
            log(string.format("round %d: a kill %.0f s after the tail's first ping (%d left)", D.round, now - (T.firstAt or now), alive))
        end
        D.tail = { round = D.round, alive = alive, since = now }
        return
    end
    if alive < 1 or alive > (tonumber(c.max_left) or 4) then return end
    if now - T.since < (tonumber(c.quiet_s) or 90) or now < (T.nextAt or 0) then return end
    T.nextAt = now + math.max(3, tonumber(c.every_s) or 12)
    T.firstAt = T.firstAt or now
    local pinged, missed, freed = {}, {}, {}
    local units = {}
    for u in pairs(D.up) do units[#units + 1] = u end
    table.sort(units)
    for _, u in ipairs(units) do
        if ALIVE.ask(u, now) > 0 then
            local i, b = poolIndex(u), BOMBER_INDEX and BOMBER_INDEX[u]
            local ev = (i and string.format("RE_SV_LastPing_%02d", i)) or (b and string.format("RE_SV_RaidPing_%02d", b)) or nil
            local r = (ev and type(SV_Event) == "function") and SV_Event(ev) or nil
            if r == 1 then pinged[#pinged + 1] = u
            else missed[#missed + 1] = u .. (ev and (" (" .. (SV_ERR[r] or tostring(r)) .. ")") or " (no ping event: a special's)") end
            if c.release then
                if WOLF and WOLF.holding and WOLF.holding(u) then
                    local okW, n = pcall(WOLF.free, u, "the round's last enemies", true, nil, now)
                    if okW and type(n) == "number" and n > 0 then freed[#freed + 1] = u .. " (its Wolf trap, " .. n .. ")" end
                end
                if DIR and DIR.holding and DIR.holding(u) then
                    local okD, did = pcall(DIR.release, u, "the round's last enemies")
                    if okD and did then freed[#freed + 1] = u .. " (held by the director)" end
                end
            end
        end
    end
    T.pings = (T.pings or 0) + 1
    if (#pinged > 0 or #freed > 0) and (T.pings == 1 or T.pings % 5 == 0 or #freed > 0) then   -- (a boss alone: nothing to say)
        log(string.format("round: last %d enemies pinged on the minimap (round %d, no kill for %.0f s; ping %d): %s%s%s", alive,
            D.round, now - T.since, T.pings, #pinged > 0 and table.concat(pinged, ", ") or "none",
            #missed > 0 and ("; not pinged: " .. table.concat(missed, ", ")) or "",
            #freed > 0 and ("; let go: " .. table.concat(freed, ", ")) or ""))
    end
end

function roundsTick(now)
    if not D then return end
    D.now = now
    if not nativeReady() then
        if not D.warned then log("rounds: the native spawner (dlls\\main.dll 0.6.0) did not register SV_Spawn: no enemies"); D.warned = true end
        return
    end
    -- ((0.73.80) the tick's SV_UnitAlive budget, its oldest answers asked again first: ALIVE, sv_spawn.lua)
    local okAl, errAl = pcall(ALIVE.tick, now)
    if not okAl and tostring(errAl) ~= D.aliveErr then D.aliveErr = tostring(errAl); log("alive: error " .. D.aliveErr) end
    D.orders = D.orders or {}
    ordersTick(now)
    eventsTick(now)
    -- every tick, whatever the round's state (code review of 2026-10-23: in the break it never ran, so the shuttle's
    -- removal and the Anomaly's lightning clean-up waited for the next round, and while fighting it ran once a second,
    -- which rounded the portal's timing)
    if D.shuttleClock then                          -- (the shuttle's countdown stops while you're down, but not in co-op
        D.grounded = playerOnAirfield()             -- while another player flies)
        D.othersFlying = D.grounded and othersFlying() or 0
    end
    specialTick(now)
    pressureAfterBoss(now)                          -- (the band's attack throttle again once an Anomaly / VALKA is down)
    local okW, errW = pcall(WOLF.tick, now)          -- (the Wolf trap's holds and releases: CFG.roles.wolf, sv_spawn.lua)
    if not okW and tostring(errW) ~= D.wolfErr then D.wolfErr = tostring(errW); log("roles: wolf error " .. D.wolfErr) end
    if D.aceBreak and D.state ~= "wait" then         -- ((0.73.78, plan G4) an ace round's break-off: CFG.aces.break_off)
        local okB, errB = pcall(aceBreakTick, now)
        if not okB and tostring(errB) ~= D.aceBreakErr then D.aceBreakErr = tostring(errB); log("aces: break-off error " .. D.aceBreakErr) end
    end
    if D.state == "wait" then
        if not D.announced and now >= D.at - CFG.hud.start_callout_lead_s then
            D.announced = true
            local t = CFG.hud.text
            local nextSpecial = D.forceSpecial or specialFor(D.round + 1)
            if nextSpecial == "valka" and SND and SND.preloadValka then pcall(SND.preloadValka) end   -- ((0.73.79) her sounds now, not mid-fight)
            -- (once: it picks the tier; (0.73.78) and the squadron, CFG.aces.rotation)
            local nextAce, nextSq, nextStandin, nextWhy = aceRound(D.round + 1, nextSpecial)
            local nk = nextSpecial and SPC.kinds[nextSpecial]
            if nk and SPC.kindValue(nk.disguise) then nk = nil end      -- (VALKA: called out as a normal round)
            if nk then
                hudCallout(string.format(t.special, D.round + 1), type(nk.sub) == "function" and nk.sub(t) or t[nk.sub])
            elseif nextAce then
                D.nextTier, D.nextTierRound = nextAce, D.round + 1   -- startRound flies this one
                D.nextSquad, D.nextStandin, D.nextWhy = nextSq, nextStandin, nextWhy
                local tn = (nextSq and type(CFG.aces[nextSq]) == "table") and nextSq or CFG.tiers.list[D.nextTier].name:lower()
                local c = CFG.aces[tn] or {}
                hudCallout(string.format(t.start, D.round + 1), string.format(t.aces_round, tostring(c.squadron or tn):upper()))
            else
                hudCallout(string.format(t.start, D.round + 1), t.start_sub)
            end
            local level = levelFor(D.round + 1)           -- (the spike's, or the intensity director's under it: P4)
            if level > levelFor(D.round) then
                hudCallout(t.spike, t.spike_sub)
                local ceil = spikeLevel(D.round + 1)
                log(string.format("spikes: round %d, difficulty level %d%s", D.round + 1, level,
                    ceil ~= level and string.format(" (the spikes' %d, eased by the intensity director)", ceil) or ""))
            end
        end
        if now >= D.at and not joinHold(now) then startRound() end
    elseif D.state == "spawning" then
        if now < D.at then return end
        if joinHold(now) then D.at = now + 1; return end
        local flying = playerOnAirfield() and othersFlying()
        if flying == 0 then                        -- the landing menu may be up, and a flight that appears then gets no orders
            if D.held ~= D.round then D.held = D.round; log(string.format("round %d: spawns held while you are down at the airfield", D.round)) end
            D.at = now + 1
            return
        elseif flying then                         -- (co-op: not while another player flies; ordersTick gives them orders)
            if D.held == D.round or D.goneOn ~= D.round then
                D.held, D.goneOn = nil, D.round
                log(string.format("round %d: spawns go on while you're down at the airfield (%s)", D.round, flyingText(flying)))
            end
        end
        if D.held == D.round then D.held = nil; log(string.format("round %d: you took off, spawns go on", D.round)) end
        -- (the intensity director's hold, P4: the rest of a later wave waits while a player's under heavy pressure, a
        -- hold that starts here, its next flight due; never a round's first wave or a special's entry; the hold's own
        -- length is its limit)
        local nq = D.queue and D.queue[1]
        if (D.wave or 1) > 1 and type(nq) == "string" and nq:sub(1, 1) ~= "@" and DIR and DIR.holdWave and DIR.holdWave(now, "spawning") then
            D.at = now + 1
            return
        end
        -- ((2026-11-08) a special that holds the round's fighters until it's under way (its kind's hold: THE FESTIVAL's
        -- come with its Tu-160s, not during its talk)
        local hk = D.special and SPC.kinds[D.special.kind]
        if type(nq) == "string" and nq:sub(1, 1) ~= "@" and hk and hk.hold then
            local okH, held = pcall(hk.hold, now, D.special)
            if okH and held then
                if D.specialHeld ~= D.round then
                    D.specialHeld = D.round
                    log(string.format("round %d: its fighters held until the %s is under way", D.round, D.special.kind))
                end
                D.at = now + 0.5
                return
            elseif D.specialHeld == D.round then
                D.specialHeld = -1
                log(string.format("round %d: the %s is under way: its fighters come now", D.round, D.special.kind))
            end
        end
        local u = table.remove(D.queue, 1)
        local sk = type(u) == "string" and u:sub(1, 1) == "@" and SPC.kinds[u:sub(2)]
        if sk then
            if not sk.spawn(now) then                -- it can't come: a normal round (its fighters, if it flies alone)
                local alone = SPC.kindValue(sk.alone)
                -- ((0.73.80) its pick and cooldown given back, strike flights replaced, the callout: SPC.unplan)
                local okU, errU = pcall(SPC.unplan, u:sub(2), now, "its spawn refused")
                if not okU then log("special: unplan error " .. tostring(errU)); D.special, RUN.specialPick[D.round] = nil, false end
                local f = alone and pickFlights(CFG.pool, D.budget or CFG.aircraft_round1, function(q) return PROBE_OF[q] or ROLE.sitsOut(q) end) or {}
                for _, q in ipairs(f) do D.queue[#D.queue + 1] = q end
                log(string.format("round %d: no %s; %d fighter flights instead", D.round, u:sub(2), #f))
            end
        elseif u then
            local r = spawnFlight(u)
            if r == -1 then log("rounds: left Survival's level, rounds stopped"); D = nil; return end
            if (r == 0 or r == -2 or r == -3) and #D.spare > 0 then        -- this flight can't come: send a spare
                local s = table.remove(D.spare, 1)
                log(string.format("round %d: sending %s instead", D.round, s))
                table.insert(D.queue, 1, s)
            end
        end
        local gapAdd = 0                            -- (the intensity director, P4: flights further apart while you're pressed)
        if type(u) == "string" and u:sub(1, 1) ~= "@" and DIR and DIR.gap then
            local okG, g = pcall(DIR.gap, now)
            if okG and type(g) == "number" then gapAdd = g end
        end
        D.at = now + CFG.spawn_gap_s + gapAdd
        if #D.queue == 0 then
            -- the next wave once this one thins out; its clock (CFG.waves.timeout_s) from this wave's last flight, not
            -- the round's start (a run of 2026-10-24: wave 1 held 3 min while the player was down at the airfield,
            -- then wave 2 came 9 s after it, its 150 s long gone)
            if D.waves and D.wave < #D.waves then D.state, D.waveAt, D.waveSeen = "wave", now, now
            else D.state = "fighting" end
        end
    elseif D.state == "wave" then                    -- (CFG.waves) the round's aircraft left, once a second
        if now < D.at then return end
        D.at = now + 1
        -- (the clock stops while you're down, but not in co-op while another player flies)
        if playerOnAirfield() and othersFlying() == 0 then D.waveAt = D.waveAt + (now - (D.waveSeen or now)) end
        D.waveSeen = now
        local alive = 0
        -- (the Spaceport Assault's Tu-160s, sv_spaceport.lua SPORT.tuTick, aren't the fighters' wave: on top of the round,
        -- they don't hold its next wave back; the round's end waits for them, the "fighting" check below)
        local tuU = D.special and type(D.special.tu) == "table" and D.special.tu.units or nil
        for u in pairs(D.up) do
            local n = ALIVE.ask(u, now)                -- ((0.73.80) at most ~1 s old: spread over the ticks)
            if n > 0 then
                if not (tuU and tuU[u]) then alive = alive + n end
            else D.up[u] = nil end
        end
        local w = CFG.waves
        local timedOut = (w.timeout_s or 0) > 0 and now - D.waveAt >= w.timeout_s       -- (0: by kills only)
        local nextAt = D.aceNextAt or w.next_at        -- ((0.73.78, plan G4) an ace round's own: CFG.aces.round next_at)
        -- (the intensity director, behaviour roadmap P4: "above 80 intensity it holds the next wave back, so a bigger
        -- round is longer, not denser": asked only once the gate's open, the wave due, DIR.holdWave starts its hold
        -- then, or says the one on; it ends by itself, 30 s at most)
        if (alive <= nextAt or timedOut) and not (DIR and DIR.holdWave and DIR.holdWave(now, "wave")) then
            D.wave, D.waveAt = D.wave + 1, now
            D.queue = D.waves[D.wave]
            local n = 0
            for _, u in ipairs(D.queue) do if u:sub(1, 1) ~= "@" then n = n + flightSize(u) end end
            log(string.format("round %d: wave %d of %d (%d aircraft) with %d of the last wave's left%s", D.round, D.wave,
                #D.waves, n, alive, alive > nextAt and string.format(" (%d s on)", w.timeout_s) or ""))
            if w.callout then
                local t = CFG.hud.text
                hudCallout(string.format(t.wave_in, D.wave, #D.waves), string.format(t.wave_in_sub, n))
            end
            local wf = TELL and tonumber(CFG.tells.wave_from_round) or 0        -- (late rounds: a radio call too, P3)
            if wf > 0 and D.round >= wf then pcall(TELL.say, "wave", TELL.ALL) end
            if DIR then                                 -- (the squad director's pincer, P2: this wave from two sides?)
                local okDr, errDr = pcall(DIR.wave, now)
                if not okDr then log("director: wave error " .. tostring(errDr)) end
            end
            D.state = "spawning"
        end
    elseif D.state == "fighting" then
        if now < D.at then return end
        D.at = now + 1
        local alive, flights = 0, 0
        for u in pairs(D.up) do
            local n = ALIVE.ask(u, now)                -- ((0.73.80) at most ~1 s old; a kill seen by the sweep: asked at once)
            if n > 0 then alive, flights = alive + n, flights + 1 else D.up[u] = nil end
        end
        if alive ~= D.lastAlive then log(string.format("round %d: %d aircraft in %d flights left", D.round, alive, flights)); D.lastAlive = alive end
        if flights > 0 then                                -- ((0.73.77) A7: the round's last enemies on the minimap)
            local okT, errT = pcall(tailTick, now, alive)
            if not okT and tostring(errT) ~= D.tailErr then D.tailErr = tostring(errT); log("round: tail error " .. D.tailErr) end
        end
        if flights == 0 and D.special and (D.special.state == "countdown" or D.special.state == "portal") then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: enemies down, the %s goes on", D.round,
                D.special.state == "portal" and "Anomaly's portal" or "shuttle's countdown")) end
        elseif flights == 0 and D.special and D.special.kind == "alicorn" and D.special.state == "sail" then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: the Alicorn is still afloat", D.round)) end
        elseif flights == 0 and D.special and D.special.kind == "ladon" and SPC.ladonBusy(D.special) then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: the Ladons are still up", D.round)) end
        elseif flights == 0 and D.special and D.special.kind == "valka"
            and (D.special.state == "lurk" or D.special.state == "opener" or D.special.state == "shot") then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: decoys down, VALKA attacks", D.round)) end
        elseif flights == 0 and D.special and D.special.kind == "amphibious" and AMPH.busy(D.special) then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: enemies down, the landing goes on", D.round)) end
        elseif flights == 0 and D.special and SPC.kinds[D.special.kind] and SPC.kinds[D.special.kind].busy
            and SPC.kinds[D.special.kind].busy(D.special) then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: enemies down, the %s goes on", D.round, D.special.kind)) end
        elseif flights == 0 then
            if D.special and D.special.kind == "amphibious" then AMPH.roundOver(now, D.special) end
            local ko = D.special and SPC.kinds[D.special.kind]
            if ko and ko.over then
                local okO, errO = pcall(ko.over, now, D.special)
                if not okO then log("special: " .. tostring(D.special.kind) .. " round end error " .. tostring(errO)) end
            end
            if D.special then pcall(SPC.endTick, now, D.special, "its round clear") end   -- ((0.73.77) D4: the backstop)
            local gap = SETUP.breakS()                 -- (the menu's BREAK BETWEEN ROUNDS, sv_menu.lua)
            local fb = D.special and D.special.kind == "festival" and tonumber((CFG.specials.festival or {}).break_after_s)
            if fb and fb > gap then gap = math.floor(fb) end   -- ((2026-11-07) "the ending timer for the next round last 60 seconds")
            log(string.format("round %d clear; round %d in %d s", D.round, D.round + 1, gap))
            addCredits(CFG.credits.round_bonus * D.round, "round " .. D.round .. " cleared")
            if logVerbose() and type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " clear") end
            pcall(ALIVE.report, D.round)              -- ((0.73.80) the round's SV_UnitAlive asks and the oldest answer used)
            D.state, D.at, D.announced = "wait", now + gap, false
            hudCallout(string.format(CFG.hud.text.complete, D.round),
                       string.format(CFG.hud.text.complete_sub, gap))
            -- ((2026-11-07) "the round before an Anomaly Round appears, a Subtitle from Charlene": the next round's special
            -- drawn now, her warning for an Anomaly; sv_escort_subs.lua)
            if ESUB and ESUB.warnNext then
                local okWn, errWn = pcall(ESUB.warnNext, D.round + 1, now)
                if not okWn then log("escort subs: warning error " .. tostring(errWn)) end
            end
            -- who shot down what (CFG.allies.kills; economy review of 2026-10-25: "show what allies do"), when anyone but
            -- you did
            local k = RUN.roundKills
            if k then
                log(string.format("kills: round %d: you %d, allied aircraft %d, ships %d, airfield defences %d, airstrikes %d",
                    D.round, k.you, k.allies, k.ships, k.defences, k.airstrike))
                if k.allies + k.ships + k.defences > 0 then
                    local t = CFG.hud.text
                    -- ((0.73.83) this game's own: each joiner shows its own count, not the host's)
                    local show = (COOP and COOP.localCallout) or hudCallout
                    show(string.format(t.kills, D.round), string.format(t.kills_sub, k.you + k.airstrike, k.allies, k.ships, k.defences))
                end
            end
            pcall(STATS.roundEnd, now)                -- (its "stats:" line a few seconds on: sv_stats.lua)
            pcall(ALLY.repairAll)                     -- (CFG.allies.repair: allies and defences back to full)
        end
    end
end

---------------------------------------------------------------------------------------------------- airfield
-- Survival's event package counts every enemy weapon that ends on one of the airfield's 4 target points in the int
-- flag SV_AirHits (tools/survival_events.py); the airfield's health is worked out here from the hits since the last
-- repair, so nothing has to write the flag. SV_Event (dlls/main.dll 0.9.0) fires RE_SV_AirfieldClose / Open, which
-- switch landing off and on (Mission 22's LiveSetTakeoffAndLandingEventExecution).
local function intFlag(name)
    local t = svFlags()
    return t and t[name]
end

function airfieldEvent(name)
    if type(SV_Event) ~= "function" then return " (no SV_Event: dlls/main.dll older than 0.9.0)" end
    local r = SV_Event(name)
    return r == 1 and (" (" .. name .. ")") or (" (" .. name .. " not fired: " .. (SV_ERR[r] or tostring(r)) .. ")")
end

function airfieldTick(tick)
    local ac = CFG.airfield
    if not ac.enabled or not D or tick % 4 ~= 0 then return end
    local t = CFG.hud.text
    local hits = intFlag("SV_AirHits")
    if hits == nil then return end
    if AF.base == nil then AF.base, AF.hits = hits, hits; log("airfield: health " .. AF.hp .. " (hits so far " .. hits .. ")") end
    for i = #AF.pending, 1, -1 do                   -- heavy bombers' bomb runs (bombTick), as the bombs land
        if tick >= AF.pending[i].due then AF.bomb = AF.bomb + AF.pending[i].dmg; table.remove(AF.pending, i) end
    end
    -- a hit count below the last one is a mission restart (the flags start over; the restart check resets the run a
    -- tick later): no damage from it (log of 2026-10-22: "health 116" and an AIRFIELD UNDER ATTACK callout on a retry)
    if hits < AF.hits then return end
    local hp = math.max(0, math.min(AF.max or CFG.airfield.hp, AF.full - (hits - AF.base) * ac.hit_damage - (AF.bomb - AF.bombBase)))
    if hits ~= AF.hits or hp ~= AF.hp then
        AF.hits = hits
        if hp ~= AF.hp then
            AF.hp, RUN.dirty = hp, true
            log(string.format("airfield: hit (%d hits, %d bomb damage), health %d", hits, AF.bomb, hp))
            if hp <= 0 and not AF.down then
                AF.down, AF.downRound, AF.closePending = true, D.round, true
                hudCallout(t.airfield_down, string.format(t.airfield_down_sub, D.round + 1))   -- airfieldTick reopens it then
                log("airfield: down")
                LB.stat("af_down", 1)
            elseif hp > 0 and AF.attackRound ~= D.round then
                AF.attackRound = D.round
                hudCallout(t.under_attack, nil)
            end
        end
    end
    if AF.closePending then
        if playerOnAirfield() then
            if not AF.closeHeld then AF.closeHeld = true; log("airfield: down, landing stays open until you take off") end
        else
            AF.closePending, AF.closed = false, true
            log("airfield: landing closed" .. airfieldEvent("RE_SV_AirfieldClose"))
        end
    end
    if AF.down and D.state == "wait" and D.round > AF.downRound then
        local reopen = AF.closed
        local back = math.max(1, math.floor(ac.repair_hp * SETUP.airfieldX() + 0.5))   -- (the menu's AIRFIELD HEALTH)
        AF.down, AF.full, AF.base, AF.bombBase, AF.hp = false, back, hits, AF.bomb, back
        AF.closePending, AF.closeHeld, AF.closed, RUN.dirty = false, false, false, true
        hudCallout(t.airfield_up, t.airfield_up_sub)
        if reopen and RUN.captured then                -- captured: it opens when it's retaken (AMPH)
            reopen = false; RUN.captured.closed = true
        end
        log("airfield: repaired to " .. back .. (reopen and (", landing open" .. airfieldEvent("RE_SV_AirfieldOpen")) or ""))
    end
end
