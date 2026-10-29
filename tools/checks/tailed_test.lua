-- tailed_test.lua <mod dir> <work dir> (run by tools/checks/tailed_test.sh): P5, a harder tailed plane
-- (tools/re/BEHAVIOUR_DIRECTOR.md unit 2), offline:
--   1. the behaviour trees. Scripts/ai/LA_SV_ProvokeNear.lua, LA_SV_Escape.lua and LA_SV_TailChase.lua are built as the
--      game builds them (their Ctor on a recording `self`) and walked by a model of the game's tree runner
--      (tools/re/BEHAVIOUR_NATIVE_LOGIC.md 3-6: the composite stack and child indices, each composite's answer to Failed /
--      Complete / Abort, a RandomSelect's single pick by weight that is never retried, decorators, probabilities). Every
--      pick of every RandomSelect, in every situation (pilot rank 1-5, AI level 1-5, the pursuer 30 m / 50 m / 500 m /
--      1.5 km away when the state began, cobra / kulbit allowed or not, a flare ready or not, mid-band / near the top /
--      near the floor of the unit's altitude band, a KDS front phase or not) must fly a move; the Provoke reactions
--      exactly one, under the 6 s blackout timer. The model first shows it finds the old shapes' faults (a gate straight
--      under a RandomSelect, a failed flare ending its break) and the reason for the opposite gates (a Selector goes on
--      after a composite child that passed its gate);
--   2. the live provoke: provokeWant's merge of a tier and the round's spike (the stricter; the tier's over the spike's;
--      tier_provoke off; the test values; a special's own), enemyProvoke's writes (only what changed), enemySpike's
--      once-per-plane write and its "provoke:" line;
--   3. the tail watch: STATS.tailTick on planes you get behind (its reaction, its states, died / escaped, a flicker
--      dropped, at most watch_max read, no bombers, no special's guard, the sweep's death first, never an episode on or
--      a read of a wreck the sweep hasn't seen down yet, one already defending kept out of the reaction figures, the
--      planes you're likely behind read before nearer ones, an episode still open at the run's end), the round line's
--      and the run line's parts; nothing on a co-op joiner or with tail_watch off.
-- Its log lines also go to <work dir>/test_lua.log, for tailed_test.sh to run tools/checks/stats_report.py on.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end

---------------------------------------------------------------------------------------------------- 1. the trees
print("behaviour trees")
-- A script's Ctor on a recording self: every node with its factory (Instance<X> -> X), args, kind, parent, children.
local function build(src, chunk)
    local nodes, root = {}, nil
    local enum = setmetatable({}, { __index = function(_, k) return k end })
    local env = setmetatable({ CppObjectBase = {}, Inherit = function() return {} end, ELiveAIManeuverSpeedType = enum,
                               EArithmeticKeyOperation = enum, ELiveAIState = enum,
                               FVector = { New = function(x, y, z) return { x, y, z } end } }, { __index = _G })
    local cls = assert(load(src, "=" .. chunk, "t", env))()
    local self = setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^Instance") then
            return function(_, ...) return { factory = k:sub(9), args = { ... } } end
        end
    end })
    function self.GenerateBehavior() end
    function self.EndGenerateBehavior() end
    function self.AddRootComposite(_, name, n)
        n.name, n.kind, n.children = name, "composite", {}
        nodes[name:lower()], root = n, n
    end
    local function add(kind)
        return function(_, parent, name, n)
            local par = assert(nodes[parent:lower()], chunk .. ": undefined parent " .. parent)
            assert(not nodes[name:lower()] and name:lower() ~= "root", chunk .. ": duplicate or reserved name " .. name)
            n.name, n.kind, n.parent, n.children = name, kind, par, {}
            par.children[#par.children + 1] = n
            nodes[name:lower()] = n
        end
    end
    self.AddComposite, self.AddTask, self.AddDecorator, self.AddProbability = add("composite"), add("task"), add("decorator"), add("probability")
    cls.Ctor(self)
    return root
end

-- The runner (BEHAVIOUR_NATIVE_LOGIC.md 3.2-3.3, 4, 5, 6). Tasks finish at once: Complete, or Failed for ActivateFlares
-- with no flare ready (BEHAVIOUR_NATIVE_MOVE.md). choose(rs, n): which of a RandomSelect's n weighted candidates it picks.
local ANSWER = {                                  -- OnChildFinished: Failed, Complete, Abort -> next / leave / end
    Selector = { "next", "leave", "end" }, LaxSelector = { "next", "leave", "next" },
    Sequencer = { "leave", "next", "end" }, LaxSequencer = { "leave", "next", "next" },
    Continuation = { "next", "next", "end" }, LaxContinuation = { "next", "next", "next" },
    RandomSelect = { "next", "next", "next" },    -- ("its parent continues": it never pushed itself)
}
local function compare(a, op, b)
    if op == "Less" then return a < b elseif op == "LessOrEqual" then return a <= b
    elseif op == "Greater" then return a > b elseif op == "GreaterOrEqual" then return a >= b
    elseif op == "Equal" then return a == b elseif op == "NotEqual" then return a ~= b end
    error("op " .. tostring(op))
end
local function decorator(n, sit)
    local f, a = n.factory, n.args
    if f == "DecoratorBlackboardFloat" then return compare(assert(sit[a[1]], a[1]), a[3], a[2])
    elseif f == "DecoratorCanCobra" then if a[1] then return sit.cobra else return not sit.cobra end
    elseif f == "DecoratorCanKulbit" then if a[1] then return sit.kulbit else return not sit.kulbit end
    elseif f == "DecoratorUnitAltitudeComparison" then                -- above: z > floor + margin, else z < top - margin
        if a[1] then return sit.alt ~= "low" else return sit.alt ~= "high" end
    elseif f == "DecoratorIsKDSP1" then if a[1] then return sit.kds else return not sit.kds end end
    error("decorator " .. f .. " not modelled")
end
local function weight(n, sit)
    local f, a = n.factory, n.args
    if f == "WeightProbabilityPilotRank" then return a[sit.rank]
    elseif f == "WeightProbabilityAILevel" then return a[sit.ai]
    elseif f == "WeightProbability" then return a[1] end
    error("probability " .. f .. " not modelled")
end
local function walk(root, sit, choose)
    local stack, idx, ran = {}, {}, {}
    local function pop() local c = stack[#stack]; stack[#stack] = nil; return c end
    local function select(c)
        if c.factory == "RandomSelect" then
            local cands = {}
            for _, ch in ipairs(c.children) do
                if ch.kind == "probability" then
                    if weight(ch, sit) > 0 and ch.children[1] then cands[#cands + 1] = ch.children[1] end
                else
                    cands[#cands + 1] = ch                       -- (a plain child weighs 10)
                end
            end
            if #cands == 0 then return nil end
            return cands[choose(c, #cands)]
        end
        assert(ANSWER[c.factory], "composite " .. tostring(c.factory) .. " not modelled")
        local i = idx[c] or 0
        local ch = c.children[i + 1]
        if not ch then return nil end
        stack[#stack + 1], idx[c] = c, i + 1
        return ch
    end
    local function enter(c)                       -- a composite's next child; exhausted: the one under it continues
        while c do
            local ch = select(c)
            if ch then return ch end
            c = pop()
        end
        return nil
    end
    local function finish(r, node)               -- the result goes to the nearest composite above it
        local c = node.parent
        while c and c.kind ~= "composite" do c = c.parent end
        if not c then return nil end
        local a = ANSWER[c.factory][r]
        if a == "end" then return nil end
        if a == "leave" then pop() end
        return enter(pop())
    end
    local node, guard = root, 0
    while node do
        guard = guard + 1
        assert(guard < 5000, "the walker looped")
        if node.kind == "composite" then node = enter(node)
        elseif node.kind == "task" then
            ran[#ran + 1] = node
            local r = (node.factory == "ActivateFlares" and not sit.flares) and 1 or 2
            node = finish(r, node)
        elseif node.kind == "decorator" then
            if decorator(node, sit) then node = node.children[1] else node = finish(1, node) end
        else
            node = nil                                -- (a probability reached any other way ends the tick)
        end
    end
    return ran
end
-- Every pick sequence of a tree in one situation: a list of the tasks each one ran.
local function allPaths(root, sit)
    local out = {}
    local function go(prefix)
        local seen, pos = {}, 0
        local ran = walk(root, sit, function(_, n) pos = pos + 1; seen[pos] = n; return prefix[pos] or 1 end)
        out[#out + 1] = ran
        for i = #prefix + 1, pos do
            for o = 2, seen[i] do
                local np = {}
                for j = 1, i - 1 do np[j] = prefix[j] or 1 end
                np[i] = o
                go(np)
            end
        end
    end
    go({})
    return out
end
local DUR = { ManeuverRoll = 6, ManeuverPitch = 6, ManeuverTurnNormal = 8, ManeuverLevel = 6, ManeuverFlyStraight = 4,
              ManeuverTurnAdvanced = 6, PursuerTarget = 1, MoveAwayFromTarget = 1 }
local function seconds(ran)
    local s = 0
    for _, t in ipairs(ran) do if DUR[t.factory] then s = s + t.args[DUR[t.factory]] end end
    return s
end
local function names(ran) local t = {}; for _, x in ipairs(ran) do t[#t + 1] = x.name end; return table.concat(t, ",") end
local function ranAny(ran, pat) for _, x in ipairs(ran) do if x.name:match(pat) then return true end end return false end
local function moved(ran)
    for _, x in ipairs(ran) do
        if x.factory:match("^Maneuver") or x.factory == "MoveAwayFromTarget" or x.factory == "PursuerTarget" then return true end
    end
    return false
end
local function situations(each)
    for rank = 1, 5 do for ai = 1, 5 do
        for _, d in ipairs({ 3000.0, 5000.0, 50000.0, 150000.0 }) do
            for _, cobra in ipairs({ true, false }) do for _, kulbit in ipairs({ true, false }) do
                for _, flares in ipairs({ true, false }) do for _, alt in ipairs({ "mid", "high", "low" }) do
                    for _, kds in ipairs({ false, true }) do
                        each({ rank = rank, ai = ai, PursuerDistance = d, cobra = cobra, kulbit = kulbit, flares = flares,
                               alt = alt, kds = kds })
                    end
                end end
            end end
        end
    end end
end
local function sitText(s)
    return string.format("rank %d, AI %d, %g cm, cobra %s, kulbit %s, flares %s, %s, kds %s", s.rank, s.ai, s.PursuerDistance,
        tostring(s.cobra), tostring(s.kulbit), tostring(s.flares), s.alt, tostring(s.kds))
end

-- the model on the old shapes (fixtures): it must find what the real scripts no longer do
local FIX_HEAD = 'local F = Inherit(CppObjectBase)\nfunction F:Ctor()\nself:GenerateBehavior()\nself:AddRootComposite("LaxSequencer", self:InstanceLaxSequencer())\n'
local FIX_TAIL = 'self:EndGenerateBehavior()\nend\nreturn F\n'
local ROLL = 'self:InstanceManeuverRoll(1.0, 90.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 0.2, false)'
local oldCobra = build(FIX_HEAD ..
    'self:AddComposite("LaxSequencer", "Pick", self:InstanceRandomSelect())\n' ..
    'self:AddDecorator("Pick", "CanCobra", self:InstanceDecoratorCanCobra(true, true))\n' ..
    'self:AddComposite("CanCobra", "CobraSeq", self:InstanceSequencer())\n' ..
    'self:AddTask("CobraSeq", "Cobra", self:InstanceManeuverPugachevsCobra(false, false))\n' ..
    'self:AddComposite("Pick", "Fallback", self:InstanceSequencer())\n' ..
    'self:AddTask("Fallback", "FB_Roll", ' .. ROLL .. ')\n' .. FIX_TAIL, "old cobra")
local noop = false
for _, ran in ipairs(allPaths(oldCobra, { cobra = false })) do if #ran == 0 then noop = true end end
check(noop, "the model finds the old cobra shape's no-op (a gate straight under a RandomSelect, no post-stall)")
local oldFlare = build(FIX_HEAD ..
    'self:AddComposite("LaxSequencer", "FlareBreak", self:InstanceLaxSequencer())\n' ..
    'self:AddTask("FlareBreak", "Flares", self:InstanceActivateFlares("PursuerActor", true))\n' ..
    'self:AddTask("FlareBreak", "FB_Roll", ' .. ROLL .. ')\n' .. FIX_TAIL, "old flare")
check(#walk(oldFlare, { flares = false }, function() return 1 end) == 1, "the model finds the old flare break's fault (no flare ready: no break)")
local selector = build(FIX_HEAD ..
    'self:AddComposite("LaxSequencer", "Gate", self:InstanceSelector())\n' ..
    'self:AddDecorator("Gate", "Close", self:InstanceDecoratorBlackboardFloat("PursuerDistance", 5000.0, EArithmeticKeyOperation.LessOrEqual, false))\n' ..
    'self:AddComposite("Close", "CloseSeq", self:InstanceSequencer())\n' ..
    'self:AddTask("CloseSeq", "A_Roll", ' .. ROLL .. ')\n' ..
    'self:AddComposite("Gate", "Other", self:InstanceSequencer())\n' ..
    'self:AddTask("Other", "B_Roll", ' .. ROLL .. ')\n' .. FIX_TAIL, "selector")
check(names(walk(selector, { PursuerDistance = 3000.0 }, function() return 1 end)) == "A_Roll,B_Roll",
      "a Selector goes on after a composite child that passed its gate (so a fallback needs the opposite gate)")

-- the real scripts
local function script(name) return build(readAll(MOD .. "/Scripts/ai/" .. name .. ".lua"), name) end
local PN, ES, TC = script("LA_SV_ProvokeNear"), script("LA_SV_Escape"), script("LA_SV_TailChase")
local bad, n, worst = {}, 0, 0
local function fault(what, sit, ran) if #bad < 6 then bad[#bad + 1] = what .. " (" .. sitText(sit) .. "): " .. names(ran) end end
situations(function(sit)
    for _, ran in ipairs(allPaths(PN, sit)) do
        n = n + 1
        local s = seconds(ran)
        worst = math.max(worst, s)
        if not moved(ran) then fault("no move", sit, ran) end
        if s > 5.0 then fault(string.format("%.1f s, past the blackout's 6 s with the decision", s), sit, ran) end
        if ranAny(ran, "^D[RL]_") and sit.PursuerDistance > 5000 then fault("the decel outside 50 m", sit, ran) end
        if ranAny(ran, "^D[RL]_") and ranAny(ran, "^DB[RL]_") then fault("decel and break both", sit, ran) end
        if ranAny(ran, "^Cobra$") and (not sit.cobra or ranAny(ran, "^CF_")) then fault("cobra", sit, ran) end
        if ranAny(ran, "^Kulbit$") and (not sit.kulbit or ranAny(ran, "^KF_")) then fault("kulbit", sit, ran) end
        if ranAny(ran, "^Flares$") and not ranAny(ran, "^F[RL]_") then fault("flares without the break", sit, ran) end
    end
end)
check(#bad == 0, string.format("LA_SV_ProvokeNear: every pick in every situation flies one move, under 5 s (%d walks, longest %.1f s)%s",
      n, worst, #bad > 0 and (": " .. table.concat(bad, " | ")) or ""))
-- what each pick does: with you far behind, the decel pick breaks; a plane without post-stall breaks instead
local function onePath(root, sit, pick)
    for _, ran in ipairs(allPaths(root, sit)) do if ranAny(ran, pick) then return ran end end
    return nil
end
local far = { rank = 4, ai = 2, PursuerDistance = 50000.0, cobra = false, kulbit = false, flares = false, alt = "mid", kds = false }
check(onePath(PN, far, "^DBR_Roll$") and not onePath(PN, far, "^D[RL]_"), "rank 4 at 500 m: the decel pick breaks hard (no 300 km/h turn)")
far.PursuerDistance = 3000.0
check(onePath(PN, far, "^DR_Roll$") and not onePath(PN, far, "^DB[RL]_"), "rank 4 at 30 m: the decel pick brakes and turns")
local ace = { rank = 5, ai = 5, PursuerDistance = 50000.0, cobra = false, kulbit = false, flares = false, alt = "mid", kds = false }
check(onePath(PN, ace, "^CF_Roll$") and onePath(PN, ace, "^KF_Roll$") and not onePath(PN, ace, "^Cobra$"),
      "AI level 5 without post-stall: the cobra and kulbit picks break right / left")
ace.cobra, ace.kulbit = true, true
check(onePath(PN, ace, "^Cobra$") and onePath(PN, ace, "^Kulbit$") and not onePath(PN, ace, "^[CK]F_"), "with post-stall: the cobra and the kulbit")
local fp = onePath(PN, ace, "^Flares$")
check(fp and ranAny(fp, "^F[RL]_Pitch$"), "no flare ready: the flare pick still breaks")

bad, n, worst = {}, 0, 0
situations(function(sit)
    for _, ran in ipairs(allPaths(ES, sit)) do
        n = n + 1
        worst = math.max(worst, seconds(ran))
        if not moved(ran) then fault("no move", sit, ran) end
        if ranAny(ran, "^P[UD]_") or ranAny(ran, "Turn") then
            if not ranAny(ran, "^LeftTurn$") and not ranAny(ran, "^RightTurn$") then fault("the sharp escape without its turn", sit, ran) end
        end
    end
end)
check(#bad == 0, string.format("LA_SV_Escape: every pick in every situation moves; the sharp one always turns (%d walks, longest %.1f s)%s",
      n, worst, #bad > 0 and (": " .. table.concat(bad, " | ")) or ""))
local high = { rank = 5, ai = 2, PursuerDistance = 50000.0, cobra = true, kulbit = true, flares = true, alt = "high", kds = false }
local climbed, sharpOnly = false, 0
for _, ran in ipairs(allPaths(ES, high)) do
    if ranAny(ran, "^PU_") or ranAny(ran, "TurnUp$") then climbed = true end
    if #ran == 1 then sharpOnly = sharpOnly + 1 end
end
check(not climbed and sharpOnly > 0, "near the band's top: no climb, and a failed gated pick still turns (" .. sharpOnly .. " picks)")

bad, n = {}, 0
situations(function(sit)
    for _, ran in ipairs(allPaths(TC, sit)) do
        n = n + 1
        local pursued = false
        for _, x in ipairs(ran) do
            if x.factory == "PursuerTarget" or x.factory == "SetMoveAwayFromTarget" then pursued = true end
        end
        if not pursued then fault("no pursuit and no break-away", sit, ran) end
    end
end)
check(#bad == 0, string.format("LA_SV_TailChase (reviewed, unchanged): every pick pursues or breaks away (%d walks)%s", n,
      #bad > 0 and (": " .. table.concat(bad, " | ")) or ""))

---------------------------------------------------------------------------------------------------- the runtime parts
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))
VERSION = "0.71.5-tailed.test"
function NotifyOnNewObject() end
function FName(s) return s end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function playerOnAirfield() return false end
function hudCallout() end
function queueEvent() end
function SV_Event() return 1 end
local function run(name, chunk)
    local src = readAll(MOD .. "/Scripts/" .. name)
    if name == "sv_coop.lua" then src = src:gsub("\nlocal M = {", "\nM = {", 1) end
    assert(load(src, chunk or ("=" .. name)))()
end
run("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
run("sv_config.lua"); run("sv_rows.lua"); run("sv_ai.lua"); run("sv_spawn.lua"); run("sv_stats.lua"); run("sv_coop.lua")
local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function count(prefix) local k = 0; for _, l in ipairs(logs) do if l:sub(1, #prefix) == prefix then k = k + 1 end end; return k end

---------------------------------------------------------------------------------------------------- 2. the live provoke
print("live provoke")
local T = {}
for i, t in ipairs(CFG.tiers.list) do T[t.name] = t end
check(T.Veteran.provoke_cone_deg == 60 and T.Veteran.provoke_time_s == 1.5 and T.Demon.provoke_cone_deg == 60
      and T.Regular.provoke_cone_deg == nil, "CFG.tiers: Veteran to Demon 60 deg / 1.5 s, none below")
local function want(round, tier, level) return provokeWant(round, tier, level) end
local w = want(7, T.Veteran)
check(w and w.cone == 60 and w.time == 1.5 and w.surround == nil and w.level == 0, "round 7 Veteran: 60 / 1.5 (no spike yet)")
w = want(8, T.Veteran)
check(w and w.cone == 60 and w.time == 1.5 and w.surround[1] == 80 and w.surround[2] == 220 and has(w.src, ": the stricter"),
      "round 8 Veteran: the tier's 60 / 1.5 over spike 1's 70 / 2.0, the spike's 80-220 m")
w = want(22, T.Demon)
check(w and w.cone == 50 and w.time == 1.0 and w.surround[1] == 50, "round 22 Demon: spike 3's stricter 50 / 1.0 kept")
CFG.ai.provoke_stricter = false
w = want(22, T.Demon)
check(w and w.cone == 60 and w.time == 1.5 and has(w.src, "the tier's over the spike's"), "provoke_stricter off: the tier's replaces (as before P5)")
CFG.ai.provoke_stricter = true
w = want(28, T.Reaper)
check(w and w.cone == 45 and w.time == 0.8 and w.surround[1] == 40 and w.surround[2] == 100, "round 28 Reaper: 45 / 0.8 / 40-100 m")
check(want(1, T.Rookie) == nil and want(5, T.Regular) == nil, "Rookie, Regular before a spike: nothing (the game's row)")
check(want(22, T.Demon, 1).cone == 60, "an explicit spike level (for a later part)")
CFG.ai.tier_provoke = false
check(want(7, T.Veteran) == nil, "tier_provoke off: round 7 Veteran: nothing")
w = want(8, T.Veteran)
check(w and w.cone == 70 and w.time == 2.0 and not has(w.src, "Veteran"), "tier_provoke off: round 8: spike 1's only")
local special = { provoke_cone_deg = 30, provoke_time_s = 0.2, surround_m = { 20, 60 } }
w = want(9, special)
check(w and w.cone == 30 and w.time == 0.2 and w.surround[1] == 20 and has(w.src, "special 30 deg"), "tier_provoke off: a special's own still")
CFG.ai.tier_provoke = true
CFG.ai.provoke_cone_deg, CFG.ai.provoke_time_s = 30, 0.5
w = want(7, T.Veteran)
check(w and w.cone == 30 and w.time == 0.5 and has(w.src, "test values"), "test values: round 7 Veteran 30 / 0.5")
check(want(1, T.Rookie) == nil, "test values: only tiers with their own")
CFG.ai.provoke_cone_deg, CFG.ai.provoke_time_s = 0, 0.0
CFG.spikes.enabled = false
w = want(22, T.Demon)
check(w and w.cone == 60 and w.level == 0, "spikes off: round 22 Demon flies its tier's")
CFG.spikes.enabled = true

local nextAddr = 0x2000
local function plane(code, unit)
    nextAddr = nextAddr + 0x10
    local o = { addr = nextAddr, state = 10, HealthInternal = 1000, loc = { X = 0, Y = 0, Z = 300000 }, fwd = { X = 1, Y = 0, Z = 0 },
                ProvokeConditionConeAngle = 85.0, ProvokeDeterminationTime = 2.5, SurroundPursuitMinRange = 10000,
                SurroundPursuitMaxRange = 30000, reads = 0,
                full = "BP_OP1022_" .. code .. "_CP_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_OP1022_" ..
                       code .. "_CP_C_" .. nextAddr }
    function o:K2_GetActorLocation() self.reads = self.reads + 1; return self.loc end
    function o:GetActorForwardVector() return self.fwd end
    o.AIStateComponent = { BlackboardComponent = { GetValueAsEnum = function() return o.state end } }
    local p = { obj = o, unit = unit or "ERA_Unit_03_Dep_Air1", name = o.full:match("([^%.:]+)$") }
    return p
end
local P = plane("f16c")
local nW, before, writes = enemyProvoke(P, want(8, T.Veteran))
check(nW == 4 and P.obj.ProvokeConditionConeAngle == 60 and P.obj.ProvokeDeterminationTime == 1.5
      and P.obj.SurroundPursuitMinRange == 8000 and P.obj.SurroundPursuitMaxRange == 22000, "enemyProvoke: the four fields written")
check(has(before, "ProvokeConditionConeAngle 85.0") and has(writes, "ProvokeDeterminationTime 1.5"), "enemyProvoke: before / after texts")
check(enemyProvoke(P, want(8, T.Veteran)) == 0, "enemyProvoke: nothing again when nothing changed")
check(enemyProvoke(P, want(22, T.Demon)) == 4 and P.provokeWant.cone == 50 and P.obj.ProvokeDeterminationTime == 1.0,
      "enemyProvoke: a new level rewrites what changed (p.provokeWant kept)")
local Q = plane("su33")
enemySpike(Q, 8, T.Veteran)
local pl = line("provoke: round 8, spike level 1, Veteran")
check(Q.spiked == 1 and Q.obj.ProvokeConditionConeAngle == 60 and Q.provokeSet.cone == 60, "enemySpike: a round 8 Veteran written once")
check(has(pl, "was ProvokeConditionConeAngle 85.0") and has(pl, "reads back 60, 1.5, 8000, 22000")
      and has(pl, "(Veteran 60 deg / 1.5 s, spike 1 70 deg / 2 s / 80-220 m: the stricter)"), "enemySpike: its provoke: line")
local n0 = count("provoke:")
local Q2 = plane("f16c")
enemySpike(Q2, 8, T.Veteran)
Q.obj.ProvokeConditionConeAngle = 77
enemySpike(Q, 8, T.Veteran)
check(count("provoke:") == n0 and Q2.provokeSet.cone == 60 and Q.obj.ProvokeConditionConeAngle == 77,
      "enemySpike: one line a tier and level; never twice on a plane")
local R = plane("f16c")
enemySpike(R, 3, T.Regular)
check(R.spiked == 0 and R.provokeSet == nil and R.obj.ProvokeConditionConeAngle == 85.0, "enemySpike: a round 3 Regular keeps the game's")
local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
check(has(mainSrc, "pcall(enemySpike, p, D and D.round, tierFor)") and has(mainSrc, 'timed("tail watch", STATS.tailTick, now)'),
      "sv_main.lua: the sweep's enemySpike, probeTick's timed tail watch")

---------------------------------------------------------------------------------------------------- 3. the tail watch
print("tail watch")
local you = { X = 0, Y = 0, Z = 300000 }
local pawn = { addr = 0x9, MaxHealth = 100, HealthInternal = 800,
               full = "BP_PlayerPlane_PP1000_f16c_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_PlayerPlane_PP1000_f16c_C_1" }
function pawn:K2_GetActorLocation() return you end
survivalPC = { Pawn = pawn }
HIT = { msl = {}, h = 800 }
A = { caps = { [1] = 31 } }
CFG.stats.enabled = true
RUN = { kills = {} }
D = { round = 8, startRound = 7, state = "fighting", now = 100, up = {}, flown = {} }
STATS.roundStart(100)
local AHEAD, SIDE = { X = 1, Y = 0, Z = 0 }, { X = 0, Y = 1, Z = 0 }
local function at(km_) return { X = km_ * 100000, Y = 0, Z = 300000 } end
local function fighter(code, km_, fwd, unit)
    local p = plane(code, unit)
    p.tier, p.tierI, p.rankSet, p.k, p.dist = T.Veteran, 3, 4, 1, km_
    p.obj.loc, p.obj.fwd = at(km_), fwd
    enemySpike(p, 8, T.Veteran)
    return p
end
local function tick(now) D.now = now; STATS.tailTick(now) end
-- T1: you get behind it at 100; Provoke at 101.5, EscapeFromPursuer at 103, evading at 104; shot down at 109.5
local T1 = fighter("f16c", 1.0, AHEAD)
local T2 = fighter("f18e", 2.0, AHEAD, "ERA_Unit_04_Dep_Air0")
local FAR = fighter("m29a", 9.0, AHEAD, "ERA_Unit_05_Dep_Air0")
planes = { T1, T2, FAR }
tick(100)
check(T1.tw and T1.tw.t0 == 100 and T1.tw.cone == 60 and T1.tw.written and T2.tw and not FAR.tw and FAR.obj.reads == 0,
      "on two planes' tails at 100 (their provoke values read); the one 9 km off not read")
local t = 100
local function run_(to, f) while t < to - 1e-9 do t = t + 0.25; if f then f(t) end; tick(t) end end
run_(101.5, function(now) if now >= 101.5 then T1.obj.state = 8 end end)
check(T1.tw.react == 1.5, "T1 went into Provoke 1.5 s after you got behind it (" .. tostring(T1.tw.react) .. ")")
run_(103, function(now) if now >= 103 then T1.obj.state = 6 end end)
-- T2 turns away at 102.5 (you lose its tail); escaped once off it for watch_grace_s
T2.obj.fwd = SIDE
run_(104, function(now) if now >= 104 then T1.obj.state = 5 end end)
run_(105.5)
local esc = line("tailed: " .. T2.name)
check(T2.tw == nil and has(esc, "no Provoke") and has(esc, "escaped after 3.0 s"), "T2 escaped: off its tail from 103.25, held 3.0 s (no Provoke)")
run_(109.5, function(now) if now >= 109.5 then T1.obj.HealthInternal = 0 end end)
local died = line("tailed: " .. T1.name)
check(T1.tw == nil and has(died, "provoke 60 deg / 1.5 s (Survival's)") and has(died, "Provoke after 1.5 s")
      and has(died, "died 9.5 s after (8.0 s after its Provoke)"), "T1 died: 9.5 s on your tail, 8.0 s after its Provoke")
check(has(died, "Provoke 1.5 s, EscapeFromPursuer 1.0 s, AttackAvoidance") and has(died, "(ERA_Unit_03_Dep_Air1, Veteran, k 1, rank 4, AI level 2)"),
      "T1's line: its states, unit, tier, k, rank, AI level")
-- a flicker (one tick on its tail) is dropped; at most watch_max read a tick (the nearest); no bombers
local FL = fighter("su33", 1.5, AHEAD, "ERA_Unit_06_Dep_Air0")
local S = {}
for i = 1, 5 do S[i] = fighter("f15e", 3.0 + i * 0.2, SIDE, "ERA_Unit_07_Dep_Air" .. (i % 3)) end
local B = fighter("b52", 0.5, AHEAD, "BOMBER")
BOMBER_UNIT.BOMBER = true
planes = { FL, S[1], S[2], S[3], S[4], S[5], B }
run_(110)
FL.obj.fwd = SIDE
run_(113)
check(FL.tw == nil and not line("tailed: " .. FL.name) and not B.tw, "a 0.25 s flicker dropped; a bomber never watched")
check(S[1].obj.reads > 0 and S[3].obj.reads > 0 and S[4].obj.reads == 0 and S[5].obj.reads == 0, "at most watch_max (4) read a tick: the nearest")
-- the sweep sees one down first
local T4 = fighter("f16c", 0.8, AHEAD, "ERA_Unit_08_Dep_Air0")
-- (beside it, a special's guard on your guns: never watched, its top tier is given, not a skill band; code review of
-- 2026-10-29)
local SG = fighter("f16c", 0.9, AHEAD, "SV_Unit_AnomalyGuards")
SG.tier, SG.tierI = CFG.tiers.list[#CFG.tiers.list], #CFG.tiers.list
planes = { T4, SG }
run_(114)
STATS.down(T4, nil, "you", 115.35)
check(has(line("tailed: " .. T4.name), "died 2.1 s after") and T4.tw == nil, "the sweep's death first: the episode ends there")
check(SG.tw == nil and SG.obj.reads == 0 and not line("tailed: " .. SG.name), "a special's guard on your guns: never watched")
-- not on a co-op joiner; not with tail_watch off
local T5 = fighter("f16c", 0.7, AHEAD, "ERA_Unit_09_Dep_Air0")
planes = { T5 }
local rawClient = COOP.client
COOP.client = function() return true end
tick(120)
COOP.client = rawClient
CFG.stats.tail_watch = false
tick(120.25)
check(T5.tw == nil and T5.obj.reads == 0, "nothing on a co-op joiner, nothing with tail_watch off")
CFG.stats.tail_watch = true
-- a wreck the sweep hasn't seen down yet (its health 0, p.down not set): no episode, nothing when the sweep finds it
t = 121
local W = fighter("f16c", 0.6, AHEAD, "ERA_Unit_10_Dep_Air0")
W.obj.HealthInternal = 0
planes = { W }
run_(122)
STATS.down(W, nil, "you", 122.1)
check(W.tw == nil and not line("tailed: " .. W.name) and W.obj.reads == 0,
      "no episode on a wreck the sweep hasn't seen down yet, and no read of it (alive checked first: code review of 2026-10-29)")
-- already in Provoke when you get behind it (another pursuer): no reaction of its own, nothing "after its Provoke"
local PD = fighter("su33", 1.2, AHEAD, "ERA_Unit_11_Dep_Air0")
PD.obj.state = 8
planes = { PD }
run_(125.25, function(now) if now >= 125.25 then PD.obj.HealthInternal = 0 end end)
local pdl = line("tailed: " .. PD.name)
check(PD.tw == nil and has(pdl, "already in Provoke when you got behind it") and has(pdl, "died 3.0 s after")
      and not has(pdl, "after its Provoke)") and not has(pdl, "Provoke after"), "already defending: its line, no reaction time")
-- four nearer planes beside you, two you're behind: those two are read first (the sweep's p.tailing, or its last pose
-- against you now), then the nearest two
local N = {}
for i = 1, 4 do N[i] = fighter("f18e", 0.9 + i * 0.2, SIDE, "ERA_Unit_12_Dep_Air" .. (i % 3)) end
local CH = fighter("f15e", 2.5, AHEAD, "ERA_Unit_13_Dep_Air0")
CH.tailing = true
local CH2 = fighter("m29a", 2.7, AHEAD, "ERA_Unit_14_Dep_Air0")
CH2.at, CH2.fwd = at(2.7), AHEAD
planes = { N[1], N[2], N[3], N[4], CH, CH2 }
run_(125.5)
check(CH.tw and CH2.tw and N[1].obj.reads > 0 and N[2].obj.reads > 0 and N[3].obj.reads == 0 and N[4].obj.reads == 0,
      "the planes you're likely behind are read before four nearer ones")
-- CH2 turns away at 127.5 (escaped, held 2.0 s); CH is still on your guns when the run ends at 130
run_(127.5)
CH2.obj.fwd = SIDE
run_(130)
check(CH2.tw == nil and has(line("tailed: " .. CH2.name), "escaped after 2.0 s") and CH.tw, "CH2 escaped after 2.0 s; CH still open")
-- the run ends (shot down) mid-round: CH's episode ends as still up, then the round's line and the run's
STATS.runEnd("died")
check(CH.tw == nil and has(line("tailed: " .. CH.name), "no Provoke; ") and has(line("tailed: " .. CH.name),
      "still up when the run ended (died), 4.5 s on its tail"), "the run's end: an open episode ends as still up")
local rl = line("stats: round 8")
check(has(rl, "(cut short: died)") and has(rl, "; tail watch: 6 episodes (Veteran+ 6): died after median 3.0 s (n 3), 8.0 s after its Provoke (n 1), escaped 2 (held median 2.5 s), still up at the end 1, Provoke after median 1.5 s (none in 4, already defending 1), blackouts 0"),
      "the round line's tail watch part")
check(has(line("stats: run over (died)"), "; tail watch Veteran+: died after median 3.0 s on your tail (n 3), 8.0 s after its Provoke (n 1), escaped 2 (held median 2.5 s), still up at the end 1, Provoke after median 1.5 s (none in 4, already defending 1), blackouts 0 [8 s+]"),
      "the run line's tail watch Veteran+ part")

logFile:close()
print(fails == 0 and "tailed: all passed" or ("tailed: " .. fails .. " FAILED"))
if fails > 0 then for i = math.max(1, #logs - 12), #logs do print("    log: " .. logs[i]) end end
os.exit(fails == 0 and 0 or 1)
