-- quit_cdo_test.lua <mod dir> <work dir> (run by tools/checks/quit_cdo_test.sh): 0.73.84, Shazzy's crash on quit of
-- 2026-11-04 19:49:19 (0.73.82, round 24 with GUN tier 2: UE4SS.dll+0x2ab5bd, a Lua property lookup of "damage" on a
-- freed object, 0.1 s after the teardown gate closed). runLeft's TAC.reset wrote the gun's stock damage back into its
-- class default (BP_plwp_gun_x1_C's, loaded with the level) after the level's purge had freed it. On the real sv_core,
-- sv_config, sv_ai, sv_hud and sv_tactical (sv_ladon's and sv_anomalies' text), the game stubbed; a freed object here
-- counts every read or write of it as the crash it would be:
--   the gun: UP.apply keeps the class default and its stock (UP.gunStock, by the class's name, for the session); the
--     gate closing (levelGate: SV_LevelGone 1, levelDrop) then TAC.reset with the class default freed touches nothing
--     and logs it forgotten (the 0.73.83 code touches it: the crash); a live one is put back to stock (a restart, a new
--     run); an address another object took since (same address, another name) isn't touched; the class loaded again
--     (a new class default) takes its stock from UP.gunStock, never from a value left upgraded;
--   VALKA's sky: levelDrop forgets RED.b (its "VALKA's sky" drop) and hudRed's at-once path touches nothing while the
--     level's torn down or its sky actor is gone; with both live it puts the sky back as before;
--   the Ladon missile's class default: HIT.reset forgets it, every use is liveObj (no valid(HIT.cdo)); VALKA's flare's
--     removal liveObj too.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's objects: LIVE[addr] true while the engine holds it; a freed one counts each read / write as a crash
VERSION = "0.73.84-quit.test"
local LIVE, crashes = {}, 0
local Om = {}
Om.__index = function(t, k)
    if not LIVE[rawget(t, "addr")] then crashes = crashes + 1; return nil end
    local p = rawget(t, "props")
    if p[k] ~= nil then return p[k] end
    return nil
end
Om.__newindex = function(t, k, v)
    if not LIVE[rawget(t, "addr")] then crashes = crashes + 1; return end
    rawget(t, "props")[k] = v
end
local function obj(addr, full, props)
    LIVE[addr] = true
    return setmetatable({ addr = addr, full = full, props = props or {} }, Om)
end
function SV_ObjChain(a) return LIVE[a] and 1 or 0 end
function FName(s) return s end
function NotifyOnNewObject() end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function SV_UnitAlive() return 0 end
local activators = {}
function FindAllOf(cls) if cls == "LivePlayerWeaponActivator" then return activators end return {} end

local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
-- (UE4SS's own, as the tests stub them: an object's address and full name without reading it)
function addrOf(o) return type(o) == "table" and rawget(o, "addr") or nil end
function nameOf(o) if type(o) ~= "table" then return "?" end if SV_ObjChain(rawget(o, "addr")) == 0 then return "?" end return rawget(o, "full") or "?" end
-- (UE4SS's IsValid reads the object itself: a freed one is a crash here, as hotfix2 found)
function valid(o)
    if type(o) ~= "table" then return false end
    if not LIVE[rawget(o, "addr")] then crashes = crashes + 1; return false end
    return true
end
local function line(pat, from) for i = #logs, from or 1, -1 do if logs[i]:find(pat) then return logs[i] end end return nil end
part("sv_config.lua"); part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_sound.lua"); part("sv_spawn.lua")
part("sv_anomalies.lua"); part("sv_rounds.lua"); part("sv_tactical.lua")
D = { round = 24 }
RUN = { ups = { gun = 2 } }
CFG.upgrades.enabled, CFG.upgrades.gun_experimental = true, true

local GUN = "/Game/Blueprints/Weapons/Gun/Player/BP_plwp_gun_x1.BP_plwp_gun_x1_C"
local function gunClass(cdo) return { addr = 0x5000, full = GUN, GetCDO = function() return cdo end } end
local cdo1 = obj(0x17A9770DC0, "BP_plwp_gun_x1_C /Game/Blueprints/Weapons/Gun/Player/BP_plwp_gun_x1.Default__BP_plwp_gun_x1_C", { damage = 15 })
local pawn = obj(0x9000, "LivePlayerPlane", { MaxHealth = 100, HealthInternal = 1000 })
local act = obj(0x9100, "LivePlayerWeaponActivator", { MaxFlareCount = 6, MachineGunClass = gunClass(cdo1) })
rawget(act, "props").GetOwner = function() return pawn end
activators[1] = act
LIVE[0x5000] = true

---------------------------------------------------------------------------------------------------- the gun
print("the gun's class default (TAC.reset, UP.apply)")
local step = 0
for _, it in pairs(CFG.shop.items) do if it.role == "upgrade" and it.up == "gun" then step = it.step end end
local want2 = 15 * (1 + step * 2)
UP.apply(pawn)
local g = UP.gunBase[GUN]
check(g and rawget(cdo1, "props").damage == want2 and UP.gunStock[GUN] == 15, string.format(
    "GUN tier 2: the class default kept, its damage 15 -> %.2f, its stock 15 kept for the session", want2))
check(g and g.full == rawget(cdo1, "full"), "kept with its full name")

-- the teardown gate closes (SV_LevelGone 1) as the purge frees the gun's class default with the level
local from = #logs + 1
LIVE[0x17A9770DC0] = nil
function SV_LevelGone() return 1 end
check(levelGate() == true and levelTorn(), "the gate closes: the level torn down")
check(has(line("^level gate: closed", from), "VALKA's sky"), "levelDrop: VALKA's sky among the drops: " .. tostring(line("^level gate: closed", from)))
crashes = 0
TAC.reset()                                      -- (runLeft's, right after the leaderboard's lines)
check(crashes == 0, "TAC.reset: the freed class default not read or written (" .. crashes .. " touches)")
check(next(UP.gunBase) == nil, "UP.gunBase emptied")
check(line("^upgrades: 1 gun class default gone with the level: forgotten, not touched", from) ~= nil, "logged: forgotten, not touched")
do                                               -- (0.73.83's line touches it: the crash this fixes)
    UP.gunBase[GUN] = g
    crashes = 0
    for _, x in pairs(UP.gunBase) do pcall(function() x.cdo.damage = x.damage end) end
    check(crashes > 0, "(the 0.73.83 TAC.reset's line reads the freed class default: the crash)")
    UP.gunBase = {}
end
function SV_LevelGone() return 0 end
levelGate()
LEAVE.reset()

-- a live one (a restart, a new run) back to stock
local cdo2 = obj(0x6000, "BP_plwp_gun_x1_C /Game/Blueprints/Weapons/Gun/Player/BP_plwp_gun_x1.Default__BP_plwp_gun_x1_C", { damage = want2 })
rawget(act, "props").MachineGunClass = gunClass(cdo2)
UP.apply(pawn)
check(UP.gunBase[GUN] and UP.gunBase[GUN].damage == 15 and rawget(cdo2, "props").damage == want2,
      "the class loaded again holding an upgraded value: its stock from UP.gunStock (15), not the " .. want2 .. " it holds")
RUN.ups.gun = 1
UP.apply(pawn)
check(math.abs(rawget(cdo2, "props").damage - 15 * (1 + step)) < 1e-9, "tier 1 on it: 15 x (1 + step), not compounded")
crashes = 0
TAC.reset()
check(crashes == 0 and rawget(cdo2, "props").damage == 15, "TAC.reset with it live: back to 15")

-- an address another object took since: not touched
RUN.ups.gun = 2
UP.apply(pawn)
local g2 = UP.gunBase[GUN]
rawset(cdo2, "full", "SomethingElse /Game/Other.Default__Other_C")
rawget(cdo2, "props").damage = 99
TAC.reset()
check(rawget(cdo2, "props").damage == 99 and next(UP.gunBase) == nil, "the slot holds another object (another name): not written")
rawset(cdo2, "full", g2.full)

-- mid-run, its class loaded again (the kept one gone): taken again, the stock kept
UP.gunBase[GUN] = g2
LIVE[0x6000] = nil
local cdo3 = obj(0x7000, "BP_plwp_gun_x1_C /Game/Blueprints/Weapons/Gun/Player/BP_plwp_gun_x1.Default__BP_plwp_gun_x1_C", { damage = 15 })
rawget(act, "props").MachineGunClass = gunClass(cdo3)
crashes = 0
UP.apply(pawn)
check(crashes == 0 and UP.gunBase[GUN].cdo == cdo3 and rawget(cdo3, "props").damage == want2,
      "a kept class default gone mid-run: the new one taken (" .. crashes .. " touches of the old)")

---------------------------------------------------------------------------------------------------- VALKA's sky
print("VALKA's sky (hudRed at once, levelDrop)")
local sets = 0
local sun = obj(0x8100, "DirectionalLightComponent")
rawget(sun, "props").SetLightColor = function() sets = sets + 1 end
local sky = obj(0x8000, "LiveCloudlyActor")
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
local dropped = 0
for name, fn in pairs(LEVEL_DROPS) do if name == "VALKA's sky" then fn("test"); dropped = dropped + 1 end end
check(dropped == 1 and RED.b == nil, "LEVEL_DROPS[\"VALKA's sky\"] forgets RED.b")
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
LEAVE.gone = true                                -- (levelTorn)
crashes, from = 0, #logs + 1
hudRed(false, nil, true)
check(sets == 0 and crashes == 0 and RED.b == nil and line("^hud: the sky's level is gone: nothing put back", from) ~= nil,
      "hudRed at once while the level's torn down: nothing touched, forgotten")
LEAVE.gone = nil
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
LIVE[0x8000], LIVE[0x8100] = nil, nil
crashes = 0
hudRed(false, nil, true)
check(sets == 0 and crashes == 0 and RED.b == nil, "its sky actor gone (not torn yet): nothing touched")
LIVE[0x8000], LIVE[0x8100] = true, true
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
from = #logs + 1
hudRed(false, nil, true)
check(sets == 1 and RED.b == nil and line("^hud: the sky put back as it was %(at once%)", from) ~= nil, "both live: the sky put back as before")
RED.b, RED.want = { actor = sky, sun = sun, sunCol = { 1, 1, 1 }, rend = {} }, true
LIVE[0x8100] = nil                               -- (a component freed before its actor)
crashes, sets = 0, 0
hudRed(false, nil, true)
check(crashes == 0 and sets == 0, "a kept sky component gone, its actor not: that one not touched (liveObj, not valid)")

---------------------------------------------------------------------------------------------------- the shuttle pad
print("the shuttle pad (SHUTTLE.gone / pad / obj: the review of the fix)")
function svFlags() return {} end
local function padObj(addr, name)
    local o = obj(addr, name, { bShowHUDBox = true, bIsNotLockonTarget = false, bIsNotFCSTargets = false, bIsInvincible = false })
    local p = rawget(o, "props")
    p.calls = 0
    for _, m in ipairs({ "SetActorHiddenInGame", "SetActorEnableCollision", "SetActorTickEnabled" }) do
        p[m] = function() p.calls = p.calls + 1 end
    end
    return o
end
local pa = padObj(0xA000, "BP_SAM_C /Game/Maps/Survival/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.SAM_1")
local pb = padObj(0xA100, "BP_Dummy_C /Game/Maps/Survival/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.Dummy_2")
SHUTTLE.pad, SHUTTLE.gone, SHUTTLE.padAt = { SV_Unit_PadDummies = { pa, pb } }, {}, nil
SPC.shuttleTakeOff(true)                         -- (round 12's take-off: the pad hidden, kept)
check(#SHUTTLE.gone == 2 and rawget(pa, "props").bIsInvincible == true and rawget(pa, "props").calls == 3
      and SHUTTLE.gone[1].name == rawget(pa, "full"), "the pad hidden and kept with each object's name")
-- the quit: the gate's drop, then the level's purge frees them
local droppedPad = 0
for name, fn in pairs(LEVEL_DROPS) do if name == "the shuttle pad" then fn("test"); droppedPad = droppedPad + 1 end end
check(droppedPad == 1 and #SHUTTLE.gone == 0 and SHUTTLE.pad == nil and SHUTTLE.obj == nil,
      "LEVEL_DROPS[\"the shuttle pad\"] forgets SHUTTLE.gone, SHUTTLE.pad and SHUTTLE.obj")
LIVE[0xA000], LIVE[0xA100] = nil, nil
crashes = 0
SPC.shuttlePadBack()                             -- (the next run's first shuttle round, spawnShuttle's first call)
check(crashes == 0, "the next run's shuttlePadBack: nothing of the old level touched")
-- without the drop (as 0.73.83 kept them): freed, or an address another object took, is not touched
LIVE[0xA000], LIVE[0xA100] = true, true
rawget(pa, "props").calls, rawget(pb, "props").calls = 0, 0
SHUTTLE.pad, SHUTTLE.gone = { SV_Unit_PadDummies = { pa, pb } }, {}
SPC.shuttleTakeOff(true)
LIVE[0xA000] = nil
rawset(pb, "full", "Another /Game/Other.Other:PersistentLevel.X")
crashes, rawget(pb, "props").calls = 0, 0
SPC.shuttlePadBack()
check(crashes == 0 and rawget(pb, "props").calls == 0 and rawget(pb, "props").bIsInvincible == true,
      "kept ones freed or another object's now: neither touched (liveObj and the name, not valid())")
-- a restart keeps the level (no drop): the hidden pad comes back as it was
rawset(pb, "full", "BP_Dummy_C /Game/Maps/Survival/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.Dummy_2")
LIVE[0xA000] = true
rawget(pa, "props").calls, rawget(pb, "props").calls = 0, 0
for k, v in pairs({ bShowHUDBox = true, bIsNotLockonTarget = false, bIsNotFCSTargets = false, bIsInvincible = false }) do rawget(pa, "props")[k] = v end
SHUTTLE.pad, SHUTTLE.gone = { SV_Unit_PadDummies = { pa, pb } }, {}
SPC.shuttleTakeOff(true)
rawget(pa, "props").calls = 0
SPC.shuttlePadBack()
check(rawget(pa, "props").calls == 3 and rawget(pa, "props").bIsInvincible == false and rawget(pa, "props").bShowHUDBox == true,
      "live under its name (a restart): shown, collision and tick back, its flags as they were")
-- the take-off's own read of a kept pad list: liveAddr, not valid()
LIVE[0xA100] = nil
SHUTTLE.pad, SHUTTLE.gone = { SV_Unit_PadDummies = { pb } }, {}
crashes = 0
SPC.shuttleTakeOff(true)
check(crashes == 0 and #SHUTTLE.gone == 0, "shuttleTakeOff: a freed object of SHUTTLE.pad not read")
LIVE[0xA100] = true
local srcR = readAll(MOD .. "/Scripts/sv_rounds.lua") .. readAll(MOD .. "/Scripts/sv_spawn.lua")
check(not has(srcR, "valid(SHUTTLE.obj)") and not has(srcR, "valid(sh)"), "SHUTTLE.obj / sh read with liveObj, never valid()")

---------------------------------------------------------------------------------------------------- VALKA's song's mute
print("VALKA's song's mute (a quit during it: the review of the fix)")
local bgmR, posts = -6, {}
function SV_PlayBGM(n) posts[#posts + 1] = n; return bgmR end
function SV_SndStop() return 1 end
function SV_SndSet() return 1 end
SND.song = { h = 7, muted = true, v = 0.9, top = 0.9 }
from = #logs + 1
SND.stopAll()                                    -- (runLeft's, the gate closed: the runtime refuses the post)
check(SND.song == nil and SND.unmuteDue == true and posts[#posts] == "AKE_System_BGM_Mute_Off"
      and has(line("^sound: the game's music back after the song", from), "refused: posted again in the next level"),
      "the unmute refused as the level goes: due, logged")
clock = clock + 5
D = { round = 1 }
bgmR = -1
SND.tick()
check(SND.unmuteDue == true, "the next level's sound tick: refused once more, still due")
SND.tick()
check(#posts == 2, "not asked again within 2 s (" .. #posts .. " posts)")
clock = clock + 2.5
bgmR = 4242
from = #logs + 1
SND.tick()
check(SND.unmuteDue == nil and line("^sound: the game's music unmuted", from) ~= nil, "posted once the runtime takes it: unmuted, logged")
SND.unmuteDue, SND.unmuteTries, SND.unmuteAt = true, 0, nil
SND.song = { h = 8, muted = true }
SND.tick()
check(SND.unmuteDue == nil, "a song of the new level holding the mute: left to its own end")
SND.song = nil
SND.unmuteDue, SND.unmuteTries, SND.unmuteAt = true, 0, nil
bgmR = -6
for _ = 1, 16 do clock = clock + 2.1; SND.tick() end
check(SND.unmuteDue == nil and line("^sound: the game's music NOT unmuted after 15 tries") ~= nil, "15 refusals: given up, logged")
SND.song = { h = 9, muted = true, v = 1, top = 1 }
bgmR = 77
SND.songStop(true)
check(SND.unmuteDue == nil, "a song's end posted while the level lives: nothing due")

---------------------------------------------------------------------------------------------------- the Ladon, the flare
print("the Ladon missile's class default, VALKA's flare")
local ladon = readAll(MOD .. "/Scripts/sv_ladon.lua")
check(not has(ladon, "valid(HIT.cdo)") and has(ladon, "liveObj(HIT.cdo)"), "sv_ladon: no valid(HIT.cdo), liveObj on every use")
local reset = ladon:match("function HIT%.reset%(%)(.-)\nend")
check(reset and has(reset, "HIT.cdo = nil"), "HIT.reset (the level's drop, runLeft) forgets it")
local an = PARTS.read("sv_anomalies.lua")
local fs = an:match("function SPC%.V%.flareStop%(s%)(.-)\nend")
check(fs and has(fs, "liveObj(a)") and not has(fs, "valid(a)"), "SPC.V.flareStop: liveObj before its K2_DestroyActor")

print(fails == 0 and "quit_cdo_test: all passed" or ("quit_cdo_test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
