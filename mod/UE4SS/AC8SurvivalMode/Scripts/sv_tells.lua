-- sv_tells.lua: tells, the behaviour roadmap's P3 ("a radio line or HUD callout before each coordinated threat ... turns
-- cheap-feeling deaths into readable ones"; tools/re/BEHAVIOUR_DIRECTOR.md unit 4).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local (tools/lua_split.py).
--
-- A tell is an id of CFG.tells.list: a radio line (RE_SV_Radio<Suffix>, a remote event of Survival's event package that
-- plays a one-row group of DT_SV_Radio: a stock AC8 line cloned there at build time, tools/survival_events.py
-- TELL_LINES, hard rule 33) and / or a HUD callout (CFG.tells.text). The API (CFG.tells has the settings):
--   TELL.say(id, slot, a, b)   say it to a player: slot nil = this game's own, TELL.ALL = every player, a number = that
--                              player's slot (only the host sends another player's: "tl", sv_coop.lua COOP.tell). a, b:
--                              numbers its text shows (bearings, an o'clock) or its line is picked by. Returns true when
--                              said (here, or sent), else false, why, and a kind ("off", "state", "gap", "cooldown",
--                              "line", "empty")
--   TELL.after(id, slot, fn, a, b, need)   say it, then run fn its lead_s later (CFG.tells.lead_s; TELL.tick, every
--                              250 ms, on the round clock: a pause holds it); not said: fn at once (never with need).
--                              Returns whether it was said
--   TELL.leadS(id)             that lead (0 with tells off here, unless this game hosts co-op: its tells still reach
--                              the joiners), for an action timed elsewhere (a record's delay is frame accurate where
--                              this tick is 0-250 ms late: hard rule 40)
--   TELL.ready(id, slot)       whether it could be said now (a lead-dependent tactic only then)
--   TELL.play(id, a, b, from, force, line)  this game's player only (a joiner's "tl" ends here; force and line, one of
--                              its radio events: the test key's, Ctrl+0)
--   TELL.known(id)             an id of this game's catalog (a joiner checks the host's against its own)
-- Each player's tells are kept apart on their own, by class (urgent ones urgent_gap_s apart, ones with a queued callout
-- gap_s, radio-only ones radio_gap_s after any: classOf), each id no sooner than its cooldown_s, none between rounds,
-- down at the airfield or over the run's summary. An urgent tell goes in front of the callout queue and cuts the
-- banner short (sv_hud.lua hudCallout / calloutNext): it never waits behind four round callouts (up to 16 s), and at
-- most one tell waits there at a time. A radio line is never asked for again within line_gap_s, by whichever tell
-- (reversal and kulbit share theirs): the cloned rows keep the template's RequeueingWaitTime of 20 s, which may skip
-- a group asked for again inside it.
-- CFG.tells.enabled is this game's own switch (PERSONAL in co-op): a host with tells off still sends its joiners theirs
-- ("tl"), and each joiner plays them by its own switches. The host's gaps, cooldowns, leads, hunt_km and
-- wave_from_round decide when a tell is sent.
-- Works with COOP nil (the Offline edition) and without the natives (SV_Event absent: no radio).
TELL = { ALL = "all" }

do
-- hudCallout and SV_Event as they are before sv_coop.lua wraps them (the contract's one exception: this part keeps them
-- at load): a tell is each player's own, so the host's must not go out again as its "co" callout or "ev" event; a
-- joiner gets the host's as "tl" and plays it from its own CFG.tells (RE_SV_Radio* is in sv_coop's KEEP_EVENTS too)
local rawHud, rawEv = hudCallout, SV_Event

local function cfg() return CFG.tells end
local function clockNow() return (D and D.now) or os.clock() end
local function mySlot() return (COOP and COOP.open and COOP.slot) or 0 end
local function isHost() return COOP and COOP.host and COOP.host() or false end

-- this run's tell clocks (D.tells: a new level or run clears them with D); evAt: when each radio event last fired here
local function st()
    if not D then return nil end
    local s = D.tells
    if not s then s = { to = {}, lines = {}, queue = {}, said = {}, evAt = {} }; D.tells = s end
    return s
end
-- one receiver's clocks: "me" (this game's player), a joiner's slot, or "all" (the host's tells to every joiner): when
-- it last had a tell of each class (at), which (lastId), and each id (by)
local function to(s, key)
    local x = s.to[key]
    if not x then x = { at = {}, lastId = {}, by = {} }; s.to[key] = x end
    return x
