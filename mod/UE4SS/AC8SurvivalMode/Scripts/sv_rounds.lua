-- sv_rounds.lua: the shuttle countdown, the specials' tick, starting and running rounds, the airfield.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_main); a name
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

-- Watches a running special: launched (its flag, or the countdown run out with the shuttle still there) or lost (its
-- flag, or nothing of its unit alive before liftoff). Pays the reward or closes the shop.
local function specialTick(now)
    SPC.shuttleClockTick(now)
    if D.shuttleRemoveAt and now >= D.shuttleRemoveAt then            -- (tools/survival_events.py RE_SV_ShuttleRemove)
        D.shuttleRemoveAt = nil
        if D.shuttleClock and D.shuttleClock.inv then SPC.shuttleInvincible(false); D.shuttleClock.inv = false end
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

local function startRound()
    D.round = D.round + 1
    local sk = spikeCfg(spikeLevel(D.round))
    local budget = math.min(CFG.aircraft_round1 + (D.round - 1) * CFG.aircraft_per_round + (sk.aircraft_add or 0),
        CFG.max_aircraft)
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
    D.budget = budget
    local spk = special and SPC.kinds[special]
    local alone = spk and SPC.kindValue(spk.alone)                  -- (a special that flies alone: no fighters)
    local raid = not special and not D.roundTier and CFG.airfield.enabled and D.round >= b.first_raid
        and (D.round - b.first_raid) % math.max(1, math.floor(b.raid_every)) == 0
    local bombers, nBombers = {}, 0
    if raid then
        local share = math.floor(budget * b.raid_share / 2 + 0.5) * 2
        bombers, nBombers = pickFlights(b.pool, share, function(u) return D.round < b.heavy_from_round and HEAVY_UNIT[u] end)
    elseif spk and spk.aircraft then                -- its own aircraft take that many of the round's
        nBombers = SPC.kindValue(spk.aircraft)
    elseif special == "amphibious" and CFG.airfield.enabled and math.random() < CFG.specials.amphibious.bomber_chance then
        raid = true                                   -- a raid on the airfield with the landing (its share of the budget)
        local share = math.floor(budget * b.raid_share / 2 + 0.5) * 2
        bombers, nBombers = pickFlights(b.pool, share, function(u) return D.round < b.heavy_from_round and HEAVY_UNIT[u] end)
    elseif special == "shuttle" then             -- strike flights at the shuttle (heavies only bomb the airfield)
        local share = math.floor(budget * CFG.specials.shuttle.strike_share / 2 + 0.5) * 2
        bombers, nBombers = pickFlights(b.pool, share, function(u) return HEAVY_UNIT[u] end)
    end
    D.strikeUnits = {}                              -- (for the shuttle's countdown log)
    if special == "shuttle" then for _, u in ipairs(bombers) do D.strikeUnits[u] = true end end
    -- allied ships at sea (CFG.allies): a normal round's strike flights at them, each at one ship (ace rounds are their
    -- squadron only)
    D.shipStrike = {}
    local ships = (not raid and not special and not D.roundTier and CFG.allies.enabled and ALLY.shipsAtSea)
        and ALLY.shipsAtSea() or {}
    if #ships > 0 then
        local share = math.floor(budget * CFG.allies.strike_share / 2 + 0.5) * 2
        local sb, sn = pickFlights(b.pool, share, function(u) return HEAVY_UNIT[u] end)
        for _, u in ipairs(sb) do bombers[#bombers + 1] = u; D.shipStrike[u] = ships[math.random(#ships)] end
        nBombers = nBombers + sn
        if #sb > 0 then log(string.format("round %d: %d strike aircraft in %d squadrons go for the allied ships", D.round, sn, #sb)) end
    end
    local nWant = alone and 0 or (budget - nBombers)
    if spk and spk.budget then nWant = spk.budget(budget) end      -- (VALKA's decoys: a few of the round's)
    local fighters, nFighters = pickFlights(CFG.pool, nWant, function(u) return PROBE_OF[u] end)
    D.queue, D.spare = {}, {}
    for _, u in ipairs(fighters) do D.queue[#D.queue + 1] = u end
    for _, u in ipairs(CFG.pool) do                 -- spares: free 2-ship flights, for a flight that fails to spawn
        if not D.up[u] and not PROBE_OF[u] and flightSize(u) == 2 then
            local queued = false
            for _, q in ipairs(D.queue) do if q == u then queued = true end end
            if not queued then D.spare[#D.spare + 1] = u end
        end
    end
    local want = #D.queue
    -- the behaviour probe: round 1's first flight flies the package script, round 2's the run-time one
    local pv = CFG.probe.enabled and CFG.probe.behaviour and ((D.round == 1 and "Pkg") or (D.round == 2 and "Rt"))
    local pu = pv and CFG.probe.units[pv]
    if pu and not D.up[pu] and PR.usable[pv] and (pv == "Pkg" or (CFG.probe.runtime and GLS.injected[PROBE_RT_MODULE])) then
        table.insert(D.queue, 1, pu)
        if #D.queue > want then D.spare[#D.spare + 1] = table.remove(D.queue) end
    end
    for _, u in ipairs(bombers) do D.queue[#D.queue + 1] = u end   -- bombers last, behind their escort
    if spk then table.insert(D.queue, 1, "@" .. special) end   -- the special first (the shuttle sets its strikers' orders)
    log(string.format("round %d: %d aircraft: %d fighters in %d squadrons%s", D.round, nFighters + nBombers, nFighters,
        #fighters, raid and string.format(", bomber raid: %d bombers in %d squadrons", nBombers, #bombers)
        or special and string.format(", special %s: %d strike aircraft in %d squadrons", special, nBombers, #bombers) or ""))
    if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " start") end
    D.state, D.at, D.lastAlive = "spawning", D.now, nil
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
-- A pool flight's index in tools/survival_events.py POOL (its SV_Up_NN flag and RE_SV_FlightOrders_NN event).
local function poolIndex(unit)
    local n, k = unit:match("^ERA_Unit_(%d+)_Dep_Air(%d)$")
    return n and (tonumber(n) - 1) * 3 + tonumber(k) + 1
end

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
        if #D.queue == 0 then D.state = "fighting" end
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
            log(string.format("round %d clear; round %d in %d s", D.round, D.round + 1, CFG.intermission_s))
            addCredits(CFG.credits.round_bonus * D.round, "round " .. D.round .. " cleared")
            if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " clear") end
            D.state, D.at, D.announced = "wait", now + CFG.intermission_s, false
            hudCallout(string.format(CFG.hud.text.complete, D.round),
                       string.format(CFG.hud.text.complete_sub, CFG.intermission_s))
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
    local hp = math.max(0, math.min(CFG.airfield.hp, AF.full - (hits - AF.base) * ac.hit_damage - (AF.bomb - AF.bombBase)))
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
        AF.down, AF.full, AF.base, AF.bombBase, AF.hp = false, ac.repair_hp, hits, AF.bomb, ac.repair_hp
        AF.closePending, AF.closeHeld, AF.closed, RUN.dirty = false, false, false, true
        hudCallout(t.airfield_up, t.airfield_up_sub)
        if reopen and RUN.captured then                -- captured: it opens when it's retaken (AMPH)
            reopen = false; RUN.captured.closed = true
        end
        log("airfield: repaired to " .. ac.repair_hp .. (reopen and (", landing open" .. airfieldEvent("RE_SV_AirfieldOpen")) or ""))
    end
end
