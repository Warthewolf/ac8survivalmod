-- escort_test.lua <mod dir> <work dir> (run by tools/checks/escort_test.sh): THE ESCORT and the ZFA-44 carriers
-- (2026-11-06; Scripts/sv_escort.lua, tools/re/ESCORT.md) on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud,
-- sv_spawn, sv_rounds, sv_flights, sv_shop, sv_allies, sv_tactical, sv_escort and sv_zfa44, the game stubbed:
--   the special kind: in the rotation from round 9, ready only with its units in the world data (SV_UnitAlive -2: not),
--     once a run; its spawn (CHARLENE at CFG start, the escorts beside her at their offsets), the route records, her
--     health; the enemy flights sent after her (EngagementOrderOverride TargetFirst, again, ESC.holds), the round's
--     spawns ahead of her (DIR.spawnAt), more enemies ahead of her, the escorts on her attackers;
--   the landing by distance: her final (gear, the escorts holding over her, her final at 450 a second on: CruiseSlow
--   again), landing closed within close_km on the final leg, rollout (invincible, the attackers back on you), landed as
--     she taxis; a landed one flying again switched off; (2026-11-07, "takes WAY TOO long") the escorts' landings from her
--     rollout, one every release_gap_s, the lined-up one first, else started anyway (hold_max_s 0), each its own records;
--     an escort high over the runway on its way to the circuit not slowed; one shot down (out), one never down (counted
--     landed after_her_s after her, switched off); the win (the pay, the unlock, her subtitle whole, landing open again),
--     the round's end (each switched off, its unit recycled);
--   her loss (no pay, no unlock, the attackers let go, the run on);
--   the STORE: the carrier locked, then on the revive row and its own item, two at most, the price; each ship's
--     container launch (an arm whose unit has planes up the carrier never launched: taken off the list first, then
--     launched: 2026-11-07, none had launched), a plane near it taken as its flight's (dressed settle_s on, not in its
--     first second), a ship with no plane in 10 s on the pose fallback, the flight down and the next arm, an arm launched
--     before recycled first, the 3 rounds' service and leaving, a sunk ship;
--   co-op: the host's "es", a joiner's copy of it (the unlock, the room's count, its NEXT row, landing closed / open),
--     a joiner's purchase asked of the host, the host's check at the room's price;
--   sv_zfa44.lua's production dressing without the ZFA-44 installed (said once, not tried again for a minute);
--   (2026-11-07, the build's names) the main menu's rows and names (ESC.setup), no round without them; RE_SV_EscortReset
--     before each operation; the escorts' cover records (<rec>Guard), her CruiseSlow, the finals' FinalSlow / FinalShort;
--     each escort released onto the landing circuit with its start ahead (none lined up: hold_max_s, started anyway); the
--     parking slots A-E by landing order; the build's leg and slot flags taken (legSync, stale ones before the reset's
--     2 s not); the allies' take-offs held while she lands; the six launcher arms a ship, an arm whose flight is up
--     skipped, a unit on the spawner's list taken off first, a downed flight's unit recycled; the pose flight's RE_SV_ZfaGo;
--   (2026-11-07, sv_escort_subs.lua, sv_subs.lua's strip) the KMG tag on their boxes; what they say: the check-in, the
--     first enemies at her, the waves ({dir}), her hits and hurt marks, an enemy near her shot down by her escorts or you,
--     her final (COMONA TOWER), touchdown and landing, each escort's own landing line, ROCK's last words and the reply,
--     nobody quoting him after, her thanks whole on the strip (no callout) then Comona's, her loss; the Anomalies' wait
--     for her (ESC.anomalyOk, after_lost, no wait without THE ESCORT) and her warning the round before (not VALKA's);
--     every line at most 70 characters, each speaker its colour.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and tostring(s):find(part, 1, true) ~= nil end
local function near(a, b, tol) return type(a) == "number" and math.abs(a - b) <= (tol or 1e-6) end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore
math.randomseed(7)

-- the game's world, stubbed
VERSION = "escort.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local nextAddr = 100
local function addr() nextAddr = nextAddr + 1; return nextAddr end
local notify = {}                                 -- NotifyOnNewObject's callbacks by class
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
local function made(cls, o) for _, fn in ipairs(notify[cls] or {}) do fn(o) end end
function FindAllOf() return {} end
local GI = { full = "GameInstance", addr = 1 }
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
local statics = {}
function StaticFindObject(p) return statics[p] end
local events, alive, spawns, recycled, texts, msgs, asks = {}, {}, {}, {}, {}, {}, {}
local function evFired(name) for _, e in ipairs(events) do if e == name then return true end end return false end
local function evCount(name) local n = 0; for _, e in ipairs(events) do if e == name then n = n + 1 end end return n end
function SV_Event(name) events[#events + 1] = name; return 1 end
function SV_UnitAlive(u) local n = alive[u]; if n == nil then return -7 end return n end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
local SIZE = { SV_Unit_Charlene = 1, SV_Unit_EscYorke = 1, SV_Unit_EscRock = 1, SV_Unit_EscAli = 1, SV_Unit_EscDanielle = 1,
               SV_Unit_Cargo1 = 1, SV_Unit_Cargo2 = 1, SV_Unit_ZfaA = 4, SV_Unit_ZfaB = 4 }
local hullAt = { SV_Unit_Cargo1 = { 1610476, 249000 } }    -- (ship 2's hull never found: its spot)
local refuse = {}
function SV_Spawn(u, x, y, z, yaw)
    if refuse[u] then return refuse[u] end
    spawns[#spawns + 1] = { u = u, x = x, y = y, z = z, yaw = yaw }
    local n = SIZE[u] or 2
    alive[u] = n
    if hullAt[u] then                              -- (its hull, as the game makes it while it spawns)
        local h = setmetatable({ full = "BP_VE021_ctslf_01_CP_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_VE021_ctslf_01_CP_C_" .. addr(),
                                 addr = addr(), X = hullAt[u][1], Y = hullAt[u][2], Z = 50, yaw = 0 }, nil)
        h = setmetatable(h, { __index = { K2_GetActorLocation = function(self) return { X = self.X, Y = self.Y, Z = self.Z } end,
                                          K2_GetActorRotation = function(self) return { Pitch = 0, Yaw = self.yaw, Roll = 0 } end,
                                          SetActive = function(self) self.off = true end, SetActorHiddenInGame = function() end,
                                          SetActorEnableCollision = function() end, SetActorTickEnabled = function() end } })
        made("/Script/Live.LiveAIGameObject", h)
    end
    return n
end
function SV_Recycle(u, f) recycled[#recycled + 1] = u .. ":" .. tostring(f); return 1 end
function SV_SetText(k, v) texts[k] = v; return 1 end
local presses = {}
function SV_ShopRequest(probe) if probe then return 1 end return table.remove(presses, 1) or "" end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_flights.lua"); part("sv_shop.lua"); part("sv_allies.lua"); part("sv_tactical.lua")
local onAirfield = false
function playerOnAirfield() return onAirfield end
local callouts = {}
function hudCallout(t, sub) callouts[#callouts + 1] = tostring(t) .. " / " .. tostring(sub) end
local function callout(pat) for _, c in ipairs(callouts) do if c:find(pat, 1, true) then return c end end return nil end
local lbs = {}
LB.special = function(k, won, s) lbs[#lbs + 1] = { k = k, won = won, s = s } end
LB.stat = function() end
SPC.kinds = SPC.kinds or {}
local rawSpawnAt = 0
DIR = { spawnAt = function() rawSpawnAt = rawSpawnAt + 1; return nil end }
local spawned = {}
function spawnFlight(u, ml, pose)                   -- (the round's spawner: recorded, its flight up)
    spawned[#spawned + 1] = { u = u, pose = pose, at = clock }
    D.up[u] = true
    return flightSize(u)
end
part("sv_subs.lua")                                  -- ((2026-11-07) the subtitle strip: what they say)
part("sv_escort.lua")
part("sv_escort_subs.lua")
part("sv_zfa44.lua")
local function line(pat, from)
    for i = #logs, from or 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end
    return nil
end
-- the subtitle lines said since log line `from` ("WHO: text", sv_subs.lua's log), and whether one of them is a line of
-- the list l (flattened; vals filled in) by who
local function subsSince(from)
    local out = {}
    for i = from or 1, #logs do
        local who, text = logs[i]:match("^subs: (.-): (.*) %(%d+%.%d s%)$")
        if who then out[#out + 1] = { who = who, text = text } end
    end
    return out
end
local function flatL(l, out)
    out = out or {}
    if type(l) == "string" then out[#out + 1] = l elseif type(l) == "table" then for _, x in ipairs(l) do flatL(x, out) end end
    return out
end
local function saidFrom(l, from, vals)
    local n = 0
    for _, s in ipairs(subsSince(from)) do
        for _, x in ipairs(flatL(l)) do
            local who, text = ESUB.line(x, vals)
            if s.who == who and s.text == text then n = n + 1 end
        end
    end
    return n
end
local C, K = CFG.specials.escort, CFG.allies.carrier
local shopTicks = 0
local function press(item)                          -- (a STORE row pressed: the landing menu's queue, shopTick takes it)
    presses[#presses + 1] = "SV_Buy_" .. item
    shopTicks = shopTicks + 1
    shopTick(shopTicks * 4)
end

---------------------------------------------------------------------------------------------------- the main menu
print("the main menu")
local function dt(name, rows)
    local t = { full = name, addr = addr(), rows = rows }
    function t:FindRow(r) return self.rows[tostring(r)] end
    function t:AddRow(r, v) self.rows[tostring(r)] = v end
    return t
end
local npcT = dt("DT_NPC", {})
local mineT = dt("DT_SV_NpcRows", { SV_Esc_Su57 = { r = 1 }, SV_Esc_Su33 = { r = 2 }, SV_Esc_Su35 = { r = 3 }, SV_Zfa_Ally = { r = 4 },
                                    SV_Zfa_Drone = { r = 6 } })
statics[PROBE_TABLES[2].path], statics[CFG.specials.shuttle.npc_rows] = npcT, mineT
-- ((2026-11-07) the ZFA-44 host's own model row (its name "ZFA-44", not the Su-47's), into DT_NPC_Model first)
local modelT, mineModelT = dt("DT_NPC_Model", {}), dt("DT_SV_ModelRows", { SV_Model_Zfa = { m = 1 }, SV_Model_ZfaDrone = { m = 2 } })
statics[ACE.model_table], statics[ACE.model_rows] = modelT, mineModelT
ESC.setup()
check(npcT.rows.SV_Esc_Su57 and npcT.rows.SV_Esc_Su33 and npcT.rows.SV_Esc_Su35 and npcT.rows.SV_Zfa_Ally and ESC.rowsOk == true
      and ESC.zfaRowOk == true and has(line("escort: the escorts' and the ZFA-44's rows"), "SV_Zfa_Ally in DT_NPC"),
      "the escorts' and the ZFA-44 host's rows from DT_SV_NpcRows into DT_NPC at the main menu, logged")
check(modelT.rows.SV_Model_Zfa ~= nil and modelT.rows.SV_Model_ZfaDrone ~= nil and npcT.rows.SV_Zfa_Drone ~= nil
      and has(line("escort: the escorts' and the ZFA-44's rows"), "SV_Zfa_Drone in DT_NPC"),
      "... both ZFA-44 hosts' own model rows (named ZFA-44) into DT_NPC_Model before them, the container drone's row too")
do                                                  -- (without its model row: no ZFA-44 host, said)
    local keepM = statics[ACE.model_rows]
    statics[ACE.model_rows] = dt("DT_SV_ModelRows", {})
    local okM, why = ZLAS.zfaModel()
    modelT.rows.SV_Model_Zfa = nil
    okM, why = ZLAS.zfaModel()
    check(okM == false and has(why, "SV_Model_Zfa not in"), "its model row missing from Survival's table: no host, said (" .. tostring(why) .. ")")
    statics[ACE.model_rows] = keepM
    ZLAS.zfaModel()
end
-- ((2026-11-07) the user: they "should each have a squadron tag KMG, as well as Charlene")
check(texts.SV_CharleneCall == "[KMG] CHARLENE" and texts.SV_Yorke == "[KMG] YORKE" and texts.SV_Rock == "[KMG] ROCK"
      and texts.SV_Ali == "[KMG] ALI" and texts.SV_Danielle == "[KMG] DANIELLE" and texts.SV_Cargo == K.name
      and texts.SV_Zfa44 == "ZFA-44" and texts.SV_ZfaSub == "VAMPIRE",
      "the eight names on their boxes set there (SV_SetText), CHARLENE's and her escorts' with the KMG tag, the ZFA-44's "
      .. "ZFA-44 over VAMPIRE (2026-11-07: it read SU-47)")
-- ((2026-11-07) the ZFA-44s' anti-missile laser, sv_escort_laser.lua) the host's row made from its laser twin's struct when
-- the laser's on and its fire-control row went into DT_NPC_FCS (that row passed on whole, never read: hard rule 29); the
-- plain row when it's off, when Survival's FCS table hasn't the row, when DT_NPC_FCS doesn't load
local Z = K.zfa
local function laserSetup(on, fcsRows, mineFcsRows)
    ESC.setupDone, ESC.setupTries, Z.laser = nil, 0, on
    local n2 = dt("DT_NPC", {})
    local m2 = dt("DT_SV_NpcRows", { SV_Esc_Su57 = { r = 1 }, SV_Esc_Su33 = { r = 2 }, SV_Esc_Su35 = { r = 3 },
                                     SV_Zfa_Ally = { r = 4 }, SV_Zfa_AllyTLS = { r = 5 }, SV_Zfa_Drone = { r = 6 },
                                     SV_Zfa_DroneTLS = { r = 7 } })
    local f2 = fcsRows and dt("DT_NPC_FCS", fcsRows) or nil
    statics[PROBE_TABLES[2].path], statics[CFG.specials.shuttle.npc_rows] = n2, m2
    statics[FCS_TABLE], statics[Z.laser_fcs_table] = f2, mineFcsRows and dt("DT_SV_NpcFCS", mineFcsRows) or nil
    local from = #logs + 1
    ESC.setup()
    return n2, f2, line("escort: the escorts' and the ZFA-44's rows", from)
end
local fcsRow = setmetatable({}, { __index = function(_, k) error("the FCS row's " .. tostring(k) .. " was read") end })
local n2, f2, said = laserSetup(true, {}, { SV_FCS_ZfaTLS = fcsRow })
check(n2.rows.SV_Zfa_Ally and n2.rows.SV_Zfa_Ally.r == 5 and n2.rows.SV_Zfa_AllyTLS == nil and rawequal(f2.rows.SV_FCS_ZfaTLS, fcsRow)
      and n2.rows.SV_Zfa_Drone and n2.rows.SV_Zfa_Drone.r == 7 and has(said, "SV_Zfa_Drone in DT_NPC (with the anti-missile laser: SV_Zfa_DroneTLS")
      and ZLAS.armed == true and ESC.zfaRowOk == true and has(said, "SV_Zfa_Ally in DT_NPC (with the anti-missile laser"),
      "the laser on: SV_FCS_ZfaTLS into DT_NPC_FCS whole, SV_Zfa_Ally made from SV_Zfa_AllyTLS's struct, logged")
n2, f2, said = laserSetup(false, {}, { SV_FCS_ZfaTLS = fcsRow })
check(n2.rows.SV_Zfa_Ally and n2.rows.SV_Zfa_Ally.r == 4 and f2.rows.SV_FCS_ZfaTLS == nil and ZLAS.armed == false
      and ESC.zfaRowOk == true and has(said, "SV_Zfa_Ally in DT_NPC (laser off"), "laser = false: the plain host, nothing in DT_NPC_FCS")
n2, f2, said = laserSetup(true, {}, {})
check(n2.rows.SV_Zfa_Ally and n2.rows.SV_Zfa_Ally.r == 4 and ZLAS.armed == false and ESC.zfaRowOk == true
      and has(said, "(no laser: SV_FCS_ZfaTLS not in DT_SV_NpcFCS"), "no fire-control row in Survival's table: the plain host, said")
n2, f2, said = laserSetup(true, nil, { SV_FCS_ZfaTLS = fcsRow })
check(n2.rows.SV_Zfa_Ally and n2.rows.SV_Zfa_Ally.r == 4 and ZLAS.armed == false and ESC.zfaRowOk == true
      and has(said, "(no laser: DT_NPC_FCS not loaded"), "DT_NPC_FCS not loaded: the plain host, said")
n2, f2, said = laserSetup(true, {}, { SV_FCS_ZfaTLS = fcsRow })          -- (on again, for the rest of the test)
-- its fire control in the log, once a plane (slot 3 Survival's arm with the laser); its interceptions from the build's flag
local function obj(full, t) t = t or {}; t.full = full; t.IsValid = function() return true end; t.GetFullName = function() return full end; return t end
local armList = { obj("x", { SystemName = FName("Flr") }), obj("x", { SystemName = FName("Gun") }), false,
                  obj("x", { SystemName = FName("BP_FCS_CIWS"),
                             ProjectileModule = obj("pm", { WeaponClass = obj("BlueprintGeneratedClass /Game/Blueprints/Weapons/Laser/Tls/UAVN/BP_SwingTLS_ForMSL.BP_SwingTLS_ForMSL_C") }),
                             GetClass = function() return obj("BlueprintGeneratedClass /Game/Mods/SurvivalMode/Weapons/BP_FCS_SV_ZfaTLS.BP_FCS_Vessel_CIWS_00_C") end }) }
local fcsC = obj("fcs", { AllArms = { ForEach = function(_, fn) for i = 1, 4 do fn(i, { get = function() return armList[i] or nil end }) end end } })
local laserPlane = obj("BP_OP1026_su47_CP_Ally_C plane", { addr = 4242, GetAddress = function() return 4242 end, FireControlSystemComponent = fcsC })
local D0 = D
D = D or {}
local from = #logs + 1
ZLAS.arms(laserPlane, "E_Unit_01_drone_5_0"); ZLAS.arms(laserPlane, "E_Unit_01_drone_5_0")
local armLine = line("zfa laser: E_Unit_01_drone_5_0 plane 4242 fire control:", from)
local armLines = 0
for i = from, #logs do if logs[i]:find("zfa laser: ", 1, true) then armLines = armLines + 1 end end
check(armLines == 1 and has(armLine, "0 Flr; 1 Gun; 2 -; 3 BP_FCS_CIWS BP_SwingTLS_ForMSL (Survival's arm)")
      and has(armLine, "-> the laser in slot 3"), "a ZFA-44's fire control in the log once, the laser's arm in slot 3")
local rawFlags, hits = svFlags, 0
svFlags = function() return { SV_ZfaTLSHits = hits } end   -- luacheck: ignore
from = #logs + 1
ZLAS.tick(); hits = 2; ZLAS.tick(); hits = 3; ZLAS.tick(); ZLAS.tick()
local hitLines = {}
for i = from, #logs do if logs[i]:find("lasers have shot down", 1, true) then hitLines[#hitLines + 1] = logs[i] end end
check(#hitLines == 2 and hitLines[1] == "carrier: the ZFA-44s' lasers have shot down 2 missiles (+2)"
      and hitLines[2] == "carrier: the ZFA-44s' lasers have shot down 3 missiles (+1)",
      "the lasers' interceptions (SV_ZfaTLSHits) logged as the count goes up, once each")
svFlags, D = rawFlags, D0                                   -- luacheck: ignore

-- planes
local orders = {}
local PM = {}
PM.__index = PM
function PM:K2_GetActorLocation() return { X = self.X, Y = self.Y, Z = self.Z } end
function PM:GetVelocity() return { X = self.vx or 0, Y = self.vy or 0, Z = 0 } end
function PM:K2_GetActorRotation() return { Pitch = 0, Yaw = self.yaw or 0, Roll = 0 } end
function PM:EngagementOrderOverride(o, target, prio) orders[#orders + 1] = { plane = self, target = target, prio = prio } end
function PM:EnableLandingGear(b) self.gear = b end
function PM:SetIsInvincible(b) self.inv = b end
function PM:EnableAvoidObstacle(b) self.avoid = b end
function PM:SetActive() self.active = false end
function PM:SetActorHiddenInGame(b) self.hidden = b end
function PM:SetActorEnableCollision() end
function PM:SetActorTickEnabled() end
local function pose(o, x, y, z, hdg, kmh)
    o.X, o.Y, o.Z, o.yaw = x, y, z, (hdg or 0) - 90
    local h, v = math.rad(hdg or 0), (kmh or 0) / 0.036
    o.vx, o.vy = math.sin(h) * v, -math.cos(h) * v
end
local function plane(unit, x, y, z, hdg, kmh)
    local o = setmetatable({ addr = addr(), HealthInternal = 1300, MaxHealth = 130 }, PM)
    o.full = "BP_Plane_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.BP_" .. tostring(unit) .. "_" .. o.addr
    pose(o, x, y, z, hdg, kmh)
    return o
end
local function fwd(h) h = math.rad(h); return math.sin(h), -math.cos(h) end
local function before(p, hdg, m, z, kmh)            -- (a point m metres before p along heading hdg)
    local fx, fy = fwd(hdg)
    return p[1] - fx * m * 100, p[2] - fy * m * 100, z or p[3] or 750, hdg, kmh
end
local g = C.geo
local pawn = setmetatable({ full = "BP_PlayerPlane_C PL_SurvivalMode", addr = addr() }, PM)
survivalPC = { full = "PlayerController PL_SurvivalMode", addr = addr(), Pawn = pawn }
RUN = newRun and newRun() or RUN
RUN.credits = 0
local now = 0
D = { round = 9, state = "spawning", now = 0, up = {}, flown = {}, queue = {}, spare = {}, taken = {}, at = 0 }
local function run(secs, each)
    for _ = 1, math.floor(secs / 0.25 + 0.5) do
        now, clock = now + 0.25, clock + 0.25
        D.now = now
        if each then each() end
        if D.special and SPC.kinds[D.special.kind] then SPC.kinds[D.special.kind].tick(now, D.special) end
        ESC.tick(now)
        SUB.hudTick(now, true, false)                -- (the strip's queue moving, as the HUD's tick moves it)
    end
end

---------------------------------------------------------------------------------------------------- the kind
print("the special kind")
local k = SPC.kinds.escort
check(type(k) == "table" and type(k.spawn) == "function" and type(k.busy) == "function" and type(k.over) == "function"
      and type(k.row) == "function" and k.sub(CFG.hud.text) == C.text.sub, "SPC.kinds.escort: spawn, tick, busy, over, row, its callout")
local inRot = false
for _, x in ipairs(CFG.specials.rotation) do if x == "escort" then inRot = true end end
check(inRot and C.from_round == 9 and C.once == true and CFG.specials.escort.enabled, "in the rotation, from round 9, once a run")
check(ALLY.unit.SV_Unit_EscYorke == "air" and ALLY.unit.E_Unit_01_drone_1_0 == "air" and ALLY.unit.SV_Unit_ZfaA == "air"
      and ALLY.unit.SV_Unit_Charlene == "charlene" and ALLY.unit.SV_Unit_Cargo2 == "cargo",
      "every unit an ally: the escorts and the ZFA-44s as allied aircraft, CHARLENE and the ships their own")
ESC.rowsOk = false
check(k.ready() == false and has(line("escort: no ESCORT round: its escorts' DT_NPC rows aren't in"), "not added"),
      "not ready without its escorts' rows in DT_NPC, logged")
ESC.rowsOk = true
alive.SV_Unit_EscRock = -2
check(k.ready() == false and has(line("escort: no ESCORT special in this build"), "SV_Unit_EscRock"),
      "not ready with a unit missing from the world data (SV_UnitAlive -2), logged")
alive.SV_Unit_EscRock = nil
clock = clock + 31
check(k.ready() == true, "ready with every unit there (SV_UnitAlive -7: not spawned)")
check(k.budget(20) == 20 and k.budget(3) >= 2, "its round's budget x budget_x, whole 2-ships")

---------------------------------------------------------------------------------------------------- spawn and route
print("spawn and route")
D.special = { kind = "escort", state = "pending" }
check(k.spawn(now) == true and ESC.S ~= nil and D.special.state == "route" and RUN.escort and RUN.escort.flown == 9,
      "spawned: the round's special in its route, flown this run")
check(events[1] == "RE_SV_EscortReset" and has(line("escort: RE_SV_EscortReset"), "every leg and slot flag back to 0"),
      "RE_SV_EscortReset before the operation's spawns")
check(k.ready() == false, "not ready again in the same run (once)")
local sp = {}
for _, s in ipairs(spawns) do sp[s.u] = s end
local st = C.start
check(sp.SV_Unit_Charlene and sp.SV_Unit_Charlene.x == st.x and sp.SV_Unit_Charlene.y == st.y and sp.SV_Unit_Charlene.z == st.z
      and near(sp.SV_Unit_Charlene.yaw, 55 - 90), "CHARLENE at the south-west start, 3 km up, heading 055 (yaw -35)")
do
    -- (code review of 2026-11-07, finding 2) each escort where the build's route starts: tools/survival_events.py's
    -- ESC_START and ESC_ESCORTS (name, row, km to her right on the way in, km above her), across the start -> IAF line
    -- (esc_route_pts: its right (-uy, ux), north being -y); none behind her
    local se = readAll(MOD .. "/../../../tools/survival_events.py")
    local sx, sy, sz = se:match("\nESC_START = %(([%-%d%.]+), ([%-%d%.]+), ([%-%d%.]+)%)")
    sx, sy, sz = tonumber(sx), tonumber(sy), tonumber(sz)
    local block = se:match("\nESC_ESCORTS = (%b[])")
    local want = {}
    for nm, right, upKm in (block or ""):gmatch("%('(%a+)', '[%w_]+', (%-?[%d%.]+), (%-?[%d%.]+)%)") do
        want[#want + 1] = { unit = "SV_Unit_Esc" .. nm, right = tonumber(right), up = tonumber(upKm) }
    end
    check(sx == st.x and sy == st.y and sz == st.z and #want == 4,
          "the build's start and its four escorts read from survival_events.py (" .. #want .. ")")
    local g = C.geo.iaf
    local dx, dy = g[1] - st.x, g[2] - st.y
    local L = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dx / L, dy / L
    local rx, ry = -uy, ux
    for _, w in ipairs(want) do
        local s = sp[w.unit]
        local ex, ey, ez = st.x + rx * w.right * 1e5, st.y + ry * w.right * 1e5, st.z + w.up * 1e5
        local off = s and math.sqrt((s.x - ex) ^ 2 + (s.y - ey) ^ 2) / 100 or -1
        local along = s and ((s.x - st.x) * ux + (s.y - st.y) * uy) / 100 or -1
        local side = s and ((s.x - st.x) * rx + (s.y - st.y) * ry) / 100 or 0
        check(s and off >= 0 and off <= 1 and near(s.z, ez, 1) and math.abs(along) <= 1 and (side > 0) == (w.right > 0),
              string.format("%s at its route's start: %.0f m to her %s (the build's %.1f km), %.0f m up (%.2f km), %.1f m along her way, %.1f m off",
                  w.unit, math.abs(side), side > 0 and "right" or "left", w.right, s and (s.z - st.z) / 100 or -1, w.up, along, off))
    end
    local y, r = sp.SV_Unit_EscYorke, sp.SV_Unit_EscRock
    check(y and r and ((y.x - st.x) * rx + (y.y - st.y) * ry) > 0 and ((r.x - st.x) * rx + (r.y - st.y) * ry) < 0,
          "YORKE to her right, ROCK to her left (the old side signs had them the other way round, and behind her)")
end
check(callout(C.text.go), "the round's callout: " .. C.text.go)
-- their planes come up (the tick's pending -> logPlane)
local P = {}
for _, s in ipairs(spawns) do
    local o = plane(s.u, s.x, s.y, s.z, 55, 600)
    P[s.u] = o
    logPlane(o, s.u, nil)
end
check(ESC.planes.SV_Unit_Charlene and #ESC.planes.SV_Unit_Charlene == 1, "her plane recorded")
local inAlly = {}
for _, p in ipairs(ALLY.state().planes) do inAlly[p.unit] = true end
check(inAlly.SV_Unit_EscYorke and not inAlly.SV_Unit_Charlene, "the escorts among the allied aircraft (their kills the allies'), not her")
run(1.5)
check(evFired("RE_SV_CharGo") and evFired("RE_SV_EscYorkeGo") and evFired("RE_SV_EscRockGo") and evFired("RE_SV_EscAliGo")
      and evFired("RE_SV_EscDanielleGo"), "each one's route record go_delay_s after its spawn")
check(P.SV_Unit_Charlene.HealthInternal == 1300 * C.health_x, string.format("her health x%g (%d)", C.health_x, P.SV_Unit_Charlene.HealthInternal))
-- the enemies after her
CFG.specials.escort.attack.share = 1.0
local E1, E2 = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air0"
D.up[E1], D.up[E2] = true, true
local e1 = plane(E1, st.x + 900000, st.y - 600000, 300000, 235, 800)
local e2 = plane(E2, st.x + 800000, st.y - 500000, 300000, 235, 800)
planes = { { obj = e1, unit = E1, name = "e1", addr = e1.addr, at = { X = st.x + 300000, Y = st.y - 100000, Z = 300000 } },
           { obj = e2, unit = E2, name = "e2", addr = e2.addr } }
orders = {}
run(5)
local onHer = 0
for _, o in ipairs(orders) do if o.target == P.SV_Unit_Charlene and o.prio == 9 then onHer = onHer + 1 end end
check(onHer >= 2 and ESC.holds(E1) and ESC.holds(E2) and has(line("escort: " .. E1 .. " sent after CHARLENE"), "TargetFirst"),
      "the round's flights sent after her (EngagementOrderOverride TargetFirst), held from the director and the hunts")
local guard = 0
for _, o in ipairs(orders) do if o.target == e1 and (o.plane == P.SV_Unit_EscYorke or o.plane == P.SV_Unit_EscRock) then guard = guard + 1 end end
check(guard > 0 and has(line("escort: guarding CHARLENE"), "YORKE onto e1"), "the escorts onto the enemy near her")
check(evFired("RE_SV_EscYorkeGuard") and evFired("RE_SV_EscDanielleGuard") and ESC.S.ac[2].guardOn and has(line("escort: YORKE covers CHARLENE"), "Guard"),
      "the build's cover (<rec>Guard) from the first enemy near her")
local g0 = evCount("RE_SV_EscYorkeGuard")
orders = {}
run(11)
check(evCount("RE_SV_EscYorkeGuard") > g0, "... given again every record_every_s (its area follows her)")
local again = 0
for _, o in ipairs(orders) do if o.target == P.SV_Unit_Charlene then again = again + 1 end end
check(again >= 2, "the order given again every again_s")
do                                                  -- ((2026-11-07) what they say as she spawns: one check-in, whole)
    local whole = false
    for _, ex in ipairs(C.text.say.go) do
        if saidFrom(ex, 1) == #ex then whole = true end
    end
    local who = {}
    for _, s in ipairs(subsSince(1)) do who[s.who] = true end
    check(whole and who["COMONA CONTROL"] and who.CHARLENE and who.YORKE and who.ROCK and who.ALI and who.DANIELLE,
          "the check-in on the subtitle strip: COMONA CONTROL, CHARLENE and each of her escorts, one exchange whole")
    check(saidFrom(C.text.say.first_attack, 1) == 0, "the first enemies sent at her: her line waits for the check-ins")
end
do
    CFG.specials.escort.ahead.share = 1.0
    local p = DIR.spawnAt(E1)
    local her = P.SV_Unit_Charlene
    local d = p and math.sqrt((p.x - her.X) ^ 2 + (p.y - her.Y) ^ 2) / 100000
    check(p and has(p.centre, "CHARLENE") and d and d > 8 and d < 17 and rawSpawnAt == 0,
          string.format("a round flight's spawn point ahead of her (%.1f km), not the director's", d or -1))
end
-- ((2026-11-07) the user: "Keep spawning Multiple enemy fighters until she lands, have them range from 4 to 12 aircraft
-- spawning per wave in different directions") a wave every every_s while she flies, min_n .. max_n each, all of it from
-- one direction round her, never the last wave's nor one next to it
local SECI = {}
for i, nm in ipairs(ESC.SECTOR) do SECI[nm] = i end
local function wavesOf()
    local ws = {}
    for _, sp in ipairs(spawned) do
        local n = sp.pose and sp.pose.why and tonumber(sp.pose.why:match("^CHARLENE's wave (%d+)"))
        if n then
            ws[n] = ws[n] or { n = 0, flights = {}, sec = SECI[sp.pose.why:match("%((.-) of her%)")], at = sp.at }
            ws[n].n = ws[n].n + flightSize(sp.u)
            table.insert(ws[n].flights, sp)
        end
    end
    return ws
end
planes[2].down = true
local HP = P.SV_Unit_Charlene
pose(HP, ZONE.X, ZONE.Y, 300000, 55, 600)          -- (her start's at the combat zone's corner: in its middle here)
run(41)
run(C.waves.every_s * 2 + 1)
local ws = wavesOf()
check(#ws >= 3 and has(line("escort: wave 3:"), "of CHARLENE, from the"), "a wave every every_s while she flies (" .. #ws .. " waves)")
local okN, okDir, okGap, sizes = true, true, true, {}
for i, w in ipairs(ws) do
    sizes[#sizes + 1] = tostring(w.n)
    if w.n < C.waves.min_n or w.n > C.waves.max_n then okN = false end
    if i > 1 then
        local dd = math.min((w.sec - ws[i - 1].sec) % 8, (ws[i - 1].sec - w.sec) % 8)
        if not w.sec or dd <= 1 then okDir = false end
        if math.abs(w.at - ws[i - 1].at - C.waves.every_s) > 0.6 then okGap = false end
    end
end
check(okN, "each wave min_n .. max_n aircraft (" .. table.concat(sizes, ", ") .. ")")
check(okDir, "each from a new direction round her, never the last one's nor next to it")
do                                                  -- (her start is at the combat zone's corner: every wave's spot inside it)
    local m, out = ZONE.HALF - 300000, 0
    for _, w in ipairs(ws) do
        for _, f in ipairs(w.flights) do
            if math.abs(f.pose.x - ZONE.X) >= m - 1 or math.abs(f.pose.y - ZONE.Y) >= m - 1 then out = out + 1 end
        end
    end
    check(out == 0, "no wave's flight put on the combat zone's edge (" .. out .. ")")
end
check(okGap, "every_s apart")
check(saidFrom(C.text.say.first_attack, 1) == 1, "... then said, once")
do                                                  -- (each wave sent at her: a line naming where it's from, room allowing)
    local n = 0
    for _, dir in ipairs({ "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }) do
        n = n + saidFrom(C.text.say.wave, 1, { dir = dir })
    end
    check(n >= 1 and n <= #ws and has(line("escort: wave"), "from the"), string.format("a wave's line with its direction (%d of %d waves)", n, #ws))
end
-- ((2026-11-07) "Being Attacked, Being Defended") her health down 10 points: her hit line; under 75%: hurt_75; an enemy
-- near her shot down by her escorts: theirs; by you: hers
do
    SUB.clear("test")
    local HPo = P.SV_Unit_Charlene
    local full = HPo.HealthInternal
    local from = #logs + 1
    HPo.HealthInternal = math.floor(full * 0.88)
    run(1)
    check(saidFrom(C.text.say.hit, from) == 1, "hit (100% -> 88%): her hit line")
    SUB.clear("test")
    HPo.HealthInternal = math.floor(full * 0.80)
    run(1)
    check(saidFrom(C.text.say.hit, from) == 1, "... not again within hit_gap_s")
    HPo.HealthInternal = math.floor(full * 0.70)
    run(1)
    check(saidFrom(C.text.say.hurt_75, from) >= 1 and has(line("escort subs: CHARLENE under 75%"), "70%"), "under 75%: her hurt_75 exchange")
    HPo.HealthInternal = full
    SUB.clear("test")
    run(C.text.say.defended_gap_s + 1)
    local function foe(name, by)
        local o = plane("ERA_Unit_09_Dep_Air0", HPo.X + 100000, HPo.Y, HPo.Z, 0, 700)
        local p = { obj = o, unit = "ERA_Unit_09_Dep_Air0", name = name, addr = o.addr, at = { X = HPo.X + 100000, Y = HPo.Y, Z = HPo.Z },
                    dmg = { [by] = 50 } }
        planes[#planes + 1] = p
        return p
    end
    local f1 = foe("BP_Def1", "allies")
    run(0.5)
    f1.down = true
    from = #logs + 1
    run(0.5)
    check(saidFrom(C.text.say.defended_ally, from) == 1 and has(line("escort subs: BP_Def1 shot down near CHARLENE"), "by allies"),
          "an enemy 1 km from her shot down by her escorts: their line (or hers for them)")
    SUB.clear("test")
    run(C.text.say.defended_gap_s + 1)
    local f2 = foe("BP_Def2", "you")
    run(0.5)
    f2.down = true
    from = #logs + 1
    run(0.5)
    check(saidFrom(C.text.say.defended_you, from) == 1, "... by you: her thanks to the pilot")
    local f3 = foe("BP_Def3", "you")
    run(0.5)
    f3.down = true
    from = #logs + 1
    run(0.5)
    check(saidFrom(C.text.say.defended_you, from) == 0, "... not again within defended_gap_s")
    SUB.clear("test")
end
do                                                  -- (a wave's flights together, km out from her, facing her)
    local w = ws[#ws]
    local f1, f2 = w.flights[1].pose, w.flights[#w.flights].pose
    local apart = math.sqrt((f1.x - f2.x) ^ 2 + (f1.y - f2.y) ^ 2) / 100000
    check((#w.flights == 1 or apart >= 1.0) and apart <= 16 * math.rad(C.waves.spread_deg) * (#w.flights - 1) + 0.01
          and f1.z >= 250000 and f1.z <= 400000,
          string.format("a wave's flights side by side (%.1f km apart for %d flights), alt_m up", apart, #w.flights))
end
-- max_up enemy aircraft up: the next wave held
do
    local keep = planes
    local full = {}
    for i = 1, C.waves.max_up do full[i] = { unit = "x" .. i } end
    planes = full
    local n0 = #wavesOf()
    run(C.waves.every_s + 1)
    check(#wavesOf() == n0 and has(line("escort: wave " .. (n0 + 1) .. " held:"), "max_up"), "held while max_up enemy aircraft are up")
    planes = keep
    run(6)
    check(#wavesOf() == n0 + 1, "... and sent once there's room")
end
do                                                  -- (at the zone's corner, her start: from a direction inside it)
    pose(HP, st.x, st.y, 300000, 55, 600)
    ESC.S.reinf.at = 0
    run(0.25)
    local all = wavesOf()
    local w, prev = all[#all], all[#all - 1]            -- (2026-11-07: against the wave just before it, not an older one)
    local mid = w.flights[math.floor((#w.flights + 1) / 2)].pose
    local m = ZONE.HALF - 300000
    check(math.abs(mid.x - ZONE.X) < m - 1 and math.abs(mid.y - ZONE.Y) < m - 1 and w.sec ~= prev.sec,
          "at her start (the combat zone's corner) a wave from a direction inside the zone")
end

---------------------------------------------------------------------------------------------------- her landing
print("her landing")
local fromLand = #logs + 1
local H = P.SV_Unit_Charlene
pose(H, before(g.iaf, 55, 1500, g.iaf[3], 450))
run(0.5)
local S = ESC.S
check(evFired("RE_SV_CharCruiseSlow") and has(line("her route at 600 km/h"), "RE_SV_CharCruiseSlow fired") and not evFired("RE_SV_EscYorkeCruiseSlow"),
      "her route at 450 within cruise_slow_km of the touchdown (her escorts covering her, not on their routes)")
check(evFired("RE_SV_CharFinal") and H.gear == true and S.state == "landing" and D.special.state == "landing",
      "her final 1.5 km before the approach fix: RE_SV_CharFinal, gear down, the round landing")
check(evFired("RE_SV_EscYorkeOrbit") and evFired("RE_SV_EscRockOrbit") and evFired("RE_SV_EscAliOrbit") and evFired("RE_SV_EscDanielleOrbit"),
      "the escorts hold over her as she's on final (their Orbit records: area on her, no path)")
check(not evFired("RE_SV_AirfieldClose") and not S.closed and callout(C.text.final),
      "her final called out; the players' landing still open with her 16 km out (close_km)")
check(saidFrom(C.text.say.final, fromLand) >= 3 and subsSince(fromLand)[1].who == "COMONA TOWER",
      "her final on the strip: COMONA TOWER clears her to land, her reply, her escorts told to hold")
check(ESC.runwayBusy() == true and ALLY.escortHold("MOONCHILD") == true and has(line("allies: MOONCHILD's take-off held"), "THE ESCORT is landing"),
      "the allies' take-offs held while she lands (the runway busy)")
local Y = P.SV_Unit_EscYorke
local function nFired(ev) local n = 0; for _, e in ipairs(events) do if e == ev then n = n + 1 end end; return n end
pose(H, before(g.touchdown, 67, 9000, 750 + 47000, 320)); run(0.5)
pose(H, before(g.touchdown, 160, 10500, 750 + 47000, 320)); run(0.5)    -- (heading off south, 1.5 km farther out)
check(nFired("RE_SV_CharFinal") == 2 and has(line("escort: CHARLENE off her approach"), "her path given again (1 of 3)"),
      "off her approach (1.5 km farther out than her closest): her path given again")
run(1)
check(nFired("RE_SV_CharFinal") == 2, "... not again within recover_gap_s")
check(nFired("RE_SV_CharCruiseSlow") == 2 and has(line("escort: CHARLENE's final at 600 km/h"), "RE_SV_CharCruiseSlow fired"),
      "her final at 450 a second after her Final record (her route given again at its 450: final_fast), the gear down")
local CS = g.circuit_start
pose(Y, before(CS, 247, 3000, CS[3], 500))         -- (YORKE holding, the circuit's start 3 km ahead, heading 247)
pose(H, before(g.touchdown, 67, 2500, 750 + 15000, 300))
run(0.5)
check(evFired("RE_SV_AirfieldClose") and S.closed, "landing closed to the players with her within close_km on the final leg")
check(has(line("escort: track: "), "CHARLENE final") and has(line("escort: track: "), "YORKE orbit"), "everyone's place logged every track_s")
check(H.avoid == false, "her obstacle avoidance off within avoid_off_km of the touchdown")
check(evFired("RE_SV_CharFinalSlow") and not evFired("RE_SV_CharFinalShort"), "her final at 280 within final_slow_km (RE_SV_CharFinalSlow)")
orders = {}
pose(H, before(g.touchdown, 67, 100, 750 + 900, 270))
run(1.5)
local back = 0
for _, o in ipairs(orders) do if o.target == pawn and o.prio == 8 then back = back + 1 end end
check(evFired("RE_SV_CharRoll") and H.inv == true and not ESC.holds(E1) and back >= 1,
      "her rollout at the touchdown point: invincible, her attackers back on you")
-- ((2026-11-07, the user: "The Landing for Yorke, Charlene, Rock, Ali and Danielle takes WAY TOO long") the escorts'
-- landings begin at her rollout (release_at "roll"), the one lined up with the circuit's start first
check(ESC.S.released == 1 and has(line("escort: YORKE released"), "the circuit's start 3.0 km ahead") and evFired("RE_SV_EscYorkeFinal")
      and has(line("escort: the escorts' landings begin"), "CHARLENE roll"),
      "the escorts' landings begin at her rollout: YORKE, lined up with the circuit's start, onto it at once")
check(evFired("RE_SV_CharFinalShort"), "her final at 260 within final_short_km (RE_SV_CharFinalShort)")
pose(H, before(g.roll_end, 67, 100, 750, 60))
run(0.5)
check(evFired("RE_SV_CharTaxi") and S.ac[1].st == "landed" and S.ac[1].how == "taxi" and S.ac[1].slotN == 1 and callout(C.text.landed)
      and has(line("escort: CHARLENE landed"), "on the ground, taxiing to its slot") and not evFired("RE_SV_CharStop"),
      "her taxi near the rollout's end: landed as she taxis to the first slot (A), called out; her stop the build's path end's")
check(saidFrom(C.text.say.touchdown, fromLand) == 1 and saidFrom(C.text.say.her_landed, fromLand) >= 2,
      "her touchdown line, then her landing exchange")
check(RUN.escort.arrived == 9, "she's at Comona: RUN.escort.arrived (the Anomalies may come now)")
local herLanded = S.t
do                                                  -- (on the ground: no more waves, even with one due)
    local n0 = #wavesOf()
    ESC.S.reinf.at = 0
    run(0.25)
    check(#wavesOf() == n0, "no wave once she's touched down")
end
local slot = function(i) return ESC.rwPoint(g.slots[i][1], g.slots[i][2]) end
pose(H, slot(1).X, slot(1).Y, 750, 160, 10)
run(0.5)
check(not H.hidden, "taxiing to her slot: left as she is")
pose(H, slot(1).X, slot(1).Y, 750 + 92500, 208, 599)        -- (2026-11-07: she climbed away from her taxi, 925 m up)
run(0.5)
check(H.hidden == true and has(line("escort: CHARLENE flying again after it landed"), "planes switched off"),
      "landed and flying again (925 m up, 599 km/h): switched off, logged")
run(C.landing.reopen_s)                             -- (reopen_s since her rollout ended)
check(evFired("RE_SV_AirfieldOpen") and not S.closed and has(line("landing open again"), "nobody on short final or the runway"),
      "the players' landing open again reopen_s after nobody's on short final or the runway (YORKE on its downwind)")
check(k.busy(D.special) == true, "the round held while the escorts are up")

---------------------------------------------------------------------------------------------------- the escorts
print("the escorts")
-- (2026-11-07, War's game: YORKE crossed the runway's centre line 2.9 km up on its way to the circuit, its 260 fired
-- there and it flew the whole circuit at 260)
pose(Y, before(g.touchdown, 67, 700, 750 + 290000, 1300))
run(0.5)
check(not evFired("RE_SV_EscYorkeFinalShort") and not evFired("RE_SV_EscYorkeFinalSlow"),
      "YORKE over the runway 2.9 km up on its way to the circuit: no slow-down (escort_short_up_m / escort_slow_up_m)")
pose(Y, before(g.iaf, 67, 10000, 90000, 500))
run(0.5)
check(evFired("RE_SV_EscYorkeFinal") and Y.gear == true, "YORKE on its final, gear down")
pose(Y, before(g.touchdown, 67, 50, 750 + 500, 250))
run(0.5)
pose(Y, before(g.roll_end, 67, 50, 750, 50))
run(0.5)
check(evFired("RE_SV_EscYorkeRoll") and evFired("RE_SV_EscYorkeTaxi") and not evFired("RE_SV_EscYorkeStop") and S.ac[2].st == "landed"
      and S.ac[2].how == "taxi" and S.ac[2].slotN == 2 and evFired("RE_SV_EscYorkeFinalShort"),
      "YORKE: its final slower once it's low near the runway, rollout, landed as it taxis to the second slot (B)")
check(saidFrom(C.text.say.crew.YORKE.landed, fromLand) == 1, "YORKE's own landing line")
local fromRock = #logs + 1
P.SV_Unit_EscRock.HealthInternal = 0
alive.SV_Unit_EscRock = 0
run(0.5)
check(S.ac[3].st == "lost" and callout("ROCK IS DOWN"), "ROCK shot down: out, called out")
check(saidFrom(C.text.say.crew.ROCK.down, fromRock) == 1 and saidFrom(C.text.say.crew.ROCK.mourn, fromRock) == 1
      and saidFrom(C.text.say.escort_down, fromRock, { name = "Rock" }) == 0,
      "ROCK's own last words, then his lead YORKE's answer (crew.ROCK.mourn, in place of escort_down)")
check(RUN.escort.down and RUN.escort.down.ROCK == true, "... ROCK marked down for the run (THE FESTIVAL's KMG lines leave him out)")
local relAt = #logs
local A = P.SV_Unit_EscAli
pose(A, before(CS, 250, 2500, CS[3], 500))
local Dn = P.SV_Unit_EscDanielle
pose(Dn, before(CS, 247, -20000, CS[3], 500))       -- (20 km past the circuit's start, heading away from it)
local tYorke, spin = S.lastRelease, 0
while S.released < 2 and spin < 120 do run(0.25); spin = spin + 1 end
check(S.released == 2 and has(line("escort: ALI released", relAt), "2 of 4") and has(line("escort: ALI released", relAt), "lined up")
      and near(S.lastRelease - tYorke, C.landing.release_gap_s, 0.6),
      string.format("the next one release_gap_s after the last (%.1f s): ALI, lined up with the circuit's start (ROCK out, DANIELLE not lined up)",
          S.lastRelease - tYorke))
check(evFired("RE_SV_EscAliFinal"), "ALI's circuit with its start ahead")
local tAli = S.lastRelease
while S.released < 3 and spin < 240 do run(0.25); spin = spin + 1 end
check(S.released == 3 and S.ac[5].st == "final" and has(line("escort: DANIELLE released"), "started anyway")
      and evFired("RE_SV_EscDanielleFinal") and near(S.lastRelease - tAli, C.landing.release_gap_s, 0.6),
      "DANIELLE, never lined up: its circuit started anyway release_gap_s after ALI (hold_max_s 0)")
pose(Dn, before(CS, 247, -3000, CS[3], 450)); run(0.5)
check(not evFired("RE_SV_EscDanielleFinalSlow"), "no slow-down on its downwind (2 km off the runway, not on the final leg)")
pose(Dn, before(g.touchdown, 67, 50, 750 + 500, 250)); run(0.5)
pose(Dn, before(g.roll_end, 67, 50, 750, 50)); run(0.5)
check(S.ac[5].st == "landed" and S.ac[5].how == "taxi" and S.ac[5].slotN == 3, "DANIELLE landed as it taxis to the third slot (C)")
check(saidFrom(C.text.say.crew.DANIELLE.landed, fromLand) == 1, "DANIELLE's own landing line")
do                                                  -- (nobody quotes ROCK once he's down)
    local rock = 0
    for _, s in ipairs(subsSince(fromRock)) do if s.who == "ROCK" then rock = rock + 1 end end
    check(rock == 1, "ROCK, shot down, says nothing past his last words (" .. rock .. " of his lines)")
end
pose(A, before(g.iaf, 247, 5000, 90000, 500))      -- (ALI never comes down: circling the fix)
local credits0 = RUN.credits
check(S.state ~= "done" and k.busy(D.special) == true, "the round held while ALI's still up")
while S.state ~= "done" and spin < 2000 do run(0.5); spin = spin + 1 end
check(S.state == "done" and near(S.t - herLanded, C.landing.after_her_s, 0.6) and S.ac[4].st == "landed" and S.ac[4].how == "timeout"
      and A.hidden == true and has(line("escort: ALI landed"), "taken off")
      and has(line("escort: round 9, the escort WON"), "4 of 5 landed"),
      string.format("after_her_s (%d s) after she landed: ALI, never down, counted landed and switched off; the escort won",
          C.landing.after_her_s))

---------------------------------------------------------------------------------------------------- the win
print("the win")
local pay = C.reward + C.reward_per_round * 9
check(S.state == "done" and S.won and D.special.state == "done" and k.busy(D.special) == false, "everyone left down: won, the round may end")
check(RUN.credits - credits0 == pay and lbs[#lbs].k == "escort" and lbs[#lbs].won == true,
      string.format("+%d zollars, the leaderboard's special won", pay))
check(ESC.unlocked() and RUN.zfa.round == 9, "the ZFA-44 carriers unlocked for the run")
do
    -- ((2026-11-07) the user: "the Lines about unlocking the ZFA-44 and Charlene Thanking the players also should be
    -- subtitles too") her thanks on the strip, the user's exact text whole, cut after its commas; no callout of it
    local cParts, sParts, at = {}, {}, nil
    for _, c in ipairs(callouts) do
        local t, sub = c:match("^(.-) / (.*)$")
        if t == C.name then cParts[#cParts + 1] = sub end
    end
    for i, s in ipairs(subsSince(1)) do
        if s.who == "CHARLENE" and C.subtitle:find(s.text, 1, true) and #s.text >= 30 then sParts[#sParts + 1] = s.text; at = at or i end
    end
    check(table.concat(sParts, " ") == C.subtitle and #sParts >= 2 and #cParts == 0,
          string.format("her thanks whole on the subtitle strip, the user's exact text, in %d lines (%s); no callout of it",
              #sParts, table.concat(sParts, " / ")))
    local okLen = true
    for _, p in ipairs(sParts) do if #p > C.thanks_chars then okLen = false end end
    check(okLen and sParts[1] and sParts[1]:sub(-1) == ",", "each line at most thanks_chars, cut after a comma")
    check(saidFrom(C.text.say.won, 1) >= 2, "then Comona's line on the ZFA-44s (VAMPIRES in the STORE), and an escort's")
end
check(callout(C.text.won) and evFired("RE_SV_AirfieldOpen") and not S.closed, "ESCORT COMPLETE called out, landing open again")
check(has(k.row(D.special, CFG.hud.text), "LANDED 4/5"), "its NEXT row: " .. tostring(k.row(D.special, CFG.hud.text)))
check(S.ac[5].slotN == 3 and ESC.runwayBusy() == false and ALLY.escortHold("MOONCHILD") == false and has(line("allies: the runway's clear of THE ESCORT"), "go on"),
      "DANIELLE in the third slot (C); the runway clear again, the take-offs go on")
local nrec = #recycled
k.over(now, D.special)
check(ESC.S == nil and H.hidden == true and Y.hidden == true, "the round's end: each one switched off")
run(10)
local rc = 0
for i = nrec + 1, #recycled do if recycled[i]:find("SV_Unit_", 1, true) then rc = rc + 1 end end
check(rc == 5, string.format("... and its unit taken off the spawner's list (%d of 5)", rc))

---------------------------------------------------------------------------------------------------- her loss
print("her loss")
RUN.escort, RUN.zfa = nil, nil
for _, u in ipairs({ "SV_Unit_Charlene", "SV_Unit_EscYorke", "SV_Unit_EscRock", "SV_Unit_EscAli", "SV_Unit_EscDanielle" }) do alive[u] = nil end
spawns = {}
D.special = { kind = "escort", state = "pending" }
D.up = { [E1] = true }
planes = { { obj = e1, unit = E1, name = "e1", addr = e1.addr } }
local cr0 = RUN.credits
check(k.spawn(now) == true, "a second escort spawned (a new run's)")
local P2 = {}
for _, s in ipairs(spawns) do P2[s.u] = plane(s.u, s.x, s.y, s.z, 55, 600); logPlane(P2[s.u], s.u, nil) end
run(6)
check(ESC.holds(E1), "an enemy after her")
P2.SV_Unit_Charlene.HealthInternal = 0
alive.SV_Unit_Charlene = 0
local fromLost = #logs + 1
run(0.5)
local S2 = ESC.S
check(S2.state == "done" and S2.lost and not ESC.unlocked() and RUN.credits == cr0 and lbs[#lbs].won == false
      and callout(C.text.lost) and not ESC.holds(E1) and k.busy(D.special) == false,
      "her death: the special failed (no pay, no unlock), the attackers let go, the round may end")
check(saidFrom(C.text.say.lost, fromLost) >= 2 and RUN.escort.lost == 9 and not RUN.escort.arrived,
      "her loss on the strip (her last words, then Comona or YORKE); RUN.escort.lost")
k.over(now, D.special)

---------------------------------------------------------------------------------------------------- the Anomalies wait
-- ((2026-11-07) the user: "Anomaly Rounds shouldn't start until Charlene arrives at the airbase btw, That Includes,
-- Valka, Mindripper, Abelcain"; "the round before an Anomaly Round appears, a Subtitle from Charlene ... (she will not be
-- able to warn players about VALKA though)")
print("the Anomalies wait for her")
do
    local G = CFG.specials.anomaly_gate
    RUN.escort = nil
    check(ESC.anomalyOk("anomaly") == false and ESC.anomalyOk("glitch") == false and ESC.anomalyOk("valka") == false
          and has(line("specials: the anomaly waits for CHARLENE to land at Comona"), "hasn't come yet"),
          "before THE ESCORT: MINDRIPPER, AB.L..IN and VALKA wait (logged)")
    check(ESC.anomalyOk("shuttle") == true and ESC.anomalyOk("ladon") == true and ESC.anomalyOk("escort") == true,
          "the other specials don't")
    RUN.escort = { flown = 9 }
    check(ESC.anomalyOk("anomaly") == false, "THE ESCORT on, she's not down yet: still waiting")
    RUN.escort.arrived = 9
    check(ESC.anomalyOk("anomaly") == true and ESC.anomalyOk("valka") == true, "she's landed at Comona: they may come")
    RUN.escort = { flown = 9, lost = 9 }
    check(ESC.anomalyOk("glitch") == true, "she was shot down (after_lost): they come anyway")
    G.after_lost = false
    check(ESC.anomalyOk("glitch") == false, "after_lost false: not in that run")
    G.after_lost = true
    RUN.escort = nil
    CFG.specials.escort.enabled = false
    check(ESC.anomalyOk("anomaly") == true, "THE ESCORT switched off: no wait")
    CFG.specials.escort.enabled = true
    ESC.rowsOk = false
    check(ESC.anomalyOk("anomaly") == true, "its rows not in (no ESCORT round this session): no wait")
    ESC.rowsOk = true
    local rot = CFG.specials.rotation
    CFG.specials.rotation = { "shuttle", "anomaly" }
    check(ESC.anomalyOk("anomaly") == true, "THE ESCORT out of the rotation: no wait")
    CFG.specials.rotation = rot
    G.enabled = false
    check(ESC.anomalyOk("anomaly") == true, "the gate off: no wait")
    G.enabled = true
    CFG.specials.shuttle.wait_for_charlene = true
    check(ESC.anomalyOk("shuttle") == false, "a special whose own settings say wait_for_charlene waits too")
    CFG.specials.shuttle.wait_for_charlene = nil
    -- specialReady (sv_spawn.lua) asks it: the dice never draw a waiting Anomaly
    local src = readAll(MOD .. "/Scripts/sv_spawn.lua")
    check(src:find("ESC.anomalyOk(k) == false", 1, true) ~= nil, "sv_spawn.lua's specialReady asks ESC.anomalyOk")
    -- her warning at the round's end, for the next round's Anomaly
    local rawFor = specialFor
    local nextKind = "anomaly"
    specialFor = function() return nextKind end
    RUN.escort = { flown = 9, arrived = 9 }
    SUB.clear("test")
    local from = #logs + 1
    check(ESUB.warnNext(12, now) == true and saidFrom(C.text.say.warn_anomaly, from) >= 2
          and has(line("escort subs: round 12 will be the anomaly"), "said"),
          "round 12 will be MINDRIPPER's: her warning at round 11's end")
    nextKind = "glitch"
    from = #logs + 1
    check(ESUB.warnNext(12, now) == true and saidFrom(C.text.say.warn_glitch, from) >= 2, "... AB.L..IN's: hers")
    nextKind = "valka"
    from = #logs + 1
    check(ESUB.warnNext(12, now) == false and #subsSince(from) == 0, "... VALKA's: none (she can't see VALKA coming)")
    nextKind = "shuttle"
    check(ESUB.warnNext(12, now) == false, "... a shuttle round: none")
    nextKind = "anomaly"
    RUN.escort = { flown = 9, lost = 9 }
    check(ESUB.warnNext(12, now) == false, "she was shot down: no warning")
    RUN.escort = { flown = 9, arrived = 9 }
    D.forceSpecial = "anomaly"
    check(ESUB.warnNext(12, now) == false, "a test key's forced round: not drawn, not warned")
    D.forceSpecial = nil
    specialFor = rawFor
    -- (the round's end calls it: sv_rounds.lua, after "round n clear")
    local rs = readAll(MOD .. "/Scripts/sv_rounds.lua")
    check(rs:find("pcall(ESUB.warnNext, D.round + 1, now)", 1, true) ~= nil, "sv_rounds.lua's round end asks ESUB.warnNext")
    RUN.escort = nil
end
do                                                  -- (every line theirs: at most 70 characters, two lines on the strip)
    local longest, most, n, bad = 0, 0, 0, {}
    local WRAP, EMU = CFG.hud.subs.w - 80, CFG.hud.subs.em_units
    local function each(l)
        for _, x in ipairs(flatL(l)) do
            local who, text = ESUB.line(x, { dir = "south-west", name = "Danielle" })
            n = n + 1
            longest = math.max(longest, #text)
            if #text > 70 then bad[#bad + 1] = text end
            if SUB.lineCount then most = math.max(most, SUB.lineCount(text, WRAP, EMU)) end
            if not (CFG.hud.subs.colors[who]) then bad[#bad + 1] = "no colour for " .. who end
        end
    end
    for k2, v in pairs(C.text.say) do
        if type(v) == "table" and k2 ~= "staff" and k2 ~= "hurt_at" and k2 ~= "crew" then each(v) end
    end
    for _, c in pairs(C.text.say.crew) do each(c.down); each(c.landed); each(c.mourn) end
    for k2, v in pairs(CFG.specials.valka.text.say) do if k2 ~= "hurt_at" then each(v) end end   -- (VALKA's round's too)
    check(#bad == 0 and most <= 2 and n > 80,
          string.format("%d lines of theirs: the longest %d characters, at most %d strip lines, each speaker its colour (%s)",
              n, longest, most, table.concat(bad, "; ")))
end

---------------------------------------------------------------------------------------------------- the STORE
print("the STORE")
RUN.credits, RUN.msg, RUN.bought, RUN.offerShown = 60000, {}, {}, nil
press("Revive")
check(RUN.msg.Revive == "CO-OP ONLY." and ESC.rowItem("Revive") == nil, "locked: the revive row is the revive row")
check(ESC.offer(false).why == K.text.locked, "locked: the carrier's own item says how to unlock it")
RUN.zfa = { unlocked = true }
check(ESC.rowItem("Revive") == "ZfaCarrier" and ESC.rowItem("Moonchild") == nil, "unlocked: the revive row sells the carrier while nobody's down")
press("Revive")
check(spawns[#spawns].u == "SV_Unit_Cargo1" and RUN.credits == 45000 and RUN.bought.ZfaCarrier == 1 and has(RUN.msg.Revive, "ON STATION"),
      "bought on the revive row: ship 1 on station, 15000 Z, counted under the carrier")
press("ZfaCarrier")
check(spawns[#spawns].u == "SV_Unit_Cargo2" and RUN.credits == 30000 and ESC.carriersUp() == 2, "the second ship from its own item")
press("ZfaCarrier")
check(RUN.credits == 30000 and has(RUN.msg.ZfaCarrier, "BOTH CARRIERS ARE OUT"), "a third refused: two at most")
check(ESC.hulls.SV_Unit_Cargo1 == nil, "the hull found in the tick, not in the callback")
run(0.5)
check(ESC.hulls.SV_Unit_Cargo1 ~= nil and has(line("carrier: SV_Unit_Cargo1's hull"), "ctslf"), "ship 1's hull found as it spawned")

---------------------------------------------------------------------------------------------------- launches
print("launches")
K.launch_wait_s = 10                                -- (this section's timings: the 0.74.11 wait)
local dressed = {}
ZFA.dress = function(o, opts) dressed[#dressed + 1] = { o = o, paint = opts.paint }; return true, "dressed" end
local A1 = K.launchers[1][1].unit
-- ((2026-11-07, the user: "ZFA-44's did not launch from the Cargo Ships": every try read each arm's unit alive, "every
-- launcher arm's flight is still up", 322 times) ship 1's first arm with 2 planes of its own up from the ship's spawn
local rawRecycle = SV_Recycle
SV_Recycle = function(u, f) if u == A1 and f == 1 then alive[u] = nil end return rawRecycle(u, f) end
alive[A1] = 2
local nrL = #recycled
run(K.first_s + 0.5)
SV_Recycle = rawRecycle
check(evFired("RE_SV_CargoLaunch_1_1") and evFired("RE_SV_CargoLaunch_2_1"), "each ship's first container launch first_s on")
do
    -- ((2026-11-07, the user's test of 0.74.9: AC8 crashed the moment such an arm's unit was taken off by force with its
    -- 2 planes up and the arm fired) never taken off with planes up: fired as it is
    local recL = false
    for i = nrL + 1, #recycled do if recycled[i] == A1 .. ":1" then recL = true end end
    check(not recL and has(line("carrier: ZFA-44 CARRIER 1: " .. A1 .. " has 2 up that this carrier never launched"), "fired as it is, never taken off with planes up")
          and not line("every launcher arm's flight is still up"),
          "an arm whose unit has planes up the carrier never launched (the ship's own): fired as it is, NOT taken off the list (it crashed AC8)")
end
check(A1 == "E_Unit_01_drone_5_0" and K.launchers[2][1].unit == "E_Unit_01_drone_3_1" and #K.launchers[1] == 6 and #K.launchers[2] == 6
      and K.launchers[1][6].record == "RE_SV_CargoLaunch_1_6" and K.launchers[2][6].unit == "E_Unit_01_drone_7_1",
      "the build's launcher arms: ship 1's E_Unit_01_drone_5_0 .. 8_0, ship 2's 3_1 .. 7_1, six each")
local z1 = plane(nil, 1610476 + 20000, 249000, 5000, 90, 300)
z1.full = "BP_OP_drone_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.Z1"
logPlane(z1, nil, nil)
run(0.5)
check(#dressed == 0, "not dressed in its first second (settle_s)")
run(1.5)
local inA = false
for _, p in ipairs(ALLY.state().planes) do if p.obj == z1 and p.unit == A1 then inA = true end end
check(inA and ESC.planes[A1] and #ESC.planes[A1] == 1, "a plane with no unit near ship 1: its flight's (" .. A1 .. "), an ally")
check(#dressed == 1 and dressed[1].o == z1 and dressed[1].paint == 3, "dressed as the ZFA-44, paint 3")
run(10)
check(has(line("carrier: ZFA-44 CARRIER 1's ZFA-44s are up"), "1 planes seen"), "ship 1's flight up")
check(spawns[#spawns].u == "SV_Unit_ZfaB" and has(line("carrier: ZFA-44 CARRIER 2: RE_SV_CargoLaunch_2_1 fired"), "launched by pose"),
      "ship 2: no plane in launch_wait_s: by pose from now on")
check(evFired("RE_SV_ZfaGoB") and has(line("carrier: ZFA-44 CARRIER 2 launches its ZFA-44s by pose"), "RE_SV_ZfaGoB fired"),
      "the pose flight's orders after its spawn (RE_SV_ZfaGoB)")
do
    local s2 = spawns[#spawns]
    local yaw = (math.deg(math.atan(K.ship_at[2][1] - 1610476, 0)) )
    check(near(s2.z, K.pose.alt_m * 100, 1) and math.abs(s2.x - K.ship_at[2][1]) < 40000, string.format("... off its bow, %g m up", s2.z / 100))
end
z1.HealthInternal = 0
alive[A1] = 0
local nr0 = #recycled
run(6)
check(has(line("carrier: ZFA-44 CARRIER 1's ZFA-44 flight " .. A1 .. " is down"), "another in"), "ship 1's flight down: another after relaunch_s")
run(K.relaunch_s)
local rec1 = false
for i = nr0 + 1, #recycled do if recycled[i] == A1 .. ":1" then rec1 = true end end
check(rec1 and evFired("RE_SV_CargoLaunch_1_2"), "the downed flight's unit off the spawner's list (its arm ready again), the next arm's launch")
local A2 = K.launchers[1][2].unit
local z2 = plane(nil, 1610476 - 30000, 249000 + 10000, 8000, 90, 300)
logPlane(z2, nil, nil)
check(ESC.planes[A2] and #ESC.planes[A2] == 1, "its plane taken as that arm's flight (" .. A2 .. ")")
run(3)
z2.HealthInternal = 0
alive[A2] = 0
-- (arm 3's unit with planes up this carrier never launched: fired as it is, never skipped, never taken off; the planes
-- up before it fired aren't its launch, so with no new one in launch_wait_s it's launched by pose)
local A3, A4 = K.launchers[1][3].unit, K.launchers[1][4].unit
alive[A3], alive[A4] = 2, 0
local nr = #recycled
local fromA3 = #logs + 1
run(20 + K.relaunch_s)
local recA3 = false
for i = nr + 1, #recycled do if recycled[i] == A3 .. ":1" then recA3 = true end end
check(evFired("RE_SV_CargoLaunch_1_3") and not recA3
      and has(line("carrier: ZFA-44 CARRIER 1: " .. A3 .. " has 2 up that this carrier never launched"), "fired as it is"),
      "the next arm in turn, its unit with 2 up this carrier never launched: fired as it is (never skipped, never taken off)")
-- ((2026-11-07) the container drone: its 2 parked planes alive and none seen out in launch_wait_s: their climb-out
-- fired anyway, never the pose flight)
check(has(line("carrier: ZFA-44 CARRIER 1: none of " .. A3 .. " seen out of its container", fromA3), "RE_SV_ZfaClimb_1_3 fired")
      and evFired("RE_SV_ZfaClimb_1_3") and line("carrier: ZFA-44 CARRIER 1: RE_SV_CargoLaunch_1_3 fired", fromA3) == nil,
      "... its 2 planes alive but none seen out of the container in launch_wait_s: their climb-out anyway, not by pose")
alive[A3], alive[A4] = nil, nil

---------------------------------------------------------------------------------------------------- service
print("service")
local R = ESC.R
local c1 = R.carriers[1]
for r = 10, 12 do
    D.round, D.state = r, "fighting"
    run(65)
    D.state = "wait"
    run(1)
end
check(c1.served == 3 and c1.state == "leaving" and callout("ZFA-44 CARRIER 1 LEAVING"),
      "3 rounds served: leaving in the break, called out")
run(3)
local gone = false
for _, x in ipairs(recycled) do if x == "SV_Unit_Cargo1:1" then gone = true end end
check(R.carriers[1] == nil and gone and ESC.carriersUp() == 0, "... off the spawner's list (SV_Recycle), the STORE can call another")
alive.SV_Unit_Cargo1 = 0
D.state = "fighting"
press("ZfaCarrier")
check(R.carriers[1] ~= nil, "another bought")
alive.SV_Unit_Cargo1 = 0
run(8)
check(R.carriers[1] == nil and callout("ZFA-44 CARRIER 1 SUNK"), "a ship sunk: called out, gone")
check(ESC.hulls.SV_Unit_Cargo1 == nil, "... its hull forgotten with its slot (the next ship's recorded afresh)")
-- ((code review of 2026-11-07, finding 7) its hull sunk while its launchers and Stinger mount still count alive
callouts = {}
alive.SV_Unit_Cargo1 = 0
press("ZfaCarrier")
run(0.5)
local c7, h7 = R.carriers[1], ESC.hulls.SV_Unit_Cargo1
check(c7 and h7 and h7.obj, "another bought, its hull found")
local part7 = { full = "BP_VE021_stgr_Base_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.Stinger_" .. addr(), addr = addr(),
                HealthInternal = 800 }
function part7:ModifyHealth(d) self.HealthInternal = math.max(0, self.HealthInternal + d * 10) end
ESC.shipObjs.SV_Unit_Cargo1[#ESC.shipObjs.SV_Unit_Cargo1 + 1] = { obj = part7, addr = part7.addr, name = part7.full }
alive.SV_Unit_Cargo1 = 3                             -- (its launchers and the Stinger: the unit still counts them)
run(2.5)
check(c7.state == "up", "(its hull up: up, whatever else)")
h7.obj.HealthInternal = 0
local nr7 = #recycled
run(2.5)
check(c7.state == "leaving" and ESC.carriersUp() == 0 and callout("ZFA-44 CARRIER 1 SUNK") and part7.HealthInternal <= 0
      and has(line("carrier: ZFA-44 CARRIER 1 sunk"), "its hull at 0 health") and R.carriers[1] == c7,
      "its hull at 0 health: sunk though its unit counts 3 alive, called out, its parts finished off, its slot held ("
      .. tostring(line("carrier: ZFA-44 CARRIER 1 sunk")) .. ")")
run(3.5)
local gone7 = false
for i = nr7 + 1, #recycled do if recycled[i] == "SV_Unit_Cargo1:1" then gone7 = true end end
check(R.carriers[1] == nil and gone7 and ESC.hulls.SV_Unit_Cargo1 == nil, "... then off the spawner's list, its slot free, its hull forgotten")
alive.SV_Unit_Cargo1 = 0

---------------------------------------------------------------------------------------------------- co-op
print("co-op")
local client = false
COOP = { open = true, host = function() return not client end, client = function() return client end,
         msg = function(to, ...) msgs[#msgs + 1] = { ... }; return true end, removeNow = function() return 0 end,
         askBuild = function(name, price, kind) asks[#asks + 1] = { name = name, price = price }; return true, "ASKED THE HOST" end,
         specialShare = function() return 1 end }
msgs = {}
ESC.esKey = nil
run(1.5)
local es = msgs[#msgs]
check(es and es[1] == "es" and es[7] == "1" and es[8] == "0", "the host's \"es\": unlocked, no carrier out (" .. table.concat(es or {}, "|") .. ")")
check(es and es[10] == "0", "the host's \"es\": field 10 the ships up as bits, none (" .. tostring(es and es[10]) .. ")")
do                                                  -- ((code review of 2026-11-07, finding 1) one ship up: bit 1
    local Rh = ESC.R
    Rh.carriers[2] = { idx = 2, unit = "SV_Unit_Cargo2", state = "up", at = now, served = 0, armI = 0, used = {}, nextLaunchAt = now + 999, name = "ZFA-44 CARRIER 2" }
    ESC.esKey = nil
    run(1.5)
    local es2 = msgs[#msgs]
    check(es2 and es2[10] == "2" and es2[8] == "1", "the host's \"es\" with ship 2 up: field 10 = 2 (" .. table.concat(es2 or {}, "|") .. ")")
    Rh.carriers[2] = nil
end
client = true
RUN.zfa = nil
events = {}
ESC.onHost({ "es", "route", "1", "5", "80", "23.4", "1", "2", "1" })
check(ESC.unlocked() and RUN.zfa.room and ESC.carriersUp() == 2, "a joiner: the room's unlock and carriers out from the host")
check(ESC.clientRow(CFG.hud.text) == "CHARLENE 80%  23.4 KM  LANDED 1/5", "a joiner's NEXT row: " .. tostring(ESC.clientRow(CFG.hud.text)))
check(evFired("RE_SV_AirfieldClose") and ESC.clientClosed, "a joiner's landing closed with the host's")
ESC.onHost({ "es", "landing", "2", "5", "80", "1.0", "1", "1", "0" })
check(evFired("RE_SV_AirfieldOpen") and not ESC.clientClosed, "... and open again")
ESC.onHost({ "es", "route", "1.5", "5", "80.7", "x", "1", "1.2", "0" })
check(ESC.clientRow(CFG.hud.text) == "CHARLENE 80%  0.0 KM  LANDED 1/5" and ESC.carriersUp() == 1, "a joiner: odd numbers from the host made whole, a bad one dropped")
-- ((code review of 2026-11-07, finding 1) a joiner's own ZFA-44s: the host's forwarded launches fire its copy of the ship's
-- launchers here, planes of no co-op id
do
    ESC.onHost({ "es", "", "0", "0", "-1", "0", "1", "2", "0", "3" })      -- (both ships up on the host's game)
    local sp1 = K.ship_at[1]
    local zA = plane(nil, sp1[1] + 20000, sp1[2], 5000, 90, 300)
    logPlane(zA, nil, nil)
    local armU = K.launchers[1][1].unit
    local inList = false
    for _, e in ipairs(ESC.planes[armU] or {}) do if e.obj == zA then inList = true end end
    check(inList and ESC.localZfa()[zA.addr] == true,
          "a joiner: a plane near its copy of ship 1 taken as that ship's ZFA-44s (ESC.localZfa: " .. armU .. ")")
    -- the host's next launch of ship 1 (arm 2): the arm's unit off this game's list first, the last flight here off
    local arm2 = K.launchers[1][2]
    alive[arm2.unit] = 2
    local nr = #recycled
    local got = ESC.beforeHostEvent(arm2.record)
    local rec = false
    for i = nr + 1, #recycled do if recycled[i] == arm2.unit .. ":1" then rec = true end end
    -- ((2026-11-07) never with planes up: the host's crash came the moment such a unit was taken off and its arm fired)
    check(got == arm2.unit and not rec and zA.active == false and zA.hidden == true
          and has(line("carrier: the host's " .. arm2.record .. " here: " .. arm2.unit .. " first"), "2 up: left as they are, never taken off with planes up"),
          "a joiner: before the host's " .. arm2.record .. " fires here: " .. arm2.unit .. " with 2 up left as it is (NOT taken off), ship 1's last flight here switched off")
    alive[arm2.unit] = 0
    nr = #recycled
    ESC.beforeHostEvent(arm2.record)
    rec = false
    for i = nr + 1, #recycled do if recycled[i] == arm2.unit .. ":1" then rec = true end end
    check(rec and has(line("carrier: the host's " .. arm2.record .. " here: " .. arm2.unit .. " first"), "nothing up, SV_Recycle"),
          "... with nothing of it up: off this game's list first (force 1)")
    check(ESC.beforeHostEvent("RE_SV_ValkaShot") == nil and ESC.beforeHostEvent("RE_SV_CargoLaunch_1_9") == nil, "... any other event: nothing")
    alive[arm2.unit] = nil
    -- ship 1 gone on the host (left or sunk): this game's own ZFA-44s of it off
    local zB = plane(nil, sp1[1] - 10000, sp1[2] + 10000, 5000, 90, 300)
    logPlane(zB, nil, nil)
    alive[armU] = 2
    local q0 = #ESC.recycleQ
    ESC.onHost({ "es", "", "0", "0", "-1", "0", "1", "1", "0", "2" })
    check(zB.active == false and zB.hidden == true and #ESC.recycleQ == q0
          and has(line("carrier: the host's ZFA-44 CARRIER 1 is gone"), "of this game's own ZFA-44s of it switched off, 0 of its arms' units"),
          "a joiner: ship 1 no longer up on the host's game (field 10): its own ZFA-44s of it off; an arm's unit with planes up NOT queued off the list")
    alive[armU] = nil
    ESC.recycleQ = {}
    ESC.onHost({ "es", "route", "1", "5", "80", "23.4", "1", "1", "0" })   -- (an older host: no field 10, nothing more taken off)
end
-- ((0.74.25) Saint Alessia's host log of 0.74.23: the run's second carrier fired arm 1 again, whose last ZFA-44s were still
-- up, and nothing came out; the first had left its parked ZFA-44s only switched off)
print("(0.74.25) the next carrier's arm: one whose last ZFA-44s aren't up; a leaving ship's parked ZFA-44s finished off")
;(function()
    local K = CFG.allies.carrier
    local arms = K.launchers[1]
    ZLAUNCH.out = nil
    for _, a in ipairs(arms) do alive[a.unit] = 2 end             -- (a fresh ship: each arm's two parked)
    local C = { name = "TEST CARRIER", armI = 0 }
    local j1 = ZLAUNCH.pickArm(C, arms)
    check(j1 == 1, "a fresh ship: arm 1 (" .. tostring(j1) .. ")")
    local from0 = #logs + 1
    local j2 = ZLAUNCH.pickArm({ name = "TEST CARRIER 2", armI = 0 }, arms)   -- (the run's next: arm 1's two still up)
    check(j2 == 2 and has(line("carrier: TEST CARRIER 2: arm 2 of", from0), "skipped"),
          "the next carrier: arm 1's last ZFA-44s still up, arm 2 (" .. tostring(j2) .. ")")
    alive[arms[1].unit] = 0
    local j3 = ZLAUNCH.pickArm({ name = "TEST CARRIER 3", armI = 0 }, arms)
    check(j3 == 1, "arm 1's flight down: arm 1 again (" .. tostring(j3) .. ")")
    local GSk = statics["/Script/Engine.Default__GameplayStatics"]
    local dmg = {}
    local gsStub = { full = "GameplayStatics", addr = addr(), ApplyDamage = function(_, o) dmg[#dmg + 1] = o end }
    statics["/Script/Engine.Default__GameplayStatics"] = gsStub
    local sp = K.ship_at[1]
    local parked = plane(arms[1].unit, sp[1], sp[2], -24483.9, 0, 0)
    local flying = plane(arms[1].unit, sp[1], sp[2], 50000, 0, 600)
    local keepPl = ESC.planes[arms[1].unit]
    ESC.planes[arms[1].unit] = { { obj = parked, addr = parked.addr, name = parked.full, at = 0 },
                                 { obj = flying, addr = flying.addr, name = flying.full, at = 0 } }
    local q0 = #ESC.recycleQ
    local n = ZLAUNCH.parkedOff(1, arms[1].unit, "TEST CARRIER leaving")
    check(n == 1 and #dmg == 1 and dmg[1] == parked, "a leaving ship: its parked ZFA-44 finished off under the sea, not the one flying ("
          .. tostring(n) .. ")")
    check(#ESC.recycleQ == q0 + #arms - 1, "... its arms' units queued off the list once none is up, but its flight's ("
          .. (#ESC.recycleQ - q0) .. " of " .. #arms .. ")")
    ESC.planes[arms[1].unit] = keepPl
    for i = #ESC.recycleQ, q0 + 1, -1 do table.remove(ESC.recycleQ, i) end
    for _, a in ipairs(arms) do alive[a.unit] = nil end
    gsStub.gone = true                                         -- (sv_core.lua keeps a /Script/ object while it's live)
    statics["/Script/Engine.Default__GameplayStatics"] = GSk
    ZLAUNCH.out = nil
end)()
RUN.credits, RUN.msg = 40000, {}
RUN.offerShown = nil
press("Revive")
check(asks[#asks] and asks[#asks].name == "ZfaCarrier" and asks[#asks].price == 15000 and RUN.credits == 25000,
      "a joiner's purchase on the revive row: asked of the host for the carrier, paid here")
client = false
RUN.zfa = { unlocked = true }
RUN.bought.ZfaCarrier = RUN.bought.ZfaCarrier or 0
local b0 = RUN.bought.ZfaCarrier
alive.SV_Unit_Cargo1, alive.SV_Unit_Cargo2 = 0, 0
ESC.R.carriers = {}
local okB, msgB = shopBuildFor(2, "ZfaCarrier", 1000, nil, true)
check(okB == false and has(msgB, "THE PRICE IS NOW"), "the host: a joiner's ask under the room's price refused")
local okC = shopBuildFor(2, "ZfaCarrier", 15000, nil, true)
check(okC == true and RUN.bought.ZfaCarrier == b0 + 1 and ESC.R.carriers[1] and ESC.R.carriers[1].buyer == 2,
      "the host builds a joiner's carrier at the room's price, counted for the room")
local list = ESC.carrierList()
check(#list == 1 and list[1] == 2, "the carriers out for host migration's list")
COOP = nil

---------------------------------------------------------------------------------------------------- the landing test T0
print("the landing test T0 (Ctrl+F5)")
alive.SV_Unit_Charlene = nil
spawns, events = {}, {}
D.state, D.at = "wait", now + 1
RUN.zfa = nil
local lb0, cr1 = #lbs, RUN.credits
ESC.testT0()
local T = ESC.S
local s0 = spawns[#spawns]
local t0x, t0y = fwd(67)
check(T and T.test == "t0" and s0 and s0.u == "SV_Unit_Charlene" and near(s0.x, g.iaf[1] - t0x * C.test.before_m * 100, 1)
      and near(s0.y, g.iaf[2] - t0y * C.test.before_m * 100, 1) and s0.z == g.iaf[3] and near(s0.yaw, 67 - 90) and #T.ac == 1
      and events[1] == "RE_SV_EscortReset",
      "RE_SV_EscortReset, then CHARLENE alone before_m short of the approach fix, heading 067 (yaw -23)")
local h0 = plane("SV_Unit_Charlene", s0.x, s0.y, s0.z, 67, 300)
logPlane(h0, "SV_Unit_Charlene", nil)
run(1.5)
check(evFired("RE_SV_CharT0Final") and not evFired("RE_SV_CharFinal") and not evFired("RE_SV_CharGo") and h0.gear == true
      and h0.inv == true and h0.HealthInternal == 1300,
      "her T0 final at once (RE_SV_CharT0Final: SV_Path_CharFinal, not her route), gear down, invincible, her health as it is")
check(has(line("escort: T0 +"), "gear") and D.at >= now + 2.5, "her place, height, speed and gear logged; the break held")
pose(h0, before(g.touchdown, 67, 100, 750 + 600, 250)); run(0.5)
check(evFired("RE_SV_CharT0Roll") and evFired("RE_SV_CharT0FinalShort") and not evFired("RE_SV_CharRoll"),
      "T0's slow-downs and rollout on its own records (RE_SV_CharT0*)")
pose(h0, before(g.roll_end, 67, 100, 750, 50)); run(0.5)
pose(h0, slot(1).X, slot(1).Y, 750, 160, 5); run(0.5)
pose(h0, slot(1).X, slot(1).Y, 750, 160, 0); run(3)
check(T.state == "done" and has(line("escort: T0 over"), "stopped") and has(line("escort: T0: her rollout began"), "past runway 07's west threshold")
      and not ESC.unlocked() and #lbs == lb0 and RUN.credits == cr1, "landed: the test over, where her rollout began logged, no pay, unlock or leaderboard line")
run(C.test.end_s + 1)
check(ESC.S == nil and h0.hidden == true, "taken off end_s after she's down")

---------------------------------------------------------------------------------------------------- the build's backstops
print("the build's backstops (its leg and slot flags)")
local rawFlags = svFlags
local F = {}
svFlags = function() return F end
alive.SV_Unit_Charlene = nil
spawns, events = {}, {}
ESC.testT0()
local T2 = ESC.S
local s1 = spawns[#spawns]
local h2 = plane("SV_Unit_Charlene", s1.x, s1.y, s1.z, 67, 300)
logPlane(h2, "SV_Unit_Charlene", nil)
F.SV_CharLeg, F.SV_TaxiSlotChar = 5, 4                -- (the last operation's, cached before the reset's 2 s: never taken)
flagCache.at = clock
run(1.5)
check(T2.ac[1].st == "final" and not has(line("the build's backstop moved it on"), "SV_CharLeg 5"), "flags read before the reset's 2 s: not taken")
F.SV_CharLeg, F.SV_TaxiSlotChar = 3, 0                -- (her final's PathFinish backstop: her rollout)
flagCache.at = clock + 1
run(0.5)
check(T2.ac[1].st == "roll" and h2.inv == true and has(line("escort: CHARLENE roll (the build's backstop moved it on"), "SV_CharLeg 3"),
      "her leg flag ahead (3: the rollout the final's end began): taken, invincible, logged")
F.SV_CharLeg, F.SV_TaxiSlotChar = 4, 4                -- (the rollout's end: her taxi, to the slot the record picked)
run(0.5)
check(T2.ac[1].st == "taxi" and T2.ac[1].slotN == 4 and has(line("escort: CHARLENE's parking slot D"), "SV_TaxiSlotChar 4"),
      "her taxi from the flag, her parking slot the build's (D), logged")
pose(h2, slot(4).X, slot(4).Y, 750, 160, 5); run(0.5)
pose(h2, slot(4).X, slot(4).Y, 750, 160, 0); run(3)
check(T2.state == "done" and has(line("escort: T0 over"), "stopped"), "stopped on that slot: the test over")
svFlags = rawFlags
run(C.test.end_s + 1)

---------------------------------------------------------------------------------------------------- a restart
-- ((code review of 2026-11-07, finding 3) a pause-menu restart mid-escort with a carrier out (sv_main.lua's level-load
-- block calls ESC.restart before the new run's D): everything of the old run taken off, the players' landing open again
print("a restart (ESC.restart)")
ESC.S, ESC.recycleQ = nil, {}
for k2 in pairs(alive) do alive[k2] = nil end
spawns, events = {}, {}
RUN.escort = nil
D.special = { kind = "escort", state = "pending" }
check(k.spawn(now) == true and ESC.S ~= nil, "(an escort up again)")
local rs = {}
for _, s2 in ipairs(spawns) do
    local p2 = plane(s2.u, s2.x, s2.y, s2.z, 55, 600)
    logPlane(p2, s2.u, nil)
    rs[#rs + 1] = p2
end
ESC.S.closed = true                                    -- (her final: the players' landing closed)
RUN.zfa = { unlocked = true }
RUN.credits, RUN.msg = 50000, {}
D.state = "wait"
press("ZfaCarrier")
local S0, R0 = ESC.S, ESC.R
check(R0 and next(R0.carriers) ~= nil, "(a carrier out)")
events = {}
ESC.restart("test restart")
local allOff = #rs == 5
for _, p2 in ipairs(rs) do if not (p2.active == false and p2.hidden == true) then allOff = false end end
local q = {}
for _, e in ipairs(ESC.recycleQ) do q[e.unit] = true end
check(ESC.S == nil and ESC.R == nil and allOff and evFired("RE_SV_AirfieldOpen") and q.SV_Unit_Charlene and q.SV_Unit_EscYorke
      and q.SV_Unit_Cargo1 and q.SV_Unit_Cargo2 and has(line("escort: test restart:"), "5 of the escort's aircraft and 2 carriers taken off"),
      "a restart: the escort's five switched off, the carrier taken off, their units queued off the list, landing open again ("
      .. tostring(line("escort: test restart:")) .. ")")
D.special = nil

---------------------------------------------------------------------------------------------------- the laser made sure
-- ((0.74.12) the user: "The Laser Interceptor HAS to work, no exceptions") ZLAS.drive: each ZFA-44 fires at the nearest
-- enemy missile within 3 km (never ours, never one out of reach), the beam from it, the missile shot down at the swing's
-- end (no lock, no damage, its life cut, the burst); the game's own laser shots hit every time
print("the ZFA-44s' laser made sure (sv_escort_laser.lua ZLAS.drive)")
do
    local fxs, comps = {}, {}
    local NL = { full = "NiagaraFunctionLibrary", addr = addr() }
    function NL:SpawnSystemAtLocation(pc, sys, at, rot)
        local c = { full = "NiagaraComponent", addr = addr(), vars = {} }
        function c:IsValid() return not self.dead end
        function c:SetVariableFloat(n, v) self.vars[tostring(n)] = v end
        function c:Deactivate() self.off = true end
        fxs[#fxs + 1] = { sys = sys, at = at, rot = rot, comp = c }
        comps[#comps + 1] = c
        return c
    end
    function NL:SpawnSystemAttached(sys, root, socket, at, rot, how)   -- (Survival's beam: attached, aimed again each tick)
        local c = { full = "NiagaraComponent", addr = addr(), vars = {} }
        function c:IsValid() return not self.dead end
        function c:SetVariableFloat(n, v) self.vars[tostring(n)] = v end
        function c:K2_SetWorldRotation(r) self.rot = r end
        function c:Deactivate() self.off = true end
        fxs[#fxs + 1] = { sys = sys, at = at, rot = rot, comp = c, attached = true, root = root, how = how }
        comps[#comps + 1] = c
        return c
    end
    statics["/Script/Niagara.Default__NiagaraFunctionLibrary"] = NL
    local ZC = CFG.allies.carrier.zfa
    for _, p in ipairs({ ZC.laser_beam_fx, ZC.laser_kill_fx, ZC.laser_hit_sound }) do
        local full = p .. "." .. p:match("[^/]+$")
        statics[full] = { full = full, addr = addr() }
    end
    local sounds = {}
    statics["/Script/AkAudio.Default__AkGameplayStatics"] = { full = "AkGameplayStatics", addr = addr(),
        PostEventAtLocation = function(_, ev, at) sounds[#sounds + 1] = { ev = ev.full, at = at } end }
    local function gobj(full, fac) return setmetatable({ full = full, addr = addr(), GetFaction = function() return fac end }, PM) end
    local enemyJet, allyJet = gobj("BP_Su30_C enemy", 2), gobj("BP_F18_C ally", 1)
    local function missile(name, x, y, z, shooter, target)
        local m = setmetatable({ full = "BP_" .. name .. "_C " .. name, addr = addr(), damage = 40, bIsHoming = true, LifeTime = 30,
                                 TargetToHome = target }, PM)
        m.GetOwner = function() return shooter end
        m.IsDestroyed = function(self) return self.gone == true end
        pose(m, x, y, z, 0, 0)
        return m
    end
    local zU = K.launchers[1][1].unit
    local z1 = plane(zU, 1000000, 0, 300000, 0, 600)
    function z1:K2_GetRootComponent() return { full = "root", owner = self } end
    ESC.planes[zU] = { { obj = z1, addr = z1.addr, name = z1.full, at = 0 } }
    local mNear = missile("wp_msl_r0", 1000000 + 200000, 0, 300000, enemyJet, z1)        -- 2 km off: the enemy's
    local far = missile("wp_msl_r1", 1000000 + 450000, 0, 300000, enemyJet, z1)         -- 4.5 km off
    local ours = missile("wp_msl_r2", 1000000 + 100000, 0, 300000, allyJet, enemyJet)   -- 1 km off, an ally's
    HIT = HIT or { msl = {} }                          -- (sv_ladon.lua's missile list: not loaded here)
    local rawMsl = HIT.msl
    HIT.msl = { { obj = mNear, name = "BP_wp_msl_r0", born = 0, from = "BP_Su30" }, { obj = far, name = "BP_wp_msl_r1", born = 0 },
                { obj = ours, name = "BP_wp_msl_r2", born = 0 } }
    D = D or {}
    local armed0 = ZLAS.armed
    ZLAS.armed = false                                  -- (the flag count is tested above)
    local from = #logs + 1
    for _ = 1, 5 do ZLAS.tick(); clock = clock + 0.05 end      -- (the assets loaded, a tick each, before the first shot)
    local fire = line("zfa laser: ", from)
    check(has(fire, " fires at BP_wp_msl_r0@") and has(fire, "2000 m off")
          and has(fire, "from BP_Su30"), "a ZFA-44 fires at the enemy missile 2 km off: " .. tostring(fire))
    local beam = fxs[1]
    check(beam and beam.sys.full:find("NS_NPC_TLS_Muzleflash01", 1, true) and near(beam.comp.vars["User.BeamLength"], 200000, 1)
          and near(beam.rot.Yaw, 0, 0.01) and near(beam.at.X, 1000000) and beam.attached and beam.root.owner == z1 and beam.how == 1,
          "the TLS's own beam attached to the ZFA-44 (kept where it is: no laser record for a plane of no known arm), 2 km at the missile")
    check(mNear.damage == 40 and mNear.bIsHoming == true, "not shot down before the swing's end")
    clock = clock + 0.4
    ZLAS.tick()
    check(mNear.damage == 0 and mNear.bIsHoming == false and mNear.LifeTime == 0.05, "at the swing's end: no lock, no damage, its life cut")
    check(has(line("zfa laser: BP_wp_msl_r0@", from), "shot down (by "), "logged: " .. tostring(line("zfa laser: BP_wp_msl_r0@", from)))
    local burst = fxs[#fxs]
    check(burst and burst.sys.full:find("NS_airExplosionA_S", 1, true) and near(burst.at.X, 1200000), "the air burst where the missile was")
    check(#sounds >= 1 and sounds[#sounds].ev:find("SPWP_OTH_TLS_HIT", 1, true), "the TLS's hit sound there")
    check(far.damage == 40 and ours.damage == 40 and ours.bIsHoming == true, "never the missile 4.5 km off, never an ally's")
    clock = clock + 2
    ZLAS.tick()
    check(comps[1].off == true, "the beam switched off after laser_beam_s")
    -- one shot a laser_shot_s: two enemy missiles in reach, the second taken a second on
    local m2 = missile("wp_msl_r3", 1000000 - 150000, 0, 300000, enemyJet, z1)
    local m3 = missile("wp_msl_r4", 1000000, 250000, 300000, enemyJet, z1)
    HIT.msl[#HIT.msl + 1] = { obj = m2, name = "BP_wp_msl_r3", born = 0 }
    HIT.msl[#HIT.msl + 1] = { obj = m3, name = "BP_wp_msl_r4", born = 0 }
    ZLAS.tick(); clock = clock + 0.5; ZLAS.tick()
    check(m2.damage == 0 and m3.damage == 40, "the nearer first, one shot a second (" .. tostring(m2.damage) .. ", " .. tostring(m3.damage) .. ")")
    clock = clock + 0.6; ZLAS.tick(); clock = clock + 0.5; ZLAS.tick()
    check(m3.damage == 0, "the next a second on")
    -- the game's own laser: made to hit every time, on its instance
    local own = setmetatable({ full = "BP_SwingTLS_ForMSL_C /Game/Maps/PL_SurvivalMode.x:BP_SwingTLS_ForMSL_C_1", addr = addr(),
                               InterceptPercentage = 0.3, InterceptAngle = 45, InterceptDistanceSquared = 9e10 }, PM)
    own.GetOwner = function() return z1 end
    z1.GetFaction = function() return 1 end
    made("/Script/Live.LiveTLSSwingforMissile", own)
    ZLAS.tick()
    check(own.InterceptPercentage == 1.0 and own.InterceptAngle == 180 and own.InterceptDistanceSquared == 300000 * 300000
          and has(line("zfa laser: ", from + 1), "") and has(table.concat(logs, "\n", from), "own laser fired"),
          "the game's own laser shot: chance 0.3 -> 1, its cone and reach")
    -- ((2026-11-07) the user: "the Laser Interceptor doesn't swing or go after the missiles, it also isn't attached to the
    -- aircraft") a launched ZFA-44 (its arm seen as it came out) fires its own laser by its arm's record; the laser that comes
    -- is handed the missile and made sure; no beam of Survival's. Its laser not coming: Survival's beam, attached
    ESC.planes[zU][1].armUnit = zU
    events = {}
    local m6 = missile("wp_msl_r6", 1000000 + 150000, 0, 300000, enemyJet, z1)
    HIT.msl[#HIT.msl + 1] = { obj = m6, name = "BP_wp_msl_r6", born = 0 }
    clock = clock + 2
    local nfx = #fxs
    ZLAS.tick()
    check(K.launchers[1][1].tls == "RE_SV_ZfaTLS_1_1" and evFired("RE_SV_ZfaTLS_1_1") and #fxs == nfx,
          "a launched ZFA-44 fires its own laser on command (RE_SV_ZfaTLS_1_1), no beam of Survival's")
    local own2 = setmetatable({ full = "BP_SwingTLS_ForMSL_C /Game/Maps/PL_SurvivalMode.x:BP_SwingTLS_ForMSL_C_2", addr = addr(),
                                InterceptPercentage = 0.3, InterceptAngle = 45, InterceptDistanceSquared = 9e10 }, PM)
    own2.GetOwner = function() return z1 end
    made("/Script/Live.LiveTLSSwingforMissile", own2)
    clock = clock + 0.3
    ZLAS.tick()
    check(own2.MissileToIntercept == m6 and own2.InterceptPercentage == 1.0 and #fxs == nfx and m6.damage == 40,
          "its laser handed the missile and made to hit; no beam of Survival's; not shot down before its swing's end")
    clock = clock + ZC.laser_stock_swing_s
    ZLAS.tick()
    check(m6.damage == 0, "made sure at its swing's end (laser_stock_swing_s)")
    local m7 = missile("wp_msl_r7", 1000000 + 120000, 0, 300000, enemyJet, z1)
    HIT.msl[#HIT.msl + 1] = { obj = m7, name = "BP_wp_msl_r7", born = 0 }
    clock = clock + 1.1
    nfx = #fxs
    ZLAS.tick()
    check(evCount("RE_SV_ZfaTLS_1_1") == 2 and #fxs == nfx, "the next: its record again, no beam of Survival's yet")
    clock = clock + ZC.laser_stock_wait_s + 0.05
    ZLAS.tick()
    check(#fxs == nfx + 1 and fxs[#fxs].attached and fxs[#fxs].sys.full:find("NS_NPC_TLS_Muzleflash01", 1, true),
          "its own laser didn't come in laser_stock_wait_s: Survival's beam, attached to it")
    ;(function()                                       -- (its own function: the main chunk is at its 200 locals)
    -- ((2026-11-07) "they're firing Multiple Beams at once") a laser that comes with nothing handed to it (its flight's record
    -- fired every plane's): handed the nearest missile nobody's on; with none, hidden, and handed the next one its plane shoots
    clock = clock + 3
    ZLAS.tick()
    local m8 = missile("wp_msl_r8", 1000000 + 90000, 0, 300000, enemyJet, z1)
    HIT.msl[#HIT.msl + 1] = { obj = m8, name = "BP_wp_msl_r8", born = 0 }
    ZC.laser_drive = false                              -- (only the game's own lasers sorted: Survival fires none here)
    ZC.laser_drive = true
    local own3 = setmetatable({ full = "BP_SwingTLS_ForMSL_C /Game/Maps/PL_SurvivalMode.x:BP_SwingTLS_ForMSL_C_3", addr = addr(),
                                InterceptPercentage = 0.3, InterceptAngle = 45, InterceptDistanceSquared = 9e10 }, PM)
    own3.GetOwner = function() return z1 end
    made("/Script/Live.LiveTLSSwingforMissile", own3)
    local from3 = #logs + 1
    ZLAS.tick()
    check(own3.MissileToIntercept == m8 and own3.hidden ~= true and has(line("zfa laser: ", from3) or "", ""),
          "a laser with nothing handed to it: handed the nearest missile nobody's on (" .. tostring(line("laser with nothing handed", from3)) .. ")")
    clock = clock + ZC.laser_stock_swing_s + 0.1
    ZLAS.tick()
    local own4 = setmetatable({ full = "BP_SwingTLS_ForMSL_C /Game/Maps/PL_SurvivalMode.x:BP_SwingTLS_ForMSL_C_4", addr = addr(),
                                InterceptPercentage = 0.3, InterceptAngle = 45, InterceptDistanceSquared = 9e10 }, PM)
    own4.GetOwner = function() return z1 end
    made("/Script/Live.LiveTLSSwingforMissile", own4)
    local from4 = #logs + 1
    ZLAS.tick()
    check(own4.hidden == true and own4.MissileToIntercept == nil and has(line("laser with nothing handed", from4), "hidden (nothing in reach)"),
          "... with none in reach: hidden (no beam at nothing)")
    local m9 = missile("wp_msl_r9", 1000000 + 70000, 0, 300000, enemyJet, z1)
    HIT.msl[#HIT.msl + 1] = { obj = m9, name = "BP_wp_msl_r9", born = 0 }
    events = {}
    clock = clock + 0.3
    ZLAS.tick()
    check(own4.MissileToIntercept == m9 and own4.hidden == false and evCount("RE_SV_ZfaTLS_1_1") == 0,
          "its plane's next shot within the second: that idle laser handed it and shown, no record fired again")
    -- ((2026-11-07) the user: "need to make the Vampires Escort the Nearest Player too them") solo: its cover record
    pose(pawn, 1000000 + 400000, 0, 300000, 0, 0)
    events = {}
    ZLAUNCH.coverAt, ZLAUNCH.escorting = 0, nil
    local fromC = #logs + 1
    ZLAS.tick()
    check(evFired("RE_SV_ZfaCover_1_1") and has(line("carrier: VAMPIRES " .. zU, fromC), "escort you (4.0 km off): RE_SV_ZfaCover_1_1 fired"),
          "the VAMPIRES flight covers the player nearest it (you): its cover record (" .. tostring(line("carrier: VAMPIRES", fromC)) .. ")")
    events = {}
    ZLAS.tick()
    check(not evFired("RE_SV_ZfaCover_1_1"), "not again within escort_s")
    end)()
    ESC.planes[zU][1].armUnit = nil
    -- laser_drive = false: the game's own only
    ZC.laser_drive = false
    local m4 = missile("wp_msl_r5", 1000000 + 50000, 0, 300000, enemyJet, z1)
    HIT.msl[#HIT.msl + 1] = { obj = m4, name = "BP_wp_msl_r5", born = 0 }
    clock = clock + 2; ZLAS.tick(); clock = clock + 1; ZLAS.tick()
    check(m4.damage == 40, "laser_drive = false: Survival fires none")
    ZC.laser_drive = true
    HIT.msl, ZLAS.armed = rawMsl, armed0
    ESC.planes[zU] = nil
end

---------------------------------------------------------------------------------------------------- the launch watch
-- ((2026-11-07) the launched ZFA-44s on Mission 16's allied container drone: parked in the ship until their arm fires;
-- one seen out of the container fires the arm's climb-out record, once; none out in launch_wait_s: the climb-out anyway
-- while any is alive, else pose)
print("the launch watch (sv_escort_laser.lua ZLAUNCH)")
do
    local U2 = K.launchers[1][2].unit
    check(K.launchers[1][2].climb == "RE_SV_ZfaClimb_1_2" and K.dt_npc_drone == "SV_Zfa_Drone", "the build's climb records and the drone's row")
    local sx, sy = K.ship_at[1][1], K.ship_at[1][2]
    local C = { name = "ZFA-44 CARRIER 1", unit = "SV_Unit_NoHull", idx = 1 }
    local F = { route = "container", record = "RE_SV_CargoLaunch_1_2", unit = U2, at = 500 }
    local p1 = plane(nil, sx + 10000, sy, -24484, 0, 0)
    local far = plane(nil, sx + 900000, sy, 3000, 0, 300)      -- (9 km off: another's)
    ESC.planes[U2] = { { obj = p1, addr = p1.addr, name = p1.full, at = 0 }, { obj = far, addr = far.addr, name = far.full, at = 0 } }
    -- ((2026-11-07) "there was no launch smoke": the drone's own put on each one out of its container; followed watch_s)
    local smokes = {}
    local NL2 = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")   -- (the library the game hands out: kept)
    function NL2:SpawnSystemAttached(sys, root) local c = { IsValid = function() return true end, Deactivate = function() end }
        smokes[#smokes + 1] = { sys = sys, root = root }; return c end
    local lf = K.launch_fx .. "." .. K.launch_fx:match("[^/]+$")
    statics[lf] = { full = lf, addr = addr() }
    function p1:K2_GetRootComponent() return { full = "root", owner = self } end
    events = {}
    -- ((2026-11-08) "ZFA-44s dont mark themselves at all on subsequent purchases": switched off by the last carrier's leaving)
    local calls1 = {}
    p1.bShowHUDBox, p1.bIsNotLockonTarget, p1.bIsNotFCSTargets, p1.bIsInvincible = false, true, true, true
    function p1:SetActorHiddenInGame(b) calls1.hidden = b end
    function p1:SetActorEnableCollision(b) calls1.collision = b end
    function p1:SetActorTickEnabled(b) calls1.tick = b end
    function p1:SetActive(b) calls1.active = b end
    check(ZLAUNCH.risen(C, F, 501) == false and evCount("RE_SV_ZfaClimb_1_2") == 0, "parked under the sea: not out yet")
    p1.Z = 2500
    local from = #logs + 1
    check(ZLAUNCH.risen(C, F, 503) == true and evCount("RE_SV_ZfaClimb_1_2") == 1 and F.climbed == true, "out of its container: its climb-out fired")
    check(has(line("carrier: ZFA-44 CARRIER 1: 1 ZFA-44 out of its container", from), "RE_SV_ZfaClimb_1_2 fired"), "logged")
    check(p1.bShowHUDBox == true and p1.bIsNotLockonTarget == false and p1.bIsNotFCSTargets == false and p1.bIsInvincible == false
          and calls1.hidden == false and calls1.collision == true and calls1.tick == true and calls1.active == true,
          "one switched off by a carrier leaving: on again out of its container (box, lock-on, damage, shown)")
    check(has(line("carrier: ZFA-44 CARRIER 1: 1 ZFA-44 out of its container", from), "1 had been switched off by a carrier leaving"),
          "logged")
    check(#smokes == 1 and smokes[1].sys.full == lf and smokes[1].root.owner == p1 and has(line("carrier: ZFA-44 CARRIER 1: 1 ZFA-44 out", from), "launch smoke on 1"),
          "the drone's launch smoke (NS_UAVLaunch001) attached to the one out, logged")
    clock = clock + 1.1
    ZLAS.tick()
    check(has(line("carrier: launched ZFA-44s +1 s:", from), "km/h, yaw"), "followed: where it is, its speed and heading, at +1 s")
    NL2.SpawnSystemAttached = nil
    check(ZLAUNCH.risen(C, F, 504) == true and evCount("RE_SV_ZfaClimb_1_2") == 1, "once")
    local F2 = { route = "container", record = "RE_SV_CargoLaunch_1_3", unit = K.launchers[1][3].unit, at = 600 }
    alive[F2.unit] = 2
    check(ZLAUNCH.late(C, F2, 615) == true and F2.up == true and evCount("RE_SV_ZfaClimb_1_3") == 1,
          "none seen out in launch_wait_s, 2 alive: the climb-out anyway")
    local F3 = { route = "container", record = "RE_SV_CargoLaunch_1_4", unit = K.launchers[1][4].unit, at = 600 }
    alive[F3.unit] = 0
    check(ZLAUNCH.late(C, F3, 615) == false and evCount("RE_SV_ZfaClimb_1_4") == 0, "none alive: by pose (false)")
    check(ZLAUNCH.risen(C, { route = "pose", unit = "SV_Unit_ZfaA", at = 0 }, 1) == false, "a pose flight: not watched")
    ESC.planes[U2] = nil
end
---------------------------------------------------------------------------------------------------- AC7's LaserInterceptor
-- ((2026-11-07) the user: "I want the entire weapon from ACE7 to be ported over") sv_escort_li.lua: the hosts' gun-less rows;
-- each ZFA-44 up gets AC7's weapon at its gun (its owner the plane, AC7's values, its own search off); AC7's fire control:
-- a volley when an enemy missile is within 1.2 km, the nearest in reach handed over each search (one beam a missile, never
-- an ally's, never one out of reach), the class's own kill, SV_Intercept for one still up after its swing, the end flash
-- and the beam thinned at the volley's end, the rest; its plane gone: removed
print("AC7's LaserInterceptor on the ZFA-44s (sv_escort_li.lua)")
;(function()
    local ZC = CFG.allies.carrier.zfa
    check(ZC.li_fx == "ac8", "shipped: AC8's own beam (AC7's Cascade beam stopped the game in the renderer)")
    ZC.li_fx = "ac7"                                      -- (AC7's beam's path first, as it was)
    local LS, begun, intercepted, stops, byAddr = {}, {}, {}, {}, {}      -- (the runtime's laser.c, stubbed)
    function SV_LaserBegin(la, ma) local m = byAddr[ma]; if not m or m.bCollided then return 0 end; LS[la] = 1; begun[#begun + 1] = { li = la, m = ma }; return 1 end
    function SV_LaserState(la, v) local s = LS[la] or 0; if v == 0 and s == 1 then LS[la] = 0; stops[#stops + 1] = la end; return s end
    function SV_Intercept(ma) local m = byAddr[ma]; intercepted[#intercepted + 1] = ma; if m and not m.bCollided then m.bCollided = true; return 1 end; return 0 end
    function SV_LaserKills() return 0 end
    local spawnedL = {}
    -- ((0.74.25) the runtime's owner store: SetOwner is AActor's Owner only, as in the game; the laser's OwningGameObject
    -- only through SV_LaserOwner)
    function SV_LaserOwner(la, pa)
        for _, x in ipairs(spawnedL) do
            if x.addr == la then
                x.ownerAddr = pa
                x.OwningGameObject = { addr = pa, GetAddress = function() return pa end }
                return 1
            end
        end
        return -4
    end
    local cls, wb = { full = "BP_SV_LaserInterceptor_C", addr = addr() }, { full = "LiveWeaponBase", addr = addr() }
    statics[ZC.li_class], statics["/Script/Live.LiveWeaponBase"] = cls, wb
    local function comp(name)
        local c = { name = name, params = {}, active = false, visible = true, bAutoActivate = true }
        function c:SetVectorParameter(n, v) self.params[tostring(n)] = v end
        function c:SetActive(on, reset) self.active, self.reset = on, reset end
        function c:SetVisibility(v) self.visible = v end
        function c:Deactivate() self.active = false end
        return c
    end
    local GS = { full = "GameplayStatics", addr = addr() }
    function GS:BeginDeferredActorSpawnFromClass(pc, c, t, how, owner)
        local a = { full = "BP_SV_LaserInterceptor_C li", addr = addr(), cls = c, how = how, owner = owner,
                    MainLaser = comp("MainLaser"), EndLaser = comp("EndLaser"), root = {} }
        function a.root:K2_SetRelativeRotation(r) self.rot = r end
        function a:K2_GetRootComponent() return self.root end
        function a:SetOwner(o) self.Owner = o end
        function a:K2_AttachToComponent(p, s, l, r, sc) self.attach = { p = p, s = tostring(s), l = l, r = r, sc = sc }; return true end
        function a:K2_DestroyActor() self.gone = true end
        spawnedL[#spawnedL + 1] = a
        return a
    end
    -- ((0.74.25) the hosts' logs: what it hands back isn't the laser (its reads came back wrong): a stand-in here)
    function GS:FinishSpawningActor(x)
        x.finished, x.autoAtFinish = true, x.MainLaser.bAutoActivate
        return { full = "TrivialObject", addr = addr() }
    end
    local keepGS = statics["/Script/Engine.Default__GameplayStatics"]
    statics["/Script/Engine.Default__GameplayStatics"] = GS
    local hits = {}
    local AK = StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")   -- (the one the game hands out: kept, its call patched)
    local keepPost = AK.PostEventAtLocation
    AK.PostEventAtLocation = function(_, ev) hits[#hits + 1] = ev.full end
    -- the rows: AC7's laser on (the runtime's functions there, its class loaded): the gun-less twins
    local n3 = dt("DT_NPC", {})
    local m3 = dt("DT_SV_NpcRows", { SV_Esc_Su57 = { r = 1 }, SV_Esc_Su33 = { r = 2 }, SV_Esc_Su35 = { r = 3 }, SV_Zfa_Ally = { r = 4 },
                                     SV_Zfa_AllyTLS = { r = 5 }, SV_Zfa_Drone = { r = 6 }, SV_Zfa_DroneTLS = { r = 7 },
                                     SV_Zfa_AllyLI = { r = 8 }, SV_Zfa_DroneLI = { r = 9 } })
    ESC.setupDone, ESC.setupTries, Z.laser = nil, 0, true
    statics[PROBE_TABLES[2].path], statics[CFG.specials.shuttle.npc_rows] = n3, m3
    local from = #logs + 1
    ESC.setup()
    local said3 = line("escort: the escorts' and the ZFA-44's rows", from)
    check(n3.rows.SV_Zfa_Ally and n3.rows.SV_Zfa_Ally.r == 8 and n3.rows.SV_Zfa_Drone and n3.rows.SV_Zfa_Drone.r == 9 and ZLI.mode == "ac7"
          and ZLI.on() and has(said3, "AC7's LaserInterceptor at its gun: SV_Zfa_AllyLI's struct, no gun")
          and has(line("zfa li: AC7's LaserInterceptor on the ZFA-44s", from), "BP_SV_LaserInterceptor_C"),
          "AC7's laser on: both hosts' gun-less rows (SV_Zfa_AllyLI, SV_Zfa_DroneLI), logged")
    -- a ZFA-44 up and the missiles near it
    local zU = K.launchers[1][1].unit
    local z1 = plane(zU, 2000000, 0, 300000, 0, 600)
    z1.PlaneBodyMesh = { full = "PlaneBodyMesh", addr = addr() }
    ESC.planes[zU] = { { obj = z1, addr = z1.addr, name = z1.full, at = 0 } }
    local function gobj(full, fac) return setmetatable({ full = full, addr = addr(), GetFaction = function() return fac end }, PM) end
    local enemyJet, allyJet = gobj("BP_Su30_C enemy", 2), gobj("BP_F18_C ally", 1)
    local function missile(name, x, shooter)
        local m = setmetatable({ full = "BP_" .. name .. "_C " .. name, addr = addr(), OwningGameObject = shooter, bCollided = false }, PM)
        m.GetOwner = function() return shooter end
        m.IsDestroyed = function() return false end
        m.IsA = function(_, c) return c == wb end
        pose(m, x, 0, 300000, 0, 0)
        byAddr[m.addr] = m
        return m
    end
    local mA, mB = missile("wp_msl_a", 2000000 + 100000, enemyJet), missile("wp_msl_b", 2000000 - 110000, enemyJet)   -- 1 / 1.1 km
    local mFar, mOurs = missile("wp_msl_far", 2000000 + 250000, enemyJet), missile("wp_msl_ours", 2000000 + 50000, allyJet)   -- (far: 2.5 km, past the 2 km reach)
    HIT = HIT or { msl = {} }
    local keepMsl = HIT.msl
    HIT.msl = { { obj = mA, name = "BP_wp_msl_a", born = 0, from = "BP_Su30" }, { obj = mB, name = "BP_wp_msl_b", born = 0 },
                { obj = mFar, name = "BP_wp_msl_far", born = 0 }, { obj = mOurs, name = "BP_wp_msl_ours", born = 0 } }
    D = D or {}
    local ev0 = #events
    from = #logs + 1
    local t0 = clock
    ZLAS.tick()
    local li = spawnedL[1]
    check(li and li.owner == z1 and li.cls == cls and li.how == 1 and li.finished and li.SearchInterval == 1.0e9 and li.InterceptTime == 1.0
          and li.InterceptAngle == 180 and li.RayDistance == 200000 and li.LifeTime == 6.0 and li.bIsBaseAttached == true
          and li.autoAtFinish == false and li.Owner == z1 and li.ownerAddr == z1.addr,
          "AC7's laser spawned for the ZFA-44: its owner the plane (SV_LaserOwner, AActor's too), AC7's values, its own search off, its beam waiting for a volley")
    check(li and li.attach and li.attach.p == z1.PlaneBodyMesh and li.attach.s == "SOC_Gun_01" and li.attach.l == 2 and li.attach.r == 2
          and li.attach.sc == 1 and has(line("zfa li: ", from) and line("carries AC7's LaserInterceptor", from), "owner its plane (SV_LaserOwner 1)")
          and has(line("carries AC7's LaserInterceptor", from), "FinishSpawningActor answered"),
          "... attached at its gun (SOC_Gun_01, snapped), logged: " .. tostring(line("carries AC7's LaserInterceptor", from)))
    check(li and li.MainLaser.active and li.MainLaser.reset and li.MainLaser.visible and li.MainLaser.params.BeamLength
          and near(li.MainLaser.params.BeamLength.X, 20000) and li.MainLaser.params.BeamLength.Y == 1 and li.EndLaser.active == false
          and li.root.rot and li.root.rot.Yaw == 0 and has(line("zfa li: ", from), "fires a volley (BP_wp_msl_a 1000 m off"),
          "an enemy missile 1 km off (AC7's 1.2 km): a volley, the beam from its start, 1.24 km long in AC7's units")
    check(#begun == 0, "no swing before its first search (li_search_s)")
    clock = t0 + 0.5; ZLAS.tick()
    check(#begun == 1 and begun[1].li == li.addr and begun[1].m == mA.addr and has(line("zfa li: ", from), "swings onto BP_wp_msl_a@"),
          "its first search: the nearest enemy missile handed over (SV_LaserBegin)")
    clock = t0 + 1.0; ZLAS.tick()
    check(#begun == 1, "one swing at a time")
    mA.bCollided, LS[li.addr] = true, 0                   -- (the class's own kill at its swing's end: the missile in its pool)
    clock = t0 + 1.5; ZLAS.tick()
    check(has(line("zfa li: ", from) and line("shot down BP_wp_msl_a@", from), "(from BP_Su30; 1 so far)") and #hits >= 1
          and hits[#hits]:find("SPWP_OTH_TLS_HIT", 1, true), "shot down at its swing's end: logged, the TLS's hit sound")
    check(#begun == 2 and begun[2].m == mB.addr, "the next search: the other enemy missile in reach")
    clock = t0 + 3.2; ZLAS.tick()                          -- (mB's swing over at 2.5 s, still up at 3.1)
    check(intercepted[1] == mB.addr and mB.bCollided == true and has(line("SV_Intercept -> 1", from), "still up"),
          "a missile still up li_sure_s after its swing: made sure (SV_Intercept)")
    for _, b in ipairs(begun) do
        check(b.m ~= mFar.addr and b.m ~= mOurs.addr, "never the missile 2.5 km off (out of its reach), never an ally's")
    end
    check(#events == ev0 and not line("zfa laser: ", from), "AC8's laser route quiet: no record fired, no beam of its own")
    -- the volley's end (6 s): a swing on given up, AC7's end flash, the beam thinned; then the rest (8 s)
    LS[li.addr] = 1
    clock = t0 + 6.0; ZLAS.tick()
    check(stops[1] == li.addr and li.EndLaser.active and li.EndLaser.reset and li.EndLaser.visible and li.MainLaser.params.BeamLength.Y == 0.5,
          "the volley's end: its swing given up, AC7's end flash (EndLaser), the beam thinning")
    clock = t0 + 6.25; ZLAS.tick()
    check(li.MainLaser.params.BeamLength.Y == 0 and li.MainLaser.active == false and li.MainLaser.visible == false, "the beam gone li_end_s on")
    local mC = missile("wp_msl_c", 2000000 + 80000, enemyJet)
    HIT.msl[#HIT.msl + 1] = { obj = mC, name = "BP_wp_msl_c", born = 0 }
    clock = t0 + 10; ZLAS.tick()
    check(li.MainLaser.active == false, "no volley in its rest (li_rest_s)")
    clock = t0 + 14.3; ZLAS.tick()
    check(li.MainLaser.active == true and has(line("fires a volley", from), "BP_wp_msl_c 800 m off"), "the next volley once rested")
    -- ((2026-11-08) li_fx "ac8", the default: AC8's own UAV beam (Niagara) on the laser's root, its end flash; AC7's never lit)
    ZC.li_fx = "ac8"
    local NLx = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local fxs = {}
    local bp = ZC.li_fx_beam .. "." .. ZC.li_fx_beam:match("[^/]+$")
    local ep = ZC.li_fx_end .. "." .. ZC.li_fx_end:match("[^/]+$")
    statics[bp], statics[ep] = { full = bp, addr = addr() }, { full = ep, addr = addr() }
    local keepSSA = NLx.SpawnSystemAttached
    function NLx:SpawnSystemAttached(sys, root, sock, loc, rot, how)
        local c = { full = "NiagaraComponent", addr = addr(), sys = sys, root = root, how = how, vars = {}, active = true }
        function c:IsValid() return true end
        function c:SetVariableFloat(n, v) self.vars[tostring(n)] = v end
        function c:SetVariableVec3(n, v) self.vars[tostring(n)] = v end
        function c:Deactivate() self.active = false end
        fxs[#fxs + 1] = c
        return c
    end
    clock = t0 + 20.3; ZLAS.tick()                       -- (the volley begun in AC7's way ends: AC8's end flash)
    check(#fxs == 1 and fxs[1].sys == statics[ep] and fxs[1].root == li.root, "a volley's end: AC8's end flash on the laser's root")
    li.MainLaser.active, li.EndLaser.active = false, false
    clock = t0 + 20.6; ZLAS.tick()
    local mD = missile("wp_msl_d", 2000000 + 90000, enemyJet)
    HIT.msl[#HIT.msl + 1] = { obj = mD, name = "BP_wp_msl_d", born = 0 }
    local from8 = #logs + 1
    clock = t0 + 29; ZLAS.tick()
    local fb = fxs[2]
    check(fb and fb.sys == statics[bp] and fb.root == li.root and fb.how == 0 and math.abs(fb.vars["User.BeamLifeTime"] - 7.2) < 1e-6
          and fb.vars["User.BeamLength"] and fb.vars["User.BeamLength"].X == 200000 and fb.vars["User.BeamLength"].Y == 1
          and li.MainLaser.active == false and li.EndLaser.active == false and has(line("fires a volley", from8), "AC8's beam"),
          "a volley: AC8's beam on the laser's root (it swings with it), 1.24 km long in cm, its life the volley's; AC7's never lit")
    clock = t0 + 35; ZLAS.tick()
    check(#fxs == 3 and fxs[3].sys == statics[ep] and fb.vars["User.BeamLength"].Y == 0.5 and li.EndLaser.active == false,
          "its end: AC8's end flash, the beam thinning")
    clock = t0 + 35.25; ZLAS.tick()
    check(fb.active == false and fb.vars["User.BeamLength"].Y == 0, "the beam off li_end_s on")
    -- ((2026-11-08) Alyssa's run of 0.74.31: a swing begun in a volley's last second was given up at its end, its missile
    -- let through) the volley holds until that swing is over
    local mE = missile("wp_msl_e", 2000000 + 60000, enemyJet)
    HIT.msl[#HIT.msl + 1] = { obj = mE, name = "BP_wp_msl_e", born = 0 }
    LS[li.addr] = 0
    clock = t0 + 44; ZLAS.tick()                          -- (rested: a volley, 44 .. 50)
    local nfx, nb = #fxs, #begun
    clock = t0 + 49.6; ZLAS.tick()                        -- (its swing begun 0.4 s before the volley's end)
    check(#begun == nb + 1 and begun[#begun].m == mE.addr, "a swing begun in the volley's last second")
    local fromH = #logs + 1
    clock = t0 + 50.1; ZLAS.tick()
    check(#fxs == nfx and has(line("volley held past", fromH), "its swing on now is finished first"),
          "the volley's time out with a swing on: held, no end flash yet")
    mE.bCollided, LS[li.addr] = true, 0                   -- (the class's kill at its swing's end)
    clock = t0 + 50.7; ZLAS.tick()
    check(has(line("shot down BP_wp_msl_e@", fromH), "so far)") and #fxs == nfx + 1 and fxs[#fxs].sys == statics[ep],
          "... the missile shot down, then the volley's end (its end flash)")
    NLx.SpawnSystemAttached = keepSSA
    -- its plane gone: removed
    ESC.planes[zU] = nil
    clock = t0 + 15; ZLAS.tick()
    check(li.gone == true and has(line("zfa li: ", from), "removed (its plane is gone)"), "its plane gone: the laser removed")
    -- put back for the rest of the test
    ZLI.mode, HIT.msl = "tls", keepMsl
    statics["/Script/Engine.Default__GameplayStatics"], AK.PostEventAtLocation = keepGS, keepPost
    SV_LaserBegin, SV_LaserState, SV_Intercept, SV_LaserKills = nil, nil, nil, nil
end)()
---------------------------------------------------------------------------------------------------- the dressing
print("the ZFA-44 dressing (sv_zfa44.lua)")
part("sv_zfa44.lua")                                -- (its real ZFA.dress again)
ZFA.C.missing_again_s = 60
local o = plane("x", 0, 0, 0, 0, 0)
local okD, why = ZFA.dress(o, { paint = 3, label = "test" })
check(okD == false and has(why, "SK_ZFA44") and has(line("zfa44: NOT dressed"), "fly as their host airframe"),
      "no SK_ZFA44: not dressed, said once")
local nl = #logs
local okD2 = ZFA.dress(o, { paint = 3 })
check(okD2 == false and #logs == nl, "... not tried again within a minute")
check(ZFA.undress(o) == false and ZFA.dressedCount() == 0, "nothing to undress")

logFile:close()
print(fails == 0 and "escort test: all passed" or ("escort test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