end

function TELL.known(id)
    local c = cfg()
    return type(id) == "string" and #id <= 32 and id:match("^[%w_]+$") ~= nil and c ~= nil and type(c.list) == "table"
        and type(c.list[id]) == "table"
end

-- (a co-op host's lead stands with its own tells off: they still go to its joiners, which play them by their own)
local function lead(id) return math.max(0, tonumber(cfg().lead_s and cfg().lead_s[id]) or 0) end
function TELL.leadS(id)
    local c = cfg()
    if not (TELL.known(id) and (c.enabled or isHost())) then return 0 end
    return lead(id)
end

-- A tell's class, for its gap: "urgent" (cuts in: urgent_gap_s after the last urgent one; they replace each other in
-- the callout queue), "hud" (a callout that queues: gap_s, the banner's own time, after the last such) or "radio" (a
-- line only: radio_gap_s after the last tell of any class). So the callout queue never fills with tells and lines don't
-- pile up, while the railgun's warning still comes the second after "submarine has surfaced".
local function classOf(e) return e.urgent and "urgent" or (e.hud and "hud" or "radio") end
local GAP_KEY = { urgent = "urgent_gap_s", hud = "gap_s", radio = "radio_gap_s" }
-- why a receiver can't have tell id now (nil: it can), and the kind ("gap", "cooldown")
local function wait(x, id, now)
    local c = cfg()
    local cl = classOf(c.list[id])
    local since = cl == "radio" and x.at.any or x.at[cl]
    local gap = tonumber(c[GAP_KEY[cl]]) or 0
    if since and now - since < gap then
        local last = cl == "radio" and x.lastId.any or x.lastId[cl]
        return string.format("%.1f s after %s, its gap %.1f s", now - since, tostring(last), gap), "gap"
    end
    local cd = tonumber(c.cooldown_s and c.cooldown_s[id]) or 0
    if x.by[id] and now - x.by[id] < cd then return string.format("its cooldown, %.0f s", cd), "cooldown" end
    return nil
end
local function mark(x, id, now)
    local cl = classOf(cfg().list[id])
    x.at[cl], x.lastId[cl], x.at.any, x.lastId.any, x.by[id] = now, id, now, id, now
end

