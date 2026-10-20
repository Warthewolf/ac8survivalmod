-- AC8 Survival Mode - runtime (UE4SS Lua half; the native half is dlls\main.dll)
-- Milestone 1:
--   * adds Survival's mission row and main-menu row to the game's tables at run time, copied from Survival's own
--     tables (DT_SV_MissionRows / DT_SV_MenuRows), so no stock or other-mod table file is overridden
--   * the main-menu entry opens the game's difficulty page; dlls\main.dll then starts Survival's mission
--   * dev shortcut: Ctrl+F8 on the main menu opens PL_SurvivalMode directly
-- Milestone 2:
--   * rounds: random flights, aircraft and bearings each round, spawned through dlls\main.dll's SV_* functions

local VERSION = "0.6.0"
local LEVEL   = "/Game/Mods/SurvivalMode/Maps/PL_SurvivalMode"
local TAG     = "[AC8SurvivalMode] "
local ROW     = "SurvivalMode"

-- { our table, the game's table, the row ours goes just above (SURVIVAL MODE sits above QUIT GAME) }
local TABLES = {
    { mine = "/Game/Mods/SurvivalMode/Data/DT_SV_MissionRows.DT_SV_MissionRows",
      game = "/Game/Datatables/Information/DT_LiveMissionTable.DT_LiveMissionTable" },
    { mine = "/Game/Mods/SurvivalMode/Data/DT_SV_MenuRows.DT_SV_MenuRows",
      game = "/Game/Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands.DT_LiveMenuMainTopCommands",
      above = "QuitGame" },
}

local function log(s) print(TAG .. s .. "\n") end

local function valid(o)
    local ok, v = pcall(function() return o ~= nil and o:IsValid() end)
    return ok and v
end

local function nameOf(o)
    local ok, s = pcall(function() return o:GetFullName() end)
    return ok and s or "?"
end

-- calls a data table method; false when this UE4SS build cannot do it
local function dtCall(dt, method, ...)
    local args = { ... }
    local ok, r = pcall(function() return dt[method](dt, table.unpack(args)) end)
    if ok then return true, r end
    return false, r
end

-- Loads a package of ours by object path ("/Game/...Pkg.Obj"). UE4SS's LoadAsset only finds assets listed in the
-- game's asset registry, which never lists a mod's new packages, so the engine's own soft-reference loader is used:
-- MakeSoftObjectPath -> Conv_SoftObjPathToSoftObjRef -> LoadAsset_Blocking (game thread only).
-- Returns the object, or nil and the reason.
local function loadObject(path)
    local o = StaticFindObject(path)
    if valid(o) then return o end
    local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if not valid(ks) then return nil, "KismetSystemLibrary not found" end
    local why = {}
    local ok, r = pcall(function()
        local sp = ks:MakeSoftObjectPath(path)
        local ref = ks:Conv_SoftObjPathToSoftObjRef(sp)
        return ks:LoadAsset_Blocking(ref)
    end)
    if ok and valid(r) then return r end
    why[#why + 1] = "LoadAsset_Blocking: " .. (ok and "returned nothing" or tostring(r))
    o = StaticFindObject(path)
    if valid(o) then return o end
    if type(LoadAsset) == "function" then
        local okL, rL = pcall(LoadAsset, path)
        if okL and valid(rL) then return rL end
        why[#why + 1] = "LoadAsset: " .. (okL and "returned nothing" or tostring(rL))
        o = StaticFindObject(path)
        if valid(o) then return o end
    end
    return nil, table.concat(why, "; ")
end

---------------------------------------------------------------------------------------------------- rows
-- The main menu reads DT_LiveMenuMainTopCommands through a soft reference (DA_LiveMenuMainTopPageSettings), so the
-- game loads the table when the menu page is built and may unload it afterwards; a reloaded table comes fresh from
-- disk without our row (test 2: the row went in after the list was built and never showed). So: load both tables
-- ourselves at start, add the rows at once, pin the tables in GameInstance.ReferencedObjects so they stay loaded,
-- and keep watching: a new table object, or a missing row, gets the row again.

-- Position of each row name, in the order the menu lists them.
local function rowOrder(dt)
    local pos = {}
    local ok, names = dtCall(dt, "GetRowNames")
    if not ok or names == nil then return pos end
    pcall(function()
        for i, n in ipairs(names) do
            local okS, s = pcall(function() return n:ToString() end)
            pos[okS and s or tostring(n)] = i
        end
    end)
    return pos
end

-- Puts our row just above `last` (Quit Game). A removed row's slot is reused by the next row added, so moving one
-- row alone puts it straight back where it was: both rows are copied, removed and added again, and the order is
-- checked; if the slots were refilled the other way round, it is done once more in the opposite order.
local function placeAbove(dt, last)
    local function inOrder() local p = rowOrder(dt); return p[ROW] and p[last] and p[ROW] < p[last] end
    if inOrder() then return true end
    for _, ourFirst in ipairs({ true, false }) do
        local _, rowA = dtCall(dt, "FindRow", ROW)
        local _, rowB = dtCall(dt, "FindRow", last)
        if rowA == nil or rowB == nil then return false end
        local tA, tB = ROW .. "_SVtmp", last .. "_SVtmp"
        dtCall(dt, "AddRow", tA, rowA); dtCall(dt, "AddRow", tB, rowB)
        local _, cA = dtCall(dt, "FindRow", tA)
        local _, cB = dtCall(dt, "FindRow", tB)
        if cA == nil or cB == nil then dtCall(dt, "RemoveRow", tA); dtCall(dt, "RemoveRow", tB); return false end
        dtCall(dt, "RemoveRow", ROW); dtCall(dt, "RemoveRow", last)
        if ourFirst then dtCall(dt, "AddRow", ROW, cA); dtCall(dt, "AddRow", last, cB)
        else             dtCall(dt, "AddRow", last, cB); dtCall(dt, "AddRow", ROW, cA) end
        dtCall(dt, "RemoveRow", tA); dtCall(dt, "RemoveRow", tB)
        local _, okA = dtCall(dt, "FindRow", ROW)
        local _, okB = dtCall(dt, "FindRow", last)
        if okA == nil or okB == nil then
            log("rows: reordering lost a row (" .. ROW .. " " .. tostring(okA ~= nil) .. ", " .. last .. " " .. tostring(okB ~= nil) .. ")")
            return false
        end
        if inOrder() then return true end
    end
    return false
end

local function addrOf(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

local function hex(a) return a and string.format("%X", a) or "?" end

local function rowNames(dt)
    local ok, names = dtCall(dt, "GetRowNames")
    if not ok or names == nil then return "?" end
    local out = {}
    pcall(function()
        for _, n in ipairs(names) do
            local okS, str = pcall(function() return n:ToString() end)
            out[#out + 1] = okS and str or tostring(n)
        end
    end)
    return table.concat(out, ", ")
end

local function gameInstance()
    for _, cls in ipairs({ "BP_LiveGameInstance_C", "LiveGameInstance", "GameInstance" }) do
        local gi = FindFirstOf(cls)
        if valid(gi) then return gi end
    end
    return nil
end

-- Keeps `o` loaded: GameInstance.ReferencedObjects is the engine's list for exactly that.
local pinned = {}
local function pin(o, what)
    local a = addrOf(o)
    if not a then return false end
    if pinned[a] ~= nil then return pinned[a] end
    local gi = gameInstance()
    if not gi then return false end                   -- not created yet: try again next pass
    local sizes = ""
    local ok, err = pcall(function()
        local arr = gi.ReferencedObjects
        local n0, m0 = arr:GetArrayNum(), arr:GetArrayMax()
        arr[#arr + 1] = o
        sizes = string.format(" [ReferencedObjects num %d -> %d, max %d -> %d]", n0, arr:GetArrayNum(), m0, arr:GetArrayMax())
    end)
    pinned[a] = ok
    log("rows: " .. what .. (ok and " pinned (kept loaded)" or (" could not be pinned (" .. tostring(err) .. ")")) .. sizes)
    return ok
end

-- Survival's container (SurvivalMode_P) is mounted: its own row table loads. Checked before anything uses
-- Survival's packages, because opening a level or row that isn't there takes the game down.
local MISSING_TRIES = 20           -- attempts (250 ms apart) before deciding Survival's tables can't be loaded
local containerState = nil         -- nil = not known yet, true / false once known
local missingTries = 0
local lastLoadError = nil

local function containerMounted()
    if containerState ~= nil then return containerState end
    if valid(loadObject(TABLES[1].mine)) then containerState = true end
    return containerState
end

local function containerMissing()
    containerState = false
    log("Survival Mode's tables could not be loaded from SurvivalMode_P (" .. tostring(lastLoadError) ..
        "), so Survival Mode is off: no menu entry and Ctrl+F8 does nothing. If AC8IoStoreLoader.log shows " ..
        "SurvivalMode_P mounted, please send UE4SS.log.")
end

-- Our source row for a table (from DT_SV_*), or nil + the reason.
local function sourceRow(t)
    local mine, why = loadObject(t.mine)
    if not mine then return nil, why end
    pin(mine, nameOf(mine))
    local okR, r = dtCall(mine, "FindRow", ROW)
    if r ~= nil then return r end
    return nil, "loaded " .. nameOf(mine) .. ", but FindRow('" .. ROW .. "') gave " ..
                (okR and "nothing" or tostring(r)) .. "; rows: " .. rowNames(mine)
end

local seen = {}                    -- per table: address of the table object last seen ("missing" if it can't load)
local ready = {}                   -- per table: our row is in

-- One pass over both tables; returns false to stop watching for good.
local function watchRows()
    if containerState == false then return false end
    for i, t in ipairs(TABLES) do
        -- the menu row only goes in once the mission row is in: an entry must never start a missing mission
        if i > 1 and not ready[1] then return true end
        local game = StaticFindObject(t.game)
        if not valid(game) then
            local why
            game, why = loadObject(t.game)
            if not game then
                if seen[i] ~= "missing" then log("rows: could not load " .. t.game .. " (" .. tostring(why) .. ")") end
                seen[i] = "missing"
                return true
            end
        end
        local a = addrOf(game)
        if seen[i] ~= a then
            log("rows: " .. nameOf(game) .. " object at " .. hex(a) ..
                ((seen[i] and seen[i] ~= "missing") and " (a new copy: the game reloaded it)" or ""))
            seen[i] = a
            ready[i] = false
        end
        pin(game, nameOf(game))
        local okF, have = dtCall(game, "FindRow", ROW)
        if not okF then
            log("rows: this UE4SS build cannot read data tables (" .. tostring(have) .. "); the menu is left as it is")
            return false
        end
        if have == nil then
            local src, why = sourceRow(t)
            if src == nil then
                lastLoadError = why
                missingTries = missingTries + 1
                if missingTries >= MISSING_TRIES then containerMissing(); return false end
                return true
            end
            containerState = true
            local okA, err = dtCall(game, "AddRow", ROW, src)
            local _, now = dtCall(game, "FindRow", ROW)
            if okA and now ~= nil then
                local placed = t.above and placeAbove(game, t.above)
                log("rows: added '" .. ROW .. "' to " .. nameOf(game) ..
                    (t.above and (placed and (" (above " .. t.above .. ")") or (" (could not place it above " .. t.above .. ")")) or ""))
                log("rows: " .. nameOf(game) .. " now has: " .. rowNames(game))
                ready[i] = true
            else
                log("rows: could not add '" .. ROW .. "' to " .. t.game .. " (" .. tostring(err) .. ")")
                return false
            end
        elseif not ready[i] then
            ready[i] = true
            containerState = true
            local placed = t.above and placeAbove(game, t.above)
            log("rows: '" .. ROW .. "' is in " .. nameOf(game) ..
                (t.above and (placed and (" (above " .. t.above .. ")") or (" (could not place it above " .. t.above .. ")")) or ""))
        end
    end
    return true
end

---------------------------------------------------------------------------------------------------- round diagnostics
-- Milestone 2 round probe: logs every AI aircraft created in Survival's level (with where it appeared), the number
-- still alive when it changes, Survival's SV_* flags when they change, and the game's difficulty at mission start.
local planes = {}                  -- created AI aircraft in this level: { obj, name }
local pending = {}                 -- AI aircraft just created, logged on a later tick (position is set by then)
local AIRFIELD = { X = 1609639.0, Y = -436414.0 }   -- Comona Airport runway (cm), the spawn anchor
local lastAlive, lastFlags = nil, nil

local function inSurvival(o) return nameOf(o):find("PL_SurvivalMode", 1, true) ~= nil end

-- Callbacks only record: all logging runs in the one game-thread tick below.
pcall(NotifyOnNewObject, "/Script/Live.LiveAIPlane", function(o) pending[#pending + 1] = { obj = o, age = 0 } end)

local function logPlane(o)
    if not valid(o) or not inSurvival(o) then return end
    local n = nameOf(o)
    local short = n:match("([^%.:]+)$") or n
    local wing = n:find("Wingman", 1, true) and " (wingman)" or ""
    planes[#planes + 1] = { obj = o, name = short }
    local where = ""
    pcall(function()
        local l = o:K2_GetActorLocation()
        local dx, dy = l.X - AIRFIELD.X, l.Y - AIRFIELD.Y
        where = string.format(" at (%.1f, %.1f) km, alt %.1f km, %.1f km from the airfield",
            l.X / 100000, l.Y / 100000, l.Z / 100000, math.sqrt(dx * dx + dy * dy) / 100000)
    end)
    log("round probe: AI aircraft created #" .. #planes .. ": " .. short .. wing .. where)
end

-- Survival's int flags (SV_*), read from the event containers' FlagData.IntegerFiled. The per-flight SV_Up_NN flags
-- (set while a flight is up, for the chase) are shown as one count.
local function flagLine()
    local parts, up = {}, 0
    local cs = FindAllOf("LiveEventContainer")
    if not cs then return nil end
    for _, c in ipairs(cs) do
        if valid(c) then
            pcall(function()
                c.FlagData.IntegerFiled:ForEach(function(k, v)
                    local okK, name = pcall(function() return k:get():ToString() end)
                    if okK and name:sub(1, 6) == "SV_Up_" then
                        local okV, val = pcall(function() return v:get().Value end)
                        if okV and type(val) == "number" and val >= 1 then up = up + 1 end
                    elseif okK and name:sub(1, 3) == "SV_" then
                        local okV, val = pcall(function() return v:get().Value end)
                        parts[#parts + 1] = name .. "=" .. (okV and tostring(val) or "?")
                    end
                end)
            end)
        end
    end
    if #parts == 0 then return nil end
    table.sort(parts)
    return table.concat(parts, " ") .. " flights up (SV_Up_*)=" .. up
end

-- The game's current difficulty (LiveDifficultyManager.CurrentDifficulty: 1 Casual .. 5 Ace).
local DIFFICULTY = { [0] = "None", "Casual", "Easy", "Normal", "Hard", "Ace", "FreeFlight" }
local function logDifficulty(when)
    local dm = FindFirstOf("LiveDifficultyManager")
    local ok, d = pcall(function() return dm.CurrentDifficulty end)
    log("difficulty " .. when .. ": " .. ((ok and type(d) == "number") and (DIFFICULTY[d] or tostring(d)) or "unknown"))
end

local levelTick = nil              -- tick count when Survival's level was loaded
pcall(NotifyOnNewObject, "/Script/Engine.World", function(w)
    if nameOf(w):find("PL_SurvivalMode", 1, true) then levelTick = -1 end      -- picked up by the next tick
end)

---------------------------------------------------------------------------------------------------- rounds
-- Survival's own spawner. The game never spawns a world-data unit again while its shot-down flight is still on the
-- phase's unit list (tools/re/SPAWN_SYSTEM.md), so rounds don't use its reinforcement events: dlls\main.dll
-- (runtime 0.6.0) registers these globals when this script starts, and the rounds below call them:
--   SV_Spawn(unit, x, y, z, yaw)   spawns the world-data unit there (cm, degrees); a shot-down flight is recycled first
--   SV_SetAircraft(unit, npc)      sets the aircraft (NPC table row) of every plane in the flight
--   SV_UnitAlive(unit)             planes still alive in the flight's current spawn (-7: not up)
--   SV_LogUnits(why)               writes the game's spawned-unit list to AC8SurvivalMode.log
-- The event package gives each flight its orders when it appears (air-only search, engage the player) and counts
-- SV_Alive / SV_Kills for this log. Must run on the game thread (the one tick below).
local CFG = {
    first_round_delay_s = 15,
    intermission_s      = 45,
    spawn_gap_s         = 3,                    -- between two flights of a round
    flights_round1      = 2,
    flights_per_round   = 1,                    -- added every round
    max_flights         = 8,                    -- flights in one round
    distance_km         = { 18, 25 },           -- from the airfield, random bearing
    altitude_m          = { 2000, 4500 },
    aircraft            = { "f16c_common", "f18e_common", "f15e_common", "f14d_common", "m21b_common",
                            "m29a_common", "m31b_common", "su33_common", "su34_common" },   -- NPC rows in Mission 22's table
    pool                = {},                   -- Mission 22's 24 "kokatu" flights (tools/survival_events.py POOL)
}
for n = 1, 8 do for k = 0, 2 do CFG.pool[#CFG.pool + 1] = string.format("ERA_Unit_%02d_Dep_Air%d", n, k) end end
do  -- optional overrides: Scripts/survival_config.lua returning a table with any of the keys above
    local ok, user = pcall(require, "survival_config")
    if ok and type(user) == "table" then
        for k, v in pairs(user) do CFG[k] = v end
        log("config: survival_config.lua loaded")
    end
end
math.randomseed(os.time())

local ZONE = { X = -707336.0, Y = -261895.0, HALF = 3700000.0 }   -- Mission 22's combat zone (80 km), 3 km margin
local SV_ERR = { [0] = "the game spawned nothing", [-1] = "not in Survival's level", [-2] = "no such unit or aircraft",
                 [-3] = "its last flight is still up", [-4] = "bad arguments", [-5] = "game functions not found" }
local D = nil                      -- the run in progress: { round, state, at, now, queue, up }

local function nativeReady()
    return type(SV_Spawn) == "function" and type(SV_UnitAlive) == "function" and type(SV_SetAircraft) == "function"
end

-- A random point distance_km from the airfield, inside the combat zone; returns x, y (cm), distance (km), bearing.
local function spawnPoint()
    local lo, hi = CFG.distance_km[1], CFG.distance_km[2]
    for _ = 1, 30 do
        local b, d = math.random() * 360, lo + math.random() * (hi - lo)
        local x = AIRFIELD.X + d * 100000 * math.cos(math.rad(b))
        local y = AIRFIELD.Y + d * 100000 * math.sin(math.rad(b))
        if math.abs(x - ZONE.X) < ZONE.HALF and math.abs(y - ZONE.Y) < ZONE.HALF then return x, y, d, b end
    end
    return AIRFIELD.X, AIRFIELD.Y + lo * 100000, lo, 90
end

local function spawnFlight(unit)
    local ac = CFG.aircraft[math.random(#CFG.aircraft)]
    local set = SV_SetAircraft(unit, ac)
    local x, y, dist, bearing = spawnPoint()
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local r = SV_Spawn(unit, x, y, alt * 100, (bearing + 180) % 360)          -- facing the airfield
    log(string.format("round %d: %s as %s (%s set), %.0f km out at bearing %.0f, %.1f km up: %s", D.round, unit, ac,
        tostring(set), dist, bearing, alt / 1000, r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r > 0 then D.up[unit] = true end
    return r
end

local function startRound()
    D.round = D.round + 1
    local free = {}
    for _, u in ipairs(CFG.pool) do if not D.up[u] then free[#free + 1] = u end end
    for i = #free, 2, -1 do local j = math.random(i); free[i], free[j] = free[j], free[i] end
    local want = math.min(CFG.flights_round1 + (D.round - 1) * CFG.flights_per_round, CFG.max_flights, #free)
    D.queue = {}
    for i = 1, want do D.queue[i] = free[i] end
    log(string.format("round %d: %d flights", D.round, want))
    if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " start") end
    D.state, D.at, D.lastAlive = "spawning", D.now, nil
end

local function roundsTick(now)
    if not D then return end
    D.now = now
    if not nativeReady() then
        if not D.warned then log("rounds: the native spawner (dlls\\main.dll 0.6.0) did not register SV_Spawn: no enemies"); D.warned = true end
        return
    end
    if D.state == "wait" then
        if now >= D.at then startRound() end
    elseif D.state == "spawning" then
        if now < D.at then return end
        local u = table.remove(D.queue, 1)
        if u and spawnFlight(u) == -1 then log("rounds: left Survival's level, rounds stopped"); D = nil; return end
        D.at = now + CFG.spawn_gap_s
        if #D.queue == 0 then D.state = "fighting" end
    elseif D.state == "fighting" then
        if now < D.at then return end
        D.at = now + 1
        local alive, flights = 0, 0
        for u in pairs(D.up) do
            local n = SV_UnitAlive(u)
            if n > 0 then alive, flights = alive + n, flights + 1 else D.up[u] = nil end
        end
        if alive ~= D.lastAlive then log(string.format("round %d: %d aircraft in %d flights left", D.round, alive, flights)); D.lastAlive = alive end
        if flights == 0 then
            log(string.format("round %d clear; round %d in %d s", D.round, D.round + 1, CFG.intermission_s))
            if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " clear") end
            D.state, D.at = "wait", now + CFG.intermission_s
        end
    end
end

local function probeTick(tick)
    if levelTick == -1 then
        levelTick = tick
        log("level loaded: PL_SurvivalMode")
        planes, lastAlive, lastFlags = {}, nil, nil
        if type(SV_Reset) == "function" then SV_Reset() end
        log("rounds: native spawner " .. (type(SV_Version) == "function" and ("runtime " .. tostring(SV_Version())) or "missing") ..
            "; round 1 in " .. CFG.first_round_delay_s .. " s")
        D = { round = 0, state = "wait", at = tick / 4 + CFG.first_round_delay_s, now = tick / 4, queue = {}, up = {} }
    end
    local okR, errR = pcall(roundsTick, tick / 4)
    if not okR then log("rounds: error " .. tostring(errR)) end
    if levelTick then
        if tick - levelTick == 8 then logDifficulty("at mission start") end
        if tick - levelTick == 48 then logDifficulty("10 s into the mission") end
    end
    local keep = {}
    for _, p in ipairs(pending) do
        p.age = p.age + 1
        if p.age >= 2 then pcall(logPlane, p.obj) else keep[#keep + 1] = p end
    end
    pending = keep
    if tick % 8 ~= 0 or not levelTick then return end                -- the rest every 2 s, in Survival only
    local fl = flagLine()
    if fl and fl ~= lastFlags then log("round probe: flags " .. fl); lastFlags = fl end
    local alive = 0
    for _, p in ipairs(planes) do
        if valid(p.obj) then
            local ok, h = pcall(function() return p.obj.HealthInternal end)
            if not ok or type(h) ~= "number" or h > 0 then alive = alive + 1 end
        end
    end
    if alive ~= lastAlive and #planes > 0 then
        log("round probe: AI aircraft alive " .. alive .. " (created so far " .. #planes .. ")")
        lastAlive = alive
    end
end

---------------------------------------------------------------------------------------------------- the one tick
-- Everything runs from this single game-thread pass every 250 ms. UE4SS 3.0.1 crashed with heap corruption inside its
-- Lua (test M2-8) while this script ran many ExecuteWithDelay timers (one per menu widget) next to two loops; one
-- loop that queues one game-thread job at a time keeps all Lua work in one place.
local tick, rowsStopped, queued = 0, false, false
LoopAsync(250, function()
    if queued then return false end
    queued = true
    ExecuteInGameThread(function()
        tick = tick + 1
        if not rowsStopped then
            local ok, r = pcall(watchRows)
            if not ok then log("rows: error " .. tostring(r)) end
            if ok and r == false then rowsStopped = true end
        end
        local ok, err = pcall(probeTick, tick)
        if not ok then log("round probe: error " .. tostring(err)) end
        queued = false
    end)
    return false
end)

---------------------------------------------------------------------------------------------------- dev shortcut
-- On-screen note. PrintString is stripped from some shipping builds, so the log line is the one to rely on.
local function notify(msg)
    log(msg)
    local pc = FindFirstOf("PlayerController")
    local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if valid(pc) and valid(ks) then
        pcall(function() ks:PrintString(pc, TAG .. msg, true, false, { R = 1, G = 0.4, B = 0.1, A = 1 }, 8.0, FName("None")) end)
    end
end

local function openSurvival()
    if not containerMounted() then
        notify("Survival Mode's map is not installed (SurvivalMode_P did not mount), so it was not opened.")
        return
    end
    local pc = FindFirstOf("PlayerController")
    if not valid(pc) then log("launch: no player controller yet; try again on the main menu"); return end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if valid(gs) then
        local ok, err = pcall(function() gs:OpenLevel(pc, FName(LEVEL), true, "") end)
        if ok then log("launch: opening " .. LEVEL); return end
        log("launch: OpenLevel failed (" .. tostring(err) .. "), trying the console command")
    end
    local ks = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if valid(ks) then
        local ok, err = pcall(function() ks:ExecuteConsoleCommand(pc, "open " .. LEVEL, pc) end)
        if ok then log("launch: console 'open " .. LEVEL .. "' sent"); return end
        log("launch: console command failed (" .. tostring(err) .. ")")
    end
end

if type(RegisterKeyBind) == "function" and Key and Key.F8 then
    local mods = (ModifierKey and ModifierKey.CONTROL) and { ModifierKey.CONTROL } or {}
    pcall(RegisterKeyBind, Key.F8, mods, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(openSurvival)
            if not ok then log("launch: error " .. tostring(err)) end
        end)
    end)
end

log("loaded, version " .. VERSION)
