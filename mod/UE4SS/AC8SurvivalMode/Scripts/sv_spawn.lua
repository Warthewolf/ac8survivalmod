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
-- compass one too.
function spawnPoint(range, compass, spread)
    range = range or CFG.distance_km
    local lo, hi = range[1], range[2]
    for try = 1, 30 do
        local d = lo + math.random() * (hi - lo)
        local x, y, b
        if compass and try <= 20 then
            b = (compass + (math.random() * 2 - 1) * (spread or 0)) % 360
            x = AIRFIELD.X + d * 100000 * math.sin(math.rad(b))
            y = AIRFIELD.Y - d * 100000 * math.cos(math.rad(b))
        else
            b = math.random() * 360
            x = AIRFIELD.X + d * 100000 * math.cos(math.rad(b))
            y = AIRFIELD.Y + d * 100000 * math.sin(math.rad(b))
        end
        if math.abs(x - ZONE.X) < ZONE.HALF and math.abs(y - ZONE.Y) < ZONE.HALF then return x, y, d, b end
    end
    return AIRFIELD.X, AIRFIELD.Y + lo * 100000, lo, 90
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
    if not heavy then ac = searchAircraft(ac, spikeLevel(D.round)) end
    local set = SV_SetAircraft(unit, ac)
    -- a raid's bombers from one direction (CFG.airfield.bombers.one_bearing; D.raidBearing, picked in startRound)
    local raid = D.raidBearing and D.raidUnits and D.raidUnits[unit]
    local x, y, dist, bearing = spawnPoint(b.distance_km, raid and D.raidBearing or nil, b.spread_deg)
    -- SV_Spawn's yaw: towards the airfield (spawnPoint's own bearing is a maths angle, a raid's a compass one)
    local yaw = raid and math.deg(math.atan(AIRFIELD.Y - y, AIRFIELD.X - x)) % 360 or (bearing + 180) % 360
    local band = heavy and b.altitude_m or b.strike_altitude_m
    local alt = band[1] + math.random() * (band[2] - band[1])
    spawningUnit = unit
    local r = SV_Spawn(unit, x, y, alt * 100, yaw)
    spawningUnit = nil
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
-- flights on the tier's own types. Returns the row and how it was picked ("pool" / "signature").
function pickAircraft(tier)
    local v = CFG.variety or {}
    local list, how = {}, "pool"
    if v.enabled and tier and tier.name and v.signature and not D.roundTier and math.random() < (v.signature_share or 0) then
        for _, a in ipairs(v.signature[tier.name:lower()] or {}) do if SR.usable[a] then list[#list + 1] = a end end
        if #list > 0 then how = "signature" end
    end
    if #list == 0 then
        for _, a in ipairs(CFG.aircraft) do list[#list + 1] = a end
        if v.enabled then
            for _, e in ipairs(v.late or {}) do if D.round >= e[2] and SR.usable[e[1]] then list[#list + 1] = e[1] end end
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
    local fcsLevel = math.max(maxLevel and topSpike or spikeLevel(D.round), tier.fcs or 0)
    local base, how = pickAircraft(tier)
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
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    spawningUnit = unit
    local r = SV_Spawn(unit, x, y, alt * 100, (bearing + 180) % 360)          -- facing the airfield
    spawningUnit = nil
    log(string.format("round %d: %s%s as %s (%s, %s set, %s)%s, %.0f km out at bearing %.0f, %.1f km up: %s", D.round, unit,
        D.flown[unit] and " (flown before, recycled)" or "", ac, how, tostring(set), tier.name or "no tier",
        jam and (", led by the jammer " .. jam) or "", dist, bearing, alt / 1000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if jam and r > 0 then
        D.jammer = { unit = unit, at = D.now }
        local t = CFG.hud.text
        hudCallout(t.jammer, t.jammer_sub)
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
