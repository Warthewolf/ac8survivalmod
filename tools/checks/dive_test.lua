-- dive_test.lua <mod dir> (run by tools/checks/dive_test.sh): the VAMPIRES' final dive (2026-11-08, Scripts/sv_escort_dive.lua)
-- on the real part with the shipped settings (sv_config.lua's CFG.allies.carrier.dive), the game stubbed:
--   a carrier leaving after its service: its ZFA-44s up kept (not a parked one, not another ship's), nil with none or the
--     dive off; nothing through the break, nothing in the next round before its enemies; then each onto the nearest enemy
--     aircraft (one each), the callout once; within detonate_m the Helios blast on its target: every enemy within blast_m
--     down with you as the cause, an ace's hurt by boss_pct, one farther untouched, the other ZFA-44 (an ally) untouched,
--     the effects (Niagara, sound, camera shake), the callout; a target down: the next; dive_s on: the blast where it is;
--     all gone: the units recycled, co-op told; a round with no enemy aircraft: they leave unpaid; a new run: the old
--     run's finished off;
--   a joiner: the host's "zd h" then its carrier gone (ESC.localOff): this game's own kept (not the host's bound copies),
--     ordered at "v", one finished off at each "b" with the effects there and no kill of its own, bad numbers dropped,
--     at most 12 blasts a second, "e" the rest;
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
local logs, callouts, msgs, fx, sounds, shakes, removed = {}, {}, {}, {}, {}, {}, {}
function log(s) logs[#logs + 1] = s end
function logOnce(_, s) log(s) end
local function lastLog(p) for i = #logs, 1, -1 do if logs[i]:find(p, 1, true) then return logs[i] end end return nil end
function hudCallout(t, s) callouts[#callouts + 1] = { t, s } end
local nextAddr = 100
local function plane(x, y, z, h)
    nextAddr = nextAddr + 1
    local o = { addr = nextAddr, loc = { X = x, Y = y, Z = z }, HealthInternal = h or 100, orders = {}, hits = {} }
    function o:K2_GetActorLocation() return { X = self.loc.X, Y = self.loc.Y, Z = self.loc.Z } end
    function o:EngagementOrderOverride(order, target, prio, a, b, fire, c) self.orders[#self.orders + 1] = { target = target, prio = prio } end
    function o:ModifyHealth(dh, inst, b)
        self.hits[#self.hits + 1] = { dh = dh, inst = inst }
        self.HealthInternal = math.max(0, self.HealthInternal + dh)
    end
    function o:SetIsInvincible(v) self.inv = v end
    function o:SetMinHealth(v) self.minH = v end
    return o
end
function liveAddr(o) return type(o) == "table" and not o.gone and o.addr or nil end
function liveObj(o) return type(o) == "table" and not o.gone end
function valid(o) return type(o) == "table" and not o.gone end
local GS = { ApplyDamage = function(self, o, dmg) o.finished = (o.finished or 0) + 1; o.HealthInternal = 0 end }
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
ESC = { planes = {}, recycleQ = {} }
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

-- names as the game gives them; ESC.same as sv_escort_laser.lua has it (its own text, loaded alone)
function nameOf(o) return type(o) == "table" and (o.fullName or ("BP_OP0018_uavc_CP_Ally_C /Game/PL:PersistentLevel.BP_OP0018_uavc_CP_Ally_C_" .. tostring(o.addr))) or "?" end
ZLAS = {}
do
    local las = readAll(MOD .. "/Scripts/sv_escort_laser.lua")
    local a = las:find("function ESC.same(e, maxAge)", 1, true)
    local b = a and las:find("\nend\n", a, true)
    assert(a and b, "no ESC.same in sv_escort_laser.lua")
    assert(load(las:sub(a, b + 4), "=ESC.same"))()
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
check(ZDIVE.take(C) == nil, "the dive off: nil (its flight switched off as before)")
DIVE.enabled = true
local n = ZDIVE.take(C)
check(n == 2, "its two up kept, not the parked one, not the other ship's (" .. tostring(n) .. ")")
check(lastLog("ZFA-44 CARRIER 1 leaving: 2 ZFA-44s stay up for their final dive as round 4's enemies come") ~= nil, "logged")
check(ZDIVE.diving(Z1.addr) and ZDIVE.diving(Z2.addr) and not ZDIVE.diving(ZO.addr) and not ZDIVE.diving(ZP.addr),
      "ZDIVE.diving: the held ones only (the escort leaves them be)")
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
check(#callouts == 1 and callouts[1][1] == DIVE.text.dive and callouts[1][2] == string.format(DIVE.text.dive_sub, 2), "the callout once: 2 dive")
clock = clock + 1
ZDIVE.tick()
check(#Z1.orders == 1 and #callouts == 1, "not ordered again before reorder_s")
clock = clock + DIVE.reorder_s
ZDIVE.tick()
check(#Z1.orders == 2 and Z1.orders[2].target == A.obj, "again every reorder_s, the same target")

section("the Helios blast on its target")
Z1.loc = { X = A.obj.loc.X - (DIVE.detonate_m - 50) * 100, Y = 0, Z = 110000 }
local z2h = Z2.HealthInternal
ZDIVE.tick()
check(A.obj.HealthInternal == 0 and A.obj.hits[1].inst == PAWN and A.obj.hits[1].dh <= -1000000, "its target down, you the cause")
check(B.obj.HealthInternal == 0, "an enemy 500 m off it down too")
check(math.abs(AC.obj.HealthInternal - 400 * (1 - DIVE.boss_pct)) < 1e-6, "the ace's boss_pct off, not killed (" .. AC.obj.HealthInternal .. ")")
check(F.obj.HealthInternal == 100 and #F.obj.hits == 0, "one 20 km off untouched")
check(Z1.finished == 1 and Z2.HealthInternal == z2h and #Z2.hits == 0, "the ZFA-44 finished off, unpaid; the other (an ally) untouched")
check(#fx == 1 and fx[1].sys.path == DIVE.fx .. "." .. DIVE.fx:match("[^/]+$") and fx[1].at.X == A.obj.loc.X, "the Helios burst where its target was")
check(#sounds == 1 and sounds[1].ev.path:find("OBJ_M09_CLOUDBOMB_EXP", 1, true) ~= nil, "its sound there")
check(#shakes == 1 and shakes[1].cls.path:find("BP_CamShake_BombImpactHelios_C", 1, true) ~= nil and shakes[1].scale >= 0.2 and shakes[1].scale < 1,
      "the camera shake, by your distance (5 km: " .. tostring(shakes[1] and shakes[1].scale) .. ")")
check(callouts[#callouts][1] == DIVE.text.blast and callouts[#callouts][2] == string.format(DIVE.text.blast_sub, 2), "HELIOS IMPACT: 2 down")
check(lastLog("Helios blast 1 (on its target)") ~= nil and lastLog("2 enemy aircraft down, 1 aces' or specials' hurt") ~= nil, "logged")
A.down, B.down = true, true

section("a target down: the next; dive_s on: the blast where it is")
clock = clock + 0.5
ZDIVE.tick()
local last = Z2.orders[#Z2.orders].target
check(last == AC.obj or last == F.obj, "Z2 onto the next nearest up")
clock = clock + DIVE.dive_s + 1
YOU.X = 9000000                                                   -- (you far off: no shake)
local shakes0 = #shakes
ZDIVE.tick()
check(Z2.finished == 1 and #fx == 2 and fx[2].at.X == Z2.loc.X, "dive_s on: its blast where it is")
check(#shakes == shakes0, "no camera shake 90 km off")
check(F.obj.HealthInternal == 100, "nothing near it down")
ZDIVE.tick()
check(lastLog("dive: over: 2 blasts, 2 enemy aircraft down") ~= nil, "over: logged")
local rq = {}
for _, e in ipairs(ESC.recycleQ) do rq[e.unit] = true end
check(rq.SV_Unit_ZfaArm1_1 and rq.SV_Unit_ZfaArm1_2, "their units on the recycle queue (off the list once none is up)")
check(not ZDIVE.diving(Z1.addr) and not ZDIVE.diving(Z2.addr), "none diving now")

section("a round with no enemy aircraft: they leave")
for _, p in ipairs(planes) do p.down = true end
D = { round = 6, state = "wait" }
local Z3 = zfa("SV_Unit_ZfaPose1", 0, 0, 110000)
check(ZDIVE.take(C) == 1, "kept")
D.round, D.state = 7, "fighting"
ZDIVE.tick()
check(Z3.finished == nil, "round 7, no enemy aircraft: still held")
D.round = 8
ZDIVE.tick()
check(Z3.finished == 1 and #fx == 2 and lastLog("found no enemy aircraft in round 7") ~= nil, "round 8: finished off, unpaid, no blast")

section("a new run: the old run's held ones finished off")
D = { round = 3, state = "wait" }
local Z4 = zfa("SV_Unit_ZfaPose1", 0, 0, 110000)
check(ZDIVE.take(C) == 1, "kept")
D = { round = 1, state = "wait" }
ZDIVE.tick()
check(Z4.finished == 1 and lastLog("held ZFA-44s of the last run finished off") ~= nil, "finished off with the run")

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
check(ZK.finished == nil and #ZK.hits == 0, "a held one taken over by another plane is never finished off")
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

section("co-op: the host tells the joiners")
D = { round = 3, state = "wait" }
COOP = { open = true, client = function() return false end, msg = function(to, ...) msgs[#msgs + 1] = { ... } end,
         removeNow = function(u) removed[#removed + 1] = u end, removeObj = function() end }
local Z5 = zfa("SV_Unit_ZfaPose2", 0, 0, 110000)
check(ZDIVE.take({ idx = 2, name = "ZFA-44 CARRIER 2" }) == 1 and msgs[1][1] == "zd" and msgs[1][2] == "h" and msgs[1][3] == "2" and msgs[1][4] == "3",
      "zd h <ship> <round>")
local G = enemy("SV_Unit_Pool04", 100000, 0, 110000)
D.round, D.state = 4, "wave"
ZDIVE.tick()
check(msgs[#msgs][2] == "v" and msgs[#msgs][3] == "1", "zd v <count>")
Z5.loc = { X = 100000, Y = 0, Z = 110000 }
ZDIVE.tick()
check(msgs[#msgs][2] == "b" and tonumber(msgs[#msgs][3]) == 100000 and msgs[#msgs][6] == "1", "zd b x y z <down so far>")
ZDIVE.tick()
check(msgs[#msgs][2] == "e" and #removed >= 1 and removed[1] == "SV_Unit_ZfaPose2", "zd e, the copies removed (COOP.removeNow)")
G.down = true

section("a joiner")
D = { round = 3, state = "wait" }
local copies = {}
COOP = { open = true, client = function() return true end, msg = function() error("a joiner sends no zd") end,
         copyAt = function(a) return copies[a] == true end }
local J1 = zfa("SV_Unit_ZfaArm1_1", 0, 0, 110000)
local J2 = zfa("SV_Unit_ZfaArm1_2", 300000, 0, 110000)
local JC = zfa("SV_Unit_ZfaPose1", 0, 900000, 110000); copies[JC.addr] = true   -- (a bound copy of the host's)
check(ZDIVE.holdLocal(1) == nil, "no zd h from the host: nil (switched off as before)")
ZDIVE.fromHost({ "zd", "h", "1", "3" })
check(ZDIVE.holdLocal(1) == 2 and not ZDIVE.diving(JC.addr), "after zd h: this game's own 2 kept, not the host's bound copy")
local H = enemy("SV_Unit_Pool05", 400000, 0, 110000, 100)
ZDIVE.tick()
check(#J1.orders == 0, "nothing before the host's zd v")
local c0 = #callouts
ZDIVE.fromHost({ "zd", "v", "2" })
ZDIVE.tick()
check(#callouts == c0 + 1 and callouts[#callouts][1] == DIVE.text.dive and #J1.orders == 1 and J1.orders[1].target == H.obj,
      "zd v: the callout, its own onto the nearest enemy copy")
local fx0 = #fx
ZDIVE.fromHost({ "zd", "b", "310000", "0", "110000", "3" })
check(#fx == fx0 + 1 and fx[#fx].at.X == 310000 and J2.finished == 1 and J1.finished == nil, "zd b: the effects there, its own nearest finished off")
check(H.obj.HealthInternal == 100 and #H.obj.hits == 0, "no kill of its own (the host's kills come as they do)")
check(callouts[#callouts][2] == string.format(DIVE.text.blast_sub, 3), "the host's count")
fx0 = #fx
ZDIVE.fromHost({ "zd", "b", "nan", "0", "0", "1" })
ZDIVE.fromHost({ "zd", "b", "1e99", "0", "0", "1" })
ZDIVE.fromHost({ "zd", "b", "0", "0", "9e9", "1" })
check(#fx == fx0, "bad numbers dropped")
for _ = 1, 20 do ZDIVE.fromHost({ "zd", "b", "0", "0", "100000", "1" }) end
check(#fx - fx0 <= 12, "at most 12 blasts a second shown (" .. (#fx - fx0) .. ")")
clock = clock + 2
ZDIVE.fromHost({ "zd", "e" })
check(J1.finished == 1 and lastLog("the host's dive over") ~= nil, "zd e: the rest finished off")
COOP = nil

section("the hooks")
local esc = readAll(MOD .. "/Scripts/sv_escort.lua")
check(esc:find("local nf = (ZDIVE and ZDIVE.take and ZDIVE.take(C)) or (C.flight and flightOff(C.flight", 1, true) ~= nil,
      "sv_escort.lua: a carrier leaving asks ZDIVE.take first")
check(esc:find("local n = (ZDIVE and ZDIVE.holdLocal and ZDIVE.holdLocal(i)) or ownZfaOff(i, nil)", 1, true) ~= nil,
      "sv_escort.lua: a joiner's own kept for the host's dive (ESC.localOff)")
local las = readAll(MOD .. "/Scripts/sv_escort_laser.lua")
check(las:find("not (ZDIVE and ZDIVE.diving and ZDIVE.diving(e.addr))", 1, true) ~= nil, "the escort's cover skips a diving one")
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
