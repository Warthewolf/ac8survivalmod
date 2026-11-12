-- sv_tanicorn_rise.lua: THE TANACORN's rise (Ctrl+R): its rig, its water and sound, the cinematic and its camera; the
-- dev install's test code only: a release keeps this header alone. Piece 2 of 2 of sv_tanicorn.lua (sv_tanicorn.lua,
-- sv_tanicorn_rise.lua), split by tools/lua_split_part.py and run by main.lua right after the piece before it: a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local.
-- DEV ONLY BEGIN (the rise: sv_tanicorn_rise.lua)
do  -- (sv_tanicorn.lua's do block, continued: this piece's own helpers stay local to it)

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
              -- ((2026-11-12) the user on 0.74.66: "the water height on the rise is too big now": the Alicorn's ending
              -- cutscene's pillars (ALCN_PILLAR_2 / _3 / _BIG: NS_IGC_alcn_ED_WaterPillar_c02_2nd / c03 / c05) are
              -- world-space mesh columns 2.4-2.8 km tall and 0.5-1 km wide, which the spawn's scale doesn't touch (their
              -- particle scripts emulated, the rise-water research): out. In their place the cutscene's c02_1st
              -- (ALCN_PILLAR_1: local space, ~100 m at scale 1, so its scale holds) and the Alicorn's water blast (local
              -- space, fixed bounds 150 m), larger)
              breach = {                                 -- (at breach_s, round where her axis stands in the sea)
                  { "SURF1", 1, 0, 0 }, { "SURF2", 1, 0, 0 }, { "SURF3", 1, 0, 0 }, { "SURF4", 1, 0, 0 },
                  { "ALCN_PILLAR_1", 2, 0, 0 }, { "ALCN_PILLAR_1", 1.5, 40, 0 }, { "ALCN_BLAST", 2, 25, 0 },
                  { "MIST", 1, 0, 0 }, { "FORD_PILLAR", 2, 0, -45 }, { "FORD_PILLAR", 2, 0, 45 } },
              -- (from breach_s to rise_until_s, one every rise_every_s, cycled, on a ring ring_m round where she stands)
              rise = { { "AB_SPLASH", 1 }, { "FORD_PILLAR", 2 }, { "IMPACT_L", 1 }, { "FORD_SPLASH", 3 } },
              rise_every_s = 0.3, rise_until_s = 5.0, ring_m = { 35, 75 },
              foam = { "FOAM_IGC", 1 }, foam_every_s = 1.0,  -- (where she stands, breach to the slam)
              -- (from rise_until_s to the slam: her bow coming down, the rest of her coming up through the surface aft
              -- of where she stood: along her hull there, both sides)
              fall = { { "FORD_PILLAR", 2 }, { "MIST", 1 }, { "AB_SPLASH", 1 }, { "FORD_SPLASH", 3 } }, fall_every_s = 0.3,
              -- (at slam_s: { path, scale, forward m, starboard m })
              -- ((2026-11-12) the 2.8 km pillars out, as at the breach: c02_1st and the water blast at their spots)
              slam = { { "ALCN_PILLAR_1", 2, -200, -50 }, { "ALCN_PILLAR_1", 2, -200, 50 }, { "ALCN_PILLAR_1", 2, 0, -55 },
                       { "ALCN_PILLAR_1", 2, 0, 55 }, { "ALCN_PILLAR_1", 2, 200, -50 }, { "ALCN_PILLAR_1", 2, 200, 50 },
                       { "ALCN_BLAST", 2, 300, 0 }, { "AB_LAND_L", 1, -100, -70 }, { "AB_LAND_L", 1, 150, -70 },
                       { "AB_LAND_R", 1, -100, 70 }, { "AB_LAND_R", 1, 150, 70 }, { "ALCN_BLAST", 2, 280, 0 } },
              slam_pillars = { "FORD_PILLAR", 2 }, slam_pillar_m = 50,     -- (both sides, every slam_pillar_m stern to bow)
              slam_foam = { "FORD_FOAM", 2 }, slam_spots = 13,             -- (along her keel)
              settle = { "FOAM_IGC", 1 }, settle_every_s = 0.5, settle_until_s = 12.5,   -- (foam along her as she settles)
              shake = "/Game/Blueprints/Vehicle/PLAYER/Camera/CameraShake/BP_CamShake_BombImpactHelios",
              shake_km = 8,
              -- ((2026-11-12) the user on 0.74.66: "the water height on the rise is too big now": a column 2 km tall stood
              -- where she broke the surface long after the rise. Nothing stopped an effect: a cutscene's looping water (the
              -- IGC ones) is switched off by its cutscene, never by itself. Every rise effect is now deactivated fx_life_s
              -- after it's spawned (its particles fade out), whatever the rise is doing then)
              fx_life_s = 8 }
