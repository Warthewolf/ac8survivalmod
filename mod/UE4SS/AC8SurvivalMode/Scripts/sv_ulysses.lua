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
-- ((2026-11-23) co-op: "ul|<kind>|..." to every joiner (sv_coop.lua COOP.ulysses), each joiner draws its own copies:
--   r|phase   its round (the fade and card at phase 1, the film look)   e|last   its end (home again when last)
--   f|id|key|x|y|z|vx|vy|vz|scale100|spin|big   a fragment launched (metres; cm/s)   s|id   shot down   l|id|land   landed)
local function tell(...) if COOP and COOP.ulysses and COOP.host and COOP.host() then pcall(COOP.ulysses, ...) end end

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
---------------------------------------------------------------------------------------------------- its sounds
-- ((2026-11-24, the user: "get the wwise sounds working for the meteorites") AC:I's Stardust set as Survival's own Wwise
-- events (tools/wwise/spec.py: SurvivalMode_Wwise_P, on AC8's sfx bus: the game's effects volume, its 3D, its mix) when
-- that container is in (sounds.wwise), else Survival's XAudio2 player (sv_sound.lua) as before, sound by sound. One on
-- something moving (a fragment's whistle) is posted ON its actor (LiveSoundBlueprintLibrary.PostEventAtActorByAkEvent:
-- Wwise's component on its root follows it) and stopped with it (AkGameplayStatics.StopActor); one at a place (an
-- impact) by PostEventAtLocation (the way Survival's heard sounds go: sv_escort_laser.lua); the encounter and the rumble 2D
local WW = { ev = {}, said = {}, on = 0 }
local AKS, LSB = nil, nil
local function wwEv(kind)
    local w = (cfg().sounds or {}).wwise
    if not (type(w) == "table" and w.enabled ~= false and type(w[kind]) == "string") then return nil end
    local name = w[kind]
    local e = WW.ev[name]
    if e == false then return nil end
    if e and liveObj(e) then return e, name end
    e = SPC and SPC.V and SPC.V.asset and SPC.V.asset((w.path or "/Game/Mods/SurvivalMode/Wwise/Events/Default_Work_Unit/") .. name) or nil
    WW.ev[name] = e or false
    ul(string.format("sound: Wwise's %s %s", name, e and "loaded" or "NOT loaded (no SurvivalMode_Wwise_P?): Survival's own player plays it"))
    return e, name
end
local function akStat()
    if not (AKS and valid(AKS)) then AKS = StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics") end
    return AKS and valid(AKS) and AKS or nil
end
-- a one-off at `at` (nil: where you are; a 2D one plays the same anywhere) -> true when Wwise took it
local function wwAt(kind, at)
    local ev, name = wwEv(kind)
    local ak = ev and akStat()
    if not ak then return false end
    at = at or (playerLocation and playerLocation()) or { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = 0 }
    local L, rot = { X = at.X, Y = at.Y, Z = at.Z or 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }
    local ok, id = pcall(function() return ak:PostEventAtLocation(ev, L, rot, survivalPC) end)
    if not ok then ok, id = pcall(function() return ak:PostEventAtLocation(ev, L, rot, "", survivalPC) end) end
    id = ok and tonumber(id) or 0
    if not WW.said[name] then
        WW.said[name] = true
        ul(string.format("sound: %s posted by Wwise at a place: playing id %s%s", name, tostring(id), ok and "" or " (the call failed)"))
    end
    return id > 0
end
-- Wwise's components on actor a (its root, its root's children)
local function wwComps(a)
    local cls, k = StaticFindObject("/Script/AkAudio.AkComponent"), 0
    if not (cls and valid(cls)) then return 0 end
    pcall(function()
        local root = a.RootComponent
        if root ~= nil and valid(root) and root:IsA(cls) then k = k + 1 end
        root.AttachChildren:ForEach(function(_, e) local x = e:get(); if valid(x) and x:IsA(cls) then k = k + 1 end end)
    end)
    return k
end
-- a sound ON actor a, following it (a whistle, the rumble) -> true when posted (stopped: wwOff(a))
local function wwOn(kind, a)
    local ev, name = wwEv(kind)
    if not (ev and a and liveObj(a)) then return false end
    if not (LSB and valid(LSB)) then LSB = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary") end
    if not (LSB and valid(LSB)) then return false end
    local ok, err = pcall(function() return LSB:PostEventAtActorByAkEvent(ev, a) end)
    WW.on = WW.on + 1
    if WW.on <= 3 or not ok then
        ul(string.format("sound: %s posted by Wwise on an actor: %s, %d Wwise component(s) on it", name,
            ok and "ok" or ("FAILED: " .. tostring(err)), ok and wwComps(a) or 0))
    end
    return ok
end
local function wwOff(a)
    local ak = akStat()
    if ak and a and liveObj(a) then pcall(function() ak:StopActor(a) end) end
end
-- ((2026-11-24) the game paused / running (sv_sound.lua SND.onPause): AC8's own pause (AKE_System_SFX_Pause_On, its main
-- SE bank) pauses some children of the sfx bus, never the sfx bus ours play on: each of ours paused / resumed on every
-- game object (UAkAudioEvent.ExecuteAction: Pause 1 / Resume 2, no actor = all, a 100 ms fade)
function ULY.wwPause(paused)
    local n, bad = 0, nil
    for name, e in pairs(WW.ev) do
        if e and liveObj(e) then
            local ok, r = pcall(function() return e:ExecuteAction(paused and 1 or 2, nil, 0, 100, 4) end)
            if ok then n = n + 1 else bad = tostring(r) end
        end
    end
    if n > 0 or bad then
        WW.paused = (WW.paused or 0) + 1
        if WW.paused <= 4 or bad then
            ul(string.format("sound: Wwise's %d event(s) %s%s", n, paused and "paused" or "resumed", bad and (" (an error: " .. bad .. ")") or ""))
        end
    end
end
if SND then SND.onPause = SND.onPause or {}; SND.onPause.ulysses = function(p) ULY.wwPause(p) end end
-- ((2026-11-24, the user: "make it so that the meteorites have the tonitrus spear impact sfx too") AC8's own Tonitrus
-- Spear impacts (its event assets: sounds.spear.ground / .sea), posted where a fragment lands, beside its own explosion
local function spearAt(kind, at)
    local sp = (cfg().sounds or {}).spear
    local path = type(sp) == "table" and sp.enabled ~= false and sp[kind] or nil
    if type(path) ~= "string" or not at then return false end
    local e = WW.ev[path]
    if e == false then return false end
    if not (e and liveObj(e)) then
        e = SPC and SPC.V and SPC.V.asset and SPC.V.asset(path) or nil
        WW.ev[path] = e or false
        ul(string.format("sound: AC8's %s %s", path:match("[^/]+$"), e and "loaded" or "NOT loaded"))
        if not e then return false end
    end
    local ak = akStat()
    if not ak then return false end
    local L, rot = { X = at.X, Y = at.Y, Z = at.Z or 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }
    local ok, id = pcall(function() return ak:PostEventAtLocation(e, L, rot, survivalPC) end)
    if not ok then ok, id = pcall(function() return ak:PostEventAtLocation(e, L, rot, "", survivalPC) end) end
    id = ok and tonumber(id) or 0
    if not WW.said[path] then
        WW.said[path] = true
        ul(string.format("sound: AC8's %s posted: playing id %s", path:match("[^/]+$"), tostring(id)))
    end
    return id > 0
end
-- an impact's sound at `at`
local function bang(at)
    local s = cfg().sounds or {}
    if not wwAt("boom", at) and s.boom and SND and SND.play then pcall(SND.play, s.boom, at) end
end
-- a falling rock's whistle (x: the host's fragment or a joiner's rock, a: its actor, where: its place for XAudio2)
local function fallOn(x, a, big, where)
    -- ((2026-11-24, the user: "The meteors were using the missile sound effect": AC:I's OBJ_FALL_STARTDUST_SMALL is the
    -- same stream as its ICBM burner) sounds.whistle false: no fall loop on a fragment (the core keeps its own)
    if not big and (cfg().sounds or {}).whistle == false then return end
    if wwOn(big and "fall_big" or "fall", a) then x.ww = a; return end
    local l = (cfg().sounds or {})[big and "fall_big" or "fall"]
    if l and SND and SND.play then
        local ok, h = pcall(SND.play, l, where)
        x.snd = ok and h or nil
    end
end
local function fallOff(x)
    if x.snd and SND and SND.stop then pcall(SND.stop, x.snd) end
    x.snd = nil
    if x.ww then wwOff(x.ww); x.ww = nil end
end

local MESH = {}
local function mesh(key)
    local path = cfg().mesh_path .. tostring(key)
    if MESH[path] ~= nil and (MESH[path] == false or liveObj(MESH[path])) then return MESH[path] or nil end
    local o = loadObject(path .. "." .. path:match("[^/]+$"))
    MESH[path] = (o ~= nil and valid(o)) and o or false
    if MESH[path] and pin then pcall(pin, o, "ULYSSES' mesh " .. tostring(key)) end   -- (kept loaded between its rounds)
    if not MESH[path] then ul("mesh " .. path .. " didn't load (is SurvivalMode_Ulysses_P installed?)") end
    return MESH[path] or nil
end
-- the rock's paint: one dynamic instance of the x40a's gear material with the rock's textures (as sv_solg.lua paint)
local PAINT = {}
-- ((2026-11-24, the ulysses2 autotest: a crash at round 2's start after a minute's break, every rock gone) a paint made
-- once and kept is the game's to collect when nothing draws with it: a kept one is used only while still live and still
-- named as when made (hard rule 59), else made again
local function paintKept(key)
    local m = PAINT[key]
    if m == nil or m == false then return m end
    local nm = PAINT[key .. "#name"]
    if liveObj(m) and (not nm or not nameOf or select(2, pcall(nameOf, m)) == nm) then return m end
    ul("paint " .. key .. ": the kept one was collected (nothing drew with it): made again")
    PAINT[key] = nil
    return nil
end
local function paintMid()
    if paintKept("mid") ~= nil then return PAINT.mid or nil end
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
    PAINT["mid#name"] = nameOf and nameOf(mid) or nil
    if pin then pcall(pin, mid, "ULYSSES' rock paint") end   -- (kept: VALKA's assets' way, sv_anomalies_valka.lua)
    ul(string.format("paint: the rock's instance made, %d textures in", nT))
    return mid
end
function ULY.tailMid(which)
    which = which or "paint"
    local key = which == "paint" and "tail" or ("tail_" .. which)
    if paintKept(key) ~= nil then return PAINT[key] or nil end
    local P = (cfg().tail or {})[which] or {}
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local parent = P.parent and loadObject(P.parent .. "." .. P.parent:match("[^/]+$"))
    if not (valid(kml) and parent and valid(parent)) then PAINT[key] = false; ul("tail " .. which .. ": its parent didn't load"); return nil end
    local ok, mid = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, parent, FName("None"), 0) end)
    if not (ok and valid(mid)) then PAINT[key] = false; return nil end
    for slot, path in pairs(P.tex or {}) do
        local t = loadObject(path .. "." .. path:match("[^/]+$"))
        if t and valid(t) then pcall(function() mid:SetTextureParameterValue(FName(slot), t) end) end
    end
    for k, v in pairs(P.scalars or {}) do pcall(function() mid:SetScalarParameterValue(FName(k), v) end) end
    for k, v in pairs(P.vectors or {}) do pcall(function() mid:SetVectorParameterValue(FName(k), { R = v[1], G = v[2], B = v[3], A = v[4] or 1 }) end) end
    PAINT[key] = mid
    PAINT[key .. "#name"] = nameOf and nameOf(mid) or nil
    if pin then pcall(pin, mid, "ULYSSES' streak " .. which) end
    ul("tail " .. which .. ": its instance made")
    return mid
end
-- a rock: actor, AC:I's mesh at `scale` (skeletal, painted), a spin, a fire trail, an engine mover at `vel` (cm/s)
local function placeAt(c, L, rot)                         -- (a whole rotation through its quaternion: hard rule 76)
    -- ((2026-11-24, the autotest: turning a rock again changed nothing) Scale3D read back from GetComponentScale made the
    -- call fail, silently in its pcall: never placed nor turned (its spawn's turn kept). A plain scale, as sv_solg.lua's;
    -- the rock's size is set after this (SetWorldScale3D)
    return pcall(function() c:K2_SetWorldTransform({ Rotation = quatOf(rot), Translation = { X = L.X, Y = L.Y, Z = L.Z },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false, {}, true) end)
end
-- look (optional): { paint = a key of cfg().tail (its streak's material), mesh = its streak's static mesh (SM_SV_Ulysses_<mesh>:
-- "Streak", AC:I's sprite card), tail_r = its streak's thickness x, hide_rock =
-- the rock itself not drawn (a streak of light only: AC:I's sky meteors) }
local function rock(key, at, vel, scale, spin, tailX, trails, look)
    local m = mesh(key)
    -- ((2026-11-23) its own streak behind it: the rock faces along its fall (+X forward), its spin a roll about that line)
    local hz = math.sqrt(vel.X * vel.X + vel.Y * vel.Y)
    local face = { Pitch = math.deg(math.atan(vel.Z, math.max(1, hz))), Yaw = math.deg(math.atan(vel.Y, vel.X)), Roll = math.random(0, 359) }
    -- ((2026-11-24, the user: "The target box isn't aligned") the actor's root a plain scene component, unturned and
    -- unscaled, moved by the ProjectileMovement; the mesh under it carries the turn, the size and the spin (the
    -- RotatingMovement on the mesh alone), and a borrowed target hangs on the root: on the spinning 1.8-3.2x mesh its
    -- -HitCenterOffset (35 m) was scaled and swung round, its lock point 60-110 m off the rock (the autotest's probe)
    local a = newActor(at, {})
    if not a then return nil end
    local root = addComp(a, "/Script/Engine.SceneComponent")
    local c = addComp(a, "/Script/Engine.SkeletalMeshComponent")
    if not c then pcall(function() a:K2_DestroyActor() end); return nil end
    local okSet = m and pcall(function() c:SetSkeletalMeshAsset(m) end)
    if m and not okSet then okSet = pcall(function() c:SetSkeletalMesh(m, true) end) and "SetSkeletalMesh" or false else okSet = okSet and "SetSkeletalMeshAsset" or false end
    -- (a bare actor has no root: its spawn place went with the first component, at the world's origin (the SOLG's run of
    -- 2026-11-22 17:58, and this one's autotest of 2026-11-23: rocks 1.5 km under the sea). Put where it's wanted once its
    -- mesh is its root, the mesh itself too)
    pcall(function() a:K2_SetActorLocation({ X = at.X, Y = at.Y, Z = at.Z }, false, {}, true) end)
    local placed = placeAt(c, at, face)
    -- ((2026-11-24, the user: "The meteors look like they're travelling backwards"; the autotest measured every rock's front
    -- at -0.96 / -0.88 of its way: its height right, its heading turned round, as a pitch read as 180 - pitch) its front read
    -- back and, if it points away from its way, turned through 180 - pitch; still wrong: the plain opposite
    local function along()
        local ok, f = pcall(function() return c:GetForwardVector() end)
        local m = math.sqrt(vel.X ^ 2 + vel.Y ^ 2 + vel.Z ^ 2)
        if not (ok and f and m > 1) then return 1 end
        return (f.X * vel.X + f.Y * vel.Y + f.Z * vel.Z) / m
    end
    local d0 = along()
    if d0 < 0.9 then
        local f1 = { Pitch = 180 - face.Pitch, Yaw = face.Yaw, Roll = face.Roll }
        placeAt(c, at, f1)
        local d1 = along()
        if d1 < 0.9 then
            local f2 = { Pitch = -face.Pitch, Yaw = face.Yaw + 180, Roll = face.Roll }
            placeAt(c, at, f2)
            if along() < d1 then placeAt(c, at, f1) end
        end
    end
    FACELOG = (FACELOG or 0) + 1
    if FACELOG <= 3 then ul(string.format("a rock's front: %.2f along its way when placed (%s), %.2f now", d0, tostring(placed), along())) end
    local mid = paintMid()
    if mid then
        local slots = 1
        pcall(function() slots = c:GetNumMaterials() end)
        for i = 0, math.max(0, slots - 1) do pcall(function() c:SetMaterial(i, mid) end) end
    end
    pcall(function() c:SetCollisionEnabled(0) end)
    pcall(function() c:SetWorldScale3D({ X = scale, Y = scale, Z = scale }) end)
    pcall(function() c:SetCastShadow(not (look and look.hide_rock)) end)
    if look and look.hide_rock then pcall(function() c:SetVisibility(false, false) end) end
    local rm = addComp(a, "/Script/Engine.RotatingMovementComponent")
    if rm then
        pcall(function() rm:SetUpdatedComponent(c) end)          -- (the mesh spins, not the root its target hangs on)
        pcall(function() rm.RotationRate = { Pitch = 0, Yaw = 0, Roll = spin } end)
    end
    local anc = root                                         -- (the borrowed target's hold: the unturned root)
    -- its own streak (SK_SV_Ulysses_Tail, tools/ulysses): behind it along -X, glowing (tail.paint), scaled with the rock
    local T = cfg().tail or {}
    -- ((2026-11-24, the ulylines autotest: every glow row drew dark grey) AC8's effect materials aren't made for skinned
    -- meshes (the engine's fallback material drawn instead): a light-only look is drawn on the static twin of the streak
    local static = T.component == "static" or (look and look.paint ~= nil and look.paint ~= "paint")
    local tm = nil
    -- ((2026-11-24, the user: "dont use those tube like meteor things, they look silly, just use the smoke") tailX 0: no
    -- streak of ours on it, its smoke and fire only (the fragments' and the core's: fragments.tail_x / big.tail_x)
    if T.enabled ~= false and n(tailX, 1) > 0 then
        if static then
            local path = cfg().mesh_path:gsub("SK_SV_", "SM_SV_") .. (look and look.mesh or T.mesh or "Tail")
            -- ((2026-11-24, the code review) cached and pinned as mesh() is: up to ~8 sky streaks a second looked up)
            tm = MESH[path]
            if not (tm and liveObj(tm)) then
                tm = loadObject(path .. "." .. path:match("[^/]+$"))
                MESH[path] = tm
                if tm and pin then pcall(pin, tm, "ULYSSES' static " .. path:match("[^/]+$")) end
            end
        else tm = mesh(T.mesh or "Tail") end
    end
    if tm and valid(tm) then
        local tc = addComp(a, static and "/Script/Engine.StaticMeshComponent" or "/Script/Engine.SkeletalMeshComponent")
        if tc then
            if static then pcall(function() tc:SetStaticMesh(tm) end)
            elseif not pcall(function() tc:SetSkeletalMeshAsset(tm) end) then pcall(function() tc:SetSkeletalMesh(tm, true) end) end
            pcall(function() tc:SetCollisionEnabled(0) end)
            pcall(function() tc:SetCastShadow(false) end)
            pcall(function() tc:K2_AttachToComponent(c, FName("None"), 2, 2, 1, false) end)
            local ts = n(T.scale, 1) * scale
            local tr = n(look and look.tail_r, 1)
            pcall(function() tc:SetRelativeScale3D({ X = ts * n(T.length_x, 1) * (tailX or 1), Y = ts * tr, Z = ts * tr }) end)
            local which = look and look.paint or "paint"
            local tmid = T[which] and ULY.tailMid and ULY.tailMid(which)
            if tmid then pcall(function() tc:SetMaterial(0, tmid) end) end
        end
        -- ((2026-11-24, the 0.75.76 shots: the streaks read as solid cream tubes) a glow round it: the same mesh a little
        -- wider and longer, on AC8's additive MI_TrainingRingGlow (VALKA's portal haze), so it burns rather than shines
        local G = T.glow
        local gmid = G and G.enabled ~= false and not (look and look.paint) and ULY.tailMid and ULY.tailMid("glow")
        local gc = gmid and addComp(a, static and "/Script/Engine.StaticMeshComponent" or "/Script/Engine.SkeletalMeshComponent")
        if gc then
            if static then pcall(function() gc:SetStaticMesh(tm) end)
            elseif not pcall(function() gc:SetSkeletalMeshAsset(tm) end) then pcall(function() gc:SetSkeletalMesh(tm, true) end) end
            pcall(function() gc:SetCollisionEnabled(0) end)
            pcall(function() gc:SetCastShadow(false) end)
            pcall(function() gc:K2_AttachToComponent(c, FName("None"), 2, 2, 1, false) end)
            local ts = n(T.scale, 1) * scale
            local gr = n(G.radius_x, 1.8)
            pcall(function() gc:SetRelativeScale3D({ X = ts * n(T.length_x, 1) * (tailX or 1) * n(G.length_x, 1.15), Y = ts * gr, Z = ts * gr }) end)
            pcall(function() gc:SetMaterial(0, gmid) end)
        end
    end
    local pm = addComp(a, "/Script/Engine.ProjectileMovementComponent")
    if pm then
        pcall(function() pm:SetUpdatedComponent(a.RootComponent) end)
        pcall(function() pm.ProjectileGravityScale = 0 end)
        pcall(function() pm.bRotationFollowsVelocity = false end)
        pcall(function() pm.MaxSpeed = 0 end)
        pcall(function() pm.Velocity = { X = vel.X, Y = vel.Y, Z = vel.Z } end)
    end
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    TRAILOK = 0
    for _, t in ipairs(trails or cfg().trails or {}) do        -- (its smoke and its fire; trails: a test's own)
        local sys = SPC and SPC.V and SPC.V.asset and SPC.V.asset(t.path)
        if valid(lib) and sys then
            local ts = n(t.scale, 6) * math.max(0.5, scale)
            local tc = nil
            if pcall(function() tc = lib:SpawnSystemAttached(sys, c, FName("None"), { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 },
                { X = ts, Y = ts, Z = ts }, 0, true, 0, true) end) and valid(tc) then TRAILOK = TRAILOK + 1 end
        end
    end
    -- ((2026-11-23, the autotest of 0.75.71: boxes right, no rock seen) the first rocks' state, for the next run
    ROCKLOG = (ROCKLOG or 0) + 1
    if ROCKLOG <= 3 then
        local function q(f) local ok, v = pcall(f); return ok and tostring(v) or "?" end
        local okL, L = pcall(function() return c:K2_GetComponentLocation() end)
        local okA, A2 = pcall(function() return a:K2_GetActorLocation() end)
        ul(string.format("rock %d (%s, x%.1f): mesh %s by %s, asset read %s, visible %s, hidden %s, registered %s, bounds %s m, comp at %s, actor at %s, root is it %s, trail %s",
            ROCKLOG, tostring(key), scale, m and nameOf(m) or "NONE", tostring(okSet), q(function() return nameOf(c:GetSkinnedAsset()) end), q(function() return c:IsVisible() end),
            q(function() return c.bHiddenInGame end), q(function() return c:IsRegistered() end), q(function() return math.floor(c.Bounds.SphereRadius / 100) end),
            okL and L and string.format("(%.1f, %.1f, %.1f km)", L.X / 100000, L.Y / 100000, L.Z / 100000) or "?",
            okA and A2 and string.format("(%.1f, %.1f, %.1f km)", A2.X / 100000, A2.Y / 100000, A2.Z / 100000) or "?",
            q(function() return addrOf(a.RootComponent) == addrOf(c) end), tostring(TRAILOK)))
    end
    return { a = a, c = c, pm = pm, anc = anc, name = nameOf and nameOf(a) or nil }
end
-- ((2026-11-24, the ulysses2 autotest's crash at round 2's start, a minute's break after round 1) still ours: its address
-- live AND still named as when made (hard rule 59: a freed address is soon another object's)
local function rockLive(r)
    if not (r and r.a and liveObj(r.a)) then return false end
    if r.name and nameOf then
        local ok, nm = pcall(nameOf, r.a)
        if not ok or nm ~= r.name then return false end
    end
    return true
end
local function rockAt(r)
    if not rockLive(r) then return nil end
    local ok, L = pcall(function() return r.a:K2_GetActorLocation() end)
    return ok and L and { X = L.X, Y = L.Y, Z = L.Z } or nil
end
local function rockOff(r)
    if rockLive(r) then pcall(function() r.a:K2_DestroyActor() end) end
    if r then r.a = nil end
end
local function boom(at, scale, silent)
    if at and fxAt then pcall(fxAt, cfg().fx, at, scale, 8) end
    if not silent then bang(at) end
end
-- ((2026-11-24, the user: "tonitrus spear impact for the impact sfx") a landing's sound: AC8's Tonitrus Spear impact
-- (kind: ground / sea) in place of the explosion (sounds.landing "spear"); the explosion only if the Spear's won't post
-- (a shot down in the air keeps the explosion: boom)
local function landSound(kind, at)
    if (cfg().sounds or {}).landing == "spear" and spearAt(kind, at) then return end
    bang(at)
    if (cfg().sounds or {}).landing ~= "spear" then spearAt(kind, at) end
end

---------------------------------------------------------------------------------------------------- the borrowed targets
local FLAGS_ON = { bShowHUDBox = true, bIsNotLockonTarget = false, bIsNotFCSTargets = false, bIsInvincible = false }
local FLAGS_OFF = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }
local function flags(o, f) for k, v in pairs(f) do pcall(function() o[k] = v end) end end
local function hideOwn(o)
    local nh, seen = 0, 0
    for _, cls in ipairs({ "/Script/Engine.StaticMeshComponent", "/Script/Engine.SkeletalMeshComponent", "/Script/Engine.PoseableMeshComponent" }) do
        local c = StaticFindObject(cls)
        local ok, list = pcall(function() return o:K2_GetComponentsByClass(c) end)
        if ok and list then
            pcall(function() list:ForEach(function(_, e)
                seen = seen + 1
                if pcall(function() e:get():SetVisibility(false, true) end) then nh = nh + 1 end
            end) end)
        end
    end
    -- ((2026-11-24, an autotest close-up: Mission 4's radar tower hanging under a fragment) its components aren't found by
    -- class (0 of 0 above: the tower's meshes never hidden): the whole actor hidden, as the Anomaly's planes are
    local hid = pcall(function() o:SetActorHiddenInGame(true) end)
    return nh, seen, hid
end
local CAPTURE = nil
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    if CAPTURE and #CAPTURE < 120 then CAPTURE[#CAPTURE + 1] = o end
end)
local U = nil                                             -- this round's state (host / solo)
local PARK = { X = 0, Y = 0, Z = -5000000 }
-- ((2026-11-28, Saint Alessia's co-op run of 0.75.117: "only the first wave of Ulysses fragments could be targeted, even
-- then only with MSL or ATG weapons, not ATA") the borrowed target is Mission 4's radar tower base, a ground object, so
-- the air-to-air specials never locked it: on a fragment it's an air object (bIsAir, what IsAir() answers), parked not
local function air(o, on) pcall(function() o.bIsAir = on and true or false end) end
-- ((2026-11-28, the same run) a borrowed unit stays up once spawned (its objects parked, never down), and SV_Spawn refuses
-- a unit still up (-3, SV_ERR_UP): her round 20 borrowed 0 (so did 15 autotest runs), and the SOLG later in the run would
-- have too. One pool a unit for the level (KEEP), taken again by ULYSSES' next round (each object still ours: live, the
-- same address and name, hard rule 59), held (HOLD) until its last round is over: then handed back, sv_rounds.lua's
-- clean-up finishing them off and taking the unit off the spawner's list (ULY.holdsTargets false). spawningUnit names the
-- spawn for that clean-up's list (SPC.CLEAN_OBJ), as the SOLG's does
local KEEP, HOLD = {}, false
local function park(o) pcall(function() o:K2_SetActorLocation(PARK, false, {}, true) end) end
local function ours(e) return e and liveObj(e.o) and addrOf(e.o) == e.a and nameOf(e.o) == e.name end
-- a borrowed unit up (or its pool kept from ULYSSES' last round): its objects hidden, parked, off; -> the list
local function poolUp(unit)
    HOLD = true
    local kept = KEEP[unit]
    if kept then
        local out = {}
        for _, e in ipairs(kept) do
            if ours(e) then
                e.used, e.attached, e.lastH = false, nil, nil
                hideOwn(e.o)
                flags(e.o, FLAGS_OFF)
                air(e.o, false)
                park(e.o)
                out[#out + 1] = e
            end
        end
        if #out > 0 then
            KEEP[unit] = out
            ul(string.format("targets: %s kept from ULYSSES' last round: %d of its %d still ours, borrowed again", unit, #out, #kept))
            return out
        end
        ul(string.format("targets: %s kept from ULYSSES' last round: none of its %d still ours; spawned again", unit, #kept))
    end
    if type(SV_Spawn) ~= "function" then return {} end
    CAPTURE = {}
    spawningUnit = unit
    local okS, r = pcall(SV_Spawn, unit, AIRFIELD.X, AIRFIELD.Y, 3000000, 0)
    spawningUnit = nil
    local got = CAPTURE
    CAPTURE = nil
    if not okS then r = "error " .. tostring(r) end
    local out = {}
    for _, o in ipairs(got) do
        if valid(o) then
            hideOwn(o)
            flags(o, FLAGS_OFF)
            air(o, false)
            park(o)
            out[#out + 1] = { o = o, a = addrOf(o), name = nameOf(o) }
        end
    end
    KEEP[unit] = out
    ul(string.format("targets: %s up, %d objects borrowed (%s)", unit, #out,
        type(r) == "number" and r > 0 and (r .. " up") or (SV_ERR and SV_ERR[r] or tostring(r))))
    return out
end
-- ULYSSES done with its targets (its last round over, or ended): held no more, so the specials' clean-up (sv_rounds.lua
-- SPC.cleanUnitsOf) finishes them off and takes their units off the spawner's list. A co-op host's held unpaid first
-- (COOP.payHold: down on every game as a removal, nobody's kill: the joiners' hits on them in the round never make one).
-- now: also the clean-up itself, at once (an end the specials' own clean-up won't see: a run over mid-round); dropped:
-- the level is going, nothing of it touched (its lists forgotten)
local function release(why, now, dropped)
    local was = HOLD
    HOLD = false
    if dropped then KEEP = {}; return end
    local units, n = {}, 0
    for unit, pool in pairs(KEEP) do
        units[#units + 1] = unit
        for _, e in ipairs(pool) do
            if ours(e) then
                n = n + 1
                if COOP and COOP.payHold and COOP.host and COOP.host() then pcall(COOP.payHold, e.o, true) end
            end
        end
    end
    KEEP = {}
    if was then ul(string.format("targets: %d handed back (%s): %s", n, tostring(why), table.concat(units, ", "))) end
    if now and was and #units > 0 and SPC and SPC.cleanUp then pcall(SPC.cleanUp, units, "ULYSSES over (" .. tostring(why) .. ")", true, now) end
end
local function boxTexts(on)
    if type(SV_SetText) ~= "function" then return end
    BOXED = on and true or nil                            -- (ULY.endAll puts the SOLG's back if still ours)
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
            local to = (r.anc and liveObj(r.anc)) and r.anc or r.c
            local att = pcall(function() e.o:K2_AttachToComponent(to, FName("None"), 2, 2, 1, false) end)
            local okH, hx, hy, hz = pcall(function() local h = e.o.HitCenterOffset; return h.X, h.Y, h.Z end)
            if att and okH and tonumber(hx) then
                pcall(function() e.o:K2_SetActorRelativeLocation({ X = -hx, Y = -hy, Z = -hz }, false, {}, true) end)
            end
            -- (its lock point, the target's place + its HitCenterOffset, against the rock's centre: once, twice a run)
            BOXLOG = (BOXLOG or 0) + 1
            if BOXLOG <= 2 then
                local okL, L = pcall(function() return e.o:K2_GetActorLocation() end)
                local R = rockAt(r)
                if okL and L and R and okH and tonumber(hx) then
                    local d = math.sqrt((L.X + hx - R.X) ^ 2 + (L.Y + hy - R.Y) ^ 2 + (L.Z + hz - R.Z) ^ 2) / 100
                    ul(string.format("target's lock point %.1f m from its rock's centre (HitCenterOffset %.0f, %.0f, %.0f cm; on %s)",
                        d, hx, hy, hz, to == r.anc and "its anchor" or "its mesh"))
                end
            end
            pcall(function() e.o.MaxHealth = hp; e.o.HealthInternal = math.floor(hp * 10 + 0.5); e.o.MinHealth = 1 end)
            local nh, seen, hid = hideOwn(e.o)
            flags(e.o, FLAGS_ON)
            air(e.o, true)
            e.attached = att
            if ARMLOG == nil or ARMLOG < 2 then                   -- (the air flag read back, the first two)
                local okA, isAir = pcall(function() return e.o:IsAir() end)
                local okB, bAir = pcall(function() return e.o.bIsAir end)
                ul(string.format("target an air object: IsAir() %s, bIsAir %s", okA and tostring(isAir) or ("unread: " .. tostring(isAir)),
                    okB and tostring(bAir) or "unread"))
            end
            -- ((2026-11-24, an autotest close-up: a radar tower under a fragment) what the borrowed target is made of, once
            ARMLOG = (ARMLOG or 0) + 1
            if ARMLOG <= 2 then
                ul(string.format("target hidden: %d of %d mesh parts, the actor %s", nh, seen, hid and "hidden" or "NOT hidden"))
                local parts = {}
                pcall(function()
                    local list = e.o:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SceneComponent"))
                    list:ForEach(function(_, x)
                        local m = x:get()
                        local cn = "?"
                        pcall(function() cn = m:GetClass():GetFName():ToString() end)
                        local vis = "?"
                        pcall(function() vis = tostring(m:IsVisible()) end)
                        parts[#parts + 1] = cn .. ":" .. vis
                    end)
                end)
                local kids = 0
                pcall(function() local arr = {}; e.o:GetAttachedActors(arr, true, true); kids = #arr end)
                ul(string.format("target %s: %d parts [%s], %d attached actors", tostring(e.name), #parts, table.concat(parts, " "), kids))
            end
            return e
        end
    end
    return nil
end
local function disarm(e)
    if not e then return end
    flags(e.o, FLAGS_OFF)
    air(e.o, false)
    pcall(function() e.o:K2_DetachFromActor(1, 1, 1) end)
    park(e.o)
    -- ((2026-11-24, the user: "atleast 50") handed back for the next fragment: the KEW unit lends 36, a round has 50-90
    -- (arm sets its health, MinHealth and flags anew)
    e.used = false
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
-- ((2026-11-24, the code review) the look is the HUD's sepia wash (sv_hud.lua HUD.film): AC8's camera manager ignores a
-- post-process volume of ours and no camera component of the plane was ever found (0 in every autotest), so neither is
-- made any more: no engine object kept between ticks (hard rule 59). FILM: its fade (from -> to over film.fade_s, os.clock)
local FILM = {}
local function filmOn()
    local f = cfg().film or {}
    if f.enabled == false then return "off" end
    if FILM.on then return "up" end
    FILM.on, FILM.from, FILM.to, FILM.at, FILM.cur, FILM.said = true, FILM.cur or 0, 1, os.clock(), FILM.cur or 0, false
    return "on (the HUD's wash)"
end
local function filmOff(now)
    if FILM.on then FILM.from, FILM.to, FILM.at = FILM.cur or 1, 0, os.clock() end
end
local function filmTick(now)
    if not FILM.on then return end
    now = os.clock()                                      -- (FILM.at is os.clock's: the tick's own clock is the game's)
    local f = cfg().film or {}
    local u = math.min(1, (now - (FILM.at or now)) / math.max(0.1, n(f.fade_s, 2)))
    FILM.cur = FILM.from + (FILM.to - FILM.from) * u
    if HUD and HUD.film then
        local fl = 1 + (math.random() * 2 - 1) * n(f.flicker, 0.04) / math.max(0.01, n(f.overlay_a, 0.26))
        local okF, r = pcall(HUD.film, n(f.overlay_a, 0.26) * FILM.cur * fl, f.overlay)
        if not FILM.said and FILM.cur > 0.5 then FILM.said = true; ul("film overlay: HUD.film " .. tostring(okF) .. " " .. tostring(r) .. ", opacity " .. string.format("%.2f", n(f.overlay_a, 0.26) * FILM.cur) .. ", on " .. tostring(HUD.filmInfo and (HUD.filmInfo()) or "?")) end
    end
    if FILM.to == 0 and u >= 1 then
        if HUD and HUD.film then pcall(HUD.film, 0) end
        FILM.on, FILM.cur = false, 0
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
-- ((2026-11-24, the user: "add more subtitles through the two rounds, like News Broadcasts, go through the lore and make
-- a story about the different areas that are being affected by the planetfall or the ulysses event", "report on it as if
-- its happening at that current time") WORLD NEWS bulletins: an exchange of text.news.round<phase> every news.every_s
-- from news.first_s, in order; text.news.core when the core comes, core_down / core_hit after it. Every game its own (the
-- host's round; a joiner's from the host's word), on the round's clock (held while paused)
local NEWS = { on = false }
local function newsClock(now) return (D and D.now) or now or os.clock() end
local function newsStart(phase, now)
    local c = cfg().news or {}
    NEWS.on = c.enabled ~= false
    NEWS.list, NEWS.i = (((cfg().text or {}).news or {})["round" .. tostring(phase)]) or {}, 0
    NEWS.nextAt = newsClock(now) + n(c.first_s, 30)
end
local function newsOne(key)
    if (cfg().news or {}).enabled == false then return end
    local ex = ((cfg().text or {}).news or {})[key]
    if type(ex) == "table" and type(ex[1]) == "table" then ex = ex[1] end
    if type(ex) == "table" then say(ex) end
end
local function newsTick(now)
    if not NEWS.on or newsClock(now) < (NEWS.nextAt or 0) then return end
    NEWS.i = NEWS.i + 1
    local ex = NEWS.list and NEWS.list[NEWS.i]
    if type(ex) ~= "table" then NEWS.on = false; return end
    say(ex)
    NEWS.nextAt = newsClock(now) + n((cfg().news or {}).every_s, 36)
end
local function newsOff() NEWS.on = false end

---------------------------------------------------------------------------------------------------- the round
local function players() return (type(playerCount) == "function" and playerCount()) or 1 end
local function fragmentsFor(phase)
    local f = cfg().fragments
    local base = n(phase == 1 and f.round1 or f.round2, 16)
    local p = players()
    local x = p <= 1 and n(f.solo_x, 1) or (1 + n(f.per_player, 0) * (p - 1))
    return math.max(1, math.min(n(f.max_n, 40), math.floor(base * x + 0.5)))
end
local function aimPoint(aimed)
    local f = cfg().fragments
    -- ((2026-11-24, the user: "it doesn't matter if meteorites miss the land mass or not, have them vastly spread out around
    -- the comona island") area_km: anywhere in that box, land or sea; land() decides by where it comes down
    local A = f.area_km
    -- (aimed: one of aim_share's, at the airfield or a town as before the spread; the rest anywhere in area_km)
    if type(A) == "table" and type(A.x) == "table" and type(A.y) == "table" and not aimed then
        U.lastAim = "comona"
        return { X = span(A.x, 0) * 100000, Y = span(A.y, 0) * 100000, Z = 0 }, U.lastAim
    end
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
    -- ((2026-11-24, the user: "Try making it like infinities"; AC:I's mission data: every meteorite dives at 45 degrees,
    -- all the same way, 550-650 km/h) dive_deg: from from_deg's side (0 = east, +X), within spread_deg, as far out as
    -- its height over tan(dive)
    if spec.dive_deg then
        bearing = math.rad(n(spec.from_deg, 0) + rnd(-1, 1) * n(spec.spread_deg, 20))
        dkm = (alt - (P.Z or 0)) / 100000 / math.tan(math.rad(n(spec.dive_deg, 45)))
    end
    local start = { X = P.X + math.cos(bearing) * dkm * 100000, Y = P.Y + math.sin(bearing) * dkm * 100000, Z = alt }
    local dx, dy, dz = P.X - start.X, P.Y - start.Y, P.Z - start.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local v = span(spec.speed_kmh, 1200) / 3.6 * 100                 -- (cm/s)
    local T = d / v
    local key = type(spec.meshes) == "table" and spec.meshes[math.random(1, #spec.meshes)] or spec.mesh or "C"
    local sc, sp = span(spec.scale, 1), span(spec.spin_dps, 20)
    local r = rock(key, start, { X = dx / T, Y = dy / T, Z = dz / T }, sc, sp, n(spec.tail_x, 1))
    if not r then return nil end
    U.lastScale, U.lastSpin = sc, sp
    U.nextId = (U.nextId or 0) + 1
    -- ((2026-11-23, the autotest of 0.75.72: rocks landed late, under the ground) the round's clock (the game's, sv_flights.lua
    -- roundClock: the one roundTick's now is, and the one the mover flies on), never os.clock: the two drift apart
    local t0 = (D and D.now) or os.clock()
    local f = { r = r, P = P, what = what, big = big, hitAt = t0 + T, born = t0, key = key, id = U.nextId }
    -- ((2026-11-24, the code review) fragments.solo_x is their COUNT's solo multiplier (fragmentsFor), not their health's:
    -- a health one is solo_hp_x (the core's solo_x is its health's, as its config says)
    local hp = n(spec.health, 300) * (players() <= 1 and n(spec.solo_hp_x or (big and spec.solo_x) or 1, 1) or 1)
    f.e = arm(big and U.poolBig or U.pool, r, hp)
    if not f.e then
        U.unarmed = (U.unarmed or 0) + 1
        if U.unarmed == 1 then ul("a fragment launched with no target on it (none of the borrowed ones free): it can't be locked") end
    end
    -- ((2026-11-28, Saint Alessia's co-op run: the other players "couldn't target anything") its target's co-op id last
    -- (COOP.groundIdOf: the host's id for it, 0 for none): each joiner puts its own copy of that target on its rock
    local cid = 0
    if f.e and COOP and COOP.groundIdOf then
        local okI, id = pcall(COOP.groundIdOf, f.e.o, f.e.cid)
        if okI and tonumber(id) and id > 0 then cid, f.e.cid = id, id end
    end
    if f.e and cid == 0 and COOP and COOP.open and COOP.host and COOP.host() then
        U.noId = (U.noId or 0) + 1
        if U.noId == 1 then ul("a fragment's target has no co-op id yet: the other players' games can't put it on their rock") end
    end
    tell("f", tostring(f.id), key, string.format("%.0f", start.X / 100), string.format("%.0f", start.Y / 100), string.format("%.0f", start.Z / 100),
        string.format("%.0f", dx / T), string.format("%.0f", dy / T), string.format("%.0f", dz / T), string.format("%.0f", (U.lastScale or 1) * 100),
        string.format("%.0f", U.lastSpin or 20), big and "1" or "0", tostring(cid))
    fallOn(f, r.a, big, function() return rockAt(f.r) end)
    return f
end
-- land or sea where P is: a trace down (near you only: hard rule 27); none: land when within sea.land_m of where it aimed
local kis = nil
-- ((2026-11-24) land or sea anywhere on Comona, the same on every game: the land map (sv_ulysses_land.lua, 100 m cells,
-- from the terrain's collision mesh). Its rows parsed once into runs
local LANDROWS
function ULY.isLand(x, y)
    local L = ULY.LAND
    if not L then return nil end
    if not LANDROWS then
        LANDROWS = {}
        for i, row in ipairs(L.rows) do
            local runs = {}
            for a, b in row:gmatch("(%d+)%-(%d+)") do runs[#runs + 1] = { tonumber(a), tonumber(b) } end
            LANDROWS[i] = runs
        end
    end
    local col = math.floor((x - L.x0) / L.cell)
    local r = math.floor((y - L.y0) / L.cell) + 1
    local runs = LANDROWS[r]
    if not runs or col < 0 or col >= L.w then return false end
    for _, ab in ipairs(runs) do if col >= ab[1] and col <= ab[2] then return true end end
    return false
end
local function onLand(P, what)
    -- (the land map first: hard rule 27, a trace far from the player finds the sea planes, not the land)
    local m = ULY.isLand(P.X, P.Y)
    if m ~= nil then return m, m and 500 or nil, "the land map" end
    local sc = cfg().sea or {}
    local seaZ = n(sc.sea_z, 350)
    if not valid(kis) then kis = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    local hit, z = {}, nil
    if valid(kis) and valid(survivalPC) then
        pcall(function() kis:LineTraceSingle(survivalPC, { X = P.X, Y = P.Y, Z = 1000000 }, { X = P.X, Y = P.Y, Z = -100000 }, 0, true, {}, 0,
            hit, true, { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0) end)
        pcall(function() local h = hit.OutHit or hit; local l = h.ImpactPoint or h.Location; if l and l.Z then z = l.Z end end)
        local what2 = "?"
        pcall(function()
            local h = hit.OutHit or hit
            local c = h.Component and h.Component:Get() or h.Component
            what2 = c and c:GetFullName() or what2
        end)
        LANDTRACE = string.format("z %.1f m on %s", (z or -1e5) / 100, tostring(what2):match("([^/%.:]+)%.[^/]*$") or tostring(what2):sub(1, 60))
        -- ((2026-11-24, the ulysses2 autotest: Comona's runway and terrain trace at 3.9-5 m, under the old sea_z + 5 m:
        -- every hit read as the sea) what it hit says it: the level's sea is a mesh named *_Env_Sea (Mission022_Common_Env_Sea)
        if z and what2 ~= "?" then return not tostring(what2):find("_Env_Sea", 1, true), z, "traced" end
    end
    if z then return z > seaZ + 500, z, "traced" end
    local base = what == "airfield" and AIRFIELD or nil
    if what == "town" then
        local best = nil
        for _, t in ipairs(cfg().towns or {}) do
            local d = (t.X - P.X) ^ 2 + (t.Y - P.Y) ^ 2
            if not best or d < best then best, base = d, t end
        end
    end
    local near = base and math.sqrt((base.X - P.X) ^ 2 + (base.Y - P.Y) ^ 2) <= n(sc.land_m, 1200) * 100
    return near, nil, "by its aim"
end
local function land(f, now)
    local at = rockAt(f.r) or f.P
    local sc = cfg().sea or {}
    local isLand, gz, how = onLand(f.P, f.what)
    if isLand then
        local G = { X = f.P.X, Y = f.P.Y, Z = gz or f.P.Z }
        boom(G, n((cfg().fx_scale or {})[f.big and "big_land" or "land"], 10), true)
        landSound("ground", G)
    else                                                  -- (the Spear's splash at the sea's level)
        local W = { X = f.P.X, Y = f.P.Y, Z = n(sc.sea_z, 350) }
        if fxAt then pcall(fxAt, sc.fx or {}, W, n(f.big and sc.big_scale or sc.scale, 1.5), 20) end
        landSound("sea", W)
    end
    f.where = (isLand and "land" or "sea") .. " (" .. how .. ")"
    tell("l", tostring(f.id), isLand and "1" or "0")
    fallOff(f)
    disarm(f.e)
    rockOff(f.r)
    local fr = cfg().fragments
    local dmg = f.big and n(cfg().big.airfield_damage, 120) or n(fr.airfield_damage, 8)
    local d = math.sqrt((f.P.X - AIRFIELD.X) ^ 2 + (f.P.Y - AIRFIELD.Y) ^ 2)
    -- ((2026-11-24, the user: spread "vastly" round Comona, area_km) by where it came down: within airfield_m of the
    -- airfield the airfield's damage, within town_m of a town the town's callout, open land as harmless as the sea. A
    -- fragment aimed at the airfield / a town (no area_km) counts for it as before
    local nearTown = false
    for _, t in ipairs(cfg().towns or {}) do
        if math.sqrt((t.X - f.P.X) ^ 2 + (t.Y - f.P.Y) ^ 2) <= n(fr.town_m, 2500) * 100 then nearTown = true end
    end
    local hurts = f.big or (isLand and (f.what == "airfield" or d < n(fr.airfield_m, 4000) * 100))
    local town = not hurts and isLand and (f.what == "town" or nearTown)
    -- ((2026-11-24, the 0.75.72 shots: "A FRAGMENT HIT THE TOWN" for one in the sea) the sea takes it: no damage, no
    -- callout (the core's still the airfield's, wherever it comes down)
    if not f.big and not isLand then
        U.landedSea = (U.landedSea or 0) + 1
    elseif hurts then
        if AF and type(AF.bomb) == "number" then AF.bomb = AF.bomb + dmg end
        U.landedAirfield = U.landedAirfield + 1
    elseif town then
        U.landedTown = U.landedTown + 1
        if (U.townSaid or 0) + 20 < now and hudCallout then U.townSaid = now; hudCallout(cfg().text.town_hit, nil) end
    else
        U.landedOpen = (U.landedOpen or 0) + 1
    end
    if f.big and hudCallout then hudCallout(cfg().text.big_hit, nil) end
    if f.big then newsOne("core_hit") end
    ul(string.format("%s landed (aimed: %s) at (%.1f, %.1f km), in the %s%s", f.big and "the core" or "a fragment", f.what, f.P.X / 100000,
        f.P.Y / 100000, (f.where or "?") .. (LANDTRACE and (" [" .. LANDTRACE .. "]") or ""),
        hurts and string.format(": the airfield -%d", dmg) or town and ": the town" or ": harmless"))
    return at
end
local function shot(f, now)
    local at = rockAt(f.r)
    boom(at, n((cfg().fx_scale or {})[f.big and "big_shot" or "shot"], 4))
    fallOff(f)
    disarm(f.e)
    rockOff(f.r)
    local pay = f.big and n(cfg().big.pay, 6000) or n(cfg().fragments.pay, 300)
    pay = specialPay and specialPay(pay) or pay
    if pay > 0 and addCredits then addCredits(pay, f.big and "the Ulysses core down" or "a Ulysses fragment down") end
    U.shot = U.shot + 1
    tell("s", tostring(f.id))
    if f.big and hudCallout then hudCallout(cfg().text.big_down, nil) end
    if f.big then newsOne("core_down") end
    if LB and LB.stat then pcall(LB.stat, f.big and "ulysses_core" or "ulysses_fragment", 1) end
    ul(string.format("%s shot down %.0f s before it would have hit (%.1f km up), paid %d", f.big and "the core" or "a fragment",
        f.hitAt - now, at and at.Z / 100000 or -1, pay))
end

-- ((2026-11-23) the autotest's A/B: rocks unseen in 0.75.71) debug_ab: two still rocks 500 m ahead of you, 60 m apart:
-- the skeletal one as the round's (rock()) and a StaticMeshComponent with the SM_ twin, both painted; logged
local function debugAB()
    local me = playerLocation and playerLocation()
    local pawn = liveObj(survivalPC) and survivalPC.Pawn
    if not (me and valid(pawn)) then return "no plane" end
    local okF, F = pcall(function() return pawn:GetActorForwardVector() end)
    local okR, Rv = pcall(function() return pawn:GetActorRightVector() end)
    if not (okF and okR) then return "no axes" end
    local P = { X = me.X + F.X * 50000, Y = me.Y + F.Y * 50000, Z = me.Z + F.Z * 50000 + 3000 }
    ULY.abAt = P
    local sk = rock("C", { X = P.X - Rv.X * 3000, Y = P.Y - Rv.Y * 3000, Z = P.Z }, { X = 0, Y = 0, Z = -1 }, 4, 20)
    local sm = loadObject(cfg().mesh_path:gsub("SK_SV_", "SM_SV_") .. "C." .. ("SM_SV_Ulysses_C"))
    local a = newActor({ X = P.X + Rv.X * 3000, Y = P.Y + Rv.Y * 3000, Z = P.Z }, { Pitch = 0, Yaw = 0, Roll = 0 })
    local c = a and addComp(a, "/Script/Engine.StaticMeshComponent")
    local okS = c and sm and pcall(function() c:SetStaticMesh(sm) end)
    if c then
        pcall(function() c:SetCollisionEnabled(0) end)
        pcall(function() c:SetWorldScale3D({ X = 4, Y = 4, Z = 4 }) end)
        pcall(function() a:K2_SetActorLocation({ X = P.X + Rv.X * 3000, Y = P.Y + Rv.Y * 3000, Z = P.Z }, false, {}, true) end)
        local mid = paintMid()
        if mid then pcall(function() c:SetMaterial(0, mid) end) end
    end
    if a then pcall(function() a:SetLifeSpan(60) end) end
    if sk and sk.a then pcall(function() sk.a:SetLifeSpan(60) end) end
    return string.format("A/B 500 m ahead: skeletal (left) %s; static (right) %s, mesh %s, set %s", sk and "up" or "NOT up", a and "up" or "NOT up",
        sm and nameOf(sm) or "NOT loaded", tostring(okS))
end
-- Stardust_Ambient's rumble under both rounds (and the break between), looped; off at the last round's end
local AMB = {}
local function ambOn()
    if AMB.h or AMB.a then return end
    -- (Wwise's: 2D, on an actor of ours, a scene root to carry its component; stopped with it)
    if wwEv("ambient") then
        local me = (playerLocation and playerLocation()) or { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = 0 }
        local a = newActor({ X = me.X, Y = me.Y, Z = me.Z or 0 }, {})
        if a then addComp(a, "/Script/Engine.SceneComponent") end
        if a and wwOn("ambient", a) then AMB.a = a; return end
        if a and liveObj(a) then pcall(function() a:K2_DestroyActor() end) end
    end
    local l = (cfg().sounds or {}).ambient
    if not (l and SND and SND.play) then return end
    local ok, h = pcall(SND.play, l, nil)
    AMB.h = ok and h or nil
end
local function ambOff()
    if AMB.a then
        wwOff(AMB.a)
        if liveObj(AMB.a) then pcall(function() AMB.a:K2_DestroyActor() end) end
        AMB.a = nil
    end
    if AMB.h and SND and SND.stop then pcall(SND.stop, AMB.h, 2) end
    AMB.h = nil
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
    tell("r", tostring(phase))
    ambOn()
    local sh = cfg().shift or {}
    if phase == 1 then
        fade(1, 0, n(sh.fade_s, 1.2) * 2, false)              -- (in from white: the time shift)
        if hudCallout then hudCallout(sh.card or "JULY 1999", sh.card_sub) end
    end
    ul(string.format("round %d: phase %d of %d, %d fragments%s; the film look %s", D.round, phase, n(cfg().rounds, 2), U.todo,
        U.bigAt and ", the core at +" .. n(cfg().big.at_s, 45) .. " s" or "", filmOn()))
    -- ((2026-11-24) 1999's Comona Control doesn't know your aircraft: its first round asks who you are, its second goes on)
    local sl = cfg().text.say or {}
    say(phase >= 2 and sl.start2 or sl.start)
    newsStart(phase, now)
    if cfg().debug_ab then ul(debugAB()) end
    local snd = (cfg().sounds or {}).encounter
    if not wwAt("encounter", nil) and snd and SND and SND.play then pcall(SND.play, snd, nil) end
    return true
end

local SKYM = { list = {}, nextAt = 0 }
local skyOne                                          -- (one of the sky's meteors: below)
-- the sky's meteors past their time (or gone) taken away: every tick, the round's or the break's (the ulysses2 autotest's
-- crash: through a minute's break they flew on untouched, hundreds of km, and round 2 touched what the game had freed)
local function skyClean(now)
    for i = #SKYM.list, 1, -1 do
        local m = SKYM.list[i]
        if now >= m.dieAt or not rockLive(m.r) then rockOff(m.r); table.remove(SKYM.list, i) end
    end
end
local function skyTick(now)
    local c = cfg().sky or {}
    if c.enabled == false or now < SKYM.nextAt then return end
    SKYM.nextAt = now + span(c.every_s, 2.5)
    local me = playerLocation and playerLocation()
    local cx, cy = me and me.X or AIRFIELD.X, me and me.Y or AIRFIELD.Y
    local burst = math.floor(span(c.burst, 1) + 0.5)
    for _ = 1, math.max(1, burst) do
        if #SKYM.list >= n(c.max_up, 70) then break end
        skyOne(c, now, cx, cy)
    end
end
skyOne = function(c, now, cx, cy)
    -- ((2026-11-24, the user: "They should not go from all directions but East to West") from_deg's side of you (the world's
    -- angle: 0 = east, +X; north is -Y, COMONA_MAP.md), spread lateral_km across, flying the other way within spread_deg;
    -- no from_deg: all directions, as before
    local d = span(c.from_km, 40) * 100000
    local alt = span(c.alt_m, 20000) * 100
    local start, across
    if c.from_deg ~= nil then
        local b = math.rad(n(c.from_deg, 0))
        local lat = rnd(-1, 1) * n(c.lateral_km, 40) * 100000
        start = { X = cx + math.cos(b) * d - math.sin(b) * lat, Y = cy + math.sin(b) * d + math.cos(b) * lat, Z = alt }
        across = b + math.pi + math.rad(rnd(-1, 1) * n(c.spread_deg, 10))
    else
        local b = math.random() * 2 * math.pi
        start = { X = cx + math.cos(b) * d, Y = cy + math.sin(b) * d, Z = alt }
        across = b + math.pi + rnd(-0.6, 0.6)                         -- (across the sky, past you, dipping)
    end
    local v = span(c.speed_kmh, 12000) / 3.6 * 100
    local dip = type(c.dip) == "table" and rnd(n(c.dip[1], 0.05), n(c.dip[2], 0.2)) or rnd(0.05, 0.2)
    local vel = { X = math.cos(across) * v, Y = math.sin(across) * v, Z = -v * dip }
    local key = type(c.meshes) == "table" and c.meshes[math.random(1, #c.meshes)] or "D"
    local r = rock(key, start, vel, span(c.scale, 3), rnd(20, 90), (c.look and c.look.mesh) and n(c.streak_x, 0.12) or n(c.tail_x, 1),
        c.no_trails and {} or cfg().sky_trails, c.look)
    -- ((2026-11-24) falling now: burnt out before floor_m (out of any fighter's reach), or at life_s)
    local life = n(c.life_s, 18)
    if c.floor_m and vel.Z < -1 then life = math.min(life, (alt - n(c.floor_m, 16000) * 100) / -vel.Z) end
    if r then SKYM.list[#SKYM.list + 1] = { r = r, dieAt = now + math.max(1, life) } end
end
local J = { on = false, rocks = {} }               -- (a joiner: the host's round on, its rocks drawn here by id)
-- ((2026-11-28, Saint Alessia's co-op run of 0.75.117: the other players "couldn't target anything", no hit of theirs
-- from 01:51 to 02:03) a joiner's games have copies of the host's borrowed targets (co-op's, as any unit's: bound by id,
-- held at the floor, a hit on one sent to the host, the host's health back), but nothing put them on the rocks here: they
-- hung where they spawned. The host's "f" names its target's co-op id; this game's copy goes on its rock (jArm: hidden,
-- its box on, an air object), off it at the rock's end (jDisarm: parked, box off). The copies on no rock: hidden, box off
-- (jSettle). J.hold: the host's ULYSSES has its next round to come (its "e" not the last), so the copies aren't switched
-- off between its rounds (ULY.holdsTargets)
J.settled = {}
local function jUnits() local t = cfg().target_units or {}; return { t.small, t.big } end
local function jSettle()
    if not (COOP and COOP.groundCopies) then return end
    local busy = {}
    for _, r in pairs(J.rocks) do if r.tgt then busy[r.tgt.a] = true end end
    for _, u in ipairs(jUnits()) do
        if type(u) == "string" then
            local okG, got = pcall(COOP.groundCopies, u)
            for _, o in ipairs(okG and got or {}) do
                local a = liveObj(o) and addrOf(o)
                local nm = a and nameOf(o)
                if a and not busy[a] and J.settled[a] ~= nm then
                    J.settled[a] = nm
                    hideOwn(o)
                    flags(o, FLAGS_OFF)
                    air(o, false)
                    park(o)
                end
            end
        end
    end
end
local function jDisarm(r)
    local t = r and r.tgt
    if not t then return end
    r.tgt = nil
    if not ours(t) then return end
    flags(t.o, FLAGS_OFF)
    air(t.o, false)
    pcall(function() t.o:K2_DetachFromActor(1, 1, 1) end)
    park(t.o)
    J.settled[t.a] = t.name
end
local function jArm(r, id)
    if not (COOP and COOP.copyObj) then return false, "this build has no COOP.copyObj" end
    local okC, o, a = pcall(COOP.copyObj, id)
    if not (okC and o and a) then return false, "no copy of the host's target " .. tostring(id) .. " here (not bound yet?)" end
    for _, r2 in pairs(J.rocks) do                       -- (still on another rock: the host took it again before its end came)
        if r2 ~= r and r2.tgt and r2.tgt.a == a then jDisarm(r2) end
    end
    local to = (r.anc and liveObj(r.anc)) and r.anc or r.c
    if not liveObj(to) then return false, "the rock has nothing to hold it" end
    local att = pcall(function() o:K2_AttachToComponent(to, FName("None"), 2, 2, 1, false) end)
    if not att then return false, "it wouldn't attach" end
    local okH, hx, hy, hz = pcall(function() local h = o.HitCenterOffset; return h.X, h.Y, h.Z end)
    if okH and tonumber(hx) then pcall(function() o:K2_SetActorRelativeLocation({ X = -hx, Y = -hy, Z = -hz }, false, {}, true) end) end
    -- (switched off by the specials' clean-up here, an older build's way: back on, or it takes no hit)
    pcall(function() o:SetActive(true, false, false) end)
    pcall(function() o:SetActorEnableCollision(true) end)
    pcall(function() o:SetActorTickEnabled(true) end)
    hideOwn(o)
    flags(o, FLAGS_ON)
    air(o, true)
    r.tgt = { o = o, a = a, name = nameOf(o), id = id }
    return true
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
            -- ((2026-11-24, the user: "in waves of 2") per_wave of them at once, each its own aim
            for _ = 1, math.max(1, math.floor(n(f.per_wave, 1))) do
                if U.sent >= U.todo or falling >= n(f.at_once, 6) then break end
                -- ((2026-11-24, the ulysses2 autotest: 6 of 10 fell harmless in the sea, all coming from the east onto a
                -- coastal airfield) one aimed at the airfield or a town (aim_share, or every one without area_km) steered
                -- onto land, aim_land_tries tries (the airfield and the towns are on the coast: half fell in the sea);
                -- one spread wide (area_km) land or sea as it comes (land_tries, 0)
                local aimed = type(f.area_km) ~= "table" or math.random() < n(f.aim_share, 0)
                local P, what = aimPoint(aimed)
                for _ = 1, aimed and n(f.aim_land_tries, 6) or n(f.land_tries, 0) do
                    if ULY.isLand(P.X, P.Y) ~= false then break end
                    P, what = aimPoint(aimed)
                end
                local x = launch(f, P, what, false)
                if x then U.list[#U.list + 1] = x; U.sent = U.sent + 1; falling = falling + 1 else U.todo = U.todo - 1 end
            end
        end
        if U.bigAt and not U.bigSent and now >= U.bigAt then
            U.bigSent = true
            local b = cfg().big
            local x = launch({ from_km = b.from_km, alt_m = b.alt_m, speed_kmh = b.speed_kmh, mesh = b.mesh, scale = b.scale,
                               spin_dps = b.spin_dps, health = b.health, solo_x = b.solo_x,
                               dive_deg = b.dive_deg, from_deg = b.from_deg, spread_deg = b.spread_deg,    -- (AC:I's 45 degrees)
                               tail_x = b.tail_x },
                             { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = 0 }, "airfield", true)
            if x then U.list[#U.list + 1] = x end
            if hudCallout then hudCallout(cfg().text.big, cfg().text.big_sub) end
            say((cfg().text.say or {}).big)
            if x then newsOne("core") end
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
    newsOff()
    for _, x in ipairs(U.list) do
        fallOff(x)                                                     -- (its fall loop: the code review)
        if not x.done then x.done = true; disarm(x.e); rockOff(x.r) end
    end
    ul(string.format("round %d over: %d of %d fragments shot down, %d landed on the airfield, %d on the town, %d in the sea, %d on open land; %d with no target on them", D.round,
        U.shot, U.sent + (U.bigSent and 1 or 0), U.landedAirfield, U.landedTown, U.landedSea or 0, U.landedOpen or 0, U.unarmed or 0))
    if host() then boxTexts(false) end
    local last = U.phase >= math.max(1, math.floor(n(cfg().rounds, 2)))
    tell("e", last and "1" or "0")
    if last and host() then release("its last round over") end        -- (sv_rounds.lua's clean-up finishes them off)
    if last then
        filmOff(now)
        skyOff()
        ambOff()
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
-- ((2026-11-24, the code review) everything ULYSSES has up taken down, whatever ended it: its last round lost (the fleet's
-- round 30, a spawn refused), a run over mid-round, the level gone (LEVEL_DROPS), a joiner made host mid-round
-- ((2026-11-28) dropped: the level is going (LEVEL_DROPS): its borrowed targets' lists forgotten, none of them touched)
function ULY.endAll(why, dropped)
    local any = U ~= nil or J.on or FILM.on or AMB.h ~= nil or AMB.a ~= nil or #SKYM.list > 0
    newsOff()
    if U then
        for _, x in ipairs(U.list) do
            fallOff(x)
            if not x.done then x.done = true; if not dropped then pcall(disarm, x.e) end; rockOff(x.r) end
        end
        U = nil
    end
    for _, r in pairs(J.rocks) do
        if dropped then r.tgt = nil else pcall(jDisarm, r) end
        fallOff(r)
        rockOff(r)
    end
    J.rocks, J.on, J.hold = {}, false, false
    if dropped then J.settled = {} end
    -- (its targets handed back, the clean-up at once: an end mid-round that the specials' own clean-up won't see)
    pcall(release, why, os.clock(), dropped)
    if host() and BOXED then pcall(boxTexts, false) end
    skyOff()
    ambOff()
    if FILM.on then
        FILM.on, FILM.cur = false, 0
        if HUD and HUD.film then pcall(HUD.film, 0) end
    end
    if any then ul("all taken down: " .. tostring(why)) end
end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["ulysses"] = function() ULY.endAll("the level dropped", true) end end
-- ((2026-11-28) whether ULYSSES still holds its borrowed targets (sv_rounds.lua SPC.cleanUnitsOf: not cleaned up while
-- it does): the host's from its first round's borrow to its last round's end; a joiner's from the host's first round to
-- its last "e"
function ULY.holdsTargets()
    if host() then return HOLD == true end
    return J.hold == true
end
-- ((2026-11-24, the code review) the Spaceport can't come the round before ULYSSES: its retake would fall on ULYSSES' first
-- round (specialFor asks the retake first) and the time shift into 1999 would never play (THE FESTIVAL's guard, the same)
do
    local sk = SPC and SPC.kinds and SPC.kinds.spaceport
    if sk and sk.ready then
        local raw = sk.ready
        sk.ready = function(round, ...)
            if round and ULY.roundIs(round + 1) then return false end
            return raw(round, ...)
        end
    end
end
function ULY.tick(now)
    filmTick(now)
    newsTick(now)
    -- (its look left on with no ULYSSES round in play or next: ended; a joiner made host keeps no host's round)
    if D and (FILM.on or AMB.h or J.on) then
        local s0 = D.special
        local inUly = s0 and s0.kind == "ulysses"
        local nextUly = D.state == "wait" and (ULY.roundIs(D.round + 1) or D.forceSpecial == "ulysses")
        if host() and J.on and not U then ULY.endAll("this game became the host mid-round")
        elseif host() and not inUly and not nextUly and not J.on and (D.state == "fighting" or D.state == "spawning" or D.state == "wait") then
            ULY.endAll("no ULYSSES round in play (round " .. tostring(D.round) .. ")")
        end
    end
    local s = D and D.special
    -- ((2026-11-24, the user: "during the intermission of these two rounds, the fake meteors up in the sky can still
    -- continue to run") the break between its rounds too: still in 1999 (the film look on until its last round's end)
    local on = (s and s.kind == "ulysses" and (D.state == "fighting" or D.state == "spawning")) or J.on
        or (FILM.on and D and D.state == "wait")
    skyClean(now)
    if on then skyTick(now)
    elseif #SKYM.list > 0 and not (U and U.phase) then
        local nextIs = D and ULY.roundIs(D.round + 1)
        if not nextIs then skyOff() end
    end
    if not D and FILM.on then filmOff(now) end
    if not D and AMB.h then ambOff() end
end

-- ---- a joiner: the host's word (sv_coop_migration.lua "ul"); each value checked, as SCOOP.fromHost's ----
local function fin(v, lim) v = tonumber(v); return v ~= nil and v == v and math.abs(v) <= lim end
local KEYS = { A = true, C = true, D = true }
function ULY.fromHost(f)
    if host() or not D then return end
    local k = f[2]
    if k == "r" then
        local ph = tonumber(f[3])
        if not (fin(ph, 10) and ph >= 1 and ph == math.floor(ph)) then return end
        J.on, J.hold = true, true
        ambOn()
        newsStart(ph, nil)
        pcall(jSettle)
        if ph == 1 then
            local sh = cfg().shift or {}
            fade(1, 0, n(sh.fade_s, 1.2) * 2, false)
            if hudCallout then hudCallout(sh.card or "JULY 1999", sh.card_sub) end
        end
        ul(string.format("the host's round: phase %d; the film look %s", ph, filmOn()))
    elseif k == "f" then
        local id, key = f[3], f[4]
        local x, y, z, vx, vy, vz, sc, sp = tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8]), tonumber(f[9]), tonumber(f[10]), tonumber(f[11]), tonumber(f[12])
        if not (KEYS[key] and fin(id, 1e6) and tonumber(id) == math.floor(tonumber(id)) and fin(x, 3e5) and fin(y, 3e5) and fin(z, 6e4) and fin(vx, 5e5) and fin(vy, 5e5)
            and fin(vz, 5e5) and fin(sc, 5000) and sc > 0 and fin(sp, 3600)) then return end
        if J.rocks[id] then jDisarm(J.rocks[id]); rockOff(J.rocks[id]) end
        local tx = n((f[13] == "1" and cfg().big or cfg().fragments).tail_x, 1)     -- (as the host draws it: its own config)
        local r = rock(key, { X = x * 100, Y = y * 100, Z = z * 100 }, { X = vx, Y = vy, Z = vz }, sc / 100, sp, tx)
        if r then
            -- ((2026-11-24, the code review) the core drawn as the host draws it: its own blasts, splash and fall sound)
            r.big = f[13] == "1"
            if r.big then newsOne("core") end                    -- (the host's core: its bulletin here too)
            fallOn(r, r.a, r.big, function() return rockAt(r) end)
            J.rocks[id] = r
            pcall(function() r.a:SetLifeSpan(600) end)
            -- ((2026-11-28) the host's target on it (its co-op id, 0 or none: an older host's, or none free there)
            local tid = tonumber(f[14])
            if tid and fin(tid, 65535) and tid >= 1 and tid == math.floor(tid) then
                pcall(jSettle)
                local okA, done, why = pcall(jArm, r, tid)
                J.armed, J.missed = (J.armed or 0) + ((okA and done) and 1 or 0), (J.missed or 0) + ((okA and done) and 0 or 1)
                if (okA and done and J.armed == 1) or (not (okA and done) and J.missed <= 3) then
                    ul(string.format("the host's fragment %s: its target %d %s", tostring(id), tid,
                        (okA and done) and "on this game's rock (lockable here)" or ("NOT on it: " .. tostring(okA and why or done))))
                end
            end
        end
    elseif k == "s" or k == "l" then
        local r = J.rocks[f[3]]
        if not r then return end
        J.rocks[f[3]] = nil
        jDisarm(r)
        local at = rockAt(r)
        local fx = cfg().fx_scale or {}
        if at then
            if r.big then newsOne(k == "s" and "core_down" or "core_hit") end
            if k == "s" then boom(at, n(r.big and fx.big_shot or fx.shot, 4))
            elseif f[4] == "1" then boom(at, n(r.big and fx.big_land or fx.land, 10), true); landSound("ground", at)
            else
                local sc = cfg().sea or {}
                local W = { X = at.X, Y = at.Y, Z = n(sc.sea_z, 350) }
                if fxAt then pcall(fxAt, sc.fx or {}, W, n(r.big and sc.big_scale or sc.scale, 1.5), 20) end
                landSound("sea", W)                           -- (the splash heard as the host hears it)
            end
        end
        fallOff(r)
        rockOff(r)
    elseif k == "e" then
        newsOff()
        for _, r in pairs(J.rocks) do
            jDisarm(r)
            fallOff(r)
            rockOff(r)
        end
        J.rocks = {}
        J.on = false
        if f[3] == "1" then J.hold = false end
        if (J.armed or 0) + (J.missed or 0) > 0 then
            ul(string.format("the host's round over: %d of its fragments' targets put on this game's rocks, %d not", J.armed or 0, J.missed or 0))
        end
        J.armed, J.missed = 0, 0
        if f[3] == "1" then
            filmOff(os.clock())
            skyOff()
            ambOff()
            local sh = cfg().shift or {}
            fade(1, 0, n(sh.fade_s, 1.2) * 2, false)
            if hudCallout then hudCallout(sh.home or "PRESENT DAY", sh.home_sub) end
        end
        ul("the host's round over" .. (f[3] == "1" and ": home again" or ""))
    end
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
-- ((2026-11-24, the user: "Shouldn't their smoke trail be thicker") the autotest's trail line-up: one rock a candidate
ULY.testRock = function(key, at, vel, scale, trails, look, tailX) return rock(key, at, vel, scale, 20, tailX or 1, trails, look) end
ULY.testRockOff = function(r) rockOff(r) end
-- ((2026-11-24, the user: "get the wwise sounds working for the meteorites") the autotest's sound line-up: each of its
-- Wwise sounds at a place / on an actor, and stopped, as the round plays them (kind: fall / fall_big / boom / encounter /
-- ambient) -> whether Wwise took it
ULY.testSoundAt = function(kind, at) return wwAt(kind, at) end
ULY.testSoundOn = function(kind, a) return wwOn(kind, a) end
ULY.testSoundOff = function(a) wwOff(a) end
ULY.testSoundComps = function(a) return wwComps(a) end
ULY.testSpear = function(kind, at) return spearAt(kind, at) end
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
