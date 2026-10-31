-- aces_test.lua <mod dir> <work dir> (run by tools/checks/aces_test.sh): the behaviour roadmap's P9, ace personalities
-- (tools/re/BEHAVIOUR_DIRECTOR.md unit 10), on the real sv_core, sv_config, sv_rows, sv_ai, sv_spawn, sv_anomalies,
-- sv_rounds (startRound exposed), sv_stats, sv_tells, sv_director and sv_coop (M and mirroredEvent exposed), the game
-- stubbed, the planes stubbed as objects with a position and a forward vector:
--   survival.ini's new sections ([aces.personality], [aces.personality.openers.*], [aces.flight.<tier>], its roles and
--     blink) read;
--   the build data (ACE.BLINK, ACE.blinkEvent: a duelist flight's lead only, letters only);
--   each squadron's ace-round role mix (ROLE.mixFor and the real startRound: Bounty the Lancers, Valkyrie the Wolf pairs,
--     Inferno / Wraith / Harvest the duelists, filled from the rest when short, theirs from the Wolf pairs first;
--     personality off: ace_mix);
--   spawnFlight's opener (each tier's openers in turn, a blink only on a duelist flight, else a kulbit), "high"'s
--     altitude (off a Lancer flight, top_m), a Valkyrie Wolf flight's trap held (ROLE.spawned), ACE.squadUp's line;
--   ACE.squadTick: first contact within the opener's km, the squadron's tell first (its radio line, no callout: the
--     round's first flight of it; later ones the opener's own tell), the opener its lead_s on: high (a salvo from the nearest
--     planes able to, gap_s apart), trap (sprung spring_s later after the "trap" tell: free and LastTGT; waits while the
--     trap's pending, gives up after wait_s; not a Wolf flight: the pack's reversal), kulbit (the flight's
--     RE_SV_AceKulbit_NN), blink (the lead to a spot behind and beside you, ground clearance, smoke); the blink tick (you
--     on its six, a hit, none for a hit inside every_s; every_s; the reversals held move_gap_s; Harvest's blink before its
--     reversal); your decoy;
--     personality off; the round line's counts;
--   co-op: a joiner who meets a squadron first (its tell by "tl", the salvo on its copies by "dv", no blink round it),
--     a joiner's game (nothing), KEEP_EVENTS (^RE_SV_WraithBlink kept);
--   the hooks by their place in the source.
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
    "\r\n[aces.personality]\r\nsmoke = false\r\n[aces.personality.openers.high]\r\nsalvo = 3\r\n" ..
    "[aces.flight.reaper]\r\nopeners = kulbit, high\r\n[aces.flight.phantom.blink]\r\nevery_s = 15\r\n" ..
    "[aces.flight.legend.roles]\r\nwolf = 0.5\r\n")

local clock = 1000                               -- (co-op's levelReady and rate limits)
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.72.0-aces.test"
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
local setAc = {}
function SV_SetAircraft(unit, row, idx) setAc[#setAc + 1] = { unit = unit, row = row, idx = idx }; return 1 end
function SV_SetLevel() return 1 end
local spawns = {}
function SV_Spawn(unit, x, y, z, yaw) spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw }; return flightSize(unit) end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
local sent = {}
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. msg; return 1 end
function SV_CoopRecv() return "" end
function SV_CoopInfo() return "open=1;state=linked;peers=1/linked/40/10/p" end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopPeerAt() return "" end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }
local callouts = {}
function hudCallout(text, sub, big) callouts[#callouts + 1] = { text = text, sub = sub, big = big } end

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
local FLAGS = {}
function svFlags() return FLAGS end
part("sv_config.lua")
local cfgLine = nil
for _, l in ipairs(logs) do if l:find("^config: survival%.ini") then cfgLine = l end end
part("sv_rows.lua"); part("sv_ai.lua")
hudCallout = function(text, sub, big) callouts[#callouts + 1] = { text = text, sub = sub, big = big } end
part("sv_spawn.lua"); part("sv_anomalies.lua")
part("sv_rounds.lua", nil, { { "\nlocal function startRound%(%)", "\nfunction startRound()" } })
part("sv_tactical.lua"); part("sv_stats.lua"); part("sv_tells.lua"); part("sv_director.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" }, { "\nlocal function mirroredEvent%(name%)", "\nfunction mirroredEvent(name)" } })
local M = _G.M
function searchAircraft(a) return a end
function playerOnAirfield() return grounded end          -- (sv_rounds.lua's own reads where you are)
function addCredits() end
LB.stat, LB.special = function() end, function() end
presetName = function() return "standard", 3 end
svFlags = function() return FLAGS end
-- the ground under a point (cm; nil: no hit) and the smoke (counted)
local groundFn = function() return 0 end
ANOM.groundAt = function(x, y) return groundFn(x, y) end
local smokes = 0
ANOM.smokeAt = function() smokes = smokes + 1; return 1 end
ROLE.live = { duelist = true, lancer = true, wolf = true, skirm = true }
CFG.airfield.enabled = false
CFG.specials.enabled = false
CFG.jammer.enabled = false
math.randomseed(9)

local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat) then n = n + 1 end end; return n end
local function evs(pat, from) local t = {}; for i = from or 1, #events do if events[i]:find(pat) then t[#t + 1] = events[i] end end; return table.concat(t, ";") end
local function said(text) for _, c in ipairs(callouts) do if c.text == text then return c end end return nil end
-- (no tell callout: none of their old texts, gone since the clean up of 2026-10-29; ACE INBOUND and the round's own
-- callouts come as ever)
local OLD_TELLS = { "POST-STALL ACES", "FROM ABOVE", "THE PACK", "THEY BLINK", "THE HARVEST", "IT BLINKED", "IT'S A TRAP",
                    "ACE POST-STALL", "BANDIT DIVING", "HE'S DRAGGING YOU", "ACE REVERSAL" }
local function noTell()
    for _, c in ipairs(callouts) do
        for _, t in ipairs(OLD_TELLS) do if tostring(c.text):find(t, 1, true) then return false end end
    end
    return true