do
    local V, IGC = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/", "/Game/OnlineMode/VFX/IGC/Emergency/"
    local BOSS = "/Game/OnlineMode/VFX/Vehicles/Boss/"
    TANI.rise.FX = {
        SURF1 = BOSS .. "BA002_alcn/Niagara/NS_ex03_alcn_surfacing01_ON", SURF2 = BOSS .. "BA002_alcn/Niagara/NS_ex03_alcn_surfacing02_ON",
        SURF3 = BOSS .. "BA002_alcn/Niagara/NS_ex03_alcn_surfacing03_ON", SURF4 = BOSS .. "BA002_alcn/Niagara/NS_ex03_alcn_surfacing04_ON",
        ALCN_PILLAR_1 = IGC .. "EB002/ED/Niagara/NS_IGC_alcn_ED_WaterPillar_c02_1st_ON",
        -- (ALCN_PILLAR_2 / _3 / _BIG: in no list since 2026-11-12: 2.4-2.8 km towers, see TANI.rise.breach)
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
-- ((2026-11-12) every effect the rise spawns, stopped fx_life_s on: { c, a, name, at } (hard rule 59: its address and name
-- checked before it's touched); a tick of its own, so the rise's end doesn't leave one running; forgotten with the level)
local FXLIVE = {}
local function fxStop(e, why)
    if liveAddr(e.c) == e.a and nameOf(e.c) == e.name then
        if pcall(function() e.c:Deactivate() end) then return true end
    end
    return false
end
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn rise fx", fn = function(now)
    if #FXLIVE == 0 then return end
    local keep, stopped = {}, 0
    for _, e in ipairs(FXLIVE) do
        if now >= e.at then
            if fxStop(e) then stopped = stopped + 1 end
        else
            keep[#keep + 1] = e
        end
    end
    FXLIVE = keep
    if stopped > 0 then TANI.rise.fxStopped = (TANI.rise.fxStopped or 0) + stopped end
end }
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["tanicorn rise fx"] = function() FXLIVE = {} end end
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
    if not (okV and v == true) then return false end
    FXLIVE[#FXLIVE + 1] = { c = c, a = addrOf(c), name = nameOf(c), at = os.clock() + (TANI.rise.fx_life_s or 8) }
    return true
end
TANI.rise.spawnFx = riseFx                                -- (tani_vls_test's: the spawn and its stop)
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
    return R.playing and (os.clock() - R.t1) * (R.rate or TANI.rise.rate) or 0
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
    if CINE and CINE.stop then pcall(CINE.stop, why) end -- ((0.74.65) the director's cameras off first: its locked blend kept)
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
    if CINE and CINE.play then                            -- ((0.74.65) the director's keyed cameras; the rig's SOC_Cam the fallback)
        local okP, okC, whyC = pcall(CINE.play, R, { rate = R.rate or C.rate })
        if okP and okC then log("tanicorn: rise cinematic: sv_cine.lua's keyed cameras (" .. tostring(whyC) .. ")"); return end
        log("tanicorn: rise cinematic: sv_cine.lua's cameras not made (" .. tostring(okP and whyC or ("error " .. tostring(okC)))
            .. "): the rig's SOC_Cam camera")
    end
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
        hullArmour(up, "Ctrl+R")                          -- ((2026-11-12) TANI.armour, if it hasn't it yet)
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
    if r > 0 then armourHulls("Ctrl+R") end              -- ((2026-11-12) her hull can't be damaged: TANI.armour)
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
            -- ((0.74.65) sv_cine.lua's director: in director mode the rise plays slowed with no cinematic, CINE's markers
            -- and keys over it; else the cinematic, which takes CINE's keyed cameras first: docs/re/CINEMATIC.md 5)
            local dir = nil
            if CINE and CINE.director then local okD, d = pcall(CINE.director); if okD then dir = d end end
            R.rate = dir and dir.speed or C.rate
            if dir then pcall(CINE.play, R, { rate = R.rate })
            elseif C.cinematic then riseCine(R) end
        elseif now - R.at > C.find_s then
            log(string.format("tanicorn: rise: %s after %d s (an old hull without the rise rig? a build before it)",
                not R.o and "no new hull of ours found" or ("its " .. (not R.rig and "RiseRig" or "HullMesh") .. " NOT found"), C.find_s))
            riseBack(R, "nothing to rise"); RISE = nil
        end
        return
    end
    if liveAddr(R.o) == nil or nameOf(R.o) ~= R.name then riseBack(R, "the hull is gone"); RISE = nil; return end
    if R.state == "hold" and now - R.t0 >= C.hold_s then
        local okP = pcall(function() R.rig:SetPlayRate(R.rate or C.rate) end)
        if not pcall(function() if not R.rig:IsPlaying() then R.rig:Play(false) end end) then okP = false end
        R.state, R.t1, R.playing = "rising", now, true
        log(string.format("tanicorn: rise: playing at rate %.2f%s", R.rate or C.rate, okP and "" or " (SetPlayRate / Play FAILED)"))
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
        log(string.format("tanicorn: rise effects: %d of %d came back (%d sprays; %d stopped so far, each %s s after its spawn)%s",
            R.fx.up, R.fx.of, R.sprays or 0, TANI.rise.fxStopped or 0, tostring(TANI.rise.fx_life_s),
            #miss > 0 and ("; NOT: " .. table.concat(miss, ", ")) or ""))
    end
    local okI, still = pcall(function() return R.rig:IsPlaying() end)
    local done = (t >= C.slam_s + 2.4 and okI and still == false)
        or now - R.t1 >= C.length_s / math.max(0.05, R.rate or C.rate) + C.end_pad_s
    if done and not R.ended then
        R.ended = true
        R.endAt = now
        riseLook(R, t)
    end
    if R.ended and now - R.endAt >= C.end_pad_s then riseBack(R, "the rise ended"); RISE = nil end
end }
end
-- DEV ONLY END
