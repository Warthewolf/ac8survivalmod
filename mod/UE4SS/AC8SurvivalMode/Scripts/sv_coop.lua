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
    spawnQ = {}, hunts = {}, mirror = 0,       -- joiner's spawns waiting, host's hunt orders waiting, inside the rounds
    peers = {}, roster = {}, hiFrom = {},      -- the other players' planes here by slot; the roster (host: kept, joiner: told)
    lastD = nil, said = {}, nextRnd = 0, nextHp = 0, nextAf = 0, nextInfo = 0, nextHi = 0,
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
local function health(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return ok and type(h) == "number" and h or nil
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
    SV_Spawn = function(unit, x, y, z, yaw)
        local r
        if x ~= nil then r = rawSpawn(unit, x, y, z, yaw) else r = rawSpawn(unit) end
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
    local now, keep = os.clock(), {}
    for _, g in ipairs(groundNew) do
        if now - g.at < 0.5 then
            keep[#keep + 1] = g                              -- (a moment to be placed and named)
        elseif valid(g.obj) and inSurvival(g.obj) and not isPlane(g.obj) then
            local ok, err = pcall(COOP.host() and hostGround or clientGround, g.obj, g.unit)
            if not ok then once("ground", "coop: ship / vehicle error " .. tostring(err)) end
        end
    end
    groundNew = keep
end

local function anyJoinerPlane()
    for s = 1, MAX_SLOT do if M.peers[s] and M.peers[s].obj then return true end end
    return false
end

local function hostPlane(o, unit)
    local u = M.units[unit]
    if not u then return end
    local a = addrOf(o)
    if SPC.alcnPool and a and SPC.alcnPool.set[a] then return end      -- (the Alicorn's parked pools: not mirrored)
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
    M.byId[id] = { obj = o, unit = unit, key = key, addr = addrOf(o) }
    send(true, "gd", unit, u.gen, key, id)
end

-- the roster: who's in which slot, their airframe and version, to every joiner (on a change)
local function sendRoster(to)
    for s = 0, MAX_SLOT do
        local r = M.roster[s]
        if r then sendTo(to, true, "pi", s, r.row or "", r.ver or "", r.name or "", r.code or "", r.lo or "") end
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
                send(true, "dn", id)
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
    if checkUp then M.nextUp = now + 2 end
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
            for _, name in ipairs(evs) do sendTo(r.to, true, "ev", name) end
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
        send(false, "rnd", D.round or 0, D.state or "wait", string.format("%.1f", secs), D.wave or 0, D.waves and #D.waves or 0, alive, lv, gp)
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

-- a joiner asked for the whole picture (it loaded in, or its link came back): every flight with anything alive
local function hostSync(to)
    sendTo(to, true, "rs")
    sendRoster(to)
    local n = 0
    for unit, u in pairs(M.units) do
        n = n + 1
        sendUnit(to, unit, u)
        for ord, pl in pairs(u.planes) do
            sendTo(to, true, "bd", unit, u.gen, ord, pl.id)
            if pl.dead then sendTo(to, true, "dn", pl.id) end
        end
        for key, g in pairs(u.ground) do
            sendTo(to, true, "gd", unit, u.gen, key, g.id)
            if g.dead then sendTo(to, true, "dn", g.id) end
        end
    end
    -- the Alicorn's fresh copy there: its core open, under water, as here (events of the fight it missed)
    local s = D and D.special
    if s and s.kind == "alicorn" and s.state == "sail" then
        local ev = {}
        if s.coreOpen then ev[#ev + 1] = "RE_SV_AlcnAdvance"; ev[#ev + 1] = "RE_SV_AlcnOpenCore" end
        if s.dived then ev[#ev + 1] = "RE_SV_AlcnDive" end
        if #ev > 0 then
            M.replays = M.replays or {}
            M.replays[#M.replays + 1] = { at = os.clock() + 12, to = to, events = ev }
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
    log(string.format("coop: sent player %d the run: %d flights", to + 1, n))
end

local function hostHit(from, id, dmg)
    local e = M.byId[id]
    if not (e and not e.dead and valid(e.obj) and finite(dmg, math.huge) and dmg > 0) then return end
    dmg = math.min(dmg, HIT_MAX)
    local P = M.peers[from]
    local causer = P and P.obj and valid(P.obj) and P.obj or nil
    local ok = pcall(function() e.obj:ModifyHealth(-dmg, causer, true) end)
    if not ok then ok = pcall(function() e.obj:ModifyHealth(-dmg, e.obj, true) end) end
    if not ok then once("hitfail", "coop: the joiners' hits can't be dealt (ModifyHealth failed)") end
end

---------------------------------------------------------------------------------------------------- joiner
local function hostPuppet()
    local P = M.peers[0]
    return P and P.obj and valid(P.obj) and P.obj or nil
end

local function killCopy(id, o)
    if type(SV_CoopBind) == "function" then SV_CoopBind(id, 0) end
    if not valid(o) then return end
    pcall(function() o:SetMinHealth(0.0) end)
    local h = health(o) or 0
    local causer = hostPuppet()
    local ok = pcall(function() o:ModifyHealth(-(h / 10 + 100), causer, true) end)
    if not ok then pcall(function() o.HealthInternal = 0 end) end
end

local function bindCopy(id, o)
    if M.dead[id] then killCopy(id, o); return end
    local a = addrOf(o)
    local r = (type(SV_CoopBind) == "function" and a) and SV_CoopBind(id, a) or -9
    if r ~= 1 then once("bind" .. tostring(r), "coop: a copy couldn't be bound (" .. tostring(r) .. "): it flies on its own") end
    pcall(function() o:SetMinHealth(0.1) end)               -- (it goes down when the host's does)
    M.copies[id] = { obj = o, exp = health(o) or 0, addr = a }
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
    local cu = M.cunits[unit]
    if not cu then return end
    cu.n = cu.n + 1
    cu.planes[cu.n] = o
    local id = cu.binds[cu.n]
    if id then bindCopy(id, o) end
end

-- a ship's, vehicle's or part's copy (groundTick): not moved, held up until the host's goes down, its hits sent
local function bindGround(id, o)
    if M.dead[id] then killCopy(id, o); M.copies[id] = nil; return end
    pcall(function() o:SetMinHealth(0.1) end)
    M.copies[id] = { obj = o, exp = health(o) or 0, addr = addrOf(o) }  -- (addr: a shot's target, "fx")
end
clientGround = function(o, unit)
    local cu = M.cunits[unit]
    if not cu then return end
    cu.gcount, cu.gobjs = cu.gcount or {}, cu.gobjs or {}
    local key = groundKey(o, cu.gcount)
    cu.gobjs[key] = o
    local id = cu.gbinds and cu.gbinds[key]
    if id then bindGround(id, o) end
end

local function killAllCopies(why)
    local n = 0
    for id, c in pairs(M.copies) do killCopy(id, c.obj); n = n + 1 end
    M.copies, M.cunits, M.spawnQ, M.dead, M.holdQ = {}, {}, {}, {}, nil
    if n > 0 then log("coop: " .. n .. " copies taken down (" .. why .. ")") end
end

local function doSpawn(q)
    local unit = q.unit
    local had = M.cunits[unit]
    if had and had.gen == q.gen and had.n > 0 then return true end   -- (that flight is up here already)
    if rawUnitAlive and rawUnitAlive(unit) > 0 then      -- the copy of its last flight still up: down first
        local cu = M.cunits[unit]
        if cu and cu.gen ~= q.gen then
            for ord, o in pairs(cu.planes) do local id = cu.binds[ord]; killCopy(id or 0, o); if id then M.copies[id] = nil end end
            for key, o in pairs(cu.gobjs or {}) do
                local id = cu.gbinds and cu.gbinds[key]; killCopy(id or 0, o); if id then M.copies[id] = nil end
            end
        end
        q.tries = (q.tries or 0) + 1
        if q.tries < 6 then q.at = os.clock() + 1.5; return false end
        log("coop: " .. unit .. "'s last copies are still up; spawning anyway")
    end
    for _, op in ipairs(q.ops) do
        if not knownRow(op.row) then
            once("row" .. tostring(op.row), "coop: the host's aircraft " .. short(op.row, 64) .. " isn't in this game's table; not set")
        elseif op.idx >= 0 then rawSetAircraft(unit, op.row, op.idx) else rawSetAircraft(unit, op.row) end
    end
    if q.level and q.level >= 0 and rawSetLevel then rawSetLevel(unit, q.level) end
    local old = M.cunits[unit]
    local same = old and old.gen == q.gen
    M.cunits[unit] = { gen = q.gen, n = 0, planes = {}, binds = same and old.binds or {}, gbinds = same and old.gbinds or {} }
    spawningUnit, spawningIdx = unit, 0                  -- (each copy's index in its flight, p.k: the host's order too)
    local r
    if q.pose then r = rawSpawn(unit, q.pose[1], q.pose[2], q.pose[3], q.pose[4]) else r = rawSpawn(unit) end
    spawningUnit, spawningIdx = nil, nil
    if r == -6 or r == -1 then                           -- (this game's level isn't ready: again in a second)
        q.tries = (q.tries or 0) + 1
        if q.tries < 30 then q.at = os.clock() + 1; M.cunits[unit] = old; return false end
    end
    M.lastSpawnAt = os.clock()
    if type(r) ~= "number" or r <= 0 then
        log("coop: the host's " .. unit .. " not spawned here (" .. (SV_ERR[r] or tostring(r)) .. ")")
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
        D.state = r.state
        if r.state == "wait" then D.at = now + r.secs - (os.clock() - r.got) else D.at = now end
        D.wave = r.wave > 0 and r.wave or nil
        D.intLevel = r.level and { round = r.round, level = r.level } or nil   -- (the copies fly it: DIR.level, P4)
        D.glitchPhase = r.glitchPhase                    -- (AB.L..IN's on the host: ANOM.clientGlitch, P7)
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
            if os.clock() - e.at < 60 then hostEvent(e.name) end      -- (a hold: once its copy has had its orders)
        end
    end
end

local function clientTick()
    -- the copies' hits: what each lost since last time goes to the host, less what another player's stand-in did to it
    -- here (their own hits come from their game: the stand-ins fly damage-0 rows, COOP.syncSetup; this is the backstop)
    local ins = nil
    for id, c in pairs(M.copies) do
        if valid(c.obj) then
            local h = health(c.obj)
            if h and h < c.exp then
                local loss = c.exp - h
                ins = ins or (M.standInSet and M.standInSet()) or {}
                if next(ins) and M.standInDamage then
                    local sd = M.standInDamage(c.obj, ins)
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
                end
                if loss > 0 then send(true, "ht", id, string.format("%.1f", loss / 10)) end
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
local function spawnReal(slot, P, code, lo)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return nil, "you have no plane here yet" end
    local path = COOP.planeClassPath(code)
    if not path then return nil, "no player plane blueprint for " .. tostring(code) end
    local cls = loadObject(path)
    if not valid(cls) then return nil, "its class didn't load (" .. path .. ")" end
    local at, yaw = P.at, (P.rot and P.rot[2]) or 0
    local a = SV_CoopSpawnPP(addrOf(pawn), at.X, at.Y, at.Z, yaw, addrOf(cls), slot, lo or "")
    if type(a) ~= "number" or a <= 0 then return nil, "SV_CoopSpawnPP " .. tostring(a) end
    for _, x in ipairs(FindAllOf("LivePlayerPlane") or {}) do
        if valid(x) and addrOf(x) == a then return x end
    end
    return nil, "spawned (" .. tostring(a) .. ") but not found"
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
    else
        P.at, P.fresh, P.down = nil, false, nil
    end
    if not D then return end
    if P.obj and not valid(P.obj) then P.obj, P.addr, P.real = nil, nil, nil end
    local unit = PEER_UNITS[slot]
    -- Their airframe comes in their "hi" (or the host's "pi") once their plane is up, and their state can come first:
    -- the stand-in spawned on the empty row of their main-menu "hi" flew the default, F-16C, for the whole run (the
    -- user's co-op run of 2026-10-29: "players are flying F-16's on my side but different aircraft on their side"; an
    -- AI plane up can't change airframe). So it waits up to AIRFRAME_WAIT_S for a row, then flies the default.
    P.freshAt = fresh and (P.freshAt or os.clock()) or nil
    local r0 = M.roster[slot]
    local known = r0 and type(r0.row) == "string" and r0.row ~= ""
    local code = r0 and r0.code ~= "" and r0.code or nil
    if P.realFailed and P.realFailed ~= code then P.realFailed = nil end        -- (another airframe: try again)
    local lo = r0 and r0.lo or ""
    -- (new weapons mid-level: their real plane here keeps the loadout it was spawned with. Replacing a live real plane
    -- crashed the game: the user's co-op run of 2026-10-30, 21:37:39, an access violation reading the destroyed plane a
    -- frame on, some game system still holding it; so it's never destroyed mid-level, and the next level's has them)
    if P.real and P.obj and lo ~= "" and lo ~= (P.lo or "") and P.loSaid ~= lo then
        P.loSaid = lo
        log(string.format("coop: player %d's loadout changed: their real plane here keeps the one it was spawned with "
            .. "(the next level's has the new one)", slot + 1))
    end
    if fresh and not P.obj and not P.spawning and levelReady() and realOn() and code and P.realFailed == nil then
        local o, why = spawnReal(slot, P, code, lo)
        if o then
            P.obj, P.addr, P.real, P.code, P.shown, P.lo = o, addrOf(o), true, code, nil, lo
            P.gear, P.flare, P.gunNext, P.flareNext, P.gunOn = nil, nil, nil, nil, nil
            log(string.format("coop: player %d's plane is their real %s (a player plane, %X): flown by its own update from their "
                .. "stream; %s", slot + 1, code, P.addr or 0, lo ~= "" and ("their loadout " .. lo) or "its default loadout (none sent)"))
        else
            P.realFailed = code
            log(string.format("coop: player %d's real plane (%s) not spawned: %s; their AI stand-in instead", slot + 1, code,
                tostring(why)))
        end
    end
    if fresh and not P.obj and not P.spawning and levelReady()                 -- (not while this level loads)
        and (known or os.clock() - P.freshAt >= AIRFRAME_WAIT_S) then
        local row = standInRow(r0 and r0.row)
        local fly = M.flyRow and M.flyRow(row) or row        -- (its damage-0 copy, <row>_svcp: the sync's)
        rawSetAircraft(unit, fly)
        spawningUnit = unit
        local r = rawSpawn(unit)
        spawningUnit = nil
        P.spawning, P.row = os.clock(), row
        log(string.format("coop: player %d's plane as %s%s: %s", slot + 1, fly,
            known and "" or string.format(" (no airframe from them in %d s)", AIRFRAME_WAIT_S),
            (type(r) == "number" and r > 0) and "spawned" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    elseif P.spawning and os.clock() - P.spawning > 10 then
        P.spawning = nil                                  -- (it never came: again)
    end
    if P.obj then
        -- (hidden while they're DOWN too, sv_down.lua: flown round their airfield out of the fight, nothing to see or hit)
        local show = (fresh and not P.down) and true or false
        if show ~= P.shown then
            P.shown = show
            pcall(function() P.obj:SetActorHiddenInGame(not show) end)
            pcall(function() P.obj:SetActorEnableCollision(show) end)
            if type(SV_CoopPeer) == "function" then SV_CoopPeer(slot, show and P.addr or 0) end
            log(string.format("coop: player %d's plane %s", slot + 1, show and "shown"
                or (fresh and "hidden (down)" or "hidden (not in the mission)")))
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
function COOP.msg(to, ...) return sendTo(to, true, ...) end
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
        local a = valid(w) and addrOf(w)
        if a then
            cur[a] = true
            if S.primed and not S.seen[a] then
                local k = kindOf(w)
                if k then
                    local okT, t = pcall(function() return w.TargetToHome end)
                    out[#out + 1] = string.format("%s:%d:0", k, (okT and valid(t)) and idOfAddr(addrOf(t)) or 0)
                    if k == "s" then S.spShotAt = os.clock() end     -- (a special weapon in flight: not electronic)
                end
            end
        end
    end
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
local function coopFire(slot, fcs, target)
    -- (your landing STORE open: the game holds the other planes inactive there and refuses their fire; the co-op run of
    -- 2026-10-30: 1,093 of its 1,094 refused shots came while that game's player was in the STORE)
    if D and D.musicHold == 1 then S.n.inStore = (S.n.inStore or 0) + 1; return nil end
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
                    and not (D and D.musicHold == 1) then
                    local okS, r = pcall(SV_CoopPPShot, P.addr, addrOfId(pid) or 0, pay)
                    if not okS then r = tostring(r) end
                    if r == 1 then S.n.pOk = (S.n.pOk or 0) + 1 else S.n.pBad = (S.n.pBad or 0) + 1 end
                    once("pfirst" .. slot, string.format("coopfire: player %d's first launch on their real plane here: %s", slot + 1,
                        r == 1 and "queued" or ("refused (" .. tostring(r) .. ")")))
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

-- the other players' state bits on their planes here: gear flips, gun bursts, flares
local function peersTick(now)
    for s, P in pairs(M.peers) do
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
                local gun = on("guns") and bit(fl, BIT_GUN) or false
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
        if n.sent + n.got + n.fired + n.failed + n.dropped + (n.bursts or 0) + (n.flares or 0) + (n.pOk or 0) + (n.pBad or 0) > 0 then
            log(string.format("coopfire: 60 s: %d shots sent, %d received (%d fired here, %d refused, %d dropped, %d with "
                .. "their target not here, %d with no plane here, %d not shown: you were in the STORE), your gun %d bursts, "
                .. "your flares %d, your gear flips %d, afterburner flips %d, throttle up to %.3f (ab_throttle %s); real planes' "
                .. "launches (T4b) %d queued, %d refused", n.sent,
                n.got, n.fired, n.failed, n.dropped, n.untargeted or 0, n.noPlane or 0, n.inStore or 0, n.bursts or 0,
                n.flares or 0, n.gear, n.ab, (n.thMax or 0) / 1000, tostring(sc().ab_throttle), n.pOk or 0, n.pBad or 0))
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
local function sendHi()
    local row, code = myAirframe()
    -- (what the host last heard: a hello sent with no plane yet is followed by the airframe once there is one; the
    -- co-op run of 2026-10-30: a player who'd been in the level before linking never sent theirs, shown as the default)
    -- The airframe's code (COOP2MP T3: the player plane the others spawn for you; the ADFX-02 has no AI row) goes last.
    M.myRow, M.myCode, M.myLo = row, code, M.myLoadout()
    send(true, "hi", VERSION, type(SV_Version) == "function" and SV_Version() or "?", row or "", M.myName or "", code or "", M.myLo)
end

-- the host's own roster entry, and everyone told
local function hostRosterSelf()
    local row, code = myAirframe()
    M.myRow, M.myCode, M.myLo = row, code, M.myLoadout()
    M.roster[0] = { row = row or "", ver = VERSION, name = M.myName or "", code = code or "", lo = M.myLo }
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
                   log = true }                                                 -- ([log] verbose: each game's log)
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

local function onHostMessage(from, f)
    local k = f[1]
    if k == "hi" then
        local ver, rt, row, name = short(f[2], 32), short(f[3], 16), short(f[4], 64), short(f[5], 32)
        local code = short(f[6], 16):match("^%w+$") or ""          -- (their airframe's code: COOP2MP T3)
        local lo = loadoutOk(f[7]) and f[7] or ""                  -- (their loadout: COOP2MP T4b)
        if not name or name == "" then name = (M.linkNames and M.linkNames[from]) or ("PLAYER " .. (from + 1)) end
        local first, was = not M.roster[from], M.roster[from] and M.roster[from].row
        M.roster[from] = { row = row or "", ver = ver, name = name, code = code, lo = lo }
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
    elseif k == "fx" then M.fxFromJoiner(from, f)       -- a joiner's shots: its plane here fires them, the others told
    elseif (k == "dw" or k == "rv") and DOWN and DOWN.onHost then DOWN.onHost(from, f)   -- (down, a revive: sv_down.lua)
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
    elseif (k == "dw" or k == "rb" or k == "rx" or k == "ro" or k == "rc") and DOWN and DOWN.onJoiner then DOWN.onJoiner(f)   -- (sv_down.lua)
    elseif k == "rnd" then
        local lv = tonumber(f[8])                         -- (the intensity director's level, P4: a whole 0-3, else none)
        if not (lv and lv == math.floor(lv) and lv >= 0 and lv <= #SPIKE_SUFFIX) then lv = nil end
        local gp = tonumber(f[9])                         -- (AB.L..IN's phase, P7: 1-3, else none)
        if not (gp == 1 or gp == 2 or gp == 3) then gp = nil end
        M.rnd = { round = tonumber(f[2]) or 0, state = f[3], secs = tonumber(f[4]) or 0, wave = tonumber(f[5]) or 0,
                  waves = tonumber(f[6]) or 0, alive = tonumber(f[7]) or 0, level = lv, glitchPhase = gp, got = os.clock() }
    elseif k == "pi" then
        local s = tonumber(f[2])
        if not slotOk(s) then return end
        f[3], f[4], f[5] = short(f[3], 64), short(f[4], 32), short(f[5], 32)
        local first, was = not M.roster[s], M.roster[s] and M.roster[s].row
        M.roster[s] = { row = f[3], ver = f[4], name = f[5], code = short(f[6], 16):match("^%w+$") or "",
                        lo = loadoutOk(f[7]) and f[7] or "" }
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
        M.spawnQ[#M.spawnQ + 1] = { unit = unit, pose = pose, ops = ops, level = tonumber(f[5]), gen = tonumber(f[6]) or 0 }
    elseif k == "bd" then
        local unit, gen, ord, id = f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
        local cu = M.cunits[unit]
        if not cu or cu.gen ~= gen then                   -- (its spawn is still queued: keep the id for it)
            cu = { gen = gen, n = 0, planes = {}, binds = {} }
            local queued = false
            for _, q in ipairs(M.spawnQ) do if q.unit == unit and q.gen == gen then queued = true end end
            if not queued then return end
            M.cunits[unit] = cu
        end
        cu.binds[ord] = id
        if cu.planes[ord] then bindCopy(id, cu.planes[ord]) end
    elseif k == "gd" then                                -- a ship's, vehicle's or part's id (hostGround)
        local unit, gen, key, id = short(f[2], 96), tonumber(f[3]), short(f[4], 96), tonumber(f[5])
        if not (gen and id and id >= 1 and id <= 65535 and id == math.floor(id)) then return end
        local cu = M.cunits[unit]
        if not cu or cu.gen ~= gen then                   -- (its spawn is still queued: keep the id for it)
            local queued = false
            for _, q in ipairs(M.spawnQ) do if q.unit == unit and q.gen == gen then queued = true end end
            if not queued then return end
            cu = { gen = gen, n = 0, planes = {}, binds = {}, gbinds = {} }
            M.cunits[unit] = cu
        end
        cu.gbinds = cu.gbinds or {}
        cu.gbinds[key] = id
        local o = cu.gobjs and cu.gobjs[key]
        if o and valid(o) then bindGround(id, o) end
    elseif k == "hp" then
        for id, h in (f[2] or ""):gmatch("(%d+):(%-?%d+)") do
            local c = M.copies[tonumber(id)]
            h = tonumber(h)
            if c and valid(c.obj) and h and h > 0 then
                local v = math.min(math.max(h, 1), 2147483647)
                pcall(function() c.obj.HealthInternal = v end)
                c.exp = v
            end
        end
    elseif k == "dn" then
        local id = tonumber(f[2])
        if id then
            M.dead[id] = true
            local c = M.copies[id]
            if c then killCopy(id, c.obj); M.copies[id] = nil end
        end
    elseif k == "ev" then
        if mirroredEvent(f[2]) and D and rawEvent and not levelReady() then    -- (held until this level is ready)
            M.evQ = M.evQ or {}
            if #M.evQ < 64 then M.evQ[#M.evQ + 1] = { name = short(f[2], 64), at = os.clock() } end
        elseif mirroredEvent(f[2]) and D and rawEvent then
            hostEvent(f[2])
        end
    elseif k == "rs" then
        M.evQ, M.dvQ, M.holdQ = nil, nil, nil
        killAllCopies("the host's run started over")
        if DOWN and DOWN.reset then pcall(DOWN.reset, "the host's run started over") end    -- (down: back, no revives)
        -- (the measurements, sv_stats.lua: the open round ends here, not at the host's next round number; an "rs" that
        -- isn't the answer to this game's own "jn" of the last 15 s is the host's new run, which ends the run's records)
        local resync = M.jnAt ~= nil and os.clock() - M.jnAt < 15
        if STATS and D then pcall(STATS.hostReset, D.now, resync) end
        -- (the host's new run, not the answer to this game's own "jn": the money and gear start over here too)
        if D and not resync and type(newRunHere) == "function" then
            local okN, errN = pcall(newRunHere, "the host's run started over")
            if not okN then log("run: error " .. tostring(errN)) end
        end
        if D then D.round, D.state, M.rnd = 0, "wait", nil end
    end
end

local function onSys(from, what, f)
    if what == "joined" then                              -- (host) a joiner linked: its "hi" names it
        log("coop: player " .. (from + 1) .. " linked")
    elseif what == "paired" or what == "restart" then      -- (joiner) the host; (either) a game started over
        sendHi()
        if COOP.client() and D then killAllCopies("new link"); M.jnAt = os.clock(); send(true, "jn") end
        if COOP.host() and what == "restart" then M.roster[from] = nil end
    elseif what == "slot" then
        COOP.slot = tonumber(f[3])
        log("coop: you are player " .. tostring((COOP.slot or -1) + 1))
    elseif what == "lost" then
        M.wasLost = M.wasLost or {}
        M.wasLost[from] = true
        callout("CO-OP LINK LOST", string.upper(playerName(from)))
    elseif what == "up" then
        if M.wasLost and M.wasLost[from] then             -- (the first "up" comes right after "paired" / "joined")
            M.wasLost[from] = nil
            callout("CO-OP LINK BACK", string.upper(playerName(from)))
            if COOP.client() and D then killAllCopies("link back"); M.jnAt = os.clock(); send(true, "jn") end
        end
    elseif what == "left" then
        callout(string.upper(playerName(from)) .. " LEFT", nil)
        M.roster[from] = nil
        local P = M.peers[from]
        if P and P.obj then pcall(function() P.obj:SetActorHiddenInGame(true) end); P.shown = false end
        if COOP.host() then send(true, "po", from) end
    elseif what == "full" then
        callout("CO-OP: THE HOST'S GAME IS FULL", nil)
    elseif what == "samerole" then
        if M.auto and COOP.host() and playerCount() <= 1 and not D then   -- (an automatic host, alone, not in a run)
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
local rawSide = KILL.side
KILL.side = function(o, pawnAddr)
    local a = addrOf(o)
    if a then for _, P in pairs(M.peers) do if P.addr and P.addr == a then return "wingmate" end end end
    return rawSide(o, pawnAddr)
end
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
function COOP.reopen(role, why)
    local c = cfg()
    local r = SV_CoopOpen(c.transport or "steam", role, c.partner or "auto", c.port or 27777, c.interp_ms or 120, VERSION,
                          maxPlayers())
    COOP.open, COOP.role, COOP.slot = r == 1, role, role == "host" and 0 or nil
    M.state, M.roster = nil, {}
    if role == "host" then M.restoreMine() end          -- (you host: your own settings)
    M.autoAt = os.clock() + AUTO_WAIT + math.random() * AUTO_WAIT
    log(string.format("coop: %s as the %s over %s (partner %s, up to %d players; %s): %s", r == 1 and "open" or "NOT open",
        role == "host" and "host" or "joiner", tostring(c.transport), tostring(c.partner), maxPlayers(), why,
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
        local n = upperName(playerName(s), 20)
        if M.nameSet[s] ~= n then
            M.nameSet[s] = n
            pcall(SV_SetText, NAME_KEYS[s], n)
        end
    end
end

-- The HUD's co-op row (sv_hud.lua hudTick): who is playing, the host first and marked, in plain words; nil when solo.
-- With lines > 0 (the HUD's info key open, CFG.hud.info) the row is "CO-OP 3/4" and up to that many lines follow it,
-- one a player (name, HOST, FLYING / AT THE AIRFIELD / DOWN / NOT IN THE MISSION, health), the last "+N MORE" when
-- they don't all fit. Its second value is the row's news for the info key: who's in, links lost and who's shot down
-- (not health, where they are or a state gone stale).
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
function COOP.hudLine(lines)
    if not COOP.open then return nil end
    if COOP.client() and M.state ~= "linked" then
        local s = M.auto and "CO-OP: LOOKING FOR A HOST..." or "CO-OP: LOOKING FOR A FRIEND WHO PICKED HOST..."
        return s, s
    end
    lines = lines or 0
    local names, news, list, n = {}, {}, {}, 0
    for s = 0, MAX_SLOT do
        if M.roster[s] or s == COOP.slot then
            n = n + 1
            local nm = upperName(playerName(s), 14) .. (s == 0 and " (HOST)" or "")
            if M.wasLost and M.wasLost[s] then nm = nm .. " (LOST)" end
            if n <= HUD_NAMES then names[#names + 1] = nm end       -- (a big room: the first few, then "+N")
            local st, hp = hudState(s)
            -- (shot down by the last state their game sent, not by its freshness: a lagging link flips that)
            local P, down = M.peers[s], st == "DOWN"
            if s ~= COOP.slot then down = P ~= nil and (P.flags or 0) % 2 == 1 and P.alive == false end
            news[#news + 1] = s .. nm .. (down and " DOWN" or "")
            if #list < lines then
                list[#list + 1] = "  " .. nm .. (st ~= "" and "   " .. st or "") .. (hp and string.format("  %d%%", hp) or "")
            end
        end
    end
    if COOP.host() and n <= 1 then
        local s = "CO-OP: YOU ARE THE HOST, WAITING FOR FRIENDS"
        return s, s
    end
    news = table.concat(news, "|")
    if lines > 0 then
        if n > lines then list[lines] = string.format("  +%d MORE", n - lines + 1) end
        return string.format("CO-OP %d/%d", n, maxPlayers()), news, list
    end
    if n > #names then names[#names + 1] = "+" .. (n - #names) end
    return string.format("CO-OP %d/%d: %s", n, maxPlayers(), table.concat(names, "  ")), news
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


function COOP.tick(tick)
    local c = cfg()
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
            M.peers[s] = (P.obj and valid(P.obj)) and { obj = P.obj, addr = addrOf(P.obj) } or {}
        end
        M.units, M.byId, M.copies, M.cunits, M.spawnQ, M.dead, M.hunts = {}, {}, {}, {}, {}, {}, {}
        M.replays, groundNew, M.holdQ = {}, {}, nil
        M.svcpUsable = {}                                              -- (the stand-ins' damage-0 rows in before it loaded)
        for row, sv in pairs(M.svcpReady or {}) do M.svcpUsable[row] = sv end
        if D then
            if COOP.host() then send(true, "rs") else M.jnAt = os.clock(); send(true, "jn") end
            log("coop: in Survival's level as " .. (COOP.host() and "the host" or ("player " .. tostring((COOP.slot or -1) + 1))))
            if COOP.client() and M.state ~= "linked" then
                callout(M.auto and "CO-OP: LOOKING FOR A HOST" or "CO-OP: WAITING FOR THE HOST",
                        M.auto and "NONE FOUND: YOU HOST" or tostring(c.partner))
            elseif COOP.host() then
                callout("CO-OP: YOU ARE THE HOST", string.format("PLAYERS %d/%d", playerCount(), maxPlayers()))
            end
        end
    end
    if not D then return end
    -- An online-style pause (user, 2026-10-26: "when the Host Pauses, the game doesn't pause all the enemies for the
    -- other players"): while another player is linked, the pause menu opens but the world keeps running, on the host's
    -- game (its enemies, which every game copies) and on a joiner's (its plane). Alone, the game pauses as ever.
    if (M.linkedPeers or 0) > 0 and valid(survivalPC) and gamePaused(survivalPC) then
        local gs = cdo("/Script/Engine.Default__GameplayStatics")
        local ok = gs and pcall(function() gs:SetGamePaused(survivalPC, false) end)
        M.unpauses = (M.unpauses or 0) + 1
        if M.unpauses == 1 or M.unpauses % 40 == 0 then
            log(string.format("coop: paused with %d players: the world kept running (%s; %d times)", playerCount(),
                ok and "unpaused" or "COULD NOT unpause", M.unpauses))
        end
        if M.unpauses == 1 then callout("CO-OP: THE GAME KEEPS RUNNING", "OTHER PLAYERS ARE STILL FLYING") end
    end
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
        local lo = M.myLoadout()                              -- (new weapons picked at the airfield: COOP2MP T4b)
        if (row and row ~= M.myRow) or (code and code ~= M.myCode) or (lo ~= "" and lo ~= M.myLo) then
            M.myRow, M.myCode = row, code
            if COOP.host() then hostRosterSelf() else sendHi() end
        end
    else
        SV_CoopMe(0, 0)
    end
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
end
end
