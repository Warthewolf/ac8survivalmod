-- (sv_coop.lua is the first of 5 pieces, split by tools/lua_split_part.py: sv_coop_joiner.lua, sv_coop_planes.lua,
-- sv_coop_sync.lua, sv_coop_migration.lua go on from where it ends, run by main.lua right after it, in that order.)
-- AC8 Survival Mode - runtime part sv_coop: Survival COOP (CFG.coop; the native half is dlls\main.dll 0.22.0 coop.c;
-- docs/re/COOP.md). Up to 24 players, one run, host-authoritative after the AC7 co-op mod Double Trigger. Player 1
-- (slot 0) is the host, players 2-24 (slots 1-23) the joiners, each linked to the host only:
--   host:    runs everything as in single player. Every flight it spawns (SV_Spawn, with the SV_SetAircraft /
--            SV_SetLevel calls before it) goes to every joiner, every aircraft of it gets a stream id (its position and
--            rotation go out 15 times a second, natively), its health once a second, its death at once. A joiner's
--            hits on its copies come back and are dealt as real damage (ModifyHealth, the cause that joiner's plane).
--            It keeps the roster (each player's name, airframe, version) and sends it to everyone.
--   joiner:  spawns no rounds of its own (roundsTick, airfieldTick and bombTick are the host's): it spawns the host's
--            flights, binds each copy to its stream (the runtime moves it every frame to where the host's is) and keeps
--            it alive (MinHealth) until the host says it's down. Its round, callouts, airfield and round bonuses are
--            the host's. Each player's kills pay their own zollars (KILL.by: another player is the "wingmate" side).
--   everyone: each other player's plane is SV_Unit_CoopPeer<A-X> (A for player 1 ... X for player 24: an allied AI
--            plane, fire off, invincible), moved every frame to where that player is (the host relays the joiners'
--            planes to each other). split_share of the host's fighter flights take the stock allied-hunt order: they
--            go for the joiners' planes too.
-- Messages are "kind|field|field...", reliable unless said: rnd (unreliable), af, co, cr, sp, bd, hp, dn, rs, pi, po,
-- ev, tl, dv, rb, rx, ro, rc, dk (host; dk: THE DECOY's round and locks, sv_decoy.lua), hi, jn, ht, in, rv (joiner; in
-- unreliable), fx and dw (either: a player's shots,
-- a player down; the host relays them; sv_down.lua has the revives').
-- SV_CoopRecv hands them over as "<sender's slot>|<message>".
COOP = { open = false, role = nil, slot = nil, noted = "solo" }

-- The role for logs\session_<stamp>.txt (runtime 0.32.32, the log bundle): "host", "join" or "solo", written when it changes.
-- Called wherever COOP.open / COOP.role are set or cleared (COOP.reopen, closeCoop).
function COOP.noteRole()
    local r = COOP.open and COOP.role or "solo"
    if r ~= "host" and r ~= "join" then r = "solo" end
    if COOP.noted == r then return end
    COOP.noted = r
    if SV_Session then pcall(SV_Session, "role=" .. r) end
end

do
-- one stand-in plane per player slot, A-X (tools/survival_events.py COOP_PEER_SLOTS; user, 2026-10-26: "allow up to
-- 24 players in a lobby"), each with its name key (NAME_KEYS)
local PEER_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWX"
MAX_SLOT = #PEER_LETTERS - 1
PEER_UNITS, NAME_KEYS, SLOT_OF = {}, {}, {}
for s = 0, MAX_SLOT do
    local c = PEER_LETTERS:sub(s + 1, s + 1)
    PEER_UNITS[s], NAME_KEYS[s] = "SV_Unit_CoopPeer" .. c, "SV_CoopName_" .. c
    SLOT_OF[PEER_UNITS[s]] = s
end
local M = {
    nextId = 0, units = {}, byId = {},        -- host: the flights mirrored, and every aircraft by stream id
    cunits = {}, copies = {}, dead = {},       -- joiner: the host's flights here, the bound copies, ids already down
    objsOf = {}, downAt = {},                  -- joiner (0.73.73): every object of each unit spawned here; when one went down
    spawnQ = {}, hunts = {}, mirror = 0,       -- joiner's spawns waiting, host's hunt orders waiting, inside the rounds
    peers = {}, roster = {}, hiFrom = {},      -- the other players' planes here by slot; the roster (host: kept, joiner: told)
    lastD = nil, said = {}, nextRnd = 0, nextHp = 0, nextAf = 0, nextInfo = 0, nextHi = 0,
    stateAt = {}, freshAt = {}, lostAt = {}, holding = {},   -- (0.73.80, the host's round hold: COOP.joinWaiting, M.noteLost)
}
COOP.M = M                                         -- (M, handed to sv_coop.lua's later pieces: tools/lua_split_part.py)
function cfg() return CFG.coop end
function COOP.host() return COOP.open and COOP.role == "host" end
function COOP.client() return COOP.open and COOP.role == "join" end

local function clean(s) return (tostring(s or ""):gsub("|", "/")) end
-- to: a slot, or nil for every other game (a joiner's go to the host)
function sendTo(to, reliable, ...)
    if not COOP.open or type(SV_CoopSend) ~= "function" then return false end
    local parts = { ... }
    for i = 1, #parts do parts[i] = clean(parts[i]) end
    return SV_CoopSend(table.concat(parts, "|"), reliable and 1 or 0, to or -1) > 0
end
function send(reliable, ...) return sendTo(nil, reliable, ...) end
-- ((0.73.77, the plan's I2: S9) a penalty the host's run takes (the Spaceport Retake's escaped rocket: sv_spaceport.lua
-- SPORT.debit) off every joiner's zollars too: "db|<n>|<why>" ("cr" carries pay only; the escape's -5,000 came off the
-- host's money alone while its callout went to everyone). Each game takes what it has of it.
function COOP.debit(n, why)
    n = math.floor(tonumber(n) or 0)
    if not COOP.host() or n <= 0 then return end
    send(true, "db", n, tostring(why or ""):sub(1, 80))
    log(string.format("coop: a penalty of %d (%s) sent to every joiner (%d linked)", n, tostring(why), M.linkedPeers or 0))
end
-- (0.74.0) GONE FISHIN' and THE FESTIVAL (sv_fishing.lua, sv_festival.lua): the host's round, its numbers to every joiner.
--   "fh|<slot>|<catch>|<kg>|<x>|<y>"  a shoal's catch, credited to player <slot> (-1: the allies', shared out at the
--                                     weigh-in), where it was (each game's splash)
--   "fsx|<kind>|<state>|<a>|<b>|<c>"  the special's NEXT row numbers once a second (fishing: secs left, shoals left, the
--                                     team's kg; festival: bombers up, missiles in the air), unreliable
--   "fw|<slot>|<kg>|<hits>|<empty>|<best>|<bestKg>|<bigone>" one player's weigh-in (each game grades and pays its own)
--   "fwe|<players>|<teamKg>|<allyKg>|<round>|<shoals>"  the weigh-in's card: each game pays its own player's haul
--   "sb|<speaker>|<text>|<secs>"      a subtitle line (SUB.say in the host's round logic, as hudCallout's "co")
-- Each game's own pay goes through COOP.payOwn: never split, never sent as "cr".
function COOP.fishCatch(slot, catch, kg, x, y)
    if COOP.host() then
        send(true, "fh", slot, catch, string.format("%d", math.floor(tonumber(kg) or 0)), string.format("%.0f", tonumber(x) or 0),
            string.format("%.0f", tonumber(y) or 0))
    end
end
function COOP.specialRow(kind, state, a, b, c)
    if COOP.host() then send(false, "fsx", kind, state, a or 0, b or 0, c or 0) end
end
function COOP.fishWeigh(slot, kg, hits, empty, best, bestKg, bigone)
    if COOP.host() then send(true, "fw", slot, kg, hits, empty, best or "", bestKg or 0, bigone and 1 or 0) end
end
function COOP.fishWeighEnd(players, teamKg, allyKg, round, total)
    if COOP.host() then send(true, "fwe", players, teamKg, allyKg, round, total) end
end
-- every player's slot in the room (the roster), this game's first; { 0 } solo
function COOP.slots()
    local out, me = {}, COOP.slot or 0
    out[1] = me
    if COOP.open then for s in pairs(M.roster) do if s ~= me then out[#out + 1] = s end end end
    table.sort(out, function(a, b) if a == me then return true elseif b == me then return false end return a < b end)
    return out
end
-- this game's own pay (GONE FISHIN''s haul): its addCredits whole, not a special's split, not sent to the joiners
function COOP.payOwn(n, why)
    M.ownPay = true
    local ok, err = pcall(addCredits, n, why)
    M.ownPay = false
    if not ok then log("coop: own pay error " .. tostring(err)) end
end
-- (the host) one object taken off without a kill (THE FESTIVAL's missile on the runway): its copies down on every game
-- first, unpaid ("dn|<id>|r"), as COOP.removeNow does a whole unit's. Whether it had an id.
-- ((code review of 2026-11-07, finding 11) (the host) object o held unpaid (on) or let go (off): should it go down while
-- held, its "dn" is a removal ("r": nobody's kill, on every game). Whether o is one of the host's mirrored objects
function COOP.payHold(o, on)
    if not (COOP.host() and o ~= nil) then return false end
    local a = addrOf(o)
    if not a then return false end
    for _, e in pairs(M.byId) do
        if e.addr == a and not e.dead then e.unpaid = on and true or nil; return true end
    end
    return false
end
function COOP.removeObj(o)
    if not (COOP.host() and o ~= nil) then return false end
    local a = addrOf(o)
    if not a then return false end
    for id, e in pairs(M.byId) do
        if e.addr == a and not e.dead then
            e.dead, e.deadAt, e.killer = true, os.clock(), false
            send(true, "dn", id, "r", "")
            if not e.key and type(SV_CoopTrack) == "function" then SV_CoopTrack(id, 0) end
            local u = M.units[e.unit]
            if u and e.ord and u.planes[e.ord] then u.planes[e.ord].dead = true end
            if u and e.key and u.ground[e.key] then u.ground[e.key].dead = true end
            return true
        end
    end
    return false
end
-- (0.73.76) VALKA in co-op (user, 2026-11-03: "will the red sky sync in coop?" ... "do it"): her round runs on the host
-- alone, so the host tells every joiner when her mood (the red sky, her song) starts and ends ("vm|1" / "vm|0") and when
-- she shows ("vr|<unit>": each game puts her X-02S and paint on its own copy of her); a joiner who links mid-fight gets
-- both with the host's whole picture.
-- (0.73.77, plan D1-D2) Also from one place every start and end of hers passes through: M.valkaWatch, each co-op tick on
-- the host, holds the joiners to her round's state (D.special: kind valka, moodOn), so any way she comes (her round, the
-- reveal mid-round after her decoys, a forced start) or goes (shot down, the run over, the level left) reaches them. In
-- gloom's run of 2026-11-02 dukka's game logged no mood at all, and the host logged nothing it sent: each send logs now.
function COOP.valkaMood(on)
    M.vmood = on == true
    if not on then M.vrev = nil end
    if COOP.host() then
        send(true, "vm", on and 1 or 0)
        log(string.format("coop: VALKA's mood %s: sent to every joiner (%d linked)", on and "on (the red sky, her song)" or "off",
            M.linkedPeers or 0))
    end
end
function COOP.valkaReveal(unit)
    M.vrev = unit
    if COOP.host() then send(true, "vr", unit) end
end
-- (0.73.77, plan D2) a joiner's VALKA mood (the host's "vm"), and taken off here when the host's run starts over or a new
-- host's level comes ("rs"), a new run or level starts here, or this game becomes the host (a migration): never left
-- red or playing with nobody left to say off. why: "the host's" for the host's own word.
function M.valkaHere(on, why)
    local c = CFG.specials and CFG.specials.valka
    if on then
        if not (c and D) then
            log("coop: the host's VALKA mood on: not here (" .. (c and "no run here yet: it comes again with the host's picture"
                or "no VALKA in this build") .. ")")
            return
        end
        if c.red and c.red.enabled ~= false then pcall(hudRed, true, c.red) end
        pcall(function() SND.songStart(c.song) end)
        log("coop: the host's VALKA mood on: the sky red and her song here too" .. (M.vmHere and " (again: the host's picture)" or ""))
        M.vmHere = true
        return
    end
    local was = M.vmHere
    M.vmHere, M.vr = nil, nil
    pcall(hudRed, false)                                     -- (faded by redTick, which drops a sky whose level is gone)
    if c then pcall(function() SND.songFade(c.song and c.song.out_s or 5) end) end
    if why == "the host's" then log("coop: the host's VALKA mood off: the sky and her song fading")
    elseif was then log("coop: VALKA's mood off here (" .. tostring(why) .. "): the sky and her song fading") end
end
-- (the host, every co-op tick) the joiners held to VALKA's round here: her mood on from SPC.V.mood (moodOn) until she's
-- down or her round's gone, her reveal (revealedAt); a special of hers that ended with its mood still on (its round
-- replaced without her end, or "done" without moodOff: she couldn't spawn after her lurk had turned it on) faded here
-- too; a joiner that became the host lets go of the old host's mood unless hers is on here
function M.valkaWatch()
    if not COOP.host() then return end
    local s = D and D.special
    local c = CFG.specials and CFG.specials.valka
    local on = s ~= nil and s.kind == "valka" and s.moodOn == true and s.state ~= "done"
    if M.vmHere then
        if not on then M.valkaHere(false, "this game is the host now") end
        M.vmHere = nil
    end
    local stale = (M.vS and M.vS ~= s and M.vS.moodOn and M.vS) or (s and s.kind == "valka" and s.moodOn and s.state == "done" and s) or nil
    if stale and SPC and SPC.V and SPC.V.moodOff then
        log("coop: VALKA's round " .. (stale == s and "is over" or "went") .. " with her mood still on: faded here and on every joiner")
        pcall(SPC.V.moodOff, c, stale, D and D.now or os.clock())
    end
    M.vS = on and s or nil
    if on ~= (M.vmood == true) then COOP.valkaMood(on) end
    if on and c and s.revealedAt and M.vrev ~= c.unit then COOP.valkaReveal(c.unit) end
end
function split(s)
    local t = {}
    for f in (s .. "|"):gmatch("([^|]*)|") do t[#t + 1] = f end
    return t
end
function once(key, msg) if not M.said[key] then M.said[key] = true; log(msg) end end
-- Guards on what another game sends (security review of 2026-10-26: a broken or hostile game must not crash, hang or
-- take over this one): text cut to a length, numbers finite and in range, slots and NPC rows ones this game has.
function short(v, n) return (tostring(v or ""):sub(1, n)) end
function finite(v, lim) return type(v) == "number" and v == v and v > -lim and v < lim end
HIT_MAX, CREDITS_MAX = 100000, 1000000                -- (one hit's damage; one round bonus's zollars)
TL_PER_S = 4                                          -- (the host's tells a joiner plays in a second, at most)
AIRFRAME_WAIT_S = 5                                   -- (s a stand-in waits for its player's airframe: peerTick)
HELLO_WAIT_S = 30                                     -- (... and for any hello at all from them: peerTick)
function slotOk(s) return type(s) == "number" and s == math.floor(s) and s >= 0 and s <= MAX_SLOT end
local knownRows = {}
function knownRow(row)                                -- a row of Survival's NPC table here (DT_SV_NpcMission)
    if type(row) ~= "string" or #row == 0 or #row > 64 or not row:match("^[%w_]+$") then return false end
    if knownRows[row] then return true end
    local dt = loadObject("/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission")
    if not dt then return true end                          -- (it can't be checked: as before)
    local ok, r = dtCall(dt, "FindRow", row)
    if ok and r ~= nil then knownRows[row] = true; return true end
    return false
end
function standInRow(row)                              -- another player's airframe: one of CFG.coop.airframes
    local c = cfg()
    if type(row) == "string" and row ~= "" then
        if row == c.default then return row end
        for _, r in pairs(c.airframes) do if r == row then return row end end
    end
    return c.default
end
function callout(text, sub)
    if cfg().callouts and type(hudCallout) == "function" then M.noMirror = true; pcall(hudCallout, text, sub); M.noMirror = false end
end
-- ((0.73.83) Rapt0r's "not gaining score" (the 0.73.79 run of 2026-11-04): a callout of this game's own that isn't sent to
-- the joiners, whatever [coop] callouts says (the round's kills: each game shows its own)
function COOP.localCallout(text, sub, big)
    if type(hudCallout) ~= "function" then return end
    M.noMirror = true
    pcall(hudCallout, text, sub, big)
    M.noMirror = false
end
function health(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return ok and type(h) == "number" and h or nil
end
-- (0.73.73) o's address while it's a live object (sv_core's liveAddr: GUObjectArray, outers too), else nil: for objects
-- kept between ticks (the copies, the units' objects)
function live(o)
    if type(liveAddr) == "function" then return liveAddr(o) end
    return valid(o) and addrOf(o) or nil
end
function myAddr()                                  -- (0.73.77) your plane's address here, or nil
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    return valid(pawn) and addrOf(pawn) or nil
end
function playerName(slot)
    local r = M.roster[slot]
    return (r and r.name and r.name ~= "") and r.name or ("PLAYER " .. (slot + 1))
end
function playerCount()
    local n = 0
    for _ in pairs(M.roster) do n = n + 1 end
    return math.max(n, 1)
end
-- A round's aircraft (or a wave's) for the host's room (sv_rounds.lua startRound): aircraft_per_player more for each
-- player past the first, up to `cap` if given (a round's: TIER.coopCap, CFG.coop.max_aircraft grown with the late
-- rounds), else CFG.coop[capKey], never fewer than one player gets
function COOP.more(n, capKey, cap)
    local c = cfg()
    local p = COOP.host() and playerCount() or 1
    if p <= 1 or type(n) ~= "number" then return n end
    local m = math.floor(n * (1 + (tonumber(c.aircraft_per_player) or 0) * (p - 1)) + 0.5)
    return math.max(n, math.min(m, tonumber(cap) or tonumber(c[capKey]) or m))
end
-- A tell (sv_tells.lua TELL.say) to joiner `slot`, or to every joiner (nil): "tl", its id and the number its line is
-- picked by only; the joiner plays it from its own CFG.tells (lines and switches: PERSONAL), nothing free-form crosses
function COOP.tell(slot, id, a)
    if not COOP.host() or (slot ~= nil and not slotOk(slot)) or type(id) ~= "string" then return false end
    local function num(v) return (type(v) == "number" and finite(v, 1e6)) and string.format("%.6g", v) or "" end
    return sendTo(slot, true, "tl", short(id, 32), num(a))
end
-- The squad director's events on one joiner's copies (sv_director.lua: a bracket salvo aimed at that player, fired by
-- that game so its own copies shoot at it, never by "ev" to every joiner): "dv", the event, its flight and a delay (the
-- tell's lead, timed there so the link's latency doesn't eat it). Only RE_SV_Salvo_<NN><L>, RE_SV_Dir*_<NN> and
-- RE_SV_Wolf*_<NN><L> names, the flight the event's own (NN its pool index); the delay 0-3 s; the joiner drops it when
-- its level isn't ready, it has no live copy of that plane (or flight), or more than DV_PER_S came that second, and one
-- still queued DV_LATE_S past its time (its level stopped being ready meanwhile: a salvo seconds late misleads; code
-- review of 2026-10-29).
DV_PER_S, DV_MAX_S, DV_LATE_S = 8, 3.0, 1.0
function dvName(ev)
    return type(ev) == "string" and #ev <= 64 and (ev:match("^RE_SV_Salvo_%d%d%u$") or ev:match("^RE_SV_Dir%a+_%d%d$")
        or ev:match("^RE_SV_Wolf%a+_%d%d%u$")) ~= nil
end
-- (a joiner) the host's flight `unit` is up here as the event wants: its plane <L> (one per letter), else any copy
function dvCopy(ev, unit)
    local nn = tostring(ev):match("_(%d%d)%u?$")
    if not (nn and poolIndex(unit) == tonumber(nn)) then return false end
    local cu = M.cunits[unit]
    if not (cu and cu.n > 0) then return false end
    local L = tostring(ev):match("_%d%d(%u)$")
    for ord, o in pairs(cu.planes) do
        local id = cu.binds[ord]
        if (not L or ord == L:byte() - 64) and valid(o) and not (id and M.dead[id]) then return true end
    end
    return false
end
function COOP.dispatch(slot, ev, unit, delay)
    if not COOP.host() or not slotOk(slot) or slot == COOP.slot or not dvName(ev) or type(unit) ~= "string" then return false end
    local d = tonumber(delay) or 0
    if not finite(d, 1e6) then d = 0 end
    return sendTo(slot, true, "dv", ev, short(unit, 96), string.format("%.2f", math.max(0, math.min(DV_MAX_S, d))))
end
-- The intensity director's scores (sv_director.lua, P4): a joiner sends its player's to the host once a second ("in",
-- unreliable: intensity and comfort 0-100, health %, missiles homing on it), clamped here and there; the host keeps each
-- player's last (IN_FRESH_S old at most) for the room's decisions. Nothing but those four numbers crosses.
IN_FRESH_S, IN_MIN_GAP_S, IN_MSL_MAX = 3, 0.25, 20
function inNum(v, hi)
    v = tonumber(v)
    if not (v and finite(v, 1e9)) then return nil end
    return math.max(0, math.min(hi, v))
end
function COOP.sendIntensity(i, c, hp, m)
    if not COOP.client() then return false end
    local function f(v, hi) local x = inNum(v, hi); return x and string.format("%.1f", x) or "" end
    return send(false, "in", f(i, 100), f(c, 100), f(hp, 100), f(m, IN_MSL_MAX))
end
function COOP.intensityOf(slot)
    local x = M.ints and M.ints[slot]
    if not x or os.clock() - x.at > IN_FRESH_S then return nil end
    return x
end
-- The host's split-hunt flight (it went after the joiners' planes, RE_SV_Hunt_NN, this spawn): the director gives it its
-- hunt back after a hold
function COOP.hunted(unit)
    local u = M.units[unit]
    return u ~= nil and M.hunted ~= nil and M.hunted[unit] == u.gen
end
function maxPlayers()                          -- (a joiner: the host's room, from its settings)
    if COOP.client() and M.hostMax then return M.hostMax end
    return math.max(2, math.min(MAX_SLOT + 1, math.floor(tonumber(cfg().max_players) or MAX_SLOT + 1)))
end

---------------------------------------------------------------------------------------------------- the natives, wrapped
-- (registered by dlls/main.dll before this script ran; every part calls them by their global names)
-- (the crash breadcrumbs, sv_core.lua's crumb: a part loaded without it, as the tests load this one, gets none)
local crumb = crumb or function() end
rawSpawn, rawSetAircraft, rawSetLevel, rawUnitAlive = SV_Spawn, SV_SetAircraft, SV_SetLevel, SV_UnitAlive
local acOps, levels = {}, {}                                 -- host: per unit, since its last spawn
if rawSetAircraft then
    SV_SetAircraft = function(unit, row, idx)
        local r
        if idx == nil then r = rawSetAircraft(unit, row) else r = rawSetAircraft(unit, row, idx) end
        if COOP.host() and type(unit) == "string" and not SLOT_OF[unit] then
            acOps[unit] = acOps[unit] or {}
            table.insert(acOps[unit], { row = row, idx = idx or -1 })
        end
        return r
    end
end
if rawSetLevel then
    SV_SetLevel = function(unit, level)
        local r = rawSetLevel(unit, level)
        if COOP.host() and type(unit) == "string" then levels[unit] = level end
        return r
    end
end
if rawSpawn then
    -- (0.73.80, the 31-round co-op test's findings coop4 / coop5) A host spawn whose caller named no unit (the amphibious
    -- assault's landing craft, sv_amphib.lua; the STORE's defences, sv_shop.lua; the shuttle's pad, sv_spawn.lua) is
    -- named for the call: the new-object feed below gives a unit's ships, vehicles and parts their co-op ids only while
    -- spawningUnit names it, so these never had any. On the joiners their copies were never bound (no floor, no host
    -- health, no "dn", none of their hits sent): each game sank its own landing craft and lost its own guns (round 24's
    -- craft; the defences lost host 7 / Shazzy 12 / cressendo 9 / dukka 11), and the others' replayed missiles at them
    -- flew unguided (target id 0). Every other reader of spawningUnit picks its own units (the troops, the specials'
    -- clean-up, the Ladons, the Spaceport, the Alicorn) and sv_core's plane feed never sees these (no planes in them).
    -- A caller's own spawningUnit is left as it is.
    local function spawnRaw(unit, x, y, z, yaw)
        if x ~= nil then return rawSpawn(unit, x, y, z, yaw) end
        return rawSpawn(unit)
    end
    SV_Spawn = function(unit, x, y, z, yaw)
        local r
        if spawningUnit == nil and type(unit) == "string" and COOP.host() and not SLOT_OF[unit] then
            spawningUnit = unit
            local okR, v = pcall(spawnRaw, unit, x, y, z, yaw)
            spawningUnit = nil                               -- (as it was, whatever the spawn did)
            if not okR then error(v, 0) end
            r = v
            once("named" .. unit, string.format("coop: %s spawned with no unit named by its caller: named for the call, "
                .. "its ships, vehicles and parts get co-op ids (0.73.80)", unit))
        else
            r = spawnRaw(unit, x, y, z, yaw)
        end
        crumb(string.format("spawn %s%s: %s", tostring(unit), x ~= nil and " at a pose" or "", tostring(r)))
        if type(r) == "number" and r > 0 and SPC and SPC.sawSpawn then SPC.sawSpawn(unit) end   -- ((0.73.83) SPC.recycleLater's)
        if COOP.host() and type(unit) == "string" and not SLOT_OF[unit] then
            local ops, lvl = acOps[unit], levels[unit]
            acOps[unit], levels[unit] = nil, nil
            if type(r) == "number" and r > 0 then
                local okS, errS = pcall(COOP.hostSpawned, unit, x and { x, y, z, yaw } or nil, ops, lvl)
                if not okS then log("coop: spawn mirror error " .. tostring(errS)) end
            end
        end
        return r
    end
end

-- The host's scripted events (SV_Event: the event package's RE_SV_* remote events) go to every joiner, whose game fires
-- them too (user, 2026-10-25: "nagase didn't talk and the shuttle never launched on their side", then "make sure that
-- all the coop events are forwarded to the joiners"): the shuttle's countdown (its radio, ignition, liftoff), the
-- specials' scripted attacks and moves (Ladon volleys, the Alicorn, the Anomaly's field, camera and end, AB.L..IN's ECM
-- and gun, VALKA), bomb runs, flight / escort / bomber orders, the landing craft's removals. All but these:
local KEEP_EVENTS = {
    "^RE_SV_RepairAircraft$", "^RE_SV_Decoy", "^RE_SV_Ally", "^RE_SV_Strike", "^RE_SV_Beat$",   -- each player's own
    "^RE_SV_Hunt_",            -- the host's flights after the joiners' planes (a joiner's copies go for the joiner anyway)
    "^RE_SV_AceTurn_", "^RE_SV_AceKulbit_",  -- moves around the host's plane: a joiner sees them in the copies' stream
    "^RE_SV_GlitchBlink", "^RE_SV_ValkaTp_",
    "^RE_SV_AirfieldOpen$", "^RE_SV_AirfieldClose$",                    -- (the airfield goes as "af")
    "^RE_SV_AnomalyField",     -- each player's own field: a joiner's game runs ANOM.clientTick on its own distance
    "^RE_SV_Radio",            -- the tells' radio lines (sv_tells.lua): each player's own, a joiner's come as "tl"
    "^RE_SV_WolfTurn",         -- a Wolf trap's LastTGT (P1, sv_spawn.lua WOLF): onto LocalPlayer, the host here
    "^RE_SV_Salvo_",           -- the squad director's missile shots at "Player" (P2): the host's own; a joiner's by "dv"
    "^RE_SV_SpecFire_",        -- an enemy's special weapon at "Player" (sv_spweapons.lua): each game fires its own at its player
    "^RE_SV_AnomalyPack",      -- PHANTASM's pack (P7): sprung on the host's field, its LastTGT onto the host (puppets there)
    "^RE_SV_WraithBlink",      -- an ace squadron lead's blink (P9): a spot round "Player", the host here (the stream shows it)
    "^RE_SV_RunOver$",         -- a co-op run's end (sv_down.lua): each game fires its own on the host's "ro"
    -- THE DECOY (sv_decoy.lua; "^RE_SV_Decoy" above keeps them all too, written out so a narrower rule for the STORE's
    -- decoy can't let them through): the Spear and its sure kill at "Player" (only the locked player's game calls them),
    -- each game's own lasers on its own marks, its bait's ping and its radio lines (the host's locks come as "dk")
    "^RE_SV_DecoySpear_", "^RE_SV_DecoyKill$", "^RE_SV_DecoyLaser", "^RE_SV_DecoyBait", "^RE_SV_DecoyRadio_",
}                              -- ((code review of 2026-11-07, finding 1) the carriers' RE_SV_CargoLaunch_<s>_<n> is
                               -- forwarded for the look: each joiner's copy of the ship launches ZFA-44s of its own, which
                               -- M.standInSet takes as the host's allies' (sv_escort.lua ESC.localZfa), hostEvent takes the
                               -- arm's unit off that game's list first (ESC.beforeHostEvent) and "es" field 10 takes them
                               -- off with their ship)
                               -- (holds and frees, RE_SV_WolfHold / WolfFree and RE_SV_DirHold / DirFree, are forwarded:
                               -- a joiner's copies hold too; so is a Ladon's rage, RE_SV_LadonRage<Key>, P7: harmless,
                               -- the copies are moved by the stream. AB.L..IN's LastTGT, RE_SV_GlitchTurn, is the host's
                               -- by mirroredEvent's RE_SV_Glitch rule)
function mirroredEvent(name)
    name = tostring(name)
    if not name:match("^RE_SV_") then return false end
    if name:match("^RE_SV_Glitch") and not (name:match("^RE_SV_GlitchEcm") or name:match("^RE_SV_GlitchGun")) then
        return false                                     -- (AB.L..IN's post-stall moves and blinks: as the aces' turns)
    end
    for _, p in ipairs(KEEP_EVENTS) do if name:match(p) then return false end end
    return true
end
-- The host's events aimed at its own plane ("Player" / LocalPlayer there) aren't fired on the host's game while the host
-- is DOWN (sv_down.lua: hidden, flown round the airfield, out of the fight): the squad director's salvos, a Wolf trap's
-- and AB.L..IN's LastTGT, the aces' turns and kulbits, the blinks round it (Wraith's, AB.L..IN's, VALKA's), MINDRIPPER's
-- pack, AB.L..IN's gun; what's forwarded still goes to the joiners. SV_ERR[-20] says so.
local HOST_DOWN_SKIPS = { "^RE_SV_Salvo_", "^RE_SV_WolfTurn", "^RE_SV_AceTurn_", "^RE_SV_AceKulbit_", "^RE_SV_WraithBlink",
                          "^RE_SV_GlitchBlink", "^RE_SV_GlitchTurn", "^RE_SV_GlitchGun", "^RE_SV_ValkaTp_", "^RE_SV_AnomalyPackSpring",
                          "^RE_SV_DecoySpear_", "^RE_SV_DecoyKill$" }        -- (THE DECOY's Spear: sv_decoy.lua)
local function hostDownSkips(name)
    if not (COOP.host() and DOWN and DOWN.me and DOWN.me()) then return false end
    name = tostring(name)
    for _, p in ipairs(HOST_DOWN_SKIPS) do
        if name:match(p) then
            M.downSkips = (M.downSkips or 0) + 1
            if M.downSkips <= 5 or M.downSkips % 50 == 0 then
                log(string.format("coop: %s not fired here: you're down (%d skipped)", name, M.downSkips))
            end
            return true
        end
    end
    return false
end
rawEvent = SV_Event
if rawEvent then
    SV_Event = function(name, ...)
        local r
        if hostDownSkips(name) then r = -20 else r = rawEvent(name, ...) end
        local nm = tostring(name)
        if nm:find("Remove", 1, true) or nm:find("Off_", 1, true) or nm:find("RunOver", 1, true) or nm:find("Destroy", 1, true) then
            crumb("event " .. nm .. ": " .. tostring(r))
        end
        if COOP.host() and mirroredEvent(name) then send(true, "ev", name) end
        return r
    end
end
-- An event fired on this game alone, whatever mirroredEvent says of its name: AB.L..IN's phase-3 gun (RE_SV_GlitchGun
-- outside a frenzy) is aimed on the host's geometry, and forwarded it fired each joiner's copy at that joiner while the
-- host was close in front of it (code review of 2026-10-29); its frenzies' are still forwarded
function COOP.eventHere(name)
    local fire = rawEvent or SV_Event
    if hostDownSkips(name) then return -20 end
    return type(fire) == "function" and fire(name) or -5
end
-- ((2026-11-11) and the other way round) an event sent to the other players as the host's SV_Event sends it, not fired on
-- this game: the shuttle countdown's tail while the host's own liftoff is replayed (sv_rounds.lua SPC.shuttleReplayTick).
-- 1 when it was sent, 0 when it isn't one to send (not the host, or an event each game fires for its own)
function COOP.eventThere(name)
    if not (COOP.host() and mirroredEvent(name)) then return 0 end
    send(true, "ev", name)
    return 1
end

---------------------------------------------------------------------------------------------------- host
local function opsText(ops)
    if not ops or #ops == 0 then return "-" end
    local t = {}
    for _, o in ipairs(ops) do t[#t + 1] = o.row .. "@" .. tostring(o.idx) end
    return table.concat(t, ";")
end
local function poseText(p)
    if not p then return "-" end
    return string.format("%.0f,%.0f,%.0f,%.1f", p[1], p[2], p[3], p[4] or 0)
end
local function sendUnit(to, unit, u)
    sendTo(to, true, "sp", unit, poseText(u.pose), opsText(u.ops), u.level or -1, u.gen)
end

function COOP.hostSpawned(unit, pose, ops, level)
    M.gen = (M.gen or 0) + 1
    M.units[unit] = { gen = M.gen, pose = pose, ops = ops, level = level, n = 0, planes = {}, ground = {}, at = os.clock() }
    sendUnit(nil, unit, M.units[unit])
end

-- A flight's ships, vehicles and parts (every AI object SV_Spawn makes that isn't a plane: the landing craft and
-- their troops, the Alicorn's hull and parts, the Ladons' pods, the shuttle) are linked like its planes, but by their
-- class and order (key "<class>#<n>": both games build a unit's objects alike) and never moved: they keep to their own
-- paths. Friends' run of 2026-10-26 (coop.11): "Lcacs ... dont die synced, if one player kills them, the others dont
-- see them", and a joiner who restarted mid-Alicorn got a fresh one, all its tanks up, its core shut. The host's
-- health and deaths go to every game, the joiners' hits to the host, as for the planes.
groundNew = {}
-- the allies' units (MOONCHILD's / the WINGMEN's flights, the ships) and the airfield's defences (AA guns, SAM sites,
-- CIWS): the host's, mirrored like its enemies; on a joiner's game their copies fight the enemies' copies there, so
-- neither what they deal nor what they take is sent to the host (it's the host's own allies' fight, dealt there)
-- ((0.73.80) and the shuttle's pad, its dummies and its guns (CFG.specials.shuttle dummies / pad): ids of their own since
-- 0.73.80 (the SV_Spawn wrapper above), the enemies' copies' bombs on them here aren't a joiner's hits, and one down on
-- the host is nobody's kill (hostKiller))
local allySet
function allyUnit(u)
    if not allySet then
        allySet = {}
        for x in pairs(ALLY and ALLY.unit or {}) do allySet[x] = true end
        local d = CFG.shop and CFG.shop.items and CFG.shop.items.Airfield and CFG.shop.items.Airfield.defences
        for _, def in pairs(d or {}) do
            if type(def) == "table" and type(def.units) == "table" then for _, x in ipairs(def.units) do allySet[x] = true end end
        end
        local sh = CFG.specials and CFG.specials.shuttle
        if type(sh) == "table" then
            for _, k in ipairs({ "dummies", "pad" }) do if type(sh[k]) == "string" and sh[k] ~= "" then allySet[sh[k]] = true end end
        end
        -- ((0.74.0) SAL's boat and THE FESTIVAL's searchlights: the host's allies, a hit on a copy never sent)
        local fi, fe = CFG.specials and CFG.specials.fishing, CFG.specials and CFG.specials.festival
        if type(fi) == "table" and type(fi.boat_unit) == "string" then allySet[fi.boat_unit] = true end
        for _, x in ipairs(type(fe) == "table" and type(fe.lights) == "table" and fe.lights or {}) do allySet[x] = true end
    end
    return u ~= nil and allySet[u] == true
end
COOP.allyUnit = allyUnit
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    if COOP.open and u and not SLOT_OF[u] and #groundNew < 600 then groundNew[#groundNew + 1] = { obj = o, unit = u, at = os.clock() } end
end)
local planeCls
local function isPlane(o)                                    -- (planes come through logPlane; unknown: left alone)
    if not (planeCls and valid(planeCls)) then planeCls = StaticFindObject("/Script/Live.LiveAIPlane") end
    local ok, r = pcall(function() return o:IsA(planeCls) end)
    return not (ok and r == false)
end
function groundKey(o, counts)
    local cls = nameOf(o):match("%.([%w_]+)_%d+$") or "obj"
    counts[cls] = (counts[cls] or 0) + 1
    return short(cls, 80) .. "#" .. counts[cls]
end
hostGround, clientGround = nil, nil                               -- (below: the host's and the joiner's)
function groundTick()
    if #groundNew == 0 then return end
    local now, keep, given = os.clock(), {}, nil
    for _, g in ipairs(groundNew) do
        if now - g.at < 0.5 then
            keep[#keep + 1] = g                              -- (a moment to be placed and named)
        elseif live(g.obj) and inSurvival(g.obj) and not isPlane(g.obj) then   -- ((0.73.80) live: kept half a second)
            local ok, err = pcall(COOP.host() and hostGround or clientGround, g.obj, g.unit)
            if not ok then once("ground", "coop: ship / vehicle error " .. tostring(err))
            elseif err == true then given = given or {}; given[g.unit] = (given[g.unit] or 0) + 1 end
        end
    end
    groundNew = keep
    -- ((0.73.80) the host: each unit's ground objects given ids this pass, a line a spawn (the joiners' "N of M bound" in
    -- strayTick): the amphibious assault's craft, the defences and the shuttle's pad never got any before)
    for unit, n in pairs(given or {}) do
        local u = M.units[unit]
        log(string.format("coop: %s: %d ground objects given ids (gen %s, %d in all)", unit, n, tostring(u and u.gen),
            u and u.gn or n))
    end
end

local function anyJoinerPlane()
    for s = 1, MAX_SLOT do if M.peers[s] and M.peers[s].obj then return true end end
    return false
end

function hostPlane(o, unit)
    local u = M.units[unit]
    if not u then return end
    local a = addrOf(o)
    -- (the Alicorn's parked pools: not mirrored. (0.73.83) Only its own unit's planes: its set of their addresses was kept
    -- after its unit was gone, and every later plane the game put at one of those addresses got no co-op id (the 0.73.79
    -- run of 2026-11-04: after the Alicorn round 18 of 41 hunts went after partly bound flights, a joiner tore 86 copies
    -- down as strays and every joiner asked for the whole picture every ~3 minutes to the end of the run))
    if unit == SPC.alicornUnit and SPC.alcnPool and a and SPC.alcnPool.set[a] then return end
    u.n = u.n + 1
    M.nextId = M.nextId % 65535 + 1
    local id = M.nextId
    u.planes[u.n] = { id = id }
    M.byId[id] = { obj = o, unit = unit, ord = u.n, addr = a }          -- (addr: a shot's target by its stream id, "fx")
    if type(SV_CoopTrack) == "function" and a then SV_CoopTrack(id, a) end
    send(true, "bd", unit, u.gen, u.n, id)
    -- split the fighters between you: a pool flight goes after the joiners' planes (allied aircraft here) with
    -- split_share, once it's had its orders
    if u.n == 1 and poolIndex(unit) and anyJoinerPlane() and math.random() < (cfg().split_share or 0) then
        M.hunts[#M.hunts + 1] = { at = os.clock() + 5, name = string.format("RE_SV_Hunt_%02d", poolIndex(unit)), unit = unit }
    end
end

hostGround = function(o, unit)
    local u = M.units[unit]
    if not u then return end
    u.gcount = u.gcount or {}
    local key = groundKey(o, u.gcount)
    M.nextId = M.nextId % 65535 + 1
    local id = M.nextId
    u.ground[key] = { id = id }
    u.gn = (u.gn or 0) + 1                                   -- ((0.73.80) for groundTick's line)
    M.byId[id] = { obj = o, unit = unit, key = key, addr = addrOf(o) }
    send(true, "gd", unit, u.gen, key, id)
    return true
end

-- the roster: who's in which slot, their airframe and version, to every joiner (on a change)
function sendRoster(to)
    for s = 0, MAX_SLOT do
        local r = M.roster[s]
        if r then
            local f = { "pi", s, r.row or "", r.ver or "", r.name or "", r.code or "", r.lo or "", r.paint or "", r.ac or "",
                        r.sid or "" }   -- (sid: their Steam ID, host migration)
            -- ((0.73.80) a plane with no stock code: its class path and stock base after the Steam ID (M.modFields))
            if M.modFields then M.modFields(f, r.code, r.cls, r.base) end
            sendTo(to, true, table.unpack(f))
        end
    end
end

-- how long the split hunt waits out a director's hold at most: the longest it can be (top cover's max_s, synced and
-- tunable), with a dive's lead and your decoy over it
local function holdWaitS()
    local tc = CFG.director and CFG.director.top_cover
    return (tonumber(tc and tc.max_s) or 45) + 120
end
-- ... and a Wolf trap at most: an ace trap's wait for its first contact (P9), the trap's hold_max_s after it, with its
-- orders' wait and your decoy over them
local function wolfWaitS()
    local w, pc = CFG.roles and CFG.roles.wolf, CFG.aces and CFG.aces.personality
    local trap = type(pc) == "table" and type(pc.openers) == "table" and pc.openers.trap
    return (type(trap) == "table" and tonumber(trap.hold_max_s) or 300)
        + (type(w) == "table" and tonumber(w.hold_max_s) or 60) + 120
end

-- (0.73.77, economy C1) Who shot the host's object e down, named in its "dn" so that every game pays the same player
-- for it (a joiner had no way to tell: every kill it saw was paid as its own, mobi118 1,473 of them, 2026-11-02):
-- { slot = s }, the player who did it the most damage (the host's own plane from its DamageHistoryMap, each joiner's
-- from their hits here, hostHit's e.by); else the host's if it fired at it in its last 15 s (KILL.fired); else
-- { side = "allies" | "ships" | "defences" }, the side that did the most; else the host's (nothing read: a kill is
-- yours then, as solo). false for one gone without being shot down (a despawn, a recycle) and for the allies' own.
-- Worked out once, at its death (hostTick), or when the plane watch pays it first (KILL.by).
KILL_SIDE_CODE = { allies = "a", ships = "s", defences = "d" }
function hostKiller(e)
    if e.killer ~= nil then return e.killer end
    if allyUnit(e.unit) or not live(e.obj) or (health(e.obj) or 1) > 0 then e.killer = false; return false end
    local me, pa, peerA, dmg, sides = COOP.slot or 0, myAddr(), {}, {}, {}
    for s, P in pairs(M.peers) do if P.addr then peerA[P.addr] = s end end
    pcall(function()
        e.obj.DamageHistoryMap:ForEach(function(k, v)
            local okK, o = pcall(function() return k:get() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and type(x) == "number" and x > 0 and valid(o) then
                local a = addrOf(o)
                if a and a == pa then dmg[me] = (dmg[me] or 0) + x
                elseif not (a and peerA[a]) and KILL and KILL.side then   -- (a joiner's stand-in's: in e.by)
                    local okS, s = pcall(KILL.side, o, pa)
                    if okS and KILL_SIDE_CODE[s] then sides[s] = (sides[s] or 0) + x end
                end
            end
        end)
    end)
    for s, x in pairs(e.by or {}) do dmg[s] = (dmg[s] or 0) + x end
    local best, slot = 0, nil
    for s, x in pairs(dmg) do if x > best then best, slot = x, s end end
    local t = KILL and KILL.fired and e.addr and KILL.fired[e.addr]
    if not slot and t and D and D.now and D.now - t <= 15 then slot = me end
    local bestS, side = 0, nil
    if not slot then for s, x in pairs(sides) do if x > bestS then bestS, side = x, s end end end
    e.killer = side and { side = side } or { slot = slot or me }
    return e.killer
end
-- (0.73.77, economy C1) The run's kills by the player each "dn" named, on the host: { [slot] = { air = n, ground = n } }
-- (planes; ships, vehicles and parts), counted as the host's enemies go down (hostTick); allies' losses, a level going
-- away and kills of no player (an ally's, a ship's, a defence's) aren't. For the co-op leaderboard's squad (plan H2)
-- and the sync report's host line; a new level (run) starts it again, and a host by migration starts it at its takeover.
function COOP.killTally() return M.tally or {} end
-- ((review of 0.73.80) The host is about to take unit's objects off without a kill (landing craft or troops that got
-- away, recalled or left at the round's end: a destroy with no attacker, health 0): each of its objects still up goes
-- down as nobody's (killer false: "dn" with no player, no tally), not as the player who once hit it. How many.
-- ((review of 0.73.80) Only objects still up: one already shot down this tick (a kill in the game between hostTick and
-- the next probe, which runs the specials first), not yet seen by hostTick, keeps its killer: hostKiller names it.)
function COOP.takenOff(unit)
    if not (COOP.host() and type(unit) == "string") then return 0 end
    local n = 0
    for _, e in pairs(M.byId) do
        if e.unit == unit and e.killer == nil and not e.dead and live(e.obj) and (health(e.obj) or 1) > 0 then
            e.killer, n = false, n + 1
        end
    end
    return n
end
-- ((0.73.83) the 0.73.79 co-op run of 2026-11-04, verified twice: each time the host took VOID WATCHER 1 off, the
-- forwarded RE_SV_AwacsRemove switched the joiners' copy off before the host's "dn" (22-58 s later, at its health's 0)
-- could finish it: its stream held at its last state (Rapt0r's 1,324 held moves) and a ghost copy up 6-14 minutes,
-- until the next purchase. (The host's) Its copies down on every game first, unpaid ("dn|<id>|r"), then the event.
function COOP.removeNow(unit)
    if not (COOP.host() and type(unit) == "string") then return 0 end
    local n, now = 0, os.clock()
    for id, e in pairs(M.byId) do
        if e.unit == unit and not e.dead then
            e.dead, e.deadAt, e.killer = true, now, false
            send(true, "dn", id, "r", "")
            if not e.key and type(SV_CoopTrack) == "function" then SV_CoopTrack(id, 0) end
            local u = M.units[e.unit]
            if u and e.ord and u.planes[e.ord] then u.planes[e.ord].dead = true end
            if u and e.key and u.ground[e.key] then u.ground[e.key].dead = true end
            n = n + 1
        end
    end
    if n > 0 then log(string.format("coop: %s taken off here: its %d copies on the joiners taken down first (unpaid)", unit, n)) end
    return n
end
-- ((0.74.22) the user's co-op run of 2026-11-08: "this space centre hasn't despawned") (the host) unit brought back as
-- it was, never spawned again (the shuttle's pad: hidden after a shuttle round, its units kept up, shown again at the
-- next one: sv_spawn.lua spawnShuttle) once COOP.removeNow took it off the joiners' games: announced to them afresh, as
-- a spawn of it would be ("sp" with a new generation, then a "gd" for each of objs, its objects in their spawn order:
-- each joiner spawns its own and binds them by key). Only while nothing of it is in the host's picture. How many ids.
function COOP.hostBack(unit, objs)
    if not (COOP.open and COOP.host() and type(unit) == "string" and type(objs) == "table") then return 0 end
    local u = M.units[unit]
    if u then
        for _, pl in pairs(u.planes) do if not pl.dead then return 0 end end
        for _, g in pairs(u.ground) do if not g.dead then return 0 end end
    end
    local up = {}
    -- (the objects groundTick gives ids, in its order: the joiners' keys count the same ones)
    for _, o in ipairs(objs) do if live(o) and inSurvival(o) and not isPlane(o) then up[#up + 1] = o end end
    if #up == 0 then return 0 end
    COOP.hostSpawned(unit, nil, nil, nil)
    local n = 0
    for _, o in ipairs(up) do if hostGround(o, unit) then n = n + 1 end end
    log(string.format("coop: %s brought back here: announced to the joiners again (gen %s), %d of its %d objects given ids",
        unit, tostring(M.units[unit] and M.units[unit].gen), n, #up))
    return n
end
-- ((review of 27097b9, finding 3) A flight the host took off with no despawn event a joiner sees (the Spaceport's Tu-160s
-- at a capture: bomber flights, no RE_SV_FlightOff_NN): "wd|<unit>". Each joiner marks its copies down and withdrawn
-- (sv_rounds.lua flightWithdrawn), as hostEvent does for RE_SV_FlightOff_NN, so the host's later "dn" with no player (a
-- shot, the recycle) pays nobody there either; before, a joiner's sweep paid each by the raw rule ("you" for a copy nobody
-- hit there). The host's alone; whether it was sent.
function COOP.withdrawn(unit)
    if not (COOP.host() and type(unit) == "string" and unit ~= "") then return false end
    send(true, "wd", unit)
    return true
end
local function tallyKill(e, kl)
    if not (kl and kl.slot) or (type(levelGoing) == "function" and levelGoing()) then return end
    M.tally = M.tally or {}
    local t = M.tally[kl.slot] or { air = 0, ground = 0 }
    M.tally[kl.slot] = t
    if e.key then t.ground = t.ground + 1 else t.air = t.air + 1 end
    if LB and LB.coopKill then pcall(LB.coopKill, kl.slot, e) end   -- ((0.73.77, plan H2) the squad's, by player: sv_leaderboard.lua)
end

function hostTick()
    local now = os.clock()
    -- deaths at once, health once a second
    local batch, nb = {}, 0
    local wantHp = now >= M.nextHp
    if wantHp then M.nextHp = now + 1 end
    for id, e in pairs(M.byId) do
        if not e.dead then
            local h = valid(e.obj) and health(e.obj) or 0
            if h <= 0 then
                e.dead, e.deadAt = true, now
                -- ((0.73.77, economy C1) "dn|<id>||<killer>": a player's slot, or a / s / d, or nothing (gone))
                local okK, kl = pcall(hostKiller, e)
                if not okK then once("killer", "coop: a kill's player couldn't be worked out: " .. tostring(kl)); kl = nil end
                -- ((code review of 2026-11-07, finding 11) one held unpaid here (COOP.payHold: THE FESTIVAL's missiles
                -- round an impact record) goes down on every game as a removal, nobody's kill)
                if e.unpaid then kl, e.killer = false, false end
                send(true, "dn", id, e.unpaid and "r" or "", kl and (kl.slot and kl.slot or KILL_SIDE_CODE[kl.side]) or "")
                tallyKill(e, kl)
                if not e.key and type(SV_CoopTrack) == "function" then SV_CoopTrack(id, 0) end
                local u = M.units[e.unit]
                if u and e.ord and u.planes[e.ord] then u.planes[e.ord].dead = true end
                if u and e.key and u.ground[e.key] then u.ground[e.key].dead = true end
            -- ((code review of 2026-11-07, finding 6) SAL's boat left out: each game's copy of it moves only with its own
            -- player's hits, and each game charges its own player for a hit it sees (sv_fishing.lua boatTick); the host's
            -- health written there was taken as that joiner's hit, every joiner paying for the host's splash)
            elseif wantHp and h ~= e.sentHp and not (FISH and FISH.isBoat and FISH.isBoat(e.unit)) then
                e.sentHp = h
                nb = nb + 1
                batch[#batch + 1] = id .. ":" .. h
                if nb >= 60 then send(true, "hp", table.concat(batch, ",")); batch, nb = {}, 0 end
            end
        elseif now - e.deadAt > 60 then
            M.byId[id] = nil
        end
    end
    if nb > 0 then send(true, "hp", table.concat(batch, ",")) end
    -- a flight with nothing left alive is forgotten (it's spawned again as a new one); one with nothing linked is
    -- forgotten once the spawner has none of it up (coop.11 sent a joiner who started over long-gone landing craft)
    local checkUp = now >= (M.nextUp or 0)
    if checkUp then M.nextUp = now + 10 end              -- ((0.73.83) every 10 s, was 2: a native ask for each unlinked unit)
    for unit, u in pairs(M.units) do
        local alive, linked = false, u.n > 0
        for _, pl in pairs(u.planes) do if not pl.dead then alive = true end end
        for _, g in pairs(u.ground) do linked = true; if not g.dead then alive = true end end
        if linked and not alive then
            M.units[unit] = nil
        elseif not linked and checkUp and rawUnitAlive and now - (u.at or now) > 10 then
            local n = rawUnitAlive(unit)
            if n == 0 or n == -7 then M.units[unit] = nil end
        end
    end
    -- the specials' lasting state for a joiner that came back (hostSync), once its copies are up
    for i = #(M.replays or {}), 1, -1 do
        local r = M.replays[i]
        if now >= r.at then
            table.remove(M.replays, i)
            local evs = r.events or {}
            if r.fn then                                   -- (as things stand when it goes: the director's holds)
                local okF, l = pcall(r.fn)
                evs = (okF and type(l) == "table") and l or {}
            end
            -- ((0.73.73) with the unit they're for: a joiner fires them only on a copy it spawned again since, not one
            -- it kept through the resync, which had them already)
            for _, name in ipairs(evs) do
                if r.unit then sendTo(r.to, true, "ev", name, r.unit) else sendTo(r.to, true, "ev", name) end
            end
            if #evs > 0 then log(string.format("coop: player %d brought up to date: %s", r.to + 1, table.concat(evs, ", "))) end
        end
    end
    -- the round and the airfield
    if D and now >= M.nextRnd then
        M.nextRnd = now + 1
        local alive = 0
        for _, p in ipairs(planes or {}) do if not p.down then alive = alive + 1 end end
        local secs = (D.state == "wait" and D.at and D.now) and math.max(0, D.at - D.now) or 0
        local lv = ""                                      -- (the intensity director's spike level: the copies fly it, P4)
        if DIR and DIR.level and D.round then
            local okL, l = pcall(DIR.level, D.round)
            if okL and type(l) == "number" then lv = l end
        end
        local gp = ""                                      -- (AB.L..IN's phase, P7: a joiner switches its copy's pods off in 3)
        local sp = D.special
        if sp and sp.kind == "glitch" and sp.state == "hunt" and type(sp.phase) == "number" then gp = sp.phase end
        local okA, al = pcall(function() return ALLY and ALLY.roomCode and ALLY.roomCode() or "" end)   -- (the room's
        if not okA then once("roomcode", "coop: the allies' summary not sent: " .. tostring(al)); al = "" end   -- allies)
        -- ((0.73.77, plan D3) the round's special as this game's music has it, specialFor: a joiner's music follows it)
        local okK, spk = pcall(M.roundSpecial, D.round or 0)
        spk = (okK and type(spk) == "string") and spk or ""
        -- ((0.73.77, the specials' clean-up D4 and the Anomaly's field on joiners) the special in play and its state,
        -- "<kind>:<state>" ("anomaly:hunt", "valka:done"), or "": a joiner's field only while the host's Anomaly hunts
        -- (ANOM.clientTick), its copies' leftovers taken off once the host's is over (sv_rounds.lua SPC.clientClean)
        local ss = (sp and type(sp.kind) == "string" and type(sp.state) == "string") and (sp.kind .. ":" .. sp.state) or ""
        -- ((0.73.78, plan G5) the room's VOID WATCHER 1 purchases this run, counted here (sv_shop.lua shopBuildFor): each
        -- joiner's STORE prices it from them, so the room's price rises x raise a purchase whoever buys it)
        local vb = math.max(0, math.min(999, math.floor(tonumber(RUN and RUN.bought and RUN.bought.VoidWatcher) or 0)))
        -- ((0.73.78) the room's purchases of every other ally and defence too (user, 2026-11-03: their prices room-wide):
        -- "<item>:<n>,...;<kind>:<n>,...", the allies' RUN.bought and the defences' RUN.defences.bought)
        local rb = {}
        for _, nm in ipairs(M.ROOM_ITEMS) do
            local n = math.floor(tonumber(RUN and RUN.bought and RUN.bought[nm]) or 0)
            if n > 0 then rb[#rb + 1] = nm .. ":" .. math.min(999, n) end
        end
        local db = {}
        for kd, n in pairs(RUN and RUN.defences and RUN.defences.bought or {}) do
            n = math.floor(tonumber(n) or 0)
            if type(kd) == "string" and kd:match("^%a+$") and n > 0 then db[#db + 1] = kd .. ":" .. math.min(999, n) end
        end
        table.sort(db)
        -- ((0.74.0) field 15: the run's GONE FISHIN' round, F (0: none), the day-night arc's and THE FESTIVAL's: sv_sky.lua)
        local arcF = math.floor(tonumber(RUN and RUN.arcF) or 0)
        send(false, "rnd", D.round or 0, D.state or "wait", string.format("%.1f", secs), D.wave or 0, D.waves and #D.waves or 0, alive, lv, gp, al,
            spk, ss, string.format("%d", vb), table.concat(rb, ",") .. ";" .. table.concat(db, ","), string.format("%d", arcF))
    end
    -- ((0.73.77, the plan's I7: S12) the Spaceport (sv_spaceport.lua SPORT.coopCode): its NEXT row's numbers for the
    -- joiners' rows, and a retake due or in play, which each joiner keeps for a host migration ("spx"; as it changes,
    -- once a second at most, and every 10 s anyway)
    if D and SPORT and SPORT.coopCode and now >= (M.nextSpx or 0) then
        M.nextSpx = now + 1
        local okS, code = pcall(SPORT.coopCode)
        if okS and type(code) == "string" and (code ~= M.spxSent or (now >= (M.spxAgain or 0) and code ~= "-;-")) then
            if code ~= M.spxSent and code:match(";(.*)$") ~= (M.spxSent or ""):match(";(.*)$") then
                log("coop: the Spaceport's state sent to the joiners: " .. code)       -- (the pending retake changed)
            end
            M.spxSent, M.spxAgain = code, now + 10
            send(true, "spx", code)
        elseif not okS then once("spx", "coop: the Spaceport's state not sent: " .. tostring(code)) end
    end
    if AF and now >= M.nextAf then
        -- ((2026-11-07) players: the airfield "at 250 health with the health bar at halfway": a joiner's bar divided the
        -- host's health by the joiner's OWN maximum (its own setup's AIRFIELD HEALTH, 200% = 500). The host's maximum
        -- goes as field 5, and the joiner's bar is out of that)
        local key = tostring(AF.hp) .. "/" .. tostring(AF.full) .. "/" .. tostring(AF.down) .. "/" .. tostring(AF.max)
        if key ~= M.afKey or now >= M.nextAf + 10 then
            M.afKey, M.nextAf = key, now + 2
            send(true, "af", AF.hp or 0, AF.full or 0, AF.down and 1 or 0, AF.max or 0)
        end
    end
    -- the hunt orders waiting
    for i = #M.hunts, 1, -1 do
        local h = M.hunts[i]
        if now >= h.at then
            table.remove(M.hunts, i)
            local wolf = D and D.up and D.up[h.unit] and WOLF and WOLF.holding(h.unit)
            if wolf and now - (h.wolfAt or now) < wolfWaitS() then
                -- (a Wolf flight holding its trap, CFG.roles.wolf: the hunt's unit-wide order would free it, so it waits
                -- for the trap's release; it was dropped, and a trap is still pending or held at +5 s, so no Wolf
                -- flight ever went after the joiners: code review of 2026-10-29)
                if not h.wolfAt then
                    log("coop: " .. h.unit .. " holds its Wolf trap; it goes after the joiners once that's let go")
                end
                h.at, h.wolfAt = now + 2, h.wolfAt or now
                M.hunts[#M.hunts + 1] = h
            elseif wolf then
                log(string.format("coop: %s held its Wolf trap %.0f s; it doesn't go after the joiners", h.unit, now - h.wolfAt))
            elseif D and D.up and D.up[h.unit] and DIR and DIR.holding and DIR.holding(h.unit) and now - (h.since or now) < holdWaitS() then
                -- (one the squad director holds back, CFG.director: the hunt again once it's let go, which gives it back;
                -- the hunt's unit-wide order would free it while it's still held, here and not on the joiners' copies)
                h.at, h.since = now + 2, h.since or now
                M.hunts[#M.hunts + 1] = h
            elseif D and D.up and D.up[h.unit] and ESC and ESC.holds and ESC.holds(h.unit) then
                -- ((2026-11-06) a flight sent after CHARLENE, THE ESCORT's: kept on her, sv_escort.lua)
                log("coop: " .. h.unit .. " is after CHARLENE (the escort): it doesn't go after the joiners")
            elseif D and D.up and D.up[h.unit] and COOP.realOn() and COOP.anyReal() then
                local ok, s, n = COOP.huntReal(h.unit)
                log("coop: " .. h.unit .. (ok and string.format(" goes after player %d's real plane (%d planes ordered onto it)", s + 1, n)
                    or " found no real plane to go after") .. (h.wolfAt and string.format(", its Wolf trap let go after %.0f s",
                    now - h.wolfAt) or ""))
            elseif D and D.up and D.up[h.unit] and type(SV_Event) == "function" then
                local r = SV_Event(h.name)
                if r == 1 and M.units[h.unit] then M.hunted = M.hunted or {}; M.hunted[h.unit] = M.units[h.unit].gen end
                log("coop: " .. h.unit .. " goes after the joiners (" .. h.name .. " " .. tostring(r) .. ")" ..
                    (h.wolfAt and string.format(", its Wolf trap let go after %.0f s", now - h.wolfAt) or ""))
            end
        end
    end
    -- the flights on a real plane whose player went (down, landed at their airfield, gone): onto another real plane, else
    -- back on you
    if M.huntOn and now >= (M.huntCheckAt or 0) then
        M.huntCheckAt = now + 5
        for unit, h in pairs(M.huntOn) do
            local u, P = M.units[unit], M.peers[h.slot]
            if not (u and u.gen == h.gen and D and D.up and D.up[unit]) then
                M.huntOn[unit] = nil
            elseif not COOP.realTarget(h.slot) then
                M.huntOn[unit] = nil
                local why = (P and P.onAirfield) and "landed at their airfield" or (P and P.down) and "down" or "gone"
                local ok, s, n = COOP.huntReal(unit)
                if not ok then n = COOP.huntHost(unit) end
                log(string.format("coop: %s's target (player %d) is %s: %s", unit, h.slot + 1, why, ok and string.format(
                    "onto player %d's real plane (%d planes)", s + 1, n) or string.format("back on you (%d planes)", n)))
            end
        end
    end
    -- ((2026-11-07) the user: "enemies are attacking my downed aircraft": the host DOWN (sv_down.lua), the round's fighter
    -- flights still on it (their appearance's orders name the host's plane) onto a living player's real plane, every 5 s;
    -- none alive: left as they are (COOP.huntHost never puts them on you while you're down))
    local imDown = DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true
    if imDown and D and D.up and now >= (M.downHuntAt or 0) then
        M.downHuntAt = now + 5
        if COOP.realOn() and COOP.anyReal() then
            local moved, planesN = 0, 0
            for unit in pairs(D.up) do
                if not (M.huntOn and M.huntOn[unit]) and poolIndex(unit) and not (BOMBER_UNIT and BOMBER_UNIT[unit])
                    and not (ESC and ESC.holds and ESC.holds(unit)) then
                    local ok, _, n = COOP.huntReal(unit)
                    if ok then moved, planesN = moved + 1, planesN + (n or 0) end
                end
            end
            if moved > 0 then
                log(string.format("coop: you're down: %d flight%s (%d planes) sent after the other players instead", moved,
                    moved == 1 and "" or "s", planesN))
            end
        elseif not M.downHuntSaid then
            M.downHuntSaid = true
            log("coop: you're down and no other player is flying: the enemies' orders left as they are (never put on you)")
        end
    elseif not imDown then
        M.downHuntSaid = nil
    end
end

-- a joiner asked for the whole picture (it loaded in, or its link came back): every flight with anything alive.
-- (0.73.73) "rs|j" first: the answer to its own "jn", not the host's new run ("rs|n"), so the joiner keeps and checks
-- what it has instead of tearing it all down; its deaths as "dn|<id>|r" (long since: not that joiner's kills); "rz" when
-- the picture's whole, so it knows which of its flights the host no longer has. The testers' logs of 0.73.70: every
-- answer took all of a joiner's copies down ("29 copies taken down (the host's run started over)") and its fresh spawns
-- were refused while the ones it couldn't finish stayed up ("its last flight is still up", 409 times).
function hostSync(to)
    M.cnt.jnGot = M.cnt.jnGot + 1
    crumb("coop: player " .. tostring((to or 0) + 1) .. " asked for the whole picture: sent (rs|j)")
    sendTo(to, true, "rs", "j")
    sendRoster(to)
    local n = 0
    for unit, u in pairs(M.units) do
        n = n + 1
        sendUnit(to, unit, u)
        for ord, pl in pairs(u.planes) do
            sendTo(to, true, "bd", unit, u.gen, ord, pl.id)
            if pl.dead then sendTo(to, true, "dn", pl.id, "r") end
        end
        for key, g in pairs(u.ground) do
            sendTo(to, true, "gd", unit, u.gen, key, g.id)
            if g.dead then sendTo(to, true, "dn", g.id, "r") end
        end
    end
    if M.vmood then sendTo(to, true, "vm", 1) end            -- ((0.73.76) VALKA's mood and her model, if she's up)
    if M.vrev then sendTo(to, true, "vr", M.vrev) end
    sendTo(to, true, "rz", n)
    -- (everything's health again with the next second's: a copy spawned again there has its stock health till then)
    for _, e in pairs(M.byId) do e.sentHp = nil end
    M.nextHp = 0
    -- the Alicorn's fresh copy there: its core open, under water, as here (events of the fight it missed)
    local s = D and D.special
    if s and s.kind == "alicorn" and s.state == "sail" then
        local ev = {}
        if s.coreOpen then ev[#ev + 1] = "RE_SV_AlcnAdvance"; ev[#ev + 1] = "RE_SV_AlcnOpenCore" end
        if s.dived then ev[#ev + 1] = "RE_SV_AlcnDive" end
        if #ev > 0 then
            M.replays = M.replays or {}
            M.replays[#M.replays + 1] = { at = os.clock() + 12, to = to, events = ev, unit = SPC and SPC.alicornUnit or nil }
        end
    end
    -- the game's attack throttle in force here (CFG.late.pressure, sv_rounds.lua roundPressure: forwarded when fired,
    -- so a joiner who links later missed it), B too: a joiner's level kept from an earlier run may still be on its C or
    -- D (review of unit 3). Not while an Anomaly or VALKA is up (TIER.PRESSURE_OWN: their own throttle; the band's
    -- preset follows the boss's end, forwarded), nor with CFG.late.pressure off (this game fires none)
    local sp = D and D.special
    if D and TIER.pressure(D.round) and not (sp and TIER.PRESSURE_OWN[sp.kind] and sp.state ~= "done") then
        sendTo(to, true, "ev", "RE_SV_Pressure" .. (D.pressure or "B"))
    end
    -- the squad director's holds in force (RE_SV_DirHold_NN, forwarded when fired: a joiner who links later missed them,
    -- and its copies of a held top cover or regroup would attack it until the release), once its copies are up, as held
    -- then (DIR.holds read when it goes: one let go meanwhile isn't sent)
    if DIR and DIR.holds then
        M.replays = M.replays or {}
        M.replays[#M.replays + 1] = { at = os.clock() + 12, to = to, fn = DIR.holds }
    end
    M.afKey, M.nextRnd, M.nextAf = nil, 0, 0
    if DOWN and DOWN.syncTo then                    -- (who's down now and the room's revives: sv_down.lua)
        local okD, errD = pcall(DOWN.syncTo, to)
        if not okD then log("coop: down list not sent: " .. tostring(errD)) end
    end
    if DECOY and DECOY.syncTo then                  -- (THE DECOY's round and its locks on: sv_decoy.lua, "dk")
        local okDk, errDk = pcall(DECOY.syncTo, to)
        if not okDk then log("coop: THE DECOY's state not sent: " .. tostring(errDk)) end
    end
    -- ((0.73.77, plan A9) the run's over here already: that player too. Saint Alessia's run of 2026-11-02: the host's
    -- "ro" at 16:54:15, scaraboy13's plane in at 16:54:24, and he fought VALKA alone on a run over for everyone else.
    -- Every player who links, or links back, asks for the picture once its level is up: this is where it ends for them)
    if M.ro then
        sendTo(to, true, "ro", M.ro.round)
        log(string.format("coop: player %d linked after the run-over (round %s, %.0f s ago): sent it again (ro)", to + 1,
            tostring(M.ro.round), os.clock() - M.ro.at))
    end
    log(string.format("coop: sent player %d the run: %d flights", to + 1, n))
end

function hostHit(from, id, dmg)
    local e = M.byId[id]
    if not (e and not e.dead and valid(e.obj) and finite(dmg, math.huge) and dmg > 0) then return end
    dmg = math.min(dmg, HIT_MAX)
    e.by = e.by or {}                                       -- ((0.73.77, economy C1) each player's hits on it: its killer)
    e.by[from] = (e.by[from] or 0) + dmg
    local P = M.peers[from]
    -- (a real plane of theirs here is another player's, role 2, and the game refuses its damage outright: hard rule 53.
    -- From COOP2MP T3 every joiner hit was refused that way, so enemies they shot never died here (the co-op run of
    -- 2026-10-30: "people are attacking ghosts on my side"). Then the hit has no attacker, and their share is kept here
    -- for the kill's credit, M.joinHits)
    local real = P and P.real
    local causer = (not real and P and P.obj and valid(P.obj)) and P.obj or nil
    local h0 = health(e.obj)
    local ok = pcall(function() e.obj:ModifyHealth(-dmg, causer, true) end)
    if not ok then ok = pcall(function() e.obj:ModifyHealth(-dmg, e.obj, true) end) end
    if not ok then once("hitfail", "coop: the joiners' hits can't be dealt (ModifyHealth failed)") end
    local h1 = health(e.obj)
    if causer and h0 and h1 and h1 >= h0 then               -- (refused with their plane named: with none)
        pcall(function() e.obj:ModifyHealth(-dmg, nil, true) end)
        real = true
    end
    if real and e.addr then
        M.joinHits = M.joinHits or {}
        M.joinHits[e.addr] = (M.joinHits[e.addr] or 0) + dmg
        h1 = health(e.obj)
        if h0 and h1 and h1 >= h0 then
            once("hitrefused", string.format("coop: a hit from player %d's real plane wasn't taken (health %d before and after)",
                from + 1, h0))
        end
    end
end
end  -- (sv_coop.lua's do block goes on in sv_coop_joiner.lua)
