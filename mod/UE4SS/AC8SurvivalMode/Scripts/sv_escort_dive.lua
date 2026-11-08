-- sv_escort_dive.lua: the VAMPIRES' final dive (2026-11-08). Part of AC8 Survival Mode's runtime, run by main.lua in order
-- after sv_escort_li; a name another part uses is a global of this mod's Lua state, its own helpers stay local.
--
-- The user: "these ZFA-44's will last 3 rounds before they fly towards the nearest enemy aircraft and explode on the
-- aircraft they were targetting with an Helios Explosion"; her answers: at the start of the 4th round, the target and
-- every enemy near it, players and allies untouched (CFG.allies.carrier.dive).
--   ZDIVE.take(C)        (sv_escort.lua, a carrier leaving after its service; the host's or solo) its ZFA-44s up are kept
--                        (not switched off with their flight): how many, or nil (none, or the dive off: switched off as before)
--   ZDIVE.tick()         (ZLAS.tick, every game) the next round's enemies up: each held ZFA-44 ordered onto the nearest
--                        enemy aircraft (one each while there are enough), within detonate_m of it the Helios blast there
--                        (dive_s on, where the ZFA-44 is): every enemy aircraft within blast_m down (yours, as an airstrike's
--                        hits), an ace's or a special's boss_pct of its health off; the ZFA-44 finished off, unpaid
--   ZDIVE.diving(addr)   (ZLAUNCH.coverTick) a held plane: never sent back to escort a player
--   ZDIVE.holdLocal(i)   (a joiner, ESC.localOff) the host's carrier i left for its dive ("zd h"): this game's own
--                        ZFA-44s of it kept too, ordered at the host's "zd v", one finished off at each of the host's blasts
--   ZDIVE.fromHost(f)    (a joiner, sv_coop_migration.lua) "zd": h (held), v (the dive), b (a blast: x, y, z, down), e (over)
-- Log lines: `carrier: <name> leaving: N ZFA-44s stay up for their final dive`, `dive: ...`.
ZDIVE = { d = nil }
do
local function dc() return (((CFG.allies or {}).carrier or {}).dive) or {} end
local function cc() return ((CFG.allies or {}).carrier) or {} end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end; return v end
local function isClient() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function linked() return COOP ~= nil and COOP.open and COOP.msg ~= nil and not isClient() end
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function hp(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end
local function dist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end   -- (cm)
local function up(e) return liveAddr(e.obj) == e.addr and (hp(e.obj) or 1) > 0 end
-- this run's state: held = { { obj, addr, unit, ship, round, target, due, ... } }, local = a joiner's own
local function st()
    local s = ZDIVE.d
    if not (s and s.D == D) then
        if s and s.held then                             -- (a run over or started again: the old run's never dive)
            local n = 0
            for _, e in ipairs(s.held) do if not e.gone and ZDIVE.finish(e, "the run is over") then n = n + 1 end end
            if n > 0 then log(string.format("dive: %d held ZFA-44s of the last run finished off, unpaid", n)) end
        end
        s = { D = D, held = {}, ships = {}, units = {}, kills = 0, blasts = 0, said = {}, hostHold = {} }
        ZDIVE.d = s
    end
    return s
end
-- the ship a ZFA-44 unit is of (sv_escort.lua's ZFA_I, from the same config)
local function shipOf(u)
    local c = cc()
    for i, pu in ipairs(c.pose_units or {}) do if pu == u then return i end end
    for i, arms in ipairs(c.launchers or {}) do
        for _, arm in ipairs(arms) do if arm.unit == u then return i end end
    end
    return nil
end
-- an enemy aircraft killed outright (a round's flight: pool, bombers, THE DECOY's UAVs, THE FESTIVAL's missiles) or only
-- hurt (an ace squadron's, a special's)
local function outright(p)
    local u = p.unit
    if not u then return true end
    if TAC and TAC.aceFlight and TAC.aceFlight(u) then return false end
    if (poolIndex and poolIndex(u)) or (BOMBER_UNIT and BOMBER_UNIT[u]) then return true end
    if DECOY and DECOY.isUnit and DECOY.isUnit(u) then return true end
    return u:find("^SV_Unit_FestCM_") ~= nil
end
local function enemyUp(p) return p and not p.down and liveObj(p.obj) and (hp(p.obj) or 1) > 0 end
local function fighting() return D and (D.state == "spawning" or D.state == "wave" or D.state == "fighting") end

-- the effects where a blast is, on this game (its own Helios: the Niagara burst, the sound, the camera shake near you)
local A = {}
local function asset(path)
    if type(path) ~= "string" or path == "" then return nil end
    local full = path:find("%.") and path or (path .. "." .. path:match("[^/]+$"))
    local o = A[full]
    if o ~= nil and liveObj(o) then return o end
    o = loadObject(full)
    A[full] = (o ~= nil and valid(o)) and o or nil
    return A[full]
end
local function effects(where)
    local c, s = dc(), st()
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = asset(c.fx)
    local sc = num(c.fx_scale, 1)
    if valid(lib) and sys and liveObj(survivalPC) then
        local ok, err = pcall(function()
            lib:SpawnSystemAtLocation(survivalPC, sys, where, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc }, true, true, 0, true)
        end)
        if not ok and not s.said.fx then s.said.fx = true; log("dive: the Helios effect failed (" .. tostring(err) .. ")") end
    elseif not s.said.fx then
        s.said.fx = true
        log("dive: the Helios effect " .. tostring(c.fx) .. (sys and " (no player controller)" or " NOT loaded"))
    end
    local ev, ak = asset(c.sound), StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
    if ev and valid(ak) and liveObj(survivalPC) then
        local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
        local tries = { function() return ak:PostEventAtLocation(ev, where, rot, survivalPC) end,
                        function() return ak:PostEventAtLocation(ev, where, rot, "", survivalPC) end }
        local okAny = false
        for i = (s.soundWay or 1), (s.soundWay or #tries) do
            if pcall(tries[i]) then s.soundWay, okAny = i, true; break end
        end
        if not okAny and not s.said.sound then s.said.sound = true; log("dive: the Helios sound can't be played") end
    end
    local you = playerLocation()
    local km_ = you and dist(you, where) / 100000 or math.huge
    local reach = num(c.shake_km, 6)
    if km_ <= reach and c.shake then
        local cls = asset(c.shake .. "." .. c.shake:match("[^/]+$") .. "_C")
        local scale = math.max(0.2, 1 - km_ / reach)
        local ok = cls and pcall(function() survivalPC:ClientStartCameraShake(cls, scale, 0, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
        if not ok and cls then
            ok = pcall(function() survivalPC.PlayerCameraManager:StartCameraShake(cls, scale, 0, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
        end
        if not ok and not s.said.shake then s.said.shake = true; log("dive: the Helios camera shake " .. (cls and "failed" or "NOT loaded")) end
    end
end

-- a held ZFA-44 finished off where it is, unpaid (ZLAUNCH.parkedOff's way): whether it went
function ZDIVE.finish(e, why)
    e.gone = true
    if liveAddr(e.obj) ~= e.addr then return false end
    if COOP and COOP.removeObj and not isClient() then pcall(COOP.removeObj, e.obj) end
    pcall(function() e.obj:SetIsInvincible(false) end)
    pcall(function() e.obj.bIsInvincible = false end)
    pcall(function() e.obj:SetMinHealth(0.0) end)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local ok = valid(gs) and pcall(function() gs:ApplyDamage(e.obj, 1.0e8, nil, nil, nil) end)
    if not ok then ok = pcall(function() e.obj:ModifyHealth(-1.0e8, nil, true) end) end
    return ok
end
function ZDIVE.diving(addr)
    local s = ZDIVE.d
    if not (s and s.D == D and addr) then return false end
    for _, e in ipairs(s.held) do if e.addr == addr and not e.gone then return true end end
    return false
end
-- the planes of ship i up (out of their container, alive): this game's own on a joiner (not the host's bound copies)
local function planesOfShip(i)
    local out = {}
    local riseZ = num(cc().rise_m, -50) * 100
    for u, l in pairs((ESC and ESC.planes) or {}) do
        if shipOf(u) == i then
            for _, e in ipairs(l) do
                local p = up(e) and at(e.obj)
                if p and p.Z > riseZ and not (isClient() and COOP and COOP.copyAt and COOP.copyAt(e.addr)) then
                    out[#out + 1] = { obj = e.obj, addr = e.addr, unit = u }
                end
            end
        end
    end
    return out
end
local function hold(i, round, why)
    local s = st()
    local l = planesOfShip(i)
    table.sort(l, function(a, b) return a.addr < b.addr end)   -- (ESC.planes' order is pairs': each pick in one order)
    for _, e in ipairs(l) do
        e.ship, e.round = i, round
        s.held[#s.held + 1] = e
        s.units[e.unit] = true
    end
    return #l
end
function ZDIVE.take(C)
    if dc().enabled == false or isClient() or not (D and C and C.idx) then return nil end
    local n = hold(C.idx, D.round)
    if n == 0 then return nil end
    log(string.format("carrier: %s leaving: %d ZFA-44%s stay up for their final dive as round %d's enemies come", tostring(C.name), n,
        n == 1 and "" or "s", D.round + 1))
    if linked() then pcall(COOP.msg, nil, "zd", "h", string.format("%d", C.idx), string.format("%d", D.round)) end
    return n
end
function ZDIVE.holdLocal(i)
    local s = st()
    local h = s.hostHold[i]
    if not (h and os.clock() - h.at < 30) or dc().enabled == false then return nil end
    local n = hold(i, h.round)
    log(string.format("dive: the host's carrier %d left for its final dive: %d of this game's own ZFA-44s of it kept up with it", i, n))
    return n > 0 and n or nil
end

-- the nearest enemy aircraft to `p` not in `taken` (all taken: the nearest of all); its record and distance (cm)
local function nearest(p, taken)
    local best, bd, any, ad = nil, math.huge, nil, math.huge
    for _, q in ipairs(planes or {}) do
        if enemyUp(q) then
            local qa = q.at or at(q.obj)
            if qa then
                local d = dist(p, qa)
                if d < ad then any, ad = q, d end
                if not taken[q.addr or q] and d < bd then best, bd = q, d end
            end
        end
    end
    if best then return best, bd end
    return any, ad
end
local function order(e, q)
    local ok = pcall(function()
        e.obj:EngagementOrderOverride(ORDER_NORMAL or 0, q.obj, PRIO_TARGET_FIRST or 9, 0, false, FIRE_BITS or 7, false)
    end)
    e.orderedAt = os.clock()
    return ok
end
-- the blast at `where`: on the host (or solo) the kills, then everyone's effects; how many down
local function blast(where, why)
    local c, s = dc(), st()
    local r = num(c.blast_m, 1000) * 100
    local pawn = survivalPC and liveObj(survivalPC) and survivalPC.Pawn or nil
    local down, hurt = 0, 0
    for _, q in ipairs(planes or {}) do
        if enemyUp(q) then
            local qa = q.at
            if qa and dist(qa, where) <= r + 300000 then qa = at(q.obj) or qa end      -- (a stale spot read again)
            if qa and dist(qa, where) <= r then
                if outright(q) then
                    if pcall(function() q.obj:ModifyHealth(-1000000.0, pawn, true) end) then down = down + 1 end
                else
                    local h = hp(q.obj) or 0
                    if h > 0 and pcall(function() q.obj:ModifyHealth(-(h * num(c.boss_pct, 0.3)), pawn, true) end) then hurt = hurt + 1 end
                end
            end
        end
    end
    s.kills, s.blasts = s.kills + down, s.blasts + 1
    effects(where)
    local t = c.text or {}
    if t.blast then hudCallout(t.blast, string.format(t.blast_sub or "%d", s.kills)) end
    if linked() then
        pcall(COOP.msg, nil, "zd", "b", string.format("%.0f", where.X), string.format("%.0f", where.Y), string.format("%.0f", where.Z),
            string.format("%d", s.kills))
    end
    log(string.format("dive: Helios blast %d (%s) at (%.1f, %.1f) km %.0f m: %d enemy aircraft down, %d aces' or specials' hurt (%d down so far)",
        s.blasts, why, where.X / 100000, where.Y / 100000, where.Z / 100, down, hurt, s.kills))
    return down
end
-- (the host or solo) the held planes' dive, every tick
local function hostTick(s)
    local c = dc()
    local live = 0
    for _, e in ipairs(s.held) do if not e.gone then live = live + 1 end end
    if live == 0 then
        if next(s.units) and not s.freed then
            s.freed = true
            for u in pairs(s.units) do
                if COOP and COOP.removeNow then pcall(COOP.removeNow, u) end
                if ESC and ESC.recycleQ then ESC.recycleQ[#ESC.recycleQ + 1] = { unit = u, at = os.clock() + 3, why = "their final dive over" } end
            end
            if linked() then pcall(COOP.msg, nil, "zd", "e") end
            log(string.format("dive: over: %d blasts, %d enemy aircraft down; the ZFA-44s' units off the list once none is up", s.blasts, s.kills))
        end
        return
    end
    local now = os.clock()
    local taken = {}
    for _, e in ipairs(s.held) do
        if not e.gone and e.target and enemyUp(e.target) then taken[e.target.addr or e.target] = true end
    end
    for _, e in ipairs(s.held) do
        if not e.gone then
            if not up(e) then
                e.gone = true                            -- (shot down, or gone: no blast)
                log("dive: a held ZFA-44 went down before its blast")
            elseif D.round >= e.round + 2 then           -- (a whole round with no enemy aircraft: it leaves)
                ZDIVE.finish(e, "no enemy aircraft in a round")
                log("dive: a held ZFA-44 found no enemy aircraft in round " .. tostring(e.round + 1) .. ": finished off, unpaid")
            elseif D.round > e.round and fighting() then
                local p = at(e.obj)
                if e.target and not enemyUp(e.target) then e.target = nil end
                if not e.target then
                    local q = p and nearest(p, taken)
                    if q then
                        e.target = q
                        taken[q.addr or q] = true
                        e.started = e.started or now
                        e.due = math.min(e.started + 2.5 * num(c.dive_s, 40), math.max(e.due or 0, now + num(c.dive_s, 40)))
                        order(e, q)
                        if not s.diveSaid then
                            s.diveSaid = true
                            local n = 0
                            for _, x in ipairs(s.held) do if not x.gone then n = n + 1 end end
                            local t = c.text or {}
                            if t.dive then hudCallout(t.dive, string.format(t.dive_sub or "%d", n)) end
                            if linked() then pcall(COOP.msg, nil, "zd", "v", string.format("%d", n)) end
                            log(string.format("dive: round %d's enemies up: %d held ZFA-44s dive at the nearest enemy aircraft", D.round, n))
                        end
                    end
                elseif now - (e.orderedAt or 0) >= num(c.reorder_s, 2) then
                    order(e, e.target)
                end
                local q = e.target
                local qa = q and at(q.obj)
                if p and qa and dist(p, qa) <= num(c.detonate_m, 800) * 100 then
                    ZDIVE.finish(e, "its blast")
                    blast(qa, "on its target")
                elseif p and e.due and now >= e.due then
                    ZDIVE.finish(e, "its blast")
                    blast(p, "its dive's time up")
                end
            end
        end
    end
end
-- (a joiner) this game's own held planes: ordered at the host's dive, one finished off at each of its blasts
local function clientTick(s)
    if not s.diveOn then return end
    local now = os.clock()
    for _, e in ipairs(s.held) do
        if not e.gone and up(e) and now - (e.orderedAt or 0) >= num(dc().reorder_s, 2) then
            local p = at(e.obj)
            local q = p and nearest(p, {})
            if q then order(e, q) else e.orderedAt = now end
        end
    end
end
function ZDIVE.tick()
    if not D then return end
    local s = ZDIVE.d
    if not (s and (s.D ~= D or #s.held > 0)) then return end
    s = st()
    if isClient() then clientTick(s) else hostTick(s) end
end

-- (a joiner) the host's "zd": its numbers checked before anything is done with them
local function coord(v, lim)
    v = tonumber(v)
    if not v or v ~= v or math.abs(v) > lim then return nil end
    return v
end
function ZDIVE.fromHost(f)
    if not (D and isClient()) then return end
    local s, k = st(), tostring(f[2] or "")
    if k == "h" then
        local i, r = math.floor(num(f[3], 0)), math.floor(num(f[4], -1))
        if i >= 1 and i <= #(cc().units or {}) and r >= 0 and r <= 999 then s.hostHold[i] = { at = os.clock(), round = r } end
    elseif k == "v" then
        if not s.diveOn then
            s.diveOn = true
            local t = dc().text or {}
            if t.dive then hudCallout(t.dive, string.format(t.dive_sub or "%d", math.floor(math.max(0, math.min(99, num(f[3], 0)))))) end
            log(string.format("dive: the host's ZFA-44s dive; %d of this game's own with them", #s.held))
        end
    elseif k == "b" then
        local x, y, z = coord(f[3], 1.0e8), coord(f[4], 1.0e8), coord(f[5], 5.0e6)
        if not (x and y and z) then return end
        local now = os.clock()
        s.rx = (s.rx and now - s.rx.at < 1) and s.rx or { at = now, n = 0 }
        s.rx.n = s.rx.n + 1
        if s.rx.n > 12 then return end                   -- (more than 12 blasts in a second: the rest not shown)
        local where = { X = x, Y = y, Z = z }
        local best, bd = nil, math.huge                  -- (this game's own held plane nearest the blast goes with it)
        for _, e in ipairs(s.held) do
            local p = not e.gone and up(e) and at(e.obj)
            if p and dist(p, where) < bd then best, bd = e, dist(p, where) end
        end
        if best then ZDIVE.finish(best, "the host's blast") end
        s.blasts = s.blasts + 1
        effects(where)
        local t = dc().text or {}
        if t.blast then hudCallout(t.blast, string.format(t.blast_sub or "%d", math.floor(math.max(0, math.min(9999, num(f[6], 0)))))) end
    elseif k == "e" then
        local n = 0
        for _, e in ipairs(s.held) do if not e.gone and ZDIVE.finish(e, "the host's dive over") then n = n + 1 end end
        for u in pairs(s.units) do
            if ESC and ESC.recycleQ then ESC.recycleQ[#ESC.recycleQ + 1] = { unit = u, at = os.clock() + 3, why = "the host's dive over" } end
        end
        s.units, s.diveOn = {}, false
        log(string.format("dive: the host's dive over after %d blasts here; %d of this game's own left finished off", s.blasts, n))
    end
end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the ZFA-44s' dive"] = function() ZDIVE.d = nil end end
end
