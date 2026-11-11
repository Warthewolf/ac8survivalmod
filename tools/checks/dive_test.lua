-- dive_test.lua <mod dir> (run by tools/checks/dive_test.sh): the VAMPIRES' final dive (2026-11-08, Scripts/sv_escort_dive.lua)
-- on the real part with the shipped settings (sv_config.lua's CFG.allies.carrier.dive), the game stubbed as it behaves:
-- GameplayStatics.ApplyDamage takes nothing off an AI plane (Saint Alessia's 50-round run of 0.74.36: 70 blasts, not one
-- ZFA-44 down), ModifyHealth does (not while it's invincible, never under its MinHealth field); the finish is the real
-- sv_core.lua finishUnpaid and sv_escort_laser.lua ZLAUNCH.finish:
--   a carrier leaving after its service: its ZFA-44s up kept as its dive (not a parked one, not another ship's), nil with
--     none or the dive off; nothing through the break, nothing in the next round before its enemies; then each onto the
--     nearest enemy aircraft (one each), the callout once a second; within detonate_m the Helios blast on its target:
--     every enemy within blast_m down with you as the cause, an ace's hurt by boss_pct, one farther untouched, the other
--     ZFA-44 (an ally) untouched, the ZFA-44 down by ModifyHealth (health 0), the effects, the callout; a target down: the
--     next; dive_s on: the blast where it is; all gone: the units recycled, co-op told; a round with no enemy aircraft:
--     they leave unpaid; a new run: the old run's finished off;
--   (2026-11-11) a ZFA-44 ModifyHealth can't take down: its blast once, its finish tried 3 times, then switched off and
--     never held again; two carriers leaving in turn: each its own dive (its callout, "zd v" / "zd e" with its id, its
--     units' recycle); both ships at once and blasts in one second: one callout each; a target out of reach: flown at
--     first, its dive_s from in reach (approach_s at most);
--   a joiner: the host's "zd h" then its carrier gone (ESC.localOff): this game's own kept (not the host's bound copies),
--     ordered at "v", one of that dive finished off at each "b" with the effects there and no kill of its own, bad
--     numbers dropped, at most 12 blasts a second, "e" its dive's rest; another dive's untouched;
--   the hooks in sv_escort.lua, sv_escort_laser.lua, sv_coop_migration.lua and main.lua's MODULES.
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)
local function section(s) print(s) end

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the shipped settings: sv_config.lua's dive table, as written
local cfgSrc = readAll(MOD .. "/Scripts/sv_config.lua")
local i0 = cfgSrc:find("dive = {", 1, true)
assert(i0, "no dive table in sv_config.lua")
local depth, j = 0, cfgSrc:find("{", i0, true)
local k = j
repeat
    local ch = cfgSrc:sub(k, k)
    if ch == "{" then depth = depth + 1 elseif ch == "}" then depth = depth - 1 end
    k = k + 1
until depth == 0
local DIVE = assert(load("return " .. cfgSrc:sub(j, k - 1)))()
CFG = { allies = { carrier = { rise_m = -50, units = { "SV_Unit_Cargo1", "SV_Unit_Cargo2" },
    pose_units = { "SV_Unit_ZfaPose1", "SV_Unit_ZfaPose2" },
    launchers = { { { unit = "SV_Unit_ZfaArm1_1" }, { unit = "SV_Unit_ZfaArm1_2" } }, { { unit = "SV_Unit_ZfaArm2_1" } } },
    dive = DIVE } } }

-- the game, stubbed
local logs, callouts, msgs, fx, sounds, shakes, removed, offs = {}, {}, {}, {}, {}, {}, {}, {}
function log(s) logs[#logs + 1] = s end
function logOnce(_, s) log(s) end
local function lastLog(p) for i = #logs, 1, -1 do if logs[i]:find(p, 1, true) then return logs[i] end end return nil end
local function since(from, p) local n = 0; for i = from, #logs do if logs[i]:find(p, 1, true) then n = n + 1 end end return n end
function hudCallout(t, s) callouts[#callouts + 1] = { t, s } end
local nextAddr = 100
local applied = 0                                 -- (GameplayStatics.ApplyDamage calls: taken nothing off, as in game)
local function plane(x, y, z, h)
    nextAddr = nextAddr + 1
    local o = { addr = nextAddr, loc = { X = x, Y = y, Z = z }, HealthInternal = h or 100, orders = {}, hits = {},
                vel = { X = 33334, Y = 0, Z = 0 } }                  -- (1,200 km/h)
    function o:K2_GetActorLocation() return { X = self.loc.X, Y = self.loc.Y, Z = self.loc.Z } end
    function o:GetVelocity() return { X = self.vel.X, Y = self.vel.Y, Z = self.vel.Z } end
    function o:EngagementOrderOverride(order, target, prio, a, b, fire, c) self.orders[#self.orders + 1] = { target = target, prio = prio } end
    -- (as AC8 takes it on an AI object: nothing while invincible, never under the MinHealth field; tough: refused, the
    -- case still open in game for an allied plane)
    function o:ModifyHealth(dh, inst, ev)
        self.hits[#self.hits + 1] = { dh = dh, inst = inst, ev = ev }
        if self.tough or self.bIsInvincible then return 0 end
        -- (dh in plain health, HealthInternal x 10, as escort_test's and pad_test's: KILLS_HEALTH_DEATH.md 2)
        self.HealthInternal = math.max(math.floor((self.MinHealth or 0) * 10), self.HealthInternal + dh * 10)
    end
    function o:SetIsInvincible(v) self.bIsInvincible = v end
    function o:SetMinHealth(v) self.minH = v end
    function o:SetActive(v) self.active = v end
    function o:SetActorTickEnabled(v) self.tick = v end
    return o
end
function liveAddr(o) return type(o) == "table" and not o.gone and o.addr or nil end
function liveObj(o) return type(o) == "table" and not o.gone end
function valid(o) return type(o) == "table" and not o.gone end
local GS = { ApplyDamage = function(self, o, dmg) applied = applied + 1 end }     -- (a no-op on AC8's AI objects)
local NIA = { SpawnSystemAtLocation = function(self, wc, sys, where, rot, scale) fx[#fx + 1] = { sys = sys, at = where, scale = scale } end }
local AK = { PostEventAtLocation = function(self, ev, where, rot, wc) sounds[#sounds + 1] = { ev = ev, at = where } end }
function StaticFindObject(p)
    if p == "/Script/Engine.Default__GameplayStatics" then return GS end
    if p == "/Script/Niagara.Default__NiagaraFunctionLibrary" then return NIA end
    if p == "/Script/AkAudio.Default__AkGameplayStatics" then return AK end
    return nil
end
local loaded = {}
function loadObject(p) loaded[p] = (loaded[p] or 0) + 1; return { path = p } end
local PAWN = { name = "your plane" }
survivalPC = { Pawn = PAWN }
function survivalPC:ClientStartCameraShake(cls, scale) shakes[#shakes + 1] = { cls = cls, scale = scale } end
local YOU = { X = 0, Y = 0, Z = 100000 }
function playerLocation() return { X = YOU.X, Y = YOU.Y, Z = YOU.Z } end
function poolIndex(u) return u:find("^SV_Unit_Pool") and 1 or nil end
BOMBER_UNIT = {}
TAC = { aceFlight = function(u) return u == "SV_Unit_Ace1" end }
LEVEL_DROPS = {}
ESC = { planes = {}, recycleQ = {}, offObj = function(o) offs[#offs + 1] = o; o.off = true; return true end }
planes = {}
local function enemy(unit, x, y, z, h)
    local o = plane(x, y, z, h)
    o.fullName = "BP_OP1026_su47_CP_C /Game/PL:PersistentLevel.BP_OP1026_su47_CP_C_" .. o.addr
    local rec = { obj = o, unit = unit, addr = o.addr, at = { X = x, Y = y, Z = z }, name = "BP_OP1026_su47_CP_C_" .. o.addr }
    planes[#planes + 1] = rec
    return rec
end
local function zfa(unit, x, y, z)
    local o = plane(x, y, z, 50)
    ESC.planes[unit] = ESC.planes[unit] or {}
    table.insert(ESC.planes[unit], { obj = o, addr = o.addr, name = nameOf(o), at = clock })
    return o
end
local function entryOf(o)
    for _, l in pairs(ESC.planes) do for _, e in ipairs(l) do if e.obj == o then return e end end end
    return nil
end
-- down the way the game kills: ModifyHealth with no attacker and the damage event, its health 0 after
local function downByModify(o)
    if o.HealthInternal ~= 0 then return false end
    for _, h in ipairs(o.hits) do if h.inst == nil and h.ev == true and h.dh < 0 then return true end end
    return false
end

-- names as the game gives them; ESC.same, ZLAUNCH.finish (sv_escort_laser.lua) and finishUnpaid (sv_core.lua) as the
-- parts have them (their own text, loaded alone)
function nameOf(o) return type(o) == "table" and (o.fullName or ("BP_OP0018_uavc_CP_Ally_C /Game/PL:PersistentLevel.BP_OP0018_uavc_CP_Ally_C_" .. tostring(o.addr))) or "?" end
local function piece(file, from, to)
    local src = readAll(MOD .. "/Scripts/" .. file)
    local a = src:find(from, 1, true)
    local b = a and src:find(to, a, true)
    assert(a and b, "no " .. from .. " in " .. file)
    assert(load(src:sub(a, b + #to - 1), "=" .. from))()
end
ZLAS, ZLAUNCH = {}, {}
piece("sv_escort_laser.lua", "function ESC.same(e, maxAge)", "\nend\n")
piece("sv_core.lua", "function finishUnpaid(o, noEvent)", "\nend\n")
do
    local las = readAll(MOD .. "/Scripts/sv_escort_laser.lua")
    local a = las:find("local function fin()", 1, true)
    local f = a and las:find("function ZLAUNCH.finish(e, why, final)", a, true)
    local b = f and las:find("\nend\n", f, true)
    assert(a and b, "no ZLAUNCH.finish in sv_escort_laser.lua")
    assert(load(las:sub(a, b + 4), "=ZLAUNCH.finish"))()
end
PARTS.dofile("sv_escort_dive.lua")
check(type(ZDIVE) == "table" and LEVEL_DROPS["the ZFA-44s' dive"] ~= nil, "the part loads (ZDIVE, its level drop)")

section("a carrier leaving: its ZFA-44s kept")
D = { round = 3, state = "wait" }
local Z1 = zfa("SV_Unit_ZfaArm1_1", 0, 0, 110000)
local Z2 = zfa("SV_Unit_ZfaArm1_2", 100000, 0, 110000)
local ZP = zfa("SV_Unit_ZfaArm1_1", 0, 0, -20000)              -- (parked, under the sea)
local ZO = zfa("SV_Unit_ZfaArm2_1", 0, 50000, 110000)           -- (the other ship's)
local C = { idx = 1, name = "ZFA-44 CARRIER 1" }
DIVE.enabled = false
check(ZDIVE.take(C) == nil, "the dive off: nil (its flight finished off as before)")
DIVE.enabled = true
local n = ZDIVE.take(C)
check(n == 2, "its two up kept, not the parked one, not the other ship's (" .. tostring(n) .. ")")
check(lastLog("ZFA-44 CARRIER 1 leaving: 2 ZFA-44s stay up for their final dive as round 4's enemies come (dive 1)") ~= nil, "logged, with its dive")
check(ZDIVE.diving(Z1.addr) and ZDIVE.diving(Z2.addr) and not ZDIVE.diving(ZO.addr) and not ZDIVE.diving(ZP.addr),
      "ZDIVE.diving: the held ones only (the escort leaves them be)")
check(ZDIVE.waiting(Z1.addr) and ZDIVE.holding(1) and not ZDIVE.holding(2), "waiting for their dive (brought toward the fight); ship 1 holding")
check(ZDIVE.take({ idx = 2, name = "none" }) == 1 and ZDIVE.diving(ZO.addr), "ship 2's own, when it leaves")
ZDIVE.d.held[#ZDIVE.d.held].gone = true; ZO.gone = true          -- (out of the way for what follows)

section("held through the break, and the next round until its enemies")
ZDIVE.tick()
check(#Z1.orders == 0 and #callouts == 0, "the break: nothing")
D.round, D.state = 4, "spawning"
ZDIVE.tick()
check(#Z1.orders == 0 and #callouts == 0, "round 4 with no enemy aircraft up: nothing")

section("the dive: each onto the nearest enemy aircraft")
local A = enemy("SV_Unit_Pool01", 500000, 0, 110000)             -- (5 km off Z1)
local B = enemy("SV_Unit_Pool02", 550000, 0, 110000)             -- (500 m off A)
local AC = enemy("SV_Unit_Ace1", 500000, 70000, 110000, 400)     -- (an ace 700 m off A)
local F = enemy("SV_Unit_Pool03", 2500000, 0, 110000)            -- (far)
ZDIVE.tick()
check(#Z1.orders == 1 and Z1.orders[1].target == A.obj and Z1.orders[1].prio == 9, "Z1 onto the nearest, A (TargetFirst)")
check(#Z2.orders == 1 and Z2.orders[1].target ~= A.obj, "Z2 onto another (one each while there are enough)")
check(not ZDIVE.waiting(Z1.addr) and ZDIVE.diving(Z1.addr), "diving now, not waiting (the escort leaves it be)")
check(#callouts == 0, "its callout held a second (the dives and blasts of a second as one)")
check(lastLog("dive: a ZFA-44 of dive 1 onto the nearest enemy aircraft, 5.0 km off") ~= nil, "its distance logged: " .. tostring(lastLog("onto the nearest enemy aircraft")))
clock = clock + 1
ZDIVE.tick()
check(#callouts == 1 and callouts[1][1] == DIVE.text.dive and callouts[1][2] == string.format(DIVE.text.dive_sub, 2), "the callout once: 2 dive")
check(#Z1.orders == 1, "not ordered again before reorder_s")
clock = clock + DIVE.reorder_s
ZDIVE.tick()
check(#Z1.orders == 2 and Z1.orders[2].target == A.obj, "again every reorder_s, the same target")

section("the Helios blast on its target: its ZFA-44 down by ModifyHealth (ApplyDamage takes nothing)")
Z1.loc = { X = A.obj.loc.X - (DIVE.detonate_m - 50) * 100, Y = 0, Z = 110000 }
local z2h = Z2.HealthInternal
local c0 = #callouts
ZDIVE.tick()
check(A.obj.HealthInternal == 0 and A.obj.hits[1].inst == PAWN and A.obj.hits[1].dh <= -1000000, "its target down, you the cause")
check(B.obj.HealthInternal == 0, "an enemy 500 m off it down too")
check(math.abs(AC.obj.HealthInternal - 400 * (1 - DIVE.boss_pct)) < 1e-6, "the ace's boss_pct off, not killed (" .. AC.obj.HealthInternal .. ")")
check(F.obj.HealthInternal == 100 and #F.obj.hits == 0, "one 20 km off untouched")
check(downByModify(Z1) and Z2.HealthInternal == z2h and #Z2.hits == 0,
      "the ZFA-44 down (health 0, ModifyHealth with no attacker: unpaid); the other (an ally) untouched (" .. Z1.HealthInternal .. ")")
check(Z1.bIsInvincible == false and Z1.MinHealth == 0, "made mortal first (invincible off, the MinHealth field 0)")
check(#fx == 1 and fx[1].sys.path == DIVE.fx .. "." .. DIVE.fx:match("[^/]+$") and fx[1].at.X == A.obj.loc.X, "the Helios burst where its target was")
check(#sounds == 1 and sounds[1].ev.path:find("OBJ_M09_CLOUDBOMB_EXP", 1, true) ~= nil, "its sound there")
check(#shakes == 1 and shakes[1].cls.path:find("BP_CamShake_BombImpactHelios_C", 1, true) ~= nil and shakes[1].scale >= 0.2 and shakes[1].scale < 1,
      "the camera shake, by your distance (5 km: " .. tostring(shakes[1] and shakes[1].scale) .. ")")
check(lastLog("Helios blast 1 (on its target)") ~= nil and lastLog("2 enemy aircraft down, 1 aces' or specials' hurt") ~= nil
      and lastLog("(dive 1: 2 down); its ZFA-44 down") ~= nil, "logged, its ZFA-44 down: " .. tostring(lastLog("Helios blast 1")))
check(not ZDIVE.diving(Z1.addr) and entryOf(Z1).dived == true, "gone from the dive once its health read 0, never held again")
A.down, B.down = true, true
clock = clock + 1
ZDIVE.tick()
check(#callouts == c0 + 1 and callouts[#callouts][1] == DIVE.text.blast and callouts[#callouts][2] == string.format(DIVE.text.blast_sub, 2),
      "HELIOS IMPACT: 2 down")

section("a target down: the next; dive_s on: the blast where it is")
clock = clock + 0.5
ZDIVE.tick()
local last = Z2.orders[#Z2.orders].target
check(last == AC.obj or last == F.obj, "Z2 onto the next nearest up")
clock = clock + DIVE.dive_s + 1
YOU.X = 9000000                                                   -- (you far off: no shake)
local shakes0 = #shakes
ZDIVE.tick()
check(downByModify(Z2) and #fx == 2 and fx[2].at.X == Z2.loc.X, "dive_s on: its blast where it is, its ZFA-44 down")
check(#shakes == shakes0, "no camera shake 90 km off")
check(F.obj.HealthInternal == 100, "nothing near it down")
ZDIVE.tick()
check(lastLog("dive: over (dive 1, ship 1): 2 blasts, 2 enemy aircraft down") ~= nil, "over: logged")
local rq = {}
for _, e in ipairs(ESC.recycleQ) do rq[e.unit] = true end
check(rq.SV_Unit_ZfaArm1_1 and rq.SV_Unit_ZfaArm1_2, "their units on the recycle queue (off the list once none is up)")
check(not ZDIVE.diving(Z1.addr) and not ZDIVE.diving(Z2.addr) and #ZDIVE.d.held == 0 and next(ZDIVE.d.dives) == nil,
      "none diving now, the dive's planes forgotten")
check(applied == 0, "ApplyDamage never needed (" .. applied .. ")")

section("a round with no enemy aircraft: they leave")
for _, p in ipairs(planes) do p.down = true end
D = { round = 6, state = "wait" }
local Z3 = zfa("SV_Unit_ZfaPose1", 0, 0, 110000)
check(ZDIVE.take(C) == 1, "kept")
D.round, D.state = 7, "fighting"
ZDIVE.tick()
check(#Z3.hits == 0, "round 7, no enemy aircraft: still held")
D.round = 8
ZDIVE.tick()
check(downByModify(Z3) and #fx == 2 and lastLog("found no enemy aircraft in round 7") ~= nil, "round 8: finished off, unpaid, no blast")

section("a new run: the old run's held ones finished off")
D = { round = 3, state = "wait" }
local Z4 = zfa("SV_Unit_ZfaPose1", 0, 0, 110000)
check(ZDIVE.take(C) == 1, "kept")
D = { round = 1, state = "wait" }
ZDIVE.tick()
check(downByModify(Z4) and lastLog("held ZFA-44s of the last run finished off") ~= nil, "finished off with the run")

section("an address reused (the user's test of 0.74.34: an Su-47 at a dead ZFA-44's address)")
D = { round = 3, state = "wait" }
local ZR = zfa("SV_Unit_ZfaPose1", 0, 0, 110000)
ZR.fullName = "BP_OP1026_su47_CP_C /Game/PL:PersistentLevel.BP_OP1026_su47_CP_C_9999"     -- (another plane there now)
local ZK = zfa("SV_Unit_ZfaPose1", 1000, 0, 110000)
check(ZDIVE.take(C) == 1 and not ZDIVE.diving(ZR.addr) and ZDIVE.diving(ZK.addr), "the reused one isn't held (its name isn't the ZFA-44's)")
check(lastLog("a ZFA-44's address is another object's now") ~= nil, "logged once by ESC.same")
ZK.fullName = "BP_OP1025_f15e_CP_C /Game/PL:PersistentLevel.BP_OP1025_f15e_CP_C_8888"     -- (taken over while held)
ZDIVE.d.held[1].sameAt = 0
D = { round = 1, state = "wait" }
ZDIVE.tick()
check(#ZK.hits == 0 and not ZK.off, "a held one taken over by another plane is never finished off or switched off")
D = { round = 3, state = "wait" }
local ZB = zfa("SV_Unit_ZfaPose2", 0, 0, 110000)
check(ZDIVE.take({ idx = 2, name = "ZFA-44 CARRIER 2" }) == 1, "kept")
local T1 = enemy("SV_Unit_Pool06", 300000, 0, 110000)
local AL = enemy("SV_Unit_Pool07", 350000, 0, 110000)
AL.obj.fullName = "BP_OP1001_a10c_Ally_C /Game/PL:PersistentLevel.BP_OP1001_a10c_Ally_C_7777"   -- (an ally at an enemy's old address)
D.round, D.state = 4, "fighting"
ZDIVE.tick()
ZB.loc = { X = 300000, Y = 0, Z = 110000 }
ZDIVE.tick()
check(T1.obj.HealthInternal == 0 and AL.obj.HealthInternal == 100 and #AL.obj.hits == 0, "the blast: its target down, never a plane at an enemy's old address")
T1.down, AL.down = true, true
ZDIVE.tick()

section("(2026-11-11) a ZFA-44 ModifyHealth can't take down: its blast once, tried 3 times, then switched off")
D = { round = 3, state = "wait" }
for _, p in ipairs(planes) do p.down = true end
local ZT = zfa("SV_Unit_ZfaArm2_1", 0, 0, 110000)
ZT.tough = true
check(ZDIVE.take({ idx = 2, name = "ZFA-44 CARRIER 2" }) == 1, "kept")
local T2 = enemy("SV_Unit_Pool08", 100000, 0, 110000)
D.round, D.state = 4, "fighting"
ZDIVE.tick()
ZT.loc = { X = 100000, Y = 0, Z = 110000 }
local fx0, from = #fx, #logs + 1
ZDIVE.tick()
check(#fx == fx0 + 1 and since(from, "dive: Helios blast") == 1 and lastLog("its ZFA-44 NOT down yet (health 50): tried again") ~= nil,
      "its blast once, its line says it's not down: " .. tostring(lastLog("its ZFA-44 NOT down")))
check(ZDIVE.diving(ZT.addr) and not ZDIVE.waiting(ZT.addr), "still held (never back to escorting) while it's tried again")
for _ = 1, 8 do clock = clock + 0.5; ZDIVE.tick() end
check(#fx == fx0 + 1 and since(from, "dive: Helios blast") == 1, "never blasted again")
local tries = 0
for _, h in ipairs(ZT.hits) do if h.ev == true then tries = tries + 1 end end
check(tries == 3 and ZT.off and not ZDIVE.diving(ZT.addr) and entryOf(ZT).retired == true,
      "tried 3 times (" .. tries .. "), then switched off and retired")
check(lastLog("could not be finished (health 50 after ModifyHealth and ApplyDamage): switched off") ~= nil, "said: " .. tostring(lastLog("could not be finished")))
check(lastLog("dive: over (dive 1, ship 2): 1 blasts, 1 enemy aircraft down") ~= nil, "its dive over, logged")
T2.down = true
D.round, D.state = 6, "wait"
check(ZDIVE.take({ idx = 2, name = "ZFA-44 CARRIER 2" }) == nil and not ZDIVE.diving(ZT.addr), "the ship's next leaving: never held again")

section("(2026-11-11) two carriers leaving in turn: each its own dive")
D = { round = 3, state = "wait" }
for _, p in ipairs(planes) do p.down = true end
msgs, removed = {}, {}
COOP = { open = true, client = function() return false end, msg = function(to, ...) msgs[#msgs + 1] = { ... } end,
         removeNow = function(u) removed[#removed + 1] = u end, removeObj = function() end }
local function sent(kind) local t = {}; for _, m in ipairs(msgs) do if m[1] == "zd" and m[2] == kind then t[#t + 1] = m end end; return t end
ESC.recycleQ = {}
local Y1 = zfa("SV_Unit_ZfaArm1_1", 0, 0, 110000)
check(ZDIVE.take(C) == 1, "the first leaving: kept")
local E1 = enemy("SV_Unit_Pool09", 50000, 0, 110000)
D.round, D.state = 4, "fighting"
ZDIVE.tick()
Y1.loc = { X = 50000, Y = 0, Z = 110000 }
ZDIVE.tick()
ZDIVE.tick()
E1.down = true
local c1 = #callouts
clock = clock + 1; ZDIVE.tick()
D.round, D.state = 6, "wait"
local Y2 = zfa("SV_Unit_ZfaArm1_2", 0, 0, 110000)
check(ZDIVE.take(C) == 1, "the second leaving: kept")
local E2 = enemy("SV_Unit_Pool10", 50000, 0, 110000)
D.round, D.state = 7, "fighting"
ZDIVE.tick()
Y2.loc = { X = 50000, Y = 0, Z = 110000 }
ZDIVE.tick()
ZDIVE.tick()
E2.down = true
clock = clock + 1; ZDIVE.tick()
local h, v, b, e = sent("h"), sent("v"), sent("b"), sent("e")
check(#h == 2 and #v == 2 and #b == 2 and #e == 2 and h[1][5] ~= h[2][5] and v[1][4] == h[1][5] and v[2][4] == h[2][5]
      and b[2][7] == h[2][5] and e[1][3] == h[1][5] and e[2][3] == h[2][5],
      string.format("each its own zd h / v / b / e, by its dive's id (h %d, v %d, b %d, e %d)", #h, #v, #b, #e))
local dc, rec = 0, {}
for i = c1, #callouts do if callouts[i][1] == DIVE.text.dive then dc = dc + 1 end end
for _, x in ipairs(ESC.recycleQ) do rec[x.unit] = true end
check(dc >= 1 and since(1, "dive: round 7's enemies up: 1 held ZFA-44s dive") == 1 and rec.SV_Unit_ZfaArm1_1 and rec.SV_Unit_ZfaArm1_2,
      "the second dive its own callout, start line and units' recycle")
check(b[1][6] == "1" and b[2][6] == "1", "each blast's own down in its zd b (" .. tostring(b[1][6]) .. ", " .. tostring(b[2][6]) .. ")")
COOP = nil

section("(2026-11-11) both ships at once, blasts in one second: one callout each")
D = { round = 3, state = "wait" }
for _, p in ipairs(planes) do p.down = true end
local W1 = zfa("SV_Unit_ZfaArm1_1", 0, 0, 110000)
local W2 = zfa("SV_Unit_ZfaArm2_1", 0, 300000, 110000)
check(ZDIVE.take(C) == 1 and ZDIVE.take({ idx = 2, name = "ZFA-44 CARRIER 2" }) == 1, "both ships' kept, two dives")
local G1 = enemy("SV_Unit_Pool11", 50000, 0, 110000)
local G2 = enemy("SV_Unit_Pool12", 50000, 300000, 110000)       -- (3 km from G1: not in W1's blast)
D.round, D.state = 4, "fighting"
local cc0 = #callouts
ZDIVE.tick()
W1.loc = { X = 50000, Y = 0, Z = 110000 }; W2.loc = { X = 50000, Y = 300000, Z = 110000 }
ZDIVE.tick()
clock = clock + 1; ZDIVE.tick()
local nd, nb, last2 = 0, 0, nil
for i = cc0 + 1, #callouts do
    if callouts[i][1] == DIVE.text.dive then nd = nd + 1; last2 = callouts[i][2] end
    if callouts[i][1] == DIVE.text.blast then nb = nb + 1 end
end
check(nd == 1 and last2 == string.format(DIVE.text.dive_sub, 2), "one FINAL DIVE callout for both (" .. nd .. ": " .. tostring(last2) .. ")")
check(nb == 1 and callouts[#callouts][2] == string.format(DIVE.text.blast_sub, 2), "one HELIOS IMPACT callout for both blasts (" .. nb .. ")")
G1.down, G2.down = true, true
ZDIVE.tick()

section("(2026-11-11) a target out of reach: flown at first, its dive_s from in reach")
D = { round = 3, state = "wait" }
for _, p in ipairs(planes) do p.down = true end
local X1 = zfa("SV_Unit_ZfaArm1_1", 0, 0, 110000)
check(ZDIVE.take(C) == 1, "kept")
local FAR = enemy("SV_Unit_Pool13", 3000000, 0, 110000)          -- (30 km: 90 s at 1,200 km/h, 13.3 km in its 40 s)
D.round, D.state = 4, "fighting"
local fxF = #fx
ZDIVE.tick()
check(#X1.orders == 1 and X1.orders[1].target == FAR.obj, "ordered onto it")
clock = clock + DIVE.dive_s + 5
ZDIVE.tick()
check(#fx == fxF and ZDIVE.diving(X1.addr) and #X1.hits == 0, "dive_s on and still 30 km off: no blast, flown at it")
X1.loc = { X = 2000000, Y = 0, Z = 110000 }                      -- (10 km off: in reach)
ZDIVE.tick()
check(lastLog("10.0 km from its target") ~= nil and lastLog("its " .. DIVE.dive_s .. " s on") ~= nil, "in reach: its dive_s on, logged")
clock = clock + DIVE.dive_s + 1
ZDIVE.tick()
check(#fx == fxF + 1 and downByModify(X1), "dive_s after that: its blast where it is, down")
ZDIVE.tick()
local X2 = zfa("SV_Unit_ZfaArm1_2", 0, 0, 110000)
D = { round = 3, state = "wait" }
check(ZDIVE.take(C) == 1, "another kept")
D.round, D.state = 4, "fighting"
ZDIVE.tick()
clock = clock + DIVE.approach_s + 1
ZDIVE.tick()
clock = clock + DIVE.dive_s + 1
ZDIVE.tick()
check(downByModify(X2) and #fx == fxF + 2, "never in reach: its dive_s from approach_s on, then its blast")
FAR.down = true
ZDIVE.tick()

section("co-op: the host tells the joiners")
D = { round = 3, state = "wait" }
msgs = {}
COOP = { open = true, client = function() return false end, msg = function(to, ...) msgs[#msgs + 1] = { ... } end,
         removeNow = function(u) removed[#removed + 1] = u end, removeObj = function() end }
removed = {}
local Z5 = zfa("SV_Unit_ZfaPose2", 0, 0, 110000)
check(ZDIVE.take({ idx = 2, name = "ZFA-44 CARRIER 2" }) == 1 and msgs[1][1] == "zd" and msgs[1][2] == "h" and msgs[1][3] == "2" and msgs[1][4] == "3"
      and msgs[1][5] == "1", "zd h <ship> <round> <dive>")
local G = enemy("SV_Unit_Pool04", 100000, 0, 110000)
D.round, D.state = 4, "wave"
ZDIVE.tick()
check(msgs[#msgs][2] == "v" and msgs[#msgs][3] == "1" and msgs[#msgs][4] == "1", "zd v <count> <dive>")
Z5.loc = { X = 100000, Y = 0, Z = 110000 }
ZDIVE.tick()
local mb = msgs[#msgs - 1] or {}                                 -- (its blast, then its dive over in the same tick: it went)
check(mb[2] == "b" and tonumber(mb[3]) == 100000 and mb[6] == "1" and mb[7] == "1",
      "zd b x y z <its down> <dive> (" .. table.concat(mb, "|") .. ")")
check(msgs[#msgs][2] == "e" and msgs[#msgs][3] == "1" and #removed >= 1 and removed[1] == "SV_Unit_ZfaPose2", "zd e <dive>, the copies removed (COOP.removeNow)")
G.down = true

section("a joiner")
D = { round = 3, state = "wait" }
local copies = {}
COOP = { open = true, client = function() return true end, msg = function() error("a joiner sends no zd") end,
         copyAt = function(a) return copies[a] == true end }
local J1 = zfa("SV_Unit_ZfaArm1_1", 0, 0, 110000)
local J2 = zfa("SV_Unit_ZfaArm1_2", 300000, 0, 110000)
local JC = zfa("SV_Unit_ZfaPose1", 0, 900000, 110000); copies[JC.addr] = true   -- (a bound copy of the host's)
local JO = zfa("SV_Unit_ZfaArm2_1", 305000, 0, 110000)                          -- (ship 2's: another dive)
check(ZDIVE.holdLocal(1) == nil, "no zd h from the host: nil (finished off as before)")
ZDIVE.fromHost({ "zd", "h", "1", "3", "7" })
ZDIVE.fromHost({ "zd", "h", "2", "3", "8" })
check(ZDIVE.holdLocal(1) == 2 and not ZDIVE.diving(JC.addr), "after zd h: this game's own 2 kept, not the host's bound copy")
check(ZDIVE.holdLocal(2) == 1, "ship 2's own as its dive 8")
local H = enemy("SV_Unit_Pool05", 400000, 0, 110000, 100)
ZDIVE.tick()
check(#J1.orders == 0, "nothing before the host's zd v")
local c2 = #callouts
ZDIVE.fromHost({ "zd", "v", "2", "7" })
ZDIVE.tick()
check(#J1.orders == 1 and J1.orders[1].target == H.obj and #JO.orders == 0, "zd v 7: its own of dive 7 onto the nearest enemy copy, dive 8's not")
clock = clock + 1; ZDIVE.tick()
check(#callouts == c2 + 1 and callouts[#callouts][1] == DIVE.text.dive, "the callout")
local fxJ = #fx
ZDIVE.fromHost({ "zd", "b", "310000", "0", "110000", "3", "7" })
check(#fx == fxJ + 1 and fx[#fx].at.X == 310000 and downByModify(J2) and #J1.hits == 0 and #JO.hits == 0,
      "zd b of dive 7: the effects there, its own nearest of that dive finished off (not dive 8's, nearer)")
check(H.obj.HealthInternal == 100 and #H.obj.hits == 0, "no kill of its own (the host's kills come as they do)")
clock = clock + 1; ZDIVE.tick()
check(callouts[#callouts][2] == string.format(DIVE.text.blast_sub, 3), "the host's count")
fxJ = #fx
ZDIVE.fromHost({ "zd", "b", "nan", "0", "0", "1", "7" })
ZDIVE.fromHost({ "zd", "b", "1e99", "0", "0", "1", "7" })
ZDIVE.fromHost({ "zd", "b", "0", "0", "9e9", "1", "7" })
check(#fx == fxJ, "bad numbers dropped")
for _ = 1, 20 do ZDIVE.fromHost({ "zd", "b", "0", "0", "100000", "1", "99" }) end
check(#fx - fxJ <= 12, "at most 12 blasts a second shown (" .. (#fx - fxJ) .. ")")
clock = clock + 2
ZDIVE.fromHost({ "zd", "e", "7" })
ZDIVE.tick()
check(downByModify(J1) and lastLog("the host's dive 7 over") ~= nil, "zd e 7: the rest of dive 7 finished off")
check(not JO.off and ZDIVE.diving(JO.addr), "dive 8's untouched (" .. tostring(JO.HealthInternal) .. ")")
ZDIVE.fromHost({ "zd", "e" })
ZDIVE.tick()
check(JO.HealthInternal == 0, "an older host's zd e (no dive): every dive's")
COOP = nil

section("the hooks")
local esc = PARTS.read("sv_escort")      -- (sv_escort.lua's family: the carriers are in sv_escort_carriers.lua)
check(esc:find("return (ZDIVE and ZDIVE.take and ZDIVE.take(C)) or (C.flight and flightOff(C.flight, why)) or 0", 1, true) ~= nil
      and esc:find('local nf = shipDone(C, C.name .. " leaving")', 1, true) ~= nil and esc:find('local nf = shipDone(C, C.name .. " sunk")', 1, true) ~= nil,
      "sv_escort.lua: a carrier leaving or sunk asks ZDIVE.take first (shipDone)")
check(esc:find("local n = ZDIVE and ZDIVE.holdLocal and ZDIVE.holdLocal(i)", 1, true) ~= nil,
      "sv_escort.lua: a joiner's own kept for the host's dive (ESC.localOff)")
local las = readAll(MOD .. "/Scripts/sv_escort_laser.lua")
check(las:find("not (ZDIVE and ZDIVE.diving and ZDIVE.diving(e.addr))", 1, true) ~= nil and las:find("ZDIVE.waiting(e.addr)", 1, true) ~= nil,
      "the escort's cover skips a diving one, covers a waiting one")
check(las:find("pcall(ZDIVE.tick)", 1, true) ~= nil, "ZLAS.tick runs ZDIVE.tick")
check(readAll(MOD .. "/Scripts/sv_coop_migration.lua"):find('k == "zd" and COOP.client()', 1, true) ~= nil, "the joiner's zd dispatch")
local fam = PARTS.family("sv_escort")
local posOf = {}
for i, m in ipairs(fam) do posOf[m] = i end
-- ((2026-11-11) sv_escort_waves.lua comes after it now: the order that matters is after sv_escort_li's)
check(posOf["sv_escort_dive.lua"] and posOf["sv_escort_li.lua"] and posOf["sv_escort_dive.lua"] > posOf["sv_escort_li.lua"],
      "main.lua MODULES: sv_escort_dive after sv_escort_li")

print(fails == 0 and "dive test: all checks passed" or ("dive test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
