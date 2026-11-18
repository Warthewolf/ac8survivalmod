-- sv_fleet_lasers.lua: the fleet's Aegis lasers (the user's dev install only; 2026-11-17, the user: "I want the Aegis Ships
-- in the Invincible Fleet Round to Carry 2 Lasers Interceptors one on the Aft and the Bow, targettable", the mount "TANACORN's
-- LASER turret"), sv_fleet.lua's piece after sv_fleet_round.lua. Part of AC8 Survival Mode's runtime, run by main.lua in
-- MODULES' order: a name another part uses is a global of this mod's Lua state, its own helpers stay local. The whole piece
-- is one test-only block, which tools/strip_test_only.py takes out of every release and test zip, and tools/dev_only.py out
-- of a TESTER zip, only this header left there.
-- A TANI=1 build's Aegis (BP_SV_IF_Aegis, tools/tanicorn/spec.py) carries two LASER mounts, LASER_BOW and LASER_AFT, each a
-- part of its ship (its box, health and pay). As an Aegis settles (sv_fleet.lua's onSettle) its mounts are put at their
-- spots (CFG.specials.fleet.lasers, metres in the hull's frame) and handed to AC7's LaserInterceptor (sv_escort_li.lua's
-- carrier lists, ZLI.extras.fleet) on the players' missiles; a mount shot off or its ship sunk: its laser gone.
-- Log: `fleet lasers: <SHIP>: 2 mounts handed to AC7's LaserInterceptor (...)`, then sv_escort_li.lua's `zfa li:` lines.
-- TEST ONLY BEGIN (the fleet's Aegis lasers: test builds only, the user's dev install)
IFLASER = {}
do
local L = {}                                              -- the mounts by address: { o, a, name, unit, body, ship, where }
local MUZZLE = "SOC_Gun_01"                               -- (the LASER mount's muzzle, as THE TANACORN's: sv_tanicorn.lua)
local function lc() return (CFG.specials and CFG.specials.fleet or {}).lasers or {} end
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function llog(s) log("fleet lasers: " .. s) end
local function laserPart(e) return type(e.cls) == "string" and e.cls:lower():find("tani_laser", 1, true) ~= nil end
local function same(e) return e ~= nil and liveAddr(e.o) == e.a and nameOf(e.o) == e.name end   -- (hard rule 59)
local function turretMesh(o) local m; pcall(function() m = o.TurretPoseableMesh end); return m end
local function shipName(sh) return (IFLEET and IFLEET.label and IFLEET.label(sh)) or tostring(sh.name or sh.unit) end
local function slotOf(o)                                  -- its component on the hull (LASER_BOW / LASER_AFT) and its name
    local c, nm
    pcall(function() c = o.RootComponent:GetAttachParent(); nm = c:GetFName():ToString() end)
    return nm, c
end
local function place(comp, where)                         -- (spots: { ahead m, right m, up m, yaw }; none: the build's spot)
    local p = (lc().spots or {})[where or ""]
    if type(p) ~= "table" or not comp then return "its built spot" end
    local ok, err = pcall(function()
        comp:K2_SetRelativeLocationAndRotation({ X = n(p[1], 0) * 100, Y = n(p[2], 0) * 100, Z = n(p[3], 0) * 100 },
            { Pitch = 0, Yaw = n(p[4], 0), Roll = 0 }, false, {}, true)
    end)
    if not ok then return "NOT moved (" .. tostring(err) .. ")" end
    return string.format("%.1f m ahead, %.1f m up, yaw %.0f", n(p[1], 0), n(p[3], 0), n(p[4], 0))
end
local function carriers()                                  -- (sv_escort_li.lua reads these each tick)
    local out = {}
    for a, e in pairs(L) do
        local h = nil
        if same(e) then pcall(function() h = e.o.HealthInternal end) end
        if not same(e) or (e.ship and e.ship.sunk) or (type(h) == "number" and h <= 0) then
            L[a] = nil                                    -- (gone, another object at its address, shot off or its ship sunk)
        else
            if not (e.body and valid(e.body)) then e.body = turretMesh(e.o) end
            out[#out + 1] = { o = e.o, a = a, unit = e.unit, body = e.body, socket = MUZZLE, foe = "players" }
        end
    end
    return out
end
IFLASER.carriers = carriers
function IFLASER.onSettle(F, sh)
    if lc().enabled == false or sh.kind ~= "aegis" then return end
    local said = {}
    for _, e in ipairs(sh.parts or {}) do
        if laserPart(e) and liveAddr(e.obj) == e.addr then
            local where, comp = slotOf(e.obj)
            L[e.addr] = { o = e.obj, a = e.addr, name = e.name, unit = sh.unit, body = turretMesh(e.obj), ship = sh, where = where }
            said[#said + 1] = string.format("%s %s", tostring(where), place(comp, where))
        end
    end
    if #said == 0 then
        llog(string.format("%s: no laser mounts among its %d parts (a build without TANI=1: the stock Aegis)", shipName(sh), #(sh.parts or {})))
        return
    end
    if HIT then HIT.wantMine = true end                   -- (the players' missiles kept for them: sv_ladon.lua)
    if ZLI then ZLI.extras = ZLI.extras or {}; ZLI.extras.fleet = carriers end
    local on = ZLI and ZLI.on and ZLI.on()
    local z = ((CFG.allies or {}).carrier or {}).zfa or {}
    llog(string.format("%s: %d mounts handed to AC7's LaserInterceptor (%s; a volley %s s, a rest %s s)%s", shipName(sh), #said,
        table.concat(said, "; "), tostring(z.li_volley_s), tostring(z.li_rest_s),
        on and "" or string.format(": the laser is NOT on (mode %s: a ZFA=1 build's main menu turns it on)", tostring(ZLI and ZLI.mode))))
end
if IFLEET then IFLEET.onSettle = IFLASER.onSettle end
-- ((0.74.165) WP9: the first missile a fleet laser shoots down in a round: LASER DEFENCE ONLINE and Control's line, once)
local saidRound = nil
if ZLI then
    ZLI.onKill = function(r)
        if not (IFLEET and IFLEET.cur and D and D.round) or saidRound == D.round then return end
        if not tostring(r and r.name or ""):find("Tani_LASER", 1, true) then return end
        saidRound = D.round
        local t = lc().text or {}
        hudCallout(t.online or "LASER DEFENCE ONLINE", t.online_sub or "SHOOT THE LASER MOUNTS FIRST")
        if SUB and SUB.say then
            local sp = ((CFG.hud or {}).subs or {}).speakers or {}
            pcall(SUB.say, sp.CTRL or "CTRL", t.online_radio or "Their lasers are burning our missiles down! Take out the laser mounts first!")
        end
        llog("LASER DEFENCE ONLINE: the first missile a fleet laser shot down this round (" .. tostring(r.name) .. ")")
    end
end
if type(LEVEL_DROPS) == "table" then                       -- (the level's objects went with it)
    LEVEL_DROPS["fleet lasers"] = function() L = {}; if ZLI and ZLI.extras then ZLI.extras.fleet = nil end end
end
end
-- TEST ONLY END
