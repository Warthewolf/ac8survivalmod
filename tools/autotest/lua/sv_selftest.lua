-- sv_selftest.lua: the autotest's in-game self-test (tools/autotest/kit.py puts it LAST in the installed main.lua's
-- MODULES, for a gated test run only; it's in no build). It reads Scripts/selftest.txt (suite=, max_s=, menu_wait_s=),
-- gets into Survival's level on its own (GameplayStatics.OpenLevel from the main menu: no input), holds your plane
-- (invincible; the runtime's DOWN autopilot round the airfield once airborne, as the soak test), runs the suite's steps
-- and logs `selftest: PASS <what>` / `selftest: FAIL <what>`, then `selftest: RESULT <passed>/<total>`. The job
-- (tools/autotest/job.py) closes the game then: the fast path skips the menu's mission setup, so the game's own end flow
-- must never run into QuitGame. It runs on Survival's own tick (MENU.tick, the game thread), touches nothing while the
-- level is going (levelGoing), and watches Survival's log lines (the global log, wrapped) for the steps that only say
-- what they did there (the Tanacorn's railguns and railcannon).
-- A suite is a list of steps run in order, a few a tick, never a coroutine: UE4SS's functions called from a coroutine fail
-- ("The lua state ... has no instance inside lua_instances unordered map", 2026-11-16's run 10), and so does everything
-- of Survival's that calls them.
SELFTEST = { pass = 0, fail = 0, lines = {}, n = 0, marks = {}, conf = { suite = "smoke", max_s = 600, menu_wait_s = 25 } }
do
local ST = SELFTEST
local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
do
    local f = io.open(DIR .. "selftest.txt", "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k then ST.conf[k] = tonumber(v) or v end
        end
        f:close()
    end
end

local function say(msg) log("selftest: " .. msg) end
-- every log line Survival writes from here on, kept (the last 6000) for the log waits
do
    local orig = log
    local MAXL = 6000
    log = function(msg, ...)
        local s = tostring(msg)
        ST.n = ST.n + 1
        ST.lines[ST.n] = s
        ST.lines[ST.n - MAXL] = nil
        return orig(msg, ...)
    end
end
function ST.check(ok, what, detail)
    if ok then ST.pass = ST.pass + 1 else ST.fail = ST.fail + 1 end
    say((ok and "PASS " or "FAIL ") .. what .. (detail and (" (" .. tostring(detail) .. ")") or ""))
    return ok
end
function ST.info(msg) say("INFO " .. msg) end
function ST.findLog(pat, since, plain)
    for i = math.max((since or 0) + 1, ST.n - 5999), ST.n do
        local s = ST.lines[i]
        if s and s:find(pat, 1, plain) then return s, i end
    end
    return nil
end

-- a test key pressed: its recorded callback run (sv_selftest_keys.lua)
function ST.press(name)
    local key = Key and Key[name]
    if key == nil then return 0 end
    local n = 0
    for _, b in ipairs(SELFTEST_BINDS or {}) do
        if b.key == key and b.ctrl and type(b.fn) == "function" then
            n = n + 1
            local ok, err = pcall(b.fn)
            if not ok then say("Ctrl+" .. name .. " callback error " .. tostring(err)) end
        end
    end
    say(string.format("pressed Ctrl+%s (%d callback%s)", name, n, n == 1 and "" or "s"))
    return n
end

-- the local player controller (GameplayStatics.GetPlayerController(game instance, 0), sv_flights.lua pcFromGame's way)
-- and your plane
function ST.pc()
    if liveObj(survivalPC) then return survivalPC end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local gi = type(gameInstance) == "function" and gameInstance() or nil
    if not (gs and valid(gs) and gi) then return nil end
    local ok, pc = pcall(function() return gs:GetPlayerController(gi, 0) end)
    if ok and pc ~= nil and valid(pc) then return pc end
    return nil
end
function ST.plane()
    local pc = ST.pc()
    local pawn = pc and pc.Pawn or nil
    return valid(pawn) and pawn or nil
end
function ST.who()                                         -- (the heartbeat: which player classes have live objects)
    local t = {}
    for _, c in ipairs({ "PlayerController", "LivePlayerController", "LocalPlayer", "BP_LiveGameInstance_C" }) do
        local ok, l = pcall(FindAllOf, c)
        t[#t + 1] = c .. " " .. ((ok and type(l) == "table") and #l or 0)
    end
    return table.concat(t, ", ")
end
function ST.openSurvival()
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local pc = ST.pc()
    local ctx = pc or (type(gameInstance) == "function" and gameInstance()) or nil
    if not (gs and valid(gs) and ctx) then return false, "no GameplayStatics or world context" end
    local ok, err = pcall(function() gs:OpenLevel(ctx, FName(LEVEL), true, "") end)
    return ok, ok and ("OpenLevel " .. LEVEL .. " with " .. (pc and "the player controller" or "the game instance"))
        or tostring(err)
end
local HOLD = { inv = 0, ap = 0, apOn = nil, ground = false }
local function holdPlane(now)
    local pawn = ST.plane()
    if not pawn then return end
    if now >= HOLD.inv then
        HOLD.inv = now + 2
        pcall(function() pawn:SetIsInvincible(true) end)
    end
    local a = addrOf(pawn)
    if a and type(SV_Down) == "function" and (a ~= HOLD.apOn or now >= HOLD.ap) then
        HOLD.ap = now + 30
        if playerOnAirfield and playerOnAirfield() then
            if not HOLD.ground then HOLD.ground = true; ST.info("your plane is on the airfield: the autopilot waits") end
            return
        end
        local okD, r = pcall(SV_Down, a, AIRFIELD.X, AIRFIELD.Y, 2500, 5000)
        if playerLocationDirty then playerLocationDirty() end
        if a ~= HOLD.apOn then ST.info("the autopilot round the airfield: " .. (okD and tostring(r) or ("error " .. tostring(r)))) end
        if okD and r == 1 then HOLD.apOn = a else HOLD.apOn = nil end
    end
end
function ST.healthOf(o)
    local h, mx
    pcall(function() h = o.HealthInternal end)
    pcall(function() mx = o.MaxHealth end)
    return tonumber(h), tonumber(mx)
end
function ST.same(e) return e and liveAddr(e.o) == e.a and nameOf(e.o) == e.name end   -- (hard rule 59)

-- ---- the steps ---------------------------------------------------------------------------------------------------
-- Q: { kind, ... } each; the tick runs the current one (and the next, up to 8 a tick, while they finish at once).
--   do_(fn)                      fn() once; return "abort" to skip the rest
--   wait(s)
--   until_(cond, timeout, done)  cond() each tick until truthy or timeout; done(value or nil)
--   log_(pat, timeout, mark, plain, done)  a log line since the mark (ST.marks[mark] or 0) matching pat; done(line or nil)
--   mark(name)                   ST.marks[name] = the line count now
local Q, qi, at = {}, 1, nil
local A = {}
function A.do_(fn) Q[#Q + 1] = { k = "do", fn = fn } end
function A.wait(s) Q[#Q + 1] = { k = "wait", s = s } end
function A.until_(cond, timeout, done) Q[#Q + 1] = { k = "until", cond = cond, t = timeout, done = done } end
function A.log_(pat, timeout, mark, plain, done)
    Q[#Q + 1] = { k = "until", t = timeout, done = done, cond = function()
        return ST.findLog(pat, mark and ST.marks[mark] or 0, plain) end }
end
function A.mark(name) A.do_(function() ST.marks[name] = ST.n end) end
local aborted = false
local function stepOnce(now)
    local s = Q[qi]
    if not s then return false end
    if s.k == "do" then
        local ok, r = pcall(s.fn)
        if not ok then ST.check(false, "a step's error: " .. tostring(r)); r = "abort" end
        if r == "abort" then aborted = true; qi = #Q + 1; return false end
        qi = qi + 1
        return true
    end
    at = at or now
    if s.k == "wait" then
        if now - at < s.s then return false end
    else
        local ok, v = pcall(s.cond)
        if not (ok and v) and now - at < s.t then return false end
        local okD, r = pcall(s.done or function() end, (ok and v) or nil)
        if not okD then ST.check(false, "a step's error: " .. tostring(r)); r = "abort" end
        if r == "abort" then aborted = true; qi = #Q + 1; at = nil; return false end
    end
    at = nil
    qi = qi + 1
    return true
end

-- ---- the way in (every suite) ------------------------------------------------------------------------------------
local function intoRun()
    A.do_(function() ST.doing = "waiting for the main menu's world" end)
    A.log_("world: /Game/Maps/Menu/PL_MainMenu", 240, nil, true, function(l)
        if not ST.check(l ~= nil, "the main menu's world loaded", l) then return "abort" end
        ST.doing = "the main menu's wait"
    end)
    A.wait(ST.conf.menu_wait_s)
    A.do_(function()
        ST.info("at the main menu: " .. ST.who() .. "; a player controller " .. tostring(ST.pc() ~= nil))
        local ok, how = ST.openSurvival()
        if not ST.check(ok, "Survival's level asked for", how) then return "abort" end
        ST.doing = "waiting for Survival's level, a run and your plane"
    end)
    A.until_(function() return D and D.now and nativeReady() and ST.plane() end, 240, function(v)
        if not ST.check(v ~= nil, "Survival's level loaded: a run (D), the spawner, your plane") then return "abort" end
        ST.doing = "settling"
    end)
    A.wait(5)
    A.do_(function()
        local inv
        pcall(function() inv = ST.plane().bIsInvincible end)
        ST.check(inv == true, "your plane invincible (SetIsInvincible read back)", tostring(inv))
        ST.info(string.format("run state %s, round %s; on the airfield %s", tostring(D and D.state), tostring(D and D.round),
            tostring(playerOnAirfield and playerOnAirfield())))
        ST.doing = "the suite"
    end)
end

-- ---- suites ------------------------------------------------------------------------------------------------------
local SUITES = {}
SUITES.smoke = function()
    intoRun()
    A.wait(20)
    A.do_(function() ST.check(ST.plane() ~= nil and D ~= nil, "still in the run 20 s on") end)
end

-- THE TANACORN (a TANI=1 build): Ctrl+L's live hull, her armour, no death chain, the railguns, the railcannon
local function partsSeen()
    local seen = TANI and TANI.liveSeen and TANI.liveSeen()
    local n = 0
    for _ in pairs(seen or {}) do n = n + 1 end
    return n, seen or {}
end
local function healthTable(seen)
    local t = {}
    for s, e in pairs(seen) do t[s] = ST.same(e) and ST.healthOf(e.o) or false end
    return t
end
local function pick(seen, pat)
    local names = {}
    for s, e in pairs(seen) do if s:find(pat) and ST.same(e) and (ST.healthOf(e.o) or 0) > 0 then names[#names + 1] = s end end
    table.sort(names)
    return names[1]
end
-- one part finished off: it goes down, nothing else does (the tester's "if the Tanacorn is hit, everything immediately dies")
local function chainTest(C, label, pats)
    local P = {}
    A.do_(function()
        local _, seen = partsSeen()
        for _, pat in ipairs(pats) do P.socket = P.socket or pick(seen, pat) end
        if not ST.check(P.socket ~= nil, "a live " .. label .. " part to finish off") then return end
        P.seen, P.before, P.hh0 = seen, healthTable(seen), ST.healthOf(C.hull)
        local dead, h, how = finishUnpaid(seen[P.socket].o)
        ST.check(dead == true, "Part_" .. P.socket .. " finished off", string.format("health %s, %s", tostring(h), tostring(how)))
    end)
    A.wait(4)
    A.do_(function()
        if not P.socket then return end
        local after, hurt = healthTable(P.seen), {}
        for s, h0 in pairs(P.before) do
            if s ~= P.socket and h0 and h0 > 0 then
                local h1 = after[s]
                if not h1 or h1 < h0 then hurt[#hurt + 1] = string.format("%s %s -> %s", s, tostring(h0), tostring(h1)) end
            end
        end
        table.sort(hurt)
        ST.check(#hurt == 0, "no other part hurt 4 s after Part_" .. P.socket .. " went down (no death chain)",
            #hurt > 0 and (#hurt .. ": " .. table.concat(hurt, ", ", 1, math.min(#hurt, 10))) or "all as before")
        local hh1 = ST.healthOf(C.hull)
        ST.check(P.hh0 ~= nil and hh1 == P.hh0, "the hull's health unchanged after Part_" .. P.socket .. " went down",
            tostring(P.hh0) .. " -> " .. tostring(hh1))
    end)
end
SUITES.tanacorn = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(TANI and TANI.live and TANI.liveHull, "THE TANACORN's Lua is in this build (sv_tanicorn)") then return "abort" end
        ST.marks.m0 = ST.n
        ST.press("L")
    end)
    A.until_(function() return TANI.liveHull() end, 30, function(h)
        C.hull = h
        if not ST.check(h ~= nil, "Ctrl+L: her live hull spawned and found", ST.findLog("tanicorn: Ctrl+L", ST.marks.m0, true)) then
            return "abort"
        end
        C.want = #TANI.live.parts
    end)
    A.until_(function() return partsSeen() >= C.want end, 15, function()
        local n = partsSeen()
        ST.check(n >= C.want, string.format("all %d live parts seen", C.want), n .. " seen")
    end)
    A.log_("tanicorn: armour: %d+ of %d+ parts", 10, "m0", false, function(l)
        ST.check(l ~= nil and l:find("no death blast", 1, true) ~= nil, "the parts' armour written (no death blast)", l)
        local cbd, inv
        pcall(function() cbd = C.hull.bCanBeDamaged end)
        pcall(function() inv = C.hull.bIsInvincible end)
        ST.check(cbd == false and inv == true, "her hull can't be damaged (bCanBeDamaged false, bIsInvincible true)",
            "read now: bCanBeDamaged " .. tostring(cbd) .. ", bIsInvincible " .. tostring(inv) .. "; " ..
            tostring(ST.findLog("tanicorn: armour (Ctrl+L): the hull", ST.marks.m0, true)))
        C.hh0 = ST.healthOf(C.hull)
    end)
    A.wait(6)                                             -- (the +2.5 s orders, the +8 s look)
    chainTest(C, "T5", { "^T5" })
    chainTest(C, "VLS block", { "^VLSS_L", "^VLS" })
    C.railUp = {}
    for _, side in ipairs({ "L", "R" }) do                 -- the railguns (stage 4)
        local rg = "RAILGUN_" .. side
        -- (either way it ends: deployed, or its NOT ordered line, 2026-11-16's first run: the drawn muzzle never rose)
        A.until_(function()
            return ST.findLog("tanicorn rail: " .. rg .. " deployed", ST.marks.m0, true)
                or ST.findLog("tanicorn rail: " .. rg .. " NOT ordered", ST.marks.m0, true)
        end, 20, function(l)
            C.railUp[side] = ST.check(l ~= nil and l:find(" deployed: ", 1, true) ~= nil and l:find("(up)", 1, true) ~= nil,
                rg .. " deployed (lift up, muzzle raised as drawn)", l or ST.findLog("tanicorn rail: " .. rg, ST.marks.m0, true))
        end)
        A.until_(function()
            return not C.railUp[side] or ST.findLog("tanicorn rail: " .. rg .. " RE_SV_TaniRailOrder" .. side .. " fired", ST.marks.m0, true)
        end, 10, function(l)
            if C.railUp[side] then ST.check(type(l) == "string", rg .. " ordered (its remote event fired after the read-back)", l) end
        end)
    end
    for _, side in ipairs({ "L", "R" }) do
        local rg = "RAILGUN_" .. side
        A.until_(function()
            return not C.railUp[side] or ST.findLog("tanicorn rail: " .. rg .. " its barrel moves", ST.marks.m0, true)
        end, 25, function(l)
            if C.railUp[side] then
                ST.check(type(l) == "string", rg .. "'s barrel moves after its order", l or ST.findLog("tanicorn rail: " .. rg, ST.marks.m0, true))
            end
        end)
    end
    A.until_(function()
        return not (C.railUp.L or C.railUp.R) or ST.findLog("tanicorn: RAILGUN_[LR] shell 1", ST.marks.m0)
    end, 40, function(l)
        if C.railUp.L or C.railUp.R then ST.check(type(l) == "string", "a railgun fired (its first EML round seen)", l) end
    end)
    A.do_(function() C.af0 = AF and AF.bomb; ST.marks.m1 = ST.n; ST.press("H") end)   -- the bow railcannon
    A.log_("tanicorn rc: deployed at", 12, "m1", true, function(l)
        ST.check(l ~= nil, "the railcannon deployed (Ctrl+H)", l or ST.findLog("tanicorn rc:", ST.marks.m1, true))
    end)
    A.log_("tanicorn rc: charge 1 at", 8, "m1", true, function(l)
        ST.check(l ~= nil and l:find("RAILGUN WARNING", 1, true) ~= nil, "its first charge, the RAILGUN WARNING up", l)
    end)
    A.log_("tanicorn rc: SHOT 1 at", 45, "m1", true, function(l) ST.check(l ~= nil, "its first shot", l) end)
    A.log_("tanicorn rc: impact 1 at", 25, "m1", true, function(l)
        ST.check(l ~= nil, "its round hit the airfield", l)
        ST.check(C.af0 ~= nil and AF and AF.bomb and AF.bomb > C.af0, "the airfield took the damage (AF.bomb up)",
            tostring(C.af0) .. " -> " .. tostring(AF and AF.bomb))
    end)
    A.log_("tanicorn rc: charge 2 at", 80, "m1", true, function(l)        -- shot down mid-charge: no impact
        C.ch2 = ST.check(l ~= nil, "its second charge started", l)
    end)
    A.wait(5)
    A.do_(function()
        if not C.ch2 then return end
        local _, seen = partsSeen()
        local rc = seen.RAILCANNON
        if not ST.check(rc ~= nil and ST.same(rc), "the railcannon part still there to shoot down") then C.ch2 = false; return end
        ST.marks.m2 = ST.n
        local dead, h, how = finishUnpaid(rc.o)
        ST.check(dead == true, "the railcannon finished off mid-charge", string.format("health %s, %s", tostring(h), tostring(how)))
    end)
    A.log_("tanicorn rc: cycle over", 10, "m2", true, function(l)
        if C.ch2 then ST.check(l ~= nil, "its cycle over once it's down", l) end
    end)
    A.wait(35)
    A.do_(function()
        if C.ch2 then ST.check(ST.findLog("tanicorn rc: impact 2", ST.marks.m1, true) == nil, "no impact from the charge it was shot down in") end
        local hh1 = ST.healthOf(C.hull)
        ST.check(TANI.liveHull() ~= nil and C.hh0 ~= nil and hh1 == C.hh0, "her hull up, its health unchanged through the whole test",
            tostring(C.hh0) .. " -> " .. tostring(hh1))
    end)
end

-- INVINCIBLE FLEET's formation test (WP7, Ctrl+N): every ship up, under way, GEOFON sailing, the rings holding, taken off
SUITES.fleet = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFLEET ~= nil, "INVINCIBLE FLEET's Lua is in this build (sv_fleet)") then return "abort" end
        local rows = ST.findLog("fleet: rows at the main menu", 0, true)
        ST.check(rows ~= nil and not rows:find("MISSING", 1, true), "the fleet's rows in at the main menu", rows)
        ST.marks.m0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: Ctrl%+N: %d+ ships coming up", 5, "m0", false, function(l)
        if not ST.check(l ~= nil, "Ctrl+N: the fleet's ships queued", l or ST.findLog("fleet: Ctrl+N", ST.marks.m0, true)) then
            return "abort"
        end
    end)
    A.log_("fleet: Ctrl%+N: %d+ of %d+ ships up", 60, "m0", false, function(l)
        local up, of = nil, nil
        if l then up, of = l:match("(%d+) of (%d+) ships up") end
        ST.check(l ~= nil and up == of, "every ship of the fleet up", l)
        ST.info("waiting 70 s for the fleet to sail")
    end)
    A.wait(70)
    A.do_(function()
        local notUnder = {}
        for i = ST.marks.m0 + 1, ST.n do
            local s = ST.lines[i]
            local who = s and s:match("^fleet: %+%d+ s (.-) NOT under way")
            if who then notUnder[#notUnder + 1] = who end
        end
        ST.check(#notUnder == 0, "every ship under way", #notUnder > 0 and table.concat(notUnder, ", ") or nil)
        local geo
        for i = ST.n, ST.marks.m0 + 1, -1 do
            local s = ST.lines[i]
            if s and s:find("^fleet: %+%d+ s GEOFON: ") then geo = s; break end
        end
        local kmh = geo and tonumber(geo:match(" (%d+) km/h heading"))
        ST.check(kmh ~= nil and kmh >= 10, "GEOFON sails (its speed between two of its lines)", geo)
        local worst, n = 0, 0
        for i = ST.marks.m0 + 1, ST.n do
            local s = ST.lines[i]
            local t, m = nil, nil
            if s then t, m = s:match("^fleet: %+(%d+) s .- from GEOFON, (%d+) m off its spot") end
            if t and tonumber(t) >= 60 then n = n + 1; worst = math.max(worst, tonumber(m)) end
        end
        ST.check(n > 0 and worst <= 1000, "the formation holds a minute on (every ship within 1 km of its spot)",
            n .. " ship lines, the worst " .. worst .. " m off")
        ST.info("the fleet's weapons: " .. tostring(ST.findLog("fleet: %+%d+ s weapons", ST.marks.m0)))
        ST.marks.m1 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: Ctrl%+N at %+%d+ s: the fleet taken off", 5, "m1", false, function(l)
        ST.check(l ~= nil, "Ctrl+N again: the fleet taken off", l)
    end)
    A.wait(12)
end

-- ---- the tick ----------------------------------------------------------------------------------------------------
local started, t0, finished = false, nil, false
local function finish(why)
    if finished then return end
    finished = true
    if why then ST.check(false, why) end
    say(string.format("RESULT %d/%d (suite %s)%s", ST.pass, ST.pass + ST.fail, tostring(ST.conf.suite),
        aborted and " (stopped early: a step it needed failed)" or ""))
end
local function tick()
    if finished then return end
    local now = os.clock()
    t0 = t0 or now
    if levelGoing and levelGoing() then return end
    if D and D.now then pcall(holdPlane, now) end
    if now - t0 > ST.conf.max_s then finish(string.format("the suite timed out (%d s) at step %d of %d", ST.conf.max_s, qi, #Q)); return end
    if now >= (ST.beatAt or 0) then                       -- (a heartbeat: the job's watchdog, and where a wait is)
        ST.beatAt = now + 30
        say(string.format("+%.0f s: step %d of %d, %s (run %s, plane %s; %s)", now - t0, qi, #Q, tostring(ST.doing or "-"),
            tostring(D ~= nil), tostring(ST.plane() ~= nil), ST.who()))
    end
    if not started then
        started = true
        local fn = SUITES[ST.conf.suite]
        if not fn then finish("no suite named " .. tostring(ST.conf.suite)); return end
        local ok, err = pcall(fn)
        if not ok then finish("the suite didn't build: " .. tostring(err)); return end
        say(string.format("suite %s starts: %d steps (max %d s; Survival %s)", ST.conf.suite, #Q, ST.conf.max_s, tostring(VERSION)))
    end
    for _ = 1, 8 do if not stepOnce(now) then break end end
    if qi > #Q then finish() end
end
if MENU and type(MENU.tick) == "function" then
    local orig = MENU.tick
    MENU.tick = function(...)
        local ok, err = pcall(tick)
        if not ok then say("tick error " .. tostring(err)) end
        return orig(...)
    end
    say("installed on MENU.tick (suite " .. tostring(ST.conf.suite) .. ")")
else
    say("no MENU.tick to run on: the self-test can't run")
end
end
