-- capture_test.lua: GEOFON's capture (Scripts/sv_fleet_capture.lua, round 30's WP14, the user's "Controlling Players plan")
-- alone on build/checks/lua.exe, the game, the clock and co-op stubbed (tools/checks/capture_test.sh runs it):
--   solo: never a capture (coop_only); IFCAP.test runs one on your own plane;
--   the host's picks: never before first_s, never with fewer than 2 flying (the last one up), never one DOWN / at the
--     airfield / without a place, never during a cinematic, the same player not again within per_player_s, every_s apart;
--   the lock: its HUD static on the locked player (and off at its end, whichever), RAVEN pinged on the minimap every 3 s,
--     broken by RAVEN's EW mast going down, by escape_km from RAVEN, by the player leaving;
--   the takeover: invincible, untargeted (Faction 0), the attack limits 0, sv_spweapons' limits held; the autopilot to the
--     gate, the landing (SV_CapLand), the touchdown held land_hold_s, the trap, DOWN; everything given back after;
--   every end gives the controls back: GEOFON gone mid-flight, the run over, the level dropped (the runtime's capture off
--     too), a "capoff" word, give_up_s; the host never left holding one (the captive's game ending it unheard: 0.74.186);
--   the host's words: bad slot / seq refused, a capoff for another seq or after the trap ignored.
local MOD = arg[1] or "../../mod/UE4SS/AC8SurvivalMode"
local fails, oks = 0, 0
local function check(c, what, extra)
    if c then oks = oks + 1; print("  ok   " .. what)
    else fails = fails + 1; print("  FAIL " .. what .. (extra ~= nil and (" (" .. tostring(extra) .. ")") or "")) end
end

---------------------------------------------------------------------------------------------------- the clock and the game
local T = 1000
os.clock = function() return T end
local logs, callouts, sent, events, caps, lands, downs, holds = {}, {}, {}, {}, {}, {}, {}, {}
function log(s) logs[#logs + 1] = s end
local function logged(pat) for i = #logs, 1, -1 do if logs[i]:find(pat) then return logs[i] end end return nil end
local function clear() logs, callouts, sent, events, caps, lands, downs = {}, {}, {}, {}, {}, {}, {} end
function hudCallout(a, b) callouts[#callouts + 1] = a .. "|" .. tostring(b) end
local function said(pat) for _, c in ipairs(callouts) do if c:find(pat) then return true end end return false end
function liveObj(o) return type(o) == "table" and not o.freed end
function valid(o) return type(o) == "table" and not o.freed end
function nameOf(o) return type(o) == "table" and o.name or nil end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function StaticFindObject() return nil end
function loadObject() return nil end
function playerLocationDirty() end
local ME = { X = 0, Y = 0, Z = 100000 }
function playerLocation() return { X = ME.X, Y = ME.Y, Z = ME.Z } end

local function actor(name, addr, at, yaw)
    local a = { name = name, addr = addr, at = at, yaw = yaw or 0 }
    a.K2_GetActorLocation = function(self) return { X = self.at.X, Y = self.at.Y, Z = self.at.Z } end
    a.K2_GetActorRotation = function(self) return { Pitch = 0, Yaw = self.yaw, Roll = 0 } end
    a.GetVelocity = function() return { X = 1250, Y = 0, Z = 0 } end
    a.GetActorForwardVector = function(self) return { X = math.cos(math.rad(self.yaw)), Y = math.sin(math.rad(self.yaw)), Z = 0 } end
    return a
end
local PAWN = { name = "PlayerPlane_0", addr = 0x1000, Faction = 1, MaxPlaneAttackerMissiles = 4, MaxPursuitAttackers = 12,
               MaxNonPlaneAttackerMissiles = 6, inv = false }
PAWN.SetIsInvincible = function(self, on) self.inv = on end
PAWN.IsOnGround = function() return false end
local HUDO = { name = "LiveHUD_0", static = 0 }
HUDO.BeginHUDDistortionLightning = function(self, secs) self.static, self.secs = self.static + 1, secs; self.on = true end
HUDO.EndHUDDistortionLightning = function(self) self.on = false end
survivalPC = { name = "PC_0", Pawn = PAWN, MyHUD = HUDO }

-- the fleet: GEOFON (ships[1]) at the origin heading 0, RAVEN 5 km off with its EW mast
local GEO = actor("SV_Unit_IFGeofon_Ford", 0x2000, { X = 0, Y = 0, Z = 0 }, 0)
local RAV = actor("SV_Unit_IFRaven_Hull", 0x3000, { X = 0, Y = 500000, Z = 0 }, 0)
local MAST = { name = "alcn_ecm_01", addr = 0x3100, HealthInternal = 50000 }
local SHIPS = { { name = "GEOFON", hull = { obj = GEO }, parts = {} },
                { name = "RAVEN", hull = { obj = RAV }, parts = { { cls = "alcn_ecm_01", obj = MAST, name = "alcn_ecm_01" } } } }
IFLEET = { cur = { ships = SHIPS } }

-- the runtime's capture: SV_Capture answers CAPRC (1 on its way, 2 at the gate), SV_Capture(0) its stop
local CAPRC, CAP_ON = 1, false
function SV_Capture(addr, gx, gy, alt, hd)
    caps[#caps + 1] = { addr = addr, gx = gx, gy = gy, alt = alt, hd = hd }
    if addr == 0 then CAP_ON = false; return 1 end
    CAP_ON = true
    return CAPRC
end
function SV_CapLand(addr, on) lands[#lands + 1] = { addr = addr, on = on }; return 1 end
function SV_Event(name) events[#events + 1] = name; return 1 end
function SV_Down() return 1 end

-- co-op: this game the host (slot 0); PLAYERS what COOP.players() gives
local PLAYERS = {}
COOP = { open = true, slot = 0, client = function() return false end, host = function() return true end,
         players = function() return PLAYERS end, name = function(slot) return ({ [0] = "War", [1] = "Alyssa", [2] = "Shazzy" })[slot] end }
IFCOOP = { send = function(what, ...) sent[#sent + 1] = table.concat({ what, ... }, "|") end }
local function sentWord(pat) for _, s in ipairs(sent) do if s:find(pat) then return s end end return nil end
local DOWNED = false
DOWN = { me = function() return DOWNED end, capture = function(why) downs[#downs + 1] = why; DOWNED = true; return true end }
ATK = { hold = function(name, on) holds[name] = on or nil end }
CINE = { on = false, active = function() return CINE.on end }
D, RUN = { round = 30 }, {}
CFG = { specials = { fleet = { ships = { { key = "Geofon", name = "GEOFON" }, { key = "Raven", name = "RAVEN" } } } } }
CFG_DEFAULTS = { specials = { fleet = { ships = CFG.specials.fleet.ships } } }
TEST_TICKS, LEVEL_DROPS = {}, {}
INS = { floors = {}, tick = function() end }              -- (sv_tactical.lua's: the floors it holds)
local function floorNow() local f = INS.floors.capture; return f and f() or 0 end
local PICK = 1
math.random = function(n) return math.min(PICK, n) end

dofile(MOD .. "/Scripts/sv_fleet_capture.lua")
local C = CFG.specials.fleet.capture
check(type(IFCAP) == "table" and C and C.enabled and C.coop_only and #TEST_TICKS == 1 and TEST_TICKS[1].name == "fleet capture"
    and type(LEVEL_DROPS["fleet capture"]) == "function" and CFG_DEFAULTS.specials.fleet.capture == C,
    "IFCAP, its settings (in CFG_DEFAULTS too), its tick and level drop")
local tick = TEST_TICKS[1].fn
local function run(secs, step)
    step = step or 0.25
    local stop = T + secs
    while T < stop - 1e-9 do T = T + step; tick(T) end
end
-- run until a word matching pat is sent (the pick's moment), at most secs
local function untilSent(pat, secs)
    local stop = T + secs
    while T < stop do
        T = T + 0.25; tick(T)
        for _, x in ipairs(sent) do if x:find(pat) then return x end end
    end
    return nil
end
local function up(slot, at) return { slot = slot, alive = true, down = false, onAirfield = false, at = at or { X = 0, Y = 400000, Z = 100000 } } end
local function shieldOn() return PAWN.inv and PAWN.Faction == 0 and PAWN.MaxPursuitAttackers == 0 and PAWN.MaxPlaneAttackerMissiles == 0
    and PAWN.MaxNonPlaneAttackerMissiles == 0 and holds.capture == true end
local function shieldOff() return not PAWN.inv and PAWN.Faction == 1 and PAWN.MaxPursuitAttackers == 12 and PAWN.MaxPlaneAttackerMissiles == 4
    and PAWN.MaxNonPlaneAttackerMissiles == 6 and holds.capture == nil end
-- a fresh run: no capture, the pick clock reset (the level dropped), the fleet and players as given
local function fresh(players)
    LEVEL_DROPS["fleet capture"]()
    T = T + 1000                                          -- (past every player's per_player_s)
    PLAYERS, DOWNED, CAPRC, CINE.on = players, false, 1, false
    MAST.HealthInternal, MAST.freed, GEO.freed, SHIPS[1].sunk = 50000, nil, nil, nil
    PAWN.inv, PAWN.Faction, PAWN.MaxPursuitAttackers, PAWN.MaxPlaneAttackerMissiles, PAWN.MaxNonPlaneAttackerMissiles = false, 1, 12, 4, 6
    ME.X, ME.Y, ME.Z = 0, 400000, 100000
    HUDO.on = false
    clear()
end

---------------------------------------------------------------------------------------------------- solo
print("solo")
COOP.open = false
fresh({ up(0) })
run(900, 1)
check(#sent == 0 and IFCAP.state() == nil and not HUDO.on, "15 min solo: never a capture (coop_only)")
COOP.open = true

---------------------------------------------------------------------------------------------------- the picks
print("the host's picks")
fresh({ up(0), { slot = 1, alive = true, down = true, at = { X = 0, Y = 0, Z = 0 } } })
run(C.first_s + 30, 1)
check(#sent == 0 and logged("no one to pick"), "one flying (the other DOWN): no one picked (never the last one up)", logs[#logs])
fresh({ up(0), { slot = 1, alive = true, onAirfield = true, at = { X = 0, Y = 0, Z = 0 } }, { slot = 2, alive = true } })
run(C.first_s + 30, 1)
check(#sent == 0, "the others at the airfield or without a place: no one picked")
fresh({ up(0), up(1) })
CINE.on = true
run(C.first_s + 60, 1)
check(#sent == 0, "a cinematic on: no pick")
CINE.on = false
fresh({ up(0), up(1) })
PICK = 2
run(C.first_s - 2, 1)
check(#sent == 0, "not before first_s (" .. C.first_s .. " s)")
run(4, 1)
local w = sentWord("^cap|1|")
check(w ~= nil and said("CAPTURE LOCK ON ALYSSA") == false, "after first_s: slot 1 picked, \"cap|1|<seq>\" sent", w)
check(IFCAP.state() == nil and not HUDO.on, "the host isn't the one locked: no static here")

---------------------------------------------------------------------------------------------------- the lock
print("the lock")
local function events_n(name) local k = 0; for _, e in ipairs(events) do if e == name then k = k + 1 end end; return k end
check(events_n("RE_SV_IFRavenPing") >= 1, "RAVEN pinged at once")
run(C.lock_s - 5, 0.25)
PLAYERS[2].at = { X = 0, Y = 500000 + (C.escape_km + 1) * 100000, Z = 100000 }
run(5, 0.25)
local pings = events_n("RE_SV_IFRavenPing")
check(pings >= 3 and pings <= 5, "pinged every 3 s of the lock (" .. pings .. " in " .. C.lock_s .. " s)")
check(sentWord("^capoff|1|") and said("CAPTURE BROKEN") and not sentWord("^capgo|"), "slot 1 more than escape_km from RAVEN: broken", sentWord("^capoff"))
-- the same player not again within per_player_s; the next pick every_s on
clear()
PLAYERS[2].at = { X = 0, Y = 400000, Z = 100000 }
PICK = 2
w = untilSent("^cap|", C.every_s + 5)
check(w ~= nil and w:find("^cap|0|"), "every_s on: the next pick isn't slot 1 again (per_player_s): the host", w)
check(IFCAP.state() == "lock" and HUDO.on and HUDO.secs == C.lock_s + 1 and said("^CAPTURE LOCK|"),
    "locked here: CAPTURE LOCK, the HUD's static for the lock", tostring(IFCAP.state()) .. " " .. tostring(HUDO.on))
check(floorNow() == C.floor_hp, "the lock: a floor of floor_hp under your health (\"They can't die until they land\")", floorNow())
MAST.HealthInternal = 0
run(1, 0.25)
check(sentWord("^capoff|0|") and IFCAP.state() == nil and not HUDO.on and said("CAPTURE BROKEN"),
    "RAVEN's EW mast destroyed: broken, the static off, nothing taken", sentWord("^capoff"))
check(floorNow() == 0, "broken: the floor off", floorNow())
check(shieldOff(), "never shielded (the lock only)")
-- the mast down: said once, no more picks
sent = {}
run(C.every_s * 2, 1)
local n_mast = 0
for _, c in ipairs(callouts) do if c:find("RAVEN'S EW MAST DOWN") then n_mast = n_mast + 1 end end
check(n_mast == 1 and not sentWord("^cap|"), "the mast down: said once, no more captures (" .. n_mast .. ")")

-- a player leaving mid-lock
fresh({ up(0), up(1) })
PICK = 2
untilSent("^cap|", C.first_s + 5)
check(sentWord("^cap|1|") ~= nil, "slot 1 locked")
table.remove(PLAYERS, 2)
run(1, 0.25)
check(sentWord("^capoff|1|.*left") ~= nil, "slot 1 left mid-lock: ended (0.74.186)", sentWord("^capoff"))
clear()
PLAYERS[2] = up(1)
run(C.every_s + 2, 1)
check(sentWord("^cap|") ~= nil, "and the host picks again")

---------------------------------------------------------------------------------------------------- the takeover and the landing
print("the takeover and the landing (the host's own plane)")
fresh({ up(0), up(1) })
PICK = 1
untilSent("^cap|", C.first_s + 5)
check(IFCAP.state() == "lock", "the host locked")
run(C.lock_s, 0.25)
check(sentWord("^capgo|0|") and IFCAP.state() == "fly" and not HUDO.on, "the lock out, in reach: \"capgo\", taken, the static off")
check(shieldOn(), "invincible, untargeted (Faction 0), the attack limits 0, sv_spweapons' held")
check(floorNow() == C.floor_hp, "the floor held while RAVEN flies you", floorNow())
local last = caps[#caps]
local gk = C.gate_km * 100000
local dk = { X = C.deck.fwd_m * 100, Y = 0, Z = C.deck.up_m * 100 }
check(last and last.addr == PAWN.addr and math.abs(last.gx - (dk.X - gk)) < 1 and math.abs(last.gy) < 1 and last.hd == 0
    and math.abs(last.alt - (C.gate_alt_m + C.deck.up_m)) < 0.01, "the autopilot to the gate gate_km behind GEOFON's deck, on its line",
    last and string.format("%.0f %.0f %.1f %s", last.gx, last.gy, last.alt, tostring(last.hd)))
PAWN.Faction, PAWN.MaxPursuitAttackers = 1, 12                -- (the game puts them back: held every tick)
run(0.5, 0.25)
check(shieldOn(), "held every tick (the game's own put back)")
CAPRC = 2
run(0.5, 0.25)
check(IFCAP.state() == "final" and logged("at the gate"), "at the gate (SV_Capture 2): its final")
check(#lands > 0 and lands[1].on == 1 and lands[1].addr == PAWN.addr, "the landing: SV_CapLand on (gear down, slowing)")
ME.X, ME.Y, ME.Z = dk.X - 300000, 0, dk.Z + 15000
run(0.25, 0.25)
last = caps[#caps]
check(last and last.alt > C.deck.up_m and math.abs(last.gx - dk.X) < 1, "3 km behind: asked down the glide over the deck's height",
    last and string.format("%.1f m", last.alt))
ME.X, ME.Y, ME.Z = dk.X, 0, dk.Z + 200
run(0.25, 0.25)
last = caps[#caps]
check(last and math.abs(last.alt - (C.deck.up_m - C.press_m)) < 0.01, "over the deck: pressed press_m into it",
    last and string.format("%.1f m", last.alt))
check(logged("touched down") ~= nil and IFCAP.state() == "final", "within land_m over it: touched down, held")
run(C.land_hold_s - 0.5, 0.25)
check(IFCAP.state() == "final", "not trapped before land_hold_s")
run(1, 0.25)
check(IFCAP.state() == nil and #downs == 1 and logged("trapped on GEOFON's deck %(landed"), "held land_hold_s: trapped, DOWN (captured)")
check(caps[#caps].addr == 0 and not CAP_ON and lands[#lands].on == 0 and said("^CAPTURED|"), "the takeover off, the landing off, CAPTURED")
check(not PAWN.inv and PAWN.Faction == 1 and PAWN.MaxPursuitAttackers == 12 and holds.capture == nil, "the shield given back (DOWN's own from there)")
check(floorNow() == 0, "trapped: the floor off (DOWN's from there)", floorNow())
PLAYERS[1].down = true
run(1, 0.25)
check(logged("captured: over") ~= nil, "the host: slot 0 down, the capture over")

print("passed over the deck without touching it")
fresh({ up(0), up(1) })
PICK = 1
untilSent("^capgo|", C.first_s + C.lock_s + 5)
CAPRC = 2
run(0.5, 0.25)
local fore = C.slab.fwd_m + C.slab.len_m / 2 - C.deck.fwd_m
ME.X, ME.Y, ME.Z = dk.X + (fore + 20) * 100, 0, dk.Z + 1200
run(0.25, 0.25)
check(IFCAP.state() == nil and logged("passed over it") and #downs == 1, "past the deck's fore end, 12 m up: trapped all the same", logs[#logs])

---------------------------------------------------------------------------------------------------- every end gives back
print("every end gives the controls back")
local function takenHere()
    fresh({ up(0), up(1) })
    PICK = 1
    untilSent("^capgo|", C.first_s + C.lock_s + 5)
    return IFCAP.state() == "fly" and shieldOn()
end
check(takenHere(), "taken")
SHIPS[1].sunk = true
run(0.5, 0.25)
check(IFCAP.state() == nil and caps[#caps].addr == 0 and shieldOff() and #downs == 0 and floorNow() == 0, "GEOFON sunk mid-flight: free, never DOWN, the floor off")
check(sentWord("^capoff|0|") ~= nil, "the host's capoff")
check(takenHere(), "taken again")
D = nil
run(0.5, 0.25)
check(IFCAP.state() == nil and caps[#caps].addr == 0 and shieldOff(), "the run over: given back")
D = { round = 30 }
check(takenHere(), "taken again")
local before = #caps
LEVEL_DROPS["fleet capture"]()
check(IFCAP.state() == nil and #caps == before + 1 and caps[#caps].addr == 0 and holds.capture == nil, "the level dropped: the runtime's capture off too (0.74.186)")
check(takenHere(), "taken again")
CAPRC = 1
run(C.give_up_s + 1, 1)
check(IFCAP.state() == nil and shieldOff() and logged("not at the deck in") and #downs == 0, "never at the gate in give_up_s: given back")
check(takenHere(), "taken again")
CAPRC = -3
run(0.25, 0.25)
check(IFCAP.state() == nil and shieldOff() and logged("SV_Capture refused"), "SV_Capture refused: given back")

print("the host never left holding one (0.74.186)")
fresh({ up(0), up(1) })
PICK = 2
untilSent("^capgo|", C.first_s + C.lock_s + 5)
check(sentWord("^capgo|1|") ~= nil, "slot 1 taken (its game flies it)")
clear()
run(C.give_up_s + 50, 1)
check(not sentWord("^capoff|") and not sentWord("^cap|"), "held while its game may still bring it down")
run(20, 1)
check(sentWord("^capoff|1|.*given up") ~= nil, "never DOWN in give_up_s + 60 s: ended", sentWord("^capoff"))
check(not sentWord("^cap|"), "no pick at once after an end")
clear()
check(untilSent("^cap|", C.every_s) ~= nil, "the host picks again after a rest")

---------------------------------------------------------------------------------------------------- the words
print("the host's words")
fresh({ up(0), up(1) })
for _, f in ipairs({ { "if", "cap", "-1", "1" }, { "if", "cap", "64", "1" }, { "if", "cap", "0", "x" }, { "if", "cap", "0", "1e9" }, { "if", "cap", "0", "1.5" }, { "if", "cap", "0.5", "1" },
                     { "if", "cap", nil, nil } }) do
    local ok = IFCAP.onHost(f)
    check(ok == false and IFCAP.state() == nil, "refused: cap " .. tostring(f[3]) .. " " .. tostring(f[4]))
end
check(IFCAP.onHost({ "if", "nope", "0", "1" }) == false, "an unknown word refused")
check(IFCAP.onHost({ "if", "cap", "0", "7" }) == true and IFCAP.state() == "lock", "cap for me: locked")
IFCAP.onHost({ "if", "capoff", "0", "8", "x" })
check(IFCAP.state() == "lock", "a capoff for another seq: ignored")
IFCAP.onHost({ "if", "capgo", "0", "7" })
check(IFCAP.state() == "fly" and shieldOn(), "capgo: taken")
IFCAP.onHost({ "if", "capoff", "0", "7", "the mast" })
check(IFCAP.state() == nil and shieldOff() and caps[#caps].addr == 0, "its capoff: given back")
check(IFCAP.onHost({ "if", "cap", "1", "9" }) == true and IFCAP.state() == nil and said("CAPTURE LOCK ON ALYSSA"), "cap for another: only said")

print(string.format("capture test: %d ok, %d failed", oks, fails))
os.exit(fails == 0 and 0 or 1)
