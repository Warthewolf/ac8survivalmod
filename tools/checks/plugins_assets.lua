-- plugins_assets.lua (dofile'd by plugins_test.lua in its purge part, a file of its own for size_check's 2000 lines):
-- the add-on API's SVP.busy(), its assets loaded by path first (the engine's soft-reference loader: no object walk) and
-- SVP.play3d. T: plugins_test's check, asAddon, GS (its GameplayStatics fake) and logs
return function(T)
    local check, asAddon, GS, logs = T.check, T.asAddon, T.GS, T.logs
    local sp, lo = 0, 0                                  -- (SpawnSound2D / loadObject calls from here on)
    local spawn0, load0 = GS.SpawnSound2D, loadObject
    GS.SpawnSound2D = function(...) sp = sp + 1; return spawn0(...) end
    loadObject = function(q) lo = lo + 1; return load0(q) end
    -- (2.2) SVP.busy(): the same hold, for an add-on's own calls
    check(type(SVP.busy) == "function", "SVP.busy is there")
    if type(SVP.busy) == "function" then
        local b0 = asAddon("coopk", SVP.busy)
        GC_BUSY = true
        local b1 = asAddon("coopk", SVP.busy)
        GC_BUSY = nil
        check(b0 == nil and b1 == "the engine is freeing objects", "SVP.busy: nil, then why while the engine frees objects")
    end
    -- (2.2) an asset loaded by its path first (LoadAsset_Blocking: the engine's name hash, no walk)
    local KS = { live = true, loads = {}, GetFullName = function() return "KismetSystemLibrary /Script/Engine.Default__KismetSystemLibrary" end }
    local SOFT = {}
    function KS:MakeSoftObjectPath(q) return { q = q } end
    function KS:Conv_SoftObjPathToSoftObjRef(sp) return { q = sp.q } end
    function KS:LoadAsset_Blocking(r) self.loads[#self.loads + 1] = r.q; return SOFT[r.q] end
    local sfo2 = StaticFindObject
    StaticFindObject = function(q) if q == "/Script/Engine.Default__KismetSystemLibrary" then return KS end return sfo2(q) end
    local SW = { live = true, Duration = 2.5, GetFullName = function() return "SoundWave /Game/X/W_Soft.W_Soft" end }
    SOFT["/Game/X/W_Soft.W_Soft"] = SW
    local s0b, lo1, sp3 = SFO_N, lo, sp
    local g1 = asAddon("coopk", SVP.load, "/Game/X/W_Soft.W_Soft")
    local s1b = SFO_N
    local SW2 = { live = true, GetFullName = function() return "SoundWave /Game/X/W_Soft2.W_Soft2" end }
    SOFT["/Game/X/W_Soft2.W_Soft2"] = SW2
    local pl = asAddon("coopk", SVP.play2d, "/Game/X/W_Soft2")
    check(g1 == SW and pl == true and sp == sp3 + 1 and lo == lo1 and SFO_N - s0b <= 1 and SFO_N == s1b,
        "by its path first: SVP.load / play2d load through LoadAsset_Blocking, no walk for the asset, loadObject not asked ("
        .. (SFO_N - s0b) .. " finds: the library object once)")
    local CS = { live = true, GetFullName = function() return "SoundWave /Game/X/W_SoftC.W_SoftC" end }
    SOFT["/Game/X/W_SoftC.W_SoftC"] = CS
    local lv2 = liveObj
    liveObj = function(o) if o == CS then return false end return lv2(o) end
    local cz, czw = asAddon("coopk", SVP.load, "/Game/X/W_SoftC.W_SoftC")
    liveObj = lv2
    check(cz == nil and tostring(czw):find("condemned", 1, true) ~= nil, "by its path: a condemned answer isn't handed out")
    local lo2 = lo
    local nf = asAddon("coopk", SVP.load, "/Game/X/W_NotSoft.W_NotSoft")
    check(nf ~= nil and lo == lo2 + 1, "no asset at that path for the soft loader: the find + loadObject way, as before")
    -- (2.2) SVP.play3d: a wave in the world, at a place, with the add-on's attenuation
    check(type(SVP.play3d) == "function", "SVP.play3d is there")
    if type(SVP.play3d) == "function" then
        local sa = {}
        GS.SpawnSoundAtLocation = function(_, ctx, w, loc, rot, vol, pitch, st, att, conc, auto)
            local c = { live = true }
            sa[#sa + 1] = { ctx = ctx, w = w, loc = loc, rot = rot, vol = vol, pitch = pitch, st = st, att = att, conc = conc, auto = auto, c = c }
            return c
        end
        local ATT = { live = true, GetFullName = function() return "SoundAttenuation /Game/X/SA_L.SA_L" end }
        SOFT["/Game/X/SA_L.SA_L"] = ATT
        local ok3, d3, c3 = asAddon("coopk", SVP.play3d, "/Game/X/W_Soft", { X = 1, Y = 2, Z = 3 }, 0.7, "/Game/X/SA_L")
        local q = sa[1] or {}
        check(ok3 == true and d3 == 2.5 and c3 == q.c and q.ctx == survivalPC and q.w == SW and q.loc.X == 1 and q.loc.Z == 3
            and q.rot.Yaw == 0 and q.vol == 0.7 and q.pitch == 1.0 and q.st == 0.0 and q.att == ATT and q.conc == nil and q.auto == true,
            "play3d: SpawnSoundAtLocation(pc, wave, at, no rotation, vol, 1, 0, its attenuation, nil, auto-destroy): ok, length, component")
        local l1 = #logs
        local lo3 = loadObject
        loadObject = function(q) if tostring(q):find("Nope", 1, true) then return nil, "no such asset" end return lo3(q) end
        local okN = asAddon("coopk", SVP.play3d, "/Game/X/W_Soft", { X = 0, Y = 0, Z = 0 }, 1.0, "/Game/X/SA_Nope")
        local okN2 = asAddon("coopk", SVP.play3d, "/Game/X/W_Soft", { X = 0, Y = 0, Z = 0 }, 1.0, "/Game/X/SA_Nope")
        loadObject = lo3
        local saidN = 0
        for i = l1 + 1, #logs do if tostring(logs[i]):find("SA_Nope", 1, true) then saidN = saidN + 1 end end
        check(okN == false and okN2 == false and #sa == 1 and saidN == 1, "play3d: an attenuation that won't load: not played, said once")
        GC_BUSY = true
        local okB = asAddon("coopk", SVP.play3d, "/Game/X/W_Soft", { X = 0, Y = 0, Z = 0 })
        GC_BUSY = nil
        check(okB == false and #sa == 1, "play3d while the engine frees objects: nothing started")
        check(asAddon("coopk", SVP.play3d, "/Game/X/W_Soft", nil) == false and #sa == 1, "play3d with no place: nothing started")
        GS.SpawnSoundAtLocation = nil
    end
    StaticFindObject = sfo2
    GS.SpawnSound2D, loadObject = spawn0, load0
end
