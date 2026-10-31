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
SPORT = {}
do
local GROUPS, WAVES, CRAFT, GARRISON = { "A", "B", "C", "D" }, { "V", "W", "X", "Y", "Z" }, { "L", "R" }, { "A", "B", "C" }
local AEGIS, BOATS = "ABCDEFGHIJKLMN", "ABCDEFGH"
local FORD = "SV_Unit_SpFord"
local DECK_FLOOR_M = 1100                         -- (the pool's 2-ship units fly 1000 m and up, as the Alicorn's deck)

local function cfg() return CFG.specials.spaceport end
local function tierPay(base) return (TIER.pay(base * TIER.specialX(), D and D.round and TIER.index(D.round))) end
local function fire(name) return tostring(type(SV_Event) == "function" and SV_Event(name) or "n/a") end
local function aliveOf(unit)                      -- (0 for a unit off the list, nil for an error: not counted)
    local n = SV_UnitAlive(unit)
    if n == -7 then return 0 end
    return n >= 0 and n or nil
end
local function spawn(unit)
    spawningUnit = unit
    local r = SV_Spawn(unit)
    spawningUnit = nil
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
    if spawningUnit == FORD and not (SPORT.fordActor and valid(SPORT.fordActor)) then SPORT.fordActor = o end
end)
-- The fleet's turrets as SV_Spawn makes them (the user's loggers of 2026-10-31: sv_weaponlog.lua's fleet watch): every
-- object of a ship unit, kept by address once its class reads as a turret's (a mount: mk15 / mk41 / mk45 / the artillery /
-- a SAM launcher); its object checked valid before each read, dropped once it's gone.
SPORT.turrets, SPORT.newParts = {}, {}
local TURRET_CLASS = { "mk15", "mk41", "mk45", "artillery", "_sam", "aagun" }
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    if u and (u:find("^SV_Unit_SpAegis") or u:find("^SV_Unit_SpFord") or u:find("^SV_Unit_SpBoat")) and #SPORT.newParts < 400 then
        SPORT.newParts[#SPORT.newParts + 1] = { obj = o, unit = u, at = os.clock() }
    end
end)
function SPORT.partsTick()
    if #SPORT.newParts == 0 then return end
    local keep, now = {}, os.clock()
    for _, np in ipairs(SPORT.newParts) do
        if now - np.at < 0.5 then keep[#keep + 1] = np                    -- (a moment to be named)
        elseif valid(np.obj) then
            local cls = ((nameOf(np.obj):match("([%w_]+)$") or "?"):gsub("_C_%d+$", ""):gsub("_C$", ""))
            local low = cls:lower()
            for _, k in ipairs(TURRET_CLASS) do
                if low:find(k, 1, true) then
                    local a = addrOf(np.obj)
                    if a then SPORT.turrets[a] = { obj = np.obj, unit = np.unit, cls = cls, shots = 0 } end
                    break
                end
            end
        end
    end
    SPORT.newParts = keep
end

local function fordAt()
    local c = cfg()
    local a = SPORT.fordActor
    if a and not valid(a) then SPORT.fordActor, a = nil, nil end
    local at
    if a then pcall(function() local v = a:K2_GetActorLocation(); at = { X = v.X, Y = v.Y, Z = v.Z } end) end
    local f = c.ford_cm or {}
    at = at or { X = f[1] or 0, Y = f[2] or 0, Z = 0 }
    return at, math.rad(f[3] or 0)
end

-- A free fighter 2-ship for the deck: not up, not one of the round's own, not a probe or a role flight sitting out.
local function deckFlight(size)
    local opts = {}
    for _, u in ipairs(CFG.pool) do
        if flightSize(u) == size and not (D.up and D.up[u]) and not (D.taken and D.taken[u]) and SV_UnitAlive(u) <= 0
            and not PROBE_OF[u] and poolIndex(u) ~= nil and not ROLE.sitsOut(u) then opts[#opts + 1] = u end
    end
    return #opts > 0 and opts[math.random(#opts)] or nil
end

-- The Ford's deck (CFG.specials.spaceport.deck), as the Alicorn's: while it's afloat, a free pool flight of deck.size
-- off its bow (spawnFlight with a pose: ahead_m along its heading, alt_m up), first_s after the fleet appears and every
-- every_s after a launch, flights + flights_per_round a round (at most max_flights), never more than max_up of them up,
-- never while you're down at the airfield (but in co-op while another player flies).
local function deck(now, s)
    local dk = cfg().deck
    local ford = s.ships and s.ships[FORD]
    if not (type(dk) == "table" and dk.enabled and ford and ford.alive > 0) then return end
    if not s.deckLeft then
        s.deckLeft = math.max(0, math.min(math.floor(tonumber(dk.max_flights) or 0),
            math.floor(tonumber(dk.flights) or 0) + math.floor(D.round * (tonumber(dk.flights_per_round) or 0))))
        s.deckNext = now + (tonumber(dk.first_s) or 45)
        log(string.format("special: the Ford's deck launches up to %d flights this round", s.deckLeft))
    end
    if s.deckLeft <= 0 or now < s.deckNext then return end
    s.deck = s.deck or {}
    local up = 0
    for u in pairs(s.deck) do if SV_UnitAlive(u) > 0 then up = up + 1 end end
    if up >= (tonumber(dk.max_up) or 2) then s.deckNext = now + 2; return end
    local flying = playerOnAirfield() and othersFlying()
    if flying == 0 then s.deckNext = now + 1; return end
    local size = math.floor(tonumber(dk.size) or 2)
    local u = deckFlight(size)
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
    if r > 0 then
        s.deck[u], s.deckN = true, (s.deckN or 0) + 1
        s.deckLeft = s.deckLeft - 1
        for i = #(D.spare or {}), 1, -1 do if D.spare[i] == u then table.remove(D.spare, i) end end   -- (no spare now)
        s.deckNext = now + (tonumber(dk.every_s) or 50)
        log(string.format("special: the Ford's deck launch %d: %s, %d aircraft at %.0f m, %d launches left this round", s.deckN, u, r,
            pose.z / 100, s.deckLeft))
    else
        s.deckNext = now + 5
        log(string.format("special: the Ford's deck: %s didn't launch (%s)", u, (SV_ERR and SV_ERR[r]) or tostring(r)))
    end
end

-- Ships lost since the last look: paid, logged, the Wasps' and the Ford's called out.
local function shipsTick(s)
    local c, t = cfg(), CFG.hud.text
    for unit, sh in pairs(s.ships) do
        if sh.alive > 0 then
            local a = aliveOf(unit) or sh.alive
            if a < sh.alive then
                addCredits(tierPay((c.pay or {})[sh.kind] or 0) * (sh.alive - a), "the spaceport's fleet: " .. sh.kind .. " sunk")
                LB.stat("ground", sh.alive - a)
                log(string.format("special: spaceport fleet: %s %s sunk", sh.kind, unit))
                if sh.kind == "wasp" then hudCallout(t.sp_wasp_down, t.sp_wasp_down_sub)
                elseif sh.kind == "ford" then hudCallout(t.sp_ford_down, t.sp_ford_down_sub) end
            end
            sh.alive = a
        end
    end
end

-- Ships still afloat.
function SPORT.shipsUp(s)
    local n = 0
    for _, sh in pairs(s and s.ships or {}) do if sh.alive > 0 then n = n + 1 end end
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

-- Whether a Spaceport Assault can come: the native spawner, the turrets' rows in, and none of its fleet still up.
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
    for _, sh in ipairs(SPORT.fleet()) do if (aliveOf(sh.unit) or 0) > 0 then return false end end
    return true
end

function SPORT.spawn(now)
    local c, t = cfg(), CFG.hud.text
    if not nativeReady() then return false end
    for _, sh in ipairs(SPORT.fleet()) do
        if (aliveOf(sh.unit) or 0) > 0 then
            log("special: the spaceport's fleet was still up from last time; taken off (RE_SV_SpFleetRemove "
                .. fire("RE_SV_SpFleetRemove") .. "), none this round")
            return false
        end
    end
    local s = D.special
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
    hudCallout(t.sp_go, t.sp_go_sub)
    log(string.format("special: round %d, the Spaceport Assault: %d ships coming in west of the spaceport", D.round, #s.queue))
    return true
end

-- The round's fighters fall back with the capture (the user's test of 2026-10-31: "after the spaceport was captured,
-- the next round didn't start": six fighters were still up, and a round ends only with its aircraft down): each pool
-- flight up is despawned (RE_SV_FlightOff_NN, Mission 22's own despawn) and off the round's list (D.up: a despawned
-- unit can still read alive), its planes marked down (no pay), the round's queue and later waves dropped, no more deck
-- launches. The round then ends as any does, and the retake comes after its break.
local function withdraw(s)
    local gone, n = {}, 0
    D.queue, D.spare = {}, {}
    if D.waves then D.wave = #D.waves end
    if D.state == "spawning" or D.state == "wave" then D.state = "fighting" end
    for u in pairs(D.up or {}) do
        local k = poolIndex(u)
        if k then
            n = n + math.max(0, SV_UnitAlive(u))
            fire(string.format("RE_SV_FlightOff_%02d", k))
            gone[u] = true
            gone[#gone + 1] = u
        end
    end
    for _, u in ipairs(gone) do D.up[u] = nil end
    for _, p in ipairs(planes or {}) do
        if p.unit and gone[p.unit] and not p.down then p.down, p.withdrawn = true, true end
    end
    s.deckLeft = 0
    log(string.format("special: the round's fighters fall back with the capture: %d flights (%d aircraft) taken off%s", #gone, n,
        #gone > 0 and (": " .. table.concat(gone, ", ")) or ""))
end

-- A lane's next free wave: one not out and not still up from before.
local function freeWave(g, L)
    for _, w in ipairs(WAVES) do
        if not L.waves[w] and (aliveOf("SV_Unit_SpLcac" .. g .. w) or 1) <= 0 then return w end
    end
end

function SPORT.tick(now, s)
    if s.state ~= "assault" then return end
    local c, t = cfg(), CFG.hud.text
    if #s.queue > 0 and now >= (s.spawnAt or 0) then          -- the fleet, a few ships at a time
        s.spawnAt = now + 0.5
        for _ = 1, math.max(1, math.floor(tonumber(c.spawn_per_tick) or 3)) do
            local sh = table.remove(s.queue, 1)
            if not sh then break end
            local r = spawn(sh.unit)
            if r > 0 then s.ships[sh.unit] = { kind = sh.kind, group = sh.group, alive = r } end
            log(string.format("special: spaceport fleet: %s %s: %s", sh.kind, sh.unit, said(r)))
        end
    end
    if now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    shipsTick(s)
    local f = svFlags() or {}
    for _, g in ipairs(GROUPS) do
        local L = s.lanes[g]
        local wasp = s.ships["SV_Unit_SpWasp" .. g]
        if wasp and wasp.alive > 0 and not s.captured and now >= L.next then   -- its Wasp's next wave
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
            local alive = wv.removed and 0 or (aliveOf(wv.unit) or wv.alive)
            if alive < wv.alive and not wv.removed then
                wv.shot, s.stat.shot = (wv.shot or 0) + (wv.alive - alive), s.stat.shot + (wv.alive - alive)
                addCredits(tierPay(c.pay and c.pay.craft or 0) * (wv.alive - alive), "landing craft down (" .. wv.unit .. ")")
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
                    if not s.captured and (aliveOf(tu) or 1) <= 0 then r = spawn(tu) end
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
                log(string.format("special: %s are away; taken off (%s)", wv.unit, fire("RE_SV_SpLcacRemove" .. g .. w)))
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
                s.capture = math.min(100, s.capture + (tonumber(c.capture_per_troop) or 5))
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
            log(string.format("special: troops %s %s; taken off (%s)", tr.unit, why, fire("RE_SV_SpTroopsRemove" .. tr.key)))
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
                if not wv.removed then wv.removed = true; log(string.format("special: %s recalled (%s)", wv.unit, fire("RE_SV_SpLcacRemove" .. g .. w))) end
            end
        end
        local okW, errW = pcall(withdraw, s)
        if not okW then log("special: the fighters' withdrawal error " .. tostring(errW)) end
    end
    local okD, errD = pcall(deck, now, s)
    if not okD and tostring(errD) ~= s.deckErr then s.deckErr = tostring(errD); log("special: the Ford's deck error " .. s.deckErr) end
end

-- The round can't end while a ship is afloat, a craft is coming in or troops are on their way, short of the capture
-- (captured, the ships carry over into the retake).
function SPORT.busy(s)
    if s.state ~= "assault" or s.captured then return false end
    if SPORT.shipsUp(s) > 0 or SPORT.craftIn(s) > 0 then return true end
    for _, tr in ipairs(s.troops) do if not tr.reached then return true end end
    return false
end

function SPORT.roundOver(now, s)
    local c, t = cfg(), CFG.hud.text
    for g, L in pairs(s.lanes or {}) do
        for w, wv in pairs(L.waves) do
            if not wv.removed then wv.removed = true; log(string.format("special: %s taken off at the round's end (%s)", wv.unit, fire("RE_SV_SpLcacRemove" .. g .. w))) end
        end
    end
    for _, tr in ipairs(s.troops or {}) do fire("RE_SV_SpTroopsRemove" .. tr.key) end
    s.troops, s.state = {}, "done"
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
            if sh.alive > 0 then RUN.sport.ships[unit] = { kind = sh.kind, group = sh.group }; left = left + 1 end
        end
        LB.special("spaceport", false, now - (s.at or now))
        hudCallout(t.sp_lost, string.format(t.sp_lost_sub, left))
        log(string.format("special: round %d, the spaceport was lost; %d ships carry over into the retake", D.round, left))
    else
        local pay = (c.reward or 0) + (c.reward_per_round or 0) * D.round
        addCredits(pay, "spaceport held")
        LB.special("spaceport", true, now - (s.at or now))
        hudCallout(t.sp_held, string.format(t.sp_held_sub, pay))
        log(string.format("special: round %d, the spaceport held (%d%% captured)", D.round, s.capture or 0))
        RUN.sport = nil
    end
end

-- The NEXT row while it's on.
function SPORT.row(s, t)
    if s.state == "assault" then
        return string.format(t.sp_row, SPORT.shipsUp(s), SPORT.craftIn(s), s.capture or 0)
    elseif s.state == "retake" then
        local g = 0
        for _, x in pairs(s.garrison or {}) do g = g + math.max(0, x.alive) end
        return string.format(t.sp_retake_row, g, SPORT.shipsUp(s))
    end
end

---------------------------------------------------------------------------------------------------- the retake
-- The round after a captured spaceport (specialFor: RUN.sport.retakeRound). Ctrl+INS (test only) forces it without a
-- lost assault: the garrison for retake.test_troops troops, and no ships.
function SPORT.retakeSpawn(now)
    local c, t = cfg(), CFG.hud.text
    if not nativeReady() then return false end
    local rs = RUN.sport or { troops = (c.retake and c.retake.test_troops) or 8, ships = {}, forced = true }
    RUN.sport = nil
    local s = D.special
    s.state, s.at, s.ships, s.garrison, s.queue = "retake", now, {}, {}, {}
    for unit, sh in pairs(rs.ships or {}) do
        local a = aliveOf(unit) or 0
        if a > 0 then s.ships[unit] = { kind = sh.kind, group = sh.group, alive = a } end
    end
    local per = math.max(1, math.floor(tonumber(c.retake and c.retake.per_unit) or 4))
    local need = math.max(1, math.min(#GARRISON, math.ceil((rs.troops or 0) / per)))
    local n = 0
    for i = 1, need do
        local u = "SV_Unit_SpGarrison" .. GARRISON[i]
        local r = (aliveOf(u) or 1) <= 0 and spawn(u) or -100
        if r > 0 then s.garrison[u] = { alive = r }; n = n + r end
        log(string.format("special: the spaceport's garrison %s: %s", u, r == -100 and "still up from before" or said(r)))
    end
    if n == 0 and SPORT.shipsUp(s) == 0 then log("special: no garrison and no ships for the retake; a normal round"); return false end
    hudCallout(t.sp_retake_go, t.sp_retake_go_sub)
    log(string.format("special: round %d, the Spaceport Retake: %d garrison vehicles, %d ships from the assault%s", D.round, n,
        SPORT.shipsUp(s), rs.forced and " (forced)" or ""))
    return true
end

function SPORT.retakeTick(now, s)
    if s.state ~= "retake" or now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    local c = cfg()
    shipsTick(s)
    for unit, x in pairs(s.garrison) do
        if x.alive > 0 then
            local a = aliveOf(unit) or x.alive
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
end

function SPORT.retakeBusy(s)
    if s.state ~= "retake" then return false end
    for _, x in pairs(s.garrison or {}) do if x.alive > 0 then return true end end
    return SPORT.shipsUp(s) > 0
end

function SPORT.retakeOver(now, s)
    local c, t = cfg(), CFG.hud.text
    s.state = "done"
    fire("RE_SV_SpGarrisonRemove")                        -- (none should be left: tidy)
    local pay = (c.retake and c.retake.reward or 0) + (c.retake and c.retake.reward_per_round or 0) * D.round
    addCredits(pay, "spaceport retaken")
    LB.special("retake", true, now - (s.at or now))
    hudCallout(t.sp_retaken, string.format(t.sp_retaken_sub, pay))
    log(string.format("special: round %d, the spaceport was retaken", D.round))
end
end
