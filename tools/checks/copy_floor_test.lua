-- copy_floor_test.lua <mod dir> <work dir> <role: host|join> (run by tools/checks/copy_floor_test.sh): 0.73.77's fixes of
-- the enemy copy desync and the joiners' kill pay, on the real sv_config.lua and sv_coop.lua (M exposed), the spawner and
-- the game's health stubbed as the runtime's and the game's (every hit clamped at the MinHealth field; SetMinHealth keeps
-- whole points only; each object's DamageHistoryMap). The logs of 0.73.76 (2026-11-02, plan Workstream A and the economy
-- proposal's C1): joiners' copies had no floor (SetMinHealth(0.1) = 0) and went down to the ships' copies there long
-- before the host's kill, the host's "hp" wrote health back onto the wrecks, their flights' next spawns were refused,
-- one run ended while a player loaded in, and every kill a joiner saw was paid as its own.
-- join: A1 the floor (the field written; a copy the ships' copies take to it put back up, nothing sent; your own lethal
--   hit sent whole, the copy waiting at 1 HP for the host's "dn"; a crash there not sent once your plane's in the maps;
--   a hit at the floor whose health doesn't move found in the map); A2 the host's "hp" never onto a copy down here; A3 a
--   refused spawn's wrecks taken down, then SV_Recycle after 6 tries (or off, or missing); A6 the sync report's floor,
--   refused and skipped counts; A9 the host's run-over while the level loads; C1 each kill by the player the host named.
-- host: C1 the killer in each "dn" (the most damage, the host's own, a side's, none for one gone), KILL.by by it, the
--   team share, the run's tally and the sync report's line; A9 a joiner who asks for the picture after the run-over gets
--   it, a new level forgets it.
local MOD, WORK, ROLE = arg[1], arg[2], arg[3]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
-- (CRLF checkouts: the sources searched as git stores them, LF)
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return (s:gsub("\r\n", "\n")) end

local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end

local clock = 100
os.clock = function() return clock end           -- luacheck: ignore

local logs = {}
function log(s) logs[#logs + 1] = s end
local function line(pat, from)
    for i = #logs, from or 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end
    return nil
end
VERSION = "0.73.77-floor.test"
SCRIPT_DIR = WORK .. "/" .. ROLE .. "/Scripts/"
-- (the kill attribution's raw parts, sv_ai.lua's: an Aegis's turret is "ships"; KILL.by's own answer "raw")
KILL = { side = function(o) return (type(o) == "table" and tostring(o.name):find("aegs", 1, true)) and "ships" or "other" end,
         read = function() end, by = function() return "raw" end, fired = {} }
LB = { send = function() end }
RUN = {}
function roundsTick() end
function airfieldTick() end
function bombTick() end
function logPlane() end
local callouts, pays = {}, 0
function hudCallout(t) callouts[#callouts + 1] = tostring(t) end
function addCredits() pays = pays + 1 end
function poolIndex() return nil end
SPC = {}
function FindAllOf() return {} end
function FindFirstOf() return nil end
local GS = {}
function GS:ApplyDamage(o, dmg)
    if not (o.invincible or o.bIsInvincible) then o.HealthInternal = math.max(math.floor((o.MinHealth or 0) * 10), o.HealthInternal - dmg) end
end
function StaticFindObject(p)
    if tostring(p):find("GameplayStatics", 1, true) then return GS end
    return { cls = "LiveAIPlane" }
end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.name or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function inSurvival() return true end
function playerOnAirfield() return false end
function gamePaused() return false end
function cdo() return nil end
SV_ERR = { [-3] = "its last flight is still up" }
local sent, inbox = {}, {}
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
local evOrder = {}                               -- ((code review of 2026-11-07) the events fired here, in order
function SV_Event(name) evOrder[#evOrder + 1] = "fired " .. tostring(name); return 1 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
local recycled = {}

-- the game's objects: health x 10, every hit clamped at the MinHealth field (SetMinHealth keeps whole points), each
-- hit added in full to the DamageHistoryMap (o.hist: attacker -> health) before the clamp. A wreck (0 health) the game
-- still counts in its unit (wreck) is let go by the game's own death check on its next ModifyHealth, unless stubborn.
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
local nextAddr = 0x1000
local function obj(cls, hp, plane)
    nextAddr = nextAddr + 0x10
    local o = { name = cls .. "_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel." .. cls .. "_C_" .. nextAddr,
                addr = nextAddr, HealthInternal = hp, plane = plane == true, hist = {} }
    function o:IsA() return self.plane end
    function o:GetAddress() return self.addr end
    function o:SetMinHealth(v) self.MinHealth = math.floor(v) end
    function o:SetIsInvincible(b) self.invincible = b end
    function o:ModifyHealth(d, causer)
        self.causers = self.causers or {}
        self.causers[#self.causers + 1] = causer or "none"           -- ((0.73.80) the kill's cause, in order)
        if causer ~= nil and causer == self.refuse then return end   -- (the game refusing that cause)
        if self.invincible then return end
        if self.wreck and not self.stubborn then self.wreck = false end
        self.HealthInternal = math.max(math.floor((self.MinHealth or 0) * 10), self.HealthInternal + d * 10)
    end
    o.DamageHistoryMap = { ForEach = function(_, fn)
        for k, v in pairs(o.hist) do fn({ get = function() return k end }, { get = function() return v end }) end
    end }
    return o
end
-- a hit as the game deals it: in full into the map, the health clamped at the floor
local function hit(o, by, hpDmg)
    o.hist[by] = (o.hist[by] or 0) + hpDmg
    o.HealthInternal = math.max(math.floor((o.MinHealth or 0) * 10), o.HealthInternal - hpDmg * 10)
end
local UNITS = {
    ERA_Unit_01_Dep_Air0 = { { "BP_OP1022_f16c_CP", 5000, true }, { "BP_OP1022_f16c_CP", 5000, true } },
    ERA_Unit_02_Dep_Air0 = { { "BP_OP1030_su33_CP", 5000, true }, { "BP_OP1030_su33_CP", 5000, true } },
    ERA_Unit_03_Dep_Air0 = { { "BP_OP1009_su34_CP", 5000, true } },
    ERA_Unit_04_Dep_Air0 = { { "BP_OP1027_m21b_CP", 5000, true } },
    ERA_Unit_05_Dep_Air0 = { { "BP_OP1027_m21b_CP", 5000, true } },
    ERA_Unit_06_Dep_Air0 = { { "BP_OP1027_m21b_CP", 5000, true } },
    ERA_Unit_07_Dep_Air0 = { { "BP_OP1002_f02a_CP", 5000, true }, { "BP_OP1002_f02a_CP", 5000, true } },
}
local world, pendingPlanes = {}, {}
local function up(o) return not o.gone and (o.wreck or o.HealthInternal > 0) end
function SV_Spawn(unit)
    for _, o in ipairs(world[unit] or {}) do if up(o) then return -3 end end
    world[unit] = {}
    for i, d in ipairs(UNITS[unit] or {}) do
        local o = obj(d[1], d[2], d[3])
        world[unit][i] = o
        for _, fn in ipairs(notify["/Script/Live.LiveAIGameObject"] or {}) do fn(o) end
        if o.plane then pendingPlanes[#pendingPlanes + 1] = { o = o, unit = spawningUnit, k = i - 1 } end
    end
    return #world[unit]
end
function SV_UnitAlive(unit)
    if not world[unit] then return -7 end
    local n = 0
    for _, o in ipairs(world[unit]) do if up(o) then n = n + 1 end end
    return n
end
function SV_Recycle(unit, force) recycled[#recycled + 1] = unit .. "/" .. tostring(force); world[unit] = nil; return 1 end

-- (sv_rounds.lua's flightWithdrawn, the real one: a joiner's copies of a flight the host took off, marked down and
-- withdrawn: the sweep neither pays nor counts them)
do
    local fw = readAll(MOD .. "/Scripts/sv_rounds.lua"):match("\nfunction flightWithdrawn%(unit%).-\nend\n")
    assert(fw, "sv_rounds.lua: flightWithdrawn not found")
    assert(load(fw, "=sv_rounds.lua flightWithdrawn"))()
end
local downs = {}
DOWN = { reset = function() end, me = function() return false end, onJoiner = function(f) downs[#downs + 1] = table.concat(f, "|") end,
         syncTo = function() end }
STATS = { hostReset = function() end, roundEnd = function() end, roundStart = function() end }
function newRunHere() end
-- ((code review of 2026-11-07, findings 1 and 6) sv_fishing.lua's boat and sv_escort.lua's ZFA-44s as sv_coop.lua asks them
FISH = { isBoat = function(u) return u == "SV_Unit_SalBoat" end }
local zfaHere = {}                               -- (this game's own ZFA-44s, by address: ESC.localZfa)
ESC = { localZfa = function() return zfaHere end,
        beforeHostEvent = function(name) evOrder[#evOrder + 1] = "before " .. tostring(name) end,
        hullShip = function(u) return u == "SV_Unit_Cargo1" and 1 or nil end }       -- (sv_escort.lua's: ship 1's hull)
-- (sv_escort_laser.lua's ZLAUNCH.holdHull: whether ship i's hull is held, its ZFA-44s up; escort_test tests the real one)
local hullHeld, holdAsked = false, {}
ZLAUNCH = { holdHull = function(i, t, who, why) holdAsked[#holdAsked + 1] = tostring(i) .. " " .. tostring(who); return hullHeld end }

PARTS.dofile("sv_config.lua")
PARTS.load("sv_coop.lua", "=sv_coop.lua", { { "\nlocal M = {", "\nM = {" } })   -- (its pieces too; M exposed)
local M = _G.M
CFG.coop.enabled = true
local function tick(dt)
    clock = clock + (dt or 0.25)
    local p = pendingPlanes
    pendingPlanes = {}
    for _, e in ipairs(p) do logPlane(e.o, e.unit, e.k) end
    COOP.tick(0)
    if COOP.client() then roundsTick(clock) end
end
local function run(s, dt) local t = 0; while t < s do tick(dt or 0.25); t = t + (dt or 0.25) end end
local function msgs(kind, from)
    local t = {}
    for i = from or 1, #sent do if sent[i]:match("^%-?%d+>" .. kind .. "|") then t[#t + 1] = sent[i] end end
    return t
end
local pawn = { addr = 0x9, HealthInternal = 1000, name = "pawn" }
function pawn:GetAddress() return self.addr end

if ROLE == "host" then
    menu = 16 + 3; tick()
    check(COOP.host(), "host: hosting")
    D = { round = 3, state = "fight", now = clock }
    survivalPC = { Pawn = pawn }
    tick()
    local U1, U2 = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air0"
    spawningUnit = U1; SV_Spawn(U1); spawningUnit = nil
    spawningUnit = U2; SV_Spawn(U2); spawningUnit = nil
    run(1.5)
    local ids = {}
    for _, m in ipairs(msgs("bd")) do
        local u, ord, id = m:match("bd|([%w_]+)|%d+|(%d+)|(%d+)")
        ids[u .. "#" .. ord] = tonumber(id)
    end
    local e1, e2, e3, e4 = world[U1][1], world[U1][2], world[U2][1], world[U2][2]
    local i1, i2, i3, i4 = ids[U1 .. "#1"], ids[U1 .. "#2"], ids[U2 .. "#1"], ids[U2 .. "#2"]
    check(i1 and i2 and i3 and i4, "host: four planes linked")

    print("host: C1, the kill's player named in its dn")
    local aegis = obj("BP_VE002_aegs_mk41", 9000)
    inbox[#inbox + 1] = "1|ht|" .. i1 .. "|300.0"              -- (player 2's hits: 300 of its 500)
    tick()
    hit(e1, pawn, 150); hit(e1, aegis, 50)                     -- (yours 150, the ships' 50: it's down)
    local s0 = #sent
    tick()
    check(table.concat(msgs("dn", s0 + 1), " ") == "-1>dn|" .. i1 .. "||1", "host: a joiner's kill (300 of its damage, yours 150): \"dn|"
          .. i1 .. "||1\" (" .. table.concat(msgs("dn", s0 + 1), " ") .. ")")
    hit(e2, pawn, 600); hit(e2, aegis, 100)
    s0 = #sent; tick()
    check(table.concat(msgs("dn", s0 + 1), " ") == "-1>dn|" .. i2 .. "||0", "host: your own kill: \"dn|" .. i2 .. "||0\"")
    hit(e3, aegis, 900)
    s0 = #sent; tick()
    check(table.concat(msgs("dn", s0 + 1), " ") == "-1>dn|" .. i3 .. "||s", "host: the allied ships' kill: \"dn|" .. i3 .. "||s\"")
    e4.gone = true
    s0 = #sent; tick()
    check(table.concat(msgs("dn", s0 + 1), " ") == "-1>dn|" .. i4 .. "||", "host: one gone (not shot down): no player named")
    local p1, p2, p3, p4 = { addr = e1.addr, obj = e1 }, { addr = e2.addr, obj = e2 }, { addr = e3.addr, obj = e3 }, { addr = e4.addr, obj = e4 }
    check(KILL.by(p1) == "wingmate" and p1.killer == 1 and KILL.by(p2) == "you" and p2.killer == 0 and KILL.by(p3) == "ships"
          and KILL.by(p4) == "raw", "host: KILL.by goes by the player named: player 2's a teammate's (p.killer 1), yours, the ships', the raw rule for one gone")
    local t, nt = COOP.killTally(), 0
    for _ in pairs(t) do nt = nt + 1 end
    check(t[1] and t[1].air == 1 and t[0] and t[0].air == 1 and nt == 2,
          "host: the run's tally: one each for player 1 and 2, none for the ships' or the gone one")
    local rep = COOP.syncReport()
    check(has(rep, "the run's kills by player: player 1 1, player 2 1"), "host: the sync report's line: " .. rep)
    -- the share: min(team_x, 1 / (players - 1))
    local function share(n) M.roster = {}; for s = 0, n - 1 do M.roster[s] = { name = "p" .. s } end; return COOP.teamShare() end
    check(share(2) == 0.5 and share(3) == 0.5 and math.abs(share(4) - 1 / 3) < 1e-9 and share(5) == 0.25 and share(6) == 0.2,
          "host: a teammate's kill pays 0.5 with 2 or 3 players, 0.33 with 4, 0.25 with 5, 0.2 with 6")
    CFG.credits.team_x = 0.3
    check(share(3) == 0.3 and share(2) == 0.3, "host: ... at most [zollars] team_x")
    CFG.credits.team_x = 0.5

    print("host: (review of 27097b9, finding 3) a flight taken off with no despawn event a joiner sees: wd")
    s0 = #sent
    local okWd, rWd = pcall(function() return COOP.withdrawn("EA_Unit_01_Air2") end)
    check(okWd and rWd == true and table.concat(msgs("wd", s0 + 1), " ") == "-1>wd|EA_Unit_01_Air2",
          "host: COOP.withdrawn(unit): \"wd|<unit>\" to every joiner (" .. tostring(okWd and rWd or rWd) .. ")")

    print("host: (code review of 2026-11-07, findings 6 and 11) SAL's boat out of the hp batch; a kill held unpaid")
    local boatH = obj("VE028_boat2_CP", 2000)
    local cmH, cm2 = obj("BP_OP0039_slcmp_CP", 2500, true), obj("BP_OP0039_slcmp_CP", 2500, true)
    M.byId[901] = { obj = boatH, unit = "SV_Unit_SalBoat", key = "VE028_boat2_CP#1", addr = boatH.addr }
    M.byId[902] = { obj = cmH, unit = "SV_Unit_FestCM_N1", ord = 1, addr = cmH.addr }
    M.byId[903] = { obj = cm2, unit = "SV_Unit_FestCM_N1", ord = 2, addr = cm2.addr }
    run(1.5)
    boatH.HealthInternal, cmH.HealthInternal = 1500, 2400
    s0 = #sent
    run(1.5)
    local hpText = table.concat(msgs("hp", s0 + 1), " ")
    check(has(hpText, "902:2400") and not has(hpText, "901:"), "host: the hp batch: a missile's health, not SAL's boat's (" .. hpText .. ")")
    check(COOP.payHold(cmH, true) == true, "host: COOP.payHold: the missile held unpaid")
    cmH.HealthInternal, cm2.HealthInternal = 0, 0
    s0 = #sent; tick()
    local dnText = table.concat(msgs("dn", s0 + 1), " ")
    check(has(dnText, "dn|902|r|") and not has(dnText, "dn|903|r"),
          "host: a held one down: a removal on every game (dn|902|r), the other one a kill as before (" .. dnText .. ")")

    print("host: A9, the run-over for a player who links after it")
    s0 = #sent
    COOP.msg(nil, "ro", 7)
    check(table.concat(msgs("ro", s0 + 1), " ") == "-1>ro|7" and M.ro and M.ro.round == 7, "host: the run-over sent and kept")
    local from = #logs + 1
    s0 = #sent
    inbox[#inbox + 1] = "1|jn"
    tick()
    local pic = {}
    for i = s0 + 1, #sent do if sent[i]:match("^1>") then pic[#pic + 1] = sent[i] end end
    check(pic[#pic] == "1>ro|7" or has(table.concat(pic, " "), "1>ro|7"), "host: the picture for a player who asked after it carries \"ro|7\"")
    check(has(line("coop: player 2 linked after the run-over (round 7", from), "sent it again (ro)"), "host: ... logged")
    D = { round = 1, state = "wait", now = clock }
    tick()
    check(M.ro == nil and next(COOP.killTally()) == nil, "host: a new level: the run-over and the tally forgotten")
    s0 = #sent
    inbox[#inbox + 1] = "1|jn"
    tick()
    local any = false
    for i = s0 + 1, #sent do if sent[i]:match("^1>ro|") then any = true end end
    check(not any, "host: ... the next picture has no run-over")
else
    menu = 16 + 4; tick()
    check(COOP.client(), "join: joined")
    COOP.slot = 1
    D = { round = 5, state = "fight", now = clock }
    survivalPC = { Pawn = pawn }
    tick(); run(3.5)
    M.jnAt, M.resyncAt = nil, 0
    local U1, U2 = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air0"
    local from = #logs + 1
    for _, m in ipairs({ "sp|" .. U1 .. "|-|-|-1|1", "bd|" .. U1 .. "|1|1|11", "bd|" .. U1 .. "|1|2|12",
                         "sp|" .. U2 .. "|-|-|-1|2", "bd|" .. U2 .. "|2|1|21", "bd|" .. U2 .. "|2|2|22" }) do
        inbox[#inbox + 1] = "0|" .. m
    end
    run(1)
    local a1, a2, b1, b2 = world[U1][1], world[U1][2], world[U2][1], world[U2][2]
    print("join: A1, the floor")
    check(a1.MinHealth == 1.0 and b2.MinHealth == 1.0 and M.copies[11] and M.copies[22],
          "join: every copy held at 1 HP: the MinHealth field written (0.73.76's SetMinHealth(0.1) kept 0)")
    check(has(line("coop: copies held at 1.0 HP until the host's kill (the field written; MinHealth reads back 1.0)", from), "1.0"),
          "join: ... logged once: " .. tostring(line("copies held at", from)))
    -- the host's allied ship's copy here takes a1 to the floor: nothing sent, a1 back up
    local ship = obj("BP_VE002_aegs_mk41", 50000)
    M.copies[90] = { obj = ship, exp = 50000, addr = ship.addr, ally = true, hp = 50000 }
    local s0 = #sent
    hit(a1, ship, 600)
    check(a1.HealthInternal == 10, "join: (the ships' copy's 600 on a 500 HP copy: it stops at 1 HP)")
    tick()
    check(#msgs("ht", s0 + 1) == 0 and a1.HealthInternal == 5000 and not M.copies[11].floorAt,
          "join: taken to the floor by the host's ally's copy here: nothing sent, put back up to the host's 500 HP")
    -- your own missile: 800 on a 500 HP copy
    from = #logs + 1
    hit(a2, pawn, 800)
    s0 = #sent; tick()
    check(table.concat(msgs("ht", s0 + 1), " ") == "-1>ht|12|800.0", "join: your 800 at the floor sent whole (not 499.0): "
          .. table.concat(msgs("ht", s0 + 1), " "))
    check(a2.HealthInternal == 10 and M.copies[12].floorAt ~= nil, "join: ... and the copy waits at 1 HP for the host's kill")
    check(line("coop: your hits read from the copies' damage maps", from) ~= nil, "join: your plane seen in a copy's map: logged")
    -- the host's kill, 0.3 s on: down here, its player named
    tick(0.3)
    from = #logs + 1
    local c0, p0 = #callouts, pays
    inbox[#inbox + 1] = "0|dn|12||1"
    tick()
    check(a2.HealthInternal <= 0 and M.copies[12] == nil and M.killer[a2.addr] and M.killer[a2.addr].code == "1",
          "join: the host's dn|12||1: down here, the floor off first, its player kept")
    -- ((0.73.80, finding coop6) named for this game's player (slot 1): taken down with your plane as its cause (the game's
    -- DESTROYED); nothing paid here by it (the pay is the plane watch's, by the player named), no callout by default
    check(a2.causers and a2.causers[#a2.causers] == pawn, "join: ... with your plane as its cause (0.73.79: none)")
    check(has(line("coop: the host's kill of copy 12 (yours): taken down here with your plane as its cause", from), "DESTROYED"),
          "join: ... logged once")
    check(pays == p0 and #callouts == c0, "join: ... nothing paid by it, no DESTROYED callout ([coop] kill_callout off)")
    local pa2 = { addr = a2.addr, obj = a2 }
    check(KILL.by(pa2) == "you" and pa2.killer == 1 and pa2.hostNamed == true, "join: KILL.by: your kill (player 2 named)")
    -- a crash into the floor, now your plane is known in the maps: nothing sent, back up
    s0 = #sent
    b1.HealthInternal = 10
    tick()
    check(#msgs("ht", s0 + 1) == 0 and b1.HealthInternal == 5000, "join: a copy at the floor with nothing of yours (a crash): nothing sent, back up")
    -- the host says less than the floor: your hit only raises it to the floor; found in the map
    inbox[#inbox + 1] = "0|hp|22:5"
    tick()
    check(b2.HealthInternal == 5, "join: (the host's hp 5: below the floor here)")
    hit(b2, pawn, 3)
    check(b2.HealthInternal == 10, "join: (your 3 on it: the clamp raises it to the floor)")
    s0 = #sent; tick()
    check(table.concat(msgs("ht", s0 + 1), " ") == "-1>ht|22|3.0" and M.copies[22].floorAt ~= nil,
          "join: ... your hit found in its map and sent (" .. table.concat(msgs("ht", s0 + 1), " ") .. ")")
    s0 = #sent; tick()
    check(#msgs("ht", s0 + 1) == 0, "join: ... once")
    inbox[#inbox + 1] = "0|hp|22:2000"
    tick()
    check(b2.HealthInternal == 2000 and M.copies[22].floorAt == nil, "join: the host's hp 2000 (it had more than you sent): off the floor")

    print("join: A2, the host's hp never onto a copy down here")
    b1.HealthInternal = 0                                      -- (down here: the floor didn't hold)
    inbox[#inbox + 1] = "0|hp|21:3000"
    tick()
    check(b1.HealthInternal == 0, "join: hp|21:3000 onto a copy at 0 here: not written (0.73.76: the wreck back up, an invisible enemy)")

    print("join: C1, the host's player named on each kill")
    from = #logs + 1
    inbox[#inbox + 1] = "0|dn|11||0"
    tick()
    local pa1 = { addr = a1.addr, obj = a1 }
    check(KILL.by(pa1) == "wingmate" and pa1.killer == 0, "join: dn|11||0: the host's kill, a teammate's here (p.killer 0)")
    check(a1.causers and a1.causers[#a1.causers] == "none" and has(line("coop: the host's kill of copy 11 (named 0)", from), "no cause"),
          "join: ... another player's kill: no cause, as before (the host flies no stand-in here), logged")
    inbox[#inbox + 1] = "0|dn|22||s"
    tick()
    check(KILL.by({ addr = b2.addr, obj = b2 }) == "ships", "join: dn|22||s: the allied ships' kill")
    inbox[#inbox + 1] = "0|dn|21"
    tick()
    check(KILL.by({ addr = b1.addr, obj = b1 }) == "raw", "join: a dn with no player (an older host's): the raw rule, as before")

    print("join: A3, a refused spawn's wrecks, then SV_Recycle")
    local U3, U4, U5, U6 = "ERA_Unit_03_Dep_Air0", "ERA_Unit_04_Dep_Air0", "ERA_Unit_05_Dep_Air0", "ERA_Unit_06_Dep_Air0"
    local w3 = obj("BP_OP1009_su34_CP", 0, true); w3.wreck = true
    world[U3] = { w3 }
    planes = { { obj = w3, unit = U3, down = true } }
    from = #logs + 1
    inbox[#inbox + 1] = "0|sp|" .. U3 .. "|-|-|-1|30"
    run(3)
    check(world[U3][1] ~= w3 and has(line("coop: " .. U3 .. " is up here (1 alive; no longer tracked here)", from), "and 1 wrecks of it still in the world"),
          "join: a wreck it still counts (nothing tracked): taken down again, the game's death check lets it go")
    check(has(line("coop: " .. U3 .. " unstuck after 2 tries", from), "(0 up, 1 wrecks)"), "join: ... and spawned: " .. tostring(line("unstuck", from)))
    local w4 = obj("BP_OP1027_m21b_CP", 0, true); w4.wreck, w4.stubborn = true, true
    world[U4] = { w4 }
    planes[#planes + 1] = { obj = w4, unit = U4, down = true }
    inbox[#inbox + 1] = "0|sp|" .. U4 .. "|-|-|-1|31"
    run(10)
    check(recycled[1] == U4 .. "/1" and world[U4] and world[U4][1] ~= w4 and has(line("coop: " .. U4 .. " unstuck: still 1 alive here after 6 tries", from), "SV_Recycle: recycled"),
          "join: one the game won't let go: SV_Recycle(unit, 1) after 6 tries, then spawned (" .. tostring(line(U4 .. " unstuck", from)) .. ")")
    CFG.coop.force_recycle = false
    local w5 = obj("BP_OP1027_m21b_CP", 0, true); w5.wreck, w5.stubborn = true, true
    world[U5] = { w5 }
    inbox[#inbox + 1] = "0|sp|" .. U5 .. "|-|-|-1|32"
    run(10)
    check(#recycled == 1 and world[U5][1] == w5 and has(line("coop: " .. U5 .. "'s last copies are still up; spawning anyway", from), "force_recycle off")
          and has(line("coop: the host's " .. U5 .. " not spawned here", from), "its last flight is still up"),
          "join: [coop] force_recycle = false: no recycle, refused as before")
    CFG.coop.force_recycle = true
    local keep = SV_Recycle
    SV_Recycle = nil
    local w6 = obj("BP_OP1027_m21b_CP", 0, true); w6.wreck, w6.stubborn = true, true
    world[U6] = { w6 }
    inbox[#inbox + 1] = "0|sp|" .. U6 .. "|-|-|-1|33"
    run(10)
    check(has(line("coop: " .. U6 .. "'s last copies are still up; spawning anyway", from), "no SV_Recycle in this runtime"),
          "join: an older runtime (no SV_Recycle): as before, logged")
    SV_Recycle = keep
    -- a wreck kept in the units' objects for the take-down, then dropped
    local reg = M.objsOf[U1]
    local kept = reg and reg[a2.addr] ~= nil
    run(125, 1)
    check(kept and (M.objsOf[U1] == nil or M.objsOf[U1][a2.addr] == nil), "join: a wreck kept in the unit's objects (for a refused spawn's take-down), dropped 120 s on")

    print("join: A6, the sync report")
    local rep = COOP.syncReport()
    check(has(rep, "the floor: 0 copies there now") and has(rep, "2 went there") and has(rep, "2 put back up (not your kill)")
          and has(rep, "2 flights refused here") and has(rep, "1 unstuck (1 by SV_Recycle)") and has(rep, "hp for 1 dead copies skipped"),
          "join: " .. rep)
    check(has(rep, "their longest wait 0.") or has(rep, "their longest wait 1."), "join: ... the longest wait at the floor (the host's dn 0.55 s on)")

    print("join: 0.73.79, your missiles at the floor (0.73.78's invincible enemies) and the hp race")
    local U7 = "ERA_Unit_07_Dep_Air0"
    for _, m in ipairs({ "sp|" .. U7 .. "|-|-|-1|40", "bd|" .. U7 .. "|40|1|41", "bd|" .. U7 .. "|40|2|42" }) do
        inbox[#inbox + 1] = "0|" .. m
    end
    run(1)
    local c1, c2 = world[U7][1], world[U7][2]
    check(M.copies[41] and M.copies[42] and c1.HealthInternal == 5000, "join: two fresh copies bound (41, 42)")
    -- your 100 on it lands and the host's hp from before it comes in the same tick: the hit still goes out
    hit(c1, pawn, 100)
    inbox[#inbox + 1] = "0|hp|41:5000"
    s0 = #sent; tick()
    check(table.concat(msgs("ht", s0 + 1), " ") == "-1>ht|41|100.0" and c1.HealthInternal == 4000,
          "join: a hit not yet sent when the host's older hp lands: kept on the copy and sent ("
          .. table.concat(msgs("ht", s0 + 1), " ") .. ", health " .. c1.HealthInternal .. ")")
    inbox[#inbox + 1] = "0|hp|41:5000"
    tick()
    check(c1.HealthInternal == 4000, "join: the host's hp from before your hit, just after it went: not put back to full (flicker)")
    tick(2)
    inbox[#inbox + 1] = "0|hp|41:4000"
    tick()
    check(c1.HealthInternal == 4000 and M.copies[41].exp == 4000, "join: ... the host's hp with your hit in it: taken")
    -- your missile (its own key in the map, not your plane's) takes it to the floor: sent whole, it waits there
    local msl = obj("BP_plwp_msl_a0", 1)
    M.shotMark(msl.addr, c1.addr)
    from = #logs + 1
    hit(c1, msl, 800)
    s0 = #sent; tick()
    check(table.concat(msgs("ht", s0 + 1), " ") == "-1>ht|41|400.0" and c1.HealthInternal == 10 and M.copies[41].floorAt ~= nil,
          "join: your missile at the floor, not in the map under your plane: sent whole, waits at 1 HP (0.73.78: undone, nothing sent) ("
          .. table.concat(msgs("ht", s0 + 1), " ") .. ", health " .. c1.HealthInternal .. ")")
    check(has(line("coop: a copy taken to the floor by your missile", from), "sent whole"), "join: ... logged once")
    -- the host says less than the floor; your missile at it is gone (its hit clamped: health doesn't move): sent again
    inbox[#inbox + 1] = "0|hp|42:5"
    tick()
    local msl2 = obj("BP_plwp_msl_a0", 1)
    M.shotMark(msl2.addr, c2.addr)
    hit(c2, msl2, 300)
    tick()
    M.shotEnd(msl2.addr)
    s0 = #sent; tick()
    check(table.concat(msgs("ht", s0 + 1), " ") == "-1>ht|42|1.0", "join: at the floor, your missile at it gone: the host's last health sent as your hit ("
          .. table.concat(msgs("ht", s0 + 1), " ") .. ")")
    s0 = #sent; tick(); tick(2)
    check(#msgs("ht", s0 + 1) == 0, "join: ... once a missile")
    -- a missile of yours at another copy: a crash into the floor here is still not yours
    local c3 = M.copies[41]
    inbox[#inbox + 1] = "0|dn|41||1"
    tick()
    check(M.copies[41] == nil and c3 ~= nil, "join: (41 down by the host's dn)")
    -- ((0.73.80) [coop] kill_callout: Survival's own DESTROYED on each kill of yours; the game refusing your plane as the
    -- cause: none then, logged)
    CFG.coop.kill_callout = true
    c2.refuse = pawn
    from = #logs + 1
    local cc = #callouts
    inbox[#inbox + 1] = "0|dn|42||1"
    tick()
    check(c2.HealthInternal <= 0 and c2.causers[#c2.causers - 1] == pawn and c2.causers[#c2.causers] == "none",
          "join: your plane refused as the cause: with none (down all the same)")
    check(has(line("coop: the host's kill of copy 42 (yours): taken down here with your plane as its cause REFUSED", from), "with none"),
          "join: ... logged")
    check(#callouts == cc + 1 and callouts[#callouts] == "DESTROYED", "join: [coop] kill_callout on: Survival's DESTROYED callout")
    CFG.coop.kill_callout = false

    print("join: (review of 27097b9, finding 3) the host's Tu-160s withdrawn at a capture: wd")
    local tuC, otherC = obj("BP_OP0060_t160_CP", 5000, true), obj("BP_OP1022_f16c_CP", 5000, true)
    local keepP = planes
    planes = { { obj = tuC, unit = "EA_Unit_01_Air2", k = 0, name = "BP_OP0060_t160_CP_C_1" },
               { obj = otherC, unit = "ERA_Unit_01_Dep_Air0", k = 0, name = "BP_OP1022_f16c_CP_C_1" } }
    local tuP, otherP = planes[1], planes[2]
    from = #logs + 1
    inbox[#inbox + 1] = "0|wd|EA_Unit_01_Air2"
    tick()
    check(tuP.down and tuP.withdrawn and not otherP.down, "join: the host's wd|EA_Unit_01_Air2: its copy here down and withdrawn (the sweep "
          .. "pays and counts no plane down: 0.73.80 paid it as \"you\" at the host's dn with no player), nothing else")
    check(has(line("coop: the host took EA_Unit_01_Air2 off (withdrawn, no despawn event)", from), "1 of its copies here off, unpaid"),
          "join: ... logged")
    s0 = #sent
    check(COOP.withdrawn("EA_Unit_01_Air2") == false and #msgs("wd", s0 + 1) == 0, "join: COOP.withdrawn: the host's alone")
    planes = keepP

    print("join: (code review of 2026-11-07, finding 1) this game's own ZFA-44s' hits on a copy: nobody's")
    UNITS.ERA_Unit_08_Dep_Air0 = { { "BP_OP1022_f16c_CP", 5000, true }, { "BP_OP1022_f16c_CP", 5000, true } }
    local U8 = "ERA_Unit_08_Dep_Air0"
    for _, m in ipairs({ "sp|" .. U8 .. "|-|-|-1|50", "bd|" .. U8 .. "|50|1|51", "bd|" .. U8 .. "|50|2|52" }) do
        inbox[#inbox + 1] = "0|" .. m
    end
    run(1)
    local z1, z2 = world[U8] and world[U8][1], world[U8] and world[U8][2]
    check(z1 and z2 and M.copies[51] and M.copies[52], "join: two fresh copies bound (51, 52)")
    local zfa = obj("BP_OP1024_su47_CP", 3000, true)   -- (a ZFA-44 its copy of the carrier launched here: no co-op id)
    zfaHere[zfa.addr] = true
    check(M.standInSet()[zfa.addr] == -1, "join: this game's own ZFA-44 in the stand-in set as the host's allies' (-1)")
    hit(z1, zfa, 100)
    s0 = #sent; tick()
    check(#msgs("ht", s0 + 1) == 0 and M.copies[51].exp == 4000,
          "join: its 100 on a copy: nothing sent as your hit (" .. table.concat(msgs("ht", s0 + 1), " ") .. ")")
    -- its lethal hit with your plane not yet seen in any copy's map: not sent whole as yours either
    local seen = M.ownSeen
    M.ownSeen = nil
    hit(z2, zfa, 800)
    s0 = #sent; tick()
    check(#msgs("ht", s0 + 1) == 0 and z2.HealthInternal > 10 and not M.copies[52].floorAt,
          "join: its lethal hit at the floor (your plane not yet in the maps): not sent whole as yours, put back up ("
          .. table.concat(msgs("ht", s0 + 1), " ") .. ", health " .. z2.HealthInternal .. ")")
    M.ownSeen = seen
    zfaHere[zfa.addr] = nil
    -- the host's carrier launch forwarded: the arm's check here first, then the event
    evOrder = {}
    inbox[#inbox + 1] = "0|ev|RE_SV_CargoLaunch_1_3"
    tick()
    check(evOrder[1] == "before RE_SV_CargoLaunch_1_3" and evOrder[2] == "fired RE_SV_CargoLaunch_1_3",
          "join: the host's RE_SV_CargoLaunch_1_3: ESC.beforeHostEvent before it fires here (" .. table.concat(evOrder, ", ") .. ")")

    print("join: (code review of 2026-11-07, findings 6 and 13) SAL's boat's copy and an ally taken off")
    local boat = obj("VE028_boat2_CP", 2000)
    function boat:SetActorHiddenInGame(b) self.hidden = b end
    M.copies[95] = { obj = boat, exp = 2000, addr = boat.addr, ally = true, unit = "SV_Unit_SalBoat", key = "VE028_boat2_CP#1", hp = 2000 }
    inbox[#inbox + 1] = "0|hp|95:1500"
    tick()
    check(boat.HealthInternal == 2000 and M.copies[95].hp == 2000,
          "join: the host's hp for SAL's boat: never written onto its copy here (it moves with your own hits alone)")
    from = #logs + 1
    inbox[#inbox + 1] = "0|dn|95|r"
    tick()
    check(boat.HealthInternal == 2000 and boat.hidden == true and boat.bIsInvincible == true and boat.bShowHUDBox == false
          and M.copies[95] == nil, "join: dn|95|r for an ally's copy: switched off here (hidden, invincible, no box), not finished off")
    local due = false
    for _, e in ipairs(M.recycleDue or {}) do if e.unit == "SV_Unit_SalBoat" then due = true end end
    check(due and has(line("coop: the host took an ally off (copy 95", from), "switched off here"),
          "join: ... its unit off this game's list 2 s on (no copy of it left), logged")

    -- ((2026-11-11) a carrier's hull the host took off: never off this game's list while a ZFA-44 of its launchers is up
    -- here (the host's own rule since 0.74.48, Shazzy's crash), looked at again 5 s on)
    print("join: a carrier's hull held on this game's list while its ZFA-44s are up")
    world.SV_Unit_Cargo1 = { obj("cargo_hull", 5000) }
    M.recycleDue = M.recycleDue or {}
    M.recycleDue[#M.recycleDue + 1] = { unit = "SV_Unit_Cargo1", at = clock, why = "carrier leaving" }
    hullHeld = true
    local r0 = #recycled
    tick()
    local held = false
    for _, e in ipairs(M.recycleDue) do if e.unit == "SV_Unit_Cargo1" and e.at > clock then held = true end end
    check(#recycled == r0 and held and holdAsked[#holdAsked] == "1 SV_Unit_Cargo1",
          "join: the hull not recycled while ship 1's ZFA-44s are up here, asked again 5 s on")
    hullHeld = false
    tick(5.25)
    local cargoOff = false
    for i = r0 + 1, #recycled do if recycled[i]:find("^SV_Unit_Cargo1/") then cargoOff = true end end
    check(cargoOff, "join: ... and off the list once none is up (" .. tostring(recycled[#recycled]) .. ")")

    print("join: A9, the host's run-over while the level loads")
    local d0 = #downs
    local keepD = D
    D = nil
    from = #logs + 1
    inbox[#inbox + 1] = "0|ro|9"
    tick()
    check(#downs == d0 + 1 and downs[#downs] == "ro|9" and has(line("coop: the host's run is over (round 9); this level is still loading", from), "comes again"),
          "join: ro with no level yet: handed to sv_down.lua (which needs the level) and logged: it comes with the picture")
    D = keepD
end
print(fails == 0 and (ROLE .. ": all passed") or (ROLE .. ": " .. fails .. " FAILED"))
if fails > 0 then for i = math.max(1, #logs - 30), #logs do print("    log: " .. logs[i]) end end
os.exit(fails == 0 and 0 or 1)
