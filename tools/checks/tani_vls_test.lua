-- tani_vls_test.lua <Scripts dir> (run by tools/checks/tani_vls_test.sh): THE TANACORN's VLS blocks in Scripts/sv_tanicorn.lua
-- (2026-11-12, WP1's VLS route: docs/re/TANICORN.md "VLS"), the part alone with the game stubbed:
--   the types: TANI.vls (9: VLSD, VLSS_L1..R4), their names as survival_events.tani_vls makes them, two with units (Ctrl+K's),
--     every type a KINDS entry (TANI.live's 32 parts, each type's row health);
--   the rows: SV_FCS_TaniVLS cloned once from NPC_FCS_VesselVLSmk41 (SlotNum 8, the fcs_set fields, no turn speeds), each
--     type's model and DT_NPC row added;
--   Ctrl+K: refused outside a run and on a joiner; in one, the two test blocks spawned across your path, each turned so its
--     cells launch toward you (180 / 270 deg), the VLS watch on;
--   the watch: its first look only learns; a launch by a block (a pooled missile hidden -> shown, its OwningGameObject the
--     block) opens that block's lids (SetAnimationMode single node, SetAnimation, SetPosition 0, SetPlayRate 1, Play) and
--     logs the missile against its nearest cell; close_s after, they shut (SetPlayRate -1, Play); a stock ship's missile
--     changes nothing; a missile of an actor of ours that isn't a block (the hull) turns the range rule on, and a block with
--     you inside its reach opens; another object at a block's address (hard rule 59) is a new block, the old one untouched;
--     the watch's end shuts the lids and logs its counts; a torn level drops everything;
--   ((2026-11-12, the weapons runtime review) Ctrl+L's guard: the last live hull's parts kept when its actor goes (or a second
--     Ctrl+L replaces its watch); no new hull spawned while one of them lives (health above 0 or unreadable, still the object
--     kept: hard rule 59); a torn level forgets them.
local DIR = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local LOG = {}
function log(s) LOG[#LOG + 1] = s end
local function logged(part, from)
    for i = from or 1, #LOG do if LOG[i]:find(part, 1, true) then return LOG[i], i end end
    return nil
end
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's objects: tables with an address, a full name and IsValid (false once freed)
local nextA, LIVE = 0x1000, {}
local OBJ = {}
OBJ.__index = OBJ
function OBJ:GetAddress() return self.__addr end
function OBJ:GetFullName() return self.__name end
function OBJ:IsValid() return LIVE[self.__addr] == self end
function OBJ:K2_GetActorLocation() return { X = self.at.X, Y = self.at.Y, Z = self.at.Z } end
function OBJ:GetVelocity() return self.vel or { X = 0, Y = 0, Z = 0 } end
local function obj(name, t, addr)
    t = setmetatable(t or {}, OBJ)
    if not addr then nextA = nextA + 0x10; addr = nextA end
    t.__addr, t.__name, t.at = addr, name, t.at or { X = 0, Y = 0, Z = 0 }
    LIVE[addr] = t
    return t
end
local function free(o) if LIVE[o.__addr] == o then LIVE[o.__addr] = nil end end

-- sv_core's helpers, as they behave without the runtime's SV_ObjChain
function valid(o) local ok, v = pcall(function() return o ~= nil and o:IsValid() end); return ok and v end
function nameOf(o) local ok, s = pcall(function() return o:GetFullName() end); return ok and s or "?" end
function addrOf(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or nil end
function liveAddr(o) local a = addrOf(o); if not a or a == 0 then return nil end; return valid(o) and a or nil end
function liveObj(o) return o ~= nil and valid(o) end
function FName(s) return s end
function pin() return true end
function hudCallout(a, b) LOG[#LOG + 1] = "callout: " .. tostring(a) .. " / " .. tostring(b) end
function nativeReady() return true end
function playerLocationDirty() end
local ME = { X = 0, Y = 0, Z = 100000 }
function playerLocation() return { X = ME.X, Y = ME.Y, Z = ME.Z } end
TEST_TICKS = {}
LEVEL_DROPS = {}                                           -- (sv_core.lua's: what each part forgets with the level)
local KEYS = {}
function testKey(name, who, fn) KEYS[name] = fn; return true end
local NEW = {}
function NotifyOnNewObject(cls, fn) NEW[cls] = fn end
local FINDS = {}
function FindAllOf(c) return FINDS[c] end
function FindFirstOf() return nil end

-- the data tables: rows by name; dtCall / cloneRow as sv_rows.lua's
local function table_(rows) return { rows = rows } end
function dtCall(dt, op, name, row)
    if op == "FindRow" then return true, dt.rows[name] end
    if op == "AddRow" then local c = {}; for k, v in pairs(row) do c[k] = v end; dt.rows[name] = c; return true end
    if op == "RemoveRow" then dt.rows[name] = nil; return true end
end
local CLONES = {}
function cloneRow(dt, src, new, edit)
    local _, have = dtCall(dt, "FindRow", new)
    if have ~= nil then return true end
    CLONES[#CLONES + 1] = new
    local okS, srow = dtCall(dt, "FindRow", src)
    if not okS or srow == nil then return false, "no row " .. src end
    dtCall(dt, "AddRow", new, srow)
    local _, r = dtCall(dt, "FindRow", new)
    local ok, err = pcall(edit, r)
    if not ok then dtCall(dt, "RemoveRow", new); return false, tostring(err) end
    return true
end
PROBE_TABLES = { {}, { path = "/DT_NPC" } }
CFG = { specials = { shuttle = { npc_rows = "/DT_SV_NpcRows" } } }
ACE = { model_table = "/DT_NPC_Model", model_rows = "/DT_SV_ModelRows" }
FCS_TABLE = "/DT_NPC_FCS"
local TABLES = { ["/DT_NPC"] = table_({}), ["/DT_SV_NpcRows"] = table_({}), ["/DT_NPC_Model"] = table_({}),
                 ["/DT_SV_ModelRows"] = table_({}),
                 ["/DT_NPC_FCS"] = table_({ NPC_FCS_VesselVLSmk41 = { SlotNum = 1, MagazineCapacity = 10, CaptureDistance = 3000,
                                                                    TriggerCount = 1, ShotIntervalTime = 5, TriggeringTime = 5,
                                                                    RestingTime = 10 },
                                            NPC_FCS_FlakGun000 = { SlotNum = 1, MagazineCapacity = 10 },
                                            NPC_FCS_VesselArtillery000 = { SlotNum = 1, MagazineCapacity = 1 },
                                            NPC_FCS_VesselCIWS000 = { SlotNum = 1, MagazineCapacity = 1 } }) }
local ANIMS, CLASSES = {}, {}
function loadObject(path)
    if TABLES[path] then return TABLES[path] end
    if path:find("/Model/AS_SV_Tani_", 1, true) then
        ANIMS[path] = ANIMS[path] or obj(path, { GetPlayLength = function() return 0.5 end })
        return ANIMS[path]
    end
    if path:find("/BP_SV_Tani_", 1, true) then
        CLASSES[path] = CLASSES[path] or obj(path)
        return CLASSES[path]
    end
    if path:find("/NS_", 1, true) then                    -- ((2026-11-12) the rise's effects)
        CLASSES[path] = CLASSES[path] or obj(path)
        return CLASSES[path]
    end
    return nil, "not stubbed"
end
local NIAG = { spawned = {} }                              -- ((2026-11-12) the rise's effects: each component kept here)
function NIAG:SpawnSystemAtLocation(_, sys, where, _, sc)
    local c = obj("NiagaraComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.NiagaraComponent_" .. nextA)
    function c:Deactivate() self.off = true end
    self.spawned[#self.spawned + 1] = c
    return c
end
function StaticFindObject(path)
    if path == "/Script/Niagara.Default__NiagaraFunctionLibrary" then return setmetatable(NIAG, OBJ) end
    if path:find("Default__BP_SV_Tani_VLS", 1, true) then
        local mesh = { ToString = function() return "TurretMesh" end }
        return obj(path, { FireControlSystemComponent = { AllArms = { { LauncherModule = { MeshComponentName = mesh } } } },
                           DamagedStateComponent = obj("dmg") })
    end
    return nil
end
SPC = { V = { comps = function(o, cls) return (o.comps and o.comps[cls]) or {} end } }

-- a VLS block: its TurretMesh (a SkeletalMeshComponent) records what's played on it
local function block(cls, name, at, part)
    local mesh = { calls = {}, pos = 0, rate = 1, playing = false }
    function mesh:GetFName() return { ToString = function() return "TurretMesh" end } end
    function mesh:SetAnimationMode(m, f) self.calls[#self.calls + 1] = "SetAnimationMode " .. m .. " " .. tostring(f) end
    function mesh:SetAnimation(a) self.calls[#self.calls + 1] = "SetAnimation " .. a.__name:match("[^/]+$") end
    function mesh:SetPosition(p) self.calls[#self.calls + 1] = "SetPosition " .. p; self.pos = p end
    function mesh:SetPlayRate(r) self.calls[#self.calls + 1] = "SetPlayRate " .. r; self.rate = r end
    function mesh:Play(l) self.calls[#self.calls + 1] = "Play " .. tostring(l); self.playing = true end
    function mesh:GetPosition() return self.pos end
    function mesh:IsPlaying() return self.playing end
    function mesh:GetPlayRate() return self.rate end
    function mesh:GetSocketLocation(s)
        local i = tonumber(s:match("SOC_Vls_0(%d)")) or 1
        return { X = at.X + i * 100, Y = at.Y, Z = at.Z + 50 }
    end
    local cells = function(s) return type(s) == "string" and s:match("^SOC_Vls_0[1-8]$") ~= nil end
    function mesh:GetFullName() return "SkeletalMeshComponent /Game/Maps.BP_SV_Tani_" .. cls .. "_C:TurretMesh" end
    function mesh:DoesSocketExist(s) return cells(s) end
    function mesh:GetSocketBoneName(s) return { ToString = function() return cells(s) and "Body" or "None" end } end
    function mesh:K2_GetComponentLocation() return { X = at.X, Y = at.Y, Z = at.Z } end
    function mesh:GetAllSocketNames() return { "SOC_Vls_01", "SOC_Vls_02" } end
    mesh.SkinnedAsset = obj("SkeletalMesh /Game/Mods/SurvivalMode/Tanicorn/Model/SK_SV_Tani_" .. cls .. ".SK_SV_Tani_" .. cls,
        { NumSockets = function() return 8 end, FindSocket = function(_, s) return cells(s) and obj("socket " .. s) or nil end })
    local root = {}
    function root:GetAttachParent()
        if not part then error("no parent") end
        return { GetFName = function() return { ToString = function() return part end } end }
    end
    local o = obj("BP_SV_Tani_" .. cls .. "_C " .. name, { at = at, RootComponent = root,
        comps = { ["/Script/Engine.SkeletalMeshComponent"] = { mesh } } })
    o.mesh = mesh
    local c = "BP_SV_Tani_" .. cls .. "_C"
    FINDS[c] = FINDS[c] or {}
    table.insert(FINDS[c], o)
    return o
end
local function missile(owner, at)
    local m = obj("BP_wp_vls_a0_C /Game/Maps.BP_wp_vls_a0_C_" .. nextA, { bHidden = true, OwningGameObject = owner,
        at = at or { X = 0, Y = 0, Z = 0 }, vel = { X = 0, Y = 0, Z = 30000 } })
    FINDS.LiveVLSMissile = FINDS.LiveVLSMissile or {}
    table.insert(FINDS.LiveVLSMissile, m)
    if NEW["/Script/Live.LiveVLSMissile"] then NEW["/Script/Live.LiveVLSMissile"](m) end   -- (as the game makes it)
    return m
end
local function tick(dt)
    clock = clock + (dt or 0.25)
    for _, t in ipairs(TEST_TICKS) do t.fn(clock) end
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

print("sv_tanicorn.lua's VLS blocks")
dofile(DIR .. "sv_tanicorn.lua")
dofile(DIR .. "sv_tanicorn_hits.lua")              -- ((2026-11-12) the hit probe: its piece)

-- the types and their names
check(type(TANI.vls) == "table" and #TANI.vls == 9, "TANI.vls: 9 block types (" .. tostring(TANI.vls and #TANI.vls) .. ")")
local byKey = {}
for _, k in ipairs(TANI.vls or {}) do byKey[k.key] = k end
local D_, L1 = byKey.VLSD, byKey.VLSS_L1
check(D_ and D_.test and D_.unit == "SV_Unit_TaniVLSDeck" and D_.npc == "SV_Npc_TaniVLSDeck" and D_.model == "SV_Model_TaniVLSDeck"
    and D_.name_key == "SV_TaniVLSDeck_Name", "VLSD: its unit and rows (SV_*_TaniVLSDeck), a test block")
check(L1 and L1.test and L1.unit == "SV_Unit_TaniVLSSL1Side" and L1.class == "BP_SV_Tani_VLSS_L1_C"
    and L1.class_path == "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_VLSS_L1.BP_SV_Tani_VLSS_L1_C"
    and L1.anim == "/Game/Mods/SurvivalMode/Tanicorn/Model/AS_SV_Tani_VLSS_L1_Open.AS_SV_Tani_VLSS_L1_Open",
    "VLSS_L1: its unit, class and Open animation")
check(byKey.VLSS_R4 and not byKey.VLSS_R4.test and byKey.VLSS_R4.unit == nil and byKey.VLSS_R4.npc == "SV_Npc_TaniVLSSR4Side",
    "VLSS_R4: rows, no unit of its own")
local allFcs = true
for _, k in ipairs(TANI.vls or {}) do allFcs = allFcs and k.fcs == "SV_FCS_TaniVLS" and k.fcs_speed == nil and k.vls end
check(allFcs, "every type on SV_FCS_TaniVLS, no turn speeds")
check(#TANI.live.parts == 32 and TANI.live.parts[17][1] == "VLSD_1" and TANI.live.parts[32][2] == "VLSS_R4",
    "TANI.live: 32 parts, the VLS blocks last (" .. #TANI.live.parts .. ")")
check(TANI.live.row_health.VLSD == 200 and TANI.live.row_health.VLSS_R2 == 200 and TANI.live.row_health.T5 == 200
    and TANI.live.row_health.T16 == 400, "each VLS type's row health 200, the T5's 200, the T16's 400 (2026-11-12: x5)")
check(KEYS.K ~= nil and KEYS.L ~= nil, "Ctrl+K and Ctrl+L bound")
check(NEW["/Script/Live.LiveVLSMissile"] ~= nil, "the VLS missiles kept as the game makes them (NotifyOnNewObject)")

-- Ctrl+K refused outside a run and on a joiner
local n0 = #LOG
KEYS.K()
check(logged("Ctrl+K outside a Survival run", n0 + 1) ~= nil, "Ctrl+K outside a run: refused")
D = { now = 1 }
COOP = { client = function() return true end }
n0 = #LOG
KEYS.K()
check(logged("the host spawns them", n0 + 1) ~= nil, "Ctrl+K on a joiner: refused")
COOP = nil

-- in a run: the rows and the two test blocks (Survival's tables hold every TANI row, as the build makes them)
for _, k in ipairs({ TANI, TANI.hull, TANI.live, table.unpack(TANI.mounts) }) do
    TABLES["/DT_SV_ModelRows"].rows[k.model] = { MaxHealth = 1 }
    TABLES["/DT_SV_NpcRows"].rows[k.npc] = { ModelId = k.model }
end
for _, k in ipairs(TANI.vls) do
    TABLES["/DT_SV_ModelRows"].rows[k.model] = { MaxHealth = k.health }
    TABLES["/DT_SV_NpcRows"].rows[k.npc] = { ModelId = k.model }
end
local SPAWNS = {}
function SV_Spawn(unit, x, y, z, face) SPAWNS[#SPAWNS + 1] = { unit = unit, x = x, y = y, z = z, face = face }; return 1 end
local pawn = obj("pawn", { K2_GetActorRotation = function() return { Yaw = 30 } end })
survivalPC = obj("pc", { Pawn = pawn })
n0 = #LOG
KEYS.K()
local fcs = TABLES["/DT_NPC_FCS"].rows.SV_FCS_TaniVLS
local nV = 0
for _, c in ipairs(CLONES) do if c == "SV_FCS_TaniVLS" then nV = nV + 1 end end
check(nV == 1, "SV_FCS_TaniVLS cloned once for the 9 types (" .. nV .. ")")
check(fcs and fcs.SlotNum == 8 and fcs.MagazineCapacity == 8 and fcs.CaptureDistance == 7000 and fcs.TriggerCount == 4
    and fcs.ShotIntervalTime == 0.4 and fcs.TriggeringTime == 1.6 and fcs.RestingTime == 10 and fcs.ReloadTime == 15
    and fcs.YawSpeed == nil, "its row: SlotNum 8, 7 km, a ripple of 4 0.4 s apart, 10 s rest, 8 cells + 15 s reload, no turn speeds")
local fl = logged("fire control row SV_FCS_TaniVLS from NPC_FCS_VesselVLSmk41: in", n0 + 1)
check(fl ~= nil and fl:find("set CaptureDistance 7000", 1, true) ~= nil, "its line read back with the set fields")
local rowsLine = logged("the 9 VLS block types' rows: 9 in", n0 + 1)
check(rowsLine ~= nil, "every type's model and DT_NPC row added")
check(TABLES["/DT_NPC_Model"].rows.SV_Model_TaniVLSSR3Side ~= nil and TABLES["/DT_NPC"].rows.SV_Npc_TaniVLSDeck ~= nil,
    "the rows in the game's tables")
check(#SPAWNS == 2 and SPAWNS[1].unit == "SV_Unit_TaniVLSDeck" and SPAWNS[2].unit == "SV_Unit_TaniVLSSL1Side",
    "the two test blocks spawned")
check(SPAWNS[1] and math.abs(SPAWNS[1].face - 210) < 1e-6 and SPAWNS[2] and math.abs(SPAWNS[2].face - 300) < 1e-6,
    "VLSD turned 180 deg, VLSS_L1 270 deg from your heading (its cells' -Y toward you)")
check(SPAWNS[1] and SPAWNS[2] and math.abs(math.sqrt((SPAWNS[1].x - SPAWNS[2].x) ^ 2 + (SPAWNS[1].y - SPAWNS[2].y) ^ 2) - 40000) < 1,
    "400 m apart across your path")
check(logged("tanicorn: VLS watch on (Ctrl+K) for 180 s", n0 + 1) ~= nil, "the VLS watch on")

-- the watch: the blocks up, a pooled missile hidden at the first look
local bD = block("VLSD", "deck", { X = 300000, Y = 0, Z = 700 })
local bL = block("VLSS_L1", "side", { X = 300000, Y = 40000, Z = 700 })
local m1 = missile(bD, { X = 300100, Y = 0, Z = 760 })
n0 = #LOG
tick()
check(logged("tanicorn: VLS watch: 1 VLS missiles known, 0 shown now (not counted); 2 blocks of ours up", n0 + 1) ~= nil,
    "its first look learns the pool and the blocks")
check(#bD.mesh.calls == 0, "nothing played yet")
-- the deck block fires
m1.bHidden = false
n0 = #LOG
tick()
local op = logged("tanicorn: VLS " .. bD.__name:match("[^%.:]+$") .. " (VLSD) lids opening (its missile", n0 + 1)
check(op ~= nil and op:find("AS_SV_Tani_VLSD_Open 0.50 s on TurretMesh, from 0.00 s", 1, true) ~= nil,
    "a launch by the deck block opens its lids (" .. tostring(op) .. ")")
check(table.concat(bD.mesh.calls, ", ") == "SetAnimationMode 1 false, SetAnimation AS_SV_Tani_VLSD_Open.AS_SV_Tani_VLSD_Open, "
    .. "SetPosition 0, SetPlayRate 1, Play false", "played as the rise plays its rig (" .. table.concat(bD.mesh.calls, ", ") .. ")")
check(#bL.mesh.calls == 0, "the side block's lids untouched")
local ml = logged("tanicorn: VLSD missile 1 (", n0 + 1)
check(ml ~= nil and ml:find("its nearest cell SOC_Vls_01 0.1 m off", 1, true) ~= nil and ml:find("pitch 90.0 at 300 m/s", 1, true) ~= nil,
    "its missile logged against its nearest cell (" .. tostring(ml) .. ")")
-- shown again on the next look: no second launch
local calls = #bD.mesh.calls
tick()
check(#bD.mesh.calls == calls, "the same missile still flying: no second launch")
-- close_s after its last missile: shut
for _ = 1, 24 do tick() end
check(bD.mesh.calls[#bD.mesh.calls - 1] == "SetPlayRate -1" and bD.mesh.calls[#bD.mesh.calls] == "Play false",
    "6 s after its last missile its lids shut (played back)")
check(logged("lids shutting (6 s after its last missile)") ~= nil, "logged once")
-- the pool item hidden, then fired again by the same block: open again, not logged again
m1.bHidden = true
tick()
m1.bHidden = false
n0 = #LOG
tick()
check(bD.mesh.calls[#bD.mesh.calls - 1] == "SetPlayRate 1" and logged("lids opening", n0 + 1) == nil,
    "reused and fired again: opened again, its line not repeated")
-- a stock ship's missile: counted, nothing else
local ship = obj("BP_VE002_aegs_mk41_CP_C stock")
local m2 = missile(ship)
tick()
m2.bHidden = false
n0 = #LOG
tick()
check(logged("not one of our blocks", n0 + 1) == nil and #bL.mesh.calls == 0, "a stock ship's missile changes nothing")
-- one of the hull's (an actor of ours that isn't a block): the range rule on; the side block with you inside 7 km opens
local hull = obj("BP_SV_Tani_HULLLIVE_C hull")
local m3 = missile(hull)
tick()
ME.X, ME.Y, ME.Z = 300000, 400000, 700         -- (3.6 km from the side block, 4 km from the deck block)
m3.bHidden = false
n0 = #LOG
tick()
check(logged("launched by BP_SV_Tani_HULLLIVE_C hull: not one of our blocks", n0 + 1) ~= nil, "a hull's missile: can't be told apart")
check(logged("VLS " .. bL.__name:match("[^%.:]+$") .. " (VLSS_L1) lids opening (you within 3.6 km)", n0 + 1) ~= nil,
    "the side block with you inside its reach opens")
ME.X, ME.Y = -3000000, 0                        -- (you leave: 33 km off)
for _ = 1, 26 do tick() end
check(bL.mesh.calls[#bL.mesh.calls - 1] == "SetPlayRate -1", "you gone: it shuts close_s after")
check(logged("lids shutting (6 s after its last missile or you leaving its reach)") ~= nil, "logged with the range rule's reason")
-- hard rule 59: another object at the side block's address
free(bL)
FINDS.BP_SV_Tani_VLSS_L1_C = {}
local bL2 = block("VLSS_L1", "other", { X = -3000000, Y = 0, Z = 700 })   -- (where you are: inside its reach)
LIVE[bL2.__addr] = nil
bL2.__addr = bL.__addr
LIVE[bL.__addr] = bL2
local old = #bL.mesh.calls
for _ = 1, 10 do tick() end
check(#bL.mesh.calls == old and #bL2.mesh.calls > 0, "another object at its address: a new block (lids by its own name), the old one untouched")
-- the mount watch's lines for a block (Ctrl+K's 60 s): its first look's muzzle on SOC_Vls_01, its lids in place of a barrel
local up = logged("tanicorn: VLSD mount BP_SV_Tani_VLSD_C deck up at (300000, 0, 700): fire control arms")
check(up ~= nil, "the mount watch's first look at the deck block")
local mz = logged("tanicorn: VLSD muzzle: ")
check(mz ~= nil and mz:find("mesh TurretMesh", 1, true) ~= nil and mz:find("asset finds SOC_Vls_01 true", 1, true) ~= nil
    and mz:find("component has it true; its bone Body", 1, true) ~= nil and mz:find("at (+100, +0, +50) cm", 1, true) ~= nil,
    "its muzzle probe on SOC_Vls_01 of TurretMesh (" .. tostring(mz) .. ")")
local two = logged("tanicorn: VLSD BP_SV_Tani_VLSD_C deck hp ")
check(two ~= nil and two:find("lids at ", 1, true) ~= nil and two:find("SOC_Vls_01 (+100, +0, +50) from the block", 1, true) ~= nil
    and not two:find("barrel", 1, true), "its 2 s line: its lids, not a barrel (" .. tostring(two) .. ")")
check(logged("a stock turret's muzzle") == nil, "no stock turret probe for a VLS block")
check(logged("reading the barrel failed") == nil, "no barrel read on a block")
-- the watch's end
n0 = #LOG
for _ = 1, 800 do tick() end
local over = logged("tanicorn: VLS watch over (its 180 s are up): 2 launches by our blocks (VLSD 2), 1 by others, 1 not told apart", n0 + 1)
check(over ~= nil, "its end: its counts (" .. tostring(over or LOG[#LOG]) .. ")")
calls = #bD.mesh.calls
m1.bHidden = true; tick(); m1.bHidden = false; tick()
check(#bD.mesh.calls == calls, "after its end nothing more is played")
-- a torn level drops everything
KEYS.K()
levelTorn = function() return true end
tick()
levelTorn = nil
n0 = #LOG
tick()
check(logged("tanicorn: VLS watch", n0 + 1) == nil and logged("lids ", n0 + 1) == nil, "a torn level: the watch off, nothing kept")

-- ((2026-11-12, the weapons runtime review) Ctrl+L's guard: with no hull of ours up, no new one while a part of the last
-- lives (SV_Spawn's recycle would take its unit off the list under them: the 0.74.48 STORE crash's pattern))
print("Ctrl+L: the last live hull's parts kept past it")
local LIVECLS = TANI.live.class
local function livePart(socket)
    local b = block("VLSD", "live_" .. socket .. "_" .. nextA, { X = 500000, Y = 0, Z = 700 }, "Part_" .. socket)
    b.HealthInternal, b.MaxHealth = 400, 40
    -- (2026-11-12) AC8's native induced explosion on death, as our cooked parts keep it (TANI.armour defuses it)
    b.DamagedStateComponent = { InducedExplosionSystem = obj("LiveInducedExplosionSystemArrangement ies_" .. socket,
        { ExplosionRadius = 100, HitDistance = 20, bIsExplosionDamageParentOnly = false, damage = 100 }) }
    b.bCauseExplosionOnDeath, b.bIsInvincibleInducedExplosion = true, false
    return b
end
local HULLS = {}
local function liveHull()
    local parts = { VLSD_1 = livePart("VLSD_1"), VLSD_2 = livePart("VLSD_2") }
    local comps = {}
    for s, b in pairs(parts) do
        comps[#comps + 1] = { GetFName = function() return { ToString = function() return "Part_" .. s end } end, ChildActor = b }
    end
    local mesh = { GetFName = function() return { ToString = function() return "HullMesh" end } end,
                   GetSocketLocation = function() return { X = 500000, Y = 0, Z = 700 } end }
    local h = obj(LIVECLS .. " /Game/Maps.hull_" .. nextA, { at = { X = 500000, Y = 0, Z = 0 }, HealthInternal = 1000, MaxHealth = 100,
        comps = { [TANI.live.comp_class] = comps, ["/Script/Engine.StaticMeshComponent"] = { mesh } } })
    h.parts = parts
    h.bCanBeDamaged = true
    function h:SetIsInvincible(v) self.inv = v end
    FINDS[LIVECLS] = { h }
    HULLS[#HULLS + 1] = h
    return h
end
function SV_Spawn(unit, x, y, z, face)
    SPAWNS[#SPAWNS + 1] = { unit = unit }
    if unit == TANI.live.unit then liveHull() end
    return 1
end
local function hullSpawns() local n = 0; for _, s in ipairs(SPAWNS) do if s.unit == TANI.live.unit then n = n + 1 end end; return n end
local function sink(h) free(h); FINDS[LIVECLS] = {} end           -- (the hull's actor gone, its parts left as they are)
ME.X, ME.Y, ME.Z = 0, 0, 100000
-- a first hull, its parts seen at +2 s, then its actor gone with both parts still up
KEYS.L()
check(hullSpawns() == 1, "Ctrl+L with nothing up: spawned")
-- ((2026-11-12) her armour, TANI.armour: the hull and every part at the watch's first tick, before the +2 s look)
n0 = #LOG
tick()
local h1 = HULLS[1]
local a1, ies1 = h1.parts.VLSD_1, h1.parts.VLSD_1.DamagedStateComponent.InducedExplosionSystem
check(h1.inv == true and h1.bIsInvincible == true and h1.bCanBeDamaged == false and h1.bCauseExplosionOnDeath == false,
    "armour: her hull can't be damaged from the watch's first tick (SetIsInvincible, bCanBeDamaged false)")
local al = logged("tanicorn: armour (Ctrl+L): the hull ", n0 + 1)
check(al ~= nil and al:find("SetIsInvincible called; read back bIsInvincible true, bCanBeDamaged false", 1, true) ~= nil,
    "its line read back (" .. tostring(al) .. ")")
check(a1.bCauseExplosionOnDeath == false and a1.bIsInvincibleInducedExplosion == true and ies1.ExplosionRadius == 0
    and ies1.HitDistance == 0 and ies1.bIsExplosionDamageParentOnly == true and ies1.damage == 20
    and h1.parts.VLSD_2.DamagedStateComponent.InducedExplosionSystem.ExplosionRadius == 0,
    "armour: every part's death blast defused (no blast, immune to its neighbours', the Aegis turrets' values) before +2 s")
local pl = logged("tanicorn: armour: VLSD (Part_VLSD_", n0 + 1)
check(pl ~= nil and pl:find("4 written, read back ExplosionRadius 0, HitDistance 0, bIsExplosionDamageParentOnly true, damage 20", 1, true) ~= nil,
    "the first part of its type read back (" .. tostring(pl) .. ")")
check(logged("tanicorn hits: start +", n0 + 1) ~= nil and logged("HULL hull_", n0 + 1) ~= nil,
    "the hit probe starts on her hull")
for _ = 1, 9 do tick() end
check(logged("tanicorn: live +2 s: Part_VLSD_1 (VLSD): ") ~= nil, "its parts seen at +2 s")
local sl = logged("tanicorn hits: start +")
check(sl ~= nil and logged("tanicorn hits: start", select(2, logged("tanicorn hits: start +")) + 1) ~= nil,
    "the probe's start lines: the hull and the first part of a type")
-- a hit on a part: logged with its health, a DOWN at 0; the hull's health never moves
n0 = #LOG
h1.parts.VLSD_2.HealthInternal = 150
tick()
local hl = logged("tanicorn hits: +", n0 + 1)
check(hl ~= nil and hl:find("Part_VLSD_2 (VLSD) hp 400 -> 150/40 (-250); by", 1, true) ~= nil, "a hit on a part logged (" .. tostring(hl) .. ")")
h1.parts.VLSD_2.HealthInternal = 0
n0 = #LOG
tick()
check((logged("Part_VLSD_2 (VLSD) hp 150 -> 0/40 (-150) DOWN", n0 + 1)) ~= nil, "its DOWN line")
check(logged("HULL hull_", n0 + 1) == nil, "the hull's health never moved: no line")
h1.parts.VLSD_2.HealthInternal = 400                     -- (back up for the guard's checks below)
for _ = 1, 30 do tick() end
check(logged("tanicorn: armour: 2 of 32 parts at +") ~= nil, "armour: its count line once armour_s is up (2 of 32 here)")
sink(h1)
-- (the review of 2026-11-12) a press before the watch's tick has seen the hull go: the handler keeps the parts itself
n0 = #LOG
KEYS.L()
check(logged("Ctrl+L refused", n0 + 1) ~= nil and hullSpawns() == 1
    and logged("callout: TEST: TANACORN LIVE / HER PARTS STILL UP", n0 + 1) ~= nil,
    "Ctrl+L before the watch's tick saw the hull go: refused (the handler keeps the watch's parts itself)")
n0 = #LOG
tick()
check(logged("the hull is gone at +", n0 + 1) ~= nil and logged("2 of its parts still up as it goes", n0 + 1) ~= nil,
    "its hull gone: 2 parts still up, kept")
check(logged("tanicorn hits: +", n0 + 1) ~= nil and logged("GONE (its actor no longer there)", n0 + 1) ~= nil,
    "the probe: the hull GONE")
n0 = #LOG
KEYS.L()
local ref = logged("tanicorn: Ctrl+L refused: no live hull of ours up, but 2 part(s) of the last one still alive", n0 + 1)
check(ref ~= nil and ref:find("(Part_VLSD_1 (VLSD), Part_VLSD_2 (VLSD))", 1, true) ~= nil,
    "Ctrl+L refused, each live part named in order (" .. tostring(ref) .. ")")
check(hullSpawns() == 1 and logged("callout: TEST: TANACORN LIVE / HER PARTS STILL UP", n0 + 1) ~= nil, "nothing spawned; its callout")
-- one part down (health 0), the other's health unreadable: still up as far as Ctrl+L knows
h1.parts.VLSD_2.HealthInternal = 0
h1.parts.VLSD_1.HealthInternal = nil
n0 = #LOG
KEYS.L()
ref = logged("tanicorn: Ctrl+L refused: no live hull of ours up, but 1 part(s)", n0 + 1)
check(ref ~= nil and ref:find("Part_VLSD_1", 1, true) ~= nil and hullSpawns() == 1,
    "a part at health 0 no longer counts; one whose health can't be read still does (" .. tostring(ref) .. ")")
-- hard rule 59: another object at that part's address now: not the part, so nothing holds Ctrl+L. As in the game, the kept
-- wrapper stays valid at its address (SV_ObjChain answers for whatever lives there) and answers the new object's name, its
-- health unreadable (counted as up): only the name half of same() can tell it isn't the part (the review of 2026-11-12)
local p1 = h1.parts.VLSD_1
p1.__name = "BP_SV_Tani_VLSD_C /Game/Maps.someone_else"
n0 = #LOG
KEYS.L()
check(logged("Ctrl+L refused", n0 + 1) == nil and hullSpawns() == 2, "another object at the part's address: not counted, spawned")
-- a second Ctrl+L while the hull is up replaces the watch; the hull gone before the new watch's +2 s look: the replaced
-- watch's parts still hold Ctrl+L
for _ = 1, 10 do tick() end
n0 = #LOG
KEYS.L()
check(logged("a live hull already up", n0 + 1) ~= nil and hullSpawns() == 2, "Ctrl+L with the hull up: looked at again, no spawn")
if HULLS[2] then sink(HULLS[2]) end                      -- (none when a check above failed: the rest still runs)
n0 = #LOG
tick()
check(logged("2 of its parts still up as it goes", n0 + 1) ~= nil, "gone before the new watch saw its parts: the old watch's kept")
n0 = #LOG
KEYS.L()
check(logged("Ctrl+L refused", n0 + 1) ~= nil and hullSpawns() == 2, "Ctrl+L refused on them")
-- a torn level forgets them
levelTorn = function() return true end
tick()
levelTorn = nil
n0 = #LOG
KEYS.L()
check(logged("Ctrl+L refused", n0 + 1) == nil and hullSpawns() == 3, "a torn level forgets the kept parts: spawned")
-- ((2026-11-12, the review) TANI.armour.parts off: the run-time layer skipped, the parts as cooked, said so
print("Ctrl+L with TANI.armour.parts off")
tick()
for _, b in pairs(HULLS[3].parts) do b.HealthInternal = 0 end
sink(HULLS[3])
tick()
TANI.armour.parts = false
n0 = #LOG
KEYS.L()
tick()
local h4 = HULLS[4]
check(h4 ~= nil, "a new hull: the last one's parts were down")
local q = h4 and h4.parts.VLSD_1
check(q ~= nil and q.bCauseExplosionOnDeath == true and q.bIsInvincibleInducedExplosion == false
    and q.DamagedStateComponent.InducedExplosionSystem.ExplosionRadius == 100, "parts off: each part untouched (its blast as cooked)")
local ol = logged("tanicorn: armour: VLSD (Part_VLSD_", n0 + 1)
check(ol ~= nil and ol:find("OFF (TANI.armour.parts false: the run-time layer skipped", 1, true) ~= nil
    and ol:find("its induced explosion as cooked: ExplosionRadius 100, HitDistance 20", 1, true) ~= nil,
    "its OFF read-back with the blast as cooked (" .. tostring(ol) .. ")")
check(h4 ~= nil and h4.inv == true, "the hull's armour still on (TANI.armour.hull)")
for _ = 1, 24 do tick() end
check(logged("(OFF: the run-time layer skipped, the parts as cooked)", n0 + 1) ~= nil, "the OFF count line")
TANI.armour.parts = true

-- ((2026-11-12) TANI.armour on Ctrl+Y's drawn hull, at the key's own look; and the A/B switch: the hull as built, still probed)
print("Ctrl+Y: her drawn hull's armour")
local HCLS = TANI.hull.class
local DRAWN = {}
local spawnLive = SV_Spawn
function SV_Spawn(unit, x, y, z, face)
    if unit ~= TANI.hull.unit then return spawnLive(unit, x, y, z, face) end
    local d = obj(HCLS .. " /Game/Maps.drawn_" .. nextA, { at = { X = 0, Y = 500000, Z = 0 }, HealthInternal = 50000, MaxHealth = 5000,
        bCanBeDamaged = true })
    function d:SetIsInvincible(v) self.inv = v end
    FINDS[HCLS] = FINDS[HCLS] or {}
    table.insert(FINDS[HCLS], d)
    DRAWN[#DRAWN + 1] = d
    return 1
end
TANI.armour.hull = false
n0 = #LOG
KEYS.Y()
check(DRAWN[1] and DRAWN[1].inv == nil and DRAWN[1].bCanBeDamaged == true
    and logged("tanicorn: armour (Ctrl+Y): OFF for the hull drawn_", n0 + 1) ~= nil, "TANI.armour.hull false: the hull as built, said so")
tick()
check(logged("tanicorn hits: start +", n0 + 1) ~= nil and logged("HULL drawn_", n0 + 1) ~= nil, "the probe watches it all the same")
TANI.armour.hull = true
n0 = #LOG
KEYS.Y()
check(DRAWN[2] and DRAWN[2].inv == true and DRAWN[2].bCanBeDamaged == false and DRAWN[1].inv == nil
    and logged("tanicorn: armour (Ctrl+Y): the hull drawn_", n0 + 1) ~= nil,
    "Ctrl+Y: the new drawn hull can't be damaged at its key press; the first one left as it was (once each)")
tick()                                                    -- (the probe takes it up at its next tick)
n0 = #LOG
DRAWN[2].HealthInternal = 49000
tick()
check(logged("HULL drawn_", n0 + 1) ~= nil and logged("hp 50000 -> 49000/5000 (-1000)", n0 + 1) ~= nil,
    "a hull's health that moves is logged (with the armour on: never expected)")
-- ((2026-11-12) the user on 0.74.66: "the water height on the rise is too big now": a looping cutscene effect stood there
-- after the rise. Every rise effect is stopped fx_life_s after its spawn, by its own tick; a reused address left alone)
print("the rise's effects stopped")
NIAG.__addr, NIAG.__name = 0x9990, "NiagaraFunctionLibrary /Script/Niagara.Default__NiagaraFunctionLibrary"
LIVE[NIAG.__addr] = NIAG
check(TANI.rise.spawnFx("/Game/OnlineMode/VFX/IGC/X/NS_Test_Pillar", { X = 0, Y = 0, Z = 0 }, 1) == true
    and TANI.rise.spawnFx("/Game/OnlineMode/VFX/IGC/X/NS_Test_Mist", { X = 0, Y = 0, Z = 0 }, 1) == true, "two effects spawned")
local f1, f2 = NIAG.spawned[#NIAG.spawned - 1], NIAG.spawned[#NIAG.spawned]
f2.__name = "NiagaraComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.SomethingElse_7"   -- (its address reused)
for _ = 1, math.ceil(TANI.rise.fx_life_s / 0.25) - 2 do tick() end
check(not f1.off, "not before fx_life_s")
for _ = 1, 4 do tick() end
check(f1.off == true and not f2.off, "stopped fx_life_s after its spawn; another object at a kept address left alone (hard rule 59)")
check(type(LEVEL_DROPS["tanicorn rise fx"]) == "function", "forgotten with the level (LEVEL_DROPS)")

-- ((2026-11-12, the review) a new run in the same level closes the probe; each part's level drop forgets its own
print("the probe and the armour with the level")
n0 = #LOG
D = { now = 2 }
tick()
check(logged("tanicorn hits: over (a new run)", n0 + 1) ~= nil and logged("tanicorn hits: start +", n0 + 1) ~= nil,
    "a new run: the probe closed and started again on the hulls still up")
for _, k in ipairs({ "tanicorn hits", "tanicorn armour", "tanicorn live" }) do
    check(type(LEVEL_DROPS[k]) == "function", "LEVEL_DROPS[\"" .. k .. "\"] registered")
end
n0 = #LOG
LEVEL_DROPS["tanicorn hits"]()
check(logged("tanicorn hits: over (the level left)", n0 + 1) ~= nil, "the level's drop closes the probe")
LEVEL_DROPS["tanicorn armour"]()
check(#TANI.armoured == 0, "and forgets the armoured hulls")
LEVEL_DROPS["tanicorn live"]()
n0 = #LOG
tick()
check(logged("the hull is gone", n0 + 1) == nil and logged("tanicorn hits:", n0 + 1) == nil,
    "after the drops no stale watch or probe line")
print(fails == 0 and "tani vls test: all passed" or ("tani vls test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
