-- AC8 Survival Mode - runtime (UE4SS Lua half; the native half is dlls\main.dll)
-- Milestone 1:
--   * adds Survival's mission row and main-menu row to the game's tables at run time, copied from Survival's own
--     tables (DT_SV_MissionRows / DT_SV_MenuRows), so no stock or other-mod table file is overridden
--   * the main-menu entry opens the game's difficulty page; dlls\main.dll then starts Survival's mission
--   * dev shortcut: Ctrl+F8 on the main menu opens PL_SurvivalMode directly
-- Milestone 2:
--   * rounds: random flights, aircraft and bearings each round, spawned through dlls\main.dll's SV_* functions
--   * round HUD: Survival's own HUD layer, built at run time (round, countdown to the next round, callouts)
--   * rounds run on the game clock, so the countdown and the rounds stop while the game is paused
--   * ammo cap: missiles, special weapons and flares capped per difficulty preset at spawn (dlls\main.dll SV_SetAmmo); gun unlimited
--   * behaviour probe: own enemy behaviour script, live PilotRank write, kill attribution (logged; CFG.probe)
--   * dev: Ctrl+F9 writes the live HUD's widget tree and on-screen geometry to hud_dump.txt (next to Scripts)

local VERSION = "0.33.0"
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

-- Every line also goes to AC8SurvivalMode\AC8SurvivalMode_lua.log, written through at once: UE4SS.log loses its last
-- lines when the game crashes (a friend's test of 2026-10-22: it stopped 40 s before the crash on sortie).
local log
do
    local LOG_FILE = nil
    local dir = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "..\\"
    local ok, f = pcall(io.open, dir .. "AC8SurvivalMode_lua.log", "w")
    if ok and f then LOG_FILE = f; pcall(function() f:setvbuf("no") end) end
    function log(s)
        print(TAG .. s .. "\n")
        if LOG_FILE then pcall(function() LOG_FILE:write(os.date("%H:%M:%S ") .. s .. "\n") end) end
    end
end

local function valid(o)
    local ok, v = pcall(function() return o ~= nil and o:IsValid() end)
    return ok and v
end

local function nameOf(o)
    local ok, s = pcall(function() return o:GetFullName() end)
    return ok and s or "?"
end

-- A widget the game made at run time (they live under /Engine/Transient). FindAllOf on a widget blueprint's class
-- also returns the copies stored inside other blueprints' WidgetTrees ("..._C:WidgetTree.X"), which are never on
-- screen (test of 2026-10-22: the landing menu's ammo panel and the TIME row were first found that way).
local function liveWidget(w)
    return valid(w) and nameOf(w):find("/Engine/Transient", 1, true) ~= nil
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

-- The game's InformationManager_ (GameInstance +0x878, LiveInformationManager) keeps its own maps built from the data
-- tables: MissionDataMap_ (MissionID -> mission data) and LevelDataMap_ (level id -> level data). The hangar and its
-- wingman panel look Survival's mission up there, not in DT_LiveMissionTable. When the manager built them before
-- Survival's row was in, 9101 was missing: a black hangar (no lighting sublevels) and a crash at sortie in the wingman
-- panel (an empty list read at AceCombat8.exe+0x79a4153; friend's test and user's test of 2026-10-22, a race at start).
-- So once the row is in, 9101 / level 70 go into those maps too (Survival's row as the value; only where Mission 22's
-- key is there too, so the map is the kind that holds rows), checked again every few seconds in case they're built anew.
local infoMapsTick
do
    local IM = { said = {}, gave = {} }
    local MAPS = { { field = "MissionDataMap_", stock = 22, ours = 9101 },     -- tools/build_survival.py MISSION_ID
                   { field = "LevelDataMap_",   stock = 40, ours = 70 } }      -- LEVEL_ID (Mission 22: 40)
    local function say(key, text) if IM.said[key] ~= text then IM.said[key] = text; log("info maps: " .. text) end end
    local function has(map, key)
        local ok, v = pcall(function() return map:Contains(key) end)
        if ok and type(v) == "boolean" then return v end
        local found = false                                  -- no Contains in this UE4SS: walk it
        pcall(function() map:ForEach(function(k) local okK, kv = pcall(function() return k:get() end)
            if okK and kv == key then found = true end end) end)
        return found
    end
    function infoMapsTick()
        if not ready[1] then return end                      -- Survival's mission row first
        local gi = gameInstance()
        local im
        pcall(function() im = gi.InformationManager_ end)
        if not valid(im) then say("im", "the game's InformationManager_ is not there yet"); return end
        local _, src = pcall(function() return StaticFindObject(TABLES[1].game) end)
        local row = nil
        if valid(src) then local okR, r = dtCall(src, "FindRow", ROW); if okR then row = r end end
        for _, m in ipairs(MAPS) do
            local okM, err = pcall(function()
                local map = im[m.field]
                if has(map, m.ours) then say(m.field, string.format("%s has %d", m.field, m.ours)); return end
                if not has(map, m.stock) then say(m.field, string.format("%s has neither %d nor %d; left alone", m.field, m.ours, m.stock)); return end
                -- Survival's own row only: a copy of Mission 22's value under 9101 would send the sortie to Mission 22's map
                if row == nil then say(m.field, m.field .. " is missing " .. m.ours .. ", and Survival's row can't be read"); return end
                local okA, errA = pcall(function() map:Add(m.ours, row) end)
                local now = has(map, m.ours)
                IM.gave[m.field] = (IM.gave[m.field] or 0) + 1
                say(m.field .. "add", string.format("%s was missing %d (the race at start): added %s%s", m.field, m.ours,
                    now and "and it is in now" or "but it is still not in", okA and "" or (" (" .. tostring(errA) .. ")")))
            end)
            if not okM then say(m.field .. "err", m.field .. ": " .. tostring(err)) end
        end
    end
end

---------------------------------------------------------------------------------------------------- round diagnostics
-- Milestone 2 round probe: logs every AI aircraft created in Survival's level (with where it appeared), the number
-- still alive when it changes, Survival's SV_* flags when they change, and the game's difficulty at mission start.
local planes = {}                  -- created AI aircraft in this level: { obj, name }
local pending = {}                 -- AI aircraft just created, logged on a later tick (position is set by then)
local AIRFIELD = { X = 1609639.0, Y = -436414.0 }   -- Comona Airport runway (cm), the spawn anchor
local lastAlive, lastFlags = nil, nil

local function inSurvival(o) return nameOf(o):find("PL_SurvivalMode", 1, true) ~= nil end

-- Callbacks only record: all logging runs in the one game-thread tick below. A plane made during an SV_Spawn call is
-- tagged with the flight being spawned (spawningUnit, set around the call): GetUnitName() reads back empty (test of
-- 2026-10-22), and the world data's object names don't follow their flights' names.
local spawningUnit = nil
pcall(NotifyOnNewObject, "/Script/Live.LiveAIPlane", function(o) pending[#pending + 1] = { obj = o, age = 0, unit = spawningUnit } end)

-- Comona Defense's shuttle (special rounds): its actor, for its health on the HUD. It may come as a LiveAIPlane
-- (OP0057_sstb); it's then kept out of `planes`, so it never counts, tiers or pays as an enemy.
local SHUTTLE = { obj = nil }
local shuttleHealth            -- (section "special rounds"; the HUD shows it)
-- The Anomaly (section "special rounds"): its field's state, for the HUD and the level reset.
local ANOM = { on = false }

local function logPlane(o, unit)
    if not valid(o) or not inSurvival(o) then return end
    local n = nameOf(o)
    local short = n:match("([^%.:]+)$") or n
    if short:find("_sstb_", 1, true) then
        SHUTTLE.obj = o
        log("special: shuttle actor " .. short .. (unit and (" (" .. unit .. ")") or ""))
        return
    end
    if n:find("Wingman", 1, true) then log("planes: wingman " .. short .. " (not an enemy)"); return end
    local rec = { obj = o, name = short, unit = unit }
    planes[#planes + 1] = rec
    local where = ""
    pcall(function()
        local l = o:K2_GetActorLocation()
        local dx, dy = l.X - AIRFIELD.X, l.Y - AIRFIELD.Y
        where = string.format(" at (%.1f, %.1f) km, alt %.1f km, %.1f km from the airfield",
            l.X / 100000, l.Y / 100000, l.Z / 100000, math.sqrt(dx * dx + dy * dy) / 100000)
    end)
    log("round probe: AI aircraft created #" .. #planes .. ": " .. short .. (unit and (" (" .. unit .. ")") or "") .. where)
end

-- Survival's int flags (SV_*), read from the event containers' FlagData.IntegerFiled. The per-flight SV_Up_NN flags
-- (set while a flight is up) are shown as one count, also returned as the second value.
-- Every SV_* int flag: { name = value }, read at most once every 0.2 s (several callers share one walk), or nil
-- while there is no event container.
-- The event containers are looked up again only when one has gone (a new level) or every 30 s; FindAllOf walks every
-- object in the game, which several times a second was a visible hitch (user, 2026-10-22: "a bit of lag").
local flagCache = { at = -1, t = nil, cs = nil, found = -100 }
local function svFlags()
    local now = os.clock()
    if now - flagCache.at < 0.2 then return flagCache.t end
    local cs = flagCache.cs
    local stale = not cs or now - flagCache.found > 30 or (#cs == 0 and now - flagCache.found > 2)
    for _, c in ipairs(cs or {}) do if not valid(c) then stale = true end end
    if stale then cs, flagCache.found = FindAllOf("LiveEventContainer") or {}, now; flagCache.cs = cs end
    local t = nil
    for _, c in ipairs(cs) do
        if valid(c) then
            t = t or {}
            pcall(function()
                c.FlagData.IntegerFiled:ForEach(function(k, v)
                    local okK, name = pcall(function() return k:get():ToString() end)
                    if okK and name:sub(1, 3) == "SV_" then
                        local okV, val = pcall(function() return v:get().Value end)
                        if okV and type(val) == "number" then t[name] = val end
                    end
                end)
            end)
        end
    end
    flagCache.at, flagCache.t = now, t
    return t
end

local function flagLine()
    local t = svFlags()
    if not t then return nil end
    local parts, up = {}, 0
    for name, val in pairs(t) do
        if name:sub(1, 6) == "SV_Up_" then
            if val >= 1 then up = up + 1 end
        else
            parts[#parts + 1] = name .. "=" .. tostring(val)
        end
    end
    if #parts == 0 then return nil, up end
    table.sort(parts)
    return table.concat(parts, " ") .. " flights up (SV_Up_*)=" .. up, up
end

local survivalPC = nil             -- the player controller in Survival's level (found by probeTick, then reused)

-- Where the player is (cm), or nil.
local function playerLocation()
    local pc = valid(survivalPC) and survivalPC or FindFirstOf("PlayerController")
    local ok, l = pcall(function()
        local v = pc.Pawn:K2_GetActorLocation()
        return { X = v.X, Y = v.Y, Z = v.Z }
    end)
    return ok and l or nil
end

local function km(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 100000
end

-- The game's current difficulty (LiveDifficultyManager.CurrentDifficulty: 1 Casual .. 5 Ace).
local DIFFICULTY = { [0] = "None", "Casual", "Easy", "Normal", "Hard", "Ace", "FreeFlight" }
local function logDifficulty(when)
    local dm = FindFirstOf("LiveDifficultyManager")
    local ok, d = pcall(function() return dm.CurrentDifficulty end)
    log("difficulty " .. when .. ": " .. ((ok and type(d) == "number") and (DIFFICULTY[d] or tostring(d)) or "unknown"))
end

local levelTick = nil              -- tick count when Survival's level was loaded (nil again once the run is over)
pcall(NotifyOnNewObject, "/Script/Engine.World", function(w)
    local n = nameOf(w)
    if n:find("PL_SurvivalMode", 1, true) then levelTick = -1 end      -- picked up by the next tick
    -- every level and sublevel the game makes, so a crash while loading shows the last one (AC8SurvivalMode_lua.log)
    log("world: " .. (n:match("(/Game/[^%.:]+)") or n))
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
    start_round         = 1,                    -- the run's first round (testing: e.g. 16 for the named aces)
    first_round_delay_s = 15,
    intermission_s      = 20,
    spawn_gap_s         = 3,                    -- between two flights of a round
    orders_check_s      = 4,                    -- a fighter flight without its SV_Up_NN flag by then gets its orders again
    -- A round's size is an aircraft budget, filled with squadrons of 2, 4 and 6 (user, 2026-10-22): the world data's
    -- fighter flights are ERA_Unit_NN_Dep_Air0 2 aircraft, _Air1 4, _Air2 6 (tools/survival_events.py flight_size);
    -- a squadron size joins the draw from its from_round.
    aircraft_round1     = 4,
    aircraft_per_round  = 2,                    -- added every round
    max_aircraft        = 24,                   -- in one round
    squadrons           = { { size = 2, from_round = 1 }, { size = 4, from_round = 4 }, { size = 6, from_round = 8 } },
    distance_km         = { 18, 25 },           -- from the airfield, random bearing
    altitude_m          = { 2000, 4500 },
    aircraft            = { "f16c_common", "f18e_common", "f15e_common", "f14d_common", "m21b_common",
                            "m29a_common", "m31b_common", "su33_common", "su34_common" },   -- NPC rows in Mission 22's table
    pool                = {},                   -- Mission 22's 24 "kokatu" flights (tools/survival_events.py POOL)
    -- Ammo cap at spawn (BUILD_PLAN Milestone 2): missiles / each special weapon / flares per preset; the gun is
    -- unlimited. The preset follows the game's difficulty (1 Casual, 2 Easy, 3 Normal, 4 Hard, 5 Ace).
    ammo = {
        enabled          = true,
        gun_unlimited    = true,
        free_restock     = false,               -- the game refills missiles over time unless this is off
        presets          = {
            casual   = { missiles = 72, special = 56, flares = 6 },
            standard = { missiles = 48, special = 28, flares = 4 },
            ace      = { missiles = 30, special = 14, flares = 3 },
        },
        by_difficulty    = { "casual", "standard", "standard", "standard", "ace" },
    },
    -- Behaviour probe (learning-AI step 1, see the "behaviour probe" section): own behaviour script on each round's
    -- first flight, live PilotRank write on every enemy, kill attribution in the log.
    -- runtime: also fly the LuaScript made at run time (route 2), put into the game's Lua by dlls/main.dll 0.8.0.
    -- (Test 20: making an in-memory package for it from UE4SS crashed the game; that is gone.)
    -- units: the probe's own flights (tools/survival_events.py PROBE_UNITS: their world data names the probe rows, as
    -- the game builds behaviour at level load); they fly only as round 1's (package script) and round 2's (run-time
    -- script) first flight, never in the normal rotation.
    ai_watch = true,                            -- log each enemy's AI state and target when they change ("ai:" lines)
    -- behaviour = false (2026-10-22): the barrel-roll probe proved the game builds Survival's scripts; its MiGs flipped
    -- between PursueTarget and ReturnToWorld and never closed in, so rounds 1-2 open with normal fighters again.
    probe = { enabled = true, behaviour = false, runtime = true, kills = true,
              units = { Pkg = "ERA_Unit_08_Dep_Air2", Rt = "ERA_Unit_08_Dep_Air1" } },
    -- Enemy skill tiers (user, 2026-10-22: early fighters must not fly like aces). Every enemy gets its tier's
    -- PilotRank when it appears (1-5: how often it picks the better evasions and flares of its behaviour set; a live
    -- write sticks, test 16), plus rank_add for the difficulty, kept within 1-5. A tier without post_stall never
    -- uses the cobra / kulbit, even on a model CFG.maneuvers allows. The round picks the tier; promote_chance of the
    -- pilots fly one tier higher. Survival's own behaviour scripts per tier come later (the game-Lua bridge first).
    tiers = {
        enabled = true,
        promote_chance = 0.2,
        rank_add = { casual = -1, standard = 0, ace = 1 },
        list = {
            { name = "Rookie",  from_round = 1,  rank = 2, post_stall = false },   -- one rank up (user, 2026-10-22:
            { name = "Regular", from_round = 4,  rank = 3, post_stall = false },   -- "still felt very easy")
            { name = "Veteran", from_round = 7,  rank = 4, post_stall = true },
            { name = "Elite",   from_round = 10, rank = 5, post_stall = true },
            { name = "Ace",     from_round = 13, rank = 5, post_stall = true },
            -- Beyond Ace (user, 2026-10-22: "make more of these pilot ranks"). The game clamps PilotRank to 1-5, so these
            -- stay at 5 and raise the AI level instead (the flight's LevelId, 100 x ai_level, written before it spawns:
            -- dlls/main.dll SV_SetLevel; stock is 2). Survival's behaviours weigh their tight tail chase, cobra / kulbit
            -- bait and scissors by it (tools/re/BEHAVIOUR_GUIDE.md 6). fcs: fire control at least that difficulty-spike
            -- level's; provoke / surround: as CFG.spikes' (react quicker when tailed, sit closer when pursuing).
            { name = "Mercenary", from_round = 16, rank = 5, post_stall = true, ai_level = 3, fcs = 1 },
            { name = "Legend",    from_round = 19, rank = 5, post_stall = true, ai_level = 4, fcs = 2 },
            { name = "Demon",     from_round = 22, rank = 5, post_stall = true, ai_level = 5, fcs = 2 },
            { name = "Phantom",   from_round = 25, rank = 5, post_stall = true, ai_level = 5, fcs = 3,
                                  provoke_cone_deg = 50, provoke_time_s = 1.0 },
            { name = "Reaper",    from_round = 28, rank = 5, post_stall = true, ai_level = 5, fcs = 3,
                                  provoke_cone_deg = 45, provoke_time_s = 0.8, surround_m = { 40, 100 } },
        },
    },
    -- Named aces (user, 2026-10-22: "build it with this line up, but custom names"). From Mercenary on, a fighter flight
    -- flies its tier's squadron: one airframe of the tier's line-up (ACE.roster; stock skins: Shark / Ventus F-15C and
    -- Su-35, Savia Rafale, Ares Su-57, Shadow Su-57 / Typhoon / Su-47, the named aces' own), its wingmen under the
    -- squadron's name and its lead, when that ace isn't already up, under the ace's own. These are only the names:
    -- [aces.<tier>] in survival.ini renames them; which airframe a name flies is fixed (tools/build_survival.py ACES).
    aces = {
        enabled = true,
        callout = true,                            -- "ACE INBOUND" the first time each ace shows up in a run
        -- airframes only Online Mode has (the ADFX-02: its model and blueprint come from Online Mode's tables, ACE.models).
        -- false leaves them out (if one ever misbehaves offline); their tier flies the rest of its line-up.
        online_aircraft = true,
        mercenary = { squadron = "Bounty",   f15c = "Ledger",   su35 = "Wager",    typhoon = "Payday" },
        legend    = { squadron = "Valkyrie", su47 = "Sigrun",   rafale = "Brynhild" },
        demon     = { squadron = "Inferno",  f22a = "Mephisto", su57 = "Belial" },
        phantom   = { squadron = "Wraith",   su57 = "Specter",  typhoon = "Revenant", su47 = "Banshee" },
        reaper    = { squadron = "Harvest",  su57 = "Grim",     f22a = "Scythe",   typhoon = "Charon", rafale = "Nightfall",
                      adfx02 = "Oblivion" },
    },
    -- Enemy search range (user 2026-10-22: no chase, enemies should always have the player in view). Mission 22's
    -- fighters use AI module NPC_AIModule_Plane000: 6 km search radius, and they lose a target hidden in cloud.
    -- Survival's own module row (a copy with these values) is given to copies of the aircraft's DT_NPC rows.
    -- The flights' unit area (activation) is set at build time: tools/survival_events.py AREA_RADIUS_M.
    -- luaset: the behaviour set those copies fly (a DT_NPC_LuaSet row, or one of CFG.behaviour_sets; nil keeps each
    -- aircraft's own); fallback_luaset when an own set couldn't be made. NLID_0400_CP (the campaign aces' set) is NOT
    -- usable: its pursuit only attacks in KDS phases, which these fighters never get (test of 2026-10-22: "the
    -- aircraft aren't attacking the player anymore").
    search = { enabled = true, radius_m = 40000, lose_in_clouds = false, luaset = "NLID_SV_Fighter",
               fallback_luaset = "NLID_0012_CP" },
    -- The fighters' missiles (user, 2026-10-22: "it takes them forever to get a missile lock"). Every stock enemy
    -- missile is fire-control row NPC_FCS_PlaneMsl000: lock only within 2.5 km and 45 deg, 2 s to arm, 2.5 s to lock,
    -- 10 s between shots (aces: 60 deg, 5 s). Each fighter's Survival NPC row gets a copy (<row>_SV in DT_NPC_FCS)
    -- with these values: range (m), cone (deg), arm / lock / between-missiles / rest (s).
    missiles = { enabled = true, capture_m = 4000, angle_deg = 60, arm_s = 0.5, lock_s = 1.5, interval_s = 2.0, rest_s = 5.0 },
    -- The fighters' gun (user, 2026-10-22: "increase their guns too and accuracy"). Every enemy gun, aces included, is
    -- NPC_FCS_PlaneGun000: fires within 1.5 km and 30 deg after 1.5 s on target, 10-round bursts, 1 s rest; its rounds
    -- (GUN_000 in DT_NPC_Weapon) do 1 damage and spread up to 3 deg. Survival's copies (<row>_SV): range (m), cone (deg),
    -- time on target before firing (s), rounds a burst, rest (s), damage multiplier, spread (deg).
    guns = { enabled = true, range_m = 2000, angle_deg = 40, aim_s = 0.8, burst = 15, rest_s = 0.6, damage_x = 1.5, spread_deg = 1.5 },
    -- Special weapons (user, 2026-10-22): each fighter type gets one of these stock ace fire-control rows (QAAM, 2AAM,
    -- LAAM, HCAA, as the Shadow aces carry theirs) in its first free weapon slot, picked at random once a session; its
    -- fire control fires it by itself when the player is in its range and cone.
    special = { enabled = true,
                fcs = { "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000", "NPC_FCS_PlaneLAAM000", "NPC_FCS_PlaneHCAA000" } },
    -- Survival's own behaviour sets: a DT_NPC_LuaSet row copied from `base`, with `slots` pointing at Survival's
    -- scripts (Scripts/ai/<name>.lua, packaged at /Game/LuaSource/SurvivalMode/AI/<name> by tools/build_survival.py
    -- LUA_SCRIPTS). Made from the main menu on: the game builds a flight's behaviour when the level loads.
    -- NLID_SV_Fighter: Mission 22's light-fighter set (0012_CP) with LA_SV_MoveAway, a ~1.5 s break after each attack
    -- pass instead of 12.5 s. The pursuit stays the stock one: its closing SetMoveAwayFromTarget is what starts the
    -- next attack run (Lua 0.18.x dropped it and the fighters drifted between runs: test of 2026-10-22).
    -- NLID_SV_Fighter's pursuit: LA_SV_TailChase (tools/re/BEHAVIOUR_GUIDE.md), the stock fighter pursuit plus a
    -- "sit on the target's tail" branch (PursuerTarget with its own-offset flag: 250 m behind the target, KDS blocked)
    -- that its pilot rank weighs: rank 1 never, 2 10 %, 3 30 %, 4 70 %, 5 always. The skill tiers and difficulty spikes
    -- raise the rank, so the tail chasing grows with the rounds. ai.tail_chase = false keeps the stock pursuit.
    behaviour_sets = {
        NLID_SV_Fighter = { base = "NLID_0012_CP", slots = { MoveAwayFromTargetLua = "LA_SV_MoveAway",
                                                             PursueTargetLua = "LA_SV_TailChase",
                                                             ProvokeNearLua = "LA_SV_ProvokeNear",
                                                             EscapeFromPursuerLua = "LA_SV_Escape" } },
    },
    -- reactions (user, 2026-10-22: "come up with some new reactions"): LA_SV_ProvokeNear when the player is close on
    -- their tail (break turn, brake-and-turn overshoot, flare break; AI level 3+ cobra bait, 4+ kulbit bait and
    -- scissors), LA_SV_Escape (low ranks the stock 8 s run, higher ranks the aces' 2 s break). false: the stock ones.
    ai = { tail_chase = true, reactions = true },
    -- Post-stall manoeuvres (Pugachev's cobra, kulbit): every stock behaviour gates them on the plane's
    -- bCanManeuverPugachevsCobra / bCanManeuverKulbit; on each enemy that appears both are turned off unless its
    -- model is listed here (the code in its blueprint name, BP_OPnnnn_<code>_...: thrust-vectoring and Flanker-family
    -- airframes; those keep their blueprint's own, e.g. su33 cobra but no kulbit), so early fighters never post-stall.
    maneuvers = { enabled = true, post_stall = { "su33", "su35", "su37", "su47", "su57", "f22a" } },
    -- Airfield and bombers (Milestone 3; tools/survival_events.py AIRFIELD_* / BOMBERS, tools/re/AIRFIELD_SUPPLY.md).
    -- The airfield starts at `hp`; every enemy weapon that reaches one of its 4 target points (the event package
    -- counts them in SV_AirHits) takes hit_damage. At 0 it is down: landing closes (no rearming) until the end of the
    -- round after, then it reopens at repair_hp. Bomber flights (2 aircraft, Mission 22's airport strike: they only
    -- go for the airfield) join rounds from bombers.from_round, one more flight every `every` rounds, up to `max`;
    -- Tu-95s and Tu-160s (`heavy`) from heavy_from_round. bombers.pool must match survival_events.BOMBERS.
    airfield = {
        enabled    = true,
        hp         = 100,
        hit_damage = 4,
        repair_hp  = 50,
        bombers = {
            -- Bomber raids (user, 2026-10-22: "in bomber rounds bombers primarily spawn"): from first_raid, every
            -- raid_every rounds; raid_share of that round's aircraft are bombers (squadrons of 2, 4, 6 by the same
            -- from_round rule), the rest fighter escort. Other rounds have no bombers.
            first_raid = 3, raid_every = 3, raid_share = 0.65,
            -- flight sizes; must match tools/survival_events.py BOMBER_SIZES (EB_Unit_01_Air0 too)
            sizes = { ERB_Unit_01_Air2 = 4, EA_Unit_01_Air0 = 2, EA_Unit_01_Air1 = 2, EA_Unit_01_Air2 = 4, EB_Unit_01_Air0 = 6 },
            aircraft = { "su34_common", "f15e_common" },
            heavy = { "tu95_common", "t160_common" },
            heavy_from_round = 3,               -- heavy flights can come in every bomber round
            distance_km = { 28, 36 },
            -- Strike aircraft come in low, as Mission 22's Su-34s do (600 m): from 1.7 km the F-15Es flipped between
            -- PursueTarget on the airfield and ReturnToWorld and never fired (AI watch, 2026-10-22).
            altitude_m = { 1500, 3000 },        -- heavies
            strike_altitude_m = { 500, 900 },
            pool = { "ERB_Unit_01_Air2", "EA_Unit_01_Air0", "EA_Unit_01_Air1", "EA_Unit_01_Air2", "EB_Unit_01_Air0" },
            -- the flights built with large-aircraft behaviour (survival_events.HEAVY_BOMBERS): they fly the heavies,
            -- the others the strike aircraft
            heavy_units = { "EA_Unit_01_Air1", "EA_Unit_01_Air2" },
            -- Heavies never bomb on their own (no stock mission lets them): when one is within drop_km of the runway
            -- its flight's bomb run is fired (RE_SV_BombRun_NN: both aircraft drop 6 bombs), at most once every
            -- run_cooldown_s, and bomb_damage is taken off the airfield damage_delay_s later (as the bombs land).
            -- drop_km 3 (was 1.5: the Tu-160s of the test of 2026-10-22 never came that close; their orbit is now 1.5 km,
            -- tools/survival_events.py HEAVY_AREA_RADIUS_M); every heavy's distance is logged every 10 s ("bombers:")
            drop_km = 3.0, run_cooldown_s = 20, bomb_damage = 12, damage_delay_s = 5,
        },
    },
    -- Credits (Milestone 4): earned for every enemy aircraft that goes down (by its flight: bomber flights pay
    -- bomber / heavy, the rest fighter; `models` is only used when a plane's flight can't be read) and for every round
    -- cleared (round_bonus x the round), spent in the airfield shop.
    credits = {
        start = 0, fighter = 100, bomber = 200, heavy = 400, round_bonus = 50,
        models = { su34 = "bomber", tu95 = "heavy", t160 = "heavy" },
    },
    -- The airfield shop: rows on the landing menu (the in-game hangar's list, under Yes / No), added while Survival's
    -- level is loaded. Landing rearms nothing (user, 2026-10-22: "landing at the airfield is still refilling your ammo
    -- regardless of buying it"): the ammo you fly with is what you took off with, less what you fired, plus what you
    -- bought (kind: 1 missiles, 2 special weapons, 4 flares; up to the aircraft's full load), or the shop repairs the
    -- airfield. Every purchase of an item makes its next one `raise` times dearer (1: the same price every time).
    -- The item names must match tools/build_survival.py SHOP_ITEMS.
    shop = {
        enabled = true,
        items = {
            -- ammo is used up now (no free rearm), so a pack costs the same every time: 25 Z a missile against 100 Z a
            -- fighter (about two missiles a kill), 100 Z a special weapon round, 75 Z a flare
            Missiles = { kind = 1, step = 12, price = 300, raise = 1.0, label = "MISSILES", what = "missiles" },
            Special  = { kind = 2, step = 4, price = 400, raise = 1.0, label = "SPECIAL WEAPON", what = "special weapon rounds" },
            Flares   = { kind = 4, step = 2, price = 150, raise = 1.0, label = "FLARES", what = "flares" },
            -- the landing menu has room for 4 shop rows, so this one repairs the airfield while it's damaged and, once
            -- it's whole, builds its defences (user, 2026-10-22: "purchase AA guns ... or SAM sites. Make them
            -- expensive"): Mission 22's airport AA guns and SAM sites, one unit each (tools/survival_events.py
            -- DEFENCES), built in `order`; a destroyed one can be built again. Each kind's price rises `raise` times.
            Airfield = { repair = 25, price = 250, raise = 1.25, label = "REPAIR AIRFIELD",
                         defences = {
                             order = { "aa", "aa", "sam", "aa", "aa", "sam", "aa" },
                             aa  = { label = "AA GUN", what = "an AA gun", price = 4000, raise = 1.25,
                                     units = { "SV_Unit_AAGun_A", "SV_Unit_AAGun_B", "SV_Unit_AAGun_C", "SV_Unit_AAGun_D",
                                               "SV_Unit_AAGun_E" } },
                             sam = { label = "SAM SITE", what = "a SAM site", price = 8000, raise = 1.25,
                                     units = { "SV_Unit_SAM_A", "SV_Unit_SAM_B" } },
                         } },
        },
    },
    -- Difficulty spikes (user, 2026-10-22: "every 7 rounds we should have a difficulty spike that's across the board,
    -- enemies react quicker, have more accuracy and will always try to get behind you, even start post stalling").
    -- Level L (rounds 1 + L x every on; the last level stays) on top of the round's skill tier and growth:
    --   missiles / guns  that level's fire control (copies of CFG.missiles / CFG.guns with these fields changed), on
    --                    rows of its own (<row>_sv<b|c|d>: tools/build_survival.py SPIKE_SUFFIXES)
    --   rank_min         every pilot at least this PilotRank (after the difficulty's rank_add)
    --   post_stall_all   cobra and kulbit on every airframe, not only CFG.maneuvers.post_stall's
    --   provoke_cone_deg / provoke_time_s   when the player is behind them: a narrower cone (Shadow squadrons fly 60)
    --                    and a quicker decision, so they turn on you sooner (live write, untested)
    --   surround_m       their pursuit sits this close behind the target (stock 100-300 m; live write, untested)
    --   aircraft_add / max_add   more aircraft each round, and a higher cap
    spikes = {
        enabled = true,
        every   = 7,
        levels  = {
            { missiles = { capture_m = 4500, angle_deg = 70, lock_s = 1.2, interval_s = 1.6, rest_s = 4.0 },
              guns = { range_m = 2200, angle_deg = 45, aim_s = 0.6, burst = 18, rest_s = 0.5, spread_deg = 1.1 },
              rank_min = 4, post_stall_all = true, provoke_cone_deg = 70, provoke_time_s = 2.0, surround_m = { 80, 220 },
              aircraft_add = 2, max_add = 4 },
            { missiles = { capture_m = 5000, angle_deg = 80, lock_s = 0.9, interval_s = 1.3, rest_s = 3.0 },
              guns = { range_m = 2400, angle_deg = 50, aim_s = 0.45, burst = 20, rest_s = 0.4, spread_deg = 0.8 },
              rank_min = 5, post_stall_all = true, provoke_cone_deg = 60, provoke_time_s = 1.5, surround_m = { 60, 160 },
              aircraft_add = 4, max_add = 8 },
            { missiles = { capture_m = 5500, angle_deg = 90, lock_s = 0.7, interval_s = 1.0, rest_s = 2.0 },
              guns = { range_m = 2600, angle_deg = 55, aim_s = 0.3, burst = 24, rest_s = 0.3, spread_deg = 0.5, damage_x = 1.8 },
              rank_min = 5, post_stall_all = true, provoke_cone_deg = 50, provoke_time_s = 1.0, surround_m = { 50, 120 },
              aircraft_add = 6, max_add = 12 },
        },
    },
    -- Special rounds (Milestone 6): from round `first`, every `every` rounds, the next special of `rotation` instead of a
    -- normal round (a special that can't start falls back to one). "shuttle" = Comona Defense
    -- (tools/survival_events.py SHUTTLE_*): the shuttle `name` on Mission 22's pad, its AA guns, SAMs and tower around
    -- it, lifts off countdown_s after it appears. The round's fighters come for the player; strike_share of its aircraft
    -- are strike flights (no heavies) sent at the shuttle. Launched: `reward` zollars. Lost: the shop is closed for the
    -- next shop_closed_rounds rounds. countdown_s is built into the event package (SHUTTLE_COUNTDOWN_S): keep it equal.
    specials = {
        enabled  = true,
        first    = 5,
        every    = 5,
        rotation = { "shuttle", "anomaly" },
        shuttle  = { name = "EMBDIR Shuttle - CORRIS", countdown_s = 150, reward = 3000, strike_share = 0.4,
                     -- pad_allies: Mission 22's pad guns, SAMs and tower around the shuttle during the countdown
                     -- (removed after it, tools/survival_events.py PAD_REMOVE_LOST_S / SHUTTLE_REMOVE_S)
                     pad_allies = true, dummies = "SV_Unit_PadDummies",
                     shop_closed_rounds = 1, unit = "SV_Unit_Shuttle", pad = "AA_Unit_01_Ground0",
                     name_key = "SV_Shuttle_Name", npc_row = "OP0057_sstb_01_SV",
                     npc_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcRows.DT_SV_NpcRows" },
        -- "anomaly" = The Anomaly (tools/survival_events.py ANOMALY_*; user, 2026-10-22): the ace `name` in an F-4E
        -- (the campaign named-ace skin) with `guards` escorts under `guards_name`, both at the top skill tier and AI
        -- level ai_level. Within field_km of it the player's controls invert (`invert`: "both", "pitch" or "roll",
        -- fading over fade_s; dlls/main.dll SV_SetControlInvert), with the stock glasses effect and radar noise; its
        -- round starts with the stock MISSION UPDATE beep, a forced WARNING and the focus camera on it. Shot down:
        -- `reward` zollars, controls back. The round ends when it and every other enemy are down.
        anomaly  = { name = "MINDRIPPER", guards_name = "PHANTASM", guards = 4, field_km = 3.0, invert = "both",
                     fade_s = 1.5, reward = 4000, ai_level = 5, guard_offset_m = 800,
                     unit = "SV_Unit_Anomaly", guard_unit = "SV_Unit_AnomalyGuards" },
    },
    -- Music (dlls/main.dll 0.9.0 SV_PlayBGM: the game's own BGM controller, which fades the old track out). Round 1
    -- keeps the mission-start track (start_track, posted by the event package); from round 2 each round starts the next
    -- track of a shuffled list, every 5th round one from `special`. A track is posted again when nothing has played
    -- for restart_s (user, 2026-10-21: the music stopped around round 5). All are looping campaign tracks of the BGM
    -- bank Survival's level loads (tools/re/MUSIC_RADIO_CAMERA.md); a name the game doesn't have is dropped.
    -- pause_player: free flight's Music Player row in Survival's pause menu; once the player opens it, Survival stops
    -- changing the music for the rest of the run.
    -- enabled = false (user, 2026-10-22): no round music at all, the Music Player is the only music (the mission-start
    -- track played over it; tools/survival_events.py MUSIC is None too). true brings the round rotation back.
    -- hold_clock: the Music Player ends each track by its own clock, which ran on through pauses, so every pause cut the
    -- track short (user, 2026-10-22: "music skipped on round change"); dlls/main.dll 0.12.0 holds it while the BGM is
    -- paused (SV_MusicClock, tools/re/MUSIC_RADIO_CAMERA.md "Track skips in Survival").
    music = {
        enabled      = false,
        pause_player = true,
        hold_clock   = true,
        start_track  = "AKE_Bgm_Ms08A_Play",
        restart_s    = 15,
        tracks  = { "AKE_Bgm_Ms02A_Play", "AKE_Bgm_Ms04A_Play", "AKE_Bgm_Ms05a_Play", "AKE_Bgm_Ms07A_Play",
                    "AKE_Bgm_Ms11A_Play", "AKE_Bgm_Ms12a_Play", "AKE_Bgm_Ms14A_Play", "AKE_Bgm_Ms17A_Play",
                    "AKE_Bgm_Ms18A_Play", "AKE_Bgm_Ms20A_Play", "AKE_Bgm_Ms21A_Play", "AKE_Bgm_Ms22A_Play",
                    "AKE_Bgm_Ms24A_Play" },
        special = { "AKE_Bgm_Ms09B_Play", "AKE_Bgm_Ms20D_Play", "AKE_Bgm_Ms23B_Play", "AKE_Bgm_Ms27A_Play",
                    "AKE_Bgm_Ms28C_Play", "AKE_Bgm_Ms30A_Play" },
    },
    -- Round HUD. Positions are on the game's HUD design canvas (3840x2160, scaled to the screen; tools/re/HUD_LAYOUT.md).
    hud = {
        enabled          = true,
        x                = 190,                 -- left edge, lined up with the game's TIME / SCORE stack
        -- Below the game's stack: TIME 108, SCORE 176 (test 13 screenshot) and the TARGET row at 244, which appears
        -- when the player locks on and covered ROUND at 244 (user screenshot, 2026-10-22).
        y                = 312,
        hide_game_timer  = true,                -- hide the stack's TIME row (Survival's mission clock is paused)
        hide_score_limit = true,                -- SCORE shows the score alone, without the mission's "/32000"
        -- AIRFIELD row (under ROUND): health bar after the label (offsets from the row's left / top), then its number
        airfield_bar     = { x = 270, dy = 15, w = 300, h = 24, frame = 3 },
        warn_color       = { 1.0, 0.3, 0.2 },   -- the bar at or under warn_hp
        warn_hp          = 25,
        line             = 68,                  -- row pitch of the game's stack
        font_size        = 37,                  -- the mission info panel's text: HUD typeface 37, spacing -70
        letter_spacing   = -70,
        banner_letter_spacing = -35,
        -- The game draws its HUD white and tints it in a post-process (green by default, plus a glow); ours is a
        -- plain widget, so it gets the measured green (linear RGB) and a faint outline in place of the glow.
        color            = { 0.26, 1.0, 0.33 },
        opacity          = 0.9,
        glow_size        = 2,                   -- outline width; 0 = none
        glow_alpha       = 0.25,
        banner_y         = 894,                 -- centre of the callout banner (the game's MessageLayerOne)
        banner_char_w    = 32,                  -- estimated width of a banner letter (design units)
        banner_pad       = 70,                  -- space between the banner's text and its box, each side
        callout_s        = 4,                   -- how long a callout stays up
        start_callout_lead_s = 3,               -- "ROUND n" this long before the round's first flight
        zorder           = 0,
        text = {
            round        = "ROUND: %d",
            next_round   = "NEXT ROUND: %s",
            first_round  = "ROUND 1 IN: %s",
            complete     = "ROUND %d COMPLETE",
            complete_sub = "NEXT ROUND IN %d SECONDS",
            credits      = "ZOLLARS: %d",
            airfield     = "AIRFIELD:",
            airfield_down_row = "AIRFIELD: DOWN",
            bombers      = "BOMBERS INBOUND",
            bombers_sub  = "PROTECT THE AIRFIELD",
            under_attack = "AIRFIELD UNDER ATTACK",
            airfield_down     = "AIRFIELD DOWN",
            airfield_down_sub = "NO LANDING UNTIL AFTER ROUND %d",
            airfield_up       = "AIRFIELD REPAIRED",
            airfield_up_sub   = "CLEARED TO LAND",
            start        = "ROUND %d",
            start_sub    = "HOSTILES INBOUND",
            special      = "SPECIAL ROUND %d",
            shuttle_sub  = "DEFEND THE %s",
            launch_row   = "LAUNCH IN: %s  SHUTTLE %d%%",
            launched     = "SHUTTLE LAUNCHED",
            launched_sub = "+%d ZOLLARS",
            shuttle_lost = "SHUTTLE LOST",
            shuttle_lost_sub = "SHOP CLOSED NEXT ROUND",
            shop_closed  = "SHOP CLOSED: THE SHUTTLE WAS LOST.",
            spike        = "DIFFICULTY UP",
            spike_sub    = "ENEMY PILOTS GROW SHARPER",
            ace          = "ACE INBOUND: %s",
            anomaly_sub  = "ANOMALY DETECTED",
            anomaly_warn = "WARNING: %s",
            anomaly_warn_sub = "ITS FIELD INVERTS YOUR CONTROLS",
            anomaly_field     = "ANOMALY FIELD",
            anomaly_field_sub = "CONTROLS INVERTED",
            anomaly_clear     = "CONTROLS RESTORED",
            anomaly_row       = "%s: %.1f KM",
            anomaly_row_field = "ANOMALY FIELD: CONTROLS INVERTED",
            anomaly_down      = "%s DOWN",
            anomaly_down_sub  = "+%d ZOLLARS",
            ace_sub      = "%s SQUADRON (%s)",
        },
    },
}
for n = 1, 8 do for k = 0, 2 do CFG.pool[#CFG.pool + 1] = string.format("ERA_Unit_%02d_Dep_Air%d", n, k) end end
-- The player's settings: config/survival.ini (BUILD_PLAN Milestone 4). Releases ship config/survival.default.ini; the
-- first run copies it to survival.ini, which an update never overwrites. A [section] names a CFG table (dots for
-- nested ones, any case; INI_ALIAS gives the friendly names), `key = value` sets a field that exists there: a number,
-- true / false, text, or a comma list for a list field. [squadrons] keys are squadron sizes (value: from_round).
-- Read once at start (the main menu builds Survival's NPC rows from CFG), so changes need a game restart.
do                                 -- (its helpers stay inside: the main chunk's 200-local limit)
local INI_ALIAS = { rounds = "", zollars = "credits", bombers = "airfield.bombers", skill = "tiers",
                    ["skill.difficulty"] = "tiers.rank_add", enemy_missiles = "missiles", enemy_guns = "guns",
                    ["ammo.casual"] = "ammo.presets.casual", ["ammo.standard"] = "ammo.presets.standard",
                    ["ammo.ace"] = "ammo.presets.ace" }
local function iniSection(name)
    local path = name:lower()
    path = INI_ALIAS[path] or path:gsub("^shop%.", "shop.items.")
    local t = CFG
    for part in path:gmatch("[^%.]+") do
        local found = nil
        for k, v in pairs(t) do if type(k) == "string" and k:lower() == part and type(v) == "table" then found = v end end
        if not found then return nil end
        t = found
    end
    return t
end
local function iniValue(old, s)
    if type(old) == "boolean" then
        local b = ({ ["true"] = true, yes = true, on = true, ["1"] = true, ["false"] = false, no = false, off = false, ["0"] = false })[s:lower()]
        return b, b ~= nil
    elseif type(old) == "number" then
        local n = tonumber(s)
        if n and math.type(old) == "integer" then n = math.tointeger(n) or math.floor(n + 0.5) end
        return n, n ~= nil
    elseif type(old) == "string" then
        return s, true
    elseif type(old) == "table" and #old > 0 and type(old[1]) ~= "table" then
        local list = {}
        for item in s:gmatch("[^,]+") do
            item = item:match("^%s*(.-)%s*$")
            if type(old[1]) == "number" then item = tonumber(item); if not item then return nil, false end end
            list[#list + 1] = item
        end
        return list, #list > 0
    end
    return nil, false
end
local function loadIni()
    local dir = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "..\\config\\"
    local f = io.open(dir .. "survival.ini", "r")
    if f then
        -- format 1 (Lua 0.24-0.25) copied every default as a live setting, which pinned them: a later default change never
        -- reached the player. Format 2 lists them switched off. An old file is kept as survival.ini.old.
        local text = f:read("a") or ""
        if not text:find("survival.ini format 2", 1, true) then
            f:close(); f = nil
            os.remove(dir .. "survival.ini.old")
            local ok = os.rename(dir .. "survival.ini", dir .. "survival.ini.old")
            log("config: survival.ini is from an older version; " .. (ok and "kept as survival.ini.old, a new one is made"
                or "could not rename it, so it is used as it is"))
            if not ok then f = io.open(dir .. "survival.ini", "r") end
        else
            f:seek("set", 0)
        end
    end
    if not f then
        local d = io.open(dir .. "survival.default.ini", "r")
        if not d then return end
        local text = d:read("a"); d:close()
        local out = io.open(dir .. "survival.ini", "w")
        if out then out:write(text); out:close(); log("config: made config\\survival.ini from survival.default.ini") end
        f = io.open(dir .. "survival.ini", "r")
        if not f then return end
    end
    local t, section, set, bad, n = nil, nil, 0, {}, 0
    for line in f:lines() do
        n = n + 1
        line = line:gsub("^\239\187\191", ""):gsub("%s*[;#].*$", ""):match("^%s*(.-)%s*$")
        local sec = line:match("^%[%s*(.-)%s*%]$")
        if sec then
            section, t = sec, iniSection(sec)
            if not t then bad[#bad + 1] = string.format("line %d: no section [%s]", n, sec) end
        elseif line ~= "" then
            local key, val = line:match("^([^=]-)%s*=%s*(.*)$")
            if not key then
                bad[#bad + 1] = string.format("line %d: not 'key = value'", n)
            elseif t then
                local ok = false
                if t == CFG.squadrons then
                    for _, q in ipairs(t) do
                        if tostring(q.size) == key then local v = tonumber(val); if v then q.from_round, ok = v, true end end
                    end
                else
                    local field = nil
                    for k in pairs(t) do if type(k) == "string" and k:lower() == key:lower() then field = k end end
                    if field then
                        local v; v, ok = iniValue(t[field], val)
                        if ok then t[field] = v end
                    end
                end
                if ok then set = set + 1 else bad[#bad + 1] = string.format("line %d: [%s] %s = %s not used", n, section, key, val) end
            end
        end
    end
    f:close()
    log(string.format("config: survival.ini, %d settings%s", set, #bad > 0 and ("; " .. table.concat(bad, "; ")) or ""))
end
    local ok, err = pcall(loadIni)
    if not ok then log("config: survival.ini could not be read: " .. tostring(err)) end
end
do  -- optional overrides: Scripts/survival_config.lua returning a table with any of the keys above. Lists (aircraft,
    -- pool, ...) are replaced whole; keyed tables (hud, hud.text) are merged, so one field can be changed alone.
    local function merge(into, from)
        for k, v in pairs(from) do
            if type(v) == "table" and type(into[k]) == "table" and #into[k] == 0 and next(into[k]) ~= nil then merge(into[k], v)
            else into[k] = v end
        end
    end
    local ok, user = pcall(require, "survival_config")
    if ok and type(user) == "table" then
        merge(CFG, user)
        log("config: survival_config.lua loaded")
    end
end
math.randomseed(os.time())

-- The difficulty preset (casual / standard / ace, CFG.ammo.by_difficulty) and the game's difficulty number.
local presetCache = { at = -100 }
local function presetName()
    local now = os.clock()
    if now - presetCache.at > 30 then           -- kept 30 s (Select Difficulty is hidden in Survival's pause menu)
        local dm = FindFirstOf("LiveDifficultyManager")
        local ok, d = pcall(function() return dm.CurrentDifficulty end)
        presetCache.at, presetCache.name, presetCache.d = now, (ok and CFG.ammo.by_difficulty[d]) or "standard", ok and d or nil
    end
    return presetCache.name, presetCache.d
end

---------------------------------------------------------------------------------------------------- behaviour probe
-- First step towards Survival's own (learning) enemy behaviour (BUILD_PLAN; tools/re/AI_BEHAVIOURS.md). One test,
-- three questions (CFG.probe):
--  1. Does an enemy run our own behaviour script? The first flight of every round flies a copy of Mission 22's MiG-29
--     whose pursue slot is LA_SV_ProbePursue (barrel roll right, then left, then the stock pursuit, every attack run):
--     odd rounds the script from Survival's package (/Game/LuaSource/SurvivalMode/AI), even rounds a LuaScript object made
--     here at run time from Scripts/ai/LA_SV_ProbePursue.lua. Rows: DT_NPC_LuaSet NLID_SV_ProbePkg/Rt (copies of
--     NLID_0000_CP) and DT_NPC SV_m29a_ProbePkg/Rt (OP1020_m29a_01) are added here at run time, as early as the main
--     menu; the mission rows sv_probe_pkg/rt are in Survival's own NPC table (tools/build_survival.py NPC_EXTRA),
--     because the spawner caches that table's aircraft when the level starts. A variant is only flown when its rows
--     were in before the level loaded.
--  2. Does a live write to an enemy's PilotRank stick? Each enemy's rank is logged, set to CFG.probe.rank, and read
--     again 10 s later.
--  3. Can a kill be attributed? Each enemy's last attacker (K2_GetLastDamagedByAttacker), the aspect and the player's
--     ammo use in the seconds before it went down are logged.
local PROBE_TABLES = {
    { key = "luaset",  path = "/Game/Datatables/AI/NPC/LuaSet/DT_NPC_LuaSet.DT_NPC_LuaSet",
      src = "NLID_0000_CP",   row = "NLID_SV_Probe" },
    { key = "npc",     path = "/Game/Datatables/AI/NPC/DT_NPC.DT_NPC",
      src = "OP1020_m29a_01", row = "SV_m29a_Probe" },
}
local PROBE_MISSION_ROW = { Pkg = "sv_probe_pkg", Rt = "sv_probe_rt" }   -- in DT_SV_NpcMission (build time)
-- The game's require("A.B.C") loads the LuaScript at /Game/LuaSource/A/B/C with StaticLoadObject and runs its Code
-- (AceCombat8.exe 0x144eb8ce0), so the packaged script sits at that path. The run-time one is put straight into the
-- game's Lua (package.loaded, section "the game's own Lua"), so its LuaScript object only carries the module name.
local PROBE_PKG_SCRIPT = "/Game/LuaSource/SurvivalMode/AI/LA_SV_ProbePursue.LA_SV_ProbePursue"
local PROBE_PKG_MODULE = "SurvivalMode.AI.LA_SV_ProbePursue"
local PROBE_RT_MODULE  = "SurvivalMode.AI.LA_SV_ProbePursueRt"
local PR = { ready = {}, usable = {}, scripts = {}, tries = 0, ammo = {} }   -- rows stay in the tables across levels
local SR = { ready = {}, usable = {}, tries = 0 }   -- enemy search rows (section "enemy search" below)
-- Difficulty spikes (CFG.spikes): the level of round `round` (0 = none yet), its settings, and its rows' suffix.
local SPIKE_SUFFIX = { [0] = "", "b", "c", "d" }      -- tools/build_survival.py SPIKE_SUFFIXES
-- CFG.aces' airframes per tier (tools/build_survival.py ACES, same keys) and their rows: a lead and a wing mission row
-- (sv_ace_<tier>_<key>_l / _w, with _sv[b|c|d] copies like the search aircraft), DT_NPC rows SV_Ace_<tier>_<key>_L / _W
-- (DT_SV_NpcRows, added at the main menu) and text keys SV_Ace_<tier>_<key> (the ace) / SV_Sqn_<tier> (the squadron).
local ACE = {
    roster = { mercenary = { "f15c", "su35", "typhoon" }, legend = { "su47", "rafale" }, demon = { "f22a", "su57" },
               phantom = { "su57", "typhoon", "su47" }, reaper = { "su57", "f22a", "typhoon", "rafale", "adfx02" },
               anomaly = { "f04e" } },             -- the Anomaly's MINDRIPPER and guards (not a tier: never a flight's)
    row = function(tier, key, part) return "sv_ace_" .. tier .. "_" .. key .. "_" .. part end,
    -- airframes from Online Mode (tools/build_survival.py ACE_MODELS): their model row (DT_SV_ModelRows) goes into the
    -- campaign's DT_NPC_Model first, and their name (the model's GameObjectDisplayName01) is Survival's text
    models = { adfx02 = { row = "SV_Model_adfx", key = "SV_Ac_adfx", name = "ADFX-02" } },
    model_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_ModelRows.DT_SV_ModelRows",
    model_table = "/Game/Datatables/AI/NPC/Model/DT_NPC_Model.DT_NPC_Model",
}
local function spikeLevel(round)
    local sp = CFG.spikes
    if not sp.enabled or not round or round < 1 or #sp.levels == 0 then return 0 end
    return math.min(#sp.levels, #SPIKE_SUFFIX, (round - 1) // math.max(1, math.floor(sp.every)))
end
local function spikeCfg(level) return level > 0 and CFG.spikes.levels[level] or {} end
-- The tier index (CFG.tiers.list) a flight spawning in round `round` flies: the round's, one higher at promote_chance.
local function pickTier(round)
    local tc, i = CFG.tiers, 1
    for k, t in ipairs(tc.list) do if math.max(round or 1, 1) >= t.from_round then i = k end end
    if i < #tc.list and math.random() < tc.promote_chance then i = i + 1 end
    return i
end
local function withLevel(base, over)                    -- a copy of `base` with `over`'s fields
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end

local function scriptDir() return debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "" end

local function readScript(file)
    local f = io.open(scriptDir() .. "ai\\" .. file, "r")
    if not f then return nil, "Scripts\\ai\\" .. file .. " not found" end
    local code = f:read("a"); f:close()
    return code
end

---------------------------------------------------------------------------------------------------- the game's own Lua
-- dlls/main.dll 0.8.0 (tools/re/GAME_LUA.md): SV_GameLua(code, name) runs a chunk in the game's Lua 5.3, the state
-- its AI behaviour scripts are built in, and returns "<status>\t<result>"; SV_GameLuaState() its address (0 while
-- the game has none). The plugin swallows every error in a behaviour script (its log is stripped from the shipping
-- game), so Survival installs a small helper there (SV_Instrument / SV_Report) that wraps a behaviour class's Ctor:
-- each build is counted and each error kept with its traceback (then raised as before). Run-time scripts are put in
-- package.loaded under their module name, which require() returns before it looks for an asset at all.
local GLS = { L = 0, injected = {}, report = nil, created = false }
local GAME_LUA_HELPER = [=[
SV_B = SV_B or { built = {}, errors = {}, nerr = 0 }
function SV_Instrument(name, C)
    if type(C) ~= "table" or rawget(C, "__sv_wrapped") then return C end
    local ctor = rawget(C, "Ctor")
    if type(ctor) == "function" then
        rawset(C, "Ctor", function(self, ...)
            SV_B.built[name] = (SV_B.built[name] or 0) + 1
            local ok, err = xpcall(ctor, debug and debug.traceback or tostring, self, ...)
            if not ok then
                SV_B.nerr = SV_B.nerr + 1
                if #SV_B.errors < 20 then SV_B.errors[#SV_B.errors + 1] = name .. ": " .. tostring(err) end
                error(err, 0)
            end
        end)
    end
    rawset(C, "__sv_wrapped", true)
    return C
end
function SV_Report()
    local t = {}
    for k, v in pairs(SV_B.built) do t[#t + 1] = k .. " x" .. v end
    table.sort(t)
    local s = "built " .. (#t > 0 and table.concat(t, ", ") or "nothing yet") .. "; errors " .. SV_B.nerr
    for i, e in ipairs(SV_B.errors) do s = s .. "\n    [" .. i .. "] " .. e end
    return s
end
return "helper in"
]=]
local GAME_LUA_DIAG = [=[
local function ty(f) local ok, v = pcall(f); return ok and type(v) or ("error: " .. tostring(v)) end
local n, ai = 0, 0
for k in pairs(package.loaded) do n = n + 1; if type(k) == "string" and k:find("^Chronicle%.AI%.") then ai = ai + 1 end end
return table.concat({ _VERSION, "io " .. type(io), "os " .. type(os), "debug " .. type(debug),
    "Inherit " .. ty(function() return Inherit end), "CppObjectBase " .. ty(function() return CppObjectBase end),
    "ELiveAIManeuverSpeedType " .. ty(function() return ELiveAIManeuverSpeedType end),
    "modules loaded " .. n .. " (" .. ai .. " Chronicle.AI)" }, ", ")
]=]
-- Stock scripts instrumented too, to compare: the root tree of every enemy plane and the two pursue scripts in use.
local GAME_LUA_STOCK = { "Chronicle.AI.LA_AIPlane", "Chronicle.AI.LA_PursueTarget_0011", "Chronicle.AI.LA_PursueTarget_0400",
                         "SurvivalMode.AI.LA_SV_MoveAway", "SurvivalMode.AI.LA_SV_TailChase",
                         "SurvivalMode.AI.LA_SV_ProvokeNear", "SurvivalMode.AI.LA_SV_Escape" }   -- ours too: builds and errors
local REQUIRE_AND_WRAP = "local ok, C = pcall(require, %q); if ok then SV_Instrument(%q, C) end; " ..
                         "return tostring(ok) .. ' ' .. tostring(C)"

local function gameLua(code, name)
    if type(SV_GameLua) ~= "function" then return false, "no SV_GameLua (dlls/main.dll older than 0.8.0)", -5 end
    local r = SV_GameLua(code, name or "SurvivalMode")
    local st, res = tostring(r):match("^(%-?%d+)\t(.*)$")
    st = tonumber(st)
    return st == 0, res or tostring(r), st
end

-- Puts a behaviour script into the game's Lua as module `mod` (instrumented). true, or false and the error.
local function gameLuaInject(mod, code)
    local short = mod:match("([^%.]+)$")
    local chunk = "local C = (function(...)\n" .. code .. "\nend)(...)\n" ..
        string.format("package.loaded[%q] = SV_Instrument(%q, C)\nreturn tostring(package.loaded[%q])", mod, short, mod)
    local ok, res = gameLua(chunk, mod)
    if ok then GLS.injected[mod] = true end
    return ok, res
end

-- Sets Survival up in a (new) game Lua state: diagnostics, the helper, the stock scripts wrapped, and our scripts.
local function gameLuaSetup()
    local ok, res = gameLua(GAME_LUA_DIAG, "SurvivalDiag")
    log("game Lua: " .. (ok and "" or "diagnostics failed: ") .. tostring(res))
    ok, res = gameLua(GAME_LUA_HELPER, "SurvivalHelper")
    log("game Lua: " .. tostring(res))
    if not ok then return end
    for _, m in ipairs(GAME_LUA_STOCK) do
        local _, resS = gameLua(string.format(REQUIRE_AND_WRAP, m, m:match("([^%.]+)$")), "SurvivalStock")
        log("game Lua: stock " .. m .. ": " .. tostring(resS))
    end
    if not CFG.probe.behaviour then return end           -- the behaviour probe is off: its scripts aren't needed
    -- The packaged script through the game's own loader (the asset route); put in directly if that fails.
    local okP, resP = gameLua(string.format(REQUIRE_AND_WRAP, PROBE_PKG_MODULE, "LA_SV_ProbePursue"), "SurvivalPkg")
    log("game Lua: packaged script via the game's require: " .. tostring(resP))
    local code = readScript("LA_SV_ProbePursue.lua")
    if okP and tostring(resP):sub(1, 5) == "true " then GLS.injected[PROBE_PKG_MODULE] = true
    elseif code then
        local okI, resI = gameLuaInject(PROBE_PKG_MODULE, code)
        log("game Lua: packaged script put in directly instead: " .. tostring(resI) .. (okI and "" or " (FAILED)"))
    end
    if code then
        local okR, resR = gameLuaInject(PROBE_RT_MODULE, (code:gsub("LA_SV_ProbePursue", "LA_SV_ProbePursueRt")))
        log("game Lua: run-time script " .. PROBE_RT_MODULE .. ": " .. tostring(resR) .. (okR and "" or " (FAILED)"))
    end
end

-- From the main menu on (every second; levelSince = ticks since Survival's level loaded, or nil): notices the game's
-- Lua state, sets Survival up in it, and in the level logs the helper's report when it changes (every 10 s).
local function gameLuaTick(tick, levelSince)
    if type(SV_GameLuaState) ~= "function" then
        if not GLS.warned then GLS.warned = true; log("game Lua: dlls/main.dll older than 0.8.0; no bridge") end
        return
    end
    local L = SV_GameLuaState()
    if L == 0 and levelSince and levelSince >= 12 and not GLS.created then   -- 3 s into Survival's level, still none
        GLS.created = true
        L = SV_GameLuaState(1)
    end
    if L ~= GLS.L then
        GLS.L, GLS.injected, GLS.report = L, {}, nil
        if L == 0 then log("game Lua: no state"); return end
        log(string.format("game Lua: state %X%s", L, levelSince and " (in Survival's level)" or ""))
        gameLuaSetup()
    end
    if L ~= 0 and levelSince and tick % 40 == 0 then
        local ok, res = gameLua("return SV_Report and SV_Report() or 'no helper'", "SurvivalReport")
        if res ~= GLS.report then GLS.report = res; log("game Lua: " .. (ok and "" or "report failed: ") .. tostring(res)) end
    end
end

-- Route 2: a LuaScript object made at run time; it only has to carry the module name (LuaInitializePath), which the
-- game's require finds in package.loaded (gameLuaInject). Its outer is the GameInstance (test 20: making a package
-- from UE4SS crashed the game).
local function runtimeScript()
    if valid(PR.scripts.rt) then return PR.scripts.rt end
    local code, why = readScript("LA_SV_ProbePursue.lua")
    if not code then return nil, why end
    code = code:gsub("LA_SV_ProbePursue", "LA_SV_ProbePursueRt")
    local cls = StaticFindObject("/Script/LuaPluginRuntime.LuaScript")
    if not valid(cls) then return nil, "class /Script/LuaPluginRuntime.LuaScript not found" end
    local o = StaticConstructObject(cls, gameInstance(), FName("SV_LA_ProbePursueRt"))
    if not valid(o) then return nil, "StaticConstructObject(LuaScript) returned nothing" end
    o.Code = code
    o.ImportPath = "../../AssetWork/LuaSource/SurvivalMode/AI/LA_SV_ProbePursueRt.lua"
    o.LuaInitializePath = PROBE_RT_MODULE
    log(string.format("probe: run-time LuaScript %s made (module %s)", nameOf(o), PROBE_RT_MODULE))
    pin(o, "probe LuaScript (run time)")
    PR.scripts.rt = o
    return o
end

local function packageScript()
    if valid(PR.scripts.pkg) then return PR.scripts.pkg end
    local o, why = loadObject(PROBE_PKG_SCRIPT)
    if not o then return nil, why end
    pin(o, "probe LuaScript (package)")
    PR.scripts.pkg = o
    return o
end

-- Adds row `new` to dt as a copy of `src` and lets edit(row) change the copy (in place: FindRow returns the row).
local function cloneRow(dt, src, new, edit)
    local _, have = dtCall(dt, "FindRow", new)
    if have ~= nil then return true end
    local okS, srow = dtCall(dt, "FindRow", src)
    if not okS or srow == nil then return false, "no row " .. src end
    dtCall(dt, "AddRow", new, srow)
    local _, row = dtCall(dt, "FindRow", new)
    if row == nil then return false, "AddRow did not add " .. new end
    local ok, err = pcall(edit, row)
    if not ok then dtCall(dt, "RemoveRow", new); return false, tostring(err) end
    return true
end

-- One variant ("Pkg" / "Rt"): LuaSet row -> NPC row (the mission row pointing at it is built in). true when in.
local function probeVariant(tables, v, script)
    local names = { luaset = PROBE_TABLES[1].row .. v, npc = PROBE_TABLES[2].row .. v, mission = PROBE_MISSION_ROW[v] }
    local steps = {
        { tables.luaset, PROBE_TABLES[1].src, names.luaset, function(r) r.LuaAsetts.PursueTargetLua.LuaScript = script end },
        { tables.npc, PROBE_TABLES[2].src, names.npc, function(r)
            r.LuaSetId = FName(names.luaset)
            if SR.module then r.NpcAIModuleId = FName(SR.module) end            -- the enemy search range too
        end },
    }
    for _, s in ipairs(steps) do
        local ok, why = cloneRow(s[1], s[2], s[3], s[4])
        if not ok then return false, s[3] .. ": " .. tostring(why) end
    end
    local check = "?"
    pcall(function()
        local _, r = dtCall(tables.luaset, "FindRow", names.luaset)
        check = nameOf(r.LuaAsetts.PursueTargetLua.LuaScript)
    end)
    log("probe: rows " .. names.luaset .. " / " .. names.npc .. " / " .. names.mission .. " in; pursue slot = " .. check)
    return true, names.mission
end

-- Called every second from the start (main menu included) until both variants are in (or 20 tries failed).
local function probeSetup()
    if not CFG.probe.enabled or not CFG.probe.behaviour or (PR.ready.Pkg and PR.ready.Rt) or PR.tries >= 20 then return end
    if not gameInstance() then return end                  -- the run-time script's outer, and where tables get pinned
    if CFG.search.enabled and not SR.done then return end  -- the probe's NPC rows take the search module row
    PR.tries = PR.tries + 1
    local tables = {}
    for _, t in ipairs(PROBE_TABLES) do
        local dt, why = loadObject(t.path)
        if not dt then
            if PR.tries == 20 then log("probe: table " .. t.path .. " not loaded (" .. tostring(why) .. "); no behaviour probe") end
            return
        end
        pin(dt, nameOf(dt))
        tables[t.key] = dt
    end
    PR.tables = tables
    -- Each variant on its own (test 18: an error making the run-time script also kept the package one from flying).
    PR.failed = PR.failed or {}
    for _, v in ipairs({ "Pkg", "Rt" }) do
        if v == "Rt" and not CFG.probe.runtime then PR.failed[v] = true end
        if not PR.ready[v] and not PR.failed[v] then
            local okV, err = pcall(function()
                local script, why = (v == "Pkg" and packageScript or runtimeScript)()
                if script then
                    local ok, res = probeVariant(tables, v, script)
                    if ok then PR.ready[v] = res else log("probe: " .. v .. " rows not added: " .. tostring(res)); PR.failed[v] = true end
                else log("probe: " .. v .. " script not available: " .. tostring(why)); PR.failed[v] = true end
            end)
            if not okV then log("probe: " .. v .. " setup error " .. tostring(err)); PR.failed[v] = true end
        end
    end
    if (PR.ready.Pkg or PR.failed.Pkg) and (PR.ready.Rt or PR.failed.Rt) then PR.tries = 20 end
end

-- The probe aircraft for this round's first flight (odd rounds: package script, even rounds: run-time script).
---------------------------------------------------------------------------------------------------- enemy search
-- CFG.search: Survival's AI module row NPC_AIModule_SV_Search (a copy of NPC_AIModule_Plane000 with CFG.search's
-- radius and cloud rule) is added to DT_NPC_AIModule, and for every aircraft in CFG.aircraft a copy of its DT_NPC row
-- (<NpcId>_SV) that uses it. Survival's NPC table has a mission row <aircraft>_sv pointing at each copy
-- (tools/build_survival.py SEARCH_AIRCRAFT), because the spawner caches that table when the level starts; as with the
-- probe, an aircraft only flies its _sv row when the rows were in before the level loaded.
local SEARCH_MODULE = { path = "/Game/Datatables/AI/NPC/AIModule/DT_NPC_AIModule.DT_NPC_AIModule",
                        src = "NPC_AIModule_Plane000", row = "NPC_AIModule_SV_Search" }
local SV_NPC_MISSION = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"

-- Called every second from the start (main menu included) until done (or 20 tries failed).
-- The fighter flights' behaviour row (tools/survival_events.py POOL_BEHAVIOUR_ROW = BEHAVIOUR_AIRCRAFT .. "_sv"): the
-- world data names it, and the game builds their behaviour from it when the level loads, so its DT_NPC row is made
-- here even when CFG.search is off or CFG.aircraft leaves that aircraft out.
local BEHAVIOUR_AIRCRAFT = "f16c_common"
local FCS_TABLE = "/Game/Datatables/AI/NPC/FCS/DT_NPC_FCS.DT_NPC_FCS"
local WEAPON_TABLE = "/Game/Datatables/AI/NPC/Weapon/DT_NPC_Weapon.DT_NPC_Weapon"

-- Survival's own behaviour sets (CFG.behaviour_sets) into DT_NPC_LuaSet. BS.ready[name] once a set is in.
local BS = { done = false, ready = {}, tries = 0 }
local function setsSetup()
    if BS.done then return end
    if not gameInstance() then return end
    BS.tries = BS.tries + 1
    local ls, why = loadObject(PROBE_TABLES[1].path)
    if not ls then
        if BS.tries >= 20 then BS.done = true; log("behaviour: DT_NPC_LuaSet not loaded (" .. tostring(why) .. "); no own sets") end
        return
    end
    pin(ls, nameOf(ls))
    for name, def in pairs(CFG.behaviour_sets) do
        local scripts, missing = {}, nil
        for slot, sname in pairs(def.slots) do
            local on = (sname ~= "LA_SV_TailChase" or CFG.ai.tail_chase)
                and ((sname ~= "LA_SV_ProvokeNear" and sname ~= "LA_SV_Escape") or CFG.ai.reactions)
            if on then                                      -- (ai.tail_chase / ai.reactions false: the stock scripts)
                local sc = loadObject("/Game/LuaSource/SurvivalMode/AI/" .. sname .. "." .. sname)
                if valid(sc) then pin(sc, "behaviour script " .. sname); scripts[slot] = sc else missing = sname end
            end
        end
        if missing then
            log("behaviour: set " .. name .. " not made (script " .. missing .. " not in the container)")
        else
            local ok, err = cloneRow(ls, def.base, name, function(r)
                for slot, sc in pairs(scripts) do r.LuaAsetts[slot].LuaScript = sc end
            end)
            if ok then
                BS.ready[name] = true
                local parts = {}
                for slot in pairs(scripts) do parts[#parts + 1] = slot .. " = " .. def.slots[slot] end
                table.sort(parts)
                log("behaviour: set " .. name .. " in (" .. def.base .. " with " .. table.concat(parts, ", ") .. ")")
            else
                log("behaviour: set " .. name .. " not made (" .. tostring(err) .. ")")
            end
        end
    end
    BS.done = true
end

local function searchSetup()
    if SR.done then return end
    if not gameInstance() or not BS.done then return end      -- the own sets first: the search rows name them
    SR.tries = SR.tries + 1
    local function giveUp(why) log("search: " .. why .. "; enemies keep the stock 6 km search"); SR.done = true end
    local mod, why1 = loadObject(SEARCH_MODULE.path)
    local npc, why2 = loadObject(PROBE_TABLES[2].path)
    local mission, why3 = loadObject(SV_NPC_MISSION)
    if not (mod and npc and mission) then
        if SR.tries >= 20 then giveUp("tables not loaded (" .. tostring(why1 or why2 or why3) .. ")") end
        return
    end
    for _, t in ipairs({ mod, npc, mission }) do pin(t, nameOf(t)) end
    -- CFG.missiles / guns / special: Survival copies of the fire-control (and gun weapon) rows the fighters use, made
    -- once and shared by every aircraft that uses the same stock row
    local wantFcs = CFG.missiles.enabled or CFG.guns.enabled or CFG.special.enabled
    local fcs = wantFcs and loadObject(FCS_TABLE) or nil
    if fcs then pin(fcs, nameOf(fcs)) elseif wantFcs then log("weapons: DT_NPC_FCS not loaded; stock fire control") end
    local wpn = CFG.guns.enabled and loadObject(WEAPON_TABLE) or nil
    if wpn then pin(wpn, nameOf(wpn)) end
    local made = {}
    local function copy(tbl, src, edit, what, suf)         -- src .. "_SV" .. suf in tbl, edited; its name, or nil
        local new = src .. "_SV" .. (suf or ""):upper()
        if made[new] == nil then
            local ok, why = cloneRow(tbl, src, new, edit)
            made[new] = ok
            log("weapons: " .. src .. " -> " .. new .. " " .. (ok and ("(" .. what .. ")") or ("not made: " .. tostring(why))))
        end
        return made[new] and new or nil
    end
    local function svFcs(src, level)
        local m = withLevel(CFG.missiles, spikeCfg(level).missiles)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.CaptureAngleRange = m.capture_m, m.angle_deg
            r.ActivationTime, r.TriggeringTime = m.arm_s, m.lock_s
            r.ShotIntervalTime, r.RestingTime = m.interval_s, m.rest_s
        end, string.format("missile: lock within %d m / %d deg, arm %.1f s, lock %.1f s, %.1f s between, rest %.1f s",
            m.capture_m, m.angle_deg, m.arm_s, m.lock_s, m.interval_s, m.rest_s), SPIKE_SUFFIX[level])
    end
    local function svGun(src, level)
        local g = withLevel(CFG.guns, spikeCfg(level).guns)
        local rounds
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.CaptureAngleRange = g.range_m, g.angle_deg
            r.TriggeringTime, r.TriggerCount, r.RestingTime = g.aim_s, g.burst, g.rest_s
            if wpn then
                local w = r.NpcWeaponId:ToString()
                rounds = copy(wpn, w, function(x)
                    x.damage = x.damage * g.damage_x
                    x.MaxSpawnAngle = g.spread_deg
                end, string.format("gun rounds: damage x%.1f, spread %.1f deg", g.damage_x, g.spread_deg), SPIKE_SUFFIX[level])
                if rounds then r.NpcWeaponId = FName(rounds) end
            end
        end, string.format("gun: within %d m / %d deg, %.1f s on target, %d-round bursts, rest %.1f s", g.range_m, g.angle_deg,
            g.aim_s, g.burst, g.rest_s), SPIKE_SUFFIX[level])
    end
    local ok, why = cloneRow(mod, SEARCH_MODULE.src, SEARCH_MODULE.row, function(r)
        if not CFG.search.enabled then return end   -- off: the stock module's values
        r.Radius = CFG.search.radius_m
        r.bEnableLostTargetInClouds = CFG.search.lose_in_clouds
    end)
    if not ok then return giveUp("module row not added: " .. tostring(why)) end
    SR.module, SR.npcRow, SR.tables = SEARCH_MODULE.row, {}, { npc = npc }
    local n, list = 0, { BEHAVIOUR_AIRCRAFT }
    for _, a in ipairs(CFG.aircraft) do if a ~= BEHAVIOUR_AIRCRAFT then list[#list + 1] = a end end
    do      -- CFG.aces and the Anomaly's: DT_NPC rows (DT_SV_NpcRows), names. The Anomaly's always: the world data names them
        local mine = loadObject(CFG.specials.shuttle.npc_rows)
        local nAces, names, lost = 0, 0, {}
        if mine then pin(mine, nameOf(mine)) end
        local models = {}                          -- ACE.models key -> its model row is in DT_NPC_Model
        if CFG.aces.online_aircraft then
            local mt, mr = loadObject(ACE.model_table), loadObject(ACE.model_rows)
            for _, t in ipairs({ mt, mr }) do if t then pin(t, nameOf(t)) end end
            for k, m in pairs(ACE.models) do
                local have = nil
                if mt then local _; _, have = dtCall(mt, "FindRow", m.row) end
                if have == nil and mt and mr then
                    local _, r = dtCall(mr, "FindRow", m.row)
                    if r ~= nil then dtCall(mt, "AddRow", m.row, r); _, have = dtCall(mt, "FindRow", m.row) end
                end
                models[k] = have ~= nil
                if have ~= nil and type(SV_SetText) == "function" then SV_SetText(m.key, m.name) end
                log("aces: model " .. m.row .. " (" .. m.name .. ") " .. (have ~= nil and "in DT_NPC_Model" or "NOT added; its aces sit out"))
            end
        end
        for tier, keys in pairs(ACE.roster) do
            local an = CFG.specials.anomaly
            local c = tier == "anomaly" and { squadron = an.guards_name, f04e = an.name } or CFG.aces[tier] or {}
            if tier ~= "anomaly" and not CFG.aces.enabled then keys = {} end
            if type(SV_SetText) == "function" and SV_SetText("SV_Sqn_" .. tier, tostring(c.squadron or tier)) == 1 then names = names + 1 end
            for _, k in ipairs(keys) do
                if type(SV_SetText) == "function" and SV_SetText("SV_Ace_" .. tier .. "_" .. k, tostring(c[k] or k)) == 1 then names = names + 1 end
                for _, part in ipairs(ACE.models[k] and not models[k] and {} or { "L", "W" }) do
                    local row = "SV_Ace_" .. tier .. "_" .. k .. "_" .. part
                    local _, have = dtCall(npc, "FindRow", row)
                    if have == nil and mine then
                        local _, r = dtCall(mine, "FindRow", row)
                        if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
                    end
                    if have ~= nil then list[#list + 1] = ACE.row(tier, k, part:lower()); nAces = nAces + 1
                    else lost[#lost + 1] = row end
                end
            end
        end
        log(string.format("aces: %d rows in DT_NPC, %d names set%s", nAces, names,
            #lost > 0 and ("; missing from DT_SV_NpcRows: " .. table.concat(lost, ", ")) or ""))
    end
    SR.levels = SR.levels or {}
    local nLevels = CFG.spikes.enabled and math.min(#CFG.spikes.levels, #SPIKE_SUFFIX) or 0
    for _, a in ipairs(list) do
        local spw                                          -- its special weapon: the same at every level
        local okA, err = pcall(function()
            local _, base = dtCall(mission, "FindRow", a)
            if base == nil then error("no mission row " .. a .. " in DT_SV_NpcMission") end
            local srcNpc = base.NpcId:ToString()
            for level = 0, nLevels do
                local mname = a .. "_sv" .. SPIKE_SUFFIX[level]
                local _, mrow = dtCall(mission, "FindRow", mname)
                if mrow == nil then error("no mission row " .. mname .. " in DT_SV_NpcMission") end
                local svNpc = mrow.NpcId:ToString()
                local okR, whyR = cloneRow(npc, srcNpc, svNpc, function(r)
                    r.NpcAIModuleId = FName(SR.module)
                    if fcs then                      -- its weapon slots onto Survival's fire control for this level
                        local free
                        for i = 0, 5 do
                            pcall(function()
                                local id = r["NpcFCSId" .. i]:ToString()
                                local new
                                if id:find("^NPC_FCS_PlaneMsl") and CFG.missiles.enabled then new = svFcs(id, level)
                                elseif id:find("^NPC_FCS_PlaneGun") and CFG.guns.enabled then new = svGun(id, level)
                                elseif (id == "None" or id == "") and i >= 3 and not free then free = i end
                                if new then r["NpcFCSId" .. i] = FName(new) end
                            end)
                        end
                        local fcsList = CFG.special.fcs
                        if CFG.special.enabled and free and #fcsList > 0 then
                            spw = spw or fcsList[math.random(#fcsList)]
                            r["NpcFCSId" .. free] = FName(spw)
                            if level == 0 then log("weapons: " .. svNpc .. " carries " .. spw .. " (slot " .. free .. ")") end
                        end
                    end
                    local set = CFG.search.luaset
                    if set and CFG.behaviour_sets[set] and not BS.ready[set] then set = CFG.search.fallback_luaset end
                    if set then r.LuaSetId = FName(set) end
                end)
                if not okR then error(svNpc .. ": " .. tostring(whyR)) end
                if level == 0 then
                    SR.ready[a], SR.npcRow[a], n = mname, svNpc, n + 1
                else
                    SR.levels[a] = SR.levels[a] or {}
                    SR.levels[a][level] = mname
                end
            end
        end)
        if not okA then log("search: " .. a .. " keeps the stock search (" .. tostring(err) .. ")") end
    end
    local check = "?"
    pcall(function()
        local _, r = dtCall(mod, "FindRow", SEARCH_MODULE.row)
        check = string.format("radius %.0f m, lose target in clouds %s", r.Radius, tostring(r.bEnableLostTargetInClouds))
    end)
    pcall(function()
        local a = CFG.aircraft[1]
        local _, r = dtCall(npc, "FindRow", SR.npcRow[a])
        check = check .. string.format("; %s flies behaviour set %s", SR.npcRow[a], r.LuaSetId:ToString())
    end)
    log(string.format("search: module %s (%s); %d of %d aircraft and ace rows use it", SEARCH_MODULE.row, check, n, #list))
    local nl = 0
    for _, t in pairs(SR.levels) do nl = nl + #t end
    log(string.format("spikes: %d difficulty-spike rows made (%d levels)", nl, nLevels))
    if not SR.ready[BEHAVIOUR_AIRCRAFT] then
        log("search: WARNING the fighters' behaviour row " .. BEHAVIOUR_AIRCRAFT .. "_sv has no DT_NPC row; don't start a run")
    end
    SR.done = true
end

-- Comona Defense's shuttle row: DT_SV_NpcRows' OP0057_sstb_01_SV (Mission 22's shuttle with Survival's name key,
-- tools/build_survival.py) goes into DT_NPC from the main menu on, before a level loads (the spawner reads it then),
-- and the name key gets CFG.specials.shuttle.name through the text hook.
local SPS = { done = false, tries = 0 }
local function specialSetup()
    if SPS.done or not gameInstance() then return end
    local c = CFG.specials.shuttle
    SPS.tries = SPS.tries + 1
    local npc, why1 = loadObject(PROBE_TABLES[2].path)
    local mine, why2 = loadObject(c.npc_rows)
    if not (npc and mine) then
        if SPS.tries >= 20 then SPS.done = true; log("special: shuttle row tables not loaded (" .. tostring(why1 or why2) .. ")") end
        return
    end
    pin(npc, nameOf(npc)); pin(mine, nameOf(mine))
    SPS.done = true
    local _, have = dtCall(npc, "FindRow", c.npc_row)
    if have == nil then
        local _, row = dtCall(mine, "FindRow", c.npc_row)
        if row == nil then log("special: " .. c.npc_row .. " missing from DT_SV_NpcRows"); return end
        dtCall(npc, "AddRow", c.npc_row, row)
        _, have = dtCall(npc, "FindRow", c.npc_row)
    end
    local named = type(SV_SetText) == "function" and SV_SetText(c.name_key, c.name) == 1
    log(string.format("special: shuttle row %s %s; its name '%s' %s", c.npc_row, have ~= nil and "in DT_NPC" or "NOT added",
        c.name, named and "set" or "not set (no text slot)"))
end

-- The mission row to fly for aircraft `a`: its _sv row when that was ready before this level loaded.
-- A difficulty spike's pursuit on an enemy (CFG.spikes: provoke_cone_deg / provoke_time_s / surround_m), once.
local enemySpike
do
local spikeSaid = {}
function enemySpike(p, round, tier)
    if p.spiked ~= nil or not round then return end
    local level = spikeLevel(round)
    p.spiked = level
    local sk = withLevel(spikeCfg(level), tier and { provoke_cone_deg = tier.provoke_cone_deg,
        provoke_time_s = tier.provoke_time_s, surround_m = tier.surround_m } or nil)
    if level == 0 and not (tier and tier.provoke_cone_deg) then return end
    local before, writes = {}, {}
    local function set(field, value)
        if value == nil then return end
        local okR, v = pcall(function() return p.obj[field] end)
        before[#before + 1] = field .. " " .. (okR and tostring(v) or "?")
        local okW, e = pcall(function() p.obj[field] = value end)
        writes[#writes + 1] = okW and (field .. " " .. tostring(value)) or (field .. " FAILED: " .. tostring(e))
    end
    set("ProvokeConditionConeAngle", sk.provoke_cone_deg)
    set("ProvokeDeterminationTime", sk.provoke_time_s)
    if sk.surround_m then set("SurroundPursuitMinRange", sk.surround_m[1] * 100); set("SurroundPursuitMaxRange", sk.surround_m[2] * 100) end
    if not spikeSaid[level] then
        spikeSaid[level] = true
        log(string.format("spikes: level %d on %s: was %s; now %s", level, p.name, table.concat(before, ", "), table.concat(writes, ", ")))
    end
end
end

local function searchAircraft(a, level)
    local sv = SR.usable[a]
    if not (sv and SR.tables) then return a end
    local _, have = dtCall(SR.tables.npc, "FindRow", SR.npcRow[a])
    if have ~= nil then
        local lv = level and level > 0 and SR.usableLevels and SR.usableLevels[a] and SR.usableLevels[a][level]
        return lv or sv
    end
    log("search: DT_NPC row " .. SR.npcRow[a] .. " is gone (the table was reloaded?); " .. a .. " flies stock this level")
    SR.usable[a], SR.ready[a], SR.done, SR.tries = nil, nil, false, 0
    return a
end

-- Question 2: PilotRank on each enemy (p from the plane list), called every 2 s while it is up.
-- CFG.tiers: this enemy's tier (by the round, sometimes one higher) and PilotRank, set once when it is first seen up.
local enemyTier
do
local tierSaid = {}
function enemyTier(p, round, flightTier)
    local tc = CFG.tiers
    if p.tier ~= nil or not tc.enabled or not round then return end
    local i = flightTier or pickTier(round)                 -- a fighter flight's was picked at its spawn
    local t = tc.list[i]
    p.tier = t
    local add = tc.rank_add[presetName()] or 0
    local want = math.max(1, math.min(5, t.rank + add, 5))
    local sk = spikeCfg(spikeLevel(round))
    if sk.rank_min then want = math.max(want, math.min(5, sk.rank_min)) end
    local ok0, r0 = pcall(function() return p.obj.PilotRank end)
    local okW, err = pcall(function() p.obj.PilotRank = want end)
    local key = round .. t.name
    if not tierSaid[key] or not okW then
        tierSaid[key] = true
        local lv = ""
        if t.ai_level and type(SV_PlaneLevel) == "function" then     -- the AI level the plane took from its desc
            local okL, l = pcall(function() return SV_PlaneLevel(addrOf(p.obj)) end)
            lv = string.format(", AI level %s (wanted %d)", okL and tostring(l) or "?", t.ai_level * 100)
        end
        log(string.format("tiers: round %d %s (%s): PilotRank %s -> %d%s%s", round, t.name, p.name, ok0 and tostring(r0) or "?",
            want, lv, okW and "" or (" (write failed: " .. tostring(err) .. ")")))
    end
end
end

-- CFG.maneuvers: post-stall permission for this enemy (p from the plane list), set once when it is first seen up:
-- its model must be listed and its tier (enemyTier, run first) must allow post-stall at all.
-- The first plane of each model logs what its blueprint had and what it reads after the write.
local enemyManeuvers
do
local maneuversSaid = {}
function enemyManeuvers(p, round)
    if p.maneuvers or not CFG.maneuvers.enabled then return end
    p.maneuvers = true
    local model = p.name:match("^BP_OP%d+_(%w+)_") or "?"
    local allow = false
    for _, m in ipairs(CFG.maneuvers.post_stall) do if m == model then allow = true end end
    if p.tier and not p.tier.post_stall then allow = false end
    local all = spikeCfg(spikeLevel(round)).post_stall_all      -- a difficulty spike: every airframe
    local function read()
        local okC, c = pcall(function() return p.obj.bCanManeuverPugachevsCobra end)
        local okK, k = pcall(function() return p.obj.bCanManeuverKulbit end)
        return string.format("cobra %s, kulbit %s", okC and tostring(c) or "?", okK and tostring(k) or "?")
    end
    local before = read()
    local ok, err = true, nil
    if all then
        allow = true
        ok, err = pcall(function()
            p.obj.bCanManeuverPugachevsCobra = true
            p.obj.bCanManeuverKulbit = true
        end)
    elseif not allow then                   -- allowed models keep their blueprint's own (test 18: su33 cobra only)
        ok, err = pcall(function()
            p.obj.bCanManeuverPugachevsCobra = false
            p.obj.bCanManeuverKulbit = false
        end)
    end
    local said = model .. (allow and "+" or "-") .. (all and "!" or "")
    if not maneuversSaid[said] then
        maneuversSaid[said] = true
        log(string.format("maneuvers: %s (%s) post-stall %s: was %s, now %s%s", model, p.name, allow and "allowed" or "off",
            before, read(), ok and "" or (" (write failed: " .. tostring(err) .. ")")))
    end
end
end

-- Kill log (for the learning layer later): every 2 s while an enemy is up its heading is kept, and when it goes down
-- the player's aspect, altitude and recent ammo use are logged. (K2_GetLastDamagedByAttacker never named anyone.)
local function probeTrack(p)
    pcall(function() local f = p.obj:GetActorForwardVector(); p.fwd = { X = f.X, Y = f.Y, Z = f.Z } end)
end

local AMMO_SHORT = { [0] = "gun", "msl", "sp1", "sp2", "flr" }

-- AI watch (CFG.ai_watch; user, 2026-10-22: "they fly towards the airfield instead of targeting the player"): every
-- 2 s each enemy's AI state (blackboard key AIState, ELiveAIState) and target (blackboard key TargetActor), logged
-- when either changes, with its distance to the player and to the airfield. (AIStateComponent.LuaAssets is not the set
-- in use: it read LA_MoveAwayFromTarget_0000 on planes whose set was built with LA_SV_MoveAway.)
local AI_STATE = { [0] = "ReturnToWorld", "AvoidObstacle", "AvoidRangeAttack", "Wingman", "ReturnToUnit", "AttackAvoidance",
                   "EscapeFromPursuer", "Blackout", "Provoke", "MoveAwayFromTarget", "PursueTarget", "FollowFormation",
                   "Group", "Patrol", "UniqueAction", "CloudAvoidance", "Idle" }
local function aiWatch(p, you)
    if not CFG.ai_watch then return end
    local st, tgt = "?", "?"
    pcall(function()
        local bb = p.obj.AIStateComponent.BlackboardComponent
        local okS, v = pcall(function() return bb:GetValueAsEnum(FName("AIState")) end)
        if okS and type(v) == "number" then st = AI_STATE[v] or tostring(v) end
        local okT, t = pcall(function() return bb:GetValueAsObject(FName("TargetActor")) end)
        if okT then tgt = valid(t) and (nameOf(t):match("([^%.:]+)$") or "?") or "none" end
    end)
    if st .. "|" .. tgt == p.aiKey then return end
    p.aiKey = st .. "|" .. tgt
    local air = p.at and math.sqrt((p.at.X - AIRFIELD.X) ^ 2 + (p.at.Y - AIRFIELD.Y) ^ 2) / 100000
    log(string.format("ai: %s (%s) %s, target %s; %s km from you, %s km from the airfield", p.name, tostring(p.unit or "?"),
        st, tgt, (p.at and you) and string.format("%.1f", km(p.at, you)) or "?", air and string.format("%.1f", air) or "?"))
end

local function probeKill(p, you)
    if not (CFG.probe.enabled and CFG.probe.kills) then return end
    local aspect, dz = "?", "?"
    if p.at and you and p.fwd then
        local tx, ty, tz = you.X - p.at.X, you.Y - p.at.Y, you.Z - p.at.Z
        local len = math.sqrt(tx * tx + ty * ty + tz * tz)
        if len > 0 then
            local c = (p.fwd.X * tx + p.fwd.Y * ty + p.fwd.Z * tz) / len      -- 1: you were ahead of it, -1: on its tail
            aspect = string.format("%.0f deg off its nose", math.deg(math.acos(math.max(-1, math.min(1, c)))))
        end
        dz = string.format("%+.1f km", (you.Z - p.at.Z) / 100000)
    end
    local used = {}                                                           -- ammo spent in the last ~6 s
    local h = PR.ammo
    for k = 0, 4 do
        local spent = 0
        for i = 2, #h do
            local a, b = h[i - 1][k], h[i][k]
            if a and b and a >= 0 and b >= 0 and b < a then spent = spent + (a - b) end
        end
        if spent > 0 then used[#used + 1] = AMMO_SHORT[k] .. " x" .. spent end
    end
    log(string.format("kill: %s; you were %s away, %s, altitude %s; you fired %s in the last 6 s",
        p.name, p.at and you and string.format("%.1f km", km(p.at, you)) or "?",
        aspect, dz, #used > 0 and table.concat(used, ", ") or "nothing seen"))
end

local ZONE = { X = -707336.0, Y = -261895.0, HALF = 3700000.0 }   -- Mission 22's combat zone (80 km), 3 km margin
local SV_ERR = { [0] = "the game spawned nothing", [-1] = "not in Survival's level", [-2] = "no such unit or aircraft",
                 [-3] = "its last flight is still up", [-4] = "bad arguments", [-5] = "game functions not found" }
local D = nil                      -- the run in progress: { round, state, at, now, queue, spare, up, flown }
-- The run's money and purchases: { credits, earned, spent, bought = { [item] = n },
-- msg = { [item] = last result }, dirty (shop texts need updating) }. Reset when Survival's level loads.
local RUN = { credits = 0, earned = 0, spent = 0, bought = {}, msg = {} }

local function addCredits(n, why)
    if n <= 0 then return end
    RUN.credits, RUN.earned, RUN.dirty = RUN.credits + n, RUN.earned + n, true
    RUN.msg = {}            -- a shop result ("NOT ENOUGH ZOLLARS ...") is stale once the credits change
    log(string.format("credits: +%d (%s), now %d", n, why, RUN.credits))
end

local function nativeReady()
    return type(SV_Spawn) == "function" and type(SV_UnitAlive) == "function" and type(SV_SetAircraft) == "function"
end

---------------------------------------------------------------------------------------------------- round HUD
-- Survival's own HUD layer, built at run time (no widget asset). The game's HUD is laid out on a 3840x2160 canvas
-- (tools/re/HUD_LAYOUT.md), so ours is too: a stock widget blueprint with no script of its own
-- (WBP_HUD_NonGlowMessage_000, its parts collapsed) -> its root canvas -> ScaleBox (scale to fit) -> SizeBox
-- 3840x2160 -> our canvas. The rows copy the mission info panel (HUD typeface 37, spacing -70, white, opacity 0.55) and
-- sit under its TIME / SCORE stack; the callout copies the MessageLayerOne banner (text in a frame of 4 px bars).
-- UUserWidget is Abstract (constructing one directly is fatal in a shipping build), so the widget comes from
-- WidgetBlueprintLibrary.Create, the engine's CreateWidget; TextBlock / Image / CanvasPanel / ScaleBox / SizeBox are
-- concrete and made with StaticConstructObject in its WidgetTree. All of it runs in the one game-thread tick.
local HUD_BASE = "/Game/Blueprints/UI/WBP/HUD4K/Campaign/WBP_HUD_NonGlowMessage_000.WBP_HUD_NonGlowMessage_000_C"
local HUD_FONT = "/Game/UI/Font/UI_FontSet_ja.UI_FontSet_ja"
local DESIGN_W, DESIGN_H = 3840, 2160
local VIS = { Visible = 0, Collapsed = 1, Hidden = 2, HitTestInvisible = 3, SelfHitTestInvisible = 4 }
local H = nil                      -- the HUD layer: { widget, tree, font, rowSlots, round, next, banner, ... }
local AF = {}                      -- the airfield: { full, base, hits, hp, down, downRound, attackRound } (section "airfield")
local hudGen, hudTries, hudOff = 0, 0, false
local hudSaid = {}

local function hudLog(key, msg)    -- once per key per level
    if hudSaid[key] then return end
    hudSaid[key] = true
    log("hud: " .. msg)
end

local function cdo(path) local o = StaticFindObject(path); return valid(o) and o or nil end

local function toText(s)
    local tl = cdo("/Script/Engine.Default__KismetTextLibrary")
    if tl then
        local ok, t = pcall(function() return tl:Conv_StringToText(s) end)
        if ok and t ~= nil then return t end
    end
    return FText(s)
end

local function newWidget(cls, name)
    local c = StaticFindObject("/Script/UMG." .. cls)
    if not valid(c) then error("class UMG." .. cls .. " not found") end
    hudGen = hudGen + 1
    local w = StaticConstructObject(c, H.tree, FName(string.format("SV_%s_%d", name, hudGen)))
    if not valid(w) then error("could not create a " .. cls) end
    return w
end

-- Puts w on a canvas: anchors a0..a1, offsets {left, top, right, bottom}, alignment; auto = size from the content.
local function slotIn(canvas, w, a0, a1, off, align, auto)
    local s = canvas:AddChildToCanvas(w)
    s:SetAnchors({ Minimum = { X = a0[1], Y = a0[2] }, Maximum = { X = a1[1], Y = a1[2] } })
    s:SetAlignment({ X = align[1], Y = align[2] })
    s:SetAutoSize(auto and true or false)
    s:SetOffsets({ Left = off[1], Top = off[2], Right = off[3], Bottom = off[4] })
    return s
end

-- Font for one of our texts: UI_FontSet_ja, then the HUD typeface, size, spacing and glow outline written into the
-- text's own Font and pushed with SetFont (test 13b: that gives the game's HUD face; the SetFont table alone may not).
local function styleText(t, spacing)
    local hc = CFG.hud
    if H.font then t:SetFont({ FontObject = H.font, TypefaceFontName = FName("HUD"), Size = hc.font_size, LetterSpacing = spacing })
    else pcall(function() t.Font.Size = hc.font_size end) end
    local ok, err = pcall(function()
        local f = t.Font
        f.TypefaceFontName = FName("HUD"); f.Size = hc.font_size; f.LetterSpacing = spacing
        t:SetFont(f)
    end)
    if not ok then hudLog("fontfields", "could not set the font fields (" .. tostring(err) .. ")") end
    if hc.glow_size > 0 then
        ok, err = pcall(function()
            local o = t.Font.OutlineSettings
            o.OutlineSize = hc.glow_size
            o.OutlineColor = { R = hc.color[1], G = hc.color[2], B = hc.color[3], A = hc.glow_alpha }
            t:SetFont(t.Font)
        end)
        if not ok then hudLog("glow", "could not set the glow outline (" .. tostring(err) .. ")") end
    end
end

local function newText(name, justify, spacing)
    local t = newWidget("TextBlock", name)
    local hc = CFG.hud
    spacing = spacing or hc.letter_spacing
    styleText(t, spacing)
    t:SetColorAndOpacity({ SpecifiedColor = { R = hc.color[1], G = hc.color[2], B = hc.color[3], A = 1 }, ColorUseRule = 0 })
    t:SetRenderOpacity(hc.opacity)
    t:SetJustification(justify or 0)                 -- ETextJustify: 0 left, 1 centre
    t:SetText(toText(""))
    H.texts[#H.texts + 1] = { w = t, spacing = spacing }
    return t
end

local function newBar(canvas, a0, a1, off)
    local b = newWidget("Image", "Bar")
    local c = CFG.hud.color
    b:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 1 })   -- no brush texture: a plain quad, as the game's bars
    b:SetRenderOpacity(CFG.hud.opacity)
    slotIn(canvas, b, a0, a1, off, { 0, 0 }, false)
end

local function fontFace(t)         -- typeface name a text actually has (for the log)
    local ok, s = pcall(function() return t.Font.TypefaceFontName:ToString() end)
    return ok and s or "?"
end

local function hudBuild(pc)
    local wbl = cdo("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not wbl then error("WidgetBlueprintLibrary not found") end
    local cls, why = loadObject(HUD_BASE)
    if not cls then error("base widget class not loaded (" .. tostring(why) .. ")") end
    local w = wbl:Create(pc, cls, pc)
    if not valid(w) then error("WidgetBlueprintLibrary.Create returned nothing") end
    H = { widget = w, tree = w.WidgetTree, shown = nil, texts = {} }
    local root = H.tree.RootWidget
    for i = root:GetChildrenCount() - 1, 0, -1 do root:GetChildAt(i):SetVisibility(VIS.Collapsed) end   -- its own banner
    local font
    font, why = loadObject(HUD_FONT)
    H.font = font
    if not font then hudLog("font", "HUD font not loaded (" .. tostring(why) .. "); using the default font") end

    local scale = newWidget("ScaleBox", "Scale")
    scale:SetStretch(2)                                     -- EStretch::ScaleToFit
    slotIn(root, scale, { 0, 0 }, { 1, 1 }, { 0, 0, 0, 0 }, { 0, 0 }, false)
    local size = newWidget("SizeBox", "Size")
    size:SetWidthOverride(DESIGN_W); size:SetHeightOverride(DESIGN_H)
    scale:SetContent(size)
    local canvas = newWidget("CanvasPanel", "Canvas")
    size:SetContent(canvas)
    H.canvas = canvas

    local hc = CFG.hud
    -- rows: ROUND, CREDITS, AIRFIELD (with its bar), NEXT ROUND (between rounds)
    H.round = newText("Round"); H.next = newText("Next")
    slotIn(canvas, H.round, { 0, 0 }, { 0, 0 }, { hc.x, hc.y, 0, 0 }, { 0, 0 }, true)
    local rowY = hc.y + hc.line
    H.credits = newText("Credits")
    slotIn(canvas, H.credits, { 0, 0 }, { 0, 0 }, { hc.x, rowY, 0, 0 }, { 0, 0 }, true)
    rowY = rowY + hc.line
    if CFG.airfield.enabled then       -- AIRFIELD: [=====     ] 85
        local ab, airY = hc.airfield_bar, rowY
        rowY = rowY + hc.line
        H.air = newText("Airfield")
        slotIn(canvas, H.air, { 0, 0 }, { 0, 0 }, { hc.x, airY, 0, 0 }, { 0, 0 }, true)
        local bar = newWidget("CanvasPanel", "AirBar")
        slotIn(canvas, bar, { 0, 0 }, { 0, 0 }, { hc.x + ab.x, airY + ab.dy, ab.w, ab.h }, { 0, 0 }, false)
        newBar(bar, { 0, 0 }, { 1, 0 }, { 0, 0, 0, ab.frame })
        newBar(bar, { 0, 1 }, { 1, 1 }, { 0, -ab.frame, 0, ab.frame })
        newBar(bar, { 0, 0 }, { 0, 1 }, { 0, 0, ab.frame, 0 })
        newBar(bar, { 1, 0 }, { 1, 1 }, { -ab.frame, 0, ab.frame, 0 })
        local fill = newWidget("Image", "AirFill")
        local c = CFG.hud.color
        fill:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 1 })
        fill:SetRenderOpacity(CFG.hud.opacity)
        local inset = ab.frame * 2
        H.airFillW, H.airFillH = ab.w - inset * 2, ab.h - inset * 2
        H.airFillSlot = slotIn(bar, fill, { 0, 0 }, { 0, 0 }, { inset, inset, H.airFillW, H.airFillH }, { 0, 0 }, false)
        H.airFill, H.airBar = fill, bar
        H.airNum = newText("AirfieldHP")
        slotIn(canvas, H.airNum, { 0, 0 }, { 0, 0 }, { hc.x + ab.x + ab.w + 20, airY, 0, 0 }, { 0, 0 }, true)
    end
    slotIn(canvas, H.next, { 0, 0 }, { 0, 0 }, { hc.x, rowY, 0, 0 }, { 0, 0 }, true)

    -- callout banner: a box of 4 px bars around centred text, centred at (1920, banner_y), width set per message
    local banner = newWidget("CanvasPanel", "Banner")
    H.bannerSlot = slotIn(canvas, banner, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, hc.banner_y, 390, 69 }, { 0.5, 0.5 }, false)
    newBar(banner, { 0, 0 }, { 1, 0 }, { 0, 0, 0, 4 })        -- top
    newBar(banner, { 0, 1 }, { 1, 1 }, { 0, -4, 0, 4 })       -- bottom
    newBar(banner, { 0, 0 }, { 0, 1 }, { 0, 0, 4, 0 })        -- left
    newBar(banner, { 1, 0 }, { 1, 1 }, { -4, 0, 4, 0 })       -- right
    H.bannerText = newText("BannerText", 1, hc.banner_letter_spacing)
    slotIn(banner, H.bannerText, { 0.5, 0.5 }, { 0.5, 0.5 }, { 0, 0.5, 0, 0 }, { 0.5, 0.5 }, true)
    H.banner = banner
    H.sub = newText("BannerSub", 1, hc.banner_letter_spacing)
    slotIn(canvas, H.sub, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, hc.banner_y + 34 + 40, 0, 0 }, { 0.5, 0 }, true)
    banner:SetVisibility(VIS.Collapsed); H.sub:SetVisibility(VIS.Collapsed)

    w:AddToViewport(hc.zorder)
    w:SetVisibility(VIS.HitTestInvisible)
    H.shown = true
    log(string.format("hud: built (base %s, font %s, typeface %s, %d widgets)", nameOf(w):match("[^%.:]+$") or "?",
        font and "UI_FontSet_ja" or "default", fontFace(H.round), hudGen))
end

local callouts = {}                -- waiting callouts, shown one after another

local function hudCallout(text, sub)   -- shown on the next HUD tick (callers are in roundsTick)
    if #callouts < 4 then callouts[#callouts + 1] = { text = text, sub = sub } end
    log("hud: callout '" .. text .. "'" .. (sub and (" / '" .. sub .. "'") or ""))
end

local function setText(w, key, s)
    if H[key] == s then return end
    H[key] = s
    w:SetText(toText(s))
end

local function clock(s)
    s = math.max(0, math.ceil(s))
    return string.format("%d:%02d", s // 60, s % 60)
end

-- One HUD pass: build when needed, show/hide with the game's HUD, update the rows and the callout.
-- The mission info stack (WBP_HUD_SubWidgets_Parts_CampaignInfo_000): its TIME row (TimerAndGauge) and the score's
-- "/limit" (BorderScoreText). Survival pauses the mission clock (EP MissionStart), so the row would sit at 60:00:00,
-- and the score has no target (user, 2026-10-22: just the score). The TIME row is hidden, not collapsed, so SCORE
-- and TARGET keep their rows; the limit is collapsed, so the score reads on its own. Both are taken from the live
-- panel (FindAllOf also returns the blueprint's template, "..._C:WidgetTree.TimerAndGauge", which isn't on screen),
-- looked up every 2 s and kept that way every pass in case the game shows them again.
local function hideGameInfo(now)
    local hc = CFG.hud
    if not (hc.hide_game_timer or hc.hide_score_limit) then return end
    local have = H.info and #H.info > 0
    for _, e in ipairs(H.info or {}) do if not valid(e.w) then have = false end end
    if not have and (not H.infoAt or now >= H.infoAt) then      -- look again only while they aren't found
        H.infoAt, H.info, H.infoSaid = now + 2, {}, H.infoSaid or {}
        for _, w in ipairs(FindAllOf("WBP_HUD_SubWidgets_Parts_CampaignInfo_000_C") or {}) do
            if liveWidget(w) then                                    -- a live panel, not a blueprint's template
                local function part(n, vis, what)
                    local ok, x = pcall(function() return w:GetWidgetFromName(FName(n)) end)
                    if not (ok and valid(x)) then ok, x = pcall(function() return w[n] end) end   -- the blueprint's variable
                    if ok and valid(x) then H.info[#H.info + 1] = { w = x, vis = vis, what = what } end
                end
                if hc.hide_game_timer then part("TimerAndGauge", VIS.Hidden, "TIME row") end
                if hc.hide_score_limit then part("BorderScoreText", VIS.Collapsed, "score limit") end
            end
        end
    end
    for _, e in ipairs(H.info) do
        if valid(e.w) and e.w:GetVisibility() ~= e.vis then
            e.w:SetVisibility(e.vis)
            if not H.infoSaid[e.what] then H.infoSaid[e.what] = true; log("hud: the game's " .. e.what .. " hidden (" .. nameOf(e.w) .. ")") end
        end
    end
end

local function hudTick(now, paused, pc)
    if hudOff or not CFG.hud.enabled or not D then return end
    if not (H and valid(H.widget)) then
        H = nil
        if not valid(pc) then return end
        hudTries = hudTries + 1
        local ok, err = pcall(hudBuild, pc)
        if not ok then
            log("hud: build failed (try " .. hudTries .. "): " .. tostring(err))
            if H and valid(H.widget) then pcall(function() H.widget:RemoveFromParent() end) end
            H = nil
            if hudTries >= 3 then hudOff = true; log("hud: giving up for this level; rounds go on without the HUD") end
            return
        end
    end
    local pawnOk = false
    pcall(function() pawnOk = valid(pc.Pawn) end)
    local gameHud = true
    pcall(function() local hud = pc:GetHUD(); if valid(hud) then gameHud = hud.bShowHUD end end)
    local show = (not paused) and pawnOk and gameHud
    if show ~= H.shown then
        H.widget:SetVisibility(show and VIS.HitTestInvisible or VIS.Collapsed)
        H.shown = show
        log("hud: " .. (show and "shown" or ("hidden (" .. (paused and "paused" or (not pawnOk and "no player aircraft") or "game HUD off") .. ")")))
    end
    pcall(hideGameInfo, now)
    local t = CFG.hud.text
    setText(H.round, "roundStr", string.format(t.round, math.max(D.round, 1)))
    setText(H.credits, "creditsStr", string.format(t.credits, RUN.credits))
    if H.air and AF.hp then
        setText(H.air, "airStr", AF.down and t.airfield_down_row or t.airfield)
        setText(H.airNum, "airNumStr", AF.down and "" or tostring(AF.hp))
        local shown = not AF.down
        if H.airBarShown ~= shown then H.airBar:SetVisibility(shown and VIS.HitTestInvisible or VIS.Collapsed); H.airBarShown = shown end
        if H.airHp ~= AF.hp then
            H.airHp = AF.hp
            H.airFillSlot:SetSize({ X = math.max(0, H.airFillW * AF.hp / CFG.airfield.hp), Y = H.airFillH })
            local c = AF.hp <= CFG.hud.warn_hp and CFG.hud.warn_color or CFG.hud.color
            H.airFill:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 1 })
        end
    end
    local sp = D.special and D.special.state == "countdown" and D.special
    if D.state == "wait" then
        setText(H.next, "nextStr", string.format(D.round == 0 and t.first_round or t.next_round, clock(D.at - now)))   -- (start_round > 1: NEXT ROUND)
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif sp then                                  -- Comona Defense: the countdown and the shuttle's health
        local hp = shuttleHealth()
        setText(H.next, "nextStr", string.format(t.launch_row, clock(CFG.specials.shuttle.countdown_s - (now - sp.at)), hp or 100))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif D.special and D.special.kind == "anomaly" and D.special.state == "hunt" and D.special.dist then
        local an = CFG.specials.anomaly
        setText(H.next, "nextStr", ANOM.on and t.anomaly_row_field or string.format(t.anomaly_row, an.name:upper(), D.special.dist))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif H.nextShown ~= false then
        H.next:SetVisibility(VIS.Collapsed); H.nextShown = false
    end

    if #callouts > 0 and not H.calloutUntil then
        local c = table.remove(callouts, 1)
        setText(H.bannerText, "bannerStr", c.text)
        -- box width: the text's own width when the game can lay it out now, else ~32 units a letter (measured on the
        -- user's screenshot of 2026-10-22: "BOMBERS INBOUND" overran a 24-a-letter box), plus banner_pad each side
        local hc, w = CFG.hud, #c.text * CFG.hud.banner_char_w
        pcall(function()
            H.bannerText:ForceLayoutPrepass()
            local d = H.bannerText:GetDesiredSize()
            if d and d.X and d.X > 0 then w = math.max(w, d.X) end
        end)
        H.bannerSlot:SetSize({ X = math.max(390, w + 2 * hc.banner_pad), Y = 69 })
        setText(H.sub, "subStr", c.sub or "")
        H.banner:SetRenderOpacity(1); H.sub:SetRenderOpacity(CFG.hud.opacity)
        H.banner:SetVisibility(VIS.HitTestInvisible)
        H.sub:SetVisibility(c.sub and VIS.HitTestInvisible or VIS.Collapsed)
        H.calloutUntil = now + CFG.hud.callout_s
    end
    if H.calloutUntil then
        local left = H.calloutUntil - now
        if left <= 0 then
            H.banner:SetVisibility(VIS.Collapsed); H.sub:SetVisibility(VIS.Collapsed); H.calloutUntil = nil
        else
            local a = CFG.hud.opacity * math.min(1, left / 0.75)                     -- fades over the last 0.75 s
            H.banner:SetRenderOpacity(a / CFG.hud.opacity); H.sub:SetRenderOpacity(a)
        end
    end
end

-- The game clock (seconds, stops while paused), or nil.
local function gameClock(pc)
    local gs = cdo("/Script/Engine.Default__GameplayStatics")
    if not (gs and valid(pc)) then return nil end
    local ok, t = pcall(function() return gs:GetTimeSeconds(pc) end)
    return (ok and type(t) == "number") and t or nil
end

local function gamePaused(pc)
    local gs = cdo("/Script/Engine.Default__GameplayStatics")
    local ok, p = pcall(function() return gs:IsGamePaused(pc) end)
    return ok and p == true
end

-- Runtime HUD reverse engineering: the live HUD's widget tree with each widget's on-screen geometry, to check the
-- static layout (tools/re/hud_layout.py) against the screen. Written to hud_dump.txt in the mod folder.
local DUMP_ROOTS = { "WBP_HUD_Chronicle_MainFlight_000_C" }

local function hudDump(why)
    local pc = FindFirstOf("PlayerController")
    local slib = cdo("/Script/UMG.Default__SlateBlueprintLibrary")
    local wll = cdo("/Script/UMG.Default__WidgetLayoutLibrary")
    local out = { "Survival Mode HUD dump (" .. why .. "), Lua " .. VERSION .. ", " .. os.date() }
    pcall(function()
        local vs = wll:GetViewportSize(pc)
        out[#out + 1] = string.format("viewport %.0f x %.0f px, UI scale %.3f", vs.X, vs.Y, wll:GetViewportScale(pc))
    end)
    local function geom(w)
        local ok, s = pcall(function()
            local g = w:GetCachedGeometry()
            local p, a, l = slib:LocalToAbsolute(g, { X = 0, Y = 0 }), slib:GetAbsoluteSize(g), slib:GetLocalSize(g)
            return string.format("abs (%.0f,%.0f) %.0fx%.0f px, local %.0fx%.0f", p.X, p.Y, a.X, a.Y, l.X, l.Y)
        end)
        local okD, dsz = pcall(function() local d = w:GetDesiredSize(); return string.format(", desired %.0fx%.0f", d.X, d.Y) end)
        return (ok and s or "geometry ?") .. (okD and dsz or "")
    end
    local lines = 0
    local function walk(w, depth)
        if lines > 3000 or depth > 16 or not valid(w) then return end
        lines = lines + 1
        local cls = "?"
        pcall(function() cls = w:GetClass():GetFName():ToString() end)
        local name = nameOf(w):match("([^%.:]+)$") or "?"
        local vis = "?"
        pcall(function() vis = tostring(w:GetVisibility()) end)
        local text = ""
        pcall(function() text = "  text='" .. w:GetText():ToString() .. "'" end)
        out[#out + 1] = string.rep("  ", depth) .. cls .. " " .. name .. "  vis " .. vis .. "  " .. geom(w) .. text
        local okT, tree = pcall(function() return w.WidgetTree end)
        if okT and valid(tree) then
            local okR, r = pcall(function() return tree.RootWidget end)
            if okR then walk(r, depth + 1) end
            return
        end
        local okN, n = pcall(function() return w:GetChildrenCount() end)
        if okN and type(n) == "number" then
            for i = 0, n - 1 do
                local okC, c = pcall(function() return w:GetChildAt(i) end)
                if okC then walk(c, depth + 1) end
            end
        end
    end
    local roots = {}
    for _, cn in ipairs(DUMP_ROOTS) do for _, w in ipairs(FindAllOf(cn) or {}) do roots[#roots + 1] = w end end
    if H and valid(H.widget) then roots[#roots + 1] = H.widget end
    for _, w in ipairs(roots) do
        local inVp = "?"
        pcall(function() inVp = tostring(w:IsInViewport()) end)
        out[#out + 1] = "--- " .. nameOf(w) .. "  in viewport: " .. inVp
        walk(w, 0)
    end
    if #roots == 0 then out[#out + 1] = "no HUD widgets found (classes: " .. table.concat(DUMP_ROOTS, ", ") .. ")" end
    local dir = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "..\\"
    local f = io.open(dir .. "hud_dump.txt", "w")
    if f then
        f:write(table.concat(out, "\n"), "\n"); f:close()
        log("hud dump (" .. why .. "): " .. lines .. " widgets written to " .. dir .. "hud_dump.txt")
    else
        log("hud dump (" .. why .. "): could not write the file, logging it instead")
        for _, l in ipairs(out) do log("hud dump: " .. l) end
    end
end

-- A random point distance_km from the airfield, inside the combat zone; returns x, y (cm), distance (km), bearing.
local function spawnPoint(range)
    range = range or CFG.distance_km
    local lo, hi = range[1], range[2]
    for _ = 1, 30 do
        local b, d = math.random() * 360, lo + math.random() * (hi - lo)
        local x = AIRFIELD.X + d * 100000 * math.cos(math.rad(b))
        local y = AIRFIELD.Y + d * 100000 * math.sin(math.rad(b))
        if math.abs(x - ZONE.X) < ZONE.HALF and math.abs(y - ZONE.Y) < ZONE.HALF then return x, y, d, b end
    end
    return AIRFIELD.X, AIRFIELD.Y + lo * 100000, lo, 90
end

local HEAVY_UNIT = {}
for _, u in ipairs(CFG.airfield.bombers.heavy_units) do HEAVY_UNIT[u] = true end

-- A bomber flight (CFG.airfield.bombers): its event-package orders send it at the airfield only.
local function spawnBomber(unit)
    local b = CFG.airfield.bombers
    local heavy = HEAVY_UNIT[unit]
    local list = heavy and b.heavy or b.aircraft
    local ac = list[math.random(#list)]
    -- strike aircraft spawn on their Survival row (search range + Survival's missile fire control); their behaviour
    -- stays the strike set the world data gave the flight (survival_events.STRIKE_BEHAVIOUR_ROW)
    if not heavy then ac = searchAircraft(ac, spikeLevel(D.round)) end
    local set = SV_SetAircraft(unit, ac)
    local x, y, dist, bearing = spawnPoint(b.distance_km)
    local band = heavy and b.altitude_m or b.strike_altitude_m
    local alt = band[1] + math.random() * (band[2] - band[1])
    spawningUnit = unit
    local r = SV_Spawn(unit, x, y, alt * 100, (bearing + 180) % 360)
    spawningUnit = nil
    log(string.format("round %d: bomber flight %s as %s (%s set), %.0f km out at bearing %.0f, %.1f km up: %s", D.round,
        unit, ac, tostring(set), dist, bearing, alt / 1000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    D.heavy = D.heavy or {}
    D.heavy[unit] = HEAVY_UNIT[unit] or nil
    if r > 0 then
        D.up[unit], D.flown[unit] = true, true
        if D.bomberCallout ~= D.round and not D.special then      -- (a special's strike flights: its own callout)
            D.bomberCallout = D.round
            hudCallout(CFG.hud.text.bombers, CFG.hud.text.bombers_sub)
        end
    end
    return r
end

local BOMBER_UNIT, BOMBER_INDEX = {}, {}           -- BOMBER_INDEX: the flight's RE_SV_BombRun_NN
for i, u in ipairs(CFG.airfield.bombers.pool) do BOMBER_UNIT[u], BOMBER_INDEX[u] = true, i end

local PROBE_OF = {}                           -- probe flight -> "Pkg" / "Rt"
for v, u in pairs(CFG.probe.units) do PROBE_OF[u] = v end

-- CFG.aces: tier `tk`'s squadron for flight `unit` (its wing row, and the lead row of an ace that isn't up already), or
-- nil (no line-up for this tier, or its rows weren't in before this level loaded: the spawner only knows those).
function ACE.flight(unit, tk, level)
    local keys = ACE.roster[tk]
    if not (keys and CFG.aces.enabled) then return nil end
    D.aceOf = D.aceOf or {}
    D.aceOf[unit] = nil                                         -- what this flight flew last time is down or recycled
    local opts = {}
    for _, k in ipairs(keys) do if SR.usable[ACE.row(tk, k, "w")] then opts[#opts + 1] = k end end
    if #opts == 0 then return nil end
    local k = opts[math.random(#opts)]
    local f, id = { wing = searchAircraft(ACE.row(tk, k, "w"), level), tier = tk, key = k }, tk .. "_" .. k
    for u, a in pairs(D.aceOf) do
        if a == id and (SV_UnitAlive(u) or 0) > 0 then return f end   -- that ace is up: wingmen only
    end
    if SR.usable[ACE.row(tk, k, "l")] then
        f.lead, f.id, D.aceOf[unit] = searchAircraft(ACE.row(tk, k, "l"), level), id, id
    end
    return f
end

local function spawnFlight(unit)
    if BOMBER_UNIT[unit] then return spawnBomber(unit) end
    local ti = CFG.tiers.enabled and pickTier(D.round) or nil
    local tier = ti and CFG.tiers.list[ti] or {}
    D.flightTier = D.flightTier or {}
    D.flightTier[unit] = ti
    local fcsLevel = math.max(spikeLevel(D.round), tier.fcs or 0)
    local ac = searchAircraft(CFG.aircraft[math.random(#CFG.aircraft)], fcsLevel)
    local ace = tier.name and ACE.flight(unit, tier.name:lower(), fcsLevel)
    if ace then ac = ace.wing end
    local pv = PROBE_OF[unit]
    if pv then                                     -- its behaviour was built from the probe row at level load
        ac = PROBE_MISSION_ROW[pv]
        log(string.format("probe: round %d's first flight %s flies %s (%s script)", D.round, unit, ac,
            pv == "Pkg" and "package" or "run-time"))
    end
    local set = SV_SetAircraft(unit, ac)
    if ace and ace.lead then SV_SetAircraft(unit, ace.lead, 0) end        -- the first aircraft: the ace
    if type(SV_SetLevel) == "function" then SV_SetLevel(unit, (tier.ai_level or 2) * 100) end   -- every spawn: descs are reused
    local x, y, dist, bearing = spawnPoint()
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    spawningUnit = unit
    local r = SV_Spawn(unit, x, y, alt * 100, (bearing + 180) % 360)          -- facing the airfield
    spawningUnit = nil
    log(string.format("round %d: %s%s as %s (%s set, %s), %.0f km out at bearing %.0f, %.1f km up: %s", D.round, unit,
        D.flown[unit] and " (flown before, recycled)" or "", ac, tostring(set), tier.name or "no tier", dist, bearing, alt / 1000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r > 0 then
        D.up[unit], D.flown[unit] = true, true
        D.orders = D.orders or {}
        D.orders[unit] = { at = D.now + CFG.orders_check_s, tries = 0 }       -- ordersTick checks it got them
        if ace then
            local c = CFG.aces[ace.tier] or {}
            local name = ace.lead and tostring(c[ace.key] or ace.key)
            log(string.format("aces: %s is %s squadron (%s)%s", unit, tostring(c.squadron), ace.key,
                name and (", led by " .. name .. " (" .. ace.lead .. ")") or ", no ace (already up)"))
            D.aceSaid = D.aceSaid or {}
            if name and CFG.aces.callout and not D.aceSaid[ace.id] then
                D.aceSaid[ace.id] = true
                local t = CFG.hud.text
                hudCallout(string.format(t.ace, name:upper()), string.format(t.ace_sub, tostring(c.squadron):upper(), tier.name:upper()))
            end
        end
    end
    return r
end

local function shuffled(t)
    for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
    return t
end

-- A round's flights: those that have flown before come first (the spawner recycles them, which keeps the game's unit
-- list short); the rest are spares, fresh ones first, for a flight that fails to spawn.
-- A flight's aircraft count (tools/survival_events.py flight_size: bombers by table, fighters by their _AirN suffix).
local function flightSize(unit)
    return CFG.airfield.bombers.sizes[unit] or ({ ["0"] = 2, ["1"] = 4, ["2"] = 6 })[unit:sub(-1)] or 2
end

-- Up to `budget` aircraft from `units` (free ones only), in squadrons of the sizes allowed this round, flights that
-- have flown before first within a size (the spawner recycles them, which keeps the game's unit list short).
-- Returns the flights and the aircraft they hold.
local function pickFlights(units, budget, skip)
    local allowed, bySize = {}, {}
    for _, q in ipairs(CFG.squadrons) do if D.round >= q.from_round then allowed[q.size] = true end end
    for _, u in ipairs(units) do
        local n = flightSize(u)
        if allowed[n] and not D.up[u] and not (skip and skip(u)) then
            bySize[n] = bySize[n] or { flown = {}, fresh = {} }
            local t = D.flown[u] and bySize[n].flown or bySize[n].fresh
            t[#t + 1] = u
        end
    end
    for _, b in pairs(bySize) do shuffled(b.flown); shuffled(b.fresh) end
    local out, left = {}, budget
    while left >= 2 do
        local options = {}
        for n, b in pairs(bySize) do if n <= left and #b.flown + #b.fresh > 0 then options[#options + 1] = n end end
        if #options == 0 then break end
        local b = bySize[options[math.random(#options)]]
        out[#out + 1] = table.remove(#b.flown > 0 and b.flown or b.fresh)
        left = left - flightSize(out[#out])
    end
    return out, budget - left
end

---------------------------------------------------------------------------------------------------- special rounds
-- The special round `round` is (CFG.specials), or nil for a normal round.
local function specialFor(round)
    local sp = CFG.specials
    local every = math.max(1, math.floor(sp.every))
    if not sp.enabled or #sp.rotation == 0 or round < sp.first or (round - sp.first) % every ~= 0 then return nil end
    return sp.rotation[((round - sp.first) // every) % #sp.rotation + 1]
end

-- Comona Defense: the pad (once a run: its guns and SAMs stay up between specials) and the shuttle, both where the
-- world data puts them (SV_Spawn without a position). The shuttle's appearance starts the event package's countdown.
local function spawnShuttle()
    local c = CFG.specials.shuttle
    for _, u in ipairs({ c.dummies, c.pad_allies and c.pad or nil }) do
        if u and SV_UnitAlive(u) <= 0 then
            local p = SV_Spawn(u)
            log("special: pad " .. u .. ": " .. (p > 0 and (p .. " objects up") or ("not spawned (" .. (SV_ERR[p] or tostring(p)) .. ")")))
        end
    end
    SHUTTLE.obj = nil
    spawningUnit = c.unit
    local r = SV_Spawn(c.unit)
    spawningUnit = nil
    log("special: shuttle " .. c.unit .. ": " .. (r > 0 and "on the pad" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r <= 0 then D.special = nil; return r end            -- a normal round, then
    D.special.state, D.special.at = "countdown", D.now
    return r
end

-- The shuttle's health in % (its actor's HealthInternal is health x 10), or nil when it can't be read.
function shuttleHealth()                  -- the local declared with SHUTTLE
    if not valid(SHUTTLE.obj) then
        SHUTTLE.obj = nil
        if D and D.special and D.now and (SHUTTLE.lookAt or -100) + 2 <= D.now then
            SHUTTLE.lookAt = D.now
            local o = FindFirstOf("BP_OP0057_sstb_CP_C")
            if valid(o) and not nameOf(o):find("Default__", 1, true) then SHUTTLE.obj = o end
        end
        if not SHUTTLE.obj then return nil end
    end
    local ok, pct = pcall(function()
        local max = SHUTTLE.obj.MaxHealth
        return max > 0 and math.max(0, math.floor(SHUTTLE.obj.HealthInternal / 10 / max * 100 + 0.5)) or nil
    end)
    return ok and pct or nil
end

-- The Anomaly (CFG.specials.anomaly; tools/survival_events.py ANOMALY_*): MINDRIPPER and its guards, spawned as one
-- special ("@anomaly" in the queue), and its field: within field_km the player's controls invert (dlls/main.dll
-- SV_SetControlInvert on the player's plane) and RE_SV_AnomalyFieldOn / Off switch the stock glasses effect and radar
-- noise; the event package does the start (MISSION UPDATE beep, WARNING, focus camera) and the end when it's down.
do
local function inverted(c, axis) return c.invert == "both" or c.invert == axis end
local function setField(on, s)
    if ANOM.on == on then return end
    ANOM.on = on
    local c, t = CFG.specials.anomaly, CFG.hud.text
    local r = "no runtime"
    if type(SV_SetControlInvert) == "function" then        -- off keeps the plane, so the controls fade back
        r = SV_SetControlInvert(on and inverted(c, "pitch") and 1 or 0, on and inverted(c, "roll") and 1 or 0, c.fade_s,
                                ANOM.pawn or 0)
    end
    if type(SV_Event) == "function" then SV_Event(on and "RE_SV_AnomalyFieldOn" or "RE_SV_AnomalyFieldOff") end
    if s and s.state == "hunt" then hudCallout(on and t.anomaly_field or t.anomaly_clear, on and t.anomaly_field_sub or nil) end
    log(string.format("special: anomaly field %s (%s, %.1f km; SV_SetControlInvert %s)", on and "ON" or "off",
        on and c.invert or "controls back", s and s.dist or -1, tostring(r)))
end
ANOM.setField = setField

-- MINDRIPPER on its row (the F-4E, at the top fire-control level), its guards beside it; false if it can't come.
function ANOM.spawn()
    local c = CFG.specials.anomaly
    local lead, wing = ACE.row("anomaly", "f04e", "l"), ACE.row("anomaly", "f04e", "w")
    if not (SR.usable[lead] and SR.usable[wing]) then
        log("special: anomaly rows weren't in before this level loaded; a normal round instead")
        return false
    end
    local level = #SPIKE_SUFFIX
    local x, y, dist, bearing = spawnPoint()
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local top = #CFG.tiers.list
    D.flightTier = D.flightTier or {}
    for k, part in ipairs({ { c.unit, lead }, { c.guard_unit, wing } }) do
        local unit, row = part[1], part[2]
        local set = SV_SetAircraft(unit, searchAircraft(row, level))
        if type(SV_SetLevel) == "function" then SV_SetLevel(unit, c.ai_level * 100) end
        local off = (k - 1) * c.guard_offset_m * 100
        spawningUnit = unit
        local r = SV_Spawn(unit, x + off, y + off, alt * 100, (bearing + 180) % 360)
        spawningUnit = nil
        log(string.format("special: anomaly %s as %s (%s set), %.0f km out at bearing %.0f, %.1f km up: %s", unit, row,
            tostring(set), dist, bearing, alt / 1000, r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
        if r > 0 then
            D.up[unit], D.flown[unit], D.flightTier[unit] = true, true, top
        elseif k == 1 then
            return false
        end
    end
    local pawn = valid(survivalPC) and survivalPC.Pawn
    ANOM.pawn = pawn and addrOf(pawn) or nil
    local t = CFG.hud.text
    hudCallout(string.format(t.anomaly_warn, c.name:upper()), t.anomaly_warn_sub)
    return true
end

-- Every tick of a running Anomaly: its distance (the field) and its end.
function ANOM.tick(now, s)
    if s.state ~= "hunt" then return end
    local c, t = CFG.specials.anomaly, CFG.hud.text
    if SV_UnitAlive(c.unit) <= 0 then
        s.state = "done"
        setField(false, s)
        if type(SV_Event) == "function" then SV_Event("RE_SV_AnomalyEnd") end
        addCredits(c.reward, c.name .. " down")
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, c.reward))
        log(string.format("special: round %d, %s shot down %.0f s after it appeared", D.round, c.name, now - s.at))
        return
    end
    local p
    for _, q in ipairs(planes) do if q.unit == c.unit and valid(q.obj) then p = q end end
    local you = playerLocation()
    if not (p and you) then return end
    local ok, l = pcall(function() local v = p.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not ok then return end
    s.dist = km(l, you)
    local pawn = valid(survivalPC) and survivalPC.Pawn
    local a = pawn and addrOf(pawn)
    if a and a ~= ANOM.pawn then ANOM.pawn = a; if ANOM.on then ANOM.on = nil end end   -- a new plane: switch again
    if ANOM.on ~= true and s.dist < c.field_km then setField(true, s)
    elseif ANOM.on ~= false and s.dist > c.field_km + 0.3 then setField(false, s) end      -- (0.3 km: no flicker)
end
end

-- Watches a running special: launched (its flag, or the countdown run out with the shuttle still there) or lost (its
-- flag, or nothing of its unit alive before liftoff). Pays the reward or closes the shop.
local function specialTick(now)
    local s = D.special
    if s and s.kind == "anomaly" then return ANOM.tick(now, s) end
    if not s or s.state ~= "countdown" then return end
    local c, t = CFG.specials.shuttle, CFG.hud.text
    local f = svFlags() or {}
    local alive = SV_UnitAlive(c.unit)
    local over = now - s.at >= c.countdown_s + 3
    local launched = (f.SV_ShuttleLaunched or 0) >= 1
    if (f.SV_ShuttleLost or 0) >= 1 or (alive <= 0 and not launched and not over) or (over and not launched and alive <= 0) then
        s.state = "done"
        RUN.shopClosedUntil = D.round + c.shop_closed_rounds
        RUN.dirty = true
        hudCallout(t.shuttle_lost, t.shuttle_lost_sub)
        log(string.format("special: round %d, the shuttle was lost %.0f s into the countdown (%d hits); shop closed through round %d",
            D.round, now - s.at, f.SV_ShuttleHits or -1, RUN.shopClosedUntil))
    elseif launched or over then
        s.state = "done"
        addCredits(c.reward, "shuttle launched")
        hudCallout(t.launched, string.format(t.launched_sub, c.reward))
        log(string.format("special: round %d, the shuttle lifted off (%s; %d hits, health %s%%)", D.round,
            launched and "event package" or "countdown over", f.SV_ShuttleHits or -1,
            tostring(shuttleHealth())))
    end
end

local function startRound()
    D.round = D.round + 1
    local sk = spikeCfg(spikeLevel(D.round))
    local budget = math.min(CFG.aircraft_round1 + (D.round - 1) * CFG.aircraft_per_round + (sk.aircraft_add or 0),
        CFG.max_aircraft + (sk.max_add or 0))
    local b = CFG.airfield.bombers
    local special = specialFor(D.round)
    D.special = special and { kind = special, state = "pending" } or nil
    local raid = not special and CFG.airfield.enabled and D.round >= b.first_raid
        and (D.round - b.first_raid) % math.max(1, math.floor(b.raid_every)) == 0
    local bombers, nBombers = {}, 0
    if raid then
        local share = math.floor(budget * b.raid_share / 2 + 0.5) * 2
        bombers, nBombers = pickFlights(b.pool, share, function(u) return D.round < b.heavy_from_round and HEAVY_UNIT[u] end)
    elseif special == "anomaly" then              -- MINDRIPPER and its guards take that many of the round's aircraft
        nBombers = 1 + CFG.specials.anomaly.guards
    elseif special == "shuttle" then             -- strike flights at the shuttle (heavies only bomb the airfield)
        local share = math.floor(budget * CFG.specials.shuttle.strike_share / 2 + 0.5) * 2
        bombers, nBombers = pickFlights(b.pool, share, function(u) return HEAVY_UNIT[u] end)
    end
    local fighters, nFighters = pickFlights(CFG.pool, budget - nBombers, function(u) return PROBE_OF[u] end)
    D.queue, D.spare = {}, {}
    for _, u in ipairs(fighters) do D.queue[#D.queue + 1] = u end
    for _, u in ipairs(CFG.pool) do                 -- spares: free 2-ship flights, for a flight that fails to spawn
        if not D.up[u] and not PROBE_OF[u] and flightSize(u) == 2 then
            local queued = false
            for _, q in ipairs(D.queue) do if q == u then queued = true end end
            if not queued then D.spare[#D.spare + 1] = u end
        end
    end
    local want = #D.queue
    -- the behaviour probe: round 1's first flight flies the package script, round 2's the run-time one
    local pv = CFG.probe.enabled and CFG.probe.behaviour and ((D.round == 1 and "Pkg") or (D.round == 2 and "Rt"))
    local pu = pv and CFG.probe.units[pv]
    if pu and not D.up[pu] and PR.usable[pv] and (pv == "Pkg" or (CFG.probe.runtime and GLS.injected[PROBE_RT_MODULE])) then
        table.insert(D.queue, 1, pu)
        if #D.queue > want then D.spare[#D.spare + 1] = table.remove(D.queue) end
    end
    for _, u in ipairs(bombers) do D.queue[#D.queue + 1] = u end   -- bombers last, behind their escort
    if special == "shuttle" then table.insert(D.queue, 1, "@shuttle") end     -- the shuttle first: it sets their orders
    if special == "anomaly" then table.insert(D.queue, 1, "@anomaly") end
    log(string.format("round %d: %d aircraft: %d fighters in %d squadrons%s", D.round, nFighters + nBombers, nFighters,
        #fighters, raid and string.format(", bomber raid: %d bombers in %d squadrons", nBombers, #bombers)
        or special and string.format(", special %s: %d strike aircraft in %d squadrons", special, nBombers, #bombers) or ""))
    if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " start") end
    D.state, D.at, D.lastAlive = "spawning", D.now, nil
end

-- The player on the ground at the airfield (landed, rolling or in the landing menu): within 3 km of the runway and
-- under 100 m, or nowhere to be read (the landing menu may hide the aircraft). Landing isn't closed under a player
-- who may be down there, so they can always take off again.
local function playerOnAirfield()
    local you = playerLocation()
    if not you then return true end
    local dx, dy = you.X - AIRFIELD.X, you.Y - AIRFIELD.Y
    return math.sqrt(dx * dx + dy * dy) < 300000 and you.Z < 10000
end

local ordersTick
do
-- A pool flight's index in tools/survival_events.py POOL (its SV_Up_NN flag and RE_SV_FlightOrders_NN event).
local function poolIndex(unit)
    local n, k = unit:match("^ERA_Unit_(%d+)_Dep_Air(%d)$")
    return n and (tonumber(n) - 1) * 3 + tonumber(k) + 1
end

-- A fighter flight's orders (player only, air search) come from its appearance trigger, which also sets SV_Up_NN. One
-- that appeared while the landing menu was up never got them (test of 2026-10-22: two F-16 flights attacked the
-- airfield), so a flight still unflagged CFG.orders_check_s after spawning gets them from RE_SV_FlightOrders_NN.
function ordersTick(now)
    for u, o in pairs(D.orders) do
        if now >= o.at then
            local i, t = poolIndex(u), svFlags()
            if not i or SV_UnitAlive(u) <= 0 then
                D.orders[u] = nil
            elseif not t or playerOnAirfield() then      -- grounded: the landing menu may be up
                o.at = now + 1
            elseif (t[string.format("SV_Up_%02d", i)] or 0) >= 1 then
                if o.tries > 0 then log("orders: " .. u .. " has its orders now") end
                D.orders[u] = nil
            elseif o.tries >= 3 or type(SV_Event) ~= "function" then
                log("orders: " .. u .. " never got its orders (SV_Up_" .. string.format("%02d", i) .. " still 0)")
                D.orders[u] = nil
            else
                o.tries, o.at = o.tries + 1, now + 5
                local ev = string.format("RE_SV_FlightOrders_%02d", i)
                local r = SV_Event(ev)
                log(string.format("orders: %s appeared without its orders; %s %s", u, ev,
                    r == 1 and "fired" or ("not fired (" .. (SV_ERR[r] or tostring(r)) .. ")")))
            end
        end
    end
end
end

local function roundsTick(now)
    if not D then return end
    D.now = now
    if not nativeReady() then
        if not D.warned then log("rounds: the native spawner (dlls\\main.dll 0.6.0) did not register SV_Spawn: no enemies"); D.warned = true end
        return
    end
    D.orders = D.orders or {}
    ordersTick(now)
    if D.state == "wait" then
        if not D.announced and now >= D.at - CFG.hud.start_callout_lead_s then
            D.announced = true
            local t = CFG.hud.text
            if specialFor(D.round + 1) == "shuttle" then
                hudCallout(string.format(t.special, D.round + 1), string.format(t.shuttle_sub, CFG.specials.shuttle.name:upper()))
            elseif specialFor(D.round + 1) == "anomaly" then
                hudCallout(string.format(t.special, D.round + 1), t.anomaly_sub)
            else
                hudCallout(string.format(t.start, D.round + 1), t.start_sub)
            end
            local level = spikeLevel(D.round + 1)
            if level > spikeLevel(D.round) then
                hudCallout(t.spike, t.spike_sub)
                log(string.format("spikes: round %d, difficulty level %d", D.round + 1, level))
            end
        end
        if now >= D.at then startRound() end
    elseif D.state == "spawning" then
        specialTick(now)                         -- (spawns may be held while the countdown runs)
        if now < D.at then return end
        if playerOnAirfield() then                 -- the landing menu may be up, and a flight that appears then gets no orders
            if D.held ~= D.round then D.held = D.round; log(string.format("round %d: spawns held while you are down at the airfield", D.round)) end
            D.at = now + 1
            return
        end
        if D.held == D.round then D.held = nil; log(string.format("round %d: you took off, spawns go on", D.round)) end
        local u = table.remove(D.queue, 1)
        if u == "@shuttle" then
            spawnShuttle()
        elseif u == "@anomaly" then
            if ANOM.spawn() then D.special.state, D.special.at = "hunt", now else D.special = nil end
        elseif u then
            local r = spawnFlight(u)
            if r == -1 then log("rounds: left Survival's level, rounds stopped"); D = nil; return end
            if (r == 0 or r == -2 or r == -3) and #D.spare > 0 then        -- this flight can't come: send a spare
                local s = table.remove(D.spare, 1)
                log(string.format("round %d: sending %s instead", D.round, s))
                table.insert(D.queue, 1, s)
            end
        end
        D.at = now + CFG.spawn_gap_s
        if #D.queue == 0 then D.state = "fighting" end
    elseif D.state == "fighting" then
        if now < D.at then return end
        D.at = now + 1
        specialTick(now)
        local alive, flights = 0, 0
        for u in pairs(D.up) do
            local n = SV_UnitAlive(u)
            if n > 0 then alive, flights = alive + n, flights + 1 else D.up[u] = nil end
        end
        if alive ~= D.lastAlive then log(string.format("round %d: %d aircraft in %d flights left", D.round, alive, flights)); D.lastAlive = alive end
        if flights == 0 and D.special and D.special.state == "countdown" then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: enemies down, the shuttle's countdown goes on", D.round)) end
        elseif flights == 0 then
            log(string.format("round %d clear; round %d in %d s", D.round, D.round + 1, CFG.intermission_s))
            addCredits(CFG.credits.round_bonus * D.round, "round " .. D.round .. " cleared")
            if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " clear") end
            D.state, D.at, D.announced = "wait", now + CFG.intermission_s, false
            hudCallout(string.format(CFG.hud.text.complete, D.round),
                       string.format(CFG.hud.text.complete_sub, CFG.intermission_s))
        end
    end
end

---------------------------------------------------------------------------------------------------- airfield
-- Survival's event package counts every enemy weapon that ends on one of the airfield's 4 target points in the int
-- flag SV_AirHits (tools/survival_events.py); the airfield's health is worked out here from the hits since the last
-- repair, so nothing has to write the flag. SV_Event (dlls/main.dll 0.9.0) fires RE_SV_AirfieldClose / Open, which
-- switch landing off and on (Mission 22's LiveSetTakeoffAndLandingEventExecution).
local function intFlag(name)
    local t = svFlags()
    return t and t[name]
end

local function airfieldEvent(name)
    if type(SV_Event) ~= "function" then return " (no SV_Event: dlls/main.dll older than 0.9.0)" end
    local r = SV_Event(name)
    return r == 1 and (" (" .. name .. ")") or (" (" .. name .. " not fired: " .. (SV_ERR[r] or tostring(r)) .. ")")
end

local function airfieldTick(tick)
    local ac = CFG.airfield
    if not ac.enabled or not D or tick % 4 ~= 0 then return end
    local t = CFG.hud.text
    local hits = intFlag("SV_AirHits")
    if hits == nil then return end
    if AF.base == nil then AF.base, AF.hits = hits, hits; log("airfield: health " .. AF.hp .. " (hits so far " .. hits .. ")") end
    for i = #AF.pending, 1, -1 do                   -- heavy bombers' bomb runs (bombTick), as the bombs land
        if tick >= AF.pending[i].due then AF.bomb = AF.bomb + AF.pending[i].dmg; table.remove(AF.pending, i) end
    end
    local hp = math.max(0, AF.full - (hits - AF.base) * ac.hit_damage - (AF.bomb - AF.bombBase))
    if hits ~= AF.hits or hp ~= AF.hp then
        AF.hits = hits
        if hp ~= AF.hp then
            AF.hp, RUN.dirty = hp, true
            log(string.format("airfield: hit (%d hits, %d bomb damage), health %d", hits, AF.bomb, hp))
            if hp <= 0 and not AF.down then
                AF.down, AF.downRound, AF.closePending = true, D.round, true
                hudCallout(t.airfield_down, string.format(t.airfield_down_sub, D.round + 1))   -- airfieldTick reopens it then
                log("airfield: down")
            elseif hp > 0 and AF.attackRound ~= D.round then
                AF.attackRound = D.round
                hudCallout(t.under_attack, nil)
            end
        end
    end
    if AF.closePending then
        if playerOnAirfield() then
            if not AF.closeHeld then AF.closeHeld = true; log("airfield: down, landing stays open until you take off") end
        else
            AF.closePending, AF.closed = false, true
            log("airfield: landing closed" .. airfieldEvent("RE_SV_AirfieldClose"))
        end
    end
    if AF.down and D.state == "wait" and D.round > AF.downRound then
        local reopen = AF.closed
        AF.down, AF.full, AF.base, AF.bombBase, AF.hp = false, ac.repair_hp, hits, AF.bomb, ac.repair_hp
        AF.closePending, AF.closeHeld, AF.closed, RUN.dirty = false, false, false, true
        hudCallout(t.airfield_up, t.airfield_up_sub)
        log("airfield: repaired to " .. ac.repair_hp .. (reopen and (", landing open" .. airfieldEvent("RE_SV_AirfieldOpen")) or ""))
    end
end

-- The world-data unit (flight) an AI plane belongs to, from its GetUnitName(); cached in p.unit, false if unreadable.
local unitWarned = false
local function planeUnit(p)
    if p.unit ~= nil then return p.unit end
    local ok, u = pcall(function() local v = p.obj:GetUnitName(); return type(v) == "string" and v or v:ToString() end)
    p.unit = (ok and type(u) == "string" and u ~= "") and u or false
    if not p.unit and not unitWarned then
        unitWarned = true
        log("planes: GetUnitName unreadable (" .. p.name .. ": " .. tostring(u) .. "); credits and bomb runs go by model")
    end
    return p.unit
end

-- Heavy bombers (CFG.airfield.bombers.heavy) over the airfield: fire their flight's scripted bomb run and queue the
-- damage. If a plane's flight can't be read, every heavy flight that is up drops.
local function bombTick(tick)
    local b = CFG.airfield.bombers
    if not CFG.airfield.enabled or not D or not D.heavy or tick % 4 ~= 2 or type(SV_Event) ~= "function" then return end
    local heavy = {}
    for _, a in ipairs(b.heavy) do heavy[a:match("^(%w+)_") or a] = true end      -- "tu95_common" -> tu95
    D.bombAt = D.bombAt or {}
    for _, p in ipairs(planes) do
        local model = not p.down and p.name:match("BP_OP%d+_(%w+)_")
        if model and heavy[model] and valid(p.obj) then
            local ok, l = pcall(function() return p.obj:K2_GetActorLocation() end)
            local dx, dy = ok and l and (l.X - AIRFIELD.X), ok and l and (l.Y - AIRFIELD.Y)
            local dist = dx and math.sqrt(dx * dx + dy * dy)
            if dist and (not p.closest or dist < p.closest) then p.closest = dist end
            if dist and tick % 40 == 2 then
                log(string.format("bombers: %s %.1f km from the airfield, %.1f km up (closest %.1f km; drop within %.1f km)",
                    p.name, dist / 100000, l.Z / 100000, p.closest / 100000, b.drop_km))
            end
            if dist and dist <= b.drop_km * 100000 then
                local unit = planeUnit(p)
                if not p.overSaid then p.overSaid = true; log("bombers: " .. p.name .. " over the airfield, flight " .. tostring(unit)) end
                local runs = {}
                if unit and BOMBER_UNIT[unit] then runs[1] = unit else for u in pairs(D.heavy) do if D.up[u] then runs[#runs + 1] = u end end end
                for _, u in ipairs(runs) do
                    if not D.bombAt[u] or tick - D.bombAt[u] >= b.run_cooldown_s * 4 then
                        D.bombAt[u] = tick
                        local ev = string.format("RE_SV_BombRun_%02d", BOMBER_INDEX[u])
                        local r = SV_Event(ev)
                        if r == 1 then AF.pending[#AF.pending + 1] = { due = tick + b.damage_delay_s * 4, dmg = b.bomb_damage } end
                        log(string.format("bombers: %s bomb run (%s): %s", u, ev, r == 1 and "fired" or ("not fired, " .. tostring(r))))
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- music
-- SV_PlayBGM(event) posts a BGM event through the game's controller (it fades the playing track out and ignores a
-- track that is already playing); SV_BGM(0) reads the id it is playing (0 = nothing). See CFG.music.
local M = {}

local function musicNext(special)
    local mc = CFG.music
    local key = (special and #mc.special > 0) and "special" or "tracks"
    local list = mc[key]
    M.bags[key] = M.bags[key] or {}
    local bag = M.bags[key]
    for _ = 1, #list + 1 do
        if #bag == 0 then
            for _, t in ipairs(list) do if not M.dropped[t] then bag[#bag + 1] = t end end
            if #bag == 0 then log("music: no playable tracks left in CFG.music." .. key); return true end
            shuffled(bag)
            if #bag > 1 and bag[#bag] == M.track then bag[1], bag[#bag] = bag[#bag], bag[1] end   -- no repeat
        end
        local t = table.remove(bag)
        local r = SV_PlayBGM(t)
        if r == -2 then
            M.dropped[t] = true
            log("music: " .. t .. " is not a BGM event the game has loaded; dropped")
        elseif r < 0 then
            table.insert(bag, t)                       -- not ready (or no game code): the same track next try
            log("music: " .. t .. " not posted (" .. tostring(r) .. "); trying again shortly")
            return false
        else                                           -- id 0 = queued by the game's delay table, or refused:
            M.track, M.silent, M.restarted = t, nil, nil   -- the silence check below finds out which
            log(string.format("music: round %d%s -> %s (playing id %d)", D.round, special and " (special)" or "", t, r))
            return true
        end
    end
    return true
end

local function musicTick(tick, now, paused)
    local mc = CFG.music
    if D and tick % 4 == 0 and type(SV_BGM) == "function" and (not mc.enabled or M.player) then
        -- Survival leaves the music alone; log what the game's BGM controller plays (user, 2026-10-22: the music
        -- player's track skips mid-play), so a change can be matched to what happened then
        local id = SV_BGM(0)
        if id ~= M.id then M.id = id; log(string.format("music: the game's BGM controller now plays id %d (status %d)", id, SV_BGM(1))) end
        if type(SV_BGMNames) == "function" then           -- track | last stop | last event the controller was given
            local names = SV_BGMNames()
            if names ~= M.names then M.names = names; log("music: the game's BGM controller: track|stop|event = " .. names) end
        end
    end
    if not mc.enabled or not D or M.player then return end
    if type(SV_PlayBGM) ~= "function" then
        if not M.warned then M.warned = true; log("music: dlls/main.dll older than 0.9.0; the mission track plays all run") end
        return
    end
    if paused then        -- the pause menu: has the player opened the music player (its page shown, not just made)?
        if tick % 4 == 0 then
            for _, w in ipairs(FindAllOf("WBP_Menu_PauseMusicPlayer_000_C") or {}) do
                local okV, vis = pcall(function() return w:IsVisible() end)
                if okV and vis and liveWidget(w) then
                    M.player = true
                    log("music: the pause menu's music player was opened; Survival leaves the music to the player")
                    break
                end
            end
        end
        return
    end
    if D.round >= 2 and D.round ~= M.round and (not M.retryAt or now >= M.retryAt) then
        if musicNext(specialFor(D.round) ~= nil) then M.round, M.retryAt = D.round, nil else M.retryAt = now + 5 end
    end
    if tick % 4 ~= 0 then return end
    local id = SV_BGM(0)
    if id ~= M.id then M.id = id; log(string.format("music: playing id %d, status %d", id, SV_BGM(1))) end
    if id == 0 and M.track then
        M.silent = M.silent or now
        if now - M.silent >= mc.restart_s then
            M.silent = nil
            if M.restarted == M.track then         -- posted again and still silent: the game won't play it
                M.dropped[M.track], M.restarted = true, nil
                log(string.format("music: %s stays silent; dropped, next track", M.track))
                musicNext(false)
            else
                M.restarted = M.track
                log(string.format("music: nothing playing for %d s; %s again (%s)", mc.restart_s, M.track,
                    tostring(SV_PlayBGM(M.track))))
            end
        end
    else
        M.silent = nil
        if id ~= 0 then M.restarted = nil end
    end
end

---------------------------------------------------------------------------------------------------- ammo cap
-- The player's ammo counts live in native memory (no reflected property holds them; Lua 0.8.0 found no module
-- objects), so dlls\main.dll (runtime 0.7.0) reads and sets them the way the stock LiveSetWeaponAmmoCount node does
-- (tools/re/AMMO.md): SV_Ammo(kind [, max]) and SV_SetAmmo(kind, count), kind 0 gun, 1 missiles, 2 special 1,
-- 3 special 2, 4 flares; a count above the weapon's maximum is capped at it. Shortly after the player's aircraft
-- appears the preset's caps are set; the gun is kept full (unlimited); every count is logged every 10 s, which
-- also shows that missiles no longer restock on their own (SV_FreeRestock, as the stock node Mission 015 uses).
local AMMO_KINDS = { [0] = "gun", "missiles", "special 1", "special 2", "flares" }
local A = nil                      -- this level's loadout state: { pawn, seenAt, applied, tries, lastLine }

local function ammoReady() return type(SV_Ammo) == "function" and type(SV_SetAmmo) == "function" end


local function ammoLine()
    local parts = {}
    for k = 0, 4 do
        local n, max = SV_Ammo(k), SV_Ammo(k, 1)
        if n >= 0 then parts[#parts + 1] = string.format("%s %d/%d", AMMO_KINDS[k], n, max) end
    end
    return table.concat(parts, ", ")
end

local function applyAmmoCaps()
    local probe = SV_Ammo(1)
    if probe < 0 and probe ~= -7 then return false, probe end                  -- not ready yet (or no game code)
    local pname, diff = presetName()
    local p = CFG.ammo.presets[pname] or CFG.ammo.presets.standard
    local want = { [1] = p.missiles, [2] = p.special, [3] = p.special, [4] = p.flares }
    local before = ammoLine()
    for k = 1, 4 do
        if want[k] and SV_Ammo(k) >= 0 then SV_SetAmmo(k, want[k]) end
    end
    A.caps, A.preset = want, pname
    RUN.dirty = true                                -- the shop's help lines show the caps
    if CFG.ammo.gun_unlimited then SV_SetAmmo(0, -1) end
    local restock = type(SV_FreeRestock) == "function" and SV_FreeRestock(CFG.ammo.free_restock and 1 or 0) or "n/a"
    log(string.format("ammo: preset %s (difficulty %s): %s -> %s; free restock was %s, now %s", pname, tostring(diff),
        before, ammoLine(), tostring(restock), CFG.ammo.free_restock and "on" or "off"))
    return true
end

local function ammoTick(tick, pc)
    if not CFG.ammo.enabled then return end
    if not ammoReady() then
        if not (A and A.warned) then A = { warned = true }; log("ammo: dlls/main.dll 0.7.0 did not register SV_Ammo; no ammo cap") end
        return
    end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not valid(pawn) then return end
    local pname = nameOf(pawn)
    if not A or A.pawn ~= pname then A = { pawn = pname, seenAt = tick, applied = false, tries = 0 } end
    if not A.applied and tick - A.seenAt >= 8 and (tick - A.seenAt) % 8 == 0 and A.tries < 10 then   -- 2 s in, retried
        A.tries = A.tries + 1
        local ok, r, code = pcall(applyAmmoCaps)
        if not ok then log("ammo: error " .. tostring(r))
        elseif not r and A.tries == 10 then log("ammo: the player's weapons could not be read (" .. tostring(code) .. "); no ammo cap") end
        A.applied = ok and r
    end
    if not A.applied then return end
    if tick % 2 == 0 then                                                      -- every 0.5 s: counts for the kill probe
        local s = {}
        for k = 0, 4 do s[k] = SV_Ammo(k) end
        PR.ammo[#PR.ammo + 1] = s
        if #PR.ammo > 12 then table.remove(PR.ammo, 1) end
        -- A.caps[k] is what the player may hold: the preset's load at spawn, less what was fired, plus what was
        -- bought. The airfield's rearm (and anything else the game refills) loads the aircraft's full stock count, so a
        -- count above it is put back: landing rearms nothing. Firing lowers it, read only away from the airfield (a
        -- rearm in progress must never pass for shots).
        local over, ground = {}, playerOnAirfield()
        for k = 1, 4 do
            local cap = A.caps and A.caps[k]
            if cap and s[k] >= 0 and A.owed and A.owed[k] then  -- bought while the count couldn't be read: load it now
                A.owed[k] = nil
                if s[k] < cap then SV_SetAmmo(k, cap); s[k] = cap end
            end
            if cap and s[k] > cap then
                SV_SetAmmo(k, cap)
                over[#over + 1] = string.format("%s %d -> %d", AMMO_KINDS[k], s[k], cap)
            elseif cap and s[k] >= 0 and s[k] < cap and not ground then
                A.caps[k] = s[k]
                RUN.dirty = true                    -- the shop's help lines show the counts
            end
        end
        if #over > 0 then
            if type(SV_FreeRestock) == "function" and not CFG.ammo.free_restock then SV_FreeRestock(0) end
            log("ammo: refilled by the game, put back to what you had (" .. A.preset .. "): " .. table.concat(over, ", "))
        end
    end
    if tick % 8 == 4 then                                                      -- every 2 s: maxima, for the shop
        A.max = A.max or {}
        for k = 0, 4 do local m = SV_Ammo(k, 1); if m >= 0 then A.max[k] = m end end
    end
    if CFG.ammo.gun_unlimited and tick % 8 == 0 then                           -- every 2 s: gun back to full
        local n, max = SV_Ammo(0), SV_Ammo(0, 1)
        if n >= 0 and n < max then SV_SetAmmo(0, -1) end
    end
    if tick % 40 == 0 then                                                     -- every 10 s: the counts, when they change
        local line = ammoLine()
        if line ~= A.lastLine then log("ammo: now " .. line); A.lastLine = line end
    end
end

local function playerControllerHere()
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if valid(pc) and inSurvival(pc) then return pc end
    end
    return nil
end

-- This pass's round time and whether the game is paused. The game clock (GetTimeSeconds) stops while paused, so the
-- rounds and the countdown do too; if it can't be read within 5 s of loading, real time is used (and logged).
local function roundClock(tick)
    local t = gameClock(survivalPC)
    if D.clock == nil then
        if t then D.clock = "game"; log("rounds: on the game clock (stops while paused)")
        elseif tick - levelTick >= 20 then
            D.clock = "ticks"; log("rounds: the game clock can't be read; using real time (rounds keep running while paused)")
        else return nil end
        D.at = (D.clock == "game" and t or tick / 4) + CFG.first_round_delay_s
    end
    if D.clock == "ticks" then return tick / 4, false end
    if not t then return D.now, true end                    -- not readable this pass: hold still
    return t, (D.now ~= nil and t == D.now) or gamePaused(survivalPC)
end

---------------------------------------------------------------------------------------------------- airfield shop
-- Survival's rows (DT_SV_ShopRows) go into the landing menu's command table (the in-game hangar's list) while
-- Survival's level is loaded, and come out again when it isn't, so stock missions never show them. Their texts are
-- set through dlls/main.dll's text hook (SV_SetText) and kept up to date with credits and prices; picking one is
-- caught by its landing-menu hook and handed over here by SV_ShopRequest (runtime 0.10.0).
local SHOP = {
    mine = "/Game/Mods/SurvivalMode/Data/DT_SV_ShopRows.DT_SV_ShopRows",
    game = "/Game/Datatables/UI/Menu/IngameMenu/IngameHangar/DT_LiveMenuIngameHangarCommands.DT_LiveMenuIngameHangarCommands",
    rows = { "SVShopMissiles", "SVShopSpecial", "SVShopFlares", "SVShopAirfield" },
}
local SH = { added = false, addr = nil, warned = {} }

local function shopWarn(key, msg)
    if SH.warned[key] then return end
    SH.warned[key] = true
    log("shop: " .. msg)
end

local function shopRowsTick(tick)
    if not CFG.shop.enabled or tick % 16 ~= 1 or containerState ~= true then return end
    local pc = valid(survivalPC) and survivalPC or (SH.addr and FindFirstOf("PlayerController"))
    if pc and valid(pc) and inSurvival(pc) then
        -- without the native landing-menu hook a shop row would reach the stock decide, which reads it as a page number
        if type(SV_ShopRequest) ~= "function" or type(SV_SetText) ~= "function" or SV_ShopRequest(1) ~= 1 then
            shopWarn("hook", "dlls/main.dll's landing menu hook is not installed (runtime 0.10.0+); no shop rows")
            return
        end
        local game = loadObject(SHOP.game)
        if not valid(game) then shopWarn("load", "could not load the landing menu's table"); return end
        local a = addrOf(game)
        if SH.addr ~= a then SH.addr, SH.added = a, false; pin(game, nameOf(game)) end
        if SH.added then return end
        local mine = loadObject(SHOP.mine)
        if not valid(mine) then shopWarn("mine", "could not load DT_SV_ShopRows"); return end
        pin(mine, nameOf(mine))
        local n = 0
        for _, r in ipairs(SHOP.rows) do
            local _, have = dtCall(game, "FindRow", r)
            if have == nil then
                local _, src = dtCall(mine, "FindRow", r)
                if src ~= nil then dtCall(game, "AddRow", r, src) end
            end
            local _, now = dtCall(game, "FindRow", r)
            if now ~= nil then n = n + 1 end
        end
        SH.added = n == #SHOP.rows
        log(string.format("shop: %d of %d rows in the landing menu (%s)", n, #SHOP.rows, rowNames(game)))
    elseif SH.addr then
        local game = StaticFindObject(SHOP.game)
        if valid(game) then
            for _, r in ipairs(SHOP.rows) do dtCall(game, "RemoveRow", r) end
            log("shop: rows taken out of the landing menu (not in Survival's level)")
        end
        SH.added, SH.addr = false, nil
    end
end

local shopTexts, shopBuy             -- (the shop's helpers stay inside the block: the 200-local limit)
do
local function shopPrice(name)
    local it = CFG.shop.items[name]
    return math.floor(it.price * it.raise ^ (RUN.bought[name] or 0) / 10 + 0.5) * 10
end

-- The shop is closed after a lost special (CFG.specials.shuttle.shop_closed_rounds): through round RUN.shopClosedUntil,
-- including the break before it, and open again in the break after it.
local function shopClosed()
    local u = RUN.shopClosedUntil
    return u ~= nil and D ~= nil and (D.round < u or (D.round == u and D.state ~= "wait"))
end

-- The airfield row's offer once the airfield is whole: the next defence to build ({ kind, unit, def, price }), or nil
-- when every one is up.
local function defenceOffer()
    local d = CFG.shop.items.Airfield.defences
    if not d or not D or not nativeReady() then return nil end
    RUN.defences = RUN.defences or { built = 0, bought = {} }
    local function free(kind)
        for _, u in ipairs(d[kind].units) do if SV_UnitAlive(u) <= 0 then return u end end
    end
    local first = d.order[RUN.defences.built % #d.order + 1]
    for _, kind in ipairs({ first, first == "aa" and "sam" or "aa" }) do
        local u = d[kind] and d[kind].units and free(kind)
        if u then
            local def = d[kind]
            return { kind = kind, unit = u, def = def,
                     price = math.floor(def.price * def.raise ^ (RUN.defences.bought[kind] or 0) / 10 + 0.5) * 10 }
        end
    end
    return nil
end

local function airfieldNeedsRepair()
    return not AF.hp or AF.down or AF.hp < CFG.airfield.hp
end

local function defencesUp(kind)
    local def = CFG.shop.items.Airfield.defences[kind]
    local units, n = def and def.units or {}, 0
    if nativeReady() then for _, u in ipairs(units) do if SV_UnitAlive(u) > 0 then n = n + 1 end end end
    return n, #units
end

function shopTexts()
    if type(SV_SetText) ~= "function" then return end
    for name, it in pairs(CFG.shop.items) do
        local price, label, help = shopPrice(name)
        if it.kind then
            local cap = A and A.caps and A.caps[it.kind]
            label = string.format("%s +%d   %d Z", it.label, it.step, price)
            help = string.format("%d more %s. Landing doesn't rearm: you fly with what you buy%s.", it.step, it.what,
                cap and string.format(" (you have %d)", cap) or "")
        elseif airfieldNeedsRepair() or not it.defences then
            label = string.format("%s +%d   %d Z", it.label, it.repair, price)
            help = string.format("Repairs the airfield by %d (now %s of %d).", it.repair,
                AF.down and "down" or tostring(AF.hp or "?"), CFG.airfield.hp)
        else
            local o = defenceOffer()
            local aa, aaMax = defencesUp("aa")
            local sam, samMax = defencesUp("sam")
            local up = string.format(" (AA guns %d of %d, SAM sites %d of %d up)", aa, aaMax, sam, samMax)
            if o then
                label = string.format("BUILD %s   %d Z", o.def.label, o.price)
                help = string.format("Builds %s at the airfield for the rest of the run%s.", o.def.what, up)
            else
                label = "AIRFIELD DEFENCES: ALL BUILT"
                help = "Every AA gun and SAM site is up" .. up .. "."
            end
        end
        if shopClosed() then help = CFG.hud.text.shop_closed end
        help = string.format("ZOLLARS %d. %s%s", RUN.credits, RUN.msg[name] and (RUN.msg[name] .. " ") or "", help)
        SV_SetText("SV_Shop_" .. name, label)
        SV_SetText("SV_Shop_" .. name .. "_Help", help)
    end
end

-- One purchase; the result goes into the item's help line and the log.
function shopBuy(name)
    local it = CFG.shop.items[name]
    if not it then log("shop: unknown item " .. tostring(name)); return end
    local price = shopPrice(name)
    local function done(msg) RUN.msg[name] = msg; RUN.dirty = true; log("shop: " .. name .. ": " .. msg) end
    if shopClosed() then return done("CLOSED.") end
    if not it.kind and it.defences and not airfieldNeedsRepair() then        -- the airfield is whole: a defence
        local o = defenceOffer()
        if not o then return done("ALL DEFENCES BUILT.") end
        if RUN.credits < o.price then return done(string.format("NOT ENOUGH ZOLLARS (%d needed).", o.price)) end
        local r = SV_Spawn(o.unit)
        if r <= 0 then return done("COULD NOT BUILD IT (" .. (SV_ERR[r] or tostring(r)) .. ").") end
        RUN.credits, RUN.spent = RUN.credits - o.price, RUN.spent + o.price
        RUN.defences.built = RUN.defences.built + 1
        RUN.defences.bought[o.kind] = (RUN.defences.bought[o.kind] or 0) + 1
        return done(string.format("%s BUILT for %d (%s).", o.def.label, o.price, o.unit))
    end
    if RUN.credits < price then return done(string.format("NOT ENOUGH ZOLLARS (%d needed).", price)) end
    if it.kind then
        local k = it.kind
        if not (A and A.applied and A.caps and A.caps[k]) then return done("NOT AVAILABLE YET.") end
        local max = SV_Ammo(k, 1)                    -- unreadable on the landing menu: the last one seen in flight
        if max < 0 then max = A.max and A.max[k] end
        if not max then return done("NOT AVAILABLE RIGHT NOW.") end
        if A.caps[k] >= max then return done("ALREADY AT FULL LOAD.") end
        local gain = math.min(it.step, max - A.caps[k])   -- the last step up to the aircraft's full load costs less
        if gain < it.step then
            price = math.ceil(price * gain / it.step / 10) * 10
            if RUN.credits < price then return done(string.format("NOT ENOUGH ZOLLARS (%d needed).", price)) end
        end
        for _, kk in ipairs(k == 2 and { 2, 3 } or { k }) do
            if A.caps[kk] then
                A.caps[kk] = A.caps[kk] + gain
                local n = SV_Ammo(kk)
                if n >= 0 then SV_SetAmmo(kk, math.min(n + gain, A.caps[kk]))
                else A.owed = A.owed or {}; A.owed[kk] = true end      -- unreadable now: ammoTick loads it
            end
        end
    else
        if not AF.hp or AF.down then return done("THE AIRFIELD IS DOWN.") end
        if AF.hp >= CFG.airfield.hp then return done("THE AIRFIELD IS NOT DAMAGED.") end
        AF.full, AF.base, AF.bombBase = math.min(CFG.airfield.hp, AF.hp + it.repair), AF.hits, AF.bomb
        AF.hp = AF.full                             -- airfieldTick works health out from these from now on
    end
    RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
    RUN.bought[name] = (RUN.bought[name] or 0) + 1
    done(string.format("BOUGHT for %d.", price))
end
end

local function shopTick(tick)
    if not CFG.shop.enabled or not D then return end
    if type(SV_ShopRequest) == "function" then
        -- every press waiting (the landing menu's hook queues them), and the texts straight after: taking one press
        -- per tick and updating the texts once a second left ~1 s with no change on screen, so purchases seemed not to
        -- register and players pressed again (user, 2026-10-22: "a good few presses to get it to register")
        local seen = {}
        for _ = 1, 8 do
            local r = SV_ShopRequest()
            if not r or r == "" then break end
            local item = r:gsub("^SV_Buy_", "")
            if seen[item] then
                log("shop: " .. item .. " pressed again within a tick; once is bought")
            else
                seen[item] = true
                local ok, err = pcall(shopBuy, item)
                if not ok then log("shop: error " .. tostring(err)) end
            end
        end
    end
    if RUN.dirty then
        RUN.dirty = false
        local ok, err = pcall(shopTexts)
        if not ok then log("shop: text error " .. tostring(err)) end
    end
end

-- The landing menu's ammo panel ([WEAPONS AMMO], WBP_Menu_IngameHangar_WeaponDetail_002: six slots
-- AmmoText{L,R}{Top,Center,Bottom}, each WBP_Hangar_Detail_Text_000 with the weapon's name in Text_Body and its stock
-- full load in Text_Body_1, e.g. "MSL" "144"; user screenshot of 2026-10-22: GUN / MSL / FLR on the left, the special
-- weapons on the right). While Survival's caps apply, each capped weapon shows what the player takes off with: the
-- cap (the rearm fills up to it; the gun is left alone).
local AMMO_SLOTS = { "AmmoTextLTop", "AmmoTextLCenter", "AmmoTextLBottom", "AmmoTextRTop", "AmmoTextRCenter", "AmmoTextRBottom" }
local AMMO_SLOT_KIND = { AmmoTextLCenter = 1, AmmoTextLBottom = 4, AmmoTextRTop = 2, AmmoTextRCenter = 3, AmmoTextRBottom = 3 }
-- A named child widget (GetWidgetFromName, else the blueprint variable) and a text widget's text (GetText, else its
-- Text property): on the landing menu the variables read back as TrivialObjects (test of 2026-10-22).
local function childWidget(w, n)
    local ok, x = pcall(function() return w:GetWidgetFromName(FName(n)) end)
    if ok and valid(x) then return x end
    ok, x = pcall(function() return w[n] end)
    if ok and valid(x) then return x end
    return nil
end
local function widgetText(t)
    local ok, v = pcall(function() return t:GetText():ToString() end)
    if ok and type(v) == "string" then return v end
    ok, v = pcall(function() return t.Text:ToString() end)
    if ok and type(v) == "string" then return v end
    return nil
end
local function slotTexts(panel, slot)                 -- the slot's name and count widgets
    local w = childWidget(panel, slot)
    return w and childWidget(w, "Text_Body"), w and childWidget(w, "Text_Body_1")
end

local function hangarAmmoTick(tick)
    if not (CFG.ammo.enabled and A and A.applied and A.caps and A.max) or tick % 2 ~= 1 then return end
    if not playerOnAirfield() then SH.panels = nil; return end   -- the landing menu only exists down there
    local live = SH.panels and #SH.panels > 0
    for _, panel in ipairs(SH.panels or {}) do if not valid(panel) then live = false end end
    if not live and tick % 8 == 1 then
        SH.panels = {}
        for _, w in ipairs(FindAllOf("WBP_Menu_IngameHangar_WeaponDetail_002_C") or {}) do
            if liveWidget(w) then SH.panels[#SH.panels + 1] = w end
        end
    end
    for _, panel in ipairs(SH.panels or {}) do
        if liveWidget(panel) and not SH.panelSaid then
            SH.panelSaid = true                      -- once: what the panel holds (test of 2026-10-22: no rewrite seen)
            local parts = {}
            for _, slot in ipairs(AMMO_SLOTS) do
                local name, count = slotTexts(panel, slot)
                parts[#parts + 1] = string.format("%s '%s' '%s'", slot, tostring(name and widgetText(name)),
                    tostring(count and widgetText(count)))
            end
            local mx = {}
            for k = 0, 4 do mx[#mx + 1] = tostring(A.max[k]) end
            log("shop: ammo panel " .. nameOf(panel) .. ": " .. table.concat(parts, ", ") .. "; maxima " .. table.concat(mx, "/"))
        end
        if liveWidget(panel) then
            for _, slot in ipairs(AMMO_SLOTS) do
                pcall(function()
                    local kind = AMMO_SLOT_KIND[slot]
                    local cap = kind and A.caps[kind]
                    if not cap then return end
                    local _, t = slotTexts(panel, slot)
                    local now = t and widgetText(t)
                    local m = now and tonumber(now:match("^%s*(%d+)%s*$"))               -- an empty special slot shows "---"
                    if not m then return end
                    local want = tostring(math.min(cap, m))
                    if now ~= want then
                        t:SetText(toText(want))
                        if not SH.ammoSaid then SH.ammoSaid = true; log("shop: landing menu ammo shows the caps (" .. now .. " -> " .. want .. ")") end
                    end
                end)
            end
        end
    end
end

-- Credits for an enemy aircraft that went down (probeTick's plane watch), by its flight's role: a bomber flight pays
-- bomber (heavy for CFG.airfield.bombers.heavy models), any other flight fighter. Only when the plane's flight
-- couldn't be read does its model decide (CFG.credits.models).
local function creditKill(p)
    local model = p.name:match("BP_OP%d+_(%w+)_") or "?"
    local kind = "fighter"
    if p.unit and BOMBER_UNIT[p.unit] then
        kind = "bomber"
        for _, h in ipairs(CFG.airfield.bombers.heavy) do if (h:match("^(%w+)_") or h) == model then kind = "heavy" end end
    elseif p.unit == false then
        kind = CFG.credits.models[model] or "fighter"
    end
    addCredits(CFG.credits[kind] or 0, model .. " down (" .. kind .. ")")
end

local function probeTick(tick)
    if levelTick == -1 then
        levelTick = tick
        log("level loaded: PL_SurvivalMode")
        if type(SV_SetControlInvert) == "function" then SV_SetControlInvert(0, 0, 0, 0) end   -- (the Anomaly's field)
        ANOM.on, ANOM.pawn = false, nil
        planes, lastAlive, lastFlags = {}, nil, nil
        presetCache.at = -100                 -- the difficulty may have changed since the last run
        if type(SV_Reset) == "function" then SV_Reset() end
        log("rounds: native spawner " .. (type(SV_Version) == "function" and ("runtime " .. tostring(SV_Version())) or "missing") ..
            "; round 1 in " .. CFG.first_round_delay_s .. " s")
        D = { round = math.max(1, math.floor(CFG.start_round)) - 1, state = "wait", at = nil, now = nil, queue = {}, spare = {}, up = {}, flown = {}, announced = false }
        PR.usable = { Pkg = PR.ready.Pkg, Rt = PR.ready.Rt }      -- only rows that were in before this level loaded
        log("probe: at level load, probe rows ready: package " .. tostring(PR.ready.Pkg ~= nil) .. ", run-time " .. tostring(PR.ready.Rt ~= nil))
        SR.usable = {}
        local nS = 0
        local nA = 0                               -- the aces' rows (CFG.aces) count apart from the aircraft
        for a, sv in pairs(SR.ready) do
            SR.usable[a] = sv
            if a:find("^sv_ace_") then nA = nA + 1 else nS = nS + 1 end
        end
        SR.usableLevels = {}                       -- spike rows in before this level loaded (the spawner cached them)
        for a, t in pairs(SR.levels or {}) do SR.usableLevels[a] = t end
        log(string.format("search: at level load, %d of %d aircraft (and %d ace rows) fly with the %s m search", nS,
            #CFG.aircraft, nA, tostring(CFG.search.radius_m)))
        if H and valid(H.widget) then pcall(function() H.widget:RemoveFromParent() end) end   -- a restart keeps the level
        H, hudTries, hudOff, hudSaid, callouts, survivalPC, A = nil, 0, false, {}, {}, nil, nil
        flagCache.at, flagCache.t, flagCache.cs, flagCache.found = -1, nil, nil, -100
        SHUTTLE.obj, SHUTTLE.lookAt = nil, nil
        M = { bags = {}, dropped = {}, round = 1, track = CFG.music.start_track }
        AF = { full = CFG.airfield.hp, hp = CFG.airfield.hp, down = false, bomb = 0, bombBase = 0, pending = {} }
        RUN = { credits = CFG.credits.start, earned = 0, spent = 0, bought = {}, msg = {}, dirty = true }
        if type(SV_MusicPlayer) == "function" then
            local old = SV_MusicPlayer(CFG.music.pause_player and 1 or 0)
            log("music: pause-menu music player " .. (old < 0 and "not available (pause list not hooked)"
                or (CFG.music.pause_player and "on" or "off")))
        end
        if type(SV_MusicClock) == "function" then
            local old = SV_MusicClock(CFG.music.hold_clock and 1 or 0)
            log("music: music player track clock " .. (old < 0 and "not hooked (tracks may end early after a pause)"
                or (CFG.music.hold_clock and "held while the BGM is paused" or "stock")))
        end
    end
    local okSR, errSR = pcall(shopRowsTick, tick)
    if not okSR then log("shop: rows error " .. tostring(errSR)) end
    if tick % 4 == 0 and containerState then                 -- search and behaviour probe rows, from the main menu on
        local okG, errG = pcall(gameLuaTick, tick, (levelTick and levelTick >= 0) and (tick - levelTick) or nil)
        if not okG then log("game Lua: error " .. tostring(errG)) end
        local okB, errB = pcall(setsSetup)
        if not okB then log("behaviour: setup error " .. tostring(errB)); BS.done = true end
        local okS, errS = pcall(searchSetup)
        if not okS then log("search: setup error " .. tostring(errS)); SR.done = true end
        local okSp, errSp = pcall(specialSetup)
        if not okSp then log("special: setup error " .. tostring(errSp)); SPS.done = true end
        local okP, errP = pcall(probeSetup)
        if not okP then log("probe: setup error " .. tostring(errP)); PR.tries = 20 end
    end
    if D then
        if not valid(survivalPC) and tick % 4 == 0 then survivalPC = playerControllerHere() end   -- once a second at most
        -- the run is over once Survival's player controller has been gone 8 s (the level was left: before, the run went
        -- on at the main menu and in stock missions, rewriting their ammo panels and paying vanished planes as kills)
        if valid(survivalPC) then D.pcSeen, D.pcLost = true, 0
        elseif D.pcSeen and tick % 4 == 0 then D.pcLost = (D.pcLost or 0) + 1 end
        -- a mission restart from the pause menu reloads the mission in the same level (no new World, so the reset below
        -- never ran and the run kept its round: user, 2026-10-22), but it sets the event package's flags back to 0: Survival's
        -- counters only grow during a run, so one that drops means the mission started again
        if tick % 8 == 4 then
            local f = svFlags()
            if f then
                D.maxFlags = D.maxFlags or {}
                for _, k in ipairs({ "SV_Kills", "SV_AirHits" }) do
                    local v = f[k]
                    if v then
                        if (D.maxFlags[k] or 0) > 0 and v < D.maxFlags[k] then
                            log(string.format("mission restarted in round %d (%s %d -> %d): the run starts over", D.round, k, D.maxFlags[k], v))
                            levelTick = -1         -- the level-load reset below, on the next tick
                        end
                        D.maxFlags[k] = math.max(D.maxFlags[k] or 0, v)
                    end
                end
            end
        end
        if (D.pcLost or 0) >= 8 then
            log(string.format("run over: left Survival's level in round %d with %d zollars", D.round, RUN.credits))
            D, A, levelTick, survivalPC, callouts = nil, nil, nil, nil, {}
            planes, pending, lastAlive, SH.panels, SHUTTLE.obj = {}, {}, nil, nil, nil
        end
    end
    if D then
        local now, paused = roundClock(tick)
        if now then
            local okR, errR = pcall(roundsTick, now)
            if not okR then log("rounds: error " .. tostring(errR)) end
            local okH, errH = pcall(hudTick, now, paused, survivalPC)
            if not okH then hudLog("tickerr", "error " .. tostring(errH)) end
            local okM, errM = pcall(musicTick, tick, now, paused)
            if not okM then log("music: error " .. tostring(errM)) end
            local okF, errF = pcall(airfieldTick, tick)
            if not okF then log("airfield: error " .. tostring(errF)) end
            local okB, errB = pcall(bombTick, tick)
            if not okB then log("bombers: error " .. tostring(errB)) end
            local okS, errS = pcall(shopTick, tick)
            if not okS then log("shop: error " .. tostring(errS)) end
            local okA2, errA2 = pcall(hangarAmmoTick, tick)
            if not okA2 then log("shop: ammo panel error " .. tostring(errA2)) end
        end
        local okA, errA = pcall(ammoTick, tick, survivalPC)
        if not okA then log("ammo: error " .. tostring(errA)) end
    end
    if levelTick then
        if tick - levelTick == 8 then logDifficulty("at mission start") end
        if tick - levelTick == 48 then logDifficulty("10 s into the mission") end
    end
    local keep = {}
    for _, p in ipairs(pending) do
        p.age = p.age + 1
        if p.age >= 2 then pcall(logPlane, p.obj, p.unit) else keep[#keep + 1] = p end
    end
    pending = keep
    if tick % 8 ~= 0 or not levelTick then return end                -- the rest every 2 s, in Survival only
    local fl, flagged = flagLine()
    if fl and fl ~= lastFlags then log("round probe: flags " .. fl); lastFlags = fl end
    -- Each aircraft's last position, so a loss shows whether it was shot down near the player or crashed far away,
    -- and every 10 s the nearest enemy's distance: the check that they come for the player.
    local you = playerLocation()
    local alive, nearest = 0, nil
    for _, p in ipairs(planes) do
        if not p.down then
            local up = valid(p.obj)
            if up then
                local ok, h = pcall(function() return p.obj.HealthInternal end)
                if ok and type(h) == "number" and h <= 0 then up = false end
            end
            if up then
                alive = alive + 1
                pcall(function() local v = p.obj:K2_GetActorLocation(); p.at = { X = v.X, Y = v.Y, Z = v.Z } end)
                local ft = D and p.unit and D.flightTier and D.flightTier[p.unit]
                pcall(planeUnit, p); pcall(enemyTier, p, D and D.round, ft); pcall(enemyManeuvers, p, D and D.round)
                pcall(enemySpike, p, D and D.round, ft and CFG.tiers.list[ft]); pcall(probeTrack, p); pcall(aiWatch, p, you)
                if p.at and you then
                    local d = km(p.at, you)
                    if not nearest or d < nearest then nearest = d end
                end
            else
                p.down = true
                log("round probe: " .. p.name .. " down" .. (p.at and string.format(", last seen %.1f km up%s",
                    p.at.Z / 100000, you and string.format(", %.1f km from you", km(p.at, you)) or "") or ""))
                pcall(probeKill, p, you)
                pcall(creditKill, p)
            end
        end
    end
    if alive ~= lastAlive and #planes > 0 then
        log("round probe: AI aircraft alive " .. alive .. " (created so far " .. #planes .. ")")
        lastAlive = alive
    end
    if tick % 40 == 0 and alive > 0 then
        local flights = 0
        if D then for _ in pairs(D.up) do flights = flights + 1 end end
        log(string.format("enemies: nearest %s from you; %d flights up (%d flagged up)",
            nearest and string.format("%.1f km", nearest) or "(player not found)", flights, flagged or 0))
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
        if not rowsStopped and (tick % 4 == 0 or not (ready[1] and ready[2])) then   -- watching for reloads: 1/s
            local ok, r = pcall(watchRows)
            if not ok then log("rows: error " .. tostring(r)) end
            if ok and r == false then rowsStopped = true end
        end
        if tick % 8 == 2 then
            local okI, errI = pcall(infoMapsTick)
            if not okI then log("info maps: error " .. tostring(errI)) end
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
    if Key.F9 then                 -- Ctrl+F9: write the live HUD's layout to hud_dump.txt (any screen)
        pcall(RegisterKeyBind, Key.F9, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(hudDump, "Ctrl+F9")
                if not ok then log("hud dump: error " .. tostring(err)) end
            end)
        end)
    end
end

log("loaded, version " .. VERSION)
