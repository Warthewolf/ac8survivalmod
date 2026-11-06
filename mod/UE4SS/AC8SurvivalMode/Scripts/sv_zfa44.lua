-- sv_zfa44.lua : the ZFA-44's look on an AI plane (ZFA.dress / ZFA.undress: the escort's carriers' flights, sv_escort.lua) and its test T0 (Ctrl+9, test code); cut to this line in every zip (no ZFA-44 container there: the carriers' planes fly as their host airframe).
-- The ZFA-44EL is the user's own edited CFA-44 from their AC7 mod Alicorn Special Raid IV (AGENTS.md's exception of
-- 2026-11-06), cooked for AC8 by tools/zfa44 into its own container SurvivalMode_ZFA44_P, which only the user's dev
-- builds carry (ZFA=1 sh tools/package_dev.sh). tools/re/ZFA44.md "T0 build"; tools/re/ESCORT.md for the carriers.
--
-- The dressing (production, outside the test block; every game dresses its own planes and copies): ZFA.dress(plane,
-- { paint = k, label = text }) puts the ZFA-44 on an AI plane the way SPC.V.model dresses VALKA (hard rule 46): a
-- SkeletalMeshComponent added to it (no collision, fixed bounds), SK_ZFA44 on it, placed on the host's body mesh,
-- painted (ZFA.PAINTS[k]), the host's own meshes hidden (again every ZFA.C.hide_s, one plane a tick: ZFA.prodTick).
-- ZFA.undress(plane) takes it off again. Without SK_ZFA44 (a build without the container) nothing is dressed, once a
-- minute tried again, said once a level. Log lines `zfa44: dressed ...`, `zfa44: NOT dressed ...`, `zfa44: undressed ...`.
--
-- T0 (test code, the test block below; Ctrl+9 in a run): VALKA's x40a when she's up, else the nearest live enemy
-- aircraft, dressed on the next paint variant; pressed again: undone. Log lines `zfa44: T0 ...`: what was dressed and how,
-- the component and mesh, each slot's material and its parent, the bounds against the host's body, the ZFA-44's
-- burner_01 / _02 against the host's nozzle sockets and effects (metres in the host's frame: forward, right, up), then
-- the same at +2 / +10 / +30 s and at the host's death. Every step is a crash breadcrumb first (crumb:
-- AC8SurvivalMode_crumbs.log), as SOLG T0 did.

ZFA = { cur = nil, paintNext = nil, assets = {}, flat = {}, dressed = {}, H = {} }
ZFA.C = {
    mesh = "/Game/Mods/SurvivalMode/ZFA44/Model/SK_ZFA44",
    tex = "/Game/Mods/SurvivalMode/ZFA44/Textures/",
    gear = "/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear",   -- (FALKEN_MATERIALS.md)
    default_normal = "/Engine/EngineMaterials/DefaultNormal",
    paint = 1,                              -- T0's first dressing's variant (ZFA.PAINTS); each later one the next
    yaw = 0,                                -- turned this much more than the host's body mesh (degrees)
    offset_cm = { X = 0, Y = 0, Z = 0 },    -- moved this far in the host's frame (forward, right, up)
    scale = 1.0,                            -- 1: life size, 24.0 m long, 14.6 m span (tools/zfa44/prepare.py)
    hide_s = 2.0,                           -- the host's meshes hidden again this often (T0; the dressing's: CFG)
    checks_s = { 2, 10, 30 },               -- T0's follow-up lines, this long after the dressing
    missing_again_s = 60,                   -- no SK_ZFA44: tried again this long after
    skip = { "^SV_Unit_Ladon", "Alicorn", "^SV_Unit_Coop", "Eml", "SOLG" },   -- never a T0 host (big ones, stand-ins, dummies)
}
-- each slot's textures by the cooked material it holds (tools/zfa44/ue_import.py PAINT); the canopy keeps AC8's
-- M_NPC_Canopy unless a variant tints it
ZFA.SLOT_TEX = { Body = { "T_ZFA44_C", "T_ZFA44_N" }, Pod = { "T_ZFA44_Pod_C", "T_ZFA44_Pod_N" },
                 Fairing = { "T_ZFA44_Fair_C", "T_ZFA44_Fair_N" } }
ZFA.SCALARS = { Ctrl_All_Emissive = 0, Turbine_speed = 0, DNormal_Strength = 0, DamegedNormal_Intencity = 0,
                PlayerPlane_Damage = 0 }
