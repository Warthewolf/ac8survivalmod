-- decoy_test.lua <mod dir> <work dir> (run by tools/checks/decoy_test.sh): THE DECOY (Scripts/sv_decoy.lua,
-- CFG.specials.decoy) on the real sv_core, sv_config and sv_decoy, the game stubbed (a spawner that makes each unit's
-- objects and records them as sv_rounds.lua's feed does, the event package's flags, the planes):
--   the round's kind (its ready: switched on, once a run, its units in the world data; its fighters; its NEXT row);
--   the bait: its laser and ping, the trap sprung when it's down (paid) or on its clock (unpaid);
--   the trap's spawns: 2.5-5 km from a player at any bearing, out of the safe circle and inside the zone, gap_km apart,
--     per_player_max near each player, max_up at once, max_total in all;
--   the closest valid player locked (not one DOWN, inside the safe circle, on the airfield or stale);
--   the lock: its mark on the plane (attached, else moved each tick), its laser, the 8 s timed by Lua, the radio, the
--     Spear at the end (RE_SV_DecoySpear_<s>, the launchers in turn), its impact and the sure kill behind sure_kill;
--     the strike cancelled when the UAV goes down, when you're inside the safe circle, when you're DOWN;
--   the lead (the rod's PredictionTime from the feed; the led point's maths);
--   the end: all down, everyone safe, the time; the reward and its x for safe; the leftovers taken off unpaid;
--   the recycles, one a recycle_gap_s;
--   the main menu: the trap UAVs' DT_NPC row (DECOY.setup), no round without it; the marks' last fallback, the build's
--     teleport onto your plane (RE_SV_DecoyMarkOnMe_<nn>) when a move doesn't hold either;
--   co-op: the host's "dk" (each lock's UAV and target slot; no strike on the host for a joiner's lock), a joiner's
--     strike on its own locks only, a killing hit sent there cancelling it (COOP.killSent), the guards on "dk", the
--     Spear and the sure kill never forwarded (sv_coop.lua KEEP_EVENTS) and skipped on a host who's DOWN.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore
math.randomseed(7)
VERSION = "0.73.85-decoy.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
function FindAllOf() return {} end
function FindFirstOf() return nil end
local statics = {}
function StaticFindObject(p) return statics[p] end
local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.name or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function liveAddr(o) return valid(o) and (addrOf(o) or 1) or nil end
svLevelOn = true
part("sv_config.lua")
SPC = SPC or {}
SPC.kinds, SPC.CLEAN_OBJ, SPC.cleanWatch, SPC.seenUnits = {}, {}, {}, {}
part("sv_decoy.lua")
local C = CFG.specials.decoy

