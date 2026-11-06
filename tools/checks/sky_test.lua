-- sky_test.lua <mod dir> <work dir> <stripped dir> (run by tools/checks/sky_test.sh): the sky Survival changes
-- (Scripts/sv_sky.lua; tools/re/FISHING.md 5) and its test key on the real sv_core, sv_config and sv_sky, the game stubbed
-- (a Cloudly actor, its stock sky asset, a renderer's working copies, the sun light, a sky light controller, two
-- post-process volumes, the two MPCs, Cloudly's custom sun):
--   SKY.read: every value it can see, the stock asset's read only;
--   SKY.apply: the renderer's copies, the light (pitch -elevation, yaw azimuth + 90, intensity, colour bytes), the sky light
--     (x its original: never compounded), the exposure only on volumes whose override is on, the MPCs, the custom sun
--     through its API; the stock asset never written, the interpolated params only when they're a run-time object;
--   SKY.restore: every original back exactly (colour bytes too), the custom sun's flag first; nothing kept after;
--   the level torn down: originals dropped untouched, a custom sun left on put back in the next level (SKY.idleTick);
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
local function part(dir, name, chunk) assert(load(readAll(dir .. "/Scripts/" .. name), chunk or ("=" .. name)))() end
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
local function params()
    return { SunElevationAngleInDegrees = 15, SunAzimuthAngleInDegrees = 142, bUseUnrealSunData = false,
             SunIntensity = { Factor = 120000, RGB = { X = 1, Y = 1, Z = 1 } }, SunDiskAngleInDegrees = 0.53,
             EnableMoon = false, MoonElevationAngleInDegrees = 10, MoonAzimuthAngleInDegrees = 0, MoonPhase = 0.5,
             MoonPhaseAngle = 0, MoonDiskAngleInDegrees = 0.5, MoonDiskBrightness = 1, MoonFractionOfSunIntensity = 0.01,
             StarsParams = { EnableStars = true, StarsIntensity = 1, StarsBackgroundIntensity = 1, StarsRadius = 1,
                             StarsTextureScreenFraction = 0.5, StarsGlobalRotation = { X = 0, Y = 0, Z = 0 },
                             StarsElevationMaskStart = 0.1 } }
end
local asset = obj("/Game/Environments/Sky/CSP_ms04_20251218b.CSP_ms04_20251218b", { Data = params() })
local interp = obj("/Engine/Transient.CloudlySkyParams_0", { Data = params() })
local our, ro = params(), params()
local rend = obj("/Engine/Transient.CloudlyRenderer_0", { Data = { SkyRendererMainThread = { OurSkyParams = arr({ our }) }, SkyParamsRO = arr({ ro }) } })
local sun = obj(L .. "LiveCloudlyActor_1.SunLight", { Intensity = 120000, LightColor = { R = 255, G = 250, B = 240 }, rot = { Pitch = -15, Yaw = -128, Roll = 0 } })
function sun:SetIntensity(v) self.Intensity = v end
function sun:SetLightColor(c, srgb)
    assert(srgb == false, "the sun's colour as bytes (bSRGB false)")
    self.LightColor = { R = math.floor(c.R * 255.999), G = math.floor(c.G * 255.999), B = math.floor(c.B * 255.999) }
end
function sun:K2_GetComponentRotation() return { Pitch = self.rot.Pitch, Yaw = self.rot.Yaw, Roll = self.rot.Roll } end
function sun:K2_SetWorldRotation(r) self.rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end
local cskyl = obj(L .. "LiveCloudlyActor_1.SkyLight", { Intensity = 1 })
local actor = obj(L .. "LiveCloudlyActor_1", { SunLight = sun, SkyLight = cskyl, CloudlySkyParamsAsset = asset,
    CloudlyInterpolatedSkyParamsAsset = interp, bUseSunLight = true, bUseSkyLight = false, bUseHeightFog = false })
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
local env, vfx = obj("/Game/Base/Material/MPC/MPC_Env_Control.MPC_Env_Control"), obj("/Game/Base/Material/MPC/MPC_VFX_Control.MPC_VFX_Control")
statics[C.mpc_env], statics[C.mpc_vfx] = env, vfx
local mpcv = { [env.addr .. "Ctrl_Scene_EmissiveScale"] = 1, [vfx.addr .. "VFXEmissiveEV"] = 11, [vfx.addr .. "VFXCloudlySkyAmbientLight"] = 1 }
statics["/Script/Engine.Default__KismetMaterialLibrary"] = obj("/Script/Engine.Default__KismetMaterialLibrary", {
    GetScalarParameterValue = function(_, wc, coll, n) return mpcv[coll.addr .. tostring(n)] or 0 end,
    SetScalarParameterValue = function(_, wc, coll, n, v) mpcv[coll.addr .. tostring(n)] = v end })
local custom = { sun = false, moon = false, calls = {} }
local pc = obj(L .. "PlayerController_0")
statics["/Script/Cloudly.Default__CloudlyActor"] = obj("/Script/Cloudly.Default__CloudlyActor", {
    GetCachedCloudlyActor = function(_, ctx) return ctx and actor or nil end,
    GetUseCustomSun = function() return custom.sun end, SetUseCustomSun = function(_, ctx, v) custom.sun = v; custom.calls[#custom.calls + 1] = "sun " .. tostring(v) end,
    GetUseCustomMoon = function() return custom.moon end, SetUseCustomMoon = function(_, ctx, v) custom.moon = v end,
    SetCustomSunPosition = function(_, ctx, el, az, force) custom.sun, custom.el, custom.az = force, el, az; custom.calls[#custom.calls + 1] = "pos " .. el .. " " .. az end,
    SetCustomMoonPosition = function(_, ctx, el, az, force) custom.moon, custom.mel, custom.maz = force, el, az end,
    ForceUpdateShadows = function() custom.shadows = (custom.shadows or 0) + 1 end })
-- the game's frame: the copies follow the custom sun while it's on (overwrite: from the asset, when set), the VFX EV put
-- back to its stock 11 (regame)
local overwrite, regame = false, false
local function frame()
    for _, p in ipairs({ our, ro }) do
        if custom.sun then p.SunElevationAngleInDegrees, p.SunAzimuthAngleInDegrees = custom.el, custom.az
        elseif overwrite then p.SunElevationAngleInDegrees, p.SunAzimuthAngleInDegrees = asset.Data.SunElevationAngleInDegrees, asset.Data.SunAzimuthAngleInDegrees end
    end
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
local function state() return { our = deep(our), ro = deep(ro), interp = deep(interp.Data), sunI = sun.Intensity, sunC = deep(sun.LightColor),
    rot = deep(sun.rot), mainI = main.Intensity, mainC = deep(main.LightColor), p1 = deep(ppv1.Settings), p2 = deep(ppv2.Settings),
    mpc = deep(mpcv), custom = { custom.sun, custom.moon } } end
local assetBefore = deep(asset.Data)

print("read")
survivalPC = pc
D = { now = 10, round = 3, state = "fighting", up = {} }
local V = SKY.view()
check(V.actor == actor and V.actorBy == "GetCachedCloudlyActor" and V.interpOk == true and #V.rend == 1 and #V.ctrl == 1 and #V.ppv == 2,
    "the view: the actor by GetCachedCloudlyActor, the run-time interpolated params, a renderer, a sky light, two volumes")
local snap = SKY.read(V)
local want = { "asset|sun_el", "interp|sun_el", "copy|CloudlyRenderer_0|Our|1|sun_el", "copy|CloudlyRenderer_0|RO|1|stars_mask", "light|pitch",
               "light|r", "cskyl|int", "skyl|BP_SkyLightController_C_1|int", "ppv|PostProcessVolume_1|bias", "mpc|vfx|VFXEmissiveEV", "custom|sun" }
local okKeys = true
for _, k in ipairs(want) do if snap.val[k] == nil then okKeys = false; print("    missing " .. k) end end
check(okKeys, "every kind of value read (" .. #snap.keys .. ")")
check(snap.ro["asset|sun_el"] and snap.ro["cskyl|int"] and not snap.ro["interp|sun_el"] and not snap.ro["light|pitch"], "the stock asset read only")

print("apply")
local before = state()
local n = SKY.apply({ sun = { el = 35, az = -130, factor = 0.5, rgb = { 0.89, 0.96, 1.0 }, disc = 0.57 }, custom = true,
    moon = { enable = true, el = 35, az = -130 }, stars = { enable = true, intensity = 7, background = 22, radius = 2.5, fraction = 0.73,
    rotation = { 2.578, 0, 0 }, mask_start = 0.263 }, exposure = { min = 0.5, max = 9, bias = 0.5 }, skylight = { x = 0.1, rgb = { 0.55, 0.65, 1 } },
    mpc = { emissive = 10000, vfx_ev = -2 } }, "night")
check(same(asset.Data, assetBefore), "the stock asset never written")
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
check(put == rb and put > 40 and #SKY.order == 0 and next(SKY.orig) == nil, "every value put back and read back as it was (" .. put .. "), nothing kept")
check(found("sky: test: put back " .. put .. " of " .. put .. " changed values, " .. put .. " read back as they were") ~= nil, "logged")

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
SKY.apply({ sun = { el = -2, az = -105 }, custom = true, copies = false, light = false }, "custom")
LEVEL_DROPS["the sky"]("test")
check(SKY.pending and #SKY.order == 0, "the gate's drop: the same")
SKY.idleTick()
check(SKY.pending ~= nil, "not again within 5 s")
clock = clock + 6
SKY.idleTick()
check(custom.sun == false and SKY.pending == nil, "then put back")
frame()
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
check(found("sky test: step 2: the renderer's copies follow the custom sun (-2 / -105): yes; the interpolated params: NO") ~= nil,
    "step 2's read-back: the copies follow, the interpolated params don't (as stubbed)")
check(found("the light (pitch -15, yaw -128): does NOT follow") ~= nil, "and the light doesn't (as stubbed)")
overwrite = true
press("F6")
check(custom.sun == false and our.SunElevationAngleInDegrees == 4 and sun.rot.Pitch == -4, "step 3: the custom sun off, the copies and the light written")
local a3 = found("sky test: step 3 at once: ")
check(a3 and a3:find("^sky test: step 3 at once: (%d+) of %1 values read back as written$"), "step 3: every write read back at once: " .. tostring(a3))
tick(C.readback_s)
local l3 = found("sky test: step 3 read back 5 s on:")
check(l3 and l3:find("overwritten (written -> now): copy|CloudlyRenderer_0|Our|1|sun_az -120 -> 142", 1, true), "step 3's read-back: the copies overwritten: " .. tostring(l3))
check(l3 and not l3:find("light|pitch", 1, true), "the light kept")
regame = true
press("F6")
check(mpcv[env.addr .. "Ctrl_Scene_EmissiveScale"] == 10000 and custom.sun == true and ppv1.Settings.AutoExposureMaxBrightness == 9, "step 4: the night set")
tick(C.readback_s)
local l4 = found("sky test: step 4 read back 5 s on:")
check(l4 and l4:find("the MPC values the game put back: mpc|vfx|VFXEmissiveEV -2 -> 11", 1, true), "step 4's read-back names the MPC the game put back: " .. tostring(l4))
regame, overwrite = false, false
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
check(a1.el == 14 and a1.az == 160 and a1.stars == 1 and a5.el == 4 and a5.az == -120, "F+1 .. F+5: the sun sinks (14 / 160 .. 4 / -120), the stars at their maximum")
check(near(a5.ex_min, 11) and near(a5.ex_bias, -0.5) and near(a1.ex_min, 12.6), "the exposure to dusk's 11 / 14 / -0.5 by F+5")
local a6, a7, a8 = SKY.arcAnchor(6, base0), SKY.arcAnchor(7, base0), SKY.arcAnchor(8, base0)
check(a6.el == 1 and a6.az == -105 and a6.set_el == -3 and a6.sl_x == 0.5 and a6.mode == "sun", "F+6 (THE FESTIVAL): sunset, 1 sinking to -3 / -105")
check(a7.mode == "moon" and a7.el == 35 and a7.az == -130 and a7.factor == 0.5 and a7.moon == 1 and a7.em == 10000 and a7.vfx == -2
    and near(a7.ex_min, 0.5) and a7.disc == 0.57, "F+7: night, the light at the moon (35 / -130, 0.5), the moon on, the city's glow")
check(near(a8.el, -4) and near(a8.az, 105) and near(a8.factor, 120000, 1e-3) and a8.mode == "sun", "F+8: dawn in the east (-4 / 105)")
local a9, a12, a30 = SKY.arcAnchor(9, base0), SKY.arcAnchor(12, base0), SKY.arcAnchor(30, base0)
check(near(a9.el, 10.225) and near(a9.az, 123.75), string.format("F+9: rising (%.3f / %.2f)", a9.el, a9.az))
check(a12.el == 52.9 and a12.az == 180 and a12.stars == 0 and near(a12.ex_min, 13) and a30.el == 52.9, "F+12 on: midday 52.9 / 180, held")
check(SKY.arcEnd() == 11, "the arc's last round F+11 (sunrise over 4)")
local m2 = SKY.arcAt(2, 0.5, base0)
check(near(m2.el, 11) and near(m2.az, -170), string.format("F+2 half way to F+3: 11 / -170 the short way round (%.1f / %.1f)", m2.el, m2.az))
local s25 = SKY.arcAt(6, 0.25, base0)
check(s25.mode == "sun" and near(s25.el, -1) and near(s25.factor, 10 ^ ((math.log(120000, 10) + math.log(0.25, 10)) / 2), 1e-3),
    string.format("sunset to night, a quarter way: the sun sinking (%.1f), its light down in log space (%.1f)", s25.el, s25.factor))
local s50, s99 = SKY.arcAt(6, 0.5, base0), SKY.arcAt(6, 1, base0)
check(s50.mode == "moon" and near(s50.factor, 0.25) and s50.el == 35 and s99.factor == 0.5, "the swap for the moon at the darkest point (0.25), then night's 0.5")
local d75 = SKY.arcAt(7, 0.75, base0)
check(d75.mode == "sun" and d75.el == -4 and near(d75.factor, 10 ^ ((math.log(0.25, 10) + math.log(120000, 10)) / 2), 1e-3), "night to dawn: the sun back after the dark")

print("the day-night arc: VALKA's gate")
RUN = { arcF = 7 }
check(SKY.arcHoldsValka(7) and SKY.arcHoldsValka(13) and SKY.arcHoldsValka(18) and not SKY.arcHoldsValka(19) and not SKY.arcHoldsValka(6),
    "no VALKA from GONE FISHIN' (7) to the arc's midday (18); from 19 she can come")
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
check(found("sky: arc: the stock sky from the level's") and found("written through the renderer's copies and the light's rotation"), "logged, with the write path")
for _ = 1, 4 do atick(2) end
check(not ARC.blendFrom, "blended in over blend_s")
for _ = 1, 120 do atick(2) end
check(near(our.SunElevationAngleInDegrees, 10.5, 0.05) and near(ro.SunAzimuthAngleInDegrees, -165, 0.1) and near(sun.rot.Pitch, -10.5, 0.05),
    string.format("F+2, 240 s in: three quarters of the way to F+3 (%.2f / %.2f, the light's pitch %.2f)", our.SunElevationAngleInDegrees,
        ro.SunAzimuthAngleInDegrees, sun.rot.Pitch))
check(asset.Data.SunElevationAngleInDegrees == 15, "the stock asset never written")
mpcv[vfx.addr .. "VFXEmissiveEV"] = 99
atick(0.25)
check(mpcv[vfx.addr .. "VFXEmissiveEV"] == 11, "the MPCs written again the next tick (the game put one back)")
D.state, D.at = "wait", clock + 20
atick(0)
for _ = 1, 10 do atick(2) end
check(near(our.SunElevationAngleInDegrees, 10, 0.01) and near(our.SunAzimuthAngleInDegrees, -160, 0.01), "the break finishes the step: F+3's 10 / -160")
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
check(our.EnableMoon == true and near(sun.Intensity, 0.5, 1e-6) and sun.LightColor.R == 227 and near(our.SunElevationAngleInDegrees, 35, 1e-6),
    "night (F+7): the light at the moon, 0.5, bluish; the moon on")
check(near(ppv1.Settings.AutoExposureMinBrightness, 0.5, 1e-6) and ppv2.Settings.AutoExposureMinBrightness == 13 and our.StarsParams.StarsIntensity == 7,
    "night's exposure on the volume with its override, the stars at their maximum")
-- VALKA's red sky over the arc: the colours left to it
RED = { want = true, k = 0.3 }
sun.LightColor = { R = 255, G = 60, B = 40 }
D.round, D.state = 14, "fighting"
for _ = 1, 3 do atick(2) end
check(sun.LightColor.G == 60 and near(sun.Intensity, 0.5, 0.02), "VALKA's red sky on: the arc leaves the colours to it, the rest goes on")
RED = { want = false, k = 0 }
for _ = 1, 2 do atick(2) end
check(sun.LightColor.R == 227, "her sky gone: the arc's colours again")
-- midday, held
D.round = 19
for _ = 1, 3 do atick(2) end
check(near(our.SunElevationAngleInDegrees, 52.9, 1e-6) and near(our.SunAzimuthAngleInDegrees, 180, 1e-6) and our.EnableMoon == false,
    "F+12 on: midday 52.9 / 180, the moon off")
D.round = 40
atick(2)
check(near(our.SunElevationAngleInDegrees, 52.9, 1e-6), "held for the rest of the run")
-- a new run with no GONE FISHIN': everything put back
RUN = {}
atick(2)
check(not ARC.on and same(state(), base), "the run has no F: everything the arc changed put back exactly")

print("the day-night arc: a late joiner, the custom sun, a restart")
RUN = { arcF = 3 }
D = { now = 3000, round = 10, state = "fighting", up = {} }
clock = 3000
atick(0)
local el0 = our.SunElevationAngleInDegrees
atick(2)
check(el0 > 14 and ARC.blendFrom ~= nil, string.format("joining at F+7: blending in from the stock sky (%.1f)", el0))
for _ = 1, 3 do atick(2) end
check(near(our.SunElevationAngleInDegrees, 35, 0.5), "5 s on: the night's sky")
SKY.arcReset("test: a restart")
check(not ARC.on and same(state(), base), "SKY.arcReset: put back now")
A.path = "custom"
RUN = { arcF = 8 }
D = { now = 4000, round = 9, state = "fighting", up = {} }
clock = 4000
custom.calls = {}
for _ = 1, 4 do atick(2) end
check(custom.calls[#custom.calls] and custom.calls[#custom.calls]:find("^pos 1[34]") and found("written through Cloudly's custom sun"),
    "path custom: Cloudly's custom sun API too (" .. tostring(custom.calls[#custom.calls]) .. ")")
SKY.arcReset("test")
A.path = "copies"
check(custom.sun == false and same(state(), base), "the custom sun off again with the rest")
-- the co-op host's F to a joiner: SKY.arcSet
RUN = {}
check(SKY.arcSet(12, "the host's") == true and RUN.arcF == 12 and SKY.arcSet(12, "again") == false, "SKY.arcSet: F kept in RUN once")
LEVEL_DROPS["the sky's arc"]("test")
check(not ARC.on and ARC.base == nil, "the level torn down: the arc forgotten untouched")

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
