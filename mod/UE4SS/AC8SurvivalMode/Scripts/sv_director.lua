-- sv_director.lua: the squad director, the behaviour roadmap's P2 ("one Lua part that watches the whole sky and fires
-- remote events on the right plane"; tools/re/BEHAVIOUR_DIRECTOR.md unit 6). P4's intensity director joins it here later.
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
-- The host's (or solo): DIR.tick runs from sv_main.lua's probeTick every 250 ms (timed "director"); on a co-op joiner it
-- does nothing of its own (P4's DIR.clientTick, once there is one). A tactic is aimed at a player (COOP.players(): a
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
        s = { spent = {}, next = {}, held = {}, aims = {}, spawns = {}, said = {}, engaged = {}, rr = 0, factor = 1 }
        D.dir = s
    end
    return s
end

---------------------------------------------------------------------------------------------------- budgets, cooldowns
-- a tactic's budget this round: CFG.director.budget's band of the latest from_round reached, cover and trap x the
-- habit counter's factor (P6: D.counter.tail, more of them against a tail chaser; the critic's gap fill)
local function bandOf(round)
    local i = 0
    for k, r in ipairs((cfg().budget or {}).from_round or {}) do if (round or 0) >= (tonumber(r) or math.huge) then i = k end end
    return i
end
local function factor(s, tactic) return (tactic == "cover" or tactic == "trap") and (s.factor or 1) or 1 end
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
    if why == "off" then return end
    local key = tactic .. "|" .. tostring(slot) .. "|" .. (tostring(why):match("^[%a ']+") or tostring(why))
    if s.said[key] == D.round then return end
    s.said[key] = D.round
    log(string.format("director: %s%s not now (%s)", tactic,
        (slot and COOP and COOP.open) and string.format(" for player %d", slot + 1) or "", tostring(why)))
end

