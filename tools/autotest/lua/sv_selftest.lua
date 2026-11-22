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
local HOLD = { inv = 0, ap = 0, apOn = nil, ground = false, unpaused = 0, hidAt = -100 }
-- ((2026-11-22) the pause of the valka runs was AC8's "Your controller has been disconnected" box (a gamepad on this PC
-- dropping): unpaused, the box stayed over every picture after. Its TextBlock found by its text, the widgets above it
-- climbed to the one in the viewport, and that one hidden (Collapsed))
local function hideDisconnect(now)
    if now - HOLD.hidAt < 2 then return end
    HOLD.hidAt = now
    local uw = StaticFindObject("/Script/UMG.UserWidget")
    local n = 0
    for _, t in ipairs(FindAllOf("TextBlock") or {}) do
        local txt = ""
        pcall(function() txt = t:GetText():ToString() end)
        if txt:lower():find("controller has been disconnected", 1, true) then
            local o, top = t, nil
            for _ = 1, 12 do
                local okO, up = pcall(function() return o:GetOuter() end)
                if not (okO and up and valid(up)) then break end
                o = up
                local isW = false
                pcall(function() isW = o:IsA(uw) end)
                if isW then
                    local inVp = false
                    pcall(function() inVp = o:IsInViewport() end)
                    if inVp then top = o; break end
                end
            end
            if top and pcall(function() top:SetVisibility(1) end) then n = n + 1 end
        end
    end
    if n > 0 then ST.info("the controller-disconnected box hidden (" .. n .. ")") end
end
local function holdPlane(now)
    local pawn = ST.plane()
    if not pawn then return end
    -- ((2026-11-22) the valka run of 13:12 paused at 13:20:42 ("hud: hidden (paused)": the game's window lost its focus,
    -- a desktop notification likely) and its world stood still to the end: the game unpaused, each time logged)
    if gamePaused and gamePaused(ST.pc()) then
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if valid(gs) and pcall(function() gs:SetGamePaused(ST.pc(), false) end) then
            HOLD.unpaused = HOLD.unpaused + 1
            if HOLD.unpaused <= 5 or HOLD.unpaused % 20 == 0 then
                ST.info("the game had paused (its window's focus lost?): unpaused (" .. HOLD.unpaused .. ")")
            end
        end
        HOLD.boxUntil = now + 10                          -- (the box comes with the pause: looked for a while)
    end
    if HOLD.boxUntil and now < HOLD.boxUntil then pcall(hideDisconnect, now) end
    if ST.apOff then return end                           -- ((0.74.166) a suite that flies your plane itself: capture, pin)
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
    if VCINE and VCINE.active and VCINE.active() then return end   -- ((2026-11-22) her cutscene flies your plane meanwhile)
    local a = addrOf(pawn)
    -- ((2026-11-22) ST.apCentre { X, Y } (cm), the valka suite's: the circle's centre elsewhere, so your plane flies a
    -- leg there; nil: round the airfield)
    local cx, cy = AIRFIELD.X, AIRFIELD.Y
    if ST.apCentre then cx, cy = ST.apCentre.X, ST.apCentre.Y end
    local key = string.format("%.0f,%.0f", cx, cy)
    if a and type(SV_Down) == "function" and (a ~= HOLD.apOn or now >= HOLD.ap or key ~= HOLD.apKey) then
        HOLD.ap = now + 30
        if playerOnAirfield and playerOnAirfield() then
            if not HOLD.ground then HOLD.ground = true; ST.info("your plane is on the airfield: the autopilot waits") end
            return
        end
        local okD, r = pcall(SV_Down, a, cx, cy, 2500, 5000)
        if playerLocationDirty then playerLocationDirty() end
        if a ~= HOLD.apOn or key ~= HOLD.apKey then
            ST.info(string.format("the autopilot round %s: %s", ST.apCentre and string.format("(%.1f, %.1f) km", cx / 100000,
                cy / 100000) or "the airfield", okD and tostring(r) or ("error " .. tostring(r))))
        end
        HOLD.apKey = key
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
    -- ((2026-11-22) the valka runs' pictures were all level, whatever the pitch asked: the camera component's own world
    -- rotation set too, and what the camera manager shows read back at the shot, ST.shot)
    pcall(function() a.CameraComponent:K2_SetWorldRotation({ Pitch = pitch, Yaw = yaw, Roll = 0 }, false, {}, true) end)
    ST.camWant = { pitch = pitch, yaw = yaw }
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
    local view = ""
    pcall(function()
        local r = pc.PlayerCameraManager:GetCameraRotation()
        view = string.format("; view pitch %.0f yaw %.0f", r.Pitch, r.Yaw)
        if CAM and ST.camWant then view = view .. string.format(" (asked %.0f / %.0f)", ST.camWant.pitch, ST.camWant.yaw) end
    end)
    say("SHOT " .. name .. " (HighResShot " .. (ok and "asked" or "NOT asked") .. view .. ")")
end
function ST.at(o) local v = o:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end
function ST.off(p, dx, dy, dz) return { X = p.X + dx, Y = p.Y + dy, Z = p.Z + dz } end
function ST.frame(o, f, r, u)                             -- a spot off o in its own frame (forward / right / up, cm)
    local p, F, R = ST.at(o), o:GetActorForwardVector(), o:GetActorRightVector()
    return { X = p.X + F.X * f + R.X * r, Y = p.Y + F.Y * f + R.Y * r, Z = p.Z + F.Z * f + R.Z * r + u }
