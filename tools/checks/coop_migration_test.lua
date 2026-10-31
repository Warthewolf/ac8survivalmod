-- coop_migration_test.lua <mod dir> <work dir> (run by tools/checks/coop_migration_test.sh): host migration (the user,
-- 2026-10-31: "if the Host does leave, it automatically tries to find the next best host"), on the real sv_config.lua and
-- sv_coop.lua (M exposed), the game and the runtime stubbed:
--   the host: the line of succession ranked by link (round trip, share resent; best first) with each Steam ID ("sq"),
--     the allies and defences up ("al"), each player's Steam ID in "pi", "hl" before a reload;
--   the first in line: the host silent after_s, it opens as host looking for everyone's Steam ID, the copies down, the
--     old host's plane set aside, the round in play again after break_s (between rounds: the next), held while the
--     others aren't back (joinWaiting), the allies and defences built again (shopBuildFor), a plane moved with its
--     player to their new slot (SV_CoopSwapPP), a slot that's another player's has the old plane set aside; nobody back
--     and another host heard: it joins it again;
--   the others: they join the first in line, the next after link_s, the old host again when nobody answers; the host's
--     "hl" makes them wait that long; linked, it's over.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
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
VERSION = "0.73.30-migration.test"
SCRIPT_DIR = WORK .. "/Scripts/"
KILL, LB = { side = function() end }, { send = function() end }
RUN = { credits = 1000, spent = 0, msg = {}, bought = {} }
function roundsTick() end
function airfieldTick() end
function bombTick() end
function logPlane() end
function hudCallout(t, sub) callouts[#callouts + 1] = tostring(t) .. " / " .. tostring(sub) end
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
function NotifyOnNewObject() end
SV_ERR = {}
local SID = { host = "76561198000000000", a = "76561198000000001", b = "76561198000000002", c = "76561198000000003" }
local sent, inbox, opens, swaps, built, peerBinds = {}, {}, {}, {}, {}, {}
local info = { state = "linked", me = SID.host, role = "host" }
local peerIds = ""
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = (to or -1) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;mode=steam;role=" .. info.role .. ";state=" .. info.state .. ";slot=0;players=2;max=24;me=" .. info.me .. ";cands=0;tele=1;peers=" end
function SV_CoopOpen(mode, role, partner) opens[#opens + 1] = { role = role, partner = partner }; info.role = role; return 1 end
function SV_CoopClose() end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer(s, a) peerBinds[#peerBinds + 1] = s .. "=" .. tostring(a); return 1 end
function SV_CoopPeerIds() return peerIds end
function SV_CoopSwapPP(a, b) swaps[#swaps + 1] = a .. "<>" .. b; return 1 end
function SV_CoopPeerAt() return "0,0,300000,0,0,0,1000,100,3,100" end   -- (in the mission, alive, fresh)
function SV_MenuSetting() return "" end
local menu = 0
function SV_MenuChoice() return menu end
function SV_Event() return 1 end
function SV_UnitAlive() return 0 end
function SV_Spawn() return 1 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function shopBuildFor(slot, name, price, kind) built[#built + 1] = { slot = slot, name = name, price = price, kind = kind }; return true, name .. " BUILT" end
SETUP = { startRound = function() return 1 end }

dofile(MOD .. "/Scripts/sv_config.lua")
local src = readAll(MOD .. "/Scripts/sv_coop.lua"):gsub("\nlocal M = {", "\nM = {", 1)
assert(load(src, "=sv_coop.lua"))()
local M = _G.M
CFG.coop.enabled = true
local function tick(dt) clock = clock + (dt or 0.25); M.nextInfo = 0; COOP.tick(0) end
local function line(part, from) for i = #logs, from or 1, -1 do if has(logs[i], part) then return logs[i] end end end
local function sentOf(kind, from) local t = {}; for i = from or 1, #sent do if sent[i]:match("^%-?%d+>" .. kind .. "|") then t[#t + 1] = sent[i] end end; return t end
local function obj(name) return { name = name, addr = math.random(1, 1e9), SetActorHiddenInGame = function(self, v) self.hidden = v end,
                                  SetActorEnableCollision = function(self, v) self.coll = v end } end

---------------------------------------------------------------------------------------------------- the host
print("the host: the line of succession and the allies")
menu = 16 + 3; tick()
check(COOP.host(), "hosting")
D = { round = 5, state = "fighting", now = 100, startRound = 1 }
tick()
for s, sid in pairs({ [1] = SID.a, [2] = SID.b, [3] = SID.c }) do M.roster[s] = { name = "P" .. s, row = "f16c_common", ver = VERSION } end
-- slot 1: 300 ms, 1 % resent; slot 2: 120 ms, 0.5 %; slot 3: 100 ms but 30 % resent
peerIds = "1:" .. SID.a .. ":300:1000:10:1,2:" .. SID.b .. ":120:1000:5:1,3:" .. SID.c .. ":100:1000:300:1"
ALLY = { run = { up = { SV_Unit_MoonchildA = { kind = "air", ally = "wingmen", buyer = 2 }, SV_Unit_ShipAegisA = { kind = "ship", key = "Aegis" },
                        SV_Unit_VoidWatcher = { kind = "air", ally = "awacs" } },
                 defCount = { aa = 1, sam = 0, ciws = 2 } }, unit = {} }
local s0 = #sent
M.sqAt = 0
tick()
local sq = sentOf("sq", s0 + 1)[1]
check(sq and sq:find("sq|" .. SID.host .. "|2:" .. SID.b .. ",1:" .. SID.a .. ",3:" .. SID.c, 1, true) ~= nil,
      "the line, best link first: player 3 (120 ms), player 2 (300 ms), player 4 (30 % resent) (" .. tostring(sq) .. ")")
local al = sentOf("al", s0 + 1)[1]
check(al and has(al, "al|AAGun:0,Ciws:0,Ciws:0,ShipAegis:0,VoidWatcher:0,Wingmen:" .. SID.b), "the allies and defences up, VOID WATCHER 1 too, the buyer's Steam ID (" .. tostring(al) .. ")")
check(M.roster[2].sid == SID.b and M.roster[0] and M.roster[0].sid == SID.host, "each roster entry with its Steam ID, yours too")
local s1 = #sent
M.sqAt = 0
tick()
check(#sentOf("sq", s1 + 1) == 0 and #sentOf("al", s1 + 1) == 0, "not again while nothing changed (30 s)")
inbox[#inbox + 1] = "2|hi|" .. VERSION .. "|0.32.7|su35_common|Bee|su35||||SU35"
tick()
local pi2 = nil
for _, m in ipairs(sentOf("pi")) do if m:find("pi|2|", 1, true) then pi2 = m end end
check(pi2 and pi2:find("|" .. SID.b .. "$") ~= nil, "pi carries their Steam ID last (" .. tostring(pi2) .. ")")
local s2 = #sent
COOP.hostAway(120)
check(sentOf("hl", s2 + 1)[1] and has(sentOf("hl", s2 + 1)[1], "hl|120"), "before a reload: hl|120")
check(has(readAll(MOD .. "/Scripts/sv_down.lua"), "pcall(COOP.hostAway, 120)"), "sv_down's run over says it before its level reloads")
ALLY = nil

---------------------------------------------------------------------------------------------------- the first in line
print("the first in line takes over")
local function asJoiner(me, slot)
    COOP.reopen("join", "test")
    COOP.slot, M.state, info.state, info.me, M.mySidV = slot, "linked", "linked", me, nil
    M.mig, M.migratedFrom, M.hostLostAt, M.hostAwayUntil, M.succ = nil, nil, nil, nil, nil
    M.roster = { [0] = { name = "Host", sid = SID.host }, [1] = { name = "Ann", sid = SID.a }, [2] = { name = "Bee", sid = SID.b },
                 [3] = { name = "Cid", sid = SID.c } }
    M.peers = {}
    for s, sid in pairs({ [0] = SID.host, [1] = SID.a, [2] = SID.b, [3] = SID.c }) do
        if s ~= slot then M.peers[s] = { obj = obj("plane" .. s), sid = sid, real = true, shown = true } end
    end
    inbox[#inbox + 1] = "0|sq|" .. SID.host .. "|2:" .. SID.b .. ",1:" .. SID.a .. ",3:" .. SID.c
    inbox[#inbox + 1] = "0|al|AAGun:0,Wingmen:" .. SID.c
    D = { round = 5, state = "fighting", now = 500, startRound = 1 }
    tick()
end
asJoiner(SID.b, 2)
check(M.succ and #M.succ == 3 and M.succ[1].sid == SID.b and M.hostSid == SID.host, "the host's line kept (3, you first)")
check(M.allyList and #M.allyList == 2 and M.allyList[2].sid == SID.c, "the allies kept (2)")
local copy = obj("copy")
copy.HealthInternal = 5000
function copy:SetMinHealth() end
function copy:ModifyHealth() self.HealthInternal = 0 end
M.copies = { [7] = { obj = copy, exp = 5000, addr = copy.addr } }
local hostPlane = M.peers[0].obj
local o0, from = #opens, #logs + 1
inbox[#inbox + 1] = "0|sys|lost"
tick()
check(M.hostLostAt ~= nil, "the host's link lost: the clock runs")
tick(29)
check(#opens == o0 and not M.mig, "29 s on: still waiting")
tick(2)
local op = opens[#opens]
check(op and op.role == "host" and op.partner == SID.a .. "," .. SID.c .. ",auto",
      "31 s on: this game opens as host looking for the others' Steam IDs (" .. tostring(op and op.partner) .. ")")
check(COOP.host() and M.mig and M.mig.hosting, "it's the host")
check(copy.HealthInternal == 0, "the old host's copies taken down")
check(hostPlane.hidden == true and M.peers[0] == nil, "the old host's plane set aside, hidden")
check(D.round == 4 and D.state == "wait" and D.at == 500 + 15 and D.startRound == 1, "round 5 again after 15 s (D.round 4, wait, at +15)")
check(callouts[#callouts] and has(callouts[#callouts], "YOU ARE THE NEW HOST") and has(callouts[#callouts], "ROUND 5"), "said: YOU ARE THE NEW HOST, ROUND 5")
local names = COOP.joinWaiting(0)
check(names and #names == 2, "the round held for the 2 others (" .. table.concat(names or {}, ", ") .. ")")
tick(5)
check(#built == 2 and built[1].price == 0, "5 s on: the allies and defences built again, at no cost (" .. #built .. ")")
local wb = nil
for _, b in ipairs(built) do if b.name == "Wingmen" then wb = b end end
check(wb and wb.slot == nil, "Cid's WINGMEN while Cid isn't back: the room's")
check(built[1].name == "AAGun" and built[1].kind == "aa" or built[2].name == "AAGun" and built[2].kind == "aa", "an AA gun by its kind")
-- Ann back as player 2 (slot 1): her plane stays hers; Cid back as player 3 (slot 2): his moves from slot 3 to 2
peerIds = "1:" .. SID.a .. ":200:100:0:1,2:" .. SID.c .. ":150:100:0:1"
M.roster[1] = { name = "Ann", sid = SID.a }
M.roster[2] = { name = "Cid", sid = SID.c }
local cidPlane = M.peers[3].obj
swaps = {}
tick()
check(M.peers[2] and M.peers[2].obj == cidPlane and swaps[1] == "2<>3", "Cid back in slot 2: his plane moved with him (" .. tostring(swaps[1]) .. ")")
check(M.peers[1] and M.peers[1].sid == SID.a, "Ann's plane where it was")
check(COOP.joinWaiting(0) == nil, "everyone back: the round's not held")
-- a newcomer in slot 3 later: Bee's old plane there (there's none: Bee is this game) ... a stranger's plane in slot 1
M.roster[1] = { name = "Dee", sid = "76561198000000009" }
local annPlane = M.peers[1].obj
tick()
check(not (M.peers[1] and M.peers[1].obj == annPlane) and annPlane.hidden == true and line("set aside, hidden (the slot is another player's now)") ~= nil,
      "a slot that's another player's now: the old plane set aside, hidden")

print("... nobody came back and another host is heard")
asJoiner(SID.b, 2)
inbox[#inbox + 1] = "0|sys|lost"
tick(); tick(31)
check(COOP.host(), "this game took over")
local o1 = #opens
inbox[#inbox + 1] = "0|sys|samerole"
tick()
check(opens[#opens] and opens[#opens].role == "join" and has(opens[#opens].partner, SID.host) and #opens == o1 + 1,
      "alone, hearing another host: it joins the old host again (" .. tostring(opens[#opens] and opens[#opens].partner) .. ")")

---------------------------------------------------------------------------------------------------- the others
print("the others follow")
asJoiner(SID.c, 3)
info.state = "lost"
inbox[#inbox + 1] = "0|sys|lost"
tick(); tick(31)
check(opens[#opens].role == "join" and opens[#opens].partner == SID.b, "31 s on: it joins Bee, first in line (" .. tostring(opens[#opens].partner) .. ")")
check(callouts[#callouts] and has(callouts[#callouts], "BEE TAKES OVER"), "said: BEE TAKES OVER")
tick(21)
check(opens[#opens].partner == SID.a, "Bee silent 20 s: Ann, next (" .. tostring(opens[#opens].partner) .. ")")
info.state = "linked"
tick()
check(M.mig == nil and has(callouts[#callouts], "ANN IS HOSTING"), "linked: it's over (" .. tostring(callouts[#callouts]) .. ")")
-- Ann is the host now (slot 0): her plane (slot 1 here) moves to slot 0, the old host's to slot 1
inbox[#inbox + 1] = "0|pi|0|f16c_common|" .. VERSION .. "|Ann|f16c||||" .. SID.a
local annPlaneHere = M.peers[1].obj
swaps = {}
tick()
check(M.peers[0] and M.peers[0].obj == annPlaneHere and swaps[1] ~= nil, "the new host's plane moved to slot 0 (" .. tostring(swaps[1]) .. ")")
-- Cid given Bee's old slot (2) by Ann: Bee's plane there moves to Bee's new slot (1) once her entry's in
COOP.slot = 2
local beePlane = M.peers[2].obj
swaps = {}
tick()
check(beePlane.hidden == true and M.peers[2] and M.peers[2].obj == beePlane, "a plane in this game's own slot now: hidden at once, kept for its player")
inbox[#inbox + 1] = "0|pi|1|f16c_common|" .. VERSION .. "|Bee|f16c||||" .. SID.b
tick()
check(M.peers[1] and M.peers[1].obj == beePlane and swaps[1] == "1<>2" and M.peers[1].shown ~= false,
      "Bee's entry in as player 2: her plane moved there from this game's slot (" .. tostring(swaps[1]) .. ")")
local stray = obj("stray")
M.peers[2] = { obj = stray, sid = "76561198000000008", real = true }
tick(); tick(11)
check(M.peers[2] == nil and stray.hidden == true and line("its player isn't back") ~= nil, "one whose player never turns up: set aside 10 s on")

print("... nobody answers")
asJoiner(SID.c, 3)
info.state = "lost"
inbox[#inbox + 1] = "0|sys|lost"
tick(); tick(31); tick(21); tick(21)
check(opens[#opens].role == "host" and opens[#opens].partner == SID.b .. "," .. SID.a .. ",auto" and COOP.host(),
      "Bee and Ann silent: Cid, last in line, takes over (" .. tostring(opens[#opens].partner) .. ")")
asJoiner(SID.c, 3)
M.succ = { { slot = 2, sid = SID.b }, { slot = 1, sid = SID.a } }        -- (Cid joined after the last line was sent)
info.state = "lost"
inbox[#inbox + 1] = "0|sys|lost"
tick(); tick(31); tick(21); tick(21)
check(opens[#opens].role == "join" and opens[#opens].partner == SID.host .. ",auto" and M.mig == nil and has(callouts[#callouts], "NO NEW HOST"),
      "not in the line, nobody answers: back to looking for the old host (" .. tostring(opens[#opens].partner) .. ")")

print("... the host said it's reloading")
asJoiner(SID.c, 3)
inbox[#inbox + 1] = "0|hl|120"
tick()
info.state = "lost"
inbox[#inbox + 1] = "0|sys|lost"
local o2 = #opens
tick(); tick(60)
check(#opens == o2 and not M.mig, "the host's reloading (hl 120): 60 s on, still waiting")
tick(61)
check(#opens == o2 + 1 and opens[#opens].partner == SID.b, "121 s on: the next host")

print("... off")
asJoiner(SID.c, 3)
CFG.coop.migration.enabled = false
info.state = "lost"
inbox[#inbox + 1] = "0|sys|lost"
local o3 = #opens
tick(); tick(200)
check(#opens == o3, "[coop.migration] enabled = false: nothing")
CFG.coop.migration.enabled = true

print(fails == 0 and "migration test: all passed" or ("migration test: " .. fails .. " FAILED"))
if fails > 0 then for i = math.max(1, #logs - 25), #logs do print("    log: " .. logs[i]) end end
os.exit(fails == 0 and 0 or 1)
