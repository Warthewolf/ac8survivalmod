-- AC8 Survival Mode - runtime part sv_coop: Survival COOP (CFG.coop; the native half is dlls\main.dll 0.22.0 coop.c;
-- tools/re/COOP.md). Up to 24 players, one run, host-authoritative after the AC7 co-op mod Double Trigger. Player 1
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
-- ev, tl, dv, rb, rx, ro, rc (host), hi, jn, ht, in, rv (joiner; in unreliable), fx and dw (either: a player's shots,
-- a player down; the host relays them; sv_down.lua has the revives').
-- SV_CoopRecv hands them over as "<sender's slot>|<message>".
COOP = { open = false, role = nil, slot = nil }

do
-- one stand-in plane per player slot, A-X (tools/survival_events.py COOP_PEER_SLOTS; user, 2026-10-26: "allow up to
-- 24 players in a lobby"), each with its name key (NAME_KEYS)
local PEER_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWX"
local MAX_SLOT = #PEER_LETTERS - 1
local PEER_UNITS, NAME_KEYS, SLOT_OF = {}, {}, {}
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
local function cfg() return CFG.coop end
function COOP.host() return COOP.open and COOP.role == "host" end
function COOP.client() return COOP.open and COOP.role == "join" end

local function clean(s) return (tostring(s or ""):gsub("|", "/")) end
-- to: a slot, or nil for every other game (a joiner's go to the host)
local function sendTo(to, reliable, ...)
    if not COOP.open or type(SV_CoopSend) ~= "function" then return false end
    local parts = { ... }
    for i = 1, #parts do parts[i] = clean(parts[i]) end
    return SV_CoopSend(table.concat(parts, "|"), reliable and 1 or 0, to or -1) > 0
end
local function send(reliable, ...) return sendTo(nil, reliable, ...) end
-- ((0.73.77, the plan's I2: S9) a penalty the host's run takes (the Spaceport Retake's escaped rocket: sv_spaceport.lua
-- SPORT.debit) off every joiner's zollars too: "db|<n>|<why>" ("cr" carries pay only; the escape's -5,000 came off the
-- host's money alone while its callout went to everyone). Each game takes what it has of it.
function COOP.debit(n, why)
    n = math.floor(tonumber(n) or 0)
    if not COOP.host() or n <= 0 then return end
    send(true, "db", n, tostring(why or ""):sub(1, 80))
    log(string.format("coop: a penalty of %d (%s) sent to every joiner (%d linked)", n, tostring(why), M.linkedPeers or 0))
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
local function split(s)
    local t = {}
    for f in (s .. "|"):gmatch("([^|]*)|") do t[#t + 1] = f end
    return t
end
local function once(key, msg) if not M.said[key] then M.said[key] = true; log(msg) end end
-- Guards on what another game sends (security review of 2026-10-26: a broken or hostile game must not crash, hang or
-- take over this one): text cut to a length, numbers finite and in range, slots and NPC rows ones this game has.
local function short(v, n) return (tostring(v or ""):sub(1, n)) end
local function finite(v, lim) return type(v) == "number" and v == v and v > -lim and v < lim end
local HIT_MAX, CREDITS_MAX = 100000, 1000000                -- (one hit's damage; one round bonus's zollars)
local TL_PER_S = 4                                          -- (the host's tells a joiner plays in a second, at most)
local AIRFRAME_WAIT_S = 5                                   -- (s a stand-in waits for its player's airframe: peerTick)
local HELLO_WAIT_S = 30                                     -- (... and for any hello at all from them: peerTick)
local function slotOk(s) return type(s) == "number" and s == math.floor(s) and s >= 0 and s <= MAX_SLOT end
local knownRows = {}
local function knownRow(row)                                -- a row of Survival's NPC table here (DT_SV_NpcMission)
    if type(row) ~= "string" or #row == 0 or #row > 64 or not row:match("^[%w_]+$") then return false end
    if knownRows[row] then return true end
    local dt = loadObject("/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission")
    if not dt then return true end                          -- (it can't be checked: as before)
    local ok, r = dtCall(dt, "FindRow", row)
    if ok and r ~= nil then knownRows[row] = true; return true end
    return false
end
local function standInRow(row)                              -- another player's airframe: one of CFG.coop.airframes
    local c = cfg()
    if type(row) == "string" and row ~= "" then
        if row == c.default then return row end
        for _, r in pairs(c.airframes) do if r == row then return row end end
    end
    return c.default
end
local function callout(text, sub)
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
local function health(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return ok and type(h) == "number" and h or nil
end
-- (0.73.73) o's address while it's a live object (sv_core's liveAddr: GUObjectArray, outers too), else nil: for objects
-- kept between ticks (the copies, the units' objects)
local function live(o)
    if type(liveAddr) == "function" then return liveAddr(o) end
    return valid(o) and addrOf(o) or nil
end
local function myAddr()                                  -- (0.73.77) your plane's address here, or nil
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    return valid(pawn) and addrOf(pawn) or nil
end
local function playerName(slot)
    local r = M.roster[slot]
    return (r and r.name and r.name ~= "") and r.name or ("PLAYER " .. (slot + 1))
end
local function playerCount()
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
local DV_PER_S, DV_MAX_S, DV_LATE_S = 8, 3.0, 1.0
local function dvName(ev)
    return type(ev) == "string" and #ev <= 64 and (ev:match("^RE_SV_Salvo_%d%d%u$") or ev:match("^RE_SV_Dir%a+_%d%d$")
        or ev:match("^RE_SV_Wolf%a+_%d%d%u$")) ~= nil
end
-- (a joiner) the host's flight `unit` is up here as the event wants: its plane <L> (one per letter), else any copy
local function dvCopy(ev, unit)
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
local IN_FRESH_S, IN_MIN_GAP_S, IN_MSL_MAX = 3, 0.25, 20
local function inNum(v, hi)
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
local function maxPlayers()                          -- (a joiner: the host's room, from its settings)
    if COOP.client() and M.hostMax then return M.hostMax end
    return math.max(2, math.min(MAX_SLOT + 1, math.floor(tonumber(cfg().max_players) or MAX_SLOT + 1)))
end

---------------------------------------------------------------------------------------------------- the natives, wrapped
-- (registered by dlls/main.dll before this script ran; every part calls them by their global names)
-- (the crash breadcrumbs, sv_core.lua's crumb: a part loaded without it, as the tests load this one, gets none)
local crumb = crumb or function() end
local rawSpawn, rawSetAircraft, rawSetLevel, rawUnitAlive = SV_Spawn, SV_SetAircraft, SV_SetLevel, SV_UnitAlive
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
}                              -- (holds and frees, RE_SV_WolfHold / WolfFree and RE_SV_DirHold / DirFree, are forwarded:
                               -- a joiner's copies hold too; so is a Ladon's rage, RE_SV_LadonRage<Key>, P7: harmless,
                               -- the copies are moved by the stream. AB.L..IN's LastTGT, RE_SV_GlitchTurn, is the host's
                               -- by mirroredEvent's RE_SV_Glitch rule)
local function mirroredEvent(name)
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
                          "^RE_SV_GlitchBlink", "^RE_SV_GlitchTurn", "^RE_SV_GlitchGun", "^RE_SV_ValkaTp_", "^RE_SV_AnomalyPackSpring" }
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
local rawEvent = SV_Event
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
local groundNew = {}
-- the allies' units (MOONCHILD's / the WINGMEN's flights, the ships) and the airfield's defences (AA guns, SAM sites,
-- CIWS): the host's, mirrored like its enemies; on a joiner's game their copies fight the enemies' copies there, so
-- neither what they deal nor what they take is sent to the host (it's the host's own allies' fight, dealt there)
-- ((0.73.80) and the shuttle's pad, its dummies and its guns (CFG.specials.shuttle dummies / pad): ids of their own since
-- 0.73.80 (the SV_Spawn wrapper above), the enemies' copies' bombs on them here aren't a joiner's hits, and one down on
-- the host is nobody's kill (hostKiller))
local allySet
local function allyUnit(u)
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
local function groundKey(o, counts)
    local cls = nameOf(o):match("%.([%w_]+)_%d+$") or "obj"
    counts[cls] = (counts[cls] or 0) + 1
    return short(cls, 80) .. "#" .. counts[cls]
end
local hostGround, clientGround                               -- (below: the host's and the joiner's)
local function groundTick()
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

local function hostPlane(o, unit)
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
local function sendRoster(to)
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
local KILL_SIDE_CODE = { allies = "a", ships = "s", defences = "d" }
local function hostKiller(e)
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

local function hostTick()
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
                send(true, "dn", id, "", kl and (kl.slot and kl.slot or KILL_SIDE_CODE[kl.side]) or "")
                tallyKill(e, kl)
                if not e.key and type(SV_CoopTrack) == "function" then SV_CoopTrack(id, 0) end
                local u = M.units[e.unit]
                if u and e.ord and u.planes[e.ord] then u.planes[e.ord].dead = true end
                if u and e.key and u.ground[e.key] then u.ground[e.key].dead = true end
            elseif wantHp and h ~= e.sentHp then
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
        send(false, "rnd", D.round or 0, D.state or "wait", string.format("%.1f", secs), D.wave or 0, D.waves and #D.waves or 0, alive, lv, gp, al,
            spk, ss, string.format("%d", vb), table.concat(rb, ",") .. ";" .. table.concat(db, ","))
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
        local key = tostring(AF.hp) .. "/" .. tostring(AF.full) .. "/" .. tostring(AF.down)
        if key ~= M.afKey or now >= M.nextAf + 10 then
            M.afKey, M.nextAf = key, now + 2
            send(true, "af", AF.hp or 0, AF.full or 0, AF.down and 1 or 0)
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
end

-- a joiner asked for the whole picture (it loaded in, or its link came back): every flight with anything alive.
-- (0.73.73) "rs|j" first: the answer to its own "jn", not the host's new run ("rs|n"), so the joiner keeps and checks
-- what it has instead of tearing it all down; its deaths as "dn|<id>|r" (long since: not that joiner's kills); "rz" when
-- the picture's whole, so it knows which of its flights the host no longer has. The testers' logs of 0.73.70: every
-- answer took all of a joiner's copies down ("29 copies taken down (the host's run started over)") and its fresh spawns
-- were refused while the ones it couldn't finish stayed up ("its last flight is still up", 409 times).
local function hostSync(to)
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

local function hostHit(from, id, dmg)
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

---------------------------------------------------------------------------------------------------- joiner
local function hostPuppet()
    local P = M.peers[0]
    return P and P.obj and valid(P.obj) and P.obj or nil
end

-- (with the host's plane as the cause when it's an AI stand-in; with none when it's their real plane, role 2, whose damage
-- the game refuses: from COOP2MP T3 no copy here could be finished, so the host's kills stayed up here, flying on by
-- their own AI, and their flights never spawned again ("its last flight is still up"): the co-op run of 2026-10-30,
-- "people are attacking ghosts", the same copy "taken down" every 5 s. Checked after: still up, GameplayStatics'
-- ApplyDamage)
-- torn: a copy this game takes down itself (the host's run started over, a stray, its flight's last copies before a
-- new spawn), not the host's kill: its address kept TORN_S so the plane watch pays nothing for it (COOP.tornDown). The
-- co-op run of 2026-10-31: three joiners' teardowns (the host's answer to their own "jn") paid 5-14 kills "by you"
-- each, 750-2,230 zollars, in the seconds after.
local TORN_S = 30
-- (0.73.77, plan A1) A copy's floor: it waits at 1 HP for the host's kill ("dn"). The MinHealth field is written (every
-- hit is clamped at it: KILLS_HEALTH_DEATH.md 2), as the revive floor and the real planes do; SetMinHealth keeps whole
-- points only, so 0.73.76's SetMinHealth(0.1) set 0 and a joiner's copies had no floor at all. The logs of 2026-11-02:
-- dukka's and mobi118's copies went down to the ships' copies there up to 700 s before the host's kill (60 and 116
-- flights), the host's "hp" then wrote health back onto the wrecks (invisible enemies with target boxes), and their
-- flights' next spawns were refused. FLOOR_IN: the floor as HealthInternal (health x 10).
local FLOOR_IN = 10
local HP_HOLD_S = 1.5                                       -- ((0.73.79) the "hp" handler's hold after a hit is sent)
local function floorOn(o)
    local hp = FLOOR_IN / 10
    local ok = pcall(function() o.MinHealth = hp end)
    if not ok then ok = pcall(function() o:SetMinHealth(hp) end) end
    if not M.floorSaid then                              -- (once a level: what the field reads back)
        M.floorSaid = true
        local okR, v = pcall(function() return o.MinHealth end)
        log(string.format("coop: copies held at %.1f HP until the host's kill (%s; MinHealth reads back %s)", hp,
            ok and "the field written" or "NOT written", okR and tostring(v) or "nothing"))
    end
    return ok
end
-- (0.73.77, plan A6) copy c's wait at the floor is over (the host's kill, or its health from the host): the minute's
-- longest kept for the sync report
local function floorDone(c)
    if not (c and c.floorAt) then return end
    local w = os.clock() - c.floorAt
    c.floorAt = nil
    if w > (M.cnt.floorMax or 0) then M.cnt.floorMax = w end
end
-- force (0.73.73): an invincible copy too (a taxiing ally, the shuttle, the pad's guns and dummies): the host's is gone or
-- spawning afresh. Without it the testers' joiners couldn't finish them ("a copy here couldn't be finished (health 9300
-- after)"), they stayed up unbound, flying their own AI ("VOID WATCHER became a space shuttle", MOONCHILD "submersible"),
-- and the host's next spawn of the unit was refused.
-- by ((0.73.80, the 31-round test's finding coop6): your plane, when the host's "dn" names this game's player): the kill
-- with your plane as its cause, so the game shows it as yours (its DESTROYED, not only the hit markers: the floor clips
-- every lethal hit of yours here, and the kill came with the host's plane or none as its cause). Refused with it: none.
-- What it answers: "yours", "yours refused" (then none), "host" (the host's AI stand-in), "none"; nil for a copy gone.
-- The pay is untouched: a joiner pays the player the host named (KILL.by, M.killerOf), never the game's cause.
local function killCopy(id, o, torn, force, by)
    if type(SV_CoopBind) == "function" and type(id) == "number" and id > 0 then SV_CoopBind(id, 0) end
    local a = live(o)
    if not a then return end
    M.downAt[a] = os.clock()                             -- (0.73.73: strayTick leaves it alone)
    if torn then
        M.torn = M.torn or {}; M.torn[a] = os.clock()
        M.tornLast = os.clock()                          -- (the pay audit, sv_audit.lua: COOP.tornRecently)
        M.cnt.torn = M.cnt.torn + 1
    end
    crumb(string.format("copy %s taken down (id %s%s%s)", nameOf(o), tostring(id), torn and ", torn: not a kill" or "",
        force and ", forced" or ""))
    if force then
        pcall(function() o:SetIsInvincible(false) end)
        pcall(function() o.bIsInvincible = false end)
    end
    pcall(function() o.MinHealth = 0.0 end)              -- ((0.73.77) the floor off first: floorOn wrote the field)
    pcall(function() o:SetMinHealth(0.0) end)
    local h = health(o) or 0
    local P0 = M.peers[0]
    local causer, how = nil, "none"
    if by ~= nil and valid(by) then causer, how = by, "yours"
    else
        causer = not (P0 and P0.real) and hostPuppet() or nil
        if causer then how = "host" end
    end
    local ok = pcall(function() o:ModifyHealth(-(h / 10 + 100), causer, true) end)
    if not ok then pcall(function() o.HealthInternal = 0 end) end
    if (health(o) or 0) > 0 and causer then                  -- (refused with the host's plane named: with none)
        pcall(function() o:ModifyHealth(-(h / 10 + 100), nil, true) end)
        how = how .. " refused"
    end
    if (health(o) or 0) > 0 then
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if valid(gs) then pcall(function() gs:ApplyDamage(o, 100000000.0, nil, nil, nil) end) end
        if (health(o) or 0) > 0 then
            once("killfail", "coop: a copy here couldn't be finished (health " .. tostring(health(o)) .. " after)")
        end
    end
    return how
end
-- (0.73.80, finding coop6) The host's "dn" for copy c (id): taken down here, with your plane as its cause when field 4
-- names this game's player (its slot), else as before (the host's AI stand-in, or none). The 31-round test's joiners saw
-- only hit markers, never the game's DESTROYED: their lethal hits stop at the floor (floorOn) and the kill came from here
-- with the host's plane or none as its cause. Each way it went logged once; [coop] kill_callout (off by default: whether
-- the game's own DESTROYED shows this way isn't known yet) adds Survival's own callout for each kill of yours.
do
local KILL_HOW = { yours = "your plane as its cause (the game's DESTROYED should show)",
                   ["yours refused"] = "your plane as its cause REFUSED by the game: with none",
                   host = "the host's plane (an AI stand-in here) as its cause", ["host refused"] = "the host's stand-in refused: with none",
                   none = "no cause (the host flies a real plane here)" }
function M.dnKill(id, c, f)
    local torn = f[3] == "r"
    local mine = not torn and COOP.slot ~= nil and f[4] ~= nil and f[4] ~= "" and tonumber(f[4]) == COOP.slot
    local by = nil
    if mine then
        local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
        if valid(pawn) then by = pawn end
    end
    local how = killCopy(id, c.obj, torn, true, by)
    if how and not torn then
        once("dnhow" .. how .. (mine and "m" or ""), string.format("coop: the host's kill of copy %d (%s): taken down here with %s",
            id, mine and "yours" or (f[4] and f[4] ~= "" and ("named " .. short(f[4], 2)) or "no player named"),
            (mine and not by) and "no plane of yours here: " .. (KILL_HOW[how] or how) or (KILL_HOW[how] or how)))
    end
    if mine and how and cfg().kill_callout == true and type(hudCallout) == "function" then
        M.noMirror = true; pcall(hudCallout, "DESTROYED", nil); M.noMirror = false   -- (whatever [coop] callouts says)
    end
    return how
end
end

-- (0.73.73) a copy whose host id is already down: taken down as not a kill (torn) and off its flight's planes here. The
-- testers' logs of 0.73.70: each resync spawned the host's flights again here, and the copies of planes the host had
-- shot down long before went down on arrival "by you": 109 kills, ~13,470 zollars (A04 13:39:40, "up 1 s ...; by you")
local function deadOnArrival(id, o, unit, ord, key)
    killCopy(id, o, true, true)
    M.copies[id] = nil
    local cu, a = M.cunits[unit], addrOf(o)
    if cu and ord and cu.planes[ord] and addrOf(cu.planes[ord]) == a then cu.planes[ord] = nil end
    if cu and key and cu.gobjs and cu.gobjs[key] and addrOf(cu.gobjs[key]) == a then cu.gobjs[key] = nil end
end
local function bindCopy(id, o, unit, ord)
    if M.dead[id] then deadOnArrival(id, o, unit, ord, nil); return end
    local a = addrOf(o)
    local r = (type(SV_CoopBind) == "function" and a) and SV_CoopBind(id, a) or -9
    if r ~= 1 then once("bind" .. tostring(r), "coop: a copy couldn't be bound (" .. tostring(r) .. "): it flies on its own") end
    floorOn(o)                                              -- (it goes down when the host's does: (0.73.77) at 1 HP)
    local was = M.copies[id]                                -- ((0.73.77) bound again: your damage so far, clientTick)
    local mine = was and was.addr == a and was.mine or nil
    local h = health(o) or 0
    M.copies[id] = { obj = o, exp = h, addr = a, ally = allyUnit(unit),   -- (ally: the host's allies' copy)
                     unit = unit, ord = ord, mine = mine, hp = h }  -- (0.73.73: its place in its flight here, "dn")
end

-- (0.73.73) every object of each of the host's units spawned here, by address (its name too: an address freed and used
-- again is another object), kept past a teardown until it's down or gone: a refused spawn of the host's takes down
-- whatever of that unit is still up here, whatever its kind (doSpawn). 0.73.70's take-down walked the enemy planes only,
-- and found none in 187 of 187 tries: the shuttle's pad (PadDummies, AA_Unit_01_Ground0), the defences, the allies'
-- flights and the shuttle were never in it.
local function noteObj(unit, o)
    local a = type(unit) == "string" and addrOf(o)
    if not a then return end
    local reg = M.objsOf[unit]
    if not reg then reg = {}; M.objsOf[unit] = reg end
    reg[a] = { obj = o, name = nameOf(o) }
end
-- ((0.73.77, plan A3) a wreck, at 0 health and still in the world, is kept 120 s: the game may still count it in its
-- unit (AliveChildAIGameObjects), which refuses the unit's next spawn, and doSpawn's take-down finds it here)
local function pruneObjs()                               -- (strayTick, every 5 s: what's down or gone dropped)
    local now = os.clock()
    for unit, reg in pairs(M.objsOf) do
        for a, e in pairs(reg) do
            -- (0.73.73 review) unreadable health counts as up, as takeUnitDown has it: dropping such an object here hid
            -- it from a later refused spawn's take-down, the ghost this registry is for
            if not live(e.obj) then reg[a] = nil
            elseif (health(e.obj) or 1) <= 0 then
                e.zeroAt = e.zeroAt or now
                if now - e.zeroAt >= 120 then reg[a] = nil end
            end
        end
        if next(reg) == nil then M.objsOf[unit] = nil end
    end
end
-- whatever of `unit` is still up here (its flight here `cu`, if any, and every object of it spawned here), taken down:
-- torn (not a kill), forced (invincible too). How many. wrecks ((0.73.77, plan A3), a spawn the game refused): its
-- objects at 0 health still in the world too, and its planes the plane watch saw go down (sv_core's `planes`) that are
-- still there, taken down again (ModifyHealth runs the game's own death check on them); how many of those, second.
local function takeUnitDown(unit, cu, wrecks)
    local n, w, seen, idOf = 0, 0, {}, {}
    for id, c in pairs(M.copies) do if c.addr then idOf[c.addr] = id end end
    local function one(o, name)
        local a = live(o)
        if not a or seen[a] or (name and nameOf(o) ~= name) then return end
        seen[a] = true
        local id = idOf[a]
        if (health(o) or 1) > 0 then killCopy(id or 0, o, true, true); n = n + 1
        elseif wrecks then killCopy(id or 0, o, true, true); w = w + 1 end
        if id then M.copies[id] = nil end
    end
    if cu then
        for _, o in pairs(cu.planes or {}) do one(o) end
        for _, o in pairs(cu.gobjs or {}) do one(o) end
    end
    local reg = M.objsOf[unit]
    for a, e in pairs(reg or {}) do
        one(e.obj, e.name)                               -- (still up after it: kept, for the next try)
        if not live(e.obj) or nameOf(e.obj) ~= e.name or (not wrecks and (health(e.obj) or 0) <= 0) then reg[a] = nil end
    end
    if wrecks then
        for _, p in ipairs(planes or {}) do if p.unit == unit and p.obj then one(p.obj) end end
    end
    if ALLY and ALLY.forgetActors then pcall(ALLY.forgetActors) end
    return n, w
end

-- (a joiner) copy o's health scaled here (sv_ai.lua enemyLate: CFG.late, a Skirmisher's x0.75, as the host scales its
-- own): what it's expected to have moves with it, so clientTick sends the host only the hits since (code review of
-- 2026-10-29: a joiner's x0.75 went to the host as that player's hit, x0.5 there). Whether o is a bound copy.
function COOP.copyScaled(o, h0, h1)
    if not (COOP.client() and type(h0) == "number" and type(h1) == "number") then return false end
    local a = addrOf(o)
    if not a then return false end
    for _, c in pairs(M.copies) do
        if c.addr == a then c.exp = c.exp + (h1 - h0); return true end
    end
    return false
end

local function clientPlane(o, unit)
    -- (the Alicorn's 131 parked pools: the host gives them no ids, hostPlane, so neither does this game's count. Counted
    -- here, they were "strays" 15 s on, their copies couldn't be taken down (put away invincible), the "jn" resync took
    -- the Alicorn's tanks and core down here and its fresh copy was refused, "its last flight is still up": the co-op
    -- run of 2026-10-31, two joiners couldn't target the Alicorn at all)
    local a = addrOf(o)
    if SPC and unit == SPC.alicornUnit and SPC.alcnPool and a and SPC.alcnPool.set[a] then return end   -- ((0.73.83) its own planes only: hostPlane)
    noteObj(unit, o)                                     -- (0.73.73: tracked here or not)
    local cu = M.cunits[unit]
    if not cu then return end
    cu.n = cu.n + 1
    cu.planes[cu.n] = o
    local id = cu.binds[cu.n]
    if id then bindCopy(id, o, unit, cu.n) end
end

-- a ship's, vehicle's or part's copy (groundTick): not moved, held up until the host's goes down, its hits sent
local function bindGround(id, o, unit, key)
    local cu = M.cunits[unit]                                -- ((0.73.80) for strayTick's "N of M bound" line: linked to
    if cu and key then cu.gb = cu.gb or {}; cu.gb[key] = true end   -- the host's id, down on arrival or not)
    if M.dead[id] then deadOnArrival(id, o, unit, nil, key); return end
    floorOn(o)                                              -- ((0.73.77) at 1 HP: the field, not SetMinHealth(0.1) = 0)
    local a, h = addrOf(o), health(o) or 0
    local was = M.copies[id]
    M.copies[id] = { obj = o, exp = h, addr = a, ally = allyUnit(unit),  -- (addr: a shot's target, "fx")
                     unit = unit, key = key, mine = was and was.addr == a and was.mine or nil, hp = h }
end
clientGround = function(o, unit)
    noteObj(unit, o)                                     -- (0.73.73: tracked here or not)
    local cu = M.cunits[unit]
    if not cu then return end
    cu.gcount, cu.gobjs = cu.gcount or {}, cu.gobjs or {}
    local key = groundKey(o, cu.gcount)
    cu.gobjs[key] = o
    local id = cu.gbinds and cu.gbinds[key]
    if id then bindGround(id, o, unit, key) end
end

-- (sv_main.lua planeSweep) plane p, just down here, is a copy this game took down itself (killCopy's torn): not a kill
function COOP.tornDown(p)
    local a = p and (p.addr or (valid(p.obj) and addrOf(p.obj)))
    local t = a and M.torn and M.torn[a] or nil   -- (0.73.73: a plane with no address gave false, and os.clock() - false errored)
    if M.torn and os.clock() >= (M.tornPruneAt or 0) then
        M.tornPruneAt = os.clock() + TORN_S
        for k, at in pairs(M.torn) do if os.clock() - at > TORN_S then M.torn[k] = nil end end
    end
    return t ~= nil and os.clock() - t <= TORN_S
end

-- (the planes forced, invincible or not, 0.73.73: one left up flies on unbound by its own AI, "VOID WATCHER became a
-- space shuttle"; ships, vehicles and parts as before: the stream never moves them anyway)
local function killAllCopies(why)
    local n, loose, seen = 0, 0, {}
    crumb("copies: all taken down (" .. tostring(why) .. ")")
    M.tornWhy = tostring(why)
    M.cnt.teardowns = M.cnt.teardowns + 1
    if ALLY and ALLY.forgetActors then pcall(ALLY.forgetActors) end   -- (the defences' cached actors: freed soon)
    for id, c in pairs(M.copies) do
        killCopy(id, c.obj, true, c.key == nil); n = n + 1
        local a = c.addr or live(c.obj)
        if a then seen[a] = true end
    end
    -- (and every copy spawned here that never got its id from the host: the user's co-op run of 2026-10-30, both links
    -- lost seconds after the round's flights were sent; their binds never came, the link-back resync took down the bound
    -- copies only and forgot the rest, which flew on by their own AI into the next rounds: "friends are reporting enemies
    -- even though i'm into the next round")
    for _, cu in pairs(M.cunits or {}) do
        for _, o in pairs(cu.planes or {}) do
            local a = live(o)
            if a and not seen[a] then seen[a] = true; killCopy(0, o, true, true); loose = loose + 1 end
        end
        for _, o in pairs(cu.gobjs or {}) do
            local a = live(o)
            if a and not seen[a] then seen[a] = true; killCopy(0, o, true); loose = loose + 1 end
        end
    end
    M.copies, M.cunits, M.spawnQ, M.dead, M.holdQ, M.rep = {}, {}, {}, {}, nil, nil
    if n + loose > 0 then
        log(string.format("coop: %d copies taken down (%s)%s", n + loose, why,
            loose > 0 and string.format(", %d of them never bound to the host's", loose) or ""))
    end
end

-- ((0.73.77) plan F1b) The level is being torn down (sv_core.lua levelGate: the runtime's teardown gate, SV_LevelGone): every
-- game object co-op keeps is forgotten, none of them touched (no killCopy, no hide, no health: they go with the level, and a
-- Lua read of a freed one is the quit crash, UE4SS's property lookup). The next level's start (D ~= M.lastD in COOP.tick)
-- builds the lists again; a player's real plane is spawned again there, as after any level.
function COOP.levelDrop(why)
    local n = 0
    for _ in pairs(M.copies or {}) do n = n + 1 end
    M.copies, M.cunits, M.spawnQ, M.holdQ, M.rep, M.pendBind = {}, {}, {}, nil, nil, nil
    M.objsOf = {}
    M.mslAt, M.mslEnd, M.gunAtT, M.shotTgt = {}, {}, {}, {}   -- ((0.73.79) your shots by the copy they went for)
    local p = 0
    for _, P in pairs(M.peers or {}) do
        if type(P) == "table" and P.obj ~= nil then P.obj, P.addr = nil, nil; p = p + 1 end
    end
    -- ((0.73.83, its review) the set-aside planes and the radar's records go with their level: kept, a freed plane's
    -- address taken by a new object would have asideTick deactivate and move that one. A restart in the same level never
    -- closes the gate, so those planes stay kept then)
    local a = #(M.aside or {})
    for _, e in ipairs(M.aside or {}) do if e.unit and M.asideUnit then M.asideUnit[e.unit] = nil end end
    M.aside, M.parkAt, M.radarSt, M.asideAt = {}, {}, {}, nil
    log(string.format("coop: the level is going (%s): %d copies, %d players' planes and %d set aside forgotten here, none touched",
        tostring(why), n, p, a))
end

-- (0.73.73) The host's answer to this game's own "jn" ("rs|j" ... "rz", hostSync) is a repair, not a teardown. What's here
-- is kept and checked against the host's picture: a flight up here of the host's generation stays as it is (the
-- picture's ids bind its copies again); one of an older generation is taken down for the host's fresh spawn (doSpawn);
-- one the host no longer has at all is taken down at the picture's end; one missing a plane the host still has up is
-- spawned again (its planes are moved by the stream; a ship or part missing alone isn't: a fresh one would start its
-- path over). Nothing is paid for, nobody DOWN comes back, the round's records go on. The testers' logs of 0.73.70: every
-- answer tore all of a joiner's copies down (2,689 copies, 115 times), "all explode and none come back" for 7 minutes
-- (A04 13:15:57), a Ladon gone here while the host's flew on (A02 11:13:58), the round cut short 58 times.
local REP_WAIT_S, JUDGE_AFTER_S = 10, 3
local function onResync()
    M.rep = { at = os.clock(), units = {}, ids = {}, rebound = 0 }
    M.spawnQ, M.pendBind = {}, nil                       -- (the picture sends every flight the host has up again)
    M.cnt.repairs = M.cnt.repairs + 1
    crumb("coop: the host's whole picture is coming (rs|j): the copies here kept")
    log("coop: the host's whole picture is coming (rs|j, its answer to this game's jn): the copies here are kept and checked against it")
end
-- (while the picture comes) the host's id `id` for plane `ord` (or part `key`) of its flight `unit`, generation gen
local function repNote(unit, gen, id, ord, key)
    local rp = M.rep
    local pu = rp and not rp.done and rp.units[unit]
    if not (pu and pu.gen == gen) then return end
    if ord then pu.alive[ord] = id else pu.galive[key] = id end
    rp.ids[id] = { unit = unit, ord = ord, key = key }
end
-- the host's id for a plane (field "binds", by its order) or part ("gbinds", by its key) of its flight `unit`, generation
-- gen, whose spawn here is still to come: kept until doSpawn spawns that generation (one generation a unit)
local function pendKeep(unit, gen, field, k, id)
    M.pendBind = M.pendBind or {}
    local pb = M.pendBind[unit]
    if not pb or pb.gen ~= gen then pb = { gen = gen, binds = {}, gbinds = {} }; M.pendBind[unit] = pb end
    pb[field][k] = id
end
local function upHere(o) return o ~= nil and live(o) ~= nil and (health(o) or 1) > 0 end
local function repairDone(why)
    local rp = M.rep
    if not rp or rp.done then return end
    rp.done = os.clock()
    local whole = why == "rz"
    local kept, fresh, redo, gone, gaps, nPic = 0, 0, {}, {}, {}, 0
    for unit, pu in pairs(rp.units) do
        nPic = nPic + 1
        local cu = M.cunits[unit]
        if not (cu and cu.gen == pu.gen and cu.upAt) then fresh = fresh + 1 end
    end
    for unit, cu in pairs(M.cunits) do
        local pu = rp.units[unit]
        if not pu then
            if whole then                                -- (the host has none of it up: down here too)
                gone[#gone + 1] = string.format("%s (%d)", unit, takeUnitDown(unit, cu))
                M.cunits[unit] = nil
            end
        elseif pu.gen == cu.gen and cu.upAt then
            local miss, gmiss = 0, 0
            if rp.done - cu.upAt >= JUDGE_AFTER_S then   -- (a flight just up here: its copies may not all be seen yet)
                for ord in pairs(pu.alive) do if not upHere(cu.planes[ord]) then miss = miss + 1 end end
                for key in pairs(pu.galive) do if not upHere(cu.gobjs and cu.gobjs[key]) then gmiss = gmiss + 1 end end
            end
            if miss > 0 then
                cu.respawn = true
                redo[#redo + 1] = string.format("%s (%d of its planes)", unit, miss)
            else
                kept = kept + 1
                if gmiss > 0 then gaps[#gaps + 1] = string.format("%s (%d)", unit, gmiss) end
            end
        end
    end
    local function list(t) return #t > 0 and (": " .. table.concat(t, ", ", 1, math.min(#t, 6)) .. (#t > 6 and ", ..." or "")) or "" end
    log(string.format("coop: the host's picture (%d flights%s): %d kept here as they were (%d copies bound again), %d spawned "
        .. "again (a plane the host has up wasn't here%s), %d new or newer here, %d taken down (the host has none of them up%s)%s",
        nPic, whole and "" or ("; " .. tostring(why) .. ": the flights it didn't name kept"), kept, rp.rebound, #redo, list(redo),
        fresh, #gone, list(gone), #gaps > 0 and string.format("; %d kept missing ships or parts the host has up (not spawned "
        .. "again: they'd start their paths over)%s", #gaps, list(gaps)) or ""))
end
-- the host's replay of `unit`'s state for a fresh copy (hostSync: the Alicorn's open core and dive, "ev|<event>|<unit>"):
-- not fired on a copy here that was kept through the resync, which had it already (its AdvancePhase again would move it
-- on a phase). Whether it's skipped.
local function keptThrough(unit, name)
    local cu, rp = unit and M.cunits[unit], M.rep
    if not (cu and rp and cu.at and cu.at < rp.at) then return false end
    log(string.format("coop: the host's %s for %s not fired here: its copy here was kept through the resync (it had it)",
        tostring(name), tostring(unit)))
    return true
end

local function unitUp(cu) return cu ~= nil and ((cu.n or 0) > 0 or next(cu.gobjs or {}) ~= nil) end
local function doSpawn(q)
    local unit = q.unit
    local rp = M.rep
    if q.rep and rp and not rp.done then                 -- (0.73.73) a repair's: once the host's whole picture is in
        if os.clock() - rp.at < REP_WAIT_S then q.at = os.clock() + 0.5; return false end
        repairDone(string.format("no end of the host's picture in %d s", REP_WAIT_S))
    end
    local had = M.cunits[unit]
    if had and had.gen == q.gen and not had.respawn and (unitUp(had) or os.clock() - (had.at or 0) < JUDGE_AFTER_S) then
        return true                                      -- (that flight is up here already)
    end
    local alive = rawUnitAlive and rawUnitAlive(unit) or 0
    if type(alive) == "number" and alive > 0 then        -- the copy of its last flight still up: down first
        if not q.downDone then
            -- (0.73.73) whatever of it is up here, whatever its kind, tracked or not (takeUnitDown). 0.73.70's take-down
            -- walked the enemy planes only ("0 of its planes taken down", 187 of 187), and a "bd" / "gd" for the queued
            -- spawn had put an empty flight of the same generation in M.cunits, so neither take-down ran at all: 409
            -- refusals ("its last flight is still up"), the stale copies flying on unbound
            q.downDone = true
            local why = (had and had.respawn and "a plane of it the host has up wasn't here: spawned again")
                or (had and had.gen ~= q.gen and ("its last flight here, gen " .. tostring(had.gen)))
                or (had and "spawned here, nothing of it seen") or "no longer tracked here"
            -- ((0.73.77, plan A3) its wrecks too: one the game still counts in the unit refused its spawns while nothing
            -- of it was tracked here (dukka 22 refusals over 7 flights, mobi118 26, 2026-11-02))
            local n, w = takeUnitDown(unit, had, true)
            q.downN, q.wrecksN = n, w
            log(string.format("coop: %s is up here (%d alive; %s): %d of its objects taken down for the host's (gen %s)%s",
                unit, alive, why, n, tostring(q.gen), w > 0 and string.format(", and %d wrecks of it still in the world", w) or ""))
        end
        -- (the Alicorn's last copy can't be shot down here: its parked pools are invincible, so it's taken off whole,
        -- as the host does when one is left from last time, and the host's fresh one comes in its place)
        if SPC and unit == SPC.alicornUnit and not q.alcnRemoved and rawEvent then
            q.alcnRemoved = true
            local r = rawEvent("RE_SV_AlcnRemove")
            log("coop: the Alicorn's last copy here is still up (" .. tostring(rawUnitAlive(unit)) .. " alive): taken off whole "
                .. "for the host's (RE_SV_AlcnRemove " .. tostring(r) .. ")")
        end
        q.tries = (q.tries or 0) + 1
        if q.tries < 6 then q.at = os.clock() + 1.5; return false end
        -- ((0.73.77, plan A3) the last resort, after 6 tries: the runtime takes the unit off the phase's list whatever it
        -- counts (SV_Recycle(unit, 1): 1 recycled, 0 nothing to do, < 0 an error); [coop] force_recycle = false: off)
        if type(SV_Recycle) == "function" and cfg().force_recycle ~= false then
            crumb(string.format("coop: %s still up here (%d alive) after %d tries: SV_Recycle", unit, alive, q.tries))
            local okR, rr = pcall(SV_Recycle, unit, 1)
            if okR and rr == 1 then M.cnt.recycled = M.cnt.recycled + 1 end
            log(string.format("coop: %s unstuck: still %d alive here after %d tries; its last flight taken off the phase's "
                .. "list anyway (SV_Recycle: %s)", unit, alive, q.tries, not okR and ("error " .. tostring(rr))
                or (rr == 1 and "recycled") or (rr == 0 and "nothing to do") or (SV_ERR[rr] or tostring(rr))))
        else
            log("coop: " .. unit .. "'s last copies are still up; spawning anyway" .. (type(SV_Recycle) ~= "function"
                and " (no SV_Recycle in this runtime)" or " ([coop] force_recycle off)"))
        end
    elseif q.downDone and not q.unstuckSaid and (alive == 0 or alive == -7) then   -- ((0.73.77, plan A3) the take-down
                                                                                     -- let it spawn: 0 up, or off the list)
        q.unstuckSaid = true
        M.cnt.unstuck = M.cnt.unstuck + 1
        log(string.format("coop: %s unstuck after %d tries: its last copies here taken down (%d up, %d wrecks)", unit,
            (q.tries or 0) + 1, q.downN or 0, q.wrecksN or 0))
    end
    for _, op in ipairs(q.ops) do
        if not knownRow(op.row) then
            once("row" .. tostring(op.row), "coop: the host's aircraft " .. short(op.row, 64) .. " isn't in this game's table; not set")
        elseif op.idx >= 0 then rawSetAircraft(unit, op.row, op.idx) else rawSetAircraft(unit, op.row) end
    end
    if SPW and SPW.noteRows then pcall(SPW.noteRows, unit, q.ops) end   -- (its special weapons fired here: sv_spweapons.lua)
    if q.level and q.level >= 0 and rawSetLevel then rawSetLevel(unit, q.level) end
    local old = M.cunits[unit]
    local same = old and old.gen == q.gen
    M.cunits[unit] = { gen = q.gen, n = 0, planes = {}, binds = same and old.binds or {}, gbinds = same and old.gbinds or {},
                       at = os.clock() }
    local pb = M.pendBind and M.pendBind[unit]               -- (binds that came before its spawn was queued)
    if pb and pb.gen == q.gen then
        for ord, id in pairs(pb.binds) do M.cunits[unit].binds[ord] = id end
        for key, id in pairs(pb.gbinds) do M.cunits[unit].gbinds[key] = id end
        M.pendBind[unit] = nil
    end
    spawningUnit, spawningIdx = unit, 0                  -- (each copy's index in its flight, p.k: the host's order too)
    if SPC and unit == SPC.alicornUnit then SPC.alcnPool = nil end   -- ((0.73.83) this copy's pools, not the last one's: as the host's alicornSpawn)
    crumb(string.format("coop: the host's %s spawned here (gen %s)", tostring(unit), tostring(q.gen)))
    local r
    if q.pose then r = rawSpawn(unit, q.pose[1], q.pose[2], q.pose[3], q.pose[4]) else r = rawSpawn(unit) end
    spawningUnit, spawningIdx = nil, nil
    if type(r) == "number" and r > 0 and SPC and SPC.sawSpawn then SPC.sawSpawn(unit) end   -- ((0.73.83) this game's copies' units: SPC.recycleLater's)
    if r == -6 or r == -1 then                           -- (this game's level isn't ready: again in a second)
        q.tries = (q.tries or 0) + 1
        if q.tries < 30 then q.at = os.clock() + 1; M.cunits[unit] = old; return false end
    end
    M.lastSpawnAt = os.clock()
    if type(r) ~= "number" or r <= 0 then
        local left = {}                                  -- ((0.73.73) what of it here couldn't be taken down)
        M.cnt.refused = M.cnt.refused + 1                -- ((0.73.77, plan A6) the sync report's flights refused)
        for _, e in pairs(M.objsOf[unit] or {}) do
            if upHere(e.obj) and nameOf(e.obj) == e.name then left[#left + 1] = tostring(e.name):match("([^%.:]+)$") or "?" end
        end
        log("coop: the host's " .. unit .. " not spawned here (" .. (SV_ERR[r] or tostring(r)) .. ")" .. (#left > 0 and
            string.format("; %d of its objects here still up: %s", #left, table.concat(left, ", ", 1, math.min(#left, 4))) or ""))
    else
        M.cunits[unit].upAt = M.lastSpawnAt                  -- (its appearance orders 2 s on: holdDue)
    end
    return true
end

-- A joiner spawns nothing until its own plane is in Survival's level and a few seconds have passed: the host's
-- spawns came in while two joiners' levels were still loading, and spawning then crashed their games (2026-10-25).
local READY_S = 3
local function levelReady()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not (D and valid(pawn)) then M.readyAt = nil; return false end
    M.readyAt = M.readyAt or (os.clock() + READY_S)
    return os.clock() >= M.readyAt
end

-- A forwarded hold (RE_SV_DirHold_NN, the squad director's; RE_SV_WolfHold_<NN><L>, a Wolf trap's) waits here until
-- that flight's copy has had its appearance orders (2 s after it appears; they'd undo an earlier hold, hard rule 26): the
-- host holds its own 3 s after its orders, but a copy spawned late here (doSpawn's retries, a level still loading) got
-- the hold first and lost it (review of unit 6). Its flight's release (RE_SV_DirFree_NN; that plane's RE_SV_WolfFree)
-- drops a hold still waiting; one whose copy isn't up HOLD_MAX_S on is dropped.
local HOLD_AFTER_S, HOLD_MAX_S = 3, 30
local function holdOf(name, kind)                       -- a hold's (or a release's) flight NN and plane letter, or nil
    local nn = name:match("^RE_SV_Dir" .. kind .. "_(%d%d)$")
    if nn then return tonumber(nn), nil end
    local wn, L = name:match("^RE_SV_Wolf" .. kind .. "_(%d%d)(%u)$")
    if wn then return tonumber(wn), L end
    return nil
end
local function holdDue(nn)                              -- when flight NN's copy here can take a hold: nil, at once (none)
    for _, q in ipairs(M.spawnQ) do if poolIndex(q.unit) == nn then return math.huge end end
    for unit, cu in pairs(M.cunits) do
        if poolIndex(unit) == nn then return cu.upAt and cu.upAt + HOLD_AFTER_S or math.huge end
    end
    return nil
end
local function freeWaiting(name)                       -- a release fired here: the holds it ends that still wait
    local fn, fL = holdOf(name, "Free")
    if not (fn and M.holdQ) then return end
    for i = #M.holdQ, 1, -1 do
        local q = M.holdQ[i]
        if q.nn == fn and (fL == nil or q.L == fL) then
            table.remove(M.holdQ, i)
            log("coop: the host's " .. q.name .. " dropped here (" .. name .. " came before it could go)")
        end
    end
end
local function hostEvent(name)                          -- (a joiner) one of the host's events, here
    local nn, L = holdOf(name, "Hold")
    local due = nn and holdDue(nn)
    if due and os.clock() < due then
        M.holdQ = M.holdQ or {}
        if #M.holdQ < 32 then
            M.holdQ[#M.holdQ + 1] = { name = name, nn = nn, L = L, at = os.clock() }
            log("coop: the host's " .. name .. " waits for its copy here to have its own orders")
        end
        return
    end
    freeWaiting(name)
    local r = rawEvent(name)
    if r ~= 1 then once("ev" .. tostring(r), "coop: the host's event " .. name .. " not fired here (" .. (SV_ERR[r] or tostring(r)) .. ")") end
    -- ((0.73.78, plan G4) a flight the host despawned (an ace break-off, the Spaceport's withdrawal): its copies here off,
    -- unpaid (sv_rounds.lua flightWithdrawn), fired here or not (the host's "dn" finishes them then); before, this game's
    -- sweep paid the vanished copies as its own kills a second on)
    local fo = tonumber(tostring(name):match("^RE_SV_FlightOff_(%d%d)$"))
    local fu = fo and poolUnit and poolUnit(fo)
    if fu and flightWithdrawn then
        log(string.format("coop: the host took %s off (%s): %d of its copies here off, unpaid", fu, name, flightWithdrawn(fu)))
    end
end

local function clientRounds(now)
    if not D then return end
    D.now = now
    local r = M.rnd
    if r then
        -- (the measurements' rounds, sv_stats.lua: a joiner runs no startRound or clear of its own, so the host's round
        -- number changing starts one and the host's state going back to "wait" ends it)
        if r.round ~= D.round then
            if STATS then pcall(STATS.roundEnd, now) end
            D.round = r.round
            RUN.roundKills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 }
            if STATS and r.round >= 1 and r.state ~= "wait" then pcall(STATS.roundStart, now) end
        end
        if STATS and r.state == "wait" and D.state ~= "wait" then pcall(STATS.roundEnd, now) end
        -- ((0.73.83) the round's kills from this game's own count, as the host shows its own: the host's callout was
        -- sent to every joiner, wrong for Rapt0r in 8 of 9 rounds (0.73.79, 2026-11-04))
        if r.state == "wait" and D.state ~= "wait" and D.round == r.round then
            local k = RUN.roundKills
            if k then
                log(string.format("kills: round %d: you %d, allied aircraft %d, ships %d, airfield defences %d, airstrikes %d (this game's)",
                    D.round, k.you or 0, k.allies or 0, k.ships or 0, k.defences or 0, k.airstrike or 0))
                if (k.allies or 0) + (k.ships or 0) + (k.defences or 0) > 0 then
                    local t = CFG.hud.text
                    COOP.localCallout(string.format(t.kills, D.round), string.format(t.kills_sub, (k.you or 0) + (k.airstrike or 0),
                        k.allies or 0, k.ships or 0, k.defences or 0))
                end
            end
        end
        D.state = r.state
        if r.state == "wait" then D.at = now + r.secs - (os.clock() - r.got) else D.at = now end
        D.wave = r.wave > 0 and r.wave or nil
        D.intLevel = r.level and { round = r.round, level = r.level } or nil   -- (the copies fly it: DIR.level, P4)
        D.glitchPhase = r.glitchPhase                    -- (AB.L..IN's on the host: ANOM.clientGlitch, P7)
        D.hostSpecial = r.hostSpecial                    -- ((0.73.77) the host's special and its state: ANOM.clientTick, SPC.clientClean)
        local hs = r.hostSpecial                         -- ((0.73.79) her song and sounds loaded before her mood: sv_sound.lua)
        if (r.special == "valka" or (type(hs) == "table" and hs.kind == "valka")) and SND and SND.preloadValka then
            pcall(SND.preloadValka)
        end
        if r.waves > 0 then D.waves = D.waves and #D.waves == r.waves and D.waves or {}; for i = #D.waves + 1, r.waves do D.waves[i] = {} end
        else D.waves = nil end
    end
    if not levelReady() then return end
    if M.dvQ and #M.dvQ > 0 then                         -- the director's events here once their delay is up ("dv")
        local keep = {}
        for _, q in ipairs(M.dvQ) do
            if os.clock() < q.at then keep[#keep + 1] = q
            elseif os.clock() > q.at + DV_LATE_S then
                once("dvlate", string.format("coop: the host's director event %s dropped (%.1f s past its time: this level "
                    .. "wasn't ready)", q.name, os.clock() - q.at))
            elseif dvCopy(q.name, q.unit) then
                freeWaiting(q.name)
                local r = rawEvent(q.name)
                log(string.format("coop: director %s fired here (%s): %s", q.name, q.unit, r == 1 and "fired" or (SV_ERR[r] or tostring(r))))
            end
        end
        M.dvQ = keep
    end
    if M.holdQ and #M.holdQ > 0 then                     -- the host's holds once their copies have had their orders
        local keep, t = {}, os.clock()
        for _, q in ipairs(M.holdQ) do
            local due = holdDue(q.nn)
            if due and t < due and t - q.at < HOLD_MAX_S then keep[#keep + 1] = q
            elseif due and t < due then
                log(string.format("coop: the host's %s dropped here (its copy wasn't up %d s on)", q.name, HOLD_MAX_S))
            else
                local r = rawEvent(q.name)
                log(string.format("coop: the host's %s fired here %.1f s after it came (its copy's orders first): %s", q.name,
                    t - q.at, r == 1 and "fired" or (SV_ERR[r] or tostring(r))))
            end
        end
        M.holdQ = keep
    end
    if ANOM and ANOM.clientTick then                     -- the Anomaly's field on your own distance to its copy
        local okA, errA = pcall(ANOM.clientTick)
        if not okA then once("anomField", "coop: anomaly field error " .. tostring(errA)) end
    end
    if ANOM and ANOM.clientGlitch then                   -- AB.L..IN's copy in its phase 3: its ECM pods off here too
        local okG, errG = pcall(ANOM.clientGlitch, now)
        if not okG then once("glitchPods", "coop: AB.L..IN pods error " .. tostring(errG)) end
    end
    if SPC and SPC.clientClean then                      -- ((0.73.77) D4: a finished special's copies taken off here)
        local okSc, errSc = pcall(SPC.clientClean, now)
        if not okSc then once("specialClean", "coop: special clean-up error " .. tostring(errSc)) end
    end
    for i = #M.spawnQ, 1, -1 do
        local q = M.spawnQ[i]
        if os.clock() >= (q.at or 0) then
            local okS, done = pcall(doSpawn, q)
            if not okS then log("coop: spawn error " .. tostring(done)); done = true end
            if done then table.remove(M.spawnQ, i) end
        end
    end
    -- the host's events held while this level loaded, in order (code review: some set lasting state, as the railgun
    -- warning and the shuttle's countdown), after the spawns waiting with them (an event for a unit not up yet does
    -- nothing: the Alicorn's open core for a joiner who started over); older than a minute: let go
    if M.evQ and #M.evQ > 0 and #M.spawnQ == 0 and os.clock() - (M.lastSpawnAt or 0) >= 2 then
        local q = M.evQ
        M.evQ = nil
        for _, e in ipairs(q) do
            if os.clock() - e.at < 60 and not keptThrough(e.unit, e.name) then hostEvent(e.name) end   -- (a hold: once its
        end                                                                                             -- copy's had its orders)
    end
end

-- (a joiner, every 5 s) a copy spawned here that's still not bound to the host's plane STRAY_S on: never driven by the
-- host, it would fly on by its own AI (the co-op run of 2026-10-30: enemies seen a round after the host had cleared them).
-- (0.73.73) A stray is up: not a copy the host has said is down, nor one taken down here in the last DOWN_KEEP_S. The
-- host's "dn" took its copy down and left it in its flight's planes here, so 0.73.70 counted each of the host's kills a
-- stray a few seconds on and asked for the whole picture: 105 of the testers' 115 "jn" came within 12 s of the host's
-- kill (A04's crumbs: 12:41:00.089 "copy ..._2147415945 taken down (id 1)", 12:41:01.643 the same copy "taken down (id 0,
-- torn: not a kill)", 12:41:02 every copy torn down). A stray is taken down, then the host's picture asked for: its
-- answer is a repair (onResync), which brings a flight the host still has up whole again here, bound to the host's.
local STRAY_S, DOWN_KEEP_S = 15, 30
local function strayable(o, a, id)
    if id and M.dead[id] then return false end
    local t = M.downAt[a]
    if t and os.clock() - t < DOWN_KEEP_S then return false end
    return (health(o) or 1) > 0
end
local function strayTick(now)
    if now < (M.strayAt or 0) then return end
    M.strayAt = now + 5
    pruneObjs()
    for a, t in pairs(M.downAt) do if now - t >= DOWN_KEEP_S then M.downAt[a] = nil end end
    for a, k in pairs(M.killer or {}) do if now - k.at >= DOWN_KEEP_S then M.killer[a] = nil end end   -- ((0.73.77) C1)
    local bound = {}
    for _, c in pairs(M.copies) do local a = c.addr or live(c.obj); if a then bound[a] = true end end
    local found, inFound = {}, {}
    for unit, cu in pairs(M.cunits) do
        if cu.at and now - cu.at >= STRAY_S then
            for ord, o in pairs(cu.planes or {}) do
                local a = live(o)
                if a and not bound[a] and not inFound[a] and strayable(o, a, cu.binds and cu.binds[ord]) then
                    inFound[a] = true
                    found[#found + 1] = { o = o, a = a, cu = cu, ord = ord, what = unit .. " #" .. ord }
                end
            end
        end
    end
    -- and any enemy AI plane here (sv_core's `planes`: allies, wingmen and the Alicorn's parked ones aren't in it; the other
    -- players' AI stand-ins skipped) that isn't one of the host's: the user, 2026-10-30, "I'm seeing players go after enemies
    -- that I'm not seeing, no target boxes or anything, however on their side they see aircraft there"
    M.strayFirst = M.strayFirst or {}
    local stillHere = {}
    for _, p in ipairs(planes or {}) do
        local o = p.obj
        local a = live(o)
        if a and not inFound[a] and not p.down and not (p.unit and SLOT_OF[p.unit]) and not bound[a] then
            stillHere[a] = true
            local first = M.strayFirst[a]
            if not first then M.strayFirst[a] = now
            elseif now - first >= STRAY_S and strayable(o, a) then
                inFound[a] = true
                found[#found + 1] = { o = o, a = a, what = (p.unit or "?") .. " " .. tostring(p.name) }
            end
        end
    end
    for a in pairs(M.strayFirst) do if not stillHere[a] then M.strayFirst[a] = nil end end
    -- (each flight's copies 20 s after they spawned: how many got the host's id, once)
    for unit, cu in pairs(M.cunits) do
        if cu.at and not cu.bindSaid and now - cu.at >= 20 and (cu.n or 0) > 0 then
            cu.bindSaid = true
            local nb = 0
            for ord = 1, cu.n do if cu.binds and cu.binds[ord] then nb = nb + 1 end end
            if nb < (cu.n or 0) then
                -- (which generation it was spawned as, and the host's last ids for that unit: whether they came at all.
                -- The co-op run of 2026-10-31: flights re-spawned after a resync went unbound, 57 on one joiner's game)
                local bl = M.bdLast and M.bdLast[unit]
                log(string.format("coop: the host's %s here: %d of %d planes bound to the host's (spawned as gen %s; the host's "
                    .. "last ids for it: %s)", unit, nb, cu.n or 0, tostring(cu.gen),
                    bl and string.format("%d for gen %s", bl.n, tostring(bl.gen)) or "none"))
            end
        end
        -- ((0.73.80) and its ships, vehicles and parts, once a spawn: the amphibious assault's craft, the defences and the
        -- shuttle's pad had no ids before 0.73.80, and their copies here fought on their own)
        if cu.at and not cu.gbindSaid and now - cu.at >= 20 and next(cu.gcount or {}) ~= nil then
            cu.gbindSaid = true
            local seen, nb, ids = 0, 0, 0
            for _, k in pairs(cu.gcount) do seen = seen + k end
            for _ in pairs(cu.gb or {}) do nb = nb + 1 end
            for _ in pairs(cu.gbinds or {}) do ids = ids + 1 end
            log(string.format("coop: the host's %s here: %d of %d ground objects bound to the host's ids (%d ids from the host)%s",
                unit, nb, seen, ids, nb < seen and "; the rest fight on their own here" or ""))
        end
    end
    if #found == 0 or not COOP.client() then return end
    local rp = M.rep
    if rp and not rp.done then return end                -- (the host's picture on its way: it may bind them)
    local names = {}
    for i, f in ipairs(found) do
        if i <= 6 then names[i] = f.what end
        killCopy(0, f.o, true, true)
        if f.cu and f.ord and f.cu.planes[f.ord] == f.o then f.cu.planes[f.ord] = nil end
        M.strayFirst[f.a] = nil
    end
    M.cnt.strays = M.cnt.strays + #found
    M.tornWhy = "strays"
    -- (then the host's picture, at most every 2 minutes: a repair, onResync; a flight it still has up that lost a plane
    -- here comes again whole, bound to the host's)
    local asked = false
    if now >= (M.resyncAt or 0) and now - (M.jnAt or -1e9) >= 30 then
        M.resyncAt, M.jnAt = now + 120, os.clock()
        send(true, "jn")
        M.cnt.jnSent = M.cnt.jnSent + 1
        asked = true
    end
    log(string.format("coop: %d stray enemy copies taken down (here %d s, never bound to the host's)%s: %s", #found, STRAY_S,
        asked and "; asked the host for its whole picture (jn): a flight of these it still has up comes again" or "",
        table.concat(names, ", ")))
end

-- (0.73.79) Which of a copy's hits at the floor were yours. 0.73.77-78 went by the copy's DamageHistoryMap alone once
-- your plane had shown up in any map (M.ownSeen), and a hit it didn't find under your plane was "not yours": the copy
-- was put back up and nothing sent. Your missiles aren't found there (2026-11-03, 0.73.78, four players: Nada's two
-- missiles from 0.3 km "damage: you 0"; Shazzy "could not damage a single" enemy, the host "everyone else dumping into
-- enemies ... 6+ missiles"): every missile that would have finished a copy was undone here and never reached the host,
-- whose own planes never go through the floor (its game was normal). Now your missiles and gun aim are kept here, by
-- the copy they went for: the missile's target (FiredExplosiveWeapons' TargetToHome, as each is launched and when it's
-- gone) and the gun's (SV_PlayerTarget while it fires).
M.mslAt, M.mslEnd, M.gunAtT, M.shotTgt = {}, {}, {}, {}
local FIRED_MSL_S, FIRED_GUN_S, MSL_END_S, FLOOR_RESEND_S = 25, 1.5, 2, 2
function M.shotMark(a, ta) M.mslAt[ta] = os.clock(); M.shotTgt[a] = ta end
function M.shotEnd(a)
    local ta = M.shotTgt[a]
    M.shotTgt[a] = nil
    if ta then M.mslEnd[ta] = os.clock() end
end
function M.gunMark(t) M.gunAtT[t] = os.clock() end
-- "msl" one of your missiles went for addr in the last FIRED_MSL_S, "gun" your gun is firing at it, or nil
function M.firedAt(addr, now)
    if not addr then return nil end
    local m, g = M.mslAt[addr], M.gunAtT[addr]
    if m and now - m <= FIRED_MSL_S then return "msl" end
    if g and now - g <= FIRED_GUN_S then return "gun" end
    return nil
end
local function shotsPrune(now)
    if now < (M.shotPruneAt or 0) then return end
    M.shotPruneAt = now + 10
    for _, t in ipairs({ M.mslAt, M.mslEnd, M.gunAtT }) do
        for k, at in pairs(t) do if now - at > 60 then t[k] = nil end end
    end
    local n = 0
    for _ in pairs(M.shotTgt) do n = n + 1 end
    if n > 200 then M.shotTgt = {} end                     -- (missiles seen launched but never gone: a level change)
end
-- what the hit that took copy c to the floor is sent to the host as (x 10): own is your damage on it since the last look
-- from its map (nil: unread, or your plane not in any map yet), loss what it lost here (less the stand-ins' share)
function M.floorLoss(c, own, loss, now)
    if own and own >= c.exp then return own end           -- (the map has your whole hit)
    local f = M.firedAt(c.addr, now)
    if f == "msl" then                                     -- (your missile went for it: the hit is yours, whole)
        M.cnt.floorMsl = (M.cnt.floorMsl or 0) + 1
        if not (own and own > 0) then
            once("floormsl", string.format("coop: a copy taken to the floor by your missile (its map has %s of yours): sent "
                .. "whole to the host (%.1f)", own and string.format("%.1f", own / 10) or "nothing read", c.exp / 10))
        end
        return c.exp
    end
    if own and own > 0 then return own end                 -- (your gun's, from the map)
    if own == nil and loss > 0 then return c.exp end       -- (as 0.73.76: unread, it's yours)
    if f == "gun" then return c.exp end                    -- (your gun on it this second)
    return 0                                               -- (not yours: an ally's copy, a ship's, a crash)
end

local function clientTick()
    pcall(strayTick, os.clock())
    pcall(shotsPrune, os.clock())
    pcall(M.buildTick, os.clock())
    -- the copies' hits: what each lost since last time goes to the host, less what another player's stand-in did to it
    -- here (their own hits come from their game: the stand-ins fly damage-0 rows, COOP.syncSetup; this is the backstop)
    -- (0.73.77, plan A1) A copy waits at the floor (FLOOR_IN, floorOn) for the host's kill, and the floor clips the hit
    -- that takes it there, so what's sent then is your own damage from its DamageHistoryMap (every hit is added there in
    -- full: the whole missile), or, the map unread, all it was expected to have (0.73.76's). A copy taken to the floor by
    -- something else (the host's allies' copies here, a crash) sends nothing and is put back up to what the host's has
    -- after your hits; one whose hit sent is lethal waits there for the host's "dn" (A6: the sync report's wait). A copy
    -- at the floor whose health doesn't move (the clamp: the host said less than the floor) is asked its map each tick.
    local ins, pa = nil, false
    for id, c in pairs(M.copies) do
        if valid(c.obj) then
            local h = health(c.obj)
            if h and h < c.exp and c.ally then
                c.exp = h                                  -- (an ally's copy: its fight is the host's, nothing sent)
                if h > 0 and h <= FLOOR_IN and (c.hp or 0) > FLOOR_IN then   -- ((0.73.77) at the floor: back to the host's)
                    local v = c.hp
                    if pcall(function() c.obj.HealthInternal = v end) then c.exp = v end
                end
            elseif h and h < c.exp then
                local loss = c.exp - h
                ins = ins or (M.standInSet and M.standInSet()) or {}
                if pa == false then pa = myAddr() end
                local sd, mine = 0, nil                    -- ((0.73.77) its map read only while it's live: kept between ticks)
                if live(c.obj) then sd, mine = M.historyOf(c.obj, ins, pa) end
                local inc = sd - (c.sdmg or 0)
                c.sdmg = sd
                if inc > 0 then
                    local cut = math.min(loss, inc * 10)                   -- (DamageHistoryMap: health, not x 10)
                    loss = loss - cut
                    M.backstops = (M.backstops or 0) + 1
                    if M.backstops <= 5 or M.backstops % 50 == 0 then
                        log(string.format("coopfire: copy %d lost %.1f, %.1f of it another player's stand-in's here: %s "
                            .. "(%d times)", id, (loss + cut) / 10, cut / 10, loss > 0 and string.format("%.1f sent", loss / 10)
                            or "nothing sent", M.backstops))
                    end
                end
                local own = nil                            -- ((0.73.77) yours since the last look, x 10; nil: unread,
                if mine then                               -- or your plane not yet seen in any copy's map this level)
                    local d = math.max(0, (mine - (c.mine or 0)) * 10)
                    c.mine = mine
                    if M.ownSeen then own = d end
                end
                local newH = h
                if h > 0 and h <= FLOOR_IN then            -- (down here, the floor not held: as before, never put back)
                    loss = M.floorLoss(c, own, loss, os.clock())   -- ((0.73.79) your missiles too, not the map alone)
                    if loss < c.exp then                   -- (not lethal by what's sent: up to the host's after it)
                        local v = math.max(FLOOR_IN + 1, c.exp - loss)
                        if pcall(function() c.obj.HealthInternal = v end) then newH = v end
                        M.cnt.floorBack = M.cnt.floorBack + 1
                    elseif not c.floorAt then
                        c.floorAt = os.clock()             -- (lethal: it waits here for the host's kill)
                        c.preFloor = c.exp                 -- ((0.73.79) what it had: sent again if it waits on, below)
                        M.cnt.floored = M.cnt.floored + 1
                    end
                end
                if loss > 0 then
                    send(true, "ht", id, string.format("%.1f", loss / 10))
                    c.sentAt, c.sentFrom = os.clock(), c.exp   -- ((0.73.79) the host's "hp" from before it lands is held off)
                end
                c.exp = newH
            elseif h and h > 0 and h <= FLOOR_IN and not c.ally then
                -- ((0.73.77) at the floor, its health not moving: your hits since, from the map)
                if pa == false then pa = myAddr() end
                local mine = nil
                if live(c.obj) then mine = select(2, M.historyOf(c.obj, nil, pa)) end
                local own = (mine and M.ownSeen) and (mine - (c.mine or 0)) * 10 or 0
                if mine then c.mine = mine end
                local now = os.clock()
                if own > 0 then
                    send(true, "ht", id, string.format("%.1f", own / 10))
                    c.sentAt, c.sentFrom = now, math.max(c.hp or 0, FLOOR_IN)
                    if not c.floorAt then c.floorAt = now; M.cnt.floored = M.cnt.floored + 1 end
                else
                    -- ((0.73.79) a missile of yours that went for it is gone (it hit, or missed) and the host's kill
                    -- hasn't come: what the host last had is sent as a hit, at most every FLOOR_RESEND_S. Its health
                    -- doesn't move at the floor, so this is the only sign of a missile hit here; a miss that ends near
                    -- a copy already held at 1 HP is the price)
                    local e = M.mslEnd[c.addr]
                    if e and now - e <= MSL_END_S and e > (c.resendAt or 0) and now - (c.resendAt or 0) >= FLOOR_RESEND_S then
                        local v = math.max(c.hp or 0, c.preFloor or 0, FLOOR_IN)
                        c.resendAt, c.sentAt, c.sentFrom = now, now, v
                        send(true, "ht", id, string.format("%.1f", v / 10))
                        M.cnt.floorResend = (M.cnt.floorResend or 0) + 1
                        once("floorresend", string.format("coop: copy %d held at the floor, your missile at it gone, no kill "
                            .. "from the host yet: its last health sent again as your hit (%.1f)", id, v / 10))
                        if not c.floorAt then c.floorAt = now; M.cnt.floored = M.cnt.floored + 1 end
                    end
                end
                c.exp = h
            elseif h and h > c.exp then
                c.exp = h                                  -- (raised here: CFG.late, a repair)
            end
        else
            M.copies[id] = nil
        end
    end
end

---------------------------------------------------------------------------------------------------- the other players' planes
local AF_CODE = "BP_PlayerPlane_PP%d+_(%w+)"
-- Every player plane's blueprint folder and name by its code (AC8's 35, build/research/ui/paths.txt: the ADFX-02's has a
-- variant suffix, so a path built from the code alone missed it in COOP2MP's T2, 2026-10-30): COOP.planeClassPath(code)
-- -> the blueprint class's path, for real player planes in place of the AI stand-ins (tools/re/COOP2MP.md)
local PP_BP = { a10c = "PP0001_a10c", f02a = "PP0002_f02a", f04e = "PP0003_f04e", f15c = "PP0004_f15c", f22a = "PP0005_f22a",
                f35c = "PP0006_f35c", f18c = "PP0007_f18c", j39e = "PP0008_j39e", su34 = "PP0009_su34", e18g = "PP0010_e18g",
                typn = "PP0011_typn", f15j = "PP0012_f15j", a06e = "PP0013_a06e", rflm = "PP0014_rflm", su25 = "PP0015_su25",
                x40a = "PP0016_x40a", mr2k = "PP0017_mr2k", fa36 = "PP0018_fa36", ea36 = "PP0019_ea36", m29a = "PP0020_m29a",
                su57 = "PP0021_su57", f16c = "PP0022_f16c", f14d = "PP0023_f14d", f18f = "PP0024_f18f", f15e = "PP0025_f15e",
                su47 = "PP0026_su47", m21b = "PP0027_m21b", su35 = "PP0028_su35", m31b = "PP0029_m31b", su33 = "PP0030_su33",
                e06b = "PP0031_e06b", f18e = "PP0032_f18e", f14a = "PP0034_f14a", adfx02 = "PP0038_adfx02_L001" }
function COOP.planeClassPath(code)
    local d = type(code) == "string" and PP_BP[code]
    if not d then return nil end
    local b = "BP_PlayerPlane_" .. d
    return string.format("/Game/Blueprints/Vehicle/PLAYER/Plane/%s/%s.%s_C", d, b, b)
end
local function myAirframe()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return nil end
    local code = nameOf(pawn):match(AF_CODE)
    local c = cfg()
    if not (code and c.airframes[code]) then                   -- (the others see it as the default: say so, once a code)
        once("afcode" .. tostring(code), string.format("coop: your plane (%s) isn't in [coop] airframes: the others see it "
            .. "as %s", tostring(code or nameOf(pawn):match("^(%S+)")), tostring(c.default)))
    end
    return code and (c.airframes[code] or c.default) or c.default, code
end

function COOP.peerPlane(o, slot)
    if not valid(o) or not inSurvival(o) then return end
    for k, v in pairs({ bPermissionToFire = false, bPermissionToEngage = false, bPermissionToUseFlares = false,
                        bPermissionToProvoke = false, bPermissionToEvade = false, bIsNotLockonTarget = true,
                        bCanBeDamagedByAlly = false, bCauseExplosionOnDeath = false, bShowHUDBox = true }) do
        pcall(function() o[k] = v end)
    end
    pcall(function() o:SetIsInvincible(true) end)
    local P = M.peers[slot] or {}
    M.peers[slot] = P
    P.obj, P.addr, P.spawning, P.shown = o, addrOf(o), nil, nil
    P.gear, P.flare, P.gunNext, P.flareNext = nil, nil, nil, nil       -- (the sync's: a new plane comes gear up)
    local r = type(SV_CoopPeer) == "function" and P.addr and SV_CoopPeer(slot, P.addr) or -9
    log(string.format("coop: player %d's plane is up (%s, %s)", slot + 1, nameOf(o):match("([^%.:]+)$") or "?",
        r == 1 and "moved every frame" or ("NOT moved: " .. tostring(r))))
end

-- COOP2MP T3 (tools/re/COOP2MP.md, hard rule 53): each other player as their own airframe's player plane, as AC8's
-- Online Mode shows them (CFG.coop.real_planes), not an AI stand-in: SV_CoopSpawnPP with their slot (a network dummy
-- controller, role 2) where their stream says they are, bound with SV_CoopPeer; the runtime feeds its own update from
-- their stream (flight.c FlNetFeed: pose, stick, afterburner, flight State). Their airframe's code comes in their "hi"
-- ("pi"); without one (an older build), or if the spawn fails, the AI stand-in as before.
local function realOn() return cfg().real_planes == true and type(SV_CoopSpawnPP) == "function" end
function COOP.realOn() return COOP.open and realOn() end
-- (0.73.80, the 31-round test's finding coop7) A plane code this game has no player plane blueprint for (a modded plane
-- only its player has: Alyssa's Falken, falken-us4ss, PP9001_falken_L001) is shown as a stock player plane of [coop.
-- real_fallback] (falken = adfx02: the add-on is built on the ADFX-02), not an AI stand-in: the joiners flew an AI F-16C
-- for her, an ally's blue box and none of her launches replayed. It gets a player's green box and T4b's replays (flight.c
-- FwWeaponOk drops a weapon number it hasn't). Its own default weapons and paint: their loadout and paint are another
-- airframe's (a modded plane's weapon ids may not exist in this game at all). ((0.73.80) Their own game's stock base for
-- it comes first, [coop] real_default after: M.fallbackFor; the AI stand-in last.)
function M.realFallback(code)
    local t = cfg().real_fallback
    if type(t) ~= "table" or type(code) ~= "string" then return nil end
    local fb = t[code]
    if fb == nil then for k, v in pairs(t) do if type(k) == "string" and k:lower() == code:lower() then fb = v end end end
    if type(fb) ~= "string" or fb == "" or fb == code or not COOP.planeClassPath(fb) then return nil end
    return fb
end
-- (0.73.80, the user 2026-11-04: "try the Falken's own blueprint first") A modded plane's own blueprint by its code
-- ([coop.real_paths]: falken = the Falken add-on's BP_PlayerPlane_PP9001_falken_L001, from Saint Alessia's log of the
-- 31-round test), tried after the path the player's own game sends (M.realClassFor): a game with that add-on installed
-- shows the real thing, with their loadout and paint; one without it, a stock fallback. Only a player plane class's path
-- under /Game/ (M.clsOk); nil when none is listed.
function M.modClassPath(code)
    local t = cfg().real_paths
    if type(t) ~= "table" or type(code) ~= "string" then return nil end
    local p = t[code]
    if p == nil then for k, v in pairs(t) do if type(k) == "string" and k:lower() == code:lower() then p = v end end end
    if not M.clsOk(p) then return nil end
    return p
end
M.modMiss = {}                                           -- (a path that didn't load: not asked again this session)

---------------------------------------------------------------------------------------------------- modded planes and skins
-- (0.73.80, the user 2026-11-04: "Can we do this for all future modded stuff ... if players have mods installed but
-- someone doesn't, that one person who doesn't have the mods sees [the stock version], but if they were to have the mods,
-- they would see the changes"; "planes and skins first") Each game says what it really flies, and every other game shows
-- it where it's installed there, a stock plane where it isn't: never invisible, never a crash.
--   sender: a plane with no stock code (the Falken's falken) adds two last fields to its "hi" (and the host's "pi" relays
--     them, after the Steam ID): its blueprint class's path (/Game/... only) and its stock BASE, the stock player plane it's
--     built on, for games without it: a parent of its class that is a stock player plane's, else its DT_LiveAircraft row's
--     OriginalPlaneStringID (the Falken's PP0038_adfx02_L001: adfx02), else this game's [coop.real_fallback]. A stock plane
--     sends neither (its code says it all): its messages are as before.
--   receiver (spawnReal -> M.realClassFor): a code with no stock blueprint here: their path, then [coop.real_paths],
--     loaded only when it's a player plane class's path (M.clsOk) and kept only when the class loaded is one (IsChildOf
--     LivePlayerPlane, else by its name), with their loadout and paint; else their base, else [coop.real_fallback], else
--     [coop] real_default (f16c), each with its own default weapons and paint; the AI stand-in last.
--   skins (M.paintHere): a paint's skin id this game hasn't (DT_Skin's rows, or the game's information manager's
--     SkinDataMap_) is given as -1, the plane's default paint, the emblems kept; when neither can be read, as sent (as
--     before). The tables are looked for at the main menu (M.tablesPrep), never in a fight.
do
local CLS_MAX = 200                                      -- (a class path's length at most)
local MSG_ROOM = 1080                                    -- (coop.c CO_MAX_LUA 1100: a longer message is cut short)
local KNOWN_SKINS = { 5014001, 21002001, 8014001, 11014001 }   -- (stock skins players flew: a source's check)
local TABLES = {                                         -- (looked for by these paths first, then by name)
    skin = { name = "DT_Skin", paths = { "/Game/Datatables/Information/DT_Skin.DT_Skin", "/Game/Datatables/Skin/DT_Skin.DT_Skin" } },
    aircraft = { name = "DT_LiveAircraft", paths = { "/Game/Datatables/Information/DT_LiveAircraft.DT_LiveAircraft",
                                                     "/Game/Datatables/Aircraft/DT_LiveAircraft.DT_LiveAircraft" } },
}
M.tbl = { path = {}, walks = 0, at = 0, said = {} }
M.skin = { ans = {}, said = {}, n = nil, keyed = nil, ids = nil, dtOk = nil, mapOk = nil }
M.baseOf = {}
local function fstr(v)                                   -- (an FName, an FString or a Lua string, as text)
    if type(v) == "string" then return v end
    if v == nil then return nil end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" then return s end
    return tostring(v)
end
local function shortName(o)
    local ok, n = pcall(function() return o:GetFName():ToString() end)
    if ok and type(n) == "string" and n ~= "" then return n end
    return (nameOf(o):match("([^%.:/%s]+)$"))
end

-- a player plane blueprint class's path: under /Game/, [%w_/.] only, a package and its class (/Game/.../X.X_C, X a
-- BP_PlayerPlane_...), <= 200 characters; with code, the class's own code (BP_PlayerPlane_PPnnnn_<code>) must be it
function M.clsOk(p, code)
    if type(p) ~= "string" or #p > CLS_MAX or p:sub(1, 6) ~= "/Game/" or p:find("//", 1, true) then return false end
    if not p:match("^[%w_/%.]+$") or select(2, p:gsub("%.", "")) ~= 1 then return false end   -- (one dot: no "..")
    local pkg, obj = p:match("/([%w_]+)%.([%w_]+)$")
    if not (pkg and obj == pkg .. "_C" and obj:match("^BP_PlayerPlane_")) then return false end
    if code ~= nil then
        local c = obj:match(AF_CODE)
        if not (c and type(code) == "string" and c:lower() == code:lower()) then return false end
    end
    return true
end
function M.baseOk(b) return type(b) == "string" and #b <= 16 and b:match("^%w+$") ~= nil end

-- the new last fields of "hi" / "pi" (f, the message's fields so far): a plane with no stock code's class path and stock
-- base; the path left out when the message would be cut (CO_MAX_LUA), nothing for a stock plane
function M.modFields(f, code, cls, base)
    if type(code) ~= "string" or code == "" or COOP.planeClassPath(code) then return f end
    cls = M.clsOk(cls, code) and cls or ""
    base = M.baseOk(base) and base or ""
    if cls == "" and base == "" then return f end
    local n = 0
    for i = 1, #f do n = n + #tostring(f[i]) + 1 end
    if n + #cls + #base + 2 > MSG_ROOM then
        once("modfieldslong", string.format("coop: a message with your plane's class path would be %d characters: sent without it "
            .. "(players with its add-on see its stock base %s)", n + #cls + #base + 2, base ~= "" and base or "or their own fallback"))
        cls = ""
    end
    f[#f + 1], f[#f + 2] = cls, base
    return f
end

-- the tables the plane and skin checks read, looked for once a session where no fight is (COOP.tick with no run: the
-- main menu, the hangar): by a few likely paths, then one walk over the DataTables loaded (3 at most, 10 s apart)
function M.tablesPrep()
    local T = M.tbl
    local now = os.clock()
    if now < (T.at or 0) then return end
    T.at = now + 10
    local want = false
    for k, d in pairs(TABLES) do
        if T[k] and not liveObj(T[k]) then T[k] = nil end
        if not T[k] and not T.tried then
            for _, p in ipairs(d.paths) do
                local ok, o = pcall(StaticFindObject, p)
                if ok and o ~= nil and valid(o) then T[k], T.path[k] = o, p; break end
            end
        end
        if not T[k] then want = true end
    end
    T.tried = true
    if want and T.walks < 3 and not (type(walkBusy) == "function" and walkBusy()) then
        T.walks = T.walks + 1
        local ok, list = pcall(FindAllOf, "DataTable")
        for _, o in ipairs((ok and type(list) == "table") and list or {}) do
            local n = valid(o) and shortName(o)
            for k, d in pairs(TABLES) do
                if n == d.name and not T[k] then T[k], T.path[k] = o, (nameOf(o):match("(/Game/%S+)$") or n) end
            end
        end
    end
    for k, d in pairs(TABLES) do
        local s = T[k] and ("found: " .. tostring(T.path[k])) or (T.walks >= 3 and "not found (its plane / skin checks without it)" or nil)
        if s and T.said[k] ~= s then T.said[k] = s; log("coop: the game's " .. d.name .. " " .. s) end
    end
    local okS, errS = pcall(M.skinPrep)
    if not okS then once("skinPrep", "coop: skins: DT_Skin error " .. tostring(errS)) end
end

---------------------------------------------------------------------------------------------------- your plane: what's sent
-- the stock base of a plane with no stock code (nil, how when none): (i) a parent of its class that is a stock player
-- plane's, (ii) its DT_LiveAircraft row's OriginalPlaneStringID, (iii) this game's [coop.real_fallback]
function M.aircraftOrigin(pawn, cls)
    local dt = M.tbl.aircraft
    if not (dt and liveObj(dt)) then return nil end
    local id, sid = nil, (cls ~= nil and shortName(cls) or ""):match("^BP_PlayerPlane_(.+)_C$")
    pcall(function() id = pawn.PlaneTypeID end)
    if type(id) ~= "number" then id = nil end
    local function mine(r)
        local okP, pid = pcall(function() return r.PlaneID end)
        if okP and id and pid == id then return true end
        local okS, ps = pcall(function() return fstr(r.PlaneStringID) end)
        return okS and sid ~= nil and ps == sid
    end
    local keys, row = {}, nil
    if id then keys[#keys + 1] = tostring(math.floor(id)) end
    if sid then keys[#keys + 1] = sid end
    for _, k in ipairs(keys) do
        local ok, r = dtCall(dt, "FindRow", k)
        if ok and r ~= nil and mine(r) then row = r; break end
    end
    if row == nil then
        local names = rowList(dt) or {}
        for i = 1, math.min(#names, 600) do
            local ok, r = dtCall(dt, "FindRow", names[i])
            if ok and r ~= nil and mine(r) then row = r; break end
        end
    end
    if row == nil then return nil end
    local okO, o = pcall(function() return fstr(row.OriginalPlaneStringID) end)   -- (an FName: never Reference, rule 29)
    return (okO and type(o) == "string" and o ~= "" and o ~= "None") and o or nil
end
function M.baseFor(code, cls, pawn)
    if type(code) ~= "string" then return nil, "no plane code" end
    if COOP.planeClassPath(code) then return code, "stock" end
    local c = cls
    for _ = 1, 12 do                                     -- (i)
        if c == nil then break end
        local okS, sup = pcall(function() return c:GetSuperStruct() end)
        if not (okS and sup ~= nil and valid(sup)) then break end
        local n = shortName(sup) or ""
        local bc = n:match("^" .. AF_CODE)
        if bc and COOP.planeClassPath(bc:lower()) then return bc:lower(), "its blueprint's parent " .. n end
        if n == "LivePlayerPlane" then break end
        c = sup
    end
    local okA, ob = pcall(M.aircraftOrigin, pawn, cls)   -- (ii)
    local oc = okA and type(ob) == "string" and ob:match("^PP%d+_(%w+)")
    if oc and oc:lower() ~= code and COOP.planeClassPath(oc:lower()) then
        return oc:lower(), "its aircraft row's OriginalPlaneStringID " .. ob
    end
    local fb = M.realFallback(code)                      -- (iii)
    if fb then return fb, "[coop.real_fallback]" end
    return nil, "none found (its class's parents, its aircraft row, [coop.real_fallback])"
end
-- your plane's class path ("" when it can't be read or sent) and stock base (""): once a plane (by its address and code),
-- the base once a class (M.baseOf), logged once
function M.myPlane(pawn, code)
    pawn = pawn or (survivalPC and valid(survivalPC) and survivalPC.Pawn)
    if not valid(pawn) then return "", "" end
    local a = addrOf(pawn)
    local mp = M.myPlaneAt
    if mp and mp.addr == a and mp.code == code then return mp.cls, mp.base end
    local cls, path = nil, ""
    pcall(function() cls = pawn:GetClass() end)
    if cls ~= nil and valid(cls) then
        local full = nameOf(cls)
        local p = full:match("^%S+%s+(/Game/%S+)$") or full:match("^(/Game/%S+)$")
        if p and M.clsOk(p, code) then path = p end
    else
        cls = nil
    end
    local key = path ~= "" and path or ("code:" .. tostring(code))
    local b = M.baseOf[key]
    if not b then
        local okB, base, how = pcall(M.baseFor, code, cls, pawn)
        if not okB then base, how = nil, "error " .. tostring(base) end
        b = { base = base or "", how = how }
        M.baseOf[key] = b
        if type(code) == "string" then
            log(string.format("coop: your plane %s (%s): its stock base for players without it: %s (%s)", code,
                path ~= "" and path or "its class path unknown", base or "none", tostring(how)))
        end
    end
    M.myPlaneAt = { addr = a, code = code, cls = path, base = b.base }
    return path, b.base
end

---------------------------------------------------------------------------------------------------- another player's plane here
-- a class path loaded and checked a player plane's (nil, why when not; a path that failed isn't asked again: M.modMiss)
function M.isPlayerPlaneClass(c)
    if not (M.ppRoot and valid(M.ppRoot)) then
        local ok, r = pcall(StaticFindObject, "/Script/Live.LivePlayerPlane")
        M.ppRoot = (ok and r ~= nil and valid(r)) and r or nil
    end
    if M.ppRoot then
        local ok, r = pcall(function() return c:IsChildOf(M.ppRoot) end)
        if ok and type(r) == "boolean" then return r, r and "a LivePlayerPlane" or "not a LivePlayerPlane" end
    end
    local n = shortName(c) or "?"
    return n:match("^BP_PlayerPlane_[%w_]+_C$") ~= nil, "by its name " .. n
end
function M.tryClass(p)
    if M.modMiss[p] then return nil, "not installed here (known)" end
    local okL, c = pcall(loadObject, p)
    if not (okL and c ~= nil and valid(c)) then M.modMiss[p] = true; return nil, "not installed here" end
    local isPP, by = M.isPlayerPlaneClass(c)
    if not isPP then M.modMiss[p] = true; return nil, "not a player plane (" .. tostring(by) .. ")" end
    return c
end
-- the stock plane shown for a code with no blueprint here: their game's base, this game's [coop.real_fallback], its
-- [coop] real_default (nil: the AI stand-in)
function M.fallbackFor(code, base)
    local b = type(base) == "string" and base:lower() or nil
    if M.baseOk(b) and b ~= code and COOP.planeClassPath(b) then return b, "their game's base" end
    local fb = M.realFallback(code)
    if fb then return fb, "[coop.real_fallback]" end
    local d = cfg().real_default
    if type(d) == "string" and d ~= "" then
        d = d:lower()
        if COOP.planeClassPath(d) and d ~= code then return d, "[coop] real_default" end
        once("realdefault", "coop: [coop] real_default " .. d .. " isn't a stock plane code: a plane with no blueprint here is an AI stand-in")
    end
    return nil
end
-- (spawnReal) the class to spawn for player slot's code: cls (nil if it didn't load), its path, the fallback's code (nil:
-- theirs), how; or false, why when there's none (the AI stand-in)
function M.realClassFor(slot, code, r0)
    local stock = COOP.planeClassPath(code)
    if stock then return loadObject(stock), stock, nil, "stock" end
    local cands = {}
    if r0 and M.clsOk(r0.cls, code) then cands[1] = { p = r0.cls, src = "the path their game sent" } end
    local rp = M.modClassPath(code)
    if rp and not (cands[1] and cands[1].p == rp) then cands[#cands + 1] = { p = rp, src = "[coop.real_paths]" } end
    local missed = {}
    for _, cd in ipairs(cands) do
        local known = M.modMiss[cd.p]
        local c, why = M.tryClass(cd.p)
        if c then
            log(string.format("coop: player %d's %s: its own blueprint is installed here (%s): the real thing (%s)", slot + 1,
                code, cd.p, cd.src))
            return c, cd.p, nil, cd.src
        end
        if not known then cd.why = why; missed[#missed + 1] = cd end
    end
    local fb, how = M.fallbackFor(code, r0 and r0.base)
    for _, cd in ipairs(missed) do
        log(string.format("coop: player %d's %s: its own blueprint %s (%s): %s instead (its path from %s)", slot + 1, code,
            cd.why == "not installed here" and "isn't installed here" or ("was rejected, " .. tostring(cd.why)), cd.p,
            fb and (how == "[coop.real_fallback]" and how or ("a real " .. fb .. " (" .. how .. ")")) or "the AI stand-in", cd.src))
    end
    if not fb then
        local d = cfg().real_default
        return false, string.format("no player plane blueprint for %s (no base from their game, no [coop.real_fallback] for it, "
            .. "[coop] real_default %s)", tostring(code), (type(d) == "string" and d ~= "") and d or "off")
    end
    local fp = COOP.planeClassPath(fb)
    return loadObject(fp), fp, fb, how
end

---------------------------------------------------------------------------------------------------- skins
-- the skin checks' sources, worked out where no fight is (M.tablesPrep: DT_Skin's keying and ids, again when its row
-- count changes) or on first use (the information manager's SkinDataMap_, one lookup a skin); each kept only when it
-- lists a stock skin (yours, or one players flew: KNOWN_SKINS)
local function mySkin()
    local p = type(M.myPaint) == "function" and M.myPaint() or ""
    local s = tonumber((tostring(p):match("^(%-?%d+)/")))
    return (s and s >= 0) and s or nil
end
local function knowsStock(has)
    local list = { mySkin() }
    for _, id in ipairs(KNOWN_SKINS) do list[#list + 1] = id end
    for _, id in ipairs(list) do if has(id) == true then return true end end
    return false
end
local function skinMap()
    local ok, m = pcall(function()
        local gi = type(gameInstance) == "function" and gameInstance() or nil
        if gi == nil then return nil end
        local im = gi.InformationManager_
        if not (im ~= nil and valid(im)) then return nil end
        return im.SkinDataMap_
    end)
    return ok and m or nil
end
local function mapHas(id)
    local ok, r = pcall(function() return skinMap():Contains(id) end)
    if ok and type(r) == "boolean" then return r end      -- (false is an answer: not `and r or nil`)
    return nil
end
local function dtHas(id)
    local S, dt = M.skin, M.tbl.skin
    if not (dt and S.dtOk and liveObj(dt)) then return nil end
    if S.ids and S.ids[id] then return true end          -- (every row's SkinID, read at the main menu)
    if S.keyed == "name" then                            -- (a row added since, named by its id as the others)
        local ok, r = dtCall(dt, "FindRow", tostring(id))
        if not ok then return nil end
        if r == nil then return false end
        local okI, v = pcall(function() return r.SkinID end)
        return not (okI and type(v) == "number") or v == id
    end
    if S.ids then return false end
    return nil
end
function M.skinPrep()
    local S, dt = M.skin, M.tbl.skin
    if not (dt and liveObj(dt)) then return end
    local names = rowList(dt)
    if not names then if not S.said.rows then S.said.rows = true; log("coop: skins: DT_Skin's rows can't be read") end; return end
    if S.n == #names then return end                     -- (no new rows since: a skin add-on registers at the main menu)
    S.n, S.ans = #names, {}
    local byName, read = true, 0
    for i = 1, math.min(#names, 8) do
        local ok, r = dtCall(dt, "FindRow", names[i])
        local okI, id = false, nil
        if ok and r ~= nil then okI, id = pcall(function() return r.SkinID end) end   -- (the int only: never DecalMaterialRef)
        if okI and type(id) == "number" then
            read = read + 1
            if tostring(math.floor(id)) ~= names[i] then byName = false end
        end
    end
    if read == 0 then
        S.keyed, S.ids, S.dtOk = nil, nil, false
    else
        -- (every row's SkinID kept either way: an add-on's rows may be named otherwise than the game's)
        S.keyed, S.ids = byName and "name" or "field", {}
        for _, nm in ipairs(names) do
            local ok, r = dtCall(dt, "FindRow", nm)
            local okI, id = false, nil
            if ok and r ~= nil then okI, id = pcall(function() return r.SkinID end) end
            if okI and type(id) == "number" then S.ids[math.floor(id)] = true end
        end
    end
    if read > 0 then S.dtOk = true; S.dtOk = knowsStock(dtHas) end
    local s = string.format("coop: skins: DT_Skin %s, %d rows%s", tostring(M.tbl.path.skin), #names,
        read == 0 and ": their SkinID can't be read, not used"
        or (S.dtOk and (", keyed by " .. (S.keyed == "name" and "the skin id" or "their SkinID") .. ": other players' skins are checked against it")
        or ": none of the stock skins in it, not used"))
    if S.said.dt ~= s then S.said.dt = s; log(s) end
end
-- true / false: skin id is / isn't in this game; nil: it can't be told (no source); cached for the session
function M.skinHere(id)
    local S = M.skin
    if S.ans[id] ~= nil then return S.ans[id] end
    if S.mapOk == nil and skinMap() ~= nil then
        S.mapOk = knowsStock(mapHas)
        log("coop: skins: the game's information manager's SkinDataMap_ " .. (S.mapOk and "lists the stock skins: other players' "
            .. "skins are checked against it" or "doesn't list the stock skins here: not used"))
    end
    local said, yes = false, false
    if S.mapOk then
        local r = mapHas(id)
        if r ~= nil then said, yes = true, r end
    end
    if not yes then
        local r = dtHas(id)
        if r ~= nil then said = true; yes = yes or r end
    end
    if not said then return nil end
    S.ans[id] = yes
    return yes
end
-- the paint ("skin/flags/e1,e2,...") given to player slot's plane here: its skin -1 (the plane's default) when this game
-- hasn't it, the emblems kept; as sent when it can't be told. (Review of 0.73.80) A negative id other than -1, or one past
-- an int32, is no game's skin (-1 is the only one the skin loader is known to take as "the default"): -1 whatever the
-- tables say, so no unknown skin reaches SV_CoopSpawnPP from a broken or hostile game.
function M.paintHere(slot, pt)
    if type(pt) ~= "string" or pt == "" then return pt end
    local skin, rest = pt:match("^(%-?%d+)(/.*)$")
    local id = tonumber(skin)
    if not id or id == -1 then return pt end
    if id < 0 or id > 2147483647 then
        local k = slot .. ":" .. skin
        if not M.skin.said[k] then
            M.skin.said[k] = true
            log(string.format("coop: player %d's skin %s isn't a skin id: their plane's default paint", slot + 1, skin:sub(1, 24)))
        end
        return "-1" .. rest
    end
    local okH, have = pcall(M.skinHere, id)
    if not okH then once("skinerr", "coop: skins: check error " .. tostring(have)); have = nil end
    if have == nil then
        once("skinsunchecked", "coop: skins aren't checked here (no DT_Skin found, the game's SkinDataMap_ not readable): "
            .. "each player's paint given as sent")
        return pt
    end
    if have then return pt end
    local k = slot .. ":" .. skin
    if not M.skin.said[k] then
        M.skin.said[k] = true
        log(string.format("coop: player %d's skin %s isn't installed here: their plane's default paint", slot + 1, skin))
    end
    return "-1" .. rest
end

---------------------------------------------------------------------------------------------------- what the others see
-- (0.73.80, finding coop7) What the others see your plane as, by this game's settings (each game decides by its own
-- [coop]; the shipped ones agree): nil when it's your own airframe, else its name, how, and true when those with its
-- add-on see the real thing (your class path is sent, or [coop.real_paths] lists it). The host's own Falken was an F-16C
-- to everyone and only its log said so ("isn't in [coop] airframes"); now each player sees it on screen once a level
-- (M.seenAsTick), and the log has it.
function M.seenAs(code, cls, base)
    if type(code) ~= "string" then return nil end
    local c = cfg()
    local row = tostring(type(c.airframes) == "table" and c.airframes[code] or c.default)
    local ai = (row:match("^(%w+)_") or row):upper()
    if c.real_planes == true then
        if COOP.planeClassPath(code) then return nil end
        local fb, how = M.fallbackFor(code, base)
        if how == "their game's base" then how = "its stock base" end
        local own = M.clsOk(cls, code) or M.modClassPath(code) ~= nil
        if fb and own then
            return string.upper(fb), "itself where its add-on is installed, else a real " .. fb .. " (" .. how .. ")", true
        end
        if fb then return string.upper(fb), "a real " .. fb .. " (" .. how .. ")" end
        if own then return "AN AI " .. ai, "itself where its add-on is installed, else an AI stand-in on " .. row, true end
    elseif type(c.airframes) == "table" and c.airframes[code] then
        return nil
    end
    return ai .. " (AI)", "an AI stand-in on " .. row
end
function M.seenAsTick(code)
    if not (D and code) or (M.seenAsD == D and M.seenAsCode == code) then return end
    M.seenAsD, M.seenAsCode = D, code
    local cls, base = M.myPlane(nil, code)
    local as, how, withMod = M.seenAs(code, cls, base)
    if not as then return end
    local mine = M.myAircraft and M.myAircraft() or ""
    mine = (mine ~= "" and mine or code):upper()
    log(string.format("coop: the other players see your %s (%s) as %s, by this game's settings (theirs decide there)", mine, code, how))
    callout(withMod and ("OTHERS SEE YOUR " .. mine .. " (" .. as .. " WITHOUT THE ADD-ON)") or ("OTHERS SEE YOUR " .. mine .. " AS " .. as), nil)
end
end

local function spawnReal(slot, P, code, lo, pt, r0)
    if walkHold and walkHold() then return nil, "the walks are held (a level going away)" end   -- (0.73.73: a held search could orphan it)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return nil, "you have no plane here yet" end
    -- ((0.73.80) its stock blueprint; else their own (the path their game sent, [coop.real_paths]) if installed here; else
    -- a stock fallback with its own weapons and paint: M.realClassFor)
    local okC, cls, path, fb, how = pcall(M.realClassFor, slot, code, r0)
    if not okC then return nil, "its class: error " .. tostring(cls) end
    if cls == false then return nil, path end            -- (no blueprint here and no fallback: path is why)
    if not (cls ~= nil and valid(cls)) then return nil, "its class didn't load (" .. tostring(path) .. ")" end
    if fb then lo, pt = "", "" end
    pt = cfg().real_paint ~= false and pt or ""
    if pt ~= "" then pt = M.paintHere(slot, pt) end      -- ((0.73.80) a skin this game hasn't: the plane's default)
    P.paintGiven = pt
    local at, yaw = P.at, (P.rot and P.rot[2]) or 0
    -- ((0.73.77) SV_CoopSpawnPP destroys the plane the runtime keeps in this slot: a set-aside one moved on first, M.nativeFree)
    local okF, whyF = M.nativeFree(slot)
    if not okF then return nil, whyF end
    local a = SV_CoopSpawnPP(addrOf(pawn), at.X, at.Y, at.Z, yaw, addrOf(cls), slot, lo or "", pt)
    if type(a) ~= "number" or a <= 0 then return nil, "SV_CoopSpawnPP " .. tostring(a) end
    for _, x in ipairs(FindAllOf("LivePlayerPlane") or {}) do
        if valid(x) and addrOf(x) == a then return x, nil, fb, how end
    end
    return nil, "spawned (" .. tostring(a) .. ") but not found"
end

---------------------------------------------------------------------------------------------------- a rejoin in another aircraft
-- (0.73.77, plan workstream C) A player who left (their link let go: "sys|left" on the host, its "po" on the joiners) or
-- whose game started a new session ("sys|restart" on the host, its "rj" on the joiners) and is back in another aircraft
-- (or with other weapons) gets a new plane here. Shake Shack's run of 2026-11-02: liljojofett left in a Su-47 and came
-- back 18 s later in a Rafale M, and everyone saw the Su-47 to the end of the level ("player 2's loadout changed: their
-- real plane here keeps the one it was spawned with"). A live player plane is still never destroyed mid-level (0.73.11's
-- crash, a frame after a replaced real plane was freed): the old one is set aside (M.setAside: unbound, hidden, collision
-- and tick off, moved up out of the fight, as host migration's) and the new one spawned as a newcomer's. SV_CoopSpawnPP
-- destroys what the runtime keeps in the slot it's given (coop.c), so a set-aside real plane is moved out of its
-- player's slot into one no player has (SV_CoopSwapPP; M.parkAt) and on again before a plane is spawned there. An AI
-- stand-in can't change airframe once up, nor its unit spawn again while it's up: the new one flies a free stand-in unit
-- (M.standInUnit; M.unitSlot maps it back to its player). A change by a player who never left keeps the rule: their
-- plane here keeps its weapons until the next level. CFG.coop.rejoin.
do
M.left, M.aside, M.parkAt, M.standUnit, M.unitSlot, M.asideUnit = {}, {}, {}, {}, {}, {}
M.radarSt = {}                                       -- ((0.73.83) planes taken off the radar here, by address: { obj, was })
local function rejoinCfg() return cfg().rejoin or {} end
-- ((0.73.83) the user, 2026-11-04: "people who leave and rejoin, their plane disappears correctly but not their radar
-- blip") SetActorHiddenInGame hides a plane's meshes, not its minimap icon: the radar draws the game's objects hidden or
-- not, at their map position, and a set-aside plane moved straight up kept its blip where it was (Saint Alessia's 0.73.81
-- run: player 2's F-22A set aside at 12:57:23). A plane hidden here (left, out of the mission, DOWN, waiting for a
-- rejoin's airframe, set aside) is taken off the radar too: deactivated (LiveGameObject.bIsActivated, the game's own
-- active flag, false while it's hidden, put back as it was when it's shown), and a set-aside one, never shown again, also
-- moved aside_far_km off the map. Which of the two the radar heeds isn't known yet: the log says what each did.
-- [coop.rejoin] radar_off = false leaves the flag alone. What to put back is kept by the plane's address (M.radarSt),
-- not on the player's table: that's made again on a new run, a slot move and a joiner's rebuild, and a plane whose state
-- was lost would stay off the radar once shown.
-- (UE4SS may give two Lua objects for one game object, and a freed plane's address can come round again for another
-- object: an entry is this plane's while the object at its address is live and still has the name it was made with, as
-- M.objsOf's prune checks; one that isn't is dropped)
local function radarKey(o) return addrOf(o) or o end
local function sameObj(e, o) return o ~= nil and live(o) and e.name ~= nil and nameOf(o) == e.name end
M.sameObj = sameObj
function M.radarOff(P)
    local o = P and P.obj
    if not (o and live(o)) then return "no plane" end
    local a = radarKey(o)
    local st = M.radarSt[a]
    if st and not sameObj(st, o) then M.radarSt[a], st = nil, nil end
    if rejoinCfg().radar_off == false and not st then return nil end
    local was, now
    pcall(function() was = o.bIsActivated end)
    if st then                                       -- (off already: off again if the game put it back on, its first state kept)
        if was == false then return "off the radar already" end
        pcall(function() o.bIsActivated = false end)
        return "off the radar again (the game had put it back on)"
    end
    local okW = pcall(function() o.bIsActivated = false end)
    pcall(function() now = o.bIsActivated end)
    M.radarSt[a] = { obj = o, was = was, name = nameOf(o) }
    if okW and now == false then return "off the radar (deactivated)" end
    return "NOT deactivated (bIsActivated " .. tostring(now) .. ")"
end
function M.radarOn(P)
    local o = P and P.obj
    if not o then return nil end
    local a = radarKey(o)
    local st = M.radarSt[a]
    if not st then return nil end
    M.radarSt[a] = nil
    if not sameObj(st, o) then return nil end
    if st.was == false then return "on the radar as it was (it was deactivated before)" end
    local okW = pcall(function() o.bIsActivated = true end)
    return okW and "on the radar again (activated)" or "NOT activated again"
end
-- a slot no player has in the runtime (nor this game, nor a plane kept there), the highest first (the host gives the
-- lowest free one to a newcomer)
local function freeNative(but)
    for t = MAX_SLOT, 0, -1 do
        if t ~= but and t ~= COOP.slot and not M.roster[t] and not (M.peers[t] and M.peers[t].obj) and not M.parkAt[t] then return t end
    end
    return nil
end
-- (spawnReal, before SV_CoopSpawnPP for `slot`) a set-aside plane the runtime keeps in that slot moved to a free one.
-- false, why when it can't be (SV_CoopSpawnPP would destroy it: no real plane spawned, the AI stand-in instead)
function M.nativeFree(slot)
    local e = M.parkAt[slot]
    if not e then return true end
    if not live(e.obj) then M.parkAt[slot] = nil; return true end         -- (gone with its level: nothing to destroy)
    local t = type(SV_CoopSwapPP) == "function" and freeNative(slot) or nil
    if not t then return false, "a set-aside plane is kept in its slot and no other slot is free" end
    SV_CoopSwapPP(slot, t)
    M.parkAt[slot], M.parkAt[t], e.slot = nil, e, t
    log(string.format("coop: a set-aside plane kept in slot %d moved to slot %d (player %d's new plane spawns there)",
        slot + 1, t + 1, slot + 1))
    return true
end
-- (M.slotFix's SV_CoopSwapPP(a, b): player slots a and b trade planes) the set-aside planes the runtime keeps in either
-- slot go with the swap, and a rejoin's mark goes with its player
function M.slotSwapped(a, b)
    M.parkAt[a], M.parkAt[b] = M.parkAt[b], M.parkAt[a]
    if M.parkAt[a] then M.parkAt[a].slot = a end
    if M.parkAt[b] then M.parkAt[b].slot = b end
    M.left[a], M.left[b] = M.left[b], M.left[a]
end
-- player `slot`'s plane here (P) set aside, never destroyed: unbound, hidden, collision and tick off, moved up out of the
-- fight (aside_alt_km); a real one moved out of its player's slot in the runtime (kept where it is, and moved before
-- that slot's next real plane spawns, when no other slot is free), an AI stand-in's unit never flown again. M.peers[slot]
-- is the caller's.
function M.setAside(slot, P, why)
    local o = P and P.obj
    if not (o and live(o)) then return false end
    M.gunOff(P)                                          -- ((review of 0.73.80) its gun's trigger let go: nothing drives it from here on)
    if type(SV_CoopPeer) == "function" then SV_CoopPeer(slot, 0) end
    local kept
    if P.real then
        local t = type(SV_CoopSwapPP) == "function" and freeNative(slot) or nil
        if t then
            SV_CoopSwapPP(slot, t)                       -- (t keeps nothing: freeNative; slot's plane is this one)
            M.parkAt[t] = { obj = o, slot = t, from = slot }
            kept = string.format("kept in slot %d", t + 1)
        else
            M.parkAt[slot] = { obj = o, slot = slot, from = slot }
            kept = "kept in its slot (no other free: moved before a new plane spawns there)"
        end
    else
        local u = P.unit or PEER_UNITS[slot]
        M.asideUnit[u] = true
        if M.unitSlot[u] then M.unitSlot[u] = nil end
        if M.standUnit[slot] == u then M.standUnit[slot] = nil end
        kept = "its unit " .. u .. " not flown again"
    end
    pcall(function() o:SetActorHiddenInGame(true) end)
    pcall(function() o:SetActorEnableCollision(false) end)
    local okT = pcall(function() o:SetActorTickEnabled(false) end)
    local radar = M.radarOff(P)
    local alt = tonumber(rejoinCfg().aside_alt_km) or 30
    local far = tonumber(rejoinCfg().aside_far_km) or 1000
    local okM, at = false, nil
    if alt > 0 or far > 0 then
        okM = pcall(function()
            local v = o:K2_GetActorLocation()
            local to = { X = v.X, Y = v.Y, Z = alt > 0 and alt * 100000 or v.Z }
            if far > 0 then to.X, to.Y = far * 100000, (#M.aside + 1) * 2000000 end   -- (off the map, 20 km apart)
            o:K2_SetActorLocation(to, false, {}, true)
            at = to
        end)
    end
    M.aside[#M.aside + 1] = { obj = o, slot = slot, real = P.real, unit = (not P.real) and (P.unit or PEER_UNITS[slot]) or nil,
                              at = okM and at or nil, radar = radar ~= nil and radar ~= "no plane", name = nameOf(o) }
    local where = "left where it is"
    if okM then
        where = alt > 0 and string.format("moved %.0f km up", alt) or "moved"
        if far > 0 then where = where .. string.format(" and %.0f km off the map", far) end
    elseif alt > 0 or far > 0 then
        where = "NOT moved"
    end
    log(string.format("coop: player %d's plane here set aside, hidden (%s): %s, tick %s, %s%s", slot + 1, why, kept,
        okT and "off" or "NOT off", where, radar and ("; " .. radar) or ""))
    return true
end
-- (COOP.tick, every 5 s) each set-aside plane kept off the radar: deactivated again and moved back off the map when the
-- game (a restart in the same level, a checkpoint) has put it back; said once a plane
function M.asideTick(now)
    if #M.aside == 0 or now < (M.asideAt or 0) then return end
    M.asideAt = now + 5
    local keep = {}
    for _, e in ipairs(M.aside) do
        local o = e.obj
        if sameObj(e, o) then keep[#keep + 1] = e end   -- (a plane gone, or its address another object's now: dropped, never touched)
        if keep[#keep] == e then
            if e.radar then
                local act
                pcall(function() act = o.bIsActivated end)
                if act == true then
                    pcall(function() o.bIsActivated = false end)
                    e.reAct = (e.reAct or 0) + 1
                    if e.reAct == 1 then
                        log(string.format("coop: player %d's set-aside plane was activated again (by the game): deactivated again", e.slot + 1))
                    end
                end
            end
            if e.at then
                local v
                pcall(function() v = o:K2_GetActorLocation() end)
                if v and (math.abs(v.X - e.at.X) > 100000 or math.abs(v.Y - e.at.Y) > 100000 or math.abs(v.Z - e.at.Z) > 100000) then
                    pcall(function() o:K2_SetActorLocation(e.at, false, {}, true) end)
                    e.reMove = (e.reMove or 0) + 1
                    if e.reMove == 1 then
                        log(string.format("coop: player %d's set-aside plane was moved back (by the game, %.0f km from its spot): moved off the map again",
                            e.slot + 1, math.sqrt((v.X - e.at.X) ^ 2 + (v.Y - e.at.Y) ^ 2 + (v.Z - e.at.Z) ^ 2) / 100000))
                    end
                end
            end
        elseif e.unit and M.asideUnit then
            M.asideUnit[e.unit] = nil
        end
    end
    M.aside = keep
end
-- (at a new level here) the set-aside planes gone with their level let go; a restart in the same level keeps them
function M.asidePrune()
    local keep = {}
    for _, e in ipairs(M.aside) do
        if (e.name and sameObj(e, e.obj)) or (not e.name and live(e.obj)) then keep[#keep + 1] = e
        elseif e.unit then M.asideUnit[e.unit] = nil end
    end
    M.aside = keep
    for t, e in pairs(M.parkAt) do if not live(e.obj) then M.parkAt[t] = nil end end
    for a, st in pairs(M.radarSt) do if not sameObj(st, st.obj) then M.radarSt[a] = nil end end   -- ((0.73.83) gone with their level)
end
-- whether stand-in unit u is set aside or flown for a player other than `slot`
local function unitTaken(u, slot)
    if M.asideUnit[u] then return true end
    if M.unitSlot[u] ~= nil and M.unitSlot[u] ~= slot then return true end
    for t, Q in pairs(M.peers) do
        if t ~= slot and Q.obj and not Q.real and (Q.unit or PEER_UNITS[t]) == u then return true end
    end
    return false
end
-- the stand-in unit player `slot`'s AI plane flies here: their own (SV_Unit_CoopPeer<A-X>), else (it's set aside, or
-- another player's) a free one: this game's own slot's (never flown here), then the highest slots nobody has. nil: none
function M.standInUnit(slot)
    local cur = M.standUnit[slot]
    if cur and not unitTaken(cur, slot) then return cur end
    M.standUnit[slot] = nil
    local own = PEER_UNITS[slot]
    if not unitTaken(own, slot) then return own end
    local order = {}
    if COOP.slot and COOP.slot ~= slot then order[1] = COOP.slot end
    for t = MAX_SLOT, 0, -1 do if t ~= slot and t ~= COOP.slot and not M.roster[t] then order[#order + 1] = t end end
    for _, t in ipairs(order) do
        local u = PEER_UNITS[t]
        if not unitTaken(u, slot) and not (type(SV_UnitAlive) == "function" and (tonumber(SV_UnitAlive(u)) or 0) > 0) then
            M.standUnit[slot], M.unitSlot[u] = u, slot
            log(string.format("coop: player %d's stand-in flies %s here (theirs, %s, is set aside or another player's)", slot + 1, u, own))
            return u
        end
    end
    once("standin" .. slot, string.format("coop: player %d's stand-in: no free stand-in unit here (theirs, %s, is set aside)", slot + 1, own))
    return nil
end
-- (on the host: "sys|left", "sys|restart"; on a joiner: the host's "po" / "rj") player `slot` may come back in another
-- aircraft: marked until they're back in the mission
function M.markLeft(slot, why)
    if not slotOk(slot) or slot == COOP.slot then return end
    if rejoinCfg().enabled == false then return end
    M.left[slot] = { at = os.clock(), why = why }
    local P = M.peers[slot]
    if P and P.obj then
        log(string.format("coop: player %d %s: if they're back in another aircraft, their plane here (%s) is set aside and a "
            .. "new one spawned", slot + 1, why, tostring(P.real and P.code or P.row or "?")))
    end
end
-- (peerTick, a player marked by M.markLeft) -> their P (a new one once the old plane's set aside: spawned below as a
-- newcomer's) and whether their old plane stays hidden meanwhile (back in the mission, their airframe not heard of yet:
-- up to wait_s)
function M.rejoinTick(slot, P, r0, code, lo, fresh)
    local rj = M.left[slot]
    if not rj then return P, false end
    if not (P.obj and live(P.obj)) then M.left[slot] = nil; return P, false end   -- (no plane here: theirs comes as anyone's)
    if not fresh then rj.freshAt = nil; return P, false end                       -- (not back yet: hidden as ever)
    rj.freshAt = rj.freshAt or os.clock()
    local known = r0 ~= nil and (code ~= nil or (type(r0.row) == "string" and r0.row ~= ""))
    if not known then
        local wait = tonumber(rejoinCfg().wait_s) or 10
        if os.clock() - rj.freshAt < wait then return P, true end
        M.left[slot] = nil
        log(string.format("coop: player %d is back, no airframe heard from them in %d s: their plane here kept", slot + 1, wait))
        return P, false
    end
    M.left[slot] = nil
    local wantReal = realOn() and code ~= nil and P.realFailed == nil
    local old = P.real and (P.code or "?") or (P.row or "?")
    local differs, new
    if P.real then
        differs = not wantReal or code ~= P.code or (lo ~= "" and lo ~= (P.lo or ""))
        new = wantReal and (code == P.code and (code .. " with other weapons") or code) or standInRow(r0.row)
    else
        new = wantReal and code or standInRow(r0.row)
        differs = wantReal or new ~= P.row
    end
    if not differs then
        log(string.format("coop: player %d is back in the same %s: their plane here kept", slot + 1, old))
        return P, false
    end
    M.setAside(slot, P, "they rejoined in another aircraft")
    local nP = { at = P.at, rot = P.rot, hp = P.hp, maxHp = P.maxHp, flags = P.flags, age = P.age, hpPct = P.hpPct, down = P.down,
                 alive = P.alive, onAirfield = P.onAirfield, fresh = P.fresh, freshAt = P.freshAt, sid = r0.sid,
                 rejoin = { from = old, to = new } }
    M.peers[slot] = nP
    return nP, false
end
-- (peerTick, their new plane spawned or not) the rejoin's line, once
function M.rejoinSaid(slot, P, what)
    local rj = P and P.rejoin
    if not rj then return end
    P.rejoin = nil
    log(string.format("coop: player %d rejoined in %s (was %s): old plane set aside, %s", slot + 1, tostring(rj.to), tostring(rj.from), what))
end
end

local function peerTick(slot)
    local s = type(SV_CoopPeerAt) == "function" and SV_CoopPeerAt(slot) or ""
    local f = {}
    for v in s:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
    local fresh = #f >= 10 and f[10] < 3000 and (math.floor(f[9]) % 2 == 1)        -- (flag 1: in Survival's level)
    local P = M.peers[slot] or {}
    M.peers[slot] = P
    -- what that player's game says of them, kept for COOP.players(): position (cm), rotation, health (x 10) and full
    -- health, flags (1 in Survival's level, 2 alive, 4 down at the airfield, 8 DOWN: shot down and waiting for a revive,
    -- sv_down.lua; the sync's 16-128) and its age (ms)
    if #f >= 10 and finite(f[1], 1e10) and finite(f[2], 1e10) and finite(f[3], 1e10) and finite(f[10], 1e9) then
        local fl = finite(f[9], 1e6) and math.floor(f[9]) or 0
        P.at, P.rot = { X = f[1], Y = f[2], Z = f[3] }, { f[4], f[5], f[6] }
        P.hp, P.maxHp, P.flags, P.age = f[7], f[8], fl, f[10]
        P.hpPct = (finite(f[7], 1e12) and finite(f[8], 1e9) and f[8] > 0) and math.max(0, math.min(100, f[7] / 10 / f[8] * 100)) or nil
        P.down = fl % 16 >= 8
        P.alive, P.onAirfield, P.fresh = fl % 4 >= 2 and not P.down, fl % 8 >= 4, fl % 2 == 1 and f[10] < 1000
        if f[10] >= 0 then M.stateAt[slot] = os.clock() - f[10] / 1000 end   -- ((0.73.80) their last state, when: M.noteLost)
    else
        P.at, P.fresh, P.down = nil, false, nil
    end
    if P.fresh then M.freshAt[slot] = os.clock() end                         -- ((0.73.80) last seen in the mission)
    if not D then return end
    if P.obj and not valid(P.obj) then P.obj, P.addr, P.real = nil, nil, nil end
    local unit = PEER_UNITS[slot]
    -- Their airframe comes in their "hi" (or the host's "pi") once their plane is up, and their state can come first:
    -- the stand-in spawned on the empty row of their main-menu "hi" flew the default, F-16C, for the whole run (the
    -- user's co-op run of 2026-10-29: "players are flying F-16's on my side but different aircraft on their side"; an
    -- AI plane up can't change airframe). So it waits up to AIRFRAME_WAIT_S for a row, then flies the default.
    P.freshAt = fresh and (P.freshAt or os.clock()) or nil
    local r0 = M.roster[slot]
    -- (whose plane it is: their Steam ID, so it moves with them to another slot, host migration: M.slotFix)
    if P.obj and not P.sid and r0 and r0.sid then P.sid = r0.sid end
    local known = r0 and type(r0.row) == "string" and r0.row ~= ""
    local code = r0 and r0.code ~= "" and r0.code or nil
    if P.realFailed and P.realFailed ~= code then P.realFailed = nil end        -- (another airframe: try again)
    local lo = r0 and r0.lo or ""
    -- ((0.73.77, plan C) back after leaving, in another aircraft: their old plane set aside, a new P spawned below)
    local hold = false
    if M.left[slot] then P, hold = M.rejoinTick(slot, P, r0, code, lo, fresh) end
    -- (new weapons mid-level: their real plane here keeps the loadout it was spawned with. Replacing a live real plane
    -- crashed the game: the user's co-op run of 2026-10-30, 21:37:39, an access violation reading the destroyed plane a
    -- frame on, some game system still holding it; so it's never destroyed mid-level, and the next level's has them)
    if P.real and P.obj and lo ~= "" and lo ~= (P.lo or "") and P.loSaid ~= lo and not M.left[slot] then
        P.loSaid = lo
        log(string.format("coop: player %d's loadout changed: their real plane here keeps the one it was spawned with "
            .. "(the next level's has the new one)", slot + 1))
    end
    if fresh and not P.obj and not P.spawning and levelReady() and realOn() and code and P.realFailed == nil then
        local o, why, fb, how = spawnReal(slot, P, code, lo, r0 and r0.paint or "", r0)
        if o then
            P.obj, P.addr, P.real, P.code, P.shown, P.lo, P.hpShown = o, addrOf(o), true, code, nil, lo, nil
            P.fallback = fb                                  -- ((0.73.80) another airframe shown for theirs, or nil)
            -- (their name under ALLY in its target box: the callsign line, runtime 0.32.2; the AI stand-ins' own way,
            -- SV_CoopName_<A-X>, doesn't reach a player plane)
            if type(SV_PPName) == "function" and P.addr then
                local acn = (r0 and r0.ac and r0.ac ~= "") and r0.ac or string.upper(code or "")
                local okN, rn = pcall(SV_PPName, P.addr, playerName(slot), acn)
                P.acShown = (okN and rn == 1) and acn or nil
                log(string.format("coop: player %d's name on their real plane's box: %s", slot + 1,
                    (okN and rn == 1) and (playerName(slot) .. " (" .. acn .. ")") or ("NOT set (" .. tostring(rn) .. ")")))
            end
            P.gear, P.flare, P.gunNext, P.flareNext, P.gunOn = nil, nil, nil, nil, nil
            P.wk, P.wkSaid, P.burstUntil = nil, nil, nil             -- ((0.73.80) its weapons read again: M.ppKinds)
            if fb then
                log(string.format("coop: player %d's plane is their %s shown as a real %s (a player plane, %X; no blueprint for %s "
                    .. "here: %s): flown by its own update from their stream; its own default loadout and paint "
                    .. "(theirs are another airframe's)", slot + 1, code, fb, P.addr or 0, code, tostring(how)))
            else
                -- ((0.73.80) the paint given: theirs, or with skin -1 when this game hasn't their skin (M.paintHere))
                local pg = P.paintGiven or ""
                local pa = (r0 and r0.paint) or ""
                log(string.format("coop: player %d's plane is their real %s (a player plane, %X%s): flown by its own update from their "
                    .. "stream; %s; %s", slot + 1, code, P.addr or 0, (how and how ~= "stock") and (", " .. how) or "",
                    lo ~= "" and ("their loadout " .. lo) or "its default loadout (none sent)",
                    pa == "" and "its default paint (none sent)" or (pg == pa and ("their paint " .. pa))
                    or (pg ~= "" and ("their paint " .. pa .. " given as " .. pg .. " (their skin isn't installed here)"))
                    or "its default paint ([coop] real_paint off)"))
            end
            M.rejoinSaid(slot, P, "new one spawned (their real plane)")       -- ((0.73.77) plan C's line)
        else
            P.realFailed = code
            log(string.format("coop: player %d's real plane (%s) not spawned: %s; their AI stand-in instead", slot + 1, code,
                tostring(why)))
        end
    end
    -- (no hello from them at all while their plane streams here: the user's co-op run of 2026-10-31, Shazzy's link came
    -- back after the host had dropped them, their game still had itself on the host's roster so never said hello again,
    -- and their plane here flew the default F-16C all level (an AI plane up can't change airframe, and one is never
    -- replaced mid-level). The host asks for it every 3 s, "hq", and the default waits HELLO_WAIT_S then.)
    if r0 then P.helloAsked = nil
    elseif fresh and COOP.host() and os.clock() >= (P.helloAskAt or 0) then
        P.helloAskAt = os.clock() + 3
        sendTo(slot, true, "hq")
        if not P.helloAsked then
            P.helloAsked = true
            log(string.format("coop: player %d's plane streams here but no hello from them: asked for it (hq)", slot + 1))
        end
    end
    local waitS = r0 and AIRFRAME_WAIT_S or HELLO_WAIT_S
    if fresh and not P.obj and not P.spawning and levelReady()                 -- (not while this level loads)
        and (known or os.clock() - P.freshAt >= waitS) then
        local row = standInRow(r0 and r0.row)
        local fly = M.flyRow and M.flyRow(row) or row        -- (its damage-0 copy, <row>_svcp: the sync's)
        unit = M.standInUnit(slot) or unit                   -- ((0.73.77) a free unit while theirs is set aside: plan C4)
        rawSetAircraft(unit, fly)
        spawningUnit = unit
        local r = rawSpawn(unit)
        spawningUnit = nil
        P.spawning, P.row, P.unit = os.clock(), row, unit
        local up = type(r) == "number" and r > 0
        log(string.format("coop: player %d's plane as %s%s: %s", slot + 1, fly,
            known and "" or string.format(" (no %s from them in %d s)", r0 and "airframe" or "hello", waitS),
            up and "spawned" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
        M.rejoinSaid(slot, P, up and ("new one spawned (an AI stand-in, " .. unit .. ")")
            or ("the new one NOT spawned (" .. (SV_ERR[r] or tostring(r)) .. ")"))
    elseif P.spawning and os.clock() - P.spawning > 10 then
        P.spawning = nil                                  -- (it never came: again)
    end
    if P.obj then
        -- (hidden while they're DOWN too, sv_down.lua: flown round their airfield out of the fight, nothing to see or hit)
        -- ((0.73.77) and while a rejoin waits for their airframe: their old plane may not be theirs any more, hold)
        local show = (fresh and not P.down and not hold) and true or false
        if show ~= P.shown then
            P.shown = show
            local radar                                  -- ((0.73.83) off the radar while hidden: M.radarOff)
            if show then radar = M.radarOn(P) end
            pcall(function() P.obj:SetActorHiddenInGame(not show) end)
            pcall(function() P.obj:SetActorEnableCollision(show) end)
            if type(SV_CoopPeer) == "function" then SV_CoopPeer(slot, show and P.addr or 0) end
            if not show then radar = M.radarOff(P) end
            log(string.format("coop: player %d's plane %s%s", slot + 1, show and "shown"
                or (hold and "hidden (back after leaving: waiting for their airframe)")
                or (fresh and "hidden (down)" or "hidden (not in the mission)"), radar and ("; " .. radar) or ""))
        end
        if P.real and valid(P.obj) and P.addr and type(SV_PPName) == "function" then
            local r1 = M.roster[slot]
            local acn = r1 and r1.ac
            if acn and acn ~= "" and acn ~= P.acShown then
                local okN, rn = pcall(SV_PPName, P.addr, playerName(slot), acn)
                if okN and rn == 1 then P.acShown = acn end
            end
        end
        -- (COOP2MP T5: their damage shown on their real plane here, its health as their game says, never under 1 HP: a
        -- real plane is never destroyed mid-level (0.73.12's crash), and hits on it here are refused anyway (hard rule 53);
        -- the field written, not SetMinHealth, which keeps whole points only)
        if P.real and show and valid(P.obj) and type(P.hp) == "number" and type(P.maxHp) == "number" and P.maxHp > 0
            and cfg().real_damage ~= false then
            local want = math.max(10, math.min(math.floor(P.maxHp * 10 + 0.5), math.floor(P.hp + 0.5)))
            if want ~= P.hpShown then
                pcall(function() P.obj.MinHealth = 1.0 end)
                local okH = pcall(function() P.obj.HealthInternal = want end)
                if okH and P.hpShown == nil then
                    log(string.format("coop: player %d's damage shown on their real plane here (health %d%%)", slot + 1,
                        math.floor(want / 10 / P.maxHp * 100 + 0.5)))
                end
                P.hpShown = okH and want or P.hpShown
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- the players, for other parts
-- COOP.players(): every player this game knows the whereabouts of, for the behaviour director (it picks a player slot
-- to aim a tactic at; tools/re/BEHAVIOUR_DIRECTOR.md): a list of { slot, obj, addr, at, hpPct, alive, onAirfield, fresh }
-- (another player's has rot too: pitch, yaw, roll from their game, and age (ms) and inLevel; yours isMe). down: shot down
-- and waiting for a revive (sv_down.lua; alive false then).
-- The local player comes first (your pawn: its position read once a tick, shared with ACE.movesTick through COOP.me();
-- health from HIT.h, its full health read every 5 s), then each other player from what peerTick already keeps of
-- SV_CoopPeerAt every tick (no native call more): obj / addr their stand-in here, fresh when their game's state is under
-- a second old. Solo, or co-op closed: only you (slot 0).
local meCache = {}
local function localPlayer()
    -- (once a tick: the run's clock D.now is set first thing in each tick, by roundsTick; no clock, no keeping)
    local now = D and D.now
    if now ~= nil and meCache.D == D and meCache.now == now then return meCache.e end
    meCache.D, meCache.now = D, now
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then meCache.e = nil; return nil end
    local e = { slot = COOP.slot or 0, obj = pawn, addr = addrOf(pawn), fresh = true, isMe = true }
    pcall(function() local v = pawn:K2_GetActorLocation(); e.at = { X = v.X, Y = v.Y, Z = v.Z } end)
    if meCache.maxAddr ~= e.addr or os.clock() >= (meCache.maxAt or 0) then
        local okM, mh = pcall(function() return pawn.MaxHealth end)
        meCache.max, meCache.maxAddr, meCache.maxAt = (okM and type(mh) == "number" and mh > 0) and mh or nil, e.addr, os.clock() + 5
    end
    local h = HIT and HIT.h
    if type(h) ~= "number" then local okH, v = pcall(function() return pawn.HealthInternal end); h = okH and type(v) == "number" and v or nil end
    e.hpPct = (h and meCache.max) and math.max(0, math.min(100, h / 10 / meCache.max * 100)) or nil
    e.down = DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true          -- (shot down, waiting for a revive: sv_down.lua)
    e.alive = (h == nil or h > 0) and not e.down
    local okA, on = pcall(playerOnAirfield, e.at)
    e.onAirfield = okA and on == true
    meCache.e = e
    return e
end
function COOP.me() return localPlayer() end
-- Sync health (the user's loggers of 2026-10-31): what this game kept of the host's flights and how often the picture
-- was rebuilt, a line a minute from sv_audit.lua (COOP.syncReport): on a joiner its copies (bound to the host's ids or
-- not), the strays taken down, its asks for the whole picture (jn) and the host's answers (rs), the copies it tore down
-- and its teardowns; on the host the joiners' asks it answered. Counted since the last report.
-- ((0.73.77, plan A6) and the floor: copies that went to it (a lethal hit sent, waiting for the host's kill), the longest
-- wait there, those put back up (taken there by something not yours); spawns of the host's refused here, flights unstuck
-- (A3) and by SV_Recycle; the host's health for copies already down here, skipped (A2))
function M.newCnt()
    return { torn = 0, teardowns = 0, strays = 0, jnSent = 0, rsGot = 0, jnGot = 0, repairs = 0,
             floored = 0, floorMax = 0, floorBack = 0, refused = 0, unstuck = 0, recycled = 0, hpDead = 0 }
end
M.cnt = M.newCnt()
function COOP.syncReport()
    local c = M.cnt
    M.cnt = M.newCnt()
    if COOP.host() then
        -- ((0.73.77, economy C1) the run's kills by the player the host named: COOP.killTally)
        local t, parts = COOP.killTally(), {}
        for s = 0, MAX_SLOT do
            local k = t[s]
            if k then parts[#parts + 1] = string.format("player %d %d%s", s + 1, k.air, k.ground > 0 and string.format(" (+%d ground)", k.ground) or "") end
        end
        return string.format("host: %d joiners linked, %d asks for the whole picture answered (rs); the run's kills by player: %s",
            M.linkedPeers or 0, c.jnGot, #parts > 0 and table.concat(parts, ", ") or "none yet")
    end
    local flights, copies, bound = 0, 0, 0
    for _, cu in pairs(M.cunits or {}) do
        flights = flights + 1
        for ord, o in pairs(cu.planes or {}) do
            if valid(o) then
                copies = copies + 1
                if cu.binds and cu.binds[ord] then bound = bound + 1 end
            end
        end
    end
    local now, atFloor, longest = os.clock(), 0, 0
    for _, cp in pairs(M.copies) do
        if cp.floorAt then atFloor = atFloor + 1; longest = math.max(longest, now - cp.floorAt) end
    end
    return string.format("joiner: %d copies of %d flights (%d bound to the host's ids, %d not), %d strays taken down, %d asks "
        .. "for the whole picture (jn), %d answers (rs; %d of them repairs, the copies kept), %d copies torn down in %d teardowns; "
        .. "the floor: %d copies there now waiting for the host's kill (the longest %.1f s), %d went there, their longest wait "
        .. "%.1f s, %d put back up (not your kill), %d your missiles' (0.73.79), %d sent again; %d flights refused here, %d "
        .. "unstuck (%d by SV_Recycle); hp for %d dead copies skipped, %d held after your hit",
        copies, flights, bound, copies - bound, c.strays, c.jnSent, c.rsGot, c.repairs or 0, c.torn, c.teardowns,
        atFloor, longest, c.floored, c.floorMax, c.floorBack, c.floorMsl or 0, c.floorResend or 0, c.refused, c.unstuck,
        c.recycled, c.hpDead, c.hpHeld or 0)
end
-- whether this game tore copies down itself within the last s seconds (and why last): the pay audit's suspect window
function COOP.tornRecently(s)
    return M.tornLast ~= nil and os.clock() - M.tornLast <= (s or 5), M.tornWhy
end
-- ((0.73.77, Workstream B1) the co-op lists kept between ticks, for the perf line's "lists:" (sv_main.lua perfLists):
-- { name, size } pairs, counted only; a list that grows over a long run shows there)
function COOP.sizes()
    if not COOP.open then return {} end
    local function n(t) local k = 0; if type(t) == "table" then for _ in pairs(t) do k = k + 1 end end; return k end
    local objs = 0
    for _, reg in pairs(M.objsOf or {}) do objs = objs + n(reg) end
    return { { "copies", n(M.copies) }, { "flights here", n(M.cunits) }, { "objects", objs }, { "ids", n(M.byId) },
             { "flights", n(M.units) }, { "dead ids", n(M.dead) }, { "torn", n(M.torn) }, { "down", n(M.downAt) },
             { "strays watched", n(M.strayFirst) }, { "players", n(M.peers) } }
end

function COOP.players()
    local out = {}
    local e = localPlayer()
    if e then out[1] = e end
    if not COOP.open then return out end
    for s = 0, MAX_SLOT do
        local P = M.peers[s]
        if s ~= COOP.slot and P and P.at then
            out[#out + 1] = { slot = s, obj = P.obj, addr = P.addr, at = P.at, hpPct = P.hpPct, alive = P.alive,
                              onAirfield = P.onAirfield, fresh = P.fresh, rot = P.rot,      -- (rot: pitch, yaw, roll)
                              down = P.down, age = P.age, inLevel = (P.flags or 0) % 2 == 1 }   -- (sv_down.lua's)
        end
    end
    return out
end
-- The player slot whose plane is at addr here (your pawn, or another player's stand-in), or nil: kills and damage by
-- player on the host (hostHit's causer is the joiner's stand-in)
function COOP.slotOfAddr(addr)
    if not addr then return nil end
    local e = localPlayer()
    if e and e.addr == addr then return e.slot end
    for s, P in pairs(M.peers) do if P.addr and P.addr == addr then return s end end
    return nil
end
-- For sv_down.lua (revives, the spectator camera): a reliable message to slot `to` (nil: everyone; a joiner's all go to
-- the host), a player's name, a slot's check, how many other games are linked, what this game keeps of another player
-- (peerTick's P), and the other players' planes here to watch (shown, their state fresh, not DOWN), in slot order
function COOP.msg(to, ...)
    -- ((0.73.77, plan A9) the host's run-over to everyone (sv_down.lua: every player down) is kept for this level: a
    -- player who links or links back later gets it with the host's picture, hostSync)
    local kind, a1 = ...
    if kind == "ro" and to == nil and COOP.host() and not M.ro then M.ro = { round = a1, at = os.clock() } end
    return sendTo(to, true, ...)
end
function COOP.name(slot) return playerName(slot) end
COOP.slotOk = slotOk
function COOP.linked() return COOP.open and (M.linkedPeers or 0) or 0 end
function COOP.peerInfo(slot) return M.peers[slot] end
-- (the host, COOP2MP T3) a flight onto one player's real plane: Normal, that plane, TargetFirst (theirs alone; hard rule
-- 53: Survival's orders name "Player", your plane, and the stock hunt only finds AI planes), the stock order's fire
-- bits, on each of its planes up. slot's plane if it's shown here, else the shown real plane the fewest flights are on.
-- -> true, slot, planes ordered; false if none. COOP.huntHost: the flight back on you (PlayerOnlyNoLimit, as it came).
local ORDER_NORMAL, PRIO_PLAYER_ONLY_NO_LIMIT, PRIO_TARGET_FIRST, FIRE_BITS = 0, 8, 9, 7
-- (not a player down at their airfield, nor one DOWN: the user's co-op run of 2026-10-30, a flight sent onto Alessia's
-- real plane as she sat in the STORE, shooting it on the runway here 5 times while she bought a revive)
local function realTarget(s)
    local P = M.peers[s]
    return (s ~= COOP.slot and P and P.real and P.shown and P.obj and valid(P.obj) and not P.onAirfield and not P.down)
        and P.obj or nil
end
COOP.realTarget = realTarget
-- (the host) the players linked but not in the mission yet (loading, the hangar, a link lost), each held for at most
-- [coop] join_wait_s from when it was first seen out: their names, or nil. The user, 2026-10-30: "is there a way that
-- we can effectively pause enemy spawns while people are joining the lobby?" (a joiner still loading when the round's
-- flights came got only 1 of 4 binds: the desync)
-- (0.73.80, the 31-round test's finding errors2) A player whose link was lost while they were in the mission (a quit, a
-- crash, a game closed: their last state in the mission within LOST_FRESH_S of their last packet) holds the round only
-- [coop] hold_lost_s after that last state: the host held its spawns 50-80 s for players who had gone (Amia 19:44:50 to
-- 19:45:40, Shazzy 20:38:31 to 20:39:51, dukka until the host left; only the native drop's sys|left, 90 s after their
-- last packet, ended it), since nothing comes from a game that quits or closes. A link lost while they weren't in the
-- mission (loading in: Amia's was lost 26-27 s twice while she loaded) keeps the hold up to join_wait_s, as before. Each
-- player's hold logged as it starts and as it ends, with how long and why.
do
local LOST_FRESH_S = 5
local function lostS() return tonumber(cfg().hold_lost_s) or 15 end
function M.noteLost(s)                                   -- (the host, on sys|lost from s)
    local now = os.clock()
    local sa, fa = M.stateAt[s], M.freshAt[s]
    local inMission = sa ~= nil and fa ~= nil and fa >= sa - LOST_FRESH_S
    M.lostAt[s] = { at = now, from = sa or now, inMission = inMission }
    log(string.format("coop: player %d's link lost %s", s + 1, inMission
        and string.format("in the mission (their last state %.0f s ago): they hold the round %s", now - (sa or now), lostS() >= 0
            and string.format("%d s after it at most ([coop] hold_lost_s)", lostS()) or "up to [coop] join_wait_s (hold_lost_s -1)")
        or string.format("while not in the mission (%s): they hold the round up to [coop] join_wait_s", fa
            and string.format("last in it %.0f s ago", now - fa) or "not seen in it here")))
end
local function holdEnd(s, why)
    local h = M.holding[s]
    if not h then return end
    M.holding[s] = nil
    log(string.format("coop: %s no longer holds the round: %s (held %.0f s; %s)", h.name, why, os.clock() - h.at, h.why))
end
function COOP.joinWaiting(now)
    if not (COOP.open and COOP.host and COOP.host()) then return nil end
    local cap = tonumber(cfg().join_wait_s) or 90
    if cap <= 0 then return nil end
    M.outSince = M.outSince or {}
    local names, ls, roster = nil, lostS(), M.roster or {}
    for s in pairs(roster) do
        if s ~= COOP.slot then
            local P = M.peers[s]
            local li = M.lostAt[s]
            if P and P.fresh then
                M.outSince[s] = nil
                holdEnd(s, "in the mission")
            else
                M.outSince[s] = M.outSince[s] or now
                if li and li.inMission and ls >= 0 and os.clock() - li.from >= ls then
                    holdEnd(s, string.format("their link was lost in the mission, nothing from them for %.0f s ([coop] hold_lost_s %d)",
                        os.clock() - li.from, ls))
                elseif now - M.outSince[s] < cap then
                    names = names or {}; names[#names + 1] = playerName(s)
                    local why = li and (li.inMission and "their link lost in the mission" or "their link lost while not in the mission")
                        or "not in the mission yet"
                    local h = M.holding[s]
                    if not h then
                        M.holding[s] = { at = os.clock(), name = playerName(s), why = why }
                        log(string.format("coop: the round waits for %s (%s), %s", playerName(s), why, (li and li.inMission and ls >= 0)
                            and string.format("up to %d s after their last state", ls) or string.format("up to %d s", cap)))
                    else
                        h.why = why
                    end
                else
                    holdEnd(s, string.format("[coop] join_wait_s %d s out of the mission", cap))
                end
            end
        end
    end
    for s in pairs(M.outSince) do if not roster[s] then M.outSince[s] = nil end end
    for s in pairs(M.holding) do if not roster[s] then holdEnd(s, "gone from the room") end end
    for s in pairs(M.lostAt) do if not roster[s] then M.lostAt[s] = nil end end
    -- (a host by migration: the old room's players not back yet, by their Steam IDs, for up to [coop.migration] wait_s)
    local mg, mc = M.mig, cfg().migration or {}
    if mg and mg.hosting and mg.expect and os.clock() - (mg.hostAt or 0) < (tonumber(mc.wait_s) or 60) then
        for sid, nm in pairs(mg.expect) do
            local back = false
            for _, r in pairs(M.roster or {}) do if r.sid == sid then back = true end end
            if not back then names = names or {}; names[#names + 1] = nm end
        end
    end
    return names
end
end
function COOP.anyReal()
    for s = 0, MAX_SLOT do if realTarget(s) then return true end end
    return false
end
local function orderFlight(unit, target, prio)
    local u, n = M.units[unit], 0
    if not (u and valid(target)) then return 0 end
    for i = 1, u.n or 0 do
        local b = u.planes[i] and M.byId[u.planes[i].id]
        if b and valid(b.obj) and pcall(function() b.obj:EngagementOrderOverride(ORDER_NORMAL, target, prio, 0, false, FIRE_BITS, false) end) then
            n = n + 1
        end
    end
    return n
end
function COOP.huntReal(unit, slot)
    local u = M.units[unit]
    if not u then return false end
    M.huntOn = M.huntOn or {}
    if slot == nil or not realTarget(slot) then
        local count, best, bestN = {}, nil, nil
        for un, h in pairs(M.huntOn) do if un ~= unit then count[h.slot] = (count[h.slot] or 0) + 1 end end
        for s = 0, MAX_SLOT do
            if realTarget(s) and (best == nil or (count[s] or 0) < bestN) then best, bestN = s, count[s] or 0 end
        end
        slot = best
    end
    local o = slot and realTarget(slot)
    local n = o and orderFlight(unit, o, PRIO_TARGET_FIRST) or 0
    if n == 0 then return false end
    M.huntOn[unit] = { slot = slot, gen = u.gen }
    M.hunted = M.hunted or {}; M.hunted[unit] = u.gen
    return true, slot, n
end
function COOP.huntHost(unit)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if M.huntOn then M.huntOn[unit] = nil end
    return valid(pawn) and orderFlight(unit, pawn, PRIO_PLAYER_ONLY_NO_LIMIT) or 0
end
function COOP.watchable()
    local out = {}
    for s = 0, MAX_SLOT do
        local P = M.peers[s]
        if s ~= COOP.slot and P and P.obj and P.shown and P.fresh and not P.down and valid(P.obj) and P.addr then
            out[#out + 1] = { slot = s, obj = P.obj, addr = P.addr, name = playerName(s) }
        end
    end
    return out
end

---------------------------------------------------------------------------------------------------- weapons, gear, afterburner
-- The other players' planes do what theirs do (user, 2026-10-29, three players on 0.72.0: "can you please work out
-- aircraft syncing, such as missiles being fired", "when allies land at the airfield, their gear doesn't deploy on my
-- screen, nor do I see their afterburners"; tools/re/COOP.md 8). Each game watches its own plane and tells the others,
-- whose stand-in of it (SV_Unit_CoopPeer<A-X>) does the same there:
--   missiles     the pawn's FiredExplosiveWeapons (its missiles in flight; pooled objects, so an address that wasn't in
--                it last tick is a shot, its class the kind, its TargetToHome the target): "fx" to the host, which
--                fires them from the shooter's stand-in and relays them to the others; SV_CoopFire (runtime 0.28.5)
--                fires the stand-in's fire-control slot 2 at that target here (its copy on a joiner), or at none
--   gun          SV_Ammo(0) dropping (read before Survival's own refill: COOP.ammoRead) -> state bit 64 while it does;
--                the others fire the stand-in's gun (slot 1) every GUN_EVERY_S at its target ("fx" g: your target)
--   flares       SV_Ammo(4) dropping -> bit 128; the others fire the stand-in's flares (slot 0) as it comes on
--   electronic   a special weapon's count (SV_Ammo(2) / (3)) dropping with nothing new in flight within ELEC_WAIT_S: an
--                ESM / jamming pod, which fires no projectile (the user's co-op run of 2026-10-30: the EA-18G's ESM
--                "didn't show up for any of us"): "fx" e; the others fire the stand-in's ECM pod (its row's ECM slot)
--   gear         LandingGearOnMesh shown -> bit 16; the others call the stand-in's EnableLandingGear as it flips
--   afterburner  SV_InputNow's throttle at ab_throttle or over -> bit 32; the runtime lights the stand-in's itself
-- Never twice: a stand-in flies its airframe's damage-0 copy (<row>_svcp, COOP.syncSetup), so what it fires here only
-- shows; a joiner takes any stand-in's damage out of what it sends the host anyway (clientTick: the backstop).
-- "fx" (reliable, a tick's shots in one): shooter -> host "fx|<k>:<id>:<age>;..." (k: m a missile, s a special weapon,
-- e an electronic special (ESM / jamming), g the gun's target; id: the target's stream id, 0 none; age: ms since it was
-- seen); host -> the others. COOP2MP T4b (runtime 0.32.0): each launch also as "p:<id>:<age>:<shot>" (the runtime's
-- SV_CoopShots: kind, weapon number, spawn slot, seed, lock-ons, where it left your plane, rotation, velocity), replayed
-- from your real plane in the other games (SV_CoopPPShot); a stand-in there fires m / s / e as before, a real plane p.
-- "fx|<shooter's slot>|..." (never back to the shooter; the host's own as slot 0). Guards: a known slot, not your own;
-- at most FX_PER_S shots a second a shooter and FX_MAX entries a message; a shot older than FX_STALE_MS (its age and
-- half the round trip of each leg) or from a shooter whose state is over a second old dropped; an id not known here
-- fired with no target.
do
local FX_PER_S, FX_MAX, FX_STALE_MS, FLAG_HOLD_S, GUN_EVERY_S, FLARE_EVERY_S = 12, 32, 1500, 0.5, 0.2, 1.0
local P_PER_S = 16                                         -- (a shooter's "p" launches a second, T4b)
-- (a special weapon's count down with nothing new in flight this long after: an electronic one, ESM / jamming)
local ELEC_WAIT_S = 0.45
-- the ECM pod's fire-control slot on a stand-in's airframe row (COOP.syncSetup records each row's: an FCS id with ECM in
-- it, or the pod it adds to the electronic-warfare airframes' copies, whose plain campaign rows carry none)
M.ecmSlot = M.ecmSlot or {}
local BIT_GEAR, BIT_AB, BIT_GUN, BIT_FLARE = 16, 32, 64, 128
local MISSION_TABLE = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"
local S = { seen = {}, kinds = {}, rate = {}, n = { sent = 0, got = 0, fired = 0, failed = 0, dropped = 0, gear = 0, ab = 0 } }
M.fxS = S
local function sc() local s = cfg().sync; return type(s) == "table" and s or {} end
local function bit(flags, b) return type(flags) == "number" and math.floor(flags / b) % 2 == 1 end
local function on(k) local s = sc(); return s.enabled == true and s[k] ~= false end

-- the stream id of the enemy at address a (the host: its own, M.byId; a joiner: its copy of the host's, M.copies), or 0
local function idOfAddr(a)
    if not a then return 0 end
    if COOP.host() then
        for id, e in pairs(M.byId) do if e.addr == a and not e.dead then return id end end
    else
        for id, c in pairs(M.copies) do if c.addr == a then return id end end
    end
    return 0
end
-- the actor here of stream id `id` (the host: its enemy; a joiner: its copy), or nil
local function addrOfId(id)
    if type(id) ~= "number" or id <= 0 then return nil end
    if COOP.host() then
        local e = M.byId[id]
        return e and not e.dead and valid(e.obj) and e.addr or nil
    end
    local c = M.copies[id]
    return c and not M.dead[id] and valid(c.obj) and c.addr or nil
end
-- the stand-ins' damage-0 mission row for airframe row `row`, when it was made before this level loaded
function M.flyRow(row)
    return sc().enabled == true and M.svcpUsable and M.svcpUsable[row] or row
end
-- every other player's stand-in here, by address (the backstop's keys)
function M.standInSet()
    local set = {}
    for s, P in pairs(M.peers) do if s ~= COOP.slot and P.addr then set[P.addr] = s end end
    for _, c in pairs(M.copies) do if c.ally and c.addr then set[c.addr] = -1 end end   -- (the host's allies' copies here:
                                                                                     -- their hits are the host's)
    return set
end
-- what the stand-ins in `set` have done to o so far (its DamageHistoryMap, in health: KILLS_HEALTH_DEATH.md 1)
function M.standInDamage(o, set)
    local sum = 0
    pcall(function()
        o.DamageHistoryMap:ForEach(function(k, v)
            local okK, a = pcall(function() return k:get():GetAddress() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and set[a] and type(x) == "number" and x > 0 then sum = sum + x end
        end)
    end)
    return sum
end
-- (0.73.77, plan A1) one look at copy o's DamageHistoryMap (in health; every hit is added there in full, before the floor
-- clamps its health): what the stand-ins and allies' copies in `set` (may be nil) have done to it, and what your plane
-- (address pa) has, nil when the map couldn't be read. The first time your plane shows up in a copy's map, M.ownSeen:
-- from then on the floor's hits trust it (clientTick)
function M.historyOf(o, set, pa)
    local sum, mine = 0, 0
    local ok = pcall(function()
        o.DamageHistoryMap:ForEach(function(k, v)
            local okK, a = pcall(function() return k:get():GetAddress() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and type(x) == "number" and x > 0 then
                if set and set[a] then sum = sum + x
                elseif pa and a == pa then mine = mine + x end
            end
        end)
    end)
    if ok and mine > 0 and not M.ownSeen then
        M.ownSeen = true
        log("coop: your hits read from the copies' damage maps: a hit the floor clips is sent whole")
    end
    return sum, ok and mine or nil
end

-- your weapon's kind by its class: "m" the standard missile (BP_plwp_msl_*), "s" a special weapon (the stand-ins fire
-- their missile slot 2 for both, for now), false the gun's and the flares' (the state bits carry those)
local function kindOf(w)
    local cls = nameOf(w):match("^(%S+)") or "?"
    local k = S.kinds[cls]
    if k == nil then
        local l = cls:lower()
        if l:find("^bp_plwp_msl") then k = "m"
        elseif l:find("gun", 1, true) or l:find("flr", 1, true) or l:find("flare", 1, true) then k = false
        else k = "s" end
        S.kinds[cls] = k
        log(string.format("coopfire: your weapon %s: %s", cls, k == "m" and "a missile (the stand-ins' slot 2)"
            or k == "s" and "a special weapon (the stand-ins' missile slot 2 for now)" or "not sent (the state bits)"))
    end
    return k
end
-- your missiles in flight against last tick's: the new ones' entries into out ("k:id:0"); the first read after your
-- plane changes only learns what's up already
local function watchShots(pawn, out)
    local okA, arr = pcall(function() return pawn.FiredExplosiveWeapons end)
    if not (okA and arr) then once("fxarr", "coopfire: your plane's FiredExplosiveWeapons can't be read: your missiles aren't sent"); return end
    local list, cur = {}, {}
    local okL = pcall(function() arr:ForEach(function(_, e) list[#list + 1] = e:get() end) end)
    if not okL then once("fxeach", "coopfire: your plane's FiredExplosiveWeapons can't be walked: your missiles aren't sent"); return end
    for _, w in ipairs(list) do
        local a = liveAddr(w)                              -- (hotfix2: not valid(): see sv_core liveAddr)
        if a then
            cur[a] = true
            if S.primed and not S.seen[a] then
                local k = kindOf(w)
                if k then
                    local okT, t = pcall(function() return w.TargetToHome end)
                    local ta = okT and t and liveAddr(t)
                    out[#out + 1] = string.format("%s:%d:0", k, ta and idOfAddr(ta) or 0)
                    if ta then M.shotMark(a, ta) end       -- ((0.73.79) a copy's hit at the floor: M.floorLoss)
                    if k == "s" then S.spShotAt = os.clock() end     -- (a special weapon in flight: not electronic)
                end
            end
        end
    end
    for a in pairs(S.seen) do if not cur[a] then M.shotEnd(a) end end   -- ((0.73.79) gone: it hit, or missed)
    S.seen, S.primed = cur, true
end

-- (sv_main.lua, just before ammoTick: before Survival's own refill) your gun's and flares' counts against what they
-- were after last tick's: a drop away from the airfield is fire
function COOP.ammoRead()
    if not (COOP.open and D and sc().enabled == true and type(SV_Ammo) == "function") then return end
    local now = os.clock()
    if playerOnAirfield() then return end                  -- (a rearm down there)
    local g, f = SV_Ammo(0), SV_Ammo(4)
    if on("guns") and type(g) == "number" and g >= 0 and S.gunLast and g < S.gunLast then
        if not S.gunAt or now - S.gunAt > FLAG_HOLD_S then S.n.bursts = (S.n.bursts or 0) + 1 end
        S.gunAt = now
    end
    if on("flares") and type(f) == "number" and f >= 0 and S.flrLast and f < S.flrLast then
        S.n.flares = (S.n.flares or 0) + 1
        S.flrAt = now
    end
    for k = 2, 3 do                                        -- (the special weapons: an ESM's use shows only here)
        local v = SV_Ammo(k)
        local was = S.spLast and S.spLast[k]
        if on("missiles") and type(v) == "number" and v >= 0 and was and v < was and not S.spDropAt then S.spDropAt = now end
    end
end
-- (COOP.tick, after ammoTick) the counts the next read goes by
local function ammoAfter()
    if type(SV_Ammo) ~= "function" then return end
    local g, f = SV_Ammo(0), SV_Ammo(4)
    S.gunLast = (type(g) == "number" and g >= 0) and g or nil
    S.flrLast = (type(f) == "number" and f >= 0) and f or nil
    S.spLast = {}
    for k = 2, 3 do local v = SV_Ammo(k); S.spLast[k] = (type(v) == "number" and v >= 0) and v or nil end
end

-- this game's state bits for its own plane (SV_CoopMe): 16 gear down, 32 afterburner, 64 gun firing, 128 flares
function M.syncBits(pawn, now)
    if sc().enabled ~= true or not valid(pawn) then return 0 end
    local b = 0
    if on("gear") then
        local down = nil
        pcall(function()
            local comp = pawn.LandingGearOnMesh
            if valid(comp) then local v = comp:IsVisible(); if type(v) == "boolean" then down = v end end
        end)
        if down == nil then once("gearread", "coopfire: your gear can't be read (LandingGearOnMesh): not sent")
        elseif down ~= S.gear then
            S.gear, S.n.gear = down, S.n.gear + 1
            if S.n.gear <= 6 then log("coopfire: your gear " .. (down and "down" or "up") .. " (LandingGearOnMesh " .. (down and "shown" or "hidden") .. ")") end
        end
        if down then b = b + BIT_GEAR end
    end
    if on("afterburner") and type(SV_InputNow) == "function" then
        local okI, s = pcall(SV_InputNow)
        local th = okI and type(s) == "string" and tonumber(s:match("^[^,]*,[^,]*,[^,]*,([^,]*)")) or nil
        if th then
            S.n.thMax = math.max(S.n.thMax or 0, th)              -- (the tally's: what full throttle reads, to calibrate)
            local ab = th / 1000 >= (tonumber(sc().ab_throttle) or 0.9)
            if ab ~= S.ab then
                S.ab, S.n.ab = ab, S.n.ab + 1
                if (S.n.ab <= 4 and logVerbose()) or not S.abSaid then   -- (the first one; up to 4 a minute with [log] verbose)
                    S.abSaid = true
                    log(string.format("coopfire: your throttle %.3f: afterburner %s (ab_throttle %s)", th / 1000,
                        ab and "on" or "off", tostring(sc().ab_throttle)))
                end
            end
            if ab then b = b + BIT_AB end
        else
            once("abread", "coopfire: SV_InputNow gave no throttle (" .. tostring(s) .. "): your afterburner isn't sent")
        end
    end
    if on("guns") and S.gunAt and now - S.gunAt <= FLAG_HOLD_S then b = b + BIT_GUN end
    if on("flares") and S.flrAt and now - S.flrAt <= FLAG_HOLD_S then b = b + BIT_FLARE end
    return b
end

-- a stand-in's fire: player slot's plane here fires fire-control slot fcs at the actor at target (nil: none)
local function standInAddr(slot)
    local P = M.peers[slot]
    return P and P.obj and P.shown and valid(P.obj) and P.addr or nil
end
local FCS_NAME = { [0] = "flares", "gun", "missiles", "ECM pod" }
-- ((review of 0.73.80) your landing STORE open: the music hold's 1 while a landing menu window was on screen at the last
-- look (sv_core.lua LANDW); the hold itself lets go ~2.5 s after it closes (two looks: a late page), the launches here
-- at once (as 0.73.79's hold did)
local function inStore()
    return D and D.musicHold == 1 and not (LANDW and LANDW.wasShown == false)
end
local function coopFire(slot, fcs, target)
    -- (your landing STORE open: the game holds the other planes inactive there and refuses their fire; the co-op run of
    -- 2026-10-30: 1,093 of its 1,094 refused shots came while that game's player was in the STORE)
    if inStore() then S.n.inStore = (S.n.inStore or 0) + 1; return nil end
    local a = standInAddr(slot)
    if not a then S.n.noPlane = (S.n.noPlane or 0) + 1; return nil end
    if M.peers[slot] and M.peers[slot].real then                 -- (a real plane: its launches come as "p", T4b)
        S.n.real = (S.n.real or 0) + 1
        return nil
    end
    if type(SV_CoopFire) ~= "function" then
        once("nofire", "coopfire: dlls/main.dll has no SV_CoopFire (runtime 0.28.5 or later): the other players' fire isn't shown")
        return nil
    end
    local okF, r = pcall(SV_CoopFire, a, fcs, target or 0)
    if not okF then r = tostring(r) end
    if r == 1 then S.n.fired = S.n.fired + 1 else S.n.failed = S.n.failed + 1 end
    local said = r == 1 and "queued" or (SV_ERR[r] and (tostring(r) .. " " .. SV_ERR[r]) or tostring(r))
    once("first" .. slot .. "/" .. fcs, string.format("coopfire: player %d's first %s here (their plane %X, %s): %s", slot + 1,
        FCS_NAME[fcs] or tostring(fcs), a, target and string.format("at %X", target) or "no target", said))
    if r ~= 1 then
        once("fail" .. fcs .. "/" .. tostring(r), string.format("coopfire: SV_CoopFire(player %d's plane, slot %d) refused: %s",
            slot + 1, fcs, said))
    end
    return r
end
local function halfRtt(slot) return math.floor(((M.rtt and M.rtt[slot]) or 100) / 2) end

-- (0.73.80) Weapon stand-ins (the user, 2026-11-04: "Then do the weapon stand-ins next"). A launch whose weapon number
-- their real plane here hasn't, or has as another kind of weapon, is shown as the nearest weapon of the same kind it has
-- instead of being dropped. A player on a weapon mod (SPWeaponCustomizer's extra special slots, AC8WeaponSwap) or in a
-- modded plane shown here on a stock fallback (its own default loadout) fires numbers the plane here hasn't: the runtime
-- refused those ("not a weapon of their plane here", 57-74 a game in the 31-round test of 2026-11-04: Amia's F-22A
-- firing weapon 3, its plane here with weapons 0-2). What the plane here has comes from SV_PPWeapons (runtime 0.32.24):
-- each number -2 not usable, -1 not known yet, 0-4 its kind as seen launched here (0 explosive: missiles and bombs, 1
-- the laser, 2 a bullet special, 3 an electronic one: ESM / ECM, 4 another), 10-14 its launcher table entry's (not
-- verified in the exe: used only with standin_table). M.weaponFor picks, for a shot of kind k and weapon w:
--   (b) a special whose id (their loadout now) sits at the plane's other special number (its loadout as it spawned:
--       theirs changed since) -> that number, the same weapon;
--   (a) w itself when the plane has it and it's of that kind or not known; but a missile special not known on a fallback
--       plane (another airframe's numbers) or where their loadout has another special now isn't trusted: the remote
--       fire treats whatever it launches as a missile, a laser or ESM there too;
--   (c) the nearest number of the same kind, ties to the lower: a missile special the nearest missile special, else
--       the standard missile (weapon 1: every player plane's, known or not); the standard missile weapon 1, else the
--       nearest special; a laser or ESM / ECM only one of its kind, else not shown; a bullet special one of its kind,
--       else a burst of the plane's gun (standin_gun_s).
-- Only numbers the plane here has are sent once it's known. A stand-in launch (c) keeps the shot's seed, start, rotation,
-- velocity and target, its spawn slot 0, the +0x26 byte 0 and its lock-ons at most 1 (another weapon's mean other
-- things); (b) changes the number only. The relay keeps the original: each game picks for its own plane. No
-- SV_PPWeapons (an older runtime), nothing read, or [coop.sync] standins = false: as sent, as before.
-- (fireShots, M.standInPay) what this game knows of player slot's real plane's weapons: { addr, at, tbl, n, k = { [0] =
-- ... }, s }; nil when it can't tell. Read on the first shot of each plane, again at most every 2 s when a shot needs it:
-- a stand-in, or its own number while that number's kind isn't known here or is known only from its table entry
-- (standin_table: the runtime may turn the table off after a launch that disagrees; the review of 0.73.80) (the runtime
-- learns it from that launch and then refuses another kind's shots there: the review of 2026-11-04), or when it couldn't
-- be read
function M.ppKinds(slot, P, now, need)
    if type(SV_PPWeapons) ~= "function" or not P.addr then return nil end
    local c = P.wk
    if c and c.addr == P.addr and (now - c.at < 2 or (c.n and not need)) then return c.n and c or nil end
    c = { addr = P.addr, at = now, tbl = sc().standin_table == true }
    P.wk = c
    local okW, s = pcall(SV_PPWeapons, P.addr, c.tbl and 1 or 0)
    if not (okW and type(s) == "string" and s ~= "") then
        once("ppw" .. slot .. "/" .. tostring(P.addr), string.format("coopfire: player %d's real plane here: its weapons can't "
            .. "be read (SV_PPWeapons: %s): their launches go as sent", slot + 1, okW and tostring(s) or ("error " .. tostring(s))))
        return nil
    end
    local k, n, usable, words = {}, 0, 0, {}
    for v in s:gmatch("[^,]+") do
        local x = M.intOf(v) or -1
        k[n] = x
        if x ~= -2 then usable = usable + 1 end
        words[#words + 1] = string.format("%d %s%s", n, (n == 0 and x == -1) and "the gun" or M.kindWord(x >= 10 and x - 10 or x, n),
            x >= 10 and " (its table's)" or "")
        n = n + 1
    end
    if n == 0 or n > 64 or usable == 0 then
        once("ppw0" .. slot .. "/" .. tostring(P.addr), string.format("coopfire: player %d's real plane here: no weapon of it usable "
            .. "(SV_PPWeapons %s): their launches go as sent", slot + 1, s))
        return nil
    end
    c.n, c.k, c.s = n, k, s
    if P.wkSaid ~= tostring(P.addr) .. s then                  -- (once a plane, again when what's known changes)
        P.wkSaid = tostring(P.addr) .. s
        log(string.format("coopfire: player %d's real plane here (%s%s): its weapons %s (SV_PPWeapons %s)", slot + 1,
            tostring(P.code or "?"), P.fallback and (", shown as a " .. tostring(P.fallback)) or "", table.concat(words, ", "), s))
    end
    return c
end
-- v as a whole number, else nil
function M.intOf(v)
    local x = tonumber(v)
    if not x or x ~= math.floor(x) or x ~= x then return nil end
    return math.floor(x)
end
-- a weapon kind in words (k: 0-4, -1 not known, -2 not usable; w its number: 0 the gun, 1 the standard missile, 2 and
-- up the specials); bare: without "a" / "the"
function M.kindWord(k, w, bare)
    local t
    if k == 0 then
        t = w == 1 and { "standard missile", "the standard missile" } or w == 0 and { "explosive weapon", "an explosive weapon" }
            or { "missile special", "a missile special" }
    else
        t = ({ [1] = { "laser", "a laser" }, [2] = { "bullet special", "a bullet special" }, [3] = { "ESM / ECM", "an ESM / ECM" },
               [4] = { "weapon of another kind", "a weapon of another kind" }, [-1] = { "not known yet", "not known yet" },
               [-2] = { "not usable", "not usable" } })[k] or { "?", "?" }
    end
    return bare and t[1] or t[2]
end
-- the kind (0-4) of weapon i on a plane here whose weapons are c (M.ppKinds); nil when it isn't known here (a table
-- entry's only with standin_table)
function M.kindAt(c, i)
    local v = c.k[i]
    if v == nil or v < 0 then return nil end
    if v >= 10 then return c.tbl and v - 10 or nil end
    return v
end
-- the number to show a shot of kind k, weapon w on a plane here whose weapons are c (M.ppKinds); ids: { sh = their
-- specials' ids now, cp = the plane's here as it spawned, dflt = it spawned with its default loadout (cp {}) } (nil:
-- not known, or a fallback); fb: a fallback plane; gun: a burst of its gun may stand in. -> x, how: "own" (w as sent),
-- "id", "near", or nil and "gun" / "none"
function M.weaponFor(k, w, c, ids, fb, gun)
    local K, n, lo = c.k, c.n, k == 0 and 1 or 2
    local function kindAt(i) return M.kindAt(c, i) end
    local function usable(i) return i >= lo and i < n and K[i] ~= nil and K[i] ~= -2 end
    if ids and (w == 2 or w == 3) and (ids.sh[w] or 0) > 0 then          -- (b) the same special, at its number here
        for j = 2, 3 do
            local kj = kindAt(j)
            if ids.cp[j] == ids.sh[w] and usable(j) and (kj == nil or kj == k) then return j, j == w and "own" or "id" end
        end
    end
    if usable(w) then                                                 -- (a) its own number
        local kw = kindAt(w)
        if kw == k then return w, "own" end
        local other = ids and (w == 2 or w == 3) and ids.cp[w] ~= ids.sh[w]
        if kw == nil and (k ~= 0 or w == 1 or not (fb or other)) then return w, "own" end
    end
    local best, bestD                                                 -- (c) the nearest of its kind (ties: the lower)
    local function consider(i)
        local ki = kindAt(i)
        if usable(i) and (ki == k or (k == 0 and i == 1 and ki == nil)) and (not best or math.abs(i - w) < bestD) then
            best, bestD = i, math.abs(i - w)
        end
    end
    if k == 0 and w <= 1 then consider(1) end                         -- (the standard missile: weapon 1 first)
    if not best then for i = 2, n - 1 do consider(i) end end          -- (a special: the specials first)
    if k == 0 and not best then consider(1) end
    if best then return best, "near" end
    if k == 2 and gun then return nil, "gun" end
    return nil, "none"
end
-- why a shot of kind k, weapon w isn't shown as itself on that plane (the log's words)
local function standWhy(k, w, c, ids, fb)
    local v = c.k[w]
    if w >= c.n or v == nil or v == -2 then return string.format("it has no weapon %d", w) end
    if w < (k == 0 and 1 or 2) then return k == 0 and "weapon 0 is the gun" or "a special's number is 2 or more" end
    local kv = M.kindAt(c, w)
    if kv and kv ~= k then return string.format("its weapon %d is %s", w, M.kindWord(kv, w)) end
    if ids and ids.dflt and (w == 2 or w == 3) then
        return string.format("their plane here spawned with its own default loadout (theirs hadn't come), their special %d is id %s",
            w - 1, tostring(ids.sh[w]))
    end
    if ids and (w == 2 or w == 3) and ids.cp[w] ~= ids.sh[w] then
        return string.format("their special %d is id %s now, the plane here has id %s there (their loadout changed since it spawned)",
            w - 1, tostring(ids.sh[w]), tostring(ids.cp[w]))
    end
    if fb then return string.format("its weapon %d isn't known yet and it's another airframe (a fallback: its numbers aren't theirs)", w) end
    return string.format("its weapon %d isn't known yet", w)
end
-- a loadout's two special ids ("a,b/c/x,y" -> { [2] = x, [3] = y }: weapons 2 and 3), nil if it has none
function M.loIds(lo)
    if type(lo) ~= "string" then return nil end
    local x, y = lo:match("/(%d+),(%d+)$")
    if not x then return nil end
    return { [2] = tonumber(x), [3] = tonumber(y) }
end
-- (fireShots) the shot to ask of player slot's real plane here for one of their launches (pay: "k,w,s,u,seed,lock,..."):
-- pay itself (its own weapon, or nothing known of the plane), another weapon's (a stand-in), or nil and why ("gun": a
-- burst of its gun instead, "none": not shown)
function M.standInPay(slot, P, pay, now)
    if sc().standins == false then return pay end
    local f = {}
    for v in pay:gmatch("[^,]+") do f[#f + 1] = v end
    local k, w = M.intOf(f[1]), M.intOf(f[2])
    if #f ~= 15 or not k or not w or k < 0 or k > 3 or w < 0 or w > 255 then return pay end   -- (the runtime refuses it)
    local c = M.ppKinds(slot, P, now, false)
    if not c then return pay end
    local r0 = M.roster[slot]
    local sh, cp = M.loIds(r0 and r0.lo), nil
    if not P.fallback then cp = M.loIds(P.lo) end
    local ids = (sh and cp) and { sh = sh, cp = cp } or nil
    -- (the review of 2026-11-04: a plane here spawned before their loadout came (P.lo "") flies the airframe's default
    -- specials, so a missile special of theirs not known there isn't trusted either: it could be a laser or ESM here.
    -- Both unknown: both the default, trusted)
    if sh and not cp and not P.fallback then ids = { sh = sh, cp = {}, dflt = true } end
    local fb, gun = P.fallback ~= nil, on("guns")
    local x, how = M.weaponFor(k, w, c, ids, fb, gun)
    -- (a stand-in, or its own number whose kind isn't known here: what's been seen launched since, first. The runtime
    -- learns a number's kind from its first launch here and refuses another kind's shots there after; without a read
    -- again those were refused for good, never put on the plane's weapon of their kind: the review of 2026-11-04.
    -- (review of 0.73.80) A kind known only from its table entry (standin_table: 10-14) isn't confirmed either: a launch
    -- that disagrees turns the table off in the runtime, and the seen kind then wins there)
    if now - c.at >= 2 and (how ~= "own" or not M.kindAt(c, x) or (c.k[x] or -1) >= 10) then
        local c2 = M.ppKinds(slot, P, now, true)
        if not c2 then return pay end
        c = c2
        x, how = M.weaponFor(k, w, c, ids, fb, gun)
    end
    if how == "own" then return pay end
    local n = S.n
    n.standBy = n.standBy or {}
    local by = n.standBy[slot] or {}
    n.standBy[slot] = by
    local mk = string.format("%s%d->%s", k == 0 and "" or (M.kindWord(k, w, true) .. " "), w, x and tostring(x) or how)
    by[mk] = (by[mk] or 0) + 1
    local what = M.kindWord(k, w, true)
    local key = string.format("si%d/%d/%d>%s/%s", slot, k, w, tostring(x or how), tostring(P.addr))
    if how == "id" or how == "near" then
        n.standIn = (n.standIn or 0) + 1
        once(key, string.format("coopfire: player %d's %s (weapon %d) shown on their real plane here as its weapon %d (%s): %s",
            slot + 1, what, w, x, M.kindWord(k, x), how == "id" and string.format("the same special sits there (id %s; their "
            .. "loadout changed since it spawned)", tostring(ids and ids.sh[w])) or standWhy(k, w, c, ids, fb)))
        f[2] = tostring(x)
        if how == "near" then
            f[3], f[4] = "0", "0"
            f[6] = tostring(math.min(M.intOf(f[6]) or 0, 1))
        end
        return table.concat(f, ",")
    end
    if how == "gun" then
        n.standGun = (n.standGun or 0) + 1
        P.burstUntil = now + (tonumber(sc().standin_gun_s) or 0.5)
        once(key, string.format("coopfire: player %d's bullet special (weapon %d) shown as their real plane's gun here: %s, and "
            .. "it has no bullet special (its weapons: %s)", slot + 1, w, standWhy(k, w, c, ids, fb), c.s))
        return nil, how
    end
    n.standNone = (n.standNone or 0) + 1
    once(key, string.format("coopfire: player %d's %s (weapon %d) NOT shown: %s, and their real plane here has no %s (its weapons: "
        .. "%s)", slot + 1, what, w, standWhy(k, w, c, ids, fb), k == 0 and "missile" or what, c.s))
    return nil, how
end
-- player slot's shots (entries "k:id:age"; extraMs: this leg's half round trip): each one that passes the guards fired
-- from their plane here; those entries (their ages grown) for the host to relay
local function fireShots(slot, body, extraMs)
    local passed = {}
    if not (slotOk(slot) and slot ~= COOP.slot and type(body) == "string") then
        once("fxslot", "coopfire: shots from a slot that isn't another player's dropped (" .. tostring(slot) .. ")")
        return passed
    end
    local P, now = M.peers[slot], os.clock()
    local R = S.rate[slot] or { at = now, n = 0 }
    S.rate[slot] = R
    if now - R.at >= 1 then R.at, R.n, R.np = now, 0, 0 end
    local lagging = P and type(P.age) == "number" and P.age > 1000      -- (their state over a second old)
    local why, n = {}, 0
    for e in body:gmatch("[^;]+") do
        n = n + 1
        local pid, page, pay = e:match("^p:(%d+):(%d+):([%-%d,]+)$")
        if pid then                                          -- (a launch for their real plane here: T4b)
            pid, page = tonumber(pid), tonumber(page) + extraMs
            local bad = (n > FX_MAX and "more than " .. FX_MAX .. " in a message") or ((pid > 65535 or #pay > 200) and "unreadable")
                or ((page > FX_STALE_MS or lagging) and "stale") or ((R.np or 0) >= P_PER_S and "over " .. P_PER_S .. " launches a second")
            if bad then
                why[bad] = (why[bad] or 0) + 1
                S.n.dropped = S.n.dropped + 1
            else
                R.np = (R.np or 0) + 1
                passed[#passed + 1] = string.format("p:%d:%d:%s", pid, page, pay)
                if P and P.real and P.addr and valid(P.obj) and on("missiles") and type(SV_CoopPPShot) == "function"
                    and not inStore() then
                    -- ((0.73.80) a weapon their plane here hasn't: the nearest of its kind it has, M.standInPay; the
                    -- relay above keeps theirs)
                    local okP, pay2 = pcall(M.standInPay, slot, P, pay, now)
                    if not okP then
                        once("sipay", "coopfire: the weapon stand-in failed (" .. tostring(pay2) .. "): their launches go as sent")
                        pay2 = pay
                    end
                    if pay2 then
                        local okS, r = pcall(SV_CoopPPShot, P.addr, addrOfId(pid) or 0, pay2)
                        if not okS then r = tostring(r) end
                        if r == 1 then S.n.pOk = (S.n.pOk or 0) + 1 else S.n.pBad = (S.n.pBad or 0) + 1 end
                        once("pfirst" .. slot, string.format("coopfire: player %d's first launch on their real plane here: %s", slot + 1,
                            r == 1 and "queued" or ("refused (" .. tostring(r) .. ")")))
                    end
                end
            end
        else
        local k, id, age = e:match("^([msge]):(%d+):(%d+)$")
        id, age = tonumber(id), tonumber(age)
        local bad = (n > FX_MAX and "more than " .. FX_MAX .. " in a message") or ((not k or id > 65535 or age > 600000) and "unreadable")
        if not bad and k == "g" then                         -- (the gun's target: no shot)
            if P then P.gunTarget = id end
            passed[#passed + 1] = string.format("g:%d:%d", id, age + extraMs)
        elseif not bad then
            age = age + extraMs
            bad = ((age > FX_STALE_MS or lagging) and "stale") or (R.n >= FX_PER_S and "over " .. FX_PER_S .. " a second") or nil
            if not bad then
                R.n, S.n.got = R.n + 1, S.n.got + 1
                passed[#passed + 1] = string.format("%s:%d:%d", k, id, age)
                local t = addrOfId(id)
                if id > 0 and not t then S.n.untargeted = (S.n.untargeted or 0) + 1 end
                if k == "e" then                                   -- (their ESM / jamming pod: the stand-in's ECM pod)
                    local row = P and P.row
                    local ecm = row and M.ecmSlot[row]
                    if not on("missiles") then
                    elseif ecm then coopFire(slot, ecm, nil)
                    else
                        once("noecm" .. slot .. tostring(row), string.format("coopfire: player %d's electronic special: their "
                            .. "plane here (%s) has no ECM pod to show it", slot + 1, tostring(row)))
                    end
                elseif on("missiles") then coopFire(slot, 2, t) end
            end
        end
        if bad then
            why[bad] = (why[bad] or 0) + 1
            S.n.dropped = S.n.dropped + 1
        end
        end
    end
    for w, c in pairs(why) do once("fxdrop" .. slot .. w, string.format("coopfire: player %d's shots dropped: %d %s", slot + 1, c, w)) end
    return passed
end
-- (the host) a joiner's "fx|entries": fired here, then to every other joiner as "fx|<slot>|entries"
function M.fxFromJoiner(from, f)
    local ok = fireShots(from, f[2], halfRtt(from))
    if #ok == 0 then return end
    local body = table.concat(ok, ";")
    for s in pairs(M.roster) do
        if s ~= 0 and s ~= from and s ~= COOP.slot then sendTo(s, true, "fx", from, body) end
    end
end
-- (a joiner) the host's "fx|<slot>|entries": the host's own or another joiner's, relayed
function M.fxFromHost(f)
    fireShots(tonumber(f[2]), f[3], halfRtt(0))
end

-- ((review of 0.73.80) a real plane's gun trigger (weapons +0x311) stays set until it's written back: let go wherever
-- the sync stops driving it (hidden, stale, set aside, a new level's P), so their plane here never fires on for good)
function M.gunOff(P)
    if P and P.real and P.gunOn and P.addr and P.obj and live(P.obj) and type(SV_CoopPPFx) == "function" then
        pcall(SV_CoopPPFx, P.addr, 1, 0)
    end
    if P then P.gunOn, P.burstUntil = false, nil end
end
-- the other players' state bits on their planes here: gear flips, gun bursts, flares
local function peersTick(now)
    for s, P in pairs(M.peers) do
        if P.gunOn and not (s ~= COOP.slot and P.obj and P.shown and P.fresh and valid(P.obj)) then M.gunOff(P) end
        if s ~= COOP.slot and P.obj and P.shown and P.fresh and valid(P.obj) and type(P.flags) == "number" then
            local fl = P.flags
            if on("gear") then
                local g = bit(fl, BIT_GEAR)
                if g ~= P.gear then
                    local first = P.gear == nil
                    P.gear = g
                    if not (first and not g) then                     -- (a new plane comes gear up: only "down" to say)
                        -- (a real plane: the game's own gear calls, as Online Mode's LandingGear; a stand-in: the AI's)
                        local okG, err = pcall(function()
                            if P.real then
                                local r = type(SV_CoopPPFx) == "function" and SV_CoopPPFx(P.addr, 2, g and 1 or 0) or -9
                                if r ~= 1 then error("SV_CoopPPFx " .. tostring(r)) end
                            else P.obj:EnableLandingGear(g, 1.0) end
                        end)
                        P.gearFlips = (P.gearFlips or 0) + 1
                        if P.gearFlips <= 4 or not okG then
                            log(string.format("coopfire: player %d's gear %s here: %s", s + 1, g and "down" or "up",
                                okG and "EnableLandingGear done" or ("EnableLandingGear failed: " .. tostring(err))))
                        end
                    end
                end
            end
            if P.real then                                    -- (a real plane: its own gun's trigger and flares, COOP2MP T4)
                -- ((0.73.80) or a bullet special their plane here hasn't, shown as a burst of its gun: M.standInPay)
                local gun = on("guns") and (bit(fl, BIT_GUN) or now < (P.burstUntil or 0)) or false
                if gun ~= (P.gunOn or false) and type(SV_CoopPPFx) == "function" then
                    P.gunOn = gun
                    SV_CoopPPFx(P.addr, 1, gun and 1 or 0)
                end
                if on("flares") then
                    local f = bit(fl, BIT_FLARE)
                    if f and (not P.flare or now >= (P.flareNext or 0)) and type(SV_CoopPPFx) == "function" then
                        P.flareNext = now + FLARE_EVERY_S
                        local r = SV_CoopPPFx(P.addr, 0, 1)
                        once("realflare" .. s, string.format("coopfire: player %d's flares on their real plane here: %s", s + 1, tostring(r)))
                    end
                    P.flare = f
                end
            else
            if on("guns") and bit(fl, BIT_GUN) and now >= (P.gunNext or 0) then
                P.gunNext = now + GUN_EVERY_S
                coopFire(s, 1, addrOfId(P.gunTarget))
            end
            if on("flares") then
                local f = bit(fl, BIT_FLARE)
                if f and (not P.flare or now >= (P.flareNext or 0)) then
                    P.flareNext = now + FLARE_EVERY_S
                    coopFire(s, 0, nil)
                end
                P.flare = f
            end
            end
        end
    end
end

-- (COOP.tick, after the state went out) this game's shots to the others, theirs shown here, the ammo counts kept
function M.syncTick(now, pawn)
    if sc().enabled ~= true then return end
    if valid(pawn) then
        local out = {}
        local pa = addrOf(pawn)
        if pa ~= S.pawn then S.pawn, S.seen, S.primed = pa, {}, false end
        if on("missiles") then watchShots(pawn, out) end
        -- the gun's target, as the gun starts or the target changes while it fires (the stand-ins aim there)
        local gun = on("guns") and S.gunAt and now - S.gunAt <= FLAG_HOLD_S
        if gun and type(SV_PlayerTarget) == "function" and pa then
            local okT, t = pcall(SV_PlayerTarget, pa)
            local id = (okT and type(t) == "number" and t > 0) and idOfAddr(t) or 0
            if okT and type(t) == "number" and t > 0 then M.gunMark(t) end   -- ((0.73.79) M.floorLoss)
            if id ~= S.gunTarget or not S.gunOn then out[#out + 1] = string.format("g:%d:0", id); S.gunTarget = id end
        end
        S.gunOn = gun
        -- a special weapon used with nothing new in flight since (an ESM / jamming pod): "e", its age since the drop
        if S.spDropAt and now - S.spDropAt >= ELEC_WAIT_S then
            if not (S.spShotAt and S.spShotAt >= S.spDropAt - 0.3) then
                out[#out + 1] = string.format("e:0:%d", math.floor((now - S.spDropAt) * 1000 + 0.5))
                once("fxelec", "coopfire: your special weapon went off with nothing in flight (an ESM or jamming pod): sent as e")
            end
            S.spDropAt = nil
        end
        -- your launches as the runtime read them, for your real plane in the other games (T4b): "p:<target id>:0:<shot>"
        if on("missiles") and type(SV_CoopShots) == "function" then
            local okL, list = pcall(SV_CoopShots)
            if okL and type(list) == "string" and list ~= "" then
                for e in list:gmatch("[^;]+") do
                    local pay, t = e:match("^([%-%d,]+),(%d+)$")
                    if pay then out[#out + 1] = string.format("p:%d:0:%s", idOfAddr(tonumber(t) ~= 0 and tonumber(t) or nil), pay) end
                end
            end
        end
        if #out > FX_MAX then for i = #out, FX_MAX + 1, -1 do out[i] = nil end end
        local shots = 0
        for _, e in ipairs(out) do local c = e:sub(1, 1); if c ~= "g" and c ~= "p" then shots = shots + 1 end end
        if #out > 0 and (M.linkedPeers or 0) > 0 then
            local body = table.concat(out, ";")
            if COOP.host() then send(true, "fx", COOP.slot or 0, body) else send(true, "fx", body) end
            S.n.sent = S.n.sent + shots
            if shots > 0 then once("fxsent", "coopfire: your first shot sent (" .. body .. ")") end
        end
    end
    peersTick(now)
    ammoAfter()
    if now >= (S.statAt or now + 60) then                   -- (a minute's tally, when anything happened)
        local n = S.n
        if n.sent + n.got + n.fired + n.failed + n.dropped + (n.bursts or 0) + (n.flares or 0) + (n.pOk or 0) + (n.pBad or 0)
            + (n.standIn or 0) + (n.standGun or 0) + (n.standNone or 0) > 0 then
            -- ((0.73.80) the weapon stand-ins, when any: how many, and each player's numbers as sent -> shown here)
            local si = ""
            if (n.standIn or 0) + (n.standGun or 0) + (n.standNone or 0) > 0 then
                local per = {}
                for s, by in pairs(n.standBy or {}) do
                    local maps = {}
                    for mk, c in pairs(by) do maps[#maps + 1] = string.format("%s x%d", mk, c) end
                    table.sort(maps)
                    per[#per + 1] = string.format("%d: %s", s + 1, table.concat(maps, ", "))
                end
                table.sort(per)
                si = string.format("; weapon stand-ins: %d on another weapon of the same kind, %d as the gun, %d not shown (no "
                    .. "weapon of that kind there); by player: %s", n.standIn or 0, n.standGun or 0, n.standNone or 0, table.concat(per, "; "))
            end
            log(string.format("coopfire: 60 s: %d shots sent, %d received (%d fired here, %d refused, %d dropped, %d with "
                .. "their target not here, %d with no plane here, %d not shown: you were in the STORE), your gun %d bursts, "
                .. "your flares %d, your gear flips %d, afterburner flips %d, throttle up to %.3f (ab_throttle %s); real planes' "
                .. "launches (T4b) %d queued, %d refused%s", n.sent,
                n.got, n.fired, n.failed, n.dropped, n.untargeted or 0, n.noPlane or 0, n.inStore or 0, n.bursts or 0,
                n.flares or 0, n.gear, n.ab, (n.thMax or 0) / 1000, tostring(sc().ab_throttle), n.pOk or 0, n.pBad or 0, si))
        end
        S.n = { sent = 0, got = 0, fired = 0, failed = 0, dropped = 0, gear = 0, ab = 0 }
        S.statAt = now + 60
    end
    S.statAt = S.statAt or now + 60
end

-- The stand-ins' damage-0 rows, made at the main menu (sv_main.lua, every second until done): the spawner reads the
-- world data's mission rows' DT_NPC rows when the level loads (hard rule 20, sv_rows.lua searchSetup), so for every
-- airframe a stand-in flies (CFG.coop.airframes, default) the mission row <row>_svcp (tools/build_survival.py,
-- COOP_STANDIN_SUFFIX) names <its NpcId>_SVCP, made here as a copy of <row>'s DT_NPC row with each fire-control slot on
-- <FCS>_SVCP and that one's weapon on <W>_SVCP: damage and AreaOfEffectDamage 0 (the allies' <FCS>_SVA way). A slot
-- whose weapon can't be made harmless is emptied. M.svcpReady[row] once made; a level that loads after flies them.
function COOP.syncSetup()
    local c = cfg()
    if M.svcpDone or not c.enabled or not gameInstance() then return end
    M.svcpTries = (M.svcpTries or 0) + 1
    local npc, mission, fcs, wpn = loadObject(PROBE_TABLES[2].path), loadObject(MISSION_TABLE), loadObject(FCS_TABLE), loadObject(WEAPON_TABLE)
    if not (npc and mission and fcs and wpn) then
        if M.svcpTries >= 20 then
            M.svcpDone = true
            log("coopfire: the stand-ins' tables didn't load: they fly their airframes' own rows (what they fire could do damage)")
        end
        return
    end
    M.svcpDone, M.svcpReady = true, {}
    for _, t in ipairs({ npc, mission, fcs, wpn }) do pin(t, nameOf(t)) end
    local made, emptied, lost, ecms = {}, {}, {}, {}
    -- (the electronic-warfare airframes: their plain campaign rows, OP1010_e18g_01 and kin, have no ECM pod, only the
    -- named aces' do; their copies get the stock one in their first free slot, so the others' ESM shows on them)
    local ELEC = { e18g_common = true, ea36_common = true, e06b_common = true }
    local function harmless(id)                           -- id .. "_SVCP": its weapon's damage 0, or nil
        local new = id .. "_SVCP"
        if made[new] == nil then
            made[new] = cloneRow(fcs, id, new, function(r)
                local w = r.NpcWeaponId:ToString()
                if w == "None" or w == "" then return end
                local wn = w .. "_SVCP"
                local okW, whyW = cloneRow(wpn, w, wn, function(x)
                    x.damage = 0
                    pcall(function() x.AreaOfEffectDamage = 0 end)
                end)
                if not okW then error("weapon " .. w .. ": " .. tostring(whyW), 0) end
                local _, xr = dtCall(wpn, "FindRow", wn)
                if not (xr ~= nil and xr.damage == 0) then error("weapon " .. wn .. " doesn't read back damage 0", 0) end
                r.NpcWeaponId = FName(wn)
            end) and true or false
        end
        return made[new] and new or nil
    end
    local rows, seen = {}, {}
    for _, r in pairs(c.airframes or {}) do if not seen[r] then seen[r] = true; rows[#rows + 1] = r end end
    if c.default and not seen[c.default] then rows[#rows + 1] = c.default end
    table.sort(rows)
    for _, row in ipairs(rows) do
        local ok, err = pcall(function()
            local _, base = dtCall(mission, "FindRow", row)
            local _, mr = dtCall(mission, "FindRow", row .. "_svcp")
            if base == nil or mr == nil then error("no mission row " .. (base == nil and row or row .. "_svcp") .. " in DT_SV_NpcMission", 0) end
            local src, dst = base.NpcId:ToString(), mr.NpcId:ToString()
            local okR, whyR = cloneRow(npc, src, dst, function(r)
                for i = 0, 5 do
                    local id = r["NpcFCSId" .. i]:ToString()
                    if id:upper():find("ECM", 1, true) then M.ecmSlot[row] = i; ecms[#ecms + 1] = row .. " slot " .. i end
                    if id ~= "None" and id ~= "" and not id:find("_SVCP$") then
                        local new = harmless(id)
                        if new then r["NpcFCSId" .. i] = FName(new)
                        else r["NpcFCSId" .. i] = FName("None"); emptied[#emptied + 1] = dst .. " slot " .. i .. " (" .. id .. ")" end
                    end
                end
                if ELEC[row] and M.ecmSlot[row] == nil then
                    for i = 3, 5 do
                        local id = r["NpcFCSId" .. i]:ToString()
                        if id == "None" or id == "" then
                            r["NpcFCSId" .. i] = FName("NPC_FCS_ECM000")
                            M.ecmSlot[row] = i
                            ecms[#ecms + 1] = row .. " slot " .. i .. " (added)"
                            break
                        end
                    end
                end
            end)
            if not okR then error(dst .. ": " .. tostring(whyR), 0) end
            M.svcpReady[row] = row .. "_svcp"
        end)
        if not ok then lost[#lost + 1] = row .. " (" .. tostring(err) .. ")" end
    end
    local n = 0
    for _ in pairs(M.svcpReady) do n = n + 1 end
    log(string.format("coopfire: the stand-ins' damage-0 rows: %d of %d airframes%s%s; ECM pods (the others' ESM shown): %s", n,
        #rows, #emptied > 0 and ("; weapons left off: " .. table.concat(emptied, ", ")) or "",
        #lost > 0 and ("; not made (their own rows): " .. table.concat(lost, "; ")) or "",
        #ecms > 0 and table.concat(ecms, ", ") or "none"))
end

-- TEST ONLY BEGIN (Ctrl+F5, sv_main.lua: the co-op fire path on an allied plane, solo; tools/re/COOP.md 8)
-- Each press the next step on the first allied fighter up (MOONCHILD or VIPER, bought in the STORE), aimed at your
-- current target (SV_PlayerTarget, or none): 1 its missiles (slot 2) with its fire permission off, 2 the same with it
-- on, 3 its gun (slot 1), 4 its flares (slot 0), 5 its gear down, 6 its gear up; each "coopfire: test ..."
function COOP.fireTest()
    local R = ALLY and ALLY.run
    local ally = nil
    for _, p in ipairs(R and R.planes or {}) do if not ally and valid(p.obj) and (health(p.obj) or 0) > 0 then ally = p end end
    if not ally then log("coopfire: test: no allied plane up (buy MOONCHILD or VIPER in the STORE)"); hudCallout("TEST: NO ALLIED PLANE UP", "BUY ONE IN THE STORE"); return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    local t = (valid(pawn) and type(SV_PlayerTarget) == "function") and SV_PlayerTarget(addrOf(pawn)) or 0
    t = (type(t) == "number" and t > 0) and t or 0
    S.test = (S.test or 0) % 6 + 1
    local a, step, r = addrOf(ally.obj), S.test, nil
    local fire = type(SV_CoopFire) == "function" and SV_CoopFire or function() return "no SV_CoopFire" end
    local what
    if step <= 2 then
        pcall(function() ally.obj.bPermissionToFire = step == 2 end)
        local okP, perm = pcall(function() return ally.obj.bPermissionToFire end)
        r, what = fire(a, 2, t), string.format("missiles (slot 2), fire permission %s", okP and tostring(perm) or "?")
    elseif step == 3 then r, what = fire(a, 1, t), "gun (slot 1)"
    elseif step == 4 then r, what = fire(a, 0, 0), "flares (slot 0)"
    else
        local okG, err = pcall(function() ally.obj:EnableLandingGear(step == 5, 1.0) end)
        r, what = okG and "done" or ("failed: " .. tostring(err)), "EnableLandingGear(" .. tostring(step == 5) .. ", 1.0)"
    end
    log(string.format("coopfire: test %d: %s (%s) %s at %s: %s", step, ally.name, ally.unit, what, t > 0 and string.format("%X", t) or "no target", tostring(r)))
    hudCallout("TEST " .. step .. ": " .. what:upper(), tostring(r))
end
-- TEST ONLY END
end

---------------------------------------------------------------------------------------------------- messages
-- your plane's loadout (SV_CoopLoadout, runtime 0.32.0: "a,b/c,d/x,y"), "" when it can't be read: the others' real
-- plane of yours carries it, so your weapon numbers mean there what they mean here (COOP2MP T4b)
local function loadoutOk(lo) return type(lo) == "string" and #lo <= 600 and lo:match("^[%d,]*/[%d,]*/%d+,%d+$") ~= nil end
function M.myLoadout()
    if type(SV_CoopLoadout) ~= "function" then return "" end
    local ok, lo = pcall(SV_CoopLoadout)
    return (ok and loadoutOk(lo)) and lo or ""
end
M.loadoutOk = loadoutOk
-- your plane's paint (SV_CoopPaint, runtime 0.32.3: "skin/flags/e1,e2,..."): the others' real plane of yours wears it
-- (COOP2MP T5; [coop] real_paint)
local function paintOk(p) return type(p) == "string" and #p <= 200 and p:match("^%-?%d+/%-?%d+/[%d,]*$") ~= nil end
function M.myPaint()
    if type(SV_CoopPaint) ~= "function" then return "" end
    local ok, p = pcall(SV_CoopPaint)
    return (ok and paintOk(p)) and p or ""
end
M.paintOk = paintOk
-- your aircraft's name as the game shows it (your plane's GetObjName: "ADFX-02" ...), for the line beside your name on
-- the others' boxes (SV_PPName's third argument, runtime 0.32.4); 32 characters at most, no "|"
local function acClean(v)
    if type(v) ~= "string" then return "" end
    v = v:gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return #v <= 32 and v or v:sub(1, 32)
end
function M.myAircraft()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return "" end
    local ok, v = pcall(function() local x = pawn:GetObjName(); return type(x) == "string" and x or x:ToString() end)
    return ok and acClean(v) or ""
end
M.acClean = acClean
local function sendHi()
    local row, code = myAirframe()
    -- (what the host last heard: a hello sent with no plane yet is followed by the airframe once there is one; the
    -- co-op run of 2026-10-30: a player who'd been in the level before linking never sent theirs, shown as the default)
    -- The airframe's code (COOP2MP T3: the player plane the others spawn for you; the ADFX-02 has no AI row) goes last.
    M.myRow, M.myCode, M.myLo, M.myPt, M.myAc = row, code, M.myLoadout(), M.myPaint(), M.myAircraft()
    -- ((0.73.80) a plane with no stock code: its class path and stock base last, for the games with and without it)
    local okP, mc, mb = pcall(M.myPlane, nil, code)
    M.myCls, M.myBase = okP and mc or "", okP and mb or ""
    send(true, table.unpack(M.modFields({ "hi", VERSION, type(SV_Version) == "function" and SV_Version() or "?", row or "",
        M.myName or "", code or "", M.myLo, M.myPt, M.myAc }, code, M.myCls, M.myBase)))
end

-- the host's own roster entry, and everyone told
local function hostRosterSelf()
    local row, code = myAirframe()
    M.myRow, M.myCode, M.myLo, M.myPt, M.myAc = row, code, M.myLoadout(), M.myPaint(), M.myAircraft()
    local okP, mc, mb = pcall(M.myPlane, nil, code)        -- ((0.73.80) relayed in "pi" for a plane with no stock code)
    M.myCls, M.myBase = okP and mc or "", okP and mb or ""
    M.roster[0] = { row = row or "", ver = VERSION, name = M.myName or "", code = code or "", lo = M.myLo, paint = M.myPt,
                    ac = M.myAc, sid = M.mySid and M.mySid() or nil, cls = M.myCls, base = M.myBase }
    sendRoster(nil)
end

-- The host's settings for everyone (user, 2026-10-26: "we need to work on survival.ini syncing as some player might edit
-- their ini files"): the host sends each joiner what its CFG has that differs from the shipped one (CFG_DEFAULTS:
-- survival.ini and survival_config.lua both), as data only ("cf", in chunks); the joiner's CFG goes back to the shipped
-- settings and takes the host's on top, in place (other parts hold CFG's tables), and its own come back when co-op
-- closes or it hosts. Each player keeps their own PERSONAL sections (name and link, HUD, sound, music, leaderboard,
-- the menu's, tells, P6's profile and flares, the test logs' probe / ai_watch / stats / log; of [coop] the host's
-- revives all the same, SHARED_IN, but for the key and camera) and the host's difficulty preset is used for everyone
-- (presetName).
do
local PERSONAL = { coop = true, hud = true, sound = true, music = true, leaderboard = true, menu = true, probe = true, ai_watch = true,
                   stats = true, tells = true, profile = true, flares = true,   -- (profile, flares: P6's, each player's own)
                   log = true,                                                  -- ([log] verbose: each game's log)
                   recycle = true }                                             -- ((0.73.77) each runtime's own (F2b))
-- Inside a PERSONAL section, the host's all the same: the run's revives ([coop.revive], sv_down.lua: one price and floor
-- for the room) but for what's each player's own there (OWN_IN: the next-player key and the spectator camera)
local SHARED_IN = { { "coop", "revive" } }
local OWN_IN = { ["coop.revive.key"] = true, ["coop.revive.ctrl"] = true, ["coop.revive.camera"] = true }
local function pathStr(p, n) local q = {}; for j = 1, n or #p do q[j] = tostring(p[j]) end; return table.concat(q, ".") end
local function ownPath(p) for j = 1, #p do if OWN_IN[pathStr(p, j)] then return true end end; return false end
local function sharedPath(p)
    for _, s in ipairs(SHARED_IN) do
        local m = #p >= #s
        for j = 1, #s do if p[j] ~= s[j] then m = false end end
        if m then return true end
    end
    return false
end
local function at(t, p) for j = 1, #p do if type(t) ~= "table" then return nil end; t = t[p[j]] end; return t end
-- world-data unit lists (CFG.pool, airfield.bombers.pool / heavy_units, allies' units): build data, the same in the same
-- build, and other parts' lookup tables are made from them at load (code review: BOMBER_UNIT, HEAVY_UNIT, ALLY.unit)
local function structural(path)
    local last = path[#path]
    return path[1] == "pool" or last == "pool" or last == "heavy_units" or last == "units"
end
-- A host's value against the shipped one at its place (security review of 2026-10-26: a broken or hostile host must
-- not hang or break a joiner): the same type; numbers finite and not wildly past the shipped size; text short, no
-- control characters; lists of at most 1000 items like the shipped ones. Paths this build doesn't have are skipped.
local function fits(v, d)
    if type(v) ~= type(d) then return false end
    if type(v) == "number" then return v == v and math.abs(v) <= math.max(math.abs(d) * 1000, 100000) end
    if type(v) == "string" then return #v <= 1024 and not v:find("%c") end
    if type(v) == "table" then
        local n = 0
        for k, x in pairs(v) do
            n = n + 1
            local dx = d[k]
            if dx == nil and math.type(k) == "integer" then dx = d[1] end    -- (a list's new item: like its first)
            if n > 1000 or dx == nil or not fits(x, dx) then return false end
        end
    end
    return true
end
local function shipped(path)                               -- CFG_DEFAULTS at path, or nil
    local t = CFG_DEFAULTS
    for j = 1, #path do
        if type(t) ~= "table" then return nil end
        t = t[path[j]]
    end
    return t
end
local CHUNK = 900
local function esc(s) return (s:gsub("[%%,{}|%c]", function(c) return string.format("%%%02X", c:byte()) end)) end
local function enc(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do if type(x) ~= "function" then enc(k, out); enc(x, out) end end
        out[#out + 1] = "}"
    elseif t == "string" then out[#out + 1] = "s" .. esc(v)
    elseif t == "number" then out[#out + 1] = math.type(v) == "integer" and string.format("i%d", v) or string.format("n%.17g", v)
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
    else out[#out + 1] = "~" end
end
local function dec(tk, i, depth)
    local s = tk[i]
    if s == "{" then
        if depth > 40 then error("settings nested too deep") end
        local t = {}
        i = i + 1
        while tk[i] and tk[i] ~= "}" do
            local k, v
            k, i = dec(tk, i, depth + 1)
            v, i = dec(tk, i, depth + 1)
            if k ~= nil then t[k] = v end
        end
        return t, i + 1
    end
    local c, rest = (s or ""):sub(1, 1), (s or ""):sub(2)
    if c == "s" then return (rest:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)), i + 1
    elseif c == "i" then return math.tointeger(tonumber(rest)) or tonumber(rest), i + 1
    elseif c == "n" then return tonumber(rest), i + 1
    elseif c == "T" then return true, i + 1
    elseif c == "F" then return false, i + 1 end
    return nil, i + 1
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function isList(t) return type(t) == "table" and #t > 0 end
local function diff(cur, def, path, out)                   -- leaves (and whole lists) of cur that differ from def
    for k, v in pairs(cur) do
        local d = def[k]
        local p = { table.unpack(path) }
        p[#p + 1] = k
        if type(v) == "function" then
        elseif type(v) == "table" and type(d) == "table" and not isList(v) and not isList(d) then diff(v, d, p, out)
        elseif not same(v, d) then out[#out + 1] = { p, v } end
    end
    for k in pairs(def) do
        if cur[k] == nil then local p = { table.unpack(path) }; p[#p + 1] = k; out[#out + 1] = { p } end
    end
end
COOP.cfgDiff = diff                                        -- (the leaderboard's edited check too: LB.edited)
local function fill(into, from)                            -- `into` made to hold a copy of `from`, in place
    for k in pairs(into) do if from[k] == nil then into[k] = nil end end
    for k, v in pairs(from) do
        if type(v) == "table" then
            if type(into[k]) ~= "table" then into[k] = {} end
            fill(into[k], v)
        else into[k] = v end
    end
end
local function synced()
    local keys = {}
    for k in pairs(CFG_DEFAULTS or {}) do if not PERSONAL[k] then keys[k] = true end end
    for k in pairs(CFG) do if not PERSONAL[k] then keys[k] = true end end
    return keys
end
local function put(k, v)                                   -- CFG[k] = a copy of v, tables in place
    if type(v) == "table" and type(CFG[k]) == "table" then fill(CFG[k], v) else CFG[k] = deepCopy(v) end
end

-- (host) the settings to one joiner (to: its slot) or to every joiner (to: nil)
function M.sendSettings(to)
    if not CFG_DEFAULTS then return end
    local out = {}
    for k in pairs(synced()) do
        local v, d = CFG[k], CFG_DEFAULTS[k]
        if type(v) == "table" and type(d) == "table" and not isList(v) and not isList(d) then diff(v, d, { k }, out)
        elseif not same(v, d) then out[#out + 1] = { { k }, v } end
    end
    for _, s in ipairs(SHARED_IN) do                       -- (the host's part of a PERSONAL section)
        local v, d = at(CFG, s), at(CFG_DEFAULTS, s)
        if type(v) == "table" and type(d) == "table" then diff(v, d, { table.unpack(s) }, out) end
    end
    for i = #out, 1, -1 do if structural(out[i][1]) or ownPath(out[i][1]) then table.remove(out, i) end end
    local tk = {}
    local pname, pdiff = presetName()
    enc({ ver = VERSION, preset = pname, pdiff = pdiff, max = maxPlayers(), diff = out }, tk)
    local text = table.concat(tk, ",")
    local n = math.max(1, math.ceil(#text / CHUNK))
    for i = 1, n do sendTo(to, true, "cf", i, n, text:sub((i - 1) * CHUNK + 1, i * CHUNK)) end
    log(string.format("coop: the host's settings to %s: %d differ from the shipped ones (%d bytes)",
        to and ("player " .. (to + 1)) or "every joiner", #out, #text))
end

-- (joiner) a chunk of the host's settings; the last one applies them
function M.onSettings(f)
    local i, n = tonumber(f[2]), tonumber(f[3])
    if not (i and n and n == math.floor(n) and n >= 1 and n <= 400 and i == math.floor(i) and i >= 1 and i <= n) then return end
    if i == 1 then M.cfParts = {} end
    M.cfParts = M.cfParts or {}
    M.cfParts[i] = f[4] or ""
    if i ~= n then return end
    for j = 1, n do if not M.cfParts[j] then log("coop: the host's settings came incomplete; kept as they were"); M.cfParts = nil; return end end
    local tk = {}
    for t in (table.concat(M.cfParts, "", 1, n) .. ","):gmatch("([^,]*),") do tk[#tk + 1] = t end
    M.cfParts = nil
    local ok, s = pcall(dec, tk, 1, 0)
    if not ok or type(s) ~= "table" or type(s.diff) ~= "table" then log("coop: the host's settings could not be read: " .. tostring(s)); return end
    if not M.mine then                                    -- (your own, for when co-op closes or you host)
        M.mine, M.mineIn = {}, {}
        for k in pairs(synced()) do M.mine[k] = deepCopy(CFG[k]) end
        for _, sp in ipairs(SHARED_IN) do M.mineIn[pathStr(sp)] = deepCopy(at(CFG, sp)) end
    end
    for k in pairs(synced()) do put(k, CFG_DEFAULTS[k]) end
    for _, sp in ipairs(SHARED_IN) do                      -- (the shipped ones, but what's each player's own there)
        local cur, d = at(CFG, sp), at(CFG_DEFAULTS, sp)
        if type(cur) == "table" and type(d) == "table" then
            local keep = {}
            for k, v in pairs(cur) do
                local q = { table.unpack(sp) }
                q[#q + 1] = k
                if ownPath(q) then keep[k] = deepCopy(v) end
            end
            fill(cur, d)
            for k, v in pairs(keep) do if type(v) == "table" and type(cur[k]) == "table" then fill(cur[k], v) else cur[k] = v end end
        end
    end
    local names, skipped = {}, 0
    for i, e in ipairs(s.diff) do
        local p = type(e) == "table" and e[1]
        local ok = i <= 5000 and type(p) == "table" and #p >= 1 and #p <= 12 and (not PERSONAL[p[1]] or sharedPath(p))
            and not ownPath(p) and not structural(p)
        local d = ok and shipped(p)
        if not ok or d == nil or e[2] == nil or not fits(e[2], d) then
            skipped = skipped + 1
        else
            local t = CFG
            for j = 1, #p - 1 do
                if type(t[p[j]]) ~= "table" then t[p[j]] = {} end
                t = t[p[j]]
            end
            local last, v = p[#p], e[2]
            if type(v) == "table" and type(t[last]) == "table" then fill(t[last], v) else t[last] = v end
            if #names < 12 then local q = {}; for j = 1, #p do q[j] = tostring(p[j]) end; names[#names + 1] = table.concat(q, ".") end
        end
    end
    if skipped > 0 then log("coop: " .. skipped .. " of the host's settings skipped (this build has no such setting, or the value doesn't fit it)") end
    M.hostPreset = type(s.preset) == "string" and short(s.preset, 16) or nil
    M.hostDiff = math.tointeger(s.pdiff)
    local mx = math.tointeger(s.max)
    M.hostMax = mx and mx >= 2 and mx <= MAX_SLOT + 1 and mx or nil
    log(string.format("coop: playing with the host's settings (Survival %s, preset %s): %d differ from the shipped ones%s",
        tostring(s.ver), tostring(M.hostPreset), #s.diff, #names > 0 and (": " .. table.concat(names, ", ") .. (#s.diff > #names and ", ..." or "")) or ""))
end

-- your own settings back (co-op closed, or you host now)
function M.restoreMine()
    if not M.mine then return end
    for k in pairs(synced()) do put(k, M.mine[k]) end
    for _, sp in ipairs(SHARED_IN) do
        local cur, mine = at(CFG, sp), M.mineIn and M.mineIn[pathStr(sp)]
        if type(cur) == "table" and type(mine) == "table" then fill(cur, mine) end
    end
    M.mine, M.mineIn, M.hostPreset, M.hostDiff, M.hostMax = nil, nil, nil, nil, nil
    log("coop: your own settings are back")
end

-- (your own settings, for the menu's settings rows: the host's are in CFG while you play with them)
function M.ownRoot() return M.mine or CFG end

local rawPreset = presetName
presetName = function()
    local name, d = rawPreset()
    if COOP.client() and M.hostPreset then return M.hostPreset, M.hostDiff or d end
    return name, d
end
end

---------------------------------------------------------------------------------------------------- allies and defences
-- (sv_shop.lua shopBuy / shopBuildFor, sv_allies.lua) A joiner's STORE purchase of an allied flight or ship or an
-- airfield defence: "ab|<id>|<item>|<price>|<kind>" to the host, paid here at once; the host builds it in its game (its
-- spawn goes to every game as its enemies' do) and answers "ak|<id>|<message>" or "ax|<id>|<why>" (refunded), or
-- "ar|<price>|<why>" later (a flight that never took off: refunded). No answer in BUILD_WAIT_S: refunded.
local BUILD_WAIT_S, BUILD_PER_S = 30, 4
function COOP.askBuild(name, price, kind)
    if not COOP.client() then return false, "NOT IN CO-OP." end
    M.builds = M.builds or {}
    M.buildSeq = (M.buildSeq or 0) % 9999 + 1
    local id = M.buildSeq
    if not send(true, "ab", id, short(name, 32), string.format("%d", price), kind and short(kind, 16) or "") then
        return false, "NO LINK TO THE HOST."
    end
    M.builds[id] = { name = name, price = price, kind = kind, at = os.clock() }
    log(string.format("shop: asked the host to build %s (%d paid, kept until it answers)", name, price))
    return true, "ASKED THE HOST: IT BUILDS IT FOR EVERYONE."
end
local function buildDone(b, msg)
    if not (b and RUN) then return end
    RUN.msg[b.name], RUN.dirty = msg, true
    RUN.bought[b.name] = (RUN.bought[b.name] or 0) + 1
    if b.kind then
        RUN.defences = RUN.defences or { built = 0, bought = {} }
        RUN.defences.built = RUN.defences.built + 1
        RUN.defences.bought[b.kind] = (RUN.defences.bought[b.kind] or 0) + 1
    elseif LB and LB.stat then pcall(LB.stat, "allies", 1) end
end
local function refundHere(price, name, why)
    if not RUN or type(price) ~= "number" or price <= 0 then return end
    RUN.credits, RUN.spent, RUN.dirty = RUN.credits + price, math.max(0, RUN.spent - price), true
    if name then RUN.msg[name] = string.format("%s. %d REFUNDED.", why, price) end
    log(string.format("shop: %s: %s; %d refunded", tostring(name or "a purchase"), why, price))
end
function M.buildTick(now)
    for id, b in pairs(M.builds or {}) do
        if now - b.at >= BUILD_WAIT_S then
            M.builds[id] = nil
            refundHere(b.price, b.name, "NO ANSWER FROM THE HOST")
        end
    end
end
-- (the host) a joiner's purchase that can't come after all (an allied flight that never took off): their zollars back
function COOP.refund(slot, price, why)
    if not (COOP.host() and slotOk(slot) and slot ~= COOP.slot) then return false end
    return sendTo(slot, true, "ar", string.format("%d", math.floor(tonumber(price) or 0)), short(why, 60))
end
-- (the host) joiner `slot` airborne here: their plane in the mission, flying, not at their airfield, not down
function COOP.airborne(slot)
    local P = M.peers[slot]
    return P ~= nil and P.fresh == true and not P.onAirfield and not P.down
end
-- the allies' orders changed here (sv_allies.lua ALLY.nextOrder): a joiner's go to the host, the host's to everyone
function COOP.orderChanged(order, how)
    if not COOP.open or how == "coop" then return end
    if COOP.client() then send(true, "ao", short(order, 16)) elseif COOP.host() then send(true, "ag", short(order, 16)) end
end
local function onBuildAsk(from, f)
    M.buildRate = M.buildRate or {}
    local now, r = os.clock(), M.buildRate[from]
    if not r or now - r.at >= 1 then r = { at = now, n = 0 }; M.buildRate[from] = r end
    r.n = r.n + 1
    if r.n > BUILD_PER_S then once("abrate" .. from, "shop: player " .. (from + 1) .. " asks for too many builds; dropped"); return end
    local id, name, price = tonumber(f[2]), short(f[3], 32), tonumber(f[4])
    local kind = (f[5] and f[5] ~= "") and short(f[5], 16) or nil
    if not (id and id == math.floor(id) and id >= 1 and id <= 9999) then return end
    local it = CFG.shop and CFG.shop.items and CFG.shop.items[name]
    if not (it and price and finite(price, CREDITS_MAX + 1) and price >= 0) then
        sendTo(from, true, "ax", id, "A BAD REQUEST"); return
    end
    local ok, msg = false, "NOT AVAILABLE RIGHT NOW."
    if type(shopBuildFor) == "function" then
        local okC, a, b = pcall(shopBuildFor, from, name, math.floor(price), kind, true)   -- ((0.73.78) true: a joiner's ask)
        if okC then ok, msg = a, b else msg = "THE HOST COULDN'T BUILD IT"; log("shop: build for player " .. (from + 1) .. ": " .. tostring(a)) end
    end
    log(string.format("shop: player %d's %s (%d): %s", from + 1, name, math.floor(price), ok and ("built: " .. tostring(msg)) or ("refused: " .. tostring(msg))))
    if ok then sendTo(from, true, "ak", id, short(msg, 80)) else sendTo(from, true, "ax", id, short(msg, 80)) end
end
local function upperText(v, n) return (tostring(v or ""):gsub("[%c|]", ""):upper():sub(1, n)) end
local function onBuildAnswer(f)
    local k, id = f[1], tonumber(f[2])
    if k == "ar" then
        local price = tonumber(f[2])
        if price and finite(price, CREDITS_MAX + 1) and price > 0 then refundHere(math.floor(price), nil, upperText(f[3], 60)) end
        return
    end
    local b = id and M.builds and M.builds[id]
    if not b then return end
    M.builds[id] = nil
    if k == "ak" then
        local msg = tostring(f[3] or ""):gsub("[%c|]", ""):sub(1, 80)
        buildDone(b, msg)
        log(string.format("shop: the host built your %s: %s", b.name, msg))
    else
        refundHere(b.price, b.name, "REFUSED: " .. upperText(f[3], 60))
    end
end
-- (a joiner) the host's allies summary in "rnd" (ALLY.roomCode: "m2w0s1") -> { m =, w =, s = } of what's in it, or nil
local function roomAlliesOf(v)
    if type(v) ~= "string" or v == "" or #v > 12 or v:gsub("[mwvs]%d%d?", "") ~= "" then return nil end
    local t = {}
    for k, n in v:gmatch("([mwvs])(%d+)") do                 -- (each letter once: m MOONCHILD, w SNIPER, v VOID WATCHER 1, s ships)
        if t[k] then return nil end
        t[k] = tonumber(n)
    end
    return t
end
-- (a joiner, sv_allies.lua ALLY.hudLine) the room's allied flights and ships, from the host's last "rnd" (5 s at most
-- old), or nil: not a joiner, nothing bought, or no word
function COOP.roomAllies()
    if not COOP.client() then return nil end
    local r = M.rnd
    return (r and r.allies and os.clock() - (r.got or 0) <= 5) and r.allies or nil
end
-- (the host, sv_allies.lua's COVER) allied planes `objs` cover player `slot`, a joiner who bought them (the user's co-op
-- run of 2026-10-30: COVER kept a joiner's flight near the host, the stock order's NearPlayer being your plane): each
-- onto one of the enemy planes nearest that player's real plane (Normal / TargetFirst, as COOP.huntReal's), within 2x
-- CFG.allies.orders cover_radius_m of it, or 4x for the flights sent onto that plane (huntReal's), those counted at half
-- their distance. -> planes ordered (0: none of their attackers in reach, or no real plane), the nearest one's km
function COOP.coverFor(slot, objs)
    local me = realTarget(slot)
    if not (me and D and D.up) then return 0 end
    local okL, at = pcall(function() return me:K2_GetActorLocation() end)
    if not (okL and at) then return 0 end
    local reach = ((CFG.allies.orders.cover_radius_m or 5000) * 100) * 2
    local c = {}
    for unit in pairs(D.up) do
        local u = M.units[unit]
        local on = M.huntOn and M.huntOn[unit] and M.huntOn[unit].slot == slot
        for i = 1, (u and u.n or 0) do
            local pl = u.planes[i]
            local b = pl and not pl.dead and M.byId[pl.id]
            if b and valid(b.obj) then
                local ok, l = pcall(function() return b.obj:K2_GetActorLocation() end)
                if ok and l then
                    local d = math.sqrt((l.X - at.X) ^ 2 + (l.Y - at.Y) ^ 2 + (l.Z - at.Z) ^ 2)
                    if d <= (on and reach * 2 or reach) then c[#c + 1] = { obj = b.obj, k = on and d * 0.5 or d, d = d } end
                end
            end
        end
    end
    if #c == 0 then return 0 end
    table.sort(c, function(a, b) return a.k < b.k end)
    local n, nearest = 0, math.huge
    for _, e in ipairs(c) do nearest = math.min(nearest, e.d) end
    for i, o in ipairs(objs or {}) do
        local e = c[(i - 1) % #c + 1]
        if valid(o) and pcall(function() o:EngagementOrderOverride(ORDER_NORMAL, e.obj, PRIO_TARGET_FIRST, 0, false, FIRE_BITS, false) end) then
            n = n + 1
        end
    end
    return n, nearest / 100000
end
local function onOrder(f, fromHost)
    local o = short(f[2], 16)
    local okL = false
    for _, x in ipairs(CFG.allies and CFG.allies.orders and CFG.allies.orders.list or {}) do if x == o then okL = true end end
    if not (okL and ALLY and ALLY.nextOrder) then return end
    if ALLY.order and ALLY.order() == o then return end
    pcall(ALLY.nextOrder, fromHost and "coop" or "a joiner", o)
end

---------------------------------------------------------------------------------------------------- host migration
-- (the user, 2026-10-31: "can we also set up a Host Migration system? so if the Host does leave, it automatically
-- tries to find the next best host"; their choices: the round in play starts again, the allies and defences are built
-- again, the best connection takes over.) While it's up, the host ranks its joiners by their link (round trip and the
-- share resent; players in the mission first) and tells everyone the order with each one's Steam ID ("sq"), and the
-- allies and defences up ("al"); before its level reloads at a run's end it says how long it'll be away ("hl"). A
-- joiner whose host has been silent [coop.migration] after_s goes down that order: if the first is itself it becomes
-- the host (it opens as host looking for everyone's Steam ID, takes over the run: the round in play again after
-- break_s, held up to wait_s while the others come back, the allies and defences built again), else it joins that one,
-- the next after link_s. Planes keep their owner (P.sid): one back in another slot has its plane moved with them
-- (SV_CoopSwapPP), a slot that's someone else's has the old plane set aside, hidden (never destroyed mid-level).
do
local ITEM_OK = { AAGun = true, SAM = true, Ciws = true, Wingmen = true, Moonchild = true, ShipAegis = true, VoidWatcher = true }
local function mig() return cfg().migration or {} end
local function sidOk(v) return type(v) == "string" and v:match("^%d+$") ~= nil and #v >= 15 and #v <= 20 end
function M.mySid()
    if not M.mySidV and type(SV_CoopInfo) == "function" then
        local v = tostring(SV_CoopInfo() or ""):match("me=(%d+)")
        if sidOk(v) then M.mySidV = v end
    end
    return M.mySidV
end
-- (the host) each linked game's Steam ID and link: { [slot] = { sid, rtt (ms), loss (share resent), up } }
function M.linkQuality()
    local q = {}
    local s = type(SV_CoopPeerIds) == "function" and tostring(SV_CoopPeerIds() or "") or ""
    for slot, sid, rtt, tx, rs, up in s:gmatch("(%d+):(%d+):(%-?%d+):(%d+):(%d+):([01])") do
        q[tonumber(slot)] = { sid = sid, rtt = tonumber(rtt), loss = tonumber(rs) / math.max(1, tonumber(tx)), up = up == "1" }
    end
    return q
end
-- (the host) the allies and defences up: "item:buyer's Steam ID" (0: yours, or none known), sorted
local function allyList()
    local R, out = ALLY and ALLY.run, {}
    if not R then return "" end
    for _, a in pairs(R.up or {}) do
        local item = a.kind == "ship" and ("Ship" .. tostring(a.key)) or (a.ally == "wingmen" and "Wingmen")
            or (a.ally == "awacs" and "VoidWatcher") or "Moonchild"
        local b = a.buyer and M.roster[a.buyer] and M.roster[a.buyer].sid or "0"
        -- ((0.73.78, plan G5) not VOID WATCHER 1 once its service is over: a new host doesn't bring a retired one back)
        if ITEM_OK[item] and not a.home then out[#out + 1] = item .. ":" .. b end
    end
    local dc = R.defCount or {}
    for kind, item in pairs({ aa = "AAGun", sam = "SAM", ciws = "Ciws" }) do
        for _ = 1, math.min(8, tonumber(dc[kind]) or 0) do out[#out + 1] = item .. ":0" end
    end
    table.sort(out)
    return table.concat(out, ",")
end
-- (the host, every 5 s) the line of succession and the allies up, sent when they change and every 30 s
local function hostShare(now)
    if now < (M.sqAt or 0) then return end
    M.sqAt = now + 5
    local me = M.mySid()
    if not me then return end
    if M.roster[0] then M.roster[0].sid = me end
    local q, list = M.linkQuality(), {}
    for s, r in pairs(M.roster) do
        local l = s ~= COOP.slot and q[s]
        if l and sidOk(l.sid) then
            r.sid = l.sid
            local P = M.peers[s]
            if l.up then
                list[#list + 1] = { s = s, sid = l.sid, score = (l.rtt >= 0 and l.rtt or 999) + 2000 * l.loss + ((P and P.fresh) and 0 or 10000) }
            end
        end
    end
    table.sort(list, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.s < b.s end)
    local parts, said = {}, {}
    for _, e in ipairs(list) do parts[#parts + 1] = e.s .. ":" .. e.sid; said[#said + 1] = string.format("%d (%.0f)", e.s + 1, e.score) end
    local order = table.concat(parts, ",")
    if order ~= M.sqSent or now >= (M.sqAgain or 0) then
        M.sqSent, M.sqAgain = order, now + 30
        send(true, "sq", me, order)
        if order ~= M.sqSaid then
            M.sqSaid = order
            log("coop: migration: the next hosts, best link first: " .. (#said > 0 and table.concat(said, ", ") or "none"))
        end
    end
    local al = allyList()
    if al ~= M.alSent or now >= (M.alAgain or 0) then M.alSent, M.alAgain = al, now + 30; send(true, "al", al) end
end
-- (the host) before its level reloads (a run's end): away for up to secs, the joiners wait that long
function COOP.hostAway(secs)
    if COOP.host() then send(true, "hl", string.format("%d", math.floor(secs))) end
end
-- (a joiner) the host's line of succession, allies, time away
function M.onSuccession(f)
    if not sidOk(f[2]) then return end
    local list = {}
    for s, sid in tostring(f[3] or ""):gmatch("(%d+):(%d+)") do
        local n = tonumber(s)
        if slotOk(n) and n ~= 0 and sidOk(sid) and #list < MAX_SLOT then list[#list + 1] = { slot = n, sid = sid } end
    end
    M.succ, M.hostSid = list, f[2]
    if M.roster[0] then M.roster[0].sid = f[2] end
end
function M.onAllies(f)
    local list = {}
    for item, sid in tostring(f[2] or ""):gmatch("(%a+):(%d+)") do
        if ITEM_OK[item] and #list < 40 then list[#list + 1] = { item = item, sid = sid ~= "0" and sid or nil } end
    end
    M.allyList = list
end
function M.onHostAway(f)
    local secs = tonumber(f[2])
    if secs and secs > 0 and secs <= 300 then
        M.hostAwayUntil = os.clock() + secs
        log(string.format("coop: migration: the host's reloading, waited for up to %d s", secs))
    end
end
-- a player's plane here set aside, hidden and unbound (a live player plane is never destroyed mid-level). (0.73.77) The
-- rejoin's M.setAside: tick and collision off, moved up, and a real one moved out of its slot in the runtime: kept there,
-- the next player's real plane in that slot (SV_CoopSpawnPP) destroyed it, the crash this rule keeps away
function M.retirePeer(s, why)
    local P = M.peers[s]
    M.peers[s] = nil
    if not (P and P.obj and valid(P.obj)) then return end
    if not M.setAside(s, P, why) then
        pcall(function() P.obj:SetActorHiddenInGame(true) end)
        pcall(function() P.obj:SetActorEnableCollision(false) end)
        if type(SV_CoopPeer) == "function" then SV_CoopPeer(s, 0) end
        local radar = M.radarOff(P)
        log(string.format("coop: player %d's plane here set aside, hidden (%s)%s", s + 1, why, radar and ("; " .. radar) or ""))
    end
end
-- (every tick, before the planes) each player's real plane in their slot: one in another moves with them (from this
-- game's own slot too: it was theirs before this game took it), one that's another player's now is set aside; one left
-- in this game's own slot is hidden at once (its slot's never ticked) and set aside 10 s on if its player hasn't turned
-- up. (An AI stand-in is its slot's unit, SV_Unit_CoopPeer<A-X>: it stays, flown from whoever has the slot now.)
function M.slotFix()
    local me = COOP.slot
    for s, r in pairs(M.roster) do
        local sid, P = r.sid, M.peers[s]
        if s ~= me and sidOk(sid) and not (P and P.sid == sid) then
            local moved = false
            for t, Q in pairs(M.peers) do
                if t ~= s and Q.real and Q.sid == sid and Q.obj then
                    M.peers[s], M.peers[t] = Q, P
                    if type(SV_CoopSwapPP) == "function" then SV_CoopSwapPP(s, t); M.slotSwapped(s, t) end   -- ((0.73.77) what's kept per slot too)
                    Q.shown, Q.ownSlotAt = nil, nil
                    if P then P.shown = nil end
                    log(string.format("coop: player %d is back as player %d: their plane here moved with them", t + 1, s + 1))
                    moved = true
                    break
                end
            end
            if not moved and P and P.real and P.obj and P.sid and P.sid ~= sid then M.retirePeer(s, "the slot is another player's now") end
        end
    end
    local P = me and M.peers[me]
    if P and P.real and P.obj then
        if not P.ownSlotAt then
            P.ownSlotAt = os.clock()
            pcall(function() P.obj:SetActorHiddenInGame(true) end)
            pcall(M.radarOff, P)                         -- ((0.73.83) its blip too)
        elseif os.clock() - P.ownSlotAt >= 10 then
            M.retirePeer(me, "it was in this game's slot, and its player isn't back")
        end
    end
end
local function sidName(sid)
    for _, r in pairs(M.roster) do if r.sid == sid and r.name and r.name ~= "" then return r.name end end
    return nil
end
local becomeHost
local function nextCandidate(now)
    local mg = M.mig
    mg.i = mg.i + 1
    local e = mg.list[mg.i]
    if not e then
        log("coop: migration: none of the next hosts answered; looking for a host as before")
        callout("CO-OP: NO NEW HOST FOUND", "LOOKING FOR A HOST AS BEFORE")
        M.mig, M.hostLostAt = nil, nil
        COOP.reopen("join", "host migration: no next host answered", (mg.oldSid and (mg.oldSid .. ",") or "") .. tostring(cfg().partner or "auto"))
        return
    end
    mg.cand, mg.candAt, mg.candName = e, now, mg.names[e.sid] or ("PLAYER " .. (e.slot + 1))
    if e.sid == M.mySid() then return becomeHost(now) end
    log(string.format("coop: migration: joining %s, the next host (%d of %d in line)", mg.candName, mg.i, #mg.list))
    callout("CO-OP: " .. string.upper(mg.candName) .. " TAKES OVER", "JOINING THEIR GAME...")
    COOP.reopen("join", "host migration", e.sid)
end
becomeHost = function(now)
    local mg, me, c = M.mig, M.mySid(), mig()
    local partners, expect = {}, {}
    for _, e in ipairs(mg.list) do
        if e.sid ~= me then partners[#partners + 1] = e.sid; expect[e.sid] = mg.names[e.sid] or ("PLAYER " .. (e.slot + 1)) end
    end
    partners[#partners + 1] = "auto"
    log(string.format("coop: migration: this game is the next host (%d of %d in line); the others are joining it", mg.i, #mg.list))
    COOP.reopen("host", "host migration", table.concat(partners, ","))
    mg.hosting, mg.expect, mg.hostAt = true, expect, now
    if LB and LB.coopTakeover then pcall(LB.coopTakeover) end   -- ((0.73.77, plan H2) the co-op run's record goes on here)
    killAllCopies("host migration")
    M.retirePeer(0, "the old host's: you're the host now")
    -- the round: the one in play again (between rounds, the next), break_s on and once everyone's back (joinWaiting).
    -- A new D: the next co-op tick sets everything up as a new level's (the units, the copies, "rs").
    local old = D
    local first = (mg.state == "wait") and (mg.round or 0) or math.max(0, (mg.round or 1) - 1)
    D = { round = first, startRound = old and old.startRound or (first + 1), state = "wait", at = ((old and old.now) or 0) + (c.break_s or 15),
          now = old and old.now, queue = {}, spare = {}, up = {}, flown = {}, announced = false, perf = old and old.perf }
    M.rnd = nil
    mg.rebuild, mg.rebuildAt = {}, now + 5
    for _, a in ipairs(M.allyList or {}) do mg.rebuild[#mg.rebuild + 1] = { item = a.item, sid = a.sid, tries = 0 } end
    log(string.format("coop: migration: round %d starts again once everyone's back (up to %d s), %d allies and defences to build again",
        first + 1, c.wait_s or 60, #mg.rebuild))
    callout("YOU ARE THE NEW HOST", string.format("ROUND %d STARTS ONCE EVERYONE'S BACK", first + 1))
end
-- (a host by migration) the allies and defences again, then done
local function afterTakeover(now)
    local mg, c = M.mig, mig()
    if mg.rebuild and now >= (mg.rebuildAt or 0) then
        mg.rebuildAt = now + 3
        for i = #mg.rebuild, 1, -1 do
            local a = mg.rebuild[i]
            local buyer = nil
            for s, r in pairs(M.roster) do if s ~= COOP.slot and a.sid and r.sid == a.sid then buyer = s end end
            local it = CFG.shop and CFG.shop.items and CFG.shop.items[a.item]
            local kind = it and (it.role == "aa" or it.role == "sam" or it.role == "ciws") and it.role or nil
            local okB, ok, msg = false, false, "NOT AVAILABLE"
            if type(shopBuildFor) == "function" then okB, ok, msg = pcall(shopBuildFor, buyer, a.item, 0, kind) end
            a.tries = a.tries + 1
            if okB and ok then
                table.remove(mg.rebuild, i)
                log(string.format("coop: migration: %s built again%s: %s", a.item, buyer and (" for player " .. (buyer + 1)) or "", tostring(msg)))
            elseif a.tries >= 10 then
                table.remove(mg.rebuild, i)
                log(string.format("coop: migration: %s NOT built again (%s)", a.item, okB and tostring(msg) or ("error " .. tostring(ok))))
            end
        end
        if #mg.rebuild == 0 then mg.rebuild = nil end
    end
    if not mg.rebuild and now - (mg.hostAt or now) >= (c.wait_s or 60) then
        log(string.format("coop: migration over: %d players with this game as the host", playerCount()))
        M.migratedFrom, M.mig = mg.oldSid, nil
    end
end
-- (a host by migration that nobody joined, hearing another host: its own link had dropped and the old host is still
-- there) it joins it again. Whether it did.
function M.migStepBack()
    local old = (M.mig and M.mig.hosting and M.mig.oldSid) or M.migratedFrom
    if not old then return false end
    log("coop: migration: nobody joined this game and another host is there: joining it again (this game's link had dropped)")
    callout("CO-OP: THE HOST'S STILL THERE", "JOINING THEM AGAIN")
    M.mig, M.migratedFrom, M.hostLostAt = nil, nil, nil
    COOP.reopen("join", "host migration undone", old .. "," .. tostring(cfg().partner or "auto"))
    return true
end
-- every tick: the host shares, a joiner watches its host, a migration goes on
function M.migTick(now)
    local c = mig()
    if not c.enabled or tostring(cfg().transport or "steam") ~= "steam" then return end
    if COOP.host() then
        hostShare(now)
        if M.mig and M.mig.hosting then afterTakeover(now) end
        return
    end
    if not (COOP.client() and D) then return end
    local mg = M.mig
    if mg then
        if M.state == "linked" then
            log(string.format("coop: migration: linked to %s, the new host", tostring(mg.candName)))
            callout("CO-OP: NEW HOST", string.upper(tostring(mg.candName)) .. " IS HOSTING")
            M.mig, M.hostLostAt = nil, nil
        elseif now - (mg.candAt or now) >= (c.link_s or 20) then
            log(string.format("coop: migration: %s didn't answer in %d s", tostring(mg.candName), c.link_s or 20))
            nextCandidate(now)
        end
        return
    end
    if not (M.hostLostAt and M.succ and #M.succ > 0) then return end
    local wait = c.after_s or 30
    if M.hostAwayUntil and M.hostAwayUntil > M.hostLostAt then wait = math.max(wait, M.hostAwayUntil - M.hostLostAt) end
    if now - M.hostLostAt < wait then return end
    local list, names = {}, {}
    for _, e in ipairs(M.succ) do
        if e.sid ~= M.hostSid then list[#list + 1] = e; names[e.sid] = sidName(e.sid) or ((M.roster[e.slot] or {}).name) end
    end
    if M.mySid() then names[M.mySid()] = M.myName end
    local oldName = playerName(0)
    M.mig = { list = list, names = names, i = 0, oldSid = M.hostSid, round = D.round, state = D.state, at = now }
    log(string.format("coop: migration: the host (%s) silent %.0f s: going down the line of %d", oldName, now - M.hostLostAt, #list))
    callout("CO-OP: " .. string.upper(oldName) .. " (HOST) IS GONE", "FINDING THE NEXT HOST...")
    nextCandidate(now)
end
end

local function onHostMessage(from, f)
    local k = f[1]
    if k == "hi" then
        local ver, rt, row, name = short(f[2], 32), short(f[3], 16), short(f[4], 64), short(f[5], 32)
        local code = short(f[6], 16):match("^%w+$") or ""          -- (their airframe's code: COOP2MP T3)
        local lo = loadoutOk(f[7]) and f[7] or ""                  -- (their loadout: COOP2MP T4b)
        local pt = paintOk(f[8]) and f[8] or ""                    -- (their paint: T5)
        local ac = acClean(f[9])                                    -- (their aircraft's name)
        -- ((0.73.80) a plane with no stock code: its blueprint class's path (a player plane's, /Game/ only) and stock base)
        local cls = M.clsOk(f[10], code) and f[10] or ""
        local base = M.baseOk(f[11]) and f[11]:lower() or ""
        if not name or name == "" then name = (M.linkNames and M.linkNames[from]) or ("PLAYER " .. (from + 1)) end
        local first, was = not M.roster[from], M.roster[from] and M.roster[from].row
        local q = M.linkQuality and M.linkQuality()[from]                -- (their Steam ID, from their link: host migration)
        M.roster[from] = { row = row or "", ver = ver, name = name, code = code, lo = lo, paint = pt, ac = ac,
                           sid = q and q.sid ~= "0" and q.sid or nil, cls = cls, base = base }
        if first then
            log(string.format("coop: player %d is %s, Survival %s, runtime %s, flies %s", from + 1, tostring(name), tostring(ver),
                tostring(rt), (row and row ~= "") and row or "(not yet: no plane)"))
            callout(string.upper(tostring(name)) .. " JOINED", string.format("PLAYERS %d/%d", playerCount(), maxPlayers()))
            if ver ~= VERSION then
                log("coop: WARNING: player " .. (from + 1) .. " runs Survival " .. tostring(ver) .. ", you " .. VERSION)
                callout("CO-OP VERSION MISMATCH", string.upper(tostring(name)) .. " HAS " .. tostring(ver))
            end
            -- (a zip unpacked with the game open leaves the old main.dll in place; SV_Version() answers the build's own
            -- version from runtime 0.28.4: before it, a fixed "0.27.0" for every build)
            local mine = type(SV_Version) == "function" and SV_Version() or nil
            if mine and rt and rt ~= "" and rt ~= "?" and rt ~= mine then
                log("coop: WARNING: player " .. (from + 1) .. " runs runtime " .. tostring(rt) .. ", you " .. tostring(mine)
                    .. " (their dlls/main.dll is another build's: unzip again with the game closed)")
                callout("CO-OP RUNTIME MISMATCH", string.upper(tostring(name)) .. " HAS MAIN.DLL " .. tostring(rt))
            end
            local okS, errS = pcall(M.sendSettings, from)
            if not okS then log("coop: settings not sent: " .. tostring(errS)) end
        elseif row and row ~= "" and row ~= was then
            local P = M.peers[from]
            log(string.format("coop: player %d flies %s%s", from + 1, row, (P and P.obj and P.row and P.row ~= standInRow(row))
                and string.format(" (their plane here stays %s until their next sortie)", P.row) or ""))
        end
        hostRosterSelf()
    elseif k == "jn" then hostSync(from)
    elseif k == "ht" then hostHit(from, tonumber(f[2]) or 0, tonumber(f[3]) or 0)
    elseif k == "ab" then onBuildAsk(from, f)            -- a joiner's ally / defence bought: built here, for everyone
    elseif k == "ao" then onOrder(f, false)              -- a joiner changed the allies' orders
    elseif k == "fx" then M.fxFromJoiner(from, f)       -- a joiner's shots: its plane here fires them, the others told
    elseif (k == "dw" or k == "rv") and DOWN and DOWN.onHost then DOWN.onHost(from, f)   -- (down, a revive: sv_down.lua)
    elseif k == "lb" and LB and LB.coopMsg then LB.coopMsg(f, from)   -- ((0.73.77, plan H2) a joiner's leaderboard name)
    elseif k == "in" then                                -- a joiner's intensity (sv_director.lua P4), once a second
        local i, c = inNum(f[2], 100), inNum(f[3], 100)
        local now = os.clock()
        M.ints = M.ints or {}
        local last = M.ints[from]
        if slotOk(from) and from ~= COOP.slot and i and c and not (last and now - last.at < IN_MIN_GAP_S) then
            M.ints[from] = { i = i, c = c, hp = inNum(f[4], 100), m = inNum(f[5], IN_MSL_MAX), at = now }
        end
    end
end

local function onJoinerMessage(f)
    local k = f[1]
    if k == "cf" then M.onSettings(f)
    elseif k == "fx" then M.fxFromHost(f)               -- a player's shots (the host's, or a joiner's relayed)
    elseif k == "ak" or k == "ax" or k == "ar" then onBuildAnswer(f)   -- the host's say on your ally / defence
    elseif k == "ag" then onOrder(f, true)               -- the allies' orders (the room's: the host's)
    elseif k == "sq" then M.onSuccession(f)              -- host migration: the next hosts, best link first
    elseif k == "al" then M.onAllies(f)                  -- host migration: the allies and defences up
    elseif k == "hl" then M.onHostAway(f)                -- host migration: the host's reloading (a run's end)
    elseif k == "lb" and LB and LB.coopMsg then LB.coopMsg(f)   -- ((0.73.77, plan H2) the co-op run's squad: sv_leaderboard.lua)
    elseif k == "hq" then                                -- the host has no hello from you (peerTick): again, once a second
        if os.clock() >= (M.hqAt or 0) then
            M.hqAt = os.clock() + 1
            sendHi()
            once("hq", "coop: the host asked for your hello (it had none from you): sent")
        end
    elseif (k == "dw" or k == "rb" or k == "rx" or k == "ro" or k == "rc") and DOWN and DOWN.onJoiner then
        -- ((0.73.77, plan A9) the host's run-over while this level still loads: it comes again with the host's picture,
        -- asked for once this game's plane is in the level)
        if k == "ro" and not D then log("coop: the host's run is over (round " .. short(f[2], 8) .. "); this level is still loading: it comes again once it's in") end
        DOWN.onJoiner(f)                                 -- (sv_down.lua)
    elseif k == "rnd" then
        local lv = tonumber(f[8])                         -- (the intensity director's level, P4: a whole 0-3, else none)
        if not (lv and lv == math.floor(lv) and lv >= 0 and lv <= #SPIKE_SUFFIX) then lv = nil end
        local gp = tonumber(f[9])                         -- (AB.L..IN's phase, P7: 1-3, else none)
        if not (gp == 1 or gp == 2 or gp == 3) then gp = nil end
        local sk = tostring(f[11] or ""):match("^%a+$")    -- ((0.73.77, plan D3) the round's special there: a word, or none)
        if sk and #sk > 16 then sk = nil end
        -- ((0.73.77, D4) the special in play there and its state: two words, or none)
        local hk, hst = tostring(f[12] or ""):match("^(%a+):(%a+)$")
        local hs = (hk and #hk <= 16 and #hst <= 16) and { kind = hk, state = hst } or nil
        M.rnd = { round = tonumber(f[2]) or 0, state = f[3], secs = tonumber(f[4]) or 0, wave = tonumber(f[5]) or 0,
                  waves = tonumber(f[6]) or 0, alive = tonumber(f[7]) or 0, level = lv, glitchPhase = gp, got = os.clock(),
                  allies = roomAlliesOf(f[10]), special = sk, hostSpecial = hs }
        -- ((0.73.78, plan G5) the room's VOID WATCHER 1 purchases (the host's count): this game's STORE prices it from it,
        -- as the host checks a joiner's ask)
        local vb = tonumber(f[13])
        if vb and vb == math.floor(vb) and vb >= 0 and vb <= 999 and RUN and RUN.bought and (RUN.bought.VoidWatcher or 0) ~= vb then
            RUN.bought.VoidWatcher, RUN.dirty = vb, true
            log(string.format("coop: VOID WATCHER 1 bought %d times in the room (the host's count): the STORE's price here from it", vb))
        end
        -- ((0.73.78) the room's other allies and defences (f14, "<item>:<n>,...;<kind>:<n>,..."): this game's STORE
        -- prices them from the host's counts, as the host checks a joiner's ask (sv_shop.lua shopBuildFor)
        local fa, fd = tostring(f[14] or ""):match("^([%w:,]*);([%a%d:,]*)$")
        if fa and RUN and RUN.bought then
            local seen = {}
            for nm, n in fa:gmatch("(%a+):(%d+)") do seen[nm] = math.min(999, tonumber(n)) end
            for _, nm in ipairs(M.ROOM_ITEMS) do
                local n = seen[nm] or 0
                if (RUN.bought[nm] or 0) ~= n then
                    RUN.bought[nm], RUN.dirty = n, true
                    log(string.format("coop: %s bought %d times in the room (the host's count): the STORE's price here from it", nm, n))
                end
            end
            RUN.defences = RUN.defences or { built = 0, bought = {} }
            local dseen = {}
            for kd, n in fd:gmatch("(%a+):(%d+)") do dseen[kd] = math.min(999, tonumber(n)) end
            for kd, n in pairs(dseen) do
                if (RUN.defences.bought[kd] or 0) ~= n then
                    RUN.defences.bought[kd], RUN.dirty = n, true
                    log(string.format("coop: the airfield's %s built %d times in the room (the host's count): its price here from it", kd, n))
                end
            end
        end
    elseif k == "pi" then
        local s = tonumber(f[2])
        if not slotOk(s) then return end
        f[3], f[4], f[5] = short(f[3], 64), short(f[4], 32), short(f[5], 32)
        local first, was = not M.roster[s], M.roster[s] and M.roster[s].row
        local sid = tostring(f[10] or ""):match("^%d+$")
        local code = short(f[6], 16):match("^%w+$") or ""
        M.roster[s] = { row = f[3], ver = f[4], name = f[5], code = code,
                        lo = loadoutOk(f[7]) and f[7] or "", paint = paintOk(f[8]) and f[8] or "", ac = acClean(f[9]),
                        sid = (sid and #sid >= 15 and #sid <= 20) and sid or nil,
                        -- ((0.73.80) after the Steam ID: a plane with no stock code's class path and stock base)
                        cls = M.clsOk(f[11], code) and f[11] or "", base = M.baseOk(f[12]) and f[12]:lower() or "" }
        if not first and s ~= COOP.slot and f[3] and f[3] ~= "" and f[3] ~= was then
            local P = M.peers[s]
            log(string.format("coop: player %d flies %s%s", s + 1, f[3], (P and P.obj and P.row and P.row ~= standInRow(f[3]))
                and string.format(" (their plane here stays %s until their next sortie)", P.row) or ""))
        end
        if first and s ~= COOP.slot then
            log(string.format("coop: player %d is %s (Survival %s, flies %s)", s + 1, tostring(f[5]), tostring(f[4]), tostring(f[3])))
            if s == 0 then
                callout("CO-OP LINKED", string.upper(tostring(f[5])) .. " IS HOSTING")
                if f[4] ~= VERSION then callout("CO-OP VERSION MISMATCH", "YOU " .. VERSION .. ", THE HOST " .. tostring(f[4])) end
            else
                callout(string.upper(tostring(f[5])) .. " JOINED", string.format("PLAYERS %d/%d", playerCount(), maxPlayers()))
            end
        end
    elseif k == "po" then
        local s = tonumber(f[2])
        if s and M.roster[s] then
            callout(string.upper(playerName(s)) .. " LEFT", nil)
            M.roster[s] = nil
        end
        if slotOk(s) then M.markLeft(s, "left") end       -- ((0.73.77, plan C1) back in another aircraft: a new plane here)
    elseif k == "rj" then                                -- ((0.73.77) a player's game started over: the same, plan C1)
        local s = tonumber(f[2])
        if slotOk(s) then M.markLeft(s, "started their game over") end
    elseif k == "af" and AF then
        local down = f[4] == "1"
        AF.hp, AF.full, RUN.dirty = tonumber(f[2]) or AF.hp, tonumber(f[3]) or AF.full, true
        if down ~= (AF.down or false) then
            AF.down = down
            if type(SV_Event) == "function" then SV_Event(down and "RE_SV_AirfieldClose" or "RE_SV_AirfieldOpen") end
            log("coop: the host's airfield is " .. (down and "down: landing closed" or "back up: landing open"))
        end
    elseif k == "co" then
        if cfg().callouts then M.noMirror = true; pcall(hudCallout, short(f[2], 120), f[3] ~= "" and short(f[3], 120) or nil, f[4] == "1"); M.noMirror = false end
    elseif k == "tl" then                                -- a tell (sv_tells.lua): an id this game knows, a number
        local id, a = short(f[2], 32), tonumber(f[3])
        local now = os.clock()
        if now - (M.tlAt or -1) >= 1 then M.tlAt, M.tlN = now, 0 end
        M.tlN = M.tlN + 1                                -- (at most TL_PER_S a second; tells are dropped, never queued:
        if M.tlN <= TL_PER_S and TELL and TELL.known(id) and levelReady()   -- a late one misleads; [coop] callouts is the
            and (a == nil or finite(a, 1e6)) then                           -- host's banners, tells are radio lines)
            local okT, errT = pcall(TELL.play, id, a, "the host")
            if not okT then once("tl", "coop: tell error " .. tostring(errT)) end
        end
    elseif k == "dv" then                                -- the director's event on this game's copies (COOP.dispatch)
        local ev, unit, delay = short(f[2], 64), short(f[3], 96), tonumber(f[4])
        local now = os.clock()
        if now - (M.dvAt or -1) >= 1 then M.dvAt, M.dvN = now, 0 end
        M.dvN = M.dvN + 1                                -- (dropped, never queued past the delay: a late shot misleads)
        local why = (M.dvN > DV_PER_S and "more than " .. DV_PER_S .. " a second") or (not dvName(ev) and "not a director event")
            or (not (delay and finite(delay, 1e6)) and "a bad delay") or (not (D and rawEvent and levelReady()) and "this level isn't ready")
            or (not dvCopy(ev, unit) and "no live copy of it here") or nil
        if why then
            once("dv" .. why, "coop: the host's director event " .. ev .. " dropped (" .. why .. ")")
        else
            M.dvQ = M.dvQ or {}
            if #M.dvQ < 32 then M.dvQ[#M.dvQ + 1] = { at = now + math.max(0, math.min(DV_MAX_S, delay)), name = ev, unit = unit } end
        end
    elseif k == "cr" then
        local n = tonumber(f[2]) or 0
        if finite(n, math.huge) and n > 0 and n <= CREDITS_MAX then
            if M.noDownBonus() then log("revive: the host's round bonus (" .. math.floor(n) .. ") not paid: you're down (down_round_bonus off)")
            else addCredits(math.floor(n), short(f[3], 80) .. " (the host's round)") end
        end
    elseif k == "sp" then
        local unit, pose, ops = short(f[2], 96), nil, {}
        if f[3] and f[3] ~= "-" then
            local p = {}
            for v in f[3]:gmatch("[^,]+") do p[#p + 1] = tonumber(v) end
            if #p == 4 and finite(p[1], 1e10) and finite(p[2], 1e10) and finite(p[3], 1e10) and finite(p[4], 1e6) then pose = p end
        end
        if f[4] and f[4] ~= "-" then
            for op in f[4]:gmatch("[^;]+") do
                local row, idx = op:match("^(.-)@(-?%d+)$")
                if row then ops[#ops + 1] = { row = row, idx = tonumber(idx) } end
            end
        end
        local gen = tonumber(f[6]) or 0
        local rp = M.rep
        local rep = rp ~= nil and not rp.done                 -- ((0.73.73) part of the host's picture: a repair's)
        if rep then rp.units[unit] = { gen = gen, alive = {}, galive = {} } end
        M.spawnQ[#M.spawnQ + 1] = { unit = unit, pose = pose, ops = ops, level = tonumber(f[5]), gen = gen, rep = rep }
    elseif k == "bd" then
        local unit, gen, ord, id = short(f[2], 96), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
        if not M.bdLast or (M.bdLastN or 0) > 512 then M.bdLast, M.bdLastN = {}, 0 end   -- (the last generation's
        local bl = M.bdLast[unit]                                                         -- ids per unit: strayTick's
        if not bl or bl.gen ~= gen then                                                   -- bound line; capped)
            if not bl then M.bdLastN = M.bdLastN + 1 end
            bl = { gen = gen, n = 0 }; M.bdLast[unit] = bl
        end
        bl.n = bl.n + 1
        if not (gen and ord and id) then return end
        M.dead[id] = nil                                 -- ((0.73.73) named by the host now: up, until its "dn" says not)
        repNote(unit, gen, id, ord, nil)
        local cu = M.cunits[unit]
        if not cu or cu.gen ~= gen then
            -- (its spawn here still to come, queued or not yet sent: kept for it, not dropped. The co-op run of 2026-10-30:
            -- a joiner still loading as the host's round came in got 1 bind of 4, and its other copies flew on by their own
            -- AI. (0.73.73) Never as an empty flight of that generation in M.cunits: it took the place of the copies still up
            -- here, which doSpawn then never took down, and the host's spawn was refused: "its last flight is still up")
            pendKeep(unit, gen, "binds", ord, id)
            return
        end
        local o, c = cu.planes[ord], M.copies[id]
        -- (0.73.73 review) a copy kept through a repair (rs|j) may have been freed since: bindCopy calls into it
        -- (SetMinHealth), which a pcall can't catch on a freed object: checked live first, as "gd" does
        local oa = o and live(o)
        if o and not oa then cu.planes[ord] = nil; o = nil end
        if o and M.rep and not M.rep.done and not (c and c.addr == oa) then M.rep.rebound = M.rep.rebound + 1 end
        cu.binds[ord] = id
        if o then bindCopy(id, o, unit, ord) end
    elseif k == "gd" then                                -- a ship's, vehicle's or part's id (hostGround)
        local unit, gen, key, id = short(f[2], 96), tonumber(f[3]), short(f[4], 96), tonumber(f[5])
        if not (gen and id and id >= 1 and id <= 65535 and id == math.floor(id)) then return end
        M.dead[id] = nil                                 -- ((0.73.73) as a plane's "bd")
        repNote(unit, gen, id, nil, key)
        local cu = M.cunits[unit]
        if not cu or cu.gen ~= gen then pendKeep(unit, gen, "gbinds", key, id); return end   -- (as a plane's "bd")
        cu.gbinds = cu.gbinds or {}
        cu.gbinds[key] = id
        local o = cu.gobjs and cu.gobjs[key]
        if o and live(o) then bindGround(id, o, unit, key) end
    elseif k == "hp" then
        -- ((0.73.77, plan A2) never onto a copy that's down here: 0.73.76 wrote the host's health back onto wrecks,
        -- invisible enemies with target boxes no hit could finish; each one skipped is counted for the sync report)
        for id, h in (f[2] or ""):gmatch("(%d+):(%-?%d+)") do
            local c = M.copies[tonumber(id)]
            h = tonumber(h)
            if c and h and h > 0 and live(c.obj) then
                local own = health(c.obj)
                if own and own <= 0 then
                    M.cnt.hpDead = M.cnt.hpDead + 1
                elseif own then
                    local v = math.min(math.max(h, 1), 2147483647)
                    -- ((0.73.79) a hit here not yet sent (it landed since clientTick's last look) stays on it: 0.73.78
                    -- wrote the host's health over it and set what's expected to match, so clientTick never saw the
                    -- loss and it was never sent. And for a moment after a hit was sent, the host's health from before
                    -- it landed doesn't put the copy back up (it flickered back to full on every hit)
                    local pend = (not c.ally and c.exp and own < c.exp) and (c.exp - own) or 0
                    if pend == 0 and v > own and c.sentAt and c.sentFrom and v <= c.sentFrom   -- (no more than it had
                        and os.clock() - c.sentAt < HP_HOLD_S then                               -- before: from before it)
                        c.hp = v                               -- (held: the host's next "hp" has your hit in it)
                        M.cnt.hpHeld = (M.cnt.hpHeld or 0) + 1
                    else
                        local w = v - pend
                        if pend > 0 and w < FLOOR_IN then w = FLOOR_IN end
                        pcall(function() c.obj.HealthInternal = w end)
                        c.exp, c.hp = v, v                     -- (hp: the host's own, an ally's copy put back to it)
                        if w > FLOOR_IN then floorDone(c) end  -- (off the floor: the host's has more than you sent)
                    end
                end
            end
        end
    elseif k == "dn" then
        local id = tonumber(f[2])
        if id then
            M.dead[id] = true
            local rp = M.rep
            local r = rp and not rp.done and rp.ids[id]       -- (the host's picture: down there)
            local pu = r and rp.units[r.unit]
            if pu then if r.ord then pu.alive[r.ord] = nil else pu.galive[r.key] = nil end end
            local c = M.copies[id]
            if c then
                -- ((0.73.77, economy C1) who made the kill, named by the host (field 4: a player's slot; a, s, d: the allies,
                -- the allied ships, the airfield's defences): this game's pay for it goes by it (KILL.by, M.killerOf))
                if f[3] ~= "r" and c.addr and f[4] and f[4] ~= "" then
                    M.killer = M.killer or {}
                    M.killer[c.addr] = { code = short(f[4], 2), at = os.clock() }
                end
                floorDone(c)                                   -- ((0.73.77, A6) its wait at the floor, if it had one)
                -- ((0.73.73) forced: the host's is down, invincible here or not; "dn|<id>|r", a death the host's picture
                -- repeats, is long since: not this game's kill. Off its flight's planes here: strayTick counted it a stray)
                -- ((0.73.80) yours (the host named this game's player): with your plane as its cause, M.dnKill)
                M.dnKill(id, c, f)
                M.copies[id] = nil
                local cu = c.unit and M.cunits[c.unit]
                if cu and c.ord and cu.planes[c.ord] and addrOf(cu.planes[c.ord]) == c.addr then cu.planes[c.ord] = nil end
                if cu and c.key and cu.gobjs and cu.gobjs[c.key] and addrOf(cu.gobjs[c.key]) == c.addr then cu.gobjs[c.key] = nil end
            end
        end
    elseif k == "ev" then
        local unit = (f[3] and f[3] ~= "") and short(f[3], 96) or nil   -- ((0.73.73) a replay for that unit's fresh copy)
        if mirroredEvent(f[2]) and D and rawEvent and not levelReady() then    -- (held until this level is ready)
            M.evQ = M.evQ or {}
            if #M.evQ < 64 then M.evQ[#M.evQ + 1] = { name = short(f[2], 64), at = os.clock(), unit = unit } end
        elseif mirroredEvent(f[2]) and D and rawEvent and not keptThrough(unit, f[2]) then
            hostEvent(f[2])
        end
    elseif k == "wd" and COOP.client() then              -- ((review of 27097b9, finding 3) a flight the host took off: COOP.withdrawn
        local unit = short(f[2], 96)
        if unit ~= "" and flightWithdrawn then
            log(string.format("coop: the host took %s off (withdrawn, no despawn event): %d of its copies here off, unpaid",
                unit, flightWithdrawn(unit)))
        end
    elseif k == "db" and COOP.client() then              -- ((0.73.77, I2: S9) the host's penalty: off your zollars too
        local n = tonumber(f[2]) or 0
        if finite(n, math.huge) and n > 0 and n <= CREDITS_MAX and SPORT and SPORT.debit then
            SPORT.debit(math.floor(n), short(f[3], 80), true)
        end
    elseif k == "spx" and COOP.client() then             -- ((0.73.77, I7: S12) the host's Spaceport: its row, a retake due)
        if SPORT and SPORT.fromHost then
            local okS, errS = pcall(SPORT.fromHost, short(f[2], 400))
            if not okS then once("spx", "coop: the host's Spaceport state not read: " .. tostring(errS)) end
        end
    elseif k == "vm" and COOP.client() then              -- ((0.73.76) the host's VALKA mood: the red sky and her song here too)
        M.valkaHere(f[2] == "1", "the host's")           -- ((0.73.77) said when it can't be here too: D2)
    elseif k == "vr" and COOP.client() then              -- ((0.73.76) she shows: her X-02S on this game's copy of her)
        local unit = short(f[2], 96)
        if D and unit == (CFG.specials.valka and CFG.specials.valka.unit) then M.vr = { unit = unit, at = os.clock(), st = {} } end
    elseif k == "rz" then                                -- ((0.73.73) the end of the host's picture: what's here settled)
        if M.rep and not M.rep.done then repairDone("rz") end
    elseif k == "rs" then
        M.cnt.rsGot = M.cnt.rsGot + 1
        -- ((0.73.73) "rs|j": the host's answer to this game's own "jn", a repair: nothing torn down, no new run here,
        -- nobody DOWN brought back, the round's records kept)
        if f[2] == "j" then return onResync() end
        -- "rs|n": the host's new run; "rs|m": a host by migration in its level (the same run, the round in play again);
        -- a bare "rs" (before 0.73.73): the host's new run, or its answer to this game's own "jn" of the last 15 s
        local resync = f[2] == "m" or ((f[2] == nil or f[2] == "") and M.jnAt ~= nil and os.clock() - M.jnAt < 15)
        M.evQ, M.dvQ, M.holdQ = nil, nil, nil
        -- ((0.73.77, plan D2) VALKA's mood off here: the host's picture says it again if she's still up there)
        if M.vmHere then M.valkaHere(false, resync and (f[2] == "m" and "a new host's level" or "the host's resync") or "the host's run started over") end
        killAllCopies(resync and (f[2] == "m" and "a new host's level" or "the host's resync") or "the host's run started over")
        -- ((0.73.73) only the host's new run brings a player who's DOWN back: Shazzy, A02 11:26:02, "revive: back (the host's
        -- run started over) after 81 s down" on the answer to his own "jn", and A09, A10, A12 the same)
        if not resync and DOWN and DOWN.reset then pcall(DOWN.reset, "the host's run started over") end
        -- (the measurements, sv_stats.lua: the open round ends here, not at the host's next round number; the host's new run
        -- ends the run's records too)
        if STATS and D then pcall(STATS.hostReset, D.now, resync) end
        -- (the host's new run: the money and gear start over here too)
        if D and not resync and type(newRunHere) == "function" then
            local okN, errN = pcall(newRunHere, "the host's run started over")
            if not okN then log("run: error " .. tostring(errN)) end
        end
        if D then D.round, D.state, M.rnd = 0, "wait", nil end
    end
end

local function onSys(from, what, f)
    if what == "joined" or what == "paired" or what == "restart" or what == "up" or what == "left" then
        M.lostAt[from] = nil                              -- ((0.73.80) linked again, or gone: no lost link held for them)
        -- ((review of 0.73.80) a rejoin or a game started over: their last states are from before it)
        if what ~= "up" then M.stateAt[from], M.freshAt[from] = nil, nil end
    end
    if what == "joined" then                              -- (host) a joiner linked: its "hi" names it
        log("coop: player " .. (from + 1) .. " linked")
    elseif what == "paired" or what == "restart" then      -- (joiner) the host; (either) a game started over
        if from == 0 then M.hostLostAt = nil end          -- (host migration: the host's back, or a new one)
        sendHi()
        if COOP.client() and D then killAllCopies("new link"); M.jnAt = os.clock(); send(true, "jn") end
        if COOP.host() and what == "restart" then
            M.roster[from] = nil
            -- ((0.73.77, plan C1) their game started over: back in another aircraft, their plane here goes; the joiners too)
            M.markLeft(from, "started their game over")
            send(true, "rj", from)
        end
    elseif what == "slot" then
        COOP.slot = tonumber(f[3])
        log("coop: you are player " .. tostring((COOP.slot or -1) + 1))
    elseif what == "lost" then
        M.wasLost = M.wasLost or {}
        M.wasLost[from] = true
        callout("CO-OP LINK LOST", string.upper(playerName(from)))
        if from == 0 and COOP.client() then M.hostLostAt = M.hostLostAt or os.clock() end   -- (host migration's clock)
        if COOP.host() and from ~= COOP.slot then M.noteLost(from) end   -- ((0.73.80) in the mission or loading: the round's hold)
    elseif what == "up" then
        if from == 0 then M.hostLostAt = nil end
        if M.wasLost and M.wasLost[from] then             -- (the first "up" comes right after "paired" / "joined")
            M.wasLost[from] = nil
            callout("CO-OP LINK BACK", string.upper(playerName(from)))
            -- (a joiner says hello again: the host may have dropped it meanwhile, its roster entry gone, and this game
            -- can't tell; the co-op run of 2026-10-31)
            if COOP.client() then sendHi() end
            if COOP.client() and D then killAllCopies("link back"); M.jnAt = os.clock(); send(true, "jn") end
        end
    elseif what == "left" then
        callout(string.upper(playerName(from)) .. " LEFT", nil)
        M.roster[from] = nil
        local P = M.peers[from]
        if P and P.obj then
            pcall(function() P.obj:SetActorHiddenInGame(true) end); P.shown = false
            local radar = M.radarOff(P)                  -- ((0.73.83) its blip too)
            if radar then log(string.format("coop: player %d's plane hidden (left): %s", from + 1, radar)) end
        end
        if COOP.host() then send(true, "po", from) end
        if from ~= 0 then M.markLeft(from, "left") end     -- ((0.73.77, plan C1) a rejoin in another aircraft: a new plane)
    elseif what == "full" then
        callout("CO-OP: THE HOST'S GAME IS FULL", nil)
    elseif what == "badver" then                          -- (joiner, runtime 0.32.6) the host runs another build
        local hv = upperText(f[3], 32)
        log(string.format("coop: the host runs Survival %s, this game %s: another build doesn't link (update to the host's)",
            tostring(f[3] or "?"), VERSION))
        callout("CO-OP: THE HOST HAS " .. (hv ~= "" and hv or "ANOTHER BUILD"), "UPDATE SURVIVAL TO JOIN (YOU HAVE " .. upperText(VERSION, 32) .. ")")
    elseif what == "refused" then                         -- (host) a joiner of another build turned away (coop.c)
        local nm, jv = upperText(f[3], 20), upperText(f[4], 32)
        log(string.format("coop: %s tried to join with Survival %s (yours %s): refused", tostring(f[3] or "?"), tostring(f[4] or "?"), VERSION))
        callout("REFUSED " .. (nm ~= "" and nm or "A PLAYER"), "THEY HAVE " .. (jv ~= "" and jv or "ANOTHER BUILD") .. ": UPDATE TO " .. upperText(VERSION, 32))
    elseif what == "samerole" then
        if COOP.host() and playerCount() <= 1 and M.migStepBack and M.migStepBack() then
            -- (a host by migration that nobody joined hears another host: its own link had dropped, the old host's
            -- still there; it joins it again)
        elseif M.auto and COOP.host() and playerCount() <= 1 and not D then   -- (an automatic host, alone, not in a run)
            log("coop: another host found; this game was hosting only because it found none (role auto): joining")
            COOP.reopen("join", "another host found")
            callout("CO-OP: ANOTHER HOST FOUND", "JOINING THEM")
        elseif M.auto then
            callout("CO-OP: TWO HOSTS", "RETRY FROM THE MENU TO JOIN THE OTHER")
        else
            callout("CO-OP: TWO HOSTS", "ONLY ONE OF YOU PICKS HOST: THE OTHERS PICK SURVIVAL CO-OP: JOIN")
        end
    end
end

local function onMessage(raw)
    local slot, body = raw:match("^(%d+)|(.*)$")     -- ("<sender's slot>|...": the slot in decimal from runtime 0.24.0)
    local from = tonumber(slot) or 0
    body = body or raw
    local f = split(body)
    for i = 2, #f do f[i] = f[i]:gsub("%c", "") end
    if f[1] == "sys" then
        log("coop: player " .. (from + 1) .. ": " .. body)
        return onSys(from, f[2], f)
    end
    if COOP.host() then return onHostMessage(from, f) end
    if from == 0 then return onJoinerMessage(f) end
end

---------------------------------------------------------------------------------------------------- the rest of the runtime, wrapped
local rawRoundsTick, rawAirfieldTick, rawBombTick = roundsTick, airfieldTick, bombTick
local function mirrored(fn, ...)                    -- the host's own round logic: its callouts and bonuses go out
    M.mirror = M.mirror + 1
    local ok, err = pcall(fn, ...)
    M.mirror = M.mirror - 1
    if not ok then error(err, 0) end
end
roundsTick = function(now)
    if COOP.client() then return clientRounds(now) end
    return mirrored(rawRoundsTick, now)
end
airfieldTick = function(tick)
    if COOP.client() then return end                -- (the host's airfield: "af")
    return mirrored(rawAirfieldTick, tick)
end
bombTick = function(tick)
    if COOP.client() then return end                -- (the host's bombers bomb the host's airfield)
    return mirrored(rawBombTick, tick)
end
-- (0.73.77, plan D3) A joiner's special rounds are the host's. Its music (sv_flights.lua musicTick: the round's special
-- from specialFor) followed this game's own dice (RUN.specialPick, rolled here for rounds the host decided), so the
-- host's special rounds played a normal round's music here and the other way round, and the log named specials the host
-- never had. The host sends its round's special in "rnd" (field 11); a joiner's specialFor answers from it (none for a
-- round the host hasn't said). M.roundSpecial (the host's "rnd"): the round's special as specialFor has it, never
-- rolling a round's dice before its time (a run started at a later round would have its first round's rolled here).
do
local rawSpecialFor = specialFor
specialFor = function(round)
    if not COOP.client() then return rawSpecialFor(round) end
    local r = M.rnd
    if not (r and r.round == round) then return nil end
    if M.spSaid ~= round then
        M.spSaid = round
        log(string.format("coop: round %d is %s on the host: a %s round's music here", round,
            r.special and ("its " .. r.special .. " special") or "a normal round", r.special and "special" or "normal"))
    end
    return r.special
end
function M.roundSpecial(round)
    local sp = CFG.specials
    if type(sp) == "table" and sp.enabled and sp.random and type(sp.rotation) == "table" and #sp.rotation > 0 then
        local pick = RUN and RUN.specialPick
        local retake = RUN and RUN.sport and RUN.sport.retakeRound == round
        if not retake and not (pick and pick[round] ~= nil) then return nil end   -- (not picked yet: not rolled here)
    end
    return rawSpecialFor(round)
end
end
local rawCallout = hudCallout
hudCallout = function(text, sub, big)
    rawCallout(text, sub, big)
    if COOP.host() and M.mirror > 0 and not M.noMirror and cfg().callouts then send(true, "co", text or "", sub or "", big and 1 or 0) end
end
local rawAddCredits = addCredits
-- (a round's bonus while you're DOWN, sv_down.lua: paid unless [coop.revive] down_round_bonus is off)
function M.noDownBonus()
    local rv = CFG.coop and CFG.coop.revive
    return DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true and type(rv) == "table" and rv.down_round_bonus == false
end
addCredits = function(n, why)
    local bonus = M.mirror > 0 and type(why) == "string" and not why:find(" down %(") and n > 0
    -- ((0.73.78, economy C3) a special's pay split: the host pays and sends each player's share, so every game pays the
    -- same, the joiners from "cr" as before; specialPay (sv_ai.lua) shows the same on the special's callout)
    if COOP.host() and bonus and M.specialPay(why) then
        local x = COOP.specialShare()
        if x < 1 then
            local whole = n
            n = specialPay(whole)
            why = string.format("%s, co-op share x%.2f of %d (%d players)", why, x, whole, playerCount())
        end
    end
    if COOP.host() and bonus and M.noDownBonus() then
        log("revive: the round's bonus (" .. tostring(n) .. ") not paid: you're down (down_round_bonus off)")
    else
        rawAddCredits(n, why)
    end
    if COOP.host() and bonus then send(true, "cr", n, why) end
end
local rawLogPlane = logPlane
logPlane = function(o, unit, k)
    local slot = unit and SLOT_OF[unit]
    if slot and M.unitSlot[unit] then slot = M.unitSlot[unit] end   -- ((0.73.77) a free unit flown for another player: plan C4)
    if slot then
        local ok, err = pcall(COOP.peerPlane, o, slot)
        if not ok then log("coop: player plane error " .. tostring(err)) end
        return
    end
    rawLogPlane(o, unit, k)
    if COOP.open and unit and valid(o) and inSurvival(o) then
        local ok, err = pcall(COOP.host() and hostPlane or clientPlane, o, unit)
        if not ok then log("coop: plane error " .. tostring(err)) end
    end
end
local rawRead = KILL.read
KILL.read = function(p)
    rawRead(p)
    local a = p and valid(p.obj) and addrOf(p.obj)
    local j = a and M.joinHits and M.joinHits[a]
    if j and j > 0 then
        p.dmg = p.dmg or {}
        p.dmg.wingmate = math.max(p.dmg.wingmate or 0, j)
    end
end
local rawSide = KILL.side
KILL.side = function(o, pawnAddr)
    local a = addrOf(o)
    if a then for _, P in pairs(M.peers) do if P.addr and P.addr == a then return "wingmate" end end end
    return rawSide(o, pawnAddr)
end
-- (0.73.77, economy C1) the player (or side) the host named for plane p's kill: the host's own (hostKiller), a joiner's
-- from its "dn" (M.killer); nil when none was named (a copy lost here on its own, an older host: as before)
function M.killerOf(p)
    local a = p and (p.addr or (live(p.obj) and addrOf(p.obj)))
    if not a then return nil end
    if COOP.host() then
        for _, e in pairs(M.byId) do
            if e.addr == a then local okK, kl = pcall(hostKiller, e); return okK and kl or nil end
        end
        return nil
    end
    local k = M.killer and M.killer[a]
    if not k then return nil end
    local s = tonumber(k.code)
    if s and slotOk(s) then return { slot = s } end
    for side, code in pairs(KILL_SIDE_CODE) do if code == k.code then return { side = side } end end
    return nil
end
-- every game pays a kill by the player the host named: its own x1, a teammate's x COOP.teamShare() (sv_main.lua
-- creditKill: p.killer, the teammate's slot, for its line); a side's (allies, ships, defences) x ally_x as before.
-- p.hostNamed on a joiner (its kills line says so).
local rawBy = KILL.by
KILL.by = function(p)
    local kl = COOP.open and M.killerOf(p) or nil
    if kl then
        p.killer, p.hostNamed = kl.slot, COOP.client() or nil
        if kl.slot then return kl.slot == (COOP.slot or 0) and "you" or "wingmate" end
        return kl.side
    end
    if rawBy then return rawBy(p) end
    return "you"
end
-- (0.73.77, economy C1, approved 2026-11-03) a teammate's kill pays min(team_x, 1 / (players - 1)) of a kill on every
-- game, the host's as a joiner's: 0.5 with 2 or 3 players, 0.33 with 4, 0.25 with 5 (CFG.credits.team_x, the host's
-- setting), so the others' kills add about one more of your own however many fly
function COOP.teamShare()
    local cap = tonumber(CFG.credits and CFG.credits.team_x) or 0.5
    local n = COOP.open and playerCount() or 1
    return math.min(cap, 1 / math.max(1, n - 1))
end
-- (0.73.78, economy C3, approved 2026-11-03) a special's reward in co-op pays each player x players ^ -special_split
-- (CFG.credits.special_split, the host's setting, 0-1): 0.5 = 1 / sqrt(players), 0.71 with 2, 0.58 with 3, 0.5 with 4,
-- 0.45 with 5; 1 solo or alone. Every game paid the whole reward before, so a special put N rewards into the run.
function COOP.specialShare()
    local e = tonumber(CFG.credits and CFG.credits.special_split) or 0.5
    local n = COOP.open and playerCount() or 1
    if n <= 1 or not (e > 0) then return 1 end
    return math.min(1, n ^ -math.min(e, 1))
end
-- a pay of the host's round logic that is a special's (its reward, or what it pays as it goes: landing craft, the
-- spaceport's fleet, ballast tanks, rockets ...): every one the joiners are sent ("cr") but the round's bonus
function M.specialPay(why) return type(why) == "string" and not why:find("^round %d+ cleared") end
-- ((0.73.78) the allies priced room-wide besides VOID WATCHER 1 (its own count is "rnd" field 13): the host's counts of
-- them in "rnd" field 14, with the defences')
M.ROOM_ITEMS = { "Moonchild", "Wingmen", "ShipAegis" }
-- ((0.73.77, plan H2) for the co-op run's squad, sv_leaderboard.lua: a slot's roster entry (name, sid, code; read
-- only) and this game's Steam ID)
function COOP.roster(slot) return M.roster[slot] end
function COOP.mySid() return M.mySid and M.mySid() or nil end
local rawSend = LB.send
LB.send = function(sh)
    if COOP.open and not cfg().leaderboard then
        log("leaderboard: a co-op run; not sent (CFG.coop.leaderboard)")
        if sh then sh.state = "local" end
        return
    end
    return rawSend(sh)
end

---------------------------------------------------------------------------------------------------- the tick
-- (Re)opens the link as role ("host" | "join"). Role auto (the default from coop.3; user, 2026-10-25: friends set
-- role = join and their games still all hosted) opens as a joiner; if no host is found in AUTO_WAIT (+ up to as much
-- again at random, so two such games don't host at once) it reopens as the host, and an automatic host that meets
-- another host while alone and before a run joins that one (onSys "samerole").
local AUTO_WAIT = 10                                  -- (s; up to twice that, at random)
-- partner: who to look for this time (host migration: the next host's Steam ID, or every player's for the new host),
-- else CFG.coop.partner
function COOP.reopen(role, why, partner)
    local c = cfg()
    local r = SV_CoopOpen(c.transport or "steam", role, partner or c.partner or "auto", c.port or 27777, c.interp_ms or 120, VERSION,
                          maxPlayers())
    COOP.open, COOP.role, COOP.slot = r == 1, role, role == "host" and 0 or nil
    M.state, M.roster = nil, {}
    if role == "host" then M.restoreMine() end          -- (you host: your own settings)
    M.autoAt = os.clock() + AUTO_WAIT + math.random() * AUTO_WAIT
    log(string.format("coop: %s as the %s over %s (partner %s, up to %d players; %s): %s", r == 1 and "open" or "NOT open",
        role == "host" and "host" or "joiner", tostring(c.transport), tostring(partner or c.partner or "auto"), maxPlayers(), why,
        r == 1 and (role == "host" and "looking for players" or "looking for the host") or
        ({ [-1] = "bad settings", [-2] = "Steam not available", [-3] = "UDP not available", [-4] = "partner isn't an IP address" })[r] or tostring(r)))
    if COOP.open and COOP.host() and M.myName ~= nil then hostRosterSelf() end
    return r
end

-- Opens co-op for this game: the role from CFG.coop.role (auto unless set), your name, and you in the roster as host
local function openCoop(why, picked)
    local c = cfg()
    if type(SV_CoopOpen) ~= "function" then log("coop: dlls/main.dll has no co-op (0.22.0 or later needed)"); return end
    local role = picked or tostring(c.role or "auto"):lower()              -- (the main menu's choice before the ini's)
    if role == "joiner" or role == "client" then role = "join" end
    if role ~= "host" and role ~= "join" then role = "auto" end
    M.auto, M.linkedOnce = role == "auto", false
    log("coop: role " .. role .. (M.auto and " (a joiner that hosts if it finds no host)" or "") ..
        (picked and " picked on the main menu" or " from CFG.coop.role"))
    COOP.reopen(M.auto and "join" or role, why)
    if not COOP.open then return end
    if type(SV_SteamName) == "function" then local okN, nm = pcall(SV_SteamName); if okN and type(nm) == "string" then M.myName = nm end end
    local own = tostring(c.name or ""):gsub("[%c|,;]", ""):match("^%s*(.-)%s*$")
    if own ~= "" then
        local n = utf8 and utf8.len(own)                                  -- (20 characters, not bytes)
        if n then M.myName = n <= 20 and own or own:sub(1, utf8.offset(own, 21) - 1) else M.myName = own:sub(1, 20) end
        log("coop: your name for the other players: " .. M.myName .. " (CFG.coop.name)")
    end
    if COOP.host() then hostRosterSelf() end
end

local function closeCoop(why)
    if type(SV_CoopClose) == "function" then SV_CoopClose() end
    COOP.open, COOP.role, COOP.slot = false, nil, nil
    M.state, M.roster, M.linkedOnce, M.wasLost = nil, {}, false, nil
    M.restoreMine()
    log("coop: closed (" .. why .. ")")
end

-- Each player's name on their plane's target box (user, 2026-10-26: "we need to get player names working on the HUD
-- always"): the stand-ins SV_Unit_CoopPeer<A-X> carry the callsign key SV_CoopName_<A-X> (NAME_KEYS;
-- tools/build_survival.py COOP_NAME_KEYS), whose text is set here whenever a name changes
local function upperName(s, max)
    s = string.upper(tostring(s or ""))
    local n = utf8 and utf8.len(s)
    if n and n > max then return s:sub(1, utf8.offset(s, max + 1) - 1) end
    return n and s or s:sub(1, max)
end
local function nameTick()
    if type(SV_SetText) ~= "function" then return end
    M.nameSet = M.nameSet or {}
    for s = 0, MAX_SLOT do
        -- ((0.73.77) a stand-in unit flown for another player, plan C4: its name key says theirs)
        local n = upperName(playerName(M.unitSlot[PEER_UNITS[s]] or s), 20)
        if M.nameSet[s] ~= n then
            M.nameSet[s] = n
            pcall(SV_SetText, NAME_KEYS[s], n)
        end
    end
end

-- The HUD's co-op row (sv_hud.lua hudTick): who is playing, the host first and marked, in plain words; nil when solo.
-- Its second value is the row's news for the info key: who's in, links lost and who's shot down (not health, where they
-- are or a state gone stale). Each player's line is on the info wall (COOP.wallInfo).
local HUD_NAMES = 6
local function hudState(s)              -- a player's state and health % for their line, from COOP.players()'s sources
    local e
    if s == COOP.slot then e = COOP.me() else
        local P = M.peers[s]
        e = P and P.fresh and P
        if not e then return "NOT IN THE MISSION" end
    end
    if not e then return "" end                                 -- (your plane not up: the HUD's hidden then)
    if e.alive == false then return "DOWN" end
    return e.onAirfield and "AT THE AIRFIELD" or "FLYING", e.hpPct and math.floor(e.hpPct + 0.5)
end
local function lookingLine() return M.auto and "CO-OP: LOOKING FOR A HOST..." or "CO-OP: LOOKING FOR A FRIEND WHO PICKED HOST..." end
local WAITING_LINE = "CO-OP: YOU ARE THE HOST, WAITING FOR FRIENDS"
function COOP.hudLine()
    if not COOP.open then return nil end
    if COOP.client() and M.state ~= "linked" then
        local s = lookingLine()
        return s, s
    end
    local names, news, n = {}, {}, 0
    for s = 0, MAX_SLOT do
        if M.roster[s] or s == COOP.slot then
            n = n + 1
            local nm = upperName(playerName(s), 14) .. (s == 0 and " (HOST)" or "")
            if M.wasLost and M.wasLost[s] then nm = nm .. " (LOST)" end
            if n <= HUD_NAMES then names[#names + 1] = nm end       -- (a big room: the first few, then "+N")
            local st = hudState(s)
            -- (shot down by the last state their game sent, not by its freshness: a lagging link flips that)
            local P, down = M.peers[s], st == "DOWN"
            if s ~= COOP.slot then down = P ~= nil and (P.flags or 0) % 2 == 1 and P.alive == false end
            news[#news + 1] = s .. nm .. (down and " DOWN" or "")
        end
    end
    if COOP.host() and n <= 1 then return WAITING_LINE, WAITING_LINE end
    if n > #names then names[#names + 1] = "+" .. (n - #names) end
    return string.format("CO-OP %d/%d: %s", n, maxPlayers(), table.concat(names, "  ")), table.concat(news, "|")
end

-- The HUD's info wall (sv_hud.lua, the user's of 2026-10-31: with more than 3 players the corner's lines couldn't show
-- what everyone was doing): { header, players = { a line each } } in co-op, nil solo. A line: the name (HOST, YOU, LOST),
-- the aircraft (their plane's own name, as on their box), FLYING / AT THE AIRFIELD / DOWN / NOT IN THE MISSION and
-- health, the host first, then by slot; every player, up to the room's 24. A joiner still looking for its host: the
-- header alone.
function COOP.wallInfo()
    if not COOP.open then return nil end
    if COOP.client() and M.state ~= "linked" then return { header = lookingLine(), players = {} } end
    local list = {}
    for s = 0, MAX_SLOT do
        if M.roster[s] or s == COOP.slot then
            local tags = {}
            if s == 0 then tags[#tags + 1] = "HOST" end
            if s == COOP.slot then tags[#tags + 1] = "YOU" end
            if M.wasLost and M.wasLost[s] then tags[#tags + 1] = "LOST" end
            local parts = { upperName(playerName(s), 14) .. (#tags > 0 and " (" .. table.concat(tags, ", ") .. ")" or "") }
            local ac = (s == COOP.slot) and M.myAc or (M.roster[s] and M.roster[s].ac)
            if type(ac) == "string" and ac ~= "" then parts[#parts + 1] = ac end
            local st, hp = hudState(s)
            if st ~= "" then parts[#parts + 1] = st end
            if hp then parts[#parts + 1] = string.format("%d%%", hp) end
            list[#list + 1] = table.concat(parts, "   ")
        end
    end
    if COOP.host() and #list <= 1 then return { header = WAITING_LINE, players = list } end
    return { header = string.format("CO-OP  %d/%d PLAYERS", #list, maxPlayers()), players = list }
end

-- The menu's view of co-op (sv_menu.lua): the lobby on the COOP HOST page, settings changed there
function COOP.lobby()
    local names = {}
    for sl = 0, MAX_SLOT do if M.roster[sl] or sl == COOP.slot then names[#names + 1] = upperName(playerName(sl), 14) end end
    return { open = COOP.open, role = COOP.role, n = playerCount(), max = maxPlayers(), names = names, state = M.state }
end
function COOP.settingsChanged(name)
    if COOP.host() and playerCount() > 1 then pcall(M.sendSettings, nil) end      -- (your joiners get it at once)
    if name == "Room" and COOP.host() then
        if playerCount() <= 1 and not D then COOP.reopen("host", "room size changed")
        else log("coop: the new room size applies the next time you host") end
    end
end
-- your own settings (the menu's setups): the host's are in CFG while you play with them
function COOP.ownRoot() return M.ownRoot() end


-- The STORE freeze (0.73.72, runtime 0.32.20; tools/re/STORE_FREEZE.md): the game's DeactivateForMinigame stops every
-- AI plane when a minigame (the airfield STORE) starts. While players are linked the runtime skips it (SV_StoreKeepAI),
-- so the world keeps flying for the others; solo, or co-op closed, the stock freeze stays. Logged once per change.
function COOP.storeKeepTick(c)
    if type(SV_StoreKeepAI) ~= "function" then return end
    local want = (c.enabled and COOP.open and c.store_keep_world ~= false and (M.linkedPeers or 0) > 0) and 1 or 0
    if want == M.storeKeep then return end
    local old = SV_StoreKeepAI(want)
    M.storeKeep = want
    if type(old) == "number" and old < 0 then
        once("storekeep", "coop: the STORE's world freeze can't be skipped here (the runtime didn't hook it: " .. tostring(old) .. ")")
    else
        log("coop: a STORE opening " .. (want == 1 and "keeps the world's AI flying (players linked)" or "stops the world's AI (stock)"))
    end
end

-- (0.73.76) a joiner's VALKA: her X-02S and paint on its copy of her once it's here (up to 30 s after "vr"), then its
-- wing sweep each tick, as her round does on the host
function COOP.valkaTick()
    local v = M.vr
    if not (v and D and COOP.client()) then return end
    local cu = M.cunits[v.unit]
    local o = nil
    for _, p in pairs(cu and cu.planes or {}) do if liveAddr(p) then o = p; break end end
    if not o then
        if v.done or os.clock() - v.at > 30 then
            if not v.done then log("coop: VALKA's copy here never came: her X-02S not put on") end
            M.vr = nil
        end
        return
    end
    if not v.done then
        local ok = SPC.V.model(CFG.specials.valka, v.st, o)
        if ok then
            v.done = true
            log("coop: VALKA's X-02S on this game's copy of her (" .. nameOf(o) .. ")")
        elseif os.clock() - v.at > 30 then M.vr = nil end
        return
    end
    pcall(SPC.V.modelTick, v.st, o, (D and D.now) or os.clock())
end

function COOP.tick(tick)
    local c = cfg()
    pcall(COOP.storeKeepTick, c)
    pcall(COOP.valkaTick)
    if not c.enabled then return end
    -- Co-op opens when the player picks COOP HOST or COOP JOIN (Survival's menu page, or the flat SURVIVAL CO-OP rows),
    -- as that role, and closes when they pick any other entry (SV_MenuChoice, the runtime's: the entry, 1 SURVIVAL MODE,
    -- 2 SP OFFLINE, 3 HOST, 4 JOIN, 5 SP ONLINE, 0 another, + 16 x the picks so far: picking the same entry again
    -- retries a co-op that couldn't open, and keeps one that's open). 6, SURVIVAL MODE's page opened, leaves co-op as it
    -- is: you pick the mode next. An older main.dll without it: open at start with CFG.coop.role, as before.
    local raw = type(SV_MenuChoice) == "function" and SV_MenuChoice() or nil
    if raw == nil then
        if not COOP.open and not M.openTried then M.openTried = true; openCoop("start") end
    elseif raw ~= M.raw and math.floor(raw) % 16 == 6 then
        M.raw = raw
    elseif raw ~= M.raw then
        M.raw = raw
        local choice = math.floor(raw) % 16
        local want = (choice == 3 and "host") or (choice == 4 and "join") or nil
        if COOP.open and want ~= M.picked then
            closeCoop((want and "the other co-op entry picked") or
                      ((choice == 1 or choice == 2 or choice == 5) and "a single-player mode picked: playing alone")
                      or "another main-menu entry picked")
        end
        M.picked = want
        if want and not COOP.open then openCoop(want == "host" and "SURVIVAL CO-OP: HOST picked" or "SURVIVAL CO-OP: JOIN picked", want) end
    end
    if not COOP.open then return end
    pcall(nameTick)
    pcall(M.asideTick, os.clock())                     -- ((0.73.83) set-aside planes kept off the radar)
    -- the other games' messages
    for _ = 1, 600 do
        local m = SV_CoopRecv()
        if not m or m == "" then break end
        local ok, err = pcall(onMessage, m)
        if not ok then log("coop: message error " .. tostring(err) .. " (" .. m:sub(1, 80) .. ")") end
    end
    local now = os.clock()
    if now >= M.nextInfo then
        M.nextInfo = now + 5
        local info = SV_CoopInfo()
        local st = info:match("state=(%a+)")
        M.linkNames, M.rtt = {}, {}
        M.linkedPeers = 0
        for s, st, rtt, name in (info:match("peers=(.*)$") or ""):gmatch("(%d+)/(%a+)/(%-?%d+)/%-?%d+/([^,]*)") do
            M.linkNames[tonumber(s)] = name
            local ms = tonumber(rtt)                         -- (the link's round trip: a shot's age, "fx")
            if ms and ms >= 0 and ms < 10000 then M.rtt[tonumber(s)] = ms end
            if st == "linked" then M.linkedPeers = M.linkedPeers + 1 end
        end
        if st ~= M.state then
            M.state = st
            log("coop: " .. info)
            if st == "searching" and COOP.client() then once("searching", "coop: waiting for the host (" .. tostring(c.partner) .. ")") end
        end
        if st == "linked" then M.linkedOnce = true end
        if M.auto and COOP.client() and not M.linkedOnce and st ~= "linked" and now >= (M.autoAt or 0) then
            log("coop: no host found in time (role auto): this game hosts")
            COOP.reopen("host", "no host found")
            callout("CO-OP: NO HOST FOUND", "YOU ARE THE HOST")
            return
        end
        if COOP.client() and st == "linked" and now >= M.nextHi and not M.roster[COOP.slot or -1] then
            M.nextHi = now + 10                              -- (the host hasn't listed us yet: hello again)
            sendHi()
        end
    end
    -- a new level (a run started, or started over)
    if D ~= M.lastD then
        M.lastD = D
        if type(SV_CoopReset) == "function" then SV_CoopReset() end
        if COOP.client() then killAllCopies("a new run here") end      -- (a restart in the same level keeps the actors)
        for s, P in pairs(M.peers) do                                  -- (kept: bound again by peerTick)
            M.gunOff(P)                                                -- ((review of 0.73.80) its trigger let go: gunOn isn't kept)
            -- (whose it is and whether it's their real plane kept too: a host by migration keeps every live plane)
            M.peers[s] = (P.obj and valid(P.obj)) and { obj = P.obj, addr = addrOf(P.obj), sid = P.sid, real = P.real, code = P.code,
                                                       lo = P.lo, row = P.row, unit = P.unit,
                                                       fallback = P.fallback } or {}   -- ((0.73.80) M.standInPay)
        end
        pcall(M.asidePrune)                                            -- ((0.73.77) set-aside planes gone with a level let go)
        if M.vmHere then M.valkaHere(false, D and "a new run here" or "the run here is over") end   -- ((0.73.77) D2)
        M.units, M.byId, M.copies, M.cunits, M.spawnQ, M.dead, M.hunts = {}, {}, {}, {}, {}, {}, {}
        M.joinHits, M.pendBind, M.strayFirst, M.rep, M.downAt = nil, nil, nil, nil, {}
        M.replays, groundNew, M.holdQ = {}, {}, nil
        -- ((0.73.77) a new level: no run-over kept (A9), the kills by player (C1) and the kills' players named start over,
        -- the floor's line again (A1))
        M.ro, M.tally, M.killer, M.floorSaid = nil, nil, nil, nil
        -- ((review of 0.73.80) the round hold's state from before (a player loading the new level whose link is lost
        -- isn't "lost in the mission" by their last run's states): each player held up to join_wait_s again
        M.stateAt, M.freshAt, M.lostAt, M.holding, M.outSince = {}, {}, {}, {}, {}
        -- ((0.73.73) the units' objects kept, a restart in the same level keeps the actors: those of a level gone, or whose
        -- address is another object's now, dropped)
        for unit, reg in pairs(M.objsOf) do
            for a, e in pairs(reg) do if not live(e.obj) or nameOf(e.obj) ~= e.name then reg[a] = nil end end
            if next(reg) == nil then M.objsOf[unit] = nil end
        end
        M.svcpUsable = {}                                              -- (the stand-ins' damage-0 rows in before it loaded)
        for row, sv in pairs(M.svcpReady or {}) do M.svcpUsable[row] = sv end
        if D then
            -- ((0.73.73) "rs|n": the host's new run, which a joiner starts over with; "rs|m" a host by migration's level, the
            -- same run: a joiner keeps its money and nobody DOWN comes back)
            if COOP.host() then send(true, "rs", (M.mig and M.mig.hosting) and "m" or "n")
            else M.jnAt = os.clock(); send(true, "jn") end
            log("coop: in Survival's level as " .. (COOP.host() and "the host" or ("player " .. tostring((COOP.slot or -1) + 1))))
            if COOP.client() and M.state ~= "linked" then
                callout(M.auto and "CO-OP: LOOKING FOR A HOST" or "CO-OP: WAITING FOR THE HOST",
                        M.auto and "NONE FOUND: YOU HOST" or tostring(c.partner))
            elseif COOP.host() then
                callout("CO-OP: YOU ARE THE HOST", string.format("PLAYERS %d/%d", playerCount(), maxPlayers()))
            end
        end
    end
    local okVw, errVw = pcall(M.valkaWatch)                          -- ((0.73.77) VALKA's mood to every joiner: D1-D2)
    if not okVw then once("valkaWatch", "coop: VALKA's mood watch error " .. tostring(errVw)) end
    if not D then
        -- ((0.73.80) no run (the main menu, the hangar): the tables the other players' planes and skins are checked
        -- against looked for here, never in a fight (M.tablesPrep)
        local okTp, errTp = pcall(M.tablesPrep)
        if not okTp then once("tablesPrep", "coop: the plane and skin tables: error " .. tostring(errTp)) end
        return
    end
    -- An online-style pause (user, 2026-10-26: "when the Host Pauses, the game doesn't pause all the enemies for the
    -- other players"): while another player is linked, the pause menu opens but the world keeps running, on the host's
    -- game (its enemies, which every game copies) and on a joiner's (its plane). Alone, the game pauses as ever.
    -- ((0.73.79) the round clock's answer this tick, when it asked the game: not paused, so nothing to undo)
    local clockSaysRunning = CLOCK_TICK == tick and CLOCK_PAUSED == false
    if (M.linkedPeers or 0) > 0 and not clockSaysRunning and valid(survivalPC) and gamePaused(survivalPC) then
        local gs = cdo("/Script/Engine.Default__GameplayStatics")
        local ok = gs and pcall(function() gs:SetGamePaused(survivalPC, false) end)
        M.unpauses = (M.unpauses or 0) + 1
        if M.unpauses == 1 or M.unpauses % 40 == 0 then
            log(string.format("coop: paused with %d players: the world kept running (%s; %d times)", playerCount(),
                ok and "unpaused" or "COULD NOT unpause", M.unpauses))
        end
        if M.unpauses == 1 then callout("CO-OP: THE GAME KEEPS RUNNING", "OTHER PLAYERS ARE STILL FLYING") end
    end
    -- (hotfix6) The host's landing STORE stops the world without pausing it (VanesCreed-'s host log of 2026-11-01: in
    -- the STORE 00:07:00-00:09:54 of round 16, not paused, its frames running, yet no enemy moved or died for anyone
    -- for those 3 minutes, as in round 15's visit): most likely the world's time dilation. While another player is
    -- linked it's kept at 1, as the pause above is undone; and the world's clock is watched, so the next log says
    -- what stops it if that isn't it.
    if (M.linkedPeers or 0) > 0 and valid(survivalPC) then
        local okW, errW = pcall(function()
            local gs = cdo("/Script/Engine.Default__GameplayStatics")
            local okD, dil = pcall(function() return gs:GetGlobalTimeDilation(survivalPC) end)
            dil = (okD and type(dil) == "number") and dil or nil
            if dil and dil < 0.99 then
                local okS = pcall(function() gs:SetGlobalTimeDilation(survivalPC, 1.0) end)
                M.dilFixes = (M.dilFixes or 0) + 1
                if M.dilFixes == 1 or M.dilFixes % 40 == 0 then
                    log(string.format("coop: time dilation was %.3f with %d players%s: set back to 1 (%s; %d times)", dil,
                        playerCount(), playerOnAirfield() and " (you're down at the airfield)" or "",
                        okS and "set" or "COULD NOT set", M.dilFixes))
                end
            end
            local t, rt = gameClock(survivalPC), os.clock()
            if t then
                if M.wcT and t == M.wcT then                     -- the world's clock didn't move since last tick
                    M.wcStill = M.wcStill or rt
                    if rt - M.wcStill >= 3 and not M.wcSaid then
                        M.wcSaid = true
                        log(string.format("coop: the world's clock has stood still %.0f s with %d players (paused %s, time dilation %s%s)",
                            rt - M.wcStill, playerCount(), tostring(gamePaused(survivalPC)), dil and string.format("%.3f", dil) or "?",
                            playerOnAirfield() and ", you're down at the airfield" or ""))
                    end
                else
                    if M.wcSaid then log(string.format("coop: the world's clock runs again after %.0f s", rt - (M.wcStill or rt))) end
                    M.wcStill, M.wcSaid = nil, nil
                end
                M.wcT = t
            end
        end)
        if not okW then once("worldclock", "coop: world clock check error " .. tostring(errW)) end
    end
    -- (the host-at-the-airfield freeze, hotfixes 7-12, removed in 0.73.67: none of its switch-backs woke the planes the
    -- STORE's minigame manager (LiveMiniGameManager) switches off, and they likely caused the renderer crashes of
    -- 2026-11-01. To be reverse engineered: HOTFIX_NOTES.md open problem 1.)
    -- our own plane, streamed (flags: 1 in Survival's level, 2 alive, 4 down at the airfield, 8 DOWN: shot down and
    -- waiting for a revive, sv_down.lua, not "alive" then; the sync's 16 gear down, 32 afterburner, 64 gun firing,
    -- 128 flares)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if valid(pawn) then
        local flags = 1
        local h = health(pawn)
        local down = DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true
        if down then flags = flags + 8 elseif h and h > 0 then flags = flags + 2 end
        if playerOnAirfield() then flags = flags + 4 end
        local okB, bits = pcall(M.syncBits, pawn, now)
        if okB then flags = flags + bits else once("syncBits", "coopfire: state bits error " .. tostring(bits)) end
        SV_CoopMe(addrOf(pawn) or 0, flags)
        local row, code = myAirframe()
        local okSa, errSa = pcall(M.seenAsTick, code)        -- ((0.73.80) "OTHERS SEE YOUR <X> AS <Y>", once a level)
        if not okSa then once("seenAs", "coop: seen-as error " .. tostring(errSa)) end
        local lo = M.myLoadout()                              -- (new weapons picked at the airfield: COOP2MP T4b)
        local pt = M.myPaint()                                -- (and paint: T5)
        local acn = M.myAircraft()                            -- (and the aircraft's name)
        local okMp, mcls = pcall(M.myPlane, pawn, code)       -- ((0.73.80) and its class path: a modded plane's, sent)
        if not okMp then once("myPlane", "coop: your plane's class: error " .. tostring(mcls)); mcls = M.myCls end
        if (row and row ~= M.myRow) or (code and code ~= M.myCode) or (lo ~= "" and lo ~= M.myLo) or (pt ~= "" and pt ~= M.myPt)
            or (acn ~= "" and acn ~= M.myAc) or (mcls ~= nil and mcls ~= "" and mcls ~= M.myCls) then
            M.myRow, M.myCode = row, code
            if COOP.host() then hostRosterSelf() else sendHi() end
        end
    else
        SV_CoopMe(0, 0)
    end
    local okSf, errSf = pcall(M.slotFix)                              -- (each plane in its owner's slot: host migration)
    if not okSf then once("slotFix", "coop: slot fix error " .. tostring(errSf)) end
    for s = 0, MAX_SLOT do
        if s ~= COOP.slot then
            local okP, errP = pcall(peerTick, s)
            if not okP then once("peerTick", "coop: player plane error " .. tostring(errP)) end
        end
    end
    local okG, errG = pcall(groundTick)
    if not okG then once("groundTick", "coop: ship / vehicle error " .. tostring(errG)) end
    local okF, errF = pcall(M.syncTick, now, pawn)                   -- (weapons, gear: the sync's)
    if not okF then once("syncTick", "coopfire: sync error " .. tostring(errF)) end
    if COOP.host() then
        local okH, errH = pcall(hostTick)
        if not okH then once("hostTick", "coop: host error " .. tostring(errH)) end
    else
        local okC, errC = pcall(clientTick)
        if not okC then once("clientTick", "coop: joiner error " .. tostring(errC)) end
    end
    local okMg, errMg = pcall(M.migTick, now)                         -- (host migration: the line, the watch, a takeover)
    if not okMg then once("migTick", "coop: migration error " .. tostring(errMg)) end
end
end
