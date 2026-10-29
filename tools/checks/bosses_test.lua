-- bosses_test.lua <mod dir> <work dir> (run by tools/checks/bosses_test.sh): the behaviour roadmap's P7, boss phases
-- (tools/re/BEHAVIOUR_DIRECTOR.md unit 9), on the real sv_core, sv_config, sv_rows, sv_ai, sv_spawn, sv_anomalies,
-- sv_rounds (startRound exposed), sv_ladon, sv_alicorn, sv_stats, sv_tells and sv_coop (M and mirroredEvent exposed),
-- the game stubbed, the bosses stubbed as objects with a position, a heading and health:
--   survival.ini's new sections ([specials.anomaly.pack], [specials.glitch.phases], [specials.ladon.rage],
--     [specials.alicorn.deck]);
--   MINDRIPPER's pack (ANOM.tick): armed with its tell as the field scrambles you, sprung spring_delay_s later, not
--     sprung when you leave the field first, called back once you've been out hold_after_s and min_s after the spring,
--     cooldown_s before the next, nothing with every guard down or the pack off; hunt_only_sprung (ACE.hunt's target
--     write waits for the spring);
--   AB.L..IN's phases (ANOM.glitchTick): phase 2 once two frenzies are over (its tell; blinks at the spot nearest your
--     six), phase 3 at 35 % health (its tell to every player; no frenzy on a hit, no RE_SV_GlitchEcm, its pods switched
--     off, its gun only with you close in front of it, LastTGT every allout_turn_s and when you're behind it; none of the
--     pods up its own logged once; a co-op host's phase-3 gun events its own, never forwarded, a frenzy's forwarded),
--     phase 3 mid-blink (it comes back first), phases off (as before);
--   a Ladon's rage (SPC.ladonTick): the other one shot down: RE_SV_LadonRage<Key>, its tell (no callout), volleys every
--     25 s; both down in one second: none; rage off: none;
--   the ALICORN's deck (SPC.alicornTick): its tell warn_s before (no callout), a Skirmisher 2-ship spawned alt_m over the
--     sea ahead_m off its bow along its heading, every every_s, no more than max_up up, none while dived or while you're
--     at the airfield (a co-op host's while another player flies: launched), after_surface_s after it surfaces,
--     D.deckLeft counted down, any free 2-ship with roles off; its tell only once nothing holds the launch (max_up, the
--     airfield), alt_m never under the pool's 1100 m floor;
--     startRound's D.deckLeft (and its escorts folded in from escort_from, none from a spawn point), never one of the
--     round's own flights (D.taken) and a spare it takes no spare any more;
--   the ALICORN's railguns and VLS (code review of 2026-10-29): once every one seen up is down (or gone), the RAILGUN
--     WARNING off, no more railgun warnings, calls or orders, no VLS call or volley (nor a volley already called); one
--     of two down, never read up, or unreadable: as before; a part found a pass after its siblings looked for again
--     before its kind counts as down (its orders and volleys go on), one found at 0 then given a pass of its own;
--     after a surfacing its call, the railgun's warning radio_gap_s later (the order its lead after that) and the
--     deck's call held a second by that gap (twice at most; a co-op host with tells off by its joiners' gap); tells
--     off: the order 5 s on as before;
--   the main menu's rows (searchSetup on fake tables): the guards' set on every level, AB.L..IN's ECM row (anomEcm's by
--     default, its own with ecm_row);
--   sure tells (the pack's, AB.L..IN's; radio lines only since the clean up of 2026-10-29): said through the gap and
--     their cooldown, a host's to its joiners through the gaps too; never with tells off, between rounds, at the
--     airfield or over the summary, nor within their lines' line_gap_s; no callout in any case; other tells as before;
--   the pack's spring when its event doesn't fire (not logged as sprung); an enraged Ladon's volleys under the gap;
--   co-op: KEEP_EVENTS (the pack and AB.L..IN's LastTGT kept, a Ladon's rage forwarded), AB.L..IN's phase in "rnd" and
--     a joiner's copy's pods switched off in phase 3 (ANOM.clientGlitch);
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
    "\r\n[specials.anomaly.pack]\r\nmin_s = 10\r\n[specials.glitch.phases]\r\nbehind_share = 0.75\r\n" ..
    "[specials.ladon.rage]\r\nvolley_every_s = 20\r\n[specials.alicorn.deck]\r\nmax_flights = 5\r\n")

local clock = 1000                               -- (co-op's levelReady and rate limits)
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.71.5-bosses.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
function NotifyOnNewObject() end
local FA = {}                                    -- FindAllOf by class
function FindAllOf(c) return FA[c] or {} end
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
function SV_Invert() return 1 end
local spawns = {}
function SV_Spawn(unit, x, y, z, yaw)
    spawns[#spawns + 1] = { unit = unit, x = x, y = y, z = z, yaw = yaw }
    return flightSize(unit)
end
function SV_MenuChoice() return 0 end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopSend() return 1 end
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
function nameOf(o) return type(o) == "table" and o.full or "?" end
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
part("sv_ladon.lua"); part("sv_alicorn.lua"); part("sv_stats.lua"); part("sv_tells.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" }, { "\nlocal function mirroredEvent%(name%)", "\nfunction mirroredEvent(name)" },
                           { "\nlocal function onJoinerMessage%(f%)", "\nfunction onJoinerMessage(f)" } })
