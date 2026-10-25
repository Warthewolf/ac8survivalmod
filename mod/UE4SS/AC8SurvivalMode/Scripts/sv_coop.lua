-- AC8 Survival Mode - runtime part sv_coop: Survival COOP (CFG.coop; the native half is dlls\main.dll 0.22.0 coop.c;
-- tools/re/COOP.md). Up to 4 players, one run, host-authoritative after the AC7 co-op mod Double Trigger. Player 1
-- (slot 0) is the host, players 2-4 (slots 1-3) the joiners, each linked to the host only:
--   host:    runs everything as in single player. Every flight it spawns (SV_Spawn, with the SV_SetAircraft /
--            SV_SetLevel calls before it) goes to every joiner, every aircraft of it gets a stream id (its position and
--            rotation go out 15 times a second, natively), its health once a second, its death at once. A joiner's
--            hits on its copies come back and are dealt as real damage (ModifyHealth, the cause that joiner's plane).
--            It keeps the roster (each player's name, airframe, version) and sends it to everyone.
--   joiner:  spawns no rounds of its own (roundsTick, airfieldTick and bombTick are the host's): it spawns the host's
--            flights, binds each copy to its stream (the runtime moves it every frame to where the host's is) and keeps
--            it alive (MinHealth) until the host says it's down. Its round, callouts, airfield and round bonuses are
--            the host's. Each player's kills pay their own zollars (KILL.by: another player is the "wingmate" side).
--   everyone: each other player's plane is SV_Unit_CoopPeer<A-D> (A for player 1 ... D for player 4: an allied AI
--            plane, fire off, invincible), moved every frame to where that player is (the host relays the joiners'
--            planes to each other). split_share of the host's fighter flights take the stock allied-hunt order: they
--            go for the joiners' planes too.
-- Messages are "kind|field|field...", reliable unless said: rnd (unreliable), af, co, cr, sp, bd, hp, dn, rs, pi, po,
-- ev (host), hi, jn, ht (joiner). SV_CoopRecv hands them over as "<sender's slot>|<message>".
COOP = { open = false, role = nil, slot = nil }

do
local PEER_UNITS = { [0] = "SV_Unit_CoopPeerA", "SV_Unit_CoopPeerB", "SV_Unit_CoopPeerC", "SV_Unit_CoopPeerD" }
local SLOT_OF = {}
for s = 0, 3 do SLOT_OF[PEER_UNITS[s]] = s end
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
}
local function mirroredEvent(name)
    name = tostring(name)
    if not name:match("^RE_SV_") then return false end
    if name:match("^RE_SV_Glitch") and not (name:match("^RE_SV_GlitchEcm") or name:match("^RE_SV_GlitchGun")) then
        return false                                     -- (AB.L..IN's post-stall moves and blinks: as the aces' turns)
    end
    for _, p in ipairs(KEEP_EVENTS) do if name:match(p) then return false end end
    return true
end
local rawEvent = SV_Event
if rawEvent then
    SV_Event = function(name, ...)
        local r = rawEvent(name, ...)
        if COOP.host() and mirroredEvent(name) then send(true, "ev", name) end
        return r
    end
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
    M.units[unit] = { gen = M.gen, pose = pose, ops = ops, level = level, n = 0, planes = {} }
    sendUnit(nil, unit, M.units[unit])
end

local function anyJoinerPlane()
    for s = 1, 3 do if M.peers[s] and M.peers[s].obj then return true end end
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
    M.byId[id] = { obj = o, unit = unit, ord = u.n }
    if type(SV_CoopTrack) == "function" and a then SV_CoopTrack(id, a) end
    send(true, "bd", unit, u.gen, u.n, id)
    -- split the fighters between you: a pool flight goes after the joiners' planes (allied aircraft here) with
    -- split_share, once it's had its orders
    if u.n == 1 and poolIndex(unit) and anyJoinerPlane() and math.random() < (cfg().split_share or 0) then
        M.hunts[#M.hunts + 1] = { at = os.clock() + 5, name = string.format("RE_SV_Hunt_%02d", poolIndex(unit)), unit = unit }
    end
end

-- the roster: who's in which slot, their airframe and version, to every joiner (on a change)
local function sendRoster(to)
    for s = 0, 3 do
        local r = M.roster[s]
        if r then sendTo(to, true, "pi", s, r.row or "", r.ver or "", r.name or "") end
    end
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
                if type(SV_CoopTrack) == "function" then SV_CoopTrack(id, 0) end
                local u = M.units[e.unit]
                if u and u.planes[e.ord] then u.planes[e.ord].dead = true end
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
    -- a flight with nothing left alive is forgotten (it's spawned again as a new one)
    for unit, u in pairs(M.units) do
        local alive = false
        for _, pl in pairs(u.planes) do if not pl.dead then alive = true end end
        if u.n > 0 and not alive then M.units[unit] = nil end
    end
    -- the round and the airfield
    if D and now >= M.nextRnd then
        M.nextRnd = now + 1
        local alive = 0
        for _, p in ipairs(planes or {}) do if not p.down then alive = alive + 1 end end
        local secs = (D.state == "wait" and D.at and D.now) and math.max(0, D.at - D.now) or 0
        send(false, "rnd", D.round or 0, D.state or "wait", string.format("%.1f", secs), D.wave or 0, D.waves and #D.waves or 0, alive)
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
            if D and D.up and D.up[h.unit] and type(SV_Event) == "function" then
                local r = SV_Event(h.name)
                log("coop: " .. h.unit .. " goes after the joiners (" .. h.name .. " " .. tostring(r) .. ")")
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
    end
    M.afKey, M.nextRnd, M.nextAf = nil, 0, 0
    log(string.format("coop: sent player %d the run: %d flights", to + 1, n))
end

local function hostHit(from, id, dmg)
    local e = M.byId[id]
    if not (e and not e.dead and valid(e.obj) and dmg > 0) then return end
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
    M.copies[id] = { obj = o, exp = health(o) or 0 }
end

local function clientPlane(o, unit)
    local cu = M.cunits[unit]
    if not cu then return end
    cu.n = cu.n + 1
    cu.planes[cu.n] = o
    local id = cu.binds[cu.n]
    if id then bindCopy(id, o) end
end

local function killAllCopies(why)
    local n = 0
    for id, c in pairs(M.copies) do killCopy(id, c.obj); n = n + 1 end
    M.copies, M.cunits, M.spawnQ, M.dead = {}, {}, {}, {}
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
        end
        q.tries = (q.tries or 0) + 1
        if q.tries < 6 then q.at = os.clock() + 1.5; return false end
        log("coop: " .. unit .. "'s last copies are still up; spawning anyway")
    end
    for _, op in ipairs(q.ops) do
        if op.idx >= 0 then rawSetAircraft(unit, op.row, op.idx) else rawSetAircraft(unit, op.row) end
    end
    if q.level and q.level >= 0 and rawSetLevel then rawSetLevel(unit, q.level) end
    local old = M.cunits[unit]
    M.cunits[unit] = { gen = q.gen, n = 0, planes = {}, binds = (old and old.gen == q.gen) and old.binds or {} }
    spawningUnit = unit
    local r
    if q.pose then r = rawSpawn(unit, q.pose[1], q.pose[2], q.pose[3], q.pose[4]) else r = rawSpawn(unit) end
    spawningUnit = nil
    if r == -6 or r == -1 then                           -- (this game's level isn't ready: again in a second)
        q.tries = (q.tries or 0) + 1
        if q.tries < 30 then q.at = os.clock() + 1; M.cunits[unit] = old; return false end
    end
    if type(r) ~= "number" or r <= 0 then
        log("coop: the host's " .. unit .. " not spawned here (" .. (SV_ERR[r] or tostring(r)) .. ")")
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

local function clientRounds(now)
    if not D then return end
    D.now = now
    local r = M.rnd
    if r then
        if r.round ~= D.round then
            D.round = r.round
            RUN.roundKills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 }
        end
        D.state = r.state
        if r.state == "wait" then D.at = now + r.secs - (os.clock() - r.got) else D.at = now end
        D.wave = r.wave > 0 and r.wave or nil
        if r.waves > 0 then D.waves = D.waves and #D.waves == r.waves and D.waves or {}; for i = #D.waves + 1, r.waves do D.waves[i] = {} end
        else D.waves = nil end
    end
    if not levelReady() then return end
    for i = #M.spawnQ, 1, -1 do
        local q = M.spawnQ[i]
        if os.clock() >= (q.at or 0) then
            local okS, done = pcall(doSpawn, q)
            if not okS then log("coop: spawn error " .. tostring(done)); done = true end
            if done then table.remove(M.spawnQ, i) end
        end
    end
end

local function clientTick()
    -- the copies' hits: what each lost since last time goes to the host
    for id, c in pairs(M.copies) do
        if valid(c.obj) then
            local h = health(c.obj)
            if h and h < c.exp then
                send(true, "ht", id, string.format("%.1f", (c.exp - h) / 10))
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
local function myAirframe()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return nil end
    local code = nameOf(pawn):match(AF_CODE)
    local c = cfg()
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
    local r = type(SV_CoopPeer) == "function" and P.addr and SV_CoopPeer(slot, P.addr) or -9
    log(string.format("coop: player %d's plane is up (%s, %s)", slot + 1, nameOf(o):match("([^%.:]+)$") or "?",
        r == 1 and "moved every frame" or ("NOT moved: " .. tostring(r))))
end

local function peerTick(slot)
    local s = type(SV_CoopPeerAt) == "function" and SV_CoopPeerAt(slot) or ""
    local f = {}
    for v in s:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
    local fresh = #f >= 10 and f[10] < 3000 and (math.floor(f[9]) % 2 == 1)        -- (flag 1: in Survival's level)
    local P = M.peers[slot] or {}
    M.peers[slot] = P
    if not D then return end
    if P.obj and not valid(P.obj) then P.obj, P.addr = nil, nil end
    local unit = PEER_UNITS[slot]
    if fresh and not P.obj and not P.spawning and levelReady() then          -- (not while this level loads)
        local r0 = M.roster[slot]
        local row = (r0 and r0.row ~= "" and r0.row) or cfg().default
        rawSetAircraft(unit, row)
        spawningUnit = unit
        local r = rawSpawn(unit)
        spawningUnit = nil
        P.spawning = os.clock()
        log(string.format("coop: player %d's plane as %s: %s", slot + 1, row,
            (type(r) == "number" and r > 0) and "spawned" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    elseif P.spawning and os.clock() - P.spawning > 10 then
        P.spawning = nil                                  -- (it never came: again)
    end
    if P.obj then
        local show = fresh and true or false
        if show ~= P.shown then
            P.shown = show
            pcall(function() P.obj:SetActorHiddenInGame(not show) end)
            if type(SV_CoopPeer) == "function" then SV_CoopPeer(slot, show and P.addr or 0) end
            log(string.format("coop: player %d's plane %s", slot + 1, show and "shown" or "hidden (not in the mission)"))
        end
    end
end

---------------------------------------------------------------------------------------------------- messages
local function sendHi()
    local row = myAirframe()
    send(true, "hi", VERSION, type(SV_Version) == "function" and SV_Version() or "?", row or "", M.myName or "")
end

-- the host's own roster entry, and everyone told
local function hostRosterSelf()
    M.roster[0] = { row = myAirframe() or "", ver = VERSION, name = M.myName or "" }
    sendRoster(nil)
end

local function onHostMessage(from, f)
    local k = f[1]
    if k == "hi" then
        local ver, rt, row, name = f[2], f[3], f[4], f[5]
        if not name or name == "" then name = (M.linkNames and M.linkNames[from]) or ("PLAYER " .. (from + 1)) end
        local first = not M.roster[from]
        M.roster[from] = { row = row or "", ver = ver, name = name }
        if first then
            log(string.format("coop: player %d is %s, Survival %s, runtime %s, flies %s", from + 1, tostring(name), tostring(ver),
                tostring(rt), tostring(row)))
            callout(string.upper(tostring(name)) .. " JOINED", string.format("PLAYERS %d/%d", playerCount(), cfg().max_players or 4))
            if ver ~= VERSION then
                log("coop: WARNING: player " .. (from + 1) .. " runs Survival " .. tostring(ver) .. ", you " .. VERSION)
                callout("CO-OP VERSION MISMATCH", string.upper(tostring(name)) .. " HAS " .. tostring(ver))
            end
        end
        hostRosterSelf()
    elseif k == "jn" then hostSync(from)
    elseif k == "ht" then hostHit(from, tonumber(f[2]) or 0, tonumber(f[3]) or 0)
    end
end

local function onJoinerMessage(f)
    local k = f[1]
    if k == "rnd" then
        M.rnd = { round = tonumber(f[2]) or 0, state = f[3], secs = tonumber(f[4]) or 0, wave = tonumber(f[5]) or 0,
                  waves = tonumber(f[6]) or 0, alive = tonumber(f[7]) or 0, got = os.clock() }
    elseif k == "pi" then
        local s = tonumber(f[2])
        if not s then return end
        local first = not M.roster[s]
        M.roster[s] = { row = f[3] or "", ver = f[4], name = f[5] }
        if first and s ~= COOP.slot then
            log(string.format("coop: player %d is %s (Survival %s, flies %s)", s + 1, tostring(f[5]), tostring(f[4]), tostring(f[3])))
            if s == 0 then
                callout("CO-OP LINKED", string.upper(tostring(f[5])) .. " IS HOSTING")
                if f[4] ~= VERSION then callout("CO-OP VERSION MISMATCH", "YOU " .. VERSION .. ", THE HOST " .. tostring(f[4])) end
            else
                callout(string.upper(tostring(f[5])) .. " JOINED", string.format("PLAYERS %d/%d", playerCount(), cfg().max_players or 4))
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
        if cfg().callouts then M.noMirror = true; pcall(hudCallout, f[2], f[3] ~= "" and f[3] or nil, f[4] == "1"); M.noMirror = false end
    elseif k == "cr" then
        local n = tonumber(f[2]) or 0
        if n > 0 then addCredits(n, tostring(f[3]) .. " (the host's round)") end
    elseif k == "sp" then
        local unit, pose, ops = f[2], nil, {}
        if f[3] and f[3] ~= "-" then
            local p = {}
            for v in f[3]:gmatch("[^,]+") do p[#p + 1] = tonumber(v) end
            if #p == 4 then pose = p end
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
    elseif k == "hp" then
        for id, h in (f[2] or ""):gmatch("(%d+):(%-?%d+)") do
            local c = M.copies[tonumber(id)]
            h = tonumber(h)
            if c and valid(c.obj) and h and h > 0 then
                local v = math.max(h, 1)
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
        if mirroredEvent(f[2]) and D and rawEvent and levelReady() then
            local r = rawEvent(f[2])
            if r ~= 1 then once("ev" .. tostring(r), "coop: the host's event " .. tostring(f[2]) .. " not fired here (" .. (SV_ERR[r] or tostring(r)) .. ")") end
        end
    elseif k == "rs" then
        killAllCopies("the host's run started over")
        if D then D.round, D.state, M.rnd = 0, "wait", nil end
    end
end

local function onSys(from, what, f)
    if what == "joined" then                              -- (host) a joiner linked: its "hi" names it
        log("coop: player " .. (from + 1) .. " linked")
    elseif what == "paired" or what == "restart" then      -- (joiner) the host; (either) a game started over
        sendHi()
        if COOP.client() and D then killAllCopies("new link"); send(true, "jn") end
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
            if COOP.client() and D then killAllCopies("link back"); send(true, "jn") end
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
            callout("CO-OP: TWO HOSTS", "ONE OF YOU: role = host, THE OTHERS: role = join OR auto")
        end
    end
end

local function onMessage(raw)
    local from = tonumber(raw:sub(1, 1)) or 0
    local f = split(raw:sub(3))
    if f[1] == "sys" then
        log("coop: player " .. (from + 1) .. ": " .. raw:sub(3))
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
addCredits = function(n, why)
    rawAddCredits(n, why)
    if COOP.host() and M.mirror > 0 and type(why) == "string" and not why:find(" down %(") and n > 0 then send(true, "cr", n, why) end
end
local rawLogPlane = logPlane
logPlane = function(o, unit)
    local slot = unit and SLOT_OF[unit]
    if slot then
        local ok, err = pcall(COOP.peerPlane, o, slot)
        if not ok then log("coop: player plane error " .. tostring(err)) end
        return
    end
    rawLogPlane(o, unit)
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
                          math.max(2, math.min(4, c.max_players or 4)))
    COOP.open, COOP.role, COOP.slot = r == 1, role, role == "host" and 0 or nil
    M.state, M.roster = nil, {}
    M.autoAt = os.clock() + AUTO_WAIT + math.random() * AUTO_WAIT
    log(string.format("coop: %s as the %s over %s (partner %s, up to %d players; %s): %s", r == 1 and "open" or "NOT open",
        role == "host" and "host" or "joiner", tostring(c.transport), tostring(c.partner), c.max_players or 4, why,
        r == 1 and (role == "host" and "looking for players" or "looking for the host") or
        ({ [-1] = "bad settings", [-2] = "Steam not available", [-3] = "UDP not available", [-4] = "partner isn't an IP address" })[r] or tostring(r)))
    if COOP.open and COOP.host() and M.myName ~= nil then hostRosterSelf() end
    return r
end

-- Opens co-op for this game: the role from CFG.coop.role (auto unless set), your name, and you in the roster as host
local function openCoop(why)
    local c = cfg()
    if type(SV_CoopOpen) ~= "function" then log("coop: dlls/main.dll has no co-op (0.22.0 or later needed)"); return end
    local role = tostring(c.role or "auto"):lower()
    if role == "joiner" or role == "client" then role = "join" end
    if role ~= "host" and role ~= "join" then role = "auto" end
    M.auto, M.linkedOnce = role == "auto", false
    log("coop: role " .. role .. (M.auto and " (a joiner that hosts if it finds no host)" or "") .. " from CFG.coop.role")
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
    log("coop: closed (" .. why .. ")")
end

-- Each player's name on their plane's target box (user, 2026-10-26: "we need to get player names working on the HUD
-- always"): the stand-ins SV_Unit_CoopPeer<A-D> carry the callsign key SV_CoopName_<A-D> (tools/build_survival.py
-- COOP_NAME_KEYS), whose text is set here whenever a name changes
local NAME_KEYS = { [0] = "SV_CoopName_A", "SV_CoopName_B", "SV_CoopName_C", "SV_CoopName_D" }
local function upperName(s, max)
    s = string.upper(tostring(s or ""))
    local n = utf8 and utf8.len(s)
    if n and n > max then return s:sub(1, utf8.offset(s, max + 1) - 1) end
    return n and s or s:sub(1, max)
end
local function nameTick()
    if type(SV_SetText) ~= "function" then return end
    M.nameSet = M.nameSet or {}
    for s = 0, 3 do
        local n = upperName(playerName(s), 20)
        if M.nameSet[s] ~= n then
            M.nameSet[s] = n
            pcall(SV_SetText, NAME_KEYS[s], n)
        end
    end
end

-- The HUD's co-op row (sv_hud.lua hudTick): who is playing, the host first and marked, in plain words; nil when solo
function COOP.hudLine()
    if not COOP.open then return nil end
    if COOP.client() and M.state ~= "linked" then
        return M.auto and "CO-OP: LOOKING FOR A HOST..." or "CO-OP: WAITING FOR THE HOST..."
    end
    local names = {}
    for s = 0, 3 do
        if M.roster[s] or s == COOP.slot then
            local n = upperName(playerName(s), 14) .. (s == 0 and " (HOST)" or "")
            if M.wasLost and M.wasLost[s] then n = n .. " (LOST)" end
            names[#names + 1] = n
        end
    end
    if COOP.host() and #names <= 1 then return "CO-OP: YOU ARE THE HOST, WAITING FOR FRIENDS" end
    return string.format("CO-OP %d/%d: %s", #names, cfg().max_players or 4, table.concat(names, "  "))
end

function COOP.tick(tick)
    local c = cfg()
    if not c.enabled then return end
    -- Co-op opens when the player picks SURVIVAL CO-OP on the main menu and closes on SURVIVAL MODE (SV_MenuChoice, the
    -- runtime's: 1 SURVIVAL MODE, 2 SURVIVAL CO-OP, 0 nothing yet). An older main.dll without it: open at start, as before.
    local choice = type(SV_MenuChoice) == "function" and SV_MenuChoice() or nil
    if choice == nil then
        if not COOP.open and not M.openTried then M.openTried = true; openCoop("start") end
    elseif choice ~= M.choice then
        M.choice = choice
        if choice == 2 and not COOP.open then openCoop("SURVIVAL CO-OP picked")
        elseif choice ~= 2 and COOP.open then closeCoop("SURVIVAL MODE picked: playing alone") end
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
        M.linkNames = {}
        for s, name in (info:match("peers=(.*)$") or ""):gmatch("(%d+)/%a+/%-?%d+/%-?%d+/([^,]*)") do M.linkNames[tonumber(s)] = name end
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
        if D then
            if COOP.host() then send(true, "rs") else send(true, "jn") end
            log("coop: in Survival's level as " .. (COOP.host() and "the host" or ("player " .. tostring((COOP.slot or -1) + 1))))
            if COOP.client() and M.state ~= "linked" then
                callout(M.auto and "CO-OP: LOOKING FOR A HOST" or "CO-OP: WAITING FOR THE HOST",
                        M.auto and "NONE FOUND: YOU HOST" or tostring(c.partner))
            elseif COOP.host() then
                callout("CO-OP: YOU ARE THE HOST", string.format("PLAYERS %d/%d", playerCount(), c.max_players or 4))
            end
        end
    end
    if not D then return end
    -- An online-style pause (user, 2026-10-26: "when the Host Pauses, the game doesn't pause all the enemies for the
    -- other players"): while another player is linked, the pause menu opens but the world keeps running, on the host's
    -- game (its enemies, which every game copies) and on a joiner's (its plane). Alone, the game pauses as ever.
    if playerCount() > 1 and valid(survivalPC) and gamePaused(survivalPC) then
        local gs = cdo("/Script/Engine.Default__GameplayStatics")
        local ok = gs and pcall(function() gs:SetGamePaused(survivalPC, false) end)
        M.unpauses = (M.unpauses or 0) + 1
        if M.unpauses == 1 or M.unpauses % 40 == 0 then
            log(string.format("coop: paused with %d players: the world kept running (%s; %d times)", playerCount(),
                ok and "unpaused" or "COULD NOT unpause", M.unpauses))
        end
        if M.unpauses == 1 then callout("CO-OP: THE GAME KEEPS RUNNING", "OTHER PLAYERS ARE STILL FLYING") end
    end
    -- our own plane, streamed (flags: 1 in Survival's level, 2 alive, 4 down at the airfield)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if valid(pawn) then
        local flags = 1
        local h = health(pawn)
        if h and h > 0 then flags = flags + 2 end
        if playerOnAirfield() then flags = flags + 4 end
        SV_CoopMe(addrOf(pawn) or 0, flags)
        local row = myAirframe()
        if row and row ~= M.myRow then
            M.myRow = row
            if COOP.host() then hostRosterSelf() else sendHi() end
        end
    else
        SV_CoopMe(0, 0)
    end
    for s = 0, 3 do
        if s ~= COOP.slot then
            local okP, errP = pcall(peerTick, s)
            if not okP then once("peerTick", "coop: player plane error " .. tostring(errP)) end
        end
    end
    if COOP.host() then
        local okH, errH = pcall(hostTick)
        if not okH then once("hostTick", "coop: host error " .. tostring(errH)) end
    else
        local okC, errC = pcall(clientTick)
        if not okC then once("clientTick", "coop: joiner error " .. tostring(errC)) end
    end
end
end
