-- sv_ulysses.lua : ULYSSES, a special round back in July 1999 (the user, 2026-11-23: "Recreate the Ulysses Event from
-- Strangereal, I want it to be A Special Round where we go back in time for a few rounds"; docs/re/ULYSSES.md; CFG
-- CFG.specials.ulysses in sv_config_arc.lua). Her picks: pure meteor defence (no fighters), 2 rounds, a time-shift
-- transition, a film look, AC:I's meteors and Stardust sounds (her exception, docs/rules/sources_and_toolchain.md),
-- scenery meteors high overhead, at the day-night arc's dawn straight after THE FESTIVAL's night.
--   ULY.roundIs(round)      its rounds: the arc's first dawn rounds (F + 7 + night_rounds + dawn_offset), `rounds` of them
--   SPC.kinds.ulysses       its kind (no fighters; busy until every fragment is down or landed; over: home again)
--   ULY.tick(now)           every tick (sv_main.lua): fragments, the big one, the sky's meteors, the film look
-- A fragment: an actor of ours (the SOLG's way: sv_solg.lua) with AC:I's meteor mesh (SK_SV_Ulysses_<A|C|D>, painted), an
-- engine mover (ProjectileMovement: its fall needs no tick), a spin, a fire trail (AC8's), and a target box: one of the
-- SOLG's KEW / MAG targets (Mission 4's radar tower base, hidden, held on it; the two never come together), its box
-- "ULYSSES" over box.small / box.big while ULYSSES has them. At its floor (MinHealth: hard rule 63's way, read back) it's
-- shot down: blown up, paid; at its time it lands: blown up where it hits, the airfield's damage (AF.bomb) or the town's.
-- The host's (or solo): co-op's joiners see the boxes (the borrowed units, the host's), their own sky meteors and film
-- look; the rocks themselves are the host's only (to do: "ul" messages).
ULY = ULY or {}
local function cfg() return CFG.specials.ulysses end
local function ul(s) log("ulysses: " .. s) end
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function rnd(a, b) return a + math.random() * (b - a) end
local function span(t, d1, d2)
    if type(t) == "table" then return rnd(n(t[1], d1), n(t[2], d2 or d1)) end
    return n(t, d1)
end
local function host() return not (COOP and COOP.client and COOP.client()) end

---------------------------------------------------------------------------------------------------- its rounds
-- the arc's first dawn round: F + 7 (its night's first round) + night_rounds (sv_config_arc.lua CFG.sky.arc), + offset
function ULY.firstRound()
    local F = SKY and SKY.arcF and SKY.arcF()
    if F == nil then return nil end
    local arc = (CFG.sky and CFG.sky.arc) or {}
    return F + 7 + math.max(1, math.floor(n(arc.night_rounds, 3))) + math.floor(n(cfg().dawn_offset, 0))
end
function ULY.roundIs(round)
    local f, r = ULY.firstRound(), tonumber(round)
    return f ~= nil and r ~= nil and cfg().enabled ~= false and r >= f and r < f + math.max(1, math.floor(n(cfg().rounds, 2)))
end
function ULY.phaseOf(round)
    local f = ULY.firstRound()
    return f and (math.floor(n(round, f)) - f + 1) or 1
end

---------------------------------------------------------------------------------------------------- actors (the SOLG's way)
local function quatOf(rot)
    local p, y, r = math.rad(n(rot.Pitch, 0)) / 2, math.rad(n(rot.Yaw, 0)) / 2, math.rad(n(rot.Roll, 0)) / 2
    local SP, CP, SY, CY, SR, CR = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return { X = CR * SP * SY - SR * CP * CY, Y = -CR * SP * CY - SR * CP * SY, Z = CR * CP * SY - SR * SP * CY, W = CR * CP * CY + SR * SP * SY }
end
local function newActor(at, rot)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local cls = StaticFindObject("/Script/Engine.Actor")
    if not (valid(gs) and valid(cls) and liveObj(survivalPC)) then return nil end
    local t = { Rotation = quatOf(rot or {}), Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, a = pcall(function()
        local x = gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1)
        return gs:FinishSpawningActor(x, t, 1)
    end)
    return ok and valid(a) and a or nil
end
local function addComp(a, path)
    local cls = StaticFindObject(path)
    if not valid(cls) then return nil end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, c = pcall(function() return a:AddComponentByClass(cls, false, t, false) end)
    return ok and valid(c) and c or nil
end
local MESH = {}
local function mesh(key)
    local path = cfg().mesh_path .. tostring(key)
    if MESH[path] ~= nil and (MESH[path] == false or valid(MESH[path])) then return MESH[path] or nil end
    local o = loadObject(path .. "." .. path:match("[^/]+$"))
    MESH[path] = (o ~= nil and valid(o)) and o or false
    if not MESH[path] then ul("mesh " .. path .. " didn't load (is SurvivalMode_Ulysses_P installed?)") end
    return MESH[path] or nil
end
-- the rock's paint: one dynamic instance of the x40a's gear material with the rock's textures (as sv_solg.lua paint)
local PAINT = {}
local function paintMid()
    if PAINT.mid ~= nil then return PAINT.mid or nil end
    local P = cfg().paint or {}
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local parent = P.parent and loadObject(P.parent .. "." .. P.parent:match("[^/]+$"))
    if not (valid(kml) and parent and valid(parent)) then PAINT.mid = false; ul("paint: its parent didn't load: the rocks unpainted"); return nil end
    local ok, mid = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, parent, FName("None"), 0) end)
    if not (ok and valid(mid)) then PAINT.mid = false; return nil end
    local nT = 0
    for slot, path in pairs(P.tex or {}) do
        local t = loadObject(path .. "." .. path:match("[^/]+$"))
        if t and valid(t) and pcall(function() mid:SetTextureParameterValue(FName(slot), t) end) then nT = nT + 1 end
    end
    for k, v in pairs(P.scalars or {}) do pcall(function() mid:SetScalarParameterValue(FName(k), v) end) end
    PAINT.mid = mid
    ul(string.format("paint: the rock's instance made, %d textures in", nT))
    return mid
end
-- a rock: actor, AC:I's mesh at `scale` (skeletal, painted), a spin, a fire trail, an engine mover at `vel` (cm/s)
local function rock(key, at, vel, scale, spin)
    local m = mesh(key)
    local a = newActor(at, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 })
    if not a then return nil end
    local c = addComp(a, "/Script/Engine.SkeletalMeshComponent")
    if not c then pcall(function() a:K2_DestroyActor() end); return nil end
    if m and not pcall(function() c:SetSkeletalMeshAsset(m) end) then pcall(function() c:SetSkeletalMesh(m, true) end) end
    -- (a bare actor has no root: its spawn place went with the first component, at the world's origin (the SOLG's run of
    -- 2026-11-22 17:58, and this one's autotest of 2026-11-23: rocks 1.5 km under the sea). Put where it's wanted once its
    -- mesh is its root, the mesh itself too)
    local rot = { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 }
    pcall(function() a:K2_SetActorLocationAndRotation({ X = at.X, Y = at.Y, Z = at.Z }, rot, false, {}, true) end)
    pcall(function() c:K2_SetWorldLocation({ X = at.X, Y = at.Y, Z = at.Z }, false, {}, true) end)
    local mid = paintMid()
    if mid then
        local slots = 1
        pcall(function() slots = c:GetNumMaterials() end)
        for i = 0, math.max(0, slots - 1) do pcall(function() c:SetMaterial(i, mid) end) end
    end
    pcall(function() c:SetCollisionEnabled(0) end)
    pcall(function() c:SetWorldScale3D({ X = scale, Y = scale, Z = scale }) end)
    pcall(function() c:SetCastShadow(true) end)
    local rm = addComp(a, "/Script/Engine.RotatingMovementComponent")
    if rm then pcall(function() rm.RotationRate = { Pitch = spin * 0.6, Yaw = spin, Roll = spin * 0.3 } end) end
    local pm = addComp(a, "/Script/Engine.ProjectileMovementComponent")
    if pm then
        pcall(function() pm:SetUpdatedComponent(a.RootComponent) end)
        pcall(function() pm.ProjectileGravityScale = 0 end)
        pcall(function() pm.bRotationFollowsVelocity = false end)
        pcall(function() pm.MaxSpeed = 0 end)
        pcall(function() pm.Velocity = { X = vel.X, Y = vel.Y, Z = vel.Z } end)
    end
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = SPC and SPC.V and SPC.V.asset and SPC.V.asset(cfg().trail)
    if valid(lib) and sys then
        local ts = n(cfg().trail_scale, 6) * math.max(0.5, scale)
        pcall(function() lib:SpawnSystemAttached(sys, c, FName("None"), { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 },
            { X = ts, Y = ts, Z = ts }, 0, true, 0, true) end)
    end
    return { a = a, c = c, pm = pm }
