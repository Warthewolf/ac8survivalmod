-- roles_test.lua <mod dir> <work dir> (run by tools/checks/roles_test.sh): the behaviour roadmap's P1, fighter roles
-- (tools/re/BEHAVIOUR_DIRECTOR.md unit 5), offline:
--   1. the role behaviour scripts (Scripts/ai/LA_SV_Lancer*, LA_SV_Wolf*, LA_SV_Skirm*) built as the game builds them
--      and walked through every pick by tailed_test.lua's model of the game's tree runner (tools/re/BEHAVIOUR_NATIVE_LOGIC.md
--      3-6), in every situation: the Lancer's pass never turn-fights and always hands over to its zoom, the zoom climbs
--      only below its band's top and always extends, the Lancer's and the Wolf bait's provoke picks each fly one move
--      under the 6 s blackout timer (the bait never breaks hard), the Wolf trap always pursues (the "Super" only at AI
--      level 5), the Skirmisher breaks off when its missile counter trips (at entry or mid-pursuit, an abort);
--   2. the rows at the main menu, on the real setsSetup / searchSetup / rolesSetup with fake tables (DT_NPC_LuaSet,
--      DT_NPC, DT_SV_NpcMission, DT_NPC_FCS, DT_NPC_Weapon): the four role sets, the role DT_NPC rows naming them, a set
--      that can't be made falling back, roles off naming the fighters' set; the Wolf airframes' leading gun rows at
--      every spike level and the Skirmishers' LAAM copy in their special slot (and neither with roles off);
--   3. ROLE's level snapshot (what a level has), the mix bands and quotas, the round's draw on the real startRound (each
--      role's share from its own flights, a short group filled from the rest, an ace round's duelists, the probes never,
--      the jammer only on a duelist or Skirmisher flight, no Wolf escort), roles off as before;
--   4. spawnFlight: each role's airframes (the Skirmishers' fallback before round 4), the Lancers 2 km higher within
--      their band, the first Lancer / Skirmisher flight of a round called out once, a Wolf flight's trap registered;
--   5. the Wolf trap (WOLF.tick): held hold_after_s after its orders are seen in (not while you're grounded), freed by
--      the timer, a hit, its own bait (or the lead) going down or the director's spring (with the turn), a held plane
--      shot down dropped, a recycled flight's earlier planes ignored, nothing freed or sprung inside your decoy (after
--      it, then), held again after it, dropped with its flight; the events co-op forwards (hold, free) and keeps (turn);
--   6. enemyLate: a Skirmisher's health x0.75 (MaxHealth lowered too), with the late rounds', not an ace squadron's;
--   7. a tier's no_provoke and moves (the Reaper's, every ordinary flight's from round 28) on duelists and ace squadrons
--      only, not on Lancer, Wolf or Skirmisher flights.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end

