-- escort_test.lua <mod dir> <work dir> (run by tools/checks/escort_test.sh): THE ESCORT and the ZFA-44 carriers
-- (2026-11-06; Scripts/sv_escort.lua, tools/re/ESCORT.md) on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud,
-- sv_spawn, sv_rounds, sv_flights, sv_shop, sv_allies, sv_tactical, sv_escort and sv_zfa44, the game stubbed:
--   the special kind: in the rotation from round 9, ready only with its units in the world data (SV_UnitAlive -2: not),
--     once a run; its spawn (CHARLENE at CFG start, the escorts beside her at their offsets), the route records, her
--     health; the enemy flights sent after her (EngagementOrderOverride TargetFirst, again, ESC.holds), the round's
--     spawns ahead of her (DIR.spawnAt), more enemies ahead of her, the escorts on her attackers;
--   the landing by distance: her final (gear, the escorts' orbit, landing closed), rollout (invincible, the attackers
--     back on you), taxi, stop, landed; the escorts one at a time once the runway's clear, each its own records; one
--     shot down (out), one stuck on final (the safety timeout: counted landed, switched off); the win (the pay, the
--     unlock, her subtitle whole, landing open again), the round's end (each switched off, its unit recycled);
--   her loss (no pay, no unlock, the attackers let go, the run on);
--   the STORE: the carrier locked, then on the revive row and its own item, two at most, the price; each ship's
--     container launch, a plane near it taken as its flight's (dressed), a ship with no plane in 10 s on the pose
--     fallback, the flight down and the next arm, an arm launched before recycled first, the 3 rounds' service and
--     leaving, a sunk ship;
--   co-op: the host's "es", a joiner's copy of it (the unlock, the room's count, its NEXT row, landing closed / open),
--     a joiner's purchase asked of the host, the host's check at the room's price;
--   sv_zfa44.lua's production dressing without the ZFA-44 installed (said once, not tried again for a minute).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
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
function StaticFindObject() return nil end
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

local function part(name, chunk)
    assert(load(readAll(MOD .. "/Scripts/" .. name), chunk or ("=" .. name)))()
end
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
    spawned[#spawned + 1] = { u = u, pose = pose }
    D.up[u] = true
    return 2
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
check(k.ready() == false, "not ready again in the same run (once)")
local sp = {}
for _, s in ipairs(spawns) do sp[s.u] = s end
local st = C.start
check(sp.SV_Unit_Charlene and sp.SV_Unit_Charlene.x == st.x and sp.SV_Unit_Charlene.y == st.y and sp.SV_Unit_Charlene.z == st.z
      and near(sp.SV_Unit_Charlene.yaw, 55 - 90), "CHARLENE at the south-west start, 3 km up, heading 055 (yaw -35)")
do
    local fx, fy = fwd(55)
    local rx, ry = math.cos(math.rad(55)), math.sin(math.rad(55))
    local y = sp.SV_Unit_EscYorke
    check(y and near(y.x, st.x - rx * 25000 - fx * 25000, 1) and near(y.y, st.y - ry * 25000 - fy * 25000, 1),
          "YORKE 250 m to her left and 250 m behind")
    local d = sp.SV_Unit_EscDanielle
    check(d and near(d.x, st.x + rx * 25000 - fx * 50000, 1), "DANIELLE to her right, 500 m behind")
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
orders = {}
run(11)
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
-- more enemies while few are up
planes[2].down = true
run(41)
check(#spawned >= 1 and spawned[1].pose and spawned[1].pose.why == "ahead of CHARLENE" and has(line("escort: more enemies:"), "ahead of CHARLENE"),
      "more enemies ahead of her while few are up")

---------------------------------------------------------------------------------------------------- her landing
print("her landing")
local H = P.SV_Unit_Charlene
pose(H, before(g.iaf, 55, 1500, g.iaf[3], 450))
run(0.5)
local S = ESC.S
check(evFired("RE_SV_CharFinal") and H.gear == true and S.state == "landing" and D.special.state == "landing",
      "her final 1.5 km before the approach fix: RE_SV_CharFinal, gear down, the round landing")
check(evFired("RE_SV_EscYorkeOrbit") and evFired("RE_SV_EscRockOrbit") and evFired("RE_SV_EscAliOrbit") and evFired("RE_SV_EscDanielleOrbit"),
      "the escorts' orbit as she's on final")
check(evFired("RE_SV_AirfieldClose") and S.closed and callout(C.text.final), "landing closed to the players, her final called out")
pose(H, before(g.touchdown, 67, 2500, 750 + 15000, 300))
run(0.5)
check(H.avoid == false, "her obstacle avoidance off within avoid_off_km of the touchdown")
orders = {}
pose(H, before(g.touchdown, 67, 100, 750 + 900, 270))
run(1.5)
local back = 0
for _, o in ipairs(orders) do if o.target == pawn and o.prio == 8 then back = back + 1 end end
check(evFired("RE_SV_CharRoll") and H.inv == true and not ESC.holds(E1) and back >= 1,
      "her rollout at the touchdown point: invincible, her attackers back on you")
check(not evFired("RE_SV_EscYorkeFinal") and ESC.S.released == 0, "no escort released while she rolls out")
pose(H, before(g.roll_end, 67, 100, 750, 60))
run(0.5)
check(evFired("RE_SV_CharTaxi"), "her taxi near the rollout's end")
run(0.5)
check(ESC.S.released == 1 and has(line("escort: YORKE released"), "1 of 4"), "the first escort released once the runway's clear")
pose(H, g.hold[1], g.hold[2], 750, 160, 10)
run(0.5)
check(evFired("RE_SV_CharStop"), "her stop at her parking spot")
pose(H, g.hold[1], g.hold[2], 750, 160, 0)
run(3)
check(S.ac[1].st == "landed" and S.ac[1].how == "stopped" and callout(C.text.landed), "landed once stopped, called out")
check(k.busy(D.special) == true, "the round held while the escorts are up")

---------------------------------------------------------------------------------------------------- the escorts
print("the escorts")
local Y = P.SV_Unit_EscYorke
pose(Y, before(g.iaf, 67, 10000, 90000, 500))
run(0.5)
check(evFired("RE_SV_EscYorkeFinal") and Y.gear == true, "YORKE's final once the approach fix is ahead of it, gear down")
pose(Y, before(g.touchdown, 67, 50, 750 + 500, 250))
run(0.5)
pose(Y, before(g.roll_end, 67, 50, 750, 50))
run(0.5)
local ys = ESC.rwPoint(1335, 60)
pose(Y, ys.X, ys.Y, 750, 160, 5)
run(0.5)
pose(Y, ys.X, ys.Y, 750, 160, 0)
run(3)
check(evFired("RE_SV_EscYorkeRoll") and evFired("RE_SV_EscYorkeTaxi") and evFired("RE_SV_EscYorkeStop") and S.ac[2].st == "landed",
      "YORKE: rollout, taxi, its own parking spot, landed")
P.SV_Unit_EscRock.HealthInternal = 0
alive.SV_Unit_EscRock = 0
run(0.5)
check(S.ac[3].st == "lost" and callout("ROCK IS DOWN"), "ROCK shot down: out, called out")
local relAt = #logs
run(46)
check(S.released == 2 and has(line("escort: ALI released", relAt), "2 of 4"), "the next escort (ALI) release_gap_s after the last, ROCK skipped")
local A = P.SV_Unit_EscAli
pose(A, before(g.iaf, 67, 8000, 90000, 500))
run(0.5)
check(evFired("RE_SV_EscAliFinal"), "ALI's final")
pose(A, before(g.iaf, 247, 5000, 90000, 500))      -- (it never comes down: circling the fix)
run(C.landing.land_timeout_s + 1)
check(S.ac[4].st == "landed" and S.ac[4].how == "timeout" and A.hidden == true and has(line("escort: ALI landed"), "taken off"),
      "ALI stuck on final: the safety timeout counts it landed, switched off as it's still flying")
run(1)
check(S.released == 3, "DANIELLE released after it")
local Dn = P.SV_Unit_EscDanielle
pose(Dn, before(g.iaf, 67, 8000, 90000, 500)); run(0.5)
pose(Dn, before(g.touchdown, 67, 50, 750 + 500, 250)); run(0.5)
pose(Dn, before(g.roll_end, 67, 50, 750, 50)); run(0.5)
local ds = ESC.rwPoint(1035, 60)
local credits0 = RUN.credits
pose(Dn, ds.X, ds.Y, 750, 160, 5); run(0.5)
pose(Dn, ds.X, ds.Y, 750, 160, 0); run(3)

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
run(K.first_s + 0.5)
check(evFired("RE_SV_CargoLaunch_1_1") and evFired("RE_SV_CargoLaunch_2_1"), "each ship's first container launch first_s on")
local z1 = plane(nil, 1610476 + 20000, 249000, 5000, 90, 300)
z1.full = "BP_OP_drone_C /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel.Z1"
logPlane(z1, nil, nil)
run(0.5)
local inA = false
for _, p in ipairs(ALLY.state().planes) do if p.obj == z1 and p.unit == "E_Unit_01_drone_1_0" then inA = true end end
check(inA and ESC.planes.E_Unit_01_drone_1_0 and #ESC.planes.E_Unit_01_drone_1_0 == 1, "a plane with no unit near ship 1: its flight's (E_Unit_01_drone_1_0), an ally")
check(#dressed == 1 and dressed[1].o == z1 and dressed[1].paint == 3, "dressed as the ZFA-44, paint 3")
run(10)
check(has(line("carrier: ZFA-44 CARRIER 1's ZFA-44s are up"), "1 planes seen"), "ship 1's flight up")
check(spawns[#spawns].u == "SV_Unit_ZfaB" and has(line("carrier: ZFA-44 CARRIER 2: RE_SV_CargoLaunch_2_1 fired"), "launched by pose"),
      "ship 2: no plane in launch_wait_s: by pose from now on")
do
    local s2 = spawns[#spawns]
    local yaw = (math.deg(math.atan(K.spots[2][1] - 1610476, 0)) )
    check(near(s2.z, K.pose.alt_m * 100, 1) and math.abs(s2.x - K.spots[2][1]) < 40000, string.format("... off its bow, %g m up", s2.z / 100))
end
z1.HealthInternal = 0
alive.E_Unit_01_drone_1_0 = 0
run(6)
check(has(line("carrier: ZFA-44 CARRIER 1's ZFA-44 flight E_Unit_01_drone_1_0 is down"), "another in"), "ship 1's flight down: another after relaunch_s")
run(K.relaunch_s)
check(evFired("RE_SV_CargoLaunch_1_2"), "the next arm's launch record")
local z2 = plane(nil, 1610476 - 30000, 249000 + 10000, 8000, 90, 300)
logPlane(z2, nil, nil)
check(ESC.planes.E_Unit_01_drone_1_1 and #ESC.planes.E_Unit_01_drone_1_1 == 1, "its plane taken as that arm's flight (E_Unit_01_drone_1_1)")
run(3)
z2.HealthInternal = 0
alive.E_Unit_01_drone_1_1 = 0
local nr = #recycled
run(20 + K.relaunch_s)
local recFirst = false
for i = nr + 1, #recycled do if recycled[i] == "E_Unit_01_drone_1_0:1" then recFirst = true end end
check(recFirst and evCount("RE_SV_CargoLaunch_1_1") == 2, "arm 1 again: its unit launched before taken off the spawner's list first")

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
print("the landing test T0 (Ctrl+F6)")
alive.SV_Unit_Charlene = nil
spawns, events = {}, {}
D.state, D.at = "wait", now + 1
RUN.zfa = nil
local lb0, cr1 = #lbs, RUN.credits
ESC.testT0()
local T = ESC.S
local s0 = spawns[#spawns]
check(T and T.test == "t0" and s0 and s0.u == "SV_Unit_Charlene" and s0.x == g.iaf[1] and s0.z == g.iaf[3] and near(s0.yaw, 67 - 90)
      and #T.ac == 1, "CHARLENE alone at the approach fix, heading 067 (yaw -23)")
local h0 = plane("SV_Unit_Charlene", s0.x, s0.y, s0.z, 67, 300)
logPlane(h0, "SV_Unit_Charlene", nil)
run(1.5)
check(evFired("RE_SV_CharFinal") and not evFired("RE_SV_CharGo") and h0.gear == true and h0.inv == true and h0.HealthInternal == 1300,
      "her final at once (no route), gear down, invincible, her health as it is")
check(has(line("escort: T0 +"), "gear") and D.at >= now + 2.5, "her place, height, speed and gear logged; the break held")
pose(h0, before(g.touchdown, 67, 100, 750 + 600, 250)); run(0.5)
pose(h0, before(g.roll_end, 67, 100, 750, 50)); run(0.5)
pose(h0, g.hold[1], g.hold[2], 750, 160, 5); run(0.5)
pose(h0, g.hold[1], g.hold[2], 750, 160, 0); run(3)
check(T.state == "done" and has(line("escort: T0 over"), "stopped") and has(line("escort: T0: her rollout began"), "past runway 07's west threshold")
      and not ESC.unlocked() and #lbs == lb0 and RUN.credits == cr1, "landed: the test over, where her rollout began logged, no pay, unlock or leaderboard line")
run(C.test.end_s + 1)
check(ESC.S == nil and h0.hidden == true, "taken off end_s after she's down")

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
