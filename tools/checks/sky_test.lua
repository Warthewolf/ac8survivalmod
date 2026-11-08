-- sky_test.lua <mod dir> <work dir> <stripped dir> (run by tools/checks/sky_test.sh): the sky Survival changes
-- (Scripts/sv_sky.lua; tools/re/FISHING.md 5) and its test key on the real sv_core, sv_config and sv_sky, the game stubbed
-- (a Cloudly actor, its stock sky asset, a renderer's working copies, the sun light, a sky light controller, two
-- post-process volumes, the two MPCs, Cloudly's custom sun):
--   the game as the user's sky test of 2026-11-07 read it: Cloudly copies the level's sky asset into the drawn copy
--     (SkyParamsRO) and onto the sun light every frame, and its custom sun API writes the asset;
--   SKY.read: every value it can see, Cloudly's sky light read only;
--   SKY.apply: the sky asset only when asked (v.asset, the arc's path), the renderer's copies, the light (pitch
--     -elevation, yaw azimuth + 90, intensity, colour bytes), the sky light (x its original: never compounded), the
--     exposure only on volumes whose override is on, the MPCs, the custom sun through its API (the asset's sun and moon it
--     moves kept to be put back); the interpolated params only when they're a run-time object;
--   SKY.restore: every original back exactly (colour bytes too), the custom sun's flag first; nothing kept after;
--   the level torn down: originals dropped untouched, a custom sun left on and the sky asset's values put back in the next
--     tick that can (SKY.idleTick: the asset found by its path);
--   the arc: on the asset, the drawn sky and the light following it, checked (`the drawn sky follows the arc`); one that
--     doesn't follow: the day's exposure kept; an asset an earlier run left changed: its shipped values first;
--   the test key (Ctrl+F6): five steps a press each with a read-back readback_s on (kept / overwritten by the game, the MPC
--     values the game puts back), `sky test: put back: N of N values match the originals`; it waits while VALKA's red
--     sky is on and while a read-back is due;
--   a release's copy: no test code, SKY.apply / restore still there.
local MOD, WORK, STRIPPED = arg[1], arg[2], arg[3]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore
VERSION = "0.74.0-sky.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local nextA = 0x10000
local function obj(name, t)
    t = t or {}
    nextA = nextA + 0x100
    t.addr, t.full = nextA, name
    t.IsValid = function(self) return not self.gone end
    t.GetAddress = function(self) return self.addr end
    t.GetFullName = function(self) return self.full end
    return t
end
local function arr(list) return { list = list, ForEach = function(self, fn) for i, x in ipairs(self.list) do fn(i, { get = function() return x end }) end end } end
local notifies, statics, all, binds = {}, {}, {}, {}
function NotifyOnNewObject(cls, fn) notifies[cls] = notifies[cls] or {}; table.insert(notifies[cls], fn) end
function StaticFindObject(p) return statics[p] end
function FindAllOf(cls) return all[cls] end
function FindFirstOf(cls) local l = all[cls]; return l and l[1] end
Key = { F6 = "F6", F10 = "F10", F11 = "F11", F12 = "F12", PAGE_DOWN = "PAGE_DOWN" }
ModifierKey = { CONTROL = "CTRL" }
function RegisterKeyBind(key, mods, fn) binds[key] = fn end
function ExecuteInGameThread(f) f() end
local function part(dir, name, chunk) dofile("parts.lua")(dir, readAll).load(name, chunk) end   -- (the part and its pieces)
part(MOD, "sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
svLevelOn = true
part(MOD, "sv_config.lua")
local callouts = {}
function hudCallout(a, b) callouts[#callouts + 1] = tostring(a) .. " / " .. tostring(b) end
local C = CFG.sky

-- the sky: Mission 4's (sun 15 / 142, factor 120000), the renderer's two copies of it, the light, the sky light
local L = "/Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel."
-- (Mission 4's CSP_ms04_20251218b as the sky test read it in game, 2026-11-07: CFG.sky.arc.stock.asset)
local function params()
    return { SunElevationAngleInDegrees = 15, SunAzimuthAngleInDegrees = 142, bUseUnrealSunData = false,
             SunIntensity = { Factor = 120000, RGB = { X = 1, Y = 1, Z = 1 } }, SunDiskAngleInDegrees = 1.2783,
             EnableMoon = false, MoonElevationAngleInDegrees = 10, MoonAzimuthAngleInDegrees = 135, MoonPhase = 0.15,
             MoonPhaseAngle = 0, MoonDiskAngleInDegrees = 0.5683, MoonDiskBrightness = -4, MoonFractionOfSunIntensity = 2.5e-06,
             StarsParams = { EnableStars = true, StarsIntensity = 4, StarsBackgroundIntensity = 0, StarsRadius = 2,
                             StarsTextureScreenFraction = 0.5, StarsGlobalRotation = { X = 0, Y = 0, Z = 0 },
                             StarsElevationMaskStart = 0.05, StarsElevationMaskEnable = false, StarsElevationMaskLength = 0.5,
                             StarsFadePower = 1, StarsScintillationsPower = 0.3, StarsMoonMaskEnable = false, StarsMoonMaskAngle = 0,
                             StarsMoonMaskLength = 0.1 },
             MultipleScatteringScale = 1.446, MultipleScatteringScaleAP = 1 }
end
local ASSET_PATH = "/Game/Cloudly/CloudlySkyParams/Ingame/Mission004/CSP_ms04_20251218b.CSP_ms04_20251218b"
local asset = obj("CloudlySkyParams " .. ASSET_PATH, { Data = params() })
local interp = obj("/Engine/Transient.CloudlySkyParams_0", { Data = params() })
local our, ro = params(), params()
local rend = obj("/Engine/Transient.CloudlyRenderer_0", { Data = { SkyRendererMainThread = { OurSkyParams = arr({ our }) }, SkyParamsRO = arr({ ro }) } })
local sun = obj(L .. "LiveCloudlyActor_1.SunLight", { Intensity = 120000, LightColor = { R = 255, G = 255, B = 255 }, rot = { Pitch = -15, Yaw = -128, Roll = 0 } })
function sun:SetIntensity(v) self.Intensity = v end
sun.SpecularScale = 1                                  -- ((2026-11-08) Mission 9's night: its moonlight's specular 0.01)
function sun:SetSpecularScale(v) self.SpecularScale = v end
function sun:SetLightColor(c, srgb)
    assert(srgb == false, "the sun's colour as bytes (bSRGB false)")
    self.LightColor = { R = math.floor(c.R * 255.999), G = math.floor(c.G * 255.999), B = math.floor(c.B * 255.999) }
end
function sun:K2_GetComponentRotation() return { Pitch = self.rot.Pitch, Yaw = self.rot.Yaw, Roll = self.rot.Roll } end
function sun:K2_SetWorldRotation(r) self.rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end
local cskyl = obj(L .. "LiveCloudlyActor_1.SkyLight", { Intensity = 1 })
local actor = obj(L .. "LiveCloudlyActor_1", { SunLight = sun, SkyLight = cskyl, CloudlySkyParamsAsset = asset,
    CloudlyInterpolatedSkyParamsAsset = interp, bUseSunLight = true, bUseSkyLight = false, bUseHeightFog = false,
    CloudlyResources = {} })                            -- (Mission 4's: no star catalog, no moon texture)
local catalog, moonTex = obj(C.stars.catalog), obj(C.night.moon_texture)
statics[C.stars.catalog], statics[C.night.moon_texture] = catalog, moonTex
local function enc(x) if x <= 0.0031308 then return x * 12.92 end return 1.055 * x ^ (1 / 2.4) - 0.055 end
local main = obj(L .. "BP_SkyLightController_C_1.MainSkyLight", { Intensity = 2.0, LightColor = { R = 200, G = 210, B = 230 } })
function main:SetIntensity(v) self.Intensity = v end
function main:SetLightColor(c) self.LightColor = { R = math.floor(enc(c.R) * 255.999), G = math.floor(enc(c.G) * 255.999), B = math.floor(enc(c.B) * 255.999) } end
local ctrl = obj(L .. "BP_SkyLightController_C_1", { MainSkyLight = main })
local function ppv(n, on)
    return obj(L .. n, { Settings = { AutoExposureMinBrightness = 13, AutoExposureMaxBrightness = 14, AutoExposureBias = 0,
        bOverride_AutoExposureMinBrightness = on, bOverride_AutoExposureMaxBrightness = on, bOverride_AutoExposureBias = on } })
end
local ppv1, ppv2 = ppv("PostProcessVolume_1", true), ppv("PostProcessVolume_2", false)
all.CloudlyRenderer, all.BP_SkyLightController_C, all.PostProcessVolume = { rend }, { ctrl }, { ppv1, ppv2 }
-- (the cockpit view's own post-process component: min 11, priority 1000; not a PostProcessVolume)
local cockpitPP = obj(L .. "BP_PostProcessMisssionBase_C_0.CockpitViewPostProcess", { Settings = { AutoExposureMinBrightness = 11,
    bOverride_AutoExposureMinBrightness = true, AutoExposureMaxBrightness = 20, bOverride_AutoExposureMaxBrightness = false } })
all.BP_PostProcessMisssionBase_C = { obj(L .. "BP_PostProcessMisssionBase_C_0", { CockpitViewPostProcess = cockpitPP }) }
local cvars = { ["r.MinScreenRadiusForLights"] = 0.03 }
statics["/Script/Engine.Default__KismetSystemLibrary"] = obj("/Script/Engine.Default__KismetSystemLibrary", {
    GetConsoleVariableFloatValue = function(_, n) return cvars[n] end,
    ExecuteConsoleCommand = function(_, wc, cmd) local n, v = cmd:match("^(%S+) (%S+)$"); cvars[n] = tonumber(v) end })
local env, vfx = obj("/Game/Base/Material/MPC/MPC_Env_Control.MPC_Env_Control"), obj("/Game/Base/Material/MPC/MPC_VFX_Control.MPC_VFX_Control")
local mec = obj("/Game/Base/Material/MPC/MPC_MEC_EmissiveControl.MPC_MEC_EmissiveControl")
statics[C.mpc_env], statics[C.mpc_vfx], statics[C.mpc_mec], statics[ASSET_PATH] = env, vfx, mec, asset
local mpcv = { [env.addr .. "Ctrl_Scene_EmissiveScale"] = 1, [vfx.addr .. "VFXEmissiveEV"] = 11, [vfx.addr .. "VFXCloudlySkyAmbientLight"] = 1,
               [mec.addr .. "Cockpit_MFD_EmissiveIntensity"] = 1, [mec.addr .. "Cockpit_Meter_EmissiveIntensity"] = 1,
               [mec.addr .. "Ice_Emissive_Intensity"] = 1, [mec.addr .. "Navigation_Emissive_Intensity"] = 0,
               [mec.addr .. "AntiCollision_Emissive_Intensity"] = 0, [mec.addr .. "FormationEmissive_Intensity"] = 0 }
statics["/Script/Engine.Default__KismetMaterialLibrary"] = obj("/Script/Engine.Default__KismetMaterialLibrary", {
    GetScalarParameterValue = function(_, wc, coll, n) return mpcv[coll.addr .. tostring(n)] or 0 end,
    SetScalarParameterValue = function(_, wc, coll, n, v) mpcv[coll.addr .. tostring(n)] = v end })
local custom = { sun = false, moon = false, calls = {} }
local pc = obj(L .. "PlayerController_0")
statics["/Script/Cloudly.Default__CloudlyActor"] = obj("/Script/Cloudly.Default__CloudlyActor", {
    GetCachedCloudlyActor = function(_, ctx) return ctx and actor or nil end,
    GetUseCustomSun = function() return custom.sun end, SetUseCustomSun = function(_, ctx, v) custom.sun = v; custom.calls[#custom.calls + 1] = "sun " .. tostring(v) end,
    GetUseCustomMoon = function() return custom.moon end, SetUseCustomMoon = function(_, ctx, v) custom.moon = v end,
    -- (the API writes the sky asset, as in game: its sun, and the moon on at its spot, phase 0)
    SetCustomSunPosition = function(_, ctx, el, az, force)
        custom.sun, custom.el, custom.az = force, el, az; custom.calls[#custom.calls + 1] = "pos " .. el .. " " .. az
        asset.Data.SunElevationAngleInDegrees, asset.Data.SunAzimuthAngleInDegrees = el, az
    end,
    SetCustomMoonPosition = function(_, ctx, el, az, force)
        custom.moon, custom.mel, custom.maz = force, el, az
        asset.Data.EnableMoon, asset.Data.MoonElevationAngleInDegrees, asset.Data.MoonAzimuthAngleInDegrees, asset.Data.MoonPhase = true, el, az, 0
    end,
    ForceUpdateShadows = function() custom.shadows = (custom.shadows or 0) + 1 end })
-- the game's frame, as the sky test read it in game (2026-11-07): Cloudly copies its sky asset into the drawn copy (ro)
-- and onto the sun light (rotation, intensity, colour bytes) every frame; the working copy `our` is left alone; the VFX
-- EV put back to its stock 11 (regame). drawnFrom: a game whose drawn copy doesn't follow the asset (a frozen sky)
local regame, drawnFrom = false, nil
local function frame()
    local src = drawnFrom or asset.Data
    for k, v in pairs(src) do
        if type(v) == "table" then
            ro[k] = ro[k] or {}
            for k2, v2 in pairs(v) do
                if type(v2) == "table" then ro[k][k2] = { X = v2.X, Y = v2.Y, Z = v2.Z } else ro[k][k2] = v2 end
            end
        else ro[k] = v end
    end
    local y = (src.SunAzimuthAngleInDegrees + 90) % 360
    if y > 180 then y = y - 360 end
    sun.rot = { Pitch = -src.SunElevationAngleInDegrees, Yaw = y, Roll = 0 }
    sun.Intensity = src.SunIntensity.Factor
    local c = src.SunIntensity.RGB
    sun.LightColor = { R = math.floor(c.X * 255 + 0.5), G = math.floor(c.Y * 255 + 0.5), B = math.floor(c.Z * 255 + 0.5) }
    if regame then mpcv[vfx.addr .. "VFXEmissiveEV"] = 11 end
end

part(MOD, "sv_sky.lua")
local function press(k) assert(binds[k], "no bind for " .. k)(); KEYQ.drain() end
local function tick(s) clock = clock + s; frame(); for _, t in ipairs(TEST_TICKS) do t.fn(clock) end end
local function found(pat) for i = #logs, 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end return nil end
local function deep(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deep(v) end return o end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b or (type(a) == "number" and math.abs(a - b) < 1e-6) end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function state() return { asset = deep(asset.Data), our = deep(our), ro = deep(ro), interp = deep(interp.Data), sunI = sun.Intensity, sunC = deep(sun.LightColor),
    rot = deep(sun.rot), mainI = main.Intensity, mainC = deep(main.LightColor), p1 = deep(ppv1.Settings), p2 = deep(ppv2.Settings),
    mpc = deep(mpcv), custom = { custom.sun, custom.moon }, spec = sun.SpecularScale, cockpit = deep(cockpitPP.Settings),
    cvars = deep(cvars), res = { actor.CloudlyResources.StarCatalog, actor.CloudlyResources.MoonTexture } } end
local assetBefore = deep(asset.Data)

print("read")
survivalPC = pc
D = { now = 10, round = 3, state = "fighting", up = {} }
local V = SKY.view()
check(V.actor == actor and V.actorBy == "GetCachedCloudlyActor" and V.interpOk == true and #V.rend == 1 and #V.ctrl == 1 and #V.ppv == 3
    and V.ppv[3].obj == cockpitPP and V.ppv[3].cap == true,
    "the view: the actor by GetCachedCloudlyActor, the run-time interpolated params, a renderer, a sky light, two volumes and the cockpit's")
local snap = SKY.read(V)
local want = { "asset|sun_el", "interp|sun_el", "copy|CloudlyRenderer_0|Our|1|sun_el", "copy|CloudlyRenderer_0|RO|1|stars_mask", "light|pitch",
               "light|r", "cskyl|int", "skyl|BP_SkyLightController_C_1|int", "ppv|PostProcessVolume_1|bias", "mpc|vfx|VFXEmissiveEV", "custom|sun" }
local okKeys = true
for _, k in ipairs(want) do if snap.val[k] == nil then okKeys = false; print("    missing " .. k) end end
check(okKeys, "every kind of value read (" .. #snap.keys .. ")")
check(snap.ro["cskyl|int"] and not snap.ro["asset|sun_el"] and not snap.ro["interp|sun_el"] and not snap.ro["light|pitch"],
    "the sky asset writable (written only when asked: v.asset), Cloudly's sky light read only")

print("apply")
local before = state()
local n = SKY.apply({ sun = { el = 35, az = -130, factor = 0.5, rgb = { 0.89, 0.96, 1.0 }, disc = 0.57 }, custom = true,
    moon = { enable = true, el = 35, az = -130 }, stars = { enable = true, intensity = 7, background = 22, radius = 2.5, fraction = 0.73,
    rotation = { 2.578, 0, 0 }, mask_start = 0.263 }, exposure = { min = 0.5, max = 9, bias = 0.5 }, skylight = { x = 0.1, rgb = { 0.55, 0.65, 1 } },
    mpc = { emissive = 10000, vfx_ev = -2 } }, "night")
check(asset.Data.SunIntensity.Factor == 120000 and asset.Data.StarsParams.StarsIntensity == 4 and asset.Data.SunElevationAngleInDegrees == 35
    and asset.Data.EnableMoon == true, "v.asset not asked: the asset's own values untouched, but the sun and moon the custom sun API moved")
check(our.SunElevationAngleInDegrees == 35 and ro.SunAzimuthAngleInDegrees == -130 and our.StarsParams.StarsIntensity == 7
    and our.StarsParams.StarsGlobalRotation.X == 2.578 and our.SunIntensity.RGB.Y == 0.96 and our.EnableMoon == true, "the copies written")
check(interp.Data.SunElevationAngleInDegrees == 35, "the run-time interpolated params written")
check(sun.rot.Pitch == -35 and sun.rot.Yaw == -40 and sun.Intensity == 0.5 and sun.LightColor.R == 227 and sun.LightColor.B == 255,
    "the light: pitch -35, yaw -40, intensity 0.5, colour 227 245 255 (" .. sun.LightColor.R .. " " .. sun.LightColor.G .. " " .. sun.LightColor.B .. ")")
check(math.abs(main.Intensity - 0.2) < 1e-9, "the sky light x 0.1 (" .. main.Intensity .. ")")
check(ppv1.Settings.AutoExposureMinBrightness == 0.5 and ppv1.Settings.AutoExposureBias == 0.5 and ppv2.Settings.AutoExposureMinBrightness == 13,
    "the exposure on the volume with its override on, not the other")
check(mpcv[env.addr .. "Ctrl_Scene_EmissiveScale"] == 10000 and mpcv[vfx.addr .. "VFXEmissiveEV"] == -2, "the MPCs")
check(custom.sun == true and custom.el == 35 and custom.az == -130 and custom.moon == true and custom.mel == 35, "the custom sun and moon through the API")
local wl = found("sky: night: wrote copy|CloudlyRenderer_0|Our|1: ")
check(n > 40 and wl and wl:find("sun_el 15 -> 35", 1, true) and wl:find("moon_on false -> true", 1, true), "logged every value written (" .. n .. "): " .. tostring(wl))
SKY.apply({ skylight = { x = 0.1 } }, "again")
check(math.abs(main.Intensity - 0.2) < 1e-9, "a second x 0.1 of the original, not compounded (" .. main.Intensity .. ")")

print("restore")
local put, rb = SKY.restore("test")
local after = state()
check(same(after.our, before.our) and same(after.ro, before.ro) and same(after.interp, before.interp), "the copies and the interpolated params as they were")
check(same(after.rot, before.rot) and after.sunI == before.sunI and same(after.sunC, before.sunC), "the light as it was (colour bytes exact)")
check(after.mainI == before.mainI and same(after.mainC, before.mainC), "the sky light as it was (" .. main.LightColor.R .. " " .. main.LightColor.G .. " " .. main.LightColor.B .. ")")
check(same(after.p1, before.p1) and same(after.mpc, before.mpc), "the exposure and the MPCs as they were")
check(custom.sun == false and custom.moon == false and custom.calls[#custom.calls] == "sun false", "the custom sun off again")
check(same(asset.Data, assetBefore), "the sky asset as shipped again (the custom sun's and moon's moves put back: 35 / -130, the moon on, phase 0)")
check(put == rb and put > 40 and #SKY.order == 0 and next(SKY.orig) == nil, "every value put back and read back as it was (" .. put .. "), nothing kept")
check(found("sky: test: put back " .. put .. " of " .. put .. " changed values, " .. put .. " read back as they were") ~= nil, "logged")

-- ((2026-11-07) the arc's path: the asset itself, which Cloudly draws the sky and its light from every frame)
print("the sky asset (v.asset)")
local nA = SKY.apply({ sun = { el = 4, az = -120, factor = 1000, rgb = { 1, 0.5, 0.25 } }, moon = { enable = true, el = 30, az = 60 },
    stars = { intensity = 7 }, asset = true, copies = false, light = false }, "asset")
check(asset.Data.SunElevationAngleInDegrees == 4 and asset.Data.SunAzimuthAngleInDegrees == -120 and asset.Data.SunIntensity.Factor == 1000
    and asset.Data.SunIntensity.RGB.Y == 0.5 and asset.Data.EnableMoon == true and asset.Data.MoonAzimuthAngleInDegrees == 60
    and asset.Data.StarsParams.StarsIntensity == 7, "the asset written (" .. nA .. " values)")
check(our.SunElevationAngleInDegrees == 15 and ro.SunElevationAngleInDegrees == 15 and sun.Intensity == 120000, "nothing else written")
check(SKY.assetPath == ASSET_PATH, "its path noted, without the class: " .. tostring(SKY.assetPath))
frame()
check(ro.SunElevationAngleInDegrees == 4 and ro.SunIntensity.Factor == 1000 and sun.rot.Pitch == -4 and sun.rot.Yaw == -30
    and sun.Intensity == 1000 and sun.LightColor.G == 128, "a frame on: the drawn copy and the sun light follow it (the game's own copy)")
SKY.restore("test")
check(same(asset.Data, assetBefore) and #SKY.order == 0 and SKY.assetPath == nil, "put back exactly, nothing kept")
frame()

print("the interpolated params a stock asset")
actor.CloudlyInterpolatedSkyParamsAsset = asset
SKY.apply({ sun = { el = 5 } }, "stock interp")
check(asset.Data.SunElevationAngleInDegrees == 15, "never written when they're the stock asset")
SKY.restore("test")
actor.CloudlyInterpolatedSkyParamsAsset = interp

print("the level torn down")
SKY.apply({ sun = { el = -2, az = -105 }, custom = true, copies = false, light = false }, "custom")
LEAVE.gone = true
SKY.restore("the level was left")
check(#SKY.order == 0 and SKY.pending and SKY.pending["custom|sun"] == false, "dropped untouched, the custom sun's original pending")
check(custom.sun == true, "nothing called on the torn-down level")
LEAVE.gone = false
SKY.idleTick()
check(custom.sun == false and SKY.pending == nil and found("sky: the custom sun a torn-down level left changed: put back (sun false") ~= nil,
    "put back in the next level")
check(asset.Data.SunElevationAngleInDegrees == 15 and asset.Data.SunAzimuthAngleInDegrees == 142
    and found("sky: the sky asset a torn-down level left changed: 2 of 2 values put back (" .. ASSET_PATH .. ")") ~= nil,
    "and the sky asset's sun the custom sun moved (the asset outlives the level), found by its path")
SKY.apply({ sun = { el = -2, az = -105 }, custom = true, copies = false, light = false }, "custom")
LEVEL_DROPS["the sky"]("test")
check(SKY.pending and #SKY.order == 0, "the gate's drop: the same")
SKY.idleTick()
check(SKY.pending ~= nil, "not again within 5 s")
clock = clock + 6
SKY.idleTick()
check(custom.sun == false and SKY.pending == nil and asset.Data.SunElevationAngleInDegrees == 15, "then put back, the asset too")
-- an asset not loaded any more: read again as shipped when it's needed (12 tries, then given up, logged)
SKY.apply({ sun = { el = 9 }, asset = true, copies = false, light = false }, "asset")
LEVEL_DROPS["the sky"]("test")
statics[ASSET_PATH] = nil
for _ = 1, 12 do clock = clock + 6; SKY.idleTick() end
check(SKY.pending == nil and found("not loaded now (" .. ASSET_PATH .. ")") ~= nil, "the asset not loaded in 12 tries: given up, logged")
statics[ASSET_PATH] = asset
asset.Data.SunElevationAngleInDegrees = 15
frame()
for _, p in ipairs({ our, ro }) do p.SunElevationAngleInDegrees, p.SunAzimuthAngleInDegrees = 15, 142 end

-- ((code review of 2026-11-07, finding 12) a value whose object isn't found at the restore is kept and tried again every
-- tick until it's put back (it was forgotten, left as the arc had it)
print("restore: a value not put back is tried again")
SKY.apply({ sun = { el = 5, az = 100 } }, "test12")
check(our.SunElevationAngleInDegrees == 5, "(the renderer's copies written)")
all.CloudlyRenderer = {}
SKY.restore("test12")
local kept = #SKY.order
check(kept > 0 and SKY.retry ~= nil and our.SunElevationAngleInDegrees == 5 and found("kept to be tried again every tick"),
      "the renderer not found: its " .. kept .. " values kept, their originals with them, logged")
SKY.retryTick()
check(#SKY.order == kept and SKY.retry ~= nil, "still not found: still kept")
all.CloudlyRenderer = { rend }
clock = clock + 11
SKY.retryTick()
check(#SKY.order == 0 and SKY.retry == nil and our.SunElevationAngleInDegrees == 15 and ro.SunAzimuthAngleInDegrees == 142
      and found("every kept value put back now"), "found again: put back (15 / 142), nothing kept, logged")
SKY.apply({ sun = { el = 5 } }, "test12")
all.CloudlyRenderer = {}
SKY.restore("test12")
LEVEL_DROPS["the sky"]("test")
check(#SKY.order == 0 and SKY.retry == nil, "the level torn down: what's kept forgotten untouched")
all.CloudlyRenderer = { rend }
LEVEL_DROPS["the sky's view"]("test")                -- (the kept view was found with no renderer: a new level's has it)
for _, p in ipairs({ our, ro }) do p.SunElevationAngleInDegrees, p.SunAzimuthAngleInDegrees = 15, 142 end

print("the test key")
check(binds.F6 ~= nil and TEST_KEYS.F6 ~= nil, "Ctrl+F6 bound through testKey")
local base = state()
press("F6")
check(SKY.test.step == 1 and found("sky test: step 1: copy|CloudlyRenderer_0|Our|1: sun_el 15") ~= nil, "step 1 logs every value")
check(same(state(), base), "step 1 writes nothing")
press("F6")
check(SKY.test.step == 1 and found("step 1's read-back is due") ~= nil, "a press before the read-back waits")
tick(C.readback_s)
check(found("sky test: step 1 read again 5 s on:") ~= nil, "step 1's read-back")
RED = { want = true, k = 0.5 }
press("F6")
check(SKY.test.step == 1 and found("VALKA's red sky is on") ~= nil, "step 2 waits while VALKA's red sky is on")
RED = { want = false, k = 0 }
press("F6")
check(custom.calls[#custom.calls] == "pos -2.0 -105.0" or custom.calls[#custom.calls] == "pos -2 -105", "step 2: the custom sun at test_sun (" .. tostring(custom.calls[#custom.calls]) .. ")")
tick(C.readback_s)
local l2 = found("sky test: step 2: the custom sun (-2 / -105): ")
check(l2 and l2:find("the sky asset follows: yes; the drawn copy (SkyParamsRO): yes; the other copies: NO; the interpolated params: NO", 1, true),
    "step 2's read-back: the asset and the drawn copy follow, the rest don't (as in game): " .. tostring(l2))
check(l2 and l2:find("the light (pitch 2, yaw -15): follows", 1, true), "and the light follows")
press("F6")
check(custom.sun == false and our.SunElevationAngleInDegrees == 4 and sun.rot.Pitch == -4, "step 3: the custom sun off, the copies and the light written")
local a3 = found("sky test: step 3 at once: ")
check(a3 and a3:find("^sky test: step 3 at once: (%d+) of %1 values read back as written$"), "step 3: every write read back at once: " .. tostring(a3))
tick(C.readback_s)
local l3 = found("sky test: step 3 read back 5 s on:")
check(l3 and l3:find("copy|CloudlyRenderer_0|RO|1|sun_az -120 -> -105", 1, true) and not l3:find("Our|1|sun_az", 1, true),
    "step 3's read-back: the drawn copy undone from the asset (the custom sun's -2 / -105 left in it), the working copy kept: " .. tostring(l3))
check(l3 and l3:find("light|yaw -30 -> -15", 1, true), "the light undone from the asset too (as in game)")
regame = true
press("F6")
check(mpcv[env.addr .. "Ctrl_Scene_EmissiveScale"] == 4000 and custom.sun == true and ppv1.Settings.AutoExposureMaxBrightness == 10
    and asset.Data.SunIntensity.Factor == 0.5, "step 4: the night set, the sky asset too")
tick(C.readback_s)
local l4 = found("sky test: step 4 read back 5 s on:")
check(l4 and l4:find("the MPC values the game put back: mpc|vfx|VFXEmissiveEV 0 -> 11", 1, true), "step 4's read-back names the MPC the game put back: " .. tostring(l4))
regame = false
press("F6")
tick(C.readback_s)
local l5 = found("sky test: put back: ")
local nb = #SKY.read().keys
check(l5 == string.format("sky test: put back: %d of %d values match the originals", nb, nb), "step 5: " .. tostring(l5))
check(same(state(), base), "the sky exactly as step 1 read it")
press("F6")
check(SKY.test.step == 1, "the next press starts again at step 1")
tick(C.readback_s)
LEVEL_DROPS["the sky test"]("test")
check(SKY.test.step == 0 and SKY.test.readAt == nil, "the level torn down: the test forgotten")

print("the day-night arc: its schedule")
RED = { want = false, k = 0 }
LEAVE.gone = false
local A = CFG.sky.arc
local base0 = SKY.arcBase(nil)
local function near(a, b, e) return type(a) == "number" and math.abs(a - b) <= (e or 1e-6) end
local a0, a1, a5 = SKY.arcAnchor(0, base0), SKY.arcAnchor(1, base0), SKY.arcAnchor(5, base0)
check(a0.el == 15 and a0.az == 142 and a0.stars == 0, "F (GONE FISHIN'): the stock sky, 15 / 142")
check(a1.el == 12.5 and a1.az == 145 and a1.stars == 1 and a5.el == 3 and a5.az == 157, "F+1 .. F+5: the sun sinks where it is (12.5 / 145 .. 3 / 157), the stars at their maximum")
check(near(a5.ex_min, 11) and near(a5.ex_bias, -0.5) and near(a1.ex_min, 12.6), "the exposure to dusk's 11 / 14 / -0.5 by F+5")
local a6, a7, a8 = SKY.arcAnchor(6, base0), SKY.arcAnchor(7, base0), SKY.arcAnchor(8, base0)
check(a6.el == 1 and a6.az == 160 and a6.set_el == -3 and a6.sl_x == 0.5 and a6.mode == "sun", "F+6 (THE FESTIVAL): sunset, 1 sinking to -3 / 160")
check(a7.mode == "moon" and a7.el == 35 and a7.az == -130 and a7.factor == 0.5 and a7.moon == 1 and a7.em == 4000 and a7.vfx == 0
    and near(a7.ex_min, 2.3) and near(a7.ex_max, 10) and near(a7.ex_bias, 0.6) and a7.disc == 0.5683 and near(a7.sl_x, 4e-5, 1e-12) and a7.spec == 0.01
    and near(a7.mfd, 6e-4, 1e-12) and near(a7.meter, 0.007, 1e-9) and a7.nav == 1,
    "F+7: the night (0.74.25: the blend's last seconds' look): the light at the moon (35 / -130, 0.5), the moon on, exposure 2.3 / 10 / +0.6 "
    .. "with sky light x4e-5, the glow 4000, the effects' EV 0, no moon glint (specular 0.01), the cockpit dimmed, the planes' own lights on")
local a9, a10 = SKY.arcAnchor(9, base0), SKY.arcAnchor(10, base0)
check(a8.mode == "moon" and a9.mode == "moon" and a8.el == 35 and a9.factor == 0.5 and near(a9.ex_min, 2.3),
    "F+7 .. F+9: three rounds of night (night_rounds 3), the same sky")
check(near(a10.el, -4) and near(a10.az, 105) and near(a10.factor, 120000, 1e-3) and a10.mode == "sun", "F+10: dawn in the east (-4 / 105)")
local a11, a14, a30 = SKY.arcAnchor(11, base0), SKY.arcAnchor(14, base0), SKY.arcAnchor(30, base0)
check(near(a11.el, 10.225) and near(a11.az, 123.75), string.format("F+11: rising (%.3f / %.2f)", a11.el, a11.az))
check(a14.el == 52.9 and a14.az == 180 and a14.stars == 0 and near(a14.ex_min, 13) and a30.el == 52.9, "F+14 on: midday 52.9 / 180, held")
check(SKY.arcEnd() == 13, "the arc's last round F+13 (3 of night, sunrise over 4)")
local a12 = SKY.arcAnchor(12, base0)
check(near(a12.ex_min, 13) and near(a12.ex_bias, 0) and near(a12.sl_x, 1) and a12.el < 52.9 and a12.el > 20,
    string.format("F+12, the sunrise's middle: the day's light back (sunrise_light_x 2), the sun still climbing (%.1f)", a12.el))
local m2 = SKY.arcAt(2, 0.5, base0)
check(near(m2.el, 8.75) and near(m2.az, 149.5), string.format("F+2 half way to F+3: 8.75 / 149.5, mostly down (%.2f / %.1f)", m2.el, m2.az))
-- ((2026-11-07) the user's -2 / -105 at full strength: the sunset round holds its light, exposure and sky light through
-- the fight (u up to swap_within_x 0.45) while the sun sinks to set_el; the last light goes in the break, before the moon)
local s25 = SKY.arcAt(6, 0.25, base0)
check(s25.mode == "sun" and near(s25.el, 1 - 4 * 0.25 / 0.45) and near(s25.factor, 120000, 1e-3) and near(s25.ex_min, 9.5)
    and near(s25.sl_x, 0.5) and near(s25.em, 100),
    string.format("sunset, a quarter way: the sun sinking (%.2f) at full strength (%.0f), the sunset's exposure, sky light and glow held", s25.el, s25.factor))
local s45 = SKY.arcAt(6, 0.45, base0)
check(near(s45.el, -3) and near(s45.factor, 120000, 1e-3) and near(s45.ex_min, 9.5), "the fight's end (u 0.45): the sun at set_el -3, its light still held")
local s475 = SKY.arcAt(6, 0.475, base0)
check(s475.mode == "sun" and near(s475.el, -3) and near(s475.factor, 10 ^ ((math.log(120000, 10) + math.log(0.25, 10)) / 2), 1e-3)
    and s475.ex_min < 9.5 and s475.ex_min > 2.3 and s475.sl_x < 0.5 and s475.sl_x > 4e-5,
    string.format("the break's first half: the last light going in log space (%.1f), the night's exposure and ambient begun together (%.2f)", s475.factor, s475.ex_min))
local n20 = SKY.arcAt(7, 0.2, base0)
check(n20.mode == "moon" and near(n20.factor, 0.5) and near(n20.ex_min, 2.3), "the night's fight: the moon's light and the night's exposure held")
local s50, s99 = SKY.arcAt(6, 0.5, base0), SKY.arcAt(6, 1, base0)
check(s50.mode == "moon" and near(s50.factor, 0.25) and s50.el == 35 and s99.factor == 0.5, "the swap for the moon at the darkest point (0.25), then night's 0.5")
-- ((0.74.25) "a period of pitch blackness" at both swaps: the night's exposure and ambient hold the darkest point both ways)
local d9a, d9b, d9c = SKY.arcAt(9, 0.25, base0), SKY.arcAt(9, 0.5, base0), SKY.arcAt(9, 0.75, base0)
check(near(s50.ex_min, 2.3) and near(s50.sl_x, 4e-5, 1e-12) and near(d9a.ex_min, 2.3) and near(d9b.ex_min, 2.3)
    and d9c.ex_min > 2.3 and d9c.ex_min < 10 and d9c.mode == "sun",
    string.format("the darkest points under the night's exposure: into the night by the swap (%.2f), out of it held till the swap (%.2f, %.2f), then on to dawn's (%.2f)",
        s50.ex_min, d9a.ex_min, d9b.ex_min, d9c.ex_min))
local h75 = SKY.arcAt(7, 0.75, base0)
check(h75.mode == "moon" and near(h75.factor, 0.5), "the first night's break: still night (the next round's night too)")
local d75 = SKY.arcAt(9, 0.75, base0)
check(d75.mode == "sun" and d75.el == -4 and near(d75.factor, 10 ^ ((math.log(0.25, 10) + math.log(120000, 10)) / 2), 1e-3), "night to dawn: the sun back after the dark")

print("the day-night arc: VALKA's gate")
RUN = { arcF = 7 }
check(SKY.arcHoldsValka(7) and SKY.arcHoldsValka(13) and SKY.arcHoldsValka(20) and not SKY.arcHoldsValka(21) and not SKY.arcHoldsValka(6),
    "no VALKA from GONE FISHIN' (7) to the arc's midday (20); from 21 she can come")
check(not SKY.arcHoldsValka(nil), "a round not known (the bag's fill): no opinion")
A.valka_gate = false
check(not SKY.arcHoldsValka(10), "valka_gate off: no gate")
A.valka_gate = true
RUN = {}
check(not SKY.arcHoldsValka(10), "no GONE FISHIN' this run: no gate")

print("the day-night arc: on the level's sky")
local base = state()
RUN = { arcF = 7 }
D = { now = 2000, round = 9, state = "fighting", up = {} }
clock = 2000
local function atick(dt) clock = clock + (dt or 0); D.now = clock; frame(); SKY.arcTick(clock) end
atick(0)
check(ARC.on and ARC.base and ARC.base.from:find("the level's", 1, true), "the stock sky read from the level: " .. tostring(ARC.base and ARC.base.from))
check(found("sky: arc: the stock sky from the level's") and found("written through the level's sky asset"), "logged, with the write path (the asset)")
check(not found("the sky asset was left changed"), "the asset as shipped: nothing to put right")
for _ = 1, 4 do atick(2) end
check(not ARC.blendFrom, "blended in over blend_s")
for _ = 1, 120 do atick(2) end
check(near(asset.Data.SunElevationAngleInDegrees, 8.125, 0.05) and near(ro.SunAzimuthAngleInDegrees, 150.25, 0.1) and near(sun.rot.Pitch, -8.125, 0.05),
    string.format("F+2, 240 s in: three quarters of the way to F+3 (%.2f / %.2f, the light's pitch %.2f)", asset.Data.SunElevationAngleInDegrees,
        ro.SunAzimuthAngleInDegrees, sun.rot.Pitch))
check(our.SunElevationAngleInDegrees == 15, "the working copy not written (the asset is the path)")
local fl = found("sky: arc: the drawn sky follows the arc: ")
check(fl ~= nil and not ARC.noFollow, "checked once off the stock sky: " .. tostring(fl))
mpcv[vfx.addr .. "VFXEmissiveEV"] = 99
atick(0.25)
check(mpcv[vfx.addr .. "VFXEmissiveEV"] == 11, "the MPCs written again the next tick (the game put one back)")
D.state, D.at = "wait", clock + 20
atick(0)
for _ = 1, 10 do atick(2) end
check(near(asset.Data.SunElevationAngleInDegrees, 7.5, 0.01) and near(asset.Data.SunAzimuthAngleInDegrees, 151, 0.01), "the break finishes the step: F+3's 7.5 / 151")
-- the festival's round (F+6) into the night (F+7): the swap at the break's darkest point
D.round, D.state = 13, "fighting"
for _ = 1, 200 do atick(2) end
check(ARC.last.mode == "sun" and near(ARC.last.u, A.swap_within_x, 1e-6), string.format("F+6's fight: the sun goes down, the swap held for the break (u %.2f)", ARC.last.u))
D.state, D.at = "wait", clock + 20
atick(0)
atick(4)
check(ARC.last.mode == "sun", "the break's start: still the sun, darkening")
for _ = 1, 3 do atick(2) end
check(ARC.last.mode == "moon" and found("the sun swapped for the moon at the break's darkest point"), "the break's middle: the moon")
for _ = 1, 5 do atick(2) end
frame()                                          -- (the drawn sky and the light follow the asset a frame on)
check(ro.EnableMoon == true and near(sun.Intensity, 0.5, 1e-6) and sun.LightColor.R == 226 and near(ro.SunElevationAngleInDegrees, 35, 1e-6),
    "night (F+7): the light at the moon, 0.5, bluish; the moon on (drawn)")
check(near(ppv1.Settings.AutoExposureMinBrightness, 2.3, 1e-6) and ppv2.Settings.AutoExposureMinBrightness == 13 and near(ro.StarsParams.StarsIntensity, 2.26, 1e-6),
    "night's exposure on the volume with its override, the stars at Mission 9's")
-- ((2026-11-08) the rest of Mission 9's night (tools/re/NIGHT_SKY.md 5)
check(sun.SpecularScale == 0.01 and near(cockpitPP.Settings.AutoExposureMinBrightness, 2.3, 1e-6) and cockpitPP.Settings.AutoExposureMaxBrightness == 20,
    "night: no moon glint on the sea (the light's specular 0.01), the cockpit view's exposure down with the rest (its max untouched)")
check(near(mpcv[mec.addr .. "Cockpit_MFD_EmissiveIntensity"], 6e-4, 1e-9) and near(mpcv[mec.addr .. "Cockpit_Meter_EmissiveIntensity"], 0.007, 1e-9)
    and mpcv[mec.addr .. "Navigation_Emissive_Intensity"] == 1 and mpcv[mec.addr .. "AntiCollision_Emissive_Intensity"] == 1
    and near(cvars["r.MinScreenRadiusForLights"], 0.01, 1e-9),
    "night: the cockpit's screens and gauges dimmed, the planes' own lights on, far small lights drawn (r.MinScreenRadiusForLights 0.01)")
check(actor.CloudlyResources.StarCatalog == catalog and actor.CloudlyResources.MoonTexture == moonTex
    and found("the stars and the moon on the sky actor"),
    "the star catalog and the moon's texture put on the sky actor (Mission 4's had neither), logged")
check(ro.StarsParams.StarsElevationMaskEnable == true and near(ro.StarsParams.StarsFadePower, 14.77, 1e-6) and ro.StarsParams.StarsMoonMaskEnable == true
    and near(ro.MultipleScatteringScale, 2.7, 1e-6) and near(ro.MoonPhase, 0.143, 1e-6) and near(ro.MoonFractionOfSunIntensity, 1e-5, 1e-12),
    "Mission 9's stars (masks, fade), its night sky's multiple scattering, its moon's phase and brightness")
-- VALKA's red sky over the arc: the colours left to it
RED = { want = true, k = 0.3 }
asset.Data.SunIntensity.RGB = { X = 1, Y = 60 / 255, Z = 40 / 255 }    -- (her red: sv_hud.lua writes the asset's sun colour)
D.round, D.state = 14, "fighting"
for _ = 1, 3 do atick(2) end
check(sun.LightColor.G == 60 and near(sun.Intensity, 0.5, 0.02), "VALKA's red sky on: the arc leaves the colours to it, the rest goes on")
RED = { want = false, k = 0 }
for _ = 1, 2 do atick(2) end
check(sun.LightColor.R == 226, "her sky gone: the arc's colours again")
-- midday, held
D.round = 21
for _ = 1, 3 do atick(2) end
check(near(ro.SunElevationAngleInDegrees, 52.9, 1e-6) and near(ro.SunAzimuthAngleInDegrees, 180, 1e-6) and ro.EnableMoon == false,
    "F+14 on: midday 52.9 / 180, the moon off")
D.round = 40
atick(2)
check(near(asset.Data.SunElevationAngleInDegrees, 52.9, 1e-6), "held for the rest of the run")
-- a new run with no GONE FISHIN': everything put back
RUN = {}
atick(2)
frame()                                          -- (the game's next frame copies the asset back into the drawn sky)
check(not ARC.on and same(state(), base), "the run has no F: everything the arc changed put back exactly (the asset too)")

print("the day-night arc: a late joiner, the custom sun, a restart")
RUN = { arcF = 3 }
D = { now = 3000, round = 10, state = "fighting", up = {} }
clock = 3000
atick(0)
local el0 = asset.Data.SunElevationAngleInDegrees
atick(2)
check(el0 > 14 and ARC.blendFrom ~= nil, string.format("joining at F+7: blending in from the stock sky (%.1f)", el0))
for _ = 1, 3 do atick(2) end
check(near(asset.Data.SunElevationAngleInDegrees, 35, 0.5), "5 s on: the night's sky")
SKY.arcReset("test: a restart")
frame()
check(not ARC.on and same(state(), base), "SKY.arcReset: put back now")
A.path = "custom"
RUN = { arcF = 8 }
D = { now = 4000, round = 9, state = "fighting", up = {} }
clock = 4000
custom.calls = {}
for _ = 1, 4 do atick(2) end
check(custom.calls[#custom.calls] and custom.calls[#custom.calls]:find("^pos 12%.") and found("written through Cloudly's custom sun"),
    "path custom: Cloudly's custom sun API too (" .. tostring(custom.calls[#custom.calls]) .. ")")
SKY.arcReset("test")
A.path = "asset"
frame()
check(custom.sun == false and same(state(), base), "the custom sun off again with the rest (the asset's sun it moved too)")
-- the co-op host's F to a joiner: SKY.arcSet
RUN = {}
check(SKY.arcSet(12, "the host's") == true and RUN.arcF == 12 and SKY.arcSet(12, "again") == false, "SKY.arcSet: F kept in RUN once")
LEVEL_DROPS["the sky's arc"]("test")
check(not ARC.on and ARC.base == nil, "the level torn down: the arc forgotten untouched")

-- ((2026-11-07) the user's game: the sky test's custom sun left the asset at 35 / -130 with the moon on)
print("the day-night arc: a sky asset an earlier run left changed")
LEVEL_DROPS["the sky's view"]("test")
asset.Data.SunElevationAngleInDegrees, asset.Data.SunAzimuthAngleInDegrees, asset.Data.EnableMoon, asset.Data.MoonPhase = 35, -130, true, 0
frame()
RUN = { arcF = 9 }
D = { now = 7000, round = 9, state = "fighting", up = {} }
clock = 7000
atick(0)
local dl = found("sky: arc: the sky asset was left changed by an earlier run or test (4 values: ")
check(dl ~= nil and dl:find("sun_el 35 (shipped 15)", 1, true) and dl:find("moon_on true (shipped false)", 1, true), "found and logged: " .. tostring(dl))
check(ARC.base.el == 15 and ARC.base.az == 142 and ARC.base.moon == 0, "the arc starts from the shipped sky")
for _ = 1, 4 do atick(2) end
check(near(asset.Data.SunElevationAngleInDegrees, 15, 0.1) and near(asset.Data.SunAzimuthAngleInDegrees, 142, 1) and asset.Data.EnableMoon == false,
    string.format("F: the shipped sky written (%.3f / %.2f, 8 s of drift toward F+1; no moon)", asset.Data.SunElevationAngleInDegrees, asset.Data.SunAzimuthAngleInDegrees))
SKY.arcReset("test")
check(same(asset.Data, assetBefore), "put back as shipped at the end")
frame()

-- a game whose drawn sky doesn't follow the asset: found in 3 checks; no glare (the day's exposure kept)
print("the day-night arc: a drawn sky that doesn't follow")
drawnFrom = params()
LEVEL_DROPS["the sky's view"]("test")
RUN = { arcF = 3 }
D = { now = 8000, round = 10, state = "fighting", up = {} }
clock = 8000
for _ = 1, 10 do atick(2) end
check(ARC.noFollow == true and found("sky: arc: the drawn sky does NOT follow the arc (3 checks running): the drawn sun at 15.00") ~= nil,
    "found after 3 checks, logged")
check(near(ppv1.Settings.AutoExposureMinBrightness, 13, 1e-6) and near(main.Intensity, 2.0, 1e-9) and mpcv[env.addr .. "Ctrl_Scene_EmissiveScale"] == 1,
    "the night's exposure, sky light and glow not applied: the day's kept (no glare)")
SKY.arcReset("test")
drawnFrom = nil
frame()
check(same(state(), base) and not ARC.noFollow, "put back; the check starts afresh")

-- ((code review of 2026-11-07, finding 4) the arc's view kept while every object of it is live, however old (it walked
-- 3-5 FindAllOf every 30 s), found afresh when one goes, and with no sky actor looked for at most every 10 s (each tick
-- half before)
print("the day-night arc: the kept view")
local views = 0
local rawFind = FindAllOf
FindAllOf = function(cls) if cls == "CloudlyRenderer" then views = views + 1 end return rawFind(cls) end
LEVEL_DROPS["the sky's view"]("test")
RUN = { arcF = 8 }
D = { now = 6000, round = 9, state = "fighting", up = {} }
clock = 6000
atick(0)
local v0 = views
for _ = 1, 60 do atick(2) end
check(v0 >= 1 and views == v0, "120 s with every object live: the view kept, no walk (" .. (views - v0) .. " walks; one every 30 s before)")
ppv2.gone = true
atick(2)
check(views == v0 + 1, "an object of it gone: found afresh at once")
ppv2.gone = nil
SKY.arcReset("test")
LEVEL_DROPS["the sky's arc"]("test")
LEVEL_DROPS["the sky's view"]("test")
local dco = statics["/Script/Cloudly.Default__CloudlyActor"]
local rawGet = dco.GetCachedCloudlyActor
dco.GetCachedCloudlyActor = function() return nil end
RUN = { arcF = 8 }
local v1 = views
for _ = 1, 40 do atick(0.25) end
check(views - v1 >= 1 and views - v1 <= 2, "no sky actor: looked for again at most every 10 s (" .. (views - v1) .. " walks in 10 s of tick halves; one each before)")
dco.GetCachedCloudlyActor = rawGet
FindAllOf = rawFind
SKY.arcReset("test")
LEVEL_DROPS["the sky's arc"]("test")
LEVEL_DROPS["the sky's view"]("test")
for _, p in ipairs({ our, ro }) do p.SunElevationAngleInDegrees, p.SunAzimuthAngleInDegrees = 15, 142 end
check(same(asset.Data, assetBefore), "the sky asset as shipped after every run of the arc")

print("the day-night arc: the step key (Ctrl+PAGE_DOWN)")
check(binds.PAGE_DOWN ~= nil, "Ctrl+PAGE_DOWN bound")
D = { now = 5000, round = 10, state = "fighting", up = {} }
RUN = { arcF = 8 }
press("PAGE_DOWN")
check(RUN.arcF == 7 and found("test: Ctrl+PAGE_DOWN, the arc stepped: F 8 -> 7 (round 10 is F+3)"), "F one less: one round on")
RUN = {}
press("PAGE_DOWN")
check(RUN.arcF == 9, "no F yet: the arc from this round (F+1)")
SKY.arcReset("test")
RUN = nil

print("a release's copy")
SKY, testKey, TEST_TICKS, TEST_KEYS = nil, nil, nil, nil
local src = readAll(STRIPPED .. "/Scripts/sv_sky.lua")
check(not src:find("TEST ONLY", 1, true) and not src:find("testKey", 1, true) and not src:find("TEST_TICKS", 1, true), "no test code left in it")
part(STRIPPED, "sv_sky.lua")
check(SKY.test == nil and type(SKY.apply) == "function" and type(SKY.restore) == "function" and type(SKY.idleTick) == "function",
    "it loads with apply / restore / idleTick")
local mainSrc = readAll(STRIPPED .. "/Scripts/sv_main.lua")
check(mainSrc:find("SKY.restore", 1, true) ~= nil and mainSrc:find("SKY.idleTick", 1, true) ~= nil and mainSrc:find("SKY.arcTick", 1, true) ~= nil
    and mainSrc:find("SKY.arcReset", 1, true) ~= nil and not mainSrc:find("TEST_TICKS", 1, true),
    "sv_main.lua's release copy: the restore at a run's end and the idle tick kept, the test ticks gone")

print(fails == 0 and "sky test: all passed" or ("sky test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
