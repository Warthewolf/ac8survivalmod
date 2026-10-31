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
function SV_Event(name) events[#events + 1] = name; if EV_HOOK then EV_HOOK(name) end; return 1 end

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
    -- (as the game's: damage from another player's real plane, role 2, is refused outright: hard rule 53)
    function o:ModifyHealth(d, causer) if causer and causer.role2 then return 0 end; self.HealthInternal = math.max(self.min, self.HealthInternal + d * 10) end
    return o
end
local UNITS = {
    SV_Unit_LcacA = { { "BP_SH010_lcac", 5000 }, { "BP_SH010_lcac", 5000 } },
    SV_Unit_AAGun_A = { { "BP_GR002_gepa_CP", 6000 } },                 -- (an airfield defence: the host's ally)
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
    spawn("SV_Unit_LcacA"); spawn("SV_Unit_Alicorn"); spawn("SV_Unit_AAGun_A")
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
    -- the joiner's plane here their real one (COOP2MP: role 2, its damage refused): the hit dealt with none named, their
    -- share kept for the kill's credit (the co-op run of 2026-10-30: every joiner hit refused, "attacking ghosts")
    local P1 = M.peers[1] or {}
    M.peers[1] = P1
    local keepObj, keepReal = P1.obj, P1.real
    P1.obj, P1.real = { addr = 0x7770, role2 = true }, true
    inbox[#inbox + 1] = "1|ht|" .. lc2 .. "|50.0"
    tick()
    check(world.SV_Unit_LcacA[2].HealthInternal == 5000 - 1200 - 500, "host: a real plane's hit dealt too (" .. world.SV_Unit_LcacA[2].HealthInternal .. ")")
    check(M.joinHits and M.joinHits[world.SV_Unit_LcacA[2].addr] == 50, "host: ... its share kept for the kill's credit")
    P1.obj, P1.real = keepObj, keepReal
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
    check(not s:find("1>ev|RE_SV_Alcn", 1, true), "host: the Alicorn's state not sent at once (its copy isn't up there yet)")
    -- (the attack throttle in force goes at once, B too: sv_rounds.lua roundPressure, late_rounds_test.sh tests it)
    check(s:find("1>ev|RE_SV_Pressure", 1, true), "host: ... the attack throttle in force is (CFG.late.pressure)")
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
    -- a joiner's ally / defence bought: built here (sv_shop.lua shopBuildFor), answered "ak" / "ax"
    local built = {}
    shopBuildFor = function(slot, name, price, kind)
        built[#built + 1] = { slot, name, price, kind }
        if name == "Ciws" then return true, "CIWS BUILT for 6000 (SV_Unit_Ciws_A)." end
        return false, "ALL BUILT."
    end
    local b0 = #sent
    inbox[#inbox + 1] = "1|ab|7|Ciws|6000|ciws"
    tick()
    check(built[1] and built[1][1] == 1 and built[1][2] == "Ciws" and built[1][3] == 6000 and built[1][4] == "ciws"
          and table.concat(sent, "\n", b0 + 1):find("1>ak|7|CIWS BUILT for 6000", 1, true), "host: a joiner's CIWS built here, answered (ak)")
    inbox[#inbox + 1] = "1|ab|8|AAGun|4000|"
    tick()
    check(built[2] and built[2][4] == nil and table.concat(sent, "\n", b0 + 1):find("1>ax|8|ALL BUILT.", 1, true), "host: one it can't build refused (ax)")
    inbox[#inbox + 1] = "1|ab|9|Nope|100|"
    inbox[#inbox + 1] = "1|ab|10|Ciws|-5|ciws"
    tick()
    local s3 = table.concat(sent, "\n", b0 + 1)
    check(#built == 2 and s3:find("1>ax|9|A BAD REQUEST", 1, true) and s3:find("1>ax|10|A BAD REQUEST", 1, true),
          "host: an unknown item or a bad price: refused, nothing built")
    for i = 11, 16 do inbox[#inbox + 1] = "1|ab|" .. i .. "|Ciws|6000|ciws" end
    tick(0)
    check(#built <= 2 + 4, "host: at most 4 asks a second from one game (" .. (#built - 2) .. " of 6 taken)")
    -- the allies' orders: a joiner's taken (the allies are the host's: one order for the room)
    local ord = {}
    ALLY = { unit = {}, order = function() return "cover" end,
             nextOrder = function(how, o) ord[#ord + 1] = tostring(how) .. "/" .. tostring(o) end }
    inbox[#inbox + 1] = "1|ao|defend"
    inbox[#inbox + 1] = "1|ao|bogus"
    tick(1)
    check(#ord == 1 and ord[1] == "a joiner/defend", "host: a joiner's order taken (defend), a made-up one not")
    -- the room's allies in "rnd" (ALLY.roomCode), for the joiners' ALLIES rows
    ALLY.roomCode = function() return "m2s1" end
    local b4 = #sent
    M.nextRnd = 0
    tick(1)
    check(table.concat(sent, "\n", b4 + 1):find("rnd|[^\n]*|m2s1"), "host: the room's allies in rnd (m2s1)")
    ALLY = nil
    -- COVER for a joiner (COOP.coverFor): the allied planes onto the enemies nearest that joiner's real plane, the
    -- flights sent onto that plane reaching twice as far and counted at half their distance
    local function at(x) return function() return { X = x, Y = 0, Z = 0 } end end
    local hit = {}
    local function ally(n)
        return { name = n, EngagementOrderOverride = function(self, o, tgt, prio) hit[#hit + 1] = { self.name, tgt.name, prio } end }
    end
    local was = { peer = M.peers[1], up = D.up, huntOn = M.huntOn }
    M.peers[1] = { real = true, shown = true, obj = { name = "theirs", K2_GetActorLocation = at(0) } }
    D.up = { SV_Up_01 = true, SV_Up_02 = true, SV_Up_03 = true }
    M.units.SV_Up_01 = { n = 2, planes = { { id = 901 }, { id = 902, dead = true } } }
    M.units.SV_Up_02 = { n = 1, planes = { { id = 903 } } }
    M.units.SV_Up_03 = { n = 1, planes = { { id = 904 } } }
    M.byId[901] = { obj = { name = "e3km", K2_GetActorLocation = at(300000) } }
    M.byId[902] = { obj = { name = "dead", K2_GetActorLocation = at(100) } }
    M.byId[903] = { obj = { name = "e9km", K2_GetActorLocation = at(900000) } }
    M.byId[904] = { obj = { name = "on16km", K2_GetActorLocation = at(1600000) } }
    M.huntOn = { SV_Up_03 = { slot = 1 } }
    local n, km = COOP.coverFor(1, { ally("a1"), ally("a2") })
    check(n == 2 and math.abs((km or 0) - 3) < 1e-6 and hit[1] and hit[1][1] == "a1" and hit[1][2] == "e3km"
          and hit[2] and hit[2][2] == "on16km" and hit[1][3] == 9,
          "host: cover for player 2: onto the nearest (3 km) and the flight sent onto them (16 km), TargetFirst: "
          .. tostring(n) .. ", " .. (hit[1] and hit[1][2] or "-") .. ", " .. (hit[2] and hit[2][2] or "-"))
    M.huntOn = nil
    hit = {}
    n = COOP.coverFor(1, { ally("a1"), ally("a2"), ally("a3") })
    check(n == 3 and hit[1][2] == "e3km" and hit[2][2] == "e9km" and hit[3][2] == "e3km",
          "host: ... not sent onto them: past 10 km out of reach, the planes shared round the rest")
    M.peers[1].onAirfield = true
    check(COOP.coverFor(1, { ally("a1") }) == 0, "host: ... at their airfield: none (the ally covers you)")
    for _, u in ipairs({ "SV_Up_01", "SV_Up_02", "SV_Up_03" }) do M.units[u] = nil end
    for id = 901, 904 do M.byId[id] = nil end
    M.peers[1], D.up, M.huntOn = was.peer, was.up, was.huntOn
else
    menu = 16 + 4; tick()
    check(COOP.client(), "join: joined")
    D = { round = 0, state = "wait" }
    survivalPC = { Pawn = { addr = 0x9, HealthInternal = 1000 } }
    -- the host's plane here its real one (COOP2MP: role 2): a copy finished with no cause named (the game refused it
    -- named: from T3 no copy here could be finished, the co-op run of 2026-10-30)
    M.peers[0] = { obj = { addr = 0x8880, role2 = true }, real = true, addr = 0x8880 }
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
    -- the host's AA gun here: its copy's losses never sent, its hits on enemies taken off what is (its fight is the host's)
    local aa = world.SV_Unit_AAGun_A
    check(aa and #aa == 1, "join: the host's AA gun spawned here")
    local b1 = #sent
    aa[1].HealthInternal = aa[1].HealthInternal - 700
    tick()
    check(not table.concat(sent, "\n", b1 + 1):find("ht|", 1, true), "join: a hit on the host's AA gun here not sent (an ally)")
    check(M.standInSet()[aa[1].addr] == -1, "join: ... its own hits here taken off what's sent (the stand-ins' backstop)")
    -- your ally / defence bought: the host asked, its answer kept or refunded
    RUN = { credits = 10000, spent = 6000, msg = {}, bought = {}, dirty = false }
    local ok = COOP.askBuild("Ciws", 6000, "ciws")
    local id = tonumber(table.concat(sent, "\n", b1 + 1):match("ab|(%d+)|Ciws|6000|ciws"))
    check(ok and id, "join: BUILD CIWS asked of the host (ab)")
    inbox[#inbox + 1] = "0|ak|" .. tostring(id) .. "|CIWS BUILT for 6000 (SV_Unit_Ciws_A)."
    tick()
    check(RUN.msg.Ciws == "CIWS BUILT for 6000 (SV_Unit_Ciws_A)." and RUN.defences and RUN.defences.bought.ciws == 1
          and RUN.bought.Ciws == 1 and RUN.credits == 10000, "join: built: counted as yours, nothing refunded")
    local b2 = #sent
    COOP.askBuild("Wingmen", 5000, nil)
    id = tonumber(table.concat(sent, "\n", b2 + 1):match("ab|(%d+)|Wingmen|"))
    inbox[#inbox + 1] = "0|ax|" .. tostring(id) .. "|BOTH ALLIED FLIGHTS ARE UP."
    tick()
    check(RUN.credits == 15000 and (RUN.msg.Wingmen or ""):find("REFUSED: BOTH ALLIED FLIGHTS ARE UP", 1, true), "join: refused: 5000 refunded")
    COOP.askBuild("SAM", 8000, "sam")
    tick(31)
    check(RUN.credits == 23000 and (RUN.msg.SAM or ""):find("NO ANSWER FROM THE HOST", 1, true), "join: no answer in 30 s: 8000 refunded")
    inbox[#inbox + 1] = "0|ar|5000|WINGMEN COULD NOT TAKE OFF"
    tick()
    check(RUN.credits == 28000, "join: a flight of yours that never took off: 5000 back (ar)")
    inbox[#inbox + 1] = "0|ak|9999|CIWS BUILT"
    tick()
    check(RUN.credits == 28000 and RUN.bought.Ciws == 1, "join: an answer to nothing asked: ignored")
    -- the room's allies from the host's "rnd", for the ALLIES row here
    inbox[#inbox + 1] = "0|rnd|3|fight|0.0|1|2|4|||m2s1"
    tick()
    local ra = COOP.roomAllies()
    check(ra and ra.m == 2 and ra.s == 1 and ra.w == nil, "join: the host's allies taken from rnd (m2s1)")
    inbox[#inbox + 1] = "0|rnd|3|fight|0.0|1|2|4|||m2v1s1"
    tick()
    ra = COOP.roomAllies()
    check(ra and ra.m == 2 and ra.v == 1 and ra.s == 1, "join: VOID WATCHER 1 in the host's allies (m2v1s1)")
    tick(6)
    check(COOP.roomAllies() == nil, "join: ... 6 s with no word: none")
    for _, bad in ipairs({ "m999", "x2", "m2;s1", "m2w2s2m2w2", "", "v1v1", "m99w99v99s99m1" }) do
        inbox[#inbox + 1] = "0|rnd|3|fight|0.0|1|2|4|||" .. bad
        tick()
        check(COOP.roomAllies() == nil, "join: a bad allies field (" .. bad .. "): none")
    end
    -- copies this game takes down itself are no kills (COOP.tornDown: the co-op runs of 2026-10-30, a joiner's teardown
    -- on the host's restart paid 41 kills), the host's kills are; the teardown drops the defences' cached actors
    local killed, torn = obj("BP_OP1004_f15c", 5000, true), obj("BP_OP1004_f15c", 5000, true)
    M.copies[998], M.copies[999] = { obj = killed, exp = 50000, addr = killed.addr }, { obj = torn, exp = 50000, addr = torn.addr }
    inbox[#inbox + 1] = "0|dn|998"
    tick()
    check(killed.HealthInternal <= 0 and not COOP.tornDown({ addr = killed.addr }), "join: the host's kill (dn): a kill here")
    local forgot = 0
    ALLY = { unit = {}, forgetActors = function() forgot = forgot + 1 end }
    inbox[#inbox + 1] = "0|rs"
    tick()
    check(torn.HealthInternal <= 0 and COOP.tornDown({ addr = torn.addr }) and forgot == 1,
          "join: taken down on the host's new run (rs): not a kill, the defences' actors forgotten")
    tick(31)
    check(not COOP.tornDown({ addr = torn.addr }), "join: ... 30 s on, forgotten (its address may be another plane's)")
    ALLY = nil
    -- the Alicorn's parked pools aren't copies here (the host gives them no ids): the co-op run of 2026-10-31, 131 of them
    -- counted as strays, a resync, the tanks and core taken down here and the fresh copy refused (still up)
    SPC = { alcnPool = { set = {}, n = 0 }, alicornUnit = "SV_Unit_Alicorn" }
    local gen = 777
    inbox[#inbox + 1] = "0|sp|SV_Unit_Alicorn|-|-|-1|" .. gen
    local removed = 0
    EV_HOOK = function(name) if name == "RE_SV_AlcnRemove" then removed = removed + 1; alive.SV_Unit_Alicorn = 0 end end
    local before3 = #logs
    for _ = 1, 12 do tick(0.5) end
    local l3 = table.concat(logs, " | ", before3 + 1)
    check(removed == 1 and l3:find("the Alicorn's last copy here is still up", 1, true) and not l3:find("spawning anyway", 1, true),
          "join: the host's fresh Alicorn while its last copy's still up here: that one taken off whole (RE_SV_AlcnRemove), once")
    check(alive.SV_Unit_Alicorn == 7 and M.cunits.SV_Unit_Alicorn and M.cunits.SV_Unit_Alicorn.gen == gen,
          "join: ... and the host's spawned in its place (" .. tostring(alive.SV_Unit_Alicorn) .. ")")
    local pool = obj("BP_FG037_uavm_ON_pool", 100, true)
    SPC.alcnPool.set[pool.addr] = true
    local plane = obj("BP_OP1022_f16c", 500, true)
    logPlane(pool, "SV_Unit_Alicorn", 0)
    check(M.cunits.SV_Unit_Alicorn.n == 0, "join: a parked pool of its isn't a copy here (no ordinal, never a stray)")
    logPlane(plane, "SV_Unit_Alicorn", 1)
    check(M.cunits.SV_Unit_Alicorn.n == 1 and M.cunits.SV_Unit_Alicorn.planes[1] == plane, "join: ... any other plane of it is (ordinal 1, as the host's)")
    local b4 = #logs
    tick(16); tick(5)
    local l4 = table.concat(logs, " | ", b4 + 1)
    check(pool.HealthInternal == 100 and not l4:find("131 stray", 1, true), "join: 20 s on, the pool's not taken down as a stray")
    EV_HOOK, SPC = nil, nil
end
print(fails == 0 and (ROLE .. ": all passed") or (ROLE .. ": " .. fails .. " FAILED"))
if fails > 0 then for i = math.max(1, #logs - 15), #logs do print("    log: " .. logs[i]) end end
os.exit(fails == 0 and 0 or 1)
