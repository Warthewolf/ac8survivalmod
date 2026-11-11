-- sv_rounds_shuttle.lua: the shuttle's liftoff replayed on this game when its own was lost in the landing STORE, its
-- removal fired again the same way, and the log's watch on the pad after the countdown (sv_rounds.lua's next piece).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order right after sv_rounds.lua (its specialTick calls these
-- at run time); a name another part uses is a global of this mod's Lua state, its own helpers stay local.

-- ((2026-11-11) Saint Alessia's co-op run of 0.74.36, 4 players: "shuttle never launched on my end, enemies still swarmed
-- around it, clients reported it launched for them a couple rounds prior") The host's countdown ran on while it was down
-- at the airfield (others flying, as above) and every second's event was sent (SV_Event 1), but its game ran none of the
-- records of those that came while its landing minigames were up: her Hangar ran 18:47:27-18:48:06, T-4 and T fell in it,
-- SV_ShuttleLaunched and SV_ShuttleRound never changed again, and a flight that appeared in it got no orders, while the
-- events after it took, she still on the runway. "countdown over" paid, called SHUTTLE LAUNCHED and ended the round with
-- the shuttle on its pad three minutes more, and SV_ShuttleRound still 1 put round 3's raid on the shuttle's orders
-- (survival_events.py SV_BomberUp_NN). Her joiners' games fired the forwarded events in their own worlds and saw it go.
-- So "countdown over" with the shuttle still there replays this game's own liftoff once its STORE is shut (SPC.storeShut):
-- RE_SV_ShuttleT_<T-14> (ignition) and _<T-4> (onto its path; only while it's still on its pad), _<T> 4 s after (the climb,
-- SV_ShuttleLaunched 1, SV_ShuttleRound 0), fired here alone (COOP.eventHere: the others' shuttles flew on time, and the
-- clock sends them the tail), then _<T+7> / _<T+13> / _<T+30> at their offsets from it. Nagase's countdown radio and the
-- focus camera aren't fired again; the shuttle is invulnerable until it's taken off, as T-20's MinHealth made it. It took
-- when SV_ShuttleLaunched reads 1 3 s after _<T> (the flag alone: a shuttle that moved without it leaves SV_ShuttleRound at
-- 1); else from _<T-4> again, REPLAY_TRIES in all. Its removal (remove_s) counts from then; given up, 30 s.
-- RE_SV_ShuttleRemove can be lost the same way: SV_ShuttleRound or SV_ShuttleLaunched still up after it (both set back to
-- 0 by it) fires it again here, with the strike flights' retasks (SPC.shuttleRemoveAgainTick).
do
local GATE_S, REPLAY_TRIES, REPLAY_WAIT_S, REMOVE_TRIES, WATCH_S = 3, 3, 300, 3, 30
-- This game's own events can take (its landing minigames over): false, and why, while its landing STORE is open
-- (D.musicHold: solo the game's pause down at the airfield, co-op the landing menu on screen; it lets go ~2.5 s after the
-- menu closes) or it's down at the airfield with no STORE yet this visit (on short final, landing and taxiing in: the
-- Landing and SeamlessIn minigames, which nothing here sees), and for GATE_S after either. SPC.gate is forgotten when
-- nothing waits on it, so a visit is seen from its start.
function SPC.storeShut(now)
    local G = SPC.gate
    if not G then G = {}; SPC.gate = G end
    local on, up = playerOnAirfield(), D.musicHold == 1
    if on and not G.on then G.seen = false end          -- (a visit to the airfield starts: its STORE to come)
    G.on = on
    if up then G.seen = true end
    local why = up and "your landing STORE is open" or (on and not G.seen) and "you're down at the airfield, your STORE not open yet" or nil
    if why then G.busyAt, G.after = now, up and "your landing STORE closed a moment ago" or "you left the airfield a moment ago" end
    if G.busyAt and now - G.busyAt < GATE_S then return false, why or G.after end
    return true, nil
