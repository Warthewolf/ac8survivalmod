-- sv_stats.lua: the behaviour roadmap's measurements (CFG.stats; tools/re/BEHAVIOUR_DIRECTOR.md, unit 1).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local (tools/lua_split.py).
--
-- The Claude Docs thesis "AC8 Survival Mode: Enemy Behaviour Reference & Challenge Thesis" (its "What to measure in each
-- test") asks every test for seven numbers: time to kill an ordinary fighter in rounds 7-12 (target 20-40 s), how long
-- a tailed enemy survives (8 s+ at Veteran), a special round's length (5-8 min), missiles left at death (under 40), what
-- did the damage at death (varied: guns, brackets, specials), the director's tactics per round (3-6, each with a
-- callout) and the share of kills from behind (under 70 %). None of them had a log line. This part keeps them, from
-- hooks the other parts call (each through pcall):
--   STATS.track(p, you, now)        sv_main.lua's plane sweep, each live enemy every 2 s: engaged, first hit, your tail
--   STATS.aiState(p, st, now)       sv_ai.lua aiWatch, the same sweep: its AI state (Provoke / EscapeFromPursuer)
--   STATS.down(p, g, by, now)       the sweep's death branch (g: KILL.geom, by: creditKill's side): "kill-time:"
--   STATS.fired(kind, n)            sv_flights.lua ammoTick: your shots (0 gun, 1 missiles, 2 / 3 specials, 4 flares)
--   STATS.hit(now, hp, pawn)        sv_ladon.lua HIT.tick: each drop of your health, with what caused it
--   STATS.death(how)                shot down (sv_leaderboard.lua) or saved by SECOND CHANCE (sv_tactical.lua): "death:"
--   STATS.roundStart / roundEnd     sv_rounds.lua (host, solo), sv_coop.lua clientRounds (a joiner): "stats: round N"
--   STATS.sample(now, you)          sv_main.lua every 2 s: time down at the airfield; a cleared round's line
--   STATS.runEnd(how)               LB.finish: "stats: run over"
--   STATS.hostReset(now, resync)    sv_coop.lua, a joiner told "rs": its round cut short; the host's new run: a run line
--   STATS.tactic(name, unit, slot, why, callout)   the squad / intensity director's tactics (P2, P4): a "director:"
--                                   line, counted per round, and the unit's live planes tagged p.dirTag = { tactic, at }
-- and, at the end of the part, P6's learning layer (PROF: your habits from the same hooks, CFG.profile).
-- Logged only (AC8SurvivalMode_lua.log), never sent: friends' release logs are the test data, so none of this is in a
-- test-only or online-only block, and the leaderboard's JSON keeps its fixed fields. The time base is D.now, the game
-- clock (it stops in a pause). Per plane on its record (hard rule 16: flights are recycled), per round in D.rs, per run
-- in RUN.metrics. Each plane is seen every 2 s, so every time here is good to about +/- 2 s.
STATS = {}
PROF = {}
do
local AMMO_KEY = { [0] = "gun", "msl", "sp1", "sp2", "flr" }
local OPEN_STATES = { Provoke = true, EscapeFromPursuer = true }                   -- it's defending: you're on its tail
local KEEP_STATES = { AttackAvoidance = true, Blackout = true, UniqueAction = true } -- (mid-defence: still the same one)
local NOT_DIRECTOR = { reversal = true }  -- the aces' own reversals (ACE.movesTick): counted apart, never tagged
local MAX_KILLS = 4000                    -- a run's kill records (60 a round for 35 rounds still fits)

local function on() local c = CFG.stats; return c ~= nil and c.enabled ~= false end
local function cfg() return CFG.stats or {} end
local function client() return (COOP and COOP.client and COOP.client()) and true or false end