-- (3, the gear instance with a flat normal, is the route proven to draw: the Falken's exactly, VALKA's paint 16, SOLG
-- T0b's; 1, the cooked instances, was never tried: tools/re/ZFA44.md 8.6)
ZFA.PAINTS = {
    { name = "COOKED" },                                        -- MI_ZFA44_* as built, on the game's own gear instance
    { name = "GEAR, ITS NORMALS", mids = true },                -- the same at run time (VALKA's paint 15, SOLG T0b's way)
    { name = "GEAR, FLAT NORMAL", mids = true, flat = true },   -- the Falken's exactly (VALKA's paint 16)
    { name = "GEAR, MREC LIVEMAP, CANOPY TINTED", mids = true, livemap = "T_ZFA44_LM_MREC",
      canopy = { Basecolor = "rt:0.05,0.045,0.03", Livemap = "rt:0.6,0.15,1" } },
}
-- the host's sockets an afterburner hangs on (VALKA's x40a aliases: DT_OP0016_x40a_FX_MapTable), looked up on each of its
-- meshes; its effect components (where its flames really are)
ZFA.NOZZLES = { "burner_01", "burner_02", "SOC_EF_Burner_01", "SOC_EF_Burner_02", "core01", "core02" }
ZFA.FX = { "/Script/Niagara.NiagaraComponent", "/Script/Engine.ParticleSystemComponent" }

