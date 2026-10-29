-- sv_ai.lua: enemy pilots: tiers, kill log, ace hunting, kill pay.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- Question 2: PilotRank on each enemy (p from the plane list), called every 2 s while it is up.
-- CFG.tiers: this enemy's tier (by the round, sometimes one higher) and PilotRank, set once when it is first seen up.
enemyTier = nil
do
local tierSaid = {}
function enemyTier(p, round, flightTier)
    local tc = CFG.tiers
    if p.tier ~= nil or not tc.enabled or not round then return end
    local i = flightTier or TIER.pick(round)                 -- a fighter flight's was picked at its spawn
    local t = tc.list[i]
    p.tier = t
    local add = (tc.rank_add[presetName()] or 0) + SETUP.skillAdd()   -- (+ the menu's ENEMY SKILL, sv_menu.lua)
    local want = math.max(1, math.min(5, t.rank + add, 5))
    if PROF and PROF.rankAdd then                            -- (a missile-heavy player: more flares, P6's learning layer)
        local okH, h = pcall(PROF.rankAdd, i)
        if okH and type(h) == "number" and h > 0 then want = math.min(5, want + h) end
    end
    p.rankBase = want                                        -- (before the spike's rank_min: P4 writes it again live)
    local sk = spikeCfg(levelFor(round))                    -- (the spike's, or the intensity director's under it)
    if sk.rank_min then want = math.max(want, math.min(5, sk.rank_min)) end
    local ok0, r0 = pcall(function() return p.obj.PilotRank end)
    local okW, err = pcall(function() p.obj.PilotRank = want end)
    p.rankSet = want                                         -- (the jammer's boost goes back to this: JAM.tick)
    local key = round .. t.name
    if not tierSaid[key] or not okW then
        tierSaid[key] = true
        local lv = ""
        if t.ai_level and type(SV_PlaneLevel) == "function" then     -- the AI level the plane took from its desc
            local okL, l = pcall(function() return SV_PlaneLevel(addrOf(p.obj)) end)
            lv = string.format(", AI level %s (wanted %d)", okL and tostring(l) or "?", t.ai_level * 100)
        end
        log(string.format("tiers: round %d %s (%s): PilotRank %s -> %d%s%s", round, t.name, p.name, ok0 and tostring(r0) or "?",
            want, lv, okW and "" or (" (write failed: " .. tostring(err) .. ")")))
    end
end
end

-- CFG.maneuvers: post-stall permission for this enemy (p from the plane list), set once when it is first seen up:
-- its model must be listed and its tier (enemyTier, run first) must allow post-stall at all.
-- The first plane of each model logs what its blueprint had and what it reads after the write.
enemyManeuvers = nil
do
local maneuversSaid = {}
function enemyManeuvers(p, round)
    if p.maneuvers or not CFG.maneuvers.enabled then return end
    p.maneuvers = true
    local model = p.name:match("^BP_OP%d+_(%w+)_") or "?"
    local allow = false
    for _, m in ipairs(CFG.maneuvers.post_stall) do if m == model then allow = true end end
    if p.tier and not p.tier.post_stall then allow = false end
    local all = spikeCfg(levelFor(round)).post_stall_all        -- a difficulty spike: every airframe
    local fl = p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]
    if fl and fl.post_stall then all = true end                    -- (a top tier: on, whatever its blueprint)
    if PROF and PROF.postStall then                                -- (a gun / close-fight player: P6's learning layer)
        local okH, on = pcall(PROF.postStall, p.tier)
        if okH and on then all = true end
    end
    local function read()
        local okC, c = pcall(function() return p.obj.bCanManeuverPugachevsCobra end)
        local okK, k = pcall(function() return p.obj.bCanManeuverKulbit end)
        return string.format("cobra %s, kulbit %s", okC and tostring(c) or "?", okK and tostring(k) or "?")
    end
    local before = read()
    local ok, err = true, nil
    if all then
        allow = true
        ok, err = pcall(function()
            p.obj.bCanManeuverPugachevsCobra = true
            p.obj.bCanManeuverKulbit = true
        end)
    elseif not allow then                   -- allowed models keep their blueprint's own (test 18: su33 cobra only)
        ok, err = pcall(function()
            p.obj.bCanManeuverPugachevsCobra = false
            p.obj.bCanManeuverKulbit = false
        end)
    end
    local said = model .. (allow and "+" or "-") .. (all and "!" or "")
    if not maneuversSaid[said] then
        maneuversSaid[said] = true
        log(string.format("maneuvers: %s (%s) post-stall %s: was %s, now %s%s", model, p.name, allow and "allowed" or "off",
            before, read(), ok and "" or (" (write failed: " .. tostring(err) .. ")")))
    end
end
end

-- Kill log (for the learning layer later): every 2 s while an enemy is up its heading is kept, and when it goes down
-- the player's aspect, altitude and recent ammo use are logged. (K2_GetLastDamagedByAttacker never named anyone.)
function probeTrack(p)
    pcall(function() local f = p.obj:GetActorForwardVector(); p.fwd = { X = f.X, Y = f.Y, Z = f.Z } end)
end

local AMMO_SHORT = { [0] = "gun", "msl", "sp1", "sp2", "flr" }

-- AI watch (CFG.ai_watch; user, 2026-10-22: "they fly towards the airfield instead of targeting the player"): every
-- 2 s each enemy's AI state (blackboard key AIState, ELiveAIState) and target (blackboard key TargetActor), logged
-- when either changes ([log] verbose), with its distance to the player and to the airfield. (AIStateComponent.LuaAssets
-- is not the set in use: it read LA_MoveAwayFromTarget_0000 on planes whose set was built with LA_SV_MoveAway.)
-- (a global: sv_stats.lua's tail watch names the states it reads with it)
AI_STATE = { [0] = "ReturnToWorld", "AvoidObstacle", "AvoidRangeAttack", "Wingman", "ReturnToUnit", "AttackAvoidance",
             "EscapeFromPursuer", "Blackout", "Provoke", "MoveAwayFromTarget", "PursueTarget", "FollowFormation",
             "Group", "Patrol", "UniqueAction", "CloudAvoidance", "Idle" }
-- Both are read every time, the log on or off (coop-perf step 10), and kept for later parts: p.aiState, and p.aiTarget /
-- p.aiTargetAddr (the object it's after and its address, for COOP.slotOfAddr; nil for none). The measurements time
-- Provoke episodes from the state (CFG.stats: STATS.aiState, sv_stats.lua); the target's name (nameOf) only for the log.
function aiWatch(p, you)
    local st, read, tobj = "?", false, nil
    pcall(function()
        local bb = p.obj.AIStateComponent.BlackboardComponent
        local okS, v = pcall(function() return bb:GetValueAsEnum(FName("AIState")) end)
        if okS and type(v) == "number" then st = AI_STATE[v] or tostring(v) end
        local okT, t = pcall(function() return bb:GetValueAsObject(FName("TargetActor")) end)
        if okT then read = true; if valid(t) then tobj = t end end
    end)
    if st ~= "?" then p.aiState = st end
    if read then p.aiTarget, p.aiTargetAddr = tobj, tobj and addrOf(tobj) or nil end
    if CFG.stats and CFG.stats.enabled then pcall(STATS.aiState, p, st, D and D.now) end
    if not (CFG.ai_watch and logVerbose()) then return end    -- (the "ai:" lines: [log] verbose, the clean up of 2026-10-29)
    local tgt = (not read and "?") or (tobj and (nameOf(tobj):match("([^%.:]+)$") or "?")) or "none"
    if st .. "|" .. tgt == p.aiKey then return end
    p.aiKey = st .. "|" .. tgt
    local air = p.at and math.sqrt((p.at.X - AIRFIELD.X) ^ 2 + (p.at.Y - AIRFIELD.Y) ^ 2) / 100000
    log(string.format("ai: %s (%s) %s, target %s; %s km from you, %s km from the airfield", p.name, tostring(p.unit or "?"),
        st, tgt, (p.at and you) and string.format("%.1f", km(p.at, you)) or "?", air and string.format("%.1f", air) or "?"))
end

-- A fighter role flight (CFG.roles: a Lancer, Wolf or Skirmisher flight, not a squadron's of a tier with these levers)
-- flies its own set's provoke and pursuit: its tier's no_provoke and moves leave it alone (ROLE.ownSet, sv_spawn.lua;
-- logged once a round)
local function roleOwn(p)
    if not (p.unit and ROLE.ownSet and ROLE.ownSet(p.unit, p.tier)) then return false end
    if D and D.roleOwnSaid ~= nil and D.roleOwnSaid[p.unit] == D.round then return true end
    if D then
        D.roleOwnSaid = D.roleOwnSaid or {}
        D.roleOwnSaid[p.unit] = D.round
        log(string.format("aces: %s (%s) keeps its role's own provoke and pursuit (the %s tier's no_provoke / moves are for "
            .. "duelists and ace squadrons)", p.unit, tostring(ROLE.flight(p.unit)), p.tier and p.tier.name or "?"))
    end
    return true
end

-- CFG.aces.flight <tier>.hunt: that tier's aircraft keep the player as their target (blackboard TargetActor)
function ACE.hunt(p)
    local fl = p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]   -- (its tier's)
    if not (fl and fl.hunt) then return end
    if TELL and TELL.hunted then pcall(TELL.hunted, p) end    -- (its flight close: the "hunt" tell, CFG.tells hunt_km)
    if fl.no_provoke and not roleOwn(p) then    -- (every 2 s: an engagement order sets it again)
        pcall(function() if p.obj.bPermissionToProvoke then p.obj.bPermissionToProvoke = false end end)
        if not p.noProvokeSaid then
            p.noProvokeSaid = true
            local okR, v = pcall(function() return p.obj.bPermissionToProvoke end)
            log(string.format("aces: %s won't defend when tailed (bPermissionToProvoke %s)", p.name, okR and tostring(v) or "?"))
        end
    end
    if DIR and DIR.aimed and DIR.aimed(p) then return end    -- (the squad director keeps it on a co-op joiner for now)
    if ANOM and ANOM.packHeld and ANOM.packHeld(p) then return end   -- (a PHANTASM guard till its pack springs: P7, off by default)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return end
    local bb = p.obj.AIStateComponent.BlackboardComponent
    local okT, t = pcall(function() return bb:GetValueAsObject(FName("TargetActor")) end)
    if okT and valid(t) and nameOf(t) == nameOf(pawn) then return end
    local ok = pcall(function() bb:SetValueAsObject(FName("TargetActor"), pawn) end)
    p.huntN = (p.huntN or 0) + 1
    if p.huntN == 1 or p.huntN % 30 == 0 then
        log(string.format("aces: %s back onto you (was %s)%s, %d times", p.name, okT and valid(t) and (nameOf(t):match("([^%.:]+)$") or "?") or "none",
            ok and "" or " (write failed)", p.huntN))
    end
end

-- Top-tier reversals (CFG.aces.flight <tier>.moves) and their geometry helpers
do
local function deg(a, b)                           -- the angle between two vectors, degrees
    local la = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
    local lb = math.sqrt(b.X * b.X + b.Y * b.Y + b.Z * b.Z)
    if la == 0 or lb == 0 then return 0 end
    return math.deg(math.acos(math.max(-1, math.min(1, (a.X * b.X + a.Y * b.Y + a.Z * b.Z) / (la * lb)))))
end
local function vec(v) return { X = v.X, Y = v.Y, Z = v.Z } end
-- CFG.aces.flight <tier>.moves: the reversals (RE_SV_AceTurn_NN / RE_SV_AceKulbit_NN on the plane's pool flight)
function ACE.movesTick(now, D)
    -- (not on a co-op joiner: its enemies are copies of the host's, moved every frame, whose reversals the host makes
    -- and the plane stream shows; fired here they'd only put a copy in UniqueAction, and the kulbit fires its special.
    -- Nor before the round clock runs: now nil)
    if COOP and COOP.client and COOP.client() then return end
    if not (now and D and D.round and type(SV_Event) == "function") then return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return end
    local me
    D.aceMoveAt = D.aceMoveAt or {}
    for _, p in ipairs(planes) do
        local fl = not p.down and p.unit and p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]
        -- (not a flight the squad director holds back: its top cover or regroup, sv_director.lua)
        if fl and fl.moves and now >= (D.aceMoveAt[p.unit] or 0) and valid(p.obj) and not roleOwn(p)
            and not (DIR and DIR.holding and DIR.holding(p.unit)) then
            local pn, pk = p.unit:match("^ERA_Unit_(%d+)_Dep_Air(%d)$")
            if pn then
                if not me then                      -- (your position as read once this tick: sv_coop.lua COOP.me)
                    local L = COOP and COOP.me and COOP.me()
                    me = (L and L.at) or vec(pawn:K2_GetActorLocation())
                end
                local at, fwd = vec(p.obj:K2_GetActorLocation()), vec(p.obj:GetActorForwardVector())
                local toMe = { X = me.X - at.X, Y = me.Y - at.Y, Z = me.Z - at.Z }
                local range = km(at, me) * 1000
                local offTail = deg({ X = -fwd.X, Y = -fwd.Y, Z = -fwd.Z }, toMe)
                if range <= 3000 and offTail <= 70 then
                    local kulbit = range <= 900
                    local ev = string.format("RE_SV_%s_%02d", kulbit and "AceKulbit" or "AceTurn", (tonumber(pn) - 1) * 3 + tonumber(pk) + 1)
                    local tell = kulbit and "kulbit" or "reversal"
                    -- (its next no sooner than this one's over, counted from the move, its tell's lead_s on: a reversal's
                    -- LastTGT takes ~25-30 s and a new request cuts it, so the squad director's cover turn (cover.move_s,
                    -- through the same D.aceMoveAt) and the next reversal wait it out; the kulbit is a short OneShot)
                    local okL, ld = pcall(function() return TELL and TELL.leadS and TELL.leadS(tell) end)
                    local cv = CFG.director and CFG.director.cover
                    D.aceMoveAt[p.unit] = now + (okL and tonumber(ld) or 0) + (kulbit and 12 or (tonumber(cv and cv.move_s) or 30))
                    D.aceMoves = (D.aceMoves or 0) + 1
                    local n, name = D.aceMoves, p.name
                    local function go()
                        local r = SV_Event(ev)
                        if n <= 5 or n % 20 == 0 then
                            log(string.format("aces: %s has you %.0f m behind it, %.0f deg off its tail: %s (%s), %d so far", name,
                                range, offTail, ev, tostring(r), n))
                        end
                    end
                    -- its tell first (behaviour roadmap P3, CFG.tells reversal / kulbit: the radio call), the move its
                    -- lead_s after (TELL.after); no tell said (or tells off): the move at once, as before
                    local said = false
                    if TELL and TELL.after then said = TELL.after(tell, nil, go) else go() end
                    pcall(STATS.tactic, "reversal", p.unit, nil, string.format("%.0f m, %.0f deg", range, offTail), said and tell or nil)
                end
            end
        end
    end
end

end

---------------------------------------------------------------------------------------------------- ace personalities
-- The named squadrons' personalities (behaviour roadmap P9: "Bounty fights as Lancers, Valkyrie as a Wolf pack, Inferno
-- as Duelists with post-stall, Wraith blinks like a lesser AB.L..IN, Harvest combines all of them. Each squadron should
-- be recognisable within 10 seconds"; tools/re/BEHAVIOUR_DIRECTOR.md unit 10; CFG.aces.personality and CFG.aces.flight
-- <tier>.roles / openers / blink). The behaviour pipeline's recipe c1: a squadron flies the behaviour set of the role
-- flights its ace round draws (ROLE.mixFor; a tree is its desc's, hard rule 20), and the rest is what Lua fires on it:
-- one opener per flight at first contact, after its tell, and a Wraith (or Harvest) lead blinking off your six (Mission
-- 22's teleport, hard rule 39: RE_SV_WraithBlink<K><J>, ACE.BLINK). A squadron's flights only (D.aceSquad: never its
-- tier's ordinary ones), the host's (or solo): a joiner's copies are moved by the plane stream.
--   ACE.pickOpener(unit, tk, role)   spawnFlight, before the spawn: the opener this squadron flight shows (its tier's
--                                    openers in turn; a blink only where its lead has blink events; none fits: kulbit;
--                                    openers "none": nil, the squadron's tell alone at first contact)
--   ACE.highAlt(alt)                 spawnFlight: a "high" flight's altitude off a Lancer flight (+ alt_add_m, top_m)
--   ACE.squadUp(unit, ace, role, n)  spawnFlight: a flight is up (a squadron's waits for first contact; any other flight
--                                    clears what a recycled one had)
--   ACE.blinkEvent(unit, j)          flight unit's lead's blink to bearing j (0 = A), or nil (no events for it)
--   ACE.squadTick(now, D, paused)    every 250 ms (sv_main.lua, timed "squads", before ACE.movesTick): first contacts,
--                                    the openers, the blinks
do
local OPEN_TELL = { high = "dive", trap = "drag", kulbit = "kulbit", blink = "blink" }   -- (a later flight's own tell)
local KNOWN = { high = true, trap = true, kulbit = true, blink = true }
local SCAN_S = 0.5                                   -- (first contacts looked for this often: p.at is the 2 s sweep's)
local function pc() local c = CFG.aces.personality; return type(c) == "table" and c or {} end
local function on() local c = CFG.aces.personality; return CFG.aces.enabled and type(c) == "table" and c.enabled ~= false end
local function oc(op) local o = pc().openers; o = type(o) == "table" and o[op]; return type(o) == "table" and o or {} end
local function fcfg(tk) local f = CFG.aces.flight and CFG.aces.flight[tk]; return type(f) == "table" and f or {} end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function client() return (COOP and COOP.client and COOP.client()) and true or false end
local function squadName(tk) local a = CFG.aces[tk]; return tostring(type(a) == "table" and a.squadron or tk) end
local function who(e) return (not e or e.isMe or not (COOP and COOP.open)) and "you" or string.format("player %d", (e.slot or 0) + 1) end
local function fire(ev)                              -- (SV_Event by name at run time: sv_coop wraps it, KEEP_EVENTS)
    local ok, r = pcall(function() return type(SV_Event) == "function" and SV_Event(ev) or -5 end)
    if not ok then return "error " .. tostring(r), false end
    if r == 1 then return "fired", true end
    return "not fired: " .. tostring(SV_ERR and SV_ERR[r] or r), false
end
local function alive(u)
    local ok, n = pcall(SV_UnitAlive, u)
    return (ok and type(n) == "number") and n or 0
end
local function decoyed(u, now) return (TAC and TAC.decoyed and TAC.decoyed(u, now)) and true or false end
local function heldTrap(u, k) local w = D.wolf and D.wolf[u]; return w ~= nil and k ~= nil and w.held[k] == true end
local function angle(ax, ay, az, bx, by, bz)          -- between two vectors, degrees (180 when one has no length)
    local la, lb = math.sqrt(ax * ax + ay * ay + az * az), math.sqrt(bx * bx + by * by + bz * bz)
    if la == 0 or lb == 0 then return 180 end
    return math.deg(math.acos(math.max(-1, math.min(1, (ax * bx + ay * by + az * bz) / (la * lb)))))
end
local function leadS(id)                             -- (a tell's lead_s, whether or not it was said: the action waits it)
    local l = CFG.tells and CFG.tells.lead_s
    return math.max(0, num(type(l) == "table" and l[id], 0))
end
-- this game's own player where they are now (COOP.me's read of this tick), or nil (none, or down at the airfield)
local function myAt()
    local e = COOP and COOP.me and COOP.me() or nil
    local at = (e and e.at) or playerLocation()
    if not at then return nil end
    local okA, onA = pcall(playerOnAirfield, at)
    if okA and onA == true then return nil end
    return at
end
-- the players a squadron can meet (COOP.players(): you first; solo or the Offline edition: you): alive, flying, their
-- state fresh, not down at the airfield
local function players()
    local all = nil
    if COOP and COOP.players then
        local ok, l = pcall(COOP.players)
        if ok and type(l) == "table" then all = l end
    end
    if not all then
        local at = playerLocation()
        all = at and { { slot = 0, isMe = true, at = at, alive = true, obj = survivalPC and valid(survivalPC) and survivalPC.Pawn } } or {}
    end
    local out = {}
    for _, e in ipairs(all) do
        if e.at and e.alive ~= false and e.fresh ~= false then
            local down = e.onAirfield
            if down == nil and e.isMe then local okA, a = pcall(playerOnAirfield, e.at); down = okA and a == true end
            if not down then out[#out + 1] = e end
        end
    end
    return out
end
-- the player a flight met (sq.contact), as they are now; nil when they're gone (down, landed)
local function targetOf(sq)
    local c = sq.contact
    if not c then return nil end
    for _, e in ipairs(players()) do
        if (c.isMe and e.isMe) or (not c.isMe and not e.isMe and e.slot == c.slot) then return e end
    end
    return nil
end
local function leadOf(unit)                          -- flight unit's lead (object 0), alive as the sweep last saw it
    for _, p in ipairs(planes) do
        if p.unit == unit and p.k == 0 and not p.down and valid(p.obj) then return p end
    end
    return nil
end
-- a tell to player e (nil: this game's own); said, and what the log says about it
local function tell(id, e, a)
    if not (id and TELL and TELL.say and TELL.known and TELL.known(id)) then return false, "no tell" end
    local ok, said, why = pcall(TELL.say, id, (e and not e.isMe) and e.slot or nil, a)
    if not ok then return false, "tell error " .. tostring(said) end
    if said == true then return true, "told (" .. id .. ")" end
    return false, string.format("%s not told: %s", id, tostring(why))
end

function ACE.blinkEvent(unit, j)
    local b = ACE.BLINK
    local i = unit and poolIndex(unit)
    if not (type(b) == "table" and i and ROLE and ROLE.of and ROLE.of[unit] == b.ROLE and not PROBE_OF[unit]) then return nil end
    local n = math.floor(360 / b.STEP_DEG)
    if type(j) ~= "number" or j < 0 or j >= n or j ~= math.floor(j) then return nil end
    return string.format("RE_SV_WraithBlink%s%s", string.char(64 + i), string.char(65 + j))
end

function ACE.pickOpener(unit, tk, role)
    if not (on() and D and tk) then return nil end
    local list = fcfg(tk).openers
    if type(list) ~= "table" or #list == 0 or (#list == 1 and tostring(list[1]) == "none") then return nil end   -- ("none")
    D.openerNext = D.openerNext or {}
    local start = math.floor(num(D.openerNext[tk], 1))
    for i = 0, #list - 1 do
        local idx = (start - 1 + i) % #list + 1
        local op = tostring(list[idx])
        if KNOWN[op] and (op ~= "blink" or ACE.blinkEvent(unit, 0)) then
            D.openerNext[tk] = idx % #list + 1
            return op
        end
    end
    D.openerNoFit = D.openerNoFit or {}
    if D.openerNoFit[tk] ~= D.round then             -- (once a round per tier)
        D.openerNoFit[tk] = D.round
        local t = {}
        for _, x in ipairs(list) do t[#t + 1] = tostring(x) end
        log(string.format("aces: %s (%s squadron%s) can't show %s (a blink needs a %s flight's lead): it opens with a kulbit",
            unit, squadName(tk), role and (", " .. role) or "", table.concat(t, " / "), tostring(ACE.BLINK and ACE.BLINK.ROLE)))
    end
    return "kulbit"
end

function ACE.highAlt(alt)
    local h = oc("high")
    return math.max(alt, math.min(alt + num(h.alt_add_m, 0), num(h.top_m, 4500)))
end

function ACE.squadUp(unit, ace, role, n)
    if not D then return end
    D.squad = D.squad or {}
    D.squad[unit] = nil                              -- (a recycled flight: what it had is gone)
    if not (type(ace) == "table" and ace.tier and on()) then return end
    local tk, op = ace.tier, ace.opener
    local sq = { tk = tk, ti = D.flightTier and D.flightTier[unit], op = op, role = role, n = n, at = D.now or 0, dmgSeen = 0,
                 blinks = 0 }
    D.squad[unit] = sq
    local b = fcfg(tk).blink
    local blinks = type(b) == "table" and b.enabled ~= false and ACE.blinkEvent(unit, 0) ~= nil
    log(string.format("aces: %s (%s squadron%s) opens with %s at first contact (within %.1f km)%s", unit, squadName(tk),
        role and (", " .. role) or "", op or "nothing", num(oc(op or "").km, 4),
        blinks and string.format("; its lead blinks off your six (every %.0f s at most)", num(b.every_s, 20)) or ""))
end

-- a flight's first contact: player e d km from its plane p. Its squadron's tell to them (the round's first flight of
-- it they meet: <tier>_in; a later one its opener's own), the opener the tell's lead_s on (sq.actAt). The
-- flight's reversals (ACE.movesTick, after this tick's squads) and the director's cover turn wait until the opener's
-- gone (sq.holdTo through D.aceMoveAt; U10's review: one fired in between and the opener cut each other); a move already
-- in flight is the opener's to wait out (act). A held trap's hold_max_s runs from here (WOLF.contact); a hit on its
-- lead from before counts for no blink (sq.dmgSeen)
local function open(unit, sq, e, d, p, now)
    sq.contact = { at = now, slot = e.slot, isMe = e.isMe == true, d = d }
    local tk, op = sq.tk, sq.op
    if WOLF and WOLF.contact then WOLF.contact(unit, now) end
    local ld = leadOf(unit)
    sq.dmgSeen = math.max(sq.dmgSeen or 0, ld and ld.dmg and tonumber(ld.dmg.you) or 0)
    D.squadSaid = D.squadSaid or {}
    local key = tk .. "|" .. (e.isMe and "me" or tostring(e.slot))
    local first = D.squadSaid[key] ~= D.round
    D.squadSaid[key] = D.round
    local id = (first and pc().tells ~= false) and (tk .. "_in") or (op and OPEN_TELL[op]) or nil
    local a = nil                                    -- (the dive's o'clock: its chained line)
    if id == "dive" and DIR and DIR.oclock and p.at then
        local okC, h = pcall(DIR.oclock, e, p.at)
        a = okC and h or 12
    end
    local said, how = tell(id, e, a)
    local lead = id and leadS(id) or 0
    if op then
        sq.actAt = now + lead
        local span = 1                               -- (a salvo: its last shot gap_s apart)
        if op == "high" then span = span + math.max(0, num(oc("high").gap_s, 0)) * math.max(0, math.floor(num(oc("high").salvo, 0)) - 1) end
        sq.holdTo = sq.actAt + span
        D.aceMoveAt = D.aceMoveAt or {}
        D.aceMoveAt[unit] = math.max(D.aceMoveAt[unit] or 0, sq.holdTo)
    end
    log(string.format("aces: %s (%s squadron) meets %s %.1f km off (%s): %s; %s", unit, squadName(tk), who(e), d, p.name or "?",
        id and how or "no tell", op and string.format("its %s in %.1f s", op, lead) or "no opener"))
    pcall(STATS.tactic, "opener", unit, e.slot, string.format("%s, %s", squadName(tk), tostring(op)), said and id or nil)
end

-- its planes able to fire the opening salvo at e: index 0-5, its row's missiles in the salvo's slot (the director's
-- check: SR.mslSlot, DIR.SALVO_FCS_SLOT), not a held Wolf trap, within range; the nearest first, at most max
local function shooters(unit, e, rangeKm, max)
    local list = {}
    for _, p in ipairs(planes) do
        if p.unit == unit and not p.down and valid(p.obj) and p.k and p.k <= 5 and p.at and not heldTrap(unit, p.k) then
            local lr = p.k == 0 and D.leadRow and D.leadRow[unit]
            local row = (lr and lr.row) or (D.flightRow and D.flightRow[unit])
            if row and SR and SR.mslSlot and DIR and SR.mslSlot[row] == DIR.SALVO_FCS_SLOT then
                local d = km(p.at, e.at)
                if d <= rangeKm then list[#list + 1] = { p = p, d = d } end
            end
        end
    end
    table.sort(list, function(x, y) return x.d < y.d end)
    local out = {}
    for i = 1, math.min(max, #list) do out[i] = list[i].p end
    return out
end
local function salvoName(p) return string.format("RE_SV_Salvo_%02d%s", poolIndex(p.unit), string.char(65 + p.k)) end
local function shotsTick(unit, sq, now)
    local keep, out = {}, {}
    for _, s in ipairs(sq.shots) do
        if now >= s.at then
            if not s.p.down and valid(s.p.obj) then out[#out + 1] = s.ev .. " " .. (fire(s.ev))
            else out[#out + 1] = s.ev .. " (down first)" end
        else keep[#keep + 1] = s end
    end
    sq.shots = #keep > 0 and keep or nil
    if #out > 0 then log(string.format("aces: %s's opening salvo: %s", unit, table.concat(out, ", "))) end
end
local function high(unit, sq, e, now)
    local h = oc("high")
    local list = shooters(unit, e, num(h.range_km, 5), math.max(0, math.floor(num(h.salvo, 0))))
    if #list == 0 then
        log(string.format("aces: %s's opening salvo: none of its planes can fire at %s (range, missile slot)", unit, who(e)))
        return
    end
    local gap = math.max(0, num(h.gap_s, 0))
    if e.isMe or not (COOP and COOP.dispatch) then
        sq.shots = {}
        for i, p in ipairs(list) do sq.shots[#sq.shots + 1] = { at = now + (i - 1) * gap, p = p, ev = salvoName(p) } end
        shotsTick(unit, sq, now)
    else                                             -- (a joiner: its own copies fire at it, "dv")
        local out = {}
        for i, p in ipairs(list) do
            local ev = salvoName(p)
            local okD, sent = pcall(COOP.dispatch, e.slot, ev, unit, (i - 1) * gap)
            out[#out + 1] = ev .. ((okD and sent) and " sent" or " not sent")
        end
        log(string.format("aces: %s's opening salvo on %s's copies (\"dv\"): %s", unit, who(e), table.concat(out, ", ")))
    end
end
-- the flight's reversal onto player e (the campaign aces' LastTGT, RE_SV_AceTurn_NN; a joiner, whom LastTGT can't reach:
-- the hunt, RE_SV_Hunt_NN); its next move no sooner than cover.move_s (D.aceMoveAt, shared with ACE.movesTick)
local function turn(unit, sq, e, now, why)
    local i = poolIndex(unit)
    if not i then return end
    D.aceMoveAt = D.aceMoveAt or {}
    local cv = CFG.director and CFG.director.cover
    D.aceMoveAt[unit] = math.max(D.aceMoveAt[unit] or 0, now + num(cv and cv.move_s, 30))
    local ev = string.format(e.isMe and "RE_SV_AceTurn_%02d" or "RE_SV_Hunt_%02d", i)
    log(string.format("aces: %s (%s squadron) %s: %s %s", unit, squadName(sq.tk), why, ev, (fire(ev))))
end
local function trap(unit, sq, e, now)
    local t = oc("trap")
    if WOLF and WOLF.holding and WOLF.holding(unit) then
        sq.springAt = now + math.max(0, num(t.spring_s, 8))
        sq.springBy = sq.springAt + math.max(0, num(t.wait_s, 15))
        log(string.format("aces: %s (%s squadron): its trap springs in %.0f s", unit, squadName(sq.tk), sq.springAt - now))
    else                                             -- (not a Wolf flight holding its trap: the pack turns on you)
        turn(unit, sq, e, now, "has no trap held: its pack turns on " .. who(e))
    end
end
local function springTick(unit, sq, now)
    local w = D.wolf and D.wolf[unit]
    if w and w.state == "pending" and now < (sq.springBy or now) then return end   -- (not held yet: it waits)
    sq.springAt = nil
    if not (WOLF and WOLF.holding and WOLF.holding(unit)) then
        log(string.format("aces: %s (%s squadron): its trap isn't held any more (sprung, freed or down); nothing to spring",
            unit, squadName(sq.tk)))
        return
    end
    local e = targetOf(sq)
    local _, how = tell("trap", e)
    sq.freeAt = now + leadS("trap")
    log(string.format("aces: %s (%s squadron): its trap springs on %s in %.1f s (%s)", unit, squadName(sq.tk), who(e),
        sq.freeAt - now, how))
end
local function free(unit, sq, now)
    local e = targetOf(sq)
    -- (the turn, LastTGT, steers to this game's player: a joiner's trap is only let go)
    local okF, n = pcall(WOLF.free, unit, string.format("%s's trap springs", squadName(sq.tk)), (e and e.isMe) == true, nil, now)
    if not okF then log("aces: trap error " .. tostring(n)) end
end
local function kulbit(unit, sq, now)
    local i = poolIndex(unit)
    if not i then return end
    D.aceMoveAt = D.aceMoveAt or {}
    D.aceMoveAt[unit] = math.max(D.aceMoveAt[unit] or 0, now + 12)       -- (a OneShot: the reversals wait it out)
    local ev = string.format("RE_SV_AceKulbit_%02d", i)
    log(string.format("aces: %s (%s squadron) kulbits as one: %s %s", unit, squadName(sq.tk), ev, (fire(ev))))
end

-- flight unit's lead blinks to a spot behind and beside you (your heading +-135 deg, ACE.BLINK's ring; else dead six,
-- else abeam), clear of the ground (ground_clear_m, or 80 % of your own height over it when you fly lower, as AB.L..IN's),
-- smoke where it left and where it came out. Whether it went
local function blinkNow(unit, sq, now, why)
    local lead, me, b = leadOf(unit), myAt(), ACE.BLINK
    if not (lead and me and ACE.blinkEvent(unit, 0)) then
        log(string.format("aces: %s's lead didn't blink (%s): %s", unit, why,
            not lead and "its lead is down" or (not me and "you're not flying" or "no blink events for it")))
        return false
    end
    local n = math.floor(360 / b.STEP_DEG)
    local head = SPC and SPC.V and SPC.V.heading and SPC.V.heading() or nil
    local side = math.random() < 0.5 and 1 or -1
    local wants = head and { head + 135 * side, head - 135 * side, head + 180, head + 90 * side, head - 90 * side }
        or { math.random() * 360, math.random() * 360, math.random() * 360 }
    local ground = ANOM and ANOM.groundAt
    local under = ground and ground(me.X, me.Y)
    local clear = math.max(0, num(pc().ground_clear_m, 150)) * 100
    if under then clear = math.max(0, math.min(clear, (me.Z - under) * 0.8)) end
    local tried = {}
    for _, want in ipairs(wants) do
        local j = math.floor((want % 360) / b.STEP_DEG + 0.5) % n
        if not tried[j] then
            tried[j] = true
            local dg = j * b.STEP_DEG
            local to = { X = me.X + b.RING_M * 100 * math.cos(math.rad(dg)), Y = me.Y + b.RING_M * 100 * math.sin(math.rad(dg)), Z = me.Z }
            local g = ground and ground(to.X, to.Y)
            if not g or to.Z >= g + clear then
                local okW, was = pcall(function() local v = lead.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
                local ev = ACE.blinkEvent(unit, j)
                local res, ok = fire(ev)
                if ok and pc().smoke ~= false and ANOM and ANOM.smokeAt then
                    if okW and was then pcall(ANOM.smokeAt, was) end
                    pcall(ANOM.smokeAt, to)
                end
                sq.blinks = sq.blinks + (ok and 1 or 0)
                log(string.format("aces: %s's lead %s blinks (%s): your heading %s -> spot %.0f deg, %d m (%s %s)", unit,
                    lead.name or "?", why, head and string.format("%.0f", head % 360) or "?", dg, b.RING_M, ev, res))
                if ok then pcall(STATS.tactic, "blink", unit, nil, why) end
                return ok
            end
        end
    end
    log(string.format("aces: %s's lead didn't blink (%s): no spot clear of the ground round you", unit, why))
    return false
end

-- the opener's action, its tell's lead_s after the first contact. A kulbit, or the turn of a trap with none held, is a
-- unique action that would cut a move of the flight still in flight (a reversal from before the contact, the director's
-- cover turn: D.aceMoveAt past the opener's own hold) and is cut by it: it waits that move out, once
local function act(unit, sq, now)
    local op, e = sq.op, targetOf(sq)
    if not op then return end
    if decoyed(unit, now) or (DIR and DIR.holding and DIR.holding(unit)) then
        log(string.format("aces: %s's %s not shown: your decoy (or the director) stands it down", unit, op))
        return
    end
    local busy = D.aceMoveAt and D.aceMoveAt[unit] or 0
    if not sq.waited and busy > now and busy > (sq.holdTo or 0) + 0.01
        and (op == "kulbit" or (op == "trap" and not (WOLF and WOLF.holding and WOLF.holding(unit)))) then
        sq.waited, sq.actAt = true, busy
        log(string.format("aces: %s's %s waits %.1f s: a move of the flight is in flight (a reversal, the director's turn)",
            unit, op, busy - now))
        return
    end
    if op == "kulbit" then kulbit(unit, sq, now); return end
    if not e then
        log(string.format("aces: %s's %s not shown: %s left the fight (down, or at the airfield)", unit, op, who(sq.contact)))
        return
    end
    if op == "high" then high(unit, sq, e, now)
    elseif op == "trap" then trap(unit, sq, e, now)
    elseif op == "blink" then
        if sq.blinkGo or now < (sq.blinkAt or 0) then
            log(string.format("aces: %s's blink opener not shown: its lead blinked already", unit))
        elseif e.isMe then
            local b = fcfg(sq.tk).blink
            if blinkNow(unit, sq, now, "its opener") and type(b) == "table" then
                sq.blinkAt = now + num(b.every_s, 20)
                D.aceMoveAt = D.aceMoveAt or {}
                D.aceMoveAt[unit] = math.max(D.aceMoveAt[unit] or 0, now + num(b.move_gap_s, 10))
            end
        else
            log(string.format("aces: %s's blink is round the host's plane only: none for %s (its tell only)", unit, who(e)))
        end
    end
end

-- your hits on flight unit's lead so far, none of them a reason for a later blink (sq.dmgSeen): taken while it couldn't
-- blink (every_s, an opener or a blink on its way, your decoy, a director hold), a hit isn't news once it can (F1's
-- review: one hit in each cooldown made on_hit a blink every every_s)
local function hitsSeen(unit, sq)
    local lead = leadOf(unit)
    sq.dmgSeen = math.max(sq.dmgSeen or 0, lead and lead.dmg and tonumber(lead.dmg.you) or 0)
end

-- a blinking tier's lead (CFG.aces.flight <tier>.blink): you on its six within tailed_km and tail_deg (its position read
-- afresh only when the sweep had it within tailed_km + 1.5 of you), or (on_hit) your hit on it since the last look: the
-- "blink" tell, the blink its lead_s later (sq.blinkGo), its next no sooner than every_s, the flight's reversals no
-- sooner than move_gap_s (D.aceMoveAt)
local function blinkCheck(unit, sq, b, now, me)
    if sq.actAt or sq.blinkGo or sq.springAt or decoyed(unit, now) or (DIR and DIR.holding and DIR.holding(unit)) then
        hitsSeen(unit, sq)
        return
    end
    local lead = leadOf(unit)
    if not (lead and ACE.blinkEvent(unit, 0)) then return end
    local why = nil
    local dmg = lead.dmg and tonumber(lead.dmg.you) or 0
    if b.on_hit and dmg > (sq.dmgSeen or 0) then why = "you hit it" end
    sq.dmgSeen = math.max(sq.dmgSeen or 0, dmg)
    local reach = num(b.tailed_km, 2.5)
    if not why and lead.dist and lead.dist <= reach + 1.5 then
        local ok, at, fwd = pcall(function()
            local v, f = lead.obj:K2_GetActorLocation(), lead.obj:GetActorForwardVector()
            return { X = v.X, Y = v.Y, Z = v.Z }, { X = f.X, Y = f.Y, Z = f.Z }
        end)
        if ok and at and fwd then
            local range = km(at, me) * 1000
            local off = angle(-fwd.X, -fwd.Y, -fwd.Z, me.X - at.X, me.Y - at.Y, me.Z - at.Z)
            if range <= reach * 1000 and off <= num(b.tail_deg, 70) then
                why = string.format("you %.0f m on its six, %.0f deg off its tail", range, off)
            end
        end
    end
    if not why then return end
    local _, how = tell("blink", nil)
    local l = leadS("blink")
    sq.blinkGo = { at = now + l, why = why .. "; " .. how }
    sq.blinkAt = now + num(b.every_s, 20)
    D.aceMoveAt = D.aceMoveAt or {}
    D.aceMoveAt[unit] = math.max(D.aceMoveAt[unit] or 0, now + l + num(b.move_gap_s, 10))
end

function ACE.squadTick(now, D, paused)
    if paused or not (now and D and D.round and D.squad and next(D.squad)) then return end
    if client() or not on() then return end
    local scan = now >= (D.squadScanAt or 0)
    if scan then D.squadScanAt = now + SCAN_S end
    local ps, me, meRead = nil, nil, false
    for unit, sq in pairs(D.squad) do
        if scan and now - sq.at > 10 and alive(unit) <= 0 then
            D.squad[unit] = nil                      -- (down, or never came: its opener goes with it)
        else
            if not sq.contact and scan then
                ps = ps or players()
                local km0, best, bd, bp = num(oc(sq.op or "").km, 4), nil, nil, nil
                for _, p in ipairs(planes) do
                    if p.unit == unit and not p.down and p.at then
                        for _, e in ipairs(ps) do
                            local d = km(p.at, e.at)
                            if d <= km0 and (not bd or d < bd) then best, bd, bp = e, d, p end
                        end
                    end
                end
                if best then open(unit, sq, best, bd, bp, now) end
            end
            if sq.actAt and now >= sq.actAt then sq.actAt = nil; act(unit, sq, now) end
            if sq.shots then shotsTick(unit, sq, now) end
            if sq.springAt and now >= sq.springAt then springTick(unit, sq, now) end
            if sq.freeAt and now >= sq.freeAt then sq.freeAt = nil; free(unit, sq, now) end
            if sq.blinkGo and now >= sq.blinkGo.at then
                local g = sq.blinkGo
                sq.blinkGo = nil
                blinkNow(unit, sq, now, g.why)
            end
            local b = fcfg(sq.tk).blink
            -- (only once it's met someone: no blink before its squadron's tell and opener, U10's review; inside every_s
            -- your hits are seen at the scan's pace, the sweep's damage reads being 2 s apart)
            if sq.contact and type(b) == "table" and b.enabled ~= false then
                if now >= (sq.blinkAt or 0) then
                    if not meRead then me, meRead = myAt(), true end
                    if me then blinkCheck(unit, sq, b, now, me) else hitsSeen(unit, sq) end
                elseif scan then hitsSeen(unit, sq) end
            end
        end
    end
end
end

-- g: its KILL.geom (worked out here when not given)
function probeKill(p, you, g)
    if not (CFG.probe.enabled and CFG.probe.kills) then return end
    g = g or KILL.geom(p, you)
    local used = {}
    for k = 0, 4 do
        local n = g.used[AMMO_SHORT[k]] or 0
        if n > 0 then used[#used + 1] = AMMO_SHORT[k] .. " x" .. n end
    end
    log(string.format("kill: %s; you were %s away, %s, altitude %s; you fired %s in the last 6 s",
        p.name, g.km and string.format("%.1f km", g.km) or "?", g.offNose and string.format("%.0f deg off its nose", g.offNose) or "?",
        g.dz and string.format("%+.1f km", g.dz) or "?", #used > 0 and table.concat(used, ", ") or "nothing seen"))
end

---------------------------------------------------------------------------------------------------- who shot it down
-- CFG.allies.kills (economy review of 2026-10-25: "no line records an ally's or a defence's kills"): each enemy's
-- DamageHistoryMap (attacker -> its total damage; tools/re/KILLS_HEALTH_DEATH.md 1) is read while it flies, with its
-- position, and once more as it goes down. Attackers by side: your aircraft "you", MOONCHILD's / the WINGMEN's planes
-- "allies", the Aegis's hull and turrets (BP_VE002_aegs_*) "ships", the AA guns and SAM sites (BP_GR002_gepa_*,
-- BP_GR005_avng_*) "defences". A kill is yours when you hit it at all (or nothing could be read); else the side that
-- did it the most damage.
KILL = {}
-- A plane's kill at one moment (the kill log's and the measurements', sv_stats.lua STATS.down): offNose, the angle off
-- its nose of the line to you (0 you were ahead of it, 180 on its tail); km, the range; dz, your height over it (km);
-- used, your shots of each kind in the last ~6 s (PR.ammo, a row every 0.5 s: shots at anything); wpn, the weapon kind
-- (gun, msl, sp1, sp2) whose count dropped last. Your position is the one from its own last sample (p.youAt, the
-- plane's 2 s sweep visit), so the aspect isn't mixed from two reads up to 2 s apart; else `you`.
function KILL.geom(p, you)
    you = p.youAt or you
    local g = { used = {} }
    if p.at and you then
        local tx, ty, tz = you.X - p.at.X, you.Y - p.at.Y, you.Z - p.at.Z
        local len = math.sqrt(tx * tx + ty * ty + tz * tz)
        g.km, g.dz = len / 100000, tz / 100000
        if p.fwd and len > 0 then
            local c = (p.fwd.X * tx + p.fwd.Y * ty + p.fwd.Z * tz) / len      -- 1: you were ahead of it, -1: on its tail
            g.offNose = math.deg(math.acos(math.max(-1, math.min(1, c))))
        end
    end
    local h, lastAt = PR.ammo, nil
    for k = 0, 4 do
        local spent, at = 0, nil
        for i = 2, #h do
            local a, b = h[i - 1][k], h[i][k]
            if a and b and a >= 0 and b >= 0 and b < a then spent, at = spent + (a - b), i end
        end
        g.used[AMMO_SHORT[k]] = spent
        if at and k <= 3 and (not lastAt or at >= lastAt) then g.wpn, lastAt = AMMO_SHORT[k], at end
    end
    return g
end

function KILL.side(o, pawnAddr)
    local a = addrOf(o)
    if a and a == pawnAddr then return "you" end
    local n = nameOf(o)
    if n:find("BP_VE002_aegs", 1, true) then return "ships" end
    if n:find("_gepa_", 1, true) or n:find("_avng_", 1, true) then return "defences" end
    local R = ALLY.run
    if R and a then for _, q in ipairs(R.planes) do if addrOf(q.obj) == a then return "allies" end end end
    if n:find("PlayerPlane", 1, true) then return "you" end
    return "other"
end

function KILL.read(p)
    if not (CFG.allies.kills and valid(p.obj)) then return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    local pa = valid(pawn) and addrOf(pawn) or nil
    local d = {}
    local ok = pcall(function()
        p.obj.DamageHistoryMap:ForEach(function(k, v)
            local okK, o = pcall(function() return k:get() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and type(x) == "number" and x > 0 and valid(o) then
                local s = KILL.side(o, pa)
                d[s] = (d[s] or 0) + x
            end
        end)
    end)
    if ok and next(d) then p.dmg = d
    elseif not ok and not KILL.said then KILL.said = true; log("kills: an enemy's DamageHistoryMap couldn't be read; every kill counts as yours") end
end

-- What you fired at lately: KILL.fired[address] = when (your aircraft's LastFiredWeaponTarget, read every tick), so a
-- plane your missile finished between two reads of its damage still counts as yours
KILL.fired = {}
function KILL.markTarget(pc, now)
    local ok, tgt = pcall(function() return pc.Pawn.LastFiredWeaponTarget end)
    local a = ok and valid(tgt) and addrOf(tgt)
    if a then KILL.fired[a] = now end
    if now >= (KILL.pruneAt or 0) then                     -- (old ones out, every 30 s)
        KILL.pruneAt = now + 30
        for k, t in pairs(KILL.fired) do if now - t > 30 then KILL.fired[k] = nil end end
    end
end

-- Who gets plane p's kill: "you", "allies", "ships" or "defences".
function KILL.by(p)
    local d = p.dmg
    if not d or (d.you or 0) > 0 then return "you" end
    local t = p.addr and KILL.fired[p.addr]
    if t and D and D.now and D.now - t <= 15 then return "you" end   -- (you fired at it in its last 15 s)
    local best, side = 0, "you"
    for s, x in pairs(d) do if s ~= "other" and x > best then best, side = x, s end end
    return side
end

---------------------------------------------------------------------------------------------------- late rounds, the jammer
-- CFG.late: a pool or bomber aircraft's health x TIER.lateHealthX(round), once, as it's first seen up (the specials
-- scale their own), times its fighter role's CFG.roles.health_x (P1: a Skirmisher's 0.75, "dies fast if caught"; not an
-- ace squadron's). HealthInternal is health x 10 and a whole number; MaxHealth is raised with it, so its damage model
-- (smoke, fire) reads the new health as whole (as AB.L..IN's), and lowered with it (x below 1), or a cut-down plane
-- would read as damaged and spawn smoking (the critic's gap fill; lowering it live is untested, raising it is confirmed).
function scaleHealth(o, x)
    if not (x and x ~= 1 and valid(o)) then return nil end
    local okH, h0 = pcall(function() return o.HealthInternal end)
    if not (okH and type(h0) == "number" and h0 > 0) then return nil end
    local h1 = math.max(1, math.floor(h0 * x + 0.5))
    pcall(function() o.HealthInternal = h1 end)
    if x < 1 then pcall(function() o.MaxHealth = h1 / 10 end)
    else pcall(function() if o.MaxHealth * 10 < h1 then o.MaxHealth = h1 / 10 end end) end
    return h0, h1
end

local lateSaid = {}
function enemyLate(p, round)
    if p.late ~= nil then return end
    p.late = false
    local u = p.unit
    if not (u and (poolIndex(u) or BOMBER_UNIT[u])) then return end
    local x = TIER.lateHealthX(round)
    local role = ROLE.flight(u)                       -- (its fighter role's health, CFG.roles.health_x; ace squadrons keep theirs)
    local rx = role and not (D and D.aceSquad and D.aceSquad[u]) and tonumber(CFG.roles.health_x and CFG.roles.health_x[role]) or 1
    if rx and rx > 0 and rx ~= 1 then x = x * rx else rx = 1 end
    if x == 1 then return end
    local h0, h1 = scaleHealth(p.obj, x)
    p.late = h1 ~= nil
    -- (a co-op joiner's copy, scaled as the host scales its own: what it's expected to have moves with it, or the cut
    -- went to the host as this player's hit and took a Skirmisher there to x0.5; code review of 2026-10-29)
    if h1 and COOP and COOP.copyScaled then COOP.copyScaled(p.obj, h0, h1) end
    local key = round .. "|" .. (rx ~= 1 and role or "")
    if h1 and not lateSaid[key] then
        lateSaid[key] = true
        log(string.format("late: round %d enemies' health x%.2f%s (%s: %d -> %d)", round, x,
            rx ~= 1 and string.format(" (%s x%.2f)", role, rx) or "", p.name, h0, h1))
    end
end

-- The jammer (CFG.jammer): its plane, found as it's seen up (its flight D.jammer.unit, an EA-18G), sharpens every enemy
-- within radius_km (PilotRank + rank_add, at most 5) while it flies; each goes back to its own rank when it's out of
-- range or the jammer is down. Run every 2 s.
JAM = {}
function JAM.tick()
    local j = D and D.jammer
    if not j then return end
    local c = CFG.jammer
    if not j.p then
        for _, p in ipairs(planes) do
            if not p.down and p.unit == j.unit and p.name:find("_e18g_", 1, true) then
                j.p, p.jammer = p, true
                log("jammer: " .. p.name .. " (" .. j.unit .. ") is up")
            end
        end
        if not j.p then return end
    end
    local on = not j.p.down and j.p.at
    local n = 0
    for _, p in ipairs(planes) do
        if p ~= j.p and not p.down and valid(p.obj) then
            local want = on and p.at and km(p.at, j.p.at) <= c.radius_km and p.rankSet
            if want and not p.jammed then
                p.jammed = true
                pcall(function() p.obj.PilotRank = math.min(5, p.rankSet + c.rank_add) end)
            elseif not want and p.jammed then
                p.jammed = nil
                pcall(function() p.obj.PilotRank = p.rankSet end)
            end
            if p.jammed then n = n + 1 end
        end
    end
    if n ~= j.n then j.n = n; log(string.format("jammer: %d enemies sharpened near it", n)) end
    -- its ECM pod (CFG.jammer.ecm), the flight's lead's (RE_SV_JamEcm_NN fires object 0's slot 4): once it's up, then
    -- every ecm_every_s; the first answer and any that isn't 1 logged
    local idx = on and c.ecm and type(SV_Event) == "function" and D.now and poolIndex(j.unit)
    if idx and (j.p.k or 0) == 0 and D.now >= (j.ecmAt or 0) then         -- (k unknown: the jammer leads)
        j.ecmAt = D.now + math.max(2, tonumber(c.ecm_every_s) or 14)
        local ev = string.format("RE_SV_JamEcm_%02d", idx)
        local r = SV_Event(ev)
        if not j.ecmSaid or r ~= 1 then
            j.ecmSaid = true
            log(string.format("jammer: its ECM pod on (%s %s), again every %d s", ev, r == 1 and "fired" or ("not fired: "
                .. (SV_ERR[r] or tostring(r))), math.max(2, tonumber(c.ecm_every_s) or 14)))
        end
    elseif on and c.ecm and (j.p.k or 0) ~= 0 and not j.ecmSaid then
        j.ecmSaid = true
        log("jammer: " .. j.p.name .. " isn't its flight's lead (object " .. tostring(j.p.k) .. "): no ECM pod (RE_SV_JamEcm fires object 0's)")
    end
    if not on then D.jammer = nil end
end

ZONE = { X = -707336.0, Y = -261895.0, HALF = 3700000.0 }   -- Mission 22's combat zone (80 km), 3 km margin
SV_ERR = { [0] = "the game spawned nothing", [-1] = "not in Survival's level", [-2] = "no such unit or aircraft",
                 [-3] = "its last flight is still up", [-4] = "bad arguments", [-5] = "game functions not found",
                 [-6] = "the level is still loading" }
D = nil                      -- the run in progress: { round, state, at, now, queue, spare, up, flown }
-- The run's money and purchases: { credits, earned, spent, bought = { [item] = n },
-- msg = { [item] = last result }, dirty (shop texts need updating) }. Reset when Survival's level loads.
RUN = { credits = 0, earned = 0, spent = 0, bought = {}, msg = {}, kills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 } }

function addCredits(n, why)
    if n <= 0 then return end
    local x = SETUP and SETUP.payX and SETUP.payX() or 1          -- (the menu's ZOLLAR INCOME %, sv_menu.lua)
    if x ~= 1 then n, why = math.max(1, math.floor(n * x + 0.5)), string.format("%s, income x%.2f", why, x) end
    RUN.credits, RUN.earned, RUN.dirty = RUN.credits + n, RUN.earned + n, true
    RUN.msg = {}            -- a shop result ("NOT ENOUGH ZOLLARS ...") is stale once the credits change
    log(string.format("credits: +%d (%s), now %d", n, why, RUN.credits))
end

-- Kill pay's multiplier now: CFG.credits.special_x in a special round, else 1.
function TIER.specialX() return (D and D.special) and (CFG.credits.special_x or 1) or 1 end

function nativeReady()
    return type(SV_Spawn) == "function" and type(SV_UnitAlive) == "function" and type(SV_SetAircraft) == "function"
end

---------------------------------------------------------------------------------------------------- round HUD
-- Survival's own HUD layer, built at run time (no widget asset). The game's HUD is laid out on a 3840x2160 canvas
-- (tools/re/HUD_LAYOUT.md), so ours is too: a stock widget blueprint with no script of its own
-- (WBP_HUD_NonGlowMessage_000, its parts collapsed) -> its root canvas -> ScaleBox (scale to fit) -> SizeBox
-- 3840x2160 -> our canvas. The rows copy the mission info panel (HUD typeface 37, spacing -70, white, opacity 0.55) and
-- sit under its TIME / SCORE stack; the callout copies the MessageLayerOne banner (text in a frame of 4 px bars).
-- UUserWidget is Abstract (constructing one directly is fatal in a shipping build), so the widget comes from
-- WidgetBlueprintLibrary.Create, the engine's CreateWidget; TextBlock / Image / CanvasPanel / ScaleBox / SizeBox are
-- concrete and made with StaticConstructObject in its WidgetTree. All of it runs in the one game-thread tick.
HUD_ASSET = { base = "/Game/Blueprints/UI/WBP/HUD4K/Campaign/WBP_HUD_NonGlowMessage_000.WBP_HUD_NonGlowMessage_000_C",
                   font = "/Game/UI/Font/UI_FontSet_ja.UI_FontSet_ja" }
DESIGN_W, DESIGN_H = 3840, 2160
VIS = { Visible = 0, Collapsed = 1, Hidden = 2, HitTestInvisible = 3, SelfHitTestInvisible = 4 }
H = nil                      -- the HUD layer: { widget, tree, font, rowSlots, round, next, banner, ... }
AF = {}                      -- the airfield: { full, base, hits, hp, down, downRound, attackRound } (section "airfield")
hudGen, hudTries, hudOff = 0, 0, false
hudSaid = {}

function hudLog(key, msg)    -- once per key per level
    if hudSaid[key] then return end
    hudSaid[key] = true
    log("hud: " .. msg)
end

function cdo(path) local o = StaticFindObject(path); return valid(o) and o or nil end

function toText(s)
    local tl = cdo("/Script/Engine.Default__KismetTextLibrary")
    if tl then
        local ok, t = pcall(function() return tl:Conv_StringToText(s) end)
        if ok and t ~= nil then return t end
    end
    return FText(s)
end

function newWidget(cls, name)
    local c = StaticFindObject("/Script/UMG." .. cls)
    if not valid(c) then error("class UMG." .. cls .. " not found") end
    hudGen = hudGen + 1
    local w = StaticConstructObject(c, H.tree, FName(string.format("SV_%s_%d", name, hudGen)))
    if not valid(w) then error("could not create a " .. cls) end
    return w
end

-- Puts w on a canvas: anchors a0..a1, offsets {left, top, right, bottom}, alignment; auto = size from the content.
function slotIn(canvas, w, a0, a1, off, align, auto)
    local s = canvas:AddChildToCanvas(w)
    s:SetAnchors({ Minimum = { X = a0[1], Y = a0[2] }, Maximum = { X = a1[1], Y = a1[2] } })
    s:SetAlignment({ X = align[1], Y = align[2] })
    s:SetAutoSize(auto and true or false)
    s:SetOffsets({ Left = off[1], Top = off[2], Right = off[3], Bottom = off[4] })
    return s
end
