-- perf_test.lua <mod dir> <work dir> (run by tools/checks/perf_test.sh): Workstream B's lag fixes (0.73.77; the plan
-- "Survival COOP: Desync, Lag and Compatibility Plan", B1-B5) on the real sv_core, sv_config, sv_ladon and sv_main's
-- chunks (creditKill .. probeTick, the natives .. the perf line), the game and the runtime stubbed:
--   B2 a long run (40 rounds of 30 aircraft, a co-op joiner's and the host's): `planes` loses its downed planes 10 s on
--     (prunePlanes, every 2 s), stays bounded, never while a Ladon round keeps its index (s.planeFrom); the first logged;
--   B5 the Ladon missiles: kept as they're made (HIT.new -> HIT.ladonPool), the toning sweep over them, the walk for the
--     two classes every 10 s instead of twice each sweep; a gone one off the pool; the pool bounded over the run;
--     a far missile's position read every other tick, a near one's every tick;
--   B1 the perf line: every part named, the shares within a part ("allies/...") apart and not counted twice, the untimed
--     rest; its second line: the lists' sizes (planes, held, allies, missiles, the co-op ones through COOP.sizes), the
--     walks by class (sv_core.lua WALK.stat), the natives (SV_UnitAlive ... counted and timed), the Lua heap;
--   the source: every call the tick halves make is timed (by name), the native wrappers pass every value through.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

