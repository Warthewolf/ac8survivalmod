-- director_test.lua <mod dir> <work dir> (run by tools/checks/director_test.sh): the behaviour roadmap's P2, the squad
-- director (tools/re/BEHAVIOUR_DIRECTOR.md unit 6), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn,
-- sv_rounds, sv_tactical, sv_stats, sv_tells, sv_director and sv_coop (M and mirroredEvent exposed), the game stubbed,
-- planes stubbed as objects with a position and a heading:
--   survival.ini's [director] sections; the budgets by round band and the habit counter's factor;
--   each tactic's trigger: its geometry, its tell first and its action lead_s later (TELL.tick), its budget, cooldown
--     and the director's gap, what it leaves alone:
--     cover (you on a plane's tail 3 s: the nearest other duelist flight's RE_SV_AceTurn_NN; never a Lancer's or an
--       escort's; cover_ask at 1.5 s; tells off: at once; grounded, a boss round, off, a joiner: nothing),
--     the trap (you on a Wolf bait's tail: drag at 1 s, the trap's free and turn on its own wingman at 2.5 s; not in your
--       decoy),
--     the bracket (two noses on you 60-120 deg apart within 4 km: both RE_SV_Salvo_<NN><L> a lead after the tell; not
--       30 deg apart, not a row whose missiles aren't in slot 2, not a held flight's, not with no budget),
--     top cover (a Lancer flight held once its orders are in, its dive with the o'clock once you've fought another
--       flight; let go when hit, as the last flight up but held ones in any round state (not while a wave still spawns;
--       two held flights: one let go), at max_s, at your decoy's end with its orders (a dive inside your decoy waits for
--       its end); roles off: any flight),
--     the pincer (a wave's flights alternating on two bearings around you, noses on you, its tell once both sides have
--       a flight; tagged and counted once they're up, a flight that fell back to a normal point left out; one side only:
--       no pincer, its budget back; not a special's or a raid's wave; co-op: around the airfield; the zone's edge),
--     regroup (a 4-ship down to 2: the tell, held hold_s, back; not the only flight up);
--   the aces' own reversal: its flight's next move no sooner than lead_s + cover.move_s (the kulbit's 12 s);
--   the fresh reads a tick (at most `reads`, a plane you're likely on the tail of first; shared with the tail watch);
--   SR.mslSlot from the real searchSetup on fake tables;
--   co-op: a joiner's bracket by "dv" (and its tell by "tl"), a joiner's cover (the hunt, its TargetActor kept on the
--     stand-in, ACE.hunt leaving it, the orders back after aim_s; inside your decoy: at its end), the split hunt waiting
--     out a hold however long it lasts and given back after it (COOP.hunted), the holds in force sent to a joiner who
--     links later (and not one let go meanwhile), KEEP_EVENTS, and the joiner's "dv" guards (names, its flight, a live
--     copy, the delay, the rate, a level still loading, "rs");
--   the hooks in sv_main, sv_rounds, sv_spawn, sv_allies, sv_ai and main.lua by their place in the source.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local defaultIni = readAll(MOD .. "/config/survival.default.ini")
writeAll(WORK .. "/config/survival.default.ini", defaultIni)
writeAll(WORK .. "/config/survival.ini", defaultIni ..
    "\r\n[director]\r\ngap_s = 4\r\nskip_specials = anomaly, valka\r\n[director.budget]\r\nbracket = 0, 2, 1, 2\r\n" ..
    "[director.pincer]\r\nsep_deg = 100, 140\r\n[director.trap]\r\nwarn = lure\r\n")

local clock = 1000                               -- (co-op's levelReady and rate limits)
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.71.5-director.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
local OBJ = {}
function StaticFindObject(p) return OBJ[p] end
local grounded = false
function playerOnAirfield() return grounded end
function airfieldTick() end
function bombTick() end
local events, eventR = {}, 1
function SV_Event(name) events[#events + 1] = name; return eventR end
local alive = {}
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
local spawns = {}
function SV_Spawn(unit, x, y, z, yaw) spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw }; return flightSize(unit) end
function SV_MenuChoice() return 0 end            -- (co-op as each test sets it)
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
local sent, inbox = {}, {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/p" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt() return "" end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

-- the real parts (sv_core's SCRIPT_DIR and log file in the work folder)
local function part(name, chunk, edits)
    local src = readAll(MOD .. "/Scripts/" .. name)
    for _, e in ipairs(edits or {}) do
        local n
        src, n = src:gsub(e[1], e[2], 1)
        assert(n == 1, name .. ": " .. e[1] .. " not found")
    end
    assert(load(src, chunk or ("=" .. name)))()
end
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
part("sv_config.lua")
local cfgLine = nil
for _, l in ipairs(logs) do if l:find("^config: survival%.ini") then cfgLine = l end end
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_tactical.lua"); part("sv_stats.lua"); part("sv_tells.lua"); part("sv_director.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" }, { "\nlocal function mirroredEvent%(name%)", "\nfunction mirroredEvent(name)" } })
local M = _G.M
function playerOnAirfield() return grounded end      -- (sv_rounds.lua's own reads the pawn)
LB.stat, LB.special = function() end, function() end
presetName = function() return "standard", 3 end
local FLAGS = {}
svFlags = function() return FLAGS end
ROLE.live = { duelist = true, lancer = true, wolf = true, skirm = true }
math.randomseed(11)

local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function evs(pat) local t = {}; for _, e in ipairs(events) do if e:find(pat) then t[#t + 1] = e end end; return table.concat(t, ",") end
local function deep(t) if type(t) ~= "table" then return t end; local c = {}; for k, v in pairs(t) do c[k] = deep(v) end; return c end

-- you (the pawn) and the planes (cm; KM(x, y) a point x km east, y km "south" (+Y), 3 km up)
local you, youFwd = { X = 0, Y = 0, Z = 300000 }, { X = 1, Y = 0, Z = 0 }
local pawn = { full = "BP_PlayerPlane_PP1000_f16c_C_1", addr = 9, MaxHealth = 100, HealthInternal = 800 }
function pawn:K2_GetActorLocation() return { X = you.X, Y = you.Y, Z = you.Z } end
function pawn:GetActorForwardVector() return { X = youFwd.X, Y = youFwd.Y, Z = youFwd.Z } end
survivalPC = { Pawn = pawn }
local function KM(x, y, z) return { X = x * 100000, Y = y * 100000, Z = (z or 3) * 100000 } end
local function DIRV(x, y, z) local l = math.sqrt(x * x + y * y + (z or 0) ^ 2); return { X = x / l, Y = y / l, Z = (z or 0) / l } end
local READS, nextAddr = 0, 100
local function mkObj(name, at, fwd)
    nextAddr = nextAddr + 1
    local o = { full = name, addr = nextAddr, at = at, fwd = fwd, HealthInternal = 1000 }
    function o:K2_GetActorLocation() READS = READS + 1; return { X = self.at.X, Y = self.at.Y, Z = self.at.Z } end
    function o:GetActorForwardVector() return { X = self.fwd.X, Y = self.fwd.Y, Z = self.fwd.Z } end
    o.AIStateComponent = { BlackboardComponent = {
        SetValueAsObject = function(_, k, v) o.tgt, o.tgtKey = v, tostring(k) end,
        GetValueAsObject = function() return o.tgt end } }
    return o
end
local function plane(unit, k, at, fwd)
    local name = string.format("BP_OP1022_f16c_C_%d", nextAddr + 1)
    local o = mkObj(name, at, fwd)
    local p = { obj = o, name = name, unit = unit, k = k, at = { X = at.X, Y = at.Y, Z = at.Z }, fwd = fwd, born = 0,
                tier = CFG.tiers.list[3] }
    planes[#planes + 1] = p
    alive[unit] = (alive[unit] or 0) + 1
    return p
end
local function move(p, at, fwd)                  -- (the plane and the sweep's last sample of it)
    p.obj.at, p.at = at, { X = at.X, Y = at.Y, Z = at.Z }
    if fwd then p.obj.fwd, p.fwd = fwd, fwd end
end
local function fresh(round, state)
    planes, alive, events, spawns, sent, callouts = {}, {}, {}, {}, {}, {}
    D = { round = round, state = state or "fighting", now = 99, up = {}, flown = {}, queue = {}, spare = {}, events = {} }
    you, youFwd, grounded = { X = 0, Y = 0, Z = 300000 }, { X = 1, Y = 0, Z = 0 }, false
    COOP.open, COOP.role, COOP.slot = false, nil, nil
    DIR.roundStart(99)
end
local function tickTo(t0, t1)                    -- the director and the tells' actions, every 250 ms from t0 to t1
    local n = math.floor((t1 - t0) / 0.25 + 0.5)
    for i = 0, n do
        local t = t0 + i * 0.25
        D.now = t
        DIR.tick(t, false)
        TELL.tick(t)
    end
end

---------------------------------------------------------------------------------------------------- survival.ini
print("survival.ini's [director]")
local DEF = CFG_DEFAULTS.director
check(cfgLine and not has(cfgLine, "not used"), "config: every line used (" .. tostring(cfgLine) .. ")")
check(CFG.director.gap_s == 4 and CFG.director.skip_specials[2] == "valka" and #CFG.director.skip_specials == 2
      and CFG.director.budget.bracket[2] == 2 and CFG.director.pincer.sep_deg[1] == 100 and CFG.director.trap.warn == "lure",
      "[director] gap_s / skip_specials, [director.budget] bracket, [director.pincer] sep_deg, [director.trap] warn read")
check(DEF.enabled and DEF.need_tell and DEF.cover.enabled and DEF.trap.enabled and DEF.bracket.enabled and DEF.top_cover.enabled
      and DEF.pincer.enabled and DEF.regroup.enabled, "every tactic has an enabled switch, on as shipped")
CFG.director = deep(DEF)

---------------------------------------------------------------------------------------------------- budgets
print("budgets by round band")
local from = #logs + 1
fresh(3)
check(has(line("director: round 3's budgets", from), "(from round 1): cover 1, trap 1, bracket 0, top_cover 0, pincer 0, regroup 0"),
      "round 3: cover 1, trap 1, the rest 0")
fresh(12)
check(has(line("director: round 12's budgets"), "(from round 10): cover 2, trap 2, bracket 1, top_cover 1, pincer 1, regroup 1"),
      "round 12: the band from round 10")
D.counter = { tail = 0.5 }
DIR.roundStart(99)
check(has(line("director: round 12's budgets"), "cover 3, trap 3, bracket 1") and has(line("director: round 12's budgets"), "x1.50 (your tail chasing)"),
      "P6's tail counter (D.counter.tail 0.5): cover and trap x1.5")

---------------------------------------------------------------------------------------------------- cover
print("cover the tailed")
local A, Q, L, E = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air1", "ERA_Unit_03_Dep_Air0", "ERA_Unit_01_Dep_Air2"
local function coverScene(round)
    fresh(round or 3)
    local p = plane(A, 0, KM(1, 0), DIRV(1, 0))                -- 1 km ahead of you, flying away: you're on its tail
    local l = plane(L, 0, KM(0, 2), DIRV(0, -1))               -- a Lancer 2 km off: never the cover (its role)
    local e = plane(E, 0, KM(0, -2.5), DIRV(0, 1))             -- an escort 2.5 km off: never (its area's on the airfield)
    local q = plane(Q, 0, KM(0, 3), DIRV(0, -1))               -- a duelist 3 km off: the cover
    D.escortUnits = { [E] = true }
    D.up = { [A] = true, [L] = true, [E] = true, [Q] = true }
    return p, l, e, q
end
local p, _, _, q = coverScene()
from = #logs + 1
tickTo(100, 101.25)
check(evs("^RE_SV_Radio") == "", "1.25 s on its tail: nothing yet")
tickTo(101.5, 101.5)
check(evs("^RE_SV_RadioEnCover") ~= "", "1.5 s: the tailed one calls for help (cover_ask: " .. evs("^RE_SV_Radio") .. ")")
tickTo(101.75, 102.75)
check(evs("^RE_SV_RadioSix") == "" and evs("^RE_SV_Ace") == "", "... nothing more before 3 s")
tickTo(103, 103)
check(evs("^RE_SV_RadioSix") ~= "" and evs("^RE_SV_Ace") == "" and has(line("tell: six", from), "BANDIT CUTTING IN"),
      "3 s: the six tell (BANDIT CUTTING IN), the turn not yet")
check(has(line("director: round 3", from), "cover on ERA_Unit_02_Dep_Air1 (1 planes)") and has(line("director: round 3", from), 'callout "six"'),
      "... counted and logged by STATS.tactic, its callout")
tickTo(103.25, 103.75)
check(evs("^RE_SV_Ace") == "", "... nor 0.75 s on")
tickTo(104, 104)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05" and has(line("director: cover: RE_SV_AceTurn_05"), "fired"),
      "lead_s (1 s) after its tell: the duelist flight's reversal, RE_SV_AceTurn_05 (not the Lancer's, not the escort's)")
check(type(q.dirTag) == "table" and q.dirTag.tactic == "cover" and q.dirTag.at == 103 and p.dirTag == nil,
      "the covering plane tagged { tactic = cover, at }, the tailed one not")
check(D.aceMoveAt[Q] == 103 + 1 + 30, "its flight's next reversal no sooner than move_s after the turn (D.aceMoveAt, shared with the aces')")
from = #logs + 1
tickTo(104.25, 120)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05" and has(line("director: cover not now", from), "its budget, 1 of 1 this round"),
      "still on its tail: no second cover (its budget, logged once)")
check(since(from, "^director: cover not now") == 1, "... logged once a round")
-- round 12 (budget 2): the cooldown, then the next one
p, _, _, q = coverScene(12)
tickTo(100, 104)
D.aceMoveAt[Q] = 0                                     -- (as if its reversal were over: the director's own cooldown counts)
from = #logs + 1
tickTo(104.25, 132.75)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05" and has(line("director: cover not now", from), "its cooldown"),
      "round 12: a second cover waits out its cooldown (30 s)")
tickTo(133, 136)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05,RE_SV_AceTurn_05", "... and comes after it")
-- the director's gap between tactics
coverScene(12)
D.dir.lastAt = 101
from = #logs + 1
tickTo(100, 104.75)
check(evs("^RE_SV_Ace") == "" and has(line("director: cover not now", from), "the director's gap"), "within gap_s of another tactic: not yet")
-- no cover: grounded, a boss round, off, a joiner, nobody to cover, tells off (at once)
coverScene(); grounded = true; tickTo(100, 106)
check(evs("^RE_SV_") == "", "you down at the airfield: nothing")
coverScene(); D.special = { kind = "anomaly" }; tickTo(100, 106)
check(evs("^RE_SV_") == "", "an Anomaly round (skip_specials): nothing")
coverScene(); CFG.director.enabled = false; tickTo(100, 106); CFG.director.enabled = true
check(evs("^RE_SV_") == "", "[director] enabled = false: nothing")
coverScene(); CFG.director.cover.enabled = false; tickTo(100, 106); CFG.director.cover.enabled = true
check(evs("^RE_SV_") == "", "[director.cover] enabled = false: nothing")
coverScene(); COOP.open, COOP.role = true, "join"; tickTo(100, 106); COOP.open, COOP.role = false, nil
check(evs("^RE_SV_") == "", "a co-op joiner: nothing (the host directs)")
_, _, _, q = coverScene(); move(q, KM(0, 7)); from = #logs + 1; tickTo(100, 106)
check(evs("^RE_SV_Ace") == "" and has(line("director: cover not now", from), "no flight within 6 km"), "no duelist within range_km: no cover (logged)")
coverScene(); CFG.tells.enabled = false; tickTo(100, 103)
check(evs("^RE_SV_Ace") == "RE_SV_AceTurn_05" and evs("^RE_SV_Radio") == "", "tells off here: the cover at 3 s, without a tell")
CFG.tells.enabled = true

---------------------------------------------------------------------------------------------------- the reads
print("fresh reads a tick")
fresh(3)
for i = 1, 20 do plane("ERA_Unit_02_Dep_Air2", i % 6, KM(0.5 + i * 0.05, -1), DIRV(0, 1)) end   -- (1.1-1.7 km off, coming at you)
local far = plane(A, 0, KM(2.9, 0.1), DIRV(1, 0))               -- you on its tail, nearly 3 km: 20 planes nearer
D.now = 100
READS = 0
DIR.tick(100, false)
check(READS == CFG.director.reads, "21 planes near you: " .. READS .. " fresh reads (reads = " .. CFG.director.reads .. ")")
check(far.pose and far.pose.t == 100 and far.dirTail ~= nil, "... the one you're likely on the tail of read first (the sweep's heading)")
READS = 0
STATS.tailTick(100)
check(READS == 0, "the tail watch reuses this tick's reads (p.pose): no read of its own")

---------------------------------------------------------------------------------------------------- the trap
print("spring the trap")
local W = "ERA_Unit_05_Dep_Air1"                          -- a Wolf 4-ship, pool 14
local function trapScene()
    fresh(3)
    local b = plane(W, 0, KM(1, 0), DIRV(1, 0))           -- bait A ahead of you
    local w1 = plane(W, 1, KM(-3, 4), DIRV(1, 0))         -- its held wingman B, off to the side
    plane(W, 2, KM(-4, 5), DIRV(1, 0)); plane(W, 3, KM(-4, 6), DIRV(1, 0))
    D.wolf = { [W] = { state = "held", held = { [1] = true, [3] = true }, keys = { 1, 3 }, at = 0, heldAt = 99 } }
    D.up = { [W] = true }
    return b, w1
end
trapScene()
CFG.director.trap.warn = "drag"
from = #logs + 1
tickTo(100, 100.75)
check(evs("^RE_SV_") == "", "0.75 s on the bait's tail: nothing")
tickTo(101, 101)
check(evs("^RE_SV_RadioDrag") ~= "" and has(line("tell: drag", from), "HE'S DRAGGING YOU"), "1 s: \"he's dragging you\" (trap.warn)")
tickTo(101.25, 102.25)
check(evs("^RE_SV_Wolf") == "", "... the trap not before 2.5 s")
tickTo(102.5, 102.5)
check(evs("^RE_SV_RadioTrap") ~= "" or evs("^RE_SV_RadioEnTrap") ~= "", "2.5 s: the trap tell")
check(has(line("director: round 3", from), "trap on ERA_Unit_05_Dep_Air1") and has(line("director: round 3", from), "its wingman B springs"),
      "... counted (STATS.tactic trap: bait A, wingman B)")
tickTo(102.75, 103.5)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfFree_14B,RE_SV_WolfTurn_14B" and D.wolf[W].held[1] == nil and D.wolf[W].held[3] == true,
      "lead_s after: its own wingman B freed and turned onto you (WOLF.free), D still held")
check(evs("^RE_SV_Ace") == "", "... and the bait isn't covered by another flight instead")
trapScene()
D.decoyed = { [W] = 200 }
tickTo(100, 106)
check(evs("^RE_SV_") == "", "inside your decoy on the Wolf flight: no drag, no spring")

---------------------------------------------------------------------------------------------------- the bracket
print("the bracket salvo")
local B1, B2 = "ERA_Unit_01_Dep_Air1", "ERA_Unit_02_Dep_Air0"          -- pool 02, 04
local function bracketScene(round, sepDeg)
    fresh(round or 6)
    D.flightRow = { [B1] = "f16c_common_sv", [B2] = "su33_common_svb" }
    SR.mslSlot = { f16c_common_sv = 2, su33_common_svb = 2 }
    local r = math.rad(sepDeg or 90)
    local a = plane(B1, 0, KM(3, 0), DIRV(-1, 0))                        -- 3 km ahead, its nose on you
    local b = plane(B2, 1, KM(3 * math.cos(r), 3 * math.sin(r)), DIRV(-math.cos(r), -math.sin(r)))   -- sepDeg round, nose on you
    D.up = { [B1] = true, [B2] = true }
    return a, b
end
local a, b = bracketScene()
from = #logs + 1
tickTo(100, 100)
check(evs("^RE_SV_RadioBracket") ~= "" and evs("^RE_SV_Salvo") == "" and has(line("tell: bracket", from), "MISSILES FROM TWO SIDES"),
      "two noses on you 90 deg apart within 4 km: the bracket tell first (MISSILES FROM TWO SIDES)")
tickTo(100.25, 100.75)
check(evs("^RE_SV_Salvo") == "", "... no shot within its lead")
tickTo(101, 101)
check(evs("^RE_SV_Salvo") == "RE_SV_Salvo_02A,RE_SV_Salvo_04B" and has(line("director: bracket: "), "RE_SV_Salvo_02A fired, RE_SV_Salvo_04B fired"),
      "1 s on: both shots in the same tick (RE_SV_Salvo_02A, _04B: pool index, then the plane's letter)")
check(a.dirTag and a.dirTag.tactic == "bracket" and b.dirTag == a.dirTag and has(line("director: round 6", from), "bracket on the round"),
      "both shooters tagged, the tactic counted")
tickTo(101.25, 140)
check(evs("^RE_SV_Salvo") == "RE_SV_Salvo_02A,RE_SV_Salvo_04B" and has(line("director: bracket not now", from), "its budget, 1 of 1"),
      "round 6's budget 1: no second (logged once)")
bracketScene(6, 30); tickTo(100, 102)
check(evs("^RE_SV_") == "", "30 deg apart: no bracket")
bracketScene(6, 150); tickTo(100, 102)
check(evs("^RE_SV_") == "", "150 deg apart: none either (sep_deg 60-120)")
a = bracketScene(); move(a, a.at, DIRV(1, 0)); tickTo(100, 102)
check(evs("^RE_SV_Salvo") == "", "one nose away from you: none")
bracketScene(); SR.mslSlot.su33_common_svb = 3; tickTo(100, 102)
check(evs("^RE_SV_Salvo") == "", "a row whose missiles aren't in slot 2: never fired")
bracketScene(); D.dir.held[B2] = { kind = "top", at = 99, dmg = 0 }; tickTo(100, 102)
check(evs("^RE_SV_Salvo") == "", "a flight the director holds: never a shooter")
from = #logs + 1
bracketScene(3); tickTo(100, 102)
check(evs("^RE_SV_") == "" and since(from, "^director: bracket") == 0, "round 3 (bracket budget 0): none, and no log of it")

---------------------------------------------------------------------------------------------------- top cover
print("top cover")
local F = "ERA_Unit_01_Dep_Air0"
local function topScene(round)
    fresh(round or 6)
    FLAGS = { SV_Up_07 = 1, SV_Up_01 = 1 }
    local l1 = plane(L, 0, KM(0, 8, 5), DIRV(0, -1))           -- the Lancers 8 km off your right wing, high
    plane(L, 1, KM(0.3, 8.2, 5), DIRV(0, -1))
    local f1 = plane(F, 0, KM(12, 0), DIRV(-1, 0))             -- another flight 12 km ahead
    D.up = { [L] = true, [F] = true }
    D.now = 200
    DIR.spawned(L, "lancer", 2)
    DIR.spawned(F, "duelist", 2)
    return l1, f1
end
local l1, f1 = topScene()
from = #logs + 1
tickTo(200, 202.75)
check(evs("^RE_SV_Dir") == "", "no hold before hold_after_s (3 s) after its orders are seen in")
tickTo(203, 203)
check(evs("^RE_SV_Dir") == "RE_SV_DirHold_07" and DIR.holding(L) and has(line("director: top cover: ERA_Unit_03_Dep_Air0", from), "held at engagement None"),
      "3 s on: the Lancer flight held (RE_SV_DirHold_07), DIR.holding")
check(not DIR.holding(F), "... the duelist flight not (top_cover.roles = lancer)")
move(f1, KM(2, 0), DIRV(-1, 0))                                -- you're in a fight with the other flight from 205
tickTo(203.25, 210.75)
check(evs("^RE_SV_DirFree") == "" and evs("^RE_SV_RadioDive") == "", "held under min_s (8 s): no dive yet")
tickTo(211, 211)
check(evs("^RE_SV_RadioDive") ~= "" and evs("^RE_SV_RadioClockC") ~= "" and has(line("hud: tell 'BANDIT DIVING'", from), "HIGH, 3 O'CLOCK"),
      "8 s held, you 3+ s in another fight: the dive tell, \"high, 3 o'clock\" (they're off your right wing) and its o'clock line")
check(has(line("director: round 6", from), "top_cover on ERA_Unit_03_Dep_Air0") and has(line("director: round 6", from), "3 o'clock"),
      "... counted (STATS.tactic top_cover)")
tickTo(211.25, 212)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_07" and not DIR.holding(L), "lead_s after: RE_SV_DirFree_07, let go")
check(l1.dirTag and l1.dirTag.tactic == "top_cover", "its planes tagged")
-- let go quietly
l1 = topScene(); tickTo(200, 203); l1.dmg = { you = 40 }; from = #logs + 1; tickTo(203.25, 205)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_07" and has(line("director: ERA_Unit_03_Dep_Air0 back in the fight", from), "you hit it"),
      "hit while held: let go at once, no dive")
_, f1 = topScene(); tickTo(200, 203); f1.down = true; from = #logs + 1; tickTo(203.25, 205)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_07" and has(line("director: ERA_Unit_03_Dep_Air0 back", from), "the round's last flight"),
      "the round's last flight: let go (or the round would never end)")
topScene(); tickTo(200, 249)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_07" and has(line("director: ERA_Unit_03_Dep_Air0 back"), "held 4"), "no fight for max_s (45 s): let go")
topScene(); tickTo(200, 203); D.decoyed = { [L] = 220 }; from = #logs + 1; tickTo(203.25, 219.75)
check(evs("^RE_SV_DirFree") == "" and DIR.holding(L), "your decoy on it: held, no release of ours inside it")
tickTo(220, 222)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_07" and not DIR.holding(L)
      and has(line("director: ERA_Unit_03_Dep_Air0 back in the fight", from), "freed by your decoy's end"),
      "... its end (RE_SV_DecoyEnd: this game's planes) then RE_SV_DirFree_07 (forwarded: a joiner's copies held too)")
-- the dive's release inside your decoy: it waits for the decoy's end
l1, f1 = topScene(); tickTo(200, 203); move(f1, KM(2, 0), DIRV(-1, 0)); tickTo(203.25, 211)
check(evs("^RE_SV_RadioDive") ~= "" and evs("^RE_SV_DirFree") == "", "(the dive's tell said)")
D.decoyed = { [L] = 230 }                                      -- (your decoy on the Lancers within the dive's lead)
from = #logs + 1
tickTo(211.25, 229.75)
check(evs("^RE_SV_DirFree") == "" and DIR.holding(L) and has(line("director: ERA_Unit_03_Dep_Air0 stays down with your decoy", from), "let go at its end"),
      "your decoy within the dive's lead: no RE_SV_DirFree (it would end the decoy early), still held")
check(DIR.release(L, "a test") == false and evs("^RE_SV_DirFree") == "", "... nor by DIR.release (P4)")
tickTo(230, 231)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_07" and not DIR.holding(L), "... let go at the decoy's end")
-- the last flight up but held ones, whatever the round's state
local L6 = "ERA_Unit_03_Dep_Air2"                              -- (a Lancer 6-ship, pool 09)
local function sixScene(state)
    fresh(12, state)
    FLAGS = { SV_Up_09 = 1, SV_Up_01 = 1 }
    for k = 0, 5 do plane(L6, k, KM(0.2 * k, 8, 5), DIRV(0, -1)) end
    local g = plane(F, 0, KM(30, 0), DIRV(-1, 0))
    D.up = { [L6] = true, [F] = true }
    D.now = 200
    DIR.spawned(L6, "lancer", 6); DIR.spawned(F, "duelist", 2)
    tickTo(200, 204)
    g.down = true; alive[F] = 0; D.up[F] = nil
end
sixScene("wave")
check(DIR.holding(L6), "(a held 6-ship)")
from = #logs + 1
tickTo(204.25, 206)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_09" and has(line("director: ERA_Unit_03_Dep_Air2 back in the fight", from), "the round's last flight (wave)"),
      "the rest of the wave down in state \"wave\" (6 left > waves.next_at: the next wave waits on them): let go at once, not at max_s")
sixScene("spawning"); D.queue = { "ERA_Unit_02_Dep_Air0" }
tickTo(204.25, 210)
check(evs("^RE_SV_DirFree") == "" and DIR.holding(L6), "... not while the wave's flights still spawn (one queued)")
D.queue = {}
tickTo(210.25, 212)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_09", "... and once they're out")
-- two held flights don't keep each other back (round 20: top cover's budget 2)
local LA, LB = "ERA_Unit_03_Dep_Air0", "ERA_Unit_04_Dep_Air0"  -- (Lancers, pool 07 and 10)
fresh(20)
FLAGS = { SV_Up_07 = 1, SV_Up_10 = 1, SV_Up_01 = 1 }
plane(LA, 0, KM(0, 8, 5), DIRV(0, -1)); plane(LA, 1, KM(0.3, 8.2, 5), DIRV(0, -1))
plane(LB, 0, KM(0, -8, 5), DIRV(0, 1)); plane(LB, 1, KM(0.3, -8.2, 5), DIRV(0, 1))
local fx = plane(F, 0, KM(30, 0), DIRV(-1, 0))
D.up = { [LA] = true, [LB] = true, [F] = true }
D.now = 200
DIR.spawned(LA, "lancer", 2); DIR.spawned(F, "duelist", 2)
tickTo(200, 204)
D.now = 234
DIR.spawned(LB, "lancer", 2)                                   -- (top cover's cooldown, 30 s, after the first)
tickTo(234, 238)
check(DIR.holding(LA) and DIR.holding(LB), "round 20: two Lancer flights held, 31 s apart")
fx.down = true; alive[F] = 0; D.up[F] = nil
tickTo(238.25, 240)
local freed = evs("^RE_SV_DirFree")
check((freed == "RE_SV_DirFree_07" or freed == "RE_SV_DirFree_10") and (DIR.holding(LA) ~= DIR.holding(LB)),
      "the other flight down: one of them let go at once (" .. freed .. "), the other still held over it")
topScene(3); tickTo(200, 206)
check(evs("^RE_SV_Dir") == "", "round 3 (top_cover budget 0): no hold")
ROLE.live = nil
topScene(); tickTo(200, 203)
check(evs("^RE_SV_DirHold") ~= "" and (DIR.holding(L) or DIR.holding(F)), "roles off: a flight held all the same (any_without_roles)")
CFG.director.top_cover.any_without_roles = false
topScene(); tickTo(200, 206)
check(evs("^RE_SV_Dir") == "", "... and none with any_without_roles = false")
CFG.director.top_cover.any_without_roles = true
ROLE.live = { duelist = true, lancer = true, wolf = true, skirm = true }

---------------------------------------------------------------------------------------------------- the pincer
print("the pincer")
local P1, P2, P3 = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air0", "ERA_Unit_01_Dep_Air1"
local function compassOf(x, y, cx, cy) return math.deg(math.atan(x - cx, -(y - cy))) % 360 end
local function adiff(x, y) local d = math.abs(x - y) % 360; return math.min(d, 360 - d) end
fresh(6)
CFG.director.pincer.chance = 1
D.queue, D.wave = { P1, P2, P3 }, 1
D.now = 300
from = #logs + 1
DIR.wave(300)
local pc = D.dir.pincer
check(pc and math.abs(pc.b0 - 90) < 1e-6 and pc.sep >= 90 and pc.sep <= 150 and has(line("director: pincer: wave 1's 3 fighter flights", from), "around you"),
      string.format("a wave of 3 fighter flights: a pincer around you, either side of your nose (east, 90): %.0f / %.0f", pc and pc.b1 or -1, pc and pc.b2 or -1))
for _, u in ipairs({ P1, P2, P3 }) do spawnFlight(u) end
local okSide, okRange, okYaw = true, true, true
for i, s in ipairs(spawns) do
    local want = (i % 2 == 1) and pc.b1 or pc.b2
    if adiff(compassOf(s.x, s.y, you.X, you.Y), want) > CFG.director.pincer.spread_deg + 1e-6 then okSide = false end
    local d = math.sqrt((s.x - you.X) ^ 2 + (s.y - you.Y) ^ 2) / 100000
    if d < 12 - 1e-6 or d > 18 + 1e-6 then okRange = false end
    if adiff(s.yaw, math.deg(math.atan(you.Y - s.y, you.X - s.x)) % 360) > 1e-6 then okYaw = false end
end
check(#spawns == 3 and okSide, "its flights alternate on the two bearings (within spread_deg)")
check(okRange and okYaw, "12-18 km from you (ring_km), each nose on you")
check(has(line("round 6: ERA_Unit_02_Dep_Air0", from), "a pincer side"), "the spawn line says so")
check(evs("^RE_SV_RadioPincer") ~= "" and since(from, "^tell: pincer") == 1 and since(from, "^tell: pincer") == 1
      and has(line("hud: callout 'TWO GROUPS INBOUND'", from), "FROM THE " .. compassName(pc.b1) .. " AND THE " .. compassName(pc.b2)),
      "the pincer tell once, naming both bearings (" .. compassName(pc.b1) .. ", " .. compassName(pc.b2) .. ")")
for _, u in ipairs({ P1, P2, P3 }) do for k = 0, flightSize(u) - 1 do plane(u, k, KM(15, 0), DIRV(-1, 0)) end end
tickTo(300, 302)
check(has(line("director: round 6", from), "pincer on the round") and has(line("director: round 6", from), "3 of 3 flights (8 planes)"),
      "once they're up: counted (STATS.tactic pincer), 8 planes tagged")
check(planes[1].dirTag and planes[1].dirTag.tactic == "pincer", "... { tactic = pincer }")
fresh(6); D.queue = { "@anomaly", P1, P2 }; DIR.wave(300)
check(D.dir.pincer == nil, "a special's wave: as it is")
fresh(6); D.queue = { P1, P2 }; D.raidUnits = { [P2] = true }; DIR.wave(300)
check(D.dir.pincer == nil, "a raid's wave: as it is")
fresh(6); D.queue = { P1 }; DIR.wave(300)
check(D.dir.pincer == nil, "one fighter flight: no pincer")
fresh(3); D.queue = { P1, P2 }; DIR.wave(300)
check(D.dir.pincer == nil, "round 3 (pincer budget 0): none")
fresh(6); D.queue = { P1, P2 }; COOP.open, COOP.role, COOP.slot = true, "host", 0; you = KM(5, 0)
D.now = 300; DIR.wave(300); spawns = {}; spawnFlight(P1)
local da = math.sqrt((spawns[1].x - AIRFIELD.X) ^ 2 + (spawns[1].y - AIRFIELD.Y) ^ 2) / 100000
check(D.dir.pincer and D.dir.pincer.centre == "airfield" and da >= 18 - 1e-6 and da <= 25 + 1e-6,
      string.format("co-op: around the airfield (%.1f km from it), the same bearings for every player", da))
COOP.open, COOP.role, COOP.slot = false, nil, nil
fresh(6); you = { X = ZONE.X + ZONE.HALF - 1000, Y = 0, Z = 300000 }; youFwd = { X = 1, Y = 0, Z = 0 }
D.queue = { P1, P2 }; D.now = 300; DIR.wave(300)
D.dir.pincer.b1, D.dir.pincer.b2 = 90, 90                       -- (both sides out over the zone's edge)
from = #logs + 1; spawns = {}; spawnFlight(P1)
check(has(line("director: pincer: ERA_Unit_01_Dep_Air0 fell back", from), "the zone's edge"), "a side out of the zone: a normal spawn point (logged)")
-- a flight that fell back is left out of the pincer (its tags and count), and the alternation goes on
local rawSpawnPoint, nCompass, failOn = spawnPoint, 0, nil
spawnPoint = function(range, compass, ...)                      -- (the director's points: the ones failOn names fall back)
    local x, y, d, bb, onIt = rawSpawnPoint(range, compass, ...)
    if compass then nCompass = nCompass + 1; if failOn(nCompass) then onIt = false end end
    return x, y, d, bb, onIt
end
fresh(6); D.queue, D.wave = { P1, P2, P3 }, 1; D.now = 300; DIR.wave(300)
nCompass, failOn = 0, function(n) return n == 3 end              -- (the third, on side 1 again)
from = #logs + 1; spawns = {}
for _, u in ipairs({ P1, P2, P3 }) do spawnFlight(u) end
for _, u in ipairs({ P1, P2, P3 }) do for k = 0, flightSize(u) - 1 do plane(u, k, KM(15, 0), DIRV(-1, 0)) end end
tickTo(300, 302)
local tagged = {}
for _, x in ipairs(planes) do if x.dirTag and x.dirTag.tactic == "pincer" then tagged[x.unit] = true end end
check(has(line("director: round 6", from), "2 of 3 flights") and tagged[P1] and tagged[P2] and not tagged[P3],
      "one of 3 fell back: counted as 2 of 3, its planes not tagged (no kill bonus for it)")
check(since(from, "^tell: pincer") == 1, "... the tell once, when both sides had a flight")
fresh(6); D.queue, D.wave = { P1, P2 }, 1; D.now = 300; DIR.wave(300)
nCompass, failOn = 0, function(n) return n % 2 == 0 end          -- (side 2 out of the zone)
from = #logs + 1; spawns = {}
for _, u in ipairs({ P1, P2 }) do spawnFlight(u) end
for _, u in ipairs({ P1, P2 }) do for k = 0, flightSize(u) - 1 do plane(u, k, KM(15, 0), DIRV(-1, 0)) end end
tickTo(300, 302)
local anyTag = false
for _, x in ipairs(planes) do if x.dirTag then anyTag = true end end
check(evs("^RE_SV_RadioPincer") == "" and not anyTag and since(from, "pincer on the round") == 0
      and has(line("director: pincer: wave 1's flights didn't come from two sides", from), "no pincer")
      and (D.dir.spent.room and D.dir.spent.room.pincer or 0) == 0,
      "one side only: no tell, no tags, not counted, its budget back")
spawnPoint = rawSpawnPoint
CFG.director.pincer.chance = DEF.pincer.chance

---------------------------------------------------------------------------------------------------- regroup
print("regroup")
local R = "ERA_Unit_01_Dep_Air1"                           -- a 4-ship, pool 02
local function regroupScene()
    fresh(10)
    D.now = 400
    DIR.spawned(R, "duelist", 4)
    local rp = {}
    for k = 0, 3 do rp[k] = plane(R, k, KM(5, k * 0.2), DIRV(-1, 0)); rp[k].born = 400.5 end
    plane(F, 0, KM(-20, 0), DIRV(1, 0))                       -- another flight up (the regroup isn't the round's last)
    D.up = { [R] = true, [F] = true }
    return rp
end
local rp = regroupScene()
tickTo(400, 404)
rp[0].down, rp[1].down = true, true
from = #logs + 1
tickTo(405, 409.75)
check(evs("^RE_SV_Dir") == "", "down to 2 of 4: nothing before after_s (10 s from its spawn)")
tickTo(410, 410)
check(evs("^RE_SV_RadioRegroup") ~= "" and evs("^RE_SV_Dir") == "RE_SV_DirHold_02" and has(line("director: round 10", from), "regroup on ERA_Unit_01_Dep_Air1"),
      "10 s on: the regroup tell, then it breaks off (RE_SV_DirHold_02), counted")
check(has(line("director: regroup: ERA_Unit_01_Dep_Air1", from), "breaks off for 7 s"), "... logged")
tickTo(410.25, 416.75)
check(evs("^RE_SV_DirFree") == "", "held for hold_s (7 s)")
tickTo(417, 417)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_02" and has(line("director: ERA_Unit_01_Dep_Air1 back in the fight", from), "regrouped"),
      "then back: RE_SV_DirFree_02")
rp = regroupScene(); tickTo(400, 404); rp[0].down = true; tickTo(405, 420)
check(evs("^RE_SV_Dir") == "", "3 of 4 left: no regroup")
rp = regroupScene(); D.up[F] = nil; for _, x in ipairs(planes) do if x.unit == F then x.down = true end end
tickTo(400, 404); rp[0].down, rp[1].down = true, true; from = #logs + 1; tickTo(405, 420)
check(evs("^RE_SV_") == "" and has(line("director: regroup not now", from), "the only flight up"), "the only flight up: no regroup (logged)")

---------------------------------------------------------------------------------------------------- SR.mslSlot
print("the missile slot at the main menu (searchSetup on fake tables)")
do
    local function fakeDT(name)
        local t = { full = name, rows = {}, addr = nextAddr + 1 }
        nextAddr = nextAddr + 1
        local function key(n) return type(n) == "table" and n.s or n end
        function t.FindRow(self, n) return self.rows[key(n)] end
        function t.AddRow(self, n, r)
            local function cp(x) if type(x) ~= "table" then return x end local c = {}; for k, v in pairs(x) do c[k] = cp(v) end; return setmetatable(c, getmetatable(x)) end
            self.rows[key(n)] = cp(r)
        end
        function t.RemoveRow(self, n) self.rows[key(n)] = nil end
        return t
    end
    local SLOTS = { "RootLua", "EvadeLua", "EvadeMissileNearLua", "EvadeMissileFarLua", "EvadeGunLua", "EvadeSpecialLua",
                    "BlackoutLua", "CloudAvoidanceLua", "ProvokeLua", "ProvokeNearLua", "ProvokeMidLua", "ProvokeFarLua",
                    "EscapeFromPursuerLua", "MoveAwayFromTargetLua", "PursueTargetLua" }
    local ls, npc, mod, mission, fcs, wpn = fakeDT("DT_NPC_LuaSet"), fakeDT("DT_NPC"), fakeDT("DT_NPC_AIModule"),
        fakeDT("DT_SV_NpcMission"), fakeDT("DT_NPC_FCS"), fakeDT("DT_NPC_Weapon")
    local base = { LuaAsetts = {} }
    for _, s in ipairs(SLOTS) do base.LuaAsetts[s] = { LuaScript = "stock " .. s } end
    ls.rows.NLID_0012_CP = base
    mod.rows.NPC_AIModule_Plane000 = { Radius = 6000, bEnableLostTargetInClouds = true }
    for _, id in ipairs({ "NPC_FCS_PlaneMsl000", "NPC_FCS_PlaneLAAM000", "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000",
                          "NPC_FCS_PlaneHCAA000", "NPC_FCS_PlaneFlr000" }) do
        fcs.rows[id] = { CaptureDistance = 2500, CaptureMinDistance = 300, CaptureAngleRange = 45, ActivationTime = 2,
                         TriggeringTime = 2.5, ShotIntervalTime = 10, RestingTime = 10, TriggerCount = 1, PredictionOffsetTime = 0 }
    end
    fcs.rows.NPC_FCS_PlaneGun000 = { CaptureDistance = 1500, CaptureAngleRange = 30, TriggeringTime = 1.5, TriggerCount = 10,
                                     RestingTime = 1, PredictionOffsetTime = 0, NpcWeaponId = FName("GUN_000") }
    wpn.rows.GUN_000 = { damage = 1, MaxSpawnAngle = 3, LifeTime = 2 }
    local list = { "f16c_common" }
    for _, x in ipairs(CFG.aircraft) do list[#list + 1] = x end
    for _, e in ipairs(CFG.variety.late) do list[#list + 1] = e[1] end
    list[#list + 1] = CFG.jammer.aircraft
    for _, x in ipairs(list) do
        local id = "OP_" .. x
        local odd = x == "f15e_common"                          -- (one row with its missiles in slot 3)
        npc.rows[id] = { NpcFCSId0 = FName("NPC_FCS_PlaneFlr000"), NpcFCSId1 = FName("NPC_FCS_PlaneGun000"),
                         NpcFCSId2 = FName(odd and "None" or "NPC_FCS_PlaneMsl000"), NpcFCSId3 = FName(odd and "NPC_FCS_PlaneMsl000" or "None"),
                         NpcFCSId4 = FName("None"), NpcFCSId5 = FName("None"), LuaSetId = FName("NLID_0012_CP"),
                         NpcAIModuleId = FName("NPC_AIModule_Plane000") }
        mission.rows[x] = { NpcId = FName(id) }
        for lv = 0, #SPIKE_SUFFIX do mission.rows[x .. "_sv" .. SPIKE_SUFFIX[lv]] = { NpcId = FName(id .. "_SV" .. SPIKE_SUFFIX[lv]:upper()) } end
    end
    OBJ[PROBE_TABLES[1].path], OBJ[PROBE_TABLES[2].path], OBJ[SEARCH_MODULE.path] = ls, npc, mod
    OBJ["/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"] = mission
    OBJ[FCS_TABLE], OBJ[WEAPON_TABLE] = fcs, wpn
    for _, d in pairs(CFG.behaviour_sets) do
        for _, n in pairs(d.slots) do OBJ["/Game/LuaSource/SurvivalMode/AI/" .. n .. "." .. n] = { full = n } end
    end
    BS.done, BS.ready, BS.tries = false, {}, 0
    SR.done, SR.ready, SR.tries, SR.levels, SR.mslSlot = false, {}, 0, {}, nil
    from = #logs + 1
    setsSetup(); searchSetup()
    check(SR.mslSlot and SR.mslSlot.f16c_common_sv == 2 and SR.mslSlot.su33_common_svc == 2, "every level's row: its first missile slot (2)")
    check(SR.mslSlot.f15e_common_sv == 3 and has(line("director: ", from), "not: f15e_common_sv 3"),
          "a row with its missiles in slot 3: recorded and named in the line (never a salvo)")
    check(has(line("director: ", from), "rows carry their missiles in fire-control slot 2 (WN_WEAPON_3: the salvo)"), "the main-menu line")
end

---------------------------------------------------------------------------------------------------- co-op
print("co-op: the host")
local standIn = mkObj("BP_OP1022_f16c_CoopPeerB_C_1", KM(50, 0), DIRV(1, 0))
local function joiner(at, yaw)
    COOP.open, COOP.role, COOP.slot = true, "host", 0
    M.peers[1] = { obj = standIn, addr = standIn.addr, at = at, rot = { 0, yaw or 0, 0 }, alive = true, fresh = true,
                   onAirfield = false, hpPct = 100 }
end
-- a bracket around the joiner (you 50 km away): its own copies fire at it, "dv" with the tell's lead
a, b = bracketScene()
joiner(KM(50, 0))
move(a, KM(53, 0), DIRV(-1, 0)); move(b, KM(50, 3), DIRV(0, -1))
tickTo(100, 102)
local function sentOf(pat) local t = {}; for _, s in ipairs(sent) do if s:find(pat) then t[#t + 1] = s end end; return table.concat(t, ";") end
check(sentOf("tl|bracket") == "1>tl|bracket||", "the bracket tell to player 2 only (\"tl\")")
check(sentOf(">dv|") == "1>dv|RE_SV_Salvo_02A|ERA_Unit_01_Dep_Air1|1.00;1>dv|RE_SV_Salvo_04B|ERA_Unit_02_Dep_Air0|1.00",
      "both shots to player 2's own copies by \"dv\", with the tell's lead (1 s) timed there")
check(evs("^RE_SV_Salvo") == "" and has(line("director: bracket on player 2's copies"), "sent"), "... none fired here (the host's own shots aim at the host)")
check(mirroredEvent("RE_SV_Salvo_02A") == false and mirroredEvent("RE_SV_DirHold_07") and mirroredEvent("RE_SV_DirFree_07"),
      "KEEP_EVENTS: RE_SV_Salvo_* kept, RE_SV_DirHold / DirFree forwarded")
check(COOP.dispatch(0, "RE_SV_Salvo_02A", B1, 1) == false and COOP.dispatch(1, "RE_SV_AceTurn_02", B1, 1) == false
      and COOP.dispatch(30, "RE_SV_Salvo_02A", B1, 1) == false, "COOP.dispatch: never to itself, a bad slot or a name not the director's")
-- a joiner's cover: a hunt, its TargetActor kept on the stand-in, the orders back after aim_s
p, _, _, q = coverScene()
joiner(KM(50, 0))
move(p, KM(51, 0), DIRV(1, 0)); move(q, KM(50, 3), DIRV(0, -1))
for _, x in ipairs(planes) do if x.unit == L or x.unit == E then move(x, KM(-30, 0)) end end
sent = {}
from = #logs + 1
tickTo(100, 103)
check(sentOf("tl|six") == "1>tl|six||" and evs("^RE_SV_RadioSix") == "", "player 2 on a plane's tail 3 s: the six tell to player 2, not played here")
tickTo(103.25, 104)
check(evs("^RE_SV_Hunt") == "RE_SV_Hunt_05" and evs("^RE_SV_Ace") == "" and has(line("director: cover for player 2", from), "RE_SV_Hunt_05 fired"),
      "lead_s after: its flight hunts (RE_SV_Hunt_05, AIFirst), no LastTGT (it would turn onto the host)")
tickTo(104.25, 105)
check(q.obj.tgt == standIn and q.obj.tgtKey == "TargetActor" and has(line("director: ERA_Unit_02_Dep_Air1's TargetActor kept on player 2's plane", from), "cover"),
      "its TargetActor kept on player 2's stand-in (logged once)")
q.tier = CFG.tiers.list[#CFG.tiers.list]                       -- (a Reaper: ACE.hunt keeps its target on the host)
ACE.hunt(q)
check(q.obj.tgt == standIn and DIR.aimed(q), "ACE.hunt leaves an aimed plane's TargetActor alone")
tickTo(105.25, 123.75)
check(evs("^RE_SV_DirFree") == "", "... for aim_s (20 s from the hunt)")
tickTo(124, 124)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_05" and not DIR.aimed(q) and has(line("director: ERA_Unit_02_Dep_Air1 back in the fight", from), "its aim on player 2 over"),
      "then its orders back (RE_SV_DirFree_05)")
-- your decoy on that flight while its aim's on: the aim's over, its orders back at the decoy's end (not before)
p, _, _, q = coverScene()
joiner(KM(50, 0))
move(p, KM(51, 0), DIRV(1, 0)); move(q, KM(50, 3), DIRV(0, -1))
for _, x in ipairs(planes) do if x.unit == L or x.unit == E then move(x, KM(-30, 0)) end end
tickTo(100, 105)
check(DIR.aimed(q), "(player 2's cover aimed)")
D.decoyed = { [Q] = 140 }
events = {}
from = #logs + 1
tickTo(105.25, 139.75)
check(evs("^RE_SV_DirFree") == "" and not DIR.aimed(q)
      and has(line("director: ERA_Unit_02_Dep_Air1 stays down with your decoy", from), "its orders back at the decoy's end"),
      "your decoy on it: the aim's over, no RE_SV_DirFree inside the decoy")
tickTo(140, 141)
check(evs("^RE_SV_DirFree") == "RE_SV_DirFree_05" and has(line("director: ERA_Unit_02_Dep_Air1 back in the fight", from), "after your decoy"),
      "... then at its end (a joiner's copies freed too)")
-- a split-hunt flight held: the hunt waits out the hold, and the hold's end gives it back (COOP.hunted)
COOP.open, COOP.role, COOP.slot = true, "host", 0
CFG.coop.enabled = true
fresh(6)
COOP.open, COOP.role, COOP.slot = true, "host", 0
COOP.tick(10)
M.units[L] = { gen = 4, n = 2, planes = { { id = 1 }, { id = 2 } }, ground = {}, at = clock }
D.up = { [L] = true }
D.dir.held[L] = { kind = "top", at = 0, dmg = 0 }
M.hunts = { { at = clock - 1, name = "RE_SV_Hunt_07", unit = L } }
events = {}
COOP.tick(11)
check(evs("^RE_SV_Hunt") == "" and #M.hunts == 1, "the co-op host's split hunt for a held flight waits (the hunt would free it)")
D.dir.held[L] = nil
clock = clock + 3
COOP.tick(12)
check(evs("^RE_SV_Hunt") == "RE_SV_Hunt_07" and COOP.hunted(L), "... and goes once it's let go (COOP.hunted)")
D.dir.held[L] = { kind = "top", at = 0, dmg = 0 }
alive[L] = 2
events = {}
DIR.release(L, "a test")
check(evs("^RE_SV_") == "RE_SV_DirFree_07,RE_SV_Hunt_07", "a split-hunt flight let go: its orders, then its hunt again")
-- a long hold (max_s 600): the split hunt waits as long as the hold lasts, past its old 60 s
D.dir.held[L] = { kind = "top", at = 0, dmg = 0 }
CFG.director.top_cover.max_s = 600
M.hunts = { { at = clock - 1, name = "RE_SV_Hunt_07", unit = L } }
events = {}
for _ = 1, 60 do clock = clock + 2; COOP.tick(13) end
check(evs("^RE_SV_Hunt") == "" and #M.hunts == 1, "a hold of 120 s (top_cover.max_s 600): the hunt still waits")
D.dir.held[L] = nil
clock = clock + 3
COOP.tick(14)
check(evs("^RE_SV_Hunt") == "RE_SV_Hunt_07", "... and goes once it's let go")
CFG.director.top_cover.max_s = DEF.top_cover.max_s
-- a joiner who links later: the holds in force, once its copies are up (as they stand then)
D.dir.held[L] = { kind = "top", at = 0, dmg = 0 }
sent = {}
inbox[#inbox + 1] = "1|jn"
COOP.tick(15)
check(sentOf("ev|RE_SV_DirHold") == "", "player 2 links: its holds not at once")
clock = clock + 13
COOP.tick(16)
check(sentOf("ev|RE_SV_DirHold") == "1>ev|RE_SV_DirHold_07" and has(line("coop: player 2 brought up to date"), "RE_SV_DirHold_07"),
      "... 12 s on (its copies up): RE_SV_DirHold_07 to player 2")
sent = {}
inbox[#inbox + 1] = "1|jn"
COOP.tick(17)
D.dir.held[L] = nil
clock = clock + 13
COOP.tick(18)
check(sentOf("ev|RE_SV_DirHold") == "", "... none for a flight let go meanwhile")
CFG.coop.enabled = false
COOP.open, COOP.role, COOP.slot = false, nil, nil

print("co-op: the joiner's \"dv\"")
do
    CFG.coop.enabled = true
    COOP.open, COOP.role, COOP.slot = true, "join", 1
    D = { round = 6, state = "fighting", now = 500, up = {}, flown = {} }
    COOP.tick(20)
    local U = B1
    local c1, c2 = mkObj("copy1", KM(1, 0), DIRV(1, 0)), mkObj("copy2", KM(2, 0), DIRV(1, 0))
    M.cunits[U] = { gen = 1, n = 2, planes = { c1, c2 }, binds = { 11, 12 }, gbinds = {} }
    M.readyAt = nil
    events = {}
    from = #logs + 1
    inbox[#inbox + 1] = "0|dv|RE_SV_Salvo_02A|" .. U .. "|1.00"
    COOP.tick(21)
    check(not M.dvQ or #M.dvQ == 0, "a level still loading: dropped")
    check(has(line("coop: the host's director event RE_SV_Salvo_02A dropped", from), "this level isn't ready"), "... logged")
    clock = clock + 4
    inbox[#inbox + 1] = "0|dv|RE_SV_Salvo_02A|" .. U .. "|1.00"
    COOP.tick(22)
    check(M.dvQ and #M.dvQ == 1, "ready: queued")
    roundsTick(500)
    check(evs("^RE_SV_Salvo") == "", "... not before its delay")
    clock = clock + 1.1
    roundsTick(501)
    check(evs("^RE_SV_Salvo") == "RE_SV_Salvo_02A" and has(line("coop: director RE_SV_Salvo_02A fired here"), "fired"),
          "1 s on: fired on this game's copy (its own fire control aims at this game's player)")
    events = {}
    local bad = { "0|dv|RE_SV_AceTurn_02|" .. U .. "|0", "0|dv|RE_SV_Salvo_04A|" .. U .. "|0", "0|dv|RE_SV_Salvo_02C|" .. U .. "|0",
                  "0|dv|RE_SV_Salvo_02A|" .. U .. "|nan", "0|dv|RE_SV_Salvo_02a|" .. U .. "|0", "0|dv|" .. ("RE_SV_Salvo_02A"):rep(5) .. "|" .. U .. "|0" }
    for _, m in ipairs(bad) do inbox[#inbox + 1] = m end
    COOP.tick(23)
    check(#M.dvQ == 0, "dropped: not a director event, another flight's number, a plane it hasn't got, a bad delay, a lower-case letter, a long name")
    M.dead[12] = true
    inbox[#inbox + 1] = "0|dv|RE_SV_Salvo_02B|" .. U .. "|0"
    COOP.tick(24)
    check(#M.dvQ == 0, "a copy already down: dropped")
    inbox[#inbox + 1] = "0|dv|RE_SV_DirHold_02|" .. U .. "|99"
    COOP.tick(25)
    check(#M.dvQ == 1 and math.abs(M.dvQ[1].at - (clock + 3)) < 1e-9, "a flight's event (any live copy): queued, its delay cut to 3 s")
    M.dvQ = {}
    clock = clock + 2
    for _ = 1, 9 do inbox[#inbox + 1] = "0|dv|RE_SV_Salvo_02A|" .. U .. "|0" end
    COOP.tick(26)
    check(#M.dvQ == 8 and has(line("coop: the host's director event RE_SV_Salvo_02A dropped"), "more than 8 a second"), "at most 8 a second")
    inbox[#inbox + 1] = "0|rs"
    COOP.tick(27)
    check(M.dvQ == nil, "the host's restart (\"rs\"): the queue gone")
    events = {}
    D = { round = 6, state = "fighting", now = 500, up = {}, flown = {} }
    p = plane(A, 0, KM(1, 0), DIRV(1, 0)); plane(Q, 0, KM(0, 3), DIRV(0, -1))
    tickTo(500, 506)
    check(evs("^RE_SV_") == "", "DIR.tick on a joiner: nothing (the host directs)")
    CFG.coop.enabled = false
    COOP.open, COOP.role, COOP.slot = false, nil, nil
end

---------------------------------------------------------------------------------------------------- the aces' moves
print("the aces' own reversal: its next no sooner than the LastTGT")
do
    local reaper
    for _, t in ipairs(CFG.tiers.list) do if t.name:lower() == "reaper" then reaper = t end end
    fresh(6)
    local r = plane(Q, 0, KM(1.5, 0), DIRV(1, 0)); r.tier = reaper   -- (a duelist Reaper 1.5 km ahead, flying away)
    D.aceMoveAt = {}
    ACE.movesTick(100, D)
    local want = 100 + TELL.leadS("reversal") + CFG.director.cover.move_s
    check(D.aceMoveAt[Q] == want, string.format("a reversal: its flight's next move at %.2f (lead_s + cover.move_s 30; was 20 s), got %s",
          want, tostring(D.aceMoveAt[Q])))
    move(r, KM(0.5, 0)); D.aceMoveAt = {}
    ACE.movesTick(200, D)
    check(D.aceMoveAt[Q] == 200 + TELL.leadS("kulbit") + 12, "a kulbit: lead_s + 12 s")
end

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
do
    local mainLua = readAll(MOD .. "/Scripts/main.lua")
    local t, d, m = mainLua:find('"sv_tells"', 1, true), mainLua:find('"sv_director"', 1, true), mainLua:find('"sv_menu"', 1, true)
    check(t and d and m and t < d and d < m, "MODULES: sv_tells, sv_director, sv_menu (before sv_coop: it wraps SV_Event after)")
    local sm = readAll(MOD .. "/Scripts/sv_main.lua")
    local mv, dr, tl = sm:find('timed("moves", ACE.movesTick', 1, true), sm:find('timed("director", DIR.tick, now, paused)', 1, true),
        sm:find('timed("tells", TELL.tick', 1, true)
    check(mv and dr and tl and mv < dr and dr < tl, "sv_main probeTick: DIR.tick after ACE.movesTick, timed \"director\", before TELL.tick")
    local sr = readAll(MOD .. "/Scripts/sv_rounds.lua")
    check(has(sr, "pcall(DIR.roundStart, D.now)") and has(sr, "pcall(DIR.wave, D.now)") and has(sr, "pcall(DIR.wave, now)"),
          "sv_rounds: startRound's budgets and wave 1, each later wave")
    local sp = readAll(MOD .. "/Scripts/sv_spawn.lua")
    check(has(sp, "pcall(DIR.spawnAt, unit)") and has(sp, "pcall(DIR.spawned, unit, role, r, ace)") and has(sp, "D.flightRow[unit] = ac"),
          "sv_spawn spawnFlight: the pincer's point, the flight's row, the spawn")
    check(has(readAll(MOD .. "/Scripts/sv_allies.lua"), "DIR.holding(u)") and has(readAll(MOD .. "/Scripts/sv_ai.lua"), "DIR.aimed(p)")
          and has(readAll(MOD .. "/Scripts/sv_ai.lua"), "DIR.holding(p.unit)"), "sv_allies' hunts and the aces' moves skip held flights; ACE.hunt aimed planes")
    local d = readAll(MOD .. "/Scripts/sv_director.lua")
    check(not d:find("local%s+[%w_,%s]*=%s*SV_Event") and not d:find("local%s+[%w_,%s]*=%s*hudCallout"),
          "sv_director never keeps SV_Event / hudCallout at load (sv_coop wraps them after)")
end

print(fails == 0 and "director test: all passed" or ("director test: " .. fails .. " FAILED"))
logFile:close()
os.exit(fails == 0 and 0 or 1)
