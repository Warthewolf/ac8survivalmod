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
#     apart at the end; again: taken off (its 5 objects, the parts switched on again, through SPC.cleanUp; never
#     SV_Recycle with them up: the review of 8ca3195, finding 1), a press while it's being taken off or with a Ford up from
#     before not spawned beside it, Ctrl+B / Ctrl+G refused in the STORE; the bow copy hanging on VesselMesh posed in its
#     frame; the hull's address taken by another object: nothing more done to it (hard rule 59), its parts taken off;
#   T2 (Ctrl+G): GEOFON 4 km ahead, its up line, 20 % a press (ModifyHealth), stage 1 at 66 % (2 fires and 2 smoke on
#     VesselMesh at their offsets, the sound, the list ramped at most 0.1 deg a tick), stage 2 at 33 % (3 more fires, its
#     slots on dimmed copies of the _DAM instances), a system that ended spawned again, the 5 s lines, the last press to 0
#     (SetMinHealth), down, its systems off 30 s on and destroyed; a press with one sunk takes what's left of it off, a new
#     one the press after; Ctrl+B with it up takes it off first, then waits for it;
#   the level torn down: forgotten;
#   WP7, the fleet (Ctrl+N, 2026-11-12): CFG.specials.fleet's 15 ships; IFLEET.setup at the main menu waiting for the allies'
#     rows, then the model rows, the turret rows (a weapon on the Spaceport fleet's fire control where it has a clone, else its
#     stock one; the fleet's search), the Spaceport's rows the fleet names, the hulls, the names and classes, its line, once a
#     session; a row missing: said, no fleet; a text SV_SetText raises on: the rest set; Ctrl+N refused outside a run, before
#     the rows are in, on a joiner, in the STORE; a ship up from before: RE_SV_IFFleetRemove and the fleet held until it's
#     gone (one that stays 8 s: dropped, never spawned beside it); the fleet spawned 3 a step at its units' own spots (no
#     pose) with spawningUnit set, each ship's spawn and up lines (hull and parts by class, its box), the fleet-up line (km and
#     bearing from the runway and you) and its callout; the 10 s lines (GEOFON's place, speed, heading; the others' km from
#     GEOFON and m off their spot), the weapons line (a launch by a part, a shell of a part's, nothing by an object that isn't
#     the fleet's or whose address is another's now: hard rule 59); a ship not under way 15 s on given its lane again
#     (RE_SV_IFGo<Key>), then under way; an RE_SV_IFGo that raises: said, the later ships still looked at; a hull at 0 sunk
#     once; held while paused and in the STORE; again: RE_SV_IFFleetRemove, then every object still up through SPC.cleanUp,
#     no SV_Recycle (also mid-spawn), a press while it's being taken off refused; the level torn down;
# then a release's copy of the parts (tools/strip_test_only.py): sv_fleet.lua only its header, no IFLEET in any part,
# every part still loading (lua_load_test.sh); and a TESTER zip's copy (tools/dev_only.py, package_release.sh TESTER=1):
# sv_fleet / sv_tanicorn / sv_cine only their headers, none of their globals or keys anywhere, every other test block kept,
# every part loading; a part defining IFLEET outside them refused.
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
local alive2 = {}                                    -- (the fleet's units: SV_UnitAlive below)
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
-- sv_rounds.lua's clean-up (the review of 8ca3195, finding 1: a test's units go its way, never SV_Recycle(unit, 1) with
-- things up): SPC.cleanUp finishes each recorded object off (health to 0) and queues the unit's look 2 s on; cleanCheck()
-- is that look (SPC.cleanTick): the unit off the spawner's list, its objects gone
local cleanups = {}
SPC.CLEAN_OBJ, SPC.cleanQ, SPC.recycleQ = {}, {}, {}
function SPC.cleanUp(list, why, mortal, now)
    local n = 0
    for _, u in ipairs(list) do
        local l = SPC.CLEAN_OBJ[u] or {}
        for _, o in ipairs(l) do
            if liveObj(o) and (o.HealthInternal == nil or o.HealthInternal > 0) then o.HealthInternal, o.killed = 0, true; n = n + 1 end
        end
        cleanups[#cleanups + 1] = { unit = u, why = why, mortal = mortal, objs = l }
        SPC.cleanQ[#SPC.cleanQ + 1] = { unit = u, at = now + 2, mortal = mortal }
    end
    return n
end
local function cleanCheck()
    for _, e in ipairs(SPC.cleanQ) do
        if e.unit:find("^SV_Unit_IF") then alive2[e.unit] = 0 else alive[e.unit] = 0 end
        for _, o in ipairs(SPC.CLEAN_OBJ[e.unit] or {}) do free(o) end
        SPC.CLEAN_OBJ[e.unit] = nil
    end
    SPC.cleanQ = {}
end

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
check(type(keys.B) == "function" and type(keys.G) == "function" and type(keys.N) == "function" and #TEST_TICKS == 2
    and TEST_TICKS[2].name == "fleet ships" and type(LEVEL_DROPS.fleet) == "function" and type(LEVEL_DROPS["fleet ships"]) == "function",
    "Ctrl+B, Ctrl+G, Ctrl+N, their two ticks and level drops")
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
check(#recycles == r0 and find("geofon: break look off at %+%d+ s %(Ctrl%+B%): 5 of its 5 objects finished off or switched off %(off the "
    .. "spawner's list from 2 s on%)", n0) ~= nil, "Ctrl+B again: its 5 objects taken down (SPC.cleanUp), never SV_Recycle with them up")
local cu = cleanups[#cleanups]
local wokeOk = true
for _, p in ipairs(F.parts) do if not (p.active == true and p.killed) then wokeOk = false end end
check(cu and cu.unit == FORD and cu.mortal == true and #cu.objs == 5 and F.hull.killed and wokeOk and SPC.cleanQ[1] and SPC.cleanQ[1].unit == FORD,
    "the hull and its 4 parts (switched on again first) finished off, the unit's look queued")
run(1)
check(GEO.look == nil, "nothing left of it")
n0 = #logs
local nSp0 = #spawns
keys.B()
check(#spawns == nSp0 and GEO.look == nil and find("geofon: Ctrl%+B: SV_Unit_SpFord is still being taken off .*%(again in a few seconds%)", n0) ~= nil
    and callouts[#callouts] == "TEST: GEOFON V-BREAK / STILL GOING: AGAIN IN A FEW SECONDS", "Ctrl+B while it's being taken off: not spawned beside it")
cleanCheck()
alive[FORD] = 1                                          -- (still up from before, none of it known here)
n0 = #logs
keys.G()
check(#spawns == nSp0 and #recycles == r0 and find("geofon: Ctrl%+G: SV_Unit_SpFord is still up from before %(1 up%) and none of its "
    .. "objects are known here: not spawned beside it, nor forced off the spawner's list with them up", n0) ~= nil,
    "a Ford still up from before, unknown: neither spawned beside it nor forced off")
alive[FORD] = 0
D.musicHold = 1                                          -- (the landing STORE open)
n0 = #logs
keys.B(); keys.G()
check(#spawns == nSp0 and count("in the STORE: refused", n0) == 2, "Ctrl+B and Ctrl+G refused in the STORE")
D.musicHold = nil

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
check(find("address is another object's now", n0) ~= nil and find("geofon: break look over at %+%d+ s: its hull is gone %(the rest taken "
    .. "off: 4 of its 4 objects finished off", n0) ~= nil and GEO.look == nil, "its hull's address another object's: the test over, its parts taken off")
check(sets == setsBefore and not F.hull.killed and F.parts[1].killed, "and nothing more done to the hull (another object's now)")
spawnOpts.bowOnVessel = nil

print("T2, Ctrl+G")
n0 = #logs
local nSp = #spawns
keys.G()
check(#spawns == nSp and find("geofon: Ctrl%+G: SV_Unit_SpFord is still being taken off", n0) ~= nil, "not while the last one is being taken off")
cleanCheck()
keys.G()
local s2 = spawns[#spawns]
check(#spawns == nSp + 1 and math.abs(s2.x - 400000) < 1 and s2.yaw == 90 and s2.su == FORD, "then GEOFON spawned 4 km ahead, broadside")
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
n0 = #logs
nSp = #spawns
keys.G()
check(#spawns == nSp and GEO.cur == nil and find("geofon: Ctrl%+G: the GEOFON before taken off first %(4 of its 5 objects finished off", n0) ~= nil
    and fords[3].parts[4].killed, "Ctrl+G with one sunk: what's left of it taken off (its 4 parts; the hull at 0 already), no new one yet")
cleanCheck()
keys.G()
check(#spawns == nSp + 1 and GEO.cur ~= nil, "Ctrl+G again: a new GEOFON")
run(1.5)
n0 = #logs
keys.B()
check(find("geofon: Ctrl%+B: GEOFON's stages test taken off first", n0) ~= nil and GEO.cur == nil and GEO.look == nil
    and find("geofon: Ctrl%+B: SV_Unit_SpFord is still being taken off", n0) ~= nil, "Ctrl+B takes GEOFON's stages off first, then waits for it")
cleanCheck()
keys.B()
check(GEO.look ~= nil, "Ctrl+B again: the V-break look")
LEVEL_DROPS.fleet("test")
check(GEO.look == nil and GEO.cur == nil, "forgotten when the level goes")

print("WP7, the fleet: its rows at the main menu (IFLEET.setup)")
local FC = CFG.specials.fleet
check(#FC.ships == 15 and FC.ships[1].name == "GEOFON" and FC.ships[1].kind == "ford" and FC.ships[2].name == "RAVEN"
    and FC.ships[2].right_m == 600 and #FC.turret_rows == 13 and FC.formation.course_yaw == 45,
    "CFG.specials.fleet: 15 ships (GEOFON first, RAVEN 600 m off its beam), 13 turret rows, the course in")
-- the game's tables: rows by name; a row's fire-control ids FName-like (ToString), as the game hands them to Lua
local function fnameV(s) return setmetatable({ v = s }, { __index = { ToString = function(self) return self.v end } }) end
local function tbl(name) return { name = name, rows = {} } end
local T = { npc = tbl("DT_NPC"), mine = tbl("DT_SV_NpcRows"), mt = tbl("DT_NPC_Model"), mr = tbl("DT_SV_ModelRows"),
            fcs = tbl("DT_NPC_FCS"), mods = tbl("DT_NPC_AIModule") }
local PATHS = { DT_NPC = T.npc, DT_SV_NpcRows = T.mine, DT_NPC_Model = T.mt, DT_SV_ModelRows = T.mr, DT_NPC_FCS = T.fcs,
                DT_NPC_AIModule = T.mods }
PROBE_TABLES = { {}, { path = "DT_NPC" } }
CFG.specials.shuttle = { npc_rows = "DT_SV_NpcRows" }
ACE = { model_table = "DT_NPC_Model", model_rows = "DT_SV_ModelRows" }
FCS_TABLE, SEARCH_MODULE = "DT_NPC_FCS", { path = "DT_NPC_AIModule" }
local loadAsset = loadObject
for _, t in pairs(T) do PATHS[t.name] = obj("DataTable " .. t.name, t) end
function loadObject(p) return PATHS[p] or loadAsset(p) end
local copyRow = function(r) local c = {}; for k, v in pairs(r) do c[k] = v end; return c end
function dtCall(t, m, a, b)
    if m == "FindRow" then return true, t.rows[a] end
    if m == "AddRow" then t.rows[a] = copyRow(b); return true end
end
function pin() end
function gameInstance() return true end
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end
-- Survival's tables as the build makes them: the named ships' model rows, the hulls, Mission 22's turrets (an AA gun on
-- NPC_FCS_VesselAAGun000, which the Spaceport's fleet has a clone of; a ship gun on NPC_FCS_VesselMS22Artillery000, which it hasn't)
for _, c in ipairs(FC.ships) do
    if c.name ~= "" then
        T.mr.rows["SV_Model_Fleet_" .. c.key] = { GameObjectDisplayName01 = "SV_FleetName_" .. c.key }
        T.mine.rows["SV_IF_" .. c.key] = { ModelId = fnameV("SV_Model_Fleet_" .. c.key), NpcFCSId0 = fnameV("None") }
    end
end
for _, r in ipairs(FC.turret_rows) do
    T.mine.rows[r] = { NpcFCSId0 = fnameV(r:find("Art", 1, true) and "NPC_FCS_VesselMS22Artillery000" or "NPC_FCS_VesselAAGun000"),
                       NpcFCSId1 = fnameV("None") }
end
SPORT = { FLEET_ROWS = { "SV_Fleet_Mk15Aegis", "SV_Fleet_FordHull" } }
T.npc.rows.SV_Fleet_Mk15Aegis = { NpcFCSId0 = fnameV("NPC_FCS_VesselCIWS000_SVA_Fleet") }   -- (in with the allies)
T.mine.rows.SV_Fleet_FordHull = { NpcFCSId0 = fnameV("None") }                            -- (not: added here)
T.fcs.rows.NPC_FCS_VesselAAGun000_SVA_Fleet = {}
T.mods.rows.NPC_AIModule_SV_Fleet = {}
ALLY, CFG.allies = { setupDone = false }, { enabled = true }
D = nil
keys.N()
check(find("fleet: Ctrl%+N outside a Survival run") ~= nil, "Ctrl+N outside a run: refused")
D = { now = 5 }
keys.N()
check(find("fleet: Ctrl%+N: the fleet's rows aren't in the game's tables %(IFLEET.setup hasn't run") ~= nil and IFLEET.cur == nil,
    "Ctrl+N before the rows are in: refused")
IFLEET.setup()
check(not IFLEET.setupDone and T.npc.rows.SV_IF_Geofon == nil, "the setup waits for the allies' (the Spaceport's turret rows)")
ALLY.setupDone = true
n0 = #logs
IFLEET.setup()
local rl = find("^fleet: rows at the main menu: ", n0)
check(rl == "fleet: rows at the main menu: 13 model rows in DT_NPC_Model, 13 hull rows and 13 turret rows in DT_NPC (9 weapons on the "
    .. "Spaceport fleet's fire control; on their stock one: NPC_FCS_VesselMS22Artillery000; their search NPC_AIModule_SV_Fleet), the "
    .. "Spaceport's 2 of 2; 20 names and classes set", "its line: " .. tostring(rl))
check(IFLEET.rowsOk == true and T.mt.rows.SV_Model_Fleet_Geofon ~= nil and T.npc.rows.SV_IF_Raven ~= nil and T.npc.rows.SV_Fleet_FordHull ~= nil
    and T.mr.rows.SV_Model_Fleet_PicketA == nil, "the models, hulls, turrets and the Spaceport's rows in (no row for an unnamed picket)")
check(T.npc.rows.SV_IFF_UdalGun.NpcFCSId0 == "NPC_FCS_VesselAAGun000_SVA_Fleet" and T.npc.rows.SV_IFF_UdalArt.NpcFCSId0:ToString() == "NPC_FCS_VesselMS22Artillery000"
    and T.npc.rows.SV_IFF_UdalGun.NpcAIModuleId == "NPC_AIModule_SV_Fleet" and T.npc.rows.SV_IF_Geofon.NpcAIModuleId == "NPC_AIModule_SV_Fleet",
    "a turret on the fleet's fire control where it has a clone, else its stock one; the fleet's search on turrets and hulls")
check(texts.SV_FleetName_Geofon == "GEOFON" and texts.SV_FleetName_Thiassi == "THIASSI" and texts.SV_FleetClass_Ford == "CARRIER"
    and texts.SV_FleetClass_Krov == "BATTLECRUISER" and texts.SV_FleetName_PicketA == nil, "the names and classes on the boxes")
local IF0 = IFLEET.setupDone
IFLEET.setup()
check(IF0 and count("^fleet: rows at the main menu", n0) == 1, "once a session")

print("WP7, Ctrl+N: the fleet at its course start")
-- the spawner: each ship at its unit's own spot (GEOFON's course start; the others off it as the build places them), a hull
-- and its parts by class; a ship sails at 12.5 m/s along the course in once it's on its lane (moving), KOLGA only once its
-- RE_SV_IFGo comes
local CLS = { ford = { "BP_VE004_grfd_CP_Ally", "BP_VE004_grfd_mk15_01_CP_Ally", "BP_VE004_grfd_mk15_02_CP_Ally",
                       "BP_VE004_grfd_mk15_03_CP_Ally", "BP_VE004_grfd_mk15_04_CP_Ally" },
              aegis = { "BP_VE002_aegs_CP", "BP_VE002_aegs_mk15_01_CP", "BP_VE002_aegs_mk41_CP", "BP_VE002_aegs_mk45_CP", "BP_VE002_artillery_CP" },
              krov = { "BP_VE005_krov_CP", "BP_VE005_krov_ak130_CP", "BP_VE005_krov_artillery_CP", "BP_VE005_krov_kashtan_07_CP", "BP_VE005_krov_s300fm_CP" },
              gors = { "BP_VE001_gors_CP", "BP_VE001_gors_3r14_CP", "BP_VE001_gors_a192_CP", "BP_VE001_gors_palma_01_CP", "BP_VE001_gors_palma_02_CP" },
              udal = { "BP_VE007_udal_CP", "BP_VE007_udal_ak130_01_CP", "BP_VE007_udal_ak130_02_CP" },
              grig = { "BP_VE015_grig_CP", "BP_VE015_grig_a190_CP", "BP_VE015_grig_ak630_01_CP", "BP_VE015_grig_ak630_02_CP" },
              boat = { "BP_VE011_mslb_CP", "BP_VE011_mslb_sam_CP" } }
local G0 = { X = -546200, Y = -2592819 }                -- (GEOFON's spawn: survival_events_fleet.if_fleet)
local a45 = math.rad(45)
local SHIPS, fleetSpawns, fleetRecycles, events, alive2, nObj = {}, {}, {}, {}, {}, 0
local spawnAsset, recycleAsset, aliveAsset = SV_Spawn, SV_Recycle, SV_UnitAlive
function SV_Spawn(unit, x, ...)
    local key = unit:match("^SV_Unit_IF(%w+)$")
    if not key then return spawnAsset(unit, x, ...) end
    local c
    for _, s in ipairs(FC.ships) do if s.key == key then c = s end end
    fleetSpawns[#fleetSpawns + 1] = { unit = unit, x = x, su = spawningUnit }
    local f, r = c.fwd_m * 100, c.right_m * 100
    local pos = { X = G0.X + math.cos(a45) * f - math.sin(a45) * r, Y = G0.Y + math.sin(a45) * f + math.cos(a45) * r, Z = 300 }
    local made = {}
    for i, cls in ipairs(CLS[c.kind]) do
        nObj = nObj + 1
        local o = obj(string.format("%s_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.%s_C_%d", cls, cls, nObj),
            { loc = pos, HealthInternal = i == 1 and 1550 or 200 })
        o.K2_GetActorLocation = function(self) return { X = self.loc.X, Y = self.loc.Y, Z = self.loc.Z } end
        o.SetActorHiddenInGame = function(self, v) self.hiddenActor = v end
        made[#made + 1] = o
    end
    for _, o in ipairs(made) do for _, fn in ipairs(notifies["/Script/Live.LiveAIGameObject"] or {}) do fn(o) end end
    SHIPS[key] = { hull = made[1], parts = { table.unpack(made, 2) }, all = made, moving = key ~= "Kolga" and key ~= "Taisch",
                   pos = pos, goAt = clock + 2.5 }
    alive2[unit] = #made
    return 1
end
function SV_UnitAlive(u) if u:find("^SV_Unit_IF") then return alive2[u] or 0 end return aliveAsset(u) end
function SV_Recycle(u, k)
    if not u:find("^SV_Unit_IF") then return recycleAsset(u, k) end
    fleetRecycles[#fleetRecycles + 1] = u
    alive2[u] = 0
    return 1
end
-- the records: RE_SV_IFFleetRemove despawns every fleet unit (but a `stuck` one); KOLGA sails once its RE_SV_IFGo comes;
-- TAISCH's RE_SV_IFGo raises (the review's finding 5: a call into the game that throws mustn't stop the later ships' looks)
local stuck = {}
function SV_Event(name)
    events[#events + 1] = name
    if name == "RE_SV_IFGoKolga" then SHIPS.Kolga.moving = true end
    if name == "RE_SV_IFGoTaisch" then error("the event table isn't there") end
    if name == "RE_SV_IFFleetRemove" then for u in pairs(alive2) do if not stuck[u] then alive2[u] = 0 end end end
    return 1
end
local bullets = {}
function FindAllOf(cls) if cls == "LiveBullet" then return bullets end return {} end
local tickN = TEST_TICKS[2].fn
local function runN(secs)
    for _ = 1, math.floor(secs / 0.25 + 0.5) do
        clock = clock + 0.25
        if not PAUSED then
            for _, s in pairs(SHIPS) do
                if s.moving and clock >= s.goAt then s.pos.X, s.pos.Y = s.pos.X + 312.5 * math.cos(a45), s.pos.Y + 312.5 * math.sin(a45) end
            end
        end
        tickN(clock)
    end
end
COOP.client = function() return true end
keys.N()
check(find("fleet: Ctrl%+N: the host spawns the fleet") ~= nil and IFLEET.cur == nil, "Ctrl+N on a joiner: refused")
COOP.client = function() return false end
D.musicHold = 1                                          -- (the landing STORE open)
n0 = #logs
keys.N()
check(IFLEET.cur == nil and find("^fleet: Ctrl%+N in the STORE: refused %(its minigame holds the world's AI; nothing spawned%)", n0) ~= nil,
    "Ctrl+N in the STORE: refused")
D.musicHold = nil
alive2.SV_Unit_IFRaven = 5                               -- (a leftover of an earlier test still up)
n0 = #logs
keys.N()
check(IFLEET.cur ~= nil and find("^fleet: Ctrl%+N: 15 ships coming up at their course start, 3 every 0.5 s", n0) ~= nil, "Ctrl+N: the fleet comes up")
check(find("^fleet: Ctrl%+N: 1 of the fleet's ships still up from before %(RAVEN%): taken off %(RE_SV_IFFleetRemove 1%); the fleet waits up "
    .. "to 8 s for them, never spawned beside them$", n0) ~= nil and events[#events] == "RE_SV_IFFleetRemove" and #fleetSpawns == 0,
    "a leftover: RE_SV_IFFleetRemove, the fleet held for it")
runN(0.25)
check(#fleetSpawns == 3 and fleetSpawns[1].unit == "SV_Unit_IFGeofon" and fleetSpawns[1].x == nil and fleetSpawns[1].su == "SV_Unit_IFGeofon"
    and fleetSpawns[2].unit == "SV_Unit_IFRaven", "3 a step, GEOFON first, at its unit's own spot (no pose), spawningUnit its unit")
check(find("^fleet: %+0 s the ships up from before are gone: the fleet comes up$", n0) ~= nil and #fleetRecycles == 0,
    "once it's gone (never SV_Recycle with it up)")
check(find("^fleet: GEOFON %(SV_Unit_IFGeofon, ford%): 1 up at its course start; 5 objects made$", n0) ~= nil
    and find("^fleet: RAVEN %(SV_Unit_IFRaven, aegis%): 1 up at its course start; 5 objects made$", n0) ~= nil, "their spawn lines")
runN(2.5)
check(#fleetSpawns == 15, "all 15 spawned in 5 steps (" .. #fleetSpawns .. ")")
local upG = find("^fleet: up: GEOFON ", n0)
check(upG == "fleet: up: GEOFON (SV_Unit_IFGeofon, ford): hull BP_VE004_grfd_CP_Ally at (-5.46, -25.93) km, health 1550; 4 parts: "
    .. "BP_VE004_grfd_mk15_01_CP_Ally, BP_VE004_grfd_mk15_02_CP_Ally, BP_VE004_grfd_mk15_03_CP_Ally, BP_VE004_grfd_mk15_04_CP_Ally; its box: GEOFON / CARRIER",
    "GEOFON's up line: " .. tostring(upG))
runN(2)
check(find("^fleet: up: BELUGA %(SV_Unit_IFBeluga, krov%): hull BP_VE005_krov_CP at .* 4 parts: BP_VE005_krov_ak130_CP, BP_VE005_krov_artillery_CP, "
    .. "BP_VE005_krov_kashtan_07_CP, BP_VE005_krov_s300fm_CP; its box: BELUGA / BATTLECRUISER$", n0) ~= nil
    and find("^fleet: up: PicketA %(SV_Unit_IFPicketA, boat%): hull BP_VE011_mslb_CP .* 1 part: BP_VE011_mslb_sam_CP; its box: its class's %(unnamed%)", n0) ~= nil,
    "a cruiser's and a picket's up lines")
local all = find("^fleet: Ctrl%+N: 15 of 15 ships up", n0)
check(all and all:find("with 48 parts at their course start %(GEOFON 30%.5 km from the runway, bearing 315 from it%); GEOFON 26%.5 km from "
    .. "you, bearing 348: fly there$") ~= nil, "the fleet up: " .. tostring(all))
check(callouts[#callouts] == "TEST: INVINCIBLE FLEET / 15 SHIPS 26 KM, BEARING 348", "its callout: " .. tostring(callouts[#callouts]))
runN(10)
local g1 = find("^fleet: %+%d+ s GEOFON: ", n0)
check(g1 and g1:find("^fleet: %+14 s GEOFON: %(%-5%.%d%d, %-25%.%d%d%) km, 30%.%d km from the runway, 26%.%d km from you, %d+ km/h heading 135, "
    .. "health 100 %%, 4 of 4 parts up$") ~= nil, "GEOFON's first 10 s line: " .. tostring(g1))
local r1 = find("^fleet: %+%d+ s RAVEN %(aegis%): ", n0)
check(r1 and r1:find("0%.60 km from GEOFON, 0 m off its spot, %d+ km/h heading 135, health 100 %%, 4 of 4 parts up$") ~= nil, "RAVEN's: " .. tostring(r1))
local k1 = find("^fleet: %+%d+ s KOLGA %(udal%): ", n0)
check(k1 and k1:find("off its spot, 0 km/h heading %-") ~= nil, "KOLGA not moving: " .. tostring(k1))
check(count("^fleet: %+%d+ s [%w]+ %(%a+%): ", n0) == 14 and find("^fleet: %+%d+ s weapons %(since the last line%): nothing; 0 of 48 parts fired", n0) ~= nil,
    "a line a ship, the weapons line")
runN(5)
check(find("^fleet: %+%d+ s GEOFON under way %(%d+ m from where it came up%)$", n0) ~= nil and SHIPS.Kolga.moving
    and find("^fleet: %+%d+ s KOLGA not under way 1%d s after its spawn %(0 m%): RE_SV_IFGoKolga fired %(1%)$", n0) ~= nil,
    "under way 15 s on; KOLGA not: its lane again (RE_SV_IFGoKolga)")
check(find("^fleet: %+%d+ s TAISCH not under way 1%d s after its spawn %(0 m%): RE_SV_IFGoTaisch fired %(error .*the event table isn't there%)$", n0) ~= nil
    and find("^fleet: %+%d+ s LAZULI under way", n0) ~= nil and find("^fleet: %+%d+ s PicketB under way", n0) ~= nil,
    "TAISCH's RE_SV_IFGo raising: said, and the ships after it still looked at (in a pcall)")
runN(15.25)
check(find("^fleet: %+%d+ s KOLGA under way %(%d+ m from where it came up%) after RE_SV_IFGoKolga$", n0) ~= nil, "KOLGA under way after it")
-- what fired: a launch by RAVEN's VLS (sv_weaponlog.lua's word), a shown shell of GEOFON's Mk 15, one by an object that isn't the
-- fleet's, and one by an address another object has now (hard rule 59)
n0 = #logs
IFLEET.onLaunch(SHIPS.Raven.parts[2].__addr, "BP_wp_vls_mk41")
IFLEET.onLaunch(SHIPS.Raven.parts[2].__addr, "BP_wp_vls_mk41")
IFLEET.onLaunch(0x7777, "BP_wp_msl")
SHIPS.Herne.parts[1].__name = "BP_SomethingElse_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_SomethingElse_C_9"
IFLEET.onLaunch(SHIPS.Herne.parts[1].__addr, "BP_wp_artillery")
local bl = obj("LiveBullet /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.LiveBullet_1", { bHidden = false, OwningGameObject = SHIPS.Geofon.parts[1] })
bullets[1] = bl
runN(10)
local wl = find("^fleet: %+%d+ s weapons", n0 + 1)
check(wl and wl:find("GEOFON BP_VE004_grfd_mk15_01_CP_Ally gun; RAVEN BP_VE002_aegs_mk41_CP BP_wp_vls_mk41 x2; 2 of 48 parts fired, you 2%d%.%d km from GEOFON$") ~= nil,
    "the weapons line: " .. tostring(wl))
bullets[1] = nil
-- sunk: a hull at 0, once
n0 = #logs + 1
SHIPS.Thiassi.hull.HealthInternal = 0
runN(1)
check(find("^fleet: %+%d+ s THIASSI sunk %(its hull at 0%); 3 of its 3 parts still up$", n0) ~= nil, "a hull at 0: sunk")
runN(10)
check(count("THIASSI sunk", n0) == 1 and count("^fleet: %+%d+ s THIASSI", n0) == 1, "once, and no more lines for it")
-- paused: no time passes
local tBefore = IFLEET.cur.t
PAUSED = true
runN(3)
check(IFLEET.cur.t == tBefore, "held while the game is paused")
PAUSED = false
-- the landing STORE open: no time passes, and Ctrl+N leaves the fleet as it is (the review's finding 4)
D.musicHold = 1
n0 = #logs
runN(3)
keys.N()
check(IFLEET.cur ~= nil and IFLEET.cur.t == tBefore and find("^fleet: Ctrl%+N in the STORE: refused %(its minigame holds the world's AI; the "
    .. "fleet stays as it is%)", n0) ~= nil and #SPC.cleanQ == 0, "held in the STORE, and Ctrl+N refused there (nothing taken off)")
D.musicHold = nil
-- again: taken off (RE_SV_IFFleetRemove, then SPC.cleanUp; never SV_Recycle(unit, 1) with things up: the review's finding 1)
n0 = #logs
local r0 = #fleetRecycles
local nCu = #cleanups
keys.N()
local off = find("^fleet: Ctrl%+N at %+%d+ s: the fleet taken off: ", n0)
check(off and off:find("15 units, RE_SV_IFFleetRemove 1; 61 of their 62 objects still up finished off or switched off %(each unit off the "
    .. "spawner's list from 2 s on%)$") ~= nil and #fleetRecycles == r0 and IFLEET.cur == nil and events[#events] == "RE_SV_IFFleetRemove",
    "Ctrl+N again: RE_SV_IFFleetRemove, then every object still up finished off, no SV_Recycle: " .. tostring(off))
check(#cleanups == nCu + 15 and cleanups[nCu + 1].unit == "SV_Unit_IFGeofon" and cleanups[nCu + 1].mortal == true and #SPC.cleanQ == 15,
    "each of the 15 units through SPC.cleanUp, its look queued")
check(SHIPS.Geofon.hull.killed and SHIPS.Geofon.parts[4].killed and SHIPS.Herne.parts[1].killed == nil and SHIPS.Herne.parts[2].killed,
    "finished off, but not an object whose address is another's now")
n0 = #logs
local nSp1 = #fleetSpawns
keys.N()
check(IFLEET.cur == nil and #fleetSpawns == nSp1 and find("^fleet: Ctrl%+N: the fleet before is still being taken off %(15 units: GEOFON, RAVEN, ", n0) ~= nil
    and callouts[#callouts] == "TEST: INVINCIBLE FLEET / STILL GOING: AGAIN IN A FEW SECONDS", "Ctrl+N while it's being taken off: refused")
cleanCheck()
-- mid-spawn: taken off with ships not spawned yet
keys.N()
runN(0.25)
n0 = #logs
keys.N()
check(find("^fleet: Ctrl%+N at %+%d+ s: the fleet taken off: 3 units %(12 not spawned yet dropped%), RE_SV_IFFleetRemove 1; 15 of their 15 objects", n0) ~= nil,
    "taken off mid-spawn (the ships not settled yet too)")
cleanCheck()
-- a ship still up from before that doesn't go: never spawned beside it, the fleet comes up without it
alive2.SV_Unit_IFPicketB, stuck.SV_Unit_IFPicketB = 2, true
nSp1 = #fleetSpawns
n0 = #logs
keys.N()
runN(4)
check(#fleetSpawns == nSp1 and find("^fleet: Ctrl%+N: 1 of the fleet's ships still up from before %(PicketB%)", n0) ~= nil, "held for it")
runN(4.25)
check(find("^fleet: %+8 s 1 ships still up 8 s after RE_SV_IFFleetRemove %(PicketB%): not spawned beside them, the fleet comes up without them$", n0) ~= nil,
    "still up 8 s on: dropped from this fleet")
runN(6)
local pbSpawned = false
for i = nSp1 + 1, #fleetSpawns do if fleetSpawns[i].unit == "SV_Unit_IFPicketB" then pbSpawned = true end end
check(#fleetSpawns == nSp1 + 14 and not pbSpawned and find("^fleet: Ctrl%+N: 14 of 15 ships up", n0) ~= nil and #fleetRecycles == r0,
    "the other 14 up, PicketB never spawned beside its leftover, nothing forced off the list")
keys.N()
cleanCheck()
alive2.SV_Unit_IFPicketB, stuck.SV_Unit_IFPicketB = 0, nil
-- the level torn down
keys.N()
LEVEL_DROPS["fleet ships"]("test")
check(IFLEET.cur == nil, "forgotten when the level goes")
-- a row missing at the main menu: no Ctrl+N fleet; a text the game refuses (SV_SetText raising): the rest set (finding 5)
IFLEET.setupDone, IFLEET.rowsOk = nil, nil
T.npc.rows, T.mine.rows.SV_IF_Kolga = {}, nil
T.mine.rows.SV_Fleet_Mk15Aegis = { NpcFCSId0 = fnameV("NPC_FCS_VesselCIWS000_SVA_Fleet") }
function SV_SetText(k, v) if k == "SV_FleetName_Raven" then error("no text table") end texts[k] = v; return 1 end
n0 = #logs
IFLEET.setup()
check(IFLEET.rowsOk == false and find("; 19 names and classes set; MISSING: SV_IF_Kolga: no Ctrl%+N fleet$", n0) ~= nil,
    "a row missing: said, and no fleet; a text refused: the other 19 set")
keys.N()
check(IFLEET.cur == nil and find("rows aren't in the game's tables %(the `fleet: rows at the main menu` line says which%)", n0) ~= nil, "Ctrl+N refused")

if fails > 0 then print("fleet test: " .. fails .. " FAILED"); os.exit(1) end
print("fleet test: all passed")
EOF
"$LUA" "$W/fleet_test.lua" "$SRC"
echo "a release's copy (strip_test_only.py)"
cp -r "$SRC/Scripts" "$SRC/config" "$W/stripped/"
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/stripped/Scripts/*.lua "$W"/stripped/config/survival.default.ini > /dev/null
if grep -n 'GEO = \|IFLEET\|testKey(\|CFG.specials.fleet = \|TEST_TICKS\|NotifyOnNewObject' "$W/stripped/Scripts/sv_fleet.lua"; then
    echo "  FAIL code of sv_fleet.lua left in a release's copy (above)"; exit 1
fi
if grep -n 'IFLEET' "$W"/stripped/Scripts/*.lua; then
    echo "  FAIL the Ctrl+N fleet's hooks left in a release's copy (sv_main.lua's setup, sv_weaponlog.lua's launches: above)"; exit 1
fi
echo "  ok   no IFLEET in any part of it (sv_main.lua's setup and sv_weaponlog.lua's hook are test-only too)"
if ! head -1 "$W/stripped/Scripts/sv_fleet.lua" | grep -q '^-- sv_fleet.lua'; then echo "  FAIL its header gone"; exit 1; fi
echo "  ok   sv_fleet.lua only its header ($(wc -l < "$W/stripped/Scripts/sv_fleet.lua") comment lines)"
if ! OUT=$(sh lua_load_test.sh "$W/stripped" 2>&1); then echo "$OUT"; echo "  FAIL the release copy doesn't load"; exit 1; fi
echo "  ok   $(echo "$OUT" | tail -1)"
echo "fleet test (release copy): all passed"
# (the review of 8ca3195, finding 2) a TESTER zip's copy: package_release.sh TESTER=1 keeps every test-only block but the
# dev install's parts, which tools/dev_only.py cuts to their headers (round 30's fleet and THE TANICORN: AGENTS.md)
echo "a TESTER zip's copy (tools/dev_only.py, as package_release.sh TESTER=1)"
mkdir -p "$W/tester"
cp -r "$SRC/Scripts" "$SRC/config" "$W/tester/"
if ! OUT=$(python -X utf8 -I "$HERE/../dev_only.py" "$W/tester" 2>&1); then echo "$OUT"; echo "  FAIL dev_only.py refused the copy"; exit 1; fi
if grep -n '^IFLEET = \|^GEO = \|^TANI = \|^CINE = \|testKey("N"\|testKey("B"\|testKey("T"\|testKey("D"' "$W"/tester/Scripts/*.lua; then
    echo "  FAIL the dev install's keys or globals left in a TESTER copy (above)"; exit 1
fi
echo "  ok   no IFLEET, GEO, TANI or CINE and none of their keys (Ctrl+N, B, T, D ...) in any part of it"
for p in sv_fleet sv_tanicorn sv_tanicorn_rise sv_tanicorn_hits sv_cine; do
    if grep -v '^--' "$W/tester/Scripts/$p.lua" | grep -q '[^[:space:]]'; then echo "  FAIL $p.lua: code left"; exit 1; fi
    # ((2026-11-12) a split part's first line is tools/lua_split_part.py's family note: its own name within the first three)
    if ! head -3 "$W/tester/Scripts/$p.lua" | grep -q "^-- $p.lua"; then echo "  FAIL $p.lua: its header gone"; exit 1; fi
done
echo "  ok   sv_fleet.lua, sv_tanicorn.lua, sv_tanicorn_rise.lua, sv_tanicorn_hits.lua and sv_cine.lua only their headers"
n=$(grep -c 'TEST ONLY BEGIN' "$W"/tester/Scripts/*.lua | awk -F: '{s+=$2} END {print s}')
if [ "$n" -lt 10 ] || ! grep -q 'testKey("F12"' "$W/tester/Scripts/sv_festival.lua"; then
    echo "  FAIL a tester's own test keys gone too ($n test blocks left)"; exit 1
fi
echo "  ok   every other test-only block kept for the tester ($n, the festival's Ctrl+F12 among them)"
if ! OUT=$(sh lua_load_test.sh "$W/tester" 2>&1); then echo "$OUT"; echo "  FAIL the TESTER copy doesn't load"; exit 1; fi
echo "  ok   $(echo "$OUT" | tail -1)"
# a part that defines one of them outside a test-only block: refused (the zip isn't made)
mkdir -p "$W/tester_bad"
cp -r "$SRC/Scripts" "$W/tester_bad/"
printf '\nIFLEET = {}\n' >> "$W/tester_bad/Scripts/sv_audit.lua"
if python -X utf8 -I "$HERE/../dev_only.py" "$W/tester_bad" > "$W/tester_bad.txt" 2>&1; then
    echo "  FAIL dev_only.py let IFLEET through outside the dev parts"; exit 1
fi
grep -q 'sv_audit.lua: IFLEET still defined' "$W/tester_bad.txt" || { cat "$W/tester_bad.txt"; echo "  FAIL its refusal doesn't say where"; exit 1; }
echo "  ok   a part defining IFLEET outside them: refused ($(grep -c 'still defined' "$W/tester_bad.txt") found)"
# ((2026-11-12) TESTER=1 TANI=1, the user's tester zip WITH THE TANACORN, passes --keep-tani (TANIZIP; zip_leak_test.sh tests
# that branch); every other TESTER zip runs it bare, its failure stopping the zip)
sed -n '/^if \[ "\$TESTER" = 1 \]; then/,/^else/p' "$HERE/../package_release.sh" \
    | grep -qxF '    python -X utf8 -I tools/dev_only.py ${TANIZIP:+--keep-tani} "$mod" || exit 1' \
    || { echo "  FAIL package_release.sh's TESTER branch doesn't run it"; exit 1; }
echo "  ok   package_release.sh's TESTER=1 runs it (--keep-tani only with TANI=1)"
echo "fleet test (TESTER copy): all passed"
