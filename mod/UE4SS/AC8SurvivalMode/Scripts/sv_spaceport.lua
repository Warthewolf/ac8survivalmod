-- sv_spaceport.lua: the Spaceport Assault and its retake.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_spaceport, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- spaceport assault
-- The user's special of 2026-10-31 (tools/re/SPACEPORT_ASSAULT.md; CFG.specials.spaceport; tools/survival_events.py SP_*
-- builds the units, paths and records). An enemy fleet off the spaceport's west shore, one ship a unit: the Ford
-- SV_Unit_SpFord, the Wasps SV_Unit_SpWasp<g> (groups A-D), Aegis SV_Unit_SpAegis<A-N> (A-H two a group, I-N round
-- the Ford) and missile boats SV_Unit_SpBoat<A-H> (two a group). Each Wasp afloat sends a wave of two landing craft
-- (SV_Unit_SpLcac<g><w>, waves V-Z) every wave_every_s; a craft that lands sets SV_SpLand<g><w><c> and puts its troops
-- ashore (SV_Unit_SpTroops<g><w><c>, invincible this round), who drive to their spot by the spaceport (SV_SpAt<g><w><c>):
-- capture_per_troop % of its capture, and they go in (taken off troop_stay_s later). At 100 % it's captured: no more
-- landings, and the round after is the retake (RUN.sport); every ship sunk and nothing still coming in short of 100 %:
-- held, `reward`. The Ford launches fighters off its deck while it's afloat (deck). The retake (CFG.specials.spaceport
-- .retake): the garrison (SV_Unit_SpGarrison<A-C>, targets, as many units as the troops that got in need) and every ship
-- still afloat from the assault; the round ends when they and its aircraft are down. The host's (or solo): the rounds'
-- ticks; the spawns and remote events reach the joiners as every special's do.
-- (0.73.77, the 1.0.0 plan's Workstream I: testing/2026-11-03/PLAN_desync_lag_compatibility.md, the review's S1-S13 in
-- testing/2026-11-03/IMPROVEMENTS.md, the economy's C2) A ship is counted by its hull: paid and called out once when its
-- hull goes, its turrets finished off with it, afloat only while the hull lives (a turret shot off alone pays
-- pay.turret). The landing craft's pay reaches the joiners, and the escape penalty comes off every game's zollars. A
-- fleet no retake can follow is taken off, and a later Spaceport takes leftovers off instead of refusing to come. The
-- fighters withdrawn at a capture are recycled when the next round is planned (SV_Recycle) or kept out of its picks.
-- The rockets always end (a timeout; an escape only from escape_min_m up), their debris only once a split is seen.
-- The waves' and the rockets' clocks wait while you're down at the airfield with nobody else flying. The capture's
-- share is whole. The pending retake is shared with the joiners (their NEXT row, a host migration). The Ford's deck
-- flights are held back when the round is planned.
SPORT = {}
do
local GROUPS, WAVES, CRAFT, GARRISON = { "A", "B", "C", "D" }, { "V", "W", "X", "Y", "Z" }, { "L", "R" }, { "A", "B", "C" }
local AEGIS, BOATS = "ABCDEFGHIJKLMN", "ABCDEFGH"
local FORD = "SV_Unit_SpFord"
local DECK_FLOOR_M = 1100                         -- (the pool's 2-ship units fly 1000 m and up, as the Alicorn's deck)

local function cfg() return CFG.specials.spaceport end
local function tierPay(base) return (TIER.pay(base * TIER.specialX(), D and D.round and TIER.index(D.round))) end
local function fire(name) return tostring(type(SV_Event) == "function" and SV_Event(name) or "n/a") end
-- ((review of 0.73.80) co-op: what's taken off without a kill goes down as nobody's on the host (sv_coop.lua
-- COOP.takenOff), not as a kill of the player who once hit it; then the removal event
local function offFire(unit, name)
    if COOP and COOP.takenOff then pcall(COOP.takenOff, unit) end
    return fire(name)
end
local function fleetFire()                         -- (the fleet's ships still up, each unit's: RE_SV_SpFleetRemove)
    if COOP and COOP.takenOff and SPORT.fleet then
        for _, sh in ipairs(SPORT.fleet()) do pcall(COOP.takenOff, sh.unit) end
    end
    return fire("RE_SV_SpFleetRemove")
end
-- (0.73.80, R30_FINDINGS perf 2: the once-a-second looks asked SV_UnitAlive for every ship, wave, troop and deck flight
-- in one tick, ~140 ms a second in the Spaceport round at 5.3 ms a call) aliveOf: the kept answer (sv_spawn.lua ALIVE),
-- at most maxAge (1 s) old and asked again in turn over the ticks; aliveNow: asked now (a check before a spawn or a
-- removal, once)
local function counted(n)                         -- (0 for a unit off the list, nil for an error: not counted)
    if n == -7 then return 0 end
    return n >= 0 and n or nil
end
local function aliveOf(unit, now, maxAge) return counted(ALIVE.ask(unit, now, maxAge)) end
local function aliveNow(unit) return counted(ALIVE.fresh(unit)) end
local HULL_AGE_S = 3                              -- (a ship whose hull is watched: its unit's count only for its turrets)
local function spawn(unit)
    spawningUnit = unit
    local r = SV_Spawn(unit)
    spawningUnit = nil
    ALIVE.spawned(unit, r)                        -- ((0.73.80) its count kept: the looks read it)
    return r
end
local function said(r) return r > 0 and (r .. " up") or ("not spawned (" .. ((SV_ERR and SV_ERR[r]) or tostring(r)) .. ")") end
local function mmss(sec) sec = math.max(0, math.floor(sec + 0.5)); return string.format("%d:%02d", sec // 60, sec % 60) end

-- The fleet in the build's order (tools/survival_events.py sp_fleet): the Ford, each group's Wasp, Aegis pair and
-- boat pair, then the Ford's ring of Aegis.
function SPORT.fleet()
    local out = { { kind = "ford", unit = FORD, group = "Ford" } }
    for i, g in ipairs(GROUPS) do
        out[#out + 1] = { kind = "wasp", unit = "SV_Unit_SpWasp" .. g, group = g }
        for k = 1, 2 do
            local a = 2 * (i - 1) + k
            out[#out + 1] = { kind = "aegis", unit = "SV_Unit_SpAegis" .. AEGIS:sub(a, a), group = g }
        end
        for k = 1, 2 do
            local b = 2 * (i - 1) + k
            out[#out + 1] = { kind = "boat", unit = "SV_Unit_SpBoat" .. BOATS:sub(b, b), group = g }
        end
    end
    for a = 9, #AEGIS do out[#out + 1] = { kind = "aegis", unit = "SV_Unit_SpAegis" .. AEGIS:sub(a, a), group = "Ford" } end
    return out
end
SPORT.GROUPS, SPORT.WAVES, SPORT.CRAFT, SPORT.GARRISON = GROUPS, WAVES, CRAFT, GARRISON
-- The turrets' own DT_NPC rows (tools/survival_events.py SP_TURRETS; the user, 2026-10-31: "up the Activation Range and
-- Targetting Range and Lifetime of ALL Ships currently at the Spaceport"): sv_allies.lua ALLY.setup puts them into
-- DT_NPC at the main menu on fire control of their own (<FCS>_SVA_Fleet, CFG.specials.spaceport.fcs) and says whether
-- they're in (ALLY.fleetReady): without them the fleet's turrets would have no rows, so no Spaceport Assault.
SPORT.FLEET_ROWS = { "SV_Fleet_Mk15Aegis", "SV_Fleet_Mk41Aegis", "SV_Fleet_Mk45Aegis", "SV_Fleet_ArtAegis",
                     "SV_Fleet_Mk15FordLB", "SV_Fleet_Mk15FordRF", "SV_Fleet_Mk15FordLF", "SV_Fleet_Mk15FordRB",
                     "SV_Fleet_SamBoat",
                     -- (the armed hulls, 0.73.45: a ship's parts spawn on the rows its hull's row names, ChildNPCId)
                     "SV_Fleet_AegisHull", "SV_Fleet_BoatHull", "SV_Fleet_FordHull" }

-- The Ford's hull as SV_Spawn makes it (spawningUnit is its unit then), for its deck's launches; checked before each
-- read and dropped once it's gone.
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    if spawningUnit == FORD and not (SPORT.fordActor and liveAddr(SPORT.fordActor)) then SPORT.fordActor = o end
end)
-- The fleet's turrets as SV_Spawn makes them (the user's loggers of 2026-10-31: sv_weaponlog.lua's fleet watch): every
-- object of a ship unit, kept by address once its class reads as a turret's (a mount: mk15 / mk41 / mk45 / the artillery /
-- a SAM launcher); its object checked valid before each read, dropped once it's gone.
SPORT.turrets, SPORT.newParts = {}, {}
-- (0.73.77) every object of each fleet ship as SV_Spawn makes it, the hull and its turrets (a co-op joiner's copies too,
-- unused there): SPORT.shipObjs[unit] = { at = <clock>, obj, obj, ... }, a new list for a new spawn of the unit;
-- shipsTick finds each ship's hull in it and finishes its turrets off when the hull goes (I1: S1, S2, S5). Each object
-- checked live before it's read.
SPORT.shipObjs = {}
local SHIP = {}                                     -- (each fleet unit: { kind, unit, group })
for _, sh in ipairs(SPORT.fleet()) do SHIP[sh.unit] = sh end
local TURRET_CLASS = { "mk15", "mk41", "mk45", "artillery", "_sam", "aagun" }
local function classOf(o) return ((nameOf(o):match("([%w_]+)$") or "?"):gsub("_C_%d+$", ""):gsub("_C$", "")) end
local function turretClass(cls)
    local low = cls:lower()
    for _, k in ipairs(TURRET_CLASS) do if low:find(k, 1, true) then return true end end
    return false
end
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    if not (u and SHIP[u]) then return end
    if not u:find("^SV_Unit_SpWasp") and #SPORT.newParts < 400 then
        SPORT.newParts[#SPORT.newParts + 1] = { obj = o, unit = u, at = os.clock() }
    end
    local l = SPORT.shipObjs[u]
    if not l or os.clock() - (l.at or 0) > 2 then l = { at = os.clock() }; SPORT.shipObjs[u] = l end   -- (a new spawn of it)
    if #l < 12 then l[#l + 1] = o end
end)
function SPORT.partsTick()
    if #SPORT.newParts == 0 then return end
    local keep, now = {}, os.clock()
    for _, np in ipairs(SPORT.newParts) do
        if now - np.at < 0.5 then keep[#keep + 1] = np                    -- (a moment to be named)
        elseif liveAddr(np.obj) then
            local cls = classOf(np.obj)
            if turretClass(cls) then
                local a = addrOf(np.obj)
                if a then SPORT.turrets[a] = { obj = np.obj, unit = np.unit, cls = cls, shots = 0 } end
            end
        end
    end
    SPORT.newParts = keep
end

local function fordAt()
    local c = cfg()
    local a = SPORT.fordActor
    if a and not liveAddr(a) then SPORT.fordActor, a = nil, nil end
    local at
    if a then pcall(function() local v = a:K2_GetActorLocation(); at = { X = v.X, Y = v.Y, Z = v.Z } end) end
    local f = c.ford_cm or {}
    at = at or { X = f[1] or 0, Y = f[2] or 0, Z = 0 }
    return at, math.rad(f[3] or 0)
end

-- A free fighter 2-ship for the deck: not up, not one of the round's own, not a probe or a role flight sitting out.
-- (0.73.77, I8: S13) one held back for the deck when the round was planned (D.spDeck, SPORT.planRound) first, then any
-- free one as before. The flight, and whether it was one held for the deck.
local function deckFlight(size)
    local opts, held = {}, {}
    for _, u in ipairs(CFG.pool) do
        -- ((0.73.80) the Lua tests first, SV_UnitAlive (kept, ALIVE) last: it was asked for the whole pool at each launch)
        if flightSize(u) == size and not (D.up and D.up[u]) and not PROBE_OF[u] and poolIndex(u) ~= nil
            and not ROLE.sitsOut(u) and (D.spDeck and D.spDeck[u] or not (D.taken and D.taken[u]))
            and ALIVE.ask(u, D.now) <= 0 then
            if D.spDeck and D.spDeck[u] then held[#held + 1] = u
            elseif not (D.taken and D.taken[u]) then opts[#opts + 1] = u end
        end
    end
    if #held > 0 then return held[math.random(#held)], true end
    return #opts > 0 and opts[math.random(#opts)] or nil, false
end

-- (0.73.77) a ship still afloat: its hull up (I1: S5; a turret left alone doesn't keep it afloat)
local function afloat(sh) return sh ~= nil and not sh.sunk and (sh.alive or 0) > 0 end

-- The Ford's deck (CFG.specials.spaceport.deck), as the Alicorn's: while it's afloat, a free pool flight of deck.size
-- off its bow (spawnFlight with a pose: ahead_m along its heading, alt_m up), first_s after the fleet appears and every
-- every_s after a launch, flights + flights_per_round a round (at most max_flights), never more than max_up of them up,
-- never while you're down at the airfield (but in co-op while another player flies).
local function deck(now, s)
    local dk = cfg().deck
    local ford = s.ships and s.ships[FORD]
    if not (type(dk) == "table" and dk.enabled and afloat(ford)) then return end
    if not s.deckLeft then
        s.deckLeft = math.max(0, math.min(math.floor(tonumber(dk.max_flights) or 0),
            math.floor(tonumber(dk.flights) or 0) + math.floor(D.round * (tonumber(dk.flights_per_round) or 0))))
        s.deckNext = now + (tonumber(dk.first_s) or 45)
        log(string.format("special: the Ford's deck launches up to %d flights this round", s.deckLeft))
    end
    if s.deckLeft <= 0 or now < s.deckNext then return end
    s.deck = s.deck or {}
    local up = 0
    for u in pairs(s.deck) do if ALIVE.ask(u, now) > 0 then up = up + 1 end end
    if up >= (tonumber(dk.max_up) or 2) then s.deckNext = now + 2; return end
    local flying = playerOnAirfield() and othersFlying()
    if flying == 0 then s.deckNext = now + 1; return end
    local size = math.floor(tonumber(dk.size) or 2)
    local u, heldBack = deckFlight(size)
    if not u then
        if not s.deckNoneSaid then s.deckNoneSaid = true; log(string.format("special: the Ford's deck: no free %d-ship to launch", size)) end
        s.deckNext = now + 5
        return
    end
    local at, yaw = fordAt()
    local ahead = (tonumber(dk.ahead_m) or 600) * 100
    local alt = math.max(DECK_FLOOR_M, tonumber(dk.alt_m) or DECK_FLOOR_M)
    local pose = { x = at.X + math.cos(yaw) * ahead, y = at.Y + math.sin(yaw) * ahead, z = math.max(at.Z, 0) + alt * 100,
                   yaw = math.deg(yaw) % 360, why = "the Ford's deck" }
    local r = spawnFlight(u, nil, pose)
    ALIVE.spawned(u, r)                              -- ((0.73.80) said again: the up count above reads it)
    if r > 0 then
        s.deck[u], s.deckN = true, (s.deckN or 0) + 1
        s.deckLeft = s.deckLeft - 1
        for i = #(D.spare or {}), 1, -1 do if D.spare[i] == u then table.remove(D.spare, i) end end   -- (no spare now)
        s.deckNext = now + (tonumber(dk.every_s) or 50)
        log(string.format("special: the Ford's deck launch %d: %s%s, %d aircraft at %.0f m, %d launches left this round", s.deckN, u,
            heldBack and " (held for the deck)" or "", r, pose.z / 100, s.deckLeft))
    else
        s.deckNext = now + 5
        log(string.format("special: the Ford's deck: %s didn't launch (%s)", u, (SV_ERR and SV_ERR[r]) or tostring(r)))
    end
end

-- (0.73.77, I1) A ship's hull among its objects (SPORT.shipObjs, a second after its spawn): the one object that isn't a
-- turret (a Wasp's only one). sh.hull the object, false when it can't be told (5 looks): that ship is counted by its
-- unit as before 0.73.77 (sunk when every part's down).
local function findHull(unit, sh)
    if sh.hull ~= nil then return end
    local l = SPORT.shipObjs[unit]
    if not l or os.clock() - (l.at or 0) < 1 then return end
    sh.hullLooks = (sh.hullLooks or 0) + 1
    local hulls, n = {}, 0
    for _, o in ipairs(l) do
        if liveAddr(o) then
            n = n + 1
            local cls = classOf(o)
            if #l == 1 or (cls ~= "?" and not turretClass(cls)) then hulls[#hulls + 1] = { o = o, cls = cls } end
        end
    end
    if #hulls == 1 then
        sh.hull, sh.hullCls, sh.parts = hulls[1].o, hulls[1].cls, #l
    elseif sh.hullLooks >= 5 then
        sh.hull = false
        log(string.format("special: spaceport fleet: %s %s's hull not told among its %d objects (%d live, %d not turrets): counted by "
            .. "its unit (sunk when every part's down)", sh.kind, unit, #l, n, #hulls))
    end
end

-- (0.73.77, I1) A sunk ship's turrets still up finished off (no attacker: as sv_ladon.lua's ladonPartsDown, which the
-- game takes): how many, and how many it didn't take.
local function finishParts(unit, sh)
    local n, left = 0, 0
    for _, o in ipairs(SPORT.shipObjs[unit] or {}) do
        if o ~= sh.hull and liveAddr(o) then
            local okH, h = pcall(function() return o.HealthInternal end)
            if okH and type(h) == "number" and h > 0 then
                pcall(function() o:SetMinHealth(0.0) end)
                local ok = pcall(function() o:ModifyHealth(-(h / 10 + 1000), nil, true) end)
                local okA, h1 = pcall(function() return o.HealthInternal end)
                if not ok or (okA and type(h1) == "number" and h1 > 0) then
                    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
                    if valid(gs) then pcall(function() gs:ApplyDamage(o, 100000000.0, nil, nil, nil) end) end
                    okA, h1 = pcall(function() return o.HealthInternal end)
                end
                if okA and type(h1) == "number" and h1 > 0 then left = left + 1 else n = n + 1 end
            end
        end
    end
    return n, left
end

-- Ships lost since the last look: paid, logged, the Wasps' and the Ford's called out.
-- (0.73.77, I1: S1, S2, S5; the economy's C2) Counted by the hull: a ship is sunk once, when its hull is gone or at 0
-- health (or its whole unit's down), paid its price once (it paid price x the parts lost: an Aegis 2,400-12,000, the
-- fleet ~242,000 in round 13), called out once (CARRIER SUNK came twice for one Ford), and its turrets still up are
-- finished off with it; a turret shot off while its hull floats pays pay.turret (the landing craft's rate).
-- ((0.73.80) a ship whose hull is found is watched by its hull, its unit's count (its turrets') asked every HULL_AGE_S;
-- one counted by its unit as before, every second)
local function shipsTick(s, now)
    local c, t = cfg(), CFG.hud.text
    local pay = c.pay or {}
    for unit, sh in pairs(s.ships) do
        if afloat(sh) then
            findHull(unit, sh)
            local a = aliveOf(unit, now, (sh.hull and liveAddr(sh.hull)) and HULL_AGE_S or nil) or sh.alive
            local why = nil
            if a <= 0 then why = "every part down"
            elseif sh.hull then
                if not liveAddr(sh.hull) then why = "its hull gone"
                else
                    local okH, h = pcall(function() return sh.hull.HealthInternal end)
                    if okH and type(h) == "number" and h <= 0 then why = "its hull down" end
                end
            end
            if why then
                sh.sunk = true
                local p = tierPay(pay[sh.kind] or 0)
                addCredits(p, "the spaceport's fleet: " .. sh.kind .. " sunk")
                LB.stat("ground", 1)
                local fin, left = 0, 0
                if a > 0 then fin, left = finishParts(unit, sh) end
                log(string.format("special: spaceport fleet: %s %s sunk (%s; +%d once%s)", sh.kind, unit, why, p,
                    (fin + left > 0) and string.format("; %d of its turrets still up finished off%s", fin,
                        left > 0 and string.format(", %d NOT (still up)", left) or "") or ""))
                if sh.kind == "wasp" then
                    hudCallout(t.sp_wasp_down, t.sp_wasp_down_sub)
                    local okW, errW = pcall(SPORT.tuWasp, now, s, unit)   -- (its Tu-160s at the airfield)
                    if not okW then log("special: the Tu-160s' error " .. tostring(errW)) end
                elseif sh.kind == "ford" then hudCallout(t.sp_ford_down, t.sp_ford_down_sub) end
                sh.alive = 0
            else
                if a < sh.alive then                      -- (a turret shot off, the hull still up)
                    local lost = sh.alive - a
                    local p = tierPay(pay.turret or 0) * lost
                    if p > 0 then addCredits(p, "the spaceport's fleet: a " .. sh.kind .. "'s turret shot off") end
                    LB.stat("ground", lost)
                    log(string.format("special: spaceport fleet: %s %s lost %d turret%s (+%d), its hull still up (%d of its objects left)",
                        sh.kind, unit, lost, lost == 1 and "" or "s", p, a))
                end
                sh.alive = a
            end
        end
    end
    if not s.hullsSaid then                               -- (once: how many ships are counted by their hull)
        local n, found, byUnit, early, unknown = 0, 0, 0, 0, 0
        for _, sh in pairs(s.ships) do
            n = n + 1
            if sh.hull then found = found + 1
            elseif sh.hull == false then byUnit = byUnit + 1
            elseif afloat(sh) then unknown = unknown + 1
            else early = early + 1 end
        end
        if n > 0 and unknown == 0 and #(s.queue or {}) == 0 then
            s.hullsSaid = true
            log(string.format("special: spaceport fleet: %d of its %d ships counted by their hull%s%s", found, n,
                byUnit > 0 and string.format(", %d by their unit (hull not told)", byUnit) or "",
                early > 0 and string.format(", %d sunk before their hull was looked for", early) or ""))
        end
    end
end

-- Ships still afloat.
function SPORT.shipsUp(s)
    local n = 0
    for _, sh in pairs(s and s.ships or {}) do if afloat(sh) then n = n + 1 end end
    return n + #(s and s.queue or {})
end

-- Landing craft on their way in (not landed, not taken off).
function SPORT.craftIn(s)
    local n = 0
    for _, L in pairs(s and s.lanes or {}) do
        for _, wv in pairs(L.waves) do
            if not wv.removed then
                local landed = 0
                for _ in pairs(wv.landed) do landed = landed + 1 end
                n = n + math.max(0, math.min(wv.alive, wv.n - landed))
            end
        end
    end
    return n
end

-- Whether a Spaceport Assault can come: the native spawner and the turrets' rows in.
-- (0.73.77, I3: S4) a fleet still up from before no longer keeps it away (every later Spaceport was refused, and the
-- clean-up in SPORT.spawn sat behind this): SPORT.spawn takes the leftovers off first.
local CLEAR_S = 8                                    -- (s the new fleet waits for leftovers taken off to go)
function SPORT.ready()
    if cfg().enabled == false then
        if not SPORT.offSaid then SPORT.offSaid = true; log("special: no Spaceport Assault: switched off ([specials.spaceport] enabled)") end
        return false
    end
    if not nativeReady() then return false end
    if not (ALLY and ALLY.fleetReady) then
        if not SPORT.rowsSaid then SPORT.rowsSaid = true; log("special: no Spaceport Assault: its turrets' rows aren't in DT_NPC") end
        return false
    end
    return true
end

---------------------------------------------------------------------------------------------------- the Tu-160s
-- (user, 2026-11-04: "in the spaceport assault round, can you please add TU-160's that come from both the North and the
-- south to target the airfield and bomb it", then "spawn everytime a WASP gets destroyed, have 4 bombers each";
-- CFG.specials.spaceport.tu160) Each Wasp sunk in the assault sends a group of `group` Tu-160s (on `aircraft`) at the
-- airfield delay_s later, the groups' sides taking `bearings` in turn (north, south, ...; the first by chance). A group is
-- the heavy bomber flights (CFG.airfield.bombers.heavy_units: built with the large-aircraft behaviour and a route in from
-- every compass sector, tools/survival_events.py HEAVY_*) whose sizes add up to `group` (the build has a 2-ship and a
-- 4-ship: a group of 4 is the 4-ship), sent through the bombers' own spawn (spawnBomberFrom, sv_spawn.lua): their route
-- over the runway, the bomb runs, the minimap pings, a heavy's pay, the round held until they're down (D.up), the co-op
-- copies. A flight can't spawn again while its last one is up (hard rule 16), so a group whose flights are still up from
-- the last group waits for them (and holds the round meanwhile: their flights are in it anyway). None after a capture
-- (a waiting group dropped) or in the retake; the host's (or solo): D.special is the host's alone.
-- s.tu = { units = { unit -> bearing } (every flight sent this assault: the row, the capture's withdrawal, the waves'
-- count), n (aircraft sent), queue = { { at, why, k (its group number) } }, k (groups asked for), side, said = { ... } }
-- the heavy flights and their sizes
local function tuFlights()
    local out = {}
    for _, u in ipairs(CFG.airfield.bombers.heavy_units or {}) do
        if BOMBER_UNIT and BOMBER_UNIT[u] then out[#out + 1] = { unit = u, size = math.max(0, tonumber(flightSize(u)) or 0) } end
    end
    return out
end
-- the ways to make a group of n from the heavy flights, fewest flights first: those adding up to n, else the biggest
-- under it (none: the smallest flight alone)
local function tuOptions(fl, n)
    local exact, under, best = {}, {}, 0
    for mask = 1, (1 << #fl) - 1 do
        local set, sum = {}, 0
        for i = 1, #fl do if mask & (1 << (i - 1)) ~= 0 then set[#set + 1] = fl[i]; sum = sum + fl[i].size end end
        if sum == n then exact[#exact + 1] = set
        elseif sum < n and sum > 0 then
            if sum > best then best, under = sum, { set } elseif sum == best then under[#under + 1] = set end
        end
    end
    local opts = #exact > 0 and exact or under
    if #opts == 0 and #fl > 0 then
        local small = fl[1]
        for _, f in ipairs(fl) do if f.size < small.size then small = f end end
        opts = { { small } }
    end
    table.sort(opts, function(x, y) return #x < #y end)
    return opts
end
-- the plan (SPORT.spawn), or nil: off, the airfield off, no heavy flight, no bearing
function SPORT.tuPlan(now)
    local c = cfg().tu160
    if not (type(c) == "table" and c.enabled ~= false and CFG.airfield.enabled) then return nil end
    local fl = tuFlights()
    local br = {}
    for _, b in ipairs(type(c.bearings) == "table" and c.bearings or {}) do
        b = tonumber(b)
        if b then br[#br + 1] = b % 360 end
    end
    if #fl == 0 or #br == 0 then
        log(string.format("special: no Tu-160s this assault (%s)", #fl == 0 and "no heavy bomber flight" or "no bearings"))
        return nil
    end
    local n = math.max(1, math.floor(tonumber(c.group) or 4))
    local opt = tuOptions(fl, n)[1]
    local names, sum = {}, 0
    for _, f in ipairs(opt or {}) do names[#names + 1] = string.format("%s (%d)", f.unit, f.size); sum = sum + f.size end
    local tu = { units = {}, n = 0, queue = {}, k = 0, side = math.random(#br), bearings = br, group = n, said = {} }
    log(string.format("special: the Tu-160s: a group of %d for each Wasp sunk, %d s after it, from the %s in turn (a group: %s%s)",
        n, math.floor(math.max(0, tonumber(c.delay_s) or 6)), (function()
            local t = {}
            for i = 1, #br do t[#t + 1] = compassName(br[(tu.side + i - 2) % #br + 1]) end
            return table.concat(t, ", then ")
        end)(), table.concat(names, " + "), sum ~= n and string.format("; the heavy flights can't make %d: %d", n, sum) or ""))
    return tu
end
-- the Tu-160s up now (this game's planes of the flights sent this assault, not down)
function SPORT.tuUp(s)
    local tu = s and s.tu
    if not (tu and tu.n and tu.n > 0) then return 0 end
    local n = 0
    for _, p in ipairs(planes or {}) do
        if not p.down and p.unit and tu.units[p.unit] and liveObj(p.obj) then n = n + 1 end
    end
    return n
end
-- a Wasp sunk (shipsTick, the assault only): its group asked for, delay_s on
function SPORT.tuWasp(now, s, unit)
    local tu = s and s.tu
    if not tu or s.kind ~= "spaceport" or s.state ~= "assault" then return end
    if s.captured then log("special: " .. tostring(unit) .. " sunk after the capture: no Tu-160s"); return end
    tu.k = tu.k + 1
    local c = cfg().tu160
    tu.queue[#tu.queue + 1] = { at = now + math.max(0, tonumber(c.delay_s) or 6), why = tostring(unit) .. " sunk", k = tu.k }
    log(string.format("special: %s sunk: Tu-160 group %d asked for (%d waiting)", tostring(unit), tu.k, #tu.queue))
end
-- (from SPORT.tick) the first group waiting, once it's due: its flights sent if they're free, else it waits for them
function SPORT.tuTick(now, s)
    local tu = s.tu
    if not tu or #tu.queue == 0 then return end
    local g = tu.queue[1]
    if now < g.at then return end
    if s.captured then
        log(string.format("special: the spaceport captured: %d Tu-160 group%s waiting dropped", #tu.queue, #tu.queue == 1 and "" or "s"))
        tu.queue = {}
        return
    end
    -- ((review of 27097b9, finding 1) solo down at the airfield (nobody else flying), as the deck and the round's spawns: a
    -- group due, even one that waited for its flights (holdClocks moves its time on with the clock: still due), waits
    -- until you're up, then comes at once; before, one whose last group the airfield's guns finished off came while you
    -- were in the STORE)
    if playerOnAirfield() and othersFlying() == 0 then return end
    local c, t = cfg().tu160, CFG.hud.text
    local fl = tuFlights()
    local opts = tuOptions(fl, tu.group)
    local free, busyOf = nil, nil
    for _, set in ipairs(opts) do
        local ok = true
        for _, f in ipairs(set) do
            if (tonumber(ALIVE.ask(f.unit, now)) or 0) > 0 then ok = false; busyOf = busyOf or set end
        end
        if ok then free = set; break end
    end
    if not free then
        -- (its flights still up: in this round (D.up), it waits for them, holding the round; up but not this round's
        -- (a stale one), the group is dropped: it could hold the round for ever)
        local inRound = false
        for _, f in ipairs(busyOf or {}) do if D.up and D.up[f.unit] then inRound = true end end
        if inRound or #opts == 0 then
            if not g.waitSaid then
                g.waitSaid = true
                log(string.format("special: Tu-160 group %d (%s) waits: its flights are still up from the last group", g.k, g.why))
            end
            if #opts > 0 then return end
        end
        table.remove(tu.queue, 1)
        tu.said[#tu.said + 1] = string.format("group %d: not sent (%s)", g.k, #opts == 0 and "no heavy flight" or "its flights up, not this round's")
        log(string.format("special: Tu-160 group %d (%s) dropped: %s", g.k, g.why, #opts == 0 and "no heavy bomber flight"
            or "its flights read up but aren't this round's"))
        return
    end
    table.remove(tu.queue, 1)
    local bearing = tu.bearings[(tu.side - 1) % #tu.bearings + 1]
    tu.side = tu.side + 1
    local parts, sent = {}, 0
    for _, f in ipairs(free) do
        local okS, res = pcall(spawnBomberFrom, f.unit, { ac = c.aircraft, bearing = bearing, spread = c.spread_deg,
                                                          distance_km = c.distance_km })
        local r = okS and tonumber(res) or nil           -- ((review of 7bcd4c4) res kept: an error's text, logged)
        if r and r > 0 then
            -- ((review of 27097b9, finding 2) SV_Spawn answers the unit's ChildAIGameObjects: a Tu-160 brings its wing
            -- objects, 12 for the 4-ship; the aircraft are the flight's size)
            local ac = (f.size and f.size > 0) and f.size or r
            sent = sent + ac
            tu.units[f.unit] = bearing
            parts[#parts + 1] = string.format("%s: %d (%d objects)", f.unit, ac, r)
        else
            parts[#parts + 1] = string.format("%s: %s", f.unit, okS and ("not spawned (" .. ((SV_ERR and r and SV_ERR[r]) or tostring(res)) .. ")")
                or ("error " .. tostring(res)))
        end
    end
    tu.n = tu.n + sent
    tu.said[#tu.said + 1] = string.format("group %d: %d from the %s", g.k, sent, compassName(bearing))
    log(string.format("special: Tu-160 group %d (%s): %d from the %s (bearing %d; %s)", g.k, g.why, sent, compassName(bearing),
        math.floor(bearing), table.concat(parts, "; ")))
    if sent > 0 then
        hudCallout(t.sp_tu160, string.format(t.sp_tu160_sub, compassName(bearing)))
        if TELL then pcall(TELL.say, "raid", TELL.ALL) end      -- (its radio call, every player: P3's tells)
    end
end

function SPORT.spawn(now)
    local c, t = cfg(), CFG.hud.text
    if not nativeReady() then return false end
    local left = {}                                  -- ((0.73.77) leftovers: taken off, the new fleet waits for them)
    for _, sh in ipairs(SPORT.fleet()) do
        if (aliveNow(sh.unit) or 0) > 0 then left[#left + 1] = sh.unit:sub(#"SV_Unit_Sp" + 1) end
    end
    local s = D.special
    s.clearUntil = nil
    if #left > 0 then
        s.clearUntil = now + CLEAR_S
        log(string.format("special: %d ships of the spaceport's fleet were still up from before (%s): taken off (RE_SV_SpFleetRemove %s); "
            .. "the new fleet waits up to %d s for them", #left, table.concat(left, ", "), fleetFire(), CLEAR_S))
    end
    s.state, s.at, s.ships, s.queue, s.lanes, s.troops, s.capture = "assault", now, {}, {}, {}, {}, 0
    -- (the wave report, the user's loggers of 2026-10-31: each wave's line as it's done, the round's at its end)
    s.stat, s.capLog = { waves = 0, craft = 0, shot = 0, landed = 0, ashore = 0, inside = 0, stuck = 0 }, {}
    local n, want = {}, c.ships or {}
    for _, sh in ipairs(SPORT.fleet()) do
        n[sh.kind] = (n[sh.kind] or 0) + 1
        if n[sh.kind] <= (tonumber(want[sh.kind]) or 0) then s.queue[#s.queue + 1] = sh end
    end
    if #s.queue == 0 then log("special: the spaceport's fleet has no ships (CFG.specials.spaceport.ships)"); return false end
    for _, g in ipairs(GROUPS) do s.lanes[g] = { next = now + (tonumber(c.first_wave_s) or 20), waves = {} } end
    SPORT.fordActor = nil
    local okT, tu = pcall(SPORT.tuPlan, now)                   -- (the Tu-160s at the airfield: SPORT.tuTick)
    s.tu = okT and tu or nil
    if not okT then log("special: the Tu-160s' plan error " .. tostring(tu)) end
    hudCallout(t.sp_go, t.sp_go_sub)
    log(string.format("special: round %d, the Spaceport Assault: %d ships coming in west of the spaceport", D.round, #s.queue))
    return true
end

-- The round's fighters fall back with the capture (the user's test of 2026-10-31: "after the spaceport was captured,
-- the next round didn't start": six fighters were still up, and a round ends only with its aircraft down): each pool
-- flight up is despawned (RE_SV_FlightOff_NN, Mission 22's own despawn) and off the round's list (D.up: a despawned
-- unit can still read alive), its planes marked down (no pay), the round's queue and later waves dropped, no more deck
-- launches. The round then ends as any does, and the retake comes after its break.
-- ((review of 7bcd4c4) The Tu-160s already sent (SPORT.tuTick: bomber flights, no pool index and no despawn event of their
-- own) fall back too: off the round's list (D.up), D.heavy and D.heavyPath, their planes marked down and withdrawn (bombTick
-- bombs with any heavy plane not down; the sweep neither pays nor counts them), nobody's on the host (COOP.takenOff: a
-- later shot or the recycle pays no player) and on every joiner (COOP.withdrawn: "wd", their copies marked as here; review
-- of 27097b9), recycled in the break as the fighters (D.spWithdrawn: SPORT.planRound). They
-- fly on until then, harmless. Before, they held the round (and bombed on) until all were shot down. Not yet sent:
-- tuTick says so (s.captured).)
local function withdraw(s)
    local gone, n = {}, 0
    local tu, tuGone, nTu = s.tu, {}, 0
    local tuUnits = (tu and (tu.n or 0) > 0 and tu.units) or {}
    D.queue, D.spare = {}, {}
    if D.waves then D.wave = #D.waves end
    if D.state == "spawning" or D.state == "wave" then D.state = "fighting" end
    for u in pairs(D.up or {}) do
        local k = poolIndex(u)
        if k then
            n = n + math.max(0, ALIVE.ask(u))
            fire(string.format("RE_SV_FlightOff_%02d", k))
            gone[u] = true
            gone[#gone + 1] = u
        elseif tuUnits[u] then
            for _, p in ipairs(planes or {}) do                -- (aircraft: a Tu-160's spawn counts its wings too)
                if p.unit == u and not p.down then nTu = nTu + 1 end
            end
            if COOP and COOP.takenOff then pcall(COOP.takenOff, u) end
            if COOP and COOP.withdrawn then pcall(COOP.withdrawn, u) end   -- ((review of 27097b9, finding 3) the joiners' copies off, unpaid)
            if D.heavy then D.heavy[u] = nil end
            if D.heavyPath then D.heavyPath[u] = nil end
            gone[u] = true
            tuGone[#tuGone + 1] = u
        end
    end
    for _, u in ipairs(tuGone) do D.up[u] = nil end
    for _, u in ipairs(gone) do D.up[u] = nil end
    if #tuGone > 0 then tu.why = "withdrawn at the capture" end
    if tu and #tu.queue > 0 then                          -- (groups still to come: none now)
        log(string.format("special: the spaceport captured: %d Tu-160 group%s waiting dropped", #tu.queue, #tu.queue == 1 and "" or "s"))
        tu.queue = {}
    end
    -- ((0.73.77, I4: S6) a despawned flight still reads up, so the native recycle refused it every round after ("still
    -- up") and it stayed first in line: SPORT.planRound recycles it when the next round is planned, or keeps it out)
    D.spWithdrawn = D.spWithdrawn or {}
    for _, u in ipairs(gone) do D.spWithdrawn[u] = true end
    for _, u in ipairs(tuGone) do D.spWithdrawn[u] = true end
    for _, p in ipairs(planes or {}) do
        if p.unit and gone[p.unit] and not p.down then p.down, p.withdrawn = true, true end
    end
    s.deckLeft = 0
    table.sort(tuGone)
    log(string.format("special: the round's fighters fall back with the capture: %d flights (%d aircraft) taken off%s%s", #gone, n,
        #gone > 0 and (": " .. table.concat(gone, ", ")) or "",
        #tuGone > 0 and string.format("; the Tu-160s too: %s (%d aircraft, no despawn event: recycled at the next round's plan)",
            table.concat(tuGone, ", "), nTu) or ""))
end

-- A lane's next free wave: one not out and not still up from before.
local function freeWave(g, L)
    for _, w in ipairs(WAVES) do
        if not L.waves[w] and (aliveNow("SV_Unit_SpLcac" .. g .. w) or 1) <= 0 then return w end
    end
end

-- (0.73.77, I6: S10) Down at the airfield with nobody else flying (solo, or every other co-op player down too), the
-- Spaceport's own clocks wait, as the shuttle's countdown does (landing early could lose the spaceport or a rocket):
-- the Wasps' next waves and the rockets' launches move on by the time held. What's already out (craft, troops ashore, a
-- rocket climbing) goes on: the game's. Once a second (the special's looks); whether they're held now.
local function holdClocks(now, s)
    local last = s.clockAt or now
    s.clockAt = now
    local held = playerOnAirfield() and othersFlying() == 0
    if held then
        local dt = math.max(0, now - last)
        for _, L in pairs(s.lanes or {}) do if L.next then L.next = L.next + dt end end
        local rk = s.rk
        if rk and rk.launch then
            for k, at in pairs(rk.launch) do if not rk.launched[k] then rk.launch[k] = at + dt end end
        end
        for _, g in ipairs(s.tu and s.tu.queue or {}) do g.at = g.at + dt end   -- (the Tu-160 groups' too)
        s.heldS = (s.heldS or 0) + dt
    end
    if held ~= (s.clocksHeld or false) then
        s.clocksHeld = held
        log(held and "special: the spaceport's clocks wait while you're down at the airfield (the next waves, the rockets' launches, the Tu-160s)"
            or string.format("special: the spaceport's clocks run again (%.0f s held this round)", s.heldS or 0))
    end
    return held
end

function SPORT.tick(now, s)
    if s.state ~= "assault" then return end
    if levelGoing() then return end                  -- ((0.73.77) no pay or spawn while the level goes away)
    ALIVE.tick(now)                                  -- ((0.73.80) roundsTick's own already: the same tick, no second budget)
    local c, t = cfg(), CFG.hud.text
    if #s.queue > 0 and now >= (s.spawnAt or 0) then          -- the fleet, a few ships at a time
        s.spawnAt = now + 0.5
        for _ = 1, math.max(1, math.floor(tonumber(c.spawn_per_tick) or 3)) do
            local sh = s.queue[1]
            if not sh then break end
            -- ((0.73.77, I3) a leftover from before still going after its removal: a moment more, then counted as it is)
            local old = s.clearUntil and (aliveOf(sh.unit, now) or 0) or 0
            if old > 0 and now < s.clearUntil then break end
            table.remove(s.queue, 1)
            if old > 0 then
                s.ships[sh.unit] = { kind = sh.kind, group = sh.group, alive = old, old = true }
                log(string.format("special: spaceport fleet: %s %s still up from before %d s after its removal: counted in this fleet "
                    .. "as it is (%d objects)", sh.kind, sh.unit, CLEAR_S, old))
            else
                local r = spawn(sh.unit)
                if r > 0 then s.ships[sh.unit] = { kind = sh.kind, group = sh.group, alive = r } end
                log(string.format("special: spaceport fleet: %s %s: %s", sh.kind, sh.unit, said(r)))
            end
        end
    end
    if now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    holdClocks(now, s)
    shipsTick(s, now)
    local f = svFlags() or {}
    for _, g in ipairs(GROUPS) do
        local L = s.lanes[g]
        local wasp = s.ships["SV_Unit_SpWasp" .. g]
        if afloat(wasp) and not s.captured and now >= L.next then   -- its Wasp's next wave
            local w = freeWave(g, L)
            if w then
                local unit = "SV_Unit_SpLcac" .. g .. w
                local r = spawn(unit)
                if r > 0 then
                    L.waves[w] = { unit = unit, n = r, alive = r, landed = {}, at = now, shot = 0, ashore = 0, nLanded = 0 }
                    s.stat.waves, s.stat.craft = s.stat.waves + 1, s.stat.craft + r
                    L.sent, L.next = (L.sent or 0) + 1, now + (tonumber(c.wave_every_s) or 60)
                    if not s.wavesSaid then s.wavesSaid = true; hudCallout(t.sp_landing, t.sp_landing_sub) end
                else
                    L.next = now + 5
                end
                log(string.format("special: the Wasp of group %s sends landing craft %s: %s", g, unit, said(r)))
            else
                L.next = now + 5
            end
        end
        for w, wv in pairs(L.waves) do
            local alive = wv.removed and 0 or (aliveOf(wv.unit, now) or wv.alive)
            if alive < wv.alive and not wv.removed then
                wv.shot, s.stat.shot = (wv.shot or 0) + (wv.alive - alive), s.stat.shot + (wv.alive - alive)
                -- ((0.73.77, I2: S3) "sunk", not "down (": sv_coop.lua's addCredits doesn't send a pay whose reason has
                -- " down (" (a plane kill, each game's own), so the joiners were never paid for a craft)
                addCredits(tierPay(c.pay and c.pay.craft or 0) * (wv.alive - alive), "landing craft sunk (" .. wv.unit .. ")")
                LB.stat("ground", wv.alive - alive)
                log(string.format("special: %s: %d landing craft left", wv.unit, alive))
            end
            wv.alive = alive
            for _, k in ipairs(CRAFT) do
                -- (a flag still 1 from this wave's last run is reset by its appearance: not read in the first 5 s)
                local key = g .. w .. k
                if now - wv.at >= 5 and (f["SV_SpLand" .. key] or 0) >= 1 and not wv.landed[k] then
                    wv.landed[k] = now
                    wv.firstLanded = wv.firstLanded or now
                    wv.nLanded, s.stat.landed = (wv.nLanded or 0) + 1, s.stat.landed + 1
                    local tu = "SV_Unit_SpTroops" .. key
                    local r = -100
                    if not s.captured and (aliveNow(tu) or 1) <= 0 then r = spawn(tu) end
                    log(string.format("special: %s craft %s on the beach; troops %s: %s", wv.unit, k, tu,
                        r == -100 and (s.captured and "none (captured)" or "still up from before") or said(r)))
                    if r > 0 then
                        wv.ashore, s.stat.ashore = (wv.ashore or 0) + 1, s.stat.ashore + 1
                        s.troops[#s.troops + 1] = { unit = tu, key = key, at = now }
                        if not s.ashoreSaid then s.ashoreSaid = true; hudCallout(t.sp_ashore, t.sp_ashore_sub) end
                    end
                end
            end
            if not wv.removed and wv.firstLanded and now - wv.firstLanded >= (tonumber(c.remove_after_s) or 60) then
                wv.removed = true                         -- (no pay for these: they got away)
                log(string.format("special: %s are away; taken off (%s)", wv.unit, offFire(wv.unit, "RE_SV_SpLcacRemove" .. g .. w)))
            end
            if wv.removed or alive <= 0 then                     -- (free again once it's off the list: freeWave)
                log(string.format("special: wave %s: %d craft, %d shot down, %d landed, %d troop vehicles ashore (%s after it left)",
                    wv.unit, wv.n, wv.shot or 0, wv.nLanded or 0, wv.ashore or 0, mmss(now - wv.at)))
                L.waves[w] = nil
            end
        end
    end
    for i = #s.troops, 1, -1 do                                -- troop vehicles at their spot, and gone in
        local tr = s.troops[i]
        if not tr.reached and now - tr.at >= 2 and (f["SV_SpAt" .. tr.key] or 0) >= 1 then
            tr.reached = now
            s.inside = (s.inside or 0) + 1
            if s.stat then s.stat.inside = s.stat.inside + 1 end
            if not s.captured then
                -- ((0.73.77, I7: S11) a whole share: a fraction from survival.ini threw at every %d of it, each tick)
                local per = math.max(1, math.min(100, math.floor((tonumber(c.capture_per_troop) or 5) + 0.5)))
                s.capture = math.min(100, math.floor(s.capture + per))
                if s.capLog then s.capLog[#s.capLog + 1] = string.format("%d%% at +%s", s.capture, mmss(now - s.at)) end
                RUN.dirty = true
                hudCallout(t.sp_troops_in, string.format(t.sp_troops_in_sub, s.capture))
                log(string.format("special: troops %s reached the spaceport; %d%% captured", tr.unit, s.capture))
            end
        end
        local why = (tr.reached and now - tr.reached >= (tonumber(c.troop_stay_s) or 30) and "gone in")
            or (not tr.reached and now - tr.at >= (tonumber(c.troop_timeout_s) or 420) and "never got there")
        if why then
            if not tr.reached and s.stat then s.stat.stuck = s.stat.stuck + 1 end
            log(string.format("special: troops %s %s; taken off (%s)", tr.unit, why, offFire(tr.unit, "RE_SV_SpTroopsRemove" .. tr.key)))
            table.remove(s.troops, i)
        end
    end
    if s.capture >= 100 and not s.captured then
        s.captured = true
        RUN.sport = { retakeRound = D.round + 1, troops = s.inside or 0, lostRound = D.round, ships = {} }
        LB.stat("captured", 1)
        hudCallout(t.sp_captured, t.sp_captured_sub)
        log(string.format("special: round %d, the spaceport is captured (%d troop vehicles in); the retake is round %d",
            D.round, s.inside or 0, D.round + 1))
        for g, L in pairs(s.lanes) do                         -- (no more landings: the craft still out go back)
            for w, wv in pairs(L.waves) do
                if not wv.removed then wv.removed = true; log(string.format("special: %s recalled (%s)", wv.unit, offFire(wv.unit, "RE_SV_SpLcacRemove" .. g .. w))) end
            end
        end
        local okW, errW = pcall(withdraw, s)
        if not okW then log("special: the fighters' withdrawal error " .. tostring(errW)) end
    end
    local okD, errD = pcall(deck, now, s)
    if not okD and tostring(errD) ~= s.deckErr then s.deckErr = tostring(errD); log("special: the Ford's deck error " .. s.deckErr) end
    if s.tu and #s.tu.queue > 0 then
        local okT, errT = pcall(SPORT.tuTick, now, s)
        if not okT then table.remove(s.tu.queue, 1); log("special: the Tu-160s' error " .. tostring(errT)) end
    end
end

-- The round can't end while a ship is afloat, a craft is coming in or troops are on their way, short of the capture
-- (captured, the ships carry over into the retake).
function SPORT.busy(s)
    if s.state ~= "assault" or s.captured then return false end
    if s.tu and #s.tu.queue > 0 then return true end         -- (a Tu-160 group still to come: its flights hold the round once up)
    if SPORT.shipsUp(s) > 0 or SPORT.craftIn(s) > 0 then return true end
    for _, tr in ipairs(s.troops) do if not tr.reached then return true end end
    return false
end

function SPORT.roundOver(now, s)
    local c, t = cfg(), CFG.hud.text
    for g, L in pairs(s.lanes or {}) do
        for w, wv in pairs(L.waves) do
            if not wv.removed then wv.removed = true; log(string.format("special: %s taken off at the round's end (%s)", wv.unit, offFire(wv.unit, "RE_SV_SpLcacRemove" .. g .. w))) end
        end
    end
    for _, tr in ipairs(s.troops or {}) do offFire(tr.unit, "RE_SV_SpTroopsRemove" .. tr.key) end
    s.troops, s.state = {}, "done"
    if s.tu then
        local tu = s.tu
        log(string.format("special: the Tu-160s this assault: %d group%s asked for (a Wasp sunk each), %d aircraft sent%s%s; %d "
            .. "still up at the round's end%s", tu.k, tu.k == 1 and "" or "s", tu.n, #tu.said > 0 and (" (" .. table.concat(tu.said, ", ") .. ")") or "",
            tu.why and (", " .. tu.why) or "", SPORT.tuUp(s), #tu.queue > 0 and string.format("; %d never came", #tu.queue) or ""))
        tu.queue = {}
    end
    local st = s.stat
    if st then
        local cl = s.capLog or {}
        log(string.format("special: the Spaceport Assault's waves (%s): %d sent, %d craft: %d shot down, %d landed; troop vehicles: "
            .. "%d ashore, %d got in, %d stuck; the capture: %s", mmss(now - (s.at or now)), st.waves, st.craft, st.shot,
            st.landed, st.ashore, st.inside, st.stuck,
            #cl > 0 and table.concat(cl, ", ", math.max(1, #cl - 19)) or "never started"))
    end
    if s.captured then                                 -- the ships still afloat carry over into the retake
        local left = 0
        for unit, sh in pairs(s.ships) do
            if afloat(sh) then RUN.sport.ships[unit] = { kind = sh.kind, group = sh.group }; left = left + 1 end
        end
        LB.special("spaceport", false, now - (s.at or now))
        -- ((0.73.77, I3: S4) no retake can follow (switched off): the fleet is taken off now, never left stranded)
        if c.enabled == false or (c.retake and c.retake.enabled == false) then
            hudCallout(t.sp_lost, nil)
            log(string.format("special: round %d, the spaceport was lost; no retake follows ([specials.spaceport.retake] enabled): "
                .. "the %d ships still afloat taken off (RE_SV_SpFleetRemove %s)", D.round, left, fleetFire()))
            RUN.sport = nil
        else
            hudCallout(t.sp_lost, string.format(t.sp_lost_sub, left))
            log(string.format("special: round %d, the spaceport was lost; %d ships carry over into the retake", D.round, left))
        end
    else
        local pay = math.floor((c.reward or 0) + (c.reward_per_round or 0) * D.round)
        addCredits(pay, "spaceport held")
        LB.special("spaceport", true, now - (s.at or now))
        hudCallout(t.sp_held, string.format(t.sp_held_sub, specialPay(pay)))   -- ((0.73.78) C3: each player's share)
        log(string.format("special: round %d, the spaceport held (%d%% captured)", D.round, s.capture or 0))
        RUN.sport = nil
        SPORT.tidyFleet("the spaceport held")
    end
end

-- (0.73.77, I1 / I3) At a Spaceport's end with every ship sunk: any part of the fleet still up (a turret the finish
-- didn't take, a ship counted by its unit) taken off with RE_SV_SpFleetRemove, logged; nothing fired when none is.
function SPORT.tidyFleet(why)
    local up = {}
    for _, sh in ipairs(SPORT.fleet()) do
        if (aliveNow(sh.unit) or 0) > 0 then up[#up + 1] = sh.unit:sub(#"SV_Unit_Sp" + 1) end
    end
    if #up > 0 then
        log(string.format("special: %s: %d of the fleet's units still had parts up (%s): taken off (RE_SV_SpFleetRemove %s)", why,
            #up, table.concat(up, ", "), fleetFire()))
    end
    return #up
end

-- The NEXT row while it's on.
function SPORT.row(s, t)
    if s.state == "assault" then
        local n = SPORT.tuUp(s)
        return string.format(t.sp_row, SPORT.shipsUp(s), SPORT.craftIn(s), s.capture or 0)
            .. ((n > 0 and t.sp_row_tu160) and string.format(t.sp_row_tu160, n) or "")
    elseif s.state == "retake" then
        local g = 0
        for _, x in pairs(s.garrison or {}) do g = g + math.max(0, x.alive) end
        return string.format(t.sp_retake_row, g, SPORT.shipsUp(s))
    end
end

---------------------------------------------------------------------------------------------------- the retake
---------------------------------------------------------------------------------------------------- the retake's rockets
-- Mission 19's two rockets on the pads (SV_Unit_SpRockets, tools/survival_events.py SP_ROCKET_*; user, 2026-10-31: "can
-- you please build the rockets this time?"). Each launches rockets.launch_a_s / launch_b_s into the retake
-- (RE_SV_SpRocketLaunch<A|B>: shown, not invincible, TGT, its climb to 20.2 km at Mission 19's 280 km/h), boost_s on
-- Mission 19's 1000 km/h (RE_SV_SpRocketBoost<A|B>: Mission 19 boosts at a path point, which never fires for Survival,
-- hard rule 1). Its climb's end sets SV_SpRocketEsc<A|B>: escaped, escape_penalty zollars and no retake reward. Mission
-- 19's split: the destroy spawner off at the start (RE_SV_SpRocketSplitOff; every debris piece held at 1 HP), on once one
-- rocket is left (RE_SV_SpRocketSplitOn): the last one killed breaks up, its debris stages (SV_Unit_SpDebriA-C)
-- targetable in turn (RE_SV_SpDebriTgt1-3, debris_tgt_s after the kill, debris_next_s after each stage), debris_pay a
-- piece, all taken off debris_timeout_s after the last change (debris on the ground counts as destroyed). The round
-- can't end while a rocket or its debris is up.
-- (0.73.77, I5: S7, S8) Every rocket ends: one neither down nor escaped timeout_s after its launch is taken off with no
-- penalty, and an escape counts only from escape_min_m up (a climb's path that finishes early, as the boost's re-issue
-- of it may, hides the rocket: taken off, no penalty). Each rocket's height and kill from its own object when both are
-- found (by their pads), else by the unit's count as before. The debris only once the split is seen (its first stage
-- up from under the sea, or the split on before the last kill), split_wait_s at most: both rockets down at once never
-- split, and their debris stayed 500 m down, "targets" for debris_timeout_s. Each debris unit's count from its spawn
-- (one that failed paid 2 pieces).
local ROCKETS, DEBRIS = "SV_Unit_SpRockets", { "SV_Unit_SpDebriA", "SV_Unit_SpDebriB", "SV_Unit_SpDebriC" }
-- ((review of 0.73.80) RE_SV_SpRocketRemove (the rockets and their debris: a destroy with no attacker, as the landing
-- craft's) as offFire: what's still up goes down as nobody's on the host (COOP.takenOff), never a kill of a player who
-- once hit it, or the host's; one shot down this tick keeps its killer)
local function rocketsOff()
    if COOP and COOP.takenOff then
        for _, u in ipairs({ ROCKETS, DEBRIS[1], DEBRIS[2], DEBRIS[3] }) do pcall(COOP.takenOff, u) end
    end
    return fire("RE_SV_SpRocketRemove")
end
-- the rockets' and their debris's objects as SV_Spawn makes them: SPORT.rkObjs[unit] = { at = <clock>, obj, ... }
SPORT.rkObjs = {}
local RK_UNIT = { [ROCKETS] = true, [DEBRIS[1]] = true, [DEBRIS[2]] = true, [DEBRIS[3]] = true }
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    if not (u and RK_UNIT[u]) then return end
    local l = SPORT.rkObjs[u]
    if not l or os.clock() - (l.at or 0) > 2 then l = { at = os.clock() }; SPORT.rkObjs[u] = l end   -- (a new spawn of it)
    if #l < 8 then l[#l + 1] = o end
end)
-- the pads, x / y cm (Mission 19's E_Obj_05_Rocket_0 / _1, where the build's port_unit keeps them): which rocket is which
local PAD = { A = { -1384043, -41261 }, B = { -1325196, 59778 } }
local ESCAPE_MIN_S = 50                          -- (an escape with no height read: only this long after its launch; ~80 s)
local DEBRIS_UP_CM = -20000                      -- (the debris spawn 500 m down; the split brings them up to the rocket)
local function posOf(o)
    local p = nil
    if o and liveAddr(o) then pcall(function() local v = o:K2_GetActorLocation(); p = { X = v.X, Y = v.Y, Z = v.Z } end) end
    return p
end
-- The island's enemies (tools/survival_events.py sp_island: their spots past tools/spaceport_spots.py's building check;
-- user, 2026-10-31: "add more enemies around the island"): air defences (Mission 6's EXSAM site, flak guns, Gecko SAMs,
-- Shilka AA guns) and armour (T-90s, BTR-90s), with the garrison; island.ad_pay / armour_pay each, the round held until
-- they're down (each fights as it appears: its engagement order, SV_SpIslUp<key>).
local ISLAND = { { "SV_Unit_SpIslExsam", "ad" }, { "SV_Unit_SpIslFlak", "ad" }, { "SV_Unit_SpIslSam", "ad" },
                 { "SV_Unit_SpIslAA", "ad" }, { "SV_Unit_SpIslTankA", "armour" }, { "SV_Unit_SpIslTankB", "armour" },
                 { "SV_Unit_SpIslApc", "armour" } }
local function rcfg() return cfg().retake and cfg().retake.rockets or {} end

-- The rockets and their debris on the pads (from retakeSpawn); s.rk the round's rockets, or nothing when they're off
local function rocketsSpawn(now, s)
    local rc = rcfg()
    if rc.enabled == false then log("special: the retake's rockets are off ([specials.spaceport.retake.rockets] enabled)"); return 0 end
    if (aliveNow(ROCKETS) or 0) > 0 then rocketsOff() end   -- (left up from before: taken off)
    local r = spawn(ROCKETS)
    if r <= 0 then log("special: the retake's rockets didn't spawn (" .. said(r) .. ")"); return 0 end
    local deb, counts = {}, {}
    for _, u in ipairs(DEBRIS) do
        local rd = spawn(u)
        counts[u] = rd > 0 and rd or 0                  -- ((0.73.77, I5: S8) each one's count from its spawn)
        deb[#deb + 1] = u .. " " .. said(rd)
    end
    s.rk = { n = r, alive = r, at = now, setupAt = now + 2, launch = { A = now + (tonumber(rc.launch_a_s) or 45),
             B = now + (tonumber(rc.launch_b_s) or 110) }, launched = {}, boosted = {}, escaped = {}, kills = 0,
             escPending = 0, debris = counts, lost = {}, out = {}, alt = {} }
    log(string.format("special: the retake's rockets on the pads: %s; launches at +%.0f s and +%.0f s; their debris: %s", said(r),
        s.rk.launch.A - now, s.rk.launch.B - now, table.concat(deb, ", ")))
    return r
end

local function rocketsEscaped(rk) local n = 0; for _ in pairs(rk.escaped) do n = n + 1 end; return n end
local function rocketsLost(rk) local n = 0; for _ in pairs(rk.lost or {}) do n = n + 1 end; return n end

-- (0.73.77, I5) which of the rocket unit's objects is A and which B (nearest its pad, else in their spawn order), at its
-- setup 2 s after the spawn; rk.byObj when both are found: their kills are read from them, not the unit's count
local function mapRockets(rk)
    local cand = {}
    for _, o in ipairs(SPORT.rkObjs[ROCKETS] or {}) do if liveAddr(o) then cand[#cand + 1] = { o = o, p = posOf(o) } end end
    rk.obj = {}
    local said2 = {}
    for _, L in ipairs({ "A", "B" }) do
        local best, bd = nil, nil
        for _, c in ipairs(cand) do
            if not c.used and c.p then
                local d = math.sqrt((c.p.X - PAD[L][1]) ^ 2 + (c.p.Y - PAD[L][2]) ^ 2)
                if not bd or d < bd then best, bd = c, d end
            end
        end
        if not best then for _, c in ipairs(cand) do if not c.used then best = c; break end end end
        if best then
            best.used, rk.obj[L] = true, best.o
            said2[#said2 + 1] = L .. (bd and string.format(" %.0f m from its pad", bd / 100) or " (by order)")
        end
    end
    rk.byObj = rk.n == 2 and rk.obj.A ~= nil and rk.obj.B ~= nil
    log(string.format("special: the rockets' objects: %d found%s; %s", #cand, #said2 > 0 and (" (" .. table.concat(said2, ", ") .. ")") or "",
        rk.byObj and "each one's height and kill read from it" or "counted by their unit"))
end

-- (0.73.77, I5) a rocket's object gone or at 0 health
local function rocketDown(o)
    if not liveAddr(o) then return true end
    local okH, h = pcall(function() return o.HealthInternal end)
    return okH and type(h) == "number" and h <= 0
end

-- (0.73.77, I5: S8) a debris stage's objects up from under the sea: true, false (still down), nil (none to read)
local function debrisUp(stage)
    local any = false
    for _, o in ipairs(SPORT.rkObjs[DEBRIS[stage]] or {}) do
        local p = posOf(o)
        if p then
            any = true
            if p.Z > DEBRIS_UP_CM then return true end
        end
    end
    if any then return false end
    return nil
end

local function debrisTick(now, rk, rc)
    local t = CFG.hud.text
    if rk.stageAt and now >= rk.stageAt then
        rk.stageAt = nil
        fire("RE_SV_SpDebriTgt" .. rk.stage)
        local a = aliveOf(DEBRIS[rk.stage], now) or 0
        log(string.format("special: the rocket's debris, stage %d (%s): targets now (%d up)", rk.stage, DEBRIS[rk.stage], a))
    end
    local u = DEBRIS[rk.stage]
    local a = aliveOf(u, now) or 0
    local was = rk.debris[u] or 0                       -- ((0.73.77) its count from its spawn: 0 if it never came)
    if a < was then
        local pay = tierPay(rc.debris_pay or 0) * (was - a)
        addCredits(pay, "the rocket's debris")
        rk.changeAt = now
        log(string.format("special: the rocket's debris %s: %d left (+%d)", u, a, pay))
    end
    rk.debris[u] = a
    if a <= 0 and not rk.stageAt then                    -- the stage gone: the next is brought in by its death
        rk.stage, rk.changeAt = rk.stage + 1, now
        if rk.stage <= #DEBRIS then
            rk.stageAt = now + (tonumber(rc.debris_next_s) or 2.8)
        else
            rk.done = true
            rocketsOff()
            hudCallout(t.sp_debris_down, t.sp_debris_down_sub)
            log("special: the rocket's debris: every stage down")
        end
    elseif now - (rk.changeAt or now) >= (tonumber(rc.debris_timeout_s) or 120) then
        rk.done = true
        rocketsOff()
        log(string.format("special: the rocket's debris: nothing changed for %.0f s (stage %d, %s %d up): taken off, counted down",
            now - rk.changeAt, rk.stage, u, a))
    end
end

local function rocketsTick(now, s)
    local rk, rc, t = s.rk, rcfg(), CFG.hud.text
    if not rk or rk.done then return end
    if rk.setupAt and now >= rk.setupAt then
        rk.setupAt = nil
        log("special: the rockets' split off until one is left, their debris held (RE_SV_SpRocketSplitOff " .. fire("RE_SV_SpRocketSplitOff") .. ")")
        local okM, errM = pcall(mapRockets, rk)
        if not okM then log("special: the rockets' objects error " .. tostring(errM)) end
    end
    rk.out, rk.lost, rk.alt = rk.out or {}, rk.lost or {}, rk.alt or {}
    local function over() return rk.kills + rocketsEscaped(rk) + rocketsLost(rk) end
    for _, L in ipairs({ "A", "B" }) do
        if not rk.launched[L] and now >= rk.launch[L] and over() < rk.n then
            rk.launched[L] = now
            hudCallout(t.sp_rocket_launch, t.sp_rocket_launch_sub)
            log(string.format("special: rocket %s launched (RE_SV_SpRocketLaunch%s %s)", L, L, fire("RE_SV_SpRocketLaunch" .. L)))
        end
        if rk.launched[L] and not rk.boosted[L] and now >= rk.launched[L] + (tonumber(rc.boost_s) or 12) then
            rk.boosted[L] = true
            log(string.format("special: rocket %s boosted to Mission 19's 1000 km/h (%s)", L, fire("RE_SV_SpRocketBoost" .. L)))
        end
        -- ((0.73.77) its height, the highest so far (m), from its object)
        local o = rk.obj and rk.obj[L]
        if rk.launched[L] and not rk.out[L] and o then
            local p = posOf(o)
            if p then rk.alt[L] = math.max(rk.alt[L] or -1e9, p.Z / 100) end
        end
    end
    local f = svFlags() or {}                           -- escapes first: an escaped rocket's despawn isn't a kill
    local escMin = tonumber(rc.escape_min_m) or 15000
    for _, L in ipairs({ "A", "B" }) do
        if rk.launched[L] and now - rk.launched[L] >= 3 and not rk.out[L] and (f["SV_SpRocketEsc" .. L] or 0) >= 1 then
            local alt, since = rk.alt[L], now - rk.launched[L]
            rk.escPending, rk.escUntil = rk.escPending + 1, now + 5   -- (its despawn isn't a kill either way)
            -- ((0.73.77, I5: S7) only a real climb escapes: from escape_min_m up, or with no height read, ESCAPE_MIN_S on)
            if (alt and alt >= escMin) or (alt == nil and since >= ESCAPE_MIN_S) then
                rk.escaped[L], rk.out[L] = now, "escaped"
                -- ((0.73.77, I2: S9) off every game's zollars: SPORT.debit sends it to the joiners)
                local took = SPORT.debit(rc.escape_penalty, "rocket " .. L .. " escaped")
                hudCallout(t.sp_rocket_escaped, string.format(t.sp_rocket_escaped_sub, took))
                log(string.format("special: rocket %s escaped (its climb's end%s, %.0f s after its launch): -%d zollars, no retake reward",
                    L, alt and string.format(" at %.0f m", alt) or "", since, took))
            else
                rk.lost[L], rk.out[L] = now, "lost"
                log(string.format("special: rocket %s's climb ended short (%s, %.0f s after its launch; an escape counts from %.0f m): "
                    .. "taken off, no penalty", L, alt and string.format("at %.0f m", alt) or "its height not read", since, escMin))
            end
        end
    end
    -- ((0.73.77, I5: S7) one neither down nor escaped timeout_s after its launch: taken off (hidden, out of the fight),
    -- no penalty, so the round never waits on it)
    local tmo = tonumber(rc.timeout_s) or 240
    for _, L in ipairs({ "A", "B" }) do
        if rk.launched[L] and not rk.out[L] and now - rk.launched[L] >= tmo then
            rk.lost[L], rk.out[L] = now, "lost"
            local o = rk.obj and rk.obj[L]
            if o and liveAddr(o) then
                pcall(function() o:SetActorHiddenInGame(true) end)
                pcall(function() o:SetActorEnableCollision(false) end)
                pcall(function() o:SetIsInvincible(true) end)
                pcall(function() o.bShowHUDBox = false end)
                pcall(function() o.bIsNotLockonTarget = true end)
            end
            log(string.format("special: rocket %s neither shot down nor escaped %.0f s after its launch (%s): taken off, no penalty", L,
                now - rk.launched[L], rk.alt[L] and string.format("at %.0f m", rk.alt[L]) or "its height not read"))
        end
    end
    if rk.escPending > 0 and now > (rk.escUntil or 0) then rk.escPending = 0 end
    -- the kills: ((0.73.77) from each rocket's object when both were found) else by the unit's count, an escape's
    -- despawn not one
    local alive = aliveOf(ROCKETS, now) or rk.alive
    local down = 0
    if rk.byObj then
        for _, L in ipairs({ "A", "B" }) do
            if not rk.out[L] and rocketDown(rk.obj[L]) then rk.out[L] = "kill"; down = down + 1 end
        end
    elseif alive < rk.alive then
        down = rk.alive - alive
        local esc = math.min(down, rk.escPending)
        rk.escPending, down = rk.escPending - esc, down - esc
    end
    if down > 0 then
        rk.kills, rk.lastKill = rk.kills + down, now
        local pay = tierPay(rc.rocket_pay or 0) * down
        addCredits(pay, "a rocket shot down")
        LB.stat("ground", down)
        hudCallout(t.sp_rocket_down, string.format(t.sp_rocket_down_sub, specialPay(pay)))   -- ((0.73.78) C3)
        log(string.format("special: a rocket shot down (+%d); %d of %d down, %d escaped, %d taken off", pay, rk.kills, rk.n,
            rocketsEscaped(rk), rocketsLost(rk)))
    end
    rk.alive = alive
    if over() >= 1 and over() < rk.n and not rk.splitOn then
        rk.splitOn, rk.splitOnAt = true, now
        log("special: one rocket left: it breaks up when it's shot down (RE_SV_SpRocketSplitOn " .. fire("RE_SV_SpRocketSplitOn") .. ")")
    end
    if over() >= rk.n and not rk.stage and not rk.splitWait then
        local lastOut = 0
        for _, at in pairs(rk.escaped) do lastOut = math.max(lastOut, at) end
        for _, at in pairs(rk.lost) do lastOut = math.max(lastOut, at) end
        if rc.debris ~= false and rk.lastKill and rk.lastKill >= lastOut then
            rk.splitWait = now + (tonumber(rc.split_wait_s) or 10)   -- ((0.73.77, I5: S8) its debris looked for first)
        else
            rk.done = true
            rocketsOff()
            log(string.format("special: the rockets are done: %d shot down, %d escaped, %d taken off", rk.kills, rocketsEscaped(rk),
                rocketsLost(rk)))
        end
    end
    -- ((0.73.77, I5: S8) the debris only once the split is seen: its first stage up from under the sea, or (none of its
    -- objects to read) the split on before the last kill; else none, the rockets done)
    if rk.splitWait and not rk.stage then
        local up = debrisUp(1)
        local onBefore = rk.splitOnAt ~= nil and rk.lastKill ~= nil and rk.splitOnAt < rk.lastKill
        if up == true or (up == nil and onBefore) then
            rk.splitWait = nil
            rk.stage, rk.stageAt, rk.changeAt = 1, now + (tonumber(rc.debris_tgt_s) or 3), now
            hudCallout(t.sp_debris, t.sp_debris_sub)
            log(string.format("special: the last rocket broke up (%s): its debris falls (stage 1 targets in %s s)",
                up and "its debris seen coming up" or "its split was on", tostring(rc.debris_tgt_s or 3)))
        elseif up == nil or now >= rk.splitWait then
            rk.splitWait, rk.done = nil, true
            rocketsOff()
            log(string.format("special: the last rocket went down without breaking up (%s): no debris; the rockets are done: %d shot "
                .. "down, %d escaped, %d taken off", up == nil and "its split wasn't on yet: they went down together"
                or string.format("no debris came up in %s s", tostring(rc.split_wait_s or 10)), rk.kills, rocketsEscaped(rk), rocketsLost(rk)))
        end
    end
    if rk.stage and not rk.done then debrisTick(now, rk, rc) end
end

-- The round after a captured spaceport (specialFor: RUN.sport.retakeRound). Ctrl+INS (test only) forces it without a
-- lost assault: the garrison for retake.test_troops troops, and no ships.
function SPORT.retakeSpawn(now)
    local c, t = cfg(), CFG.hud.text
    if not nativeReady() then return false end
    local rs = RUN.sport or { troops = (c.retake and c.retake.test_troops) or 8, ships = {}, forced = true }
    RUN.sport = nil
    local s = D.special
    s.state, s.at, s.ships, s.garrison, s.queue = "retake", now, {}, {}, {}
    -- ((0.73.77, I7: S12) the retake in play, for the joiners while it's on (SPORT.coopCode): a host migration starts it
    -- again on the new host)
    s.rs = { retakeRound = D.round, troops = rs.troops or 0, lostRound = rs.lostRound or 0 }
    local again = {}
    for unit, sh in pairs(rs.ships or {}) do
        local a = aliveNow(unit) or 0
        -- ((0.73.77) a host by migration: the old host's ships here were its copies, taken down with them: spawned again)
        if a <= 0 and rs.fromHost and SHIP[unit] then
            local r = spawn(unit)
            a = r > 0 and r or 0
            again[#again + 1] = unit:sub(#"SV_Unit_Sp" + 1) .. " " .. said(r)
        end
        if a > 0 then s.ships[unit] = { kind = sh.kind, group = sh.group, alive = a } end
    end
    if #again > 0 then
        log("special: the retake's ships spawned again on this game (a host migration took the old host's copies down): "
            .. table.concat(again, ", "))
    end
    local per = math.max(1, math.floor(tonumber(c.retake and c.retake.per_unit) or 4))
    local need = math.max(1, math.min(#GARRISON, math.ceil((rs.troops or 0) / per)))
    local n = 0
    for i = 1, need do
        local u = "SV_Unit_SpGarrison" .. GARRISON[i]
        local r = (aliveNow(u) or 1) <= 0 and spawn(u) or -100
        if r > 0 then s.garrison[u] = { alive = r }; n = n + r end
        log(string.format("special: the spaceport's garrison %s: %s", u, r == -100 and "still up from before" or said(r)))
    end
    local nr = rocketsSpawn(now, s)
    local ni, isl = 0, {}
    local ic = c.retake and c.retake.island or {}
    s.island = {}
    if ic.enabled ~= false then
        for _, it in ipairs(ISLAND) do
            local r = (aliveNow(it[1]) or 1) <= 0 and spawn(it[1]) or -100
            if r > 0 then s.island[it[1]] = { alive = r, kind = it[2] }; ni = ni + r end
            isl[#isl + 1] = it[1]:sub(#"SV_Unit_SpIsl" + 1) .. " " .. (r == -100 and "still up from before" or said(r))
        end
        log("special: the island's defences and armour: " .. table.concat(isl, ", "))
    end
    if n == 0 and ni == 0 and SPORT.shipsUp(s) == 0 and nr == 0 then log("special: no garrison, island enemies, ships or rockets for the retake; a normal round"); return false end
    hudCallout(t.sp_retake_go, t.sp_retake_go_sub)
    log(string.format("special: round %d, the Spaceport Retake: %d garrison vehicles, %d island enemies, %d ships from the assault%s",
        D.round, n, ni, SPORT.shipsUp(s), rs.forced and " (forced)" or ""))
    return true
end

function SPORT.retakeTick(now, s)
    if s.state ~= "retake" or now < (s.nextAt or 0) then return end
    if levelGoing() then return end                  -- ((0.73.77) no pay while the level goes away)
    s.nextAt = now + 1
    ALIVE.tick(now)                                  -- ((0.73.80) roundsTick's own already: the same tick, no second budget)
    local c = cfg()
    holdClocks(now, s)                               -- ((0.73.77, I6: S10) the rockets' launches wait while you're down)
    shipsTick(s, now)
    for unit, x in pairs(s.garrison) do
        if x.alive > 0 then
            local a = aliveOf(unit, now) or x.alive
            if a < x.alive then
                addCredits(tierPay(c.retake and c.retake.garrison_pay or 0) * (x.alive - a), "the spaceport's garrison: a vehicle down")
                LB.stat("ground", x.alive - a)
                log(string.format("special: the spaceport's garrison %s: %d left", unit, a))
            end
            x.alive = a
        end
    end
    local okD, errD = pcall(deck, now, s)
    if not okD and tostring(errD) ~= s.deckErr then s.deckErr = tostring(errD); log("special: the Ford's deck error " .. s.deckErr) end
    local ic = c.retake and c.retake.island or {}
    for unit, x in pairs(s.island or {}) do
        if x.alive > 0 then
            local a = aliveOf(unit, now) or x.alive
            if a < x.alive then
                addCredits(tierPay((x.kind == "ad" and ic.ad_pay or ic.armour_pay) or 0) * (x.alive - a),
                    x.kind == "ad" and "the island's air defences: one down" or "the island's armour: one down")
                LB.stat("ground", x.alive - a)
                log(string.format("special: the island's %s %s: %d left", x.kind == "ad" and "air defence" or "armour", unit, a))
            end
            x.alive = a
        end
    end
    local okR, errR = pcall(rocketsTick, now, s)
    if not okR and tostring(errR) ~= s.rkErr then s.rkErr = tostring(errR); log("special: the retake's rockets error " .. s.rkErr) end
end

function SPORT.retakeBusy(s)
    if s.state ~= "retake" then return false end
    for _, x in pairs(s.garrison or {}) do if x.alive > 0 then return true end end
    if s.rk and not s.rk.done then return true end                -- (a rocket or its debris still up)
    for _, x in pairs(s.island or {}) do if x.alive > 0 then return true end end
    return SPORT.shipsUp(s) > 0
end

function SPORT.retakeOver(now, s)
    local c, t = cfg(), CFG.hud.text
    s.state = "done"
    if COOP and COOP.takenOff then                        -- ((review of 0.73.80) taken off: nobody's, as offFire)
        for _, g in ipairs(GARRISON) do pcall(COOP.takenOff, "SV_Unit_SpGarrison" .. g) end
    end
    fire("RE_SV_SpGarrisonRemove")                        -- (none should be left: tidy)
    if s.rk then rocketsOff() end
    if s.island and next(s.island) then
        if COOP and COOP.takenOff then for _, it in ipairs(ISLAND) do pcall(COOP.takenOff, it[1]) end end
        fire("RE_SV_SpIslandRemove")
    end
    if next(s.ships or {}) then SPORT.tidyFleet("the spaceport retaken") end   -- ((0.73.77) a sunk ship's parts left)
    local pay = math.floor((c.retake and c.retake.reward or 0) + (c.retake and c.retake.reward_per_round or 0) * D.round)
    local esc = s.rk and rocketsEscaped(s.rk) or 0
    if esc > 0 then                                         -- (a rocket reached orbit: no reward)
        log(string.format("special: the retake's reward withheld: %d rocket%s escaped", esc, esc == 1 and "" or "s"))
        pay = 0
    end
    addCredits(pay, "spaceport retaken")
    LB.special("retake", true, now - (s.at or now))
    hudCallout(t.sp_retaken, string.format(t.sp_retaken_sub, specialPay(pay)))   -- ((0.73.78) C3: each player's share)
    log(string.format("special: round %d, the spaceport was retaken", D.round))
end

---------------------------------------------------------------------------------------------------- the round's plan
-- (0.73.77) The round being planned (sv_rounds.lua startRound, its special known, before any flight is picked; pick its
-- picker, which marks what it takes in D.taken):
--   * I4 (S6): the fighters withdrawn at a capture (D.spWithdrawn) still reading up are recycled (the native runtime's
--     SV_Recycle(unit, 1): 1 recycled, 0 nothing to do, < 0 an error), in the break after their round (a destroy at the
--     moment of a spawn is the 2026-11-02 runway crash's pattern); without it, or refused, kept out of this round's
--     picks (D.taken) while they read up;
--   * I3 (S4): a retake that was due and didn't come (another special forced, its spawn refused) takes the fleet left
--     from its assault off (RE_SV_SpFleetRemove) and forgets it;
--   * I8 (S13): a Spaceport round with the Ford (the assault, or a retake it's carried into) holds deck.reserve of its
--     deck's flights back from the round's fighters (round 13's 22 fighters took every free 2-ship: 2 of 8 launches,
--     "no free 2-ship to launch"); the deck launches them first (deckFlight), relaunching one once it's down.
function SPORT.planRound(special, pick)
    D.spDeck = nil
    local w = D.spWithdrawn
    if w and next(w) then
        local done, kept, gone = {}, {}, 0
        for u in pairs(w) do
            if SV_UnitAlive(u) <= 0 then
                w[u], gone = nil, gone + 1
            else
                local r = nil
                if type(SV_Recycle) == "function" then
                    local okR, x = pcall(SV_Recycle, u, 1)
                    r = okR and tonumber(x) or nil
                end
                if r == 1 or (r == 0 and SV_UnitAlive(u) <= 0) then
                    w[u] = nil
                    done[#done + 1] = u
                else
                    if D.taken then D.taken[u] = true end
                    kept[#kept + 1] = u .. (r and string.format(" (SV_Recycle %s)", (SV_ERR and SV_ERR[r]) or tostring(r)) or "")
                end
            end
        end
        log(string.format("special: the fighters withdrawn at the capture: %d down since, %d recycled (SV_Recycle)%s%s", gone, #done,
            #done > 0 and (": " .. table.concat(done, ", ")) or "", #kept > 0 and string.format("; %d still up kept out of round %d's picks%s: %s",
                #kept, D.round, type(SV_Recycle) == "function" and "" or " (no SV_Recycle in this runtime)", table.concat(kept, ", ")) or ""))
    end
    local rs = RUN.sport
    if rs and (tonumber(rs.retakeRound) or 0) <= D.round and special ~= "retake" then
        local up = {}
        for _, sh in ipairs(SPORT.fleet()) do
            if (aliveNow(sh.unit) or 0) > 0 then up[#up + 1] = sh.unit:sub(#"SV_Unit_Sp" + 1) end
        end
        log(string.format("special: the Spaceport Retake due in round %s didn't come (round %d is %s): %s", tostring(rs.retakeRound),
            D.round, special or "a normal round", #up > 0 and string.format("the %d ships left from its assault taken off (%s; "
                .. "RE_SV_SpFleetRemove %s)", #up, table.concat(up, ", "), fleetFire()) or "no ship left from its assault"))
        RUN.sport = nil
    end
    local dk = cfg().deck
    local withFord = (special == "spaceport" and (tonumber((cfg().ships or {}).ford) or 0) > 0)
        or (special == "retake" and RUN.sport ~= nil and type(RUN.sport.ships) == "table" and RUN.sport.ships[FORD] ~= nil)
    if type(dk) == "table" and dk.enabled and withFord and type(pick) == "function" then
        local planned = math.max(0, math.min(math.floor(tonumber(dk.max_flights) or 0),
            math.floor(tonumber(dk.flights) or 0) + math.floor(D.round * (tonumber(dk.flights_per_round) or 0))))
        local want = math.min(planned, math.max(0, math.floor(tonumber(dk.reserve) or 0)))
        local size = math.floor(tonumber(dk.size) or 2)
        if want > 0 then
            local got = pick(CFG.pool, want * size, function(u)
                return flightSize(u) ~= size or PROBE_OF[u] or poolIndex(u) == nil or ROLE.sitsOut(u) or ALIVE.ask(u) > 0
            end)
            D.spDeck = {}
            for _, u in ipairs(got) do D.spDeck[u] = true end
            log(string.format("special: the Ford's deck: %d of %d %d-ships held back from round %d's fighters for it (%d launches "
                .. "planned)%s", #got, want, size, D.round, planned, #got > 0 and (": " .. table.concat(got, ", ")) or ""))
        end
    end
end

---------------------------------------------------------------------------------------------------- money and co-op
-- (0.73.77, I2: S9) A penalty off this game's zollars, as the STORE takes them (each game takes what it has of it), and
-- from the host (or solo) to every co-op game ("db", sv_coop.lua COOP.debit; the escape's -5,000 came off the host's
-- money alone while its callout went to everyone). fromHost: a joiner's, from the host's "db". What was taken here.
function SPORT.debit(n, why, fromHost)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return 0 end
    -- ((0.73.78) split as a special's reward is (economy C3, user 2026-11-03: "you have it right"): each player loses the
    -- penalty x players ^ -special_split, worked out on the host and sent as it is; solo the whole of it)
    if not fromHost and COOP and COOP.specialShare then
        local okS, sh = pcall(COOP.specialShare)
        if okS and type(sh) == "number" and sh > 0 and sh < 1 then
            log(string.format("special: the penalty's co-op share x%.2f of %d", sh, n))
            n = math.floor(n * sh / 10 + 0.5) * 10
        end
    end
    local took = math.min(n, math.max(0, math.floor(RUN.credits or 0)))
    if took > 0 then RUN.credits, RUN.dirty, RUN.msg = RUN.credits - took, true, {} end
    log(string.format("credits: -%d (%s%s), now %d", took, tostring(why), fromHost and ", the host's round" or "", RUN.credits or 0))
    if not fromHost and COOP and COOP.debit then
        local okD, errD = pcall(COOP.debit, n, why)
        if not okD then log("special: the penalty's co-op send error " .. tostring(errD)) end
    end
    return took
end

-- (0.73.77, I7: S12) What the host shares with the joiners about the Spaceport (sv_coop.lua "spx", once a second while
-- it changes, every 10 s anyway): "<row>;<pending>". row: the NEXT row's numbers ("a:<ships>:<craft>:<capture %>" in the
-- assault, "r:<garrison>:<ships>" in the retake, "-"); pending: the retake due or in play ("<round>:<troops>:<lost
-- round>:<ship>,<ship>...", the ships as SV_Unit_Sp<name>'s <name>, "-"), which a joiner keeps as its RUN.sport so a host
-- migration (sv_coop.lua becomeHost: the round in play again, between rounds the next) still brings the retake.
function SPORT.coopCode()
    local s = D and D.special
    local row = "-"
    if s and s.kind == "spaceport" and s.state == "assault" then
        row = string.format("a:%d:%d:%d:%d", SPORT.shipsUp(s), SPORT.craftIn(s), math.floor(s.capture or 0), SPORT.tuUp(s))
    elseif s and s.kind == "retake" and s.state == "retake" then
        local g = 0
        for _, x in pairs(s.garrison or {}) do g = g + math.max(0, x.alive) end
        row = string.format("r:%d:%d", g, SPORT.shipsUp(s))
    end
    local rs, ships = RUN.sport, {}
    if rs then
        for unit in pairs(rs.ships or {}) do ships[#ships + 1] = unit:sub(#"SV_Unit_Sp" + 1) end
    elseif s and s.kind == "retake" and s.state == "retake" and s.rs then
        rs = s.rs
        for unit, sh in pairs(s.ships or {}) do if afloat(sh) then ships[#ships + 1] = unit:sub(#"SV_Unit_Sp" + 1) end end
    end
    local pend = "-"
    if rs then
        table.sort(ships)
        pend = string.format("%d:%d:%d:%s", math.floor(tonumber(rs.retakeRound) or 0), math.floor(tonumber(rs.troops) or 0),
            math.floor(tonumber(rs.lostRound) or 0), table.concat(ships, ","))
    end
    return row .. ";" .. pend
end

-- (0.73.77, I7) a joiner: the host's "spx" (checked: whole numbers in range, the fleet's own units only)
function SPORT.fromHost(code)
    if type(code) ~= "string" or #code > 400 then return end
    local row, pend = code:match("^([^;]*);([^;]*)$")
    if not row then return end
    local function num(v, hi) v = tonumber(v); return (v and v >= 0 and v <= hi and v == math.floor(v)) and v or nil end
    local h = nil
    local a1, a2, a3, a4 = row:match("^a:(%d+):(%d+):(%d+):?(%d*)$")
    if a1 and num(a1, 100) and num(a2, 200) and num(a3, 100) and (a4 == "" or num(a4, 24)) then
        h = { kind = "a", a = num(a1, 100), b = num(a2, 200), c = num(a3, 100), d = a4 ~= "" and num(a4, 24) or 0 }
    else
        local r1, r2 = row:match("^r:(%d+):(%d+)$")
        if r1 and num(r1, 100) and num(r2, 100) then h = { kind = "r", a = num(r1, 100), b = num(r2, 100) } end
    end
    if h then h.got = os.clock() end
    SPORT.hostRow = h
    if pend == "-" or pend == "" then
        if RUN.sport and RUN.sport.fromHost then
            RUN.sport = nil
            log("coop: the host's Spaceport Retake is no longer pending")
        end
        return
    end
    local rr, tr, lr, list = pend:match("^(%d+):(%d+):(%d+):([%w,]*)$")
    if not (rr and num(rr, 100000) and num(tr, 1000) and num(lr, 100000)) then return end
    local ships, n = {}, 0
    for k in list:gmatch("[%w]+") do
        local sh = SHIP["SV_Unit_Sp" .. k]
        if sh and n < 40 then ships[sh.unit] = { kind = sh.kind, group = sh.group }; n = n + 1 end
    end
    local was = RUN.sport
    RUN.sport = { retakeRound = num(rr, 100000), troops = num(tr, 1000), lostRound = num(lr, 100000), ships = ships, fromHost = true }
    if not (was and was.fromHost and was.retakeRound == RUN.sport.retakeRound) then
        log(string.format("coop: the host's Spaceport Retake is due in round %d (%d ships carried): kept here for a host migration",
            RUN.sport.retakeRound, n))
    end
end

-- (0.73.77, I7: S12) a joiner's NEXT row: the host's Spaceport row (5 s fresh at most), or nil
function SPORT.clientRow(t)
    local h = SPORT.hostRow
    if not (h and COOP and COOP.client and COOP.client() and os.clock() - (h.got or 0) <= 5) then return nil end
    if h.kind == "a" then
        return string.format(t.sp_row, h.a, h.b, h.c) .. (((h.d or 0) > 0 and t.sp_row_tu160) and string.format(t.sp_row_tu160, h.d) or "")
    end
    if h.kind == "r" then return string.format(t.sp_retake_row, h.a, h.b) end
    return nil
end
end
