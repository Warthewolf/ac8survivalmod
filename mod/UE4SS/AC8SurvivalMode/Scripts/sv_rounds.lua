-- sv_rounds.lua: the shuttle countdown, the specials' tick, starting and running rounds, the airfield.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- The shuttle's countdown clock (D.shuttleClock: cd seconds run, fired the last second's event): it runs on the game
-- clock except while you're down at the airfield (D.grounded, from roundsTick), and fires RE_SV_ShuttleT_<s> for each
-- whole second s (tools/survival_events.py build_shuttle: radio, ignition, liftoff at countdown_s, the climb after it)
-- up to countdown_s + 30; it stops when the shuttle is lost. While the countdown is held the shuttle can't be hurt
-- (user, 2026-10-23: "Make the shuttle invulnerable while the countdown is held"; LiveGameObject.SetIsInvincible).
function SPC.shuttleInvincible(on)
    if not valid(SHUTTLE.obj) then shuttleHealth() end           -- (finds the shuttle's actor)
    if not valid(SHUTTLE.obj) then return false end
    local ok = pcall(function() SHUTTLE.obj:SetIsInvincible(on) end)
    log(string.format("special: shuttle %s%s", on and "invulnerable while the countdown is held" or "can be hit again",
        ok and "" or " (SetIsInvincible failed)"))
    return ok
end

function SPC.shuttleClockTick(now)
    local k = D.shuttleClock
    if not k then return end
    local dt = math.max(0, now - k.at)
    k.at = now
    if not D.grounded then k.cd = k.cd + dt end
    if D.grounded ~= k.grounded then
        k.grounded = D.grounded
        log(string.format("special: shuttle countdown %s at %.0f s", D.grounded and "held (you're down at the airfield)" or "running", k.cd))
    end
    local want = (D.grounded and not k.s.lost and k.s.state == "countdown") or false   -- (not after liftoff)
    if want ~= (k.inv or false) and SPC.shuttleInvincible(want) then k.inv = want end
    local last = CFG.specials.shuttle.countdown_s + 30
    while k.fired < math.min(math.floor(k.cd), last) do
        k.fired = k.fired + 1
        if type(SV_Event) == "function" then SV_Event("RE_SV_ShuttleT_" .. k.fired) end
    end
    if k.fired >= last or k.s.lost then
        if k.inv then SPC.shuttleInvincible(false) end
        D.shuttleClock = nil
    end
end

-- Taking the shuttle and its pad off (with RE_SV_ShuttleRemove). That event's LiveSetActiveGameObjectExecution switches
-- nothing off (a run of 2026-10-24: fired, result 1, and the shuttle, the pad's 9 dummies and its guns were still up
-- every round after), so Lua does it: the shuttle is killed (no longer invincible, MinHealth 0, GameplayStatics.
-- ApplyDamage) so its unit is down and SV_Spawn brings a fresh one next time, and it and everything at the pad
-- (SHUTTLE.padAt, 1.5 km round; not aircraft) is hidden, without collision, target box, lock or targeting, invincible
-- and not ticking. The pad's objects come back as they were at the next shuttle round (spawnShuttle: their units are
-- still up, so they aren't spawned again).
do
local GROUND = { "LiveAIGroundDummy", "LiveAIGroundVehicleObject", "LiveAIGameObject" }
local FLAGS = { "bShowHUDBox", "bIsNotLockonTarget", "bIsNotFCSTargets", "bIsInvincible" }
local GONE = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }
local function hide(o, keep)
    local was = { obj = o }
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
function SPC.shuttleTakeOff()
    SHUTTLE.gone = SHUTTLE.gone or {}
    local sh, killed, hidden, failed = SHUTTLE.obj, "no shuttle actor", 0, 0
    if not valid(sh) then shuttleHealth(); sh = SHUTTLE.obj end
    local f = svFlags() or {}
    if valid(sh) and (f.SV_ShuttleLaunched or 0) < 1 then    -- (a kill now would count as shot down on the pad)
        killed = "not killed (SV_ShuttleLaunched is 0)"
        if hide(sh, false) then hidden = hidden + 1 else failed = failed + 1 end
    elseif valid(sh) then
        pcall(function() sh:SetIsInvincible(false) end)
        pcall(function() sh:SetMinHealth(0.0) end)
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local ok = valid(gs) and pcall(function() gs:ApplyDamage(sh, 100000000.0, nil, nil, nil) end)
        killed = ok and "damage applied" or "ApplyDamage failed"
        if hide(sh, false) then hidden = hidden + 1 else failed = failed + 1 end
    end
    local at = SHUTTLE.padAt
    if at then
        local planeCls = StaticFindObject("/Script/Live.LiveAIPlane")
        local seen = {}
        for _, cls in ipairs(GROUND) do
            for _, o in ipairs(FindAllOf(cls) or {}) do
                local a = valid(o) and addrOf(o)
                if a and not seen[a] and not nameOf(o):find("Default__", 1, true) then
                    seen[a] = true
                    local okP, isPlane = pcall(function() return valid(planeCls) and o:IsA(planeCls) end)
                    local okL, l = pcall(function() local v = o:K2_GetActorLocation(); return { X = v.X, Y = v.Y } end)
                    if not (okP and isPlane) and okL and l and math.sqrt((l.X - at.X) ^ 2 + (l.Y - at.Y) ^ 2) <= 150000 then
                        if hide(o, true) then hidden = hidden + 1 else failed = failed + 1 end
                    end
                end
            end
        end
    end
    log(string.format("special: shuttle and pad off: the shuttle %s; %d objects hidden%s%s", killed, hidden,
        failed > 0 and string.format(", %d only partly", failed) or "", at and "" or " (the pad's spot unknown: the shuttle only)"))
end
-- the pad's objects back as they were (the next shuttle round)
function SPC.shuttlePadBack()
    local n = 0
    for _, w in ipairs(SHUTTLE.gone or {}) do
        local o = w.obj
        if valid(o) then
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
end

-- Watches a running special: launched (its flag, or the countdown run out with the shuttle still there) or lost (its
-- flag, or nothing of its unit alive before liftoff). Pays the reward or closes the shop.
local function specialTick(now)
    SPC.shuttleClockTick(now)
    -- the shuttle killed and hidden first, RE_SV_ShuttleRemove 3 s later: that event sets SV_ShuttleLaunched back to 0,
    -- and a shuttle destroyed while it's 0 counts as shot down on the pad (failure radio, SV_ShuttleLost)
    if D.shuttleRemoveAt and now >= D.shuttleRemoveAt then
        D.shuttleRemoveAt, D.shuttleEventAt, D.shuttleCheckAt = nil, now + 3, now + 5
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
            if BOMBER_UNIT[u] and SV_UnitAlive(u) > 0 and type(SV_Event) == "function" then
                back[#back + 1] = u .. " " .. tostring(SV_Event(string.format("RE_SV_BomberRetask_%02d", BOMBER_INDEX[u])))
            end
        end
        if #back > 0 then log("special: strike flights back onto the airfield: " .. table.concat(back, ", ")) end
    end
    if D.shuttleCheckAt and now >= D.shuttleCheckAt then           -- did the kill take its unit down?
        D.shuttleCheckAt = nil
        local u = CFG.specials.shuttle.unit
        log(string.format("special: shuttle unit %s: %d alive 5 s after it was taken off (0: a fresh one next time)", u, SV_UnitAlive(u)))
    end
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
    if not s or s.state ~= "countdown" then return end
    local c, t = CFG.specials.shuttle, CFG.hud.text
    local f = svFlags() or {}
    local alive = SV_UnitAlive(c.unit)
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
        D.shuttleRemoveAt = now + c.remove_s            -- it and the pad's allies, once it's well up
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, "shuttle launched")
        LB.special("shuttle", true, cd)
        hudCallout(t.launched, string.format(t.launched_sub, pay))
        log(string.format("special: round %d, the shuttle lifted off (%s; %d hits, health %s%%)", D.round,
            launched and "event package" or "countdown over", f.SV_ShuttleHits or -1,
            tostring(shuttleHealth())))
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
    for _, u in ipairs(bombers) do one[#one + 1] = u end
    local cur, n = nil, 0
    for k = i, #fighters do
        local u = fighters[k]
        if not cur or n + size(u) > cap then cur, n = {}, 0; waves[#waves + 1] = cur end
        cur[#cur + 1] = u; n = n + size(u)
    end
    return waves
end

-- The most aircraft a wave holds now (CFG.waves.max_up, by the game's difficulty when max_up_by_preset has it).
local function waveCap()
    local w = CFG.waves
    local n = (w.max_up_by_preset and w.max_up_by_preset[presetName()]) or w.max_up
    return math.max(2, math.floor(n * SETUP.enemyX() + 0.5))      -- (the menu's ENEMY AIRCRAFT %, sv_menu.lua)
end

local function startRound()
    D.round = D.round + 1
    pruneDown()
    D.events = {}
    local sk = spikeCfg(spikeLevel(D.round))
    local budget = math.min(CFG.aircraft_round1 + (D.round - 1) * CFG.aircraft_per_round + (sk.aircraft_add or 0),
        CFG.max_aircraft)
    budget = math.max(1, math.floor(budget * SETUP.enemyX() + 0.5))     -- (the menu's ENEMY AIRCRAFT %, sv_menu.lua)
    local b = CFG.airfield.bombers
    local special = D.forceSpecial or specialFor(D.round)          -- (Ctrl+1 .. Ctrl+5: a special next, for testing)
    D.forceSpecial = nil
    if special == "amphibious" and not AMPH.ready() then          -- no lane can come: a normal round
        log(string.format("round %d: no landing craft can come; a normal round", D.round))
        special = nil
    end
    D.special = special and { kind = special, state = "pending" } or nil
    RUN.specialPick = RUN.specialPick or {}                      -- (as it is: a forced one too; specialFor reads it)
    RUN.specialPick[D.round] = special or false
    if special then
        RUN.lastSpecial = special
        RUN.specialAt = RUN.specialAt or {}
        RUN.specialAt[special] = D.round                    -- (its cooldown: specialFor)
    end
    if special == "amphibious" then                  -- a harder round: more escort (user: "make it difficult")
        budget = math.min(budget + (CFG.specials.amphibious.extra_aircraft or 0), CFG.max_aircraft)
    end
    -- (user, 2026-10-22: "when an ACE team spawns, no other aircraft other than those special to those levels should
    -- spawn"): an ace round (CFG.aces every) is its tier's squadrons throughout, with no bomber raid
    D.roundTier = nil
    local aceTi = (D.nextTierRound == D.round and D.nextTier) or aceRound(D.round, special)   -- (the one its callout named)
    if aceTi then
        local ti = aceTi
        local tn = CFG.tiers.list[ti].name
        if ACE.roster[tn:lower()] then
            D.roundTier = ti
            local c = CFG.aces[tn:lower()] or {}
            if D.aceRoundSaid ~= D.round then
                D.aceRoundSaid = D.round
                log(string.format("aces: round %d is a %s round (%s squadron only)", D.round, tn, tostring(c.squadron)))
            end
        end
    end
    D.nextTier, D.nextTierRound = nil, nil
    if COOP and COOP.more then budget = COOP.more(budget, "max_aircraft") end    -- (co-op: more for more players)
    D.budget = budget
    local spk = special and SPC.kinds[special]
    local alone = spk and SPC.kindValue(spk.alone)                  -- (a special that flies alone: no fighters)
    local raid = not special and not D.roundTier and CFG.airfield.enabled and D.round >= b.first_raid
        and (D.round - b.first_raid) % math.max(1, math.floor(b.raid_every)) == 0
    local bombers, nBombers = {}, 0
    local taken = {}                                -- (flights already picked this round: one pick never takes them again)
    local function pick(units, n, skip)
        local out, got = pickFlights(units, n, function(u) return taken[u] or (skip and skip(u)) end)
        for _, u in ipairs(out) do taken[u] = true end
        return out, got
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
    if normal and CFG.airfield.enabled and st and st.enabled and D.round >= st.from_round and math.random() < st.chance then
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
    local fighters, nFighters = pick(CFG.pool, nWant, function(u) return PROBE_OF[u] end)
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
        for i = 1, math.min(n, #fighters) do
            if poolIndex(fighters[i]) then D.escortUnits[fighters[i]] = true; nEsc = nEsc + 1 end
        end
    end
    -- the round's jammer (CFG.jammer): one fighter flight led by an EA-18G
    local jc = CFG.jammer
    D.jammerUnit, D.jammer = nil, nil
    if normal and jc and jc.enabled and D.round >= jc.from_round and math.random() < jc.chance and SR.usable[jc.aircraft] then
        for _, u in ipairs(fighters) do if not D.jammerUnit and poolIndex(u) and not PROBE_OF[u] then D.jammerUnit = u end end
        if D.jammerUnit then log(string.format("round %d: the jammer flies with %s", D.round, D.jammerUnit)) end
    end
    D.waves = makeWaves(spk and special or nil, fighters, bombers, COOP and COOP.more and COOP.more(waveCap(), "max_up") or waveCap())
    D.wave, D.queue = 1, D.waves[1]
    D.spare = {}
    for _, u in ipairs(CFG.pool) do                 -- spares: free 2-ship flights, for a flight that fails to spawn
        if not D.up[u] and not taken[u] and not PROBE_OF[u] and flightSize(u) == 2 then D.spare[#D.spare + 1] = u end
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
    log(string.format("round %d: %d aircraft: %d fighters in %d squadrons%s%s%s", D.round, nFighters + nBombers, nFighters,
        #fighters, raid and string.format(", bomber raid: %d bombers in %d squadrons%s", nBombers, #bombers,
            D.raidBearing and string.format(" from the %s (bearing %d)", compassName(D.raidBearing), D.raidBearing) or "")
        or special and string.format(", special %s: %d strike aircraft in %d squadrons", special, nBombers, #bombers) or "",
        nEsc > 0 and string.format(", %d escort flights", nEsc) or "", waveText))
    if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " start") end
    D.state, D.at, D.lastAlive, D.waveAt = "spawning", D.now, nil, D.now
    RUN.roundKills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 }
end

-- The player on the ground at the airfield (landed, rolling or in the landing menu): within 3 km of the runway and
-- under 100 m, or nowhere to be read (the landing menu may hide the aircraft). Landing isn't closed under a player
-- who may be down there, so they can always take off again.
function playerOnAirfield()
    local you = playerLocation()
    if not you then return true end
    local dx, dy = you.X - AIRFIELD.X, you.Y - AIRFIELD.Y
    return math.sqrt(dx * dx + dy * dy) < 300000 and you.Z < 10000
end

local ordersTick
do
-- A fighter flight's orders (player only, air search) come from its appearance trigger, which also sets SV_Up_NN. One
-- that appeared while the landing menu was up never got them (test of 2026-10-22: two F-16 flights attacked the
-- airfield), so a flight still unflagged CFG.orders_check_s after spawning gets them from RE_SV_FlightOrders_NN.
function ordersTick(now)
    for u, o in pairs(D.orders) do
        if now >= o.at then
            local i, t = poolIndex(u), svFlags()
            if not i or SV_UnitAlive(u) <= 0 then
                D.orders[u] = nil
            elseif not t or playerOnAirfield() then      -- grounded: the landing menu may be up
                o.at = now + 1
            elseif (t[string.format("SV_Up_%02d", i)] or 0) >= 1 then
                if o.tries > 0 then log("orders: " .. u .. " has its orders now") end
                D.orders[u] = nil
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

function roundsTick(now)
    if not D then return end
    D.now = now
    if not nativeReady() then
        if not D.warned then log("rounds: the native spawner (dlls\\main.dll 0.6.0) did not register SV_Spawn: no enemies"); D.warned = true end
        return
    end
    D.orders = D.orders or {}
    ordersTick(now)
    eventsTick(now)
    -- every tick, whatever the round's state (code review of 2026-10-23: in the break it never ran, so the shuttle's
    -- removal and the Anomaly's lightning clean-up waited for the next round, and while fighting it ran once a second,
    -- which rounded the portal's timing)
    if D.shuttleClock then D.grounded = playerOnAirfield() end   -- (the shuttle's countdown stops while you're down)
    specialTick(now)
    if D.state == "wait" then
        if not D.announced and now >= D.at - CFG.hud.start_callout_lead_s then
            D.announced = true
            local t = CFG.hud.text
            local nextSpecial = D.forceSpecial or specialFor(D.round + 1)
            local nextAce = aceRound(D.round + 1, nextSpecial)          -- (once: it picks the tier)
            local nk = nextSpecial and SPC.kinds[nextSpecial]
            if nk and SPC.kindValue(nk.disguise) then nk = nil end      -- (VALKA: called out as a normal round)
            if nk then
                hudCallout(string.format(t.special, D.round + 1), type(nk.sub) == "function" and nk.sub(t) or t[nk.sub])
            elseif nextAce then
                D.nextTier, D.nextTierRound = nextAce, D.round + 1   -- startRound flies this one
                local tn = CFG.tiers.list[D.nextTier].name:lower()
                local c = CFG.aces[tn] or {}
                hudCallout(string.format(t.start, D.round + 1), string.format(t.aces_round, tostring(c.squadron or tn):upper()))
            else
                hudCallout(string.format(t.start, D.round + 1), t.start_sub)
            end
            local level = spikeLevel(D.round + 1)
            if level > spikeLevel(D.round) then
                hudCallout(t.spike, t.spike_sub)
                log(string.format("spikes: round %d, difficulty level %d", D.round + 1, level))
            end
        end
        if now >= D.at then startRound() end
    elseif D.state == "spawning" then
        if now < D.at then return end
        if playerOnAirfield() then                 -- the landing menu may be up, and a flight that appears then gets no orders
            if D.held ~= D.round then D.held = D.round; log(string.format("round %d: spawns held while you are down at the airfield", D.round)) end
            D.at = now + 1
            return
        end
        if D.held == D.round then D.held = nil; log(string.format("round %d: you took off, spawns go on", D.round)) end
        local u = table.remove(D.queue, 1)
        local sk = type(u) == "string" and u:sub(1, 1) == "@" and SPC.kinds[u:sub(2)]
        if sk then
            if not sk.spawn(now) then                -- it can't come: a normal round (its fighters, if it flies alone)
                local alone = SPC.kindValue(sk.alone)
                D.special, RUN.specialPick[D.round] = nil, false
                local f = alone and pickFlights(CFG.pool, D.budget or CFG.aircraft_round1, function(q) return PROBE_OF[q] end) or {}
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
        D.at = now + CFG.spawn_gap_s
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
        if playerOnAirfield() then D.waveAt = D.waveAt + (now - (D.waveSeen or now)) end   -- (the clock stops while you're down)
        D.waveSeen = now
        local alive = 0
        for u in pairs(D.up) do
            local n = SV_UnitAlive(u)
            if n > 0 then alive = alive + n else D.up[u] = nil end
        end
        local w = CFG.waves
        local timedOut = (w.timeout_s or 0) > 0 and now - D.waveAt >= w.timeout_s       -- (0: by kills only)
        if alive <= w.next_at or timedOut then
            D.wave, D.waveAt = D.wave + 1, now
            D.queue = D.waves[D.wave]
            local n = 0
            for _, u in ipairs(D.queue) do if u:sub(1, 1) ~= "@" then n = n + flightSize(u) end end
            log(string.format("round %d: wave %d of %d (%d aircraft) with %d of the last wave's left%s", D.round, D.wave,
                #D.waves, n, alive, alive > w.next_at and string.format(" (%d s on)", w.timeout_s) or ""))
            if w.callout then
                local t = CFG.hud.text
                hudCallout(string.format(t.wave_in, D.wave, #D.waves), string.format(t.wave_in_sub, n))
            end
            D.state = "spawning"
        end
    elseif D.state == "fighting" then
        if now < D.at then return end
        D.at = now + 1
        local alive, flights = 0, 0
        for u in pairs(D.up) do
            local n = SV_UnitAlive(u)
            if n > 0 then alive, flights = alive + n, flights + 1 else D.up[u] = nil end
        end
        if alive ~= D.lastAlive then log(string.format("round %d: %d aircraft in %d flights left", D.round, alive, flights)); D.lastAlive = alive end
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
        elseif flights == 0 then
            if D.special and D.special.kind == "amphibious" then AMPH.roundOver(now, D.special) end
            local gap = SETUP.breakS()                 -- (the menu's BREAK BETWEEN ROUNDS, sv_menu.lua)
            log(string.format("round %d clear; round %d in %d s", D.round, D.round + 1, gap))
            addCredits(CFG.credits.round_bonus * D.round, "round " .. D.round .. " cleared")
            if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " clear") end
            D.state, D.at, D.announced = "wait", now + gap, false
            hudCallout(string.format(CFG.hud.text.complete, D.round),
                       string.format(CFG.hud.text.complete_sub, gap))
            -- who shot down what (CFG.allies.kills; economy review of 2026-10-25: "show what allies do"), when anyone but
            -- you did
            local k = RUN.roundKills
            if k then
                log(string.format("kills: round %d: you %d, allied aircraft %d, ships %d, airfield defences %d, airstrikes %d",
                    D.round, k.you, k.allies, k.ships, k.defences, k.airstrike))
                if k.allies + k.ships + k.defences > 0 then
                    local t = CFG.hud.text
                    hudCallout(string.format(t.kills, D.round), string.format(t.kills_sub, k.you + k.airstrike, k.allies, k.ships, k.defences))
                end
            end
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
