-- VALKA's SOLG's lasers, Survival's own (2026-11-23). The game's own turret firing (AC8's land CIWS arm on our turret
-- rows, BP_SV_SolgTLS) fired one burst and never again in every autotest (0.75.32-0.75.35: its ammo, its reload, a
-- trigger count of 999, switching it off and on: none brought a second burst; the user: "as soon as the solg started
-- moving they stopped firing or they were like rapid firing"). So each live, open laser turret runs Gould's cycle here
-- (docs/re/SOLG.md 13: fire 10 s at a player within reach, then 5 s rest): AC8's player TLS beam (the ZFA-44's proven
-- one, sv_escort_li.lua) from the turret to your plane, the TLS shooting sound, and `damage` a hit every hit_s (the
-- user: "damage them for 5 health every hit"). Each game fires at its own player only (a co-op joiner's game at its
-- own plane, from its copies of the host's turrets), so nothing more needs syncing.
SLAS = SLAS or {}
local function C() return (SOLG and SOLG.C and SOLG.C.own_laser) or {} end
local function num(v, d) v = tonumber(v); if v == nil then return d end; return v end
local function sl(msg) log("solg laser: " .. msg) end
local FXA = {}
local function fxAsset(path)
    if type(path) ~= "string" then return nil end
    local full = path .. "." .. path:match("[^/]+$")
    local o = FXA[full]
    if o and liveObj(o) then return o end
    o = loadObject(full)
    if o ~= nil and valid(o) then FXA[full] = o; if pin then pcall(pin, o, "the SOLG laser's " .. full:match("[^/]+$")) end; return o end
    return nil
end
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
-- the turn from a to b as a quaternion (hard rule 76: a rotator's Pitch from Lua is dropped; a transform's quaternion isn't)
local function quatTo(a, b)
    local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    local h = math.sqrt(dx * dx + dy * dy)
    local yaw, pitch = math.atan(dy, dx), math.atan(dz, h)
    local cy, sy, cp, sp = math.cos(yaw / 2), math.sin(yaw / 2), math.cos(pitch / 2), math.sin(pitch / 2)
    -- (FRotator(pitch, yaw, 0).Quaternion(), roll 0)
    return { X = sp * sy, Y = -sp * cy, Z = cp * sy, W = cp * cy }, math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function sound(who, on)
    local c = C()
    local name = on and c.sound or c.sound_stop
    if type(name) ~= "string" or name == "" or not liveObj(who) then return end
    local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
    if lib and valid(lib) then pcall(function() lib:PostEventAtActorByName(FName(name), who) end) end
end
local function beamOff(t)
    if t.comp and liveObj(t.comp) then pcall(function() t.comp:DestroyComponent() end) end
    if t.sndOn then sound(t.o, false) end
    t.comp, t.sndOn = nil, nil
end
local function aimBeam(t, from, to)
    local q, len = quatTo(from, to)
    pcall(function() t.comp:K2_SetWorldTransform({ Rotation = q, Translation = from, Scale3D = { X = 1, Y = 1, Z = 1 } }, false, {}, true) end)
    pcall(function() t.comp:SetVariableVec3(FName("User.BeamLength"), { X = len, Y = 1, Z = 1 }) end)
    pcall(function() t.comp:SetVariableVec3(FName("BeamLength"), { X = len, Y = 1, Z = 1 }) end)
end
local function beamOn(t, from, to, life)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = fxAsset(C().beam_fx)
    if not (valid(lib) and sys and liveObj(t.o)) then return false end
    local ok, comp = pcall(function()                     -- (on the turret, kept where it is: it rides the SOLG)
        return lib:SpawnSystemAttached(sys, t.o:K2_GetRootComponent(), FName("None"), from, { Pitch = 0, Yaw = 0, Roll = 0 }, 1, true, true, 0, true)
    end)
    if not (ok and comp and liveObj(comp)) then
        if not SLAS.failSaid then SLAS.failSaid = true; sl("its beam couldn't be made: " .. tostring(comp)) end
        return false
    end
    pcall(function() comp:SetVariableFloat(FName("User.BeamLifeTime"), life) end)
    pcall(function() comp:SetVariableFloat(FName("BeamLifeTime"), life) end)
    t.comp = comp
    aimBeam(t, from, to)
    sound(t.o, true)
    t.sndOn = true
    return true
end
-- every live, open laser turret of this game's SOLG (SOLG.laserTurrets: { o, bone, live, open })
local T = {}                                               -- (per turret, by its bone: its cycle)
function SLAS.stop()
    for _, t in pairs(T) do beamOff(t) end
    T = {}
end
function SLAS.tick(now)
    local c = C()
    if c.enabled == false or not (SOLG and SOLG.laserTurrets) then return end
    local list = SOLG.laserTurrets()
    if not list then if next(T) then SLAS.stop() end; return end
    local pawn = nil
    pcall(function() pawn = survivalPC.Pawn end)
    local you = pawn and liveObj(pawn) and at(pawn) or nil
    local reach = num(c.reach_m, 1500) * 100
    local seen = {}
    for _, e in ipairs(list) do
        local t = T[e.bone]
        if not t then
            t = { bone = e.bone, nextAt = now + math.random() * num(c.rest_s, 5) }   -- (staggered: never all at once)
            T[e.bone] = t
        end
        t.o = e.o
        seen[e.bone] = true
        local from = e.live and e.open and liveObj(e.o) and at(e.o) or nil
        if not from then
            beamOff(t)
        elseif t.comp then                                 -- (firing: kept on you, a hit every hit_s, off at its end)
            local d = you and math.sqrt((you.X - from.X) ^ 2 + (you.Y - from.Y) ^ 2 + (you.Z - from.Z) ^ 2) or math.huge
            if now >= t.offAt or not you then
                beamOff(t)
                t.nextAt = now + num(c.rest_s, 5)
            else
                aimBeam(t, from, you)
                if d <= reach * 1.1 and now >= (t.hitAt or 0) then
                    t.hitAt = now + num(c.hit_s, 1)
                    local dmg = num(c.damage, 5)
                    local okD = pcall(function() pawn:ModifyHealth(-dmg, e.o, true) end)
                    if not okD then pcall(function() pawn:ModifyHealth(-dmg, nil, true) end) end
                    SLAS.hits = (SLAS.hits or 0) + 1
                    if SLAS.hits == 1 or SLAS.hits % 25 == 0 then sl(string.format("%d hits on you (%s, %.1f km, %d a hit)", SLAS.hits, e.bone, d / 100000, dmg)) end
                end
            end
        elseif now >= t.nextAt and you and not (downNow and downNow()) then
            local d = math.sqrt((you.X - from.X) ^ 2 + (you.Y - from.Y) ^ 2 + (you.Z - from.Z) ^ 2)
            if d <= reach then
                local life = num(c.fire_s, 10)
                if beamOn(t, from, you, life) then
                    t.offAt, t.hitAt = now + life, now + num(c.first_hit_s, 0.5)
                    SLAS.bursts = (SLAS.bursts or 0) + 1
                    if SLAS.bursts <= 2 or SLAS.bursts % 20 == 0 then sl(string.format("burst %d: %s at you, %.1f km", SLAS.bursts, e.bone, d / 100000)) end
                else
                    t.nextAt = now + 2
                end
            else
                t.nextAt = now + 0.5                       -- (out of reach: looked at again soon)
            end
        end
    end
    for b, t in pairs(T) do if not seen[b] then beamOff(t); T[b] = nil end end
end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the SOLG's own lasers"] = function() T = {} end end