end
local function rockAt(r)
    if not (r and liveObj(r.a)) then return nil end
    local ok, L = pcall(function() return r.a:K2_GetActorLocation() end)
    return ok and L and { X = L.X, Y = L.Y, Z = L.Z } or nil
end
local function rockOff(r)
    if r and liveObj(r.a) then pcall(function() r.a:K2_DestroyActor() end) end
end
local function boom(at, scale)
    if at and fxAt then pcall(fxAt, cfg().fx, at, scale, 8) end
    local s = cfg().sounds or {}
    if s.boom and SND and SND.play then pcall(SND.play, s.boom, at) end
end

---------------------------------------------------------------------------------------------------- the borrowed targets
local FLAGS_ON = { bShowHUDBox = true, bIsNotLockonTarget = false, bIsNotFCSTargets = false, bIsInvincible = false }
local FLAGS_OFF = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }
local function flags(o, f) for k, v in pairs(f) do pcall(function() o[k] = v end) end end
local function hideOwn(o)
    for _, cls in ipairs({ "/Script/Engine.StaticMeshComponent", "/Script/Engine.SkeletalMeshComponent" }) do
        local c = StaticFindObject(cls)
        local ok, list = pcall(function() return o:K2_GetComponentsByClass(c) end)
        if ok and list then pcall(function() list:ForEach(function(_, e) pcall(function() e:get():SetVisibility(false, true) end) end) end) end
    end