end
-- (2026-11-16) what draws near your plane: every Niagara / Cascade effect and every static mesh within r_m of it, nearest
-- first, with its asset, its owner and (for a mesh) its first material (round30 run 45: a checkered sheet by the plane)
function ST.near(r_m, tag)
    local pl = ST.plane()
    if not (pl and valid(pl)) then ST.info("near " .. tag .. ": no plane"); return end
    local P = ST.at(pl)
    local r2 = (r_m * 100) ^ 2
    local function short(o) local n = "?"; pcall(function() n = o:GetFullName() end); return (n:match("([^%./ ]+)$") or n) end
    for _, k in ipairs({ "NiagaraComponent", "ParticleSystemComponent", "StaticMeshComponent", "InstancedStaticMeshComponent" }) do
        local L = {}
        local all = FindAllOf(k) or {}
        for _, c in ipairs(all) do
            local okL, v = pcall(function() return c:K2_GetComponentLocation() end)
            if okL and v then
                local d2 = (v.X - P.X) ^ 2 + (v.Y - P.Y) ^ 2 + (v.Z - P.Z) ^ 2
                if d2 < r2 then
                    local vis = true
                    pcall(function() vis = c:IsVisible() end)
                    local what, own = "?", "?"
                    pcall(function() own = short(c:GetOwner()) end)
                    if k == "NiagaraComponent" then pcall(function() what = short(c:GetAsset()) .. (c:IsActive() and "" or " (off)") end)
                    elseif k == "ParticleSystemComponent" then pcall(function() what = short(c.Template) end)
                    else pcall(function() what = short(c.StaticMesh) .. " / " .. short(c:GetMaterial(0)) end) end
                    if vis then L[#L + 1] = { d = math.sqrt(d2) / 100, s = string.format("%s on %s %.0f m", what, own, math.sqrt(d2) / 100) } end
                end
            end
        end
        table.sort(L, function(a, b) return a.d < b.d end)
        local out = {}
        for i = 1, math.min(#L, 14) do out[i] = L[i].s end
        ST.info(string.format("near %s: %s within %d m of your plane (%d of %d): %s", tag, k, r_m, #L, #all, table.concat(out, "; ")))
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

-- ((0.74.161) GEOFON's capture, WP14 4's first test: your plane pinned to a point moving at 45 km/h for 30 s by a per-frame
-- teleport (SV_Pin): does the flight model or the camera fight it? the drift between moves (log), pictures of the view
SUITES.pin = function()
    intoRun()
    A.wait(8)
    local P = {}
    A.do_(function()
        local pl = ST.plane()
        if not ST.check(pl ~= nil and type(SV_Pin) == "function" and type(SV_PinInfo) == "function", "your plane and SV_Pin / SV_PinInfo (runtime 0.32.38)") then return end
        local l, r = pl:K2_GetActorLocation(), pl:K2_GetActorRotation()
        local yaw = math.rad(r.Yaw)
        local v = 1250                                    -- (cm/s: 45 km/h)
        if type(SV_Down) == "function" then pcall(SV_Down, 0) end   -- (intoRun's autopilot round the airfield off first)
        local rc = SV_Pin(addrOf(pl) or 0, l.X, l.Y, l.Z, math.cos(yaw) * v, math.sin(yaw) * v, r.Yaw, 30)   -- (the runtime takes its address)
        P.on = rc == 1
        ST.check(rc == 1, "SV_Pin on your plane", tostring(rc))
    end)
    A.wait(2)
    A.do_(function()
        local i = type(SV_PinInfo) == "function" and SV_PinInfo() or ""
        ST.check(i:sub(1, 1) == "1", "pinned 2 s on (SV_PinInfo: on,moves,refused,mean,worst,read)", i)
    end)
    A.wait(1); A.do_(function() ST.shot("pin_3s") end)
    A.wait(10); A.do_(function() ST.shot("pin_13s") end)
    A.wait(10); A.do_(function() ST.shot("pin_23s") end)
    A.wait(9)
    A.do_(function()
        local i = type(SV_PinInfo) == "function" and SV_PinInfo() or ""
        local on, moves, fails, mean, worst = i:match("^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)")
        ST.info("pin: " .. i)
        ST.check(on == "0" and tonumber(moves or "0") > 100, "over after 30 s, moved every input build", i)
        ST.check(fails == "0", "every move taken", i)
        ST.check(tonumber(mean or "1e9") < 200, "the drift between moves small (mean under 2 m): the flight model doesn't fight it",
            tostring(mean) .. " / worst " .. tostring(worst))
    end)
    A.wait(3)
    A.do_(function() ST.check(ST.plane() ~= nil and D ~= nil, "still flying after it") end)
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
    local eye = function() return { X = R.X, Y = R.Y, Z = 40000 } end      -- (under the storm's cloud base: run 38 at 1.2 km was inside it)
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
            ST.check(a.on and a.profile == "fleet" and (a.kRaw or a.k) == k and (w.on == stormy),
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
        A.do_(function()                                  -- (a bolt 7 km ahead in view, then the game's own shot of it)
            if stormy and THUNDER and THUNDER.cloudFlash then
                local e, l = eye(), nw()
                local dx, dy = l.X - e.X, l.Y - e.Y
                local d = math.sqrt(dx * dx + dy * dy)
                local cls = ((((CFG.specials.fleet or {}).sky or {}).storm or {}).lightning or {}).class
                pcall(THUNDER.cloudFlash, { X = e.X + dx / d * 700000, Y = e.Y + dy / d * 700000, Z = 250000 }, cls or "bolt", "the test's, in view")
            end
            ST.shot(string.format("night_k%02d_nw2_bolt", k))
        end)
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
-- (2026-11-16) the user: "when the Invincible Fleet first spawns, they should all Surface out of the sea the same way the
-- Tanacorn does". A probe: can a stock ship ride THE TANACORN's rise rig? A bare SkeletalMeshActor with her rig (SK_SV_Tani_RIG,
-- AS_SV_Tani_RIG_Rise) at GEOFON's spot and heading, scaled to her length; GEOFON's live hull attached to its SOC_Hull; the
-- rise scrubbed to 0 and played; her height logged every 0.5 s, pictured from beside; detached at the end
SUITES.surface = function()
    intoRun()
    local P = {}
    local RIG = "/Game/Mods/SurvivalMode/Tanicorn/Model/SK_SV_Tani_RIG.SK_SV_Tani_RIG"
    local ANIM = "/Game/Mods/SurvivalMode/Tanicorn/Model/AS_SV_Tani_RIG_Rise.AS_SV_Tani_RIG_Rise"
    local function geofon()
        for _, sh in ipairs(IFLEET and IFLEET.cur and IFLEET.cur.ships or {}) do
            if (sh.name == "GEOFON" or sh.key == "GEOFON") and sh.hull and sh.hull.obj and valid(sh.hull.obj) then return sh.hull.obj end
        end
        return nil
    end
    A.do_(function() ST.marks.f0 = ST.n; ST.press("N") end)
    A.log_("fleet: Ctrl%+N: %d+ of %d+ ships up", 60, "f0", false, function(l)
        if not ST.check(l ~= nil, "the fleet up", l) then return "abort" end
    end)
    A.wait(3)
    A.do_(function()
        local g = geofon()
        if not ST.check(g ~= nil, "GEOFON's hull found") then return "abort" end
        P.g = g
        local okL, l = pcall(function() return g:K2_GetActorLocation() end)
        local okR, r = pcall(function() return g:K2_GetActorRotation() end)
        if not (okL and okR) then ST.check(false, "GEOFON's place read"); return "abort" end
        P.at, P.yaw = { X = l.X, Y = l.Y, Z = l.Z }, r.Yaw
        local rig, anim = loadObject(RIG), loadObject(ANIM)
        if not ST.check(rig ~= nil and anim ~= nil, "her rig and its rise loaded (the Tanicorn container)", tostring(rig) .. " / " .. tostring(anim)) then return "abort" end
        local gs, cls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.SkeletalMeshActor")
        local sc = 0.5
        local q = quatOf(P.yaw, 0)
        local t = { Rotation = q, Translation = { X = P.at.X, Y = P.at.Y, Z = 0 }, Scale3D = { X = sc, Y = sc, Z = sc } }
        local okB, a = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
        if not ST.check(okB and a ~= nil and valid(a), "a SkeletalMeshActor for the rig spawned", tostring(a)) then return "abort" end
        local m = a.SkeletalMeshComponent
        local steps = {}
        local function try(name, f) local ok, e = pcall(f); steps[#steps + 1] = name .. (ok and "" or (" FAILED " .. tostring(e):sub(1, 60))) end
        try("SetSkeletalMeshAsset", function() m:SetSkeletalMeshAsset(rig) end)
        try("tick option", function() m.VisibilityBasedAnimTickOption = 0 end)
        try("no update-rate optimisations", function() m.bEnableUpdateRateOptimizations = false end)
        try("FinishSpawning", function() gs:FinishSpawningActor(a, t, 1) end)
        try("SetAnimationMode", function() m:SetAnimationMode(1, true) end)
        try("SetAnimation", function() m:SetAnimation(anim) end)
        try("SetPosition 0", function() m:SetPosition(0, false) end)
        P.rig, P.m = a, m
        local okS, s0 = pcall(function() return m:GetSocketLocation(FName("SOC_Hull")) end)
        ST.info("surface: the rig: " .. table.concat(steps, ", ") .. string.format("; SOC_Hull at z %s m", okS and string.format("%.1f", s0.Z / 100) or "?"))
        local okA, e = pcall(function() g:K2_AttachToComponent(m, FName("SOC_Hull"), 2, 2, 1, true) end)
        ST.check(okA, "GEOFON attached to the rig's SOC_Hull", tostring(e))
        local okZ, z = pcall(function() return g:K2_GetActorLocation().Z end)
        ST.info(string.format("surface: GEOFON at z %s m once attached (was %.1f m)", okZ and string.format("%.1f", z / 100) or "?", P.at.Z / 100))
        P.zs = {}
    end)
    A.do_(function()
        local beside = function() return ST.frame(P.g, -20000, 90000, 3000) end
        ST.look(beside(), { X = P.at.X, Y = P.at.Y, Z = 6000 }, 55)
        local ok, e = pcall(function() P.m:Play(false) end)
        ST.info("surface: the rise playing: " .. tostring(ok and "yes" or e))
        P.t0 = os.clock()
    end)
    for i = 1, 32 do
        A.wait(0.5)
        A.do_(function()
            local function f1(v) return type(v) == "number" and string.format("%.1f", v) or "?" end
            local okZ, z = pcall(function() return P.g:K2_GetActorLocation().Z end)
            local okP, pr = pcall(function() return P.g:K2_GetActorRotation().Pitch end)
            local okS, sz = pcall(function() return P.m:GetSocketLocation(FName("SOC_Hull")).Z end)
            if okZ and type(z) == "number" then P.zs[#P.zs + 1] = z / 100 end
            if i % 4 == 0 then
                ST.info(string.format("surface: +%s s GEOFON at z %s m, pitch %s; the rig's SOC_Hull at z %s m", f1(os.clock() - (P.t0 or os.clock())),
                    f1(okZ and type(z) == "number" and z / 100 or nil), f1(okP and pr or nil), f1(okS and type(sz) == "number" and sz / 100 or nil)))
            end
            if i % 3 == 0 then ST.shot(string.format("surface_%02d", i)) end
        end)
    end
    A.do_(function()
        local zmin, zmax = math.huge, -math.huge
        for _, z in ipairs(P.zs) do zmin, zmax = math.min(zmin, z), math.max(zmax, z) end
        ST.check(#P.zs > 20 and zmax - zmin > 20, "GEOFON rode the rig (her height moved)", string.format("%d readings, z %.1f .. %.1f m", #P.zs, zmin, zmax))
        ST.lookBack()
        pcall(function() P.g:K2_DetachFromActor(1, 1, 1) end)
        pcall(function() P.rig:K2_DestroyActor() end)
        local okZ, z = pcall(function() return P.g:K2_GetActorLocation().Z end)
        ST.info(string.format("surface: GEOFON detached at z %s m", okZ and string.format("%.1f", z / 100) or "?"))
    end)
    A.wait(4)
    A.do_(function()
        local okZ, z = pcall(function() return P.g:K2_GetActorLocation().Z end)
        ST.info(string.format("surface: 4 s after: GEOFON at z %s m (back on the water?)", okZ and string.format("%.1f", z / 100) or "?"))
    end)
end
-- (2026-11-16) the surfacing, probe 2 (run 40: GEOFON's live hull attached to the rig never left the water: its own movement
-- holds it): drawn doubles on the rig, the live ship and its parts hidden meanwhile. (A) a bare spawn of her own blueprint
-- class (no unit, no AI orders), (B) a StaticMeshActor with her hull's mesh. Each rides a rise; its height logged, pictured
SUITES.surface2 = function()
    intoRun()
    local P = {}
    local RIG = "/Game/Mods/SurvivalMode/Tanicorn/Model/SK_SV_Tani_RIG.SK_SV_Tani_RIG"
    local ANIM = "/Game/Mods/SurvivalMode/Tanicorn/Model/AS_SV_Tani_RIG_Rise.AS_SV_Tani_RIG_Rise"
    local function f1(v) return type(v) == "number" and string.format("%.1f", v) or "?" end
    local function zOf(o) local ok, z = pcall(function() return o:K2_GetActorLocation().Z end); return ok and type(z) == "number" and z / 100 or nil end
    local function ship()
        for _, sh in ipairs(IFLEET and IFLEET.cur and IFLEET.cur.ships or {}) do
            if (sh.name == "GEOFON" or sh.key == "GEOFON") and sh.hull and sh.hull.obj and valid(sh.hull.obj) then return sh end
        end
        return nil
    end
    local function hideLive(h)
        local sh = P.sh
        local n = 0
        for _, e in ipairs({ sh.hull, table.unpack(sh.parts or {}) }) do
            if e and e.obj and valid(e.obj) then pcall(function() e.obj:SetActorHiddenInGame(h) end); n = n + 1 end
        end
        return n
    end
    local function newRig()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local cls = StaticFindObject("/Script/Engine.SkeletalMeshActor")
        local rig, anim = loadObject(RIG), loadObject(ANIM)
        local t = { Rotation = quatOf(P.yaw, 0), Translation = { X = P.at.X, Y = P.at.Y, Z = 0 }, Scale3D = { X = 0.5, Y = 0.5, Z = 0.5 } }
        local a = gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1)
        local m = a.SkeletalMeshComponent
        pcall(function() m:SetSkeletalMeshAsset(rig) end)
        pcall(function() m.VisibilityBasedAnimTickOption = 0 end)
        pcall(function() m.bEnableUpdateRateOptimizations = false end)
        gs:FinishSpawningActor(a, t, 1)
        pcall(function() m:SetAnimationMode(1, true) end)
        pcall(function() m:SetAnimation(anim) end)
        pcall(function() m:SetPosition(0, false) end)
        return a, m
    end
    local function ride(tag, makeDouble)
        A.do_(function()
            local okR, a, m = pcall(newRig)
            if not ST.check(okR and a ~= nil, tag .. ": a rig spawned", tostring(a)) then return end
            P.rig, P.m = a, m
            local okD, d, why = pcall(makeDouble)
            if not ST.check(okD and d ~= nil and valid(d), tag .. ": its double spawned", tostring(okD and why or d)) then return end
            P.d = d
            local okA, e = pcall(function() d:K2_AttachToComponent(m, FName("SOC_Hull"), 2, 2, 1, true) end)
            ST.check(okA, tag .. ": its double on the rig's SOC_Hull", tostring(e))
            ST.info(string.format("%s: the live GEOFON and %d of its objects hidden", tag, hideLive(true)))
            P.zs = {}
            ST.look(ST.frame(P.sh.hull.obj, -20000, 90000, 3000), { X = P.at.X, Y = P.at.Y, Z = 6000 }, 55)
            pcall(function() m:Play(false) end)
            P.t0 = os.clock()
        end)
        for i = 1, 30 do
            A.wait(0.5)
            A.do_(function()
                if not P.d then return end
                local z = zOf(P.d)
                if z then P.zs[#P.zs + 1] = z end
                local okS, sz = pcall(function() return P.m:GetSocketLocation(FName("SOC_Hull")).Z end)
                if i % 4 == 0 then ST.info(string.format("%s: +%s s the double at z %s m; the rig's SOC_Hull at z %s m", tag, f1(os.clock() - P.t0), f1(z), f1(okS and sz / 100 or nil))) end
                if i % 3 == 0 then ST.shot(string.format("%s_%02d", tag, i)) end
            end)
        end
        A.do_(function()
            local zmin, zmax = math.huge, -math.huge
            for _, z in ipairs(P.zs or {}) do zmin, zmax = math.min(zmin, z), math.max(zmax, z) end
            ST.check(#(P.zs or {}) > 20 and zmax - zmin > 15, tag .. ": the double rode the rig (its height moved)", string.format("%d readings, z %s .. %s m", #(P.zs or {}), f1(zmin), f1(zmax)))
            ST.lookBack()
            if P.d then pcall(function() P.d:K2_DestroyActor() end) end
            if P.rig then pcall(function() P.rig:K2_DestroyActor() end) end
            hideLive(false)
            P.d, P.rig = nil, nil
        end)
        A.wait(2)
    end
    A.do_(function() ST.marks.f0 = ST.n; ST.press("N") end)
    A.log_("fleet: Ctrl%+N: %d+ of %d+ ships up", 60, "f0", false, function(l)
        if not ST.check(l ~= nil, "the fleet up", l) then return "abort" end
    end)
    A.wait(3)
    A.do_(function()
        P.sh = ship()
        if not ST.check(P.sh ~= nil, "GEOFON found") then return "abort" end
        local g = P.sh.hull.obj
        local l, r = g:K2_GetActorLocation(), g:K2_GetActorRotation()
        P.at, P.yaw = { X = l.X, Y = l.Y, Z = l.Z }, r.Yaw or 0
        local okC, c = pcall(function() return g:GetClass() end)
        P.cls = okC and c or nil
        local meshes = {}
        for _, c2 in ipairs(SPC and SPC.V and SPC.V.comps and SPC.V.comps(g, "/Script/Engine.StaticMeshComponent") or {}) do
            local okM, sm = pcall(function() return c2.StaticMesh end)
            if okM and sm and valid(sm) then meshes[#meshes + 1] = sm end
        end
        P.mesh = meshes[1]
        ST.info(string.format("surface2: GEOFON's class %s, %d static meshes (the first %s)", P.cls and P.cls:GetFullName() or "?", #meshes,
            P.mesh and P.mesh:GetFullName() or "none"))
    end)
    ride("double_A", function()                          -- (A) her own class, bare
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local t = { Rotation = quatOf(P.yaw, 0), Translation = { X = P.at.X, Y = P.at.Y, Z = -20000 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local d = gs:BeginDeferredActorSpawnFromClass(ST.pc(), P.cls, t, 1, nil, 1)
        gs:FinishSpawningActor(d, t, 1)
        return d, "her class, bare"
    end)
    ride("double_B", function()                          -- (B) a StaticMeshActor with her hull's mesh
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local cls = StaticFindObject("/Script/Engine.StaticMeshActor")
        local t = { Rotation = quatOf(P.yaw, 0), Translation = { X = P.at.X, Y = P.at.Y, Z = -20000 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local d = gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1)
        local c = d.StaticMeshComponent
        pcall(function() c:SetMobility(2) end)
        gs:FinishSpawningActor(d, t, 1)
        pcall(function() c:SetMobility(2) end)
        pcall(function() c:SetStaticMesh(P.mesh) end)
        return d, "a StaticMeshActor"
    end)
end
-- (2026-11-16) INVINCIBLE FLEET surfacing (IFSURF, CFG.specials.fleet.surface): Ctrl+N's doubles rise on her rig in waves,
-- the cinematic's cuts pictured as it plays (your view is its camera), then the fade, the real fleet up on its spots, your
-- view back
SUITES.surfacing = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFSURF ~= nil and IFSURF.start ~= nil, "INVINCIBLE FLEET's surfacing is in this build") then return "abort" end
        ST.marks.s0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet surfacing: %d+ ships rise over", 10, "s0", false, function(l)
        if not ST.check(l ~= nil, "the surfacing started", l or ST.findLog("fleet surfacing:", ST.marks.s0, true)) then return "abort" end
    end)
    for i = 1, 18 do
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("surfacing_%02d", i)) end)
    end
    A.log_("fleet surfacing: the rise over", 20, "s0", true, function(l)
        local up, of = nil, nil
        if l then up, of = l:match("(%d+) of (%d+) doubles up") end
        ST.check(up ~= nil and up == of and tonumber(of) >= 15, "every ship's double rose", l)
    end)
    A.log_("fleet surfacing: over", 10, "s0", true, function(l)
        ST.check(l ~= nil and not l:find("NOT:", 1, true), "the swap: the doubles off, the real fleet up, your view back", l)
    end)
    A.log_("fleet: Ctrl%+N: %d+ of %d+ ships up", 30, "s0", false, function(l)
        ST.check(l ~= nil, "the real fleet up after the surfacing", l)
    end)
    A.wait(2)
    A.do_(function() ST.shot("surfacing_after") end)
end
-- (2026-11-16) round 30 as it will look: the fleet's arc at its pre-dawn (step 5) with the storm in, then Ctrl+N: the fleet
-- surfacing in the storm, its cinematic pictured as it plays, the real fleet up after
SUITES.round30 = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSURF ~= nil, "the fleet's night and surfacing are in this build") then return "abort" end
        IFSKY.step(2)                                     -- (the night first: the storm comes in at its moon)
    end)
    A.wait(8)
    A.do_(function() IFSKY.step(5) end)                   -- (round 30: the pre-dawn, the storm on)
    A.wait(8)
    A.do_(function()
        local a, w = SKY.arcState(), IFSKY.storm()
        ST.check(a.k == 5 and w.on, "round 30's pre-dawn, the storm on", string.format("step %s, %s, storm %s, %d flashes", tostring(a.k), tostring(a.mode), tostring(w.on), w.flashes or 0))
        ST.marks.s0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet surfacing: %d+ ships rise over", 10, "s0", false, function(l)
        if not ST.check(l ~= nil, "the surfacing started in the storm", l) then return "abort" end
    end)
    for i = 1, 18 do
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("r30_%02d", i)); if i >= 15 then ST.near(3000, "r30_" .. i) end end)
    end
    A.log_("fleet surfacing: the rise over", 20, "s0", true, function(l)
        local up, of = nil, nil
        if l then up, of = l:match("(%d+) of (%d+) doubles up") end
        ST.check(up ~= nil and up == of and tonumber(of) >= 15, "every ship's double rose", l)
    end)
    A.log_("fleet surfacing: over", 10, "s0", true, function(l)
        ST.check(l ~= nil and not l:find("NOT:", 1, true), "the swap and your view back", l)
    end)
    for i = 1, 4 do
        A.wait(0.7)
        A.do_(function() ST.shot(string.format("r30_over_%d", i)); ST.near(3000, "over_" .. i) end)
    end
    A.log_("fleet: Ctrl%+N: %d+ of %d+ ships up", 30, "s0", false, function(l)
        ST.check(l ~= nil, "the real fleet up after the surfacing", l)
    end)
    A.wait(2)
    A.do_(function() ST.shot("r30_after"); IFSKY.step(nil) end)
end
-- (2026-11-17) the epic surfacing (sv_fleet_surface.lua; the user: "make the Ships Rising out of the sea cutscene more
-- cinematic? like go epic with it"): round30's storm and Ctrl+N, a picture every 1.5 s of its ~30 s, then its log: 6 shots
-- each a move, the 9 beats (3 radio lines, the cued strikes, the title card), the letterbox, the hand-held shake, shakes
-- at the breaches and GEOFON's big one, the real fleet up after
SUITES.epic = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSURF ~= nil and IFSURF.quiet ~= nil and IFSKY.strike ~= nil,
            "the epic surfacing is in this build (IFSURF.quiet, IFSKY.strike)") then return "abort" end
        IFSKY.step(2)
    end)
    A.wait(8)
    A.do_(function() IFSKY.step(5) end)
    A.wait(8)
    A.do_(function()
        local w = IFSKY.storm()
        ST.check(w.on, "round 30's pre-dawn, the storm on", string.format("storm %s, %d flashes", tostring(w.on), w.flashes or 0))
        ST.marks.s0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet surfacing: %d+ ships rise over", 10, "s0", false, function(l)
        if not ST.check(l ~= nil, "the surfacing started", l) then return "abort" end
        ST.check(l:find("letterbox 2.39", 1, true) ~= nil and l:find("6 shots, 9 beats", 1, true) ~= nil,
            "its letterbox, 6 shots and 9 beats", l)
        ST.check(l:find("hand-held shake on", 1, true) ~= nil, "the hand-held shake on", l)
        ST.check(l:find("Survival's true", 1, true) ~= nil, "Survival's HUD held", l)
    end)
    for i = 1, 22 do
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("epic_%02d", i)) end)
    end
    A.log_("fleet surfacing: the rise over", 20, "s0", true, function(l)
        local up, of = nil, nil
        if l then up, of = l:match("(%d+) of (%d+) doubles up") end
        ST.check(up ~= nil and up == of and tonumber(of) >= 15, "every ship's double rose", l)
    end)
    A.log_("fleet surfacing: over", 10, "s0", true, function(l)
        ST.check(l ~= nil and not l:find("NOT:", 1, true), "the swap and your view back", l)
        local sk, bt = nil, nil
        if l then sk, bt = l:match("(%d+) shakes, %d+ roars, (%d+) beats") end
        ST.check(tonumber(sk or 0) >= 1 and tonumber(bt or 0) == 9, "shakes at the breaches, all 9 beats", l)
        for i = 1, 6 do
            local s6 = ST.findLog("fleet surfacing: shot " .. i .. " at", ST.marks.s0, true)
            ST.check(s6 ~= nil and s6:find("move", 1, true) ~= nil and not s6:find("NOT taken", 1, true), "shot " .. i .. ", a move", s6)
        end
        local big = ST.findLog("GEOFON slams down, the big shake", ST.marks.s0, true)
        ST.check(big ~= nil, "GEOFON's slam: the big shake", big)
        for _, w in ipairs({ "CHARLENE says", "CTRL says", "VALKA says", "the title card", "a strike by GEOFON" }) do
            local b = ST.findLog(w, ST.marks.s0, true)
            ST.check(b ~= nil, "beat: " .. w, b)
        end
        local st = ST.findLog("a strike by PicketA", ST.marks.s0, true)
        ST.info("the first cued strike: " .. tostring(st))
    end)
    for i = 1, 3 do
        A.wait(0.7)
        A.do_(function() ST.shot(string.format("epic_over_%d", i)) end)
    end
    A.log_("fleet: Ctrl%+N: %d+ of %d+ ships up", 30, "s0", false, function(l)
        ST.check(l ~= nil, "the real fleet up after the surfacing", l)
    end)
    A.wait(2)
    A.do_(function() ST.shot("epic_after"); IFSKY.step(nil) end)
end
-- (2026-11-16) the storm's lightning bolt as drawn (round30 run 45: a checkered sheet by the plane: a ribbon with the
-- default material?): THUNDER.cloudFlash's bolt (NS_CloudLightning x bolt_scale) and its cloud light, each spawned at 3, 6
-- and 12 km in front of a fixed camera over the airfield, by day, the game's own shot a moment after
SUITES.bolt = function()
    intoRun()
    local R = { X = 1609574, Y = -435747, Z = 500 }
    local eye = { X = R.X, Y = R.Y, Z = 60000 }
    local dir = { X = -0.7071, Y = -0.7071 }
    A.do_(function()
        if not ST.check(THUNDER ~= nil and THUNDER.cloudFlash ~= nil, "the storm's cloud lightning is in this build") then return "abort" end
        if tostring(ST.conf.night) == "1" and IFSKY and IFSKY.step then IFSKY.step(3) end   -- (conf night=1: the fleet's storm night)
    end)
    A.wait(tostring(ST.conf.night) == "1" and 12 or 0.5)
    A.do_(function() ST.look(eye, { X = eye.X + dir.X * 1000000, Y = eye.Y + dir.Y * 1000000, Z = 120000 }, 60) end)
    A.wait(2)
    for _, k in ipairs({ { 3, "bolt" }, { 6, "bolt" }, { 12, "bolt" }, { 6, "class" } }) do
        local km, how = k[1], k[2]
        A.do_(function()
            local cls = ((((CFG.specials.fleet or {}).sky or {}).storm or {}).lightning or {}).class
            local at = { X = eye.X + dir.X * km * 100000, Y = eye.Y + dir.Y * km * 100000, Z = 250000 }
            local ok, what = pcall(THUNDER.cloudFlash, at, how == "class" and cls or "bolt", "the bolt probe")
            ST.info(string.format("bolt probe: %s at %d km: %s", how, km, ok and tostring(what) or ("error " .. tostring(what))))
        end)
        A.wait(0.25)
        A.do_(function() ST.shot(string.format("bolt_%s_%02dkm", how, km)) end)
        A.wait(0.6)
        A.do_(function() ST.shot(string.format("bolt_%s_%02dkm_b", how, km)) end)
        A.wait(2.5)
    end
    -- (Mission 12's lightning volume's own effects: BP_LightninigVolume_MS12's defaults, each spawned 6 km ahead in view)
    A.do_(function()
        local cls = loadObject("/Game/Blueprints/System/Lightning/BP_LightninigVolume_MS12.BP_LightninigVolume_MS12_C")
        local cdo
        pcall(function() cdo = cls:GetCDO() end)
        if not cdo then pcall(function() cdo = StaticFindObject("/Game/Blueprints/System/Lightning/BP_LightninigVolume_MS12.Default__BP_LightninigVolume_MS12_C") end) end
        ST.BOLTS = {}
        local parts = {}
        for _, f in ipairs({ "LightinigEffect", "LivelyLightinigEffect", "LightinigPredictiveVoltageEffect" }) do
            local okF, v = pcall(function() return cdo[f] end)
            local nm = okF and v and v:IsValid() and v:GetFullName() or "none"
            parts[#parts + 1] = f .. " = " .. nm
            if nm ~= "none" then ST.BOLTS[#ST.BOLTS + 1] = { f = f, sys = v } end
        end
        local okI, iv = pcall(function() return cdo.PointLightIntensityMultiplier end)
        ST.info("bolt probe: Mission 12's lightning volume: " .. table.concat(parts, "; ") .. "; light x" .. tostring(okI and iv))
    end)
    for k = 1, 3 do
        A.do_(function()
            local b = ST.BOLTS and ST.BOLTS[k]
            if not b then return end
            local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
            local at = { X = eye.X + dir.X * 600000, Y = eye.Y + dir.Y * 600000, Z = 0 }
            local ok, c = pcall(function() return lib:SpawnSystemAtLocation(ST.pc(), b.sys, at, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = 1, Y = 1, Z = 1 }, true, true, 0, false) end)
            ST.info(string.format("bolt probe: %s spawned 6 km ahead at sea level: %s", b.f, tostring(ok and c ~= nil)))
        end)
        A.wait(0.2)
        A.do_(function() if ST.BOLTS and ST.BOLTS[k] then ST.shot(string.format("bolt_vol_%d", k)) end end)
        A.wait(0.5)
        A.do_(function() if ST.BOLTS and ST.BOLTS[k] then ST.shot(string.format("bolt_vol_%d_b", k)) end end)
        A.wait(2)
    end
    A.do_(function() ST.lookBack() end)
end
-- (2026-11-16) lightning bolts from AC8's own bolt meshes (runs 46-49: NS_CloudLightning draws no bolt, Mission 12's volume
-- effects are discharges on a plane): SM_Thunder001 / 004 / SM_StraightLightning001 as a Movable StaticMeshActor, 4 km
-- ahead of a fixed camera over the airfield, at three scales, shown 0.4 s then taken off; the storm night (conf night=1)
SUITES.meshbolt = function()
    intoRun()
    local R = { X = 1609574, Y = -435747, Z = 500 }
    local eye = { X = R.X, Y = R.Y, Z = 60000 }
    local dir = { X = -0.7071, Y = -0.7071 }
    local M = "/Game/VFX/ResourceAsset/Mesh/Lightning/"
    A.do_(function()
        if tostring(ST.conf.night) == "1" and IFSKY and IFSKY.step then IFSKY.step(3) end
    end)
    A.wait(tostring(ST.conf.night) == "1" and 12 or 0.5)
    A.do_(function() ST.look(eye, { X = eye.X + dir.X * 1000000, Y = eye.Y + dir.Y * 1000000, Z = 100000 }, 60) end)
    A.wait(2)
    for _, k in ipairs({ { "SM_Thunder001_IE03", 30 }, { "SM_Thunder001_IE03", 100 }, { "SM_Thunder004_IE03", 100 },
                         { "SM_StraightLightning001_IE03", 100 }, { "SM_Thunder006_IE04", 100 } }) do
        local name, sc = k[1], k[2]
        local B = {}
        A.do_(function()
            local mesh = loadObject(M .. name .. "." .. name)
            local gs, cls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.StaticMeshActor")
            local at = { X = eye.X + dir.X * 400000, Y = eye.Y + dir.Y * 400000, Z = 150000 }
            local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = { X = sc, Y = sc, Z = sc } }
            local okB, a = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
            if not (okB and a and valid(a) and mesh) then ST.info("meshbolt: " .. name .. " NOT spawned (mesh " .. tostring(mesh) .. ")"); return end
            local c = a.StaticMeshComponent
            pcall(function() c:SetMobility(2) end)
            pcall(function() gs:FinishSpawningActor(a, t, 1) end)
            pcall(function() c:SetMobility(2) end)
            local okS = pcall(function() c:SetStaticMesh(mesh) end)
            if tostring(ST.conf.mat or "") ~= "" then           -- (conf mat=<path>: the lightning's own material on it; the meshes carry the checker)
                local mi = loadObject(tostring(ST.conf.mat))
                pcall(function() c:SetMaterial(0, mi) end)
            end
            local mat = "?"
            pcall(function() mat = c:GetMaterial(0):GetFullName() end)
            local bx = "?"
            pcall(function() local b = mesh:GetBounds(); bx = string.format("%.0f x %.0f x %.0f cm", b.BoxExtent.X * 2, b.BoxExtent.Y * 2, b.BoxExtent.Z * 2) end)
            B.a = a
            ST.info(string.format("meshbolt: %s x%d 4 km ahead: mesh set %s, material %s, its size %s", name, sc, tostring(okS), mat, bx))
        end)
        A.wait(0.15)
        A.do_(function() ST.shot(string.format("meshbolt_%s_x%d", name, sc)) end)
        A.wait(0.3)
        A.do_(function() if B.a and valid(B.a) then pcall(function() B.a:K2_DestroyActor() end) end end)
        A.wait(1.5)
    end
    A.do_(function() ST.lookBack() end)
end
-- (2026-11-16) a bolt you can see (runs 46-51: NS_CloudLightning's sprites and the bare bolt meshes never showed): the Online
-- Alicorn's lightning arc (NS_alcn_LiSpark_edge*: a bolt mesh with its own material, glow, sparks and light) and the cloud
-- lightning, each spawned ahead of your plane at a few sizes and turns, pictured from your own view; the storm night (night=1)
SUITES.arcbolt = function()
    intoRun()
    local O = "/Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/"
    local CL = "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning"
    A.do_(function()
        if tostring(ST.conf.night) == "1" and IFSKY and IFSKY.step then IFSKY.step(3) end
    end)
    A.wait(tostring(ST.conf.night) == "1" and 12 or 0.5)
    local E = "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/"
    local TRY = (tostring(ST.conf.set) == "2") and {
        { E .. "NS_ElectricEvasion001", 10, 2, 300, 0 },
        { E .. "NS_ElectricEvasion001", 40, 4, 600, 0 },
        { E .. "NS_ElectricEvasion001", 40, 4, 600, 90 },
        { E .. "NS_ElectricDischargeM001", 20, 2, 300, 0 },
        { E .. "NS_ElectricDischargeM001", 80, 4, 600, 0 },
        { O .. "NS_alcn_LiSpark_edgesingle_ON", 150, 6, 800, 90, true },
        { O .. "NS_alcn_LiSpark_edgedouble_ON", 300, 10, 1500, 90, true },
    } or {
        { O .. "NS_alcn_LiSpark_edgesingle_ON", 30, 2, 300, 0 },
        { O .. "NS_alcn_LiSpark_edgesingle_ON", 150, 4, 600, 0 },
        { O .. "NS_alcn_LiSpark_edgesingle_ON", 150, 4, 600, 90 },
        { O .. "NS_alcn_LiSpark_edgedouble_ON", 150, 4, 600, 90 },
        { O .. "NS_alcn_LiSpark_pointdouble_ON", 150, 4, 600, 0 },
        { CL, 12, 4, 800, 0 },
        { CL, 60, 8, 1500, 0 },
    }
    for n, k in ipairs(TRY) do
        local path, sc, km, up, pitch = k[1], k[2], k[3], k[4], k[5]
        A.do_(function()
            local pl = ST.plane()
            local sys = loadObject(path .. "." .. (path:match("([^/]+)$")))
            local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
            if not (pl and sys and lib) then ST.info("arcbolt " .. n .. ": no plane / system / library"); return end
            local at = ST.frame(pl, km * 100000, 0, up * 100)
            local yaw = 0
            pcall(function() yaw = pl:K2_GetActorRotation().Yaw end)
            local ok, c = pcall(function() return lib:SpawnSystemAtLocation(ST.pc(), sys, at, { Pitch = pitch, Yaw = yaw + 90, Roll = 0 }, { X = sc, Y = sc, Z = sc }, true, true, 0, false) end)
            if ok and c then pcall(function() c:SetVariableFloat(FName("Scale"), sc) end) end
            if ok and c and k[6] then                     -- (white-blue: the arc's Color, both spellings)
                for _, nmC in ipairs({ "Color", "User.Color" }) do
                    pcall(function() c:SetVariableLinearColor(FName(nmC), { R = 3.0, G = 4.0, B = 8.0, A = 1.0 }) end)
                end
            end
            ST.info(string.format("arcbolt %d: %s x%d, %d km ahead, %d m up, pitch %d: %s", n, path:match("([^/]+)$"), sc, km, up, pitch, tostring(ok and c ~= nil)))
        end)
        A.wait(0.1)
        A.do_(function() ST.shot(string.format("arcbolt_%d_a", n)) end)
        A.wait(0.4)
        A.do_(function() ST.shot(string.format("arcbolt_%d_b", n)) end)
        A.wait(2)
    end
end
-- (2026-11-16) the cloud flash's ways, pictured from your view in the storm night (run 53: a light inside the storm clouds
-- lights them up): Cloudly's effect light ("effect") and the three stock cloud light classes with a real radius (the
-- storm gave them none: 10 m), each 5 km ahead and 1 km up, pictured at +0.1 and +0.35 s
SUITES.cloudflash = function()
    intoRun()
    A.do_(function()
        if not ST.check(THUNDER ~= nil and THUNDER.cloudFlash ~= nil, "the cloud flash is in this build") then return "abort" end
        if IFSKY and IFSKY.step then IFSKY.step(3) end
    end)
    A.wait(12)
    local BP = "/Game/Blueprints/Cloudly/CloudLight/"
    local TRY = {
        { "effect", nil }, { "effect", nil },
        { BP .. "BP_CloudLight_Ms009_FarExplosion.BP_CloudLight_Ms009_FarExplosion_C", 4000 },
        { BP .. "BP_CloudLight_Ms012_PodargeDead.BP_CloudLight_Ms012_PodargeDead_C", 4000 },
        { BP .. "BP_CloudLight_Ms022_ShuttleLaunch.BP_CloudLight_Ms022_ShuttleLaunch_C", 4000 },
    }
    for n, k in ipairs(TRY) do
        A.do_(function()
            local L = (((CFG.specials or {}).thunder or {}).buildup or {}).lightning
            local lc = type(L) == "table" and L or nil
            if lc then lc.radius_m, lc.bolt = k[2] or 6000, false end
            local pl = ST.plane()
            local at = ST.frame(pl, 500000, (n % 2 == 0) and 150000 or -150000, 100000)
            local ok, what = pcall(THUNDER.cloudFlash, at, k[1], "the cloud flash probe")
            ST.info(string.format("cloudflash %d: %s (radius %s m): %s", n, k[1]:match("BP_CloudLight_([%w_]+)%.") or k[1], tostring(k[2] or 6000), ok and tostring(what) or ("error " .. tostring(what))))
        end)
        A.wait(0.1)
        A.do_(function() ST.shot(string.format("cloudflash_%d_a", n)) end)
        A.wait(0.25)
        A.do_(function() ST.shot(string.format("cloudflash_%d_b", n)) end)
        A.wait(3)
    end
end
-- (2026-11-16) a bolt drawn from AC8's own blue laser beam (NS_UAVTLS_Muzzleflash01: User.BeamLength = { length, width,
-- width } along its forward axis): 8 segments zigzagging from the cloud base (2 km) down to the sea, a 3-segment branch,
-- 5 km ahead of your plane and 1.5 km aside, at widths 3, 10 and 25, then the player TLS beam; the storm night
SUITES.beambolt = function()
    intoRun()
    local TLS = "/Game/VFX/Vehicles/Weapon/TLS/"
    A.do_(function() if IFSKY and IFSKY.step then IFSKY.step(3) end end)
    A.wait(12)
    local function seg(lib, sys, a, b, w, life)
        local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        local rot = { Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }
        local ok, c = pcall(function() return lib:SpawnSystemAtLocation(ST.pc(), sys, a, rot, { X = 1, Y = 1, Z = 1 }, true, true, 0, false) end)
        if not (ok and c) then return nil end
        for _, nm in ipairs({ "User.BeamLength", "BeamLength" }) do
            pcall(function() c:SetVariableVec3(FName(nm), { X = len, Y = w, Z = w }) end)
        end
        for _, nm in ipairs({ "User.BeamLifeTime", "BeamLifeTime" }) do pcall(function() c:SetVariableFloat(FName(nm), life) end) end
        return c
    end
    for n, k in ipairs({ { "NS_UAVTLS_Muzzleflash01", 3 }, { "NS_UAVTLS_Muzzleflash01", 10 }, { "NS_UAVTLS_Muzzleflash01", 25 },
                         { "NS_TLS_Muzzleflash01", 10 } }) do
        local B = { cs = {} }
        A.do_(function()
            local pl = ST.plane()
            local sys = loadObject(TLS .. k[1] .. "." .. k[1])
            local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
            if not (pl and sys and lib) then ST.info("beambolt " .. n .. ": no plane / system / library"); return end
            local base = ST.frame(pl, 500000, (n % 2 == 0) and 150000 or -150000, 0)
            local fw = ST.frame(pl, 100, 0, 0)
            local P0 = ST.at(pl)
            local fx, fy = fw.X - P0.X, fw.Y - P0.Y
            local fl = math.sqrt(fx * fx + fy * fy); fx, fy = fx / fl, fy / fl
            local rx, ry = -fy, fx
            local pts, top = {}, 200000
            for i = 0, 8 do
                local side = (i == 0 or i == 8) and 0 or (math.random() * 2 - 1) * 15000
                local along = (i == 0 or i == 8) and 0 or (math.random() * 2 - 1) * 8000
                pts[#pts + 1] = { X = base.X + rx * side + fx * along, Y = base.Y + ry * side + fy * along, Z = top * (1 - i / 8) }
            end
            for i = 1, 8 do local c = seg(lib, sys, pts[i], pts[i + 1], k[2], 0.4); if c then B.cs[#B.cs + 1] = c end end
            local j = pts[3]                                   -- (a branch off the third joint)
            local last = j
            for i = 1, 3 do
                local nx = { X = last.X + rx * 9000 + (math.random() * 2 - 1) * 4000, Y = last.Y + ry * 9000 + (math.random() * 2 - 1) * 4000, Z = last.Z - 22000 }
                local c = seg(lib, sys, last, nx, k[2] * 0.6, 0.4); if c then B.cs[#B.cs + 1] = c end
                last = nx
            end
            ST.info(string.format("beambolt %d: %s width %d: %d of 11 segments up, 5 km ahead, 2 km tall", n, k[1], k[2], #B.cs))
        end)
        A.wait(0.08)
        A.do_(function() ST.shot(string.format("beambolt_%d_a", n)) end)
        A.wait(0.25)
        A.do_(function() ST.shot(string.format("beambolt_%d_b", n)) end)
        A.wait(0.4)
        A.do_(function() for _, c in ipairs(B.cs) do pcall(function() c:DestroyComponent() end) end end)
        A.wait(2.5)
    end
end
-- (2026-11-16) a flash of our own in the storm clouds (run 53: a light inside them shows them; run 55: the stock cloud lights
-- ramp up over seconds in their own colours): an engine PointLight, blue-white, km of radius, at three strengths, 6 km
-- ahead and 3 km up, pictured at +0.1 and +0.3 s, then off; the storm night
SUITES.pointflash = function()
    intoRun()
    A.do_(function() if IFSKY and IFSKY.step then IFSKY.step(3) end end)
    A.wait(12)
    for n, k in ipairs({ { 1e7, 6000 }, { 1e9, 6000 }, { 1e11, 8000 }, { 1e9, 15000 } }) do
        local B = {}
        A.do_(function()
            local pl = ST.plane()
            local gs, cls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.PointLight")
            local at = ST.frame(pl, 600000, (n % 2 == 0) and 200000 or -200000, 0)
            at.Z = 300000
            local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = { X = 1, Y = 1, Z = 1 } }
            local okB, a = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
            if not (okB and a and valid(a)) then ST.info("pointflash " .. n .. ": no light"); return end
            pcall(function() gs:FinishSpawningActor(a, t, 1) end)
            local c = a.PointLightComponent
            local done = {}
            for _, f in ipairs({
                { "mobility", function() c:SetMobility(2) end },
                { "colour", function() c:SetLightColor({ R = 0.75, G = 0.82, B = 1.0, A = 1.0 }, true) end },
                { "radius", function() c:SetAttenuationRadius(k[2] * 100) end },
                { "intensity", function() c:SetIntensity(k[1]) end },
                { "source", function() c:SetSourceRadius(20000) end },
            }) do done[#done + 1] = f[1] .. (pcall(f[2]) and "" or " NOT") end
            local units = "?"
            pcall(function() units = tostring(c.IntensityUnits) end)
            B.a = a
            ST.info(string.format("pointflash %d: intensity %.0e, radius %d m (units %s): %s", n, k[1], k[2], units, table.concat(done, ", ")))
        end)
        A.wait(0.1)
        A.do_(function() ST.shot(string.format("pointflash_%d_a", n)) end)
        A.wait(0.2)
        A.do_(function() ST.shot(string.format("pointflash_%d_b", n)) end)
        A.wait(0.2)
        A.do_(function() if B.a and valid(B.a) then pcall(function() B.a:K2_DestroyActor() end) end end)
        A.wait(2.5)
    end
end
-- (2026-11-16) the lightning effects with their parameters set BEFORE they start (runs 53-56 set them after: the Alicorn arc
-- stayed red, the beam drew nothing): spawned inactive, Color / BeamLength / BeamLifeTime set, then activated. The cloud
-- lightning big and white-blue, the Alicorn arc white-blue, a jagged bolt of the UAV beam; the storm night
SUITES.fxparams = function()
    intoRun()
    local O = "/Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/"
    local CLp = "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning"
    local TLS = "/Game/VFX/Vehicles/Weapon/TLS/NS_UAVTLS_Muzzleflash01"
    A.do_(function() if IFSKY and IFSKY.step then IFSKY.step(3) end end)
    A.wait(12)
    local function sysOf(path) return loadObject(path .. "." .. path:match("([^/]+)$")) end
    local function spawn(sys, at, rot, sc, params)
        local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
        local ok, c = pcall(function() return lib:SpawnSystemAtLocation(ST.pc(), sys, at, rot, { X = sc, Y = sc, Z = sc }, true, false, 0, false) end)
        if not (ok and c) then return nil end
        for _, q in ipairs(params) do
            for _, nm in ipairs({ q[1], "User." .. q[1] }) do
                if q[2] == "c" then pcall(function() c:SetVariableLinearColor(FName(nm), q[3]) end)
                elseif q[2] == "v" then pcall(function() c:SetVariableVec3(FName(nm), q[3]) end)
                else pcall(function() c:SetVariableFloat(FName(nm), q[3]) end) end
            end
        end
        pcall(function() c:Activate(true) end)
        return c
    end
    local WB = { R = 4.0, G = 5.0, B = 9.0, A = 1.0 }
    local TRY = {
        { "cloud lightning x40, white-blue", function(pl, cs)
            local at = ST.frame(pl, 500000, -150000, 0); at.Z = 250000
            cs[#cs + 1] = spawn(sysOf(CLp), at, { Pitch = 0, Yaw = 0, Roll = 0 }, 40, { { "Color", "c", WB } }) end },
        { "cloud lightning x120, white-blue x4", function(pl, cs)
            local at = ST.frame(pl, 800000, 200000, 0); at.Z = 300000
            cs[#cs + 1] = spawn(sysOf(CLp), at, { Pitch = 0, Yaw = 0, Roll = 0 }, 120, { { "Color", "c", { R = 16, G = 20, B = 36, A = 1 } } }) end },
        { "the Alicorn arc x150, white-blue", function(pl, cs)
            local at = ST.frame(pl, 400000, -120000, 50000)
            cs[#cs + 1] = spawn(sysOf(O .. "NS_alcn_LiSpark_edgesingle_ON"), at, { Pitch = 90, Yaw = 0, Roll = 0 }, 150, { { "Color", "c", WB } }) end },
        { "a UAV beam bolt, width 25", function(pl, cs)
            local sys = sysOf(TLS)
            local base = ST.frame(pl, 500000, 150000, 0)
            local fw, P0 = ST.frame(pl, 100, 0, 0), ST.at(pl)
            local fx, fy = fw.X - P0.X, fw.Y - P0.Y
            local fl = math.sqrt(fx * fx + fy * fy); fx, fy = fx / fl, fy / fl
            local pts = {}
            for i = 0, 8 do
                local side = (i == 0 or i == 8) and 0 or (math.random() * 2 - 1) * 15000
                pts[#pts + 1] = { X = base.X - fy * side, Y = base.Y + fx * side, Z = 200000 * (1 - i / 8) }
            end
            for i = 1, 8 do
                local a, b = pts[i], pts[i + 1]
                local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
                local len = math.sqrt(dx * dx + dy * dy + dz * dz)
                cs[#cs + 1] = spawn(sys, a, { Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }, 1,
                    { { "BeamLength", "v", { X = len, Y = 25, Z = 25 } }, { "BeamLifeTime", "f", 0.5 } })
            end
        end },
    }
    for n, k in ipairs(TRY) do
        local B = { cs = {} }
        A.do_(function()
            local pl = ST.plane()
            if not pl then return end
            local ok, err = pcall(k[2], pl, B.cs)
            ST.info(string.format("fxparams %d: %s: %d effects started%s", n, k[1], #B.cs, ok and "" or (" (error " .. tostring(err) .. ")")))
        end)
        A.wait(0.1)
        A.do_(function() ST.shot(string.format("fxparams_%d_a", n)) end)
        A.wait(0.3)
        A.do_(function() ST.shot(string.format("fxparams_%d_b", n)) end)
        A.wait(0.6)
        A.do_(function() for _, c in ipairs(B.cs) do pcall(function() c:DestroyComponent() end) end end)
        A.wait(2.5)
    end
end
-- (2026-11-17) why runs 50-51's bolt meshes drew nothing (not even the default checker): an engine cube and a bolt mesh as
-- StaticMeshActors, Movable before they finish, 2-3 km ahead of your plane, SetStaticMesh's own answer and the component's
-- bounds read back, pictured at +0.2, +1 and +3 s; by day (no night=1) or the storm night
SUITES.meshbolt2 = function()
    intoRun()
    A.do_(function() if tostring(ST.conf.night) == "1" and IFSKY and IFSKY.step then IFSKY.step(3) end end)
    A.wait(tostring(ST.conf.night) == "1" and 12 or 0.5)
    local M = "/Game/VFX/ResourceAsset/Mesh/Lightning/"
    local T1 = M .. "SM_Thunder001_IE03.SM_Thunder001_IE03"
    local AL, LT = "/Game/OnlineMode/VFX/Vehicles/Boss/", "/Game/VFX/Environment/Common/Lightning/CloudLightning/"
    local SET = (tostring(ST.conf.set) == "mats") and {
        { T1, 15, 3000, AL .. "BA002_alcn/Material/M_alcn_LiSparkEdge_ON.M_alcn_LiSparkEdge_ON" },
        { T1, 15, 3000, AL .. "BA004_chnd/Material/MI_chnd_Flash002_ON.MI_chnd_Flash002_ON" },
        { T1, 15, 3000, AL .. "BA002_alcn/Material/MI_alcn_Glow001_ON.MI_alcn_Glow001_ON" },
        { T1, 15, 3000, LT .. "MI_CloudLightning001.MI_CloudLightning001" },
        { T1, 15, 3000, LT .. "MI_NearCloudLightning001.MI_NearCloudLightning001" },
    } or { { "/Engine/BasicShapes/Cube.Cube", 100, 2000, nil }, { T1, 15, 3000, nil },
           { T1, 15, 3000, "/Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial" } }
    for n, k in ipairs(SET) do
        local B = {}
        A.do_(function()
            local pl = ST.plane()
            local mesh = loadObject(k[1])
            local gs, cls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.StaticMeshActor")
            local at = ST.frame(pl, k[3] * 100, (n == 1) and -60000 or 60000, 20000)
            local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = { X = k[2], Y = k[2], Z = k[2] } }
            local okB, a = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
            if not (okB and a and valid(a) and mesh) then ST.info("meshbolt2 " .. n .. ": NOT spawned (mesh " .. tostring(mesh) .. ")"); return end
            local c = a.StaticMeshComponent
            local mob0 = "?"; pcall(function() mob0 = tostring(c.Mobility) end)
            pcall(function() c:SetMobility(2) end)
            local set1 = "?"; pcall(function() set1 = tostring(c:SetStaticMesh(mesh)) end)
            pcall(function() gs:FinishSpawningActor(a, t, 1) end)
            local set2 = "?"; pcall(function() set2 = tostring(c:SetStaticMesh(mesh)) end)
            if k[4] then local mi = loadObject(k[4]); pcall(function() c:SetMaterial(0, mi) end) end
            local got, mat, vis, sc, mob = "?", "?", "?", "?", "?"
            pcall(function() got = c.StaticMesh:GetFullName():match("([^%./ ]+)$") end)
            pcall(function() mat = c:GetMaterial(0):GetFullName():match("([^%./ ]+)$") end)
            pcall(function() vis = tostring(c:IsVisible()) .. "/" .. tostring(a.bHidden) end)
            pcall(function() local v = c:K2_GetComponentScale(); sc = string.format("%.0f", v.X) end)
            pcall(function() mob = tostring(c.Mobility) end)
            local bnd = "?"
            pcall(function() local o, e, r = nil, nil, nil; local b = c.Bounds; bnd = string.format("%.0f m", (b.SphereRadius or 0) / 100) end)
            local d = "?"
            pcall(function() local L = c:K2_GetComponentLocation(); local P = ST.at(pl); d = string.format("%.1f km", math.sqrt((L.X-P.X)^2+(L.Y-P.Y)^2+(L.Z-P.Z)^2) / 100000) end)
            B.a = a
            ST.info(string.format("meshbolt2 %d: %s x%s: mobility %s -> %s, SetStaticMesh before %s / after %s, mesh %s, material %s, visible/hidden %s, bounds %s, %s off",
                n, k[1]:match("([^%./]+)$"), sc, mob0, mob, set1, set2, got, mat, vis, bnd, d))
        end)
        for _, w in ipairs({ 0.2, 0.8, 2.0 }) do
            A.wait(w)
            A.do_(function() ST.shot(string.format("meshbolt2_%d_%.1f", n, w)) end)
        end
        A.do_(function() if B.a and valid(B.a) then pcall(function() B.a:K2_DestroyActor() end) end end)
        A.wait(1)
    end
end
-- (2026-11-17, 0.74.87) the fleet's storm night as you'd see it: its bolts (THUNDER.bolt: AC8's bolt meshes in the cloud
-- lightning material) warmed up under the fade, then flashing round the airfield; pictured from your view and from a fixed
-- camera 3 km up over the runway looking out to sea
SUITES.stormview = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil and THUNDER.bolt ~= nil, "the fleet's storm and its bolts are in this build") then return "abort" end
        ST.marks.s0 = ST.n
        IFSKY.step(3)
    end)
    A.log_("fleet storm: warm%-up under the black: %d+ bolts", 15, "s0", false, function(l)
        ST.check(l ~= nil and not l:find("under the black: 0 bolts", 1, true), "the bolts and the rain warmed up under the fade", l)
    end)
    A.log_("bolts: %d+ %(the fleet's storm%)", 20, "s0", false, function(l)
        ST.check(l ~= nil, "the storm's first bolt", l)
    end)
    for i = 1, 14 do
        A.wait(0.6)
        A.do_(function() ST.shot(string.format("storm_you_%02d", i)) end)
    end
    local eye = { X = 1610476, Y = -436143, Z = 300000 }
    A.do_(function() ST.look(eye, { X = eye.X - 1000000, Y = eye.Y - 300000, Z = 150000 }, 75) end)
    for i = 1, 10 do
        A.wait(0.7)
        A.do_(function() ST.shot(string.format("storm_wide_%02d", i)) end)
    end
    A.do_(function()
        ST.lookBack()
        local l = ST.findLog("bolts: ", ST.marks.s0, true)
        ST.info("stormview: the last bolt line: " .. tostring(l))
    end)
end
-- (2026-11-17) why the clouds don't light up (the user: "Can you try to find out why the clouds don't light up please"):
-- Cloudly lights its clouds from one effect light, which AC8's cloud lights (ALiveCloudLight) drive from a timeline. The stock
-- curves (build/stock BP_CloudLight_*): Mission 9's far explosion peaks near 15 (radius 70 km), Mission 12's Podarge 40,000
-- from 4.1 to 6.8 s after its spawn (radius 5 km, falloff 4), Mission 22's shuttle 7,000 from 5 s on (radius 2 km, falloff
-- 12); cloudflash pictured each at 0.1 and 0.35 s and moved on at 3 s, and the storm's own lights were Mission 9's. Here,
-- under the storm night, with the effect light read back each step (the Cloudly actor, its sky asset, the interpolated
-- params, the renderer's drawn copy): A Mission 12's light pictured every 0.5 s from 3.5 s; B the bare cloud light
-- (BP_CloudLight_Base: no timeline) held at 40,000 then 400,000, 6 km ahead then 2 km; C the sky asset's effect light
-- written straight (bEnableEffectLight on, the brightness, position in cm then in m, radius), its originals put back.
SUITES.cloudlit = function()
    intoRun()
    local CLT = {}
    local BPP = "/Game/Blueprints/Cloudly/CloudLight/"
    A.do_(function()
        local S = (((CFG.specials or {}).fleet or {}).sky or {}).storm
        if type(S) == "table" and type(S.lightning) == "table" then S.lightning.enabled = false end   -- (no bolts in the pictures)
        if tostring(ST.conf.night or "1") == "1" and IFSKY and IFSKY.step then IFSKY.step(3) end
    end)
    A.wait(12)
    local function f3(v) if type(v) ~= "number" then return tostring(v) end; return string.format("%.4g", v) end
    local function params(dd, nm)
        local s = nm .. ": ?"
        pcall(function()
            local p, t = dd.EffectLightParams, dd.EffectLightTransientParams
            local w, c = t.WorldPosition, t.LightColor
            s = string.format("%s: enable %s (density %s ^%s, brightness x%s, radius x%s, falloff x%s); light %s at %s %s %s, radius %s, falloff %s, colour %s %s %s, inverse-square %s",
                nm, tostring(p.bEnableEffectLight), f3(p.DensityAttenuationFactor), f3(p.DensityAttenuationExponent),
                f3(p.LightBrightnessScale), f3(p.AttenuationRadiusScale), f3(p.LightFalloffExponentScale),
                f3(t.LightBrightness), f3(w.X), f3(w.Y), f3(w.Z), f3(t.AttenuationRadius), f3(t.LightFalloffExponent),
                f3(c.X), f3(c.Y), f3(c.Z), tostring(t.bUseInverseSquaredFalloff))
        end)
        return s
    end
    local function elRead(tag)
        local V = SKY and SKY.viewCached and SKY.viewCached(os.clock(), nil)
        if not V then ST.info("cloudlit " .. tag .. ": no sky view"); return end
        local a = V.actor
        local use, el = "?", "?"
        pcall(function() use = tostring(a.bUseEffectLight) end)
        pcall(function() local l = a.EffectLight; el = (l ~= nil and liveObj(l)) and "yes" or "none" end)
        ST.info(string.format("cloudlit %s: the Cloudly actor (%s): bUseEffectLight %s, EffectLight %s", tag, tostring(V.actorBy), use, el))
        if V.asset then ST.info("cloudlit " .. tag .. ": " .. params(V.asset.Data, "the sky asset")) end
        if V.interp then ST.info("cloudlit " .. tag .. ": " .. params(V.interp.Data, "the interpolated params" .. (V.interpOk and "" or " (the asset itself)"))) end
        for _, r in ipairs(V.rend or {}) do
            local n = 0
            pcall(function()
                r.obj.Data.SkyParamsRO:ForEach(function(_, e)
                    n = n + 1
                    if n <= 2 then ST.info("cloudlit " .. tag .. ": " .. params(e:get(), "drawn copy " .. n .. " of " .. tostring(r.name))) end
                end)
            end)
            if n == 0 then ST.info("cloudlit " .. tag .. ": " .. tostring(r.name) .. " has no drawn copy to read") end
        end
        local l = CLT.a
        if l and valid(l) then
            local w = "?"
            pcall(function() local v = l.WorldPosition; w = string.format("%.0f %.0f %.0f", v.X, v.Y, v.Z) end)
            ST.info(string.format("cloudlit %s: the cloud light: brightness %s, radius %s, falloff %s, at %s, restore %s",
                tag, f3(l.LightBrightness), f3(l.AttenuationRadius), f3(l.LightFalloffExponent), w, tostring(l.bRestoreUseEffectLight)))
        end
    end
    local function spawnCL(name, at, set)
        local cls = loadObject(BPP .. name .. "." .. name .. "_C")
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not (cls and gs and valid(gs)) then return nil, "no class or GameplayStatics" end
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
        if not okB or x == nil or not valid(x) then return nil, "no actor" end
        pcall(function() x.WorldPosition = { X = at.X, Y = at.Y, Z = at.Z } end)
        if set then set(x) end
        local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
        if not okF or a == nil or not valid(a) then return nil, "its spawn didn't finish" end
        if set then set(a) end
        return a, "up"
    end
    local function hold(a, b, r, fo)
        pcall(function() a.LightBrightness = b end)
        pcall(function() a.AttenuationRadius = r end)
        pcall(function() a.LightFalloffExponent = fo end)
        pcall(function() a.LightColor = { R = 215, G = 225, B = 255, A = 255 } end)
        pcall(function() a.bUseInverseSquaredFalloff = false end)
    end
    local function ahead(km, up_m)
        local pl = ST.plane()
        if not pl then return nil end
        return ST.frame(pl, km * 100000, 0, up_m * 100)
    end
    -- A: Mission 12's Podarge light through its flash
    A.do_(function() elRead("0 before"); ST.shot("cloudlit_0_before") end)
    A.do_(function()
        local at = ahead(6, 1500)
        if not at then ST.info("cloudlit A: no plane"); return end
        local a, why = spawnCL("BP_CloudLight_Ms012_PodargeDead", at)
        CLT.a = a
        ST.info(string.format("cloudlit A: Mission 12's Podarge light 6 km ahead, 1.5 km over you (%.0f %.0f %.0f): %s", at.X, at.Y, at.Z, why))
    end)
    A.wait(1)
    A.do_(function() elRead("A +1 s") end)
    A.wait(2.5)
    for i = 1, 8 do
        A.do_(function()
            ST.shot(string.format("cloudlit_A_%d_%.1fs", i, 3 + 0.5 * i))
            if i == 3 or i == 5 then elRead(string.format("A +%.1f s", 3 + 0.5 * i)) end
        end)
        A.wait(0.5)
    end
    A.wait(2)
    A.do_(function() elRead("A after (its timeline over)"); CLT.a = nil end)
    -- B: the bare cloud light, held by us
    A.do_(function()
        local at = ahead(6, 1500)
        if not at then return end
        local a, why = spawnCL("BP_CloudLight_Base", at, function(x) hold(x, 40000, 500000, 4) end)
        CLT.a = a
        ST.info("cloudlit B: the bare cloud light held at 40000, radius 5 km, falloff 4, 6 km ahead: " .. why)
    end)
    A.wait(0.4)
    A.do_(function() ST.shot("cloudlit_B_1_40k") ; elRead("B 40000") end)
    A.wait(0.8)
    A.do_(function() ST.shot("cloudlit_B_2_40k") end)
    A.do_(function() if CLT.a and valid(CLT.a) then hold(CLT.a, 400000, 500000, 4) end end)
    A.wait(0.4)
    A.do_(function() ST.shot("cloudlit_B_3_400k"); elRead("B 400000") end)
    A.do_(function()
        local at = ahead(2, 600)
        if CLT.a and valid(CLT.a) and at then
            pcall(function() CLT.a.WorldPosition = { X = at.X, Y = at.Y, Z = at.Z } end)
            pcall(function() CLT.a:K2_SetActorLocation(at, false, {}, true) end)
        end
    end)
    A.wait(0.4)
    A.do_(function() ST.shot("cloudlit_B_4_400k_2km"); elRead("B 2 km") end)
    A.do_(function() if CLT.a and valid(CLT.a) then pcall(function() CLT.a:K2_DestroyActor() end) end; CLT.a = nil end)
    A.wait(0.6)
    A.do_(function() ST.shot("cloudlit_B_5_gone"); elRead("B gone") end)
    -- C: the sky asset's effect light written straight
    local function cWrite(scale, tag)
        local V = SKY and SKY.viewCached and SKY.viewCached(os.clock(), nil)
        local at = ahead(4, 1000)
        if not (V and V.asset and at) then ST.info("cloudlit C: no sky asset / plane"); return end
        local objs = { V.asset }
        if V.interpOk and V.interp then objs[#objs + 1] = V.interp end
        for k, o in ipairs(objs) do
            local d = o.Data
            if not CLT.orig then
                CLT.orig = {}
                pcall(function()
                    local p, t = d.EffectLightParams, d.EffectLightTransientParams
                    CLT.orig = { en = p.bEnableEffectLight, b = t.LightBrightness, r = t.AttenuationRadius, f = t.LightFalloffExponent,
                                 x = t.WorldPosition.X, y = t.WorldPosition.Y, z = t.WorldPosition.Z }
                end)
            end
            pcall(function() d.EffectLightParams.bEnableEffectLight = true end)
            pcall(function() d.EffectLightTransientParams.LightBrightness = 40000 end)
            pcall(function() d.EffectLightTransientParams.AttenuationRadius = 500000 * scale end)
            pcall(function() d.EffectLightTransientParams.LightFalloffExponent = 4 end)
            pcall(function() d.EffectLightTransientParams.LightColor = { X = 0.85, Y = 0.9, Z = 1.0 } end)
            pcall(function() d.EffectLightTransientParams.WorldPosition = { X = at.X * scale, Y = at.Y * scale, Z = at.Z * scale } end)
        end
        ST.info(string.format("cloudlit C (%s): the sky asset's effect light written%s: 40000, 4 km ahead, 1 km over you", tag, #objs > 1 and " (and the interpolated params)" or ""))
    end
    A.do_(function() cWrite(1, "cm") end)
    A.wait(0.4)
    A.do_(function() ST.shot("cloudlit_C_1_cm"); elRead("C cm") end)
    A.do_(function() cWrite(0.01, "m") end)
    A.wait(0.4)
    A.do_(function() ST.shot("cloudlit_C_2_m"); elRead("C m") end)
    A.do_(function()
        local V = SKY and SKY.viewCached and SKY.viewCached(os.clock(), nil)
        local o = CLT.orig or {}
        local objs = { V and V.asset }
        if V and V.interpOk and V.interp then objs[#objs + 1] = V.interp end
        for _, x in ipairs(objs) do
            if x then
                local d = x.Data
                if o.en ~= nil then pcall(function() d.EffectLightParams.bEnableEffectLight = o.en end) end
                pcall(function() d.EffectLightTransientParams.LightBrightness = o.b or 0 end)
                if o.r then pcall(function() d.EffectLightTransientParams.AttenuationRadius = o.r end) end
                if o.f then pcall(function() d.EffectLightTransientParams.LightFalloffExponent = o.f end) end
                if o.x then pcall(function() d.EffectLightTransientParams.WorldPosition = { X = o.x, Y = o.y, Z = o.z } end) end
            end
        end
        ST.info("cloudlit C: the sky asset's effect light put back (enable " .. tostring(o.en) .. ", brightness " .. tostring(o.b) .. ")")
    end)
    A.wait(0.4)
    A.do_(function() ST.shot("cloudlit_C_3_back"); elRead("C back") end)
end
-- (2026-11-17) cloudlit's run 65: Mission 12's light lit the storm clouds orange at 3.5-4.5 s, nothing at 5-6 s (its
-- brightness still 10-30k), white at 6.5-7 s (its curve at 0); the bare light held at 40k / 400k reached Cloudly's drawn
-- copy and lit nothing (after that white flash: the exposure down?). Here, a line a tick (Cloudly's switch, the drawn
-- copy's light, the asset's, the light's own): 1 the bare light first (the exposure still the night's), spawned at 0 and
-- driven a tick at a time (a ramp, a hold, a flicker), 3 km ahead; 2 Mission 12's light 4 km ahead, read from its spawn to
-- 9 s; 3 Mission 12's light at 4x (CustomTimeDilation: its flash at ~1-1.7 s), a lightning flash's length.
SUITES.cloudlit2 = function()
    intoRun()
    local CLT = { t0 = 0 }
    local BPP = "/Game/Blueprints/Cloudly/CloudLight/"
    A.do_(function()
        local S = (((CFG.specials or {}).fleet or {}).sky or {}).storm
        if type(S) == "table" and type(S.lightning) == "table" then S.lightning.enabled = false end
        if tostring(ST.conf.night or "1") == "1" and IFSKY and IFSKY.step then IFSKY.step(3) end
    end)
    A.wait(12)
    local function g(v) if type(v) ~= "number" then return "?" end; return string.format("%.4g", v) end
    local function lightOf(dd)
        local s = "?"
        pcall(function()
            local t = dd.EffectLightTransientParams
            local w, c = t.WorldPosition, t.LightColor
            s = string.format("%s (%.2f %.2f %.2f) at %.1f %.1f %.1f km r %s f %s", g(t.LightBrightness), c.X, c.Y, c.Z,
                w.X / 100000, w.Y / 100000, w.Z / 100000, g(t.AttenuationRadius), g(t.LightFalloffExponent))
        end)
        return s
    end
    local function rd(tag)
        local V = SKY and SKY.viewCached and SKY.viewCached(os.clock(), nil)
        if not V then return end
        local use, drawn, asset, own = "?", "?", "?", "-"
        pcall(function() use = tostring(V.actor.bUseEffectLight) end)
        if V.asset then asset = lightOf(V.asset.Data) end
        for _, r in ipairs(V.rend or {}) do
            local n = 0
            pcall(function() r.obj.Data.SkyParamsRO:ForEach(function(_, e) n = n + 1; if n == 1 then drawn = lightOf(e:get()) end end) end)
        end
        local l = CLT.a
        if l and valid(l) then pcall(function() own = g(l.LightBrightness) end) end
        ST.info(string.format("cl2 %s +%.2f s: use %s | drawn %s | asset %s | light %s", tag, os.clock() - CLT.t0, use, drawn,
            asset == drawn and "same" or asset, own))
    end
    local function spawnCL(name, at)
        local cls = loadObject(BPP .. name .. "." .. name .. "_C")
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not (cls and gs and valid(gs)) then return nil, "no class or GameplayStatics" end
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
        if not okB or x == nil or not valid(x) then return nil, "no actor" end
        pcall(function() x.WorldPosition = { X = at.X, Y = at.Y, Z = at.Z } end)
        local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
        if not okF or a == nil or not valid(a) then return nil, "its spawn didn't finish" end
        return a, "up"
    end
    local function ahead(km, up_m)
        local pl = ST.plane()
        if not pl then return nil end
        return ST.frame(pl, km * 100000, 0, up_m * 100)
    end
    -- 1: the bare light, driven by us a tick at a time
    A.do_(function() rd("0 before"); ST.shot("cl2_0_before") end)
    A.do_(function()
        local at = ahead(3, 300)
        if not at then ST.info("cl2 1: no plane"); return end
        local a, why = spawnCL("BP_CloudLight_Base", at)
        CLT.a, CLT.t0 = a, os.clock()
        if a then
            pcall(function() a.AttenuationRadius = 500000 end)
            pcall(function() a.LightFalloffExponent = 4 end)
            pcall(function() a.LightColor = { R = 215, G = 225, B = 255, A = 255 } end)
            pcall(function() a.bUseInverseSquaredFalloff = false end)
        end
        ST.info(string.format("cl2 1: the bare light 3 km ahead, 300 m over you (%.0f %.0f %.0f): %s", at.X, at.Y, at.Z, why))
    end)
    local SEQ = { 0, 0, 5000, 20000, 40000, 40000, 40000, 40000, 40000, 40000, 20000, 5000, 0, 0, 40000, 0, 40000, 40000, 0, 0,
                  400000, 400000, 400000, 400000, 0, 0 }
    for i, b in ipairs(SEQ) do
        A.do_(function()
            if CLT.a and valid(CLT.a) then pcall(function() CLT.a.LightBrightness = b end) end
            rd("1 set " .. b)
            if i % 2 == 0 then ST.shot(string.format("cl2_1_%02d_%d", i, b)) end
        end)
        A.wait(0.25)
    end
    A.do_(function() if CLT.a and valid(CLT.a) then pcall(function() CLT.a:K2_DestroyActor() end) end; CLT.a = nil end)
    A.wait(3)
    -- 2: Mission 12's light, read from its spawn to 9 s
    A.do_(function()
        local at = ahead(4, 500)
        if not at then return end
        local a, why = spawnCL("BP_CloudLight_Ms012_PodargeDead", at)
        CLT.a, CLT.t0 = a, os.clock()
        ST.info("cl2 2: Mission 12's light 4 km ahead, 500 m over you: " .. why)
    end)
    for i = 1, 36 do
        A.do_(function()
            rd("2")
            if i >= 12 and i % 2 == 0 then ST.shot(string.format("cl2_2_%02d", i)) end
        end)
        A.wait(0.25)
    end
    A.wait(3)
    -- 3: Mission 12's light at 4x
    A.do_(function()
        local at = ahead(4, 500)
        if not at then return end
        local a, why = spawnCL("BP_CloudLight_Ms012_PodargeDead", at)
        if a then pcall(function() a.CustomTimeDilation = 4 end) end
        CLT.a, CLT.t0 = a, os.clock()
        ST.info("cl2 3: Mission 12's light at 4x (CustomTimeDilation " .. tostring(a and a.CustomTimeDilation) .. "): " .. why)
    end)
    for i = 1, 14 do
        A.do_(function()
            rd("3")
            if i >= 3 and i <= 9 then ST.shot(string.format("cl2_3_%02d", i)) end
        end)
        A.wait(0.25)
    end
end
-- (2026-11-17) cloudlit3: runs 65-66 measured nothing: your plane flies IN the storm's cloud layer (ICING UP, a white-out,
-- the exposure swinging), so its view went white and black whatever the light did. Here a still camera outside the clouds
-- (5 km over your plane looking down onto the layer 6 km ahead; then 1.8 km under it looking up) and the bare cloud light
-- (BP_CloudLight_Base, ours a tick at a time) in the layer at that spot: off, 40k, off, 400k, 4M (radius 50 km), off, each
-- pictured 0.6 s after it's set; then Mission 12's light at 4x there (its flash at ~1-1.8 s). The camera re-aimed before
-- each picture (a cloud light took the view back to the plane in runs 41 and 44).
SUITES.cloudlit3 = function()
    intoRun()
    local CLT = { t0 = 0 }
    local BPP = "/Game/Blueprints/Cloudly/CloudLight/"
    A.do_(function()
        local S = (((CFG.specials or {}).fleet or {}).sky or {}).storm
        if type(S) == "table" and type(S.lightning) == "table" then S.lightning.enabled = false end
        if tostring(ST.conf.night or "1") == "1" and IFSKY and IFSKY.step then IFSKY.step(3) end
    end)
    A.wait(12)
    local function g(v) if type(v) ~= "number" then return "?" end; return string.format("%.4g", v) end
    local function rd(tag)
        local V = SKY and SKY.viewCached and SKY.viewCached(os.clock(), nil)
        if not V then return end
        local use, drawn = "?", "?"
        pcall(function() use = tostring(V.actor.bUseEffectLight) end)
        for _, r in ipairs(V.rend or {}) do
            local n = 0
            pcall(function()
                r.obj.Data.SkyParamsRO:ForEach(function(_, e)
                    n = n + 1
                    if n == 1 then
                        local t = e:get().EffectLightTransientParams
                        drawn = string.format("%s at %.1f %.1f %.1f km r %s", g(t.LightBrightness), t.WorldPosition.X / 100000,
                            t.WorldPosition.Y / 100000, t.WorldPosition.Z / 100000, g(t.AttenuationRadius))
                    end
                end)
            end)
        end
        ST.info(string.format("cl3 %s: use %s | drawn %s", tag, use, drawn))
    end
    local function spawnCL(name, at)
        local cls = loadObject(BPP .. name .. "." .. name .. "_C")
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not (cls and gs and valid(gs)) then return nil, "no class or GameplayStatics" end
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
        if not okB or x == nil or not valid(x) then return nil, "no actor" end
        pcall(function() x.WorldPosition = { X = at.X, Y = at.Y, Z = at.Z } end)
        local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
        if not okF or a == nil or not valid(a) then return nil, "its spawn didn't finish" end
        return a, "up"
    end
    local function aim() if CLT.eye and CLT.tgt then ST.look(CLT.eye, CLT.tgt, 60) end end
    local SEQ = { { 0, 500000 }, { 40000, 500000 }, { 0, 500000 }, { 400000, 500000 }, { 4000000, 5000000 }, { 0, 500000 } }
    for v, view in ipairs({ { "over", 5000 }, { "under", -1800 } }) do
        A.do_(function()
            local pl = ST.plane()
            if not pl then ST.info("cl3: no plane"); return end
            CLT.tgt = ST.frame(pl, 600000, 0, 0)
            CLT.eye = ST.frame(pl, 0, 0, view[2] * 100)
            if v == 1 then
                local a, why = spawnCL("BP_CloudLight_Base", CLT.tgt)
                CLT.a = a
                if a then
                    pcall(function() a.LightFalloffExponent = 4 end)
                    pcall(function() a.LightColor = { R = 215, G = 225, B = 255, A = 255 } end)
                    pcall(function() a.bUseInverseSquaredFalloff = false end)
                end
                ST.info("cl3: the bare light in the layer 6 km ahead of your plane: " .. why)
            elseif CLT.a and valid(CLT.a) then
                pcall(function() CLT.a.WorldPosition = { X = CLT.tgt.X, Y = CLT.tgt.Y, Z = CLT.tgt.Z } end)
                pcall(function() CLT.a:K2_SetActorLocation(CLT.tgt, false, {}, true) end)
            end
            local ok, why = ST.look(CLT.eye, CLT.tgt, 60)
            ST.info(string.format("cl3 %s: a still camera %.1f km %s your plane, on the light's spot: %s", view[1],
                math.abs(view[2]) / 1000, view[2] > 0 and "over" or "under", tostring(why)))
        end)
        A.wait(2.5)
        for i, k in ipairs(SEQ) do
            A.do_(function()
                if CLT.a and valid(CLT.a) then
                    pcall(function() CLT.a.LightBrightness = k[1] end)
                    pcall(function() CLT.a.AttenuationRadius = k[2] end)
                end
            end)
            A.wait(0.6)
            A.do_(function() aim(); rd(string.format("%s %d set %d", view[1], i, k[1])) end)
            A.do_(function() ST.shot(string.format("cl3_%s_%d_%d", view[1], i, k[1])) end)
            A.wait(0.4)
        end
    end
    A.do_(function() if CLT.a and valid(CLT.a) then pcall(function() CLT.a:K2_DestroyActor() end) end; CLT.a = nil end)
    -- Mission 12's light at 4x, from over the layer again
    A.do_(function()
        local pl = ST.plane()
        if not pl then return end
        CLT.tgt = ST.frame(pl, 600000, 0, 0)
        CLT.eye = ST.frame(pl, 0, 0, 500000)
        ST.look(CLT.eye, CLT.tgt, 60)
    end)
    A.wait(2.5)
    A.do_(function() aim(); ST.shot("cl3_m12_0_before") end)
    A.wait(0.4)
    A.do_(function()
        local a, why = spawnCL("BP_CloudLight_Ms012_PodargeDead", CLT.tgt)
        if a then pcall(function() a.CustomTimeDilation = 4 end) end
        CLT.a, CLT.t0 = a, os.clock()
        aim()
        ST.info("cl3 m12: Mission 12's light at 4x at the spot: " .. why)
    end)
    for i = 1, 10 do
        A.do_(function()
            aim()
            rd(string.format("m12 +%.2f s", os.clock() - CLT.t0))
            if i >= 3 and i <= 8 then ST.shot(string.format("cl3_m12_%d", i)) end
        end)
        A.wait(0.25)
    end
    A.do_(function() ST.lookBack() end)
end
-- (2026-11-17) cloudlit4: run 67's still cameras swung white / black with each change of the light (the eye adaptation:
-- off -> a white frame, 40k -> a black one), so nothing local could be read. Here the eye adaptation frozen
-- (ShowFlag.EyeAdaptation 0: a fixed exposure from the night's min / max; put back after) and two still cameras under
-- the storm's cloud base (1.8 km under your plane; 6 km and 12 km from the light's spot in the layer): off, 40k, off,
-- 400k, off, 4M (radius 50 km), off; then Mission 12's light at 4x from the near one.
SUITES.cloudlit4 = function()
    intoRun()
    local CLT = { t0 = 0 }
    local BPP = "/Game/Blueprints/Cloudly/CloudLight/"
    local function cmd(c)
        local ks, pc = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"), ST.pc()
        local ok = valid(ks) and pc and pcall(function() ks:ExecuteConsoleCommand(pc, c, pc) end)
        ST.info("cl4: console `" .. c .. "`: " .. tostring(ok))
    end
    A.do_(function()
        local S = (((CFG.specials or {}).fleet or {}).sky or {}).storm
        if type(S) == "table" and type(S.lightning) == "table" then S.lightning.enabled = false end
        if tostring(ST.conf.night or "1") == "1" and IFSKY and IFSKY.step then IFSKY.step(3) end
    end)
    A.wait(12)
    local function g(v) if type(v) ~= "number" then return "?" end; return string.format("%.4g", v) end
    local function rd(tag)
        local V = SKY and SKY.viewCached and SKY.viewCached(os.clock(), nil)
        if not V then return end
        local drawn = "?"
        for _, r in ipairs(V.rend or {}) do
            local n = 0
            pcall(function()
                r.obj.Data.SkyParamsRO:ForEach(function(_, e)
                    n = n + 1
                    if n == 1 then local t = e:get().EffectLightTransientParams; drawn = g(t.LightBrightness) .. " r " .. g(t.AttenuationRadius) end
                end)
            end)
        end
        ST.info(string.format("cl4 %s: drawn %s", tag, drawn))
    end
    local function spawnCL(name, at)
        local cls = loadObject(BPP .. name .. "." .. name .. "_C")
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not (cls and gs and valid(gs)) then return nil, "no class or GameplayStatics" end
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
        if not okB or x == nil or not valid(x) then return nil, "no actor" end
        pcall(function() x.WorldPosition = { X = at.X, Y = at.Y, Z = at.Z } end)
        local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
        if not okF or a == nil or not valid(a) then return nil, "its spawn didn't finish" end
        return a, "up"
    end
    local function aim() if CLT.eye and CLT.tgt then ST.look(CLT.eye, CLT.tgt, 60) end end
    A.do_(function()
        local pl = ST.plane()
        if not pl then ST.info("cl4: no plane"); return end
        CLT.tgt = ST.frame(pl, 600000, 0, 0)
        CLT.base = ST.frame(pl, 0, 0, -180000)
        CLT.F = pl:GetActorForwardVector()
        local a, why = spawnCL("BP_CloudLight_Base", CLT.tgt)
        CLT.a = a
        if a then
            pcall(function() a.LightFalloffExponent = 4 end)
            pcall(function() a.LightColor = { R = 215, G = 225, B = 255, A = 255 } end)
            pcall(function() a.bUseInverseSquaredFalloff = false end)
        end
        ST.info("cl4: the bare light in the layer 6 km ahead of your plane: " .. why)
        cmd("ShowFlag.EyeAdaptation 0")
    end)
    local SEQ = { { 0, 500000 }, { 40000, 500000 }, { 0, 500000 }, { 400000, 500000 }, { 0, 500000 }, { 4000000, 5000000 }, { 0, 500000 } }
    for v, back in ipairs({ 0, 600000 }) do
        A.do_(function()
            if not (CLT.base and CLT.F) then return end
            CLT.eye = { X = CLT.base.X - CLT.F.X * back, Y = CLT.base.Y - CLT.F.Y * back, Z = CLT.base.Z }
            aim()
        end)
        A.wait(1.5)
        for i, k in ipairs(SEQ) do
            A.do_(function()
                if CLT.a and valid(CLT.a) then
                    pcall(function() CLT.a.LightBrightness = k[1] end)
                    pcall(function() CLT.a.AttenuationRadius = k[2] end)
                end
            end)
            A.wait(0.6)
            A.do_(function() aim(); rd(string.format("view %d step %d set %d", v, i, k[1])) end)
            A.do_(function() ST.shot(string.format("cl4_v%d_%d_%d", v, i, k[1])) end)
            A.wait(0.4)
        end
    end
    A.do_(function() if CLT.a and valid(CLT.a) then pcall(function() CLT.a:K2_DestroyActor() end) end; CLT.a = nil end)
    A.do_(function()
        if not (CLT.base and CLT.F) then return end
        CLT.eye = { X = CLT.base.X, Y = CLT.base.Y, Z = CLT.base.Z }
        aim()
    end)
    A.wait(1.5)
    A.do_(function() aim(); ST.shot("cl4_m12_0_before") end)
    A.wait(0.4)
    A.do_(function()
        local a, why = spawnCL("BP_CloudLight_Ms012_PodargeDead", CLT.tgt)
        if a then pcall(function() a.CustomTimeDilation = 4 end) end
        CLT.a, CLT.t0 = a, os.clock()
        aim()
        ST.info("cl4 m12: Mission 12's light at 4x at the spot: " .. why)
    end)
    for i = 1, 10 do
        A.do_(function()
            aim()
            rd(string.format("m12 +%.2f s", os.clock() - CLT.t0))
            if i >= 3 and i <= 8 then ST.shot(string.format("cl4_m12_%d", i)) end
        end)
        A.wait(0.25)
    end
    A.do_(function() cmd("ShowFlag.EyeAdaptation 2"); ST.lookBack() end)
end
-- (2026-11-17) 0.74.89's cloud flashes (the user: "Yeah test them"): the fleet's storm lights its clouds with Survival's own
-- cloud light at some strikes (hard rule 70). The light up under the fade, the first cloud flash; pictures from your view,
-- then from a still camera under the cloud base, then cloud flashes put in that camera's view (the storm's own paused).
SUITES.cloudstorm = function()
    intoRun()
    local CS = {}
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil and THUNDER.cloudReady ~= nil, "the storm's cloud flashes are in this build") then return "abort" end
        ST.marks.s0 = ST.n
        IFSKY.step(3)
    end)
    A.log_("fleet storm: warm%-up under the black", 15, "s0", false, function(l)
        ST.check(l ~= nil and l:find("its cloud light", 1, true) ~= nil, "the bolts, the rain and its cloud light warmed up under the fade", l)
    end)
    A.log_("cloud lightning %(the fleet's storm%): a cloud flash", 20, "s0", false, function(l)
        ST.check(l ~= nil, "the storm's first cloud flash", l)
    end)
    for i = 1, 16 do
        A.wait(0.6)
        A.do_(function() ST.shot(string.format("cs_you_%02d", i)) end)
    end
    local eye = { X = 1610476, Y = -436143, Z = 120000 }
    local tgt = { X = eye.X - 1000000, Y = eye.Y - 300000, Z = 300000 }
    A.do_(function() ST.look(eye, tgt, 75) end)
    for i = 1, 12 do
        A.wait(0.6)
        A.do_(function() ST.look(eye, tgt, 75); ST.shot(string.format("cs_under_%02d", i)) end)
    end
    -- cloud flashes put in the still camera's view, 6 km out in the cloud layer
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    A.do_(function()
        local L = cfg()
        CS.was = L.cloud and L.cloud.enabled
        if L.cloud then L.cloud.enabled = false end
    end)
    A.wait(2.5)
    for k, b in ipairs({ 200000, 400000 }) do
        local at = { X = eye.X + (tgt.X - eye.X) * 0.6, Y = eye.Y + (tgt.Y - eye.Y) * 0.6, Z = 300000 }
        A.do_(function() ST.look(eye, tgt, 75); ST.shot(string.format("cs_put_%d_0_before", k)) end)
        A.wait(0.3)
        A.do_(function()
            local L = cfg()
            local c = {}
            for key, v in pairs(L.cloud or {}) do c[key] = v end
            c.brightness, c.steps = b, { 1, 1, 1, 1, 1, 0.3, 0 }
            local ok, what = pcall(THUNDER.cloudFlash, at, "effect", "the test", c)
            ST.info(string.format("cloudstorm: a cloud flash put 6 km out in the camera's view at %d: %s", b, ok and tostring(what) or ("error " .. tostring(what))))
        end)
        for j, w in ipairs({ 0.3, 0.4, 0.5, 0.7, 1.0 }) do
            A.wait(w)
            A.do_(function() ST.look(eye, tgt, 75); ST.shot(string.format("cs_put_%d_%d", k, j)) end)
        end
        A.wait(1.5)
    end
    A.do_(function()
        local L = cfg()
        if L.cloud then L.cloud.enabled = CS.was end
        ST.lookBack()
        local n = 0
        for i = ST.marks.s0 or 1, ST.n do
            local l = ST.lines and ST.lines[i]
            if l and l:find("a cloud flash (", 1, true) then n = n + 1 end
        end
        ST.info(string.format("cloudstorm: %d cloud flashes logged (of the first 60 lightning lines)", n))
    end)
end
-- (2026-11-17) cloudview: run 69's storm flashes (150k-400k, 2-25 km round the centres) showed nothing clear in your view
-- (auto exposure on, as you play). Here, from your own view, the storm's own cloud flashes paused: a flash put in your
-- camera's view (4 km or 10 km ahead, at your height, in the layer you fly in), held ~2 s, pictured before / at 0.3, 0.8,
-- 1.5 s / after; brightness 400k and 1M (its cap), radius 5 and 10 km.
SUITES.cloudview = function()
    intoRun()
    local CV = {}
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil and THUNDER.cloudReady ~= nil, "the storm's cloud flashes are in this build") then return "abort" end
        ST.marks.s0 = ST.n
        IFSKY.step(3)
    end)
    A.log_("fleet storm: warm%-up under the black", 15, "s0", false, function(l)
        ST.check(l ~= nil and l:find("its cloud light", 1, true) ~= nil, "its cloud light up under the fade", l)
        local L = cfg()
        CV.was = L.cloud and L.cloud.enabled
        if L.cloud then L.cloud.enabled = false end
    end)
    A.wait(4)
    local TRY = { { 4, 400000, 5000 }, { 4, 1000000, 5000 }, { 4, 400000, 10000 }, { 4, 1000000, 10000 }, { 10, 1000000, 10000 } }
    for k, t in ipairs(TRY) do
        local tag = string.format("cv_%d_%dkm_%dk_r%d", k, t[1], t[2] / 1000, t[3] / 1000)
        A.do_(function() ST.shot(tag .. "_0_before") end)
        A.wait(0.3)
        A.do_(function()
            local pcm, L, R
            pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
            pcall(function() R = pcm:GetCameraRotation() end)
            if not (L and R) then ST.info(tag .. ": no camera"); return end
            local yw = math.rad(R.Yaw or 0)
            local at = { X = L.X + math.cos(yw) * t[1] * 100000, Y = L.Y + math.sin(yw) * t[1] * 100000, Z = L.Z + 20000 }
            local c = {}
            for key, v in pairs(cfg().cloud or {}) do c[key] = v end
            c.brightness, c.radius_m, c.steps = t[2], t[3], { 1, 1, 1, 1, 1, 1, 1, 1, 0 }
            local ok, what = pcall(THUNDER.cloudFlash, at, "effect", "the test", c)
            ST.info(string.format("%s: a cloud flash %d km ahead of your camera, 200 m over it: %s", tag, t[1], ok and tostring(what) or ("error " .. tostring(what))))
        end)
        for j, w in ipairs({ 0.3, 0.5, 0.7 }) do
            A.wait(w)
            A.do_(function() ST.shot(string.format("%s_%d_on", tag, j)) end)
        end
        A.wait(2.2)
        A.do_(function() ST.shot(tag .. "_4_after") end)
        A.wait(1)
    end
    A.do_(function() local L = cfg(); if L.cloud then L.cloud.enabled = CV.was end end)
end
-- (2026-11-17) 0.74.90's Ctrl+S (the user: "yeah make a test key that goes into night storm"): pressed, the fleet's night
-- storm comes under its fade with its cloud light and flashes; again, it clears and the round's own sky is back; a third
-- time, the storm again. Pictures from your view at each.
-- (2026-11-17) restart129: 0.74.129, the user's crash of 0.74.128 (a pause-menu restart in round 30, the storm again 8 s
-- on, AceCombat8.exe+0x5761b98) and the cloud burst dimmed (burst.py DIM 300). Ctrl+S: the storm in, its flashes, pictures
-- of the bursts; then a mission restart as sv_main.lua's restart check makes it (D.restarted, levelTick -1: the level-load
-- reset; the self-test can't press the pause menu's RESTART, so the mission isn't reloaded); the restart's drop line, the
-- storm's layout put back; then Ctrl+S again: the storm in again, 60 s of strikes, the strike light and the bursts, no crash.
SUITES.restart129 = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSKY.storm ~= nil, "the fleet's night storm is in this build") then return "abort" end
        ST.check(type(levelRestartDrop) == "function" and type(RESTART_DROPS) == "table" and RESTART_DROPS["fleet storm"] == true,
            "levelRestartDrop and the fleet's RESTART_DROPS are in")
        ST.marks.r1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 20, "r1", true, function(l) ST.check(l ~= nil, "Ctrl+S: the storm in", l) end)
    A.log_("fleet storm: flash 1 (", 25, "r1", true, function(l) ST.check(l ~= nil, "its cloud flashes", l) end)
    for i = 1, 10 do
        A.wait(1.3)
        A.do_(function() ST.shot(string.format("rs_burst_%02d", i)) end)
    end
    A.do_(function()
        ST.check(IFSKY.storm().on == true, "the storm on before the restart", tostring(IFSKY.storm().flashes) .. " flashes")
        ST.marks.r2 = ST.n
        D.restarted = true                                -- (as sv_main.lua's restart check: the level-load reset next tick)
        levelTick = -1
        ST.info("restart: D.restarted, levelTick -1 (the reset as after a pause-menu RESTART)")
    end)
    A.log_("restart: the mission's reload took", 10, "r2", true, function(l)
        ST.check(l ~= nil and l:find("fleet storm", 1, true) ~= nil and l:find("put back first: fleet storm", 1, true) ~= nil,
            "the restart dropped the fleet's parts, the storm put back first", l)
    end)
    A.log_("the mission restarted", 10, "r2", true, function(l) ST.check(l ~= nil, "the storm's layout back to the level's", l) end)
    A.wait(6)
    A.do_(function()
        ST.check(D ~= nil and IFSKY.storm().on == false, "a new run, the storm off", "D " .. tostring(D ~= nil))
        ST.check(IFLEET == nil or IFLEET.cur == nil, "no old fleet kept")
        ST.shot("rs_after_restart")
        ST.marks.r3 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 20, "r3", true, function(l) ST.check(l ~= nil, "Ctrl+S after the restart: the storm in again", l) end)
    A.log_("strike light 1:", 30, "r3", true, function(l) ST.check(l ~= nil, "a strike light after the restart (where it crashed)", l) end)
    for i = 1, 8 do
        A.wait(6)
        A.do_(function() ST.shot(string.format("rs_again_%02d", i)) end)
    end
    A.do_(function()
        local s = IFSKY.storm()
        ST.check(s.on == true and (s.flashes or 0) > 10, "60 s of the storm after the restart, no crash", tostring(s.flashes) .. " flashes")
        local prob = ST.findLog("sunk (its hull gone)", ST.marks.r2, true)
        ST.check(prob == nil, "no ghost ship paid as sunk after the restart")
    end)
end
-- (2026-11-17) whiteout: what whites the clouds out in the storm (the user's picture of 0.74.128, again at 0.74.129 with
-- the burst at 300)? Ctrl+S, the storm in, 24 pictures over ~36 s; run with config_whiteout_nolight (the strike light
-- off) and config_whiteout_noburst (the cloud burst off: the stock glow), the pictures' white compared.
SUITES.whiteout = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSKY.storm ~= nil, "the fleet's night storm is in this build") then return "abort" end
        local lt = ((((CFG.specials.fleet or {}).sky or {}).storm or {}).lightning or {})
        local w = tostring(ST.conf.whiteout or "")
        if w == "nolight" and lt.plane_light then lt.plane_light.enabled = false end
        if w == "noburst" and lt.bolt_glow then lt.bolt_glow.flash = {} end
        local sc = ((((CFG.specials.fleet or {}).sky or {}).storm or {}).cells)
        if w == "nocells" and sc then sc.enabled = false end   -- (the 19 cells and the bolts' glow / burst)
        local bg = sc and sc.bolt_glow
        if w == "noburst2" and bg then bg.flash = {} end         -- (the stock glow in its place)
        if w == "noglow" and bg then bg.enabled = false end
        if w == "nobolts" then lt.bolts = nil end
        ST.info("whiteout: " .. w)
        ST.info("plane_light enabled " .. tostring((lt.plane_light or {}).enabled) .. "; bolt_glow.flash " ..
            tostring(type((lt.bolt_glow or {}).flash) == "table" and #lt.bolt_glow.flash or "none"))
        ST.marks.w1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 20, "w1", true, function(l) ST.check(l ~= nil, "Ctrl+S: the storm in", l) end)
    A.wait(4)
    for i = 1, 24 do
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("wo_%02d", i)) end)
    end
    A.do_(function() ST.check(IFSKY.storm().on == true, "the storm still on", tostring(IFSKY.storm().flashes) .. " flashes") end)
end
-- (2026-11-17) phase2: round 30's phase 2 (sv_fleet_round.lua p2Tick, 0.74.131: the user, "GEOFON falls, Tanacorn rises",
-- beaten "All her guns down"). fleet30's way into round 30; then GEOFON's health taken down in steps (ModifyHealth on its
-- hull, as the players' hits): its stage 1 at 66 %, stage 2 at 33 %, the hold at 15 %, the break at 3 % (the V, paid as
-- sunk); pictures of each; the TANACORN spawned in the gap as it splits (no fade), her rise; then her guns finished one by one (her
-- live watch's parts, finishUnpaid): paid, the half line, all down: beaten, her reward; the rest of the fleet and the
-- round's aircraft finished: the win.
SUITES.phase2 = function()
    intoRun()
    local C = {}
    local function geo() local F = IFLEET and IFLEET.cur; return F and F.ships[1] end
    local function cut(to)                               -- GEOFON's health to share `to` of its maximum (ModifyHealth, health)
        local g = geo()
        if not (g and g.hull) then return "no GEOFON" end
        local o = g.hull.obj
        local h, mx
        pcall(function() h = o.HealthInternal; mx = o.MaxHealth * 10 end)
        if not (h and mx and mx > 0) then return "its health unread" end
        local amount = (h - to * mx) / 10
        if amount <= 0 then return string.format("already at %.0f %%", 100 * h / mx) end
        local ok = pcall(function() o:ModifyHealth(-amount, nil, true) end)
        local h1
        pcall(function() h1 = o.HealthInternal end)
        return string.format("%.0f %% -> %s (ModifyHealth %s)", 100 * h / mx, h1 and string.format("%.1f %%", 100 * h1 / mx) or "?",
            ok and "ok" or "FAILED")
    end
    A.do_(function()
        if not ST.check(IFROUND ~= nil and GEO ~= nil and GEO.attach ~= nil and TANI ~= nil and TANI.roundRise ~= nil,
            "round 30's phase 2 is in this build") then return "abort" end
        ST.marks.p0 = ST.n
        D.round = 29
        C.cr = RUN.credits
        ST.info("phase2: the run set to round 29's break (credits " .. tostring(RUN.credits) .. ")")
    end)
    A.log_("fleet round: round 30: the fleet's 15 ships coming", 120, "p0", true, function(l)
        if not ST.check(l ~= nil, "round 30 started", l) then return "abort" end
    end)
    A.log_("15 of 15 ships up", 70, "p0", true, function(l) ST.check(l ~= nil, "the fleet up after the surfacing", l) end)
    A.log_("fleet round: phase 2: GEOFON watched", 20, "p0", true, function(l) ST.check(l ~= nil, "phase 2 watches GEOFON", l) end)
    A.wait(12)                                            -- ((0.74.147) the Tanager's lines come 10 s after the sighting)
    A.do_(function() ST.marks.p1 = ST.n; ST.info("phase2: GEOFON " .. cut(0.6)) end)
    A.log_("geofon: stage 1 at 66", 10, "p1", true, function(l) ST.check(l ~= nil, "GEOFON's stage 1 (fires, smoke, list)", l) end)
    A.wait(2)
    A.do_(function() ST.shot("p2_stage1"); ST.near(2500, "stage1") end)
    A.do_(function() ST.marks.p2 = ST.n; ST.info("phase2: GEOFON " .. cut(0.3)) end)
    A.log_("geofon: stage 2 at 33", 10, "p2", true, function(l) ST.check(l ~= nil, "GEOFON's stage 2 (more fires, its _DAM look)", l) end)
    A.wait(2)
    A.do_(function() ST.shot("p2_stage2") end)
    A.do_(function() ST.marks.p3 = ST.n; ST.info("phase2: GEOFON " .. cut(0.10)) end)
    A.log_("fleet round: phase 2: GEOFON at", 10, "p3", true, function(l) ST.check(l ~= nil and l:find("SetMinHealth", 1, true) and
        not l:find("FAILED", 1, true), "GEOFON held at its break (SetMinHealth)", l) end)
    A.do_(function() ST.marks.p4 = ST.n; ST.info("phase2: GEOFON a killing blow: " .. cut(0.0)) end)
    A.log_("fleet round: phase 2: GEOFON at its break", 10, "p4", true, function(l)
        if not ST.check(l ~= nil, "GEOFON held whole at its break (not sunk outright)", l) then return "abort" end
    end)
    A.log_("fleet round: GEOFON (ford) sunk", 5, "p4", true, function(l) ST.check(l ~= nil, "GEOFON paid as sunk", l) end)
    A.log_("fleet round: phase 2: the TANACORN under GEOFON", 5, "p4", true, function(l)
        if not ST.check(l ~= nil and l:find("spawned, rising", 1, true) ~= nil, "the TANACORN spawned in the gap", l) then return "abort" end
    end)
    A.log_("fleet round: phase 2: her rise released", 8, "p4", true, function(l)   -- ((0.74.148) held through her spawn's hitch)
        ST.check(l ~= nil and not l:find("NOT", 1, true), "her rise released after her spawn's hitch", l)
    end)
    A.log_("the rise's find at once after her spawn", 10, "p4", true, function(l)
        ST.check(l ~= nil and l:find("her state hold", 1, true) ~= nil, "found and put under the sea in her spawn's call (no tick on the surface)", l)
    end)
    for i = 1, 4 do                                   -- (her bow breaks the surface ~2.3 s in: pictures through it)
        A.wait(0.8)
        A.do_(function() ST.shot(string.format("p2_breach_%d", i)) end)
    end
    A.log_("fleet round: phase 2: GEOFON split in two by her bow", 8, "p4", true, function(l)
        ST.check(l ~= nil and l:find("its V rearing", 1, true) ~= nil, "GEOFON split by her bow's breach (its V rearing)", l)
    end)
    A.log_("cine: cinematic of 12 keys", 5, "p4", true, function(l)
        ST.check(l ~= nil and l:find("a cut", 1, true) ~= nil, "her rise's own shot list (12 keys, its cuts)", l)
    end)
    A.log_("cine: cinematic of 12 keys", 5, "p4", true, function(l)   -- ((0.74.157) no camera that kept looking the wrong way)
        local off = l and tonumber(l:match("read back worst ([%d%.]+) deg off"))
        ST.check(off ~= nil and off <= 10, "every camera aimed where its key says (read back within 10 deg)", tostring(off))
    end)
    A.log_("geofon: break look %+%d+ s: bow .-pitch [+-]?[1-9]", 8, "p4", false, function(l)
        ST.check(l ~= nil, "GEOFON's V reared (its halves' pitch read back off 0)", l)
    end)
    A.do_(function() local g = geo(); C.g = g and g.hull and g.hull.obj or nil; ST.info("phase2: GEOFON's hull kept for its pictures: " .. tostring(C.g ~= nil)) end)
    for i = 1, 12 do
        A.wait(1.0)
        A.do_(function() ST.shot(string.format("p2_rise_%02d", i)) end)
        if i % 4 == 0 then                            -- (GEOFON's halves from 700 m off its starboard side, 60 m up: aimed and shot
            A.wait(0.6)                                -- in one step, the rise's cinematic takes the view back each tick)
            A.do_(function()
                if not (C.g and valid(C.g)) then ST.info("phase2: GEOFON's hull gone: no picture"); return end
                local okA, at = pcall(ST.frame, C.g, -8000, 70000, 6000)
                local okL, look = pcall(ST.frame, C.g, 0, 0, 1500)
                if okA and okL and ST.look(at, look, 45) then ST.shot(string.format("p2_geofon_%02d", i)) end
            end)
        end
    end
    A.do_(function() ST.lookBack() end)
    A.log_("cine: beat 4 at", 20, "p4", true, function(l)
        ST.check(l ~= nil and l:find("THE TANACORN", 1, true) ~= nil, "her title card on its beat", l)
    end)
    A.log_("fleet round: phase 2: the TANACORN up and fighting", 40, "p4", true, function(l)
        if not ST.check(l ~= nil, "her rise over: fighting", l) then return "abort" end
    end)
    A.log_("held while she rises", 2, "p4", true, function(l)   -- ((0.74.145) her railguns wait for her rise to end)
        ST.check(l ~= nil, "her railguns held through her rise", l)
    end)
    A.wait(2)
    A.do_(function()
        ST.shot("p2_fight")
        local up, of = TANI.livePartsUp()
        ST.check(up ~= nil and of ~= nil and of > 0, "her parts counted", string.format("%s of %s up", tostring(up), tostring(of)))
        ST.info("phase2: the row: " .. tostring(IFROUND.row(D.special, {})))
        ST.marks.p5 = ST.n
        local seen, k = TANI.liveSeen() or {}, 0       -- ((0.74.157) 22 of 35 first (past phase2_share 0.6), never the railcannon
        for s, e in pairs(seen) do
            if s ~= "RAILCANNON" and liveAddr(e.o) == e.a and nameOf(e.o) == e.name and k < 22 then
                if pcall(finishUnpaid, e.o) then k = k + 1 end
            end
        end
        C.firstK = k
        ST.info("phase2: " .. k .. " of her guns finished (the railcannon kept)")
    end)
    A.log_("fleet round: phase 2: %d+ of her guns shot down", 6, "p5", false, function(l) ST.check(l ~= nil, "her guns paid as they go down", l) end)
    A.log_("fleet round: phase 2: her phase 2 at", 10, "p5", true, function(l)   -- ((0.74.156) her phases)
        ST.check(l ~= nil and l:find("started", 1, true) ~= nil, "her phase 2 (22 of 35 down): the railcannon's cycle started", l)
    end)
    A.log_("tanicorn rc: .-charg", 40, "p5", false, function(l) ST.check(l ~= nil, "her railcannon charging at the airfield", l) end)
    A.do_(function()
        ST.shot("p2_railcannon")
        ST.marks.p6 = ST.n
        local e = (TANI.liveSeen() or {})["RAILCANNON"]
        local ok = e and liveAddr(e.o) == e.a and nameOf(e.o) == e.name and pcall(finishUnpaid, e.o)
        ST.info("phase2: her railcannon shot down: " .. tostring(ok))
    end)
    A.log_("fleet round: phase 2: her core open", 15, "p6", true, function(l)
        ST.check(l ~= nil and l:find("SetMinHealth", 1, true) ~= nil and l:find("railcannon", 1, true) ~= nil,
            "her core open by her railcannon's loss: armour off, health held", l)
    end)
    A.wait(2)
    A.do_(function()
        ST.shot("p2_core")
        ST.info("phase2: the row: " .. tostring(IFROUND.row(D.special, {})))
        local o = TANI.liveHull and TANI.liveHull()
        if not o then ST.info("phase2: no hull for the core"); return end
        local h; pcall(function() h = o.HealthInternal end)
        local ok = pcall(function() o:ModifyHealth(-((h or 1e6) / 10 + 1000), nil, true) end)
        local h1; pcall(function() h1 = o.HealthInternal end)
        ST.info(string.format("phase2: her core hit: %s -> %s (%s)", tostring(h), tostring(h1), ok and "ModifyHealth ok" or "FAILED"))
    end)
    A.log_("fleet round: phase 2: the TANACORN beaten", 15, "p5", true, function(l)
        ST.check(l ~= nil and l:find("core destroyed", 1, true) ~= nil, "her core destroyed: beaten, her reward", l)
    end)
    A.wait(3)
    A.do_(function()
        ST.shot("p2_beaten")
        local F = IFLEET and IFLEET.cur
        local k = 0
        for i = 2, #(F and F.ships or {}) do
            local sh = F.ships[i]
            if sh.hull then if pcall(finishUnpaid, sh.hull.obj) then k = k + 1 end end
        end
        for _, pl in ipairs(planes or {}) do
            if pl.unit and D.up and D.up[pl.unit] and pl.obj then pcall(finishUnpaid, pl.obj) end
        end
        ST.marks.p7 = ST.n
        ST.info("phase2: the rest of the fleet finished: " .. k)
    end)
    A.log_("fleet round: won at", 60, "p7", true, function(l) ST.check(l ~= nil, "won after her", l) end)
    A.log_("fleet round: crew: v6157_6001_alt1", 5, "p0", true, function(l)   -- ((0.74.153) the Alicorn crew's voices)
        ST.check(l ~= nil, "the crew: Salvation is nigh at the sighting", l)
    end)
    A.log_("fleet round: crew: v6349_6001", 5, "p0", true, function(l) ST.check(l ~= nil, "the crew: the oath at the split", l) end)
    A.log_("subs: VALKA: I feel its presence close", 5, "p0", true, function(l)   -- ((0.74.146) Audrey and Valka)
        ST.check(l ~= nil, "Audrey and Valka on the missing Tanager", l)
    end)
    A.log_("subs: VALKA: Stop looking for the Tanager on the water", 5, "p0", true, function(l)   -- ((0.74.158) her hints)
        ST.check(l ~= nil, "Valka at GEOFON's stage 1: look under it", l)
    end)
    A.log_("subs: VALKA: The carrier's hurting her", 5, "p0", true, function(l) ST.check(l ~= nil, "Valka at GEOFON's stage 2", l) end)
    A.log_("subs: INTERCEPT:", 1, "p0", true, function(l)  -- ((0.74.159) the crew heard, never subtitled)
        ST.check(l == nil, "no subtitle for Torres or the crew", l)
    end)
    A.log_("tanicorn: sink (", 5, "p5", true, function(l) ST.check(l ~= nil, "her death: her sinking started", l) end)
    for i = 1, 3 do
        A.wait(4)
        A.do_(function() ST.shot(string.format("p2_sink_%d", i)) end)
    end
    A.log_("tanicorn: sink over", 50, "p5", true, function(l)
        ST.check(l ~= nil and l:find("down (", 1, true) ~= nil, "she went under and her hull was finished off", l)
    end)
    A.do_(function()
        ST.shot("p2_won")
        ST.info(string.format("phase2: credits %s -> %s", tostring(C.cr), tostring(RUN.credits)))
        ST.check(RUN.credits - (C.cr or 0) >= 50000 + 60000, "paid: the fleet's win (50,000) and hers (60,000) at least")
    end)
    A.wait(2)
end
-- (2026-11-17) shell: WP13 (sv_fleet_round.lua shellTick, 0.74.137): round 30 as fleet30 starts it; the gun line set out to
-- 60 km so every ship in range is shelling at once; its callout, each ship at its gun line, salvos landing on the runway
-- (-3 each), the airfield's health falling; pictures of the runway from 1.5 km off; then the gun line back to 20 km.
SUITES.shell = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFROUND ~= nil and CFG.specials.fleet.shell ~= nil, "round 30's shelling is in this build") then return "abort" end
        ST.marks.s0 = ST.n
        D.round = 29
    end)
    A.log_("fleet round: round 30: the fleet's 15 ships coming", 120, "s0", true, function(l)
        if not ST.check(l ~= nil, "round 30 started", l) then return "abort" end
    end)
    A.log_("15 of 15 ships up", 70, "s0", true, function(l) ST.check(l ~= nil, "the fleet up after the surfacing", l) end)
    A.log_("fleet: scars: %d+ ships", 60, "s0", false, function(l)        -- ((0.74.140) WP8; the summary line)
        local k, set = nil, nil
        if l then k, set = l:match("scars: (%d+) ships, (%d+) of") end
        ST.check(k ~= nil and tonumber(k) >= 14 and tonumber(set) > 0, "every fleet ship scarred (its _DAM slots)", l)
    end)
    A.do_(function()
        local F = IFLEET and IFLEET.cur
        local g = F and F.ships[2] and F.ships[2].hull and F.ships[2].hull.obj
        if g and ST.look(ST.frame(g, 60000, 30000, 6000), ST.frame(g, 0, 0, 1500), 40) then ST.shot("scars_raven") end
    end)
    A.wait(2)
    A.do_(function()
        ST.lookBack()
        C.km = CFG.specials.fleet.shell.shell_km
        CFG.specials.fleet.shell.shell_km = 60
        C.hp = AF and AF.hp
        ST.marks.s1 = ST.n
        ST.info("shell: the gun line out to 60 km for the test; the airfield's health " .. tostring(C.hp))
    end)
    A.log_("fleet round: shelling: .- at the gun line", 15, "s1", false, function(l) ST.check(l ~= nil, "ships at the gun line, shelling", l) end)
    A.log_("fleet round: shelling: .-'s salvo landed: %-3 airfield", 40, "s1", false, function(l)
        ST.check(l ~= nil, "a salvo landed: -3 on the airfield", l)
    end)
    local rw = function() local f = CFG.specials.fleet.formation.runway_cm; return { X = f[1], Y = f[2], Z = 500 } end
    for i = 1, 4 do
        A.wait(4)
        A.do_(function()
            local p = rw()
            if ST.look({ X = p.X - 150000, Y = p.Y + 60000, Z = 30000 }, p, 50) then ST.shot(string.format("shell_runway_%d", i)) end
        end)
    end
    A.log_("fleet round: deck: launch 1 off GEOFON's bow", 40, "s0", true, function(l)   -- ((0.74.144) GEOFON's deck)
        ST.check(l ~= nil, "GEOFON launched a flight off its deck", l)
    end)
    A.wait(6)
    A.do_(function()
        ST.lookBack()
        local hp = AF and AF.hp
        ST.check(C.hp and hp and hp < C.hp, "the airfield's health fell under the shelling", string.format("%s -> %s", tostring(C.hp), tostring(hp)))
        CFG.specials.fleet.shell.shell_km = C.km
        ST.info("shell: the gun line back to " .. tostring(C.km) .. " km")
    end)
    A.wait(2)
end
SUITES.stormkey = function()
    intoRun()
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSKY.storm ~= nil, "the fleet's night storm is in this build") then return "abort" end
        ST.marks.k1 = ST.n
        ST.check(ST.press("S") == 1, "Ctrl+S is bound (one callback)")
    end)
    A.log_("fleet storm: the arc at step 3 now", 3, "k1", true, function(l) ST.check(l ~= nil, "Ctrl+S: the fleet's arc at its night", l) end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l) ST.check(l ~= nil, "the storm in under its fade", l) end)
    A.log_("a cloud flash (", 20, "k1", true, function(l) ST.check(l ~= nil, "its cloud flashes", l) end)
    for i = 1, 4 do
        A.wait(1)
        A.do_(function() ST.shot(string.format("sk_on_%d", i)) end)
    end
    A.do_(function()
        ST.check(IFSKY.storm().on == true, "IFSKY.storm(): on", tostring(IFSKY.storm().flashes) .. " flashes")
        ST.marks.k2 = ST.n
        ST.press("S")
    end)
    A.wait(0.2)
    A.do_(function() ST.shot("sk_leaving_1") end)        -- (0.74.90's run 72: the day here, a second before the fade)
    A.wait(0.5)
    A.do_(function() ST.shot("sk_leaving_2") end)
    A.log_("fleet storm: the arc at step nil now", 4, "k2", true, function(l)
        local i = select(2, ST.findLog("fleet storm: the arc at step nil now", ST.marks.k2, true))
        local f = select(2, ST.findLog("under a fade to black", ST.marks.k2, true))
        ST.check(l ~= nil and i ~= nil, "Ctrl+S again: the test's step off", l)
        ST.info("cleared: the step off at log line " .. tostring(i) .. ", the fade's line at " .. tostring(f))
    end)
    A.log_("fleet storm: cleared (", 15, "k2", true, function(l) ST.check(l ~= nil, "the storm cleared under its fade", l) end)
    A.wait(4)
    A.do_(function()
        ST.check(IFSKY.storm().on == false and IFSKY.k == nil, "IFSKY.storm(): off, no test step")
        ST.shot("sk_day")
    end)
    A.wait(1)
    A.do_(function()
        ST.marks.k3 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 15, "k3", true, function(l) ST.check(l ~= nil, "a third Ctrl+S: the storm in again", l) end)
    A.wait(3)
    A.do_(function() ST.shot("sk_again") end)
end
-- (2026-11-17) 0.74.92 (the user flying 0.74.91: "night time is too bright, also the sea is back to green again ... and
-- theres no spawning cloud lights or thunder"): Ctrl+S, the storm's warm-up with its thunder loaded, the first thunders
-- posted, pictures from your view (the night's look, the sea), Ctrl+J's four sounds, then a still camera under the cloud
-- base with a cloud flash put 6 km out in its view (the storm's own paused), under the night's capped exposure.
SUITES.storm92 = function()
    intoRun()
    local C = {}
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSKY.storm ~= nil, "the fleet's night storm is in this build") then return "abort" end
        ST.marks.k1 = ST.n
        ST.check(ST.press("S") == 1, "Ctrl+S is bound")
    end)
    A.log_("fleet storm: warm-up under the black", 6, "k1", true, function(l)
        ST.check(l ~= nil and l:find("its cloud light", 1, true) ~= nil and l:find("thunder 4 of 4 loaded", 1, true) ~= nil,
            "the warm-up: its cloud light, the 4 thunder sounds loaded", l)
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l) ST.check(l ~= nil, "the storm in under its fade", l) end)
    A.log_("fleet storm: thunder 1: ", 20, "k1", true, function(l)
        ST.check(l ~= nil and l:find("posted", 1, true) ~= nil, "the first thunder posted", l)
    end)
    for i = 1, 10 do
        A.wait(0.6)
        A.do_(function() ST.shot(string.format("s92_you_%02d", i)) end)
    end
    for i = 1, 4 do
        A.do_(function() ST.marks["j" .. i] = ST.n; ST.press("J") end)
        A.log_("fleet storm: Ctrl+J thunder " .. i .. " of 4", 3, "j" .. i, true, function(l)
            ST.check(l ~= nil and l:find("(posted;", 1, true) ~= nil, "Ctrl+J sound " .. i .. " posted", l)
        end)
        A.wait(1.5)
    end
    -- the still camera under the cloud base (run 68's), a flash put in its view, the night's own exposure (capped)
    A.do_(function()
        local L = cfg()
        C.was = L.cloud and L.cloud.enabled
        if L.cloud then L.cloud.enabled = false end
        local pl = ST.plane()
        if not pl then return end
        C.tgt = ST.frame(pl, 600000, 0, 0)
        C.eye = ST.frame(pl, 0, 0, -180000)
        ST.look(C.eye, C.tgt, 60)
    end)
    A.wait(3)
    A.do_(function() if C.eye then ST.look(C.eye, C.tgt, 60) end; ST.shot("s92_under_0_before") end)
    A.wait(0.3)
    A.do_(function()
        if not C.tgt then return end
        local c = {}
        for k, v in pairs(cfg().cloud or {}) do c[k] = v end
        c.brightness, c.steps = 300000, { 1, 1, 1, 1, 1, 1, 0 }
        local ok, what = pcall(THUNDER.cloudFlash, C.tgt, "effect", "the test", c)
        ST.info("storm92: a cloud flash put 6 km out in the camera's view: " .. (ok and tostring(what) or ("error " .. tostring(what))))
    end)
    for j, w in ipairs({ 0.3, 0.4, 0.5 }) do
        A.wait(w)
        A.do_(function() if C.eye then ST.look(C.eye, C.tgt, 60) end; ST.shot(string.format("s92_under_%d_on", j)) end)
    end
    A.wait(2.5)
    A.do_(function() if C.eye then ST.look(C.eye, C.tgt, 60) end; ST.shot("s92_under_4_after") end)
    A.do_(function()
        local L = cfg()
        if L.cloud then L.cloud.enabled = C.was end
        ST.lookBack()
        local th = 0
        for i = ST.marks.k1 or 1, ST.n do
            local l = ST.lines and ST.lines[i]
            if l and l:find("fleet storm: thunder ", 1, true) then th = th + 1 end
        end
        ST.info(string.format("storm92: %d thunder lines logged (the first 3 and any not posted)", th))
    end)
end
-- (2026-11-17) flash92: run 74's 300k flash showed nothing under the night's own exposure (run 68's 400k white was its
-- frozen exposure, ~16x brighter than the night's). The storm night (Ctrl+S), the still camera under the cloud base
-- (run 68's), the storm's own flashes paused: a flash 6 km out in its view at 1M, 2M, 4M, 8M (radius 5 km) and 2M at 10 km,
-- max_brightness lifted for the test; pictured before / at 0.4 and 0.9 s / after (the blackout run 68 saw at 4M, 50 km).
SUITES.flash92 = function()
    intoRun()
    local C = {}
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil and THUNDER.cloudFlash ~= nil, "the storm and its flashes are in this build") then return "abort" end
        ST.marks.k1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l)
        ST.check(l ~= nil, "the storm in", l)
        local L = cfg()
        C.was = L.cloud and L.cloud.enabled
        if L.cloud then L.cloud.enabled = false end
    end)
    A.do_(function()
        local pl = ST.plane()
        if not pl then return end
        C.tgt = ST.frame(pl, 600000, 0, 0)
        C.eye = ST.frame(pl, 0, 0, -180000)
        ST.look(C.eye, C.tgt, 60)
    end)
    A.wait(3)
    local TRY = { { 1000000, 5000 }, { 2000000, 5000 }, { 4000000, 5000 }, { 8000000, 5000 }, { 2000000, 10000 } }
    for k, t in ipairs(TRY) do
        local tag = string.format("f92_%d_%dM_r%d", k, t[1] / 1000000, t[2] / 1000)
        A.do_(function() if C.eye then ST.look(C.eye, C.tgt, 60) end; ST.shot(tag .. "_0_before") end)
        A.wait(0.3)
        A.do_(function()
            if not C.tgt then return end
            local c = {}
            for key, v in pairs(cfg().cloud or {}) do c[key] = v end
            c.brightness, c.radius_m, c.max_brightness, c.steps = t[1], t[2], 1.0e9, { 1, 1, 1, 1, 1, 1, 0 }
            local ok, what = pcall(THUNDER.cloudFlash, C.tgt, "effect", "the test", c)
            ST.info(tag .. ": " .. (ok and tostring(what) or ("error " .. tostring(what))))
        end)
        for j, w in ipairs({ 0.4, 0.5 }) do
            A.wait(w)
            A.do_(function() if C.eye then ST.look(C.eye, C.tgt, 60) end; ST.shot(string.format("%s_%d_on", tag, j)) end)
        end
        A.wait(2.5)
        A.do_(function() if C.eye then ST.look(C.eye, C.tgt, 60) end; ST.shot(tag .. "_3_after") end)
        A.wait(1)
    end
    A.do_(function()
        local L = cfg()
        if L.cloud then L.cloud.enabled = C.was end
        ST.lookBack()
    end)
end
-- (2026-11-17) watch93: the user watching the screen ("Keep testing and I'll watch the screen"): each step called out on
-- the HUD first. The night storm (Ctrl+S); its own lightning paused; cloud flashes put 1.5, 3 or 6 km ahead of your camera
-- at your height (in the layer you fly in), 0.4M to 8M, held ~1.5 s, one at a time; the four thunder sounds (Ctrl+J) 5 s
-- apart; then the whole storm 20 s. Pictures at each flash for the record.
SUITES.watch93 = function()
    intoRun()
    local C = {}
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    local function say(a, b) pcall(hudCallout, a, b); ST.info("watch93: " .. a .. " / " .. b) end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil and THUNDER.cloudFlash ~= nil, "the storm and its flashes are in this build") then return "abort" end
        say("TEST: NIGHT STORM", "CTRL+S IN 3 S")
    end)
    A.wait(3)
    A.do_(function() ST.marks.k1 = ST.n; ST.press("S") end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l) ST.check(l ~= nil, "the storm in", l) end)
    A.wait(4)
    A.do_(function()
        local L = cfg()
        C.on, C.cloud = L.enabled, L.cloud and L.cloud.enabled
        L.enabled = false
        say("TEST: CLOUD FLASHES", "THE STORM'S OWN LIGHTNING PAUSED: WATCH AHEAD")
    end)
    A.wait(4)
    local TRY = { { 400000, 3 }, { 1000000, 3 }, { 2000000, 3 }, { 3000000, 3 }, { 8000000, 3 },
                  { 2000000, 1.5 }, { 8000000, 1.5 }, { 2000000, 6 }, { 8000000, 6 } }
    for k, t in ipairs(TRY) do
        local label = string.format("%s, %.1f KM AHEAD", t[1] >= 1000000 and string.format("%g MILLION", t[1] / 1000000) or string.format("%dK", t[1] / 1000), t[2])
        A.do_(function() say(string.format("TEST: CLOUD FLASH %d/%d", k, #TRY), label .. " IN 2 S") end)
        A.wait(2)
        A.do_(function()
            local pcm, L, R
            pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
            pcall(function() R = pcm:GetCameraRotation() end)
            if not (L and R) then ST.info("watch93: no camera"); return end
            local yw = math.rad(R.Yaw or 0)
            local at = { X = L.X + math.cos(yw) * t[2] * 100000, Y = L.Y + math.sin(yw) * t[2] * 100000, Z = L.Z }
            local c = {}
            for key, v in pairs(cfg().cloud or {}) do c[key] = v end
            c.brightness, c.max_brightness, c.steps = t[1], 1.0e9, { 1, 1, 1, 1, 1, 1, 0 }
            local ok, what = pcall(THUNDER.cloudFlash, at, "effect", "the test", c)
            ST.info(string.format("watch93 flash %d: %s", k, ok and tostring(what) or ("error " .. tostring(what))))
        end)
        A.wait(0.5)
        A.do_(function() ST.shot(string.format("w93_flash_%d", k)) end)
        A.wait(3)
    end
    A.do_(function() say("TEST: THUNDER SOUNDS", "FOUR, 5 S APART: LISTEN") end)
    A.wait(3)
    for i = 1, 4 do
        A.do_(function() ST.press("J") end)
        A.wait(5)
    end
    A.do_(function()
        local L = cfg()
        L.enabled = C.on
        say("TEST: THE WHOLE STORM", "BOLTS, CLOUD FLASHES, THUNDER: 20 S")
    end)
    for i = 1, 8 do
        A.wait(2.5)
        A.do_(function() ST.shot(string.format("w93_storm_%d", i)) end)
    end
    A.do_(function() say("TEST: DONE", "THANK YOU") end)
    A.wait(2)
end
-- (2026-11-17) watch94: run 77, the user watching: none of the cloud flashes (Cloudly's effect light, 0.4M-8M) lit the
-- clouds, and none of the thunder sounds was heard (posted by name). 0.74.94 plays them with PostEventAtLocation. Called
-- out on the HUD first: the night storm (Ctrl+S); the four thunder sounds (Ctrl+J) 5 s apart; the whole sky flashed five
-- ways, a double flicker each, the storm's own lightning paused (A the clouds' sky light x20, B the moonlight (the night's
-- sun factor) x30, C the sky light x30, D the exposure +2.5, E B and C), twice through; the whole storm 15 s.
SUITES.watch94 = function()
    intoRun()
    local C = {}
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    local function say(a, b) pcall(hudCallout, a, b); ST.info("watch94: " .. a .. " / " .. b) end
    local function view() return SKY and SKY.viewCached and SKY.viewCached(os.clock(), nil) end
    local KINDS = {
        { "A", "THE CLOUDS' OWN SKY LIGHT X20", function(v) SKY.addField("cloud_amb", "CloudSkyAmbientLightIntensity"); return { { "asset|cloud_amb", "x", 20 } } end },
        { "B", "THE MOONLIGHT X30", function(v) return { { "asset|sun_factor", "x", 30 } } end },
        { "C", "THE SKY LIGHT X30", function(v) local t = {}; for _, x in ipairs(v.ctrl or {}) do t[#t + 1] = { "skyl|" .. x.name .. "|int", "x", 30 } end; return t end },
        { "D", "THE EXPOSURE +2.5", function(v) local t = {}; for _, x in ipairs(v.ppv or {}) do t[#t + 1] = { "ppv|" .. x.name .. "|bias", "+", 2.5 } end; return t end },
        { "E", "MOONLIGHT X30 AND SKY LIGHT X30", function(v)
            local t = { { "asset|sun_factor", "x", 30 } }
            for _, x in ipairs(v.ctrl or {}) do t[#t + 1] = { "skyl|" .. x.name .. "|int", "x", 30 } end
            return t end },
    }
    local function on(K)
        local v = view()
        if not v then return "no sky view" end
        C.saved = {}
        local parts = {}
        for _, k in ipairs(K[3](v)) do
            local get, set = SKY.slot(v, k[1])
            if get and set then
                local old = get()
                if type(old) == "number" then
                    local new = k[2] == "x" and old * k[3] or old + k[3]
                    C.saved[#C.saved + 1] = { set = set, old = old }
                    set(new)
                    parts[#parts + 1] = string.format("%s %.4g -> %.4g", k[1], old, new)
                else
                    parts[#parts + 1] = k[1] .. " unread"
                end
            else
                parts[#parts + 1] = k[1] .. " no slot"
            end
        end
        return #parts > 0 and table.concat(parts, ", ") or "nothing to write"
    end
    local function off() for _, x in ipairs(C.saved or {}) do pcall(x.set, x.old) end; C.saved = {} end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and SKY ~= nil and SKY.slot ~= nil, "the storm and the sky's slots are in this build") then return "abort" end
        say("TEST: NIGHT STORM", "CTRL+S IN 3 S")
    end)
    A.wait(3)
    A.do_(function() ST.marks.k1 = ST.n; ST.press("S") end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l) ST.check(l ~= nil, "the storm in", l) end)
    A.wait(3)
    A.do_(function() say("TEST: THUNDER SOUNDS", "FOUR, 5 S APART: LISTEN (PLAYED THE NEW WAY)") end)
    A.wait(3)
    for i = 1, 4 do
        A.do_(function() ST.marks["j" .. i] = ST.n; ST.press("J") end)
        A.log_("fleet storm: Ctrl+J thunder " .. i .. " of 4", 3, "j" .. i, true, function(l)
            ST.check(l ~= nil and l:find("(played;", 1, true) ~= nil, "Ctrl+J sound " .. i .. " played", l)
        end)
        A.wait(5)
    end
    A.do_(function()
        local L = cfg()
        C.on = L.enabled
        L.enabled = false
        say("TEST: SKY FLASHES", "THE STORM'S OWN LIGHTNING PAUSED: FIVE KINDS, A TO E")
    end)
    A.wait(4)
    for round = 1, 2 do
        for _, K in ipairs(KINDS) do
            A.do_(function() say("TEST: SKY FLASH " .. K[1] .. (round == 2 and " AGAIN" or ""), K[2] .. " IN 2 S") end)
            A.wait(2)
            A.do_(function() ST.info("watch94 " .. K[1] .. ": " .. on(K)); if round == 1 then ST.shot("w94_" .. K[1] .. "_on") end end)
            A.wait(0.3)
            A.do_(function() off() end)
            A.wait(0.2)
            A.do_(function() on(K) end)
            A.wait(0.25)
            A.do_(function() off() end)
            A.wait(1)
            A.do_(function() if round == 1 then ST.shot("w94_" .. K[1] .. "_off") end end)
            A.wait(2)
        end
    end
    A.do_(function()
        local L = cfg()
        L.enabled = C.on
        say("TEST: THE WHOLE STORM", "BOLTS, CLOUD FLASHES, THUNDER: 15 S")
    end)
    A.wait(15)
    A.do_(function()
        local n = 0
        for i = ST.marks.k1 or 1, ST.n do
            local l = ST.lines and ST.lines[i]
            if l and l:find("fleet storm: thunder ", 1, true) then n = n + 1; ST.info("watch94 saw: " .. l) end
        end
        say("TEST: DONE", "THANK YOU")
    end)
    A.wait(2)
end
-- (2026-11-17) cloudunits: the user: "you need to be having the cloud light work". Its values reach Cloudly's drawn copy
-- (runs 65-66) yet no flash lit a cloud (runs 70, 74-77, 0.4M-8M): is its position in Cloudly's own units? (Cloudly works in
-- metres: KickBlastEffect's CenterInMeters; we and the stock lights we spawned gave centimetres.) The storm night, its own
-- lightning paused, the storm's cloud light (THUNDER.cloudFlash) 1 km ahead of your camera, held ~1.5 s: its WorldPosition
-- in cm (as ever), in m, in km, its radius and brightness to match; pictured before / on / after, each called out.
SUITES.cloudunits = function()
    intoRun()
    local C = {}
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    local function say(a, b) pcall(hudCallout, a, b); ST.info("cloudunits: " .. a .. " / " .. b) end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil and THUNDER.cloudFlash ~= nil, "the storm and its cloud light are in this build") then return "abort" end
        ST.marks.k1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l)
        ST.check(l ~= nil, "the storm in", l)
        local L = cfg()
        C.on = L.enabled
        L.enabled = false
    end)
    A.wait(4)
    -- { label, position scale, radius_m (the light's AttenuationRadius = radius_m x 100), brightness }
    local TRY = { { "CM (AS EVER), 5 KM ROUND, 400K", 1, 5000, 400000 },
                  { "METRES, 500000 ROUND (MISSION 12'S), 40K (MISSION 12'S)", 0.01, 5000, 40000 },
                  { "METRES, 500000 ROUND, 400K", 0.01, 5000, 400000 },
                  { "METRES, 5000 ROUND, 400K", 0.01, 50, 400000 },
                  { "KM, 500 ROUND, 400K", 0.00001, 5, 400000 },
                  { "METRES, 500000 ROUND, 4M", 0.01, 5000, 4000000 } }
    for k, t in ipairs(TRY) do
        local tag = "cu_" .. k
        A.do_(function() say(string.format("TEST: CLOUD LIGHT %d/%d", k, #TRY), t[1] .. " IN 2 S") end)
        A.wait(2)
        A.do_(function() ST.shot(tag .. "_0_before") end)
        A.wait(0.3)
        A.do_(function()
            local pcm, L, R
            pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
            pcall(function() R = pcm:GetCameraRotation() end)
            if not (L and R) then ST.info(tag .. ": no camera"); return end
            local yw = math.rad(R.Yaw or 0)
            local w = { X = L.X + math.cos(yw) * 100000, Y = L.Y + math.sin(yw) * 100000, Z = L.Z }
            local at = { X = w.X * t[2], Y = w.Y * t[2], Z = w.Z * t[2] }
            local c = {}
            for key, v in pairs(cfg().cloud or {}) do c[key] = v end
            c.brightness, c.radius_m, c.max_brightness, c.steps = t[4], t[3], 1.0e9, { 1, 1, 1, 1, 1, 1, 0 }
            local ok, what = pcall(THUNDER.cloudFlash, at, "effect", "the test", c)
            ST.info(string.format("%s: WorldPosition %.6g %.6g %.6g, radius %.6g, %s", tag, at.X, at.Y, at.Z, t[3] * 100,
                ok and tostring(what) or ("error " .. tostring(what))))
        end)
        A.wait(0.4)
        A.do_(function() ST.shot(tag .. "_1_on") end)
        A.wait(0.5)
        A.do_(function() ST.shot(tag .. "_2_on") end)
        A.wait(2.5)
        A.do_(function() ST.shot(tag .. "_3_after") end)
        A.wait(1)
    end
    A.do_(function() local L = cfg(); L.enabled = C.on; say("TEST: DONE", "THANK YOU") end)
    A.wait(2)
end
-- (2026-11-17) cloudforce: run 79: the cloud light's position in cm, m or km lit nothing either. Cloudly caches its clouds'
-- lighting (shadows, AO, a reprojection history) and redoes it when told (ACloudlyActor ForceUpdate / ForceUpdateShadows /
-- ForceUpdateAO / ClearReprojectionHistory): is the effect light baked into it? The storm night, its lightning paused, the
-- storm's cloud light 1 km ahead of your camera (cm, 5 km round), held ~1.5 s, with each way of redoing it every tick while
-- it's on; then 4M with all of them; then Mission 12's own light (at 4x) with all of them.
SUITES.cloudforce = function()
    intoRun()
    local C = {}
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    local function say(a, b) pcall(hudCallout, a, b); ST.info("cloudforce: " .. a .. " / " .. b) end
    local function cdo() return StaticFindObject("/Script/Cloudly.Default__CloudlyActor") end
    local FORCE = {
        none = function() return "nothing redone" end,
        clear = function() local o = cdo(); return tostring(pcall(function() o:ClearReprojectionHistory() end)) end,
        aoshadow = function() local o = cdo(); return tostring(pcall(function() o:ForceUpdateAO() end)) .. "/" .. tostring(pcall(function() o:ForceUpdateShadows(2) end)) end,
        all = function()
            local o = cdo()
            local okF = pcall(function() o:ForceUpdate({ bForceUpdateShadows = true, bForceUpdateAO = true, FrameCount = 2, bRecaptureSkyLight = false,
                                                         CurrentSkyLight = nil, World = nil, bClearReprojectionHistory = true }) end)
            local okC = pcall(function() o:ClearReprojectionHistory() end)
            return tostring(okF) .. "/" .. tostring(okC)
        end,
    }
    local function ahead(km)
        local pcm, L, R
        pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
        pcall(function() R = pcm:GetCameraRotation() end)
        if not (L and R) then return nil end
        local yw = math.rad(R.Yaw or 0)
        return { X = L.X + math.cos(yw) * km * 100000, Y = L.Y + math.sin(yw) * km * 100000, Z = L.Z }
    end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil and THUNDER.cloudFlash ~= nil, "the storm and its cloud light are in this build") then return "abort" end
        ST.marks.k1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l)
        ST.check(l ~= nil, "the storm in", l)
        local L = cfg()
        C.on = L.enabled
        L.enabled = false
    end)
    A.wait(4)
    local TRY = { { "NOTHING REDONE", "none", 400000 }, { "REPROJECTION CLEARED", "clear", 400000 },
                  { "AO AND SHADOWS REDONE", "aoshadow", 400000 }, { "ALL REDONE", "all", 400000 }, { "ALL REDONE, 4M", "all", 4000000 } }
    for k, t in ipairs(TRY) do
        local tag = "cf_" .. k
        A.do_(function() say(string.format("TEST: CLOUD LIGHT %d/%d", k, #TRY + 1), t[1] .. " IN 2 S") end)
        A.wait(2)
        A.do_(function() ST.shot(tag .. "_0_before") end)
        A.wait(0.3)
        A.do_(function()
            local at = ahead(1)
            if not at then ST.info(tag .. ": no camera"); return end
            local c = {}
            for key, v in pairs(cfg().cloud or {}) do c[key] = v end
            c.brightness, c.radius_m, c.max_brightness, c.steps = t[3], 5000, 1.0e9, { 1, 1, 1, 1, 1, 1, 1, 0 }
            local ok, what = pcall(THUNDER.cloudFlash, at, "effect", "the test", c)
            ST.info(string.format("%s: %s; %s", tag, ok and tostring(what) or ("error " .. tostring(what)), FORCE[t[2]]()))
        end)
        for i = 1, 6 do
            A.wait(0.25)
            A.do_(function() FORCE[t[2]](); if i == 2 then ST.shot(tag .. "_1_on") elseif i == 5 then ST.shot(tag .. "_2_on") end end)
        end
        A.wait(2.5)
        A.do_(function() ST.shot(tag .. "_3_after") end)
        A.wait(1)
    end
    -- Mission 12's own light at 4x (its flash ~1-1.7 s), 1 km ahead, everything redone each tick
    A.do_(function() say(string.format("TEST: CLOUD LIGHT %d/%d", #TRY + 1, #TRY + 1), "MISSION 12'S OWN LIGHT, ALL REDONE, IN 2 S") end)
    A.wait(2)
    A.do_(function()
        if THUNDER.cloudOff then pcall(THUNDER.cloudOff) end    -- (one effect light: the storm's taken off first)
        ST.shot("cf_m12_0_before")
        local at = ahead(1)
        local cls = loadObject("/Game/Blueprints/Cloudly/CloudLight/BP_CloudLight_Ms012_PodargeDead.BP_CloudLight_Ms012_PodargeDead_C")
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not (at and cls and gs) then ST.info("cf_m12: no camera / class"); return end
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
        if okB and x then
            pcall(function() x.WorldPosition = at end)
            local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
            if okF and a then pcall(function() a.CustomTimeDilation = 4 end); C.m12 = a end
        end
        ST.info("cf_m12: Mission 12's light 1 km ahead at 4x: " .. tostring(C.m12 ~= nil))
    end)
    for i = 1, 12 do
        A.wait(0.25)
        A.do_(function() FORCE.all(); if i == 5 or i == 6 or i == 7 then ST.shot("cf_m12_" .. i) end end)
    end
    A.wait(2)
    A.do_(function() local L = cfg(); L.enabled = C.on; say("TEST: DONE", "THANK YOU") end)
    A.wait(2)
end
-- (2026-11-17) cloudday: runs 77-80: at the storm night no way of driving the cloud light lit a cloud (Mission 12's own
-- light either). By day, Survival's own sky (no Ctrl+S): the cloud light 1 km and 4 km ahead of your camera at 400k and 4M,
-- orange (Mission 12's colour, to tell it from the day's white), and Mission 12's own light 1 km ahead at 4x.
SUITES.cloudday = function()
    intoRun()
    local C = {}
    local function say(a, b) pcall(hudCallout, a, b); ST.info("cloudday: " .. a .. " / " .. b) end
    local function ahead(km)
        local pcm, L, R
        pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
        pcall(function() R = pcm:GetCameraRotation() end)
        if not (L and R) then return nil end
        local yw = math.rad(R.Yaw or 0)
        return { X = L.X + math.cos(yw) * km * 100000, Y = L.Y + math.sin(yw) * km * 100000, Z = L.Z }
    end
    A.wait(3)
    local TRY = { { 1, 400000 }, { 1, 4000000 }, { 4, 400000 }, { 4, 4000000 } }
    for k, t in ipairs(TRY) do
        local tag = "cd_" .. k
        A.do_(function() say(string.format("TEST: CLOUD LIGHT BY DAY %d/%d", k, #TRY + 1), string.format("%g KM AHEAD, %gK, ORANGE, IN 2 S", t[1], t[2] / 1000)) end)
        A.wait(2)
        A.do_(function() ST.shot(tag .. "_0_before") end)
        A.wait(0.3)
        A.do_(function()
            local at = ahead(t[1])
            if not at then ST.info(tag .. ": no camera"); return end
            local c = { brightness = t[2], radius_m = 5000, max_brightness = 1.0e9, color = { 255, 120, 40 }, steps = { 1, 1, 1, 1, 1, 1, 0 } }
            local ok, what = pcall(THUNDER.cloudFlash, at, "effect", "the test", c)
            ST.info(tag .. ": " .. (ok and tostring(what) or ("error " .. tostring(what))))
        end)
        A.wait(0.4)
        A.do_(function() ST.shot(tag .. "_1_on") end)
        A.wait(0.5)
        A.do_(function() ST.shot(tag .. "_2_on") end)
        A.wait(2.5)
        A.do_(function() ST.shot(tag .. "_3_after") end)
        A.wait(1)
    end
    A.do_(function() say("TEST: CLOUD LIGHT BY DAY 5/5", "MISSION 12'S OWN LIGHT IN 2 S") end)
    A.wait(2)
    A.do_(function()
        if THUNDER.cloudOff then pcall(THUNDER.cloudOff) end
        ST.shot("cd_m12_0_before")
        local at = ahead(1)
        local cls = loadObject("/Game/Blueprints/Cloudly/CloudLight/BP_CloudLight_Ms012_PodargeDead.BP_CloudLight_Ms012_PodargeDead_C")
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not (at and cls and gs) then return end
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1) end)
        if okB and x then
            pcall(function() x.WorldPosition = at end)
            local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
            if okF and a then pcall(function() a.CustomTimeDilation = 4 end) end
        end
    end)
    for i = 1, 10 do
        A.wait(0.25)
        A.do_(function() if i >= 4 and i <= 7 then ST.shot("cd_m12_" .. i) end end)
    end
    A.do_(function() say("TEST: DONE", "THANK YOU") end)
    A.wait(2)
end
-- (2026-11-17) cloudquality: runs 77-81: Cloudly's effect light lights nothing in Survival's level, day or night, the stock
-- lights too. Cloudly's quality cvars (r.Cloudly.QualityLevel, .Min, .Max, the scalability's sg.*) read; then by day the
-- orange cloud light 1 km ahead at 400k / 4M as the game has it, and again with r.Cloudly.QualityLevel at each of 0..4
-- (put back after).
SUITES.cloudquality = function()
    intoRun()
    local C = {}
    local function say(a, b) pcall(hudCallout, a, b); ST.info("cloudquality: " .. a .. " / " .. b) end
    local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local function cv(n) local v; pcall(function() v = ks:GetConsoleVariableIntValue(n) end); return v end
    local function cvf(n) local v; pcall(function() v = ks:GetConsoleVariableFloatValue(n) end); return v end
    local function cmd(c) pcall(function() ks:ExecuteConsoleCommand(ST.pc(), c, ST.pc()) end) end
    local function ahead(km)
        local pcm, L, R
        pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
        pcall(function() R = pcm:GetCameraRotation() end)
        if not (L and R) then return nil end
        local yw = math.rad(R.Yaw or 0)
        return { X = L.X + math.cos(yw) * km * 100000, Y = L.Y + math.sin(yw) * km * 100000, Z = L.Z }
    end
    A.do_(function()
        local names = { "r.Cloudly.QualityLevel", "r.Cloudly.QualityLevel.Min", "r.Cloudly.QualityLevel.Max", "r.Cloudly.ScalabilityBias.ScreenFraction",
                        "r.Cloudly.ScalabilityBias.AllHighResTiles", "sg.EffectsQuality", "sg.ShadowQuality", "sg.PostProcessQuality", "sg.TextureQuality",
                        "sg.ViewDistanceQuality", "sg.FoliageQuality", "sg.ShadingQuality", "sg.GlobalIlluminationQuality", "sg.ReflectionQuality" }
        local t = {}
        for _, n in ipairs(names) do t[#t + 1] = n .. " " .. tostring(cv(n)) .. " (" .. tostring(cvf(n)) .. ")" end
        ST.info("cloudquality cvars: " .. table.concat(t, ", "))
        C.q0 = cv("r.Cloudly.QualityLevel")
    end)
    A.wait(2)
    local LEVELS = { "as is", 0, 1, 2, 3, 4 }
    for k, q in ipairs(LEVELS) do
        local tag = "cq_" .. k
        A.do_(function()
            if q ~= "as is" then cmd("r.Cloudly.QualityLevel " .. q) end
            say(string.format("TEST: CLOUD QUALITY %s", tostring(q)), "1 KM AHEAD, 4M, ORANGE, IN 2 S")
        end)
        A.wait(2)
        A.do_(function() ST.info(tag .. ": r.Cloudly.QualityLevel now " .. tostring(cv("r.Cloudly.QualityLevel"))); ST.shot(tag .. "_0_before") end)
        A.wait(0.3)
        A.do_(function()
            local at = ahead(1)
            if not at then return end
            local c = { brightness = 4000000, radius_m = 5000, max_brightness = 1.0e9, color = { 255, 90, 20 }, steps = { 1, 1, 1, 1, 1, 1, 0 } }
            local ok, what = pcall(THUNDER.cloudFlash, at, "effect", "the test", c)
            ST.info(tag .. ": " .. (ok and tostring(what) or ("error " .. tostring(what))))
        end)
        A.wait(0.6)
        A.do_(function() ST.shot(tag .. "_1_on") end)
        A.wait(2.5)
        A.do_(function() ST.shot(tag .. "_2_after") end)
        A.wait(0.5)
    end
    A.do_(function() if C.q0 then cmd("r.Cloudly.QualityLevel " .. C.q0) end; say("TEST: DONE", "THANK YOU") end)
    A.wait(2)
end
-- (2026-11-17) cloudscal: run 82: r.Cloudly.QualityLevel 0-4 changed nothing; the game runs at sg.* 1 (effects, shadows,
-- post process, GI, reflections). Every sg.* at 3 and Cloudly at 3 (put back after): the orange cloud light 1 km ahead at
-- 400k / 4M by day, then the storm night (Ctrl+S) with its lightning paused, the same.
SUITES.cloudscal = function()
    intoRun()
    local C = {}
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    local function say(a, b) pcall(hudCallout, a, b); ST.info("cloudscal: " .. a .. " / " .. b) end
    local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local function cv(n) local v; pcall(function() v = ks:GetConsoleVariableIntValue(n) end); return v end
    local function cmd(c) pcall(function() ks:ExecuteConsoleCommand(ST.pc(), c, ST.pc()) end) end
    local SG = { "sg.EffectsQuality", "sg.ShadowQuality", "sg.PostProcessQuality", "sg.GlobalIlluminationQuality", "sg.ReflectionQuality", "r.Cloudly.QualityLevel" }
    local function ahead(km)
        local pcm, L, R
        pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
        pcall(function() R = pcm:GetCameraRotation() end)
        if not (L and R) then return nil end
        local yw = math.rad(R.Yaw or 0)
        return { X = L.X + math.cos(yw) * km * 100000, Y = L.Y + math.sin(yw) * km * 100000, Z = L.Z }
    end
    local function flash(tag, b)
        A.do_(function() say("TEST: " .. tag, string.format("1 KM AHEAD, %gK, ORANGE, IN 2 S", b / 1000)) end)
        A.wait(2)
        A.do_(function() ST.shot(tag .. "_0_before") end)
        A.wait(0.3)
        A.do_(function()
            local at = ahead(1)
            if not at then return end
            local c = { brightness = b, radius_m = 5000, max_brightness = 1.0e9, color = { 255, 90, 20 }, steps = { 1, 1, 1, 1, 1, 1, 0 } }
            local ok, what = pcall(THUNDER.cloudFlash, at, "effect", "the test", c)
            ST.info(tag .. ": " .. (ok and tostring(what) or ("error " .. tostring(what))))
        end)
        A.wait(0.6)
        A.do_(function() ST.shot(tag .. "_1_on") end)
        A.wait(2.5)
        A.do_(function() ST.shot(tag .. "_2_after") end)
        A.wait(0.5)
    end
    A.do_(function()
        C.was = {}
        for _, n in ipairs(SG) do C.was[n] = cv(n); cmd(n .. " 3") end
        local t = {}
        for _, n in ipairs(SG) do t[#t + 1] = n .. " " .. tostring(C.was[n]) .. " -> " .. tostring(cv(n)) end
        ST.info("cloudscal: " .. table.concat(t, ", "))
        say("TEST: HIGH SETTINGS", "EFFECTS, SHADOWS, GI, CLOUDS AT HIGH")
    end)
    A.wait(4)
    flash("cs_day_400k", 400000)
    flash("cs_day_4m", 4000000)
    A.do_(function() ST.marks.k1 = ST.n; ST.press("S") end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l)
        ST.check(l ~= nil, "the storm in", l)
        local L = cfg(); C.on = L.enabled; L.enabled = false
    end)
    A.wait(4)
    flash("cs_night_400k", 400000)
    flash("cs_night_4m", 4000000)
    A.do_(function()
        local L = cfg(); L.enabled = C.on
        for _, n in ipairs(SG) do if C.was[n] then cmd(n .. " " .. C.was[n]) end end
        say("TEST: DONE", "SETTINGS PUT BACK")
    end)
    A.wait(2)
end
-- (2026-11-17) listen94: the user heard no thunder in runs 77-83 (only run 78 played 0.74.94's way, and she wasn't listening).
-- A sound she knows (the STORE's bought beep, posted by name as the STORE does) as the control, then the four thunder
-- sounds (Ctrl+J, PostEventAtLocation) 4 s apart, twice through, then the beep again; each called out first.
SUITES.listen94 = function()
    intoRun()
    local BEEP = "AKE_GEN_UI_INGAME_BaseResupply_Decide_Play"
    local function say(a, b) pcall(hudCallout, a, b); ST.info("listen94: " .. a .. " / " .. b) end
    local function beep(tag)
        A.do_(function() say("LISTEN: " .. tag, "THE STORE BEEP, A SOUND YOU KNOW, IN 2 S") end)
        A.wait(2)
        A.do_(function() ST.info("listen94 beep: " .. tostring(THUNDER and THUNDER.post and THUNDER.post(BEEP))) end)
        A.wait(1.5)
        A.do_(function() THUNDER.post(BEEP) end)
        A.wait(2.5)
    end
    A.wait(3)
    beep("THE CONTROL")
    for round = 1, 2 do
        for i = 1, 4 do
            A.do_(function() say(string.format("LISTEN: THUNDER %d/4%s", i, round == 2 and " AGAIN" or ""), "IN 2 S") end)
            A.wait(2)
            A.do_(function() ST.marks["j" .. round .. i] = ST.n; ST.press("J") end)
            A.log_("fleet storm: Ctrl+J thunder " .. i .. " of 4", 3, "j" .. round .. i, true, function(l)
                ST.check(l ~= nil and l:find("(played;", 1, true) ~= nil, "thunder " .. i .. " played", l)
            end)
            A.wait(3)
        end
    end
    beep("THE CONTROL AGAIN")
    A.do_(function() say("LISTEN: DONE", "THANK YOU") end)
    A.wait(2)
end
-- (2026-11-17) cells95: the user's Mission 12 screenshot: its clouds glow blue from inside: Mission012_Phase01_VFX's 19
-- NS_CloudLightning in its cloud towers, drawn after the clouds (sort 100). 0.74.95's storm spawns them so: Ctrl+S, the
-- 19 up, pictures from your view, then still cameras from over the airfield onto two of the towers (spot 1, spot 12), 8
-- frames each 0.5 s apart; each step called out.
SUITES.cells95 = function()
    intoRun()
    local function say(a, b) pcall(hudCallout, a, b); ST.info("cells95: " .. a .. " / " .. b) end
    A.do_(function()
        if not ST.check(IFSKY ~= nil, "the storm is in this build") then return "abort" end
        say("TEST: NIGHT STORM", "CTRL+S IN 3 S: MISSION 12'S CLOUD LIGHTNING")
    end)
    A.wait(3)
    A.do_(function() ST.marks.k1 = ST.n; ST.press("S") end)
    A.log_("fleet storm: cloud lightning: ", 15, "k1", true, function(l)
        ST.check(l ~= nil and l:find("19 of 19 up (19 of them drawn after the clouds", 1, true) ~= nil, "the 19 cloud lightning cells up, drawn after the clouds", l)
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l) ST.check(l ~= nil, "the storm in", l) end)
    for i = 1, 6 do
        A.wait(0.7)
        A.do_(function() ST.shot(string.format("c95_you_%d", i)) end)
    end
    local VIEWS = { { "TOWER 1", { X = 2389746, Y = -1425882, Z = 636631 } }, { "TOWER 12", { X = 2618538, Y = -950632, Z = 636631 } } }
    for v, V in ipairs(VIEWS) do
        A.do_(function()
            say("TEST: LOOK AT " .. V[1], "A STILL CAMERA OVER THE AIRFIELD")
            ST.look({ X = 1610476, Y = -436143, Z = 350000 }, V[2], 45)
        end)
        A.wait(2)
        for i = 1, 8 do
            A.do_(function() ST.look({ X = 1610476, Y = -436143, Z = 350000 }, V[2], 45); ST.shot(string.format("c95_t%d_%d", v, i)) end)
            A.wait(0.5)
        end
    end
    A.do_(function() ST.lookBack(); say("TEST: DONE", "THANK YOU") end)
    A.wait(2)
end
-- (2026-11-17) glow96: 0.74.96's glows over the bolts (Mission 12's NS_CloudLightning, sort 100) weren't seen in run 86's
-- surfacing at 4-14 km. The storm night, its lightning paused: the glow put 2 km and 5 km ahead of your camera at your
-- height + 300 m, at scale 1, 3 and 6 (spawned inactive, sort 100, activated), pictured at 0.3, 0.8 and 1.5 s; then four
-- bolts struck 3-6 km out in your view (THUNDER.bolt) with a glow (scale 3) over each top.
SUITES.glow96 = function()
    intoRun()
    local C = { list = {} }
    local SYS = "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning.NS_CloudLightning"
    local function cfg() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    local function say(a, b) pcall(hudCallout, a, b); ST.info("glow96: " .. a .. " / " .. b) end
    local function cam()
        local pcm, L, R
        pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
        pcall(function() R = pcm:GetCameraRotation() end)
        return L, R
    end
    local function glow(at, sc)
        local lib, sys = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary"), loadObject(SYS)
        if not (lib and sys) then return "no Niagara / system" end
        local ok, comp = pcall(function() return lib:SpawnSystemAtLocation(survivalPC, sys, at, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc }, false, false, 0, false) end)
        if not (ok and comp) then return "no spawn" end
        pcall(function() comp.bOverrideSeparateTranslucencySortPriority = true end)
        pcall(function() comp.SeparateTranslucencySortPriority = 100 end)
        pcall(function() comp:SetTranslucentSortPriority(100) end)
        pcall(function() comp:Activate(true) end)
        C.list[#C.list + 1] = comp
        return "up"
    end
    local function clear() for _, c in ipairs(C.list) do pcall(function() c:DestroyComponent() end) end; C.list = {} end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil and THUNDER.bolt ~= nil, "the storm and its bolts are in this build") then return "abort" end
        ST.marks.k1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l)
        ST.check(l ~= nil, "the storm in", l)
        local L = cfg(); C.on = L.enabled; L.enabled = false
    end)
    A.wait(4)
    for _, km in ipairs({ 2, 5 }) do
        for _, sc in ipairs({ 1, 3, 6 }) do
            local tag = string.format("g96_%dkm_x%d", km, sc)
            A.do_(function() say("TEST: CLOUD GLOW", string.format("%d KM AHEAD, SCALE %d, IN 2 S", km, sc)) end)
            A.wait(2)
            A.do_(function() ST.shot(tag .. "_0") end)
            A.wait(0.2)
            A.do_(function()
                local L, R = cam()
                if not (L and R) then return end
                local yw = math.rad(R.Yaw or 0)
                local at = { X = L.X + math.cos(yw) * km * 100000, Y = L.Y + math.sin(yw) * km * 100000, Z = L.Z + 30000 }
                ST.info(tag .. ": " .. glow(at, sc))
            end)
            for j, w in ipairs({ 0.3, 0.5, 0.7 }) do
                A.wait(w)
                A.do_(function() ST.shot(string.format("%s_%d", tag, j)) end)
            end
            A.wait(1.5)
            A.do_(function() clear() end)
        end
    end
    for k = 1, 4 do
        A.do_(function() say("TEST: A BOLT AND ITS GLOW " .. k .. "/4", "3-6 KM OUT IN YOUR VIEW, IN 2 S") end)
        A.wait(2)
        A.do_(function()
            local b = {}
            for key, v in pairs(cfg().bolts or {}) do b[key] = v end
            b.view_km, b.steps = { 3, 6 }, { 1, 1, 1, 1, 1, 1, 0 }
            local ok, what, why, top = pcall(THUNDER.bolt, { X = 0, Y = 0, Z = 0 }, b, "the test", true)
            local g = (ok and type(top) == "table") and glow({ X = top.X, Y = top.Y, Z = top.Z + 30000 }, 3) or "no top"
            ST.info(string.format("g96 bolt %d: %s; glow %s", k, ok and tostring(what or why) or ("error " .. tostring(what)), g))
        end)
        A.wait(0.3)
        A.do_(function() ST.shot(string.format("g96_bolt%d_1", k)) end)
        A.wait(0.6)
        A.do_(function() ST.shot(string.format("g96_bolt%d_2", k)) end)
        A.wait(1.5)
        A.do_(function() clear() end)
    end
    A.do_(function() local L = cfg(); L.enabled = C.on; clear(); say("TEST: DONE", "THANK YOU") end)
    A.wait(2)
end
-- (2026-11-17) flash: our own cloud flash (tools/stormfx NS_SV_CloudFlash, a burst at each activation): the storm's glow
-- pool uses it when its container is in (the log names it); spawned alone 3 and 6 km ahead at cloud height, pictures 0.1-1.2 s
-- after; then strikes on cue in your view (IFSKY.strike: the bolt, our flash at its top, thunder), pictures on each; then the
-- storm's own lightning for 12 s. Pass: the system loads, spawns and the game lives; the pictures say whether it draws.
SUITES.flash = function()
    intoRun()
    local C = { list = {} }
    local SYS = "/Game/Mods/SurvivalMode/StormFx/NS_SV_CloudFlash.NS_SV_CloudFlash"
    local BURST = "/Game/Mods/SurvivalMode/StormFx/NS_SV_CloudBurst.NS_SV_CloudBurst"   -- (AC8's own, its spawn literals raised)
    local function say(a, b) pcall(hudCallout, a, b); ST.info("flash: " .. a .. " / " .. b) end
    local function cam()
        local pcm, L, R
        pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
        pcall(function() R = pcm:GetCameraRotation() end)
        return L, R
    end
    local function ahead(km, upM)
        local L, R = cam()
        if not (L and R) then return nil end
        local yw = math.rad(R.Yaw or 0)
        return { X = L.X + math.cos(yw) * km * 100000, Y = L.Y + math.sin(yw) * km * 100000, Z = (upM and upM * 100) or (L.Z + 30000) }
    end
    local function flash(at, path, sc)
        local lib, sys = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary"), loadObject(path or SYS)
        if not sys then return "NOT loaded" end
        if not lib then return "no Niagara" end
        local ok, comp = pcall(function() return lib:SpawnSystemAtLocation(survivalPC, sys, at, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc or 1, Y = sc or 1, Z = sc or 1 }, false, false, 0, false) end)
        if not (ok and comp) then return "no spawn" end
        pcall(function() comp.bOverrideSeparateTranslucencySortPriority = true end)
        pcall(function() comp.SeparateTranslucencySortPriority = 100 end)
        pcall(function() comp:SetTranslucentSortPriority(100) end)
        pcall(function() comp:Activate(true) end)
        C.list[#C.list + 1] = comp
        return "up"
    end
    local function clear() for _, c in ipairs(C.list) do pcall(function() c:DestroyComponent() end) end; C.list = {} end
    local function L() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSKY.strike ~= nil and THUNDER ~= nil, "the storm and its cued strike are in this build") then return "abort" end
        ST.info("NS_SV_CloudFlash " .. (loadObject(SYS) and "loads" or "NOT in"))
        ST.check(loadObject(BURST) ~= nil, "NS_SV_CloudBurst loads (AC8's own, patched: its container installed)", BURST)
        ST.marks.k1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l)
        ST.check(l ~= nil, "the storm in", l)
        C.on = L().enabled; L().enabled = false            -- (its own lightning held while we take our pictures)
    end)
    A.wait(4)
    -- (burstwatch, run 20261117_140335: left on, the burst lit the sky from its first frame (the stock one only at 15 s); its
    -- particles die when it's switched off (bCanDieWhenEmitterDeactivates): on 0.5 s, pictures inside it; scales 0.15-0.6)
    for _, sc in ipairs({ 0.15, 0.3, 0.6 }) do
        local km = 5
        local tag = string.format("bu_x%03d", math.floor(sc * 100))
        A.do_(function() say("TEST: AC8'S CLOUD BURST", string.format("5 KM AHEAD, SCALE %.2f, IN 2 S", sc)) end)
        A.wait(2)
        A.do_(function() ST.shot(tag .. "_0") end)
        A.wait(0.2)
        A.do_(function() local at = ahead(km); ST.info(tag .. ": " .. (at and flash(at, BURST, sc) or "no camera")) end)
        for j, w in ipairs({ 0.1, 0.15, 0.2 }) do
            A.wait(w)
            A.do_(function() ST.shot(string.format("%s_%d", tag, j)) end)
        end
        A.do_(function() for _, c in ipairs(C.list) do pcall(function() c:Deactivate() end) end end)
        for j, w in ipairs({ 0.2, 0.6 }) do
            A.wait(w)
            A.do_(function() ST.shot(string.format("%s_%d", tag, j)) end)
        end
        A.wait(1.5)
        A.do_(function() clear() end)
    end
    for _, km in ipairs({}) do                               -- (our own cooked flash: run 20261117_135637 drew it full-screen
        local tag = string.format("fl_%dkm", km)            -- with blocky artifacts; off here)
        A.do_(function() say("TEST: CLOUD FLASH", string.format("%d KM AHEAD, IN 2 S", km)) end)
        A.wait(2)
        A.do_(function() ST.shot(tag .. "_0") end)
        A.wait(0.2)
        A.do_(function() local at = ahead(km); ST.info(tag .. ": " .. (at and flash(at) or "no camera")) end)
        for j, w in ipairs({ 0.1, 0.2, 0.3, 0.6 }) do
            A.wait(w)
            A.do_(function() ST.shot(string.format("%s_%d", tag, j)) end)
        end
        A.wait(1.5)
        A.do_(function() clear() end)
    end
    for k = 1, 4 do
        A.do_(function() say("TEST: A STRIKE " .. k .. "/4", "4 KM AHEAD, IN 2 S") end)
        A.wait(2)
        A.do_(function()
            local at = ahead(4, 3000)
            local ok, okS, what = pcall(IFSKY.strike, at, "the flash test")
            ST.info(string.format("fl strike %d: %s", k, ok and tostring(what) or ("error " .. tostring(okS))))
        end)
        for j, w in ipairs({ 0.15, 0.25, 0.4 }) do
            A.wait(w)
            A.do_(function() ST.shot(string.format("fl_strike%d_%d", k, j)) end)
        end
        A.wait(1.5)
    end
    A.do_(function() L().enabled = C.on; say("TEST: THE STORM'S OWN", "12 S") end)
    for i = 1, 8 do
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("fl_storm_%d", i)) end)
    end
    A.do_(function()
        local l = ST.findLog("fleet storm: the bolts' cloud flash:", ST.marks.k1, true)
        ST.check(l ~= nil and l:find("NS_SV_CloudBurst", 1, true) ~= nil, "the storm's glow pool uses AC8's burst", l)
        clear(); say("TEST: DONE", "THANK YOU")
    end)
    A.wait(2)
end
-- (2026-11-17) burstwatch: when do the cloud lightnings flash? Each spawned 5 km ahead at 3 km up and LEFT ON 16 s in front
-- of a fixed camera, a picture every 0.5 s: Mission 12's stock NS_CloudLightning, AC8's patched NS_SV_CloudBurst (its spawn
-- literals x20: run 20261117_140029 showed nothing switched off after 0.25 s: a loop delay?), our NS_SV_CloudFlash at 1/4 scale
SUITES.burstwatch = function()
    intoRun()
    local W = {}
    -- ((0.74.112) as the storm uses them: each switched on 0.5 s (its scale), off, every 2 s, 8 times, at 7 and 10 km; pictures
    -- at 0.1 / 0.25 / 0.4 s inside each; AC8's burst (x5) and our own flash (800 m, x0.6))
    local LIST = { { "burst", "/Game/Mods/SurvivalMode/StormFx/NS_SV_CloudBurst.NS_SV_CloudBurst", 0.1 },
                   { "own", "/Game/Mods/SurvivalMode/StormFx/NS_SV_CloudFlash.NS_SV_CloudFlash", 1 } }
    local function L() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and THUNDER ~= nil, "the storm is in this build") then return "abort" end
        ST.marks.k1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l)
        ST.check(l ~= nil, "the storm in", l)
        W.on = L().enabled; L().enabled = false
    end)
    A.wait(4)
    for _, e in ipairs(LIST) do
        for _, km in ipairs(e[1] == "burst" and { 4, 7, 10 } or { 4 }) do
            A.do_(function()
                local me = playerLocation and playerLocation()
                if not me then ST.info("burstwatch: no plane spot"); return end
                W.cam = { X = me.X, Y = me.Y, Z = me.Z + 50000 }
                W.spot = { X = me.X + km * 100000, Y = me.Y, Z = 400000 }
                ST.look(W.cam, W.spot, 50)
                local lib, sys = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary"), loadObject(e[2])
                if not sys then ST.info("burstwatch " .. e[1] .. ": NOT loaded"); return end
                local sc = e[3]
                local ok, comp = pcall(function() return lib:SpawnSystemAtLocation(survivalPC, sys, W.spot, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc }, false, false, 0, false) end)
                if ok and comp then
                    pcall(function() comp.bOverrideSeparateTranslucencySortPriority = true end)
                    pcall(function() comp.SeparateTranslucencySortPriority = 100 end)
                    pcall(function() comp:SetTranslucentSortPriority(100) end)
                    W.comp = comp
                end
                ST.info(string.format("burstwatch %s %d km: %s (scale %s)", e[1], km, (ok and comp) and "spawned" or "NOT spawned", tostring(sc)))
            end)
            for k = 1, 5 do
                A.do_(function()                                     -- ((0.74.116) a fresh system each flash, as the storm's)
                    if W.comp then pcall(function() W.comp:DestroyComponent() end); W.comp = nil end
                    local lib, sys = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary"), loadObject(e[2])
                    local sc = e[3]
                    local ok, comp = pcall(function() return lib:SpawnSystemAtLocation(survivalPC, sys, W.spot, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc }, false, false, 0, false) end)
                    if ok and comp then
                        pcall(function() comp.bOverrideSeparateTranslucencySortPriority = true end)
                        pcall(function() comp.SeparateTranslucencySortPriority = 100 end)
                        pcall(function() comp:SetTranslucentSortPriority(100) end)
                        pcall(function() comp:Activate(true) end)
                        W.comp = comp
                    end
                end)
                for q, w in ipairs({ 0.1, 0.15, 0.15, 0.2, 0.15 }) do       -- ((0.74.115) on 0.8 s, as the storm's)
                    A.wait(w)
                    A.do_(function() ST.shot(string.format("bw_%s_%dkm_%d_%d", e[1], km, k, q)) end)
                end
                A.wait(0.05)
                A.do_(function() if W.comp then pcall(function() W.comp:Deactivate() end) end end)
                A.wait(1.5)
            end
            A.do_(function() if W.comp then pcall(function() W.comp:DestroyComponent() end); W.comp = nil end; ST.lookBack() end)
            A.wait(1)
        end
    end
    A.do_(function() L().enabled = W.on end)
    A.wait(1)
end
-- (2026-11-17) planelight: a strike's light on your plane (sv_fleet_storm.lua slFlash: our directional light from the strike,
-- flickered a tick at a time). The night storm, its own lightning held; strikes on cue 4, 8 and 12 km off your camera's
-- right, 3 km up, twice each; pictures just before and 0.1 / 0.35 / 0.6 s after. The log: the light made and turned.
SUITES.planelight = function()
    intoRun()
    local W = {}
    local function L() return ((((CFG.specials or {}).fleet or {}).sky or {}).storm or {}).lightning or {} end
    local function side(km)
        local pcm, Lc, R
        pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); Lc = { X = v.X, Y = v.Y, Z = v.Z } end)
        pcall(function() R = pcm:GetCameraRotation() end)
        if not (Lc and R) then return nil end
        local yw = math.rad((R.Yaw or 0) + 60)
        return { X = Lc.X + math.cos(yw) * km * 100000, Y = Lc.Y + math.sin(yw) * km * 100000, Z = 300000 }
    end
    A.do_(function()
        if not ST.check(IFSKY ~= nil and IFSKY.strike ~= nil, "the storm and its cued strike are in this build") then return "abort" end
        ST.marks.k1 = ST.n
        ST.press("S")
    end)
    A.log_("fleet storm: in (", 15, "k1", true, function(l)
        ST.check(l ~= nil, "the storm in", l)
        W.on = L().enabled; L().enabled = false
    end)
    A.wait(5)
    -- ((0.74.120) intensity 6 lifted the plane 5 -> 7 of 255: a ladder at 6 km)
    for _, km in ipairs({ 6 }) do
        for r, inten in ipairs({ 1000, 4000, 10000 }) do   -- ((0.74.122) the point light, at once)
            local tag = string.format("pl_i%d", inten)
            A.do_(function() local pl = L().plane_light; if pl then pl.intensity, pl.max_km = inten, 15 end; ST.shot(tag .. "_0") end)
            A.wait(0.5)
            A.do_(function()
                local at = side(km)
                local ok, okS, what = pcall(IFSKY.strike, at, "the plane-light test")
                ST.info(string.format("%s: %s", tag, ok and tostring(what) or ("error " .. tostring(okS))))
            end)
            for q, w in ipairs({ 0.1, 0.25, 0.25 }) do
                A.wait(w)
                A.do_(function() ST.shot(string.format("%s_%d", tag, q)) end)
            end
            A.wait(2)
        end
    end
    A.do_(function()
        local l = ST.findLog("fleet storm: strike light 1:", ST.marks.k1, true)
        ST.check(l ~= nil, "the strike light made and turned", l)
        L().enabled = W.on
    end)
    A.wait(1)
end
-- (2026-11-17) fleet30: WP10 step 1 (sv_fleet_round.lua) played: the run set to round 29 in its first break: the warning;
-- round 30 the fleet's: its callout, the surfacing, the fleet up; GEOFON sunk (finishUnpaid on its hull): 6,000 and its
-- callout; the rest sunk and the round's own fighters finished: the win, 50,000, the airfield fully repaired. Pictures.
SUITES.fleet30 = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFROUND ~= nil and SPC and SPC.kinds and SPC.kinds.fleet ~= nil, "round 30's fleet is in this build") then return "abort" end
        ST.marks.k0 = ST.n
        ST.check(D and D.state == "wait", "the run's first break", tostring(D and D.state))
        D.round = 29
        C.cr = RUN.credits
        ST.info("fleet30: the run set to round 29's break (credits " .. tostring(RUN.credits) .. ")")
    end)
    A.log_("fleet round: round 29's break: the warning", 10, "k0", true, function(l) ST.check(l ~= nil, "round 29's break: the warning", l) end)
    A.log_("fleet round: round 30 is the fleet's", 10, "k0", true, function(l) ST.check(l ~= nil, "round 30 picked as the fleet's", l) end)
    A.do_(function() ST.shot("f30_warning") end)
    A.log_("fleet round: round 30: the fleet's 15 ships coming", 120, "k0", true, function(l)
        ST.check(l ~= nil, "round 30 started: the fleet coming, its music", l)
    end)
    for i = 1, 6 do
        A.wait(4)
        A.do_(function() ST.shot(string.format("f30_surfacing_%d", i)) end)
    end
    A.log_("15 of 15 ships up", 60, "k0", true, function(l) ST.check(l ~= nil, "the fleet up after the surfacing", l) end)
    A.wait(3)
    A.do_(function()
        ST.shot("f30_fleet_up")
        local F = IFLEET and IFLEET.cur
        local g = F and F.ships[1]
        if not (g and g.hull) then ST.info("fleet30: GEOFON's hull not kept"); return end
        ST.marks.k1 = ST.n
        local okF, dead, h, how = pcall(finishUnpaid, g.hull.obj)
        ST.info(string.format("fleet30: GEOFON finished: %s %s %s %s", tostring(okF), tostring(dead), tostring(h), tostring(how)))
    end)
    A.log_("fleet round: GEOFON (ford) sunk", 15, "k1", true, function(l)
        local z = l and tonumber(l:match(": (%d+) zollars"))   -- (6,000 x the special's and the tier's, as the Spaceport's pay: run 88's 24,000)
        ST.check(z ~= nil and z >= 6000, "GEOFON sunk: 6,000 at least (x the special and the tier)", l)
    end)
    A.wait(2)
    A.do_(function()
        ST.shot("f30_geofon_sunk")
        local F = IFLEET and IFLEET.cur
        local k = 0
        for i = 2, #(F and F.ships or {}) do
            local sh = F.ships[i]
            if sh.hull then local okF = pcall(finishUnpaid, sh.hull.obj); if okF then k = k + 1 end end
        end
        ST.info("fleet30: " .. k .. " more hulls finished")
    end)
    A.wait(8)
    A.do_(function()
        local F = IFLEET and IFLEET.cur
        local afloat = 0
        for _, sh in ipairs(F and F.ships or {}) do if (sh.r or 0) > 0 and not sh.sunk then afloat = afloat + 1 end end
        ST.info("fleet30: afloat now " .. afloat .. ", row " .. tostring(IFROUND.row and IFROUND.row(D.special, {})))
        ST.marks.k2 = ST.n
        local k = 0
        for _, pl in ipairs(planes or {}) do
            if pl.unit and D.up and D.up[pl.unit] and pl.obj then if pcall(finishUnpaid, pl.obj) then k = k + 1 end end
        end
        ST.info("fleet30: the round's own aircraft finished: " .. k)
    end)
    A.log_("fleet round: won at", 60, "k2", true, function(l)
        ST.check(l ~= nil and l:find("15 ships sunk", 1, true) ~= nil and l:find("health", 1, true) ~= nil, "won: every ship sunk, the airfield repaired", l)
    end)
    A.wait(1)
    A.do_(function()
        ST.shot("f30_won")
        ST.info(string.format("fleet30: credits %s -> %s; the airfield %s / %s, closed %s", tostring(C.cr), tostring(RUN.credits),
            tostring(AF and AF.hp), tostring(AF and AF.full), tostring(AF and AF.closed)))
        ST.check(RUN.credits - (C.cr or 0) >= 50000 + 22600, "paid: the fleet (22,600 at least, before the tier) and the win (50,000)")
        ST.check(IFLEET.cur == nil, "the fleet taken off")
    end)
    A.wait(3)
end
-- (2026-11-17) aegislasers: the fleet's Aegis lasers (sv_fleet_lasers.lua, BP_SV_IF_Aegis: the user, "2 Lasers Interceptors
-- one on the Aft and the Bow, targettable"): Ctrl+N; every Aegis's two mounts handed to AC7's LaserInterceptor and each one
-- carrying its laser; RAVEN's bow and stern close up; one mount shot off (finishUnpaid): its laser gone. Pictures.
-- ((0.74.164) the user: "Have the Raven use ECM too": RAVEN's Mk 15 slot carries the Alicorn's ECM part) the fleet up
-- (Ctrl+N), RAVEN's parts read (an alcn_ecm part among them), pictured; your plane put 3 km off RAVEN (SV_Respawn's move)
-- and the cockpit pictured (its jamming on your HUD?)
SUITES.ravenecm = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFLEET ~= nil, "the fleet is in this build") then return "abort" end
        ST.marks.r0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: up: RAVEN", 60, "r0", true, function(l)
        ST.check(l ~= nil and l:find("alcn_ecm", 1, true) ~= nil, "RAVEN up with the Alicorn's ECM among its parts", l)
    end)
    A.wait(6)
    A.do_(function()
        for _, sh in ipairs(IFLEET.cur and IFLEET.cur.ships or {}) do
            if sh.name == "RAVEN" and sh.hull and valid(sh.hull.obj) then C.sh = sh end
        end
        if not C.sh then ST.info("ravenecm: RAVEN not found"); return end
        for _, e in ipairs(C.sh.parts) do
            ST.info(string.format("ravenecm: RAVEN part %s health %s", e.cls, tostring(ST.healthOf(e.obj))))
            if e.cls:find("ecm", 1, true) then C.ecm = e end
        end
        ST.check(C.ecm ~= nil, "RAVEN's ECM part found", C.ecm and C.ecm.cls or "none")
    end)
    local function ecmObj() return C.ecm and valid(C.ecm.obj) and C.ecm.obj or (C.sh and C.sh.hull and C.sh.hull.obj) end
    A.picture("raven_ecm_close", function() local o = ecmObj(); return o and ST.off(ST.at(o), 2500, 3000, 1500) end,
        function() local o = ecmObj(); return o and ST.at(o) end, 40)
    A.picture("raven_side", function() local o = C.sh and C.sh.hull and C.sh.hull.obj; return o and ST.frame(o, 0, 13000, 4000) end,
        function() local o = C.sh and C.sh.hull and C.sh.hull.obj; return o and ST.at(o) end, 60)
    A.do_(function()
        local o = C.sh and C.sh.hull and C.sh.hull.obj
        local pl = ST.plane()
        if not (o and pl and type(SV_Respawn) == "function") then ST.info("ravenecm: no move (RAVEN, plane or SV_Respawn missing)"); return end
        if type(SV_Down) == "function" then pcall(SV_Down, 0) end
        local r = ST.at(o)
        local x, y, z = r.X - 300000, r.Y, 80000                 -- (3 km west of her, 800 m up, facing her)
        local rc = SV_Respawn(addrOf(pl) or 0, x, y, z, 0, 0, 0)
        ST.info("ravenecm: your plane moved 3 km off RAVEN: SV_Respawn " .. tostring(rc))
    end)
    A.wait(3); A.do_(function() ST.shot("raven_ecm_cockpit_3s") end)
    A.wait(5); A.do_(function() ST.shot("raven_ecm_cockpit_8s") end)
    A.wait(5)
    A.do_(function() ST.check(ST.plane() ~= nil and D ~= nil, "still flying after it") end)
end

-- ((0.74.164) GEOFON's capture, solo on your own plane (IFCAP.test): the lock, the takeover to the gate, the line down to the
-- deck, the trap, your plane given back; the user's rules: invincible and untargeted while RAVEN flies you, given back after
SUITES.capture = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFLEET ~= nil and IFCAP ~= nil, "the fleet and its capture are in this build") then return "abort" end
        ST.marks.c0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: up: RAVEN", 60, "c0", true, function(l) ST.check(l ~= nil, "the fleet up (RAVEN)", l) end)
    A.wait(10)
    A.do_(function()                                       -- (the harness's own autopilot and shield off; your plane put 10 km
        ST.apOff = true                                    -- behind GEOFON at 1500 m, facing along its way)
        if type(SV_Down) == "function" then pcall(SV_Down, 0) end
        local sh = IFLEET.cur and IFLEET.cur.ships and IFLEET.cur.ships[1]
        local pl = ST.plane()
        if sh and sh.hull and valid(sh.hull.obj) and pl and type(SV_Respawn) == "function" then
            local l, r = sh.hull.obj:K2_GetActorLocation(), sh.hull.obj:K2_GetActorRotation()
            local y = math.rad(r.Yaw)
            local rc = SV_Respawn(addrOf(pl) or 0, l.X - math.cos(y) * 1000000, l.Y - math.sin(y) * 1000000, 150000, 0, r.Yaw, 0)
            ST.info("capture: your plane put 10 km behind GEOFON: SV_Respawn " .. tostring(rc))
        end
    end)
    A.do_(function()                                       -- ((0.74.167) the player plane's targeting fields: what to switch off)
        local pl = ST.plane()
        local names = {}
        pcall(function()
            local cls = pl:GetClass()
            while cls and cls:IsValid() do
                cls:ForEachProperty(function(prop)
                    local nm = prop:GetFName():ToString()
                    local low = nm:lower()
                    if low:find("target") or low:find("lock") or low:find("faction") or low:find("team") or low:find("attack")
                        or low:find("hostile") or low:find("enemy") or low:find("aggro") then
                        local v = "?"
                        pcall(function() v = tostring(pl[nm]) end)
                        names[#names + 1] = nm .. "=" .. v
                    end
                end)
                cls = cls:GetSuperStruct()
            end
        end)
        ST.info("capture: the player plane's targeting fields: " .. (#names > 0 and table.concat(names, ", ") or "none read"))
    end)
    A.wait(3)
    A.do_(function()
        ST.marks.c1 = ST.n
        local ok, why = IFCAP.test(4)
        ST.check(ok == true, "a capture on your plane (IFCAP.test)", tostring(why))
    end)
    A.wait(1); A.do_(function() ST.shot("capture_lock") end)
    A.log_("capture: seq %d+: taken over", 10, "c1", false, function(l) ST.check(l ~= nil, "taken over after the lock", l) end)
    A.wait(2)
    A.do_(function()
        local pl = ST.plane()
        local inv, fa, mp = nil, nil, nil
        pcall(function() inv = pl.bIsInvincible end)
        pcall(function() fa = pl.Faction end)
        pcall(function() mp = pl.MaxPursuitAttackers end)
        ST.check(inv == true and fa == 0 and mp == 0, "while RAVEN flies you: invincible, no enemy targets you",
            string.format("invincible %s, faction %s, pursuers %s", tostring(inv), tostring(fa), tostring(mp)))
        ST.shot("capture_taken")
    end)
    A.wait(10); A.do_(function() ST.shot("capture_fly_1"); ST.info("capture: state " .. tostring(IFCAP.state())) end)
    A.wait(15); A.do_(function() ST.shot("capture_fly_2"); ST.info("capture: state " .. tostring(IFCAP.state())) end)
    A.wait(15); A.do_(function() ST.shot("capture_fly_3"); ST.info("capture: state " .. tostring(IFCAP.state())) end)
    -- ((0.74.181) the user: "Go ahead": outside pictures of the plane at its touchdown on GEOFON's deck)
    A.until_(function() return ST.findLog("capture: seq %d+: touched down", ST.marks.c1, false) or IFCAP.state() == nil end, 200,
        function() end)
    A.picture("capture_touchdown_above", function() local pl = ST.plane(); return pl and ST.off(ST.at(pl), 0, 1, 80000) end,
        function() local pl = ST.plane(); return pl and ST.at(pl) end, 60)
    A.picture("capture_touchdown_behind", function() local pl = ST.plane(); return pl and ST.off(ST.at(pl), -6000, 0, 2500) end,
        function() local pl = ST.plane(); return pl and ST.at(pl) end, 50)
    A.picture("capture_touchdown_side", function() local pl = ST.plane(); return pl and ST.off(ST.at(pl), 0, 7000, 1200) end,
        function() local pl = ST.plane(); return pl and ST.at(pl) end, 50)
    -- (to its end on its own clock: the checks the moment it's over, not a fixed wait's later)
    A.until_(function() return IFCAP.state() == nil end, 200, function(v) ST.check(v ~= nil, "the capture over within 200 s") end)
    A.do_(function()                                       -- (at once: given back, mortal and targetable; then the harness's
        local pl = ST.plane()                              -- shield again: the fleet's missiles still in the air hit it)
        local inv, fa, mp = nil, nil, nil
        pcall(function() inv = pl.bIsInvincible end)
        pcall(function() fa = pl.Faction end)
        pcall(function() mp = pl.MaxPursuitAttackers end)
        ST.check(inv == false and fa == 1 and mp ~= 0, "after it: mortal and targetable again",
            string.format("invincible %s, faction %s, pursuers %s", tostring(inv), tostring(fa), tostring(mp)))
        ST.apOff = nil
        ST.shot("capture_deck")
        -- ((0.74.193) up to the capture's end only: the solo test gives your plane back over the fleet, whose guns may down
        -- it after (0.74.193's run: shot down 9 s after the trap, the touchdown pictures holding this check 10 s)
        local _, di = ST.findLog("death: round", ST.marks.c1, true)
        local _, ei = ST.findLog("captured on GEOFON", ST.marks.c1, true)
        if not ei then _, ei = ST.findLog("given back", ST.marks.c1, true) end
        ST.check(di == nil or (ei ~= nil and di > ei), "never shot down or crashed while RAVEN flew it",
            di and string.format("a death at log line %d, the capture's end at %s", di, tostring(ei)) or nil)
    end)
    A.log_("capture: seq %d+: at the gate", 5, "c1", false, function(l) ST.check(l ~= nil, "at GEOFON's gate", l) end)
    A.log_("capture: seq %d+: trapped on GEOFON's deck", 5, "c1", false, function(l) ST.check(l ~= nil, "trapped on GEOFON's deck", l) end)
    A.do_(function()                                       -- ((0.74.174) the landing: said either way, a touchdown or a pass)
        ST.info("capture: the landing: " .. tostring(ST.findLog("capture: seq %d+: the landing", ST.marks.c1, false)))
        ST.info("capture: touchdown: " .. tostring(ST.findLog("capture: seq %d+: touched down", ST.marks.c1, false)))
    end)
    A.log_("capture: seq %d+: captured on GEOFON", 5, "c1", false, function(l) ST.check(l ~= nil, "captured (solo: given back)", l) end)
    A.wait(3)
    A.do_(function()
        ST.shot("capture_after")
        ST.check(ST.plane() ~= nil and D ~= nil, "still in the run after it")
    end)
end

-- ((0.74.182) where GEOFON's hull really is against its root: its bounds and its meshes' places, pictured from above its root
-- and above its bounds' centre (the capture's deck mark and slab are placed from the root)
-- ((0.74.186) A6: can Lua move a ship (a co-op rejoiner's fleet copies start at the course's start)? GEOFON's hull moved
-- 2 km along its course by K2_SetActorLocation (teleport), then where it and a part of it are, and its speed, over 15 s
SUITES.shipmove = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFLEET ~= nil, "the fleet is in this build") then return "abort" end
        ST.marks.s0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: up: GEOFON", 60, "s0", true, function(l) ST.check(l ~= nil, "GEOFON up", l) end)
    A.wait(10)
    A.do_(function()
        local sh = IFLEET.cur and IFLEET.cur.ships and IFLEET.cur.ships[1]
        local o = sh and sh.hull and sh.hull.obj
        if not ST.check(o ~= nil and valid(o), "GEOFON's hull") then return end
        C.o = o
        for _, e in ipairs(sh.parts or {}) do if valid(e.obj) then C.p = e.obj; C.pn = e.name; break end end
        local r = ST.at(o)
        local yaw = o:K2_GetActorRotation().Yaw
        C.at0, C.yaw = r, yaw
        C.to = { X = r.X + math.cos(math.rad(yaw)) * 200000, Y = r.Y + math.sin(math.rad(yaw)) * 200000, Z = r.Z }
        C.p0 = C.p and ST.at(C.p)
        local hit = {}
        local ok, err = pcall(function() o:K2_SetActorLocation(C.to, false, hit, true) end)
        ST.info(string.format("shipmove: from (%.0f, %.0f) to (%.0f, %.0f) along %.0f deg: K2_SetActorLocation %s", r.X / 100, r.Y / 100,
            C.to.X / 100, C.to.Y / 100, yaw, ok and "called" or ("FAILED " .. tostring(err))))
        C.t0 = os.clock()
    end)
    for _, t in ipairs({ 0.5, 2, 6, 15 }) do
        A.do_(function() C.waitTo = C.t0 + t end)
        A.until_(function() return os.clock() >= C.waitTo end, t + 5)
        A.do_(function()
            if not valid(C.o) then ST.info("shipmove: the hull's gone"); return end
            local l = ST.at(C.o)
            local v = C.o:GetVelocity()
            local dTo = math.sqrt((l.X - C.to.X) ^ 2 + (l.Y - C.to.Y) ^ 2) / 100
            local dFrom = math.sqrt((l.X - C.at0.X) ^ 2 + (l.Y - C.at0.Y) ^ 2) / 100
            local pl = C.p and valid(C.p) and ST.at(C.p)
            local pOff = pl and C.p0 and math.sqrt((pl.X - l.X - (C.p0.X - C.at0.X)) ^ 2 + (pl.Y - l.Y - (C.p0.Y - C.at0.Y)) ^ 2) / 100
            ST.info(string.format("shipmove: +%.1f s: the hull %.0f m from the new spot, %.0f m from the old; %.0f km/h; part %s %s",
                t, dTo, dFrom, math.sqrt(v.X * v.X + v.Y * v.Y) * 0.036, tostring(C.pn),
                pOff and string.format("%.0f m off its place on the hull", pOff) or "not read"))
            if t == 15 then
                ST.check(dTo < 1000, "the hull stayed at the new spot (within 1 km after 15 s)", string.format("%.0f m", dTo))
                ST.check(pOff == nil or pOff < 50, "its part went with it", pOff and string.format("%.0f m", pOff))
            end
        end)
    end
    A.picture("shipmove_after", function() return C.o and valid(C.o) and ST.off(ST.at(C.o), -40000, 30000, 15000) end,
        function() return C.o and valid(C.o) and ST.at(C.o) end, 60)
end

-- ((0.74.187) A6: Mission 13's LiveAIPathTeleportByDistanceExecution on GEOFON (RE_SV_IFProbeNear: Set 3000, _Far: Set
-- 300000): where it puts the hull (the distance's unit), and whether it sails on from there
SUITES.shipprobe = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFLEET ~= nil, "the fleet is in this build") then return "abort" end
        ST.marks.s0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: up: GEOFON", 60, "s0", true, function(l) ST.check(l ~= nil, "GEOFON up", l) end)
    A.wait(10)
    local function hull()
        local sh = IFLEET.cur and IFLEET.cur.ships and IFLEET.cur.ships[1]
        return sh and sh.hull and valid(sh.hull.obj) and sh.hull.obj or nil
    end
    for _, ev in ipairs({ "RE_SV_IFProbeNear", "RE_SV_IFProbeFar" }) do
        A.do_(function()
            local o = hull()
            if not ST.check(o ~= nil, "GEOFON's hull before " .. ev) then return end
            C.o, C.a = o, ST.at(o)
            C.yaw = o:K2_GetActorRotation().Yaw
            local r = SV_Event(ev)
            ST.info(string.format("shipprobe: %s fired (%s) at (%.0f, %.0f) m, heading %.0f", ev, tostring(r), C.a.X / 100, C.a.Y / 100, C.yaw))
            C.t0 = os.clock()
        end)
        for _, t in ipairs({ 1, 4, 10 }) do
            A.do_(function() C.waitTo = C.t0 + t end)
            A.until_(function() return os.clock() >= C.waitTo end, t + 5)
            A.do_(function()
                local o = hull()
                if not o then ST.info("shipprobe: no hull"); return end
                local l = ST.at(o)
                local dx, dy = (l.X - C.a.X) / 100, (l.Y - C.a.Y) / 100
                local y = math.rad(C.yaw)
                local along = dx * math.cos(y) + dy * math.sin(y)
                local v = o:GetVelocity()
                ST.info(string.format("shipprobe: %s +%d s: moved %.0f m (along its heading %+.0f m), heading now %.0f, %.0f km/h%s", ev, t,
                    math.sqrt(dx * dx + dy * dy), along, o:K2_GetActorRotation().Yaw, math.sqrt(v.X * v.X + v.Y * v.Y) * 0.036,
                    o ~= C.o and " (another object)" or ""))
            end)
        end
        A.picture("shipprobe_" .. ev:sub(12), function() local o = hull(); return o and ST.off(ST.at(o), -40000, 30000, 15000) end,
            function() local o = hull(); return o and ST.at(o) end, 60)
    end
end

-- ((0.74.188) A6: the rejoiner's catch-up RE_SV_IFAt_<kk> (every ship's lane path again, then Mission 13's path teleport by
-- distance to kk * 2 km): GEOFON there, sailing on forward along its lane, its parts with it, the formation's next ship too
-- ((0.74.191) A6 probe: RE_SV_IFVar<A-D> (GEOFON to point 2, then its lane again with one path arg changed): which one sails on
SUITES.fleetvar = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFLEET ~= nil and IFCOOP and IFCOOP.alongOf, "the fleet is in this build") then return "abort" end
        ST.marks.s0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: up: GEOFON", 60, "s0", true, function(l) ST.check(l ~= nil, "GEOFON up", l) end)
    A.wait(10)
    local function geo() local sh = IFLEET.cur and IFLEET.cur.ships and IFLEET.cur.ships[1]; return sh and sh.hull and valid(sh.hull.obj) and sh.hull.obj or nil end
    for _, tag in ipairs({ "A", "B", "C", "D" }) do
        A.do_(function()
            local r = SV_Event("RE_SV_IFVar" .. tag)
            C.t0, C.m = os.clock(), {}
            ST.info(string.format("fleetvar: %s fired (%s)", tag, tostring(r)))
        end)
        for _, t in ipairs({ 3, 9, 18 }) do
            A.do_(function() C.waitTo = C.t0 + t end)
            A.until_(function() return os.clock() >= C.waitTo end, t + 5)
            A.do_(function()
                local o = geo()
                if not o then return end
                local l = ST.at(o)
                local m = IFCOOP.alongOf(l.X, l.Y, 4000)
                C.m[t] = m
                ST.info(string.format("fleetvar: %s +%d s: %s m along, heading %.0f", tag, t, m and string.format("%.0f", m) or "off", o:K2_GetActorRotation().Yaw))
                if t == 18 then
                    local fwd = C.m[3] and m and m > C.m[3] + 50
                    ST.info(string.format("fleetvar: %s %s", tag, fwd and "SAILS ON FORWARD" or "back or stopped"))
                end
            end)
        end
    end
end

SUITES.fleetat = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFLEET ~= nil and IFCOOP and IFCOOP.alongOf, "the fleet and IFCOOP.alongOf are in this build") then return "abort" end
        ST.marks.s0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: up: GEOFON", 60, "s0", true, function(l) ST.check(l ~= nil, "GEOFON up", l) end)
    A.wait(10)
    local function ship(i)
        local sh = IFLEET.cur and IFLEET.cur.ships and IFLEET.cur.ships[i]
        return sh and sh.hull and valid(sh.hull.obj) and sh.hull.obj or nil, sh
    end
    A.do_(function()
        local m = IFCOOP.alongNow()
        ST.info(string.format("fleetat: GEOFON %.0f m along its lane before (alongNow)", m or -1))
        ST.check(m ~= nil and m < 1500, "alongNow near the start before", m)
    end)
    for _, kk in ipairs({ 2, 15 }) do                    -- ((0.74.190) by point: point kk, 0 the lane's first)
        local P = IFCOOP.coursePts()
        local want = P[kk + 1][3]
        A.do_(function()
            local r = SV_Event(string.format("RE_SV_IFPt_%02d", kk))
            ST.info(string.format("fleetat: RE_SV_IFPt_%02d fired (%s): point %d is %.0f m along counted from 0, %.0f m from 1", kk, tostring(r),
                kk, want, P[kk][3]))
            C.t0, C.prev = os.clock(), nil
            local o, sh = ship(1)
            C.part = nil
            for _, e in ipairs(sh and sh.parts or {}) do if valid(e.obj) then C.part = e.obj; break end end
        end)
        for _, t in ipairs({ 2, 8, 20 }) do
            A.do_(function() C.waitTo = C.t0 + t end)
            A.until_(function() return os.clock() >= C.waitTo end, t + 5)
            A.do_(function()
                local o = ship(1)
                if not o then ST.info("fleetat: no GEOFON"); return end
                local l = ST.at(o)
                local m = IFCOOP.alongOf(l.X, l.Y, want)
                local pl = C.part and valid(C.part) and ST.at(C.part)
                local pd = pl and math.sqrt((pl.X - l.X) ^ 2 + (pl.Y - l.Y) ^ 2) / 100
                local o2 = ship(2)
                local l2 = o2 and ST.at(o2)
                local d2 = l2 and math.sqrt((l2.X - l.X) ^ 2 + (l2.Y - l.Y) ^ 2) / 100
                ST.info(string.format("fleetat: %02d +%d s: GEOFON %s m along (want ~%.0f), heading %.0f; a part %s m from its hull; ship 2 %s m from it",
                    kk, t, m and string.format("%.0f", m) or "OFF the course", want, o:K2_GetActorRotation().Yaw,
                    pd and string.format("%.0f", pd) or "?", d2 and string.format("%.0f", d2) or "?"))
                if t == 2 then ST.check(m ~= nil and math.abs(m - want) < 400, string.format("%02d: GEOFON at ~%.0f m along", kk, want), m) end
                if t == 20 then
                    ST.check(m ~= nil and C.prev ~= nil and m > C.prev + 50, string.format("%02d: sailing on forward along its lane", kk),
                        string.format("%s -> %s", tostring(C.prev), tostring(m)))
                    ST.check(pd == nil or pd < 300, string.format("%02d: its part with it", kk), pd)
                end
                C.prev = m
            end)
        end
        A.picture("fleetat_" .. kk, function() local o = ship(1); return o and ST.off(ST.at(o), -40000, 30000, 15000) end,
            function() local o = ship(1); return o and ST.at(o) end, 60)
    end
end

SUITES.geofondeck = function()
    intoRun()
    local C = {}
    A.do_(function()
        if not ST.check(IFLEET ~= nil, "the fleet is in this build") then return "abort" end
        ST.marks.g0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: up: GEOFON", 60, "g0", true, function(l) ST.check(l ~= nil, "GEOFON up", l) end)
    A.wait(8)
    A.do_(function()
        local sh = IFLEET.cur and IFLEET.cur.ships and IFLEET.cur.ships[1]
        local o = sh and sh.hull and sh.hull.obj
        if not ST.check(o ~= nil and valid(o), "GEOFON's hull") then return end
        C.o = o
        local r = ST.at(o)
        local okB, ori, ext = pcall(function()
            local a, b = {}, {}
            o:GetActorBounds(false, a, b, false)
            return a, b
        end)
        C.root = r
        if okB and ori and ori.X then
            C.ctr = { X = ori.X, Y = ori.Y, Z = ori.Z }
            ST.info(string.format("geofondeck: root (%.0f, %.0f, %.0f) cm; bounds centre (%+.0f, %+.0f, %+.0f) m from it, extent (%.0f, %.0f, %.0f) m",
                r.X, r.Y, r.Z, (ori.X - r.X) / 100, (ori.Y - r.Y) / 100, (ori.Z - r.Z) / 100, ext.X / 100, ext.Y / 100, ext.Z / 100))
        else
            ST.info("geofondeck: bounds not read (" .. tostring(ori) .. ")")
        end
        pcall(function()
            local cls = StaticFindObject("/Script/Engine.StaticMeshComponent")
            o:K2_GetComponentsByClass(cls):ForEach(function(_, el)
                local c = el:get()
                local nm, l, e = "?", nil, nil
                pcall(function() nm = c:GetFName():ToString() end)
                pcall(function() local v = c:K2_GetComponentLocation(); l = { X = v.X, Y = v.Y, Z = v.Z } end)
                pcall(function() local b = c.Bounds; e = { X = b.BoxExtent.X, Y = b.BoxExtent.Y, Z = b.BoxExtent.Z }; l = { X = b.Origin.X, Y = b.Origin.Y, Z = b.Origin.Z } end)
                if l then
                    ST.info(string.format("geofondeck: mesh %s at (%+.0f, %+.0f, %+.0f) m from the root%s", nm, (l.X - r.X) / 100, (l.Y - r.Y) / 100,
                        (l.Z - r.Z) / 100, e and string.format(", extent (%.0f, %.0f, %.0f) m", e.X / 100, e.Y / 100, e.Z / 100) or ""))
                end
            end)
        end)
    end)
    A.picture("geofon_above_root", function() return C.root and ST.off(C.root, 0, 1, 60000) end, function() return C.root end, 60)
    A.picture("geofon_above_bounds", function() local c = C.ctr or C.root; return c and ST.off(c, 0, 1, 60000) end,
        function() return C.ctr or C.root end, 60)
    A.picture("geofon_side", function() local c = C.ctr or C.root; return c and ST.off(c, -30000, 30000, 8000) end,
        function() return C.ctr or C.root end, 50)
end

SUITES.aegislasers = function()
    intoRun()
    local C = {}
    local function raven()
        for _, sh in ipairs(IFLEET.cur and IFLEET.cur.ships or {}) do
            if sh.name == "RAVEN" and sh.hull and valid(sh.hull.obj) then return sh end
        end
    end
    A.do_(function()
        if not ST.check(IFLEET ~= nil and IFLASER ~= nil, "the fleet's lasers are in this build (sv_fleet_lasers)") then return "abort" end
        ST.marks.m0 = ST.n
        ST.press("N")
    end)
    A.log_("fleet: Ctrl%+N: %d+ of %d+ ships up", 60, "m0", false, function(l)
        ST.check(l ~= nil and l:find("59 parts", 1, true) ~= nil, "every ship up, 59 parts (each Aegis 4 + its 2 lasers, RAVEN's EW mast)", l)
    end)
    A.wait(8)
    A.do_(function()
        local n, lines = 0, {}
        for i = ST.marks.m0 + 1, ST.n do
            local l = ST.lines[i]
            if l and l:find("^fleet lasers: ") then n = n + 1; lines[#lines + 1] = l end
        end
        ST.check(n == 5 and table.concat(lines, "\n"):find("NOT", 1, true) == nil and table.concat(lines, "\n"):find("2 mounts handed", 1, true) ~= nil,
            "every Aegis (5): its 2 mounts handed to AC7's LaserInterceptor", lines[1])
        local carry = 0
        for i = ST.marks.m0 + 1, ST.n do
            local l = ST.lines[i]
            if l and l:find("carries AC7's LaserInterceptor", 1, true) and l:find("Tani_LASER", 1, true) then carry = carry + 1 end
        end
        ST.check(carry >= 10, "each of the 10 mounts carries its laser (sv_escort_li.lua)", carry .. " lines")
        local sh = raven()
        C.sh = sh
        if not sh then ST.info("aegislasers: RAVEN not found"); return end
        for _, e in ipairs(sh.parts) do
            if e.cls:find("Tani_LASER", 1, true) then C.mount = C.mount or e end
            ST.info(string.format("aegislasers: RAVEN part %s %s health %s", e.cls, e.name:match("([^%.:]+)$") or "?", tostring(ST.healthOf(e.obj))))
        end
    end)
    local function hull() return C.sh and C.sh.hull and C.sh.hull.obj end
    A.picture("aegis_side", function() return ST.frame(hull(), 0, 13000, 4000) end, function() return ST.at(hull()) end, 60)
    -- ((run 91: framed off the hull, the pictures missed the mounts) each mount looked at itself, from its side and above)
    local function mountAt(where)
        for _, e in ipairs(C.sh and C.sh.parts or {}) do
            local nm
            pcall(function() nm = e.obj.RootComponent:GetAttachParent():GetFName():ToString() end)
            if nm == where and valid(e.obj) then return e.obj end
        end
    end
    A.picture("aegis_bow", function() local m = mountAt("LASER_BOW"); return m and ST.off(ST.at(m), 2500, 3500, 1800) end,
        function() local m = mountAt("LASER_BOW"); return m and ST.at(m) end, 35)
    A.picture("aegis_stern", function() local m = mountAt("LASER_AFT"); return m and ST.off(ST.at(m), -2500, 3500, 1800) end,
        function() local m = mountAt("LASER_AFT"); return m and ST.at(m) end, 35)
    -- ((0.74.162) the beams' width: every laser's volley on command (Ctrl+['s ESC.testLaser), the bow's beams pictured)
    A.do_(function()
        ST.marks.lz = ST.n
        if not ST.check(ESC ~= nil and ESC.testLaser ~= nil, "the lasers' volley on command (ESC.testLaser)") then return end
        pcall(ESC.testLaser)
    end)
    A.log_("fires a volley", 5, "lz", true, function(l)
        ST.check(l ~= nil and l:find("copies round it", 1, true) ~= nil, "a volley's beam drawn with its copies round it (li_beam_w)", l)
    end)
    A.picture("aegis_beam_bow", function() local m = mountAt("LASER_BOW"); return m and ST.off(ST.at(m), 1500, 2500, 900) end,
        function() local m = mountAt("LASER_BOW"); return m and ST.at(m) end, 40)
    A.picture("aegis_beam_far", function() local m = mountAt("LASER_BOW"); return m and ST.off(ST.at(m), 6000, 9000, 3000) end,
        function() local m = mountAt("LASER_BOW"); return m and ST.at(m) end, 40)
    A.do_(function()
        for _, w in ipairs({ "LASER_BOW", "LASER_AFT" }) do
            local m = mountAt(w)
            local h = C.sh and C.sh.hull and C.sh.hull.obj
            if m and h then
                local mp, hp = ST.at(m), ST.at(h)
                ST.info(string.format("aegislasers: RAVEN %s at %.0f / %.0f / %.0f cm from its hull's origin (world)", w, mp.X - hp.X, mp.Y - hp.Y, mp.Z - hp.Z))
            end
        end
    end)
    A.do_(function()
        if not (C.mount and valid(C.mount.obj)) then ST.info("aegislasers: no mount to shoot off"); return end
        C.before = #(IFLASER.carriers and IFLASER.carriers() or {})
        local okF, dead = pcall(finishUnpaid, C.mount.obj)
        ST.info(string.format("aegislasers: a mount finished: %s %s (carriers before %d)", tostring(okF), tostring(dead), C.before))
    end)
    A.wait(3)
    A.do_(function()
        local after = #(IFLASER.carriers and IFLASER.carriers() or {})
        ST.check(C.before ~= nil and after == C.before - 1, "a mount shot off: its laser gone", tostring(C.before) .. " -> " .. after)
        ST.shot("aegis_mount_down")
    end)
    A.wait(2)
end
-- (2026-11-17) hudprobe: which way really hides the game's HUD (the user: "during the cutscenes ... we need to disable the
-- HUD"; run 20261116_222923: distortion "took" and hid nothing). Each of sv_cine.lua's routes alone (CINE.hudTry) and the
-- cheat manager's other switches, a picture each; then the fleet's surfacing (Ctrl+N), pictures mid-way: the HUD held.
SUITES.hudprobe = function()
    intoRun()
    A.wait(3)
    A.do_(function()
        if not ST.check(CINE ~= nil and CINE.hudTry ~= nil, "sv_cine's HUD routes are in this build") then return "abort" end
        ST.shot("hud_00_base")
    end)
    for i, r in ipairs({ "widgets", "cheatnew", "showhud", "distortion" }) do
        A.do_(function() local ok, why = CINE.hudTry(r, 20); ST.info(string.format("hudprobe: %s: %s %s", r, tostring(ok), tostring(why))) end)
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("hud_%02d_%s", i, r)) end)
        A.do_(function() CINE.hudShow("probe", "the probe's next") end)
        A.wait(1.5)
    end
    local CM = {}
    for i, call in ipairs({ { "SetDisplayHUD", false, true }, { "SetShowHUDAll", false, true }, { "ChangeHUDType", 8, 3 }, { "ToggleDisplayHUD" } }) do
        A.do_(function()
            CM.o = CINE.cheatMake and CINE.cheatMake()
            if not CM.o then ST.info("hudprobe: no cheat manager made"); return end
            local ok, err = pcall(function() if call[2] == nil then CM.o[call[1]](CM.o) else CM.o[call[1]](CM.o, call[2]) end end)
            ST.info(string.format("hudprobe: cheat manager %s(%s): %s %s", call[1], tostring(call[2]), tostring(ok), tostring(err)))
        end)
        A.wait(1.5)
        A.do_(function() ST.shot(string.format("hud_%02d_cm_%s", 10 + i, call[1])) end)
        A.do_(function()
            if CM.o then pcall(function() if call[3] == nil then CM.o[call[1]](CM.o) else CM.o[call[1]](CM.o, call[3]) end end) end
        end)
        A.wait(1.5)
    end
    A.do_(function() ST.shot("hud_20_back"); ST.marks.s0 = ST.n; ST.press("N") end)
    A.log_("fleet surfacing: %d+ ships rise over", 20, "s0", false, function(l)
        ST.check(l ~= nil and l:find("the HUD held", 1, true) ~= nil, "the surfacing holds the HUD", l)
    end)
    for i = 1, 4 do
        A.wait(4)
        A.do_(function() ST.shot(string.format("hud_3%d_surfacing", i)) end)
    end
    A.log_("fleet surfacing: over", 40, "s0", false, function(l) ST.check(l ~= nil, "the surfacing over", l) end)
    A.wait(3)
    A.do_(function()
        ST.shot("hud_40_after")
        ST.check(ST.findLog("hud: the fleet's surfacing let go", ST.marks.s0, true) ~= nil, "Survival's HUD let go after it")
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

-- ((2026-11-22) the user: "do an automated test on Valka's round", "look into why she seems to fight in one place, she
-- doesn't seem to take the fight anywhere and just flies around in one spot", "screenshots of everything") VALKA's round
-- forced (her disguise off: config_valka.lua, so she comes at once, alone), her fight tracked every 0.5 s
-- (`valka-track:` lines; her events `valka-ev:`; tools/autotest/valka_track.py reads them): phase A your plane round the
-- airfield, B a 30 km leg west (ST.apCentre: does she take the fight with you?), C round there; pictures in each phase.
-- conf valka_a_s / valka_c_s: the circling phases' lengths (s); valka_leg_km: phase B's leg.
local VT = { n = 0, ev = {}, at = -1, from = nil, phase = "-", samples = 0, hooked = false, d = {} }
local function vtVel(x)
    local ok, v = pcall(function() local q = x:GetVelocity(); return { X = q.X, Y = q.Y, Z = q.Z } end)
    return ok and v or nil
end
local function vtKmh(v) return v and math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) * 0.036 or -1 end
local function vtHer() return glitchActor and glitchActor(CFG.specials.valka) or nil end
local function vtSample(now, s)
    if now - VT.at < 0.5 then return end
    VT.at = now
    local o = vtHer()
    local you = playerLocation and playerLocation()
    local pl = ST.plane()
    local her = o and where(o)
    if not her and not (s and s.state) then return end
    VT.from = VT.from or now
    local nose = -1
    if o and her and you then
        local okF, f = pcall(function() local q = o:GetActorForwardVector(); return { X = q.X, Y = q.Y, Z = q.Z } end)
        local tx, ty, tz = you.X - her.X, you.Y - her.Y, you.Z - her.Z
        local n = math.sqrt(tx * tx + ty * ty + tz * tz)
        if okF and n > 0 then nose = math.deg(math.acos(math.max(-1, math.min(1, (f.X * tx + f.Y * ty + f.Z * tz) / n)))) end
        VT.d[VT.phase] = VT.d[VT.phase] or { n = 0, sum = 0 }
        VT.d[VT.phase].n, VT.d[VT.phase].sum = VT.d[VT.phase].n + 1, VT.d[VT.phase].sum + n / 100000
    end
    local function p3(p) return p and string.format("%.0f %.0f %.0f", p.X / 100, p.Y / 100, p.Z / 100) or "- - -" end
    VT.samples = VT.samples + 1
    local hp = nil
    if o then hp = ST.healthOf(o) end
    log(string.format("valka-track: %.1f %s %s her %s v %.0f you %s v %.0f nose %.0f hp %s", now - VT.from, VT.phase,
        tostring(s and s.state), p3(her), vtKmh(o and vtVel(o)), p3(you), vtKmh(pl and vtVel(pl)), nose, tostring(hp)))
end
local function vtHook()
    if VT.hooked then return true end
    if not (SPC and SPC.valkaTick and SPC.V and SPC.V.event) then return false end
    VT.hooked = true
    local origTick, origEv = SPC.valkaTick, SPC.V.event
    SPC.valkaTick = function(now, s, ...)
        local r = origTick(now, s, ...)
        local ok, err = pcall(vtSample, os.clock(), s)
        if not ok and not VT.errSaid then VT.errSaid = true; ST.info("valka track error " .. tostring(err)) end
        return r
    end
    SPC.V.event = function(ev, ...)
        local e = tostring(ev)
        local k = e:find("^RE_SV_ValkaTp_") and "Tp" or e:gsub("^RE_SV_Valka", "")
        VT.ev[k] = (VT.ev[k] or 0) + 1
        VT.n = VT.n + 1
        log(string.format("valka-ev: %.1f %s %s", os.clock() - (VT.from or os.clock()), VT.phase, e))
        return origEv(ev, ...)
    end
    return true
end
local function vtCounts()
    local t = {}
    for k, v in pairs(VT.ev) do t[#t + 1] = k .. " " .. v end
    table.sort(t)
    return table.concat(t, ", ")
end
-- the pictures of her: chase (behind her), wide (beside the two of you), top (over the fight)
local function vtPictures(tag)
    local function her() return vtHer() end
    local function mid()
        local h, y = ST.at(her()), playerLocation()
        return { X = (h.X + y.X) / 2, Y = (h.Y + y.Y) / 2, Z = (h.Z + y.Z) / 2 }
    end
    A.picture("valka_" .. tag .. "_chase", function() return ST.frame(her(), -9000, 1500, 2000) end,
        function() return ST.at(her()) end, 55)
    A.picture("valka_" .. tag .. "_wide", function()
        local h, y, m = ST.at(her()), playerLocation(), mid()
        local dx, dy = y.X - h.X, y.Y - h.Y
        local n = math.max(1, math.sqrt(dx * dx + dy * dy))
        local side = math.max(150000, n * 0.9)
        return { X = m.X - dy / n * side, Y = m.Y + dx / n * side, Z = m.Z + 40000 }
    end, mid, 60)
    -- (high behind you, both in view: the run of 13:00 showed a straight-down camera keeps a level view)
    A.picture("valka_" .. tag .. "_high", function()
        local h, y = ST.at(her()), playerLocation()
        local dx, dy = y.X - h.X, y.Y - h.Y
        local n = math.max(1, math.sqrt(dx * dx + dy * dy))
        local back = math.max(150000, n * 0.6)
        return { X = y.X + dx / n * back, Y = y.Y + dy / n * back, Z = y.Z + math.max(80000, n * 0.5) }
    end, mid, 70)
end
-- her portal (CFG.specials.valka.portal, D.special.portal): a spot dist_m in front of its face, side_m to its right, up_m
local function vtPortal() local s = D and D.special; return s and s.portal end
local function vtPortalCam(dist_m, side_m, up_m)
    local P = vtPortal()
    if not P then return nil end
    local r = math.rad(P.yaw)
    return { X = P.at.X + math.cos(r) * dist_m * 100 - math.sin(r) * side_m * 100,
             Y = P.at.Y + math.sin(r) * dist_m * 100 + math.cos(r) * side_m * 100, Z = P.at.Z + up_m * 100 }
end
local function vtPortalShot(name)
    A.do_(function() ST.shot(name) end)
    A.wait(2.2)
end
SUITES.valka = function()
    intoRun()
    local aS, cS = tonumber(ST.conf.valka_a_s) or 90, tonumber(ST.conf.valka_c_s) or 60
    local legKm = tonumber(ST.conf.valka_leg_km) or 30
    A.do_(function()
        local c = CFG.specials and CFG.specials.valka
        if not ST.check(c ~= nil and c.enabled ~= false and SPC and SPC.valkaTick ~= nil, "VALKA is in this build") then return "abort" end
        ST.check(c.disguise == false, "her disguise off (config_valka.lua): she comes at once, alone", tostring(c.disguise))
        ST.check(vtHook(), "her round's tick and events watched (valka-track / valka-ev lines)")
        ST.info(string.format("her settings: engage_every_s %s, turn_every_s %s, post_stall_every_s %s (within %s km), blink_s %s "
            .. "every %s, spots %s, railgun_every_s %s within %s km; luaset %s, pilot_rank %s, speed_x %s, chase %s, portal %s",
            tostring(c.engage_every_s), tostring(c.turn_every_s),
            tostring(c.post_stall_every_s), tostring(c.post_stall_range_km), tostring(c.blink_s), tostring(c.blink_every_s),
            c.spots and #c.spots or 0, tostring(c.railgun_every_s), tostring(c.railgun_range_km), tostring(c.luaset),
            tostring(c.pilot_rank), tostring(c.speed_x), tostring(c.chase), tostring(type(c.portal) == "table" and c.portal.enabled)))
        local row = ST.findLog("special: VALKA (", 0, true) or ST.findLog("special: VALKA keeps", 0, true)
        if c.luaset then ST.check(row ~= nil and row:find("flies", 1, true) ~= nil, "her row flies her own behaviour set", row) end
        ST.info("her row: " .. tostring(ST.findLog("special: VALKA's row", 0, true)))
    end)
    if ST.conf.portal_probe and ST.ppAll then ST.ppAll(ST.conf.portal_only) end   -- (the portal's pieces first: portalprobe)
    A.do_(function()
        ST.marks.v0 = ST.n
        D.forceSpecial = "valka"                          -- (Ctrl+8's own: the next round hers, in 3 s)
        if D.state == "wait" then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
        ST.info(string.format("her round forced: round %d, state %s", (D.round or 0) + 1, tostring(D.state)))
        ST.doing = "VALKA's opener"
    end)
    A.log_("special: VALKA's railgun up", 90, "v0", true, function(l) ST.check(l ~= nil, "her opener's railgun up", l) end)
    -- ((2026-11-22) her portal: open with the opener's charge, her shot and she come out of it, it closes)
    A.log_("special: VALKA's portal opens", 12, "v0", true, function(l)
        ST.marks.portal = l and true or nil
        if type(CFG.specials.valka.portal) == "table" and CFG.specials.valka.portal.enabled then
            ST.check(l ~= nil, "her portal opens with her opener's charge", l)
        end
    end)
    -- ((2026-11-22) the user: "Create a cutscene similar to the Invincible Fleets Arrival of the Portal Opening, and Valka
    -- coming out of it": sv_valka_cine.lua films it; pictures through it 0.8 s apart, no camera of ours)
    A.do_(function()
        if VCINE then VCINE.after = function() HOLD.ap, HOLD.apOn = 0, nil end end   -- (our autopilot back after it)
        local on = VCINE and VCINE.active and VCINE.active()
        ST.marks.cine = on or nil
        ST.check(on == true, "her cutscene films her portal's opening", ST.findLog("special: VALKA's cutscene: starts", ST.marks.v0))
    end)
    for k = 1, 19 do
        A.do_(function()
            local st = VCINE and VCINE.state and VCINE.state()
            if st then ST.shot(string.format("cine_%02d_shot%d", k, st.shot or 0))
            elseif k == 1 then ST.shot("portal_nocine") end
        end)
        A.wait(0.8)
    end
    A.log_("special: VALKA's opener shot from", 40, "v0", true, function(l) ST.check(l ~= nil, "her opener's shot", l) end)
    A.log_("special: VALKA shows", 30, "v0", true, function(l)
        if not ST.check(l ~= nil, "VALKA shows (her reveal)", l) then return "abort" end
        VT.phase = "R"
    end)
    A.log_("special: VALKA comes out", 5, "v0", true, function(l)
        local m = l and tonumber(l:match("comes out (%d+) m"))
        ST.check(m ~= nil and m < 1000, "she comes out of her portal's middle (within 1 km of it at her reveal)", l)
    end)
    A.log_("special: VALKA's cutscene: over", 20, "v0", true, function(l)
        ST.check(l ~= nil and l:find("your view and plane back", 1, true) ~= nil, "her cutscene ends, your view and plane back", l)
    end)
    A.wait(0.5)
    A.do_(function() ST.shot("cine_after_yourview") end)
    A.do_(function()                                      -- (its closing, if it's still closing: from in front)
        local P = vtPortal()
        if P then ST.look(vtPortalCam(3600, 600, 0), P.at, 45) end
    end)
    A.wait(0.3)
    for k = 1, 2 do
        A.do_(function() if vtPortal() then ST.shot("portal_close_" .. k) end end)
        A.wait(0.9)
    end
    A.do_(function() ST.lookBack() end)
    A.wait(2.5)
    A.do_(function()
        ST.check(vtPortal() == nil, "her portal closed after she was through",
            ST.findLog("special: VALKA's portal closed", ST.marks.v0, true) or (vtPortal() and vtPortal().phase))
    end)
    A.do_(function() VT.phase = "A"; ST.doing = "phase A: round the airfield"; ST.info("phase A: your plane round the airfield, " .. aS .. " s") end)
    A.wait(8)
    vtPictures("a")
    A.wait(math.max(5, aS - 30))
    A.do_(function()
        ST.info("phase A over: her events " .. vtCounts())
        VT.phase = "B"
        ST.apCentre = { X = AIRFIELD.X - legKm * 100000, Y = AIRFIELD.Y }
        ST.doing = "phase B: a leg west"
        ST.info(string.format("phase B: your plane's circle moved %d km west: a leg there", legKm))
    end)
    A.wait(25)
    vtPictures("b")
    A.until_(function()
        local y = playerLocation()
        return y and math.sqrt((y.X - ST.apCentre.X) ^ 2 + (y.Y - ST.apCentre.Y) ^ 2) < 700000
    end, 200, function(v)
        ST.info("phase B over: " .. (v and "your plane at the new circle" or "200 s, not there yet") .. "; her events " .. vtCounts())
        VT.phase = "C"
        ST.doing = "phase C: round the new spot"
    end)
    A.wait(10)
    vtPictures("c")
    -- ((2026-11-22) her blinks start when she's hit: two small hits (10 HP of her health each), 20 s apart)
    for k = 1, 2 do
        A.do_(function()
            local o = vtHer()
            local h = o and ST.healthOf(o)
            if h and h > 200 then pcall(function() o.HealthInternal = h - 100 end) end
            ST.marks["hit" .. k] = ST.n
            ST.info(string.format("a hit on her (%s -> %s)", tostring(h), tostring(o and ST.healthOf(o))))
        end)
        A.log_("special: VALKA hit", 3, "hit" .. k, true, function(l) ST.check(l ~= nil, "she blinks when hit (" .. k .. ")", l) end)
        -- ((2026-11-22) her blink portals: a camera beside where she comes back, 0.6 s on)
        A.wait(0.4)
        A.do_(function()
            local o = vtHer()
            if o then ST.look(ST.frame(o, 30000, 30000, 0), ST.at(o), 55) end
        end)
        A.wait(0.3)
        A.do_(function()
            local s = D and D.special
            ST.shot("valka_blink_" .. k)
            ST.info("her blink portals up: " .. tostring(s and s.bportals and #s.bportals or 0))
        end)
        A.wait(2.2)
        A.do_(function() ST.lookBack() end)
        A.wait(3)
        A.do_(function()
            local b = {}
            for i = ST.marks["hit" .. k] + 1, ST.n do
                local s = ST.lines[i]
                if s and s:find("^special: VALKA blink") then b[#b + 1] = s:gsub("^special: ", "") end
            end
            ST.check(#b > 0, "her blinks after hit " .. k .. " put her somewhere new", table.concat(b, " | "))
        end)
        A.wait(10)
    end
    A.wait(math.max(5, cS - 20))
    A.do_(function()
        local s = D and D.special
        ST.info("phase C over: her events " .. vtCounts())
        local parts = {}
        for _, ph in ipairs({ "A", "B", "C" }) do
            local d = VT.d[ph]
            parts[#parts + 1] = string.format("%s %s", ph, d and d.n > 0 and string.format("%.1f km", d.sum / d.n) or "-")
        end
        ST.info("her mean distance from you by phase: " .. table.concat(parts, ", "))
        ST.check(VT.samples >= 100, "her fight tracked", VT.samples .. " samples")
        ST.check(vtHer() ~= nil, "she's still up at the end (nobody shoots her in this test)", s and tostring(s.state))
        ST.apCentre = nil
    end)
end

-- ((2026-11-22) the user: "try to build a 3D Portal, an event horizon that she spawns out of") the game's own pieces a
-- portal could be made of, one at a time at a spot 9 km north of the runway, 3 km up, photographed by a camera of ours
-- and taken away: meshes (the engine's basic shapes, rings) with the game's VFX materials (each instance's parameters
-- logged: `portal-mat:`), and Niagara systems (a picture as each starts and one 2.5 s on). conf portal_only: a comma
-- list of piece names (the others skipped).
local PP = { at = nil, actor = nil, fx = {} }
local function ppPath(p) return p:find("%.") and p or (p .. "." .. p:match("[^/]+$")) end
local function ppSpot() return { X = AIRFIELD.X, Y = AIRFIELD.Y - 900000, Z = 300000 } end
local function ppCam(dist_m, up_m) local s = ppSpot(); return { X = s.X, Y = s.Y + dist_m * 100, Z = s.Z + (up_m or 0) * 100 } end
local function ppMatParams(mi, name)
    local parts = {}
    for _, k in ipairs({ "ScalarParameterValues", "VectorParameterValues", "TextureParameterValues" }) do
        pcall(function()
            mi[k]:ForEach(function(_, e)
                local v = e:get()
                local n = "?"
                pcall(function() n = v.ParameterInfo.Name:ToString() end)
                local val = "?"
                if k == "ScalarParameterValues" then pcall(function() val = string.format("%.3g", v.ParameterValue) end)
                elseif k == "VectorParameterValues" then pcall(function() local c = v.ParameterValue; val = string.format("(%.2g %.2g %.2g %.2g)", c.R, c.G, c.B, c.A) end)
                else pcall(function() val = (v.ParameterValue:GetFullName():match("([^%./ ]+)$") or "?") end) end
                parts[#parts + 1] = k:sub(1, 1) .. ":" .. n .. "=" .. val
            end)
        end)
    end
    local parent = "?"
    pcall(function() parent = mi.Parent:GetFullName():match("([^%./ ]+)$") or "?" end)
    log(string.format("portal-mat: %s (parent %s): %s", name, parent, #parts > 0 and table.concat(parts, ", ") or "no overrides read"))
end
local function ppClear()
    if PP.actor and valid(PP.actor) then pcall(function() PP.actor:K2_DestroyActor() end) end
    PP.actor = nil
    for _, c in ipairs(PP.fx) do pcall(function() c:DeactivateImmediate() end); pcall(function() c:K2_DestroyComponent(c) end) end
    PP.fx = {}
end
local function ppActor(at)
    local gs, cls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.Actor")
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local a = gs:BeginDeferredActorSpawnFromClass(ST.pc(), cls, t, 1, nil, 1)
    return gs:FinishSpawningActor(a, t, 1)
end
-- a mesh piece: mesh `mesh` sized size_m across (its bounds' sphere), squashed by flat (its Z scale x flat), turned by
-- rot (Pitch, Yaw, Roll), its material(s) `mat` (nil: its own) as a dynamic instance with params set
local function ppMesh(name, mesh, mat, size_m, flat, rot, params, stack)
    ppClear()
    local at = ppSpot()
    local a = ppActor(at)
    if not valid(a) then ST.info("portal piece " .. name .. ": no actor"); return end
    PP.actor = a
    local smc = StaticFindObject("/Script/Engine.StaticMeshComponent")
    local nStack = stack and tonumber(stack[1]) or 1
    for si = 1, nStack do
    local comp = a:AddComponentByClass(smc, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    local m, why = loadObject(ppPath(mesh))
    if not valid(m) then ST.info("portal piece " .. name .. ": mesh not loaded (" .. tostring(why) .. ")"); return end
    pcall(function() comp:SetStaticMesh(m) end)
    local r = 100
    pcall(function() r = m:GetBounds().SphereRadius end)
    local k = (size_m * 100 / 2) / math.max(1, r)
    pcall(function() comp:SetCollisionEnabled(0) end)
    pcall(function() comp:SetWorldScale3D({ X = k, Y = k, Z = k * (flat or 1) }) end)
    local o = (si - 1)
    local sx, sy, sz = stack and (tonumber(stack[2]) or 0) * 100 * o or 0, stack and (tonumber(stack[3]) or 0) * 100 * o or 0,
        stack and (tonumber(stack[4]) or 0) * 100 * o or 0
    pcall(function() comp:K2_SetWorldLocation({ X = at.X + sx, Y = at.Y + sy, Z = at.Z + sz }, false, {}, true) end)
    if rot then pcall(function() comp:K2_SetWorldRotation(rot, false, {}, true) end) end
    local nmat = 0
    pcall(function() nmat = comp:GetNumMaterials() end)
    local own = {}
    for i = 0, nmat - 1 do pcall(function() own[#own + 1] = comp:GetMaterial(i):GetFullName():match("([^%./ ]+)$") end) end
    local said = "its own (" .. table.concat(own, ", ") .. ")"
    if mat then
        local mi, whyM = loadObject(ppPath(mat))
        if valid(mi) then
            ppMatParams(mi, mat:match("[^/]+$"))
            local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
            local okM, mid = pcall(function() return kml:CreateDynamicMaterialInstance(ST.pc(), mi, FName("None"), 0) end)
            if okM and valid(mid) then
                for pn, v in pairs(params or {}) do
                    if type(v) == "number" then pcall(function() mid:SetScalarParameterValue(FName(pn), v) end)
                    elseif type(v) == "table" then pcall(function() mid:SetVectorParameterValue(FName(pn), { R = v[1], G = v[2], B = v[3], A = v[4] or 1 }) end)
                    else local tx = loadObject(ppPath(v)); if valid(tx) then pcall(function() mid:SetTextureParameterValue(FName(pn), tx) end) end end
                end
                for i = 0, math.max(0, nmat - 1) do pcall(function() comp:SetMaterial(i, mid) end) end
                said = mat:match("[^/]+$")
            else said = "its own (" .. mat:match("[^/]+$") .. "'s instance NOT made)" end
        else said = "its own (" .. mat:match("[^/]+$") .. " NOT loaded: " .. tostring(whyM) .. ")" end
    end
    for i = 0, nmat - 1 do pcall(function() local mm = comp:GetMaterial(i); if mm and i == 0 then ppMatParams(mm, "slot 0 of " .. name) end end) end
    if si == 1 then
        ST.info(string.format("portal piece %s: %s (bounds radius %.0f cm, x%.1f -> %d m), %d material slot(s), %s%s", name,
            mesh:match("[^/]+$"), r, k, size_m, nmat, said, nStack > 1 and (", " .. nStack .. " overlapping copies") or ""))
    end
    end
end
local function ppNiagara(name, sys, scale)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local s, why = loadObject(ppPath(sys))
    if not valid(s) then ST.info("portal piece " .. name .. ": system not loaded (" .. tostring(why) .. ")"); return end
    local ok, comp = pcall(function()
        return lib:SpawnSystemAtLocation(ST.pc(), s, ppSpot(), { Pitch = 0, Yaw = 0, Roll = 0 }, { X = scale, Y = scale, Z = scale },
            true, true, 0, true)
    end)
    if ok and comp then PP.fx[#PP.fx + 1] = comp end
    ST.info(string.format("portal piece %s: %s x%.1f %s", name, sys:match("[^/]+$"), scale, ok and comp and "spawned" or ("NOT spawned: " .. tostring(comp))))
end
local PP_PIECES = {
    { "ring_mgf", "mesh", "/Game/Environments/MegaFloat/Base/Mesh/SM_MGF_MagneticControlRing002_I07", nil, 220 },
    { "ring_mgf_glow", "mesh", "/Game/Environments/MegaFloat/Base/Mesh/SM_MGF_MagneticControlRing002_I07", "/Game/VFX/Mission/Traning/MI_TrainingRingGlow", 220 },
    { "ring_elevator", "mesh", "/Game/Environments/City/Unique/Map15/Mesh/SM_UNI_OrbitElevatorRing002_I22", nil, 220 },
    { "ring_elevator_glow", "mesh", "/Game/Environments/City/Unique/Map15/Mesh/SM_UNI_OrbitElevatorRing002_I22", "/Game/VFX/Mission/Traning/MI_TrainingRingGlow", 220 },
    { "ring_training", "mesh", "/Game/Environments/MegaFloat/Base/Mesh/SM_MGF_MagneticControlRingParts001_I07", "/Game/VFX/Mission/Traning/MI_TrainingRing", 220 },
    { "sphere_refraction", "mesh", "/Engine/BasicShapes/Sphere", "/Game/VFX/Mission/Mission027/CoreDestroy/MI_CoreDest_ShockDomeRefraction001", 180 },
    { "sphere_blacksmoke", "mesh", "/Engine/BasicShapes/Sphere", "/Game/VFX/Mission/Mission027/CoreDestroy/MI_CoreDest_AfterExitBlackSmokeMesh", 180 },
    { "sphere_barrier", "mesh", "/Engine/BasicShapes/Sphere", "/Game/VFX/Vehicles/Weapon/UAV/Barrier/MI_Distortion", 180 },
    { "disc_black", "mesh", "/Engine/BasicShapes/Cylinder", "/Engine/BasicShapes/BasicShapeMaterial", 180, 0.03, { Pitch = 0, Yaw = 0, Roll = 90 }, { Color = { 0, 0, 0, 1 } } },
    { "disc_glow", "mesh", "/Engine/BasicShapes/Cylinder", "/Game/VFX/Mission/Traning/MI_TrainingRingGlow", 180, 0.03, { Pitch = 0, Yaw = 0, Roll = 90 } },
    { "circle_glow", "mesh", "/Game/VFX/ResourceAsset/Mesh/Splash/SM_Circle002_IE03", "/Game/VFX/Mission/Traning/MI_TrainingRingGlow", 220, 1, { Pitch = 0, Yaw = 0, Roll = 90 } },
    { "plasma", "fx", "/Game/VFX/Mission/Mission027/CoreDestroy/NS_MGF_CoreDest1st_CoreElectricPlasma", 3 },
    { "maingun_charge", "fx", "/Game/VFX/Mission/Mission010/GR036/MainCannon/NS_Maingun_Charge_Electric_1set", 6 },
    { "maingun_base", "fx", "/Game/VFX/Mission/Mission010/GR036/MainCannon/NS_Maingun_Charge_Base", 6 },
    { "charge_electric", "fx", "/Game/VFX/IGC/Ms10/Ms100010/NS_IGCVFX_Ms100010_ChargeElectric001", 6 },
    { "shockwave25", "fx", "/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_ShockWave001", 3 },
    { "shockwave29", "fx", "/Game/VFX/IGC/Ms29/Ms290030/NS_IGCVFX_Ms290030_ShockWave001", 3 },
    { "discharge", "fx", "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricDischargeM001", 20 },
    { "farflash", "fx", "/Game/VFX/Mission/Mission023/NS_ms23FarFlash", 2 },
    -- (2026-11-22, the second probe: the materials' colours, and arcs / lightning for the rim)
    { "ring_training_red", "mesh", "/Game/Environments/MegaFloat/Base/Mesh/SM_MGF_MagneticControlRingParts001_I07", "/Game/VFX/Mission/Traning/MI_TrainingRing",
      220, 1, { Pitch = 0, Yaw = 0, Roll = 90 }, { Color = { 5, 0.2, 0.4, 1 } } },
    { "lens_purple", "mesh", "/Engine/BasicShapes/Sphere", "/Game/VFX/Mission/Traning/MI_TrainingRingGlow", 200, 0.22,
      { Pitch = 0, Yaw = 0, Roll = 90 }, { Color = { 0.75, 0.1, 1.0, 1 }, EmissiveIntensity = 60, Opacity = 0.5, EmissiveFresnelFalloff = 3 } },
    { "sign", "fx", "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricSign001", 40 },
    { "lightning", "fx", "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning", 3 },
    { "shock1", "fx", "/Game/VFX/IGC/Ms10/Ms100010/NS_IGCVFX_Ms100010_Shock1", 6 },
    { "spark29", "fx", "/Game/VFX/IGC/Ms29/Ms290025/NS_IGCVFX_Ms290025_Spark001", 10 },
    { "plasma_big", "fx", "/Game/VFX/Mission/Mission027/CoreDestroy/NS_MGF_CoreDest1st_CoreElectricPlasma", 10 },
    -- ((2026-11-22) the user: "isn't there like a moving texture we could use?" (no material of ours: hard rule 58) AC8's
    -- animated materials on our own disk (tools/valka_portal), facing the camera: does a texture move on it?)
}
do
    local DISK = "/Game/Mods/SurvivalMode/ValkaPortal/Model/SM_SV_BHDiskHot"
    local FACE = { Pitch = 0, Yaw = 0, Roll = 90 }
    for _, m in ipairs({
        { "mat_pyro", "/Game/VFX/Mission/Mission027/CoreDestroy/MI_CoreDest_AfterExitBlackSmokeMesh",
          { DistScroll_U = 0.6, DistScroll_V = 0.1, ColorEmissiveScale = 20, SunLightIlluminance = 2 } },
        { "mat_pyro_exit", "/Game/VFX/Mission/Mission027/CoreDestroy/MI_MGF_DestExitSmokeVS", { ColorEmissiveScale = 20 } },
        { "mat_laser10", "/Game/VFX/Mission/Mission010/GR036/MainCannon/MI_SearchLaserBeam001", {} },
        { "mat_laser29", "/Game/VFX/IGC/Ms29/Ms290010/MI_IGCVFX_Ms290010_SearchLaserBeam001", {} },
        { "mat_chargetrail", "/Game/VFX/Vehicles/Weapon/Cannon/MI_ChargeLightningBeamTrail", {} },
        { "mat_vaporring", "/Game/VFX/IGC/Ms29/Ms290010/MI_IGCVFX_Ms290010_VaporTrailRing001", {} },
        { "mat_electric", "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/MI_Electric", {} },
        { "mat_glowpom", "/Game/VFX/Mission/Mission010/GR036/MainCannon/MI_Glow05", {} },
        { "mat_lightning27", "/Game/VFX/Mission/Mission027/CoreDestroy/MI_Lightning003", {} },
        { "mat_elevator_vat", "/Game/VFX/Mission/Mission020/Material/MI_UNI_OrbitElevatorRing004_I22_VAT", {} },
        { "mat_heat", "/Game/VFX/Common/Materials/HeatDistortion/MI_Heat_Distortion05_01", {} },
    }) do
        PP_PIECES[#PP_PIECES + 1] = { m[1], "mesh", DISK, m[2], 260, 1, FACE, m[3], twice = true }
    end
    -- ((2026-11-22) the black hole's glow in layers: is MI_TrainingRing see-through with Opacity, do its overlaps add up;
    -- is MI_TrainingRingGlow flat (no fresnel) with EmissiveFresnelFalloff near 0? Three planes overlapping, each 35 % on)
    local PLANE, RING = "/Engine/BasicShapes/Plane", "/Game/VFX/Mission/Traning/MI_TrainingRing"
    local GLOW = "/Game/VFX/Mission/Traning/MI_TrainingRingGlow"
    local ST3 = { 3, 70, -2, 30 }                         -- (each copy 70 m right, 30 m up, 2 m nearer the camera)
    for _, m in ipairs({
        { "lay_ring_op100", RING, { Color = { 1, 0.6, 0.2, 1 }, Opacity = 1 } },
        { "lay_ring_op30", RING, { Color = { 1, 0.6, 0.2, 1 }, Opacity = 0.3 } },
        { "lay_ring_op10", RING, { Color = { 1, 0.6, 0.2, 1 }, Opacity = 0.1 } },
        { "lay_glow_flat", GLOW, { Color = { 1, 0.6, 0.2, 1 }, EmissiveIntensity = 2, Opacity = 0.3, EmissiveFresnelFalloff = 0.01 } },
        { "lay_glow_flat_dim", GLOW, { Color = { 1, 0.6, 0.2, 1 }, EmissiveIntensity = 1, Opacity = 0.12, EmissiveFresnelFalloff = 0.01 } },
        { "lay_glow_inv", GLOW, { Color = { 1, 0.6, 0.2, 1 }, EmissiveIntensity = 2, Opacity = 0.3, EmissiveFresnelInverseHardness = 0 } },
        { "lay_glow_default", GLOW, { Color = { 1, 0.6, 0.2, 1 }, EmissiveIntensity = 2, Opacity = 0.3 } },
    }) do
        PP_PIECES[#PP_PIECES + 1] = { m[1], "mesh", PLANE, m[2], 200, 1, { Pitch = 0, Yaw = 0, Roll = -90 }, m[3], twice = true, stack = ST3 }   -- (its face to the camera: -Y)
    end
    -- ((2026-11-22) her black hole's shadow: the engine's BasicShapeMaterial is lit (the sun's broad highlight on it in
    -- every run), MI_TrainingRing adds light (a black of it changed nothing, run of 16:19): an unlit black?)
    local SH = "/Game/Mods/SurvivalMode/ValkaPortal/Model/SM_SV_BHShadow"
    local BLACK = { Color = { 0, 0, 0, 1 }, BaseColor = { 0, 0, 0, 1 }, EmissiveColor = { 0, 0, 0, 1 }, Emissive = { 0, 0, 0, 1 },
                    Tint = { 0, 0, 0, 1 }, TintColor = { 0, 0, 0, 1 }, EmissiveIntensity = 0, Brightness = 0, Intensity = 0 }
    for _, m in ipairs({
        { "shade_basic", "/Engine/BasicShapes/BasicShapeMaterial", { Color = { 0, 0, 0, 1 } } },
        { "shade_envunlit", "/Game/Base/Material/Environment/Special/M_Env_Unlit", BLACK },
        { "shade_envunlit_raw", "/Game/Base/Material/Environment/Special/M_Env_Unlit", {} },
        { "shade_billboard", "/Game/OnlineMode/Environment/Common_Nimbus/Prop/Materials/Prop_BillBoard_EA_Unlit_Inst", BLACK },
        { "shade_ring_black", "/Game/VFX/Mission/Traning/MI_TrainingRing", { Color = { 0, 0, 0, 1 }, Opacity = 1 } },
    }) do
        PP_PIECES[#PP_PIECES + 1] = { m[1], "mesh", SH, m[2], 260, 1, nil, m[3], twice = true }
    end
end
local function ppAll(only)
    local want = nil
    if only and only ~= "" then want = {}; for n in tostring(only):gmatch("[^,]+") do want[n] = true end end
    for _, p in ipairs(PP_PIECES) do
        local name = p[1]
        if not want or want[name] then
            if p[2] == "mesh" then
                A.do_(function() ST.look(ppCam(-900, 60), ppSpot(), 45); ppMesh(name, p[3], p[4], p[5], p[6], p[7], p[8], p.stack) end)
                A.wait(2)
                A.do_(function() ST.shot("portal_" .. name) end)
                A.wait(2.5)
                if p.twice then                                   -- (the same view 2.5 s on: does its texture move?)
                    A.do_(function() ST.shot("portal_" .. name .. "_later") end)
                    A.wait(2.5)
                else
                    A.do_(function() ST.look(ppCam(-700, 450), ppSpot(), 45) end)   -- (from above and the side: its depth)
                    A.wait(1)
                    A.do_(function() ST.shot("portal_" .. name .. "_above") end)
                    A.wait(2.5)
                end
                A.do_(ppClear)
            else
                A.do_(function() ST.look(ppCam(-900, 60), ppSpot(), 45) end)
                A.wait(1)
                A.do_(function() ppNiagara(name, p[3], p[4]) end)
                A.wait(0.4)
                A.do_(function() ST.shot("portal_" .. name .. "_start") end)
                A.wait(2.6)
                A.do_(function() ST.shot("portal_" .. name .. "_3s") end)
                A.wait(2.5)
                A.do_(ppClear)
            end
        end
    end
    A.do_(function() ST.lookBack() end)
end
ST.ppAll = ppAll                                          -- (the valka suite's conf portal_probe=1)
SUITES.portalprobe = function()
    intoRun()
    A.do_(function() ST.info(string.format("the portal's pieces at (%.1f, %.1f) km, 3 km up", ppSpot().X / 100000, ppSpot().Y / 100000)) end)
    ppAll(ST.conf.portal_only)
    A.do_(function() ST.check(true, "every portal piece tried (see the INFO lines and the pictures)") end)
end

-- ((2026-11-22) T1 of the SOLG (Scripts/sv_solg.lua, docs/re/SOLG.md): AC:I's SOLG as its own actor (no game unit),
-- 9 km north of the runway, 3.5 km up, nose east, flying east at 120 m/s: does it draw (painted, not black), its
-- rings turn (AC:I's spin), three solar array wings shot off fall away tumbling. Pictures from off its side and nose.)
local SOLGT = { at = nil }
local function solgSpot() return { X = AIRFIELD.X, Y = AIRFIELD.Y - 900000, Z = 350000 } end
local function solgCam(fwd_m, side_m, up_m)               -- metres from the SOLG where it is now (its nose along +X)
    local L = (SOLG and SOLG.where and SOLG.where()) or solgSpot()
    return { X = L.X + fwd_m * 100, Y = L.Y + side_m * 100, Z = L.Z + (up_m or 0) * 100 }, { X = L.X, Y = L.Y, Z = L.Z }
end
SUITES.solg = function()
    intoRun()
    A.do_(function()
        local ok = SOLG and SOLG.spawn and SOLG.spawn(solgSpot(), 0, { X = 12000, Y = 0, Z = 0 })
        ST.check(ok == true, "the SOLG up (its own actor, AC:I's mesh)", ST.findLog("solg: up at", 0) or ST.findLog("solg: ", 0))
    end)
    A.wait(1.5)
    for k, v in ipairs({ { 0, -4200, 300, 55, "side" }, { 2600, -2600, 500, 50, "nose" }, { -2400, -1800, 200, 55, "tail" } }) do
        A.do_(function() local at, look = solgCam(v[1], v[2], v[3]); ST.look(at, look, v[4]) end)
        A.wait(0.6)
        A.do_(function() ST.shot("solg_" .. k .. "_" .. v[5]) end)
        A.wait(2.4)
    end
    -- its spin: the same view 5 s apart
    A.do_(function() local at, look = solgCam(1200, -2400, 0); ST.look(at, look, 50) end)
    A.wait(0.6)
    A.do_(function() ST.shot("solg_spin_a") end)
    A.wait(5)
    A.do_(function() local at, look = solgCam(1200, -2400, 0); ST.look(at, look, 50) end)
    A.wait(0.4)
    A.do_(function() ST.shot("solg_spin_b") end)
    A.wait(1)
    -- three wings shot off, filmed falling
    A.do_(function() local at, look = solgCam(-600, -2200, 200); ST.look(at, look, 55) end)
    A.wait(0.5)
    for _, b in ipairs({ "SG04_01", "SG05_03", "SG05_07" }) do
        A.do_(function() ST.check(SOLG.breakPanel(b) == true, b .. " shot off: it falls", ST.findLog("solg: " .. b, 0)) end)
        A.wait(0.3)
    end
    for k = 1, 5 do                                       -- (on the first wing falling, from 700 m off its side)
        A.do_(function()
            local P = SOLG.panelAt(1)
            if P then ST.look({ X = P.X + 30000, Y = P.Y - 60000, Z = P.Z + 15000 }, P, 50) end
            ST.info(P and string.format("the first wing falling at %.2f km up", P.Z / 100000) or "the first wing: gone")
        end)
        A.wait(0.3)
        A.do_(function() ST.shot("solg_fall_" .. k) end)
        A.wait(1.6)
    end
    A.do_(function()
        ST.info(tostring(ST.findLog("solg: up at", 0)))
        SOLG.stop("T1 over")
        ST.lookBack()
        ST.check(not SOLG.up(), "the SOLG taken down", ST.findLog("solg: taken down", 0))
    end)
end

-- ((2026-11-22) T2 of the SOLG: its targets (each type a unit on AC8's generic destructible base, held on its bones):
-- up and counted, held (their distance from their bones), boxes in the pictures, then every phase's targets brought to
-- their floor (SOLG.hurt, as hits would) and broken by the SOLG in AC:I's order to its destruction)
local function solgTick(sec)                              -- (no VALKA round here: the suite ticks the SOLG itself)
    local t0 = nil
    A.until_(function()
        t0 = t0 or os.clock()
        pcall(SOLG.tick, os.clock())
        return os.clock() - t0 >= sec
    end, sec + 5)
end
SUITES.solg2 = function()
    intoRun()
    A.do_(function()
        local ok = SOLG.spawn(solgSpot(), 0, { X = 3000, Y = 0, Z = 0 })
        ST.check(ok == true, "the SOLG up", ST.findLog("solg: up at", 0))
    end)
    A.wait(1)
    A.do_(function()
        local nT = SOLG.targetsUp()
        ST.check(nT == 92, "its 92 targets up on their bones (SAW 18, MAG 32, KEW 36, CORE 4, HATCH 1, SP 1)",
            ST.findLog("solg: targets up", 0))
        local st = SOLG.state()
        ST.check(st and st.phase == 1, "phase 1 on (the wings and MAG panels)", st and ("phase " .. tostring(st.phase)))
        ST.check(st and st.open == 22, "Gould's opening: 22 lockable (each wing row's third, the 16 required MAG panels)",
            st and tostring(st.open))
        ST.check(ST.findLog("(16 MAG optional)", 0, true) ~= nil, "16 MAG panels optional (4 an arm, opening after their arm's 4)",
            ST.findLog("solg: targets up", 0))
    end)
    solgTick(3)
    A.do_(function()                                      -- (a wing row: its third down, its second opens)
        local open0 = SOLG.state().open
        for _, e in ipairs(SOLG.debugTargets()) do
            if e.bone == "SG04_03" then pcall(function() e.o.HealthInternal = 10 end) end
        end
        pcall(SOLG.tick, os.clock())
        local st = SOLG.state()
        local second = false
        for _, e in ipairs(SOLG.debugTargets()) do if e.bone == "SG04_02" then second = e.open == true end end
        ST.check(second and st.open == open0, "SG04_03 down: SG04_02 opens (open " .. st.open .. ")")
    end)
    A.do_(function()                                      -- (held: each target's distance from its bone)
        local worst, nn = 0, 0
        for _, e in ipairs(SOLG.debugTargets and SOLG.debugTargets() or {}) do
            if not e.live then goto skip end                  -- (one shot down is moved out of the way)
            -- ((2026-11-22) its lock point (HitCenterOffset off its base, in its own frame), where its box shows)
            local okL, L = pcall(function()
                local P, h = e.o:K2_GetActorLocation(), e.o.HitCenterOffset
                local F, R, U = e.o:GetActorForwardVector(), e.o:GetActorRightVector(), e.o:GetActorUpVector()
                return { X = P.X + F.X * h.X + R.X * h.Y + U.X * h.Z, Y = P.Y + F.Y * h.X + R.Y * h.Y + U.Y * h.Z,
                         Z = P.Z + F.Z * h.X + R.Z * h.Y + U.Z * h.Z }
            end)
            local okB, B = pcall(function() return SOLG.boneLoc(e.bone) end)
            if okL and okB and L and B then
                local d = math.sqrt((L.X - B.X) ^ 2 + (L.Y - B.Y) ^ 2 + (L.Z - B.Z) ^ 2) / 100
                worst, nn = math.max(worst, d), nn + 1
            end
            ::skip::
        end
        ST.check(nn > 80 and worst < 30, string.format("targets' lock points held on their bones (%d read, worst %.1f m off)", nn, worst))
    end)
    for k, v in ipairs({ { 0, -3000, 200, 50, "boxes_side" }, { 700, -1600, 300, 50, "boxes_arms" } }) do
        A.do_(function() local at, look = solgCam(v[1], v[2], v[3]); ST.look(at, look, v[4]) end)
        A.wait(0.6)
        A.do_(function() ST.shot("solg2_" .. k .. "_" .. v[5]) end)
        A.wait(1.5)
    end
    -- every phase, in turn (the first with Gould's 15 s pause, the rest without)
    for _, ph in ipairs({ { "SAW", 18, "MAG", 32, 2, 17 }, { "KEW", 36, nil, 0, 3 }, { "CORE", 4, nil, 0, 4 }, { "HATCH", 1, nil, 0, 5 }, { "SP", 1, nil, 0, nil } }) do
        if ph[1] == "KEW" then A.do_(function() SOLG.C.pause_s = {} end) end
        A.do_(function()
            for k = 1, ph[2] do SOLG.hurt(ph[1], 1) ; pcall(SOLG.tick, os.clock()) end
            if ph[3] then for k = 1, ph[4] do SOLG.hurt(ph[3], 1); pcall(SOLG.tick, os.clock()) end end
        end)
        if ph[6] then
            A.do_(function()
                local st = SOLG.state()
                ST.check(st and st.pause and st.pause > 10 and st.phase == 1, string.format("phase 1 done: a %.0f s pause before phase 2",
                    st and st.pause or -1), ST.findLog("phase 1 done", 0))
            end)
        end
        solgTick(ph[6] or 1.5)
        A.do_(function()
            local st = SOLG.state()
            if ph[5] then
                ST.check(st and st.phase == ph[5], string.format("%s down: phase %d on", ph[1], ph[5]),
                    ST.findLog("solg: phase " .. ph[5], 0) or (st and ("phase " .. tostring(st.phase) .. ", " .. st.live .. " live")))
            else
                ST.check(st and st.destroyed, "the SP shell down: the SOLG destroyed", ST.findLog("solg: every target down", 0))
            end
        end)
        A.do_(function() local at, look = solgCam(300, -2200, 300); ST.look(at, look, 55) end)
        A.wait(0.5)
        A.do_(function() ST.shot("solg2_after_" .. ph[1]) end)
        A.wait(1.2)
    end
    A.do_(function()
        SOLG.stop("T2 over")
        ST.lookBack()
        ST.check(not SOLG.up(), "the SOLG and its targets taken down", ST.findLog("solg: taken down", 0))
    end)
end

-- ((2026-11-22) T3 of the SOLG: in VALKA's round (sv_valka_solg.lua). Her round forced, her health put under 20 %:
-- invincible, gone through a portal, her lines, the SOLG out of its own portal at a corner with its targets, every target
-- broken: destroyed, falling, pay, she's back; then once more, left alone: it hits the spaceport (Mission 25's blast), the
-- airfield down, she's back. config_valkasolg.lua: call_s 4, travel_s 45, corner_km 12 (a short fall to watch))
local function vsHer() return glitchActor(CFG.specials.valka) end
local function vsLow()                                    -- her health under at_pct
    local o = vsHer()
    local ok = o and pcall(function() o.HealthInternal = math.floor(o.MaxHealth * 10 * 0.19) end)
    return ok and true or false
end
local function vsCam()                                    -- from 4 km off its side, a little above, looking at it
    local L = SOLG.where and SOLG.where()
    if not L then return nil end
    return { X = L.X - 150000, Y = L.Y - 400000, Z = L.Z + 80000 }, L
end
SUITES.valkasolg = function()
    intoRun()
    A.do_(function()
        SOLG.C.pause_s = {}                               -- (Gould's pauses: solg2's; here the flow)
        local c = CFG.specials.valka
        if not ST.check(c and type(c.solg) == "table" and c.solg.enabled and VSOLG ~= nil, "her SOLG is in this build",
            c and c.solg and ("travel_s " .. tostring(c.solg.travel_s) .. ", call_s " .. tostring(c.solg.call_s))) then return "abort" end
        ST.marks.v0 = ST.n
        D.forceSpecial = "valka"
        if D.state == "wait" then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
        ST.doing = "VALKA's round"
    end)
    A.log_("special: VALKA shows", 150, "v0", true, function(l) if not ST.check(l ~= nil, "VALKA shows", l) then return "abort" end end)
    A.wait(4)
    for pass = 1, 2 do
        if pass == 2 then                                 -- (the first one's wreck and units gone first: once a round in play)
            A.log_("solg: taken down (its wreck's gone)", 40, "z0", true, function(l) ST.check(l ~= nil, "its wreck gone, its units taken off", l) end)
            A.wait(3)
        end
        A.do_(function()
            local s = D.special
            if pass == 2 and s then s.solgDone, s.solg = nil, nil end      -- (once more: the spaceport hit this time)
            ST.marks["s" .. pass] = ST.n
            ST.check(vsLow(), string.format("pass %d: her health put at 19 %%", pass))
        end)
        A.log_("special: VALKA's SOLG: her health at", 10, "s" .. pass, true, function(l)
            ST.check(l ~= nil and l:find("invincible", 1, true) ~= nil, "she's invincible and gone through a portal", l)
            local o = vsHer()
            local okI, inv = pcall(function() return o.bIsInvincible end)
            ST.check(okI and inv == true, "her plane untouchable", tostring(inv))
        end)
        if pass == 1 then
            A.log_("special: VALKA's round: solg said", 5, "s" .. pass, true, function(l) ST.check(l ~= nil, "her and AUDREY's lines", l) end)
        end
        -- ((0.75.17) its portal's opening pictured (the scalers: smooth or not, it must show), from 7 km off its face
        A.log_("special: VALKA's SOLG: its portal opens", 15, "s" .. pass, true, function(l) end)
        for k = 1, 4 do
            A.do_(function()
                local G = D.special and D.special.solg
                local P = G and G.ph and G.ph.portal
                if P then
                    local r = math.rad(P.yaw or 0)
                    ST.look({ X = P.at.X + math.cos(r) * 700000, Y = P.at.Y + math.sin(r) * 700000, Z = P.at.Z + 60000 }, P.at, 40)
                end
            end)
            A.wait(0.3)
            A.do_(function() ST.shot(string.format("vsolg%d_0open_%d", pass, k)) end)
            A.wait(0.9)
        end
        A.log_("special: VALKA's SOLG: out of the corner", 15, "s" .. pass, true, function(l)
            if not ST.check(l ~= nil and l:find("92 targets", 1, true) ~= nil, "the SOLG out of a corner with its 92 targets", l) then return "abort" end
            -- ((2026-11-22) the user: "the solg didn't look angled downwards") its nose down as the game has it
            ST.check(SOLG.pitchNow ~= nil and SOLG.pitchNow <= -15, string.format("its nose down as it falls (the game's pitch %s)", tostring(SOLG.pitchNow)))
            -- ((2026-11-22) the user: "shes still attacking the players while invisible") parked out of reach meanwhile
            local o, you = vsHer(), playerLocation()
            local okD, d = pcall(function() local L = o:K2_GetActorLocation(); return math.sqrt((L.X - you.X) ^ 2 + (L.Y - you.Y) ^ 2 + (L.Z - you.Z) ^ 2) / 100000 end)
            ST.check(okD and d > 20, string.format("VALKA parked out of the fight while it's up (%.1f km from you)", okD and d or -1))
            local pl = ST.findLog("special: VALKA's SOLG: its portal opens", ST.marks["s" .. pass])
            ST.check(pl ~= nil and pl:find("once it's full size", 1, true) ~= nil, "its portal opens first; the SOLG once it's full size", pl)
            local st = VSOLG.state(D.special)
            local dt = st and st.portal_to_solg_s
            ST.check(dt ~= nil and dt >= 4, string.format("the SOLG came through %.1f s after its portal began to open", dt or -1))
        end)
        for k = 1, 4 do
            A.do_(function() local at, look = vsCam(); if at then ST.look(at, look, 55) end end)
            A.wait(0.5)
            A.do_(function() ST.shot(string.format("vsolg%d_%d_out", pass, k)) end)
            A.wait(2.0)
        end
        if pass == 1 then
            A.do_(function()                              -- every target broken, phase by phase (as hits would)
                for _, key in ipairs({ "SAW", "MAG" }) do for k = 1, 40 do SOLG.hurt(key, 1); pcall(SOLG.tick, os.clock()) end end
            end)
            A.wait(1.5)
            A.do_(function() for k = 1, 40 do SOLG.hurt("KEW", 1); pcall(SOLG.tick, os.clock()) end end)
            A.wait(1.5)
            A.do_(function() for k = 1, 5 do SOLG.hurt("CORE", 1); pcall(SOLG.tick, os.clock()) end end)
            A.wait(1.5)
            A.do_(function() ST.marks.z0 = ST.n; SOLG.hurt("SP", 1) end)
            A.log_("special: VALKA's SOLG: destroyed", 8, "z0", true, function(l)
                ST.check(l ~= nil, "the SOLG destroyed: pay, AUDREY's lines", l)
                ST.check(ST.findLog("solg: falling", ST.marks.z0) ~= nil, "it falls apart", ST.findLog("solg: falling", ST.marks.z0))
                local arms = 0
                for k = 1, 4 do if ST.findLog(string.format("solg: SG01_%02d broken off with its ", k), ST.marks.s1, true) then arms = arms + 1 end end
                ST.check(arms == 4, string.format("each autoloader broke off once its 9 KEW shells were down (%d of 4)", arms),
                    ST.findLog("broken off with its", ST.marks.s1))
                ST.check(ST.findLog("on the arms: SG01_01 9, SG01_02 9, SG01_03 9, SG01_04 9", ST.marks.s1) ~= nil,
                    "9 KEW shells hold each arm (Gould)", ST.findLog("solg: targets up", ST.marks.s1))
            end)
            for k = 1, 3 do
                A.do_(function() local at, look = vsCam(); if at then ST.look(at, look, 60) end end)
                A.wait(0.4)
                A.do_(function() ST.shot("vsolg1_down_" .. k) end)
                A.wait(2.5)
            end
        else
            A.do_(function() ST.lookBack(); ST.doing = "the SOLG falling on the spaceport" end)
            A.log_("special: VALKA's SOLG: it hit the spaceport", 80, "s2", true, function(l)
                ST.check(l ~= nil and not l:find(": 0 effect", 1, true), "it hits the spaceport: Mission 25's blast", l)
                ST.check(AF and AF.down == true, "the airfield down for a round", AF and tostring(AF.down))
                local pad = CFG.specials.valka.solg.pad_cm
                ST.look({ X = pad[1] - 900000, Y = pad[2] - 900000, Z = 250000 }, { X = pad[1], Y = pad[2], Z = 0 }, 50)
            end)
            for k = 1, 6 do
                A.do_(function() ST.shot("vsolg2_hit_" .. k) end)
                A.wait(1.2)
            end
            A.do_(function() ST.lookBack() end)
        end
        A.log_("special: VALKA's SOLG: she's back", 20, "s" .. pass, true, function(l)
            ST.check(l ~= nil, string.format("pass %d: she's back", pass), l)
        end)
        A.wait(1.5)
        A.do_(function()
            local o = vsHer()
            local okI, inv = pcall(function() return o.bIsInvincible end)
            ST.check(okI and inv == false, "she's damageable again (after her way back)", tostring(inv))
            -- ((2026-11-22) the user: "when Valka came back in, she was invisible with no target box")
            local okV, hid, box = pcall(function() return o.bHidden, o.bShowHUDBox end)
            ST.check(okV and hid == false and box == true, "she's seen again, her target box on", string.format("hidden %s, box %s", tostring(hid), tostring(box)))
            local sp = D and D.special
            if sp and sp.modelComp then
                local okM, vis = pcall(function() return sp.modelComp:IsVisible() end)
                ST.check(okM and vis == true, "her X-02S shown", tostring(vis))
            end
        end)
        A.wait(2)
    end
end

-- ((2026-11-22) the SOLG's lasers (sv_solg.lua LSRA / LSRB on AC8's land Phalanx, firing BP_SV_SolgTLS, 5 a hit;
-- tools/build_survival_solg.py): the SOLG parked over your circle, its first phase broken, its arm lasers up; shots of
-- our laser counted (its objects as they come), your health's drops read (config_solglaser.lua: plane = "floor",
-- shootable but never down), pictures; then the KEW shells broken: the barrel's lasers up, the arms' down with the arms
local LSR = { ours = 0, stock = 0, drops = {}, last = nil }
pcall(NotifyOnNewObject, "/Script/Live.LiveTLSSwingforPlane", function(o)
    local okP, full = pcall(function() return o:GetClass():GetFullName() end)
    full = okP and tostring(full) or ""
    if full:find("Default__", 1, true) then return end
    if full:find("BP_SV_SolgTLS", 1, true) then
        LSR.ours = LSR.ours + 1
        LSR.times = LSR.times or {}
        LSR.times[#LSR.times + 1] = os.clock()
        LSR.new = LSR.new or {}
        if #LSR.new < 40 then LSR.new[#LSR.new + 1] = { o = o, at = os.clock() } end
    else LSR.stock = LSR.stock + 1 end
    if LSR.ours + LSR.stock <= 3 then LSR.first = (LSR.first or "") .. " " .. full end
end)
local function lsrLook(e, now)                        -- a laser's state: where, hidden, its Niagara parts
    local o = e.o
    if not (o and pcall(function() return o:IsValid() end) and o:IsValid()) then return "gone" end
    local r = {}
    local okL, L = pcall(function() local v = o:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    local you = playerLocation()
    if okL and L and you then
        r[#r + 1] = string.format("%.1f km from you", math.sqrt((L.X - you.X) ^ 2 + (L.Y - you.Y) ^ 2 + (L.Z - you.Z) ^ 2) / 100000)
        e.L = L
    end
    pcall(function() r[#r + 1] = "hidden " .. tostring(o.bHidden) end)
    pcall(function()
        local root = o.RootComponent
        local par = root:GetAttachParent()
        r[#r + 1] = "attached to " .. (par and par:IsValid() and (par:GetFullName():match("[^%.:]+$") or "?") .. " visible " .. tostring(par:IsVisible()) or "nothing")
    end)
    local nc = StaticFindObject("/Script/Niagara.NiagaraComponent")
    local okC, list = pcall(function() return o:K2_GetComponentsByClass(nc) end)
    if okC and list then
        pcall(function() list:ForEach(function(_, x)
            local c = x:get()
            local nm, vis, act, asset = "?", "?", "?", "?"
            pcall(function() nm = c:GetFName():ToString() end)
            pcall(function() vis = tostring(c:IsVisible()) end)
            pcall(function() act = tostring(c:IsActive()) end)
            pcall(function() asset = c.Asset:GetFName():ToString() end)
            r[#r + 1] = string.format("[%s: %s, visible %s, active %s]", nm, asset, vis, act)
        end) end)
    else r[#r + 1] = "no Niagara parts read" end
    return table.concat(r, ", ")
end
local function lsrHealth()
    local p = ST.plane()
    local ok, h = pcall(function() return p.HealthInternal end)
    return ok and tonumber(h) or nil
end
SUITES.solglaser = function()
    intoRun()
    A.do_(function()
        SOLG.C.pause_s = {}
        local you = playerLocation()
        local at = { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = (you and you.Z or 150000) + 60000 }
        local ok = SOLG.spawn(at, 0, nil)
        ST.check(ok == true, "the SOLG up over your circle", ST.findLog("solg: up at", 0))
        ST.check(ST.findLog("the lasers' fire control SV_FCS_SolgTLS in DT_NPC_FCS", 0) ~= nil, "its lasers' fire control row in the game's table",
            ST.findLog("solg: rows:", 0))
    end)
    A.wait(1)
    A.do_(function()
        ST.marks.l0 = ST.n
        SOLG.targetsUp()
        for _, key in ipairs({ "SAW", "MAG" }) do for k = 1, 40 do SOLG.hurt(key, 1); pcall(SOLG.tick, os.clock()) end end
    end)
    A.log_("solg: phase 2: its lasers up", 10, "l0", true, function(l)
        ST.check(l ~= nil and l:find("LSRA 16 of 16", 1, true) ~= nil and l:find("16 on the arms", 1, true) ~= nil,
            "phase 2: the arms' 16 lasers up (4 an arm)", l)
        LSR.ours, LSR.stock, LSR.drops, LSR.last = 0, 0, {}, lsrHealth()
        ST.info("your health at the lasers' start: " .. tostring(LSR.last))
    end)
    local t0 = nil
    A.until_(function()                                   -- 40 s of it: the SOLG held, your health's drops
        t0 = t0 or os.clock()
        pcall(SOLG.tick, os.clock())
        local now = os.clock()
        -- ((0.75.12: Gould's lasers reach 1.2 km, your circle is farther) the SOLG kept 500 m over you, its arms' in reach
        local you = playerLocation()
        if you then
            if not LSR.actor then
                for _, e in ipairs(SOLG.debugTargets() or {}) do
                    local okA, a = pcall(function() return e.o.RootComponent:GetAttachParent():GetOwner() end)
                    if okA and a and valid(a) then LSR.actor = a; break end
                end
            end
            -- ((2026-11-22) the user: "as soon as the solg started moving they stopped firing or they were like rapid
            -- firing") --conf move=1: the SOLG sweeps past you at 120 m/s (its fall's speed), 500 m up, from 2.4 km back
            local dx = 0
            if ST.conf.move == 1 then dx = (-2400 + 120 * (now - t0)) * 100 end
            if LSR.actor and valid(LSR.actor) then
                pcall(function() LSR.actor:K2_SetActorLocation({ X = you.X + dx, Y = you.Y, Z = you.Z + 50000 }, false, {}, true) end)
            end
        end
        for _, e in ipairs(LSR.new or {}) do
            if not e.seen1 and now - e.at >= 0.6 then e.seen1 = true; ST.info("laser +0.6 s: " .. lsrLook(e, now)) end
            if not e.seen2 and now - e.at >= 1.5 then
                e.seen2 = true
                ST.info("laser +1.5 s: " .. lsrLook(e, now))
                local you = playerLocation()
                if e.L and you and (LSR.pics or 0) < 6 and now >= (LSR.picAt or 0) then   -- (from beside the beam)
                    LSR.pics, LSR.picAt = (LSR.pics or 0) + 1, now + 3
                    local mx, my, mz = (e.L.X + you.X) / 2, (e.L.Y + you.Y) / 2, (e.L.Z + you.Z) / 2
                    local dx, dy = you.X - e.L.X, you.Y - e.L.Y
                    local d = math.max(1, math.sqrt(dx * dx + dy * dy))
                    ST.look({ X = mx - dy / d * 250000, Y = my + dx / d * 250000, Z = mz + 30000 }, { X = mx, Y = my, Z = mz }, 70)
                    LSR.shotAt = now + 0.35
                end
            end
        end
        if LSR.shotAt and now >= LSR.shotAt then LSR.shotAt = nil; ST.shot("solglaser_beam_" .. (LSR.pics or 0)) end
        if LSR.backAt and now >= LSR.backAt then LSR.backAt = nil; ST.lookBack() end
        if LSR.shotAt == nil and (LSR.pics or 0) > 0 and not LSR.backAt and now >= (LSR.picAt or 0) - 2 then LSR.backAt = now + 0.3 end
        local h = lsrHealth()
        if h and LSR.last and h < LSR.last - 0.5 then LSR.drops[#LSR.drops + 1] = LSR.last - h end
        LSR.last = h or LSR.last
        return os.clock() - t0 >= 40
    end, 50)
    for k = 1, 4 do
        A.do_(function()
            local you, L = playerLocation(), SOLG.where()
            if you and L then ST.look({ X = you.X - (L.X - you.X) * 0.15, Y = you.Y - (L.Y - you.Y) * 0.15, Z = you.Z + 20000 }, L, 60) end
        end)
        A.wait(0.4)
        A.do_(function() ST.shot("solglaser_" .. k) end)
        A.wait(2.0)
    end
    A.do_(function()
        ST.lookBack()
        local sizes = {}
        for i = 1, math.min(12, #LSR.drops) do sizes[#sizes + 1] = string.format("%.0f", LSR.drops[i]) end
        ST.info(string.format("lasers: %d of ours, %d stock swing lasers; your health dropped %d times (HealthInternal: %s)%s",
            LSR.ours, LSR.stock, #LSR.drops, table.concat(sizes, ", "), LSR.first and (" first:" .. LSR.first) or ""))
        ST.check(LSR.ours > 0, string.format("the SOLG's lasers fired (%d shots of BP_SV_SolgTLS)", LSR.ours))
        do                                                -- (each second's shots: a steady fire or bursts)
            local per, t1 = {}, (LSR.times or {})[1]
            for _, t in ipairs(LSR.times or {}) do local k = math.floor(t - t1); per[k] = (per[k] or 0) + 1 end
            local row = {}
            for k = 0, 45 do row[#row + 1] = tostring(per[k] or 0) end
            ST.info("laser shots a second" .. (ST.conf.move == 1 and " (the SOLG moving)" or "") .. ": " .. table.concat(row, " "))
        end
        ST.check(LSR.stock == 0, "no stock laser fired meanwhile (ours is its own blueprint)", tostring(LSR.stock))
        local one = nil                                   -- (a hit: the smallest drop but the last (the floor cuts it); every other a whole number)
        if #LSR.drops > 1 then table.remove(LSR.drops) end
        for _, d in ipairs(LSR.drops) do one = (not one or d < one) and d or one end
        local whole = 0
        for _, d in ipairs(LSR.drops) do if one and math.abs(d / one - math.floor(d / one + 0.5)) < 0.08 then whole = whole + 1 end end
        ST.check(#LSR.drops > 0 and whole == #LSR.drops, string.format("every hit the same: %.1f health a hit (weapon 5, the game's own "
            .. "scaling for your plane: x%.2f); %d of %d drops whole hits", (one or 0) / 10, (one or 0) / 50, whole, #LSR.drops))
        ST.marks.l1 = ST.n
        for k = 1, 40 do SOLG.hurt("KEW", 1); pcall(SOLG.tick, os.clock()) end
    end)
    A.log_("solg: phase 3: its lasers up", 10, "l1", true, function(l)
        ST.check(l ~= nil and l:find("LSRC 8 of 8", 1, true) ~= nil and l:find("0 on the arms", 1, true) ~= nil,
            "phase 3: the barrel's front 8 lasers up", l)
        ST.check(ST.findLog("LSRB 4 of 4", ST.marks.l0, true) ~= nil, "phase 2: the barrel's tail 4 up with the arms'",
            ST.findLog("LSRB", ST.marks.l0, true))
        local st = SOLG.state()
        ST.check(st and (st.per.LSRA or 0) == 0, "the arms' lasers went down with their arms", st and tostring(st.per.LSRA))
    end)
    A.wait(2)
    A.do_(function() SOLG.stop("laser test over") end)
end

-- ((2026-11-22) the ZFA-44s' lasers' sound (the user: "check that the ZFA, and Tanacorn Lasers are also using the
-- correct laser sounds"): a carrier sent (ESC.testCarrier, Ctrl+DEL's), its ZFA-44s out and each carrying AC7's
-- LaserInterceptor; every laser's volley on command (ESC.testLaser, Ctrl+['s); the TLS's shooting sound posted on each
-- laser (ZLI.sound: on, then its stop), none refused; pictures of a ZFA-44 firing. (The sound itself: the user's ears.)
local function zfaLasers()
    local out = {}
    for _, x in ipairs(FindAllOf("BP_SV_LaserInterceptor_C") or {}) do
        if valid(x) and not tostring(x:GetFullName()):find("Default__", 1, true) then out[#out + 1] = x end
    end
    return out
end
SUITES.zfasound = function()
    intoRun()
    A.do_(function()
        local z = CFG.allies.carrier.zfa
        ST.check(z.li_fire_sound == "AKE_GEN_PLAYER_ARMS_SPWeapon_TLS_Emit_Play" and z.li_fire_stop == "AKE_GEN_PLAYER_ARMS_SPWeapon_TLS_Emit_Stop",
            "the LaserInterceptor's shooting sound is the TLS's (on and stop)", tostring(z.li_fire_sound))
        ST.marks.z0 = ST.n
        if not ST.check(ESC and ESC.testCarrier and ESC.testLaser, "the carrier and laser test hooks are in this build") then return "abort" end
        ESC.testCarrier()
    end)
    A.log_("carries AC7's LaserInterceptor", 240, "z0", true, function(l)
        if not ST.check(l ~= nil, "a ZFA-44 carries AC7's LaserInterceptor", l) then return "abort" end
    end)
    A.wait(6)
    A.do_(function()
        ST.marks.z1 = ST.n
        ESC.testLaser()
    end)
    A.log_("fires a volley", 5, "z1", true, function(l) ST.check(l ~= nil, "the lasers fire a volley on command", l) end)
    for k = 1, 4 do
        A.do_(function()
            local L = zfaLasers()[1]
            local at = L and ST.at(L)
            if at then ST.look({ X = at.X - 8000, Y = at.Y - 12000, Z = at.Z + 3000 }, at, 45) end
        end)
        A.wait(0.4)
        A.do_(function() ST.shot("zfasound_volley_" .. k) end)
        A.wait(1.0)
    end
    A.do_(function()
        ST.lookBack()
        local L = zfaLasers()
        local on, off = 0, 0
        for _, x in ipairs(L) do                          -- (the sound posted on each laser, then stopped)
            local r = { li = x }
            ZLI.sound(r, true)
            if r.sndOn then on = on + 1 end
            ZLI.sound(r, false)
            if not r.sndOn then off = off + 1 end
        end
        ST.check(#L > 0 and on == #L and off == #L, string.format("the TLS shooting sound posted on each of %d lasers and stopped (%d / %d)", #L, on, off))
        ST.check(ST.findLog("couldn't be posted", ST.marks.z0, true) == nil, "no laser's sound refused", ST.findLog("couldn't be posted", ST.marks.z0, true))
    end)
    A.wait(8)
    A.do_(function()
        local n = 0
        for i = ST.marks.z1 + 1, ST.n do if (ST.lines[i] or ""):find("fires a volley", 1, true) then n = n + 1 end end
        ST.info(string.format("zfasound: %d volleys fired on command; their sound on with each, off with its beam", n))
    end)
end

-- ((2026-11-22) the SOLG on a co-op JOINER (sv_solg_coop.lua), on one PC: COOP.client made true only while the suite
-- hands the joiner's side the host's words ("vs|...") and ticks it; the host's units' copies stood in for by the units
-- spawned here (COOP.groundCopies served from them, as co-op serves a joiner its copies). Its portal, its SOLG up on the
-- host's course, its pieces' copies placed (the lasers' with phase 2), every piece broken by the host's word (the arms
-- off after their KEW shells, the lasers with them), destroyed (falling, the team's pay), then once more: the spaceport
-- hit (Mission 25's strike). Pictures of each.
local SJ = { cap = nil, copies = {} }
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o) if SJ.cap and #SJ.cap < 200 then SJ.cap[#SJ.cap + 1] = o end end)
local function asJoiner(fn)
    local was = COOP.client
    COOP.client = function() return true end
    local ok, e = pcall(fn)
    COOP.client = was
    if not ok then ST.info("solgjoiner: error " .. tostring(e)) end
end
local function sjWord(...)
    local f = { "vs", ... }
    asJoiner(function() SCOOP.fromHost(f) end)
end
local function sjCopies(t)                                -- (the host's copies of type t: its unit spawned here)
    SJ.cap = {}
    spawningUnit = t.unit
    pcall(SV_Spawn, t.unit, SJ.at.X, SJ.at.Y, SJ.at.Z, 0)
    spawningUnit = nil
    SJ.copies[t.unit], SJ.cap = SJ.cap, nil
    return #SJ.copies[t.unit]
end
local function sjTick(sec)
    local t0 = nil
    A.until_(function()
        t0 = t0 or os.clock()
        asJoiner(function() SCOOP.clientTick(os.clock()) end)
        return os.clock() - t0 >= sec
    end, sec + 5)
end
local function sjCam(fwd, side, up)                       -- (metres from where the SOLG is now)
    local L = SOLG.where and SOLG.where()
    if not L then return nil end
    return { X = L.X + fwd * 100, Y = L.Y + side * 100, Z = L.Z + up * 100 }, L
end
local function sjShot(name, fwd, side, up, fov)
    A.do_(function() local at, look = sjCam(fwd, side, up); if at then ST.look(at, look, fov or 55) end end)
    A.wait(0.5)
    A.do_(function() ST.shot("solgjoiner_" .. name) end)
    A.wait(1.0)
end
SUITES.solgjoiner = function()
    intoRun()
    A.do_(function()
        if not ST.check(SCOOP ~= nil and SCOOP.fromHost ~= nil and COOP ~= nil, "the SOLG's co-op part is in this build") then return "abort" end
        SOLG.C.pause_s = {}
        SJ.wasGC = COOP.groundCopies
        COOP.groundCopies = function(unit) return SJ.copies[unit] or {} end
        SJ.at = { X = AIRFIELD.X + 300000, Y = AIRFIELD.Y - 900000, Z = 400000 }
        ST.marks.j0 = ST.n
        sjWord("po", string.format("%.0f", SJ.at.X / 100), string.format("%.0f", SJ.at.Y / 100), string.format("%.0f", SJ.at.Z / 100), "0", "2600")
        ST.check(ST.findLog("solg coop: the host's portal opens", ST.marks.j0, true) ~= nil, "the host's portal opens here",
            ST.findLog("solg coop:", ST.marks.j0, true))
    end)
    sjTick(5.5)
    sjShot("1_portal", -6000, 0, 800, 60)
    A.do_(function()                                      -- (the host's copies come: its pieces' units)
        local got = {}
        for _, t in ipairs(SOLG.C.targets) do if not t.laser then got[#got + 1] = t.key .. " " .. sjCopies(t) end end
        ST.info("solgjoiner: the host's copies stood in: " .. table.concat(got, ", "))
        sjWord("up", string.format("%.0f", SJ.at.X / 100 - 1500), string.format("%.0f", SJ.at.Y / 100), string.format("%.0f", SJ.at.Z / 100),
            "0", "3000", "0", "-300", "360", "0")
        ST.check(ST.findLog("solg coop: the host's SOLG up here", ST.marks.j0, true) ~= nil, "the host's SOLG up here",
            ST.findLog("solg coop: the host's SOLG", ST.marks.j0, true))
    end)
    sjTick(2)
    A.do_(function()
        local per = {}
        for _, key in ipairs({ "SAW", "MAG", "KEW", "CORE", "HATCH", "SP" }) do
            per[#per + 1] = ST.findLog("co-op: the host's " .. key .. " copies placed: ", ST.marks.j0, true) and key or nil
        end
        ST.check(#per == 6, "its pieces' copies placed on its bones (SAW, MAG, KEW, CORE, HATCH, SP)", ST.findLog("copies placed", ST.marks.j0, true))
        local st = SOLG.state()
        ST.check(st and st.open == 22, "Gould's opening here too: 22 lockable", st and tostring(st.open))
    end)
    sjShot("2_up", 0, -3200, 400, 55)
    A.do_(function()                                      -- (the host's phase 2: its lasers' copies come)
        ST.marks.j1 = ST.n
        sjWord("ph", "2")
        for _, t in ipairs(SOLG.C.targets) do if t.laser and t.phase == 2 then sjCopies(t) end end
    end)
    sjTick(2)
    A.do_(function()
        ST.check(ST.findLog("co-op: the host's LSRA copies placed: 16 of 16", ST.marks.j1, true) ~= nil, "phase 2: the arms' laser copies placed",
            ST.findLog("LSRA copies", ST.marks.j1, true))
        ST.marks.j2 = ST.n
        for k = 1, 6 do sjWord("b", string.format("SG04_%02d", k)) end
        for k = 1, 12 do sjWord("b", string.format("SG05_%02d", k)) end
        for k = 1, 32 do sjWord("b", string.format("SG07_%02d", k)) end
        for k = 1, 36 do sjWord("b", string.format("KEW_%02d", k)) end
    end)
    sjTick(2)
    A.do_(function()
        local arms = 0
        for k = 1, 4 do if ST.findLog(string.format("solg: SG01_%02d broken off", k), ST.marks.j2) then arms = arms + 1 end end
        ST.check(arms == 4, string.format("the host's breaks: wings falling, the 4 arms off after their KEW shells (%d)", arms))
        local st = SOLG.state()
        ST.check(st and (st.per.LSRA or 0) == 0, "the arms' lasers down with them", st and tostring(st.per.LSRA))
        -- (the code review: a joiner's pay is the host's own, sent as "cr": never paid again here by the host's word)
        ST.check(ST.findLog("(the host's word)", ST.marks.j2, true) == nil, "no second pay here for the host's breaks (the host's \"cr\" pays)",
            ST.findLog("(the host's word)", ST.marks.j2, true))
    end)
    sjShot("3_broken", 300, -2600, 500, 55)
    A.do_(function()
        ST.marks.j3 = ST.n
        sjWord("ph", "3"); sjWord("b", "SG03_01"); sjWord("b", "SG03_02"); sjWord("b", "SG03_03"); sjWord("b", "SG03_04")
        sjWord("ph", "4"); sjWord("b", "CORE_01"); sjWord("dn")
        ST.check(ST.findLog("solg coop: the host's SOLG destroyed", ST.marks.j3, true) ~= nil and ST.findLog("solg: falling", ST.marks.j3, true) ~= nil,
            "the host's word: destroyed, falling apart here", ST.findLog("solg coop:", ST.marks.j3, true))
    end)
    sjTick(2)
    sjShot("4_down", 300, -3000, 600, 60)
    A.do_(function()                                      -- (once more: its spaceport hit)
        sjWord("st")
        for _, t in ipairs(SOLG.C.targets) do if SPC and SPC.cleanUp then pcall(SPC.cleanUp, { t.unit }, "solgjoiner", true, os.clock()) end end
        SJ.copies = {}
        ST.marks.j4 = ST.n
        local pad = CFG.specials.valka.solg.pad_cm
        sjWord("hit", string.format("%.0f", pad[1] / 100), string.format("%.0f", pad[2] / 100), "0")
        ST.check(ST.findLog("solg coop: the host's SOLG hit the spaceport", ST.marks.j4, true) ~= nil, "the host's hit: Mission 25's strike here",
            ST.findLog("solg coop:", ST.marks.j4, true))
        ST.look({ X = pad[1] - 900000, Y = pad[2] - 900000, Z = 250000 }, { X = pad[1], Y = pad[2], Z = 0 }, 50)
    end)
    sjTick(3)
    A.do_(function() ST.shot("solgjoiner_5_hit") end)
    A.wait(1)
    A.do_(function()
        ST.lookBack()
        sjWord("vg", "1"); sjWord("vg", "0"); sjWord("st")
        ST.check(ST.findLog("solg coop: VALKA gone through a portal here", ST.marks.j4, true) ~= nil and ST.findLog("solg coop: VALKA back here", ST.marks.j4, true) ~= nil,
            "VALKA gone and back here (the host's word)", ST.findLog("solg coop: VALKA", ST.marks.j4, true))
        COOP.groundCopies = SJ.wasGC
        ST.check(not (SOLG.up and SOLG.up()), "all taken down", tostring(SOLG.up and SOLG.up()))
    end)
end

-- ((2026-11-22) the portal's scalers (0.75.18: the pieces didn't grow or shrink): a portal opened in front of you, its
-- first scaler read each tick (its bone B's scale, play rate, position, playing, its anim tick option); then remedies one
-- at a time on its pieces' scalers: A the anim tick option set again, B huge bounds (never culled), C SetPosition and
-- rate again after a tick; each logged with the bone's scale after. Pictures.
local function spBone(sc)
    local r = {}
    pcall(function() local t = sc:GetSocketTransform(FName("B"), 0); r.s = t.Scale3D.X end)
    pcall(function() r.rate = sc:GetPlayRate() end)
    pcall(function() r.pos = sc:GetPosition() end)
    pcall(function() r.play = sc:IsPlaying() end)
    pcall(function() r.opt = sc.VisibilityBasedAnimTickOption end)
    pcall(function() r.mode = sc:GetAnimationMode() end)
    pcall(function() r.vis = sc:IsVisible() end)
    return string.format("bone scale %s, rate %s, pos %s, playing %s, tick option %s, mode %s, visible %s",
        tostring(r.s), tostring(r.rate), tostring(r.pos), tostring(r.play), tostring(r.opt), tostring(r.mode), tostring(r.vis)), r.s
end
SUITES.scalerprobe = function()
    intoRun()
    local SP = {}
    A.do_(function()
        local c = CFG.specials.valka
        local you = playerLocation()
        local f = ST.plane() and ST.plane():GetActorForwardVector()
        SP.at = { X = you.X + f.X * 600000, Y = you.Y + f.Y * 600000, Z = you.Z + 40000 }
        SP.h = {}
        local ok = SPC.V.portalOpen(c, SP.h, SP.at, math.deg(math.atan(-f.Y, -f.X)), os.clock())
        local P = SP.h.portal
        local n = 0
        for _, e in ipairs(P and P.meshes or {}) do if e.sc then n = n + 1 end end
        ST.check(ok and n > 0, string.format("a portal up, %d pieces on scalers", n))
        SP.e = P and P.meshes[1]
        if SP.e and SP.e.sc then ST.info("scaler at once: " .. spBone(SP.e.sc)) end
        SP.e1 = SP.e
    end)
    for k = 1, 6 do                                       -- (its own ticks: the portal ticked as her round would)
        A.do_(function()
            pcall(SPC.V.portalTick, CFG.specials.valka, SP.h, os.clock())
            if SP.e and SP.e.sc then
                local okW, w = pcall(function() return SP.e.comp:K2_GetComponentScale().X end)
                local nm = ""
                pcall(function() nm = SP.e.part.mesh:match("[^/]+$") end)
                ST.info(string.format("scaler tick %d: %s; the piece (%s) world scale %s", k, (spBone(SP.e.sc)), nm, okW and string.format("%.3f", w) or "?"))
            end
        end)
        A.wait(0.5)
    end
    A.do_(function() local P = SP.h.portal; if P then ST.look({ X = P.at.X + 300000, Y = P.at.Y, Z = P.at.Z + 30000 }, P.at, 50) end end)
    A.wait(0.4)
    A.do_(function() ST.shot("scalerprobe_1_after_open") end)
    -- ((0.75.21: "it doesn't have an closing animation") its closing, now: the bone must fall back
    A.do_(function() local P = SP.h.portal; if P then P.closeAt = os.clock() end; SP.closeAt = os.clock() end)
    for k = 1, 8 do
        A.do_(function()
            pcall(SPC.V.portalTick, CFG.specials.valka, SP.h, os.clock())
            if SP.e and SP.e.sc and SP.h.portal then
                local txt, sc0 = spBone(SP.e.sc)
                ST.info(string.format("closing tick %d: %s", k, txt))
                SP.closeMin = math.min(SP.closeMin or 1e9, tonumber(sc0) or 1e9)
            end
        end)
        A.wait(0.4)
    end
    A.do_(function()
        ST.check((SP.closeMin or 1e9) < 50 or SP.h.portal == nil, string.format("the closing shrinks its pieces (bone down to %s)", tostring(SP.closeMin)))
        SP.h = {}
        SPC.V.portalOpen(CFG.specials.valka, SP.h, SP.at, 0, os.clock())
        SP.e = SP.h.portal and SP.h.portal.meshes[1]
    end)
    -- the remedies
    local REM = {
        { "A tick option 0 again", function(sc) sc.VisibilityBasedAnimTickOption = 0 end },
        { "B bounds x1e6 and fixed bounds off", function(sc) sc:SetBoundsScale(1000000); sc.bComponentUseFixedSkelBounds = false end },
        { "C replayed: grow, rate 1", function(sc) sc:PlayAnimation(SPC.V.asset(SPC.V.PORTAL_GROW), false); sc:SetPlayRate(1) end },
        { "D refresh bone transforms", function(sc) sc:RefreshBoneTransforms(nil) end },
        { "E update every frame", function(sc) sc.bEnableUpdateRateOptimizations = false; sc.bNoSkeletonUpdate = false end },
    }
    for _, rm in ipairs(REM) do
        A.do_(function()
            local P = SP.h.portal
            local okR, err = 0, nil
            for _, e in ipairs(P and P.meshes or {}) do
                if e.sc then
                    local ok, er = pcall(rm[2], e.sc)
                    if ok then okR = okR + 1 else err = er end
                end
            end
            ST.info(string.format("remedy %s: on %d scalers%s", rm[1], okR, err and (" (error " .. tostring(err) .. ")") or ""))
        end)
        A.wait(1.2)
        A.do_(function() if SP.e and SP.e.sc then ST.info(string.format("after remedy %s: %s", rm[1], (spBone(SP.e.sc)))) end end)
    end
    A.do_(function() ST.shot("scalerprobe_2_after_remedies") end)
    -- (2) a fresh actor, the scaler its ROOT (as the SOLG's body), grow played at rate 1; and one looping; its bones' names
    A.do_(function()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = SP.at, Scale3D = { X = 1, Y = 1, Z = 1 } }
        SP.roots = {}
        for i, loop in ipairs({ false, true }) do
            local okA, a2 = pcall(function() local x = gs:BeginDeferredActorSpawnFromClass(survivalPC, StaticFindObject("/Script/Engine.Actor"), t, 1, nil, 1); return gs:FinishSpawningActor(x, t, 1) end)
            local sc = okA and a2:AddComponentByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"), false, t, false)
            if sc then
                pcall(function() sc:SetSkeletalMeshAsset(SPC.V.asset(SPC.V.PORTAL_SCALER)) end)
                pcall(function() sc:PlayAnimation(SPC.V.asset(SPC.V.PORTAL_GROW), loop) end)
                SP.roots[i] = { a = a2, sc = sc, loop = loop }
                local names = {}
                pcall(function() for k = 0, sc:GetNumBones() - 1 do names[#names + 1] = sc:GetBoneName(k):ToString() end end)
                local okR, isRoot = pcall(function() return a2.RootComponent == sc end)
                ST.info(string.format("root scaler %d (loop %s): root %s, bones [%s], %s", i, tostring(loop), tostring(okR and isRoot), table.concat(names, ","), (spBone(sc))))
            end
        end
    end)
    for k = 1, 3 do
        A.wait(0.6)
        A.do_(function() for i, r in ipairs(SP.roots or {}) do ST.info(string.format("root scaler %d +%d: %s", i, k, (spBone(r.sc)))) end end)
    end
    A.do_(function()                                    -- (and a portal piece's scaler: its bones, the component's own tick)
        local e = SP.e
        if e and e.sc then
            local names = {}
            pcall(function() for k = 0, e.sc:GetNumBones() - 1 do names[#names + 1] = e.sc:GetBoneName(k):ToString() end end)
            local tk = {}
            pcall(function() tk[#tk + 1] = "tick enabled " .. tostring(e.sc:IsComponentTickEnabled()) end)
            pcall(function() tk[#tk + 1] = "active " .. tostring(e.sc:IsActive()) end)
            pcall(function() tk[#tk + 1] = "registered " .. tostring(e.sc:IsRegistered()) end)
            ST.info("piece scaler: bones [" .. table.concat(names, ",") .. "], " .. table.concat(tk, ", "))
        end
        for _, r in ipairs(SP.roots or {}) do pcall(function() r.a:K2_DestroyActor() end) end
    end)
    A.wait(0.5)
    A.do_(function()
        ST.lookBack()
        SPC.V.portalStop(SP.h)
    end)
end

-- ((2026-11-22) the SOLG's pitch came back 0: which way of tilting it sticks (read from its nose's direction, now and on))
local function spPitch(a)
    local ok, v = pcall(function() local f = a:GetActorForwardVector(); return math.deg(math.asin(math.max(-1, math.min(1, f.Z)))) end)
    return ok and v or nil
end
SUITES.solgpitch = function()
    intoRun()
    local T = {}
    local function fresh(at)
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local x = gs:BeginDeferredActorSpawnFromClass(survivalPC, StaticFindObject("/Script/Engine.Actor"), t, 1, nil, 1)
        return gs:FinishSpawningActor(x, t, 1)
    end
    local function dirs(c)
        local o = {}
        pcall(function() local f = c:GetForwardVector(); o[#o + 1] = string.format("fwd (%.2f, %.2f, %.2f)", f.X, f.Y, f.Z) end)
        pcall(function() local u = c:GetUpVector(); o[#o + 1] = string.format("up (%.2f, %.2f, %.2f)", u.X, u.Y, u.Z) end)
        return table.concat(o, " ")
    end
    local h = math.rad(-45) / 2
    local cases = {
        { "roll 45", function(c) c:K2_SetWorldRotation({ Pitch = 0, Yaw = 0, Roll = 45 }, false, {}, true) end },
        { "pitch -45", function(c) c:K2_SetWorldRotation({ Pitch = -45, Yaw = 0, Roll = 0 }, false, {}, true) end },
        { "pitch -45 by a transform's quaternion", function(c) c:K2_SetWorldTransform({ Rotation = { X = 0, Y = -math.sin(h), Z = 0, W = math.cos(h) },
            Translation = c:K2_GetComponentLocation(), Scale3D = { X = 1, Y = 1, Z = 1 } }, false, {}, true) end },
        { "pitch -45 added", function(c) c:K2_AddWorldRotation({ Pitch = -45, Yaw = 0, Roll = 0 }, false, {}, true) end },
        { "pitch -45 added local", function(c) c:K2_AddLocalRotation({ Pitch = -45, Yaw = 0, Roll = 0 }, false, {}, true) end },
        { "pitch -45 relative", function(c) c:K2_SetRelativeRotation({ Pitch = -45, Yaw = 0, Roll = 0 }, false, {}, true) end },
    }
    A.do_(function()
        local you = playerLocation()
        for i, cs in ipairs(cases) do
            local at = { X = you.X + 300000 * i, Y = you.Y, Z = you.Z + 300000 }
            local okA, a = pcall(fresh, at)
            local c = okA and a:AddComponentByClass(StaticFindObject("/Script/Engine.StaticMeshComponent"), false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
            if c then
                local ok, er = pcall(cs[2], c)
                ST.info(string.format("case %d (%s): %s; %s", i, cs[1], ok and "called" or ("error " .. tostring(er)), dirs(c)))
                T[i] = a
            end
        end
    end)
    A.wait(0.5)
    A.do_(function() for _, a in pairs(T) do pcall(function() a:K2_DestroyActor() end) end end)
end

-- ((2026-11-22) the user: "make the solg pieces targetable by air weapons too": which GameObjectCategory a target can
-- carry so both an AIR_ONLY and a GROUND_ONLY weapon select it. The SOLG 1.5 km ahead, one SAW target; your plane's
-- weapons' LockOnTargetType set to each type in turn, the target's category to each in turn, SelectTarget forced on it)
SUITES.airprobe = function()
    intoRun()
    local P = {}
    A.do_(function()
        local you, pl = playerLocation(), ST.plane()
        local f = pl:GetActorForwardVector()
        SOLG.C.pause_s = {}
        local at = { X = you.X + f.X * 150000, Y = you.Y + f.Y * 150000, Z = you.Z + 20000 }
        ST.check(SOLG.spawn(at, math.deg(math.atan(f.Y, f.X)), nil) == true, "the SOLG ahead of you")
    end)
    A.wait(1)
    A.do_(function()
        SOLG.targetsUp()
        for _, e in ipairs(SOLG.debugTargets()) do if e.key == "SAW" and e.open then P.e = e; break end end
        ST.check(P.e ~= nil, "an open SAW target", P.e and P.e.bone)
        local pl = ST.plane()
        local pa = addrOf(pl)
        local pc = nil
        pcall(function() pc = pl:GetController() end)
        local function ownerName(x) local ok, o = pcall(function() return x:GetOwner() end); return ok and o and (o:GetFullName():match("[^%.:]+$") or "?") or "none" end
        local function mineOrYours(x)
            local ok, o = pcall(function() return x:GetOwner() end)
            if not (ok and o) then return false end
            if addrOf(o) == pa or (pc and addrOf(o) == addrOf(pc)) then return true end
            local ok2, o2 = pcall(function() return o:GetOwner() end)
            return ok2 and o2 and addrOf(o2) == pa or false
        end
        local sels = FindAllOf("LiveTargetSelectionComponent") or {}
        for k, c in ipairs(sels) do
            if k <= 6 then ST.info("selection component " .. k .. ": owner " .. ownerName(c)) end
            if not P.sel and mineOrYours(c) then P.sel = c end
        end
        P.sel = P.sel or sels[1]
        P.w = {}
        local ws = FindAllOf("LiveWeaponBase") or {}
        for k, w in ipairs(ws) do
            if mineOrYours(w) then P.w[#P.w + 1] = w end
        end
        ST.info(string.format("%d selection components, %d weapons in all", #sels, #ws))
        for k = 1, math.min(5, #ws) do ST.info("weapon " .. k .. ": " .. (ws[k]:GetFullName():match("[^%.:]+$") or "?") .. ", owner " .. ownerName(ws[k])) end
        ST.info(string.format("selection component %s, your weapons %d", tostring(P.sel ~= nil), #P.w))
        pcall(function() ST.info("the target's category now: " .. tostring(P.e.o.GameObjectCategory)) end)
    end)
    local CATS = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
    local TYPES = { 0, 1, 2 }
    for _, ty in ipairs(TYPES) do
        for _, cat in ipairs(CATS) do
            A.do_(function()
                if not (P.e and P.sel) then return end
                for _, w in ipairs(P.w) do pcall(function() w.LockOnTargetType = ty end) end
                pcall(function() P.e.o.GameObjectCategory = cat end)
                local okS, got = pcall(function() return P.sel:SelectTarget(true, P.e.o, false) end)
                local cur = nil
                pcall(function() cur = P.sel:GetSelectedTarget() end)
                local hit = (okS and got and addrOf(got) == addrOf(P.e.o)) or (cur and addrOf(cur) == addrOf(P.e.o))
                ST.info(string.format("lock type %d, category %d: %s", ty, cat, hit and "SELECTED" or "not selected"))
            end)
            A.wait(0.3)
        end
    end
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
