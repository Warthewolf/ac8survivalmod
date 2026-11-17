-- sv_fleet_surface.lua: INVINCIBLE FLEET's surfacing, the cutscene at round 30's start and at Ctrl+N (the user's dev install
-- only; 2026-11-16, made epic 2026-11-17: the user, "can you please make the Ships Rising out of the sea cutscene more
-- cinematic? like go epic with it"), sv_fleet.lua's piece after sv_fleet_lasers.lua (moved out of sv_fleet.lua whole, its
-- file near the 2,000-line limit). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order: a name another
-- part uses is a global of this mod's Lua state, its own helpers stay local (it shares none of sv_fleet.lua's locals). The
-- whole piece is one test-only block, which tools/strip_test_only.py takes out of every release and test zip, and
-- tools/dev_only.py out of a TESTER zip, only this header left there.
-- CFG.specials.fleet.surface (sv_fleet.lua): the 15 ships' doubles rise in waves (pickets first, GEOFON last) after lead_s
-- of empty sea; each shot a camera move (two camera actors, the engine's blend from one to the other over the shot) in its
-- ship's frame, letterboxed (the cameras' aspect ratio held); shakes at the breaches and slams near the camera, GEOFON's the
-- big one; the water's roar at a breach near it; beats on the clock: the storm's strikes on cue (sv_fleet_storm.lua's
-- IFSKY.strike, the storm's own ones further apart meanwhile), the radio (SUB.say) and the title card (the callout); your
-- plane on the autopilot, both HUDs held (the callouts and subtitles let through), then the fade, the swap, your view back.
-- Log: `fleet surfacing: ...`.
-- TEST ONLY BEGIN (INVINCIBLE FLEET's surfacing: test builds only, the user's dev install)
IFSURF = {}
do
local S = nil
local ATTACKERS = { "MaxPlaneAttackerMissiles", "MaxPursuitAttackers", "MaxNonPlaneAttackerMissiles" }
local HOLD = "the fleet's surfacing"
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function cs() return (CFG.specials and CFG.specials.fleet or {}).surface or {} end
local function quat(yaw) local h = math.rad(yaw) / 2; return { X = 0, Y = 0, Z = math.sin(h), W = math.cos(h) } end
local function slog(s2) log("fleet surfacing: " .. s2) end
local function same(e) return e ~= nil and e.a ~= nil and liveAddr(e.o) == e.a and nameOf(e.o) == e.name end
local function kept(o) return { o = o, a = addrOf(o), name = nameOf(o) } end
local function frame()                                    -- GEOFON's spot, the course's forward and right, its yaw
    local f = (CFG.specials.fleet or {}).formation or {}
    local rw = f.runway_cm or { 1610476, -436143 }
    local yaw = n(f.course_yaw, 45)
    local a = math.rad(yaw)
    local ux, uy = math.cos(a), math.sin(a)
    local d = n(cs().start_km, 30.5) * 100000
    return { X = rw[1] - ux * d, Y = rw[2] - uy * d }, { X = ux, Y = uy }, { X = -uy, Y = ux }, yaw
end
local function spotOf(G, u, r, c)                         -- a ship's spot from its formation offsets (sv_fleet.lua fleetList's)
    local f, rr = n(c.fwd_m, 0) * 100, n(c.right_m, 0) * 100
    return { X = G.X + u.X * f + r.X * rr, Y = G.Y + u.Y * f + r.Y * rr, Z = 0 }
end
local function off(p, u, r, m)                            -- metres { forward, right, up } off p, in the course's frame
    return { X = p.X + (u.X * m[1] + r.X * m[2]) * 100, Y = p.Y + (u.Y * m[1] + r.Y * m[2]) * 100, Z = (p.Z or 0) + n(m[3], 0) * 100 }
end
local function spawnDeferred(cls, at, yaw, sc)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (valid(gs) and valid(cls) and liveObj(survivalPC)) then return nil end
    local t = { Rotation = quat(yaw), Translation = at, Scale3D = { X = sc, Y = sc, Z = sc } }
    local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)
    if not (okB and x and valid(x)) then return nil end
    return x, t, gs
