-- sv_sky.lua: the sky Survival changes (CFG.sky; tools/re/FISHING.md 5): the day-night arc's owner (the arc comes later).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local.
--
-- The stock sky asset (the level's CloudlySkyParamsAsset, Mission 4's CSP_ms04...) is never written: Mission 4's campaign
-- would inherit what's left in it. Survival writes the renderer's working copies of its params (CloudlyRenderer .Data
-- .SkyRendererMainThread.OurSkyParams / .SkyParamsRO), the interpolated params only when they're a run-time object, the
-- sun light (its rotation: pitch -elevation, yaw azimuth + 90; intensity the sun's factor; colour), the level's sky light
-- (BP_SkyLightController's MainSkyLight), the post-process volumes' exposure, two material parameter collections
-- (CFG.sky.mpc_env / mpc_vfx, through KismetMaterialLibrary: the world's instance) and Cloudly's custom sun / moon (its
-- static API on /Script/Cloudly.Default__CloudlyActor). Each value's original is kept the first time it's touched and put
-- back exactly (SKY.restore: a run's end, sv_main.lua runLeft); the level's objects are found afresh for each apply or
-- restore (liveObj on each), never kept between ticks. The level torn down (sv_core.lua levelGate) drops the originals
-- untouched; a custom sun left on then is put back in the next level (SKY.pending, SKY.idleTick from sv_main.lua).
--
--   SKY.apply(v, why)    writes sky values v (each field optional), returns how many were written:
--       v.sun = { el =, az =, factor =, rgb = { r, g, b }, disc = }   elevation, azimuth (a compass bearing, east 90)
--       v.custom = true      the sun (and v.moon's spot) through the custom sun API too; false: the custom sun off
--       v.copies = false     not into the renderer's working copies (default: in)
--       v.light = false      not onto the sun light (default: rotation from el / az, intensity factor, colour rgb)
--       v.moon = { enable =, el =, az =, phase =, phase_angle =, disc =, brightness = }
--       v.stars = { enable =, intensity =, background =, radius =, fraction =, rotation = { x, y, z }, mask_start = }
--       v.exposure = { min =, max =, bias = }     every post-process volume whose override for it is on
--       v.skylight = { x =, rgb = { r, g, b } }    the sky light: x times its original intensity
--       v.mpc = { emissive =, vfx_ev =, vfx_amb = }
--   SKY.restore(why)     every value Survival changed put back: how many, how many read back as they were
--   SKY.read(V)          every value it can see: { keys = { key, ... }, val = { [key] = value }, ro = { [key] = true } }
--   SKY.view()           the level's sky objects, found afresh
-- VALKA's red sky (sv_hud.lua hudRed / RED) is hers: the sky test waits while it's on.
SKY = { orig = {}, order = {}, pending = nil, idleAt = 0, idleTries = 0 }
do
-- an FSkyParams field: the short name in a key -> its path in the struct
local SP = {
    { "sun_el", "SunElevationAngleInDegrees" }, { "sun_az", "SunAzimuthAngleInDegrees" },
    { "sun_factor", "SunIntensity.Factor" }, { "sun_r", "SunIntensity.RGB.X" }, { "sun_g", "SunIntensity.RGB.Y" },
    { "sun_b", "SunIntensity.RGB.Z" }, { "sun_disc", "SunDiskAngleInDegrees" }, { "unreal_sun", "bUseUnrealSunData" },
    { "moon_on", "EnableMoon" }, { "moon_el", "MoonElevationAngleInDegrees" }, { "moon_az", "MoonAzimuthAngleInDegrees" },
    { "moon_phase", "MoonPhase" }, { "moon_phase_angle", "MoonPhaseAngle" }, { "moon_disc", "MoonDiskAngleInDegrees" },
    { "moon_bright", "MoonDiskBrightness" }, { "moon_frac", "MoonFractionOfSunIntensity" },
    { "stars_on", "StarsParams.EnableStars" }, { "stars_int", "StarsParams.StarsIntensity" },
    { "stars_bg", "StarsParams.StarsBackgroundIntensity" }, { "stars_radius", "StarsParams.StarsRadius" },
    { "stars_frac", "StarsParams.StarsTextureScreenFraction" }, { "stars_rx", "StarsParams.StarsGlobalRotation.X" },
    { "stars_ry", "StarsParams.StarsGlobalRotation.Y" }, { "stars_rz", "StarsParams.StarsGlobalRotation.Z" },
    { "stars_mask", "StarsParams.StarsElevationMaskStart" },
}
local SP_PATH = {}
for _, f in ipairs(SP) do SP_PATH[f[1]] = f[2] end
SKY.SP = SP
local MPC_NAMES = { { "env", "Ctrl_Scene_EmissiveScale" }, { "vfx", "VFXEmissiveEV" }, { "vfx", "VFXCloudlySkyAmbientLight" } }

local function short(o) return (nameOf(o):match("([^%.:]+)$")) or "?" end
local function getPath(st, path)
    local o = st
    for part in path:gmatch("[^%.]+") do o = o[part] end
    return o
end
local function setPath(st, path, v)
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    local o = st
    for i = 1, #parts - 1 do o = o[parts[i]] end
    o[parts[#parts]] = v
end
local function live(o) return o ~= nil and liveObj(o) end
-- f's value, nil when it errs (a false stays false: never `ok and v or nil`)
local function pget(f)
    local ok, v = pcall(f)
    if ok then return v end
    return nil
end
-- a struct's array elements: fn(element, its 1-based place) for each, inside the array's walk (the element is the
-- engine's memory: never kept past the call); how many
local function eachElem(list, fn)
    local n = 0
    pcall(function() list:ForEach(function(_, e) n = n + 1; fn(e:get(), n) end) end)
    return n
end
local function rendArray(r, arr)
    local list
    pcall(function()
        local d = r.Data
        if arr == "Our" then list = d.SkyRendererMainThread.OurSkyParams else list = d.SkyParamsRO end
    end)
    return list
end

-- The level's sky objects, found afresh (each a live object; walks held by walkHold give nothing: V.held says why)
function SKY.view()
    local V = { rend = {}, ctrl = {}, ppv = {} }
    V.held = walkHold and walkHold() or nil
    if liveObj(survivalPC) then V.pc = survivalPC end
    local cdo = StaticFindObject("/Script/Cloudly.Default__CloudlyActor")
    if cdo ~= nil and live(cdo) then V.cdo = cdo end
    if V.cdo and V.pc then
        pcall(function() local a = V.cdo:GetCachedCloudlyActor(V.pc, true); if live(a) then V.actor, V.actorBy = a, "GetCachedCloudlyActor" end end)
    end
    if not V.actor then
        for _, cn in ipairs({ "LiveCloudlyActor", "CloudlyActor" }) do
            for _, o in ipairs(FindAllOf(cn) or {}) do
                if not V.actor and live(o) and not nameOf(o):find("Default__", 1, true) then V.actor, V.actorBy = o, "FindAllOf " .. cn end
            end
        end
    end
    if V.actor then
        local a = V.actor
        pcall(function() local x = a.SunLight; if live(x) then V.sun = x end end)
        pcall(function() local x = a.SkyLight; if live(x) then V.cskyl = x end end)
        pcall(function() local x = a.CloudlySkyParamsAsset; if live(x) then V.asset = x end end)
        pcall(function() local x = a.CloudlyInterpolatedSkyParamsAsset; if live(x) then V.interp = x end end)
        -- the interpolated params are written only when they're a run-time object, never the stock asset
        if V.interp and (not V.asset or addrOf(V.interp) ~= addrOf(V.asset)) and nameOf(V.interp):find("/Engine/Transient", 1, true) then
            V.interpOk = true
        end
    end
    for _, r in ipairs(FindAllOf("CloudlyRenderer") or {}) do
        if live(r) and not nameOf(r):find("Default__", 1, true) then V.rend[#V.rend + 1] = { obj = r, name = short(r) } end
    end
    for _, c in ipairs(FindAllOf("BP_SkyLightController_C") or {}) do
        local okL, l = pcall(function() return c.MainSkyLight end)
        if live(c) and okL and live(l) and not nameOf(c):find("Default__", 1, true) then V.ctrl[#V.ctrl + 1] = { obj = l, name = short(c) } end
    end
    for _, p in ipairs(FindAllOf("PostProcessVolume") or {}) do
        if live(p) and not nameOf(p):find("Default__", 1, true) then V.ppv[#V.ppv + 1] = { obj = p, name = short(p) } end
    end
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    if kml ~= nil and live(kml) then V.kml = kml end
    local c = CFG.sky or {}
    if type(c.mpc_env) == "string" then V.env = loadObject(c.mpc_env) end
    if type(c.mpc_vfx) == "string" then V.vfx = loadObject(c.mpc_vfx) end
    return V
end

-- A key's reader and writer on view V: get() -> value or nil, set(v) -> true (nil set: read only). Keys:
--   asset|<f>  interp|<f>  copy|<renderer>|Our|RO|<n>|<f>   the sky params (f: SP's short names)
--   light|pitch|yaw|roll|int|r|g|b   cskyl|int   skyl|<controller>|int|r|g|b   ppv|<volume>|min|max|bias
--   mpc|env|vfx|<parameter>   custom|sun|moon
local function slot(V, key)
    local p = {}
    for x in key:gmatch("[^|]+") do p[#p + 1] = x end
    local kind = p[1]
    if kind == "asset" or kind == "interp" then
        local o, path = kind == "asset" and V.asset or V.interp, SP_PATH[p[2]]
        if not (o and path) then return nil end
        local get = function() return pget(function() return getPath(o.Data, path) end) end
        local set = nil
        if kind == "interp" and V.interpOk then
            set = function(v) return pcall(function() setPath(o.Data, path, v) end) end
        end
        return get, set
    elseif kind == "copy" then
        local path, idx = SP_PATH[p[5]], tonumber(p[4])
        local r = nil
        for _, x in ipairs(V.rend) do if x.name == p[2] then r = x.obj end end
        if not (r and path and idx) then return nil end
        local function at(fn)
            local list = rendArray(r, p[3])
            if not list then return false end
            local done = false
            eachElem(list, function(st, n) if n == idx then done = pcall(fn, st) end end)
            return done
        end
        return function() local v; at(function(st) v = getPath(st, path) end); return v end,
               function(v) return at(function(st) setPath(st, path, v) end) end
    elseif kind == "light" then
        local l, f = V.sun, p[2]
        if not l then return nil end
        if f == "pitch" or f == "yaw" or f == "roll" then
            local F = ({ pitch = "Pitch", yaw = "Yaw", roll = "Roll" })[f]
            return function() return pget(function() return l:K2_GetComponentRotation()[F] end) end,
                   function(v)
                       return pcall(function()
                           local q = l:K2_GetComponentRotation()
                           local t = { Pitch = q.Pitch, Yaw = q.Yaw, Roll = q.Roll }
                           t[F] = v
                           l:K2_SetWorldRotation(t, false, {}, true)
                       end)
                   end
        elseif f == "int" then
            return function() return pget(function() return l.Intensity end) end,
                   function(v) return pcall(function() l:SetIntensity(v) end) end
        elseif f == "r" or f == "g" or f == "b" then
            local F = f:upper()
            -- (FColor bytes; written back with bSRGB false: byte / 255 truncates back to the same byte)
            return function() return pget(function() return l.LightColor[F] end) end,
                   function(v)
                       return pcall(function()
                           local q = l.LightColor
                           local t = { R = q.R, G = q.G, B = q.B }
                           t[F] = v
                           l:SetLightColor({ R = t.R / 255, G = t.G / 255, B = t.B / 255, A = 1 }, false)
                       end)
                   end
        end
    elseif kind == "cskyl" then
        local l = V.cskyl
        if not l then return nil end
        return function() return pget(function() return l.Intensity end) end, nil
    elseif kind == "skyl" then
        local l = nil
        for _, x in ipairs(V.ctrl) do if x.name == p[2] then l = x.obj end end
        local f = p[3]
        if not l then return nil end
        if f == "int" then
            return function() return pget(function() return l.Intensity end) end,
                   function(v) return pcall(function() l:SetIntensity(v) end) end
        end
        local F = f:upper()
        -- (USkyLightComponent::SetLightColor keeps it as sRGB bytes: the byte's own linear value goes in)
        local function lin(b) local c = b / 255; if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
        return function() return pget(function() return l.LightColor[F] end) end,
               function(v)
                   return pcall(function()
                       local q = l.LightColor
                       local t = { R = q.R, G = q.G, B = q.B }
                       t[F] = v
                       l:SetLightColor({ R = lin(t.R), G = lin(t.G), B = lin(t.B), A = 1 })
                   end)
               end
    elseif kind == "ppv" then
        local o = nil
        for _, x in ipairs(V.ppv) do if x.name == p[2] then o = x.obj end end
        local F = ({ min = "AutoExposureMinBrightness", max = "AutoExposureMaxBrightness", bias = "AutoExposureBias" })[p[3]]
        if not (o and F) then return nil end
        return function() return pget(function() return o.Settings[F] end) end,
               function(v) return pcall(function() o.Settings[F] = v end) end
    elseif kind == "mpc" then
        local coll = p[2] == "env" and V.env or V.vfx
        local name = p[3]
        if not (coll and V.kml and V.pc and name) then return nil end
        return function() return pget(function() return V.kml:GetScalarParameterValue(V.pc, coll, FName(name)) end) end,
               function(v) return pcall(function() V.kml:SetScalarParameterValue(V.pc, coll, FName(name), v) end) end
    elseif kind == "custom" then
        if not (V.cdo and V.pc) then return nil end
        local G, S = p[2] == "moon" and "GetUseCustomMoon" or "GetUseCustomSun", p[2] == "moon" and "SetUseCustomMoon" or "SetUseCustomSun"
        return function() return pget(function() return V.cdo[G](V.cdo, V.pc) end) end,
               function(v) return pcall(function() V.cdo[S](V.cdo, V.pc, v == true) end) end
    end
    return nil
end
SKY.slot = slot

-- every key view V can show, in a fixed order
local function keysOf(V)
    local out = {}
    local function sp(prefix) for _, f in ipairs(SP) do out[#out + 1] = prefix .. f[1] end end
    if V.asset then sp("asset|") end
    if V.interp then sp("interp|") end
    for _, r in ipairs(V.rend) do
        for _, arr in ipairs({ "Our", "RO" }) do
            local list = rendArray(r.obj, arr)
            local n = list and eachElem(list, function() end) or 0
            for i = 1, n do sp(string.format("copy|%s|%s|%d|", r.name, arr, i)) end
        end
    end
    if V.sun then for _, f in ipairs({ "pitch", "yaw", "roll", "int", "r", "g", "b" }) do out[#out + 1] = "light|" .. f end end
    if V.cskyl then out[#out + 1] = "cskyl|int" end
    for _, c in ipairs(V.ctrl) do for _, f in ipairs({ "int", "r", "g", "b" }) do out[#out + 1] = "skyl|" .. c.name .. "|" .. f end end
    for _, v in ipairs(V.ppv) do for _, f in ipairs({ "min", "max", "bias" }) do out[#out + 1] = "ppv|" .. v.name .. "|" .. f end end
    for _, m in ipairs(MPC_NAMES) do out[#out + 1] = "mpc|" .. m[1] .. "|" .. m[2] end
    out[#out + 1], out[#out + 2] = "custom|sun", "custom|moon"
    return out
end
SKY.keysOf = keysOf

function SKY.read(V)
    V = V or SKY.view()
    local snap = { keys = {}, val = {}, ro = {} }
    for _, k in ipairs(keysOf(V)) do
        local get, set = slot(V, k)
        if get then
            local v = get()
            if v ~= nil then
                snap.keys[#snap.keys + 1] = k
                snap.val[k] = v
                if not set then snap.ro[k] = true end
            end
        end
    end
    return snap
end

local function fmt(v)
    if type(v) == "number" then return string.format("%.5g", v) end
    return tostring(v)
end
SKY.fmt = fmt
-- whether two values are the same (numbers within a little: floats, and a colour byte's rounding)
function SKY.same(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) <= math.max(1e-3, math.abs(a) * 1e-4) end
    return a == b
end
-- a list of "key value" (or "key a -> b") lines grouped by the key's object (all but its last field): one log line each
function SKY.logGroups(head, keys, text)
    local groups, order = {}, {}
    for _, k in ipairs(keys) do
        local g, f = k:match("^(.*)|([^|]+)$")
        g, f = g or k, f or ""
        if not groups[g] then groups[g] = {}; order[#order + 1] = g end
        groups[g][#groups[g] + 1] = f .. " " .. text(k)
    end
    for _, g in ipairs(order) do log(string.format("%s %s: %s", head, g, table.concat(groups[g], ", "))) end
    return #order
end

-- the values v asks for, as { key = value } on view V (originals: an intensity x is of the original kept)
local function wanted(V, v)
    local want, f = {}, {}
    local s, m, st = v.sun or {}, v.moon or {}, v.stars or {}
    f.sun_el, f.sun_az, f.sun_factor, f.sun_disc = s.el, s.az, s.factor, s.disc
    if type(s.rgb) == "table" then f.sun_r, f.sun_g, f.sun_b = s.rgb[1], s.rgb[2], s.rgb[3] end
    f.moon_on, f.moon_el, f.moon_az, f.moon_phase, f.moon_phase_angle = m.enable, m.el, m.az, m.phase, m.phase_angle
    f.moon_disc, f.moon_bright = m.disc, m.brightness
    f.stars_on, f.stars_int, f.stars_bg, f.stars_radius, f.stars_frac = st.enable, st.intensity, st.background, st.radius, st.fraction
    if type(st.rotation) == "table" then f.stars_rx, f.stars_ry, f.stars_rz = st.rotation[1], st.rotation[2], st.rotation[3] end
    f.stars_mask = st.mask_start
    if v.copies ~= false then
        for _, k in ipairs(keysOf(V)) do
            local kind, field = k:match("^(%a+)|"), k:match("|([%w_]+)$")
            if (kind == "copy" or (kind == "interp" and V.interpOk)) and f[field] ~= nil then want[k] = f[field] end
        end
    end
    if v.light ~= false and V.sun then
        if s.el then want["light|pitch"] = -s.el end
        if s.az then local y = (s.az + 90) % 360; if y > 180 then y = y - 360 end; want["light|yaw"] = y end
        if s.factor then want["light|int"] = s.factor end
        if type(s.rgb) == "table" then
            for i, F in ipairs({ "r", "g", "b" }) do want["light|" .. F] = math.max(0, math.min(255, math.floor((s.rgb[i] or 1) * 255 + 0.5))) end
        end
    end
    local sl = v.skylight
    if type(sl) == "table" then
        for _, c in ipairs(V.ctrl) do
            local k = "skyl|" .. c.name .. "|int"
            if sl.x then
                local base = SKY.orig[k]
                if base == nil then local get = slot(V, k); base = get and get() end
                if type(base) == "number" then want[k] = base * sl.x end
            end
            if type(sl.rgb) == "table" then
                for i, F in ipairs({ "r", "g", "b" }) do
                    want["skyl|" .. c.name .. "|" .. F] = math.max(0, math.min(255, math.floor((sl.rgb[i] or 1) * 255 + 0.5)))
                end
            end
        end
    end
    local ex = v.exposure
    if type(ex) == "table" then
        for _, p in ipairs(V.ppv) do
            for _, e in ipairs({ { "min", "AutoExposureMinBrightness" }, { "max", "AutoExposureMaxBrightness" }, { "bias", "AutoExposureBias" } }) do
                local on = false
                pcall(function() on = p.obj.Settings["bOverride_" .. e[2]] == true end)
                if on and ex[e[1]] ~= nil then want["ppv|" .. p.name .. "|" .. e[1]] = ex[e[1]] end
            end
        end
    end
    local mp = v.mpc
    if type(mp) == "table" then
        if mp.emissive ~= nil then want["mpc|env|Ctrl_Scene_EmissiveScale"] = mp.emissive end
        if mp.vfx_ev ~= nil then want["mpc|vfx|VFXEmissiveEV"] = mp.vfx_ev end
        if mp.vfx_amb ~= nil then want["mpc|vfx|VFXCloudlySkyAmbientLight"] = mp.vfx_amb end
    end
    return want
end
SKY.wanted = wanted

-- one value written on view V, its original kept the first time; the value it had and whether the write went
local function writeKey(V, k, value)
    local get, set = slot(V, k)
    if not (get and set) then return nil, false end
    local old = get()
    if SKY.orig[k] == nil and old ~= nil then SKY.orig[k] = old; SKY.order[#SKY.order + 1] = k end
    local ok = set(value) == true
    return old, ok
end
SKY.writeKey = writeKey

function SKY.apply(v, why)
    why = tostring(why or "?")
    if type(v) ~= "table" then return 0 end
    if levelTorn and levelTorn() then log("sky: " .. why .. ": the level is going: nothing written"); return 0 end
    local V = SKY.view()
    if not V.actor then log("sky: " .. why .. ": no sky actor found" .. (V.held and (" (walks held: " .. V.held .. ")") or "") .. ": nothing written"); return 0 end
    local want = wanted(V, v)
    local keys = {}
    for k in pairs(want) do keys[#keys + 1] = k end
    table.sort(keys)
    local done, failed, text = 0, {}, {}
    for _, k in ipairs(keys) do
        local old, ok = writeKey(V, k, want[k])
        if ok then done = done + 1; text[k] = fmt(old) .. " -> " .. fmt(want[k])
        else failed[#failed + 1] = k end
    end
    local written = {}
    for _, k in ipairs(keys) do if text[k] then written[#written + 1] = k end end
    SKY.logGroups("sky: " .. why .. ": wrote", written, function(k) return text[k] end)
    -- the custom sun / moon (the API's own state: its use flags are kept as the originals)
    local s, m = v.sun or {}, v.moon or {}
    if v.custom == true and s.el and s.az and V.cdo and V.pc then
        writeKey(V, "custom|sun", true)                      -- (the original kept; the position call sets it anyway)
        local okC, errC = pcall(function() V.cdo:SetCustomSunPosition(V.pc, s.el, s.az, true) end)
        log(string.format("sky: %s: SetCustomSunPosition(%s, %s, true): %s", why, fmt(s.el), fmt(s.az), okC and "called" or ("failed: " .. tostring(errC))))
        if okC then done = done + 1 end
        if m.el and m.az then
            writeKey(V, "custom|moon", true)
            local okM, errM = pcall(function() V.cdo:SetCustomMoonPosition(V.pc, m.el, m.az, true) end)
            log(string.format("sky: %s: SetCustomMoonPosition(%s, %s, true): %s", why, fmt(m.el), fmt(m.az), okM and "called" or ("failed: " .. tostring(errM))))
        end
    elseif v.custom == false and V.cdo and V.pc then
        local old, ok = writeKey(V, "custom|sun", false)
        log(string.format("sky: %s: the custom sun off (it was %s): %s", why, fmt(old), ok and "done" or "FAILED"))
        local oldM, okM = writeKey(V, "custom|moon", false)
        log(string.format("sky: %s: the custom moon off (it was %s): %s", why, fmt(oldM), okM and "done" or "FAILED"))
    elseif v.custom ~= nil then
        log(string.format("sky: %s: the custom sun NOT set: %s", why, not V.cdo and "no Default__CloudlyActor" or "no player controller"))
    end
    if (s.el or s.az) and V.cdo then
        local okU = pcall(function() V.cdo:ForceUpdateShadows(8) end)
        log("sky: " .. why .. ": ForceUpdateShadows(8) " .. (okU and "called" or "failed"))
    end
    log(string.format("sky: %s: %d values written%s (sky actor %s by %s; %d renderer(s), %d sky light(s), %d post-process volume(s)%s)",
        why, done, #failed > 0 and string.format(", %d NOT: %s", #failed, table.concat(failed, ", ")) or "", short(V.actor),
        tostring(V.actorBy), #V.rend, #V.ctrl, #V.ppv, V.held and (", walks held: " .. V.held) or ""))
    return done
end

-- the originals' custom flags, for a level torn down with them changed: put back in the next one (SKY.idleTick)
local function pendingFrom()
    local p = nil
    for _, k in ipairs({ "custom|sun", "custom|moon" }) do
        if SKY.orig[k] ~= nil then p = p or {}; p[k] = SKY.orig[k] end
    end
    return p
end

function SKY.restore(why)
    why = tostring(why or "?")
    if #SKY.order == 0 then return 0, 0 end
    if levelTorn and levelTorn() then
        SKY.pending = pendingFrom()
        log(string.format("sky: %s: the level's torn down: its %d changed values go with it, none put back%s", why, #SKY.order,
            SKY.pending and " (the custom sun's put back in the next level)" or ""))
        SKY.orig, SKY.order = {}, {}
        return 0, 0
    end
    local V = SKY.view()
    local put, same, lost, keys, text = 0, 0, {}, {}, {}
    -- the custom sun first (it moves the copies and the light), then each value in the order it was first changed
    local order = {}
    for _, k in ipairs(SKY.order) do if k:find("^custom|") then order[#order + 1] = k end end
    for _, k in ipairs(SKY.order) do if not k:find("^custom|") then order[#order + 1] = k end end
    for _, k in ipairs(order) do
        local get, set = slot(V, k)
        local o = SKY.orig[k]
        if get and set and set(o) == true then
            put = put + 1
            local now = get()
            if SKY.same(now, o) then same = same + 1 end
            keys[#keys + 1] = k
            text[k] = fmt(o) .. (SKY.same(now, o) and "" or (" (reads " .. fmt(now) .. ")"))
        else
            lost[#lost + 1] = k
        end
    end
    SKY.logGroups("sky: " .. why .. ": put back", keys, function(k) return text[k] end)
    local pend = nil
    for _, k in ipairs(lost) do if k:find("^custom|") then pend = pend or {}; pend[k] = SKY.orig[k] end end
    SKY.pending = pend
    log(string.format("sky: %s: put back %d of %d changed values, %d read back as they were%s%s", why, put, #order, same,
        #lost > 0 and string.format("; %d NOT (their objects not found%s): %s", #lost, V.held and (", walks held: " .. V.held) or "",
            table.concat(lost, ", ")) or "", pend and "; the custom sun put back in the next level" or ""))
    SKY.orig, SKY.order = {}, {}
    return put, same
end

-- (sv_main.lua probeTick, while SKY.pending) a custom sun or moon a torn-down level left changed: put back as it was in
-- the next level that has a player controller (every 5 s, 12 tries)
function SKY.idleTick()
    local P = SKY.pending
    if not P then return end
    local now = os.clock()
    if now < (SKY.idleAt or 0) or (levelTorn and levelTorn()) or (walkHold and walkHold()) then return end
    SKY.idleAt = now + 5
    SKY.idleTries = (SKY.idleTries or 0) + 1
    local pc = liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController")
    local cdo = StaticFindObject("/Script/Cloudly.Default__CloudlyActor")
    local done = {}
    if pc ~= nil and liveObj(pc) and cdo ~= nil and liveObj(cdo) then
        if P["custom|sun"] ~= nil and pcall(function() cdo:SetUseCustomSun(pc, P["custom|sun"] == true) end) then done[#done + 1] = "sun " .. fmt(P["custom|sun"]) end
        if P["custom|moon"] ~= nil and pcall(function() cdo:SetUseCustomMoon(pc, P["custom|moon"] == true) end) then done[#done + 1] = "moon " .. fmt(P["custom|moon"]) end
    end
    if #done > 0 or SKY.idleTries >= 12 then
        log(string.format("sky: the custom sun a torn-down level left changed: %s", #done > 0 and ("put back (" .. table.concat(done, ", ") .. ")")
            or "NOT put back (no player controller or Cloudly in 12 tries)"))
        SKY.pending, SKY.idleTries = nil, 0
    end
end

-- (the teardown gate's drop, sv_core.lua levelDrop: the originals are the level's, forgotten untouched)
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the sky"] = function()
        if #SKY.order > 0 then SKY.pending = pendingFrom() end
        SKY.orig, SKY.order = {}, {}
    end
end
end

-- TEST ONLY BEGIN
-- Ctrl+F6 in a run: the sky test (tools/re/FISHING.md 5), one step a press, each logging every value it writes and a
-- read-back CFG.sky.readback_s later (`sky test: ...`, and SKY.apply's `sky: sky test step N: wrote ...`):
--   1 read only: every value Survival can see (the sky actor, the stock asset's params, the renderer's copies, the light,
--     the sky lights, the volumes' exposure and their overrides, the MPCs, the custom sun), again 5 s on (what moves alone)
--   2 the custom sun at test_sun (SetCustomSunPosition(-2, -105, true)): do the copies and the light follow?
--   3 the custom sun off, the sun at test_copies through the copies and the light's rotation alone: kept or overwritten?
--   4 the night set (CFG.sky.night, stars): which values hold, which the game puts back (the MPCs)
--   5 everything put back: `sky test: put back: N of N values match the originals` (against step 1's read)
-- Not while VALKA's red sky is on, nor before the last step's read-back.
do
local T = { step = 0, readAt = nil, base = nil, wrote = nil }
SKY.test = T
local function c() return CFG.sky or {} end
local function startRead(now, what) T.readAt, T.readWhat = now + (tonumber(c().readback_s) or 5), what end
local function compare(snap, keysToCheck, against)
    local same, diff = 0, {}
    for _, k in ipairs(keysToCheck) do
        local v = snap.val[k]
        if v ~= nil and SKY.same(v, against[k]) then same = same + 1
        else diff[#diff + 1] = k .. " " .. SKY.fmt(against[k]) .. " -> " .. SKY.fmt(v) end
    end
    return same, diff
end
local function sunKeys(snap)
    local out = {}
    for _, k in ipairs(snap.keys) do
        if k:find("|sun_el$") or k:find("|sun_az$") or k:find("^light|") or k:find("^custom|") then out[#out + 1] = k end
    end
    return out
end
local function logSnap(head, snap, keys)
    SKY.logGroups(head, keys or snap.keys, function(k) return SKY.fmt(snap.val[k]) .. (snap.ro[k] and " (read only)" or "") end)
end
local function step1(now)
    local V = SKY.view()
    log(string.format("sky test: step 1 (read only): sky actor %s (%s), its asset %s, interpolated params %s%s; sun light %s, "
        .. "Cloudly's sky light %s; %d renderer(s), %d sky light controller(s), %d post-process volume(s); MPCs %s / %s; "
        .. "Default__CloudlyActor %s, player controller %s%s",
        V.actor and nameOf(V.actor) or "NOT found", tostring(V.actorBy), V.asset and nameOf(V.asset) or "none",
        V.interp and nameOf(V.interp) or "none", V.interp and (V.interpOk and " (a run-time object: written)" or " (NOT written)") or "",
        V.sun and nameOf(V.sun) or "none", V.cskyl and nameOf(V.cskyl) or "none", #V.rend, #V.ctrl, #V.ppv,
        V.env and "found" or "NOT found", V.vfx and "found" or "NOT found", V.cdo and "found" or "NOT found", V.pc and "found" or "NOT found",
        V.held and (" (walks held: " .. V.held .. ")") or ""))
    if V.actor then
        local flags = {}
        for _, f in ipairs({ "bUseSunLight", "bUseSkyLight", "bUseHeightFog", "bUseCloudlyEnvMap", "EnableCloudlySequencer",
                             "bUseSkyLightPositioningInGame", "CloudlySequencerTime" }) do
            local okF, x = pcall(function() return V.actor[f] end)
            flags[#flags + 1] = f .. " " .. (okF and SKY.fmt(x) or "?")
        end
        log("sky test: step 1: the sky actor's " .. table.concat(flags, ", "))
    end
    for _, p in ipairs(V.ppv) do
        local fl = {}
        for _, f in ipairs({ "AutoExposureMinBrightness", "AutoExposureMaxBrightness", "AutoExposureBias" }) do
            local okF, x = pcall(function() return p.obj.Settings["bOverride_" .. f] end)
            fl[#fl + 1] = f .. " override " .. (okF and SKY.fmt(x) or "?")
        end
        local okU, unb = pcall(function() return p.obj.bUnbound end)
        log(string.format("sky test: step 1: volume %s: %s; unbound %s", p.name, table.concat(fl, ", "), okU and SKY.fmt(unb) or "?"))
    end
    for _, r in ipairs(V.rend) do
        local okA, lens = pcall(function()
            local d = r.obj.Data
            local a, b = 0, 0
            d.SkyRendererMainThread.OurSkyParams:ForEach(function() a = a + 1 end)
            d.SkyParamsRO:ForEach(function() b = b + 1 end)
            return a .. " in OurSkyParams, " .. b .. " in SkyParamsRO"
        end)
        log(string.format("sky test: step 1: renderer %s: %s", r.name, okA and lens or ("NOT readable: " .. tostring(lens))))
    end
    local snap = SKY.read(V)
    T.base = snap
    logSnap("sky test: step 1:", snap)
    log(string.format("sky test: step 1: %d values read (%d read only)", #snap.keys, (function() local n = 0; for _ in pairs(snap.ro) do n = n + 1 end; return n end)()))
    T.wrote = nil
    startRead(now, 1)
    hudCallout("TEST: SKY 1 READ", string.format("%d VALUES", #snap.keys))
end
local function step2(now)
    local s = c().test_sun or { -2, -105 }
    local n = SKY.apply({ sun = { el = s[1], az = s[2] }, custom = true, copies = false, light = false }, "sky test step 2")
    local at = SKY.read()
    logSnap("sky test: step 2: at once:", at, sunKeys(at))
    T.wrote = nil
    T.expect = { el = s[1], az = s[2] }
    startRead(now, 2)
    hudCallout("TEST: SKY 2 CUSTOM SUN", string.format("%s / %s (%d)", SKY.fmt(s[1]), SKY.fmt(s[2]), n))
end
local function wroteNow(v)
    local V = SKY.view()
    local w = SKY.wanted(V, v)
    return w
end
-- right after a step's writes: which read back as written at once (a write that didn't take, not one the game undid later)
local function atOnce(step)
    local keys = {}
    for k in pairs(T.wrote or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local same, diff = compare(SKY.read(), keys, T.wrote or {})
    log(string.format("sky test: step %d at once: %d of %d values read back as written%s", step, same, #keys,
        #diff > 0 and ("; not (written -> reads): " .. table.concat(diff, ", ")) or ""))
end
local function step3(now)
    local s = c().test_copies or { 4, -120 }
    local v = { sun = { el = s[1], az = s[2] }, custom = false, copies = true, light = true }
    T.wrote = wroteNow(v)
    local n = SKY.apply(v, "sky test step 3")
    atOnce(3)
    startRead(now, 3)
    hudCallout("TEST: SKY 3 COPIES + LIGHT", string.format("%s / %s (%d)", SKY.fmt(s[1]), SKY.fmt(s[2]), n))
end
local function step4(now)
    local ng, st = c().night or {}, c().stars or {}
    local ex = ng.exposure or {}
    local v = { sun = { el = ng.sun_el, az = ng.sun_az, factor = ng.factor, rgb = ng.rgb, disc = ng.sun_disc },
                custom = true, copies = true, light = true,
                moon = { enable = true, el = ng.moon_el, az = ng.moon_az },
                stars = { enable = true, intensity = st.intensity, background = st.background, radius = st.radius,
                          fraction = st.fraction, rotation = st.rotation, mask_start = st.mask_start },
                exposure = { min = ex[1], max = ex[2], bias = ex[3] },
                skylight = { x = ng.skylight_x, rgb = ng.skylight_rgb },
                mpc = { emissive = ng.emissive, vfx_ev = ng.vfx_ev } }
    T.wrote = wroteNow(v)
    local n = SKY.apply(v, "sky test step 4")
    atOnce(4)
    startRead(now, 4)
    hudCallout("TEST: SKY 4 NIGHT", string.format("%d VALUES", n))
end
local function step5(now)
    T.restored = {}
    for k, v in pairs(SKY.orig) do T.restored[k] = v end
    local put, same = SKY.restore("sky test step 5")
    -- values the game itself changed since step 1's read (the custom sun moves the copies and the light): put back too
    local extra, extraKeys = 0, {}
    if T.base then
        local V = SKY.view()
        for _, k in ipairs(T.base.keys) do
            if not T.base.ro[k] then
                local get, set = SKY.slot(V, k)
                local v = get and get()
                if get and set and v ~= nil and not SKY.same(v, T.base.val[k]) and set(T.base.val[k]) == true then
                    extra = extra + 1
                    extraKeys[#extraKeys + 1] = k .. " " .. SKY.fmt(v) .. " -> " .. SKY.fmt(T.base.val[k])
                end
            end
        end
    end
    log(string.format("sky test: step 5: %d changed values put back (%d read back as they were)%s", put, same,
        extra > 0 and string.format("; %d more the game had changed since step 1 put back too: %s", extra, table.concat(extraKeys, ", "))
            or (T.base and "; nothing else differed from step 1's read" or "; no step 1 read this time (pressed after a reload?)")))
    T.wrote = nil
    startRead(now, 5)
    hudCallout("TEST: SKY 5 PUT BACK", string.format("%d + %d VALUES", put, extra))
end
local function readBack()
    local w, snap = T.readWhat, SKY.read()
    local secs = tonumber(c().readback_s) or 5
    if w == 1 then
        local keys = {}
        for _, k in ipairs(T.base and T.base.keys or {}) do keys[#keys + 1] = k end
        local same, diff = compare(snap, keys, T.base and T.base.val or {})
        log(string.format("sky test: step 1 read again %d s on: %d of %d unchanged%s", secs, same, #keys,
            #diff > 0 and ("; moved by themselves: " .. table.concat(diff, ", ")) or ""))
    elseif w == 2 then
        local keys = sunKeys(snap)
        logSnap(string.format("sky test: step 2: %d s on:", secs), snap, keys)
        local e, cf, inf = T.expect or {}, {}, {}
        for _, k in ipairs(keys) do
            local want = k:find("sun_el$") and e.el or e.az
            if k:find("^copy|") then cf[#cf + 1] = SKY.same(snap.val[k], want)
            elseif k:find("^interp|") then inf[#inf + 1] = SKY.same(snap.val[k], want) end
        end
        local yaw = e.az and ((e.az + 90) % 360) or nil
        if yaw and yaw > 180 then yaw = yaw - 360 end
        local lp, ly = snap.val["light|pitch"], snap.val["light|yaw"]
        local function all(t) if #t == 0 then return "nothing to read" end for _, x in ipairs(t) do if not x then return "NO" end end return "yes" end
        log(string.format("sky test: step 2: the renderer's copies follow the custom sun (%s / %s): %s; the interpolated params: %s; "
            .. "the light (pitch %s, yaw %s): %s; custom sun %s", SKY.fmt(e.el), SKY.fmt(e.az), all(cf), all(inf), SKY.fmt(lp), SKY.fmt(ly),
            (lp and ly and e.el) and ((SKY.same(lp, -e.el) and SKY.same(ly, yaw)) and "follows" or "does NOT follow") or "not read",
            SKY.fmt(snap.val["custom|sun"])))
    elseif w == 3 or w == 4 then
        local keys = {}
        for k in pairs(T.wrote or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        local same, diff = compare(snap, keys, T.wrote or {})
        local mpcBack = {}
        for _, d in ipairs(diff) do if d:find("^mpc|") then mpcBack[#mpcBack + 1] = d end end
        log(string.format("sky test: step %d read back %d s on: %d of %d values kept%s%s", w, secs, same, #keys,
            #diff > 0 and ("; overwritten (written -> now): " .. table.concat(diff, ", ")) or "",
            w == 4 and ("; the MPC values the game put back: " .. (#mpcBack > 0 and table.concat(mpcBack, ", ") or "none")) or ""))
        if w == 4 then logSnap(string.format("sky test: step 4: %d s on:", secs), snap, sunKeys(snap)) end
    elseif w == 5 then
        local against, keys = {}, {}
        if T.base then
            for _, k in ipairs(T.base.keys) do keys[#keys + 1] = k; against[k] = T.base.val[k] end
        else                                     -- (no step 1 read this time: the values Survival changed)
            for k, v in pairs(T.restored or {}) do keys[#keys + 1] = k; against[k] = v end
            table.sort(keys)
        end
        local same, diff = compare(snap, keys, against)
        log(string.format("sky test: put back: %d of %d values match the originals%s", same, #keys,
            #diff > 0 and ("; differ (original -> now): " .. table.concat(diff, ", ")) or ""))
        hudCallout("TEST: SKY PUT BACK", string.format("%d OF %d MATCH", same, #keys))
        T.base = nil
    end
end
testKey("F6", "sv_sky.lua's sky test", function()
    local now = os.clock()
    if not (D and D.now) then log("sky test: Ctrl+F6 outside a Survival run"); return end
    if levelTorn and levelTorn() then return end
    if T.readAt then
        log(string.format("sky test: step %d's read-back is due in %.1f s: press again after it", T.step, T.readAt - now))
        hudCallout("TEST: SKY " .. T.step .. " READING BACK", "WAIT")
        return
    end
    local nextStep = T.step % 5 + 1
    if nextStep > 1 and nextStep < 5 and RED and (RED.want or (tonumber(RED.k) or 0) > 0) then
        log("sky test: VALKA's red sky is on: step " .. nextStep .. " waits until it's gone (her sky puts its own values back)")
        hudCallout("TEST: SKY WAITS", "VALKA'S RED SKY IS ON")
        return
    end
    T.step = nextStep
    log(string.format("sky test: Ctrl+F6, step %d of 5", T.step))
    local steps = { step1, step2, step3, step4, step5 }
    steps[T.step](now)
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "sky test", fn = function(now)
    if not T.readAt or now < T.readAt then return end
    T.readAt = nil
    if levelTorn and levelTorn() then return end
    readBack()
end }
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the sky test"] = function() T.step, T.readAt, T.base, T.wrote = 0, nil, nil, nil end
end
end
-- TEST ONLY END
