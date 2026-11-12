-- deal_test.lua <mod dir> (run by tools/checks/deal_test.sh): THE DEAL (Scripts/sv_deal.lua) on its own, the game, the
-- subtitles, the HUD and co-op stubbed. Covered:
--   solo: no offer on a kind it isn't listed for, nor when the dice say no (logged), nor in the STORE (later, once it's
--     shut), nor before offer_after_s; the offer: the Hornet up ahead of you (its name set, an ally's unit), War's
--     introduction, the vote opening after it with its callout; the NEXT row (keys, tally, clock, your vote); Ctrl+A /
--     Ctrl+X; one player answering closes it; YES taken; NO refused; nobody answering by the clock: NO; the clock held
--     while paused; the leaving lines, the Hornet taken off leave_s after; the pay at the round's clear (what was
--     earned while it was on x (kills_x - 1), the round's own bonus and the deal's own pay left out, plus the bonus), and
--     none when the round moves on uncleared;
--   co-op host: "dl" sent reliable as it opens and as a vote comes in, unreliable every resend_s; a joiner's "vt"; a tie is
--     NO; everyone answering closes it; "dr" sent with the result; allow_change (the last answer counts; off: the first);
--     hostile "vt"s (slot, id, value, a closed vote, the host's own slot) ignored;
--   co-op joiner: the host's "dl" opens its view, the keys send "vt" to the host (not recorded here), "dr" closes it and a
--     deal taken pays this game's own extra only (COOP.payOwn), hostile "dl" / "dr" ignored, a vote with no result dropped;
--   Ctrl+H: offered now (host), refused on a joiner and with a deal on.
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function has(s, part) return s ~= nil and tostring(s):find(part, 1, true) ~= nil end

-- the world
local logs, callouts, said, spawns, recycles, sent, credits, own = {}, {}, {}, {}, {}, {}, {}, {}
function log(s) logs[#logs + 1] = s end
local function logged(part) for _, l in ipairs(logs) do if has(l, part) then return true end end return false end
local function clearLogs() logs = {} end
function hudCallout(t, s) callouts[#callouts + 1] = { t, s } end
local isUsed = {}
SUB = {
    say = function(who, text)
        local key = who .. "|" .. text
        if isUsed[key] then return false end
        isUsed[key] = true
        said[#said + 1] = key
        return true
    end,
    fresh = function(x) for _, l in ipairs(x) do if isUsed[l] then return false end end return true end,
    left = function() return 6 end,
}
CFG = { specials = {}, hud = { subs = { colors = {} } } }
CFG_DEFAULTS = { specials = {}, hud = { subs = { colors = {} } } }
function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
TEST_TICKS, TEST_KEYS = {}, {}
local testKeys = {}
function testKey(name, who, fn) testKeys[name] = fn; return true end
Key = { A = 65, X = 88, H = 72 }
ModifierKey = { CONTROL = 1 }
local binds = {}
function RegisterKeyBind(key, mods, fn) binds[key] = fn end
function ExecuteInGameThread(f) f() end
local PAUSED = false
function gamePaused() return PAUSED end
function valid(o) return o ~= nil end
local pawn = {
    K2_GetActorLocation = function() return { X = 100000, Y = 200000, Z = 300000 } end,
    K2_GetActorRotation = function() return { Yaw = 0 } end,
}
survivalPC = { Pawn = pawn }
local HORNET_OK = true
function SV_Spawn(unit, x, y, z, yaw) spawns[#spawns + 1] = { unit, x, y, z, yaw }; return HORNET_OK and 1 or -2 end
local texts = {}
function SV_SetText(k, v) texts[k] = v; return 1 end
function SV_Recycle(u, n) recycles[#recycles + 1] = u; return 1 end
SV_ERR = { [-2] = "no such unit or aircraft" }
ALLY = { unit = {} }
local STORE_SHUT = true
SPC = { storeShut = function() return STORE_SHUT end }
local raw = function(n, why) credits[#credits + 1] = { n, why } end
addCredits = raw
local ROLL = 0.1
math.random = function(n) if n then return 1 end return ROLL end        -- luacheck: ignore

-- co-op: off (solo) until a case turns it on
COOP = { open = false, role = nil, slot = nil, peers = 1 }
function COOP.host() return COOP.open and COOP.role == "host" end
function COOP.client() return COOP.open and COOP.role == "join" end
function COOP.msg(to, ...) sent[#sent + 1] = { to = to, reliable = true, f = { ... } } ; return true end
function sendTo(to, reliable, ...) sent[#sent + 1] = { to = to, reliable = reliable, f = { ... } }; return true end
function COOP.slotOk(s) return type(s) == "number" and s == math.floor(s) and s >= 0 and s <= 23 end
function COOP.players() local l = {}; for i = 1, COOP.peers do l[i] = { slot = i - 1 } end return l end
function COOP.payOwn(n, why) own[#own + 1] = { n, why } end
function COOP.localCallout(t, s) callouts[#callouts + 1] = { t, s, here = true } end

dofile(MOD .. "/Scripts/sv_deal.lua")
local C = CFG.specials.deal
check(type(DEAL) == "table" and type(C) == "table", "the part loads: DEAL and CFG.specials.deal")
check(CFG_DEFAULTS.specials.deal ~= nil and CFG_DEFAULTS.specials.deal ~= C and CFG_DEFAULTS.specials.deal.vote_s == 30,
    "its settings in CFG_DEFAULTS too (not an edit), a copy; vote_s 30 (the user)")
check(CFG.hud.subs.colors.WAR and CFG.hud.subs.colors.HAYTHORN and CFG_DEFAULTS.hud.subs.colors.WAR,
    "WAR's and HAYTHORN's colours on the subtitle strip (and in the defaults)")
check(binds[65] and binds[88] and TEST_KEYS[65] and TEST_KEYS[88], "Ctrl+A / Ctrl+X bound (and known to TEST_KEYS)")
check(testKeys.H ~= nil, "Ctrl+H, the test key")
check(#TEST_TICKS == 1 and TEST_TICKS[1].name == "deal", "its tick among the test ticks")

local clock = 1000
local function run(secs, step)
    step = step or 0.25
    local n = math.floor(secs / step + 0.5)
    for _ = 1, n do clock = clock + step; TEST_TICKS[1].fn(clock) end
end
local function reset()
    D = nil
    run(0.25)
    logs, callouts, said, spawns, recycles, sent, credits, own = {}, {}, {}, {}, {}, {}, {}, {}
    isUsed = {}
end
local function newRound(kind, round)
    D = { round = round or 5, state = "fighting", special = kind and { kind = kind } or nil, now = clock }
end

print("solo")
-- a kind not listed: never
reset(); newRound("shuttle")
run(C.offer_after_s + 5)
check(DEAL.V == nil and #spawns == 0 and not logged("deal:"), "a kind not in kinds (shuttle): no offer, nothing logged")
-- the dice say no
reset(); ROLL = 0.9; newRound("ladon")
run(C.offer_after_s + 5)
check(DEAL.V == nil and logged("no offer (rolled 0.90, chance 0.35)"), "the dice say no: no offer, logged")
run(C.offer_after_s + 5)
check(#spawns == 0, "rolled once a round only")
-- the STORE: later, once it's shut
reset(); ROLL = 0.1; STORE_SHUT = false; newRound("ladon", 6)
run(C.offer_after_s - 5)
check(DEAL.V == nil, "not before offer_after_s")
run(20)
check(DEAL.V == nil, "not while the STORE's open")
STORE_SHUT = true
run(0.5)
local V = DEAL.V
check(V and V.phase == "intro" and logged("offered on round 6 (ladon"), "offered once the STORE's shut (logged)")
check(#spawns == 1 and spawns[1][1] == "SV_Unit_DealHornet" and math.abs(spawns[1][2] - 250000) < 1 and
    math.abs(spawns[1][3] - 270000) < 1 and spawns[1][4] == 315000, "the Hornet up 1.5 km ahead, 0.7 km right, 150 m up")
check(texts.SV_DealHornet == "WAR & HAYTHORN" and ALLY.unit.SV_Unit_DealHornet == "air", "its name WAR & HAYTHORN, an ally's unit")
check(#said == 2 and has(said[1] .. said[2], "WAR|"), "War's introduction said (an exchange of two)")
check(DEAL.row() == nil, "no row before the vote opens")
run(6.5)
check(V.phase == "open" and has(said[3], "WAR|"), "the vote opens after the introduction, War asks")
check(callouts[1] and callouts[1][1] == "THE DEAL" and has(callouts[1][2], "CTRL+A / CTRL+X"), "its callout")
local row = DEAL.row()
check(has(row, "CTRL+A YES / CTRL+X NO") and has(row, "YES 0  NO 0") and has(row, "0:30"), "the NEXT row: " .. tostring(row))
PAUSED = true
run(10)
check(has(DEAL.row(), "0:30") and V.phase == "open", "the clock holds while paused")
PAUSED = false
binds[65]()
run(0.25)
check(V.phase == "closed" and V.taken and logged("YES 1, NO 0: TAKEN (the most votes)") and logged("everyone answered"),
    "Ctrl+A: YES, one player: closed at once, TAKEN")
check(has(DEAL.row(), "THE DEAL: TAKEN (YES 1 / NO 0)"), "the result on the row")
check(logged("the stakes for ladon: none yet"), "the stakes: none yet (the user's call), logged")
check(#sent == 0, "solo: nothing sent")
addCredits(100, "kill: F-16C")
addCredits(250 * 6, "round 6 cleared")
check(DEAL.won and DEAL.won.earned == 100, "earned while it's on counted, the round's clear bonus not")
run(C.result_row_s + 1)
check(DEAL.row() == nil, "the row cleared result_row_s after")
check(logged("deal:") and #said >= 5, "the leaving lines")
run(C.hornet.leave_s)
check(#recycles == 1 and recycles[1] == "SV_Unit_DealHornet" and logged("the Hornet taken off"), "the Hornet taken off leave_s after")
credits = {}
D.state = "wait"
run(0.25)
check(credits[1] and credits[1][1] == 100 and credits[1][2] == "the deal's extra", "paid: the earned 100 again (kills_x 2)")
check(credits[2] and credits[2][1] == 5000 + 250 * 6 and credits[2][2] == "the deal's bonus", "and the bonus 5000 + 250 x round 6")
check(DEAL.won == nil and logged("round 6 cleared with the deal: +100"), "paid once, logged")
check(callouts[#callouts][1] == "THE DEAL PAID" and has(callouts[#callouts][2], "+6600"), "its callout: +6600")

-- NO, and nobody answering
reset(); newRound("valka", 7)
run(C.offer_after_s + 7)
check(DEAL.V and DEAL.V.phase == "open", "valka: open")
binds[88]()
run(0.25)
check(DEAL.V.phase == "closed" and not DEAL.V.taken and logged("REFUSED (the most votes)") and DEAL.won == nil, "Ctrl+X: NO, refused")
reset(); newRound("alicorn", 8)
run(C.offer_after_s + 7)
run(C.vote_s + 0.5)
check(DEAL.V.phase == "closed" and not DEAL.V.taken and logged("the clock ran out") and logged("nobody answered: no"),
    "nobody answers by the clock: NO")
-- taken, then the round moves on uncleared
reset(); newRound("glitch", 9)
run(C.offer_after_s + 7)
binds[65](); run(0.25)
D.round = 10
run(0.25)
check(DEAL.won == nil and logged("never cleared with the deal on") and #credits == 0, "the round moved on uncleared: not paid")
-- no Hornet in this build
reset(); HORNET_OK = false; newRound("ladon", 11)
run(C.offer_after_s + 1)
check(DEAL.V and logged("not spawned (no such unit or aircraft): the deal goes on without the plane"), "no Hornet unit: goes on, logged")
run(7); binds[65](); run(C.leave_after_s + C.hornet.leave_s + 1)
check(#recycles == 0, "and nothing to take off")
HORNET_OK = true

-- a new run with a vote open: dropped
reset(); newRound("ladon", 12)
run(C.offer_after_s + 7)
check(DEAL.V and DEAL.V.phase == "open", "open")
clearLogs(); newRound("ladon", 1)
run(0.25)
check(DEAL.V == nil and logged("the last run's deal dropped") and #recycles == 1, "a new run: the last run's vote dropped, its Hornet off")

print("co-op host")
reset(); COOP.open, COOP.role, COOP.slot, COOP.peers = true, "host", 0, 2
newRound("spaceport", 12)
run(C.offer_after_s + 7)
V = DEAL.V
local function sentOf(k, rel) local n = 0; for _, m in ipairs(sent) do if m.f[1] == k and (rel == nil or m.reliable == rel) then n = n + 1 end end return n end
check(V.phase == "open" and sentOf("dl", true) == 1 and sent[1].to == nil and sent[1].f[2] == V.id and sent[1].f[3] == "spaceport",
    "\"dl\" to everyone, reliable, as it opens")
run(C.resend_s + 0.25)
check(sentOf("dl", false) >= 1, "\"dl\" again unreliable every resend_s")
-- hostile votes
local id = tostring(V.id)
for _, bad in ipairs({ { 1, { "vt", "999", "1" } }, { 1, { "vt", id, "2" } }, { 1, { "vt", id, "nan" } }, { 1, { "vt", id, "0.5" } },
                       { 1, { "vt", id } }, { 1, { "vt" } }, { 30, { "vt", id, "1" } }, { -1, { "vt", id, "1" } },
                       { 0, { "vt", id, "1" } }, { 1.5, { "vt", id, "1" } }, { "x", { "vt", id, "1" } } }) do
    DEAL.onVote(bad[1], bad[2])
end
check(next(V.votes) == nil, "hostile \"vt\"s ignored (a wrong id, value, slot, the host's own slot, cut short)")
binds[65]()
check(V.votes[0] == 1 and V.phase == "open", "the host's YES: still open (2 players)")
DEAL.onVote(1, { "vt", id, "1" })
DEAL.onVote(1, { "vt", id, "0" })
check(V.votes[1] == 0, "allow_change: the joiner's last answer counts")
run(0.25)
check(V.phase == "closed" and not V.taken and logged("YES 1, NO 1: REFUSED (a tie is no)"), "everyone answered: a tie is NO")
local dr
for _, m in ipairs(sent) do if m.f[1] == "dr" then dr = m end end
check(dr and dr.reliable and dr.f[2] == V.id and dr.f[3] == 1 and dr.f[4] == 1 and dr.f[5] == 0, "\"dr\" sent: 1, 1, not taken")
DEAL.onVote(1, { "vt", id, "1" })
check(V.votes[1] == 0, "a vote after the close ignored")
-- allow_change off
reset(); C.allow_change = false; newRound("ladon", 13)
run(C.offer_after_s + 7)
V = DEAL.V
DEAL.onVote(2, { "vt", tostring(V.id), "1" }); DEAL.onVote(2, { "vt", tostring(V.id), "0" })
check(V.votes[2] == 1, "allow_change off: the first answer counts")
C.allow_change = true
-- Ctrl+H
reset(); newRound(nil, 14)
testKeys.H()
check(DEAL.V and DEAL.V.phase == "intro" and logged("offered on round 14 (none, Ctrl+H)"), "Ctrl+H: offered now, no special needed")
clearLogs(); testKeys.H()
check(logged("a deal is on already"), "Ctrl+H again with a deal on: refused")

print("co-op joiner")
reset(); COOP.role, COOP.slot = "join", 1
newRound("ladon", 15)
run(C.offer_after_s + 7)
check(DEAL.V == nil and #spawns == 0, "a joiner never offers")
for _, bad in ipairs({ { "dl" }, { "dl", "0", "ladon", "30", "0", "0" }, { "dl", "1.5", "ladon", "30", "0", "0" },
                       { "dl", "1", "lad on!", "30", "0", "0" }, { "dl", "1", "ladon", "inf", "0", "0" },
                       { "dl", "1", "ladon", "500", "0", "0" }, { "dl", "1", "ladon", "30", "25", "0" },
                       { "dl", "1", "ladon", "30", "-1", "0" }, { "dl", "1", string.rep("a", 400), "30", "0", "0" } }) do
    DEAL.fromHost("dl", bad)
end
check(DEAL.J == nil, "hostile \"dl\"s ignored")
DEAL.fromHost("dl", { "dl", "4", "ladon", "30", "1", "0" })
row = DEAL.row()
check(DEAL.J and has(row, "YES 1  NO 0") and has(row, "0:30"), "the host's \"dl\": the row " .. tostring(row))
binds[88]()
check(sent[#sent].to == 0 and sent[#sent].f[1] == "vt" and sent[#sent].f[2] == 4 and sent[#sent].f[3] == 0, "Ctrl+X: \"vt\" to the host")
check(has(DEAL.row(), "YOU: NO"), "your vote on the row")
local n0 = #sent
binds[88]()
check(#sent == n0, "the same answer again: not sent again")
for _, bad in ipairs({ { "dr", "4", "1", "0", "2" }, { "dr", "4", "x", "0", "1" }, { "dr", "4", "1", "99", "1" }, { "dr", "x", "1", "0", "1" } }) do
    DEAL.fromHost("dr", bad)
end
check(DEAL.J.phase == "open", "hostile \"dr\"s ignored")
DEAL.fromHost("dr", { "dr", "4", "2", "1", "1" })
check(DEAL.J.phase == "closed" and DEAL.J.taken and has(DEAL.row(), "TAKEN (YES 2 / NO 1)") and DEAL.won, "\"dr\": taken, on the row")
addCredits(300, "kill: Su-33")
D.state = "wait"
run(0.25)
check(own[1] and own[1][1] == 300 and #credits == 1, "a joiner: its own extra (COOP.payOwn), no bonus of its own (the host's, sent)")
reset(); newRound("ladon", 16); run(0.25)
DEAL.fromHost("dl", { "dl", "5", "ladon", "30", "0", "0" })
run(41)
check(DEAL.J == nil and logged("no result from the host"), "a vote with no result 10 s after its close: dropped")
clearLogs(); testKeys.H()
check(logged("on a joiner"), "Ctrl+H on a joiner: refused")

print(fails == 0 and "deal test: all passed" or ("deal test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
