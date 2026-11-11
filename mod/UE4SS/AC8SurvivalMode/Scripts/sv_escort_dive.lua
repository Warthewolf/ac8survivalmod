-- sv_escort_dive.lua: the VAMPIRES' final dive (2026-11-08). Part of AC8 Survival Mode's runtime, run by main.lua in order
-- after sv_escort_li; a name another part uses is a global of this mod's Lua state, its own helpers stay local.
--
-- The user: "these ZFA-44's will last 3 rounds before they fly towards the nearest enemy aircraft and explode on the
-- aircraft they were targetting with an Helios Explosion"; her answers: at the start of the 4th round, the target and
-- every enemy near it, players and allies untouched (CFG.allies.carrier.dive).
--   ZDIVE.take(C)        (sv_escort.lua, a carrier leaving after its service or sunk; the host's or solo) its ZFA-44s up
--                        are kept as one dive of its own (its id): how many, or nil (none, or the dive off: finished off)
--   ZDIVE.tick()         (ZLAS.tick, every game) the next round's enemies up: each held ZFA-44 ordered onto the nearest
--                        enemy aircraft (one each while there are enough); its dive_s start once that's in its reach
--                        (its speed x dive_s) or approach_s on; within detonate_m of it the Helios blast there (dive_s on,
--                        where the ZFA-44 is): every enemy aircraft within blast_m down (yours, as an airstrike's hits),
--                        an ace's or a special's boss_pct of its health off; the ZFA-44 finished off, unpaid
--   ZDIVE.waiting(addr)  (ZLAUNCH.coverTick) a held plane before its dive: escorts the player nearest it (toward the fight)
--   ZDIVE.diving(addr)   (ZLAUNCH.coverTick, parkedOff) a held plane: never sent back to escort a player, never finished
--                        off by a hull's hold
--   ZDIVE.holding(i)     (ZLAUNCH.holdHull) a held plane of ship i up: its hull's give-up clock waits
--   ZDIVE.holdLocal(i)   (a joiner, ESC.localOff) the host's carrier i left for its dive ("zd h"): this game's own
--                        ZFA-44s of it kept too, ordered at the host's "zd v", one finished off at each of the host's blasts
--   ZDIVE.fromHost(f)    (a joiner, sv_coop_migration.lua) "zd": h (held: ship, round, dive), v (the dive: count, dive),
--                        b (a blast: x, y, z, its down, dive), e (over: dive)
-- ((2026-11-11) Saint Alessia's 50-round co-op run of 0.74.36: 70 Helios blasts and not one ZFA-44 down, the survivors
-- held again at every leaving, the callout and "zd v" / "zd e" once a run) Each ZFA-44 counts as gone only once its health
-- reads 0 (ZDIVE.finish: ZLAUNCH.finish's ModifyHealth), its blast once (e.blasted), its finish tried FINISH_TRIES times,
-- then it's switched off and never escorted or held again; each carrier's dive has its own callout, messages and units'
-- recycle; the callouts of the blasts in a second (two ships may leave at once) are one.
-- Log lines: `carrier: <name> leaving: N ZFA-44s stay up for their final dive ... (dive k)`, `dive: ...`.
ZDIVE = { d = nil }
do
local function dc() return (((CFG.allies or {}).carrier or {}).dive) or {} end
local function cc() return ((CFG.allies or {}).carrier) or {} end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end; return v end
local function isClient() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function linked() return COOP ~= nil and COOP.open and COOP.msg ~= nil and not isClient() end
local FINISH_TRIES, RETRY_S, BATCH_S = 3, 1, 1
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function hp(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end
local function dist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end   -- (cm)
-- (its own plane still: ESC.same, sv_escort_laser.lua: a freed plane's address is reused, and the address alone took an
-- enemy's new plane as a ZFA-44 in the user's test of 0.74.34) maxAge as ESC.same's
local function same(e, maxAge)
    if ESC and ESC.same then return ESC.same(e, maxAge) end
    return liveAddr(e.obj) == e.addr
end
local function up(e) return same(e, 0.5) and (hp(e.obj) or 1) > 0 end
-- this run's state: held = { { obj, addr, unit, name, src (its ESC.planes entry), ship, round, dive, target, due, ... } },
-- dives = { [id] = { id, ship, round, units, said, n, blasts, kills, on (a joiner's: the host's "v") } }
local function st()
    local s = ZDIVE.d
    if not (s and s.D == D) then
        if s and s.held then                             -- (a run over or started again: the old run's never dive)
            local n = 0
            for _, e in ipairs(s.held) do if not e.gone and ZDIVE.finish(e, "the run is over", true) then n = n + 1 end end
            if n > 0 then log(string.format("dive: %d held ZFA-44s of the last run finished off, unpaid", n)) end
        end
        s = { D = D, held = {}, dives = {}, nextId = 0, blasts = 0, said = {}, hostHold = {}, pend = {} }
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
-- an enemy record of `planes` still its plane (its short name the one logged; fresh: read now, else at most every 0.5 s)
local function enemyUp(p, fresh)
    if not (p and not p.down and liveObj(p.obj) and (hp(p.obj) or 1) > 0) then return false end
    if not p.name then return true end
    local c = os.clock()
    if fresh or c >= (p.zdNameAt or 0) then
        p.zdNameAt = c + 0.5
        p.zdSame = (nameOf(p.obj):match("([^%.:]+)$") or "") == p.name
    end
    return p.zdSame
end
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
-- ((2026-11-11) Saint Alessia's run: 20 HELIOS IMPACT callouts in one second) the callouts of a second as one: the dives
-- starting (how many ZFA-44s) and the blasts (how many enemies down), each shown BATCH_S after the first of its kind
local function queue(s, kind, n)
    local p = s.pend[kind]
    if not p then p = { at = os.clock(), n = 0 }; s.pend[kind] = p end
    p.n = p.n + math.max(0, math.floor(n or 0))
end
local function flush(s)
    local t, now = dc().text or {}, os.clock()
    for _, kind in ipairs({ "dive", "blast" }) do
        local p = s.pend[kind]
        if p and now - p.at >= BATCH_S then
            s.pend[kind] = nil
            if t[kind] then hudCallout(t[kind], string.format(t[kind .. "_sub"] or "%d", math.min(p.n, 9999))) end
        end
    end
end

-- a held ZFA-44 finished off where it is, unpaid (sv_escort_laser.lua ZLAUNCH.finish: its own plane still, ModifyHealth,
-- read back; final: switched off when it's still up): whether it went, its health after, how. Gone (never held, escorted
-- or tried again) once it's down, not its plane any more, or final
function ZDIVE.finish(e, why, final)
    if e.gone then return e.dead == true, nil, "gone" end
    local dead, h, how
    if ZLAUNCH and ZLAUNCH.finish then dead, h, how = ZLAUNCH.finish(e, why, final)
    elseif not same(e) then dead, how = false, "not its plane"
    else dead, h, how = finishUnpaid(e.obj) end
    e.tries = (e.tries or 0) + 1
    if dead or how == "not its plane" or final then
        e.gone, e.dead = true, dead == true
        if e.src and not dead and how ~= "not its plane" then e.src.retired = true end
    end
    return dead == true, h, how
end
local function heldOf(addr, f)
    local s = ZDIVE.d
    if not (s and s.D == D and addr) then return false end
    for _, e in ipairs(s.held) do if e.addr == addr and not e.gone and f(e) then return true end end
    return false
end
function ZDIVE.diving(addr) return heldOf(addr, function() return true end) end
function ZDIVE.waiting(addr) return heldOf(addr, function(e) return not (e.target or e.ending or e.started or e.approach) end) end
function ZDIVE.holding(i)
    local s = ZDIVE.d
    if not (s and s.D == D) then return false end
    for _, e in ipairs(s.held) do if e.ship == i and not e.gone then return true end end
    return false
end
-- the planes of ship i up (out of their container, alive): this game's own on a joiner (not the host's bound copies), none
-- a dive took before (held, down or switched off: e.dived) or one that couldn't be finished (e.retired)
local function planesOfShip(i)
    local out = {}
    local riseZ = num(cc().rise_m, -50) * 100
    for u, l in pairs((ESC and ESC.planes) or {}) do
        if shipOf(u) == i then
            for _, e in ipairs(l) do
                local p = not (e.dived or e.retired or e.dead) and up(e) and at(e.obj)
                if p and p.Z > riseZ and same(e) and not (isClient() and COOP and COOP.copyAt and COOP.copyAt(e.addr)) then
                    out[#out + 1] = { obj = e.obj, addr = e.addr, unit = e.armUnit or u, name = e.name, src = e }
                end
            end
        end
    end
    return out
end
local function hold(i, round, id)
    local s = st()
    local l = planesOfShip(i)
    table.sort(l, function(a, b) return a.addr < b.addr end)   -- (ESC.planes' order is pairs': each pick in one order)
    if #l == 0 then return 0 end
    local d = s.dives[id] or { id = id, ship = i, round = round, units = {}, n = 0, blasts = 0, kills = 0 }
    s.dives[id] = d
    for _, e in ipairs(l) do
        e.ship, e.round, e.dive = i, round, id
        e.src.dived = true
        s.held[#s.held + 1] = e
        d.units[e.unit] = true
        d.n = d.n + 1
    end
    return #l
end
function ZDIVE.take(C)
    if dc().enabled == false or isClient() or not (D and C and C.idx) then return nil end
    local s = st()
    s.nextId = s.nextId + 1
    local id = s.nextId
    local n = hold(C.idx, D.round, id)
    if n == 0 then return nil end
    log(string.format("carrier: %s leaving: %d ZFA-44%s stay up for their final dive as round %d's enemies come (dive %d)", tostring(C.name), n,
        n == 1 and "" or "s", D.round + 1, id))
    if linked() then pcall(COOP.msg, nil, "zd", "h", string.format("%d", C.idx), string.format("%d", D.round), string.format("%d", id)) end
    return n
end
function ZDIVE.holdLocal(i)
    local s = st()
    local h = s.hostHold[i]
    if not (h and os.clock() - h.at < 30) or dc().enabled == false then return nil end
    local n = hold(i, h.round, h.id or -i)              -- (an older host's "h" has no dive: this ship's own key)
    log(string.format("dive: the host's carrier %d left for its final dive (dive %d): %d of this game's own ZFA-44s of it kept up with it",
        i, h.id or -i, n))
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
-- (cm/s) how fast a ZFA-44 flies: its own speed, or speed_kmh while it reads under half that (a turn) or not at all
local function speedOf(o)
    local ok, v = pcall(function() local x = o:GetVelocity(); return math.sqrt(x.X ^ 2 + x.Y ^ 2 + x.Z ^ 2) end)
    local floor = num(dc().speed_kmh, 1200) / 0.036
    v = (ok and type(v) == "number" and v == v) and v or 0
    return v >= floor * 0.5 and v or floor
end
-- one try at a held plane's end (e.ending: why), again RETRY_S on, final at the FINISH_TRIES-th: whether it went, its health
local function endStep(e, now)
    if e.gone then return e.dead == true, nil end
    if now < (e.tryAt or 0) then return false, nil end
    e.tryAt = now + RETRY_S
    local dead, h = ZDIVE.finish(e, e.ending, (e.tries or 0) + 1 >= FINISH_TRIES)
    if dead and (e.tries or 0) > 1 then log(string.format("dive: a held ZFA-44 down on try %d (%s)", e.tries, tostring(e.ending))) end
    return dead, h
end
-- the blast at `where` of dive d (its ZFA-44 tried first: down, health h): on the host (or solo) the kills, then
-- everyone's effects; how many down
local function blast(where, why, d, dead, h)
    local c, s = dc(), st()
    local r = num(c.blast_m, 1000) * 100
    local pawn = survivalPC and liveObj(survivalPC) and survivalPC.Pawn or nil
    local down, hurt = 0, 0
    for _, q in ipairs(planes or {}) do
        local qa = q.at
        if qa and dist(qa, where) <= r + 300000 and enemyUp(q, true) then
            qa = at(q.obj) or qa                         -- (a stale spot read again)
            if qa and dist(qa, where) <= r then
                if outright(q) then
                    if pcall(function() q.obj:ModifyHealth(-1000000.0, pawn, true) end) then down = down + 1 end
                else
                    local hh = hp(q.obj) or 0
                    if hh > 0 and pcall(function() q.obj:ModifyHealth(-(hh * num(c.boss_pct, 0.3)), pawn, true) end) then hurt = hurt + 1 end
                end
            end
        end
    end
    s.blasts, d.blasts, d.kills = s.blasts + 1, d.blasts + 1, d.kills + down
    effects(where)
    queue(s, "blast", down)
    if linked() then
        pcall(COOP.msg, nil, "zd", "b", string.format("%.0f", where.X), string.format("%.0f", where.Y), string.format("%.0f", where.Z),
            string.format("%d", down), string.format("%d", d.id))
    end
    log(string.format("dive: Helios blast %d (%s) at (%.1f, %.1f) km %.0f m: %d enemy aircraft down, %d aces' or specials' hurt "
        .. "(dive %d: %d down); its ZFA-44 %s", s.blasts, why, where.X / 100000, where.Y / 100000, where.Z / 100, down, hurt, d.id, d.kills,
        dead and "down" or string.format("NOT down yet (health %s): tried again", tostring(h))))
    return down
end
-- (the host or solo) the held planes' dive, every tick
local function hostTick(s)
    local c, now = dc(), os.clock()
    local diveS = num(c.dive_s, 40)
    local taken = {}
    for _, e in ipairs(s.held) do
        if not e.gone and e.target and enemyUp(e.target) then taken[e.target.addr or e.target] = true end
    end
    for _, e in ipairs(s.held) do
        local d = s.dives[e.dive]
        if not e.gone and d then
            if e.ending then
                endStep(e, now)
            elseif not up(e) then
                e.gone = true                            -- (shot down, or gone: no blast)
                log("dive: a held ZFA-44 went down before its blast")
            elseif D.round >= e.round + 2 then           -- (a whole round with no enemy aircraft: it leaves)
                e.ending = "no enemy aircraft in a round"
                log("dive: a held ZFA-44 found no enemy aircraft in round " .. tostring(e.round + 1) .. ": finished off, unpaid")
                endStep(e, now)
            elseif D.round > e.round and fighting() then
                local p = at(e.obj)
                if e.target and not enemyUp(e.target) then e.target = nil end
                if not e.target then
                    local q, dq
                    if p then q, dq = nearest(p, taken) end
                    if q then
                        e.target = q
                        taken[q.addr or q] = true
                        e.approach = e.approach or now
                        if e.started then e.due = math.min(e.started + 2.5 * diveS, math.max(e.due or 0, now + diveS)) end
                        order(e, q)
                        if not e.saidD then
                            e.saidD = true
                            local v = speedOf(e.obj)
                            log(string.format("dive: a ZFA-44 of dive %d onto the nearest enemy aircraft, %.1f km off (about %.0f s at %.0f km/h; %.1f km in its %d s)",
                                d.id, dq / 100000, dq / v, v * 0.036, v * diveS / 100000, diveS))
                        end
                        if not d.said then
                            d.said = true
                            local n = 0
                            for _, x in ipairs(s.held) do if x.dive == d.id and not x.gone then n = n + 1 end end
                            queue(s, "dive", n)
                            if linked() then pcall(COOP.msg, nil, "zd", "v", string.format("%d", n), string.format("%d", d.id)) end
                            log(string.format("dive: round %d's enemies up: %d held ZFA-44s dive at the nearest enemy aircraft (dive %d, ship %d)",
                                D.round, n, d.id, d.ship))
                        end
                    end
                elseif now - (e.orderedAt or 0) >= num(c.reorder_s, 2) then
                    order(e, e.target)
                end
                local q = e.target
                local qa = q and at(q.obj)
                local dd = (p and qa) and dist(p, qa) or nil
                -- ((2026-11-11) every blast of Saint Alessia's run timed out 15-50 km from the fight) its dive_s once its
                -- target is in its reach, or approach_s after its first target (flown at it meanwhile)
                if dd and not e.started and (dd <= speedOf(e.obj) * diveS or now - (e.approach or now) >= num(c.approach_s, 120)) then
                    e.started, e.due = now, now + diveS
                    if now - (e.approach or now) >= 1 then
                        log(string.format("dive: a ZFA-44 of dive %d %.1f km from its target %.0f s after its first: its %d s on", d.id, dd / 100000,
                            now - e.approach, diveS))
                    end
                end
                local where, why
                if dd and dd <= num(c.detonate_m, 800) * 100 then where, why = qa, "on its target"
                elseif p and e.due and now >= e.due then where, why = p, "its dive's time up" end
                if where and not e.blasted then        -- (once: its finish tried again after, never its blast)
                    e.blasted, e.ending = true, "its blast"
                    local dead, h = endStep(e, now)
                    blast(where, why, d, dead, h)
                end
            end
        end
    end
    -- each dive over (its planes all gone): its units off the list, the joiners told, its planes forgotten
    for id, d in pairs(s.dives) do
        local live = 0
        for _, e in ipairs(s.held) do if e.dive == id and not e.gone then live = live + 1 end end
        if live == 0 then
            s.dives[id] = nil
            for u in pairs(d.units) do
                if COOP and COOP.removeNow then pcall(COOP.removeNow, u) end
                if ESC and ESC.recycleQ then ESC.recycleQ[#ESC.recycleQ + 1] = { unit = u, at = os.clock() + 3, why = "their final dive over" } end
            end
            if linked() then pcall(COOP.msg, nil, "zd", "e", string.format("%d", id)) end
            log(string.format("dive: over (dive %d, ship %d): %d blasts, %d enemy aircraft down; the ZFA-44s' units off the list once none is up",
                id, d.ship, d.blasts, d.kills))
            for k = #s.held, 1, -1 do if s.held[k].dive == id then table.remove(s.held, k) end end
        end
    end
end
-- (a joiner) this game's own held planes: ordered at the host's dive, one finished off at each of its blasts
local function clientTick(s)
    local now = os.clock()
    for _, e in ipairs(s.held) do
        local d = s.dives[e.dive]
        if not e.gone then
            if e.ending then endStep(e, now)
            elseif not up(e) then e.gone = true
            elseif D.round >= (e.round or D.round) + 3 then        -- (the host's "b" / "e" never came: its own end)
                e.ending = "the host's dive never ended here"
                endStep(e, now)
            elseif d and d.on and now - (e.orderedAt or 0) >= num(dc().reorder_s, 2) then
                local p = at(e.obj)
                local q
                if p then q = nearest(p, {}) end
                if q then order(e, q) else e.orderedAt = now end
            end
        end
    end
    for id, d in pairs(s.dives) do                       -- (a dive of this game's own all gone: forgotten)
        local live = 0
        for _, e in ipairs(s.held) do if e.dive == id and not e.gone then live = live + 1 end end
        if live == 0 then
            s.dives[id] = nil
            for k = #s.held, 1, -1 do if s.held[k].dive == id then table.remove(s.held, k) end end
            if d.on == nil then log(string.format("dive: this game's own ZFA-44s of dive %d all gone", id)) end
        end
    end
end
function ZDIVE.tick()
    if not D then return end
    local s = ZDIVE.d
    if not (s and (s.D ~= D or #s.held > 0 or next(s.pend) or next(s.dives))) then return end
    s = st()
    if isClient() then clientTick(s) else hostTick(s) end
    flush(s)
end

-- (a joiner) the host's "zd": its numbers checked before anything is done with them
local function coord(v, lim)
    v = tonumber(v)
    if not v or v ~= v or math.abs(v) > lim then return nil end
    return v
end
local function whole(v, lo, hi)                          -- (a whole number in lo..hi, else nil)
    v = tonumber(v)
    if not v or v ~= v or v < lo or v > hi or v % 1 ~= 0 then return nil end
    return v
end
-- the dives "v" / "b" / "e" name (id: that one, if this game has it; none: an older host's, every one)
local function divesOf(s, id)
    local out = {}
    for k, d in pairs(s.dives) do if id == nil or k == id then out[#out + 1] = d end end
    return out
end
function ZDIVE.fromHost(f)
    if not (D and isClient()) then return end
    local s, k = st(), tostring(f[2] or "")
    if k == "h" then
        local i, r = math.floor(num(f[3], 0)), math.floor(num(f[4], -1))
        if i >= 1 and i <= #(cc().units or {}) and r >= 0 and r <= 999 then s.hostHold[i] = { at = os.clock(), round = r, id = whole(f[5], 1, 99999) } end
    elseif k == "v" then
        local id, n = whole(f[4], 1, 99999), math.floor(math.max(0, math.min(99, num(f[3], 0))))
        if id and s.lastV == id then return end           -- (said already)
        s.lastV = id
        local mine = 0
        for _, d in ipairs(divesOf(s, id)) do
            d.on = true
            for _, e in ipairs(s.held) do if e.dive == d.id and not e.gone then mine = mine + 1 end end
        end
        queue(s, "dive", n)
        log(string.format("dive: the host's ZFA-44s dive (dive %s); %d of this game's own with them", tostring(id or "?"), mine))
    elseif k == "b" then
        local x, y, z = coord(f[3], 1.0e8), coord(f[4], 1.0e8), coord(f[5], 5.0e6)
        if not (x and y and z) then return end
        local now = os.clock()
        s.rx = (s.rx and now - s.rx.at < 1) and s.rx or { at = now, n = 0 }
        s.rx.n = s.rx.n + 1
        if s.rx.n > 12 then return end                   -- (more than 12 blasts in a second: the rest not shown)
        local where, id = { X = x, Y = y, Z = z }, whole(f[7], 1, 99999)
        local best, bd = nil, math.huge                  -- (this game's own held plane of its dive nearest the blast goes with it;
        for _, e in ipairs(s.held) do                    -- an older host's, of no dive: any)
            local p = not e.gone and not e.ending and (id == nil or e.dive == id) and up(e) and at(e.obj)
            if p and dist(p, where) < bd then best, bd = e, dist(p, where) end
        end
        if best then best.ending = "the host's blast"; endStep(best, now) end
        s.blasts = s.blasts + 1
        effects(where)
        queue(s, "blast", math.max(0, math.min(999, num(f[6], 0))))
    elseif k == "e" then
        local id, n, q = whole(f[3], 1, 99999), 0, 0
        for _, d in ipairs(divesOf(s, id)) do
            for _, e in ipairs(s.held) do
                if e.dive == d.id and not e.gone and not e.ending then e.ending = "the host's dive over"; endStep(e, os.clock()); n = n + 1 end
            end
            for u in pairs(d.units) do
                if ESC and ESC.recycleQ then ESC.recycleQ[#ESC.recycleQ + 1] = { unit = u, at = os.clock() + 3, why = "the host's dive over" }; q = q + 1 end
            end
            d.units, d.on = {}, false
        end
        log(string.format("dive: the host's dive %s over after %d blasts here; %d of this game's own finished off, %d units off the list once none is up",
            tostring(id or "?"), s.blasts, n, q))
    end
end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the ZFA-44s' dive"] = function() ZDIVE.d = nil end end
end
