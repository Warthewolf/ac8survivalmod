-- sv_escort_li.lua: AC7's LaserInterceptor on the ZFA-44s (2026-11-07; docs/re/LASER_INTERCEPTOR.md 9-10, tools/laser7,
-- runtime laser.c). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order, right after
-- sv_escort_laser.lua (sv_escort's family): a name another part uses is a global of this mod's Lua state, its own helpers
-- stay local.
--
-- The user, 2026-11-07: "I want the entire weapon from ACE7 to be ported over". AC7's wp_LaserInterceptor rebuilt on
-- AC8's own class ALiveLaserInterceptor (BP_SV_LaserInterceptor, the container SurvivalMode_Laser7_P: its values, its swing
-- curve, its Cascade beam and end flash with their meshes, materials and texture) is carried by every ZFA-44 in place of
-- its gun, as AC7's weapon UAVs carried it (CFG.allies.carrier.zfa li_*):
--   ZLI.rows(npc, mine, addRow, row, dr)  (sv_escort_laser.lua ZLAS.zfaRow, the main menu) the hosts' gun-less rows
--                     (li_row, li_row_drone: the build's ZFA_LI_*) when AC7's laser is on (li, the runtime's SV_LaserBegin
--                     of 0.32.26, li_class loaded): -> in, its note; nil: ZLAS's laser as before (logged why)
--   ZLI.tick()        (ZLAS.tick, every game) each ZFA-44 up (not parked) gets its laser: li_class spawned at its gun
--                     (li_mesh's li_socket), its owner the plane, its own search off (Survival searches: one beam a
--                     missile, enemies' only). Then AC7's fire control (its FCSActivationDist, FCSVolleyTime,
--                     FCSVolleyRestInterval): an enemy missile within li_activation_m of the plane starts a volley of
--                     li_volley_s (the beam's charge-up, then the beam, li_beam_x long), li_rest_s between volleys. Each
--                     li_search_s of a volley the laser not swinging takes the nearest enemy missile within li_range_m in
--                     li_angle of the plane's nose that no other laser is on, and SV_LaserBegin hands it over: the class's
--                     own swing (AC7's curve, li_intercept_s) and its own kill (the game's interceptor kill and its
--                     "Intercepted" effect), the hit sound (li_hit_sound). A missile still up li_sure_s after its swing's
--                     end, fired by the same shooter: SV_Intercept (li_sure). The volley's end: AC7's end flash
--                     (EndLaser), the beam thinned over li_end_s; a swing on then is given up (AC7's laser ended with its
--                     life). Its plane gone, the run over or the level going: the laser removed.
--   ZLI.extra()       ((2026-11-11) set by a test part: sv_tanicorn.lua's LASER mounts) more carriers, each with its own
--                     mesh and socket (TurretPoseableMesh, SOC_Gun_01) and foe "players": an enemy's laser, on the players'
--                     own missiles (HIT.minePool, sv_ladon.lua, while HIT.wantMine) instead of the enemies'
--   ZLI.test()       (a test key's, dev builds only: Ctrl+[ through ESC.testLaser) a volley now on every ZFA-44's laser
--   ZLI.summary()     the run's line for ZLAS.tick's round-end log
-- Log: `zfa li: ...`
ZLI = ZLI or {}
do
local function zc() return ((CFG.allies or {}).carrier or {}).zfa or {} end
local function num(v, d) v = tonumber(v); if v == nil then return d end; return v end
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function dist(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function short(o)
    local n = nameOf(o):match("([%w_]+)$") or "?"
    return (n:gsub("_C_%d+$", ""):gsub("_C$", ""))
end
local said = 0
local function say(fmt, ...)
    if said >= num(zc().li_log_n, 60) then return end
    said = said + 1
    log("zfa li: " .. string.format(fmt, ...))
end

-- the class, loaded once a level (nil and why not)
local CLS
local function class()
    if CLS ~= nil and liveObj(CLS) then return CLS end
    CLS = nil
    local path = zc().li_class
    if type(path) ~= "string" or path == "" then return nil, "no li_class" end
    local o, why = loadObject(path)
    -- ((2026-11-08) pinned: loaded at the main menu and held by nothing until a carrier's launch, the class could be
    -- collected on the way to Survival's level and loaded again; every spawn from 0.74.23 on came back empty)
    if o ~= nil and valid(o) then CLS = o; pin(o, "AC7's LaserInterceptor class"); return o end
    return nil, tostring(why)
end

-- ((2026-11-08) once a level, when every spawn came back empty) the class's state and a spawn of AC8's own
-- LaserInterceptor class at the same spot (destroyed at once): which of the two the game refuses
local probed
local function probe(gs, cls, t, why)
    if probed == D then return end
    probed = D
    local parts = {}
    local okC, cdo = pcall(function() return cls:GetCDO() end)
    parts[#parts + 1] = "its default object " .. ((okC and cdo and valid(cdo)) and (nameOf(cdo):match("([^%.:]+)$") or "?") or "MISSING")
    local native = StaticFindObject("/Script/Live.LiveLaserInterceptor")
    local okI, isA = pcall(function() return cls:IsChildOf(native) end)
    parts[#parts + 1] = "a LiveLaserInterceptor: " .. tostring(okI and isA or ("unread: " .. tostring(isA)))
    parts[#parts + 1] = "live: " .. tostring(liveObj(cls))
    if valid(native) then
        local okN, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, native, t, 1, nil, 1) end)
        local ok2, a = pcall(function() return x:GetAddress() end)
        local got = okN and ok2 and type(a) == "number" and a ~= 0
        parts[#parts + 1] = "AC8's own class spawned there: " .. (got and "yes" or ("NO (" .. tostring(okN and a or x) .. ")"))
        if got then pcall(function() x:K2_DestroyActor() end) end
    end
    say("AC7's laser refused (%s): %s", tostring(why), table.concat(parts, "; "))
end

-- AC7's laser on? (decided at the main menu by ZLI.rows: "ac7", else ZLAS's laser)
function ZLI.on() return ZLI.mode == "ac7" and type(SV_LaserBegin) == "function" end

function ZLI.rows(npc, mine, addRow, row, dr)
    local z = zc()
    ZLI.mode = nil
    if z.laser == false then return nil end
    if z.li == false then ZLI.mode = "tls"; log("zfa li: AC7's LaserInterceptor off (li = false): AC8's laser as before"); return nil end
    if type(SV_LaserBegin) ~= "function" or type(SV_LaserState) ~= "function" then
        ZLI.mode = "tls"
        log("zfa li: the runtime has no SV_LaserBegin (main.dll before 0.32.26): AC8's laser as before")
        return nil
    end
    local cls, why = class()
    if not cls then
        ZLI.mode = "tls"
        log("zfa li: " .. tostring(z.li_class) .. " not loaded (" .. tostring(why) .. "; no SurvivalMode_Laser7_P?): AC8's laser as before")
        return nil
    end
    local slot = "NpcFCSId" .. tostring(math.floor(num(z.laser_slot, 1)))
    local function one(r, lr)
        local _, have = dtCall(npc, "FindRow", r)
        if have ~= nil then                                -- (in already this game: as it was put in)
            local cur
            pcall(function() cur = have[slot]:ToString() end)
            return true, (cur == nil or cur == "None") and " (already in, no gun: AC7's laser)" or (" (already in, " .. slot .. " " .. tostring(cur) .. ")")
        end
        local _, tr = dtCall(mine, "FindRow", tostring(lr))
        if tr == nil then return false, " (" .. tostring(lr) .. " not in " .. nameOf(mine) .. ")" end
        dtCall(npc, "AddRow", r, tr)
        local _, got = dtCall(npc, "FindRow", r)
        if got == nil then return false, " (from " .. tostring(lr) .. " NOT added)" end
        return true, string.format(" (AC7's LaserInterceptor at its gun: %s's struct, no gun)", tostring(lr))
    end
    local in1, n1 = one(row, z.li_row)
    local in2, n2 = true, ""
    if type(dr) == "string" and dr ~= "" then
        local okD, nD = one(dr, z.li_row_drone)
        in2, n2 = okD, string.format("; %s%s%s", dr, okD and " in DT_NPC" or " NOT added", nD)
    end
    ZLI.mode = "ac7"
    log(string.format("zfa li: AC7's LaserInterceptor on the ZFA-44s (%s, its own search off: Survival's, one beam a missile)", nameOf(cls)))
    return in1 and in2, n1 .. n2
end

-- the run's state: the lasers by plane, the missiles they're on
local S
local function st()
    if S and S.D == D then return S end
    S = { D = D, L = {}, claims = {}, volleys = 0, swings = 0, kills = 0, sure = 0, refused = 0, lost = 0, k0 = nil }
    return S
end
local function liveLaser(r) return r.li ~= nil and liveAddr(r.li) == r.liA end
local function remove(r, why)
    if liveLaser(r) then pcall(function() r.li:K2_DestroyActor() end) end
    r.li, r.liA = nil, nil
    say("%s's laser removed (%s)", r.name, why)
end
-- every laser of a state removed (the run over), or forgotten (the level going: its actors go with it)
local function clear(s, torn)
    for _, r in pairs(s.L) do
        if torn then r.li = nil else remove(r, "the run's over") end
    end
    s.L, s.claims = {}, {}
end

-- the ZFA-44s up: { [plane address] = { o, a, at, unit } } (alive, out of their container: never parked)
-- ((0.74.25) and what was seen: a joiner's log of 0.74.23 had the host's carrier launch here and no laser fitted, with no
-- line saying why: { seen, gone, down, parked })
local function planes(fitted)
    local ps, why = {}, { seen = 0, gone = 0, down = 0, parked = 0 }
    local riseZ = num(((CFG.allies or {}).carrier or {}).rise_m, -50) * 100
    for u, l in pairs((ESC and ESC.planes) or {}) do
        if ESC.kindOf(u) == "zfa" then
            for _, e in ipairs(l) do
                why.seen = why.seen + 1
                if liveAddr(e.obj) == e.addr then
                    local okH, h = pcall(function() return e.obj.HealthInternal end)
                    if not (okH and type(h) == "number" and h <= 0) then
                        local p = at(e.obj)
                        if p and p.Z > riseZ then
                            -- ((2026-11-08) an Su-47 at a dead ZFA-44's address was fitted: ESC.same, sv_escort_laser.lua)
                            if ESC.same(e, (fitted and fitted[e.addr]) and 1 or nil) then ps[e.addr] = { o = e.obj, a = e.addr, at = p, unit = u, e = e }
                            else why.gone = why.gone + 1 end
                        else why.parked = why.parked + 1 end
                    else why.down = why.down + 1 end
                else why.gone = why.gone + 1 end
            end
        end
    end
    -- ((2026-11-11) other carriers: ZLI.extra(), the TANACORN's LASER mounts (sv_tanicorn.lua's test block, the user: "the
    -- LASERS have to be Laser Interceptors"): { o, a, unit, body, socket, foe }, each checked by ZLI.extra itself against
    -- the name it was captured with (hard rule 59); foe "players": they shoot down the players' missiles, not the enemies')
    if type(ZLI.extra) == "function" then
        local okX, list = pcall(ZLI.extra)
        if okX and type(list) == "table" then
            for _, e in ipairs(list) do
                why.seen = why.seen + 1
                if e.o ~= nil and e.a ~= nil and liveAddr(e.o) == e.a then
                    local okH, h = pcall(function() return e.o.HealthInternal end)
                    local p = at(e.o)
                    if okH and type(h) == "number" and h <= 0 then why.down = why.down + 1
                    elseif p then ps[e.a] = { o = e.o, a = e.a, at = p, unit = e.unit, body = e.body, socket = e.socket, foe = e.foe }
                    else why.gone = why.gone + 1 end
                else why.gone = why.gone + 1 end
            end
        end
    end
    return ps, why
end

local function beamX()
    local z = zc()
    local x = num(z.li_beam_x, 0)
    if x <= 0 then x = num(z.li_range_m, 1240) * 10 end   -- (AC7's units, ~0.1 m: the components are scaled x10)
    return x
end
-- ((2026-11-08) the beam drawn by AC8's own effects (li_fx "ac8"): AC7's Cascade beam stopped the game in the renderer)
local function ac8fx() return zc().li_fx ~= "ac7" end
local FXA = {}
local function fxAsset(path)
    if type(path) ~= "string" or path == "" then return nil end
    local full = path .. "." .. path:match("[^/]+$")
    local o = FXA[full]
    if o ~= nil and liveObj(o) then return o end
    o = loadObject(full)
    if o ~= nil and valid(o) then FXA[full] = o; pin(o, "the ZFA-44 laser's effect " .. full:match("[^/]+$")); return o end
    return nil
end
-- an AC8 effect on the laser's root (it swings with it), or nil
local function fxOn(r, path, life)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = fxAsset(path)
    if not (valid(lib) and sys and r.li and liveLaser(r)) then return nil end
    local ok, comp = pcall(function()                     -- (EAttachLocation 0, KeepRelativeOffset: at its root, as AC7's)
        return lib:SpawnSystemAttached(sys, r.li:K2_GetRootComponent(), FName("None"), { X = 0, Y = 0, Z = 0 },
            { Pitch = 0, Yaw = 0, Roll = 0 }, 0, true, true, 0, true)
    end)
    if not (ok and comp and comp:IsValid()) then
        say("%s: AC8's beam effect %s failed: %s", r.name, tostring(path), tostring(comp))
        return nil
    end
    if life then
        pcall(function() comp:SetVariableFloat(FName("User.BeamLifeTime"), life) end)
        pcall(function() comp:SetVariableFloat(FName("BeamLifeTime"), life) end)
    end
    return comp
end
-- ((2026-11-11) the user: "change the laser color to red") a beam's colour (li_color: linear HDR { R, G, B }), through
-- the UAV beam's own User.BeamColor; logged the first time for each laser: what was set and whether it took
local function tint(r, c)
    local z = zc()
    local col = z.li_color
    if not (c and liveObj(c)) or type(col) ~= "table" or #col < 3 then return end
    local lc = { R = num(col[1], 1), G = num(col[2], 0), B = num(col[3], 0), A = 1 }
    local how
    for _, n in ipairs({ "User.BeamColor", "BeamColor" }) do
        if pcall(function() c:SetVariableLinearColor(FName(n), lc) end) then how = how or ("SetVariableLinearColor " .. n) end
    end
    if not how and pcall(function() c:SetColorParameter(FName("BeamColor"), lc) end) then how = "SetColorParameter BeamColor" end
    if not r.tintSaid then
        r.tintSaid = true
        say("%s's beam colour (%.1f, %.1f, %.1f): %s", r.name, lc.R, lc.G, lc.B, how or "NOT set (no colour call took)")
    end
end
local function beam(r, yz)
    if ac8fx() then
        local c = r.fxBeam
        if not (c and liveObj(c)) then return end
        local len = num(zc().li_range_m, 1240) * 100              -- (AC8's own units: cm)
        pcall(function() c:SetVariableVec3(FName("User.BeamLength"), { X = len, Y = yz, Z = yz }) end)
        pcall(function() c:SetVariableVec3(FName("BeamLength"), { X = len, Y = yz, Z = yz }) end)
        return
    end
    pcall(function() r.li.MainLaser:SetVectorParameter(FName("BeamLength"), { X = beamX(), Y = yz, Z = yz }) end)
end

-- ((2026-11-10) the user: "up the swing speed for the laser interceptors": li_intercept_s 0.5) The class reads its swing
-- curve in seconds, not as a share of InterceptTime (docs/re/LASER_INTERCEPTOR.md 9: alpha = curve(timer), its kill at
-- timer > InterceptTime), so with AC7's 1 s curve and a 0.5 s swing the beam was only half way to its missile at the
-- kill. Laser x's curve kept when it's at its end (0.98 or more) by InterceptTime `it`, else cleared: a null curve is
-- checked by the class and swings straight over InterceptTime. What was done, for the laser's line
local function curveFit(x, it)
    local okC, c = pcall(function() return x.SwingRateCurve end)
    if not (okC and c ~= nil and valid(c)) then return "no swing curve (a straight swing)" end
    local okV, v = pcall(function() return c:GetFloatValue(it) end)
    local at = (okV and type(v) == "number") and string.format("%.2f at %.2f s", v, it) or string.format("unread at %.2f s", it)
    if okV and type(v) == "number" and v >= 0.98 then return "its swing curve kept (" .. at .. ")" end
    pcall(function() x.SwingRateCurve = nil end)
    local okR, c2 = pcall(function() return x.SwingRateCurve end)
    if okR and (c2 == nil or not valid(c2)) then return "its swing curve cleared (" .. at .. "): a straight swing" end
    return "its swing curve NOT cleared (" .. at .. "): the beam is short of its missile at the kill"
end

-- plane p's laser: AC7's weapon spawned at its gun -> the laser, its note; nil and why not
local function spawn(p)
    local z = zc()
    local cls, why = class()
    if not cls then return nil, "its class isn't loaded (" .. tostring(why) .. ")" end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (valid(gs) and liveObj(survivalPC)) then return nil, "no GameplayStatics / player controller" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = p.at.X, Y = p.at.Y, Z = p.at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    -- (AlwaysSpawn; its owner the plane) ((0.74.25) Saint Alessia's host log of 0.74.23: "its laser NOT spawned (not
    -- spawned (UObject: ...))", 5 tries on each ZFA-44, where 0.74.21's had spawned: again with no owner at the spawn
    -- (SV_LaserOwner gives it its plane after), and what came back logged)
    local function deferred(owner, ctx)
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(ctx or survivalPC, cls, t, 1, owner, 1) end)
        if okB and x and valid(x) then return x end
        if not okB then return nil, "error " .. tostring(x) end
        local okA, ad = pcall(function() return x:GetAddress() end)
        return nil, string.format("%s, address %s", tostring(x), okA and tostring(ad) or "unread")
    end
    local x, why1 = deferred(p.o)
    if not x then
        local why2, why3, how
        x, why2 = deferred(nil)
        how = "with no owner at the spawn"
        -- ((2026-11-08) the plane's own world, not the player controller's: a third try)
        if not x then x, why3 = deferred(p.o, p.o); how = "in the plane's world" end
        if not x then
            local why = string.format("with its plane as owner: %s; with none: %s; in the plane's world: %s", tostring(why1),
                tostring(why2), tostring(why3))
            probe(gs, cls, t, why)
            return nil, "not spawned (" .. why .. ")"
        end
        say("%s: its laser spawned only %s (with its plane as owner: %s)", short(p.o) .. "@" .. tostring(p.a), how, tostring(why1))
    end
    -- its values before it begins (this laser's only, never the class's): AC7's; its own search off (SearchInterval: a
    -- search never due); LifeTime the volley (the beam's particle lives, the class's tick: LifeTime + 0.2 / - 0.5)
    local vals = { SearchInterval = 1.0e9, InterceptTime = num(z.li_intercept_s, 1.0), InterceptAngle = num(z.li_angle, 180),
                   RayDistance = num(z.li_range_m, 1240) * 100, LifeTime = num(z.li_volley_s, 6.0), bIsBaseAttached = true }
    for k, v in pairs(vals) do pcall(function() x[k] = v end) end
    local curveHow = curveFit(x, vals.InterceptTime)
    pcall(function() x.MainLaser.bAutoActivate = false end)   -- (the beam waits for a volley)
    pcall(function() x.EndLaser.bAutoActivate = false end)
    local okF, fin = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
    if not (okF and valid(x)) then
        pcall(function() x:K2_DestroyActor() end)
        return nil, "not finished (" .. tostring(fin) .. ")"
    end
    -- ((0.74.25) the hosts' logs of 0.74.21 and 0.74.23 read FinishSpawningActor's answer as no laser: its owner -4097, its
    -- SearchInterval an object, not a number. The laser is x, the actor the deferred spawn made: used from here on.)
    local a = x
    pcall(function() a:SetOwner(p.o) end)
    -- its OwningGameObject, which the class reads every tick and the game sets only when a plane's fire control fires one:
    -- none, the runtime's tick guard held the laser and refused every swing (the user: "the ZFA-44's did not fire their
    -- laser"). The runtime's store (SV_LaserOwner, 0.32.28), else UE4SS's.
    local ownHow = "not set"
    if type(SV_LaserOwner) == "function" then
        local okO, r = pcall(SV_LaserOwner, addrOf(a), p.a)
        ownHow = "SV_LaserOwner " .. tostring(okO and r or ("error " .. tostring(r)))
    end
    if not ownHow:find(" 1$") then
        local okW = pcall(function() a.OwningGameObject = p.o end)
        ownHow = ownHow .. (okW and "; written by UE4SS" or "; UE4SS's write failed")
    end
    local body = p.body                                   -- ((2026-11-11) a carrier's own mesh and socket: ZLI.extra's)
    if not valid(body) then pcall(function() body = p.o[z.li_mesh or "PlaneBodyMesh"] end) end
    if not valid(body) then pcall(function() body = p.o:K2_GetRootComponent() end) end
    local sock = p.socket or z.li_socket or "SOC_Gun_01"
    local attached = false
    if valid(body) then                                   -- (at its gun: location and rotation the socket's)
        attached = pcall(function() a:K2_AttachToComponent(body, FName(sock), 2, 2, 1, false) end)
    end
    pcall(function() a.MainLaser:SetVisibility(false, false) end)
    pcall(function() a.EndLaser:SetVisibility(false, false) end)
    if ac8fx() then                                       -- (AC7's Cascade beam never lit: AC8's renderer can't draw it)
        pcall(function() a.MainLaser:Deactivate() end)
        pcall(function() a.EndLaser:Deactivate() end)
    end
    local own, si
    pcall(function() own = a.OwningGameObject end)
    pcall(function() si = a.SearchInterval end)
    local ownA = own ~= nil and addrOf(own) or nil
    return a, string.format("owner %s (%s), search every %s s (off), %s, a swing %.2f s, %s%s", ownA == p.a and "its plane" or ("NOT its plane (" .. tostring(ownA) .. ")"),
        ownHow, tostring(si), attached and ("at " .. tostring(sock)) or "NOT attached", vals.InterceptTime, curveHow,
        (fin ~= nil and addrOf(fin) ~= addrOf(a)) and string.format("; FinishSpawningActor answered %s, not the laser", tostring(addrOf(fin))) or "")
end

local function volleyOn(s, r, clock, why)
    local z = zc()
    r.phase, r.from, r.to = "volley", clock, clock + num(z.li_volley_s, 6.0)
    r.nextSearch = clock + num(z.li_search_s, 0.5)       -- (AC7's first search: SearchInterval after the weapon's birth)
    pcall(function() r.li:K2_GetRootComponent():K2_SetRelativeRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, false) end)
    local how = "AC7's beam"
    if ac8fx() then                                       -- (AC8's own beam: AC7's never lit)
        if r.fxBeam and liveObj(r.fxBeam) then pcall(function() r.fxBeam:Deactivate() end) end
        r.fxBeam = fxOn(r, z.li_fx_beam, num(z.li_volley_s, 6.0) + num(z.li_intercept_s, 1.0) + num(z.li_end_s, 0.2))
        tint(r, r.fxBeam)                                 -- ((2026-11-11) li_color: red, AC7's)
        how = r.fxBeam and "AC8's beam" or "no beam drawn"
        beam(r, 1)
    else
        pcall(function() r.li.EndLaser:SetActive(false, false) end)
        beam(r, 1)
        pcall(function() r.li.MainLaser:SetVisibility(true, false) end)
        pcall(function() r.li.MainLaser:SetActive(true, true) end)   -- (AC7's OnCreateWeaponEnd: the beam from its start)
    end
    s.volleys = s.volleys + 1
    say("%s fires a volley (%s; %s; %d so far)", r.name, why, how, s.volleys)
end
local function volleyOff(s, r, clock)
    pcall(SV_LaserState, r.liA, 0)                        -- (a swing on now is given up: AC7's laser ended with its life)
    for ma, c in pairs(s.claims) do
        if c.r == r then s.claims[ma] = nil; c.m.liClaimed = nil end
    end
    if ac8fx() then
        fxOn(r, zc().li_fx_end, nil)                      -- (AC8's end flash: it ends by itself)
    else
        pcall(function() r.li.EndLaser:SetVisibility(true, false) end)
        pcall(function() r.li.EndLaser:SetActive(true, true) end)    -- (AC7's OnLifeTimeExpired: the end flash)
    end
    beam(r, 0.5)
    r.phase, r.offAt = "ending", clock + num(zc().li_end_s, 0.2)
end
local function beamOff(r, clock)
    beam(r, 0)                                            -- (AC7's LaserScale at 0: the beam thinned to nothing)
    if ac8fx() then
        if r.fxBeam and liveObj(r.fxBeam) then pcall(function() r.fxBeam:Deactivate() end) end
        r.fxBeam = nil
    else
        pcall(function() r.li.MainLaser:Deactivate() end)
        pcall(function() r.li.MainLaser:SetVisibility(false, false) end)
    end
    r.phase, r.restUntil = "rest", clock + num(zc().li_rest_s, 8.0)
end

local function flying(o)                                 -- a missile still in the air (not collided, not destroyed)
    if not liveAddr(o) then return false end
    local okC, c = pcall(function() return o.bCollided end)
    if okC and c == true then return false end
    local okD, d = pcall(function() return o:IsDestroyed() end)
    return not (okD and d == true)
end
local function shooterOf(o)
    local ok, w = pcall(function() return o.OwningGameObject end)
    return ok and w and addrOf(w) or nil
end
-- the enemy missiles up, with their place (HIT.msl; one shot down and fired again from its pool is a new one)
local function missiles()
    local ms = {}
    for _, m in ipairs((HIT and HIT.msl) or {}) do
        local ma = addrOf(m.obj)
        if ma and liveAddr(m.obj) == ma then
            if m.liDown and flying(m.obj) then m.liDown, m.zEnemy, m.zDone = nil, nil, nil end   -- (fired again)
            if not m.liDown and not m.liClaimed and ZLAS.enemyOf and ZLAS.enemyOf(m) and flying(m.obj) then
                local p = at(m.obj)
                if p then m.zAt = p; ms[#ms + 1] = m end
            end
        end
    end
    return ms
end
-- ((2026-11-11) the players' own missiles in flight, for an enemy carrier's laser (foe "players": the TANACORN's LASER
-- mounts): sv_ladon.lua keeps every BP_plwp_* missile the game makes in HIT.minePool while HIT.wantMine (a pool's missiles
-- launched again and again). In flight: not collided, not destroyed, and moved since the last look (a pooled one lies still)
local function mine()
    local ms = {}
    for a, m in pairs((HIT and HIT.minePool) or {}) do
        if liveAddr(m.obj) ~= a or short(m.obj) ~= m.name then
            HIT.minePool[a] = nil                          -- (gone, or another object at its address: hard rule 59)
            HIT.mineN = math.max(0, (HIT.mineN or 1) - 1)
        else
            local p = at(m.obj)
            local moved = p ~= nil and m.zLast ~= nil and dist(p, m.zLast) > 100
            m.zLast = p
            if moved and flying(m.obj) then
                if m.still then m.still, m.liDown = nil, nil end   -- (launched again from its pool)
                if not m.liDown and not m.liClaimed then m.zAt = p; ms[#ms + 1] = m end
            else
                m.still = true
            end
        end
    end
    return ms
end
local function nose(o)
    local ok, v = pcall(function() local f = o:GetActorForwardVector(); return { X = f.X, Y = f.Y, Z = f.Z } end)
    return ok and v or nil
end
local function inCone(p, m, angle)
    if angle >= 180 then return true end
    local f = nose(p.o)
    if not f then return true end
    local dx, dy, dz = m.zAt.X - p.at.X, m.zAt.Y - p.at.Y, m.zAt.Z - p.at.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < 1 then return true end
    local c = math.max(-1, math.min(1, (f.X * dx + f.Y * dy + f.Z * dz) / d))
    return math.deg(math.acos(c)) <= angle
end

-- the missiles the lasers are on: shot down (the class's own kill at its swing's end), made sure, or lost
local function claimsTick(s, clock)
    local z = zc()
    for ma, c in pairs(s.claims) do
        local m = c.m
        if not flying(m.obj) or liveAddr(m.obj) ~= ma then
            s.claims[ma], m.liClaimed = nil, nil
            m.liDown, m.zDone = true, true
            if clock >= c.due - 0.25 then
                s.kills = s.kills + 1
                if ZLAS.sound then ZLAS.sound(z.li_hit_sound or z.laser_hit_sound, m.zAt) end
                say("%s's laser shot down %s (from %s; %d so far)", c.r.name, c.name, tostring(m.from or "?"), s.kills)
            else
                s.lost = s.lost + 1
                say("%s went down %.2f s into %s's swing: it hit something first", c.name, clock - c.at, c.r.name)
            end
        elseif clock >= c.due + num(z.li_sure_s, 0.6) then  -- (still up after its swing's end)
            s.claims[ma], m.liClaimed = nil, nil
            local same = shooterOf(m.obj) == c.shooter
            local weapon = false
            pcall(function() weapon = m.obj:IsA(StaticFindObject("/Script/Live.LiveWeaponBase")) end)
            if z.li_sure ~= false and same and weapon and type(SV_Intercept) == "function" then
                local okI, r = pcall(SV_Intercept, ma)
                if okI and r == 1 then
                    s.kills, s.sure = s.kills + 1, s.sure + 1
                    m.liDown, m.zDone = true, true
                    if ZLAS.sound then ZLAS.sound(z.li_hit_sound or z.laser_hit_sound, at(m.obj) or m.zAt) end
                end
                say("%s still up %.2f s after %s's swing: SV_Intercept -> %s", c.name, clock - c.at, c.r.name, tostring(okI and r or "error"))
            else
                say("%s still up after %s's swing, not made sure (%s)", c.name, c.r.name,
                    not same and "fired again by another shooter" or (not weapon and "not a weapon") or "li_sure off / no SV_Intercept")
            end
        end
    end
end

-- a laser not swinging takes the nearest enemy missile in its reach nobody's on
local function search(s, r, p, ms, clock)
    local z = zc()
    local okS, stNow = pcall(SV_LaserState, r.liA)
    if not okS or stNow ~= 0 then return end
    local range, angle = num(z.li_range_m, 1240) * 100, num(z.li_angle, 180)
    local best, bd = nil, range
    for _, m in ipairs(ms) do
        if not m.liClaimed then
            local d = dist(r.at or p.at, m.zAt)
            if d <= bd and inCone(p, m, angle) then best, bd = m, d end
        end
    end
    if not best then return end
    local ma = addrOf(best.obj)
    local okB, res = pcall(SV_LaserBegin, r.liA, ma)
    local nm = (best.name or short(best.obj)) .. "@" .. tostring(ma)
    if okB and res == 1 then
        best.liClaimed = true
        s.claims[ma] = { m = best, r = r, name = nm, at = clock, due = clock + num(z.li_intercept_s, 1.0), shooter = shooterOf(best.obj) }
        s.swings = s.swings + 1
        say("%s swings onto %s %.0f m off (from %s; swing %d)", r.name, nm, bd / 100, tostring(best.from or "?"), s.swings)
    else
        s.refused = s.refused + 1
        best.liDown = true                                 -- (not one in flight: asked again only once fired again)
        say("%s: SV_LaserBegin on %s -> %s", r.name, nm, tostring(okB and res or ("error " .. tostring(res))))
    end
end

function ZLI.tick()
    if not ZLI.on() then return end
    if (levelTorn and levelTorn()) or not liveObj(survivalPC) then
        if S then clear(S, true); S = nil end            -- (the level going: its actors go with it, nothing called)
        return
    end
    if S and S.D ~= D then clear(S, false); S = nil end   -- (the run over, or a new one)
    if not D then return end
    local s = st()
    local z = zc()
    local clock = os.clock()
    local ps, why = planes(s.L)
    -- the lasers of planes gone
    for a, r in pairs(s.L) do
        if not ps[a] then remove(r, "its plane is gone"); s.L[a] = nil end
    end
    if next(ps) == nil then
        -- ((0.74.25) once a run, and again once something changed: none up to fit, of how many seen here)
        local key = string.format("%d/%d/%d/%d", why.seen, why.gone, why.down, why.parked)
        if why.seen > 0 and s.noneSaid ~= key and clock >= (s.noneAt or 0) then
            s.noneSaid, s.noneAt = key, clock + 30
            say("no ZFA-44 up here to fit (%s): %d seen here, %d gone, %d down, %d still parked (under rise_m)",
                (COOP and COOP.client and COOP.client()) and "a joiner" or "the host or solo", why.seen, why.gone, why.down, why.parked)
        end
        return
    end
    local ms, mineMs = missiles(), nil
    claimsTick(s, clock)
    local act = num(z.li_activation_m, 1200) * 100
    for a, p in pairs(ps) do
        if p.foe == "players" then                         -- ((2026-11-11) an enemy's laser: the players' missiles)
            mineMs = mineMs or mine()
        end
        local here = p.foe == "players" and mineMs or ms   -- (each carrier its own side's list)
        local r = s.L[a]
        if not r then
            r = { o = p.o, a = a, name = short(p.o) .. "@" .. tostring(a), unit = p.unit, phase = "rest", restUntil = clock, tries = 0 }
            s.L[a] = r
        end
        r.at = p.at
        if not liveLaser(r) then
            if r.li ~= nil then say("%s's laser was gone: another", r.name) end
            r.li, r.liA = nil, nil
            if clock >= (r.retryAt or 0) and r.tries < 5 then
                r.tries = r.tries + 1
                local li, note = spawn(p)
                if li then
                    r.li, r.liA, r.phase, r.restUntil = li, addrOf(li), "rest", clock
                    say("%s (%s) carries AC7's LaserInterceptor: %s", r.name, tostring(p.unit), note)
                else
                    r.retryAt = clock + 5
                    say("%s: its laser NOT spawned (%s; try %d of 5)", r.name, tostring(note), r.tries)
                end
            end
        end
        if liveLaser(r) then
            if r.phase == "rest" and clock >= (r.restUntil or 0) then
                for _, m in ipairs(here) do                -- (AC7's FCSActivationDist: an enemy missile that near)
                    if dist(p.at, m.zAt) <= act then
                        volleyOn(s, r, clock, string.format("%s %.0f m off", m.name or short(m.obj), dist(p.at, m.zAt) / 100))
                        break
                    end
                end
            end
            if r.phase == "volley" then
                -- ((2026-11-08) Alyssa's run of 0.74.31: swing 4 began in the volley's last second and was given up at
                -- its end, its missile let through) a swing still on at the volley's end is finished first
                local swinging = false
                if clock >= r.to then
                    for _, c in pairs(s.claims) do
                        if c.r == r and clock < (c.due or 0) + 0.25 then swinging = true end
                    end
                    if swinging and not r.heldSaid then
                        r.heldSaid = true
                        say("%s's volley held past its %.1f s: its swing on now is finished first", r.name, num(z.li_volley_s, 6.0))
                    end
                end
                if clock >= r.to and not swinging then
                    r.heldSaid = nil
                    volleyOff(s, r, clock)
                elseif clock >= (r.nextSearch or 0) then
                    r.nextSearch = clock + num(z.li_search_s, 0.5)
                    search(s, r, p, here, clock)
                end
            elseif r.phase == "ending" and clock >= (r.offAt or 0) then
                beamOff(r, clock)
            end
        end
    end
end

function ZLI.summary()
    if not S or S.volleys == 0 then return nil end
    local k = type(SV_LaserKills) == "function" and SV_LaserKills() or -1
    return string.format("AC7's lasers: %d volleys, %d swings, %d missiles shot down (%d made sure by SV_Intercept), %d went down first, %d refused; the class's own kills %s",
        S.volleys, S.swings, S.kills, S.sure, S.lost, S.refused, tostring(k))
end

-- TEST ONLY BEGIN
-- Ctrl+[ (ESC.testLaser): a volley now on every ZFA-44's laser (the beam seen with no missile near), their state logged
-- ((2026-11-11) the beam's red, to choose by eye: each press the next of these on li_color, logged; User.BeamColor may be
-- the beam's colour outright or a tint on AC8's own, which only the screen tells)
local REDS = { { 100, 21.5, 22.8, "AC7's HDR red" }, { 20, 2, 2, "a mid red" }, { 1, 0.08, 0.08, "a plain red" } }
local redAt = 0
function ZLI.test()
    if not ZLI.on() then log("test: Ctrl+[: AC7's LaserInterceptor isn't on (mode " .. tostring(ZLI.mode) .. ")"); return end
    local s = st()
    local clock, n = os.clock(), 0
    redAt = redAt % #REDS + 1
    local red = REDS[redAt]
    zc().li_color = { red[1], red[2], red[3] }
    for _, r in pairs(s.L) do r.tintSaid = nil end
    log(string.format("test: Ctrl+[: the beam's colour %d of %d, %s (%.1f, %.1f, %.1f)", redAt, #REDS, red[4], red[1], red[2], red[3]))
    for _, r in pairs(s.L) do
        if liveLaser(r) then
            local okS, stNow = pcall(SV_LaserState, r.liA)
            log(string.format("test: Ctrl+[: %s's laser %s, state %s, phase %s", r.name, tostring(r.liA), tostring(okS and stNow), tostring(r.phase)))
            if r.phase ~= "volley" then volleyOn(s, r, clock, "test key Ctrl+["); n = n + 1 end
        end
    end
    hudCallout("TEST: AC7 LASERS", n > 0 and string.format("%d VOLLEY%s, RED %d OF %d", n, n == 1 and "" or "S", redAt, #REDS)
        or "NO LASER UP (CTRL+DEL: A CARRIER, CTRL+U: THE LASER MOUNT)")
end
if ESC then ESC.testLaser = function() ZLI.test() end end
testKey("OEM_FOUR", "sv_escort_li.lua's AC7 laser volley", function()
    if ESC and ESC.testLaser then ESC.testLaser() end
end)
-- TEST ONLY END
end