---------------------------------------------------------------------------------------------------- 1. the trees
print("the role behaviour scripts")
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
        assert(name:lower() ~= "root", chunk .. ": a node named Root")
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
    for _, n in pairs(nodes) do
        if n.kind == "decorator" or n.kind == "probability" then assert(#n.children == 1, chunk .. ": " .. n.name .. " has " .. #n.children .. " children") end
        if n.kind == "probability" then assert(n.parent.factory == "RandomSelect", chunk .. ": probability " .. n.name .. " outside a RandomSelect") end
    end
    return root
end
-- tailed_test.lua's runner model, with two more decorators (IsFireMissileFinished; its abort mid-task) and plain
-- WeightProbability. A task under an aborting decorator named in sit.abort ends Abort (3) instead of Complete.
local ANSWER = {
    Selector = { "next", "leave", "end" }, LaxSelector = { "next", "leave", "next" },
    Sequencer = { "leave", "next", "end" }, LaxSequencer = { "leave", "next", "next" },
    RandomSelect = { "next", "next", "next" },
}
local function decorator(n, sit)
    local f, a = n.factory, n.args
    if f == "DecoratorUnitAltitudeComparison" then if a[1] then return sit.alt ~= "low" else return sit.alt ~= "high" end
    elseif f == "DecoratorIsFireMissileFinished" then return (sit.fired == true) == a[1]
    elseif f == "DecoratorCanCobra" then if a[1] then return sit.cobra else return not sit.cobra end
    elseif f == "DecoratorCanKulbit" then if a[1] then return sit.kulbit else return not sit.kulbit end end
    error("decorator " .. f .. " not modelled")
end
local function weight(n, sit)
    local f, a = n.factory, n.args
    if f == "WeightProbabilityPilotRank" then return a[sit.rank]
    elseif f == "WeightProbabilityAILevel" then return a[sit.ai]
    elseif f == "WeightProbability" then return a[1] end
    error("probability " .. f .. " not modelled")
end
local function abortedBy(node, sit)                  -- an aborting decorator above the task that trips mid-run
    local c = node.parent
    while c do
        if c.kind == "decorator" and c.args[#c.args] == true and sit.abort == c.name then return true end
        c = c.parent
    end
    return false
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
                else cands[#cands + 1] = ch end
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
    local function enter(c)
        while c do
            local ch = select(c)
            if ch then return ch end
            c = pop()
        end
        return nil
    end
    local function finish(r, node)
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
            node = finish(abortedBy(node, sit) and 3 or 2, node)
        elseif node.kind == "decorator" then
            if decorator(node, sit) then node = node.children[1] else node = finish(1, node) end
        else node = nil end
    end
    return ran
end
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
              ManeuverTurnAdvanced = 6, PursuerTarget = 1, MoveAwayFromTarget = 1, MoveCenterAltitude = 1 }
local function seconds(ran)
    local s = 0
    for _, t in ipairs(ran) do if DUR[t.factory] then s = s + t.args[DUR[t.factory]] end end
    return s
end
local function names(ran) local t = {}; for _, x in ipairs(ran) do t[#t + 1] = x.name end; return table.concat(t, ",") end
local function ranAny(ran, pat) for _, x in ipairs(ran) do if x.name:match(pat) then return true end end return false end
local function ranFactory(ran, f) for _, x in ipairs(ran) do if x.factory == f then return x end end return nil end
local function situations(each)
    for rank = 1, 5 do for ai = 1, 5 do
        for _, alt in ipairs({ "mid", "high", "low" }) do
            for _, fired in ipairs({ false, true }) do for _, cobra in ipairs({ true, false }) do
                for _, abort in ipairs({ false, true }) do
                    each({ rank = rank, ai = ai, alt = alt, fired = fired, cobra = cobra, kulbit = cobra,
                           abort = abort and "SP_NoShotYet" or nil })
                end
            end end
        end
    end end
end
local function script(name) return build(readAll(MOD .. "/Scripts/ai/" .. name .. ".lua"), name) end
local NEW = { "LA_SV_LancerPass", "LA_SV_LancerZoom", "LA_SV_LancerBreak", "LA_SV_WolfDrag", "LA_SV_WolfStrike",
              "LA_SV_SkirmPass", "LA_SV_SkirmExtend" }
local T = {}
for _, n in ipairs(NEW) do T[n] = script(n) end
check(true, "every role script builds: one root, parents first, unique names, one child per decorator / probability")
-- every script packed, instrumented and in a set (the build checks the sets' names too)
local bs = readAll(MOD .. "/../../../tools/build_survival.py")
local cfgSrc = readAll(MOD .. "/Scripts/sv_config.lua")
for _, n in ipairs(NEW) do
    check(has(bs, "'" .. n .. "'") and has(cfgSrc, '"SurvivalMode.AI.' .. n .. '"') and has(cfgSrc, '= "' .. n .. '"'),
          n .. ": in LUA_SCRIPTS, GAME_LUA_STOCK and a behaviour set")
end

local function every(root, what, fn)
    local bad, n, worst = {}, 0, 0
    situations(function(sit)
        for _, ran in ipairs(allPaths(root, sit)) do
            n = n + 1
            worst = math.max(worst, seconds(ran))
            local why = fn(ran, sit)
            if why and #bad < 5 then bad[#bad + 1] = why .. ": " .. names(ran) end
        end
    end)
    check(#bad == 0, string.format("%s (%d walks, longest %.1f s)%s", what, n, worst, #bad > 0 and (": " .. table.concat(bad, " | ")) or ""))
    return worst
end
every(T.LA_SV_LancerPass, "LA_SV_LancerPass: always one slashing pass (lead pursuit, extends when you turn out of its nose, " ..
    "breaks a head-on merge, KDS blocked), through at speed and on to its zoom", function(ran)
    local pt = ranFactory(ran, "PursuerTarget")
    if not pt then return "no pass" end
    local a = pt.args
    if not (a[4] == true and a[7] == true and a[11] == true and a[14] == true and a[1] <= 6) then return "the pass's arguments" end
    if not ranAny(ran, "^LP_Through$") or ran[#ran].factory ~= "SetMoveAwayFromTarget" then return "no hand-over to the zoom" end
end)
local zoomWorst = every(T.LA_SV_LancerZoom, "LA_SV_LancerZoom: climbs unless near its band's top, always extends", function(ran, sit)
    local climbed = ranAny(ran, "^LZ_Pull$")
    if sit.alt == "high" and climbed then return "climbed at the top" end
    if sit.alt ~= "high" and not (climbed and ranAny(ran, "^LZ_Hold$")) then return "no climb below the top" end
    if ran[#ran].name ~= "LZ_Extend" then return "no extend" end
end)
check(zoomWorst <= 11, string.format("LA_SV_LancerZoom: at most ~11 s (%.1f)", zoomWorst))
every(T.LA_SV_LancerBreak, "LA_SV_LancerBreak (tailed, near, mid and far): every pick runs and reverses, never turn-fights, " ..
    "under 5 s (the blackout's 6)", function(ran)
    if seconds(ran) > 5 then return "too long" end
    if not (ranAny(ran, "_Run$") and ranAny(ran, "_Turn$")) then return "no run and reversal" end
    if ranFactory(ran, "PursuerTarget") then return "a pursuit" end
end)
every(T.LA_SV_WolfDrag, "LA_SV_WolfDrag (the bait tailed): every pick drags (relative to you, no hard break), under 4 s",
    function(ran)
    if seconds(ran) > 4 then return "too long" end
    for _, x in ipairs(ran) do
        if x.args[4] ~= "SpdRelative" and x.args[3] ~= "SpdRelative" and x.args[2] ~= "SpdRelative" then return "not relative to you" end
        if x.factory == "ManeuverTurnNormal" or x.factory == "ManeuverTurnAdvanced" then return "a hard break" end
    end
    if #ran < 2 then return "no drag" end
end)
local superSeen = {}
every(T.LA_SV_WolfStrike, "LA_SV_WolfStrike (the trap): always pursues close (its own offset, at most 200 m behind, never " ..
    "giving up); its Super only at AI level 5", function(ran, sit)
    local pt = ranFactory(ran, "PursuerTarget")
    if not pt then return "no pursuit" end
    if not (pt.args[16] == true and pt.args[17][1] >= -200 and pt.args[7] == false and pt.args[14] == true) then return "the pursuit's arguments" end
    if ranAny(ran, "^WS_Super") then
        superSeen[sit.ai] = true
        if sit.ai < 5 then return "Super below AI level 5" end
    elseif ran[#ran].factory ~= "SetMoveAwayFromTarget" then return "the strike doesn't hand over" end
end)
check(superSeen[5] and not superSeen[4], "LA_SV_WolfStrike: the Super branch at AI level 5 (an ace squadron in a Wolf flight keeps it)")
every(T.LA_SV_SkirmPass, "LA_SV_SkirmPass: pursues while no missile has gone, breaks off as one does (at entry or an abort " ..
    "mid-pursuit), always into its extend", function(ran, sit)
    local pursued = ranAny(ran, "^SP_Pursue$")
    if sit.fired and pursued then return "pursued with a missile already counted" end
    if not sit.fired and not pursued then return "no pursuit" end
    if ran[#ran].name ~= "SP_MoveAway" then return "no break-off" end
    local pt = ranFactory(ran, "PursuerTarget")
    if pt and not (pt.args[7] == true and pt.args[11] == true and pt.args[13] >= 3000 and pt.args[1] <= 8) then return "the pursuit's arguments" end
end)
check(names(walk(T.LA_SV_SkirmPass, { fired = false, abort = "SP_NoShotYet" }, function() return 1 end)) == "SP_Level,SP_Pursue,SP_MoveAway",
      "LA_SV_SkirmPass: a missile fired mid-pursuit aborts it, and the break-off still comes (the stock wingmen's abort shape)")
-- why the attack has a LaxSequencer of its own: with the gate straight in the root, a missile already counted at entry
-- ends the whole tree before its break-off (it would restart in PursueTarget, level 0.1 s, over and over)
local bare = build('local F = Inherit(CppObjectBase)\nfunction F:Ctor()\nself:GenerateBehavior()\n' ..
    'self:AddRootComposite("R", self:InstanceLaxSequencer())\n' ..
    'self:AddTask("R", "B_Level", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1750.0, 0.1, false))\n' ..
    'self:AddDecorator("R", "B_Gate", self:InstanceDecoratorIsFireMissileFinished(false, true))\n' ..
    'self:AddComposite("B_Gate", "B_Pick", self:InstanceRandomSelect())\n' ..
    'self:AddTask("B_Pick", "B_Pursue", self:InstancePursuerTarget(8.0, "TargetActor", 10.0, false, 3000.0, 20.0, true, 120.0, 2.0, 8.0, true, 45.0, 3000.0, true, false, false, FVector.New(-400.0, 0.0, 5.0)))\n' ..
    'self:AddTask("R", "B_MoveAway", self:InstanceSetMoveAwayFromTarget("SelfActor"))\n' ..
    'self:EndGenerateBehavior()\nend\nreturn F\n', "bare gate")
check(names(walk(bare, { fired = true }, function() return 1 end)) == "B_Level",
      "the model finds the bare gate's fault (a missile counted at entry: no break-off)")
every(T.LA_SV_SkirmExtend, "LA_SV_SkirmExtend: the long extend, then back to its band's middle", function(ran)
    if names(ran) ~= "SE_Level,SE_Extend,SE_Altitude" then return "not the extend" end
end)

---------------------------------------------------------------------------------------------------- the runtime parts
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local defaultIni = readAll(MOD .. "/config/survival.default.ini")
writeAll(WORK .. "/config/survival.default.ini", defaultIni)
-- a player's survival.ini: the shipped one with the roles' sections set live
writeAll(WORK .. "/config/survival.ini", defaultIni ..
    "\r\n[roles.mix]\r\nfrom_round = 1, 4, 10\r\nskirm = 0.0, 0.25, 0.2\r\n[roles.health_x]\r\nskirm = 0.7\r\n" ..
    "[roles]\r\njammer = duelist, skirm\r\n[roles.wolf]\r\nhold_max_s = 50\r\n")
VERSION = "0.71.5-roles.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance" }
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
local OBJ = {}
function StaticFindObject(p) return OBJ[p] end
local grounded = false
function playerOnAirfield() return grounded end
function hudCallout() end
function airfieldTick() end
function bombTick() end
local events, eventResult = {}, 1
function SV_Event(name) events[#events + 1] = name; return eventResult end
local spawns = {}
local alive = {}
function SV_SetAircraft(unit, row, idx) spawns[#spawns + 1] = { unit = unit, row = row, idx = idx }; return 1 end
function SV_SetLevel() return 1 end
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_Spawn(unit, x, y, z) spawns[#spawns + 1] = { unit = unit, z = z }; return flightSize(unit) end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopSend() return 1 end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=0" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt() return "" end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }
local tells = {}
TELL = { ALL = "all", say = function(id, slot) tells[#tells + 1] = id .. "@" .. tostring(slot); return true end }

local function run(name, chunk, edits)
    local src = readAll(MOD .. "/Scripts/" .. name)
    for _, e in ipairs(edits or {}) do
        local n
        src, n = src:gsub(e[1], e[2], 1)
        assert(n == 1, name .. ": " .. e[1] .. " not found")
    end
    assert(load(src, chunk or ("=" .. name)))()
end
run("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
run("sv_config.lua")
local cfgLine = nil
for _, l in ipairs(logs) do if l:find("^config: survival%.ini") then cfgLine = l end end
run("sv_rows.lua"); run("sv_ai.lua"); run("sv_spawn.lua")
run("sv_rounds.lua", nil, { { "\nlocal function startRound%(%)", "\nfunction startRound()" } })
run("sv_stats.lua")
run("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" }, { "\nlocal function mirroredEvent%(name%)", "\nfunction mirroredEvent(name)" } })
TELL = { ALL = "all", say = function(id, slot) tells[#tells + 1] = id .. "@" .. tostring(slot); return true end }
function playerOnAirfield() return grounded end      -- (sv_rounds.lua's own reads the pawn: none here)
LB.stat = function() end
presetName = function() return "standard", 3 end
SPC.kinds = {}
function SPC.kindValue(v, ...) if type(v) == "function" then return v(...) end return v end
math.randomseed(5)
local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function since(from, pat) local out = {}; for i = from, #logs do if logs[i]:find(pat) then out[#out + 1] = logs[i] end end; return out end

print("survival.ini's roles")
check(cfgLine and not has(cfgLine, "not used"), "config: every line used (" .. tostring(cfgLine) .. ")")
check(CFG.roles.mix.skirm[2] == 0.25 and CFG.roles.health_x.skirm == 0.7 and CFG.roles.wolf.hold_max_s == 50
      and CFG.roles.jammer[2] == "skirm", "[roles.mix] skirm, [roles.health_x], [roles.wolf] hold_max_s and [roles] jammer read")
CFG.roles = (function(t) local function d(x) if type(x) ~= "table" then return x end local c = {}; for k, v in pairs(x) do c[k] = d(v) end; return c end; return d(t) end)(CFG_DEFAULTS.roles)

---------------------------------------------------------------------------------------------------- 2. the rows
print("the rows at the main menu (setsSetup, searchSetup, rolesSetup on fake tables)")
local function copyRow(r)
    if type(r) ~= "table" then return r end
    local c = {}
    for k, v in pairs(r) do c[k] = copyRow(v) end
    return setmetatable(c, getmetatable(r))
end
local function fakeDT(name)
    local t = { full = name, rows = {} }
    function t.FindRow(self, n) return self.rows[type(n) == "table" and n.s or n] end
    function t.AddRow(self, n, r) self.rows[type(n) == "table" and n.s or n] = copyRow(r) end
    function t.RemoveRow(self, n) self.rows[type(n) == "table" and n.s or n] = nil end
    return t
end
local SLOTS = { "RootLua", "EvadeLua", "EvadeMissileNearLua", "EvadeMissileFarLua", "EvadeGunLua", "EvadeSpecialLua",
                "BlackoutLua", "CloudAvoidanceLua", "ProvokeLua", "ProvokeNearLua", "ProvokeMidLua", "ProvokeFarLua",
                "EscapeFromPursuerLua", "MoveAwayFromTargetLua", "PursueTargetLua" }
local tbl = {}
local missingScripts = {}
local function tables()
    for k in pairs(OBJ) do OBJ[k] = nil end
    tbl.ls, tbl.npc, tbl.mod = fakeDT("DT_NPC_LuaSet"), fakeDT("DT_NPC"), fakeDT("DT_NPC_AIModule")
    tbl.mission, tbl.fcs, tbl.wpn = fakeDT("DT_SV_NpcMission"), fakeDT("DT_NPC_FCS"), fakeDT("DT_NPC_Weapon")
    local base = { LuaAsetts = {} }
    for _, s in ipairs(SLOTS) do base.LuaAsetts[s] = { LuaScript = "stock " .. s } end
    tbl.ls.rows.NLID_0012_CP = base
    tbl.mod.rows.NPC_AIModule_Plane000 = { Radius = 6000, bEnableLostTargetInClouds = true }
    for _, id in ipairs({ "NPC_FCS_PlaneMsl000", "NPC_FCS_PlaneLAAM000", "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000",
                          "NPC_FCS_PlaneHCAA000", "NPC_FCS_PlaneFlr000" }) do
        tbl.fcs.rows[id] = { CaptureDistance = 2500, CaptureMinDistance = 300, CaptureAngleRange = 45, ActivationTime = 2,
                             TriggeringTime = 2.5, ShotIntervalTime = 10, RestingTime = 10, TriggerCount = 1, PredictionOffsetTime = 0 }
    end
    tbl.fcs.rows.NPC_FCS_PlaneGun000 = { CaptureDistance = 1500, CaptureAngleRange = 30, TriggeringTime = 1.5, TriggerCount = 10,
                                         RestingTime = 1, PredictionOffsetTime = 0, NpcWeaponId = FName("GUN_000") }
    tbl.wpn.rows.GUN_000 = { damage = 1, MaxSpawnAngle = 3, LifeTime = 2 }
    local function npcRow(id)
        return { NpcFCSId0 = FName("NPC_FCS_PlaneFlr000"), NpcFCSId1 = FName("NPC_FCS_PlaneGun000"),
                 NpcFCSId2 = FName("NPC_FCS_PlaneMsl000"), NpcFCSId3 = FName("None"), NpcFCSId4 = FName("None"),
                 NpcFCSId5 = FName("None"), LuaSetId = FName("NLID_0012_CP"), NpcAIModuleId = FName("NPC_AIModule_Plane000") }
    end
    local list = { "f16c_common" }
    for _, a in ipairs(CFG.aircraft) do list[#list + 1] = a end
    for _, e in ipairs(CFG.variety.late) do list[#list + 1] = e[1] end
    list[#list + 1] = CFG.jammer.aircraft
    for _, a in ipairs(list) do
        local npc = "OP_" .. a
        tbl.npc.rows[npc] = npcRow(npc)
        tbl.mission.rows[a] = { NpcId = FName(npc) }
        for lv = 0, #SPIKE_SUFFIX do
            tbl.mission.rows[a .. "_sv" .. SPIKE_SUFFIX[lv]] = { NpcId = FName(npc .. "_SV" .. SPIKE_SUFFIX[lv]:upper()) }
        end
    end
    for key, row in pairs(ROLE.ROWS) do
        tbl.mission.rows[row] = { NpcId = FName(({ lancer = "SV_Role_Lancer", wolf = "SV_Role_WolfLead",
                                                  wolf_wing = "SV_Role_WolfWing", skirm = "SV_Role_Skirmish" })[key]) }
    end
    OBJ[PROBE_TABLES[1].path], OBJ[PROBE_TABLES[2].path], OBJ[SEARCH_MODULE.path] = tbl.ls, tbl.npc, tbl.mod
    OBJ["/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"] = tbl.mission
    OBJ[FCS_TABLE], OBJ[WEAPON_TABLE] = tbl.fcs, tbl.wpn
    for name in pairs((function() local s = {}; for _, d in pairs(CFG.behaviour_sets) do for _, n in pairs(d.slots) do s[n] = true end end; return s end)()) do
        if not missingScripts[name] then
            OBJ["/Game/LuaSource/SurvivalMode/AI/" .. name .. "." .. name] = { full = name }
        end
    end
end
local function setup()
    BS.done, BS.ready, BS.tries = false, {}, 0
    SR.done, SR.ready, SR.tries, SR.levels = false, {}, 0, {}
    RS.done, RS.ready = false, {}
    tables()
    setsSetup(); searchSetup(); rolesSetup()
    SR.usable = {}
    for a, sv in pairs(SR.ready) do SR.usable[a] = sv end
    SR.usableLevels = {}
    for a, t in pairs(SR.levels or {}) do SR.usableLevels[a] = t end
end
local from = #logs + 1
setup()
for _, set in ipairs({ "NLID_SV_Lancer", "NLID_SV_WolfLead", "NLID_SV_WolfWing", "NLID_SV_Skirmisher", "NLID_SV_Fighter" }) do
    check(BS.ready[set] and tbl.ls.rows[set], set .. " made")
end
local lr = tbl.ls.rows.NLID_SV_Lancer
check(lr and lr.LuaAsetts.PursueTargetLua.LuaScript.full == "LA_SV_LancerPass" and lr.LuaAsetts.ProvokeMidLua.LuaScript.full == "LA_SV_LancerBreak"
      and lr.LuaAsetts.ProvokeNearLua.LuaScript.full == "LA_SV_LancerBreak" and lr.LuaAsetts.ProvokeFarLua.LuaScript.full == "LA_SV_LancerBreak"
      and lr.LuaAsetts.EvadeLua.LuaScript == "stock EvadeLua", "NLID_SV_Lancer: its pass, zoom, break (near, mid and far: never the stock far turns), the rest stock")
check(tbl.ls.rows.NLID_SV_WolfLead.LuaAsetts.EscapeFromPursuerLua.LuaScript == "stock EscapeFromPursuerLua",
      "NLID_SV_WolfLead keeps the stock 8 s escape run (the drag)")
for key, set in pairs({ lancer = "NLID_SV_Lancer", wolf = "NLID_SV_WolfLead", wolf_wing = "NLID_SV_WolfWing", skirm = "NLID_SV_Skirmisher" }) do
    local npc = RS.ready[key] and RS.ready[key].npc
    local r = npc and tbl.npc.rows[npc]
    check(r and r.LuaSetId:ToString() == set and r.NpcAIModuleId:ToString() == SEARCH_MODULE.row,
          string.format("rolesSetup: %s's row %s flies %s with Survival's search", key, tostring(npc), set))
end
check(has(line("roles: behaviour rows", from), "lancer sv_role_lancer -> SV_Role_Lancer flies NLID_SV_Lancer"), "the roles' row line")
-- the fire control
local f16 = tbl.npc.rows.OP_f16c_common_SV
check(f16.NpcFCSId1:ToString() == "NPC_FCS_PlaneGun000_SV_WOLF" and tbl.fcs.rows.NPC_FCS_PlaneGun000_SV_WOLF.PredictionOffsetTime == 0.5,
      "a Wolf airframe (F-16C): its gun leads you 0.5 s (NPC_FCS_PlaneGun000_SV_WOLF)")
check(tbl.npc.rows.OP_m29a_common_SVC.NpcFCSId1:ToString() == "NPC_FCS_PlaneGun000_SVC_WOLF", "... at every spike level (MiG-29, level c)")
check(tbl.npc.rows.OP_f15e_common_SV.NpcFCSId1:ToString() == "NPC_FCS_PlaneGun000_SV", "a Lancer airframe's gun: Survival's own, no lead")
local laam = tbl.fcs.rows.NPC_FCS_PlaneLAAM000_SV_SKIRM
check(tbl.npc.rows.OP_f02a_common_SV.NpcFCSId3:ToString() == "NPC_FCS_PlaneLAAM000_SV_SKIRM"
      and tbl.npc.rows.OP_f35c_common_SVD.NpcFCSId3:ToString() == "NPC_FCS_PlaneLAAM000_SV_SKIRM"
      and laam and laam.CaptureDistance == 7000 and laam.CaptureMinDistance == 2500 and laam.CaptureAngleRange == 45,
      "a Skirmisher airframe's special slot: the LAAM copy, 7 km, never inside 2.5 km, at every level")
check(tbl.npc.rows.OP_su33_common_SV.NpcFCSId3:ToString() ~= "NPC_FCS_PlaneLAAM000_SV_SKIRM", "a duelist airframe's special: the random one")
-- a set that can't be made: its role row flies the fighters' set; ROLE.levelLoad draws its flights as duelists
missingScripts.LA_SV_WolfDrag = true
from = #logs + 1
setup()
check(not BS.ready.NLID_SV_WolfLead and tbl.npc.rows.SV_Role_WolfLead.LuaSetId:ToString() == "NLID_SV_Fighter",
      "LA_SV_WolfDrag not in the container: the Wolf bait's row flies NLID_SV_Fighter")
check(has(line("roles: behaviour rows", from), "(wanted NLID_SV_WolfLead: not made)"), "... and says so")
ROLE.levelLoad()
check(ROLE.live and ROLE.live.wolf == "duelist" and ROLE.flight("ERA_Unit_05_Dep_Air1") == "duelist" and ROLE.live.lancer == true,
      "ROLE.levelLoad: the Wolf flights fly as duelists, the Lancers as Lancers")
missingScripts.LA_SV_WolfDrag = nil
-- roles off at the main menu: every role row names the fighters' set, no role fire control
CFG.roles.enabled = false
setup()
check(tbl.npc.rows.SV_Role_Lancer.LuaSetId:ToString() == "NLID_SV_Fighter" and tbl.npc.rows.SV_Role_Skirmish.LuaSetId:ToString() == "NLID_SV_Fighter",
      "roles off: the role rows fly NLID_SV_Fighter")
check(tbl.npc.rows.OP_f16c_common_SV.NpcFCSId1:ToString() == "NPC_FCS_PlaneGun000_SV" and not tbl.fcs.rows.NPC_FCS_PlaneLAAM000_SV_SKIRM,
      "roles off: no Wolf gun lead, no Skirmisher LAAM")
ROLE.levelLoad()
check(ROLE.live == nil and ROLE.flight("ERA_Unit_03_Dep_Air0") == nil and has(line("roles: off"), "drawn as before"),
      "roles off: ROLE.live nil, no flight has a role")
CFG.roles.enabled = true
ROLE.levelLoad()                                       -- (the rows made with roles off, roles on by the level's load)
check(ROLE.live.lancer == "duelist" and ROLE.live.wolf == "duelist" and ROLE.flight("ERA_Unit_07_Dep_Air0") == "duelist",
      "rows made with roles off, roles on at the level's load: every role flight drawn as a duelist (its rows fly the fighters' set)")
-- no role rows at all (an older container): its flights sit out
setup()
tbl.mission.rows.sv_role_lancer = nil
RS.done, RS.ready = false, {}
rolesSetup()
ROLE.levelLoad()
check(ROLE.live.lancer == false and ROLE.flight("ERA_Unit_03_Dep_Air2") == nil and #ROLE.groups().lancer == 0,
      "no Lancer row before the level loaded: the Lancer flights sit out")
setup()
ROLE.levelLoad()
check(ROLE.live.lancer == true and ROLE.live.wolf == true and ROLE.live.skirm == true and has(line("roles: at level load"), "lancer NLID_SV_Lancer"),
      "ROLE.levelLoad: every role in")

---------------------------------------------------------------------------------------------------- 3. the draw
print("the roles' draw")
local function aircraftOf(units) local n = 0; for _, u in ipairs(units) do n = n + flightSize(u) end; return n end
local g = ROLE.groups()
check(aircraftOf(g.duelist) == 24 and aircraftOf(g.lancer) == 24 and aircraftOf(g.wolf) == 24 and aircraftOf(g.skirm) == 14,
      string.format("the groups: duelist %d, lancer %d, wolf %d, skirm %d aircraft (the probes' 10 left out; 86 in all)",
          aircraftOf(g.duelist), aircraftOf(g.lancer), aircraftOf(g.wolf), aircraftOf(g.skirm)))
local w1, b1 = ROLE.mixFor(1)
local w4 = ROLE.mixFor(5)
local w10, b10 = ROLE.mixFor(30)
local wa, ba = ROLE.mixFor(16, true)
check(b1 == 1 and w1.duelist == 0.6 and w1.skirm == 0 and w4.skirm == 0.2 and b10 == 10 and w10.lancer == 0.25
      and ba == "ace" and wa.duelist == 1 and wa.wolf == 0, "ROLE.mixFor: the bands (1, 4, 10) and an ace round's")
local q = ROLE.quotas(24, w10)
check(q.duelist + q.lancer + q.wolf + q.skirm == 24 and q.duelist % 2 == 0 and q.lancer % 2 == 0 and q.duelist >= 6,
      string.format("ROLE.quotas(24): %d / %d / %d / %d, whole 2-ships", q.duelist, q.lancer, q.wolf, q.skirm))
local q5 = ROLE.quotas(5, w1)
check(q5.duelist + q5.lancer + q5.wolf + q5.skirm == 4, "ROLE.quotas(5): two 2-ships (an odd one left for the fill)")
check(ROLE.quotas(8, { duelist = 0, lancer = 0, wolf = 0, skirm = 0 }).duelist == 8, "ROLE.quotas with no weights: duelists")

CFG.airfield.enabled = false
CFG.specials.enabled = false
local function fresh(round)
    planes = {}
    D = { round = round - 1, startRound = 1, state = "wait", at = 0, now = 1000, up = {}, flown = {}, queue = {}, spare = {},
          events = {}, pressure = "B" }
end
local function roundPicks()
    local by, total = {}, 0
    for _, w in ipairs(D.waves) do
        for _, u in ipairs(w) do
            if u:sub(1, 1) ~= "@" then
                local r = ROLE.flight(u) or "?"
                by[r] = (by[r] or 0) + flightSize(u); total = total + flightSize(u)
                assert(not PROBE_OF[u], "a probe flight picked")
            end
        end
    end
    return by, total
end
local function shareOk(round, runs)
    local sums, n = {}, 0
    for _ = 1, runs do
        fresh(round)
        startRound()
        local by, total = roundPicks()
        n = n + total
        for r, v in pairs(by) do sums[r] = (sums[r] or 0) + v end
    end
    return sums, n
end
for _, c in ipairs({ { 1, { duelist = 0.6, lancer = 0.2, wolf = 0.2, skirm = 0 } }, { 6, { duelist = 0.4, lancer = 0.2, wolf = 0.2, skirm = 0.2 } },
                     { 15, { duelist = 0.3, lancer = 0.25, wolf = 0.25, skirm = 0.2 } } }) do
    local sums, n = shareOk(c[1], 200)
    local ok, parts = true, {}
    for _, r in ipairs(ROLE.LIST) do
        local s = (sums[r] or 0) / n
        parts[#parts + 1] = string.format("%s %.2f", r, s)
        if math.abs(s - c[2][r]) > 0.12 then ok = false end
    end
    check(ok and not sums["?"], string.format("round %d: each role's share of the aircraft near the mix (%s)", c[1], table.concat(parts, ", ")))
end
local full, runs35 = 0, 60                              -- (P8's round 35: 60 of the pool's 86, by role)
for _ = 1, runs35 do
    fresh(35); startRound()
    local _, t35 = roundPicks()
    if t35 == 60 then full = full + 1 end
end
check(full >= runs35 * 0.85, string.format("round 35 (P8's 60 aircraft): all 60 drawn by role in %d of %d rounds", full, runs35))
fresh(15); startRound()
local rl = line("roles: round 15")
check(has(rl, "the mix from round 10") and has(rl, "of 30 aircraft") and has(rl, "duelist "), "the round's roles line: " .. tostring(rl))
-- a group short: filled from the rest
CFG.roles.mix.wolf = { 0.0, 0.0, 0.9 }
CFG.roles.mix.duelist = { 0.6, 0.4, 0.1 }
CFG.roles.mix.lancer = { 0.2, 0.2, 0.0 }
CFG.roles.mix.skirm = { 0.0, 0.2, 0.0 }
local shortOk, shortLine = true, nil
for _ = 1, 20 do
    fresh(15); startRound()
    local byS, tS = roundPicks()
    rl = line("roles: round 15")
    if not (tS == 30 and byS.wolf == 24 and has(rl, "short: wolf 24 of") and has(rl, "filled from")) then shortOk, shortLine = false, rl end
end
check(shortOk, string.format("a group too small for its share (wolf 0.9 of 30): its 24, the rest from the others (%s)",
      tostring(shortLine or rl)))
CFG.roles.mix = (function() local m = {}; for k, v in pairs(CFG_DEFAULTS.roles.mix) do m[k] = { table.unpack(v) } end; return m end)()
-- an ace round: the duelists first
fresh(16)
D.nextTier, D.nextTierRound = 6, 16
startRound()
local byA, tA = roundPicks()
check(D.roundTier == 6 and byA.duelist == 24 and tA == 30 and has(line("roles: round 16"), "an ace round's mix"),
      string.format("an ace round: the 24 duelists, then the rest (%d of %d)", byA.duelist or 0, tA))
-- the jammer: only a duelist or Skirmisher flight
CFG.jammer.chance, CFG.jammer.from_round = 1.0, 2
SR.usable[CFG.jammer.aircraft] = SR.usable[CFG.jammer.aircraft] or "e18g_common_sv"
local jamBad, jams = 0, 0
for _ = 1, 150 do
    fresh(12); startRound()
    if D.jammerUnit then
        jams = jams + 1
        local r = ROLE.flight(D.jammerUnit)
        if r ~= "duelist" and r ~= "skirm" then jamBad = jamBad + 1 end
    end
end
check(jams > 100 and jamBad == 0, string.format("the jammer leads only duelist or Skirmisher flights (%d rounds with one, %d not)", jams, jamBad))
CFG.jammer.chance, CFG.jammer.from_round = CFG_DEFAULTS.jammer.chance, CFG_DEFAULTS.jammer.from_round
-- a raid's escorts: never a Wolf flight (its trap's hold), first in the queue
CFG.airfield.enabled = true
local escBad, escN = 0, 0
for _ = 1, 100 do
    fresh(CFG.airfield.bombers.first_raid); startRound()
    for u in pairs(D.escortUnits or {}) do
        escN = escN + 1
        if ROLE.flight(u) == "wolf" then escBad = escBad + 1 end
    end
end
check(escN > 0 and escBad == 0, string.format("a raid's escorts: %d, none a Wolf flight", escN))
CFG.airfield.enabled = false
-- roles off: the draw as before (the whole pool, no roles line)
local saveLive = ROLE.live
ROLE.live = nil
from = #logs + 1
fresh(15); startRound()
local _, tOff = roundPicks()
check(tOff == 30 and #since(from, "^roles: round") == 0, "roles off (ROLE.live nil): 30 aircraft from the whole pool, no roles line")
ROLE.live = saveLive
-- a group that sits out (its row wasn't in at level load): never drawn, never a spare
ROLE.live = { duelist = true, lancer = false, wolf = true, skirm = true }
local sitBad = 0
for _ = 1, 50 do
    fresh(15); startRound()
    for _, w in ipairs(D.waves) do for _, u in ipairs(w) do if ROLE.of[u] == "lancer" then sitBad = sitBad + 1 end end end
    for _, u in ipairs(D.spare) do if ROLE.of[u] == "lancer" then sitBad = sitBad + 1 end end
end
check(sitBad == 0 and ROLE.sitsOut("ERA_Unit_03_Dep_Air0") and not ROLE.sitsOut("ERA_Unit_01_Dep_Air0"),
      "a role sitting out (no row at level load): its flights never drawn nor a spare (ROLE.sitsOut)")
ROLE.live = saveLive
check(not ROLE.sitsOut("ERA_Unit_03_Dep_Air0"), "ROLE.sitsOut: nothing sits out with every row in")

---------------------------------------------------------------------------------------------------- 4. spawnFlight
print("spawnFlight with roles")
local function spawnOf(unit, round)
    D.round = round
    spawns = {}
    local r = spawnFlight(unit)
    local row, z
    for _, s in ipairs(spawns) do if s.row and not s.idx then row = s.row end; if s.z then z = s.z end end
    return r, row, z
end
local function base(row) return (row or ""):gsub("_sv[bcd]?$", "") end
local function inList(a, l) for _, x in ipairs(l) do if x == a then return true end end return false end
fresh(10)
local okL, okW, okS, okD = true, true, true, true
local zMin, zMax = math.huge, 0
for _ = 1, 40 do
    D.up = {}
    local _, row, z = spawnOf("ERA_Unit_03_Dep_Air0", 10)
    if not inList(base(row), CFG.roles.aircraft.lancer) then okL = false end
    zMin, zMax = math.min(zMin, z), math.max(zMax, z)
    _, row = spawnOf("ERA_Unit_05_Dep_Air0", 10); if not inList(base(row), CFG.roles.aircraft.wolf) then okW = false end
    _, row = spawnOf("ERA_Unit_07_Dep_Air0", 10); if not inList(base(row), CFG.roles.aircraft.skirm) then okS = false end
    _, row = spawnOf("ERA_Unit_01_Dep_Air0", 10); if not inList(base(row), CFG.roles.aircraft.duelist) then okD = false end
end
check(okL and okW and okS and okD, "round 10: each role flies its own airframes (Lancer F-15E/F-14D/F-15C/Su-34, Wolf, Skirmisher, duelist)")
check(zMin >= 400000 and zMax <= 650000, string.format("the Lancers spawn 2 km higher: %.1f-%.1f km (the others 2-4.5)", zMin / 100000, zMax / 100000))
CFG.altitude_m = { 8000, 8000 }
local _, _, zTop = spawnOf("ERA_Unit_04_Dep_Air1", 10)
check(zTop == (ROLE.LANCER_TOP_M - 500) * 100, "... kept 500 m under their band's top (" .. zTop / 100000 .. " km)")
CFG.altitude_m = { 2000, 4500 }
from = #logs + 1
local fb = true
for _ = 1, 20 do local _, row = spawnOf("ERA_Unit_07_Dep_Air1", 2); if not inList(base(row), CFG.roles.aircraft.wolf) then fb = false end end
check(fb and has(line("roles: no skirm airframe yet in round 2", from), "wolf's"), "round 2: no Skirmisher airframe yet, the Wolf ones (logged)")
fresh(9)
local okS9 = true
for _ = 1, 30 do local _, row = spawnOf("ERA_Unit_07_Dep_Air2", 9); if not inList(base(row), CFG.roles.aircraft.skirm) then okS9 = false end end
check(okS9, "round 9: the Skirmishers fly the F-2A, Gripen and F-35C only")
check(has(line("round 9: ERA_Unit_07_Dep_Air2 [skirm]"), "as "), "the spawn line names the role")
-- tells: the first Lancer and Skirmisher flight of a round, once each
fresh(8); tells = {}
spawnOf("ERA_Unit_03_Dep_Air0", 8); spawnOf("ERA_Unit_04_Dep_Air1", 8); spawnOf("ERA_Unit_07_Dep_Air0", 8)
spawnOf("ERA_Unit_01_Dep_Air0", 8); spawnOf("ERA_Unit_05_Dep_Air0", 8)
check(table.concat(tells, ",") == "lancer@all,skirm@all", "round 8: one 'lancer' and one 'skirm' tell to every player (" .. table.concat(tells, ",") .. ")")
spawnOf("ERA_Unit_03_Dep_Air1", 9)
check(tells[3] == "lancer@all", "the next round's first Lancer flight calls again")
check(CFG.tells.list.lancer and CFG.tells.list.skirm and CFG.tells.text.lancer and CFG.tells.text.skirm_sub, "the tells' catalog has lancer and skirm")
CFG.roles.tells = false; tells = {}
fresh(11); spawnOf("ERA_Unit_03_Dep_Air0", 11)
check(#tells == 0, "[roles] tells = false: no callout")
CFG.roles.tells = true
-- a Wolf flight's trap
fresh(10)
spawnOf("ERA_Unit_05_Dep_Air2", 10)
local wf = D.wolf and D.wolf.ERA_Unit_05_Dep_Air2
check(wf and wf.state == "pending" and table.concat(wf.keys, ",") == "1,3,5", "a Wolf 6-ship: objects 1, 3, 5 to hold")
check(WOLF.holding("ERA_Unit_05_Dep_Air2"), "WOLF.holding while its hold is pending (hunts and escorts leave it alone)")

---------------------------------------------------------------------------------------------------- 5. the Wolf trap
print("the Wolf trap (WOLF.tick)")
local U = "ERA_Unit_05_Dep_Air1"                       -- pool index 14
local FLAGS = {}
svFlags = function() return FLAGS end
local function mkPlanes(unit, n)
    planes = {}
    for k = 0, n - 1 do planes[#planes + 1] = { unit = unit, k = k, name = "BP_OP1022_f16c_C_" .. k, obj = {} } end
end
local function evs(pat) local t = {}; for _, e in ipairs(events) do if e:find(pat) then t[#t + 1] = e end end; return table.concat(t, ",") end
fresh(10); D.now = 100
alive[U] = 4
WOLF.spawned(U, 4, 100)
mkPlanes(U, 4)
events = {}
WOLF.tick(101)
check(#events == 0, "no hold before the flight's orders are seen in (SV_Up_14 0)")
FLAGS.SV_Up_14 = 1
WOLF.tick(102)                                         -- (seen at 102: held at 105)
WOLF.tick(104.5)
check(#events == 0, "... nor before hold_after_s (3 s) after that")
grounded = true
WOLF.tick(106)
check(#events == 0, "... nor while you're down at the airfield")
grounded = false
WOLF.tick(106.25)
check(evs("^RE_SV_WolfHold") == "RE_SV_WolfHold_14B,RE_SV_WolfHold_14D" and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap"), "held B, D"),
      "held: RE_SV_WolfHold_14B and _14D (objects 1 and 3), logged")
check(WOLF.holding(U), "WOLF.holding: true")
events = {}
planes[2].dmg = { you = 30 }                           -- object 1 hit by you
WOLF.tick(107.5)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfFree_14B" and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap freed (you hit it)"), ": B"),
      "a held plane you hit: freed alone (RE_SV_WolfFree_14B), no turn")
events = {}
D.decoyed = { [U] = 110 }                              -- your DECOY ends at 110 (its DecoyEnd frees them all)
WOLF.tick(110.5)
check(#events == 0, "a decoy's end: not held again before rehold_s")
WOLF.tick(111.5)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfHold_14D" and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap again after your decoy"), "held D"),
      "rehold_s after your decoy's end: the one still held is held again (D)")
events = {}
WOLF.tick(113)
check(#events == 0, "... once")
planes[1].down = true                                  -- the bait down
WOLF.tick(114)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfFree_14D" and not WOLF.holding(U), "its bait down: the rest freed, nothing held")
-- the timer, and the director's spring with the turn
fresh(10); events = {}
WOLF.spawned(U, 4, 200); mkPlanes(U, 4); FLAGS.SV_Up_14 = 1
WOLF.tick(200); WOLF.tick(203.5)
events = {}
WOLF.tick(203.5 + CFG.roles.wolf.hold_max_s - 1)
check(#events == 0, "held: not freed before hold_max_s")
WOLF.tick(203.5 + CFG.roles.wolf.hold_max_s + 0.1)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfFree_14B,RE_SV_WolfFree_14D" and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap freed (held 60 s)"), ""),
      "hold_max_s (60 s): both freed")
fresh(10); events = {}
WOLF.spawned(U, 4, 300); mkPlanes(U, 4)
WOLF.tick(300); WOLF.tick(303.1)
events = {}
check(WOLF.free(U, "the director springs it", true) == 2
      and evs("^RE_SV_Wolf") == "RE_SV_WolfFree_14B,RE_SV_WolfTurn_14B,RE_SV_WolfFree_14D,RE_SV_WolfTurn_14D",
      "WOLF.free(unit, why, true), the squad director's spring: each freed and turned onto the player (LastTGT)")
-- the flight down; an event the container hasn't got
alive[U] = 0
WOLF.tick(304)
check(D.wolf[U] == nil, "its flight down: dropped")
alive[U] = 4
fresh(10); events = {}; eventResult = -2
WOLF.spawned(U, 4, 400); mkPlanes(U, 4)
WOLF.tick(400); WOLF.tick(403.1)
check(D.wolf[U] == nil and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap"), "not fired"), "no hold event in the container: logged, dropped")
eventResult = 1
CFG.roles.wolf.hold = false
fresh(10); WOLF.spawned(U, 4, 500)
check(not (D.wolf and D.wolf[U]) and not WOLF.holding(U), "[roles.wolf] hold = false: no trap held")
CFG.roles.wolf.hold = true
-- each held plane's own bait (the plane before it); a held plane shot down (U5's review)
fresh(10); events = {}
WOLF.spawned(U, 4, 600); mkPlanes(U, 4); FLAGS.SV_Up_14 = 1
WOLF.tick(600); WOLF.tick(603.1)
events = {}
planes[3].down = true                                  -- bait C (k 2)
WOLF.tick(604.5)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfFree_14D" and D.wolf[U].held[1] and WOLF.holding(U)
      and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap freed (its bait C is down)"), ": D"),
      "a 4-ship's second bait (C) down: its own trap plane (D) freed alone, B still held")
events = {}
planes[2].down = true; planes[2].dmg = { you = 100 }   -- B shot down while held
WOLF.tick(606)
check(#events == 0 and not WOLF.holding(U) and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap: B down"), "while held"),
      "a held plane shot down: dropped (nothing fired at it), the trap done")
-- a recycled flight: its earlier spawn's planes (down, born before this one) aren't its baits, whatever the list's order
fresh(10); events = {}
WOLF.spawned(U, 4, 700); FLAGS.SV_Up_14 = 1
planes = {}
for k = 0, 3 do planes[#planes + 1] = { unit = U, k = k, name = "new_" .. k, obj = {}, born = 701 } end
planes[#planes + 1] = { unit = U, k = 0, name = "old_0", obj = {}, down = true, born = 650 }
planes[#planes + 1] = { unit = U, k = 2, name = "old_2", obj = {}, down = true, born = 650 }
WOLF.tick(700); WOLF.tick(703.1)
events = {}
WOLF.tick(705)
check(#events == 0 and D.wolf[U].held[1] and D.wolf[U].held[3], "a recycled flight: the earlier spawn's downed lead and bait free nothing")
-- your DECOY on a holding flight: nothing freed or sprung inside it (the item keeps the flight stood down, the joiners'
-- copies too); after its end the releases it held back, then the rest held again rehold_s on
run("sv_tactical.lua")
fresh(10); events = {}
WOLF.spawned(U, 4, 800); mkPlanes(U, 4); FLAGS.SV_Up_14 = 1
WOLF.tick(800); WOLF.tick(803.1)
events = {}
D.decoyed = { [U] = 840 }                              -- stood down until 840
planes[2].dmg = { you = 20 }                           -- B hit inside it
WOLF.tick(812)
check(#events == 0 and D.wolf[U].held[1] and D.wolf[U].held[3], "your decoy: a held plane you hit isn't freed inside it")
D.now = 815
check(WOLF.free(U, "the director springs it", true) == 0 and #events == 0
      and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap kept (the director springs it)"), "not sprung"),
      "... nor sprung (WOLF.free answers 0, logged): the turn would send them at you")
WOLF.free(U, "again", true)
check(#events == 0 and not has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap kept (again)"), "kept"), "... logged once a decoy")
WOLF.tick(840.2)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfFree_14B" and has(line("roles: ERA_Unit_05_Dep_Air1 (wolf) trap freed (you hit it)"), ": B"),
      "its end: the hit one freed then (B)")
events = {}
WOLF.tick(841.3)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfHold_14D", "rehold_s after it: the other held again (D)")
-- hold_max_s and the lead down inside a decoy: both wait for its end
events = {}
D.decoyed[U] = 900
planes[1].down = true                                  -- the lead down inside it
WOLF.tick(870)                                         -- (and 66 s held)
check(#events == 0 and D.wolf[U].held[3], "hold_max_s and the lead down inside a decoy: nothing freed")
WOLF.tick(900.5)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfFree_14D" and not WOLF.holding(U), "... at its end: freed")
D.decoyed = nil
-- co-op: the holds and frees go to the joiners, the turn stays the host's
check(mirroredEvent("RE_SV_WolfHold_14B") and mirroredEvent("RE_SV_WolfFree_14D") and not mirroredEvent("RE_SV_WolfTurn_14B"),
      "co-op: RE_SV_WolfHold / WolfFree forwarded to joiners, RE_SV_WolfTurn kept (LastTGT steers to the host)")
local coopSrc, alliesSrc = readAll(MOD .. "/Scripts/sv_coop.lua"), readAll(MOD .. "/Scripts/sv_allies.lua")
check(has(coopSrc, "WOLF.holding(h.unit)") and has(alliesSrc, "WOLF.holding(u)"),
      "the co-op host's and the allies' hunts skip a flight holding its trap")

---------------------------------------------------------------------------------------------------- 6. health
print("enemyLate: the roles' health")
local function plane(unit, h)
    return { unit = unit, name = "BP_OP_test_C_1", obj = { HealthInternal = h * 10, MaxHealth = h } }
end
fresh(5)
local sk = plane("ERA_Unit_07_Dep_Air1", 60)
enemyLate(sk, 5)
check(sk.obj.HealthInternal == math.floor(600 * 0.75 + 0.5) and sk.obj.MaxHealth == 45,
      "a Skirmisher in round 5: health x0.75, MaxHealth lowered with it (45, not read as damaged)")
check(has(line("late: round 5"), "(skirm x0.75)"), "... logged with its role")
local du = plane("ERA_Unit_01_Dep_Air1", 60)
enemyLate(du, 5)
check(du.obj.HealthInternal == 600 and du.obj.MaxHealth == 60, "a duelist in round 5: untouched")
local late = TIER.lateHealthX(20)
local sk20 = plane("ERA_Unit_08_Dep_Air0", 60)
enemyLate(sk20, 20)
check(sk20.obj.HealthInternal == math.floor(600 * (late * 0.75) + 0.5), string.format("a Skirmisher in round 20: x%.3f (late x%.3f, its x0.75)", late * 0.75, late))
D.aceSquad = { ERA_Unit_07_Dep_Air2 = true }
local acePl = plane("ERA_Unit_07_Dep_Air2", 60)
enemyLate(acePl, 5)
check(acePl.obj.HealthInternal == 600, "an ace squadron in a Skirmisher flight: its own health")
ROLE.live = nil
local off = plane("ERA_Unit_07_Dep_Air1", 60)
enemyLate(off, 5)
check(off.obj.HealthInternal == 600, "roles off: untouched")
ROLE.live = saveLive

---------------------------------------------------------------------------------------------------- 7. a tier's levers
print("a tier's no_provoke and moves leave role flights alone (ACE.hunt, ACE.movesTick; U5's review)")
do
    local reaper
    for _, t in ipairs(CFG.tiers.list) do if t.name:lower() == "reaper" then reaper = t end end
    local youAt = { X = 0, Y = 0, Z = 300000 }
    local pawn = { addr = 0x9, full = "BP_PlayerPlane_PP1000_f16c_C_1", MaxHealth = 100, HealthInternal = 800 }
    function pawn:K2_GetActorLocation() return youAt end
    survivalPC = { Pawn = pawn }
    local bb = { GetValueAsObject = function() return pawn end, SetValueAsObject = function() end }
    local function acePlane(unit)                      -- 1.5 km ahead of you, you on its six
        local o = { addr = 0x500, loc = { X = 150000, Y = 0, Z = 300000 }, fwd = { X = 1, Y = 0, Z = 0 }, full = "BP_OP_x_C_1",
                    bPermissionToProvoke = true, AIStateComponent = { BlackboardComponent = bb } }
        function o:K2_GetActorLocation() return self.loc end
        function o:GetActorForwardVector() return self.fwd end
        return { obj = o, name = o.full, unit = unit, k = 0, tier = reaper }
    end
    local function moves(unit, aceSquad)
        fresh(30); D.aceSquad = aceSquad; events = {}
        local p = acePlane(unit)
        planes = { p }
        ACE.movesTick(100, D)
        pcall(ACE.hunt, p)
        return table.concat(events, ","), p.obj.bPermissionToProvoke
    end
    ROLE.live = { duelist = true, lancer = true, wolf = true, skirm = true }
    check(reaper and CFG.aces.flight.reaper.moves and CFG.aces.flight.reaper.no_provoke, "the Reaper tier has moves and no_provoke")
    local ev, prov = moves("ERA_Unit_01_Dep_Air0")
    check(ev == "RE_SV_AceTurn_01" and prov == false, "a Reaper-tier duelist: the reversal (" .. ev .. ") and no provoke, as before")
    for _, u in ipairs({ "ERA_Unit_03_Dep_Air0", "ERA_Unit_05_Dep_Air1", "ERA_Unit_07_Dep_Air0" }) do
        ev, prov = moves(u)
        check(ev == "" and prov == true and has(line("aces: " .. u), "keeps its role's own provoke and pursuit"),
              string.format("a Reaper-tier %s flight: no reversal, its own provoke (LancerBreak / WolfDrag / the defence), logged",
                  ROLE.flight(u)))
    end
    ev, prov = moves("ERA_Unit_03_Dep_Air0", { ERA_Unit_03_Dep_Air0 = true })
    check(ev == "RE_SV_AceTurn_07" and prov == false, "an ace squadron in a Lancer flight: its tier's reversal and no provoke")
    ROLE.live = nil
    ev, prov = moves("ERA_Unit_03_Dep_Air0")
    check(ev == "RE_SV_AceTurn_07" and prov == false, "roles off: every Reaper-tier flight as before")
    ROLE.live = saveLive
end

logFile:close()
print(fails == 0 and "roles test: all passed" or ("roles test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
