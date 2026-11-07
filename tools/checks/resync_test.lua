-- resync_test.lua <mod dir> <work dir> <role: host|join> (run by tools/checks/resync_test.sh): a co-op joiner's copies of
-- the host's flights through a resync, on the real sv_config.lua and sv_coop.lua (M exposed), the spawner stubbed as the
-- runtime's (SV_Spawn refuses a unit while anything of its last flight is up: "its last flight is still up"; objects can
-- be invincible). The testers' logs of 0.73.70 (2026-11-01, 12 joiner logs): every kill of the host's was a "stray" on the
-- joiner a few seconds on, its "jn" was answered with "rs" and every copy there was torn down, the host's spawns were
-- refused while the copies it couldn't finish stayed up and flew their own AI, the re-spawned copies of planes long down
-- were paid as kills, and a joiner DOWN came back for free.
-- host: a new level's "rs|n" (and "rs|m" for a host by migration); a joiner's "jn" answered "rs|j", the deaths as
--   "dn|<id>|r", "rz" at the picture's end, everything's health again, the Alicorn's replays with their unit.
-- join: the host's "dn" leaves no stray; a real stray is taken down and the picture asked for; "rs|j" is a repair (copies
--   kept and bound again, a flight the host no longer has taken down at "rz", one missing a plane the host has up spawned
--   again, nothing paid, nobody DOWN back, the round's records kept, a replay for a kept copy not fired); a "bd" / "gd"
--   for a queued spawn doesn't hide the flight still up; a refused spawn takes down whatever of the unit is up, invincible
--   or untracked; "rs|n" is the host's new run, "rs|m" a new host's level, a bare "rs" as before.
local MOD, WORK, ROLE = arg[1], arg[2], arg[3]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end

