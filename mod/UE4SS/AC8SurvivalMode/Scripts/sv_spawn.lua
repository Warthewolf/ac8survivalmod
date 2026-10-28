-- sv_spawn.lua: the clock, spawn points, squadrons, flights and the shuttle's spawn.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- The game clock (seconds, stops while paused), or nil.
function gameClock(pc)
    local gs = cdo("/Script/Engine.Default__GameplayStatics")
    if not (gs and valid(pc)) then return nil end
    local ok, t = pcall(function() return gs:GetTimeSeconds(pc) end)
    return (ok and type(t) == "number") and t or nil
end

function gamePaused(pc)
    local gs = cdo("/Script/Engine.Default__GameplayStatics")
    local ok, p = pcall(function() return gs:IsGamePaused(pc) end)
    return ok and p == true
end

-- Runtime HUD reverse engineering: the live HUD's widget tree with each widget's on-screen geometry, to check the
-- static layout (tools/re/hud_layout.py) against the screen. Written to hud_dump.txt in the mod folder.
local DUMP_ROOTS = { "WBP_HUD_Chronicle_MainFlight_000_C" }

function hudDump(why)
    local pc = FindFirstOf("PlayerController")
    local slib = cdo("/Script/UMG.Default__SlateBlueprintLibrary")
    local wll = cdo("/Script/UMG.Default__WidgetLayoutLibrary")
    local out = { "Survival Mode HUD dump (" .. why .. "), Lua " .. VERSION .. ", " .. os.date() }
    pcall(function()
        local vs = wll:GetViewportSize(pc)
        out[#out + 1] = string.format("viewport %.0f x %.0f px, UI scale %.3f", vs.X, vs.Y, wll:GetViewportScale(pc))
    end)
    local function geom(w)
        local ok, s = pcall(function()
            local g = w:GetCachedGeometry()
            local p, a, l = slib:LocalToAbsolute(g, { X = 0, Y = 0 }), slib:GetAbsoluteSize(g), slib:GetLocalSize(g)
            return string.format("abs (%.0f,%.0f) %.0fx%.0f px, local %.0fx%.0f", p.X, p.Y, a.X, a.Y, l.X, l.Y)
        end)
        local okD, dsz = pcall(function() local d = w:GetDesiredSize(); return string.format(", desired %.0fx%.0f", d.X, d.Y) end)
        return (ok and s or "geometry ?") .. (okD and dsz or "")
    end
    local lines = 0
    local function walk(w, depth)
        if lines > 3000 or depth > 16 or not valid(w) then return end
        lines = lines + 1
        local cls = "?"
        pcall(function() cls = w:GetClass():GetFName():ToString() end)
        local name = nameOf(w):match("([^%.:]+)$") or "?"
        local vis = "?"
        pcall(function() vis = tostring(w:GetVisibility()) end)
        local text = ""
        pcall(function() text = "  text='" .. w:GetText():ToString() .. "'" end)
        out[#out + 1] = string.rep("  ", depth) .. cls .. " " .. name .. "  vis " .. vis .. "  " .. geom(w) .. text
        local okT, tree = pcall(function() return w.WidgetTree end)
        if okT and valid(tree) then
            local okR, r = pcall(function() return tree.RootWidget end)
            if okR then walk(r, depth + 1) end
            return
        end
        local okN, n = pcall(function() return w:GetChildrenCount() end)
        if okN and type(n) == "number" then
            for i = 0, n - 1 do
                local okC, c = pcall(function() return w:GetChildAt(i) end)
                if okC then walk(c, depth + 1) end
            end
        end
    end
    local roots = {}
    for _, cn in ipairs(DUMP_ROOTS) do for _, w in ipairs(FindAllOf(cn) or {}) do roots[#roots + 1] = w end end
    if H and valid(H.widget) then roots[#roots + 1] = H.widget end
    for _, w in ipairs(roots) do
        local inVp = "?"
        pcall(function() inVp = tostring(w:IsInViewport()) end)
        out[#out + 1] = "--- " .. nameOf(w) .. "  in viewport: " .. inVp
        walk(w, 0)
    end
    if #roots == 0 then out[#out + 1] = "no HUD widgets found (classes: " .. table.concat(DUMP_ROOTS, ", ") .. ")" end
    local dir = SCRIPT_DIR .. "..\\"
    local f = io.open(dir .. "hud_dump.txt", "w")
    if f then
        f:write(table.concat(out, "\n"), "\n"); f:close()
        log("hud dump (" .. why .. "): " .. lines .. " widgets written to " .. dir .. "hud_dump.txt")
    else
        log("hud dump (" .. why .. "): could not write the file, logging it instead")
        for _, l in ipairs(out) do log("hud dump: " .. l) end
    end
end

-- A random point distance_km from the airfield, inside the combat zone; returns x, y (cm), distance (km), bearing.
-- compass (optional): around that compass bearing from the airfield (within spread degrees; north -Y, east +X, as
-- Mission 22's dummyN0 / dummyS0 sit), for a raid that comes from one direction; the bearing returned is then the
-- compass one too, and a 5th value is true (false: the zone's edge left it a random point, a maths angle). cx, cy
-- (optional): around that point instead of the airfield (the squad director's pincer, around the player).
function spawnPoint(range, compass, spread, cx, cy)
    range = range or CFG.distance_km
    local lo, hi = range[1], range[2]
    local ox, oy = cx or AIRFIELD.X, cy or AIRFIELD.Y
    for try = 1, 30 do
        local d = lo + math.random() * (hi - lo)
        local x, y, b
        if compass and try <= 20 then
            b = (compass + (math.random() * 2 - 1) * (spread or 0)) % 360
            x = ox + d * 100000 * math.sin(math.rad(b))
            y = oy - d * 100000 * math.cos(math.rad(b))
        else
            b = math.random() * 360
            x = ox + d * 100000 * math.cos(math.rad(b))
            y = oy + d * 100000 * math.sin(math.rad(b))
        end
        if math.abs(x - ZONE.X) < ZONE.HALF and math.abs(y - ZONE.Y) < ZONE.HALF then return x, y, d, b, compass ~= nil and try <= 20 end
    end
    return AIRFIELD.X, AIRFIELD.Y + lo * 100000, lo, 90, false
end

-- A compass bearing from the airfield whose raid spawn points (range km out) are inside the combat zone, or nil.
function raidBearing(range)
    local d = (range[1] + range[2]) / 2
    for _ = 1, 24 do
        local b = math.random(0, 359)
        local x = AIRFIELD.X + d * 100000 * math.sin(math.rad(b))
        local y = AIRFIELD.Y - d * 100000 * math.cos(math.rad(b))
        if math.abs(x - ZONE.X) < ZONE.HALF * 0.9 and math.abs(y - ZONE.Y) < ZONE.HALF * 0.9 then return b end
    end
    return nil
end

-- "NORTH-EAST" for a compass bearing.
function compassName(b)
    local names = { "NORTH", "NORTH-EAST", "EAST", "SOUTH-EAST", "SOUTH", "SOUTH-WEST", "WEST", "NORTH-WEST" }
    return names[math.floor(((b or 0) % 360) / 45 + 0.5) % 8 + 1]
end

HEAVY_UNIT = {}
for _, u in ipairs(CFG.airfield.bombers.heavy_units) do HEAVY_UNIT[u] = true end

-- A bomber flight (CFG.airfield.bombers): its event-package orders send it at the airfield only.
local function spawnBomber(unit)
    local b = CFG.airfield.bombers
    local heavy = HEAVY_UNIT[unit]
    local list = heavy and b.heavy or b.aircraft
    local ac = list[math.random(#list)]
    -- strike aircraft spawn on their Survival row (search range + Survival's missile fire control); their behaviour
    -- stays the strike set the world data gave the flight (survival_events.STRIKE_BEHAVIOUR_ROW)
    if not heavy then ac = searchAircraft(ac, levelFor(D.round)) end   -- (the spike's, or the intensity director's)
    local set = SV_SetAircraft(unit, ac)
    -- a raid's bombers from one direction (CFG.airfield.bombers.one_bearing; D.raidBearing, picked in startRound)
    local raid = D.raidBearing and D.raidUnits and D.raidUnits[unit]
    local x, y, dist, bearing = spawnPoint(b.distance_km, raid and D.raidBearing or nil, b.spread_deg)
    -- SV_Spawn's yaw: towards the airfield (spawnPoint's own bearing is a maths angle, a raid's a compass one)
    local yaw = raid and math.deg(math.atan(AIRFIELD.Y - y, AIRFIELD.X - x)) % 360 or (bearing + 180) % 360
    local band = heavy and b.altitude_m or b.strike_altitude_m
    local alt = band[1] + math.random() * (band[2] - band[1])
    spawningUnit, spawningIdx = unit, 0                    -- (each plane's index in the flight: sv_core.lua p.k)
    local r = SV_Spawn(unit, x, y, alt * 100, yaw)
    spawningUnit, spawningIdx = nil, nil
    log(string.format("round %d: bomber flight %s as %s (%s set), %.0f km out at bearing %.0f, %.1f km up: %s", D.round,
        unit, ac, tostring(set), dist, bearing, alt / 1000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    D.heavy = D.heavy or {}
    D.heavy[unit] = HEAVY_UNIT[unit] or nil
    if r > 0 then
        D.up[unit], D.flown[unit] = true, true
        if D.shipStrike and D.shipStrike[unit] then ALLY.strike(unit, D.shipStrike[unit]) end   -- (its own callout)
        if D.bomberCallout ~= D.round and (not D.special or D.special.kind == "amphibious")
            and not (D.shipStrike and D.shipStrike[unit]) then
            D.bomberCallout = D.round
            local t = CFG.hud.text
            if D.strikeAir and D.strikeAir[unit] then hudCallout(t.strike_air, t.strike_air_sub)   -- (a normal round's package)
            elseif raid and b.warn then hudCallout(string.format(t.raid, compassName(D.raidBearing)), string.format(t.raid_sub, D.raidBombers or 0))
            else hudCallout(t.bombers, t.bombers_sub) end
            if TELL then pcall(TELL.say, "raid", TELL.ALL) end      -- (its radio call, every player: P3's tells)
        end
    end
    return r
end

BOMBER_UNIT, BOMBER_INDEX = {}, {}           -- BOMBER_INDEX: the flight's RE_SV_BombRun_NN
for i, u in ipairs(CFG.airfield.bombers.pool) do BOMBER_UNIT[u], BOMBER_INDEX[u] = true, i end

PROBE_OF = {}                           -- probe flight -> "Pkg" / "Rt"
for v, u in pairs(CFG.probe.units) do PROBE_OF[u] = v end

-- CFG.aces: tier `tk`'s squadron for flight `unit` (its wing row, and the lead row of an ace that isn't up already), or
-- nil (no line-up for this tier, or its rows weren't in before this level loaded: the spawner only knows those).
function ACE.flight(unit, tk, level)
    local keys = ACE.roster[tk]
    if not (keys and CFG.aces.enabled) then return nil end
    D.aceOf = D.aceOf or {}
    D.aceOf[unit] = nil                                         -- what this flight flew last time is down or recycled
    local opts = {}
    for _, k in ipairs(keys) do if SR.usable[ACE.row(tk, k, "w")] then opts[#opts + 1] = k end end
    if #opts == 0 then return nil end
    local k = opts[math.random(#opts)]
    local f, id = { wing = searchAircraft(ACE.row(tk, k, "w"), level), tier = tk, key = k }, tk .. "_" .. k
    for u, a in pairs(D.aceOf) do
        if a == id and (SV_UnitAlive(u) or 0) > 0 then return f end   -- that ace is up: wingmen only
    end
    if SR.usable[ACE.row(tk, k, "l")] then
        f.lead, f.id, D.aceOf[unit] = searchAircraft(ACE.row(tk, k, "l"), level), id, id
    end
    return f
end

-- The airframe (a DT_SV_NpcMission row) a fighter flight of tier `tier` flies this round (CFG.aircraft, CFG.variety):
-- the round-1 pool plus the airframes whose round has come (only those whose Survival rows were in before the level
-- loaded: SR.usable), types flown less this run picked more often, and from the Mercenary tier on signature_share of
-- flights on the tier's own types. role (a fighter role, CFG.roles; nil: any): only the role's own airframes
-- (CFG.roles.aircraft) of that list, a signature type only when it's one of them; none unlocked yet (the Skirmishers'
-- join at rounds 4 / 7 / 9): its fallback role's, else the whole list (the critic's gap fill). Returns the row and how
-- it was picked ("pool" / "signature" / the role's).
function pickAircraft(tier, role)
    local v = CFG.variety or {}
    local list, how = {}, "pool"
    local function roleSet(r)                          -- the airframes role r flies (a set), or nil for any
        local l = r and CFG.roles and type(CFG.roles.aircraft) == "table" and CFG.roles.aircraft[r]
        if type(l) ~= "table" then return nil end
        local s = {}
        for _, a in ipairs(l) do s[a] = true end
        return s
    end
    local own = roleSet(role)
    if v.enabled and tier and tier.name and v.signature and not D.roundTier and math.random() < (v.signature_share or 0) then
        for _, a in ipairs(v.signature[tier.name:lower()] or {}) do
            if SR.usable[a] and (not own or own[a]) then list[#list + 1] = a end
        end
        if #list > 0 then how = "signature" end
    end
    if #list == 0 then
        for _, a in ipairs(CFG.aircraft) do list[#list + 1] = a end
        if v.enabled then
            for _, e in ipairs(v.late or {}) do if D.round >= e[2] and SR.usable[e[1]] then list[#list + 1] = e[1] end end
        end
        if own then                                   -- a role's flight: its own airframes of what's unlocked
            local function keep(s)
                local t = {}
                for _, a in ipairs(list) do if s and s[a] then t[#t + 1] = a end end
                return t
            end
            local mine = keep(own)
            if #mine > 0 then
                list, how = mine, role
            else
                local fb = CFG.roles.fallback and CFG.roles.fallback[role]
                local theirs = (type(fb) == "string" and fb ~= role) and keep(roleSet(fb)) or {}
                how = #theirs > 0 and (role .. ", " .. fb .. "'s airframes") or (role .. ", any airframe")
                if #theirs > 0 then list = theirs end
                D.roleNoAc = D.roleNoAc or {}
                if D.roleNoAc[role] ~= D.round then
                    D.roleNoAc[role] = D.round
                    log(string.format("roles: no %s airframe yet in round %d; its flights fly %s", role, D.round,
                        #theirs > 0 and (fb .. "'s") or "the whole pool's"))
                end
            end
        end
    end
    RUN.seenAc = RUN.seenAc or {}
    local pick = list[math.random(#list)]
    if v.enabled and v.unseen and #list > 1 then         -- a type flown n times this run: weight 1 / (1 + n)
        local total, w = 0, {}
        for i, a in ipairs(list) do w[i] = 1 / (1 + (RUN.seenAc[a] or 0)); total = total + w[i] end
        local r = math.random() * total
        for i, a in ipairs(list) do r = r - w[i]; if r <= 0 then pick = a; break end end
    end
    RUN.seenAc[pick] = (RUN.seenAc[pick] or 0) + 1
    return pick, how
end

-- maxLevel (the dev key Ctrl+6): the top skill tier's squadron (its ace leading) on the top fire-control level,
-- whatever the round
function spawnFlight(unit, maxLevel)
    if BOMBER_UNIT[unit] then return spawnBomber(unit) end
    local ti = CFG.tiers.enabled and (maxLevel and #CFG.tiers.list or D.roundTier or TIER.pick(D.round)) or nil
    local tier = ti and CFG.tiers.list[ti] or {}
    D.flightTier = D.flightTier or {}
    D.flightTier[unit] = ti
    local topSpike = CFG.spikes.enabled and math.min(#CFG.spikes.levels, #SPIKE_SUFFIX) or 0
    -- (the round's spike level, or the intensity director's under it: CFG.intensity.level; the tier's fcs the floor)
    local fcsLevel = math.max(maxLevel and topSpike or levelFor(D.round), tier.fcs or 0)
    local role = ROLE.flight(unit)                    -- (its fighter role, CFG.roles: nil with roles off)
    D.flightRole = D.flightRole or {}
    D.flightRole[unit] = role
    local base, how = pickAircraft(tier, role)
    local ac = searchAircraft(base, fcsLevel)
    local ace = (D.roundTier or maxLevel) and tier.name and ACE.flight(unit, tier.name:lower(), fcsLevel)   -- (ace rounds only)
    if ace then ac, how = ace.wing, "ace squadron" end
    -- the round's jammer (CFG.jammer; D.jammerUnit, picked in startRound): its lead an EA-18G
    local jam = D.jammerUnit == unit and not ace and SR.usable[CFG.jammer.aircraft] and searchAircraft(CFG.jammer.aircraft, fcsLevel)
    local pv = PROBE_OF[unit]
    if pv then                                     -- its behaviour was built from the probe row at level load
        ac = PROBE_MISSION_ROW[pv]
        log(string.format("probe: round %d's first flight %s flies %s (%s script)", D.round, unit, ac,
            pv == "Pkg" and "package" or "run-time"))
    end
    local set = SV_SetAircraft(unit, ac)
    if ace and ace.lead then SV_SetAircraft(unit, ace.lead, 0) end        -- the first aircraft: the ace
    if jam then SV_SetAircraft(unit, jam, 0) end                           -- the first aircraft: the jammer
    if type(SV_SetLevel) == "function" then SV_SetLevel(unit, (tier.ai_level or 2) * 100) end   -- every spawn: descs are reused
    local x, y, dist, bearing = spawnPoint()
    local yaw = (bearing + 180) % 360                                          -- facing the airfield
    local pin = nil                         -- (a pincer wave's flight: its side's bearing, P2's director, sv_director.lua)
    if DIR and DIR.spawnAt then
        local okPn, pn = pcall(DIR.spawnAt, unit)
        if okPn then pin = pn else log("director: pincer error " .. tostring(pn)) end
    end
    if pin then x, y, dist, bearing, yaw = pin.x, pin.y, pin.d, pin.b, pin.yaw end
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    if role == "lancer" then                          -- (the Lancers come from above: CFG.roles.lancer, within their band)
        alt = math.min(alt + (tonumber(CFG.roles.lancer and CFG.roles.lancer.alt_add_m) or 0), ROLE.LANCER_TOP_M - 500)
        -- (above your usual height against a player who stays high: P6's learning layer, sv_stats.lua PROF.lancerAlt)
        local okHi, hi = true, nil
        if PROF and PROF.lancerAlt then okHi, hi = pcall(PROF.lancerAlt) end
        if okHi and type(hi) == "number" and hi > alt then alt = math.min(hi, ROLE.LANCER_TOP_M - 500) end
    end
    -- a lead on its own row (the ace's, the jammer's): its airframe, for the spawn index's check (sv_core.lua leadCheck)
    D.leadRow = D.leadRow or {}
    D.leadRow[unit] = (ace and ace.lead and { row = ace.lead, code = ace.key }) or (jam and { row = jam, code = "e18g" }) or nil
    D.flightRow = D.flightRow or {}
    D.flightRow[unit] = ac                         -- (its wings' row: the director's salvo checks its missile slot, SR.mslSlot)
    spawningUnit, spawningIdx = unit, 0                                       -- (each plane's index in the flight: p.k)
    local r = SV_Spawn(unit, x, y, alt * 100, yaw)
    spawningUnit, spawningIdx = nil, nil
    log(string.format("round %d: %s%s%s as %s (%s, %s set, %s)%s, %.0f km out at bearing %.0f%s, %.1f km up: %s", D.round, unit,
        role and (" [" .. role .. "]") or "", D.flown[unit] and " (flown before, recycled)" or "", ac, how, tostring(set), tier.name or "no tier",
        jam and (", led by the jammer " .. jam) or "", dist, bearing, pin and (" (compass) from " .. (pin.centre or "the pincer's centre") .. ", a pincer side") or "",
        alt / 1000, r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r > 0 and role then pcall(ROLE.spawned, unit, role, r, ace) end   -- (its tell, the Wolf trap's hold: below)
    if r > 0 and DIR and DIR.spawned then pcall(DIR.spawned, unit, role, r, ace) end   -- (the director's top cover, regroup)
    if jam and r > 0 then
        D.jammer = { unit = unit, at = D.now }
        local t = CFG.hud.text
        hudCallout(t.jammer, t.jammer_sub)
        if TELL then pcall(TELL.say, "jammer", TELL.ALL) end        -- (its radio call, every player: P3's tells)
    elseif D.jammerUnit == unit then
        D.jammerUnit = nil                                                -- (it didn't come: no jammer this round)
    end
    if r > 0 then
        D.up[unit], D.flown[unit] = true, true
        if D.escortUnits and D.escortUnits[unit] then            -- a raid's escort: over the airfield, once its orders are in
            queueEvent(D.now + CFG.orders_check_s + 1, string.format("RE_SV_Escort_%02d", poolIndex(unit)), unit .. " escorts the raid")
        end
        D.aceSquad = D.aceSquad or {}
        D.aceSquad[unit] = ace and true or nil                -- (the leaderboard's ace squadron kills)
        D.orders = D.orders or {}
        D.orders[unit] = { at = D.now + CFG.orders_check_s, tries = 0 }       -- ordersTick checks it got them
        if ace then
            local c = CFG.aces[ace.tier] or {}
            local name = ace.lead and tostring(c[ace.key] or ace.key)
            log(string.format("aces: %s is %s squadron (%s)%s", unit, tostring(c.squadron), ace.key,
                name and (", led by " .. name .. " (" .. ace.lead .. ")") or ", no ace (already up)"))
            D.aceSaid = D.aceSaid or {}
            if name and CFG.aces.callout and not D.aceSaid[ace.id] then
                D.aceSaid[ace.id] = true
                local t = CFG.hud.text
                hudCallout(string.format(t.ace, name:upper()), string.format(t.ace_sub, tostring(c.squadron):upper(), tier.name:upper()))
            end
        end
    end
    return r
end

function shuffled(t)
    for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
    return t
end

---------------------------------------------------------------------------------------------------- fighter roles
-- The fighter roles (CFG.roles, behaviour roadmap P1; tools/re/BEHAVIOUR_DIRECTOR.md unit 5; build data ROLE in
-- sv_config.lua): what this level has, the round's draw by role, each role flight's tell and the Wolf trap's hold.
-- The host's (or solo): a joiner's copies fly the host's picks, and roundsTick (which calls all of this) is the host's.
do
-- ROLE.live: each role's state in this level, from the rows that were in before it loaded (rolesSetup, sv_rows.lua; the
-- behaviour build and the spawner only know those): true (its set), "duelist" (its set wasn't made: its flights fly the
-- fighters' set, drawn and armed as duelists) or false (no row: its flights sit out). nil: roles off (or no level yet):
-- every flight drawn and armed as before roles.
function ROLE.levelLoad()
    ROLE.live = nil
    local c = CFG.roles
    if not (c and c.enabled) then log("roles: off; every fighter flight flies the fighters' set, drawn as before"); return end
    local live, parts = { duelist = true }, {}
    for _, r in ipairs(ROLE.LIST) do
        if r ~= "duelist" then
            local x = RS and RS.ready and RS.ready[r]
            local w, wset = x, ROLE.SETS[r]             -- (a Wolf flight's trap row too)
            if r == "wolf" then w, wset = RS.ready.wolf_wing, ROLE.SETS.wolf_wing end
            if not (x and w) then live[r] = false
            elseif x.set == ROLE.SETS[r] and w.set == wset then live[r] = true      -- (its rows fly its own sets)
            else live[r] = "duelist" end
            parts[#parts + 1] = string.format("%s %s", r, live[r] == true and ROLE.SETS[r]
                or (live[r] and "the fighters' set (its own wasn't made)") or "sits out (no behaviour row)")
        end
    end
    ROLE.live = live
    log("roles: at level load " .. table.concat(parts, ", "))
end

-- Pool flight `unit`'s role this level (nil: roles off, not a pool fighter, a probe flight or its group sits out).
function ROLE.flight(unit)
    local live = ROLE.live
    local r = live and ROLE.of[unit]
    if not r or PROBE_OF[unit] then return nil end
    if live[r] == true then return r end
    return live[r] == "duelist" and "duelist" or nil
end

-- Flight `unit` sits out this level (its role's behaviour row wasn't in when it loaded: what its desc would build is
-- unknown, so it never flies, as the probe flights): the role-blind picks (spares, a special's refill, Ctrl+6) skip it.
function ROLE.sitsOut(unit)
    local live = ROLE.live
    local r = live and ROLE.of[unit]
    return (r and live[r] == false) and true or false
end

-- Each role's flights this level ({ role = { units } }; a role flying the fighters' set counts as duelists).
function ROLE.groups()
    local g = {}
    for _, r in ipairs(ROLE.LIST) do g[r] = {} end
    for _, u in ipairs(CFG.pool) do
        local r = ROLE.flight(u)
        if r then g[r][#g[r] + 1] = u end
    end
    return g
end

-- Of `units` (a role's group: a few flights), the free ones (not up, of a size this round allows: CFG.squadrons) whose
-- aircraft add up to `want` exactly, flights flown before preferred (as pickFlights: the spawner recycles them); none
-- adds up: the most under it. pickFlights' own random sizes can strand a remainder in a group this small (round 35's
-- duelist 18 as 2 + 2 + 6 + 6, its 4-ships too big for the 2 left: 1 round in 5 came up short). Groups of more than
-- 12 flights: nil (pickFlights then).
local function exactFlights(units, want)
    local allowed, free = {}, {}
    for _, q in ipairs(CFG.squadrons) do if D.round >= q.from_round then allowed[q.size] = true end end
    for _, u in ipairs(units) do if allowed[flightSize(u)] and not D.up[u] then free[#free + 1] = u end end
    if #free > 12 then return nil end
    local sols, best, bestSum, bestFlown = {}, {}, 0, -1
    for mask = 1, (1 << #free) - 1 do
        local sum, flown, sub = 0, 0, {}
        for i = 1, #free do
            if mask & (1 << (i - 1)) ~= 0 then
                sum = sum + flightSize(free[i]); sub[#sub + 1] = free[i]
                if D.flown[free[i]] then flown = flown + 1 end
            end
        end
        if sum == want then
            if flown > bestFlown then sols, bestFlown = {}, flown end
            if flown == bestFlown then sols[#sols + 1] = sub end
        elseif sum < want and sum > bestSum then best, bestSum = sub, sum end
    end
    if #sols > 0 then return sols[math.random(#sols)] end
    return best
end

-- A round's fighters by its role mix (ROLE.mixFor: CFG.roles mix or, ace true, ace_mix): each role's share in whole
-- 2-ships (ROLE.quotas) from its own flights (exactFlights, then through `pick`: startRound's, pickFlights with the
-- round's taken flights skipped); what a role's flights can't field comes from the rest. Returns the flights
-- (shuffled, so each wave asks different questions) and their aircraft, as pick does.
function ROLE.pickRound(nWant, pick, ace)
    local w, band = ROLE.mixFor(D.round, ace)
    -- (not an ace round's: the learning layer's role weights, P6: your habits, sv_stats.lua PROF.roleW; a role the band
    -- has no share for stays out)
    local hw, habits = nil, false
    if not ace and PROF and PROF.roleW then
        local okW, x = pcall(PROF.roleW)
        if okW and type(x) == "table" then hw = x end
    end
    for _, r in ipairs(ROLE.LIST) do
        local x = hw and tonumber(hw[r]) or 1
        if x ~= 1 and (w[r] or 0) > 0 then w[r], habits = w[r] * x, true end
    end
    local groups = ROLE.groups()
    for _, r in ipairs(ROLE.LIST) do if #groups[r] == 0 then w[r] = 0 end end
    local q = ROLE.quotas(nWant, w)
    local out, got, parts, short = {}, 0, {}, {}
    local by = {}
    for _, r in ipairs(ROLE.LIST) do
        local n = 0
        if q[r] > 0 then
            local f
            local sub = exactFlights(groups[r], q[r])      -- (its flights adding up to the share; pick takes them all)
            local subN = 0
            for _, u in ipairs(sub or {}) do subN = subN + flightSize(u) end
            f, n = pick(sub or groups[r], sub and subN or q[r])
            for _, u in ipairs(f) do out[#out + 1] = u end
            if n < q[r] then short[#short + 1] = string.format("%s %d of %d", r, n, q[r]) end
        end
        got, by[r] = got + n, n
    end
    local fill = ""
    if nWant - got >= 2 then                          -- (a group short: the rest of the pool, any role)
        local all = {}
        for _, r in ipairs(ROLE.LIST) do for _, u in ipairs(groups[r]) do all[#all + 1] = u end end
        local f, n = pick(all, nWant - got)
        local from = {}
        for _, u in ipairs(f) do
            out[#out + 1] = u
            local r = ROLE.flight(u)
            by[r] = (by[r] or 0) + flightSize(u)
            from[r] = (from[r] or 0) + flightSize(u)
        end
        got = got + n
        local ft = {}
        for _, r in ipairs(ROLE.LIST) do if from[r] then ft[#ft + 1] = r .. " " .. from[r] end end
        if n > 0 then fill = "; filled from " .. table.concat(ft, ", ") end
    end
    for _, r in ipairs(ROLE.LIST) do parts[#parts + 1] = string.format("%s %d", r, by[r] or 0) end
    local wt = {}
    for _, r in ipairs(ROLE.LIST) do wt[#wt + 1] = string.format("%s %.2f", r, w[r] or 0) end
    log(string.format("roles: round %d (%s%s: %s): %d of %d aircraft: %s%s%s", D.round,
        band == "ace" and "an ace round's mix" or band and ("the mix from round " .. band) or "no mix band: duelists",
        habits and ", weighed by your habits" or "", table.concat(wt, ", "), got, nWant, table.concat(parts, ", "),
        #short > 0 and ("; short: " .. table.concat(short, ", ")) or "", fill))
    return shuffled(out), got
end

-- The round's jammer may lead flight `unit` (its EA-18G on object 0: CFG.roles.jammer's roles, so it never takes a Wolf
-- bait's drag set or a Lancer's; the critic's gap fill). Any flight with roles off.
function ROLE.jammerOk(unit)
    local r = ROLE.flight(unit)
    if not (ROLE.live and r) then return true end
    for _, x in ipairs(CFG.roles.jammer or {}) do if x == r then return true end end
    return false
end

-- Flight `unit` flies a role set of its own (a Lancer, Wolf or Skirmisher flight, not an ace squadron's: that keeps its
-- tier's levers). A skill tier's no_provoke and moves (CFG.aces.flight; from round 28 every ordinary flight is Reaper
-- tier, TIER.pick) leave it alone (ACE.hunt, ACE.movesTick; U5's review): no_provoke keeps a plane out of its Provoke
-- slot (no LA_SV_LancerBreak, no LA_SV_WolfDrag, no Skirmisher defence), and a reversal (RE_SV_AceTurn_NN, LastTGT on
-- every plane of the flight) turns a Lancer with you and a held Wolf trap onto you. False for duelists and roles off.
function ROLE.ownSet(unit)
    local r = unit and ROLE.flight(unit)
    return r ~= nil and r ~= "duelist" and not (D and D.aceSquad and D.aceSquad[unit])
end

-- A role flight is up (spawnFlight, inside roundsTick: n planes): the round's first Lancer and first Skirmisher flight
-- call themselves out to every player (CFG.roles.tells; P3's tells "lancer" / "skirm", HUD only), a Wolf flight's trap
-- is held once its orders are in (WOLF). An ace squadron in a role flight neither calls out nor holds.
function ROLE.spawned(unit, role, n, ace)
    local c = CFG.roles
    if ace then return end
    if (role == "lancer" or role == "skirm") and c.tells and TELL then
        D.roleSaid = D.roleSaid or {}
        if D.roleSaid[role] ~= D.round then
            D.roleSaid[role] = D.round
            pcall(TELL.say, role, TELL.ALL)
        end
    end
    if role == "wolf" then WOLF.spawned(unit, n, D.now) end
end
end

-- The Wolf trap (CFG.roles.wolf, P1; the critic's gap fill: "per-object engagement hold, using the stock by-object
-- form"). A Wolf flight is bait and trap pairs: its even planes (the bait, NLID_SV_WolfLead) attack and drag you when
-- tailed; its odd planes (the trap, ROLE.wolfHeld, NLID_SV_WolfWing) are held at engagement None (RE_SV_WolfHold_<NN><L>,
-- one object each: tools/survival_events.py build_wolf) hold_after_s after their flight's orders are seen in (SV_Up_NN:
-- the appearance's own orders come 2 s after it spawns and would undo an earlier hold, hard rule 26), and fly with their
-- formation [I]. Freed (RE_SV_WolfFree_<NN><L>: their appearance's orders on that object) when: hold_max_s pass, one is
-- hit by you (free_on_hit, that one), its own bait (the plane before it, k - 1: free_on_bait_down) goes down (that one;
-- the lead, object 0, frees them all), or the squad director springs it (P2: WOLF.free(unit, why, true) adds
-- RE_SV_WolfTurn_<NN><L>, LastTGT onto the player). A held plane shot down is just dropped. Your DECOY stands the whole
-- flight down (RE_SV_Decoy_NN) until its end: nothing is freed or turned inside it (a WolfFree would send that plane back
-- in early, and to the joiners' copies; the reasons still stand after it, so those releases come then), and its end
-- (RE_SV_DecoyEnd_NN, a unit-wide order) frees them all: the ones still held are held again rehold_s later (U5's
-- review). Hunts (ALLY.tick's, co-op's) and escort duty leave a holding flight alone (WOLF.holding). The host's (or solo):
-- WOLF.tick runs in roundsTick; the holds and frees are forwarded to co-op joiners (their copies hold too), the turn isn't
-- (LastTGT steers to the host). Untested in game: a per-object engagement order on a pool plane, what a later unit-wide
-- order does to a per-object None (BEHAVIOUR_NATIVE_LOGIC 8.5: every engagement order rewrites the permission bytes).
WOLF = {}
do
local function cfg() return (CFG.roles and CFG.roles.wolf) or {} end
local function evName(kind, unit, k) return string.format("RE_SV_Wolf%s_%02d%s", kind, poolIndex(unit), string.char(65 + k)) end
local function fire(name)
    local r = type(SV_Event) == "function" and SV_Event(name) or -5
    return r == 1, r
end
local function keyList(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
end
-- the time your DECOY on flight `unit` ends, while it stands the flight down (sv_tactical.lua TAC.decoyed), else nil
local function decoyEnd(unit, now)
    if not (TAC and TAC.decoyed and TAC.decoyed(unit, now)) then return nil end
    return D.decoyed and D.decoyed[unit] or now
end

-- flight `unit` (n planes) is up: its trap's objects, to hold once its orders are in
function WOLF.spawned(unit, n, now)
    D.wolf = D.wolf or {}
    D.wolf[unit] = nil
    local c = cfg()
    if not (c.hold and poolIndex(unit) and now) then return end
    local keys = {}
    for k = 0, (n or 0) - 1 do if ROLE.wolfHeld(k) then keys[#keys + 1] = k end end
    if #keys == 0 then return end
    D.wolf[unit] = { at = now, keys = keys, held = {}, state = "pending" }
end

-- Whether any of flight `unit`'s trap is held (or about to be): hunts and escort duty leave it alone.
function WOLF.holding(unit)
    local w = D and D.wolf and D.wolf[unit]
    return w ~= nil and (w.state == "pending" or next(w.held) ~= nil)
end

local function hold(unit, w, keys, why)
    local fired, failed = {}, {}
    for _, k in ipairs(keys) do
        local ev = evName("Hold", unit, k)
        local ok, r = fire(ev)
        if ok then w.held[k] = true; fired[#fired + 1] = string.char(65 + k)
        else failed[#failed + 1] = ev .. " " .. (SV_ERR[r] or tostring(r)) end
    end
    log(string.format("roles: %s (wolf) trap %s: %s%s", unit, why,
        #fired > 0 and ("held " .. table.concat(fired, ", ")) or "none held",
        #failed > 0 and (" (not fired: " .. table.concat(failed, ", ") .. ")") or ""))
end

-- Frees flight `unit`'s held trap (only: that object alone) and, with turn, sends each onto the player (LastTGT): the
-- squad director's spring (P2) calls it with turn. Returns how many were freed: 0 while your DECOY stands the flight
-- down (nothing fired, the trap stays held: call again after; its end frees the flight and the trap is held again).
-- now: the round clock (D.now when nil).
function WOLF.free(unit, why, turn, only, now)
    local w = D and D.wolf and D.wolf[unit]
    if not w then return 0 end
    now = now or D.now
    local dec = decoyEnd(unit, now)
    if dec then
        if w.decoyNote ~= dec then                       -- (once a decoy)
            w.decoyNote = dec
            log(string.format("roles: %s (wolf) trap kept (%s): your decoy stands its flight down for %.0f s more%s", unit,
                tostring(why), math.max(0, dec - (now or dec)), turn and "; not sprung" or ""))
        end
        return 0
    end
    local done = {}
    for _, k in ipairs(keyList(w.held)) do
        if only == nil or only == k then
            fire(evName("Free", unit, k))
            if turn then fire(evName("Turn", unit, k)) end
            w.held[k] = nil
            done[#done + 1] = string.char(65 + k)
        end
    end
    if #done > 0 then
        log(string.format("roles: %s (wolf) trap freed (%s): %s%s", unit, why, table.concat(done, ", "),
            turn and ", turned onto the player" or ""))
    end
    if not next(w.held) and w.state == "held" then w.state = "free" end
    return #done
end

-- Every 250 ms from roundsTick: the holds come in, the releases (once a second).
function WOLF.tick(now)
    local W = D and D.wolf
    if not (W and next(W) and now) then return end
    local c = cfg()
    local flags
    for unit, w in pairs(W) do
        if SV_UnitAlive(unit) <= 0 then
            W[unit] = nil                                   -- (down, or its spawn didn't come: it's recycled next time)
        elseif w.state == "pending" then
            if not w.upAt then
                flags = flags or svFlags() or {}
                if (flags[string.format("SV_Up_%02d", poolIndex(unit))] or 0) >= 1 then w.upAt = now end
            end
            if w.upAt and now >= w.upAt + (tonumber(c.hold_after_s) or 3) and not playerOnAirfield() then
                w.state, w.heldAt = "held", now
                hold(unit, w, w.keys, string.format("%.0f s after its orders", now - w.upAt))
                if not next(w.held) then W[unit] = nil end   -- (no event fired: an older container)
            elseif not w.upAt and now - w.at > 30 then
                log("roles: " .. unit .. " (wolf) never got its orders; its trap isn't held")
                W[unit] = nil
            end
        elseif w.state == "held" and next(w.held) and now >= (w.checkAt or 0) then
            w.checkAt = now + 1
            -- this spawn's planes by index (a recycled flight's earlier planes stay on the list, down, until the round's
            -- end: born before this spawn); a held one shot down is dropped (nothing to free); the held ones hit
            local mine, hits, gone = {}, {}, {}
            for _, p in ipairs(planes) do
                if p.unit == unit and p.k and (p.born == nil or p.born >= w.at) then
                    mine[p.k] = p
                    if w.held[p.k] then
                        if p.down then w.held[p.k] = nil; gone[#gone + 1] = string.char(65 + p.k)
                        -- (you, or in co-op a joiner: the host's KILL.side calls a stand-in's damage "wingmate")
                        elseif p.dmg and (p.dmg.you or 0) + (p.dmg.wingmate or 0) > 0 then hits[#hits + 1] = p.k end
                    end
                end
            end
            if #gone > 0 then log(string.format("roles: %s (wolf) trap: %s down while held", unit, table.concat(gone, ", "))) end
            if not next(w.held) then
                w.state = "free"
            elseif not decoyEnd(unit, now) then               -- (your decoy: nothing released inside it; after it, then)
                if now - w.heldAt >= (tonumber(c.hold_max_s) or 60) then
                    WOLF.free(unit, string.format("held %.0f s", now - w.heldAt), false, nil, now)
                elseif c.free_on_bait_down and mine[0] and mine[0].down then
                    WOLF.free(unit, "its lead, bait A, is down", false, nil, now)     -- (the flight's lead: all of them)
                else
                    if c.free_on_bait_down then                -- (each held plane's own bait: the plane before it)
                        for _, k in ipairs(keyList(w.held)) do
                            local b = mine[k - 1]
                            if b and b.down then WOLF.free(unit, "its bait " .. string.char(64 + k) .. " is down", false, k, now) end
                        end
                    end
                    if c.free_on_hit then
                        for _, k in ipairs(hits) do if w.held[k] then WOLF.free(unit, "you hit it", false, k, now) end end
                    end
                end
                -- a unit-wide order after the hold (your DECOY's end fires its flight's orders): held again
                local dec = D.decoyed and D.decoyed[unit]
                if dec and dec ~= w.decoySeen and dec > w.heldAt and now >= dec + (tonumber(c.rehold_s) or 1) and next(w.held) then
                    w.decoySeen = dec
                    hold(unit, w, keyList(w.held), "again after your decoy")
                end
            end
        end
    end
end
end

-- A round's flights: those that have flown before come first (the spawner recycles them, which keeps the game's unit
-- list short); the rest are spares, fresh ones first, for a flight that fails to spawn.
-- A flight's aircraft count (tools/survival_events.py flight_size: bombers by table, fighters by their _AirN suffix).
function flightSize(unit)
    return CFG.airfield.bombers.sizes[unit] or ({ ["0"] = 2, ["1"] = 4, ["2"] = 6 })[unit:sub(-1)] or 2
end

-- Up to `budget` aircraft from `units` (free ones only), in squadrons of the sizes allowed this round, flights that
-- have flown before first within a size (the spawner recycles them, which keeps the game's unit list short).
-- Returns the flights and the aircraft they hold.
function pickFlights(units, budget, skip)
    local allowed, bySize = {}, {}
    for _, q in ipairs(CFG.squadrons) do if D.round >= q.from_round then allowed[q.size] = true end end
    for _, u in ipairs(units) do
        local n = flightSize(u)
        if allowed[n] and not D.up[u] and not (skip and skip(u)) then
            bySize[n] = bySize[n] or { flown = {}, fresh = {} }
            local t = D.flown[u] and bySize[n].flown or bySize[n].fresh
            t[#t + 1] = u
        end
    end
    for _, b in pairs(bySize) do shuffled(b.flown); shuffled(b.fresh) end
    local out, left = {}, budget
    while left >= 2 do
        local options = {}
        for n, b in pairs(bySize) do if n <= left and #b.flown + #b.fresh > 0 then options[#options + 1] = n end end
        if #options == 0 then break end
        local b = bySize[options[math.random(#options)]]
        out[#out + 1] = table.remove(#b.flown > 0 and b.flown or b.fresh)
        left = left - flightSize(out[#out])
    end
    return out, budget - left
end

---------------------------------------------------------------------------------------------------- special rounds
-- A special that's switched off (CFG.specials.<kind>.enabled = false) never comes, whatever the rotation says.
function specialOn(kind)
    local c = CFG.specials[kind]
    return SPC.kinds[kind] ~= nil and not (type(c) == "table" and c.enabled == false)
end

-- The special round `round` is (CFG.specials), or nil for a normal round.
function specialFor(round)
    local sp = CFG.specials
    local sx = SETUP and SETUP.specialsX and SETUP.specialsX() or 1   -- (the menu's SPECIAL ROUNDS, sv_menu.lua: 0 = off)
    if sx <= 0 then return nil end
    if sp.enabled and sp.random and #sp.rotation > 0 then
        RUN.specialPick = RUN.specialPick or {}
        local pick = RUN.specialPick
        if pick[round] == nil then
            local kind, early = false, sp.early
            -- each special at most once in cooldown_rounds (user, 2026-10-23: "Each Special Round can only Spawn Once
            -- Every 10 rounds"): one that started in round r can't come again before r + cooldown_rounds
            local function ready(k)
                local last = RUN.specialAt and RUN.specialAt[k]
                return specialOn(k) and (not last or round - last >= (sp.cooldown_rounds or 0))
            end
            -- (in the early window only the early special comes: user, 2026-10-23, "between 2 and 6 ... I only
            -- wanted the Shuttle Launch to ever do"; the others start after it)
            local inEarly = early and early.kind and round >= (early.from or 0) and round <= (early.to or -1)
            if inEarly then
                if not pick[round - 1] and RUN.lastSpecial ~= early.kind and ready(early.kind) and math.random() < math.min(0.9, (early.chance or 0) * sx) then
                    kind = early.kind
                    RUN.lastSpecial = kind
                end
            elseif round >= sp.first and not pick[round - 1] and math.random() < math.min(0.9, sp.chance * sx) then
                local choices = {}
                for _, k in ipairs(sp.rotation) do
                    if (k ~= RUN.lastSpecial or #sp.rotation == 1) and ready(k) then choices[#choices + 1] = k end
                end
                if #choices > 0 then                       -- (every one cooling down: a normal round)
                    kind = choices[math.random(#choices)]
                    RUN.lastSpecial = kind
                end
            end
            pick[round] = kind
            if kind then log(string.format("specials: round %d will be %s", round, kind)) end
        end
        return pick[round] or nil
    end
    local every = math.max(1, math.floor(sp.every))
    if not sp.enabled or #sp.rotation == 0 or round < sp.first or (round - sp.first) % every ~= 0 then return nil end
    local kind = sp.rotation[((round - sp.first) // every) % #sp.rotation + 1]
    return specialOn(kind) and kind or nil
end

-- A pool flight's index in tools/survival_events.py POOL (its SV_Up_NN flag and its RE_SV_*_NN events), or nil.
function poolIndex(unit)
    local n, k = tostring(unit):match("^ERA_Unit_(%d+)_Dep_Air(%d)$")
    return n and (tonumber(n) - 1) * 3 + tonumber(k) + 1
end

-- Comona Defense: the pad (once a run: its guns and SAMs stay up between specials) and the shuttle, both where the
-- world data puts them (SV_Spawn without a position). The shuttle's appearance starts the event package's countdown.
function spawnShuttle()
    local c = CFG.specials.shuttle
    pcall(SPC.shuttlePadBack)                             -- (the pad hidden after the last one: its units are still up)
    for _, u in ipairs({ c.dummies, c.pad_allies and c.pad or nil }) do
        if u and SV_UnitAlive(u) <= 0 then
            local p = SV_Spawn(u)
            log("special: pad " .. u .. ": " .. (p > 0 and (p .. " objects up") or ("not spawned (" .. (SV_ERR[p] or tostring(p)) .. ")")))
        end
    end
    SHUTTLE.obj = nil
    spawningUnit = c.unit
    local r = SV_Spawn(c.unit)
    spawningUnit = nil
    log("special: shuttle " .. c.unit .. ": " .. (r > 0 and "on the pad" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r <= 0 then D.special = nil; return r end            -- a normal round, then
    D.special.state, D.special.at = "countdown", D.now
    D.shuttleClock = { cd = 0, fired = 0, at = D.now, s = D.special }
    return r
end

-- The shuttle's health in % (its actor's HealthInternal is health x 10), or nil when it can't be read.
function shuttleHealth()                  -- the local declared with SHUTTLE
    if not valid(SHUTTLE.obj) then
        SHUTTLE.obj = nil
        if D and D.special and D.now and (SHUTTLE.lookAt or -100) + 2 <= D.now then
            SHUTTLE.lookAt = D.now
            local o = FindFirstOf("BP_OP0057_sstb_CP_C")
            if valid(o) and not nameOf(o):find("Default__", 1, true) then SHUTTLE.obj = o end
        end
        if not SHUTTLE.obj then return nil end
    end
    local ok, pct = pcall(function()
        local max = SHUTTLE.obj.MaxHealth
        return max > 0 and math.max(0, math.floor(SHUTTLE.obj.HealthInternal / 10 / max * 100 + 0.5)) or nil
    end)
    return ok and pct or nil
end