---------------------------------------------------------------------------------------------------- the main menu
-- the trap UAVs' DT_NPC row (DT_SV_NpcRows' SV_DecoyUav) into DT_NPC, as the shoal's (sv_fishing.lua FISH.setup)
print("the main menu")
do
    local GI = { name = "GameInstance", addr = 0x10 }
    function gameInstance() return GI end
    function pin() return true end
    local function dt(name, rows)
        local t = { name = name, addr = 0x20 + #name, rows = rows }
        function t:FindRow(r) return self.rows[tostring(r)] end
        function t:AddRow(r, v) self.rows[tostring(r)] = v end
        return t
    end
    local npcT, mineT = dt("DT_NPC", {}), dt("DT_SV_NpcRows", { [C.dt_npc] = { row = "uav" } })
    statics[PROBE_TABLES[2].path], statics[CFG.specials.shuttle.npc_rows] = npcT, mineT
    DECOY.setup()
    local said = false
    for _, l in ipairs(logs) do if l:find("decoy: the trap UAVs' row SV_DecoyUav in DT_NPC", 1, true) then said = true end end
    check(C.dt_npc == "SV_DecoyUav" and npcT.rows.SV_DecoyUav ~= nil and DECOY.rowOk == true and said,
        "the trap UAVs' row SV_DecoyUav into DT_NPC at the main menu, logged")
end

---------------------------------------------------------------------------------------------------- the game, stubbed
local events, credits, callouts, specials, recycles = {}, {}, {}, {}, {}
local MISSING_EV, MISSING_UNIT = {}, {}
function SV_Event(n) events[#events + 1] = n; return MISSING_EV[n] and -2 or 1 end
SV_ERR = { [-2] = "no such unit", [-3] = "its last flight is still up" }
function addCredits(n, why) credits[#credits + 1] = { n = n, why = why } end
function specialPay(n) return n end
function hudCallout(t, s) callouts[#callouts + 1] = tostring(t) .. " / " .. tostring(s) end
LB = { stat = function() end, special = function(k, won, s) specials[#specials + 1] = { kind = k, won = won, s = s } end }
function nativeReady() return true end
function othersFlying() return 0 end
local ON_AF = false
function playerOnAirfield() return ON_AF end
local HITS = 0
function svFlags() return { [DECOY.HIT_FLAG] = HITS } end
local ATTACH_WORKS, MOVE_WORKS = true, true
local nextAddr = 0x1000
local function obj(name, hp, at)
    nextAddr = nextAddr + 0x10
    local o = { name = name .. "_C_" .. nextAddr, addr = nextAddr, HealthInternal = hp, at = at or { X = 0, Y = 0, Z = 0 },
                vel = { X = 0, Y = 0, Z = 0 } }
    function o:K2_GetActorLocation()
        if self.parent and ATTACH_WORKS then return self.parent:K2_GetActorLocation() end
        return { X = self.at.X, Y = self.at.Y, Z = self.at.Z }
    end
    function o:GetVelocity() return self.vel end
    function o:GetActorForwardVector() return { X = 0, Y = -1, Z = 0 } end
    function o:K2_AttachToActor(p) self.parent = p; return true end
    function o:GetAttachParentActor() return self.parent end
    function o:K2_DetachFromActor() self.parent = nil end
    function o:K2_SetActorLocation(v)            -- (MOVE_WORKS false: the call answers, the game puts it back)
        if MOVE_WORKS then self.at = { X = v.X, Y = v.Y, Z = v.Z } end
        self.moved = (self.moved or 0) + 1
        return true
    end
    function o:SetActive() end
    function o:SetActorHiddenInGame(h) self.hidden = h end
    function o:SetActorEnableCollision() end
    function o:SetActorTickEnabled() end
    return o
end
-- each unit's objects as the spawner makes them, recorded as sv_rounds.lua's feed records a watched unit's
local world = {}
local function kindOf(unit)
    if unit == C.bait_unit or unit:find(C.uav_prefix, 1, true) == 1 then return "uav" end
    if unit == C.bait_mark or unit:find(C.mark_prefix, 1, true) == 1 then return "mark" end
    if unit:find(C.spear_prefix, 1, true) == 1 then return "spear" end
    return nil
end
function SV_Spawn(unit, x, y, z, yaw)
    local k = kindOf(unit)
    if not k or MISSING_UNIT[unit] then return -2 end
    if world[unit] and world[unit].up then return -3 end
    local at = x and { X = x, Y = y, Z = z } or { X = 0, Y = 0, Z = 300000 }
    local list = {}
    if k == "uav" then
        list = { obj("BP_OP0033_uavst_CP", 60, at), obj("BP_OP0033_uavst_laser_CP", 1000, at) }
        list[2].SearchPhaseTime, list[2].DesignatePhaseTime = 30, 15
    elseif k == "mark" then list = { obj("BP_AI_Dummy_Relative_Air", 1000, at) }
    else list = { obj("BP_OP0034_aship_RoG_ms19_CP", 1000, at), obj("BP_AI_TargetingDummy", 1000, at) } end
    world[unit] = { up = true, objs = list, yaw = yaw, at = at }
    if SPC.cleanWatch[unit] then
        local l = { at = os.clock() }
        for _, o in ipairs(list) do l[#l + 1] = o end
        SPC.CLEAN_OBJ[unit] = l
        SPC.seenUnits[unit] = true
    end
    return 1
end
function SV_UnitAlive(unit)
    if not kindOf(unit) or MISSING_UNIT[unit] then return -2 end
    local w = world[unit]
    if not (w and w.up) then return -7 end
    local n = 0
    for _, o in ipairs(w.objs) do if not o.gone and o.HealthInternal > 0 then n = n + 1 end end
    return n
end
function SV_Recycle(unit, force) recycles[#recycles + 1] = unit .. ":" .. tostring(force); if world[unit] then world[unit].up = false end; return 1 end
local function bodyOf(unit) return world[unit] and world[unit].objs[1] end

-- you: 30 km north of the runway, 3 km up
local me = obj("BP_PlayerPlane_PP0001_f16c", 1000, { X = 1610476, Y = -3436142, Z = 300000 })
survivalPC = { name = "PC", Pawn = me }
function playerLocation() return me:K2_GetActorLocation() end

local now = 0
local function evs(pat) local n = 0; for _, e in ipairs(events) do if e:find(pat) then n = n + 1 end end; return n end
local function logged(pat) for _, l in ipairs(logs) do if l:find(pat) then return l end end return nil end
local function step(dt, host)
    local t1 = now + (dt or 0.25)
    while now < t1 - 1e-9 do
        now = now + 0.125; clock = clock + 0.125
        D.now = now
        if host ~= false and D.special and D.special.kind == "decoy" then SPC.kinds.decoy.tick(now, D.special) end
        DECOY.tick(now)
    end
end
local function fresh(round)
    events, credits, callouts, specials, recycles, logs = {}, {}, {}, {}, {}, {}
    world, HITS, ON_AF, ATTACH_WORKS, MOVE_WORKS = {}, 0, false, true, true
    me.HealthInternal, me.MaxHealth, me.at, me.vel, me.gone = 1000, 100, { X = 1610476, Y = -3436142, Z = 300000 }, { X = 0, Y = 0, Z = 0 }, nil
    SPC.CLEAN_OBJ, SPC.seenUnits = {}, {}
    for _, f in pairs(LEVEL_DROPS) do pcall(f) end
    D = { round = round or 12, now = 0, special = { kind = "decoy", state = "pending" } }
    RUN = { specialAt = {}, credits = 0 }
    COOP, DOWN, now = nil, nil, 0
    DECOY.st = { locks = 0, struck = 0, hits = 0, cancelled = 0 }
    DECOY.Q = { by = {}, n = {} }
end

---------------------------------------------------------------------------------------------------- the round's kind
print("the round's kind")
fresh()
local K = SPC.kinds.decoy
check(K and K.sub == "dc_sub" and CFG.hud.text.dc_sub ~= nil and type(K.spawn) == "function" and type(K.tick) == "function"
    and type(K.busy) == "function" and type(K.over) == "function" and type(K.row) == "function", "SPC.kinds.decoy, its callout's sub")
local inRot = false
for _, k in ipairs(CFG.specials.rotation) do if k == "decoy" then inRot = true end end
local inDef = false
for _, k in ipairs(CFG_DEFAULTS.specials.rotation) do if k == "decoy" then inDef = true end end
check(inRot and inDef and C.from_round == 10 and C.once_per_run == true, "in the rotation (a shipped default) from round 10, once a run")
check(K.budget(20) == 0 and K.budget(9) == 0, "no normal aircraft in the round by default (fighter_share 0: " .. K.budget(20) .. ")")
C.fighter_share = 0.3
check(K.budget(20) == 6 and K.budget(9) == 2, "fighter_share set: that share of the round's, whole 2-ships (" .. K.budget(20) .. ")")
C.fighter_share = 0
DECOY.rowOk = false
check(K.ready() == false and logged("no DECOY round: its UAVs' DT_NPC row SV_DecoyUav isn't in %(not added"), "not ready without its UAVs' row in DT_NPC, logged")
DECOY.rowOk = true
check(K.ready() == true and logged("units are in this build's world data"), "ready: its units in the world data")
RUN.specialAt.decoy = 11
check(K.ready() == false, "once a run: not again after its round")
DECOY.forced = true
check(K.ready() == true, "the test key's force goes past once a run")
DECOY.forced, RUN.specialAt.decoy = nil, nil
for _, f in pairs(LEVEL_DROPS) do pcall(f) end
MISSING_UNIT[DECOY.uav(35)] = true
check(K.ready() == false and logged("world data has no SV_Unit_DecoyUav_35"), "a build without its units: never")
MISSING_UNIT[DECOY.uav(35)] = nil
for _, f in pairs(LEVEL_DROPS) do pcall(f) end
C.enabled = false
check(K.ready() == false, "enabled = false: never")
C.enabled = true

---------------------------------------------------------------------------------------------------- the bait
print("the bait")
fresh()
local s = D.special
check(K.spawn(0) == true and s.state == "bait", "spawned: its state bait")
check(world[C.bait_unit] and world[C.bait_mark] and world[DECOY.spear(1)] and world[DECOY.spear(4)], "the bait, its mark and 4 launchers up")
check(callouts[1] and callouts[1]:find(CFG.hud.text.dc_go, 1, true), "its callout")
step(0.25)
check(evs("^RE_SV_DecoyBaitLaser$") == 1 and evs("^RE_SV_DecoyBaitPing$") == 1, "its laser on its mark, its ping")
local podB = world[C.bait_unit].objs[2]
check(podB.SearchPhaseTime == C.lock_delay_s and podB.DesignatePhaseTime == C.bait_timeout_s + 120,
    "its pod's phases on the instance: its laser held through its whole wait (" .. tostring(podB.DesignatePhaseTime) .. " s)")
step(13)
check(evs("^RE_SV_DecoyBaitPing$") == 2, "pinged again ping_every_s on")
check(K.busy(s) and K.row(s, CFG.hud.text):find("RECON DRONE", 1, true), "busy, its NEXT row")
bodyOf(C.bait_unit).HealthInternal = 0
step(0.5)
check(s.state == "trap" and #credits == 1 and credits[1].n == C.pay.bait + C.pay.bait_per_round * 12, "shot down: paid ("
    .. tostring(credits[1] and credits[1].n) .. "), the trap springs")
check(evs("^RE_SV_DecoyRadio_Brief$") == 1 and evs("^RE_SV_DecoyBaitLaserOff$") == 1, "the brief on the radio, its laser off")

print("the bait on its clock")
fresh()
s = D.special
K.spawn(0)
ON_AF = true
step(C.bait_timeout_s + 5)
check(s.state == "bait", "its clock stops while you're down at the airfield")
ON_AF = false
step(C.bait_timeout_s + 1)
check(s.state == "trap" and #credits == 0, "not shot down in bait_timeout_s: the trap springs, unpaid")

---------------------------------------------------------------------------------------------------- spawns
print("the trap's spawns")
local okSpots, n, lo, hi = true, 0, 1e9, 0
local ups = {}
local you = { X = 1610476, Y = -3436142, Z = 300000 }
for _ = 1, 400 do
    local p = DECOY.spawnSpot(you, ups, C)
    if p then
        n = n + 1
        local d2 = math.sqrt((p.X - you.X) ^ 2 + (p.Y - you.Y) ^ 2) / 100000
        lo, hi = math.min(lo, d2), math.max(hi, d2)
        if math.abs(p.Z - you.Z) > C.alt_m * 100 + 1 or DECOY.inSafe(p, C) then okSpots = false end
        for _, q in ipairs(ups) do
            if math.sqrt((p.X - q.X) ^ 2 + (p.Y - q.Y) ^ 2 + (p.Z - q.Z) ^ 2) < C.gap_km * 100000 then okSpots = false end
        end
        if #ups < 6 then ups[#ups + 1] = p end
    end
end
check(n > 300 and lo >= C.spawn_km[1] - 1e-6 and hi <= C.spawn_km[2] + C.alt_m / 1000 + 1e-6 and okSpots,
    string.format("spawn_km from you (%.2f-%.2f km flat), within alt_m, gap_km apart, out of the safe circle (%d spots)", lo, hi, n))
local nearAf = { X = 1610476, Y = -436142 - 600000, Z = 300000 }     -- (6 km from the runway: half the ring is inside)
local inside = 0
for _ = 1, 200 do local p = DECOY.spawnSpot(nearAf, {}, C); if p and DECOY.inSafe(p, C) then inside = inside + 1 end end
check(inside == 0, "a player near the airfield: never a spot inside safe_km")
local edgeYou = { X = -707336, Y = -261895 - 3950000, Z = 300000 }  -- (0.5 km inside the zone's north edge)
local outZone = 0
for _ = 1, 200 do local p = DECOY.spawnSpot(edgeYou, {}, C); if p and p.Y < -261895 - 3800000 then outZone = outZone + 1 end end
check(outZone == 0, "near the zone's edge: never past edge_km of it")
local p1 = DECOY.spawnSpot(you, {}, C)
local yawTo = math.deg(math.atan(you.Y - p1.Y, you.X - p1.X))
check(math.abs(p1.yaw - yawTo) < 1e-6, "its yaw facing the player")

fresh()
s = D.special
K.spawn(0)
step(0.25)
bodyOf(C.bait_unit).HealthInternal = 0
step(1.5)
check(s.spawned == 1 and world[DECOY.uav(1)] and world[DECOY.mark(1)], "a UAV and its mark round you a second into the trap")
step(30)
local up = 0
for _, U in pairs(s.u) do if U.state == "up" then up = up + 1 end end
check(up == C.per_player_max and s.spawned == C.per_player_max, "per_player_max near you at most (" .. up .. " up)")
for _, U in pairs(s.u) do
    local d = math.sqrt((U.pos.X - me.at.X) ^ 2 + (U.pos.Y - me.at.Y) ^ 2) / 100000
    if d < C.spawn_km[1] - 0.01 or d > C.spawn_km[2] + 0.01 then check(false, "a UAV out of spawn_km: " .. d) end
end

---------------------------------------------------------------------------------------------------- closest
print("the closest player")
local players = {
    { slot = 0, at = { X = 0, Y = -3000000, Z = 300000 }, alive = true, fresh = true },
    { slot = 1, at = { X = 100000, Y = -3000000, Z = 300000 }, alive = true, fresh = true, down = true },
    { slot = 2, at = { X = 1610476, Y = -436142, Z = 300000 }, alive = true, fresh = true },        -- (over the runway)
    { slot = 3, at = { X = 200000, Y = -3000000, Z = 300000 }, alive = true, fresh = false },
    { slot = 4, at = { X = 300000, Y = -3000000, Z = 300000 }, alive = true, fresh = true },
    { slot = 5, at = { X = 50000, Y = -3000000, Z = 300000 }, alive = true, fresh = true, onAirfield = true },
}
local e1 = DECOY.closest({ X = 120000, Y = -3000000, Z = 300000 }, players, C)
check(e1 and e1.slot == 0, "the nearest valid one (not one DOWN, stale or on the airfield): slot " .. tostring(e1 and e1.slot))
local e2 = DECOY.closest({ X = 1610476, Y = -500000, Z = 300000 }, players, C)
check(e2 and e2.slot == 4, "never one inside the safe circle, however near (the next nearest: slot " .. tostring(e2 and e2.slot) .. ")")
local e3 = DECOY.closest({ X = 290000, Y = -3000000, Z = 300000 }, players, C)
check(e3 and e3.slot == 4, "from another side: slot 4")
check(DECOY.closest({ X = 0, Y = 0, Z = 0 }, { players[2], players[3] }, C) == nil, "none valid: nobody")

---------------------------------------------------------------------------------------------------- the lock and the 8 s
print("the lock, the 8 s, the Spear")
fresh()
s = D.special
C.max_up, C.per_player_max = 1, 1
K.spawn(0)
step(0.25)
bodyOf(C.bait_unit).HealthInternal = 0
step(1.5)
step(C.lock_after_s + 0.5)
local g = DECOY.G[1]
check(g and g.armed and g.slot == 0 and evs("^RE_SV_DecoyLaserOn_01$") == 1, "UAV 1 locks you: its laser on its mark")
local mk = world[DECOY.mark(1)].objs[1]
check(mk.parent == me, "its mark attached to your plane")
local r = DECOY.R[1]
check(r and r.state == "count" and math.abs(r.strikeAt - r.at - (C.lock_delay_s + C.lock_s)) < 1e-6, "your 8 s (+ the search) run")
check(evs("^RE_SV_DecoyRadio_Lock$") == 1, "the radio's lock")
local podU = world[DECOY.uav(1)].objs[2]
check(podU.SearchPhaseTime == C.lock_delay_s and podU.DesignatePhaseTime == C.designate_s, "its pod's search and hold on the instance")
step(0.5)
check(DECOY.markMode == "attach" and logged("attached %(K2_AttachToActor held"), "the attach held: logged")
step(r.strikeAt - now - 0.3)
check(evs("^RE_SV_DecoySpear_") == 0 and evs("^RE_SV_DecoyRadio_Imminent$") == 1, "no Spear before the 8 s; the imminent call before it")
me.vel = { X = 25000, Y = 0, Z = 0 }
local rod = obj("BP_RodsFromGod", 1, { X = 0, Y = 0, Z = 5800000 })
rod.PredictionTime = 0
for _, fn in ipairs(notify["/Script/Live.LiveMeteoriteImpact"] or {}) do fn(rod) end
step(0.5)
check(rod.PredictionTime == C.lead.fall_s, "a rod from the feed led by the fall: PredictionTime " .. tostring(rod.PredictionTime))
check(evs("^RE_SV_DecoySpear_1$") == 1 and r.state == "struck", "the Spear called at 8 s: RE_SV_DecoySpear_1")
check(evs("^RE_SV_DecoyRadio_Incoming$") == 1, "the radio's incoming")
local sl = logged("the Spear called on you")
check(sl and sl:find("250 m/s", 1, true) and sl:find("400 m ahead", 1, true), "the call's line: your speed and the led point, 1.6 s (" .. tostring(sl) .. ")")
check(evs("^RE_SV_DecoyKill$") == 0, "no sure kill (sure_kill off)")
step(3)
HITS, me.HealthInternal = 1, 700
step(0.5)
check(logged("the Spear's impact %(SV_DecoySpearHit 0 %-> 1%)"), "its impact seen, your health logged")
step(1.25)
check(evs("^RE_SV_DecoyRadio_Hit$") == 1 and logged("a second after the Spear's impact: your health 70"), "it hurt you: the radio's hit")
step(C.relock_s)
check(DECOY.G[1] and DECOY.G[1].seq == 2 and s.locks == 2, "relock_s after the call it locks again")

print("the sure kill, the launchers in turn")
C.sure_kill = true
local r2 = DECOY.R[1]
step(r2.strikeAt - now + 0.2)
check(evs("^RE_SV_DecoySpear_2$") == 1, "the next launcher: RE_SV_DecoySpear_2")
HITS = 2
step(0.5)
check(evs("^RE_SV_DecoyKill$") == 1, "sure_kill: RE_SV_DecoyKill once the rod lands")
C.sure_kill = false

print("strikes cancelled")
step(C.relock_s + 1)
local r3 = DECOY.R[1]
check(r3 and r3.state == "count", "a third lock")
local spears = evs("^RE_SV_DecoySpear_")
step(3)
bodyOf(DECOY.uav(1)).HealthInternal = 0
step(0.5)
check(r3.state == "cancelled" and logged("UAV 1 down .- into its lock on you: strike cancelled"), "the UAV shot down: strike cancelled")
step(10)
check(evs("^RE_SV_DecoySpear_") == spears, "no Spear after it")
check(evs("^RE_SV_DecoyLaserOff_01$") >= 1, "its laser off")
local paid = 0
for _, cr in ipairs(credits) do if cr.why:find("Spear UAV shot down", 1, true) then paid = paid + cr.n end end
check(paid == C.pay.uav + C.pay.uav_per_round * 12, "the UAV paid (" .. paid .. ")")
local kill = false
for _, cr in ipairs(credits) do if cr.why:find(" down %(") then kill = true end end
check(not kill, "no pay of the round's reads as a kill's (\" down (\": co-op neither splits nor sends those)")
local rqU, rqM = false, false
for _, x in ipairs(recycles) do if x == DECOY.uav(1) .. ":1" then rqU = true end; if x == DECOY.mark(1) .. ":1" then rqM = true end end
check(rqU and rqM, "its unit and its mark off the spawner's list (forced: the pod and the mark keep them up)")
check(world[DECOY.uav(1)].objs[2].hidden == true and mk.hidden == true, "its pod and its mark switched off first")

-- safe and DOWN
step(5)
local k2 = nil
for k, rr in pairs(DECOY.R) do if rr.state == "count" then k2 = k end end
-- ((2026-11-07) one lock on you at a time, lock_gap_s after the last, a UAV relock_s after its own strike: the next
-- may take a while)
for _ = 1, 30 do
    if k2 then break end
    step(1)
    for k, rr in pairs(DECOY.R) do if rr.state == "count" then k2 = k end end
end
check(k2 ~= nil, "the next UAV locks you")
if k2 then
    spears = evs("^RE_SV_DecoySpear_")
    DOWN = { me = function() return true end }
    step(0.5)
    check(DECOY.R[k2].state == "cancelled" and logged("lock on you dropped: you're down"), "you're DOWN: dropped")
    DOWN = nil
    step(C.lock_s + 3)
    check(evs("^RE_SV_DecoySpear_") == spears, "no Spear on a player DOWN")
end

---------------------------------------------------------------------------------------------------- the move fallback
print("the marks moved when the attach doesn't hold")
fresh()
s = D.special
ATTACH_WORKS = false
C.max_up, C.per_player_max = 1, 1
K.spawn(0); step(0.25); bodyOf(C.bait_unit).HealthInternal = 0
step(C.lock_after_s + 2.5)
step(0.5)
local mk2 = world[DECOY.mark(1)].objs[1]
check(DECOY.markMode == "move" and logged("by a move each tick %(K2_AttachToActor didn't hold"), "the fallback logged")
local moved = mk2.moved or 0
me.at = { X = me.at.X + 50000, Y = me.at.Y, Z = me.at.Z }
step(0.25)
check((mk2.moved or 0) > moved and mk2.at.X == me.at.X, "the mark moved onto your plane each tick")
check(DECOY.moveHeld == true and logged("marks moved onto their planes each tick hold") and evs("^RE_SV_DecoyMarkOnMe_") == 0,
    "the move held: logged, no teleport")
step(C.lock_s + 3)
check(evs("^RE_SV_DecoySpear_") == 1, "the Spear all the same")

---------------------------------------------------------------------------------------------------- the teleport fallback
print("the build's teleport when a move doesn't hold either")
fresh()
s = D.special
ATTACH_WORKS, MOVE_WORKS = false, false
C.max_up, C.per_player_max = 1, 1
K.spawn(0); step(0.25); bodyOf(C.bait_unit).HealthInternal = 0
step(1.5)
check(world[DECOY.mark(1)] ~= nil, "UAV 1 and its mark up")
me.at = { X = me.at.X + 50000, Y = me.at.Y, Z = me.at.Z }   -- (you 500 m on: a move that didn't hold leaves the mark behind)
DECOY.markMode = "move"                                     -- (the attach already known not to hold this level)
step(C.lock_after_s + 1.5)
step(0.5)
check(DECOY.markMode == "teleport" and logged("didn't hold either") and logged("by the build's teleport %(RE_SV_DecoyMarkOnMe_01 fired%)"),
    "a move that doesn't hold either: the mark on your plane by RE_SV_DecoyMarkOnMe_01, logged")
local tp = evs("^RE_SV_DecoyMarkOnMe_01$")
step(0.5)
check(tp >= 1 and evs("^RE_SV_DecoyMarkOnMe_01$") > tp, "... each tick while the lock is on (" .. evs("^RE_SV_DecoyMarkOnMe_01$") .. ")")
step(C.lock_s + 3)
check(evs("^RE_SV_DecoySpear_") == 1, "the Spear all the same")
ATTACH_WORKS, MOVE_WORKS = true, true

---------------------------------------------------------------------------------------------------- the end
print("the end")
fresh()
s = D.special
C.max_up, C.per_player_max, C.max_total = 2, 2, 2
K.spawn(0); step(0.25); bodyOf(C.bait_unit).HealthInternal = 0
step(6)
check(s.spawned == 2, "two UAVs")
bodyOf(DECOY.uav(1)).HealthInternal = 0
step(0.5)
check(s.state == "trap", "one down: on")
bodyOf(DECOY.uav(2)).HealthInternal = 0
step(0.5)
local rw = credits[#credits]
check(s.state == "done" and s.endWhy == "all down" and rw.n == C.reward + C.reward_per_round * 12, "all max_total down: over, its reward")
check(specials[1] and specials[1].kind == "decoy" and specials[1].won == true and not K.busy(s), "beaten (LB.special), the round free to end")
check(callouts[#callouts]:find(CFG.hud.text.dc_done, 1, true), "its callout")

fresh()
s = D.special
C.max_total = 35
K.spawn(0); step(0.25); bodyOf(C.bait_unit).HealthInternal = 0
step(5)
local leftUp = s.spawned
me.at = { X = 1610476, Y = -436142, Z = 50000 }
step(C.safe_after_s + C.safe_hold_s + 1)
rw = credits[#credits]
check(s.state == "done" and s.endWhy == "safe" and rw.n == math.floor((C.reward + C.reward_per_round * 12) * C.reward_safe_x + 0.5),
    "everyone inside the safe circle safe_hold_s: over, its reward x" .. C.reward_safe_x)
check(specials[1] and specials[1].won == false, "safe: not beaten")
local taken = 0
for _, U in pairs(s.u) do if U.state == "left" then taken = taken + 1 end end
check(leftUp > 0 and taken == leftUp, "the UAVs still up taken off unpaid (" .. taken .. ")")

fresh()
s = D.special
K.spawn(0); step(0.25); bodyOf(C.bait_unit).HealthInternal = 0
step(C.trap_s + 1)
check(s.state == "done" and s.endWhy == "time", "trap_s up: over")
C.max_up, C.per_player_max = 12, 4

---------------------------------------------------------------------------------------------------- recycle pacing
print("recycles, one a recycle_gap_s")
fresh()
DECOY.recycleLater({ "SV_Unit_DecoyUav_05", "SV_Unit_DecoyMark_05", "SV_Unit_DecoyUav_06" }, "test", 1)
SV_Spawn("SV_Unit_DecoyUav_05"); SV_Spawn("SV_Unit_DecoyMark_05"); SV_Spawn("SV_Unit_DecoyUav_06")
D.special = nil
step(1.25, false)
check(#recycles == 1, "the first after its wait")
step(0.5, false)
check(#recycles == 1, "none more within recycle_gap_s")
step(2, false)
check(#recycles == 3, "the rest one a gap (" .. #recycles .. ")")

---------------------------------------------------------------------------------------------------- co-op: the host
print("two locks on you at a time, the hit judged, the fall learnt (2026-11-07, Alyssa's test)")
fresh()
s = D.special
C.max_up, C.per_player_max = 3, 3
K.spawn(0)
step(0.25)
bodyOf(C.bait_unit).HealthInternal = 0
local most, ups = 0, 0
local callAt, spears0 = {}, evs("^RE_SV_DecoySpear_")
for _ = 1, 160 do
    step(0.25)
    if evs("^RE_SV_DecoySpear_") > spears0 + #callAt then callAt[#callAt + 1] = now end
    local n = 0
    for _, rr in pairs(DECOY.R) do if rr.state == "count" then n = n + 1 end end
    if n > most then most = n end
    local u = 0
    for _, U in pairs(s.u or {}) do if U.state == "up" then u = u + 1 end end
    if u > ups then ups = u end
end
check(ups >= 3 and most >= 1 and most <= C.locks_per_player,
    string.format("at most locks_per_player locks on you at a time (%d) with %d UAVs up", most, ups))
local gapMin, gapMax = 999, 0
for i = 2, #callAt do gapMin = math.min(gapMin, callAt[i] - callAt[i - 1]); gapMax = math.max(gapMax, callAt[i] - callAt[i - 1]) end
check(#callAt >= 2 and gapMin >= C.lock_gap_s - 0.2, string.format("their strikes at least lock_gap_s apart (%d calls, %.2f s the closest)",
    #callAt, gapMin))
-- ((2026-11-07) the user: "have the strikes come every 10 seconds with the UAVs")
check(#callAt >= 3 and gapMax <= C.lock_gap_s + 0.6, string.format("a strike every lock_gap_s (%.1f) while they're up (%.2f s the longest)",
    C.lock_gap_s, gapMax))

fresh()
s = D.special
C.max_up, C.per_player_max = 1, 1
K.spawn(0)
step(0.25)
bodyOf(C.bait_unit).HealthInternal = 0
step(1.5)
step(C.lock_after_s + 0.5)
local rj = DECOY.R[1]
check(rj and rj.state == "count", "a lock")
step(rj.strikeAt - now + 0.2)
check(rj.state == "struck", "its Spear called")
step(1.75)
C.hit.chance = 1.0                                  -- (a sure roll for the flow; the odds checked below)
HITS = 1
step(0.5)
-- ((2026-11-07) the user: a hit is "heavy damage", not a kill)
check(evs("^RE_SV_DecoyKill$") == 0 and me.HealthInternal == 500 and logged("the Spear hits you %(judged: 0 m off.-a 100%% chance.-%-50 HP %(50%% of your 100%), 50 HP left"),
    "your line held, no health lost to the rod: the hit judged, half your health (no kill)")
local rk
for _ = 1, 120 do
    step(0.25)
    for _, rr in pairs(DECOY.R) do if rr.state == "count" then rk = rr end end
    if rk then break end
end
check(rk ~= nil, "the next lock")
if rk then
    step(rk.strikeAt - now + 0.2)
    me.at = { X = me.at.X + 60000, Y = me.at.Y, Z = me.at.Z }  -- (600 m off the line: you broke away)
    step(1.75)
    HITS = 2
    step(0.5)
    check(evs("^RE_SV_DecoyKill$") == 0 and me.HealthInternal == 500 and logged("the Spear missed you %(judged: 600 m off.-a 0%% chance"),
        "600 m off your line: it missed (no damage)")
end
C.hit.chance = 0.6
do                                                  -- (heavy damage: lethal only with half or less left; can_kill; 100 %)
    local k0 = evs("^RE_SV_DecoyKill$")
    me.HealthInternal = 400
    local what = DECOY.hurtMe(C)
    check(evs("^RE_SV_DecoyKill$") == k0 + 1 and what:find("lethal", 1, true), "a hit with half or less left: the kill (" .. what .. ")")
    C.hit.can_kill = false
    me.HealthInternal = 400
    what = DECOY.hurtMe(C)
    check(evs("^RE_SV_DecoyKill$") == k0 + 1 and me.HealthInternal == 10, "can_kill = false: 1 HP left (" .. what .. ")")
    C.hit.can_kill = true
    C.hit.damage_pct = 100
    me.HealthInternal = 1000
    what = DECOY.hurtMe(C)
    check(evs("^RE_SV_DecoyKill$") == k0 + 2, "damage_pct 100: every hit a kill, as before")
    C.hit.damage_pct = 50
    me.HealthInternal = 1000
end
check(math.abs(DECOY.hitChance(0) - 0.6) < 1e-9 and math.abs(DECOY.hitChance(100) - 0.3) < 1e-9 and DECOY.hitChance(200) == 0
      and DECOY.hitChance(500) == 0 and DECOY.hitChance(nil) == 0, "the odds: 60% on your line, 30% at 100 m off it, none from 200 m")
math.randomseed(7)
local hitsN = 0
for _ = 1, 2000 do if math.random() < DECOY.hitChance(0) then hitsN = hitsN + 1 end end
check(hitsN > 1100 and hitsN < 1300, "flying straight on, about 60 of 100 strikes hit (" .. hitsN .. " of 2000)")
check(#DECOY.falls == 2 and math.abs(DECOY.fallS() - 2.0) < 0.3, "the fall learnt from the impacts: " .. string.format("%.2f", DECOY.fallS()) .. " s")
DECOY.falls = { 0.1, 0.1, 0.1 }
check(DECOY.fallS() == C.lead.min_s, "the learnt fall kept within min_s .. max_s")
DECOY.falls = {}
check(DECOY.fallS() == C.lead.fall_s, "fall_s until two impacts are seen")

print("the bait's Spear on the airfield (2026-11-07: it did no damage)")
fresh()
s = D.special
C.max_up, C.per_player_max = 1, 1
AF = { bomb = 0, down = false }
K.spawn(0)
step(0.25)
local oldRod = obj("BP_RodsFromGod", 1, { X = 0, Y = 0, Z = 0 })              -- (a pooled rod made before: never the airfield's)
for _, fn in ipairs(notify["/Script/Live.LiveMeteoriteImpact"] or {}) do fn(oldRod) end
step(0.25)
bodyOf(C.bait_unit).HealthInternal = 0
step(0.5)
check(DECOY.bs ~= nil and logged("the bait's Spear on the airfield watched"), "the bait down: its Spear on the airfield watched")
local mk0 = DECOY.bs and DECOY.bs.mark
local rodA = obj("BP_RodsFromGod", 1, { X = mk0.X, Y = mk0.Y, Z = 5800000 })
for _, fn in ipairs(notify["/Script/Live.LiveMeteoriteImpact"] or {}) do fn(rodA) end
step(0.25)
rodA.at = { X = mk0.X + 30000, Y = mk0.Y, Z = 600 }                        -- (it came down 300 m from the mark)
step(0.125)
check(AF.bomb == 0, "not counted on the tick it moved")
step(0.25)
check(AF.bomb == C.bait_strike.damage and DECOY.bs == nil and logged("the bait's Spear landed on the airfield %(a rod stopped there%)")
      , string.format("landed 300 m from the mark: -%d airfield (AF.bomb %s)", C.bait_strike.damage, tostring(AF.bomb)))
check(oldRod.at.Z == 0 and AF.bomb == 40, "the rod made before the bait's end never counted")
-- none seen landing: the damage at the mark wait_s after a new rod showed
fresh()
s = D.special
AF = { bomb = 0, down = false }
K.spawn(0)
step(0.25)
bodyOf(C.bait_unit).HealthInternal = 0
step(0.5)
local rodB = obj("BP_RodsFromGod", 1, { X = 0, Y = 0, Z = 5800000 })
for _, fn in ipairs(notify["/Script/Live.LiveMeteoriteImpact"] or {}) do fn(rodB) end
step(0.25)
rodB.gone = true
step(C.bait_strike.wait_s + 0.5)
check(AF.bomb == C.bait_strike.damage and logged("none seen landing: at its mark"), "a rod seen, none landing: at the mark wait_s on")
COOP = { host = function() return false end, client = function() return true end, open = true, slot = 1 }
AF = { bomb = 0, down = false }
DECOY.baitStrikeStart(now)
local rodC = obj("BP_RodsFromGod", 1, { X = 0, Y = 0, Z = 5800000 })
for _, fn in ipairs(notify["/Script/Live.LiveMeteoriteImpact"] or {}) do fn(rodC) end
step(0.25, false)
rodC.gone = true
step(C.bait_strike.wait_s + 0.5, false)
check(AF.bomb == 0 and logged("the host's airfield takes the damage"), "a joiner: the blast only (the host's airfield takes the damage)")
COOP = nil
AF = nil

print("co-op: the host")
local sent = {}
local function coop(role, slot, list)
    COOP = { open = true, slot = slot, role = role }
    function COOP.host() return role == "host" end
    function COOP.client() return role == "join" end
    function COOP.msg(to, ...) local t = { ... }; for i = 1, #t do t[i] = tostring(t[i]) end; sent[#sent + 1] = (to or -1) .. ">" .. table.concat(t, "|"); return true end
    function COOP.players() return list end
    function COOP.slotOk(x) return type(x) == "number" and x >= 0 and x <= 23 and x == math.floor(x) end
    function COOP.takenOff() return 1 end
    function COOP.killSent() return false end
end
local function sentOf(pat) local t = {}; for _, m in ipairs(sent) do if m:find(pat) then t[#t + 1] = m end end; return t end
fresh()
s = D.special
local joiner = obj("BP_PlayerPlane_PP0002_fa18", 1000, { X = 1610476, Y = -3436142, Z = 300000 })
me.at = { X = 1610476, Y = -436142, Z = 50000 }            -- (the host at the runway: never locked)
local plist = {
    { slot = 0, obj = me, at = me.at, alive = true, fresh = true, isMe = true },
    { slot = 2, obj = joiner, at = joiner.at, alive = true, fresh = true },
}
coop("host", 0, plist)
C.max_up, C.per_player_max = 1, 1
K.spawn(0)
check(#sentOf("^%-1>dk|s|bait|") == 1, "the bait's state to every joiner (dk|s|bait)")
step(0.25); bodyOf(C.bait_unit).HealthInternal = 0
step(C.lock_after_s + 2.5)
local ls = sentOf("^%-1>dk|l|1|2|1$")
check(#ls == 1, "UAV 1's lock on player 3 (slot 2) to every joiner: dk|l|1|2|1 (" .. table.concat(sent, " ; ") .. ")")
check(DECOY.G[1] and DECOY.G[1].armed and world[DECOY.mark(1)].objs[1].parent == joiner, "the host's own mark 1 on that joiner's plane, its laser on")
check(next(DECOY.R) == nil, "no 8 s on the host: the lock isn't on it")
step(C.lock_s + 3)
check(evs("^RE_SV_DecoySpear_") == 0, "never the Spear on the host for a joiner's lock")
bodyOf(DECOY.uav(1)).HealthInternal = 0
step(0.5)
check(#sentOf("^%-1>dk|c|1|down$") == 1, "its kill to every joiner: dk|c|1|down")
DECOY.syncTo(5)
check(#sentOf("^5>dk|s|trap|") == 1, "a joiner asking for the picture gets the round's state (dk|s to it alone)")

---------------------------------------------------------------------------------------------------- co-op: a joiner
print("co-op: a joiner")
fresh()
D.special = nil
sent = {}
local host = obj("BP_PlayerPlane_PP0003_f15e", 1000, { X = 0, Y = -3000000, Z = 300000 })
me.at = { X = 1610476, Y = -3436142, Z = 300000 }
plist = { { slot = 2, obj = me, at = me.at, alive = true, fresh = true, isMe = true },
          { slot = 0, obj = host, at = host.at, alive = true, fresh = true } }
coop("join", 2, plist)
DECOY.fromHost({ "dk", "s", "trap", "1", "0", "1", "35" })
check(evs("^RE_SV_DecoyRadio_Brief$") == 1 and DECOY.clientRow(CFG.hud.text):find("SPEAR UAVS: 1 UP", 1, true), "the host's trap: the brief here, its NEXT row")
spawningUnit = DECOY.uav(3); SV_Spawn(DECOY.uav(3), 1610476, -3136142, 300000, 0); spawningUnit = nil   -- (the copies)
spawningUnit = DECOY.mark(3); SV_Spawn(DECOY.mark(3), 0, 0, 0, 0); spawningUnit = nil
DECOY.fromHost({ "dk", "l", "3", "2", "7" })
step(0.25, false)
local r7 = DECOY.R[3]
check(DECOY.G[3] and DECOY.G[3].armed and evs("^RE_SV_DecoyLaserOn_03$") == 1 and r7 and r7.state == "count",
    "a lock on you: this game's laser on its copy, your 8 s")
local copyAddr = bodyOf(DECOY.uav(3)).addr
function COOP.killSent(a) return a == copyAddr end
step(2)
check(r7.state == "cancelled" and logged("taken down by your hit"), "your killing hit sent (the copy at the floor): cancelled")
function COOP.killSent() return false end
step(C.lock_s + 2, false)
check(evs("^RE_SV_DecoySpear_") == 0, "no Spear after it")
spawningUnit = DECOY.uav(4); SV_Spawn(DECOY.uav(4), 0, -2800000, 300000, 0); spawningUnit = nil
spawningUnit = DECOY.mark(4); SV_Spawn(DECOY.mark(4), 0, 0, 0, 0); spawningUnit = nil
DECOY.fromHost({ "dk", "l", "4", "0", "8" })
step(0.25, false)
check(DECOY.G[4] and DECOY.G[4].armed and world[DECOY.mark(4)].objs[1].parent == host and DECOY.R[4] == nil,
    "a lock on the host: its laser here, the mark on the host's plane, no 8 s here")
step(C.lock_s + 3, false)
check(evs("^RE_SV_DecoySpear_") == 0, "never the Spear here for another player's lock")
DECOY.fromHost({ "dk", "l", "4", "2", "8" })
step(0.25, false)
check(DECOY.R[4] == nil, "a repeated or older lock: ignored")
local bad = { { "dk", "l", "99", "2", "9" }, { "dk", "l", "1", "30", "9" }, { "dk", "l", "1", "1.5", "9" },
              { "dk", "s", "boom", "1", "0", "1", "35" }, { "dk", "c", "1", "hack" }, { "dk", "x" }, { "dk", "s", "trap", "-1", "0", "0", "35" } }
local got = 0
for _, f in ipairs(bad) do if DECOY.parse(f) then got = got + 1 end end
check(got == 0, "the guards: a UAV past the build's, a slot past 23 or not whole, an unknown state, cancel or kind, a count < 0")
check(DECOY.parse({ "dk", "c", "4", "down" }) and DECOY.parse({ "dk", "s", "done", "35", "35", "0", "35" }), "and the good ones pass")
DECOY.fromHost({ "dk", "c", "4", "down" })
check(DECOY.G[4] == nil and #DECOY.rq > 0, "the host's UAV down: its lock off here, its copies' units queued off the list")
local rx0 = #logs
for i = 1, 60 do DECOY.fromHost({ "dk", "l", "5", "2", tostring(100 + i) }) end
check(logged("more than 40 of the host's"), "more than 40 a second: the rest dropped")
clock = clock + 1.5                                    -- (the next second)
DECOY.fromHost({ "dk", "s", "done", "35", "35", "0", "35" })
check(next(DECOY.G) == nil and DECOY.clientRow(CFG.hud.text) == nil, "the host's trap over: every lock here off, no row")
COOP = nil

---------------------------------------------------------------------------------------------------- KEEP_EVENTS
print("co-op: the Spear never forwarded")
local src = PARTS.read("sv_coop.lua")
local keepSrc = src:match("local KEEP_EVENTS = (%b{})")
local KEEP = assert(load("return " .. keepSrc))()
local function kept(name) for _, p in ipairs(KEEP) do if name:match(p) then return true end end return false end
check(kept("RE_SV_DecoySpear_1") and kept("RE_SV_DecoySpear_4") and kept("RE_SV_DecoyKill"), "RE_SV_DecoySpear_* and RE_SV_DecoyKill kept")
check(kept("RE_SV_DecoyLaserOn_07") and kept("RE_SV_DecoyLaserOff_35") and kept("RE_SV_DecoyBaitLaser") and kept("RE_SV_DecoyBaitPing")
    and kept("RE_SV_DecoyRadio_Lock"), "each game's lasers, bait ping and radio kept")
check(not kept("RE_SV_FlightOrders_01") and not kept("RE_SV_LadonVolleyKotL"), "the others still forwarded")
local skips = src:match("local HOST_DOWN_SKIPS = (%b{})")
local SK = assert(load("return " .. skips))()
local sk = false
for _, p in ipairs(SK) do if ("RE_SV_DecoySpear_2"):match(p) then sk = true end end
check(sk, "the Spear skipped on a host who's DOWN")
check(src:find('k == "dk" and COOP.client()', 1, true) and src:find("function COOP.killSent", 1, true)
    and src:find("DECOY.syncTo", 1, true), "sv_coop.lua: \"dk\" read on a joiner, COOP.killSent, the picture's DECOY state")

print(fails == 0 and "decoy test: all passed" or ("decoy test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
