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
--                     The hull already up rises, either kind (Ctrl+Y's drawn one or Ctrl+L's live one).
--   Ctrl+L in a run   (2026-11-11) THE TANACORN with her 16 gun mounts LIVE (TANI.live: each a child actor, its own health,
--                     box, fire control and order), 5 km ahead as Ctrl+Y; a line a part at +2 s and +8 s, its health and
--                     aim every 5 s for 2 minutes, a line when one goes down (TANI=1 builds: the world data has the parts).
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
-- (2026-11-11, WP2 step 2, route (a): docs/design/INVINCIBLE_FLEET.md "WP2 step 2") THE TANACORN with her gun mounts LIVE,
-- Ctrl+L (survival_events.TANI_HULL_LIVE_* / TANI_LIVE): BP_SV_Tani_HULLLIVE, the drawn hull's rise rig and hull mesh with
-- each gun mount's socket a LiveChildActorComponent (Part_<socket>) whose child is that mount's own blueprint, made a live
-- part of the hull's AI object by the world data (TANI=1 builds only): its own rows (the test mounts'), health, box and
-- TGT, fire control row, and its order 2.5 s after the hull appears. The VLS blocks, railcannon and sub-railguns drawn as
-- on BP_SV_Tani_HULL. parts: { socket, mount type } in the build's order (tools/build_survival.py check_tanicorn_build
-- reads them here); row_health: each type's model row's MaxHealth (TANI_HEALTH, TANI_MOUNT_PARTS), to tell whether the
-- part took its row
TANI.live = { unit = "SV_Unit_TaniHullLive", npc = "SV_Npc_TaniHullLive", model = "SV_Model_TaniHullLive",
              class = "BP_SV_Tani_HULLLIVE_C", class_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_HULLLIVE.BP_SV_Tani_HULLLIVE_C",
              name_key = "SV_TaniHullLive_Name", name = "TANACORN", ahead_cm = 500000, z_cm = 0,
              comp_class = "/Script/Live.LiveChildActorComponent", looks_s = { 2, 8 }, every_s = 5, watch_s = 120,
              row_health = { T16 = 80, T5 = 40, CIWS = 30, LASER = 30 },
              parts = {
                  { "T16_FWD", "T16" }, { "T16_AFT", "T16" },
                  { "T5_1", "T5" }, { "T5_2", "T5" }, { "T5_3", "T5" }, { "T5_4", "T5" }, { "T5_5", "T5" }, { "T5_6", "T5" },
                  { "CIWS_1", "CIWS" }, { "CIWS_2", "CIWS" }, { "CIWS_3", "CIWS" }, { "CIWS_4", "CIWS" },
                  { "LASER_FWD_L", "LASER" }, { "LASER_FWD_R", "LASER" }, { "LASER_AFT_L", "LASER" }, { "LASER_AFT_R", "LASER" },
              } }
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
    local lm = addRow(mt, mr, TANI.live.model)               -- ((2026-11-11) the live hull's: its parts' rows are the mounts')
    local ln = addRow(npc, mine, TANI.live.npc)
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
        pcall(SV_SetText, TANI.live.name_key, TANI.live.name)
        for _, k in ipairs(TANI.mounts) do pcall(SV_SetText, k.name_key, k.name) end
    end
    T.rows = m and n and hm and hn and lm and ln and allIn
    return T.rows, string.format("%s %s, %s %s; %s %s, %s %s; %s %s, %s %s; %s", TANI.model, m and "in DT_NPC_Model" or "NOT added",
        TANI.npc, n and "in DT_NPC" or "NOT added", TANI.hull.model, hm and "in" or "NOT added", TANI.hull.npc,
        hn and "in" or "NOT added", TANI.live.model, lm and "in" or "NOT added", TANI.live.npc, ln and "in" or "NOT added",
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
            out[#out + 1] = { o = e.o, a = a, unit = e.unit or e.k.unit, body = e.body, socket = MUZZLE, foe = "players" }
        end
    end
    return out
end
local function liCarry(o, k, unit)            -- (unit: a live part's, its hull's unit and component)
    local a = addrOf(o)
    if not a or T.li[a] then return end
    T.li[a] = { o = o, name = nameOf(o), k = k, body = turretMesh(o), unit = unit }
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

-- every hull of ours in the level, either kind (Ctrl+Y's drawn BP_SV_Tani_HULL, Ctrl+L's live BP_SV_Tani_HULLLIVE)
local function ourHulls()
    local out = {}
    for _, cls in ipairs({ TANI.hull.class, TANI.live.class }) do
        for _, o in ipairs(FindAllOf(cls) or {}) do
            if valid(o) and not nameOf(o):find("Default__", 1, true) then out[#out + 1] = o end
        end
    end
    return out
end

-- (2026-11-11, WP2 step 2, route (a)) Ctrl+L: THE TANACORN with her gun mounts live (TANI.live), broadside ahead_cm out,
-- her waterline on the sea, as Ctrl+Y (a live hull already up is looked at again: its unit can't spawn while its flight is
-- up, hard rule 16). Logged: `tanicorn: live hull class ...`, `tanicorn: the live parts' classes: T5 in memory, ...` (a
-- TANI=1 world data loads them with the level: its child descs import them), `tanicorn: Ctrl+L, SV_Unit_TaniHullLive at
-- (x, y, 0) facing F: N up`; at +2 s and +8 s a line a part, `tanicorn: live +2 s: Part_T5_1 (T5): BP_SV_Tani_T5_C <name>,
-- health H/M (its row's 40), 0.0 m from Mount_T5_1, on Part_T5_1 (attached to the hull true), a child of the hull true (its
-- AttachedParentGameObject <the hull>)` (on: its root's attach parent; a child: in the hull's AttachedChildGameObjects),
-- then `tanicorn: live +2 s: N of 16 parts up ...`; the first part of each type its fire control arms and muzzle (as Ctrl+T's / Ctrl+U's mount lines); each LASER part
-- handed to AC7's LaserInterceptor (liCarry: `tanicorn: LASER mount ... handed to ...`, then sv_escort_li.lua's `zfa li:`);
-- every every_s for watch_s `tanicorn: live +T s: Part_T5_1 (T5) hp H/M, barrel yaw Y pitch P, muzzle (...) from the mount;
-- D m from its socket`; `tanicorn: live Part_T5_1 (T5) destroyed at +T s ...` when a part goes down (its health 0, or gone)
-- while the hull lives; the shells as the mounts' (`tanicorn: T5 shell N: ...`: keyed by their mount's class, so the parts'
-- too). Each part kept by its address AND the name it was captured with (hard rule 59).
do
local LV = nil                                           -- the live hull's watch (Ctrl+L)
local KIND = {}                                          -- a mount type's key -> its KINDS entry (the T5's: TANI)
for _, k in ipairs(KINDS) do KIND[k.key] = k end
local function short(o) return (nameOf(o):match("([^%.:]+)$")) or "?" end
local function v3of(f) local ok, v = pcall(f); if ok and v and v.X then return { X = v.X, Y = v.Y, Z = v.Z } end return nil end
local function gap(a, b)
    if not (a and b) then return nil end
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function same(e) return e and liveAddr(e.o) == e.a and nameOf(e.o) == e.name end   -- (hard rule 59)
local function healthOf(o)
    local h, mx
    pcall(function() h = o.HealthInternal end)
    pcall(function() mx = o.MaxHealth end)
    return tonumber(h), tonumber(mx)
end
local function hullMesh(W)                               -- the live hull's HullMesh (its Mount_* sockets)
    if W.mesh and liveObj(W.mesh) then return W.mesh end
    W.mesh = nil
    for _, c in ipairs((SPC and SPC.V and SPC.V.comps and SPC.V.comps(W.o, "/Script/Engine.StaticMeshComponent")) or {}) do
        local okN, n = pcall(function() return c:GetFName():ToString() end)
        if okN and n == "HullMesh" then W.mesh = c end
    end
    return W.mesh
end
local function partComps(W)                              -- its LiveChildActorComponents by name (Part_<socket>)
    local by = {}
    for _, c in ipairs((SPC and SPC.V and SPC.V.comps and SPC.V.comps(W.o, TANI.live.comp_class)) or {}) do
        local okN, n = pcall(function() return c:GetFName():ToString() end)
        if okN and n then by[n] = c end
    end
    return by
end
local function childOf(c)                                -- a child actor component's actor
    local ch
    pcall(function() ch = c.ChildActor end)
    if not valid(ch) then ch = nil; pcall(function() ch = c:GetChildActor() end) end
    return valid(ch) and ch or nil
end
local function hullKids(W)                               -- the hull's AttachedChildGameObjects: { [address] = true }, count
    local kids, n = {}, nil
    pcall(function()
        local arr, k = W.o.AttachedChildGameObjects, 0
        local function add(e)
            local x = e
            pcall(function() x = e:get() end)
            local a = addrOf(x)
            if a then kids[a] = true end
            k = k + 1
        end
        if type(arr) == "table" then for _, e in ipairs(arr) do add(e) end else arr:ForEach(function(_, e) add(e) end) end
        n = k
    end)
    return kids, n
end
-- one part as it stands: its line, and its record (W.parts[socket]) made the first time its child is seen
local function partLine(W, s, key, kids)
    local C, cn = TANI.live, "Part_" .. s
    local c = W.comps[cn]
    if not c then return string.format("%s (%s): no such component on the hull", cn, key), false end
    local ch = childOf(c)
    if not ch then
        local cc = "?"
        pcall(function() cc = c.ChildActorClass:GetFName():ToString() end)
        return string.format("%s (%s): no child actor (its ChildActorClass %s)", cn, key, cc), false
    end
    local k = KIND[key]
    local e = W.parts[s]
    if not (e and same(e)) then
        e = { o = ch, a = addrOf(ch), name = nameOf(ch), k = k, key = key, alive = true }
        W.parts[s] = e
        if k and not W.kinds[key] then                   -- (the first of each type: as the mounts' up and muzzle lines)
            W.kinds[key] = true
            log(string.format("tanicorn: live %s %s: fire control arms %s", key, cn, armsOf(ch)))
            log("tanicorn: live " .. key .. " muzzle: " .. muzzleProbe(turretMesh(ch)))
        end
        if k and k.li then liCarry(ch, k, TANI.live.unit .. " " .. cn) end   -- (the LASER: AC7's LaserInterceptor, as Ctrl+U's)
    end
    local cls = "?"
    pcall(function() cls = ch:GetClass():GetFName():ToString() end)
    local h, mx = healthOf(ch)
    local mesh = hullMesh(W)
    local d = gap(mesh and v3of(function() return mesh:GetSocketLocation(FName("Mount_" .. s)) end),
        v3of(function() return ch:K2_GetActorLocation() end))
    local att, onComp = "?", "?"
    pcall(function() local pa = ch:GetAttachParentActor(); att = tostring(valid(pa) and addrOf(pa) == W.a) end)
    pcall(function() onComp = ch.RootComponent:GetAttachParent():GetFName():ToString() end)
    local par = "?"
    pcall(function() local p = ch.AttachedParentGameObject; par = valid(p) and short(p) or "none" end)
    local want = C.row_health[key]
    return string.format("%s (%s): %s %s, health %s/%s (its row's %s%s), %s m from Mount_%s, on %s (attached to the hull %s), "
        .. "a child of the hull %s (its AttachedParentGameObject %s)", cn, key, cls, short(ch), tostring(h), tostring(mx),
        tostring(want), (want and mx and math.abs(mx - want) > 0.01) and ": NOT its row's" or "", d and string.format("%.1f", d / 100) or "?",
        s, onComp, att, tostring(kids[e.a] == true), par), true
end
local function liveLook(W, tag)
    W.comps = partComps(W)
    local kids, nk = hullKids(W)
    local up = 0
    for _, pr in ipairs(TANI.live.parts) do
        local line, ok = partLine(W, pr[1], pr[2], kids)
        if ok then up = up + 1 end
        log("tanicorn: live " .. tag .. ": " .. line)
    end
    local h, mx = healthOf(W.o)
    local n = 0
    for _ in pairs(W.comps) do n = n + 1 end
    log(string.format("tanicorn: live %s: %d of %d parts up on %s at %s (its %d part components; its AttachedChildGameObjects %s; "
        .. "its health %s/%s)%s", tag, up, #TANI.live.parts, short(W.o), at(W.o), n, tostring(nk), tostring(h), tostring(mx),
        up == 0 and ": none live (a world data without them? TANI=1 builds only; the classes line above)" or ""))
end
local function liveDowns(W, now)                         -- a line when a part goes down (its health 0, or the actor gone)
    for _, pr in ipairs(TANI.live.parts) do
        local e = W.parts[pr[1]]
        if e and e.alive then
            local why
            if not same(e) then why = "gone (its actor no longer there)"
            else
                local h = healthOf(e.o)
                if h and h <= 0 then why = "destroyed (health 0)" end
            end
            if why then
                e.alive = false
                local hh, hm = healthOf(W.o)
                log(string.format("tanicorn: live Part_%s (%s) %s at +%.1f s; the hull's health %s/%s", pr[1], e.key, why,
                    now - W.t0, tostring(hh), tostring(hm)))
            end
        end
    end
end
local function liveLines(W, now)                         -- every every_s: each live part's health, aim and socket gap
    W.comps = partComps(W)
    local kids = hullKids(W)
    local mesh = hullMesh(W)
    for _, pr in ipairs(TANI.live.parts) do
        local s, key = pr[1], pr[2]
        local e = W.parts[s]
        if not (e and same(e)) then                      -- (not seen yet, or another object now: looked for again)
            local line, ok = partLine(W, s, key, kids)
            if not ok then log(string.format("tanicorn: live +%.0f s: %s", now - W.t0, line)) end
            e = W.parts[s]
        end
        if e and same(e) and e.alive then
            local h, mx = healthOf(e.o)
            local d = gap(mesh and v3of(function() return mesh:GetSocketLocation(FName("Mount_" .. s)) end),
                v3of(function() return e.o:K2_GetActorLocation() end))
            log(string.format("tanicorn: live +%.0f s: Part_%s (%s) hp %s/%s, %s; %s m from its socket", now - W.t0, s, key,
                tostring(h), tostring(mx), (aim(e.o)), d and string.format("%.1f", d / 100) or "?"))
        end
    end
end

testKey("L", "sv_tanicorn.lua's live hull test", function()
    if not (D and D.now) or not nativeReady() then log("tanicorn: Ctrl+L outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("tanicorn: Ctrl+L: the host spawns it (you're a joiner)"); return end
    local C = TANI.live
    local cls, why = loadObject(C.class_path)
    log("tanicorn: live hull class " .. (cls and ("loaded " .. nameOf(cls)) or ("NOT loaded: " .. tostring(why))))
    if cls then pin(cls, "tanicorn live hull class") end
    local said = {}
    for _, k in ipairs(KINDS) do                         -- (the parts' classes: a TANI=1 world data's imports load them)
        said[#said + 1] = k.key .. (valid(StaticFindObject(k.class_path)) and " in memory" or " NOT in memory")
    end
    log("tanicorn: the live parts' classes: " .. table.concat(said, ", ")
        .. " (a TANI=1 build's world data imports them: loaded with the level)")
    local ok, rows = rowsIn()
    log("tanicorn: rows: " .. rows)
    local now = os.clock()
    local before, up = {}, nil
    for _, o in ipairs(FindAllOf(C.class) or {}) do
        before[addrOf(o) or 0] = true
        if valid(o) and not nameOf(o):find("Default__", 1, true) then up = o end
    end
    local W = { t0 = now, before = before, parts = {}, kinds = {}, comps = {}, looks = {} }
    if up then
        W.o, W.a, W.name = up, addrOf(up), nameOf(up)
        log(string.format("tanicorn: Ctrl+L, a live hull already up (its unit can't spawn again while it's up: hard rule 16): "
            .. "%s at %s, looked at again", short(up), at(up)))
        hudCallout("TEST: TANACORN LIVE", "THE HULL ALREADY UP")
    else
        local p = playerLocation()
        if not p then log("tanicorn: no player location"); return end
        local yaw = playerYaw()
        local x, y = p.X + math.cos(math.rad(yaw)) * C.ahead_cm, p.Y + math.sin(math.rad(yaw)) * C.ahead_cm
        local face = (yaw + 90) % 360                     -- (broadside to you: her whole length in view)
        local r
        if FISH and FISH.spawn then r = FISH.spawn(C.unit, x, y, C.z_cm, face) else r = SV_Spawn(C.unit, x, y, C.z_cm, face) end
        r = tonumber(r) or -5
        log(string.format("tanicorn: Ctrl+L, %s at (%.0f, %.0f, %d) facing %.0f: %s%s", C.unit, x, y, C.z_cm, face,
            r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")"),
            ok and "" or " (its rows aren't all in)"))
        hudCallout("TEST: TANACORN LIVE", r > 0 and "5 KM AHEAD" or "NOT SPAWNED")
        if r <= 0 then return end
    end
    for _, s in ipairs(C.looks_s) do W.looks[#W.looks + 1] = { at = now + s, tag = "+" .. s .. " s" } end
    W.next, W.until_ = now + C.looks_s[#C.looks_s] + C.every_s, now + C.watch_s
    for _, k in ipairs(KINDS) do T.shells[k.key] = 0 end -- (the first 12 shells of each type again: the parts' too)
    LV = W
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn live hull", fn = function(now)
    local W = LV
    if not W then return end
    if not D or (levelTorn and levelTorn()) then LV = nil; return end
    if not W.o then                                       -- (the new live hull of ours)
        for _, o in ipairs(FindAllOf(TANI.live.class) or {}) do
            if valid(o) and not nameOf(o):find("Default__", 1, true) and not W.before[addrOf(o) or 0] then
                W.o, W.a, W.name = o, addrOf(o), nameOf(o)
            end
        end
        if not W.o then
            if now - W.t0 > TANI.live.looks_s[#TANI.live.looks_s] + 2 then
                log("tanicorn: live: no new live hull of ours found (its class not cooked yet? tools/tanicorn/build.sh)")
                LV = nil
            end
            return
        end
    end
    if not same(W) then
        log(string.format("tanicorn: live: the hull is gone at +%.1f s", now - W.t0)); LV = nil; return
    end
    while W.looks[1] and now >= W.looks[1].at do liveLook(W, table.remove(W.looks, 1).tag) end
    if now >= (W.downAt or 0) then W.downAt = now + 0.5; liveDowns(W, now) end   -- (twice a second, while the hull lives)
    if now <= W.until_ and now >= W.next and #W.looks == 0 then
        W.next = now + TANI.live.every_s
        liveLines(W, now)
    end
end }
end

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
              bow_x_m = 324.8,                           -- (the bow's tip from midships: tools/tanicorn's hull export)
              -- the two hull sockets the pitch is measured between, and their rest angle (deg: the hull's json, UE cm)
              bow_socket = "Mount_RAILCANNON", stern_socket = "Mount_VLSD_8", rest_pitch = math.deg(math.atan(-691.8 - 991.4, 12590.4 + 26400.0)),
              part = "Part_T16_FWD",
              anim = "/Game/Mods/SurvivalMode/Tanicorn/Model/AS_SV_Tani_RIG_Rise",
              breach_sound = "/Game/WwiseAssets/BA002_alcn/AKE_BA002_alcn_Surface_Play",
              -- ((0.74.65) the user on 0.74.64's recording: "needs more water VFX": the Ford's effects, made for a 333 m
              -- ship, barely showed on her 650 m; only the slam's water pillars (NS_VesselsPillarL001) read on screen. Now
              -- the water AC8 made for ships her size as well: the Alicorn's and the Arsenal Bird's cutscene water (Online
              -- Mode's IGC: spawned bare, no user parameter needed), with the Ford's pillars at twice their size.
              -- Each entry { path, scale, forward m, starboard m } from her rest midships; the paths are FX.* below)
              breach = {                                 -- (at breach_s, round where her axis stands in the sea)
                  { "SURF1", 1, 0, 0 }, { "SURF2", 1, 0, 0 }, { "SURF3", 1, 0, 0 }, { "SURF4", 1, 0, 0 },
                  { "ALCN_PILLAR_1", 1, 0, 0 }, { "ALCN_PILLAR_2", 1, 10, 0 }, { "ALCN_BLAST", 1, 25, 0 },
                  { "MIST", 1, 0, 0 }, { "FORD_PILLAR", 2, 0, -45 }, { "FORD_PILLAR", 2, 0, 45 } },
              -- (from breach_s to rise_until_s, one every rise_every_s, cycled, on a ring ring_m round where she stands)
              rise = { { "AB_SPLASH", 1 }, { "FORD_PILLAR", 2 }, { "IMPACT_L", 1 }, { "FORD_SPLASH", 3 } },
              rise_every_s = 0.3, rise_until_s = 5.0, ring_m = { 35, 75 },
              foam = { "FOAM_IGC", 1 }, foam_every_s = 1.0,  -- (where she stands, breach to the slam)
              -- (from rise_until_s to the slam: her bow coming down, the rest of her coming up through the surface aft
              -- of where she stood: along her hull there, both sides)
              fall = { { "FORD_PILLAR", 2 }, { "MIST", 1 }, { "AB_SPLASH", 1 }, { "FORD_SPLASH", 3 } }, fall_every_s = 0.3,
              -- (at slam_s: { path, scale, forward m, starboard m })
              slam = { { "ALCN_PILLAR_BIG", 1, -200, -50 }, { "ALCN_PILLAR_BIG", 1, -200, 50 }, { "ALCN_PILLAR_BIG", 1, 0, -55 },
                       { "ALCN_PILLAR_BIG", 1, 0, 55 }, { "ALCN_PILLAR_BIG", 1, 200, -50 }, { "ALCN_PILLAR_BIG", 1, 200, 50 },
                       { "ALCN_PILLAR_3", 1, 300, 0 }, { "AB_LAND_L", 1, -100, -70 }, { "AB_LAND_L", 1, 150, -70 },
                       { "AB_LAND_R", 1, -100, 70 }, { "AB_LAND_R", 1, 150, 70 }, { "ALCN_BLAST", 1, 280, 0 } },
              slam_pillars = { "FORD_PILLAR", 2 }, slam_pillar_m = 50,     -- (both sides, every slam_pillar_m stern to bow)
              slam_foam = { "FORD_FOAM", 2 }, slam_spots = 13,             -- (along her keel)
              settle = { "FOAM_IGC", 1 }, settle_every_s = 0.5, settle_until_s = 12.5,   -- (foam along her as she settles)
              shake = "/Game/Blueprints/Vehicle/PLAYER/Camera/CameraShake/BP_CamShake_BombImpactHelios",
              shake_km = 8 }
do
    local V, IGC = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/", "/Game/OnlineMode/VFX/IGC/Emergency/"
    local BOSS = "/Game/OnlineMode/VFX/Vehicles/Boss/"
    TANI.rise.FX = {
        SURF1 = BOSS .. "BA002_alcn/Niagara/NS_ex03_alcn_surfacing01_ON", SURF2 = BOSS .. "BA002_alcn/Niagara/NS_ex03_alcn_surfacing02_ON",
        SURF3 = BOSS .. "BA002_alcn/Niagara/NS_ex03_alcn_surfacing03_ON", SURF4 = BOSS .. "BA002_alcn/Niagara/NS_ex03_alcn_surfacing04_ON",
        ALCN_PILLAR_1 = IGC .. "EB002/ED/Niagara/NS_IGC_alcn_ED_WaterPillar_c02_1st_ON",
        ALCN_PILLAR_2 = IGC .. "EB002/ED/Niagara/NS_IGC_alcn_ED_WaterPillar_c02_2nd_ON",
        ALCN_PILLAR_3 = IGC .. "EB002/ED/Niagara/NS_IGC_alcn_ED_WaterPillar_c03_ON",
        ALCN_PILLAR_BIG = IGC .. "EB002/ED/Niagara/NS_IGC_alcn_WaterPillar_c05_ON",
        ALCN_BLAST = BOSS .. "BA002_alcn/Niagara/NS_alcn_WaterExplosion01_ON",
        MIST = IGC .. "EB001/ED/Niagara/NS_IGC_aias_WaterSmoke_c03_ON",
        FOAM_IGC = IGC .. "EB002/OP/Niagara/NS_IGC_aegs_WaterFoam_OP_c02_ON",
        AB_SPLASH = BOSS .. "BA001_aias/Niagara/NS_MS19_AB_LandingSplash_01_ON",
        AB_LAND_L = BOSS .. "BA001_aias/Niagara/NS_MS19_AB_LandingSplash_00_L_ON",
        AB_LAND_R = BOSS .. "BA001_aias/Niagara/NS_MS19_AB_LandingSplash_00_R_ON",
        IMPACT_L = BOSS .. "BA001_aias/Niagara/NS_WaterImpact_L01_ON",
        FORD_PILLAR = V .. "NS_VesselsPillarL001", FORD_SPLASH = V .. "NS_VesselsWaveSplashL001", FORD_FOAM = V .. "NS_VesselsWaveFoamXL001",
    }
end
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
    -- ((2026-11-11) either kind: Ctrl+Y's drawn hull or Ctrl+L's live one, whose parts ride HullMesh as child actors)
    local before, up = {}, nil
    for _, o in ipairs(ourHulls()) do
        before[addrOf(o) or 0] = true
        up = o
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
            for _, o in ipairs(ourHulls()) do
                if not R.before[addrOf(o) or 0] then R.o, R.name = o, nameOf(o) end
            end
        end
        if R.o then
            R.rig = riseComp(R.o, "/Script/Engine.SkeletalMeshComponent", "RiseRig")
            R.hull = riseComp(R.o, "/Script/Engine.StaticMeshComponent", "HullMesh")
            -- ((2026-11-11) on the live hull the part is a LiveChildActorComponent, a scene component on the same socket)
            R.part = riseComp(R.o, "/Script/Engine.PoseableMeshComponent", C.part) or riseComp(R.o, TANI.live.comp_class, C.part)
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
    -- ((0.74.65) "needs more water VFX": the effects by name from TANI.rise.FX, many more of them, bigger ones)
    if not R.fwd then
        local f = v3(R.o, function() return R.o:GetActorForwardVector() end)
        local h = f and math.sqrt(f.X * f.X + f.Y * f.Y) or 0
        R.fwd = h > 1e-6 and { X = f.X / h, Y = f.Y / h } or { X = 1, Y = 0 }
        R.fx = { up = 0, of = 0, by = {} }
    end
    local function spot(along_m, across_m)               -- a place on the sea in her frame (m: forward, starboard)
        local f = R.fwd
        return { X = R.x + (f.X * along_m - f.Y * across_m) * 100, Y = R.y + (f.Y * along_m + f.X * across_m) * 100, Z = R.z }
    end
    local function fx(key, where, sc)                    -- an effect by its FX name: counted, and by name when it fails
        R.fx.of = R.fx.of + 1
        local path = C.FX[key] or key
        if riseFx(path, where, sc) then R.fx.up = R.fx.up + 1; return true end
        R.fx.by[key] = (R.fx.by[key] or 0) + 1
        return false
    end
    local function list(l, along, across)               -- a list of { key, scale, forward, starboard } round a point
        local up = 0
        for _, e in ipairs(l) do if fx(e[1], spot(along + (e[3] or 0), across + (e[4] or 0)), e[2]) then up = up + 1 end end
        return up
    end
    if not R.breached and t >= C.breach_s then
        R.breached = true
        local up = list(C.breach, C.breach_m, 0)
        log(string.format("tanicorn: rise breach at +%.1f s: %d of %d effects up (%.0f m forward of her rest midships), the sound %s",
            t, up, #C.breach, C.breach_m, riseSound(C.breach_sound, spot(C.breach_m, 0)) and "played" or "FAILED"))
    end
    -- the sea round where she stands while she climbs (a ring), then along her hull aft of it as her bow comes down and the
    -- rest of her comes up through the surface; foam where she stands all the while
    if R.breached and t < C.slam_s and now >= (R.sprayAt or 0) then
        local rising = t < C.rise_until_s
        R.sprayAt = now + (rising and C.rise_every_s or C.fall_every_s)
        R.sprays = (R.sprays or 0) + 1
        local l = rising and C.rise or C.fall
        local e = l[(R.sprays - 1) % #l + 1]
        if rising then
            local a, r = math.rad(math.random(0, 359)), math.random(C.ring_m[1], C.ring_m[2])
            fx(e[1], spot(C.breach_m + math.cos(a) * r, math.sin(a) * r), e[2])
        else
            local back = math.min(300, (t - C.rise_until_s) / math.max(0.1, C.slam_s - C.rise_until_s) * 300)
            fx(e[1], spot(C.breach_m - back * math.random(), (R.sprays % 2 == 0 and 1 or -1) * math.random(30, 50)), e[2])
        end
        if now >= (R.foamAt or 0) then R.foamAt = now + C.foam_every_s; fx(C.foam[1], spot(C.breach_m, 0), C.foam[2]) end
    end
    if not R.slammed and t >= C.slam_s then
        R.slammed = true
        local n, up, of = math.max(2, C.slam_spots), 0, 0
        for i = 0, n - 1 do                                -- (foam along her keel, stern to bow, at sea level)
            of = of + 1
            if fx(C.slam_foam[1], spot(-300 + 600 * i / (n - 1), 0), C.slam_foam[2]) then up = up + 1 end
        end
        local pu, po = 0, 0
        for x = -300, 300, C.slam_pillar_m do              -- (pillars both sides, every slam_pillar_m)
            for _, y in ipairs({ -45, 45 }) do
                po = po + 1
                if fx(C.slam_pillars[1], spot(x, y), C.slam_pillars[2]) then pu = pu + 1 end
            end
        end
        local bu = list(C.slam, 0, 0)
        local shook = false
        local cls = riseAsset(C.shake, true)
        local you = playerLocation()
        local km_ = you and math.sqrt((you.X - R.x) ^ 2 + (you.Y - R.y) ^ 2) / 100000 or 99
        if cls and km_ <= C.shake_km then
            local sc = math.max(0.2, 1 - km_ / C.shake_km)
            shook = pcall(function() survivalPC:ClientStartCameraShake(cls, sc, 0, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
                or pcall(function() survivalPC.PlayerCameraManager:StartCameraShake(cls, sc, 0, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
        end
        log(string.format("tanicorn: rise slam at +%.1f s: %d of %d foam along her keel, %d of %d pillars along her sides, %d of %d "
            .. "big ones (the Alicorn's, the Arsenal Bird's); the shake %s (%.1f km)", t, up, of, pu, po, bu, #C.slam,
            shook and "on" or (cls and "not on" or "NOT loaded"), km_))
    end
    if R.slammed and t < C.settle_until_s and now >= (R.settleAt or 0) then   -- (foam along her as she settles)
        R.settleAt = now + C.settle_every_s
        fx(C.settle[1], spot(math.random(-300, 300), math.random(-40, 40)), C.settle[2])
    end
    if R.slammed and t >= C.settle_until_s and not R.fxSaid then
        R.fxSaid = true
        local miss = {}
        for k, n in pairs(R.fx.by) do miss[#miss + 1] = k .. " x" .. n end
        log(string.format("tanicorn: rise effects: %d of %d came back (%d sprays)%s", R.fx.up, R.fx.of, R.sprays or 0,
            #miss > 0 and ("; NOT: " .. table.concat(miss, ", ")) or ""))
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
