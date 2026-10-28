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
-- Logged only (AC8SurvivalMode_lua.log), never sent: friends' release logs are the test data, so none of this is in a
-- test-only or online-only block, and the leaderboard's JSON keeps its fixed fields. The time base is D.now, the game
-- clock (it stops in a pause). Per plane on its record (hard rule 16: flights are recycled), per round in D.rs, per run
-- in RUN.metrics. Each plane is seen every 2 s, so every time here is good to about +/- 2 s.
STATS = {}
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
            local at, fwd = fresh(p)
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
end
