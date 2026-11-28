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
    hit_m = 20,                             -- ((2026-11-28) a target's hit sphere (m) unless its type says (targets[].hit_m)
    -- a wing shot off: pushed out from the barrel (m/s), down (m/s), its tumble (deg/s, each axis up to), gone after
    pitch_min_deg = 20,                     -- its nose down at least this much as it falls (the user: 45 "way too angled down", "go to 20")
    fall = { out_mps = 35, down_mps = 15, tumble_dps = 40, gravity = 1.0, life_s = 30, body_gravity = 0.35, body_tumble_dps = 4 },
    -- its targets (docs/re/SOLG.md 5: AC:I's types, counts and health): each type a unit of ours on AC8's GENERIC
    -- destructible base (tools/survival_events_specials.py SOLG_*: Mission 4's radar tower ported, no boss), its objects
    -- held on the SOLG's bones (its own mesh hidden: you see the SOLG's piece), their health AC:I's x health_x, held at
    -- floor HP so the game never breaks one its own way (a radar tower's wreck in the sky): at the floor the SOLG breaks
    -- it (the piece hidden, its wreck shown, a wing falling, an explosion, pay). AC:I's phases: 1 the wings (SAW) and
    -- the MAG panels, 2 the KEW shells, 3 the core units, 4 the rear hatch, 5 the SP shell; a phase's targets are
    -- lockable only then.
    targets = {
        -- ((2026-11-28) hit_m: its hit sphere's radius (the SAW panels' over each panel, ~108 m across: the user, "anywhere
        -- on the SAW panels"); the others SOLG.C.hit_m)
        { key = "SAW", unit = "SV_Unit_SOLG_SAW", phase = 1, health = 900, pay = 40, bones = { "SG04_%02d", 6, "SG05_%02d", 12 },
          hit_m = 55 },
        { key = "MAG", unit = "SV_Unit_SOLG_MAG", phase = 1, health = 600, pay = 25, bones = { "SG07_%02d", 32 } },
        { key = "KEW", unit = "SV_Unit_SOLG_KEW", phase = 2, health = 1000, pay = 50, bones = { "KEW_%02d", 36 } },
        { key = "CORE", unit = "SV_Unit_SOLG_CORE", phase = 3, health = 1500, pay = 200, bones = { "SG03_%02d", 4 } },
        -- ((2026-11-22) the user: "the rear hatch that has to be destroyed": AC:I's s_sg08, the disc closing its shaft
        -- (CONT_UNKNOWN in AC:I's data, 1 HP there: its health here a guess); the SP shell behind it, down the shaft)
        { key = "HATCH", unit = "SV_Unit_SOLG_HATCH", phase = 4, health = 2000, pay = 150, bones = { "SG08_%02d", 1 } },
        { key = "SP", unit = "SV_Unit_SOLG_SP", phase = 5, health = 2500, pay = 800, bones = { "CORE_%02d", 1 } },
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
    -- ((2026-11-22) the user: "make it so that the KEW Shells have a chain reaction"; her picks: "Damage neighbours",
    -- "The shooter, full pay") a KEW shell destroyed: hop_s later every live shell within reach_m (an arm's are 40 m
    -- apart in a line: its one or two neighbours) loses damage_pct of its health; one brought down blows the same way
    -- (its normal pay: the team's, as any shot down). Ours (AC:I has none; AC8's induced explosion reaches 20 m)
    ping = { enabled = true, every_s = 20 },
    -- ((2026-11-23) the user: "why haven't we set up the SOLG with collision yet?") its pieces' own shapes (PA_SV_SOLG, a body
    -- per bone: tools/solg/ue_import.py keep_physics) block as the world does (`profile`): a plane flown into it takes the
    -- game's own collision (the first try, a query from Lua, isn't callable: GetDistanceToCollision). Its stand-ins and
    -- turrets, attached to it, are ignored as it moves; a mover stopped by a plane is started again (its velocity kept).
    -- A piece shot off takes its shape with it.
    collision = { enabled = true, profile = "BlockAll" },
    -- ((2026-11-23) the user: "Air weapons and ground weapons as well need to work on the solg") its pieces are one kind of
    -- target (a ground object's), and a weapon locks air only, ground only or both (DT_WeaponSettings' LockOnTargetType:
    -- 0 both, 1 air, 2 ground). While it's up, every player weapon that's air or ground only locks both; put back as it
    -- goes (each game its own table)
    all_weapons = { enabled = true, table = "/Game/Datatables/PLAYER/DT_WeaponSettings.DT_WeaponSettings" },
    -- ((2026-11-23) the autotest: each turret fires its first burst, then never again (1-4 hits in 50 s, held still or
    -- moving; its ammo not limited): the land CIWS's cycle never comes round again on our turrets. Every rearm_s (Gould's
    -- 10 s of fire, 5 s rest) each live laser is switched off and on, which starts its cycle (and a burst) afresh)
    laser_rearm_s = 0,                     -- (off: switching them off and on didn't bring a second burst)
    laser_perf = { enabled = false, trigger_count = 999 },   -- (off: the game's own firing is left alone, own_laser fires)
    -- ((2026-11-23) its lasers are Survival's own (Scripts/sv_solg_laser.lua): Gould's 10 s on a player within reach, 5 s
    -- rest; AC8's player TLS beam (the ZFA-44's), its shooting sound, `damage` a hit every hit_s)
    -- ((2026-11-23) the first run: every turret in reach at once, a hit a second each: 275 hits in 21 s) at most max_at_you
    -- beams on you at a time, a hit every hit_s at hit_chance
    own_laser = { enabled = true, reach_m = 1500, fire_s = 10, rest_s = 5, hit_s = 2, first_hit_s = 1, damage = 5,
                  max_at_you = 3, hit_chance = 0.5,
                  beam_fx = "/Game/VFX/Vehicles/Weapon/TLS/NS_TLS_Muzzleflash01",
                  sound = "AKE_GEN_PLAYER_ARMS_SPWeapon_TLS_Emit_Play", sound_stop = "AKE_GEN_PLAYER_ARMS_SPWeapon_TLS_Emit_Stop" },
    -- ((2026-11-22) the user: "some black smoke that pours off the sides of the SOLG after things have been destroyed,
    -- and VFX for the splash down of its objects") a ship's black smoke on the bone of each piece shot off (its wreck's
    -- place on the body), at most max; a falling wing, arm or the SOLG itself at the sea or the ground: a water pillar
    -- and a sea burst there (land: a ground burst), then it's gone
    smoke = { enabled = true, max = 30, scale = 4, keys = { SAW = true, MAG = true, KEW = true, CORE = true, HATCH = true, SP = true, ARM = true },
              fx = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsSmokeS001" },
    splash = { enabled = true, sea_z = 350, scale = 3, body_scale = 8, life_s = 20, fall_life_s = 150,
               sea = { "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsPillarL001",
                       "/Game/VFX/Environment/Common/Explosion/GroundExplosion/groundExplosionA001/NS_groundExplosionASmallSea003" },
               land = { "/Game/VFX/Environment/Common/Explosion/AirExplosion/NS_airExplosionA/NS_airExplosionA_M" } },   -- (its minimap alert: RE_SV_SolgPing on its SP shell's unit)
    kew_chain = { enabled = true, reach_m = 45, damage_pct = 60, hop_s = 0.4 },
    fcs_table = "/Game/Mods/SurvivalMode/Data/DT_SV_SolgFCS.DT_SV_SolgFCS", fcs_row = "SV_FCS_SolgTLS",
    laser_model_row = "SV_Model_SOLG_LSR",
    -- their boxes: "SOLG" over each type's AC:I name (texts by key: tools/survival_events_specials.py SOLG_*)
    model_row = "SV_Model_SOLG", name_key = "SV_SOLG_Name", name = "SOLG",
    names = { SAW = "SOLAR ARRAY WING", MAG = "MAG PANEL", KEW = "KEW SHELL", CORE = "CORE UNIT", HATCH = "REAR HATCH", SP = "SP SHELL",
              LSRA = "LASER UNIT", LSRB = "LASER UNIT", LSRC = "LASER UNIT" },
    health_x = 0.25,                        -- (AC:I's health is a 4-player raid's: a first guess, every hit logged)
    floor = 1,                              -- a live target's HP floor: it breaks there
    fx = { "/Game/VFX/Environment/Common/Explosion/AirExplosion/NS_airExplosionA/NS_airExplosionA_M" },
    fx_scale = { SAW = 3, MAG = 2, KEW = 3, CORE = 5, HATCH = 6, SP = 8, SOLG = 12, ARM = 6, LSRA = 2, LSRB = 2, LSRC = 2 },
    -- ((2026-11-28) the user: "the SOLG didn't have any sounds") AC:I's own SOLG bank (tools/solg/sounds.py: its six break
    -- sounds, no engine or laser of its own; docs/rules/sources_and_toolchain.md, 2026-11-23) through Survival's player
    -- (sv_sound.lua SND.play) where a piece breaks, on every game: small (a panel, a shell, a laser) one of four, big
    -- (big_keys, an arm, the SOLG itself) one of two; gap_s at least between two of a kind (a KEW chain breaks a dozen)
    sounds = { enabled = true, gap_s = 0.3, big_keys = { CORE = true, HATCH = true, SP = true },
               small = { files = { "solg/break_small_1.wav", "solg/break_small_2.wav", "solg/break_small_3.wav", "solg/break_small_4.wav" },
                         db = 4, curve = { max = 900000, shape = "exp1" } },
               big = { files = { "solg/break_big_1.wav", "solg/break_big_2.wav" }, db = 8, curve = { max = 2500000, shape = "exp1" } } },
} }
do
local S = nil                                             -- the SOLG up: { actor, body, move, panels = {...} }
local SNDAT = { small = -1, big = -1, said = false }      -- (breakSound: when each kind last played)
local function breakSound(big, at)
    local c = SOLG.C.sounds
    if not (c and c.enabled ~= false and SND and SND.play and type(at) == "table") then return end
    local s = big and c.big or c.small
    if not (s and type(s.files) == "table" and #s.files > 0) then return end
    local kind, now = big and "big" or "small", os.clock()
    if now - SNDAT[kind] < (tonumber(c.gap_s) or 0.3) then return end
    SNDAT[kind] = now
    local f = s.files[math.random(#s.files)]
    local ok, h = pcall(SND.play, { file = f, db = tonumber(s.db) or 0, curve = s.curve }, { X = at.X, Y = at.Y, Z = at.Z })
    if not SNDAT.said then
        SNDAT.said = true
        log(string.format("solg: its break sound %s: %s", f, (ok and h) and "playing" or ("NOT played (" .. tostring(h) .. ")")))
    end
end
local function step(s) if crumb then crumb("solg: " .. s) end end
local function sl(s) log("solg: " .. s) end
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function obj(path) return loadObject(path .. "." .. path:match("[^/]+$")) end

-- an actor of ours at `at`, turned `rot` (a number: a yaw; a table: { Pitch, Yaw, Roll }). ((2026-11-22) its whole
-- rotation in its spawn transform: a rotation set afterwards never took (the pitch probe of 0.75.26: pitch 0.0 after
-- K2_SetActorRotation, 1.5 s on too), only the spawn's (the yaw always worked): "the solg didn't look angled downwards")
-- a { Pitch, Yaw, Roll } as a quaternion (UE's FRotator::Quaternion). (hard rule 76: a rotator's Pitch handed from Lua
-- is dropped by the engine call, its Yaw and Roll kept: a tilt goes through a transform's quaternion)
local function quatOf(rot)
    local p, y, r = math.rad(n(rot.Pitch, 0)) / 2, math.rad(n(rot.Yaw, 0)) / 2, math.rad(n(rot.Roll, 0)) / 2
    local SP, CP, SY, CY, SR, CR = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return { X = CR * SP * SY - SR * CP * CY, Y = -CR * SP * CY - SR * CP * SY, Z = CR * CP * SY - SR * SP * CY, W = CR * CP * CY + SR * SP * SY }
end
-- component c put at L turned rot (whole: through its transform's quaternion)
local function placeAt(c, L, rot)
    return pcall(function() c:K2_SetWorldTransform({ Rotation = quatOf(rot), Translation = { X = L.X, Y = L.Y, Z = L.Z },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false, {}, true) end)
end
local function newActor(at, rot)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local cls = StaticFindObject("/Script/Engine.Actor")
    if not (valid(gs) and valid(cls) and liveObj(survivalPC)) then return nil end
    if type(rot) ~= "table" then rot = { Pitch = 0, Yaw = rot or 0, Roll = 0 } end
    local t = { Rotation = quatOf(rot), Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
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
    -- ((2026-11-22) the user: "make it so that the Solg is angled downwards as if its falling ... it just looks like its falling
    -- flat") its nose down along its fall: its path's angle, at least pitch_min_deg (AC:I's Gould starts it 11 degrees down)
    local pitch = 0
    if vel then
        local hz = math.sqrt(n(vel.X, 0) ^ 2 + n(vel.Y, 0) ^ 2)
        local path = math.deg(math.atan(-n(vel.Z, 0), math.max(1, hz)))
        pitch = math.max(path, n(SOLG.C.pitch_min_deg, 20))
    end
    local a = newActor(at, { Pitch = -pitch, Yaw = yaw or 0, Roll = 0 })
    if not a then sl("no actor"); return false end
    step("its skeletal mesh")
    local body = addComp(a, "/Script/Engine.SkeletalMeshComponent")
    if not body then sl("no SkeletalMeshComponent"); pcall(function() a:K2_DestroyActor() end); return false end
    if SOLG.C.collision and SOLG.C.collision.enabled ~= false then
        pcall(function() body:SetCollisionProfileName(FName(SOLG.C.collision.profile or "BlockAll"), true) end)
        pcall(function() body:SetCollisionEnabled(3) end)                  -- (QueryAndPhysics: it blocks)
    else
        pcall(function() body:SetCollisionEnabled(0) end)
    end
    pcall(function() body:SetCastShadow(false) end)
    local okM = pcall(function() body:SetSkeletalMeshAsset(sk) end) or pcall(function() body:SetSkeletalMesh(sk, true) end)
    -- ((2026-11-22, run 17:58) a bare actor has no root: its spawn place went with the first component, the SOLG lay at the
    -- world's origin on the sea. Put where it's wanted once its mesh is its root)
    pcall(function() a:K2_SetActorLocationAndRotation({ X = at.X, Y = at.Y, Z = at.Z }, { Pitch = -pitch, Yaw = yaw or 0, Roll = 0 }, false, {}, true) end)
    -- (as the game has it, from its nose's direction: logged; a rotation's read came back empty, 0.75.25)
    -- (and on its body itself, the mesh you see: whether or not the actor has it as its root, read back from it)
    placeAt(body, at, { Pitch = -pitch, Yaw = yaw or 0, Roll = 0 })   -- (its tilt: hard rule 76)
    local okP, pitchNow = pcall(function() local f = body:GetForwardVector(); return math.deg(math.asin(math.max(-1, math.min(1, f.Z)))) end)
    pitchNow = okP and tonumber(pitchNow) or nil
    SOLG.pitchNow = pitchNow
    step("painting")
    local painted = paint(body)
    step("hiding its wrecks")
    local hid = 0
    pcall(function()
        local nb = body:GetNumBones()
        for i = 0, nb - 1 do
            local bn = body:GetBoneName(i):ToString()
            -- ((2026-11-23) the body's own wreck, never shown, its shape terminated too (PBO_Term): a solid one in its hollow shaft)
            if bn:match("_W$") and pcall(function() body:HideBoneByName(FName(bn), bn == "SOLG_W" and 1 or 0) end) then hid = hid + 1 end
        end
    end)
    step("its spin")
    local anim = obj(SOLG.C.spin)
    local spun = valid(anim) and pcall(function() body:PlayAnimation(anim, true) end)
    if spun then pcall(function() body:SetPlayRate(n(SOLG.C.spin_rate, 1)) end) end
    step("its mover")
    local mv = vel and mover(a, vel, 0) or nil
    S = { actor = a, body = body, move = mv, panels = {}, at0 = at, yaw = yaw, broken = {}, round = SOLG.spawnRound,
          vel = vel and { X = vel.X, Y = vel.Y, Z = vel.Z } or nil }
    SOLG.spawnRound = nil                                 -- (a test's own SOLG: no round of its own)
    pcall(SOLG.weaponsAll, true)
    sl(string.format("up at (%.1f, %.1f) km, %.1f km up, nose %.0f deg, %.0f deg down (the game's pitch %s): mesh %s, %s, %d wrecks hidden, spin %s, mover %s",
        at.X / 100000, at.Y / 100000, at.Z / 100000, yaw or 0, pitch, pitchNow and string.format("%.1f", pitchNow) or "?", okM and "on" or "NOT set", painted, hid,
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
    pcall(function() S.body:HideBoneByName(FName(bone), 1) end)   -- (its shape gone too: PBO_Term)
    local sk = obj(path)
    local a = valid(sk) and newActor(L, R) or nil
    local c = a and addComp(a, "/Script/Engine.SkeletalMeshComponent")
    if not c then sl("break " .. bone .. ": its falling mesh NOT made"); return false end
    pcall(function() c:SetCollisionEnabled(0) end)
    pcall(function() c:SetSkeletalMeshAsset(sk) end)
    placeAt(c, L, R)                                      -- (its bone's whole rotation: hard rule 76)   -- (its root now: run 17:58)
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
    S.panels[#S.panels + 1] = { actor = a, gone = os.clock() + n(SOLG.C.splash.fall_life_s, 150) }   -- (gone at its splash)
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
    breakSound(true, SOLG.where())                        -- ((2026-11-28) coming apart: AC:I's big break
    sl("falling (gravity " .. (S.move and "on" or "NO mover") .. ", tumble " .. (rot and "on" or "off") .. ")")
    return true
end
-- an arm broken off (all its targets down): hidden on the body with every piece on it, its own mesh falls away
function SOLG.breakArm(armBone, pieces)
    if not (S and liveObj(S.body)) or S.broken[armBone] then return false end
    local L, R = boneAt(S.body, armBone)
    if not (L and R) then sl("break " .. armBone .. ": its bone not found"); return false end
    S.broken[armBone] = true
    for _, b in ipairs({ armBone, armBone .. "_W" }) do pcall(function() S.body:HideBoneByName(FName(b), 1) end) end
    for _, b in ipairs(pieces or {}) do
        pcall(function() S.body:HideBoneByName(FName(b), 1) end)
        pcall(function() S.body:HideBoneByName(FName(b .. "_W"), 1) end)
    end
    local sk = obj(SOLG.C.arm)
    local a = valid(sk) and newActor(L, R) or nil
    local c = a and addComp(a, "/Script/Engine.SkeletalMeshComponent")
    if not c then sl("break " .. armBone .. ": its falling mesh NOT made"); return false end
    pcall(function() c:SetCollisionEnabled(0) end)
    pcall(function() c:SetSkeletalMeshAsset(sk) end)
    placeAt(c, L, R)                                      -- (its bone's whole rotation: hard rule 76)
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
    S.panels[#S.panels + 1] = { actor = a, gone = os.clock() + n(SOLG.C.splash.fall_life_s, 150), big = true }
    if SOLG.smokeOn then SOLG.smokeOn(armBone) end        -- (its stump smokes)
    if fxAt then pcall(fxAt, SOLG.C.fx, L, n(SOLG.C.fx_scale.ARM, 6), 8) end
    breakSound(true, L)
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
-- a black smoke on the body at `bone` (once a bone, at most smoke.max)
local function smokeOn(bone)
    local sm = SOLG.C.smoke
    if not (sm and sm.enabled ~= false and S and liveObj(S.body)) then return end
    S.smokes = S.smokes or {}
    if S.smokes[bone] or (S.nSmoke or 0) >= n(sm.max, 30) then return end
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = SPC and SPC.V and SPC.V.asset(sm.fx)
    if not (valid(lib) and sys) then return end
    local ok, c = pcall(function()
        return lib:SpawnSystemAttached(sys, S.body, FName(bone), { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }, 0, false, true, 0, true)
    end)
    if ok and c then
        local k = n(sm.scale, 4)
        pcall(function() c:SetWorldScale3D({ X = k, Y = k, Z = k }) end)
        S.smokes[bone], S.nSmoke = c, (S.nSmoke or 0) + 1
        if S.nSmoke == 1 then sl("smoke pouring off it (" .. bone .. ")") end
    end
end
SOLG.smokeOn = smokeOn
-- ((2026-11-22) the autotest: each turret fired one burst, then none for 45 s, with the row's ammo limit off too) their
-- fire control's projectile module carries its own bLimitAmmo / AmmoCount (the ZFA's aim-only arm we copied: 0 rounds):
-- unlimited on each of these turrets' modules, what they had logged once
function SOLG.lasersArmed(list)
    local mine = {}
    for _, e in ipairs(list or {}) do
        local okN, nm = pcall(function() return e.o:GetFName():ToString() end)
        if okN and nm then mine[#mine + 1] = nm end
    end
    if #mine == 0 then return 0 end
    local nn, was = 0, nil
    for _, m in ipairs(FindAllOf("LiveFCSModule_ProjectileCommon") or {}) do
        local okF, full = pcall(function() return m:GetFullName() end)
        if okF and full then
            for _, nm in ipairs(mine) do
                if full:find(nm, 1, true) then
                    if not was then pcall(function() was = string.format("bLimitAmmo %s, AmmoCount %s", tostring(m.bLimitAmmo), tostring(m.AmmoCount)) end) end
                    if pcall(function() m.bLimitAmmo = false; m.AmmoCount = 99999 end) then nn = nn + 1 end
                    break
                end
            end
        end
    end
    sl(string.format("lasers: %d of %d turrets' fire control given unlimited ammo (they had %s)", nn, #mine, tostring(was)))
    -- ((2026-11-23) still one burst: their launcher's performance and fire control, logged once and overwritten: reload not
    -- held for the fired weapon (bPendingReloadByAttachedWeapon: our borrowed plane laser may never report it's done), a
    -- magazine, trigger_count bursts)
    local lp = SOLG.C.laser_perf or {}
    local said, np = false, 0
    for _, m in ipairs(FindAllOf("LiveFCSModule_LauncherCommon") or {}) do
        local okF, full = pcall(function() return m:GetFullName() end)
        local hit = false
        if okF and full then for _, nm in ipairs(mine) do if full:find(nm, 1, true) then hit = true; break end end end
        if hit then
            local okP, pf = pcall(function() return m:K2_GetCurrentPerformance() end)
            local okC, fc = pcall(function() return m:K2_GetCurrentFireControl() end)
            if not said then
                said = true
                local t = {}
                pcall(function() t[#t + 1] = string.format("performance: fire rate %s, magazine %s, reload %s s, reload held for its weapon %s, slots %s",
                    tostring(pf.FireRate), tostring(pf.MagazineCapacity), tostring(pf.ReloadTime), tostring(pf.bPendingReloadByAttachedWeapon), tostring(pf.SlotNum)) end)
                pcall(function() t[#t + 1] = string.format("fire control: capture %s cm, angle %s, activation %s s, triggering %s s, trigger count %s, interval %s s, resting %s s",
                    tostring(fc.CaptureDistance), tostring(fc.CaptureAngleRange), tostring(fc.ActivationTime), tostring(fc.TriggeringTime),
                    tostring(fc.TriggerCount), tostring(fc.ShotIntervalTime), tostring(fc.RestingTime)) end)
                sl("lasers: their launcher had " .. table.concat(t, "; "))
            end
            -- ((2026-11-23) K2_OverwritePerformance / K2_OverwriteFireControl with the struct handed back from Lua crashed the
            -- game (run 004237): the one field written in place on the module's own FireControl instead)
            local okW = false
            if lp.enabled ~= false then
                okW = pcall(function() m.FireControl.TriggerCount = n(lp.trigger_count, 999) end)
            end
            if okW then np = np + 1 end
        end
    end
    sl(string.format("lasers: %d launchers' trigger count set to %d", np, n(lp.trigger_count, 999)))
    return nn
end
-- the ground (or sea) under x, y
local kis = nil
local function groundZ(x, y)
    if not valid(kis) then kis = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    if not (valid(kis) and valid(survivalPC)) then return nil end
    local hit, z = {}, nil
    pcall(function()
        kis:LineTraceSingle(survivalPC, { X = x, Y = y, Z = 1000000 }, { X = x, Y = y, Z = -100000 }, 0, true, {}, 0,
            hit, true, { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    end)
    pcall(function() local h = hit.OutHit or hit; local l = h.ImpactPoint or h.Location; if l and l.Z then z = l.Z end end)
    return z
end
-- a falling actor at the surface: its splash (true: it's there)
local function splashed(a, scale)
    local sp = SOLG.C.splash
    if not (sp and sp.enabled ~= false and liveObj(a)) then return false end
    local ok, L = pcall(function() local v = a:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not (ok and L) then return false end
    local sea = n(sp.sea_z, 350)
    if L.Z > sea + 150000 then return false end           -- (high up still: no trace)
    local gz = groundZ(L.X, L.Y)
    local land = gz and gz > sea + 500
    local surf = land and gz or sea
    if L.Z > surf + 3000 then return false end
    if fxAt then pcall(fxAt, land and sp.land or sp.sea, { X = L.X, Y = L.Y, Z = surf }, scale, n(sp.life_s, 20)) end
    S.splashes = (S.splashes or 0) + 1
    if S.splashes == 1 then sl(string.format("a piece came down in the %s: its splash", land and "land" or "sea")) end
    return true
end
-- its laser turrets now (sv_solg_laser.lua's): { o, bone, live, open }; nil with no SOLG
-- its mover kept going: a plane it hit (its collision) stops a ProjectileMovementComponent (no bounce): started again
function SOLG.crashTick()
    if not (S and S.move and S.vel and liveObj(S.move) and liveObj(S.actor)) or S.falling then return end
    local okV, sp = pcall(function() local v = S.move.Velocity; return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end)
    local want = math.sqrt(S.vel.X ^ 2 + S.vel.Y ^ 2 + S.vel.Z ^ 2)
    if okV and sp and sp < want * 0.5 then
        pcall(function() S.move:SetUpdatedComponent(S.actor.RootComponent) end)
        pcall(function() S.move.Velocity = { X = S.vel.X, Y = S.vel.Y, Z = S.vel.Z } end)
        S.restarts = (S.restarts or 0) + 1
        if S.restarts <= 3 then sl(string.format("its mover started again (%.0f of %.0f m/s: something it hit stopped it)", sp / 100, want / 100)) end
    end
end
-- the player's weapons: air / ground only -> both while it's up (on), as they were (off)
local WPN = { was = nil }
function SOLG.weaponsAll(on)
    local c = SOLG.C.all_weapons
    if not (c and c.enabled ~= false) then return 0 end
    if on and WPN.was then return 0 end
    if not on and not WPN.was then return 0 end
    -- (putting them back: the table already held, pinned, so nothing is loaded while a level is torn down)
    local dt = (not on and WPN.dt and valid(WPN.dt)) and WPN.dt or loadObject(c.table)
    if not valid(dt) then sl("all weapons: no " .. tostring(c.table)); return 0 end
    local nn = 0
    if on then
        WPN.was, WPN.dt = {}, dt
        if pin then pcall(pin, dt, "the weapons' settings (the SOLG's)") end
        for _, name in ipairs(rowList and rowList(dt) or {}) do
            local okR, r = dtCall(dt, "FindRow", name)
            local t = nil
            if r ~= nil then pcall(function() t = tonumber(r.LockOnTargetType) end) end
            if t == 1 or t == 2 then
                pcall(function() r.LockOnTargetType = 0 end)
                if dtCall(dt, "AddRow", name, r) then WPN.was[name] = t; nn = nn + 1 end
            end
        end
        sl(string.format("all weapons: %d air or ground only weapons lock both while it's up", nn))
    else
        for name, t in pairs(WPN.was) do
            local okR, r = dtCall(dt, "FindRow", name)
            if r ~= nil then
                pcall(function() r.LockOnTargetType = t end)
                if dtCall(dt, "AddRow", name, r) then nn = nn + 1 end
            end
        end
        WPN.was = nil
        sl(string.format("all weapons: %d put back as they were", nn))
    end
    return nn
end
function SOLG.laserTurrets()
    if not (S and S.targets) or S.destroyed then return nil end
    local out = {}
    for _, e in ipairs(S.targets) do
        if e.t.laser then out[#out + 1] = { o = e.o, bone = e.bone, live = e.live, open = e.open } end
    end
    return out
end
function SOLG.stop(why)
    pcall(SOLG.weaponsAll, false)                        -- (the weapons as they were, whatever happens below)
    if not S then return end
    if SLAS and SLAS.stop then pcall(SLAS.stop) end
    for _, c in pairs(S.smokes or {}) do pcall(function() c:DestroyComponent() end) end
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
    if (levelTorn and levelTorn()) or not D then pcall(SOLG.weaponsAll, false); S = nil; return end   -- (the code review of 2026-11-23: never left on)
    if SOLG.targetsTick then pcall(SOLG.targetsTick) end
    if S and SLAS and SLAS.tick then
        local okL, errL = pcall(SLAS.tick, os.clock())
        if not okL and not S.slasErr then S.slasErr = true; sl("its lasers: error " .. tostring(errL)) end
    end
    if not S then return end
    if SOLG.crashTick then
        local okC, errC = pcall(SOLG.crashTick)
        if not okC and not S.crashErr then S.crashErr = true; sl("its collision: error " .. tostring(errC)) end
    end
    if S and S.pauseUntil and os.clock() >= S.pauseUntil then
        local ph = S.pauseNext
        S.pauseUntil, S.pauseNext = nil, nil
        if ph and SOLG.phaseOn then pcall(SOLG.phaseOn, ph) end
    end
    local clock = os.clock()
    -- ((2026-11-22) the user: "add a minimap alert ping as to where the SOLG spawns") Mission 22's "look here" on its
    -- SP shell's unit (RE_SV_SolgPing), on this game's own copy: at once, then every every_s while it's up
    local pg = SOLG.C.ping
    if pg and pg.enabled ~= false and S.targets and not S.destroyed and type(SV_Event) == "function" and clock >= (S.pingAt or 0) then
        local sp = nil
        for _, e in ipairs(S.targets) do if e.key == "SP" and e.live then sp = e end end
        if sp then
            S.pingAt = clock + n(pg.every_s, 20)
            local okP, r = pcall(SV_Event, "RE_SV_SolgPing")
            S.pings = (S.pings or 0) + 1
            if S.pings == 1 or not (okP and r == 1) then
                sl(string.format("pinged on the minimap (RE_SV_SolgPing %s; every %d s while it's up)",
                    okP and r == 1 and "fired" or ("NOT fired: " .. tostring(r)), n(pg.every_s, 20)))
            end
        end
    end
    -- ((2026-11-22) the user: "make sure that all the solg pieces are successfully deleted after the round is completed")
    if D and S.round and D.round ~= S.round then SOLG.stop("its round is over"); return end
    for i = #S.panels, 1, -1 do                           -- (a falling piece at the surface: its splash, then gone)
        local p = S.panels[i]
        if not p.down and splashed(p.actor, n(SOLG.C.splash.scale, 3) * (p.big and 2 or 1)) then p.down = true; p.gone = math.min(p.gone, clock + 1) end
    end
    if S.falling and not S.bodyDown and splashed(S.actor, n(SOLG.C.splash.body_scale, 8)) then
        S.bodyDown = true
        pcall(function() S.body:SetVisibility(false, true) end)
    end
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
            pcall(function() S.body:IgnoreActorWhenMoving(o, true) end)   -- (its own stand-ins never block its fall)
            -- ((2026-11-22) the user: "all the target boxes were on the top of the radar tower not at its base which
            -- threw the targetting off") its lock point (HitCenterOffset, the tower's top) put on the bone, not its base
            if att and not t.laser then
                local okH, hx, hy, hz = pcall(function() local h = o.HitCenterOffset; return h.X, h.Y, h.Z end)
                if okH and tonumber(hx) then
                    local okR = pcall(function() o:K2_SetActorRelativeLocation({ X = -hx, Y = -hy, Z = -hz }, false, {}, true) end)
                    if not okR then pcall(function() o.RootComponent:K2_SetRelativeLocation({ X = -hx, Y = -hy, Z = -hz }, false, {}, true) end) end
                    if not S.hitOffSaid then S.hitOffSaid = true; sl(string.format("targets: lock point %.0f, %.0f, %.0f cm off the base: put on the bones", hx, hy, hz)) end
                end
            end
            if not mirror then
                pcall(function() o.MaxHealth = hp; o.HealthInternal = math.floor(hp * 10 + 0.5) end)
                pcall(function() o.MinHealth = n(SOLG.C.floor, 1) end)
            end
            if not t.laser then hideOwn(o) elseif SOLG.C.laser_hide ~= false then hideOwn(o, false) end
            -- ((2026-11-28) its hit sphere over the piece it stands for (t.hit_m, else SOLG.C.hit_m): the SAW panels 55 m (the
            -- user: "if I target anywhere on the SAW panels that its hittable"); the pawn is invisible, the sphere all to hit
            if not t.laser then
                local was, now, how = hitSphere(o, t.hit_m or SOLG.C.hit_m)
                S.sphereSaid = S.sphereSaid or {}
                if not S.sphereSaid[t.key] then
                    S.sphereSaid[t.key] = true
                    sl(string.format("targets: %s's hit sphere %s m -> %s m (%s)", t.key, was and string.format("%.1f", was) or "?",
                        now and string.format("%.1f", now) or "NOT set", tostring(how)))
                end
            end
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
            if SOLG.lasersArmed then pcall(SOLG.lasersArmed, new) end
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
    elseif e.t.laser then pcall(function() S.body:HideBoneByName(FName(e.bone), 1) end)   -- (AC:I has no wreck for it)
    else
        pcall(function() S.body:HideBoneByName(FName(e.bone), 1) end)        -- (its shape off; its wreck's stays)
        pcall(function() S.body:UnHideBoneByName(FName(e.bone .. "_W")) end)
    end
    if L and fxAt then pcall(fxAt, SOLG.C.fx, L, n(SOLG.C.fx_scale[e.key], 3), 6) end
    if L and why ~= "gone" then breakSound(((SOLG.C.sounds or {}).big_keys or {})[e.key] == true, L) end
    if SOLG.C.smoke and SOLG.C.smoke.keys[e.key] and why ~= "gone" then smokeOn(e.bone) end
    local kc = SOLG.C.kew_chain
    if e.key == "KEW" and L and kc and kc.enabled ~= false and not S.mirror and why ~= "gone" and why ~= "its arm's gone" then
        local reach, at = n(kc.reach_m, 45) * 100, os.clock() + n(kc.hop_s, 0.4)
        S.chain = S.chain or {}
        for _, x in ipairs(S.targets) do
            if x.live and x.key == "KEW" and x ~= e then
                local B = boneAt(S.body, x.bone)
                if B and math.sqrt((B.X - L.X) ^ 2 + (B.Y - L.Y) ^ 2 + (B.Z - L.Z) ^ 2) <= reach then
                    S.chain[#S.chain + 1] = { e = x, at = at, from = e.bone }
                end
            end
        end
    end
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
    local rr = n(SOLG.C.laser_rearm_s, 0)
    if rr > 0 and not S.mirror then                       -- (its lasers' cycle started afresh: see laser_rearm_s)
        local now = os.clock()
        if S.rearmOff then                                -- (switched off last tick: on again now)
            for _, e in ipairs(S.rearmOff) do if e.live and liveObj(e.o) then pcall(function() e.o.bIsActivated = true end) end end
            S.rearmOff = nil
        elseif now >= (S.rearmAt or 0) then
            S.rearmAt = now + rr
            local off = {}
            for _, e in ipairs(S.targets) do
                if e.t.laser and e.live and e.open and liveObj(e.o) and pcall(function() e.o.bIsActivated = false end) then off[#off + 1] = e end
            end
            if #off > 0 then
                S.rearmOff = off
                S.rearms = (S.rearms or 0) + 1
                if S.rearms <= 2 then sl(string.format("lasers rearmed: %d turrets' cycle started afresh (every %d s)", #off, rr)) end
            end
        end
    end
    if S.chain and #S.chain > 0 and not S.mirror then       -- (the KEW shells' chain: its blasts due now)
        local now, keep = os.clock(), {}
        for _, c in ipairs(S.chain) do
            if c.at > now then keep[#keep + 1] = c
            elseif c.e.live and liveObj(c.e.o) then
                local ok, h, mx = pcall(function() return c.e.o.HealthInternal, c.e.o.MaxHealth end)
                if ok and tonumber(h) and tonumber(mx) then
                    local to = math.max(math.floor(n(SOLG.C.floor, 1) * 10), h - mx * 10 * n(SOLG.C.kew_chain.damage_pct, 60) / 100)
                    pcall(function() c.e.o.HealthInternal = to end)
                    sl(string.format("KEW chain: %s's blast on %s: %.0f%% left%s", c.from, c.e.bone, 100 * to / (mx * 10),
                        to <= floorIn and " (it blows)" or ""))
                end
            end
        end
        S.chain = keep
    end
    if S.mirror and SOLG.adoptTick then pcall(SOLG.adoptTick) end
    for _, e in ipairs(S.targets) do
        if e.live and S.mirror then                       -- (a joiner: its copies only held on their bones)
            if liveObj(e.o) and addrOf(e.o) == e.a and not e.attached then
                local L = boneAt(S.body, e.bone)
                if L then pcall(function() e.o:K2_SetActorLocation(L, false, {}, true) end) end
            end
            if liveObj(e.o) and addrOf(e.o) == e.a then        -- (its damaged state's mesh hidden again, as the host's)
                local ok, h = pcall(function() return e.o.HealthInternal end)
                if ok and tonumber(h) and h ~= e.lastH then
                    if e.lastH and not e.t.laser then hideOwn(e.o) elseif e.lastH and SOLG.C.laser_hide ~= false then hideOwn(e.o, false) end
                    e.lastH = h
                end
            end
        elseif e.live then
            if not liveObj(e.o) or addrOf(e.o) ~= e.a then breakTarget(e, "gone")
            else
                if not e.attached then
                    local L = boneAt(S.body, e.bone)
                    if L then pcall(function() e.o:K2_SetActorLocation(L, false, {}, true) end) end
                end
                local ok, h = pcall(function() return e.o.HealthInternal end)
                -- ((2026-11-22) the user: "weird radar towers models on everything": hit, AC8's destructible base
                -- shows its damaged state's mesh, visible again: hidden again whenever its health moves)
                if ok and tonumber(h) and h ~= e.lastH then
                    if e.lastH and not e.t.laser then hideOwn(e.o) elseif e.lastH and SOLG.C.laser_hide ~= false then hideOwn(e.o, false) end
                    e.lastH = h
                end
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
function SOLG.debugActor() return S and S.actor or nil end                    -- (the tests')
function SOLG.boneLoc(bone) if S and liveObj(S.body) then return (boneAt(S.body, bone)) end end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the SOLG"] = function() pcall(SOLG.weaponsAll, false); S = nil; CAPTURE = nil end end
end