do
    local SKC = "/Script/Engine.SkeletalMeshComponent"
    local function step(s) crumb("zfa44: " .. s) end
    local function short(o) return nameOf(o):match("([%w_]+)$") or "?" end
    local function v3(v) return { X = v.X, Y = v.Y, Z = v.Z } end

    -- a /Game/ or /Engine/ asset by package path, kept while it's a live object (the hard-rule-9 load: loadObject)
    local function asset(path)
        local full = path .. "." .. path:match("[^/]+$")
        local o = ZFA.assets[full]
        if o ~= nil and liveObj(o) then return o end
        ZFA.assets[full] = nil
        local why
        o, why = loadObject(full)
        if o ~= nil and valid(o) then ZFA.assets[full] = o; return o end
        return nil, why
    end
    -- "rt:R,G,B": a 4 x 4 render target of that colour (VALKA's flatTexture; the level's, dropped with it)
    local function flatTex(spec)
        local t = ZFA.flat[spec]
        if t ~= nil and liveObj(t) then return t end
        local r, g, b = spec:match("^rt:([%d%.]+),([%d%.]+),([%d%.]+)$")
        local krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
        if not r or not valid(krl) or not liveObj(survivalPC) then return nil end
        local col = { R = tonumber(r), G = tonumber(g), B = tonumber(b), A = 1 }
        local ok, rt = pcall(function() return krl:CreateRenderTarget2D(survivalPC, 4, 4, 2, col, false, false) end)
        if not (ok and valid(rt)) then return nil end
        pcall(function() krl:ClearRenderTarget2D(survivalPC, rt, col) end)
        ZFA.flat[spec] = rt
        return rt
    end

    -- the host's body mesh (a PlaneBody* property, as SPC.V.addBody places VALKA's), else nil (its root then)
    local function bodyRef(o, mine)
        for _, n in ipairs(SPC.V.BODY_PROPS) do
            local okP, p = pcall(function() return o[n] end)
            if okP and p and liveObj(p) and addrOf(p) ~= mine then return p, n end
        end
        return nil, "its root"
    end
    local function place(s)
        local C, comp, o, ref = ZFA.C, s.comp, s.host, s.ref
        return pcall(function()
            local l, r
            if ref and liveObj(ref) then l, r = ref:K2_GetComponentLocation(), ref:K2_GetComponentRotation()
            else l, r = o:K2_GetActorLocation(), o:K2_GetActorRotation() end
            local f, rt, up, d = o:GetActorForwardVector(), o:GetActorRightVector(), o:GetActorUpVector(), C.offset_cm
            comp:K2_SetWorldLocationAndRotation({ X = l.X + f.X * d.X + rt.X * d.Y + up.X * d.Z,
                                                  Y = l.Y + f.Y * d.X + rt.Y * d.Y + up.Y * d.Z,
                                                  Z = l.Z + f.Z * d.X + rt.Z * d.Y + up.Z * d.Z },
                { Pitch = r.Pitch, Yaw = r.Yaw + C.yaw, Roll = r.Roll }, false, {}, true)
            if C.scale ~= 1 then comp:SetRelativeScale3D({ X = C.scale, Y = C.scale, Z = C.scale }) end
        end)
    end

    -- the host's meshes but ours hidden (VALKA's modelHide), each one hidden recorded to show again; how many this time
    local function hide(s)
        local o, me, n = s.host, addrOf(s.comp), 0
        local function one(comp)
            local a = liveAddr(comp)
            if not a or a == me then return end
            local okV, vis = pcall(function() return comp:IsVisible() end)
            if okV and vis and pcall(function() comp:SetVisibility(false, false) end) then
                n = n + 1
                if not s.hidden[a] then s.hidden[a] = { obj = comp, name = short(comp) } end
            end
        end
        for _, cls in ipairs({ "/Script/Engine.StaticMeshComponent", SKC }) do
            for _, comp in ipairs(SPC.V.comps(o, cls)) do one(comp) end
        end
        for _, k in ipairs({ "PilotMeshComponent", table.unpack(SPC.V.BODY_PROPS) }) do
            local ok, comp = pcall(function() return o[k] end)
            if ok and comp then one(comp) end
        end
        return n
    end

    -- each slot's kind by the cooked material it holds
    local function slotKind(m)
        local n = nameOf(m)
        for _, kind in ipairs({ "Body", "Pod", "Fairing" }) do
            if n:find("MI_ZFA44_" .. kind, 1, true) then return kind end
        end
        if n:find("M_NPC_Canopy", 1, true) then return "Canopy" end
        return nil
    end
    local function slotsOf(comp)
        local out, n = {}, 0
        pcall(function() n = comp:GetNumMaterials() end)
        for i = 0, n - 1 do
            local ok, m = pcall(function() return comp:GetMaterial(i) end)
            out[i] = { m = ok and m or nil, kind = ok and m and slotKind(m) or nil }
        end
        return out, n
    end
    -- paint variant k on the ZFA-44 (fresh run-time instances each time); what it did
    local function paint(s, k)
        local C, pv = ZFA.C, ZFA.PAINTS[k]
        for i = 0, (s.nSlots or 0) - 1 do                   -- (the slots as built first)
            local m = s.slots[i] and s.slots[i].m
            if m and liveObj(m) then pcall(function() s.comp:SetMaterial(i, m) end) end
        end
        if not pv.mids then return "as built" end
        local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local gear, why = asset(C.gear)
        local dn = asset(C.default_normal)
        local lm = asset(C.tex .. (pv.livemap or "T_ZFA44_LM"))
        if not (valid(kml) and gear) then return "NOT painted: " .. C.gear:match("[^/]+$") .. " " .. tostring(why) end
        local wc = liveObj(survivalPC) and survivalPC or s.host
        local said, bad = {}, {}
        for i = 0, (s.nSlots or 0) - 1 do
            local kind = s.slots[i] and s.slots[i].kind
            local tx = kind and ZFA.SLOT_TEX[kind]
            local tint = kind == "Canopy" and pv.canopy or nil
            if tx or tint then
                local okM, mid = pcall(function() return kml:CreateDynamicMaterialInstance(wc, gear, FName("None"), 0) end)
                if okM and valid(mid) then
                    local want = {}
                    if tx then
                        want.Basecolor = asset(C.tex .. tx[1])
                        want.Normalmap = pv.flat and dn or asset(C.tex .. tx[2])
                        want.Livemap = lm
                    else
                        want.Basecolor, want.Livemap, want.Normalmap = flatTex(tint.Basecolor), flatTex(tint.Livemap), dn
                    end
                    want.Detail_Normal, want.Blend_Dameged_Normalmap = dn, dn
                    local miss = {}
                    for pn, t in pairs(want) do
                        local ok = false
                        if t then ok = pcall(function() mid:SetTextureParameterValue(FName(pn), t) end) end
                        if not ok then miss[#miss + 1] = pn end
                    end
                    for pn, v in pairs(ZFA.SCALARS) do pcall(function() mid:SetScalarParameterValue(FName(pn), v) end) end
                    if pv.flat then pcall(function() mid:SetScalarParameterValue(FName("NormalIntencity"), 0) end) end
                    if pcall(function() s.comp:SetMaterial(i, mid) end) then
                        said[#said + 1] = tostring(kind) .. (#miss > 0 and (" (NOT set: " .. table.concat(miss, " ") .. ")") or "")
                    else
                        bad[#bad + 1] = tostring(kind)
                    end
                else
                    bad[#bad + 1] = tostring(kind) .. " (no instance)"
                end
            end
        end
        return string.format("instances of %s on %s%s, Normalmap %s, Livemap %s", short(gear),
            #said > 0 and table.concat(said, ", ") or "no slot", #bad > 0 and (", NOT on " .. table.concat(bad, ", ")) or "",
            pv.flat and "DefaultNormal (NormalIntencity 0)" or "its own", pv.livemap or "T_ZFA44_LM (flat 0 / 0.75 / 1)")
    end
    local function paintIndex(k) k = math.floor(tonumber(k) or 1); return ((k - 1) % #ZFA.PAINTS) + 1 end

    -- The ZFA-44 built on plane o with paint variant k: the component added, the mesh set, placed and painted (the
    -- host's meshes not hidden yet). Its record { host, comp, slots, ref, ... }, or nil and why. A crumb before each step.
    function ZFA.build(o, k, tag)
        local C = ZFA.C
        tag = tag or ""
        step(tag .. "loading SK_ZFA44")
        local sk, why = asset(C.mesh)
        if not sk then return nil, string.format("%s not loaded (%s): is SurvivalMode_ZFA44_P installed?", C.mesh, tostring(why)), true end
        local cls = StaticFindObject(SKC)
        if not valid(cls) then return nil, "no SkeletalMeshComponent class" end
        step(tag .. "adding a SkeletalMeshComponent to " .. short(o))
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okC, comp = pcall(function() return o:AddComponentByClass(cls, false, t, false) end)
        if not (okC and comp and valid(comp)) then
            return nil, "AddComponentByClass on " .. short(o) .. " " .. (okC and "gave nothing" or tostring(comp))
        end
        pcall(function() comp:SetCollisionEnabled(0) end)                 -- (ECollisionEnabled NoCollision: its spheres hit)
        local fixed = pcall(function() comp.bComponentUseFixedSkelBounds = true end)   -- (the mesh's bounds, not the PA's)
        step(tag .. "setting SK_ZFA44 on it")
        local okM = pcall(function() comp:SetSkeletalMeshAsset(sk) end) or pcall(function() comp:SetSkeletalMesh(sk, true) end)
        if not okM then
            pcall(function() comp:K2_DestroyComponent(comp) end)
            return nil, "SK_ZFA44 not set on the component (taken off again)"
        end
        k = paintIndex(k)
        local s = { host = o, hostAddr = addrOf(o), hostName = short(o), at = os.clock(), comp = comp, hidden = {}, hideAt = 0,
                    done = {}, back = 0, paintK = k, sk = sk, fixed = fixed }
        s.slots, s.nSlots = slotsOf(comp)
        s.ref, s.refBy = bodyRef(o, addrOf(comp))
        step(tag .. "placing it")
        s.placed = place(s)
        step(tag .. "painting it: " .. ZFA.PAINTS[k].name)
        s.painted = paint(s, k)
        return s
    end
    -- the record's component taken off its host (destroyed, else hidden) and the host's hidden meshes shown again
    -- (skipShow: VALKA's T0 handles hers); whether it was destroyed and how many meshes came back
    function ZFA.strip(s, skipShow)
        local shown = 0
        if not skipShow and liveObj(s.host) then
            for _, h in pairs(s.hidden) do
                if liveObj(h.obj) and pcall(function() h.obj:SetVisibility(true, false) end) then shown = shown + 1 end
            end
        end
        local gone = false
        if liveObj(s.comp) then
            gone = pcall(function() s.comp:K2_DestroyComponent(s.comp) end)
            if not gone then pcall(function() s.comp:SetVisibility(false, false) end) end
        end
        return gone, shown
    end

    -- (production) the ZFA-44 on AI plane o (opts.paint: its variant; opts.label: the log's name for it): true and what
    -- was done, or false and why. Each plane once (by its address, ZFA.dressed); its meshes hidden again by ZFA.prodTick.
    function ZFA.dress(o, opts)
        opts = opts or {}
        local a = liveAddr(o)
        if not a then return false, "not a live object" end
        if ZFA.dressed[a] and liveObj(ZFA.dressed[a].host) and ZFA.dressed[a].hostAddr == a then return true, "already dressed" end
        ZFA.dressed[a] = nil
        if ZFA.missingAt and os.clock() - ZFA.missingAt < (ZFA.C.missing_again_s or 60) then return false, ZFA.missingWhy end
        local s, why, missing = ZFA.build(o, opts.paint or 3, "dress: ")
        if not s then
            if missing then
                ZFA.missingAt, ZFA.missingWhy = os.clock(), why
                if not ZFA.missingSaid then
                    ZFA.missingSaid = true
                    log("zfa44: NOT dressed: " .. tostring(why) .. "; the ZFA-44s fly as their host airframe (tried again every "
                        .. tostring(ZFA.C.missing_again_s or 60) .. " s)")
                end
            else
                log(string.format("zfa44: %s (%s) NOT dressed: %s", short(o), tostring(opts.label or "?"), tostring(why)))
            end
            return false, why
        end
        s.prod, s.label, s.hideS = true, opts.label, tonumber(opts.hide_s) or ZFA.C.hide_s
        local n = hide(s)
        s.hideAt = os.clock() + s.hideS
        ZFA.dressed[a] = s
        ZFA.dressedN = (ZFA.dressedN or 0) + 1
        local pv = ZFA.PAINTS[s.paintK]
        if ZFA.dressedN <= 4 or ZFA.dressedN % 20 == 0 then
            log(string.format("zfa44: dressed %s (%s) as the ZFA-44 (%d so far): placed on %s%s, paint %d %s: %s; %d of its meshes hidden",
                s.hostName, tostring(opts.label or "?"), ZFA.dressedN, s.refBy, s.placed and "" or " (NOT placed)", s.paintK, pv.name,
                tostring(s.painted), n))
        end
        return true, string.format("paint %d %s, %d meshes hidden", s.paintK, pv.name, n)
    end
    -- (production) the ZFA-44 off plane o again: true when it had one
    function ZFA.undress(o)
        local a = addrOf(o)
        local s = a and ZFA.dressed[a]
        if not s then return false end
        ZFA.dressed[a] = nil
        if not (liveObj(s.host) and addrOf(s.host) == s.hostAddr) then return false end
        local gone, shown = ZFA.strip(s)
        log(string.format("zfa44: undressed %s (%s): the ZFA-44 %s, %d of its meshes shown again", s.hostName, tostring(s.label or "?"),
            gone and "destroyed" or "hidden", shown))
        return true
    end
    -- (production, every tick on every game: sv_escort.lua ESC.tick) at most two dressed planes a call get their own
    -- meshes hidden again (VALKA's came back on); a gone one is dropped, never read again; one at 0 health left as it is
    function ZFA.prodTick()
        local now, n = os.clock(), 0
        for a, s in pairs(ZFA.dressed) do
            if liveAddr(s.host) ~= a then
                ZFA.dressed[a] = nil
            elseif n < 2 and now >= (s.hideAt or 0) then
                n = n + 1
                s.hideAt = now + (s.hideS or ZFA.C.hide_s)
                local okH, h = pcall(function() return s.host.HealthInternal end)
                if not (okH and type(h) == "number" and h <= 0) and liveObj(s.comp) then
                    local back = hide(s)
                    if back > 0 and not s.backSaid then
                        s.backSaid = true
                        log(string.format("zfa44: %d of %s's meshes came back on and were hidden again", back, s.hostName))
                    end
                end
            end
        end
    end
    function ZFA.dressedCount() local k = 0; for _ in pairs(ZFA.dressed) do k = k + 1 end; return k end
    -- (for the test block below)
    ZFA.H = { SKC = SKC, step = step, short = short, v3 = v3, hide = hide, paint = paint, slotsOf = slotsOf, paintIndex = paintIndex }
end
if type(LEVEL_DROPS) == "table" then                         -- (the level's objects: forgotten, none of them touched)
    LEVEL_DROPS["the ZFA-44 dressings"] = function() ZFA.dressed, ZFA.flat, ZFA.missingAt, ZFA.missingSaid = {}, {}, nil, nil end
end

-- TEST ONLY BEGIN (the ZFA-44's test T0: Ctrl+9, sv_main.lua's test keys; its tick, probeTickB)
do
    local H = ZFA.H
    local SKC, step, short, v3 = H.SKC, H.step, H.short, H.v3

    -- the host's frame: where it is and its axes; a world point in it, metres (forward, right, up)
    local function frame(o)
        local ok, f = pcall(function()
            return { at = v3(o:K2_GetActorLocation()), f = v3(o:GetActorForwardVector()), r = v3(o:GetActorRightVector()),
                     u = v3(o:GetActorUpVector()) }
        end)
        return ok and f or nil
    end
    local function inFrame(F, p)
        local d = { X = p.X - F.at.X, Y = p.Y - F.at.Y, Z = p.Z - F.at.Z }
        local function dot(a) return (d.X * a.X + d.Y * a.Y + d.Z * a.Z) / 100 end
        return { dot(F.f), dot(F.r), dot(F.u) }
    end
    local function fmt(q) return q and string.format("(%.1f, %.1f, %.1f)", q[1], q[2], q[3]) or "?" end
    local function apart(a, b)
        if not (a and b) then return nil end
        return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
    end

    local function skipped(unit)
        for _, pat in ipairs(ZFA.C.skip) do if unit and tostring(unit):find(pat) then return true end end
        return false
    end
    -- VALKA's x40a and her round's state, when she's up
    local function valkaUp()
        local s = D and D.special
        local c = CFG.specials and CFG.specials.valka
        if not (s and s.kind == "valka" and s.state ~= "done" and type(c) == "table") then return nil end
        for _, list in ipairs({ planes, pending }) do
            for _, q in ipairs(list) do
                if q.unit == c.unit and liveObj(q.obj) then return q.obj, s end
            end
        end
        return nil
    end
    -- the nearest live enemy aircraft (the core's `planes`: no allies, wingmen or the shuttle), its record, its km
    local function nearest()
        local you = playerLocation()
        if not you then return nil end
        local best, bp, bd = nil, nil, nil
        for _, p in ipairs(planes) do
            if not p.down and not skipped(p.unit) and liveObj(p.obj) then
                local okH, h = pcall(function() return p.obj.HealthInternal end)
                local okL, l = pcall(function() return v3(p.obj:K2_GetActorLocation()) end)
                if okH and type(h) == "number" and h > 0 and okL and l then
                    local d = km(l, you)
                    if not bd or d < bd then best, bp, bd = p.obj, p, d end
                end
            end
        end
        return best, bp, bd
    end

    -- what each slot holds now: its material and that material's parent
    local function slotsSay(s)
        local out = {}
        for i = 0, (s.nSlots or 0) - 1 do
            local ok, m = pcall(function() return s.comp:GetMaterial(i) end)
            local par = "?"
            if ok and m and liveObj(m) then
                local okP, p = pcall(function() return m.Parent end)
                par = (okP and p and liveObj(p)) and nameOf(p):match("([^%s]+)$") or "none"
            end
            out[#out + 1] = string.format("%d %s: %s (parent %s)", i, tostring(s.slots[i] and s.slots[i].kind or "?"),
                ok and m and short(m) or "nothing", par)
        end
        return table.concat(out, "; ")
    end

    -- the ZFA-44's burners and size against the host's nozzles, effects and body, in the host's frame (metres)
    local function report(s, label)
        local o, comp = s.host, s.comp
        local F = frame(o)
        if not F then log("zfa44: T0 " .. label .. ": the host's frame not read"); return end
        local ours, parts = {}, {}
        for _, n in ipairs({ "burner_01", "burner_02", "cam_nose", "vapor01" }) do
            local ok, l = pcall(function() return v3(comp:GetSocketLocation(FName(n))) end)
            ours[n] = ok and l and inFrame(F, l) or nil
        end
        local host = {}                                      -- the host's nozzle sockets, on whichever mesh has them
        for _, cls in ipairs({ "/Script/Engine.StaticMeshComponent", SKC }) do
            for _, mc in ipairs(SPC.V.comps(o, cls)) do
                if addrOf(mc) ~= addrOf(comp) then
                    for _, n in ipairs(ZFA.NOZZLES) do
                        if not host[n] then
                            local okE, e = pcall(function() return mc:DoesSocketExist(FName(n)) end)
                            if okE and e then
                                local okL, l = pcall(function() return v3(mc:GetSocketLocation(FName(n))) end)
                                if okL and l then host[n] = { at = inFrame(F, l), on = short(mc) } end
                            end
                        end
                    end
                end
            end
        end
        for _, n in ipairs({ "burner_01", "burner_02" }) do
            local alias = n == "burner_01" and { "burner_01", "SOC_EF_Burner_01", "core01" } or { "burner_02", "SOC_EF_Burner_02", "core02" }
            local h, hn = nil, nil
            for _, a in ipairs(alias) do if not h and host[a] then h, hn = host[a], a end end
            local d = h and apart(ours[n], h.at)
            parts[#parts + 1] = string.format("%s %s m%s", n, fmt(ours[n]),
                h and string.format(" vs the host's %s %s m on %s: %.1f m apart", hn, fmt(h.at), h.on, d or -1)
                or " (the host has no nozzle socket of that side)")
        end
        local found = {}
        for _, n in ipairs(ZFA.NOZZLES) do if host[n] then found[#found + 1] = n end end
        local fx = {}                                        -- the host's effects (its flames are where these are)
        for _, cls in ipairs(ZFA.FX) do
            for _, c in ipairs(SPC.V.comps(o, cls)) do
                if #fx < 10 then
                    local okS, sock = pcall(function() return c:GetAttachSocketName():ToString() end)
                    local okL, l = pcall(function() return v3(c:K2_GetComponentLocation()) end)
                    local okV, vis = pcall(function() return c:IsVisible() end)
                    fx[#fx + 1] = string.format("%s@%s %s m%s", short(c), okS and sock or "?", okL and fmt(inFrame(F, l)) or "?",
                        okV and not vis and " (hidden)" or "")
                end
            end
        end
        local function bounds(c)
            local ok, b = pcall(function()
                local q = c.Bounds
                return string.format("sphere %.1f m, box %.1f x %.1f x %.1f m", q.SphereRadius / 100, q.BoxExtent.X / 50,
                    q.BoxExtent.Y / 50, q.BoxExtent.Z / 50)
            end)
            return ok and b or "?"
        end
        local okV, vis = pcall(function() return comp:IsVisible() end)
        local okSp, kmh = pcall(function() local q = o:GetVelocity(); return math.sqrt(q.X ^ 2 + q.Y ^ 2 + q.Z ^ 2) * 0.036 end)
        log(string.format("zfa44: T0 %s: on %s at %.0f km/h, the ZFA-44 %s, %s (the host's body %s %s); nose %s m, "
            .. "left wing tip %s m", label, s.hostName, okSp and kmh or -1, okV and (vis and "visible" or "HIDDEN") or "?",
            bounds(comp), s.refBy, s.ref and liveObj(s.ref) and bounds(s.ref) or "?", fmt(ours.cam_nose), fmt(ours.vapor01)))
        log(string.format("zfa44: T0 %s: %s; the host's nozzle sockets %s; its effects %s", label, table.concat(parts, "; "),
            #found > 0 and table.concat(found, " ") or "none found", #fx > 0 and table.concat(fx, ", ") or "none found"))
    end

    function ZFA.t0Dress(o, how, vs)
        local C = ZFA.C
        local k = H.paintIndex(ZFA.paintNext or C.paint)
        ZFA.paintNext = (k % #ZFA.PAINTS) + 1
        local pv = ZFA.PAINTS[k]
        local s, why, missing = ZFA.build(o, k, "T0 ")
        if not s then
            log("zfa44: T0: " .. tostring(why))
            if type(hudCallout) == "function" then
                hudCallout(missing and "TEST: ZFA-44 NOT INSTALLED" or "TEST: ZFA-44 NOT DRESSED", missing and "SurvivalMode_ZFA44_P" or nil)
            end
            return false
        end
        s.how = how
        ZFA.cur = s
        if vs then                                           -- VALKA: her X-02S hidden with the x40a's meshes while we're on
            s.valka, s.valkaComp, s.valkaSweep = vs, vs.modelComp, vs.sweepLen
            vs.modelComp, vs.sweepLen = s.comp, nil          -- (her modelTick keeps ours shown, hers hidden, no sweep on ours)
        end
        step("T0 hiding the host's meshes")
        local n = H.hide(s)
        s.hideAt = os.clock() + C.hide_s
        step("T0 dressed")
        local okRel, rel = pcall(function()
            local a, r = o:K2_GetActorRotation(), s.ref and s.ref:K2_GetComponentRotation()
            return r and string.format("%.0f / %.0f / %.0f", r.Pitch - a.Pitch, r.Yaw - a.Yaw, r.Roll - a.Roll) or "-"
        end)
        local names = {}
        for _, h in pairs(s.hidden) do names[#names + 1] = h.name end
        table.sort(names)
        log(string.format("zfa44: T0: %s (%s) dressed as the ZFA-44: a %s added (collision off, fixed bounds %s), %s on it, "
            .. "placed on %s%s (its rotation against the actor %s deg; yaw +%g, offset %g / %g / %g cm, scale %g); paint %d %s: %s; "
            .. "%d of its meshes hidden (%s)%s", s.hostName, how, s.comp:GetClass():GetFName():ToString(), s.fixed and "on" or "NOT set",
            nameOf(s.sk):match("([^%s]+)$") or C.mesh, s.refBy, s.placed and "" or " (NOT placed)", okRel and rel or "?",
            C.yaw, C.offset_cm.X, C.offset_cm.Y, C.offset_cm.Z, C.scale, k, pv.name, tostring(s.painted), n, table.concat(names, ", "),
            vs and "; VALKA's X-02S hidden while it's on" or ""))
        log(string.format("zfa44: T0: %d slots: %s", s.nSlots or 0, slotsSay(s)))
        report(s, "at once")
        if type(hudCallout) == "function" then hudCallout("TEST: ZFA-44 T0", string.format("PAINT %d: %s", k, pv.name)) end
        return true
    end

    function ZFA.undo(why)
        local s = ZFA.cur
        ZFA.cur = nil
        if not s then return end
        step("T0 undoing on " .. s.hostName)
        local shown = 0
        if s.valka then                                      -- (her X-02S back, the x40a's meshes left as she keeps them)
            local vs = s.valka
            if vs.modelComp == s.comp then vs.modelComp, vs.sweepLen = s.valkaComp, s.valkaSweep end
            if s.valkaComp and liveObj(s.valkaComp) and pcall(function() s.valkaComp:SetVisibility(true, false) end) then shown = 1 end
        end
        local gone, back = ZFA.strip(s, s.valka ~= nil or not liveObj(s.host))
        shown = shown + back
        log(string.format("zfa44: T0: undone on %s (%s) after %.0f s: the ZFA-44 %s, %d of its meshes shown again%s", s.hostName,
            why, os.clock() - s.at, gone and "destroyed" or "hidden (not destroyed)", shown,
            s.valka and " (VALKA's X-02S)" or ""))
        if type(hudCallout) == "function" then hudCallout("TEST: ZFA-44 OFF", s.hostName) end
    end

    function ZFA.press()
        if ZFA.cur then ZFA.undo("Ctrl+9 again"); return end
        if not (D and D.now) then log("zfa44: T0: Ctrl+9 outside a Survival run"); return end
        if levelTorn and levelTorn() then return end
        local o, vs = valkaUp()
        local how
        if o then
            how = "VALKA's x40a"
        else
            local p, d
            o, p, d = nearest()
            if not o then
                log("zfa44: T0: Ctrl+9: no live enemy aircraft to dress")
                if type(hudCallout) == "function" then hudCallout("TEST: ZFA-44", "NO ENEMY AIRCRAFT UP") end
                return
            end
            how = string.format("the nearest live enemy aircraft, %.1f km off, %s", d or -1, tostring(p and p.unit))
        end
        ZFA.t0Dress(o, how, vs)
    end

    -- each tick half (sv_main.lua probeTickB): the host's meshes hidden again, the follow-up lines, its end
    function ZFA.tick()
        local s = ZFA.cur
        if not s then return end
        local now = os.clock()
        if not liveObj(s.host) then                          -- (gone: nothing of it touched again)
            log(string.format("zfa44: T0: %s is gone %.0f s after it was dressed (its ZFA-44 with it)", s.hostName, now - s.at))
            ZFA.cur = nil
            return
        end
        if not liveObj(s.comp) then
            log(string.format("zfa44: T0: the ZFA-44 on %s is gone (%.0f s); the host left as it is", s.hostName, now - s.at))
            ZFA.cur = nil
            return
        end
        local okH, h = pcall(function() return s.host.HealthInternal end)
        if okH and type(h) == "number" and h <= 0 and not s.downSaid then
            s.downSaid = true
            report(s, string.format("at its death (+%.0f s)", now - s.at))
            log("zfa44: T0: " .. s.hostName .. " is down: its ZFA-44 left on it (Ctrl+9 takes it off while it's still there)")
        end
        if now >= s.hideAt and not s.downSaid then
            s.hideAt = now + ZFA.C.hide_s
            local n = H.hide(s)
            if n > 0 then
                s.back = s.back + n
                if not s.backSaid then
                    s.backSaid = true
                    log(string.format("zfa44: T0: %d of %s's meshes came back on and were hidden again (+%.0f s)", n, s.hostName, now - s.at))
                end
            end
        end
        for _, t in ipairs(ZFA.C.checks_s) do
            if not s.done[t] and now - s.at >= t then
                s.done[t] = true
                report(s, string.format("+%d s", t))
                if t == ZFA.C.checks_s[1] then log(string.format("zfa44: T0 +%d s: %d slots: %s", t, s.nSlots or 0, slotsSay(s))) end
            end
        end
    end
end
if type(LEVEL_DROPS) == "table" then                         -- (the level's objects: forgotten, none of them touched)
    LEVEL_DROPS["the ZFA-44 test"] = function() ZFA.cur = nil end
end
-- TEST ONLY END
