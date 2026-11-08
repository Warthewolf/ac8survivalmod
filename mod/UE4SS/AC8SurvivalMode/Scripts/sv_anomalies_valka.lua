-- sv_anomalies_valka.lua: VALKA's X-02S, paint, opener railgun and round (her blinks, railgun rounds, flares, sounds
-- and parts are sv_anomalies.lua's); the special kinds table (SPC.kinds); PHANTASM's pack and the Anomaly's tick; a
-- co-op joiner's field and copy of AB.L..IN. Piece 2 of 3 of sv_anomalies.lua (sv_anomalies.lua,
-- sv_anomalies_valka.lua, sv_anomalies_dev.lua), split by tools/lua_split_part.py and run by main.lua right after the
-- piece before it: a name another part uses is a global of this mod's Lua state, its own helpers stay local.
do  -- (sv_anomalies.lua's do block, continued: this piece's own helpers stay local to it)

-- her components of class `cls` (a /Script path), from her component tree (RootComponent and AttachChildren down, as
-- SPC.V.parts walks it; test of 2026-10-24: K2_GetComponentsByClass's array gave nothing from Lua), hers only
function SPC.V.comps(o, cls)
    local out, queue, i, me = {}, {}, 1, addrOf(o)
    local class = StaticFindObject(cls)
    pcall(function() queue[1] = o.RootComponent end)
    while queue[i] and i <= 400 do
        local comp = queue[i]
        i = i + 1
        pcall(function()
            local owner = comp:GetOwner()
            if valid(owner) and addrOf(owner) == me then
                if comp:IsA(class) then out[#out + 1] = comp end
                comp.AttachChildren:ForEach(function(_, e) queue[#queue + 1] = e:get() end)
            end
        end)
    end
    return out
end

-- Her X-02S (AC7's, user, 2026-10-24: "full port as the X-02S is swing winged"; tools/x02s, cooked in UE 5.4 into
-- its own container SurvivalMode_Valka_P): her airframe's body mesh component gets SK_X02S_Valka (AC7's skeleton, its
-- sockets, so what hangs on burner_01 / _02, her afterburners, moves to the X-02S's nozzles) and plays
-- A_X02S_Valka_Sweep, the swing wings alone (AC7's x02s_Anim frames 50-100): unswept below sweep_kmh[1], swept above
-- sweep_kmh[2] (AC7's VwgMin / VwgMax), a full travel taking sweep_s. Her other meshes are hidden (again every 2 s)
-- and her parts gone (not lockable); her flight model and railguns stay the x40a's. Off (the x40a as it is) when
-- `model` is "" or doesn't load. True if on.
SPC.V.BODY_PROPS = { "PlaneBodySkelMeshComponent", "PlaneBodyMeshComponent", "PlaneBodyStaticMeshComponent", "PlaneBodyMesh" }
-- Her paint (test of 2026-10-24, 0.66.2: "her paint was all blackened out"). MI_X02S_Valka sets only Basecolor /
-- Normalmap / Livemap on AC8's MP_PP0032_f18e_Decal, the rest stays at the parent's defaults, which every stock skin
-- overrides (weathering, wet, dirt, smoke, paint regions...), and its Livemap (AC8's _MRX: metallic / roughness / ?)
-- is all black. At her reveal her MI_X02S_Valka slots get dynamic instances; a variant (CFG.specials.valka.paint, or
-- its old test key, since gone: Ctrl+9 is the ZFA-44 test T0 now) sets on them:
--   1 raw     as built (what 0.66.2 showed)
--   2 stock   the stock F/A-18E skin's scalar / vector values (MI_PP0032_f18e_001_Decal) and no dirt mask (black)
--   3 stock + white Livemap   4 stock + the parent's own dirt mask   5 stock + white Livemap and the parent's dirt
-- and, as 2 stayed black (test of 2026-10-24, 0.67.1: "she was still coated black", "her mesh was missing pieces"),
-- three that tell where it goes wrong:
--   6 stock + the F/A-18E's own Livemap (if it's ours that's wrong)   7 the F/A-18E's three textures (wrongly mapped,
--   but lit if the material works on her)   8 the engine's grid material on every slot (the mesh and its lighting alone)
SPC.V.PAINT_STOCK = "/Game/Vehicles/Aircraft/PP/PP0032_f18e/Materials/001/MI_PP0032_f18e_001_Decal"
SPC.V.PAINT_TEX = { black = "/Engine/EngineResources/Black", white = "/Engine/EngineResources/WhiteSquareTexture",
    f18_c = "/Game/Vehicles/Aircraft/PP/PP0032_f18e/Textures/001/T_PP0032_f18e_001_C", f18_mrx = "/Game/Vehicles/Aircraft/PP/PP0032_f18e/Textures/001/T_PP0032_f18e_001_MRX", f18_no = "/Game/Vehicles/Aircraft/PP/PP0032_f18e/Textures/001/T_PP0032_f18e_001_NO" }
SPC.V.PAINTS = {
    { name = "RAW" },
    { name = "STOCK", stock = true, dirt = "black" },
    { name = "STOCK + WHITE LIVEMAP", stock = true, dirt = "black", livemap = "white" },
    { name = "STOCK + PARENT DIRT", stock = true },
    { name = "STOCK + WHITE LIVEMAP + PARENT DIRT", stock = true, livemap = "white" },
    { name = "STOCK + F-18 LIVEMAP", stock = true, dirt = "black", livemap = "f18_mrx" },
    { name = "F-18 TEXTURES", stock = true, dirt = "black", livemap = "f18_mrx", basecolor = "f18_c", normal = "f18_no" },
    { name = "ENGINE GRID", material = "/Engine/EngineMaterials/WorldGridMaterial" },
    -- AC8's aircraft master (MP_Live_Vehicle_Base_UDIM, 1-7) samples virtual textures only (docs/re/AIRCRAFT_MATERIALS.md):
    -- with ordinary ones it draws black. These are AC8's general masters with ordinary samplers and skinned-mesh shaders:
    -- a dynamic instance of one, her colour and normal maps in it (not with `flat_normal`), its own Livemap default
    -- unless `livemap` says otherwise. 9 and 10 have no texture parameters at all (their packages name none): plain
    -- white (test of 2026-10-25). 11 showed her grey paint with odd shading: its Livemap default is black.
    { name = "LIVE BASE", parent = "/Game/Base/Material/MP/MP_Live_Base_CameraDitherFade" },
    { name = "LIVE BASE WPO", parent = "/Game/Base/Material/MP/MP_Live_Base_WPO" },
    { name = "CHARACTER BASE", parent = "/Game/Base/Material/Character/M_Live_Cha_Base" },
    { name = "CHARACTER + WHITE LIVEMAP", parent = "/Game/Base/Material/Character/M_Live_Cha_Base", livemap = "white" },
    { name = "CHARACTER, FLAT NORMAL", parent = "/Game/Base/Material/Character/M_Live_Cha_Base", flat_normal = true },
    { name = "CHARACTER + WHITE LIVEMAP, FLAT NORMAL", parent = "/Game/Base/Material/Character/M_Live_Cha_Base",
      livemap = "white", flat_normal = true },
    -- (0.73.76) the Falken add-on's way (docs/re/FALKEN_MATERIALS.md: an AC7 aircraft whose paint draws in AC8): an
    -- instance of a stock aircraft's GEAR material (MI_*_Gear -> MP_Gear -> M_Live_Vehicle_Base), which samples
    -- ordinary textures and has skinned-mesh shaders, not the virtual-texture skin master (black, rule 44). The x40a's
    -- own gear instance; her colour (and normal) map, the stock neutral Livemap, the base's emissive, turbine, detail and
    -- damage normals off. 15: with her normal map; 16: the Falken's exactly (flat normal, normal strength 0).
    { name = "X-40A GEAR, HER NORMALS", parent = "/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear",
      tex = { Livemap = "rt:0,0.75,1", Detail_Normal = "/Engine/EngineMaterials/DefaultNormal",
              Blend_Dameged_Normalmap = "/Engine/EngineMaterials/DefaultNormal" },
      scalars = { Ctrl_All_Emissive = 0, Turbine_speed = 0, DNormal_Strength = 0, DamegedNormal_Intencity = 0, PlayerPlane_Damage = 0 } },
    { name = "X-40A GEAR, FALKEN'S (FLAT NORMAL)", parent = "/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear",
      flat_normal = true,
      tex = { Livemap = "rt:0,0.75,1", Normalmap = "/Engine/EngineMaterials/DefaultNormal",
              Detail_Normal = "/Engine/EngineMaterials/DefaultNormal", Blend_Dameged_Normalmap = "/Engine/EngineMaterials/DefaultNormal" },
      scalars = { Ctrl_All_Emissive = 0, Turbine_speed = 0, NormalIntencity = 0, DNormal_Strength = 0, DamegedNormal_Intencity = 0,
                  PlayerPlane_Damage = 0 } },
}
-- her own textures, for the `parent` variants
SPC.V.PAINT_OWN = { Basecolor = "/Game/Mods/SurvivalMode/Valka/Textures/T_X02S_Valka_C",
                    Normalmap = "/Game/Mods/SurvivalMode/Valka/Textures/T_X02S_Valka_NO" }
-- the parent values logged once (what a stock skin changes, for the real fix)
SPC.V.PAINT_SAY = { "WeatheringWeight", "Wet_Darkness", "Wet_Range", "AO_amoumt", "MetallicMapWeight",
    "Metallic_Remap_Target_Low", "Metallic_Remap_Target_High", "Roughness_Remap", "Roughness_Contrast", "Ctrl_B_Smoke",
    "Ctrl_G_OilDirt", "Ctrl_R_ColorUnevenness", "B_Color_Weight", "G_Color_Weight", "R_ColorFade_Weight", "NormalIntencity" }
-- ((0.73.80) R30_FINDINGS specials 2 / perf 6: her reveal took ~0.7 s on the host, the X-02S, its sweep and her paint's
-- materials and textures loaded on that tick (LoadAsset_Blocking, after a StaticFindObject scan of every /Game/ path),
-- her opener ~0.74 s with her round's class and her flare's materials) Her assets, kept once loaded: SPC.V.asset(path
-- [, object]) answers the one kept while it's a live object (liveObj), else loads it (loadObject) and keeps it. Nil and
-- why if it can't be loaded. Her paint is still made on her body at her reveal (fresh dynamic instances from these:
-- an instance made in the break could be collected before she shows, and one kept loaded would keep the level's player
-- controller, its outer, alive), so she looks the same.
SPC.V.assets = {}
function SPC.V.asset(path, obj)
    local full = path .. "." .. (obj or path:match("[^/]+$"))
    local o = SPC.V.assets[full]
    if o ~= nil and liveObj(o) then return o end
    SPC.V.assets[full] = nil
    local why
    o, why = loadObject(full)
    if o ~= nil and valid(o) then SPC.V.assets[full] = o; return o end
    return nil, why
end
-- what she loads at her opener and her reveal: { path, object }, each once (her X-02S and its sweep, her paint variant's
-- materials and textures, her railgun's round class, her opener's lens flash, its shot's flash, her blinks' smoke);
-- on a co-op joiner (client) only her X-02S and paint: the rest is the host's (COOP.valkaTick puts the model on its copy)
function SPC.V.preloadList(c, client)
    local V, out, seen = SPC.V, {}, {}
    local function add(path, obj)
        if type(path) ~= "string" or path == "" or path:sub(1, 3) == "rt:" then return end
        local full = path .. "." .. (obj or path:match("[^/]+$"))
        if not seen[full] then seen[full] = true; out[#out + 1] = { path = path, obj = obj } end
    end
    if c.model and c.model ~= "" then
        add(c.model)
        add(c.sweep_anim)
        local pv = V.PAINTS[(((tonumber(c.paint) or 2) - 1) % #V.PAINTS) + 1]
        if pv.parent then
            add(pv.parent)
            for slot, p in pairs(V.PAINT_OWN) do if not (pv.flat_normal and slot == "Normalmap") then add(p) end end
            for _, p in pairs(pv.tex or {}) do add(p) end
        elseif pv.material then add(pv.material)
        elseif pv.stock then add(V.PAINT_STOCK) end
        for _, k in ipairs({ "dirt", "livemap", "basecolor", "normal" }) do if pv[k] then add(V.PAINT_TEX[pv[k]]) end end
    end
    if client then return out end
    if c.eml_weapon and c.eml_weapon ~= "" then add(c.eml_weapon, c.eml_weapon:match("[^/]+$") .. "_C") end
    add(c.flash); add(c.smoke)                          -- (her opener shot's flash, her blinks' smoke: fxAt)
    local f = c.flare
    if type(f) == "table" and f.enabled and type(f.path) == "string" then
        for _, e in ipairs(f.elements or {}) do add(f.path .. e[1]) end
    end
    return out
end
-- Loaded in the break before her round, one a tick, as her sounds are (SND.preloadValka's moments, below: the NEXT
-- announcement, her round's start, the host's VALKA round on a joiner; her lurk drains it too). Each /Game/ asset is
-- kept loaded (pin: GameInstance.ReferencedObjects, as the Anomaly's sounds; an asset's outer is its package, never a
-- level's object). Again any time it's asked (at most every 10 s) for what isn't kept any more.
SPC.V.PRE = { q = nil, at = nil, n = 0, total = 0, ms = 0, worst = 0, worstWhat = nil, failed = 0, wrapped = false }
function SPC.V.preload()
    local c = CFG.specials and CFG.specials.valka
    if type(c) ~= "table" or c.enabled == false then return false end
    local P = SPC.V.PRE
    if P.q then return false end                                  -- (loading)
    local now = os.clock()
    if P.at and now >= P.at and now - P.at < 10 then return false end   -- (asked lately: "rnd" asks often on a joiner)
    P.at = now
    local q = {}
    local okC, client = pcall(function() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end)
    for _, a in ipairs(SPC.V.preloadList(c, okC and client)) do
        local o = SPC.V.assets[a.path .. "." .. (a.obj or a.path:match("[^/]+$"))]
        if not (o ~= nil and liveObj(o)) then q[#q + 1] = a end
    end
    if #q == 0 then return false end
    P.q, P.n, P.total, P.ms, P.worst, P.worstWhat, P.failed = q, 0, #q, 0, 0, nil, 0
    log(string.format("special: VALKA's X-02S, paint, railgun round, flare and flash: %d assets loading, one a tick, before her fight", #q))
    return true
end
function SPC.V.preTick()
    local P = SPC.V.PRE
    local q = P.q
    if not q then return end
    if (levelTorn and levelTorn()) or (walkHold and walkHold()) then return end   -- (not while a level comes or goes)
    local a = table.remove(q, 1)
    if a then
        local what = a.obj or a.path:match("[^/]+$")
        local t0 = os.clock()
        local o, why = SPC.V.asset(a.path, a.obj)
        local ms = (os.clock() - t0) * 1000
        P.ms = P.ms + ms
        if ms > P.worst then P.worst, P.worstWhat = ms, what end
        if o then
            P.n = P.n + 1
            if a.path:sub(1, 6) == "/Game/" and type(pin) == "function" then pcall(pin, o, "VALKA's " .. what) end
        else
            P.failed = P.failed + 1
            log(string.format("special: VALKA's %s not loaded before her fight (%s): loaded when she needs it", what, tostring(why)))
        end
    end
    if #q == 0 then
        P.q = nil
        log(string.format("special: VALKA's assets loaded before her fight: %d of %d, %.0f ms in all, worst %.0f ms (%s)",
            P.n, P.total, P.ms, P.worst, tostring(P.worstWhat)))
    end
end
local function paintTex(k)
    local p = SPC.V.PAINT_TEX[k]
    return p and SPC.V.asset(p)                         -- ((0.73.80) kept: SPC.V.asset)
end
-- (0.73.76) a flat colour as a texture, "rt:R,G,B" (0-1, linear): a 4x4 render target cleared to it, made once a
-- colour (the user's screenshot of 00:22: black blotches on her body; AC8's T_Livemap isn't flat, 111 of its 256 DXT1
-- blocks differ, so its pattern landed on her UVs; the Falken add-on gives its body a flat 4x4 Livemap, 0 / 0.75 / 1:
-- no metal, roughness 0.75, unshadowed). Nil if it can't be made.
SPC.V.flatTex = {}
local function flatTexture(spec)
    local t = SPC.V.flatTex[spec]
    if t ~= nil and liveObj(t) then return t end        -- ((0.73.80) liveObj: kept between her rounds, valid() reads a freed one)
    local r, g, b = spec:match("^rt:([%d%.]+),([%d%.]+),([%d%.]+)$")
    if not r then return nil end
    local krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    if not valid(krl) then return nil end
    local col = { R = tonumber(r), G = tonumber(g), B = tonumber(b), A = 1 }
    local ok, rt = pcall(function() return krl:CreateRenderTarget2D(survivalPC, 4, 4, 2, col, false, false) end)   -- (2: RTF_RGBA8, linear)
    if not (ok and valid(rt)) then log("special: VALKA's paint: a flat texture " .. spec .. " couldn't be made (" .. tostring(rt) .. ")"); return nil end
    pcall(function() krl:ClearRenderTarget2D(survivalPC, rt, col) end)
    SPC.V.flatTex[spec] = rt
    return rt
end

-- name -> value of a material instance's own scalar / vector overrides
local function paintValues(mi)
    local sc, ve = {}, {}
    pcall(function()
        mi.ScalarParameterValues:ForEach(function(_, e)
            local v = e:get()
            sc[v.ParameterInfo.Name:ToString()] = v.ParameterValue
        end)
    end)
    pcall(function()
        mi.VectorParameterValues:ForEach(function(_, e)
            local v = e:get()
            local q = v.ParameterValue
            ve[v.ParameterInfo.Name:ToString()] = { R = q.R, G = q.G, B = q.B, A = q.A }
        end)
    end)
    return sc, ve
end
-- variant k on her body (fresh dynamic instances each time, so one variant never carries into the next); its name
function SPC.V.paint(c, s, body, k)
    local V = SPC.V
    k = ((k - 1) % #V.PAINTS) + 1
    local pv = V.PAINTS[k]
    s.paintK = k
    if not s.paintSlots then                            -- her MI_X02S_Valka slots and that material
        s.paintSlots = {}
        pcall(function()
            for i = 0, body:GetNumMaterials() - 1 do
                local m = body:GetMaterial(i)
                if valid(m) and nameOf(m):find("MI_X02S_Valka", 1, true) then
                    s.paintSlots[#s.paintSlots + 1] = i
                    s.paintMI = s.paintMI or m
                end
            end
        end)
    end
    if not s.paintMI then
        log(string.format("special: %s's paint: no MI_X02S_Valka slot on %s", c.name, nameOf(body)))
        return pv.name
    end
    if not s.paintOrig then                             -- every slot's own material (the canopy's too), to go back to
        s.paintOrig, s.paintN = {}, 0
        pcall(function()
            s.paintN = body:GetNumMaterials()
            for i = 0, s.paintN - 1 do s.paintOrig[i] = body:GetMaterial(i) end
        end)
    end
    for i = 0, (s.paintN or 0) - 1 do                   -- (the grid variant changes every slot)
        if valid(s.paintOrig[i]) then pcall(function() body:SetMaterial(i, s.paintOrig[i]) end) end
    end
    if pv.parent then                                   -- another AC8 master, her textures on it
        local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local parent, why = V.asset(pv.parent)          -- ((0.73.80) kept from the break's preload, as every load below)
        local okM, mid = false, nil                     -- (not `valid(parent) and pcall(...)`: `and` keeps one value)
        if valid(parent) and valid(kml) then
            okM, mid = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, parent, FName("None"), 0) end)
        end
        if not (okM and valid(mid)) then
            log(string.format("special: %s's paint %d %s: no instance of %s (%s)", c.name, k, pv.name, pv.parent,
                tostring(valid(parent) and mid or why)))
            return pv.name
        end
        local set = {}
        for slot, path in pairs(V.PAINT_OWN) do
            if not (pv.flat_normal and slot == "Normalmap") then
                local t = V.asset(path)
                local ok = valid(t) and pcall(function() mid:SetTextureParameterValue(FName(slot), t) end)
                set[#set + 1] = slot .. (ok and "" or " NOT set")
            end
        end
        if pv.flat_normal then set[#set + 1] = "its own flat normal" end
        local live = pv.livemap and paintTex(pv.livemap)
        if live then pcall(function() mid:SetTextureParameterValue(FName("Livemap"), live) end) end
        for slot, path in pairs(pv.tex or {}) do        -- (0.73.76) more textures by path (the gear variants), or a flat "rt:R,G,B"
            local t = path:sub(1, 3) == "rt:" and flatTexture(path) or V.asset(path)
            local ok = false
            if valid(t) then ok = pcall(function() mid:SetTextureParameterValue(FName(slot), t) end) end
            set[#set + 1] = slot .. " " .. path:match("[^/]+$") .. (ok and "" or " NOT set")
        end
        for n, v in pairs(pv.scalars or {}) do          -- (0.73.76) scalar values (the gear variants)
            local ok = pcall(function() mid:SetScalarParameterValue(FName(n), v) end)
            set[#set + 1] = string.format("%s %g%s", n, v, ok and "" or " NOT set")
        end
        local n = 0
        for _, i in ipairs(s.paintSlots) do
            if pcall(function() body:SetMaterial(i, mid) end) then n = n + 1 end
        end
        log(string.format("special: %s's paint %d %s: %d slots on %s, %s%s", c.name, k, pv.name, n, pv.parent:match("[^/]+$"),
            table.concat(set, ", "), pv.livemap and (", Livemap " .. pv.livemap .. (live and "" or " NOT loaded")) or ", its own Livemap"))
        return pv.name
    end
    if pv.material then
        local m, why = V.asset(pv.material)
        local n = 0
        for i = 0, (s.paintN or 0) - 1 do
            if valid(m) and pcall(function() body:SetMaterial(i, m) end) then n = n + 1 end
        end
        log(string.format("special: %s's paint %d %s: %d of %d slots%s", c.name, k, pv.name, n, s.paintN or 0,
            valid(m) and "" or (" (" .. pv.material .. " not loaded: " .. tostring(why) .. ")")))
        return pv.name
    end
    local sc, ve, nStock = {}, {}, 0
    if pv.stock then
        local stock, why = V.asset(V.PAINT_STOCK)
        if valid(stock) then sc, ve = paintValues(stock) else
            log(string.format("special: %s's paint: %s not loaded (%s)", c.name, V.PAINT_STOCK, tostring(why)))
        end
    end
    local dirt, live = pv.dirt and paintTex(pv.dirt), pv.livemap and paintTex(pv.livemap)
    local base, nrm = pv.basecolor and paintTex(pv.basecolor), pv.normal and paintTex(pv.normal)
    local said, made = {}, 0
    for _, i in ipairs(s.paintSlots) do
        local okM, mid = pcall(function() return body:CreateDynamicMaterialInstance(i, s.paintMI, FName("None")) end)
        if okM and valid(mid) then
            made = made + 1
            if not s.paintSaid then                      -- the parent's values, once
                s.paintSaid = true
                for _, n in ipairs(V.PAINT_SAY) do
                    local okV, v = pcall(function() return mid:K2_GetScalarParameterValue(FName(n)) end)
                    said[#said + 1] = string.format("%s %s", n, okV and string.format("%.3g", v) or "?")
                end
            end
            nStock = 0
            for n, v in pairs(sc) do
                if pcall(function() mid:SetScalarParameterValue(FName(n), v) end) then nStock = nStock + 1 end
            end
            for n, v in pairs(ve) do
                if pcall(function() mid:SetVectorParameterValue(FName(n), v) end) then nStock = nStock + 1 end
            end
            if dirt then pcall(function() mid:SetTextureParameterValue(FName("DirtMask"), dirt) end) end
            if live then pcall(function() mid:SetTextureParameterValue(FName("Livemap"), live) end) end
            if base then pcall(function() mid:SetTextureParameterValue(FName("Basecolor"), base) end) end
            if nrm then pcall(function() mid:SetTextureParameterValue(FName("Normalmap"), nrm) end) end
        end
    end
    if made == 0 then                                   -- (no instances: the slots back as built)
        for _, i in ipairs(s.paintSlots) do pcall(function() body:SetMaterial(i, s.paintMI) end) end
    end
    if #said > 0 then log(string.format("special: %s's paint: the parent's values: %s", c.name, table.concat(said, ", "))) end
    log(string.format("special: %s's paint %d %s: %d slots, %d stock values%s%s", c.name, k, pv.name, made, nStock,
        pv.dirt and (", dirt mask " .. pv.dirt .. (dirt and "" or " NOT loaded")) or "",
        pv.livemap and (", Livemap " .. pv.livemap .. (live and "" or " NOT loaded")) or "") ..
        (pv.basecolor and (", Basecolor " .. pv.basecolor .. (base and "" or " NOT loaded")) or "") ..
        (pv.normal and (", Normalmap " .. pv.normal .. (nrm and "" or " NOT loaded")) or ""))
    return pv.name
end
-- no skeletal body of her own (the x40a's isn't one: test of 2026-10-24, 0.66.0, only the wreck meshes were skeletal
-- and 3 other meshes got hidden): a skeletal mesh component of ours added to her (AActor::AddComponentByClass, on her
-- root), no collision (her own spheres still take the hits), placed where her body mesh is (any PlaneBody* one) and
-- turned model_yaw more. Returns it and how it was placed, or nil and why not.
function SPC.V.addBody(c, o)
    local cls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    if not valid(cls) then return nil, "no SkeletalMeshComponent class" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, comp = pcall(function() return o:AddComponentByClass(cls, false, t, false) end)
    if not ok or not comp or not valid(comp) then
        return nil, "AddComponentByClass " .. (ok and "gave nothing" or tostring(comp))
    end
    pcall(function() comp:SetCollisionEnabled(0) end)      -- (ECollisionEnabled NoCollision)
    local yaw = c.model_yaw or 0
    local ref, by = nil, "her root"
    for _, n in ipairs(SPC.V.BODY_PROPS) do
        local okP, p = pcall(function() return o[n] end)
        if okP and p and valid(p) and addrOf(p) ~= addrOf(comp) then ref, by = p, n; break end
    end
    local placed
    if ref then
        placed = pcall(function()
            local l, r = ref:K2_GetComponentLocation(), ref:K2_GetComponentRotation()
            comp:K2_SetWorldLocationAndRotation({ X = l.X, Y = l.Y, Z = l.Z },
                { Pitch = r.Pitch, Yaw = r.Yaw + yaw, Roll = r.Roll }, false, {}, true)
        end)
    else
        placed = pcall(function()
            comp:K2_SetRelativeLocationAndRotation({ X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = yaw, Roll = 0 }, false, {}, true)
        end)
    end
    return comp, string.format("placed by %s%s, yaw +%d", by, placed and "" or " (NOT placed)", yaw)
end
function SPC.V.model(c, s, o)
    if not c.model or c.model == "" or s.modelComp then return s.modelComp ~= nil end
    local function load(path) return SPC.V.asset(path) end    -- ((0.73.80) kept from the break's preload: SPC.V.preload)
    local sk, why = load(c.model)
    local anim, whyAnim = nil, "no sweep_anim"
    if c.sweep_anim and c.sweep_anim ~= "" then anim, whyAnim = load(c.sweep_anim) end
    if not valid(sk) then
        log(string.format("special: %s's X-02S %s not loaded (%s); the x40a shows", c.name, c.model, tostring(why)))
        return false
    end
    -- her body: the plane's own body mesh (its PlaneBody* property, as glitchDeadLook finds it), else the biggest
    -- skeletal mesh in her tree that isn't a wreck mesh (test of 2026-10-24, 0.66.0: the tree held only
    -- DamagedMainBodyMesh / DamagedPartsMesh, the X-02S went on the wreck one, which never draws: hard rule 41)
    local body, best, names = nil, -1, {}
    local skel = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    for _, n in ipairs(SPC.V.BODY_PROPS) do
        local ok, comp = pcall(function() return o[n] end)
        if ok and comp and valid(comp) then
            local okC, cls = pcall(function() return comp:GetClass():GetFName():ToString() end)
            local isSkel = pcall(function() assert(comp:IsA(skel)) end)
            names[#names + 1] = string.format("%s=%s%s", n, okC and cls or "?", isSkel and "" or " (not skeletal)")
            if isSkel and not body then body, best = comp, 1e12 end
        end
    end
    for _, comp in ipairs(SPC.V.comps(o, "/Script/Engine.SkeletalMeshComponent")) do
        local nm = nameOf(comp):match("([%w_]+)$") or "?"
        names[#names + 1] = nm
        local okB, r = pcall(function() return comp.Bounds.SphereRadius end)
        local size = (okB and type(r) == "number" and r) or 0
        if not nm:find("^Damaged") and size > best then body, best = comp, size end
    end
    local added, whyAdd = false, nil
    if not valid(body) then
        body, whyAdd = SPC.V.addBody(c, o)
        added = valid(body)
    end
    if not valid(body) then
        local all = {}
        for _, comp in ipairs(SPC.V.comps(o, "/Script/Engine.ActorComponent")) do
            all[#all + 1] = (nameOf(comp):match("([%w_]+)$") or "?") .. ":" .. (pcall(function() return comp:GetClass():GetFName():ToString() end) and comp:GetClass():GetFName():ToString() or "?")
        end
        log(string.format("special: %s has no skeletal mesh component and none could be added (%s); her tree: %s; the x40a shows",
            c.name, tostring(whyAdd), #all > 0 and table.concat(all, ", ") or "nothing (no RootComponent?)"))
        return false
    end
    local okM = pcall(function() body:SetSkeletalMeshAsset(sk) end) or pcall(function() body:SetSkeletalMesh(sk, true) end)
    if not okM then
        log(string.format("special: %s's X-02S mesh not set on %s; the x40a shows", c.name, nameOf(body)))
        return false
    end
    SPC.V.cur = s
    SPC.V.paint(c, s, body, c.paint or 2)
    local k = (c.model_length_m or 19.6) / 19.6
    if k ~= 1 then pcall(function() local v = body.RelativeScale3D; body:SetRelativeScale3D({ X = v.X * k, Y = v.Y * k, Z = v.Z * k }) end) end
    local okA, errA = false, "not loaded: " .. tostring(whyAnim)
    if valid(anim) then
        okA, errA = pcall(function()
            body:SetAnimationMode(1, true)                                  -- (EAnimationMode AnimationSingleNode)
            body:SetAnimation(anim)
            body:SetPlayRate(0)
            body:Play(false)
            body:SetPosition(0, false)
        end)
    end
    s.modelComp, s.sweepPos = body, 0
    s.sweepLen = okA and (pcall(function() return anim:GetPlayLength() end) and anim:GetPlayLength() or 1) or nil
    local hid = SPC.V.modelHide(s, o)
    SPC.V.partsGone(c, s, o, true)
    log(string.format("special: %s's railguns moved onto her: %d parts", c.name, SPC.V.partsPlace(c, s, o)))
    -- her hit spheres from the x40a's size to the X-02S's (hit_radius_m), each logged once
    local spheres = {}
    for _, sc in ipairs(SPC.V.comps(o, "/Script/Engine.SphereComponent")) do
        local nm = nameOf(sc):match("([%w_]+)$") or "?"
        if not nm:find("^Damaged") then                 -- (DamagedCollision is her wreck's: 0.66.0 shrank it)
            local okR, r = pcall(function() return sc:GetUnscaledSphereRadius() end)
            if valid(sc) and okR and type(r) == "number" and c.hit_radius_m and r > c.hit_radius_m * 100 then
                pcall(function() sc:SetSphereRadius(c.hit_radius_m * 100, true) end)
                spheres[#spheres + 1] = string.format("%s %.0f -> %.0f m", nm, r / 100, c.hit_radius_m)
            elseif valid(sc) and okR then
                spheres[#spheres + 1] = string.format("%s %.0f m (kept)", nm, (r or 0) / 100)
            end
        end
    end
    log(string.format("special: %s's hit spheres: %s", c.name, #spheres > 0 and table.concat(spheres, ", ") or "none found"))
    s.modelOwner = o
    log(string.format("special: %s flies the X-02S (%s on %s%s of %s; sweep %s%s): %d other meshes hidden, %d parts gone",
        c.name, c.model:match("[^/]+$"), nameOf(body):match("([%w_]+)$") or "?",
        added and (" (added; " .. tostring(whyAdd) .. ")") or "", #names > 0 and table.concat(names, ", ") or "none",
        okA and "on" or "OFF",
        okA and string.format(" %.0f-%.0f km/h", c.sweep_kmh[1], c.sweep_kmh[2]) or (" (" .. tostring(errA) .. ")"),
        hid, #(s.parts or {})))
    return true
end
-- her other meshes (the x40a's, not the X-02S's body) hidden; how many it hid this time. (Her named body / pilot
-- meshes too: they needn't be in the tree SPC.V.comps walks.)
function SPC.V.modelHide(s, o)
    local n, me, seen = 0, addrOf(s.modelComp), {}
    local function hide(comp)
        local a = valid(comp) and addrOf(comp)
        if not a or a == me or seen[a] then return end
        seen[a] = true
        local okV, vis = pcall(function() return comp:IsVisible() end)
        if okV and vis and pcall(function() comp:SetVisibility(false, false) end) then n = n + 1 end
    end
    for _, cls in ipairs({ "/Script/Engine.StaticMeshComponent", "/Script/Engine.SkeletalMeshComponent" }) do
        for _, comp in ipairs(SPC.V.comps(o, cls)) do hide(comp) end
    end
    for _, k in ipairs({ "PilotMeshComponent", table.unpack(SPC.V.BODY_PROPS) }) do
        local ok, comp = pcall(function() return o[k] end)
        if ok and comp then hide(comp) end
    end
    return n
end
-- every tick: the wings towards their sweep for her speed (played, so it's smooth between ticks); every 2 s the
-- x40a's meshes hidden again
function SPC.V.modelTick(s, o, now)
    local c, body = CFG.specials.valka, s.modelComp
    if not valid(body) then return end
    if s.sweepLen then
        local okV, v = pcall(function() local q = o:GetVelocity(); return math.sqrt(q.X ^ 2 + q.Y ^ 2 + q.Z ^ 2) * 0.036 end)
        local lo, hi = c.sweep_kmh[1], c.sweep_kmh[2]
        local want = okV and math.max(0, math.min(1, (v - lo) / math.max(1, hi - lo))) * s.sweepLen or 0
        pcall(function()
            local cur = body:GetPosition()
            local d = want - cur
            if math.abs(d) < 0.02 * s.sweepLen then
                body:SetPlayRate(0)
            else
                body:SetPlayRate((d > 0 and 1 or -1) / math.max(0.1, c.sweep_s))
                if not body:IsPlaying() then body:Play(false) end
            end
            s.sweepPos = cur / s.sweepLen
        end)
    end
    if now < (s.modelAt or 0) then return end
    s.modelAt = now + 2
    SPC.V.partsPlace(c, s, o)
    local n = SPC.V.modelHide(s, o)
    if n > 0 and not s.modelSaid then
        s.modelSaid = true
        log("special: VALKA: " .. n .. " of the x40a's meshes came back on and were hidden again")
    end
end

-- The opener's dummy railgun (AC7's ms18_dummy_eml_p1; tools/survival_events.py VALKA_EML_*): spawned once on the
-- horizon ahead of you (user, 2026-10-24: "always spawns on the horizon, not up in the sky or anything weird"): along
-- your heading, level with you (your pitch left out), at least opener_min_alt_m up, facing you, and fixed there; it
-- never follows you. opener_km is its distance at the shot: it spawns further out by what you'll fly towards it
-- through the charge (your level speed along your heading x (charge_s + 1 s for the spawn), at most opener_max_km;
-- test of 2026-10-24: spawned 9 km out, the player was 4.8 km from it at the shot), and nearer when the combat zone's
-- edge comes first (still straight ahead). Its actor comes through the LiveAIGameObject hook (SPC.V.emlActor).
-- Returns the point and its yaw, or nil.
function SPC.V.emlSpawn(c)
    local pawn = valid(survivalPC) and survivalPC.Pawn
    local you = playerLocation()
    local h = SPC.V.heading()
    if not pawn or not you or not h or type(SV_Spawn) ~= "function" then return nil end
    local f = { X = math.cos(math.rad(h)), Y = math.sin(math.rad(h)) }
    if c.opener_bearing then                            -- a fixed compass bearing (north -Y, east +X: Mission 22's
        local b = math.rad(c.opener_bearing)            -- dummyN0 / dummyS0 sit at Y -650 / +650 km)
        f = { X = math.sin(b), Y = -math.cos(b) }
        h = math.deg(math.atan(f.Y, f.X))
    end
    local okV, v = pcall(function() local q = pawn:GetVelocity(); return { X = q.X, Y = q.Y } end)
    local closing = okV and math.max(0, v.X * f.X + v.Y * f.Y) or 0                 -- cm/s towards it
    local want = math.min(c.opener_km * 100000 + closing * (c.charge_s + 1), (c.opener_max_km or 30) * 100000)
    local edge = ZONE.HALF * 0.95                        -- (the zone's edge first: nearer, still on its bearing)
    local function room(dir)
        local d = want
        for _, k in ipairs({ "X", "Y" }) do
            local lim = dir[k] > 0.001 and (ZONE[k] + edge - you[k]) / dir[k] or dir[k] < -0.001 and (ZONE[k] - edge - you[k]) / dir[k]
            if lim then d = math.min(d, math.max(0, lim)) end
        end
        return d
    end
    local d = room(f)
    if d < want * 0.5 then                               -- (near the zone's edge that way: code review of 2026-10-25,
        local best, bestD = f, d                        -- it spawned ~1 km from you) the bearing with the most room
        for deg = 0, 315, 45 do
            local g = { X = math.sin(math.rad(deg)), Y = -math.cos(math.rad(deg)) }
            local gd = room(g)
            if gd > bestD then best, bestD = g, gd end
        end
        if best ~= f then
            log(string.format("special: %s's opener: only %.1f km of room on its bearing; one with %.1f km instead", c.name,
                d / 100000, bestD / 100000))
        end
        f, d = best, bestD
        h = math.deg(math.atan(f.Y, f.X))
    end
    local at = { X = you.X + f.X * d, Y = you.Y + f.Y * d, Z = math.max(you.Z, c.opener_min_alt_m * 100) }
    local yaw = (h + 180) % 360
    SPC.V.emlActor = nil
    SPC.V.modMark(c.eml_unit)
    spawningUnit = c.eml_unit
    local r = SV_Spawn(c.eml_unit, at.X, at.Y, at.Z, yaw)
    spawningUnit = nil
    SPC.V.modRecord()                                   -- ((0.73.80) its modules kept as they're made, not walked for)
    at.km = math.sqrt((at.X - you.X) ^ 2 + (at.Y - you.Y) ^ 2 + (at.Z - you.Z) ^ 2) / 100000
    log(string.format("special: %s's railgun %s %.1f km out on the horizon (%s, world yaw %.0f, %.1f km up, you closing at %.0f km/h)",
        c.name, r > 0 and "up" or ("NOT up (" .. (SV_ERR[r] or tostring(r)) .. ")"), at.km,
        c.opener_bearing and string.format("compass bearing %.0f", c.opener_bearing) or "ahead of you", h, at.Z / 100000,
        closing * 0.036))
    if r <= 0 then return nil end
    return at, yaw
end

-- Her round's start (the spawn queue's "@valka"): disguised, she waits ("lurk") for the round's decoy fighters to go
-- down (SPC.valkaTick starts her opener then); else the opener starts now. False if she can't come.
function SPC.valkaSpawn(now)
    local c = CFG.specials.valka
    if not SR.usable[ACE.row("valka", "x40a", "l")] then
        log("special: VALKA's row wasn't in before this level loaded; a normal round instead")
        return false
    end
    D.special.state, D.special.at = "lurk", now
    SPC.V.modReset()                                    -- ((0.73.80) this round's railgun modules kept afresh)
    pcall(SPC.V.preload)                                -- ((0.73.80) her assets, if the break didn't load them: her lurk does)
    -- the WARNING from her round's start until she's down (user, 2026-10-24: "the warning stays on for that entire
    -- round until VALKA is killed"; her attack's events set it again, SV_ValkaDown / RE_SV_ValkaEnd switch it off)
    SPC.V.event("RE_SV_ValkaWarnOn")
    if c.disguise then
        log(string.format("special: round %d is VALKA's, called out as a normal round; she attacks once its fighters are down",
            D.round))
    else
        D.special.clearAt = now                         -- (no decoys: her opener straight away)
    end
    return true
end

-- VALKA on her ace row (the x40a and its railguns) at the top fire-control level, at `at` ({ X, Y, Z } cm: where
-- her railgun fired from) facing `yaw`, or spawn_km from you when there's no opener; shown at once (her reveal). False
-- if she can't come.
function SPC.valkaArrive(now, at, yaw)
    local c = CFG.specials.valka
    local row = ACE.row("valka", "x40a", "l")
    local x, y, _, bearing = spawnPoint()
    local px, py, pb, pd = ANOM.nearPlayer(c.spawn_km)
    if px then x, y, bearing = px, py, pb end
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local z, heading = alt * 100, (bearing + 180) % 360
    if at then x, y, z, heading, pd = at.X, at.Y, at.Z, yaw, at.km end
    local set = SV_SetAircraft(c.unit, searchAircraft(row, #SPIKE_SUFFIX))
    if type(SV_SetLevel) == "function" then SV_SetLevel(c.unit, c.ai_level * 100) end
    -- ((0.73.80) her railgun round's class default: her damage back before her own railguns are made, life and single
    -- rounds as the opener's; her railguns' modules kept as they're made. (review of 0.73.80) With an opener (at), not
    -- yet: its round may be made after the railgun's spin-up, past her reveal; valkaTick puts it back at s.harmUntil)
    if not at then pcall(SPC.V.roundDefaults, c, "hers") end
    SPC.V.modMark(c.unit)
    spawningUnit = c.unit
    local r = SV_Spawn(c.unit, x, y, z, heading)
    spawningUnit = nil
    SPC.V.modRecord()
    log(string.format("special: VALKA as %s (%s set), %s, heading %.0f, %.1f km up: %s", row, tostring(set),
        pd and string.format("%.1f km from you", pd) or "at a spawn point", heading or -1, z / 100000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r <= 0 then return false end
    D.flightTier = D.flightTier or {}
    D.up[c.unit], D.flown[c.unit], D.flightTier[c.unit] = true, true, #CFG.tiers.list
    D.special.state, D.special.at = "fired", now
    return true
end

-- (0.73.76) Her round's mood, once: the screen fading to red (hudRed) and the song (SND.songStart, CFG.specials.valka.
-- song) together, as the round's flying enemies are all down (user, 2026-11-02: "make sure that the red begins to fade
-- after the enemies that fly in the round are dead"); both fade out after her death (moodOff).
function SPC.V.mood(c, s)
    if s.moodOn then return end
    s.moodOn = true
    -- (0.73.76) every joiner's too; (0.73.77, plan D1) told first, and this game's sky in a pcall: an error there left
    -- moodOn set and the joiners never told (sv_coop.lua's M.valkaWatch holds them to moodOn as well)
    if COOP and COOP.valkaMood then pcall(COOP.valkaMood, true) end
    if c.red and c.red.enabled ~= false then s.redOn = true; pcall(hudRed, true, c.red) end
    pcall(SND.songStart, c.song)
end
function SPC.V.moodOff(c, s, now)
    if s.moodOn and COOP and COOP.valkaMood then pcall(COOP.valkaMood, false) end   -- (0.73.76) every joiner's too ((0.73.77) first)
    if s.redOn then s.redOn = false; pcall(hudRed, false, nil, c == nil) end        -- (a cleanup: the sky back at once)
    if c then pcall(SND.songFade, c.song and c.song.out_s or 5) else pcall(SND.songStop) end
    s.moodOn = false
end

-- ((2026-11-07) her round's subtitles, CFG.specials.valka.text.say: the user, Valka "has outbursts where she becomes the
-- full anomaly version of herself (the X-02S anomaly)"; AUDREY breaking in on the radio partway through) what's under
-- `key` said (sv_escort_subs.lua ESUB.say: one exchange, whole); `charlene`: only once CHARLENE's at Comona this run
function SPC.V.subs(c, key, charlene)
    local say = c.text and c.text.say
    if not (type(say) == "table" and say[key] and ESUB and ESUB.say) then return false end
    if charlene and not (RUN and type(RUN.escort) == "table" and RUN.escort.arrived) then return false end
    local ok, said = pcall(ESUB.say, nil, "valka." .. key, nil, { list = say[key], force = true })
    if ok and said then log("special: " .. c.name .. "'s round: " .. key .. " said (subtitles)") end
    return ok and said == true
end
-- AUDREY at her health under each hurt_at mark (once each a round)
function SPC.V.subsHealth(c, s, o)
    local say = c.text and c.text.say
    if not (type(say) == "table" and type(say.hurt_at) == "table") then return end
    local okH, h, mh = pcall(function() return o.HealthInternal, o.MaxHealth end)
    if not (okH and type(h) == "number" and type(mh) == "number" and mh > 0) then return end
    local pct = h / (mh * 10) * 100
    s.subsMark = s.subsMark or {}
    for _, m in ipairs(say.hurt_at) do
        m = math.floor(tonumber(m) or 0)
        if pct <= m and not s.subsMark[m] then
            s.subsMark[m] = true
            SPC.V.subs(c, "audrey_" .. m)
            return                                       -- (one mark a tick: a big hit past two says the first)
        end
    end
end

-- Every tick of VALKA's round.
function SPC.valkaTick(now, s)
    local c, t, V = CFG.specials.valka, CFG.hud.text, SPC.V
    V.flareTick(c, s, now)
    -- ((0.73.80) no walk for her rounds after a shot any more (every tick for 3-3.5 s, none ever found in the 31-round
    -- run): their life, single rounds and the opener's no-damage are on the round's class default, SPC.V.roundDefaults)
    if s.alertOffAt and now >= s.alertOffAt then        -- the railgun alert off again after a shot
        s.alertOffAt = nil
        if not s.chargeAt then V.event("RE_SV_ValkaAlertOff") end
    end
    if s.harmUntil and now >= s.harmUntil then          -- ((review of 0.73.80) the opener's round flown: her damage back
        s.harmUntil = nil                               -- (not once she's done: "off" ran then, and stays)
        if s.state ~= "done" then pcall(V.roundDefaults, c, "hers"); pcall(V.roundsHarm, c) end
    end
    if s.passAt and now >= s.passAt then                -- her round passing you (its sound)
        s.passAt = nil
        SND.event(CFG.sound.valka.pass, nil)
    end
    if s.emlRemoveAt and now >= s.emlRemoveAt then      -- her railgun's gone eml_remove_s after its shot
        s.emlRemoveAt = nil
        V.event("RE_SV_ValkaEmlRemove")
        -- ((0.73.77) D4: that event's LiveDestroyUnitExecution never took it down (invincible from setGone: "1 of 1
        -- aircraft alive" to the end of every run, its box on, firing at players near the base): its minimap display
        -- off, then finished off by Lua, SV_UnitAlive asked 2 s on: `special: VALKA's opener railgun removed` / NOT)
        if liveObj(V.emlActor) then pcall(V.radarOff, addrOf(V.emlActor)) end
        if SPC.cleanUp then
            local okC, errC = pcall(SPC.cleanUp, { c.eml_unit }, string.format("%.0f s after its shot", c.eml_remove_s or 4), true, now)
            if not okC then log("special: VALKA's opener railgun: clean-up error " .. tostring(errC)) end
        end
        V.emlActor = nil
    end
    if s.state == "lurk" then                           -- the decoys first: lurk_s after the last is down, the opener
        if not V.PRE.wrapped then pcall(V.preTick) end  -- ((0.73.80) her assets, one a tick, if SND.tick doesn't load them)
        if D.state ~= "fighting" then return end
        if c.disguise then
            for u in pairs(D.up) do if SV_UnitAlive(u) > 0 then s.clearAt = nil; return end end
            s.clearAt = s.clearAt or now + c.lurk_s
        end
        V.mood(c, s)                                    -- (0.73.76) the flyers down (or none): red and her song
        if now < (s.clearAt or now) then return end
        s.emlAt, s.emlYaw = V.emlSpawn(c)
        if not s.emlAt then                             -- no railgun: she comes as she is, the reveal without the shot
            log(string.format("special: %s's railgun couldn't spawn; she comes without the opener", c.name))
            V.event("RE_SV_ValkaWarnOn")
            if not SPC.valkaArrive(now) then
                s.state = "done"
                V.event("RE_SV_ValkaEnd")               -- (the WARNING off)
                pcall(V.roundDefaults, c, "off")         -- ((0.73.80) her round class as it was)
                log(string.format("special: %s couldn't spawn; the round ends", c.name))
            end
            return
        end
        s.state, s.openAt, s.chargeAt = "opener", now, nil
        return
    end
    local you = playerLocation()
    if s.state == "opener" then                         -- the railgun found and hidden, the flash, the charge, the shot
        local e = V.emlActor
        if not s.chargeAt then
            if not valid(e) then
                if now - s.openAt < c.arrive_s + 3 then return end
                log(string.format("special: %s's railgun actor not found %.0f s after it spawned; the opener goes on unseen",
                    c.name, now - s.openAt))
            else
                setGone(e, true)
                SPC.V.mark(c, e)
            end
            V.modSaid(c, c.eml_unit, "her opener's")   -- ((0.73.80) kept as the game made them: no walk)
            local n, why = V.singleShot(c)
            log(string.format("special: %s's railguns single-shot: %d launcher modules%s", c.name, n, why and (" (" .. why .. ")") or ""))
            pcall(V.roundDefaults, c, "opener")          -- ((0.73.80) her round's life, single rounds, no damage: its class default)
            local nW, whyW = V.emlWeapon(c)
            log(string.format("special: %s's railgun rounds: %d on %s (%s)", c.name, nW, tostring(c.eml_weapon), whyW))
            log(string.format("special: %s's railguns on the minimap: %d launchers (style %d)", c.name, V.radar(c), c.radar_hud or 1))
            V.event("RE_SV_ValkaAlertOn")
            s.chargeAt = now + c.charge_s
            V.event("RE_SV_ValkaWarnOn")                -- WARNING until she's down (no banner of ours: no tells)
            V.event("RE_SV_ValkaEmlChargeOn")
            V.sndCharge(s, s.emlAt, now)
            local fx = V.flareStart(c, s, s.emlAt, now)      -- AC7 M18's lens flash; Mission 23's flash if it can't
            if fx == 0 then
                local flashes = {}
                for i = 1, c.flash_layers or 1 do flashes[i] = c.flash end
                fx = fxAt(flashes, s.emlAt, c.flash_scale, c.flash_s)
            end
            log(string.format("special: %s's opener: railgun charging %.1f km from you for %.1f s (flash: %d)", c.name,
                s.emlAt.km, c.charge_s, fx))
            return
        end
        if valid(e) then setGone(e, true); SPC.V.mark(c, e) end
        V.sndRise(s, now, c.charge_s)
        if now < s.chargeAt then return end
        V.singleShot(c)                                 -- (in case its module came late; (0.73.80) the kept ones: no walk)
        V.emlWeapon(c)
        V.radar(c)
        V.event("RE_SV_ValkaEmlShot")
        V.event("RE_SV_ValkaEmlChargeOff")
        V.sndShot(s, s.emlAt, now)
        s.alertOffAt = now + (c.alert_off_s or 3)
        do
            local flashes = {}
            for i = 1, c.flash_layers or 1 do flashes[i] = c.flash end
            fxAt(flashes, s.emlAt, c.flash_scale, c.flash_s)
        end
        local d = you and math.sqrt((s.emlAt.X - you.X) ^ 2 + (s.emlAt.Y - you.Y) ^ 2 + (s.emlAt.Z - you.Z) ^ 2) / 100000
        log(string.format("special: %s's opener shot from %s km", c.name, d and string.format("%.1f", d) or "?"))
        s.chargeAt, s.shots, s.state = nil, 1, "shot"
        s.shotAt, s.revealAt, s.emlRemoveAt = now, now + c.reveal_s, now + c.eml_remove_s
        -- ((review of 0.73.80) the opener's no-damage held until its round has been made (the railgun's spin-up, 3 s) and
        -- has flown its life; her first shot comes railgun_every_s after her reveal, later)
        s.harmUntil = now + c.reveal_s + 3 + (tonumber(c.eml_life_s) or 8)
        return
    end
    if s.state == "shot" then                           -- reveal_s after the shot she's there, where it came from
        if now < s.revealAt then return end
        if not SPC.valkaArrive(now, s.emlAt, s.emlYaw) then
            s.state = "done"
            V.event("RE_SV_ValkaEnd")                   -- (the WARNING off)
            pcall(V.roundDefaults, c, "off")             -- ((0.73.80) her round class as it was)
            log(string.format("special: %s couldn't spawn after her shot; the round ends", c.name))
        end
        return
    end
    local o = glitchActor(c)
    if s.state == "fired" then                          -- shown: her health, the camera on her, her name
        if not o then
            if now - s.at >= c.arrive_s + 3 then
                s.state = "hunt"
                log(string.format("special: %s's actor not found %.0f s after she spawned; no reveal", c.name, now - s.at))
            end
            return
        end
        local hx = math.min(c.health_max_x or 1, 1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first))
        local hp = c.health * hx
        local okH = pcall(function() o.MaxHealth = hp; o.HealthInternal = math.floor(hp * 10 + 0.5) end)
        local okB = pcall(function() o.bShowHUDBox = true end)               -- (her desc's tgt too: build_survival.py)
        V.model(c, s, o)                                                     -- her X-02S
        if COOP and COOP.valkaReveal then pcall(COOP.valkaReveal, c.unit) end   -- (0.73.76) on every joiner's copy too
        V.modSaid(c, c.unit, "her")                     -- ((0.73.80) her railguns' modules kept as the game made them)
        s.singleN = V.singleShot(c)                     -- her own railguns ((0.73.76) always: the opener's set it to 1 first,
        log(string.format("special: %s's own railguns single-shot: %d launcher modules", c.name, s.singleN or 0))  -- so hers kept their bursts)
        V.radar(c)
        do
            local nW, whyW = V.emlWeapon(c)
            log(string.format("special: %s's own railgun rounds: %d on %s (%s)", c.name, nW, tostring(c.eml_weapon), whyW))
        end
        local cam = 1
        for k, n in ipairs(ANOMALY_CAMERAS) do if n == c.camera then cam = k end end
        V.event("RE_SV_ValkaCam_" .. string.char(64 + cam))
        V.event("RE_SV_ValkaReveal")
        s.state, s.revealedAt = "hunt", now
        s.railAt, s.turnAt, s.psAt, s.invertAt = now + c.railgun_every_s, now + c.turn_every_s, now + c.post_stall_every_s,
            now + c.invert_every_s
        hudCallout(c.anomaly_line or t.valka_sub, nil)   -- what's happening, then her name big
        hudCallout(c.name:upper(), nil, c.big_x)
        V.subs(c, "reveal")                             -- ((2026-11-07) Comona can't see where she came from;
        V.subs(c, "reveal_charlene", true)              -- nor can CHARLENE)
        log(string.format("special: %s shows, %.0f HP (x%.2f)%s, target box %s; camera %s", c.name, hp, hx,
            okH and "" or " (health NOT set)", okB and "on" or "NOT set", ANOMALY_CAMERAS[cam]))
        return
    end
    -- ((0.73.77) liveObj, not valid(): the clean-up may take her unit off the native list while the wreck falls)
    if s.state == "done" and s.wreckUntil and now < s.wreckUntil and liveObj(s.modelOwner) then
        V.modelHide(s, s.modelOwner)                    -- her X-02S falls, not the x40a's wreck
        return
    end
    if s.state ~= "hunt" then return end
    V.mood(c, s)                                        -- (0.73.76) red and her song, if her round had no lurk
    s.railAt, s.turnAt = s.railAt or now + c.railgun_every_s, s.turnAt or now + c.turn_every_s   -- (no opener: no reveal)
    s.psAt, s.invertAt = s.psAt or now + c.post_stall_every_s, s.invertAt or now + c.invert_every_s
    if SV_UnitAlive(c.unit) <= 0 then
        s.state = "done"
        V.moodOff(c, s, now)                            -- (0.73.76) the red and her song fade away after she dies
        if s.modelComp then s.wreckUntil = now + (c.wreck_s or 15) end
        V.event("RE_SV_ValkaEnd")                       -- the WARNING off (as SV_ValkaDown, in case it's missed)
        if s.invertUntil then V.invert(c, s, false, now) end
        if s.chargeAt then V.event("RE_SV_ValkaChargeOff") end
        V.event("RE_SV_ValkaAlertOff")
        V.flareStop(s)
        V.sndStop(s)
        ANOM.cleanFx(now, true)
        -- ((0.73.77) D4 / the white square left on the minimap: her railguns' forced minimap display off, and what's
        -- left of her unit (the x40a's parts, invincible while her X-02S flew: partsGone; RailGunCK, Mission 26's sure kill,
        -- hit dukka two VALKA rounds on) and of her opener's taken down at once, not after the wreck's fall; the round's
        -- clean-up (sv_rounds.lua SPC.endTick) looks again then)
        pcall(V.radarOff)
        pcall(V.roundDefaults, c, "off")                 -- ((0.73.80) her railgun round's class default as it was)
        log(string.format("special: %s's railgun modules this round: %d walks for them (0.73.80: 0 when the game's making of "
            .. "them was kept), %d launchers kept", c.name, V.MOD.walks or 0, #V.keptLaunchers()))
        if SPC.cleanUp then
            local okC, nC = pcall(SPC.cleanUp, { c.unit, c.eml_unit }, "her death", true, now)
            log(string.format("special: %s down: %s of her unit's objects still up, taken off", c.name,
                okC and tostring(nC) or ("? (error " .. tostring(nC) .. ")")))
        end
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, c.name .. " down")
        LB.special("valka", true, now - s.at)
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, specialPay(pay)))   -- ((0.73.78) C3)
        V.subs(c, "down")                               -- ((2026-11-07) AUDREY takes her home)
        V.subs(c, "down_charlene", true)
        log(string.format("special: round %d, %s shot down %.0f s after she showed (%d railgun shots, %d blinks, %d turns, %d scrambles)",
            D.round, c.name, now - (s.revealedAt or s.at), s.shots or 0, s.blinks or 0, s.turns or 0, s.scrambles or 0))
        return
    end
    if not o then return end
    V.modelTick(s, o, now)
    pcall(V.subsHealth, c, s, o)                         -- ((2026-11-07) AUDREY breaks in as her health falls)
    if now >= (s.holdAt or 0) then                       -- her parts held (EvadeOnly), again every hold_s
        s.holdAt = now + (c.hold_s or 5)
        V.event("RE_SV_ValkaHold")
    end
    if now >= (s.engageAt or 0) then                     -- her orders again (the player only), every engage_every_s
        s.engageAt = now + (c.engage_every_s or 5)
        V.event("RE_SV_ValkaEngage")
    end
    local at = where(o)
    if at and you then s.dist = math.sqrt((at.X - you.X) ^ 2 + (at.Y - you.Y) ^ 2 + (at.Z - you.Z) ^ 2) / 100000 end
    -- the angle between her nose and you (for LastTGT when you're behind her, and her railgun's cone)
    local offNose = nil
    if at and you then
        local okF, f = pcall(function() local q = o:GetActorForwardVector(); return { X = q.X, Y = q.Y, Z = q.Z } end)
        local tx, ty, tz = you.X - at.X, you.Y - at.Y, you.Z - at.Z
        local n = math.sqrt(tx * tx + ty * ty + tz * tz)
        if okF and n > 0 then offNose = math.deg(math.acos(math.max(-1, math.min(1, (f.X * tx + f.Y * ty + f.Z * tz) / n)))) end
    end
    -- the scrambled controls: a chance every invert_every_s, for invert_s
    if s.invertUntil and (now >= s.invertUntil or downNow()) then V.invert(c, s, false, now) end   -- ((0.73.77) A10: DOWN)
    if not s.invertUntil and now >= s.invertAt then
        s.invertAt = now + c.invert_every_s
        if math.random() < c.invert_chance then s.scrambles = (s.scrambles or 0) + 1; V.invert(c, s, true, now) end
    end
    -- blinks: a hit outside a spell (and its cooldown) starts blink_s of them
    local okH, hpNow = pcall(function() return o.HealthInternal end)
    hpNow = okH and type(hpNow) == "number" and hpNow or nil
    if hpNow and s.lastHp and hpNow < s.lastHp - 0.5 and not s.blinkUntil and now >= (s.blinkCool or 0) then
        s.blinkUntil, s.nextBlink = now + c.blink_s, now
        log(string.format("special: %s hit (%.0f -> %.0f): blinking for %.0f s", c.name, s.lastHp, hpNow, c.blink_s))
    end
    s.lastHp = hpNow or s.lastHp
    if s.vanished then                                  -- back, round you, nose on you
        local ev, to, deg
        if you then ev, to, deg = V.blinkSpot(c, s, you) end
        if ev then
            s.lastDeg, s.blinks = deg, (s.blinks or 0) + 1
            V.event(ev)
            if to and fxAt({ c.smoke }, to, c.smoke_scale, c.smoke_s) == 0 and not s.smokeSaid then
                s.smokeSaid = true; log("special: VALKA's smoke " .. c.smoke .. " didn't spawn")
            end
        end
        setGone(o, false); V.partsGone(c, s, o, false)
        s.vanished, s.nextBlink = false, now + c.blink_every_s
    elseif s.blinkUntil and now >= s.blinkUntil then
        s.blinkUntil, s.blinkCool = nil, now + c.blink_cooldown_s
    elseif s.blinkUntil and now >= s.nextBlink and not s.chargeAt then   -- gone in a puff (back next tick)
        if at then fxAt({ c.smoke }, at, c.smoke_scale, c.smoke_s) end
        setGone(o, true); V.partsGone(c, s, o, true, true)
        s.vanished = true
        return
    end
    -- her railgun: warning and charge, then one shot (when you're in front of her, near enough)
    if s.chargeAt then V.sndRise(s, now, c.railgun_charge_s) end
    if s.chargeAt and now >= s.chargeAt then
        V.singleShot(c)                                 -- (0.73.76) every launcher single-shot right before each shot (no bursts)
        V.event("RE_SV_ValkaRailgun")
        V.event("RE_SV_ValkaChargeOff")
        V.sndShot(s, at, now)
        s.chargeAt, s.shots, s.railAt = nil, (s.shots or 0) + 1, now + c.railgun_every_s
        s.alertOffAt = now + (c.alert_off_s or 3)
        log(string.format("special: %s railgun shot %d, %.1f km from you, %.0f deg off her nose", c.name, s.shots,
            s.dist or -1, offNose or -1))
    elseif not s.chargeAt and now >= s.railAt and s.dist and s.dist <= c.railgun_range_km and offNose
        and offNose <= c.railgun_cone_deg then
        s.chargeAt = now + c.railgun_charge_s
        V.event("RE_SV_ValkaChargeOn")
        V.event("RE_SV_ValkaAlertOn")
        -- ((review of 0.73.80) her damage on the class default (if the opener's hold hasn't run out: it can't be left on)
        -- and on the rounds pooled from the opener's shot, before this one's made)
        if s.harmUntil then s.harmUntil = nil; pcall(V.roundDefaults, c, "hers") end
        pcall(V.roundsHarm, c)
        -- ((0.73.80) the kept launchers, no walk; no rounds to put their damage back on: the opener's no-damage was
        -- taken off her round's class default before she spawned)
        V.radar(c)
        V.sndCharge(s, function() return valid(o) and where(o) or nil end, now)
        hudCallout(t.valka_charge, t.valka_charge_sub)
    end
    -- LastTGT: every turn_every_s, and at once (behind_gap_s apart) when you're behind her within behind_km
    local behind = offNose and offNose > 110 and s.dist and s.dist <= c.behind_km
    if (now >= s.turnAt) or (behind and now >= (s.behindAt or 0)) then
        s.turnAt, s.behindAt, s.turns = now + c.turn_every_s, now + c.behind_gap_s, (s.turns or 0) + 1
        s.psAt = math.max(s.psAt, now + 3)                -- (not straight into a post-stall)
        V.event("RE_SV_ValkaTurn")
        if s.turns <= 5 or s.turns % 10 == 0 then
            log(string.format("special: %s LastTGT %d%s, %.1f km from you", c.name, s.turns, behind and " (you behind her)" or "",
                s.dist or -1))
        end
    elseif c.post_stall and now >= s.psAt and s.dist and s.dist <= c.post_stall_range_km then
        s.psAt = now + c.post_stall_every_s
        if not s.psOn then
            s.psOn = true
            pcall(function() o.bCanManeuverPugachevsCobra = true; o.bCanManeuverKulbit = true end)
        end
        local moves = c.post_stall_moves or {}
        if #moves > 0 then V.event("RE_SV_Valka" .. moves[math.random(#moves)]) end
    end
end

-- ((0.73.80) her assets loaded with her sounds (sv_sound.lua, a part before this one): SND.preloadValka, asked in the
-- break before her round (the NEXT announcement, her round's start; a joiner on the host's VALKA round), queues them too,
-- and SND.tick, every tick, loads one; her lurk does when this couldn't be put in)
if type(SND) == "table" and type(SND.preloadValka) == "function" and type(SND.tick) == "function" then
    local sndPreload, sndTick = SND.preloadValka, SND.tick
    function SND.preloadValka(...)
        local okV, errV = pcall(SPC.V.preload)
        if not okV then logOnce("valka preload", "special: VALKA's preload error " .. tostring(errV)) end
        return sndPreload(...)
    end
    function SND.tick(...)
        local okV, errV = pcall(SPC.V.preTick)
        if not okV then logOnce("valka preload tick", "special: VALKA's preload error " .. tostring(errV)) end
        return sndTick(...)
    end
    SPC.V.PRE.wrapped = true
end

-- The special rounds by kind (CFG.specials.rotation; code review of 2026-10-23: each new one meant a branch in eight
-- places): `sub` its callout's second line (a CFG.hud.text key, or a function of the texts), `alone` whether its round
-- has no fighters of its own (a value or a function), `aircraft` how many of the round's aircraft it counts for,
-- `spawn(now)` its arrival from the spawn queue ("@<kind>"; false: it can't come, a normal round instead) and
-- `tick(now, s)` its every tick (the shuttle's countdown is specialTick's own).
SPC.kinds = {
    shuttle    = { sub = function(t) return string.format(t.shuttle_sub, CFG.specials.shuttle.name:upper()) end,
                   spawn = function() spawnShuttle(); return true end },
    anomaly    = { sub = "anomaly_sub", alone = function() return CFG.specials.anomaly.only end,
                   aircraft = function() return 1 + CFG.specials.anomaly.guards end,
                   spawn = function(now)
                       if not ANOM.spawn() then return false end
                       D.special.state, D.special.at = CFG.specials.anomaly.portal.enabled and "portal" or "hunt", now
                       return true
                   end,
                   tick = function(now, s) return ANOM.tick(now, s) end },
    amphibious = { sub = "amphib_sub", spawn = function(now) return AMPH.spawn(now) end,
                   tick = function(now, s) return AMPH.tick(now, s) end },
    -- (ready() whether it can come now, else a normal round; busy(s) holds the round's end, over(now, s) at its end,
    -- row(s, t) its NEXT row: sv_spaceport.lua)
    spaceport  = { sub = "spaceport_sub", ready = function() return SPORT.ready() end,
                   budget = function(budget)
                       return math.floor(budget * (CFG.specials.spaceport.fighter_share or 0.5) / 2 + 0.5) * 2
                   end,
                   spawn = function(now) return SPORT.spawn(now) end, tick = function(now, s) return SPORT.tick(now, s) end,
                   busy = function(s) return SPORT.busy(s) end, over = function(now, s) return SPORT.roundOver(now, s) end,
                   row = function(s, t) return SPORT.row(s, t) end },
    retake     = { sub = "retake_sub",
                   ready = function()                    -- (forced too: none with the Spaceport or its retake off)
                       local c = CFG.specials.spaceport
                       return not (c.enabled == false or (c.retake and c.retake.enabled == false))
                   end,
                   budget = function(budget)
                       local r = CFG.specials.spaceport.retake or {}   -- (extra_aircraft: more fighters, 2026-10-31)
                       return math.floor((budget * (r.fighter_share or 0.6) + (r.extra_aircraft or 0)) / 2 + 0.5) * 2
                   end,
                   spawn = function(now) return SPORT.retakeSpawn(now) end,
                   tick = function(now, s) return SPORT.retakeTick(now, s) end,
                   busy = function(s) return SPORT.retakeBusy(s) end, over = function(now, s) return SPORT.retakeOver(now, s) end,
                   row = function(s, t) return SPORT.row(s, t) end },
    ladon      = { sub = "ladon_sub", alone = true, aircraft = 2, spawn = function(now) return SPC.ladonSpawn(now) end,
                   tick = function(now, s) return SPC.ladonTick(now, s) end },
    alicorn    = { sub = "alicorn_sub", alone = true, aircraft = 1, spawn = function(now) return SPC.alicornSpawn(now) end,
                   tick = function(now, s) return SPC.alicornTick(now, s) end },
    glitch     = { sub = "glitch_sub", alone = true, aircraft = 1, spawn = function(now) return ANOM.glitchSpawn(now) end,
                   tick = function(now, s) return ANOM.glitchTick(now, s) end },
    -- (disguise: a normal round's callout and budget(budget) decoy fighters, VALKA after them: CFG.specials.valka)
    -- ((0.74.0) not from GONE FISHIN' until the festival's over and the arc's sky is back at midday: sv_sky.lua
    -- SKY.arcHoldsValka; the host's decision; her test key still forces her)
    valka      = { sub = "valka_sub", disguise = function() return CFG.specials.valka.disguise end,
                   ready = function(round, forced)
                       if forced or not (SKY and SKY.arcHoldsValka) then return true end
                       return not SKY.arcHoldsValka(round)
                   end,
                   alone = function() return not CFG.specials.valka.disguise end,
                   budget = function(budget)
                       local c = CFG.specials.valka
                       if not c.disguise then return 0 end
                       local n = math.floor(budget * c.decoy_share / 2 + 0.5) * 2         -- (whole 2-ships)
                       return math.max(c.decoy_min, math.min(c.decoy_max, n, budget))
                   end,
                   spawn = function(now) return SPC.valkaSpawn(now) end,
                   tick = function(now, s) return SPC.valkaTick(now, s) end },
    -- ((0.74.0) GONE FISHIN' and THE FESTIVAL, sv_fishing.lua / sv_festival.lua: no fighters of their own)
    fishing    = { sub = "fishing_sub", alone = true, aircraft = 0,
                   ready = function(round, forced) return FISH.ready(round, forced) end,
                   spawn = function(now) return FISH.roundSpawn(now) end, tick = function(now, s) return FISH.roundTick(now, s) end,
                   busy = function(s) return FISH.busy(s) end, over = function(now, s) return FISH.roundOver(now, s) end,
                   row = function(s, t) return FISH.row(s, t) end },
    -- ((2026-11-07) "Include more Enemy Aircraft in the Festival Mission": fighters with the raid, FEST.fighters)
    festival   = { sub = "festival_sub", alone = false, aircraft = 12,
                   budget = function(budget) return FEST.fighters(budget) end,
                   -- ((2026-11-08) "they need to spawn WITH the TU-160's not beforehand": its fighters held through its talk)
                   hold = function(now, s) return FEST.hold(now, s) end,
                   ready = function(round, forced) return FEST.ready(round, forced) end,
                   spawn = function(now) return FEST.roundSpawn(now) end, tick = function(now, s) return FEST.roundTick(now, s) end,
                   busy = function(s) return FEST.busy(s) end, over = function(now, s) return FEST.roundOver(now, s) end,
                   row = function(s, t) return FEST.row(s, t) end },
}
-- a kind's field that may be a function (alone, aircraft, sub)
function SPC.kindValue(v, ...) if type(v) == "function" then return v(...) end return v end

-- PHANTASM's pack (CFG.specials.anomaly.pack; behaviour roadmap P7, docs/re/BEHAVIOUR_DIRECTOR.md unit 9): the guards
-- spring while the field scrambles you, spring_delay_s after it comes on (the tell "pack" first: an ambush call and THE
-- PACK SPRINGS), then are called back round MINDRIPPER once you've been out of the field hold_after_s, at least min_s
-- after the spring, cooldown_s before the next. Two remote events (tools/survival_events.py build_anomaly):
-- RE_SV_AnomalyPackSpring (you only, anywhere, the campaign aces' LastTGT onto you by unit) and RE_SV_AnomalyPackHold
-- (their appearance's orders: you only near it, their area on it). The host's (or solo): its field (ANOM.on) springs it,
-- the LastTGT steers to the host's plane, so both are kept there (sv_coop.lua KEEP_EVENTS ^RE_SV_AnomalyPack); a
-- joiner's own field never springs it. After MINDRIPPER is down nothing: its down records loose the guards anyway.
-- s.pack: nil (held), "armed" (the tell said, the spring due at s.packAt) or "sprung" (since s.packSince).
function ANOM.packTick(now, s, c)
    local pk = c.pack
    if not (pk and pk.enabled and s and s.state == "hunt") or type(SV_Event) ~= "function" then return end
    if ANOM.on == true then s.fieldOffAt = nil elseif not s.fieldOffAt then s.fieldOffAt = now end
    if SV_UnitAlive(c.guard_unit) <= 0 then                 -- (no guard left: nothing to spring or call back)
        if s.pack and not s.packGoneSaid then
            s.packGoneSaid = true
            log(string.format("special: %s's pack: every guard down (%d springs)", c.name, s.packSprings or 0))
        end
        s.pack = nil
        return
    end
    local function fire(ev)
        local r = SV_Event(ev)
        if r ~= 1 then log(string.format("special: %s not fired: %s", ev, SV_ERR and SV_ERR[r] or tostring(r))) end
        return r == 1
    end
    if s.pack == nil then
        if ANOM.on == true and now >= (s.packCool or 0) then
            s.pack, s.packAt = "armed", now + (tonumber(pk.spring_delay_s) or 0)
            -- (this game's player: the host's, as the spring; a sure tell: through its gap and cooldown)
            local how = "not told (no tells)"
            if TELL then
                local okT, r, why = pcall(TELL.say, "pack")
                if okT and r == true then how = "told"
                else how = "not told: " .. tostring(okT and why or r) end
            end
            log(string.format("special: %s's pack: your controls scrambled %.1f km from it; %s springs in %.1f s (%s)",
                c.name, s.dist or -1, c.guards_name, s.packAt - now, how))
        end
    elseif s.pack == "armed" then
        if ANOM.on ~= true then                                  -- (out of the field before it sprang: held)
            s.pack = nil
            log(string.format("special: %s's pack: you left the field first; not sprung", c.name))
        elseif now >= s.packAt then
            if fire("RE_SV_AnomalyPackSpring") then
                s.pack, s.packSince, s.packSprings = "sprung", now, (s.packSprings or 0) + 1
                log(string.format("special: %s's pack sprung (%d): %s loose on you (LastTGT), %d of %d guards up, %.1f km from %s",
                    c.name, s.packSprings, c.guards_name, SV_UnitAlive(c.guard_unit), c.guards or 4, s.dist or -1, c.name))
            else                                                 -- (its event didn't fire: held, cooldown_s to the next)
                s.pack, s.packCool = nil, now + (tonumber(pk.cooldown_s) or 0)
                log(string.format("special: %s's pack not sprung (its event not fired); armed again in %.0f s", c.name,
                    s.packCool - now))
            end
        end
    elseif s.pack == "sprung" and ANOM.on ~= true and now - (s.packSince or now) >= (tonumber(pk.min_s) or 0)
        and s.fieldOffAt and now - s.fieldOffAt >= (tonumber(pk.hold_after_s) or 0) then
        fire("RE_SV_AnomalyPackHold")
        s.pack, s.packCool = nil, now + (tonumber(pk.cooldown_s) or 0)
        log(string.format("special: %s's pack held: back round %s %.0f s after it sprang (%.0f s out of the field)",
            c.name, c.name, now - s.packSince, now - s.fieldOffAt))
    end
end

-- A guard of the Anomaly whose hunt waits for its pack (pack.hunt_only_sprung: ACE.hunt keeps a top-tier plane's target
-- on you; held, it guards MINDRIPPER instead). False with it off, on a co-op joiner (no D.special there) and after
-- MINDRIPPER's round.
function ANOM.packHeld(p)
    local c = CFG.specials.anomaly
    local pk = c and c.pack
    if not (pk and pk.enabled and pk.hunt_only_sprung and p and p.unit == c.guard_unit) then return false end
    local s = D and D.special
    return s ~= nil and s.kind == "anomaly" and s.state == "hunt" and s.pack ~= "sprung"
end

-- Every tick of a running Anomaly: its distance (the field) and its end.
function ANOM.tick(now, s)
    local c, t = CFG.specials.anomaly, CFG.hud.text
    if s.state == "portal" then return portalTick(now, s, c) end
    if s.state ~= "hunt" then return end
    if SV_UnitAlive(c.unit) <= 0 then
        s.state = "done"
        setField(false, s)
        if type(SV_Event) == "function" then SV_Event("RE_SV_AnomalyEnd") end
        local live = #ANOM.fx
        ANOM.cleanFx(now, true)                                               -- every system on it off now
        log(string.format("special: %s down: its %d lightning systems switched off", c.name, live))
        local nb = fxAt(c.portal.burst, s.lastAt, c.portal.scale)             -- the lightning again where it fell
        log(string.format("special: %s's last burst (%d systems)", c.name, nb))
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, c.name .. " down")
        LB.special("anomaly", true, now - s.at)
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, specialPay(pay)))   -- ((0.73.78) C3)
        log(string.format("special: round %d, %s shot down %.0f s after it appeared (its pack sprang %d times)", D.round,
            c.name, now - s.at, s.packSprings or 0))
        return
    end
    local p
    for _, q in ipairs(planes) do if q.unit == c.unit and valid(q.obj) then p = q end end
    if p and not s.healthDone then                 -- its health for its round (economy review of 2026-10-25)
        s.healthDone = true
        local hx = math.min(c.health_max_x or 1, 1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first))
        local h0, h1 = scaleHealth(p.obj, hx)
        log(string.format("special: %s's health x%.2f for round %d (%s -> %s)", c.name, hx, D.round, tostring(h0), tostring(h1)))
    end
    local you = playerLocation()
    if not (p and you) then return end
    local ok, l = pcall(function() local v = p.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not ok then return end
    s.dist, s.lastAt = km(l, you), l
    if c.portal.enabled and now >= (s.nextAura or 0) then                  -- it crackles while it's up
        s.nextAura = now + c.portal.aura_every_s
        portalFx({ c.portal.aura }, p.obj, nil, c.portal.aura_scale)
        if math.random() < 0.35 then strike(p.obj) end
    end
    local pawn = valid(survivalPC) and survivalPC.Pawn
    local a = pawn and addrOf(pawn)
    if a and a ~= ANOM.pawn then ANOM.pawn = a; if ANOM.on then ANOM.on = nil end end   -- a new plane: switch again
    if downNow() then                                                  -- ((0.73.77) A10: none on you while you're DOWN)
        if ANOM.on then setField(false, nil); log("special: anomaly field off: you're DOWN")
        elseif s.dist < c.field_km then setField(true, s) end         -- (setField holds it off: logged once)
    elseif ANOM.on ~= true and s.dist < c.field_km then setField(true, s)
    elseif ANOM.on ~= false and s.dist > c.field_km + 0.3 then setField(false, s) end      -- (0.3 km: no flicker)
    local okP, errP = pcall(ANOM.packTick, now, s, c)                                       -- (its pack: P7)
    if not okP and tostring(errP) ~= s.packErr then s.packErr = tostring(errP); log("special: pack error " .. s.packErr) end
end

-- A Survival COOP joiner's own field (sv_coop.lua clientRounds; code review of 2026-10-26: the host's field events
-- switched every joiner's field on the host's distance): the joiner runs no rounds, so its distance to its copy of the
-- Anomaly decides it here, as ANOM.tick does for the host. Off once the copy is gone.
-- (0.73.77) The user, 2026-11-03: "After shooting down Mindripper, the field ... lingered for other players but not me ...
-- still getting his controls reversed in much further rounds when flying near where we shot Mindripper down": any copy
-- of its unit that was still a valid object counted, a wreck or a copy left up by the copy desync (plan A1) too, so its
-- crash site scrambled that joiner for the rest of the run (the host runs its own state, so never had it). Now only
-- while the host's round has the Anomaly up (sv_coop.lua "rnd" field 11: D.hostSpecial, its kind and state) and only a
-- live copy (not down, health above 0), off at once when the host's is over; never on a joiner who's DOWN (A10).
local function liveCopy(unit)
    local p
    for _, q in ipairs(planes) do
        if q.unit == unit and not q.down and liveObj(q.obj) then
            local okH, h = pcall(function() return q.obj.HealthInternal end)
            if okH and type(h) == "number" and h > 0 then p = q end
        end
    end
    return p
end
ANOM.liveCopy = liveCopy
function ANOM.clientTick()
    local c = CFG.specials.anomaly
    local hs = D and D.hostSpecial
    if not (hs and hs.kind == "anomaly" and hs.state == "hunt") then
        if ANOM.on then
            setField(false, nil)
            log("coop: the Anomaly is over on the host: its field off here")
        end
        return
    end
    if downNow() then
        if ANOM.on then setField(false, nil); log("special: anomaly field off: you're DOWN") end
        return
    end
    local p = liveCopy(c.unit)
    local you = playerLocation()
    if not (p and you) then
        if ANOM.on then setField(false, nil) end
        return
    end
    local ok, l = pcall(function() local v = p.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not ok then return end
    local s = { state = "hunt", dist = km(l, you) }
    local pawn = valid(survivalPC) and survivalPC.Pawn
    local a = pawn and addrOf(pawn)
    if a and a ~= ANOM.pawn then ANOM.pawn = a; if ANOM.on then ANOM.on = nil end end
    if ANOM.on ~= true and s.dist < c.field_km then setField(true, s)
    elseif ANOM.on ~= false and s.dist > c.field_km + 0.3 then setField(false, s) end
end

-- A Survival COOP joiner's copy of AB.L..IN in its phase 3 (code review of unit 9: the host switched its own plane's
-- pods off while the joiner's copy, its own pod row firing, jammed on after "it's not jamming anymore"): the host's phase comes
-- in "rnd" (sv_coop.lua: D.glitchPhase), and the copy's pods are switched off here every ecm_check_s, as glitchPodsOff
-- does on the host. Nothing before phase 3, with the phases or ecm_pods_off off, or with no copy up.
function ANOM.clientGlitch(now)
    local c = CFG.specials.glitch
    local ph = c and c.phases
    if not (type(ph) == "table" and ph.enabled and ph.ecm_pods_off and D and D.glitchPhase == 3) then
        ANOM.glitchCopy = nil
        return
    end
    local cs = ANOM.glitchCopy
    if not cs then
        cs = {}
        ANOM.glitchCopy = cs
        log(string.format("coop: %s in its phase 3 on the host: its copy's ECM pods switched off here every %.0f s", c.name,
            math.max(1, tonumber(ph.ecm_check_s) or 3)))
    end
    if now < (cs.podsAt or 0) then return end
    cs.podsAt = now + math.max(1, tonumber(ph.ecm_check_s) or 3)
    local p = liveCopy(c.unit)                         -- ((0.73.77) a live copy only: not a wreck, health above 0)
    local o = p and p.obj
    if o then pcall(glitchPodsOff, c, cs, o) end
end
end