local clock = 100
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
local logs = {}
function log(s) logs[#logs + 1] = s end
local function line(pat, from)
    for i = #logs, from or 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end
    return nil
end
local function count(pat, from) local n = 0; for i = from or 1, #logs do if logs[i]:find(pat, 1, true) then n = n + 1 end end; return n end
VERSION = "0.73.73-resync.test"
SCRIPT_DIR = WORK .. "/" .. ROLE .. "/Scripts/"
KILL, LB = { side = function() end, read = function() end }, { send = function() end }
RUN = {}
function roundsTick() end
function airfieldTick() end
function bombTick() end
function logPlane() end
function hudCallout() end
function addCredits() end
function poolIndex() return nil end
SPC = {}                                         -- (sv_core's: the specials' functions)
function FindAllOf() return {} end
function FindFirstOf() return nil end
local GS = {}
function GS:ApplyDamage(o, dmg) if not (o.invincible or o.bIsInvincible) then o.HealthInternal = math.max(math.floor((o.MinHealth or 0) * 10), o.HealthInternal - dmg) end end
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
local sent, inbox, events = {}, {}, {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = (to or -1) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/p" end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
local bindsNative = {}
function SV_CoopBind(id, a) bindsNative[id] = (a ~= 0) and a or nil; return 1 end
function SV_MenuSetting() return "" end
local menu = 0
function SV_MenuChoice() return menu end
function SV_Event(name) events[#events + 1] = name; return 1 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end

-- the spawner: each unit's objects made in the same order on every game; a unit is refused while anything of its last
-- flight is up (the runtime's Recycle: SV_ERR_UP); objects can be invincible (a taxiing ally, the shuttle's pad)
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
local nextAddr = 0x1000
local function obj(cls, hp, plane, inv)
    nextAddr = nextAddr + 0x10
    local o = { name = cls .. "_C /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel." .. cls .. "_C_" .. nextAddr,
                addr = nextAddr, HealthInternal = hp, min = 0, plane = plane == true, invincible = inv == true }
    function o:IsA() return self.plane end
    -- (as the game's: SetMinHealth keeps whole points only, every hit is clamped at the MinHealth field: 0.73.77's floor
    -- writes the field, KILLS_HEALTH_DEATH.md 1-2)
    function o:SetMinHealth(v) self.MinHealth = math.floor(v) end
    function o:SetIsInvincible(b) self.invincible = b end
    function o:ModifyHealth(d)
        if self.invincible or self.bIsInvincible then return end
        self.HealthInternal = math.max(math.floor((self.MinHealth or 0) * 10), self.HealthInternal + d * 10)
    end
    return o
end
local UNITS = {
    ERA_Unit_01_Dep_Air0 = { { "BP_OP1022_f16c_CP", 5000, true }, { "BP_OP1022_f16c_CP", 5000, true } },
    ERA_Unit_02_Dep_Air0 = { { "BP_OP1030_su33_CP", 5000, true }, { "BP_OP1030_su33_CP", 5000, true } },
    ERA_Unit_04_Dep_Air0 = { { "BP_OP1009_su34_CP", 5000, true } },
    ERA_Unit_06_Dep_Air0 = { { "BP_OP1027_m21b_CP", 5000, true }, { "BP_OP1027_m21b_CP", 5000, true } },
    SV_Unit_LcacA = { { "BP_SH010_lcac", 5000 }, { "BP_SH010_lcac", 5000 } },
    SV_Unit_VoidWatcher = { { "BP_OP0005_e767_CP_Ally", 9000, true, true } },          -- (invincible until airborne)
    SV_Unit_PadDummies = { { "BP_GR_paddummy", 1000, false, true }, { "BP_GR_paddummy", 1000, false, true } },   -- (invincible)
}
local world, refused, pendingPlanes = {}, 0, {}
local function up(o) return not o.gone and o.HealthInternal > 0 end
function SV_Spawn(unit, x)
    for _, o in ipairs(world[unit] or {}) do if up(o) then refused = refused + 1; return -3 end end
    world[unit] = {}
    for i, d in ipairs(UNITS[unit] or {}) do
        local o = obj(d[1], d[2], d[3], d[4])
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

-- the other parts this one tells: the revives (sv_down.lua), the measurements (sv_stats.lua), a new run (sv_main.lua)
local downResets, statsResets, newRuns = {}, {}, {}
DOWN = { reset = function(why) downResets[#downResets + 1] = why end, me = function() return false end }
STATS = { hostReset = function(now, resync) statsResets[#statsResets + 1] = resync end, roundEnd = function() end,
          roundStart = function() end }
function newRunHere(why) newRuns[#newRuns + 1] = why end

-- load the real parts (sv_coop with its M exposed)
PARTS.dofile("sv_config.lua")
PARTS.load("sv_coop.lua", "=sv_coop.lua", { { "\nlocal M = {", "\nM = {" } })   -- (its pieces too; M exposed)
local M = _G.M
CFG.coop.enabled = true
local function tick(dt)
    clock = clock + (dt or 0.25)
    local p = pendingPlanes
    pendingPlanes = {}
    for _, e in ipairs(p) do logPlane(e.o, e.unit, e.k) end      -- (sv_main: AI planes logged a tick or two after they're made)
    COOP.tick(0)
    if COOP.client() then roundsTick(clock) end
end
local function run(s, dt) local t = 0; while t < s do tick(dt or 0.25); t = t + (dt or 0.25) end end
local function msgs(kind, from)
    local t = {}
    for i = from or 1, #sent do if sent[i]:match("^%-?%d+>" .. kind .. "|") or sent[i]:match("^%-?%d+>" .. kind .. "$") then t[#t + 1] = sent[i] end end
    return t
end

if ROLE == "host" then
    print("host: the new level's rs, a joiner's jn answered as a repair")
    menu = 16 + 3; tick()
    check(COOP.host(), "host: hosting")
    local s0 = #sent
    D = { round = 3, state = "fight" }
    tick()
    check(table.concat(msgs("rs", s0 + 1), " ") == "-1>rs|n", "host: a new level: \"rs|n\", the host's new run (" .. table.concat(msgs("rs", s0 + 1), " ") .. ")")
    -- a flight and a ship up, one plane of the flight shot down
    spawningUnit = "ERA_Unit_01_Dep_Air0"; SV_Spawn("ERA_Unit_01_Dep_Air0"); spawningUnit = nil
    spawningUnit = "SV_Unit_LcacA"; SV_Spawn("SV_Unit_LcacA"); spawningUnit = nil
    run(1.5)
    local ids = {}
    for _, m in ipairs(msgs("bd")) do local id = m:match("bd|ERA_Unit_01_Dep_Air0|%d+|%d+|(%d+)"); if id then ids[#ids + 1] = tonumber(id) end end
    check(#ids == 2 and #msgs("gd") == 2, "host: the flight's planes and the craft linked (bd 2, gd 2)")
    world.ERA_Unit_01_Dep_Air0[1].HealthInternal = 0
    tick()
    check(has(table.concat(msgs("dn"), " "), "-1>dn|" .. ids[1]), "host: the plane shot down: dn|" .. tostring(ids[1]) .. " to everyone")
    run(1.5)
    -- a joiner's jn
    local j0 = #sent
    inbox[#inbox + 1] = "1|jn"
    tick()
    local pic = {}
    for i = j0 + 1, #sent do if sent[i]:match("^1>") then pic[#pic + 1] = sent[i] end end
    local all = table.concat(pic, "\n")
    check(pic[1] == "1>rs|j", "host: the answer starts \"rs|j\" (its answer to that joiner's jn, not a new run): " .. tostring(pic[1]))
    check(has(all, "1>dn|" .. ids[1] .. "|r") and not has(all, "1>dn|" .. ids[1] .. "\n"), "host: the plane long down repeated as \"dn|" .. ids[1] .. "|r\"")
    local iz, ilast = nil, 0
    for i, m in ipairs(pic) do
        if m:match("^1>rz|") then iz = i end
        if m:match("^1>[bg]d|") or m:match("^1>sp|") or m:match("^1>dn|") then ilast = i end
    end
    check(iz and iz > ilast and pic[iz] == "1>rz|2", "host: \"rz|2\" after the picture's last flight (" .. tostring(iz and pic[iz]) .. ")")
    local hp = table.concat(msgs("hp", j0 + 1), " ")       -- (in the same tick: hostTick runs after the messages)
    check(has(hp, "hp|") and has(hp, ids[2] .. ":5000"),
          "host: every copy's health sent again with it, unchanged or not (a copy spawned again there has its stock health): " .. hp)
    -- the Alicorn's state, 12 s on, with its unit
    SPC.alicornUnit = "SV_Unit_Alicorn"
    D.special = { kind = "alicorn", state = "sail", coreOpen = true, dived = true }
    inbox[#inbox + 1] = "1|jn"
    tick()
    run(13, 0.5)
    local ev = table.concat(msgs("ev"), " ")
    check(has(ev, "1>ev|RE_SV_AlcnAdvance|SV_Unit_Alicorn") and has(ev, "1>ev|RE_SV_AlcnDive|SV_Unit_Alicorn"),
          "host: the Alicorn's replays name its unit (a joiner fires them on a fresh copy only)")
    D.special, SPC.alicornUnit = nil, nil
    -- a host by migration's level
    M.mig = { hosting = true }
    local m0 = #sent
    D = { round = 6, state = "wait" }
    tick()
    check(table.concat(msgs("rs", m0 + 1), " ") == "-1>rs|m", "host: a host by migration's new level: \"rs|m\" (the same run)")
    M.mig = nil
else
    menu = 16 + 4; tick()
    check(COOP.client(), "join: joined")
    D = { round = 5, state = "fight", now = clock }
    survivalPC = { Pawn = { addr = 0x9, HealthInternal = 1000, name = "pawn" } }
    tick(); run(3.5)
    M.jnAt, M.resyncAt = nil, 0                       -- (the new level's own jn: long ago)
    local function bound(id, o) return M.copies[id] ~= nil and M.copies[id].addr == o.addr and bindsNative[id] == o.addr end
    local function jnCount(from) return #msgs("jn", from) end

    ------------------------------------------------------------------------------------------------ the host's kill: no stray
    print("join: the host's kill leaves no stray (105 of 115 jn in the testers' logs)")
    local U1 = "ERA_Unit_01_Dep_Air0"
    inbox[#inbox + 1] = "0|sp|" .. U1 .. "|-|-|-1|1"
    inbox[#inbox + 1] = "0|bd|" .. U1 .. "|1|1|11"
    inbox[#inbox + 1] = "0|bd|" .. U1 .. "|1|2|12"
    run(1)
    local a1, a2 = world[U1][1], world[U1][2]
    check(bound(11, a1) and bound(12, a2), "join: the host's flight spawned here, both copies bound (the ids came before its spawn ran)")
    local from, s0 = #logs + 1, #sent
    inbox[#inbox + 1] = "0|dn|11"
    tick()
    check(a1.HealthInternal <= 0 and not COOP.tornDown({ addr = a1.addr }) and M.copies[11] == nil and M.cunits[U1].planes[1] == nil,
          "join: the host's kill (dn): down here, a kill (not torn), off its flight's planes here")
    run(25)
    check(jnCount(s0 + 1) == 0 and not line("stray", from) and up(a2) and bound(12, a2),
          "join: 25 s on, no stray and no jn (0.73.70 took it down again 1-2 s on as a stray and asked for the whole picture)")

    ------------------------------------------------------------------------------------------------ a real stray
    print("join: a copy never bound is still a stray: taken down, then the host's picture asked for")
    local U2 = "ERA_Unit_02_Dep_Air0"
    inbox[#inbox + 1] = "0|sp|" .. U2 .. "|-|-|-1|2"
    inbox[#inbox + 1] = "0|bd|" .. U2 .. "|2|1|21"                -- (its second plane's id never comes)
    run(1)
    local b1, b2 = world[U2][1], world[U2][2]
    from, s0 = #logs + 1, #sent
    run(16)
    check(b2.HealthInternal <= 0 and COOP.tornDown({ addr = b2.addr }) and up(b1) and bound(21, b1),
          "join: 15 s on, the unbound copy taken down (torn: not a kill); the bound one left")
    check(jnCount(s0 + 1) == 1 and has(line("coop: 1 stray enemy copies taken down", from), "asked the host for its whole picture (jn)"),
          "join: ... and the host's picture asked for, once (" .. tostring(line("stray", from)) .. ")")

    ------------------------------------------------------------------------------------------------ the repair
    print("join: the host's answer (rs|j) is a repair, not a teardown")
    local U4, LC, VW = "ERA_Unit_04_Dep_Air0", "SV_Unit_LcacA", "SV_Unit_VoidWatcher"
    inbox[#inbox + 1] = "0|sp|" .. U4 .. "|-|-|-1|4"
    inbox[#inbox + 1] = "0|bd|" .. U4 .. "|4|1|41"
    inbox[#inbox + 1] = "0|sp|" .. LC .. "|-|-|-1|3"
    inbox[#inbox + 1] = "0|gd|" .. LC .. "|3|BP_SH010_lcac_C#1|31"
    inbox[#inbox + 1] = "0|gd|" .. LC .. "|3|BP_SH010_lcac_C#2|32"
    inbox[#inbox + 1] = "0|sp|" .. VW .. "|-|-|-1|5"
    inbox[#inbox + 1] = "0|bd|" .. VW .. "|5|1|51"
    run(5)
    local d1, l1, l2, v1 = world[U4][1], world[LC][1], world[LC][2], world[VW][1]
    check(bound(41, d1) and M.copies[31] and M.copies[32] and bound(51, v1), "join: (a flight, two craft and VOID WATCHER 1 up here, bound)")
    M.copies[12] = nil; bindsNative[12] = nil                     -- (a bind lost: the picture's id binds it again)
    RUN.credits = 4321
    from, s0 = #logs + 1, #sent
    local dr, sr, nr, round0 = #downResets, #statsResets, #newRuns, D.round
    for _, m in ipairs({ "rs|j",
        "sp|" .. U1 .. "|-|-|-1|1", "bd|" .. U1 .. "|1|1|11", "dn|11|r", "bd|" .. U1 .. "|1|2|12",
        "sp|" .. U2 .. "|-|-|-1|2", "bd|" .. U2 .. "|2|1|21", "bd|" .. U2 .. "|2|2|22",
        "sp|" .. LC .. "|-|-|-1|3", "gd|" .. LC .. "|3|BP_SH010_lcac_C#1|31", "gd|" .. LC .. "|3|BP_SH010_lcac_C#2|32",
        "sp|" .. VW .. "|-|-|-1|5", "bd|" .. VW .. "|5|1|51", "rz|4",
        "ev|RE_SV_AlcnAdvance|" .. LC }) do                         -- (U4: the host has none of it up any more)
        inbox[#inbox + 1] = "0|" .. m
    end
    tick()
    check(not line("copies taken down (", from) and up(a2) and up(l1) and up(l2) and up(v1),
          "join: no teardown: the copies the host has up are kept (0.73.70: \"29 copies taken down (the host's run started over)\")")
    check(bound(12, a2), "join: the lost bind bound again by the picture's id")
    check(d1.HealthInternal <= 0 and COOP.tornDown({ addr = d1.addr }) and M.cunits[U4] == nil,
          "join: the flight the host no longer has: taken down at the picture's end (torn: not a kill)")
    check(#downResets == dr and #statsResets == sr and #newRuns == nr and D.round == round0 and RUN.credits == 4321,
          "join: nobody DOWN brought back, the round's records and the money kept, the round number left as it is")
    check(not has(table.concat(events, " "), "RE_SV_AlcnAdvance") and has(line("not fired here", from), "kept through the resync"),
          "join: a replay for a copy kept through the resync not fired (it had it already)")
    local rl = line("coop: the host's picture (4 flights)", from)
    check(has(rl, "3 kept here as they were (1 copies bound again)") and has(rl, "1 spawned again") and has(rl, U2 .. " (1 of its planes)")
          and has(rl, "1 taken down") and has(rl, U4), "join: the picture's line: " .. tostring(rl))
    run(4)
    local nb1, nb2 = world[U2][1], world[U2][2]
    check(nb1 ~= b1 and b1.HealthInternal <= 0 and COOP.tornDown({ addr = b1.addr }) and bound(21, nb1) and bound(22, nb2),
          "join: the flight missing a plane the host has up: spawned again whole, both bound (its old copy torn: not a kill)")
    check(has(line("coop: " .. U2 .. " is up here (1 alive; a plane of it the host has up wasn't here: spawned again)", from), "1 of its objects taken down"),
          "join: ... logged")
    check(count("stray", from) == 0 and refused == 0, "join: no strays after it, nothing refused")

    ------------------------------------------------------------------------------------------------ the generation race
    print("join: a bd for the host's next spawn of a unit doesn't hide the copy still up (409 refusals)")
    from = #logs + 1
    inbox[#inbox + 1] = "0|sp|" .. VW .. "|-|-|-1|6"
    inbox[#inbox + 1] = "0|bd|" .. VW .. "|6|1|61"
    tick()
    check(M.cunits[VW] and (M.cunits[VW].gen == 5 or M.cunits[VW].gen == 6) and not (M.cunits[VW].gen == 6 and M.cunits[VW].n == 0 and up(v1)),
          "join: the bd for gen 6 kept for its spawn, not an empty gen-6 flight in place of the one up here")
    run(4)
    local v2 = world[VW][1]
    check(v1.HealthInternal <= 0 and COOP.tornDown({ addr = v1.addr }) and v2 ~= v1 and bound(61, v2) and refused == 0
          and not line("not spawned here", from), "join: the invincible copy (gen 5) taken down (forced), the host's gen 6 spawned and bound")
    check(has(line("coop: " .. VW .. " is up here (1 alive; its last flight here, gen 5)", from), "1 of its objects taken down for the host's (gen 6)"),
          "join: ... logged: " .. tostring(line("is up here", from)))

    ------------------------------------------------------------------------------------------------ the host's new run; leftovers
    print("join: the host's new run (rs|n); what a teardown couldn't finish, taken down when the host spawns it again")
    local PD = "SV_Unit_PadDummies"
    inbox[#inbox + 1] = "0|sp|" .. PD .. "|-|-|-1|7"
    inbox[#inbox + 1] = "0|gd|" .. PD .. "|7|BP_GR_paddummy_C#1|71"
    inbox[#inbox + 1] = "0|gd|" .. PD .. "|7|BP_GR_paddummy_C#2|72"
    run(2)
    local p1, p2 = world[PD][1], world[PD][2]
    check(M.copies[71] and M.copies[72], "join: (the pad's invincible dummies up, bound)")
    from = #logs + 1
    dr, nr = #downResets, #newRuns
    inbox[#inbox + 1] = "0|rs|n"
    tick()
    check(#downResets == dr + 1 and #newRuns == nr + 1 and has(line("copies taken down (the host's run started over)", from), "copies"),
          "join: rs|n: the host's new run: copies taken down, the run here started over, nobody left DOWN")
    check(v2.HealthInternal <= 0 and up(p1) and up(p2) and next(M.cunits) == nil,
          "join: ... an allied plane forced down; the pad's invincible dummies stay up (ground, as before), untracked")
    inbox[#inbox + 1] = "0|sp|" .. PD .. "|-|-|-1|8"
    inbox[#inbox + 1] = "0|gd|" .. PD .. "|8|BP_GR_paddummy_C#1|81"
    run(4)
    check(p1.HealthInternal <= 0 and p2.HealthInternal <= 0 and world[PD][1] ~= p1 and M.copies[81] and refused == 0
          and has(line("coop: " .. PD .. " is up here (2 alive; no longer tracked here)", from), "2 of its objects taken down for the host's (gen 8)"),
          "join: the host's next spawn of them: the leftovers taken down (forced, untracked), its own spawned (0.73.70: \"0 of its planes\")")

    ------------------------------------------------------------------------------------------------ dead on arrival
    print("join: a copy of a plane the host shot down long ago, spawned here again: not a kill (109 phantom kills)")
    local U6 = "ERA_Unit_06_Dep_Air0"
    inbox[#inbox + 1] = "0|sp|" .. U6 .. "|-|-|-1|9"
    inbox[#inbox + 1] = "0|bd|" .. U6 .. "|9|1|91"
    inbox[#inbox + 1] = "0|dn|91"
    inbox[#inbox + 1] = "0|bd|" .. U6 .. "|9|2|92"
    run(1)
    local e1, e2 = world[U6][1], world[U6][2]
    check(e1.HealthInternal <= 0 and COOP.tornDown({ addr = e1.addr }) and M.cunits[U6].planes[1] == nil and bound(92, e2),
          "join: down on arrival as not a kill (torn), off its flight's planes; the other bound")
    inbox[#inbox + 1] = "0|dn|92|r"
    tick()
    check(e2.HealthInternal <= 0 and COOP.tornDown({ addr = e2.addr }), "join: \"dn|<id>|r\" (the picture's: long since): not a kill here")

    ------------------------------------------------------------------------------------------------ rs|m, a bare rs
    print("join: rs|m (a new host's level) and a bare rs")
    dr, nr = #downResets, #newRuns
    RUN.credits = 777
    inbox[#inbox + 1] = "0|rs|m"
    tick()
    check(#downResets == dr and #newRuns == nr and statsResets[#statsResets] == true, "join: rs|m: no new run, nobody DOWN back, the round cut short")
    M.jnAt = clock - 5
    inbox[#inbox + 1] = "0|rs"
    tick()
    check(#downResets == dr and #newRuns == nr, "join: a bare rs 5 s after this game's jn (an older host's answer): no new run, nobody DOWN back")
    M.jnAt = clock - 100
    inbox[#inbox + 1] = "0|rs"
    tick()
    check(#downResets == dr + 1 and #newRuns == nr + 1, "join: a bare rs otherwise: the host's new run")

    ------------------------------------------------------------------------------------------------ the picture never ends
    print("join: a picture with no end (rz) in 10 s: the flights it named spawned, the others kept")
    D.round = 5
    local U7 = "ERA_Unit_01_Dep_Air0"
    inbox[#inbox + 1] = "0|sp|" .. U7 .. "|-|-|-1|10"
    inbox[#inbox + 1] = "0|bd|" .. U7 .. "|10|1|101"
    inbox[#inbox + 1] = "0|bd|" .. U7 .. "|10|2|102"
    run(2)
    from = #logs + 1
    inbox[#inbox + 1] = "0|rs|j"
    inbox[#inbox + 1] = "0|sp|" .. U6 .. "|-|-|-1|11"
    inbox[#inbox + 1] = "0|bd|" .. U6 .. "|11|1|111"
    run(5)
    check(M.rep and not M.rep.done and world[U6][1] == e1, "join: the repair waits for rz (the flight it named not spawned yet)")
    run(7)
    check(M.rep and M.rep.done and has(line("coop: the host's picture (1 flights; no end of the host's picture in 10 s", from), "the flights it didn't name kept")
          and M.cunits[U7] and up(world[U7][1]) and bound(111, world[U6][1]),
          "join: 10 s on: settled without it, the flight it didn't name kept, the one it named spawned")
end
print(fails == 0 and (ROLE .. ": all passed") or (ROLE .. ": " .. fails .. " FAILED"))
if fails > 0 then for i = math.max(1, #logs - 25), #logs do print("    log: " .. logs[i]) end end
os.exit(fails == 0 and 0 or 1)
