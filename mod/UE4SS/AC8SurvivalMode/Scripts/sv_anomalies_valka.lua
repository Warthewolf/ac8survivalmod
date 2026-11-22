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
    if o ~= nil and valid(o) then
        SPC.V.assets[full] = o
        -- ((2026-11-22) a crash at her return blink (0.75.26: a call on a freed object, from Lua): kept only in this cache,
        -- an asset no portal held any more was freed and its address reused (hard rule 59), and her next portal handed the
        -- stale one to the engine. Pinned now (GameInstance.ReferencedObjects): never freed while the game runs)
        if pin then pcall(pin, o, "VALKA's " .. (full:match("[^/%.]+$") or full)) end
        return o
    end
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
    if type(c.portal) == "table" and c.portal.enabled then  -- ((2026-11-22) her portal's pieces)
        for _, part in ipairs(c.portal.parts or {}) do add(part.mesh); add(part.mat); add(part.fx) end
    end
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
    local r = SV_Spawn(c.eml_unit, at.X, at.Y, at.Z - (tonumber(c.unit_up_m) or 0) * 100, yaw)   -- (as hers: valkaArrive)
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
    -- ((2026-11-22) the user: "change Valka's spawn location to the inside of the Portal": her plane sits unit_up_m over
    -- her unit's point in the world data (build_survival_units.py valka_unit: (0, 0, 300000)) and SV_Spawn moves the
    -- point, keeping that; every run of the day showed her 3.0 km over her portal. Taken off: she's at z, in its middle)
    local r = SV_Spawn(c.unit, x, y, z - (tonumber(c.unit_up_m) or 0) * 100, heading)
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
    if s.portal then V.portalTick(c, s, now) end         -- ((2026-11-22) her portal: open, hold, close)
    if VCINE and VCINE.tick then VCINE.tick(c, s, now) end    -- (its cutscene: sv_valka_cine.lua)
    if SOLG and SOLG.tick then SOLG.tick(now) end             -- (her SOLG: sv_solg.lua)
    if VSOLG and VSOLG.strikesTick then pcall(VSOLG.strikesTick, now) end   -- (its strike, stopped in time even once she's down)
    if s.bportals then V.blinkPortalsTick(c, s, now) end  -- (and her blinks' small ones)
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
            V.event("RE_SV_ValkaWarnOn")
            -- ((2026-11-22) the user: "Create a cutscene similar to the Invincible Fleets Arrival of the Portal Opening, and
            -- Valka coming out of it": sv_valka_cine.lua, from now till she's out; her charge cine.charge_s meanwhile)
            if type(c.portal) == "table" and c.portal.enabled and VCINE and VCINE.start then
                local okV, onV = pcall(VCINE.start, c, s, s.emlAt, s.emlYaw, now)
                if not okV then log("special: VALKA's cutscene error " .. tostring(onV)) end
                if okV and onV then s.chargeAt = now + (tonumber(c.cine and c.cine.charge_s) or c.charge_s) end
            end                -- WARNING until she's down (no banner of ours: no tells)
            V.event("RE_SV_ValkaEmlChargeOn")
            V.sndCharge(s, s.emlAt, now)
            -- ((2026-11-22) the user: "a 3D Portal, an event horizon that she spawns out of") it opens where her
            -- opener fires from, facing you; her shot comes out of it, then she does
            if type(c.portal) == "table" and c.portal.enabled then
                local okP, errP = pcall(V.portalOpen, c, s, s.emlAt, s.emlYaw, now)
                if not okP then log("special: VALKA's portal error " .. tostring(errP)) end
                if okP and s.portal and COOP and COOP.valkaPortal then pcall(COOP.valkaPortal, s.emlAt, s.emlYaw, "o") end
            end
            -- ((2026-11-22) the user: "Get rid of the flash png thing": no lens flash, nor Mission 23's flash, with her black
            -- hole up (portal.flash = true brings them back))
            local noFlash = s.portal and not (type(c.portal) == "table" and c.portal.flash)
            local fx = noFlash and 0 or V.flareStart(c, s, s.emlAt, now)   -- AC7 M18's lens flash; Mission 23's flash if it can't
            if fx == 0 and not noFlash then
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
        -- ((2026-11-22) the runs of 15:13, 15:45 and 15:57: as her opener's round came at you the game cut to your plane
        -- (a black frame, then your chase view, its bank on it) in the middle of her cutscene. While it films, the shot
        -- is only heard (its charge, its crack): no round at you; the cutscene shows her coming out instead)
        local filmed = VCINE and VCINE.active and VCINE.active() and not (c.cine and c.cine.shoot)
        if filmed then log(string.format("special: %s's opener round held: her cutscene films", c.name))
        else V.event("RE_SV_ValkaEmlShot") end
        V.event("RE_SV_ValkaEmlChargeOff")
        V.sndShot(s, s.emlAt, now)
        s.alertOffAt = now + (c.alert_off_s or 3)
        if not (s.portal and not (type(c.portal) == "table" and c.portal.flash)) then   -- ((2026-11-22) none with her hole up)
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
        -- ((2026-11-22) with her portal up: a little behind its face, so she flies out through it)
        local from = s.portal and V.portalExit(c, s.emlAt, s.emlYaw) or s.emlAt
        if s.portal then
            pcall(V.portalThrough, c, s, now)
            if COOP and COOP.valkaPortal then pcall(COOP.valkaPortal, s.emlAt, s.emlYaw, "t") end
        end
        if not SPC.valkaArrive(now, from, s.emlYaw) then
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
        if s.portal and s.portal.at then                -- ((2026-11-22) out of her portal's middle? unit_up_m)
            pcall(function()
                local h, P = o:K2_GetActorLocation(), s.portal.at
                log(string.format("special: %s comes out %.0f m from her portal's middle (%.0f m over it; its shadow %.0f m across)",
                    c.name, math.sqrt((h.X - P.X) ^ 2 + (h.Y - P.Y) ^ 2 + (h.Z - P.Z) ^ 2) / 100, (h.Z - P.Z) / 100, s.portal.size / 100))
            end)
        end
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
        local filmed = VCINE and VCINE.active and VCINE.active()
        if not filmed then V.event("RE_SV_ValkaCam_" .. string.char(64 + cam)) end   -- (the cutscene's cameras on her instead)
        V.event("RE_SV_ValkaReveal")
        s.state, s.revealedAt = "hunt", now
        s.railAt, s.turnAt, s.psAt, s.invertAt = now + c.railgun_every_s, V.turnClock(c, now), now + c.post_stall_every_s,
            now + c.invert_every_s
        hudCallout(c.anomaly_line or t.valka_sub, nil)   -- what's happening, then her name big
        hudCallout(c.name:upper(), nil, c.big_x)
        V.subs(c, "reveal")                             -- ((2026-11-07) Comona can't see where she came from;
        V.subs(c, "reveal_charlene", true)              -- nor can CHARLENE)
        log(string.format("special: %s shows, %.0f HP (x%.2f)%s, target box %s; camera %s", c.name, hp, hx,
            okH and "" or " (health NOT set)", okB and "on" or "NOT set", filmed and "the cutscene's" or ANOMALY_CAMERAS[cam]))
        return
    end
    -- ((0.73.77) liveObj, not valid(): the clean-up may take her unit off the native list while the wreck falls)
    if s.state == "done" and s.wreckUntil and now < s.wreckUntil and liveObj(s.modelOwner) then
        V.modelHide(s, s.modelOwner)                    -- her X-02S falls, not the x40a's wreck
        return
    end
    if s.state ~= "hunt" then return end
    V.mood(c, s)                                        -- (0.73.76) red and her song, if her round had no lurk
    s.railAt, s.turnAt = s.railAt or now + c.railgun_every_s, s.turnAt or V.turnClock(c, now)   -- (no opener: no reveal)
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
        V.portalStop(s)
        V.blinkPortalsStop(s)
        if VSOLG and VSOLG.stop then pcall(VSOLG.stop, s, "her death") end
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
        log(string.format("special: round %d, %s shot down %.0f s after she showed (%d railgun shots, %d blinks, %d chases, %d turns, "
            .. "%d post-stalls, %d scrambles)", D.round, c.name, now - (s.revealedAt or s.at), s.shots or 0, s.blinks or 0,
            s.chases or 0, s.turns or 0, s.stalls or 0, s.scrambles or 0))
        return
    end
    if not o then return end
    V.modelTick(s, o, now)
    pcall(V.subsHealth, c, s, o)                         -- ((2026-11-07) AUDREY breaks in as her health falls)
    if VSOLG and VSOLG.tick then                         -- ((2026-11-22) at 20 % her SOLG: sv_valka_solg.lua; the rest waits)
        local okS, busy = pcall(VSOLG.tick, c, s, o, now)
        if not okS then
            if not s.solgErr then s.solgErr = true; log("special: VALKA's SOLG: error " .. tostring(busy)) end
        elseif busy then return end
    end
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
    -- blinks: a hit outside a spell (and its cooldown) starts blink_count of them ((2026-11-22) before: blink_s of them)
    local okH, hpNow = pcall(function() return o.HealthInternal end)
    hpNow = okH and type(hpNow) == "number" and hpNow or nil
    if hpNow and s.lastHp and hpNow < s.lastHp - 0.5 and not s.blinkUntil and now >= (s.blinkCool or 0) then
        local n = tonumber(c.blink_count)
        s.blinkLeft = n and n > 0 and math.floor(n) or nil
        s.blinkUntil = now + (s.blinkLeft and (s.blinkLeft * (c.blink_every_s or 1) + 1) or c.blink_s)
        s.nextBlink = now
        log(string.format("special: %s hit (%.0f -> %.0f): %s", c.name, s.lastHp, hpNow, s.blinkLeft
            and string.format("%d blinks onto your six or across your nose", s.blinkLeft) or string.format("blinking for %.0f s", c.blink_s)))
    end
    s.lastHp = hpNow or s.lastHp
    if not (s.dist and s.dist > (c.chase_km or 6)) then s.farSince = nil end   -- (her chase's clock: only while she's far)
    if s.vanished then                                  -- back: round you, onto your six or across your nose; nose on you
        local ev, to, deg, how
        if you then
            if s.blinkWhy == "chase" then ev, to, deg, how = V.attackSpot(c, s, you, "six", c.chase_ring)
            elseif type(c.blink_rings) == "table" and #c.blink_rings > 0 then ev, to, deg, how = V.attackSpot(c, s, you)
            else ev, to, deg = V.blinkSpot(c, s, you); how = "round you" end
        end
        if ev then
            s.lastDeg, s.blinks = deg, (s.blinks or 0) + 1
            V.event(ev)
            if to and deg then pcall(V.blinkPortal, c, s, to, (deg + 180) % 360, now) end   -- (she comes out facing you)
            if to and fxAt({ c.smoke }, to, c.smoke_scale, c.smoke_s) == 0 and not s.smokeSaid then
                s.smokeSaid = true; log("special: VALKA's smoke " .. c.smoke .. " didn't spawn")
            end
            if s.blinks <= 6 or s.blinks % 10 == 0 then
                log(string.format("special: %s blink %d (%s): %s, %s", c.name, s.blinks, s.blinkWhy or "hit", tostring(how), ev))
            end
        end
        setGone(o, false); V.partsGone(c, s, o, false)
        s.vanished, s.nextBlink = false, now + c.blink_every_s
        if s.blinkLeft then
            s.blinkLeft = s.blinkLeft - 1
            if s.blinkLeft <= 0 then s.blinkLeft, s.blinkUntil = nil, now end   -- (the spell's over: its cooldown next tick)
        end
        if s.blinkWhy == "chase" then s.blinkWhy = nil; s.blinkUntil = nil end
    elseif c.chase and not s.blinkUntil and not s.chargeAt and s.dist and s.dist > (c.chase_km or 6)
        and now - (s.revealedAt or s.at or now) >= (tonumber(c.chase_after_s) or 0) then
        -- ((2026-11-22) she takes the fight to you: farther than chase_km for chase_s, onto your six, chase_gap_s apart)
        s.farSince = s.farSince or now
        if now - s.farSince >= (c.chase_s or 4) and now >= (s.chaseAt or 0) then
            s.farSince, s.chaseAt, s.chases = nil, now + (c.chase_gap_s or 15), (s.chases or 0) + 1
            log(string.format("special: %s chases you: %.1f km away for %.0f s, onto your six (chase %d)", c.name, s.dist,
                c.chase_s or 4, s.chases))
            if at then fxAt({ c.smoke }, at, c.smoke_scale, c.smoke_s) end
            if at and you then pcall(V.blinkPortal, c, s, at, math.deg(math.atan(you.Y - at.Y, you.X - at.X)), now) end
            setGone(o, true); V.partsGone(c, s, o, true, true)
            s.vanished, s.blinkWhy, s.blinkUntil = true, "chase", now + 5
            return
        end
    elseif s.blinkUntil and now >= s.blinkUntil then
        s.blinkUntil, s.blinkCool = nil, now + c.blink_cooldown_s
    elseif s.blinkUntil and now >= s.nextBlink and not s.chargeAt then   -- gone in a puff (back next tick)
        if at then fxAt({ c.smoke }, at, c.smoke_scale, c.smoke_s) end
        if at and you then pcall(V.blinkPortal, c, s, at, math.deg(math.atan(you.Y - at.Y, you.X - at.X)), now) end
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
    if s.turnEndAt and now >= s.turnEndAt then          -- ((2026-11-22) her LastTGT's turn-in over: her own flying again
        s.turnEndAt = nil
        V.event("RE_SV_ValkaTurnEnd")
    end
    -- LastTGT: every turn_every_s, and at once (behind_gap_s apart) when you're behind her within behind_km
    local behind = offNose and offNose > 110 and s.dist and s.dist <= c.behind_km
    -- ((2026-11-22) only once you've sat behind her behind_hold_s: right after a pass of hers you're behind her too, and
    -- an instant LastTGT then turned her back onto you every time, so she never ran out of a pass)
    if behind then s.behindSince = s.behindSince or now else s.behindSince = nil end
    behind = behind and now - s.behindSince >= (tonumber(c.behind_hold_s) or 0)
    if (now >= s.turnAt) or (behind and now >= (s.behindAt or 0)) then
        s.turnAt, s.behindAt, s.turns = V.turnClock(c, now), now + c.behind_gap_s, (s.turns or 0) + 1
        -- ((2026-11-22) a turn-in, not a 20 s tail chase: reset turn_hold_s on; 0 keeps it whole)
        local hold = tonumber(c.turn_hold_s) or 0
        s.psAt = math.max(s.psAt, now + math.max(3, hold + 1))   -- (not straight into a post-stall, nor one its reset cuts)
        V.event("RE_SV_ValkaTurn")
        s.turnEndAt = hold > 0 and now + hold or nil
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
        if #moves > 0 and math.random() < (tonumber(c.post_stall_chance) or 1) then   -- ((2026-11-22) a chance, not each time)
            s.stalls = (s.stalls or 0) + 1
            V.event("RE_SV_Valka" .. moves[math.random(#moves)])
        end
    end
end
-- ((2026-11-22) LastTGT on a clock only when turn_every_s > 0) her next clock LastTGT
function SPC.V.turnClock(c, now)
    local e = tonumber(c.turn_every_s) or 0
    return e > 0 and now + e or math.huge
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

-- ((2026-11-22) the user: "try to build a 3D Portal, an event horizon that she spawns out of") VALKA's portal
-- (CFG.specials.valka.portal): one actor of ours where she comes out, its parts the game's own pieces (portal.parts:
-- meshes, the engine's basic shapes and stock rings with the game's VFX materials, and Niagara systems), facing along
-- her way out (yaw): it opens over open_s (each mesh part grown from nothing, eased), turns (spin), holds until she's
-- through, then closes over close_s and is taken away. A mesh part: { mesh, mat (nil: its own), size (x size_m), flat
-- (its thickness x), axis ("z": the mesh's Z along her way out; "x"), spin (x spin_dps), params (the material's scalars
-- and vectors) }; a Niagara part: { fx, scale, at ("open" / "burst" / "close"), rim (copies round its rim), rim_r (x
-- size_m), life }. Visual only: nothing hits it, nobody locks it.
SPC.V.PORTAL_STATS = { opened = 0, parts = 0, fx = 0, failed = 0 }
local function portalFrame(yaw)
    local r = math.rad(yaw or 0)
    return { X = math.cos(r), Y = math.sin(r), Z = 0 }, { X = -math.sin(r), Y = math.cos(r), Z = 0 }
end
local function portalRot(part, yaw)
    if part.axis == "x" then return { Pitch = 0, Yaw = yaw, Roll = 0 } end
    -- (its local Z along her way out: rolled up, then turned. (2026-11-22) a Pitch of -89.9 never took (the run of 13:26:
    -- the portal lay flat), a Roll did (the probe's standing rings); the disc's two faces are alike, so Z along +-her way)
    -- ((2026-11-22) the black hole: `tilt`, the roll: 90 its face towards you (the shadow, the photon ring, the lensed arcs),
    -- 5 the disk lying nearly flat, tipped that much towards you)
    return { Pitch = 0, Yaw = (yaw or 0) + 90, Roll = tonumber(part.tilt) or 90 }
end
local function portalMesh(pc, P, part, a, smc, kml)
    local m = SPC.V.asset(part.mesh)
    if not m then return nil end
    local okC, comp = pcall(function()
        return a:AddComponentByClass(smc, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
            Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    end)
    if not (okC and valid(comp)) then return nil end
    pcall(function() comp:SetStaticMesh(m) end)
    pcall(function() comp:SetCollisionEnabled(0) end)
    pcall(function() comp:SetCastShadow(false) end)
    -- ((2026-11-22) `sort`: its place among the see-through pieces (lower first): the black over the shadow's glossy ball
    -- first, so the disk's near side draws over it)
    if part.sort then pcall(function() comp:SetTranslucentSortPriority(math.floor(tonumber(part.sort) or 0)) end) end
    local r = 100
    pcall(function() r = m:GetBounds().SphereRadius end)
    -- ((2026-11-22) `abs`: a piece of one model (tools/valka_portal: 1 unit, 100 cm, the black hole's shadow across), sized
    -- size_m x size for that unit, so the pieces keep their places; else sized by its own bounds)
    local k = part.abs and (P.size / 100) * (part.size or 1) or (P.size * (part.size or 1) / 2) / math.max(1, r)
    -- (`turn`: degrees round its own axis from the start: the lensed arcs' broad side up, 180: the runs of 14:17 and 14:26)
    local e = { comp = comp, k = k, flat = part.flat or 1, part = part, spun = tonumber(part.turn) or 0,
                spin = (part.spin or 0) * (tonumber(pc.spin_dps) or 0), axis = part.axis }
    if part.mat then
        local mi = SPC.V.asset(part.mat)
        local okM, mid = false, nil
        if mi and valid(kml) then okM, mid = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, mi, FName("None"), 0) end) end
        if okM and valid(mid) then
            for pn, v in pairs(part.params or {}) do
                if type(v) == "number" then pcall(function() mid:SetScalarParameterValue(FName(pn), v) end)
                elseif type(v) == "table" then pcall(function() mid:SetVectorParameterValue(FName(pn), { R = v[1], G = v[2], B = v[3], A = v[4] or 1 }) end) end
            end
            local n = 1
            pcall(function() n = comp:GetNumMaterials() end)
            for k = 0, math.max(0, n - 1) do pcall(function() comp:SetMaterial(k, mid) end) end
            e.mid = mid
            -- ((2026-11-22) the user: "animated to show it moving": `pulse` { amount, Hz }, its Color's brightness
            -- flickering on two waves out of step (AC8's animated materials don't move on a mesh: the probe of 14:43)
            if part.params and type(part.params.Color) == "table" and (type(part.pulse) == "table" or part.flare) then
                e.color, e.ph = part.params.Color, math.random() * 6.283
                if type(part.pulse) == "table" then e.pulse = part.pulse end
            end
        end
    end
    -- ((2026-11-22) the user: "the portal opening and closing is so laggy its not smooth at all": Lua sets things 4 times
    -- a second) each piece on its own scaler (SK_SV_PortalScaler: tools/valka_portal/scaler.py), whose one bone B the
    -- engine scales every frame as it plays A_SV_PortalGrow (held at 0.001 till its window; backwards as it closes), spun by an
    -- engine RotatingMovementComponent; the tick only starts them (portalTick). No scaler (an older container): as before
    local sk = P.scaler ~= false and SPC.V.asset(SPC.V.PORTAL_SCALER) or nil
    local grow = sk and SPC.V.asset(SPC.V.PORTAL_GROW) or nil
    local sc = nil
    if sk and grow then
        local okS, x = pcall(function()
            return a:AddComponentByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"), false,
                { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
        end)
        if okS and valid(x) then sc = x end
    end
    if sc then
        local okM = pcall(function() sc:SetSkeletalMeshAsset(sk) end) or pcall(function() sc:SetSkeletalMesh(sk, true) end)
        pcall(function() sc:SetCollisionEnabled(0) end)
        pcall(function() sc:SetCastShadow(false) end)
        pcall(function() sc.VisibilityBasedAnimTickOption = 0 end)   -- (its bone moved even off screen: AlwaysTickPoseAndRefreshBones)
        pcall(function() sc:K2_SetWorldLocationAndRotation({ X = P.at.X, Y = P.at.Y, Z = P.at.Z }, portalRot(part, P.yaw), false, {}, true) end)
        -- ((0.75.17's pictures: the pieces turned and stretched) the piece put where it belongs at full size first, the
        -- scaler's bone still at rest, and attached keeping that (its bone's own frame is the importer's, turned from
        -- glTF's): the bone's scale then shrinks and grows it about the portal's middle, nothing else
        pcall(function() comp:K2_SetWorldLocation({ X = P.at.X, Y = P.at.Y, Z = P.at.Z }, false, {}, true) end)
        pcall(function() comp:K2_SetWorldRotation(portalRot(part, P.yaw), false, {}, true) end)
        if e.spun ~= 0 then pcall(function() comp:K2_AddLocalRotation({ Pitch = 0, Yaw = e.spun, Roll = 0 }, false, {}, true) end) end
        pcall(function() comp:SetWorldScale3D({ X = e.k, Y = e.k, Z = e.k * e.flat }) end)
        local okA = okM and pcall(function() comp:K2_AttachToComponent(sc, FName("B"), 1, 1, 1, false) end)
        if okA then
            -- (held at its start, 0.001, till its window. (2026-11-22) not paused at rate 0: a paused animation isn't run, its
            -- bone stayed at full size till its window ("the black hole ... is already at full size"): a creep instead)
            pcall(function() sc:PlayAnimation(grow, false) end)
            pcall(function() sc:SetPosition(0, false) end)
            pcall(function() sc:SetPlayRate(SPC.V.PORTAL_CREEP) end)
            -- (0.75.20's probe: its bone at full size till the engine first runs the animation, a frame on: the piece
            -- hidden till the portal's first tick, then shown, small)
            pcall(function() comp:SetVisibility(false, false) end)
            e.sc, e.hold = sc, true
            if e.spin ~= 0 then
                local okR, rot = pcall(function() return a:AddComponentByClass(StaticFindObject("/Script/Engine.RotatingMovementComponent"), false,
                    { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false) end)
                if okR and valid(rot) then
                    pcall(function() rot:SetUpdatedComponent(comp) end)
                    pcall(function() rot.bRotationInLocalSpace = true end)
                    e.rot = rot
                    SPC.V.portalSpin(e, 0.15)
                end
            end
            return e
        end
        pcall(function() sc:K2_DestroyComponent(sc) end)     -- (not on it: the old way below)
    end
    pcall(function() comp:K2_SetWorldLocation({ X = P.at.X, Y = P.at.Y, Z = P.at.Z }, false, {}, true) end)
    pcall(function() comp:K2_SetWorldRotation(portalRot(part, P.yaw), false, {}, true) end)
    if e.spun ~= 0 then pcall(function() comp:K2_AddLocalRotation({ Pitch = 0, Yaw = e.spun, Roll = 0 }, false, {}, true) end) end
    pcall(function() comp:SetWorldScale3D({ X = 0.001, Y = 0.001, Z = 0.001 }) end)
    return e
end
SPC.V.PORTAL_CREEP = 0.0001                       -- (a waiting piece's grow: run, but nothing in a minute)
SPC.V.PORTAL_SCALER = "/Game/Mods/SurvivalMode/ValkaPortal/Model/SK_SV_PortalScaler"
SPC.V.PORTAL_GROW = "/Game/Mods/SurvivalMode/ValkaPortal/Model/SK_SV_PortalScaler_Anim"   -- (its grow: the importer's name, never renamed)
-- a piece's engine spin at its rate x k (the portal's spin-up as it opens, faster as it drains)
function SPC.V.portalSpin(e, k)
    if not e.rot then return end
    local d = e.spin * k
    if e.spinK and math.abs(d - e.spinK) < 0.5 then return end
    e.spinK = d
    pcall(function() e.rot.RotationRate = e.axis == "x" and { Pitch = 0, Yaw = 0, Roll = d } or { Pitch = 0, Yaw = d, Roll = 0 } end)
end
-- a piece's scaler: its animation started at the rate that fills `secs`
local function scalerGo(e, anim, secs, fresh)
    local okP = true
    if fresh then okP = pcall(function() e.sc:PlayAnimation(anim, false) end) end
    pcall(function() e.sc:SetPlayRate(1 / math.max(0.05, secs)) end)
    return okP
end
-- the portal at `at` (cm) facing `yaw`; true if it came up
-- (pc: another portal's settings, her blinks' small ones: blink_portal; quiet: not logged)
function SPC.V.portalOpen(c, s, at, yaw, now, pc, quiet)
    pc = pc or c.portal
    SPC.V.portalStop(s)
    if not (type(pc) == "table" and pc.enabled and at) then return false end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local actorCls, smc = StaticFindObject("/Script/Engine.Actor"), StaticFindObject("/Script/Engine.StaticMeshComponent")
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    if not (valid(gs) and valid(actorCls) and valid(smc) and valid(survivalPC)) then return false end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okA, a = pcall(function()
        local x = gs:BeginDeferredActorSpawnFromClass(survivalPC, actorCls, t, 1, nil, 1)
        return gs:FinishSpawningActor(x, t, 1)
    end)
    if not (okA and valid(a)) then log("special: VALKA's portal: no actor (" .. tostring(a) .. ")"); return false end
    -- ((2026-11-22) an empty root first: a new component goes on the actor's root, and the first piece (the black hole's
    -- shadow) was the root, so every scaler hung off it and it couldn't go on its own: "the Black Hole did not move")
    pcall(function()
        local root = a:AddComponentByClass(StaticFindObject("/Script/Engine.SceneComponent"), false,
            { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
        root:K2_SetWorldLocation({ X = at.X, Y = at.Y, Z = at.Z }, false, {}, true)
    end)
    local P = { actor = a, at = { X = at.X, Y = at.Y, Z = at.Z }, yaw = yaw or 0, from = now, phase = "open", meshes = {},
                fired = {}, size = (tonumber(pc.size_m) or 250) * 100, pc = pc }
    local said = {}
    -- ((2026-11-22) its own pieces (SurvivalMode_ValkaPortal_P) missing: the stock pieces' portal, `fallback`)
    local parts = pc.parts or {}
    if pc.fallback and parts[1] and parts[1].mesh and not SPC.V.asset(parts[1].mesh) then
        parts = pc.fallback
        if not quiet then log("special: VALKA's portal: its own pieces aren't in (" .. parts[1].mesh .. "...): the stock pieces' portal") end
    end
    P.parts = parts
    for _, part in ipairs(parts) do
        if part.mesh then
            local okE, e = pcall(portalMesh, pc, P, part, a, smc, kml)
            local nm = (part.mesh:match("[^/]+$") or "?") .. (part.mat and ("/" .. (part.mat:match("[^/]+$") or "?")) or "")
            if okE and e then P.meshes[#P.meshes + 1] = e; said[#said + 1] = nm
            else SPC.V.PORTAL_STATS.failed = SPC.V.PORTAL_STATS.failed + 1; said[#said + 1] = nm .. " NOT up" end
        end
    end
    s.portal = P
    SPC.V.PORTAL_STATS.opened = SPC.V.PORTAL_STATS.opened + 1
    SPC.V.PORTAL_STATS.parts = SPC.V.PORTAL_STATS.parts + #P.meshes
    local onSc = 0
    for _, e in ipairs(P.meshes) do if e.sc then onSc = onSc + 1 end end
    P.onScalers = onSc
    if not quiet then log(string.format("special: VALKA's portal opens at (%.1f, %.1f) km, %.1f km up, facing %.0f, %.0f m across: %d mesh parts, %d on their scalers (the engine's every frame) (%s)",
        at.X / 100000, at.Y / 100000, at.Z / 100000, P.yaw, P.size / 100, #P.meshes, onSc, table.concat(said, ", "))) end
    SPC.V.portalFx(c, s, "open")
    return true
end
-- its Niagara parts for moment `when` ("open", "burst", "close"), once each; how many came up
function SPC.V.portalFx(c, s, when)
    local P = s.portal
    local pc = P and P.pc or c.portal
    if not (P and pc) or P.fired[when] then return 0 end
    P.fired[when] = true
    local _, r = portalFrame(P.yaw)
    local n = 0
    for _, part in ipairs(P.parts or pc.parts or {}) do
        if part.fx and (part.at or "open") == when then
            local copies = math.max(1, part.rim or 1)
            for k = 1, copies do
                local p = P.at
                if (part.rim or 0) > 0 then
                    local th = 2 * math.pi * (k - 1) / copies
                    local rad = P.size * (part.rim_r or 0.5)
                    p = { X = P.at.X + rad * math.cos(th) * r.X, Y = P.at.Y + rad * math.cos(th) * r.Y, Z = P.at.Z + rad * math.sin(th) }
                end
                n = n + fxAt({ part.fx }, p, part.scale or 1, part.life or ((pc.open_s or 3) + (pc.hold_s or 2) + 4))
            end
        end
    end
    SPC.V.PORTAL_STATS.fx = SPC.V.PORTAL_STATS.fx + n
    if pc == c.portal then log(string.format("special: VALKA's portal: %d effect(s) at its %s", n, when)) end
    return n
end
-- every tick: open (grow), hold, close (shrink), gone; the rings turning
function SPC.V.portalTick(c, s, now)
    local P = s.portal
    local pc = P and P.pc or c.portal
    if not P then return end
    if not liveObj(P.actor) then s.portal = nil; return end
    local open, close = math.max(0.1, tonumber(pc.open_s) or 3), math.max(0.1, tonumber(pc.close_s) or 2)
    -- ((2026-11-22) the user: "Have a Portal Opening animation too where it opens and have a closing animation too")
    -- each piece grows in its own window of the opening (part.open = { from, to }, shares of open_s: a pinpoint of
    -- light first, the shadow out of it, the disk unfurling ring by ring from the inside, the lensed arcs last) and
    -- collapses in its own window of the closing (part.close: the outer disk first, falling inwards, the shadow, the
    -- photon ring snapping shut last); the disk spins up as it opens (x0.15 -> 1) and faster as it drains (-> x4);
    -- `flare` pieces burn bright as it opens and once more as it shuts
    local x, y = 1, nil                                  -- (the opening's share done; the closing's)
    if P.phase == "open" or P.phase == "hold" then
        x = math.min(1, (now - P.from) / open)
        if x >= 1 and P.phase == "open" then P.phase = "hold" end
        if P.closeAt and now >= P.closeAt then P.phase, P.closeFrom = "close", now; SPC.V.portalFx(c, s, "close") end
        if not P.closeAt and now - P.from > (tonumber(pc.max_s) or 30) then P.closeAt = now end   -- (never left open)
    end
    if P.phase == "close" then
        y = math.min(1, (now - (P.closeFrom or now)) / close)
        if y >= 1 then
            SPC.V.portalStop(s)
            if pc == c.portal then log("special: VALKA's portal closed") end
            return
        end
    end
    local dt = math.min(0.5, now - (P.lastTick or now))
    P.lastTick = now
    -- ((2026-11-22) `face_you`: the whole hole turned to you each tick (its lensed arcs always face whoever looks), each
    -- piece set again and turned by its own spin so far)
    local turn = false
    if pc.face_you then
        -- (the camera you see through, not your plane: her reveal's focus camera looks from beside, the run of 14:26
        -- showed the arcs edge-on there; your plane's place when the camera can't be read)
        local you = nil
        pcall(function()
            local v = survivalPC.PlayerCameraManager:GetCameraLocation()
            if v and v.X then you = { X = v.X, Y = v.Y, Z = v.Z } end
        end)
        you = you or (playerLocation and playerLocation())
        if you then
            local yaw = math.deg(math.atan(you.Y - P.at.Y, you.X - P.at.X))
            if math.abs(((yaw - P.yaw + 540) % 360) - 180) > 0.3 then P.yaw, turn = yaw, true end
        end
    end
    local spinK = y and (1 + 3 * y) or (0.15 + 0.85 * x)
    for _, e in ipairs(P.meshes) do
        if e.sc and liveObj(e.comp) then                -- (on its scaler: the engine scales and spins it every frame)
            -- (shown once into its window and 0.3 s on: the engine has run its grow by then (0.75.23's probe: full size before))
            if e.hold and e.grown and now > P.from + 0.3 then e.hold = nil; pcall(function() e.comp:SetVisibility(true, false) end) end
            if e.hold and y then e.hold = nil end         -- (closing before it was ever shown: left hidden)
            if y then
                local w = e.part.close
                local from = (P.closeFrom or now) + (w and w[1] or 0) * close
                if not e.shrunk and now >= from then       -- (its grow played backwards from where it is: falling in)
                    e.shrunk = true
                    -- ((2026-11-22) "it doesn't have an closing animation": a grow that had ended was stopped, and a rate
                    -- alone never restarts it: played again, backwards, from where it is)
                    local pos = 1
                    pcall(function() pos = e.sc:GetPosition() end)
                    if not pos or pos <= 0.0001 then pos = 1 end
                    pcall(function() e.sc:SetPosition(math.min(1, pos), false) end)
                    pcall(function() e.sc:SetPlayRate(-1 / math.max(0.05, ((w and (w[2] - w[1])) or 1) * close)) end)
                    pcall(function() e.sc:Play(false) end)
                end
            elseif not e.grown then
                local w = e.part.open
                if now >= P.from + (w and w[1] or 0) * open then
                    e.grown = true
                    scalerGo(e, nil, ((w and (w[2] - w[1])) or 1) * open, false)
                end
            end
            SPC.V.portalSpin(e, spinK)
            local bright = 1
            if y and e.part.flare then bright = 1 + 4 * math.max(0, math.min(1, (y - 0.55) / 0.35))
            elseif not y and e.part.flare then bright = 1 + 3 * (1 - math.max(0, math.min(1, x / 0.45))) end
            if e.mid and e.color and (e.pulse or bright ~= 1) then
                local f = bright
                if e.pulse then
                    local amp, hz = tonumber(e.pulse[1]) or 0, tonumber(e.pulse[2]) or 1
                    f = f * (1 + amp * (0.6 * math.sin(6.283 * hz * now + e.ph) + 0.4 * math.sin(6.283 * hz * 2.37 * now + 1.7 * e.ph)))
                end
                local cc = e.color
                pcall(function() e.mid:SetVectorParameterValue(FName("Color"), { R = cc[1] * f, G = cc[2] * f, B = cc[3] * f, A = cc[4] or 1 }) end)
            end
            if turn then pcall(function() e.sc:K2_SetWorldRotation(portalRot(e.part, P.yaw), false, {}, true) end) end
        elseif liveObj(e.comp) then
            local gi, bright = 1, 1
            if y then
                local w = e.part.close
                local z = w and (y - w[1]) / math.max(0.01, w[2] - w[1]) or y
                z = math.max(0, math.min(1, z))
                gi = 1 - z * z                           -- (falling in faster and faster)
                if e.part.flare then bright = 1 + 4 * math.max(0, math.min(1, (y - 0.55) / 0.35)) end
            else
                local w = e.part.open
                local z = w and (x - w[1]) / math.max(0.01, w[2] - w[1]) or x
                z = math.max(0, math.min(1, z))
                gi = 1 - (1 - z) ^ 3                     -- (out fast, settling)
                if e.part.flare then bright = 1 + 3 * (1 - math.max(0, math.min(1, x / 0.45))) end
            end
            local k = math.max(0.001, e.k * gi)
            pcall(function() e.comp:SetWorldScale3D({ X = k, Y = k, Z = k * e.flat }) end)
            if e.mid and e.color and (e.pulse or bright ~= 1) then
                local f = bright
                if e.pulse then
                    local amp, hz = tonumber(e.pulse[1]) or 0, tonumber(e.pulse[2]) or 1
                    f = f * (1 + amp * (0.6 * math.sin(6.283 * hz * now + e.ph) + 0.4 * math.sin(6.283 * hz * 2.37 * now + 1.7 * e.ph)))
                end
                local cc = e.color
                pcall(function() e.mid:SetVectorParameterValue(FName("Color"), { R = cc[1] * f, G = cc[2] * f, B = cc[3] * f, A = cc[4] or 1 }) end)
            end
            if e.spin ~= 0 and dt > 0 then e.spun = (e.spun + e.spin * spinK * dt) % 360 end
            if turn then
                pcall(function()
                    e.comp:K2_SetWorldRotation(portalRot(e.part, P.yaw), false, {}, true)
                    if e.spun ~= 0 then e.comp:K2_AddLocalRotation({ Pitch = 0, Yaw = e.spun, Roll = 0 }, false, {}, true) end
                end)
            elseif e.spin ~= 0 and dt > 0 then
                local d = e.spin * spinK * dt
                pcall(function()
                    if e.axis == "x" then e.comp:K2_AddLocalRotation({ Pitch = 0, Yaw = 0, Roll = d }, false, {}, true)
                    else e.comp:K2_AddLocalRotation({ Pitch = 0, Yaw = d, Roll = 0 }, false, {}, true) end
                end)
            end
        end
    end
end
-- she's through: its burst now, closed hold_s later
function SPC.V.portalThrough(c, s, now)
    local P = s.portal
    if not P then return end
    SPC.V.portalFx(c, s, "burst")
    P.closeAt = now + (tonumber(P.pc and P.pc.hold_s or c.portal.hold_s) or 2)
end
-- ((2026-11-22) her blinks through small portals, CFG.specials.valka.blink_portal: one where she vanishes, one where she
-- comes back, each opening, holding hold_s and closing on its own) one at `at` facing `yaw`
function SPC.V.blinkPortal(c, s, at, yaw, now)
    local bp = c.blink_portal
    if not (type(bp) == "table" and bp.enabled and at) then return false end
    s.bportals = s.bportals or {}
    if #s.bportals >= 6 then return false end            -- (never a pile of them)
    local h = {}
    local ok, up = pcall(SPC.V.portalOpen, c, h, at, yaw, now, bp, true)
    if not (ok and up and h.portal) then return false end
    h.portal.closeAt = now + (tonumber(bp.open_s) or 0.3) + (tonumber(bp.hold_s) or 0.6)
    s.bportals[#s.bportals + 1] = h
    SPC.V.portalFx(c, h, "burst")
    if COOP and COOP.valkaBlinkPortal and COOP.host and COOP.host() then pcall(COOP.valkaBlinkPortal, at, yaw) end
    return true
end
function SPC.V.blinkPortalsTick(c, s, now)
    if not s.bportals then return end
    local keep = {}
    for _, h in ipairs(s.bportals) do
        pcall(SPC.V.portalTick, c, h, now)
        if h.portal then keep[#keep + 1] = h end
    end
    s.bportals = #keep > 0 and keep or nil
end
function SPC.V.blinkPortalsStop(s)
    for _, h in ipairs(s and s.bportals or {}) do pcall(SPC.V.portalStop, h) end
    if s then s.bportals = nil end
end
-- where she comes out of it: exit_back_m behind its face, so she flies out through it
function SPC.V.portalExit(c, at, yaw)
    local f = portalFrame(yaw)
    local back = (tonumber(c.portal and c.portal.exit_back_m) or 150) * 100
    return { X = at.X - f.X * back, Y = at.Y - f.Y * back, Z = at.Z, km = at.km }
end
function SPC.V.portalStop(s)
    local P = s and s.portal
    if not P then return end
    if not (levelTorn and levelTorn()) and liveObj(P.actor) then pcall(function() P.actor:K2_DestroyActor() end) end
    s.portal = nil
end
end
