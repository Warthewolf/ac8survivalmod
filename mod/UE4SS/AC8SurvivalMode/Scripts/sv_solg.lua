-- sv_solg.lua : the SOLG, VALKA's last move (the user, 2026-11-22: "When Valka reaches 20% health ... Valka Calls in
-- the SOLG. The SOLG spawns at high altitude out of another Portal ... and begins to travel towards the space centre";
-- "the SOLG cannot use any boss from the game it needs to be it's own custom thing"; docs/re/SOLG.md). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order: a name another part uses is a
-- global of this mod's Lua state, its own helpers stay local.
-- This piece: the SOLG's own body, no game unit under it: an actor of ours whose root is AC:I's SOLG as our skeletal
-- mesh (tools/solg: SK_SV_SOLG, a bone per piece and its wreck <bone>_W, RING_1 / RING_2 carrying their pieces),
-- painted on the x40a's gear material (VALKA's paint: AC8's own material, hard rule 58), playing AC:I's own ring spin
-- (A_SV_SOLG_Spin: tools/solg/kfm1.py decoded AC:I's `auta` clips), flown by the engine's ProjectileMovementComponent
-- (smooth every frame). A solar array wing shot off: hidden on the body, its own mesh (SK_SV_SOLG_SAW4 / 5, its wreck
-- shown) falling away under gravity, tumbling (a RotatingMovementComponent): AC:I has no animation for that (its
-- cutscenes are the arrival, the panels fixed), so the engine's motion does it.
-- Log: `solg: ...`; every spawn step is a crash breadcrumb (crumb()).
SOLG = { C = {
    mesh = "/Game/Mods/SurvivalMode/SOLG/Model/SK_SV_SOLG",
    spin = "/Game/Mods/SurvivalMode/SOLG/Model/A_SV_SOLG_Spin",
    panels = { SG04 = "/Game/Mods/SurvivalMode/SOLG/Model/SK_SV_SOLG_SAW4", SG05 = "/Game/Mods/SurvivalMode/SOLG/Model/SK_SV_SOLG_SAW5" },
    -- ((2026-11-22) the user: "Each of its autoloaders falls off after each has had all of its targets destroyed") an arm
    -- (SG01_01..04) with its 8 MAG panels and 9 KEW shells (the targets nearest it): when the last is down it breaks
    -- off, this mesh (the arm and its pieces' wrecks: tools/solg/prepare.py) falling in its place
    arm = "/Game/Mods/SurvivalMode/SOLG/Model/SK_SV_SOLG_ARM", arms = { "SG01_01", "SG01_02", "SG01_03", "SG01_04" },
    arm_keys = { KEW = true }, arm_riders = { MAG = true },   -- (Gould: an arm waits for its 9 KEW shells alone)
    tex = "/Game/Mods/SurvivalMode/SOLG/Textures/T_SV_SOLG_",
    paint = { parent = "/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear",
              tex = { Livemap = "rt:0,0.75,1", Normalmap = "/Engine/EngineMaterials/DefaultNormal",
                      Detail_Normal = "/Engine/EngineMaterials/DefaultNormal",
                      Blend_Dameged_Normalmap = "/Engine/EngineMaterials/DefaultNormal" },
              scalars = { Ctrl_All_Emissive = 0, Turbine_speed = 0, NormalIntencity = 0, DNormal_Strength = 0,
                          DamegedNormal_Intencity = 0, PlayerPlane_Damage = 0 } },
    spin_rate = 1.0,                        -- the spin animation's play rate (1: AC:I's, a ring's turn in 40 s)
    -- a wing shot off: pushed out from the barrel (m/s), down (m/s), its tumble (deg/s, each axis up to), gone after
    fall = { out_mps = 35, down_mps = 15, tumble_dps = 40, gravity = 1.0, life_s = 30, body_gravity = 0.35, body_tumble_dps = 4 },
    -- its targets (docs/re/SOLG.md 5: AC:I's types, counts and health): each type a unit of ours on AC8's GENERIC
    -- destructible base (tools/survival_events_specials.py SOLG_*: Mission 4's radar tower ported, no boss), its objects
    -- held on the SOLG's bones (its own mesh hidden: you see the SOLG's piece), their health AC:I's x health_x, held at
    -- floor HP so the game never breaks one its own way (a radar tower's wreck in the sky): at the floor the SOLG breaks
    -- it (the piece hidden, its wreck shown, a wing falling, an explosion, pay). AC:I's phases: 1 the wings (SAW) and
    -- the MAG panels, 2 the KEW shells, 3 the core units, 4 the SP shell; a phase's targets are lockable only then.
    targets = {
        { key = "SAW", unit = "SV_Unit_SOLG_SAW", phase = 1, health = 900, pay = 40, bones = { "SG04_%02d", 6, "SG05_%02d", 12 } },
        { key = "MAG", unit = "SV_Unit_SOLG_MAG", phase = 1, health = 600, pay = 25, bones = { "SG07_%02d", 32 } },
        { key = "KEW", unit = "SV_Unit_SOLG_KEW", phase = 2, health = 1000, pay = 50, bones = { "KEW_%02d", 36 } },
        { key = "CORE", unit = "SV_Unit_SOLG_CORE", phase = 3, health = 1500, pay = 200, bones = { "SG03_%02d", 4 } },
        { key = "SP", unit = "SV_Unit_SOLG_SP", phase = 4, health = 2500, pay = 800, bones = { "CORE_%02d", 1 } },
        -- ((2026-11-22) its laser turrets (AC:I's f_111t, CONT_LASER UNIT, 850: tools/solg/lasers.py), on AC8's land
        -- Phalanx firing our own laser (BP_SV_SolgTLS, 5 a hit: tools/build_survival_solg.py): up with their phase
        -- (the arms' with the KEW shells, the barrel's with the core units, as AC:I's TLS), shot down for pay, never
        -- needed for the next phase (`optional`); an arm's go down with it
        { key = "LSRA", unit = "SV_Unit_SOLG_LSRA", phase = 2, health = 850, pay = 60, bones = { "LSR_%02d", 16 },
          optional = true, laser = true },
        -- ((2026-11-22) SOLG -Gould-'s rules, AC:I's DATA92 529, docs/re/SOLG.md 13: the barrel's tail 4 with the arms',
        -- its front 8 with the core units (Gould's sweep in its fighters' phase, cut here: the user, "SOLG pieces only"))
        { key = "LSRB", unit = "SV_Unit_SOLG_LSRB", phase = 2, health = 850, pay = 60, bones = { "LSR_%02d", 4, 25 },
          optional = true, laser = true },
        { key = "LSRC", unit = "SV_Unit_SOLG_LSRC", phase = 3, health = 850, pay = 60, bones = { "LSR_%02d", 8, 17 },
          optional = true, laser = true },
    },
    -- ((2026-11-22) the user: "SOLG -Gould- is the one we want", "Follow Gould exactly" (no aircraft phases)) Gould's
    -- rules (docs/re/SOLG.md 13): phase 1 needs 16 MAG panels (mag_required, 4 an arm), each arm's other 4 open once
    -- its 4 are down and are optional; each row of 3 wings opens from its third: wait_for (bone -> the bone that must
    -- be down first); a pause after each phase (pause_s, by the phase just done) before the next one's targets open
    mag_required = { 1, 2, 5, 6, 11, 12, 13, 14, 19, 20, 21, 22, 29, 30, 31, 32 },
    wing_rows = { { "SG04_%02d", 1 }, { "SG04_%02d", 4 }, { "SG05_%02d", 1 }, { "SG05_%02d", 4 }, { "SG05_%02d", 7 }, { "SG05_%02d", 10 } },
    pause_s = { [1] = 15, [2] = 15, [3] = 30 },
    fcs_table = "/Game/Mods/SurvivalMode/Data/DT_SV_SolgFCS.DT_SV_SolgFCS", fcs_row = "SV_FCS_SolgTLS",
    laser_model_row = "SV_Model_SOLG_LSR",
    -- their boxes: "SOLG" over each type's AC:I name (texts by key: tools/survival_events_specials.py SOLG_*)
    model_row = "SV_Model_SOLG", name_key = "SV_SOLG_Name", name = "SOLG",
    names = { SAW = "SOLAR ARRAY WING", MAG = "MAG PANEL", KEW = "KEW SHELL", CORE = "CORE UNIT", SP = "SP SHELL",
              LSRA = "LASER UNIT", LSRB = "LASER UNIT", LSRC = "LASER UNIT" },
    health_x = 0.25,                        -- (AC:I's health is a 4-player raid's: a first guess, every hit logged)
    floor = 1,                              -- a live target's HP floor: it breaks there
    fx = { "/Game/VFX/Environment/Common/Explosion/AirExplosion/NS_airExplosionA/NS_airExplosionA_M" },
    fx_scale = { SAW = 3, MAG = 2, KEW = 3, CORE = 5, SP = 8, SOLG = 12, ARM = 6, LSRA = 2, LSRB = 2, LSRC = 2 },
} }
do
local S = nil                                             -- the SOLG up: { actor, body, move, panels = {...} }
local function step(s) if crumb then crumb("solg: " .. s) end end
local function sl(s) log("solg: " .. s) end
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function obj(path) return loadObject(path .. "." .. path:match("[^/]+$")) end

local function newActor(at, yaw)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local cls = StaticFindObject("/Script/Engine.Actor")
    if not (valid(gs) and valid(cls) and liveObj(survivalPC)) then return nil end
    local h = math.rad(yaw or 0) / 2
    local t = { Rotation = { X = 0, Y = 0, Z = math.sin(h), W = math.cos(h) }, Translation = { X = at.X, Y = at.Y, Z = at.Z },
                Scale3D = { X = 1, Y = 1, Z = 1 } }
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
local flat = {}
local function flatTex(spec)                              -- "rt:R,G,B": a 4x4 render target of that colour
    if flat[spec] and valid(flat[spec]) then return flat[spec] end
    local r, g, b = spec:match("^rt:([%d%.]+),([%d%.]+),([%d%.]+)$")
    local krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    if not r or not valid(krl) then return nil end
    local col = { R = tonumber(r), G = tonumber(g), B = tonumber(b), A = 1 }
    local ok, rt = pcall(function() return krl:CreateRenderTarget2D(survivalPC, 4, 4, 2, col, false, false) end)
    if not (ok and valid(rt)) then return nil end
    pcall(function() krl:ClearRenderTarget2D(survivalPC, rt, col) end)
    flat[spec] = rt
    return rt
end
-- each slot (its cooked MI_SV_SOLG_<id>) on an instance of the x40a's gear material with that texture
local function paint(comp)
    local P = SOLG.C.paint
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local parent = obj(P.parent)
    if not (valid(parent) and valid(kml)) then return "NOT painted (no parent)" end
    local shared = {}
    for slot, path in pairs(P.tex) do shared[slot] = path:sub(1, 3) == "rt:" and flatTex(path) or obj(path) end
    local nn, slots, bad = 0, 0, {}
    pcall(function() slots = comp:GetNumMaterials() end)
    for i = 0, slots - 1 do
        local okG, m = pcall(function() return comp:GetMaterial(i) end)
        local id = okG and valid(m) and (nameOf(m):match("MI_SV_SOLG_(%x+)") or nil)
        local tex = id and obj(SOLG.C.tex .. id)
        local okM, mid = false, nil
        if valid(tex) then okM, mid = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, parent, FName("None"), 0) end) end
        if okM and valid(mid) then
            pcall(function() mid:SetTextureParameterValue(FName("Basecolor"), tex) end)
            for slot, t in pairs(shared) do if valid(t) then pcall(function() mid:SetTextureParameterValue(FName(slot), t) end) end end
            for k, v in pairs(P.scalars or {}) do pcall(function() mid:SetScalarParameterValue(FName(k), v) end) end
            if pcall(function() comp:SetMaterial(i, mid) end) then nn = nn + 1 end
        else
            bad[#bad + 1] = tostring(id or i)
        end
    end
    return string.format("%d of %d slots painted%s", nn, slots, #bad > 0 and (" (NOT: " .. table.concat(bad, " ") .. ")") or "")
end
-- an engine mover on actor a (its root): velocity (cm/s), gravity scale
local function mover(a, vel, gravity)
    local pm = addComp(a, "/Script/Engine.ProjectileMovementComponent")
    if not pm then return nil end
    pcall(function() pm:SetUpdatedComponent(a.RootComponent) end)
    pcall(function() pm.ProjectileGravityScale = gravity or 0 end)
    pcall(function() pm.bRotationFollowsVelocity = false end)
    pcall(function() pm.bShouldBounce = false end)
    pcall(function() pm.MaxSpeed = 0 end)                -- (no limit)
    pcall(function() pm.Velocity = { X = vel.X, Y = vel.Y, Z = vel.Z } end)
    pcall(function() pm:SetVelocityInLocalSpace(pm.Velocity) end)  -- (harmless if the world one took)
    pcall(function() pm.Velocity = { X = vel.X, Y = vel.Y, Z = vel.Z } end)
    return pm
end
local function boneAt(comp, bone)
    local okL, L = pcall(function() local v = comp:GetSocketLocation(FName(bone)); return { X = v.X, Y = v.Y, Z = v.Z } end)
    local okR, R = pcall(function() local r = comp:GetSocketRotation(FName(bone)); return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end)
    return okL and L or nil, okR and R or nil
end

-- the SOLG up at `at` (cm), its nose to `yaw`, flying vel (cm/s); true if it came up
function SOLG.spawn(at, yaw, vel)
    SOLG.stop("a new one")
    step("loading SK_SV_SOLG")
    local sk = obj(SOLG.C.mesh)
    if not valid(sk) then sl("SK_SV_SOLG not loaded: is SurvivalMode_SOLG_P installed?"); return false end
    step("its actor")
    local a = newActor(at, yaw)
    if not a then sl("no actor"); return false end
    step("its skeletal mesh")
    local body = addComp(a, "/Script/Engine.SkeletalMeshComponent")
    if not body then sl("no SkeletalMeshComponent"); pcall(function() a:K2_DestroyActor() end); return false end
    pcall(function() body:SetCollisionEnabled(0) end)
    pcall(function() body:SetCastShadow(false) end)
    local okM = pcall(function() body:SetSkeletalMeshAsset(sk) end) or pcall(function() body:SetSkeletalMesh(sk, true) end)
    -- ((2026-11-22, run 17:58) a bare actor has no root: its spawn place went with the first component, the SOLG lay at the
    -- world's origin on the sea. Put where it's wanted once its mesh is its root)
    pcall(function() a:K2_SetActorLocationAndRotation({ X = at.X, Y = at.Y, Z = at.Z }, { Pitch = 0, Yaw = yaw or 0, Roll = 0 }, false, {}, true) end)
    step("painting")
    local painted = paint(body)
    step("hiding its wrecks")
    local hid = 0
    pcall(function()
        local nb = body:GetNumBones()
        for i = 0, nb - 1 do
            local bn = body:GetBoneName(i):ToString()
            if bn:match("_W$") and pcall(function() body:HideBoneByName(FName(bn), 0) end) then hid = hid + 1 end
        end
    end)
    step("its spin")
    local anim = obj(SOLG.C.spin)
    local spun = valid(anim) and pcall(function() body:PlayAnimation(anim, true) end)
    if spun then pcall(function() body:SetPlayRate(n(SOLG.C.spin_rate, 1)) end) end
    step("its mover")
    local mv = vel and mover(a, vel, 0) or nil
    S = { actor = a, body = body, move = mv, panels = {}, at0 = at, yaw = yaw, broken = {} }
    sl(string.format("up at (%.1f, %.1f) km, %.1f km up, nose %.0f deg: mesh %s, %s, %d wrecks hidden, spin %s, mover %s",
        at.X / 100000, at.Y / 100000, at.Z / 100000, yaw or 0, okM and "on" or "NOT set", painted, hid,
        spun and "playing" or (valid(anim) and "NOT played" or "NOT loaded"), mv and "on" or (vel and "NOT made" or "none")))
    return true
end
function SOLG.up() return S ~= nil and liveObj(S.actor) end
function SOLG.where() if S and liveObj(S.actor) then local ok, L = pcall(function() return S.actor:K2_GetActorLocation() end); return ok and L or nil end end
-- one solar array wing (SG04_nn / SG05_nn) shot off: hidden on the body, its own mesh falls away tumbling
function SOLG.breakPanel(bone)
    if not (S and liveObj(S.body)) or S.broken[bone] then return false end
    local kind = bone:match("^(SG0[45])_")
    local path = kind and SOLG.C.panels[kind]
    local L, R = boneAt(S.body, bone)
    if not (path and L and R) then sl("break " .. bone .. ": not a panel, or its bone not found"); return false end
    S.broken[bone] = true
    pcall(function() S.body:HideBoneByName(FName(bone), 0) end)
    local sk = obj(path)
    local a = valid(sk) and newActor(L, R.Yaw) or nil
    local c = a and addComp(a, "/Script/Engine.SkeletalMeshComponent")
    if not c then sl("break " .. bone .. ": its falling mesh NOT made"); return false end
    pcall(function() c:SetCollisionEnabled(0) end)
    pcall(function() c:SetSkeletalMeshAsset(sk) end)
    pcall(function() a:K2_SetActorLocationAndRotation(L, R, false, {}, true) end)   -- (its root now: run 17:58)
    paint(c)
    pcall(function() c:HideBoneByName(FName("PANEL"), 0) end)   -- (its wreck falls)
    -- its push: away from the barrel (the body's axis through its middle), down, and the body's own velocity
    local B = SOLG.where() or L
    local f = SOLG.C.fall
    local ox, oy, oz = L.X - B.X, L.Y - B.Y, L.Z - B.Z
    local okF, F = pcall(function() local v = S.actor:GetActorForwardVector(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if okF and F then local d = ox * F.X + oy * F.Y + oz * F.Z; ox, oy, oz = ox - F.X * d, oy - F.Y * d, oz - F.Z * d end
    local len = math.max(1, math.sqrt(ox * ox + oy * oy + oz * oz))
    local bv = { X = 0, Y = 0, Z = 0 }
    pcall(function() local v = S.move.Velocity; bv = { X = v.X, Y = v.Y, Z = v.Z } end)
    local out, down = n(f.out_mps, 35) * 100, n(f.down_mps, 15) * 100
    local vel = { X = bv.X + ox / len * out, Y = bv.Y + oy / len * out, Z = bv.Z + oz / len * out - down }
    local pm = mover(a, vel, n(f.gravity, 1))
    local rot = addComp(a, "/Script/Engine.RotatingMovementComponent")
    local t = n(f.tumble_dps, 40)
    if rot then
        pcall(function() rot.RotationRate = { Pitch = (math.random() * 2 - 1) * t, Yaw = (math.random() * 2 - 1) * t, Roll = (math.random() * 2 - 1) * t } end)
    end
    S.panels[#S.panels + 1] = { actor = a, gone = os.clock() + n(f.life_s, 30) }
    sl(string.format("%s shot off: falling (%s, tumble %s)", bone, pm and "a mover" or "NO mover", rot and "on" or "off"))
    return true
end
-- destroyed: the whole of it falls, slowly turning over (gravity on its mover, a tumble)
function SOLG.fall()
    if not (S and liveObj(S.actor)) or S.falling then return false end
    S.falling = true
    local f = SOLG.C.fall
    if S.move then pcall(function() S.move.ProjectileGravityScale = n(f.body_gravity, 0.35) end) end
    local rot = addComp(S.actor, "/Script/Engine.RotatingMovementComponent")
    local t = n(f.body_tumble_dps, 4)
    if rot then pcall(function() rot.RotationRate = { Pitch = t, Yaw = t * 0.3, Roll = t * 0.6 } end) end
    pcall(function() S.body:SetPlayRate(0.2) end)       -- (its rings winding down)
    sl("falling (gravity " .. (S.move and "on" or "NO mover") .. ", tumble " .. (rot and "on" or "off") .. ")")
    return true
end
-- an arm broken off (all its targets down): hidden on the body with every piece on it, its own mesh falls away
function SOLG.breakArm(armBone, pieces)
    if not (S and liveObj(S.body)) or S.broken[armBone] then return false end
    local L, R = boneAt(S.body, armBone)
    if not (L and R) then sl("break " .. armBone .. ": its bone not found"); return false end
    S.broken[armBone] = true
    for _, b in ipairs({ armBone, armBone .. "_W" }) do pcall(function() S.body:HideBoneByName(FName(b), 0) end) end
    for _, b in ipairs(pieces or {}) do
        pcall(function() S.body:HideBoneByName(FName(b), 0) end)
        pcall(function() S.body:HideBoneByName(FName(b .. "_W"), 0) end)
    end
    local sk = obj(SOLG.C.arm)
    local a = valid(sk) and newActor(L, R.Yaw) or nil
    local c = a and addComp(a, "/Script/Engine.SkeletalMeshComponent")
    if not c then sl("break " .. armBone .. ": its falling mesh NOT made"); return false end
    pcall(function() c:SetCollisionEnabled(0) end)
    pcall(function() c:SetSkeletalMeshAsset(sk) end)
    pcall(function() a:K2_SetActorLocationAndRotation(L, R, false, {}, true) end)
    paint(c)
    pcall(function() c:HideBoneByName(FName("ARM"), 0) end)      -- (its wreck falls, its pieces' wrecks on it)
    for k = 13, 16 do pcall(function() c:HideBoneByName(FName(string.format("P_LSR_%02d", k)), 0) end) end   -- (its lasers: down)
    local B = SOLG.where() or L
    local f = SOLG.C.fall
    local ox, oy, oz = L.X - B.X, L.Y - B.Y, L.Z - B.Z
    local okF, F = pcall(function() local v = S.actor:GetActorForwardVector(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if okF and F then local d = ox * F.X + oy * F.Y + oz * F.Z; ox, oy, oz = ox - F.X * d, oy - F.Y * d, oz - F.Z * d end
    local len = math.max(1, math.sqrt(ox * ox + oy * oy + oz * oz))
    local bv = { X = 0, Y = 0, Z = 0 }
    pcall(function() local v = S.move.Velocity; bv = { X = v.X, Y = v.Y, Z = v.Z } end)
    local out, down = n(f.out_mps, 35) * 100 * 0.6, n(f.down_mps, 15) * 100
    local pm = mover(a, { X = bv.X + ox / len * out, Y = bv.Y + oy / len * out, Z = bv.Z + oz / len * out - down }, n(f.gravity, 1))
    local rot = addComp(a, "/Script/Engine.RotatingMovementComponent")
    local t = n(f.tumble_dps, 40) * 0.3
    if rot then pcall(function() rot.RotationRate = { Pitch = (math.random() * 2 - 1) * t, Yaw = (math.random() * 2 - 1) * t, Roll = (math.random() * 2 - 1) * t } end) end
    S.panels[#S.panels + 1] = { actor = a, gone = os.clock() + n(f.life_s, 30) * 1.5 }
    if fxAt then pcall(fxAt, SOLG.C.fx, L, n(SOLG.C.fx_scale.ARM, 6), 8) end
    sl(string.format("%s broken off with its %d pieces: falling (%s, tumble %s)", armBone, #(pieces or {}), pm and "a mover" or "NO mover", rot and "on" or "off"))
    return true
end
-- where the k-th falling wing is now (the tests' cameras)
function SOLG.panelAt(k)
    local p = S and S.panels[k or 1]
    if not (p and liveObj(p.actor)) then return nil end
    local ok, L = pcall(function() local v = p.actor:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    return ok and L or nil
end
function SOLG.stop(why)
    if not S then return end
    if S.targets and not S.mirror then                    -- (a joiner's are the host's copies: co-op takes them down)
        for _, t in ipairs(SOLG.C.targets) do
            if SPC and SPC.cleanUp then pcall(SPC.cleanUp, { t.unit }, "the SOLG gone", true, os.clock()) end
        end
    end
    for _, p in ipairs(S.panels) do if liveObj(p.actor) then pcall(function() p.actor:K2_DestroyActor() end) end end
    if liveObj(S.actor) then pcall(function() S.actor:K2_DestroyActor() end) end
    sl("taken down (" .. tostring(why) .. ")")
    S = nil
end
function SOLG.tick(now)
    if not S then return end
    if (levelTorn and levelTorn()) or not D then S = nil; return end
    if SOLG.targetsTick then pcall(SOLG.targetsTick) end
    if S and S.pauseUntil and os.clock() >= S.pauseUntil then
        local ph = S.pauseNext
        S.pauseUntil, S.pauseNext = nil, nil
        if ph and SOLG.phaseOn then pcall(SOLG.phaseOn, ph) end
    end
    local clock = os.clock()
    for i = #S.panels, 1, -1 do
        local p = S.panels[i]
        if clock >= p.gone or not liveObj(p.actor) then
            if liveObj(p.actor) then pcall(function() p.actor:K2_DestroyActor() end) end
            table.remove(S.panels, i)
        end
    end
end
-- ---- its targets ----
-- at the main menu (sv_rows.lua): its model row into DT_NPC_Model, each type's row into DT_NPC, their names
function SOLG.rowsIn(npc, mine)
    local C = SOLG.C
    local mt, mr = loadObject(ACE.model_table), loadObject(ACE.model_rows)
    if not (mt and mr and npc and mine) then return "the tables didn't load" end
    for _, t in ipairs({ mt, mr }) do pin(t, nameOf(t)) end
    local have = true
    for _, m in ipairs({ C.model_row, C.laser_model_row }) do
        local _, h = dtCall(mt, "FindRow", m)
        if h == nil then
            local _, r = dtCall(mr, "FindRow", m)
            if r ~= nil then dtCall(mt, "AddRow", m, r); _, h = dtCall(mt, "FindRow", m) end
        end
        if h == nil then have = nil end
    end
    -- the lasers' fire-control row (passed on whole: its soft class never read, hard rule 29)
    local fcsT, mineF = loadObject(FCS_TABLE), loadObject(C.fcs_table)
    local fcsIn = false
    if fcsT and mineF then
        for _, t in ipairs({ fcsT, mineF }) do pin(t, nameOf(t)) end
        local _, f = dtCall(fcsT, "FindRow", C.fcs_row)
        if f == nil then
            local _, r = dtCall(mineF, "FindRow", C.fcs_row)
            if r ~= nil then dtCall(fcsT, "AddRow", C.fcs_row, r); _, f = dtCall(fcsT, "FindRow", C.fcs_row) end
        end
        fcsIn = f ~= nil
    end
    local nIn = 0
    for _, t in ipairs(C.targets) do
        local row = "SV_SOLG_" .. t.key
        local _, h = dtCall(npc, "FindRow", row)
        if h == nil then
            local _, r = dtCall(mine, "FindRow", row)
            if r ~= nil then dtCall(npc, "AddRow", row, r); _, h = dtCall(npc, "FindRow", row) end
        end
        if h ~= nil then nIn = nIn + 1 end
        if type(SV_SetText) == "function" then SV_SetText("SV_SOLG_Sub_" .. t.key, C.names[t.key] or t.key) end
    end
    if type(SV_SetText) == "function" then SV_SetText(C.name_key, C.name) end
    return string.format("model rows %s, %d of %d target rows in, the lasers' fire control %s %s", have ~= nil and "in" or "NOT in",
        nIn, #C.targets, C.fcs_row, fcsIn and "in DT_NPC_FCS" or "NOT in (they won't fire)")
end
local FLAGS_ON = { bShowHUDBox = true, bIsNotLockonTarget = false, bIsNotFCSTargets = false, bIsInvincible = false }
local FLAGS_OFF = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }
local CAPTURE = nil                                       -- the objects SV_Spawn makes while it runs
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    if CAPTURE and #CAPTURE < 200 then CAPTURE[#CAPTURE + 1] = o end
end)
local function flags(o, f) for k, v in pairs(f) do pcall(function() o[k] = v end) end end
-- the base's own meshes off (its box and lock stay). ((2026-11-22) the user: "I don't see any of the red laser beams":
-- a laser turret's meshes only, never what's attached to them (`deep` false: its muzzle's laser fires from there);
-- SOLG.C.laser_hide = false: the Phalanx shown, for a look)
local function hideOwn(o, deep)
    local nh = 0
    if deep == nil then deep = true end
    -- ((0.75.12's pictures: the Phalanx's turret showed) its TurretPoseableMesh too (a PoseableMesh, not a SkeletalMesh)
    for _, cls in ipairs({ "/Script/Engine.StaticMeshComponent", "/Script/Engine.SkeletalMeshComponent", "/Script/Engine.PoseableMeshComponent" }) do
        local c = StaticFindObject(cls)
        local ok, list = pcall(function() return o:K2_GetComponentsByClass(c) end)
        if ok and list then
            pcall(function() list:ForEach(function(_, e) local m = e:get(); if pcall(function() m:SetVisibility(false, deep) end) then nh = nh + 1 end end) end)
        end
    end
    return nh
end
local function bonesOf(t)
    local out, b = {}, t.bones
    local i = 1
    while i <= #b do
        local from = type(b[i + 2]) == "number" and b[i + 2] or 1   -- ({ fmt, count[, first] } ...)
        for k = from, from + b[i + 1] - 1 do out[#out + 1] = string.format(b[i], k) end
        i = i + (type(b[i + 2]) == "number" and 3 or 2)
    end
    return out
end
-- one target type's unit up, its objects on their bones: how many, its note
local breakTarget                                         -- (below; openUp's and phaseOn's too)
-- type t's objects (in the order they were made) onto its bones; mirror: a co-op joiner's copies of the host's (their
-- health the host's, held by co-op: never set here)
local function placeAll(t, got, on, mirror)
    local bones = bonesOf(t)
    local hp = n(t.health, 1000) * n(SOLG.C.health_x, 0.25)
    local placed = 0
    for k, o in ipairs(got) do
        local bone = bones[k]
        if bone and valid(o) then
            local att = pcall(function() o:K2_AttachToComponent(S.body, FName(bone), 2, 2, 1, false) end)
            if not mirror then
                pcall(function() o.MaxHealth = hp; o.HealthInternal = math.floor(hp * 10 + 0.5) end)
                pcall(function() o.MinHealth = n(SOLG.C.floor, 1) end)
            end
            if not t.laser then hideOwn(o) elseif SOLG.C.laser_hide ~= false then hideOwn(o, false) end
            flags(o, on and FLAGS_ON or FLAGS_OFF)
            S.targets[#S.targets + 1] = { o = o, a = addrOf(o), key = t.key, bone = bone, t = t, hp = hp, attached = att, live = true }
            placed = placed + 1
        end
    end
    return placed, #bones
end
local function typeUp(t, on)
        CAPTURE = {}
        spawningUnit = t.unit
        local r = SV_Spawn(t.unit, S.at0.X, S.at0.Y, S.at0.Z, 0)
        spawningUnit = nil
        local got = CAPTURE
        CAPTURE = nil
        local placed, nb = placeAll(t, got, on, false)
        return placed, string.format("%s %d of %d (%s)", t.key, placed, nb, r > 0 and (r .. " up") or (SV_ERR and SV_ERR[r] or tostring(r)))
end
-- each arm-borne target's arm: the nearest arm bone (they sit along it); lasers on .onArm (they don't hold it up)
local function armsOf(list)
    local armAt = {}
    for _, ab in ipairs(SOLG.C.arms or {}) do armAt[ab] = boneAt(S.body, ab) end
    for _, e in ipairs(list) do
        if (SOLG.C.arm_keys or {})[e.key] or e.t.laser or (SOLG.C.arm_riders or {})[e.key] then
            local L, best, bd = boneAt(S.body, e.bone), nil, nil
            for ab, A in pairs(armAt) do
                if L and A then
                    local d = (L.X - A.X) ^ 2 + (L.Y - A.Y) ^ 2 + (L.Z - A.Z) ^ 2
                    if not bd or d < bd then best, bd = ab, d end
                end
            end
            if best and bd < (400 * 100) ^ 2 then                  -- (the barrel's lasers: on no arm)
                if (SOLG.C.arm_keys or {})[e.key] then e.arm = best else e.onArm = best end
            end
        end
    end
end
-- every target type's unit up (the lasers' with their phase), its objects on their bones; the first phase's lockable
-- (Gould) a target's own rules: optional MAG panels, its wait (bones that must be down first)
local function gouldRules()
    local C = SOLG.C
    local req, byBone = {}, {}
    for _, k in ipairs(C.mag_required or {}) do req[string.format("SG07_%02d", k)] = true end
    for _, e in ipairs(S.targets) do byBone[e.bone] = e end
    for _, row in ipairs(C.wing_rows or {}) do      -- (its third opens first, then its second, then its first)
        local a, b, c = string.format(row[1], row[2]), string.format(row[1], row[2] + 1), string.format(row[1], row[2] + 2)
        if byBone[b] then byBone[b].wait = { c } end
        if byBone[a] then byBone[a].wait = { b } end
    end
    if next(req) then
        local reqOnArm = {}
        for _, e in ipairs(S.targets) do
            if e.key == "MAG" and req[e.bone] and e.onArm then reqOnArm[e.onArm] = reqOnArm[e.onArm] or {}; table.insert(reqOnArm[e.onArm], e.bone) end
        end
        for _, e in ipairs(S.targets) do
            if e.key == "MAG" and not req[e.bone] then e.optional, e.wait = true, reqOnArm[e.onArm or ""] or {} end
        end
    end
end
local function waitDone(e)
    for _, b in ipairs(e.wait or {}) do
        for _, x in ipairs(S.targets) do if x.bone == b and x.live then return false end end
    end
    return true
end
-- the open ones (their phase on, their wait done) lockable; how many newly
local function openUp()
    local n0 = 0
    for _, e in ipairs(S.targets) do
        if e.live and S.lateBroken and S.lateBroken[e.bone] then S.lateBroken[e.bone] = nil; breakTarget(e, "the host's") end
        if e.live and not e.open and e.t.phase <= (S.phase or 0) and not S.pauseUntil and waitDone(e) and liveObj(e.o) then
            e.open = true; flags(e.o, FLAGS_ON); n0 = n0 + 1
        end
    end
    return n0
end
function SOLG.targetsUp()
    if not (S and liveObj(S.body)) then return 0 end
    S.targets, S.phase = {}, 1
    local total, said = 0, {}
    for _, t in ipairs(SOLG.C.targets) do
        if not t.laser then
            local placed, note = typeUp(t, false)
            total = total + placed
            said[#said + 1] = note
        end
    end
    local att = 0
    for _, e in ipairs(S.targets) do if e.attached then att = att + 1 end end
    armsOf(S.targets)
    gouldRules()
    local opened = openUp()
    local perArm = {}
    for _, e in ipairs(S.targets) do if e.arm then perArm[e.arm] = (perArm[e.arm] or 0) + 1 end end
    local pa = {}
    for _, ab in ipairs(SOLG.C.arms or {}) do pa[#pa + 1] = ab .. " " .. (perArm[ab] or 0) end
    local nOpt = 0
    for _, e in ipairs(S.targets) do if e.optional and not e.t.optional then nOpt = nOpt + 1 end end
    sl(string.format("targets up: %s; %d attached to their bones, %d held by hand; phase 1, %d open (%d MAG optional); on the arms: %s",
        table.concat(said, ", "), att, total - att, opened, nOpt, table.concat(pa, ", ")))
    return total
end
local function phaseOn(ph)
    S.phase = ph
    for _, t in ipairs(SOLG.C.targets) do                 -- (its lasers up now: they fire from now on)
        if t.laser and t.phase == ph and S.mirror then    -- (a joiner: the host's copies, adopted as they come)
            S.pend = S.pend or {}
            S.pend[t.key] = os.clock() + 20
        elseif t.laser and t.phase == ph then
            local first = #S.targets + 1
            local placed, note = typeUp(t, false)
            local new = {}
            for i = first, #S.targets do new[#new + 1] = S.targets[i] end
            armsOf(new)
            local onArm = 0
            for _, e in ipairs(new) do
                if e.onArm and S.broken[e.onArm] then breakTarget(e, "its arm's gone") elseif e.onArm then onArm = onArm + 1 end
            end
            sl(string.format("phase %d: its lasers up: %s, %d on the arms", ph, note, onArm))
        end
    end
    local nOn = openUp()
    sl(string.format("phase %d: %d targets lockable", ph, nOn))
    if SOLG.onPhase and not S.mirror then pcall(SOLG.onPhase, ph, nOn) end
end
SOLG.phaseOn = phaseOn
breakTarget = function(e, why)
    e.live = false
    flags(e.o, FLAGS_OFF)
    local L = boneAt(S.body, e.bone)
    if e.key == "SAW" then SOLG.breakPanel(e.bone)
    elseif e.t.laser then pcall(function() S.body:HideBoneByName(FName(e.bone), 0) end)   -- (AC:I has no wreck for it)
    else
        pcall(function() S.body:HideBoneByName(FName(e.bone), 0) end)
        pcall(function() S.body:UnHideBoneByName(FName(e.bone .. "_W")) end)
    end
    if L and fxAt then pcall(fxAt, SOLG.C.fx, L, n(SOLG.C.fx_scale[e.key], 3), 6) end
    pcall(function() e.o:K2_DetachFromActor(1, 1, 1) end)
    pcall(function() e.o:K2_SetActorLocation({ X = 0, Y = 0, Z = -5000000 }, false, {}, true) end)   -- (out of the way)
    S.broken = S.broken or {}
    S.down = (S.down or 0) + 1
    if why == "gone" then sl(string.format("%s gone without being shot down: broken, unpaid", e.bone)) end
    if SOLG.onBreak and not S.mirror and why ~= "its arm's gone" and why ~= "gone" then pcall(SOLG.onBreak, e.key, e.bone, e.t.pay, why) end
    openUp()                                              -- (what waited on it: Gould's wing rows, an arm's MAG panels)
    if e.t.optional or e.optional then return end         -- (a laser, an optional panel: the phases go on without it)
    if e.arm then                                         -- (its arm's last target: the arm breaks off)
        local left, pieces = 0, {}
        for _, x in ipairs(S.targets) do
            if x.arm == e.arm then pieces[#pieces + 1] = x.bone; if x.live then left = left + 1 end end
        end
        if left == 0 then
            for _, x in ipairs(S.targets) do                  -- (its riders, MAG panels and lasers, go down with it)
                if x.onArm == e.arm then
                    if x.live then breakTarget(x, "its arm's gone") end
                    if not x.t.laser then pieces[#pieces + 1] = x.bone end   -- (their wrecks off the body: the arm's mesh has them)
                end
            end
            SOLG.breakArm(e.arm, pieces)
        end
    end
    if S.mirror then return end                           -- (a joiner: the next phase and the end are the host's word)
    -- the phase over: the next one's on (AC:I's); the last one: the SOLG destroyed
    if S.pauseUntil then return end
    for _, x in ipairs(S.targets) do if x.live and not x.t.optional and not x.optional and x.t.phase == S.phase then return end end
    local nextPh = nil
    for _, x in ipairs(S.targets) do
        if x.live and not x.t.optional and not x.optional and (not nextPh or x.t.phase < nextPh) then nextPh = x.t.phase end
    end
    local pause = nextPh and n((SOLG.C.pause_s or {})[S.phase], 0) or 0
    if nextPh and pause > 0 then                          -- (Gould's pause before the next phase opens)
        S.pauseUntil, S.pauseNext = os.clock() + pause, nextPh
        sl(string.format("phase %d done: phase %d in %.0f s", S.phase, nextPh, pause))
    elseif nextPh then phaseOn(nextPh)
    else
        sl("every target down: the SOLG destroyed")
        S.destroyed = true
        for _, x in ipairs(S.targets) do if x.live then breakTarget(x, "its arm's gone") end end   -- (its lasers with it)
    end
end
-- (the tests': a target's HP straight to its floor, as a hit would)
function SOLG.hurt(key, k)
    if not S or not S.targets then return false end
    local i = 0
    for _, e in ipairs(S.targets) do
        if e.key == key and e.live then
            i = i + 1
            if i == (k or 1) then pcall(function() e.o.HealthInternal = math.floor(n(SOLG.C.floor, 1) * 10) end); return true end
        end
    end
    return false
end
function SOLG.state()
    if not S then return nil end
    local live, perKey = 0, {}
    for _, e in ipairs(S.targets or {}) do if e.live then live = live + 1; perKey[e.key] = (perKey[e.key] or 0) + 1 end end
    local open = 0
    for _, e in ipairs(S.targets or {}) do if e.live and e.open then open = open + 1 end end
    return { phase = S.phase, live = live, per = perKey, destroyed = S.destroyed, down = S.down or 0, open = open,
             pause = S.pauseUntil and math.max(0, S.pauseUntil - os.clock()) or nil, next = S.pauseNext }
end
-- each tick: unattached targets put on their bones; health read; at the floor, broken
local function targetsTick()
    if not (S and S.targets) then return end
    local floorIn = n(SOLG.C.floor, 1) * 10 + 0.5
    if S.mirror and SOLG.adoptTick then pcall(SOLG.adoptTick) end
    for _, e in ipairs(S.targets) do
        if e.live and S.mirror then                       -- (a joiner: its copies only held on their bones)
            if liveObj(e.o) and addrOf(e.o) == e.a and not e.attached then
                local L = boneAt(S.body, e.bone)
                if L then pcall(function() e.o:K2_SetActorLocation(L, false, {}, true) end) end
            end
        elseif e.live then
            if not liveObj(e.o) or addrOf(e.o) ~= e.a then breakTarget(e, "gone")
            else
                if not e.attached then
                    local L = boneAt(S.body, e.bone)
                    if L then pcall(function() e.o:K2_SetActorLocation(L, false, {}, true) end) end
                end
                local ok, h = pcall(function() return e.o.HealthInternal end)
                if ok and tonumber(h) and h <= floorIn then breakTarget(e, "shot down") end
            end
        end
    end
end
SOLG.targetsTick = targetsTick
-- ---- co-op: a joiner's SOLG (sv_solg_coop.lua) ----
-- its targets: this game's copies of the host's units (COOP.groundCopies), placed as they come (the lasers' with the
-- host's phase); breaks and phases from the host's word
function SOLG.mirrorUp()
    if not (S and liveObj(S.body)) then return 0 end
    S.targets, S.phase, S.mirror, S.pend = {}, 1, true, {}
    for _, t in ipairs(SOLG.C.targets) do if not t.laser then S.pend[t.key] = os.clock() + 20 end end
    return SOLG.adoptTick()
end
function SOLG.adoptTick()
    if not (S and S.mirror and S.pend and COOP and COOP.groundCopies) then return 0 end
    local placedAll = 0
    for key, untilAt in pairs(S.pend) do
        local t
        for _, x in ipairs(SOLG.C.targets) do if x.key == key then t = x end end
        local got = t and COOP.groundCopies(t.unit) or {}
        local nb = t and #bonesOf(t) or 0
        if t and (#got >= nb or (#got > 0 and os.clock() >= untilAt)) then
            local first = #S.targets + 1
            local placed = placeAll(t, got, false, true)
            local new = {}
            for i = first, #S.targets do new[#new + 1] = S.targets[i] end
            armsOf(new)
            if not t.laser then gouldRules() end
            S.pend[key] = nil
            placedAll = placedAll + placed
            sl(string.format("co-op: the host's %s copies placed: %d of %d", key, placed, nb))
            for _, e in ipairs(new) do                    -- (an arm already gone here: its lasers with it)
                if e.onArm and S.broken[e.onArm] then breakTarget(e, "its arm's gone") end
            end
            openUp()
        elseif t and os.clock() >= untilAt then
            S.pend[key] = nil
            sl(string.format("co-op: the host's %s copies never came (%d of %d)", key, #got, nb))
        end
    end
    return placedAll
end
-- the host's word: piece `bone` broken; phase `ph` on
function SOLG.breakBone(bone)
    if not (S and S.targets) then return false end
    for _, e in ipairs(S.targets) do
        if e.bone == bone and e.live then breakTarget(e, "the host's"); return true, n(e.t.pay, 0), e.key end
    end
    S.lateBroken = S.lateBroken or {}                     -- (its copy not placed yet: broken once it is)
    S.lateBroken[bone] = true
    return false
end
function SOLG.mirrorPhase(ph)
    if not (S and S.mirror) then return end
    if (S.phase or 0) < ph then phaseOn(ph) end
end
function SOLG.debugTargets() return S and S.targets or {} end          -- (the tests')
function SOLG.boneLoc(bone) if S and liveObj(S.body) then return (boneAt(S.body, bone)) end end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the SOLG"] = function() S = nil; CAPTURE = nil end end
end
