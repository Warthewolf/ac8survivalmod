-- AC8 Survival Mode - runtime part sv_coop: Survival COOP (CFG.coop; the native half is dlls\main.dll 0.20.0 coop.c;
-- tools/re/COOP.md). Two players, one run, host-authoritative after the AC7 co-op mod Double Trigger:
--   host:   runs everything as in single player. Every flight it spawns (SV_Spawn, with the SV_SetAircraft /
--           SV_SetLevel calls before it) is sent to the joiner, every aircraft of it gets a stream id (its position and
--           rotation go out 15 times a second, natively), its health once a second, its death at once. The joiner's
--           hits on its copies come back and are dealt as real damage (ModifyHealth, the cause the joiner's plane).
--   joiner: spawns no rounds of its own (roundsTick, airfieldTick and bombTick are the host's): it spawns the host's
--           flights, binds each copy to its stream (the runtime moves it every frame to where the host's is) and keeps
--           it alive (MinHealth) until the host says it's down. Its round, callouts, airfield and round bonuses are
--           the host's. Each player's kills pay their own zollars (KILL.by: the other player is the "wingmate" side).
--   both:   the other player's plane is SV_Unit_CoopPeer (an allied AI plane, fire off, invincible), moved every frame
--           to where the other player is. A plane the host's fighters are sent after (split_share of its flights:
--           the stock allied-hunt order) makes them go for the joiner too.
-- Messages are "kind|field|field...", reliable unless said: hi, rnd (unreliable), af, co, cr, sp, bd, hp, dn, rs (host),
-- jn, ht (joiner).
COOP = { open = false, role = nil }

do
local PEER_UNIT = "SV_Unit_CoopPeer"
local M = {
    nextId = 0, units = {}, byId = {},        -- host: the flights mirrored, and every aircraft by stream id
    cunits = {}, copies = {}, dead = {},       -- joiner: the host's flights here, the bound copies, ids already down
    spawnQ = {}, hunts = {}, mirror = 0,       -- joiner's spawns waiting, host's hunt orders waiting, inside the rounds
    peer = {}, lastD = nil, said = {}, nextHi = 0, nextRnd = 0, nextHp = 0, nextAf = 0, nextInfo = 0,
}
local function cfg() return CFG.coop end
function COOP.host() return COOP.open and COOP.role == "host" end
function COOP.client() return COOP.open and COOP.role == "join" end

local function clean(s) return (tostring(s or ""):gsub("|", "/")) end
local function send(reliable, ...)
    if not COOP.open or type(SV_CoopSend) ~= "function" then return false end
    local parts = { ... }
    for i = 1, #parts do parts[i] = clean(parts[i]) end
    return SV_CoopSend(table.concat(parts, "|"), reliable and 1 or 0) == 1
end
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

---------------------------------------------------------------------------------------------------- the natives, wrapped
-- (registered by dlls/main.dll before this script ran; every part calls them by their global names)
local rawSpawn, rawSetAircraft, rawSetLevel, rawUnitAlive = SV_Spawn, SV_SetAircraft, SV_SetLevel, SV_UnitAlive
local acOps, levels = {}, {}                                 -- host: per unit, since its last spawn
if rawSetAircraft then
    SV_SetAircraft = function(unit, row, idx)
        local r
        if idx == nil then r = rawSetAircraft(unit, row) else r = rawSetAircraft(unit, row, idx) end
        if COOP.host() and type(unit) == "string" and unit ~= PEER_UNIT then
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
        if COOP.host() and type(unit) == "string" and unit ~= PEER_UNIT then
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
local function sendUnit(unit, u)
    send(true, "sp", unit, poseText(u.pose), opsText(u.ops), u.level or -1, u.gen)
end

function COOP.hostSpawned(unit, pose, ops, level)
    M.gen = (M.gen or 0) + 1
    M.units[unit] = { gen = M.gen, pose = pose, ops = ops, level = level, n = 0, planes = {} }
    sendUnit(unit, M.units[unit])
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
    -- split the fighters between the two of you: a pool flight goes after the joiner's plane (it's an allied aircraft
    -- here) with split_share, once it's had its orders
    if u.n == 1 and poolIndex(unit) and M.peer.obj and math.random() < (cfg().split_share or 0) then
        M.hunts[#M.hunts + 1] = { at = os.clock() + 5, name = string.format("RE_SV_Hunt_%02d", poolIndex(unit)), unit = unit }
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
                log("coop: " .. h.unit .. " goes after the joiner (" .. h.name .. " " .. tostring(r) .. ")")
            end
        end
    end
end

-- the joiner asked for the whole picture (it loaded in, or the link came back): every flight with anything alive
local function hostSync()
    send(true, "rs")
    for unit, u in pairs(M.units) do
        sendUnit(unit, u)
        for ord, pl in pairs(u.planes) do
            send(true, "bd", unit, u.gen, ord, pl.id)
            if pl.dead then send(true, "dn", pl.id) end
        end
    end
    M.afKey, M.nextRnd, M.nextAf = nil, 0, 0
    log("coop: sent the joiner the run: " .. (function() local n = 0; for _ in pairs(M.units) do n = n + 1 end; return n end)() .. " flights")
end

local function hostHit(id, dmg)
    local e = M.byId[id]
    if not (e and not e.dead and valid(e.obj) and dmg > 0) then return end
    local causer = M.peer.obj and valid(M.peer.obj) and M.peer.obj or nil
    local ok = pcall(function() e.obj:ModifyHealth(-dmg, causer, true) end)
    if not ok then ok = pcall(function() e.obj:ModifyHealth(-dmg, e.obj, true) end) end
    if not ok then once("hitfail", "coop: the joiner's hits can't be dealt (ModifyHealth failed)") end
    M.hits = (M.hits or 0) + 1
end

---------------------------------------------------------------------------------------------------- joiner
local function killCopy(id, o)
    if type(SV_CoopBind) == "function" then SV_CoopBind(id, 0) end
    if not valid(o) then return end
    pcall(function() o:SetMinHealth(0.0) end)
    local h = health(o) or 0
    local causer = M.peer.obj and valid(M.peer.obj) and M.peer.obj or nil
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
    if type(r) ~= "number" or r <= 0 then
        log("coop: the host's " .. unit .. " not spawned here (" .. (SV_ERR[r] or tostring(r)) .. ")")
    end
    return true
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

---------------------------------------------------------------------------------------------------- the other player's plane
local AF_CODE = "BP_PlayerPlane_PP%d+_(%w+)"
local function myAirframe()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return nil end
    local code = nameOf(pawn):match(AF_CODE)
    local c = cfg()
    return code and (c.airframes[code] or c.default) or c.default, code
end

function COOP.peerPlane(o)
    if not valid(o) or not inSurvival(o) then return end
    for k, v in pairs({ bPermissionToFire = false, bPermissionToEngage = false, bPermissionToUseFlares = false,
                        bPermissionToProvoke = false, bPermissionToEvade = false, bIsNotLockonTarget = true,
                        bCanBeDamagedByAlly = false, bCauseExplosionOnDeath = false, bShowHUDBox = true }) do
        pcall(function() o[k] = v end)
    end
    pcall(function() o:SetIsInvincible(true) end)
    M.peer.obj, M.peer.addr, M.peer.spawning = o, addrOf(o), nil
    local r = type(SV_CoopPeer) == "function" and M.peer.addr and SV_CoopPeer(M.peer.addr) or -9
    M.peer.bound = r == 1
    log("coop: the other player's plane is up (" .. (nameOf(o):match("([^%.:]+)$") or "?") .. ", " ..
        (r == 1 and "moved every frame" or ("NOT moved: " .. tostring(r))) .. ")")
end

local function peerTick()
    local s = type(SV_CoopPeerAt) == "function" and SV_CoopPeerAt() or ""
    local f = {}
    for v in s:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
    local fresh = #f >= 10 and f[10] < 3000 and (math.floor(f[9]) % 2 == 1)        -- (flag 1: in Survival's level)
    M.peer.at = fresh and { X = f[1], Y = f[2], Z = f[3] } or nil
    M.peer.hp, M.peer.max = f[7], f[8]
    if not D then return end
    local P = M.peer
    if P.obj and not valid(P.obj) then P.obj, P.addr, P.bound = nil, nil, false end
    if fresh and not P.obj and not P.spawning then
        local row = M.peerRow or cfg().default
        rawSetAircraft(PEER_UNIT, row)
        spawningUnit = PEER_UNIT
        local r = rawSpawn(PEER_UNIT)
        spawningUnit = nil
        P.spawning = os.clock()
        log("coop: the other player's plane as " .. row .. ": " .. ((type(r) == "number" and r > 0) and "spawned" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    elseif P.spawning and os.clock() - P.spawning > 10 then
        P.spawning = nil                                  -- (it never came: again)
    end
    if P.obj then
        local show = fresh and true or false
        if show ~= P.shown then
            P.shown = show
            pcall(function() P.obj:SetActorHiddenInGame(not show) end)
            if type(SV_CoopPeer) == "function" then SV_CoopPeer(show and P.addr or 0) end
            log("coop: the other player's plane " .. (show and "shown" or "hidden (they're not in the mission)"))
        end
    end
end

---------------------------------------------------------------------------------------------------- messages
local function onHi(f)
    local role, ver, rt, row, name = f[2], f[3], f[4], f[5], f[6]
    if not name or name == "" then name = M.infoName or "the other player" end
    M.peerRow, M.peerName, M.peerVer = row ~= "" and row or nil, name, ver
    if not M.hiSeen then
        M.hiSeen = true
        log(string.format("coop: the other player: %s (%s), Survival %s, runtime %s, flies %s", tostring(name), tostring(role),
            tostring(ver), tostring(rt), tostring(row)))
        callout(CFG.hud.text.coop_linked or "CO-OP LINKED", string.upper(tostring(name)) .. (COOP.host() and " JOINED" or " IS HOSTING"))
        if ver ~= VERSION then
            log("coop: WARNING: the other player runs Survival " .. tostring(ver) .. ", you " .. VERSION .. ": install the same build")
            callout("CO-OP VERSION MISMATCH", "YOU " .. VERSION .. ", THEM " .. tostring(ver))
        end
    end
    if M.peer.obj and M.peerRow and M.peerRow ~= M.peer.row then M.peer.row = M.peerRow end
end

local function sendHi()
    local row = myAirframe()
    send(true, "hi", COOP.role, VERSION, type(SV_Version) == "function" and SV_Version() or "?", row or "", "")
end

local function onMessage(msg)
    local f = split(msg)
    local k = f[1]
    if k == "sys" then
        local what = f[2]
        if what == "paired" or what == "restart" then
            M.hiSeen = false; sendHi()
            if COOP.client() and D then killAllCopies("new link"); send(true, "jn") end
        elseif what == "lost" then
            M.wasLost = true
            callout("CO-OP LINK LOST", "WAITING FOR " .. string.upper(tostring(M.peerName or "the other player")))
        elseif what == "up" then
            if M.wasLost then                             -- (the first "up" comes right after "paired")
                M.wasLost = false
                callout("CO-OP LINK BACK", nil)
                if COOP.client() and D then killAllCopies("link back"); send(true, "jn") end
            end
        elseif what == "samerole" then
            callout("CO-OP: BOTH OF YOU ARE " .. (COOP.host() and "HOSTS" or "JOINERS"), "ONE OF YOU SET role = " .. (COOP.host() and "join" or "host"))
        end
        log("coop: " .. msg)
        return
    end
    if k == "hi" then onHi(f); return end
    if COOP.host() then
        if k == "jn" then hostSync()
        elseif k == "ht" then hostHit(tonumber(f[2]) or 0, tonumber(f[3]) or 0)
        end
        return
    end
    -- joiner
    if k == "rnd" then
        M.rnd = { round = tonumber(f[2]) or 0, state = f[3], secs = tonumber(f[4]) or 0, wave = tonumber(f[5]) or 0,
                  waves = tonumber(f[6]) or 0, alive = tonumber(f[7]) or 0, got = os.clock() }
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
    elseif k == "rs" then
        killAllCopies("the host's run started over")
        if D then D.round, D.state, M.rnd = 0, "wait", nil end
    end
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
    if unit == PEER_UNIT then
        local ok, err = pcall(COOP.peerPlane, o)
        if not ok then log("coop: peer plane error " .. tostring(err)) end
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
    if a and M.peer.addr and a == M.peer.addr then return "wingmate" end
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
function COOP.tick(tick)
    local c = cfg()
    if not c.enabled then return end
    if not COOP.open and not M.openTried then
        M.openTried = true
        if type(SV_CoopOpen) ~= "function" then log("coop: dlls/main.dll has no co-op (0.20.0 or later needed)"); return end
        local role = (c.role or "host"):lower()
        role = (role == "join" or role == "joiner" or role == "client") and "join" or "host"
        local r = SV_CoopOpen(c.transport or "steam", role, c.partner or "auto", c.port or 27777, c.interp_ms or 120, VERSION)
        COOP.open, COOP.role = r == 1, role
        log(string.format("coop: %s as the %s over %s (partner %s): %s", r == 1 and "open" or "NOT open", role == "host" and "host" or "joiner",
            tostring(c.transport), tostring(c.partner), r == 1 and "looking for the other player" or
            ({ [-1] = "bad settings", [-2] = "Steam not available", [-3] = "UDP not available", [-4] = "partner isn't an IP address" })[r] or tostring(r)))
        if not COOP.open then return end
    end
    if not COOP.open then return end
    -- the other game's messages
    for _ = 1, 400 do
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
        local pn = info:match("peername=(.*)$")
        if pn and pn ~= "" then M.infoName = pn end
        if st ~= M.state then
            M.state = st
            log("coop: " .. info)
            if st == "searching" and COOP.client() then once("searching", "coop: waiting for the host (" .. tostring(c.partner) .. ")") end
        end
        if not M.hiSeen and st == "linked" then sendHi() end
    end
    -- a new level (a run started, or started over)
    if D ~= M.lastD then
        M.lastD = D
        if type(SV_CoopReset) == "function" then SV_CoopReset() end
        if COOP.client() then killAllCopies("a new run here") end      -- (a restart in the same level keeps the actors)
        local keep = M.peer.obj and valid(M.peer.obj) and M.peer.obj or nil
        M.peer = keep and { obj = keep, addr = addrOf(keep) } or {}     -- (bound again by peerTick)
        M.units, M.byId, M.copies, M.cunits, M.spawnQ, M.dead, M.hunts = {}, {}, {}, {}, {}, {}, {}
        if D then
            if COOP.host() then send(true, "rs") else send(true, "jn") end
            log("coop: in Survival's level as the " .. (COOP.host() and "host" or "joiner"))
            if COOP.client() and M.state ~= "linked" then callout("CO-OP: WAITING FOR THE HOST", tostring(c.partner)) end
        end
    end
    if not D then return end
    -- our own plane, streamed (flags: 1 in Survival's level, 2 alive, 4 down at the airfield)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if valid(pawn) then
        local flags = 1
        local h = health(pawn)
        if h and h > 0 then flags = flags + 2 end
        if playerOnAirfield() then flags = flags + 4 end
        SV_CoopMe(addrOf(pawn) or 0, flags)
        local row = myAirframe()
        if row and row ~= M.myRow then M.myRow = row; if M.hiSeen then sendHi() end end
    else
        SV_CoopMe(0, 0)
    end
    local okP, errP = pcall(peerTick)
    if not okP then once("peerTick", "coop: peer error " .. tostring(errP)) end
    if COOP.host() then
        local okH, errH = pcall(hostTick)
        if not okH then once("hostTick", "coop: host error " .. tostring(errH)) end
    else
        local okC, errC = pcall(clientTick)
        if not okC then once("clientTick", "coop: joiner error " .. tostring(errC)) end
    end
end
end