end
local SYS = {}                                            -- ((0.74.145) each system loaded once, kept with its name (hard rule
local function sysOf(path)                                -- 59): the surfacing's 300+ waters loaded each by path cost ~9 ms a tick)
    local e = SYS[path]
    if e and liveObj(e.o) and nameOf(e.o) == e.n then return e.o end
    local o = loadObject(path .. "." .. (path:match("[^/]+$") or ""))
    SYS[path] = o and { o = o, n = nameOf(o) } or nil
    return o
end
local function fxAt(name, at, sc)                         -- one of TANI.rise.FX's waters, kept to be stopped at its life
    local FX = TANI and TANI.rise and TANI.rise.FX or {}
    local path = FX[name]
    if not path then return false end
    local sys = sysOf(path)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (sys and valid(lib) and liveObj(survivalPC)) then return false end
    local okS, comp = pcall(function()
        return lib:SpawnSystemAtLocation(survivalPC, sys, at, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc }, true, true, 0, false)
    end)
    if not (okS and comp) then return false end
    S.fx[#S.fx + 1] = { e = kept(comp), off = os.clock() + n(cs().fx_life_s, 8) }
    return true
end
-- ((0.74.134) the user: "go over the VFX used for the Invincible fleets rise out of the ocean also, it could use more VFX
-- work on all the ships") cs().water: each ship's water from its bow's breach point (breach_m x its scale forward of its
-- rest midships, where the rig's motion breaks the surface), sprays round its bow as it climbs and along its hull as it
-- falls, the slam along its whole keel on both sides, foam as it settles; denser on bigger ships (dens), never more than
-- max_live waters up at once (S.fx)
local function wc() return cs().water or {} end
local function shipSpot(sh, fwd_m, right_m)              -- a spot on the sea in a ship's frame (metres, scaled by its size)
    return off({ X = sh.spot.X, Y = sh.spot.Y, Z = 0 }, S.u, S.r, { fwd_m * sh.sc, right_m * sh.sc, 0 })
end
local function room() return #S.fx < n(wc().max_live, 150) end
local function wAt(sh, e, at)                            -- one water e = { FX name, scale } at at, the ship's own scale on it
    if not room() then S.capped = (S.capped or 0) + 1; return false end
    local ok = fxAt(e[1], at, math.max(0.25, sh.sc * n(cs().fx_x, 2)) * n(e[2], 1))
    sh.wUp, sh.wOf = (sh.wUp or 0) + (ok and 1 or 0), (sh.wOf or 0) + 1
    return ok
end
local function dense(sh) return math.random() <= math.min(1, math.max(n(wc().min_dens, 0.35), sh.sc * n(wc().dens, 3))) end
local function shipWater(sh, r0, now)                    -- every tick of a ship's rise: its climb, fall and settle
    local w = wc()
    if w.enabled == false then return end
    local bm = n(w.breach_m, 115.8)
    if r0 >= n(cs().breach_s, 0.8) and r0 < n(w.climb_until_s, 5.5) and now >= (sh.climbAt or 0) then   -- (round its bow)
        sh.climbAt = now + n(w.climb_every_s, 0.5)
        if dense(sh) then
            local l = w.climb or {}
            local e = l[(sh.climbN or 0) % math.max(1, #l) + 1]
            sh.climbN = (sh.climbN or 0) + 1
            local a, rr = math.rad(math.random(0, 359)), math.random(n(w.ring_m and w.ring_m[1], 25), n(w.ring_m and w.ring_m[2], 60))
            if e then wAt(sh, e, shipSpot(sh, bm + math.cos(a) * rr, math.sin(a) * rr)) end
        end
    end
    if r0 >= n(w.climb_until_s, 5.5) and r0 < n(cs().slam_s, 9) and now >= (sh.fallAt or 0) then         -- (down along its hull)
        sh.fallAt = now + n(w.fall_every_s, 0.45)
        if dense(sh) then
            local l = w.fall or {}
            local e = l[(sh.fallN or 0) % math.max(1, #l) + 1]
            sh.fallN = (sh.fallN or 0) + 1
            local back = (r0 - n(w.climb_until_s, 5.5)) / math.max(0.1, n(cs().slam_s, 9) - n(w.climb_until_s, 5.5)) * 300
            local side = (sh.fallN % 2 == 0) and 1 or -1
            if e then wAt(sh, e, shipSpot(sh, bm - back * math.random(), side * math.random(30, 50))) end
        end
    end
    if r0 >= n(cs().slam_s, 9) and r0 < n(cs().slam_s, 9) + n(w.settle_s, 4) and now >= (sh.settleAt or 0) then   -- (foam)
        sh.settleAt = now + n(w.settle_every_s, 0.7)
        if dense(sh) and w.settle then wAt(sh, w.settle, shipSpot(sh, math.random(-280, 280), math.random(-40, 40))) end
    end
end
local function keelSlam(sh)                              -- the slam along its whole keel, both sides
    local w = wc()
    if w.enabled == false then return end
    local k = math.max(2, math.floor(n(w.keel_spots, 6) * math.min(1, math.max(0.34, sh.sc * 3)) + 0.5))
    for i = 0, k - 1 do
        local f = -300 + 600 * i / (k - 1)
        for _, e in ipairs(w.keel or {}) do
            for _, y in ipairs({ -45, 45 }) do wAt(sh, e, shipSpot(sh, f, y)) end
        end
    end
end
local function water(sh, list, at)
    local up, of = 0, 0
    local sc = math.max(0.3, sh.sc * n(cs().fx_x, 2))
    for _, w in ipairs(type(list) == "table" and list or {}) do
        of = of + 1
        if room() and fxAt(w[1], at or { X = sh.spot.X, Y = sh.spot.Y, Z = 0 }, sc * n(w[2], 1)) then up = up + 1 end
    end
    return up, of
end
-- ---- the camera's side: its spot, a shake, a sound on it ----
local function camAt()
    local L
    pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
    return L
end
local function nearCam(spot, m)                           -- a ship's spot within m metres of the camera (flat)
    local L = camAt()
    if not (L and spot) then return false end
    return math.sqrt((L.X - spot.X) ^ 2 + (L.Y - spot.Y) ^ 2) <= m * 100
end
local SHAKES = {}
local function shake(spec)                                -- spec { path, scale }: the game's camera shake on your camera
    if type(spec) ~= "table" or type(spec[1]) ~= "string" or not liveObj(survivalPC) then return false end
    local path = spec[1]
    local cls = SHAKES[path]
    if not (cls and liveObj(cls)) then
        cls = loadObject(path .. "." .. path:match("[^/]+$") .. "_C")
        SHAKES[path] = cls
    end
    if not cls then return false end
    local rot, sc = { Pitch = 0, Yaw = 0, Roll = 0 }, n(spec[2], 1)
    if pcall(function() survivalPC:ClientStartCameraShake(cls, sc, 0, rot) end) then return true end
    return pcall(function() survivalPC.PlayerCameraManager:StartCameraShake(cls, sc, 0, rot) end)
end
local function sound(name)
    if type(name) ~= "string" or name == "" or not (IFSKY and IFSKY.post) then return "no sound" end
    local ok, r = pcall(IFSKY.post, name)
    return ok and tostring(r) or ("error " .. tostring(r))
end
-- ---- the cameras: two actors, each shot cut to its `from` and blended to its `to` ----
local function view(cam, blend)
    if not (cam and valid(cam) and liveObj(survivalPC)) then return false end
    local fn = n(cs().blend_fn, 0)
    return pcall(function() survivalPC:SetViewTargetWithBlend(cam, blend or 0, fn, 1, false) end)
end
local function newCam(at, yaw)
    local x, t, gs = spawnDeferred(StaticFindObject("/Script/Engine.CameraActor"), at, yaw, 1)
    if not x then return nil end
    pcall(function() gs:FinishSpawningActor(x, t, 1) end)
    local lb = cs().letterbox or {}
    local on = lb.enabled ~= false
    pcall(function() x.CameraComponent.bConstrainAspectRatio = on end)      -- (the black bars: the engine's own)
    if on then pcall(function() x.CameraComponent.AspectRatio = n(lb.aspect, 2.39) end) end
    return x
end
local function place(cam, p, pose)                        -- a camera at pose { at, look, fov } in its ship's frame
    local at, look = off(p, S.u, S.r, pose.at or { 0, 0, 0 }), off(p, S.u, S.r, pose.look or { 0, 0, 0 })
    local dx, dy, dz = look.X - at.X, look.Y - at.Y, look.Z - at.Z
    local yaw, pitch = math.deg(math.atan(dy, dx)), math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
    pcall(function() cam:K2_SetActorLocationAndRotation(at, { Pitch = pitch, Yaw = yaw, Roll = 0 }, false, {}, true) end)
    pcall(function() cam.CameraComponent:SetFieldOfView(n(pose.fov, 55)) end)
end
local function camTo(i, t)                                -- shot i: cut to its from, blend to its to over the shot
    local shots = cs().shots or {}
    local sh0 = shots[i]
    local p = S.spots[sh0.ship] or S.G
    for _, k in ipairs({ "a", "b" }) do
        if not (S.cams[k] and valid(S.cams[k])) then S.cams[k] = newCam(off(p, S.u, S.r, { 0, 0, 50 }), S.yaw) end
        if not S.cams[k] then return false, 0 end
    end
    local from = sh0.from or { at = sh0.at, look = sh0.look, fov = sh0.fov }
    local to = sh0.to or from
    local dur = math.max(0.1, n(shots[i + 1] and shots[i + 1].t, S.overAt) - n(sh0.t, 0))
    place(S.cams.a, p, from)
    place(S.cams.b, p, to)
    local okA = view(S.cams.a, 0)
    local okB = view(S.cams.b, dur)
    S.shotEnd = S.t0 + n(sh0.t, 0) + dur
    return okA and okB, dur
end
local function onCams(vt)
    local a = addrOf(vt)
    return a ~= nil and (a == addrOf(S.cams.a) or a == addrOf(S.cams.b))
end
-- ---- your plane held on the autopilot meanwhile ----
local function playerHold(on)
    local pawn = liveObj(survivalPC) and survivalPC.Pawn or nil
    if not valid(pawn) then return "no plane of yours" end
    if on then
        local me = playerLocation()
        local c = cs()
        local alt = math.max(n(c.autopilot_alt_m, 1500), me and me.Z / 100 or 0)
        if type(SV_Down) == "function" and me then pcall(SV_Down, addrOf(pawn) or 0, me.X, me.Y, alt, n(c.autopilot_radius_m, 3500)) end
        playerLocationDirty()
        pcall(function() pawn:SetIsInvincible(true) end)
        S.limits = {}
        for _, f in ipairs(ATTACKERS) do
            local okR, v = pcall(function() return pawn[f] end)
            if okR and type(v) == "number" and pcall(function() pawn[f] = 0 end) then S.limits[f] = v end
        end
        return "your plane invincible on the autopilot, the attack limits at 0"
    end
    pcall(function() survivalPC:SetViewTargetWithBlend(pawn, 0, 0, 0, false) end)
    pcall(function() pawn:SetIsInvincible(false) end)
    for f, v in pairs(S.limits or {}) do pcall(function() pawn[f] = v end) end
    if type(SV_Down) == "function" then pcall(SV_Down, 0); playerLocationDirty() end
    return "your view and plane back"
end
local function clearDoubles()
    local nD = 0
    for _, sh in ipairs(S.ships) do
        if sh.d and same(sh.d) then pcall(function() sh.d.o:K2_DestroyActor() end); nD = nD + 1 end
        if sh.rig and same(sh.rig) then pcall(function() sh.rig.o:K2_DestroyActor() end) end
        sh.d, sh.rig = nil, nil
    end
    return nD
end
-- ---- the beats on the clock: a strike on cue, a radio line, the title card ----
local function beat(b)
    if b.bolt then
        local p = S.spots[b.bolt.ship] or S.G
        local at = off(p, S.u, S.r, { n(b.bolt.fwd_m, 0), n(b.bolt.right_m, 0), n(b.bolt.up_m, 3000) })
        if not (IFSKY and IFSKY.strike) then return "a strike: no IFSKY.strike" end
        local ok, okS, what = pcall(IFSKY.strike, at, HOLD)
        return "a strike by " .. tostring(b.bolt.ship) .. ": " .. (ok and tostring(what) or ("error " .. tostring(okS)))
    elseif b.say then
        local code, text = tostring(b.say):match("^([^|]+)|(.+)$")
        local sp = ((CFG.hud or {}).subs or {}).speakers or {}
        if not (code and SUB and SUB.say) then return "a line NOT said (no SUB, or not CODE|text)" end
        local ok = pcall(SUB.say, sp[code] or code, text)
        return string.format("%s says '%s'%s", code, text, ok and "" or " (SUB.say FAILED)")
    elseif b.title then
        local tc = cs().title or {}
        if type(hudCallout) ~= "function" then return "the title: no hudCallout" end
        pcall(hudCallout, tc.text or "INVINCIBLE FLEET", tc.sub, tc.big)
        return "the title card " .. tostring(tc.text or "INVINCIBLE FLEET")
    end
    return "an empty beat"
end
function IFSURF.start(F)
    local c = cs()
    if c.enabled == false or (COOP and COOP.client and COOP.client() == true) then return false end   -- (the host's: WP12 brings joiners)
    local mesh, anim = loadObject(c.rig), loadObject(c.anim)
    if not (mesh and anim) then slog("her rig or its rise didn't load (a build without the Tanicorn container?): the fleet as before"); return false end
    local G, u, r, yaw = frame()
    S = { F = F, t0 = os.clock(), G = G, u = u, r = r, yaw = yaw, ships = {}, spots = {}, fx = {}, mesh = mesh, anim = anim,
          shot = 0, beat = 0, cams = {}, phase = "rise", seed = math.floor(os.clock() * 1000) % 100000, shakes = 0, sounds = 0 }
    local x = S.seed
    local function rnd() x = (x * 1103515245 + 12345) % 2147483648; return x / 2147483648 end
    local last, lead = 0, n(c.lead_s, 0)
    for _, sc0 in ipairs((CFG.specials.fleet or {}).ships or {}) do
        local cl = (c.classes or {})[sc0.kind]
        if cl then
            local sh = { key = sc0.key, name = sc0.name, kind = sc0.kind, spot = spotOf(G, u, r, sc0), cls = cl[1],
                         sc = n(cl[2], 150) / n(c.tani_m, 650), at = lead + n((c.waves or {})[sc0.kind], 0) + rnd() * n(c.jitter_s, 1) }
            S.spots[sc0.key] = sh.spot
            if sc0.name and sc0.name ~= "" then S.spots[sc0.name] = sh.spot end
            S.ships[#S.ships + 1] = sh
            last = math.max(last, sh.at)
        end
    end
    S.overAt = last + n(c.length_s, 15) + n(c.end_pad_s, 1)
    F.nextAt, F.burst = math.huge, #(F.queue or {})        -- (the real fleet held, then up at once under the fade)
    S.said = playerHold(true)
    -- ((2026-11-17) the user: "during the cutscenes ... we need to disable the HUD") Survival's HUD and the game's (sv_cine.lua's
    -- routes, the target boxes too) held off till it's over; Survival's callouts and subtitles let through (its radio, its title)
    local hh = HUD and HUD.hold and select(2, pcall(HUD.hold, true, HOLD, { callouts = true }))
    local okG, gh = false, nil
    if CINE and CINE.hudHide then okG, gh = pcall(CINE.hudHide, HOLD, S.overAt + 10) end
    local dropped = 0                                     -- (banners waiting from before, a test key's: not over the opening shot)
    if type(callouts) == "table" then dropped = #callouts; for i = #callouts, 1, -1 do callouts[i] = nil end end
    local hand = (c.shake or {}).hand
    S.hand = hand and shake(hand) or false
    slog(string.format("%d ships rise over %.1f s (%.1f s of sea first; waves %s), %d shots, %d beats, letterbox %s; %s; the HUD held (Survival's %s, the game's %s); hand-held shake %s; %d banners dropped",
        #S.ships, S.overAt, lead, "pickets first, GEOFON last", #(c.shots or {}), #(c.beats or {}),
        (c.letterbox or {}).enabled == false and "off" or tostring(n((c.letterbox or {}).aspect, 2.39)), S.said, tostring(hh),
        okG and tostring(gh) or "no sv_cine", S.hand and "on" or "off", dropped))
    return true
end
-- the storm's own strikes x this further apart while the surfacing films (sv_fleet_storm.lua's lightTick); 1 when it's not
function IFSURF.quiet() return S and n(cs().storm_quiet_x, 1) or 1 end
local function hit(sh, what)                              -- a breach or slam: its shake and its roar, when near the camera
    local c = cs()
    local k = c.shake or {}
    local big = what == "slam" and sh.kind == "ford"
    local spec = big and k.geofon or k[what]
    local said = ""
    if spec and (big or nearCam(sh.spot, n(k.near_m, 1500))) and shake(spec) then
        S.shakes = S.shakes + 1
        said = big and ", the big shake" or ", a shake"
    end
    -- ((0.74.136) the user: "Keep going", the night's sprays faint in run 20261117_182008's pictures) a big ship's breach
    -- near the camera lit by a strike beside it (IFSKY.strike: its bolt, its cloud flash, the storm's light on your camera)
    local st = (c.water or {}).strike or {}
    if what == "breach" and st.enabled ~= false and (st.kinds or {})[sh.kind] and IFSKY and IFSKY.strike
        and nearCam(sh.spot, n(st.near_m, 3000)) and os.clock() >= (S.strikeAt or 0) then
        S.strikeAt = os.clock() + n(st.gap_s, 1.5)
        local o = st.off_m or { -600, -900 }
        local okS, okK = pcall(IFSKY.strike, off({ X = sh.spot.X, Y = sh.spot.Y, Z = 0 }, S.u, S.r, { n(o[1], -600) * sh.sc * 2, n(o[2], -900), n(st.up_m, 3000) }), HOLD)
        S.strikes = (S.strikes or 0) + ((okS and okK) and 1 or 0)
        said = said .. ((okS and okK) and ", a strike beside it" or "")
    end
    local sp = c.splash or {}
    if what == "breach" and sp.sound and nearCam(sh.spot, n(sp.near_m, 2500)) and S.sounds < n(sp.max, 12) then
        S.sounds = S.sounds + 1
        said = said .. ", its roar " .. sound(sp.sound)
    end
    return said
end
local function shipTick(sh, now)
    local c = cs()
    local t = now - S.t0
    if not sh.rig then                                    -- its rig, at its rest pose (measured next tick)
        local x, tr, gs = spawnDeferred(StaticFindObject("/Script/Engine.SkeletalMeshActor"), { X = sh.spot.X, Y = sh.spot.Y, Z = 0 }, S.yaw, sh.sc)
        if not x then sh.failed = "its rig didn't spawn"; return end
        local m = x.SkeletalMeshComponent
        pcall(function() m:SetSkeletalMeshAsset(S.mesh) end)
        pcall(function() m.VisibilityBasedAnimTickOption = 0 end)
        pcall(function() m.bEnableUpdateRateOptimizations = false end)
        pcall(function() gs:FinishSpawningActor(x, tr, 1) end)
        pcall(function() m:SetAnimationMode(1, true) end)
        pcall(function() m:SetAnimation(S.anim) end)
        pcall(function() m:SetPosition(n(c.length_s, 15), false) end)
        sh.rig, sh.m, sh.state = kept(x), m, "measure"
        return
    end
    if not same(sh.rig) then sh.failed = sh.failed or "its rig gone"; return end
    if sh.state == "measure" then                         -- its rest's SOC_Hull onto the spot, then its start pose and its double
        local okS, sk = pcall(function() return sh.m:GetSocketLocation(FName("SOC_Hull")) end)
        local okL, rl = pcall(function() return sh.rig.o:K2_GetActorLocation() end)
        if okS and okL and sk and rl then
            local to = { X = rl.X + sh.spot.X - sk.X, Y = rl.Y + sh.spot.Y - sk.Y, Z = rl.Z - sk.Z }
            pcall(function() sh.rig.o:K2_SetActorLocation(to, false, {}, true) end)
            sh.moved = string.format("%.0f m", math.sqrt((sh.spot.X - sk.X) ^ 2 + (sh.spot.Y - sk.Y) ^ 2) / 100)
        end
        pcall(function() sh.m:SetPosition(0, false) end)
        local cls = loadObject(sh.cls .. "." .. (sh.cls:match("[^/]+$") or "") .. "_C")
        local d, tr, gs = spawnDeferred(cls, { X = sh.spot.X, Y = sh.spot.Y, Z = -30000 }, S.yaw, 1)
        if d then
            pcall(function() gs:FinishSpawningActor(d, tr, 1) end)
            pcall(function() d:K2_AttachToComponent(sh.m, FName("SOC_Hull"), 2, 2, 1, true) end)
            sh.d = kept(d)
        else
            sh.failed = "its double didn't spawn (" .. tostring(sh.cls) .. ")"
        end
        sh.state = "wait"
        return
    end
    if sh.state == "wait" and t >= sh.at then
        pcall(function() sh.m:Play(false) end)
        sh.state, sh.t0 = "rise", now
        return
    end
    if sh.state == "rise" then
        local r0 = now - sh.t0
        if not sh.breach and r0 >= n(c.breach_s, 0.8) then   -- ((0.74.134) at its bow's breach point, where it breaks the sea)
            sh.breach = true; sh.bUp, sh.bOf = water(sh, c.breach, wc().enabled ~= false and shipSpot(sh, n(wc().breach_m, 115.8), 0) or nil)
            local h = hit(sh, "breach")
            if h ~= "" then slog(string.format("+%.1f s %s breaches%s", t, sh.name ~= "" and sh.name or sh.key, h)) end
        end
        if not sh.slam and r0 >= n(c.slam_s, 9) then
            sh.slam = true; sh.sUp, sh.sOf = water(sh, c.slam)
            keelSlam(sh)
            local h = hit(sh, "slam")
            if h ~= "" then slog(string.format("+%.1f s %s slams down%s", t, sh.name ~= "" and sh.name or sh.key, h)) end
        end
        shipWater(sh, r0, now)
        if r0 >= n(c.length_s, 15) then sh.state = "rest" end
    end
end
local function over(why)
    local nD = clearDoubles()
    if S.F and IFLEET and IFLEET.cur == S.F then S.F.nextAt = S.F.t end   -- (the real fleet up now, at once: F.burst)
    for _, k in ipairs({ "a", "b" }) do
        if S.cams[k] and valid(S.cams[k]) then pcall(function() S.cams[k]:K2_DestroyActor() end) end
    end
    if S.hand then pcall(function() survivalPC.PlayerCameraManager:StopAllCameraShakes(true) end) end
    local back = playerHold(false)
    local b, sl, failed, wu, wo = 0, 0, {}, 0, 0
    for _, sh in ipairs(S.ships) do
        b, sl = b + (sh.bUp or 0), sl + (sh.sUp or 0)
        wu, wo = wu + (sh.wUp or 0), wo + (sh.wOf or 0)
        if sh.failed then failed[#failed + 1] = (sh.name or sh.key) .. ": " .. sh.failed end
    end
    slog(string.format("over (%s): %d doubles taken off, the real fleet up; %d breach and %d slam waters, %d of %d climb / fall / keel / "
        .. "settle waters (%d held back at the live cap), %d strikes at breaches, %d shakes, %d roars, %d beats; %s%s",
        why, nD, b, sl, wu, wo, S.capped or 0, S.strikes or 0, S.shakes, S.sounds, S.beat, back, #failed > 0 and ("; NOT: " .. table.concat(failed, ", ")) or ""))
    if HUD and HUD.hold then pcall(HUD.hold, false, HOLD) end
    if CINE and CINE.hudShow then pcall(CINE.hudShow, HOLD, "the surfacing over") end
    S = nil
end
function IFSURF.state() return S and { phase = S.phase, ships = #S.ships, shot = S.shot, t = os.clock() - S.t0 } or nil end
TEST_TICKS[#TEST_TICKS + 1] = { name = "fleet surfacing", fn = function(now)
    if not S then return end
    if not D or (levelTorn and levelTorn()) then S = nil; return end
    if not (IFLEET and IFLEET.cur == S.F) then over("the fleet taken off"); return end
    local c = cs()
    local t = now - S.t0
    for i = #S.fx, 1, -1 do                               -- (each water stopped at its life: AC8's IGC waters never stop)
        local w = S.fx[i]
        if now >= w.off then
            if same(w.e) then pcall(function() w.e.o:Deactivate() end) end
            table.remove(S.fx, i)
        end
    end
    if S.phase == "rise" then
        for _, sh in ipairs(S.ships) do if not sh.failed then shipTick(sh, now) end end
        local shots = c.shots or {}
        while shots[S.shot + 1] and t >= n(shots[S.shot + 1].t, 0) do
            S.shot = S.shot + 1
            local ok, dur = camTo(S.shot, t)
            slog(string.format("shot %d at +%.1f s: %s, a %.1f s move%s", S.shot, t, tostring(shots[S.shot].ship), dur,
                ok and "" or " (the view NOT taken)"))
        end
        local beats = c.beats or {}
        while beats[S.beat + 1] and t >= n(beats[S.beat + 1].t, 0) do
            S.beat = S.beat + 1
            local ok, what = pcall(beat, beats[S.beat])
            slog(string.format("beat %d at +%.1f s: %s", S.beat, t, ok and tostring(what) or ("error " .. tostring(what))))
        end
        if S.cams.b and valid(S.cams.b) and liveObj(survivalPC) then  -- (the view kept on the cameras: a flash or the game may take it)
            local okV, vt = pcall(function() return survivalPC:GetViewTarget() end)
            if okV and vt and not onCams(vt) then
                S.reverts = (S.reverts or 0) + 1
                view(S.cams.b, math.max(0, (S.shotEnd or now) - now))
            end
        end
        if t >= S.overAt then
            local f = c.fade or {}
            local okF = THUNDER and THUNDER.camFade and pcall(THUNDER.camFade, 0, 1, n(f.out_s, 0.8), true)
            S.phase, S.at = "out", now + (okF and n(f.out_s, 0.8) or 0)
            local ups = 0
            for _, sh in ipairs(S.ships) do if sh.d and same(sh.d) then ups = ups + 1 end end
            slog(string.format("the rise over at +%.1f s: %d of %d doubles up, %d view reverts kept back; the fade", t, ups, #S.ships, S.reverts or 0))
        end
    elseif S.phase == "out" and now >= S.at then
        local f = c.fade or {}
        clearDoubles()
        if S.F then S.F.nextAt = S.F.t end
        S.phase, S.at = "hold", now + n(f.hold_s, 0.8)
    elseif S.phase == "hold" and now >= S.at then
        local f = c.fade or {}
        if THUNDER and THUNDER.camFade then pcall(THUNDER.camFade, 1, 0, n(f.in_s, 1.2), false) end
        over("the rise ended")
    end
end }
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["fleet surfacing"] = function() S = nil end
end
end
-- TEST ONLY END
