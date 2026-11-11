-- cine_test.lua <work dir> (run by tools/checks/cine_test.sh on a copy of the mod's Scripts and config): THE TANACORN's
-- rise cinematic and its director (Scripts/sv_cine.lua, docs/re/CINEMATIC.md) on the real sv_core, sv_config, sv_ai and
-- sv_hud (HUD.hold), the game stubbed (the player controller and its camera manager, the camera actors, GameplayStatics,
-- Niagara, the game's HUD actor and widgets, THE TANACORN's hull):
--   the file: missing -> today's camera (export_tanacorn.py RISE_CAM, fov 55) and the file made; a hand-edited one read
--     (comments, commas, out of order -> sorted, bad lines skipped and named, the settings); text -> parse round trip;
--     a save keeps the one before as rise_camera.prev.txt;
--   the keys: sorted by t, one within 0.25 s replaced;
--   her frame: a key's spot in the world (forward, starboard, up from her rest midships) and back;
--   the cinematic: a camera at each key's spot turned onto its look point (the spawn's quaternion and the rotator agree),
--     its FOV; the view on key 1 at once, then the blends in order, each over the time left to its key (at her rate,
--     0.5 too), on her clock; the view given back when the game takes it (not while paused); Survival's HUD held, the
--     game's widgets hidden (a blueprint's template copy never touched), hidden again when the game shows them;
--   every stop path: CINE.stop (a second Ctrl+R), the rise over (R.back), the run's end (a new run), the level torn down
--     (forgotten untouched, the game's widgets put back next run if still as left), each with the view back, the HUD
--     hold let go (callouts held while it was all off shown after), the game's HUD as it was, the cameras destroyed
--     once the view is off them;
--   HUD.hold counted: two holders, one letting go twice; a hold from an old run dropped; the routes showhud and cheat;
--   the director: Ctrl+D on (markers at each key's spot every 2 s, a line a key), the rise tracked only, Ctrl+E at her
--     time (place, look point 500 m along the view, FOV; saved; the callout), replacing, with no rise (+1 s);
--     Ctrl+V a camera a press with the callouts still shown and the rest of the HUD off, then back; Ctrl+W a new take;
--     the keys refused outside a run and on a joiner.
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
local FINDS = {}
function FindAllOf(c) return FINDS[c] end
function FindFirstOf() return nil end
function NotifyOnNewObject() end
function FName(s) return s end
function FText(s) return s end

-- the engine's statics: GameplayStatics (the camera actors), Niagara (the markers), the HUD's widget library
local cams, fxs = {}, {}
local function fwdOfRot(r)
    local p, y = math.rad(r.Pitch), math.rad(r.Yaw)
    return { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
end
local function fwdOfQuat(q)                    -- the quaternion's +X: what the spawn transform's Rotation turns it to
    return { X = 1 - 2 * (q.Y * q.Y + q.Z * q.Z), Y = 2 * (q.X * q.Y + q.W * q.Z), Z = 2 * (q.X * q.Z - q.W * q.Y) }
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
function nativeReady() return true end
local PAUSED = false
function gamePaused() return PAUSED end

-- you: your plane, the controller (the view: SetViewTargetWithBlend / GetViewTarget), the camera manager
local pawn = obj("BP_PlayerPlane_PP1000_f16c_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PP_1",
    { loc = { X = 0, Y = 0, Z = 300000 } })
pawn.K2_GetActorLocation = function(self) return self.loc end
pawn.GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end
local pcm = obj("LivePlayerCameraManager /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.PCM_0",
    { loc = { X = 0, Y = 0, Z = 300000 }, fwd = { X = 1, Y = 0, Z = 0 }, fov = 70 })
pcm.GetCameraLocation = function(self) return self.loc end
pcm.K2_GetActorLocation = function(self) return self.loc end
pcm.GetActorForwardVector = function(self) return self.fwd end
pcm.GetFOVAngle = function(self) return self.fov end
local hudA = obj("LiveMainHUDParent4K_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.LiveMainHUDParent4K_C_0", { bShowHUD = true })
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

-- THE TANACORN: her hull facing +Y (yaw 90: her starboard is -X), 5 km east, 2 km north
local hull = obj("BP_SV_Tani_HULL_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_SV_Tani_HULL_C_1",
    { loc = { X = 500000, Y = 200000, Z = 0 } })
hull.K2_GetActorLocation = function(self) return self.loc end
hull.GetActorForwardVector = function() return { X = 0, Y = 1, Z = 0 } end
local hullCdo = obj("BP_SV_Tani_HULL_C /Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_HULL.Default__BP_SV_Tani_HULL_C")
FINDS["BP_SV_Tani_HULL_C"] = { hull, hullCdo }
TANI = { hull = { class = "BP_SV_Tani_HULL_C" }, rise = { rate = 1.0 } }

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
local S, C = CINE.S, CINE.cfg
local riseT = nil                                 -- (her clock: nil before she plays)
local rate = 1
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
local function hullR() return { o = hull, name = nameOf(hull), x = 500000, y = 200000, z = 0 } end
local hooks = { clock = function() return riseT end, rate = function() return rate end }

---------------------------------------------------------------------------------------------------- the file
print("the file")
check(type(cineTick) == "function" and type(keys.D) == "function" and type(keys.E) == "function" and type(keys.V) == "function"
    and type(keys.W) == "function" and type(LEVEL_DROPS.cine) == "function", "its tick, Ctrl+D / E / V / W and its level drop")
local mk = find("^cine: keys %(loaded%)")
check(mk ~= nil and has(mk, "today's camera (the file missing), the file made at 0, 5, 9, 15 s") and has(mk, "director speed 0.35, blend cubic")
    and has(mk, "the game's HUD by widgets, cheat, showhud"), "missing: today's camera, the file made: " .. tostring(mk))
local K = CINE.keys
check(#K == 4 and K[1].t == 0 and K[1].at[1] == 700 and K[1].at[2] == -650 and K[1].at[3] == 12 and K[1].look[1] == 300
    and K[1].look[3] == 40 and K[4].t == 15 and K[4].at[2] == -720 and K[4].look[1] == 40 and K[2].fov == 55,
    "the defaults: RISE_CAM (t, place, look point; UE's y as starboard), fov 55")
local made = fileText(C.file)
check(has(made, "director_speed = 0.35") and has(made, "\n0        700      -650     12       300      0        40       55\n")
    and has(made, "\n15       600      -720     18       40       0        10       55\n"), "the file written: its settings and a key a line")
do
    local k2, set2, bad2 = CINE.parse(CINE.text(CINE.DEFAULTS))
    local same = #k2 == 4
    for i = 1, 4 do
        local a, b = k2[i], CINE.DEFAULTS[i]
        same = same and a.t == b.t and a.fov == b.fov
        for j = 1, 3 do same = same and a.at[j] == b.at[j] and a.look[j] == b.look[j] end
    end
    check(same and #bad2 == 0 and set2.blend == "cubic" and #set2.hud == 3, "text -> parse: the same keys and settings")
end
local edited = table.concat({
    "; a note", "director_speed = 0.5", "blend = Ease_In_Out", "hud = showhud",
    "9, 640, -700, 16, 80, 0, 15, 40   ; commas, a note after it",
    "2.5 100 -300 20 0 0 30 60",
    "1 2 3",                                  -- (line 7: 3 values)
    "4 1 1 1 1 1 1 200",                      -- (line 8: fov)
    "speed = 3",                              -- (line 9: no such setting)
    "  # a hash note",
    "0 700 -650 12 300 0 40 55",
}, "\n")
assert(io.open(CONF .. C.file, "wb")):write(edited):close()
local n0 = #logs
CINE.load("test")
K = CINE.keys
check(#K == 3 and K[1].t == 0 and K[2].t == 2.5 and K[3].t == 9 and K[3].fov == 40 and K[2].at[2] == -300,
    "a hand-edited file: comments, commas, out of order -> sorted (0, 2.5, 9)")
check(has(find("line 7 skipped", n0), "3 values, not 8") and has(find("line 8 skipped", n0), "fov must be 5 to 170")
    and has(find("line 9 skipped", n0), "no setting speed"), "its bad lines skipped, each named by its line")
check(S.set.director_speed == 0.5 and S.set.blend == "easeinout" and #S.set.hud == 1 and S.set.hud[1] == "showhud"
    and CINE.director() == nil, "its settings: director_speed, blend (any case, _ ignored), hud")
CINE.save(CINE.keys, "test")
check(fileText(C.prev) == edited and has(fileText(C.file), "\n2.5      100      -300     20       0        0        30       60\n")
    and has(fileText(C.file), "blend = easeinout") and has(fileText(C.file), "hud = showhud"),
    "a save: the file before kept as rise_camera.prev.txt, the keys and settings written")

---------------------------------------------------------------------------------------------------- the keys
print("the keys: sorted, one within 0.25 s replaced")
do
    local l = {}
    local function k(t) return { t = t, at = { 0, 0, 0 }, look = { 1, 0, 0 }, fov = 50 } end
    CINE.add(l, k(5)); CINE.add(l, k(0)); local i3 = CINE.add(l, k(9))
    local i, rep = CINE.add(l, k(7))
    check(i == 3 and not rep and i3 == 3 and l[1].t == 0 and l[2].t == 5 and l[3].t == 7 and l[4].t == 9, "7 s between 5 and 9: key 3")
    i, rep = CINE.add(l, k(7.2))
    check(i == 3 and rep and #l == 4 and l[3].t == 7.2, "7.2 s replaces 7 s (within 0.25 s)")
    i, rep = CINE.add(l, k(7.5))
    check(i == 4 and not rep and #l == 5, "7.5 s is another (0.3 s from 7.2)")
end

---------------------------------------------------------------------------------------------------- her frame
print("her frame")
local F = { x = 500000, y = 200000, z = 0, fx = 0, fy = 1 }
do
    local w = CINE.world(F, { 700, -650, 12 })
    check(near(w.X, 565000) and near(w.Y, 270000) and near(w.Z, 1200), "700 m forward, 650 m to port, 12 m up: north and east of her (her port is +X)")
    local b = CINE.toFrame(F, w)
    check(near(b[1], 700) and near(b[2], -650) and near(b[3], 12), "and back")
    local F2 = { x = 0, y = 0, z = 0, fx = math.cos(math.rad(30)), fy = math.sin(math.rad(30)) }
    local b2 = CINE.toFrame(F2, CINE.world(F2, { -120, 340, 55 }))
    check(near(b2[1], -120, 1e-6) and near(b2[2], 340, 1e-6) and near(b2[3], 55, 1e-6), "at any heading")
end

---------------------------------------------------------------------------------------------------- the cinematic
print("the cinematic")
assert(io.open(CONF .. C.file, "wb")):write(CINE.text(CINE.DEFAULTS)):close()
tick(0.25)
check(H ~= nil and H.widget.vis == VIS.HitTestInvisible, "Survival's HUD up before")
n0 = #logs
local R = hullR()
local ok, why = CINE.play(R, hooks)
check(ok == true and why == "keyed" and #cams == 4 and CINE.active() == "cinematic", "CINE.play: 4 cameras, keyed")
do
    local c1, k1 = cams[1], CINE.keys[1]
    local w, lk = CINE.world(F, k1.at), CINE.world(F, k1.look)
    local dx, dy, dz = lk.X - w.X, lk.Y - w.Y, lk.Z - w.Z
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    local f, q = c1:GetActorForwardVector(), fwdOfQuat(c1.t.Rotation)
    check(near(c1.loc.X, w.X) and near(c1.loc.Y, w.Y) and near(c1.loc.Z, w.Z) and c1.finished, "key 1's camera at its spot, finished")
    check(near(f.X, dx / n, 1e-9) and near(f.Y, dy / n, 1e-9) and near(f.Z, dz / n, 1e-9), "turned onto its look point (K2_SetActorRotation)")
    check(near(q.X, dx / n, 1e-9) and near(q.Y, dy / n, 1e-9) and near(q.Z, dz / n, 1e-9), "the spawn's quaternion the same way")
    check(c1.CameraComponent.fov == 55 and c1.CameraComponent.bConstrainAspectRatio == false, "its FOV 55, no aspect bars")
end
check(views[#views].o == cams[1] and views[#views].blend == 0 and views[#views].fn == 1, "the view on key 1 at once (cubic)")
check(has(find("^cine: cinematic of 4 keys", n0), "read back 0.0 deg off"), "logged with each camera read back")
check(mainFlight.vis == VIS.Hidden and message.vis == VIS.Hidden and glow.vis == VIS.Hidden and template.vis == 3,
    "the game's HUD widgets hidden (the flight HUD, its message layer, the HUD's glow root; not a template copy)")
local gl = find("^cine: the game's HUD hidden by widgets", n0)
check(has(gl, "3 of 3 widgets hidden: GlowWidgetPtr WBP_HUD_Glow_000_C_2, NonGlowFrontWidgetPtr WBP_HUD_Chronicle_MainFlight_000_C_7, WBP_HUD_SubWidgets_Message_000"),
    "logged by route: " .. tostring(gl))
callouts, H.calloutUntil = {}, nil
hudCallout("A CALLOUT", "WHILE IT PLAYS")
tick(0.25)
check(H.widget.vis == VIS.Collapsed and has(find("^hud: hidden", n0), "held: the rise's cinematic") and find("^hud: held %(the rise's cinematic%)", n0),
    "Survival's HUD held off (hud: hidden (held: the rise's cinematic))")
check(#callouts == 1 and not H.calloutUntil, "a callout waits while it's all off")
-- her clock starts: the blends
local v0 = #views
riseT, rate = 0, 1
tick(16)
local bl = {}
for i = v0 + 1, #views do bl[#bl + 1] = views[i] end
check(#bl == 3 and bl[1].o == cams[2] and bl[2].o == cams[3] and bl[3].o == cams[4], "the blends in order: key 2, 3, 4")
local t1, t2, t3 = S.play.blends[1], S.play.blends[2], S.play.blends[3]
check(near(t1.t + t1.blend, 5) and near(t2.t + t2.blend, 9) and near(t3.t + t3.blend, 15) and near(t2.t, 5) and near(t3.t, 9),
    string.format("each over the time left to its key (%.2f+%.2f, %.2f+%.2f, %.2f+%.2f)", t1.t, t1.blend, t2.t, t2.blend, t3.t, t3.blend))
check(bl[1].blend > 4.5 and bl[2].blend == 4 and bl[3].blend == 6 and bl[1].lock == false, "4.75, 4 and 6 s, the outgoing camera live")
check(S.play.cur == 4 and #views == v0 + 3, "on the last key after 15 s, nothing more")
-- the game takes the view
pc.vt = pawn
PAUSED = true
tick(0.5)
check(pc.vt == pawn, "paused: the view not taken back")
PAUSED = false
tick(0.25)
check(pc.vt == cams[4] and views[#views].blend == 0 and S.play.reverts == 1 and find("^cine: the game took the view", n0),
    "the game took the view: given back to key 4's camera at once")
mainFlight.vis = 3
tick(0.25)
check(mainFlight.vis == VIS.Hidden and find("^cine: the game showed its NonGlowFrontWidgetPtr WBP_HUD_Chronicle_MainFlight_000_C_7 again", n0), "the game showed its HUD: hidden again")
-- stop: a second Ctrl+R
n0 = #logs
CINE.stop("Ctrl+R again")
local back = views[#views]
check(back.o == pawn and back.blend == 1 and back.lock == true and CINE.active() == nil, "CINE.stop: the view back on your plane (1 s, the camera locked)")
check(mainFlight.vis == 3 and message.vis == 4 and glow.vis == 3 and has(find("^cine: the game's HUD back", n0), "3 of 3 widgets back"),
    "the game's HUD widgets back as they were (3, 4, 3)")
tick(0.25)
check(H.widget.vis == VIS.HitTestInvisible and find("^hud: the rise's cinematic let go", n0) and H.calloutUntil ~= nil and H.bannerText.text == "A CALLOUT",
    "Survival's HUD back, the callout held shown")
check(not cams[1].destroyed, "the cameras kept while the view leaves them")
tick(1.5)
check(cams[1].destroyed and cams[2].destroyed and cams[3].destroyed and cams[4].destroyed, "then destroyed")

print("at half her rate")
riseT, rate = nil, 0.5
cams = {}
CINE.play(hullR(), hooks)
riseT = 0
tick(32)
local b1 = S.play.blends[1]
check(#S.play.blends == 3 and near(b1.t + b1.blend * 0.5, 5) and near(S.play.blends[2].blend, 8), "blends over the time left at her rate (8 s for 4 s of hers)")
CINE.stop("test")
rate = 1

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
assert(io.open(CONF .. C.file, "wb")):write((CINE.text(CINE.DEFAULTS):gsub("hud = widgets cheat showhud", "hud = cheat showhud"))):close()
n0 = #logs
cams = {}
CINE.play(hullR(), hooks)
check(hudA.bShowHUD == false and mainFlight.vis == 3 and has(find("^cine: the game's HUD hidden by showhud", n0), "before it cheat: no cheat manager"),
    "hud = cheat showhud: no cheat manager, bShowHUD off")
CINE.stop("test")
check(hudA.bShowHUD == true, "bShowHUD back on")
local cmCalls = {}
pc.CheatManager = obj("LiveCheatManager /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.LiveCheatManager_0")
pc.CheatManager.ChangeHUDType = function(_, m) cmCalls[#cmCalls + 1] = m end
CINE.play(hullR(), hooks)
CINE.stop("test")
check(cmCalls[1] == 2 and cmCalls[2] == 3 and hudA.bShowHUD == true, "with a cheat manager: EverythingDisabled, then RestoreToDefault")
pc.CheatManager = nil
assert(io.open(CONF .. C.file, "wb")):write(CINE.text(CINE.DEFAULTS)):close()
tick(2)

---------------------------------------------------------------------------------------------------- the director
print("the director")
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
check(okD == false and whyD == "director" and #cams == 0 and HUD.state() == nil and mainFlight.vis == 3, "a rise in director mode: no cinematic, no HUD off")
riseT = 6.3
pcm.loc = CINE.world(F, { 100, -400, 50 })
pcm.fwd = { X = -1, Y = 0, Z = 0 }                 -- (across her, from her port side)
n0 = #logs
local file0 = fileText(C.file)
keys.E()
K = CINE.keys
local k3 = K[3]
check(#K == 5 and near(k3.t, 6.3) and near(k3.at[1], 100) and near(k3.at[2], -400) and near(k3.at[3], 50) and near(k3.look[1], 100)
    and near(k3.look[2], 100) and near(k3.look[3], 50) and k3.fov == 70, "Ctrl+E at her time: key 3 at 6.3 s, its place, the point 500 m along the view, fov 70")
check(said[#said].text == "CAMERA KEY 3 AT 6.3 S" and has(find("^cine: Ctrl%+E, camera key 3 of 5", n0), "the rise's time")
    and has(find("^cine: Ctrl%+E, camera key 3 of 5", n0), "the camera manager's forward"), "its callout and log line")
check(has(fileText(C.file), "\n6.3      100      -400     50       100      100      50       70\n") and fileText(C.prev) == file0, "saved at once, the file before kept")
riseT = 6.45
keys.E()
check(#CINE.keys == 5 and near(CINE.keys[3].t, 6.45) and said[#said].sub == "REPLACED THE ONE THERE", "6.45 s replaces it")
CINE.stop("the rise ended")
n0 = #logs
keys.E()
check(#CINE.keys == 6 and near(CINE.keys[4].t, 7.45) and has(find("^cine: Ctrl%+E, camera key 4 of 6", n0), "no rise playing: the last key recorded (6.45 s) + 1 s"),
    "with no rise: the last recorded + 1 s, said so")
local tt = {}
for i, k in ipairs(CINE.keys) do tt[i] = k.t end
check(table.concat(tt, ",") == "0,5,6.45,7.45,9,15", "sorted (" .. table.concat(tt, ",") .. ")")

print("the preview")
cams, callouts, H.calloutUntil = {}, {}, nil
n0 = #logs
keys.V()
check(#cams == 1 and pc.vt == cams[1] and near(cams[1].loc.X, w1.X) and said[#said].text == "KEY 1 OF 6 AT 0.0 S", "Ctrl+V: key 1's camera, its callout")
tick(0.25)
check(H.widget.vis == VIS.HitTestInvisible and H.round.op == 0 and H.banner.op ~= 0 and H.calloutUntil and H.bannerText.text == "KEY 1 OF 6 AT 0.0 S",
    "the HUD off but its callout (the rows at opacity 0)")
check(mainFlight.vis == VIS.Hidden, "the game's HUD hidden")
for _ = 2, 6 do keys.V() end
tick(1)
check(#cams == 6 and pc.vt == cams[6] and cams[1].destroyed and not cams[6].destroyed and said[#said].text == "KEY 6 OF 6 AT 15.0 S",
    "a press each: key 6 of 6, the ones before destroyed")
keys.V()
tick(1)
check(pc.vt == pawn and cams[6].destroyed and mainFlight.vis == 3 and has(find("^cine: preview over", n0), "the view back on your plane"),
    "past the last: back on your plane, the game's HUD back")
check(H.round.op == CFG.hud.opacity and H.widget.vis == VIS.HitTestInvisible, "Survival's rows back at their opacity")

print("a new take")
local cur = fileText(C.file)
n0 = #logs
keys.W()
check(#CINE.keys == 4 and CINE.keys[3].t == 9 and has(fileText(C.prev), "\n6.45     ") and has(fileText(C.file), "\n9        640      -700")
    and not has(fileText(C.file), "6.45") and has(find("^cine: Ctrl%+W, a new take: the 6 keys kept in", n0), "today's camera back (4 keys)"),
    "Ctrl+W: the 6 keys to rise_camera.prev.txt, today's camera back")
check(cur ~= nil and said[#said].text == "NEW TAKE", "its callout")
keys.D()
check(CINE.director() == nil and said[#said].text == "DIRECTOR MODE OFF", "Ctrl+D again: off")

if fails > 0 then print("cine test: " .. fails .. " FAILED"); os.exit(1) end
print("cine test: all passed")