VERSION = "0.73.77-perf.test"
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
function FName(s) return s end
local found, walked = {}, {}
function FindAllOf(c) walked[#walked + 1] = c; clock = clock + 0.004; return found[c] end   -- (a walk takes 4 ms here)
function FindFirstOf(c) walked[#walked + 1] = "first:" .. c; return nil end
function StaticFindObject() return nil end
local unitAsks = 0
function SV_UnitAlive() unitAsks = unitAsks + 1; return 2 end
function SV_Event(name) return name == "RE_SV_Two" and 1 or 1, "second" end
function SV_SetText() return 1 end
function SV_Spawn() return 1 end
function SV_ObjChain() return 1 end

local function run(name, chunk) assert(load(readAll(MOD .. "/Scripts/" .. name), chunk or ("=" .. name)))() end
run("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function liveAddr(o) return valid(o) and addrOf(o) or nil end
function liveObj(o) return valid(o) end
run("sv_config.lua")
run("sv_ladon.lua")
local function line(pat, from) for i = #logs, from or 1, -1 do if logs[i]:find(pat) then return logs[i] end end return nil end
local function count(pat, from) local n = 0; for i = from or 1, #logs do if logs[i]:find(pat) then n = n + 1 end end return n end

-- sv_main.lua's chunks
local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
local cA, cB = mainSrc:find("\nlocal function creditKill%(p%)"), mainSrc:find("\nlocal function probeTick%(tick%)")
check(cA and cB and cA < cB, "sv_main.lua: creditKill .. probeTick found")
local _, timed, _, prunePlanes = assert(load(mainSrc:sub(cA, cB) ..
    "\nreturn creditKill, timed, planeSweep, prunePlanes\n", "=sv_main.lua"))()
check(type(prunePlanes) == "function" and type(PERF) == "table" and type(PERF.add) == "function",
      "the chunk loads: prunePlanes, PERF.add (the parts' timer)")
local nA, nB = mainSrc:find("\n%-%- %(0%.73%.77, Workstream B1%) The natives"), mainSrc:find("\n%-%- Everything runs from this one loop")
check(nA and nB and nA < nB, "sv_main.lua: the natives .. the perf line found")
local rawUnitAlive, rawEvent = SV_UnitAlive, SV_Event
local perfLine = assert(load(mainSrc:sub(nA, nB) .. "\nreturn perfLine\n", "=sv_main.lua"))()
check(type(perfLine) == "function" and SV_UnitAlive ~= rawUnitAlive and SV_Event ~= rawEvent,
      "the perf line's chunk loads; SV_UnitAlive and SV_Event wrapped")
local a1, a2 = SV_Event("RE_SV_Two")
check(a1 == 1 and a2 == "second", "a wrapped native passes every value back (" .. tostring(a1) .. ", " .. tostring(a2) .. ")")
function memText() return "memory 1 MB, committed 2 MB" end

---------------------------------------------------------------------------------------------------- B2: the plane list
print("B2: the plane list over a long run")
local nextAddr = 0x1000
local function plane(unit)
    nextAddr = nextAddr + 0x10
    local o = { addr = nextAddr, full = "BP_OP1022_f16c_CP_C_" .. nextAddr, HealthInternal = 1000 }
    return { obj = o, name = o.full, unit = unit, addr = o.addr }
end
-- a run: each round 30 aircraft, each shot down 20-60 s after it's made; the sweep marks them down (here: p.down), the
-- prune runs every 2 s (probeTickB's slot 0)
local function longRun(rounds, special)
    planes, pending = {}, {}
    PERF.pruned = 0
    D = { round = 0, now = 0, up = {}, vanished = {}, special = special }
    local most, made = 0, 0
    for r = 1, rounds do
        D.round = r
        local born = {}
        for i = 1, 30 do
            local p = plane("ERA_Unit_01_Dep_Air" .. (i % 8))
            planes[#planes + 1] = p
            born[#born + 1] = { p = p, at = clock + 20 + (i % 5) * 10 }
            made = made + 1
        end
        for _ = 1, 45 do                            -- (90 s of the round, the prune every 2 s)
            clock = clock + 2
            for _, b in ipairs(born) do if not b.p.down and clock >= b.at then b.p.down = true end end
            prunePlanes()
            most = math.max(most, #planes)
        end
    end
    return most, made
end
do                                                  -- a co-op joiner: no rounds of its own (no pruneDown at a round's start)
    COOP = { client = function() return true end }
    local from = #logs + 1
    local most, made = longRun(40)
    check(made == 1200 and most <= 30 and #planes <= 30,
          string.format("a joiner's 40 rounds (%d aircraft made): at most %d on the list at once, %d at the end", made, most, #planes))
    check(PERF.pruned >= 1170, "... the downed ones taken off (" .. PERF.pruned .. ")")
    check(count("^round probe: %d+ downed aircraft off the list 10 s after they went down", from) == 1,
          "the first prune logged once: " .. tostring(line("^round probe: %d+ downed aircraft off the list", from)))
    COOP = nil
end
do                                                  -- a plane down 10 s exactly: off; 9 s: still on
    planes, D = {}, { round = 1, now = 0 }
    local a, b = plane("U1"), plane("U2")
    planes = { a, b }
    a.down = true
    prunePlanes()                                   -- (seen down now)
    clock = clock + 9
    b.down = true
    prunePlanes()
    check(#planes == 2, "a plane down 9 s: still on the list (others may read it a few seconds on)")
    clock = clock + 1
    prunePlanes()
    check(#planes == 1 and planes[1] == b, "... 10 s: off; the one down 1 s stays")
end
do                                                  -- a Ladon round keeps its index into the list: no prune then
    local most = longRun(2, { kind = "ladon", planeFrom = 1 })
    check(most == 60 and #planes == 60 and PERF.pruned == 0, "a Ladon round (s.planeFrom): nothing taken off mid-round (" .. #planes .. ")")
end
do                                                  -- the host: a round's start still prunes them all at once (sv_rounds.lua)
    local src = readAll(MOD .. "/Scripts/sv_rounds.lua")
    check(has(src, "for _, p in ipairs(planes) do if not p.down then keep[#keep + 1] = p end end"), "the host's round-start prune is kept (pruneDown)")
end

---------------------------------------------------------------------------------------------------- B5: the Ladon missiles
print("B5: the Ladon missiles")
check(type(LEVEL_DROPS) ~= "table" or type(LEVEL_DROPS.hits) == "function",
      "the teardown gate's drop for the hits' kept missiles registered (LEVEL_DROPS.hits)")
local lvl = "/Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel."
local function missile(cls, x)
    nextAddr = nextAddr + 0x10
    local m = { addr = nextAddr, full = cls .. "_C " .. lvl .. cls .. "_C_" .. nextAddr, damage = 50, MaxHomingAngle = 60,
                MaxRotationAngle = 90, x = x or 500000, reads = 0 }
    function m:K2_GetActorLocation() self.reads = self.reads + 1; return { X = self.x, Y = 0, Z = 0 } end
    function m:GetOwner() return nil end
    return m
end
local function made(list) for _, o in ipairs(list) do for _, fn in ipairs(notify["/Script/Live.LiveMissile"] or {}) do fn(o) end end end
local you = { addr = 9, full = "BP_PlayerPlane_PP1000_f16c_C_1", HealthInternal = 800, MaxHealth = 100 }
function you:K2_GetActorLocation() return { X = 0, Y = 0, Z = 0 } end
function you:GetAddress() return 9 end
local pc = { Pawn = you }
HIT.reset()
local ladon = plane("SV_Unit_LadonKot")
planes, D = { ladon }, { round = 5, now = 0 }
local vls = {}
for i = 1, 24 do vls[i] = missile("BP_wp_vls_ladon") end
local sure = missile("BP_wp_vls_certain_ladon")
sure.damage = 9999
made(vls); made({ sure })
found = { BP_wp_vls_ladon_C = vls, BP_wp_vls_certain_ladon_C = { sure } }
local w0 = #walked
local now = 100
HIT.tick(pc, now)
local kept = 0
for _ in pairs(HIT.ladonPool) do kept = kept + 1 end
check(kept == 25, "the 24 VLS missiles and the sure kill kept as they're made (" .. kept .. ")")
check(sure.damage <= 10.5 and vls[1].damage <= 10.5, "toned down as they came in")
local wFirst = #walked - w0
for i = 1, 80 do                                   -- 20 s of a Ladon up: the sweep every 0.5 s, every tick of 250 ms
    now = now + 0.25
    vls[(i % 24) + 1].damage = 50                  -- (launched again from the pool: the game's own damage back)
    sure.damage = 9999
    HIT.tick(pc, now)
end
local walks = 0
for i = w0 + 1, #walked do if walked[i] == "BP_wp_vls_ladon_C" then walks = walks + 1 end end
check(walks <= 3, string.format("20 s of a Ladon up: the walk for its missiles %d times (every 10 s; it was twice every 0.5 s: 40)", walks))
check(vls[1].damage <= 10.5 and vls[13].damage <= 10.5 and sure.damage <= 10.5, "... and every one launched again toned down again")
check(wFirst <= 2, "the first sweep: one walk a class at most (" .. wFirst .. ")")
check(line("^hits: the Ladons' missiles toned from their pool") ~= nil, "logged once: " .. tostring(line("^hits: the Ladons' missiles toned")))
vls[5].gone = true
now = now + 0.5
HIT.tick(pc, now)
check(HIT.ladonPool[vls[5].addr] == nil, "a missile gone: off the pool at once, never touched again")
HIT.ladonPool[vls[6].addr].name = "something else"   -- (its address another object's now)
now = now + 0.5
HIT.tick(pc, now)
check(HIT.ladonPool[vls[6].addr] == nil, "an address used again (its name not the missile's): off the pool")
do                                                  -- the missiles near you: a far one read every other tick
    local far, near = missile("BP_wp_msl_a0", 500000), missile("BP_wp_msl_a0", 100000)
    made({ far, near })
    now = now + 0.25; HIT.tick(pc, now)             -- (taken in: read once)
    local f0, n0 = far.reads, near.reads
    for _ = 1, 8 do now = now + 0.25; HIT.tick(pc, now) end
    check(near.reads - n0 == 8 and far.reads - f0 == 4, string.format("a missile 1 km off read every tick (%d of 8), one 5 km off every other (%d of 8)",
          near.reads - n0, far.reads - f0))
end
do                                                  -- the pool over a long run: bounded by what's live
    for r = 1, 30 do
        local burst = {}
        for i = 1, 20 do burst[i] = missile("BP_wp_vls_ladon") end
        made(burst)
        now = now + 0.5; HIT.tick(pc, now)
        for _, m in ipairs(burst) do m.gone = true end   -- (the level's pools freed: a restart, a new level)
        now = now + 0.5; HIT.tick(pc, now)
    end
    local k = 0
    for _ in pairs(HIT.ladonPool) do k = k + 1 end
    check(k <= 25, "30 bursts of 20 made and freed: the pool keeps only the live ones (" .. k .. ")")
    check(#HIT.msl <= 60, "the missiles tracked: 60 at most (" .. #HIT.msl .. ")")
end

---------------------------------------------------------------------------------------------------- B1: the perf line
print("B1: the perf line")
do
    planes = {}
    for i = 1, 12 do planes[i] = plane("U" .. i); planes[i].down = i > 9 end
    pending = { {}, {} }
    ALLY.run = { planes = { {}, {} }, up = { SV_Unit_MoonchildA = {} }, esmFields = { [1] = {} }, defActors = { {}, {}, {} } }
    KILL = { fired = { [1] = 1, [2] = 2 } }
    SH = { decor = { [1] = {} } }
    RUN = { metrics = { kills = { 1, 2, 3 }, tw = { 1 } } }
    WLOG = { sizes = function() return { { "weapon objects", 140 } } end }
    COOP = { sizes = function() return { { "copies", 33 }, { "dead ids", 1200 } } end }
    D = { round = 12, now = 500, up = { A = true, B = true }, vanished = { {} }, events = {} }
    PERF.pruned = 17
    local from = #logs + 1
    local tick = 1000
    for i = 1, 241 do                               -- a minute: every part timed, two shares of the allies part
        local t0 = os.clock()
        clock = clock + 0.002; PERF.add("rounds", t0)
        t0 = os.clock(); clock = clock + 0.003; PERF.add("allies", t0)
        PERF.add("allies/counts", t0 + 0.002)       -- (1 ms of the allies' 3: within it)
        t0 = os.clock(); clock = clock + 0.0005; PERF.add("leave check", t0)
        if i % 8 == 0 then FindAllOf("TextBlock") end
        SV_UnitAlive("SV_Unit_AAGun_A")
        SV_ObjChain(1); SV_ObjChain(2); SV_ObjChain(3)
        tick = tick + 1
        perfLine(7, 3, tick)                       -- (10 ms a tick: 2 + 3 + 0.5 timed)
    end
    local L1 = line("^perf: tick avg", from)
    local L2 = line("^perf: lists: ", from)
    check(L1 and has(L1, "tick avg 10.0 ms (halves 7.0 + 3.0)"), "the perf line: " .. tostring(L1))
    check(L1 and has(L1, "rounds 2.0/") and has(L1, "allies 3.0/") and has(L1, "leave check 0.5/"), "... every part by name")
    check(L1 and has(L1, "untimed 4.5 ") and has(L1, "within them: allies/counts 1.0/"),
          "... the untimed rest (10 - 5.5 = 4.5: the shares not counted twice), the shares within a part apart")
    check(L2 and has(L2, "planes 12 (9 up; 17 down taken off since)") and has(L2, "new planes 2") and has(L2, "held 1")
          and has(L2, "flights up 2") and has(L2, "allied planes 2") and has(L2, "allies up 1") and has(L2, "ESM fields 1")
          and has(L2, "defences' actors 3") and has(L2, "kill marks 2") and has(L2, "store icons 1") and has(L2, "kill records 3")
          and has(L2, "weapon objects 140") and has(L2, "co-op copies 33") and has(L2, "co-op dead ids 1200"),
          "the second line: the lists' sizes (" .. tostring(L2) .. ")")
    check(L2 and L2:find("walks: %d+ %(") and has(L2, "TextBlock ") and has(L2, "found)"), "... the walks by class, with what they found")
    check(L2 and has(L2, "natives: SV_UnitAlive 1.0 a tick") and L2:find("Lua heap [%d%.]+ MB$"), "... the natives counted a tick, the Lua heap")
    check(L2 and has(L2, "SV_ObjChain 3 a tick"), "... SV_ObjChain (liveAddr's) counted only")
    check(PERF.pruned == 0 and D.perf == nil, "the counts start again after each line")
    from = #logs + 1
    for _ = 1, 1199 do tick = tick + 1; perfLine(1, 1, tick) end
    check(line("^perf: tick avg", from) == nil, "then every 5 minutes (none within 1199 ticks)")
end

---------------------------------------------------------------------------------------------------- the source
print("the source: every call the tick halves make, timed")
do
    local function body(from)
        local a = mainSrc:find(from)
        local b = a and mainSrc:find("\nend\r?\n", a + 1)
        return a and mainSrc:sub(a, b or #mainSrc) or ""
    end
    local pt, ptB = body("\nlocal function probeTick%(tick%)"), body("\nlocal function probeTickB%(tick%)")
    local loop = mainSrc:sub(mainSrc:find("\nLoopAsync%(125") or 1)
    for _, n in ipairs({ "shop rows", "setup", "leave check", "restart check", "clock", "music hold", "death check", "rounds",
                         "hud", "music", "airfield", "bombers" }) do
        check(has(pt, '"' .. n .. '"'), "probeTick: \"" .. n .. "\" timed")
    end
    for _, n in ipairs({ "leave check", "shop", "allies", "icons", "ammo panel", "sound", "hits", "kill marks", "beat", "new planes",
                         "planes", "prune", "stats sample", "jammer", "flags", "verbose", "ammo", "difficulty" }) do
        check(has(ptB, '"' .. n .. '"'), "probeTickB: \"" .. n .. "\" timed")
    end
    for _, n in ipairs({ "rows watch", "info maps", "speakers", "leaderboard", "menu", "coop" }) do
        check(has(loop, '"' .. n .. '"'), "the loop: \"" .. n .. "\" timed")
    end
    -- no pcall left untimed in either half but the ones inside a timed block (perfAdd's), the level load's (no run yet)
    -- and the inner calls the timed blocks cover
    local loose = {}
    for l in (ptB .. "\n"):gmatch("([^\n]*)\n") do
        if l:find("pcall%(") and not l:find("timed%(") and not l:find("^%s*%-%-") then loose[#loose + 1] = l:match("^%s*(.-)%s*$") end
    end
    local allowed = { "pcall(probeTickB", "pcall(logPlane", "hookErr(\"stats: STATS.sample\"" }
    local bad = {}
    for _, l in ipairs(loose) do
        local ok = false
        for _, a in ipairs(allowed) do if l:find(a, 1, true) then ok = true end end
        if not ok then bad[#bad + 1] = l end
    end
    check(#bad == 0, "probeTickB: every pcall timed (" .. (#bad > 0 and table.concat(bad, " | ") or "none loose") .. ")")
    check(has(readAll(MOD .. "/Scripts/sv_core.lua"), "return timedWalk(rawAll, tostring(cls), cls)"), "sv_core: every FindAllOf timed by class")
    check(has(readAll(MOD .. "/Scripts/sv_allies.lua"), 'pa("allies/defence health", t0)')
          and has(readAll(MOD .. "/Scripts/sv_shop.lua"), 'pa("shop/texts", t0)'), "the allies' and the shop's shares timed")
end

print(fails == 0 and "perf test: all passed" or ("perf test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
