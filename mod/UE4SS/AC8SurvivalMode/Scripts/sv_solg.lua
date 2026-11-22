-- sv_solg.lua : the SOLG, VALKA's last move (the user, 2026-11-22: "When Valka reaches 20% health ... Valka Calls in
-- the SOLG. The SOLG spawns at high altitude out of another Portal ... and begins to travel towards the space centre";
-- "the SOLG cannot use any boss from the game it needs to be it's own custom thing"; docs/re/SOLG.md, the plan in
-- docs/design). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order: a name another part uses is a
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
    tex = "/Game/Mods/SurvivalMode/SOLG/Textures/T_SV_SOLG_",
    paint = { parent = "/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear",
              tex = { Livemap = "rt:0,0.75,1", Normalmap = "/Engine/EngineMaterials/DefaultNormal",
                      Detail_Normal = "/Engine/EngineMaterials/DefaultNormal",
                      Blend_Dameged_Normalmap = "/Engine/EngineMaterials/DefaultNormal" },
              scalars = { Ctrl_All_Emissive = 0, Turbine_speed = 0, NormalIntencity = 0, DNormal_Strength = 0,
                          DamegedNormal_Intencity = 0, PlayerPlane_Damage = 0 } },
    spin_rate = 1.0,                        -- the spin animation's play rate (1: AC:I's, a ring's turn in 40 s)
    -- a wing shot off: pushed out from the barrel (m/s), down (m/s), its tumble (deg/s, each axis up to), gone after
    fall = { out_mps = 35, down_mps = 15, tumble_dps = 40, gravity = 1.0, life_s = 30 },
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
function SOLG.stop(why)
    if not S then return end
    for _, p in ipairs(S.panels) do if liveObj(p.actor) then pcall(function() p.actor:K2_DestroyActor() end) end end
    if liveObj(S.actor) then pcall(function() S.actor:K2_DestroyActor() end) end
    sl("taken down (" .. tostring(why) .. ")")
    S = nil
end
function SOLG.tick(now)
    if not S then return end
    if (levelTorn and levelTorn()) or not D then S = nil; return end
    local clock = os.clock()
    for i = #S.panels, 1, -1 do
        local p = S.panels[i]
        if clock >= p.gone or not liveObj(p.actor) then
            if liveObj(p.actor) then pcall(function() p.actor:K2_DestroyActor() end) end
            table.remove(S.panels, i)
        end
    end
end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the SOLG"] = function() S = nil end end
end
