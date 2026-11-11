-- pad_test.lua <mod dir> <work dir> (run by tools/checks/pad_test.sh): the shuttle's pad taken off after liftoff (user's
-- run of 2026-10-30: "spaceport did not despawn after shuttle round"; the take-off hid what was within 1.5 km of the
-- shuttle, "16 objects hidden" in every log, and the control centre, its 3 dummies and a SAM site stand 1.6-2.0 km out),
-- on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn and sv_rounds, the game stubbed:
--   spawnShuttle: each pad unit's objects recorded as SV_Spawn makes them (SHUTTLE.pad), nothing made otherwise;
--   SPC.shuttleTakeOff: (2026-11-11) the shuttle killed by ModifyHealth (sv_core.lua finishUnpaid; GameplayStatics.
--     ApplyDamage takes nothing off AC8's AI objects, stubbed so), one that can't be said with its health and hidden;
--     every recorded object hidden (hidden, no collision, no tick, no target box, no lock, invincible),
--     those 2 km out too, each once; the 1.5 km sweep still takes anything else close, nothing farther, no aircraft;
--     the log line's counts;
--   the next shuttle round: the pad's objects back (its units still up, not spawned again), then hidden again;
--   a new run (the pad's units gone): a fresh record, the old objects left alone;
--   (0.73.80) the spawner refusing the shuttle (-3, its last one still on its list): SV_Recycle(unit, 1) and spawned
--     again; refused again: a normal round from the start (sv_rounds.lua SPC.unplan: its strike flights out, as many
--     fighters' aircraft in, its pick and cooldown given back, the pad hidden again, a normal round's callout).
-- The objects' places are the world data's (WD_SurvivalMode_global: SV_Unit_PadDummies, AA_Unit_01_Ground0).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end

local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.72.4-pad.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
local notify = {}
function NotifyOnNewObject(cls, f) notify[#notify + 1] = { cls = cls, f = f } end
local world = {}                                  -- every object made, for FindAllOf
local PLANE_CLS = { full = "/Script/Live.LiveAIPlane" }
-- ((2026-11-11) Saint Alessia's run: "the shuttle damage applied" and 1 alive 5 s on: ApplyDamage takes nothing off
-- AC8's AI objects, ModifyHealth does (not while invincible, never under the MinHealth field)
local damaged = 0
local GS = { full = "Default__GameplayStatics" }
function GS:ApplyDamage(o) damaged = damaged + 1 end
-- (0.73.79) a class's walk finds its subclasses' objects too, as UE4SS's FindAllOf does: the take-off walks
-- LiveAIGameObject only now (the ground dummies, ground vehicles and planes are LiveAIGameObjects)
local SUPER = { LiveAIGroundDummy = "LiveAIGameObject", LiveAIGroundVehicleObject = "LiveAIGameObject", LiveAIPlane = "LiveAIGameObject" }
WALKS = {}
function FindAllOf(cls)
    if cls == "LiveEventContainer" then return {} end
    WALKS[#WALKS + 1] = cls
    local t = {}
    for _, o in ipairs(world) do
        local c = o.cls
        while c do
            if c == cls then t[#t + 1] = o; break end
            c = SUPER[c]
        end
    end
    return t
end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject(p)
    if p == "/Script/Live.LiveAIPlane" then return PLANE_CLS end
    if p == "/Script/Engine.Default__GameplayStatics" then return GS end
    return nil
end
function playerOnAirfield() return false end
function SV_Event() return 1 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

local nextAddr = 100
local Obj = {}
Obj.__index = Obj
function Obj:GetAddress() return self.addr end
function Obj:K2_GetActorLocation() return { X = self.X, Y = self.Y, Z = 600000 } end
function Obj:SetActorHiddenInGame(b) self.hidden = b end
function Obj:SetActorEnableCollision(b) self.collision = b end
function Obj:SetActorTickEnabled(b) self.tick = b end
function Obj:IsA(c) return c == PLANE_CLS and self.plane == true end
function Obj:SetIsInvincible(b) self.inv = b end
function Obj:SetMinHealth() end
function Obj:ModifyHealth(dh, causer, ev)
    self.mods = (self.mods or 0) + 1
    if self.tough or self.inv or self.HealthInternal == nil then return 0 end
    self.HealthInternal = math.max(math.floor((self.MinHealth or 0) * 10), self.HealthInternal + dh * 10)
end
-- an object made by the spawner: every LiveAIGameObject callback sees it (LiveAIGroundDummy is one: SPECIAL_ROUNDS.md)
local function make(name, cls, xkm, ykm, plane)
    nextAddr = nextAddr + 1
    local o = setmetatable({ full = name, name = name, cls = cls, addr = nextAddr, X = xkm * 100000, Y = ykm * 100000,
                             bShowHUDBox = true, bIsNotLockonTarget = false, bIsNotFCSTargets = false, bIsInvincible = false,
                             hidden = false, collision = true, tick = true, plane = plane }, Obj)
    world[#world + 1] = o
    for _, n in ipairs(notify) do if n.cls == "/Script/Live.LiveAIGameObject" then n.f(o) end end
    return o
end
-- the units' objects where the world data puts them (km)
local UNITS = {
    SV_Unit_PadDummies = { { "Shuttle_Dummy_Point0", -13.249, 0.597 }, { "Shuttle_Dummy_0", -13.294, 0.661 },
        { "Shuttle_Dummy_1", -13.201, 0.561 }, { "Shuttle_Dummy_2", -13.399, 0.498 }, { "Shuttle_Dummy_3", -13.207, 0.755 },
        { "Shuttle_Dummy_4", -13.127, 0.541 }, { "Tower_Dummy0", -14.977, 1.334 }, { "Tower_Dummy1", -14.860, 1.467 },
        { "Tower_Dummy2", -14.946, 1.638 } },
    AA_Unit_01_Ground0 = { { "AAGUN_0", -14.441, 1.478, "gepa" }, { "AAGUN_1", -13.384, 1.310, "gepa" },
        { "AAGUN_2", -13.850, 1.685, "gepa" }, { "AAGUN_3", -14.050, 0.945, "gepa" }, { "AAGUN_4", -13.579, -0.405, "gepa" },
        { "AAGUN_5", -12.855, -0.193, "gepa" }, { "SAM0", -12.936, -0.276, "avng" }, { "SAM1", -14.583, 1.510, "avng" },
        { "SAM2", -13.863, 1.596, "avng" }, { "SAM3", -13.574, -0.257, "avng" }, { "Tower_0", -14.973, 1.501, "ctrl" } },
}
local alive = {}
local spawned = {}
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_Spawn(u)
    spawned[#spawned + 1] = u
    if u == "SV_Unit_Shuttle" then
        SHUTTLE_ACTOR = make("BP_OP0057_sstb_CP_C_" .. nextAddr, "LiveAIPlane", -13.249, 0.597, true)
        SHUTTLE_ACTOR.HealthInternal, SHUTTLE_ACTOR.inv = 9300, true
        alive[u] = 1
        return 1
    end
    local l = UNITS[u]
    if not l then return -1 end
    for _, d in ipairs(l) do
        make("AA_Obj_01_Ground0_" .. d[1] .. "_" .. nextAddr, d[4] and "LiveAIGroundVehicleObject" or "LiveAIGroundDummy", d[2], d[3])
    end
    alive[u] = #l
    return #l
end

local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
function svFlags() return { SV_ShuttleLaunched = 1 } end
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function lastLog(pat) for i = #logs, 1, -1 do if logs[i]:find(pat) then return logs[i] end end end
local function padObjs()
    local t = {}
    for _, o in ipairs(world) do if not o.gone and o.name:find("^AA_Obj_01_Ground0_") then t[#t + 1] = o end end
    return t
end
local function gone(o)                            -- hidden as the take-off hides
    return o.hidden == true and o.collision == false and o.tick == false and o.bShowHUDBox == false
           and o.bIsNotLockonTarget == true and o.bIsNotFCSTargets == true and o.bIsInvincible == true
end
local function back(o)
    return o.hidden == false and o.collision == true and o.tick == true and o.bShowHUDBox == true
           and o.bIsNotLockonTarget == false and o.bIsNotFCSTargets == false and o.bIsInvincible == false
end
local function count(l, f) local n = 0; for _, o in ipairs(l) do if f(o) then n = n + 1 end end; return n end
local function round()
    D = D or {}
    D.round, D.now, D.special = 2, 100, { kind = "shuttle", state = "pending" }
end

---------------------------------------------------------------------------------------------------- spawnShuttle
print("spawnShuttle: the pad's objects recorded as they're made")
round()
local r = spawnShuttle()
local pad = padObjs()
check(r == 1 and #pad == 20, "the pad's 20 objects and the shuttle up (" .. #pad .. ")")
check(SHUTTLE.pad and #SHUTTLE.pad.SV_Unit_PadDummies == 9 and #SHUTTLE.pad.AA_Unit_01_Ground0 == 11,
      "recorded: 9 dummies, 11 guns, SAMs and the control centre")
check(SHUTTLE.padSpawning == nil, "the record closed after the spawns")
make("BP_OP1022_f16c_CP_C_9001", "LiveAIPlane", -13.3, 0.6, true)          -- (made after: never recorded)
check(#SHUTTLE.pad.SV_Unit_PadDummies == 9 and #SHUTTLE.pad.AA_Unit_01_Ground0 == 11, "objects made later aren't recorded")

---------------------------------------------------------------------------------------------------- shuttleTakeOff
print("SPC.shuttleTakeOff: the whole pad hidden")
local near = make("BP_GR_stranger_near", "LiveAIGroundVehicleObject", -13.0, 0.6)      -- 0.25 km: the sweep's
local far = make("BP_GR_stranger_far", "LiveAIGroundVehicleObject", -15.3, 0.6)        -- 2.05 km, not the pad's
local jet = make("BP_OP1022_f16c_CP_C_9002", "LiveAIGameObject", -13.25, 0.6, true)   -- an aircraft at the pad
SHUTTLE.obj = SHUTTLE_ACTOR
SHUTTLE.padAt = { X = -13.249 * 100000, Y = 0.597 * 100000 }
local from = #logs + 1
WALKS = {}
SPC.shuttleTakeOff()
check(#WALKS == 1 and WALKS[1] == "LiveAIGameObject", "(0.73.79) one walk, LiveAIGameObject's (" .. table.concat(WALKS, ", ") .. ")")
check(count(pad, gone) == 20, "all 20 of the pad's objects hidden (" .. count(pad, gone) .. ")")
local far5 = {}
for _, o in ipairs(pad) do
    local d = math.sqrt((o.X - SHUTTLE.padAt.X) ^ 2 + (o.Y - SHUTTLE.padAt.Y) ^ 2) / 100
    if d > 1500 then far5[#far5 + 1] = o end
end
check(#far5 == 5 and count(far5, gone) == 5, "the 5 beyond 1.5 km (control centre, its dummies, SAM1) too")
check(gone(SHUTTLE_ACTOR) and SHUTTLE_ACTOR.HealthInternal == 0 and damaged == 0, "the shuttle killed (by ModifyHealth: ApplyDamage takes nothing) and hidden")
check(gone(near) and not far.hidden and not jet.hidden, "the sweep: a stranger within 1.5 km hidden, not one 2 km out, no aircraft")
check(#SHUTTLE.gone == 21, "each kept once to bring back (" .. #SHUTTLE.gone .. ")")
local l = lastLog("shuttle and pad off")
check(since(from, "shuttle and pad off") == 1 and l and l:find("the shuttle killed (damage event); 22 objects hidden (20 of them the pad's own, as spawned)", 1, true),
      "logged: " .. tostring(l))

---------------------------------------------------------------------------------------------------- the next shuttle round
print("the next shuttle round: the pad back, not spawned again")
alive.SV_Unit_Shuttle = 0
spawned = {}
round()
spawnShuttle()
check(#spawned == 1 and spawned[1] == "SV_Unit_Shuttle", "only the shuttle spawned (" .. table.concat(spawned, ", ") .. ")")
check(count(pad, back) == 20 and back(near), "the pad's objects back as they were")
check(#SHUTTLE.pad.SV_Unit_PadDummies == 9 and #SHUTTLE.pad.AA_Unit_01_Ground0 == 11, "the record kept")
SHUTTLE.obj = SHUTTLE_ACTOR
SHUTTLE_ACTOR.tough = true                      -- (one ModifyHealth can't take down: said, hidden all the same)
from = #logs + 1
SPC.shuttleTakeOff()
check(count(pad, gone) == 20, "and hidden again after its liftoff")
check(gone(SHUTTLE_ACTOR) and SHUTTLE_ACTOR.HealthInternal == 9300 and since(from, "the shuttle NOT killed %(health 9300 after ModifyHealth and ApplyDamage%)") == 1,
      "a shuttle that can't be finished: said with its health, hidden all the same (" .. tostring(lastLog("shuttle and pad off")) .. ")")

---------------------------------------------------------------------------------------------------- a new run
print("a new run: a fresh record")
for _, o in ipairs(world) do o.gone = true end
alive = {}
round()
spawnShuttle()
local pad2 = padObjs()
check(#pad2 == 20 and #SHUTTLE.pad.SV_Unit_PadDummies == 9 and #SHUTTLE.pad.AA_Unit_01_Ground0 == 11,
      "the pad spawned again, its new objects recorded, the old ones dropped")
SHUTTLE.obj = SHUTTLE_ACTOR
SPC.shuttleTakeOff()
check(count(pad2, gone) == 20, "all 20 hidden after that liftoff")

---------------------------------------------------------------------------------------------------- (0.73.80) refused
-- (R30_FINDINGS specials 0: rounds 17 and 30 of the test of 2026-11-04, "not spawned (its last flight is still up)", the
-- strike flown as a plain raid) the spawner refuses a unit whose last spawn is still on its list (-3)
print("(0.73.80) the shuttle's last one still on the spawner's list: taken off and spawned again; refused twice: a normal round")
local callouts = {}
hudCallout = function(text, sub) callouts[#callouts + 1] = tostring(text) .. " / " .. tostring(sub) end
local rawSpawnStub = SV_Spawn
local recycled, recycleTakes = {}, true
SV_Spawn = function(u)
    if u == "SV_Unit_Shuttle" and (alive[u] or 0) > 0 then spawned[#spawned + 1] = u .. " refused"; return -3 end
    return rawSpawnStub(u)
end
SV_Recycle = function(u, force)
    recycled[#recycled + 1] = u .. ":" .. tostring(force)
    if recycleTakes then alive[u] = 0 end
    return 1
end
alive.SV_Unit_Shuttle = 1                       -- (the last one, killed and hidden at its liftoff, still on the list)
spawned = {}
round()
from = #logs + 1
local r2 = spawnShuttle()
check(r2 == 1 and recycled[1] == "SV_Unit_Shuttle:1" and spawned[1] == "SV_Unit_Shuttle refused" and spawned[2] == "SV_Unit_Shuttle"
      and D.special and D.special.state == "countdown",
      "refused (-3): SV_Recycle(unit, 1), spawned again, on the pad, its countdown on (" .. table.concat(spawned, ", ") .. ")")
check(since(from, "its last one taken off the spawner's list %(SV_Recycle 1%), spawned again: on the pad") == 1, "logged")
SHUTTLE.obj = SHUTTLE_ACTOR
SPC.shuttleTakeOff()
D.shuttleClock = nil
-- refused again after the recycle: a normal round from the start
recycleTakes, recycled, spawned, callouts = false, {}, {}, {}
alive.SV_Unit_Shuttle = 1
round()
local STRIKE = CFG.airfield.bombers.pool[1]
D.up, D.flown, D.strikeUnits, D.taken = {}, {}, { [STRIKE] = true }, { [STRIKE] = true }
D.queue = { STRIKE }
D.waves, D.wave = { D.queue }, 1
RUN.specialPick, RUN.specialAt = { [2] = "shuttle" }, { shuttle = 2 }
D.specialAtWas = { kind = "shuttle", at = nil }
local actorBefore = SHUTTLE_ACTOR
local hiddenBefore = actorBefore.hidden
from = #logs + 1
local r3 = spawnShuttle()
local strikeLeft, fighters = false, 0
for _, u in ipairs(D.queue) do if u == STRIKE then strikeLeft = true elseif poolIndex(u) then fighters = fighters + flightSize(u) end end
check(r3 == -3 and #recycled == 1 and D.special == nil and D.shuttleClock == nil,
      "refused twice: no shuttle, no countdown (" .. tostring(r3) .. ")")
check(not strikeLeft and not D.taken[STRIKE] and fighters == flightSize(STRIKE) and next(D.strikeUnits) == nil,
      "its strike flight out of the round, as many fighters' aircraft in (" .. fighters .. "; it flew on as a plain raid)")
check(RUN.specialPick[2] == false and RUN.specialAt.shuttle == nil, "its pick and its cooldown given back")
check(count(pad2, gone) == 20 and actorBefore.hidden == hiddenBefore, "the pad hidden again, nothing else touched")
check(#callouts == 1 and callouts[1] == string.format(CFG.hud.text.start, 2) .. " / " .. CFG.hud.text.start_sub,
      "a normal round's callout (" .. tostring(callouts[1]) .. ")")
check(since(from, "^round 2: no shuttle after all %(its spawn refused: ") == 1
      and since(from, "its 1 strike flight %(" .. flightSize(STRIKE) .. " aircraft%) out of the round") == 1
      and since(from, "its cooldown given back") == 1, "logged: " .. tostring(lastLog("no shuttle after all")))
SV_Spawn, SV_Recycle = rawSpawnStub, nil

---------------------------------------------------------------------------------------------------- (0.74.22) co-op
-- (the user's co-op run of 2026-11-08, a joiner's log: "this space centre hasn't despawned": a joiner who came in at
-- round 4 got the host's hidden pad, up and shown) the host takes the pad's copies off the joiners' games at each
-- take-off (COOP.removeNow), and announces them again when the next shuttle round brings the pad back (COOP.hostBack)
print("(0.74.22) co-op host: the pad's copies off the joiners' games at its take-off, announced again when it's back")
local removed, announced = {}, {}
COOP = { host = function() return false end, client = function() return false end,
         removeNow = function(u) removed[#removed + 1] = u; return 1 end,
         hostBack = function(u, objs) announced[#announced + 1] = u .. ":" .. #objs; return #objs end }
round()
spawnShuttle()                                  -- (the pad hidden since the last take-off: back, its units still up)
check(#announced == 2 and announced[1] == "SV_Unit_PadDummies:9" and announced[2] == "AA_Unit_01_Ground0:11"
      and count(pad2, back) == 20, "the pad back here and announced again, each unit with its objects (" .. table.concat(announced, ", ") .. ")")
SHUTTLE.obj = SHUTTLE_ACTOR
from = #logs + 1
SPC.shuttleTakeOff()
check(#removed == 2 and removed[1] == "SV_Unit_PadDummies" and removed[2] == "AA_Unit_01_Ground0" and count(pad2, gone) == 20,
      "its take-off: hidden here, both units' copies off the joiners' games (" .. table.concat(removed, ", ") .. ")")
removed = {}
SPC.shuttleTakeOff(true)
check(#removed == 2, "the pad-only take-off too (a shuttle round whose shuttle never came)")
COOP.removeNow = function() error("no link") end
SPC.shuttleTakeOff()
check(since(from, "special: the pad's copies off the joiners' games: error") == 2 and count(pad2, gone) == 20,
      "an error there logged, the pad hidden all the same")
for _, o in ipairs(world) do o.gone = true end
alive, announced = {}, {}
round()
spawnShuttle()
check(#announced == 0 and #padObjs() == 20, "a new run: the pad spawned afresh, nothing announced by hand (the spawn's own mirror does it)")
COOP = nil

logFile:close()
print(fails == 0 and "pad_test: all passed" or ("pad_test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
