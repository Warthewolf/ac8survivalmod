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
--     skipped, a unit on the spawner's list taken off first, a downed flight's unit recycled; the pose flight's RE_SV_ZfaGo.
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
part("sv_escort.lua")
part("sv_zfa44.lua")
local function line(pat, from)
    for i = #logs, from or 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end
    return nil
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
local mineT = dt("DT_SV_NpcRows", { SV_Esc_Su57 = { r = 1 }, SV_Esc_Su33 = { r = 2 }, SV_Esc_Su35 = { r = 3 }, SV_Zfa_Ally = { r = 4 } })
statics[PROBE_TABLES[2].path], statics[CFG.specials.shuttle.npc_rows] = npcT, mineT
ESC.setup()
check(npcT.rows.SV_Esc_Su57 and npcT.rows.SV_Esc_Su33 and npcT.rows.SV_Esc_Su35 and npcT.rows.SV_Zfa_Ally and ESC.rowsOk == true
      and ESC.zfaRowOk == true and has(line("escort: the escorts' and the ZFA-44's rows"), "SV_Zfa_Ally in DT_NPC"),
      "the escorts' and the ZFA-44 host's rows from DT_SV_NpcRows into DT_NPC at the main menu, logged")
check(texts.SV_CharleneCall == "CHARLENE" and texts.SV_Yorke == "YORKE" and texts.SV_Rock == "ROCK" and texts.SV_Ali == "ALI"
      and texts.SV_Danielle == "DANIELLE" and texts.SV_Cargo == K.name and texts.SV_Zfa44 == "ZFA-44",
      "the seven names on their boxes set there (SV_SetText)")

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
    local w = wavesOf()[#wavesOf()]
    local mid = w.flights[math.floor((#w.flights + 1) / 2)].pose
    local m = ZONE.HALF - 300000
    check(math.abs(mid.x - ZONE.X) < m - 1 and math.abs(mid.y - ZONE.Y) < m - 1 and w.sec ~= ws[#ws].sec,
          "at her start (the combat zone's corner) a wave from a direction inside the zone")
end

---------------------------------------------------------------------------------------------------- her landing
print("her landing")
local H = P.SV_Unit_Charlene
pose(H, before(g.iaf, 55, 1500, g.iaf[3], 450))
run(0.5)
local S = ESC.S
check(evFired("RE_SV_CharCruiseSlow") and has(line("her route at 450 km/h"), "RE_SV_CharCruiseSlow fired") and not evFired("RE_SV_EscYorkeCruiseSlow"),
      "her route at 450 within cruise_slow_km of the touchdown (her escorts covering her, not on their routes)")
check(evFired("RE_SV_CharFinal") and H.gear == true and S.state == "landing" and D.special.state == "landing",
      "her final 1.5 km before the approach fix: RE_SV_CharFinal, gear down, the round landing")
check(evFired("RE_SV_EscYorkeOrbit") and evFired("RE_SV_EscRockOrbit") and evFired("RE_SV_EscAliOrbit") and evFired("RE_SV_EscDanielleOrbit"),
      "the escorts hold over her as she's on final (their Orbit records: area on her, no path)")
check(not evFired("RE_SV_AirfieldClose") and not S.closed and callout(C.text.final),
      "her final called out; the players' landing still open with her 16 km out (close_km)")
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
check(nFired("RE_SV_CharCruiseSlow") == 2 and has(line("escort: CHARLENE's final at 450 km/h"), "RE_SV_CharCruiseSlow fired"),
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
P.SV_Unit_EscRock.HealthInternal = 0
alive.SV_Unit_EscRock = 0
run(0.5)
check(S.ac[3].st == "lost" and callout("ROCK IS DOWN"), "ROCK shot down: out, called out")
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
    local parts = {}
    for _, c in ipairs(callouts) do
        local t, sub = c:match("^(.-) / (.*)$")
        if t == C.name then parts[#parts + 1] = sub end
    end
    check(table.concat(parts, " ") == C.subtitle and #parts >= 2,
          string.format("her subtitle whole, the user's exact text, in %d callouts", #parts))
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
run(0.5)
local S2 = ESC.S
check(S2.state == "done" and S2.lost and not ESC.unlocked() and RUN.credits == cr0 and lbs[#lbs].won == false
      and callout(C.text.lost) and not ESC.holds(E1) and k.busy(D.special) == false,
      "her death: the special failed (no pay, no unlock), the attackers let go, the round may end")
k.over(now, D.special)

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
    local recL = false
    for i = nrL + 1, #recycled do if recycled[i] == A1 .. ":1" then recL = true end end
    check(recL and has(line("carrier: ZFA-44 CARRIER 1: " .. A1 .. " had 2 up that this carrier never launched"), "taken off the spawner's list first")
          and not line("every launcher arm's flight is still up"),
          "an arm whose unit has planes up the carrier never launched (the ship's own): taken off the list first, then launched")
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
-- (arm 3's unit with planes up this carrier never launched: taken off the list first and launched, never skipped)
local A3, A4 = K.launchers[1][3].unit, K.launchers[1][4].unit
alive[A3], alive[A4] = 2, 0
local nr = #recycled
run(20 + K.relaunch_s)
local recA3 = false
for i = nr + 1, #recycled do if recycled[i] == A3 .. ":1" then recA3 = true end end
check(evFired("RE_SV_CargoLaunch_1_3") and recA3
      and has(line("carrier: ZFA-44 CARRIER 1: " .. A3 .. " had 2 up that this carrier never launched"), "taken off the spawner's list first"),
      "the next arm in turn, its unit with 2 up this carrier never launched: taken off the spawner's list, then launched (never skipped)")
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
    check(got == arm2.unit and rec and zA.active == false and zA.hidden == true
          and has(line("carrier: the host's " .. arm2.record .. " here: " .. arm2.unit .. " first"), "of this game's ZFA-44s of ship 1 before it switched off"),
          "a joiner: before the host's " .. arm2.record .. " fires here: " .. arm2.unit .. " off this game's list (force 1), ship 1's last flight here switched off")
    check(ESC.beforeHostEvent("RE_SV_ValkaShot") == nil and ESC.beforeHostEvent("RE_SV_CargoLaunch_1_9") == nil, "... any other event: nothing")
    alive[arm2.unit] = nil
    -- ship 1 gone on the host (left or sunk): this game's own ZFA-44s of it off
    local zB = plane(nil, sp1[1] - 10000, sp1[2] + 10000, 5000, 90, 300)
    logPlane(zB, nil, nil)
    alive[armU] = 2
    local q0 = #ESC.recycleQ
    ESC.onHost({ "es", "", "0", "0", "-1", "0", "1", "1", "0", "2" })
    check(zB.active == false and zB.hidden == true and #ESC.recycleQ > q0
          and has(line("carrier: the host's ZFA-44 CARRIER 1 is gone"), "of this game's own ZFA-44s of it switched off"),
          "a joiner: ship 1 no longer up on the host's game (field 10): its own ZFA-44s of it off, its arms' units queued off the list")
    alive[armU] = nil
    ESC.recycleQ = {}
    ESC.onHost({ "es", "route", "1", "5", "80", "23.4", "1", "1", "0" })   -- (an older host: no field 10, nothing more taken off)
end
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
