-- tick_loop_test.lua <mod dir> (run by tools/checks/tick_loop_test.sh): the tick loop and the key presses (0.73.82, Saint
-- Alessia's crash on launch of 2026-11-04: UE4SS's Lua faulted while the 0.73.75 watchdog logged, wrote a crumb and made
-- a callback on UE4SS's async thread as the game thread ran the ticks queued during a 54 s load). The loop's code is
-- sv_main.lua's as it is (from its state to its LoopAsync, the tick itself stubbed), KEYQ sv_core.lua's as it is:
--   the async function: one job queued when none waits or runs; nothing while one waits (under TICK_LOST_S) or runs;
--     not again within SETTLE_S of the last one's end; no log, Lua crumb, allocation or call but the clock and the
--     queueing, on every path (measured with the collector stopped and the call stack warmed, and a call hook); a lost
--     tick queued again after 10 s, then after 20, 40, each with the runtime's SV_Crumb of a fixed text (its only other
--     call there); the job logs it on the game thread (once, with the count) and the back-off starts over; a job that
--     starts between the async function's reads (inside its clock call) is never taken for none queued, nor for lost;
--   the job: the key presses first, then the tick, an error in either logged and the loop going on, no collector step
--     (the review of 2026-11-04); back-to-back queued jobs (a long load's) run each, and nothing is queued between them;
--   KEYQ: a bind (with or without modifiers) gives UE4SS a function that only counts (no allocation, the bind's own not
--     called); KEYQ.drain runs each bind's function once a press (up to KEYQ.MAX), on the game thread, with
--     ExecuteInGameThread running its function at once and put back after; an error logged, the other keys still run;
--     anything not a bind passed to UE4SS as it is.
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end

local clock = 100
local IN_ASYNC, IN_KEY = false, false
local logs, crumbs, offThread = {}, {}, {}
function log(s) if IN_ASYNC or IN_KEY then offThread[#offThread + 1] = "log: " .. s end; logs[#logs + 1] = s end
function crumb(s) if IN_ASYNC or IN_KEY then offThread[#offThread + 1] = "crumb: " .. s end; crumbs[#crumbs + 1] = s end
local CLOCK_HOOK = nil                             -- (run once inside the next clock read: a job starting right then)
os.clock = function()                             -- luacheck: ignore
    if CLOCK_HOOK then local h = CLOCK_HOOK; CLOCK_HOOK = nil; h() end
    return clock
end
local function presized(n) local t = {}; for i = 1, n do t[i] = false end; for i = n, 1, -1 do t[i] = nil end; return t end
-- the runtime's SV_Crumb (captured by the loop at load), its list made big enough now (adding to it makes nothing)
local svCrumbs = presized(64)
function SV_Crumb(s) svCrumbs[#svCrumbs + 1] = s; return 1 end

-- UE4SS: LoopAsync keeps its function, ExecuteInGameThread queues (the game thread runs the queue when the test says)
local loopFn, queue, realBinds = nil, presized(512), {}
function LoopAsync(ms, fn) loopFn = fn; return 0 end
local function realQueue(fn) queue[#queue + 1] = fn end
ExecuteInGameThread = realQueue
function RegisterKeyBind(key, a, b) realBinds[#realBinds + 1] = { key = key, a = a, b = b } end

-- KEYQ, sv_core.lua's block as it is
local coreSrc = readAll(MOD .. "/Scripts/sv_core.lua")
local kA = coreSrc:find("\nKEYQ = {", 1, true)
local kB = kA and coreSrc:find("\nend\r?\n", (coreSrc:find("\ndo\r?\n", kA)))
check(kA and kB, "sv_core.lua: the KEYQ block found")
assert(load(coreSrc:sub(kA, kB + 4), "=sv_core.lua(KEYQ)"))()
local tm = coreSrc:find("\n-- TEST ONLY BEGIN", 1, true)
local te = tm and coreSrc:find("\n-- TEST ONLY END", tm, true)
local inTest = false
while tm do
    if kA > tm and kA < (te or #coreSrc) then inTest = true end
    tm = coreSrc:find("\n-- TEST ONLY BEGIN", (te or #coreSrc), true)
    te = tm and coreSrc:find("\n-- TEST ONLY END", tm, true)
end
check(not inTest, "KEYQ is outside every TEST ONLY block (a release keeps it)")
check(coreSrc:find("\nKEYQ = {", 1, true) < coreSrc:find("RegisterKeyBind, Key.F11", 1, true),
      "KEYQ wraps RegisterKeyBind before sv_core's first bind")

-- the loop, sv_main.lua's as it is, its tick stubbed
local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
local a = mainSrc:find("\nlocal waiting, running", 1, true)
local t1 = mainSrc:find("\nlocal function tickJob()", 1, true)
local j = mainSrc:find("\nlocal function job()", 1, true)
local z = j and mainSrc:find("\n%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-[%-]+ dev keys", j)
check(a and t1 and j and z and a < t1 and t1 < j, "sv_main.lua: the loop's state, tickJob and job found")
TICKS, TICK_HOOK = 0, nil
local _, tEnd = mainSrc:find("\nend\r?\n", t1 + 1)   -- (tickJob's end: everything after it up to the dev keys, as it is)
local chunk = mainSrc:sub(a, t1) .. "local function tickJob() TICKS = TICKS + 1; if TICK_HOOK then TICK_HOOK() end end\n"
    .. mainSrc:sub(tEnd + 1, z)
assert(load(chunk, "=sv_main.lua(loop)"))()
check(type(loopFn) == "function", "LoopAsync(125, ...) given its function")
local job = nil

-- the async function, watched: no log / crumb, no allocation (the collector stopped, no hook then), and with a counting
-- call hook (it makes nothing) the calls it makes: the clock and, when it queues, ExecuteInGameThread (less 2: its own
-- call and debug.sethook's, which ends the watch)
local nCalls = 0
local function counter() nCalls = nCalls + 1 end
local function warm(n) if n > 0 then return 1 + warm(n - 1) end return 0 end   -- (Lua's call records made beforehand)
local function async()
    local before = #queue
    collectgarbage("stop")
    warm(16)
    local kb = collectgarbage("count")
    IN_ASYNC = true
    local r = loopFn()
    IN_ASYNC = false
    local grew = collectgarbage("count") - kb
    collectgarbage("restart")
    local queued = #queue > before
    if queued then job = queue[#queue] end
    return queued, r, grew
end
local function callsOf()                                 -- (one more async call, its calls counted)
    local before = #queue
    nCalls = 0
    IN_ASYNC = true
    debug.sethook(counter, "c")
    local r = loopFn()
    debug.sethook()
    IN_ASYNC = false
    local queued = #queue > before
    if queued then job = queue[#queue] end
    return nCalls - 2, queued, r                           -- (less its own call and debug.sethook's)
end
for _ = 1, 3 do debug.sethook(counter, "c"); (function() end)(); debug.sethook() end   -- (warm up the hook)
print("the async function")
local q, r, grew = async()
check(q and r == false and grew == 0 and #queue == 1 and #svCrumbs == 0,
      "nothing waiting: one job queued, nothing made, no crumb, LoopAsync kept (false)")
q, r, grew = async()
local cw = callsOf()
check(not q and grew == 0 and cw == 1, "a job waiting (0 s): nothing queued, nothing made, nothing called but the clock")
clock = clock + 9.9
q, r, grew = async()
check(not q and grew == 0, "... 9.9 s on: still nothing")

print("the job")
local ranKeys, order = 0, {}
local realDrain = KEYQ.drain
KEYQ.drain = function() ranKeys = ranKeys + 1; order[#order + 1] = "keys"; return realDrain() end
local duringRun = {}
local gcSteps = 0
local realGc = collectgarbage
TICK_HOOK = function()
    order[#order + 1] = "tick"
    collectgarbage = function(what, ...) if what == "step" then gcSteps = gcSteps + 1 end return realGc(what, ...) end
    local q2, _, g2 = async()
    local c2 = callsOf()
    duringRun[#duringRun + 1] = { q = q2, g = g2, c = c2 }
end
clock = clock + 0.05
local qn = #queue
queue[qn]()                                              -- the game thread runs it
collectgarbage = realGc
check(TICKS == 1 and ranKeys == 1 and order[1] == "keys" and order[2] == "tick", "the job ran the keys, then the tick")
check(gcSteps == 0 and not mainSrc:sub(j, z):find('collectgarbage%(?%s*"step"') and not mainSrc:sub(j, z):find("collectgarbage, \"step\"", 1, true),
      "no collector step in the job (the review of 2026-11-04)")
check(#duringRun == 1 and not duringRun[1].q and duringRun[1].g == 0 and duringRun[1].c == 0,
      "while the job runs: the async function queues nothing, makes nothing, calls nothing")
TICK_HOOK = nil
q = async()
check(not q, "right after the job ends: nothing queued (within SETTLE_S)")
clock = clock + 0.03
local cn, qn2 = callsOf()
check(qn2 and cn == 2 and #svCrumbs == 0, "30 ms on: the next queued (the clock and ExecuteInGameThread called, nothing else, no crumb)")
check(#offThread == 0, "nothing logged or crumbed off the game thread so far")

print("a job starting between the async function's reads")
do
    local co = coroutine.create(queue[#queue])
    TICK_HOOK = coroutine.yield
    clock = clock + 0.2                                  -- (the game thread held a little: the job still waiting)
    local nq = #queue
    CLOCK_HOOK = function() assert(coroutine.resume(co)) end   -- (the job starts inside the clock read, and runs on)
    loopFn()
    check(#queue == nq, "not lost yet: nothing queued while it runs (`waiting` held by the job)")
    TICK_HOOK = nil
    assert(coroutine.resume(co))
    check(coroutine.status(co) == "dead", "... the job ends")
    clock = clock + 0.05
    loopFn()                                             -- (the next one queued)
    co = coroutine.create(queue[#queue])
    TICK_HOOK = coroutine.yield
    clock = clock + 10.5                                 -- (and held past TICK_LOST_S)
    nq = #queue
    local nc, lostBefore = #svCrumbs, nil
    CLOCK_HOOK = function() assert(coroutine.resume(co)) end
    loopFn()
    check(#queue == nq and #svCrumbs == nc, "past the lost deadline: nothing queued, no crumb (the job had started)")
    TICK_HOOK = nil
    assert(coroutine.resume(co))
    local lostLogs = 0
    for _, l in ipairs(logs) do if has(l, "hadn't run the tick") then lostLogs = lostLogs + 1 end end
    check(lostLogs == 0, "... and nothing counted lost")
    clock = clock + 0.05
    loopFn()
    queue[#queue]()
    TICKS = TICKS - 3                                    -- (these three ticks aren't the counts below)
    clock = clock + 0.05
    loopFn()                                             -- (one left waiting for the next part)
end

print("a lost tick, and a long load's queued ticks")
local base = #queue
clock = clock + 10.01
q, r, grew = async()
check(q and grew == 0 and #queue == base + 1 and #offThread == 0 and #svCrumbs == 1 and has(svCrumbs[1], "tick lost"),
      "10 s waiting: queued again, nothing made, nothing logged there, the runtime's crumb (a fixed text)")
clock = clock + 10
q = async()
check(not q and #svCrumbs == 1, "... 10 s after that: not again (the next after twice as long)")
clock = clock + 10.01
local cl, ql = callsOf()
check(ql and cl == 3 and #queue == base + 2 and #svCrumbs == 2 and svCrumbs[2] == svCrumbs[1],
      "... 20 s after it: queued again (the clock, SV_Crumb and ExecuteInGameThread called, nothing else)")
clock = clock + 39
q = async()
check(not q, "... 39 s after that: not again (40)")
clock = clock + 1.1
q, r, grew = async()
check(q and grew == 0 and #queue == base + 3 and #svCrumbs == 3, "... 40 s after it: queued again, nothing made")
check(#offThread == 0 and #logs == 0, "still nothing logged anywhere (the job says it)")
-- the game thread comes back: every queued job runs one after another; nothing queued in between
local pending = {}
for i = base, #queue do pending[#pending + 1] = queue[i] end
local between = 0
for i, f in ipairs(pending) do
    f()
    if i < #pending then if async() then between = between + 1 end end
end
check(TICKS == 1 + #pending and between == 0, "the " .. #pending .. " queued jobs each ran a tick, nothing queued between them")
local said = 0
for _, l in ipairs(logs) do if has(l, "tick: the game thread hadn't run the tick queued") then said = said + 1 end end
check(said == 1 and has(logs[1], "queued again 3 times (3 so far)") and #crumbs == 1 and has(crumbs[1], "tick lost"),
      "the first of them logged it once (3 times, 3 so far), with a crumb, on the game thread")
check(#offThread == 0, "nothing logged or crumbed off the game thread")
clock = clock + 0.05
q = async()
check(q, "the loop goes on")
clock = clock + 10.01
q = async()
check(q, "a new lost tick: queued again after 10 s (the back-off started over)")
queue[#queue]()
clock = clock + 0.05
queue[#queue - 1]()                                      -- (the one taken as lost turns up: one more tick, harmless)

print("errors")
TICK_HOOK = function() error("boom") end
clock = clock + 0.05
q = async()
local n0 = #logs
queue[#queue]()
TICK_HOOK = nil
check(has(logs[#logs], "tick: error") and has(logs[#logs], "boom"), "an error in the tick logged")
clock = clock + 0.05
q = async()
check(q, "... and the loop goes on")
queue[#queue]()

print("KEYQ")
local runs, inGame = {}, {}
local before = #realBinds
RegisterKeyBind(10, { "CTRL" }, function() runs[#runs + 1] = "A"; ExecuteInGameThread(function() inGame[#inGame + 1] = "A" end) end)
RegisterKeyBind(11, function() runs[#runs + 1] = "B" end)
RegisterKeyBind(12, { "CTRL" }, function() error("key C broke") end)
RegisterKeyBind(13, { "CTRL" }, function() ExecuteInGameThread(function() error("key D's inner broke") end) end)
RegisterKeyBind(14, "not a function")
check(#realBinds == before + 5 and realBinds[before + 1].key == 10 and type(realBinds[before + 1].b) == "function"
      and realBinds[before + 1].a[1] == "CTRL" and type(realBinds[before + 2].a) == "function" and realBinds[before + 2].b == nil,
      "binds passed on with their modifiers (3 arguments) or without (2), each with a counting function")
check(realBinds[before + 5].a == "not a function", "anything not a bind passed on as it is")
local pA, pB = realBinds[before + 1].b, realBinds[before + 2].a
collectgarbage("stop")
warm(16)
local kb = collectgarbage("count")
IN_KEY = true
pA(); pA(); pB()
IN_KEY = false
local kgrew = collectgarbage("count") - kb
collectgarbage("restart")
check(kgrew == 0 and #runs == 0 and #offThread == 0, "a press on UE4SS's thread: counted only (nothing made, nothing run, nothing logged)")
local qBefore = #queue
KEYQ.drain = realDrain
realDrain()
check(#runs == 3 and runs[1] == "A" and runs[2] == "A" and runs[3] == "B", "the drain: each press run once (A twice, B once)")
check(#inGame == 2 and #queue == qBefore and ExecuteInGameThread == realQueue,
      "ExecuteInGameThread ran its function at once meanwhile (nothing queued) and was put back")
realDrain()
check(#runs == 3, "drained again: nothing new")
for _ = 1, 9 do pB() end
realBinds[before + 3].b(); realBinds[before + 4].b()
local nl = #logs
realDrain()
check(#runs == 3 + KEYQ.MAX, "9 presses between two drains: run KEYQ.MAX (" .. KEYQ.MAX .. ") times")
local errs = 0
for i = nl + 1, #logs do if has(logs[i], "keys: error") then errs = errs + 1 end end
check(errs == 2 and ExecuteInGameThread == realQueue, "a key's error and its inner function's error logged, the others ran, ExecuteInGameThread put back")
pA()
clock = clock + 0.05
q = async()
local r0 = #runs
queue[#queue]()
check(#runs == r0 + 1 and runs[#runs] == "A", "the tick's job runs the presses")

print(fails == 0 and "tick_loop_test: all passed" or ("tick_loop_test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
