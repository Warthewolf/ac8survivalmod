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
--     off, its gun only with you close in front of it, LastTGT every allout_turn_s and when you're behind it), phase 3
--     mid-blink (it comes back first), phases off (as before);
--   a Ladon's rage (SPC.ladonTick): the other one shot down: RE_SV_LadonRage<Key>, its callout and tell, volleys every
--     25 s; both down in one second: none; rage off: none;
--   the ALICORN's deck (SPC.alicornTick): its tell and callout warn_s before, a Skirmisher 2-ship spawned alt_m over the
--     sea ahead_m off its bow along its heading, every every_s, no more than max_up up, none while dived or while you're
--     at the airfield, after_surface_s after it surfaces, D.deckLeft counted down, any free 2-ship with roles off;
--     startRound's D.deckLeft (and its escorts folded in from escort_from, none from a spawn point);
--   the main menu's rows (searchSetup on fake tables): the guards' set on every level, AB.L..IN's own ECM row;
--   co-op: KEEP_EVENTS (the pack and AB.L..IN's LastTGT kept, a Ladon's rage forwarded);
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
function hudCallout(text, sub, big, urgent) callouts[#callouts + 1] = { text = text, sub = sub, urgent = urgent } end

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
hudCallout = function(text, sub, big, urgent) callouts[#callouts + 1] = { text = text, sub = sub, urgent = urgent } end
part("sv_spawn.lua"); part("sv_anomalies.lua")
part("sv_rounds.lua", nil, { { "\nlocal function startRound%(%)", "\nfunction startRound()" } })
part("sv_ladon.lua"); part("sv_alicorn.lua"); part("sv_stats.lua"); part("sv_tells.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" }, { "\nlocal function mirroredEvent%(name%)", "\nfunction mirroredEvent(name)" } })
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
check(said("THE PACK SPRINGS") and said("THE PACK SPRINGS").urgent and evs("^RE_SV_Radio(E?n?Trap)") ~= "",
      "the tell: THE PACK SPRINGS (urgent) and an ambush line")
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
check(said("IT'S ON YOUR SIX", c1) and evs("^RE_SV_RadioSix") ~= "", "its tell: IT'S ON YOUR SIX and a check-your-six line")
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
check(said("ITS ECM IS DOWN", c1) and said("ITS ECM IS DOWN", c1).urgent and evs("^RE_SV_RadioGlitchEcm", g3) == "RE_SV_RadioGlitchEcm",
      "its tell: ITS ECM IS DOWN (urgent) and \"it's not jamming anymore\"")
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
tickL(41, 41)
local M_ = s.units.Mishka
check(M_.rage and s.raged == "Mishka" and evs("^RE_SV_LadonRage") == "RE_SV_LadonRageMishka",
      "KOT down: MISHKA enraged (RE_SV_LadonRageMishka)")
check(said("MISHKA ENRAGED") and said("MISHKA ENRAGED").sub == "NEW HEADING, FASTER VOLLEYS" and evs("^RE_SV_RadioLadonRage") ~= "",
      "its callout and the tell's \"the hostile's changed course\"")
