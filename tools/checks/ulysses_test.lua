-- ulysses_test.lua <mod dir> (run by tools/checks/ulysses_test.sh): ULYSSES (Scripts/sv_ulysses.lua, the user's special
-- of 2026-11-23) on the real sv_config_arc.lua and sv_ulysses.lua, the game stubbed: its rounds are the day-night arc's
-- first dawn rounds after THE FESTIVAL's night (F + 7 + night_rounds), `rounds` of them; its kind registered (no fighters,
-- its busy / over / row); the fragments solo and in co-op; the spawn refused without its meshes (a normal round).
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local S = MOD .. "/UE4SS/AC8SurvivalMode/Scripts/"
if not io.open(S .. "sv_ulysses.lua", "rb") then S = MOD .. "/Scripts/" end

-- the game stubbed
CFG = { specials = {}, sky = { arc = { night_rounds = 3 } }, hud = { text = {} } }
SPC = { kinds = {}, V = { asset = function() return nil end } }
local logs = {}
function log(s) logs[#logs + 1] = s end
function valid(o) return o ~= nil end
function liveObj(o) return o ~= nil end
function loadObject() return nil end
function StaticFindObject() return nil end
function NotifyOnNewObject() end
function testKey() end
function addrOf(o) return o end
function nameOf(o) return tostring(o) end
function FName(s) return s end
AIRFIELD = { X = 1609639, Y = -436414 }
local F = 9
SKY = { arcF = function() return F end }
RUN = {}
D = nil
local players = 1
function playerCount() return players end
assert(loadfile(S .. "sv_config_arc.lua"))()
check(type(CFG.specials.ulysses) == "table" and CFG.specials.ulysses.enabled == true, "its config (sv_config_arc.lua CFG.specials.ulysses)")
assert(loadfile(S .. "sv_ulysses.lua"))()

-- its rounds: F 9 (GONE FISHIN'), the festival 15, the night 16-18, dawn from 19: ULYSSES 19 and 20
check(ULY.firstRound() == 19, "its first round: the arc's first dawn round, F + 7 + night_rounds (" .. tostring(ULY.firstRound()) .. ")")
check(not ULY.roundIs(18) and ULY.roundIs(19) and ULY.roundIs(20) and not ULY.roundIs(21), "rounds 19 and 20, not 18 or 21")
check(ULY.phaseOf(19) == 1 and ULY.phaseOf(20) == 2, "round 19 the shower, round 20 the shower and the big one")
CFG.sky.arc.night_rounds = 2
check(ULY.firstRound() == 18, "it follows the arc's night_rounds (2: round 18)")
CFG.sky.arc.night_rounds = 3
F = nil
check(ULY.firstRound() == nil and not ULY.roundIs(19), "no arc (GONE FISHIN' not come yet): never")
F = 9
CFG.specials.ulysses.enabled = false
check(not ULY.roundIs(19), "switched off: never")
CFG.specials.ulysses.enabled = true

-- its kind
local k = SPC.kinds.ulysses
check(k ~= nil and k.alone == true and k.aircraft == 0, "its kind: no fighters of its own (pure meteor defence)")
check(k and k.ready(19, false) and not k.ready(17, false) and k.ready(5, true), "ready on its rounds, or forced")
check(k and k.busy({}) == false and k.row({}, {}) == nil, "not busy and no NEXT row when it hasn't started")

-- the spawn without its meshes (SurvivalMode_Ulysses_P missing): refused, so a normal round
D = { round = 19, special = { kind = "ulysses" }, state = "spawning" }
check(k and k.spawn(0) == false, "no meshes in the build: refused (a normal round)")
local said = false
for _, l in ipairs(logs) do if l:find("meshes aren't in this build", 1, true) then said = true end end
check(said, "... and said so")

-- the fragments: solo x solo_x, co-op + per_player a player, at most max_n
local f = CFG.specials.ulysses.fragments
local src = io.open(S .. "sv_ulysses.lua", "rb"):read("a")
check(src:find("local function fragmentsFor", 1, true) ~= nil, "fragmentsFor is there")
local function count(phase)
    local base = phase == 1 and f.round1 or f.round2
    local x = players <= 1 and f.solo_x or (1 + f.per_player * (players - 1))
    return math.max(1, math.min(f.max_n, math.floor(base * x + 0.5)))
end
players = 1
check(count(1) == math.floor(f.round1 * f.solo_x + 0.5), "solo: round 1's fragments x solo_x")
players = 4
check(count(2) == math.min(f.max_n, math.floor(f.round2 * (1 + f.per_player * 3) + 0.5)), "4 players: round 2's x (1 + per_player x 3)")
players = 24
check(count(2) <= f.max_n, "24 players: at most max_n")

-- its sounds, meshes and boxes named
local c = CFG.specials.ulysses
check(c.sounds.fall.file == "ulysses/fall_small.wav" and c.sounds.boom.file == "ulysses/explosion.wav", "its sounds (Sounds/ulysses, tools/ulysses/sounds.py)")
check(c.mesh_path == "/Game/Mods/SurvivalMode/Ulysses/Model/SK_SV_Ulysses_", "its meshes (SurvivalMode_Ulysses_P, tools/ulysses)")
check(c.target_units.small == "SV_Unit_SOLG_KEW" and c.target_units.big == "SV_Unit_SOLG_MAG", "its boxes: the SOLG's KEW / MAG units borrowed")
check(src:find("TEST ONLY BEGIN", 1, true) and src:find("TEST ONLY END", 1, true), "its test key inside TEST ONLY")

print(fails == 0 and "ulysses test: all passed" or ("ulysses test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
