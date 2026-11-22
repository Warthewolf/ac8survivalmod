-- VALKA's SOLG in co-op (the user, 2026-11-22: "Is this all synced for coop?" ... "you need to start on it pronto").
-- Her round runs on the host alone; the SOLG's pieces are units (sv_solg.lua), so co-op already mirrors them: each joiner
-- has copies of them, its hits on them go to the host ("ht"), the host's health comes back ("hp"). This part is the rest:
-- the host's word on each step, "vs|<kind>|...", and each joiner drawing the same thing on its own game:
--   po|x|y|z|yaw|size     its portal opens (metres; the SOLG's size, metres across)
--   up|x|y|z|yaw|vx|vy|vz|T|age   the SOLG out of it at x, y, z (metres), flying vx, vy, vz (cm/s), T s to the pad, age s ago
--   ph|n                  phase n on (its lasers' copies placed as they come)
--   b|bone                a piece broken (its wing falling, its arm when its last KEW shell's gone: the same rules here)
--   dn                    destroyed (falling apart)        hit|x|y|z   it hit the spaceport (Mission 25's strike there)
--   vg|1 / vg|0           VALKA gone through a portal / back (her copy here hidden / shown)
--   st                    taken down (its wreck gone, her round over)
-- A joiner who links mid-fight gets the picture (SCOOP.syncTo from hostSync): its portal, the SOLG where it is now, its
-- phase and every piece broken so far. The lines: SUB.say's own "sb"; the airfield: "af"; the pay: the host's, sent as
-- "cr" (sv_coop_migration.lua's addCredits, the round mirrored). Log lines `solg coop: ...`.
SCOOP = SCOOP or {}

local function sl(s) log("solg coop: " .. s) end
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function fin(v, lim) v = tonumber(v); return v ~= nil and v == v and math.abs(v) <= lim end
local function host() return COOP ~= nil and COOP.host ~= nil and COOP.host() == true end
local function client() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function vc() return CFG.specials and CFG.specials.valka end

-- ---- the host ----
local H = { broken = {}, phase = nil, up = nil, po = nil, gone = false }
local function say(...) if host() and COOP.valkaSolg then pcall(COOP.valkaSolg, ...) end end
local function m(v) return string.format("%.0f", n(v, 0) / 100) end
function SCOOP.portal(at, yaw, size_m)
    H.po = { at = at, yaw = yaw, size = size_m, t = os.clock() }
    say("po", m(at.X), m(at.Y), m(at.Z), string.format("%.0f", yaw or 0), string.format("%.0f", size_m or 0))
end
function SCOOP.up(from, yaw, vel, T)
    H.up, H.broken, H.phase, H.po = { from = from, yaw = yaw, vel = vel, T = T, t = os.clock() }, {}, 1, nil
    say("up", m(from.X), m(from.Y), m(from.Z), string.format("%.0f", yaw or 0), string.format("%.0f", vel.X),
        string.format("%.0f", vel.Y), string.format("%.0f", vel.Z), string.format("%.0f", T or 0), "0")
end
function SCOOP.phase(ph) H.phase = ph; say("ph", string.format("%d", ph)) end
function SCOOP.broke(bone) H.broken[#H.broken + 1] = bone; say("b", bone) end
function SCOOP.destroyed() H.dn = true; say("dn") end
function SCOOP.hit(P) H.up, H.po = nil, nil; say("hit", m(P.X), m(P.Y), m(P.Z)) end
function SCOOP.gone(on) H.gone = on == true; say("vg", on and "1" or "0") end
function SCOOP.stop() if H.up or H.po or H.gone then say("st") end; H = { broken = {}, gone = false } end
-- (hostSync) a joiner linking now: the picture as it stands
function SCOOP.syncTo(to)
    if not (host() and COOP.msg) then return end
    local function tell(...) pcall(COOP.msg, to, "vs", ...) end
    if H.gone then tell("vg", "1") end
    if H.po and not H.up then
        tell("po", m(H.po.at.X), m(H.po.at.Y), m(H.po.at.Z), string.format("%.0f", H.po.yaw or 0), string.format("%.0f", H.po.size or 0))
    end
    local u = H.up
    if u then
        tell("up", m(u.from.X), m(u.from.Y), m(u.from.Z), string.format("%.0f", u.yaw or 0), string.format("%.0f", u.vel.X),
            string.format("%.0f", u.vel.Y), string.format("%.0f", u.vel.Z), string.format("%.0f", u.T or 0),
            string.format("%.1f", os.clock() - u.t))
        for ph = 2, H.phase or 1 do tell("ph", string.format("%d", ph)) end
        for _, b in ipairs(H.broken) do tell("b", b) end
        if H.dn then tell("dn") end
    end
    sl(string.format("player %d linked mid-fight: the SOLG's picture sent (%s, phase %s, %d broken)", (to or 0) + 1,
        u and "up" or (H.po and "its portal" or "none"), tostring(H.phase), #H.broken))
end

-- ---- a joiner ----
local J = { ph = {}, gone = false }
local function valkaCopies()
    local c = vc()
    return (c and COOP.planeCopies) and COOP.planeCopies(c.unit) or {}
end
local function hideValka(on)
    local nn = 0
    for _, o in ipairs(valkaCopies()) do
        if valid(o) then
            pcall(setGone, o, on); nn = nn + 1
            pcall(function() o.bIsActivated = not on end)   -- (off the radar and out of the fight, as the host's: 2026-11-22)
        end
    end
    return nn
end
function SCOOP.fromHost(f)
    if not (client() and D and SOLG) then return end
    local k, c = f[2], vc()
    if not c then return end
    local now = os.clock()
    if k == "po" then
        local x, y, z, yaw, size = n(f[3]), n(f[4]), n(f[5]), n(f[6]), n(f[7])
        if not (fin(x, 2e5) and fin(y, 2e5) and fin(z, 4e4) and fin(yaw, 720) and fin(size, 2e4)) then return end
        if type(c.portal) == "table" and c.portal.enabled then
            local pc = {}
            for kk, v in pairs(c.portal) do pc[kk] = v end
            pc.size_m, pc.max_s, pc.face_you = size, n(c.solg and c.solg.portal_max_s, 40), false
            J.ph = {}
            pcall(SPC.V.portalOpen, c, J.ph, { X = x * 100, Y = y * 100, Z = z * 100 }, yaw, now, pc, true)
            J.phOut = now + n(pc.open_s, 4.5) + 6
        end
        sl(string.format("the host's portal opens at (%.1f, %.1f) km, %.0f m across", x / 1000, y / 1000, size))
    elseif k == "up" then
        local x, y, z, yaw = n(f[3]), n(f[4]), n(f[5]), n(f[6])
        local vx, vy, vz, T, age = n(f[7]), n(f[8]), n(f[9]), n(f[10]), n(f[11], 0)
        if not (fin(x, 2e5) and fin(y, 2e5) and fin(z, 4e4) and fin(yaw, 720) and fin(vx, 1e6) and fin(vy, 1e6) and fin(vz, 1e6)
            and fin(T, 3600) and fin(age, 3600)) then return end
        local at = { X = x * 100 + vx * age, Y = y * 100 + vy * age, Z = z * 100 + vz * age }
        local ok = SOLG.spawn(at, yaw, { X = vx, Y = vy, Z = vz })
        local placed = ok and SOLG.mirrorUp() or 0
        J.up = ok
        sl(string.format("the host's SOLG %s (%.0f s in, %d of its pieces placed so far: the rest as their copies come)",
            ok and "up here" or "NOT up here", age, placed))
    elseif k == "ph" then
        local ph = n(f[3])
        if ph and ph >= 1 and ph <= 9 then SOLG.mirrorPhase(ph) end
    elseif k == "b" then
        local bone = tostring(f[3] or ""):match("^[%w_]+$")
        if bone and #bone <= 16 then SOLG.breakBone(bone) end   -- (its pay: the host's own, sent as "cr" with the round's)
    elseif k == "dn" then
        local L = SOLG.where and SOLG.where()
        if L and fxAt then fxAt(SOLG.C.fx, L, n(SOLG.C.fx_scale.SOLG, 12), 10) end
        pcall(SOLG.fall)
        J.wreckUntil = now + n(c.solg and c.solg.wreck_s, 25)
        sl("the host's SOLG destroyed: falling apart here")
    elseif k == "hit" then
        local x, y, z = n(f[3]), n(f[4]), n(f[5])
        if not (fin(x, 2e5) and fin(y, 2e5) and fin(z, 4e4)) then return end
        local P = { X = x * 100, Y = y * 100, Z = z * 100 }
        local g = c.solg or {}
        local okQ = VSOLG and VSOLG.strike and VSOLG.strike(g.hit_seq, P, n(g.hit_fx_s, 20))
        if not okQ then fxAt(g.hit_fx or {}, P, n(g.hit_fx_scale, 12), n(g.hit_fx_s, 20)) end
        pcall(SOLG.stop, "it hit the host's spaceport")
        sl("the host's SOLG hit the spaceport: Mission 25's strike here")
    elseif k == "vg" then
        J.gone = f[3] == "1"
        sl(string.format("VALKA %s here (%d copies of her)", J.gone and "gone through a portal" or "back", hideValka(J.gone)))
    elseif k == "st" then
        SCOOP.clientStop("the host's word")
    end
end
function SCOOP.clientStop(why)
    if J.ph and J.ph.portal then pcall(SPC.V.portalStop, J.ph) end
    if SOLG and SOLG.up and SOLG.up() then pcall(SOLG.stop, why) end
    if J.gone then hideValka(false) end
    J = { ph = {}, gone = false }
end
-- each tick on a joiner (sv_coop's): its portal, the SOLG, its wreck's time, her copies kept hidden
function SCOOP.clientTick(now)
    if not client() then return end
    local c = vc()
    if J.ph and J.ph.portal and c then
        pcall(SPC.V.portalTick, c, J.ph, now)
        if J.phOut and now >= J.phOut then J.phOut = nil; pcall(SPC.V.portalThrough, c, J.ph, now) end
    end
    if SOLG and SOLG.tick then SOLG.tick(now) end
    if VSOLG and VSOLG.strikesTick then pcall(VSOLG.strikesTick, now) end   -- (the host's spaceport strike here: stopped in time)
    if J.wreckUntil and now >= J.wreckUntil then J.wreckUntil = nil; pcall(SOLG.stop, "its wreck's gone") end
    if J.gone and now >= (J.hideAt or 0) then J.hideAt = now + 1; hideValka(true) end   -- (a copy of her made since)
end
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the SOLG's co-op"] = function() H = { broken = {}, gone = false }; J = { ph = {}, gone = false } end
end
