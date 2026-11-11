-- lag_test.lua <mod dir> <work dir> (run by tools/checks/lag_test.sh): Saint Alessia's 50-round co-op run's lag fixes in
-- the allies part (2026-11-11), on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_rounds, sv_flights,
-- sv_shop, sv_allies and sv_tactical, the game stubbed (FindAllOf counted: in the game each walk reads every object,
-- ~41 ms late in her run):
--   lag-3, the round clear's repair: the allied ships' and the defences' objects kept as SV_Spawn makes them (ALLY.parts:
--     ALLY.buy, the STORE's defences through sv_shop.lua, which now names the unit), their names read the tick after; the
--     repair heals from those with no walk (the old one walked 7 classes in one tick), only the classes it always healed,
--     never an object whose address is another's now (hard rule 59); a unit up with none kept: walked for one class a
--     tick at a round clear, at once for the STORE's airfield repair; ALLY.forgetActors drops them;
--   the defences' re-find (lag missed-1): their actors from the kept objects, no walk; the walk as before when one up
--     has none kept;
--   lag-5, VOID WATCHER's ESM fields: a tick reads the fields set in the last life_s + 5 s and a slice of the rest (all
--     of them every ESM_SWEEP_S), names compared only before a field is set again; nothing while it isn't airborne here
--     and no field was set in ESM_ACTIVE_S; an old field launched again found by the sweep; the newest ESM_KEEP kept.
-- Each of these fails on the code before the fix (its walks, its reads every tick).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- the game's world, stubbed
VERSION = "0.74.51-lag.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
local GI = { full = "GameInstance", addr = 1 }
local notify = {}                                 -- NotifyOnNewObject's callbacks by class (the game calls them at construction)
function NotifyOnNewObject(cls, fn) notify[cls] = notify[cls] or {}; table.insert(notify[cls], fn) end
local function made(cls, o) for _, fn in ipairs(notify[cls] or {}) do fn(o) end end
local objects, walked = {}, {}
function FindAllOf(c) walked[#walked + 1] = c; return objects[c] or {} end
function FindFirstOf(c) if c == "BP_LiveGameInstance_C" then return GI end return nil end
function StaticFindObject() return nil end
local events, alive, spawned = {}, {}, {}
function SV_Event(name) events[#events + 1] = name; return 1 end
function SV_UnitAlive(u) return alive[u] or 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
local spawnParts = {}                             -- unit -> the objects its spawn makes (made() at the spawn, as the game)
function SV_Spawn(u)
    spawned[#spawned + 1] = u
    alive[u] = 1
    for _, o in ipairs(spawnParts[u] or {}) do made("/Script/Live.LiveAIGameObject", o) end
    return 1
end
function SV_SetText() return 1 end
function SV_ShopRequest(probe) if probe then return 1 end return "" end
-- objects by address (the runtime's GUObjectArray): SV_ObjChain counted, as liveAddr and nameOf ask it in the game
local byAddr, chainAsks, nameReads = {}, 0, 0
function SV_ObjChain(a) chainAsks = chainAsks + 1; local o = byAddr[a]; return (o and not o.gone) and 1 or 0 end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) nameReads = nameReads + 1; return type(o) == "table" and not o.gone and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_flights.lua"); part("sv_shop.lua"); part("sv_allies.lua"); part("sv_tactical.lua")
function playerOnAirfield() return false end
function hudCallout() end
local rawFlags = svFlags
local FLAGS = {}
svFlags = function() return FLAGS end
local function line(pat, from)
    for i = #logs, from or 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end
    return nil
end
local lvl = "/Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel."
local nextAddr = 1000
local function obj(cls, hp, extra)                -- an object of the level: its name holds its class's, as the game's
    nextAddr = nextAddr + 1
    local o = { full = cls .. " " .. lvl .. cls .. "_" .. nextAddr, addr = nextAddr, HealthInternal = hp or 600, MaxHealth = 60 }
    o.K2_GetActorLocation = function() return { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = 0 } end
    for k, v in pairs(extra or {}) do o[k] = v end
    byAddr[o.addr] = o
    return o
end
local function walksSince(n) return #walked - n end
CFG.allies.enabled, CFG.allies.repair = true, true

---------------------------------------------------------------------------------------------------- lag-3: the repair
print("lag-3: the round clear's repair from the objects kept at their spawn")
D = { round = 20, now = 100, state = "wait", up = {} }
RUN = { credits = 99999, spent = 0, bought = {}, kills = 0, roundKills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 } }
ALLY.run = nil
local R = ALLY.state()
local SHIPU = CFG.allies.ships.Aegis.units[1]
local hull, mk15, mk41 = obj("BP_VE002_aegs_CP_C", 300), obj("BP_VE002_aegs_mk15_01_CP_C", 200), obj("BP_VE002_aegs_mk41_CP_C", 600)
local mk45, art = obj("BP_VE002_aegs_mk45_CP_C", 100), obj("BP_VE002_aegs_artillery_CP_C", 100)
spawnParts[SHIPU] = { hull, mk15, mk41, mk45, art }
check(ALLY.buy("ally_ship", SHIPU, "Aegis", 1000) == true and ALLY.parts[SHIPU] and #ALLY.parts[SHIPU] == 5,
      "a ship bought: its 5 objects kept as SV_Spawn makes them (ALLY.buy names the unit)")
-- a defence built at the STORE (sv_shop.lua: its spawn names the unit now; solo, no co-op wrapper to name it)
local DEFU = CFG.shop.items.Airfield.defences.aa.units[1]
local gun = obj("BP_GR002_gepa_CP_C", 250)
local dummy = obj("BP_LiveAIGroundDummy_C", 600)
spawnParts[DEFU] = { gun, dummy }
local okB, msgB = shopBuildFor(nil, "AAGun", 99999, nil, false)
check(okB and ALLY.parts[DEFU] and #ALLY.parts[DEFU] == 2, "an AA gun built at the STORE: its objects kept (spawningUnit named "
      .. "by sv_shop.lua's spawn: " .. tostring(msgB) .. ")")
check(spawningUnit == nil, "... spawningUnit back to nil after it")
local n0 = nameReads
ALLY.tick(100)
check(ALLY.parts[SHIPU][1].name == hull.full and ALLY.parts[DEFU][1].name == gun.full, "the tick after: each kept object's name read once")
check(R.defUp and R.defUp[DEFU] == true, "the AA gun counted up")
local w0, from = #walked, #logs + 1
ALLY.repairAll()
check(walksSince(w0) == 0, "the round clear's repair: no walk over every object (" .. walksSince(w0) .. "; 7 before, ~41 ms each late in her run)")
check(hull.HealthInternal == 600 and mk15.HealthInternal == 600 and mk45.HealthInternal == 600 and mk41.HealthInternal == 600,
      "the ship's hull and Mk 15 / Mk 41 / Mk 45 healed to full")
check(art.HealthInternal == 100, "... its artillery mount left as it always was (not one of the classes repaired)")
check(gun.HealthInternal == 600 and dummy.HealthInternal == 600, "the AA gun healed; its dummy (no defence class) left alone")
check(has(line("allies: repaired between rounds: 0 aircraft, 3 ship parts, 1 airfield defences", from), "defences")
      and not has(line("allies: repaired between rounds", from), "walk left"), "logged: 3 ship parts, 1 defence, no walk left")
-- hard rule 59: an address now another object's is never healed
mk15.HealthInternal = 200
local imp = { full = "BP_OP0018_uavc_CP_C " .. lvl .. "BP_OP0018_uavc_CP_C_77", addr = mk15.addr, HealthInternal = 100, MaxHealth = 60 }
local kept = ALLY.parts[SHIPU][2].obj
ALLY.parts[SHIPU][2].obj = imp                    -- (the kept handle now reads another object at that address)
byAddr[mk15.addr] = imp
ALLY.repairAll()
check(imp.HealthInternal == 100, "an object freed and its address another's (an enemy drone): not healed (hard rule 59)")
ALLY.parts[SHIPU][2].obj, byAddr[mk15.addr] = kept, mk15
-- a ship whose objects weren't kept (a spawn nobody named): walked for, one class a tick, from the next tick
local SHIP2 = CFG.allies.ships.Aegis.units[2]
if SHIP2 then
    R.up[SHIP2] = { kind = "ship", key = "Aegis", at = 100 }
    alive[SHIP2] = 1
    local h2 = obj("BP_VE002_aegs_CP_C", 300)
    objects = { BP_VE002_aegs_CP_C = { h2 } }
    w0, from = #walked, #logs + 1
    ALLY.repairAll()
    check(walksSince(w0) == 0 and R.repairWalk and has(line("allies: repaired between rounds", from), "a walk left for the ships " .. SHIP2),
          "a ship with none of its objects kept: no walk in the clear's tick, one left for it (logged)")
    local perTick = {}
    for k = 1, 5 do local wk = #walked; ALLY.tick(100 + k * 0.25); perTick[k] = walksSince(wk) end
    check(perTick[1] == 1 and perTick[2] == 1 and perTick[3] == 1 and perTick[4] == 1 and perTick[5] == 0 and R.repairWalk == nil,
          "... the walk one class a tick: 4 ticks for the ships' 4 classes, then done")
    check(h2.HealthInternal == 600 and has(line("allies: the repair's walk for the ships " .. SHIP2, from), "1 more repaired"),
          "... the unkept ship's hull healed by it, logged")
    R.up[SHIP2], alive[SHIP2], objects = nil, nil, {}
else
    check(false, "a second Aegis unit to test with")
end
-- the STORE's airfield repair: a defence up with none kept is walked for at once, as before
local DEFU2 = CFG.shop.items.Airfield.defences.aa.units[2]
alive[DEFU2] = 1
ALLY.forgetAlive(DEFU2)                           -- (as the STORE does at a build)
local gun2 = obj("BP_GR002_gepa_CP_C", 120)
objects = { BP_GR002_gepa_CP_C = { gun, gun2 } }
ALLY.tick(102)                                    -- (counted up: R.defUp)
gun.HealthInternal = 300
w0, from = #walked, #logs + 1
local nRep = ALLY.repairDefences()
check(nRep == 2 and gun2.HealthInternal == 600 and walksSince(w0) == 3 and has(line("allies: the repair walked for the defences", from), DEFU2),
      "the STORE's airfield repair with a defence's objects not kept: walked for at once, as before (" .. tostring(nRep) .. ", logged)")
alive[DEFU2], objects = nil, {}
ALLY.tick(108)
-- the defences' health from the kept objects: no walk
print("the defences' actors from their kept objects (the re-find's walks)")
R.defActors, R.defWalk, R.defActorsAt = nil, nil, nil
R.checkAt = 0
w0 = #walked
ALLY.tick(110)
check(walksSince(w0) == 0 and R.defActors and #R.defActors == 1 and R.defActors[1] == gun and R.defWalk == nil,
      "found from the kept objects: the AA gun, no walk (3 walks before, 41-48 ms each late in her run)")
check(R.defHp == 100 and has(line("allies: the airfield defences' actors from their objects kept at their spawn: 1 for 1 up"), "no walk"),
      "its health read (100%), logged once")
-- ALLY.forgetActors (a co-op joiner's teardown, the level going): the kept objects dropped
ALLY.forgetActors()
check(next(ALLY.parts) == nil, "ALLY.forgetActors: the objects kept at their spawn dropped too")
R.checkAt = 0
w0 = #walked
ALLY.tick(112)
check(walksSince(w0) == 1 and R.defWalk ~= nil, "... the defences' actors then walked for as before (one class a tick)")

---------------------------------------------------------------------------------------------------- lag-5: ESM fields
print("lag-5: VOID WATCHER's ESM fields")
alive = {}
local AW = CFG.allies.awacs
ALLY.forgetActors()
R = ALLY.state()
R.up = {}
R.esmFields = {}
local now = 500
D.now = now
local fields = {}
for i = 1, 40 do                                  -- 40 old fields (each launch a new object in her run), set long ago
    local f = obj("BP_wp_esm_MS28_C", 1, { bHidden = true, EffectRangeMeter = AW.esm.range_m, SupportEffectRangeMeter = AW.esm.range_m,
                                           LifeTime = AW.esm.life_s })
    fields[i] = f
    R.esmFields[f.addr] = { obj = f, name = f.full, shown = false, at = now - 200 - i }
end
local newF = obj("BP_wp_esm_MS28_C", 1, { bHidden = false, EffectRangeMeter = 3200, SupportEffectRangeMeter = 3200, LifeTime = 10000 })
ALLY.esmNew = { newF }
ALLY.tick(now)
check(newF.EffectRangeMeter == AW.esm.range_m and R.esmFields[newF.addr] and R.esmFields[newF.addr].at == now,
      "a new field: set to " .. AW.esm.range_m .. " m, kept with its time")
local ticks, worstChain, worstNames = 0, 0, 0
for k = 1, 12 do                                  -- 3 s of ticks (not airborne here, but a field set just now)
    local c0, n1 = chainAsks, nameReads
    D.now = now + k * 0.25
    ALLY.tick(D.now)
    ticks = ticks + 1
    worstChain = math.max(worstChain, chainAsks - c0)
    worstNames = math.max(worstNames, nameReads - n1)
end
check(worstChain <= 6, "41 fields: at most " .. worstChain .. " liveAddr asks a tick (the new one, a slice of the old; 41 + 41 "
      .. "names' before, every tick)")
check(worstNames == 0, "no field's name read in a tick where nothing's set again (" .. worstNames .. ")")
local visited = R.esmVisits or 0
check(visited >= 41, "... every field visited within ESM_SWEEP_S (3 s): " .. visited .. " visits")
-- an old one launched again: found by the sweep within 3 s, its name checked first, set
local f7 = fields[7]
f7.bHidden, f7.EffectRangeMeter, f7.LifeTime = false, 3200, 10000
local fromE = #logs + 1
for k = 13, 25 do D.now = now + k * 0.25; ALLY.tick(D.now) end
check(f7.EffectRangeMeter == AW.esm.range_m and f7.LifeTime == AW.esm.life_s and has(line("launched again", fromE), "BP_wp_esm_MS28_C_"),
      "an old field launched again: found by the sweep within 3 s, set again, logged")
-- an old field's address another object's now: never set (its name compared first)
local f9 = fields[9]
local intruder = { full = "BP_wp_esm_player_C " .. lvl .. "BP_wp_esm_player_C_5", addr = f9.addr, bHidden = false,
                   EffectRangeMeter = 3200, LifeTime = 10000 }
R.esmFields[f9.addr].obj = intruder
byAddr[f9.addr] = intruder
for k = 26, 40 do D.now = now + k * 0.25; ALLY.tick(D.now) end
check(intruder.EffectRangeMeter == 3200 and R.esmFields[f9.addr] == nil, "an address another object's now: never set, dropped (hard rule 59)")
-- nothing while VOID WATCHER isn't airborne here and no field was set in ESM_ACTIVE_S
R.esmSetAt = D.now - 200
local c0 = chainAsks
for k = 41, 60 do D.now = now + k * 0.25; ALLY.tick(D.now) end
check(chainAsks == c0, "VOID WATCHER not airborne, no field set in 90 s: no field read at all (" .. (chainAsks - c0) .. " asks)")
-- airborne here: the sweep goes on
R.up[AW.unit] = { kind = "air", ally = "awacs", at = D.now - 300 }
FLAGS.SV_AwacsAir = 1
c0 = chainAsks
for k = 61, 64 do D.now = now + k * 0.25; ALLY.tick(D.now) end
check(chainAsks > c0, "airborne: swept again (" .. (chainAsks - c0) .. " asks in 4 ticks)")
R.up[AW.unit], FLAGS.SV_AwacsAir = nil, nil
-- the newest ESM_KEEP kept
local q = {}
for i = 1, 40 do q[i] = obj("BP_wp_esm_MS28_C", 1, { bHidden = false, EffectRangeMeter = 3200, LifeTime = 10000 }) end
ALLY.esmNew = q
D.now = D.now + 0.25
ALLY.tick(D.now)
local n = 0
for _ in pairs(R.esmFields) do n = n + 1 end
check(n <= 33 and has(line("allies: VOID WATCHER 1's ESM fields: the newest 32 kept"), "let go"), "the list bounded: " .. n
      .. " fields after 40 more (32 kept, logged once)")
svFlags = rawFlags

print(fails == 0 and "lag test: all passed" or ("lag test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
