-- sv_main.lua: kill credits, the probe tick, the keys, the loops that run it all.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- The landing menu's ammo panel ([WEAPONS AMMO], WBP_Menu_IngameHangar_WeaponDetail_002: six slots
-- AmmoText{L,R}{Top,Center,Bottom}, each WBP_Hangar_Detail_Text_000 with the weapon's name in Text_Body and its stock
-- full load in Text_Body_1, e.g. "MSL" "144"; user screenshot of 2026-10-22: GUN / MSL / FLR on the left, the special
-- weapons on the right). While Survival's caps apply, each capped weapon shows what the player takes off with: the
-- cap (the rearm fills up to it; the gun is left alone).
local AMMO_SLOTS = { "AmmoTextLTop", "AmmoTextLCenter", "AmmoTextLBottom", "AmmoTextRTop", "AmmoTextRCenter", "AmmoTextRBottom" }
local AMMO_SLOT_KIND = { AmmoTextLCenter = 1, AmmoTextLBottom = 4, AmmoTextRTop = 2, AmmoTextRCenter = 3, AmmoTextRBottom = 3 }
-- A named child widget (GetWidgetFromName, else the blueprint variable) and a text widget's text (GetText, else its
-- Text property): on the landing menu the variables read back as TrivialObjects (test of 2026-10-22).
local function childWidget(w, n)
    local ok, x = pcall(function() return w:GetWidgetFromName(FName(n)) end)
    if ok and valid(x) then return x end
    ok, x = pcall(function() return w[n] end)
    if ok and valid(x) then return x end
    return nil
end
local function widgetText(t)
    local ok, v = pcall(function() return t:GetText():ToString() end)
    if ok and type(v) == "string" then return v end
    ok, v = pcall(function() return t.Text:ToString() end)
    if ok and type(v) == "string" then return v end
    return nil
