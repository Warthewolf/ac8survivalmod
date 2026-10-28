-- coop_ground_test.lua <mod dir> <work dir> <role: host|join> (run by tools/checks/coop_ground_test.sh): Survival COOP's
-- ships, vehicles and parts (sv_coop.lua groundTick / hostGround / clientGround, "gd"), on the real sv_config.lua and
-- sv_coop.lua (M exposed). Friends' run of 2026-10-26 (coop.11): landing craft didn't die on every game, and a joiner
-- who started over mid-Alicorn got a fresh one, tanks up and core shut.
-- host: spawns two landing craft and an Alicorn (hull, 4 tanks, core, a pooled plane), sinks a craft, a tank and the
--   other tanks, takes a joiner's hit, and answers a joiner who started over; writes what it sent to <work>.
-- join: plays the host's messages on its own copies (built alike) and checks they're bound, held up, sunk with the
--   host's, kept at the host's health, its hits sent, the Alicorn's core opened after its spawn.
local MOD, WORK, ROLE = arg[1], arg[2], arg[3]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end

-- a clock the test moves
local clock = 100
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
local logs = {}
function log(s) logs[#logs + 1] = s end
VERSION = "0.71.0-coop.test"
SCRIPT_DIR = WORK .. "/" .. ROLE .. "/Scripts/"
KILL, LB = { side = function() end }, { send = function() end }
RUN = {}
function roundsTick() end
function airfieldTick() end
function bombTick() end
function logPlane() end
function hudCallout() end
function addCredits() end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return { cls = "LiveAIPlane" } end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.name or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function inSurvival() return true end
function myAirframe() return "f16c" end
function playerOnAirfield() return false end
function gamePaused() return false end
SV_ERR = {}
local sent, inbox, events = {}, {}, {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = (to or -1) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/p" end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_MenuSetting() return "" end
local menu = 0
function SV_MenuChoice() return menu end
function SV_Event(name) events[#events + 1] = name; return 1 end

-- the spawner: each unit's objects, made in the same order on every game (NotifyOnNewObject, then SV_Spawn's return)
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
local nextAddr, world = 0x1000, {}
local function obj(cls, hp, plane)
    nextAddr = nextAddr + 0x10
    local o = { name = cls .. "_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel." .. cls .. "_C_" .. nextAddr,
                addr = nextAddr, HealthInternal = hp, min = 0, plane = plane }
    function o:IsA() return self.plane == true end
    function o:SetMinHealth(v) self.min = v * 10 end
    function o:ModifyHealth(d) self.HealthInternal = math.max(self.min, self.HealthInternal + d * 10) end
    return o
end
local UNITS = {
    SV_Unit_LcacA = { { "BP_SH010_lcac", 5000 }, { "BP_SH010_lcac", 5000 } },
    SV_Unit_Alicorn = { { "BP_BA002_alcn", 90000 }, { "BP_BA002_alcn_btankfl_Base", 18750 }, { "BP_BA002_alcn_btankfr_Base", 18750 },
                        { "BP_BA002_alcn_btankrl_Base", 18750 }, { "BP_BA002_alcn_btankrr_Base", 18750 },
                        { "BP_MP028_dummy_emlmcore_Base", 31250 }, { "BP_FG037_uavm_ON_pool", 100, true } },
}
local alive = {}
function SV_Spawn(unit)
    world[unit] = {}
    for _, d in ipairs(UNITS[unit] or {}) do
        local o = obj(d[1], d[2], d[3])
        world[unit][#world[unit] + 1] = o
        for _, fn in ipairs(notify["/Script/Live.LiveAIGameObject"] or {}) do fn(o) end
    end
    alive[unit] = #world[unit]
    return 1
end
function SV_UnitAlive(unit) return alive[unit] or -7 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end

-- load the real parts (sv_coop with its M exposed)
dofile(MOD .. "/Scripts/sv_config.lua")
local src = readAll(MOD .. "/Scripts/sv_coop.lua"):gsub("\nlocal M = {", "\nM = {", 1)
assert(load(src, "=sv_coop.lua"))()
local M = _G.M
CFG.coop.enabled = true
local function tick(dt) clock = clock + (dt or 0.25); COOP.tick(0); if COOP.client() then roundsTick(clock) end end
local function spawn(unit) spawningUnit = unit; SV_Spawn(unit); spawningUnit = nil end
local function msgs(kind) local t = {}; for _, m in ipairs(sent) do if m:match("^%-?%d+>" .. kind .. "|") then t[#t + 1] = m end end; return t end
local function byKey()
    local t = {}
    for _, m in ipairs(msgs("gd")) do local unit, key, id = m:match("gd|([^|]+)|%d+|([^|]+)|(%d+)"); t[unit .. "/" .. key] = tonumber(id) end
    return t
end

if ROLE == "host" then
    menu = 16 + 3; tick()
    check(COOP.host(), "host: hosting")
    D = { round = 8, state = "fight" }
    tick()
    spawn("SV_Unit_LcacA"); spawn("SV_Unit_Alicorn")
    tick(0.1); check(#msgs("gd") == 0, "host: no ids before the objects are half a second old")
    tick(1)
    local k = byKey()
    check(k["SV_Unit_LcacA/BP_SH010_lcac_C#1"] and k["SV_Unit_LcacA/BP_SH010_lcac_C#2"], "host: both landing craft linked (gd)")
    check(k["SV_Unit_Alicorn/BP_BA002_alcn_C#1"] and k["SV_Unit_Alicorn/BP_BA002_alcn_btankfl_Base_C#1"]
          and k["SV_Unit_Alicorn/BP_MP028_dummy_emlmcore_Base_C#1"], "host: the Alicorn's hull, tanks and core linked")
    check(not k["SV_Unit_Alicorn/BP_FG037_uavm_ON_pool_C#1"], "host: its pooled plane left out (a plane)")
    -- the host's health to every game, and the Alicorn's tank health lowered here
    world.SV_Unit_Alicorn[2].HealthInternal = 3456
    tick(1.1)
    check(#msgs("hp") > 0 and table.concat(msgs("hp"), " "):find(":3456", 1, true), "host: a tank's lowered health sent (hp)")
    -- a landing craft sunk here: down on every game
    world.SV_Unit_LcacA[1].HealthInternal = 0
    tick()
    local lc1 = k["SV_Unit_LcacA/BP_SH010_lcac_C#1"]
    check(table.concat(msgs("dn"), " "):find("dn|" .. lc1, 1, true), "host: the sunk craft goes down everywhere (dn " .. tostring(lc1) .. ")")
    -- a joiner's hit on the other craft
    local lc2 = k["SV_Unit_LcacA/BP_SH010_lcac_C#2"]
    inbox[#inbox + 1] = "1|ht|" .. lc2 .. "|120.0"
    tick()
    check(world.SV_Unit_LcacA[2].HealthInternal == 5000 - 1200, "host: the joiner's hit dealt (" .. world.SV_Unit_LcacA[2].HealthInternal .. ")")
    -- the tanks gone, the core open, the Alicorn under water; then a joiner starts over
    for i = 2, 5 do world.SV_Unit_Alicorn[i].HealthInternal = 0 end
    D.special = { kind = "alicorn", state = "sail", coreOpen = true, dived = true }
    tick()
    local before = #sent
    inbox[#inbox + 1] = "1|jn"
    tick()
    local after = {}
    for i = before + 1, #sent do after[#after + 1] = sent[i] end
    local s = table.concat(after, "\n")
    check(s:find("1>sp|SV_Unit_Alicorn|", 1, true) and s:find("1>gd|SV_Unit_Alicorn|%d+|BP_BA002_alcn_btankrr_Base_C#1|"),
          "host: the joiner who started over gets the Alicorn and its parts' ids")
    check(s:find("1>dn|" .. k["SV_Unit_Alicorn/BP_BA002_alcn_btankfr_Base_C#1"], 1, true), "host: ... and its tanks down")
    check(not s:find("1>ev|"), "host: the Alicorn's state not sent at once (its copy isn't up there yet)")
    tick(13)
    local ev = table.concat(msgs("ev"), " ")
    check(ev:find("1>ev|RE_SV_AlcnAdvance", 1, true) and ev:find("1>ev|RE_SV_AlcnOpenCore", 1, true) and ev:find("1>ev|RE_SV_AlcnDive", 1, true),
          "host: 12 s on, the Alicorn's core open and dive sent to that joiner")
    -- a unit with nothing linked and nothing up is forgotten (coop.11 sent long-gone craft to a joiner who started over)
    M.units.SV_Unit_Ghost = { gen = 99, n = 0, planes = {}, ground = {}, at = clock - 20 }
    tick(2.5)
    check(M.units.SV_Unit_Ghost == nil, "host: a unit the spawner has none of is forgotten")
    local out = {}
    for _, m in ipairs(sent) do
        local to, body = m:match("^(%-?%d+)>(.*)$")
        if to == "-1" or to == "1" then out[#out + 1] = "0|" .. body end
    end
    writeAll(WORK .. "/ground_messages.txt", table.concat(out, "\n"))
else
    menu = 16 + 4; tick()
    check(COOP.client(), "join: joined")
    D = { round = 0, state = "wait" }
    survivalPC = { Pawn = { addr = 0x9, HealthInternal = 1000 } }
    tick()
    local lines = {}
    for l in readAll(WORK .. "/ground_messages.txt"):gmatch("[^\n]+") do lines[#lines + 1] = l end
    -- the first run of messages (until the joiner's restart: the second "rs"-less sync comes after the first "ev")
    for _, l in ipairs(lines) do inbox[#inbox + 1] = l end
    for _ = 1, 20 do tick(0.5) end
    local lc = world.SV_Unit_LcacA
    check(lc and #lc == 2, "join: the host's landing craft spawned here")
    check(lc[1].gone or lc[1].HealthInternal <= 0, "join: the craft the host sank is down here too (" .. tostring(lc and lc[1].HealthInternal) .. ")")
    check(lc[2].min > 0 and lc[2].HealthInternal > 0, "join: the other is held up until the host's goes down")
    local al = world.SV_Unit_Alicorn
    check(al and al[2].HealthInternal <= 0 and al[5].HealthInternal <= 0, "join: the Alicorn's tanks down as on the host")
    check(al and al[6].HealthInternal > 0, "join: its core still up")
    local ev = table.concat(events, " ")
    check(ev:find("RE_SV_AlcnOpenCore", 1, true) and ev:find("RE_SV_AlcnDive", 1, true), "join: the host's Alicorn state played here")
    -- a hit here goes to the host
    local before = #sent
    lc[2].HealthInternal = lc[2].HealthInternal - 500
    tick()
    local s = table.concat(sent, "\n", before + 1)
    check(s:find("ht|%d+|50%.0"), "join: a hit on a craft here sent to the host (ht)")
end
print(fails == 0 and (ROLE .. ": all passed") or (ROLE .. ": " .. fails .. " FAILED"))
if fails > 0 then for i = math.max(1, #logs - 15), #logs do print("    log: " .. logs[i]) end end
os.exit(fails == 0 and 0 or 1)
