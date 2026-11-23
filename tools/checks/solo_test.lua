-- solo_test.lua <mod dir> (run by tools/checks/solo_test.sh): the solo nerf of 2026-11-18 (the user: "the Invincible
-- Fleet needs a nerf for solo rounds and so does the Escort Mission"): sv_core.lua soloVal (t.solo[key] while one player
-- flies: solo, a co-op room of one, co-op closed; t[key] with two or more), the escort's solo values on the real
-- sv_config_specials.lua, and the fleet's in sv_fleet.lua's text (a DEV ONLY / TESTER part: its tests are fleet_test.sh's)
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return (s:gsub("\r\n", "\n")) end
local S = MOD .. "/UE4SS/AC8SurvivalMode/Scripts/"
if not io.open(S .. "sv_core.lua", "rb") then S = MOD .. "/Scripts/" end

-- soloVal, taken from sv_core.lua as it ships
local core = readAll(S .. "sv_core.lua")
local a = core:find("\nfunction soloVal%(")
local b = a and core:find("\nend\n", a, true)
check(a ~= nil and b ~= nil, "sv_core.lua has soloVal")
assert(load(core:sub(a, b + 4), "=soloVal"))()

local t = { x = 4, y = 1, solo = { x = 6 } }
COOP = nil
check(soloVal(t, "x") == 6 and soloVal(t, "y") == 1, "solo: solo's where it has one, the table's elsewhere")
COOP = { open = true, players = function() return { {} } end }
check(soloVal(t, "x") == 6, "a co-op room of one: solo's")
COOP.players = function() return { {}, {} } end
check(soloVal(t, "x") == 4, "two players: the table's own")
COOP = { open = false, players = function() return { {}, {} } end }
check(soloVal(t, "x") == 6, "co-op closed: solo's")
COOP = { open = true, players = function() error("boom") end }
check(soloVal(t, "x") == 6, "COOP.players failing: solo's")
COOP = nil
check(soloVal(nil, "x") == nil and soloVal({ x = 2 }, "x") == 2 and soloVal({ x = 2, solo = 5 }, "x") == 2, "no table / no solo / a bad solo")

-- the escort's, on the real config
CFG = nil
local env = setmetatable({}, { __index = _G })
local src = readAll(S .. "sv_config_specials.lua")
local e = src:match("\n    escort = (%b{})")
check(e ~= nil, "sv_config_specials.lua's escort table found")
local esc = e and load("return " .. e, "=escort", "t", env)()
if esc then
    check(soloVal(esc, "health_x") == 6 and esc.health_x == 4, "THE ESCORT solo: her health x6 (x4 in co-op)")
    check(soloVal(esc.attack, "share") == 0.4 and soloVal(esc.attack, "max") == 2 and esc.attack.max == 4,
        "solo: 40 % of the flights after her, 2 at most (60 %, 4 in co-op)")
    local w = esc.waves
    check(soloVal(w, "min_n") == 2 and soloVal(w, "max_n") == 8 and soloVal(w, "every_s") == 60 and soloVal(w, "max_up") == 14
        and soloVal(w, "first_s") == 20 and w.min_n == 4 and w.max_n == 7 and w.every_s == 75 and w.max_up == 16,
        "solo: waves of 2-8 every 60 s, 14 up at most (4-7, 75 s, 16 in co-op since 2026-11-23)")
end

-- the fleet's, in sv_fleet.lua's text and where they're read
local fl = readAll(S .. "sv_fleet.lua")
check(fl:find("geofon_x = 1.5, solo = { hull_x = 0.7 }", 1, true) and fl:find('num(soloVal(fm(), "hull_x"), 1)', 1, true),
    "INVINCIBLE FLEET solo: hulls x0.7 (GEOFON x1.05)")
check(fl:find("damage = 3, solo = { damage = 2 }", 1, true) and readAll(S .. "sv_fleet_round.lua"):find('n(soloVal(c, "damage"), 6)', 1, true),
    "solo: the shelling 2 a salvo (3)")
local rail = readAll(S .. "sv_tanicorn_rail.lua")
local _, nEvery = rail:gsub('num%(soloVal%(c, "every_s"%), 90%)', "")
check(fl:find("solo = { damage = 60, every_s = 120 }", 1, true) and rail:find('num(soloVal(c, "damage"), 100)', 1, true) and nEvery == 3,
    "solo: the railcannon 60 every 120 s (100 every 90)")
check(fl:find("core_floor = 0.02, solo = { core_missiles = 20 }", 1, true)
    and readAll(S .. "sv_fleet_round.lua"):find('n(soloVal(c, "core_missiles"), 30)', 1, true), "solo: her core 20 missiles (30)")

print(fails == 0 and "solo test: all passed" or ("solo test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
