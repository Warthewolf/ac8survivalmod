-- sv_sky.lua: the sky Survival changes (CFG.sky; tools/re/FISHING.md 5): the day-night arc's owner (CFG.sky.arc, below).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local.
--
-- ((2026-11-07) the user's sky test, in a run where the arc's sun "isn't moving at all" and its night "looks over exposed")
-- Cloudly draws the sky, and drives its sun light, from the level's CloudlySkyParamsAsset (Mission 4's CSP_ms04...): every
-- frame it copies that asset into the renderer's drawn copy (CloudlyRenderer .Data.SkyParamsRO and two of OurSkyParams)
-- and onto the sun light (rotation, intensity, colour), so a write to those is undone at once; its custom sun API writes
-- into the asset itself. The day-night arc writes the asset (v.asset). The asset outlives the level and Mission 4's
-- campaign reads it too, so every value of it is put back exactly: at a run's end (SKY.restore, sv_main.lua runLeft), after
-- a level torn down with it changed in the next tick that can (SKY.pending, SKY.idleTick: the asset found again by its
-- path), and one an earlier run left changed is put back to its shipped values (CFG.sky.arc.stock.asset, SKY.assetShipped).
-- Survival also writes the renderer's working copies (OurSkyParams / SkyParamsRO: the sky test's; undone by the next frame),
-- the interpolated params only when they're a run-time object, the sun light (its rotation: pitch -elevation, yaw azimuth
-- + 90; intensity the sun's factor; colour), the level's sky light (BP_SkyLightController's MainSkyLight), the
-- post-process volumes' exposure, two material parameter collections (CFG.sky.mpc_env / mpc_vfx, through
-- KismetMaterialLibrary: the world's instance) and Cloudly's custom sun / moon (its static API on
-- /Script/Cloudly.Default__CloudlyActor). Each value's original is kept the first time it's touched and put back exactly;
-- the level's objects are checked live (liveObj) before each use. The level torn down (sv_core.lua levelGate) drops the
-- level's originals untouched; a custom sun left on, and the sky asset's, are put back in the next tick that can.
--
--   SKY.apply(v, why, opts)  writes sky values v (each field optional), returns how many were written (opts.V: a view
--                        to write on, else found afresh; opts.quiet: no line a value, only what failed and why):
--       v.sun = { el =, az =, factor =, rgb = { r, g, b }, disc = }   elevation, azimuth (a compass bearing, east 90)
--       v.custom = true      the sun (and v.moon's spot) through the custom sun API too; false: the custom sun off
--       v.asset = true       into the level's sky asset itself (what Cloudly draws and lights by: the arc's path)
--       v.copies = false     not into the renderer's working copies (default: in)
--       v.light = false      not onto the sun light (default: rotation from el / az, intensity factor, colour rgb)
--       v.moon = { enable =, el =, az =, phase =, phase_angle =, disc =, brightness = }
--       v.stars = { enable =, intensity =, background =, radius =, fraction =, rotation = { x, y, z }, mask_start = }
--       v.exposure = { min =, max =, bias = }     every post-process volume whose override for it is on
--       v.skylight = { x =, rgb = { r, g, b } }    the sky light: x times its original intensity
--       v.mpc = { emissive =, vfx_ev =, vfx_amb = }
--   SKY.restore(why)     every value Survival changed put back: how many, how many read back as they were; one that
--                        couldn't be put back is kept and tried again (SKY.retryTick) until it is or the level goes
--   SKY.read(V)          every value it can see: { keys = { key, ... }, val = { [key] = value }, ro = { [key] = true } }
--   SKY.view()           the level's sky objects, found afresh; SKY.viewCached(now [, s]) the last one while each of its
--                        objects is live (liveObj) (and it's under s old, when s is given); one with no sky actor looked
--                        for again at most every 10 s
-- VALKA's red sky (sv_hud.lua hudRed / RED) is hers: the sky test waits while it's on, the arc leaves the colours to it.
-- The day-night arc (SKY.arc*, below) GONE FISHIN' starts: its round F kept in RUN.arcF on every game.
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
        -- (the asset: written only when an apply asks for it (v.asset), its originals always put back; the interpolated
        -- params only when they're a run-time object, never the stock asset)
        if kind == "asset" or V.interpOk then
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
    if v.asset == true and V.asset then
        for _, fd in ipairs(SP) do if f[fd[1]] ~= nil then want["asset|" .. fd[1]] = f[fd[1]] end end
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

-- an object's path for StaticFindObject (its full name without the class: "CloudlySkyParams /Game/..." -> "/Game/...")
local function objPath(o)
    local s = nameOf(o)
    return s:match("^[^/%s]+%s+(/.+)$") or s
end
-- the sky asset's path noted with its first original (put back by it after a level's torn down: SKY.idleTick)
local function noteAsset(V, k)
    if V.asset and k:find("^asset|") and not SKY.assetPath then SKY.assetPath = objPath(V.asset) end
end
SKY.noteAsset = noteAsset
-- one value written on view V, its original kept the first time; the value it had and whether the write went
local function writeKey(V, k, value)
    local get, set = slot(V, k)
    if not (get and set) then return nil, false end
    local old = get()
    if SKY.orig[k] == nil and old ~= nil then SKY.orig[k] = old; SKY.order[#SKY.order + 1] = k; noteAsset(V, k) end
    local ok = set(value) == true
    return old, ok
end
SKY.writeKey = writeKey
-- a value's original kept without writing it: one the game changes for us (the custom sun API writes the asset)
local function keepOrig(V, k)
    if SKY.orig[k] ~= nil then return end
    local get = slot(V, k)
    local v = get and get()
    if v ~= nil then SKY.orig[k] = v; SKY.order[#SKY.order + 1] = k; noteAsset(V, k) end
end
SKY.keepOrig = keepOrig

function SKY.apply(v, why, opts)
    why = tostring(why or "?")
    opts = opts or {}
    if type(v) ~= "table" then return 0 end
    if levelTorn and levelTorn() then log("sky: " .. why .. ": the level is going: nothing written"); return 0 end
    local V = opts.V or SKY.view()
    if not V.actor then
        if not opts.quiet then log("sky: " .. why .. ": no sky actor found" .. (V.held and (" (walks held: " .. V.held .. ")") or "") .. ": nothing written") end
        return 0
    end
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
    if not opts.quiet then SKY.logGroups("sky: " .. why .. ": wrote", written, function(k) return text[k] end) end
    -- the custom sun / moon (the API's own state: its use flags are kept as the originals)
    local s, m = v.sun or {}, v.moon or {}
    if v.custom == true and s.el and s.az and V.cdo and V.pc then
        writeKey(V, "custom|sun", true)                      -- (the original kept; the position call sets it anyway)
        -- (the API writes the sky asset's sun and moon (the sky test of 2026-11-07: the asset read -2 / -105 after it; the
        -- moon's call left it on, at 35 / -130, phase 0.15 -> 0): their originals kept, so they're put back with the rest)
        for _, f in ipairs({ "sun_el", "sun_az" }) do keepOrig(V, "asset|" .. f) end
        if m.el and m.az then for _, f in ipairs({ "moon_on", "moon_el", "moon_az", "moon_phase" }) do keepOrig(V, "asset|" .. f) end end
        local okC, errC = pcall(function() V.cdo:SetCustomSunPosition(V.pc, s.el, s.az, true) end)
        if not (opts.quiet and okC) then
            log(string.format("sky: %s: SetCustomSunPosition(%s, %s, true): %s", why, fmt(s.el), fmt(s.az), okC and "called" or ("failed: " .. tostring(errC))))
        end
        if okC then done = done + 1 end
        if m.el and m.az then
            writeKey(V, "custom|moon", true)
            local okM, errM = pcall(function() V.cdo:SetCustomMoonPosition(V.pc, m.el, m.az, true) end)
            if not (opts.quiet and okM) then
                log(string.format("sky: %s: SetCustomMoonPosition(%s, %s, true): %s", why, fmt(m.el), fmt(m.az), okM and "called" or ("failed: " .. tostring(errM))))
            end
        end
    elseif v.custom == false and V.cdo and V.pc then
        local old, ok = writeKey(V, "custom|sun", false)
        local oldM, okM = writeKey(V, "custom|moon", false)
        if not (opts.quiet and ok and okM) then
            log(string.format("sky: %s: the custom sun off (it was %s): %s", why, fmt(old), ok and "done" or "FAILED"))
            log(string.format("sky: %s: the custom moon off (it was %s): %s", why, fmt(oldM), okM and "done" or "FAILED"))
        end
    elseif v.custom ~= nil and not opts.quiet then
        log(string.format("sky: %s: the custom sun NOT set: %s", why, not V.cdo and "no Default__CloudlyActor" or "no player controller"))
    end
    if (s.el or s.az) and V.cdo and opts.shadows ~= false then
        local okU = pcall(function() V.cdo:ForceUpdateShadows(8) end)
        if not (opts.quiet and okU) then log("sky: " .. why .. ": ForceUpdateShadows(8) " .. (okU and "called" or "failed")) end
    end
    local fkey = table.concat(failed, ",")
    if not opts.quiet or (#failed > 0 and fkey ~= SKY.failedKey) then
        log(string.format("sky: %s: %d values written%s (sky actor %s by %s; %d renderer(s), %d sky light(s), %d post-process volume(s)%s)",
            why, done, #failed > 0 and string.format(", %d NOT: %s", #failed, table.concat(failed, ", ")) or "", short(V.actor),
            tostring(V.actorBy), #V.rend, #V.ctrl, #V.ppv, V.held and (", walks held: " .. V.held) or ""))
    end
    if opts.quiet then SKY.failedKey = fkey end
    return done, failed
end

-- the originals of what outlives a level torn down with it changed, put back in the next tick that can (SKY.idleTick):
-- the custom sun's flags, and the sky asset's values (with its path, to find it again)
local function pendingFrom()
    local p = nil
    for _, k in ipairs(SKY.order) do
        if (k == "custom|sun" or k == "custom|moon" or k:find("^asset|")) and SKY.orig[k] ~= nil then p = p or {}; p[k] = SKY.orig[k] end
    end
    if p then p.assetPath = SKY.assetPath end
    return p
end
local function pendingAsset(P)
    local keys = {}
    for k in pairs(P or {}) do if type(k) == "string" and k:find("^asset|") then keys[#keys + 1] = k end end
    table.sort(keys)
    return keys
end

-- opts (the retry's): V a view to use (else found afresh), quiet (logged only when something was put back)
function SKY.restore(why, opts)
    why = tostring(why or "?")
    opts = opts or {}
    if #SKY.order == 0 then SKY.retry = nil; return 0, 0 end
    if levelTorn and levelTorn() then
        SKY.pending = pendingFrom()
        local nA = #pendingAsset(SKY.pending)
        log(string.format("sky: %s: the level's torn down: its %d changed values go with it, none put back now%s", why, #SKY.order,
            SKY.pending and string.format(" (%s put back in the next tick that can)", nA > 0 and string.format("the sky asset's %d and the custom sun's", nA)
                or "the custom sun's") or ""))
        SKY.orig, SKY.order, SKY.retry, SKY.assetPath = {}, {}, nil, nil
        return 0, 0
    end
    local V = opts.V or SKY.view()
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
    local loud = not (opts.quiet and put == 0)
    if loud then SKY.logGroups("sky: " .. why .. ": put back", keys, function(k) return text[k] end) end
    -- ((code review of 2026-11-07, finding 12) a value whose object wasn't found is kept, its original with it, and tried
    -- again every tick (SKY.retryTick) until it's put back or the level goes (LEVEL_DROPS forgets it then); before, it was
    -- forgotten here and stayed as the arc had left it. The custom sun's flags as before: put back by SKY.idleTick)
    local pend, keepO, keepK = nil, {}, {}
    for _, k in ipairs(lost) do
        if k:find("^custom|") then pend = pend or {}; pend[k] = SKY.orig[k]
        else keepO[k] = SKY.orig[k]; keepK[#keepK + 1] = k end
    end
    if pend or not opts.quiet then SKY.pending = pend end
    if loud then
        log(string.format("sky: %s: put back %d of %d changed values, %d read back as they were%s%s%s", why, put, #order, same,
            #lost > 0 and string.format("; %d NOT (their objects not found%s): %s", #lost, V.held and (", walks held: " .. V.held) or "",
                table.concat(lost, ", ")) or "", pend and "; the custom sun put back in the next level" or "",
            #keepK > 0 and string.format("; %d kept to be tried again every tick", #keepK) or ""))
    end
    SKY.orig, SKY.order = keepO, keepK
    if next(keepO) == nil then SKY.assetPath = nil end
    if #keepK > 0 then
        SKY.retry = SKY.retry or { why = why, tries = 0, freshAt = os.clock() + 10 }
    else
        if SKY.retry and SKY.retry.tries > 0 then
            log(string.format("sky: %s: every kept value put back now (%d tries)", SKY.retry.why, SKY.retry.tries))
        end
        SKY.retry = nil
    end
    return put, same
end
-- (sv_main.lua probeTick, every tick while SKY.retry) the values SKY.restore couldn't put back tried again on the kept
-- view, and on a fresh one (an object that wasn't found then may be now) 10 s on, then 20, 40, ... at most every 5
-- minutes (an object gone for good costs a walk that often, no more); not while the arc writes the sky (it puts
-- everything back at its end), nor while walks are held or the level's going (LEVEL_DROPS forgets them untouched)
function SKY.retryTick()
    local R = SKY.retry
    if not R then return end
    if #SKY.order == 0 then SKY.retry = nil; return end
    if (levelTorn and levelTorn()) or (walkHold and walkHold()) or (ARC and ARC.on) then return end
    local now = os.clock()
    R.tries = R.tries + 1
    local V
    if now >= (R.freshAt or 0) then
        R.freshEvery = math.min(300, (R.freshEvery or 5) * 2)
        R.freshAt = now + R.freshEvery
        V = SKY.view()
    else
        V = SKY.viewCached(now)
    end
    SKY.restore(R.why, { V = V, quiet = true })
end

-- (sv_main.lua probeTick, while SKY.pending) what a torn-down level left changed and outlives it, put back as it was
-- (every 5 s, 12 tries): a custom sun or moon in the next level that has a player controller; the sky asset's values
-- the moment it's found loaded (StaticFindObject on its path: no walk), and when it isn't loaded any more (12 tries) it's
-- read from its package again, as shipped, when it's next needed
function SKY.idleTick()
    local P = SKY.pending
    if not P then return end
    local now = os.clock()
    if now < (SKY.idleAt or 0) or (levelTorn and levelTorn()) or (walkHold and walkHold()) then return end
    SKY.idleAt = now + 5
    SKY.idleTries = (SKY.idleTries or 0) + 1
    local last = SKY.idleTries >= 12
    if (P["custom|sun"] ~= nil or P["custom|moon"] ~= nil) and not P.customDone then
        local pc = liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController")
        local cdo = StaticFindObject("/Script/Cloudly.Default__CloudlyActor")
        local done = {}
        if pc ~= nil and liveObj(pc) and cdo ~= nil and liveObj(cdo) then
            if P["custom|sun"] ~= nil and pcall(function() cdo:SetUseCustomSun(pc, P["custom|sun"] == true) end) then done[#done + 1] = "sun " .. fmt(P["custom|sun"]) end
            if P["custom|moon"] ~= nil and pcall(function() cdo:SetUseCustomMoon(pc, P["custom|moon"] == true) end) then done[#done + 1] = "moon " .. fmt(P["custom|moon"]) end
        end
        if #done > 0 or last then
            log(string.format("sky: the custom sun a torn-down level left changed: %s", #done > 0 and ("put back (" .. table.concat(done, ", ") .. ")")
                or "NOT put back (no player controller or Cloudly in 12 tries)"))
            P.customDone = true
        end
    else
        P.customDone = true
    end
    local aKeys = pendingAsset(P)
    if #aKeys > 0 and not P.assetDone then
        local o = P.assetPath and StaticFindObject(P.assetPath) or nil
        if o ~= nil and liveObj(o) then
            local n = 0
            for _, k in ipairs(aKeys) do
                local path = SP_PATH[k:match("^asset|(.+)$")]
                if path and pcall(function() setPath(o.Data, path, P[k]) end) then n = n + 1 end
            end
            log(string.format("sky: the sky asset a torn-down level left changed: %d of %d values put back (%s)", n, #aKeys, tostring(P.assetPath)))
            P.assetDone = true
        elseif last then
            log(string.format("sky: the sky asset a torn-down level left changed (%d values): not loaded now (%s): read from its "
                .. "package again, as shipped, when it's next needed", #aKeys, tostring(P.assetPath)))
            P.assetDone = true
        end
    else
        P.assetDone = true
    end
    if P.customDone and P.assetDone then SKY.pending, SKY.idleTries = nil, 0 end
end

-- (the teardown gate's drop, sv_core.lua levelDrop: the originals are the level's, forgotten untouched)
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the sky"] = function()
        if #SKY.order > 0 then SKY.pending = pendingFrom() end
        SKY.orig, SKY.order, SKY.retry, SKY.assetPath = {}, {}, nil, nil
    end
end
end

-- The level's sky objects kept between applies (the arc writes every CFG.sky.arc.apply_s: four walks each was too many),
-- each checked live (liveObj) before it's used again, found afresh past maxAge or when any is gone
do
local VC = { V = nil, at = -1e9 }
local function live(o) return o ~= nil and liveObj(o) end
local function viewLive(V)
    if not (V and V.actor and live(V.actor)) then return false end
    for _, k in ipairs({ "sun", "asset", "interp", "cskyl", "pc", "env", "vfx" }) do
        if V[k] ~= nil and not live(V[k]) then return false end
    end
    for _, list in ipairs({ V.rend, V.ctrl, V.ppv }) do
        for _, x in ipairs(list or {}) do if not live(x.obj) then return false end end
    end
    return true
end
-- ((code review of 2026-11-07, finding 4) kept while every object of it is live, however old (maxAge: only a caller that
-- wants one no older), found afresh the moment one is gone; a view with no sky actor (not loaded yet, walks held) is
-- looked for again at most every NO_ACTOR_S. Before, the arc walked again (3-5 FindAllOf, ~100-350 ms) every 30 s with
-- everything live, and every tick half while the actor was missing)
local NO_ACTOR_S = 10
SKY.NO_ACTOR_S = NO_ACTOR_S
function SKY.viewCached(now, maxAge)
    local V = VC.V
    if V and now >= VC.at then
        if V.actor then
            if (maxAge == nil or now - VC.at < maxAge) and viewLive(V) then return V end
        elseif now - VC.at < NO_ACTOR_S then
            return V
        end
    end
    VC.V, VC.at = SKY.view(), now
    VC.walks = (VC.walks or 0) + 1
    return VC.V
end
function SKY.viewWalks() return VC.walks or 0 end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the sky's view"] = function() VC.V, VC.at = nil, -1e9 end end
end

---------------------------------------------------------------------------------------------------- the day-night arc
-- (0.74.0; FISHING_ROUND_PLAN.md 0, tools/re/FISHING.md 5) GONE FISHIN' (round F, RUN.arcF) starts the run's sunset:
--   k = round - F   0 the stock sky; 1-5 the sun sinks a step a round (sink_el / sink_az); 6 sunset (THE FESTIVAL);
--                   7 .. 6 + night_rounds night (the light at the moon's spot, the moon on; 3 rounds: the user,
--                   2026-11-07, "have the night time last for 3 rounds before the sun rises again"); 7 + night_rounds
--                   dawn in the east, rising over sunrise_rounds rounds; then midday, held for the rest of the run
-- A round drifts from its own sky toward the next one's (within_x of the step over round_s of its fight; a step that
-- swaps the sun for the moon or back only swap_within_x, so the swap comes at its darkest point in the break, the light
-- at dark_factor then), and the break finishes the step by the next round's start. Brightness (the light's factor, the
-- city's glow) moves in log space, the sun's bearing the short way round. Every game works out the same sky from the
-- round, its state, its seconds and F (a joiner's from the host's "rnd", F from its field 15): a new level, a late
-- joiner or a step of the test key blends in over blend_s. Written every apply_s on the kept view (SKY.viewCached), the
-- MPC values every tick (the airfield's STORE may switch the graphics row back); the colours are left alone while
-- VALKA's red sky is on (her red layers on the arc and fades back to it). Everything the arc changed is put back at the
-- run's end (sv_main.lua runLeft: SKY.restore), at a restart (SKY.arcReset) and when a run has no F any more; a level
-- torn down drops it untouched (LEVEL_DROPS).
--   SKY.arcF()             the run's F, or nil
--   SKY.arcSet(F, why)     F set (GONE FISHIN''s start on the host; a joiner from "rnd"; the test keys)
--   SKY.arcAnchor(k, base) the sky at the start of round F + k (base: the stock sky's numbers)
--   SKY.arcAt(k, u, base)  the sky u (0-1) of the way from round F + k's to F + k + 1's
--   SKY.arcHoldsValka(r)   VALKA can't come in round r: from GONE FISHIN' to the arc's midday (valka_gate)
--   SKY.arcEnd()           the last round of the arc (k): the round before midday is held
--   SKY.arcTick(now)       every tick of a run, every game (sv_main.lua probeTickB)
--   SKY.arcReset(why)      put back now and forgotten (a restart, the run's end)
ARC = { on = false, base = nil, last = nil, roundAt = {}, said = {} }
do
local FIELDS = { "el", "az", "factor", "r", "g", "b", "disc", "moon", "mel", "maz", "stars", "ex_min", "ex_max", "ex_bias",
                 "sl_x", "sl_r", "sl_g", "sl_b", "em", "vfx" }
local LOG_FIELDS = { factor = true, em = true }        -- (brightness: log space)
local MODE_FIELDS = { el = true, az = true, factor = true, r = true, g = true, b = true, disc = true, moon = true,
                      mel = true, maz = true }
local function acfg() return (CFG.sky or {}).arc or {} end
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function lerpLog(a, b, t)
    if a > 0 and b > 0 then return 10 ^ lerp(math.log(a, 10), math.log(b, 10), t) end
    return lerp(a, b, t)
end
local function lerpAz(a, b, t)
    local d = ((b - a + 180) % 360) - 180
    local x = a + d * t
    x = ((x + 180) % 360) - 180
    if x == -180 and b > 0 then x = 180 end
    return x
end
local function copy(s) local t = {}; for k, v in pairs(s) do t[k] = v end; return t end
local function trip(t, d) t = type(t) == "table" and t or d; return n(t[1], d[1]), n(t[2], d[2]), n(t[3], d[3]) end

function SKY.arcF()
    local F = RUN and RUN.arcF
    if type(F) == "number" and F >= -20 and F == math.floor(F) then return F end   -- (under 1: a test key's early festival)
    return nil
end
local function nightRounds() return math.max(1, math.floor(n(acfg().night_rounds, 3))) end
function SKY.arcEnd() return 7 + nightRounds() + math.max(1, math.floor(n(acfg().sunrise_rounds, 4))) - 1 end
function SKY.arcSet(F, why)
    F = tonumber(F)
    if not (RUN and F and F >= -20) then return false end
    F = math.floor(F)
    if RUN.arcF == F then return false end
    local was = RUN.arcF
    RUN.arcF, RUN.dirty = F, true
    if ARC.on then ARC.blendFrom, ARC.blendAt = ARC.last and copy(ARC.last) or nil, nil end   -- (a step: blended in)
    log(string.format("sky: arc: GONE FISHIN' at round %d%s (%s): the festival's round %d, midday from round %d", F,
        was and string.format(" (was %d)", was) or "", tostring(why or "?"), F + math.floor(n((CFG.specials.festival or {}).round_after, 6)),
        F + SKY.arcEnd() + 1))
    return true
end
function SKY.arcHoldsValka(round)
    local c = acfg()
    if c.valka_gate == false then return false end
    local F = SKY.arcF()
    round = tonumber(round)
    if not (F and round) then return false end
    local last = (c.enabled ~= false and (CFG.sky or {}).enabled ~= false) and SKY.arcEnd()
        or math.floor(n((CFG.specials.festival or {}).round_after, 6))
    return round >= F and round <= F + last
end

-- ((2026-11-07) the sky test's custom sun left the user's asset at 35 / -130 with the moon on, and a run that ends
-- without its restore (a crash) leaves the arc's) The sky asset's values an earlier run left changed: their shipped
-- values (CFG.sky.arc.stock.asset, Mission 4's as read in game) taken as their originals, so the arc starts from the
-- shipped sky and puts it back; each logged once. How many differed.
function SKY.assetShipped(V)
    local ship = (acfg().stock or {}).asset
    if not (V and V.asset and type(ship) == "table") then return 0 end
    local diff = {}
    for _, fd in ipairs(SKY.SP) do
        local f, k = fd[1], "asset|" .. fd[1]
        if ship[f] ~= nil and SKY.orig[k] == nil then
            local get = SKY.slot(V, k)
            local v = get and get()
            if v ~= nil and not SKY.same(v, ship[f]) then
                SKY.orig[k] = ship[f]
                SKY.order[#SKY.order + 1] = k
                diff[#diff + 1] = string.format("%s %s (shipped %s)", f, SKY.fmt(v), SKY.fmt(ship[f]))
            end
        end
    end
    if #diff > 0 then
        SKY.noteAsset(V, "asset|sun_el")                 -- (its path, for a restore after a level torn down)
        log(string.format("sky: arc: the sky asset was left changed by an earlier run or test (%d values: %s): the shipped "
            .. "values used, and put back at the end", #diff, table.concat(diff, ", ")))
    end
    return #diff
end

-- The stock sky's numbers: the level's own (the sky asset's params as shipped, the light, the sky lights, the exposure
-- and the MPCs as they were before Survival changed them: SKY.orig), else CFG.sky.arc.stock (Mission 4's)
function SKY.arcBase(V)
    local st = acfg().stock or {}
    local b = { el = n(st.el, 15), az = n(st.az, 142), factor = n(st.factor, 120000), r = 1, g = 1, b = 1, disc = n(st.disc, 0.5),
                moon = 0, mel = n(st.el, 15), maz = n(st.az, 142), stars = 0, sl_x = 1, sl_r = 1, sl_g = 1, sl_b = 1,
                em = n(st.emissive, 1), vfx = n(st.vfx_ev, 11), from = "CFG.sky.arc.stock" }
    b.ex_min, b.ex_max, b.ex_bias = trip(st.exposure, { 13, 14, 0 })
    if not V then return b end
    SKY.assetShipped(V)
    local function rd(k)
        if SKY.orig[k] ~= nil then return SKY.orig[k] end
        local get = SKY.slot(V, k)
        return get and get() or nil
    end
    local got = 0
    local function take(field, key, f)
        local v = rd(key)
        if type(v) == "boolean" then v = v and 1 or 0 end
        if type(v) == "number" then b[field] = f and f(v) or v; got = got + 1 end
    end
    if V.asset then
        take("el", "asset|sun_el"); take("az", "asset|sun_az"); take("factor", "asset|sun_factor"); take("disc", "asset|sun_disc")
        take("r", "asset|sun_r"); take("g", "asset|sun_g"); take("b", "asset|sun_b")
        take("moon", "asset|moon_on"); take("mel", "asset|moon_el"); take("maz", "asset|moon_az")
        b.stars_on = rd("asset|stars_on")
        b.st = {}
        for _, f in ipairs({ "stars_int", "stars_bg", "stars_radius", "stars_frac", "stars_rx", "stars_ry", "stars_rz", "stars_mask" }) do
            local v = rd("asset|" .. f)
            if type(v) == "number" then b.st[f] = v end
        end
    end
    local c1 = V.ctrl and V.ctrl[1]
    if c1 then
        local function byte(v) return math.max(0, math.min(1, v / 255)) end
        take("sl_r", "skyl|" .. c1.name .. "|r", byte); take("sl_g", "skyl|" .. c1.name .. "|g", byte); take("sl_b", "skyl|" .. c1.name .. "|b", byte)
    end
    for _, p in ipairs(V.ppv or {}) do
        local on = false
        pcall(function() on = p.obj.Settings.bOverride_AutoExposureMinBrightness == true end)
        if on and not b.exFrom then
            b.exFrom = p.name
            take("ex_min", "ppv|" .. p.name .. "|min"); take("ex_max", "ppv|" .. p.name .. "|max"); take("ex_bias", "ppv|" .. p.name .. "|bias")
        end
    end
    take("em", "mpc|env|Ctrl_Scene_EmissiveScale"); take("vfx", "mpc|vfx|VFXEmissiveEV")
    if got > 0 then b.from = string.format("the level's (%d values)", got) end
    return b
end

-- the sky at the start of round F + k, on the stock sky `base`
function SKY.arcAnchor(k, base)
    local c, ng = acfg(), (CFG.sky or {}).night or {}
    local a = copy(base)
    a.mode, a.set_el, a.stars = "sun", nil, 0
    local R = math.max(1, math.floor(n(c.sunrise_rounds, 4)))
    local function exp(t) a.ex_min, a.ex_max, a.ex_bias = trip(t, { base.ex_min, base.ex_max, base.ex_bias }) end
    if k <= 0 then return a end
    local sinkEl, sinkAz = c.sink_el or {}, c.sink_az or {}
    if k <= 5 then
        a.el, a.az = n(sinkEl[k], base.el), n(sinkAz[k], base.az)
        local dx1, dx2, dx3 = trip(c.dusk_exposure, { 11, 14, -0.5 })
        local t = k / 5
        a.ex_min, a.ex_max, a.ex_bias = lerp(base.ex_min, dx1, t), lerp(base.ex_max, dx2, t), lerp(base.ex_bias, dx3, t)
        a.stars = 1
    elseif k == 6 then
        a.el, a.az, a.set_el = n(c.sunset_el, 1), n(c.sunset_az, 160), n(c.set_el, -3)
        exp(c.sunset_exposure)
        a.sl_x, a.em, a.vfx, a.stars = n(c.sunset_skylight, 0.5), n(c.sunset_emissive, 100), n(c.sunset_vfx_ev, 8), 1
    elseif k <= 6 + nightRounds() then              -- (the night: the same sky each of its rounds)
        a.mode = "moon"
        a.el, a.az, a.factor = n(ng.sun_el, 35), n(ng.sun_az, -130), n(ng.factor, 0.5)
        a.r, a.g, a.b = trip(ng.rgb, { 0.89, 0.96, 1 })
        a.disc, a.moon, a.mel, a.maz = n(ng.sun_disc, 0.57), 1, n(ng.moon_el, 35), n(ng.moon_az, -130)
        exp(ng.exposure)
        a.sl_x = n(ng.skylight_x, 0.1)
        a.sl_r, a.sl_g, a.sl_b = trip(ng.skylight_rgb, { 0.55, 0.65, 1 })
        a.em, a.vfx, a.stars = n(ng.emissive, 10000), n(ng.vfx_ev, -2), 1
    else
        local dawn = copy(base)
        dawn.el, dawn.az = n(c.dawn_el, -4), n(c.dawn_az, 105)
        dawn.ex_min, dawn.ex_max, dawn.ex_bias = trip(c.dawn_exposure, { 4, 14, -2 })
        dawn.sl_x, dawn.em, dawn.vfx = n(c.dawn_skylight, 0.3), n(c.dawn_emissive, 10000), n(c.dawn_vfx_ev, 5)
        local mid = copy(base)
        mid.el, mid.az = n(c.midday_el, 52.9), n(c.midday_az, 180)
        mid.ex_min, mid.ex_max, mid.ex_bias = trip(c.day_exposure, { 13, 14, 0 })
        local t = math.min(1, (k - 7 - nightRounds()) / R)
        -- ((2026-11-07) the user at round F+9: "sun is currently up in the sky but it's not back to normal brightness
        -- yet") the light (exposure, sky light, glow, the effects' EV) back to the day's sunrise_light_x times as fast as
        -- the sun climbs: by the sunrise's middle with 2
        local tl = math.min(1, t * math.max(1, n(c.sunrise_light_x, 2)))
        for _, f in ipairs(FIELDS) do
            local x, y = dawn[f], mid[f]
            if type(x) == "number" and type(y) == "number" then
                local tf = MODE_FIELDS[f] and t or tl
                if f == "az" then a[f] = lerpAz(x, y, tf) elseif LOG_FIELDS[f] then a[f] = lerpLog(x, y, tf) else a[f] = lerp(x, y, tf) end
            end
        end
        a.stars = t < 1 and 1 or 0                    -- (the stars at their stock again with midday: unseen by day)
    end
    return a
end

-- u (0-1) of the way from round F + k's sky to F + k + 1's; a swap of the sun for the moon (or back) goes through the
-- dark in the step's middle: the light at dark_factor (the sunset's sun at set_el first), the swap at u 0.5
function SKY.arcAt(k, u, base)
    local A, B = SKY.arcAnchor(k, base), SKY.arcAnchor(k + 1, base)
    u = math.max(0, math.min(1, u))
    local s = { mode = A.mode, k = k, u = u }
    for _, f in ipairs(FIELDS) do
        local x, y = A[f], B[f]
        if type(x) == "number" and type(y) == "number" then
            if f == "az" or f == "maz" then s[f] = lerpAz(x, y, u) elseif LOG_FIELDS[f] then s[f] = lerpLog(x, y, u) else s[f] = lerp(x, y, u) end
        end
    end
    if A.mode ~= B.mode then
        -- ((2026-11-07) the user's screenshot of the sun at -2 / -105 at full strength: "very nice", "slowly get it to
        -- transition to that sunset") A step that swaps the sun for the moon (or back) holds its own sky through the fight
        -- (u up to hold = swap_within_x): only the sunset's sun moves, sinking to set_el at full strength. From hold to the
        -- swap at u 0.5 (the break's first half) its light fades to dark_factor; the rest (exposure, sky light, glow, EV,
        -- stars) moves on to the next round's from hold to the break's end. (Before, the light faded from the fight's
        -- start: ~7 at -2 deg, where the user's 120000 looked right.)
        local c = acfg()
        local dark = math.max(1e-3, n(c.dark_factor, 0.25))
        local hold = math.max(0, math.min(0.49, n(c.swap_within_x, 0.45)))
        local v = math.max(0, (u - hold) / (1 - hold))
        for _, f in ipairs(FIELDS) do
            local x, y = A[f], B[f]
            if not MODE_FIELDS[f] and type(x) == "number" and type(y) == "number" then
                if LOG_FIELDS[f] then s[f] = lerpLog(x, y, v) else s[f] = lerp(x, y, v) end
            end
        end
        local from, to, t
        if u < 0.5 then
            from, to = copy(A), copy(A)
            if u <= hold then
                t = hold > 0 and u / hold or 1
                if A.set_el then to.el = A.set_el end    -- (the sunset's sun sinks, its light held)
            else
                t = (u - hold) / (0.5 - hold)
                if A.set_el then from.el, to.el = A.set_el, A.set_el end
                to.factor = dark                          -- (then the last light goes, before the moon)
            end
            s.mode = A.mode
        else
            from, to, t = copy(B), B, (u - 0.5) / 0.5
            from.factor = dark
            s.mode = B.mode
        end
        for f in pairs(MODE_FIELDS) do
            local x, y = from[f], to[f]
            if type(x) == "number" and type(y) == "number" then
                if f == "az" or f == "maz" then s[f] = lerpAz(x, y, t) elseif LOG_FIELDS[f] then s[f] = lerpLog(x, y, t) else s[f] = lerp(x, y, t) end
            end
        end
    elseif A.set_el then
        s.el = lerp(A.el, A.set_el, u)                  -- (the sunset round's sun sinks to set_el)
    end
    return s
end

-- the sky struct s as SKY.apply's v (colours left out with VALKA's red sky on)
local function asV(s, base, red)
    local c = acfg()
    local st, mx = base.st or {}, (CFG.sky or {}).stars or {}
    local v = { sun = { el = s.el, az = s.az, factor = s.factor, disc = s.disc } }
    if not red then v.sun.rgb = { s.r, s.g, s.b } end
    v.moon = { enable = s.moon >= 0.5, el = s.mel, az = s.maz }
    if s.stars > 0 or base.stars_on ~= nil then
        local function sv(f, m) local b0 = st[f]; if b0 == nil then return s.stars >= 0.5 and m or nil end; return lerp(b0, m, s.stars) end
        local rot = type(mx.rotation) == "table" and mx.rotation or { 2.578, 0, 0 }
        v.stars = { enable = (s.stars > 0) or (base.stars_on == true) or nil,
                    intensity = sv("stars_int", n(mx.intensity, 7)), background = sv("stars_bg", n(mx.background, 22)),
                    radius = sv("stars_radius", n(mx.radius, 2.5)), fraction = sv("stars_frac", n(mx.fraction, 0.73)),
                    rotation = { sv("stars_rx", n(rot[1], 2.578)), sv("stars_ry", n(rot[2], 0)), sv("stars_rz", n(rot[3], 0)) },
                    mask_start = sv("stars_mask", n(mx.mask_start, 0.263)) }
        if s.stars <= 0 and base.stars_on ~= nil then v.stars.enable = base.stars_on end
    end
    v.exposure = { min = s.ex_min, max = s.ex_max, bias = s.ex_bias }
    v.skylight = { x = s.sl_x }
    if not red then v.skylight.rgb = { s.sl_r, s.sl_g, s.sl_b } end
    v.mpc = { emissive = s.em, vfx_ev = s.vfx }
    -- path (CFG.sky.arc.path): "asset" (the default since the user's sky test of 2026-11-07: the level's sky asset, which
    -- Cloudly draws and lights by, nothing else of the sun's); "copies" (the renderer's copies and the light: undone
    -- every frame); "custom" (those and Cloudly's custom sun API, which moves the asset's sun)
    if c.path == "custom" then v.custom = true
    elseif c.path ~= "copies" then v.asset, v.copies, v.light = true, false, false end
    return v
end
SKY.arcV = asV

-- where the arc is now: k (round - F), u (0-1 of the way to the next round's sky) and why
local function arcPlace(now, F)
    local c = acfg()
    local r, st = D and tonumber(D.round) or 0, D and D.state
    local k = r - F
    if k < 0 then return 0, 0, "before GONE FISHIN'" end
    local swap = SKY.arcAnchor(k, ARC.base).mode ~= SKY.arcAnchor(k + 1, ARC.base).mode
    local cap = swap and n(c.swap_within_x, 0.45) or n(c.within_x, 0.75)
    if st == "wait" then
        local b = ARC.brk
        if not (b and b.round == r) then
            local at0 = ARC.roundAt[r]
            local u0 = at0 and cap * math.min(1, math.max(0, now - at0) / math.max(1, n(c.round_s, 240))) or 0
            b = { round = r, at = now, u0 = u0 }
            ARC.brk = b
        end
        local due = D and tonumber(D.at) or (now + 20)
        local span = math.max(1, due - b.at - 1)
        local t = math.min(1, math.max(0, now - b.at) / span)
        if swap and b.u0 < 0.5 then                     -- (the swap, the darkest point, in the break's middle)
            if t < 0.5 then return k, b.u0 + (0.5 - b.u0) * t / 0.5, "the break, darkening" end
            return k, 0.5 + 0.5 * (t - 0.5) / 0.5, "the break, lightening"
        end
        return k, b.u0 + (1 - b.u0) * t, "the break"
    end
    ARC.roundAt[r] = ARC.roundAt[r] or now
    return k, cap * math.min(1, math.max(0, now - ARC.roundAt[r]) / math.max(1, n(c.round_s, 240))), "the fight"
end

local MPC_KEYS = { em = "mpc|env|Ctrl_Scene_EmissiveScale", vfx = "mpc|vfx|VFXEmissiveEV" }
local mpcV = { }
-- the MPC values written now (every tick: the game may put them back), on a small view of their own (no walks)
local function mpcWrite(s)
    local c = CFG.sky or {}
    if not liveObj(survivalPC) then return 0 end
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    if not (kml and liveObj(kml)) then return 0 end
    if not (mpcV.env and liveObj(mpcV.env)) and type(c.mpc_env) == "string" then mpcV.env = loadObject(c.mpc_env) end
    if not (mpcV.vfx and liveObj(mpcV.vfx)) and type(c.mpc_vfx) == "string" then mpcV.vfx = loadObject(c.mpc_vfx) end
    local V = { kml = kml, pc = survivalPC, env = mpcV.env, vfx = mpcV.vfx }
    local nW = 0
    for f, k in pairs(MPC_KEYS) do
        if type(s[f]) == "number" then
            local _, ok = SKY.writeKey(V, k, s[f])
            if ok then nW = nW + 1 end
        end
    end
    return nW
end

local function fmt1(v) return type(v) == "number" and string.format("%.1f", v) or tostring(v) end
local function arcLine(s, why)
    return string.format("k %d, u %.2f (%s): %s %s / %s, factor %s, exposure %s / %s / %s, sky light x%.2f, glow %s, EV %s, stars %.0f",
        s.k, s.u, why, s.mode == "moon" and "the light at the moon" or "sun", fmt1(s.el), fmt1(s.az), string.format("%.4g", s.factor),
        fmt1(s.ex_min), fmt1(s.ex_max), fmt1(s.ex_bias), s.sl_x, string.format("%.4g", s.em), fmt1(s.vfx), s.stars)
end

-- ((2026-11-07) the arc wrote the renderer's copies for a whole run and nothing of the sun showed) Whether what the arc
-- writes is what's drawn: the drawn copy's sun (the renderer's SkyParamsRO, which Cloudly fills from the asset every frame)
-- and the sun light's intensity, read a write on, once the written sky is off the stock one (1 deg, or the light's
-- strength by a third). Followed: logged once. Not followed 3 checks running: logged, and from then on the exposure, the
-- sky light and the glow stay at the day's (SKY.arcTick), so a sky that doesn't darken can't glare either.
local function followCheck(V)
    local w, b = ARC.wrote, ARC.base
    if not (w and b) or ARC.followSaid then return end
    local function off(x, y)
        if x > 0 and y > 0 then return math.abs(math.log(x, 10) - math.log(y, 10)) end
        return math.abs(x - y)
    end
    if math.abs(w.el - b.el) < 1 and off(w.factor, b.factor) < 0.12 then return end     -- (still the stock sky: nothing to tell)
    local r1 = V.rend and V.rend[1]
    local gE = r1 and SKY.slot(V, "copy|" .. r1.name .. "|RO|1|sun_el")
    local gI = SKY.slot(V, "light|int")
    local el, li = gE and gE(), gI and gI()
    if type(el) ~= "number" and type(li) ~= "number" then
        ARC.followSaid = true
        log("sky: arc: the drawn sky and the sun light can't be read: whether they follow the arc is NOT checked")
        return
    end
    local okE = type(el) ~= "number" or math.abs(el - w.el) <= 0.5
    local okI = type(li) ~= "number" or off(li, w.factor) <= 0.2
    local line = string.format("the drawn sun at %s (written %.2f), the sun light %s (written %s)",
        type(el) == "number" and string.format("%.2f", el) or "not read", w.el,
        type(li) == "number" and string.format("%.4g", li) or "not read", string.format("%.4g", w.factor))
    if okE and okI then
        ARC.followSaid, ARC.misses = true, 0
        log("sky: arc: the drawn sky follows the arc: " .. line)
    else
        ARC.misses = (ARC.misses or 0) + 1
        if ARC.misses >= 3 then
            ARC.followSaid, ARC.noFollow = true, true
            log("sky: arc: the drawn sky does NOT follow the arc (3 checks running): " .. line .. "; the exposure, the sky light "
                .. "and the glow kept at the day's from now on (no glare)")
        end
    end
end

function SKY.arcReset(why)
    local was = ARC.on
    ARC.on, ARC.base, ARC.last, ARC.roundAt, ARC.brk, ARC.blendFrom, ARC.blendAt, ARC.nextApply = false, nil, nil, {}, nil, nil, nil, nil
    ARC.lastK, ARC.mode = nil, nil
    ARC.wrote, ARC.followSaid, ARC.misses, ARC.noFollow = nil, nil, nil, nil
    mpcV.env, mpcV.vfx = nil, nil
    if was and #SKY.order > 0 then
        local okR, put = pcall(SKY.restore, "the arc's over (" .. tostring(why) .. ")")
        log(string.format("sky: arc: over (%s): %s", tostring(why), okR and (tostring(put) .. " values put back") or ("restore error " .. tostring(put))))
    end
end

function SKY.arcTick(now)
    local c, sc = acfg(), CFG.sky or {}
    if sc.enabled == false or c.enabled == false or not D then return end
    if levelTorn and levelTorn() then return end
    local F = SKY.arcF()
    if not F then
        if ARC.on then SKY.arcReset("the run has no GONE FISHIN' now") end
        return
    end
    -- TEST ONLY BEGIN (the sky test's steps 2-4 write the sky themselves: the arc waits)
    if SKY.test and SKY.test.step and SKY.test.step >= 2 and SKY.test.step <= 4 then return end
    -- TEST ONLY END
    if walkHold and walkHold() then return end
    local first = not ARC.on
    if first then
        ARC.on, ARC.roundAt, ARC.brk = true, {}, nil
        ARC.nextApply = 0
    end
    if not ARC.base then
        local V = SKY.viewCached(now)
        if not V.actor then
            if not ARC.noActorSaid then ARC.noActorSaid = true; log("sky: arc: no sky actor found yet: waiting") end
            return
        end
        ARC.base = SKY.arcBase(V)
        log(string.format("sky: arc: the stock sky from %s: sun %s / %s, factor %s, exposure %s / %s / %s, glow %s, EV %s; "
            .. "written through %s", ARC.base.from, fmt1(ARC.base.el), fmt1(ARC.base.az), string.format("%.4g", ARC.base.factor),
            fmt1(ARC.base.ex_min), fmt1(ARC.base.ex_max), fmt1(ARC.base.ex_bias), string.format("%.4g", ARC.base.em),
            fmt1(ARC.base.vfx), c.path == "custom" and "Cloudly's custom sun and the renderer's copies"
                or c.path == "copies" and "the renderer's copies and the light's rotation"
                or "the level's sky asset (Cloudly draws the sky and its sun light from it)"))
        if first then ARC.blendFrom, ARC.blendAt = copy(ARC.base), nil end
    end
    local k, u, why = arcPlace(now, F)
    if k > SKY.arcEnd() + 1 then k, u, why = SKY.arcEnd() + 1, 0, "midday, held" end
    local s = SKY.arcAt(k, u, ARC.base)
    -- (a blend in: a new level, a late joiner, a step of the test key)
    if ARC.blendFrom then
        ARC.blendAt = ARC.blendAt or now
        local t = math.min(1, (now - ARC.blendAt) / math.max(0.1, n(c.blend_s, 5)))
        if t >= 1 then ARC.blendFrom, ARC.blendAt = nil, nil
        else
            local b = ARC.blendFrom
            for _, f in ipairs(FIELDS) do
                if not (b.mode and b.mode ~= s.mode and MODE_FIELDS[f]) and type(b[f]) == "number" and type(s[f]) == "number" then
                    if f == "az" or f == "maz" then s[f] = lerpAz(b[f], s[f], t) elseif LOG_FIELDS[f] then s[f] = lerpLog(b[f], s[f], t)
                    else s[f] = lerp(b[f], s[f], t) end
                end
            end
            why = why .. string.format(", blending in %.0f%%", t * 100)
        end
    end
    if ARC.noFollow then                                  -- (the drawn sky doesn't follow: nothing else darkens either)
        local b = ARC.base
        s.ex_min, s.ex_max, s.ex_bias, s.em, s.vfx = b.ex_min, b.ex_max, b.ex_bias, b.em, b.vfx
        s.sl_x, s.sl_r, s.sl_g, s.sl_b = 1, b.sl_r, b.sl_g, b.sl_b
        why = why .. ", the day's exposure (the drawn sky doesn't follow)"
    end
    ARC.last = s
    pcall(mpcWrite, s)                                    -- (every tick)
    if ARC.mode ~= s.mode then
        if ARC.mode then log(string.format("sky: arc: round %d: the %s swapped for the %s at the break's darkest point", D.round or 0,
            ARC.mode == "moon" and "moon" or "sun", s.mode == "moon" and "moon" or "sun")) end
        ARC.mode = s.mode
    end
    if now < (ARC.nextApply or 0) then return end
    ARC.nextApply = now + math.max(0.25, n(c.apply_s, 2))
    local V = SKY.viewCached(now)
    if not V.actor then return end
    local red = RED and (RED.want or (tonumber(RED.k) or 0) > 0) or false
    local shadows = not (ARC.shEl and math.abs(ARC.shEl - s.el) < 0.05 and math.abs(((ARC.shAz - s.az + 180) % 360) - 180) < 0.05)
    if shadows then ARC.shEl, ARC.shAz = s.el, s.az end
    pcall(followCheck, V)
    local okA, nW, failed = pcall(SKY.apply, asV(s, ARC.base, red), "arc", { V = V, quiet = true, shadows = shadows })
    if not okA then logOnce("sky arc apply", "sky: arc: write error " .. tostring(nW)); return end
    ARC.wrote = { el = s.el, factor = s.factor }
    if ARC.lastK ~= k or now >= (ARC.logAt or 0) then
        ARC.logAt = now + 60
        log(string.format("sky: arc: round %d (F+%d): %s; %d values written%s%s", D.round or 0, k, arcLine(s, why), nW or 0,
            type(failed) == "table" and #failed > 0 and string.format(", %d not", #failed) or "", red and "; VALKA's red sky has the colours" or ""))
        ARC.lastK = k
    end
end

-- (the teardown gate's drop: the sky's objects and its originals are the level's; the arc's place comes again with the
-- next level, blended in)
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the sky's arc"] = function()
        ARC.on, ARC.base, ARC.last, ARC.brk, ARC.blendFrom, ARC.blendAt, ARC.mode, ARC.lastK = false, nil, nil, nil, nil, nil, nil, nil
        ARC.wrote, ARC.followSaid, ARC.misses, ARC.noFollow = nil, nil, nil, nil
        ARC.roundAt = {}
        mpcV.env, mpcV.vfx = nil, nil
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
--   4 the night set (CFG.sky.night, stars), the sky asset too (the arc's path): which values hold, which the game puts back
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
                custom = true, copies = true, light = true, asset = true,
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
        -- ((2026-11-07) the drawn copy (SkyParamsRO) and the sky asset apart from the other copies: in game the asset and
        -- the drawn copy followed, two working copies of the seven too, the rest and the interpolated params not)
        local e, af, rf, cf, inf = T.expect or {}, {}, {}, {}, {}
        for _, k in ipairs(keys) do
            local want = k:find("sun_el$") and e.el or e.az
            if k:find("^asset|") then af[#af + 1] = SKY.same(snap.val[k], want)
            elseif k:find("^copy|[^|]+|RO|") then rf[#rf + 1] = SKY.same(snap.val[k], want)
            elseif k:find("^copy|") then cf[#cf + 1] = SKY.same(snap.val[k], want)
            elseif k:find("^interp|") then inf[#inf + 1] = SKY.same(snap.val[k], want) end
        end
        local yaw = e.az and ((e.az + 90) % 360) or nil
        if yaw and yaw > 180 then yaw = yaw - 360 end
        local lp, ly = snap.val["light|pitch"], snap.val["light|yaw"]
        local function all(t) if #t == 0 then return "nothing to read" end for _, x in ipairs(t) do if not x then return "NO" end end return "yes" end
        local function some(t)
            local y = 0
            for _, x in ipairs(t) do if x then y = y + 1 end end
            if #t == 0 then return "nothing to read" end
            return y == #t and "yes" or y == 0 and "NO" or string.format("%d of %d", y, #t)
        end
        -- (the light's pitch reads nil in game: its yaw alone then)
        local lightFollows = (ly and e.el) and (SKY.same(ly, yaw) and (lp == nil or SKY.same(lp, -e.el))) or nil
        log(string.format("sky test: step 2: the custom sun (%s / %s): the sky asset follows: %s; the drawn copy (SkyParamsRO): %s; "
            .. "the other copies: %s; the interpolated params: %s; the light (pitch %s, yaw %s): %s; custom sun %s", SKY.fmt(e.el),
            SKY.fmt(e.az), all(af), all(rf), some(cf), all(inf), SKY.fmt(lp), SKY.fmt(ly),
            lightFollows == nil and "not read" or lightFollows and "follows" or "does NOT follow", SKY.fmt(snap.val["custom|sun"])))
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

-- TEST ONLY BEGIN
-- Ctrl+PAGE_DOWN in a run (any game: each computes its own sky; a joiner's F comes back from the host's next "rnd"): the
-- day-night arc one round on (F one less; none yet: from this round, F + 1 in), blended in over blend_s
testKey("PAGE_DOWN", "sv_sky.lua's arc step", function()
    if not (D and D.now and RUN) then log("test: Ctrl+PAGE_DOWN outside a Survival run"); return end
    local F = SKY.arcF()
    local to = F and (F - 1) or math.max(1, (D.round or 1) - 1)
    if to < 1 then log("test: Ctrl+PAGE_DOWN: the arc can't step past round 1's start"); return end
    SKY.arcSet(to, "test key Ctrl+PAGE_DOWN")
    local k = (D.round or 0) - to
    hudCallout("TEST: SKY ARC", string.format("ROUND %d IS F+%d", D.round or 0, k))
    log(string.format("test: Ctrl+PAGE_DOWN, the arc stepped: F %s -> %d (round %d is F+%d)", tostring(F), to, D.round or 0, k))
end)
-- TEST ONLY END
