-- tells_test.lua <mod dir> <work dir> (run by tools/checks/tells_test.sh): the behaviour roadmap's P3, tells
-- (tools/re/BEHAVIOUR_DIRECTOR.md unit 4), on the real sv_core.lua, sv_config.lua, sv_ai.lua, sv_hud.lua, sv_spawn.lua,
-- sv_stats.lua, sv_tells.lua, sv_alicorn.lua, sv_ladon.lua and sv_coop.lua (M and mirroredEvent exposed), the game stubbed:
--   the catalog (CFG.tells: every tell's lines are RE_SV_Radio<letters>, its texts there, its keys known);
--   the HUD's urgent path (hudCallout / calloutNext: a tell in front of the queue, in place of a waiting one, the banner
--     cut short and put back after it, the queue never over 4);
--   TELL.say / play: a line at random but never the same twice running, the a-th (pick), a chained line, texts filled
--     (compass, o'clock), the gaps by class (urgent, queued callout, radio-only), cooldowns, none between rounds, at the
--     airfield or over the summary, radio / hud / all off; no radio line asked for again within line_gap_s by any tell
--     (reversal and kulbit share theirs: the callout only, or not said), a line that didn't fire not counted;
--   TELL.after: the action lead_s later (TELL.tick, on the round clock), at once unsaid or with tells off, never with need;
--   the wiring: an ace's reversal and kulbit (ACE.movesTick: the call, the move lead_s later), the hunt (ACE.hunt), the
--     ALICORN's railgun (the call and RAILGUN WARNING lead_s before the order, off alert_s after it, at a dive, at the
--     sink; the first call "activated", then the others), its dive, surfacing and VLS volley (after its call), a Ladon's
--     volley, and the raid, jammer, wave and Ctrl+0 hooks by their place in the source;
--   co-op: the host's tells never go out as "co" / "ev" (RE_SV_Radio* kept), TELL.ALL and a slot's tell go as "tl" with
--     their own gaps, and still with the host's own tells off (its leads stand), a joiner plays the host's "tl" from its
--     own catalog, drops unknown ids, non-finite numbers, more than 4 a second, while its level loads, with callouts off
--     or with its own tells off;
--   the ALICORN's RAILGUN WARNING off when the run restarts with it up (SPC.alicornCleanup).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

