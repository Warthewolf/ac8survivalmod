-- sv_valka_cine.lua: VALKA's arrival cutscene (the user, 2026-11-22: "Create a cutscene similar to the Invincible Fleets
-- Arrival of the Portal Opening, and Valka coming out of it, you dont have to make it for the portal closing"). Part of
-- AC8 Survival Mode's runtime, run by main.lua in MODULES' order after sv_anomalies_valka.lua: a name another part uses
-- is a global of this mod's Lua state, its own helpers stay local. In every build that has her (the fleet's surfacing,
-- sv_fleet_surface.lua, is test-only: its way is copied here, not called).
-- CFG.specials.valka.cine: from her portal's opening (sv_anomalies_valka.lua, her opener's charge) till she's out of it
-- and away: letterboxed shots in the portal's frame (two camera actors, the engine's blend from one to the other over
-- each shot), the last one riding on her; your plane on the autopilot and invincible, its attack limits at 0; the
-- game's HUD widgets and Survival's HUD held (Survival's callouts and subtitles let through: her name over her way out);
-- the game's camera shakes at the opening and at her shot; the fade, your view back. Log: `special: VALKA's cutscene ...`.
VCINE = {}
do
local S = nil
local HOLD = "VALKA's arrival"
local ATTACKERS = { "MaxPlaneAttackerMissiles", "MaxPursuitAttackers", "MaxNonPlaneAttackerMissiles" }
-- the game's HUD: the HUD actor's root widgets and the live flight HUD's (sv_cine.lua's `widgets` route, the one its
-- tests found to hide it: 6 of 6, 2026-11-17)
local HUD_FIELDS = { "GlowWidgetPtr", "NonGlowFrontWidgetPtr", "NonGlowBackWidgetPtr", "NonGlowWidget", "HUDMessageWidget" }
local HUD_CLASSES = { "WBP_HUD_Chronicle_MainFlight_000_C", "WBP_HUD_SubWidgets_Message_000_C" }
local HIDDEN = 2                                          -- (ESlateVisibility: 0 Visible, 1 Collapsed, 2 Hidden)
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function cl(s2) log("special: VALKA's cutscene: " .. s2) end
local function cc() return (CFG.specials.valka or {}).cine or {} end

local function hudActor()
    local hud
    pcall(function() hud = survivalPC:GetHUD() end)
    if not valid(hud) then pcall(function() hud = survivalPC.MyHUD end) end
    return valid(hud) and hud or nil
end
local function gameHudOff()
    local items, seen = {}, {}
    local function add(w)
        if w == nil or not liveObj(w) then return end
        local a = addrOf(w)
        if not a or seen[a] then return end
        seen[a] = true
        local okV, v = pcall(function() return w:GetVisibility() end)
        if not (okV and type(v) == "number" and v ~= 1 and v ~= HIDDEN) then return end
        pcall(function() w:SetVisibility(HIDDEN) end)
        local okR, v2 = pcall(function() return w:GetVisibility() end)
        if okR and v2 == HIDDEN then items[#items + 1] = { o = w, a = a, old = v } end
    end
    local hud = hudActor()
    if hud then for _, f in ipairs(HUD_FIELDS) do pcall(function() add(hud[f]) end) end end
    for _, c in ipairs(HUD_CLASSES) do
        for _, w in ipairs(FindAllOf(c) or {}) do
            local okN, nm = pcall(function() return w:GetFullName() end)
            if not (okN and tostring(nm):find("Default__", 1, true)) then add(w) end
        end
    end
    return items
end
local function gameHudKeep()                              -- hidden again if the game showed it
    for _, e in ipairs(S.hud or {}) do
        if liveObj(e.o) and addrOf(e.o) == e.a then
            local okV, v = pcall(function() return e.o:GetVisibility() end)
            if okV and v ~= HIDDEN then S.hudReverts = S.hudReverts + 1; pcall(function() e.o:SetVisibility(HIDDEN) end) end
        end
    end
end
local function gameHudBack()
    local back = 0
    for _, e in ipairs(S.hud or {}) do
        if liveObj(e.o) and addrOf(e.o) == e.a then
            local okV, v = pcall(function() return e.o:GetVisibility() end)
            if okV and v == HIDDEN and pcall(function() e.o:SetVisibility(e.old) end) then back = back + 1 end
        end
    end
    return back
end

-- ---- the portal's frame: its middle, her way out (ahead), right, up ----
local function off(m)
    local P, f, r = S.at, S.f, S.r
    return { X = P.X + (f.X * n(m[1], 0) + r.X * n(m[2], 0)) * 100, Y = P.Y + (f.Y * n(m[1], 0) + r.Y * n(m[2], 0)) * 100,
             Z = P.Z + n(m[3], 0) * 100 }
end
local function rotTo(at, look)
    local dx, dy, dz = look.X - at.X, look.Y - at.Y, look.Z - at.Z
    return { Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }
end

-- ---- the cameras: two actors, each shot cut to its `from` and blended to its `to` ----
local function newCam()
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local cls = StaticFindObject("/Script/Engine.CameraActor")
    if not (valid(gs) and valid(cls) and liveObj(survivalPC)) then return nil end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = off({ 0, 0, 200 }), Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)
    if not (okB and x and valid(x)) then return nil end
    pcall(function() gs:FinishSpawningActor(x, t, 1) end)
    local lb = n(cc().letterbox, 2.39)
    if lb > 0 then
        pcall(function() x.CameraComponent.bConstrainAspectRatio = true end)   -- (the black bars: the engine's own)
        pcall(function() x.CameraComponent.AspectRatio = lb end)
    end
    return x
end
local function view(cam, blend)
    if not (cam and valid(cam) and liveObj(survivalPC)) then return false end
    return pcall(function() survivalPC:SetViewTargetWithBlend(cam, blend or 0, n(cc().blend_fn, 0), 1, false) end)
end
local function place(cam, pose)
    local at, look = off(pose.at or { 0, 0, 0 }), off(pose.look or { 0, 0, 0 })
    pcall(function() cam:K2_DetachFromActor(1, 1, 1) end)
    pcall(function() cam:K2_SetActorLocationAndRotation(at, rotTo(at, look), false, {}, true) end)
    pcall(function() cam.CameraComponent:SetFieldOfView(n(pose.fov, 55)) end)
end
-- a camera riding on her: m = { behind m, right m, up m }, looking along her nose
local function ride(cam, her, m, fov)
    local okA = pcall(function() cam:K2_AttachToActor(her, FName("None"), 2, 2, 1, false) end)   -- (SnapToTarget)
    if not okA then return false end
    local ok = pcall(function()
        cam:K2_SetActorRelativeLocation({ X = -n(m[1], 40) * 100, Y = n(m[2], 0) * 100, Z = n(m[3], 8) * 100 }, false, {}, true)
    end)
    pcall(function() cam:K2_SetActorRelativeRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, true) end)
    pcall(function() cam.CameraComponent:SetFieldOfView(n(fov, 58)) end)
    return ok
end
local function shotGo(i)
    local shots = cc().shots or {}
    local sh = shots[i]
    for _, k in ipairs({ "a", "b" }) do
        if not (S.cams[k] and valid(S.cams[k])) then S.cams[k] = newCam() end
        if not S.cams[k] then return false, 0, "no camera" end
    end
    local dur = math.max(0.1, n(shots[i + 1] and shots[i + 1].t, n(cc().end_s, 14)) - n(sh.t, 0))
    S.shotEnd = S.t0 + n(sh.t, 0) + dur
    if sh.chase then
        local her = glitchActor and glitchActor(CFG.specials.valka) or nil
        if her and liveObj(her) and ride(S.cams.a, her, sh.chase, sh.from and sh.from.fov) then
            S.riding = true
            return view(S.cams.a, 0), dur, "riding on her"
        end
    end
    S.riding = false
    local from = sh.from or { at = { 1000, 0, 0 } }
    local to = sh.to
    place(S.cams.a, from)
    local okA = view(S.cams.a, 0)
    if not to then S.last = "a"; return okA, dur, "still" end
    place(S.cams.b, to)
    local okB = view(S.cams.b, dur)
    S.last = "b"
    return okA and okB, dur, "a move"
end
local function onCams(vt)
    local a = addrOf(vt)
    return a ~= nil and (a == addrOf(S.cams.a) or a == addrOf(S.cams.b))
end
-- ((2026-11-22) the runs of 15:13 and 15:45: from her shot on the screen showed your plane, though no view revert was
-- seen (GetViewTarget's pcall failed every time). The screen's camera (the camera manager's place) against ours: further
-- than 300 m from the line between our two cameras (a blend runs along it) or from the riding one, it isn't ours)
local function at(o)
    local okL, L = pcall(function() return o:K2_GetActorLocation() end)
    return okL and L and { X = L.X, Y = L.Y, Z = L.Z } or nil
end
local function povOff()
    local okP, P = pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not (okP and P) then return nil end
    local a = S.cams.a and valid(S.cams.a) and at(S.cams.a)
    local b = (not S.riding) and S.last == "b" and S.cams.b and valid(S.cams.b) and at(S.cams.b) or a
    if not a then return nil end
    local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    local L2 = dx * dx + dy * dy + dz * dz
    local u = L2 > 0 and math.max(0, math.min(1, ((P.X - a.X) * dx + (P.Y - a.Y) * dy + (P.Z - a.Z) * dz) / L2)) or 0
    local cx, cy, cz = a.X + dx * u, a.Y + dy * u, a.Z + dz * u
    return math.sqrt((P.X - cx) ^ 2 + (P.Y - cy) ^ 2 + (P.Z - cz) ^ 2) / 100, P
end
local SHAKES = {}
local function shake(spec)                                -- spec { path, scale }: the game's camera shake on your camera
    if type(spec) ~= "table" or type(spec[1]) ~= "string" or not liveObj(survivalPC) then return false end
    local cls = SHAKES[spec[1]]
    if not (cls and liveObj(cls)) then
        cls = loadObject(spec[1] .. "." .. spec[1]:match("[^/]+$") .. "_C")
        SHAKES[spec[1]] = cls
    end
    if not cls then return false end
    local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
    if pcall(function() survivalPC:ClientStartCameraShake(cls, n(spec[2], 1), 0, rot) end) then return true end
    return pcall(function() survivalPC.PlayerCameraManager:StartCameraShake(cls, n(spec[2], 1), 0, rot) end)
end
local function fade(from, to, dur, hold)
    return pcall(function()
        survivalPC.PlayerCameraManager:StartCameraFade(from, to, dur, { R = 0, G = 0, B = 0, A = 1 }, false, hold)
    end)
end

-- ---- your plane held on the autopilot meanwhile ----
local function playerHold(on)
    local pawn = liveObj(survivalPC) and survivalPC.Pawn or nil
    if not valid(pawn) then return "no plane of yours" end
    if DOWN and DOWN.me and DOWN.me() then                -- (DOWN keeps its own: safe, held, its spectator view)
        if on then S.limits, S.down = {}, true end
        return "you're DOWN: your plane, controls and view left to DOWN"
    end
    if on then
        local me = playerLocation()
        local c = cc()
        local alt = math.max(n(c.autopilot_alt_m, 1500), me and me.Z / 100 or 0)
        if type(SV_Down) == "function" and me then pcall(SV_Down, addrOf(pawn) or 0, me.X, me.Y, alt, n(c.autopilot_radius_m, 3500)) end
        if playerLocationDirty then playerLocationDirty() end
        pcall(function() pawn:SetIsInvincible(true) end)
        S.limits = {}
        for _, f in ipairs(ATTACKERS) do
            local okR, v = pcall(function() return pawn[f] end)
            if okR and type(v) == "number" and pcall(function() pawn[f] = 0 end) then S.limits[f] = v end
        end
        return "your plane invincible on the autopilot, the attack limits at 0"
    end
    if S.down then return "DOWN's view kept" end
    pcall(function() survivalPC:SetViewTargetWithBlend(pawn, 0, 0, 0, false) end)
    pcall(function() pawn:SetIsInvincible(false) end)
    for f, v in pairs(S.limits or {}) do pcall(function() pawn[f] = v end) end
    if type(SV_Down) == "function" then pcall(SV_Down, 0); if playerLocationDirty then playerLocationDirty() end end
    return "your view and plane back"
end

local function over(why)
    for _, k in ipairs({ "a", "b" }) do
        if S.cams[k] and valid(S.cams[k]) then pcall(function() S.cams[k]:K2_DestroyActor() end) end
    end
    local back = playerHold(false)
    local hb = gameHudBack()
    if HUD and HUD.hold then pcall(HUD.hold, false, HOLD) end
    cl(string.format("over (%s) at +%.1f s: %d shots, %s; the game's HUD back (%d of %d widgets, hidden again %d times), %d view reverts kept back",
        why, (S.now or S.t0) - S.t0, S.shot, back, hb, #(S.hud or {}), S.hudReverts, S.reverts))
    S = nil
    if VCINE.after then pcall(VCINE.after, why) end        -- (the self-test's hold back on its plane)
end

-- from her portal's opening: true if it films
function VCINE.start(c, s, at, yaw, now)
    local k = c.cine
    if not (type(k) == "table" and k.enabled and at and liveObj(survivalPC)) then return false end
    if S then over("a new one") end
    local a = math.rad(yaw or 0)
    S = { t0 = now, at = { X = at.X, Y = at.Y, Z = at.Z }, f = { X = math.cos(a), Y = math.sin(a) }, r = { X = -math.sin(a), Y = math.cos(a) },
          cams = {}, shot = 0, reverts = 0, hudReverts = 0, phase = "film", s = s }
    S.said = playerHold(true)
    S.hud = gameHudOff()
    local hh = HUD and HUD.hold and select(2, pcall(HUD.hold, true, HOLD, { callouts = true }))
    local sk = shake((k.shake or {}).open)
    cl(string.format("starts: %d shots over %.1f s, letterbox %s; %s; the game's HUD: %d widgets hidden; Survival's held %s; shake %s",
        #(k.shots or {}), n(k.end_s, 14), tostring(n(k.letterbox, 2.39)), S.said, #S.hud, tostring(hh), sk and "on" or "off"))
    return true
end
function VCINE.active() return S ~= nil and S.phase ~= "back" end
function VCINE.state() return S and { phase = S.phase, shot = S.shot, t = (S.now or S.t0) - S.t0, riding = S.riding } or nil end
function VCINE.tick(c, s, now)
    if not S then return end
    if (levelTorn and levelTorn()) or not D then S = nil; return end
    local k = cc()
    local t = now - S.t0
    S.now = now
    if S.phase == "film" then
        if s.state == "done" or t >= n(k.max_s, 25) then over(s.state == "done" and "her round over" or "too long"); return end
        if s.state ~= S.lastState then                   -- (her shot: the shake)
            if s.state == "shot" then shake((k.shake or {}).shot) end
            S.lastState = s.state
        end
        local shots = k.shots or {}
        while shots[S.shot + 1] and t >= n(shots[S.shot + 1].t, 0) do
            S.shot = S.shot + 1
            local ok, dur, how = shotGo(S.shot)
            cl(string.format("shot %d at +%.1f s: %s, %.1f s%s", S.shot, t, tostring(how), dur, ok and "" or " (the view NOT taken)"))
        end
        local cam = S.last and S.cams[S.last]
        if S.riding then cam = S.cams.a end
        if cam and valid(cam) and liveObj(survivalPC) then   -- (the view kept on the cameras: the game may take it)
            local off, P = povOff()
            if off and off > 300 then
                S.reverts = S.reverts + 1
                if S.reverts <= 3 then
                    local okV, vt = pcall(function() return survivalPC.PlayerCameraManager.ViewTarget.Target end)
                    cl(string.format("+%.1f s the screen's camera is %.0f m off ours (at (%.2f, %.2f, %.2f) km, view target %s, her state %s): taken back",
                        t, off, P.X / 100000, P.Y / 100000, P.Z / 100000, okV and vt and nameOf(vt) or "?", tostring(s.state)))
                end
                view(cam, S.riding and 0 or math.max(0, (S.shotEnd or now) - now))
            end
        end
        gameHudKeep()
        -- ((2026-11-22) the run of 15:13 showed your plane's view from her shot on, and our cameras rolled, with no view
        -- revert seen: what the screen's camera is, each second (the view target, the camera manager's place and turn,
        -- ours), so the next run says who has it)
        if not S.diagAt or now >= S.diagAt then
            S.diagAt = now + 1
            local okD, errD = pcall(function()
                local pcm = survivalPC.PlayerCameraManager
                local okT, vt = pcall(function() return pcm.ViewTarget.Target end)
                local okR, R = pcall(function() local r = pcm:GetCameraRotation(); return { P = r.Pitch, Y = r.Yaw, R = r.Roll } end)
                local off, P = povOff()
                cl(string.format("+%.1f s the screen's camera %s m off ours%s, turned %s; view target %s",
                    t, off and string.format("%.0f", off) or "?",
                    P and string.format(" (at %.2f, %.2f, %.2f km)", P.X / 100000, P.Y / 100000, P.Z / 100000) or "",
                    okR and R and string.format("(%.0f, %.0f, %.0f)", R.P, R.Y, R.R) or "?",
                    okT and vt and (nameOf(vt) .. (onCams(vt) and " (ours)" or "")) or "?"))
            end)
            if not okD and not S.diagErr then S.diagErr = true; cl("the view's line not read: " .. tostring(errD)) end
        end
        if t >= n(k.end_s, 14) then
            local f = k.fade or {}
            local okF = fade(0, 1, n(f.out_s, 0.6), true)
            S.phase, S.at = "out", now + (okF and n(f.out_s, 0.6) or 0)
        end
    elseif S.phase == "out" and now >= S.at then
        S.phase, S.at = "hold", now + n((k.fade or {}).hold_s, 0.3)
        gameHudKeep()
    elseif S.phase == "hold" and now >= S.at then
        S.phase = "back"
        fade(1, 0, n((k.fade or {}).in_s, 0.9), false)
        over("filmed")
    end
end
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["VALKA's cutscene"] = function() S = nil end
end
end
