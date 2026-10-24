-- sv_spawn.lua: the clock, spawn points, squadrons, flights and the shuttle's spawn.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_main); a name
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
function spawnPoint(range)
    range = range or CFG.distance_km
    local lo, hi = range[1], range[2]
    for _ = 1, 30 do
        local b, d = math.random() * 360, lo + math.random() * (hi - lo)
        local x = AIRFIELD.X + d * 100000 * math.cos(math.rad(b))
        local y = AIRFIELD.Y + d * 100000 * math.sin(math.rad(b))
        if math.abs(x - ZONE.X) < ZONE.HALF and math.abs(y - ZONE.Y) < ZONE.HALF then return x, y, d, b end
    end
    return AIRFIELD.X, AIRFIELD.Y + lo * 100000, lo, 90
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
    local x, y, dist, bearing = spawnPoint(b.distance_km)
    local band = heavy and b.altitude_m or b.strike_altitude_m
    local alt = band[1] + math.random() * (band[2] - band[1])
    spawningUnit = unit
    local r = SV_Spawn(unit, x, y, alt * 100, (bearing + 180) % 360)
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
            hudCallout(CFG.hud.text.bombers, CFG.hud.text.bombers_sub)
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
    local ac = searchAircraft(CFG.aircraft[math.random(#CFG.aircraft)], fcsLevel)
    local ace = (D.roundTier or maxLevel) and tier.name and ACE.flight(unit, tier.name:lower(), fcsLevel)   -- (ace rounds only)
    if ace then ac = ace.wing end
    local pv = PROBE_OF[unit]
    if pv then                                     -- its behaviour was built from the probe row at level load
        ac = PROBE_MISSION_ROW[pv]
        log(string.format("probe: round %d's first flight %s flies %s (%s script)", D.round, unit, ac,
            pv == "Pkg" and "package" or "run-time"))
    end
    local set = SV_SetAircraft(unit, ac)
    if ace and ace.lead then SV_SetAircraft(unit, ace.lead, 0) end        -- the first aircraft: the ace
    if type(SV_SetLevel) == "function" then SV_SetLevel(unit, (tier.ai_level or 2) * 100) end   -- every spawn: descs are reused
    local x, y, dist, bearing = spawnPoint()
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    spawningUnit = unit
    local r = SV_Spawn(unit, x, y, alt * 100, (bearing + 180) % 360)          -- facing the airfield
    spawningUnit = nil
    log(string.format("round %d: %s%s as %s (%s set, %s), %.0f km out at bearing %.0f, %.1f km up: %s", D.round, unit,
        D.flown[unit] and " (flown before, recycled)" or "", ac, tostring(set), tier.name or "no tier", dist, bearing, alt / 1000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r > 0 then
        D.up[unit], D.flown[unit] = true, true
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
-- The special round `round` is (CFG.specials), or nil for a normal round.
function specialFor(round)
    local sp = CFG.specials
    if sp.enabled and sp.random and #sp.rotation > 0 then
        RUN.specialPick = RUN.specialPick or {}
        local pick = RUN.specialPick
        if pick[round] == nil then
            local kind, early = false, sp.early
            -- each special at most once in cooldown_rounds (user, 2026-10-23: "Each Special Round can only Spawn Once
            -- Every 10 rounds"): one that started in round r can't come again before r + cooldown_rounds
            local function ready(k)
                local last = RUN.specialAt and RUN.specialAt[k]
                return not last or round - last >= (sp.cooldown_rounds or 0)
            end
            -- (in the early window only the early special comes: user, 2026-10-23, "between 2 and 6 ... I only
            -- wanted the Shuttle Launch to ever do"; the others start after it)
            local inEarly = early and early.kind and round >= (early.from or 0) and round <= (early.to or -1)
            if inEarly then
                if not pick[round - 1] and RUN.lastSpecial ~= early.kind and ready(early.kind) and math.random() < (early.chance or 0) then
                    kind = early.kind
                    RUN.lastSpecial = kind
                end
            elseif round >= sp.first and not pick[round - 1] and math.random() < sp.chance then
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
    return sp.rotation[((round - sp.first) // every) % #sp.rotation + 1]
end

-- Comona Defense: the pad (once a run: its guns and SAMs stay up between specials) and the shuttle, both where the
-- world data puts them (SV_Spawn without a position). The shuttle's appearance starts the event package's countdown.
function spawnShuttle()
    local c = CFG.specials.shuttle
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