local function median(t)
    local n = #t
    if n == 0 then return nil end
    local s = table.move(t, 1, n, 1, {})
    table.sort(s)
    if n % 2 == 1 then return s[(n + 1) // 2] end
    return (s[n // 2] + s[n // 2 + 1]) / 2
end
local function sec(v) return v and string.format("%.0f s", v) or "-" end
local function sec1(v) return v and string.format("%.1f s", v) or "-" end   -- (the tail watch: 250 ms ticks)
local function share(a, b) return (b or 0) > 0 and string.format("%.0f%%", 100 * (a or 0) / b) or "-" end
local function angle(ax, ay, az, bx, by, bz)          -- between two vectors, degrees (180 when one has no length)
    local la, lb = math.sqrt(ax * ax + ay * ay + az * az), math.sqrt(bx * bx + by * by + bz * bz)
    if la == 0 or lb == 0 then return 180 end
    return math.deg(math.acos(math.max(-1, math.min(1, (ax * bx + ay * by + az * bz) / (la * lb)))))
end
local function tierIndex(t)                           -- a plane's tier (CFG.tiers.list entry) as its index, or nil
    if not t then return nil end
    for i, x in ipairs(CFG.tiers.list) do if x == t or x.name == t.name then return i end end
    return nil
end
local function veteran()                              -- the run line's "Veteran+": that tier's index
    for i, x in ipairs(CFG.tiers.list) do if x.name == "Veteran" then return i end end
    return 3
end
local function metrics()                              -- the run's records (RUN is made anew at every level load)
    local m = RUN.metrics
    if not m then
        m = { kills = {}, rounds = {}, fired = {}, dmg = {}, hpTaken = 0, brackets = 0, deaths = {} }
        RUN.metrics = m
    end
    return m
end
local function held(k)                               -- what you hold of ammo kind k: Survival's count, else the last read
    if A and A.caps and A.caps[k] then return A.caps[k] end
    local h = PR and PR.ammo or {}
    for i = #h, 1, -1 do local v = h[i][k]; if v and v >= 0 then return v end end
    return nil
end

---------------------------------------------------------------------------------------------------- per plane
-- Each live enemy, every 2 s (the sweep's visit, after p.at / p.fwd / p.dmg / p.dist are fresh): born (logPlane), first
-- within engage_km of you (p.engagedAt), first hurt by you (p.hitAt), and your geometric tail: within tail_km and
-- tail_deg of its six (the aces' reversal test, ACE.movesTick). An episode on its tail runs from the first sample that
-- has you there (p.tailAt) to the first that hasn't (an escape) or to its death. p.youAt: where you were at this sample,
-- so the kill's aspect (KILL.geom) comes from one moment, not two reads 2 s apart.
function STATS.track(p, you, now)
    if not (on() and now and you and p.at) then return end
    local c = cfg()
    p.born = p.born or now                                 -- (logged before the round clock ran)
    p.youAt = { X = you.X, Y = you.Y, Z = you.Z }
    if p.tierI == nil and p.tier then p.tierI = tierIndex(p.tier) or false end
    if p.ace == nil then p.ace = (D and D.aceSquad and p.unit and D.aceSquad[p.unit]) and true or false end
    local d = p.dist or km(p.at, you)
    if not p.engagedAt and d <= (c.engage_km or 5) then p.engagedAt = now end
    if not p.hitAt and p.dmg and (p.dmg.you or 0) > 0 then p.hitAt = now end
    local tailing = false
    if p.fwd then
        local off = angle(-p.fwd.X, -p.fwd.Y, -p.fwd.Z, you.X - p.at.X, you.Y - p.at.Y, you.Z - p.at.Z)
        tailing = off <= (c.tail_deg or 70) and d <= (c.tail_km or 3)
    end
    if tailing then
        p.tailAt = p.tailAt or now
    elseif p.tailAt then                                   -- it got out from under you
        p.tailS, p.tailN = (p.tailS or 0) + (now - p.tailAt), (p.tailN or 0) + 1
        if D and D.rs then D.rs.tailEscaped = D.rs.tailEscaped + 1 end
        p.tailAt = nil
    end
    p.tailing = tailing
end

-- Its AI state (aiWatch's read, every 2 s): Provoke or EscapeFromPursuer starts an episode (p.provokeAt; the real start
-- can be up to 2 s earlier), AttackAvoidance / Blackout / UniqueAction keep it open, anything else ends it (escaped).
-- Not on a co-op joiner: its enemies are the host's, moved every frame (hard rule 48), so their AI state isn't theirs.
function STATS.aiState(p, st, now)
    if not (on() and now) or client() or st == nil or st == "?" then return end
    local rs = D and D.rs
    if rs then rs.stateS[st] = (rs.stateS[st] or 0) + 2 end            -- (time in each state, a sample a 2 s)
    if OPEN_STATES[st] then
        p.provokeAt = p.provokeAt or now
    elseif p.provokeAt and not KEEP_STATES[st] then
        p.provokeS, p.provokeN = (p.provokeS or 0) + (now - p.provokeAt), (p.provokeN or 0) + 1
        if rs then rs.provokeEscaped = rs.provokeEscaped + 1 end
        p.provokeAt = nil
    end
end

---------------------------------------------------------------------------------------------------- the tail watch (P5)
-- P5's gate (a harder tailed plane; the thesis: "a tailed enemy lasts 8 s+ at Veteran"; runtime-ai step 10): the 2 s
-- sweep above can't tell a 0.8 s reaction from 2.5 s. STATS.tailTick runs every 250 ms tick (sv_main.lua probeTick,
-- timed "tail watch"; the host or solo: a joiner's enemies are the host's): the enemies with a skill tier (no bombers)
-- within watch_km of you by the sweep's last sample, at most watch_max a tick, get a fresh position and heading: those
-- you're likely on the tail of first (the sweep's p.tailing, or its last pose against where you are now: no read), then
-- the nearest, so a plane you chase at 2.5 km isn't crowded out by four nearer ones in a furball. You on a live one's
-- tail (tail_km, tail_deg: the sweep's own test) opens an episode (p.tw, t0), and its provoke values in force are read
-- then (ProvokeConditionConeAngle / ProvokeDeterminationTime: Survival's write, sv_rows.lua enemySpike, or the game's own
-- row). While it's open the plane is read every tick, its AI state too: when it first went into Provoke or
-- EscapeFromPursuer after t0 (its reaction), how long it spent in each state. One already in Provoke,
-- EscapeFromPursuer or Blackout at its first read was defending before you got there (another pursuer, or you closed
-- from beyond tail_km): "already defending", kept out of the reaction figures (the A/B of the live provoke reads those).
-- The episode ends when it dies ("died": seconds since t0, and since its Provoke, the thesis' own measure), once you've
-- been off its tail for watch_grace_s ("escaped": how long you held it), or when the run ends with you still on it
-- ("still up"); an escape or a still-up shorter than ESC_MIN_S is a flicker at the cone's edge, dropped. A "tailed:"
-- line, the round line's "tail watch" part, and the run line's Veteran+ figures.
local tailEnd, tailCut = nil, nil
do
local AISTATE = nil                               -- (FName("AIState"), made at the first read, in the game thread)
local ESC_MIN_S = 1.0
local SHOWN = { "Provoke", "EscapeFromPursuer", "AttackAvoidance", "Blackout", "UniqueAction" }
local PRE = { Provoke = true, EscapeFromPursuer = true, Blackout = true }   -- (at the first read: already defending)
local function tw() local c = cfg(); return c.tail_watch ~= false and on() end
local function readState(p)
    local ok, v = pcall(function()
        AISTATE = AISTATE or FName("AIState")
        local bb = p.bb or p.obj.AIStateComponent.BlackboardComponent
        p.bb = bb
        return bb:GetValueAsEnum(AISTATE)
    end)
    if not (ok and type(v) == "number") then p.bb = nil; return nil end
    return (AI_STATE and AI_STATE[v]) or tostring(v)
end
local function fresh(p)                           -- position (cm) and heading now, or nil
    local ok, at, fwd = pcall(function()
        local v, f = p.obj:K2_GetActorLocation(), p.obj:GetActorForwardVector()
        return { X = v.X, Y = v.Y, Z = v.Z }, { X = f.X, Y = f.Y, Z = f.Z }
    end)
    if ok then return at, fwd end
    return nil
end
local function alive(p)
    if p.down or not valid(p.obj) then return false end
    local ok, h = pcall(function() return p.obj.HealthInternal end)
    return not (ok and type(h) == "number" and h <= 0)
end
local function geom(at, fwd, me)                  -- range (m) and your angle off its tail (deg)
    local dx, dy, dz = me.X - at.X, me.Y - at.Y, me.Z - at.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 100, angle(-fwd.X, -fwd.Y, -fwd.Z, dx, dy, dz)
end
local function open(p, now, m, off)
    local e = { t0 = now, last = now, st = {}, km = m / 1000, off = off, written = p.provokeSet ~= nil }
    local okC, c = pcall(function() return p.obj.ProvokeConditionConeAngle end)
    local okT, t = pcall(function() return p.obj.ProvokeDeterminationTime end)
    e.cone, e.time = okC and type(c) == "number" and c or nil, okT and type(t) == "number" and t or nil
    if p.tierI == nil and p.tier then p.tierI = tierIndex(p.tier) or false end
    p.tw = e
end
-- An episode ends (how): "died" (its death seen now, by the watch or the sweep), "escaped", or "up" (the run ended with
-- the episode open; why: the run's end); its line and its counts. An already-defending episode (e.pre) has no reaction
-- of its own: counted apart, never in the reaction figures or "after its Provoke" (that Provoke began before t0).
tailEnd = function(p, now, how, why)
    local e = p.tw
    if not e then return end
    p.tw = nil
    local died = how == "died"
    local held = (died and now or e.last) - e.t0
    if not died and held < ESC_MIN_S then return end
    local fromProv = (died and e.provAt) and now - e.provAt or nil
    local vet = (p.tierI or 0) >= veteran()
    local rs, m = D and D.rs, metrics()
    if rs then
        local w = rs.tw
        w.n = w.n + 1
        if vet then w.vet = w.vet + 1 end
        if died then
            w.died[#w.died + 1] = held
            if fromProv then w.diedProv[#w.diedProv + 1] = fromProv end
        elseif how == "up" then
            w.up = w.up + 1
        else
            w.esc[#w.esc + 1] = held
        end
        if e.pre then w.pre = w.pre + 1
        elseif e.react then w.react[#w.react + 1] = e.react else w.noReact = w.noReact + 1 end
        if (e.st.Blackout or 0) > 0 then w.blackout = w.blackout + 1 end
    end
    m.tw = m.tw or {}
    if #m.tw < 4000 then
        m.tw[#m.tw + 1] = { round = D and D.round or 0, vet = vet, died = died, up = how == "up", held = held,
                            fromProv = fromProv, react = e.react, pre = e.pre, blackout = (e.st.Blackout or 0) > 0 }
    end
    local st = {}
    for _, name in ipairs(SHOWN) do if (e.st[name] or 0) > 0 then st[#st + 1] = string.format("%s %.1f s", name, e.st[name]) end end
    if (e.st.other or 0) > 0 then st[#st + 1] = string.format("other %.1f s", e.st.other) end
    local t = p.tier
    local ending = (died and string.format("died %.1f s after%s", held,
            fromProv and string.format(" (%.1f s after its Provoke)", fromProv) or ""))
        or (how == "up" and string.format("still up when the run ended (%s), %.1f s on its tail", tostring(why or "?"), held))
        or string.format("escaped after %.1f s", held)
    log(string.format("tailed: %s (%s, %s%s, rank %s, AI level %s): provoke %s deg / %s s (%s); you on its tail at %.1f km, " ..
        "%.0f deg off its six; %s; %s; %s", p.name, tostring(p.unit or "?"), t and t.name or "no tier",
        p.k and (", k " .. p.k) or "", tostring(p.rankSet or "?"), tostring(t and t.ai_level or 2),
        e.cone and string.format("%.0f", e.cone) or "?", e.time and string.format("%.1f", e.time) or "?",
        e.written and "Survival's" or "the game's", e.km, e.off,
        (e.pre and string.format("already in %s when you got behind it", e.pre))
            or (e.react and string.format("Provoke after %.1f s", e.react)) or "no Provoke",
        #st > 0 and table.concat(st, ", ") or "no states read", ending))
end
-- The run's over with episodes open (STATS.runEnd, before its last round's line): each ends as "still up".
tailCut = function(now, why)
    for _, p in ipairs(planes or {}) do if p.tw then tailEnd(p, now, "up", why) end end
end
function STATS.tailTick(now)
    if not (now and D and tw()) or client() then return end
    local c = cfg()
    local me = COOP and COOP.me and COOP.me()
    me = me and me.at
    if not me then
        local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
        local ok, v = pcall(function() return pawn:K2_GetActorLocation() end)
        if not (ok and v) then return end
        me = { X = v.X, Y = v.Y, Z = v.Z }
    end
    local cand, near = {}, {}
    local wkm, max = c.watch_km or 4.5, math.max(1, math.floor(c.watch_max or 4))
    local tkm, tdeg, grace = (c.tail_km or 3) * 1000, c.tail_deg or 70, c.watch_grace_s or 2.0
    for _, p in ipairs(planes) do
        if p.tw then cand[#cand + 1] = p
        elseif not p.down and p.tier and p.dist and p.dist <= wkm and not (p.unit and BOMBER_UNIT[p.unit]) then
            -- (likely on its tail: the sweep said so, or its last pose against you now; no read)
            local likely = p.tailing and true or false
            if not likely and p.at and p.fwd then
                local m, off = geom(p.at, p.fwd, me)
                likely = m <= tkm and off <= tdeg
            end
            p.twFirst = likely
            near[#near + 1] = p
        end
    end
    table.sort(near, function(a, b)
        if a.twFirst ~= b.twFirst then return a.twFirst end
        return a.dist < b.dist
    end)
    for i = 1, math.min(#near, max - #cand) do cand[#cand + 1] = near[i] end
    for _, p in ipairs(cand) do
        local e = p.tw
        if e and not alive(p) then
            tailEnd(p, now, "died")
        else
            -- (one fresh read a plane a tick, shared with the squad director: p.pose, sv_director.lua, which runs first)
            local at, fwd
            local q = p.pose
            if q and q.t == now then at, fwd = q.at, q.fwd
            else
                at, fwd = fresh(p)
                if at then p.pose = { t = now, at = at, fwd = fwd } end
            end
            if at then
                local m, off = geom(at, fwd, me)
                local tailing = m <= tkm and off <= tdeg
                if tailing and not e and alive(p) then open(p, now, m, off); e = p.tw end   -- (never on a wreck)
                if e then
                    local dt = math.max(0, math.min(1, now - (e.seen or now)))
                    e.seen = now
                    local st = readState(p)
                    if st then
                        local k = (st == "Provoke" or st == "EscapeFromPursuer" or st == "AttackAvoidance" or st == "Blackout"
                                   or st == "UniqueAction") and st or "other"
                        e.st[k] = (e.st[k] or 0) + dt
                        if e.first == nil then                     -- (its first read: was it defending already?)
                            e.first = st
                            if PRE[st] then e.pre = st end
                        end
                        if not (e.react or e.pre) and (st == "Provoke" or st == "EscapeFromPursuer") then
                            e.react, e.provAt = now - e.t0, now
                        end
                    end
                    if tailing then e.last = now
                    elseif now - e.last >= grace then tailEnd(p, now, "escaped") end
                end
            end
        end
    end
end
end

-- An enemy found down (the sweep, up to 2 s after it fell). g: KILL.geom (aspect, range, your recent shots and the
-- weapon spent last), by: creditKill's side ("you", "allies", "ships", "defences", "airstrike", "wingmate" in co-op;
-- nil for a Ladon). An ordinary fighter: a pool flight's plane that isn't a bomber, an ace squadron's, the jammer or a
-- probe flight (ace and jammer as the host's spawner set them, also for a plane the sweep never tracked). A co-op
-- joiner can't tell: only the host knows which flights are aces or led by the jammer (D.aceSquad, D.jammer), so a
-- joiner's pool fighters are ordinary = nil, kept out of the time to kill. Only your own kills feed the shares (behind,
-- weapon); every death ends its tail episodes.
local function isOrdinary(p, u)
    if not (u and poolIndex(u) and not BOMBER_UNIT[u] and not PROBE_OF[u]) then return false end
    if client() then return nil end
    local ace = p.ace                                       -- (as tracked, while its flight was the one it came with)
    if ace == nil then ace = D.aceSquad and D.aceSquad[u] end
    if ace then return false end
    local lr = D.leadRow and D.leadRow[u]                   -- (the jammer, down before JAM.tick saw it: its EA-18G)
    if p.jammer or (lr and lr.code == "e18g" and p.name and p.name:find("_e18g_", 1, true)) then return false end
    return true
end
function STATS.down(p, g, by, now)
    if PROF.kill then pcall(PROF.kill, p, g, by) end      -- (P6's habits: your kills; with the measurements off too)
    if not (on() and D and now) then return end
    if p.tw then tailEnd(p, now, "died") end              -- (the sweep saw it down before the tail watch did)
    local c, rs = cfg(), D.rs
    local u = p.unit
    local ordinary = isOrdinary(p, u)
    local mine = by == "you"
    local behind, close = nil, nil
    if g and g.offNose and g.km then
        behind = g.offNose >= 180 - (c.tail_deg or 70) and g.km <= (c.tail_km or 3)
        close = g.km <= (c.close_km or 1.2)
    end
    local wpn = g and g.wpn or nil
    local r = { round = D.round or 0, tierI = p.tierI or nil, ordinary = ordinary, mine = mine, behind = behind, wpn = wpn,
                up = p.born and now - p.born, engaged = p.engagedAt and now - p.engagedAt, hit = p.hitAt and now - p.hitAt,
                tailedAI = p.provokeAt and now - p.provokeAt, tailedGeo = p.tailAt and now - p.tailAt }
    if rs then
        rs.down = rs.down + 1
        if mine then rs.mineAll = rs.mineAll + 1 end
        if ordinary == nil then rs.unsorted = rs.unsorted + 1 end      -- (a joiner's pool fighters)
        if ordinary then
            rs.fighters = rs.fighters + 1
            if mine then
                rs.fightersMine = rs.fightersMine + 1
                if r.engaged then rs.ttk[#rs.ttk + 1] = r.engaged end
                if r.up then rs.ttkSpawn[#rs.ttkSpawn + 1] = r.up end
                if r.hit then rs.ttkHit[#rs.ttkHit + 1] = r.hit end
            end
        end
        if r.tailedAI then rs.tailedAI[#rs.tailedAI + 1] = r.tailedAI end
        if r.tailedGeo then rs.tailedGeo[#rs.tailedGeo + 1] = r.tailedGeo end
        if mine then
            if behind ~= nil then rs.mineGeo = rs.mineGeo + 1; if behind then rs.behind = rs.behind + 1 end end
            if close then rs.close = rs.close + 1 end
            local w = ((wpn == "sp1" or wpn == "sp2") and "special") or wpn or "none"
            rs.wpn[w] = (rs.wpn[w] or 0) + 1
        end
    end
    local m = metrics()
    if #m.kills < MAX_KILLS then m.kills[#m.kills + 1] = r end
    if c.kill_lines == false then return end
    local tag = type(p.dirTag) == "table" and p.dirTag or nil
    log(string.format("kill-time: %s (%s, %s, round %d%s%s): up %s, engaged %s (within %g km), since your first hit %s, " ..
        "tailed %s (AI Provoke %s); %s; by %s%s", p.name, tostring(u or "?"), p.tier and p.tier.name or "no tier", r.round,
        p.k and (", k " .. p.k) or "", (ordinary and ", ordinary") or (ordinary == nil and ", ordinary ?") or "", sec(r.up),
        sec(r.engaged), c.engage_km or 5,
        sec(r.hit), sec(r.tailedGeo), sec(r.tailedAI),
        (g and g.offNose and g.km) and string.format("%.0f deg off its nose at %.1f km, %+.1f km", g.offNose, g.km, g.dz or 0)
            or "aspect ?", tostring(by or "?"),
        tag and string.format(", director %s %.0f s before", tostring(tag.tactic), now - (tag.at or now)) or ""))
end

---------------------------------------------------------------------------------------------------- your shots, your hits
function STATS.fired(k, n)
    if not (on() and type(k) == "number" and type(n) == "number" and n > 0 and n < 100000) then return end
    local m = metrics()
    m.fired[k] = (m.fired[k] or 0) + n
    if D and D.rs then D.rs.fired[k] = (D.rs.fired[k] or 0) + n end
end

local function unitAt(addr)                           -- the enemy (its flight, else its name) at that address, or nil
    if not addr then return nil end
    for _, p in ipairs(planes) do if p.addr == addr then return p.unit or p.name end end
    return nil
end
local function aimedElsewhere(m, pa)                  -- a missile homing on something else (an ally's, a ship's)
    if not (pa and valid(m.obj)) then return false end
    local ok, t = pcall(function() return m.obj.TargetToHome end)
    if not (ok and valid(t)) then return false end
    return addrOf(t) ~= pa
end
-- What caused a drop of your health now: "missile" (an enemy missile within 800 m, seen in the last 0.6 s: the HIT
-- log's own test; who fired it, its name, and whether missiles of two shooters were within bracket_km in the last
-- second: a bracket), else "gun/close" (an enemy within gun_km: its gun, its pulse cannon, a collision), else "unknown"
-- (a SAM's blast, the railgun, the ground). HIT.msl holds every missile but yours; one homing on someone else is skipped.
local function classify(now, pawn)
    local c = cfg()
    local pa = valid(pawn) and addrOf(pawn) or nil
    local br = (c.bracket_km or 1.5) * 1000
    local reach = math.max(800, br)                   -- (only these are read for their target: a few, not the sky's 60)
    local best, shooters, n = nil, {}, 0
    for _, m in ipairs(HIT.msl or {}) do
        local age = now - (m.seen or -1e9)
        if m.d and age <= 1 and m.d <= reach and not aimedElsewhere(m, pa) then
            if age <= 0.6 and m.d <= 800 and (not best or m.d < best.d) then best = m end
            local key = m.fromAddr or m.from
            if key and m.d <= br and not shooters[key] then shooters[key] = true; n = n + 1 end
        end
    end
    if best then return "missile", unitAt(best.fromAddr) or best.from or "?", best.name, n >= 2 end
    local near, nd = nil, nil
    for _, p in ipairs(planes) do
        if not p.down and p.dist and p.dist <= (c.gun_km or 1.5) and (not nd or p.dist < nd) then near, nd = p, p.dist end
    end
    if near then return "gun/close", near.unit or near.name, nil, false end
    return "unknown", nil, nil, false
end
-- A drop of your health (HIT.tick, every tick it happens; hp in HP): kept for 60 s (at most 80) for the death line,
-- and added up per round and per run by its source.
function STATS.hit(now, hp, pawn)
    if not (on() and D and now and type(hp) == "number" and hp > 0) then return end
    local src, who, what, bracket = classify(now, pawn)
    local ring = D.hitRing or {}
    D.hitRing = ring
    ring[#ring + 1] = { at = now, hp = hp, src = src, who = who, what = what, bracket = bracket }
    while #ring > 80 or (ring[1] and now - ring[1].at > 60) do table.remove(ring, 1) end
    local m = metrics()
    m.dmg[src], m.hpTaken = (m.dmg[src] or 0) + hp, m.hpTaken + hp
    if bracket then m.brackets = m.brackets + 1 end
    local rs = D.rs
    if rs then rs.dmg[src], rs.hp = (rs.dmg[src] or 0) + hp, rs.hp + hp end
end

-- Your aircraft's own damage record (CFG.stats.pawn_history; metrics brief step 6.3, untested): its DamageHistoryMap,
-- attacker -> damage since it took off (the armour's share in it too, which HIT can't see), read as KILL.read reads an
-- enemy's. The three that did the most, by flight (an enemy here) or name, as "; record: ..." for the death line.
local function pawnHistory()
    if cfg().pawn_history == false then return "" end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return "" end
    local by, n = {}, 0
    local ok = pcall(function()
        pawn.DamageHistoryMap:ForEach(function(k, v)
            local okK, o = pcall(function() return k:get() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and type(x) == "number" and x > 0 and valid(o) then
                local who = unitAt(addrOf(o)) or ((nameOf(o):match("([^%.:]+)$") or "?"):gsub("_C_%d+$", ""))
                by[who], n = (by[who] or 0) + x, n + 1
            end
        end)
    end)
    if not ok then return "; record: not read" end
    local t = {}
    for w, x in pairs(by) do t[#t + 1] = { w, x } end
    table.sort(t, function(a, b) return a[2] > b[2] end)
    local top = {}
    for i = 1, math.min(3, #t) do top[i] = string.format("%s %.0f", t[i][1], t[i][2]) end
    return string.format("; record: %d attacker%s%s", n, n == 1 and "" or "s", #top > 0 and (", " .. table.concat(top, ", ")) or "")
end

-- Shot down ("died") or saved at the floor by SECOND CHANCE ("saved"): what hit you in the last death_window_s, by
-- source and by shooter, and what you still held (metrics 4 and 5).
function STATS.death(how)
    if not (on() and D) then return end
    local c, now, m = cfg(), D.now or 0, metrics()
    local win = c.death_window_s or 30
    local tot, by, nM, shooters, nS, br, top = 0, {}, 0, {}, 0, 0, {}
    for _, e in ipairs(D.hitRing or {}) do
        if now - e.at <= win then
            tot = tot + e.hp
            by[e.src] = (by[e.src] or 0) + e.hp
            if e.src == "missile" then
                nM = nM + 1
                if e.who and not shooters[e.who] then shooters[e.who] = true; nS = nS + 1 end
            end
            if e.bracket then br = br + 1 end
            if e.who then top[e.who] = (top[e.who] or 0) + e.hp end
        end
    end
    local tl = {}
    for w, hp in pairs(top) do tl[#tl + 1] = { w, hp } end
    table.sort(tl, function(a, b) return a[2] > b[2] end)
    local tt = {}
    for i = 1, math.min(3, #tl) do tt[i] = string.format("%s %.0f HP", tl[i][1], tl[i][2]) end
    local msl = held(1)
    if how == "died" then m.mslLeft = msl end
    if #m.deaths < 50 then m.deaths[#m.deaths + 1] = { round = D.round, how = how, hp = tot, by = by } end
    local rs = D.rs
    log(string.format("death: round %d (%s)%s: last %d s -%.0f HP: missiles %s (%d hits from %d shooters, %d brackets), " ..
        "gun/close %s, unknown %s; top: %s; missiles left %s (fired %d this run, %d this round), specials %s/%s, flares %s%s",
        D.round or 0, how == "saved" and "saved by SECOND CHANCE" or tostring(how),
        rs and string.format(", %.0f s into the round", now - rs.at) or "", win, tot, share(by.missile, tot), nM, nS, br,
        share(by["gun/close"], tot), share(by.unknown, tot), #tt > 0 and table.concat(tt, ", ") or "nothing seen",
        tostring(msl or "?"), m.fired[1] or 0, rs and rs.fired[1] or 0, tostring(held(2) or "?"), tostring(held(3) or "?"),
        tostring(held(4) or "?"), pawnHistory()))
end

---------------------------------------------------------------------------------------------------- the director's tactics
-- A tactic the director spends (P2 / P4 call this): counted in the round, logged, and the unit's live planes tagged
-- p.dirTag = { tactic, at } (one contract: P8's director-kill bonus and the kill-time line read it). slot: the player
-- it's aimed at (COOP.players()), nil for the room. ACE.movesTick's reversals come here as "reversal": counted apart
-- (the round line's "ace reversals"), not tagged, not logged again (aces: lines). Runs with CFG.stats off too (the tag).
function STATS.tactic(name, unit, slot, why, callout)
    if not D then return end
    name = tostring(name or "?")
    local rs = D.rs
    if NOT_DIRECTOR[name] then
        if rs then rs.moves[name] = (rs.moves[name] or 0) + 1 end
        return
    end
    if rs then
        rs.tactics[name] = (rs.tactics[name] or 0) + 1
        rs.nTactics = rs.nTactics + 1
        if callout then rs.callouts = rs.callouts + 1 end
    end
    local n = 0
    if unit then
        local tag = { tactic = name, at = D.now }
        for _, p in ipairs(planes) do if not p.down and p.unit == unit then p.dirTag = tag; n = n + 1 end end
    end
    log(string.format("director: round %d +%.0f s: %s on %s%s%s%s", D.round or 0, (rs and D.now) and (D.now - rs.at) or 0,
        name, unit and string.format("%s (%d planes)", unit, n) or "the round",
        (slot and COOP and COOP.open) and string.format(", player %d", slot + 1) or "", why and (" (" .. tostring(why) .. ")") or "",
        callout and string.format('; callout "%s"', tostring(callout)) or ""))
end

---------------------------------------------------------------------------------------------------- rounds
local function newRound(now)
    local ti = CFG.tiers.enabled and CFG.tiers.list[TIER.index(D.round)]
    return { round = D.round, at = now, ground = 0, tier = ti and ti.name or "no tier", client = client(),
             down = 0, mineAll = 0, fighters = 0, fightersMine = 0, unsorted = 0, ttk = {}, ttkSpawn = {}, ttkHit = {},
             tailedAI = {}, tailedGeo = {}, provokeEscaped = 0, tailEscaped = 0, mineGeo = 0, behind = 0, close = 0,
             wpn = {}, fired = {}, dmg = {}, hp = 0, tactics = {}, nTactics = 0, callouts = 0, moves = {}, stateS = {},
             tw = { n = 0, vet = 0, died = {}, diedProv = {}, esc = {}, up = 0, react = {}, noReact = 0, pre = 0, blackout = 0 } }
end
-- The tail watch's part of the round line (P5): its episodes, Veteran+ among them. "Provoke after" is the fresh
-- reactions only; "already defending": episodes whose plane was in Provoke / EscapeFromPursuer / Blackout at once.
local function watchPart(w)
    if not w or cfg().tail_watch == false then return "" end
    return string.format("; tail watch: %d episode%s (Veteran+ %d): died after median %s (n %d), %s after its Provoke " ..
        "(n %d), escaped %d (held median %s), still up at the end %d, Provoke after median %s (none in %d, already " ..
        "defending %d), blackouts %d", w.n, w.n == 1 and "" or "s",
        w.vet, sec1(median(w.died)), #w.died, sec1(median(w.diedProv)), #w.diedProv, #w.esc, sec1(median(w.esc)), w.up,
        sec1(median(w.react)), w.noReact, w.pre, w.blackout)
end

-- The round's line, logged a few seconds after it ended (flushRound): the sweep sees a plane down up to 2 s after the
-- spawner does, so the round's last kills come in after its clear.
local function flushRound()
    local rs = D and D.rs
    if not rs or rs.logged or not rs.ended then return end
    rs.logged = true
    local m = metrics()
    local len = rs.ended - rs.at
    local kind = rs.kind or "normal"
    local spS                                              -- the special's own time (LB.special)
    for _, s in ipairs((RUN.stats and RUN.stats.specials) or {}) do if s.round == rs.round then spS = s.seconds end end
    local tl = {}
    for name, x in pairs(rs.tactics) do tl[#tl + 1] = name .. " x" .. x end
    table.sort(tl)
    local players = 1
    if COOP and COOP.open and COOP.lobby then local okL, lb = pcall(COOP.lobby); if okL and lb and lb.n then players = lb.n end end
    local w, f = rs.wpn, rs.fired
    -- (a joiner can't tell the host's aces and jammer from ordinary fighters: its pool fighters down, no time to kill)
    local ft = rs.client and string.format("ordinary fighters ? (a joiner can't tell aces; %d pool fighters down)", rs.unsorted)
        or string.format("ordinary fighters %d (yours %d): time to kill since engaged median %s (n %d), since spawn median %s, " ..
            "since your first hit median %s", rs.fighters, rs.fightersMine, sec(median(rs.ttk)), #rs.ttk,
            sec(median(rs.ttkSpawn)), sec(median(rs.ttkHit)))
    log(string.format("stats: round %d (%s, %s%s, %d player%s)%s: length %.0f s (%.0f s at the airfield), %d wave%s; " ..
        "aircraft down %d (yours %d), %s; tailed survival: AI Provoke median %s (%d died, %d escaped), " ..
        "geometric median %s (%d died, %d escaped); kills from behind %d/%d (%s); your kills with missiles %d, gun %d, " ..
        "special %d, nothing seen %d (%d close); missiles left %s, fired %d this round; you took %.0f HP (missiles %s, " ..
        "gun/close %s, unknown %s); director tactics %d (%s; %d callouts); ace reversals %d",
        rs.round, rs.tier, kind, spS and string.format(" %d s", spS) or "", players, players == 1 and "" or "s",
        rs.cut and (" (cut short: " .. tostring(rs.cut) .. ")") or "", len, rs.ground, rs.waves or 1,
        (rs.waves or 1) == 1 and "" or "s", rs.down, rs.mineAll, ft, sec(median(rs.tailedAI)), #rs.tailedAI, rs.provokeEscaped,
        sec(median(rs.tailedGeo)), #rs.tailedGeo, rs.tailEscaped, rs.behind, rs.mineGeo, share(rs.behind, rs.mineGeo),
        w.msl or 0, w.gun or 0, w.special or 0, w.none or 0, rs.close, tostring(rs.mslLeft or "?"), f[1] or 0, rs.hp,
        share(rs.dmg.missile, rs.hp), share(rs.dmg["gun/close"], rs.hp), share(rs.dmg.unknown, rs.hp), rs.nTactics,
        #tl > 0 and table.concat(tl, ", ") or "none", rs.callouts, rs.moves.reversal or 0) .. watchPart(rs.tw))
    if #m.rounds < 500 then
        m.rounds[#m.rounds + 1] = { round = rs.round, kind = kind, len = len, ground = rs.ground, special = spS,
                                    tactics = rs.nTactics, callouts = rs.callouts }
    end
end

-- A round starts (startRound's end on the host and solo; on a joiner, the host's round number changing): the last one's
-- line goes out first if it hasn't yet.
function STATS.roundStart(now)
    if not (on() and D and D.round and D.round >= 1) then return end
    flushRound()
    D.rs = newRound(now or D.now or 0)
end

-- A round ends (the clear; a joiner: the host's state back to "wait"; cut: the run ended in it): its length, kind and
-- missiles left are taken now, its line a few seconds later (flushRound, from STATS.sample).
function STATS.roundEnd(now, cut)
    if PROF.checkpoint then pcall(PROF.checkpoint) end    -- (P6: the run so far into its file)
    local rs = D and D.rs
    if not (on() and rs) or rs.ended then return end
    now = now or D.now or rs.at
    rs.ended, rs.cut, rs.flushAt = now, cut, now + 3
    rs.kind = (D.special and D.special.kind) or (D.roundTier and "aces") or (client() and "?") or "normal"
    rs.waves = D.waves and #D.waves or 1
    rs.mslLeft = held(1)
end

-- Every 2 s (the sweep's summaries): the round's time down at the airfield while it's being fought (game clock, so a
-- pause in the landing store doesn't count), and a cleared round's line once the sweep has seen its last planes.
function STATS.sample(now, you)
    if PROF.sample then pcall(PROF.sample, now, you) end  -- (P6's habits: where you fly)
    local rs = D and D.rs
    if not (on() and rs and now) then return end
    if rs.ended then
        if now >= (rs.flushAt or 0) then flushRound() end
        return
    end
    local dt = rs.sampleAt and math.max(0, math.min(4, now - rs.sampleAt)) or 0
    rs.sampleAt = now
    if (D.state == "spawning" or D.state == "wave" or D.state == "fighting") and playerOnAirfield(you or nil) then
        rs.ground = rs.ground + dt
    end
end

-- Co-op, a joiner: the host sent "rs" (sv_coop.lua), before D.round goes back to 0. As the answer to this game's own
-- "jn" (its level loaded, its link came back) it's a resync: the open round ends here, cut short, and the host's next
-- round number starts a fresh one. Otherwise the host started a new run while this game's level, RUN and leaderboard run
-- go on: the round ends, the run so far gets its line, and the host's next run starts on empty records (RUN.metrics).
function STATS.hostReset(now, resync)
    if not resync and PROF.newRun then pcall(PROF.newRun, "the host started over") end   -- (P6: the run so far learnt)
    if not (on() and D) then return end
    if D.rs and not D.rs.ended then STATS.roundEnd(now, resync and "co-op resync" or "the host started over") end
    flushRound()
    local m = RUN.metrics
    if resync or not (m and (#m.rounds > 0 or #m.kills > 0)) then return end
    STATS.runEnd("the host started over")
    RUN.metrics = nil
end

---------------------------------------------------------------------------------------------------- the run
-- The run's over (LB.finish: died, restart, left): the round it ended in, then one line with the seven metrics against
-- the thesis' targets. RUN.metrics.kills keeps every kill's round, so "rounds 7-12" is worked out here.
function STATS.runEnd(how)
    if PROF.fold then pcall(PROF.fold, how) end           -- (P6: the run learnt into your profile, written)
    if not (on() and D) then return end
    local c, m = cfg(), metrics()
    if m.over then return end
    m.over = true
    if c.tail_watch ~= false then tailCut(D.now or 0, how) end   -- (episodes still open: in the run's last round)
    if D.rs and not D.rs.ended then STATS.roundEnd(D.now, how) end
    flushRound()
    local a, b, vet = c.ttk_from_round or 7, c.ttk_to_round or 12, veteran()
    local ttk, tAI, tGeo, geo, behind, unsorted = {}, {}, {}, 0, 0, 0
    for _, r in ipairs(m.kills) do
        if r.ordinary and r.mine and r.engaged and r.round >= a and r.round <= b then ttk[#ttk + 1] = r.engaged end
        if r.ordinary == nil and r.mine and r.round >= a and r.round <= b then unsorted = unsorted + 1 end
        if r.tierI and r.tierI >= vet then
            if r.tailedAI then tAI[#tAI + 1] = r.tailedAI end
            if r.tailedGeo then tGeo[#tGeo + 1] = r.tailedGeo end
        end
        if r.mine and r.behind ~= nil then geo = geo + 1; if r.behind then behind = behind + 1 end end
    end
    local sp = {}
    for _, s in ipairs((RUN.stats and RUN.stats.specials) or {}) do
        sp[#sp + 1] = string.format("%s %d s%s", tostring(s.kind), s.seconds or 0, s.won and "" or " (lost)")
    end
    local srl, tac, nr = {}, 0, 0
    for _, r in ipairs(m.rounds) do
        nr, tac = nr + 1, tac + (r.tactics or 0)
        if r.kind ~= "normal" and r.kind ~= "aces" and r.kind ~= "?" then
            srl[#srl + 1] = string.format("round %d %s %.0f s", r.round, r.kind, r.len)
        end
    end
    local msl = m.mslLeft
    if how ~= "died" or msl == nil then msl = held(1) end
    local d, f = m.dmg, m.fired
    local wpart = ""                                       -- the tail watch's Veteran+ episodes (P5's gate)
    if c.tail_watch ~= false then
        local wd, wp, we, wr, wn, wb, wu, wa = {}, {}, {}, {}, 0, 0, 0, 0
        for _, e in ipairs(m.tw or {}) do
            if e.vet then
                if e.died then wd[#wd + 1] = e.held; if e.fromProv then wp[#wp + 1] = e.fromProv end
                elseif e.up then wu = wu + 1
                else we[#we + 1] = e.held end
                if e.pre then wa = wa + 1 elseif e.react then wr[#wr + 1] = e.react else wn = wn + 1 end
                if e.blackout then wb = wb + 1 end
            end
        end
        wpart = string.format("; tail watch Veteran+: died after median %s on your tail (n %d), %s after its Provoke (n %d), " ..
            "escaped %d (held median %s), still up at the end %d, Provoke after median %s (none in %d, already defending %d), " ..
            "blackouts %d [8 s+]", sec1(median(wd)), #wd, sec1(median(wp)), #wp, #we, sec1(median(we)), wu, sec1(median(wr)),
            wn, wa, wb)
    end
    log(string.format("stats: run over (%s): rounds %d-%d; time to kill rounds %d-%d median %s (n %d%s) [target 20-40 s]; " ..
        "tailed survival Veteran+ AI Provoke median %s (n %d), geometric median %s (n %d) [8 s+]; specials %s; special " ..
        "rounds %s [5-8 min]; missiles left at the end %s [under 40]; damage taken %.0f HP: missiles %s, gun/close %s, " ..
        "unknown %s, brackets %d [varied]; director tactics per round avg %.1f (%d in %d rounds) [3-6]; kills from behind " ..
        "%s (%d/%d) [under 70%%]; fired: missiles %d, specials %d, flares %d, gun %d",
        tostring(how), D.startRound or 1, D.round or 0, a, b, sec(median(ttk)), #ttk,
        unsorted > 0 and string.format("; %d of your kills left out: a co-op joiner can't tell aces", unsorted) or "",
        sec(median(tAI)), #tAI,
        sec(median(tGeo)), #tGeo, #sp > 0 and table.concat(sp, ", ") or "none", #srl > 0 and table.concat(srl, ", ") or "none",
        tostring(msl or "?"), m.hpTaken, share(d.missile, m.hpTaken), share(d["gun/close"], m.hpTaken),
        share(d.unknown, m.hpTaken), m.brackets, nr > 0 and tac / nr or 0, tac, nr, share(behind, geo), behind, geo,
        f[1] or 0, (f[2] or 0) + (f[3] or 0), f[4] or 0, f[0] or 0) .. wpart)
end

-- (for tools/checks/stats_test.lua: the helpers above, unchanged)
STATS.median, STATS.classify = median, classify

---------------------------------------------------------------------------------------------------- P6: the learning layer
-- The thesis' P6 ("punish habits": the kill log has each kill's aspect and your weapons; the enemies drift towards
-- countering what this player keeps doing; across runs the profile is saved and picks the next run's role mix; the
-- metrics brief's steps 11-13, the critic's flare row and squad-director hook; CFG.profile, CFG.flares;
-- tools/re/BEHAVIOUR_DIRECTOR.md unit 8):
--   PROF.kill(p, g, by)      STATS.down, every game (a co-op joiner learns from its own kills): yours only (by "you")
--   PROF.sample(now, you)    STATS.sample, every 2 s: a fight's time in the air (high, near the airfield, on a tail)
--   PROF.weights(round)      sv_rounds.lua startRound (the host or solo), before its picks: D.counter, the round's line
--   PROF.chance, rankAdd, postStall, roleW, lancerAlt   the counters where each acts (sv_rounds, sv_ai, sv_spawn); a co-op
--                            joiner's give the base, 0, false, nil: its enemies are the host's copies
--   PROF.menu()              the main menu, once a session, before the NPC rows (sv_main.lua): the profile and the AI's
--                            flare row (PROF.flareWant, sv_rows.lua searchSetup)
--   PROF.levelLoad()         each level load: the profile read again (a run that ended this session, a hand edit)
--   PROF.checkpoint()        STATS.roundEnd: the run so far into the file ([run]; a game that closes loses a round)
--   PROF.fold(how)           STATS.runEnd (LB.finish: died, restart, left): the run learnt into the profile and written
--   PROF.newRun(why)         STATS.hostReset: a co-op host's new run while this game's level goes on
-- The run's counts in RUN.habit (RUN is made anew at each level load), the saved profile in PROF.saved, the round's
-- counters in D.counter (sv_director.lua DIR.roundStart reads its `tail`). The file is the game's own
-- (config/survival_profile.ini; the contract: never synced, not CFG), so a co-op host's settings never reach it.
do
local FILE, FORMAT = "survival_profile.ini", 1
local HABITS = { "missile", "gun", "tail", "high", "airfield" }
local PARTS = { "missile", "gun", "behind", "tail_time", "high", "airfield" }     -- the file's shares (tail from two)
local BY_KILL = { missile = true, gun = true, behind = true }                     -- (weighed by kills; the rest by time)
local RUN_KEYS = { "round", "from", "K", "Kw", "Km", "Kg", "Kgeo", "Kc", "Kb", "S", "Sh", "Sa", "St", "landings" }
local ROLE_GAIN = { gun = { "duelist", "wolf" }, tail = { "wolf" }, high = { "lancer" }, airfield = { "skirm" } }
local ALT_BIN, ALT_BINS = 250, 80                  -- (your height's histogram: 250 m bins up to 20 km)
local seen = {}                                    -- (run ids learnt from this session: a checkpoint is never learnt twice)
local wrote = { said = false }

local function pcfg() return CFG.profile or {} end
local function pon() local c = CFG.profile; return c ~= nil and c.enabled ~= false end
local function hcfg(h) local c = pcfg()[h]; return type(c) == "table" and c or {} end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end return v end
local function f2(v) return v and string.format("%.2f", v) or "-" end
local function filePath() return SCRIPT_DIR .. "..\\config\\" .. FILE end
local function neutral() return { version = FORMAT, runs = 0, learnt = 0, kills = 0 } end
local function tierAt(name)                        -- a CFG.tiers.list name's index (any case), or nil
    if type(name) ~= "string" then return nil end
    for i, t in ipairs(CFG.tiers.list) do if t.name:lower() == name:lower() then return i end end
    return nil
end
local nHabits = 0
local function newHabit()                          -- (its id from the clocks and a count: math.random's draws untouched)
    nHabits = nHabits + 1
    return { id = string.format("%08x%05x%02x", os.time() % 0x100000000, math.floor(os.clock() * 1000) % 0x100000,
                                nHabits % 0x100),
             K = 0, Kw = 0, Km = 0, Kg = 0, Kgeo = 0, Kc = 0, Kb = 0, S = 0, Sh = 0, Sa = 0, St = 0, landings = 0, alt = {} }
end
local function habit()                             -- this run's counts (made at its first kill, sample or round)
    local h = RUN and RUN.habit
    if h then return h end
    h = newHabit()
    if RUN then RUN.habit = h end
    return h
end
local function altMedian(h)                        -- your usual height (m): the median of the run's samples, else h.altM
    if (h.S or 0) <= 0 or not h.alt then return h.altM end
    local half, c = h.S / 2, 0
    for b = 0, ALT_BINS do
        c = c + (h.alt[b] or 0)
        if c >= half then return (b + 0.5) * ALT_BIN end
    end
    return h.altM
end
-- a run's shares (nil: nothing seen for one): missile Km / Kw (kills with a weapon seen), gun the bigger of Kg / Kw and
-- Kc / Kgeo (kills with an aspect), behind Kb / Kgeo, tail_time (St / S) / tail.time_full at most 1, high Sh / S,
-- airfield Sa / S
local function runShares(h)
    local s, tf = {}, math.max(0.01, num(hcfg("tail").time_full, 0.3))
    if h.Kw > 0 then s.missile = h.Km / h.Kw end
    if h.Kw > 0 or h.Kgeo > 0 then s.gun = math.max(h.Kw > 0 and h.Kg / h.Kw or 0, h.Kgeo > 0 and h.Kc / h.Kgeo or 0) end
    if h.Kgeo > 0 then s.behind = h.Kb / h.Kgeo end
    if h.S > 0 then s.tail_time, s.high, s.airfield = math.min(1, h.St / h.S / tf), h.Sh / h.S, h.Sa / h.S end
    return s
end
local function habitsOf(x)                         -- the five habits from the shares (tail: 0.6 behind + 0.4 its time)
    local t = { missile = x.missile, gun = x.gun, high = x.high, airfield = x.airfield }
    if x.behind and x.tail_time then t.tail = 0.6 * x.behind + 0.4 * x.tail_time else t.tail = x.behind or x.tail_time end
    return t
end
-- the shares in force: this run's (once it has live_kills of your kills / live_samples samples) weighed against the
-- saved profile's as if those were prior_kills / prior_samples of this run's; without one, the other
local function current(h, sv)
    local c, s, cur = pcfg(), runShares(h), {}
    local learnt = sv ~= nil and (sv.learnt or 0) > 0
    for _, k in ipairs(PARTS) do
        local kill = BY_KILL[k]
        local have = kill and h.K or h.S
        local x = s[k]
        if x ~= nil and have < num(kill and c.live_kills or c.live_samples, kill and 5 or 30) then x = nil end
        local prior = learnt and sv[k] or nil
        local w0 = math.max(0, num(kill and c.prior_kills or c.prior_samples, kill and 20 or 150))
        if x ~= nil and prior ~= nil then cur[k] = (w0 * prior + have * x) / (w0 + have)
        elseif x ~= nil then cur[k] = x else cur[k] = prior end
    end
    return cur
end
local function strength(name, x)                   -- a habit's strength: 0 at (or under) its threshold, 1 at 1.0
    local c = hcfg(name)
    if c.enabled == false or x == nil then return 0 end
    local thr = num(c.threshold, 1)
    if thr >= 1 or x <= thr then return 0 end
    return math.min(1, (x - thr) / (1 - thr))
end
local function chanceWith(base, x, max)            -- a chance base x x, at most max (never under base)
    if not x or x <= 1 then return base end
    return math.max(base, math.min(num(max, 0.9), base * x))
end

---------------------------------------------------------------------------------------------------- your kills, your flying
-- One of your kills (STATS.down, the sweep's death branch: g its KILL.geom). The weapon: your shots in the 6 s before
-- (g.used: the gun's, else a missile's or a special's; nothing seen: no weapon), the aspect from its last sample.
function PROF.kill(p, g, by)
    if not (pon() and by == "you" and D) then return end
    local h = habit()
    h.K = h.K + 1
    if not g then return end
    local u, sc = g.used or {}, CFG.stats or {}
    local gun = (u.gun or 0) > 0
    if gun or (u.msl or 0) + (u.sp1 or 0) + (u.sp2 or 0) > 0 then
        h.Kw = h.Kw + 1
        if gun then h.Kg = h.Kg + 1 else h.Km = h.Km + 1 end
    end
    if g.offNose and g.km then
        h.Kgeo = h.Kgeo + 1
        if g.km <= (sc.close_km or 1.2) then h.Kc = h.Kc + 1 end
        if g.offNose >= 180 - (sc.tail_deg or 70) and g.km <= (sc.tail_km or 3) then h.Kb = h.Kb + 1 end
    end
end

-- Every 2 s (STATS.sample, the sweep's summaries; `you` read by the sweep): a sample of a fight (spawning, wave,
-- fighting) in the air: your height (its histogram), high (high.over_m over the enemy fighters within high.near_km by
-- their last sample, none near: above high.alone_m), near the airfield (airfield.km of the runway), on an enemy's tail
-- (CFG.stats tail_km / tail_deg of its six, from where you were at its sample, p.youAt); and your landings. Cached
-- fields only: no reads.
function PROF.sample(now, you)
    if not (pon() and D and now and you and you.Z) then return end
    local h = habit()
    if h.sampleAt and now - h.sampleAt < 1.5 then return end      -- (a pause: the round clock stands still)
    h.sampleAt = now
    local ground = playerOnAirfield(you)
    if h.wasGround == false and ground then h.landings = h.landings + 1 end
    h.wasGround = ground
    if ground or not (D.state == "spawning" or D.state == "wave" or D.state == "fighting") then return end
    h.S = h.S + 1
    local m = you.Z / 100
    local b = math.max(0, math.min(ALT_BINS, math.floor(m / ALT_BIN)))
    h.alt[b] = (h.alt[b] or 0) + 1
    local hc, sc = hcfg("high"), CFG.stats or {}
    local nearKm, tkm, tdeg = num(hc.near_km, 15), (sc.tail_km or 3) * 100000, sc.tail_deg or 70
    local sum, n, tailing = 0, 0, false
    for _, p in ipairs(planes or {}) do
        if not p.down and p.at and p.dist and p.dist <= nearKm and not (p.unit and BOMBER_UNIT[p.unit]) then
            sum, n = sum + p.at.Z / 100, n + 1
            local me = p.youAt or you
            if not tailing and p.fwd then
                local dx, dy, dz = me.X - p.at.X, me.Y - p.at.Y, me.Z - p.at.Z
                tailing = math.sqrt(dx * dx + dy * dy + dz * dz) <= tkm and angle(-p.fwd.X, -p.fwd.Y, -p.fwd.Z, dx, dy, dz) <= tdeg
            end
        end
    end
    if (n > 0 and m >= sum / n + num(hc.over_m, 1000)) or (n == 0 and m >= num(hc.alone_m, 5000)) then h.Sh = h.Sh + 1 end
    local dx, dy = you.X - AIRFIELD.X, you.Y - AIRFIELD.Y
    if math.sqrt(dx * dx + dy * dy) / 100000 <= num(hcfg("airfield").km, 8) then h.Sa = h.Sa + 1 end
    if tailing then h.St = h.St + 1 end
end

---------------------------------------------------------------------------------------------------- the counters
-- The round's counters (startRound, the host's or solo, before its strike, jammer and fighter picks): each habit's
-- share now (current: this run's and the saved profile's), its strength, and what that does (D.counter); one line a
-- round with the raw shares next to every decision (the thresholds and gains are guesses until test logs exist).
function PROF.weights(round)
    if not D then return end
    D.counter = nil
    if not pon() or client() then return end
    local h, sv = habit(), PROF.saved
    local hab = habitsOf(current(h, sv))
    local st = {}
    for _, k in ipairs(HABITS) do st[k] = strength(k, hab[k]) end
    local ctr = { round = round, habits = hab, strength = st, roleW = {} }
    for _, r in ipairs(ROLE.LIST) do ctr.roleW[r] = 1 end
    for hn, roles in pairs(ROLE_GAIN) do
        for _, r in ipairs(roles) do ctr.roleW[r] = ctr.roleW[r] + math.max(0, num(hcfg(hn)[r], 0)) * st[hn] end
    end
    local parts = {}
    if st.missile > 0 then
        local c, jc = hcfg("missile"), CFG.jammer or {}
        ctr.jammerX = 1 + math.max(0, num(c.jammer_x, 0)) * st.missile
        ctr.rank, ctr.rankFrom = math.max(0, math.floor(num(c.rank_add, 0))), tierAt(c.rank_from)
        parts[#parts + 1] = string.format("the jammer's chance %.2f -> %.2f", num(jc.chance, 0),
            chanceWith(num(jc.chance, 0), ctr.jammerX, c.jammer_max))
        if ctr.rank > 0 then
            parts[#parts + 1] = ctr.rankFrom and string.format("PilotRank +%d from %s", ctr.rank, CFG.tiers.list[ctr.rankFrom].name)
                or string.format("PilotRank: no tier %s (rank_from)", tostring(c.rank_from))
        end
        parts[#parts + 1] = PROF.flareWant and "the AI's flares refilled (this session's)"
            or "the AI's flares stock this session (from the next one)"
    end
    if st.gun > 0 then
        local c = hcfg("gun")
        ctr.postStallFrom = tierAt(c.post_stall_from)
        parts[#parts + 1] = ctr.postStallFrom and ("post-stall on every airframe from " .. CFG.tiers.list[ctr.postStallFrom].name)
            or string.format("post-stall: no tier %s (post_stall_from)", tostring(c.post_stall_from))
    end
    if st.tail > 0 then
        ctr.tail = math.max(0, num(hcfg("tail").budget_x, 0)) * st.tail
        parts[#parts + 1] = string.format("cover and trap x%.2f", 1 + ctr.tail)
    end
    if st.high > 0 then                                -- (your usual height: this run's once it has live_samples)
        local alt = h.S >= num(pcfg().live_samples, 30) and altMedian(h) or (sv and (sv.learnt or 0) > 0 and sv.alt_m) or nil
        if alt then
            ctr.lancerAlt = alt + num(hcfg("high").above_m, 0)
            parts[#parts + 1] = string.format("Lancers from %.1f km up (your usual %.1f km)", ctr.lancerAlt / 1000, alt / 1000)
        else
            parts[#parts + 1] = "Lancers' height: yours not known yet"
        end
    end
    if st.airfield > 0 then
        local c, sk = hcfg("airfield"), CFG.strike or {}
        ctr.strikeX = 1 + math.max(0, num(c.strike_x, 0)) * st.airfield
        parts[#parts + 1] = string.format("the strike's chance %.2f -> %.2f", num(sk.chance, 0),
            chanceWith(num(sk.chance, 0), ctr.strikeX, c.strike_max))
    end
    local rw = {}
    for _, r in ipairs(ROLE.LIST) do if ctr.roleW[r] ~= 1 then rw[#rw + 1] = string.format("%s x%.2f", r, ctr.roleW[r]) end end
    if #rw > 0 then
        parts[#parts + 1] = "role mix " .. table.concat(rw, ", ") .. (ROLE.live and "" or " (roles off: no effect)")
    end
    D.counter = ctr
    local hp = {}
    for _, k in ipairs(HABITS) do
        hp[#hp + 1] = string.format("%s %s%s", k, f2(hab[k]), st[k] > 0 and string.format(" (over %s, strength %.2f)",
            f2(num(hcfg(k).threshold, 1)), st[k]) or "")
    end
    log(string.format("learning: round %d: habits %s (this run %d of your kills, %d s flown; the profile %s) -> %s", round,
        table.concat(hp, ", "), h.K, h.S * 2,
        sv and string.format("%d runs, %d learnt from", sv.runs or 0, sv.learnt or 0) or "none",
        #parts > 0 and table.concat(parts, ", ") or "nothing to counter"))
end

local function counter()                           -- the round's counters on the host or solo (nil on a co-op joiner)
    local c = D and D.counter
    if c == nil or client() then return nil end
    return c
end
-- kind "jammer" / "strike": that pick's chance, base, with the round's counter (missile / airfield habit) on it
function PROF.chance(kind, base)
    local c = counter()
    if not (c and type(base) == "number") then return base end
    if kind == "jammer" then return chanceWith(base, c.jammerX, hcfg("missile").jammer_max) end
    if kind == "strike" then return chanceWith(base, c.strikeX, hcfg("airfield").strike_max) end
    return base
end
-- PilotRank to add to a plane of tier index ti (enemyTier): the missile habit's rank_add from rank_from up
function PROF.rankAdd(ti)
    local c = counter()
    if not (c and c.rank and c.rank > 0 and c.rankFrom and type(ti) == "number" and ti >= c.rankFrom) then return 0 end
    return c.rank
end
-- post-stall on for a plane of tier t (enemyManeuvers; a CFG.tiers.list entry or its index): the gun habit's
function PROF.postStall(t)
    local c = counter()
    local ti = type(t) == "number" and t or tierIndex(t)
    return c ~= nil and c.postStallFrom ~= nil and ti ~= nil and ti >= c.postStallFrom
end
-- the round's role weights ({ role = x }: ROLE.pickRound multiplies the mix's by them) or nil
function PROF.roleW() local c = counter(); return c and c.roleW or nil end
-- the Lancers' spawn height (m) above your usual one (the high habit), or nil
function PROF.lancerAlt() local c = counter(); return c and c.lancerAlt or nil end

---------------------------------------------------------------------------------------------------- the file
-- config/survival_profile.ini: [profile] (version, runs counted, runs learnt from, your kills, the six shares, your
-- usual height) and, while a run is on, [run] (its id and counts at its last round's end). Read with io (never
-- loaded as code): known keys only, every value a number clamped to its range; anything else is skipped.
local INT_MAX = { version = 1000, runs = 1e9, learnt = 1e9, kills = 1e9 }
local function parse(text)
    local sv, run, sec, ver, skipped = neutral(), nil, "profile", nil, 0
    sv.version = nil
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local l = raw:gsub(";.*$", ""):match("^%s*(.-)%s*$")
        if l ~= "" then
            local s = l:match("^%[%s*(.-)%s*%]$")
            if s then
                sec = s:lower()
                if sec == "run" then run = run or {} end
            else
                local k, v = l:match("^([%w_]+)%s*=%s*(.-)$")
                local x = tonumber(v)
                if x and (x ~= x or x == math.huge or x == -math.huge) then x = nil end
                local ok = false
                if k and sec == "profile" then
                    if k == "version" and x then ver, ok = math.floor(x), true
                    elseif INT_MAX[k] and x then sv[k], ok = math.max(0, math.min(INT_MAX[k], math.floor(x))), true
                    elseif k == "alt_m" and x then sv.alt_m, ok = math.max(0, math.min(20000, x)), true
                    else
                        for _, p in ipairs(PARTS) do
                            if k == p and x then sv[k], ok = math.max(0, math.min(1, x)), true end
                        end
                    end
                elseif k and sec == "run" then
                    if k == "id" and v:match("^%x+$") and #v <= 16 then run.id, ok = v, true
                    elseif k == "alt_m" and x then run.alt_m, ok = math.max(0, math.min(20000, x)), true
                    else
                        for _, p in ipairs(RUN_KEYS) do
                            if k == p and x then run[k], ok = math.max(0, math.min(1e7, math.floor(x))), true end
                        end
                    end
                end
                if not ok then skipped = skipped + 1 end
            end
        end
    end
    return sv, run, ver, skipped
end
local function render(sv, h)
    local L = { "; AC8 Survival Mode: how you fly, learnt from your runs (the learning layer: [profile] in survival.ini).",
                "; Written by the game at each run's end; delete this file to start over. Yours only: never sent, never",
                "; shared in co-op.", "[profile]", "version = " .. FORMAT,
                string.format("runs = %d", sv.runs or 0), string.format("learnt = %d", sv.learnt or 0),
                string.format("kills = %d", sv.kills or 0) }
    for _, k in ipairs(PARTS) do if sv[k] then L[#L + 1] = string.format("%s = %.4f", k, sv[k]) end end
    if sv.alt_m then L[#L + 1] = string.format("alt_m = %d", math.floor(sv.alt_m + 0.5)) end
    local hb, t = habitsOf(sv), {}
    for _, k in ipairs(HABITS) do t[#t + 1] = k .. " " .. f2(hb[k]) end
    L[#L + 1] = "; habits: " .. table.concat(t, ", ")
    if h then
        L[#L + 1] = "[run]"
        L[#L + 1] = "; the run on now (at its last round's end): learnt from at its end, or at the next start if the game closed"
        L[#L + 1] = "id = " .. h.id
        for _, k in ipairs(RUN_KEYS) do L[#L + 1] = string.format("%s = %d", k, math.floor(num(h[k], 0))) end
        local alt = altMedian(h)
        if alt then L[#L + 1] = string.format("alt_m = %d", math.floor(alt + 0.5)) end
    end
    return table.concat(L, "\n") .. "\n"
end
-- written whole: <file>.tmp, then the old one removed and the new one moved in (as survival.ini's update)
local function write(sv, h)
    local p = filePath()
    local f = io.open(p .. ".tmp", "w")
    if not f then
        if not wrote.said then wrote.said = true; log("learning: can't write config\\" .. FILE .. ": the profile stays this session's") end
        return false
    end
    f:write(render(sv, h))
    f:close()
    os.remove(p)
    local ok, err = os.rename(p .. ".tmp", p)
    if not ok and not wrote.said then wrote.said = true; log("learning: " .. FILE .. " not moved in: " .. tostring(err)) end
    return ok and true or false
end

-- run h (this run's counts, or an unfinished one's from the file) into profile sv: its runs and kills always; its
-- shares (each weighed by its evidence: K / (K + fold_kills), S / (S + fold_samples), at most run_weight_max; the first
-- run learnt from: its own) when it has min_kills of your kills and started at round 1. nil, or why it wasn't learnt.
local function foldInto(sv, h, from)
    local c = pcfg()
    sv.runs, sv.kills = (sv.runs or 0) + 1, (sv.kills or 0) + h.K
    local minK = num(c.min_kills, 8)
    if h.K < minK then return string.format("only %d of your kills, min_kills %d", h.K, minK) end
    if (from or 1) > 1 then return string.format("a head start at round %d", from) end
    local s, first = runShares(h), (sv.learnt or 0) == 0
    local maxW = math.max(0, math.min(1, num(c.run_weight_max, 0.5)))
    local function w(ev, fold) return math.min(maxW, ev / (ev + math.max(1, fold))) end
    for _, k in ipairs(PARTS) do
        local x = s[k]
        if x ~= nil then
            local a = BY_KILL[k] and w(h.K, num(c.fold_kills, 30)) or w(h.S, num(c.fold_samples, 300))
            if first or sv[k] == nil then sv[k] = x else sv[k] = (1 - a) * sv[k] + a * x end
        end
    end
    local alt = altMedian(h)
    if alt then
        local a = w(h.S, num(c.fold_samples, 300))
        if first or not sv.alt_m then sv.alt_m = alt else sv.alt_m = (1 - a) * sv.alt_m + a * alt end
    end
    sv.learnt = (sv.learnt or 0) + 1
    return nil
end
local function profileText(sv)
    local hb, t = habitsOf(sv), {}
    for _, k in ipairs(HABITS) do t[#t + 1] = k .. " " .. f2(hb[k]) end
    return string.format("%d runs (%d learnt from), %d of your kills; %s%s", sv.runs or 0, sv.learnt or 0, sv.kills or 0,
        table.concat(t, ", "), sv.alt_m and string.format(", your usual height %.1f km", sv.alt_m / 1000) or "")
end
local function runText(h)
    local s, t = habitsOf(runShares(h)), {}
    for _, k in ipairs(HABITS) do t[#t + 1] = k .. " " .. f2(s[k]) end
    local alt = altMedian(h)
    return string.format("%d of your kills (missiles %d, gun %d, of %d with a weapon seen; close %d, from behind %d, of %d " ..
        "with an aspect), %d s flown (high %s, near the airfield %s, on a tail %s%s), %d landings: %s", h.K, h.Km, h.Kg, h.Kw,
        h.Kc, h.Kb, h.Kgeo, h.S * 2, share(h.Sh, h.S), share(h.Sa, h.S), share(h.St, h.S),
        alt and string.format(", usually %.1f km up", alt / 1000) or "", h.landings or 0, table.concat(t, ", "))
end

-- The profile from its file (where: "the main menu", "level load"). A [run] left in it (the game closed mid-run) is
-- learnt from first, once a session. A missing, broken or other-format file: a neutral profile and a line, never an
-- error (hard rule 50). save off: no profile (each run on its own).
function PROF.load(where)
    PROF.saved = nil
    if not pon() then return end
    if pcfg().save == false then log("learning: [profile] save off: each run learns on its own"); return end
    local f = io.open(filePath(), "r")
    if not f then
        PROF.saved = neutral()
        log(string.format("learning: profile at %s: none yet (config\\%s is made at your first run's end)", where, FILE))
        return
    end
    local text = f:read("a") or ""
    f:close()
    local okP, sv, run, ver, skipped = pcall(parse, text)
    if not okP then sv, run, ver, skipped = nil, nil, nil, 0 end
    if not (sv and ver == FORMAT) then
        PROF.saved = neutral()
        log(string.format("learning: profile at %s: config\\%s %s: starting from a neutral profile (it's written anew at " ..
            "this run's end)", where, FILE, not okP and "not readable" or (ver and ("is format " .. ver .. ", not " .. FORMAT))
            or "has no version line"))
        return
    end
    local extra = ""
    local cur = RUN and RUN.habit
    if run and run.id and not seen[run.id] and not (cur and cur.id == run.id) then
        seen[run.id] = true
        local h = newHabit()
        for _, k in ipairs(RUN_KEYS) do h[k] = run[k] or 0 end
        h.id, h.alt, h.altM = run.id, nil, run.alt_m
        local why = foldInto(sv, h, run.from or 1)
        write(sv, nil)
        extra = string.format("; the run the game closed in (round %d, %d of your kills) %s first", run.round or 0, h.K,
            why and ("counted, not learnt from (" .. why .. ")") or "learnt from")
    end
    PROF.saved = sv
    log(string.format("learning: profile at %s from config\\%s: %s%s%s", where, FILE, profileText(sv), extra,
        skipped > 0 and string.format("; %d lines skipped", skipped) or ""))
end
function PROF.levelLoad() PROF.load("level load") end

-- The main menu, once a session (sv_main.lua, before the NPC rows are made): the profile, and whether this session's
-- fighters get the refilled flare row (CFG.flares: the saved profile missile-heavy, or always): PROF.flareWant
function PROF.menu()
    PROF.menuDone = true
    PROF.load("the main menu")
    PROF.flareWant = nil
    local f = CFG.flares
    if not (type(f) == "table" and f.enabled) then log("learning: the AI's flares stay stock this session ([flares] off)"); return end
    local sv = PROF.saved
    local x = (sv and (sv.learnt or 0) > 0) and sv.missile or nil
    local s = pon() and strength("missile", x) or 0
    if f.always or s > 0 then
        PROF.flareWant = { magazine = math.max(1, math.min(999, math.floor(num(f.magazine, 20)))),
                           reload_s = math.max(0.5, math.min(120, num(f.reload_s, 8))) }
        log(string.format("learning: the AI's flares refilled this session (%s): %d in the magazine, %.1f s to reload",
            f.always and "[flares] always" or string.format("your saved missile share %s, over %s", f2(x),
            f2(num(hcfg("missile").threshold, 1))), PROF.flareWant.magazine, PROF.flareWant.reload_s))
    else
        log(string.format("learning: the AI's flares stay stock this session (your saved missile share %s; its threshold %s)",
            f2(x), f2(num(hcfg("missile").threshold, 1))))
    end
end

-- A round's end (STATS.roundEnd): the run so far into the file's [run], once for each round (checkpoint)
function PROF.checkpoint()
    local c, h = pcfg(), RUN and RUN.habit
    if not (pon() and h and D) or h.folded or c.save == false or c.checkpoint == false then return end
    local key = string.format("%d|%d|%d", D.round or 0, h.K, h.S)
    if h.cpKey == key or (h.K == 0 and h.S == 0) then return end
    h.cpKey, h.round, h.from = key, D.round or 0, D.startRound or 1
    write(PROF.saved or neutral(), h)
end

-- The run's over (STATS.runEnd; how: died, restart, left, the host started over): learnt into the profile, written
-- ([run] gone). Not a run with nothing flown (no kill, no sample). save off: its habits logged only.
function PROF.fold(how)
    local h = RUN and RUN.habit
    if not (pon() and h) or h.folded then return end
    h.folded = true
    seen[h.id] = true
    if h.K == 0 and h.S == 0 then return end
    if pcfg().save == false then
        log(string.format("learning: run over (%s): %s; not saved ([profile] save off)", tostring(how), runText(h)))
        return
    end
    local sv = PROF.saved or neutral()
    local why = foldInto(sv, h, D and D.startRound or 1)
    PROF.saved = sv
    local ok = write(sv, nil)
    log(string.format("learning: run over (%s): %s; %s; the profile now %s%s", tostring(how), runText(h),
        why and ("counted, not learnt from (" .. why .. ")") or "learnt from", profileText(sv),
        ok and (", saved to config\\" .. FILE) or ", NOT saved"))
end

-- A co-op host's new run while this game's level goes on (STATS.hostReset): this one's over, the next starts empty
function PROF.newRun(why)
    if RUN and RUN.habit then
        PROF.fold(why)
        RUN.habit = nil
    end
end

-- (for tools/checks/profile_test.lua: the maths above, unchanged)
PROF.runShares, PROF.habitsOf, PROF.current, PROF.strength, PROF.parse, PROF.render = runShares, habitsOf, current,
    strength, parse, render
end
end
