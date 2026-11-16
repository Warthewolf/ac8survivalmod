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
        if ST.conf.plane == "floor" then                  -- (shootable, never down: a health floor, not invincible)
            pcall(function() pawn:SetIsInvincible(false) end)
            local mx = tonumber(pawn.MaxHealth) or 100
            pcall(function() pawn:SetMinHealth(mx * 0.4) end)
            pcall(function() pawn.MinHealth = mx * 0.4 end)
        else
            pcall(function() pawn:SetIsInvincible(true) end)
        end
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
-- ---- screenshots (the user, 2026-11-16: "Screenshots would be good") ------------------------------------------------
-- ST.look(at, look, fov): a CameraActor of ours at `at` (world cm) turned onto `look`, your view on it (sv_cine.lua's spawn and
-- SetViewTargetWithBlend); ST.shot(name): the game's own HighResShot (Saved/Screenshots, collected by job.py) and a
-- `selftest: SHOT <name>` line (job.py captures the game's window too); ST.lookBack(): your plane's view, the camera gone.
local CAM = nil
local function quatOf(yaw, pitch)                         -- (yaw about Z, then pitch about Y: a camera's turn, no roll)
    local cy, sy, cp, sp = math.cos(math.rad(yaw) / 2), math.sin(math.rad(yaw) / 2), math.cos(math.rad(pitch) / 2), math.sin(math.rad(pitch) / 2)
    return { X = sy * sp, Y = -cy * sp, Z = sy * cp, W = cy * cp }
end
function ST.look(at, look, fov)
    local gs, ccls, pc = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.CameraActor"), ST.pc()
    if not (valid(gs) and valid(ccls) and pc) then return false, "no GameplayStatics / CameraActor / player controller" end
    local dx, dy, dz = look.X - at.X, look.Y - at.Y, look.Z - at.Z
    local yaw, pitch = math.deg(math.atan(dy, dx)), math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
    local t = { Rotation = quatOf(yaw, pitch), Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, a = pcall(function() return gs:BeginDeferredActorSpawnFromClass(pc, ccls, t, 1, nil, 1) end)
    if not (okB and a and valid(a)) then return false, "the camera's spawn gave nothing" end
    pcall(function() gs:FinishSpawningActor(a, t, 1) end)
    pcall(function() a:K2_SetActorRotation({ Pitch = pitch, Yaw = yaw, Roll = 0 }, true) end)
    pcall(function() a.CameraComponent.bConstrainAspectRatio = false end)
    pcall(function() a.CameraComponent:SetFieldOfView(fov or 50) end)
    if CAM and valid(CAM) then pcall(function() CAM:K2_DestroyActor() end) end
    CAM = a
    local ok = pcall(function() pc:SetViewTargetWithBlend(a, 0, 0, 0, false) end)
    return ok, ok and "your view on the camera" or "SetViewTargetWithBlend failed"
end
function ST.lookBack()
    local pc, pawn = ST.pc(), ST.plane()
    if pc and pawn then pcall(function() pc:SetViewTargetWithBlend(pawn, 0, 0, 0, false) end) end
    if CAM and valid(CAM) then pcall(function() CAM:K2_DestroyActor() end) end
    CAM = nil
end
function ST.shot(name)
    local ks, pc = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"), ST.pc()
    local ok = valid(ks) and pc and pcall(function() ks:ExecuteConsoleCommand(pc, "HighResShot 1", pc) end)
    say("SHOT " .. name .. " (HighResShot " .. (ok and "asked" or "NOT asked") .. ")")
end
function ST.at(o) local v = o:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end
function ST.off(p, dx, dy, dz) return { X = p.X + dx, Y = p.Y + dy, Z = p.Z + dz } end
function ST.frame(o, f, r, u)                             -- a spot off o in its own frame (forward / right / up, cm)
    local p, F, R = ST.at(o), o:GetActorForwardVector(), o:GetActorRightVector()
    return { X = p.X + F.X * f + R.X * r, Y = p.Y + F.Y * f + R.Y * r, Z = p.Z + F.Z * f + R.Z * r + u }
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
-- a picture's steps: the camera at atFn() onto lookFn() (read when the step runs), a frame or two drawn, the shot, back
function A.picture(name, atFn, lookFn, fov)
    A.do_(function()
        local okA, at = pcall(atFn)
        local okL, look = pcall(lookFn)
        if not (okA and at and okL and look) then ST.info("picture " .. name .. ": its spot not read"); return end
        local ok, why = ST.look(at, look, fov)
        if not ok then ST.info("picture " .. name .. ": " .. tostring(why)) end
    end)
    A.wait(1.5)
    A.do_(function() ST.shot(name) end)
    A.wait(2.5)                                           -- (the job grabs the window within ~1 s of the line)
    A.do_(function() ST.lookBack() end)
end
-- (2026-11-16) what the rounds in flight of objects whose class matches ownerPat home on, sampled once a second for n
-- seconds (each round counted once): checks none at the runway's target points (BP_GR000_dummy) and some at you
function A.rounds(ownerPat, what, n)
    local S = { last = -1, n = 0, you = 0, dummy = 0, other = {}, seen = {}, byD = {}, byY = {} }
    A.until_(function()
        local now = os.clock()
        if now - S.last < 1 then return false end
        S.last, S.n = now, S.n + 1
        local pa
        pcall(function() pa = ST.plane():GetAddress() end)
        local ok, list = pcall(FindAllOf, "LiveExplosiveWeapon")
        for _, w in ipairs(ok and list or {}) do
            local hid, wa, own = nil, nil, ""
            pcall(function() hid = w.bHidden end)
            pcall(function() wa = w:GetAddress() end)
            pcall(function() own = w.OwningGameObject:GetFullName() end)
            if hid == false and wa and own:find(ownerPat, 1, true) then
                local tn, ta = "none", nil
                pcall(function() local t = w.TargetToHome; ta = t:GetAddress(); tn = t:GetFullName() end)
                local key = tostring(wa) .. "|" .. tostring(ta)
                if not S.seen[key] then
                    S.seen[key] = true
                    local ok2 = (own:match("(BP_[%w_]-_C)[_ ]") or own:sub(1, 30)):gsub("_C$", "")
                    local wn = (w:GetFullName():match("(BP_wp_[%w_]-)_C") or "?")
                    local k = ok2 .. " " .. wn
                    if ta and pa and ta == pa then S.you = S.you + 1; S.byY[k] = (S.byY[k] or 0) + 1
                    elseif tn:find("dummy", 1, true) then S.dummy = S.dummy + 1; S.byD[k] = (S.byD[k] or 0) + 1
                    else local t = (tn:match("([%w_]+_C)_") or tn):sub(1, 40); S.other[t] = (S.other[t] or 0) + 1 end
                end
            end
        end
        return S.n >= n
    end, n + 15, function()
        local function list(t) local o = {}; for k, v in pairs(t) do o[#o + 1] = k .. " x" .. v end
            return #o > 0 and table.concat(o, ", ") or "none" end
        local d = string.format("%d samples: %d rounds at you (%s), %d at the runway's points (%s), others: %s", S.n, S.you,
            list(S.byY), S.dummy, list(S.byD), list(S.other))
        ST.check(S.dummy == 0, "no " .. what .. " round in flight homes on the runway's target points", d)
        ST.check(S.you > 0, what .. " rounds in flight home on you", d)
    end)
end
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
        local inv, mh, mx
        pcall(function() inv = ST.plane().bIsInvincible end)
        pcall(function() mh, mx = ST.plane().MinHealth, ST.plane().MaxHealth end)
        if ST.conf.plane == "floor" then                  -- ((2026-11-16) an invincible plane drew no fire from her mounts)
            ST.check(inv ~= true and tonumber(mh) and tonumber(mh) > 0, "your plane shootable but never down (a MinHealth floor)",
                "bIsInvincible " .. tostring(inv) .. ", MinHealth " .. tostring(mh) .. " of MaxHealth " .. tostring(mx))
        else
            ST.check(inv == true, "your plane invincible (SetIsInvincible read back)", tostring(inv))
        end
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
        -- a hit on her hull through the game's own damage path, her invincibility left on (finishUnpaid takes it off first)
        local ok, err = pcall(function() C.hull:ModifyHealth(-500, nil, true) end)
        C.hitTried = ok and "ModifyHealth(-500, with its damage event)" or ("ModifyHealth refused: " .. tostring(err):sub(1, 60))
    end)
    A.wait(1)
    A.do_(function()
        local h1 = ST.healthOf(C.hull)
        ST.check(C.hh0 ~= nil and h1 == C.hh0, "a 500-point hit on her hull takes nothing (her invincibility holds)",
            tostring(C.hitTried) .. ": health " .. tostring(C.hh0) .. " -> " .. tostring(h1))
        C.hh0 = h1                                         -- (the later checks against what's there now)
    end)
    A.wait(5)                                             -- (the +2.5 s orders, the +8 s look)
    -- (2026-11-16) her guns on you: the hull's unit area was the scored dummy's 1.5 km (they shelled the runway's target
    -- points when she spawned near them, never your plane 5 km off): her first shell's target, then her barrels turning
    A.log_("weapons: first launch of %S+ by BP_SV_Tani_", 40, "m0", false, function(l)
        ST.check(l ~= nil and not l:find("dummy", 1, true), "her guns fire at you (not at the runway's target points)", l)
    end)
    A.wait(12)
    A.do_(function()
        local REST = { T16_FWD = 73, CIWS_1 = 177, LASER_FWD_L = 100 }     -- (their rest yaws in runs 12-20)
        for _, s in ipairs({ "T16_FWD", "CIWS_1", "LASER_FWD_L" }) do
            local yaws = {}
            for i = ST.marks.m0 + 1, ST.n do
                local y = ST.lines[i] and ST.lines[i]:match("live %+%d+ s: Part_" .. s .. " %(.-barrel yaw (%-?[%d%.]+)")
                if y then yaws[#yaws + 1] = y end
            end
            -- (a barrel held on you reads the same each line: off its rest angle counts; run 23: T16_FWD 154.0 twice, rest
            -- 71-75 in every run before. The CIWS and LASER are point defence: at rest with your plane ~5 km off)
            local moved = false
            for k = 1, #yaws do
                if yaws[k] ~= yaws[1] or math.abs((tonumber(yaws[k]) or REST[s]) - REST[s]) > 10 then moved = true end
            end
            local what = #yaws .. " readings: " .. table.concat(yaws, " ", math.max(1, #yaws - 5)) .. " (rest ~" .. REST[s] .. ")"
            if s == "T16_FWD" then ST.check(moved, "Part_T16_FWD's barrel turned onto you", what)
            else ST.info("Part_" .. s .. (moved and " turned: " or " at rest (point defence, out of its reach): ") .. what) end
        end
    end)
    A.rounds("BP_SV_Tani_", "her", 20)
    A.picture("tanacorn_whole", function() return ST.frame(C.hull, -30000, 90000, 22000) end,
        function() return ST.frame(C.hull, 0, 0, 3000) end, 55)
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
        end, 85, function(l)          -- (run 27: a barrel started after +33 s)
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
    A.picture("railgun_L_raised", function()
        local _, seen = partsSeen(); return ST.frame(seen.RAILGUN_L.o, 2500, -4500, 1800) end,
        function() local _, seen = partsSeen(); return ST.frame(seen.RAILGUN_L.o, 0, 0, 500) end, 45)
    A.do_(function() C.af0 = AF and AF.bomb; ST.marks.m1 = ST.n; ST.press("H") end)   -- the bow railcannon
    A.log_("tanicorn rc: deployed at", 12, "m1", true, function(l)
        ST.check(l ~= nil, "the railcannon deployed (Ctrl+H)", l or ST.findLog("tanicorn rc:", ST.marks.m1, true))
    end)
    A.log_("tanicorn rc: charge 1 at", 8, "m1", true, function(l)
        ST.check(l ~= nil and l:find("RAILGUN WARNING", 1, true) ~= nil, "its first charge, the RAILGUN WARNING up", l)
    end)
    A.picture("railcannon_charging", function()
        local _, seen = partsSeen(); return ST.frame(seen.RAILCANNON.o, 4500, 9000, 2500) end,
        function() local _, seen = partsSeen(); return ST.frame(seen.RAILCANNON.o, 4500, 0, 1500) end, 60)
    A.log_("tanicorn rc: SHOT 1 at", 45, "m1", true, function(l) ST.check(l ~= nil, "its first shot", l) end)
    A.picture("railcannon_impact", function() return { X = AIRFIELD.X - 90000, Y = AIRFIELD.Y + 60000, Z = 35000 } end,
        function() return { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = 0 } end, 50)
    A.log_("tanicorn rc: impact 1 at", 25, "m1", true, function(l)
        ST.check(l ~= nil, "its round hit the airfield", l)
        ST.check(C.af0 ~= nil and AF and AF.bomb and AF.bomb > C.af0, "the airfield took the damage (AF.bomb up)",
            tostring(C.af0) .. " -> " .. tostring(AF and AF.bomb))
    end)
    -- (2026-11-16) the Spear strike's impact (Mission 25 day 1's cutscene set) from high and far, as the user's picture
    -- frames it: ~7 km off, 3.5 km up, as the fireball grows, then its dust
    local function wideAt() return { X = 1609574 - 450000, Y = -435747 + 220000, Z = 110000 } end   -- (under the cloud deck: seq run 34)
    local function wideOn() return { X = 1609574, Y = -435747, Z = 100000 } end
    A.picture("spear_impact_wide", wideAt, wideOn, 45)
    A.picture("spear_impact_dust", wideAt, wideOn, 45)
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
-- (2026-11-16) the railcannon's impact (Mission 25 day 1's Spear strike set: TANI.rcFx "impact") at a few scales, one at a
-- time over the runway's impact point, each pictured early and late from ~4.3 km off and 1.3 km up (under the cloud deck):
-- the user's picture is the target look. conf scales=1,4,8,12 (the list)
SUITES.spear = function()
    intoRun()
    local list = {}
    for v in tostring(ST.conf.scales or "1,4,8,12"):gmatch("[%d%.]+") do list[#list + 1] = tonumber(v) end
    local P = { X = 1609574, Y = -435747, Z = 500 }
    local function at() return { X = P.X - 380000, Y = P.Y + 200000, Z = 130000 } end
    local function on() return { X = P.X, Y = P.Y, Z = P.Z + 40000 } end
    local keep
    A.do_(function()
        local rc = CFG and CFG.specials and CFG.specials.fleet and CFG.specials.fleet.railcannon
        if not ST.check(TANI ~= nil and TANI.rcFx ~= nil and rc ~= nil and rc.fx and rc.fx.impact, "the railcannon's impact set is in this build") then
            return "abort"
        end
        keep = {}
        for i, e in ipairs(rc.fx.impact) do keep[i] = e[2] end
    end)
    for _, sc in ipairs(list) do
        A.do_(function()
            local rc = CFG.specials.fleet.railcannon
            for _, e in ipairs(rc.fx.impact) do e[2] = sc end
            local ok, up, of = pcall(TANI.rcFx, "impact", nil, P)
            ST.check(ok and up == of and of == 7, string.format("the impact set at scale %s: %s of %s up", sc, tostring(up), tostring(of)))
        end)
        A.wait(2.0)
        A.picture(string.format("spear_x%s_early", sc), at, on, 55)
        A.wait(2.0)
        A.picture(string.format("spear_x%s_late", sc), at, on, 55)
        A.wait(19)                                        -- (its life, impact_life_s 25, runs out before the next)
    end
    A.do_(function()
        local rc = CFG.specials.fleet.railcannon
        for i, e in ipairs(rc.fx.impact) do e[2] = keep and keep[i] or 1 end
    end)
end
-- (2026-11-16) the user: the railcannon's impact "needs to look EXACTLY like" Mission 25 day 1's Spear strike cutscene. A
-- probe: the cutscene's own VFX layer (CLS_IGC_Ms250010_Shot0030_VFX: its spawnables with their parameters, transforms and
-- timing) played by a LevelSequencePlayer of ours; where and when its pieces come up (they stand at the cutscene's own
-- world spots); then again with its transform origin moved so its explosion lands on the runway's impact point, pictured
-- low (under the clouds) and high (as the user's picture) through the strike
SUITES.seq = function()
    intoRun()
    local SEQ = "/Game/Sequencer/IGC/IGC_Ms250010/VFX/CLS_IGC_Ms250010_Shot0030_VFX.CLS_IGC_Ms250010_Shot0030_VFX"
    local P = { X = 1609574, Y = -435747, Z = 500 }
    local S = { t0 = 0, seen = {} }
    local function fn(o) local ok, n = pcall(function() return o:GetFullName() end); return ok and n or "?" end
    local function pieces()
        local out = {}
        local ok, list = pcall(FindAllOf, "NiagaraActor")
        for _, a in ipairs(ok and list or {}) do
            local asset = "?"
            pcall(function() asset = fn(a.NiagaraComponent.Asset) end)
            if asset:find("Ms250010", 1, true) then
                local l = { X = 0, Y = 0, Z = 0 }
                pcall(function() l = ST.at(a) end)
                local sc = "?"
                pcall(function() local v = a:GetActorScale3D(); sc = string.format("%.2f", v.X) end)
                out[#out + 1] = { a = a, name = (fn(a):match("([^%.:]+)$") or "?"), asset = asset:match("NS_IGCVFX_Ms250010_[%w_]+") or asset, l = l, sc = sc }
            end
        end
        return out
    end
    local function say(tag)
        local ps = pieces()
        local parts = {}
        for _, p in ipairs(ps) do
            parts[#parts + 1] = string.format("%s=%s (%.0f, %.0f, %.0f) x%s", p.name, p.asset, p.l.X, p.l.Y, p.l.Z, p.sc)
        end
        ST.info(string.format("seq %s: %d pieces: %s", tag, #ps, table.concat(parts, "; ")))
        return ps
    end
    local function newPlayer(origin, hold)
        local seq = loadObject(SEQ)
        if not seq then return nil, "the sequence didn't load" end
        local lsp = StaticFindObject("/Script/LevelSequence.Default__LevelSequencePlayer")
        if not (lsp and lsp:IsValid()) then return nil, "no LevelSequencePlayer class" end
        local settings = { bAutoPlay = false, LoopCount = { Value = 0 }, PlayRate = 1.0, StartTime = 0.0,
            bRandomStartTime = false, bRestoreState = false, bDisableMovementInput = false, bDisableLookAtInput = false,
            bHidePlayer = false, bHideHud = false, bDisableCameraCuts = true, bPauseAtEnd = hold == true }
        local out = {}
        local ok, pl = pcall(function() return lsp:CreateLevelSequencePlayer(ST.pc(), seq, settings, out) end)
        if not (ok and pl and pl:IsValid()) then return nil, "CreateLevelSequencePlayer: " .. tostring(pl) end
        local actor
        pcall(function() actor = pl:GetOuter() end)
        local why = "origin none"
        if origin and actor then
            local okO, e = pcall(function()
                actor.bOverrideInstanceData = true
                actor.DefaultInstanceData.TransformOrigin = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
                    Translation = origin, Scale3D = { X = 1, Y = 1, Z = 1 } }
            end)
            why = okO and string.format("origin (%.0f, %.0f, %.0f) set on %s", origin.X, origin.Y, origin.Z, fn(actor):match("[^%.:]+$") or "?")
                or ("origin NOT set: " .. tostring(e))
        end
        local dur = "?"
        pcall(function() local d = pl:GetDuration(); dur = string.format("%d frames at %d/%d", d.Time.FrameNumber.Value, d.Rate.Numerator, d.Rate.Denominator) end)
        return pl, string.format("player %s, actor %s, duration %s, %s", fn(pl):match("[^%.:]+$") or "?", actor and (fn(actor):match("[^%.:]+$") or "?") or "none", dur, why)
    end
    -- (run 33) the pieces in the sequence's own space (no origin): Explosion002 x25.11 at (605172, -533159, -5879) on the
    -- ground with RingSmoke001 x35.3 at -7935, ShockWave002 / 001 x20 at +4850 / +24830, Explosion001 x35.3 at -222623,
    -- Explosion005 x1 at +30380, SandSmoke001 x1 at (919048, -601484, +144284), the rod's trail falling from (1005867,
    -- -390217, 815830), three rains on the cutscene's camera. Explosion002 is put on the impact point; the rod's trail and the
    -- rains hidden; the player held at its last frame (bPauseAtEnd) so the pieces live on, stopped at +stop_s
    local E2 = { X = 605172, Y = -533159, Z = -5879 }
    local high = function() return { X = P.X - 800000, Y = P.Y + 300000, Z = 400000 } end
    local highOn = function() return { X = P.X, Y = P.Y, Z = P.Z + 120000 } end
    local low = function() return { X = P.X - 450000, Y = P.Y + 220000, Z = 110000 } end
    local lowOn = function() return { X = P.X, Y = P.Y, Z = P.Z + 100000 } end
    local function hideExtras()
        local n = 0
        for _, p in ipairs(pieces()) do
            if p.l.X ~= 0 and (p.asset:find("Rain", 1, true) or p.asset:find("BulletTrail", 1, true)) then
                pcall(function() p.a:SetActorHiddenInGame(true) end)
                pcall(function() p.a.NiagaraComponent:Deactivate() end)
                n = n + 1
            end
        end
        return n
    end
    local function run(tag, at, on, fov, times)
        A.do_(function()
            local o = { X = P.X - E2.X, Y = P.Y - E2.Y, Z = P.Z - E2.Z }
            local pl, why = newPlayer(o, true)
            ST.info("seq " .. tag .. ": " .. tostring(why))
            if not ST.check(pl ~= nil, "the cutscene's VFX layer, Explosion002 on the impact point (" .. tag .. ")", why) then return "abort" end
            S.pl = pl
            pcall(function() pl:Play() end)
            S.t0 = os.clock()
            ST.look(at(), on(), fov)
        end)
        A.wait(0.3)
        A.do_(function() ST.info("seq " .. tag .. ": " .. hideExtras() .. " pieces hidden (the rod's trail, the rains)") end)
        local last = 0.3
        for i, t in ipairs(times) do
            A.wait(t - last); last = t
            A.do_(function()
                ST.shot(string.format("seq_%s_%02d_%02ds", tag, i, math.floor(t + 0.5)))
                if t >= 6 and not S.said6 then
                    S.said6 = true
                    local live = 0
                    for _, p in ipairs(pieces()) do if p.l.X ~= 0 then live = live + 1 end end
                    ST.check(live >= 8, "its pieces still up after its 5.5 s (held at its last frame)", live .. " up at +" .. math.floor(t) .. " s")
                end
            end)
        end
        A.do_(function()
            pcall(function() S.pl:Stop() end)
            ST.lookBack()
        end)
        A.wait(1)
        A.do_(function()
            local live = 0
            for _, p in ipairs(pieces()) do if p.l.X ~= 0 then live = live + 1 end end
            ST.check(live == 0, "its pieces gone once stopped (" .. tag .. ")", live .. " left")
            S.said6 = nil
        end)
        A.wait(2)
    end
    run("high", high, highOn, 45, { 1.5, 3, 4.5, 6, 8, 11, 15, 20 })
    run("low", low, lowOn, 55, { 1.5, 3, 5, 8, 12 })
end
-- (2026-11-16) THE TANACORN's rise (Ctrl+R, sv_tanicorn_rise.lua; WP4): her rig found and played, the breach's and the
-- slam's effects up, the hull from 130 m under the sea to its rest with the bow up ~35 deg on the way, the rise over and
-- your view back; its cinematic pictured as it plays (the window grabs: your view is its camera)
SUITES.rise = function()
    intoRun()
    A.do_(function()
        if not ST.check(TANI ~= nil and TANI.rise ~= nil, "THE TANACORN's rise is in this build (sv_tanicorn_rise)") then return "abort" end
        ST.marks.r0 = ST.n
        ST.press("R")
    end)
    A.log_("tanicorn: Ctrl%+R", 10, "r0", false, function(l)
        if not ST.check(l ~= nil and not l:find("outside", 1, true), "Ctrl+R: the hull up for its rise", l) then return "abort" end
    end)
    A.log_("tanicorn: rise: RiseRig found", 15, "r0", true, function(l)
        ST.check(l ~= nil, "her RiseRig found and scrubbed to 0", l or ST.findLog("tanicorn: rise:", ST.marks.r0, true))
    end)
    A.log_("tanicorn: rise: playing at rate", 10, "r0", true, function(l)
        ST.check(l ~= nil and not l:find("FAILED", 1, true), "her rise playing", l)
    end)
    for i, t in ipairs({ 1, 2.5, 4, 5.5, 7, 9, 10.5, 13, 16 }) do
        A.wait(i == 1 and 1 or (t - ({ 1, 2.5, 4, 5.5, 7, 9, 10.5, 13, 16 })[i - 1]))
        A.do_(function() ST.shot(string.format("rise_%02d_%04.1fs", i, t)) end)
    end
    A.log_("tanicorn: rise breach at", 5, "r0", true, function(l)
        local up, of = nil, nil
        if l then up, of = l:match("(%d+) of (%d+) effects up") end
        ST.check(up ~= nil and up == of and tonumber(of) > 0, "the breach: every effect up", l)
    end)
    A.log_("tanicorn: rise slam at", 5, "r0", true, function(l)
        ST.check(l ~= nil, "the slam: its foam and pillars", l)
    end)
    A.log_("tanicorn: rise over", 30, "r0", true, function(l)
        ST.check(l ~= nil, "the rise over, your view back", l)
        local zs, ps = {}, {}
        for i = ST.marks.r0 + 1, ST.n do
            local s = ST.lines[i] or ""
            local z = s:match("tanicorn: rise %+[%d%.]+ s: hull at z (%-?[%d%.]+) m")
            local pt = s:match("pitch (%-?[%d%.]+)")
            if z then zs[#zs + 1] = tonumber(z); if pt then ps[#ps + 1] = tonumber(pt) end end
        end
        local zmin, zmax, pmax = math.huge, -math.huge, -math.huge
        for _, z in ipairs(zs) do zmin, zmax = math.min(zmin, z), math.max(zmax, z) end
        for _, v in ipairs(ps) do pmax = math.max(pmax, v) end
        ST.check(#zs > 10 and zmin < -60 and zmax > zmin + 60, "her hull rose from under the sea",
            string.format("%d readings, z %s .. %s m", #zs, tostring(zmin), tostring(zmax)))
        ST.check(#ps > 10 and pmax > 20, "her bow up on the way (the pitch)", string.format("pitch at most %s deg", tostring(pmax)))
    end)
    A.log_("tanicorn: rise effects:", 20, "r0", true, function(l)
        ST.info("rise effects: " .. tostring(l))
    end)
end
-- (2026-11-16) THE TANACORN's rise with her guns live (round 30's phase 3: Ctrl+L, then Ctrl+R rises the hull already up):
-- her 35 parts ride her rig through the rise (each on its socket after), her armour holds, then her rounds come at you
SUITES.riselive = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(TANI ~= nil and TANI.rise ~= nil and TANI.live ~= nil, "THE TANACORN's live hull and rise in this build") then return "abort" end
        ST.marks.m0 = ST.n
        ST.press("L")
    end)
    A.until_(function() return partsSeen() >= #TANI.live.parts end, 20, function()
        local n = partsSeen()
        C.want = #TANI.live.parts
        ST.check(n >= C.want, string.format("her live hull up with its %d parts", C.want), n .. " seen")
    end)
    A.wait(3)
    A.do_(function()
        ST.marks.r0 = ST.n
        ST.press("R")
    end)
    A.log_("tanicorn: Ctrl%+R", 10, "r0", false, function(l)
        ST.check(l ~= nil and l:find("already up", 1, true) ~= nil, "Ctrl+R: the live hull already up rises where it is", l)
    end)
    A.log_("tanicorn: rise: RiseRig found", 15, "r0", true, function(l)
        ST.check(l ~= nil, "her RiseRig found on the live hull", l or ST.findLog("tanicorn: rise:", ST.marks.r0, true))
    end)
    for i, t in ipairs({ 1, 3, 5, 7, 9.5, 12 }) do
        A.wait(i == 1 and 1 or (t - ({ 1, 3, 5, 7, 9.5, 12 })[i - 1]))
        A.do_(function() ST.shot(string.format("riselive_%02d_%04.1fs", i, t)) end)
    end
    A.log_("tanicorn: rise over", 30, "r0", true, function(l)
        ST.check(l ~= nil, "the rise over, your view back", l)
        local zs = {}
        for i = ST.marks.r0 + 1, ST.n do
            local z = (ST.lines[i] or ""):match("tanicorn: rise %+[%d%.]+ s: hull at z (%-?[%d%.]+) m")
            if z then zs[#zs + 1] = tonumber(z) end
        end
        local zmin, zmax = math.huge, -math.huge
        for _, z in ipairs(zs) do zmin, zmax = math.min(zmin, z), math.max(zmax, z) end
        ST.check(#zs > 10 and zmax > zmin + 60, "her live hull rose from under the sea", string.format("%d readings, z %s .. %s m", #zs, tostring(zmin), tostring(zmax)))
        ST.marks.after = ST.n
    end)
    A.wait(8)                                             -- (two of the live watch's 5 s lines after the rise)
    A.do_(function()
        local _, seen = partsSeen()
        local alive = 0
        for _ in pairs(seen) do alive = alive + 1 end
        ST.check(alive >= C.want, "all her parts still there after the rise", alive .. " of " .. tostring(C.want))
        local far = {}
        local n = 0
        for i = (ST.marks.after or 0) + 1, ST.n do
            local s = ST.lines[i] or ""
            local part, d = s:match("live %+%d+ s: (Part_[%w_]+) %(.-; (%-?[%d%.]+) m from its socket")
            if part then n = n + 1; if tonumber(d) > 5 then far[#far + 1] = part .. " " .. d .. " m" end end
        end
        ST.check(n > 0 and #far == 0, "each part on its socket after the rise (the live watch)", n .. " readings" .. (#far > 0 and (", off: " .. table.concat(far, ", ")) or ""))
        local h = TANI.liveHull and TANI.liveHull()
        local cbd, inv
        pcall(function() cbd = h.bCanBeDamaged end)
        pcall(function() inv = h.bIsInvincible end)
        ST.check(cbd == false and inv == true, "her hull's armour after the rise", "bCanBeDamaged " .. tostring(cbd) .. ", bIsInvincible " .. tostring(inv))
    end)
    A.rounds("BP_SV_Tani_", "her (after the rise)", 15)
end
-- (2026-11-16) INVINCIBLE FLEET's night and storm (sv_fleet.lua IFSKY, CFG.specials.fleet.sky): the arc stepped through its
-- rounds (IFSKY.step: 25's sinking sun .. 35's clearing), the storm on from the night's first moon and off at 35, its
-- lightning counted; each step pictured from 1.2 km over the airfield towards the fleet's north-west and away; at the
-- pre-dawn (round 30) the fleet brought up (Ctrl+N) and GEOFON pictured in the storm
SUITES.fleetnight = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSKY.step ~= nil and SKY ~= nil and SKY.arcState ~= nil, "INVINCIBLE FLEET's night is in this build") then
            return "abort"
        end
        ST.marks.n0 = ST.n
    end)
    local R = { X = 1609574, Y = -435747, Z = 500 }
    local eye = function() return { X = R.X, Y = R.Y, Z = 120000 } end
    local nw = function() return { X = R.X - 1000000, Y = R.Y - 1000000, Z = 60000 } end
    local se = function() return { X = R.X + 1000000, Y = R.Y + 1000000, Z = 60000 } end
    local function geofonObj()
        for _, sh in ipairs(IFLEET and IFLEET.cur and IFLEET.cur.ships or {}) do
            if (sh.name == "GEOFON" or sh.key == "GEOFON") and sh.hull and sh.hull.obj and valid(sh.hull.obj) then return sh.hull.obj end
        end
        return nil
    end
    local STEPS = { { 0, "round 25: the sun starts down", false }, { 1, "round 26: sunset", false },
                    { 2, "round 27: night, the storm in", true }, { 4, "round 29: night", true },
                    { 5, "round 30: pre-dawn, the fleet", true }, { 6, "round 31: sunrise", true },
                    { 8, "round 33: morning", true }, { 10, "round 35: the storm cleared", false } }
    for _, stp in ipairs(STEPS) do
        local k, what, stormy = stp[1], stp[2], stp[3]
        A.do_(function() IFSKY.step(k) end)
        A.wait(9)                                         -- (the arc's blend_s 5, the storm's fade 2.6)
        A.do_(function()
            local a, w = SKY.arcState(), IFSKY.storm()
            ST.check(a.on and a.profile == "fleet" and a.k == k and (w.on == stormy),
                string.format("%s: the fleet's arc at step %s, the %s, the storm %s", what, tostring(a.k), tostring(a.mode), w.on and "on" or "off"),
                string.format("profile %s, step %s, mode %s, storm %s (%d flashes so far)", tostring(a.profile), tostring(a.k), tostring(a.mode),
                    tostring(w.on), w.flashes or 0))
        end)
        if k == 5 then                                    -- (the fleet at the pre-dawn)
            A.do_(function() ST.marks.f0 = ST.n; ST.press("N") end)
            A.log_("fleet: Ctrl%+N: %d+ of %d+ ships up", 60, "f0", false, function(l)
                ST.check(l ~= nil, "the fleet up in the pre-dawn storm", l)
            end)
            A.wait(5)
            A.picture("fleetnight_geofon", function() return ST.frame(geofonObj(), -60000, 40000, 15000) end,
                function() return ST.at(geofonObj()) end, 55)
        end
        A.do_(function() ST.look(eye(), nw(), 70) end)
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("night_k%02d_nw", k)) end)
        A.wait(0.9)
        A.do_(function() ST.shot(string.format("night_k%02d_nw2", k)) end)
        A.do_(function() ST.look(eye(), se(), 70) end)
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("night_k%02d_se", k)) end)
        A.do_(function() ST.lookBack() end)
    end
    A.do_(function()
        local w = IFSKY.storm()
        ST.check((w.flashes or 0) > 60, "a lot of lightning through the storm", (w.flashes or 0) .. " flashes")
        ST.check(ST.findLog("fleet storm: in", ST.marks.n0, true) ~= nil and ST.findLog("fleet storm: cleared", ST.marks.n0, true) ~= nil,
            "the storm swapped in and cleared, each under a fade to black",
            tostring(ST.findLog("fleet storm: in", ST.marks.n0, true)) .. " / " .. tostring(ST.findLog("fleet storm: cleared", ST.marks.n0, true)))
        IFSKY.step(nil)
    end)
end
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
    -- (2026-11-16, 0.74.77) the ships' parts ordered PlayerOnlyNoLimit: what their rounds in flight home on, sampled after
    -- the orders (a gun's FIRST launch comes 1-2 s after its ship's spawn, before its +2.5 s order: run 24's three at the
    -- runway's points were those; run 21 (0.74.76): every gun's at BP_GR000_dummy_CP)
    A.rounds("BP_VE0", "ship", 25)
    -- (a ship's .hull is sv_fleet's entry { obj, addr, ... }: the actor is its .obj; GEOFON by name, not by order)
    local function geofon()
        for _, sh in ipairs(IFLEET.cur and IFLEET.cur.ships or {}) do
            if (sh.name == "GEOFON" or sh.key == "GEOFON") and sh.hull and valid(sh.hull.obj) then return sh.hull.obj end
        end
        local sh = IFLEET.cur and IFLEET.cur.ships[1]
        return sh and sh.hull and sh.hull.obj
    end
    A.picture("fleet_formation", function() return ST.frame(geofon(), -140000, -70000, 50000) end,
        function() return ST.at(geofon()) end, 55)
    A.picture("geofon_close", function() return ST.frame(geofon(), -45000, 30000, 12000) end,
        function() return ST.at(geofon()) end, 50)
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