end
local function flagText(f, name) return tostring(f[name] or "?") end
-- fires RE_SV_ShuttleT_<sec> on this game alone; the result is kept for the replay's last line
local function fireHere(R, sec)
    local name = "RE_SV_ShuttleT_" .. sec
    local r = (COOP and COOP.eventHere and COOP.eventHere(name)) or (type(SV_Event) == "function" and SV_Event(name)) or -5
    R.fired[#R.fired + 1] = r == 1 and tostring(sec) or (sec .. " (" .. (SV_ERR[r] or tostring(r)) .. ")")
    return r
end
-- the shuttle still on its pad (SHUTTLE.padAt, recorded in its countdown): within 200 m of it and under 100 m above;
-- not known (no pad spot, no actor): true, its path given again
local function onPad()
    local at = SHUTTLE.padAt
    if not at or not liveObj(SHUTTLE.obj) then return true end
    local ok, v = pcall(function() local l = SHUTTLE.obj:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    if not (ok and v) then return true end
    return math.sqrt((v.X - at.X) ^ 2 + (v.Y - at.Y) ^ 2) < 20000 and v.Z - (at.Z or v.Z) < 10000
end
-- "countdown over" with the shuttle still up (specialTick): true when this game replays its liftoff (the host's or a solo
-- game's; never a joiner's, whose shuttle copy flies on the host's forwarded events)
function SPC.shuttleReplayStart(now)
    if COOP and COOP.client and COOP.client() then return false end
    SPC.gate = nil
    local R = { at = now, tries = 0, phase = "wait", fired = {} }
    D.shuttleReplay = R
    R.inv = SPC.shuttleInvincible(true, "invulnerable until its liftoff is replayed here and it's taken off")
    return true
end
function SPC.shuttleReplayTick(now)
    local R = D.shuttleReplay
    if not R then return end
    local c = CFG.specials.shuttle
    local T, f = c.countdown_s, svFlags() or {}
    local function finish(why)
        D.shuttleReplay, SPC.gate = nil, nil
        D.shuttleRemoveAt = now + 30
        log(string.format("special: shuttle liftoff not replayed here: %s (events fired %s; SV_ShuttleLaunched %s, "
            .. "SV_ShuttleRound %s); it and the pad taken off in 30 s", why, #R.fired > 0 and table.concat(R.fired, ", ")
            or "none", flagText(f, "SV_ShuttleLaunched"), flagText(f, "SV_ShuttleRound")))
    end
    if R.phase ~= "tail" and ((f.SV_ShuttleLost or 0) >= 1 or ALIVE.ask(c.unit, now) <= 0) then
        return finish("the shuttle's gone")
    end
    local open, why = SPC.storeShut(now)
    if R.phase == "wait" then
        if not open then
            if R.waitWhy ~= why and why then
                R.waitWhy = why
                log(string.format("special: shuttle liftoff replay waits: %s (try %d of %d)", why, R.tries + 1, REPLAY_TRIES))
            end
            if now - R.at > REPLAY_WAIT_S then
                return finish(string.format("your STORE was open or you were down at the airfield %d s", REPLAY_WAIT_S))
            end
            return
        end
        R.tries, R.waitWhy = R.tries + 1, nil
        if R.tries == 1 then fireHere(R, T - 14) end   -- (ignition: its boost and sound, once)
        local pad = onPad()
        if pad then fireHere(R, T - 4) end
        R.phase, R.liftAt = "lift", now + (pad and 4 or 0)
        log(string.format("special: shuttle liftoff replayed here, try %d of %d: %s, the climb %s", R.tries, REPLAY_TRIES,
            pad and "onto its path (still on its pad)" or "not onto its path again (already off its pad)",
            pad and "in 4 s" or "now"))
        return
    end
    if R.phase == "lift" then
        if now < R.liftAt then return end
        fireHere(R, T)
        R.phase, R.liftedAt = "check", now
        return
    end
    if R.phase == "check" then
        if now < R.liftedAt + 3 then return end
        if (f.SV_ShuttleLaunched or 0) >= 1 then
            R.phase = "tail"
            R.tail = { { R.liftedAt + 7, T + 7 }, { R.liftedAt + 13, T + 13 }, { R.liftedAt + 30, T + 30 } }
            D.shuttleRemoveAt = now + c.remove_s
            log(string.format("special: shuttle lifted off here at the replay's try %d (SV_ShuttleLaunched %s, "
                .. "SV_ShuttleRound %s, %.0f s after the countdown ran out); taken off in %.0f s", R.tries,
                flagText(f, "SV_ShuttleLaunched"), flagText(f, "SV_ShuttleRound"), now - R.at, c.remove_s))
        elseif R.tries < REPLAY_TRIES then
            R.phase = "wait"
            log(string.format("special: shuttle liftoff replay, try %d: SV_ShuttleLaunched still %s 3 s after the climb: "
                .. "again", R.tries, flagText(f, "SV_ShuttleLaunched")))
        else
            finish(string.format("it never left its pad here in %d tries", REPLAY_TRIES))
        end
        return
    end
    -- the tail at its offsets, each once this game's events can take
    while open and R.tail[1] and now >= R.tail[1][1] do fireHere(R, table.remove(R.tail, 1)[2]) end
    if not R.tail[1] then
        D.shuttleReplay, SPC.gate = nil, nil
        log("special: shuttle liftoff replay done here (events fired " .. table.concat(R.fired, ", ") .. ")")
    end
end
-- (the 5 s check after RE_SV_ShuttleRemove) the flags it sets back to 0 still up: fired again on this game
function SPC.shuttleRemoveCheck(now)
    local f = svFlags() or {}
    if (f.SV_ShuttleRound or 0) < 1 and (f.SV_ShuttleLaunched or 0) < 1 then return false end
    if COOP and COOP.client and COOP.client() then return false end
    SPC.gate = nil
    D.shuttleRemoveAgain = { tries = 0 }
    log(string.format("special: RE_SV_ShuttleRemove didn't take here (SV_ShuttleRound %s, SV_ShuttleLaunched %s): fired "
        .. "again on this game once its STORE is shut", flagText(f, "SV_ShuttleRound"), flagText(f, "SV_ShuttleLaunched")))
    return true
end
function SPC.shuttleRemoveAgainTick(now)
    local A = D.shuttleRemoveAgain
    if not A then return end
    if D.special and D.special.kind == "shuttle" and D.special.state == "countdown" then   -- (a new shuttle's up)
        D.shuttleRemoveAgain, SPC.gate = nil, nil
        return
    end
    if A.checkAt then
        if now < A.checkAt then return end
        local f = svFlags() or {}
        local done = (f.SV_ShuttleRound or 0) < 1 and (f.SV_ShuttleLaunched or 0) < 1
        if done or A.tries >= REMOVE_TRIES then
            D.shuttleRemoveAgain, SPC.gate = nil, nil
            log(string.format("special: RE_SV_ShuttleRemove fired again here %d time%s: %s (SV_ShuttleRound %s, "
                .. "SV_ShuttleLaunched %s)", A.tries, A.tries == 1 and "" or "s", done and "it took" or "it never took",
                flagText(f, "SV_ShuttleRound"), flagText(f, "SV_ShuttleLaunched")))
            return
        end
        A.checkAt = nil
    end
    if not SPC.storeShut(now) then return end
    A.tries, A.checkAt = A.tries + 1, now + 3
    local here = COOP and COOP.eventHere or SV_Event
    local r = type(here) == "function" and here("RE_SV_ShuttleRemove") or -5
    local back = {}
    for u in pairs(D.up or {}) do
        if BOMBER_UNIT[u] and ALIVE.ask(u, now) > 0 and type(here) == "function" then
            back[#back + 1] = u .. " " .. tostring(here(string.format("RE_SV_BomberRetask_%02d", BOMBER_INDEX[u])))
        end
    end
    log(string.format("special: RE_SV_ShuttleRemove fired again here, try %d (%s)%s", A.tries, tostring(r),
        #back > 0 and ("; strike flights back onto the airfield: " .. table.concat(back, ", ")) or ""))
end
-- (from "countdown over" to its removal) every WATCH_S: the flags the raids' orders read and how near anything is to the
-- pad (the "swarm" of her report: the log placed nothing round the pad after its round)
function SPC.shuttleWatchTick(now)
    local at = SHUTTLE.padAt
    if not (at and (D.shuttleRemoveAt or D.shuttleReplay)) then D.shuttleWatchAt = nil; return end
    if now < (D.shuttleWatchAt or now) then return end
    D.shuttleWatchAt = now + WATCH_S
    local f = svFlags() or {}
    local function flat(v) return math.sqrt((v.X - at.X) ^ 2 + (v.Y - at.Y) ^ 2) / 100000 end
    local sh = "not found"
    if liveObj(SHUTTLE.obj) then
        pcall(function()
            local v = SHUTTLE.obj:K2_GetActorLocation()
            sh = string.format("%.1f km from its pad, %.1f km up", flat(v), (v.Z - (at.Z or 0)) / 100000)
        end)
    end
    local near, n5 = nil, 0
    for _, q in ipairs(planes) do
        if valid(q.obj) then
            pcall(function()
                local d = flat(q.obj:K2_GetActorLocation())
                if not near or d < near then near = d end
                if d <= 5 then n5 = n5 + 1 end
            end)
        end
    end
    log(string.format("special: shuttle after its countdown, round %d: SV_ShuttleLaunched %s, SV_ShuttleRound %s; the "
        .. "shuttle %s; the nearest enemy aircraft %s from the pad, %d within 5 km", D.round or 0,
        flagText(f, "SV_ShuttleLaunched"), flagText(f, "SV_ShuttleRound"), sh,
        near and string.format("%.1f km", near) or "none", n5))
end
end
