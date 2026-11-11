-- cine_test.lua <work dir> (run by tools/checks/cine_test.sh on a copy of the mod's Scripts and config): THE TANACORN's
-- rise cinematic and its director (Scripts/sv_cine.lua, docs/re/CINEMATIC.md) on the real sv_core, sv_config, sv_ai and
-- sv_hud (HUD.hold), the game stubbed (the player controller and its camera manager, the camera actors, GameplayStatics,
-- Niagara, the game's HUD actor, its widgets and its target boxes, THE TANACORN's hulls):
--   the file: missing -> today's camera (export_tanacorn.py RISE_CAM, fov 55), made only at the director's first use; a
--     hand-edited one read (comments, commas, out of order -> sorted, bad lines skipped and named, a line within 0.25 s of
--     another replacing it and named, roll and cut columns, the settings); text -> parse round trip; a save keeps the one
--     before as rise_camera.prev.txt and a hand edit since as rise_camera.edited.txt;
--   the keys: sorted by t, one within 0.25 s replaced; her frame: a key's spot in the world and back; the roll (a camera's
--     quaternion with roll, its up read back); the path: export_tanacorn.py's pchip, a camera every 0.5 s through the keys
--     (each key one), a cut starting a new run, at most 64 cameras;
--   the cinematic: a camera at each sample's spot turned onto its look point (the spawn's quaternion and the rotator
--     agree), its FOV; the view on camera 1 over 1 s from your plane (cubic), then linear blends with the outgoing camera
--     locked, each started before the view gets to its camera (never a hold), each ending at its camera's time (at her
--     rate, 0.5 too); a per-key blend (cubic); a cut (blend 0, the next blend unlocked) after a wait on the camera before;
--     the view given back when the game takes it (not while paused); Survival's HUD held, the game's widgets hidden (a
--     blueprint's template copy never touched), hidden again when the game shows them;
--   every stop path: CINE.stop, the rise over (R.back), the run's end (a new run), the level torn down (forgotten
--     untouched, the game's widgets put back next run if still as left), the level left (CINE.leave: the widgets back at
--     once, the view and cameras left; nothing once it's torn down), each with the view back, the HUD hold let go, the
--     game's HUD as it was, the cameras destroyed once the view is off them;
--   HUD.hold counted; the routes distortion (the HUD's blackout, renewed while held, ended), showhud (Survival's HUD and
--     the preview's callouts still up) and cheat; callouts on: the rows off, the banner and the subtitles kept;
--   the target boxes: her bShowHUDBox, every shown box hidden (the HUD's TargetContainerManager), hidden again when the
--     game shows one, a new one hidden, put back (a box that's a spare again left hidden), boxes = hers, by class;
--   the director: Ctrl+D on (markers at each key's spot every 2 s, a line a key), the rise tracked only, Ctrl+E in her
--     hold (0 s), at her time (place, look point 500 m along the view, roll, FOV; saved; the callout), replacing, after a
--     hand edit (the file read again first), on a freed rig (no call on it), with no rise (+1 s); the rise let go when
--     it's over; Ctrl+V a camera a press (the callouts still shown, the rest of the HUD off), ended by Ctrl+D, by Ctrl+E,
--     after 20 s, by a new plane (one at the old one's address too), refused while down; Ctrl+W a new take kept in its own file a later save never writes;
--     director mode off at a new run; the hulls looked for at most every 10 s, Ctrl+L's live hull too; the keys refused
--     outside a run and on a joiner.
local WORK = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
local function near(a, b, e) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (e or 1e-6) end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local CONF = WORK .. "/config/"
local function fileText(n) local f = io.open(CONF .. n, "rb"); if not f then return nil end; local s = f:read("a"); f:close(); return s end
local function writeText(n, s) assert(io.open(CONF .. n, "wb")):write(s):close() end
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's objects: live while LIVE[addr]
local LIVE, nextA = {}, 0x1000
local function obj(name, t)
    nextA = nextA + 0x10
    t = t or {}
    t.__addr, t.__name = nextA, name
    LIVE[nextA] = true
    return t
end
local function free(o) LIVE[o.__addr] = nil end

-- widgets: their visibility, render opacity and canvas children
local Wm = {}
local methods = {
    SetText = function(self, t) self.text = t end,
    SetVisibility = function(self, v) self.vis = v end,
    GetVisibility = function(self) return self.vis end,
    SetRenderOpacity = function(self, v) self.op = v end,
    GetRenderOpacity = function(self) return self.op or 1 end,
    AddChildToCanvas = function(self, w)
        self.kids = self.kids or {}
        self.kids[#self.kids + 1] = w
        return setmetatable({}, { __index = function() return function() end end })
    end,
    GetChildrenCount = function(self) return #(self.kids or {}) end,
    GetChildAt = function(self, i) return (self.kids or {})[i + 1] end,
    SetContent = function(self, w) self.kids = { w } end,
    GetDesiredSize = function() return { X = 100, Y = 40 } end,
}
local function noop() end
Wm.__index = function(_, k) return methods[k] or (type(k) == "string" and k:match("^%u") and noop) or nil end
local function widget(cls, name, vis) return setmetatable(obj(cls .. " " .. name, { vis = vis, Font = { OutlineSettings = {} } }), Wm) end

-- UE4SS
local binds = {}
function RegisterKeyBind(key, mods, fn) binds[#binds + 1] = { key = key, mods = mods, fn = fn } end
Key = { I = 73, O = 79 }
ModifierKey = { CONTROL = "CTRL" }
function ExecuteInGameThread(fn) fn() end
local FINDS, finds = {}, {}
function FindAllOf(c) finds[c] = (finds[c] or 0) + 1; return FINDS[c] end
function FindFirstOf() return nil end
function NotifyOnNewObject() end
function FName(s) return s end
function FText(s) return s end
local function tmap(m)                               -- (UE4SS's TMap: ForEach(key, value), each with :get())
    return { m = m, ForEach = function(self, fn)
        for k, v in pairs(self.m) do fn({ get = function() return k end }, { get = function() return v end }) end
    end }
end
local function tarray(l)                             -- (UE4SS's TArray: ForEach(index, element))
    return { l = l, ForEach = function(self, fn) for i, v in ipairs(self.l) do fn(i, { get = function() return v end }) end end }
end

-- the engine's statics: GameplayStatics (the camera actors), Niagara (the markers), the HUD's widget library
local cams, fxs = {}, {}
local function fwdOfRot(r)
    local p, y = math.rad(r.Pitch), math.rad(r.Yaw)
    return { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
end
local function fwdOfQuat(q)                    -- the quaternion's +X: what the spawn transform's Rotation turns it to
    return { X = 1 - 2 * (q.Y * q.Y + q.Z * q.Z), Y = 2 * (q.X * q.Y + q.W * q.Z), Z = 2 * (q.X * q.Z - q.W * q.Y) }
end
local function upOfQuat(q)                     -- ... and its +Z
    return { X = 2 * (q.X * q.Z + q.W * q.Y), Y = 2 * (q.Y * q.Z - q.W * q.X), Z = 1 - 2 * (q.X * q.X + q.Y * q.Y) }
end
local gs = obj("GameplayStatics /Script/Engine.Default__GameplayStatics")
gs.BeginDeferredActorSpawnFromClass = function(_, _, cls, t)
    local c = obj(string.format("CameraActor /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.CameraActor_%d", #cams + 1),
        { cls = cls, t = t, loc = t.Translation, CameraComponent = { bConstrainAspectRatio = true } })
    c.CameraComponent.SetFieldOfView = function(self, v) self.fov = v end
    c.K2_SetActorRotation = function(self, r) self.rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end
    c.GetActorForwardVector = function(self) return self.rot and fwdOfRot(self.rot) or fwdOfQuat(self.t.Rotation) end
    c.K2_GetActorLocation = function(self) return self.loc end
    c.K2_DestroyActor = function(self) self.destroyed = true; free(self) end
    cams[#cams + 1] = c
    return c
end
gs.FinishSpawningActor = function(_, a) a.finished = true end
local niag = obj("NiagaraFunctionLibrary /Script/Niagara.Default__NiagaraFunctionLibrary")
niag.SpawnSystemAtLocation = function(_, _, sys, where, _, sc)
    fxs[#fxs + 1] = { sys = sys, where = where, sc = sc.X, at = clock }
    return obj("NiagaraComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.NiagaraComponent_" .. #fxs)
end
local wbl = obj("WidgetBlueprintLibrary /Script/UMG.Default__WidgetBlueprintLibrary")
wbl.Create = function()
    return setmetatable(obj("WBP_HUD_NonGlowMessage_000_C /Engine/Transient.GameEngine_1:WBP_HUD_NonGlowMessage_000_C_9",
        { WidgetTree = { RootWidget = widget("CanvasPanel", "Root") }, vis = 0 }), Wm)
end
local STATICS = { ["/Script/Engine.Default__GameplayStatics"] = gs, ["/Script/Niagara.Default__NiagaraFunctionLibrary"] = niag,
                  ["/Script/UMG.Default__WidgetBlueprintLibrary"] = wbl,
                  ["/Script/Engine.CameraActor"] = obj("Class /Script/Engine.CameraActor") }
function StaticFindObject(p)
    if STATICS[p] then return STATICS[p] end
    local cls = p:match("^/Script/UMG%.(%w+)$")
    if cls then STATICS[p] = obj("Class " .. p, { cls = cls }); return STATICS[p] end
    return nil
end
function StaticConstructObject(c, _, name) return widget(c.cls, name, 0) end

-- the real parts
local PARTS = dofile("parts.lua")(WORK, readAll)
PARTS.load("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
local function find(pat, from) for i = from or 1, #logs do if logs[i]:find(pat) then return logs[i], i end end return nil end
local function count(pat, from) local n = 0; for i = from or 1, #logs do if logs[i]:find(pat) then n = n + 1 end end return n end
function valid(o) return type(o) == "table" and o.__addr ~= nil and LIVE[o.__addr] == true end
function liveAddr(o) return valid(o) and o.__addr or nil end
function liveObj(o) return valid(o) end
function addrOf(o) return type(o) == "table" and o.__addr or nil end
function nameOf(o) return valid(o) and o.__name or "?" end
local assets = {}
function loadObject(p) assets[p] = assets[p] or obj("Asset " .. p); return assets[p] end
function pin() end
PARTS.load("sv_config.lua"); PARTS.load("sv_ai.lua"); PARTS.load("sv_hud.lua")
LB, ALLY, TAC = { hud = function() end }, { hudLine = function() return nil end }, { line = function() return nil end }
COOP = { client = function() return false end }
local downNow = false
DOWN = { me = function() return downNow end }
function nativeReady() return true end
local PAUSED = false
function gamePaused() return PAUSED end

-- you: your plane, the controller (the view: SetViewTargetWithBlend / GetViewTarget), the camera manager
local pawn = obj("BP_PlayerPlane_PP1000_f16c_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PP_1",
    { loc = { X = 0, Y = 0, Z = 300000 } })
pawn.K2_GetActorLocation = function(self) return self.loc end
pawn.GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end
local pcm = obj("LivePlayerCameraManager /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PCM_0",
    { loc = { X = 0, Y = 0, Z = 300000 }, fwd = { X = 1, Y = 0, Z = 0 }, up = { X = 0, Y = 0, Z = 1 }, fov = 70 })
pcm.GetCameraLocation = function(self) return self.loc end
pcm.K2_GetActorLocation = function(self) return self.loc end
pcm.GetActorForwardVector = function(self) return self.fwd end
pcm.GetActorUpVector = function(self) return self.up end
pcm.GetFOVAngle = function(self) return self.fov end
local dists = {}                                     -- (the HUD's blackout: BeginHUDDistortion / EndHUDDistortion calls)
local hudA = obj("LiveMainHUDParent4K_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.LiveMainHUDParent4K_C_0", { bShowHUD = true })
hudA.BeginHUDDistortion = function(_, info) dists[#dists + 1] = { info = info, at = clock } end
hudA.EndHUDDistortion = function() dists[#dists + 1] = { ended = true, at = clock } end
local views = {}
local pc = obj("BP_LivePlayerController_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PC_0",
    { Pawn = pawn, PlayerCameraManager = pcm, vt = pawn })
pc.GetHUD = function() return hudA end
pc.SetViewTargetWithBlend = function(self, o, blend, fn, exp, lock)
    views[#views + 1] = { o = o, blend = blend, fn = fn, exp = exp, lock = lock, at = clock }
    self.vt = o
end
pc.GetViewTarget = function(self) return self.vt end
survivalPC = pc
local you = { X = 0, Y = 0, Z = 300000 }
function playerLocation() return you end

-- the game's HUD: the flight HUD (drawn into a render texture), its message layer, the HUD actor's glow root (and its
-- front root: the flight HUD again), a blueprint's template copy of the flight HUD (never on screen)
local TR = "/Engine/Transient.LiveGameEngine_1:BP_LiveGameInstance_C_1."
local mainFlight = widget("WBP_HUD_Chronicle_MainFlight_000_C", TR .. "WBP_HUD_Chronicle_MainFlight_000_C_7", 3)
local message = widget("WBP_HUD_SubWidgets_Message_000_C", TR .. "WBP_HUD_SubWidgets_Message_000_C_3", 4)
local glow = widget("UserWidget", TR .. "WBP_HUD_Glow_000_C_2", 3)
local template = widget("WBP_HUD_Chronicle_MainFlight_000_C", "/Game/Blueprints/UI/WBP/HUD4K/X.X_C:WidgetTree.MainFlight", 3)
hudA.GlowWidgetPtr, hudA.NonGlowFrontWidgetPtr = glow, mainFlight
FINDS["WBP_HUD_Chronicle_MainFlight_000_C"] = { template, mainFlight }
FINDS["WBP_HUD_SubWidgets_Message_000_C"] = { message }

-- THE TANACORN: her hull facing +Y (yaw 90: her starboard is -X), 5 km east, 2 km north; her box on
local hull = obj("BP_SV_Tani_HULL_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_SV_Tani_HULL_C_1",
    { loc = { X = 500000, Y = 200000, Z = 0 }, bShowHUDBox = true })
hull.K2_GetActorLocation = function(self) return self.loc end
hull.GetActorForwardVector = function() return { X = 0, Y = 1, Z = 0 } end
local hullCdo = obj("BP_SV_Tani_HULL_C /Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_HULL.Default__BP_SV_Tani_HULL_C")
FINDS["BP_SV_Tani_HULL_C"] = { hull, hullCdo }
TANI = { hull = { class = "BP_SV_Tani_HULL_C" }, live = { class = "BP_SV_Tani_HULLLIVE_C" }, rise = { rate = 1.0, hold_s = 1.5 } }

-- a run
local function newRun() D = { round = 5, state = "fighting", now = 100, at = 130 }; RUN = { credits = 1000, items = {}, kills = {} } end
newRun()
H, hudTries, hudOff, callouts = nil, 0, false, {}
local said = {}                                  -- (every callout asked for: the HUD queues 4 at most)
do
    local real = hudCallout
    function hudCallout(a, b, c) said[#said + 1] = { text = a, sub = b }; return real(a, b, c) end
end
local keys = {}
function testKey(name, who, fn) keys[name] = fn; return true end
TEST_TICKS = {}
PARTS.load("sv_cine.lua", "@" .. WORK .. "/Scripts/sv_cine.lua")
local cineTick
for _, t in ipairs(TEST_TICKS) do if t.name == "cine" then cineTick = t.fn end end
local S, C, GH = CINE.S, CINE.cfg, CINE.GH
local riseT = nil                                 -- (her clock: nil before she plays)
local rate = 1
local function tick0() D.now = clock; cineTick(clock); hudTick(clock, PAUSED, pc) end   -- (a tick now: her clock as it is)
local function tick(dt)                           -- the tick every 250 ms (her clock at `rate` while she plays)
    local t1 = clock + (dt or 0.25)
    repeat
        clock = clock + 0.25
        if riseT then riseT = riseT + 0.25 * rate end
        D.now = clock
        cineTick(clock)
        hudTick(clock, PAUSED, pc)
    until clock >= t1 - 1e-9
end
local rig = obj("SkeletalMeshComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_SV_Tani_HULL_C_1.RiseRig")
local function hullR() return { o = hull, name = nameOf(hull), rig = rig, x = 500000, y = 200000, z = 0 } end
local hooks = { clock = function() return riseT end, rate = function() return rate end }
local function setFile(over)                      -- today's camera's file, its settings changed
    local t = CINE.text(CINE.DEFAULTS)
    for k, v in pairs(over or {}) do t = t:gsub("\n" .. k .. " = [^\n]*", "\n" .. k .. " = " .. v) end
    writeText(C.file, t)
end
local function viewsFrom(v0) local l = {}; for i = v0 + 1, #views do l[#l + 1] = views[i] end; return l end

---------------------------------------------------------------------------------------------------- the file
print("the file")
check(type(cineTick) == "function" and type(keys.D) == "function" and type(keys.E) == "function" and type(keys.V) == "function"
    and type(keys.W) == "function" and type(LEVEL_DROPS.cine) == "function" and type(CINE.leave) == "function",
    "its tick, Ctrl+D / E / V / W, its level drop and CINE.leave")
local mk = find("^cine: keys %(loaded%)")
check(mk ~= nil and has(mk, "today's camera (the file missing), made at the director's first use; at 0, 5, 9, 15 s")
    and has(mk, "director speed 0.35, blend smooth, enter 1 s, callouts on, boxes hide")
    and has(mk, "the game's HUD by distortion, widgets, cheat, showhud"), "missing: today's camera: " .. tostring(mk))
check(fileText(C.file) == nil, "the file not made at start (a TESTER zip's config untouched until the director is used)")
CINE.load("test", true)
local K = CINE.keys
check(#K == 4 and K[1].t == 0 and K[1].at[1] == 700 and K[1].at[2] == -650 and K[1].at[3] == 12 and K[1].look[1] == 300
    and K[1].look[3] == 40 and K[4].t == 15 and K[4].at[2] == -720 and K[4].look[1] == 40 and K[2].fov == 55,
    "the defaults: RISE_CAM (t, place, look point; UE's y as starboard), fov 55")
local made = fileText(C.file)
check(has(made, "director_speed = 0.35\nblend = smooth\nenter_blend = 1\ncallouts = on\nboxes = hide\nhud = distortion widgets cheat showhud\n")
    and has(made, "\n0        700      -650     12       300      0        40       55\n")
    and has(made, "\n15       600      -720     18       40       0        10       55\n"), "made at the first use: its settings and a key a line")
do
    local k2, set2, bad2 = CINE.parse(CINE.text(CINE.DEFAULTS))
    local same = #k2 == 4
    for i = 1, 4 do
        local a, b = k2[i], CINE.DEFAULTS[i]
        same = same and a.t == b.t and a.fov == b.fov and a.roll == nil and a.cut == nil
        for j = 1, 3 do same = same and a.at[j] == b.at[j] and a.look[j] == b.look[j] end
    end
    check(same and #bad2 == 0 and set2.blend == "smooth" and #set2.hud == 4 and set2.callouts == true and set2.boxes == "hide",
        "text -> parse: the same keys and settings")
end
local edited = table.concat({
    "; a note", "director_speed = 0.5", "blend = Ease_In_Out", "hud = showhud", "callouts = off", "boxes = hers", "enter_blend = 0",
    "9, 640, -700, 16, 80, 0, 15, 40   ; commas, a note after it",
    "2.5 100 -300 20 0 0 30 60",
    "1 2 3",                                  -- (line 10: 3 values)
    "4 1 1 1 1 1 1 200",                      -- (line 11: fov)
    "speed = 3",                              -- (line 12: no such setting)
    "  # a hash note",
    "0 700 -650 12 300 0 40 55",
}, "\n")
writeText(C.file, edited)
local n0 = #logs
CINE.load("test")
K = CINE.keys
check(#K == 3 and K[1].t == 0 and K[2].t == 2.5 and K[3].t == 9 and K[3].fov == 40 and K[2].at[2] == -300,
    "a hand-edited file: comments, commas, out of order -> sorted (0, 2.5, 9)")
check(has(find("line 10 skipped", n0), "3 values, not 8") and has(find("line 11 skipped", n0), "fov must be 5 to 170")
    and has(find("line 12 skipped", n0), "no setting speed"), "its bad lines skipped, each named by its line")
check(S.set.director_speed == 0.5 and S.set.blend == "easeinout" and #S.set.hud == 1 and S.set.hud[1] == "showhud"
    and S.set.callouts == false and S.set.boxes == "hers" and S.set.enter_blend == 0 and CINE.director() == nil,
    "its settings: director_speed, blend (any case, _ ignored), hud, callouts, boxes, enter_blend")
do
    local k3, _, bad3 = CINE.parse("5 1 1 1 2 2 2 50\n5.1 1 1 1 2 2 2 50 -15 CUT\n6 1 1 1 2 2 2 50 200\n7 1 1 1 2 2 2 50 cut\n")
    check(#k3 == 2 and k3[1].t == 5.1 and k3[1].roll == -15 and k3[1].cut == true and k3[2].t == 7 and k3[2].roll == nil
        and k3[2].cut == true, "a 9th column the roll, a last word cut")
    check(#bad3 == 2 and bad3[1].line == 2 and bad3[1].replaces == 1 and has(bad3[1].why, "replaces line 1 (within 0.25 s of it)")
        and bad3[2].line == 3 and has(bad3[2].why, "roll must be -180 to 180"), "a line within 0.25 s of another replaces it, named")
    local t3 = CINE.text(k3)
    check(has(t3, "\n5.1      1        1        1        2        2        2        50       -15      cut\n")
        and has(t3, "\n7        1        1        1        2        2        2        50       cut\n"), "written back with its roll and cut")
    local k4 = CINE.parse(t3)
    check(#k4 == 2 and k4[1].roll == -15 and k4[1].cut and k4[2].cut and not k4[2].roll, "and read again the same")
    writeText(C.file, "0 1 1 1 2 2 2 50\n0.2 1 1 1 2 2 2 50\n")
    n0 = #logs
    CINE.load("test")
    check(has(find("line 2 replaces line 1", n0), "line 1 not taken"), "named in the log when read")
end
writeText(C.file, edited)
CINE.load("test")
CINE.save(CINE.keys, "test")
check(fileText(C.prev) == edited and fileText(C.edited) == nil and has(fileText(C.file), "\n2.5      100      -300     20       0        0        30       60\n")
    and has(fileText(C.file), "blend = easeinout") and has(fileText(C.file), "hud = showhud") and has(fileText(C.file), "boxes = hers"),
    "a save: the file before kept as rise_camera.prev.txt, the keys and settings written")
local handEdit = fileText(C.file) .. "12 1 2 3 4 5 6 50\n"
writeText(C.file, handEdit)
n0 = #logs
CINE.save(CINE.keys, "test")
check(fileText(C.edited) == handEdit and fileText(C.prev) == handEdit and has(find("^cine: 3 keys saved", n0 + 1), "kept as rise_camera.edited.txt"),
    "a save over a hand edit made since: the edit kept as rise_camera.edited.txt")

---------------------------------------------------------------------------------------------------- the keys
print("the keys: sorted, one within 0.25 s replaced")
do
    local l = {}
    local function k(t) return { t = t, at = { 0, 0, 0 }, look = { 1, 0, 0 }, fov = 50 } end
    CINE.add(l, k(5)); CINE.add(l, k(0)); local i3 = CINE.add(l, k(9))
    local i, rep = CINE.add(l, k(7))
    check(i == 3 and not rep and i3 == 3 and l[1].t == 0 and l[2].t == 5 and l[3].t == 7 and l[4].t == 9, "7 s between 5 and 9: key 3")
    i, rep = CINE.add(l, k(7.2))
    check(i == 3 and rep and rep[1].t == 7 and #l == 4 and l[3].t == 7.2, "7.2 s replaces 7 s (within 0.25 s), handed back")
    i, rep = CINE.add(l, k(7.5))
    check(i == 4 and not rep and #l == 5, "7.5 s is another (0.3 s from 7.2)")
end

---------------------------------------------------------------------------------------------------- her frame
print("her frame, the roll, the path")
local F = { x = 500000, y = 200000, z = 0, fx = 0, fy = 1 }
do
    local w = CINE.world(F, { 700, -650, 12 })
    check(near(w.X, 565000) and near(w.Y, 270000) and near(w.Z, 1200), "700 m forward, 650 m to port, 12 m up: north and east of her (her port is +X)")
    local b = CINE.toFrame(F, w)
    check(near(b[1], 700) and near(b[2], -650) and near(b[3], 12), "and back")
    local F2 = { x = 0, y = 0, z = 0, fx = math.cos(math.rad(30)), fy = math.sin(math.rad(30)) }
    local b2 = CINE.toFrame(F2, CINE.world(F2, { -120, 340, 55 }))
    check(near(b2[1], -120, 1e-6) and near(b2[2], 340, 1e-6) and near(b2[3], 55, 1e-6), "at any heading")
    local okR = true
    for _, r in ipairs({ { 10, 30, 25 }, { -20, 200, -60 }, { 45, -90, 170 }, { 0, 0, 0 } }) do
        local q = CINE.quat({ Pitch = r[1], Yaw = r[2], Roll = r[3] })
        local f, u = fwdOfQuat(q), upOfQuat(q)
        local back = CINE.rollOf(f, u)
        local fr = fwdOfRot({ Pitch = r[1], Yaw = r[2] })
        okR = okR and near(back, r[3], 1e-6) and near(f.X, fr.X, 1e-9) and near(f.Y, fr.Y, 1e-9) and near(f.Z, fr.Z, 1e-9)
    end
    check(okR, "a camera's quaternion with its roll (FRotator::Quaternion): its forward the rotator's, its roll read back from its up")
    local banked = CINE.rollOf({ X = -1, Y = 0, Z = 0 }, { X = 0, Y = -math.sin(math.rad(20)), Z = math.cos(math.rad(20)) })
    check(near(banked, 20, 1e-9), "looking west, the up leaning north (its right side): roll +20")
    local ts, lf = { 0, 5, 9, 15 }, { 300, 200, 80, 40 }
    check(near(CINE.pchip(ts, lf, 2.5), 265.11194, 1e-5) and near(CINE.pchip(ts, lf, 7), 133.60665, 1e-5)
        and near(CINE.pchip(ts, lf, 12), 51.455696, 1e-5) and near(CINE.pchip(ts, { 700, 680, 640, 600 }, 4.5), 682.911613, 1e-5)
        and near(CINE.pchip(ts, { 40, 70, 15, 10 }, 7), 43.33502, 1e-5) and CINE.pchip(ts, lf, 5) == 200 and CINE.pchip(ts, lf, 20) == 40,
        "pchip: export_tanacorn.py's values (RISE_CAM's look_f at 2.5, 7, 12 s; at_f at 4.5; look_u at 7), the keys exact")
    local P, step = CINE.path(CINE.DEFAULTS, true, 0.5)
    local okT, keysAt = true, {}
    for i, p in ipairs(P) do
        okT = okT and near(p.t, (i - 1) * 0.5, 1e-9)
        if p.key then keysAt[#keysAt + 1] = i .. ":" .. p.key end
    end
    check(#P == 31 and step == 0.5 and okT and table.concat(keysAt, ",") == "1:1,11:2,19:3,31:4" and near(P[6].look[1], 265.11194, 1e-5)
        and near(P[10].at[1], 682.911613, 1e-5) and P[11].at[1] == 680 and P[6].fov == 55 and P[6].roll == 0,
        "smooth: a camera every 0.5 s (31), each key one (1, 11, 19, 31), between them on the curve")
    local cutKeys = { CINE.DEFAULTS[1], CINE.DEFAULTS[2], { t = 9, at = { 640, -700, 16 }, look = { 80, 0, 15 }, fov = 55, cut = true }, CINE.DEFAULTS[4] }
    local Pc = CINE.path(cutKeys, true, 0.5)
    check(#Pc == 24 and Pc[11].key == 2 and Pc[11].t == 5 and Pc[12].key == 3 and Pc[12].cut and Pc[12].t == 9 and not Pc[13].cut
        and near(Pc[6].look[1], 250, 1e-9), "a cut: two runs (0-5, 9-15), the first ending flat at key 2, the cut key starting the second")
    local Pk = CINE.path(cutKeys, false)
    check(#Pk == 4 and Pk[3].cut and not Pk[1].cut and Pk[2].key == 2, "another blend: the keys themselves")
    local long = { { t = 0, at = { 0, 0, 0 }, look = { 1, 0, 0 }, fov = 50 }, { t = 100, at = { 0, 0, 0 }, look = { 1, 0, 0 }, fov = 50 } }
    local Pl, stepL = CINE.path(long, true, 0.5)
    check(#Pl <= C.max_cams and stepL > 0.5, string.format("a long one: %d cameras at most (%d, every %.2f s)", C.max_cams, #Pl, stepL))
    local rolls = CINE.path({ { t = 0, at = { 0, 0, 0 }, look = { 1, 0, 0 }, fov = 50, roll = 170 },
                              { t = 1, at = { 0, 0, 0 }, look = { 1, 0, 0 }, fov = 50, roll = -170 } }, true, 0.5)
    check(near(rolls[2].roll, 180, 1e-9), "the roll the shorter way round (170 to -170 through 180)")
end

---------------------------------------------------------------------------------------------------- the cinematic
print("the cinematic (smooth)")
setFile({ hud = "widgets cheat showhud", callouts = "off", boxes = "keep" })
tick(0.25)
check(H ~= nil and H.widget.vis == VIS.HitTestInvisible, "Survival's HUD up before")
n0 = #logs
local R = hullR()
local ok, why = CINE.play(R, hooks)
check(ok == true and why == "keyed" and #cams == 31 and CINE.active() == "cinematic", "CINE.play: 31 cameras, keyed")
do
    local c1, k1 = cams[1], CINE.keys[1]
    local w, lk = CINE.world(F, k1.at), CINE.world(F, k1.look)
    local dx, dy, dz = lk.X - w.X, lk.Y - w.Y, lk.Z - w.Z
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    local f, q = c1:GetActorForwardVector(), fwdOfQuat(c1.t.Rotation)
    check(near(c1.loc.X, w.X) and near(c1.loc.Y, w.Y) and near(c1.loc.Z, w.Z) and c1.finished, "camera 1 at key 1's spot, finished")
    check(near(f.X, dx / n, 1e-9) and near(f.Y, dy / n, 1e-9) and near(f.Z, dz / n, 1e-9), "turned onto its look point (K2_SetActorRotation)")
    check(near(q.X, dx / n, 1e-9) and near(q.Y, dy / n, 1e-9) and near(q.Z, dz / n, 1e-9), "the spawn's quaternion the same way")
    check(c1.CameraComponent.fov == 55 and c1.CameraComponent.bConstrainAspectRatio == false, "its FOV 55, no aspect bars")
    local p6 = CINE.world(F, { CINE.pchip({ 0, 5, 9, 15 }, { 700, 680, 640, 600 }, 2.5), CINE.pchip({ 0, 5, 9, 15 }, { -650, -660, -700, -720 }, 2.5),
                               CINE.pchip({ 0, 5, 9, 15 }, { 12, 14, 16, 18 }, 2.5) })
    check(near(cams[6].loc.X, p6.X, 1e-6) and near(cams[6].loc.Y, p6.Y, 1e-6) and near(cams[6].loc.Z, p6.Z, 1e-6), "camera 6 on the curve at 2.5 s")
end
check(views[#views].o == cams[1] and views[#views].blend == 1 and views[#views].fn == 1 and views[#views].lock == false,
    "the view on camera 1 over 1 s from your plane (cubic, enter_blend; as today's riseCine)")
check(has(find("^cine: cinematic of 4 keys: 31 cameras", n0), "read back worst 0.0 deg off, FOV set on 31 of 31"), "logged with every camera read back")
check(mainFlight.vis == VIS.Hidden and message.vis == VIS.Hidden and glow.vis == VIS.Hidden and template.vis == 3,
    "the game's HUD widgets hidden (the flight HUD, its message layer, the HUD's glow root; not a template copy)")
local gl = find("^cine: the game's HUD hidden by widgets", n0)
check(has(gl, "3 of 3 widgets hidden: GlowWidgetPtr WBP_HUD_Glow_000_C_2, NonGlowFrontWidgetPtr WBP_HUD_Chronicle_MainFlight_000_C_7, WBP_HUD_SubWidgets_Message_000"),
    "logged by route: " .. tostring(gl))
check(hull.bShowHUDBox == true, "boxes = keep: her box left")
callouts, H.calloutUntil = {}, nil
hudCallout("A CALLOUT", "WHILE IT PLAYS")
tick(0.25)
check(H.widget.vis == VIS.Collapsed and has(find("^hud: hidden", n0), "held: the rise's cinematic") and find("^hud: held %(the rise's cinematic%)", n0),
    "callouts = off: Survival's HUD held off (hud: hidden (held: the rise's cinematic))")
check(#callouts == 1 and not H.calloutUntil, "a callout waits while it's all off")
-- her clock starts: the blends
local v0 = #views
riseT, rate = 0, 1
tick0()
tick(16)
local P = S.play.path
local bl, okB = viewsFrom(v0), true
local T = S.play
check(#T.blends == 30 and #bl == 30 and T.blends[1].i == 2 and T.blends[1].t == 0 and near(T.blends[1].blend, 0.5)
    and T.blends[2].i == 3 and T.blends[30].i == 31, "30 blends, camera 2 first (at 0 s over 0.5 s), then on to camera 31")
for k, b in ipairs(T.blends) do
    okB = okB and near(b.t + b.blend * rate, P[b.i].t, 1e-9) and b.lock == true and bl[k].o == cams[b.i] and bl[k].fn == 0
        and bl[k].lock == true and (k == 1 or (b.i > T.blends[k - 1].i and b.t <= P[T.blends[k - 1].i].t))
end
check(okB, "each linear (fn 0), its outgoing camera locked, ending at its camera's time, started before the view got to the last")
check(T.holds == 0 and T.cur == 31 and find("^cine: %+4%.25 s: to camera 11 of 31 %(key 2 at 5 s%) over 0%.75 s", n0) ~= nil,
    "never held at a camera; on camera 31 after 15 s; a line a key")
-- the game takes the view
pc.vt = pawn
PAUSED = true
tick(0.5)
check(pc.vt == pawn, "paused: the view not taken back")
PAUSED = false
tick(0.25)
check(pc.vt == cams[31] and views[#views].blend == 0 and S.play.reverts == 1 and find("^cine: the game took the view", n0),
    "the game took the view: given back to camera 31 at once")
mainFlight.vis = 3
tick(0.25)
check(mainFlight.vis == VIS.Hidden and find("^cine: the game showed its NonGlowFrontWidgetPtr WBP_HUD_Chronicle_MainFlight_000_C_7 again", n0), "the game showed its HUD: hidden again")
-- stop: a second Ctrl+R
n0 = #logs
CINE.stop("Ctrl+R again")
local back = views[#views]
check(back.o == pawn and back.blend == 1 and back.lock == true and back.fn == 1 and CINE.active() == nil, "CINE.stop: the view back on your plane (1 s, cubic, the camera locked)")
check(has(find("^cine: cinematic over", n0), "30 blends, 0 cuts, on camera 31 of 31; held at a camera 0 times"), "logged: its blends, no hold")
check(mainFlight.vis == 3 and message.vis == 4 and glow.vis == 3 and has(find("^cine: the game's HUD back", n0), "3 of 3 widgets back"),
    "the game's HUD widgets back as they were (3, 4, 3)")
tick(0.25)
check(H.widget.vis == VIS.HitTestInvisible and find("^hud: the rise's cinematic let go", n0) and H.calloutUntil ~= nil and H.bannerText.text == "A CALLOUT",
    "Survival's HUD back, the callout held shown")
check(not cams[1].destroyed, "the cameras kept while the view leaves them")
tick(1.5)
local allGone = true
for _, c in ipairs(cams) do allGone = allGone and c.destroyed == true end
check(allGone, "then destroyed")

print("at half her rate")
riseT, rate = nil, 0.5
cams = {}
CINE.play(hullR(), hooks)
riseT = 0
tick0()
tick(32)
do
    local okH = #S.play.blends == 30 and S.play.holds == 0
    for _, b in ipairs(S.play.blends) do okH = okH and near(b.t + b.blend * 0.5, S.play.path[b.i].t, 1e-9) end
    check(okH and near(S.play.blends[1].blend, 1.0), "blends over the time left at her rate (1 s for her first 0.5 s), never held")
end
CINE.stop("test")
rate = 1

print("one blend a key (blend = cubic)")
setFile({ hud = "widgets", callouts = "off", boxes = "keep", blend = "cubic" })
riseT = nil
cams = {}
CINE.play(hullR(), hooks)
v0 = #views
riseT = 0
tick0()
tick(16)
do
    local b, vl = S.play.blends, viewsFrom(v0)
    check(#cams == 4 and #b == 3 and b[1].i == 2 and b[2].i == 3 and b[3].i == 4 and near(b[1].t + b[1].blend, 5) and near(b[2].t + b[2].blend, 9)
        and near(b[3].t + b[3].blend, 15) and b[2].t < 5 and vl[1].fn == 1 and vl[2].lock == true,
        "4 cameras; to keys 2, 3, 4, each ending at its time, each started before the view got to the last (cubic, locked)")
end
CINE.stop("test")

print("a cut")
writeText(C.file, (CINE.text({ CINE.DEFAULTS[1], CINE.DEFAULTS[2], { t = 9, at = { 640, -700, 16 }, look = { 80, 0, 15 }, fov = 55, cut = true },
    CINE.DEFAULTS[4] }):gsub("hud = [^\n]*", "hud = widgets"):gsub("boxes = hide", "boxes = keep")))
riseT = nil
cams = {}
CINE.play(hullR(), hooks)
v0 = #views
riseT = 0
tick0()
tick(8.5)
local waitAt = #views
check(S.play.cur == 11 and S.play.holds == 0, "before the cut: the view on its way to (then on) camera 11, key 2 at 5 s")
tick(0.25)
check(#views == waitAt, "it waits there until the cut")
tick(0.25)
do
    local vl = viewsFrom(waitAt)
    check(#vl == 2 and vl[1].o == cams[12] and vl[1].blend == 0 and vl[2].o == cams[13] and vl[2].lock == false and near(vl[2].blend, 0.5)
        and S.play.cuts == 1, "at 9 s: cut to camera 12 (key 3), then on to camera 13 over 0.5 s with the outgoing camera live")
end
tick(7)
check(S.play.cur == 24 and S.play.holds == 0 and views[#views].lock == true, "on to the last camera, locked again, never held")
CINE.stop("test")
setFile({ hud = "widgets cheat showhud", callouts = "off", boxes = "keep" })

print("the rise over: R.back (sv_tanicorn's riseBack)")
riseT = nil
cams = {}
R = hullR()
CINE.play(R, hooks)
tick(0.25)
R.back = true
n0 = #logs
tick(0.25)
check(CINE.active() == nil and has(find("^cine: cinematic over", n0), "the rise is over") and mainFlight.vis == 3, "stopped, the HUD back")
tick(0.25)
check(H.widget.vis == VIS.HitTestInvisible, "Survival's HUD back")

print("the run's end")
cams = {}
CINE.play(hullR(), hooks)
tick(0.25)
newRun()
n0 = #logs
tick(0.25)
check(CINE.active() == nil and has(find("^cine: cinematic over", n0), "the run's over") and mainFlight.vis == 3 and views[#views].o == pawn,
    "a new run: stopped, the view back, the game's HUD back")
check(H.widget.vis == VIS.HitTestInvisible and HUD.state() == nil, "and Survival's HUD")

print("the level torn down")
cams = {}
CINE.play(hullR(), hooks)
tick(0.25)
n0 = #logs
LEVEL_DROPS.cine("the level torn down")
check(CINE.active() == nil and S.R == nil and HUD.state() == nil and mainFlight.vis == VIS.Hidden, "forgotten, nothing touched (the widgets left as they were)")
for _, c in ipairs(cams) do free(c) end
free(glow)                                         -- (the level's: gone with it)
message.vis = VIS.Collapsed                        -- (the game changed it since)
newRun()
tick(0.25)
check(mainFlight.vis == 3 and message.vis == VIS.Collapsed and has(find("^cine: the game's HUD back", n0), "1 of 3 widgets back"),
    "next run: the flight HUD put back (still as left), what the game changed left as it is")
message.vis = 4
glow = widget("UserWidget", TR .. "WBP_HUD_Glow_000_C_4", 3)
hudA.GlowWidgetPtr = glow

print("the level left (CINE.leave, sv_main.lua runLeft: no tick follows)")
cams = {}
CINE.play(hullR(), hooks)
tick(0.25)
D = nil                                            -- (leaveNow: runLeft ends the run in the same half)
local vLeave = #views
n0 = #logs
check(CINE.leave("Quit Mission") == true, "CINE.leave: there was something up")
check(mainFlight.vis == 3 and message.vis == 4 and glow.vis == 3 and #views == vLeave and not cams[1].destroyed and CINE.active() == nil
    and HUD.holds["the rise's cinematic"] == nil and has(find("^cine: the level was left", n0), "with cinematic"),
    "the game's HUD widgets back at once; the view and the cameras left to the level")
newRun()
cams = {}
CINE.play(hullR(), hooks)
tick(0.25)
LEAVE.gone = true                                  -- (the gate: the level torn down, LEVEL_DROPS ran)
LEVEL_DROPS.cine("the level torn down")
CINE.leave("the level torn down")
check(mainFlight.vis == VIS.Hidden, "once torn down: nothing touched")
LEAVE.gone = false
newRun()
tick(0.25)
check(mainFlight.vis == 3, "the widgets put back at the next run's first tick")
cams = {}
CINE.play(hullR(), hooks)
tick(0.25)
LEAVE.gone = true                                  -- (sv_tanicorn's riseBack -> CINE.stop with the level torn down)
local vTorn = #views
CINE.stop("the run's over")
check(CINE.active() == nil and #views == vTorn and mainFlight.vis == VIS.Hidden and not cams[1].destroyed,
    "CINE.stop once torn down: forgotten, nothing touched (no view call, no widget, no camera)")
LEAVE.gone = false
newRun()
tick(0.25)
check(mainFlight.vis == 3, "and the widgets put back at the next run's first tick")

---------------------------------------------------------------------------------------------------- HUD.hold
print("HUD.hold: counted")
HUD.hold(true, "a"); HUD.hold(true, "b"); HUD.hold(true, "a")
HUD.hold(false, "a")
tick(0.25)
check(H.widget.vis == VIS.Collapsed, "two holders, one let go: still off")
HUD.hold(false, "a")
tick(0.25)
check(H.widget.vis == VIS.Collapsed, "the same one letting go again: still off")
HUD.hold(false, "b")
tick(0.25)
check(H.widget.vis == VIS.HitTestInvisible, "the last let go: on")
HUD.hold(true, "c")
tick(0.25)
newRun()
n0 = #logs
tick(0.25)
check(H.widget.vis == VIS.HitTestInvisible and find("^hud: c's hold dropped %(its run is over%)", n0), "a hold from an old run dropped")

print("the game's HUD by its other routes")
setFile({ hud = "cheat showhud", boxes = "keep" })
n0 = #logs
cams = {}
local sub = widget("CanvasPanel", "SubPanel", 3)              -- (sv_subs.lua's strip, on Survival's canvas)
sub.op = 0.7
H.canvas:AddChildToCanvas(sub)
H.subPanel = sub
CINE.play(hullR(), hooks)
check(hudA.bShowHUD == false and mainFlight.vis == 3 and has(find("^cine: the game's HUD hidden by showhud", n0), "before it cheat: no cheat manager"),
    "hud = cheat showhud: no cheat manager, bShowHUD off")
tick(0.25)
check(H.widget.vis == VIS.HitTestInvisible and H.round.op == 0 and sub.op == 0.7 and H.banner.op ~= 0,
    "callouts = on (and bShowHUD off by showhud): Survival's HUD up, its rows at opacity 0, the banner and subtitles kept")
CINE.stop("test")
tick(0.25)
check(hudA.bShowHUD == true and H.round.op == CFG.hud.opacity, "bShowHUD back on, the rows back")
local cmCalls = {}
pc.CheatManager = obj("LiveCheatManager /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.LiveCheatManager_0")
pc.CheatManager.ChangeHUDType = function(_, m) cmCalls[#cmCalls + 1] = m end
CINE.play(hullR(), hooks)
CINE.stop("test")
check(cmCalls[1] == 2 and cmCalls[2] == 3 and hudA.bShowHUD == true, "with a cheat manager: EverythingDisabled, then RestoreToDefault")
pc.CheatManager = nil
print("the HUD's own blackout (route distortion, the default)")
setFile({ boxes = "keep" })
dists = {}
n0 = #logs
cams = {}
riseT = nil
CINE.play(hullR(), hooks)
local d1 = dists[1]
check(#dists == 1 and d1.info.UseHideHUD == true and d1.info.BeginHideHUDTime == 0 and near(d1.info.HideHUDTime, 20.5)
    and d1.info.MaxDistortionScale == 0 and d1.info.NeedUpdateDistortion == false and mainFlight.vis == 3
    and has(find("^cine: the game's HUD hidden by distortion", n0), "HideHUDTime 20.5 s"),
    "BeginHUDDistortion: UseHideHUD for her hold + the way in + her 15 s + the way out + 2 s (20.5 s), no distortion; no widget touched")
tick(19)
check(#dists == 1, "not renewed while it lasts")
tick(1)
check(#dists == 2 and near(dists[2].info.HideHUDTime, 7) and has(find("^cine: the HUD's blackout renewed", n0), "still held"),
    "renewed (5 + 2 s) while still held at its end")
CINE.stop("test")
check(dists[3] and dists[3].ended and has(find("^cine: the game's HUD back", n0), "the blackout over (EndHUDDistortion, renewed 1 times)"),
    "EndHUDDistortion at the end")
tick(1.5)

---------------------------------------------------------------------------------------------------- the boxes
print("the target boxes")
local function boxActor(n, hidden)
    local b = obj("ChronicleTargetContainerActorBP_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.ChronicleTargetContainerActorBP_C_" .. n,
        { bHidden = hidden })
    b.SetActorHiddenInGame = function(self, h) self.bHidden = h end
    return b
end
local e1, e2, e3 = obj("Enemy 1"), obj("Enemy 2"), obj("Enemy 3")
local box1, box2, box3 = boxActor(1, false), boxActor(2, true), boxActor(3, false)
local mgr = obj("LiveTargetContainerManager /Engine/Transient.LiveTargetContainerManager_0",
    { TargetContainers = tmap({ [e1] = box1, [e3] = box3 }), ContainerPool = tarray({ box2 }) })
hudA.TargetContainerManager = mgr
setFile({ hud = "widgets" })
n0 = #logs
cams = {}
CINE.play(hullR(), hooks)
check(box1.bHidden == true and box3.bHidden == true and box2.bHidden == true and hull.bShowHUDBox == false
    and has(find("^cine: the target boxes", n0), "2 hidden of 3 (the HUD's TargetContainerManager; 1 spares, 1 of them hidden already)")
    and find("^cine: her target box off", n0), "boxes = hide: her bShowHUDBox off, every box shown hidden (the spare left as it was)")
box1.bHidden = false                               -- (the game shows one again)
mgr.TargetContainers.m[e2] = box2; mgr.ContainerPool.l = {}; box2.bHidden = false   -- (a new target: a spare taken, shown)
tick(0.25)
check(box1.bHidden == true and box2.bHidden == true and has(find("^cine: the game showed a target box again", n0), "BP_C_1"),
    "the game's shown boxes hidden again, a new target's too")
mgr.TargetContainers.m[e3] = nil; mgr.ContainerPool.l = { box3 }   -- (a target gone: its box a spare again, hidden by the pool)
tick(0.25)
n0 = #logs
CINE.stop("test")
check(box1.bHidden == false and box2.bHidden == false and box3.bHidden == true and hull.bShowHUDBox == true
    and has(find("^cine: the game's HUD back", n0), "2 of 3 target boxes back, 1 left hidden as spares (1 more hidden while held, 1 shown again by the game)")
    and has(find("^cine: the game's HUD back", n0), "her box back"), "put back: the targets' boxes shown, the spare left hidden, her box on")
tick(1.5)
setFile({ hud = "widgets", boxes = "hers" })
cams = {}
CINE.play(hullR(), hooks)
check(hull.bShowHUDBox == false and box1.bHidden == false and box2.bHidden == false, "boxes = hers: only hers off")
CINE.stop("test")
check(hull.bShowHUDBox == true, "and back")
hudA.TargetContainerManager = nil
FINDS["ChronicleTargetContainerActorBP_C"] = { box1 }
setFile({ hud = "widgets" })
n0 = #logs
cams = {}
CINE.play(hullR(), hooks)
check(box1.bHidden == true and has(find("^cine: the target boxes", n0), "found by class"), "without the manager: found by class (once)")
CINE.stop("test")
check(box1.bHidden == false, "and back")
FINDS["ChronicleTargetContainerActorBP_C"] = nil
tick(2)

---------------------------------------------------------------------------------------------------- the director
print("the director")
setFile({ hud = "widgets cheat showhud" })
D = nil
n0 = #logs
keys.D()
check(find("^cine: Ctrl%+D outside a Survival run", n0) and S.dir == false, "Ctrl+D outside a run: refused")
newRun()
COOP.client = function() return true end
keys.E()
check(find("^cine: Ctrl%+E: the host's", n0) ~= nil, "Ctrl+E on a joiner: refused")
COOP.client = function() return false end
fxs = {}
keys.D()
local dir = CINE.director()
check(dir and dir.speed == 0.35 and said[#said].text == "DIRECTOR MODE ON", "Ctrl+D: director mode on, its speed 0.35")
tick(0.25)
check(#fxs == 4 and fxs[1].sc == 3 and has(fxs[1].sys.__name, "NS_ms23FarFlash"), "a marker at each of the 4 cameras' spots (the M23 far flash x3)")
local w1 = CINE.world(F, CINE.keys[1].at)
check(near(fxs[1].where.X, w1.X) and near(fxs[1].where.Y, w1.Y) and near(fxs[1].where.Z, w1.Z), "key 1's marker at its camera's spot")
check(count("^cine: key %d of 4 %(the markers%)", n0) == 4 and has(find("^cine: key 1 of 4", n0), "her port side"), "a line a key in the log")
tick(2)
check(#fxs == 8, "again 2 s on")
cams = {}
riseT = nil
R = hullR()
local okD, whyD = CINE.play(R, hooks)
check(okD == false and whyD == "director" and #cams == 0 and HUD.state() == nil and mainFlight.vis == 3 and hull.bShowHUDBox == true,
    "a rise in director mode: no cinematic, no HUD off")
pcm.loc = CINE.world(F, { 650, -500, 30 })
n0 = #logs
keys.E()
check(CINE.keys[1].t == 0 and near(CINE.keys[1].at[1], 650) and #CINE.keys == 4 and has(find("^cine: Ctrl%+E, camera key 1 of 4", n0), "her hold: 0 s")
    and said[#said].sub == "REPLACED THE ONE THERE", "Ctrl+E in her hold (her clock not started): at 0 s, said so")
riseT = 6.3
pcm.loc = CINE.world(F, { 100, -400, 50 })
pcm.fwd = { X = -1, Y = 0, Z = 0 }                 -- (across her, from her port side)
n0 = #logs
local file0 = fileText(C.file)
keys.E()
K = CINE.keys
local k3 = K[3]
check(#K == 5 and near(k3.t, 6.3) and near(k3.at[1], 100) and near(k3.at[2], -400) and near(k3.at[3], 50) and near(k3.look[1], 100)
    and near(k3.look[2], 100) and near(k3.look[3], 50) and k3.fov == 70 and k3.roll == nil,
    "Ctrl+E at her time: key 3 at 6.3 s, its place, the point 500 m along the view, fov 70, level")
check(said[#said].text == "CAMERA KEY 3 AT 6.3 S" and has(find("^cine: Ctrl%+E, camera key 3 of 5", n0), "the rise's time")
    and has(find("^cine: Ctrl%+E, camera key 3 of 5", n0), "the camera manager's forward), roll 0"), "its callout and log line")
check(has(fileText(C.file), "\n6.3      100      -400     50       100      100      50       70\n") and fileText(C.prev) == file0, "saved at once, the file before kept")
riseT = 6.45
pcm.up = { X = 0, Y = -math.sin(math.rad(20)), Z = math.cos(math.rad(20)) }   -- (banked 20 degrees right)
keys.E()
check(#CINE.keys == 5 and near(CINE.keys[3].t, 6.45) and near(CINE.keys[3].roll, 20) and said[#said].sub == "REPLACED THE ONE THERE"
    and has(fileText(C.file), "\n6.45     100      -400     50       100      100      50       70       20\n"), "6.45 s replaces it, banked: its roll recorded")
pcm.up = { X = 0, Y = 0, Z = 1 }
riseT = 7
pcm.loc = CINE.world(F, { 300, -900, 80 })
keys.E()
check(said[#said].text == "CAMERA KEY 4 AT 7.0 S" and #CINE.keys == 6, "7 s: key 4")
-- her edit in the file, then Ctrl+E with nothing else between
local edit = fileText(C.file):gsub("\n15       ", "\n11       1        2        3        4        5        6        50\n15       ")
writeText(C.file, edit)
riseT = 12
n0 = #logs
keys.E()
local tt = {}
for i, k in ipairs(CINE.keys) do tt[i] = string.format("%g", k.t) end
check(table.concat(tt, ",") == "0,5,6.45,7,9,11,12,15" and has(fileText(C.file), "\n11       1        2        3")
    and find("^cine: keys %(Ctrl%+E: the file was changed since it was read%)", n0) and fileText(C.edited) ~= edit,
    "a hand edit, then Ctrl+E: the file read again first, her key 11 kept with the new one (" .. table.concat(tt, ",") .. ")")
-- her rig freed (the hull going): no call on it, the clock not read
R.playing = true
free(rig)
n0 = #logs
keys.E()
check(has(find("^cine: Ctrl%+E, camera key", n0), "no rise playing: the last key recorded (12 s) + 1 s") and CINE.keys[8] and near(CINE.keys[8].t, 13),
    "her rig freed: her clock not read (13 s, the last + 1)")
rig = obj("SkeletalMeshComponent /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_SV_Tani_HULL_C_1.RiseRig_2")
R.back = true
n0 = #logs
tick(0.25)
check(S.R == nil and find("^cine: the rise's frame let go %(the rise is over%)", n0), "the rise over (R.back): her frame let go at the next tick")
keys.E()
check(has(find("^cine: Ctrl%+E, camera key", n0), "no rise playing: the last key recorded (13 s) + 1 s"), "with no rise: the last recorded + 1 s, said so")
-- back to a smaller set for the preview
writeText(C.file, CINE.text({ CINE.DEFAULTS[1], CINE.DEFAULTS[2], { t = 6.45, at = { 100, -400, 50 }, look = { 100, 100, 50 }, fov = 70, roll = 20 },
    { t = 7.45, at = { 100, -400, 50 }, look = { 100, 100, 50 }, fov = 70 }, CINE.DEFAULTS[3], CINE.DEFAULTS[4] }):gsub("hud = [^\n]*", "hud = widgets"))

print("the preview")
cams, callouts, H.calloutUntil = {}, {}, nil
n0 = #logs
keys.V()
w1 = CINE.world(F, CINE.keys[1].at)
check(#cams == 1 and pc.vt == cams[1] and near(cams[1].loc.X, w1.X) and said[#said].text == "KEY 1 OF 6 AT 0.0 S"
    and said[#said].sub == "CTRL+D: BACK TO YOUR PLANE", "Ctrl+V: key 1's camera, its callout (CTRL+D: BACK TO YOUR PLANE)")
tick(0.25)
check(H.widget.vis == VIS.HitTestInvisible and H.round.op == 0 and H.banner.op ~= 0 and H.calloutUntil and H.bannerText.text == "KEY 1 OF 6 AT 0.0 S",
    "the HUD off but its callout (the rows at opacity 0)")
check(mainFlight.vis == VIS.Hidden and hull.bShowHUDBox == false, "the game's HUD hidden, her box off")
keys.V(); keys.V()
check(cams[3].rot.Roll == 20 and said[#said].text == "KEY 3 OF 6 AT 6.5 S", "key 3's camera rolled 20 degrees")
keys.D()
check(pc.vt == pawn and S.pv == nil and CINE.director() ~= nil and said[#said].text == "CAMERA PREVIEW OVER" and mainFlight.vis == 3
    and hull.bShowHUDBox == true, "Ctrl+D in a preview: over, your plane back (director mode as it was)")
keys.V()
local nk = #CINE.keys
keys.E()
check(pc.vt == pawn and S.pv == nil and #CINE.keys == nk and said[#said].sub == "CTRL+E AGAIN: RECORD A KEY", "Ctrl+E in a preview: over, no key recorded")
keys.V()
tick(19.75)
check(S.pv ~= nil, "a preview held while you look")
tick(0.5)
check(S.pv == nil and pc.vt == pawn and said[#said].text == "CAMERA PREVIEW OVER" and find("^cine: preview over %(no Ctrl%+V for 20 s%)", n0),
    "20 s with no Ctrl+V: over")
keys.V()
local pawn2 = obj("BP_PlayerPlane_PP1000_f16c_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PP_2")
pc.Pawn = pawn2
tick(0.25)
check(S.pv == nil and find("^cine: preview over %(your plane changed or is gone%)", n0), "a new plane (shot down, respawned): over")
pc.Pawn = pawn
pc.vt = pawn
keys.V()
local n1 = #logs
pc.Pawn = { __addr = pawn.__addr, __name = "BP_PlayerPlane_PP1000_f16c_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PP_3" }
tick(0.25)
check(S.pv == nil and find("^cine: preview over %(your plane changed or is gone%)", n1),
    "a new plane at the old one's address (hard rule 59): over")
pc.Pawn = pawn
pc.vt = pawn
downNow = true
keys.V()
check(S.pv == nil and said[#said].text == "CTRL+V: NOT WHILE YOU'RE DOWN", "refused while you're down (the spectator has the view)")
downNow = false
cams = {}
for _ = 1, 6 do keys.V() end
tick(1)
check(#cams == 6 and pc.vt == cams[6] and cams[1].destroyed and not cams[6].destroyed and said[#said].text == "KEY 6 OF 6 AT 15.0 S"
    and said[#said].sub == "CTRL+V OR CTRL+D: BACK TO YOUR PLANE", "a press each: key 6 of 6, the ones before destroyed")
keys.V()
tick(1)
check(pc.vt == pawn and cams[6].destroyed and mainFlight.vis == 3 and has(find("^cine: preview over %(past the last key%)", n0), "the view back on your plane"),
    "past the last: back on your plane, the game's HUD back")
check(H.round.op == CFG.hud.opacity and H.widget.vis == VIS.HitTestInvisible, "Survival's rows back at their opacity")

print("a new take")
local cur = fileText(C.file)
n0 = #logs
keys.W()
local takeLine = find("^cine: Ctrl%+W, a new take", n0)
local takeFile = takeLine and takeLine:match("config\\(rise_camera%.take_[%d_]+%.txt)")
check(takeFile ~= nil and fileText(takeFile) == cur and has(takeLine, "the 6 keys kept in") and #CINE.keys == 4
    and has(fileText(C.file), "\n9        640      -700") and not has(fileText(C.file), "6.45"), "Ctrl+W: the 6 keys kept in " .. tostring(takeFile) .. ", today's camera back")
check(said[#said].text == "NEW TAKE" and has(said[#said].sub, "6 KEYS KEPT IN RISE_CAMERA.TAKE_"), "its callout names the file")
keys.E()
keys.E()
check(takeFile and fileText(takeFile) == cur and not has(fileText(C.prev), "6.45"), "two keys later the take is still whole (the .prev only one save's undo)")
keys.D()
check(CINE.director() == nil and said[#said].text == "DIRECTOR MODE OFF", "Ctrl+D again: off")

print("director mode and the hulls")
setFile({ hud = "widgets" })
keys.D()
check(CINE.director() ~= nil, "on")
newRun()
n0 = #logs
tick(0.25)
check(CINE.director() == nil and find("^cine: director mode OFF %(the run's over%)", n0), "a new run: director mode off, said so")
keys.D()
free(hull)                                         -- (Ctrl+Y's hull gone; Ctrl+L's live one comes later)
FINDS["BP_SV_Tani_HULL_C"] = { hullCdo }
finds = {}
fxs = {}
n0 = #logs
tick(9.5)
check(#fxs == 0 and (finds["BP_SV_Tani_HULL_C"] or 0) <= 2 and find("^cine: the markers wait: no TANACORN up", n0),
    "no hull: the markers wait, the hulls looked for at most every 10 s (" .. tostring(finds["BP_SV_Tani_HULL_C"]) .. " in 9.5 s)")
local live = obj("BP_SV_Tani_HULLLIVE_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_SV_Tani_HULLLIVE_C_1",
    { loc = { X = 0, Y = 0, Z = 0 } })
live.K2_GetActorLocation = function(self) return self.loc end
live.GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end
FINDS["BP_SV_Tani_HULLLIVE_C"] = { live }
tick(2)
check(#fxs == 4 and near(fxs[1].where.X, 70000) and near(fxs[1].where.Y, -65000), "Ctrl+L's live hull found too: the markers at its keys")
keys.D()

if fails > 0 then print("cine test: " .. fails .. " FAILED"); os.exit(1) end
print("cine test: all passed")
