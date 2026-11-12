-- sv_rounds_store.lua: this game's landing STORE as a gate on the event package, and the one-shot events that change
-- the world fired again on this game once it's shut (hard rule 64). Part of AC8 Survival Mode's runtime, run by main.lua
-- in order right after sv_rounds_shuttle.lua (sv_rounds.lua's next piece): roundsTick (the host's, a solo game's) and a
-- joiner's clientRounds call STOREQ.tick every tick, sv_coop.lua's SV_Event wrapper STOREQ.before / STOREQ.fired, a
-- joiner's hostEvent STOREQ.forwarded, sv_spawn.lua's ALIVE.spawned STOREQ.sawSpawn, spawnBomber STOREQ.bomberPre /
-- STOREQ.bomberUp, sv_spaceport.lua STOREQ.note (at its load) and STOREQ.here; a name another part uses is a global of
-- this mod's Lua state, its own helpers stay local.
--
-- ((2026-11-11) hard rule 64, the rest of the STORE problem: Saint Alessia's host of 0.74.36 ran none of the records of
-- the events it sent while its landing minigames were up, SV_Event answering 1 all the same; the shuttle's liftoff was
-- the one seen, sv_rounds_shuttle.lua replays it; the sweep of every other host event at the same risk ranked these.)
--   The gate (SPC.storeShut, moved here): this game's events can't take while its landing STORE is open (D.musicHold),
--     while it's down at the airfield with no STORE yet this visit (the Landing and SeamlessIn minigames, which nothing
--     here sees), and for GATE_S after either; asked every tick, on the host, a solo game and a joiner (whose music hold
--     is its own landing menu's).
--   The host (or a solo game): an event of RULES fired through SV_Event while the gate is closed is fired again on this
--     game alone (COOP.eventHere: the joiners had it on time) once it's open, back to back; each one's effect read back
--     where the event package leaves one (a flag it sets, a counter it adds to, its unit gone): fired again only while it
--     hasn't taken, CHECK_S between, TRIES in all; dropped when what undoes it came after it (a hold after a free, a
--     newer pressure preset, the warning on again), when its unit was spawned again since (a new flight has its own
--     orders: a late removal or free would hit it), or when it's KEEP_S old.
--   Order: what shares a unit or a chain (the shuttle's seconds, a rocket's launch and boost, the attack throttle's
--     presets and the bosses' ends that put it back) goes in the order it came; the rest doesn't wait on it. One being
--     read back (Q.checks, its own clock) holds back only what shares its unit or chain. A flight's free or escort waits
--     for that flight's own orders (ordersTick's RE_SV_FlightOrders_NN, D.orders) as it would have on time; a heavy's
--     route for its flight's (STOREQ.bomberUp). Gaps only where the timing is the world's: the shuttle's seconds by their
--     own offsets from T from T-4 on, a rocket's boost boost_s after its launch.
--   Bomber and strike flights (spawnBomber): their appearance's orders (SV_BomberUp_NN) are read back BOMBER_CHECK_S on
--     by the counter SV_BOrd_NN the event package keeps (survival_events.py), gate or not, as ordersTick reads a pool
--     flight's SV_Up_NN; lost, RE_SV_BomberOrders_NN (the appearance's orders, the airfield's or, while SV_ShuttleRound
--     is 1, the shuttle's) is fired here once the gate's open, TRIES in all. An event package without the counter: one
--     that appeared while the gate was closed gets RE_SV_BomberRetask_NN (the airfield's) once it's open while
--     SV_ShuttleRound reads 0, and the log says the shuttle's orders need the newer package. A ship strike's orders are
--     its RE_SV_Strike event's (a rule), never these. Each heavy's route and each loop count in a flag of their own
--     (SV_BRoute_NNR, SV_BRoute_NN<L>), so two of one flight's lost in one STORE are read apart.
--   A joiner: the host's forwarded events of RULES marked `join` that come while this game's gate is closed are held
--     and fired here once it's open (each one's effect read first: a removal whose copies are gone already, a boss's
--     end already in, isn't fired); with the gate open one comes as ever, unless it shares a unit or a chain with one
--     still held or read back (then behind it); HOLD_MAX_S at most with the gate closed, then fired whatever (as
--     before). The shuttle's countdown collapses to what changes the world (shuttleKeep: its MinHealth, the ignition,
--     its path, the climb and its flags, the camera off, the climb's second leg, the boost off); its radio lines, sounds
--     and the camera's start that come with the gate closed aren't fired late. The Spaceport's removals know their units
--     on every game (from their names, or noted by sv_spaceport.lua at its load), so a held one is dropped when its units
--     spawned again since.
--   Logged once per kind with a count (`storeq: ...`): what was held or is to be fired again, each fired (again) and
--     whether it took, what was dropped and why, and a summary when the queue's done.
-- What's left out and why: docs/re/COOP.md section 13 (repeating events, spawns, counters, paths that start over, the
-- shuttle's countdown and removal, the Spaceport's launch on the host: each has its own replay or heals by itself).
STOREQ = {}
do
local GATE_S, CHECK_S, TRIES, HOLD_MAX_S, KEEP_S, BOMBER_CHECK_S = 3, 3, 3, 420, 900, 4
local ORDERS_WAIT_S, PER_TICK, Q_MAX = 30, 32, 96
local gen = {}                                -- unit -> its spawns so far (STOREQ.sawSpawn: any game, every spawn)
local noted = {}                              -- event -> the units it takes off (STOREQ.note: the Spaceport's removals)

local function client() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function st()
    local Q = D and D.storeQ
    if not Q and D then
        -- q: waiting, in the order they came; checks: fired, read back on their own clock; chainAt: the last of each
        -- chain fired from here; batch: one pass's tallies (flush alone starts one); drops: what's tallied outside one
        Q = { q = {}, checks = {}, bombers = {}, said = {}, chainAt = {}, batch = nil, drops = nil, shut = false }
        D.storeQ = Q
    end
    return Q
end
-- this game alone: the host's own copy (never sent again), a joiner's held one as hostEvent fires it
local function here(name)
    local f = (COOP and COOP.eventHere) or rawEvent or SV_Event
    if type(f) ~= "function" then return -5 end
    local ok, r = pcall(f, name)
    return ok and r or -5
end
local function errText(r) return r == 1 and "fired" or ("not fired: " .. tostring(SV_ERR and SV_ERR[r] or r)) end
-- a unit's planes alive now (a removal's effect: ALIVE.fresh, asked whatever's kept)
local function aliveOf(u)
    local ok, n = pcall(function()
        if ALIVE and ALIVE.fresh then return ALIVE.fresh(u) end
        return SV_UnitAlive(u)
    end)
    n = ok and tonumber(n) or nil
    if n == -7 then return 0 end                -- (off this game's list)
    return (n and n >= 0) and n or nil
end
-- (a bomber flight's watch, every tick) ALIVE's kept answer, up to a second old, within the tick's ask budget (lag-2)
local function aliveKept(u, now)
    local ok, n = pcall(function()
        if ALIVE and ALIVE.ask then return ALIVE.ask(u, now, 1.0) end
        return SV_UnitAlive(u)
    end)
    n = ok and tonumber(n) or nil
    if n == -7 then return 0 end
    return (n and n >= 0) and n or nil
end

---------------------------------------------------------------------------------------------------- the gate
-- This game's own events can take (its landing minigames over): false, and why, while its landing STORE is open
-- (D.musicHold: solo the game's pause down at the airfield, co-op the landing menu on screen; it lets go ~2.5 s after the
-- menu closes) or it's down at the airfield with no STORE yet this visit (on short final, landing and taxiing in: the
-- Landing and SeamlessIn minigames, which nothing here sees), and for GATE_S after either. Asked every tick (STOREQ.tick,
-- the shuttle's replay), so a visit is seen from its start and a STORE shut before anything needs the gate still counts.
-- G.spell counts the gate's closed spells (a new one each time it shuts after being open).
function STOREQ.gate(now)
    local G = SPC.gate
    if not G then G = {}; SPC.gate = G end
    if not D then return true, nil end
    local on, up = playerOnAirfield(), D.musicHold == 1
    if on and not G.on then G.seen = false end          -- (a visit to the airfield starts: its STORE to come)
    G.on = on
    if up then G.seen = true end
    local why = up and "your landing STORE is open" or (on and not G.seen) and "you're down at the airfield, your STORE not open yet" or nil
    if why then G.busyAt, G.after = now, up and "your landing STORE closed a moment ago" or "you left the airfield a moment ago" end
    local open = not (G.busyAt and now - G.busyAt < GATE_S)
    if not open and G.wasOpen ~= false then G.spell = (G.spell or 0) + 1 end
    G.wasOpen = open
    if not open then return false, why or G.after end
    return true, nil
end
SPC.storeShut = STOREQ.gate                            -- (its old name: the shuttle's replay, the Spaceport's relaunch)

---------------------------------------------------------------------------------------------------- the rules
-- Each one-shot event that changes the world and is safe to run twice (tools/survival_events*.py: what its records do;
-- docs/re/COOP.md section 13 has the table): `host` fired again on the host or a solo game, `join` held on a joiner,
-- `own` each player's own (fired again on any game); `unit` the unit(s) it acts on (spawned again since: dropped);
-- `flag` = { name, value } it sets, `counter` a flag it adds 1 to, `gone` its unit(s) read 0 alive once it's done
-- ("before": a switch-off, gone only by a recycle: read before a fire, never after); `undo` the events that undo it (a
-- list of patterns); `chain` what it goes in order with besides its units, `offset` its time on that chain's clock (the
-- gap kept from the one before it, from `spaceFrom` on); `orders` waits for its flight's own orders; `throttle` /
-- `pressure` the attack throttle's (a boss's end puts ATTACK_BASE back: a newer preset fired again after it).
local function pool(nn) return type(poolUnit) == "function" and poolUnit(tonumber(nn)) or nil end
local function bomber(nn)
    local p = CFG.airfield and CFG.airfield.bombers and CFG.airfield.bombers.pool
    return p and p[tonumber(nn)] or nil
end
local function sp(key) return function() local c = CFG.specials and CFG.specials[key]; return c and c.unit end end
local function valkaEml() local c = CFG.specials and CFG.specials.valka; return c and c.eml_unit end
local function alicorn() return SPC.alicornUnit or "SV_Unit_Alicorn" end
local function awacs() local a = CFG.allies and CFG.allies.awacs; return a and a.unit end
-- (survival_events.py build_heavy) each heavy flight's route and each of its planes' loops: a counter of its own
local function routeCount(nn) return string.format("SV_BRoute_%02dR", tonumber(nn)) end
local function loopCount(nn, L) return string.format("SV_BRoute_%02d%s", tonumber(nn), tostring(L)) end
local function shuttleT() local c = CFG.specials and CFG.specials.shuttle; return c and tonumber(c.countdown_s) end
local function boostS()
    local c = CFG.specials and CFG.specials.spaceport
    local r = c and c.retake and c.retake.rockets
    return tonumber(r and r.boost_s) or 12
end
local function rocket(L) return "rocket" .. tostring(L) end
-- the frees: undone by a newer hold of that flight (or plane), whichever system's (a Wolf trap's, the director's, a decoy)
local function freeUndo(nn, L)
    return { L and ("^RE_SV_WolfHold_" .. nn .. L .. "$") or ("^RE_SV_WolfHold_" .. nn .. "%u$"),
             "^RE_SV_DirHold_" .. nn .. "$", "^RE_SV_Decoy_" .. nn .. "$" }
end
local RULES = {
    { pat = "^RE_SV_AnomalyEnd$", kind = "AnomalyEnd", host = true, join = true, unit = sp("anomaly"), flag = { "SV_AnomalyUp", 0 },
      chain = "throttle", throttle = true },
    { pat = "^RE_SV_ValkaEnd$", kind = "ValkaEnd", host = true, join = true, unit = sp("valka"), flag = { "SV_ValkaUp", 0 },
      chain = "throttle", throttle = true },
    { pat = "^RE_SV_ValkaChargeOff$", kind = "ValkaChargeOff", host = true, join = true, unit = sp("valka"),
      undo = function() return { "^RE_SV_ValkaChargeOn$" } end },
    { pat = "^RE_SV_ValkaAlertOff$", kind = "ValkaAlertOff", host = true, join = true, unit = sp("valka"),
      undo = function() return { "^RE_SV_ValkaAlertOn$" } end },
    { pat = "^RE_SV_AlcnAlertOff$", kind = "AlcnAlertOff", host = true, join = true, unit = alicorn,
      undo = function() return { "^RE_SV_AlcnAlertOn$" } end },
    { pat = "^RE_SV_AnomalyFieldOff$", kind = "AnomalyFieldOff", own = true, unit = sp("anomaly"),
      undo = function() return { "^RE_SV_AnomalyFieldOn$" } end },
    { pat = "^RE_SV_WolfFree_(%d%d)(%u)$", kind = "WolfFree", host = true, join = true, unit = pool, orders = true,
      undo = function(nn, L) return freeUndo(nn, L) end },
    { pat = "^RE_SV_DirFree_(%d%d)$", kind = "DirFree", host = true, join = true, unit = pool, orders = true,
      undo = function(nn) return freeUndo(nn, nil) end },
    { pat = "^RE_SV_DecoyEnd_(%d%d)$", kind = "DecoyEnd", host = true, unit = pool, orders = true,
      undo = function(nn) return freeUndo(nn, nil) end },
    { pat = "^RE_SV_Escort_(%d%d)$", kind = "Escort", host = true, join = true, unit = pool, orders = true },
    { pat = "^RE_SV_Strike%w+_(%d%d)$", kind = "Strike", host = true, unit = bomber },
    { pat = "^RE_SV_Pressure%u$", kind = "Pressure", host = true, join = true, chain = "throttle", pressure = true,
      undo = function() return { "^RE_SV_Pressure%u$" } end },
    { pat = "^RE_SV_HeavyRoute_(%d%d)%u$", kind = "HeavyRoute", host = true, unit = bomber, counter = routeCount },
    { pat = "^RE_SV_HeavyLoop_(%d%d)(%u)%u$", kind = "HeavyLoop", host = true, unit = bomber, counter = loopCount },
    { pat = "^RE_SV_AwacsHome$", kind = "AwacsHome", host = true, join = true, unit = awacs, flag = { "SV_AwacsHome", 1 } },
    { pat = "^RE_SV_AwacsRemove$", kind = "AwacsRemove", host = true, join = true, unit = awacs, flag = { "SV_AwacsAir", 0 } },
    { pat = "^RE_SV_AlcnRemove$", kind = "AlcnRemove", host = true, join = true, unit = alicorn, gone = true },
    { pat = "^RE_SV_ValkaEmlRemove$", kind = "ValkaEmlRemove", host = true, join = true, unit = valkaEml, gone = true },
    { pat = "^RE_SV_LcacRemove(%u)$", kind = "LcacRemove", host = true, join = true, gone = true,
      unit = function(l) return "SV_Unit_Lcac" .. l end },
    { pat = "^RE_SV_LcacTroopsRemove(%u)(%w)$", kind = "LcacTroopsRemove", host = true, join = true, gone = true,
      unit = function(l, k) return "SV_Unit_LcacTroops" .. l .. k end },
    { pat = "^RE_SV_FlightOff_(%d%d)$", kind = "FlightOff", host = true, join = true, unit = pool, gone = "before" },
    -- the Spaceport's (survival_events.py sp_craft: a wave's craft SV_Unit_SpLcac<g><w>, its troops SV_Unit_SpTroops<g><w><c>;
    -- the fleet, garrison, island and rockets noted by sv_spaceport.lua at its load: the same on every game)
    { pat = "^RE_SV_SpLcacRemove(%w+)$", kind = "SpRemove", host = true, join = true, gone = true,
      unit = function(x) return "SV_Unit_SpLcac" .. x end },
    { pat = "^RE_SV_SpTroopsRemove(%w+)$", kind = "SpRemove", host = true, join = true, gone = true,
      unit = function(x) return "SV_Unit_SpTroops" .. x end },
    { pat = "^RE_SV_Sp%a+Remove$", kind = "SpRemove", host = true, join = true, gone = true, noted = true },
    { pat = "^RE_SV_BomberRetask_(%d%d)$", kind = "BomberRetask", join = true, unit = bomber },   -- (the host's: the shuttle's)
    { pat = "^RE_SV_ShuttleT_(%d+)$", kind = "ShuttleT", join = true, shuttle = true, chain = "ShuttleT", spaceFrom = -4,
      offset = function(s) local T = shuttleT(); return (T and tonumber(s)) and (tonumber(s) - T) or nil end },
    { pat = "^RE_SV_SpRocketLaunch(%u)$", kind = "SpRocketLaunch", join = true, chain = rocket, offset = function() return 0 end },
    { pat = "^RE_SV_SpRocketBoost(%u)$", kind = "SpRocketBoost", join = true, chain = rocket, offset = function() return boostS() end },
}
STOREQ.RULES = RULES
local HERE = { kind = "Here", pat = "" }              -- (STOREQ.here's: its units given)
-- the shuttle's countdown seconds a joiner fires late (T its liftoff): T-20 its MinHealth (it can't die from then: a
-- copy left mortal can be shot down here and its standing() records never run), T-14 the ignition, T-4 onto its path, T
-- the climb and its flags, T+7 the focus camera off (T-2's, if it came before the gate shut), T+13 the second leg, T+30
-- the boost off
local function shuttleKeep(sec)
    local T = shuttleT()
    sec = tonumber(sec)
    if not (T and sec) then return false end
    for _, d in ipairs({ -20, -14, -4, 0, 7, 13, 30 }) do if sec == T + d then return true end end
    return false
end
STOREQ.shuttleKeep = shuttleKeep
local function match(name)
    for _, rule in ipairs(RULES) do
        local caps = { name:match(rule.pat) }
        if caps[1] ~= nil then return rule, caps end      -- (a pattern with no captures: the name itself)
    end
    return nil, nil
end
STOREQ.match = match
local function call(f, caps)
    if type(f) ~= "function" then return f end
    local ok, v = pcall(f, table.unpack(caps or {}))
    return ok and v or nil
end
local function unitsOf(rule, caps, name)
    local u
    if rule.noted then u = noted[name] elseif rule.unit then u = call(rule.unit, caps) end
    if type(u) == "string" then return { u } end
    return type(u) == "table" and u or nil
end
local function keysOf(chain, units)
    local t = {}
    if chain then t[#t + 1] = "c:" .. tostring(chain) end
    for _, u in ipairs(units or {}) do t[#t + 1] = "u:" .. u end
    return t
end
-- (the Spaceport's removals, sv_spaceport.lua at its load and as it fires them) the units an event takes off
function STOREQ.note(name, units)
    if type(name) == "string" and type(units) == "table" then
        local t = {}
        for _, u in ipairs(units) do if type(u) == "string" then t[#t + 1] = u end end
        noted[name] = t
    end
end
-- (ALIVE.spawned: every spawn on any game; a spawn's caller may say it again the same moment: counted once)
local genAt = {}
function STOREQ.sawSpawn(unit, r)
    if type(unit) == "string" and tonumber(r) and tonumber(r) > 0 and genAt[unit] ~= os.clock() then
        gen[unit], genAt[unit] = (gen[unit] or 0) + 1, os.clock()
    end
end
local function gens(units)
    local t = {}
    for _, u in ipairs(units or {}) do t[u] = gen[u] or 0 end
    return t
end

---------------------------------------------------------------------------------------------------- the queue
-- a pass's tally (flush starts it as the gate opens); one outside a pass (a countdown second dropped, an undo, a late
-- fire with the gate shut) goes into Q.drops, counted into the next pass or said as the gate opens
local function tally(Q, kind, what)
    local b = Q.batch
    if not b then b = Q.drops; if not b then b = { kinds = {}, order = {} }; Q.drops = b end end
    local k = b.kinds[kind]
    if not k then k = {}; b.kinds[kind] = k; b.order[#b.order + 1] = kind end
    k[what] = (k[what] or 0) + 1
    return k[what]
end
-- once per kind (and what) per closed spell or queue pass, with the count so far
local function sayOnce(Q, key, msg)
    local n = (Q.said[key] or 0) + 1
    Q.said[key] = n
    if n == 1 then log(msg) end
end
local function summary(b)
    if not b then return end
    local parts = {}
    for _, kind in ipairs(b.order) do
        local k, sub = b.kinds[kind], {}
        for _, w in ipairs({ "took", "fired", "unread", "already", "failed", "refused", "late", "dropped" }) do
            if k[w] then sub[#sub + 1] = w .. " " .. k[w] end
        end
        if #sub > 0 then parts[#parts + 1] = kind .. " (" .. table.concat(sub, ", ") .. ")" end
    end
    if #parts > 0 then log("storeq: done here: " .. table.concat(parts, "; ")) end
end
local function counterOf(e)
    local f = svFlags()
    local v = f and e.counter and tonumber(f[e.counter])
    return v
end
-- whether e's effect is in here: true, false, or nil (nothing to read)
local function took(e)
    local rule = e.rule
    if rule.flag then
        local f = svFlags()
        local v = f and tonumber(f[rule.flag[1]])
        if v == nil then return nil end
        return v == rule.flag[2], string.format("%s %s", rule.flag[1], tostring(v))
    end
    if e.counter then
        local v = counterOf(e)
        if v == nil or e.c0 == nil then return nil end
        return v > e.c0, string.format("%s %s, was %s", e.counter, tostring(v), tostring(e.c0))
    end
    if rule.gone and e.units and #e.units > 0 then
        local up, unknown = 0, false
        for _, u in ipairs(e.units) do
            local n = aliveOf(u)
            if n == nil then unknown = true else up = up + n end
        end
        if up > 0 then return false, up .. " alive" end
        if unknown then return nil end
        return true, "none alive"
    end
    return nil
end
-- how = "again" (this game's own, fired again), "held" (a joiner's, the gate closed), "behind" (a joiner's, the gate
-- open, behind one of its unit or chain still held or read back)
local function enqueue(name, rule, caps, now, why, how, c0, units)
    local Q = st()
    if not Q then return end
    units = units or unitsOf(rule, caps, name)
    local chain = call(rule.chain, caps)
    local e = { name = name, rule = rule, kind = rule.kind, at = now, units = units, gen = gens(units), why = why, how = how,
                tries = 0, spell = SPC.gate and SPC.gate.spell or 0, chain = chain, offset = tonumber(call(rule.offset, caps)),
                keys = keysOf(chain, units) }
    if rule.counter then e.counter = call(rule.counter, caps); e.c0 = c0 end
    if rule.undo then
        local p = call(rule.undo, caps)
        e.undo = type(p) == "table" and p or nil
    end
    Q.q[#Q.q + 1] = e
    if #Q.q > Q_MAX then table.remove(Q.q, 1) end            -- (bounded: the oldest goes)
    local key = "q" .. rule.kind .. "/" .. how .. "/" .. tostring(e.spell)
    local n = (Q.said[key] or 0) + 1
    Q.said[key] = n
    if n == 1 then
        if how == "held" then
            log(string.format("storeq: the host's %s held here: %s; fired here once it's shut (%s: the first held this time)",
                name, tostring(why), rule.kind))
        elseif how == "behind" then
            log(string.format("storeq: the host's %s goes behind what's held here: %s (%s: the first this time)",
                name, tostring(why), rule.kind))
        else
            log(string.format("storeq: %s fired while %s: fired again here once it's shut, %s (%s: the first this time)",
                name, tostring(why), (rule.flag or rule.counter or rule.gone) and "unless it took after all" or "whatever",
                rule.kind))
        end
    end
end
local function undone(e, name)
    for _, p in ipairs(e.undo or {}) do if name:match(p) then return true end end
    return false
end
-- an event fired or forwarded here: the queued ones it undoes dropped (a hold after a free, a newer preset, ...)
local function undoBy(name)
    local Q = D and D.storeQ
    if not Q then return end
    for _, list in ipairs({ Q.q, Q.checks }) do
        for i = #list, 1, -1 do
            local e = list[i]
            if e.undo and undone(e, name) then
                table.remove(list, i)
                if tally(Q, e.kind, "dropped") == 1 then
                    log(string.format("storeq: %s not fired %shere: %s came after it", e.name, e.how == "again" and "again " or "", name))
                end
            end
        end
    end
end
STOREQ.undo = undoBy
local function staleWhy(e, now)
    for _, u in ipairs(e.units or {}) do
        if (gen[u] or 0) ~= (e.gen[u] or 0) then return u .. " spawned again since" end
    end
    if e.how == "again" and now - e.at > KEEP_S then return string.format("%.0f s old", now - e.at) end
    return nil
end
-- (a timed chain's) when one at `offset` on it may go: the last of its chain fired here, plus their offsets' difference
local function goAt(Q, chain, offset, rule)
    local ca = chain and Q.chainAt[chain]
    if not (ca and offset and ca.offset and ca.offset >= (rule.spaceFrom or -math.huge) and offset > ca.offset) then return nil end
    return ca.at + (offset - ca.offset), ca
end
-- a flight's free or escort: its flight's own orders first (ordersTick's D.orders, cleared once SV_Up_NN reads 1, 5 s after
-- RE_SV_FlightOrders_NN at the least), as on time; ORDERS_WAIT_S at most, counted from your takeoff
local function ordersWait(Q, e, now)
    if not (e.rule.orders and D and type(D.orders) == "table") then return false end
    for _, u in ipairs(e.units or {}) do
        if D.orders[u] ~= nil then
            if playerOnAirfield() or not e.ordersSince then e.ordersSince = now end
            if now - e.ordersSince < ORDERS_WAIT_S then
                sayOnce(Q, "ow/" .. e.name .. "/" .. tostring(e.spell), string.format("storeq: %s waits here for %s's own orders "
                    .. "first (RE_SV_FlightOrders_NN: as it went on time)", e.name, u))
                return true
            end
        end
    end
    return false
end
-- a bomber flight being given its orders here: a queued route or loop of its waits (stock order: orders, then the path)
local function bomberBusy(Q, e, now)
    for _, u in ipairs(e.units or {}) do
        local b = Q.bombers[u]
        if b and ((b.firedAt and now < b.firedAt + 3) or (not b.firedAt and b.lost ~= false and now < b.checkAt)) then return true end
    end
    return false
end
local WORD_AGAIN = { took = "took here", already = "not fired again: it took after all", fired = "fired again here",
                     unread = "fired again here, whether it took isn't readable", refused = "not fired again here" }
local WORD_HELD = { took = "took here", already = "not fired here: its effect is in already",
                    unread = "fired here, whether it took isn't readable", refused = "not fired here" }
local function finish(Q, e, what, detail, now)
    if tally(Q, e.kind, what) ~= 1 then return end
    local text
    if what == "failed" then text = string.format("never took here in %d tries", e.tries)
    elseif what == "late" then text = string.format("fired here %.0f s after it came, this game's STORE still open (as before)", now - e.at)
    elseif what == "fired" and e.how ~= "again" then text = string.format("fired here (held %.0f s)", now - e.at)
    else text = (e.how == "again" and WORD_AGAIN or WORD_HELD)[what] or what end
    log(string.format("storeq: %s %s%s (%s: the first this time)", e.name, text, detail and (" (" .. detail .. ")") or "", e.kind))
end
local function queuedKind(Q, kind)
    for _, x in ipairs(Q.q) do if x.kind == kind then return true end end
    return false
end
-- after one fired here: the throttle's last preset noted; a boss's end, which puts ATTACK_BASE back, followed by the
-- preset that came after it (fired on time, or forwarded then), unless one's still queued to come after it anyway
local function afterFire(Q, e, now)
    if e.rule.pressure then Q.lastPressure = { name = e.name, at = e.at } end
    if not e.rule.throttle then return end
    local P = Q.lastPressure
    if P and P.at > e.at and not queuedKind(Q, "Pressure") then
        local rp = here(P.name)
        sayOnce(Q, "thr/" .. e.kind .. "/" .. tostring(e.spell), string.format("storeq: %s fired again here after %s: it came "
            .. "after it, and both set the attack throttle (%s)", P.name, e.name, errText(rp)))
    end
end
-- the ones fired and read back on their own clock (CHECK_S on): took, or fired again (TRIES in all) once the gate's open
local function checksTick(Q, now, open)
    if #Q.checks == 0 then return end
    local keep = {}
    for _, e in ipairs(Q.checks) do
        local stay = true
        if now >= e.checkAt then
            local stale = staleWhy(e, now)
            local t, what = nil, nil
            if not stale then t, what = took(e) end
            if stale then
                stay = false
                if tally(Q, e.kind, "dropped") == 1 then log(string.format("storeq: %s not read back here: %s", e.name, stale)) end
            elseif t == true then stay = false; finish(Q, e, "took", what, now)
            elseif t == nil then stay = false; finish(Q, e, "unread", what, now)
            elseif e.tries >= TRIES then stay = false; finish(Q, e, "failed", what, now)
            elseif open then
                local r = here(e.name)
                e.tries, e.checkAt = e.tries + 1, now + CHECK_S
                log(string.format("storeq: %s didn't take here (%s): fired here again, try %d of %d (%s)", e.name, tostring(what),
                    e.tries, TRIES, errText(r)))
                if r == 1 then afterFire(Q, e, now) else stay = false; finish(Q, e, "refused", errText(r), now) end
            elseif e.waitSaid ~= (SPC.gate or {}).spell then
                e.waitSaid = (SPC.gate or {}).spell
                log(string.format("storeq: %s didn't take here (%s): again once this game's events can take (try %d of %d)",
                    e.name, tostring(what), e.tries + 1, TRIES))
            end
        end
        if stay then keep[#keep + 1] = e end
    end
    Q.checks = keep
end
-- one fired here from the queue (its effect read first); true when it's to be read back (Q.checks: what shares its unit
-- or chain waits for it)
local function fireEntry(Q, e, now, late)
    local rule = e.rule
    if rule.gone or rule.flag or (e.counter and e.c0 ~= nil) then
        local t0, what0 = took(e)                                  -- (its effect in already?)
        if t0 == true then finish(Q, e, "already", what0, now); return end
    end
    if e.counter and e.c0 == nil then e.c0 = counterOf(e) end    -- (not read at its fire: from before this one)
    local r = here(e.name)
    e.tries = e.tries + 1
    if r == 1 then
        if e.offset and e.chain then Q.chainAt[e.chain] = { at = now, offset = e.offset, name = e.name } end
        afterFire(Q, e, now)
    end
    if late then
        finish(Q, e, "late", errText(r), now)
    elseif r ~= 1 then
        finish(Q, e, "refused", errText(r), now)
    elseif rule.flag or e.counter or rule.gone == true then
        e.checkAt = now + CHECK_S
        Q.checks[#Q.checks + 1] = e
        if #Q.checks > Q_MAX then table.remove(Q.checks, 1) end
        if e.tries == 1 and tally(Q, e.kind, "sent") == 1 then
            if e.how == "again" then
                log(string.format("storeq: %s fired again here, %.0f s after it was lost (%s); its effect read back in %d s",
                    e.name, now - e.at, tostring(e.why), CHECK_S))
            else
                log(string.format("storeq: %s fired here (held %.0f s: %s); its effect read back in %d s", e.name, now - e.at,
                    tostring(e.why), CHECK_S))
            end
        end
        return true
    else
        finish(Q, e, "fired", nil, now)
    end
end
local function startBatch(Q, edge)
    local kinds, ks = {}, {}
    for _, list in ipairs({ Q.q, Q.checks }) do for _, x in ipairs(list) do kinds[x.kind] = (kinds[x.kind] or 0) + 1 end end
    for k, c in pairs(kinds) do ks[#ks + 1] = k .. " " .. c end
    table.sort(ks)
    log(string.format(edge and "storeq: this game's events can take again: %d to fire here in order (%s)"
        or "storeq: %d more to fire here in order, behind what fired just before them (%s)", #Q.q + #Q.checks, table.concat(ks, ", ")))
    Q.batch = Q.drops or { kinds = {}, order = {} }               -- (what was dropped while it was shut, counted in)
    Q.drops = nil
end
local function flush(now, open)
    local Q = st()
    if not Q then return end
    local edge = open and Q.shut
    Q.shut = not open
    if open and not Q.batch then
        if #Q.q > 0 or #Q.checks > 0 then startBatch(Q, edge)
        elseif Q.drops then summary(Q.drops); Q.drops = nil end   -- (only drops this spell: said as it opens)
    end
    checksTick(Q, now, open)
    -- in the order they came, what shares a unit or a chain with one before it still waiting (or read back) after it
    local blocked, fired, i = {}, 0, 1
    for _, c in ipairs(Q.checks) do for _, k in ipairs(c.keys) do blocked[k] = true end end
    while Q.q[i] and fired < PER_TICK do
        local e, done = Q.q[i], false
        local stale = staleWhy(e, now)
        local held = false
        for _, k in ipairs(e.keys) do if blocked[k] then held = true; break end end
        if stale then
            done = true
            if tally(Q, e.kind, "dropped") == 1 then
                log(string.format("storeq: %s not fired %shere: %s", e.name, e.how == "again" and "again " or "", stale))
            end
        elseif not held then
            -- (a joiner's: HOLD_MAX_S at most while the gate stays shut, then fired whatever, as before)
            local late = not open and (e.how ~= "again" or client()) and now - e.at >= HOLD_MAX_S
            local t = (open or late) and goAt(Q, e.chain, e.offset, e.rule)
            if (open or late) and not (t and now < t) and not bomberBusy(Q, e, now) and not ordersWait(Q, e, now) then
                done, fired = true, fired + 1
                if fireEntry(Q, e, now, late) then for _, k in ipairs(e.keys) do blocked[k] = true end end
            end
        end
        if done then table.remove(Q.q, i)
        else
            for _, k in ipairs(e.keys) do blocked[k] = true end
            i = i + 1
        end
    end
    if Q.batch and #Q.q == 0 and #Q.checks == 0 then summary(Q.batch); Q.batch = nil end
end

---------------------------------------------------------------------------------------------------- the hooks
-- (sv_coop.lua's SV_Event wrapper, before the native) a counter rule's count before its fire
function STOREQ.before(name)
    if not D then return nil end
    local rule, caps = match(tostring(name))
    if not (rule and rule.counter) then return nil end
    local f = svFlags()
    local key = call(rule.counter, caps)
    return f and key and tonumber(f[key]) or nil
end
-- (... after it) an event of RULES this game fired while its gate was closed: to be fired again here once it's open
function STOREQ.fired(name, r, c0)
    if not D then return end
    name = tostring(name)
    if r ~= 1 then return end                             -- (not dispatched: nothing the STORE could eat, nor undone by it)
    undoBy(name)
    local rule, caps = match(name)
    if not rule then return end
    if not (rule.own or (rule.host and not client())) then return end
    local now = D.now or 0
    local open, why = STOREQ.gate(now)
    if open then
        if rule.pressure then st().lastPressure = { name = name, at = now } end   -- (it took: a boss's end fired late follows it)
        return
    end
    enqueue(name, rule, caps, now, why, "again", c0)
end
-- (a joiner, the gate open) why one of the host's must go behind what's held here: one of its unit or chain still held
-- or read back, or the last of its timed chain fired here too short a time ago; nil: fired now
local function behind(Q, rule, caps, name, now)
    local chain, units = call(rule.chain, caps), unitsOf(rule, caps, name)
    local mine = {}
    for _, k in ipairs(keysOf(chain, units)) do mine[k] = true end
    for _, list in ipairs({ Q.q, Q.checks }) do
        for _, e in ipairs(list) do
            for _, k in ipairs(e.keys) do
                if mine[k] then return e.name .. (list == Q.q and " still to fire here before it" or " still read back here") end
            end
        end
    end
    local t, ca = goAt(Q, chain, tonumber(call(rule.offset, caps)), rule)
    if t and now < t then return string.format("%s fired here %.1f s ago, %.0f s before it on the host", ca.name, now - ca.at,
        tonumber(call(rule.offset, caps)) - ca.offset) end
    return nil
end
-- (a joiner's hostEvent) one of the host's events: true when it's held here (this game's gate closed, or one it must
-- follow still to fire), false to fire it now as ever
function STOREQ.forwarded(name)
    if not D then return false end
    name = tostring(name)
    undoBy(name)
    local rule, caps = match(name)
    if not (rule and rule.join) then return false end
    local Q = st()
    local now = D.now or 0
    local open, why = STOREQ.gate(now)
    if rule.shuttle and not shuttleKeep(caps[1]) then
        if open then return false end                     -- (fired now: only what lasts is held)
        tally(Q, "ShuttleT", "dropped")
        sayOnce(Q, "shdrop/" .. tostring(SPC.gate and SPC.gate.spell), string.format("storeq: the host's %s not fired here: %s, "
            .. "and it changes nothing that lasts (the countdown's radio, a sound, the camera's start: not played late)", name, tostring(why)))
        return true
    end
    if open then
        local b = behind(Q, rule, caps, name, now)
        if not b then
            if rule.pressure then Q.lastPressure = { name = name, at = now } end
            return false
        end
        enqueue(name, rule, caps, now, b, "behind")
        return true
    end
    enqueue(name, rule, caps, now, why, "held")
    return true
end
-- (a joiner's own one-shot that changes its world: sv_spaceport.lua SPORT.rkFromHost's end of its copy of a rocket)
-- fired on this game alone now, and again once its gate's open if it's closed now; `units` what it takes off (spawned
-- again since: not fired again, a new retake's)
function STOREQ.here(name, units)
    local r = here(name)
    if not D then return r end
    local ok, err = pcall(function()
        local now = D.now or 0
        local open, why = STOREQ.gate(now)
        if not open and r == 1 then
            local u = nil
            if type(units) == "table" then u = {}; for _, x in ipairs(units) do if type(x) == "string" then u[#u + 1] = x end end end
            enqueue(tostring(name), HERE, {}, now, why, "again", nil, u)
        end
    end)
    if not ok and D.storeQErr ~= tostring(err) then D.storeQErr = tostring(err); log("storeq: error " .. D.storeQErr) end
    return r
end

---------------------------------------------------------------------------------------------------- bomber flights
-- (spawnBomber, before SV_Spawn) its orders' count now: the token STOREQ.bomberUp compares with
function STOREQ.bomberPre(unit)
    local i = BOMBER_INDEX and BOMBER_INDEX[unit]
    local f = i and svFlags()
    return f and tonumber(f[string.format("SV_BOrd_%02d", i)]) or nil
end
-- (spawnBomber, after it: r its aircraft) watched until its orders are in (the count up), or given again
function STOREQ.bomberUp(unit, r, c0, now)
    if client() or not D then return end
    local i = BOMBER_INDEX and BOMBER_INDEX[unit]
    if not (i and tonumber(r) and tonumber(r) > 0) then return end
    if D.shipStrike and D.shipStrike[unit] then return end   -- (its RE_SV_Strike gives its orders: a rule above)
    now = now or D.now or 0
    local open, why = STOREQ.gate(now)
    local Q = st()
    Q.bombers[unit] = { i = i, at = now, c0 = c0, closed = (not open) and why or nil, checkAt = now + BOMBER_CHECK_S,
                        tries = 0, gen = gen[unit] or 0 }
    if not open then
        sayOnce(Q, "bup/" .. tostring(SPC.gate and SPC.gate.spell), string.format("storeq: bomber flight %s appeared while %s: its "
            .. "orders read back in %d s, given again here once this game's events can take", unit, tostring(why), BOMBER_CHECK_S))
    end
end
local function bombersTick(now, open)
    if client() then return end
    local Q = st()
    for unit, b in pairs(Q.bombers) do
        if (gen[unit] or 0) ~= b.gen or (aliveKept(unit, now) or 1) <= 0 then
            Q.bombers[unit] = nil                          -- (spawned again: its own watch; or down)
        elseif now >= b.checkAt and svFlags() == nil then
            if now - b.at > 60 then                        -- (the flags unreadable a minute: nothing to go by)
                Q.bombers[unit] = nil
                if b.closed then log(string.format("storeq: bomber flight %s: its orders not checked (the event package's flags "
                    .. "can't be read here)", unit)) end
            end
        elseif now >= b.checkAt then
            local f = svFlags()
            local key = string.format("SV_BOrd_%02d", b.i)
            local c = f and tonumber(f[key])
            if c ~= nil and b.c0 == nil and b.closed then b.c0 = c end           -- (not read before its spawn: from now)
            if c ~= nil and b.c0 ~= nil then
                if c > b.c0 then
                    if b.tries > 0 or b.closed then
                        log(string.format("storeq: bomber flight %s has its orders here (%s %d%s)", unit, key, c,
                            b.tries > 0 and string.format("; RE_SV_BomberOrders_%02d fired here %d time%s", b.i, b.tries,
                                b.tries == 1 and "" or "s") or ": its appearance's took"))
                    end
                    Q.bombers[unit] = nil
                elseif not open then
                    b.lost = true
                    local spell = (SPC.gate or {}).spell
                    if b.waitSaid ~= spell then
                        b.waitSaid = spell
                        log(string.format("storeq: bomber flight %s without its orders here (%s still %d): given again once "
                            .. "this game's events can take", unit, key, c))
                    end
                elseif b.tries >= TRIES then
                    log(string.format("storeq: bomber flight %s never had its orders here (%s still %d after %d tries)", unit, key, c, b.tries))
                    Q.bombers[unit] = nil
                else
                    b.lost = true
                    local ev = string.format("RE_SV_BomberOrders_%02d", b.i)
                    local rr = here(ev)
                    b.tries, b.checkAt, b.firedAt = b.tries + 1, now + CHECK_S, now
                    local sr = tonumber(f.SV_ShuttleRound)
                    log(string.format("storeq: bomber flight %s appeared without its orders here (%s still %d): %s %s, try %d "
                        .. "of %d (SV_ShuttleRound %s: %s)", unit, key, c, ev, errText(rr), b.tries, TRIES, tostring(sr),
                        (sr or 0) >= 1 and "the shuttle's orders" or "the airfield's"))
                    if rr ~= 1 then Q.bombers[unit] = nil end
                end
            elseif not b.closed then
                Q.bombers[unit] = nil                      -- (not readable, and nothing says it was lost)
            elseif open then
                local sr = f and tonumber(f.SV_ShuttleRound)
                if sr == 0 then
                    local ev = string.format("RE_SV_BomberRetask_%02d", b.i)
                    local rr = here(ev)
                    b.firedAt = now
                    log(string.format("storeq: bomber flight %s appeared while %s: %s %s here (the airfield's orders; whether "
                        .. "they took isn't readable: an event package without SV_BOrd_NN, made before 2026-11-11)", unit,
                        tostring(b.closed), ev, errText(rr)))
                else
                    log(string.format("storeq: bomber flight %s appeared while %s: its orders not given again (SV_ShuttleRound "
                        .. "%s: the shuttle's need the event package with RE_SV_BomberOrders_NN; the shuttle's retasks send it "
                        .. "to the airfield)", unit, tostring(b.closed), tostring(sr)))
                end
                Q.bombers[unit] = nil
            end
        end
    end
end

-- every tick (roundsTick's start: the host's, a solo game's; a joiner's clientRounds once its level is ready); the
-- gate's error (playerOnAirfield's) taken as open: everything fires as it did before this piece
function STOREQ.tick(now)
    if not D then return end
    local okG, open = pcall(STOREQ.gate, now)
    if not okG then
        if D.storeQErr ~= tostring(open) then D.storeQErr = tostring(open); log("storeq: gate error " .. D.storeQErr) end
        open = true
    end
    local okB, errB = pcall(bombersTick, now, open)
    if not okB and D.storeQErr ~= tostring(errB) then D.storeQErr = tostring(errB); log("storeq: bombers error " .. D.storeQErr) end
    local okF, errF = pcall(flush, now, open)
    if not okF and D.storeQErr ~= tostring(errF) then D.storeQErr = tostring(errF); log("storeq: error " .. D.storeQErr) end
end
-- (tests, the log) what's still to fire or be read back, and the first still to fire's name
function STOREQ.pending()
    local Q = D and D.storeQ
    if not Q then return 0, nil end
    return #Q.q + #Q.checks, (Q.q[1] and Q.q[1].name) or (Q.checks[1] and Q.checks[1].name) or nil
end
end