end
local CAPTURE = nil
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    if CAPTURE and #CAPTURE < 120 then CAPTURE[#CAPTURE + 1] = o end
end)
local U = nil                                             -- this round's state (host / solo)
local PARK = { X = 0, Y = 0, Z = -5000000 }
-- a borrowed unit up: its objects hidden, parked, off; -> the list
local function poolUp(unit)
    if type(SV_Spawn) ~= "function" then return {} end
    CAPTURE = {}
    local r = SV_Spawn(unit, AIRFIELD.X, AIRFIELD.Y, 3000000, 0)
    local got = CAPTURE
    CAPTURE = nil
    local out = {}
    for _, o in ipairs(got) do
        if valid(o) then
            hideOwn(o)
            flags(o, FLAGS_OFF)
            pcall(function() o:K2_SetActorLocation(PARK, false, {}, true) end)
            out[#out + 1] = { o = o, a = addrOf(o), name = nameOf(o) }
        end
    end
    ul(string.format("targets: %s up, %d objects borrowed (%s)", unit, #out, r and r > 0 and (r .. " up") or tostring(r)))
    return out
end
local function boxTexts(on)
    if type(SV_SetText) ~= "function" then return end
    local c = cfg().box or {}
    if on then
        SV_SetText("SV_SOLG_Name", c.name or "ULYSSES")
        SV_SetText("SV_SOLG_Sub_KEW", c.small or "FRAGMENT")
        SV_SetText("SV_SOLG_Sub_MAG", c.big or "ULYSSES CORE")
    elseif SOLG and SOLG.C then                           -- (the SOLG's own back)
        SV_SetText("SV_SOLG_Name", SOLG.C.name or "SOLG")
        for _, k in ipairs({ "KEW", "MAG" }) do SV_SetText("SV_SOLG_Sub_" .. k, (SOLG.C.names or {})[k] or k) end
    end
end
-- a target from the pool onto rock r's mesh, its health hp: -> the entry
local function arm(pool, r, hp)
    for _, e in ipairs(pool) do
        if not e.used and liveObj(e.o) and addrOf(e.o) == e.a then
            e.used = true
            local att = pcall(function() e.o:K2_AttachToComponent(r.c, FName("None"), 2, 2, 1, false) end)
            local okH, hx, hy, hz = pcall(function() local h = e.o.HitCenterOffset; return h.X, h.Y, h.Z end)
            if att and okH and tonumber(hx) then
                pcall(function() e.o:K2_SetActorRelativeLocation({ X = -hx, Y = -hy, Z = -hz }, false, {}, true) end)
            end
            pcall(function() e.o.MaxHealth = hp; e.o.HealthInternal = math.floor(hp * 10 + 0.5); e.o.MinHealth = 1 end)
            hideOwn(e.o)
            flags(e.o, FLAGS_ON)
            e.attached = att
            return e
        end
    end
    return nil
end
local function disarm(e)
    if not e then return end
    flags(e.o, FLAGS_OFF)
    pcall(function() e.o:K2_DetachFromActor(1, 1, 1) end)
    pcall(function() e.o:K2_SetActorLocation(PARK, false, {}, true) end)
end
local function atFloor(e)
    if not (e and liveObj(e.o) and addrOf(e.o) == e.a) then return false, "gone" end
    local ok, h = pcall(function() return e.o.HealthInternal end)
    if ok and tonumber(h) then
        if h ~= e.lastH then hideOwn(e.o); e.lastH = h end   -- (the base's damaged mesh, hidden again)
        return h <= 15, nil
    end
    return false, nil
end

---------------------------------------------------------------------------------------------------- the film look
local FILM = {}
local function filmSet(w)
    if not (FILM.v and liveObj(FILM.v)) then return end
    pcall(function() FILM.v.BlendWeight = w end)
end
local function filmOn()
    local f = cfg().film or {}
    if f.enabled == false then return "off" end
    if FILM.v and liveObj(FILM.v) then return "up" end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local cls = StaticFindObject("/Script/Engine.PostProcessVolume")
    if not (valid(gs) and valid(cls) and liveObj(survivalPC)) then return "no PostProcessVolume class" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, v = pcall(function()
        local x = gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1)
        return gs:FinishSpawningActor(x, t, 1)
    end)
    if not (ok and valid(v)) then return "the volume didn't spawn" end
    pcall(function() v.bUnbound = true end)
    pcall(function() v.Priority = 1000 end)
    pcall(function() v.BlendWeight = 0 end)
    local tint = f.tint or { 1, 0.9, 0.72 }
    local sets = {
        function(s) s.bOverride_ColorSaturation = true; s.ColorSaturation = { X = f.saturation, Y = f.saturation, Z = f.saturation, W = 1 } end,
        function(s) s.bOverride_SceneColorTint = true; s.SceneColorTint = { R = tint[1], G = tint[2], B = tint[3], A = 1 } end,
        function(s) s.bOverride_FilmGrainIntensity = true; s.FilmGrainIntensity = f.grain end,
        function(s) s.bOverride_VignetteIntensity = true; s.VignetteIntensity = f.vignette end,
    }
    local nOk = 0
    for _, fn in ipairs(sets) do if pcall(function() fn(v.Settings) end) then nOk = nOk + 1 end end
    pcall(function() v.bEnabled = true end)
    local okR, back = pcall(function() return v.Settings.FilmGrainIntensity end)
    -- ((2026-11-23, the autotest: 4 of 4 written, nothing seen) AC8's own grading comes with the view's camera, after any
    -- volume: the same settings on the camera components of your plane (their blend weight 1), put back at the end
    FILM.cams = {}
    local pawn = liveObj(survivalPC) and survivalPC.Pawn
    local cc = StaticFindObject("/Script/Engine.CameraComponent")
    local okC, list = pcall(function() return pawn:K2_GetComponentsByClass(cc) end)
    if okC and list then
        pcall(function() list:ForEach(function(_, e)
            local cam = e:get()
            local saved = {}
            for _, k in ipairs({ "bOverride_ColorSaturation", "bOverride_SceneColorTint", "bOverride_FilmGrainIntensity", "bOverride_VignetteIntensity",
                                 "ColorSaturation", "SceneColorTint", "FilmGrainIntensity", "VignetteIntensity" }) do
                pcall(function() local x = cam.PostProcessSettings[k]; saved[k] = type(x) == "userdata" and nil or x end)
            end
            local w = 0
            for _, fn in ipairs(sets) do if pcall(function() fn(cam.PostProcessSettings) end) then w = w + 1 end end
            pcall(function() cam.PostProcessBlendWeight = 1 end)
            FILM.cams[#FILM.cams + 1] = { cam = cam, saved = saved, w = w }
        end) end)
    end
    local camW = 0
    for _, x in ipairs(FILM.cams) do camW = camW + x.w end
    FILM.v, FILM.from, FILM.to, FILM.at = v, 0, 1, os.clock()
    return string.format("on (%d of %d settings written, grain read back %s; on %d camera(s) of your plane, %d settings)", nOk, #sets,
        okR and tostring(back) or "?", #FILM.cams, camW)
end
local function filmOff(now)
    if FILM.v and liveObj(FILM.v) then FILM.from, FILM.to, FILM.at = FILM.cur or 1, 0, now or os.clock() end
end
local function filmTick(now)
    if not (FILM.v and liveObj(FILM.v)) then return end
    local fs = math.max(0.1, n((cfg().film or {}).fade_s, 2))
    local u = math.min(1, (now - (FILM.at or now)) / fs)
    FILM.cur = FILM.from + (FILM.to - FILM.from) * u
    filmSet(FILM.cur)
    for _, x in ipairs(FILM.cams or {}) do                 -- (the camera's: its blend scaled the same way)
        if valid(x.cam) then pcall(function() x.cam.PostProcessSettings.FilmGrainIntensity = n((cfg().film or {}).grain, 0.45) * FILM.cur end) end
    end
    if FILM.to == 0 and u >= 1 then
        for _, x in ipairs(FILM.cams or {}) do
            if valid(x.cam) then
                for k, val in pairs(x.saved) do pcall(function() x.cam.PostProcessSettings[k] = val end) end
                for _, k in ipairs({ "bOverride_ColorSaturation", "bOverride_SceneColorTint", "bOverride_FilmGrainIntensity", "bOverride_VignetteIntensity" }) do
                    if x.saved[k] == nil then pcall(function() x.cam.PostProcessSettings[k] = false end) end
                end
            end
        end
        FILM.cams = {}
        pcall(function() FILM.v:K2_DestroyActor() end); FILM.v = nil
    end
end

---------------------------------------------------------------------------------------------------- the time shift
local function fade(from, to, dur, hold)
    local pcm = liveObj(survivalPC) and survivalPC.PlayerCameraManager
    if valid(pcm) then pcall(function() pcm:StartCameraFade(from, to, dur, { R = 1, G = 1, B = 1, A = 1 }, false, hold) end) end
end
local function say(list)
    if not list then return end
    for i, l in ipairs(list) do
        local who, txt = tostring(l):match("^([^|]+)|(.+)$")
        if SUB and SUB.say then pcall(SUB.say, who or "", txt or l, 4.5) end   -- (queued one after another)
    end
end

---------------------------------------------------------------------------------------------------- the round
local function players() return (type(playerCount) == "function" and playerCount()) or 1 end
local function fragmentsFor(phase)
    local f = cfg().fragments
    local base = n(phase == 1 and f.round1 or f.round2, 16)
    local p = players()
    local x = p <= 1 and n(f.solo_x, 1) or (1 + n(f.per_player, 0) * (p - 1))
    return math.max(1, math.min(n(f.max_n, 40), math.floor(base * x + 0.5)))
end
local function aimPoint()
    local f = cfg().fragments
    local towns = cfg().towns or {}
    local base
    if #towns == 0 or math.random() < n((f.aim or {}).airfield, 0.6) then base, U.lastAim = { X = AIRFIELD.X, Y = AIRFIELD.Y }, "airfield"
    else base, U.lastAim = towns[math.random(1, #towns)], "town" end
    local sp = n(f.spread_m, 2500) * 100
    local ang = math.random() * 2 * math.pi
    local r = math.sqrt(math.random()) * sp
    return { X = base.X + math.cos(ang) * r, Y = base.Y + math.sin(ang) * r, Z = 0 }, U.lastAim
end
-- one falling body from `from_km` out, `alt_m` up, onto P at `speed_kmh`: -> the entry
local function launch(spec, P, what, big)
    local bearing = math.random() * 2 * math.pi
    local dkm, alt = span(spec.from_km, 30), span(spec.alt_m, 10000) * 100
    local start = { X = P.X + math.cos(bearing) * dkm * 100000, Y = P.Y + math.sin(bearing) * dkm * 100000, Z = alt }
    local dx, dy, dz = P.X - start.X, P.Y - start.Y, P.Z - start.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local v = span(spec.speed_kmh, 1200) / 3.6 * 100                 -- (cm/s)
    local T = d / v
    local key = type(spec.meshes) == "table" and spec.meshes[math.random(1, #spec.meshes)] or spec.mesh or "C"
    local r = rock(key, start, { X = dx / T, Y = dy / T, Z = dz / T }, span(spec.scale, 1), span(spec.spin_dps, 20))
    if not r then return nil end
    local f = { r = r, P = P, what = what, big = big, hitAt = os.clock() + T, born = os.clock(), key = key }
    local hp = n(spec.health, 300) * (players() <= 1 and n(spec.solo_x, 1) or 1)
    f.e = arm(big and U.poolBig or U.pool, r, hp)
    local s = cfg().sounds or {}
    if SND and SND.play and (big and s.fall_big or s.fall) then
        f.snd = SND.play(big and s.fall_big or s.fall, function() return rockAt(f.r) end)
    end
    return f
end
local function land(f, now)
    local at = rockAt(f.r) or f.P
    boom(f.P, n((cfg().fx_scale or {})[f.big and "big_land" or "land"], 10))
    if f.snd and SND and SND.stop then pcall(SND.stop, f.snd) end
    disarm(f.e)
    rockOff(f.r)
    local dmg = f.big and n(cfg().big.airfield_damage, 120) or n(cfg().fragments.airfield_damage, 8)
    local d = math.sqrt((f.P.X - AIRFIELD.X) ^ 2 + (f.P.Y - AIRFIELD.Y) ^ 2)
    if f.what == "airfield" or f.big or d < 400000 then
        if AF and type(AF.bomb) == "number" then AF.bomb = AF.bomb + dmg end
        U.landedAirfield = U.landedAirfield + 1
    else
        U.landedTown = U.landedTown + 1
        if (U.townSaid or 0) + 20 < now and hudCallout then U.townSaid = now; hudCallout(cfg().text.town_hit, nil) end
    end
    if f.big and hudCallout then hudCallout(cfg().text.big_hit, nil) end
    ul(string.format("%s landed on the %s (%.1f, %.1f km)%s", f.big and "the core" or "a fragment", f.what, f.P.X / 100000,
        f.P.Y / 100000, (f.what == "airfield" or f.big) and string.format(": the airfield -%d", dmg) or ""))
    return at
end
local function shot(f, now)
    local at = rockAt(f.r)
    boom(at, n((cfg().fx_scale or {})[f.big and "big_shot" or "shot"], 4))
    if f.snd and SND and SND.stop then pcall(SND.stop, f.snd) end
    disarm(f.e)
    rockOff(f.r)
    local pay = f.big and n(cfg().big.pay, 6000) or n(cfg().fragments.pay, 300)
    pay = specialPay and specialPay(pay) or pay
    if pay > 0 and addCredits then addCredits(pay, f.big and "the Ulysses core down" or "a Ulysses fragment down") end
    U.shot = U.shot + 1
    if f.big and hudCallout then hudCallout(cfg().text.big_down, nil) end
    if LB and LB.stat then pcall(LB.stat, f.big and "ulysses_core" or "ulysses_fragment", 1) end
    ul(string.format("%s shot down %.0f s before it would have hit (%.1f km up), paid %d", f.big and "the core" or "a fragment",
        f.hitAt - now, at and at.Z / 100000 or -1, pay))
end

function ULY.spawn(now)
    local s = D and D.special
    if not s then return false end
    if not mesh("C") then ul("its meshes aren't in this build: a normal round"); return false end
    pcall(paintMid)
    local phase = ULY.forcedPhase or ULY.phaseOf(D.round)
    U = { phase = phase, list = {}, todo = fragmentsFor(phase), sent = 0, shot = 0, landedAirfield = 0, landedTown = 0,
          nextAt = now + n(cfg().fragments.first_s, 8), startAt = now, bigAt = nil, bigSent = false }
    if host() then
        boxTexts(true)
        U.pool = poolUp(cfg().target_units.small)
        U.poolBig = (phase >= 2 and cfg().big.enabled ~= false) and poolUp(cfg().target_units.big) or {}
        if phase >= 2 and cfg().big.enabled ~= false then U.bigAt = now + n(cfg().big.at_s, 45) end
    end
    s.state, s.at = "shower", now
    local sh = cfg().shift or {}
    if phase == 1 then
        fade(1, 0, n(sh.fade_s, 1.2) * 2, false)              -- (in from white: the time shift)
        if hudCallout then hudCallout(sh.card or "JULY 1999", sh.card_sub) end
    end
    ul(string.format("round %d: phase %d of %d, %d fragments%s; the film look %s", D.round, phase, n(cfg().rounds, 2), U.todo,
        U.bigAt and ", the core at +" .. n(cfg().big.at_s, 45) .. " s" or "", filmOn()))
    say((cfg().text.say or {}).start)
    local snd = (cfg().sounds or {}).encounter
    if snd and SND and SND.play then pcall(SND.play, snd, nil) end
    return true
end

local SKYM = { list = {}, nextAt = 0 }
local function skyTick(now)
    local c = cfg().sky or {}
    for i = #SKYM.list, 1, -1 do
        local m = SKYM.list[i]
        if now >= m.dieAt or not liveObj(m.r.a) then rockOff(m.r); table.remove(SKYM.list, i) end
    end
    if c.enabled == false or now < SKYM.nextAt then return end
    SKYM.nextAt = now + span(c.every_s, 2.5)
    local me = playerLocation and playerLocation()
    local cx, cy = me and me.X or AIRFIELD.X, me and me.Y or AIRFIELD.Y
    local b = math.random() * 2 * math.pi
    local d = span(c.from_km, 40) * 100000
    local alt = span(c.alt_m, 20000) * 100
    local start = { X = cx + math.cos(b) * d, Y = cy + math.sin(b) * d, Z = alt }
    local across = b + math.pi + rnd(-0.6, 0.6)                         -- (across the sky, past you, dipping)
    local v = span(c.speed_kmh, 12000) / 3.6 * 100
    local vel = { X = math.cos(across) * v, Y = math.sin(across) * v, Z = -v * rnd(0.05, 0.2) }
    local key = type(c.meshes) == "table" and c.meshes[math.random(1, #c.meshes)] or "D"
    local r = rock(key, start, vel, span(c.scale, 3), rnd(20, 90))
    if r then SKYM.list[#SKYM.list + 1] = { r = r, dieAt = now + n(c.life_s, 18) } end
end
local function skyOff()
    for _, m in ipairs(SKYM.list) do rockOff(m.r) end
    SKYM.list = {}
end

function ULY.roundTick(now, s)
    if not U then return end
    -- the shower: a fragment every every_s, at most at_once falling
    if host() then
        local f = cfg().fragments
        local falling = 0
        for _, x in ipairs(U.list) do if not x.done and not x.big then falling = falling + 1 end end
        if U.sent < U.todo and now >= U.nextAt and falling < n(f.at_once, 6) then
            U.nextAt = now + span(f.every_s, 6)
            local P, what = aimPoint()
            local x = launch(f, P, what, false)
            if x then U.list[#U.list + 1] = x; U.sent = U.sent + 1 else U.todo = U.todo - 1 end
        end
        if U.bigAt and not U.bigSent and now >= U.bigAt then
            U.bigSent = true
            local b = cfg().big
            local x = launch({ from_km = b.from_km, alt_m = b.alt_m, speed_kmh = b.speed_kmh, mesh = b.mesh, scale = b.scale,
                               spin_dps = b.spin_dps, health = b.health, solo_x = b.solo_x },
                             { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = 0 }, "airfield", true)
            if x then U.list[#U.list + 1] = x end
            if hudCallout then hudCallout(cfg().text.big, cfg().text.big_sub) end
            say((cfg().text.say or {}).big)
            ul(string.format("the core inbound: %s, lands in %.0f s", x and "up" or "NOT up", x and (x.hitAt - now) or -1))
        end
        for _, x in ipairs(U.list) do
            if not x.done then
                local down, why = atFloor(x.e)
                if down then x.done = true; shot(x, now)
                elseif now >= x.hitAt then x.done = true; land(x, now)
                elseif why == "gone" and x.e then x.e = nil end
            end
        end
    end
end
function ULY.busy(s)
    if not U then return false end
    if not host() then return false end
    if U.sent < U.todo or (U.bigAt and not U.bigSent) then return true end
    for _, x in ipairs(U.list) do if not x.done then return true end end
    return false
end
function ULY.roundOver(now, s)
    if not U then return end
    for _, x in ipairs(U.list) do if not x.done then x.done = true; disarm(x.e); rockOff(x.r) end end
    ul(string.format("round %d over: %d of %d fragments shot down, %d landed on the airfield, %d on the town%s", D.round, U.shot,
        U.sent + (U.bigSent and 1 or 0), U.landedAirfield, U.landedTown, U.bigSent and "" or ""))
    if host() then boxTexts(false) end
    local last = U.phase >= math.max(1, math.floor(n(cfg().rounds, 2)))
    if last then
        filmOff(now)
        skyOff()
        local sh = cfg().shift or {}
        fade(1, 0, n(sh.fade_s, 1.2) * 2, false)
        if hudCallout then hudCallout(sh.home or "PRESENT DAY", sh.home_sub) end
        say((cfg().text.say or {}).home)
    end
    U = nil
end
function ULY.row(s, t)
    if not U then return nil end
    local left = (U.todo - U.sent)
    for _, x in ipairs(U.list) do if not x.done then left = left + 1 end end
    return string.format("ULYSSES  %d FRAGMENTS LEFT  %d DOWN", left + ((U.bigAt and not U.bigSent) and 1 or 0), U.shot)
end
-- every tick (sv_main.lua): the film look's blend, the sky's meteors while in 1999 (each game its own)
function ULY.tick(now)
    filmTick(now)
    local s = D and D.special
    local on = s and s.kind == "ulysses" and (D.state == "fighting" or D.state == "spawning")
    if on then skyTick(now)
    elseif #SKYM.list > 0 and not (U and U.phase) then
        local nextIs = D and ULY.roundIs(D.round + 1)
        if not nextIs then skyOff() end
    end
    if not D and FILM.v then filmOff(now) end
end

-- the special's kind (sv_anomalies_valka.lua SPC.kinds): no fighters of its own, busy while fragments fall
if SPC and SPC.kinds then
    SPC.kinds.ulysses = { sub = function() return cfg().text.sub end, alone = true, aircraft = 0,
                          ready = function(round, forced) return forced or ULY.roundIs(round) end,
                          spawn = function(now) return ULY.spawn(now) end,
                          tick = function(now, s) return ULY.roundTick(now, s) end,
                          busy = function(s) return ULY.busy(s) end, over = function(now, s) return ULY.roundOver(now, s) end,
                          row = function(s, t) return ULY.row(s, t) end }
end
function ULY.debug() return U, SKYM, FILM end                  -- (the tests')

-- TEST ONLY BEGIN (ULYSSES' test key: test builds only)
-- Ctrl+Q: the next round is ULYSSES (phase 1; again: phase 2, then off); its log says which
testKey("Q", "sv_ulysses.lua's ULYSSES round", function()
    if not D then log("test: Ctrl+Q: no run"); return end
    ULY.forcedPhase = ((ULY.forcedPhase or 0) % 3) + 1
    if ULY.forcedPhase == 3 then ULY.forcedPhase, D.forceSpecial = nil, nil; log("test: Ctrl+Q: ULYSSES off"); return end
    D.forceSpecial = "ulysses"
    local f = ULY.firstRound()
    log(string.format("test: Ctrl+Q: the next round is ULYSSES, phase %d (its rounds from the arc: %s)", ULY.forcedPhase, tostring(f)))
end)
-- TEST ONLY END
