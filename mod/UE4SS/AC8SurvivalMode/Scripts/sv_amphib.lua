-- sv_amphib.lua: the amphibious assault.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- amphibious assault
-- CFG.specials.amphibious; tools/survival_events.py LCAC_* builds the units, paths and records. A lane L is unit
-- SV_Unit_Lcac<L> (four craft, W X Y Z); a craft that reaches the beach sets SV_LcacLand<L><craft> and its troops are
-- SV_Unit_LcacTroops<L><craft>, whose arrival at the runway sets SV_LcacRunway<L><craft>. RUN.amph.troops: the troop
-- units put ashore this run that are still up; RUN.captured: { untilRound, closePending, closed } while the airfield is
-- taken.
do
local function amph() RUN.amph = RUN.amph or { count = 0, troops = {}, capture = 0 }; return RUN.amph end

local function tierPay(base) return (TIER.pay(base * TIER.specialX(), D and D.round and TIER.index(D.round))) end

-- The troop units' actors, as SV_Spawn creates them (spawningUnit is the troop unit then): AMPH.actors[unit] = { actor }
AMPH.actors = {}
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    if u and u == CFG.specials.valka.eml_unit then SPC.V.emlActor = o end      -- VALKA's opener railgun
    if u and u:find("^SV_Unit_LcacTroops") then
        local l = AMPH.actors[u] or {}
        l[#l + 1] = o
        AMPH.actors[u] = l
    end
end)

-- A unit's vehicles alive: SV_UnitAlive, 0 for a unit that's off the list, nil for an error (not counted as kills).
local function aliveOf(unit)
    local n = SV_UnitAlive(unit)
    if n == -7 then return 0 end
    return n >= 0 and n or nil
end

-- Whether a landing can come now (native spawner, a lane not still afloat): startRound asks before it adds the
-- round's extras, so a landing that can't come is a plain normal round.
function AMPH.ready()
    if not nativeReady() then return false end
    for _, l in ipairs(CFG.specials.amphibious.lanes) do
        if (aliveOf("SV_Unit_Lcac" .. l) or 1) <= 0 then return true end
    end
    return false
end

-- Landing craft still on their way in, and troop vehicles ashore and alive.
function AMPH.counts()
    local craft, ashore = 0, 0
    local s = D and D.special and D.special.kind == "amphibious" and D.special
    if s and s.lanes then
        for _, l in pairs(s.lanes) do
            local landed = 0
            for _ in pairs(l.landed) do landed = landed + 1 end
            -- the craft not landed yet, at most those alive (code review of 2026-10-23: alive - landed undercounted
            -- once a landed craft was shot on its way out)
            craft = craft + math.max(0, math.min(l.alive, (l.n or l.alive) - landed))
        end
    end
    for _, t in ipairs(amph().troops) do ashore = ashore + math.max(0, t.alive) end
    return craft, ashore
end

-- The airfield's capture so far, in % (0-100).
function AMPH.capture() return math.min(100, amph().capture or 0) end

-- The round can't end while a craft is still coming in or troops are ashore and the airfield isn't taken.
function AMPH.busy(s)
    local craft, ashore = AMPH.counts()
    return craft > 0 or (ashore > 0 and not RUN.captured)
end

