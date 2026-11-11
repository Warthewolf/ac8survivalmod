#!/bin/sh
# fleet_test.sh : INVINCIBLE FLEET's test part Scripts/sv_fleet.lua (GEOFON's look tests T1 and T2, test builds only:
# docs/design/INVINCIBLE_FLEET_RISE_FORD.md 4.2 (a), (b) and 5) run alone on build/checks/lua.exe (tools/checks/lua_build.sh
# makes it), the game and the parts it calls stubbed (the harness below, written to build/checks/fleet):
#   its settings: CFG.specials.fleet.geofon, the same in CFG_DEFAULTS (shipped: no edit, nothing for co-op to send);
#   the keys: Ctrl+B and Ctrl+G refused outside a run, on a joiner and in a Spaceport round;
#   T1 (Ctrl+B): the Ford spawned 3.5 km ahead broadside with spawningUnit set and its objects caught, its up line, the V
#     posed (DamagedStaticMesh shown, +25 deg and 21 m down; VesselMesh -15 deg and 23 m down, its 3 slots on their _DAM
#     instances; its 4 parts hidden and switched off, its 2 antennas hidden, the hull invincible), the 2 s lines read back
#     (gap ~0 m at the break), the halves parted from +10 s in steps of at most 1 m (4 a second), held while paused, ~220 m
#     apart at the end; again: taken off (SV_Recycle); the bow copy hanging on VesselMesh posed in its frame; the hull's
#     address taken by another object: nothing more done to it (hard rule 59);
#   T2 (Ctrl+G): GEOFON 4 km ahead, its up line, 20 % a press (ModifyHealth), stage 1 at 66 % (2 fires and 2 smoke on
#     VesselMesh at their offsets, the sound, the list ramped at most 0.1 deg a tick), stage 2 at 33 % (3 more fires, its
#     slots on dimmed copies of the _DAM instances), a system that ended spawned again, the 5 s lines, the last press to 0
#     (SetMinHealth), down, its systems off 30 s on and destroyed; Ctrl+B with it up takes it off first;
#   the level torn down: forgotten;
# then a release's copy of the parts (tools/strip_test_only.py): sv_fleet.lua only its header, every part still loading
# (lua_load_test.sh).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/fleet"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
rm -rf "$W" && mkdir -p "$W/stripped"
cat > "$W/fleet_test.lua" <<'EOF'
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local logs, callouts = {}, {}
function log(s) logs[#logs + 1] = s end
local function find(pat, from)                         -- the first log line from index `from` matching pat
    for i = from or 1, #logs do if logs[i]:find(pat) then return logs[i], i end end
    return nil
end
local function count(pat, from)
    local n = 0
    for i = from or 1, #logs do if logs[i]:find(pat) then n = n + 1 end end
    return n
end
local said = {}
function logOnce(k, m) if not said[k] then said[k] = true; log(m) end end
function crumb() end
function hudCallout(a, b) callouts[#callouts + 1] = tostring(a) .. " / " .. tostring(b) end
local clock = 100
os.clock = function() return clock end           -- luacheck: ignore

-- the game's objects: live while LIVE[addr]; a name kept on __name (nameOf), the address on __addr
local LIVE, nextA = {}, 0x1000
local function obj(name, t)
    nextA = nextA + 0x10
    t = t or {}
    t.__addr, t.__name = nextA, name
    LIVE[nextA] = true
    return t
end
local function free(o) LIVE[o.__addr] = nil end
function liveAddr(o) local a = type(o) == "table" and o.__addr; return (a and LIVE[a]) and a or nil end
function liveObj(o) return liveAddr(o) ~= nil end
function valid(o) return liveAddr(o) ~= nil end
function addrOf(o) return type(o) == "table" and o.__addr or nil end
function nameOf(o) if not liveAddr(o) then return "?" end return o.__name end
function FName(s) return s end

local function rotP(x, z, deg)
    local a = math.rad(deg)
    return x * math.cos(a) - z * math.sin(a), x * math.sin(a) + z * math.cos(a)
end
-- a component's origin and pitch / roll in its actor's frame (cm), through its parents
local function inActor(c)
    if not c.parent or c.parent.isRoot then
        local l, r = c.RelativeLocation, c.RelativeRotation
        return { x = l.X, y = l.Y, z = l.Z, p = r.Pitch, r = r.Roll }
    end
    local pf = inActor(c.parent)
    local l, r = c.RelativeLocation, c.RelativeRotation
    local rx, rz = rotP(l.X, l.Z, pf.p)
    return { x = pf.x + rx, y = pf.y + l.Y, z = pf.z + rz, p = pf.p + r.Pitch, r = pf.r + r.Roll }
end
local sets = 0                                       -- K2_SetRelativeLocationAndRotation calls
local function comp(fn, parent, owner)
    local c = obj("StaticMeshComponent " .. owner.__name .. "." .. fn)
    c.fn, c.parent, c.owner, c.visible, c.slots = fn, parent, owner, true, {}
    c.RelativeLocation, c.RelativeRotation = { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }
    c.GetFName = function() return { ToString = function() return fn end } end
    c.GetAttachParent = function(self) return self.parent end
    c.IsVisible = function(self) return self.visible end
    c.SetVisibility = function(self, v) self.visible = v end
    c.SetHiddenInGame = function(self, h) self.hiddenInGame = h end
    c.K2_SetRelativeLocationAndRotation = function(self, l, r)
        sets = sets + 1
        self.RelativeLocation = { X = l.X, Y = l.Y, Z = l.Z }
        self.RelativeRotation = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
    end
    c.K2_SetRelativeRotation = function(self, r) self.RelativeRotation = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end
    c.K2_GetComponentLocation = function(self)
        local f, o = inActor(self), self.owner
        local a = math.rad(o.yaw)
        return { X = o.loc.X + f.x * math.cos(a) - f.y * math.sin(a), Y = o.loc.Y + f.x * math.sin(a) + f.y * math.cos(a), Z = o.loc.Z + f.z }
    end
    c.K2_GetComponentRotation = function(self) local f = inActor(self); return { Pitch = f.p, Yaw = self.owner.yaw, Roll = f.r } end
    c.GetNumMaterials = function(self) return #self.slots end
    c.GetMaterial = function(self, i) return self.slots[i + 1] end
    c.SetMaterial = function(self, i, m) self.slots[i + 1] = m end
    c.CreateDynamicMaterialInstance = function(self, i, parent)
        local mid = obj("MaterialInstanceDynamic /Engine/Transient.MID_" .. nextA, { params = {}, Parent = parent })
        mid.K2_GetScalarParameterValue = function(_, n) return n == "Charred_Embers_Brightness" and 650000 or 0 end
        mid.SetScalarParameterValue = function(self2, n, v) self2.params[n] = v end
        self.slots[i + 1] = mid
        return mid
    end
    return c
end
local MATS = "/Game/Vehicles/Vessels/VE004_gfrd/Materials/01/"
local assets = {}
function loadObject(path)
    if not assets[path] then
        local a = obj("Asset " .. path)
        a.GetPathName = function() return path end
        assets[path] = a
    end
    return assets[path]
end
local function mat(n)
    local nm = string.format("MI_VE004_grfd_%02d", n)
    local m = obj("MaterialInstanceConstant " .. MATS .. nm .. "." .. nm)
    m.GetPathName = function() return MATS .. nm .. "." .. nm end
    return m
end

-- the spawner: the Ford's hull (root, VesselMesh, DamagedStaticMesh, two antennas) and its four Mk 15s
local FORD = "SV_Unit_SpFord"
local notifies, spawns, recycles, alive, nFord = {}, {}, {}, {}, 0
local spawnOpts = {}
local fords = {}
function NotifyOnNewObject(cls, fn) notifies[cls] = notifies[cls] or {}; table.insert(notifies[cls], fn) end
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw, su = spawningUnit }
    nFord = nFord + 1
    local h = obj(string.format("BP_VE004_grfd_CP_Ally_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_VE004_grfd_CP_Ally_C_%d", nFord),
        { loc = { X = x, Y = y, Z = z }, yaw = yaw, HealthInternal = 300000, MaxHealth = 30000, calls = {} })
    h.K2_GetActorLocation = function(self) return self.loc end
    h.K2_GetActorRotation = function(self) return { Pitch = 0, Yaw = self.yaw, Roll = 0 } end
    h.SetIsInvincible = function(self, v) self.inv = v end
    h.SetMinHealth = function(self, v) self.minHealth = v end
    h.ModifyHealth = function(self, d) if not self.inv then self.HealthInternal = math.max(0, self.HealthInternal + d * 10) end end
    h.SetActorHiddenInGame = function(self, v) self.hiddenActor = v end
    local root = obj("SceneComponent " .. h.__name .. ".DefaultSceneRoot", { isRoot = true })
    root.GetFName = function() return { ToString = function() return "DefaultSceneRoot" end } end
    h.root = root
    h.K2_GetRootComponent = function(self) return self.root end
    local vm = comp("VesselMesh", root, h)
    local dm = comp("DamagedStaticMesh", spawnOpts.bowOnVessel and vm or root, h)
    dm.visible = false
    vm.slots = { mat(1), mat(2), mat(3) }
    h.comps = { vm, dm, comp("SM_VE004_grfd_antenna_01", vm, h), comp("SM_VE004_grfd_antenna_02", vm, h) }
    h.VesselMesh, h.DamagedStaticMesh = vm, dm
    local made = { h }
    for k = 1, 4 do
        local p = obj(string.format("BP_VE004_grfd_mk15_%02d_CP_Ally_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_VE004_grfd_mk15_%02d_CP_Ally_C_%d", k, k, nFord), {})
        p.SetActorHiddenInGame = function(self, v) self.hiddenActor = v end
        p.SetActive = function(self, v) self.active = v end
        made[#made + 1] = p
    end
    for _, o in ipairs(made) do for _, fn in ipairs(notifies["/Script/Live.LiveAIGameObject"] or {}) do fn(o) end end
    alive[unit] = 1
    fords[#fords + 1] = { hull = h, parts = { table.unpack(made, 2) }, all = made }
    return 1
end
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_Recycle(u)
    recycles[#recycles + 1] = u
    for _, f in ipairs(fords) do for _, o in ipairs(f.all) do free(o) end end
    alive[u] = 0
    return 1
end
SV_ERR = { [0] = "the game spawned nothing" }
SPC = { V = { comps = function(o) return o.comps or {} end,
              PART_FLAGS = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true } } }

-- the engine's libraries: Niagara (the systems attached), materials, Wwise, damage
local fxs, posts = {}, {}
local lib = obj("NiagaraFunctionLibrary /Script/Niagara.Default__NiagaraFunctionLibrary")
lib.SpawnSystemAttached = function(_, sys, onto, _, loc)
    local f = obj("NiagaraComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.NiagaraComponent_" .. nextA, { active = true })
    f.IsActive = function(self) return self.active end
    f.Deactivate = function(self) self.active = false; self.deactivated = true end
    f.K2_DestroyComponent = function(self) self.destroyed = true; free(self) end
    f.SetWorldScale3D = function() end
    fxs[#fxs + 1] = { sys = sys, onto = onto, loc = loc, c = f }
    return f
end
local ak = obj("AkGameplayStatics /Script/AkAudio.Default__AkGameplayStatics")
ak.PostEventAtLocation = function(_, ev, where) posts[#posts + 1] = { ev = ev, where = where }; return 1 end
local STATICS = { ["/Script/Niagara.Default__NiagaraFunctionLibrary"] = lib, ["/Script/AkAudio.Default__AkGameplayStatics"] = ak }
function StaticFindObject(p) return STATICS[p] end
function FindFirstOf() return nil end

-- the parts sv_fleet.lua uses
local PAUSED = false
function gamePaused() return PAUSED end
survivalPC = obj("PlayerController /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PC_0",
                 { Pawn = { K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end } })
function playerLocation() return { X = 0, Y = 0, Z = 100000 } end
function nativeReady() return true end
D, RUN, COOP = nil, {}, { client = function() return false end, host = function() return false end }
CFG = { specials = {} }
CFG_DEFAULTS = { specials = {} }
function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
local keys = {}
TEST_TICKS, LEVEL_DROPS = {}, {}
function testKey(name, who, fn) keys[name] = fn; return true end

dofile(MOD .. "/Scripts/sv_fleet.lua")
local C = CFG.specials.fleet and CFG.specials.fleet.geofon
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
check(C ~= nil and C.unit == FORD and #C.stages == 2 and C.look.bow.pitch == 25 and C.look.stern.down_m == 23,
    "CFG.specials.fleet.geofon: the Ford, two stages, the V's angles")
check(CFG_DEFAULTS.specials.fleet ~= CFG.specials.fleet and same(CFG_DEFAULTS.specials.fleet, CFG.specials.fleet),
    "the same in CFG_DEFAULTS (a copy): shipped, no edit")
check(type(keys.B) == "function" and type(keys.G) == "function" and #TEST_TICKS == 1 and type(LEVEL_DROPS.fleet) == "function",
    "Ctrl+B, Ctrl+G, its tick and its level drop")
local tick = TEST_TICKS[1].fn
local function run(secs) for _ = 1, math.floor(secs / 0.25 + 0.5) do clock = clock + 0.25; tick(clock) end end

-- refusals
keys.B()
check(find("geofon: Ctrl%+B outside a Survival run") ~= nil and #spawns == 0, "Ctrl+B outside a run: refused")
D = { now = 5 }
COOP.client = function() return true end
keys.G()
check(find("geofon: Ctrl%+G: the host spawns it") ~= nil and #spawns == 0, "Ctrl+G on a joiner: refused")
COOP.client = function() return false end
D.special = { kind = "spaceport" }
keys.B()
check(find("not in a Spaceport round") ~= nil and #spawns == 0, "Ctrl+B in a Spaceport round: refused")
D.special = nil

print("T1, Ctrl+B")
local n0 = #logs
keys.B()
local s1 = spawns[1]
check(s1 and s1.unit == FORD and math.abs(s1.x - 350000) < 1 and math.abs(s1.y) < 1 and s1.z == 50 and s1.yaw == 90 and s1.su == FORD,
    "the Ford spawned 3.5 km ahead of you, broadside (yaw 90), at z 50 cm, spawningUnit its unit")
check(find("geofon: Ctrl%+B %(the V%-break look%), SV_Unit_SpFord at %(350000, 0, 50%) facing 90 %(you at yaw 0%): 1 up; 5 objects made", n0) ~= nil,
    "its spawn logged with the 5 objects made")
run(1.5)
local F = fords[1]
local up = find("^geofon: up: ", n0)
check(up and up:find("SV_Unit_SpFord BP_VE004_grfd_CP_Ally_C_1, health 300000 %(of 300000%)") and up:find("VesselMesh %(on DefaultSceneRoot, shown%)")
    and up:find("DamagedStaticMesh %(on DefaultSceneRoot, hidden%)") and up:find("4 parts") ~= nil, "its up line: " .. tostring(up))
local once = find("^geofon: break look: bow copy", n0)
check(once == "geofon: break look: bow copy (DamagedStaticMesh) pitch +25 down 21 m, stern copy (VesselMesh, 3 slots _DAM) pitch -15 down 23 m; "
    .. "4 parts, 2 antennas hidden", "the once line: " .. tostring(once))
local vm, dm = F.hull.VesselMesh, F.hull.DamagedStaticMesh
check(vm.RelativeLocation.Z == -2300 and vm.RelativeRotation.Pitch == -15 and dm.RelativeLocation.Z == -2100 and dm.RelativeRotation.Pitch == 25,
    "the stern copy at -15 deg 23 m down, the bow copy at +25 deg 21 m down")
check(dm.visible == true and F.hull.comps[3].visible == false and F.hull.comps[4].visible == false, "the bow copy shown, the antennas hidden")
local damOk = true
for i = 1, 3 do if vm.slots[i] ~= assets[string.format("%sMI_VE004_grfd_%02d_DAM.MI_VE004_grfd_%02d_DAM", MATS, i, i)] then damOk = false end end
check(damOk, "the stern copy's 3 slots on their own _DAM instances")
local partsOk = true
for _, p in ipairs(F.parts) do if not (p.hiddenActor == true and p.active == false and p.bIsInvincible == true and p.bShowHUDBox == false) then partsOk = false end end
check(partsOk and F.hull.inv == true, "its 4 parts hidden, switched off and untargetable; the hull invincible")
local l1 = find("^geofon: break look %+%d+ s:", n0)
check(l1 and l1:find("bow %(0%.0, 0%.0, %-21%.0%) m, stern %(0%.0, 0%.0, %-23%.0%) m, gap %-?0 m; pitch %+25%.0 / %-15%.0") ~= nil,
    "the first 2 s line, read back in the ship's frame, the decks meeting at the water: " .. tostring(l1))
run(9.5)                                             -- (to +11 s: not moving yet)
check(dm.RelativeLocation.X == 0, "no move before move_after_s")
local lastX, maxStep = dm.RelativeLocation.X, 0
for _ = 1, 40 do clock = clock + 0.25; tick(clock); maxStep = math.max(maxStep, dm.RelativeLocation.X - lastX); lastX = dm.RelativeLocation.X end
check(dm.RelativeLocation.X > 0 and vm.RelativeLocation.X < 0 and maxStep <= 101, string.format("the halves part, a step at most 1 m (%.0f cm)", maxStep))
PAUSED = true
local xp = dm.RelativeLocation.X
run(3)
check(dm.RelativeLocation.X == xp, "held while the game is paused")
PAUSED = false
run(20)
check(math.abs(dm.RelativeLocation.X - 10000) < 1 and math.abs(vm.RelativeLocation.X + 10000) < 1 and math.abs(dm.RelativeLocation.Z + 2500) < 1
    and math.abs(vm.RelativeLocation.Z + 2600) < 1, "parted 100 m each way, 4 and 3 m further down")
check(find("geofon: break look %+%d+ s: parted %(100 m each way%), held there", n0) ~= nil, "the parted line")
local lastLine = logs[#logs]
for i = #logs, 1, -1 do if logs[i]:find("^geofon: break look %+%d+ s: bow") then lastLine = logs[i]; break end end
local gap = tonumber(lastLine:match("gap (%-?%d+) m"))
check(gap and gap >= 210 and gap <= 230, "the gap at the waterline once parted: " .. tostring(gap) .. " m")
local nLines = count("^geofon: break look %+%d+ s: bow", n0)
check(nLines >= 15 and nLines <= 25, "a line every 2 s (" .. nLines .. ")")
local r0 = #recycles
keys.B()
check(#recycles == r0 + 1 and recycles[#recycles] == FORD and find("geofon: break look off at %+%d+ s %(Ctrl%+B%): 5 of its objects hidden, SV_Recycle 1", n0) ~= nil,
    "Ctrl+B again: hidden and taken off (SV_Recycle)")
run(1)
check(GEO.look == nil, "nothing left of it")

print("T1, the bow copy hanging on VesselMesh; the hull's address reused")
spawnOpts.bowOnVessel = true
n0 = #logs
keys.B()
run(1.5)
F = fords[2]
vm, dm = F.hull.VesselMesh, F.hull.DamagedStaticMesh
local fb = inActor(dm)
check(math.abs(fb.x) < 0.01 and math.abs(fb.z + 2100) < 0.01 and math.abs(fb.p - 25) < 1e-6 and math.abs(dm.RelativeRotation.Pitch - 40) < 1e-6,
    "posed in VesselMesh's frame: +25 deg and 21 m down in the ship's (40 deg on its parent)")
l1 = find("^geofon: break look %+%d+ s:", n0)
check(l1 and l1:find("bow %(0%.0, 0%.0, %-21%.0%) m") ~= nil and l1:find("pitch %+25%.0 / %-15%.0") ~= nil, "read back the same: " .. tostring(l1))
run(12)
local setsBefore = sets
F.hull.__name = "BP_SomethingElse_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_SomethingElse_C_7"
run(2)
check(find("address is another object's now", n0) ~= nil and find("geofon: break look over at %+%d+ s: its hull is gone", n0) ~= nil and GEO.look == nil,
    "its hull's address another object's: the test over")
check(sets == setsBefore, "and nothing more done to it")
spawnOpts.bowOnVessel = nil

print("T2, Ctrl+G")
n0 = #logs
local nSp = #spawns
keys.G()
local s2 = spawns[#spawns]
check(#spawns == nSp + 1 and math.abs(s2.x - 400000) < 1 and s2.yaw == 90 and s2.su == FORD, "GEOFON spawned 4 km ahead, broadside")
check(find("geofon: Ctrl%+G %(GEOFON's stages%): SV_Unit_SpFord was still on the spawner's list %(1 up%): SV_Recycle 1", n0) ~= nil,
    "the Ford left up taken off the list first")
run(1.5)
F = fords[3]
vm = F.hull.VesselMesh
check(find("^geofon: up: SV_Unit_SpFord BP_VE004_grfd_CP_Ally_C_3", n0) ~= nil and F.hull.inv == nil, "its up line; mortal")
keys.G()
check(F.hull.HealthInternal == 240000 and find("geofon: Ctrl%+G at %+%d+ s: health 100 %% %-> 80 %% %(ModifyHealth%)", n0) ~= nil, "Ctrl+G: 20 % off")
keys.G()
run(0.25)
local st1 = find("^geofon: stage 1", n0)
check(st1 == "geofon: stage 1 at 66 % (health 60 %): 2 fires, 2 smoke, list 2.0 deg over 20 s, 0 material slots (none at this stage); its sound played",
    "stage 1: " .. tostring(st1))
local fireP = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsFireL001.NS_VesselsFireL001"
check(#fxs == 4 and fxs[1].onto == vm and fxs[1].sys == assets[fireP] and fxs[1].loc.X == 6000 and fxs[1].loc.Y == -1200 and fxs[1].loc.Z == 2100,
    "its systems attached to VesselMesh at their offsets (the first fire at (60, -12, 21) m)")
check(#posts == 1 and posts[1].ev == assets["/Game/WwiseAssets/Events/CS_AceLive_SE/Events_General/EXP/SEA/SE_GEN_EXP_SEA_VE004_grfd/AKE_GEN_EXP_SEA_VE004_grfd_Body_Killed_Secondary_Play.AKE_GEN_EXP_SEA_VE004_grfd_Body_Killed_Secondary_Play"],
    "its sound at the ship")
local lastR, maxR = vm.RelativeRotation.Roll, 0
for _ = 1, 88 do clock = clock + 0.25; tick(clock); maxR = math.max(maxR, vm.RelativeRotation.Roll - lastR); lastR = vm.RelativeRotation.Roll end
check(math.abs(vm.RelativeRotation.Roll - 2) < 1e-6 and maxR <= 0.1 + 1e-9, string.format("the list ramped to 2 deg, %.3f deg a tick at most", maxR))
local five = find("^geofon: %+%d+ s: health 60 %%, stage 1, list", n0)
check(five ~= nil and five:find("fires and smoke 4 of 4 burning") ~= nil, "the 5 s line: " .. tostring(five))
keys.G(); keys.G()
run(0.25)
local st2 = find("^geofon: stage 2", n0)
check(st2 and st2:find("^geofon: stage 2 at 33 %% %(health 20 %%%): 3 fires, 1 smoke, list 5%.0 deg over 30 s, 3 material slots %(dim, 3 of 3: slot 0 MI_VE004_grfd_01 %-> MI_VE004_grfd_01_DAM a dimmed copy, embers 650000 %-> 130000") ~= nil,
    "stage 2: " .. tostring(st2))
check(vm.slots[1].params and vm.slots[1].params.Charred_Embers_Brightness == 130000 and vm.slots[1].Parent == assets[MATS .. "MI_VE004_grfd_01_DAM.MI_VE004_grfd_01_DAM"],
    "its slots on dimmed copies of their _DAM instances")
local nFx = #fxs
fxs[1].c.active = false                              -- (a system ended by itself)
run(1.25)
check(#fxs == nFx + 1 and fxs[#fxs].loc.X == 6000 and find("spawned again as each one ends", n0) ~= nil, "a system that ended spawned again")
keys.G()
check(F.hull.minHealth == 0 and F.hull.HealthInternal == 0, "the last press: SetMinHealth 0, to 0")
run(0.25)
check(find("^geofon: down at %+%d+ s %(its hull at 0%); stages reached 2 of 2", n0) ~= nil, "down: its hull at 0")
run(30.5)
local offd = true
for _, f in ipairs(fxs) do if not f.c.deactivated and not f.c.destroyed and LIVE[f.c.__addr] then offd = false end end
check(find("its fires and smoke off", n0) ~= nil and offd, "its systems off 30 s on")
run(3.5)
local gone = 0
for _, f in ipairs(fxs) do if f.c.destroyed then gone = gone + 1 end end
check(gone == #fxs, "and destroyed (" .. gone .. " of " .. #fxs .. ")")

print("T2 then T1; the level torn down")
keys.G()
run(1.5)
n0 = #logs
keys.B()
check(find("geofon: Ctrl%+B: GEOFON's stages test taken off first", n0) ~= nil and GEO.cur == nil and GEO.look ~= nil, "Ctrl+B takes GEOFON's stages off first")
LEVEL_DROPS.fleet("test")
check(GEO.look == nil and GEO.cur == nil, "forgotten when the level goes")

if fails > 0 then print("fleet test: " .. fails .. " FAILED"); os.exit(1) end
print("fleet test: all passed")
EOF
"$LUA" "$W/fleet_test.lua" "$SRC"
echo "a release's copy (strip_test_only.py)"
cp -r "$SRC/Scripts" "$SRC/config" "$W/stripped/"
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/stripped/Scripts/*.lua "$W"/stripped/config/survival.default.ini > /dev/null
if grep -n 'GEO = \|testKey(\|CFG.specials.fleet = \|TEST_TICKS\|NotifyOnNewObject' "$W/stripped/Scripts/sv_fleet.lua"; then
    echo "  FAIL code of sv_fleet.lua left in a release's copy (above)"; exit 1
fi
if ! head -1 "$W/stripped/Scripts/sv_fleet.lua" | grep -q '^-- sv_fleet.lua'; then echo "  FAIL its header gone"; exit 1; fi
echo "  ok   sv_fleet.lua only its header ($(wc -l < "$W/stripped/Scripts/sv_fleet.lua") comment lines)"
if ! OUT=$(sh lua_load_test.sh "$W/stripped" 2>&1); then echo "$OUT"; echo "  FAIL the release copy doesn't load"; exit 1; fi
echo "  ok   $(echo "$OUT" | tail -1)"
echo "fleet test (release copy): all passed"