-- a clock the test moves (co-op's levelReady and rate limits)
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.71.5-tells.test"
local notify = {}
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
function FName(s) return s end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
local airfield = false
function playerOnAirfield() return airfield end
function queueEvent() end
function searchAircraft(a) return a end
local roundsBody = nil                            -- (what the host's "rounds" run, mirrored by sv_coop)
function roundsTick(now) if roundsBody then roundsBody(now) end end
function airfieldTick() end
function bombTick() end
function addCredits() end
function svFlags() return {} end
local events, eventR = {}, 1
function SV_Event(name) events[#events + 1] = name; return eventR end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
local unitAlive = 1
function SV_UnitAlive() return unitAlive end
function SV_Spawn() return 0 end
SV_ERR = { [-5] = "SV_ERR_NOEVENT" }
-- co-op's natives
local menu, sent, inbox = 0, {}, {}
function SV_MenuChoice() return menu end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/p" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt() return "" end

-- the real parts (sv_core's SCRIPT_DIR and log file in the work folder)
local function run(name, chunk, edits)
    local src = readAll(MOD .. "/Scripts/" .. name)
    for _, e in ipairs(edits or {}) do
        local n
        src, n = src:gsub(e[1], e[2], 1)
        assert(n == 1, name .. ": " .. e[1] .. " not found")
    end
    assert(load(src, chunk or ("=" .. name)))()
end
run("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
run("sv_config.lua"); run("sv_ai.lua"); run("sv_hud.lua"); run("sv_spawn.lua"); run("sv_stats.lua")
local hudRaw = hudCallout
run("sv_tells.lua"); run("sv_alicorn.lua"); run("sv_ladon.lua")
run("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" }, { "\nlocal function mirroredEvent%(name%)", "\nfunction mirroredEvent(name)" } })
local M = _G.M
LB.stat, LB.special = function() end, function() end
local C = CFG.tells
local DEF = CFG_DEFAULTS.tells

local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function count(list, pat) local n = 0; for _, v in ipairs(list) do if tostring(v):match(pat) then n = n + 1 end end; return n end
local function deep(t) if type(t) ~= "table" then return t end; local c = {}; for k, v in pairs(t) do c[k] = deep(v) end; return c end
local function reset() CFG.tells = deep(DEF); C = CFG.tells end

-- the player
local you = { X = 0, Y = 0, Z = 300000 }
local pawn = { addr = 0x9, full = "BP_PlayerPlane_PP1000_f16c_C_1", MaxHealth = 100, HealthInternal = 800 }
function pawn:K2_GetActorLocation() return you end
survivalPC = { Pawn = pawn }
HIT = HIT or {}
HIT.msl, HIT.h = {}, 800
local function run0(round) D = { round = round or 10, state = "fighting", now = 100, up = {}, flown = {}, queue = {}, spare = {} } end

---------------------------------------------------------------------------------------------------- the catalog
print("the catalog (CFG.tells)")
do
    local bad, n, events0 = {}, 0, {}
    for id, e in pairs(C.list) do
        n = n + 1
        if not id:match("^[%a_]+$") then bad[#bad + 1] = id .. ": id" end
        for _, ev in ipairs(e.radio or {}) do
            if not ev:match("^RE_SV_Radio%a+$") then bad[#bad + 1] = id .. ": " .. ev end
            events0[ev] = true
        end
        if e.hud and not C.text[e.hud] then bad[#bad + 1] = id .. ": no text " .. e.hud end
        if not (e.radio or e.hud) then bad[#bad + 1] = id .. ": neither a line nor a callout" end
        if e.chain and not C.list[e.chain] then bad[#bad + 1] = id .. ": chain " .. e.chain end
        if e.args and e.args ~= "compass" and e.args ~= "clock" then bad[#bad + 1] = id .. ": args " .. e.args end
        if C.cooldown_s[id] == nil then bad[#bad + 1] = id .. ": no cooldown_s" end
    end
    for id in pairs(C.cooldown_s) do if not C.list[id] then bad[#bad + 1] = "cooldown_s." .. id end end
    for id in pairs(C.lead_s) do if not C.list[id] then bad[#bad + 1] = "lead_s." .. id end end
    local ne = 0
    for _ in pairs(events0) do ne = ne + 1 end
    check(#bad == 0, string.format("%d tells, %d radio events, every one named and textured right%s", n, ne,
        #bad > 0 and (": " .. table.concat(bad, "; ")) or ""))
    check(#C.list.clock.radio == 12 and C.list.clock.radio[6] == "RE_SV_RadioClockF", "the o'clock lines: 12, the 6th is ClockF")
    check(TELL.known("reversal") and not TELL.known("nosuch") and not TELL.known("re versal") and not TELL.known(("x"):rep(40)),
          "TELL.known: catalog ids only")
    check(TELL.leadS("alcn_rail") == 5 and TELL.leadS("nosuch") == 0 and TELL.leadS("hunt") == 0, "TELL.leadS: alcn_rail 5, others 0")
    local mods = readAll(MOD .. "/Scripts/main.lua")
    local a, b, c = mods:find('"sv_stats"', 1, true), mods:find('"sv_tells"', 1, true), mods:find('"sv_coop"', 1, true)
    check(a and b and c and a < b and b < c, "MODULES: sv_tells after sv_stats, before sv_coop")
end

---------------------------------------------------------------------------------------------------- the HUD's urgent path
print("the HUD (sv_hud.lua hudCallout / calloutNext)")
do
    callouts = {}
    H = {}
    hudCallout("ROUND 5", "HOSTILES INBOUND"); hudCallout("WAVE 2 OF 3", nil)
    hudCallout("ACE REVERSAL", "HE'S TURNING INTO YOU", nil, true)
    check(#callouts == 3 and callouts[1].text == "ACE REVERSAL" and callouts[1].urgent and callouts[2].text == "ROUND 5",
          "an urgent one goes in front of the queue")
    hudCallout("WARNING: RAILGUN", nil, nil, true)
    check(#callouts == 3 and callouts[1].text == "WARNING: RAILGUN" and count({ callouts[1].text, callouts[2].text, callouts[3].text }, "REVERSAL") == 0,
          "a newer tell takes the waiting one's place (one tell waits at a time)")
    hudCallout("A", nil); hudCallout("B", nil)
    check(#callouts == 4 and callouts[4].text == "A", "the queue stays at 4 (B dropped, as ever)")
    callouts = {}
    for _, t in ipairs({ "R1", "R2", "R3", "R4" }) do hudCallout(t, nil) end
    hudCallout("VLS LAUNCH", nil, nil, true)
    check(#callouts == 4 and callouts[1].text == "VLS LAUNCH" and callouts[4].text == "R3" and has(line("hud: callout"), "'R4' dropped for a tell"),
          "a full queue of callouts loses its last for a tell, logged")
    callouts = {}
    hudCallout("ROUND 5", nil)
    local c = calloutNext(10)
    check(c and c.text == "ROUND 5", "a free banner: the queue's first")
    H.calloutCur, H.calloutUntil = c, 14
    hudCallout("WAVE 2 OF 3", nil)
    check(calloutNext(11) == nil, "a busy banner: a callout waits")
    hudCallout("ACE REVERSAL", nil, nil, true)
    local t = calloutNext(11)
    check(t and t.urgent and H.calloutUntil == nil and callouts[1] == H.calloutCur and callouts[2].text == "WAVE 2 OF 3",
          "a tell cuts the banner short; the cut callout (3 s left) comes back right after it")
    H.calloutCur, H.calloutUntil = { text = "ROUND 6" }, 12
    callouts = {}
    hudCallout("ACE REVERSAL", nil, nil, true)
    calloutNext(11)
    check(#callouts == 0, "a callout with 1 s left isn't put back")
    H.calloutCur, H.calloutUntil = { text = "WARNING: RAILGUN", urgent = true }, 13
    hudCallout("VLS LAUNCH", nil, nil, true)
    check(calloutNext(11) == nil and #callouts == 1, "a tell never cuts another tell")
    callouts = {}
    H.calloutCur, H.calloutUntil = { text = "ROUND 7" }, 15
    for _, t in ipairs({ "W1", "W2", "W3" }) do hudCallout(t, nil) end
    hudCallout("ACE REVERSAL", nil, nil, true)
    local cut = calloutNext(11)
    check(cut and cut.urgent and #callouts == 3 and callouts[1].text == "ROUND 7" and callouts[3].text == "W2"
          and has(line("hud: callout 'W3'"), "dropped (a tell cut in)"), "the cut callout put back into a full queue: its last dropped, logged")
    local src = readAll(MOD .. "/Scripts/sv_hud.lua")
    check(has(src, "local c = calloutNext(now)") and has(src, "CFG.tells.hud_s") and has(src, "H.calloutCur, H.calloutUntil = c,"),
          "hudTick shows calloutNext's, a tell for hud_s")
    callouts, H = {}, nil
end

---------------------------------------------------------------------------------------------------- saying
print("TELL.say / TELL.play (solo)")
reset(); run0(10); callouts = {}; events = {}
math.randomseed(3)
do
    local ok = TELL.say("reversal")
    check(ok == true and (events[1] == "RE_SV_RadioTurnA" or events[1] == "RE_SV_RadioTurnB"), "reversal: one of its lines (" .. tostring(events[1]) .. ")")
    check(callouts[1] and callouts[1].text == "ACE REVERSAL" and callouts[1].sub == "HE'S TURNING INTO YOU" and callouts[1].urgent,
          "... and its callout, urgent")
    check(has(line("tell: reversal"), "(fired)") and has(line("tell: reversal"), "tell callout 'ACE REVERSAL'"), "... logged: " .. tostring(line("tell: reversal")))
    local s1 = events[1]
    local ok2, why, kind = TELL.say("kulbit")
    check(not ok2 and kind == "gap" and has(line("tell: kulbit not said"), "gap 2.5"), "an urgent one right after an urgent one: its gap (" .. tostring(why) .. ")")
    D.now = 102.5
    events = {}
    check(TELL.say("kulbit") == true and events[1] ~= nil and events[1] ~= s1,
          "... 2.5 s on: said, with the other line (reversal's asked for within line_gap_s; they share theirs)")
    D.now = 106
    local ok3, _, k3 = TELL.say("reversal")
    check(not ok3 and k3 == "cooldown", "reversal again 6 s on: its cooldown")
    D.now = 121
    events = {}
    check(TELL.say("reversal") and events[1] == s1, "21 s on: said, its own line again (the other is the kulbit's, 18.5 s ago: " .. tostring(events[1]) .. ")")
    -- classes
    events = {}
    check(not TELL.say("raid") and #events == 0, "a radio-only one right after a tell: its gap (radio_gap_s)")
    D.now = 123
    check(TELL.say("raid") and events[1]:match("^RE_SV_RadioRaid[ABC]$") ~= nil and has(line("tell: raid"), "RE_SV_RadioRaid"), "... 2 s on: a raid line")
    D.now = 130
    check(TELL.say("alcn_up") and TELL.say("alcn_rail") and callouts[1].text == "WARNING: RAILGUN",
          "an urgent one right after a radio-only one: said (the railgun's call the second 'submarine has surfaced' is)")
    D.now = 131
    check(TELL.say("hunt") and callouts[#callouts].text == "YOU ARE BEING HUNTED" and not callouts[#callouts].urgent, "a queued callout (hunt): its own gap, not the urgent ones'")
    D.now = 133
    local okR, _, kR = TELL.say("regroup")
    check(not okR and kR == "gap", "another queued callout 2 s later: gap_s 4")
    D.now = 135.5
    check(TELL.say("regroup") == true, "... 4.5 s later: said")
    -- pick, chain, texts
    D.now = 200; events = {}; callouts = {}
    check(TELL.say("clock", nil, 6) and events[1] == "RE_SV_RadioClockF", "clock 6: the 6th line (pick a)")
    D.now = 203; events = {}
    check(TELL.say("dive", nil, 3) and events[1]:match("^RE_SV_RadioDive[ABCD]$") and events[2] == "RE_SV_RadioClockC"
          and callouts[#callouts].sub == "HIGH, 3 O'CLOCK", "dive at 3 o'clock: a dive line, then ClockC; 'HIGH, 3 O'CLOCK'")
    D.now = 230
    check(TELL.say("pincer", nil, 90, 270) and callouts[#callouts].sub == "FROM THE EAST AND THE WEST", "pincer from 90 and 270: 'FROM THE EAST AND THE WEST'")
    D.now = 260; events = {}
    eventR = -5
    check(TELL.say("wave") and has(line("tell: wave"), "(not fired: " .. tostring(SV_ERR[-5])), "an event that didn't fire: logged with its error")
    eventR = 1
    -- when not
    D.now = 300; D.state = "wait"
    local okW, whyW = TELL.say("bracket")
    check(not okW and whyW == "between rounds", "between rounds: none")
    D.state = "fighting"; airfield = true
    check(not TELL.say("bracket") and has(line("tell: bracket not said"), "down at the airfield"), "down at the airfield: none")
    airfield = false; LB.show = {}
    check(not TELL.say("bracket"), "over the run's summary: none")
    LB.show = nil
    C.radio = false; events = {}
    local okE, _, kE = TELL.say("wave")
    D.now = 310
    check(not okE and kE == "empty" and TELL.say("bracket") and #events == 0 and callouts[1].text == "MISSILES FROM TWO SIDES",
          "radio off: a radio-only tell has nothing to show; others the callout only")
    C.radio, C.hud = true, false; callouts = {}; D.now = 330
    check(TELL.say("six") and #events == 1 and #callouts == 0, "hud off: the line only")
    C.enabled = false
    check(not TELL.say("six") and not TELL.ready("six"), "tells off: none")
    reset()
    D.now = 400
    check(TELL.ready("six") and not TELL.ready("nosuch"), "TELL.ready: a tell that could be said")
    TELL.say("six")
    check(not TELL.ready("six"), "... and not right after it")
    check(TELL.play("six", nil, nil, nil, true, "RE_SV_RadioSixC") and events[#events] == "RE_SV_RadioSixC", "TELL.play forced (Ctrl+0): that line, past the gaps")
end

print("line_gap_s (a radio line not asked for again within it, by any tell)")
do
    reset(); run0(10); events = {}; callouts = {}
    C.cooldown_s.reversal, C.cooldown_s.kulbit = 0, 0
    TELL.say("reversal")
    D.now = 103
    TELL.say("kulbit")
    check(count(events, "^RE_SV_RadioTurn[AB]$") == 2 and events[1] ~= events[2], "reversal, then kulbit 3 s on: both lines asked for")
    D.now = 106; events = {}; callouts = {}
    check(TELL.say("reversal") == true and #events == 0 and callouts[1] and callouts[1].text == "ACE REVERSAL"
          and has(line("tell: reversal"), "no line (each played within line_gap_s)"), "both within 20 s: its callout only, logged")
    C.hud = false; D.now = 109
    local ok, why, kind = TELL.say("kulbit")
    check(not ok and kind == "line" and has(line("tell: kulbit not said"), "line_gap_s 20"), "... no callout either: not said (" .. tostring(why) .. ")")
    C.hud = true
    D.now = 124
    events = {}
    check(TELL.say("kulbit") and events[1] ~= nil, "21 s after the first: a line again (" .. tostring(events[1]) .. ")")
    D.now = 130; eventR = -5
    TELL.say("clock", nil, 6)
    eventR = 1; D.now = 133; events = {}
    check(TELL.say("clock", nil, 6) and events[1] == "RE_SV_RadioClockF", "a line that didn't fire doesn't count (clock 6 again 3 s on)")
    D.now = 136; events = {}
    local okC, _, kC = TELL.say("clock", nil, 6)
    check(not okC and kC == "line" and #events == 0, "... once it fired: not again within 20 s (pick a; clock has no callout)")
    C.line_gap_s = 0; D.now = 139
    check(TELL.say("clock", nil, 6) and events[1] == "RE_SV_RadioClockF", "line_gap_s 0: no such limit")
end

---------------------------------------------------------------------------------------------------- the lead
print("TELL.after / TELL.tick (the lead)")
do
    reset(); run0(10); events = {}
    local ran = {}
    check(TELL.after("reversal", nil, function() ran[#ran + 1] = D.now end) == true and #ran == 0, "said: the action waits its lead")
    TELL.tick(100.75)
    check(#ran == 0, "... not after 0.75 s")
    D.now = 101; TELL.tick(101)
    check(#ran == 1, "... after 1 s (lead_s reversal 1.0)")
    check(TELL.after("kulbit", nil, function() ran[#ran + 1] = "k" end) == false and ran[2] == "k", "not said (its gap): at once")
    check(TELL.after("trap", nil, function() ran[#ran + 1] = "t" end, nil, nil, true) == false and #ran == 2, "need, not said: never")
    D.now = 200
    check(TELL.after("ladon_vls", nil, function() ran[#ran + 1] = "l" end) and ran[3] == "l", "lead 0: with the tell")
    TELL.after("hunt", nil, function() error("boom") end)
    check(has(line("tell: hunt's action"), "boom"), "a failing action is logged, not raised")
    C.enabled = false
    TELL.after("bracket", nil, function() ran[#ran + 1] = "b" end)
    check(ran[4] == "b" and TELL.leadS("bracket") == 0, "tells off: at once, lead 0")
    reset()
    D.now = 300
    TELL.after("six", nil, function() ran[#ran + 1] = "s" end)
    D = nil
    TELL.tick(305)
    check(#ran == 4, "a new run (D gone): the waiting action is dropped with it")
end

---------------------------------------------------------------------------------------------------- the wiring
print("the wiring")
do
    -- an ace's reversal and kulbit (sv_ai.lua ACE.movesTick)
    reset(); run0(30); events = {}; callouts = {}
    local reaper
    for _, t in ipairs(CFG.tiers.list) do if t.name:lower() == "reaper" then reaper = t end end
    local function plane(x, fwdX)
        local o = { addr = 0x500, loc = { X = x, Y = 0, Z = 300000 }, fwd = { X = fwdX, Y = 0, Z = 0 }, full = "BP_OP1022_su57_CP_C_7" }
        function o:K2_GetActorLocation() return self.loc end
        function o:GetActorForwardVector() return self.fwd end
        return o
    end
    local R = { obj = plane(150000, 1), name = "BP_OP1022_su57_CP_C_7", unit = "ERA_Unit_05_Dep_Air0", tier = reaper }
    planes = { R }
    ACE.movesTick(100, D)
    check(count(events, "^RE_SV_RadioTurn") == 1 and count(events, "^RE_SV_AceTurn") == 0 and callouts[1] and callouts[1].text == "ACE REVERSAL",
          "you on a Reaper's tail: its tell (" .. tostring(events[1]) .. ", ACE REVERSAL), the turn not yet")
    D.now = 101; TELL.tick(101)
    check(events[#events] == "RE_SV_AceTurn_13" and has(line("aces: "), "RE_SV_AceTurn_13 (1)"), "... RE_SV_AceTurn_13 1 s later, logged")
    D.aceMoveAt = {}; D.now = 125; events = {}
    R.obj.loc.X = 80000
    ACE.movesTick(125, D)
    check(count(events, "^RE_SV_RadioTurn") == 1 and callouts[1].text == "ACE POST-STALL", "within 900 m: the kulbit's tell")
    D.now = 125.5; TELL.tick(125.5)
    check(events[#events] == "RE_SV_AceKulbit_13", "... the kulbit 0.5 s later")
    CFG.tells.enabled = false; D.aceMoveAt = {}; events = {}
    ACE.movesTick(150, D)
    check(events[1] == "RE_SV_AceKulbit_13" and #events == 1, "tells off: the move at once, no line (as before)")
    reset()
    -- the hunt (sv_ai.lua ACE.hunt -> TELL.hunted)
    D.now = 200; callouts = {}; events = {}
    R.dist = 12
    pcall(ACE.hunt, R)
    check(count(events, "^RE_SV_RadioHunt") == 0, "a hunting flight 12 km out: no hunt tell yet")
    R.dist = 7
    pcall(ACE.hunt, R)
    check(count(events, "^RE_SV_RadioHunt") == 1 and callouts[#callouts].text == "YOU ARE BEING HUNTED", "within hunt_km 8: the hunt tell")
    local R2 = { obj = plane(0, 1), name = "x", unit = "ERA_Unit_06_Dep_Air0", tier = reaper, dist = 5 }
    D.now = 220
    pcall(ACE.hunt, R2)
    check(count(events, "^RE_SV_RadioHunt") == 1 and D.tellHunt[R2.unit] == D.round, "another flight within its cooldown: none, and marked done")
    D.now = 300
    pcall(ACE.hunt, R); pcall(ACE.hunt, R2)
    check(count(events, "^RE_SV_RadioHunt") == 1, "... once a flight a round")
    CFG.coop.enabled, COOP.open, COOP.role = true, true, "join"
    D.tellHunt = {}
    pcall(ACE.hunt, R)
    check(count(events, "^RE_SV_RadioHunt") == 1, "on a co-op joiner: none (the host's planes hunt the host)")
    CFG.coop.enabled, COOP.open, COOP.role = false, false, nil
    planes = {}

    -- the ALICORN (sv_alicorn.lua SPC.alicornTick)
    reset(); run0(10); events = {}; callouts = {}
    local s = { kind = "alicorn", state = "sail", at = 0, tanks = 4, coreOpen = false, dived = false, nextDive = 1000,
                nextRail = 100, nextVolley = 130 }
    D.special = s
    local at = {}
    local function upTo(t1)
        for t = math.floor(D.now) + 1, t1 do
            D.now = t
            local n0 = #events
            SPC.alicornTick(t, s); TELL.tick(t)
            for i = n0 + 1, #events do at[#at + 1] = { t, events[i] } end
        end
    end
    local function when(ev, from)
        for _, e in ipairs(at) do if e[2] == ev and e[1] >= (from or 0) then return e[1] end end
        return nil
    end
    D.now = 90
    upTo(140)
    check(when("RE_SV_RadioAlcnRailFirst") == 95 and when("RE_SV_AlcnAlertOn") == 95, "the railgun's first call and RAILGUN WARNING 5 s before the order (95)")
    check(when("RE_SV_AlcnRailgun") == 100 and when("RE_SV_AlcnAlertOff") == 112, "the order at 100 as before; the warning off 12 s after it (112)")
    check(has(line("special: the Alicorn's railgun in"), "5 s: warned"), "... logged")
    check(when("RE_SV_RadioAlcnVls") == 130 and when("RE_SV_AlcnVolley") == 131, "the VLS volley's call at 130, the volley 1 s after it")
    local rail = 0
    for _, l in ipairs(logs) do if l == "hud: tell 'WARNING: RAILGUN' / 'BUILD SPEED, THEN BREAK'" then rail = rail + 1 end end
    check(rail >= 1, "WARNING: RAILGUN / BUILD SPEED, THEN BREAK on the HUD")
    upTo(156)
    local second = when("RE_SV_RadioAlcnRailA", 140) or when("RE_SV_RadioAlcnRailB", 140)
    check(second == 155 and when("RE_SV_AlcnAlertOn", 140) == 155, "the next call (not 'activated' again) and warning at 155")
    s.nextDive = 157
    upTo(165)
    check(when("RE_SV_AlcnDive", 150) == 157 and when("RE_SV_RadioAlcnDive") == 157 and when("RE_SV_AlcnAlertOff", 150) == 157,
          "a dive: its call, and the warning off with it")
    check(when("RE_SV_AlcnRailgun", 150) == nil, "no railgun while dived")
    unitAlive = 0
    s.dived, s.nextRail, s.nextDive = false, 168, 1000
    upTo(170)
    local off = when("RE_SV_AlcnAlertOff", 158)
    check(s.state == "done" and when("RE_SV_AlcnAlertOn", 158) == 166 and off and off <= 168 and when("RE_SV_AlcnRailgun", 158) == nil,
          "warned at 166, then it sank: the warning off at the sink (" .. tostring(off) .. "), no order")
    unitAlive = 1
    -- rail_alert off: the call, no warning; tells off: the warning at the order
    s = { kind = "alicorn", state = "sail", at = 0, tanks = 4, nextDive = 1000, nextRail = 300, nextVolley = 1000 }
    D.special, D.now, at = s, 290, {}
    CFG.specials.alicorn.rail_alert.enabled = false
    upTo(300)
    check(when("RE_SV_RadioAlcnRailFirst") == 295 and when("RE_SV_AlcnAlertOn") == nil, "rail_alert off: the call, no RAILGUN WARNING")
    CFG.specials.alicorn.rail_alert.enabled = true
    CFG.tells.enabled = false
    s = { kind = "alicorn", state = "sail", at = 0, tanks = 4, nextDive = 1000, nextRail = 400, nextVolley = 1000 }
    D.special, D.now, at = s, 390, {}
    upTo(400)
    check(when("RE_SV_AlcnAlertOn") == 400 and when("RE_SV_AlcnRailgun") == 400 and not (when("RE_SV_RadioAlcnRailFirst")
          or when("RE_SV_RadioAlcnRailA") or when("RE_SV_RadioAlcnRailB")), "tells off: the warning with the order, no call")
    events = {}
    SPC.alicornCleanup(s); SPC.alicornCleanup(s); SPC.alicornCleanup({ kind = "ladon" })
    check(count(events, "^RE_SV_AlcnAlertOff$") == 1 and s.railAlertOn == nil and s.railOffAt == nil
          and has(line("special: the Alicorn's RAILGUN"), "off with the run"), "a run restarted with the warning up: off once (SPC.alicornCleanup)")
    local reset0 = readAll(MOD .. "/Scripts/sv_main.lua")
    check(has(reset0, "pcall(SPC.V.cleanup, D.special); pcall(SPC.alicornCleanup, D.special)"), "... called by the level-load reset")
    reset()

    -- a Ladon's volley (sv_ladon.lua SPC.ladonTick)
    D = { round = 15, state = "fighting", now = 500, up = {}, flown = {} }
    events, callouts = {}, {}
    local L = { obj = { HealthInternal = 12000, full = "ladon" }, unit = "SV_Unit_LadonKot", name = "ladon", dist = 5 }
    planes = { L }
    local ls = { kind = "ladon", state = "run", at = 480, units = { Kot = { unit = "SV_Unit_LadonKot", alive = true, runs = 0 } } }
    for t = 500, 512 do D.now = t; SPC.ladonTick(t, ls); ls.nextAt = nil; TELL.tick(t) end
    check(count(events, "^RE_SV_RadioLadonVls") == 1 and count(events, "^RE_SV_LadonVolleyKot") == 1, "a Ladon's volley: its call and the volley")
    local iT, iV
    for i, e in ipairs(events) do if e:match("RadioLadonVls") then iT = i elseif e:match("LadonVolleyKot") then iV = i end end
    check(iT and iV and iT < iV and has(line("special: Ladon"), "fires a launcher"), "... the call first (lead 0: the same tick), the volley logged")
    planes = {}

    -- the rest, by their place in the source
    local function body(file, from)
        local src = readAll(MOD .. "/Scripts/" .. file)
        local a = src:find(from)
        local b = a and src:find("\nend\r?\n", a + 1)
        return a and src:sub(a, b or #src) or ""
    end
    local sb = body("sv_spawn.lua", "\nlocal function spawnBomber%(unit%)")
    check(has(sb, 'pcall(TELL.say, "raid", TELL.ALL)') and sb:find("t.raid_sub", 1, true) < sb:find('"raid", TELL.ALL', 1, true),
          "spawnBomber: the raid's call to every player after its callout")
    local sf = body("sv_spawn.lua", "\nfunction spawnFlight%(unit, maxLevel%)")
    check(has(sf, 'pcall(TELL.say, "jammer", TELL.ALL)'), "spawnFlight: the jammer's call")
    check(has(body("sv_main.lua", "\nlocal function creditKill%(p%)"), 'pcall(TELL.say, "jammer_down", TELL.ALL)'), "creditKill: the jammer down")
    local rt = body("sv_rounds.lua", "\nfunction roundsTick%(now%)")
    check(has(rt, 'pcall(TELL.say, "wave", TELL.ALL)') and has(rt, "CFG.tells.wave_from_round"), "roundsTick's next wave: the late rounds' call")
    local pt = body("sv_main.lua", "\nlocal function probeTick%(tick%)")
    check(has(pt, 'timed("tells", TELL.tick, now)'), "probeTick: TELL.tick every 250 ms, timed")
    local mainSrc = readAll(MOD .. "/Scripts/sv_main.lua")
    local k0, inside = mainSrc:find("Key.ZERO", 1, true), false
    if k0 then
        local before = mainSrc:sub(1, k0)
        local lastB, lastE = 0, 0
        for p in before:gmatch("()TEST ONLY BEGIN") do lastB = p end
        for p in before:gmatch("()TEST ONLY END") do lastE = p end
        inside = lastB > lastE and mainSrc:find("TEST ONLY END", k0, true) ~= nil
    end
    check(inside, "Ctrl+0 (every line in turn) inside a TEST ONLY block")
end

---------------------------------------------------------------------------------------------------- co-op
print("co-op")
do
    reset()
    CFG.coop.enabled = true
    menu = 16 + 3
    D = { round = 12, state = "fighting", now = 600, up = {}, flown = {} }
    COOP.tick(1)
    check(COOP.host(), "hosting")
    check(hudCallout ~= hudRaw and mirroredEvent("RE_SV_RadioTurnA") == false and mirroredEvent("RE_SV_AlcnAlertOn") == true,
          "sv_coop wrapped hudCallout; RE_SV_Radio* kept, the railgun warning forwarded")
    sent, events, callouts = {}, {}, {}
    roundsBody = function() TELL.say("hunt"); hudCallout("ROUND 12", nil); SV_Event("RE_SV_AlcnAlertOn") end
    roundsTick(600)
    check(count(sent, "co|YOU ARE BEING HUNTED") == 0 and count(sent, "co|ROUND 12") == 1, "a tell inside the host's rounds: no \"co\" (a round callout still goes)")
    check(count(sent, "ev|RE_SV_Radio") == 0 and count(sent, "ev|RE_SV_AlcnAlertOn") == 1, "... its line no \"ev\" (the railgun warning still goes)")
    roundsBody = nil
    sent = {}
    D.now = 610
    check(TELL.say("raid", TELL.ALL) and count(events, "^RE_SV_RadioRaid") >= 1 and sent[#sent] == "-1>tl|raid||", "TELL.ALL: played here and \"tl\" to every joiner")
    sent = {}
    D.now = 611
    local nE = #events
    check(TELL.say("six", 2) == true and sent[1] == "2>tl|six||" and #events == nE, "a slot's tell: \"tl\" to player 3 only, nothing here")
    local okS, _, kS = TELL.say("six", 2)
    check(not okS and (kS == "gap" or kS == "cooldown") and #sent == 1, "... its own gaps on the host (again at once: none)")
    D.now = 640
    check(TELL.say("dive", 2, 4) and sent[#sent] == "2>tl|dive|4|", "numbers go along (dive at 4 o'clock)")
    D.now = 660
    check(TELL.say("pincer", 1, 0 / 0) and sent[#sent] == "1>tl|pincer||", "a non-finite number isn't sent")
    check(COOP.tell(99, "six") == false and COOP.tell(nil, nil) == false, "COOP.tell: a bad slot or id sends nothing")
    hudCallout("TEST", nil, nil, true)
    check(callouts[1] and callouts[1].urgent, "the wrapped hudCallout passes urgent on")
    -- the host's own tells off: its joiners still get theirs (PERSONAL), with the host's leads
    C.enabled = false
    sent, events, callouts = {}, {}, {}
    D.now = 680
    check(TELL.say("jammer", TELL.ALL) == true and sent[#sent] == "-1>tl|jammer||" and #events == 0,
          "the host's tells off: TELL.ALL not played here, still sent to every joiner")
    check(TELL.say("bracket", 3) == true and sent[#sent] == "3>tl|bracket||" and #callouts == 0, "... and a slot's tell sent")
    check(TELL.leadS("alcn_rail") == 5 and TELL.ready("six", 4) and not TELL.ready("six") and TELL.ready("six", TELL.ALL),
          "... its leads stand; ready for a joiner, not for itself")
    local ranV
    D.now = 683
    check(TELL.after("alcn_vls", TELL.ALL, function() ranV = D.now end) == true and ranV == nil, "... a TELL.ALL action waits its lead")
    D.now = 684; TELL.tick(684)
    check(ranV == 684 and #events == 0, "... 1 s on (lead_s alcn_vls), nothing played here")
    C.enabled = true

    -- the joiner
    menu = 32 + 4
    COOP.tick(2)
    check(COOP.client(), "joined")
    D = { round = 12, state = "fighting", now = 700, up = {}, flown = {} }
    M.readyAt = nil
    events, callouts, sent = {}, {}, {}
    inbox[#inbox + 1] = "0|tl|reversal||"
    COOP.tick(3)
    local cos = {}
    for _, c in ipairs(callouts) do cos[#cos + 1] = c.text end
    check(count(events, "^RE_SV_Radio") == 0 and count(cos, "ACE REVERSAL") == 0, "a tell while this level is still loading: dropped")
    clock = clock + 4
    inbox[#inbox + 1] = "0|tl|reversal||"
    COOP.tick(4)
    check(count(events, "^RE_SV_RadioTurn") == 1 and callouts[1] and callouts[1].text == "ACE REVERSAL" and has(line("tell: reversal (the host's)"), "RE_SV_RadioTurn"),
          "the host's reversal played here, from this game's catalog")
    check(count(sent, "ev|") == 0 and count(sent, "co|") == 0, "... nothing sent back")
    D.now = 710; clock = clock + 2
    for _, m in ipairs({ "0|tl|nosuch||", "0|tl|dive|1e999|", "0|tl|" .. ("a"):rep(80) .. "||", "0|tl|hunt|nan|" }) do inbox[#inbox + 1] = m end
    local plays = 0
    local realPlay = TELL.play
    TELL.play = function(...) plays = plays + 1; return realPlay(...) end
    COOP.tick(5)
    check(plays == 1, "unknown ids, a huge number, a long id dropped; 'nan' (no number) plays as none (" .. plays .. " played)")
    plays = 0; clock = clock + 2
    for _ = 1, 7 do inbox[#inbox + 1] = "0|tl|wave||" end
    COOP.tick(6)
    check(plays == 4, "at most 4 a second (" .. plays .. ")")
    plays = 0; clock = clock + 2
    CFG.coop.callouts = false
    inbox[#inbox + 1] = "0|tl|wave||"
    COOP.tick(7)
    check(plays == 0, "callouts off ([coop] callouts): none")
    CFG.coop.callouts = true
    CFG.tells.enabled = false; clock = clock + 2
    local nJ = #events
    inbox[#inbox + 1] = "0|tl|raid||"
    COOP.tick(7)
    check(#events == nJ and not has(line("tell: raid (the host's)"), "RadioRaid"), "this game's own tells off: the host's not played")
    CFG.tells.enabled = true; plays = 0
    D.state = "wait"; D.now = 760; clock = clock + 2
    inbox[#inbox + 1] = "0|tl|bracket||"
    COOP.tick(8)
    check(plays == 1 and callouts[1].text == "MISSILES FROM TWO SIDES", "the host's tell while this game still shows the break: played (the host's round)")
    TELL.play = realPlay
    D.state = "fighting"; D.now = 800
    check(TELL.say("six", 5) == false and TELL.say("raid", TELL.ALL) and count(sent, "tl|") == 0, "a joiner tells no one else (TELL.ALL: its own game only)")
end

logFile:close()
print(fails == 0 and "tells test: all passed" or ("tells test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
