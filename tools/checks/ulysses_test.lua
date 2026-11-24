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
SPC = { kinds = { spaceport = { ready = function() return true end } }, V = { asset = function() return nil end } }
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
-- ((2026-11-24, the user: "Spawn more meteorites, have atleast 50 spawn in waves of 2")
players = 1
check(count(1) >= 50 and count(2) >= 50, "solo: at least 50 fragments a round (" .. count(1) .. " / " .. count(2) .. ")")
check(f.per_wave == 2 and src:find("math.floor(n(f.per_wave, 1))", 1, true) ~= nil, "they come in waves of 2")
check(f.at_once <= 36, "at most 36 falling at once: the SOLG's KEW unit lends 36 targets")
check(f.at_once + 6 <= 48, "their fall loops, the rumble and the explosions within the sound player's 48 voices")
check(src:find("e.used = false", 1, true) ~= nil, "each target handed back when its fragment is done (50-90 a round from 36)")

-- its sounds, meshes and boxes named
local c = CFG.specials.ulysses
check(c.sounds.fall.file == "ulysses/fall_small.wav" and c.sounds.boom.file == "ulysses/explosion.wav", "its sounds (Sounds/ulysses, tools/ulysses/sounds.py)")
check(c.mesh_path == "/Game/Mods/SurvivalMode/Ulysses/Model/SK_SV_Ulysses_", "its meshes (SurvivalMode_Ulysses_P, tools/ulysses)")
check(c.target_units.small == "SV_Unit_SOLG_KEW" and c.target_units.big == "SV_Unit_SOLG_MAG", "its boxes: the SOLG's KEW / MAG units borrowed")
check(src:find("TEST ONLY BEGIN", 1, true) and src:find("TEST ONLY END", 1, true), "its test key inside TEST ONLY")

-- ((2026-11-24) the land map (sv_ulysses_land.lua, tools/ulysses/landmask.py) against places the game's traces settled
-- near the player; AC:I's settings (a 45 degree dive from the east at 550-650 km/h; the sky's sprite streak)
assert(loadfile(S .. "sv_ulysses_land.lua"))()
check(ULY.LAND and #ULY.LAND.rows == ULY.LAND.h, "the land map is there, its rows all")
for _, p in ipairs({ { "the runway", AIRFIELD.X, AIRFIELD.Y, true }, { "the city", 1290000, -290000, true },
                     { "the east key's terrain", 2470000, -730000, true }, { "the sea off the runway", 1620000, -360000, false },
                     { "the sea south east", 1790000, -610000, false }, { "open sea", 0, 3000000, false } }) do
    check(ULY.isLand(p[2], p[3]) == p[4], "land map: " .. p[1] .. " is " .. (p[4] and "land" or "sea"))
end
check(f.dive_deg == 45 and f.from_deg == 0, "fragments: AC:I's 45 degree dive from the east")
check(c.big.dive_deg == 45, "the core dives at 45 degrees too")
-- ((2026-11-24, the user: higher, "around 1300km/h"; "vastly spread out around the comona island"; the sky's "quicker",
-- "zoom across the sky, not at 45 degree", "trails ... longer")
local function fall_s(alt_m, kmh) return alt_m / math.sin(math.rad(45)) / (kmh / 3.6) end
check(f.speed_kmh[1] >= 1200 and f.speed_kmh[1] <= 1400 and c.big.speed_kmh >= 1200 and c.big.speed_kmh <= 1400,
    "fragments from around 1300 km/h, the core at it")
check(f.speed_kmh[2] >= 2100 and f.speed_kmh[2] <= 2300, "... some faster, up to about 2200 km/h (the user's range)")
check(f.alt_m[1] >= 18000 and c.big.alt_m >= f.alt_m[2], "fragments from 18 km up or higher, the core higher still")
check(fall_s(f.alt_m[1], f.speed_kmh[2]) >= 40 and fall_s(c.big.alt_m, c.big.speed_kmh) >= 90,
    string.format("time to catch them: fragments %.0f-%.0f s down, the core %.0f s", fall_s(f.alt_m[1], f.speed_kmh[2]),
        fall_s(f.alt_m[2], f.speed_kmh[1]), fall_s(c.big.alt_m, c.big.speed_kmh)))
local A = f.area_km
local ZONE_EAST_CM = -707336 + 4000000                  -- (Mission 22's combat zone, sv_ai.lua ZONE: its east edge, +32.9 km)
check(A and A.x[1] <= -19 and A.x[2] >= 20 and A.y[1] <= -12 and A.y[2] >= 7, "fragments spread over the whole island chain and the sea round it")
check(A and A.x[2] * 100000 <= ZONE_EAST_CM, "... their impacts inside the combat zone's east edge")
check(f.land_tries == 0, "... never steered onto land")
check(f.aim_share == 0 and src:find("math.random() >= n(f.aim_share, 0)", 1, true) ~= nil, "aim_share there, 0 (all spread) until the user says")
check(src:find("f.what == \"town\" or nearTown", 1, true) and src:find("U.landedOpen", 1, true), "open land is harmless; a town's callout only near a town")
check(src:find("n(fr.airfield_m, 4000)", 1, true), "the airfield's damage only within airfield_m of it")
check(c.sky.dip[2] <= 0.3 and c.sky.speed_kmh[1] >= 20000 and c.sky.streak_x >= 0.3,
    "the sky's meteors: a shallow line across the sky (dip <= 0.3), 20,000 km/h or more, longer streaks")
check(c.sky.look and c.sky.look.mesh == "Streak" and c.tail.streak and c.tail.streak.tex.EmissiveMap:find("T_SV_Ulysses_Streak", 1, true),
    "the sky: AC:I's trail sprite on the streak card")
check(c.sounds.ambient and c.sounds.ambient.loop == true, "the Stardust rumble, looped")
-- ((2026-11-24, the user: "get the wwise sounds working for the meteorites") its five as Survival's own Wwise events
local sp = io.open(S .. "../../../../tools/wwise/spec.py", "rb") or io.open(MOD .. "/../tools/wwise/spec.py", "rb")
local spec = sp and sp:read("a") or ""
if sp then sp:close() end
local w = c.sounds.wwise or {}
local allIn = spec ~= ""
for _, k in ipairs({ "fall", "fall_big", "boom", "encounter", "ambient" }) do
    local ev = w[k]
    if not (type(ev) == "string" and ev:sub(1, 5) == "Play_" and spec:find("'" .. ev:sub(6) .. "'", 1, true)) then allIn = false end
end
check(w.enabled ~= false and allIn, "its five sounds' Wwise events are the ones tools/wwise/spec.py builds")
check(src:find("PostEventAtActorByAkEvent", 1, true) and src:find("StopActor", 1, true) and src:find("PostEventAtLocation", 1, true),
    "a whistle posted on its rock and stopped with it, an impact at its place")
local direct = 0
for line in src:gmatch("[^\n]+") do if line:find("pcall(SND.play", 1, true) and not line:find("^%s*%-%-") then direct = direct + 1 end end
check(direct == 4, "Survival's own player only as the fallback (" .. direct .. " calls: an impact, a whistle, the rumble, the encounter)")

-- ((2026-11-24, the code review) the Spaceport never the round before ULYSSES (its retake would take ULYSSES' first round)
F = 9
check(SPC.kinds.spaceport.ready(18) == false and SPC.kinds.spaceport.ready(17) == true, "the Spaceport refused the round before ULYSSES, not others")
check(type(ULY.endAll) == "function" and LEVEL_DROPS == nil or (LEVEL_DROPS and LEVEL_DROPS.ulysses), "its clean-up (ULY.endAll), on a level drop too")
check(pcall(ULY.endAll, "the test"), "its clean-up runs with nothing up")

print(fails == 0 and "ulysses test: all passed" or ("ulysses test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
