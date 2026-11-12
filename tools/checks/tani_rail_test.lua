-- tani_rail_test.lua <Scripts dir> (run by tools/checks/tani_rail_test.sh): THE TANACORN's Alicorn armaments in
-- Scripts/sv_tanicorn_rail.lua (2026-11-12, stage 4: docs/re/TANICORN.md "Railguns and railcannon"), her family's pieces
-- with the game stubbed, on Ctrl+L's live hull (sv_tanicorn.lua's watch, as the game's would make it):
--   the settings: CFG.specials.fleet.railcannon as sv_fleet.lua ships them (read in a sandbox);
--   the railguns: nothing written before after_s; the Deploy's end pose written in COMPONENT space (EBoneSpaces 1) as
--     quaternion transforms (no rotator), stepped over deploy_s (the lift -600 -> 0 cm, the hatches 105 deg about X at
--     (0, +-460, -30)); the lift read back after the last write and the order (RE_SV_TaniRailOrderL) fired only then, the
--     railgun HUD written first (hard rule 45: IsDispRadarMap, ForceAlertDisp, HUDControl 1, read back); held while the
--     STORE is open, fired once it shuts; a pose that doesn't take (written twice, still -600): never ordered; a barrel that
--     never moves: ordered again move_s on (hard rule 64), then "it took" once it moves; another object at a railgun's
--     address: a new record, and one whose lift can't be read: never ordered;
--   the railcannon: shielded at first sight (the four part flags, SetIsInvincible); Ctrl+H's refusals (outside a run, a
--     joiner, the STORE, no live hull, no Part_RAILCANNON, it down); Ctrl+H: its Deploy played as the VLS lids'; the
--     deploy's clock held while paused; the shield off at its end and its health sized in missiles (only lowered; x players);
--     a charge: one RE_SV_AlcnAlertOn, the callout, the radio, the discharge on SOC_Gun_01, the sounds and RTPC 50 -> 100,
--     the warning callout; held in the STORE and landed alone (not with another player flying); the shot (muzzle effects,
--     the beam's length), the impact's AF.bomb once (100 of 250, scaled to AF.max), RE_SV_AlcnAlertOff once after; the
--     next charge every_s after the last one started; none on the airfield down or on a joiner; every effect stopped after
--     its life (one whose address was reused left alone: hard rule 59); shot down mid-charge: the charge's sound stopped,
--     its effect off, the warning off, the callout, TANI.coreOpen, no impact; Ctrl+H again: stowed and shielded; a new run
--     and LEVEL_DROPS end or forget it; another object at its address: nothing done to it.
local DIR = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local LOG = {}
function log(s) LOG[#LOG + 1] = s end
local function logged(part, from)
    for i = from or 1, #LOG do if LOG[i]:find(part, 1, true) then return LOG[i], i end end
    return nil
end
local function count(part, from)
    local n = 0
    for i = from or 1, #LOG do if LOG[i]:find(part, 1, true) then n = n + 1 end end
    return n
end
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore
math.random = function() return 0.5 end           -- (the shot's spot on the runway: its centre)

-- the game's objects: tables with an address, a full name and IsValid (false once freed)
local nextA, LIVE = 0x1000, {}
local OBJ = {}
OBJ.__index = OBJ
function OBJ:GetAddress() return self.__addr end
function OBJ:GetFullName() return self.__name end
function OBJ:IsValid() return LIVE[self.__addr] == self end
function OBJ:K2_GetActorLocation() return { X = self.at.X, Y = self.at.Y, Z = self.at.Z } end
local function obj(name, t, addr)
    t = setmetatable(t or {}, OBJ)
    if not addr then nextA = nextA + 0x10; addr = nextA end
    t.__addr, t.__name, t.at = addr, name, t.at or { X = 0, Y = 0, Z = 0 }
    LIVE[addr] = t
    return t
end

-- sv_core's helpers, as they behave without the runtime's SV_ObjChain
function valid(o) local ok, v = pcall(function() return o ~= nil and o:IsValid() end); return ok and v end
function nameOf(o) local ok, s = pcall(function() return o:GetFullName() end); return ok and s or "?" end
function addrOf(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or nil end
function liveAddr(o) local a = addrOf(o); if not a or a == 0 then return nil end; return valid(o) and a or nil end
function liveObj(o) return o ~= nil and valid(o) end
function FName(s) return s end
function pin() return true end
local CALLOUTS = {}
function hudCallout(a, b) CALLOUTS[#CALLOUTS + 1] = tostring(a) .. " / " .. tostring(b); LOG[#LOG + 1] = "callout: " .. CALLOUTS[#CALLOUTS] end
function nativeReady() return true end
function playerLocationDirty() end
local ME = { X = 3600000, Y = -435747, Z = 300000 }       -- (20 km off the runway: no shake)
function playerLocation() return { X = ME.X, Y = ME.Y, Z = ME.Z } end
TEST_TICKS = {}
LEVEL_DROPS = {}
local KEYS = {}
function testKey(name, who, fn) KEYS[name] = fn; return true end
function NotifyOnNewObject() end
local FINDS = {}
function FindAllOf(c) return FINDS[c] end
function FindFirstOf() return nil end
local PAUSED, ONAF, OTHERS, LANDING = false, false, 0, false
function gamePaused() return PAUSED end
function playerOnAirfield() return ONAF end
function othersFlying() return OTHERS end
SV_ERR = { [-5] = "no runtime" }
local EVENTS = {}                                        -- every remote event fired: { ev, clock }
local SEQ = {}                                           -- the railguns' writes, reads and orders in order
function SV_Event(ev) EVENTS[#EVENTS + 1] = { ev = ev, at = clock }; SEQ[#SEQ + 1] = "event " .. ev; return 1 end
local function fired(ev, from)
    local n = 0
    for i = from or 1, #EVENTS do if EVENTS[i].ev == ev then n = n + 1 end end
    return n
end
local TOLD = {}
TELL = { ALL = -1, say = function(id) TOLD[#TOLD + 1] = id; return true end }

-- the data tables (sv_tanicorn.lua's rows at Ctrl+L)
local function table_(rows) return { rows = rows } end
function dtCall(dt, op, name, row)
    if op == "FindRow" then return true, dt.rows[name] end
    if op == "AddRow" then local c = {}; for k, v in pairs(row) do c[k] = v end; dt.rows[name] = c; return true end
    if op == "RemoveRow" then dt.rows[name] = nil; return true end
end
function cloneRow(dt, src, new, edit)
    local _, have = dtCall(dt, "FindRow", new)
    if have ~= nil then return true end
    local okS, srow = dtCall(dt, "FindRow", src)
    if not okS or srow == nil then return false, "no row " .. src end
    dtCall(dt, "AddRow", new, srow)
    local _, r = dtCall(dt, "FindRow", new)
    local ok, err = pcall(edit, r)
    if not ok then dtCall(dt, "RemoveRow", new); return false, tostring(err) end
    return true
end
PROBE_TABLES = { {}, { path = "/DT_NPC" } }
CFG = { specials = { shuttle = { npc_rows = "/DT_SV_NpcRows" } }, airfield = { enabled = true, hp = 250 } }
ACE = { model_table = "/DT_NPC_Model", model_rows = "/DT_SV_ModelRows" }
FCS_TABLE = "/DT_NPC_FCS"
local TABLES = { ["/DT_NPC"] = table_({}), ["/DT_SV_NpcRows"] = table_({}), ["/DT_NPC_Model"] = table_({}),
                 ["/DT_SV_ModelRows"] = table_({}),
                 ["/DT_NPC_FCS"] = table_({ NPC_FCS_VesselVLSmk41 = { SlotNum = 1, MagazineCapacity = 10 },
                                            NPC_FCS_FlakGun000 = { SlotNum = 1, MagazineCapacity = 10 },
                                            NPC_FCS_VesselArtillery000 = { SlotNum = 1, MagazineCapacity = 1 },
                                            NPC_FCS_VesselCIWS000 = { SlotNum = 1, MagazineCapacity = 1 } }),
                 ["/Game/Mods/SurvivalMode/Data/DT_SV_TaniFCS.DT_SV_TaniFCS"] = table_({ SV_FCS_TaniRail = { SlotNum = 1,
                     MagazineCapacity = 1, ReloadTime = 10 } }) }
local ASSETS = {}
function loadObject(path)
    if TABLES[path] then return TABLES[path] end
    if path:find("/Game/", 1, true) then
        ASSETS[path] = ASSETS[path] or obj(path, { GetPlayLength = function() return path:find("RAILCANNON_Deploy", 1, true) and 3.333 or 1 end })
        return ASSETS[path]
    end
    return nil, "not stubbed"
end
-- the engine's libraries: every effect, sound and RTPC recorded
local NIAG = { spawned = {} }
local function comp(sys, where, attach)
    local c = obj("NiagaraComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.NiagaraComponent_" .. nextA,
        { sys = sys, where = where, attach = attach, vars = {} })
    function c:Deactivate() self.off = true end
    function c:IsActive() return not self.off and not self.ended end
    function c:SetVariableFloat(n, v) self.vars[n] = v end
    function c:SetWorldScale3D(s) self.scale = s.X end
    NIAG.spawned[#NIAG.spawned + 1] = c
    return c
end
function NIAG:SpawnSystemAtLocation(_, sys, where, rot, sc) local c = comp(sys, where); c.rot, c.sc = rot, sc and sc.X; return c end
function NIAG:SpawnSystemAttached(sys, to, socket, loc, rot, locType)
    if NIAG.refuseSocket and socket ~= "None" then error("no such socket") end
    local c = comp(sys, nil, to); c.socket, c.locType = socket, locType; return c
end
local POSTS, AKPOSTS, RTPCS = {}, {}, {}
local SNDLIB = { PostEventAtActorByName = function(_, name, actor) POSTS[#POSTS + 1] = { name = name, actor = actor, at = clock }; return #POSTS end }
local AKLIB = { PostEventAtLocation = function(_, ev, where) AKPOSTS[#AKPOSTS + 1] = { ev = ev, where = where } end,
                SetRTPCValue = function(_, rt, v, ms, actor, name) RTPCS[#RTPCS + 1] = { v = v, ms = ms, actor = actor, name = name } end }
local function posted(name, actor, from)
    local n = 0
    for i = from or 1, #POSTS do if POSTS[i].name == name and (actor == nil or POSTS[i].actor == actor) then n = n + 1 end end
    return n
end
function StaticFindObject(path)
    if path == "/Script/Niagara.Default__NiagaraFunctionLibrary" then return setmetatable(NIAG, OBJ) end
    if path == "/Script/Live.Default__LiveSoundBlueprintLibrary" then return setmetatable(SNDLIB, OBJ) end
    if path == "/Script/AkAudio.Default__AkGameplayStatics" then return setmetatable(AKLIB, OBJ) end
    return nil
end
for _, l in ipairs({ NIAG, SNDLIB, AKLIB }) do nextA = nextA + 0x10; l.__addr, l.__name = nextA, "lib " .. nextA; LIVE[nextA] = l end
SPC = { V = { comps = function(o, cls) return (o.comps and o.comps[cls]) or {} end,
              PART_FLAGS = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true } },
        playerMissileDamage = function() return 80, "BP_plwp_msl_a0" end,
        -- (sv_rounds_shuttle.lua's: down at the airfield before this visit's STORE, on the rounds' clock)
        storeShut = function(now)
            if type(now) ~= "number" then error("SPC.storeShut wants the rounds' clock") end
            if LANDING then return false, "you're down at the airfield, your STORE not open yet" end
            return true, nil
        end }
local SHAKES = 0
local pawn = obj("pawn", { K2_GetActorRotation = function() return { Yaw = 0 } end })
survivalPC = obj("pc", { Pawn = pawn, ClientStartCameraShake = function() SHAKES = SHAKES + 1 end })
AF = { max = 250, full = 250, hp = 250, down = false, bomb = 0, bombBase = 0, pending = {} }

-- a railgun: its TurretPoseableMesh keeps what's written (unless stuck), its barrel turned by the test (yaw, pitch)
local function railgun(key, name, at, part)
    local pm = { writes = {}, bones = { lift = { X = 0, Y = 0, Z = -600 } }, yaw = 0, pitch = 10 }
    function pm:GetFName() return { ToString = function() return "TurretPoseableMesh" end } end
    function pm:GetFullName() return "PoseableMeshComponent /Game/Maps.BP_SV_Tani_" .. key .. "_C:TurretPoseableMesh" end
    function pm:SetBoneTransformByName(b, t, space)
        self.writes[#self.writes + 1] = { bone = b, t = t, space = space }
        SEQ[#SEQ + 1] = "write " .. key .. " " .. b
        if not self.stuck then self.bones[b] = { X = t.Translation.X, Y = t.Translation.Y, Z = t.Translation.Z } end
    end
    function pm:GetBoneLocationByName(b, space)
        SEQ[#SEQ + 1] = "read " .. key .. " " .. b
        if self.noRead then error("no such function") end
        local v = self.bones[b] or { X = 0, Y = 0, Z = 0 }
        return { X = v.X, Y = v.Y, Z = v.Z, space = space }
    end
    function pm:GetSocketTransform(s, space)                  -- (as drawn: sockLow, a pose written but never drawn)
        local lz = self.sockLow and -600 or self.bones.lift.Z
        return { Translation = { X = 875.6, Y = -0.5, Z = -196 + (lz + 600) }, space = space }
    end
    function pm:GetSocketLocation(s)
        local base = { X = at.X - 199, Y = at.Y, Z = at.Z + self.bones.lift.Z + 404 }
        if s ~= "SOC_Gun_01" then return base end
        local y, p = math.rad(self.yaw), math.rad(self.pitch)
        return { X = base.X + 1074 * math.cos(p) * math.cos(y), Y = base.Y + 1074 * math.cos(p) * math.sin(y), Z = base.Z + 1074 * math.sin(p) }
    end
    function pm:K2_GetComponentLocation() return { X = at.X, Y = at.Y, Z = at.Z } end
    local lmv = { HUDControl = 0, IsDispRadarMap = false, ForceAlertDisp = false }   -- (its writes in SEQ: before the order?)
    local lm = setmetatable({}, { __index = lmv, __newindex = function(_, f, v) lmv[f] = v; SEQ[#SEQ + 1] = "hud " .. key .. " " .. f end })
    function lm:GetClass() return { GetFName = function() return { ToString = function() return "LiveFCSModule_LauncherTripleRailCannon" end } end } end
    local root = { GetAttachParent = function() return { GetFName = function() return { ToString = function() return part end } end } end }
    local o = obj("BP_SV_Tani_" .. key .. "_C " .. name, { at = at, HealthInternal = 4000, MaxHealth = 400, RootComponent = root,
        comps = { ["/Script/Engine.PoseableMeshComponent"] = { pm } },
        FireControlSystemComponent = { AllArms = { { LauncherModule = lm } } } })
    o.pm, o.lm = pm, lm
    return o
end
-- the railcannon: its TurretMesh (a SkeletalMeshComponent) records what's played on it
local function railcannon(name, at, addr)
    local m = { calls = {}, pos = 0, rate = 1, playing = false }
    function m:GetFName() return { ToString = function() return "TurretMesh" end } end
    function m:GetFullName() return "SkeletalMeshComponent /Game/Maps.BP_SV_Tani_RAILCANNON_C:TurretMesh" end
    function m:SetAnimationMode(md, f) self.calls[#self.calls + 1] = "SetAnimationMode " .. md .. " " .. tostring(f) end
    function m:SetAnimation(a) self.calls[#self.calls + 1] = "SetAnimation " .. a.__name:match("[^/]+$") end
    function m:SetPosition(p) self.calls[#self.calls + 1] = "SetPosition " .. p; self.pos = p end
    function m:SetPlayRate(r) self.calls[#self.calls + 1] = "SetPlayRate " .. r; self.rate = r end
    function m:Play(l) self.calls[#self.calls + 1] = "Play " .. tostring(l); self.playing = true end
    function m:GetPosition() return self.pos end
    function m:IsPlaying() return self.playing end
    function m:GetSocketTransform() return { Translation = { X = 8165, Y = 0, Z = (self.playing and self.rate > 0) and 3454.4 or 1566.6 } } end
    function m:GetSocketLocation(s)
        if s == "railcannon_pitch" then return { X = at.X - 965, Y = at.Y, Z = at.Z + 1080 } end
        return { X = at.X + 9131, Y = at.Y, Z = at.Z + 1566 }   -- (her bow along +X: the runway lies along it below)
    end
    function m:K2_GetComponentLocation() return { X = at.X, Y = at.Y, Z = at.Z } end
    local o = obj("BP_SV_Tani_RAILCANNON_C " .. name, { at = at, HealthInternal = 10000, MaxHealth = 1000,
        bShowHUDBox = true, bIsNotLockonTarget = false, bIsNotFCSTargets = false, bIsInvincible = false,
        comps = { ["/Script/Engine.SkeletalMeshComponent"] = { m } } }, addr)
    function o:SetIsInvincible(v) self.inv = v end
    o.mesh = m
    return o
end
local function tick(dt)
    clock = clock + (dt or 0.25)
    for _, t in ipairs(TEST_TICKS) do t.fn(clock) end
end
local function ticks(n) for _ = 1, n do tick() end end
local function untilLog(part, max, from)                  -- ticks until a line is logged: its line, or nil
    for _ = 1, max do
        local l = logged(part, from)
        if l then return l end
        tick()
    end
    return logged(part, from)
end

print("sv_tanicorn_rail.lua's settings (sv_fleet.lua)")
local function sandbox()                                  -- sv_fleet.lua's CFG.specials.fleet, the rest of it stubbed
    local function stub()
        return setmetatable({}, { __index = function(t, k) local x = stub(); rawset(t, k, x); return x end,
                                  __call = function() return stub() end })
    end
    local env = { math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, type = type, tostring = tostring,
                  tonumber = tonumber, pcall = pcall, select = select, next = next, setmetatable = setmetatable, error = error,
                  assert = assert, os = os, rawget = rawget, rawset = rawset, getmetatable = getmetatable, CFG = { specials = {} } }
    setmetatable(env, { __index = function(t, k) local x = stub(); rawset(t, k, x); return x end })
    local f, err = loadfile(DIR .. "sv_fleet.lua", "t", env)
    if not f then return nil, err end
    local ok, e2 = pcall(f)
    if not ok then return nil, e2 end
    return env.CFG.specials.fleet
end
local FLEET, ferr = sandbox()
local RCC = FLEET and FLEET.railcannon
check(type(RCC) == "table", "sv_fleet.lua's CFG.specials.fleet.railcannon read (" .. tostring(ferr or "") .. ")")
RCC = RCC or {}
check(RCC.enabled == true and RCC.charge_s == 30 and RCC.every_s == 90 and RCC.damage == 100 and RCC.missiles == 8
    and RCC.per_player == 0.5 and RCC.damage_of_max == true and RCC.deploy_s == 3.4,
    "its values: charge 30 s, every 90 s, 100 of the airfield's 250, 8 missiles +50 % a player, deploy 3.4 s")
check(RCC.fx and RCC.fx.charge and RCC.fx.charge[1]:find("NS_alcn_RailCannonDischarge_ON", 1, true) and RCC.sound
    and RCC.sound.charge == "AKE_BA002_alcn_Cannon_Charge_Play" and RCC.sound.rtpc == "EX03_CANNON_CHARGE"
    and RCC.text and RCC.text.aim == "THE TANACORN IS AIMING AT THE AIRFIELD", "its effects, sounds and texts (the Alicorn's)")
local allAc8 = true
for _, l in ipairs({ RCC.fx and RCC.fx.muzzle or {}, RCC.fx and RCC.fx.impact or {} }) do
    for _, e in ipairs(l) do allAc8 = allAc8 and type(e[1]) == "string" and e[1]:find("^/Game/") ~= nil and not e[1]:find("/Mods/", 1, true) end
end
check(allAc8, "every effect AC8's own (no system of ours: hard rule 58)")
CFG.specials.fleet = { railcannon = RCC }

print("sv_tanicorn_rail.lua loaded with its family")
dofile(DIR .. "sv_tanicorn.lua")
dofile(DIR .. "sv_tanicorn_rise.lua")
dofile(DIR .. "sv_tanicorn_hits.lua")
dofile(DIR .. "sv_tanicorn_rail.lua")
check(KEYS.H ~= nil and type(TANI.rcStart) == "function" and type(TANI.rcLine) == "function" and type(TANI.rcFx) == "function"
    and type(TANI.railRow) == "function" and type(TANI.liveHull) == "function", "Ctrl+H bound; TANI.rcStart / rcLine / rcFx / railRow, TANI.liveHull")
check(type(LEVEL_DROPS["tanicorn rail"]) == "function", "LEVEL_DROPS[\"tanicorn rail\"] registered")
for _, k in ipairs({ TANI, TANI.hull, TANI.live, table.unpack(TANI.mounts) }) do
    TABLES["/DT_SV_ModelRows"].rows[k.model] = { MaxHealth = 1 }
    TABLES["/DT_SV_NpcRows"].rows[k.npc] = { ModelId = k.model }
end
for _, l in ipairs({ TANI.vls, TANI.rail }) do
    for _, k in ipairs(l) do
        TABLES["/DT_SV_ModelRows"].rows[k.model] = { MaxHealth = k.health }
        TABLES["/DT_SV_NpcRows"].rows[k.npc] = { ModelId = k.model }
    end
end
local CORE = {}
TANI.coreOpen = function(why) CORE[#CORE + 1] = why end

-- Ctrl+H refused outside a run, before any hull
local n0 = #LOG
KEYS.H()
check(logged("tanicorn rc: Ctrl+H refused: outside a Survival run", n0 + 1) ~= nil, "Ctrl+H outside a run: refused")
D = { now = 1 }
COOP = { client = function() return true end, players = function() return { {} } end }
n0 = #LOG
KEYS.H()
check(logged("Ctrl+H refused: the host's railcannon (you're a joiner)", n0 + 1) ~= nil, "Ctrl+H on a joiner: refused")
COOP.client = function() return false end
D.musicHold = 1
n0 = #LOG
KEYS.H()
check(logged("Ctrl+H refused: the STORE is open", n0 + 1) ~= nil, "Ctrl+H in the STORE: refused")
D.musicHold = nil
n0 = #LOG
KEYS.H()
check(logged("Ctrl+H refused: no live hull of ours up: Ctrl+L first", n0 + 1) ~= nil, "Ctrl+H with no live hull: refused (Ctrl+L first)")

-- Ctrl+L's live hull with (or without) its rail parts
local LIVECLS = TANI.live.class
local HULL, WITH_RC = nil, false
local function liveHull()
    local at = { X = 500000, Y = 0, Z = 0 }
    local parts = { RAILGUN_L = railgun("RAILGUN_L", "gunL_" .. nextA, { X = 480000, Y = -4000, Z = 1000 }, "Part_RAILGUN_L"),
                    RAILGUN_R = railgun("RAILGUN_R", "gunR_" .. nextA, { X = 480000, Y = 4000, Z = 1000 }, "Part_RAILGUN_R") }
    if WITH_RC then parts.RAILCANNON = railcannon("rc_" .. nextA, { X = 530000, Y = 0, Z = 1000 }) end
    local comps = {}
    for s, b in pairs(parts) do
        comps[#comps + 1] = { GetFName = function() return { ToString = function() return "Part_" .. s end } end, ChildActor = b, socket = s }
    end
    local mesh = { GetFName = function() return { ToString = function() return "HullMesh" end } end,
                   GetSocketLocation = function() return { X = 500000, Y = 0, Z = 700 } end }
    local h = obj(LIVECLS .. " /Game/Maps.hull_" .. nextA, { at = at, HealthInternal = 50000, MaxHealth = 5000,
        comps = { [TANI.live.comp_class] = comps, ["/Script/Engine.StaticMeshComponent"] = { mesh } } })
    function h:SetIsInvincible(v) self.inv = v end
    h.parts, h.pcomps = parts, comps
    FINDS[LIVECLS] = { h }
    HULL = h
    return h
end
function SV_Spawn(unit) if unit == TANI.live.unit then liveHull() end; return 1 end

print("a hull without its railcannon (a container cooked before it)")
KEYS.L()
tick()
check(HULL ~= nil and TANI.liveHull() == HULL, "Ctrl+L: the live hull up (TANI.liveHull)")
n0 = #LOG
KEYS.H()
check(logged("Ctrl+H refused: her live hull has no Part_RAILCANNON child", n0 + 1) ~= nil, "Ctrl+H with no Part_RAILCANNON: refused")
FINDS[LIVECLS] = {}
LIVE[HULL.__addr] = nil
for _, b in pairs(HULL.parts) do LIVE[b.__addr] = nil end
tick()

print("the railguns")
WITH_RC = true
SEQ, EVENTS = {}, {}
n0 = #LOG
KEYS.L()
tick()
local gL, gR, rc = HULL.parts.RAILGUN_L, HULL.parts.RAILGUN_R, HULL.parts.RAILCANNON
gR.pm.stuck = true                                       -- (its pose never takes)
check(logged("tanicorn rail: RAILGUN_L Part_RAILGUN_L ", n0 + 1) ~= nil and logged("seen: deploying in 3 s", n0 + 1) ~= nil,
    "each railgun seen with the live watch's armour (" .. tostring(logged("tanicorn rail: RAILGUN_L", n0 + 1)) .. ")")
ticks(10)
check(#gL.pm.writes == 0, "nothing written before after_s (3 s)")
D.musicHold = 1                                          -- (the STORE opens before its deploy ends: its order held)
ticks(3)
check(#gL.pm.writes > 0 and logged("tanicorn rail: RAILGUN_L deploying at +3.", n0 + 1) ~= nil
    and logged("lift z -600 cm, SOC_Gun_01 z -196 cm in the mesh", n0 + 1) ~= nil, "after_s on: deploying, its stowed pose read first")
local allCS, quats, lifts = true, true, {}
for _, w in ipairs(gL.pm.writes) do
    allCS = allCS and w.space == 1
    local r = w.t.Rotation
    quats = quats and r.W ~= nil and r.Pitch == nil and r.Yaw == nil and r.Roll == nil and w.t.Scale3D.X == 1
    if w.bone == "lift" then lifts[#lifts + 1] = w.t.Translation.Z end
end
untilLog("tanicorn rail: RAILGUN_L deployed", 20, n0 + 1)
for _, w in ipairs(gL.pm.writes) do
    allCS = allCS and w.space == 1
    local r = w.t.Rotation
    quats = quats and r.W ~= nil and r.Pitch == nil and r.Yaw == nil and r.Roll == nil
end
lifts = {}
for _, w in ipairs(gL.pm.writes) do if w.bone == "lift" then lifts[#lifts + 1] = w.t.Translation.Z end end
check(allCS, "every bone written in component space (EBoneSpaces 1)")
check(quats, "as quaternion transforms (Rotation { X, Y, Z, W }), never a rotator")
local mono, mid = #lifts >= 6, 0
for i = 2, #lifts do mono = mono and lifts[i] >= lifts[i - 1] end
for _, z in ipairs(lifts) do if z > -600 and z < 0 then mid = mid + 1 end end
check(mono and mid >= 3 and lifts[#lifts] == 0, "the lift stepped up over deploy_s, -600 -> 0 cm, after the hatches open ("
    .. #lifts .. " writes, " .. string.format("%.0f .. %.0f", lifts[1] or 0, lifts[#lifts] or 0) .. ")")
local hn, hp_
for _, w in ipairs(gL.pm.writes) do if w.bone == "Hatch_n" then hn = w end; if w.bone == "Hatch_p" then hp_ = w end end
check(hn and math.abs(hn.t.Rotation.X + 0.79335) < 1e-4 and math.abs(hn.t.Rotation.W - 0.60876) < 1e-4 and hn.t.Translation.Y == 460
    and hn.t.Translation.Z == -30 and hp_ and math.abs(hp_.t.Rotation.X - 0.79335) < 1e-4 and hp_.t.Translation.Y == -460,
    "the hatches' end pose: Hatch_n (-0.79335, 0, 0, 0.60876) at (0, 460, -30), Hatch_p (+0.79335, ...) at (0, -460, -30)")
local dl = logged("tanicorn rail: RAILGUN_L deployed: lift z 0 cm (up), SOC_Gun_01 z 404 cm in the mesh", n0 + 1)
check(dl ~= nil, "its lift read back up, SOC_Gun_01 raised (" .. tostring(dl or logged("RAILGUN_L deployed", n0 + 1)) .. ")")
check(fired("RE_SV_TaniRailOrderL") == 0 and logged("RAILGUN_L order held: the STORE is open", n0 + 1) ~= nil,
    "the STORE open: its order held (hard rule 64)")
D.musicHold = nil
PAUSED = true
tick()
check(fired("RE_SV_TaniRailOrderL") == 0 and logged("RAILGUN_L order held: the game paused (held through it)", n0 + 1) ~= nil,
    "the game paused: its order held (hard rule 60)")
PAUSED = false
tick()
local ol = logged("tanicorn rail: RAILGUN_L RE_SV_TaniRailOrderL fired (try 1, its deploy read back); railgun HUD "
    .. "LiveFCSModule_LauncherTripleRailCannon: written; read back IsDispRadarMap true, ForceAlertDisp true, HUDControl 1", n0 + 1)
check(fired("RE_SV_TaniRailOrderL") == 1 and ol ~= nil, "the STORE shut: ordered, its railgun HUD written and read back (" .. tostring(ol) .. ")")
check(gL.lm.IsDispRadarMap == true and gL.lm.ForceAlertDisp == true and gL.lm.HUDControl == 1, "hard rule 45's three fields on its arm")
local lastWrite, firstRead, firstOrder = 0, nil, nil
for i, s in ipairs(SEQ) do
    if s == "write RAILGUN_L lift" then lastWrite = i end
    if s == "event RE_SV_TaniRailOrderL" and not firstOrder then firstOrder = i end
end
for i = lastWrite + 1, #SEQ do if SEQ[i] == "read RAILGUN_L lift" and not firstRead then firstRead = i end end
check(firstOrder and firstRead and firstRead < firstOrder and lastWrite < firstRead, "the order only after the last write's read-back")
local hudAt
for i, s in ipairs(SEQ) do if s == "hud RAILGUN_L HUDControl" and not hudAt then hudAt = i end end
check(hudAt and firstOrder and hudAt < firstOrder, "its railgun HUD written BEFORE its order (hard rule 45)")
-- the stuck one: written twice, never ordered
ticks(2)
check(logged("tanicorn rail: RAILGUN_R its lift reads z -600 cm after its deploy: the end pose written again (2 of 2)", n0 + 1) ~= nil
    and logged("tanicorn rail: RAILGUN_R NOT ordered: its lift still reads z -600 cm after 2 writes", n0 + 1) ~= nil
    and fired("RE_SV_TaniRailOrderR") == 0, "a pose that doesn't take: written again, then NOT ordered (fail safe)")
-- hard rule 64: its barrel never moves, so its order again move_s on; then it moves
n0 = #LOG
ticks(33)
check(fired("RE_SV_TaniRailOrderL") == 2 and logged("RE_SV_TaniRailOrderL fired (try 2, again: its barrel still at yaw 0.0 pitch 10.0 8 s on)", n0 + 1) ~= nil,
    "its barrel still after move_s: ordered again (" .. tostring(logged("RE_SV_TaniRailOrderL fired (try 2", n0 + 1)) .. ")")
gL.pm.yaw, gL.pm.pitch = 40, 18
ticks(33)
check(logged("tanicorn rail: RAILGUN_L its barrel moves (yaw 0.0 -> 40.0, pitch 10.0 -> 18.0)", n0 + 1) ~= nil
    and fired("RE_SV_TaniRailOrderL") == 2, "its barrel moving: the order took, no more orders")
-- its lift falls back: written again
gL.pm.bones.lift.Z = -600
n0 = #LOG
ticks(21)
check(logged("tanicorn rail: RAILGUN_L its lift fell back to z -600 cm (1): the end pose written again", n0 + 1) ~= nil
    and gL.pm.bones.lift.Z == 0, "its lift read every check_s: fallen back, written again")
-- hard rule 59: another object at RAILGUN_R's address now (its lift can't be read): a new record, never ordered
local oldR = gR
local newR = railgun("RAILGUN_R", "someoneElse", { X = 480000, Y = 4000, Z = 1000 }, "Part_RAILGUN_R")
LIVE[newR.__addr] = nil
newR.__addr = oldR.__addr
LIVE[oldR.__addr] = newR
newR.pm.noRead = true
for _, c in ipairs(HULL.pcomps) do if c.socket == "RAILGUN_R" then c.ChildActor = newR end end
n0 = #LOG
ticks(2)
check(logged("tanicorn rail: RAILGUN_R gone (its actor no longer there): forgotten", n0 + 1) ~= nil and #newR.pm.writes == 0,
    "another object at its address: the record dropped, nothing written to the new one")
local nl = untilLog("tanicorn rail: RAILGUN_R Part_RAILGUN_R BP_SV_Tani_RAILGUN_R_C someoneElse seen", 40, n0 + 1)
check(nl ~= nil, "the new one seen once the live watch looks at it again (" .. tostring(nl) .. ")")
local cl = untilLog("tanicorn rail: RAILGUN_R NOT ordered: its lift can't be read back", 40, n0 + 1)
check(cl ~= nil and fired("RE_SV_TaniRailOrderR") == 0, "its lift unreadable: NOT ordered (no read-back, no order)")
-- its lift up as written but its muzzle still down as drawn (the gun would fire from inside the hull): written again, never ordered
local low = railgun("RAILGUN_R", "drawnLow", { X = 480000, Y = 4000, Z = 1000 }, "Part_RAILGUN_R")
LIVE[low.__addr] = nil
low.__addr = newR.__addr
LIVE[newR.__addr] = low
low.pm.sockLow = true
for _, c in ipairs(HULL.pcomps) do if c.socket == "RAILGUN_R" then c.ChildActor = low end end
n0 = #LOG
local ll = untilLog("tanicorn rail: RAILGUN_R NOT ordered: SOC_Gun_01 still z -196 cm in the mesh as drawn after 2 writes, its lift z 0 cm", 80, n0 + 1)
check(ll ~= nil and logged("tanicorn rail: RAILGUN_R its lift reads z 0 cm (up) but SOC_Gun_01 z -196 cm in the mesh as drawn after its "
    .. "deploy: the end pose written again (2 of 2)", n0 + 1) ~= nil and fired("RE_SV_TaniRailOrderR") == 0,
    "its lift up as written, its muzzle down as drawn: written again, then NOT ordered (" .. tostring(ll) .. ")")

print("the railcannon: its shield, Ctrl+H, its deploy")
local sl = logged("tanicorn rc: Part_RAILCANNON BP_SV_Tani_RAILCANNON_C rc_")
check(sl ~= nil and sl:find("seen: shielded while stowed (4 flags written, SetIsInvincible(true) called; read back bShowHUDBox false, "
    .. "bIsNotLockonTarget true, bIsNotFCSTargets true, bIsInvincible true)", 1, true) ~= nil and rc.inv == true,
    "shielded from the first tick it's seen (" .. tostring(sl) .. ")")
check(count("seen: shielded while stowed") == 1, "once")
rc.HealthInternal = 0
n0 = #LOG
KEYS.H()
check(logged("Ctrl+H refused: Part_RAILCANNON is down (health 0)", n0 + 1) ~= nil, "Ctrl+H with it down: refused")
rc.HealthInternal = 10000
local e0 = #EVENTS
n0 = #LOG
KEYS.H()
local hl = logged("tanicorn rc: Ctrl+H: deploying (AS_SV_Tani_RAILCANNON_Deploy 3.33 s on TurretMesh, from 0.00 s; SOC_Gun_01 z 1567 cm in the mesh)", n0 + 1)
check(hl ~= nil, "Ctrl+H: deploying (" .. tostring(logged("tanicorn rc: Ctrl+H", n0 + 1)) .. ")")
check(table.concat(rc.mesh.calls, ", ") == "SetAnimationMode 1 false, SetAnimation AS_SV_Tani_RAILCANNON_Deploy.AS_SV_Tani_RAILCANNON_Deploy, "
    .. "SetPosition 0, SetPlayRate 1, Play false", "its Deploy played as the VLS lids' (" .. table.concat(rc.mesh.calls, ", ") .. ")")
check(rc.inv == true and rc.bIsInvincible == true, "still shielded while it deploys")
PAUSED = true
ticks(4)
PAUSED = false
check(logged("tanicorn rc: the clock held at +0.", n0 + 1) ~= nil and logged("(the game paused)", n0 + 1) ~= nil
    and logged("tanicorn rc: deployed", n0 + 1) == nil, "its deploy's clock held while paused")
local t0 = clock
local dep = untilLog("tanicorn rc: deployed at +3.", 30, n0 + 1)
check(dep ~= nil and clock - t0 >= 3.4, "deployed at deploy_s of its own clock (" .. tostring(dep) .. ")")
check(dep and dep:find("position 0.00 of 3.33 s, SOC_Gun_01 z 3454 cm in the mesh (from 1567: +18.9 m", 1, true) ~= nil,
    "its muzzle risen ~19 m")
check(dep and dep:find("shield off (4 flags written, SetIsInvincible(false) called; read back bShowHUDBox true, bIsNotLockonTarget "
    .. "false, bIsNotFCSTargets false, bIsInvincible false)", 1, true) ~= nil and rc.inv == false, "its shield off, the flags as they were")
check(dep and dep:find("health set to 8.0 missiles (6400 HealthInternal: 80 x 10 x 8.0, players 1)", 1, true) ~= nil
    and rc.HealthInternal == 6400, "its health sized: 8 of your missiles (solo)")
check(logged("tanicorn rc: charge 1 at +", n0 + 1) == nil, "no charge in its deploy's tick (it waits for a tick nothing holds)")
tick()

print("the railcannon's charges")
local c1 = logged("tanicorn rc: charge 1 at +", n0 + 1)
check(c1 ~= nil and c1:find("(30 s): RAILGUN WARNING RE_SV_AlcnAlertOn fired; NS_alcn_RailCannonDischarge_ON up on SOC_Gun_01; "
    .. "RTPC_Init posted (id ", 1, true) ~= nil and c1:find("radio said", 1, true) ~= nil, "charge 1: its warning, effect, sound, radio (" .. tostring(c1) .. ")")
check(fired("RE_SV_AlcnAlertOn", e0 + 1) == 1 and TOLD[#TOLD] == "alcn_rail_first", "one RE_SV_AlcnAlertOn; the railgun's first radio line")
check(logged("callout: THE TANACORN IS AIMING AT THE AIRFIELD / RAILCANNON CHARGING: 30 S", n0 + 1) ~= nil, "its callout")
local chargeFx = NIAG.spawned[#NIAG.spawned]
check(chargeFx and chargeFx.attach == rc.mesh and chargeFx.socket == "SOC_Gun_01" and chargeFx.locType == 0
    and chargeFx.sys.__name:find("NS_alcn_RailCannonDischarge_ON", 1, true) ~= nil, "her discharge attached to TurretMesh's SOC_Gun_01")
check(posted("AKE_BA002_alcn_Cannon_RTPC_Init", rc) == 1 and posted("AKE_BA002_alcn_Cannon_Charge_Play", rc) == 0,
    "RTPC_Init posted on the railcannon, Charge_Play not yet")
-- the STORE holds its clock, and so does your landing with nobody else flying (not with another player up)
local tStart = clock
D.musicHold = 1
ticks(20)
D.musicHold = nil
ONAF = true
ticks(8)
OTHERS = 1
ticks(8)
ONAF, OTHERS = false, 0
check(logged("(the STORE open)", n0 + 1) ~= nil and logged("(you landed with nobody else flying)", n0 + 1) ~= nil,
    "the clock held in the STORE and landed alone")
local cp = untilLog("tanicorn rc: Charge_Play posted", 80, n0 + 1)
check(cp ~= nil and posted("AKE_BA002_alcn_Cannon_Charge_Play", rc) == 1, "Charge_Play posted on her (" .. tostring(cp) .. ")")
-- charge_s - charge_sound_s = 10 s of its clock; the holds: 5 s STORE + 2 s landed alone; landed with another flying: counted
check(clock - tStart >= 16.9 and clock - tStart <= 17.6, string.format("Charge_Play at +10 s of the charge's own clock (%.2f s of the "
    .. "wall's, 7 of them held)", clock - tStart))
local sh1 = untilLog("tanicorn rc: SHOT 1 at +", 100, n0 + 1)
check(sh1 ~= nil and sh1:find("-> runway (16.1, -4.4) km", 1, true) ~= nil and sh1:find("muzzle fx 2 of 2 up; streak beam 1 of 1 up; "
    .. "shot sound posted", 1, true) ~= nil, "its shot at the runway's centre (" .. tostring(sh1) .. ")")
check(logged("callout: RAILCANNON FIRING IN 10 S", n0 + 1) ~= nil, "the warning callout 10 s before")
check(chargeFx.off == true and posted("AKE_BA002_alcn_Cannon_Charge_End_Play", rc) == 1, "her discharge off at the shot, Charge_End posted")
local r1, rN = RTPCS[1], RTPCS[#RTPCS]
check(#RTPCS > 20 and r1.name == "EX03_CANNON_CHARGE" and r1.actor == rc and r1.v == 50 and rN.v == 100,
    string.format("the RTPC on her each tick, 50 -> 100 (%d sets)", #RTPCS))
local beam
for _, c in ipairs(NIAG.spawned) do if c.sys and c.sys.__name:find("NS_TLS_Muzzleflash01", 1, true) then beam = c end end
local mz = { X = 530000 + 9131, Y = 0, Z = 1000 + 1566 }     -- (its muzzle, the runway's centre: the shot's line)
local want = math.sqrt((1609574 - mz.X) ^ 2 + (-435747 - mz.Y) ^ 2 + (500 - mz.Z) ^ 2)
check(beam and beam.vars["User.BeamLength"] and math.abs(beam.vars["User.BeamLength"] - want) < 1,
    "the beam's User.BeamLength the shot's length (" .. tostring(beam and beam.vars["User.BeamLength"]) .. " cm)")
check(AF.bomb == 0, "no damage before the round lands")
local im1 = untilLog("tanicorn rc: impact 1 at +", 20, n0 + 1)
check(im1 ~= nil and im1:find(": -100 airfield (AF.bomb 0 -> 100; health before 250); impact fx 6 of 6 up, its sound posted, the shake "
    .. "none: you're", 1, true) ~= nil and AF.bomb == 100, "the impact: -100 on AF.bomb once (" .. tostring(im1) .. ")")
check(logged("callout: THE AIRFIELD IS HIT / TANACORN RAILCANNON: -100", n0 + 1) ~= nil, "its callout")
ticks(16)
check(fired("RE_SV_AlcnAlertOn", e0 + 1) == 1 and fired("RE_SV_AlcnAlertOff", e0 + 1) == 1, "one RAILGUN WARNING pair a charge")
-- every effect stopped after its life (fx_life_s 6), one whose address was reused left alone
local reused = NIAG.spawned[#NIAG.spawned]
reused.__name = "NiagaraComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.SomethingElse_9"
ticks(30)
local allOff, n = true, 0
for _, c in ipairs(NIAG.spawned) do if c ~= reused then n = n + 1; allOff = allOff and c.off == true end end
check(allOff and n >= 9 and not reused.off, string.format("all %d of its effects stopped after their life; a reused address left alone", n))
-- the next charge every_s after the last one started (its own clock)
local c2 = untilLog("tanicorn rc: charge 2 at +", 300, n0 + 1)
local s1 = tonumber(c1:match("charge 1 at %+([%d%.]+) s"))
local s2 = c2 and tonumber(c2:match("charge 2 at %+([%d%.]+) s"))
check(s2 and s1 and math.abs(s2 - s1 - 90) < 0.3, string.format("charge 2 at every_s after charge 1 started (+%s, +%s)", tostring(s1), tostring(s2)))
check(TOLD[#TOLD] == "alcn_rail", "its next radio line")
-- the airfield down when it lands: no damage
untilLog("tanicorn rc: SHOT 2", 200, n0 + 1)
AF.down = true
local im2 = untilLog("tanicorn rc: impact 2 at +", 20, n0 + 1)
check(im2 ~= nil and im2:find("the airfield is down: no damage", 1, true) ~= nil and AF.bomb == 100, "the airfield down: no damage")
AF.down = false
-- a joiner's game (the host gone, its railcannon's round landing here): no damage either
local c3 = untilLog("tanicorn rc: charge 3 at +", 400, n0 + 1)
untilLog("tanicorn rc: SHOT 3", 200, n0 + 1)
COOP.client = function() return true end
local im3 = untilLog("tanicorn rc: impact 3 at +", 20, n0 + 1)
COOP.client = function() return false end
check(c3 ~= nil and im3 ~= nil and im3:find("a joiner: the host's airfield takes it", 1, true) ~= nil and AF.bomb == 100,
    "on a joiner: the host's airfield, no damage here")
-- the airfield down holds the next charge's start (not the warning's end: off_after_s on the wall's clock)
AF.down = true
local eH = #EVENTS
n0 = #LOG
ticks(400)
check(logged("tanicorn rc: charge 4", n0 + 1) == nil and logged("(the airfield down)", n0 + 1) ~= nil, "the airfield down: no new charge")
check(fired("RE_SV_AlcnAlertOff", eH + 1) == 1 and fired("RE_SV_AlcnAlertOn", eH + 1) == 0, "its warning off all the same")
AF.down = false

print("the railcannon shot down mid-charge")
local e4 = #EVENTS
local c4 = untilLog("tanicorn rc: charge 4 at +", 400, n0 + 1)
ticks(40)
local cfx4 = NIAG.spawned[#NIAG.spawned]
local bomb0 = AF.bomb
rc.HealthInternal = 0
n0 = #LOG
tick()
local dl4 = logged("tanicorn rc: Part_RAILCANNON shot down at +", n0 + 1)
check(c4 ~= nil and dl4 ~= nil and dl4:find("(in its charge): its charge sound stopped, its charge effect off, RE_SV_AlcnAlertOff fired; "
    .. "no impact", 1, true) ~= nil, "shot down mid-charge: everything off (" .. tostring(dl4) .. ")")
check(posted("AKE_BA002_alcn_Cannon_Charge_Stop", rc) == 1 and cfx4.off == true and fired("RE_SV_AlcnAlertOff", e4 + 1) == 1,
    "Charge_Stop on her, her discharge off, the warning off")
check(logged("callout: TANACORN RAILCANNON DOWN / THE AIRFIELD IS SAFE", n0 + 1) ~= nil and CORE[#CORE] == "the railcannon down",
    "its callout; TANI.coreOpen called (stage 3's hook)")
check(logged("tanicorn rc: cycle over (shot down) at +", n0 + 1) ~= nil, "its cycle over")
ticks(200)
check(AF.bomb == bomb0 and logged("tanicorn rc: SHOT", n0 + 1) == nil and logged("tanicorn rc: impact", n0 + 1) == nil, "no shot, no impact after")

print("Ctrl+H again, a new run, the level dropped, a reused address")
rc.HealthInternal = 6400                                 -- (up again for the rest)
n0 = #LOG
KEYS.H()
ticks(20)
check(logged("tanicorn rc: deployed at +", n0 + 1) ~= nil and rc.inv == false, "Ctrl+H: deployed again")
local calls = #rc.mesh.calls
KEYS.H()
local ov = logged("tanicorn rc: cycle over (Ctrl+H again) at +", n0 + 1)
check(ov ~= nil and ov:find("RE_SV_AlcnAlertOff fired", 1, true) ~= nil and ov:find("stowed (its Deploy played back)", 1, true) ~= nil
    and ov:find("shielded again (4 flags written, SetIsInvincible(true) called", 1, true) ~= nil, "Ctrl+H again: stopped, stowed, shielded (" .. tostring(ov) .. ")")
check(rc.mesh.calls[calls + 1] == "SetPlayRate -1" and rc.mesh.calls[calls + 2] == "Play false" and rc.inv == true and rc.bShowHUDBox == false,
    "played back, its shield on again")
check(logged("callout: TEST: TANACORN RAILCANNON / STOWED", n0 + 1) ~= nil, "its callout")
-- a new run in the same level ends it (its warning off)
n0 = #LOG
KEYS.H()
untilLog("tanicorn rc: charge 1 at +", 30, n0 + 1)
local eN = #EVENTS
D = { now = 2 }
tick()
check(logged("tanicorn rc: cycle over (a new run)", n0 + 1) ~= nil and fired("RE_SV_AlcnAlertOff", eN + 1) == 1, "a new run: over, its warning off")
-- the level dropped: forgotten, nothing touched
n0 = #LOG
KEYS.H()
ticks(4)
local before = #rc.mesh.calls
local posts = #POSTS
LEVEL_DROPS["tanicorn rail"]()
check(TANI.rcLine(rc):find("not shielded yet", 1, true) ~= nil and #rc.mesh.calls == before and #POSTS == posts,
    "LEVEL_DROPS: the cycle and its shield forgotten, nothing touched (" .. TANI.rcLine(rc) .. ")")
-- another object at its address mid-charge: over, nothing done to the new one
ticks(2)
n0 = #LOG
KEYS.H()
untilLog("tanicorn rc: charge 1 at +", 30, n0 + 1)
local other = railcannon("intruder", { X = 0, Y = 0, Z = 0 }, rc.__addr)
other.bShowHUDBox, other.bIsInvincible = "untouched", "untouched"
posts = #POSTS
n0 = #LOG
local cores = #CORE
tick()
check(logged("tanicorn rc: Part_RAILCANNON gone with her hull up: taken as shot down at +", n0 + 1) ~= nil
    and logged("its charge sound left (its actor gone: nothing posted on it)", n0 + 1) ~= nil
    and logged("tanicorn rc: cycle over (shot down)", n0 + 1) ~= nil and #CORE == cores + 1
    and logged("callout: TANACORN RAILCANNON DOWN / THE AIRFIELD IS SAFE", n0 + 1) ~= nil,
    "gone with her hull up: shot down, as the Alicorn's parts (its callout, TANI.coreOpen)")
check(#other.mesh.calls == 0 and other.inv == nil and other.bShowHUDBox == "untouched"
    and posted("AKE_BA002_alcn_Cannon_Charge_Stop", nil, posts + 1) == 0, "nothing done to the object at its address now (hard rule 59)")
-- the socket refused: her discharge on the root at the muzzle's place
print("her discharge's fallback: the part's root")
rc = railcannon("rc2", { X = 530000, Y = 0, Z = 1000 })
rc.GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end
rc.GetActorRightVector = function() return { X = 0, Y = 1, Z = 0 } end
rc.GetActorUpVector = function() return { X = 0, Y = 0, Z = 1 } end
local root = { GetFName = function() return { ToString = function() return "root" end } end }
rc.K2_GetRootComponent = function() return root end
for _, c in ipairs(HULL.pcomps) do if c.socket == "RAILCANNON" then c.ChildActor = rc end end
NIAG.refuseSocket = true
COOP.players = function() return { {}, {}, {} } end    -- (three players: 16 missiles would be above its row's 1000)
n0 = #LOG
KEYS.L()                                                 -- (the hull up: looked at again, its parts seen again)
local s2 = untilLog("tanicorn rc: Part_RAILCANNON BP_SV_Tani_RAILCANNON_C rc2 seen: shielded while stowed", 8, n0 + 1)
check(s2 ~= nil and rc.inv == true, "a new railcannon object: shielded as it's seen")
KEYS.H()
local cr = untilLog("tanicorn rc: charge 1 at +", 30, n0 + 1)
local rfx = NIAG.spawned[#NIAG.spawned]
check(cr ~= nil and cr:find("NS_alcn_RailCannonDischarge_ON up on its root (SOC_Gun_01 refused", 1, true) ~= nil and rfx.attach == root
    and rfx.socket == "None", "SOC_Gun_01 refused: on its root (" .. tostring(cr) .. ")")
check(logged("health kept at 10000 HealthInternal (16.0 missiles of 80 would be 12800: only ever lowered, never above its row's)", n0 + 1) ~= nil
    and rc.HealthInternal == 10000, "three players: 16 missiles, capped at its row's")
NIAG.refuseSocket = nil

print("down at the airfield, a Deploy that doesn't show up, your missile's damage read late")
KEYS.H()                                                 -- (rc2's cycle stopped and stowed)
local rc3 = railcannon("rc3", { X = 530000, Y = 0, Z = 1000 })
for _, c in ipairs(HULL.pcomps) do if c.socket == "RAILCANNON" then c.ChildActor = rc3 end end
COOP.players = function() return { {} } end
n0 = #LOG
KEYS.L()
check(untilLog("tanicorn rc: Part_RAILCANNON BP_SV_Tani_RAILCANNON_C rc3 seen: shielded while stowed", 8, n0 + 1) ~= nil, "rc3 seen")
LANDING = true
KEYS.H()
check(logged("Ctrl+H refused: you're down at the airfield, your STORE not open yet (an event fired there runs nothing: hard rule 64)",
    n0 + 1) ~= nil, "Ctrl+H down at the airfield before its STORE: refused (the landing minigames, hard rule 64)")
LANDING = false
local play3 = rc3.mesh.Play
rc3.mesh.Play = function(self, l) self.calls[#self.calls + 1] = "Play " .. tostring(l) end   -- (its Deploy never plays)
local eA = #EVENTS
KEYS.H()
local np1 = untilLog("tanicorn rc: its Deploy not up at +3.4 s", 30, n0 + 1)
local np2 = untilLog("tanicorn rc: NOT deployed:", 30, n0 + 1)
check(np1 ~= nil and np1:find("SOC_Gun_01 z 1567 cm in the mesh (from 1567; raised: at least 2500): played again (1 of 1), "
    .. "still shielded", 1, true) ~= nil, "its Deploy not up: played again once (" .. tostring(np1) .. ")")
check(np2 ~= nil and np2:find("after 2 plays: kept shielded, no charge", 1, true) ~= nil and rc3.inv == true and rc3.bIsInvincible == true
    and fired("RE_SV_AlcnAlertOn", eA + 1) == 0 and logged("tanicorn rc: cycle over (its Deploy didn't take)", n0 + 1) ~= nil,
    "still not up: left shielded, no charge, no warning (" .. tostring(np2) .. ")")
rc3.mesh.Play = play3                                    -- (its own again: plays)
local reads = 0
local md = SPC.playerMissileDamage
SPC.playerMissileDamage = function() reads = reads + 1; if reads < 3 then return nil end return 80 end
n0 = #LOG
KEYS.H()
local dp3 = untilLog("tanicorn rc: deployed at +", 30, n0 + 1)
check(dp3 ~= nil and dp3:find("its health left at its row's (your missile's damage unread, try 1 of 5: again in 2 s): 10000", 1, true) ~= nil,
    "your missile's damage unread at its deploy: its row's health for now (" .. tostring(dp3) .. ")")
local hs3 = untilLog("tanicorn rc: health: health set to 8.0 missiles (6400 HealthInternal", 40, n0 + 1)
check(hs3 ~= nil and rc3.HealthInternal == 6400 and reads == 3, "read again every 2 s: sized at the third read (" .. tostring(hs3) .. ")")
SPC.playerMissileDamage = md
KEYS.H()
-- a torn level: forgotten
levelTorn = function() return true end
tick()
levelTorn = nil
check(TANI.rcLine(rc):find("not shielded yet", 1, true) ~= nil, "a torn level: forgotten")
if os.getenv("RAIL_LOG") then                             -- (RAIL_LOG=1: the part's own log lines, as a run would show them)
    for _, l in ipairs(LOG) do
        if l:find("tanicorn rail:", 1, true) or l:find("tanicorn rc:", 1, true) or l:find("SV_FCS_TaniRail", 1, true) then print("LOG " .. l) end
    end
end
print(fails == 0 and "tani rail test: all passed" or ("tani rail test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
