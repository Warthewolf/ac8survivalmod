-- sv_director.lua: the squad director, the behaviour roadmap's P2 ("one Lua part that watches the whole sky and fires
-- remote events on the right plane"; tools/re/BEHAVIOUR_DIRECTOR.md unit 6), and the intensity director, P4 (its own
-- block at the end, CFG.intensity: "pressure follows the player, not the clock"; unit 7).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local (tools/lua_split.py).
--
-- A plane's behaviour tree is fixed when the level loads (hard rule 20), so the director works only through levers
-- already proven, or built for it on the same stock records: the aces' LastTGT on a flight (RE_SV_AceTurn_NN), the Wolf
-- trap's per-object free and turn (sv_spawn.lua WOLF), one plane's missile shot at the player (RE_SV_Salvo_<NN><L>,
-- Mission 19's LiveFireOneShotWeapon on fire-control slot DIR.SALVO_FCS_SLOT: hard rule 40), a flight's engagement held
-- and given back (RE_SV_DirHold_NN: None; RE_SV_DirFree_NN: its appearance's orders) and the spawner's points. Six
-- tactics (CFG.director has their settings and what each does): cover the tailed, spring the trap, bracket salvo, top
-- cover, pincer arrival, regroup. Each comes after its tell (P3, sv_tells.lua: the action its lead_s later), has a
-- cooldown and a budget a round, and is counted and logged by STATS.tactic (a "director:" line; the planes involved
-- tagged p.dirTag = { tactic, at }, which P8's kill bonus pays on).
-- The host's (or solo): DIR.tick runs from sv_main.lua's probeTick every 250 ms (timed "director"), P4's part first; on
-- a co-op joiner only P4's DIR.clientTick (its own scores to the host). A tactic is aimed at a player (COOP.players(): a
-- slot): the host's own through the events above; a joiner, whom LastTGT can't reach (it steers by LocalPlayer, the
-- host's plane here), through a hunt (RE_SV_Hunt_NN, AIFirst: the joiners' planes) with the flight's TargetActor kept on
-- that joiner's stand-in for a while, and a salvo fired on that joiner's own copies ("dv", sv_coop.lua COOP.dispatch).
-- Cheap (the contract's perf rules): positions from the 2 s sweep's p.at, fresh reads for at most `reads` planes a tick
-- (the ones being tailed first, then the nearest to a player; kept in p.pose, which the tail watch reuses), at most one
-- tactic started a tick, decisions logged, never ticks.
--   DIR.tick(now, paused)             every tick (sv_main.lua, after ACE.movesTick)
--   DIR.roundStart(now)               startRound's end (sv_rounds.lua): the round's budgets
--   DIR.wave(now)                     a wave's start (startRound, the "wave" branch): a pincer, maybe
--   DIR.spawnAt(unit)                 spawnFlight: a pincer flight's spawn point, or nil
--   DIR.spawned(unit, role, n, ace)   spawnFlight: a flight is up (top cover and regroup watch it)
--   DIR.holding(unit)                 a flight the director holds back (hunts and the aces' moves leave it alone)
--   DIR.aimed(p)                      a plane whose TargetActor the director keeps on a joiner (ACE.hunt leaves it)
--   DIR.release(unit, why)            let a held flight go now (P4: "the director ... releases a held flight")
--   DIR.push(slot, why, km)           P4's push on a comfortable player: a held top cover dives, else a flight turns in
--   DIR.holds()                       the holds in force, RE_SV_DirHold_NN (sv_coop.lua: a joiner who links later)
--   P4 (below): DIR.level, DIR.holdWave, DIR.gap, DIR.holdOn, DIR.pressure, DIR.hot, DIR.intensityTick, DIR.clientTick
DIR = { SALVO_FCS_SLOT = 2 }   -- (the fighters' missile slot, WN_WEAPON_3; tools/survival_events.py SALVO_SLOT checks it)

do
local ROOM_TACTIC = { top_cover = true, pincer = true, regroup = true }  -- (budgets the room's, not each player's)
local TAIL_GRACE_S = 1.0                                   -- (off its tail this long: the tail episode ends)
local TARGET = nil                                         -- (FName("TargetActor"), made at the first write)

local function cfg() return CFG.director or {} end
local function on() local c = CFG.director; return c ~= nil and c.enabled ~= false end
local function tc(name) local t = cfg()[name]; return type(t) == "table" and t or {} end
local function tacticOn(name) return on() and tc(name).enabled ~= false end
local function client() return (COOP and COOP.client and COOP.client()) and true or false end
local function letter(k) return string.char(65 + k) end
local function num(v, d) return tonumber(v) or d end
local function alive(u)
    local ok, n = pcall(SV_UnitAlive, u)
    return (ok and type(n) == "number") and n or 0
end
local function angle(ax, ay, az, bx, by, bz)          -- between two vectors, degrees (180 when one has no length)
    local la, lb = math.sqrt(ax * ax + ay * ay + az * az), math.sqrt(bx * bx + by * by + bz * bz)
    if la == 0 or lb == 0 then return 180 end
    return math.deg(math.acos(math.max(-1, math.min(1, (ax * bx + ay * by + az * bz) / (la * lb)))))
end
-- fire remote event ev (the global SV_Event at call time: sv_coop wraps it after this part loads, and forwards what
-- isn't kept): what happened, for the log, and whether it fired
local function fire(ev)
    local ok, r = pcall(function() return type(SV_Event) == "function" and SV_Event(ev) or -5 end)
    if not ok then return "error " .. tostring(r), false end
    if r == 1 then return "fired", true end
    return "not fired: " .. tostring(SV_ERR and SV_ERR[r] or r), false
end

-- this run's state (D.dir: a new level or run clears it with D)
local function st()
    if not D then return nil end
    local s = D.dir
    if not s then
        s = { spent = {}, next = {}, held = {}, aims = {}, after = {}, spawns = {}, said = {}, engaged = {}, rr = 0, factor = 1 }
        D.dir = s
    end
    return s
end

---------------------------------------------------------------------------------------------------- budgets, cooldowns
-- a tactic's budget this round: CFG.director.budget's band of the latest from_round reached, cover and trap x the
-- habit counter's factor (P6: D.counter.tail, more of them against a tail chaser; the critic's gap fill), the top cover
-- x its own (P6: D.counter.top, more of it against a player who stays high; the U8 review)
local function bandOf(round)
    local i = 0
    for k, r in ipairs((cfg().budget or {}).from_round or {}) do if (round or 0) >= (tonumber(r) or math.huge) then i = k end end
    return i
end
local function factor(s, tactic)
    if tactic == "cover" or tactic == "trap" then return s.factor or 1 end
    return tactic == "top_cover" and (s.topFactor or 1) or 1
end
local function budgetOf(s, tactic)
    local list, i = (cfg().budget or {})[tactic], bandOf(D.round)
    local n = (type(list) == "table" and i > 0) and num(list[i], 0) or 0
    return math.floor(n * factor(s, tactic) + 0.5)
end
local function keyOf(tactic, slot) return ROOM_TACTIC[tactic] and "room" or tostring(slot or 0) end
-- why tactic can't be started (for player slot) now, or nil: its budget, its cooldown, the director's gap (noGap: not
-- counted, for the room's tactics that aren't a moment: a pincer, a top cover's hold)
local function blockedBy(s, tactic, slot, now, noGap)
    if not tacticOn(tactic) then return "off" end
    local key = keyOf(tactic, slot)
    local used, max = (s.spent[key] and s.spent[key][tactic]) or 0, budgetOf(s, tactic)
    if max <= 0 then return "off" end                -- (none this round band: not logged)
    if used >= max then return string.format("its budget, %d of %d this round", used, max) end
    local t = s.next[key .. "|" .. tactic]
    if t and now < t then return string.format("its cooldown, %.0f s more", t - now) end
    if not noGap and s.lastAt and now - s.lastAt < num(cfg().gap_s, 0) then
        return string.format("the director's gap, %.1f s after its last", now - s.lastAt)
    end
    -- (P4: no new pressure on a player the intensity director has above its high mark, CFG.intensity.hold.tactics)
    local hot = slot ~= nil and not ROOM_TACTIC[tactic] and DIR.hot and DIR.hot(slot)
    if hot then return string.format("under pressure: intensity %.0f", hot) end
    return nil
end
local function spend(s, tactic, slot, now, noGap)
    local key = keyOf(tactic, slot)
    s.spent[key] = s.spent[key] or {}
    s.spent[key][tactic] = (s.spent[key][tactic] or 0) + 1
    local cd = num(cfg().cooldown_s and cfg().cooldown_s[tactic], 0)
    s.next[key .. "|" .. tactic] = now + cd / factor(s, tactic)
    if not noGap then s.lastAt = now end
end
-- a tactic held back: once a round per tactic, player and kind of reason
local function refuse(s, tactic, slot, why)
    if why == "off" or tostring(why):sub(1, 5) == "off (" then return end   -- (no budget this round band: not logged)
    local key = tactic .. "|" .. tostring(slot) .. "|" .. (tostring(why):match("^[%a ']+") or tostring(why))
    if s.said[key] == D.round then return end
    s.said[key] = D.round
    log(string.format("director: %s%s not now (%s)", tactic,
        (slot and COOP and COOP.open) and string.format(" for player %d", slot + 1) or "", tostring(why)))
end

---------------------------------------------------------------------------------------------------- players, tells
-- the players a tactic may be aimed at (COOP.players(): you first, then the others; solo or the Offline edition: you):
-- alive, flying, their state fresh (flying()); past CFG.director.players, you and the others round-robin (players(s))
local function flying()
    local all = nil
    if COOP and COOP.players then
        local ok, l = pcall(COOP.players)
        if ok and type(l) == "table" then all = l end
    end
    if not all then
        local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
        local at = valid(pawn) and playerLocation() or nil
        all = {}
        if at then
            local okA, onA = pcall(playerOnAirfield, at)
            all[1] = { slot = 0, isMe = true, obj = pawn, at = at, fresh = true, alive = true, onAirfield = okA and onA == true }
        end
    end
    local out = {}
    for _, e in ipairs(all) do
        if e.at and e.alive ~= false and e.fresh ~= false and not e.onAirfield then out[#out + 1] = e end
    end
    return out
end
local function players(s)
    local out = flying()
    local max = math.max(1, math.floor(num(cfg().players, 4)))
    if #out <= max then return out end
    local pick, rest = {}, {}
    for _, e in ipairs(out) do if e.isMe then pick[#pick + 1] = e else rest[#rest + 1] = e end end
    local n = math.min(#rest, max - #pick)
    for i = 1, n do pick[#pick + 1] = rest[(s.rr + i - 1) % #rest + 1] end
    s.rr = (s.rr + n) % math.max(1, #rest)
    return pick
end
local function tellSlot(e)                           -- (TELL's: nil this game's player, a joiner's slot, or every player)
    if e == nil then return TELL and TELL.ALL or "all" end
    if e.isMe then return nil end
    return e.slot
end
local function who(e) return (e and COOP and COOP.open) and string.format("player %d", e.slot + 1) or "you" end
-- whether its tell can be said to player e (nil: every player) now (CFG.director.need_tell; tells off on this game,
-- for its own player: the tactic goes without one, as TELL.after does)
local function tellReady(id, e)
    if not cfg().need_tell or not (TELL and TELL.ready) then return true end
    local tellsOn = CFG.tells and CFG.tells.enabled
    local host = COOP and COOP.host and COOP.host()
    if not tellsOn and (e == nil and not host or (e and e.isMe)) then return true end
    local ok, r = pcall(TELL.ready, id, tellSlot(e))
    return ok and r == true
end
local function tellSay(id, e, a, b)
    if not (TELL and TELL.say) or not id or id == "" then return false end
    local ok, r = pcall(TELL.say, id, tellSlot(e), a, b)
    return ok and r == true
end
-- its tell, then fn its lead_s later (TELL.after; no TELL: at once). Whether the tell was said
local function tellAfter(id, e, fn, a, b)
    if not (TELL and TELL.after) then
        local ok, err = pcall(fn)
        if not ok then log("director: " .. id .. "'s action failed: " .. tostring(err)) end
        return false
    end
    local ok, r = pcall(TELL.after, id, tellSlot(e), fn, a, b)
    return ok and r == true
end

---------------------------------------------------------------------------------------------------- planes
-- a pool fighter of a round (not a bomber, not the probes'), alive as the sweep last saw it
local function poolPlane(p)
    local u = p.unit
    return not p.down and u ~= nil and poolIndex(u) ~= nil and not BOMBER_UNIT[u] and not PROBE_OF[u] and valid(p.obj)
end
local function decoyed(u, now) return (TAC and TAC.decoyed and TAC.decoyed(u, now)) and true or false end
local function heldTrap(u, k) local w = D.wolf and D.wolf[u]; return w ~= nil and k ~= nil and w.held[k] == true end
local function busy(s, u, now) return s.held[u] ~= nil or s.aims[u] ~= nil or decoyed(u, now) end
-- its position and heading now (a fresh read, at most rb.n a tick; one read this tick is shared: p.pose, which the
-- tail watch, sv_stats.lua, uses too)
local function pose(p, now, rb)
    local q = p.pose
    if q and q.t == now then return q end
    if rb.n <= 0 then return nil end
    rb.n = rb.n - 1
    local ok, at, fwd = pcall(function()
        local v, f = p.obj:K2_GetActorLocation(), p.obj:GetActorForwardVector()
        return { X = v.X, Y = v.Y, Z = v.Z }, { X = f.X, Y = f.Y, Z = f.Z }
    end)
    if not (ok and at and fwd) then return nil end
    q = { t = now, at = at, fwd = fwd }
    p.pose = q
    return q
end
-- your damage (or a joiner's: "wingmate" on the host) on flight unit's live planes so far
local function hits(unit)
    local n = 0
    for _, p in ipairs(planes) do
        if p.unit == unit and p.dmg then n = n + (p.dmg.you or 0) + (p.dmg.wingmate or 0) end
    end
    return n
end
-- another flight of the round, one the director doesn't hold, still has a plane up (two held flights don't keep each
-- other back: the round, or the wave's next, waits on them)
local function othersUp(s, unit)
    for _, p in ipairs(planes) do
        if not p.down and p.unit and p.unit ~= unit and D.up and D.up[p.unit] and not s.held[p.unit] then return true end
    end
    return false
end
local function nearestOf(unit, at)                   -- flight unit's live plane nearest `at` (the sweep's positions)
    local best, bd
    for _, p in ipairs(planes) do
        if not p.down and p.unit == unit and p.at then
            local d = km(p.at, at)
            if not bd or d < bd then best, bd = p, d end
        end
    end
    return best, bd
end
local function nearestPlayer(unit, ps)
    local best, bd
    for _, e in ipairs(ps) do
        local _, d = nearestOf(unit, e.at)
        if d and (not bd or d < bd) then best, bd = e, d end
    end
    return best, bd
end

---------------------------------------------------------------------------------------------------- holds, aims, orders
-- a joiner's flight: its TargetActor kept on that player's stand-in for secs (every second: aimsTick; ACE.hunt leaves
-- it, DIR.aimed); k: one plane of it only. restore: the flight's orders back when it's over (it was sent hunting)
local function aim(s, unit, k, e, secs, why, restore)
    if not (e and e.obj and valid(e.obj)) then
        log(string.format("director: %s can't be aimed at %s (no stand-in plane here)", unit, who(e)))
        return
    end
    s.aims[unit] = { k = k, slot = e.slot, obj = e.obj, untilT = D.now + num(secs, 20), why = why, restore = restore }
end
-- a flight's engagement back: RE_SV_DirFree_NN (its appearance's orders: air-only search, PlayerOnlyNoLimit; forwarded,
-- so a joiner's copies too), then, aimed at a joiner (e) or for one of the co-op host's split-hunt flights
-- (COOP.hunted), RE_SV_Hunt_NN again (Normal / AIFirst: the joiners' planes; the host's only). Whether it went: never
-- while your DECOY stands the flight down (a unit-wide order would end the item you paid for early, here and on the
-- joiners' copies): its end (RE_SV_DecoyEnd_NN, this game's planes) comes first, then ours (s.after: afterTick)
local function orders(s, unit, e, why)
    local i = poolIndex(unit)
    if not i then return false end
    if decoyed(unit, D.now) then
        s.after[unit] = tostring(why)
        log(string.format("director: %s stays down with your decoy (%s): its orders back at the decoy's end", unit, tostring(why)))
        return false
    end
    local parts = {}
    local ev = string.format("RE_SV_DirFree_%02d", i)
    parts[#parts + 1] = ev .. " " .. (fire(ev))
    local hunted = COOP and COOP.hunted and COOP.hunted(unit)
    if (e and not e.isMe) or hunted then
        local h = string.format("RE_SV_Hunt_%02d", i)
        parts[#parts + 1] = h .. " " .. (fire(h))
    end
    log(string.format("director: %s back in the fight (%s): %s", unit, tostring(why), table.concat(parts, ", ")))
    return true
end
local function hold(s, unit, kind, now, why, secs)
    local ev = string.format("RE_SV_DirHold_%02d", poolIndex(unit))
    local res, ok = fire(ev)
    if ok then s.held[unit] = { kind = kind, at = now, untilT = secs and now + secs or nil, dmg = hits(unit), why = why } end
    log(string.format("director: %s: %s %s (%s %s)", why, unit,
        kind == "top" and "held at engagement None until you're in a fight" or string.format("breaks off for %.0f s", secs or 0),
        ev, res))
    return ok
end
-- held flight unit back in the fight (e: aimed at that player; a joiner's: its TargetActor on them for aim_s). Whether
-- it was let go: inside your decoy it stays held (a dive's tell said or not), and heldTick lets it go at the decoy's end
local function release(s, unit, why, e)
    local h = s.held[unit]
    if h and decoyed(unit, D.now) then
        h.decoy = D.decoyed and D.decoyed[unit]
        if not h.decoySaid then
            h.decoySaid = true
            log(string.format("director: %s stays down with your decoy (%s): let go at its end", unit, tostring(why)))
        end
        return false
    end
    s.held[unit] = nil
    if orders(s, unit, e, why) and e and not e.isMe then aim(s, unit, nil, e, tc("top_cover").aim_s, h and h.why or why, true) end
    return true
end
-- the orders put off by your decoy (orders' s.after), once it's over: RE_SV_DecoyEnd_NN gave this game's planes theirs
-- back; RE_SV_DirFree_NN (forwarded) frees a joiner's copies too, a split-hunt flight's hunt again
local function afterTick(s, now)
    for unit, why in pairs(s.after) do
        if alive(unit) <= 0 then s.after[unit] = nil
        elseif not decoyed(unit, now) then
            s.after[unit] = nil
            orders(s, unit, nil, why .. ", after your decoy")
        end
    end
end
local function aimsTick(s, now)
    for unit, a in pairs(s.aims) do
        if now >= a.untilT or alive(unit) <= 0 or decoyed(unit, now) then   -- (your decoy: it's stood down, the aim's over)
            s.aims[unit] = nil
            if a.restore and alive(unit) > 0 then orders(s, unit, nil, a.why .. ": its aim on player " .. (a.slot + 1) .. " over") end
        else
            local n = 0
            for _, p in ipairs(planes) do
                if not p.down and p.unit == unit and (a.k == nil or p.k == a.k) and valid(p.obj) and valid(a.obj) then
                    local ok = pcall(function()
                        TARGET = TARGET or FName("TargetActor")
                        p.obj.AIStateComponent.BlackboardComponent:SetValueAsObject(TARGET, a.obj)
                    end)
                    if ok then n = n + 1 end
                end
            end
            if not a.said then
                a.said = true
                log(string.format("director: %s%s's TargetActor kept on player %d's plane for %.0f s (%d planes; %s)", unit,
                    a.k and (" " .. letter(a.k)) or "", a.slot + 1, a.untilT - now, n, a.why))
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- cover the tailed
-- the flight that covers plane p for player e: the nearest plane of another pool flight within cover.range_km of e that
-- may turn (a duelist's or an ace squadron's: a Lancer, Wolf or Skirmisher flight keeps its role, ROLE.ownSet; not an
-- escort over the airfield, whose small area beats the move, nor the jammer's, nor one held, aimed, decoyed, holding its
-- Wolf trap or still in a reversal, D.aceMoveAt, shared with ACE.movesTick). rng: another range (P4's push, with p a
-- plane of no flight: {})
local function coverer(s, p, e, now, rng)
    rng = rng or num(tc("cover").range_km, 6)
    local best, bd
    D.aceMoveAt = D.aceMoveAt or {}
    for _, q in ipairs(planes) do
        local u = q.unit
        if q ~= p and u ~= p.unit and q.at and poolPlane(q) and not (ROLE and ROLE.ownSet and ROLE.ownSet(u))
            and not (D.escortUnits and D.escortUnits[u]) and not (D.jammer and D.jammer.unit == u) and not busy(s, u, now)
            and not (WOLF and WOLF.holding and WOLF.holding(u)) and now >= (D.aceMoveAt[u] or 0) then
            local d = km(q.at, e.at)
            if d <= rng and (not bd or d < bd) then best, bd = q, d end
        end
    end
    return best, bd
end
local function doCover(s, p, e, q, d, held, now)
    local c, unit, slot = tc("cover"), q.unit, e.slot
    local i = poolIndex(unit)
    spend(s, "cover", slot, now)
    local lead = (TELL and TELL.leadS) and num(TELL.leadS("six"), 0) or 0
    D.aceMoveAt[unit] = now + lead + num(c.move_s, 30)      -- (one LastTGT takes ~25-30 s: not cut by a new request)
    local fn
    if e.isMe then
        local ev = string.format("RE_SV_AceTurn_%02d", i)
        fn = function() log(string.format("director: cover: %s %s", ev, (fire(ev)))) end
    else                                              -- (a joiner: LastTGT would turn onto the host)
        fn = function()
            if alive(unit) <= 0 then return end
            local h = string.format("RE_SV_Hunt_%02d", i)
            log(string.format("director: cover for player %d: %s %s", slot + 1, h, (fire(h))))
            aim(s, unit, nil, e, c.aim_s, "cover", true)
        end
    end
    local said = tellAfter("six", e, fn)
    pcall(STATS.tactic, "cover", unit, slot, string.format("%s (%s) had %s on its tail %.1f s at %.0f m; %s %.1f km away turns in",
        p.name, p.unit, who(e), held, p.dirTail and p.dirTail.m or 0, q.name, d), said and "six" or nil)
end

---------------------------------------------------------------------------------------------------- spring the trap
-- a Wolf bait (an even plane of a Wolf flight) whose own wingman (the next plane) is held: chased long enough, the trap
-- springs (WOLF.free with the turn: RE_SV_WolfFree + RE_SV_WolfTurn on that plane; a joiner's: the free, its
-- TargetActor on them)
local function trapBait(p, now)
    return p.k ~= nil and p.k % 2 == 0 and ROLE and ROLE.flight and ROLE.flight(p.unit) == "wolf"
        and heldTrap(p.unit, p.k + 1) and not decoyed(p.unit, now)
end
local function doTrap(s, p, e, held, now)
    local unit, k = p.unit, p.k + 1
    spend(s, "trap", e.slot, now)
    local fn = function()
        local okF, n = pcall(WOLF.free, unit, "the director's spring: you chased bait " .. letter(p.k), e.isMe == true, k, D and D.now)
        if okF and (n or 0) > 0 and not e.isMe then aim(s, unit, k, e, tc("trap").aim_s, "the trap", false) end
    end
    local said = tellAfter("trap", e, fn)
    pcall(STATS.tactic, "trap", unit, e.slot, string.format("%s chased bait %s (%s) %.1f s: its wingman %s springs",
        who(e), letter(p.k), p.name, held, letter(k)), said and "trap" or nil)
end

---------------------------------------------------------------------------------------------------- bracket salvo
-- may plane p fire the salvo: its row's first missile slot is DIR.SALVO_FCS_SLOT (searchSetup's SR.mslSlot; the lead's
-- own row when it has one, D.leadRow), it has an index in its flight, isn't a held Wolf trap, its flight isn't held
local function salvoOk(s, p, now)
    if not p.k or p.k > 5 or heldTrap(p.unit, p.k) or busy(s, p.unit, now) then return false end
    local lr = p.k == 0 and D.leadRow and D.leadRow[p.unit]
    local row = (lr and lr.row) or (D.flightRow and D.flightRow[p.unit])
    return row ~= nil and SR and SR.mslSlot ~= nil and SR.mslSlot[row] == DIR.SALVO_FCS_SLOT
end
local function salvoName(p) return string.format("RE_SV_Salvo_%02d%s", poolIndex(p.unit), letter(p.k)) end
-- the pair of shooters around player e whose bearings from e are sep_deg apart (the nearest to 90), or nil
local function bestPair(list, e, lo, hi)
    local best, ba, bb, bs
    for i = 1, #list - 1 do
        for j = i + 1, #list do
            local a, b = list[i].pose.at, list[j].pose.at
            local sep = angle(a.X - e.at.X, a.Y - e.at.Y, a.Z - e.at.Z, b.X - e.at.X, b.Y - e.at.Y, b.Z - e.at.Z)
            if sep >= lo and sep <= hi and (not best or math.abs(sep - 90) < best) then
                best, ba, bb, bs = math.abs(sep - 90), list[i], list[j], sep
            end
        end
    end
    return ba, bb, bs
end
local function doBracket(s, a, b, e, sep, now)
    spend(s, "bracket", e.slot, now)
    local evs = { salvoName(a), salvoName(b) }
    local said
    if e.isMe or not (COOP and COOP.dispatch) then
        said = tellAfter("bracket", e, function()
            local out = {}
            for j, p in ipairs({ a, b }) do
                if not p.down and valid(p.obj) then out[#out + 1] = evs[j] .. " " .. (fire(evs[j])) end
            end
            log("director: bracket: " .. (#out > 0 and table.concat(out, ", ") or "both down before the shot"))
        end)
    else                                              -- (a joiner: its own copies fire at it, the tell's lead timed there)
        said = tellSay("bracket", e)
        local delay = (said and TELL and TELL.leadS) and num(TELL.leadS("bracket"), 0) or 0
        local out = {}
        for j, p in ipairs({ a, b }) do
            local okD, sent = pcall(COOP.dispatch, e.slot, evs[j], p.unit, delay)
            out[#out + 1] = evs[j] .. ((okD and sent) and " sent" or " not sent")
        end
        log(string.format("director: bracket on player %d's copies in %.1f s (\"dv\"): %s", e.slot + 1, delay, table.concat(out, ", ")))
    end
    local tag = { tactic = "bracket", at = now }
    a.dirTag, b.dirTag = tag, tag                      -- (the two shooters only: STATS.tactic tags a whole flight)
    pcall(STATS.tactic, "bracket", nil, e.slot, string.format("%s (%s) and %s (%s), %.0f deg apart around %s", a.name, a.unit,
        b.name, b.unit, sep, who(e)), said and "bracket" or nil)
end

---------------------------------------------------------------------------------------------------- the 4 Hz part
-- every tick: the planes near a player read afresh (tailed ones first), who's on whose tail (cover, trap), who could
-- bracket whom; at most one tactic started
local function fastTick(s, now, ps)
    local c, cc, ct, cb = cfg(), tc("cover"), tc("trap"), tc("bracket")
    local nearKm = num(c.near_km, 6)
    local tailM, tailDeg = num(cc.tail_km, 3) * 1000, num(cc.tail_deg, 70)
    local cand = {}
    for _, p in ipairs(planes) do
        if p.at and poolPlane(p) then
            local bd, be
            for _, e in ipairs(ps) do local d = km(p.at, e.at); if not bd or d < bd then bd, be = d, e end end
            if bd and bd <= nearKm then
                -- (likely on its tail, read first: an episode open, the sweep's own test, or its last pose against the
                -- nearest player now, with some slack; no read)
                local likely = p.dirTail ~= nil or p.tailing == true
                if not likely and p.fwd and bd * 1000 <= tailM * 1.5 then
                    likely = angle(-p.fwd.X, -p.fwd.Y, -p.fwd.Z, be.at.X - p.at.X, be.at.Y - p.at.Y, be.at.Z - p.at.Z) <= tailDeg + 20
                end
                p.dirKm, p.dirLikely = bd, likely
                cand[#cand + 1] = p
            elseif p.dirTail then p.dirTail = nil end
        elseif p.dirTail then p.dirTail = nil end
    end
    if #cand == 0 then return end
    table.sort(cand, function(x, y)
        if x.dirLikely ~= y.dirLikely then return x.dirLikely end
        return x.dirKm < y.dirKm
    end)
    local rb = { n = math.max(0, math.floor(num(c.reads, 8))) }
    local brM, noseDeg = num(cb.range_km, 4) * 1000, num(cb.nose_deg, 60)
    local shooters, tailed = {}, {}
    for _, p in ipairs(cand) do
        local q = pose(p, now, rb)
        if not q and rb.n <= 0 then break end
        if q then
            local tBy, tM
            for i, e in ipairs(ps) do
                local dx, dy, dz = e.at.X - q.at.X, e.at.Y - q.at.Y, e.at.Z - q.at.Z
                local m = math.sqrt(dx * dx + dy * dy + dz * dz) / 100
                if m <= tailM and angle(-q.fwd.X, -q.fwd.Y, -q.fwd.Z, dx, dy, dz) <= tailDeg and (not tM or m < tM) then tBy, tM = e, m end
                if m <= brM and angle(q.fwd.X, q.fwd.Y, q.fwd.Z, dx, dy, dz) <= noseDeg and salvoOk(s, p, now) then
                    shooters[i] = shooters[i] or {}
                    table.insert(shooters[i], p)
                end
            end
            local t = p.dirTail
            if tBy then
                if not (t and t.slot == tBy.slot) then t = { slot = tBy.slot, at = now }; p.dirTail = t end
                t.last, t.m, t.e = now, tM, tBy
                tailed[#tailed + 1] = p
            elseif t and now - (t.last or now) > TAIL_GRACE_S then
                p.dirTail = nil
            end
        end
    end
    -- you on a plane's tail: a Wolf bait's trap springs, any other plane's flight is covered
    for _, p in ipairs(tailed) do
        local t = p.dirTail
        local e, held = t.e, now - t.at
        if trapBait(p, now) then
            if tacticOn("trap") then
                if not t.warned and held >= num(ct.drag_s, 1) and not blockedBy(s, "trap", e.slot, now, true) then
                    t.warned = true
                    tellSay(ct.warn, e)                  -- ("he's dragging you": its pre-tell)
                end
                if held >= num(ct.spring_s, 2.5) then
                    local why = blockedBy(s, "trap", e.slot, now) or (not tellReady("trap", e) and "its tell can't be said now") or nil
                    if why then refuse(s, "trap", e.slot, why)
                    else doTrap(s, p, e, held, now); t.at, t.warned = now, nil; return end
                end
            end
        elseif tacticOn("cover") and held >= num(cc.ask_s, 1.5) then
            local q, d = coverer(s, p, e, now)
            if not t.asked and q and not blockedBy(s, "cover", e.slot, now, true) then
                t.asked = true
                tellSay("cover_ask", e)                  -- (the tailed one calls for help)
            end
            if held >= num(cc.tail_s, 3) then
                local why = blockedBy(s, "cover", e.slot, now) or (not q and string.format("no flight within %.0f km to cover %s",
                    num(cc.range_km, 6), p.name)) or (not tellReady("six", e) and "its tell can't be said now") or nil
                if why then refuse(s, "cover", e.slot, why)
                else doCover(s, p, e, q, d, held, now); t.at, t.asked = now, nil; return end
            end
        end
    end
    -- two of them around a player: the bracket
    if tacticOn("bracket") then
        local sep = cb.sep_deg or {}
        local lo, hi = num(sep[1], 60), num(sep[2], 120)
        for i, e in ipairs(ps) do
            local list = shooters[i]
            if list and #list >= 2 then
                local a, b, sp = bestPair(list, e, lo, hi)
                if a then
                    local why = blockedBy(s, "bracket", e.slot, now) or (not tellReady("bracket", e) and "its tell can't be said now") or nil
                    if why then refuse(s, "bracket", e.slot, why) else doBracket(s, a, b, e, sp, now); return end
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- top cover
-- a flight top cover may hold: a Lancer flight (top_cover.roles; with roles off, any, when any_without_roles)
local function topRole(unit)
    local c = tc("top_cover")
    local r = ROLE and ROLE.flight and ROLE.flight(unit)
    if r then
        for _, x in ipairs(c.roles or {}) do if x == r then return true end end
        return false
    end
    return not (ROLE and ROLE.live) and c.any_without_roles == true
end
-- the o'clock (1-12) of `at` from player e's heading (12 ahead, 3 on the right; level): your pawn's forward vector,
-- a joiner's yaw from its state
local function oclock(e, at)
    local yaw
    if e.isMe then
        local ok, f = pcall(function() local v = e.obj:GetActorForwardVector(); return { X = v.X, Y = v.Y } end)
        if ok and f and (f.X ~= 0 or f.Y ~= 0) then yaw = math.deg(math.atan(f.Y, f.X)) end
    elseif type(e.rot) == "table" then yaw = tonumber(e.rot[2]) end
    if not yaw then return 12 end
    local rel = (math.deg(math.atan(at.Y - e.at.Y, at.X - e.at.X)) - yaw) % 360
    local h = math.floor(rel / 30 + 0.5) % 12
    return h == 0 and 12 or h
end
DIR.oclock = oclock                                  -- (P9's squadrons: a dive opener's o'clock, sv_ai.lua ACE.squadTick)
local function dive(s, unit, e, now, why)
    local h = s.held[unit]
    if not h then return false end
    h.diving = true
    s.lastAt = now
    local p = nearestOf(unit, e.at)
    local clock = p and oclock(e, p.at) or 12
    local said = tellAfter("dive", e, function() if s.held[unit] then release(s, unit, why, e) end end, clock)
    pcall(STATS.tactic, "top_cover", unit, e.slot, string.format("%s; it dives on %s from %d o'clock", why, who(e), clock),
        said and "dive" or nil)
    return true
end
local function topTick(s, now, ps)
    local c = tc("top_cover")
    local flags = nil
    -- a flight that came up and is the kind to hold: held once its orders are in (they come 2 s after it spawns and
    -- would undo an earlier hold: hard rule 26)
    for unit, sp in pairs(s.spawns) do
        if sp.top == nil then
            if not (tacticOn("top_cover") and topRole(unit)) or sp.ace or (D.escortUnits and D.escortUnits[unit])
                or (D.jammer and D.jammer.unit == unit) then
                sp.top = false
            else
                if not sp.upAt then
                    flags = flags or svFlags() or {}
                    if (flags[string.format("SV_Up_%02d", poolIndex(unit))] or 0) >= 1 then sp.upAt = now end
                end
                if sp.upAt and now >= sp.upAt + num(c.hold_after_s, 3) then
                    local why = blockedBy(s, "top_cover", nil, now, true)
                        or (not othersUp(s, unit) and "it's the only flight up") or (busy(s, unit, now) and "it's in hand already") or nil
                    sp.top = false
                    if why then refuse(s, "top_cover", nil, why .. " (" .. unit .. ")")
                    elseif hold(s, unit, "top", now, "top cover") then spend(s, "top_cover", nil, now, true); sp.top = true end
                elseif not sp.upAt and now - sp.at > 30 then
                    sp.top = false
                end
            end
        end
    end
end
-- held flights: a top cover dives once a player has fought another flight engaged_s (within engage_km) and it's been
-- held min_s; it's let go quietly at max_s, when hit, as the round's last flight (no flight up but held ones, whatever
-- the round's state: in "wave" the next wave waits on the planes left, held or not, and with waves.timeout_s 0 it would
-- never come; not while a wave's flights are still spawning) or at your decoy's end (RE_SV_DirFree_NN then too: the
-- decoy's own end is this game's, and a joiner's copies were held by the forwarded hold). A regroup ends after hold_s
-- (or when hit).
local function heldTick(s, now, ps)
    if not next(s.held) then s.engaged = {}; return end
    local c = tc("top_cover")
    local engKm = num(c.engage_km, 3)
    for _, e in ipairs(ps) do                         -- (each player fighting a flight that isn't held, since when)
        local eng = false
        for _, p in ipairs(planes) do
            if not p.down and p.at and p.unit and not s.held[p.unit] and poolIndex(p.unit) and km(p.at, e.at) <= engKm then eng = true; break end
        end
        if eng then s.engaged[e.slot] = s.engaged[e.slot] or now else s.engaged[e.slot] = nil end
    end
    for unit, h in pairs(s.held) do
        local held = now - h.at
        if alive(unit) <= 0 then
            s.held[unit] = nil
            log(string.format("director: %s down while held (%s)", unit, h.why))
        elseif decoyed(unit, now) then
            h.decoy = D.decoyed and D.decoyed[unit]      -- (its end, RE_SV_DecoyEnd_NN, gives it its orders back)
        elseif h.decoy and now >= h.decoy then
            s.held[unit] = nil
            orders(s, unit, nil, h.why .. ", freed by your decoy's end")
        elseif h.diving then                          -- (its tell said: it goes after the lead)
        elseif hits(unit) > (h.dmg or 0) then
            release(s, unit, "you hit it while it was held")
        elseif not othersUp(s, unit) and not (D.state == "spawning" and D.queue and #D.queue > 0) then
            release(s, unit, string.format("the round's last flight (%s)", tostring(D.state)))
        elseif h.kind == "top" and DIR.holdOn and DIR.holdOn(now) then
            -- (P4's intensity hold: its dive and its max_s wait for the hold's end, 30 s at most; hit, or the last
            -- flight up, it still goes, above)
            if h.intHold ~= DIR.holdOn(now) then
                h.intHold = DIR.holdOn(now)
                log(string.format("director: %s (top cover) waits for the intensity hold (%.0f s more)", unit, h.intHold - now))
            end
        elseif h.kind == "regroup" then
            if now >= (h.untilT or now) then release(s, unit, "regrouped") end
        elseif held >= num(c.max_s, 45) then
            release(s, unit, string.format("held %.0f s", held))
        elseif held >= num(c.min_s, 8) then
            local best, since = nil, nil
            for _, e in ipairs(ps) do
                local t = s.engaged[e.slot]
                if t and now - t >= num(c.engaged_s, 3) and (not since or t < since) then best, since = e, t end
            end
            if best then
                local why = (s.lastAt and now - s.lastAt < num(cfg().gap_s, 0) and "the director's gap")
                    or (not tellReady("dive", best) and "its tell can't be said now") or nil
                if why then refuse(s, "top_cover", best.slot, why)
                else dive(s, unit, best, now, string.format("held %.0f s; %s fought another flight %.0f s", held, who(best), now - since)) end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- regroup
-- a flight of min_size or more down to half its planes (this spawn's) after_s or more after it came up: the regroup
-- tell, then it breaks off (RE_SV_DirHold_NN) for hold_s and comes back (RE_SV_DirFree_NN), once a spawn
local function regroupTick(s, now, ps)
    if not tacticOn("regroup") then return end
    local c = tc("regroup")
    for unit, sp in pairs(s.spawns) do
        if not sp.regroup and (sp.n or 0) >= num(c.min_size, 4) and now - sp.at >= num(c.after_s, 10) then
            local up, seen = 0, 0
            for _, p in ipairs(planes) do
                if p.unit == unit and (p.born == nil or p.born >= sp.at - 1) then
                    seen = seen + 1
                    if not p.down then up = up + 1 end
                end
            end
            if seen >= sp.n and up >= 1 and up <= sp.n / 2 then
                sp.regroup = true
                local e = nearestPlayer(unit, ps)
                local why = blockedBy(s, "regroup", nil, now) or (busy(s, unit, now) and "it's in hand already")
                    or (not othersUp(s, unit) and "it's the only flight up")   -- (heldTick would let it go at once)
                    or ((D.escortUnits and D.escortUnits[unit]) and "an escort") or ((WOLF and WOLF.holding(unit)) and "its Wolf trap is held")
                    or (not e and "nobody near it") or (not tellReady("regroup", e) and "its tell can't be said now") or nil
                if why then refuse(s, "regroup", nil, why .. " (" .. unit .. ")")
                else
                    spend(s, "regroup", nil, now)
                    local secs = num(c.hold_s, 7)
                    local said = tellAfter("regroup", e, function()
                        if alive(unit) > 0 and not s.held[unit] then hold(s, unit, "regroup", D.now, "regroup", secs) end
                    end)
                    pcall(STATS.tactic, "regroup", unit, e.slot, string.format("%d of its %d planes left; it breaks off %.0f s",
                        up, sp.n, secs), said and "regroup" or nil)
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- pincer arrival
-- a wave's pincer, once its flights are up (or fell back to a normal point; 60 s after its first was placed; force: the
-- next wave's start): counted and the planes of its flights that came up on a side tagged; only when both sides had one
-- (else no pincer: not counted, nothing tagged, its budget back)
local function pincerTick(s, now, force)
    local pc = s.pincer
    if not pc or pc.done then return end
    if not (force or (pc.n + pc.nFell >= pc.total and now >= (pc.last or now) + 1.5) or (pc.first and now - pc.first > 60)) then
        return
    end
    pc.done = true
    if pc.count[1] == 0 or pc.count[2] == 0 then
        local r = s.spent.room
        if r and (r.pincer or 0) > 0 then r.pincer = r.pincer - 1 end
        log(string.format("director: pincer: wave %d's flights didn't come from two sides (%d and %d up on them, %d at a normal "
            .. "point: the zone's edge): no pincer, not counted", pc.wave or 0, pc.count[1], pc.count[2], pc.nFell))
        return
    end
    local tag, nTag = { tactic = "pincer", at = now }, 0
    for _, p in ipairs(planes) do if not p.down and p.unit and pc.sides[p.unit] then p.dirTag = tag; nTag = nTag + 1 end end
    pcall(STATS.tactic, "pincer", nil, nil, string.format("wave %d: %d of %d flights (%d planes) from bearings %.0f and %.0f around %s",
        pc.wave or 0, pc.n, pc.total, nTag, pc.b1, pc.b2, pc.centre == "player" and "you" or "the airfield"),
        pc.said and "pincer" or nil)
end

---------------------------------------------------------------------------------------------------- the API
local function skipped()                              -- a boss round whose own script runs the fight (skip_specials)
    local sp = D.special
    if not sp then return false end
    for _, k in ipairs(cfg().skip_specials or {}) do if k == sp.kind then return true end end
    return false
end

function DIR.holding(unit)
    local s = D and D.dir
    return s ~= nil and unit ~= nil and s.held[unit] ~= nil
end

function DIR.aimed(p)
    local s = D and D.dir
    local a = s and p and p.unit and s.aims[p.unit]
    return a ~= nil and (a.k == nil or a.k == p.k) and (D.now or 0) < a.untilT
end

function DIR.roundStart(now)
    local s = st()
    if not s then return end
    s.round, s.spent, s.next, s.spawns, s.pincer, s.engaged, s.held, s.aims = D.round, {}, {}, {}, nil, {}, {}, {}
    s.after = {}
    local tail = D.counter and tonumber(D.counter.tail) or 0          -- (P6's habit counters, when they're there)
    local top = D.counter and tonumber(D.counter.top) or 0
    s.factor, s.topFactor = 1 + math.max(0, tail or 0), 1 + math.max(0, top or 0)
    if not on() then return end
    local parts = {}
    for _, t in ipairs({ "cover", "trap", "bracket", "top_cover", "pincer", "regroup" }) do
        parts[#parts + 1] = string.format("%s %d%s", t, budgetOf(s, t), tacticOn(t) and "" or " (off)")
    end
    local i = bandOf(D.round)
    log(string.format("director: round %d's budgets (from round %s): %s%s%s", D.round,
        tostring(((cfg().budget or {}).from_round or {})[i] or "-"), table.concat(parts, ", "),
        s.factor ~= 1 and string.format("; cover and trap x%.2f (your tail chasing)", s.factor) or "",
        s.topFactor ~= 1 and string.format("; top cover x%.2f (you stay high)", s.topFactor) or ""))
end

function DIR.spawned(unit, role, n, ace)
    local s = st()
    if not (s and poolIndex(unit)) then return end
    s.spawns[unit] = { at = D.now or 0, n = n, role = role, ace = ace and true or nil }
    s.held[unit], s.aims[unit], s.after[unit] = nil, nil, nil   -- (a recycled flight: its last spawn's hold and aim are gone)
    local pc = s.pincer                               -- (a pincer flight placed on its side, DIR.spawnAt: it came up there)
    local side = pc and pc.pend[unit]
    if side then
        pc.pend[unit], pc.sides[unit] = nil, side
        pc.count[side], pc.n, pc.last = pc.count[side] + 1, pc.n + 1, D.now
    end
end

-- A wave starts (D.queue its flights): with pincer.chance, its fighter flights (2 or more; not a special's wave, a raid's
-- or the escorts) come from two bearings sep_deg apart (spawnFlight asks DIR.spawnAt): around you (ring_km; ahead: either
-- side of your nose, else anywhere) solo, around the airfield in co-op (where you are, if 3 km or more out). Host or solo.
-- Its tell comes once both sides have a flight on them (DIR.spawnAt: one spawn gap after its first; you may be down at
-- the airfield as a round starts: the spawns wait for you); a tell refused then (its gaps) leaves the pincer without one.
function DIR.wave(now)
    local s = st()
    if not s then return end
    if s.pincer and not s.pincer.done then pincerTick(s, now or 0, true) end   -- (the last one counted)
    s.pincer = nil
    if not (tacticOn("pincer") and now) or client() or skipped() then return end
    local c = tc("pincer")
    local units, n = {}, 0
    for _, u in ipairs(D.queue or {}) do
        if type(u) ~= "string" or u:sub(1, 1) == "@" or (D.raidUnits and D.raidUnits[u]) then return end   -- (as it is)
        if poolIndex(u) and not BOMBER_UNIT[u] and not (D.escortUnits and D.escortUnits[u]) then units[u] = true; n = n + 1 end
    end
    if n < 2 or math.random() >= num(c.chance, 0) then return end
    local why = blockedBy(s, "pincer", nil, now, true)
    if why then refuse(s, "pincer", nil, why); return end
    local me = COOP and COOP.me and COOP.me() or nil
    local at = (me and me.at) or playerLocation()
    local centre = (COOP and COOP.open) and "airfield" or "player"
    local b0 = nil
    if centre == "player" and c.ahead and at then           -- your heading as a compass bearing (north -Y, east +X)
        local ok, f = pcall(function() local v = survivalPC.Pawn:GetActorForwardVector(); return { X = v.X, Y = v.Y } end)
        if ok and f and (f.X ~= 0 or f.Y ~= 0) then b0 = math.deg(math.atan(f.X, -f.Y)) % 360 end
    elseif centre == "airfield" and at then
        local dx, dy = at.X - AIRFIELD.X, at.Y - AIRFIELD.Y
        if dx * dx + dy * dy >= 300000 * 300000 then b0 = math.deg(math.atan(dx, -dy)) % 360 end
    end
    b0 = b0 or math.random() * 360
    local sr = c.sep_deg or {}
    local lo, hi = num(sr[1], 90), num(sr[2], 150)
    local sep = lo + math.random() * math.max(0, hi - lo)
    spend(s, "pincer", nil, now, true)
    -- (tries: the flights placed, for the sides' alternation; pend: placed, not yet up; sides / count / n: up on a side;
    -- fell / nFell: at a normal point, the zone's edge)
    s.pincer = { b0 = b0, sep = sep, b1 = (b0 - sep / 2) % 360, b2 = (b0 + sep / 2) % 360, units = units, total = n, n = 0,
                 tries = 0, pend = {}, sides = {}, count = { 0, 0 }, placed = { 0, 0 }, fell = {}, nFell = 0, centre = centre,
                 at = now, wave = D.wave }
    log(string.format("director: pincer: wave %d's %d fighter flights from two sides, bearings %.0f and %.0f (%.0f deg apart) around %s",
        D.wave or 0, n, s.pincer.b1, s.pincer.b2, sep, centre == "player" and "you" or "the airfield"))
end

-- A pincer flight's spawn: on its side's bearing (alternating) around the centre (where you are now, or the airfield),
-- its nose on the centre: { x, y, d (km), b (compass), yaw, side, centre }; nil for any other flight or when the zone's edge
-- left it a random point (spawnPoint's own fallback: that flight is left out of the pincer, its tags and its count). It
-- counts on its side once it's up (DIR.spawned). The pincer tell, to every player, once both sides have a flight.
function DIR.spawnAt(unit)
    local s = D and D.dir
    local pc = s and s.pincer
    if not (pc and not pc.done and pc.units[unit] and not pc.sides[unit] and not pc.fell[unit]) then return nil end
    local c = tc("pincer")
    pc.tries, pc.first = pc.tries + 1, pc.first or D.now
    local side = (pc.tries % 2 == 1) and 1 or 2
    local bearing = side == 1 and pc.b1 or pc.b2
    local cx, cy, range = AIRFIELD.X, AIRFIELD.Y, CFG.distance_km
    if pc.centre == "player" then
        local me = COOP and COOP.me and COOP.me() or nil
        local at = (me and me.at) or playerLocation()
        if at then cx, cy, range = at.X, at.Y, c.ring_km or { 12, 18 } end
    end
    local x, y, d, b, onIt = spawnPoint(range, bearing, num(c.spread_deg, 10), cx, cy)
    pc.last = D.now
    if not onIt then
        pc.fell[unit], pc.nFell, pc.pend[unit] = true, pc.nFell + 1, nil
        log(string.format("director: pincer: %s fell back to a random point (the zone's edge at bearing %.0f): not part of it",
            unit, bearing))
        return nil
    end
    pc.pend[unit] = side
    pc.placed[side] = pc.placed[side] + 1
    if not pc.told and pc.placed[1] > 0 and pc.placed[2] > 0 then
        pc.told = true
        pc.said = tellSay("pincer", nil, pc.b1, pc.b2)
    end
    return { x = x, y = y, d = d, b = b, yaw = math.deg(math.atan(cy - y, cx - x)) % 360, side = bearing,
             centre = (pc.centre == "player" and cx ~= AIRFIELD.X) and "you" or "the airfield" }
end

-- Lets held flight unit go now (P4's intensity director): a top cover dives on the nearest player, after its tell.
-- Whether it did (not inside your decoy: then at its end)
function DIR.release(unit, why)
    local s = D and D.dir
    local h = s and s.held[unit]
    if not h or h.diving then return false end
    why = why or "the director let it go"
    if h.kind == "top" and not decoyed(unit, D.now) then
        local e = nearestPlayer(unit, players(s))
        if e and dive(s, unit, e, D.now or 0, why) then return true end
    end
    return release(s, unit, why)
end

-- P4's "spends a tactic or releases a held flight" on player `slot` (the intensity director: that player's been
-- comfortable calm_s): a held top cover (the one nearest them; none while its intensity hold is on or inside your decoy)
-- dives on them after its tell; else the nearest flight that may turn (cover's choice: a duelist's or an ace squadron's
-- within rangeKm; its next move no sooner than cover.move_s) turns onto them after "check your six" (a joiner: the hunt,
-- its TargetActor on their stand-in for cover.aim_s), counted and tagged "push". The director's gap applies; its tell
-- must be sayable (need_tell). Returns what it did, or nil and why not.
function DIR.push(slot, why, rangeKm)
    local s = st()
    if not (s and D and D.round) then return nil, "no run" end
    if not on() then return nil, "the squad director is off ([director] enabled)" end
    local now = D.now or 0
    local e = nil
    for _, x in ipairs(flying()) do if x.slot == slot then e = x end end
    if not e then return nil, "not flying" end
    if s.lastAt and now - s.lastAt < num(cfg().gap_s, 0) then
        return nil, string.format("the director's gap, %.1f s after its last", now - s.lastAt)
    end
    why = "the intensity director: " .. tostring(why or "comfortable")
    if not (DIR.holdOn and DIR.holdOn(now)) then
        local bu, bd = nil, nil
        for unit, h in pairs(s.held) do
            if h.kind == "top" and not h.diving and not decoyed(unit, now) then
                local _, d = nearestOf(unit, e.at)
                if d and (not bd or d < bd) then bu, bd = unit, d end
            end
        end
        if bu then
            if not tellReady("dive", e) then return nil, "the dive's tell can't be said now" end
            dive(s, bu, e, now, why)
            return string.format("held %s dives on %s (%.1f km off)", bu, who(e), bd)
        end
    end
    local rng = num(rangeKm, num(tc("cover").range_km, 6))
    local q, d = coverer(s, {}, e, now, rng)
    if not q then return nil, string.format("no flight within %.0f km may turn onto %s", rng, who(e)) end
    if not tellReady("six", e) then return nil, "its tell can't be said now" end
    local c, unit, i = tc("cover"), q.unit, poolIndex(q.unit)
    s.lastAt = now
    local lead = (TELL and TELL.leadS) and num(TELL.leadS("six"), 0) or 0
    D.aceMoveAt[unit] = now + lead + num(c.move_s, 30)
    local fn
    if e.isMe then
        local ev = string.format("RE_SV_AceTurn_%02d", i)
        fn = function() log(string.format("director: push: %s %s", ev, (fire(ev)))) end
    else                                              -- (a joiner: LastTGT would turn onto the host)
        fn = function()
            if alive(unit) <= 0 then return end
            local h = string.format("RE_SV_Hunt_%02d", i)
            log(string.format("director: push on player %d: %s %s", e.slot + 1, h, (fire(h))))
            aim(s, unit, nil, e, c.aim_s, "push", true)
        end
    end
    local said = tellAfter("six", e, fn)
    pcall(STATS.tactic, "push", unit, e.slot, string.format("%s; %s %.1f km from %s turns in", why, q.name, d, who(e)),
        said and "six" or nil)
    return string.format("%s turns onto %s (%.1f km off)", unit, who(e), d)
end

-- The holds in force now: RE_SV_DirHold_NN of each flight held (a top cover, a regroup; one diving or inside your decoy
-- too: its release follows). A co-op joiner who links after a hold was forwarded missed it: sv_coop.lua's hostSync sends
-- these once its copies are up, read then
function DIR.holds()
    local s = D and D.dir
    local out = {}
    if not s then return out end
    for unit in pairs(s.held) do
        local i = poolIndex(unit)
        if i and alive(unit) > 0 then out[#out + 1] = string.format("RE_SV_DirHold_%02d", i) end
    end
    table.sort(out)
    return out
end

function DIR.tick(now, paused)
    if client() then                                  -- (a joiner: the host directs; P4's sampler and "in", below)
        if DIR.clientTick then return DIR.clientTick(now, paused) end
        return
    end
    if DIR.intensityTick then                         -- (P4: the scores, the hold, a push, the level; its own switch)
        local okI, errI = pcall(DIR.intensityTick, now, paused)
        if not okI and D and not D.intErr then D.intErr = true; log("intensity: error " .. tostring(errI)) end
    end
    if not (on() and now and D and D.round and not paused) then return end
    local state = D.state
    if state ~= "spawning" and state ~= "wave" and state ~= "fighting" then return end
    local s = st()
    if s.round ~= D.round then DIR.roundStart(now) end
    local ps = players(s)
    if now >= (s.slowAt or 0) then                    -- once a second: holds, aims, the pincer's tag, top cover, regroup
        s.slowAt = now + 1
        aimsTick(s, now)
        afterTick(s, now)
        heldTick(s, now, ps)
        pincerTick(s, now)
        if not skipped() and #ps > 0 then topTick(s, now, ps); regroupTick(s, now, ps) end
    end
    if skipped() or #ps == 0 then return end
    fastTick(s, now, ps)
end
end

---------------------------------------------------------------------------------------------------- P4: the intensity director
-- The thesis' P4: "Track a 0-100 intensity score from damage taken in the last 30 s, missiles inbound, enemies within
-- 5 km and health. Track a comfort score from time spent on an enemy's tail, kills per minute and health above 70 %.
-- When comfort is high and intensity low for 20 s, the director spends a tactic or releases a held flight. When
-- intensity stays above 80, it holds the next wave and the top cover back for 15-20 s. Tiers stay as the floor; spikes
-- become the director's ceiling." (runtime-ai steps 7-9, coop-perf step 6; CFG.intensity says what each setting does;
-- tools/re/BEHAVIOUR_DIRECTOR.md unit 7.)
--   Every game, every tick: your health's drops (HIT.h, HP x10). Once a second on the round clock (not in a pause):
--     your scores from what's kept already: the drops of the last window_s, HIT.msl's missiles within msl_km homing on
--     your pawn (TargetToHome; one within MSL_NEAR_M whose target can't be read counts), the sweep's p.dist (2 s old at
--     most), your tail (each plane's last pose against where you were then, p.youAt, else now), RUN.kills.you, health
--     (MaxHealth read every 5 s). A co-op joiner sends its own to the host ("in", sv_coop.lua) and its copies fly the
--     host's level ("rnd").
--   The host (or solo), once a second for the room: per player (COOP.players(): flying, fresh; a joiner's last "in"
--     under 3 s old) how long it's been hot (intensity above high) or calm (comfort comfort.high+, intensity low or
--     under), in fights only (spawning, wave, fighting; not a boss round of skip_specials); then the top cover's hold,
--     the level, a push. The wave hold starts when roundsTick asks (a wave due: DIR.holdWave). Every decision logged
--     ("intensity:"), the scores every log_s.
--   DIR.level(round)          the spike level enemies of round `round` fly (sv_config.lua levelFor's)
--   DIR.holdWave(now, what)   a wave due (roundsTick: its gate open, or a later wave's next flight): wait? The wave
--                             hold on, or one started now (sv_rounds.lua)
--   DIR.gap(now)              seconds more between two flights while a player's hot (hold.spawn_gap_add_s; sv_rounds.lua)
--   DIR.holdOn(now)           the top cover's hold's end while it's on, else false (heldTick: its dive waits; DIR.push)
--   DIR.pressure(band)        the attack throttle preset for a round band's (sv_rounds.lua roundPressure): stepped down
--                             by the level's ease (level.pressure, not under level.pressure_min)
--   DIR.hot(slot)             that player's intensity while above high (hold.tactics), else false (blockedBy)
--   DIR.intensityTick(now, paused), DIR.clientTick(now, paused)   DIR.tick's P4 part: the host's (solo's), a joiner's
-- State in D.int (a new level or run clears it with D); the level's ease carries over the run's rounds.
do
local FIGHT = { spawning = true, wave = true, fighting = true }
local MSL_NEAR_M = 1000                     -- (a missile this close whose target can't be read: counted as on you)
local HOLD_MAX_S = 30                       -- (a hold's hard limit, whatever hold.secs says)
local PUSH_RETRY_S = 5                      -- (a push that found nothing to send: tried again this much later)

local function icfg() return CFG.intensity or {} end
local function ion() local c = CFG.intensity; return c ~= nil and c.enabled ~= false end
local function sub(name) local t = icfg()[name]; return type(t) == "table" and t or {} end
local function leverOn(name) return ion() and sub(name).enabled ~= false end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function client() return (COOP and COOP.client and COOP.client()) and true or false end
local function whoOf(e) return (e.isMe or not (COOP and COOP.open)) and "you" or string.format("player %d", (e.slot or 0) + 1) end
local function angle(ax, ay, az, bx, by, bz)          -- between two vectors, degrees (180 when one has no length)
    local la, lb = math.sqrt(ax * ax + ay * ay + az * az), math.sqrt(bx * bx + by * by + bz * bz)
    if la == 0 or lb == 0 then return 180 end
    return math.deg(math.acos(math.max(-1, math.min(1, (ax * bx + ay * by + az * bz) / (la * lb)))))
end
local function st()
    if not D then return nil end
    local s = D.int
    if not s then
        s = { dmg = {}, tail = {}, kills = {}, pl = {}, ease = 0, hotFor = 0, coolFor = 0, holdsWave = {}, pushN = {},
              pushNext = {}, said = {} }
        D.int = s
    end
    return s
end
local function skipped()                              -- a boss round whose own script runs the fight (skip_specials)
    local sp = D and D.special
    if not sp then return false end
    for _, k in ipairs(icfg().skip_specials or {}) do if k == sp.kind then return true end end
    return false
end
local function once(s, key, msg)                      -- once a round
    if s.said[key] == D.round then return end
    s.said[key] = D.round
    log(msg)
end
local function prune(ring, now, secs)                 -- a ring's entries ({ t, v }) younger than secs
    local keep = {}
    for _, x in ipairs(ring) do if now - x.t < secs then keep[#keep + 1] = x end end
    return keep
end
local function total(ring) local n = 0; for _, x in ipairs(ring) do n = n + x.v end; return n end

---------------------------------------------------------------------------------------------------- the scores (every game)
-- your health's drops since the last sample (HIT.h every tick; a new aircraft, HIT.pawn, starts over)
local function healthTick(s)
    local h = HIT and HIT.h
    if type(h) ~= "number" then return end
    if s.hKey ~= HIT.pawn then s.hKey, s.hLast = HIT.pawn, h; return end
    if s.hLast and h < s.hLast then s.drop = (s.drop or 0) + (s.hLast - h) end
    s.hLast = h
end
-- this game's player: { obj, at, hp (%), onAirfield }, or nil (COOP.me(): its pawn read once a tick, shared)
local function mine(s, now)
    local e = (COOP and COOP.me) and COOP.me() or nil
    local pawn = (e and e.obj) or (survivalPC and valid(survivalPC) and survivalPC.Pawn) or nil
    if not valid(pawn) then return nil end
    local key = HIT and HIT.pawn
    if now >= (s.maxAt or 0) or s.maxKey ~= key then
        local ok, mh = pcall(function() return pawn.MaxHealth end)
        if ok and type(mh) == "number" and mh > 0 then s.maxHp = mh end
        s.maxAt, s.maxKey = now + 5, key
    end
    local at = (e and e.at) or playerLocation()
    local h = HIT and HIT.h
    local hp = (type(h) == "number" and s.maxHp) and clamp(h / 10 / s.maxHp * 100, 0, 100) or (e and e.hpPct) or nil
    local onA = e and e.onAirfield
    if onA == nil then
        local ok, v = pcall(playerOnAirfield, at)
        onA = ok and v == true
    end
    return { obj = pawn, at = at, hp = hp, onAirfield = onA }
end
-- enemy missiles homing on you within km (HIT.msl: seen in the last second)
local function missilesOn(me, now, km_)
    local list = HIT and HIT.msl
    if not (list and me.obj) then return 0 end
    local pa, n, lim = addrOf(me.obj), 0, km_ * 1000
    for _, m in ipairs(list) do
        if m.d and m.d <= lim and now - (m.seen or -1e9) <= 1.0 and valid(m.obj) then
            local ok, t = pcall(function() return m.obj.TargetToHome end)
            if ok and valid(t) then
                if addrOf(t) == pa then n = n + 1 end
            elseif m.d <= MSL_NEAR_M then
                n = n + 1
            end
        end
    end
    return n
end
-- you on an enemy's tail (within tail_km / tail_deg of its six): each plane's last pose (the sweep's, 2 s old at most)
-- against where you were at that sample (p.youAt, sv_stats.lua), else where you are now
local function onTail(me, cc)
    local tkm, tdeg = num(cc.tail_km, 3), num(cc.tail_deg, 70)
    for _, p in ipairs(planes) do
        if not p.down and p.at and p.fwd and p.dist and p.dist <= tkm + 1 then
            local y = p.youAt or me.at
            if y then
                local dx, dy, dz = y.X - p.at.X, y.Y - p.at.Y, y.Z - p.at.Z
                if math.sqrt(dx * dx + dy * dy + dz * dz) <= tkm * 100000
                    and angle(-p.fwd.X, -p.fwd.Y, -p.fwd.Z, dx, dy, dz) <= tdeg then return true end
            end
        end
    end
    return false
end
-- this second's scores: s.me = { i (smoothed), c, raw, dmg %, msl, near, hp, tailS, kpm, win, onAirfield }, or nil
local function sample(s, now)
    local c, sc, cc = icfg(), sub("score"), sub("comfort")
    local win = math.max(1, num(c.window_s, 30))
    local kw = math.max(1, num(cc.kills_window_s, 60))
    local me = mine(s, now)
    local drop = s.drop or 0
    s.drop = 0
    s.dmg, s.tail, s.kills = prune(s.dmg, now, win), prune(s.tail, now, win), prune(s.kills, now, kw)
    if drop > 0 and s.maxHp then s.dmg[#s.dmg + 1] = { t = now, v = drop / 10 / s.maxHp * 100 } end
    local k = (RUN and RUN.kills and tonumber(RUN.kills.you)) or 0
    if s.kLast and k > s.kLast then s.kills[#s.kills + 1] = { t = now, v = k - s.kLast } end
    s.kLast = k
    if not me then s.me = nil; return nil end
    local dmg, msl, near = total(s.dmg), missilesOn(me, now, num(sc.msl_km, 4)), 0
    local nkm = num(sc.near_km, 5)
    for _, p in ipairs(planes) do if not p.down and p.dist and p.dist <= nkm then near = near + 1 end end
    if onTail(me, cc) then s.tail[#s.tail + 1] = { t = now, v = 1 } end
    local tailS, kpm, hp = total(s.tail), total(s.kills) * 60 / kw, me.hp or 100
    local raw = num(sc.damage, 40) * clamp(dmg / math.max(1, num(sc.dmg_full, 0.4) * 100), 0, 1)
        + num(sc.missiles, 25) * clamp(msl / math.max(1, num(sc.msl_full, 2)), 0, 1)
        + num(sc.near, 20) * clamp(near / math.max(1, num(sc.near_full, 4)), 0, 1)
        + num(sc.health, 15) * clamp(1 - hp / 100, 0, 1)
    raw = clamp(raw, 0, 100)
    local x = clamp(num(c.smooth_x, 0.35), 0.01, 1)
    local i = s.i and (s.i + (raw - s.i) * x) or raw
    local comfort = num(cc.tail, 40) * clamp(tailS / (win * clamp(num(cc.tail_full, 0.5), 0.01, 1)), 0, 1)
        + num(cc.kills, 35) * clamp(kpm / math.max(0.01, num(cc.kpm_full, 2)), 0, 1)
        + num(cc.healthy, 25) * ((hp > num(cc.hp_pct, 70)) and 1 or 0)
    s.i = i
    s.me = { i = i, c = clamp(comfort, 0, 100), raw = raw, dmg = dmg, msl = msl, near = near, hp = hp, tailS = tailS,
             kpm = kpm, win = win, onAirfield = me.onAirfield }
    return s.me
end

---------------------------------------------------------------------------------------------------- the level (the spikes a ceiling)
-- every live enemy flown again at spike level `level`, as it would have been given at its first sweep: its provoke
-- (sv_rows.lua provokeWant / enemyProvoke: only the fields that change; MINDRIPPER's and the Ladons' keep their own; a
-- level with nothing to write for its tier, spike level 0 below a tier without its own provoke: the game's own values
-- it had before its first write back, provokeStockWant) and its PilotRank (enemyTier's, p.rankBase, raised to the
-- level's rank_min; p.rankSet, which the jammer's boost goes back to: a plane near the jammer keeps its boost on it,
-- sv_ai.lua JAM.tick). Its fire control and post-stall stay as it spawned: rows are set at spawn, and post-stall once
-- (enemyManeuvers), so a plane up when level 1 eases to 0 keeps level 1's post_stall_all, while new ones fly without
local function reapply(level, why)
    if not (provokeWant and enemyProvoke and D and D.round) then return end
    local an = CFG.specials and CFG.specials.anomaly
    local rmin = spikeCfg(level).rank_min
    local n, m, nr = 0, 0, 0
    for _, p in ipairs(planes) do
        if not p.down and p.unit and not p.unit:find("^SV_Unit_Ladon") and not (an and p.unit == an.unit) and valid(p.obj) then
            if p.spiked ~= nil then
                local ft = D.flightTier and D.flightTier[p.unit]
                local okW, w = pcall(provokeWant, D.round, ft and CFG.tiers.list[ft] or nil, level)
                if okW and not w and provokeStockWant then okW, w = pcall(provokeStockWant, p, level) end
                if okW and w then
                    m = m + 1
                    local okP, k = pcall(enemyProvoke, p, w)
                    if okP and (k or 0) > 0 then n = n + 1 end
                    p.spiked = w.level
                end
            end
            if p.rankBase and p.rankSet then
                local want = rmin and math.max(p.rankBase, math.min(5, rmin)) or p.rankBase
                if want ~= p.rankSet then
                    p.rankSet = want
                    local jam = p.jammed and CFG.jammer and tonumber(CFG.jammer.rank_add) or 0
                    if pcall(function() p.obj.PilotRank = math.min(5, want + jam) end) then nr = nr + 1 end
                end
            end
        end
    end
    log(string.format("intensity: level %d on the enemies up (%s): provoke written again on %d of %d, PilotRank on %d", level,
        why, n, m, nr))
end
local function maxDrop() return clamp(math.floor(num(sub("level").max_drop, 1)), 0, 3) end
-- the game's attack throttle for the new ease (runtime-ai step 8d, U3's RE_SV_Pressure presets: sv_rounds.lua
-- pressureNow fires the round band's preset through DIR.pressure, when it isn't the one in force; not inside an
-- Anomaly / VALKA fight, whose own throttle is up: the band's, eased, again once its boss is down)
local function pressureAgain(why)
    if not pressureNow then return end
    local okP, errP = pcall(pressureNow, why)
    if not okP then log("intensity: pressure error " .. tostring(errP)) end
end
-- the room above high for down_after_s of fighting: a level down (to max_drop under the spikes); below up_below for
-- up_after_s: a level back; gap_s between two changes. The room's hot / cool time only runs in fights with a player up.
local function levelTick(s, now, dt, room, by, high)
    local lc = sub("level")
    if not leverOn("level") then
        if s.ease ~= 0 then
            s.ease = 0
            log("intensity: level off: enemies fly the spikes' levels again")
            pressureAgain("the intensity director's level off")
        end
        return
    end
    if room > high then s.hotFor, s.coolFor = s.hotFor + dt, 0
    elseif room < num(lc.up_below, 50) then s.coolFor, s.hotFor = s.coolFor + dt, 0
    else s.hotFor, s.coolFor = 0, 0 end
    if s.levelAt and now - s.levelAt < num(lc.gap_s, 45) then return end
    local ceil, was = spikeLevel(D.round), DIR.level(D.round)
    if s.hotFor >= num(lc.down_after_s, 30) and s.ease < maxDrop() and was > 0 then
        s.ease, s.levelAt, s.hotFor = s.ease + 1, now, 0
        local lv = DIR.level(D.round)
        log(string.format("intensity: round %d: the room above %.0f for %.0f s of fighting (%s at %.0f): enemies from now fly "
            .. "difficulty level %d (the spikes' %d, at most %d under)", D.round, high, num(lc.down_after_s, 30),
            by and whoOf(by.e) or "?", room, lv, ceil, maxDrop()))
        reapply(lv, "eased")
        pressureAgain("the intensity director's level down")
    elseif s.coolFor >= num(lc.up_after_s, 60) and s.ease > 0 then
        s.ease, s.levelAt, s.coolFor = s.ease - 1, now, 0
        local lv = DIR.level(D.round)
        log(string.format("intensity: round %d: the room below %.0f for %.0f s of fighting: enemies from now fly difficulty "
            .. "level %d (the spikes' %d)", D.round, num(lc.up_below, 50), num(lc.up_after_s, 60), lv, ceil))
        reapply(lv, "back up")
        pressureAgain("the intensity director's level back up")
    end
end

---------------------------------------------------------------------------------------------------- the holds
-- Two kinds, each hold.secs long (a random time in it, at most HOLD_MAX_S), never made longer, the next of its kind no
-- sooner than hold.gap_s after the last one ended, and only for a player above high for hold.after_s:
--   the wave hold (s.hold): started only when a wave is due, roundsTick's question (DIR.holdWave): the wave gate open
--     (the last wave thinned to waves.next_at, or its timeout) or a later wave's next flight up; at most hold.per_wave
--     a wave. (Review of unit 7: started as soon as a player was hot, mostly right after a wave came, it ran out long
--     before the gate opened and held nothing; the hold after it was then refused for gap_s or per_wave.)
--   the top cover's (s.cover): started once a second (decide) while the squad director holds a top cover (D.dir.held,
--     kind "top"): its dive and its max_s wait (DIR.holdOn, P2's heldTick). Neither counts for the other's gap or
--     per_wave: a wave due while the top cover's on gets a hold of its own, and the top cover isn't held twice in a row.
-- the top cover flights held now ("ERA_..., ..."), or nil
local function topHeld()
    local units = {}
    for unit, h in pairs((D.dir and D.dir.held) or {}) do if h.kind == "top" and not h.diving then units[#units + 1] = unit end end
    if #units == 0 then return nil end
    table.sort(units)
    return table.concat(units, ", ")
end
local function roomText(ps)
    if #ps < 2 then return "" end
    local t = {}
    for _, q in ipairs(ps) do t[#t + 1] = string.format("%s %.0f", whoOf(q.e), q.x.i) end
    return "; the room: " .. table.concat(t, ", ")
end
-- the hold `kind` ("hold": the wave's, "cover": the top cover's) over: its end, the gap's start for its kind
local function holdEnd(s, kind, now, why)
    local h = s[kind]
    local endT = math.min(now, h.untilT)
    s[kind] = nil
    if kind == "hold" then s.waveEnd = endT else s.coverEnd = endT end
    if s.rs and s.rs.round == h.round then s.rs.holdS = s.rs.holdS + (endT - h.at) end
    log(string.format("intensity: hold over after %.0f s (%s)%s", endT - h.at, h.what, why and (": " .. why) or ""))
end
-- the player above high for hold.after_s with the highest intensity (decide's s.pl, once a second), or nil
local function hottest(s)
    local after, best = num(sub("hold").after_s, 3), nil
    for _, pl in pairs(s.pl) do
        if pl.i and pl.e and (pl.hotFor or 0) >= after and (not best or pl.i > best.i) then best = pl end
    end
    return best
end
local function holdStart(s, kind, now, pl, what, key)
    local hc = sub("hold")
    local r = type(hc.secs) == "table" and hc.secs or { 15, 20 }
    local lo = num(r[1], 15)
    local hi = num(r[2], lo)
    local secs = clamp(lo + math.random() * math.max(0, hi - lo), 0, HOLD_MAX_S)
    if secs <= 0 then return nil end
    local h = { at = now, untilT = now + secs, round = D.round, slot = pl.e.slot, what = what, key = key, said = {} }
    s[kind] = h
    if s.rs then s.rs.holds = s.rs.holds + 1 end
    log(string.format("intensity: round %d: held %.0f s (%s at intensity %.0f, above %.0f for %.0f s): %s wait%s",
        D.round, secs, whoOf(pl.e), pl.i, num(icfg().high, 80), pl.hotFor, what, roomText(s.ps or {})))
    return h
end
-- the top cover's hold (decide, once a second, the host's in a fight)
local function holdTick(s, now)
    if s.cover or not leverOn("hold") then return end
    local units = topHeld()
    if not units then return end
    local pl = hottest(s)
    if not pl then return end
    local gap = num(sub("hold").gap_s, 20)
    if s.coverEnd and now - s.coverEnd < gap then
        once(s, "cgap|" .. tostring(s.coverEnd), string.format("intensity: hold not now (%s at intensity %.0f; the top cover's "
            .. "last ended %.0f s ago, hold.gap_s %.0f)", whoOf(pl.e), pl.i, now - s.coverEnd, gap))
        return
    end
    holdStart(s, "cover", now, pl, "the top cover (" .. units .. ")")
end
-- roundsTick's question, a wave due (`what` "wave": the next one's gate open; "spawning": a later wave's next flight
-- up): wait? Yes while the wave hold's on; else one starts now when a player's hot, per_wave and gap_s allow
local function waveHold(s, now, what)
    if s.hold and (now >= s.hold.untilT or s.hold.round ~= D.round) then holdEnd(s, "hold", now) end
    local w = (D.wave or 1) + (what == "wave" and 1 or 0)
    local label = what == "wave" and string.format("wave %d", w) or string.format("the rest of wave %d", w)
    local h = s.hold
    if not h then
        if not leverOn("hold") or client() or skipped() then return false end
        local pl = hottest(s)
        if not pl then return false end
        local hc, key = sub("hold"), D.round .. "|" .. w
        local per = math.max(0, math.floor(num(hc.per_wave, 1)))
        if (s.holdsWave[key] or 0) >= per then
            once(s, "wave|" .. key, string.format("intensity: hold not now (%s at intensity %.0f; wave %d had its %d): %s comes",
                whoOf(pl.e), pl.i, w, per, label))
            return false
        end
        local gap = num(hc.gap_s, 20)
        if s.waveEnd and now - s.waveEnd < gap then
            once(s, "gap|" .. key, string.format("intensity: hold not now (%s at intensity %.0f; the last ended %.0f s ago, "
                .. "hold.gap_s %.0f): %s comes", whoOf(pl.e), pl.i, now - s.waveEnd, gap, label))
            return false
        end
        h = holdStart(s, "hold", now, pl, label, key)
        if not h then return false end
        s.holdsWave[key] = (s.holdsWave[key] or 0) + 1
    end
    if not h.said[what] then
        h.said[what] = true
        log(string.format("round %d: %s waits for the intensity hold (%.0f s more)", D.round, label, h.untilT - now))
    end
    return true
end

---------------------------------------------------------------------------------------------------- a push
-- the players calm for calm_s, the most comfortable first: the squad director spends a tactic on the first one it can
-- (DIR.push: a held top cover dives, else a flight turns onto them); push.per_round each a round from push.from_round,
-- cooldown_s apart. One used up, on its cooldown or with nothing to send (tried again PUSH_RETRY_S on) doesn't keep
-- the next calm player waiting (review of unit 7). One push a second at most.
local function pushTick(s, now, ps)
    if not leverOn("push") then return end
    local pc, calm = sub("push"), num(icfg().calm_s, 20)
    if (D.round or 0) < num(pc.from_round, 1) then return end
    local cands = {}
    for _, q in ipairs(ps) do
        local pl = s.pl[q.e.slot or 0]
        if pl and pl.calmFor >= calm then cands[#cands + 1] = { q = q, pl = pl } end
    end
    table.sort(cands, function(a, b)
        if a.q.x.c ~= b.q.x.c then return a.q.x.c > b.q.x.c end
        return (a.q.e.slot or 0) < (b.q.e.slot or 0)
    end)
    local max = math.max(0, math.floor(num(pc.per_round, 2)))
    for _, x in ipairs(cands) do
        local q, pl = x.q, x.pl
        local slot = q.e.slot or 0
        local what = string.format("%s comfortable %.0f s (comfort %.0f, intensity %.0f)", whoOf(q.e), pl.calmFor, q.x.c, q.x.i)
        local used = s.pushN[slot] or 0
        local why = (used >= max and string.format("its %d this round", max))
            or (now < (s.pushNext[slot] or 0) and string.format("its cooldown, %.0f s more", s.pushNext[slot] - now)) or nil
        if why then
            once(s, "push|" .. slot .. "|" .. (why:match("^[%a ]+") or why), "intensity: " .. what .. ": no push (" .. why .. ")")
        else
            local okP, did, whyNot = pcall(DIR.push, slot, what, num(pc.range_km, 8))
            if not okP then did, whyNot = nil, "error " .. tostring(did) end
            if did then
                s.pushN[slot], s.pushNext[slot], pl.calmFor = used + 1, now + num(pc.cooldown_s, 40), 0
                if s.rs then s.rs.pushes = s.rs.pushes + 1 end
                log("intensity: " .. what .. ": " .. did)
                return
            end
            pl.calmFor = math.max(0, calm - PUSH_RETRY_S)
            once(s, "nopush|" .. slot .. "|" .. (tostring(whyNot):match("^[%a ']+") or "?"),
                "intensity: " .. what .. ": nothing sent (" .. tostring(whyNot) .. ")")
        end
    end
end

---------------------------------------------------------------------------------------------------- rounds, lines
local function roundLine(s, now)
    local r = s.rs
    if not r or r.said then return end
    r.said = true
    for _, kind in ipairs({ "hold", "cover" }) do
        if s[kind] and s[kind].round == r.round then holdEnd(s, kind, now, "the round's over") end
    end
    if r.n == 0 then return end
    local ceil, lv = spikeLevel(r.round), DIR.level(r.round)
    log(string.format("intensity: round %d: you avg %.0f, peak %.0f, above %.0f for %d s; comfort avg %.0f%s; level %d%s", r.round,
        r.sumI / r.n, r.peak, num(icfg().high, 80), r.hotS, r.sumC / r.n,
        client() and "" or string.format("; held %d (%.0f s), pushes %d", r.holds, r.holdS, r.pushes),
        lv, lv ~= ceil and string.format(" (the spikes' %d%s)", ceil, client() and ", the host's" or "") or ""))
end
-- the round the scores count for (a fight of D.round): its sums; its line once it's over (D.state "wait", or the next)
local function roundTrack(s, now)
    if not (D.round and FIGHT[D.state]) then
        if s.rs and not s.rs.said then roundLine(s, now) end
        return
    end
    if not s.rs or s.rs.round ~= D.round then
        if s.rs and not s.rs.said then roundLine(s, now) end
        s.rs = { round = D.round, n = 0, sumI = 0, peak = 0, hotS = 0, sumC = 0, holds = 0, holdS = 0, pushes = 0 }
        s.pushN = {}
        local ceil, lv = spikeLevel(D.round), DIR.level(D.round)
        if lv ~= ceil and not client() then
            log(string.format("intensity: round %d: enemies fly difficulty level %d (the spikes' %d, eased for the room's pressure)",
                D.round, lv, ceil))
        end
    end
    local m = s.me
    if m and not m.onAirfield then
        local r = s.rs
        r.n, r.sumI, r.sumC, r.peak = r.n + 1, r.sumI + m.i, r.sumC + m.c, math.max(r.peak, m.i)
        if m.i > num(icfg().high, 80) then r.hotS = r.hotS + 1 end
    end
end
-- your scores every log_s seconds of a fight (the host's: the other players' last too, a hold on; a level eased)
local function scoreLine(s, now)
    local every, m = num(icfg().log_s, 10), s.me
    if every <= 0 or not m or m.onAirfield or not (D.round and FIGHT[D.state]) or now < (s.logAt or 0) then return end
    s.logAt = now + every
    local parts = { string.format("intensity: round %d: you %.0f (damage %.0f%% of your health in %.0f s, %d missile%s on you, " ..
        "%d enem%s within %.0f km, health %.0f%%), comfort %.0f (on a tail %.0f s of %.0f, %.1f kills a minute)", D.round, m.i,
        m.dmg, m.win, m.msl, m.msl == 1 and "" or "s", m.near, m.near == 1 and "y" or "ies", num(sub("score").near_km, 5), m.hp,
        m.c, m.tailS, m.win, m.kpm) }
    if not client() then
        local slots = {}
        for slot, pl in pairs(s.pl) do if not pl.isMe and pl.i then slots[#slots + 1] = slot end end
        table.sort(slots)
        for _, slot in ipairs(slots) do
            local pl = s.pl[slot]
            parts[#parts + 1] = string.format("player %d %.0f, comfort %.0f", slot + 1, pl.i, pl.c or 0)
        end
        for _, kind in ipairs({ "hold", "cover" }) do
            local h = s[kind]
            if h then parts[#parts + 1] = string.format("holding %s (%.0f s more)", h.what, h.untilT - now) end
        end
    end
    local ceil, lv = spikeLevel(D.round), DIR.level(D.round)
    if lv ~= ceil then parts[#parts + 1] = string.format("level %d (the spikes' %d)", lv, ceil) end
    log(table.concat(parts, "; "))
end

---------------------------------------------------------------------------------------------------- the room (the host)
local function decide(s, now, dt)
    local c = icfg()
    local high, low, cHigh = num(c.high, 80), num(c.low, 35), num(sub("comfort").high, 60)
    local fight = D.round and FIGHT[D.state] and not skipped()
    local ps = {}
    if fight then
        local all = nil
        if COOP and COOP.players then
            local ok, l = pcall(COOP.players)
            if ok and type(l) == "table" then all = l end
        end
        for _, e in ipairs(all or { { slot = 0, isMe = true } }) do
            local x = nil
            if e.isMe then x = s.me elseif COOP and COOP.intensityOf then x = COOP.intensityOf(e.slot) end
            if x and e.alive ~= false and e.fresh ~= false and not e.onAirfield and not x.onAirfield then ps[#ps + 1] = { e = e, x = x } end
        end
    end
    local seen, room, by = {}, 0, nil
    for _, q in ipairs(ps) do
        local slot = q.e.slot or 0
        local pl = s.pl[slot] or {}
        s.pl[slot], seen[slot] = pl, true
        pl.i, pl.c, pl.isMe, pl.e = q.x.i, q.x.c, q.e.isMe, q.e
        pl.hotFor = (q.x.i > high) and (pl.hotFor or 0) + dt or 0
        pl.calmFor = (q.x.c >= cHigh and q.x.i <= low) and (pl.calmFor or 0) + dt or 0
        if q.x.i > room then room, by = q.x.i, q end
    end
    for slot, pl in pairs(s.pl) do if not seen[slot] then pl.i, pl.hotFor, pl.calmFor = nil, 0, 0 end end
    s.ps = ps                                         -- (the room this second: a wave hold's line, DIR.holdWave)
    for _, kind in ipairs({ "hold", "cover" }) do
        local h = s[kind]
        if h and (not fight or now >= h.untilT or h.round ~= D.round) then
            holdEnd(s, kind, now, (not fight) and "no fight to hold" or nil)
        end
    end
    if not fight then return end
    holdTick(s, now)
    if #ps > 0 then levelTick(s, now, dt, room, by, high) end
    pushTick(s, now, ps)
end

---------------------------------------------------------------------------------------------------- the API
function DIR.level(round)
    local ceil = spikeLevel(round)
    if ceil <= 0 or not leverOn("level") then return ceil end
    if client() then                                  -- (the host's, from its "rnd": sv_coop.lua clientRounds)
        local x = D and D.intLevel
        if x and x.round == round and type(x.level) == "number" then return clamp(math.floor(x.level), 0, ceil) end
        return ceil
    end
    local s = D and D.int
    return math.max(0, ceil - math.min(s and s.ease or 0, maxDrop()))
end

function DIR.holdOn(now)
    local h = D and D.int and D.int.cover
    if h and h.round == D.round and now and now < h.untilT then return h.untilT end
    return false
end

-- (roundsTick asks only when the wave's due: sv_rounds.lua's gate `(alive <= next_at or timedOut) and not ...`, the
-- spawning branch at a later wave's next flight; an error here never stops the rounds: no hold)
function DIR.holdWave(now, what)
    local s = D and D.int
    if not (s and now and D.round and ion()) then return false end
    local okH, r = pcall(waveHold, s, now, what)
    if not okH then
        if not D.intErr then D.intErr = true; log("intensity: error " .. tostring(r)) end
        return false
    end
    return r == true
end

-- seconds more between two of a wave's flights (runtime-ai step 8a): hold.spawn_gap_add_s while a player's been above
-- high for hold.after_s (a round's first wave too; the host's, solo's), else 0. Logged once a wave
function DIR.gap(now)
    local s = D and D.int
    if not (s and now and D.round and leverOn("hold")) or client() or skipped() then return 0 end
    local add = clamp(num(sub("hold").spawn_gap_add_s, 0), 0, 10)
    if add <= 0 then return 0 end
    local pl = hottest(s)
    if not pl then return 0 end
    once(s, "sgap|" .. (D.wave or 1), string.format("intensity: round %d: wave %d's flights %.0f s further apart (%s at intensity %.0f)",
        D.round, D.wave or 1, add, whoOf(pl.e), pl.i))
    return add
end

-- the attack throttle preset for the round band's `band` (sv_rounds.lua roundPressure; TIER.PRESSURE_PRESETS letters,
-- gentler first): one letter down a level the room's eased (level.pressure), never under level.pressure_min nor under
-- what the band asks for already (the director only eases: the spikes' and U3's late presets are its ceiling)
function DIR.pressure(band)
    local lc = sub("level")
    if type(band) ~= "string" or not leverOn("level") or lc.pressure == false or client() then return band end
    local ease = math.min((D and D.int and D.int.ease) or 0, maxDrop())
    local P = TIER and TIER.PRESSURE_PRESETS or "ABCD"
    local i = P:find(band, 1, true)
    if ease <= 0 or not i then return band end
    local m = type(lc.pressure_min) == "string" and lc.pressure_min:upper() or "B"
    local floor = nil
    if #m == 1 then floor = P:find(m, 1, true) end
    floor = floor or P:find("B", 1, true) or 1
    if i <= floor then return band end
    local j = math.max(floor, i - ease)
    return P:sub(j, j)
end

function DIR.hot(slot)
    local s = D and D.int
    if not (s and leverOn("hold") and sub("hold").tactics ~= false) then return false end
    local pl = s.pl[slot or 0]
    if pl and pl.i and pl.i > num(icfg().high, 80) then return pl.i end
    return false
end

function DIR.intensityTick(now, paused)
    local s = st()
    if not (s and now and ion()) then return end
    healthTick(s)
    if paused or now < (s.at or 0) then return end
    local dt = clamp(now - (s.last or (now - 1)), 0, 2)
    s.at, s.last = now + 1, now
    sample(s, now)
    roundTrack(s, now)
    decide(s, now, dt)
    scoreLine(s, now)
end

-- a joiner: its own scores to the host ("in", once a second), the host's level on its copies when it changes
function DIR.clientTick(now, paused)
    local s = st()
    if not (s and now and ion()) then return end
    healthTick(s)
    if paused or now < (s.at or 0) then return end
    s.at, s.last = now + 1, now
    sample(s, now)
    roundTrack(s, now)
    local x = D.intLevel
    if x and x.round == D.round and type(x.level) == "number" then
        local key = x.round .. ":" .. x.level
        if key ~= s.lvKey then
            local ceil = spikeLevel(D.round)
            if x.level ~= ceil or s.lvRound == D.round then
                log(string.format("intensity: the host's difficulty level for round %d: %d (the spikes' %d)", D.round, DIR.level(D.round), ceil))
                reapply(DIR.level(D.round), "the host's level")
            end
            s.lvKey, s.lvRound = key, D.round
        end
    end
    scoreLine(s, now)
    local m = s.me
    if m and COOP and COOP.sendIntensity then pcall(COOP.sendIntensity, m.i, m.c, m.hp, m.msl) end
end
end