-- why nobody can have a tell now (nil: they can): no run, between rounds, the run's summary up. fromHost: a joiner's
-- tell from the host, whose round state the host checked (a joiner's mirror of it may lag a second)
local function roomBlocked(fromHost)
    if not D then return "no run" end
    if D.state == "wait" and not fromHost then return "between rounds" end
    if LB and LB.show then return "the run is over" end
    return nil
end
-- ... nor this game's player: down at the airfield either (each game its own)
local function blocked(fromHost)
    local why = roomBlocked(fromHost)
    if why then return why end
    local ok, on = pcall(playerOnAirfield)
    if ok and on == true then return "down at the airfield" end
    return nil
end

-- a refusal, once a round per tell and reason (the log's "why not"; a gap or cooldown by its kind, its seconds vary)
local function refused(s, id, why, kind)
    local key = id .. "|" .. ((kind == "gap" or kind == "cooldown") and kind or tostring(why)) .. "|" .. tostring(D and D.round)
    if s and s.said[key] then return end
    if s then s.said[key] = true end
    log(string.format("tell: %s not said (%s)", id, tostring(why)))
end

-- whether radio event ev may be asked for now: not within line_gap_s of its last time here, by any tell (the cloned
-- rows' RequeueingWaitTime is the template's 20 s, tools/build_survival.py build_radio: a group asked for again inside
-- it may be skipped; reversal and kulbit share their lines, and an ace can kulbit 12 s after its reversal)
local function lineFree(s, ev, now)
    local g, t = tonumber(cfg().line_gap_s) or 0, s.evAt[ev]
    return not (t and g > 0 and now - t < g)
end
-- a line of tell id: the a-th (pick "a"), else one at random, not the one it said last when another will do; only
-- lines free now (lineFree). nil, plus true when a line was left out for that
local function pickLine(s, id, e, a, now)
    local list = e.radio
    if type(list) ~= "table" or #list == 0 then return nil end
    if e.pick == "a" then
        local i = math.floor(tonumber(a) or 0)
        local ev = (i >= 1 and i <= #list) and list[i] or nil
        if ev and not lineFree(s, ev, now) then return nil, true end
        return ev
    end
    local free, opts = {}, {}
    for _, ev in ipairs(list) do
        if lineFree(s, ev, now) then
            free[#free + 1] = ev
            if ev ~= s.lines[id] then opts[#opts + 1] = ev end
        end
    end
    if #opts == 0 then opts = free end
    if #opts == 0 then return nil, true end
    return opts[math.random(#opts)]
end

-- a text with the tell's numbers in it (args: "compass" names bearings, "clock" an o'clock); nil stays nil
local function fill(fmt, kind, a, b)
    if type(fmt) ~= "string" or not fmt:find("%", 1, true) then return fmt end
    local x, y = tonumber(a) or 0, tonumber(b) or 0
    if kind == "compass" and type(compassName) == "function" then x, y = compassName(x % 360), compassName(y % 360)
    elseif kind == "clock" then x = math.max(1, math.min(12, math.floor(x + 0.5))) end
    local ok, out = pcall(string.format, fmt, x, y)
    return ok and out or fmt
end

-- fire a line's remote event (its time kept for lineFree once it fired); what happened, for the log
local function fireLine(s, ev, now)
    if not (ev and type(rawEv) == "function") then return "no radio (natives absent)" end
    local ok, r = pcall(rawEv, ev)
    if not ok then return "error " .. tostring(r) end
    if r == 1 then s.evAt[ev] = now; return "fired" end
    return "not fired: " .. tostring(SV_ERR and SV_ERR[r] or r)
end

function TELL.play(id, a, b, from, force, line)
    local c = cfg()
    if not (c and c.enabled) then return false, "tells off", "off" end
    if not TELL.known(id) then return false, "not a tell here", "off" end
    local s = st()
    if not s then return false, "no run", "state" end
    local why = blocked(from ~= nil)
    if why and not force then refused(s, id, why, "state"); return false, why, "state" end
    local now, x = clockNow(), to(s, "me")
    local kind
    why, kind = wait(x, id, now)
    if why and not force then refused(s, id, why, kind); return false, why, kind end
    local e = c.list[id]
    local ev, busy
    if c.radio then ev, busy = pickLine(s, id, e, a, now) end
    if force and line then for _, l in ipairs(e.radio or {}) do if l == line then ev = l end end end
    local text, sub
    if c.hud and e.hud then
        local t = c.text or {}
        text, sub = fill(t[e.hud], e.args, a, b), fill(t[e.hud .. "_sub"], e.args, a, b)
    end
    if not ev and not text then
        if busy then
            why = string.format("each of its lines played within line_gap_s %.0f s", tonumber(c.line_gap_s) or 0)
            refused(s, id, why, "line")
            return false, why, "line"
        end
        refused(s, id, "nothing to show: its radio or HUD half is off", "empty")
        return false, "nothing to show", "empty"
    end
    mark(x, id, now)
    local parts = {}
    if ev then
        s.lines[id] = ev
        parts[#parts + 1] = ev .. " (" .. fireLine(s, ev, now) .. ")"
        local ch = e.chain and c.list[e.chain]                 -- (a line after it, e.g. the dive's o'clock)
        local ev2 = ch and pickLine(s, e.chain, ch, a, now)
        if ev2 then s.lines[e.chain] = ev2; parts[#parts + 1] = "then " .. ev2 .. " (" .. fireLine(s, ev2, now) .. ")" end
    elseif busy then
        parts[#parts + 1] = "no line (each played within line_gap_s)"
    end
    if text and type(rawHud) == "function" then
        local okH = pcall(rawHud, text, sub, nil, e.urgent == true)
        parts[#parts + 1] = string.format("%s '%s'%s", e.urgent and "tell callout" or "callout", text, okH and "" or " (failed)")
    end
    log(string.format("tell: %s%s: %s", id, from and (" (" .. tostring(from) .. "'s)") or "", table.concat(parts, ", ")))
    return true
end

-- the host's tell to another player (key: a slot, or "all" for every joiner), kept apart as this game's own are
local function send(s, key, slot, id, a, b)
    local now, x = clockNow(), to(s, key)
    local why, kind = wait(x, id, now)
    if why then
        refused(s, id, (key == "all" and "every joiner: " or ("player " .. (slot + 1) .. ": ")) .. why, kind)
        return false, why, kind
    end
    local okC, sent = pcall(COOP.tell, slot, id, a, b)
    if not (okC and sent) then return false, "not sent" .. (okC and "" or (": " .. tostring(sent))), "off" end
    mark(x, id, now)
    log(string.format("tell: %s to %s (\"tl\")", id, key == "all" and "every joiner" or ("player " .. (slot + 1))))
    return true
end

-- (this game's own switch, CFG.tells.enabled, is TELL.play's: a co-op host with tells off still sends its joiners
-- theirs, as each player's tells are their own)
function TELL.say(id, slot, a, b)
    local c = cfg()
    if not c then return false, "tells off", "off" end
    if not TELL.known(id) then return false, "not a tell here", "off" end
    if slot == nil or slot == mySlot() then return TELL.play(id, a, b) end
    local s = st()
    if not s then return false, "no run", "state" end
    if slot == TELL.ALL then
        local said, why, kind = TELL.play(id, a, b)
        if isHost() and not roomBlocked(false) then              -- (each joiner checks its own airfield and gaps)
            if send(s, "all", nil, id, a, b) then said = true end
        end
        return said, why, kind
    end
    if not (isHost() and type(slot) == "number") then return false, "only the host tells another player", "off" end
    local why = roomBlocked(false)
    if why then return false, why, "state" end
    return send(s, slot, slot, id, a, b)
end

-- (this game's player: its own switch and state; another player: the host's gaps for them; TELL.ALL: either)
function TELL.ready(id, slot)
    if not TELL.known(id) then return false end
    local s = st()
    if not s or roomBlocked(false) then return false end
    local now = clockNow()
    local function mine() return cfg().enabled == true and not blocked(false) and wait(to(s, "me"), id, now) == nil end
    if slot == nil or slot == mySlot() then return mine() end
    if slot == TELL.ALL then return mine() or (isHost() and wait(to(s, "all"), id, now) == nil) end
    return isHost() and type(slot) == "number" and wait(to(s, slot), id, now) == nil
end

function TELL.after(id, slot, fn, a, b, need)
    local okS, said = pcall(TELL.say, id, slot, a, b)
    if not okS then log("tell: " .. tostring(id) .. " error " .. tostring(said)) end
    said = okS and said == true
    if need and not said then return false end
    local s = st()
    local wait_s = said and lead(id) or 0                   -- (said here or sent: someone has had the tell)
    if wait_s > 0 and s then
        s.queue[#s.queue + 1] = { at = clockNow() + wait_s, fn = fn, id = id }
        return said
    end
    local okF, errF = pcall(fn)
    if not okF then log("tell: " .. tostring(id) .. "'s action failed: " .. tostring(errF)) end
    return said
end

-- every 250 ms (sv_main.lua probeTick, on the round clock): the actions whose lead is up, in the order they were told
function TELL.tick(now)
    local s = D and D.tells
    if not (s and #s.queue > 0) then return end
    now = now or clockNow()
    local due, keep = {}, {}
    for _, q in ipairs(s.queue) do if now >= q.at then due[#due + 1] = q else keep[#keep + 1] = q end end
    s.queue = keep
    for _, q in ipairs(due) do
        local okF, errF = pcall(q.fn)
        if not okF then log("tell: " .. tostring(q.id) .. "'s action failed: " .. tostring(errF)) end
    end
end

-- A hunting tier's flight (CFG.aces.flight <tier>.hunt: ACE.hunt keeps its target on you) within hunt_km of you for
-- the first time this round (p.dist, the 2 s sweep's): "hunt", once a flight a round (its cooldown keeps several
-- flights to one call; only a gap waits for the next sweep). Not on a co-op joiner: the host's planes hunt the host.
function TELL.hunted(p)
    local c = cfg()
    if not (c and c.enabled and D and D.round and p.unit and p.dist) or p.dist > (tonumber(c.hunt_km) or 0) then return end
    if COOP and COOP.client and COOP.client() then return end
    D.tellHunt = D.tellHunt or {}
    if D.tellHunt[p.unit] == D.round then return end
    local said, _, kind = TELL.say("hunt")
    if said or kind == "cooldown" then D.tellHunt[p.unit] = D.round end
end
end
