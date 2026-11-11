-- sv_tanicorn.lua: THE TANICORN's milestone 0 test (docs/re/TANICORN.md; the user's Anomaly boss, 2026-11-09).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order: a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local.
--
-- One gun mount of Survival's own (BP_SV_Tani_T5: our skeleton, mesh, blueprint straight on AC8's native
-- ALiveAIGroundVehicleObject, built and cooked by tools/tanicorn; its container SurvivalMode_Tani_P is staged with TANI=1
-- only) spawned through Survival's rows as GONE FISHIN's shoals are: the world-data unit SV_Unit_TaniTest on its mission
-- row, its DT_NPC row SV_Npc_TaniMount and model row SV_Model_TaniMount (whose blueprint is ours) added from Survival's
-- tables to the game's at the first press. Test builds only: all of it is in the test-only block below.
--   Ctrl+T in a run   (0.74.43 had Ctrl+`, the game console's key) our class loaded by itself first (`tanicorn: class
--                     ...`: AC8 took our cooked blueprint or not), then the mount spawned 3 km ahead on the sea through the
--                     shoals' spawn capture (FISH.spawn: every AI object the spawner makes, `tanicorn: the spawn made ...`),
--                     looked at again 1 s and 4 s on. While one is up (60 s after a spawn): its health and its aim bones'
--                     angles every 2 s (`tanicorn: ... yaw ... pitch ...`): AC8's fire control turning our bones to you.
-- (0.74.43, the user's first run: rows in, SV_Spawn "1 up" four times, no BP_SV_Tani_T5_C found in 33 walks)
-- (0.74.45: our class loads in AC8 with its fire control; the spawn still made no object: the rows were added too late)
--   Ctrl+U in a run   (0.74.61) the other three gun mounts as the T5 (TANI.mounts: the 16-inch triple, the CIWS, the laser),
--                     each on its own rows and fire control row (cloned at the main menu: `tanicorn: fire control row
--                     SV_FCS_Tani<part> from <stock row>: in (SlotNum N, ...)`), spawned 3 km ahead in a row across your
--                     path, 400 m apart; the same looks, 2 s lines and shell lines as the T5's, each line naming its mount
--                     (T5, T16, CIWS, LASER).
--                     (2026-11-11) The LASER carries AC7's LaserInterceptor at its muzzle, as the ZFA-44s do (sv_escort_li.lua:
--                     `tanicorn: LASER mount ... handed to AC7's LaserInterceptor`, then its `zfa li:` lines), on YOUR
--                     missiles: fire some at it from inside 2 km. Its CIWS row is only its aim now (no ammo).
--   Ctrl+Y in a run   (0.74.60) THE TANACORN's whole hull, every part drawn on its socket, 5 km ahead.
--   Ctrl+R in a run   (2026-11-11) THE TANACORN rises on her rig with the cinematic (TANI.rise; again: everything back).
-- TEST ONLY BEGIN
TANI = { unit = "SV_Unit_TaniTest", npc = "SV_Npc_TaniMount", model = "SV_Model_TaniMount",
         class = "BP_SV_Tani_T5_C", class_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T5.BP_SV_Tani_T5_C",
         cdo_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T5.Default__BP_SV_Tani_T5_C",
         dummy = "BP_GR000_dummy_CP_C", name_key = "SV_TaniMount_Name", name = "TANICORN MOUNT",
         fcs = "SV_FCS_TaniT5", fcs_src = "NPC_FCS_FlakGun000", fcs_slots = 2,   -- (0.74.59; survival_events.TANI_FCS)
         -- (0.74.60) the row's turn speeds: the stock flak gun's 360 deg/s jumped about (the user's run of 0.74.59: "it
         -- tracks but not as smoothly as it was previously kinda jumps around like the stock flak cannon"); our arm's 40
         fcs_speed = 40,
         -- (0.74.60) THE TANACORN's hull with its parts drawn on their sockets (survival_events.TANI_HULL_*), Ctrl+Y:
         -- broadside to you ahead_cm out, its waterline on the sea
         hull = { unit = "SV_Unit_TaniHull", npc = "SV_Npc_TaniHull", model = "SV_Model_TaniHull",
                  class = "BP_SV_Tani_HULL_C", class_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_HULL.BP_SV_Tani_HULL_C",
                  name_key = "SV_TaniHull_Name", name = "TANACORN", ahead_cm = 500000, z_cm = 0 },
         ahead_cm = 300000, z_cm = 700, every_s = 2.0, watch_s = 60 }
TANI.key = "T5"
-- (0.74.61) the other gun mounts, each as the T5 (the build's survival_events.TANI_MOUNTS: unit, NPC row, model row and name
-- key; its NPC row's NpcFCSId0 names fcs, cloned here at the main menu from fcs_src). fcs_src is a stock row whose arms
-- blueprint drives BN_turret_yaw / BN_turret_pitch on TurretPoseableMesh with the GUN prefix, as our mounts are rigged
-- (0.74.59: the row's arm replaces the blueprint's and gives it its muzzles):
--   T16    NPC_FCS_VesselArtillery000: BP_FCS_Vessel_Artillery_00, the ships' main gun (BP_wp_artillery_vesselgun, a LiveArtillery
--          shell), 30 km. The railgun arms the land battleships carry (BP_FCS_StrafingRailgun_00, the GR036 main cannon) drive
--          PM_Cannon's BN_turret_pitch_01 / _02, which our triple hasn't
--   CIWS   NPC_FCS_VesselCIWS000: BP_FCS_Vessel_CIWS_00, the Aegis's Mk15 (BP_wp_ciws_vessel, a LiveAttachedInterceptorWeapon), 2.5 km
--   LASER  NPC_FCS_VesselCIWS000 too, for its aim only (no ammo: no_gun): its weapon is AC7's LaserInterceptor at its muzzle
--          (li; the user, 2026-11-11: "the LASERS have to be Laser Interceptors"), not a stock arm (0.74.61 fired the CIWS's gun)
-- fcs_slots: its muzzles (SOC_Gun_01..N); fcs_speed { yaw, pitch } deg/s and the yaw / pitch arcs: the mount's own
-- (tools/tanicorn/spec.py FCS), in place of the stock row's (the CIWS's +-60, the artillery's +-110: a ship's side mounts)
TANI.mounts = {
    { key = "T16", unit = "SV_Unit_TaniT16Gun", npc = "SV_Npc_TaniT16Gun", model = "SV_Model_TaniT16Gun",
      class = "BP_SV_Tani_T16_C", class_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T16.BP_SV_Tani_T16_C",
      cdo_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T16.Default__BP_SV_Tani_T16_C",
      name_key = "SV_TaniT16Gun_Name", name = "TANICORN 16-INCH",
      fcs = "SV_FCS_TaniT16", fcs_src = "NPC_FCS_VesselArtillery000", fcs_slots = 3, fcs_speed = { 12, 8 },
      yaw = { -150, 150 }, pitch = { -2, 45 } },
    { key = "CIWS", unit = "SV_Unit_TaniCIWS", npc = "SV_Npc_TaniCIWS", model = "SV_Model_TaniCIWS",
      class = "BP_SV_Tani_CIWS_C", class_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_CIWS.BP_SV_Tani_CIWS_C",
      cdo_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_CIWS.Default__BP_SV_Tani_CIWS_C",
      name_key = "SV_TaniCIWS_Name", name = "TANICORN CIWS",
      fcs = "SV_FCS_TaniCIWS", fcs_src = "NPC_FCS_VesselCIWS000", fcs_slots = 1, fcs_speed = { 120, 100 },
      yaw = { -180, 180 }, pitch = { -10, 85 } },
    { key = "LASER", unit = "SV_Unit_TaniLASER", npc = "SV_Npc_TaniLASER", model = "SV_Model_TaniLASER",
      class = "BP_SV_Tani_LASER_C", class_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_LASER.BP_SV_Tani_LASER_C",
      cdo_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_LASER.Default__BP_SV_Tani_LASER_C",
      name_key = "SV_TaniLASER_Name", name = "TANICORN LASER",
      fcs = "SV_FCS_TaniLASER", fcs_src = "NPC_FCS_VesselCIWS000", fcs_slots = 1, fcs_speed = { 120, 100 },   -- (its aim)
      yaw = { -180, 180 }, pitch = { -10, 85 },
      -- (2026-11-11) the user: "the LASERS have to be Laser Interceptors": AC7's LaserInterceptor at its muzzle (li: handed
      -- to sv_escort_li.lua, as the ZFA-44s carry it), the CIWS row only its aim: no_gun, its gun given no ammo
      -- (bLimitAmmo, AmmoCount 0)
      li = true, no_gun = true },
}
TANI.mount_gap_cm = 40000                                -- (Ctrl+U: the three across your path, 400 m apart)
do
local T = { rows = nil, next = 0, seen = {}, until_ = 0, checks = {}, shells = {}, stock = {} }
local KINDS = { TANI }                                   -- every gun mount type (the T5 and TANI.mounts): its key and class
for _, k in ipairs(TANI.mounts) do KINDS[#KINDS + 1] = k end

local function kindOf(o)                                 -- the mount type of one of our mounts (by its class), or nil
    local cls = "?"
    pcall(function() cls = o:GetClass():GetFName():ToString() end)
    for _, k in ipairs(KINDS) do if k.class == cls then return k end end
    return nil
end

local function ours()                                    -- every gun mount of ours in the level: { o, k } (k: its type)
    local out = {}
    for _, k in ipairs(KINDS) do
        for _, o in ipairs(FindAllOf(k.class) or {}) do
            if valid(o) and not nameOf(o):find("Default__", 1, true) then out[#out + 1] = { o = o, k = k } end
        end
    end
    return out
end

-- (0.74.59) one mount's fire control row (its NPC row's NpcFCSId0, tools/build_survival.py): spec.fcs cloned from the stock
-- spec.fcs_src with its muzzles (SlotNum), a magazine of at least that, its turn speeds (fcs_speed: a number, or { yaw,
-- pitch }) and, when spec has them, its yaw / pitch arcs. The row path is the one that gives the arm its muzzles (0.74.58,
-- the user: "THE GUN FIRED FROM THE BARREL THIS TIME", "only one barrel was working": the row's SlotNum 1)
local function fcsRow(fcs, spec)
    local ys, ps = spec.fcs_speed, spec.fcs_speed
    if type(spec.fcs_speed) == "table" then ys, ps = spec.fcs_speed[1], spec.fcs_speed[2] end
    local okF, whyF = cloneRow(fcs, spec.fcs_src, spec.fcs, function(r)
        r.SlotNum = spec.fcs_slots
        if (tonumber(r.MagazineCapacity) or 0) < spec.fcs_slots then r.MagazineCapacity = spec.fcs_slots end
        r.YawSpeed, r.PitchSpeed = ys, ps
        if spec.yaw then r.YawAngleMin, r.YawAngleMax = spec.yaw[1], spec.yaw[2] end
        if spec.pitch then r.PitchAngleMin, r.PitchAngleMax = spec.pitch[1], spec.pitch[2] end
        if spec.no_gun then r.bLimitAmmo, r.AmmoCount = true, 0 end   -- ((2026-11-11) the laser's aim only, no gun)
    end)
    local slots, mag, speed, arcs, ammo = "?", "?", "?", "?", ""
    pcall(function()
        local _, r = dtCall(fcs, "FindRow", spec.fcs)
        slots, mag = tostring(r.SlotNum), tostring(r.MagazineCapacity)
        speed = tostring(r.YawSpeed) .. "/" .. tostring(r.PitchSpeed)
        arcs = string.format("yaw %s..%s, pitch %s..%s", tostring(r.YawAngleMin), tostring(r.YawAngleMax),
            tostring(r.PitchAngleMin), tostring(r.PitchAngleMax))
        if spec.no_gun then ammo = string.format(", ammo limited %s, %s rounds (no gun)", tostring(r.bLimitAmmo), tostring(r.AmmoCount)) end
    end)
    log(string.format("tanicorn: fire control row %s from %s: %s (SlotNum %s, magazine %s, yaw / pitch speed %s, %s%s)",
        spec.fcs, spec.fcs_src, okF and "in" or ("NOT made: " .. tostring(whyF)), slots, mag, speed, arcs, ammo))
    return okF
end

local function rowsIn()                                  -- the model first: the row names it (as FISH.setup)
    if T.rows then return true, "in already" end
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows)
    local mt, mr = loadObject(ACE.model_table), loadObject(ACE.model_rows)
    if not (npc and mine and mt and mr) then return false, "the row tables didn't load" end
    for _, t in ipairs({ npc, mine, mt, mr }) do pin(t, nameOf(t)) end
    local function addRow(dst, src, row)
        local _, have = dtCall(dst, "FindRow", row)
        if have == nil then
            local _, r = dtCall(src, "FindRow", row)
            if r == nil then return false end
            dtCall(dst, "AddRow", row, r)
            _, have = dtCall(dst, "FindRow", row)
        end
        return have ~= nil
    end
    -- each mount's fire control row first (its NPC row names it): the T5's (the stock flak gun's NPC_FCS_FlakGun000 with the
    -- twin mount's two muzzles) and (0.74.61) the other three's (TANI.mounts)
    local fcs = loadObject(FCS_TABLE)
    if fcs then
        pin(fcs, nameOf(fcs))
        for _, k in ipairs(KINDS) do fcsRow(fcs, k) end
    end
    local m = addRow(mt, mr, TANI.model)
    local n = addRow(npc, mine, TANI.npc)
    local hm = addRow(mt, mr, TANI.hull.model)               -- (0.74.60) the hull's
    local hn = addRow(npc, mine, TANI.hull.npc)
    local more, allIn = {}, true                             -- (0.74.61) the other mounts'
    for _, k in ipairs(TANI.mounts) do
        local km = addRow(mt, mr, k.model)
        local kn = addRow(npc, mine, k.npc)
        allIn = allIn and km and kn
        more[#more + 1] = string.format("%s %s, %s %s", k.model, km and "in" or "NOT added", k.npc, kn and "in" or "NOT added")
    end
    if type(SV_SetText) == "function" then
        pcall(SV_SetText, TANI.name_key, TANI.name)
        pcall(SV_SetText, TANI.hull.name_key, TANI.hull.name)
        for _, k in ipairs(TANI.mounts) do pcall(SV_SetText, k.name_key, k.name) end
    end
    T.rows = m and n and hm and hn and allIn
    return T.rows, string.format("%s %s, %s %s; %s %s, %s %s; %s", TANI.model, m and "in DT_NPC_Model" or "NOT added", TANI.npc,
        n and "in DT_NPC" or "NOT added", TANI.hull.model, hm and "in" or "NOT added", TANI.hull.npc, hn and "in" or "NOT added",
        table.concat(more, "; "))
end

-- (0.74.46) the rows at the main menu, as the shoal's (FISH.setup): 0.74.43-0.74.45 added them at the key press, after
-- the level was up, and the spawner made the unit with no object in it ("up, 0 aircraft") although the rows were in
function TANI.setup()
    if TANI.setupDone or not gameInstance() then return end
    TANI.tries = (TANI.tries or 0) + 1
    local ok, why = rowsIn()
    if ok or TANI.tries >= 20 then
        TANI.setupDone = true
        log("tanicorn: rows at the main menu: " .. why)
    end
end

-- our cooked class, loaded by itself: whether AC8 takes it, and what its defaults hold (k: a mount type, KINDS)
local function classCheck(k)
    local cls, why = loadObject(k.class_path)
    if not cls then return "NOT loaded: " .. tostring(why) end
    pin(cls, "tanicorn class " .. k.key)
    local parts = { "loaded " .. nameOf(cls) }
    local cdo = StaticFindObject(k.cdo_path)
    if valid(cdo) then
        local arms, mesh, dmg = "?", "?", "?"
        pcall(function() arms = tostring(#cdo.FireControlSystemComponent.AllArms) end)
        pcall(function() dmg = tostring(valid(cdo.DamagedStateComponent)) end)
        pcall(function() mesh = cdo.FireControlSystemComponent.AllArms[1].LauncherModule.MeshComponentName:ToString() end)
        parts[#parts + 1] = string.format("defaults: fire control arms %s, launcher mesh %s, damage state %s", arms, mesh, dmg)
    else
        parts[#parts + 1] = "its defaults object not found"
    end
    return table.concat(parts, "; ")
end

local function at(o)
    local ok, l = pcall(function() return o:K2_GetActorLocation() end)
    return ok and l and string.format("(%.0f, %.0f, %.0f)", l.X, l.Y, l.Z) or "?"
end

local function describe(list)
    local out = {}
    for _, o in ipairs(list) do
        local cls = "?"
        pcall(function() cls = o:GetClass():GetFName():ToString() end)
        out[#out + 1] = string.format("%s [%s] at %s%s", (nameOf(o):match("([^%.:]+)$")) or "?", cls, at(o),
            liveObj(o) and "" or " (gone)")
    end
    return #out > 0 and table.concat(out, "; ") or "nothing"
end

-- (0.74.51) a bone or socket of the turret mesh in the world: "yaw/pitch" degrees, or "(x, y, z) yaw/pitch" with its
-- place. GetBoneRotationByName handed back no Yaw in the user's run of 0.74.50 ("yaw ? pitch ?"); a skinned mesh's
-- GetSocketRotation / GetSocketLocation take a bone name as well as a socket's.
-- (0.74.54) the turret mesh from the actor's component tree (SPC.V.comps, as the ZFA-44 test reads its sockets):
-- o.TurretPoseableMesh gave rotators with no Yaw for bones and sockets alike (the user's runs of 0.74.50-0.74.53)
local function turretMesh(o)
    local m
    if SPC and SPC.V and SPC.V.comps then
        pcall(function() m = SPC.V.comps(o, "/Script/Engine.PoseableMeshComponent")[1] end)
    end
    return m or o.TurretPoseableMesh
end

-- (0.74.54) what the engine sees of a mount's muzzle (0.74.50-0.74.53: every shell, AA stream or flak, left the turret
-- mesh's origin, under the mount, along its forward: SOC_Gun_01 never found): the mesh, its asset (and the deprecated
-- SkeletalMesh field), the asset's sockets, whether the component knows SOC_Gun_01, its bone, and where it puts it
-- against the mesh's origin (at the barrels' tips: ~ +10 m forward, +4 m up; at (0, 0, 0): not found)
local MUZZLE = "SOC_Gun_01"
local function muzzleProbe(m)
    local out = {}
    local function try(label, f)
        local ok, v = pcall(f)
        out[#out + 1] = label .. " " .. (ok and tostring(v) or ("? (" .. tostring(v):sub(1, 80) .. ")"))
    end
    try("mesh", function() return nameOf(m):match("([^%.:]+)$") end)
    try("asset", function() return nameOf(m.SkinnedAsset):match("([^%.]+)$") end)
    try("old field", function() return valid(m.SkeletalMesh) and nameOf(m.SkeletalMesh):match("([^%.]+)$") or "empty" end)
    try("asset sockets", function() return m.SkinnedAsset:NumSockets() end)
    try("asset finds " .. MUZZLE, function() return valid(m.SkinnedAsset:FindSocket(FName(MUZZLE))) end)
    try("component has it", function() return m:DoesSocketExist(FName(MUZZLE)) end)
    try("its bone", function() return m:GetSocketBoneName(FName(MUZZLE)):ToString() end)
    try("at", function()
        local l, c = m:GetSocketLocation(FName(MUZZLE)), m:K2_GetComponentLocation()
        return string.format("(%+.0f, %+.0f, %+.0f) cm from the mesh's origin", l.X - c.X, l.Y - c.Y, l.Z - c.Z)
    end)
    try("names", function()
        -- ((2026-11-11) a plain Lua table from UE4SS here, not a TArray: the user's run of 0.74.61, ":ForEach" "attempt to call")
        local t, list = {}, m:GetAllSocketNames()
        local function add(e)
            local okS, s = pcall(function() return e:ToString() end)
            if not okS then okS, s = pcall(function() return e:get():ToString() end) end
            t[#t + 1] = okS and s or tostring(e)
        end
        if type(list) == "table" then for _, e in ipairs(list) do add(e) end
        else list:ForEach(function(_, e) add(e) end) end
        return #t > 0 and table.concat(t, ",") or "none"
    end)
    return table.concat(out, "; ")
end

-- the same of the first stock turret mesh in the level with that muzzle (the airfield's guns), once a spawn: the
-- difference between ours and a stock one the game fires from
local function stockProbe(o)
    local me = addrOf(o)
    local n = 0
    for _, m in ipairs(FindAllOf("PoseableMeshComponent") or {}) do
        n = n + 1
        if n > 400 then break end
        local ok, has = pcall(function()
            local ow = m:GetOwner()
            return valid(ow) and addrOf(ow) ~= me and not nameOf(ow):find("Tani", 1, true) and m:DoesSocketExist(FName(MUZZLE))
        end)
        if ok and has then
            local owner = "?"
            pcall(function() owner = nameOf(m:GetOwner()):match("([^%.:]+)$") end)
            return owner .. ": " .. muzzleProbe(m)
        end
    end
    return string.format("none with %s among %d turret meshes", MUZZLE, n)
end

local function heading(dx, dy, dz)                      -- yaw / pitch (degrees) of a direction
    return math.deg(math.atan(dy, dx)), math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
end

-- (0.74.55) where the barrels point and where the muzzle is, from positions alone: 0.74.54's probe read socket places
-- right (SOC_Gun_01 at the barrel's tip) while every rotation read gave no Yaw. The barrel = turret_pitch -> SOC_Gun_01.
local function aim(o)
    local ok, r, t = pcall(function()
        local m = turretMesh(o)
        local ml = o:K2_GetActorLocation()
        local p, q = m:GetSocketLocation(FName("BN_turret_pitch")), m:GetSocketLocation(FName(MUZZLE))
        local y, pt = heading(q.X - p.X, q.Y - p.Y, q.Z - p.Z)
        return string.format("barrel yaw %.1f pitch %.1f, muzzle (%+.0f, %+.0f, %+.0f) from the mount", y, pt,
            q.X - ml.X, q.Y - ml.Y, q.Z - ml.Z), { x = q.X - ml.X, y = q.Y - ml.Y, z = q.Z - ml.Z, yaw = y, pitch = pt }
    end)
    if ok then return r, t end
    if not T.aimErr then T.aimErr = true; log("tanicorn: reading the barrel failed: " .. tostring(r)) end
    return "barrel ?"
end

-- (0.74.55) every flak shell the game makes while a mount is watched (NotifyOnNewObject, as ALLY's ESM fields: the actor
-- at its construction, before it has a place), then at the next tick its place and velocity run back over its age to
-- where it started, against the mount and its muzzle at that moment. The user's runs of 0.74.50-0.74.54: the fire "from
-- below the mount" while the engine puts SOC_Gun_01 at the barrel's tip: this is where the game actually starts it.
-- (0.74.56) every flak gun the game makes, ours or a stock one (the Spaceport island's GR023s: Ctrl+END), for the first
-- 12 of each a session: its owner, where it sits against its owner, and where it says it hangs (ALiveAttachedWeapon's
-- AttachedComponent / AttachedSocketName / bIsBaseAttached). 0.74.55 showed ours sitting at the mount's origin to the
-- centimetre with no velocity: LiveFlakGun is an ALiveAttachedWeapon, the bursts come from where it hangs.
-- (0.74.61) and the other mounts' weapons as they're made: the T16's artillery shells (LiveArtillery, a shell in flight, not
-- attached: its start comes from its place and velocity) and the CIWS / LASER's gun (BP_wp_ciws_vessel, a
-- LiveAttachedInterceptorWeapon: it hangs where the flak gun does, its socket the line to read)
local NEWSHELL = {}
local SHELL_CLASSES = { "/Script/Live.LiveFlakGun", "/Script/Live.LiveArtillery", "/Script/Live.LiveAttachedInterceptorWeapon" }
if type(NotifyOnNewObject) == "function" then
    for _, c in ipairs(SHELL_CLASSES) do
        local short = c:match("Live%.(.+)$")
        pcall(NotifyOnNewObject, c, function(o)
            if #NEWSHELL < 32 then NEWSHELL[#NEWSHELL + 1] = { o = o, t = os.clock(), c = short } end
        end)
    end
end

local function hangs(w)                                   -- an attached weapon's own record of where it hangs
    local comp, owner, sock, base = "?", "?", "?", "?"
    pcall(function()
        local c = w.AttachedComponent
        if valid(c) then
            comp = c:GetFName():ToString()
            pcall(function() owner = (nameOf(c:GetOwner()):match("([^%.:]+)$")) or "?" end)
        else
            comp = "none"
        end
    end)
    pcall(function() sock = w.AttachedSocketName:ToString() end)
    pcall(function() base = tostring(w.bIsBaseAttached) end)
    return string.format("hangs on %s (of %s) at socket %s, base attached %s", comp, owner, sock, base)
end

-- (0.74.61) the first 12 of each weapon class (s.c) a session that aren't ours
local function stockShells(list, now)
    for _, s in ipairs(list) do
        pcall(function()
            local o = s.o
            if not valid(o) then return end
            local ow = o:GetOwner()
            if valid(ow) and nameOf(ow):find("Tani", 1, true) then return end
            local c = s.c or "?"
            T.stock[c] = (T.stock[c] or 0) + 1
            if T.stock[c] > 12 then return end
            local l, ol = o:K2_GetActorLocation(), valid(ow) and ow:K2_GetActorLocation()
            log(string.format("tanicorn: a stock %s %d (%s): at (%+.0f, %+.0f, %+.0f) from its owner %s; %s",
                c, T.stock[c], (nameOf(o):match("([^%.:]+)$")) or "?", ol and l.X - ol.X or 0, ol and l.Y - ol.Y or 0,
                ol and l.Z - ol.Z or 0, valid(ow) and ((nameOf(ow):match("([^%.:]+)$")) or "?") or "none", hangs(o)))
        end)
    end
end

-- (0.74.61) each of our shells against the mount that made it (its owner; 0.74.55-0.74.60's the first T5 found), the first 12
-- of each mount type a spawn: `tanicorn: <T5|T16|CIWS|LASER> shell N: ...`
local function shells(now)
    if #NEWSHELL == 0 then return end
    local list = NEWSHELL
    NEWSHELL = {}
    stockShells(list, now)
    local aims, all = {}, nil
    for _, s in ipairs(list) do
        local mount, k
        pcall(function()
            local ow = s.o:GetOwner()
            if valid(ow) and nameOf(ow):find("Tani", 1, true) then mount = ow end
        end)
        if mount then
            k = kindOf(mount)
            if not k then                                -- (its owner isn't a mount itself: the first of ours, as before)
                all = all or ours()
                if all[1] then mount, k = all[1].o, all[1].k else mount = nil end
            end
        end
        if mount and k then
            T.shells[k.key] = (T.shells[k.key] or 0) + 1
            local nth = T.shells[k.key]
            local id = addrOf(mount) or tostring(mount)
            if nth <= 12 and aims[id] == nil then
                local _, a = aim(mount)
                local ml
                pcall(function() ml = mount:K2_GetActorLocation() end)
                aims[id] = { a = a, ml = ml }
            end
            local here = aims[id]
            if nth <= 12 and here and here.ml then
                local a, ml = here.a, here.ml
                local ok, line = pcall(function()
                    local l, v = s.o:K2_GetActorLocation(), s.o:GetVelocity()
                    local age = now - s.t
                    local sx, sy, sz = l.X - v.X * age - ml.X, l.Y - v.Y * age - ml.Y, l.Z - v.Z * age - ml.Z
                    local y, pt = heading(v.X, v.Y, v.Z)
                    return string.format("shell %d (%s): started (%+.0f, %+.0f, %+.0f) from the mount, flying yaw %.1f pitch %.1f at %.0f m/s " ..
                        "(seen %.2f s after it was made, now (%+.0f, %+.0f, %+.0f)); the muzzle (%s), the barrel yaw %s pitch %s; %s",
                        nth, s.c or "?", sx, sy, sz, y, pt, math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) / 100, age,
                        l.X - ml.X, l.Y - ml.Y, l.Z - ml.Z,
                        type(a) == "table" and string.format("%+.0f, %+.0f, %+.0f", a.x, a.y, a.z) or "?",
                        type(a) == "table" and string.format("%.1f", a.yaw) or "?", type(a) == "table" and string.format("%.1f", a.pitch) or "?",
                        hangs(s.o))
                end)
                log("tanicorn: " .. k.key .. " " .. (ok and line or ("a shell, not read: " .. tostring(line))))
            end
        end
    end
end

-- (0.74.46) the class spawned straight, as AC7's laser is (sv_escort_li.lua): BeginDeferredActorSpawnFromClass +
-- FinishSpawningActor, AlwaysSpawn, no owner: whether our blueprint comes up as an actor at all, apart from the spawner
local function direct(x, y, face)
    local cls = loadObject(TANI.class_path)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (cls and valid(gs) and liveObj(survivalPC)) then return nil, "no class / GameplayStatics / player controller" end
    local h = math.rad(face) / 2
    local t = { Rotation = { X = 0, Y = 0, Z = math.sin(h), W = math.cos(h) }, Translation = { X = x, Y = y, Z = TANI.z_cm },
                Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, a = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)
    if not (okB and a and valid(a)) then return nil, "deferred spawn: " .. tostring(a) end
    local okF, fin = pcall(function() return gs:FinishSpawningActor(a, t, 1) end)
    if not (okF and valid(a)) then return nil, "not finished: " .. tostring(fin) end
    return a, "spawned " .. nameOf(a)
end

-- a spawn's look 1 s and 4 s on (c: { tag, made, k: its mount type, x, y: its spot })
local function look(c)
    local k = c.k or TANI
    local alive = type(SV_UnitAlive) == "function" and SV_UnitAlive(k.unit) or "?"
    local n = 0
    for _, o in ipairs(FindAllOf(k.class) or {}) do
        if valid(o) and not nameOf(o):find("Default__", 1, true) then n = n + 1 end
    end
    local dummies = 0
    if FISH and FISH.findNear and c.x then dummies = #FISH.findNear(TANI.dummy, c.x, c.y, 100000) end
    log(string.format("tanicorn: %s %s: SV_UnitAlive %s; the spawn's objects: %s; %d of our class in the level, %d stock dummies near the spot",
        k.key, c.tag, tostring(alive), describe(c.made), n, dummies))
end

-- (0.74.61) a mount's fire control arms: how many, and each one's name and launcher (the row's arm, BP_FCS_..._C, in place of
-- the blueprint's own LiveFireControlSystemArms when the row took: 0.74.59)
local function armsOf(o)
    local n, names = "?", {}
    pcall(function()
        local arms = o.FireControlSystemComponent.AllArms
        n = tostring(#arms)
        for i = 1, #arms do
            local a, launcher = arms[i], "?"
            pcall(function() launcher = a.LauncherModule:GetClass():GetFName():ToString() end)
            names[#names + 1] = (valid(a) and ((nameOf(a):match("([^%.:]+)$")) or "?") or "none") .. " / " .. launcher
        end
    end)
    return n .. (#names > 0 and (" (" .. table.concat(names, ", ") .. ")") or "")
end

-- (2026-11-11) the LASER mounts carry AC7's LaserInterceptor (the user: "the LASERS have to be Laser Interceptors"), as
-- the ZFA-44s do: handed to sv_escort_li.lua through ZLI.extra, its laser at the mount's muzzle (TurretPoseableMesh's
-- SOC_Gun_01, where the CIWS gun hung in the user's run of 0.74.61) and on the players' missiles (foe "players": the
-- missiles sv_ladon.lua keeps in HIT.minePool while HIT.wantMine; on from here, so a pool made early is kept too).
-- Each kept mount checked against the name it was captured with before it's handed over (hard rule 59).
-- Logged: `tanicorn: LASER mount <name> handed to AC7's LaserInterceptor ...`, then sv_escort_li.lua's `zfa li: ...`
-- (`... carries AC7's LaserInterceptor: ... at SOC_Gun_01`, `... fires a volley`, `... swings onto ...`, `... shot down`)
if HIT then HIT.wantMine = true end
T.li = {}
local function liCarriers()
    local out = {}
    for a, e in pairs(T.li) do
        if liveAddr(e.o) ~= a or nameOf(e.o) ~= e.name then
            T.li[a] = nil                                -- (gone, or another object at its address)
        else
            if not valid(e.body) then e.body = turretMesh(e.o) end
            out[#out + 1] = { o = e.o, a = a, unit = e.k.unit, body = e.body, socket = MUZZLE, foe = "players" }
        end
    end
    return out
end
local function liCarry(o, k)
    local a = addrOf(o)
    if not a or T.li[a] then return end
    T.li[a] = { o = o, name = nameOf(o), k = k, body = turretMesh(o) }
    if HIT then HIT.wantMine = true end
    if ZLI then ZLI.extra = liCarriers end
    local on = ZLI and ZLI.on and ZLI.on()
    local mine = 0
    for _ in pairs((HIT and HIT.minePool) or {}) do mine = mine + 1 end
    log(string.format("tanicorn: %s mount %s handed to AC7's LaserInterceptor (sv_escort_li.lua's `zfa li:` lines; your "
        .. "missiles known so far %d)%s", k.key, (nameOf(o):match("([^%.:]+)$")) or "?", mine,
        on and "" or string.format(": its laser is NOT on (mode %s: a ZFA=1 build's main menu turns it on)", tostring(ZLI and ZLI.mode))))
end

local function watch(now)
    for i = #T.checks, 1, -1 do                          -- the 1 s and 4 s looks after a spawn
        local c = T.checks[i]
        if now >= c.at then table.remove(T.checks, i); look(c) end
    end
    shells(now)                                          -- (every tick: the shells made since the last)
    if now > T.until_ or now < T.next then return end
    T.next = now + TANI.every_s
    for _, e in ipairs(ours()) do                        -- (0.74.61) every mount type's, a line each
        local o, k = e.o, e.k
        local h, mx = "?", "?"
        pcall(function() h = o.HealthInternal end)
        pcall(function() mx = o.MaxHealth end)
        local id = addrOf(o)
        if id and not T.seen[id] then
            T.seen[id] = true
            log(string.format("tanicorn: %s mount %s up at %s: fire control arms %s, health %s/%s", k.key, nameOf(o), at(o),
                armsOf(o), tostring(h), tostring(mx)))
            log("tanicorn: " .. k.key .. " muzzle: " .. muzzleProbe(turretMesh(o)))
            if k.li then liCarry(o, k) end               -- ((2026-11-11) the LASER: AC7's LaserInterceptor)
            if not T.stockSaid then                      -- (once a key press: the same for every mount)
                T.stockSaid = true
                log("tanicorn: a stock turret's muzzle: " .. stockProbe(o))
            end
        end
        local ay = "?"
        pcall(function() ay = string.format("%.1f", o:K2_GetActorRotation().Yaw) end)
        log(string.format("tanicorn: %s %s hp %s/%s actor yaw %s, %s", k.key, (nameOf(o):match("([^%.:]+)$")) or "?",
            tostring(h), tostring(mx), ay, (aim(o))))
    end
end

-- the yaw you're flying (degrees), 0 when it can't be read
local function playerYaw()
    local yaw = 0
    pcall(function()
        local pc = liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController")
        yaw = pc.Pawn:K2_GetActorRotation().Yaw
    end)
    return yaw
end

-- one mount (k: a mount type) spawned through Survival's rows at (x, y) on the sea facing `face`, through the shoals' spawn
-- capture: -> SV_Spawn's result, the objects the spawn made
local function spawnMount(k, x, y, face)
    local r
    if FISH and FISH.spawn then r = FISH.spawn(k.unit, x, y, TANI.z_cm, face) else r = SV_Spawn(k.unit, x, y, TANI.z_cm, face) end
    local list = {}
    for _, o in ipairs((FISH and FISH.actors and FISH.actors[k.unit]) or {}) do list[#list + 1] = o end
    return tonumber(r) or -5, list
end

testKey("T", "sv_tanicorn.lua's mount test", function()
    if not (D and D.now) or not nativeReady() then log("tanicorn: Ctrl+T outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("tanicorn: Ctrl+T: the host spawns it (you're a joiner)"); return end
    log("tanicorn: class " .. classCheck(TANI))
    local ok, why = rowsIn()
    log("tanicorn: rows: " .. why)
    local p = playerLocation()
    if not p then log("tanicorn: no player location"); return end
    local yaw = playerYaw()
    local x = p.X + math.cos(math.rad(yaw)) * TANI.ahead_cm
    local y = p.Y + math.sin(math.rad(yaw)) * TANI.ahead_cm
    local face = (yaw + 180) % 360
    local r, list = spawnMount(TANI, x, y, face)
    local said = r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")")
    log(string.format("tanicorn: Ctrl+T, %s at (%.0f, %.0f, %d) facing %.0f: %s%s", TANI.unit, x, y, TANI.z_cm, face,
        said, ok and "" or " (its rows aren't all in)"))
    log("tanicorn: the spawn made " .. describe(list))
    if #list == 0 then                                    -- (the spawner made none: our class straight, beside the spot)
        local d, whyD = direct(x + 30000, y, face)
        log("tanicorn: straight spawn of our class 300 m from the spot: " .. whyD)
        if d then list[#list + 1] = d end
    end
    hudCallout("TEST: TANICORN MOUNT", r > 0 and "3 KM AHEAD" or "NOT SPAWNED")
    local now = os.clock()
    T.checks[#T.checks + 1] = { at = now + 1, tag = "+1 s", made = list, k = TANI, x = x, y = y }
    T.checks[#T.checks + 1] = { at = now + 4, tag = "+4 s", made = list, k = TANI, x = x, y = y }
    T.next, T.until_, T.shells[TANI.key], T.stockSaid = 0, now + TANI.watch_s, 0, nil
end)

-- (0.74.61) Ctrl+U: the other three mounts (TANI.mounts: T16, CIWS, LASER), each on its own rows and fire control row, 3 km
-- ahead (ahead_cm) in a row across your path, mount_gap_cm apart (the T16 on your left, the LASER on your right), each facing
-- you. Logged as the T5's, each line naming its mount: `tanicorn: <part> class loaded ...`, `tanicorn: Ctrl+U, <unit> (<part>)
-- at (x, y, z) facing F: 1 up`, `tanicorn: <part> +1 s / +4 s: ...`, and while they're up (watch_s) `tanicorn: <part> mount
-- ... up at ...: fire control arms 1 (<the row's arm> / LiveFCSModule_LauncherBoneControl)`, `tanicorn: <part> muzzle: ...`,
-- the 2 s lines `tanicorn: <part> <name> hp ... barrel yaw ... pitch ...` and `tanicorn: <part> shell N (<class>): ...
-- hangs on TurretPoseableMesh ... at socket SOC_Gun_0N`
testKey("U", "sv_tanicorn.lua's mounts test", function()
    if not (D and D.now) or not nativeReady() then log("tanicorn: Ctrl+U outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("tanicorn: Ctrl+U: the host spawns them (you're a joiner)"); return end
    for _, k in ipairs(TANI.mounts) do log("tanicorn: " .. k.key .. " class " .. classCheck(k)) end
    local ok, why = rowsIn()
    log("tanicorn: rows: " .. why)
    local p = playerLocation()
    if not p then log("tanicorn: no player location"); return end
    local yaw = playerYaw()
    local fx, fy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    local cx, cy = p.X + fx * TANI.ahead_cm, p.Y + fy * TANI.ahead_cm
    local face = (yaw + 180) % 360
    local now, up, n = os.clock(), {}, #TANI.mounts
    for i, k in ipairs(TANI.mounts) do
        local off = (i - (n + 1) / 2) * TANI.mount_gap_cm    -- (across your path: -gap, 0, +gap; + is your right)
        local x, y = cx - fy * off, cy + fx * off
        local r, list = spawnMount(k, x, y, face)
        local said = r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")")
        log(string.format("tanicorn: Ctrl+U, %s (%s) at (%.0f, %.0f, %d) facing %.0f: %s%s; the spawn made %s", k.unit, k.key,
            x, y, TANI.z_cm, face, said, ok and "" or " (its rows aren't all in)", describe(list)))
        if r > 0 then up[#up + 1] = k.key end
        T.checks[#T.checks + 1] = { at = now + 1, tag = "+1 s", made = list, k = k, x = x, y = y }
        T.checks[#T.checks + 1] = { at = now + 4, tag = "+4 s", made = list, k = k, x = x, y = y }
        T.shells[k.key] = 0
    end
    hudCallout("TEST: TANICORN MOUNTS", #up > 0 and (table.concat(up, ", ") .. " 3 KM AHEAD") or "NOT SPAWNED")
    T.next, T.until_, T.stockSaid = 0, now + TANI.watch_s, nil
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn mount watch", fn = watch }

-- (0.74.60) Ctrl+Y: THE TANACORN's hull with every part drawn on its socket (BP_SV_Tani_HULL), broadside to you hull.ahead_cm
-- out, its waterline on the sea. Logged: our class loaded, the spawn, and 2 s and 8 s on where it is and how many of its
-- parts' meshes it carries (PoseableMeshComponents: 32 expected, 2 + 6 + 4 + 4 + 16) and its static meshes (the hull's).
local function hullLook(tag)
    local H = TANI.hull
    local found = {}
    for _, o in ipairs(FindAllOf(H.class) or {}) do
        if valid(o) and not nameOf(o):find("Default__", 1, true) then found[#found + 1] = o end
    end
    if #found == 0 then log(string.format("tanicorn: hull %s: none of our class in the level", tag)); return end
    for _, o in ipairs(found) do
        local parts, statics = "?", "?"
        if SPC and SPC.V and SPC.V.comps then
            pcall(function() parts = #SPC.V.comps(o, "/Script/Engine.PoseableMeshComponent") end)
            pcall(function() statics = #SPC.V.comps(o, "/Script/Engine.StaticMeshComponent") end)
        end
        local ay = "?"
        pcall(function() ay = string.format("%.1f", o:K2_GetActorRotation().Yaw) end)
        log(string.format("tanicorn: hull %s: %s at %s facing %s: %s part meshes, %s static meshes", tag,
            (nameOf(o):match("([^%.:]+)$")) or "?", at(o), ay, tostring(parts), tostring(statics)))
    end
end

testKey("Y", "sv_tanicorn.lua's hull test", function()
    if not (D and D.now) or not nativeReady() then log("tanicorn: Ctrl+Y outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("tanicorn: Ctrl+Y: the host spawns it (you're a joiner)"); return end
    local H = TANI.hull
    local cls, why = loadObject(H.class_path)
    log("tanicorn: hull class " .. (cls and ("loaded " .. nameOf(cls)) or ("NOT loaded: " .. tostring(why))))
    if cls then pin(cls, "tanicorn hull class") end
    local ok, rows = rowsIn()
    log("tanicorn: rows: " .. rows)
    local p = playerLocation()
    if not p then log("tanicorn: no player location"); return end
    local yaw = 0
    pcall(function()
        local pc = liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController")
        yaw = pc.Pawn:K2_GetActorRotation().Yaw
    end)
    local x = p.X + math.cos(math.rad(yaw)) * H.ahead_cm
    local y = p.Y + math.sin(math.rad(yaw)) * H.ahead_cm
    local face = (yaw + 90) % 360                         -- (broadside to you: her whole length in view)
    local r
    if FISH and FISH.spawn then r = FISH.spawn(H.unit, x, y, H.z_cm, face) else r = SV_Spawn(H.unit, x, y, H.z_cm, face) end
    local said = r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")")
    log(string.format("tanicorn: Ctrl+Y, %s at (%.0f, %.0f, %d) facing %.0f: %s%s", H.unit, x, y, H.z_cm, face, said,
        ok and "" or " (its rows aren't all in)"))
    hudCallout("TEST: TANACORN", r > 0 and "5 KM AHEAD" or "NOT SPAWNED")
    T.hullChecks = { { at = os.clock() + 2, tag = "+2 s" }, { at = os.clock() + 8, tag = "+8 s" } }
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn hull look", fn = function(now)
    if not T.hullChecks then return end
    for i = #T.hullChecks, 1, -1 do
        local c = T.hullChecks[i]
        if now >= c.at then table.remove(T.hullChecks, i); hullLook(c.tag) end
    end
    if #T.hullChecks == 0 then T.hullChecks = nil end
end }

-- (2026-11-11) Ctrl+R: THE TANACORN rises on her rig (WP4's route B2: docs/design/INVINCIBLE_FLEET_RISE_FORD.md 2.3, 3 and
-- 5's T3). The hull as Ctrl+Y spawns it, broadside rise.ahead_cm out; its RiseRig (BP_SV_Tani_HULL's first component: our
-- three-bone SK_SV_Tani_RIG, HullMesh on its SOC_Hull, every part on HullMesh) scrubbed to 0 (the whole ship 130 m under
-- the sea), after hold_s played at rate (0.74.64: her surfacing shot's motion): the bow out at 0.8 s along her own axis at
-- 35 deg, standing 120 m over the water at 5 s, the hang, her bow down about where she stands in the water, the slam at 9 s,
-- the settle, at rest at 15 s (AS_SV_Tani_RIG_Rise's end: her spot on the water). With cinematic: your view on a camera
-- actor (spawned from Lua, else SV_SpawnCam) on the rig's SOC_Cam (its keys in the same animation, low off her port bow), your plane
-- invincible, flown round where you are by the runtime's loiter autopilot (SV_Down), the enemies' attack limits on you at
-- 0; all put back after (and at a second Ctrl+R, the run's end or the hull gone). At breach_s the Alicorn's surfacing plume
-- and sound at the bow, at slam_s AC8's vessel foam and splashes along her keel line and a shake. The times are the rig's
-- own position (GetPosition), the clock if it can't be read. Logged: `tanicorn: Ctrl+R, ...`, `tanicorn: rise: RiseRig found
-- (...)`, every every_s `tanicorn: rise +T s: hull at z Z m, bow socket (x, y, z) m, stern socket (x, y, z) m, pitch P, the
-- bow's tip ~B m; Part_T16_FWD z m` (positions from her spawn point; the pitch from the two sockets: rotators read no Yaw
-- from Lua, 0.74.55), `tanicorn: rise cinematic: ...`, `tanicorn: rise over: ...`.
-- If the hull never moves while the rig plays: its bone doesn't move what hangs on it (the plan's risk 1): the log's
-- VisibilityBasedAnimTickOption read-back says whether the blueprint's value took.
-- ((0.74.64) the user on 0.74.63's rise: "the rise worked but it was waaay to high up and there was no VFX's with it": the
-- rig now plays her surfacing shot's motion (35 deg, the bow 120 m up at 5 s, the slam at 9 s, at rest at 15 s:
-- export_tanacorn.py surf_pose); the effects spawn with no pre-cull (0.74.63's "26 of 26 up" counted calls: the cull check
-- at 2.2 km may have handed back nothing) and each one counted only when it came back; the camera spawned from Lua
-- (SV_SpawnCam answers -1 solo: it needs co-op's own plane))
TANI.rise = { hold_s = 1.5, rate = 1.0, breach_s = 0.8, slam_s = 9.0, length_s = 15.0, cinematic = true, blend_s = 1.0,
              cam_fov = 55, autopilot_alt_m = 1500, autopilot_radius_m = 3500, every_s = 0.5, ahead_cm = 500000, find_s = 10,
              end_pad_s = 1.0,
              breach_m = 115.8,                          -- (where her axis stands in the sea: from her rest midships, forward)
              spray_s = 0.5, spray_scale = 1.5,          -- (the sea off her where she stands in the water, rising and falling)
              fx_scale = 1.5,                            -- (the Ford's effects, for a 333 m ship, on her 650 m)
              bow_x_m = 324.8,                           -- (the bow's tip from midships: tools/tanicorn's hull export)
              -- the two hull sockets the pitch is measured between, and their rest angle (deg: the hull's json, UE cm)
              bow_socket = "Mount_RAILCANNON", stern_socket = "Mount_VLSD_8", rest_pitch = math.deg(math.atan(-691.8 - 991.4, 12590.4 + 26400.0)),
              part = "Part_T16_FWD",
              anim = "/Game/Mods/SurvivalMode/Tanicorn/Model/AS_SV_Tani_RIG_Rise",
              -- (the Alicorn's own four surfacing systems, all at once where she breaks the surface)
              breach_fx = { "/Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/NS_ex03_alcn_surfacing01_ON",
                            "/Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/NS_ex03_alcn_surfacing02_ON",
                            "/Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/NS_ex03_alcn_surfacing03_ON",
                            "/Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/NS_ex03_alcn_surfacing04_ON" },
              breach_sound = "/Game/WwiseAssets/BA002_alcn/AKE_BA002_alcn_Surface_Play",
              spray_fx = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsWaveSplashL001",
              foam_fx = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsWaveFoamXL001",
              slam_fx = { "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsWaveFoamXL001",
                          "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsWaveSplashL001" },
              -- (the Ford's death's water pillars, either side of her forebody at the slam: x forward of midships, y across)
              pillar_fx = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsPillarL001",
              pillars = { { 100, -60 }, { 100, 60 }, { 200, -55 }, { 200, 55 }, { 280, -40 }, { 280, 40 } },
              slam_spots = 13, shake = "/Game/Blueprints/Vehicle/PLAYER/Camera/CameraShake/BP_CamShake_BombImpactHelios",
              shake_km = 8 }
local RISE_ATTACKERS = { "MaxPlaneAttackerMissiles", "MaxPursuitAttackers", "MaxNonPlaneAttackerMissiles" }   -- (sv_down.lua's)
local RA = {}
local function riseAsset(path, cls)                      -- an asset by path (a blueprint's class with cls), kept
    local full = path .. "." .. path:match("[^/]+$") .. (cls and "_C" or "")
    if RA[full] ~= nil and liveObj(RA[full]) then return RA[full] end
    local o = loadObject(full)
    RA[full] = (o ~= nil and valid(o)) and o or nil
    if RA[full] then pin(RA[full], "the rise's " .. full:match("[^%.]+$")) end
    return RA[full]
end
local function riseFx(path, where, n)                    -- an AC8 effect at a place: whether one came back, live
    local lib, sys = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary"), riseAsset(path)
    if not (valid(lib) and sys and liveObj(survivalPC)) then return false end
    -- ((0.74.64) bPreCullCheck false: with it on, the spawn may hand back nothing for a far camera, and 0.74.63 counted
    -- the calls, not what came back)
    local ok, c = pcall(function()
        return lib:SpawnSystemAtLocation(survivalPC, sys, where, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = n or 1, Y = n or 1, Z = n or 1 },
            true, true, 0, false)
    end)
    if not (ok and c) then return false end
    local okV, v = pcall(function() return c:IsValid() end)
    return okV and v == true
end
local function riseSound(path, where)
    local ev, ak = riseAsset(path), StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
    if not (ev and valid(ak) and liveObj(survivalPC)) then return false end
    local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
    if pcall(function() ak:PostEventAtLocation(ev, where, rot, survivalPC) end) then return true end
    return pcall(function() ak:PostEventAtLocation(ev, where, rot, "", survivalPC) end)
end
local function riseComp(o, cls, name)                    -- her component of that class and name
    for _, c in ipairs((SPC and SPC.V and SPC.V.comps and SPC.V.comps(o, cls)) or {}) do
        if nameOf(c):find(name, 1, true) then return c end
    end
    return nil
end
local function v3(c, f) local ok, v = pcall(f); if ok and v then return { X = v.X, Y = v.Y, Z = v.Z } end return nil end
local function riseHere(R)                               -- the rig's time: its own position, else the clock's
    local ok, p = pcall(function() return R.rig:GetPosition() end)
    if ok and type(p) == "number" and R.playing then return p end
    return R.playing and (os.clock() - R.t1) * TANI.rise.rate or 0
end
local function riseLook(R, t)
    local C = TANI.rise
    local bow = v3(R.hull, function() return R.hull:GetSocketLocation(FName(C.bow_socket)) end)
    local st = v3(R.hull, function() return R.hull:GetSocketLocation(FName(C.stern_socket)) end)
    local mid = v3(R.hull, function() return R.hull:K2_GetComponentLocation() end)
    local pt = R.part and v3(R.part, function() return R.part:K2_GetComponentLocation() end)
    local function rel(v) return v and string.format("(%.0f, %.0f, %.0f) m", (v.X - R.x) / 100, (v.Y - R.y) / 100, (v.Z - R.z) / 100) or "?" end
    local pitch, tip = "?", "?"
    if bow and st then
        local dx, dy = bow.X - st.X, bow.Y - st.Y
        local p = math.deg(math.atan(bow.Z - st.Z, math.sqrt(dx * dx + dy * dy))) - C.rest_pitch
        pitch = string.format("%.1f", p)
        if mid then
            tip = string.format("%.0f", (mid.Z - R.z) / 100 + C.bow_x_m * math.sin(math.rad(p)))
            R.top = math.max(R.top or -1e9, (mid.Z - R.z) / 100 + C.bow_x_m * math.sin(math.rad(p)))
        end
    end
    log(string.format("tanicorn: rise +%.1f s: hull at z %s m, bow socket %s, stern socket %s, pitch %s, the bow's tip ~%s m; %s z %s m",
        t, mid and string.format("%.1f", (mid.Z - R.z) / 100) or "?", rel(bow), rel(st), pitch, tip, C.part,
        pt and string.format("%.1f", (pt.Z - R.z) / 100) or "?"))
    return bow, st, mid
end
local function riseBack(R, why)                          -- your view, plane and the enemies' limits put back
    if not R or R.back then return end
    R.back = true
    local parts = {}
    local pawn = liveObj(survivalPC) and survivalPC.Pawn or nil
    if R.cine then
        if valid(pawn) then
            parts[#parts + 1] = pcall(function() survivalPC:SetViewTargetWithBlend(pawn, TANI.rise.blend_s, 0, 0, false) end)
                and "view back on your plane" or "view back FAILED"
            pcall(function() pawn:SetIsInvincible(false) end)
            for f, v in pairs(R.limits or {}) do pcall(function() pawn[f] = v end) end
        end
        if type(SV_Down) == "function" then pcall(SV_Down, 0); playerLocationDirty() end
        parts[#parts + 1] = "autopilot off, invincible off, the attack limits back"
        if R.cam then pcall(function() R.cam:K2_DestroyActor() end) end
    end
    log(string.format("tanicorn: rise over (%s): %s; %d view reverts; the bow's tip highest ~%s m", why,
        #parts > 0 and table.concat(parts, ", ") or "no cinematic", R.reverts or 0, R.top and string.format("%.0f", R.top) or "?"))
end
local function riseCine(R)                               -- the cinematic: autopilot, invincible, limits, the view
    local C, pawn = TANI.rise, liveObj(survivalPC) and survivalPC.Pawn or nil
    if not valid(pawn) then log("tanicorn: rise cinematic: no plane of yours"); return end
    local me = playerLocation()
    local alt = math.max(C.autopilot_alt_m, me and me.Z / 100 or 0)
    local okD, rD = false, "no SV_Down"
    if type(SV_Down) == "function" and me then okD, rD = pcall(SV_Down, addrOf(pawn) or 0, me.X, me.Y, alt, C.autopilot_radius_m) end
    playerLocationDirty()
    pcall(function() pawn:SetIsInvincible(true) end)
    R.limits = {}
    for _, f in ipairs(RISE_ATTACKERS) do
        local okR, v = pcall(function() return pawn[f] end)
        if okR and type(v) == "number" and pcall(function() pawn[f] = 0 end) then R.limits[f] = v end
    end
    R.cine = true
    local cam, why = nil, "no SV_Spawncam (runtime 0.32.1)"
    -- ((0.74.64) a CameraActor spawned from Lua first, as sv_escort_li.lua spawns the laser (deferred, then finished):
    -- SV_SpawnCam answered -1 in the user's solo run of 0.74.63, it finds the world through co-op's own plane)
    local gs, ccls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.CameraActor")
    if valid(gs) and valid(ccls) and me and liveObj(survivalPC) then
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = me.X, Y = me.Y, Z = me.Z + 3000 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, ccls, t, 1, nil, 1) end)
        if okB and x and valid(x) then
            pcall(function() gs:FinishSpawningActor(x, t, 1) end)
            if valid(x) then cam, why = x, "spawned from Lua" end
        else
            why = "the Lua spawn gave nothing (" .. tostring(okB and x or "error") .. ")"
        end
    end
    if not cam and type(SV_SpawnCam) == "function" and me then
        local ca = SV_SpawnCam(me.X, me.Y, me.Z + 3000)
        why = "SV_SpawnCam " .. tostring(ca)
        if type(ca) == "number" and ca > 0 then
            for _, x in ipairs(FindAllOf("CameraActor") or {}) do if valid(x) and addrOf(x) == ca then cam = x end end
        end
    end
    local att = false
    if cam then
        pcall(function() cam.CameraComponent.bConstrainAspectRatio = false end)
        pcall(function() cam.CameraComponent:SetFieldOfView(C.cam_fov) end)
        att = pcall(function() cam:K2_AttachToComponent(R.rig, FName("SOC_Cam"), 2, 2, 1, false) end)
        R.cam = cam
    end
    local okV = false
    if cam then okV = pcall(function() survivalPC:SetViewTargetWithBlend(cam, C.blend_s, 0, 0, false) end) end
    log(string.format("tanicorn: rise cinematic: %s; your plane invincible, the autopilot round (%.0f, %.0f) at %.0f m: %s; the "
        .. "attack limits at 0: %d of %d", cam and (att and "the view on the rise camera (SOC_Cam, blend " .. C.blend_s .. " s)" or
        "the camera NOT attached to SOC_Cam") .. (okV and "" or ", SetViewTargetWithBlend FAILED") or ("no camera (" .. why .. ")"),
        me and me.X or 0, me and me.Y or 0, alt, okD and tostring(rD) or ("error " .. tostring(rD)), (function()
            local n = 0; for _ in pairs(R.limits) do n = n + 1 end; return n end)(), #RISE_ATTACKERS))
end
local RISE = nil
testKey("R", "sv_tanicorn.lua's rise test", function()
    if RISE and not RISE.back then riseBack(RISE, "Ctrl+R again"); RISE = nil; return end
    if not (D and D.now) or not nativeReady() then log("tanicorn: Ctrl+R outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("tanicorn: Ctrl+R: the host spawns it (you're a joiner)"); return end
    local H, C = TANI.hull, TANI.rise
    local cls, why = loadObject(H.class_path)
    log("tanicorn: hull class " .. (cls and ("loaded " .. nameOf(cls)) or ("NOT loaded: " .. tostring(why))))
    if cls then pin(cls, "tanicorn hull class") end
    local anim = riseAsset(C.anim)
    local ok, rows = rowsIn()
    -- ((0.74.63) a hull of ours already up (Ctrl+Y's) rises where it is: its unit can't spawn again while its flight is up
    -- (hard rule 16; the user's run of 0.74.62, 22:24: every Ctrl+R after a Ctrl+Y "not spawned (its last flight is still up)")
    local before, up = {}, nil
    for _, o in ipairs(FindAllOf(H.class) or {}) do
        before[addrOf(o) or 0] = true
        if valid(o) and not nameOf(o):find("Default__", 1, true) then up = o end
    end
    local at0 = up and v3(up, function() return up:K2_GetActorLocation() end)
    if at0 then
        log(string.format("tanicorn: Ctrl+R, the hull already up rises where it is: %s at (%.0f, %.0f, %.0f); the rise animation %s",
            (nameOf(up):match("([^%.:]+)$")) or "?", at0.X, at0.Y, at0.Z, anim and "loaded" or "NOT loaded"))
        hudCallout("TEST: THE TANACORN RISES", "THE HULL ALREADY UP")
        RISE = { o = up, name = nameOf(up), x = at0.X, y = at0.Y, z = at0.Z, before = {}, anim = anim, at = os.clock(),
                 state = "finding", next = 0 }
        return
    end
    local p = playerLocation()
    if not p then log("tanicorn: no player location"); return end
    local yaw = playerYaw()
    local x, y = p.X + math.cos(math.rad(yaw)) * C.ahead_cm, p.Y + math.sin(math.rad(yaw)) * C.ahead_cm
    local face = (yaw + 90) % 360                         -- (broadside: the rise camera is off her port beam)
    local r
    if FISH and FISH.spawn then r = FISH.spawn(H.unit, x, y, H.z_cm, face) else r = SV_Spawn(H.unit, x, y, H.z_cm, face) end
    log(string.format("tanicorn: Ctrl+R, %s at (%.0f, %.0f, %d) facing %.0f: %s%s; rows: %s; the rise %s", H.unit, x, y, H.z_cm,
        face, r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")"),
        ok and "" or " (its rows aren't all in)", rows, anim and ("animation " .. nameOf(anim):match("[^%.]+$")) or "animation NOT loaded"))
    hudCallout("TEST: THE TANACORN RISES", r > 0 and "5 KM AHEAD" or "NOT SPAWNED")
    if r > 0 then RISE = { x = x, y = y, z = H.z_cm, before = before, anim = anim, at = os.clock(), state = "finding", next = 0 } end
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn rise", fn = function(now)
    local R, C = RISE, TANI.rise
    if not R or R.back then return end
    if not D or (levelTorn and levelTorn()) then riseBack(R, "the run's over"); RISE = nil; return end
    if R.state == "finding" then                          -- (the new hull of ours, then its rig, hull mesh and part)
        if not R.o then                                   -- ((0.74.63) not when it's the hull already up)
            for _, o in ipairs(FindAllOf(TANI.hull.class) or {}) do
                if valid(o) and not nameOf(o):find("Default__", 1, true) and not R.before[addrOf(o) or 0] then R.o, R.name = o, nameOf(o) end
            end
        end
        if R.o then
            R.rig = riseComp(R.o, "/Script/Engine.SkeletalMeshComponent", "RiseRig")
            R.hull = riseComp(R.o, "/Script/Engine.StaticMeshComponent", "HullMesh")
            R.part = riseComp(R.o, "/Script/Engine.PoseableMeshComponent", C.part)
        end
        if R.o and R.rig and R.hull then
            local steps, len, tick, uro = {}, "?", "?", "?"
            local anim = R.anim
            for _, s in ipairs({ { "SetAnimationMode", function() R.rig:SetAnimationMode(1, true) end },
                                 { "SetAnimation", function() if anim then R.rig:SetAnimation(anim) end end },
                                 { "SetPlayRate 0", function() R.rig:SetPlayRate(0) end },
                                 { "Play", function() R.rig:Play(false) end },
                                 { "SetPosition 0", function() R.rig:SetPosition(0, false) end } }) do
                if not pcall(s[2]) then steps[#steps + 1] = s[1] .. " FAILED" end
            end
            pcall(function() len = string.format("%.1f s", anim:GetPlayLength()) end)
            pcall(function() tick = tostring(R.rig.VisibilityBasedAnimTickOption) end)
            pcall(function() uro = tostring(R.rig.bEnableUpdateRateOptimizations) end)
            log(string.format("tanicorn: rise: RiseRig found on %s (%s, %s); scrubbed to 0%s; VisibilityBasedAnimTickOption %s, "
                .. "update-rate optimisations %s; HullMesh on it, %s %s", (R.name:match("([^%.:]+)$")) or "?",
                anim and (nameOf(anim):match("[^%.]+$") or "?") or "no animation", len,
                #steps > 0 and (" (" .. table.concat(steps, ", ") .. ")") or "", tick, uro, C.part, R.part and "found" or "NOT found"))
            R.state, R.t0 = "hold", now
            riseLook(R, 0)
            if C.cinematic then riseCine(R) end
        elseif now - R.at > C.find_s then
            log(string.format("tanicorn: rise: %s after %d s (an old hull without the rise rig? a build before it)",
                not R.o and "no new hull of ours found" or ("its " .. (not R.rig and "RiseRig" or "HullMesh") .. " NOT found"), C.find_s))
            riseBack(R, "nothing to rise"); RISE = nil
        end
        return
    end
    if liveAddr(R.o) == nil or nameOf(R.o) ~= R.name then riseBack(R, "the hull is gone"); RISE = nil; return end
    if R.state == "hold" and now - R.t0 >= C.hold_s then
        local okP = pcall(function() R.rig:SetPlayRate(C.rate) end)
        if not pcall(function() if not R.rig:IsPlaying() then R.rig:Play(false) end end) then okP = false end
        R.state, R.t1, R.playing = "rising", now, true
        log(string.format("tanicorn: rise: playing at rate %.2f%s", C.rate, okP and "" or " (SetPlayRate / Play FAILED)"))
    end
    if R.cine and R.cam then                              -- (the game may take the view back: given again)
        local okT, vt = pcall(function() return survivalPC:GetViewTarget() end)
        if okT and vt and addrOf(vt) ~= addrOf(R.cam) and not R.back then
            R.reverts = (R.reverts or 0) + 1
            pcall(function() survivalPC:SetViewTargetWithBlend(R.cam, 0, 0, 0, false) end)
        end
    end
    local t = riseHere(R)
    if now >= R.next then R.next = now + C.every_s; R.lastBow, R.lastStern, R.lastMid = riseLook(R, t) end
    if R.state ~= "rising" then return end
    -- ((0.74.64) the sea round her, in her rest frame: her rest place (R.x, R.y, R.z) and forward (the actor's, as a vector:
    -- rotators don't read from Lua). Her motion (the surfacing shot's) slides along her own axis through one point on the
    -- sea, then pivots about it (breach_m forward of her rest midships), so that's where the water stands round her)
    if not R.fwd then
        local f = v3(R.o, function() return R.o:GetActorForwardVector() end)
        local h = f and math.sqrt(f.X * f.X + f.Y * f.Y) or 0
        R.fwd = h > 1e-6 and { X = f.X / h, Y = f.Y / h } or { X = 1, Y = 0 }
        R.fx = { up = 0, of = 0 }
    end
    local function spot(along_m, across_m)               -- a place on the sea in her frame (m: forward, starboard)
        local f = R.fwd
        return { X = R.x + (f.X * along_m - f.Y * across_m) * 100, Y = R.y + (f.Y * along_m + f.X * across_m) * 100, Z = R.z }
    end
    local function fx(path, where, sc)
        R.fx.of = R.fx.of + 1
        if riseFx(path, where, sc) then R.fx.up = R.fx.up + 1; return true end
        return false
    end
    if not R.breached and t >= C.breach_s then
        R.breached = true
        local where, up = spot(C.breach_m, 0), 0
        for _, p in ipairs(C.breach_fx) do if fx(p, where, 1) then up = up + 1 end end
        log(string.format("tanicorn: rise breach at +%.1f s: %d of %d of the Alicorn's surfacing effects up (%.0f m forward of her "
            .. "rest midships), the sound %s", t, up, #C.breach_fx, C.breach_m, riseSound(C.breach_sound, where) and "played" or "FAILED"))
    end
    -- the sea pouring off her where she stands in it, both sides, while she rises and her bow comes down; from her hang on,
    -- along her hull aft of it too, as the rest of her comes up through the surface
    if R.breached and t < C.slam_s + 0.5 and now >= (R.sprayAt or 0) then
        R.sprayAt = now + C.spray_s
        R.sprays = (R.sprays or 0) + 1
        local side = (R.sprays % 2 == 0) and 1 or -1
        fx(C.spray_fx, spot(C.breach_m + math.random(-20, 20), side * 35), C.spray_scale)
        if R.sprays % 3 == 0 then fx(C.foam_fx, spot(C.breach_m, 0), C.spray_scale) end
        if t > 5.0 then
            local back = math.min(300, (t - 5.0) / 4.0 * 300)      -- (5 -> 9 s: from where she stands to 300 m aft of it)
            fx(C.spray_fx, spot(C.breach_m - back * math.random(), -side * 35), C.spray_scale)
        end
    end
    if not R.slammed and t >= C.slam_s then
        R.slammed = true
        local n, up, of = math.max(2, C.slam_spots), 0, 0
        for i = 0, n - 1 do                                -- (along her keel, stern to bow, at sea level)
            local where = spot(-300 + 600 * i / (n - 1), 0)
            for _, p in ipairs(C.slam_fx) do of = of + 1; if fx(p, where, C.fx_scale) then up = up + 1 end end
        end
        local pu = 0
        for _, q in ipairs(C.pillars) do if fx(C.pillar_fx, spot(q[1], q[2]), C.fx_scale) then pu = pu + 1 end end
        local shook = false
        local cls = riseAsset(C.shake, true)
        local you = playerLocation()
        local km_ = you and math.sqrt((you.X - R.x) ^ 2 + (you.Y - R.y) ^ 2) / 100000 or 99
        if cls and km_ <= C.shake_km then
            local sc = math.max(0.2, 1 - km_ / C.shake_km)
            shook = pcall(function() survivalPC:ClientStartCameraShake(cls, sc, 0, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
                or pcall(function() survivalPC.PlayerCameraManager:StartCameraShake(cls, sc, 0, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
        end
        log(string.format("tanicorn: rise slam at +%.1f s: %d of %d foam / splashes along her keel, %d of %d water pillars up; "
            .. "the shake %s (%.1f km); %d of %d of the rise's effects came back in all (%d sprays)", t, up, of, pu, #C.pillars,
            shook and "on" or (cls and "not on" or "NOT loaded"), km_, R.fx.up, R.fx.of, R.sprays or 0))
    end
    local okI, still = pcall(function() return R.rig:IsPlaying() end)
    local done = (t >= C.slam_s + 2.4 and okI and still == false)
        or now - R.t1 >= C.length_s / math.max(0.05, C.rate) + C.end_pad_s
    if done and not R.ended then
        R.ended = true
        R.endAt = now
        riseLook(R, t)
    end
    if R.ended and now - R.endAt >= C.end_pad_s then riseBack(R, "the rise ended"); RISE = nil end
end }
end
-- TEST ONLY END