function searchAircraft(a) return a end
function playerOnAirfield() return grounded end          -- (sv_rounds.lua's own reads where you are)
function addCredits() end
LB.stat, LB.special = function() end, function() end
AMPH.ready = function() return true end
local SP = CFG.specials

local nextAddr = 100
local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end
local function evs(pat, from)
    local t = {}
    for i = from or 1, #events do if events[i]:match(pat) then t[#t + 1] = events[i] end end
    return table.concat(t, ";")
end
local function count(pat, from) local n = 0; for i = from or 1, #events do if events[i]:match(pat) then n = n + 1 end end; return n end
local function said(text, from)
    for i = from or 1, #callouts do if callouts[i].text == text then return callouts[i] end end
    return nil
end
local function deep(t) if type(t) ~= "table" then return t end; local c = {}; for k, v in pairs(t) do c[k] = deep(v) end; return c end
local function KM(x, y, z) return { X = x * 100000, Y = y * 100000, Z = (z or 3) * 100000 } end

-- the player: at `you`, flying along +X (heading 0) at 250 m/s
local you = KM(0, 0)
local vel = { X = 25000, Y = 0, Z = 0 }
local pawn = { addr = 9, full = "BP_PlayerPlane_PP1000_f16c_C_1" }
function pawn:K2_GetActorLocation() return you end
function pawn:GetVelocity() return vel end
function pawn:GetActorForwardVector() return { X = 1, Y = 0, Z = 0 } end
survivalPC = { Pawn = pawn, full = "PC", addr = 8 }

-- an AI plane / actor: a position, a forward vector, health
local function mkObj(full, at, fwd, hp)
    nextAddr = nextAddr + 1
    local o = { full = full, addr = nextAddr, at = at, fwd = fwd or { X = 1, Y = 0, Z = 0 }, HealthInternal = hp or 4500,
                MaxHealth = (hp or 4500) / 10, hidden = false, fired = 0 }
    function o:K2_GetActorLocation() return self.at end
    function o:GetActorForwardVector() return self.fwd end
    function o:GetVelocity() return { X = self.fwd.X * 30000, Y = self.fwd.Y * 30000, Z = 0 } end
    function o:SetActorHiddenInGame(h) self.hidden = h end
    function o:SetActorEnableCollision() end
    function o:GetDamagePercentage() return 0 end
    function o:FireOneShotWeaponWithLocationTracking() self.fired = self.fired + 1 end
    function o:GetNumMaterials() return 0 end
    return o
end
local function run(round, state) D = { round = round or 20, state = state or "fighting", now = 0, up = {}, flown = {}, queue = {}, spare = {} } end

---------------------------------------------------------------------------------------------------- survival.ini
print("survival.ini's new sections")
check(cfgLine and not has(cfgLine, "not used"), "config: every line used (" .. tostring(cfgLine) .. ")")
check(SP.anomaly.pack.min_s == 10 and SP.glitch.phases.behind_share == 0.75 and SP.ladon.rage.volley_every_s == 20
      and SP.alicorn.deck.max_flights == 5, "[specials.anomaly.pack] / [specials.glitch.phases] / [specials.ladon.rage] / [specials.alicorn.deck] read")
check(SP.anomaly.pack.guard_luaset == "NLID_SV_WolfWing" and CFG.behaviour_sets.NLID_SV_WolfWing ~= nil,
      "the guards fly the Wolf trap's set (one of Survival's)")
for _, k in ipairs({ "anomaly", "glitch", "ladon", "alicorn" }) do SP[k] = deep(CFG_DEFAULTS.specials[k]) end
check(SP.anomaly.pack.min_s == 12 and SP.glitch.phases.behind_share == 0.5, "the shipped settings for the rest")
for _, id in ipairs({ "pack", "glitch_six", "glitch_allout", "ladon_rage", "alcn_deck" }) do
    check(TELL.known(id) and CFG.tells.cooldown_s[id] ~= nil, "the tell " .. id .. " is in the catalog")
end

---------------------------------------------------------------------------------------------------- MINDRIPPER's pack
print("MINDRIPPER's pack (ANOM.tick)")
local AN = SP.anomaly
local mind = mkObj("BP_OP0001_f04e_Mindripper_C_1", KM(5, 0), nil, 10000)
local function anomalyRound()
    run(20)
    planes = { { unit = AN.unit, obj = mind, name = "MINDRIPPER" } }
    alive[AN.unit], alive[AN.guard_unit] = 1, 4
    D.special = { kind = "anomaly", state = "hunt", at = 0, healthDone = true }
    ANOM.on = false
    ANOM.pawn = pawn.addr
    AN.portal.enabled = false
    events, callouts = {}, {}
    return D.special
end
local function atk(km_) you = KM(5 - km_, 0) end           -- you km_ west of MINDRIPPER
local function tickA(from, to, step)
    for t = from, to, step or 0.25 do D.now = t; ANOM.tick(t, D.special) end
end
local s = anomalyRound()
atk(5); tickA(0, 2)
check(ANOM.on == false and s.pack == nil and evs("Pack") == "", "5 km from it: no field, the pack held")
local f0 = #logs + 1
atk(2.5); tickA(2.25, 2.25)
check(ANOM.on == true and s.pack == "armed" and has(line("special: MINDRIPPER's pack: your controls", f0), "springs in 1.5 s (told)"),
      "in the field: armed, its tell said: " .. tostring(line("special: MINDRIPPER's pack", f0)))
check(not said("THE PACK SPRINGS") and evs("^RE_SV_Radio(E?n?Trap)") ~= "",
      "the tell: an ambush line, no callout (the field's own callout as ever)")
tickA(2.5, 3.5)
check(evs("^RE_SV_AnomalyPack") == "", "not before spring_delay_s")
tickA(3.75, 3.75)
check(evs("^RE_SV_AnomalyPack") == "RE_SV_AnomalyPackSpring" and s.pack == "sprung" and s.packSprings == 1,
      "spring_delay_s on: RE_SV_AnomalyPackSpring")
atk(5); tickA(4, 8)
check(evs("Hold") == "" and s.fieldOffAt == 4, "out of the field at once: no hold before min_s / hold_after_s")
tickA(8.25, 15.5)
check(evs("Hold") == "", "out 11.5 s but the spring only 11.75 s ago: still loose (min_s 12)")
tickA(15.75, 15.75)
check(evs("^RE_SV_AnomalyPack") == "RE_SV_AnomalyPackSpring;RE_SV_AnomalyPackHold" and s.pack == nil and s.packCool == 35.75,
      "min_s after the spring and hold_after_s out of the field: RE_SV_AnomalyPackHold, cooldown 20 s")
atk(2.5); tickA(16, 35.5)
check(s.pack == nil and count("Spring") == 1, "back in the field inside its cooldown: not armed")
tickA(35.75, 35.75)
check(s.pack == "armed", "its cooldown over: armed again")
atk(5); tickA(36, 36)
check(s.pack == nil and has(line("special: MINDRIPPER's pack: you left"), "not sprung"), "out of the field before it sprang: held, not sprung")
tickA(36.25, 40)
check(count("Spring") == 1, "... and nothing fired")
-- every guard down
s = anomalyRound(); alive[AN.guard_unit] = 0
atk(2.5); tickA(0, 3)
check(s.pack == nil and evs("Pack") == "", "every guard down: no pack")
-- off
s = anomalyRound(); AN.pack.enabled = false
atk(2.5); tickA(0, 3)
check(ANOM.on == true and s.pack == nil and evs("Pack") == "", "pack off: the field as before, no pack")
AN.pack.enabled = true
-- its tell is a sure one (code review of unit 9; a radio line only since the clean up of 2026-10-29): tells off, none
-- (the pack springs anyway); inside its cooldown, said through it
CFG.tells.enabled = false
s = anomalyRound()
f0 = #logs + 1
atk(2.5); tickA(0, 0)
check(s.pack == "armed" and not said("THE PACK SPRINGS") and evs("^RE_SV_Radio") == ""
      and has(line("special: MINDRIPPER's pack: your controls", f0), "(not told: tells off)"),
      "tells off: armed, no line, no callout (" .. tostring(line("special: MINDRIPPER's pack: your controls", f0)) .. ")")
tickA(0.25, 1.5)
check(s.pack == "sprung", "... and it springs spring_delay_s on all the same")
CFG.tells.enabled = true
s = anomalyRound()
TELL.say("pack")                                          -- (said just now: its cooldown would refuse the next)
callouts, events = {}, {}
f0 = #logs + 1
atk(2.5); tickA(3, 3)                                     -- (past radio_gap_s, inside its cooldown 20 s)
check(evs("^RE_SV_Radio(E?n?Trap)") ~= "" and not said("THE PACK SPRINGS") and has(line("special: MINDRIPPER's pack: your controls", f0), "(told)")
      and has(line("tell: pack", f0), "a sure tell through its cooldown"),
      "inside its cooldown: said through it, the other ambush line (" .. tostring(line("tell: pack", f0)) .. ")")
-- its spring's event not fired: not sprung (and not logged as sprung), armed again after cooldown_s
s = anomalyRound()
atk(2.5); tickA(0, 1.25)
eventR = 0
f0 = #logs + 1
tickA(1.5, 1.75)
eventR = 1
check(s.pack == nil and (s.packSprings or 0) == 0 and s.packCool == 21.5 and line("special: MINDRIPPER's pack not sprung", f0) ~= nil
      and line("special: MINDRIPPER's pack sprung", f0) == nil,
      "its spring not fired: held, logged as not sprung (" .. tostring(line("special: MINDRIPPER's pack not sprung", f0)) .. ")")
-- hunt_only_sprung: ACE.hunt's TargetActor waits for the spring
do
    s = anomalyRound()
    local writes = 0
    local bb = { GetValueAsObject = function() return nil end, SetValueAsObject = function() writes = writes + 1 end }
    local g = { unit = AN.guard_unit, name = "PHANTASM 1", tier = CFG.tiers.list[#CFG.tiers.list],
                obj = { full = "g", addr = 77, AIStateComponent = { BlackboardComponent = bb } } }
    ACE.hunt(g)
    check(writes == 1, "hunt_only_sprung off: a guard's target kept on you (the top tier's hunt)")
    AN.pack.hunt_only_sprung = true
    writes = 0; ACE.hunt(g)
    check(writes == 0 and ANOM.packHeld(g), "hunt_only_sprung: held, its target left alone")
    s.pack = "sprung"; ACE.hunt(g)
    check(writes == 1 and not ANOM.packHeld(g), "... sprung: onto you")
    s.pack = nil
    check(not ANOM.packHeld({ unit = "ERA_Unit_01_Dep_Air0" }), "... never another flight")
    D.special = nil
    check(not ANOM.packHeld(g), "... nor outside MINDRIPPER's round (a co-op joiner's copies)")
    AN.pack.hunt_only_sprung = false
end
check(not mirroredEvent("RE_SV_AnomalyPackSpring") and not mirroredEvent("RE_SV_AnomalyPackHold"),
      "co-op: both pack events kept on the host (KEEP_EVENTS)")

---------------------------------------------------------------------------------------------------- AB.L..IN
print("AB.L..IN's phases (ANOM.glitchTick)")
local GL = SP.glitch
local glitch
local function glitchRound(hp)
    run(20)
    glitch = mkObj("BP_OP0010_e18g_Glitch_C_1", KM(1, 0), { X = -1, Y = 0, Z = 0 }, hp or 4500)
    planes = { { unit = GL.unit, obj = glitch, name = "AB.L..IN" } }
    pending = {}
    alive[GL.unit] = 1
    D.special = { kind = "glitch", state = "arrive", at = 0 }
    events, callouts = {}, {}
    you = KM(0, 0)
    ANOM.glitchTick(1.25, D.special)                     -- (arrive_s 1: it shows)
    return D.special
end
local function tickG(from, to, step)
    for t = from, to, step or 0.25 do D.now = t; ANOM.glitchTick(t, D.special) end
end
local function hit(n) glitch.HealthInternal = glitch.HealthInternal - (n or 100) end
local function frenzy(at)                                -- a hit and its frenzy through
    hit(); tickG(at, at + GL.frenzy_s + 0.5)
end
s = glitchRound()
check(s.state == "hunt" and s.phase == 1 and s.hp0 == glitch.HealthInternal, "it appears: phase 1, its health the mark (" .. tostring(s.hp0) .. ")")
tickG(1.5, 2)
local e0 = count("^RE_SV_GlitchEcm")
frenzy(2.25)
check(s.frenzies == 1 and s.phase == 1 and (s.blinks or 0) > 0 and not s.frenzyUntil, "a hit: frenzy 1 (" .. tostring(s.blinks) .. " blinks), still phase 1")
local f1 = #logs + 1
local c1 = #callouts + 1
frenzy(10)
check(s.frenzies == 2 and s.phase == 2 and has(line("special: AB.L..IN phase 2 (from 1)", f1), "2 frenzies over"),
      "two frenzies over: phase 2 (" .. tostring(line("special: AB.L..IN phase 2", f1)) .. ")")
check(not said("IT'S ON YOUR SIX", c1) and evs("^RE_SV_RadioSix") ~= "", "its tell: a check-your-six line, no callout")
-- phase 2: the blinks at your six (you fly +X, heading 0: your six is bearing 180, spot G on ring A or B)
GL.phases.behind_share = 1.0
local b0, n0 = #events + 1, s.blinks
frenzy(20)
local behind, other = 0, 0
for i = b0, #events do
    local ev = events[i]
    if ev:match("^RE_SV_GlitchBlink_") then if ev:match("^RE_SV_GlitchBlink_[AB]G$") then behind = behind + 1 else other = other + 1 end end
end
check(behind > 0 and other == 0 and s.behindBlinks == behind, string.format("phase 2, behind_share 1: every blink at your six (%d at spot G, %d elsewhere)", behind, other))
check(has(line("special: AB.L..IN blink"), "behind you") or has(line("special: AB.L..IN blink " .. (n0 + 1) .. " behind"), "spot 180"),
      "... logged: " .. tostring(line("special: AB.L..IN blink")))
vel = { X = 0, Y = 25000, Z = 0 }                         -- (now flying +Y, heading 90: your six bearing 270, spot J)
b0 = #events + 1
frenzy(30)
check(evs("^RE_SV_GlitchBlink_", b0):gsub("RE_SV_GlitchBlink_[AB]J", ""):gsub(";", "") == "" and evs("^RE_SV_GlitchBlink_", b0) ~= "",
      "flying +Y the blinks follow your six (spot J, bearing 270)")
vel = { X = 25000, Y = 0, Z = 0 }
GL.phases.behind_share = 0
b0 = #events + 1
frenzy(40)
check(evs("^RE_SV_GlitchBlink_[AB]G$", b0) == "" or count("^RE_SV_GlitchBlink_", b0) > 2, "behind_share 0: the blinks round you as before")
GL.phases.behind_share = 0.5
check(count("^RE_SV_GlitchEcm") > e0, "phases 1-2: its ECM pod fired every ecm_every_s")
-- phase 3: at 35 % of its health
local pod = { full = "BP_wp_ecm_a0_C_1", addr = 501, bJammingEnable = true, bSupportEnable = true }
function pod:GetOwner() return glitch end
function pod:GetInstigator() return nil end
local other_pod = { full = "BP_wp_ecm_a0_C_2", addr = 502, bJammingEnable = true, bSupportEnable = true }
function other_pod:GetOwner() return mind end
function other_pod:GetInstigator() return nil end
FA.BP_wp_ecm_a0_C = { pod, other_pod }
f1, c1 = #logs + 1, #callouts + 1
local ecm3 = count("^RE_SV_GlitchEcm")
local g3 = #events + 1
glitch.HealthInternal = math.floor(s.hp0 * 0.34)
you = KM(3, 0)                                            -- (2 km behind it: it flies -X, you're east of it)
tickG(50, 50)
check(s.phase == 3 and has(line("special: AB.L..IN phase 3 (from 2)", f1), "at 34 % of its health"), "at 34 % of its health: phase 3")
check(not said("ITS ECM IS DOWN", c1) and evs("^RE_SV_RadioGlitchEcm", g3) == "RE_SV_RadioGlitchEcm",
      "its tell: \"it's not jamming anymore\", no callout")
check(pod.bJammingEnable == false and pod.bSupportEnable == false and other_pod.bJammingEnable == true
      and has(line("special: AB.L..IN's ECM pods off"), "1 of 1"), "its own pods switched off (not another plane's)")
tickG(50.25, 80)
check(count("^RE_SV_GlitchEcm") == ecm3, "phase 3: no more RE_SV_GlitchEcm (30 s on)")
local fz = s.frenzies
hit(); tickG(80.25, 82)
check(not s.frenzyUntil and s.frenzies == fz, "a hit in phase 3: no frenzy")
-- LastTGT: once phase 3 starts (+1 s), and at once (3 s apart) with you behind it, else every allout_turn_s
check(count("^RE_SV_GlitchTurn", g3) >= 10 and has(line("special: AB.L..IN LastTGT"), "you behind it"),
      "you behind it within 3 km: LastTGT every allout_behind_s (" .. count("^RE_SV_GlitchTurn", g3) .. " in 32 s)")
local t0 = count("^RE_SV_GlitchTurn")
you = KM(1, 3)                                            -- (3 km to its side: not behind it)
tickG(82.25, 102.25)
local nT = count("^RE_SV_GlitchTurn") - t0
check(nT == 2, "you off its tail: LastTGT every allout_turn_s 10 (" .. nT .. " in 20 s)")
-- its guns: only with you within 1.5 km and 20 deg of its nose
local gun0, fire0 = count("^RE_SV_GlitchGun"), glitch.fired
tickG(102.5, 105)
check(count("^RE_SV_GlitchGun") == gun0 and glitch.fired == fire0, "you off its nose: its gun quiet")
you = KM(0, 0.1)                                          -- (1 km ahead of it, 6 deg off its nose)
tickG(105.25, 107.25)
local nG = count("^RE_SV_GlitchGun") - gun0
check(nG == 5 and glitch.fired > fire0 and has(line("special: AB.L..IN's guns all out"), "1.0 km off its nose"),
      string.format("you close in front of it: RE_SV_GlitchGun every allout_gun_s 0.5 (%d in 2 s) and the led shots (%d)", nG, glitch.fired - fire0))
you = KM(-1, 0)                                           -- (2 km ahead: out of allout_range_km)
gun0 = count("^RE_SV_GlitchGun")
tickG(107.5, 109)
check(count("^RE_SV_GlitchGun") == gun0, "2 km in front of it: out of allout_range_km, quiet")
-- a co-op host: phase 3's gun events on its own game alone (hot3 is the host's geometry; forwarded, each joiner's copy
-- fired at that joiner: code review of 2026-10-29, bosses-3); a frenzy's still forwarded
do
    local sentB, rawSend = {}, SV_CoopSend
    SV_CoopSend = function(msg) sentB[#sentB + 1] = msg; return 1 end
    local function fwd() local n = 0; for _, m in ipairs(sentB) do if m == "ev|RE_SV_GlitchGun" then n = n + 1 end end; return n end
    COOP.open, COOP.role, COOP.slot = true, "host", 0
    you = KM(0, 0.1)
    gun0 = count("^RE_SV_GlitchGun")
    local fH = #logs + 1
    tickG(109.25, 111.25)
    check(count("^RE_SV_GlitchGun") - gun0 == 5 and fwd() == 0 and has(line("special: AB.L..IN's phase-3 gun events on the host alone", fH), "fire their own"),
          string.format("a co-op host close in front of it in phase 3: RE_SV_GlitchGun here (%d in 2 s), none forwarded (%d; logged)",
              count("^RE_SV_GlitchGun") - gun0, fwd()))
    local sF = glitchRound()
    tickG(1.5, 1.5)
    sentB = {}
    hit(); tickG(1.75, 3)
    check(sF.frenzyUntil and fwd() > 0, "... a frenzy's gun events forwarded as before (" .. fwd() .. ")")
    SV_CoopSend = rawSend
    COOP.open, COOP.role, COOP.slot = false, nil, nil
    s = sF
end
-- none of the pods up its own: that's logged too, once (a tester greps "ECM pods off"; code review of 2026-10-29)
do
    local sZ = glitchRound()
    FA.BP_wp_ecm_a0_C = { other_pod }
    glitch.HealthInternal = math.floor(sZ.hp0 * 0.3)
    local fZ = #logs + 1
    tickG(1.5, 8)
    local nZ = 0
    for i = fZ, #logs do if logs[i]:find("^special: AB%.L%.%.IN's ECM pods off") then nZ = nZ + 1 end end
    check(sZ.phase == 3 and nZ == 1 and has(line("special: AB.L..IN's ECM pods off", fZ), "none of its own found (1 BP_wp_ecm_a0 up"),
          "phase 3 with none of the pods up its own: logged once (" .. tostring(line("special: AB.L..IN's ECM pods off", fZ)) .. ")")
    pod.bJammingEnable, pod.bSupportEnable = true, true
    FA.BP_wp_ecm_a0_C = { pod, other_pod }
    tickG(8.25, 12)
    check(pod.bJammingEnable == false and has(line("special: AB.L..IN's ECM pods off", fZ), "1 of 1"), "... its own pod up later: switched off, and that logged")
end
-- phase 3 while it's gone mid-blink: it comes back, then the frenzy is over
s = glitchRound()
s.phase = 2
tickG(1.5, 1.5)                                           -- (its health read once: a hit is a drop from it)
hit(); tickG(1.75, 2.75)
check(s.frenzyUntil ~= nil, "a frenzy in phase 2")
for _ = 1, 20 do
    if s.vanished then break end
    D.now = D.now + 0.25; ANOM.glitchTick(D.now, s)
end
check(glitch.hidden == true, "... gone in a puff")
glitch.HealthInternal = math.floor(s.hp0 * 0.2)
local tn = D.now
tickG(tn + 0.25, tn + 0.25)
check(s.phase == 3 and glitch.hidden == false and not s.vanished, "phase 3 mid-blink: it's back the same tick")
tickG(tn + 0.5, tn + 0.5)
check(not s.frenzyUntil, "... and its frenzy over the next")
-- phases off: as before
GL.phases.enabled = false
s = glitchRound()
tickG(1.5, 1.5)
for k = 1, 3 do frenzy(2 + k * 10) end
glitch.HealthInternal = math.floor(s.hp0 * 0.2)
local ecmOff = count("^RE_SV_GlitchEcm")
hit(); tickG(40, 60)
check(s.phase == 1 and s.frenzies == 4 and count("^RE_SV_GlitchEcm") > ecmOff and count("^RE_SV_GlitchTurn") == 0,
      "phases off: one phase (frenzies on every hit, its ECM up, no LastTGT)")
GL.phases.enabled = true
check(not mirroredEvent("RE_SV_GlitchTurn") and mirroredEvent("RE_SV_GlitchGun") and mirroredEvent("RE_SV_GlitchEcm"),
      "co-op: its LastTGT kept on the host (the RE_SV_Glitch rule), its gun and ECM forwarded as before")

---------------------------------------------------------------------------------------------------- the Ladons
print("a Ladon's rage (SPC.ladonTick)")
local LA = SP.ladon
local kot, mishka
local function ladonRound()
    run(14)
    D.special = { kind = "ladon", state = "run", at = 0, runs = 0, planeFrom = 1, scaledN = 2,
                  units = { Kot = { unit = "SV_Unit_LadonKot", alive = true, runs = 0 },
                            Mishka = { unit = "SV_Unit_LadonMishka", alive = true, runs = 0 } } }
    kot, mishka = mkObj("Ladon_Kot", KM(5, 0)), mkObj("Ladon_Mishka", KM(5, 2))
    planes = { { unit = "SV_Unit_LadonKot", obj = kot, dist = 5 }, { unit = "SV_Unit_LadonMishka", obj = mishka, dist = 5 } }
    alive.SV_Unit_LadonKot, alive.SV_Unit_LadonMishka = 1, 1
    FLAGS = {}
    AF.bomb, AF.down = 0, false
    events, callouts = {}, {}
    return D.special
end
local function tickL(from, to)
    for t = from, to do D.now = t; SPC.ladonTick(t, D.special); TELL.tick(t) end
end
s = ladonRound()
tickL(0, 40)
local v0 = count("^RE_SV_LadonVolley")
alive.SV_Unit_LadonKot = 0
planes[1].down = true
f1 = #logs + 1
local mv0 = count("^RE_SV_LadonVolleyMishka")
tickL(41, 41)
local mv1 = count("^RE_SV_LadonVolleyMishka")
local M_ = s.units.Mishka
check(M_.rage and s.raged == "Mishka" and evs("^RE_SV_LadonRage") == "RE_SV_LadonRageMishka",
      "KOT down: MISHKA enraged (RE_SV_LadonRageMishka)")
check(not said("MISHKA ENRAGED") and evs("^RE_SV_RadioLadonRage") ~= "", "its tell, \"the hostile's changed course\" (no callout)")
check(has(line("special: Ladon MISHKA enraged", f1), "volleys every 25 s"), "logged: " .. tostring(line("special: Ladon MISHKA enraged", f1)))
local va = {}
for t = 42, 120 do
    local n = count("^RE_SV_LadonVolleyMishka")
    tickL(t, t)
    if count("^RE_SV_LadonVolleyMishka") > n then va[#va + 1] = t end
end
check(#va >= 3 and va[1] == 46 and va[2] - va[1] == 25 and va[3] - va[2] == 25 and mv1 == mv0,
      "its volleys: the next first_s 5 after its rage (not with it), then every 25 s (" .. table.concat(va, ", ") .. ")")
check(has(line("special: Ladon MISHKA fires"), ", enraged"), "the volley lines say enraged")
do                                                        -- (enraged, the other's volley_gap_s doesn't hold it)
    local gap0 = LA.volley_gap_s
    LA.volley_gap_s = 1000
    local nv = count("^RE_SV_LadonVolleyMishka")
    s.volleyAny = D.now
    M_.volleyAt = D.now + 1
    tickL(D.now + 1, D.now + 1)
    check(count("^RE_SV_LadonVolleyMishka") == nv + 1, "enraged: its volley through the gap the other's last set (volley_gap_s 1000)")
    LA.volley_gap_s = gap0
    s.nextAt = nil                                        -- (the pass below in the same second)
end
FLAGS.SV_LadonRunMishka = 1
tickL(121, 121)
check(has(line("special: Ladon MISHKA's pass over the airfield"), "(enraged"), "its next pass logged as enraged")
alive.SV_Unit_LadonMishka = 0
tickL(122, 122)
check(s.state == "done" and count("^RE_SV_LadonRage") == 1, "MISHKA down: the round done, no second rage")
-- both down in one second
s = ladonRound()
tickL(0, 5)
alive.SV_Unit_LadonKot, alive.SV_Unit_LadonMishka = 0, 0
tickL(6, 6)
check(evs("^RE_SV_LadonRage") == "" and not said("MISHKA ENRAGED") and not said("KOT ENRAGED"), "both down in the same second: no rage")
-- rage off
LA.rage.enabled = false
s = ladonRound()
tickL(0, 10); alive.SV_Unit_LadonKot = 0; tickL(11, 11)
check(evs("^RE_SV_LadonRage") == "" and not s.units.Mishka.rage, "rage off: KOT down, MISHKA as before")
LA.rage.enabled = true
check(mirroredEvent("RE_SV_LadonRageMishka"), "co-op: RE_SV_LadonRage<Key> forwarded (harmless: the copies follow the stream)")

---------------------------------------------------------------------------------------------------- the ALICORN's deck
print("the ALICORN's deck (SPC.alicornTick)")
local AL = SP.alicorn
local core
SR.usable = SR.usable or {}
for _, a in ipairs({ "f02a_common", "j39e_common", "f35c_common", "f16c_common", "m29a_common", "f18e_common", "m21b_common" }) do SR.usable[a] = true end
local function alicornRound(round)
    run(round or 14)
    D.deckLeft = 3
    core = mkObj("BP_MP028_dummy_emlmcore_Base_C_1", { X = -2000000, Y = -550000, Z = -500 }, { X = 0.8, Y = -0.6, Z = 0 })
    FA[AL.core_class] = { core }
    alive.SV_Unit_Alicorn = 1
    for _, u in ipairs(CFG.pool) do alive[u] = 0 end
    D.special = { kind = "alicorn", state = "sail", at = 0, tanks = 4, coreOpen = false, dived = false,
                  nextDive = 1e9, nextRail = 1e9, nextVolley = 1e9 }
    ROLE.live = { duelist = true, lancer = true, wolf = true, skirm = true }
    events, callouts, spawns = {}, {}, {}
    grounded = false
    you = KM(-15, -5)
    return D.special
end
local function tickC(from, to)
    for t = from, to do D.now = t; SPC.alicornTick(t, D.special); TELL.tick(t) end
end
s = alicornRound()
tickC(0, 21)
check(#spawns == 0 and evs("^RE_SV_RadioAlcnDeck") == "", "nothing off its deck before first_s - warn_s")
tickC(22, 22)
check(evs("^RE_SV_RadioAlcnDeck") ~= "" and not said("PLANES LAUNCHING") and #callouts == 0,
      "warn_s 3 before: \"planes launching from the carrier\" (no callout)")
tickC(23, 25)
local sp1 = spawns[1]
check(#spawns == 1 and ROLE.of[sp1.unit] == "skirm" and flightSize(sp1.unit) == 2, "first_s 25: a Skirmisher 2-ship (" .. tostring(sp1 and sp1.unit) .. ")")
check(sp1 and math.abs(sp1.x - (core.at.X + 0.8 * 80000)) < 1 and math.abs(sp1.y - (core.at.Y - 0.6 * 80000)) < 1
      and math.abs(sp1.z - 120000) < 1 and math.abs(sp1.yaw - (math.deg(math.atan(-0.6, 0.8)) % 360)) < 0.01,
      string.format("ahead_m 800 off its bow, alt_m 1200 over the sea, along its heading (x %.0f, y %.0f, z %.0f, yaw %.1f)",
          sp1 and sp1.x or -1, sp1 and sp1.y or -1, sp1 and sp1.z or -1, sp1 and sp1.yaw or -1))
check(D.up[sp1.unit] and D.deckLeft == 2 and has(line("special: the Alicorn's deck launch 1"), "(skirm), 2 aircraft at 1200 m, 2 launches left"),
      "up, counted (D.deckLeft 2): " .. tostring(line("special: the Alicorn's deck launch 1")))
check(has(line("round 14: " .. sp1.unit), "at the Alicorn's deck"), "spawnFlight's line: at the Alicorn's deck")
alive[sp1.unit] = 2
tickC(26, 59)
check(#spawns == 1, "nothing for every_s 35")
tickC(60, 60)
local sp2 = spawns[2]
check(#spawns == 2 and sp2.unit ~= sp1.unit and ROLE.of[sp2.unit] == "skirm", "every_s on: the other Skirmisher 2-ship (" .. tostring(sp2 and sp2.unit) .. ")")
alive[sp2.unit] = 2
local cw, ew = #callouts + 1, #events + 1
tickC(61, 100)
check(#spawns == 2 and has(line("special: the Alicorn's deck waits"), "2 of its flights up"), "max_up 2 up: the deck waits")
check(evs("^RE_SV_RadioAlcnDeck", ew) == "", "... untold while it waits (its tell only once the launch can go)")
alive[sp1.unit] = 0; D.up[sp1.unit] = nil
grounded = true
tickC(101, 104)
check(#spawns == 2 and evs("^RE_SV_RadioAlcnDeck", ew) == "", "one down, but you're at the airfield: waits, untold")
grounded = false
tickC(105, 105)
check(#spawns == 2 and evs("^RE_SV_RadioAlcnDeck", ew) ~= "" and #callouts == 0, "you took off: its tell first")
tickC(106, 107)
check(#spawns == 2, "... and the launch not before warn_s")
tickC(108, 108)
check(#spawns == 3 and D.deckLeft == 0, "warn_s after its tell: launched (the round's last, D.deckLeft 0)")
alive[spawns[3].unit] = 0; D.up[spawns[3].unit] = nil; alive[sp2.unit] = 0; D.up[sp2.unit] = nil
tickC(106, 200)
check(#spawns == 3, "D.deckLeft 0: no more")
-- dived: none; surfaced: after_surface_s
s = alicornRound()
s.nextDive = 10
tickC(0, 10)                                              -- (the dive at 10 s: where it sailed, -5 m)
core.at = { X = core.at.X, Y = core.at.Y, Z = -500000 }   -- (down under the sea while dived)
tickC(11, 40)
check(s.dived and #spawns == 0 and evs("^RE_SV_RadioAlcnDeck") == "", "dived from 10 s (still 5 km down at 40 s): no launch, no call")
core.at = { X = core.at.X, Y = core.at.Y, Z = -500 }
tickC(41, 41)
check(not s.dived and s.deckNext == 41 + AL.deck.after_surface_s, "surfaced: the next launch after_surface_s (6) on")
tickC(42, 47)
check(#spawns == 1, "... launched " .. tostring(#spawns))
-- roles off: any free 2-ship
s = alicornRound()
ROLE.live = nil
tickC(0, 25)
check(#spawns == 1 and flightSize(spawns[1].unit) == 2 and has(line("special: the Alicorn's deck launch 1"), "(roles off)"),
      "roles off: any free pool 2-ship (" .. tostring(spawns[1] and spawns[1].unit) .. ")")
-- alt_m under the pool's floor: 1100 m
AL.deck.alt_m = 600
s = alicornRound()
tickC(0, 25)
check(#spawns == 1 and math.abs(spawns[1].z - 110000) < 1 and has(line("special: the Alicorn's deck launch 1"), "at 1100 m (alt_m under the pool's floor)"),
      "alt_m 600: launched at the 1100 m floor (" .. tostring(spawns[1] and spawns[1].z) .. ")")
AL.deck.alt_m = CFG_DEFAULTS.specials.alicorn.deck.alt_m
-- a co-op host down at the airfield: it launches while another player flies (othersFlying; user, 2026-10-29: "the game
-- isn't paused for the other players"), and waits as solo while they're down too
do
    local M = _G.M
    local peersWas = M.peers
    COOP.open, COOP.role, COOP.slot = true, "host", 0
    M.peers = { [1] = { at = KM(10, 0), alive = true, fresh = true, onAirfield = false, hpPct = 100 } }
    s = alicornRound()
    grounded = true
    local f0 = #logs + 1
    tickC(0, 25)
    check(#spawns == 1 and has(line("tell: alcn_deck to every joiner", f0), "(\"tl\")") and evs("^RE_SV_RadioAlcnDeck") == ""
          and has(line("special: the Alicorn's deck launch 1", f0), "you're down at the airfield, 1 other player(s) flying"),
          "a co-op host down at the airfield, player 2 flying: its call to the joiners only (the host's down), launched at first_s (logged)")
    M.peers[1].onAirfield = true
    s = alicornRound()
    grounded = true
    tickC(0, 40)
    check(#spawns == 0 and evs("^RE_SV_RadioAlcnDeck") == "", "... player 2 down at the airfield too: waits, untold")
    M.peers, COOP.open, COOP.role, COOP.slot = peersWas, false, nil, nil
    grounded = false
end
-- off
AL.deck.enabled = false
s = alicornRound()
tickC(0, 60)
check(#spawns == 0, "deck off: none")
AL.deck.enabled = true
ROLE.live = nil

---------------------------------------------------------------------------------------------------- the ALICORN's arms
-- (code review of 2026-10-29: its railgun's tell, RAILGUN WARNING and order, and its VLS call and volley, came every
-- minute after the player had shot them all down)
print("the ALICORN's railguns and VLS (SPC.alicornTick: none of their tells or orders once they're down)")
local RAIL = "BP_BA002_alcn_emls_Base_C"
local VLS = { "BP_BA002_alcn_vlsL1_Base_C", "BP_BA002_alcn_vlsL2_Base_C", "BP_BA002_alcn_vlsR1_Base_C", "BP_BA002_alcn_vlsR2_Base_C" }
local rails, vlss, tl
local function armsRound(rail0)
    s = alicornRound()
    D.deckLeft = 0
    s.nextRail, s.nextVolley = 10, 12                    -- (warned at 5, the order at 10, every 60 s; the VLS' call at 12)
    rails = { mkObj(RAIL .. "_1", KM(0, 0), nil, rail0 or 1600), mkObj(RAIL .. "_2", KM(0, 0), nil, rail0 or 1600) }
    FA[RAIL] = rails
    vlss = {}
    for i, c in ipairs(VLS) do vlss[i] = mkObj(c .. "_1", KM(0, 0), nil, 1000); FA[c] = { vlss[i] } end
    tl = {}
    return s
end
local function tickT(from, to)                            -- (tl: each event and callout with its second)
    for t = from, to do
        local e0, c0 = #events, #callouts
        D.now = t; SPC.alicornTick(t, D.special); TELL.tick(t)
        for i = e0 + 1, #events do tl[#tl + 1] = { t, events[i] } end
        for i = c0 + 1, #callouts do tl[#tl + 1] = { t, callouts[i].text } end
    end
end
local function at(what, from, to)                         -- the seconds `what` came (an event pattern or a callout text)
    local t = {}
    for _, e in ipairs(tl) do
        if e[1] >= (from or 0) and e[1] <= (to or 1e9) and (e[2] == what or e[2]:match(what)) then t[#t + 1] = e[1] end
    end
    return table.concat(t, ",")
end
local function cleanArms() FA[RAIL] = nil; for _, c in ipairs(VLS) do FA[c] = nil end end
s = armsRound()
f0 = #logs + 1
tickT(0, 29)
check(at("^RE_SV_RadioAlcnRail") == "5" and at("^RE_SV_AlcnAlertOn$") == "5" and at("^RE_SV_AlcnRailgun$") == "10"
      and at("^RE_SV_RadioAlcnVls$") == "12" and at("^RE_SV_AlcnVolley$") == "13", "all up: the railgun warned at 5, its order at 10, the VLS' call at 12 and volley at 13")
check(has(line("special: the Alicorn's railguns found:", f0), "found: 2 (kept;") and has(line("special: the Alicorn's VLS found:", f0), "found: 4 (kept;"),
      "... the parts found logged once kept (2 railguns, 4 VLS: the in-game test's counts)")
rails[1].HealthInternal = 0                               -- (one railgun down: the other still fires)
tickT(30, 65)
check(at("^RE_SV_RadioAlcnRail", 30) == "65" and at("^RE_SV_AlcnAlertOn$", 30) == "65" and not (s.armsDown or {}).rail,
      "one railgun down, the other up: warned again at 65")
f0 = #logs + 1
rails[2].HealthInternal = 0                               -- (the other shot down inside the warning, before its order)
tickT(66, 200)
local railDown = line("special: the Alicorn's railguns are down", f0)
check((s.armsDown or {}).rail and at("^RE_SV_AlcnAlertOff$", 66) == "66" and at("^RE_SV_AlcnRailgun$", 66) == ""
      and at("^RE_SV_RadioAlcnRail", 66) == "" and at("^RE_SV_AlcnAlertOn$", 66) == "",
      "both down: the RAILGUN WARNING off at once (66), no order at 70, no warning or call for 135 s after")
check(has(railDown, "(2 found, none up): its RAILGUN WARNING off, no more railgun warnings or orders"), "... logged: " .. tostring(railDown))
check(at("^RE_SV_RadioAlcnVls$", 66) == "102,147,192" and at("^RE_SV_AlcnVolley$", 66) == "103,148,193", "... its VLS still called and fired every 45 s")
for _, o in ipairs(vlss) do o.HealthInternal = 0 end
f0 = #logs + 1
tickT(201, 400)
check((s.armsDown or {}).vls and at("^RE_SV_RadioAlcnVls$", 201) == "" and at("^RE_SV_AlcnVolley$", 201) == ""
      and has(line("special: the Alicorn's VLS are down", f0), "(4 found, none up): no more VLS calls or volleys"),
      "every VLS down: no call or volley (" .. tostring(line("special: the Alicorn's VLS are down", f0)) .. ")")
local nDown = 0
for _, l in ipairs(logs) do if l:find("^special: the Alicorn's %a+ are down") then nDown = nDown + 1 end end
check(nDown == 2, "... each logged once (" .. nDown .. ")")
-- the VLS down between its call and its volley: no volley
s = armsRound()
tickT(0, 11)
for _, o in ipairs(vlss) do o.HealthInternal = 0 end
tickT(12, 20)
check(at("^RE_SV_RadioAlcnVls$") == "12" and at("^RE_SV_AlcnVolley$") == "", "its VLS down in the call's lead: the call at 12, no volley at 13")
-- gone (no longer valid) counts as down, as a tank; the parts are kept once found, looked for again only before they
-- count as down
s = armsRound()
tickT(0, 20)
local finds = 0
local rawFind = FindAllOf
FindAllOf = function(c) if c == RAIL then finds = finds + 1 end return rawFind(c) end
for _, o in ipairs(rails) do o.gone = true end
tickT(21, 100)
FindAllOf = rawFind
check((s.armsDown or {}).rail and at("^RE_SV_AlcnRailgun$", 21) == "" and has(line("special: the Alicorn's railguns are down"), "(0 found, none up)"),
      "railguns seen up, then gone: down")
check(finds == 1, "... the railguns kept once found: one FindAllOf of them before they counted as down, none after (" .. finds .. ")")
-- a part found a pass after its siblings (the railguns are their hatches' grandchildren): looked for again before its
-- kind counts as down, so the first ones shot down don't silence it (F4's review: tracked from the first pass only,
-- the second railgun's orders and two VLS' volleys stopped)
s = armsRound()
FA[RAIL], FA[VLS[3]], FA[VLS[4]] = { rails[1] }, {}, {}
tickT(0, 1)                                               -- (the first parts pass: one railgun, two VLS)
FA[RAIL], FA[VLS[3]], FA[VLS[4]] = rails, { vlss[3] }, { vlss[4] }
tickT(2, 20)
f0 = #logs + 1
rails[1].HealthInternal, vlss[1].HealthInternal, vlss[2].HealthInternal = 0, 0, 0
tickT(21, 80)
check(not (s.armsDown or {}).rail and at("^RE_SV_AlcnAlertOn$", 21) == "65" and at("^RE_SV_AlcnRailgun$", 21) == "70"
      and has(line("special: the Alicorn's railguns: 1 more found", f0), "(2 in all, 1 up)"),
      "the second railgun found a pass late, the first shot down: looked for again, warned at 65, its order at 70 ("
      .. tostring(line("special: the Alicorn's railguns:", f0)) .. ")")
check(not (s.armsDown or {}).vls and at("^RE_SV_RadioAlcnVls$", 21) == "57" and at("^RE_SV_AlcnVolley$", 21) == "58"
      and has(line("special: the Alicorn's VLS: 2 more found", f0), "(4 in all, 2 up)"),
      "two VLS found a pass late, the first two shot down: their call at 57, the volley at 58")
finds = 0
FindAllOf = function(c) if c == RAIL then finds = finds + 1 end return rawFind(c) end
rails[2].HealthInternal = 0
tickT(81, 140)
FindAllOf = rawFind
check((s.armsDown or {}).rail and at("^RE_SV_AlcnRailgun$", 81) == "" and finds == 1
      and has(line("special: the Alicorn's railguns are down", f0), "(2 found, none up)"),
      "... then the second shot down: down (one more look, " .. finds .. "), no order at 130")
-- one found as the others go down, still at 0 (its first read as it appears): a pass of its own before the kind counts
s = armsRound()
FA[RAIL] = { rails[1] }
tickT(0, 20)
rails[1].HealthInternal, rails[2].HealthInternal = 0, 0
FA[RAIL] = rails
tickT(21, 22)
local late = (s.armsDown or {}).rail
rails[2].HealthInternal = 1600
tickT(23, 80)
check(not late and not (s.armsDown or {}).rail and at("^RE_SV_AlcnRailgun$", 21) == "70",
      "a railgun found at 0 as the first goes down: not counted down that pass; up the next, its order at 70")
-- a railgun never read up (0 at its first read) isn't counted down; one whose health can't be read counts as up
s = armsRound(0)
tickT(0, 80)
check(not (s.armsDown or {}).rail and at("^RE_SV_AlcnRailgun$") == "10,70" and at("^RE_SV_AlcnAlertOn$") == "5,65",
      "railguns at 0 from the first read: never seen up, so not counted down (warned and fired as before)")
s = armsRound()
rails[1].HealthInternal, rails[2].HealthInternal = nil, nil
tickT(0, 80)
check(not (s.armsDown or {}).rail and at("^RE_SV_AlcnRailgun$") == "10,70", "railguns whose health can't be read: up")
cleanArms()

-- after a surfacing: "submarine has surfaced", the railgun's warning radio_gap_s later (not the same second: code
-- review of 2026-10-29), its order lead_s after that, and the deck's call held by that warning's gap
print("the ALICORN surfacing: its calls kept apart")
local function surfaceRound()
    s = alicornRound()
    D.deckLeft = 1
    s.nextDive, s.nextRail = 10, 20                       -- (dives at 10 for 20 s; its railgun order due under water)
    tl = {}
    return s
end
s = surfaceRound()
f0 = #logs + 1
tickT(0, 37)
local early = #spawns
tickT(38, 45)
check(at("^RE_SV_RadioAlcnUp$") == "31" and at("^RE_SV_RadioAlcnRailFirst$") == "33" and at("^RE_SV_AlcnAlertOn$") == "33"
      and at("^RE_SV_AlcnRailgun$") == "38",
      string.format("surfaced at 31: its call, the railgun's 2 s later (33, was 31), the order lead_s 5 after it (38; up %s, rail %s, order %s)",
          at("^RE_SV_RadioAlcnUp$"), at("^RE_SV_RadioAlcnRailFirst$"), at("^RE_SV_AlcnRailgun$")))
check(at("^RE_SV_RadioAlcnDeck$") == "35" and early == 0 and #spawns == 1 and D.deckLeft == 0
      and has(line("tell: alcn_deck not said", f0), "1.0 s after alcn_rail_first, its gap 2.0 s"),
      "the deck's call held a second by the railgun's gap (35, not 34) and its launch warn_s after (" .. tostring(line("tell: alcn_deck not said", f0)) .. ")")
-- a gap that won't end: the call twice held, then the launch untold
s = surfaceRound()
tickT(0, 33)
local gap0 = CFG.tells.radio_gap_s
CFG.tells.radio_gap_s = 100
tickT(34, 38)
early = #spawns
tickT(39, 45)
CFG.tells.radio_gap_s = gap0
check(at("^RE_SV_RadioAlcnDeck$") == "" and early == 0 and #spawns == 1,
      "a gap that won't end: held twice (34, 35), then untold at 36, the launch at 39 (" .. tostring(early) .. " by 38)")
-- tells off: nothing said, the order 5 s after the surfacing as before
CFG.tells.enabled = false
s = surfaceRound()
tickT(0, 45)
CFG.tells.enabled = true
check(at("^RE_SV_RadioAlcn") == "" and at("^RE_SV_AlcnAlertOn$") == "36" and at("^RE_SV_AlcnRailgun$") == "36",
      "tells off: the RAILGUN WARNING with the order, 5 s after the surfacing (36) as before")
-- a co-op host with its own tells off: the deck's call to its joiners held by their gap too, then sent (F4's review:
-- TELL.say read "off", this game's own, so the call refused for the joiners' gap was dropped)
do
    local host0, tell0 = COOP.host, COOP.tell
    local sent = {}
    COOP.host = function() return true end
    COOP.tell = function(slot, id) sent[#sent + 1] = id .. "@" .. tostring(D.now); return true end
    CFG.tells.enabled = false
    s = surfaceRound()
    f0 = #logs + 1
    tickT(0, 45)
    CFG.tells.enabled = true
    COOP.host, COOP.tell = host0, tell0
    local out = table.concat(sent, ",")
    check(has(out, "alcn_up@31,alcn_rail_first@33,alcn_deck@35") and #spawns == 1
          and has(line("tell: alcn_deck not said", f0), "every joiner: 1.0 s after alcn_rail_first"),
          "a host with tells off: its joiners' deck call held a second by their gap, sent at 35, the launch after (" .. out .. ")")
end
ROLE.live = nil

---------------------------------------------------------------------------------------------------- startRound
print("startRound: the deck's launches")
CFG.airfield.enabled = false
presetName = function() return "standard", 3 end
local function round(n, special)
    planes = {}
    D = { round = n - 1, state = "wait", at = 0, now = 1000, up = {}, flown = {}, queue = {}, spare = {}, events = {} }
    D.forceSpecial = special
    for _, u in ipairs(CFG.pool) do alive[u] = 0 end
    local from = #logs + 1
    startRound()
    local fighters = 0
    for _, w in ipairs(D.waves or {}) do for _, u in ipairs(w) do if u:sub(1, 1) ~= "@" then fighters = fighters + 1 end end end
    return fighters, line("round " .. n .. ": the Alicorn's deck", from)
end
local nf, l = round(8, "alicorn")
check(D.deckLeft == 3 and nf == 0 and has(l, "up to 3 flights of 2"), "round 8: 2 + floor(8 x 0.15) = 3 launches, no fighters (" .. tostring(l) .. ")")
nf, l = round(14, "alicorn")
check(D.deckLeft and D.deckLeft > 4 and nf == 0 and has(l, "of them its escorts"),
      "round 14 (from escort_from): its escorts off the deck too, none from a spawn point (" .. tostring(l) .. ")")
nf, l = round(40, "alicorn")
check(D.deckLeft == 6 + 4 and nf == 0, "round 40: max_flights 6 + its escorts' 4 (8 aircraft): " .. tostring(D.deckLeft))
AL.deck.escorts = false
nf = round(14, "alicorn")
check(D.deckLeft == 4 and nf > 0, "escorts false: 4 launches, its escorts as fighter flights (" .. nf .. ")")
do                                                        -- (the deck never launches a flight the round queued)
    local queued, keep = {}, nil
    for _, w in ipairs(D.waves or {}) do for _, u in ipairs(w) do queued[u] = true end end
    local nq = 0
    for u in pairs(D.taken or {}) do nq = nq + 1 end
    for _, u in ipairs(CFG.pool) do                       -- (every free 2-ship up but one, the queued ones left free)
        if not D.taken[u] and flightSize(u) == 2 and not PROBE_OF[u] then
            if not keep then keep = u else alive[u] = 2 end
        end
    end
    local spare0 = #D.spare
    D.special = { kind = "alicorn", state = "sail", at = D.now, tanks = 4, coreOpen = false, dived = false,
                  nextDive = 1e9, nextRail = 1e9, nextVolley = 1e9 }
    FA[AL.core_class] = { core }
    spawns = {}
    for t = D.now, D.now + 25 do SPC.alicornTick(t, D.special) end
    check(nq > 0 and #spawns == 1 and spawns[1].unit == keep and not queued[keep],
          string.format("the deck: the one free flight not the round's own (%s; %d taken)", tostring(spawns[1] and spawns[1].unit), nq))
    local inSpare = false
    for _, u in ipairs(D.spare) do if u == keep then inSpare = true end end
    check(not inSpare and #D.spare == spare0 - 1, "... and no spare any more (" .. spare0 .. " -> " .. #D.spare .. ")")
    alive[keep] = 0; D.up[keep] = nil
    for t = D.now + 26, D.now + 70 do SPC.alicornTick(t, D.special) end
    check(#spawns == 2 and not queued[spawns[2].unit], "... nor the next (" .. tostring(spawns[2] and spawns[2].unit) .. ")")
    alive[keep] = 2
    for _, u in ipairs(CFG.pool) do if D.taken[u] then alive[u] = 0 end end
    local n0 = #spawns
    for t = D.now + 71, D.now + 140 do SPC.alicornTick(t, D.special) end
    check(#spawns == n0, "only the round's own flights free: none launched (" .. (#spawns - n0) .. ")")
    for _, u in ipairs(CFG.pool) do alive[u] = 0 end
end
AL.deck.escorts = true
AL.deck.enabled = false
nf = round(14, "alicorn")
check(D.deckLeft == nil and nf > 0, "deck off: none, its escorts as before")
AL.deck.enabled = true
round(9, "ladon")
check(D.deckLeft == nil, "another special's round: no deck")

---------------------------------------------------------------------------------------------------- the main menu's rows
print("the main menu's rows (searchSetup on fake tables)")
local function fakeDT(name)
    nextAddr = nextAddr + 1
    local t = { full = name, rows = {}, addr = nextAddr }
    local function key(n) return type(n) == "table" and n.s or n end
    function t.FindRow(self, n) return self.rows[key(n)] end
    function t.AddRow(self, n, r)
        local function cp(x) if type(x) ~= "table" then return x end local c = {}; for k, v in pairs(x) do c[k] = cp(v) end; return setmetatable(c, getmetatable(x)) end
        self.rows[key(n)] = cp(r)
    end
    function t.RemoveRow(self, n) self.rows[key(n)] = nil end
    return t
end
local function menuRows()
    local SLOTS = { "RootLua", "EvadeLua", "EvadeMissileNearLua", "EvadeMissileFarLua", "EvadeGunLua", "EvadeSpecialLua",
                    "BlackoutLua", "CloudAvoidanceLua", "ProvokeLua", "ProvokeNearLua", "ProvokeMidLua", "ProvokeFarLua",
                    "EscapeFromPursuerLua", "MoveAwayFromTargetLua", "PursueTargetLua" }
    local ls, npc, mod, mission, fcs, wpn = fakeDT("DT_NPC_LuaSet"), fakeDT("DT_NPC"), fakeDT("DT_NPC_AIModule"),
        fakeDT("DT_SV_NpcMission"), fakeDT("DT_NPC_FCS"), fakeDT("DT_NPC_Weapon")
    local base = { LuaAsetts = {} }
    for _, sl in ipairs(SLOTS) do base.LuaAsetts[sl] = { LuaScript = "stock " .. sl } end
    ls.rows.NLID_0012_CP = base
    mod.rows.NPC_AIModule_Plane000 = { Radius = 6000, bEnableLostTargetInClouds = true }
    for _, id in ipairs({ "NPC_FCS_PlaneMsl000", "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000", "NPC_FCS_PlaneFlr000",
                          "NPC_FCS_PlaneLAAM000", "NPC_FCS_ECM000" }) do
        fcs.rows[id] = { CaptureDistance = 2500, CaptureMinDistance = 300, CaptureAngleRange = 45, ActivationTime = 2,
                         TriggeringTime = 2.5, ShotIntervalTime = 10, RestingTime = 10, TriggerCount = 1, PredictionOffsetTime = 0,
                         MagazineCapacity = 10 }
    end
    fcs.rows.NPC_FCS_PlaneGun000 = { CaptureDistance = 1500, CaptureAngleRange = 30, TriggeringTime = 1.5, TriggerCount = 10,
                                     RestingTime = 1, PredictionOffsetTime = 0, NpcWeaponId = FName("GUN_000") }
    wpn.rows.GUN_000 = { damage = 1, MaxSpawnAngle = 3, LifeTime = 2 }
    local function npcRow(ecm)
        return { NpcFCSId0 = FName("NPC_FCS_PlaneFlr000"), NpcFCSId1 = FName("NPC_FCS_PlaneGun000"),
                 NpcFCSId2 = FName("NPC_FCS_PlaneMsl000"), NpcFCSId3 = FName(ecm and "NPC_FCS_ECM000" or "None"),
                 NpcFCSId4 = FName("None"), NpcFCSId5 = FName("None"), LuaSetId = FName("NLID_0012_CP"),
                 NpcAIModuleId = FName("NPC_AIModule_Plane000"), MaxHealthDifference = 0,
                 PitchSpeedDifference = 0, RollSpeedDifference = 0, YawSpeedDifference = 0 }
    end
    local function mrows(a, id, ecm)
        npc.rows[id] = npcRow(ecm)
        mission.rows[a] = { NpcId = FName(id) }
        for lv = 0, #SPIKE_SUFFIX do mission.rows[a .. "_sv" .. SPIKE_SUFFIX[lv]] = { NpcId = FName(id .. "_SV" .. SPIKE_SUFFIX[lv]:upper()) } end
    end
    local list = { "f16c_common" }
    for _, x in ipairs(CFG.aircraft) do list[#list + 1] = x end
    for _, e in ipairs(CFG.variety.late) do list[#list + 1] = e[1] end
    list[#list + 1] = CFG.jammer.aircraft
    for _, x in ipairs(list) do mrows(x, "OP_" .. x) end
    mrows(ACE.row("anomaly", "f04e", "l"), "SV_Ace_anomaly_f04e_L")
    mrows(ACE.row("anomaly", "f04e", "w"), "SV_Ace_anomaly_f04e_W")
    mrows(ACE.row("glitch", "e18g", "l"), "SV_Ace_glitch_e18g_L", true)
    OBJ = {}
    OBJ[PROBE_TABLES[1].path], OBJ[PROBE_TABLES[2].path], OBJ[SEARCH_MODULE.path] = ls, npc, mod
    OBJ["/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"] = mission
    OBJ[FCS_TABLE], OBJ[WEAPON_TABLE] = fcs, wpn
    for _, d in pairs(CFG.behaviour_sets) do
        for _, n in pairs(d.slots) do OBJ["/Game/LuaSource/SurvivalMode/AI/" .. n .. "." .. n] = { full = n } end
    end
    BS.done, BS.ready, BS.tries = false, {}, 0
    SR.done, SR.ready, SR.tries, SR.levels, SR.mslSlot = false, {}, 0, {}, nil
    setsSetup(); searchSetup()
    return npc, fcs
end
local from = #logs + 1
local npc, fcs = menuRows()
local guards = {}
for lv = 0, #SPIKE_SUFFIX do
    local r = npc.rows["SV_Ace_anomaly_f04e_W_SV" .. SPIKE_SUFFIX[lv]:upper()]
    guards[#guards + 1] = r and r.LuaSetId:ToString() or "none"
end
check(table.concat(guards, ",") == "NLID_SV_WolfWing,NLID_SV_WolfWing,NLID_SV_WolfWing,NLID_SV_WolfWing",
      "the guards' row flies NLID_SV_WolfWing on every level (" .. table.concat(guards, ",") .. ")")
check(npc.rows["SV_Ace_anomaly_f04e_L_SV"].LuaSetId:ToString() == "NLID_SV_Fighter" and npc.rows.OP_f16c_common_SV.LuaSetId:ToString() == "NLID_SV_Fighter",
      "MINDRIPPER and the fighters keep the fighters' set")
check(has(line("special: the Anomaly's guards (", from), "fly NLID_SV_WolfWing (its pack)"), "logged once")
local gr = npc.rows.SV_Ace_glitch_e18g_L_SV
local ge = gr and gr.NpcFCSId3:ToString()
check(ge == "NPC_FCS_ECM000_SVX" and fcs.rows.NPC_FCS_ECM000_SVX.ShotIntervalTime == 14,
      "AB.L..IN's ECM slot by default: anomEcm's row, as confirmed (" .. tostring(ge) .. ": every 14 s)")
local ml = npc.rows.SV_Ace_anomaly_f04e_L_SV
local mEcm = {}
for i = 3, 5 do local id = ml["NpcFCSId" .. i]:ToString(); if id:find("ECM") then mEcm[#mEcm + 1] = id end end
check(table.concat(mEcm, ",") == "NPC_FCS_ECM000_SVX", "MINDRIPPER's pod keeps anomEcm's row (" .. table.concat(mEcm, ",") .. ")")
AN.pack.guard_luaset = ""
GL.phases.ecm_row = true
npc, fcs = menuRows()
ge = npc.rows.SV_Ace_glitch_e18g_L_SV.NpcFCSId3:ToString()
check(npc.rows.SV_Ace_anomaly_f04e_W_SV.LuaSetId:ToString() == "NLID_SV_Fighter" and ge == "NPC_FCS_ECM000_SVE"
      and fcs.rows.NPC_FCS_ECM000_SVE.ShotIntervalTime == 60 and fcs.rows.NPC_FCS_ECM000_SVE.RestingTime == 60,
      "guard_luaset \"\": the fighters' set; ecm_row true: AB.L..IN's own row (" .. tostring(ge) .. ": 60 s between, 60 s rest)")
AN.pack.guard_luaset = "NLID_SV_WolfWing"
GL.phases.ecm_row = false

---------------------------------------------------------------------------------------------------- sure tells
print("sure tells (TELL.say / TELL.play)")
run(20)
callouts, events = {}, {}
-- with tells on: through the gap and the cooldown (the pack's above), never a callout
TELL.say("reversal")
events = {}
local fT = #logs + 1
check(TELL.say("glitch_allout", TELL.ALL) == true and evs("^RE_SV_RadioGlitchEcm") ~= ""
      and has(line("tell: glitch_allout", fT), "a sure tell through"), "said right after another tell: through its gap, to every player")
check(TELL.say("glitch_six") == true and evs("^RE_SV_RadioSix") ~= "", "... and AB.L..IN's other one right after it too")
check(TELL.play("glitch_allout", nil, "the host") == false and #callouts == 0, "a joiner's from the host within line_gap_s: not said (its one line)")
check(#callouts == 0, "no callout from any of them")
CFG.tells.enabled = false
events = {}
local saidA, whyA, kindA, shownA = TELL.play("glitch_allout")
check(saidA == false and whyA == "tells off" and kindA == "off" and shownA == nil and #callouts == 0 and evs("^RE_SV_Radio") == "",
      "tells off: nothing (no callout in its place now; no 4th result)")
TELL.say("glitch_six", TELL.ALL)
TELL.play("glitch_allout", nil, "the host")
TELL.say("reversal")
check(#callouts == 0 and evs("^RE_SV_Radio") == "", "... to every player, from the host, or another tell: nothing either")
CFG.tells.enabled = true
D.state = "wait"
D.now = 60
check(not TELL.say("glitch_six") and #callouts == 0 and evs("^RE_SV_Radio") == "", "between rounds: not a sure tell either")
D.state = "fighting"
grounded = true
local fS = #logs + 1
local saidS, whyS, kindS = TELL.play("glitch_six")
local _, _, kindJ = TELL.play("glitch_six", nil, "the host")
check(saidS == false and whyS == "down at the airfield" and kindS == "state" and kindJ == "state" and #callouts == 0
      and has(line("tell: glitch_six not said", fS), "(down at the airfield)"),
      "down at the airfield: not said, here or from the host's \"tl\" (kind state, logged)")
grounded = false
D.state = "wait"
check(TELL.play("glitch_six", nil, "the host") == true and evs("^RE_SV_RadioSix") ~= "",
      "... a joiner's from the host while its mirrored state still says wait: said (the host checked its round)")
D.state = "fighting"
LB.show = true
D.now = 90
check(not TELL.say("glitch_allout"), "over the run's summary: none")
LB.show = nil
do                                                        -- (a host's to its joiners: a sure one through the gaps)
    local host0, tell0 = COOP.host, COOP.tell
    local sent = {}
    COOP.host = function() return true end
    COOP.tell = function(slot, id) sent[#sent + 1] = id; return true end
    run(20)
    TELL.say("glitch_allout", TELL.ALL); TELL.say("glitch_allout", TELL.ALL)
    D.now = 3                                             -- (past radio_gap_s: the next tell may go)
    TELL.say("reversal", TELL.ALL); TELL.say("reversal", TELL.ALL)
    COOP.host, COOP.tell = host0, tell0
    local n = { glitch_allout = 0, reversal = 0 }
    for _, id in ipairs(sent) do n[id] = (n[id] or 0) + 1 end
    check(n.glitch_allout == 2 and n.reversal == 1, string.format("a host's sure tell to its joiners through its gap (%d sent), another tell not (%d)",
        n.glitch_allout, n.reversal))
end
---------------------------------------------------------------------------------------------------- co-op: AB.L..IN on a joiner
print("co-op: a joiner's copy of AB.L..IN in its phase 3")
onJoinerMessage({ "rnd", "20", "fighting", "0.0", "1", "1", "1", "", "3" })
check(M.rnd and M.rnd.glitchPhase == 3, "\"rnd\": the host's AB.L..IN phase 3 read")
onJoinerMessage({ "rnd", "20", "fighting", "0.0", "1", "1", "1", "", "7" })
local gp7 = M.rnd.glitchPhase
onJoinerMessage({ "rnd", "20", "fighting", "0.0", "1", "1", "1", "" })
check(gp7 == nil and M.rnd.glitchPhase == nil, "... a phase out of 1-3 or none: nil")
M.rnd = nil
run(20)
local copy = mkObj("BP_OP0001_e18g_Glitch_C_7", KM(0, 0))
local cpod = { full = "BP_wp_ecm_a0_C_7", addr = 701, bJammingEnable = true, bSupportEnable = true }
function cpod:GetOwner() return copy end
function cpod:GetInstigator() return nil end
FA.BP_wp_ecm_a0_C = { cpod }
planes = { { unit = GL.unit, obj = copy } }
D.glitchPhase = 2
ANOM.clientGlitch(1)
check(cpod.bJammingEnable == true, "phase 2: the copy's pods left alone")
D.glitchPhase = 3
ANOM.clientGlitch(2)
check(cpod.bJammingEnable == false and cpod.bSupportEnable == false, "phase 3: the copy's pods switched off")
cpod.bJammingEnable = true
ANOM.clientGlitch(3)
check(cpod.bJammingEnable == true, "... not again before ecm_check_s (2 s)")
ANOM.clientGlitch(4)
check(cpod.bJammingEnable == false, "... and again after it (a new pod off)")
cpod.bJammingEnable = true
GL.phases.ecm_pods_off = false
ANOM.clientGlitch(10)
check(cpod.bJammingEnable == true, "ecm_pods_off false: left alone")
GL.phases.ecm_pods_off = true
D.glitchPhase = nil
ANOM.clientGlitch(20)
check(cpod.bJammingEnable == true and ANOM.glitchCopy == nil, "the host's phase gone: nothing")

---------------------------------------------------------------------------------------------------- the hooks
print("the hooks, by their place in the source")
local function body(file, from_)
    local src = readAll(MOD .. "/Scripts/" .. file)
    local a = src:find(from_)
    local b = a and src:find("\nend\r?\n", a + 1)
    return a and src:sub(a, b or #src) or ""
end
check(has(body("sv_anomalies.lua", "\nfunction ANOM%.tick%("), "pcall(ANOM.packTick, now, s, c)"), "ANOM.tick: the pack after the field")
check(has(body("sv_ai.lua", "\nfunction ACE%.hunt%("), "ANOM.packHeld(p)"), "ACE.hunt: hunt_only_sprung")
check(has(body("sv_alicorn.lua", "\nfunction SPC%.alicornTick%("), "pcall(SPC.alicornDeck, now, s, c)"), "alicornTick: the deck each second")
check(has(body("sv_ladon.lua", "\nfunction SPC%.ladonTick%("), "pcall(SPC.ladonRage, now, s, k)"), "ladonTick: the rage at a kill")
check(has(readAll(MOD .. "/Scripts/sv_hud.lua"), "t.glitch_row_allout"), "the HUD row: AB.L..IN's phase 3")
check(has(readAll(MOD .. "/Scripts/sv_coop.lua"), '"^RE_SV_AnomalyPack",'), "KEEP_EVENTS: ^RE_SV_AnomalyPack")
check(has(readAll(MOD .. "/Scripts/sv_coop.lua"), 'alive, lv, gp)'), "the host's \"rnd\": AB.L..IN's phase")
check(has(body("sv_coop.lua", "\nlocal function clientRounds%("), "D.glitchPhase = r.glitchPhase")
      and has(body("sv_coop.lua", "\nlocal function clientRounds%("), "pcall(ANOM.clientGlitch, now)"), "clientRounds: the phase kept, the copy's pods")
check(has(body("sv_rounds.lua", "\nlocal function startRound%("), "D.taken = taken"), "startRound: the round's own flights for the deck")

logFile:close()
if fails > 0 then print("bosses test: " .. fails .. " FAILED"); os.exit(1) end
print("bosses test: all passed")