---------------------------------------------------------------------------------------------------- players, tells
-- the players a tactic may be aimed at (COOP.players(): you first, then the others; solo or the Offline edition: you):
-- alive, flying, their state fresh; past CFG.director.players, you and the others round-robin
local function players(s)
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
-- another flight of the round still has a plane up
local function othersUp(unit)
    for _, p in ipairs(planes) do
        if not p.down and p.unit and p.unit ~= unit and D.up and D.up[p.unit] then return true end
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
-- (COOP.hunted), RE_SV_Hunt_NN again (Normal / AIFirst: the joiners' planes; the host's only)
local function orders(s, unit, e, why)
    local i = poolIndex(unit)
    if not i then return end
    local parts = {}
    local ev = string.format("RE_SV_DirFree_%02d", i)
    parts[#parts + 1] = ev .. " " .. (fire(ev))
    local hunted = COOP and COOP.hunted and COOP.hunted(unit)
    if (e and not e.isMe) or hunted then
        local h = string.format("RE_SV_Hunt_%02d", i)
        parts[#parts + 1] = h .. " " .. (fire(h))
    end
    log(string.format("director: %s back in the fight (%s): %s", unit, tostring(why), table.concat(parts, ", ")))
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
-- held flight unit back in the fight (e: aimed at that player; a joiner's: its TargetActor on them for aim_s)
local function release(s, unit, why, e)
    local h = s.held[unit]
    s.held[unit] = nil
    orders(s, unit, e, why)
    if e and not e.isMe then aim(s, unit, nil, e, tc("top_cover").aim_s, h and h.why or why, true) end
end
local function aimsTick(s, now)
    for unit, a in pairs(s.aims) do
        if now >= a.untilT or alive(unit) <= 0 then
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
-- Wolf trap or still in a reversal, D.aceMoveAt, shared with ACE.movesTick)
local function coverer(s, p, e, now)
    local rng = num(tc("cover").range_km, 6)
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
                        or (not othersUp(unit) and "it's the only flight up") or (busy(s, unit, now) and "it's in hand already") or nil
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
-- held min_s; it's let go quietly at max_s, when hit, as the round's last flight or when your decoy's end frees it. A
-- regroup ends after hold_s (or when hit).
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
            log(string.format("director: %s (%s) freed by your decoy's end", unit, h.why))
        elseif h.diving then                          -- (its tell said: it goes after the lead)
        elseif hits(unit) > (h.dmg or 0) then
            release(s, unit, "you hit it while it was held")
        elseif D.state == "fighting" and not othersUp(unit) then
            release(s, unit, "the round's last flight")
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
-- a wave's pincer, once its flights are up: counted and its planes tagged
local function pincerTick(s, now)
    local pc = s.pincer
    if not pc or pc.done then return end
    if not ((pc.n >= pc.total and now >= (pc.last or now) + 1.5) or now - pc.at > 60) then return end
    pc.done = true
    if pc.n == 0 then return end
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
    local tail = D.counter and tonumber(D.counter.tail) or 0          -- (P6's habit counter, when it's there)
    s.factor = 1 + math.max(0, tail or 0)
    if not on() then return end
    local parts = {}
    for _, t in ipairs({ "cover", "trap", "bracket", "top_cover", "pincer", "regroup" }) do
        parts[#parts + 1] = string.format("%s %d%s", t, budgetOf(s, t), tacticOn(t) and "" or " (off)")
    end
    local i = bandOf(D.round)
    log(string.format("director: round %d's budgets (from round %s): %s%s", D.round,
        tostring(((cfg().budget or {}).from_round or {})[i] or "-"), table.concat(parts, ", "),
        s.factor ~= 1 and string.format("; cover and trap x%.2f (your tail chasing)", s.factor) or ""))
end

function DIR.spawned(unit, role, n, ace)
    local s = st()
    if not (s and poolIndex(unit)) then return end
    s.spawns[unit] = { at = D.now or 0, n = n, role = role, ace = ace and true or nil }
    s.held[unit], s.aims[unit] = nil, nil             -- (a recycled flight: its last spawn's hold and aim are gone)
end

-- A wave starts (D.queue its flights): with pincer.chance, its fighter flights (2 or more; not a special's wave, a raid's
-- or the escorts) come from two bearings sep_deg apart (spawnFlight asks DIR.spawnAt): around you (ring_km; ahead: either
-- side of your nose, else anywhere) solo, around the airfield in co-op (where you are, if 3 km or more out). Host or solo.
-- Its tell comes with its first flight (you may be down at the airfield as a round starts: the spawns wait for you); a
-- tell refused then (its gaps) leaves the pincer without one.
function DIR.wave(now)
    local s = st()
    if not s then return end
    if s.pincer and not s.pincer.done then s.pincer.at = -math.huge; pincerTick(s, now or 0) end   -- (the last one counted)
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
    s.pincer = { b0 = b0, sep = sep, b1 = (b0 - sep / 2) % 360, b2 = (b0 + sep / 2) % 360, units = units, total = n, n = 0,
                 sides = {}, centre = centre, at = now, wave = D.wave }
    log(string.format("director: pincer: wave %d's %d fighter flights from two sides, bearings %.0f and %.0f (%.0f deg apart) around %s",
        D.wave or 0, n, s.pincer.b1, s.pincer.b2, sep, centre == "player" and "you" or "the airfield"))
end

-- A pincer flight's spawn: on its side's bearing (alternating) around the centre (where you are now, or the airfield),
-- its nose on the centre: { x, y, d (km), b (compass), yaw, side, centre }; nil for any other flight or when the zone's edge
-- left it a random point (spawnPoint's own fallback). The first one says the pincer tell to every player.
function DIR.spawnAt(unit)
    local s = D and D.dir
    local pc = s and s.pincer
    if not (pc and pc.units[unit] and not pc.sides[unit]) then return nil end
    local c = tc("pincer")
    local side = (pc.n % 2 == 0) and pc.b1 or pc.b2
    pc.n = pc.n + 1
    pc.sides[unit] = side
    local cx, cy, range = AIRFIELD.X, AIRFIELD.Y, CFG.distance_km
    if pc.centre == "player" then
        local me = COOP and COOP.me and COOP.me() or nil
        local at = (me and me.at) or playerLocation()
        if at then cx, cy, range = at.X, at.Y, c.ring_km or { 12, 18 } end
    end
    local x, y, d, b, onIt = spawnPoint(range, side, num(c.spread_deg, 10), cx, cy)
    pc.last = D.now
    if not onIt then
        log(string.format("director: pincer: %s fell back to a random point (the zone's edge at bearing %.0f)", unit, side))
        return nil
    end
    if not pc.told then
        pc.told = true
        pc.said = tellSay("pincer", nil, pc.b1, pc.b2)
    end
    return { x = x, y = y, d = d, b = b, yaw = math.deg(math.atan(cy - y, cx - x)) % 360, side = side,
             centre = (pc.centre == "player" and cx ~= AIRFIELD.X) and "you" or "the airfield" }
end

-- Lets held flight unit go now (P4's intensity director): a top cover dives on the nearest player, after its tell.
function DIR.release(unit, why)
    local s = D and D.dir
    local h = s and s.held[unit]
    if not h or h.diving then return false end
    why = why or "the director let it go"
    if h.kind == "top" then
        local e = nearestPlayer(unit, players(s))
        if e and dive(s, unit, e, D.now or 0, why) then return true end
    end
    release(s, unit, why)
    return true
end

function DIR.tick(now, paused)
    if client() then                                  -- (a joiner: the host directs; P4's own sampler, later)
        if DIR.clientTick then return DIR.clientTick(now, paused) end
        return
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
        heldTick(s, now, ps)
        pincerTick(s, now)
        if not skipped() and #ps > 0 then topTick(s, now, ps); regroupTick(s, now, ps) end
    end
    if skipped() or #ps == 0 then return end
    fastTick(s, now, ps)
end
end
