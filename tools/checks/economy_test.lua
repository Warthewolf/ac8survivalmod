-- economy_test.lua <mod dir> <work dir> (run by tools/checks/economy_test.sh): 0.73.78's economy C3-C6 and the
-- airstrike's limits (the economy proposal approved 2026-11-03; plan Workstream G3 / G6), on the real sv_core, sv_config,
-- sv_rows, sv_ai, sv_hud, sv_spawn, sv_rounds, sv_flights, sv_shop, sv_allies, sv_tactical and sv_coop (M and
-- onJoinerMessage exposed), the game stubbed:
--   C4 / C5: the STORE's AIRSTRIKE, ECM BURST and DECOY rows priced price + price_per_round x the round (the round in
--     play, in a break the next one): 5500 / 3500 at round 5, 10000 / 6500 at 20, 17500 / 11500 at 45; the charge and
--     NOT ENOUGH ZOLLARS at the label's price; items without price_per_round as before; price_per_round on any item; the
--     airstrike's kills x0.25 (airstrike_x);
--   G6: one airstrike bought a round (the row's label and why, the next round's sale; per_round 0: no limit); the call
--     only by its key (an auto call refused, none from the auto tick with 12 enemies on you), one called a round (its
--     callout, the next round's), never an ace squadron's flights (the host's D.aceSquad, a joiner's ace rows from the
--     host's spawn; only an ace squadron near: held, its callout), at most max_hit of the flight, the nearest you
--     (max_hit 0: the whole flight); nothing hit: the item and the round's call back; the row's help;
--   C3: a co-op host's special pays x 1 / sqrt(players), sent so ("cr") with the share in its reason; the round's bonus
--     and kills whole; solo, alone and outside the round logic whole; special_split 0 and 1; a joiner paying the host's
--     "cr" as sent; specialPay for the callouts, and every special reward's callout through it (by the source).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.73.78-economy.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
local events = {}
function SV_Event(name) events[#events + 1] = name; return 1 end
function SV_UnitAlive() return 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Spawn() return 1 end
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end
local requests = {}
function SV_ShopRequest(probe)
    if probe then return 1 end
    return table.remove(requests, 1) or ""
end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
local sent = {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=0" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt() return "" end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

local function part(name, chunk, edits) PARTS.load(name, chunk, edits) end   -- (the part and its pieces, each edit in the piece with its text)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function liveAddr(o) return valid(o) and (addrOf(o) or 1) or nil end
svLevelOn = true
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_flights.lua"); part("sv_shop.lua"); part("sv_allies.lua"); part("sv_tactical.lua")
LB = LB or {}
LB.stat, LB.special = LB.stat or function() end, LB.special or function() end   -- (sv_leaderboard.lua, not loaded here)
local onAirfield = true
function playerOnAirfield() return onAirfield end
local callouts = {}
function hudCallout(t, sub) callouts[#callouts + 1] = tostring(t) .. " / " .. tostring(sub) end
local function line(pat, from)
    for i = #logs, from or 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end
    return nil
end
local function lastCallout() return callouts[#callouts] end

local tick = 0
local function shop(...)
    for _, r in ipairs({ ... }) do requests[#requests + 1] = "SV_Buy_" .. r end
    RUN.dirty = true
    tick = tick + 1
    shopTick(tick)
    tick = tick + 1
    RUN.dirty = true
    shopTick(tick)
end
local function newRun()
    D = { round = 5, state = "fighting", now = 100, up = {}, flown = {}, queue = {}, events = {}, orders = {} }
    RUN.credits, RUN.spent, RUN.earned, RUN.bought, RUN.msg, RUN.items = 1000000, 0, 0, {}, {}, {}
    RUN.defences, RUN.offerShown, RUN.strikeBuys, RUN.strikeCalls = nil, nil, nil, nil
end
local IT, TA = CFG.shop.items, CFG.tactical

---------------------------------------------------------------------------------------------------- C4 / C5
print("C4 / C5: the tactical items' prices by the round")
check(IT.Airstrike.price == 4000 and IT.Airstrike.price_per_round == 300 and IT.Ecm.price == 2500 and IT.Ecm.price_per_round == 200
      and IT.Decoy.price == 2500 and IT.Decoy.price_per_round == 200 and CFG.credits.airstrike_x == 0.25,
      "shipped: AIRSTRIKE 4000 + 300 a round, ECM BURST and DECOY 2500 + 200 a round, an airstrike's kills x0.25")
newRun()
local function rows(r, state)
    D.round, D.state = r, state
    shop()
    return texts.SV_Shop_Airstrike, texts.SV_Shop_Ecm, texts.SV_Shop_Decoy
end
local a, e, d = rows(5, "fighting")
check(a == "AIRSTRIKE (0/2)   5500 Z" and e == "ECM BURST (0/2)   3500 Z" and d == "DECOY (0/2)   3500 Z",
      "round 5: 5500, 3500, 3500 (" .. tostring(a) .. "; " .. tostring(e) .. "; " .. tostring(d) .. ")")
a, e = rows(20, "spawning")
check(a == "AIRSTRIKE (0/2)   10000 Z" and e == "ECM BURST (0/2)   6500 Z", "round 20: 10000, 6500 (" .. tostring(a) .. "; " .. tostring(e) .. ")")
a, e = rows(45, "wave")
check(a == "AIRSTRIKE (0/2)   17500 Z" and e == "ECM BURST (0/2)   11500 Z", "round 45: 17500, 11500 (" .. tostring(a) .. "; " .. tostring(e) .. ")")
a, e = rows(4, "wait")
check(a == "AIRSTRIKE (0/2)   5500 Z" and e == "ECM BURST (0/2)   3500 Z", "in the break after round 4: round 5's prices (" .. tostring(a) .. ")")
a = rows(0, "wait")
check(a == "AIRSTRIKE (0/2)   4300 Z", "before round 1: round 1's 4300 (" .. tostring(a) .. ")")
check(texts.SV_Shop_Insurance == "SECOND CHANCE   50000 Z", "an item without price_per_round as before: SECOND CHANCE 50000 (" .. tostring(texts.SV_Shop_Insurance) .. ")")
IT.Insurance.price_per_round = 1000
rows(20, "fighting")
check(texts.SV_Shop_Insurance == "SECOND CHANCE   70000 Z", "price_per_round on any item: SECOND CHANCE 50000 + 1000 a round, 70000 at 20")
IT.Insurance.price_per_round = nil
local c0 = RUN.credits
shop("Ecm")
check(c0 - RUN.credits == 6500 and RUN.items.ecm == 1 and RUN.msg.Ecm == "ECM BURST READY (1 carried) for 6500 (round 20's price).",
      "bought at round 20: 6500 charged, the label's price (" .. tostring(RUN.msg.Ecm) .. ")")
RUN.credits = 6490
shop("Decoy")
check(RUN.credits == 6490 and RUN.msg.Decoy == "NOT ENOUGH ZOLLARS (6500 needed).", "6490 Z: NOT ENOUGH ZOLLARS at that price (" .. tostring(RUN.msg.Decoy) .. ")")
check(has(readAll(MOD .. "/Scripts/sv_main.lua"), 'local byX = (by == "airstrike" and (c.airstrike_x or 1))'),
      "creditKill: an airstrike's kill pays airstrike_x")

---------------------------------------------------------------------------------------------------- G6: the STORE
print("G6: one airstrike bought a round")
newRun()
shop()
check(has(texts.SV_Shop_Airstrike_Help, "Destroys up to 4 aircraft of the biggest enemy flight within 15 km of you, never an ace squadron's (Ctrl+F1). One a round, bought or called. Kills pay 25%."),
      "its help: up to 4, never an ace squadron's, its key only, one a round, 25 % (" .. tostring(texts.SV_Shop_Airstrike_Help) .. ")")
check(not has(texts.SV_Shop_Airstrike_Help, "by itself") and has(texts.SV_Shop_Ecm_Help, "or by itself when 2 missiles close in"),
      "the airstrike never goes by itself; the ECM burst's auto as before")
c0 = RUN.credits
shop("Airstrike")
check(RUN.items.airstrike == 1 and c0 - RUN.credits == 5500 and RUN.strikeBuys and RUN.strikeBuys.round == 5, "round 5: one bought, 5500")
check(texts.SV_Shop_Airstrike == "AIRSTRIKE (1/2): ONE A ROUND" and has(texts.SV_Shop_Airstrike_Help, "Bought for round 5: the next once it's over."),
      "its row: AIRSTRIKE (1/2): ONE A ROUND, no price (" .. tostring(texts.SV_Shop_Airstrike) .. ")")
c0 = RUN.credits
shop("Airstrike")
check(RUN.items.airstrike == 1 and RUN.credits == c0 and RUN.msg.Airstrike == "ONE A ROUND: THE NEXT AFTER ROUND 5.",
      "a second press in round 5: refused, nothing charged (" .. tostring(RUN.msg.Airstrike) .. ")")
check(has(line("shop: Airstrike: ONE A ROUND: THE NEXT AFTER ROUND 5."), "ONE A ROUND"), "... logged")
D.state = "wait"                                     -- (round 5 cleared: the break is round 6's)
shop()
check(texts.SV_Shop_Airstrike == "AIRSTRIKE (1/2)   5800 Z", "the break after round 5: sold again at round 6's 5800 (" .. tostring(texts.SV_Shop_Airstrike) .. ")")
shop("Airstrike")
check(RUN.items.airstrike == 2 and RUN.strikeBuys.round == 6, "... bought: 2 carried")
D.round, D.state = 7, "fighting"
shop("Airstrike")
check(RUN.items.airstrike == 2 and RUN.msg.Airstrike == "YOU CARRY AS MANY AS YOU CAN.", "2 of 2 carried: as many as you can")
TA.airstrike.per_round = 0
RUN.items.airstrike = 0
shop("Airstrike"); shop("Airstrike")
check(RUN.items.airstrike == 2, "per_round 0: two in one round")
TA.airstrike.per_round = 1

---------------------------------------------------------------------------------------------------- G6: the call
print("G6: the airstrike's call")
newRun()
onAirfield = false
local YOU = { X = 0, Y = 0, Z = 300000 }
function playerLocation() return YOU end
local nextAddr = 5000
local function plane(unit, dkm)
    nextAddr = nextAddr + 1
    local o = { addr = nextAddr, full = "BP_OP1022_f16c_CP_C_" .. nextAddr, hits = 0 }
    function o:ModifyHealth(dmg, by) self.hits = self.hits + 1; self.by = by end
    return { unit = unit, at = { X = dkm * 100000, Y = 0, Z = 300000 }, obj = o, name = o.full }
end
local U1, U2, U3 = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air0", "ERA_Unit_03_Dep_Air0"
local function sky()
    planes = {}
    for _, k in ipairs({ 9, 3, 7, 4, 8, 5 }) do planes[#planes + 1] = plane(U1, k) end      -- (6, nearest 3, 4, 5, 7)
    for k = 1, 8 do planes[#planes + 1] = plane(U2, 2 + k * 0.5) end                       -- (an ace squadron's wing: 8)
    return planes
end
sky()
D.aceSquad = { [U2] = true }                         -- (the host's spawner: Harvest's wing flight, no ace leading it)
D.aceOf = {}
check(TAC.aceFlight(U2) and not TAC.aceFlight(U1), "the host: an ace squadron's wing flight known (D.aceSquad), not led by an ace")
RUN.items = { airstrike = 2 }
local from = #logs + 1
check(TAC.use("airstrike", "auto") == false and RUN.items.airstrike == 2 and TAC.strike == nil
      and line("tactical: airstrike (auto) refused: only its key calls it", from) ~= nil, "an auto call: refused, nothing used (logged)")
D.now = 200
local ok = TAC.use("airstrike", "key")
check(ok and TAC.strike and TAC.strike.unit == U1 and #TAC.strike.planes == 4, "Ctrl+F1: the ordinary flight (6) struck, not the bigger ace squadron's (8); 4 of it")
local dk = {}
for _, p in ipairs(TAC.strike and TAC.strike.planes or {}) do dk[#dk + 1] = string.format("%g", p.at.X / 100000) end
table.sort(dk)
check(table.concat(dk, ",") == "3,4,5,7", "... the 4 nearest you: 3, 4, 5, 7 km (" .. table.concat(dk, ",") .. ")")
check(lastCallout() == "AIRSTRIKE INBOUND / TARGET: 4 AIRCRAFT" and RUN.items.airstrike == 1, "its callout: TARGET: 4 AIRCRAFT; one left")
check(has(line("tactical: airstrike (key) on " .. U1 .. ", 4 of its 6 aircraft", from), "round 5's 1 of 1; 8 of an ace squadron's near, spared"),
      "logged: 4 of its 6, round 5's 1 of 1, the ace squadron spared (" .. tostring(line("tactical: airstrike (key) on", from)) .. ")")
D.now = 205
TAC.tick(D.now)
local hit, struck = 0, 0
for _, p in ipairs(planes) do if p.obj.hits > 0 then hit = hit + 1 end; if p.struck then struck = struck + 1 end end
check(hit == 4 and struck == 4 and lastCallout() == "AIRSTRIKE: 4 DOWN / nil", "4 s on: 4 hit (ModifyHealth), struck, AIRSTRIKE: 4 DOWN")
from = #logs + 1
local n0 = #callouts
check(TAC.use("airstrike", "key") == false and RUN.items.airstrike == 1 and callouts[#callouts] == "AIRSTRIKE HELD / ONE A ROUND: THE NEXT IN ROUND 6"
      and #callouts == n0 + 1 and line("tactical: airstrike held: 1 called in round 5 already (1 a round", from) ~= nil,
      "a second call in round 5: held, its callout (ONE A ROUND: THE NEXT IN ROUND 6), logged, nothing used")
D.round = 6
sky()
check(TAC.use("airstrike", "key") and #TAC.strike.planes == 4, "round 6: called again")
TAC.strike = nil
RUN.items.airstrike, RUN.strikeCalls = 2, nil
-- only the ace squadron near
planes = {}
for k = 1, 8 do planes[#planes + 1] = plane(U2, 2 + k * 0.5) end
from = #logs + 1
check(TAC.use("airstrike", "key") == false and RUN.items.airstrike == 2 and lastCallout() == "AIRSTRIKE HELD / NEVER ON AN ACE SQUADRON"
      and line("tactical: airstrike held: only an ace squadron's flights within 15 km (8 aircraft): never on them", from) ~= nil,
      "only an ace squadron's flight near: held, NEVER ON AN ACE SQUADRON, logged, nothing used")
check(RUN.strikeCalls == nil or RUN.strikeCalls.n == 0, "... not counted as the round's call")
-- a joiner: no D.aceSquad; the host's spawn set the flight's rows (SPW.noteRows)
D.aceSquad, D.aceOf = nil, nil
SPW = { row = { [U2] = "sv_ace_reaper_su57_w_sv1" }, leadRow = {} }
check(TAC.aceFlight(U2) and not TAC.aceFlight(U1), "a joiner: the ace squadron's flight known by its row from the host's spawn (sv_ace_*)")
SPW.row, SPW.leadRow = { [U2] = "sv_f16c_common_sv" }, { [U2] = "SV_Ace_reaper_su57_l_sv" }
check(TAC.aceFlight(U2), "... or by its lead's row")
sky()
check(TAC.use("airstrike", "key") and TAC.strike.unit == U1, "a joiner: struck the ordinary flight, the ace squadron's spared")
TAC.strike = nil
SPW = nil
-- max_hit 0: the whole flight
RUN.strikeCalls, D.aceSquad = nil, { [U2] = true }
TA.airstrike.max_hit = 0
sky()
check(TAC.use("airstrike", "key") and #TAC.strike.planes == 6, "max_hit 0: the whole flight (6)")
-- nothing hit (all gone first): the item and the round's call back
for _, p in ipairs(TAC.strike.planes) do p.obj.gone = true end
local items = RUN.items.airstrike
D.now = 300; TAC.strike.at = 300
TAC.tick(D.now)
check(RUN.items.airstrike == items + 1 and RUN.strikeCalls.n == 0, "nothing hit: the airstrike back, and the round's call")
TA.airstrike.max_hit = 4
-- no auto call: 14 enemies within 10 km, airstrikes carried, a whole fight of ticks
RUN.items, RUN.strikeCalls, TAC.strike = { airstrike = 2 }, nil, nil
sky()
for k = 1, 20 do D.now = 400 + k; TAC.tick(D.now) end
check(TAC.strike == nil and RUN.items.airstrike == 2, "14 enemies within 10 km for 20 s, two carried: never called by itself")
check(TA.airstrike.auto == nil and TA.airstrike.auto_near == nil and TA.airstrike.per_round == 1 and TA.airstrike.max_hit == 4,
      "[tactical.airstrike]: auto / auto_near / auto_km gone; per_round 1, max_hit 4")
onAirfield = true

---------------------------------------------------------------------------------------------------- C3
print("C3: a special's reward split in co-op")
local roundsHook
function roundsTick() if roundsHook then roundsHook() end end   -- (the host's round logic: sv_coop.lua mirrors it)
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" }, { "\nlocal function onJoinerMessage%(f%)", "\nfunction onJoinerMessage(f)" } })
local M = _G.M
check(type(COOP.specialShare) == "function" and type(specialPay) == "function", "the parts loaded: COOP.specialShare, specialPay")
local function players(n) M.roster = {}; for s = 0, n - 1 do M.roster[s] = { name = "p" .. s } end end
local function pay(n, why, inRound)
    local c = RUN.credits
    if inRound == false then addCredits(n, why) else roundsHook = function() addCredits(n, why) end; roundsTick(0); roundsHook = nil end
    return RUN.credits - c
end
local function crs(from) local t = {}; for i = from or 1, #sent do if sent[i]:find(">cr|", 1, true) then t[#t + 1] = sent[i] end end; return t end
newRun()
COOP.open, COOP.role, COOP.slot = false, nil, nil
players(1)
check(pay(16500, "VALKA down") == 16500 and #crs() == 0 and specialPay(16500) == 16500, "solo: VALKA's 16500 whole, nothing sent")
COOP.open, COOP.role, COOP.slot = true, "host", 0
players(1)
check(COOP.specialShare() == 1 and pay(16500, "VALKA down") == 16500, "a co-op host alone: whole")
local shares = {}
for _, n in ipairs({ 2, 3, 4, 5 }) do players(n); shares[#shares + 1] = string.format("%.2f", COOP.specialShare()) end
check(table.concat(shares, " ") == "0.71 0.58 0.50 0.45", "1 / sqrt(players): 0.71 0.58 0.50 0.45 with 2-5 (" .. table.concat(shares, " ") .. ")")
players(2)
local s0 = #sent
from = #logs + 1
local got = pay(16500, "VALKA down")
check(got == 11667 and table.concat(crs(s0 + 1), " ") == "-1>cr|11667|VALKA down, co-op share x0.71 of 16500 (2 players)",
      "2 players: VALKA's 16500 pays the host 11667 and sends cr|11667 (" .. got .. "; " .. table.concat(crs(s0 + 1), " ") .. ")")
check(line("credits: +11667 (VALKA down, co-op share x0.71 of 16500 (2 players)), now", from) ~= nil, "... its credits line names the share")
check(specialPay(16500) == 11667, "specialPay (the callouts'): 11667")
players(4)
check(pay(28800, "the Alicorn sunk") == 14400 and pay(2400, "the spaceport's fleet: aegis sunk") == 1200
      and pay(300, "landing craft sunk (lane A)") == 150 and pay(1000, "Alicorn ballast tank down") == 500,
      "4 players: the Alicorn 28800 -> 14400, an Aegis 2400 -> 1200, a landing craft 300 -> 150, a ballast tank 1000 -> 500")
players(5)
check(pay(19100, "MINDRIPPER down") == 8542, "5 players: MINDRIPPER's 19100 -> 8542")
s0 = #sent
check(pay(1250, "round 5 cleared") == 1250 and table.concat(crs(s0 + 1), " ") == "-1>cr|1250|round 5 cleared", "the round's bonus: whole, sent whole")
s0 = #sent
check(pay(180, "f16c down (fighter, Regular x1.1)") == 180 and #crs(s0 + 1) == 0, "a kill: whole, not sent (each game pays its own)")
s0 = #sent
check(pay(16500, "VALKA down", false) == 16500 and #crs(s0 + 1) == 0, "outside the host's round logic: whole, not sent (as before)")
players(2)
CFG.credits.special_split = 0
check(COOP.specialShare() == 1 and pay(16500, "VALKA down") == 16500, "special_split 0: the whole reward to everyone")
CFG.credits.special_split = 1
check(pay(16500, "VALKA down") == 8250, "special_split 1: an equal split, 8250")
CFG.credits.special_split = 0.5
-- a joiner pays the host's "cr" as sent
COOP.role, COOP.slot = "join", 1
local c1 = RUN.credits
from = #logs + 1
onJoinerMessage({ "cr", "11667", "VALKA down, co-op share x0.71 of 16500 (2 players)" })
check(RUN.credits - c1 == 11667 and line("credits: +11667 (VALKA down, co-op share x0.71 of 16500 (2 players) (the host's round)), now", from) ~= nil,
      "a joiner: the host's cr|11667 paid as sent (" .. (RUN.credits - c1) .. ")")
check(specialPay(16500) == 16500, "a joiner's specialPay: as given (its callouts are the host's)")
s0 = #sent
check(pay(16500, "VALKA down", false) == 16500 and #crs(s0 + 1) == 0, "a joiner's own pay: never split nor sent")
COOP.open = false
-- every special reward's callout through specialPay (by the source)
local sites = {
    { "sv_anomalies.lua", "string.format(t.anomaly_down_sub, specialPay(pay))", 3 },
    { "sv_ladon.lua", "string.format(t.ladon_down_sub, specialPay(pay))", 1 },
    { "sv_alicorn.lua", "string.format(t.alicorn_down_sub, specialPay(pay))", 1 },
    { "sv_rounds.lua", "string.format(t.launched_sub, specialPay(pay))", 1 },
    { "sv_spaceport.lua", "string.format(t.sp_held_sub, specialPay(pay))", 1 },
    { "sv_spaceport.lua", "string.format(t.sp_retaken_sub, specialPay(pay))", 1 },
    { "sv_spaceport.lua", "string.format(t.sp_rocket_down_sub, specialPay(pay))", 1 },
    { "sv_amphib.lua", "string.format(t.repelled_sub, specialPay(pay))", 1 },
}
local bad = {}
for _, s in ipairs(sites) do
    local src, n = PARTS.read(s[1]), 0
    local at = 1
    while true do
        local i = src:find(s[2], at, true)
        if not i then break end
        n, at = n + 1, i + 1
    end
    if n ~= s[3] then bad[#bad + 1] = s[1] .. " " .. s[2] .. " x" .. n end
end
check(#bad == 0, "every special reward's callout shows each player's share (" .. (#bad > 0 and table.concat(bad, "; ") or "10 sites") .. ")")

logFile:close()
print("economy test: " .. (fails > 0 and (fails .. " FAILED") or "all passed"))
os.exit(fails > 0 and 1 or 0)