end
-- The slot's name and count TextBlocks. Found by their full names under the panel (<panel>.WidgetTree_N.AmmoText<slot>.
-- WidgetTree_N.<text>): GetWidgetFromName gave nothing on the live panel (test of 2026-10-23: every slot 'nil'). The
-- count is the text that reads as a number (or "---", an empty special slot), the name the other; the count widget is
-- kept once found, as Survival's own number then shows in it.
local function slotTexts(panel, slot)
    SH.slotCache = SH.slotCache or {}
    local key = addrOf(panel) or nameOf(panel)   -- (the address read back nil on the live panel: test of 2026-10-23)
    local c = SH.slotCache[key]
    -- (none yet: looked for again every 2 s, not every call, three times at most: a panel with no ammo slots, such as the
    -- confirmation's, walked every TextBlock in memory every 2 s while you were down at the airfield; the co-op run of
    -- 2026-10-30's "ammo panel" up to 95 ms a tick. The TextBlocks' names are read once a second for every panel)
    if not c or (not c.found and (c.tries or 0) < 3 and os.clock() - c.at > 2) then
        c = { slots = {}, at = os.clock(), tries = (c and c.tries or 0) + 1 }
        local base = nameOf(panel):match("^%S+%s+(.+)$") or nameOf(panel)
        if not (SH.tbNames and os.clock() - SH.tbNames.at < 1) then
            local list = {}
            for _, t in ipairs(FindAllOf("TextBlock") or {}) do list[#list + 1] = { t = t, n = nameOf(t) } end
            SH.tbNames = { at = os.clock(), list = list }
        end
        for _, e in ipairs(SH.tbNames.list) do
            local t, n = e.t, e.n
            local at = n:find(base, 1, true)
            local sl, leaf = nil, nil         -- (not `at and s:match(...)`: `and` keeps only the first capture)
            if at then sl, leaf = n:sub(at + #base):match("^%.WidgetTree[_%d]*%.(AmmoText%a+)%.WidgetTree[_%d]*%.([%w_]+)$") end
            if sl then c.slots[sl] = c.slots[sl] or { all = {} }; c.slots[sl].all[leaf] = t; c.found = true end
        end
        SH.slotCache[key] = c
    end
    local e = c.slots[slot]
    if not e then return nil, nil end
    if not (e.count and valid(e.count)) then
        for _, t in pairs(e.all) do
            local v = widgetText(t)
            if v and (v:match("^%s*%d+%s*$") or v:match("^%s*%-+%s*$")) then e.count = t
            elseif v and v:match("%a") then e.name = t end
        end
    end
    return e.name, e.count
end

local function hangarAmmoTick(tick)
    if not (CFG.ammo.enabled and A and A.applied and A.caps and A.max) or tick % 2 ~= 1 then return end
    if not playerOnAirfield() then SH.panels, SH.slotCache, SH.tbNames = nil, nil, nil; return end   -- the landing menu only exists down there
    -- every 2 s, all of them: the STORE pages show their own panel, made when the page opens, while the landing
    -- page's stays valid (report of 2026-10-23: the STORE still showed the stock counts)
    if tick % 8 == 1 or not SH.panels then
        SH.panels = {}
        for _, w in ipairs(FindAllOf("WBP_Menu_IngameHangar_WeaponDetail_002_C") or {}) do
            if liveWidget(w) then SH.panels[#SH.panels + 1] = w end
        end
    end
    for _, panel in ipairs(SH.panels or {}) do
        local pkey = addrOf(panel) or nameOf(panel)
        SH.panelSaid = SH.panelSaid or {}
        if liveWidget(panel) and not SH.panelSaid[pkey] then
            SH.panelSaid[pkey] = true                -- once a panel: what it holds (test of 2026-10-22: no rewrite seen)
            local parts = {}
            for _, slot in ipairs(AMMO_SLOTS) do
                local name, count = slotTexts(panel, slot)
                parts[#parts + 1] = string.format("%s '%s' '%s'", slot, tostring(name and widgetText(name)),
                    tostring(count and widgetText(count)))
            end
            local mx = {}
            for k = 0, 4 do mx[#mx + 1] = tostring(A.max[k]) end
            log("shop: ammo panel " .. nameOf(panel) .. ": " .. table.concat(parts, ", ") .. "; maxima " .. table.concat(mx, "/"))
        end
        if liveWidget(panel) then
            for _, slot in ipairs(AMMO_SLOTS) do
                pcall(function()
                    local kind = AMMO_SLOT_KIND[slot]
                    local cap = kind and A.caps[kind]
                    if not cap then return end
                    local _, t = slotTexts(panel, slot)
                    local now = t and widgetText(t)
                    if not (now and now:match("^%s*%d+%s*$")) then return end              -- an empty special slot shows "---"
                    local want = tostring(math.min(cap, A.max[kind] or cap))              -- what you take off with
                    if now ~= want then
                        t:SetText(toText(want))
                        SH.ammoSaid = SH.ammoSaid or {}
                        if not SH.ammoSaid[pkey] then SH.ammoSaid[pkey] = true; log("shop: ammo panel " .. (nameOf(panel):match("([%w_]+)$") or "?") .. " shows the caps (" .. now .. " -> " .. want .. ")") end
                    end
                end)
            end
        end
    end
end

-- Credits for an enemy aircraft that went down (probeTick's plane watch), by its flight's role: a bomber flight pays
-- bomber (heavy for CFG.airfield.bombers.heavy models), any other flight fighter. Only when the plane's flight
-- couldn't be read does its model decide (CFG.credits.models). Returns who shot it down (KILL.by's side, "airstrike"),
-- for the measurements (STATS.down); nil for a Ladon.
local function creditKill(p)
    if p.unit and p.unit:find("^SV_Unit_Ladon") then return end   -- (a Ladon pays its own reward: SPC.ladonTick)
    local model = p.name:match("BP_OP%d+_(%w+)_") or "?"
    local kind = "fighter"
    if p.unit and BOMBER_UNIT[p.unit] then
        kind = "bomber"
        for _, h in ipairs(CFG.airfield.bombers.heavy) do if (h:match("^(%w+)_") or h) == model then kind = "heavy" end end
    elseif p.unit == false then
        kind = CFG.credits.models[model] or "fighter"
    end
    -- its skill tier's pay (the tier it was given, else the round's own), x the round (CFG.credits round_x_*), and who
    -- shot it down (KILL.by: an ally's, a ship's or a defence's kill pays ally_x, an airstrike's airstrike_x)
    local list, ti = CFG.tiers.list, nil
    for i, t in ipairs(list) do if t == p.tier then ti = i end end
    ti = ti or (D and D.round and TIER.index(D.round))
    local c = CFG.credits
    local by = p.struck and "airstrike" or KILL.by(p)
    local byX = (by == "airstrike" and (c.airstrike_x or 1)) or (by ~= "you" and (c.ally_x or 1)) or 1
    local rx = TIER.roundX(D and D.round)
    local jx = p.jammer and (CFG.jammer.pay_x or 1) or 1
    -- your kill of a plane the squadron director used in a tactic within tag_s (CFG.late.director_pay; behaviour roadmap
    -- P8: "so fighting smart pays at any count"): p.dirTag = { tactic, at }, set by STATS.tactic (sv_stats.lua). The
    -- sweep sees a kill up to 2 s late. Pays nothing until the director (P2) tags planes; a co-op joiner's copies carry
    -- no tag (the director runs on the host), so a joiner's own kills of them pay no bonus.
    local dp, dt, dx = CFG.late.director_pay, p.dirTag, 1
    if by == "you" and type(dt) == "table" and type(dp) == "table" and dp.enabled and D and D.now
        and D.now - (tonumber(dt.at) or -math.huge) <= (dp.tag_s or 20) then dx = tonumber(dp.x) or 1 end
    local pay, x = TIER.pay((c[kind] or 0) * TIER.specialX() * rx * byX * jx * dx, ti)
    addCredits(pay, string.format("%s down (%s%s%s%s%s%s%s)", model, kind, ti and (", " .. list[ti].name .. " x" .. x) or "",
        TIER.specialX() ~= 1 and (", special x" .. TIER.specialX()) or "", rx ~= 1 and string.format(", round x%.2f", rx) or "",
        by ~= "you" and string.format(", by %s x%.2f", by, byX) or "", jx ~= 1 and string.format(", the jammer x%g", jx) or "",
        dx ~= 1 and string.format(", director %s x%g", tostring(dt.tactic), dx) or ""))
    RUN.kills[by] = (RUN.kills[by] or 0) + 1
    if RUN.roundKills then RUN.roundKills[by] = (RUN.roundKills[by] or 0) + 1 end
    if by ~= "you" and by ~= "airstrike" then
        local d = p.dmg or {}
        log(string.format("kills: %s (%s) went down to the %s (damage: you %.0f, allies %.0f, ships %.0f, defences %.0f)", p.name,
            tostring(p.unit), by, d.you or 0, d.allies or 0, d.ships or 0, d.defences or 0))
    end
    if p.jammer then
        local t = CFG.hud.text
        hudCallout(t.jammer_down, string.format(t.jammer_down_sub, pay))
        if TELL then pcall(TELL.say, "jammer_down", TELL.ALL) end   -- (the jamming's lifted, every player: P3's tells)
    end
    LB.stat("air", 1)
    if by == "allies" or by == "ships" then LB.stat("by_allies", 1) elseif by == "defences" then LB.stat("by_defences", 1) end
    if p.unit and D and D.aceSquad and D.aceSquad[p.unit] then LB.stat("aces", 1) end
    return by
end

-- A new run's money and gear (RUN): a level loaded, or a joiner's when the host's run starts over (newRunHere)
function newRun()
    return { credits = SETUP.zollars(), earned = 0, spent = 0, bought = {}, msg = {}, dirty = true,
             -- kills by who made them (KILL.by), the airframes flown so far (pickAircraft), the tactical items, upgrade
             -- tiers and SECOND CHANCE held (sv_tactical.lua)
             kills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 }, seenAc = {},
             items = {}, ups = {}, insured = false,
             -- (the leaderboard's run clock from the level's start: made later, a run shot down at once read 0:00:00)
             stats = { started = os.time(), air = 0, ground = 0, aces = 0, allies = 0, af_down = 0, captured = 0,
                       by_allies = 0, by_defences = 0, specials = {} } }
end

-- (a joiner, sv_coop.lua "rs") The host's run started over and this game's level didn't: its run starts over too, its
-- money, items, upgrades (UP.apply puts them back to stock within 2 s), SECOND CHANCE and loadout (the ammo preset
-- again: A) as a new run's. The co-op run of 2026-10-30: after the host's restart in round 7 the joiners went into its
-- round 1 with 4,400-15,260 zollars and their upgrades, the host with 720. Allies bought stay up (each game's own).
function newRunHere(why)
    if not D then return end
    local had = RUN and RUN.credits
    RUN = newRun()
    A = nil
    pcall(TAC.reset)
    log(string.format("run: %s: this game's run starts over too: %d zollars (had %s), no items, upgrades or SECOND CHANCE, "
        .. "the loadout as a new run's", tostring(why), RUN.credits, tostring(had)))
end

local function timed(name, fn, ...)                -- pcall(fn, ...), its time added to the run's tick timer (D.perf)
    local t0 = os.clock()
    local ok, err = pcall(fn, ...)
    local pf = D and D.perf
    if pf then
        local e = pf.parts[name] or { n = 0, sum = 0, max = 0 }
        pf.parts[name] = e
        local dt = (os.clock() - t0) * 1000
        e.n, e.sum, e.max = e.n + 1, e.sum + dt, math.max(e.max, dt)
    end
    return ok, err
end

-- Each aircraft's last position, so a loss shows whether it was shot down near the player or crashed far away, and
-- every 10 s the nearest enemy's distance: the check that they come for the player. Each aircraft every 2 s, an eighth
-- of them each tick (all of them on one tick every 2 s was a hitch with 60 aircraft up: user, 2026-10-23, "the custom
-- HUD ... seems a bit laggy"). Timed as "planes" in the perf line (coop-perf step 10). Returns where you are (or nil
-- / false) when a plane was visited this tick.
local tornSeen = 0                                 -- (co-op copies this game took down itself: COOP.tornDown)
local function planeSweep(slot)
    local you = nil
    for i, p in ipairs(planes) do
        if not p.down and i % 8 == slot then
            if you == nil then you = playerLocation() or false end
            local up = valid(p.obj)
            if up then
                local ok, h = pcall(function() return p.obj.HealthInternal end)
                if ok and type(h) == "number" and h <= 0 then up = false end
            end
            if up then
                pcall(function() local v = p.obj:K2_GetActorLocation(); p.at = { X = v.X, Y = v.Y, Z = v.Z } end)
                p.dist = (p.at and you) and km(p.at, you) or nil                   -- (ACE.hunt's tell reads it)
                local ft = D and p.unit and D.flightTier and D.flightTier[p.unit]
                pcall(planeUnit, p)
                local own = p.unit and p.unit:find("^SV_Unit_Ladon")              -- (the Ladons: their own tuning)
                if not own then pcall(enemyTier, p, D and D.round, ft); pcall(enemyManeuvers, p, D and D.round) end
                local an = CFG.specials.anomaly
                local tierFor = (p.unit == an.unit) and { provoke_cone_deg = an.provoke_cone_deg,
                    provoke_time_s = 1.0 / math.max(1, an.aggression or 1), surround_m = an.surround_m }
                    or (ft and CFG.tiers.list[ft])
                if not own then pcall(enemySpike, p, D and D.round, tierFor) end
                if D then pcall(enemyLate, p, D.round) end                         -- (CFG.late: late rounds' health)
                pcall(probeTrack, p); pcall(ACE.hunt, p); pcall(aiWatch, p, you or nil)
                pcall(KILL.read, p)                                                -- (who's hurt it so far)
                p.addr = p.addr or addrOf(p.obj)                                   -- (KILL.fired's key)
                hookErr("stats: STATS.track", pcall(STATS.track, p, you or nil, D and D.now))   -- (sv_stats.lua)
            elseif COOP and COOP.tornDown and COOP.tornDown(p) then           -- (a co-op copy this game took down
                p.down = true                                                      -- itself: no kill, no pay, no stats)
                tornSeen = tornSeen + 1
                if tornSeen <= 3 or tornSeen % 25 == 0 then
                    log(string.format("round probe: %s taken down here (co-op, not a kill; %d so far)", p.name, tornSeen))
                end
            else
                p.down = true
                pcall(KILL.read, p)                                                -- (the last hits, if it's still there)
                log("round probe: " .. p.name .. " down" .. (p.at and string.format(", last seen %.1f km up%s",
                    p.at.Z / 100000, you and string.format(", %.1f km from you", km(p.at, you)) or "") or ""))
                local okG, g = pcall(KILL.geom, p, you or nil)                     -- (its aspect and your last shots)
                if not okG then g = nil end
                pcall(probeKill, p, you or nil, g)
                local okC, by = pcall(creditKill, p)
                if not okC then log("credits: error " .. tostring(by)); by = nil end
                hookErr("stats: STATS.down", pcall(STATS.down, p, g, by, D and D.now))
                if p.unit and p.unit:find("^SV_Unit_Ladon") then           -- (its parts with it: sv_ladon.lua)
                    hookErr("special: ladonPartsDown", pcall(ladonPartsDown, p))
                end
            end
        end
    end
    return you
end

local function probeTick(tick)
    if levelTick == -1 then
        levelTick = tick
        log("level loaded: PL_SurvivalMode (" .. memText() .. ")")
        pcall(logRenderCVars)                      -- (AC8's texture / VT settings, logged once, read only)
        if type(SV_Invert) == "function" then SV_Invert(0, 0, 0, 0) end   -- (the Anomaly's field)
        ANOM.on, ANOM.pawn, ANOM.fx = false, nil, {}
        SH.store, SH.storeTries, SH.added, SH.decor = nil, 0, false, {}      -- (the store: checked again in this level)
        do                                         -- the Anomaly's sounds (Mission 23's) and portal systems, loaded and kept
            local an, got, want = CFG.specials.anomaly, 0, 0
            local function keep(path)
                local n = path:match("[^/]+$")
                want = want + 1
                local o = loadObject(path .. "." .. n)
                if o then pin(o, n); got = got + 1 else log("special: anomaly asset not loaded: " .. path) end
            end
            for _, n in ipairs(an.down_sound_names) do keep(an.down_sounds .. n) end
            for _, n in ipairs(an.hum_sound_names) do keep(an.hum_sounds .. n) end
            for _, part in ipairs({ an.portal.open, an.portal.burst, { an.portal.strike, an.portal.aura } }) do
                for _, p in ipairs(part) do keep(p) end
            end
            log(string.format("special: anomaly sounds and portal systems loaded: %d of %d", got, want))
        end
        if D and D.special then                                            -- (a restart mid-fight: her effects,
            pcall(SPC.V.cleanup, D.special); pcall(SPC.alicornCleanup, D.special)   -- the Alicorn's RAILGUN WARNING)
        end
        pcall(SND.stopAll)
        planes, lastAlive, lastFlags = {}, nil, nil
        presetCache.at = -100                 -- the difficulty may have changed since the last run
        if type(SV_Reset) == "function" then SV_Reset() end
        log("rounds: native spawner " .. (type(SV_Version) == "function" and ("runtime " .. tostring(SV_Version())) or "missing") ..
            "; round 1 in " .. CFG.first_round_delay_s .. " s")
        local first = SETUP.startRound()                -- (the menu's START AT ROUND, sv_menu.lua)
        D = { round = first - 1, startRound = first, state = "wait", at = nil, now = nil, queue = {}, spare = {}, up = {}, flown = {}, announced = false }
        PR.usable = { Pkg = PR.ready.Pkg, Rt = PR.ready.Rt }      -- only rows that were in before this level loaded
        log("probe: at level load, probe rows ready: package " .. tostring(PR.ready.Pkg ~= nil) .. ", run-time " .. tostring(PR.ready.Rt ~= nil))
        SR.usable = {}
        local nS = 0
        local nA = 0                               -- the aces' rows (CFG.aces) count apart from the aircraft
        for a, sv in pairs(SR.ready) do
            SR.usable[a] = sv
            if a:find("^sv_ace_") then nA = nA + 1 else nS = nS + 1 end
        end
        SR.usableLevels = {}                       -- spike rows in before this level loaded (the spawner cached them)
        for a, t in pairs(SR.levels or {}) do SR.usableLevels[a] = t end
        log(string.format("search: at level load, %d of %d aircraft (and %d ace rows) fly with the %s m search", nS,
            #CFG.aircraft, nA, tostring(CFG.search.radius_m)))
        local okRl, errRl = pcall(ROLE.levelLoad)        -- (the fighter roles this level has: their rows were in)
        if not okRl then ROLE.live = nil; log("roles: level load error " .. tostring(errRl) .. "; roles off this level") end
        if H and valid(H.widget) then pcall(function() H.widget:RemoveFromParent() end) end   -- a restart keeps the level
        H, hudTries, hudOff, hudSaid, callouts, survivalPC, A = nil, 0, false, {}, {}, nil, nil
        flagCache.at, flagCache.t, flagCache.cs, flagCache.found = -1, nil, nil, -100
        SHUTTLE.obj, SHUTTLE.lookAt = nil, nil          -- (SHUTTLE.gone kept: a restart keeps the level, and its hidden pad)
        M = { bags = {}, dropped = {}, round = 1, track = CFG.music.start_track }
        local afMax = SETUP.airfieldHP()                -- (the menu's AIRFIELD HEALTH)
        AF = { max = afMax, full = afMax, hp = afMax, down = false, bomb = 0, bombBase = 0, pending = {} }
        RUN = newRun()
        pcall(TAC.reset)                                -- (the gun's class default back to stock, the ECM / decoy off)
        if DOWN and DOWN.reset then pcall(DOWN.reset, "a new level", true) end   -- (co-op: nobody down, no revives yet)
        local okPf, errPf = pcall(PROF.levelLoad)       -- (the learning layer's saved profile read again: P6, sv_stats.lua)
        if not okPf then PROF.saved = nil; log("learning: level load error " .. tostring(errPf)) end
        ALLY.run, KILL.fired = nil, {}             -- (a new level: no allies up, nothing fired at)
        if type(SV_MusicPlayer) == "function" then
            local old = SV_MusicPlayer(CFG.music.pause_player and 1 or 0)
            log("music: pause-menu music player " .. (old < 0 and "not available (pause list not hooked)"
                or (CFG.music.pause_player and "on" or "off")))
        end
        if type(SV_MusicClock) == "function" then
            local old = SV_MusicClock(CFG.music.hold_clock and 1 or 0)
            log("music: music player track clock " .. (old < 0 and "not hooked (tracks may end early after a pause)"
                or (CFG.music.hold_clock and "held while the BGM is paused" or "stock")))
        end
    end
    local okSR, errSR = pcall(shopRowsTick, tick)
    if not okSR then log("shop: rows error " .. tostring(errSR)) end
    if tick % 4 == 0 and containerState then                 -- search and behaviour probe rows, from the main menu on
        local okG, errG = pcall(gameLuaTick, tick, (levelTick and levelTick >= 0) and (tick - levelTick) or nil)
        if not okG then log("game Lua: error " .. tostring(errG)) end
        if not PROF.menuDone then                        -- (the learning layer's saved profile, once a session: P6; the AI's
            local okPf, errPf = pcall(PROF.menu)         -- flare row below, searchSetup, comes from it)
            if not okPf then PROF.menuDone = true; log("learning: profile error " .. tostring(errPf)) end
        end
        local okB, errB = pcall(setsSetup)
        if not okB then log("behaviour: setup error " .. tostring(errB)); BS.done = true end
        local okS, errS = pcall(searchSetup)
        if not okS then log("search: setup error " .. tostring(errS)); SR.done = true end
        local okRl, errRl = pcall(rolesSetup)            -- (the fighter roles' behaviour rows, after the search rows)
        if not okRl then log("roles: setup error " .. tostring(errRl)); RS.done = true end
        local okAc, errAc = pcall(SPC.alicornSetup)
        if not okAc then log("special: Alicorn setup error " .. tostring(errAc)); SPC.alicornDone = true end
        local okL, errL = pcall(SPC.ladonSetup)
        if not okL then log("special: Ladon setup error " .. tostring(errL)); SPC.ladonDone = true end
        local okSp, errSp = pcall(specialSetup)
        if not okSp then log("special: setup error " .. tostring(errSp)); SPS.done = true end
        local okAs, errAs = pcall(ALLY.setup)
        if not okAs then log("allies: setup error " .. tostring(errAs)); ALLY.setupDone = true end
        if COOP and COOP.syncSetup then                  -- (the co-op stand-ins' damage-0 rows, sv_coop.lua)
            local okCs, errCs = pcall(COOP.syncSetup)
            if not okCs then log("coopfire: setup error " .. tostring(errCs)) end
        end
        local okP, errP = pcall(probeSetup)
        if not okP then log("probe: setup error " .. tostring(errP)); PR.tries = 20 end
        local okM, errM = pcall(SHOP.menuSetup)
        if not okM then log("shop: store setup error " .. tostring(errM)); SH.menuDone = true end
    end
    if D then
        if not valid(survivalPC) and tick % 4 == 0 then survivalPC = playerControllerHere() end   -- once a second at most
        -- the run is over once Survival's player controller has been gone 8 s (the level was left: before, the run went
        -- on at the main menu and in stock missions, rewriting their ammo panels and paying vanished planes as kills)
        if valid(survivalPC) then D.pcSeen, D.pcLost = true, 0
        elseif D.pcSeen and tick % 4 == 0 then D.pcLost = (D.pcLost or 0) + 1 end
        -- a mission restart from the pause menu reloads the mission in the same level (no new World, so the reset below
        -- never ran and the run kept its round: user, 2026-10-22), but it sets the event package's flags back to 0: Survival's
        -- counters only grow during a run, so one that drops means the mission started again
        if tick % 8 == 4 then
            local f = svFlags()
            if f then
                D.maxFlags = D.maxFlags or {}
                for _, k in ipairs({ "SV_Kills", "SV_AirHits", "SV_Beat" }) do      -- (SV_Beat: our heartbeat)
                    local v = f[k]
                    if v then
                        if (D.maxFlags[k] or 0) > 0 and v < D.maxFlags[k] then
                            log(string.format("mission restarted in round %d (%s %d -> %d): the run starts over", D.round, k, D.maxFlags[k], v))
                            levelTick = -1         -- the level-load reset below, on the next tick
                            local okL, errL = pcall(LB.finish, "restart")          -- (its error mustn't stop the reset)
                            if not okL then log("leaderboard: error " .. tostring(errL)) end
                        end
                        D.maxFlags[k] = math.max(D.maxFlags[k] or 0, v)
                    end
                end
            end
        end
        if (D.pcLost or 0) >= 8 then
            log(string.format("run over: left Survival's level in round %d with %d zollars", D.round, RUN.credits))
            local okL, errL = pcall(LB.finish, "left")          -- (its error mustn't stop the reset)
            if not okL then log("leaderboard: error " .. tostring(errL)) end
            if type(SV_MusicHold) == "function" then SV_MusicHold(0) end   -- (never left held)
            if D.special then pcall(SPC.V.cleanup, D.special) end
            pcall(SND.stopAll)
            pcall(TAC.reset)                       -- (the gun's class default back to stock)
            if DOWN and DOWN.reset then pcall(DOWN.reset, "the level was left", true) end
            D, A, levelTick, survivalPC, callouts = nil, nil, nil, nil, {}
            planes, pending, lastAlive, SH.panels, SHUTTLE.obj = {}, {}, nil, nil, nil
            ALLY.run = nil
            HIT.reset()
        end
    end
    if D then
        local now, paused = roundClock(tick)
        pcall(SND.setPaused, paused)                                    -- (Survival's own sounds hold their breath)
        if now then
            local okR, errR = timed("rounds", roundsTick, now)
            if not okR then log("rounds: error " .. tostring(errR)) end
            local okH, errH = timed("hud", hudTick, now, paused, survivalPC)
            if not okH then hudLog("tickerr", "error " .. tostring(errH)) end
            local okM, errM = timed("music", musicTick, tick, now, paused)
            if not okM then log("music: error " .. tostring(errM)) end
            -- the landing store plays its own supply music without pausing the BGM channel, so the Music Player's track
            -- clock ran out there (user, 2026-10-24: "music skipped"): held while it's open (paused, down at the airfield).
            -- In co-op the store doesn't pause the game (sv_coop.lua's online-style pause keeps the world running while
            -- others are linked), so the hold never came on there (friends' logs of 2026-10-26: rearmed and bought in the
            -- store, no hold) and the track ended early: then the landing menu being up holds it.
            if type(SV_MusicHold) == "function" then
                local hold = 0
                if playerOnAirfield() then
                    if paused then
                        hold = 1
                    elseif COOP and COOP.open and (tick % 2 == 0 or D.musicHold == 1) then
                        for _, w in ipairs(landingWindows(tick)) do                       -- (sv_core.lua: once a tick)
                            local okV, vis = pcall(function() return w:IsVisible() end)   -- (a closed one may linger
                            if valid(w) and okV and vis == true then hold = 1; break end  -- until it's collected)
                        end
                    elseif COOP and COOP.open then
                        hold = D.musicHold or 0                     -- (looked at every other tick)
                    end
                end
                if hold ~= D.musicHold then
                    D.musicHold = hold
                    SV_MusicHold(hold)
                    log("music: track clock " .. (hold == 1 and "held (landing store)" or "running"))
                end
            end
            local okF, errF = timed("airfield", airfieldTick, tick)
            if not okF then log("airfield: error " .. tostring(errF)) end
            local okB, errB = timed("bombers", bombTick, tick)
            if not okB then log("bombers: error " .. tostring(errB)) end
            local okS, errS = timed("shop", shopTick, tick)
            if not okS then log("shop: error " .. tostring(errS)) end
            local okAl, errAl = timed("allies", ALLY.tick, now)
            if not okAl then log("allies: error " .. tostring(errAl)) end
            local okI, errI = timed("icons", SHOP.decorTick, tick)
            if not okI and not SH.decorErr then SH.decorErr = true; log("shop: row icons error " .. tostring(errI)) end
            local okA2, errA2 = timed("ammo panel", hangarAmmoTick, tick)
            if not okA2 then log("shop: ammo panel error " .. tostring(errA2)) end
        end
        if tick % 4 == 1 then pcall(LB.deathCheck, survivalPC) end      -- shot down: the run's over
        if PPTEST and PPTEST.tick then pcall(PPTEST.tick, os.clock()) end   -- (COOP2MP's test key: nil in releases, stripped)
        if now and valid(survivalPC) then                               -- Survival's own sounds follow (sv_sound.lua)
            local okSn, errSn = timed("sound", SND.tick)
            if not okSn and not D.sndErr then D.sndErr = true; log("sound: error " .. tostring(errSn)) end
        end
        if now and valid(survivalPC) then                               -- what hits the player (section "hits")
            local okHt, errHt = timed("hits", HIT.tick, survivalPC, now)
            if not okHt and not D.hitErr then D.hitErr = true; log("hits: error " .. tostring(errHt)) end
            local okWl, errWl = timed("weapons log", WLOG.tick, now)          -- (sv_weaponlog.lua)
            if not okWl and not D.wlogErr then D.wlogErr = true; log("weapons: log error " .. tostring(errWl)) end
            if CFG.allies.kills then pcall(KILL.markTarget, survivalPC, now) end   -- (what you fired at: KILL.by)
            -- the STORE's tactical items and SECOND CHANCE (sv_tactical.lua)
            local okT, errT = timed("tactical", TAC.tick, now)
            if not okT and not D.tacErr then D.tacErr = true; log("tactical: error " .. tostring(errT)) end
            local okIn, errIn = timed("floor", INS.tick, now)
            if not okIn and not D.insErr then D.insErr = true; log("insurance: error " .. tostring(errIn)) end
            if DOWN and DOWN.tick then                  -- co-op's revives and the spectator camera (sv_down.lua)
                local okDn, errDn = timed("down", DOWN.tick)
                if not okDn and D and not D.downErr then D.downErr = true; log("down: error " .. tostring(errDn)) end
            end
        end
        if tick % 40 == 9 and type(SV_Event) == "function" then pcall(SV_Event, "RE_SV_Beat") end   -- (restart detection)
        if ACE.squadTick then                   -- the ace squadrons' openers and blinks (P9, sv_ai.lua; before the reversals)
            local okSq, errSq = timed("squads", ACE.squadTick, now, D, paused)
            if not okSq and D and not D.squadErr then D.squadErr = true; log("aces: squadron error " .. tostring(errSq)) end
        end
        local okMv, errMv = timed("moves", ACE.movesTick, now, D)              -- top-tier reversals (CFG.aces.flight)
        if not okMv and not D.movesErr then D.movesErr = true; log("aces: moves error " .. tostring(errMv)) end
        if DIR and DIR.tick then                                        -- the squad director (P2, sv_director.lua)
            local okDr, errDr = timed("director", DIR.tick, now, paused)
            if not okDr and D and not D.dirErr then D.dirErr = true; log("director: error " .. tostring(errDr)) end
        end
        if now and TELL then                                            -- actions told lead_s ago (sv_tells.lua)
            local okTl, errTl = timed("tells", TELL.tick, now)
            if not okTl and not D.tellErr then D.tellErr = true; log("tell: tick error " .. tostring(errTl)) end
        end
        if now and not paused then                                      -- P5's gate: you on an enemy's tail (sv_stats.lua)
            local okTw, errTw = timed("tail watch", STATS.tailTick, now)
            if not okTw and not D.twErr then D.twErr = true; log("stats: tail watch error " .. tostring(errTw)) end
        end
        if COOP and COOP.ammoRead then                   -- (co-op: your gun and flares firing, before the refill below)
            local okAr, errAr = timed("coop ammo", COOP.ammoRead)
            if not okAr and not D.ammoReadErr then D.ammoReadErr = true; log("coopfire: ammo read error " .. tostring(errAr)) end
        end
        local okA, errA = timed("ammo", ammoTick, tick, survivalPC)
        if not okA then log("ammo: error " .. tostring(errA)) end
    end
    if levelTick then
        if tick - levelTick == 8 then logDifficulty("at mission start") end
        if tick - levelTick == 48 then logDifficulty("10 s into the mission") end
    end
    local keep = {}
    for _, p in ipairs(pending) do
        p.age = p.age + 1
        if p.age >= 2 then pcall(logPlane, p.obj, p.unit, p.k) else keep[#keep + 1] = p end
    end
    pending = keep
    if not levelTick then return end                                -- the rest in Survival only
    local slot = tick % 8
    local okPl, you = timed("planes", planeSweep, slot)            -- (each aircraft every 2 s: planeSweep above)
    if not okPl then
        if not (D and D.planesErr) then log("round probe: planes error " .. tostring(you)) end
        if D then D.planesErr = true end
        you = nil
    end
    if slot ~= 0 then return end                                    -- every 2 s: the summaries
    if D then hookErr("stats: STATS.sample", pcall(STATS.sample, D.now, you or nil)) end   -- (the measurements, P6's samples)
    local okJ, errJ = pcall(JAM.tick)                               -- (the jammer's boost on the enemies near it)
    if not okJ and not D.jamErr then D.jamErr = true; log("jammer: error " .. tostring(errJ)) end
    -- (the log's diagnostics: with [log] verbose the flags on every change, the planes alive, the nearest every 10 s;
    -- without, the flags once a level and when one that isn't a counter changes, flagLine's key)
    local verbose = logVerbose()
    local fl, flagged, flagKey = flagLine()
    local key = verbose and fl or flagKey
    if fl and key ~= lastFlags then log("round probe: flags " .. fl); lastFlags = key end
    if not verbose then return end
    local alive, nearest = 0, nil
    for _, p in ipairs(planes) do
        if not p.down then
            alive = alive + 1
            if p.dist and (not nearest or p.dist < nearest) then nearest = p.dist end
        end
    end
    if alive ~= lastAlive and #planes > 0 then
        log("round probe: AI aircraft alive " .. alive .. " (created so far " .. #planes .. ")")
        lastAlive = alive
    end
    if tick % 40 == 0 and alive > 0 then
        local flights = 0
        if D then for _ in pairs(D.up) do flights = flights + 1 end end
        log(string.format("enemies: nearest %s from you; %d flights up (%d flagged up)",
            nearest and string.format("%.1f km", nearest) or "(player not found)", flights, flagged or 0))
    end
end

---------------------------------------------------------------------------------------------------- the one tick
-- Everything runs from this single game-thread pass every 250 ms. UE4SS 3.0.1 crashed with heap corruption inside its
-- Lua (test M2-8) while this script ran many ExecuteWithDelay timers (one per menu widget) next to two loops; one
-- loop that queues one game-thread job at a time keeps all Lua work in one place.
local tick, rowsStopped, queued = 0, false, false
LoopAsync(250, function()
    if queued then return false end
    queued = true
    ExecuteInGameThread(function()
        tick = tick + 1
        if not rowsStopped and (tick % 4 == 0 or not (ready[1] and ready[2])) then   -- watching for reloads: 1/s
            local ok, r = pcall(watchRows)
            if not ok then log("rows: error " .. tostring(r)) end
            if ok and r == false then rowsStopped = true end
        end
        if tick % 8 == 2 then
            local okI, errI = pcall(infoMapsTick)
            if not okI then log("info maps: error " .. tostring(errI)) end
        end
        local t0 = os.clock()
        local ok, err = pcall(probeTick, tick)
        if not ok then log("round probe: error " .. tostring(err)) end
        local okM, errM = timed("menu", MENU.tick, tick)   -- Survival's menu pages and the run setups (sv_menu.lua)
        if not okM then log("menu: error " .. tostring(errM)) end
        if COOP and COOP.tick then                  -- Survival COOP (sv_coop.lua): the other game's messages, our plane, mirrors
            local okC, errC = timed("coop", COOP.tick, tick)   -- (its own row in the perf line, as the HUD's and rounds')
            if not okC then log("coop: error " .. tostring(errC)) end
        end
        if D then                                   -- (report of 2026-10-23: "the custom HUD ... seems a bit laggy")
            local pf = D.perf or { n = 0, sum = 0, max = 0, parts = {}, at = tick }
            D.perf = pf
            local dt = (os.clock() - t0) * 1000
            pf.n, pf.sum, pf.max = pf.n + 1, pf.sum + dt, math.max(pf.max, dt)
            if tick - pf.at >= (logVerbose() and 240 or 1200) then   -- (a minute's ticks; five without [log] verbose)
                -- (every part by its share of the time, the untimed rest last: the co-op run of 2026-10-30's lines named
                -- the four worst single ticks only, which left most of an average 9-30 ms tick unexplained)
                local parts, timedSum = {}, 0
                for k, v in pairs(pf.parts) do parts[#parts + 1] = { k, v }; timedSum = timedSum + v.sum end
                table.sort(parts, function(a, b) return a[2].sum > b[2].sum end)
                local top = {}
                for i = 1, math.min(12, #parts) do
                    local v = parts[i][2]
                    top[#top + 1] = string.format("%s %.1f/%.0f %d%%", parts[i][1], v.sum / math.max(1, pf.n), v.max,
                        math.floor(100 * v.sum / math.max(pf.sum, 0.001) + 0.5))
                end
                local rest = math.max(0, pf.sum - timedSum)
                log(string.format("perf: tick avg %.1f ms, worst %.1f ms over %d ticks; parts (ms a tick / worst, share): %s; untimed %.1f %d%%; %s",
                    pf.sum / pf.n, pf.max, pf.n, table.concat(top, ", "), rest / pf.n, math.floor(100 * rest / math.max(pf.sum, 0.001) + 0.5), memText()))
                D.perf = nil
            end
        end
        if tick % 4 == 3 then pcall(ALLY.speakerTick, D ~= nil) end        -- the run's ally speakers, on and off
        if tick % 4 == 1 then pcall(LB.poll) end                         -- the leaderboard sends' answers
        if tick % 20 == 7 then pcall(LB.queueTick) end                   -- runs waiting to be sent
        queued = false
    end)
    return false
end)

---------------------------------------------------------------------------------------------------- dev keys
-- TEST ONLY BEGIN (tools/package_test.sh strips every such block from release / test zips: user, 2026-10-23, "remove
-- all the special codes for accessing levels and cash")
-- On-screen note. PrintString is stripped from some shipping builds, so the log line is the one to rely on.
local function notify(msg)
    log(msg)
    local pc = FindFirstOf("PlayerController")
    local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if valid(pc) and valid(ks) then
        pcall(function() ks:PrintString(pc, TAG .. msg, true, false, { R = 1, G = 0.4, B = 0.1, A = 1 }, 8.0, FName("None")) end)
    end
end

local function openSurvival()
    if not containerMounted() then
        notify("Survival Mode's map is not installed (SurvivalMode_P did not mount), so it was not opened.")
        return
    end
    local pc = FindFirstOf("PlayerController")
    if not valid(pc) then log("launch: no player controller yet; try again on the main menu"); return end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if valid(gs) then
        local ok, err = pcall(function() gs:OpenLevel(pc, FName(LEVEL), true, "") end)
        if ok then log("launch: opening " .. LEVEL); return end
        log("launch: OpenLevel failed (" .. tostring(err) .. "), trying the console command")
    end
    local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if valid(ks) then
        local ok, err = pcall(function() ks:ExecuteConsoleCommand(pc, "open " .. LEVEL, pc) end)
        if ok then log("launch: console 'open " .. LEVEL .. "' sent"); return end
        log("launch: console command failed (" .. tostring(err) .. ")")
    end
end
-- TEST ONLY END

if type(RegisterKeyBind) == "function" and Key then
    local mods = (ModifierKey and ModifierKey.CONTROL) and { ModifierKey.CONTROL } or {}
    -- TEST ONLY BEGIN
    do
    -- (every test key below, pressed, makes its run unranked: LB.testKey, sv_leaderboard.lua)
    local RegisterKeyBind = function(key, m, fn)
        return RegisterKeyBind(key, m, function(...)
            if LB and LB.testKey then pcall(LB.testKey, key) end
            return fn(...)
        end)
    end
    -- Ctrl+F8 on the main menu opens PL_SurvivalMode directly
    if Key.F8 then
        pcall(RegisterKeyBind, Key.F8, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(openSurvival)
                if not ok then log("launch: error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+F9 in a run gives 5000 zollars
    if Key.F9 then
        pcall(RegisterKeyBind, Key.F9, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    if not D then log("test: Ctrl+F9 outside a Survival run"); return end
                    addCredits(5000, "test key Ctrl+F9")
                    RUN.dirty = true
                    hudCallout("TEST: +5000 ZOLLARS", string.format("NOW %d", RUN.credits))
                end)
                if not ok then log("test: Ctrl+F9 error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+F10 in a run: the nearest enemy aircraft is moved every frame 200 m off your left wing through the co-op
    -- runtime's AI-plane teleport (vtable slot 315, the path a joiner's copies of the host's enemies take), a second
    -- press lets it go. The solo check of that path before friends join again (two joiners crashed, 2026-10-25).
    if Key.F10 then
        pcall(RegisterKeyBind, Key.F10, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
                    if not D or not valid(pawn) then log("test: Ctrl+F10 outside a flight"); return end
                    if type(SV_CoopFollow) ~= "function" then log("test: Ctrl+F10 needs dlls/main.dll 0.22"); return end
                    if TEST_AI_FOLLOW then
                        SV_CoopFollow(0)
                        TEST_AI_FOLLOW = nil
                        log("test: Ctrl+F10 the enemy is let go")
                        hudCallout("TEST: ENEMY LET GO", nil)
                        return
                    end
                    local l, best, bestD = pawn:K2_GetActorLocation(), nil, nil
                    for _, p in ipairs(planes or {}) do
                        if not p.down and valid(p.obj) then
                            local okP, q = pcall(function() return p.obj:K2_GetActorLocation() end)
                            if okP and q then
                                local dd = (q.X - l.X) ^ 2 + (q.Y - l.Y) ^ 2 + (q.Z - l.Z) ^ 2
                                if not bestD or dd < bestD then best, bestD = p, dd end
                            end
                        end
                    end
                    if not best then hudCallout("TEST: NO ENEMY UP", "WAIT FOR A ROUND"); return end
                    local f = SV_CoopFollow(addrOf(best.obj), addrOf(pawn), 0, -200, 50, 0)
                    log(string.format("test: Ctrl+F10 %s (%s, %.1f km away) moved every frame through the AI teleport: %s",
                        nameOf(best.obj):match("([^%.:]+)$") or "?", tostring(best.unit), math.sqrt(bestD) / 100000, tostring(f)))
                    if f == 1 then
                        TEST_AI_FOLLOW = true
                        hudCallout("TEST: ENEMY IN FORMATION", "200 M OFF YOUR LEFT WING; CTRL+F10 LETS GO")
                    else
                        hudCallout("TEST: ENEMY NOT MOVED", tostring(f))
                    end
                end)
                if not ok then log("test: Ctrl+F10 error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+1 .. Ctrl+5 in a run: the next round is that special (in the break: it starts in 3 s), for testing
    -- (user, 2026-10-23: "build special keys for me to test each special round"; were Ctrl+F11 / Ctrl+F12)
    ;(function()                   -- (its own function: the main chunk's 200-local limit)
    local TEST_SPECIALS = { { "ONE", "shuttle", "COMONA DEFENSE" }, { "TWO", "anomaly", "THE ANOMALY" },
                            { "THREE", "amphibious", "AMPHIBIOUS ASSAULT" }, { "FOUR", "ladon", "THE LADONS" },
                            { "FIVE", "alicorn", "THE ALICORN" }, { "SEVEN", "glitch", "AB.L..IN" },
                            { "EIGHT", "valka", "VALKA" },
                            -- (the Spaceport Assault and its retake, sv_spaceport.lua: Ctrl+END / Ctrl+INS)
                            { "END", "spaceport", "SPACEPORT ASSAULT" }, { "INS", "retake", "SPACEPORT RETAKE" } }
    for i, ts in ipairs(TEST_SPECIALS) do
        local key, kind, label = Key[ts[1]], ts[2], ts[3]
        if key then
            pcall(RegisterKeyBind, key, mods, function()
                ExecuteInGameThread(function()
                    local ok, err = pcall(function()
                        if not D or not D.now then log("test: Ctrl+" .. ts[1] .. " outside a Survival run"); return end
                        D.forceSpecial = kind
                        local soon = D.state == "wait"
                        if soon then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
                        hudCallout("TEST: " .. label, soon and "STARTING NOW" or "NEXT ROUND")
                        log(string.format("test: Ctrl+%s, round %d is %s (%s)", ts[1], D.round + 1, kind,
                            soon and "starting in 3 s" or "after this round"))
                    end)
                    if not ok then log("test: Ctrl+" .. ts[1] .. " error " .. tostring(err)) end
                end)
            end)
        end
    end
    end)()
    -- Ctrl+6 in a run: a flight at the top level now (the last skill tier's squadron, its ace leading, on the top
    -- fire control), whatever the round (user, 2026-10-23: "a special key to have one of the Aircraft Spawn that is
    -- the MAX LEVEL"); it counts in the round like any flight
    if Key.SIX then
        pcall(RegisterKeyBind, Key.SIX, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    if not D or not D.now or not nativeReady() then log("test: Ctrl+6 outside a Survival run"); return end
                    local unit
                    for _, u in ipairs(CFG.pool) do
                        if not unit and not D.up[u] and not PROBE_OF[u] and not ROLE.sitsOut(u) and flightSize(u) == 2 and SV_UnitAlive(u) <= 0 then unit = u end
                    end
                    if not unit then hudCallout("TEST: NO FREE FLIGHT", "TRY AGAIN WHEN SOME ARE DOWN"); return end
                    local r = spawnFlight(unit, true)
                    local tn = (CFG.tiers.list[#CFG.tiers.list] or {}).name or "?"
                    hudCallout("TEST: " .. tn:upper() .. " FLIGHT", r > 0 and "INBOUND" or "COULD NOT SPAWN")
                    log(string.format("test: Ctrl+6, a %s flight (%s): %s", tn, unit, tostring(r)))
                end)
                if not ok then log("test: Ctrl+6 error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+9 while VALKA flies the X-02S: her next paint variant (SPC.V.PAINTS), named on the HUD and in the log
    if Key.NINE then
        pcall(RegisterKeyBind, Key.NINE, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    local s = SPC.V.cur
                    if not D or not s or not valid(s.modelComp) then log("test: Ctrl+9 without VALKA's X-02S up"); return end
                    local n = SPC.V.paint(CFG.specials.valka, s, s.modelComp, (s.paintK or 1) + 1)
                    hudCallout("TEST: VALKA PAINT " .. s.paintK, n)
                end)
                if not ok then log("test: Ctrl+9 error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+0 in a run: the next line of the tells' catalog (CFG.tells, sv_tells.lua: every radio line of every tell in
    -- turn), said here whatever the gaps, to hear each one (the behaviour roadmap P3's test list,
    -- tools/re/BEHAVIOUR_DIRECTOR.md unit 4)
    if Key.ZERO then
        pcall(RegisterKeyBind, Key.ZERO, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    if not D or not D.now or not TELL then log("test: Ctrl+0 outside a Survival run"); return end
                    local ids, all = {}, {}
                    for id in pairs(CFG.tells.list) do ids[#ids + 1] = id end
                    table.sort(ids)
                    for _, id in ipairs(ids) do
                        for i, line in ipairs(CFG.tells.list[id].radio or {}) do all[#all + 1] = { id, line, i } end
                    end
                    D.tellTest = (D.tellTest or 0) % #all + 1
                    local e = all[D.tellTest]
                    local said, why = TELL.play(e[1], e[3], nil, true, e[2])
                    log(string.format("test: Ctrl+0, tell line %d of %d: %s %s (%s)", D.tellTest, #all, e[1], e[2],
                        said and "said" or tostring(why)))
                end)
                if not ok then log("test: Ctrl+0 error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+F11 in a run: COOP2MP's T1c (tools/re/COOP2MP.md): a real player plane beside you, spawned as Online Mode
    -- spawns another player's (network dummy controller, network object, role 2), its own tick ON and fed (SV_CoopFeed,
    -- runtime 0.29.1): every frame, just before its own remote update, its network data gets your pose 150 m off your
    -- right wing and your stick, so it flies itself as Online Mode's remote players do (T1 / T2 kept its tick off and
    -- moved it: no animations, afterburner, HUD box or enemy attacks). Without SV_CoopFeed (an older main.dll) or if it
    -- refuses, T1's way. Each press the next airframe: your own plane's class, the ADFX-02, the FA-36 (another class,
    -- its own default weapons). Ctrl+F12 takes it away. Watch: does it fly beside you, its control surfaces, gear and
    -- afterburner, an ALLY tag / HUD box, do the enemies go for it; every 5 s `test: second plane ...` says where it is,
    -- its health and how many enemies have it (and you) as their nearest player plane, every second `coop2mp: fed
    -- plane ...` how far it is from where it was sent.
    -- T1d (0.73.2; T1c's test: the enemies had it as their NearestPlayerPlane but never attacked it): an enemy attacks
    -- its fire control's tracking target (GetTrackingTarget), and Survival's orders name "Player" (your plane only). So
    -- every other enemy up is ordered onto the copy (EngagementOrderOverride: Normal, the copy, TargetFirst: it alone),
    -- again every 5 s while it isn't tracking it; the rest pick for themselves. The copy is held at PP_FLOOR health
    -- (never shot down in the test), given your attack limits, and the 5 s line counts the enemies' tracking targets.
    -- Ctrl+F12 (and the next Ctrl+F11) gives the ordered ones back their own order (you, PlayerOnlyNoLimit).
    -- T4a (0.73.5, runtime 0.31.0): the copy of your own plane's class fires what you fire, Online Mode's way (the
    -- runtime replays each launch of yours from the copy's own weapons, your flares too, your gun's trigger mirrored;
    -- `coop2mp: T4 ...` lines); another airframe replays nothing (its weapons aren't yours).
    local ppTest = { addr = nil, step = 0, ordered = {} }
    local PP_FLOOR = 300
    local ORDER_NORMAL, PRIO_PLAYER_ONLY_NO_LIMIT, PRIO_TARGET_FIRST, FIRE_BITS = 0, 8, 9, 7
    local function ppOrder(e, target, prio)
        return pcall(function() e:EngagementOrderOverride(ORDER_NORMAL, target, prio, 0, false, FIRE_BITS, false) end)
    end
    local function ppRelease(why)                      -- the ordered enemies back on you
        local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
        local n = 0
        for _, e in pairs(ppTest.ordered) do
            if valid(e) and valid(pawn) and ppOrder(e, pawn, PRIO_PLAYER_ONLY_NO_LIMIT) then n = n + 1 end
        end
        ppTest.ordered = {}
        if n > 0 then log(string.format("test: %s: %d enemies back on you", why, n)) end
    end
    local function ppTracking(e)                       -- an enemy's fire control's target: "it", "you", "other", "none"
        local ok, t = pcall(function() return e:GetTrackingTarget() end)
        if not ok then return "?" end
        if not valid(t) then return "none" end
        local a = addrOf(t)
        local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
        if a == ppTest.addr then return "it" elseif valid(pawn) and a == addrOf(pawn) then return "you" end
        return "other"
    end
    local function ppSplit(now)                         -- every other enemy up onto the copy (T1d)
        local o = ppTest.obj
        if not valid(o) then return end
        local i, sent = 0, 0
        for _, p in ipairs(planes or {}) do
            if not p.down and valid(p.obj) then
                i = i + 1
                local key = addrOf(p.obj)
                if i % 2 == 1 then
                    if ppTracking(p.obj) ~= "it" and ppOrder(p.obj, o, PRIO_TARGET_FIRST) then sent = sent + 1 end
                    ppTest.ordered[key] = p.obj
                end
            end
        end
        if sent > 0 then log(string.format("test: %d enemies ordered onto the second plane (TargetFirst)", sent)) end
    end
    local function ppPrepare(o, pawn)                   -- the copy's floor and your attack limits
        local okF = pcall(function() o.MinHealth = PP_FLOOR end)
        if not okF then okF = pcall(function() o:SetMinHealth(PP_FLOOR) end) end
        local lim = {}
        for _, k in ipairs({ "MaxPlaneAttackerMissiles", "MaxPursuitAttackers", "MaxNonPlaneAttackerMissiles" }) do
            local okY, y = pcall(function() return pawn[k] end)
            local okW = okY and type(y) == "number" and pcall(function() o[k] = y end)
            local okI, it = pcall(function() return o[k] end)
            lim[#lim + 1] = string.format("%s %s (yours %s%s)", k, okI and tostring(it) or "?", okY and tostring(y) or "?",
                okW and "" or ", not copied")
        end
        log(string.format("test: Ctrl+F11 the copy's floor %d HP: %s; %s", PP_FLOOR, okF and "set" or "NOT SET", table.concat(lim, ", ")))
    end
    local PP_PLANES = { { name = "YOUR OWN" }, { name = "ADFX-02", code = "adfx02" }, { name = "FA-36", code = "fa36" } }
    local function ppClass(e)                          -- (sv_coop.lua's table of every player plane's blueprint)
        if not e.code then return nil end
        local path = COOP and COOP.planeClassPath and COOP.planeClassPath(e.code)
        if not path then return nil, "no blueprint path for " .. e.code end
        return loadObject(path)
    end
    PPTEST = { tick = function(now)
        -- (T4a: your gear on the copy, through the game's own gear calls: SV_CoopPPFx kind 2)
        if ppTest.obj and type(SV_CoopPPFx) == "function" then
            local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
            local down = nil
            pcall(function()
                local comp = pawn.LandingGearOnMesh
                if valid(comp) then local v = comp:IsVisible(); if type(v) == "boolean" then down = v end end
            end)
            if down ~= nil and down ~= ppTest.gear then
                local first = ppTest.gear == nil
                ppTest.gear = down
                if not first then
                    log(string.format("test: your gear %s: the copy's %s", down and "down" or "up", tostring(SV_CoopPPFx(ppTest.addr, 2,
                        down and 1 or 0))))
                end
            end
        end
        if not (ppTest.obj and now >= (ppTest.logAt or 0)) then return end
        ppTest.logAt = now + 5
        local o, pawn = ppTest.obj, survivalPC and valid(survivalPC) and survivalPC.Pawn
        if not valid(o) then log("test: second plane " .. tostring(ppTest.name) .. ": gone"); ppTest.obj = nil; return end
        local d = "?"
        pcall(function()
            local a, b = o:K2_GetActorLocation(), pawn:K2_GetActorLocation()
            d = string.format("%.0f m", math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) / 100)
        end)
        local okH, h = pcall(function() return o.HealthInternal end)
        local onIt, onYou, up = 0, 0, 0
        for _, p in ipairs(planes or {}) do
            if not p.down and valid(p.obj) then
                up = up + 1
                local okN, np = pcall(function() return p.obj.NearestPlayerPlane end)
                local na = okN and valid(np) and addrOf(np)
                if na and na == ppTest.addr then onIt = onIt + 1 elseif na and na == addrOf(pawn) then onYou = onYou + 1 end
            end
        end
        local okT, tk = pcall(function() return o:IsActorTickEnabled() end)
        local okG, gr = pcall(function() return o:IsOnGround() end)
        local okA, act = pcall(function() return o.bIsActivated end)
        local tr, ord, ordIt = { it = 0, you = 0, other = 0, none = 0, ["?"] = 0 }, 0, 0
        for _, p in ipairs(planes or {}) do
            if not p.down and valid(p.obj) then
                local t = ppTracking(p.obj)
                tr[t] = (tr[t] or 0) + 1
                if ppTest.ordered[addrOf(p.obj)] then ord = ord + 1; if t == "it" then ordIt = ordIt + 1 end end
            end
        end
        log(string.format("test: second plane %s: %s from you, health %s, its tick %s, on the ground %s, activated %s; of %d enemies "
            .. "up, %d have it as their nearest player plane, %d you; tracking: %d it, %d you, %d other, %d none, %d unread; ordered "
            .. "onto it %d (%d tracking it); your pawn %s", ppTest.name, d, okH and tostring(h) or "?", okT and tostring(tk) or "?",
            okG and tostring(gr) or "?", okA and tostring(act) or "?", up, onIt, onYou, tr.it, tr.you, tr.other, tr.none, tr["?"],
            ord, ordIt, valid(pawn) and "yours" or "GONE"))
        ppSplit(now)
    end }
    local function ppCopy()
        for _, o in ipairs(FindAllOf("LivePlayerPlane") or {}) do
            if valid(o) and addrOf(o) == ppTest.addr then return o end
        end
    end
    if Key.F11 then
        pcall(RegisterKeyBind, Key.F11, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
                    if not D or not valid(pawn) then log("test: Ctrl+F11 outside a flight"); return end
                    if type(SV_CoopSpawnPP) ~= "function" then log("test: Ctrl+F11 needs dlls/main.dll 0.21.0"); return end
                    ppTest.step = ppTest.step % #PP_PLANES + 1
                    local e = PP_PLANES[ppTest.step]
                    local cls, why = ppClass(e)
                    if e.code and not valid(cls) then
                        log(string.format("test: Ctrl+F11 %s: its class didn't load (%s)", e.name, tostring(why)))
                        hudCallout("TEST: " .. e.name .. " DIDN'T LOAD", "CTRL+F11 FOR THE NEXT")
                        return
                    end
                    local l, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
                    local yaw = math.rad(r.Yaw)
                    local x, y = l.X - math.sin(yaw) * 15000, l.Y + math.cos(yaw) * 15000
                    log(string.format("test: Ctrl+F11 spawning %s (%s)", e.name, cls and nameOf(cls) or "your plane's class"))
                    local a = SV_CoopSpawnPP(addrOf(pawn), x, y, l.Z, r.Yaw, cls and addrOf(cls) or 0)
                    log(string.format("test: Ctrl+F11 second player plane (%s): %s", e.name, tostring(a)))
                    ppRelease("Ctrl+F11 the last copy gone")
                    if type(a) ~= "number" or a <= 0 then hudCallout("TEST: " .. e.name .. " FAILED", tostring(a)); ppTest.obj = nil; return end
                    ppTest.addr, ppTest.name, ppTest.logAt, ppTest.gear = a, e.name, 0, nil
                    local c = ppCopy()
                    ppTest.obj = c
                    local f = type(SV_CoopFeed) == "function" and SV_CoopFeed(a, addrOf(pawn), 0, 150, 0) or "no SV_CoopFeed"
                    if f == 1 then
                        log("test: Ctrl+F11 the copy's own tick stays on, fed (SV_CoopFeed 1)")
                    else
                        local okT, et = pcall(function() c:SetActorTickEnabled(false) end)
                        log("test: Ctrl+F11 not fed (" .. tostring(f) .. "): T1's way, its own tick off: " .. (okT and "done" or tostring(et)))
                        f = SV_CoopFollow(a, addrOf(pawn), 0, 150, 0, 0)
                    end
                    if valid(c) then ppPrepare(c, pawn) end
                    local after = survivalPC.Pawn
                    log("test: Ctrl+F11 after the spawn: your pawn is " .. (addrOf(after) == addrOf(pawn) and "still yours" or
                        ("NOW " .. nameOf(after))) .. "; formation " .. tostring(f))
                    hudCallout("TEST: " .. e.name .. " BESIDE YOU", "CTRL+F11 NEXT AIRFRAME, CTRL+F12 REMOVE")
                end)
                if not ok then log("test: Ctrl+F11 error " .. tostring(err)) end
            end)
        end)
    end
    if Key.F12 then
        pcall(RegisterKeyBind, Key.F12, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    if type(SV_CoopKillPP) ~= "function" then return end
                    ppRelease("Ctrl+F12")
                    ppTest.addr, ppTest.step, ppTest.obj = nil, 0, nil
                    if type(SV_CoopFeed) == "function" then SV_CoopFeed(0) end
                    log("test: Ctrl+F12 second player plane removed: " .. tostring(SV_CoopKillPP()))
                end)
                if not ok then log("test: Ctrl+F12 error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+F5 in a run: the co-op fire path (SV_CoopFire, runtime 0.28.5) on an allied plane, solo, each press the next
    -- step: its missiles with its fire permission off, then on, its gun, its flares, its gear down, up (sv_coop.lua
    -- COOP.fireTest; tools/re/COOP.md 8)
    if Key.F5 then
        pcall(RegisterKeyBind, Key.F5, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    if not D or not COOP or not COOP.fireTest then log("test: Ctrl+F5 outside a Survival run"); return end
                    COOP.fireTest()
                end)
                if not ok then log("test: Ctrl+F5 error " .. tostring(err)) end
            end)
        end)
    end
    -- co-op's revives solo (sv_down.lua; tools/re/COOP.md 9): T1 Ctrl+F6 the floor on / off (down-test: lines once a
    -- second), T2 Ctrl+END each press the next step: down (watching MOONCHILD / VIPER or an enemy; the revive key the
    -- next), back by the loiter, down, back by SV_Respawn
    for key, t in pairs({ F6 = { "T1", "testFloor" }, END = { "T2", "testDown" } }) do
        if Key[key] then
            pcall(RegisterKeyBind, Key[key], mods, function()
                ExecuteInGameThread(function()
                    local ok, err = pcall(function()
                        if not D or not DOWN or not DOWN[t[2]] then log("test: " .. t[1] .. " (Ctrl+" .. key .. ") outside a Survival run"); return end
                        DOWN[t[2]]()
                    end)
                    if not ok then log("test: " .. t[1] .. " (Ctrl+" .. key .. ") error " .. tostring(err)) end
                end)
            end)
        else
            log("test: " .. t[1] .. " not bound: UE4SS has no key " .. key)
        end
    end
    -- The Spaceport Assault's map marks (tools/re/SPACEPORT_ASSAULT.md; hard rule 27: the terrain's collision is only
    -- there near the player, so the shore can't be traced from afar). In flight, low over the spot: Ctrl+HOME a beach the
    -- landing craft land on, Ctrl+PAGE_UP a spot at sea for the fleet, Ctrl+PAGE_DOWN a spot at the spaceport the troops
    -- drive to. Each writes `<kind> x y z ground surface` (cm; surface S sea, L land, ? unknown, from what a straight-down
    -- trace hit) to config\spaceport_marks.txt, and a beach also the ground round it (8 directions at 0.5, 1, 2 and 3 km)
    -- to config\spaceport_rings.txt, so the build can tell which way the open water is. (The airport's beaches came
    -- the same way: Lua 0.35.x's Ctrl+F10 marks, removed in 0.44.1.)
    ;(function()                   -- (its own function: the main chunk's 200-local limit)
    local function marksDir() return SCRIPT_DIR .. "..\\config\\" end
    local function groundAt(ks, x, y)
        local hit = {}
        local ok, r = pcall(function()
            return ks:LineTraceSingle(survivalPC, { X = x, Y = y, Z = 1000000 }, { X = x, Y = y, Z = -100000 }, 0, true, {}, 0,
                hit, true, { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
        end)
        local z, what
        pcall(function()
            local h = hit.OutHit or hit
            local l = h.ImpactPoint or h.Location
            if l and l.Z then z = l.Z end
        end)
        for _, field in ipairs({ "Component", "PhysMaterial" }) do
            if not what then
                pcall(function()
                    local o = (hit.OutHit or hit)[field]
                    if o and o.Get then o = o:Get() end
                    local n = o and nameOf(o)                       -- (its outers checked: sv_core.lua nameOf)
                    if n and n ~= "" and n ~= "?" then what = n:match("([^%.:/]+)$") or n end
                end)
            end
        end
        if ok and r then return z, what end
        return nil, nil
    end
    local function surface(what)
        if not what then return "?" end
        local w = what:lower()
        if w:find("sea") or w:find("water") or w:find("ocean") then return "S" end
        if w:find("landscape") or w:find("terrain") or w:find("ter_") then return "L" end
        return "?"
    end
    local KINDS = { HOME = { "beach", "BEACH MARKED", "a landing craft lands here" },
                    PAGE_UP = { "sea", "FLEET SPOT MARKED", "a ship sails here" },
                    PAGE_DOWN = { "spaceport", "SPACEPORT SPOT MARKED", "troops drive here" } }
    local counts = {}
    for key, k in pairs(KINDS) do
        if Key[key] then
            pcall(RegisterKeyBind, Key[key], mods, function()
                ExecuteInGameThread(function()
                    local ok, err = pcall(function()
                        local you = playerLocation and playerLocation()
                        if not (D and you) then log("test: Ctrl+" .. key .. " (spaceport mark) outside a flight"); return end
                        local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                        local z, what = nil, nil
                        if valid(ks) then z, what = groundAt(ks, you.X, you.Y) end
                        local f = io.open(marksDir() .. "spaceport_marks.txt", "a")
                        if f then
                            f:write(string.format("%s %.0f %.0f %.0f %s %s\n", k[1], you.X, you.Y, you.Z,
                                z and string.format("%.0f", z) or "?", surface(what)))
                            f:close()
                        end
                        local rings = ""
                        if k[1] == "beach" and valid(ks) then          -- (the ground round it, while you're here)
                            local parts = {}
                            for d = 0, 7 do
                                local a, hs = math.rad(d * 45), {}
                                for _, km in ipairs({ 0.5, 1, 2, 3 }) do
                                    local rz, rw = groundAt(ks, you.X + math.cos(a) * km * 100000, you.Y + math.sin(a) * km * 100000)
                                    hs[#hs + 1] = (rz and string.format("%.0f", rz / 100) or "-") .. surface(rw)
                                end
                                parts[#parts + 1] = (d * 45) .. ":" .. table.concat(hs, ",")
                            end
                            rings = table.concat(parts, " ")
                            local r = io.open(marksDir() .. "spaceport_rings.txt", "a")
                            if r then r:write(string.format("beach %.0f %.0f %s\n", you.X, you.Y, rings)); r:close() end
                        end
                        counts[k[1]] = (counts[k[1]] or 0) + 1
                        hudCallout(string.format("%s (%d)", k[2], counts[k[1]]), string.format("%.1f, %.1f KM: %s", you.X / 100000,
                            you.Y / 100000, k[3]))
                        log(string.format("test: spaceport mark %s %d at %.0f, %.0f, %.0f cm (ground %s, %s, %s)%s", k[1], counts[k[1]],
                            you.X, you.Y, you.Z, tostring(z), surface(what), tostring(what), rings ~= "" and (": ring " .. rings) or ""))
                    end)
                    if not ok then log("test: Ctrl+" .. key .. " (spaceport mark) error " .. tostring(err)) end
                end)
            end)
        else
            log("test: the spaceport mark for " .. k[1] .. " not bound: UE4SS has no key " .. key)
        end
    end
    end)()
    end
    -- TEST ONLY END
    if Key.F7 then                 -- Ctrl+F7: write the live HUD's layout to hud_dump.txt (any screen)
        pcall(RegisterKeyBind, Key.F7, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(hudDump, "Ctrl+F7")
                if not ok then log("hud dump: error " .. tostring(err)) end
            end)
        end)
    end
end

log("loaded, version " .. VERSION)

-- AC8's texture and virtual-texture settings (tools/re/AIRCRAFT_MATERIALS.md: its aircraft skins are virtual textures),
-- read through KismetSystemLibrary and logged once (at the first level load): read only, changes nothing
local RENDER_CVARS = {
    { "r.VirtualTextures", "i" }, { "r.VT.TileSize", "i" }, { "r.VT.TileBorderSize", "i" }, { "r.VT.EnableFeedback", "i" },
    { "r.VT.FeedbackFactor", "i" }, { "r.VT.MaxUploadsPerFrame", "i" }, { "r.VT.PoolSizeScale", "f" },
    { "r.VT.EnableAutoImport", "i" }, { "r.VT.Residency.Show", "i" }, { "r.VT.PoolAutoGrow", "i" },
    { "r.VT.MaxReleasedPerFrame", "i" }, { "r.Streaming.PoolSize", "i" }, { "r.Streaming.UseFixedPoolSize", "i" },
    { "r.Streaming.FullyLoadUsedTextures", "i" }, { "r.TextureStreaming", "i" }, { "r.MaterialQualityLevel", "i" },
    { "r.Shaders.FastMath", "i" }, { "fx.Niagara.GPUSort", "i" }, { "fx.GPUSort.MaxSortBatchSize", "i" },
}
-- the game's memory for the log ("memory 5123 MB, committed 7012 MB"), from the runtime (SV_MemMB, 0.18.3)
function memText()
    if type(SV_MemMB) ~= "function" then return "memory ?" end
    local v = SV_MemMB()
    if type(v) ~= "number" or v < 0 then return "memory ?" end
    return string.format("memory %d MB, committed %d MB", v // 100000, v % 100000)
end
function logRenderCVars()
    if RENDER_CVARS.said then return end
    local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if not valid(ks) then return end
    local out = {}
    for _, cv in ipairs(RENDER_CVARS) do
        local ok, v = pcall(function()
            if cv[2] == "f" then return ks:GetConsoleVariableFloatValue(cv[1]) end
            return ks:GetConsoleVariableIntValue(cv[1])
        end)
        out[#out + 1] = cv[1] .. "=" .. (ok and tostring(v) or "?")
    end
    RENDER_CVARS.said = true
    log("render settings: " .. table.concat(out, " "))
end