end
local function deep(t) if type(t) ~= "table" then return t end; local c = {}; for k, v in pairs(t) do c[k] = deep(v) end; return c end
local function sentOf(pat) local t = {}; for _, s in ipairs(sent) do if s:find(pat) then t[#t + 1] = s end end; return table.concat(t, ";") end

-- you (the pawn), flying +X (heading 0) at 250 m/s; KM(x, y, z): x km east (+X), y km +Y, z km up
local function KM(x, y, z) return { X = x * 100000, Y = y * 100000, Z = (z or 3) * 100000 } end
local function DIRV(x, y, z) local l = math.sqrt(x * x + y * y + (z or 0) ^ 2); return { X = x / l, Y = y / l, Z = (z or 0) / l } end
local you, youFwd = KM(0, 0), DIRV(1, 0)
local pawn = { full = "BP_PlayerPlane_PP1000_f16c_C_1", addr = 9, MaxHealth = 100, HealthInternal = 800 }
function pawn:K2_GetActorLocation() return { X = you.X, Y = you.Y, Z = you.Z } end
function pawn:GetActorForwardVector() return { X = youFwd.X, Y = youFwd.Y, Z = youFwd.Z } end
function pawn:GetVelocity() return { X = youFwd.X * 25000, Y = youFwd.Y * 25000, Z = 0 } end
survivalPC = { Pawn = pawn, full = "PC", addr = 8 }
local nextAddr = 100
local function mkObj(name, at, fwd)
    nextAddr = nextAddr + 1
    local o = { full = name, addr = nextAddr, at = at, fwd = fwd, HealthInternal = 1000 }
    function o:K2_GetActorLocation() return { X = self.at.X, Y = self.at.Y, Z = self.at.Z } end
    function o:GetActorForwardVector() return { X = self.fwd.X, Y = self.fwd.Y, Z = self.fwd.Z } end
    o.AIStateComponent = { BlackboardComponent = { SetValueAsObject = function() end, GetValueAsObject = function() return nil end,
                                                   GetValueAsEnum = function() return 10 end } }
    return o
end
-- plane k of flight unit at `at`, nose along fwd (the sweep's last sample: p.at / p.dist as of now)
local function plane(unit, k, at, fwd, tierIdx)
    local name = string.format("BP_OP1021_su57_C_%d", nextAddr + 1)
    local o = mkObj(name, at, fwd or DIRV(-1, 0))
    local p = { obj = o, name = name, unit = unit, k = k, at = { X = at.X, Y = at.Y, Z = at.Z }, fwd = o.fwd, born = 0,
                tier = CFG.tiers.list[tierIdx or #CFG.tiers.list] }
    p.dist = km(p.at, you)
    planes[#planes + 1] = p
    alive[unit] = (alive[unit] or 0) + 1
    return p
end
local function move(p, at, fwd)
    p.obj.at, p.at = at, { X = at.X, Y = at.Y, Z = at.Z }
    if fwd then p.obj.fwd, p.fwd = fwd, fwd end
    p.dist = km(p.at, you)
end
local function tierOf(name) for i, t in ipairs(CFG.tiers.list) do if t.name == name then return i end end end
local function fresh(round, tk)
    planes, alive, events, spawns, sent, callouts, setAc, smokes = {}, {}, {}, {}, {}, {}, {}, 0
    D = { round = round, state = "fighting", now = 100, up = {}, flown = {}, queue = {}, spare = {}, events = {} }
    D.roundTier = tk and tierOf(tk) or nil
    you, youFwd, grounded = KM(0, 0), DIRV(1, 0), false
    COOP.open, COOP.role, COOP.slot = false, nil, nil
    M.peers = {}
    groundFn = function() return 0 end
    STATS.roundStart(100)
end
local function tickTo(t0, t1, withMoves)               -- the squads (and the reversals, ACE.movesTick) every 250 ms
    local n = math.floor((t1 - t0) / 0.25 + 0.5)
    for i = 0, n do
        local t = t0 + i * 0.25
        D.now = t
        ACE.squadTick(t, D, false)
        if withMoves then ACE.movesTick(t, D) end
        TELL.tick(t)
    end
end
-- the ace rows (searchSetup's at the main menu): usable, their missiles in slot 2
SR.usable, SR.mslSlot = SR.usable or {}, {}
for tk, keys in pairs(ACE.roster) do
    for _, k in ipairs(keys) do
        for _, part_ in ipairs({ "l", "w" }) do
            SR.usable[ACE.row(tk, k, part_)] = ACE.row(tk, k, part_) .. "_sv"
            SR.mslSlot[ACE.row(tk, k, part_)] = 2
        end
    end
end
for _, a in ipairs(CFG.aircraft) do SR.usable[a] = a .. "_sv" end

---------------------------------------------------------------------------------------------------- survival.ini
print("survival.ini's [aces.personality] and [aces.flight.*]")
local AC = CFG.aces
check(cfgLine and not has(cfgLine, "not used"), "config: every line used (" .. tostring(cfgLine) .. ")")
check(AC.personality.smoke == false and AC.personality.openers.high.salvo == 3 and AC.flight.reaper.openers[2] == "high"
      and #AC.flight.reaper.openers == 2 and AC.flight.phantom.blink.every_s == 15 and AC.flight.legend.roles.wolf == 0.5,
      "[aces.personality] smoke, [aces.personality.openers.high] salvo, [aces.flight.reaper] openers, [aces.flight.phantom.blink] every_s, [aces.flight.legend.roles] read")
CFG.aces = deep(CFG_DEFAULTS.aces)
AC = CFG.aces
check(AC.personality.enabled and AC.flight.phantom.blink.enabled and AC.flight.reaper.blink.enabled and AC.flight.reaper.moves
      and AC.flight.reaper.hunt, "shipped: personalities on, Wraith's and Harvest's blinks on, Harvest's reversals and hunt kept")
for _, id in ipairs({ "mercenary_in", "legend_in", "demon_in", "phantom_in", "reaper_in", "blink" }) do
    check(TELL.known(id) and CFG.tells.cooldown_s[id] ~= nil and CFG.tells.lead_s[id] ~= nil, "the tell " .. id .. " is in the catalog")
end

---------------------------------------------------------------------------------------------------- build data
print("the blink events (ACE.BLINK, ACE.blinkEvent)")
check(ACE.BLINK.STEP_DEG == 45 and ACE.BLINK.RING_M == 1000 and ACE.BLINK.ROLE == "duelist", "ACE.BLINK: 45 deg, 1000 m, the duelists' flights")
check(ACE.blinkEvent("ERA_Unit_01_Dep_Air0", 0) == "RE_SV_WraithBlinkAA" and ACE.blinkEvent("ERA_Unit_02_Dep_Air2", 7) == "RE_SV_WraithBlinkFH",
      "a duelist flight's lead: RE_SV_WraithBlink<K><J> (pool flight A..F, bearing A..H)")
check(ACE.blinkEvent("ERA_Unit_03_Dep_Air0", 0) == nil and ACE.blinkEvent("ERA_Unit_01_Dep_Air0", 8) == nil
      and ACE.blinkEvent("ERA_Unit_01_Dep_Air0", 1.5) == nil and ACE.blinkEvent("SV_Unit_Glitch", 0) == nil,
      "none for a Lancer flight, a bearing past H or not whole, a unit off the pool")
local letters = true
for nn = 1, 2 do for k = 0, 2 do for j = 0, 7 do
    local e = ACE.blinkEvent(string.format("ERA_Unit_%02d_Dep_Air%d", nn, k), j)
    if not (e and e:match("^RE_SV_WraithBlink%u%u$")) then letters = false end
end end end
check(letters, "every one of the 48 names in letters (hard rule 17)")

---------------------------------------------------------------------------------------------------- the role mix
print("each squadron's ace-round roles (ROLE.mixFor, startRound)")
local function w(tk) local x, band = ROLE.mixFor(16, tk); return x, band end
local m, b = w("mercenary")
check(b == "ace:mercenary" and m.lancer == 1 and m.duelist == 0, "Bounty: the Lancers' (band ace:mercenary)")
m, b = w("legend")
check(b == "ace:legend" and m.wolf == 1 and m.lancer == 0, "Valkyrie: the Wolf pairs'")
for _, tk in ipairs({ "demon", "phantom", "reaper" }) do
    m, b = w(tk)
    check(b == "ace:" .. tk and m.duelist == 1 and m.wolf == 0 and m.lancer == 0, tk .. ": the duelists' (LA_SV_TailChase's Super pursuit)")
end
m, b = ROLE.mixFor(16, true)
check(b == "ace" and m.duelist == 1, "an ace round without a tier key: ace_mix as before")
AC.personality.enabled = false
m, b = w("mercenary")
check(b == "ace" and m.duelist == 1 and m.lancer == 0, "personality off: ace_mix")
AC.personality.enabled = true
AC.flight.demon.roles = { duelist = 0, lancer = 0, wolf = 0, skirm = 0 }
m, b = w("demon")
check(b == "ace" and m.duelist == 1, "a squadron whose roles are all 0: ace_mix")
AC.flight.demon.roles = deep(CFG_DEFAULTS.aces.flight.demon.roles)
local function roundPicks()
    local by, total = {}, 0
    for _, wv in ipairs(D.waves) do
        for _, u in ipairs(wv) do
            if u:sub(1, 1) ~= "@" then
                local r = ROLE.flight(u) or "?"
                by[r] = (by[r] or 0) + flightSize(u); total = total + flightSize(u)
            end
        end
    end
    return by, total
end
local function aceRoundOf(tk, round)
    fresh(round - 1)
    D.state = "wait"
    D.nextTier, D.nextTierRound = tierOf(tk), round
    local from = #logs + 1
    startRound()
    return from
end
local from = aceRoundOf("Mercenary", 16)
local by, total = roundPicks()
check(D.roundTier == tierOf("Mercenary") and (by.lancer or 0) == 24 and total >= 28,
      string.format("round 16, Bounty's: the Lancers' 24 aircraft, the rest filled (lancer %d of %d)", by.lancer or 0, total))
check(has(line("roles: round 16", from), "the Bounty squadron's roles") and has(line("roles: round 16", from), "filled from"),
      "its roles line: " .. tostring(line("roles: round 16", from)))
aceRoundOf("Legend", 19)
by, total = roundPicks()
check((by.wolf or 0) == 24 and total >= 28, string.format("round 19, Valkyrie's: the Wolf pairs' 24 (wolf %d of %d)", by.wolf or 0, total))
from = aceRoundOf("Demon", 22)
by, total = roundPicks()
check((by.duelist or 0) == 24 and total >= 28, string.format("round 22, Inferno's: the duelists' 24 (duelist %d of %d)", by.duelist or 0, total))
-- (F1's review: a duelists' squadron's rest from the Wolf pairs first, whose pursuits keep the Super branch)
check((by.wolf or 0) == total - 24 and (by.lancer or 0) + (by.skirm or 0) == 0
      and has(line("roles: round 22", from), "(the Wolf pairs first: they keep the Super pursuit)"),
      string.format("... the rest from the Wolf pairs first, none from the Lancers or Skirmishers (wolf %d, lancer %d, skirm %d)",
          by.wolf or 0, by.lancer or 0, by.skirm or 0))
local bigWolf, bigOk = 0, true
for _ = 1, 20 do                                  -- (a Harvest round past the Wolf pairs' 24: the rest from any group)
    aceRoundOf("Reaper", 28)
    D.waves = {}
    local taken = {}
    local f, n = ROLE.pickRound(56, function(units, want)
        local o, g = pickFlights(units, want, function(u) return taken[u] end)
        for _, u in ipairs(o) do taken[u] = true end
        return o, g
    end, "reaper")
    local b2 = {}
    for _, u in ipairs(f) do local r = ROLE.flight(u) or "?"; b2[r] = (b2[r] or 0) + flightSize(u) end
    if (b2.duelist or 0) ~= 24 or (b2.wolf or 0) ~= 24 or n ~= 56 then bigOk = false end
    bigWolf = math.max(bigWolf, b2.wolf or 0)
end
check(bigOk, "a Harvest round of 56: the duelists' 24, the Wolf pairs' 24, the last 8 from the Lancers / Skirmishers (wolf " .. bigWolf .. ")")
aceRoundOf("Mercenary", 16)
by, total = roundPicks()
check((by.lancer or 0) == 24 and not has(line("roles: round 16"), "Wolf pairs first"),
      "Bounty's round: its rest from any group, as before (no Wolf-first)")
AC.personality.enabled = false
from = aceRoundOf("Mercenary", 16)
check(has(line("roles: round 16", from), "an ace round's mix"), "personality off: ace_mix's line, as before")
AC.personality.enabled = true

---------------------------------------------------------------------------------------------------- spawnFlight
print("spawnFlight: the opener, its altitude, Valkyrie's trap, ACE.squadUp")
local function spawnAs(tk, unit, round)
    fresh(round or 28, tk)
    local from_ = #logs + 1
    local r = spawnFlight(unit)
    return r, from_, spawns[#spawns]
end
local r, from_, sp = spawnAs("Mercenary", "ERA_Unit_03_Dep_Air1")
check(r == 4 and D.squad["ERA_Unit_03_Dep_Air1"] and D.squad["ERA_Unit_03_Dep_Air1"].op == "high"
      and has(line("aces: ERA_Unit_03_Dep_Air1 (Bounty squadron, lancer) opens with high", from_), "within 5.0 km"),
      "a Bounty Lancer flight: opens with high (" .. tostring(line("aces: ERA_Unit_03_Dep_Air1", from_)) .. ")")
check(sp.z >= (CFG.altitude_m[1] + CFG.roles.lancer.alt_add_m) * 100 and sp.z <= (ROLE.LANCER_TOP_M - 500) * 100,
      string.format("... spawned the Lancers' 2 km higher (%.1f km), within their band", sp.z / 100000))
local highs, lows = 0, 0
for _ = 1, 40 do
    r, from_, sp = spawnAs("Mercenary", "ERA_Unit_01_Dep_Air2")
    if sp.z / 100 >= math.min(CFG.altitude_m[1] + 2000, 4500) - 1 and sp.z / 100 <= 4500 + 1e-6 then highs = highs + 1 end
    if sp.z / 100 < CFG.altitude_m[1] + 2000 - 1 and sp.z / 100 < 4500 - 1 then lows = lows + 1 end
end
check(highs == 40 and lows == 0, string.format("a Bounty flight off the Lancers (a duelist 6-ship): alt_add_m higher, top_m 4.5 km at most (%d of 40)", highs))
r, from_ = spawnAs("Legend", "ERA_Unit_05_Dep_Air2")
check(D.squad["ERA_Unit_05_Dep_Air2"].op == "trap" and D.wolf and D.wolf["ERA_Unit_05_Dep_Air2"]
      and D.wolf["ERA_Unit_05_Dep_Air2"].state == "pending" and #D.wolf["ERA_Unit_05_Dep_Air2"].keys == 3,
      "a Valkyrie Wolf 6-ship: opens with trap, its trap (B, D, F) held once its orders are in (ROLE.spawned)")
r, from_ = spawnAs("Demon", "ERA_Unit_05_Dep_Air1")
check(D.squad["ERA_Unit_05_Dep_Air1"].op == "kulbit" and not (D.wolf and D.wolf["ERA_Unit_05_Dep_Air1"]),
      "an Inferno flight filled into a Wolf flight: a kulbit, no trap held")
-- Harvest: kulbit, blink, high in turn; a blink only on a duelist flight's lead
fresh(28, "Reaper")
local ops = {}
for _, u in ipairs({ "ERA_Unit_01_Dep_Air0", "ERA_Unit_01_Dep_Air1", "ERA_Unit_01_Dep_Air2", "ERA_Unit_02_Dep_Air0" }) do
    spawnFlight(u); ops[#ops + 1] = D.squad[u].op
end
check(table.concat(ops, ",") == "kulbit,blink,high,kulbit", "Harvest's openers in turn on duelist flights: " .. table.concat(ops, ","))
spawnFlight("ERA_Unit_03_Dep_Air0")               -- (next: blink, but a Lancer flight has no blink events)
check(D.squad["ERA_Unit_03_Dep_Air0"].op == "high", "on a Lancer flight the blink is skipped (its lead has no blink events): high")
fresh(25, "Phantom")
from_ = #logs + 1
spawnFlight("ERA_Unit_04_Dep_Air0")
check(D.squad["ERA_Unit_04_Dep_Air0"].op == "kulbit" and has(line("aces: ERA_Unit_04_Dep_Air0 (Wraith squadron, lancer) can't show", from_), "it opens with a kulbit"),
      "Wraith filled into a Lancer flight: no blink there, a kulbit (logged)")
fresh(25, "Phantom")
spawnFlight("ERA_Unit_02_Dep_Air1")
check(D.squad["ERA_Unit_02_Dep_Air1"].op == "blink" and has(line("aces: ERA_Unit_02_Dep_Air1 (Wraith squadron"), "its lead blinks off your six (every 20 s at most)"),
      "a Wraith duelist flight: the blink opener, its lead's blinks")
-- not an ace round: no squadron (a recycled flight's entry cleared)
D.roundTier = nil
spawnFlight("ERA_Unit_02_Dep_Air1")
check(D.squad["ERA_Unit_02_Dep_Air1"] == nil, "an ordinary flight in the same unit: its squadron entry cleared")
AC.personality.enabled = false
fresh(28, "Reaper")
spawnFlight("ERA_Unit_01_Dep_Air0")
check(D.squad["ERA_Unit_01_Dep_Air0"] == nil and D.aceSquad["ERA_Unit_01_Dep_Air0"], "personality off: an ace squadron, no opener")
AC.personality.enabled = true
AC.flight.demon.openers = { "none" }
fresh(22, "Demon")
spawnFlight("ERA_Unit_01_Dep_Air1")
plane("ERA_Unit_01_Dep_Air1", 0, KM(3, 0), DIRV(-1, 0), tierOf("Demon"))
from_ = #logs + 1
tickTo(100, 101)
check(D.squad["ERA_Unit_01_Dep_Air1"].op == nil and evs("^RE_SV_RadioTurn") ~= "" and noTell() and evs("^RE_SV_Ace") == ""
      and has(line("aces: ERA_Unit_01_Dep_Air1 (Inferno squadron) meets", from_), "no opener"),
      "openers none: its squadron's tell at first contact (within 4 km), no opener")
AC.flight.demon.openers = { "kulbit" }

---------------------------------------------------------------------------------------------------- the openers
print("first contact and the openers (ACE.squadTick)")
-- Inferno: the kulbit
local U = "ERA_Unit_01_Dep_Air1"
fresh(22, "Demon")
spawnFlight(U)
local p1 = plane(U, 0, KM(3, 0), DIRV(-1, 0), tierOf("Demon"))
local p2 = plane(U, 1, KM(3.2, 0.3), DIRV(-1, 0), tierOf("Demon"))
from_ = #logs + 1
tickTo(100, 102)
check(D.squad[U].contact == nil and evs("^RE_SV_") == "", "3 km off: no contact (kulbit's km 2.5)")
move(p1, KM(2.2, 0))
tickTo(102.25, 102.5)                              -- (first contacts looked for every 0.5 s)
check(D.squad[U].contact and noTell()
      and evs("^RE_SV_RadioTurn") ~= "" and has(line("aces: " .. U .. " (Inferno squadron) meets you 2.2 km off", from_), "told (demon_in)"),
      "2.2 km: its tell, a reversal line, no callout (" .. tostring(line("aces: " .. U, from_)) .. ")")
check(evs("^RE_SV_AceKulbit") == "", "... the kulbit not yet (its lead_s 0.5)")
tickTo(102.75, 103.25)
check(evs("^RE_SV_AceKulbit") == "RE_SV_AceKulbit_02" and has(line("aces: " .. U .. " (Inferno squadron) kulbits as one"), "fired")
      and D.aceMoveAt[U] >= 103 + 12 - 0.01, "lead_s on: RE_SV_AceKulbit_02, the reversals wait 12 s")
tickTo(103.5, 110)
check(#evs("^RE_SV_AceKulbit"):gsub("[^;]", "") == 0 and since(from_, "meets you") == 1, "once a flight")
check(D.rs and D.rs.moves.opener == 1, "counted as an ace move (the round line's openers)")
-- a second Inferno flight: its opener's own tell
local U2 = "ERA_Unit_02_Dep_Air0"
spawnFlight(U2)
plane(U2, 0, KM(0, 2), DIRV(0, -1), tierOf("Demon"))
callouts = {}
tickTo(110.25, 111)
check(noTell() and has(line("aces: " .. U2 .. " (Inferno squadron) meets"), "told (kulbit)"),
      "the round's second Inferno flight: the kulbit tell, not the squadron's again")

-- Bounty: the high salvo
U = "ERA_Unit_03_Dep_Air1"
fresh(16, "Mercenary")
spawnFlight(U)
local q = {}
for k = 0, 3 do q[k] = plane(U, k, KM(4 + k * 0.4, 0, 5), DIRV(-1, 0), tierOf("Mercenary")) end
from_ = #logs + 1
tickTo(100, 100)
check(noTell() and evs("^RE_SV_RadioDive") ~= "" and evs("^RE_SV_Salvo") == "",
      "4.1 km: a dive line (no callout), no salvo yet (lead_s 1.0)")
tickTo(100.25, 101.75)
local sv = evs("^RE_SV_Salvo")
check(sv == "RE_SV_Salvo_08A;RE_SV_Salvo_08B", "lead_s on: the two nearest planes fire (A at once, B gap_s 0.6 later): " .. sv)
check(has(line("aces: " .. U .. "'s opening salvo", from_), "RE_SV_Salvo_08B fired"), "... logged")
-- a row whose missiles aren't in the salvo's slot: none
fresh(16, "Mercenary")
spawnFlight(U)
for k = 0, 3 do plane(U, k, KM(4, 0.1 * k, 5), DIRV(-1, 0), tierOf("Mercenary")) end
local saveSlot = SR.mslSlot
SR.mslSlot = {}
tickTo(100, 101.5)
check(evs("^RE_SV_Salvo") == "" and has(line("aces: " .. U .. "'s opening salvo"), "none of its planes can fire"),
      "a row with its missiles elsewhere: no salvo (logged)")
SR.mslSlot = saveSlot

-- Valkyrie: the trap
U = "ERA_Unit_05_Dep_Air2"
fresh(19, "Legend")
spawnFlight(U)
for k = 0, 5 do plane(U, k, KM(6 + k * 0.2, 0), DIRV(-1, 0), tierOf("Legend")) end
D.wolf[U].state, D.wolf[U].heldAt, D.wolf[U].held = "held", 100, { [1] = true, [3] = true, [5] = true }
for _, x in ipairs(planes) do move(x, KM(3.8 + x.k * 0.05, 0)) end
from_ = #logs + 1
tickTo(100, 100)
check(noTell() and evs("^RE_SV_RadioEnLure") ~= "" and has(line("aces: " .. U .. " (Valkyrie squadron): its trap springs in 8 s", from_), "springs"),
      "3.8 km: a lure line (no callout), its trap springs in 8 s")
tickTo(100.25, 107.75)
check(evs("^RE_SV_Wolf") == "", "nothing before spring_s")
tickTo(108, 108)
check(noTell() and evs("^RE_SV_Radio(E?n?Trap)") ~= "" and has(line("aces: " .. U .. " (Valkyrie squadron): its trap springs on you in 1.0 s"), "told (trap)"),
      "spring_s on: an \"it's a trap\" line (no callout)")
tickTo(108.25, 109.25)
check(evs("^RE_SV_Wolf") == "RE_SV_WolfFree_15B;RE_SV_WolfTurn_15B;RE_SV_WolfFree_15D;RE_SV_WolfTurn_15D;RE_SV_WolfFree_15F;RE_SV_WolfTurn_15F"
      and not WOLF.holding(U) and has(line("roles: " .. U .. " (wolf) trap freed (Valkyrie's trap springs)"), "turned onto the player"),
      "its lead_s on: B, D and F freed and turned onto you (" .. evs("^RE_SV_Wolf") .. ")")
-- still pending at the spring: it waits, then gives up after wait_s
fresh(19, "Legend")
spawnFlight(U)
for k = 0, 5 do plane(U, k, KM(3.5, k * 0.1), DIRV(-1, 0), tierOf("Legend")) end
D.wolf[U].held = { [1] = true }                     -- (WOLF.holding: pending)
tickTo(100, 109)
check(D.squad[U].springAt ~= nil and evs("^RE_SV_Wolf") == "", "the trap not held yet at spring_s: it waits")
D.wolf[U].state, D.wolf[U].heldAt = "held", 109
tickTo(109.25, 111)
check(evs("^RE_SV_WolfFree") == "RE_SV_WolfFree_15B", "held then: sprung")
-- held until first contact (U10's review): a flight that meets you after roles.wolf's hold_max_s still has its trap
local function wolfTo(t0, t1)
    for i = 0, math.floor((t1 - t0) / 0.25 + 0.5) do
        local t = t0 + i * 0.25
        D.now = t; WOLF.tick(t); ACE.squadTick(t, D, false); TELL.tick(t)
    end
end
FLAGS["SV_Up_15"] = 1
fresh(19, "Legend")
spawnFlight(U)
check(D.wolf[U].untilContact == 300 and CFG.roles.wolf.hold_max_s == 60,
      "a Valkyrie trap: held until first contact (300 s at most: openers.trap hold_max_s; roles.wolf's 60 s from the contact)")
for k = 0, 5 do plane(U, k, KM(20 + k * 0.2, 0), DIRV(-1, 0), tierOf("Legend")) end
from_ = #logs + 1
wolfTo(100, 190)
check(WOLF.holding(U) and D.wolf[U].state == "held" and evs("^RE_SV_WolfHold") == "RE_SV_WolfHold_15B;RE_SV_WolfHold_15D;RE_SV_WolfHold_15F"
      and evs("^RE_SV_WolfFree") == "" and since(from_, "trap freed") == 0,
      "held 87 s without meeting anyone (past roles.wolf's 60 s): still held")
for _, x in ipairs(planes) do move(x, KM(3.8 + x.k * 0.05, 0)) end
wolfTo(190.25, 200)
check(noTell() and evs("^RE_SV_RadioEnLure") ~= "" and D.wolf[U].untilContact == nil and D.wolf[U].maxFrom == 190.5
      and evs("^RE_SV_Wolf[FT]") == "RE_SV_WolfFree_15B;RE_SV_WolfTurn_15B;RE_SV_WolfFree_15D;RE_SV_WolfTurn_15D;RE_SV_WolfFree_15F;RE_SV_WolfTurn_15F"
      and has(line("roles: " .. U .. " (wolf) trap freed (Valkyrie's trap springs)", from_), "turned onto the player"),
      "met at last (190 s): its lure line, its trap springs on you then (" .. evs("^RE_SV_Wolf[FT]") .. ")")
-- the contact's own hold_max_s: a spring that never comes (your decoy) is let go roles.wolf's 60 s after the contact
fresh(19, "Legend")
spawnFlight(U)
for k = 0, 5 do plane(U, k, KM(3.8 + k * 0.05, 0), DIRV(-1, 0), tierOf("Legend")) end
D.decoyed = { [U] = 104 }
local saveDec = TAC.decoyed
TAC.decoyed = function(u, now) return D.decoyed and D.decoyed[u] and now < D.decoyed[u] end
wolfTo(100, 101)                                   -- (met at once, its trap pending: the opener stood down by the decoy)
check(D.wolf[U].maxFrom == 100 and has(line("aces: " .. U .. "'s trap not shown"), "decoy"), "met inside your decoy: the trap opener not shown")
TAC.decoyed = saveDec
D.decoyed = nil
from_ = #logs + 1
wolfTo(101.25, 162.75)
check(WOLF.holding(U) and evs("^RE_SV_WolfFree") == "", "held (at 103), not sprung: kept until 60 s after the contact or the hold, the later")
wolfTo(163, 164)
check(evs("^RE_SV_WolfFree") == "RE_SV_WolfFree_15B;RE_SV_WolfFree_15D;RE_SV_WolfFree_15F" and evs("^RE_SV_WolfTurn") == ""
      and has(line("roles: " .. U .. " (wolf) trap freed (held", from_), "since it met you"),
      "60 s after the contact: let go (" .. tostring(line("roles: " .. U .. " (wolf) trap freed", from_)) .. ")")
-- nobody meets it: let go hold_max_s after the hold
AC.personality.openers.trap.hold_max_s = 120
fresh(19, "Legend")
spawnFlight(U)
for k = 0, 5 do plane(U, k, KM(30, k * 0.2), DIRV(0, 1), tierOf("Legend")) end
from_ = #logs + 1
wolfTo(100, 222.75)
check(WOLF.holding(U), "nobody met it: still held before openers.trap hold_max_s (120 s from the hold at 103)")
wolfTo(223, 224)
check(not WOLF.holding(U) and has(line("roles: " .. U .. " (wolf) trap freed (held", from_), "nobody met it"),
      "let go then: " .. tostring(line("roles: " .. U .. " (wolf) trap freed", from_)))
AC.personality.openers.trap.hold_max_s = 0
fresh(19, "Legend")
spawnFlight(U)
check(D.wolf[U].untilContact == nil, "openers.trap hold_max_s 0: held as any Wolf pack's (roles.wolf's hold_max_s from the hold)")
AC.personality.openers.trap.hold_max_s = CFG_DEFAULTS.aces.personality.openers.trap.hold_max_s
FLAGS["SV_Up_15"] = nil
-- not a Wolf flight: the pack turns on you
U = "ERA_Unit_01_Dep_Air0"
fresh(19, "Legend")
spawnFlight(U)
check(D.squad[U].op == "trap", "a Valkyrie flight filled into a duelist 2-ship still shows the trap opener")
plane(U, 0, KM(3, 0), DIRV(-1, 0), tierOf("Legend")); plane(U, 1, KM(3.2, 0), DIRV(-1, 0), tierOf("Legend"))
tickTo(100, 100.5)
check(evs("^RE_SV_AceTurn") == "RE_SV_AceTurn_01" and has(line("aces: " .. U .. " (Valkyrie squadron) has no trap held"), "fired")
      and D.aceMoveAt[U] >= 130, "... with no trap held its pack turns on you (RE_SV_AceTurn_01), the next move 30 s on")

-- Wraith: the blink opener
U = "ERA_Unit_01_Dep_Air1"
fresh(25, "Phantom")
spawnFlight(U)
local lead = plane(U, 0, KM(4, 0), DIRV(-1, 0), tierOf("Phantom"))
plane(U, 1, KM(4.3, 0.2), DIRV(-1, 0), tierOf("Phantom"))
move(lead, KM(3.9, 0))
smokes = 0
tickTo(100, 100.25)
check(noTell() and evs("^RE_SV_RadioSix") ~= "" and evs("^RE_SV_WraithBlink") == "", "3.9 km: a check-your-six line (no callout), no blink yet")
tickTo(100.5, 100.5)
local bl = evs("^RE_SV_WraithBlink")
check(bl == "RE_SV_WraithBlinkBD" or bl == "RE_SV_WraithBlinkBF", "lead_s on: its lead to a spot behind and beside you (heading 0: 135 or 225 deg): " .. bl)
check(smokes == 2, "smoke where it left and where it came out (smoke true as shipped)")
check(D.squad[U].blinkAt == 100.5 + 20 and D.aceMoveAt[U] >= 110.5 and D.squad[U].blinks == 1, "its next blink no sooner than every_s 20, the reversals 10 s")
-- the ground: both sides blocked, dead six then
fresh(25, "Phantom")
spawnFlight(U)
plane(U, 0, KM(3.5, 0), DIRV(-1, 0), tierOf("Phantom"))
groundFn = function(x, y) if y > 1000 or y < -1000 then return 290000 end return 0 end   -- (a ridge either side)
tickTo(100, 100.5)
check(evs("^RE_SV_WraithBlink") == "RE_SV_WraithBlinkBE" and smokes == 2, "the spots beside you over high ground: dead six (180 deg), smoke where it left and came out")
fresh(25, "Phantom")
groundFn = function(x, y) if math.abs(x) < 1 and math.abs(y) < 1 then return 0 end return 299500 end   -- (only under you low)
spawnFlight(U)
plane(U, 0, KM(3.5, 0), DIRV(-1, 0), tierOf("Phantom"))
you = KM(0, 0, 3.0)
tickTo(100, 100.5)
check(evs("^RE_SV_WraithBlink") == "" and has(line("aces: " .. U .. "'s lead didn't blink"), "no spot clear of the ground"),
      "every spot under the ground's clearance: no blink (logged)")

-- Wraith hit before it's met (U10's review): no blink before its tell; met, one blink (its opener), the hit not again
U = "ERA_Unit_01_Dep_Air1"
fresh(25, "Phantom")
groundFn = function() return 0 end
spawnFlight(U)
lead = plane(U, 0, KM(6, 0), DIRV(-1, 0), tierOf("Phantom"))
lead.dmg = { you = 30 }
callouts = {}
tickTo(100, 102)
check(evs("^RE_SV_WraithBlink") == "" and evs("^RE_SV_RadioSix") == "" and D.squad[U].contact == nil,
      "Wraith's lead hit from 6 km, before it's met: no blink, no blink tell (its blinks wait for first contact)")
move(lead, KM(3.9, 0))
from_ = #logs + 1
tickTo(102.25, 103)
check(evs("^RE_SV_RadioSix") ~= "" and noTell() and evs("^RE_SV_WraithBlink") ~= "" and not evs("^RE_SV_WraithBlink"):find(";", 1, true)
      and since(from_, "blinks %(its opener%)") == 1, "met at 3.9 km: its tell, then one blink, the opener's")
tickTo(103.25, 126)
check(not evs("^RE_SV_WraithBlink"):find(";", 1, true) and since(from_, "tell: blink:") == 0,
      "every_s on: no blink for the hit from before it was met (" .. evs("^RE_SV_WraithBlink") .. ")")
-- Harvest met with you behind one of its planes (U10's review): its kulbit, no reversal in the same tick or until it's over
U = "ERA_Unit_01_Dep_Air0"
fresh(28, "Reaper")
spawnFlight(U)
check(D.squad[U].op == "kulbit", "Harvest's first flight: the kulbit opener")
plane(U, 0, KM(2.45, 0.3), DIRV(-1, 0), tierOf("Reaper"))       -- (its lead head-on: no reversal, no blink for it)
plane(U, 1, KM(2.4, 0), DIRV(1, 0), tierOf("Reaper"))           -- (you 2.4 km on this one's six: a reversal's range)
from_ = #logs + 1
tickTo(100, 100.25, true)
check(evs("^RE_SV_RadioHunt") ~= "" and noTell() and evs("^RE_SV_AceTurn") == "" and D.aceMoveAt[U] >= 101.5,
      "met at 2.4 km: its tell; the reversal held until the opener's gone (" .. tostring(D.aceMoveAt[U]) .. ")")
tickTo(100.5, 112.25, true)
check(evs("^RE_SV_AceKulbit") == "RE_SV_AceKulbit_01" and evs("^RE_SV_AceTurn") == "", "its kulbit, and no reversal inside its 12 s")
tickTo(112.5, 115, true)
check(evs("^RE_SV_AceTurn") == "RE_SV_AceTurn_01", "after it: the reversal")
-- a move already in flight at the contact (a reversal from before it): the kulbit waits it out
fresh(28, "Reaper")
spawnFlight(U)
plane(U, 0, KM(2.2, 0), DIRV(-1, 0), tierOf("Reaper"))
D.aceMoveAt = { [U] = 120 }
from_ = #logs + 1
tickTo(100, 119.75, true)
check(evs("^RE_SV_Ace") == "" and has(line("aces: " .. U .. "'s kulbit waits", from_), "a move of the flight is in flight"),
      "a reversal in flight till 120 s: no kulbit before it's over (" .. tostring(line("aces: " .. U .. "'s kulbit waits", from_)) .. ")")
tickTo(120, 120.5, true)
check(evs("^RE_SV_Ace") == "RE_SV_AceKulbit_01" and D.aceMoveAt[U] >= 132, "then the kulbit, the reversals 12 s after it")

---------------------------------------------------------------------------------------------------- the blink tick
print("the blink tick: on your six, a hit, every_s, Harvest's reversal after")
fresh(25, "Phantom")
groundFn = function() return 0 end
spawnFlight(U)
lead = plane(U, 0, KM(10, 0), DIRV(1, 0), tierOf("Phantom"))
D.squad[U].contact = { at = 99, isMe = true, slot = 0, d = 4 }   -- (met already: the opener is past)
tickTo(100, 101)
check(evs("^RE_SV_WraithBlink") == "", "10 km off: nothing")
move(lead, KM(1.5, 0), DIRV(0, 1))                -- (1.5 km off, flying across your nose: you're 90 deg off its tail)
tickTo(101, 101)
check(evs("^RE_SV_WraithBlink") == "" and evs("^RE_SV_RadioSix") == "", "1.5 km off but 90 deg off its tail: nothing (tail_deg 70)")
move(lead, KM(1.5, 0), DIRV(1, 0))                -- (you 1.5 km behind it, on its six)
from_ = #logs + 1
tickTo(101.25, 101.25)
check(evs("^RE_SV_RadioSix") ~= "" and noTell() and evs("^RE_SV_WraithBlink") == "",
      "you on its six: its tell (a check-your-six line, no callout), the blink lead_s later")
tickTo(101.5, 101.75)
check(evs("^RE_SV_WraithBlink") ~= "" and has(line("aces: " .. U .. "'s lead", from_), "you 1500 m on its six"), "... then the blink: " .. tostring(line("aces: " .. U .. "'s lead", from_)))
local n1 = #evs("^RE_SV_WraithBlink"):gsub("[^;]", "")
move(lead, KM(1.5, 0), DIRV(1, 0))
tickTo(102, 121)
check(#evs("^RE_SV_WraithBlink"):gsub("[^;]", "") == n1, "still on its six: none again inside every_s 20")
tickTo(121.25, 122)
check(#evs("^RE_SV_WraithBlink"):gsub("[^;]", "") == n1 + 1, "every_s on: again")
-- on_hit
fresh(25, "Phantom")
spawnFlight(U)
lead = plane(U, 0, KM(6, 0), DIRV(-1, 0), tierOf("Phantom"))
D.squad[U].contact = { at = 99, isMe = true, slot = 0, d = 4 }
tickTo(100, 100.5)
lead.dmg = { you = 30 }
from_ = #logs + 1
tickTo(100.75, 101.5)
check(evs("^RE_SV_WraithBlink") ~= "" and has(line("aces: " .. U .. "'s lead", from_), "you hit it"), "Wraith's lead hit by you: it blinks (on_hit)")
-- a hit inside every_s (F1's review): no blink for it once every_s is over; a hit after it, one
local nHit = #evs("^RE_SV_WraithBlink"):gsub("[^;]", "")
tickTo(101.75, 106)
lead.dmg = { you = 60 }                            -- (5 s after the blink)
from_ = #logs + 1
tickTo(106.25, 124)
check(#evs("^RE_SV_WraithBlink"):gsub("[^;]", "") == nHit and since(from_, "you hit it") == 0,
      "hit again 5 s after its blink: no blink for it when every_s 20 is over (" .. evs("^RE_SV_WraithBlink") .. ")")
lead.dmg = { you = 90 }
tickTo(124.25, 125)
check(#evs("^RE_SV_WraithBlink"):gsub("[^;]", "") == nHit + 1 and has(line("aces: " .. U .. "'s lead", from_), "you hit it"),
      "a hit after every_s: it blinks")
-- Harvest: on its lead's six, the blink first, its reversal held move_gap_s
fresh(28, "Reaper")
U = "ERA_Unit_01_Dep_Air0"
spawnFlight(U)
lead = plane(U, 0, KM(1.2, 0), DIRV(1, 0), tierOf("Reaper"))
D.squad[U].contact = { at = 99, isMe = true, slot = 0, d = 4 }
tickTo(100, 101, true)
check(evs("^RE_SV_WraithBlink") ~= "" and evs("^RE_SV_AceTurn") == "" and evs("^RE_SV_AceKulbit") == "",
      "Harvest's lead with you on its six: it blinks; no reversal")
move(lead, KM(1.2, 0), DIRV(1, 0))
tickTo(101.25, 110, true)
check(evs("^RE_SV_AceTurn") == "" and evs("^RE_SV_AceKulbit") == "", "still on its six: no reversal inside move_gap_s 10")
tickTo(110.25, 112, true)
check(evs("^RE_SV_AceTurn") == "RE_SV_AceTurn_01", "after it: its reversal (Harvest keeps its moves)")
-- Harvest's blink isn't on a hit (on_hit false)
fresh(28, "Reaper")
spawnFlight(U)
lead = plane(U, 0, KM(6, 0), DIRV(-1, 0), tierOf("Reaper"))
D.squad[U].contact = { at = 99, isMe = true, slot = 0, d = 4 }
lead.dmg = { you = 50 }
tickTo(100, 102)
check(evs("^RE_SV_WraithBlink") == "", "Harvest's lead hit: no blink (on_hit false)")
-- your decoy stands it down: no opener, no blink
fresh(22, "Demon")
U = "ERA_Unit_01_Dep_Air1"
spawnFlight(U)
plane(U, 0, KM(2, 0), DIRV(-1, 0), tierOf("Demon"))
D.decoyed = { [U] = 200 }
local saveTac = TAC.decoyed
TAC.decoyed = function(u, now) return D.decoyed and D.decoyed[u] and now < D.decoyed[u] end
from_ = #logs + 1
tickTo(100, 101)
check(evs("^RE_SV_AceKulbit") == "" and has(line("aces: " .. U .. "'s kulbit not shown", from_), "decoy"), "inside your decoy: its kulbit not shown")
TAC.decoyed = saveTac
-- personality off: nothing ticks
AC.personality.enabled = false
fresh(22, "Demon")
D.squad = { [U] = { tk = "demon", op = "kulbit", at = 99, dmgSeen = 0, blinks = 0 } }
plane(U, 0, KM(1, 0), DIRV(-1, 0), tierOf("Demon"))
tickTo(100, 102)
check(evs("^RE_SV_") == "" and D.squad[U].contact == nil, "personality off: no contact, no opener")
AC.personality.enabled = true
-- the round line counts them
fresh(22, "Demon")
spawnFlight(U)
plane(U, 0, KM(2, 0), DIRV(-1, 0), tierOf("Demon"))
tickTo(100, 101)
STATS.roundEnd(101)
for t = 101, 106, 1 do STATS.sample(t, you) end
check(has(line("stats: round 22"), "squadron openers 1, blinks 0"), "the round line: squadron openers 1, blinks 0 (" .. tostring(line("stats: round 22")) .. ")")

---------------------------------------------------------------------------------------------------- co-op
print("co-op")
check(mirroredEvent("RE_SV_WraithBlinkAB") == false and mirroredEvent("RE_SV_AceKulbit_05") == false
      and mirroredEvent("RE_SV_WolfFree_15B") == true, "KEEP_EVENTS: the blinks kept (round the host), the trap's free forwarded")
local standIn = mkObj("BP_OP1022_f16c_CoopPeerB_C_1", KM(0, 0), DIRV(1, 0))
local function joiner(at)
    COOP.open, COOP.role, COOP.slot = true, "host", 0
    M.peers[1] = { obj = standIn, addr = standIn.addr, at = at, rot = { 0, 0, 0 }, alive = true, fresh = true,
                   onAirfield = false, hpPct = 100 }
end
-- a joiner meets Bounty first: its tell to that joiner, the salvo on its copies
U = "ERA_Unit_03_Dep_Air1"
fresh(16, "Mercenary")
spawnFlight(U)
for k = 0, 3 do plane(U, k, KM(60 + k * 0.3, 0, 5), DIRV(-1, 0), tierOf("Mercenary")) end
joiner(KM(57, 0, 5))
sent, callouts = {}, {}
tickTo(100, 102)
check(sentOf("tl|mercenary_in") == "1>tl|mercenary_in|" and noTell() and evs("^RE_SV_Radio") == "",
      "player 2 meets Bounty first: mercenary_in to them only (\"tl\", no number now), not said here")
check(evs("^RE_SV_Salvo") == "" and sentOf(">dv|RE_SV_Salvo_08A|") ~= "" and sentOf(">dv|RE_SV_Salvo_08B|") ~= "",
      "lead_s on: the salvo on player 2's own copies (\"dv\"), none fired here: " .. sentOf(">dv|"))
-- a joiner meets Wraith first: its tell, no blink (round the host only)
U = "ERA_Unit_01_Dep_Air1"
fresh(25, "Phantom")
spawnFlight(U)
plane(U, 0, KM(62, 0), DIRV(-1, 0), tierOf("Phantom"))
joiner(KM(59, 0))
sent = {}
from_ = #logs + 1
tickTo(100, 101)
check(sentOf("tl|phantom_in") ~= "" and evs("^RE_SV_WraithBlink") == "" and has(line("aces: " .. U .. "'s blink is round the host's plane only", from_), "player 2"),
      "player 2 meets Wraith first: its tell, no blink round them (logged)")
-- the squadron's tell on the joiner: its own catalog's lines (no text to name the squadron in now)
check(TELL.known("phantom_in") and CFG.tells.list.phantom_in.args == nil and CFG.tells.list.phantom_in.sure == true,
      "phantom_in: a sure radio tell in the joiner's own catalog (no text, no args)")
-- on a joiner's game: nothing (the host's planes are puppets there)
COOP.open, COOP.role, COOP.slot = true, "join", 1
fresh(22, "Demon"); COOP.open, COOP.role, COOP.slot = true, "join", 1
D.squad = { [U] = { tk = "demon", op = "kulbit", at = 99, dmgSeen = 0, blinks = 0 } }
plane(U, 0, KM(1, 0), DIRV(-1, 0), tierOf("Demon"))
tickTo(100, 102)
check(evs("^RE_SV_") == "" and D.squad[U].contact == nil, "a joiner's game: no contact, no opener")
COOP.open, COOP.role, COOP.slot = false, nil, nil

---------------------------------------------------------------------------------------------------- the tells
print("the squadron tells: radio lines only (the clean up of 2026-10-29)")
fresh(28, "Reaper")
callouts, events = {}, {}
check(TELL.play("reaper_in") == true and evs("^RE_SV_RadioHunt") ~= "" and noTell(), "reaper_in: a hunt line, no callout")
for _, id in ipairs({ "mercenary_in", "legend_in", "demon_in", "phantom_in", "reaper_in" }) do
    local e = CFG.tells.list[id]
    check(e and e.sure == true and e.hud == nil and e.urgent == nil and e.args == nil and #e.radio > 0, id .. ": sure, its lines, nothing for the HUD")
end

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
local mainSrc, spawnSrc, roundsSrc = readAll(MOD .. "/Scripts/sv_main.lua"), readAll(MOD .. "/Scripts/sv_spawn.lua"), readAll(MOD .. "/Scripts/sv_rounds.lua")
local a1, a2 = mainSrc:find('timed("squads", ACE.squadTick, now, D, paused)', 1, true), mainSrc:find('timed("moves", ACE.movesTick, now, D)', 1, true)
check(a1 and a2 and a1 < a2, "sv_main.lua: ACE.squadTick timed as \"squads\", before ACE.movesTick")
local s1 = spawnSrc:find("pcall(ACE.pickOpener, unit, ace.tier, role)", 1, true)
local s2 = s1 and spawnSrc:find("local r = SV_Spawn(unit, x, y, alt * 100, yaw)", s1, true)   -- (spawnFlight's, not spawnBomber's)
local s3 = spawnSrc:find("pcall(ACE.squadUp, unit, ace, role, r)", 1, true)
local s4 = spawnSrc:find("pcall(ROLE.spawned, unit, role, r, ace)", 1, true)
check(s1 and s2 and s3 and s4 and s1 < s2 and s2 < s4 and s4 < s3, "sv_spawn.lua: the opener picked before the spawn, ROLE.spawned then ACE.squadUp after it")
check(has(spawnSrc, 'if role == "wolf" and ace.opener == "trap" then') and has(spawnSrc, 'WOLF.spawned(unit, n, D.now, type(t) == "table" and t.hold_max_s or nil)'),
      "ROLE.spawned: a trap squadron holds its trap until first contact")
check(has(roundsSrc, "ROLE.pickRound(nWant, pick, aceKey or D.roundTier ~= nil)"), "sv_rounds.lua: an ace round draws by its tier's key")
check(has(readAll(MOD .. "/Scripts/main.lua"), 'VERSION = "0.73.47"'), "main.lua VERSION 0.73.47")

logFile:close()
print(fails == 0 and "aces test: all passed" or ("aces test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
