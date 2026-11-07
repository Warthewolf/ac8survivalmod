-- coop_rejoin_test.lua <mod dir> <work dir> (run by tools/checks/coop_rejoin_test.sh): 0.73.77, the plan's workstreams
-- C and D, on the real sv_config.lua and sv_coop.lua (M exposed) and sv_anomalies.lua's mood functions, the game and the
-- runtime stubbed (SV_CoopSpawnPP destroys what its slot holds, as coop.c does):
--   C, real planes, the host: a loadout change by a player who never left keeps their plane (the next level's); one who
--     left and is back in another aircraft: the old plane set aside (unbound, hidden, collision and tick off, moved up,
--     moved out of its slot in the runtime before the new one spawns: never destroyed), the new one spawned, the line;
--     back in the same aircraft: kept; back with no airframe heard yet: the old plane hidden, then replaced; no airframe
--     in wait_s: kept; a newcomer in the slot a set-aside plane is kept in: moved on first; a game started over ("rj");
--   C, a joiner: the host's "po" / "rj" mark it, the host's "pi" brings the new airframe;
--   C4, AI stand-ins: the old one set aside, its unit never flown again, the new one on a free unit, mapped back to its
--     player (their plane, their name on its box);
--   D1-D2, VALKA's mood: SPC.V.mood tells the joiners first (an error in the host's own sky doesn't stop it), the host's
--     watch on her round's state (a mood set another way, her reveal, her end, the run over, her round gone with it on),
--     again in the whole picture for a joiner who asks (jn); a joiner: on / off, not here without a run, off on the
--     host's new run, a new run here, this game becoming the host;
--   D3, a joiner's special-round music: the host's "rnd" field 11, its specialFor never rolling dice of its own; the
--     host's field from its pick, never rolling a round not picked yet;
--   rejoin off; the migration's set-aside the same way;
--   (0.73.83) the radar ("people who leave and rejoin, their plane disappears correctly but not their radar blip"): a plane
--     hidden here is deactivated (bIsActivated false) and put back as it was when shown (left, rejoined in the same
--     aircraft, DOWN, a stand-in); a set-aside one also moved aside_far_km off the map and kept there and deactivated
--     (asideTick puts it back once, said once); radar_off = false leaves the flag; a new run keeps what to put back;
--     its review: a reused address never touched (the name checked), off again when the game put a hidden plane back on,
--     the level going forgets them all.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return (s:gsub("\r\n", "\n")) end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local clock = 100
os.clock = function() return clock end           -- luacheck: ignore

-- the game, stubbed
local logs, callouts = {}, {}
function log(s) logs[#logs + 1] = s end
VERSION = "0.73.77-rejoin.test"
SCRIPT_DIR = WORK .. "/Scripts/"
KILL, LB = { side = function() end }, { send = function() end }
RUN = { credits = 1000, spent = 0, msg = {}, bought = {} }
SETUP = { startRound = function() return 1 end, specialsX = function() return 1 end }
function roundsTick() end
function airfieldTick() end
function bombTick() end
function logPlane() end
function hudCallout(t, sub) callouts[#callouts + 1] = tostring(t) .. " / " .. tostring(sub) end
function addCredits() end
local ppList = {}
function FindAllOf(c) if c == "LivePlayerPlane" then return ppList end return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function inSurvival() return true end
function playerOnAirfield() return false end
function gamePaused() return false end
function NotifyOnNewObject() end
local classes = {}
-- (0.73.80) a class path listed in notInstalled doesn't load (an add-on this game hasn't: the Falken's own blueprint)
local notInstalled = {}
function loadObject(path)
    if notInstalled[path] then return nil end
    local o = { addr = 7000 + #classes, path = path, full = "BlueprintGeneratedClass " .. path }   -- ((0.73.80) named: M.isPlayerPlaneClass)
    classes[o.addr] = path; classes[#classes + 1] = o; return o
end
SV_ERR = {}

local nextAddr = 1000
local function plane(full)
    nextAddr = nextAddr + 1
    local o = { full = full, addr = nextAddr, X = 1000, Y = 2000, Z = 300000, HealthInternal = 1000, bIsActivated = true }
    function o:SetActorHiddenInGame(v) self.hidden = v end
    function o:SetActorEnableCollision(v) self.coll = v end
    function o:SetActorTickEnabled(v) self.tick = v end
    function o:K2_GetActorLocation() return { X = self.X, Y = self.Y, Z = self.Z } end
    function o:K2_SetActorLocation(v) self.X, self.Y, self.Z = v.X, v.Y, v.Z; return true end
    function o:K2_DestroyActor() self.destroyed = true end
    function o:SetIsInvincible() end
    function o:GetAddress() return self.addr end
    return o
end
local pawn = plane("BP_PlayerPlane_PP0022_f16c_C_0")
survivalPC = { Pawn = pawn, full = "PC" }

-- the runtime, stubbed: its per-slot real planes (g_peerPP) and calls in order
local seq, native, sent, inbox, setAc, names, alive = {}, {}, {}, {}, {}, {}, {}
local function seqSince(n) local t = {}; for i = n + 1, #seq do t[#t + 1] = seq[i] end; return table.concat(t, ", ") end
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = (to or -1) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;mode=steam;state=linked;slot=0;players=2;max=24;me=0;cands=0;tele=1;peers=1/linked/40/10/Lil" end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer(s, a) seq[#seq + 1] = "peer " .. s .. "=" .. tostring(a); return 1 end
function SV_CoopSwapPP(a, b) native[a], native[b] = native[b], native[a]; seq[#seq + 1] = "swap " .. a .. "<>" .. b; return 1 end
local spawnArgs = {}                              -- ((0.73.80) each spawn's loadout and paint, by slot)
function SV_CoopSpawnPP(pawnA, x, y, z, yaw, clsA, slot, lo, pt)
    spawnArgs[slot] = { lo = lo, pt = pt }
    local old = native[slot]
    if old and not old.gone then old.destroyedBySpawn, old.gone = true, true end   -- (coop.c: "a second call removes that slot's")
    local d = (classes[clsA] or ""):match("Plane/([^/]+)/") or "PP0000_x"
    local o = plane("BP_PlayerPlane_" .. d .. "_C_" .. nextAddr)
    o.X, o.Y, o.Z = x, y, z
    native[slot] = o
    ppList[#ppList + 1] = o
    seq[#seq + 1] = "spawnPP " .. slot .. " " .. d
    return o.addr
end
local peerState = {}
function SV_CoopPeerAt(slot) return peerState[slot] or "" end
function SV_Spawn(unit) seq[#seq + 1] = "spawn " .. unit; return 1 end
function SV_SetAircraft(unit, row) setAc[#setAc + 1] = unit .. "=" .. tostring(row); return 1 end
function SV_SetLevel() return 1 end
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_Event() return 1 end
function SV_SetText(k, n) names[k] = n end
function SV_MenuSetting() return "" end
local menu = 0
function SV_MenuChoice() return menu end

PARTS.dofile("sv_config.lua")
do                                                -- (sv_spawn.lua's own specialOn / specialFor, before sv_coop wraps it)
    local sp = readAll(MOD .. "/Scripts/sv_spawn.lua")
    local a1 = sp:find("function specialOn(kind)", 1, true)
    local tail = "    return specialOn(kind) and kind or nil\nend\n"
    local a2 = a1 and sp:find(tail, a1, true)
    assert(a1 and a2, "sv_spawn.lua: specialOn / specialFor not found")
    assert(load(sp:sub(a1, a2 + #tail - 1), "=sv_spawn specialFor"))()
end
PARTS.load("sv_coop.lua", "=sv_coop.lua", { { "\nlocal M = {", "\nM = {" } })   -- (its pieces too; M exposed)
local M = _G.M
CFG.coop.enabled = true
local function tick(dt) clock = clock + (dt or 0.25); M.nextInfo = 0; COOP.tick(0) end
local function line(part, from) for i = #logs, from or 1, -1 do if has(logs[i], part) then return logs[i] end end end
local function sentOf(kind, from) local t = {}; for i = from or 1, #sent do if sent[i]:match("^%-?%d+>" .. kind .. "|") then t[#t + 1] = sent[i] end end; return t end
local FRESH = "500000,0,300000,0,90,0,1000,100,3,100"      -- (in the mission, alive, a tenth of a second old)
local LO1, LO2, LO3 = "11,12//1,2", "21,22//3,4", "31,32//5,6"
local function hi(slot, row, code, lo, ac) return string.format("%d|hi|%s|0.32.21|%s|Lil|%s|%s||%s", slot, VERSION, row, code, lo or "", ac or "") end

---------------------------------------------------------------------------------------------------- C: real planes, the host
print("C: a rejoin in another aircraft, real planes (the host)")
menu = 16 + 3; tick()
check(COOP.host(), "hosting")
D = { round = 5, state = "fighting", now = 100, startRound = 1, up = {}, flown = {} }
tick()
inbox[#inbox + 1] = "1|sys|joined"
inbox[#inbox + 1] = hi(1, "su47_common", "su47", LO1, "SU-47")
peerState[1] = FRESH
tick(); tick(4)
local su47 = native[1]
check(su47 and has(su47.full, "su47") and M.peers[1] and M.peers[1].obj == su47 and M.peers[1].real,
      "player 2's real Su-47 spawned in their slot (" .. tostring(su47 and su47.full) .. ")")
-- a loadout change by a player who never left: kept (the next level's has it)
local from, n0 = #logs + 1, #seq
inbox[#inbox + 1] = hi(1, "su47_common", "su47", LO2, "SU-47")
tick()
check(native[1] == su47 and M.peers[1].obj == su47 and not has(seqSince(n0), "spawnPP") and line("player 2's loadout changed: their real plane here keeps", from),
      "new weapons from a player who never left: their plane kept, said so (today's rule)")
-- they leave: marked, hidden
from = #logs + 1
inbox[#inbox + 1] = "1|sys|left"
peerState[1] = ""
tick()
check(M.left[1] ~= nil and su47.hidden == true and line("coop: player 2 left: if they're back in another aircraft", from),
      "left: their plane hidden, a rejoin marked (" .. tostring(line("coop: player 2 left", from)) .. ")")
check(su47.bIsActivated == false and line("coop: player 2's plane hidden (left): off the radar (deactivated)", from) ~= nil,
      "(0.73.83) left: off the radar too (deactivated), said so")
-- back 18 s later in a Rafale M (liljojofett, Shake Shack's run of 2026-11-02)
clock = clock + 18
from, n0 = #logs + 1, #seq
inbox[#inbox + 1] = "1|sys|joined"
inbox[#inbox + 1] = hi(1, "rflm_common", "rflm", LO2, "RAFALE M")
peerState[1] = FRESH
tick()
local rflm = native[1]
check(rflm and has(rflm.full, "rflm") and M.peers[1].obj == rflm and M.peers[1].real and M.peers[1].code == "rflm",
      "back in a Rafale M: their real Rafale M spawned (" .. tostring(rflm and rflm.full) .. ")")
check(line("coop: player 2 rejoined in rflm (was su47): old plane set aside, new one spawned (their real plane)", from) ~= nil,
      "the plan's line: rejoined in rflm (was su47): old plane set aside, new one spawned")
local order = seqSince(n0)
local pU, pS, pP = order:find("peer 1=0", 1, true), order:find("swap 1<>23", 1, true), order:find("spawnPP 1 PP0014_rflm", 1, true)
check(pU and pS and pP and pU < pS and pS < pP, "unbound, moved out of slot 2 into slot 24, then the new one spawned in slot 2 (" .. order .. ")")
check(not su47.gone and not su47.destroyedBySpawn and not su47.destroyed and native[23] == su47 and M.parkAt[23] and M.parkAt[23].obj == su47,
      "the Su-47 never destroyed: kept in slot 24 in the runtime")
check(su47.hidden == true and su47.coll == false and su47.tick == false and su47.Z == 3000000,
      "the Su-47 hidden, collision and tick off, 30 km up (" .. tostring(su47.Z) .. ")")
check(su47.X == 100000000 and su47.Y == 2000000 and su47.bIsActivated == false,
      "(0.73.83) ... and 1000 km off the map, deactivated: off the radar (" .. tostring(su47.X) .. ", " .. tostring(su47.Y) .. ")")
check(line("coop: player 2's plane here set aside, hidden (they rejoined in another aircraft): kept in slot 24, tick off, moved 30 km up "
           .. "and 1000 km off the map; off the radar already", from) ~= nil,
      "the set-aside's line (" .. tostring(line("set aside", from)) .. ")")
check(rflm.bIsActivated == true, "the new Rafale M on the radar (never deactivated)")
-- (0.73.83) the game puts the set-aside plane back (a restart in the same level): asideTick puts it off the radar again, once said
do
    local f0 = #logs + 1
    su47.bIsActivated, su47.X = true, 5000
    tick(5.1)
    check(su47.bIsActivated == false and su47.X == 100000000 and line("set-aside plane was activated again (by the game): deactivated again", f0) ~= nil
          and line("set-aside plane was moved back (by the game", f0) ~= nil, "(0.73.83) put back by the game: off the radar and the map again, said so")
    su47.bIsActivated = true
    tick(5.1)
    local n = 0
    for i = f0, #logs do if has(logs[i], "activated again (by the game)") then n = n + 1 end end
    check(su47.bIsActivated == false and n == 1, "... again: put back, said once")
end
tick()
check(M.peers[1].shown == true and has(seq[#seq] or "", "peer 1=" .. rflm.addr) or line("coop: player 2's plane shown", from) ~= nil,
      "the new one shown and bound to their stream")
-- back in the same aircraft: kept
inbox[#inbox + 1] = "1|sys|left"; peerState[1] = ""; tick()
from, n0 = #logs + 1, #seq
inbox[#inbox + 1] = "1|sys|joined"; inbox[#inbox + 1] = hi(1, "rflm_common", "rflm", LO2, "RAFALE M"); peerState[1] = FRESH
tick()
check(native[1] == rflm and M.peers[1].obj == rflm and not has(seqSince(n0), "spawnPP") and not has(seqSince(n0), "swap")
      and line("coop: player 2 is back in the same rflm: their plane here kept", from) ~= nil and rflm.hidden == false,
      "back in the same Rafale M with the same weapons: kept and shown")
check(rflm.bIsActivated == true and line("coop: player 2's plane shown; on the radar again (activated)", from) ~= nil,
      "(0.73.83) ... and on the radar again (" .. tostring(line("player 2's plane shown", from)) .. ")")
-- (0.73.83) DOWN: hidden and off the radar, back on it when they're up again
do
    local DOWNST = "500000,0,300000,0,90,0,1000,100,9,100"   -- (their stream's flags: in the mission, DOWN)
    local f0 = #logs + 1
    peerState[1] = DOWNST; tick()
    check(rflm.hidden == true and rflm.bIsActivated == false and line("coop: player 2's plane hidden (down); off the radar (deactivated)", f0) ~= nil,
          "(0.73.83) DOWN: hidden and off the radar")
    -- a new run here (a restart in the same level: the players' tables made again, the planes kept) keeps what to put back
    local Dkeep, Pold = D, M.peers[1]
    D = { round = 1, state = "break", now = clock, startRound = 1, up = {}, flown = {} }
    tick()
    check(M.peers[1] ~= Pold and M.peers[1].obj == rflm and rflm.hidden == true and rflm.bIsActivated == false,
          "(0.73.83) a new run here: player 2's table made again, their plane kept (still DOWN: hidden, off the radar)")
    peerState[1] = FRESH; tick()
    check(rflm.hidden == false and rflm.bIsActivated == true, "(0.73.83) up again after the new run: shown, on the radar (kept by its address)")
    D = Dkeep; tick()
    -- a plane the game had deactivated itself stays so
    rflm.bIsActivated = false
    peerState[1] = DOWNST; tick()
    peerState[1] = FRESH; tick()
    check(rflm.hidden == false and rflm.bIsActivated == false, "(0.73.83) a plane that was deactivated before it was hidden: left so when shown")
    rflm.bIsActivated = true
    -- radar_off = false: the flag left alone
    CFG.coop.rejoin.radar_off = false
    peerState[1] = DOWNST; tick()
    check(rflm.hidden == true and rflm.bIsActivated == true, "(0.73.83) [coop.rejoin] radar_off = false: hidden, the flag left alone")
    peerState[1] = FRESH; tick()
    CFG.coop.rejoin.radar_off = true
    check(rflm.hidden == false and rflm.bIsActivated == true, "... shown again")
end
-- back with no airframe heard yet: the old plane stays hidden, then replaced
inbox[#inbox + 1] = "1|sys|left"; peerState[1] = ""; tick()
from, n0 = #logs + 1, #seq
inbox[#inbox + 1] = "1|sys|joined"; inbox[#inbox + 1] = hi(1, "", "", "", ""); peerState[1] = FRESH
tick(); tick(2)
check(rflm.hidden == true and M.peers[1].obj == rflm and line("coop: player 2's plane shown", from) == nil and not has(seqSince(n0), "spawnPP"),
      "back, no airframe heard yet: their old plane stays hidden (not shown with their new stream)")
inbox[#inbox + 1] = hi(1, "su57_common", "su57", LO3, "SU-57")
tick()
local su57 = native[1]
check(su57 and has(su57.full, "su57") and M.peers[1].obj == su57 and native[22] == rflm and not rflm.gone
      and line("coop: player 2 rejoined in su57 (was rflm)", from) ~= nil,
      "their airframe comes: the Rafale M set aside in slot 23, their Su-57 spawned")
-- back with no airframe for wait_s: kept
inbox[#inbox + 1] = "1|sys|left"; peerState[1] = ""; tick()
from, n0 = #logs + 1, #seq
inbox[#inbox + 1] = "1|sys|joined"; inbox[#inbox + 1] = hi(1, "", "", "", ""); peerState[1] = FRESH
tick(); tick(9)
check(su57.hidden == true, "9 s on: still hidden")
tick(1.5)
check(su57.hidden == false and line("coop: player 2 is back, no airframe heard from them in 10 s: their plane here kept", from) ~= nil
      and not has(seqSince(n0), "spawnPP"), "none in 10 s: their plane kept and shown")
-- the same weapons on a new airframe? the same airframe with new weapons after a rejoin: replaced
inbox[#inbox + 1] = "1|sys|left"; peerState[1] = ""; tick()
from = #logs + 1
inbox[#inbox + 1] = "1|sys|joined"; inbox[#inbox + 1] = hi(1, "su57_common", "su57", LO1, "SU-57"); peerState[1] = FRESH
tick()
check(native[1] ~= su57 and has(native[1].full, "su57") and not su57.gone and line("coop: player 2 rejoined in su57 with other weapons (was su57)", from) ~= nil,
      "back in the same airframe with other weapons: a new one with them (the old kept aside)")
local su57b = native[1]
-- a newcomer in slot 24, where the Su-47 is kept: moved on before their plane spawns
from, n0 = #logs + 1, #seq
inbox[#inbox + 1] = "23|sys|joined"
inbox[#inbox + 1] = string.format("23|hi|%s|0.32.21|f15c_common|New|f15c|||F-15C", VERSION)
peerState[23] = FRESH
tick()
order = seqSince(n0)
local moved = order:match("swap 23<>(%d+)")
local sw, sp = order:find("swap 23<>", 1, true), order:find("spawnPP 23 PP0004_f15c", 1, true)
check(sw and sp and sw < sp and not su47.gone and moved and native[tonumber(moved)] == su47,
      "a newcomer in slot 24: the Su-47 kept there moved to slot " .. tostring(moved and tonumber(moved) + 1) .. " first, then their F-15C (" .. order .. ")")
check(line("coop: a set-aside plane kept in slot 24 moved to slot", from) ~= nil, "said so")
check(not rflm.gone and not su57.gone and not su47.gone, "nothing set aside was ever destroyed")
-- a game started over: marked, the joiners told
local s0 = #sent
inbox[#inbox + 1] = "1|sys|restart"
tick()
check(M.left[1] ~= nil and M.left[1].why == "started their game over" and sentOf("rj", s0 + 1)[1] == "-1>rj|1",
      "their game started over: marked, every joiner told (rj|1)")
M.left[1] = nil
-- rejoin off: kept
CFG.coop.rejoin.enabled = false
inbox[#inbox + 1] = "1|sys|left"; peerState[1] = ""; tick()
check(M.left[1] == nil, "[coop.rejoin] enabled = false: nothing marked (their plane kept, as before)")
CFG.coop.rejoin.enabled = true
peerState[23] = ""

---------------------------------------------------------------------------------------------------- C: a joiner
print("C: a rejoin seen by a joiner")
COOP.reopen("join", "test")
COOP.slot, M.state = 2, "linked"
M.peers, M.left, M.parkAt, M.aside = {}, {}, {}, {}
native = {}
inbox[#inbox + 1] = string.format("0|pi|1|su47_common|%s|Lil|su47|%s||SU-47|", VERSION, LO1)
peerState[1] = FRESH
tick(); tick(1)
local jsu47 = native[1]
check(jsu47 and has(jsu47.full, "su47") and M.peers[1].obj == jsu47, "a joiner: player 2's real Su-47 here")
inbox[#inbox + 1] = "0|po|1"; peerState[1] = ""
tick()
check(M.left[1] ~= nil, "the host's po: marked")
from, n0 = #logs + 1, #seq
inbox[#inbox + 1] = string.format("0|pi|1|rflm_common|%s|Lil|rflm|%s||RAFALE M|", VERSION, LO2)
peerState[1] = FRESH
tick()
check(native[1] and has(native[1].full, "rflm") and not jsu47.gone and jsu47.hidden == true
      and line("coop: player 2 rejoined in rflm (was su47): old plane set aside, new one spawned", from) ~= nil,
      "the host's pi with their Rafale M: the Su-47 set aside here too, their Rafale M spawned (" .. seqSince(n0) .. ")")
peerState[1] = ""                                 -- (not back in the mission yet: the mark waits)
inbox[#inbox + 1] = "0|rj|1"
tick()
check(M.left[1] ~= nil and M.left[1].why == "started their game over", "the host's rj: marked")
inbox[#inbox + 1] = "0|rj|99"
tick()
check(M.left[98] == nil, "a slot that can't be: ignored")
M.left[1] = nil
peerState[1] = ""

---------------------------------------------------------------------------------------------------- C4: AI stand-ins
print("C4: AI stand-ins (real planes off)")
COOP.reopen("host", "test")
M.peers, M.left, M.parkAt, M.aside, M.standUnit, M.unitSlot, M.asideUnit = {}, {}, {}, {}, {}, {}, {}
native = {}
CFG.coop.real_planes = false
inbox[#inbox + 1] = "1|sys|joined"
inbox[#inbox + 1] = hi(1, "su47_common", "su47", LO1, "SU-47")
peerState[1] = FRESH
n0 = #seq
tick()
check(has(seqSince(n0), "spawn SV_Unit_CoopPeerB"), "player 2's stand-in on their own unit, B (" .. seqSince(n0) .. ")")
local sb = plane("BP_OP0001_su47_C_1")
logPlane(sb, "SV_Unit_CoopPeerB")
check(M.peers[1].obj == sb, "... up as player 2's plane")
inbox[#inbox + 1] = "1|sys|left"; peerState[1] = ""; tick()
clock = clock + 18
from, n0 = #logs + 1, #seq
inbox[#inbox + 1] = "1|sys|joined"; inbox[#inbox + 1] = hi(1, "rflm_common", "rflm", LO2, "RAFALE M"); peerState[1] = FRESH
tick()
order = seqSince(n0)
check(sb.hidden == true and sb.coll == false and sb.tick == false and not sb.destroyed and M.asideUnit.SV_Unit_CoopPeerB == true,
      "the Su-47 stand-in set aside: hidden, collision and tick off, its unit B never flown again")
check(sb.bIsActivated == false and sb.X == 100000000, "(0.73.83) ... off the radar (deactivated) and 1000 km off the map")
check(has(order, "peer 1=0") and has(order, "spawn SV_Unit_CoopPeerA") and not has(order, "spawn SV_Unit_CoopPeerB"),
      "the new one on a free unit: this game's own slot's, A (" .. order .. ")")
check(line("coop: player 2 rejoined in rflm_common (was su47_common): old plane set aside, new one spawned (an AI stand-in, SV_Unit_CoopPeerA)", from) ~= nil,
      "the plan's line, for a stand-in (" .. tostring(line("rejoined", from)) .. ")")
local sa = plane("BP_OP0014_rflm_C_1")
logPlane(sa, "SV_Unit_CoopPeerA")
check(M.peers[1].obj == sa and M.peers[0] == nil, "unit A's plane up as player 2's (not the host's own slot)")
tick()
check(names.SV_CoopName_A == "LIL", "player 2's name on unit A's box (" .. tostring(names.SV_CoopName_A) .. ")")
-- a player in slot 1 (unit A's own): another free unit for them, never A
from, n0 = #logs + 1, #seq
COOP.slot = 0
CFG.coop.real_planes = true
peerState[1] = ""

---------------------------------------------------------------------------------------------------- D1-D2: VALKA, the host
print("D: VALKA's mood on every joiner (the host)")
CFG.coop.real_planes = true
SPC = { V = {} }
do                                                -- (sv_anomalies.lua's own mood functions)
    local an = PARTS.read("sv_anomalies.lua")
    local a1 = an:find("function SPC.V.mood(c, s)", 1, true)
    local tail = "\n    s.moodOn = false\nend\n"
    local a2 = a1 and an:find(tail, a1, true)
    assert(a1 and a2, "sv_anomalies.lua: SPC.V.mood / moodOff not found")
    assert(load(an:sub(a1, a2 + #tail - 1), "=sv_anomalies mood"))()
end
local reds, songs = {}, {}
function hudRed(on) reds[#reds + 1] = on and "on" or "off" end
SND = { songStart = function() songs[#songs + 1] = "start" end, songFade = function() songs[#songs + 1] = "fade" end,
        songStop = function() songs[#songs + 1] = "stop" end }
local vc = CFG.specials.valka
-- her round (the lurk after her decoys, or no decoys: SPC.V.mood)
D.special = { kind = "valka", state = "lurk" }
local s1 = #sent
from = #logs + 1
SPC.V.mood(vc, D.special)
check(sentOf("vm", s1 + 1)[1] == "-1>vm|1" and line("coop: VALKA's mood on (the red sky, her song): sent to every joiner (1 linked)", from) ~= nil,
      "SPC.V.mood: every joiner told at once, logged")
check(reds[#reds] == "on" and songs[#songs] == "start", "... and this game's sky and song")
tick()
check(#sentOf("vm", s1 + 1) == 1, "the watch sends it no second time")
D.special.state, D.special.revealedAt = "hunt", clock
tick()
check(sentOf("vr", s1 + 1)[1] == "-1>vr|" .. vc.unit, "her reveal (revealedAt) sent by the watch: vr|" .. vc.unit)
-- a joiner who asks for the whole picture while she's up
local s2 = #sent
inbox[#inbox + 1] = "1|jn"
tick()
check(sentOf("vm", s2 + 1)[1] == "1>vm|1" and sentOf("vr", s2 + 1)[1] == "1>vr|" .. vc.unit, "a joiner's jn while she's up: vm|1 and vr in its picture")
-- her end
local s3 = #sent
from = #logs + 1
D.special.state = "done"
SPC.V.moodOff(vc, D.special, clock)
check(sentOf("vm", s3 + 1)[1] == "-1>vm|0" and line("coop: VALKA's mood off: sent to every joiner", from) ~= nil and songs[#songs] == "fade",
      "her death: vm|0 to every joiner, logged; her song fading here")
tick()
check(#sentOf("vm", s3 + 1) == 1, "... once")
-- an error in this game's sky never keeps the joiners from it
local rawRed = hudRed
hudRed = function() error("no sky") end
D.special = { kind = "valka", state = "lurk" }
local s4 = #sent
SPC.V.mood(vc, D.special)
hudRed = rawRed
check(sentOf("vm", s4 + 1)[1] == "-1>vm|1" and D.special.moodOn == true, "this game's sky erring: the joiners told all the same")
-- the run over with her up (D gone)
local s5 = #sent
local Dk = D
D = nil
tick()
check(sentOf("vm", s5 + 1)[1] == "-1>vm|0", "the run over with her up: vm|0 (the watch)")
D = Dk
-- a mood on by any other way (moodOn set, nothing said): the watch says it
D.special = { kind = "valka", state = "hunt", moodOn = true }
local s6 = #sent
tick()
check(sentOf("vm", s6 + 1)[1] == "-1>vm|1", "her mood on another way (a start that never called SPC.V.mood): the watch sends vm|1")
-- her round gone with her mood on (replaced without her end): faded here and everywhere
local s7 = #sent
from = #logs + 1
D.special = { kind = "ladon", state = "hunt" }
tick()
check(sentOf("vm", s7 + 1)[1] == "-1>vm|0" and line("coop: VALKA's round went with her mood still on", from) ~= nil and songs[#songs] == "fade",
      "her round replaced with her mood on: faded here, vm|0 to every joiner")
-- her round over with her mood still on (she couldn't spawn after her lurk turned it on: "done", no moodOff)
D.special = { kind = "valka", state = "lurk", moodOn = true }
tick()
local s10 = #sent
from = #logs + 1
D.special.state = "done"
songs = {}
tick()
check(sentOf("vm", s10 + 1)[1] == "-1>vm|0" and #sentOf("vm", s10 + 1) == 1 and line("coop: VALKA's round is over with her mood still on", from) ~= nil
      and songs[1] == "fade" and D.special.moodOn == false, "her round over with her mood on (no moodOff): faded here, vm|0 once")
D.special = nil
tick()

---------------------------------------------------------------------------------------------------- D2: VALKA, a joiner
print("D: VALKA's mood on a joiner")
COOP.reopen("join", "test")
COOP.slot, M.state = 2, "linked"
M.vmood = nil
reds, songs = {}, {}
local Dj = D
D = nil
from = #logs + 1
inbox[#inbox + 1] = "0|vm|1"
tick()
check(line("coop: the host's VALKA mood on: not here (no run here yet: it comes again with the host's picture)", from) ~= nil and #reds == 0,
      "vm|1 with no run here: said so, nothing turned red")
D = Dj
M.lastD = D
from = #logs + 1
inbox[#inbox + 1] = "0|vm|1"
tick()
check(reds[#reds] == "on" and songs[#songs] == "start" and M.vmHere == true
      and line("coop: the host's VALKA mood on: the sky red and her song here too", from) ~= nil, "vm|1: the sky red, her song, logged")
inbox[#inbox + 1] = "0|vm|1"
tick()
check(line("(again: the host's picture)", from) ~= nil, "again (the host's picture): said so")
inbox[#inbox + 1] = "0|vm|0"
tick()
check(reds[#reds] == "off" and songs[#songs] == "fade" and not M.vmHere and line("coop: the host's VALKA mood off: the sky and her song fading", from) ~= nil,
      "vm|0: the sky back, her song fading")
inbox[#inbox + 1] = "0|vm|1"; tick()
from = #logs + 1
inbox[#inbox + 1] = "0|rs|n"
tick()
check(not M.vmHere and reds[#reds] == "off" and line("coop: VALKA's mood off here (the host's run started over)", from) ~= nil,
      "the host's new run with her up here: off here")
D = { round = 1, state = "wait", now = 100, startRound = 1, up = {}, flown = {} }
M.lastD = D
inbox[#inbox + 1] = "0|vm|1"; tick()
from = #logs + 1
D = { round = 1, state = "wait", now = 100, startRound = 1, up = {}, flown = {} }
tick()
check(not M.vmHere and line("coop: VALKA's mood off here (a new run here)", from) ~= nil, "a new run here with her up: off here")
inbox[#inbox + 1] = "0|vm|1"; tick()
from = #logs + 1
COOP.reopen("host", "test")
local s8 = #sent
tick()
check(not M.vmHere and line("coop: VALKA's mood off here (this game is the host now)", from) ~= nil and #sentOf("vm", s8 + 1) == 0,
      "this game becomes the host with the old host's mood on: off here, nothing sent")

---------------------------------------------------------------------------------------------------- D3: special-round music
print("D3: a joiner's special-round music is the host's")
COOP.reopen("join", "test")
COOP.slot, M.state = 2, "linked"
RUN.specialPick = {}
from = #logs + 1
inbox[#inbox + 1] = "0|rnd|7|fighting|0.0|1|1|5||||anomaly"
tick()
check(M.rnd and M.rnd.special == "anomaly" and specialFor(7) == "anomaly", "the host's round 7 is its Anomaly: specialFor(7) here too")
check(line("coop: round 7 is its anomaly special on the host: a special round's music here", from) ~= nil, "said so, once a round")
check(specialFor(8) == nil and RUN.specialPick[7] == nil and RUN.specialPick[8] == nil, "no dice rolled here (RUN.specialPick untouched)")
inbox[#inbox + 1] = "0|rnd|8|wait|5.0|0|0|0||||"
tick()
check(specialFor(8) == nil and line("coop: round 8 is a normal round on the host: a normal round's music here", from) ~= nil,
      "a normal round there: a normal round's music here")
inbox[#inbox + 1] = "0|rnd|9|fighting|0.0|1|1|5||||Drop Table"
tick()
check(specialFor(9) == nil, "a field that isn't a word: none")
-- the host's field: from its pick, never a round not picked yet
COOP.reopen("host", "test")
D.round = 12
CFG.specials.enabled, CFG.specials.random = true, true
RUN.specialPick = { [12] = "ladon" }
local s9 = #sent
M.nextRnd = 0
tick()
local function field11(m)                         -- ("<to>>rnd|f2|...": f[1] "rnd")
    local f = {}
    for x in ((m or ""):gsub("^%-?%d+>", "") .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
    return f[11]
end
local r1 = sentOf("rnd", s9 + 1)[1]
check(field11(r1) == "ladon", "the host's rnd: field 11 its round's special (" .. tostring(r1) .. ")")
D.round = 13
RUN.specialPick = {}
s9 = #sent
M.nextRnd = 0
tick()
r1 = sentOf("rnd", s9 + 1)[1]
check(field11(r1) == "" and RUN.specialPick[13] == nil, "a round not picked yet: an empty field, its dice not rolled (" .. tostring(r1) .. ")")

---------------------------------------------------------------------------------------------------- 0.73.80: real_fallback
print("0.73.80: a plane with no blueprint here as its [coop.real_fallback]; what the others see you as")
-- (the 31-round test, finding coop7: Alyssa's modded Falken flew as an AI F-16C on every joiner, a blue ally box, none
-- of her launches replayed)
do
    local FALKEN_BP = CFG.coop.real_paths.falken
    notInstalled[FALKEN_BP] = true                        -- (this game hasn't the Falken add-on: its fallback)
    local fromF, n0f = #logs + 1, #seq
    inbox[#inbox + 1] = "5|sys|joined"
    inbox[#inbox + 1] = hi(5, "f16c_common", "falken", LO1, "FALKEN")
    peerState[5] = FRESH
    tick(); tick(1)
    local fk = native[5]
    check(fk and has(fk.full, "PP0038_adfx02_L001") and M.peers[5].obj == fk and M.peers[5].real and M.peers[5].code == "falken"
          and M.peers[5].fallback == "adfx02" and not has(seqSince(n0f), "spawn SV_Unit_CoopPeer"),
          "a Falken (no blueprint here): a real ADFX-02 player plane in its slot, not an AI stand-in (" .. tostring(fk and fk.full) .. ")")
    check(spawnArgs[5] and spawnArgs[5].lo == "" and spawnArgs[5].pt == "", "... with its own default weapons and paint (theirs are another airframe's)")
    check(line("coop: player 6's plane is their falken shown as a real adfx02 (a player plane", fromF) ~= nil, "... logged")
    check(line("coop: player 6's falken: its own blueprint isn't installed here (" .. FALKEN_BP .. "): [coop.real_fallback] instead", fromF) ~= nil
          and M.modMiss[FALKEN_BP] == true, "(0.73.80) its own blueprint tried first, not installed: logged, not asked again")
    -- ((0.73.80, changed: was the AI stand-in) a code with no fallback: [coop] real_default's stock plane, a real F-16C
    -- with its own weapons and paint; real_default "": the AI stand-in, as before
    n0f = #seq
    inbox[#inbox + 1] = "6|sys|joined"
    inbox[#inbox + 1] = hi(6, "f16c_common", "mystery", LO1, "MYSTERY")
    peerState[6] = FRESH
    tick(); tick(1)
    local my = native[6]
    check(my and has(my.full, "PP0022_f16c") and M.peers[6].obj == my and M.peers[6].real and M.peers[6].fallback == "f16c"
          and spawnArgs[6].lo == "" and spawnArgs[6].pt == "" and not has(seqSince(n0f), "spawn SV_Unit_CoopPeer")
          and has(line("coop: player 7's plane is their mystery shown as a real f16c (a player plane", fromF), "here: [coop] real_default)"),
          "(0.73.80) a code with no fallback: a real F-16C ([coop] real_default), its own weapons and paint (" .. seqSince(n0f) .. ")")
    CFG.coop.real_default = ""
    n0f = #seq
    inbox[#inbox + 1] = "8|sys|joined"
    inbox[#inbox + 1] = hi(8, "f16c_common", "mystery", LO1, "MYSTERY")
    peerState[8] = FRESH
    tick(); tick(1)
    check(native[8] == nil and line("coop: player 9's real plane (mystery) not spawned: no player plane blueprint for mystery "
          .. "(no base from their game, no [coop.real_fallback] for it, [coop] real_default off); their AI stand-in instead", fromF) ~= nil
          and has(seqSince(n0f), "spawn SV_Unit_CoopPeerI"),
          "real_default off: a code with no fallback is the AI stand-in (" .. seqSince(n0f) .. ")")
    CFG.coop.real_default = "f16c"
    -- the setting off for it: the stand-in too; a fallback that's no player plane: ignored
    CFG.coop.real_fallback.falken = "nope"
    check(M.realFallback("falken") == nil and M.realFallback("FALKEN") == nil, "a fallback with no blueprint: none")
    CFG.coop.real_fallback.falken = "adfx02"
    check(M.realFallback("FALKEN") == "adfx02" and M.realFallback("f16c") == nil, "the code any case; a stock code has none")
    inbox[#inbox + 1] = "5|sys|left"; inbox[#inbox + 1] = "6|sys|left"; inbox[#inbox + 1] = "8|sys|left"
    peerState[5], peerState[6], peerState[8] = "", "", ""
    tick()
    -- your own plane: "OTHERS SEE YOUR <X> AS <Y>" once a level when it isn't your own airframe on their games
    local was = pawn.full
    local c0 = #callouts
    tick()
    check(#callouts == c0, "your stock F-16C: nothing to say")
    pawn.full = "BP_PlayerPlane_PP9001_falken_L001_C_0"
    tick(); tick()
    -- ((0.73.80, changed: the callout's wording) what players without the add-on see, its stock base (here this game's
    -- [coop.real_fallback]: the pawn has no class to read)
    check(#callouts == c0 + 1 and callouts[#callouts] == "OTHERS SEE YOUR FALKEN (ADFX02 WITHOUT THE ADD-ON) / nil"
          and line("coop: the other players see your FALKEN (falken) as itself where its add-on is installed, else a real adfx02 "
          .. "(its stock base)", fromF) ~= nil,
          "your Falken: OTHERS SEE YOUR FALKEN (ADFX02 WITHOUT THE ADD-ON), once, logged (" .. tostring(callouts[#callouts]) .. ")")
    pawn.full = "BP_PlayerPlane_PP9002_mystery_C_0"
    tick()
    -- ((0.73.80, changed: was "AS F16C (AI)") a plane with no fallback: [coop] real_default's real F-16C
    check(callouts[#callouts] == "OTHERS SEE YOUR MYSTERY AS F16C / nil"
          and line("coop: the other players see your MYSTERY (mystery) as a real f16c ([coop] real_default)", fromF) ~= nil,
          "a plane with no fallback: OTHERS SEE YOUR MYSTERY AS F16C ([coop] real_default) (" .. tostring(callouts[#callouts]) .. ")")
    CFG.coop.real_default = ""
    check(M.seenAs("mystery") == "F16C (AI)", "... real_default off: AS F16C (AI), as before")
    CFG.coop.real_default = "f16c"
    local c1 = #callouts
    tick()
    check(#callouts == c1, "... once a level")
    CFG.coop.real_planes = false
    pawn.full = "BP_PlayerPlane_PP0038_adfx02_L001_C_0"
    tick()
    check(callouts[#callouts] == "OTHERS SEE YOUR ADFX02 AS F16C (AI) / nil", "real planes off: an ADFX-02 (no AI row) seen as the default's F-16C")
    CFG.coop.real_planes = true
    pawn.full = was
    tick()
end

---------------------------------------------------------------------------------------------------- 0.73.80: real_paths
print("0.73.80: a modded plane's own blueprint, where its add-on is installed here ([coop.real_paths])")
do
    local FALKEN_BP = CFG.coop.real_paths.falken
    notInstalled[FALKEN_BP], M.modMiss = nil, {}          -- (this game has the Falken add-on)
    local fromK, n0k = #logs + 1, #seq
    inbox[#inbox + 1] = "7|sys|joined"
    inbox[#inbox + 1] = hi(7, "f16c_common", "falken", LO1, "FALKEN")
    peerState[7] = FRESH
    tick(); tick(1)
    local fk = native[7]
    check(fk and has(fk.full, "PP9001_falken_L001") and M.peers[7].obj == fk and M.peers[7].real and M.peers[7].code == "falken"
          and M.peers[7].fallback == nil and not has(seqSince(n0k), "spawn SV_Unit_CoopPeer"),
          "a Falken with its add-on installed here: its own real plane, no fallback (" .. tostring(fk and fk.full) .. ")")
    check(spawnArgs[7] and spawnArgs[7].lo == LO1, "... with their loadout (their own airframe's)")
    check(line("coop: player 8's falken: its own blueprint is installed here (" .. FALKEN_BP .. "): the real thing", fromK) ~= nil
          and line("coop: player 8's plane is their real falken (a player plane", fromK) ~= nil, "... logged")
    -- a path that isn't /Game/: never loaded
    CFG.coop.real_paths.mystery = "C:/evil.uasset"
    check(M.modClassPath("mystery") == nil and M.modClassPath("FALKEN") == FALKEN_BP, "only /Game/ paths; the code any case")
    CFG.coop.real_paths.mystery = nil
    inbox[#inbox + 1] = "7|sys|left"
    peerState[7] = ""
    tick()
end

---------------------------------------------------------------------------------------------------- 0.73.83: its review
print("0.73.83: the radar's records, their review (a reused address, the game putting a plane back on, the level going)")
do
    -- a set-aside plane whose address is another object's now (freed, the address come round again): never touched, dropped
    local px = plane("BP_OP0001_f16c_C_77")
    check(M.setAside(23, { obj = px, real = false, unit = "SV_Unit_CoopPeerX" }, "test") == true and px.bIsActivated == false
          and M.asideUnit.SV_Unit_CoopPeerX == true, "a test plane set aside (deactivated, its unit kept off)")
    local n = #M.aside
    px.full = "BP_PlayerPlane_PP0022_f16c_C_9"                  -- (another object at its address now)
    px.bIsActivated, px.X, px.Y, px.Z = true, 1234, 5678, 9000
    tick(5.1)
    check(px.bIsActivated == true and px.X == 1234 and px.Z == 9000 and #M.aside == n - 1 and not M.asideUnit.SV_Unit_CoopPeerX,
          "its address another object's now: never deactivated or moved, dropped (its unit free again)")
    -- the radar's record: off again when the game put a hidden plane back on, its first state kept
    local py = plane("BP_OP0001_f16c_C_78")
    local P = { obj = py }
    check(M.radarOff(P) == "off the radar (deactivated)" and py.bIsActivated == false, "a plane hidden: off the radar")
    check(M.radarOff(P) == "off the radar already" and py.bIsActivated == false, "hidden again: off already")
    py.bIsActivated = true
    check(M.radarOff(P) == "off the radar again (the game had put it back on)" and py.bIsActivated == false,
          "the game put it back on, hidden again: off again")
    check(M.radarOn(P) == "on the radar again (activated)" and py.bIsActivated == true, "... its first state kept: on again when shown")
    -- a record whose address is another object's now: dropped, the new one taken off from its own state
    local pz = plane("BP_OP0001_f16c_C_79")
    local Q = { obj = pz }
    M.radarOff(Q)
    pz.full, pz.bIsActivated = "BP_OP0003_mig29_C_5", true
    check(M.radarOff(Q) == "off the radar (deactivated)" and pz.bIsActivated == false, "a record for another object at that address: dropped, a fresh one")
    -- the level going: the set-aside planes and the records forgotten, none touched
    local pw = plane("BP_OP0001_f16c_C_80")
    M.setAside(22, { obj = pw, real = false, unit = "SV_Unit_CoopPeerW" }, "test")
    pw.bIsActivated = true
    COOP.levelDrop("a test")
    check(#M.aside == 0 and next(M.radarSt) == nil and next(M.parkAt) == nil and not M.asideUnit.SV_Unit_CoopPeerW
          and pw.bIsActivated == true and line("set aside forgotten here, none touched") ~= nil,
          "the level going: the set-aside planes and the radar's records forgotten, none touched")
end

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
do
    local an = PARTS.read("sv_anomalies.lua")
    check(has(an, "V.mood(c, s)                                    -- (0.73.76) the flyers down (or none): red and her song")
          and has(an, "V.mood(c, s)                                        -- (0.73.76) red and her song, if her round had no lurk")
          and has(an, "V.moodOff(c, s, now)                            -- (0.73.76) the red and her song fade away after she dies"),
          "sv_anomalies: her lurk and hunt call SPC.V.mood, her death SPC.V.moodOff")
    local cs = PARTS.read("sv_coop.lua")
    check(has(cs, "local okVw, errVw = pcall(M.valkaWatch)"), "sv_coop: the host's watch every co-op tick")
    check(has(cs, "if M.vmood then sendTo(to, true, \"vm\", 1) end"), "sv_coop: hostSync resends her mood")
    check(has(cs, "local okF, whyF = M.nativeFree(slot)"), "sv_coop: spawnReal frees the slot first")
    check(has(readAll(MOD .. "/Scripts/sv_flights.lua"), "musicNext(specialFor(D.round) ~= nil)"), "sv_flights: the music asks specialFor")
end

do
    local errs = {}
    for _, l in ipairs(logs) do
        if l:find("player plane error", 1, true) or l:find("mood watch error", 1, true) or l:find("message error", 1, true) then errs[#errs + 1] = l end
    end
    check(#errs == 0, "no error in the parts touched (" .. tostring(errs[1]) .. ")")
end

print(fails == 0 and "co-op rejoin test: all passed" or ("co-op rejoin test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
