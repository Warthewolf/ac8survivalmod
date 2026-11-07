-- sv_escort_li.lua: AC7's LaserInterceptor on the ZFA-44s (2026-11-07; tools/re/LASER_INTERCEPTOR.md 9-10, tools/laser7,
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
--   ZLI.test()        (a test key's, dev builds only: Ctrl+[ through ESC.testLaser) a volley now on every ZFA-44's laser
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
    if o ~= nil and valid(o) then CLS = o; return o end
    return nil, tostring(why)
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
local function planes()
    local ps = {}
    local riseZ = num(((CFG.allies or {}).carrier or {}).rise_m, -50) * 100
    for u, l in pairs((ESC and ESC.planes) or {}) do
        if ESC.kindOf(u) == "zfa" then
            for _, e in ipairs(l) do
                if liveAddr(e.obj) == e.addr then
                    local okH, h = pcall(function() return e.obj.HealthInternal end)
                    if not (okH and type(h) == "number" and h <= 0) then
                        local p = at(e.obj)
                        if p and p.Z > riseZ then ps[e.addr] = { o = e.obj, a = e.addr, at = p, unit = u, e = e } end
                    end
                end
            end
        end
    end
    return ps
end

local function beamX()
    local z = zc()
    local x = num(z.li_beam_x, 0)
    if x <= 0 then x = num(z.li_range_m, 1240) * 10 end   -- (AC7's units, ~0.1 m: the components are scaled x10)
    return x
end
local function beam(r, yz)
    pcall(function() r.li.MainLaser:SetVectorParameter(FName("BeamLength"), { X = beamX(), Y = yz, Z = yz }) end)
end

-- plane p's laser: AC7's weapon spawned at its gun -> the laser, its note; nil and why not
local function spawn(p)
    local z = zc()
    local cls, why = class()
    if not cls then return nil, "its class isn't loaded (" .. tostring(why) .. ")" end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (valid(gs) and liveObj(survivalPC)) then return nil, "no GameplayStatics / player controller" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = p.at.X, Y = p.at.Y, Z = p.at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, p.o, 1) end)   -- (AlwaysSpawn; its owner the plane)
    if not (okB and x and valid(x)) then return nil, "not spawned (" .. tostring(x) .. ")" end
    -- its values before it begins (this laser's only, never the class's): AC7's; its own search off (SearchInterval: a
    -- search never due); LifeTime the volley (the beam's particle lives, the class's tick: LifeTime + 0.2 / - 0.5)
    local vals = { SearchInterval = 1.0e9, InterceptTime = num(z.li_intercept_s, 1.0), InterceptAngle = num(z.li_angle, 180),
                   RayDistance = num(z.li_range_m, 1240) * 100, LifeTime = num(z.li_volley_s, 6.0), bIsBaseAttached = true }
    for k, v in pairs(vals) do pcall(function() x[k] = v end) end
    pcall(function() x.MainLaser.bAutoActivate = false end)   -- (the beam waits for a volley)
    pcall(function() x.EndLaser.bAutoActivate = false end)
    local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
    if not (okF and a and valid(a)) then
        pcall(function() x:K2_DestroyActor() end)
        return nil, "not finished (" .. tostring(a) .. ")"
    end
    pcall(function() a:SetOwner(p.o) end)                 -- (its OwningGameObject: the class reads it every tick)
    local body
    pcall(function() body = p.o[z.li_mesh or "PlaneBodyMesh"] end)
    if not valid(body) then pcall(function() body = p.o:K2_GetRootComponent() end) end
    local attached = false
    if valid(body) then                                   -- (at its gun: location and rotation the socket's)
        attached = pcall(function() a:K2_AttachToComponent(body, FName(z.li_socket or "SOC_Gun_01"), 2, 2, 1, false) end)
    end
    pcall(function() a.MainLaser:SetVisibility(false, false) end)
    pcall(function() a.EndLaser:SetVisibility(false, false) end)
    local own, si
    pcall(function() own = a.OwningGameObject end)
    pcall(function() si = a.SearchInterval end)
    local ownA = own ~= nil and addrOf(own) or nil
    return a, string.format("owner %s, search every %s s (off), %s", ownA == p.a and "its plane" or ("NOT its plane (" .. tostring(ownA) .. ")"),
        tostring(si), attached and ("at " .. tostring(z.li_socket or "SOC_Gun_01")) or "NOT attached")
end

local function volleyOn(s, r, clock, why)
    local z = zc()
    r.phase, r.from, r.to = "volley", clock, clock + num(z.li_volley_s, 6.0)
    r.nextSearch = clock + num(z.li_search_s, 0.5)       -- (AC7's first search: SearchInterval after the weapon's birth)
    pcall(function() r.li:K2_GetRootComponent():K2_SetRelativeRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, false) end)
    pcall(function() r.li.EndLaser:SetActive(false, false) end)
    beam(r, 1)
    pcall(function() r.li.MainLaser:SetVisibility(true, false) end)
    pcall(function() r.li.MainLaser:SetActive(true, true) end)   -- (AC7's OnCreateWeaponEnd: the beam from its start)
    s.volleys = s.volleys + 1
    say("%s fires a volley (%s; %d so far)", r.name, why, s.volleys)
end
local function volleyOff(s, r, clock)
    pcall(SV_LaserState, r.liA, 0)                        -- (a swing on now is given up: AC7's laser ended with its life)
    for ma, c in pairs(s.claims) do
        if c.r == r then s.claims[ma] = nil; c.m.liClaimed = nil end
    end
    pcall(function() r.li.EndLaser:SetVisibility(true, false) end)
    pcall(function() r.li.EndLaser:SetActive(true, true) end)    -- (AC7's OnLifeTimeExpired: the end flash)
    beam(r, 0.5)
    r.phase, r.offAt = "ending", clock + num(zc().li_end_s, 0.2)
end
local function beamOff(r, clock)
    beam(r, 0)                                            -- (AC7's LaserScale at 0: the beam thinned to nothing)
    pcall(function() r.li.MainLaser:Deactivate() end)
    pcall(function() r.li.MainLaser:SetVisibility(false, false) end)
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
    local ps = planes()
    -- the lasers of planes gone
    for a, r in pairs(s.L) do
        if not ps[a] then remove(r, "its plane is gone"); s.L[a] = nil end
    end
    if next(ps) == nil then return end
    local ms = missiles()
    claimsTick(s, clock)
    local act = num(z.li_activation_m, 1200) * 100
    for a, p in pairs(ps) do
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
                for _, m in ipairs(ms) do                  -- (AC7's FCSActivationDist: an enemy missile that near)
                    if dist(p.at, m.zAt) <= act then
                        volleyOn(s, r, clock, string.format("%s %.0f m off", m.name or short(m.obj), dist(p.at, m.zAt) / 100))
                        break
                    end
                end
            end
            if r.phase == "volley" then
                if clock >= r.to then
                    volleyOff(s, r, clock)
                elseif clock >= (r.nextSearch or 0) then
                    r.nextSearch = clock + num(z.li_search_s, 0.5)
                    search(s, r, p, ms, clock)
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
function ZLI.test()
    if not ZLI.on() then log("test: Ctrl+[: AC7's LaserInterceptor isn't on (mode " .. tostring(ZLI.mode) .. ")"); return end
    local s = st()
    local clock, n = os.clock(), 0
    for _, r in pairs(s.L) do
        if liveLaser(r) then
            local okS, stNow = pcall(SV_LaserState, r.liA)
            log(string.format("test: Ctrl+[: %s's laser %s, state %s, phase %s", r.name, tostring(r.liA), tostring(okS and stNow), tostring(r.phase)))
            if r.phase ~= "volley" then volleyOn(s, r, clock, "test key Ctrl+["); n = n + 1 end
        end
    end
    hudCallout("TEST: AC7 LASERS", n > 0 and string.format("%d VOLLEY%s", n, n == 1 and "" or "S") or "NO ZFA-44 LASER UP (CTRL+DEL: A CARRIER)")
end
if ESC then ESC.testLaser = function() ZLI.test() end end
testKey("OEM_FOUR", "sv_escort_li.lua's AC7 laser volley", function()
    if ESC and ESC.testLaser then ESC.testLaser() end
end)
-- TEST ONLY END
end