function AMPH.spawn(now)
    local c, t = CFG.specials.amphibious, CFG.hud.text
    if not nativeReady() then return false end
    local A = amph()
    local want = math.min(#c.lanes, c.lanes_first + A.count * c.lanes_more)
    local order = {}
    for _, l in ipairs(c.lanes) do table.insert(order, math.random(#order + 1), l) end
    local s = D.special
    s.lanes, s.state, s.at = {}, "assault", now
    local n = 0
    for _, l in ipairs(order) do
        if n >= want then break end
        local unit = "SV_Unit_Lcac" .. l
        if SV_UnitAlive(unit) > 0 then           -- still afloat from last time: off now, it comes again next time
            local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacRemove" .. l) or "n/a"
            log(string.format("special: lane %s's craft were still up; taken off (%s)", l, tostring(r)))
        else
            local r = SV_Spawn(unit)
            log(string.format("special: landing craft lane %s (%s): %s", l, unit, r > 0 and (r .. " craft") or
                ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
            if r > 0 then s.lanes[l] = { n = r, alive = r, landed = {}, removed = false, at = now }; n = n + 1 end
        end
    end
    if n == 0 then log("special: no landing craft could come; a normal round"); return false end
    A.count = A.count + 1
    hudCallout(t.amphib_go, t.amphib_go_sub)
    log(string.format("special: round %d, amphibious assault on %d lanes", D.round, n))
    return true
end

-- Every second: craft lost (pay), craft landed (their troops ashore), landed craft taken off once they're away.
function AMPH.tick(now, s)
    if s.state ~= "assault" or now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    local c, t = CFG.specials.amphibious, CFG.hud.text
    local f = svFlags() or {}
    for l, lane in pairs(s.lanes) do
        local unit = "SV_Unit_Lcac" .. l
        local alive = lane.removed and 0 or (aliveOf(unit) or lane.alive)
        if alive < lane.alive and not lane.removed then
            local pay = tierPay(c.craft_pay) * (lane.alive - alive)
            addCredits(pay, string.format("landing craft down (lane %s)", l))
            LB.stat("ground", lane.alive - alive)
            log(string.format("special: lane %s: %d landing craft left", l, alive))
        end
        lane.alive = alive
        for _, k in ipairs(c.craft) do
            -- (a flag still 1 from this lane's last assault is reset by its appearance: not read in the first 5 s)
            if now - lane.at >= 5 and (f["SV_LcacLand" .. l .. k] or 0) >= 1 and not lane.landed[k] then
                lane.landed[k] = now
                lane.firstLanded = lane.firstLanded or now
                local tu = "SV_Unit_LcacTroops" .. l .. k
                local r = -100
                if SV_UnitAlive(tu) <= 0 then
                    AMPH.actors[tu] = {}
                    spawningUnit = tu
                    r = SV_Spawn(tu)
                    spawningUnit = nil
                end
                log(string.format("special: lane %s craft %s on the beach; troops %s: %s", l, k, tu,
                    r > 0 and (r .. " vehicle(s) ashore") or (r == -100 and "still up from before" or
                    ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")"))))
                if r > 0 then
                    local A = amph()
                    A.troops[#A.troops + 1] = { unit = tu, alive = r, at = now, lane = l, craft = k }
                    if not s.ashoreSaid then s.ashoreSaid = true; hudCallout(t.ashore, t.ashore_sub) end
                end
            end
        end
        if lane.firstLanded and not lane.removed and now - lane.firstLanded >= c.remove_after_s then
            lane.removed = true                        -- (no pay for these: they got away)
            local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacRemove" .. l) or "n/a"
            log(string.format("special: lane %s's craft are away; taken off (%s)", l, tostring(r)))
        end
    end
end

-- The round is over (nothing coming in, no troops ashore, or the airfield taken): the reward if it held, and craft
-- still afloat taken off.
function AMPH.roundOver(now, s)
    local c, t = CFG.specials.amphibious, CFG.hud.text
    for l, lane in pairs(s.lanes or {}) do
        if not lane.removed and SV_UnitAlive("SV_Unit_Lcac" .. l) > 0 then
            lane.removed = true
            local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacRemove" .. l) or "n/a"
            log(string.format("special: lane %s's craft taken off at the round's end (%s)", l, tostring(r)))
        end
    end
    s.state = "done"
    if not RUN.captured and (amph().capture or 0) > 0 then        -- short of 100: the next landing starts from 0
        log(string.format("special: the capture stopped at %d%%", AMPH.capture()))
        amph().capture = 0
    end
    LB.special("amphibious", not s.captured, now - (s.at or now))
    if not s.captured then
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, "landing repelled")
        hudCallout(t.repelled, string.format(t.repelled_sub, pay))
        log(string.format("special: round %d, the landing was repelled", D.round))
    end
end

local function free(why, removeLeft)
    local cap, t = RUN.captured, CFG.hud.text
    RUN.captured, RUN.dirty = nil, true
    if removeLeft then                                   -- its time is up: the troops still ashore go
        for _, tr in ipairs(amph().troops) do
            if tr.alive > 0 then
                tr.alive, tr.removed = 0, true
                local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacTroopsRemove" .. tr.lane .. tr.craft) or "n/a"
                log(string.format("special: troops %s taken off (%s)", tr.unit, tostring(r)))
            end
        end
    end
    local reopen = cap.closed and not AF.down
    hudCallout(removeLeft and t.freed or t.retaken, t.retaken_sub)
    log("special: the airfield is free again (" .. why .. ")" .. (reopen and (", landing open" .. airfieldEvent("RE_SV_AirfieldOpen")) or ""))
end

-- Every tick, any round: troop vehicles lost (pay), the capture, landing closed under it, and the airfield freed.
function AMPH.runTick(now)
    if not D or not nativeReady() or now < (AMPH.nextAt or 0) then return end
    AMPH.nextAt = now + 1
    local c, t = CFG.specials.amphibious, CFG.hud.text
    local A, ashore, f = amph(), 0, nil
    for _, tr in ipairs(A.troops) do
        if tr.alive > 0 then
            local n = aliveOf(tr.unit) or tr.alive
            if n < tr.alive then
                addCredits(tierPay(c.troop_pay) * (tr.alive - n), "troop vehicle down (" .. tr.unit .. ")")
                LB.stat("ground", tr.alive - n)
                log(string.format("special: troops %s: %d left", tr.unit, n))
            end
            tr.alive = n
            ashore = ashore + n
        end
        -- at the runway (the end of its drive path): its share of the capture, once (troops spawned in the first 2 s
        -- may still read last time's flag, reset by their appearance)
        if tr.alive > 0 and not tr.reached and now - tr.at >= 2 then
            f = f or svFlags() or {}
            if (f["SV_LcacRunway" .. tr.lane .. tr.craft] or 0) >= 1 then
                tr.reached = true
                if not RUN.captured then
                    A.capture = math.min(100, (A.capture or 0) + c.capture_per_troop)
                    RUN.dirty = true
                    hudCallout(t.on_runway, string.format(t.on_runway_sub, A.capture))
                    log(string.format("special: troops %s reached the runway; airfield %d%% captured", tr.unit, A.capture))
                end
            end
        end
    end
    -- every 15 s: a troop vehicle short of the runway that hasn't moved stuck_m in stuck_s (or, with no actor seen,
    -- has been ashore troop_timeout_s) is taken off: no pay, no capture
    for _, tr in ipairs(A.troops) do
        if tr.alive > 0 and not tr.reached and now >= (tr.checkAt or tr.at + 15) then
            tr.checkAt = now + 15
            local at
            for _, o in ipairs(AMPH.actors[tr.unit] or {}) do
                if not at and valid(o) then
                    pcall(function() local v = o:K2_GetActorLocation(); at = { X = v.X, Y = v.Y, Z = v.Z } end)
                end
            end
            local why
            if at then
                local moved = tr.last and math.sqrt((at.X - tr.last.X) ^ 2 + (at.Y - tr.last.Y) ^ 2) / 100 or math.huge
                if moved < c.stuck_m then tr.still = (tr.still or 0) + 15 else tr.still, tr.last = 0, at end
                tr.last = tr.last or at
                if now >= (tr.posAt or 0) then
                    tr.posAt = now + 60
                    log(string.format("special: troops %s at (%.1f, %.1f) km, %.0f m up, %.1f km from the runway%s", tr.unit,
                        at.X / 100000, at.Y / 100000, at.Z / 100, math.sqrt((at.X - c.runway_cm[1]) ^ 2 + (at.Y - c.runway_cm[2]) ^ 2) / 100000,
                        (tr.still or 0) > 0 and string.format(", still for %d s", tr.still) or ""))
                end
                if (tr.still or 0) >= c.stuck_s then why = string.format("hasn't moved in %d s", tr.still) end
            elseif now - tr.at >= c.troop_timeout_s then
                why = string.format("ashore %d s, no actor to watch", math.floor(now - tr.at))
            end
            if why then
                local n = tr.alive
                tr.alive, tr.removed = 0, true
                local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacTroopsRemove" .. tr.lane .. tr.craft) or "n/a"
                hudCallout(t.troops_stuck, string.format(t.troops_stuck_sub, n))
                log(string.format("special: troops %s stuck (%s): taken off (%s)", tr.unit, why, tostring(r)))
                ashore = ashore - n
            end
        end
    end
    local up = {}                                         -- the dead ones out: a later assault's troops on the same
    for _, tr in ipairs(A.troops) do if tr.alive > 0 then up[#up + 1] = tr end end   -- lane / craft can't count them again
    A.troops = up
    if (A.capture or 0) >= 100 and not RUN.captured then
        RUN.captured, RUN.dirty = { untilRound = D.round + c.captured_rounds, closePending = true }, true
        A.capture = 0                                     -- (the meter starts over once it's back in our hands)
        if D.special and D.special.kind == "amphibious" then D.special.captured = true end
        LB.stat("captured", 1)
        hudCallout(t.captured, t.captured_sub)
        log(string.format("special: round %d, the airfield is captured (100%%, %d troop vehicles ashore); back after round %d at the latest",
            D.round, ashore, RUN.captured.untilRound))
    end
    local cap = RUN.captured
    if not cap then return end
    if cap.closePending then
        if playerOnAirfield() then
            if not cap.heldSaid then cap.heldSaid = true; log("special: captured, landing stays open until you take off") end
        else
            cap.closePending = false
            if not AF.closed then cap.closed = true; log("special: landing closed" .. airfieldEvent("RE_SV_AirfieldClose"))
            else cap.closed = true end
        end
    end
    if ashore == 0 then
        free("every landed troop vehicle destroyed", false)
    elseif D.state == "wait" and D.round >= cap.untilRound then
        free(string.format("%d rounds", c.captured_rounds), true)
    end
end
end
