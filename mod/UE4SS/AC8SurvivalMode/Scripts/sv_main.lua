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
    -- (0.73.73: not while the walks are held, walkHold: a held walk finds nothing, and isn't a try)
    if (not c or (not c.found and (c.tries or 0) < 3 and os.clock() - c.at > 2)) and not walkHold() then
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
    local e = c and c.slots[slot]
    if not e then return nil, nil end
    -- (0.73.73: the TextBlocks are kept between ticks: liveObj before any read, a gone one dropped)
    if e.name and not liveObj(e.name) then e.name = nil end
    if not (e.count and liveObj(e.count)) then
        e.count = nil
        for k, t in pairs(e.all) do
            local v = liveObj(t) and widgetText(t) or nil
            if not liveObj(t) then e.all[k] = nil end
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
    -- page's stays valid (report of 2026-10-23: the STORE still showed the stock counts). ((0.73.77, Workstream B4) Only
    -- when the landing menu's windows changed since (a page opened or closed: SHOP.windowsKey, from the icons' walk, no
    -- walk of its own), a kept panel is gone, or every 8 s: this walk over every object ran every 2 s down there.)
    local wkey = SHOP.windowsKey and SHOP.windowsKey(tick) or nil
    local gone = false
    for _, w in ipairs(SH.panels or {}) do if not liveObj(w) then gone = true end end
    if not SH.panels or gone or (tick % 8 == 1 and (wkey ~= SH.panelKey or tick % 32 == 1)) then
        SH.panelKey = wkey
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
    if DECOY and DECOY.isUnit and DECOY.isUnit(p.unit) then return end   -- (THE DECOY's UAVs too: sv_decoy.lua)
    local model = p.name:match("BP_OP%d+_(%w+)_") or "?"
    local kind = "fighter"
    -- ((0.74.0) THE FESTIVAL's Tu-160s and cruise missiles: their own pay, CFG.specials.festival pay_bomber / pay_missile)
    local fk, fbase = nil, nil
    if FEST and FEST.killPay then fk, fbase = FEST.killPay(p.unit) end
    if fk then kind = fk
    elseif p.unit and BOMBER_UNIT[p.unit] then
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
    -- ((0.73.77, economy C1) in co-op the host names each kill's player (sv_coop.lua KILL.by, p.killer): a teammate's
    -- pays COOP.teamShare(), min(team_x, 1 / (players - 1)), on every game; on a joiner every kill was paid as its own)
    local byX = (by == "airstrike" and (c.airstrike_x or 1))
        or (by == "wingmate" and COOP and COOP.teamShare and COOP.teamShare())
        or (by ~= "you" and (c.ally_x or 1)) or 1
    local byText = (by == "wingmate" and type(p.killer) == "number") and ("player " .. (p.killer + 1)) or by
    local rx = TIER.roundX(D and D.round)
    local jx = p.jammer and (CFG.jammer.pay_x or 1) or 1
    -- your kill of a plane the squadron director used in a tactic within tag_s (CFG.late.director_pay; behaviour roadmap
    -- P8: "so fighting smart pays at any count"): p.dirTag = { tactic, at }, set by STATS.tactic (sv_stats.lua). The
    -- sweep sees a kill up to 2 s late. Pays nothing until the director (P2) tags planes; a co-op joiner's copies carry
    -- no tag (the director runs on the host), so a joiner's own kills of them pay no bonus.
    local dp, dt, dx = CFG.late.director_pay, p.dirTag, 1
    if by == "you" and type(dt) == "table" and type(dp) == "table" and dp.enabled and D and D.now
        and D.now - (tonumber(dt.at) or -math.huge) <= (dp.tag_s or 20) then dx = tonumber(dp.x) or 1 end
    local pay, x = TIER.pay((fbase or c[kind] or 0) * TIER.specialX() * rx * byX * jx * dx, ti)
    addCredits(pay, string.format("%s down (%s%s%s%s%s%s%s)", model, kind, ti and (", " .. list[ti].name .. " x" .. x) or "",
        TIER.specialX() ~= 1 and (", special x" .. TIER.specialX()) or "", rx ~= 1 and string.format(", round x%.2f", rx) or "",
        by ~= "you" and string.format(", by %s x%.2f", byText, byX) or "", jx ~= 1 and string.format(", the jammer x%g", jx) or "",
        dx ~= 1 and string.format(", director %s x%g", tostring(dt.tactic), dx) or ""))
    RUN.kills[by] = (RUN.kills[by] or 0) + 1
    if RUN.roundKills then RUN.roundKills[by] = (RUN.roundKills[by] or 0) + 1 end
    if by ~= "you" and by ~= "airstrike" then
        local d = p.dmg or {}
        log(string.format("kills: %s (%s) went down to %s (damage: you %.0f, allies %.0f, ships %.0f, defences %.0f)%s", p.name,
            tostring(p.unit), by == "wingmate" and byText ~= by and byText or ("the " .. by), d.you or 0, d.allies or 0,
            d.ships or 0, d.defences or 0, p.hostNamed and ", named by the host" or ""))
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

-- (0.73.77, Workstream B1) The time since t0 added to the run's tick timer (D.perf) as part `name`. Every call the tick
-- halves make goes through it now (timed below, or perfAdd around a block whose text the checks read), so the perf
-- line's untimed rest has names: Shake Shack's host of 2026-11-02 went from 15 to 85 ms a tick over 46 rounds, the
-- untimed rest 6 -> 36 ms of it. A name with a "/" ("allies/defences") is a share of the part before the "/", timed
-- inside it (sv_allies.lua, sv_shop.lua, sv_ladon.lua through PERF.add): shown apart, never counted twice.
local function perfAdd(name, t0)
    local pf = D and D.perf
    if not pf then return end
    local e = pf.parts[name] or { n = 0, sum = 0, max = 0 }
    pf.parts[name] = e
    local dt = (os.clock() - t0) * 1000
    e.n, e.sum, e.max = e.n + 1, e.sum + dt, math.max(e.max, dt)
end
PERF = { add = perfAdd, pruned = 0 }
local function timed(name, fn, ...)                -- pcall(fn, ...), its time added to the run's tick timer (D.perf)
    local t0 = os.clock()
    local ok, err = pcall(fn, ...)
    perfAdd(name, t0)
    return ok, err
end

-- Each aircraft's last position, so a loss shows whether it was shot down near the player or crashed far away, and
-- every 10 s the nearest enemy's distance: the check that they come for the player. Each aircraft every 2 s, an eighth
-- of them each tick (all of them on one tick every 2 s was a hitch with 60 aircraft up: user, 2026-10-23, "the custom
-- HUD ... seems a bit laggy"). Timed as "planes" in the perf line (coop-perf step 10). Returns where you are (or nil
-- / false) when a plane was visited this tick.
local tornSeen = 0                                 -- (co-op copies this game took down itself: COOP.tornDown)
-- (0.73.73) Nothing is paid or counted once the level is going away (levelGoing, sv_core.lua): the testers' logs of
-- 0.73.70, 6 runs paid for the planes a quit to the main menu destroyed, up to 26 kills / 4,340 Z "by you" (A10, A06,
-- A04, A08, A16, A19), counted in the leaderboard's and the learning layer's kills too. And a plane gone from the game
-- without being seen at 0 health (destroyed, not shot down) is paid VANISH_HOLD_S later, and only if the level is still
-- on then: in A10 the first four went 63 ms before the main menu's world was made (11:31:57.386 / .449).
local VANISH_HOLD_S = 1.0
local function goneWithLevel(p, why)                -- (not paid, not counted: the first one of a level logged)
    LEAVE.unpaid = (LEAVE.unpaid or 0) + 1
    if not LEAVE.unpaidSaid then
        LEAVE.unpaidSaid = true
        log(string.format("round probe: %s gone with the level (%s): not paid or counted, nor any plane after it", p.name, tostring(why)))
    end
end
local function downCounted(p, you, now)              -- a plane shot down: the kill's lines, its pay and the measurements
    log("round probe: " .. p.name .. " down" .. (p.at and string.format(", last seen %.1f km up%s",
        p.at.Z / 100000, you and string.format(", %.1f km from you", km(p.at, you)) or "") or ""))
    local okG, g = pcall(KILL.geom, p, you or nil)                     -- (its aspect and your last shots)
    if not okG then g = nil end
    pcall(probeKill, p, you or nil, g)
    local okC, by = pcall(creditKill, p)
    if not okC then log("credits: error " .. tostring(by)); by = nil end
    hookErr("stats: STATS.down", pcall(STATS.down, p, g, by, now))
    if p.unit and p.unit:find("^SV_Unit_Ladon") then           -- (its parts with it: sv_ladon.lua)
        hookErr("special: ladonPartsDown", pcall(ladonPartsDown, p))
    end
end
local function vanishedTick()                       -- (each sweep) the planes held VANISH_HOLD_S: paid now, or not at all
    local q = D and D.vanished
    if not (q and #q > 0) then return end
    local keep, going = {}, levelGoing()
    for _, e in ipairs(q) do
        if going then goneWithLevel(e.p, LEAVE.why)
        elseif os.clock() - e.at >= VANISH_HOLD_S then downCounted(e.p, e.you, e.now)
        else keep[#keep + 1] = e end
    end
    D.vanished = keep
end
local function planeSweep(slot)
    local you = nil
    pcall(vanishedTick)
    for i, p in ipairs(planes) do
        if not p.down and i % 8 == slot then
            if you == nil then you = playerLocation() or false end
            -- (0.73.73: liveObj before the health read: the plane is kept between ticks, and a freed one read garbage)
            local up, dead = liveObj(p.obj), false
            if up then
                local ok, h = pcall(function() return p.obj.HealthInternal end)
                if ok and type(h) == "number" and h <= 0 then up, dead = false, true end
            end
            if up then
                pcall(function() local v = p.obj:K2_GetActorLocation(); p.at = { X = v.X, Y = v.Y, Z = v.Z } end)
                p.dist = (p.at and you) and km(p.at, you) or nil                   -- (ACE.hunt's tell reads it)
                local ft = D and p.unit and D.flightTier and D.flightTier[p.unit]
                pcall(planeUnit, p)
                local own = p.unit and (p.unit:find("^SV_Unit_Ladon")             -- (the Ladons: their own tuning;
                    or (DECOY and DECOY.isUnit and DECOY.isUnit(p.unit))           -- THE DECOY's UAVs: their orbit;
                    or p.unit:find("^SV_Unit_FestCM_"))                           -- (0.74.0) THE FESTIVAL's cruise missiles: stock)
                if not own then pcall(enemyTier, p, D and D.round, ft); pcall(enemyManeuvers, p, D and D.round) end
                local an = CFG.specials.anomaly
                local tierFor = (p.unit == an.unit) and { provoke_cone_deg = an.provoke_cone_deg,
                    provoke_time_s = 1.0 / math.max(1, an.aggression or 1), surround_m = an.surround_m }
                    or (ft and CFG.tiers.list[ft])
                if not own then pcall(enemySpike, p, D and D.round, tierFor) end
                if D and not (p.unit and p.unit:find("^SV_Unit_FestCM_")) then pcall(enemyLate, p, D.round) end   -- (CFG.late)
                pcall(probeTrack, p); pcall(ACE.hunt, p); pcall(aiWatch, p, you or nil)
                pcall(KILL.read, p)                                                -- (who's hurt it so far)
                p.addr = p.addr or addrOf(p.obj)                                   -- (KILL.fired's key)
                hookErr("stats: STATS.track", pcall(STATS.track, p, you or nil, D and D.now))   -- (sv_stats.lua)
            -- (0.73.73: tornDown in a pcall: with no address it errs, and the error stopped this slot's sweep at it each tick)
            elseif COOP and COOP.tornDown and select(2, pcall(COOP.tornDown, p)) == true then   -- (a co-op copy this game took down
                p.down = true                                                      -- itself: no kill, no pay, no stats)
                tornSeen = tornSeen + 1
                if tornSeen <= 3 or tornSeen % 25 == 0 then
                    log(string.format("round probe: %s taken down here (co-op, not a kill; %d so far)", p.name, tornSeen))
                end
            elseif levelGoing() then                                           -- (0.73.73: the level going away)
                p.down = true
                goneWithLevel(p, LEAVE.why)
            else
                p.down = true
                if dead then
                    pcall(KILL.read, p)                                        -- (the last hits: it's still there)
                    downCounted(p, you, D and D.now)
                elseif D then                                                  -- (gone without its death seen: held)
                    D.vanished = D.vanished or {}
                    D.vanished[#D.vanished + 1] = { p = p, you = you, at = os.clock(), now = D.now }
                end
            end
        end
    end
    return you
end

-- (0.73.77, Workstream B2) A plane seen down PLANE_KEEP_S ago comes off `planes` (every 2 s, probeTickB). Before, the
-- host's and solo's list lost its downed planes only at a round's start (sv_rounds.lua pruneDown), and a co-op joiner's
-- never: a joiner runs no startRound, so every aircraft of its run stayed in `planes`, which a dozen parts walk every
-- tick (the sweep, the hits, the director, the tail watch, the co-op stray watch, the weapons log...). Not while a
-- special keeps an index into the list (a Ladon round's s.planeFrom, sv_ladon.lua: its bodies' down entries count
-- there); its round's start prunes it. The down entries live on wherever another part holds them (D.vanished, the
-- director's tags): only the list lets go. How many came off (PERF.pruned, the perf line's), first one logged a level.
local PLANE_KEEP_S = 10
local function prunePlanes()
    local s = D and D.special
    if s and s.planeFrom then return 0 end
    local now, keep, cut = os.clock(), {}, 0
    for _, p in ipairs(planes) do
        if p.down then
            p.downSeen = p.downSeen or now
            if now - p.downSeen >= PLANE_KEEP_S then cut = cut + 1 else keep[#keep + 1] = p end
        else
            keep[#keep + 1] = p
        end
    end
    if cut == 0 then return 0 end
    planes = keep
    PERF.pruned = PERF.pruned + cut
    if D and not D.pruneSaid then
        D.pruneSaid = true
        log(string.format("round probe: %d downed aircraft off the list %d s after they went down, %d still on it "
            .. "(0.73.77: every 2 s, not only at a round's start)", cut, PLANE_KEEP_S, #keep))
    end
    return cut
end

-- The run's over: Survival's level was left. Every part stops with D, so nothing of the run reads the level's objects
-- after this. (0.73.73: at once when the level is going away for sure, leaveNow, not only once its player controller had
-- been gone 8 s: every part read the level's objects as they were freed for those 8 s, paying for its planes on the way.)
local function runLeft(why)
    log(string.format("run over: left Survival's level in round %d with %d zollars (%s)", D.round, RUN.credits, tostring(why)))
    local okL, errL = pcall(LB.finish, "left")          -- (its error mustn't stop the reset)
    if not okL then log("leaderboard: error " .. tostring(errL)) end
    if type(SV_MusicHold) == "function" then SV_MusicHold(0) end   -- (never left held)
    if D.special then pcall(SPC.V.cleanup, D.special) end
    if FEST and FEST.sirenOff then pcall(FEST.sirenOff, "the level was left") end   -- ((0.74.0) THE FESTIVAL's siren)
    if SUB and SUB.clear then pcall(SUB.clear, "the level was left") end
    pcall(SND.stopAll)
    pcall(hudRed, false, nil, true)        -- ((0.73.76) VALKA's red sky put back at once, a joiner's too: no tick may follow)
    if SKY then pcall(SKY.restore, "the level was left") end   -- ((0.74.0) the sky's values Survival changed: sv_sky.lua)
    if CINE and CINE.leave then pcall(CINE.leave, why) end    -- ((2026-11-12) the rise cinematic's HUD hide: sv_cine.lua)
    if SKY and SKY.arcReset then pcall(SKY.arcReset, "the level was left") end
    pcall(TAC.reset)                       -- (the gun's class default back to stock)
    if DOWN and DOWN.reset then pcall(DOWN.reset, "the level was left", true) end
    local held = D.vanished and #D.vanished or 0
    if held > 0 or (LEAVE.unpaid or 0) > 0 then
        log(string.format("round probe: %d planes gone with the level: not paid or counted", (LEAVE.unpaid or 0) + held))
    end
    D, A, survivalPC, callouts = nil, nil, nil, {}
    if levelTick ~= -1 then levelTick = nil end           -- (-1: Survival's level loading again, its reset to come)
    planes, pending, lastAlive, SH.panels, SHUTTLE.obj = {}, {}, nil, nil, nil
    ALLY.run = nil
    HIT.reset()
end
-- The level going away for sure (0.73.73): another level loading, or its spawner gone (levelGoing) with your plane gone
-- too. A restart keeps both (the testers' two of 2026-11-01), and the restart's own check needs the run (D) to start over.
local function leaveNow()
    if not (D and levelGoing()) then LEAVE.pawnGoneAt = nil; return false end
    if svLevelOn == false then return true end
    local pawn = nil
    if liveObj(survivalPC) then pcall(function() pawn = survivalPC.Pawn end) end
    if pawn ~= nil and liveObj(pawn) then LEAVE.pawnGoneAt = nil; return false end
    -- (0.73.73 review) your plane gone 3 s, not one look: a restart swaps the old pawn for the new one
    LEAVE.pawnGoneAt = LEAVE.pawnGoneAt or os.clock()
    return os.clock() - LEAVE.pawnGoneAt >= 3
end

-- (probeTick's round clock, for its second half: probeTickB)
local bNow, bPaused
local function probeTick(tick)
    if levelGate() then if D then runLeft(LEAVE.why) end return end   -- ((0.73.77) F1: the level torn down: sv_core.lua levelGate)
    if SKY and SKY.pending then pcall(SKY.idleTick) end   -- ((0.74.0) a custom sun a torn-down level left on: sv_sky.lua)
    if SKY and SKY.retry then pcall(SKY.retryTick) end   -- ((code review of 2026-11-07, finding 12) sky values not put back yet)
    if levelTick == -1 then
        levelTick = tick
        log("level loaded: PL_SurvivalMode (" .. memText() .. ")")
        pcall(logRenderCVars)                      -- (AC8's texture / VT settings, logged once, read only)
        if type(SV_Invert) == "function" then SV_Invert(0, 0, 0, 0) end   -- (the Anomaly's field)
        ANOM.on, ANOM.pawn, ANOM.fx = false, nil, {}
        SH.store, SH.storeTries, SH.added, SH.decor = nil, 0, false, {}      -- (the store: checked again in this level)
        SH.textSent, SH.rowTexts, SH.textSaid = nil, nil, nil   -- ((0.73.77) its texts sent afresh, its rows found again: B4)
        HIT.ladonWalked, HIT.ladonWalkStep, HIT.base = nil, nil, nil  -- ((0.73.79) the Ladon missiles' walk once in this level)
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
        if SKY and SKY.arcReset then pcall(SKY.arcReset, "the run starts over") end   -- ((0.74.0) the day-night arc put back)
        if SUB and SUB.clear then pcall(SUB.clear, "the run starts over") end
        -- ((code review of 2026-11-07, finding 3) what the new specials hold that a restart's mission reload doesn't take:
        -- THE FESTIVAL's siren (our own actor: it looped all the next run) and searchlights, SAL's boat, the weigh-in's
        -- card, THE ESCORT's aircraft and the ZFA-44 carriers (sv_escort.lua ESC.restart). THE DECOY lets its locks go
        -- itself with the old D (sv_decoy.lua DECOY.tick: resetRun)
        if FEST and FEST.restart then pcall(FEST.restart, "the run starts over") end
        if FISH and FISH.boatOff then pcall(FISH.boatOff, "the run starts over") end
        if SUB and SUB.cardOff then pcall(SUB.cardOff) end
        if ESC and ESC.restart then pcall(ESC.restart, "the run starts over") end
        planes, lastAlive, lastFlags = {}, nil, nil
        presetCache.at = -100                 -- the difficulty may have changed since the last run
        if type(SV_Reset) == "function" then SV_Reset() end
        LEAVE.reset()                              -- (0.73.73: this level's spawner not yet seen, nothing going away)
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
        pcall(MUSIC.levelLoad)                          -- (the music player's tracks that loop for ever: sv_music.lua)
    end
    local okSR, errSR = timed("shop rows", shopRowsTick, tick)
    if not okSR then log("shop: rows error " .. tostring(errSR)) end
    local okMu, errMu = timed("music player", MUSIC.tick, tick)
    if not okMu then log("music player: error " .. tostring(errMu)) end
    if tick % 4 == 0 and containerState then                 -- search and behaviour probe rows, from the main menu on
        local tSu = os.clock()                               -- ((0.73.77) "setup" in the perf line: B1)
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
        if FISH and FISH.setup then                      -- ((0.74.0) the shoal's rows and names: sv_fishing.lua)
            local okFs, errFs = pcall(FISH.setup)
            if not okFs then log("fishing: setup error " .. tostring(errFs)); FISH.setupDone = true end
        end
        if ESC and ESC.setup then                        -- (THE ESCORT's and the ZFA-44's rows and names: sv_escort.lua)
            local okEs, errEs = pcall(ESC.setup)
            if not okEs then log("escort: setup error " .. tostring(errEs)); ESC.setupDone = true end
        end
        if DECOY and DECOY.setup then                    -- (THE DECOY's trap UAVs' row: sv_decoy.lua)
            local okDs, errDs = pcall(DECOY.setup)
            if not okDs then log("decoy: setup error " .. tostring(errDs)); DECOY.setupDone = true end
        end
        -- TEST ONLY BEGIN (THE TANICORN's test mount's rows, at the main menu as the shoal's: sv_tanicorn.lua)
        if TANI and TANI.setup then
            local okTs, errTs = pcall(TANI.setup)
            if not okTs then log("tanicorn: setup error " .. tostring(errTs)); TANI.setupDone = true end
        end
        if IFLEET and IFLEET.setup then                  -- ((2026-11-12) INVINCIBLE FLEET's ships' rows: sv_fleet.lua, Ctrl+N)
            local okFl, errFl = pcall(IFLEET.setup)
            if not okFl then log("fleet: setup error " .. tostring(errFl)); IFLEET.setupDone, IFLEET.rowsOk = true, false end
        end
        -- TEST ONLY END
        if COOP and COOP.syncSetup then                  -- (the co-op stand-ins' damage-0 rows, sv_coop.lua)
            local okCs, errCs = pcall(COOP.syncSetup)
            if not okCs then log("coopfire: setup error " .. tostring(errCs)) end
        end
        local okP, errP = pcall(probeSetup)
        if not okP then log("probe: setup error " .. tostring(errP)); PR.tries = 20 end
        local okM, errM = pcall(SHOP.menuSetup)
        if not okM then log("shop: store setup error " .. tostring(errM)); SH.menuDone = true end
        perfAdd("setup", tSu)
    end
    local tLv = os.clock()                         -- ((0.73.77) "leave check", both halves: B1)
    if leaveNow() then runLeft(LEAVE.why) end      -- (0.73.73: the level going away, at once)
    perfAdd("leave check", tLv)
    local tRc = os.clock()                         -- ((0.73.77) "restart check": the controller, the flags: B1)
    if D then
        if not liveObj(survivalPC) and tick % 4 == 0 then survivalPC = playerControllerHere(); playerLocationDirty() end   -- once a second at most
        -- the run is over once Survival's player controller has been gone 8 s (the level was left: before, the run went
        -- on at the main menu and in stock missions, rewriting their ammo panels and paying vanished planes as kills)
        if liveObj(survivalPC) then D.pcSeen, D.pcLost = true, 0
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
        if (D.pcLost or 0) >= 8 then runLeft("its player controller gone 8 s") end
    end
    perfAdd("restart check", tRc)
    if D then
        local tCk = os.clock()                     -- ((0.73.77) "clock": B1)
        local now, paused = roundClock(tick)
        pcall(SND.setPaused, paused)                                    -- (Survival's own sounds hold their breath)
        perfAdd("clock", tCk)
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
            local tMh = os.clock()                 -- ((0.73.77) "music hold": B1)
            if type(SV_MusicHold) == "function" then
                local hold = 0
                if playerOnAirfield() then
                    if paused then
                        hold = 1
                    elseif COOP and COOP.open then
                        -- ((0.73.80, findings perf4 / specials8) the landing menu's kept windows, looked at every tick, no
                        -- walk of its own (sv_core.lua landingShown): one on screen holds it (a closed one may linger until
                        -- it's collected: IsVisible); none lets go once a walk has looked again; not known yet (a page just
                        -- closed, the next one looked for) keeps it as it was. It walked every object every tick while
                        -- held: 1,176 walks in the host's 5.6-minute STORE stay of 2026-11-04)
                        local shown = landingShown(tick)
                        if shown == nil then hold = D.musicHold or 0 else hold = shown and 1 or 0 end
                    end
                else
                    landingLeft()                          -- (this airfield visit's walks logged: sv_core.lua)
                end
                if hold ~= D.musicHold then
                    D.musicHold = hold
                    SV_MusicHold(hold)
                    log("music: track clock " .. (hold == 1 and "held (landing store)" or "running"))
                end
            end
            perfAdd("music hold", tMh)
            local okF, errF = timed("airfield", airfieldTick, tick)
            if not okF then log("airfield: error " .. tostring(errF)) end
            local okB, errB = timed("bombers", bombTick, tick)
            if not okB then log("bombers: error " .. tostring(errB)) end
        end
        if tick % 4 == 1 then timed("death check", LB.deathCheck, survivalPC) end   -- shot down: the run's over
        if PPTEST and PPTEST.tick then pcall(PPTEST.tick, os.clock()) end   -- (COOP2MP's test key: nil in releases, stripped)
        bNow, bPaused = now, paused
        -- ((0.73.79) this tick's pause answer for COOP.tick, which runs right after in the same callback: false only when
        -- the round clock asked the game this tick (it ran on the game's clock and that clock moved), so co-op needn't
        -- ask again)
        CLOCK_TICK, CLOCK_PAUSED = tick, nil
        if D and D.clock == "game" then CLOCK_PAUSED = paused and true or false end
    else
        bNow, bPaused = nil, nil
        CLOCK_TICK, CLOCK_PAUSED = nil, nil
    end
end

-- The tick's second half, 125 ms after probeTick (the loop below): the STORE, the allies, Survival's sounds, what hits
-- you, the loggers, the AI's parts, the ammo and the plane sweep, on probeTick's clock (bNow, bPaused). The tick ran
-- whole on one frame every 250 ms (15-38 ms on the user's PC, worst 357 ms: a frame that long four times a second; a
-- friend's report of 2026-10-31, "choppy" and stuttering in solo play): in two halves, each part still once a tick.
local function probeTickB(tick)
    if levelGate() then if D then runLeft(LEAVE.why) end return end   -- ((0.73.77) F1: the level torn down: sv_core.lua levelGate)
    local tLv = os.clock()                         -- ((0.73.77) "leave check", both halves: B1)
    if leaveNow() then runLeft(LEAVE.why) end      -- (0.73.73: the level going away since the first half)
    perfAdd("leave check", tLv)
    -- TEST ONLY BEGIN (the ZFA-44's test T0, sv_zfa44.lua: its host's meshes kept hidden, its follow-up lines)
    if ZFA and ZFA.cur then
        local okZ, errZ = timed("zfa44", ZFA.tick)
        if not okZ then log("zfa44: T0 tick error " .. tostring(errZ)) end
    end
    -- TEST ONLY END
    if D then
        local now, paused = bNow, bPaused
        if now then
            local okS, errS = timed("shop", shopTick, tick)
            if not okS then log("shop: error " .. tostring(errS)) end
            local okAl, errAl = timed("allies", ALLY.tick, now)
            if not okAl then log("allies: error " .. tostring(errAl)) end
            if ESC and ESC.tick then                  -- THE ESCORT's test, the ZFA-44 carriers and their dressing (sv_escort.lua)
                local okEs, errEs = timed("escort", ESC.tick, now)
                if not okEs and not D.escErr then D.escErr = true; log("escort: tick error " .. tostring(errEs)) end
            end
            local okI, errI = timed("icons", SHOP.decorTick, tick)
            if not okI and not SH.decorErr then SH.decorErr = true; log("shop: row icons error " .. tostring(errI)) end
            local okA2, errA2 = timed("ammo panel", hangarAmmoTick, tick)
            if not okA2 then log("shop: ammo panel error " .. tostring(errA2)) end
        end
        if now and liveObj(survivalPC) then                              -- Survival's own sounds follow (sv_sound.lua)
            local okSn, errSn = timed("sound", SND.tick)
            if not okSn and not D.sndErr then D.sndErr = true; log("sound: error " .. tostring(errSn)) end
        end
        if now and liveObj(survivalPC) then                              -- what hits the player (section "hits")
            local okHt, errHt = timed("hits", HIT.tick, survivalPC, now)
            if not okHt and not D.hitErr then D.hitErr = true; log("hits: error " .. tostring(errHt)) end
            local okWl, errWl = timed("weapons log", WLOG.tick, now)          -- (sv_weaponlog.lua)
            if not okWl and not D.wlogErr then D.wlogErr = true; log("weapons: log error " .. tostring(errWl)) end
            local okAt, errAt = timed("attackers", ATK.tick, now)             -- (sv_spweapons.lua: missiles at once)
            if not okAt and not D.atkErr then D.atkErr = true; log("attackers: error " .. tostring(errAt)) end
            local okSw, errSw = timed("specials", SPW.tick, now)              -- (sv_spweapons.lua)
            if not okSw and not D.spwErr then D.spwErr = true; log("specials: error " .. tostring(errSw)) end
            if DECOY and DECOY.tick then                                       -- (THE DECOY's locks and Spear here: sv_decoy.lua)
                local okDc, errDc = timed("decoy", DECOY.tick, now)
                if not okDc and D and not D.decoyErr then D.decoyErr = true; log("decoy: error " .. tostring(errDc)) end
            end
            local okAu, errAu = timed("audit", AUDIT.tick, now)               -- (sv_audit.lua)
            if not okAu and not D.auditErr then D.auditErr = true; log("audit: error " .. tostring(errAu)) end
            if CFG.allies.kills then timed("kill marks", KILL.markTarget, survivalPC, now) end   -- (what you fired at: KILL.by)
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
        if now and SKY and SKY.arcTick then                -- ((0.74.0) the day-night arc, every game: sv_sky.lua)
            local okSk, errSk = timed("sky arc", SKY.arcTick, now)
            if not okSk then logOnce("sky arc tick", "sky: arc error " .. tostring(errSk) .. " (its first: not logged again)") end
        end
        if now and FISH and FISH.clientTick then          -- ((0.74.0) a co-op joiner's GONE FISHIN' and THE FESTIVAL:
            local okFc, errFc = timed("fishing", FISH.clientTick, now)   -- the boat, the host's state; sv_fishing / festival)
            if not okFc then logOnce("fishing client", "fishing: client error " .. tostring(errFc)) end
        end
        if now and FEST and FEST.clientTick then
            local okXc, errXc = timed("festival", FEST.clientTick, now)
            if not okXc then logOnce("festival client", "festival: client error " .. tostring(errXc)) end
        end
        -- TEST ONLY BEGIN (the test keys' steps: sv_sky.lua, sv_fishing.lua, sv_festival.lua; testKey, sv_core.lua)
        for _, t in ipairs(TEST_TICKS or {}) do
            local okX, errX = timed(t.name, t.fn, os.clock())
            if not okX then logOnce("test tick " .. t.name, "test: " .. t.name .. " error " .. tostring(errX) .. " (its first: not logged again)") end
        end
        -- TEST ONLY END
        if tick % 40 == 9 and type(SV_Event) == "function" then timed("beat", SV_Event, "RE_SV_Beat") end   -- (restart detection)
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
        if tick - levelTick == 8 then timed("difficulty", logDifficulty, "at mission start") end
        if tick - levelTick == 48 then timed("difficulty", logDifficulty, "10 s into the mission") end
    end
    local tNp = os.clock()                                          -- ((0.73.77) "new planes": B1)
    local keep = {}
    for _, p in ipairs(pending) do
        p.age = p.age + 1
        if p.age >= 2 then pcall(logPlane, p.obj, p.unit, p.k) else keep[#keep + 1] = p end
    end
    pending = keep
    perfAdd("new planes", tNp)
    if not levelTick then return end                                -- the rest in Survival only
    local slot = tick % 8
    local okPl, you = timed("planes", planeSweep, slot)            -- (each aircraft every 2 s: planeSweep above)
    if not okPl then
        if not (D and D.planesErr) then log("round probe: planes error " .. tostring(you)) end
        if D then D.planesErr = true end
        you = nil
    end
    if slot ~= 0 then return end                                    -- every 2 s: the summaries
    timed("prune", prunePlanes)                                     -- ((0.73.77) planes down 10 s off the list: B2)
    local tSs = os.clock()                                          -- ((0.73.77) "stats sample": B1)
    if D then hookErr("stats: STATS.sample", pcall(STATS.sample, D.now, you or nil)) end   -- (the measurements, P6's samples)
    perfAdd("stats sample", tSs)
    local okJ, errJ = timed("jammer", JAM.tick)                     -- (the jammer's boost on the enemies near it)
    if not okJ and not D.jamErr then D.jamErr = true; log("jammer: error " .. tostring(errJ)) end
    -- (the log's diagnostics: with [log] verbose the flags on every change, the planes alive, the nearest every 10 s;
    -- without, the flags once a level and when one that isn't a counter changes, flagLine's key)
    local tFl = os.clock()                                          -- ((0.73.77) "flags": B1)
    local verbose = logVerbose()
    local fl, flagged, flagKey = flagLine()
    local key = verbose and fl or flagKey
    if fl and key ~= lastFlags then log("round probe: flags " .. fl); lastFlags = key end
    perfAdd("flags", tFl)
    if not verbose then return end
    local tVb = os.clock()                                          -- ((0.73.77) "verbose": [log] verbose's lines, B1)
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
    perfAdd("verbose", tVb)
end

---------------------------------------------------------------------------------------------------- the one tick
-- The perf line (report of 2026-10-23: "the custom HUD ... seems a bit laggy"): every part by its share of the time,
-- the untimed rest last (the co-op run of 2026-10-30's lines named the four worst single ticks only, which left most of
-- an average 9-30 ms tick unexplained); a minute in, then every five (every minute with [log] verbose); the worst half is
-- the longest the game thread waited on one frame.
-- (0.73.77, Workstream B1) The natives the parts call most, counted and timed for the perf line's second line
-- ("natives: ..."), wrapped here as sv_main.lua runs last (every part calls them by their global names at call time;
-- sv_coop.lua's own raw copies aren't counted). SV_UnitAlive walks the spawner's whole unit list, a memory check on each
-- unit, and that list grows with every unit spawned in the level: its cost can grow over a run with nothing in Lua
-- growing. SV_ObjChain is liveAddr's: how many kept objects every part checks a tick.
local NAT, NAT_NAMES = {}, { "SV_UnitAlive", "SV_Event", "SV_Spawn", "SV_SetText", "SV_ObjChain" }
do
    local function done(e, t0, ...)
        local dt = (os.clock() - t0) * 1000
        e.n, e.ms = e.n + 1, e.ms + dt
        if dt > e.max then e.max = dt end
        return ...
    end
    for _, name in ipairs(NAT_NAMES) do
        local raw = _G[name]
        if type(raw) == "function" then
            local e = { n = 0, ms = 0, max = 0 }
            NAT[name] = e
            if name == "SV_ObjChain" then          -- (counted only: thousands a tick, each as cheap as the clock's read)
                _G[name] = function(...) e.n = e.n + 1; return raw(...) end
            else
                _G[name] = function(...) local t0 = os.clock(); return done(e, t0, raw(...)) end
            end
        end
    end
end

-- (0.73.77, B1) The perf line's second line: the long-lived lists' sizes (every list a part keeps between ticks: one that
-- grows over a long run shows here, the plan's first suspect `planes`), the walks over every object (sv_core.lua WALK.stat,
-- by class: each reads every object, so their cost grows with what the game holds), the natives above, the Lua heap.
local function sizeOf(t) local n = 0; if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end; return n end
local function perfLists()
    local up = 0
    for _, p in ipairs(planes or {}) do if not p.down then up = up + 1 end end
    local out = { string.format("planes %d (%d up; %d down taken off since)", #(planes or {}), up, PERF.pruned) }
    local function add(name, n) if type(n) == "number" and n > 0 then out[#out + 1] = name .. " " .. n end end
    add("new planes", #(pending or {}))
    add("held", D.vanished and #D.vanished)
    add("flights up", sizeOf(D.up))
    add("events", D.events and #D.events)
    local R = ALLY.run
    if R then
        add("allied planes", R.planes and #R.planes)
        add("allies up", sizeOf(R.up))
        add("ESM fields", sizeOf(R.esmFields))
        add("defences' actors", R.defActors and #R.defActors)
    end
    add("missiles", HIT.msl and #HIT.msl)
    add("Ladon missiles", sizeOf(HIT.ladonPool))
    add("kill marks", sizeOf(KILL.fired))
    add("store icons", sizeOf(SH.decor))
    local m = RUN and RUN.metrics
    if m then add("kill records", m.kills and #m.kills); add("tail records", m.tw and #m.tw) end
    if WLOG and WLOG.sizes then
        local okW, w = pcall(WLOG.sizes)
        if okW and type(w) == "table" then for _, e in ipairs(w) do add(e[1], e[2]) end end
    end
    if COOP and COOP.sizes then                    -- (sv_coop.lua's: its copies, flights, ids, torn ...)
        local okC, cs = pcall(COOP.sizes)
        if okC and type(cs) == "table" then for _, e in ipairs(cs) do add("co-op " .. tostring(e[1]), e[2]) end end
    end
    return table.concat(out, ", ")
end
local function perfWalks(n)
    local st = WALK and WALK.stat
    local list, k, ms, worst, worstCls = {}, 0, 0, 0, nil
    for cls, e in pairs(st or {}) do
        list[#list + 1] = { cls, e }
        k, ms = k + e.n, ms + e.ms
        if e.max > worst then worst, worstCls = e.max, cls end
    end
    if WALK then WALK.stat = {} end
    -- ((0.73.79) the StaticFindObject lookups that still scanned every object, and those handed out kept: sv_core.lua)
    local f = WALK and WALK.fstat
    local finds = ""
    if f then
        finds = string.format("; finds: %d scanned (%.2f a tick), %.1f ms a tick, worst %.0f ms (%s); %d kept answers", f.n,
            f.n / math.max(1, n), f.ms / math.max(1, n), f.max, tostring(f.maxPath or "-"), f.kept)
        f.n, f.ms, f.max, f.maxPath, f.kept = 0, 0, 0, nil, 0
    end
    if k == 0 then return "walks: none" .. finds end
    table.sort(list, function(a, b) return a[2].ms > b[2].ms end)
    local top = {}
    for i = 1, math.min(6, #list) do
        local e = list[i][2]
        top[#top + 1] = string.format("%s %dx %.0f ms (%d found)", list[i][1], e.n, e.ms, e.found)
    end
    return string.format("walks: %d (%.2f a tick), %.1f ms a tick, worst %.0f ms (%s); most: %s", k, k / math.max(1, n),
        ms / math.max(1, n), worst, tostring(worstCls), table.concat(top, ", ")) .. finds
end
local function perfNatives(n)
    local t = {}
    for _, name in ipairs(NAT_NAMES) do
        local e = NAT[name]
        if e and e.n > 0 and name == "SV_ObjChain" then
            t[#t + 1] = string.format("%s %.0f a tick", name, e.n / math.max(1, n))
            e.n = 0
        elseif e and e.n > 0 then
            t[#t + 1] = string.format("%s %.1f a tick %.2f ms (worst %.0f)", name, e.n / math.max(1, n), e.ms / math.max(1, n), e.max)
            e.n, e.ms, e.max = 0, 0, 0
        end
    end
    return "natives: " .. (#t > 0 and table.concat(t, ", ") or "none")
end

local function perfLine(tA, tB, tick)
    if not D.perf then                             -- ((0.73.77) a new period: the walks and natives counted from here)
        if WALK then WALK.stat = {} end
        local f = WALK and WALK.fstat
        if f then f.n, f.ms, f.max, f.maxPath, f.kept = 0, 0, 0, nil, 0 end
        for _, e in pairs(NAT) do e.n, e.ms, e.max = 0, 0, 0 end
    end
    local pf = D.perf or { n = 0, sum = 0, max = 0, maxA = 0, maxB = 0, parts = {}, at = tick }
    D.perf = pf
    pf.n, pf.sum = pf.n + 1, pf.sum + tA + tB
    pf.max, pf.maxA, pf.maxB = math.max(pf.max, tA, tB), math.max(pf.maxA, tA), math.max(pf.maxB, tB)
    pf.sumA = (pf.sumA or 0) + tA
    if tick - pf.at < ((logVerbose() or not D.perfSaid) and 240 or 1200) then return end
    D.perfSaid = true
    -- ((0.73.77) every part (it was the top 12, which hid the small ones); the shares within a part, "allies/defences",
    -- apart: their time is in their part's already)
    local parts, subs, timedSum = {}, {}, 0
    for k, v in pairs(pf.parts) do
        if k:find("/", 1, true) then subs[#subs + 1] = { k, v }
        else parts[#parts + 1] = { k, v }; timedSum = timedSum + v.sum end
    end
    local function fmt(list)
        table.sort(list, function(a, b) return a[2].sum > b[2].sum end)
        local top = {}
        for i = 1, #list do
            local v = list[i][2]
            top[#top + 1] = string.format("%s %.1f/%.0f %d%%", list[i][1], v.sum / math.max(1, pf.n), v.max,
                math.floor(100 * v.sum / math.max(pf.sum, 0.001) + 0.5))
        end
        return table.concat(top, ", ")
    end
    local rest = math.max(0, pf.sum - timedSum)
    log(string.format("perf: tick avg %.1f ms (halves %.1f + %.1f), worst half %.1f ms (first %.0f, second %.0f) over %d ticks; "
        .. "parts (ms a tick / worst, share): %s; untimed %.1f %d%%; within them: %s; %s", pf.sum / pf.n, pf.sumA / pf.n,
        (pf.sum - pf.sumA) / pf.n, pf.max, pf.maxA, pf.maxB, pf.n, fmt(parts), rest / pf.n,
        math.floor(100 * rest / math.max(pf.sum, 0.001) + 0.5), #subs > 0 and fmt(subs) or "-", memText()))
    local okL, lists = pcall(perfLists)
    log(string.format("perf: lists: %s; %s; %s; Lua heap %.1f MB", okL and lists or ("error " .. tostring(lists)),
        perfWalks(pf.n), perfNatives(pf.n), collectgarbage("count") / 1024))
    PERF.pruned = 0
    D.perf = nil
end

-- Everything runs from this one loop's game-thread jobs, one at a time. UE4SS 3.0.1 crashed with heap corruption inside
-- its Lua (test M2-8) while this script ran many ExecuteWithDelay timers (one per menu widget) next to two loops; one
-- loop that queues one game-thread job at a time keeps all Lua work in one place. A tick is 250 ms in two halves 125
-- ms apart (probeTick, then probeTickB), so no one frame carries all of it (a friend's "choppy", 2026-10-31).
local tick, rowsStopped, half, tA = 0, false, 1, 0
-- (0.73.75) a tick queued for the game thread and never run held the loop for good: the user's test of 2026-11-02 23:24:49,
-- UE4SS "Error: [Lua::Registry::get_function_ref] Ref was not function" 16 ms after a test key's handler queued its own
-- (both queue game-thread callbacks at once); from then on no tick ran: the round's clock never counted down, the run
-- never ended at the main menu ("run over" never logged) and SURVIVAL MODE's pages never opened. A tick queued
-- TICK_LOST_S ago and not run is taken as lost and queued again. (0.73.82: that can't bring this case back: UE4SS 3.0.1's
-- process_event_hook sets its "an action is running" flag before it looks the action's function up, and the lookup's
-- throw leaves it set, so no game-thread action of any mod runs again. The likely cause, two ExecuteInGameThread calls
-- at once from two threads, is gone with KEYQ; the re-queue stays for a job dropped any other way, and its crumb shows
-- the case.)
-- ((0.73.82) Saint Alessia's crash on launch of 2026-11-04 20:28 (her 12:28:34): UE4SS 3.0.1 runs LoopAsync's function on
-- its own async thread, in this mod's one Lua state, with no lock against the game thread, and Lua isn't safe on two
-- threads at once. The game thread was held 54 s by the main menu's load; the watchdog queued the tick again every 10 s
-- (four more), each time logging, writing a crumb and making a new function there; when the game thread came back it
-- ran the five queued ticks one after another, and the watchdog's next "queued again", 10 s after the last, fell inside
-- them: UE4SS's Lua faulted (lua_getiuservalue on nothing, reading 0xa) 70 ms after the tick's last line. Now the async
-- function only reads its flags and the clock (all captured here: no global looked up, nothing made) and queues the one
-- job made below, and only when no job is waiting or running and the last ended SETTLE_S ago (UE4SS lets go of a job's
-- references just after it returns); a tick taken as lost is queued again once, then after twice as long each time, with
-- a crumb there (the runtime's SV_Crumb with a fixed text: no Lua made), and the job logs it on the game thread. A job
-- holds `waiting` until it ends, so one starting between the async function's reads can't look like none queued, and
-- counts itself in `runs` as it starts: the async function queues only if `running` is still false and no job started
-- since its first look (a job run whole while that thread was held between its reads, the second review of 2026-11-04).
-- Key presses run at the job's start (sv_core.lua KEYQ). The review of 2026-11-04 took out a collector step at the
-- job's end: Lua 5.4's collectgarbage("step", 0) drops the pause after a cycle, so the whole heap was collected every
-- tick half (1-5 ms more on the game thread, measured) and collector steps elsewhere came more often, not less.)
local waiting, running, queuedAt, doneAt, lostAfter, runs = false, false, 0, 0, 0, 0
local lostTicks, lostSaid, TICK_LOST_S, SETTLE_S = 0, 0, 10, 0.02   -- (0.73.76: 10 s; 5 s fired during level loads, 2026-11-02 23:30 / 23:31)
local osClock, inGameThread = os.clock, ExecuteInGameThread
local svCrumb = type(SV_Crumb) == "function" and SV_Crumb or nil   -- (the runtime registers it before main.lua runs)
local function tickJob()
    half = 1 - half
    PLOC.on, PLOC.have, PLOC.v = true, false, nil   -- ((0.73.79) your position read once in this half: playerLocation)
    if half == 1 then                           -- the second half: probeTickB, the leaderboard's polls, the perf line
        local t1 = os.clock()
        local okB, errB = pcall(probeTickB, tick)
        if not okB then log("round probe: error (second half) " .. tostring(errB)) end
        if tick % 4 == 3 then timed("speakers", ALLY.speakerTick, D ~= nil) end   -- the run's ally speakers, on and off
        if tick % 4 == 1 then timed("leaderboard", LB.poll) end                  -- the leaderboard sends' answers
        if tick % 20 == 7 then timed("leaderboard", LB.queueTick) end            -- runs waiting to be sent
        local tB = (os.clock() - t1) * 1000
        if D then pcall(perfLine, tA, tB, tick) end
        PLOC.on, PLOC.have, PLOC.v = false, false, nil
        return
    end
    tick = tick + 1
    local t0 = os.clock()                       -- ((0.73.77) the rows' watch and the info maps in the first half too: B1)
    -- ((0.73.79, the lag audit's item 3) in a run on Survival's level the main menu's tables and the hangar's maps
    -- aren't read by the game (they're pinned, read at the main menu and the hangar), so they're watched every 30 s
    -- (rows) and 60 s (info maps) instead of every 1 s / 2 s: 4-5 ms a tick on a tester's PC, each pass a few
    -- object scans. Back to the menu's pace at the first sign another level loads (svLevelOn false, LEAVE.why), before
    -- the main menu builds its page.)
    local quiet = D ~= nil and svLevelOn ~= false and not LEAVE.why and ready[1] and ready[2]
    if not rowsStopped and (tick % (quiet and 120 or 4) == 0 or not (ready[1] and ready[2])) then   -- watching for reloads
        local ok, r = timed("rows watch", watchRows)
        if not ok then log("rows: error " .. tostring(r)) end
        if ok and r == false then rowsStopped = true end
    end
    if tick % (quiet and 240 or 8) == 2 then
        local okI, errI = timed("info maps", infoMapsTick)
        if not okI then log("info maps: error " .. tostring(errI)) end
    end
    local ok, err = pcall(probeTick, tick)
    if not ok then log("round probe: error " .. tostring(err)) end
    local okM, errM = timed("menu", MENU.tick, tick)   -- Survival's menu pages and the run setups (sv_menu.lua)
    if not okM then log("menu: error " .. tostring(errM)) end
    if COOP and COOP.tick and not levelGate() then   -- Survival COOP (sv_coop.lua): the other game's messages, our plane, mirrors
        -- ((0.73.77) F1: held while the level is torn down: its copies and planes are the level's)
        local okC, errC = timed("coop", COOP.tick, tick)   -- (its own row in the perf line, as the HUD's and rounds')
        if not okC then log("coop: error " .. tostring(errC)) end
    end
    tA = (os.clock() - t0) * 1000
    PLOC.on, PLOC.have, PLOC.v = false, false, nil
end
local function lostSay()
    local n = lostTicks - lostSaid
    lostSaid = lostTicks
    log(string.format("tick: the game thread hadn't run the tick queued %d s or more before (lost, or a long load): queued "
        .. "again %d time%s (%d so far)", TICK_LOST_S, n, n == 1 and "" or "s", lostTicks))
    crumb(string.format("tick lost: queued again (%d so far)", lostTicks))
end
local function job()                                -- (the game thread: one of UE4SS's game-thread actions)
    runs = runs + 1
    running = true                                  -- (`waiting` held until the end: the async function reads `running` first)
    if lostTicks ~= lostSaid then pcall(lostSay) end
    lostAfter = 0
    if KEYQ and KEYQ.drain then
        local okK, errK = pcall(KEYQ.drain)
        if not okK then pcall(log, "keys: error " .. tostring(errK)) end
    end
    local ok, err = pcall(tickJob)
    if not ok then pcall(log, "tick: error " .. tostring(err)) end
    doneAt = osClock()                              -- (in this order: a look between these sees the settle, or a job running)
    waiting = false
    running = false
end
if type(LoopAsync) == "function" and type(inGameThread) == "function" then
    LoopAsync(125, function()                       -- (UE4SS's async thread: its flags, the clock and the queueing only)
        if running then return false end
        local seen = runs
        local t = osClock()
        local lost, la = false, lostAfter
        if waiting then
            if la == 0 then la = TICK_LOST_S; lostAfter = la end
            if t - queuedAt < la then return false end
            lost = true
        elseif t - doneAt < SETTLE_S then
            return false
        end
        if running or runs ~= seen then return false end   -- (a job started since the first look: not lost, not free)
        if lost then lostTicks, lostAfter = lostTicks + 1, la * 2 end   -- (queued again: the next after twice as long)
        waiting, queuedAt = true, t
        inGameThread(job)
        if lost and svCrumb then svCrumb("tick lost: queued again (seen on UE4SS's async thread)") end
        return false
    end)
end

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
    local boundKeys = TEST_KEYS or {}   -- (a key bound twice here or by testKey, sv_core.lua: logged, both would run on a press)
    local RegisterKeyBind = function(key, m, fn)
        if key ~= nil and boundKeys[key] then
            local kn = tostring(key)
            pcall(function() for n, v in pairs(Key) do if v == key then kn = n end end end)
            log("test: Ctrl+" .. kn .. " is bound twice: both run on a press")
        end
        if key ~= nil then boundKeys[key] = true end
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
    -- Ctrl+1 .. Ctrl+5 in a run: the next round is that special (in the break: it starts in 3 s), for testing
    -- (user, 2026-10-23: "build special keys for me to test each special round"; were Ctrl+F11 / Ctrl+F12)
    ;(function()                   -- (its own function: the main chunk's 200-local limit)
    local TEST_SPECIALS = { { "ONE", "shuttle", "COMONA DEFENSE" }, { "TWO", "anomaly", "THE ANOMALY" },
                            { "THREE", "amphibious", "AMPHIBIOUS ASSAULT" }, { "FOUR", "ladon", "THE LADONS" },
                            { "FIVE", "alicorn", "THE ALICORN" }, { "SEVEN", "glitch", "AB.L..IN" },
                            { "EIGHT", "valka", "VALKA" },   -- (0.73.76: back for the user's own VALKA build; a build without her logs it)
                            -- (the Spaceport Assault and its retake, sv_spaceport.lua: Ctrl+END / Ctrl+INS)
                            { "END", "spaceport", "SPACEPORT ASSAULT" }, { "INS", "retake", "SPACEPORT RETAKE" },
                            -- (THE ESCORT, sv_escort.lua: Ctrl+0; a build without its units logs it and flies a normal round)
                            { "ZERO", "escort", "THE ESCORT" } }
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
    -- Ctrl+9 in a run: the ZFA-44's test T0 (sv_zfa44.lua, docs/re/ZFA44.md "T0 build"): VALKA's x40a when she's up,
    -- else the nearest live enemy aircraft, dressed as the ZFA-44 (its container SurvivalMode_ZFA44_P: the user's dev
    -- builds with ZFA=1 only), each dressing on the next paint variant; pressed again: undone
    if Key.NINE then
        pcall(RegisterKeyBind, Key.NINE, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    if ZFA and ZFA.press then ZFA.press() else log("test: Ctrl+9: no ZFA-44 test (sv_zfa44.lua)") end
                end)
                if not ok then log("zfa44: T0: Ctrl+9 error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+F5 in a run: THE ESCORT's landing test T0 (sv_escort.lua ESC.testT0, docs/re/ESCORT.md): CHARLENE alone short
    -- of the approach fix, her final, rollout, taxi and stop logged every 0.5 s; Ctrl+DEL: the ZFA-44 carriers unlocked and
    -- one sent now (ESC.testCarrier). (Were Ctrl+F1 / F2, the tactical items' airstrike and ECM burst keys: sv_tactical.lua)
    for _, tk in ipairs({ { "F5", "testT0" }, { "DEL", "testCarrier" } }) do
        if Key[tk[1]] then
            pcall(RegisterKeyBind, Key[tk[1]], mods, function()
                ExecuteInGameThread(function()
                    local ok, err = pcall(function()
                        if ESC and ESC[tk[2]] then ESC[tk[2]]() else log("test: Ctrl+" .. tk[1] .. ": no escort (sv_escort.lua)") end
                    end)
                    if not ok then log("escort: test Ctrl+" .. tk[1] .. " error " .. tostring(err)) end
                end)
            end)
        else
            log("test: Ctrl+" .. tk[1] .. " not bound (THE ESCORT's " .. tk[2] .. "): UE4SS's Key table has no " .. tk[1])
        end
    end
    end                            -- (the test keys' do: their RegisterKeyBind wrapper)
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

-- AC8's texture and virtual-texture settings (docs/re/AIRCRAFT_MATERIALS.md: its aircraft skins are virtual textures),
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