check(has(line("special: Ladon MISHKA enraged", f1), "volleys every 25 s"), "logged: " .. tostring(line("special: Ladon MISHKA enraged", f1)))
local va = {}
for t = 42, 120 do
    local n = count("^RE_SV_LadonVolleyMishka")
    tickL(t, t)
    if count("^RE_SV_LadonVolleyMishka") > n then va[#va + 1] = t end
end
check(#va >= 3 and va[1] <= 46 and va[2] - va[1] == 25 and va[3] - va[2] == 25,
      "its volleys: the next within first_s 5, then every 25 s (" .. table.concat(va, ", ") .. ")")
check(has(line("special: Ladon MISHKA fires"), ", enraged"), "the volley lines say enraged")
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
check(#spawns == 0 and not said("PLANES LAUNCHING"), "nothing off its deck before first_s - warn_s")
tickC(22, 22)
check(said("PLANES LAUNCHING") and said("PLANES LAUNCHING").sub == "FIGHTERS OFF THE ALICORN'S DECK" and evs("^RE_SV_RadioAlcnDeck") ~= "",
      "warn_s 3 before: its callout and \"planes launching from the carrier\"")
tickC(23, 25)
local sp1 = spawns[1]
check(#spawns == 1 and ROLE.of[sp1.unit] == "skirm" and flightSize(sp1.unit) == 2, "first_s 25: a Skirmisher 2-ship (" .. tostring(sp1 and sp1.unit) .. ")")
check(sp1 and math.abs(sp1.x - (core.at.X + 0.8 * 80000)) < 1 and math.abs(sp1.y - (core.at.Y - 0.6 * 80000)) < 1
      and math.abs(sp1.z - 60000) < 1 and math.abs(sp1.yaw - (math.deg(math.atan(-0.6, 0.8)) % 360)) < 0.01,
      string.format("ahead_m 800 off its bow, alt_m 600 over the sea, along its heading (x %.0f, y %.0f, z %.0f, yaw %.1f)",
          sp1 and sp1.x or -1, sp1 and sp1.y or -1, sp1 and sp1.z or -1, sp1 and sp1.yaw or -1))
check(D.up[sp1.unit] and D.deckLeft == 2 and has(line("special: the Alicorn's deck launch 1"), "(skirm), 2 aircraft at 600 m, 2 launches left"),
      "up, counted (D.deckLeft 2): " .. tostring(line("special: the Alicorn's deck launch 1")))
check(has(line("round 14: " .. sp1.unit), "at the Alicorn's deck"), "spawnFlight's line: at the Alicorn's deck")
alive[sp1.unit] = 2
tickC(26, 59)
check(#spawns == 1, "nothing for every_s 35")
tickC(60, 60)
local sp2 = spawns[2]
check(#spawns == 2 and sp2.unit ~= sp1.unit and ROLE.of[sp2.unit] == "skirm", "every_s on: the other Skirmisher 2-ship (" .. tostring(sp2 and sp2.unit) .. ")")
alive[sp2.unit] = 2
tickC(61, 100)
check(#spawns == 2 and has(line("special: the Alicorn's deck waits"), "2 of its flights up"), "max_up 2 up: the deck waits")
alive[sp1.unit] = 0; D.up[sp1.unit] = nil
grounded = true
tickC(101, 104)
check(#spawns == 2, "one down, but you're at the airfield: waits")
grounded = false
tickC(105, 105)
check(#spawns == 3 and D.deckLeft == 0, "you took off: launched (the round's last, D.deckLeft 0)")
alive[spawns[3].unit] = 0; D.up[spawns[3].unit] = nil; alive[sp2.unit] = 0; D.up[sp2.unit] = nil
tickC(106, 200)
check(#spawns == 3, "D.deckLeft 0: no more")
-- dived: none; surfaced: after_surface_s
s = alicornRound()
s.nextDive = 10
tickC(0, 10)                                              -- (the dive at 10 s: where it sailed, -5 m)
core.at = { X = core.at.X, Y = core.at.Y, Z = -500000 }   -- (down under the sea while dived)
tickC(11, 40)
check(s.dived and #spawns == 0 and not said("PLANES LAUNCHING"), "dived from 10 s (still 5 km down at 40 s): no launch, no call")
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
-- off
AL.deck.enabled = false
s = alicornRound()
tickC(0, 60)
check(#spawns == 0, "deck off: none")
AL.deck.enabled = true
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
check(ge == "NPC_FCS_ECM000_SVE" and fcs.rows.NPC_FCS_ECM000_SVE.ShotIntervalTime == 60 and fcs.rows.NPC_FCS_ECM000_SVE.RestingTime == 60,
      "AB.L..IN's ECM slot: its own row (" .. tostring(ge) .. ": 60 s between, 60 s rest)")
local ml = npc.rows.SV_Ace_anomaly_f04e_L_SV
local mEcm = {}
for i = 3, 5 do local id = ml["NpcFCSId" .. i]:ToString(); if id:find("ECM") then mEcm[#mEcm + 1] = id end end
check(table.concat(mEcm, ",") == "NPC_FCS_ECM000_SVX", "MINDRIPPER's pod keeps anomEcm's row (" .. table.concat(mEcm, ",") .. ")")
AN.pack.guard_luaset = ""
GL.phases.ecm_row = false
npc = menuRows()
check(npc.rows.SV_Ace_anomaly_f04e_W_SV.LuaSetId:ToString() == "NLID_SV_Fighter" and npc.rows.SV_Ace_glitch_e18g_L_SV.NpcFCSId3:ToString() == "NPC_FCS_ECM000_SVX",
      "guard_luaset \"\" / ecm_row false: the fighters' set and anomEcm's row, as before")
AN.pack.guard_luaset = "NLID_SV_WolfWing"
GL.phases.ecm_row = true

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

logFile:close()
if fails > 0 then print("bosses test: " .. fails .. " FAILED"); os.exit(1) end
print("bosses test: all passed")
