-- AC8 Survival Mode - runtime (UE4SS Lua half; the native half is dlls\main.dll)
-- Milestone 1:
--   * adds Survival's mission row and main-menu row to the game's tables at run time, copied from Survival's own
--     tables (DT_SV_MissionRows / DT_SV_MenuRows), so no stock or other-mod table file is overridden
--   * the main-menu entry opens the game's difficulty page; dlls\main.dll then starts Survival's mission
--   * dev keys (in the dev build only; tools/package_test.sh strips them from every zip): open the map from the main
--     menu, zollars, a chosen special next
-- Milestone 2:
--   * rounds: random flights, aircraft and bearings each round, spawned through dlls\main.dll's SV_* functions
--   * round HUD: Survival's own HUD layer, built at run time (round, countdown to the next round, callouts)
--   * rounds run on the game clock, so the countdown and the rounds stop while the game is paused
--   * ammo cap: missiles, special weapons and flares capped per difficulty preset at spawn (dlls\main.dll SV_SetAmmo); gun unlimited
--   * behaviour probe: own enemy behaviour script, live PilotRank write, kill attribution (logged; CFG.probe)
--   * dev: Ctrl+F7 writes the live HUD's widget tree and on-screen geometry to hud_dump.txt (next to Scripts)

local VERSION = "0.63.0"
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
-- main.lua's folder (Scripts\): the mod's files are found from it (..\config\, ..\AC8SurvivalMode_lua.log, ai\)
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""

local log
do
    local LOG_FILE = nil
    local dir = SCRIPT_DIR .. "..\\"
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

-- A DataTable's row names in table order, as strings (nil when they can't be read). GetRowNames may hand back FNames
-- or plain strings: a plain string has no ToString (test of 2026-10-23: the STORE's index check read nothing).
local function rowList(dt)
    local ok, names = dtCall(dt, "GetRowNames")
    if not ok or names == nil then return nil end
    local out = {}
    pcall(function()
        for _, n in ipairs(names) do
            local okS, str = pcall(function() return n:ToString() end)
            out[#out + 1] = okS and str or tostring(n)
        end
    end)
    return out
end

local function rowNames(dt)
    local l = rowList(dt)
    return l and table.concat(l, ", ") or "?"
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
        "), so Survival Mode is off: no menu entry. If AC8IoStoreLoader.log shows " ..
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
-- The STORE's allies (section "allies"): its functions, the run's state (ALLY.run) and which units are allies.
local ALLY = { unit = {} }
-- The Anomaly (section "special rounds"): its field's state, for the HUD and the level reset.
local ANOM = { on = false }
-- The amphibious assault (section "amphibious assault"): its functions; its run state is RUN.amph / RUN.captured.
local AMPH = {}
-- The Ladons and later specials (section "ladon"): their functions; their state is in D.special.
local SPC = {}
-- The leaderboard (section "leaderboard"): the run's stats (RUN.stats), its end, the prompt and sending.
local LB = { queue = {}, jobs = {}, show = nil }
-- its camera settings, in tools/survival_events.py ANOMALY_CAMERAS order (RE_SV_AnomalyCam_A, _B, ...)
local ANOMALY_CAMERAS = { "LookAt_Event_Camera", "LookAt_Event_Camera_ms08-01", "LookAt_Event_Camera_ms04-01",
                          "LookAt_Event_Camera_ms23-01", "LookAt_Event_Camera_ms22-01" }

local function logPlane(o, unit)
    if not valid(o) or not inSurvival(o) then return end
    local n = nameOf(o)
    local short = n:match("([^%.:]+)$") or n
    if short:find("_sstb_", 1, true) then
        SHUTTLE.obj = o
        log("special: shuttle actor " .. short .. (unit and (" (" .. unit .. ")") or ""))
        return
    end
    if unit and ALLY.unit[unit] then                 -- MOONCHILD: no kill credit, no enemy skill or spikes on it
        log("allies: " .. short .. " (" .. unit .. ") is an ally, not an enemy")
        if ALLY.unit[unit] == "air" then local R = ALLY.state(); R.planes[#R.planes + 1] = { obj = o, unit = unit, name = short } end
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
-- Every SV_* int flag: { name = value }, read at most once a second (several callers share one walk), or nil
-- while there is no event container.
-- The event containers are looked up again only when one has gone (a new level) or every 30 s; FindAllOf walks every
-- object in the game, which several times a second was a visible hitch (user, 2026-10-22: "a bit of lag").
local flagCache = { at = -1, t = nil, cs = nil, found = -100 }
local function svFlags()
    local now = os.clock()
    -- (was 0.2 s: with the 250 ms tick that walked every flag of the event package each tick, hundreds of map
    -- entries through two pcalls each; user, 2026-10-23: "the custom HUD ... seems a bit laggy")
    if now - flagCache.at < 1.0 then return flagCache.t end
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
    max_aircraft        = 60,                   -- in one round, difficulty spikes included (user, 2026-10-23: 60)
    squadrons           = { { size = 2, from_round = 1 }, { size = 4, from_round = 4 }, { size = 6, from_round = 8 } },
    distance_km         = { 18, 25 },           -- from the airfield, random bearing
    altitude_m          = { 2000, 4500 },
    aircraft            = { "f16c_common", "f18e_common", "f15e_common", "f14d_common", "m21b_common",
                            "m29a_common", "su47_common", "su33_common", "su34_common" },   -- NPC rows in Mission 22's table
                                                                            -- (su47_common: Survival's; the MiG-31 is out,
                                                                            -- user 2026-10-23)
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
    -- pilots fly one tier higher. Survival's behaviour scripts (CFG.behaviour_sets) weigh their moves by the rank
    -- and the AI level these set; ranks 6-10 fly the named aces' squadrons (CFG.aces).
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
    -- Ace rounds come on a cycle (user, 2026-10-22: "Ace Rounds on a Cycle"): from first_round, every `every`th round is
    -- an ace round, all of it the round's tier's squadrons (no ordinary flights, no bomber raid); the rounds between are
    -- normal ones, ordinary aircraft flown at the same tier (its AI level, fire control and reactions).
    aces = {
        enabled = true,
        first_round = 16, every = 3,
        callout = true,                            -- "ACE INBOUND" the first time each ace shows up in a run
        -- their guns lead you (user, 2026-10-24: "apply the gun lead to all enemy ace aircraft and scale it"): a tier's
        -- gun_lead_s (PredictionOffsetTime: the seconds ahead of you they aim; stock aircraft guns 0), the higher the
        -- tier the more, + gun_lead_per_level for each difficulty spike level, at most gun_lead_max. "anomaly" is
        -- MINDRIPPER's guards (MINDRIPPER and AB.L..IN have their own: specials.anomaly / glitch gun_lead_s).
        gun_lead_s = { mercenary = 0.4, legend = 0.55, demon = 0.7, phantom = 0.85, reaper = 1.0, anomaly = 0.85 },
        gun_lead_per_level = 0.1, gun_lead_max = 1.3,
        -- airframes only Online Mode has (the ADFX-02: its model and blueprint come from Online Mode's tables, ACE.models).
        -- false leaves them out (if one ever misbehaves offline); their tier flies the rest of its line-up.
        online_aircraft = true,
        mercenary = { squadron = "Bounty",   f15c = "Ledger",   su35 = "Wager",    typhoon = "Payday" },
        legend    = { squadron = "Valkyrie", su47 = "Sigrun",   rafale = "Brynhild" },
        demon     = { squadron = "Inferno",  f22a = "Mephisto", su57 = "Belial" },
        phantom   = { squadron = "Wraith",   su57 = "Specter",  typhoon = "Revenant", su47 = "Banshee" },
        reaper    = { squadron = "Harvest",  su57 = "Grim",     f22a = "Scythe",   typhoon = "Charon", rafale = "Nightfall",
                      adfx02 = "Oblivion" },
        -- a tier's squadron airframes (its ace rows, lead and wing) flying beyond stock (user, 2026-10-23: "the Reaper
        -- Squadron was so easy to handle, make them 10x more aggressive ... they still had issues getting behind me";
        -- their behaviours already weigh everything at rank 5 / AI level 5): turn rates + turn_add (pitch / roll / yaw,
        -- as MINDRIPPER's 120 / 270 / 25), top and cornering speed x speed_x, cruise x cruise_x, health + health_add;
        -- post_stall: cobra and kulbit on, whatever the airframe's blueprint says (Grim's Su-57 had both off);
        -- hunt: its target kept on you (the AI's blackboard TargetActor, every 2 s: Grim's stayed on the airfield's
        -- target dummy for the whole of the test of 2026-10-23 while its wingman went for the player); no_provoke: its
        -- bPermissionToProvoke off (tools/re/BEHAVIOUR_NATIVE_LOGIC.md 8.2: being tailed put it in Provoke, then our
        -- reactions handed it to EscapeFromPursuer, both above PursueTarget, so a tailed ace defended and never
        -- turned on you; without it the pursuit, and LA_SV_TailChase's AI-level-5 "Super" branch, turn it onto you);
        -- moves: when you get behind one of its aircraft (within 3 km, inside 70 deg of its tail; ACE.movesTick, 4 times
        -- a second) its flight does the campaign aces' LastTGT reversal, or within 900 m the Shadow kulbit
        -- (tools/survival_events.py build_ace_moves), each flight at most every 20 s
        flight = {
            reaper = { turn_add = { pitch = 180, roll = 360, yaw = 45 }, speed_x = 1.25, cruise_x = 1.15,
                       health_add = 600, post_stall = true, hunt = true, no_provoke = true, moves = true },
        },
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
    maneuvers = { enabled = true, post_stall = { "su33", "su35", "su37", "su47", "su57", "f22a",
                                                 "f04e",              -- (f04e: only the Anomaly's flies one)
                                                 "adfx02", "typn", "rflm" } },   -- (the Reaper squadron's, 2026-10-23)
    -- Airfield and bombers (Milestone 3; tools/survival_events.py AIRFIELD_* / BOMBERS, tools/re/AIRFIELD_SUPPLY.md).
    -- The airfield starts at `hp`; every enemy weapon that reaches one of its 4 target points (the event package
    -- counts them in SV_AirHits) takes hit_damage. At 0 it is down: landing closes (no rearming) until the end of the
    -- round after, then it reopens at repair_hp. Bomber flights (2 aircraft, Mission 22's airport strike: they only
    -- go for the airfield) join rounds from bombers.from_round, one more flight every `every` rounds, up to `max`;
    -- Tu-95s and Tu-160s (`heavy`) from heavy_from_round. bombers.pool must match survival_events.BOMBERS.
    -- hp 250 / repair_hp 125 (user, 2026-10-23: "buff the airbase health"; at 100 a bomber raid took it from full to
    -- down in about 45 s in rounds 7 and 9 of that day's test); the STORE's repairs restore 60 (were 25).
    airfield = {
        enabled    = true,
        hp         = 250,
        hit_damage = 4,
        repair_hp  = 125,
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
    -- bomber / heavy, the rest fighter; `models` is only used when a plane's flight can't be read), times tier_pay of
    -- the enemy's skill tier (CFG.tiers.list order: Rookie x1.0 ... Reaper x2.0), and for every round cleared
    -- (round_bonus x the round), spent in the STORE. Economy check of 2026-10-23 (user: "edit the rewards and check the
    -- economy again"): with flat kill pay and round_bonus 50, ordinary rounds about broke even on ammo and repairs
    -- from round 8 and lost money from 16 (the enemies take more missiles a kill, the pay stayed 100), so allies at
    -- 15000-20000 were out of reach. Now (model): ~18000 by round 10, ~64000 by 20, ~156000 by 30.
    -- special_x (user, 2026-10-23: "Special Rounds should pay out larger amounts, as should their enemies"): every
    -- kill in a special round (aircraft, landing craft, troop vehicles, the Alicorn's ballast tanks) pays x this
    -- (1.5 in 0.49.3, then "buff the special round eco more": 2, and the specials' own rewards twice 0.49.2's).
    credits = {
        start = 0, fighter = 100, bomber = 200, heavy = 400, round_bonus = 100, special_x = 2.0,
        tier_pay = { 1.0, 1.1, 1.25, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0 },
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
        -- the beep on every STORE press (Wwise events of the always-loaded game-SE bank): bought, or nothing bought
        sounds  = { bought = "AKE_GEN_UI_INGAME_BaseResupply_Decide_Play", refused = "AKE_GEN_UI_OUTGAME_General_Reject_Play" },
        items = {
            -- ammo is used up now (no free rearm), so a pack costs the same every time: 25 Z a missile against 100 Z a
            -- fighter (about two missiles a kill), 100 Z a special weapon round, 75 Z a flare
            Missiles = { kind = 1, step = 12, price = 300, raise = 1.0, label = "MISSILES", what = "missiles" },
            Special  = { kind = 2, step = 4, price = 400, raise = 1.0, label = "SPECIAL WEAPON", what = "special weapon rounds" },
            Flares   = { kind = 4, step = 2, price = 150, raise = 1.0, label = "FLARES", what = "flares" },
            -- The landing menu has room for 4 shop rows (its list holds 6, 2 are stock), so this one does three jobs in
            -- turn: it repairs your aircraft while it's damaged (user, 2026-10-22: "add the ability to buy repairs for
            -- your aircraft"; `aircraft`: the stock full repair, price x the damage, at least min_price), then the
            -- airfield while that's damaged, then builds its defences (user: "purchase AA guns ... or SAM sites. Make
            -- them expensive"): Mission 22's airport AA guns and SAM sites, one unit each (tools/survival_events.py
            -- DEFENCES), built in `order`; a destroyed one can be built again. Each kind's price rises `raise` times.
            -- The STORE's own rows (user, 2026-10-23: "a special tab ... for the store items with their own icons";
            -- tools/re/AIRFIELD_SHOP_UI.md): one per job on its two pages, SUPPLIES (missiles, special weapon, flares,
            -- aircraft repair) and AIRFIELD (airfield repair, AA gun, SAM site). Without the STORE pages the four rows
            -- above stand in, with Airfield doing three jobs in turn.
            RepairAircraft = { role = "aircraft", label = "REPAIR AIRCRAFT", price = 600, min_price = 100, raise = 1.0 },
            -- (raise 1.0, was 1.25: airfield repairs are upkeep every raid, and 1.25 compounding made the 20th one 21700)
            RepairAirfield = { role = "airfield", label = "REPAIR AIRFIELD", repair = 60, price = 300, raise = 1.0 },
            AAGun          = { role = "aa",  label = "BUILD AA GUN" },          -- (prices: Airfield.defences)
            SAM            = { role = "sam", label = "BUILD SAM SITE" },
            -- Allies (CFG.allies; user, 2026-10-23: "make it so that these Allied Aircraft and Ships are expensive"):
            -- MOONCHILD on the AIRFIELD page, the ships on the DOCKS page; each purchase of one makes the next dearer
            Moonchild      = { role = "ally_air",  label = "MOONCHILD: 2 x F-22", price = 15000, raise = 1.25 },
            ShipAegis      = { role = "ally_ship", ship = "Aegis", label = "AEGIS DESTROYER", price = 20000, raise = 1.25 },
            Airfield = { role = "combined", repair = 60, price = 300, raise = 1.0, label = "REPAIR AIRFIELD",
                         defences = {
                             order = { "aa", "aa", "sam", "aa", "aa", "sam", "aa" },
                             aa  = { label = "AA GUN", what = "an AA gun", price = 4000, raise = 1.25,
                                     units = { "SV_Unit_AAGun_A", "SV_Unit_AAGun_B", "SV_Unit_AAGun_C", "SV_Unit_AAGun_D",
                                               "SV_Unit_AAGun_E" } },
                             sam = { label = "SAM SITE", what = "a SAM site", price = 8000, raise = 1.25,
                                     units = { "SV_Unit_SAM_A", "SV_Unit_SAM_B" } },
                             -- their fire control (user, 2026-10-23: "increase the fire rate of the Airfield"): the
                             -- allies' (CFG.allies.fcs: x0.5 times, x1.6 range, x1.5 cone), then arming / lock x lock_x
                             -- and time between shots / rest x fire_x (0.5: twice as often again, 4x the stock rate)
                             fcs = { lock_x = 0.75, fire_x = 0.5 },
                         } },
        },
    },
    -- Allies the STORE sells (user, 2026-10-23; tools/survival_events.py ALLY_*): MOONCHILD, two-ships of F-22s that
    -- take off from the airfield once you're airborne (up to two flights at once, takeoff_gap_s apart: both park on one
    -- spot), and allied ships sailing lanes south and north of the airfield (four Aegis destroyers, one per lane; the
    -- LCS Freedom is gone, user 2026-10-23). They fight until shot down or sunk; a lost one can be bought again. Every
    -- weapon they carry gets fire control of its own (rows <FCS>_SVA, made at the main menu): lock-on range x range_x,
    -- its cone x angle_x, arming, lock, aim and reload times x time_x, gun spread x spread_x. A ship type's own `fcs`
    -- goes further (rows <FCS>_SVA_<key>): arming and lock x lock_x, time between shots and rest x fire_x (user,
    -- 2026-10-23: "make the Aegis Lock On faster and Fire Rate increase"), and range_x in place of the allies' (user:
    -- the Aegis locks on and fires from 2x the stock range). Enemies go for them: once MOONCHILD is airborne hunt_share of the enemy fighter
    -- flights prefer it to you, and while ships are at sea strike_share of a normal round's aircraft (no specials, no
    -- raids) are strike flights sent at one of them.
    allies = {
        enabled      = true,
        hunt_share   = 0.35,                     -- (0.5 until 0.48.5: MOONCHILD was swarmed in 2 minutes)
        strike_share = 0.25,
        -- gun_lead_s / burst_x: MOONCHILD's guns aim gun_lead_s ahead (PredictionOffsetTime; stock aircraft guns 0)
        -- and fire bursts burst_x as long (stock 10 rounds); aa_lead_x: the ships' and the airfield's AA guns and CIWS
        -- lead that much further (stock AA guns 0.8 s; user, 2026-10-24: "increase the gun lead for the allied
        -- fighters too, and their bursts, increase the gun lead for allied AA guns too")
        fcs          = { range_x = 1.6, angle_x = 1.5, time_x = 0.5, spread_x = 0.4, gun_lead_s = 1.0, burst_x = 3,
                         aa_lead_x = 1.5 },
        aircraft     = { name = "MOONCHILD", name_key = "SV_Moonchild", takeoff_gap_s = 45,
                         units = { "SV_Unit_MoonchildA", "SV_Unit_MoonchildB" },
                         -- scaling with the enemy (user, 2026-10-23: "buff the allied F-22's so they scale up with the
                         -- enemy"), set as each one is seen up and again every round while it flies: PilotRank the
                         -- round's skill tier's + rank_add (at least rank_min, at most 5; not lowered on Casual), AI level
                         -- the tier's (at least ai_level_min; set before each takeoff), health x health_x x (1 +
                         -- health_per_round x (round - 1)), at most health_max_x. (Test of 2026-10-23: a 15000 Z flight
                         -- bought in round 9 was gone 112 s after takeoff.)
                         scale = { rank_add = 1, rank_min = 3, ai_level_min = 3, health_x = 2.0, health_per_round = 0.08,
                                   health_max_x = 4.5 } },
        ships        = {
            -- search_m: its turrets' AI module (a copy of NPC_AIModule_Turret000, 6000 m, made NPC_AIModule_SV_<key>),
            -- the farthest they see anything, and no losing targets in cloud. missile: its homing missiles' own weapon
            -- row (VLS_Vessel_000: 9 s of flight from 500 km/h, +300 km/h a second to 3000, ~4 km, so 6 km locks fell
            -- short; user, 2026-10-23: "aegis ships still don't engage far enough"): lock-on at range_m, life_s of
            -- flight, acceleration x accel_x, top speed speed_max_kmph, turn rate x turn_x.
            Aegis = { name = "DDG AEGIS", turrets = "aegs", fcs = { lock_x = 0.5, fire_x = 0.5, range_x = 2.0, search_m = 25000,
                                                  missile = { range_m = 20000, life_s = 30, accel_x = 2.0,
                                                              speed_max_kmph = 3600, turn_x = 1.5 } },
                      units = { "SV_Unit_ShipAegisA", "SV_Unit_ShipAegisB", "SV_Unit_ShipAegisC", "SV_Unit_ShipAegisD" } },
        },
        -- Speakers who talk as allies during a Survival run (user, 2026-10-23: the Savian mercenary leader's line at
        -- MOONCHILD's takeoff showed as an enemy's). The game reads speakers from the game instance's own
        -- DT_SpeakerTable, not the level's (a build-time copy for the level changed nothing), so the row is changed
        -- while a run is on and put back after it: ColorType 0 (ally), ProcessID `process` (Mission 22's allied
        -- fighters' radio).
        ally_speakers = { { table = "/Game/Datatables/Radio/DT_SpeakerTable.DT_SpeakerTable", row = "826",
                            id = "ms25_Savia_Mercenary_Leader", process = "Ally_Fighter_Mob" } },
        text = { takeoff = "%s CLEARED FOR TAKEOFF", takeoff_sub = "TWO F-22s JOINING THE FIGHT",
                 air_lost = "%s FLIGHT LOST", ship = "%s AT SEA", ship_sub = "ALLIED SHIP JOINING THE FIGHT",
                 sunk = "%s SUNK", lost_sub = "THE STORE CAN SEND ANOTHER",
                 strike = "STRIKE FLIGHTS INBOUND", strike_sub = "HEADING FOR OUR SHIPS" },
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
    --   aircraft_add     more aircraft each round (never above max_aircraft)
    spikes = {
        enabled = true,
        every   = 7,
        levels  = {
            { missiles = { capture_m = 4500, angle_deg = 70, lock_s = 1.2, interval_s = 1.6, rest_s = 4.0 },
              guns = { range_m = 2200, angle_deg = 45, aim_s = 0.6, burst = 18, rest_s = 0.5, spread_deg = 1.1 },
              rank_min = 4, post_stall_all = true, provoke_cone_deg = 70, provoke_time_s = 2.0, surround_m = { 80, 220 },
              aircraft_add = 2 },
            { missiles = { capture_m = 5000, angle_deg = 80, lock_s = 0.9, interval_s = 1.3, rest_s = 3.0 },
              guns = { range_m = 2400, angle_deg = 50, aim_s = 0.45, burst = 20, rest_s = 0.4, spread_deg = 0.8 },
              rank_min = 5, post_stall_all = true, provoke_cone_deg = 60, provoke_time_s = 1.5, surround_m = { 60, 160 },
              aircraft_add = 4 },
            { missiles = { capture_m = 5500, angle_deg = 90, lock_s = 0.7, interval_s = 1.0, rest_s = 2.0 },
              guns = { range_m = 2600, angle_deg = 55, aim_s = 0.3, burst = 24, rest_s = 0.3, spread_deg = 0.5, damage_x = 1.8 },
              rank_min = 5, post_stall_all = true, provoke_cone_deg = 50, provoke_time_s = 1.0, surround_m = { 50, 120 },
              aircraft_add = 6 },
        },
    },
-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
    -- The Discord leaderboard (Milestone 8; leaderboard/README.md; user, 2026-10-23: an end-of-run prompt, a
    -- Cloudflare Worker, boards for highest round, score per difficulty and fastest specials). Every run that ends (shot
    -- down, restarted or left) is submitted (user, 2026-10-23: "have it always submit a run regardless"; was a Y / N
    -- prompt), and its summary shows for show_s seconds with how it went. The name on the leaderboard: `pilot`, or when
    -- that's empty the player's Steam name (dlls/main.dll SV_SteamName), kept to what the leaderboard takes (letters,
    -- digits, space _ - ., 24 at most); with neither, Pilot-<6 hex> made once a install (config\pilot_id.txt). Runs that
    -- couldn't get through wait in config\pending_runs.txt and go at the next start. Only the leaderboard's own server is
    -- contacted (dlls/main.dll SV_Post; its address is built in).
-- ONLINE ONLY END
--OFFLINE:     -- The end-of-run summary (round, score, kills, specials, time) shows for show_s seconds. This is the Offline
--OFFLINE:     -- edition: nothing is sent anywhere.
    leaderboard = { pilot = "", show_s = 15 },
    -- Special rounds (Milestone 6): from round `first`, every `every` rounds, the next special of `rotation` instead of a
    -- normal round (a special that can't start falls back to one). "shuttle" = Comona Defense
    -- (tools/survival_events.py SHUTTLE_*): the shuttle `name` on Mission 22's pad, its AA guns, SAMs and tower around
    -- it, lifts off countdown_s after it appears. The round's fighters come for the player; strike_share of its aircraft
    -- are strike flights (no heavies) sent at the shuttle. Launched: `reward` zollars. Lost: the shop is closed for the
    -- next shop_closed_rounds rounds. countdown_s is built into the event package (SHUTTLE_COUNTDOWN_S): keep it equal.
    -- The countdown runs on Survival's own clock (D.shuttleClock), which stops while you're down at the airfield (user,
    -- 2026-10-23: it ran on in the landing store): each whole second fires that second's RE_SV_ShuttleT_<s>.
    -- random (user, 2026-10-23: "after round 3, special rounds get randomised into the normal play, they can appear on
    -- any round above 3, their difficulty increases along with the corresponding round"): from round `first` each
    -- round is a special with `chance`, never two in a row (and not the same one twice running); the pick is made
    -- once a round (RUN.specialPick), so its callout and the round agree. random = false: every `every` rounds, in
    -- `rotation` order. A special's own enemies scale with its round as a normal round's do (budget, skill tier,
    -- difficulty spikes); the Ladons, which fly alone, take ladon.bomb_per_round more bomb damage and health_per_round
    -- more health a round after `first`.
    specials = {
        enabled  = true,
        random   = true,
        chance   = 0.3,
        first    = 4,
        every    = 5,
        rotation = { "shuttle", "anomaly", "amphibious", "ladon", "alicorn", "glitch", "valka" },
        -- an early special (user, 2026-10-23: "buff the chances of the shuttle spawning between rounds 2 and 6"): in
        -- rounds from .. to, each round is `kind` with `chance` (before `first` too), under the same rules (never two
        -- specials in a row, not the same one twice running), and no other special comes in those rounds: the
        -- random picks above start after `to` (user: only the Shuttle Launch may come between 2 and 6).
        early    = { kind = "shuttle", from = 2, to = 6, chance = 0.35 },
        -- each special comes at most once in this many rounds (user, 2026-10-23): Comona Defense in round 2 can come
        -- again from round 12; the others keep their chance meanwhile. 0: no cooldown.
        cooldown_rounds = 10,
        -- "alicorn" = the ALICORN (tools/survival_events.py ALCN_*; tools/re/ALICORN.md; user, 2026-10-23: "start
        -- working on the ALICORN special round ... spawn none of the normal aircraft"): Online Mode's submarine
        -- carrier, without the fighters and drones it launches there, sailing the west sea. It dives every
        -- dive_every_s for dive_for_s, and while surfaced fires its railgun every railgun_every_s and a VLS volley at
        -- you every volley_every_s. Destroy its four ballast tanks and the core opens; destroy the core to sink it.
        -- Its parts' health x health_x (tuned for an online squad) and health_per_round more a round after `first`.
        -- Each ballast tank takes tank_missiles of your standard missiles (user, 2026-10-23: "it should only take like
        -- 6 missiles to destroy each ballast tank"; 14 missiles took none down), from the missile's own damage read in
        -- game, more a round as above; health_x when it can't be read. 0: health_x. Its weapons (weapon_classes: the
        -- VLS, SAM, AA guns, CIWS, ECM and their hatches) take weapon_missiles each, its railguns railgun_missiles
        -- (user, 2026-10-23: "lower the health down on the alicorns weaponry"; they had the online squad's 800-2000 and
        -- took 10-62.5 % from most weapons); never more than they had. 0: their online health.
        -- Its rows are Online Mode's (DT_SV_Alcn*): `tables` adds them to the campaign tables at the main menu.
        -- Debuffed across the board (user, 2026-10-23: "way too strong"; were 110 / 30 / 25 / 35 / 25, health x0.5,
        -- +0.04 a round, at most x1.5): shorter dives, its first shot later, railgun and volleys less often, less health.
        alicorn = { name = "ALICORN", dive_every_s = 120, dive_for_s = 20, first_shot_s = 40, railgun_every_s = 60,
                    volley_every_s = 45, health_x = 0.3, health_per_round = 0.03, health_max_x = 1.0,
                    tank_pay = 500, reward = 12000, reward_per_round = 400, tank_missiles = 6,
                    weapon_missiles = 3, railgun_missiles = 4,
                    weapon_classes = {   -- its weapons and their hatches: which *_missiles each takes
                        BP_BA002_alcn_hatch_emls_L_Base_C = "railgun_missiles", BP_BA002_alcn_hatch_emls_R_Base_C = "railgun_missiles",
                        BP_BA002_alcn_emls_Base_C = "railgun_missiles",
                        BP_BA002_alcn_vlsL1_Base_C = "weapon_missiles", BP_BA002_alcn_vlsL2_Base_C = "weapon_missiles",
                        BP_BA002_alcn_vlsR1_Base_C = "weapon_missiles", BP_BA002_alcn_vlsR2_Base_C = "weapon_missiles",
                        BP_BA002_alcn_vls_Base_C = "weapon_missiles", BP_BA002_alcn_ecm_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchL1_Base_C = "weapon_missiles", BP_BA002_alcn_hatchL2_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchL3_Base_C = "weapon_missiles", BP_BA002_alcn_hatchL4_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchL5_Base_C = "weapon_missiles", BP_BA002_alcn_hatchL6_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchR1_Base_C = "weapon_missiles", BP_BA002_alcn_hatchR2_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchR3_Base_C = "weapon_missiles", BP_BA002_alcn_hatchR4_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchR5_Base_C = "weapon_missiles", BP_BA002_alcn_hatchR6_Base_C = "weapon_missiles",
                        BP_BA002_alcn_aagun_Base_C = "weapon_missiles", BP_BA002_alcn_ram_Base_C = "weapon_missiles",
                        BP_BA002_alcn_ciws_Base_C = "weapon_missiles", BP_BA002_alcn_ciwsp5_Base_C = "weapon_missiles" },
                    tank_classes = { "BP_BA002_alcn_btankfl_Base_C", "BP_BA002_alcn_btankfr_Base_C",
                                     "BP_BA002_alcn_btankrl_Base_C", "BP_BA002_alcn_btankrr_Base_C" },
                    core_class = "BP_MP028_dummy_emlmcore_Base_C",
                    tables = { { "/Game/Mods/SurvivalMode/Data/DT_SV_AlcnNpc.DT_SV_AlcnNpc", "/Game/Datatables/AI/NPC/DT_NPC.DT_NPC" },
                               { "/Game/Mods/SurvivalMode/Data/DT_SV_AlcnModel.DT_SV_AlcnModel",
                                 "/Game/Datatables/AI/NPC/Model/DT_NPC_Model.DT_NPC_Model" },
                               { "/Game/Mods/SurvivalMode/Data/DT_SV_AlcnWpDur.DT_SV_AlcnWpDur",
                                 "/Game/Datatables/AI/NPC/WeaponDurability/DT_NPC_WeaponDurability.DT_NPC_WeaponDurability" },
                               { "/Game/Mods/SurvivalMode/Data/DT_SV_AlcnExDur.DT_SV_AlcnExDur",
                                 "/Game/Datatables/AI/NPC/ExplosionDurability/DT_NPC_ExplosionDurability.DT_NPC_ExplosionDurability" } } },
        -- "glitch" = AB.L..IN, squadron tag IFF: FATAL ERROR (user, 2026-10-23: "One Last Anomaly. an EA-18G Growler, It's
        -- health is set to 450. it has ECM Activated always, it's a normal aircraft, but as soon as it gets damaged, it
        -- begins to teleport at different angles, during this time, it's constantly firing it's gun at you ... for 6
        -- seconds before continuing to flight normally against you ... disappear in a small smoke cloud, also have it
        -- reappear within small smoke clouds too"; "it teleports around the player ... fully aiming at the player as
        -- it fires it's gun with extreme accuracy"). One EA-18G alone (tools/survival_events.py GLITCH_*), `health`
        -- HP (the EA-18G has 60), its ECM pod always up, an accurate gun that holds the trigger (gun_*: it fires once
        -- you're within gun_range_m and gun_angle_deg of its nose). It arrives hidden and shows in a puff of `smoke`
        -- arrive_s later. Each time it's hit (outside a frenzy) it frenzies for frenzy_s: every blink_every_s it
        -- vanishes in smoke (hidden, untargetable, unhurt) and comes back in smoke at one of the `blinks` spots around
        -- you at your height (user: "at whatever height the player is closest too"), one at least ground_clear_m above
        -- the ground, at least blink_turn_deg round you from the last one, and its gun is fired at you all
        -- through it (gun_every_s). Its health grows health_per_round a round after `first` (at most
        -- health_max_x), as the other specials'. Shot down: `reward` zollars.
        glitch   = { name = "AB.L..IN", squadron = "IFF: FATAL ERROR", unit = "SV_Unit_Glitch", health = 450,
                     reward = 7000, reward_per_round = 250, ai_level = 5, spawn_km = { 6, 9 }, arrive_s = 1.0,
                     health_per_round = 0.04, health_max_x = 3.0,
                     frenzy_s = 6, blink_every_s = 1.0, blink_turn_deg = 60, ground_clear_m = 150,
                     -- its gun and ECM pod on command (tools/survival_events.py GLITCH_GUN_* / _ECM_SLOT): through a
                     -- frenzy RE_SV_GlitchGun every gun_every_s, which fires the gun at you 5 times 0.1 s apart (user,
                     -- 2026-10-23: "make it fire at 0.1"; = GLITCH_GUN_SHOTS x GLITCH_GUN_EVERY_S, keep in step); the
                     -- pod every ecm_every_s while it's up
                     gun_every_s = 0.5, ecm_every_s = 14,
                     -- its blink spots: the event package's (tools/survival_events.py GLITCH_BLINK_*; keep in step, not
                     -- an ini setting): RE_SV_GlitchBlink_<ring letter><bearing letter>, every step_deg on each ring
                     blinks = { step_deg = 30, rings_m = { 500, 800 } },
                     gun_range_m = 1500, gun_angle_deg = 6, gun_damage_x = 1.5, gun_spread_deg = 0.1,
                     -- it leads you as MINDRIPPER does (user, 2026-10-24): gun_lead_s ahead; 0.8 s suits its blinks
                     -- 500 / 800 m from you (its rounds fly 833 m/s). Its own fire control leads by its row; in a frenzy
                     -- (user: "go through the mission event the EA-18G uses and see if you can find gun lead for it": the
                     -- event's LiveFireOneShotWeapon only aims at the target) Lua also fires it each tick gun_lead_shots
                     -- times with LiveAIGameObject.FireOneShotWeaponWithLocationTracking at where you'll be gun_lead_s on
                     -- (your velocity); gun_lead_event: the event's unled shots go on as well (false: only the led ones)
                     gun_lead_s = 0.8, gun_lead_shots = 2, gun_lead_event = true,
                     -- post-stalls on command (user, 2026-10-24: "make the EA-18G do post stalls even more"): outside
                     -- a frenzy, within post_stall_range_km of you, one of post_stall_moves (tools/survival_events.py
                     -- GLITCH_POST_STALL: Shadow / Toprak kulbits, Tasha's cobra) every post_stall_every_s, and as soon
                     -- as you get behind it (more than 110 deg off its nose within post_stall_behind_km), at least
                     -- post_stall_gap_s apart; its own cobra / kulbit are on whatever the round
                     post_stall = true, post_stall_every_s = 6, post_stall_gap_s = 3, post_stall_range_km = 3,
                     post_stall_behind_km = 1.5, post_stall_moves = { "Kulbit", "KulbitB", "Cobra" },
                     -- the dead flying (user: "look spooky like its the dead flying"): its airframe in the wreck's
                     -- burnt material, no pilot or stores, the damaged-plane smoke and fire on it
                     dead_look = true, dead_fx_scale = 1.0,
                     dead_material = "/Game/Vehicles/Aircraft/PP/PP0010_e18g/Materials/Common/MI_PP0010_e18g_DAM",
                     dead_fx = { "/Game/VFX/Vehicles/Aircraft/Common/Damage/DamagedSmokeNPC/NS_DamagedSmokeFireNPC001",
                                 "/Game/VFX/Vehicles/Aircraft/Common/Damage/DamagedSmokeNPC/NS_DamagedSmokeNPC001" },
                     smoke = "/Game/VFX/Vehicles/Aircraft/Common/Bailout/NS_BailoutSmoke001", smoke_scale = 4.0,
                     smoke_s = 3.0 },
        -- "valka" = VALKA (user, 2026-10-24: "port the Mihaly Fight from ACE7 into ACE8 Survival Mode as an Anomaly Boss,
        -- we're going to mix MINDRIPPER's abilities and ABELCAINS abilities into this new Anomaly called VALKA, who uses
        -- an EML"; tools/survival_events.py VALKA_*). AC7 Mission 18's opener: she comes hidden and is kept opener_m
        -- ahead of you, facing you; a flash of light there, the railgun WARNING and charge for charge_s, then one
        -- railgun shot at you. reveal_s after it she's on the far ring (6 km), shows, and the focus camera swings onto
        -- her (`camera`). Then a Super AI (the top fire-control level, ai_level, MINDRIPPER's attack pressure) on you
        -- alone, anywhere (user: "the AI after the initial shot will always target the player and go after the player
        -- also using the lastTGT psm ability"): LastTGT every turn_every_s and at once when you get behind her within
        -- behind_km (behind_gap_s apart), post-stalls (post_stall_*), blinks round you (AB.L..IN's: each hit outside a
        -- blink spell starts blink_s of them, one every blink_every_s, then blink_cooldown_s before the next spell), her
        -- railgun every railgun_every_s (railgun_charge_s of warning first) when you're within railgun_range_km and
        -- railgun_cone_deg of her nose, and every invert_every_s a chance of invert_chance that your controls scramble
        -- for invert_s (random_min..random_max of random_fx, as MINDRIPPER's field). Her railgun fires one round a
        -- shot (user, 2026-10-24: "Mission 26 has a 4 shot EML, I only want single shot": its part's TriggerCount and
        -- MagazineCapacity 3 -> single_shot). No AC7 voice lines, no invincibility (AC7 held Mihaly's health with
        -- SetMinHealth until a radio line; she has none). Shot down: `reward` zollars.
        valka    = { name = "VALKA", squadron = "MIHALY'S SHADOW", unit = "SV_Unit_Valka", health = 900,
                     health_per_round = 0.04, health_max_x = 2.5, reward = 9000, reward_per_round = 300, ai_level = 5,
                     spawn_km = { 6, 9 }, arrive_s = 1.0,
                     opener_m = 700, charge_s = 6.0, reveal_s = 1.5,
                     flash = "/Game/VFX/Mission/Mission023/NS_ms23FarFlash", flash_scale = 3.0, flash_s = 2.0,
                     camera = "LookAt_Event_Camera_ms22-01",
                     turn_every_s = 12, behind_km = 1.5, behind_gap_s = 4,
                     post_stall = true, post_stall_every_s = 9, post_stall_range_km = 3,
                     post_stall_moves = { "Kulbit", "KulbitB", "Cobra" },
                     blink_s = 4, blink_every_s = 1.0, blink_turn_deg = 60, ground_clear_m = 150, blink_cooldown_s = 8,
                     smoke = "/Game/VFX/Vehicles/Aircraft/Common/Bailout/NS_BailoutSmoke001", smoke_scale = 4.0,
                     smoke_s = 3.0,
                     railgun_every_s = 15, railgun_charge_s = 2.5, railgun_range_km = 5, railgun_cone_deg = 25,
                     single_shot = 1,
                     -- weapons added to her row's empty slots (slot = fire-control row): the x40a row carries flares and
                     -- missiles only; both on MINDRIPPER's quick fire control
                     weapons = { [1] = "NPC_FCS_PlaneGun000", [3] = "NPC_FCS_PlaneQAAM000" },
                     invert = "random", invert_every_s = 20, invert_chance = 0.35, invert_s = 8, fade_s = 1.0,
                     random_fx = { "pitch", "roll", "yaw", "swap", "throttle" }, random_min = 1, random_max = 2,
                     -- her teleport rings (tools/survival_events.py VALKA_SPOTS; keep in step, not an ini setting):
                     -- { ring, metres, step deg }: A the opener's, B / C her blinks, D where she shows
                     spots = { { "A", 700, 10 }, { "B", 500, 30 }, { "C", 800, 30 }, { "D", 6000, 30 } } },
        -- "ladon" = two Ladons, KOT and MISHKA (tools/survival_events.py LADON*; user, 2026-10-23): from the far west
        -- along a long route and over the airfield, then round it again and again, bombing it (bomb_damage) on every
        -- pass, until both are down. Nothing else flies in their round. Their rows: health_add HP on the Ladon's
        -- 1200, speeds x speed_x (1.0 since the route's speed went to 2500 km/h, user 2026-10-23: their rows mustn't cap
        -- it; the route's own speed is built in: LADON_SPEED). Each one down pays `reward` (+ reward_per_round x the round).
        -- volley_*: its missiles (RE_SV_LadonVolley<Key>L / R: the hatch opens, one launcher fires its salvo at you,
        -- left and right in turn) every volley_every_s while you're within volley_range_km of it, the first once
        -- you've been in range volley_warn_s, and never within volley_gap_s of the other Ladon's; its pulse cannons
        -- fire on their own. (Was both launchers every 20 s within 12 km: the player was down within 9 s of the first
        -- volley, test of 2026-10-23; then both Ladons fired together, a friend's test the same day.)
        -- missile_*: their VLS missiles (BP_wp_vls_ladon: 15 damage, 60 deg homing cone) as they appear in Survival:
        -- damage x missile_damage_x, homing cone x missile_homing_x (user, 2026-10-24: "tone that down too, only minorly").
        -- Health: user, 2026-10-24 "lower their health dramatically": 400 HP (was 900), x1.21 by round 12 (was x1.32).
        ladon = { names = { Kot = "KOT", Mishka = "MISHKA" }, health_add = -800, speed_x = 1.0, bomb_damage = 20,
                  bomb_per_round = 1, health_per_round = 0.03, health_max_x = 2.0,
                  volley_every_s = 45, volley_range_km = 8, volley_warn_s = 10, volley_gap_s = 22,
                  missile_damage_x = 0.8, missile_homing_x = 0.85,
                  reward = 6000, reward_per_round = 200,
                  npc_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcRows.DT_SV_NpcRows" },
        -- "amphibious" = Amphibious Assault (SURVIVAL_SPEC.md 7; tools/survival_events.py LCAC_*): landing craft on
        -- `lanes` (from the user's marks; `craft` craft each, side by side) cross to Comona's beaches by the airport,
        -- lanes_first of them the first time, lanes_more more each time after; each craft that reaches the beach puts a
        -- BTR-90 ashore, which drives to the runway. Each one that gets there adds capture_per_troop % to the airfield's
        -- capture (on the HUD); at 100 it is captured (landing and the STORE closed, "AIRFIELD CAPTURED") for
        -- captured_rounds rounds, or until every landed troop vehicle is destroyed (user, 2026-10-23: "each troop that
        -- reaches the runway should put a percentage on the HUD ... when it reaches 100% the airfield is captured").
        -- A round that ends short of 100 starts the next landing from 0. The round's
        -- fighters come as in a normal round, and bomber_chance of the time a bomber raid on the airfield with them
        -- (user: "enemy aircraft still spawn also, with a chance for bombers to also spawn"). No capture: `reward`
        -- (+ reward_per_round x the round); each craft pays craft_pay, each troop vehicle troop_pay (times the tier's
        -- pay, as aircraft). Craft that landed are taken off remove_after_s after landing (they're heading out).
        -- (user, 2026-10-23: "spawn all LCAC lanes, make it difficult": every lane every time, 16 craft, extra_aircraft
        -- more fighters than the round's own and a bomber raid more often)
        amphibious = { lanes = { "A", "B", "C", "D" }, craft = { "W", "X", "Y", "Z" }, lanes_first = 4, lanes_more = 1,
                       capture_per_troop = 25, extra_aircraft = 4,
                       captured_rounds = 2, bomber_chance = 0.6, reward = 4000, reward_per_round = 160,
                       craft_pay = 150, troop_pay = 150, remove_after_s = 90,
                       -- troop vehicles that stop short of the runway (a friend's test of 2026-10-23: 5 troops ashore,
                       -- none moving or to be found, so the round never ended): one that hasn't moved stuck_m in
                       -- stuck_s is taken off (no pay, no capture); without its actor to watch, after troop_timeout_s.
                       -- runway_cm: where they drive to (survival_events.LCAC_RUNWAY), for the log's distances.
                       stuck_m = 50, stuck_s = 60, troop_timeout_s = 540, runway_cm = { 1609574, -435747 } },
        -- reward_per_round: added to `reward` x the round (2026-10-23: a late special paid less than a normal round)
        shuttle  = { name = "EMBDIR Shuttle - CORRIS", countdown_s = 150, reward = 6000, reward_per_round = 200, strike_share = 0.4,
                     -- pad_allies: Mission 22's pad guns, SAMs and tower around the shuttle during the countdown
                     -- (removed after it, tools/survival_events.py PAD_REMOVE_LOST_S / SHUTTLE_REMOVE_S)
                     -- remove_s: liftoff to the shuttle and pad being taken off; = SHUTTLE_REMOVE_S (its flags reset after it)
                     remove_s = 180,
                     pad_allies = true, dummies = "SV_Unit_PadDummies",
                     shop_closed_rounds = 1, unit = "SV_Unit_Shuttle", pad = "AA_Unit_01_Ground0",
                     name_key = "SV_Shuttle_Name", npc_row = "OP0057_sstb_01_SV",
                     npc_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcRows.DT_SV_NpcRows" },
        -- "anomaly" = The Anomaly (tools/survival_events.py ANOMALY_*; user, 2026-10-22): the ace `name` in an F-4E
        -- (the campaign named-ace skin) with `guards` escorts under `guards_name`, both at the top skill tier and AI
        -- level ai_level. Within field_km of it the player's controls invert (`invert`: "both", "pitch" or "roll",
        -- or "random": each time you come into it, random_min..random_max of random_fx: pitch / roll / yaw (rudder)
        -- inverted, swap (pitch and roll swapped), throttle (throttle and brake swapped); user, 2026-10-24),
        -- fading over fade_s (dlls/main.dll SV_Invert), with the stock glasses effect and radar noise; its
        -- round starts with the stock MISSION UPDATE beep, a forced WARNING and the focus camera on it. Shot down:
        -- `reward` zollars, controls back. The round ends when it and every other enemy are down.
        -- field_km 3.2: the ECM pod's ring on the radar is 3.2 km (BP_wp_ecm_a0), so the ring shows the field
        anomaly  = { name = "MINDRIPPER", guards_name = "PHANTASM", guards = 4, field_km = 3.2, invert = "random",
                     random_fx = { "pitch", "roll", "yaw", "swap", "throttle" }, random_min = 1, random_max = 2,
                     fade_s = 1.5, reward = 8000, reward_per_round = 300, ai_level = 5, guard_offset_m = 800,
                     -- its round has nothing else in it (user, 2026-10-22: "no other aircraft other than those special
                     -- to those levels should spawn")
                     only = true,
                     -- stronger (user: "make the F-4 more stronger"; 1000 HP from 2026-10-24, was 500: a friend's
                     -- test had it down to 2 missiles 12 s into its field): the F-4E has 60 HP and turns slowly (pitch 30,
                     -- roll 90); its DT_NPC rows get health_add HP and turn_add degrees/s (MaxHealthDifference,
                     -- Pitch/Roll/YawSpeedDifference). hover: it floats (user: "didn't hover in place"): its speeds
                     -- times hover_speed (Speed*Coefficient), so it hangs in the air and turns on the spot.
                     health_add = 940, turn_add = { pitch = 120, roll = 270, yaw = 25 }, hover = true, hover_speed = 0.06,
                     -- (user, 2026-10-22: "make MINDRIPPER 5x more aggressive with everything"): its own fire control
                     -- from the top difficulty spike's, `aggression` times quicker (arm, lock, time on target, between
                     -- shots, rests; gun bursts that many times longer), half again the reach and cone, gun rounds x2
                     -- damage at half the spread; every special weapon it has room for; it reacts to you `aggression`
                     -- times quicker (provoke) and sits closer on your tail (surround_m).
                     aggression = 5, provoke_cone_deg = 30, surround_m = { 20, 60 },
                     -- its gun on top of that (user, 2026-10-24: "increase its gun accuracy and distance 20x"): spread
                     -- / gun_accuracy_x, firing range and its rounds' life (how far they fly) x gun_reach_x
                     gun_accuracy_x = 20, gun_reach_x = 20,
                     -- and it leads you (user, 2026-10-24: "make MINDRIPPER lead targets with its gun"): it aims where
                     -- you'll be gun_lead_s ahead (PredictionOffsetTime; its rounds fly 833 m/s, so 1 s suits ~0.8 km)
                     gun_lead_s = 1.0,
                     -- its guards' search range: they see you only this close, so they stay circling it and jump you
                     -- when you come near (test of 2026-10-22: with the 40 km search they left it for you and the airfield)
                     guard_search_m = 5000,
                     -- its weapon slots after the gun and missiles: two special weapons and the E-18G ace's ECM pod
                     -- (user, 2026-10-22: "a warning to the minimap for MINDRIPPER, similar to what the ECM uses": the
                     -- game draws an ECM carrier's area on the radar itself; it also makes your missiles miss near it)
                     weapons = { "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000", "NPC_FCS_ECM000" },
                     -- its arrival camera (tools/survival_events.py ANOMALY_CAMERAS; the shuttle's ms22-01 was too close)
                     -- (the shuttle's ms22-01 was too close at ~20 km: the game zooms in harder the farther the target
                     -- is; the Celaeno's ms23-01 at 8-12 km was too far out: user, 2026-10-22, "go back to the
                     -- shuttle's") the shuttle's camera, with the portal spawn_km from you, any direction (nil: anywhere)
                     -- (spawn_km 8-12 put back to the ~20 km out it was: user, 2026-10-22, "put it back to 20km")
                     camera = "LookAt_Event_Camera_ms22-01", spawn_km = { 0, 0 },     -- (0, 0: off)
                     unit = "SV_Unit_Anomaly", guard_unit = "SV_Unit_AnomalyGuards",
                     -- the Celaeno's death sounds (Mission 23's sound events, played by the event package when it's
                     -- down: tools/survival_events.py ANOMALY_DOWN_SOUNDS), loaded with the level so they can play
                     down_sounds = "/Game/WwiseAssets/Events/CS_AceLive_SE/MissionSpecific/Events_Ms23/EXP/SKY/SE_Ms23_EXP_SKY_OP0049_cleo/",
                     down_sound_names = { "AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq01_Play",
                                          "AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq02_Play",
                                          "AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq03_Play" },
                     -- (and the Celaeno's control-unit crackle on MINDRIPPER while it's up)
                     hum_sounds = "/Game/WwiseAssets/Events/CS_AceLive_SE/MissionSpecific/Events_Ms23/ARMS/SKY/SE_Ms23_ARMS_SKY_OP0049_cleo/",
                     hum_sound_names = { "AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Electricity_Play",
                                         "AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Electricity_Stop",
                                         "AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Collapse_Play" },
                     -- The portal (user, 2026-10-22: "the zoom in camera appears, then the portal, then MINDRIPPER";
                     -- lightning from the game's own electric effects). MINDRIPPER and its guards spawn hidden, the
                     -- event package's focus camera swings onto MINDRIPPER, open_at_s later the `open` systems crackle
                     -- on it for open_s, then the `burst` systems fire and they appear. Niagara systems, attached to
                     -- MINDRIPPER, `scale` times their size (they're made for one aircraft).
                     -- (user: "effects could be better"): lightning strikes all round it while it opens (strike, one
                     -- every strike_every_s within strike_m), the burst with more of them, a crackle on MINDRIPPER every
                     -- aura_every_s while it's up, and the burst again where it's shot down.
                     portal = { enabled = true, open_at_s = 1.0, open_s = 3.0, scale = 6.0,
                                strike = "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning",
                                strike_every_s = 0.3, strike_m = 350, burst_strikes = 8,
                                aura = "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricSign001",
                                aura_every_s = 2.0, aura_scale = 3.0,
                                -- every system it spawns is switched off fx_life_s after it starts (the burst where it
                                -- falls: death_fx_s), and all of them at once when it's shot down (user, 2026-10-23:
                                -- "make sure that the electric discharge despawns after the kill")
                                fx_life_s = 3.0, death_fx_s = 4.0,
                                open = { "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricSign001",
                                         "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning" },
                                burst = { "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricDischargeM001",
                                          "/Game/VFX/Mission/Mission023/NS_ms23FarFlash",
                                          "/Game/VFX/Mission/Mission027/CoreDestroy/NS_MGF_CoreDest1st_CoreElectricPlasma" } } },
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
        -- the end-of-run summary's panel (user, 2026-10-23: "a dark green background with light green edges so that we
        -- can see the text better"): its box on the 3840 x 2160 layout, its fill (r, g, b, a) and edge colour / width
        summary          = { w = 1700, y = 520, h = 690, fill = { 0.02, 0.16, 0.05, 0.82 }, edge = { 0.6, 1.0, 0.65 }, edge_px = 4 },
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
            glitch_sub   = "IFF: FATAL ERROR",
            glitch_row   = "%s: %.1f KM",
            glitch_row_frenzy = "%s: SIGNAL UNSTABLE",
            valka_sub    = "ELECTROMAGNETIC LAUNCHER DETECTED",
            valka_charge = "WARNING: RAILGUN",
            valka_charge_sub = "EML CHARGING",
            valka_row    = "%s: %.1f KM",
            valka_row_charge = "%s: RAILGUN CHARGING",
            valka_row_field  = "%s: %s",                 -- (her name, the scramble: anomaly_fx joined by " + ")
            anomaly_warn = "WARNING: %s",
            anomaly_warn_sub = "ITS FIELD SCRAMBLES YOUR CONTROLS",
            anomaly_field     = "ANOMALY FIELD",
            anomaly_field_sub = "%s",                     -- (what the field does this time: anomaly_fx joined by " + ")
            anomaly_clear     = "CONTROLS RESTORED",
            anomaly_row       = "%s: %.1f KM",
            anomaly_row_field = "ANOMALY FIELD: %s",
            anomaly_fx        = { pitch = "PITCH INVERTED", roll = "ROLL INVERTED", yaw = "RUDDER INVERTED",
                                  swap = "STICK AXES SWAPPED", throttle = "THROTTLE / BRAKE SWAPPED" },
            anomaly_down      = "%s DOWN",
            anomaly_down_sub  = "+%d ZOLLARS",
            aces_round   = "ACE SQUADRONS: %s",
            ladon_sub    = "LADONS INBOUND",
            lb_title     = "RUN OVER: %s",
            lb_lines     = { "ROUND REACHED  %d", "SCORE  %s", "KILLS  %d AIR, %d GROUND", "SPECIALS BEATEN  %d",
                             "TIME  %s", "ZOLLARS EARNED  %s" },
            lb_sending   = "SENDING...",
            lb_sent      = "SUBMITTED: SCORE %s",
            lb_queued    = "NO CONNECTION: IT WILL BE SENT NEXT TIME",
            lb_refused   = "NOT ACCEPTED: %s",

            alicorn_sub  = "SUBMARINE CONTACT",
            alicorn_go   = "THE ALICORN",
            alicorn_go_sub = "DESTROY ITS BALLAST TANKS, THEN ITS CORE",
            alicorn_row  = "ALICORN: BALLAST TANKS %d/4  CORE %s%s",
            alicorn_dive = "THE ALICORN IS DIVING",
            alicorn_surface = "THE ALICORN HAS SURFACED",
            alicorn_core = "CORE EXPOSED",
            alicorn_core_sub = "HIT THE ALICORN'S CORE",
            alicorn_down = "THE ALICORN IS SINKING",
            alicorn_down_sub = "+%d ZOLLARS",
            ladon_go     = "LADONS FROM THE WEST",
            ladon_go_sub = "STOP %s AND %s BEFORE THEY REACH THE AIRFIELD",
            ladon_row    = "LADONS LEFT: %d  BOMBING RUNS: %d",
            ladon_run    = "%s: BOMBING RUN",
            ladon_run_sub = "THE AIRFIELD IS HIT",
            ladon_down   = "%s DOWN",
            ladon_down_sub = "+%d ZOLLARS",
            amphib_sub   = "LANDING CRAFT INBOUND",
            amphib_go    = "AMPHIBIOUS ASSAULT",
            amphib_go_sub = "STOP THE LANDING CRAFT BEFORE THEY REACH THE BEACH",
            amphib_row   = "LANDING CRAFT: %d  TROOPS: %d  AIRFIELD CAPTURE: %d%%",
            ashore       = "TROOPS ASHORE",
            ashore_sub   = "STOP THEM BEFORE THEY REACH THE RUNWAY",
            troops_stuck = "TROOPS BOGGED DOWN",
            troops_stuck_sub = "%d OUT OF THE FIGHT",
            on_runway    = "TROOPS ON THE RUNWAY",
            on_runway_sub = "AIRFIELD %d%% CAPTURED",
            captured     = "AIRFIELD CAPTURED",
            captured_sub = "DESTROY THE LANDED TROOPS TO RETAKE IT",
            captured_row = "AIRFIELD CAPTURED: %d ROUND%s LEFT, %d TROOPS",
            retaken      = "AIRFIELD RETAKEN",
            retaken_sub  = "CLEARED TO LAND",
            freed        = "AIRFIELD BACK IN OUR HANDS",
            repelled     = "LANDING REPELLED",
            repelled_sub = "+%d ZOLLARS",
            shop_captured = "SHOP CLOSED: THE AIRFIELD IS CAPTURED.",
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
                    ["ammo.ace"] = "ammo.presets.ace",
                    -- (0.35.3's name for the aircraft repair, still in the survival.ini files it extended)
                    ["shop.airfield.aircraft"] = "shop.items.RepairAircraft" }
-- sections of things since taken out, still in older survival.ini files: skipped without a warning
local INI_RETIRED = { ["shop.shipfreedom"] = true, ["allies.ships.freedom"] = true }
local function iniSection(name)
    local path = name:lower()
    path = INI_ALIAS[path] or path:gsub("^shop%.", "shop.items.")
    local t = CFG
    for part in path:gmatch("[^%.]+") do
        local found = nil
        for k, v in pairs(t) do if type(k) == "string" and k:lower() == part:lower() and type(v) == "table" then found = v end end
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
-- Settings an update added to survival.default.ini (a key or a section survival.ini doesn't have, switched on or off)
-- are appended to survival.ini, switched off, with the comment lines above them, so players find them there (user,
-- 2026-10-22: "I couldn't find it in the ini"). Nothing the player wrote is changed.
local function mergeDefaults(dir)
    local d = io.open(dir .. "survival.default.ini", "r")
    local u = io.open(dir .. "survival.ini", "r")
    if not (d and u) then if d then d:close() end; if u then u:close() end; return end
    local have, sec = {}, ""
    for line in u:lines() do
        local h = line:match("^%s*%[%s*(.-)%s*%]")
        if h then sec = h:lower()
        else
            local k = line:match("^%s*;?%s*([%w_]+)%s*=")
            if k then have[sec .. "/" .. k:lower()] = true end
        end
    end
    u:close()
    local out, comments, cur, curShown = {}, {}, "", false
    for line in d:lines() do
        local h = line:match("^%s*%[%s*(.-)%s*%]")
        local k = not h and line:match("^%s*;?%s*([%w_]+)%s*=")
        if h then
            cur, curShown, comments = h, false, {}
        elseif k then
            if cur ~= "" and not have[cur:lower() .. "/" .. k:lower()] then
                if not curShown then out[#out + 1] = ""; out[#out + 1] = "[" .. cur .. "]"; curShown = true end
                for _, c in ipairs(comments) do out[#out + 1] = c end
                out[#out + 1] = line:match("^%s*;") and line or (";" .. line)
            end
            comments = {}
        elseif line:match("^%s*;") then
            comments[#comments + 1] = line
        else
            comments = {}
        end
    end
    d:close()
    if #out == 0 then return end
    local w = io.open(dir .. "survival.ini", "a")
    if not w then return end
    w:write("\n; ---- settings added by Survival Mode " .. VERSION .. " (from survival.default.ini) ----\n")
    w:write(table.concat(out, "\n") .. "\n")
    w:close()
    log("config: added the new settings to survival.ini (" .. #out .. " lines)")
end

local function loadIni()
    local dir = SCRIPT_DIR .. "..\\config\\"
    pcall(mergeDefaults, dir)
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
            if not t and not INI_RETIRED[sec:lower()] then bad[#bad + 1] = string.format("line %d: no section [%s]", n, sec) end
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
               anomaly = { "f04e" },               -- the Anomaly's MINDRIPPER and guards (not a tier: never a flight's)
               glitch = { "e18g" },                -- AB.L..IN (CFG.specials.glitch; not a tier either)
               valka = { "x40a" } },               -- VALKA (CFG.specials.valka; not a tier either)
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
-- The skill tiers (CFG.tiers): TIER.index(round) the round's own tier, TIER.pick(round) that or (promote_chance) the
-- one above it, TIER.pay(base, i) a kill's zollars at tier i (CFG.credits.tier_pay, rounded to 10) and its multiplier.
local TIER = {}
function TIER.index(round)
    local i = 1
    for k, t in ipairs(CFG.tiers.list) do if math.max(round or 1, 1) >= t.from_round then i = k end end
    return i
end
function TIER.pick(round)
    local tc, i = CFG.tiers, TIER.index(round)
    if i < #tc.list and math.random() < tc.promote_chance then i = i + 1 end
    return i
end
function TIER.pay(base, i)
    local tp = CFG.credits.tier_pay or {}
    local x = (i and (tp[i] or tp[#tp])) or 1
    return math.floor(base * x / 10 + 0.5) * 10, x
end
-- An ace round (CFG.aces first_round / every): the round's tier's squadrons only.
-- An ace round (CFG.aces first_round / every; never a special round): the tier index whose squadrons fly it (the
-- round's tier, or the first one above it that has squadrons), or nil.
local function aceRound(round, special)
    local a = CFG.aces
    if special or not (a.enabled and CFG.tiers.enabled and round >= a.first_round
        and (round - a.first_round) % math.max(1, math.floor(a.every)) == 0) then return nil end
    local ti = TIER.pick(round)
    for k = ti, #CFG.tiers.list do if ACE.roster[CFG.tiers.list[k].name:lower()] then return k end end
    return nil
end
local function withLevel(base, over)                    -- a copy of `base` with `over`'s fields
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end

local function readScript(file)
    local f = io.open(SCRIPT_DIR .. "ai\\" .. file, "r")
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
    local mission, why3 = loadObject("/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission")   -- (Survival's NPC table)
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
    -- a gun's fire-control row and its rounds' weapon row, copied under suffix `suf` (o: range, angle, aim, burst,
    -- rest, damage_x, spread, optional life_x and lead; `what` names it in the log). lead: PredictionOffsetTime, the
    -- seconds ahead of the target it aims (the stock AA guns' 0.8; every aircraft gun 0, so they aim where you are)
    local function gunRow(src, o, what, suf)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.CaptureAngleRange = o.range, o.angle
            r.TriggeringTime, r.TriggerCount, r.RestingTime = o.aim, o.burst, o.rest
            if o.lead then r.PredictionOffsetTime = o.lead end
            if wpn then
                local rounds = copy(wpn, r.NpcWeaponId:ToString(), function(x)
                    x.damage = x.damage * o.damage_x
                    x.MaxSpawnAngle = o.spread
                    if o.life_x then x.LifeTime = x.LifeTime * o.life_x end      -- (how far they fly)
                end, string.format("%sgun rounds: damage x%.1f, spread %.3f deg%s", what, o.damage_x, o.spread,
                    o.life_x and string.format(", life x%.0f", o.life_x) or ""), suf)
                if rounds then r.NpcWeaponId = FName(rounds) end
            end
        end, string.format("%sgun: within %.0f m / %.0f deg, %.2f s on target, %.0f-round bursts, rest %.2f s%s", what, o.range,
            o.angle, o.aim, o.burst, o.rest, o.lead and string.format(", leads %.2f s", o.lead) or ""), suf)
    end
    local function svGun(src, level)
        local g = withLevel(CFG.guns, spikeCfg(level).guns)
        return gunRow(src, { range = g.range_m, angle = g.angle_deg, aim = g.aim_s, burst = g.burst, rest = g.rest_s,
                             damage_x = g.damage_x, spread = g.spread_deg }, "", SPIKE_SUFFIX[level])
    end
    -- an ace tier's: the level's gun, leading you by its tier's gun_lead_s (rows _SV<level>_<TIER>), or nil (no lead set)
    local function aceGun(src, level, tier)
        local A = CFG.aces
        local base = type(A.gun_lead_s) == "table" and A.gun_lead_s[tier]
        if type(base) ~= "number" or base <= 0 then return nil end
        local lead = math.min(A.gun_lead_max or base, base + (A.gun_lead_per_level or 0) * level)
        local g = withLevel(CFG.guns, spikeCfg(level).guns)
        return gunRow(src, { range = g.range_m, angle = g.angle_deg, aim = g.aim_s, burst = g.burst, rest = g.rest_s,
                             damage_x = g.damage_x, spread = g.spread_deg, lead = lead },
                      tier .. " aces' ", SPIKE_SUFFIX[level] .. "_" .. tier)
    end
    -- MINDRIPPER's own (CFG.specials.anomaly.aggression): the top spike level's, that many times quicker (rows _SVX)
    local AN = CFG.specials.anomaly
    local AGG = math.max(1, AN.aggression or 1)
    local function anomFcs(src)
        local m = withLevel(CFG.missiles, spikeCfg(#SPIKE_SUFFIX).missiles)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.CaptureAngleRange = m.capture_m * 1.5, math.min(180, m.angle_deg * 1.5)
            r.ActivationTime, r.TriggeringTime = m.arm_s / AGG, m.lock_s / AGG
            r.ShotIntervalTime, r.RestingTime = m.interval_s / AGG, m.rest_s / AGG
            r.TriggerCount = math.max(2, r.TriggerCount or 1)             -- salvos of two
        end, string.format("MINDRIPPER's missiles: lock within %d m / %d deg, arm %.2f s, lock %.2f s, %.2f s between, rest %.2f s",
            m.capture_m * 1.5, math.min(180, m.angle_deg * 1.5), m.arm_s / AGG, m.lock_s / AGG, m.interval_s / AGG,
            m.rest_s / AGG), "x")
    end
    -- its ECM pod held up (tools/re/MINIMAP_MARKERS.md 3a: the stock row rests 30 s after each 15 s, so the radar ring
    -- comes and goes): no rest, a new pod as the last one's 15 s run out, and up from 20 km so the ring is there first
    -- (user, 2026-10-23: AB.L..IN's "ECM didn't turn on": TriggeringTime was 0.5; the stock row's 15 s matches the
    -- pod's 15 s LifeTime, so it's kept, with the 30 s rest taken out and a new pod every 14 s)
    local function anomEcm(src)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.ActivationTime = 20000, 0.5
            r.TriggeringTime, r.ShotIntervalTime, r.RestingTime = 15.0, 14.0, 0     -- (each new pod 1 s before the last ends)
            r.MagazineCapacity = 999
        end, "ECM pod (MINDRIPPER's, AB.L..IN's): always up (no rest, 15 s on, every 14 s, from 20 km)", "x")
    end
    local function anomGun(src)
        local g = withLevel(CFG.guns, spikeCfg(#SPIKE_SUFFIX).guns)
        local reach, acc = AN.gun_reach_x or 1, AN.gun_accuracy_x or 1
        return gunRow(src, { range = g.range_m * 1.5 * reach, angle = math.min(180, g.angle_deg * 1.5), aim = g.aim_s / AGG,
                             burst = math.min(200, g.burst * AGG), rest = g.rest_s / AGG, damage_x = g.damage_x * 2,
                             spread = g.spread_deg / 2 / acc, life_x = reach, lead = AN.gun_lead_s }, "MINDRIPPER's ", "x")
    end
    -- AB.L..IN's (CFG.specials.glitch gun_*): long bursts, no rest, accurate rounds (rows _SVG)
    local function glitchGun(src)
        local GL = CFG.specials.glitch
        return gunRow(src, { range = GL.gun_range_m, angle = GL.gun_angle_deg, aim = 0.05, burst = 200, rest = 0,
                             damage_x = GL.gun_damage_x, spread = GL.gun_spread_deg, lead = GL.gun_lead_s }, "AB.L..IN's ", "g")
    end
    local ok, why = cloneRow(mod, SEARCH_MODULE.src, SEARCH_MODULE.row, function(r)
        if not CFG.search.enabled then return end   -- off: the stock module's values
        r.Radius = CFG.search.radius_m
        r.bEnableLostTargetInClouds = CFG.search.lose_in_clouds
    end)
    if not ok then return giveUp("module row not added: " .. tostring(why)) end
    local guardModule = SEARCH_MODULE.row .. "_Guard"           -- the Anomaly's guards' (CFG.specials.anomaly.guard_search_m)
    local okG = cloneRow(mod, SEARCH_MODULE.src, guardModule, function(r)
        r.Radius = AN.guard_search_m
        r.bEnableLostTargetInClouds = false
    end)
    log(string.format("special: the Anomaly's guards search %d m (%s)", AN.guard_search_m, okG and guardModule or "module NOT made"))
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
            local an, gl, va = CFG.specials.anomaly, CFG.specials.glitch, CFG.specials.valka
            local c = (tier == "anomaly" and { squadron = an.guards_name, f04e = an.name })
                or (tier == "glitch" and { squadron = gl.squadron, e18g = gl.name })
                or (tier == "valka" and { squadron = va.squadron, x40a = va.name }) or CFG.aces[tier] or {}
            if tier ~= "anomaly" and tier ~= "glitch" and tier ~= "valka" and not CFG.aces.enabled then keys = {} end
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
                    if have ~= nil then
                        list[#list + 1] = ACE.row(tier, k, part:lower()); nAces = nAces + 1
                        SR.aceTier = SR.aceTier or {}
                        SR.aceTier[ACE.row(tier, k, part:lower())] = tier      -- (its gun's lead: CFG.aces.gun_lead_s)
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
                    r.NpcAIModuleId = FName((a == ACE.row("anomaly", "f04e", "w") and okG) and guardModule or SR.module)
                    if a == ACE.row("anomaly", "f04e", "l") then          -- MINDRIPPER (CFG.specials.anomaly)
                        local an = CFG.specials.anomaly
                        local okE, errE = pcall(function()           -- (a failure keeps the row, as stock)
                            r.MaxHealthDifference = an.health_add
                            r.PitchSpeedDifference, r.RollSpeedDifference = an.turn_add.pitch, an.turn_add.roll
                            r.YawSpeedDifference = an.turn_add.yaw
                            if an.hover then
                                r.SpeedNormalCoefficient, r.SpeedMaxCoefficient = an.hover_speed, an.hover_speed
                                r.SpeedMinCoefficient, r.SpeedTurnCoefficient = an.hover_speed, an.hover_speed
                            end
                        end)
                        if level == 0 then
                            log(string.format("special: %s's row %s: +%d HP, turn +%d/+%d/+%d, %s%s", an.name, svNpc,
                                an.health_add, an.turn_add.pitch, an.turn_add.roll, an.turn_add.yaw,
                                an.hover and string.format("hovers (speed x%.2f)", an.hover_speed) or "flies",
                                okE and "" or ("; NOT applied: " .. tostring(errE))))
                        end
                    end
                    if a == ACE.row("glitch", "e18g", "l") then            -- AB.L..IN (CFG.specials.glitch)
                        local gl = CFG.specials.glitch
                        local okE, errE = pcall(function() r.MaxHealthDifference = gl.health - 60 end)   -- (the EA-18G: 60)
                        if level == 0 then
                            log(string.format("special: %s's row %s: %d HP%s", gl.name, svNpc, gl.health,
                                okE and "" or ("; NOT applied: " .. tostring(errE))))
                        end
                    end
                    local ft = a:match("^sv_ace_(%a+)_")                    -- a tier's squadron: CFG.aces.flight
                    local fl = ft and CFG.aces.flight and CFG.aces.flight[ft]
                    if fl then
                        local okF, errF = pcall(function()
                            r.PitchSpeedDifference = (r.PitchSpeedDifference or 0) + fl.turn_add.pitch
                            r.RollSpeedDifference = (r.RollSpeedDifference or 0) + fl.turn_add.roll
                            r.YawSpeedDifference = (r.YawSpeedDifference or 0) + fl.turn_add.yaw
                            if fl.health_add then r.MaxHealthDifference = (r.MaxHealthDifference or 0) + fl.health_add end
                            for f, x in pairs({ SpeedMaxCoefficient = fl.speed_x, SpeedTurnCoefficient = fl.speed_x,
                                                SpeedNormalCoefficient = fl.cruise_x }) do
                                local v = r[f]
                                r[f] = ((type(v) == "number" and v > 0) and v or 1.0) * x
                            end
                        end)
                        if level == 0 then
                            log(string.format("aces: %s flies harder: turn +%d/+%d/+%d, speed x%.2f, cruise x%.2f, %+d HP%s", svNpc,
                                fl.turn_add.pitch, fl.turn_add.roll, fl.turn_add.yaw, fl.speed_x, fl.cruise_x, fl.health_add or 0,
                                okF and "" or ("; NOT applied: " .. tostring(errF))))
                        end
                    end
                    local mind = a == ACE.row("anomaly", "f04e", "l")       -- MINDRIPPER: its own, every level
                    local glitch = a == ACE.row("glitch", "e18g", "l")      -- AB.L..IN: its gun and ECM pod
                    local valka = a == ACE.row("valka", "x40a", "l")        -- VALKA: MINDRIPPER's fire control
                    if fcs and valka then              -- the x40a row has no gun: hers in slot 1, a QAAM in slot 3
                        pcall(function()
                            local va = CFG.specials.valka
                            for slot, id in pairs(va.weapons or {}) do
                                local cur = r["NpcFCSId" .. slot]:ToString()
                                if cur == "None" or cur == "" then r["NpcFCSId" .. slot] = FName(id) end
                            end
                        end)
                    end
                    if fcs then                      -- its weapon slots onto Survival's fire control for this level
                        local free, frees = nil, {}
                        for i = 0, 5 do
                            pcall(function()
                                local id = r["NpcFCSId" .. i]:ToString()
                                local new
                                if id:find("^NPC_FCS_PlaneMsl") and CFG.missiles.enabled then
                                    new = (mind or valka) and anomFcs(id) or svFcs(id, level)
                                elseif valka and id:find("^NPC_FCS_PlaneQAAM") then
                                    new = anomFcs(id)
                                elseif id:find("^NPC_FCS_PlaneGun") and CFG.guns.enabled then
                                    new = ((mind or valka) and anomGun(id)) or (glitch and glitchGun(id))
                                        or (SR.aceTier and SR.aceTier[a] and aceGun(id, level, SR.aceTier[a])) or svGun(id, level)
                                elseif glitch and id:find("ECM", 1, true) then
                                    new = anomEcm(id)                                -- its pod always up
                                elseif (id == "None" or id == "") and i >= 3 then free = free or i; frees[#frees + 1] = i end
                                if new then r["NpcFCSId" .. i] = FName(new) end
                            end)
                        end
                        local fcsList = CFG.special.fcs
                        if mind then                    -- its own (CFG.specials.anomaly.weapons: specials and the ECM pod)
                            local got = {}
                            for k, slot in ipairs(frees) do
                                local w = AN.weapons[k]
                                if w and w:find("ECM") then w = anomEcm(w) or w             -- its pod held up
                                elseif w then w = anomFcs(w) or w end                       -- its special weapons quicker too
                                if w then r["NpcFCSId" .. slot] = FName(w); got[#got + 1] = w end
                            end
                            if level == 0 then log("weapons: " .. svNpc .. " (MINDRIPPER) carries " .. table.concat(got, ", ")) end
                            free = nil
                        end
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
    local i = flightTier or TIER.pick(round)                 -- a fighter flight's was picked at its spawn
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
    local fl = p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]
    if fl and fl.post_stall then all = true end                    -- (a top tier: on, whatever its blueprint)
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

-- CFG.aces.flight <tier>.hunt: that tier's aircraft keep the player as their target (blackboard TargetActor)
function ACE.hunt(p)
    local fl = p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]   -- (its tier's)
    if not (fl and fl.hunt) then return end
    if fl.no_provoke then                       -- (every 2 s: an engagement order sets it again)
        pcall(function() if p.obj.bPermissionToProvoke then p.obj.bPermissionToProvoke = false end end)
        if not p.noProvokeSaid then
            p.noProvokeSaid = true
            local okR, v = pcall(function() return p.obj.bPermissionToProvoke end)
            log(string.format("aces: %s won't defend when tailed (bPermissionToProvoke %s)", p.name, okR and tostring(v) or "?"))
        end
    end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return end
    local bb = p.obj.AIStateComponent.BlackboardComponent
    local okT, t = pcall(function() return bb:GetValueAsObject(FName("TargetActor")) end)
    if okT and valid(t) and nameOf(t) == nameOf(pawn) then return end
    local ok = pcall(function() bb:SetValueAsObject(FName("TargetActor"), pawn) end)
    p.huntN = (p.huntN or 0) + 1
    if p.huntN == 1 or p.huntN % 30 == 0 then
        log(string.format("aces: %s back onto you (was %s)%s, %d times", p.name, okT and valid(t) and (nameOf(t):match("([^%.:]+)$") or "?") or "none",
            ok and "" or " (write failed)", p.huntN))
    end
end

-- Top-tier reversals (CFG.aces.flight <tier>.moves) and their geometry helpers
do
local function deg(a, b)                           -- the angle between two vectors, degrees
    local la = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
    local lb = math.sqrt(b.X * b.X + b.Y * b.Y + b.Z * b.Z)
    if la == 0 or lb == 0 then return 0 end
    return math.deg(math.acos(math.max(-1, math.min(1, (a.X * b.X + a.Y * b.Y + a.Z * b.Z) / (la * lb)))))
end
local function vec(v) return { X = v.X, Y = v.Y, Z = v.Z } end
-- CFG.aces.flight <tier>.moves: the reversals (RE_SV_AceTurn_NN / RE_SV_AceKulbit_NN on the plane's pool flight)
function ACE.movesTick(now, D)
    if not (D and D.round and type(SV_Event) == "function") then return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return end
    local me
    D.aceMoveAt = D.aceMoveAt or {}
    for _, p in ipairs(planes) do
        local fl = not p.down and p.unit and p.tier and p.tier.name and CFG.aces.flight and CFG.aces.flight[p.tier.name:lower()]
        if fl and fl.moves and now >= (D.aceMoveAt[p.unit] or 0) and valid(p.obj) then
            local pn, pk = p.unit:match("^ERA_Unit_(%d+)_Dep_Air(%d)$")
            if pn then
                me = me or vec(pawn:K2_GetActorLocation())
                local at, fwd = vec(p.obj:K2_GetActorLocation()), vec(p.obj:GetActorForwardVector())
                local toMe = { X = me.X - at.X, Y = me.Y - at.Y, Z = me.Z - at.Z }
                local range = km(at, me) * 1000
                local offTail = deg({ X = -fwd.X, Y = -fwd.Y, Z = -fwd.Z }, toMe)
                if range <= 3000 and offTail <= 70 then
                    local kulbit = range <= 900
                    local ev = string.format("RE_SV_%s_%02d", kulbit and "AceKulbit" or "AceTurn", (tonumber(pn) - 1) * 3 + tonumber(pk) + 1)
                    local r = SV_Event(ev)
                    D.aceMoveAt[p.unit] = now + (kulbit and 12 or 20)
                    D.aceMoves = (D.aceMoves or 0) + 1
                    if D.aceMoves <= 5 or D.aceMoves % 20 == 0 then
                        log(string.format("aces: %s has you %.0f m behind it, %.0f deg off its tail: %s (%s), %d so far", p.name,
                            range, offTail, ev, tostring(r), D.aceMoves))
                    end
                end
            end
        end
    end
end

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

-- Kill pay's multiplier now: CFG.credits.special_x in a special round, else 1.
function TIER.specialX() return (D and D.special) and (CFG.credits.special_x or 1) or 1 end

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
local HUD_ASSET = { base = "/Game/Blueprints/UI/WBP/HUD4K/Campaign/WBP_HUD_NonGlowMessage_000.WBP_HUD_NonGlowMessage_000_C",
                   font = "/Game/UI/Font/UI_FontSet_ja.UI_FontSet_ja" }
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

local function newBar(canvas, a0, a1, off, color)
    local b = newWidget("Image", "Bar")
    local c = color or CFG.hud.color
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
    local cls, why = loadObject(HUD_ASSET.base)
    if not cls then error("base widget class not loaded (" .. tostring(why) .. ")") end
    local w = wbl:Create(pc, cls, pc)
    if not valid(w) then error("WidgetBlueprintLibrary.Create returned nothing") end
    H = { widget = w, tree = w.WidgetTree, shown = nil, texts = {} }
    local root = H.tree.RootWidget
    for i = root:GetChildrenCount() - 1, 0, -1 do root:GetChildAt(i):SetVisibility(VIS.Collapsed) end   -- its own banner
    local font
    font, why = loadObject(HUD_ASSET.font)
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

    -- the end-of-run summary (LB.show): a title and its lines, centred, under the banner, on a panel behind them
    local sm = hc.summary
    H.lbPanel = newWidget("CanvasPanel", "LbPanel")
    slotIn(canvas, H.lbPanel, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, sm.y, sm.w, sm.h }, { 0.5, 0 }, false)
    local fill = newWidget("Image", "LbFill")
    fill:SetColorAndOpacity({ R = sm.fill[1], G = sm.fill[2], B = sm.fill[3], A = sm.fill[4] })
    slotIn(H.lbPanel, fill, { 0, 0 }, { 1, 1 }, { 0, 0, 0, 0 }, { 0, 0 }, false)
    local e = sm.edge_px
    newBar(H.lbPanel, { 0, 0 }, { 1, 0 }, { 0, 0, 0, e }, sm.edge)          -- top
    newBar(H.lbPanel, { 0, 1 }, { 1, 1 }, { 0, -e, 0, e }, sm.edge)         -- bottom
    newBar(H.lbPanel, { 0, 0 }, { 0, 1 }, { 0, 0, e, 0 }, sm.edge)          -- left
    newBar(H.lbPanel, { 1, 0 }, { 1, 1 }, { -e, 0, e, 0 }, sm.edge)         -- right
    H.lbPanel:SetVisibility(VIS.Collapsed)
    H.lbTitle = newText("LbTitle", 1, hc.banner_letter_spacing)
    slotIn(canvas, H.lbTitle, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, 560, 0, 0 }, { 0.5, 0 }, true)
    H.lbLines = {}
    for i = 1, 8 do
        H.lbLines[i] = newText("LbLine" .. i)
        slotIn(canvas, H.lbLines[i], { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, 560 + 30 + i * hc.line, 0, 0 }, { 0.5, 0 }, true)
    end
    H.lbTitle:SetVisibility(VIS.Collapsed)
    for _, l in ipairs(H.lbLines) do l:SetVisibility(VIS.Collapsed) end
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
    local show = ((not paused) and pawnOk and gameHud) or (LB.show ~= nil)    -- (the run's summary stays up)
    pcall(LB.hud, now)
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
        local cd = D.shuttleClock and D.shuttleClock.cd or (now - sp.at)
        setText(H.next, "nextStr", string.format(t.launch_row, clock(math.max(0, CFG.specials.shuttle.countdown_s - cd)), hp or 100))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif D.special and D.special.kind == "alicorn" and D.special.state == "sail" then
        local sp = D.special
        setText(H.next, "nextStr", string.format(t.alicorn_row, sp.tanks or 4, sp.coreOpen and "EXPOSED" or "SHUT",
            sp.dived and "  (DIVED)" or ""))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif D.special and D.special.kind == "ladon" and D.special.state == "run" then
        setText(H.next, "nextStr", string.format(t.ladon_row, SPC.ladonsLeft(D.special), D.special.runs or 0))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif D.special and D.special.kind == "amphibious" and D.special.state == "assault" then
        local craft, ashore = AMPH.counts()
        setText(H.next, "nextStr", string.format(t.amphib_row, craft, ashore, AMPH.capture()))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif RUN.captured then
        local left = math.max(0, RUN.captured.untilRound - D.round)
        local _, ashore = AMPH.counts()
        setText(H.next, "nextStr", string.format(t.captured_row, left, left == 1 and "" or "S", ashore))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif D.special and D.special.kind == "glitch" and D.special.state == "hunt" and D.special.dist then
        local gl = CFG.specials.glitch
        setText(H.next, "nextStr", D.special.frenzyUntil and string.format(t.glitch_row_frenzy, gl.name)
            or string.format(t.glitch_row, gl.name, D.special.dist))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif D.special and D.special.kind == "valka" and D.special.state == "hunt" and D.special.dist then
        local sp, va = D.special, CFG.specials.valka
        setText(H.next, "nextStr", sp.chargeAt and string.format(t.valka_row_charge, va.name)
            or sp.invertUntil and string.format(t.valka_row_field, va.name, sp.fxText or "")
            or string.format(t.valka_row, va.name, sp.dist))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif D.special and D.special.kind == "anomaly" and D.special.state == "hunt" and D.special.dist then
        local an = CFG.specials.anomaly
        setText(H.next, "nextStr", ANOM.on and string.format(t.anomaly_row_field, ANOM.fxText or "") or string.format(t.anomaly_row, an.name:upper(), D.special.dist))
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
    local dir = SCRIPT_DIR .. "..\\"
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
        if D.shipStrike and D.shipStrike[unit] then ALLY.strike(unit, D.shipStrike[unit]) end   -- (its own callout)
        if D.bomberCallout ~= D.round and (not D.special or D.special.kind == "amphibious")
            and not (D.shipStrike and D.shipStrike[unit]) then
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

-- maxLevel (the dev key Ctrl+6): the top skill tier's squadron (its ace leading) on the top fire-control level,
-- whatever the round
local function spawnFlight(unit, maxLevel)
    if BOMBER_UNIT[unit] then return spawnBomber(unit) end
    local ti = CFG.tiers.enabled and (maxLevel and #CFG.tiers.list or D.roundTier or TIER.pick(D.round)) or nil
    local tier = ti and CFG.tiers.list[ti] or {}
    D.flightTier = D.flightTier or {}
    D.flightTier[unit] = ti
    local topSpike = CFG.spikes.enabled and math.min(#CFG.spikes.levels, #SPIKE_SUFFIX) or 0
    local fcsLevel = math.max(maxLevel and topSpike or spikeLevel(D.round), tier.fcs or 0)
    local ac = searchAircraft(CFG.aircraft[math.random(#CFG.aircraft)], fcsLevel)
    local ace = (D.roundTier or maxLevel) and tier.name and ACE.flight(unit, tier.name:lower(), fcsLevel)   -- (ace rounds only)
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
        D.aceSquad = D.aceSquad or {}
        D.aceSquad[unit] = ace and true or nil                -- (the leaderboard's ace squadron kills)
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
    if sp.enabled and sp.random and #sp.rotation > 0 then
        RUN.specialPick = RUN.specialPick or {}
        local pick = RUN.specialPick
        if pick[round] == nil then
            local kind, early = false, sp.early
            -- each special at most once in cooldown_rounds (user, 2026-10-23: "Each Special Round can only Spawn Once
            -- Every 10 rounds"): one that started in round r can't come again before r + cooldown_rounds
            local function ready(k)
                local last = RUN.specialAt and RUN.specialAt[k]
                return not last or round - last >= (sp.cooldown_rounds or 0)
            end
            -- (in the early window only the early special comes: user, 2026-10-23, "between 2 and 6 ... I only
            -- wanted the Shuttle Launch to ever do"; the others start after it)
            local inEarly = early and early.kind and round >= (early.from or 0) and round <= (early.to or -1)
            if inEarly then
                if not pick[round - 1] and RUN.lastSpecial ~= early.kind and ready(early.kind) and math.random() < (early.chance or 0) then
                    kind = early.kind
                    RUN.lastSpecial = kind
                end
            elseif round >= sp.first and not pick[round - 1] and math.random() < sp.chance then
                local choices = {}
                for _, k in ipairs(sp.rotation) do
                    if (k ~= RUN.lastSpecial or #sp.rotation == 1) and ready(k) then choices[#choices + 1] = k end
                end
                if #choices > 0 then                       -- (every one cooling down: a normal round)
                    kind = choices[math.random(#choices)]
                    RUN.lastSpecial = kind
                end
            end
            pick[round] = kind
            if kind then log(string.format("specials: round %d will be %s", round, kind)) end
        end
        return pick[round] or nil
    end
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
    D.shuttleClock = { cd = 0, fired = 0, at = D.now, s = D.special }
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
-- SV_Invert on the player's plane) and RE_SV_AnomalyFieldOn / Off switch the stock glasses effect and radar
-- noise; the event package does the start (MISSION UPDATE beep, WARNING, focus camera) and the end when it's down.
do
-- the field's effects this time: { pitch = true, ... }. invert = "random" (user, 2026-10-24: "random each time"):
-- random_min..random_max of random_fx, picked each time you come into it; else "both", "pitch" or "roll" as before.
local FX_ORDER = { "pitch", "roll", "yaw", "swap", "throttle" }
local function pickFx(c)
    if c.invert ~= "random" then return { pitch = c.invert == "both" or c.invert == "pitch",
                                          roll = c.invert == "both" or c.invert == "roll" } end
    local pool = {}
    for _, k in ipairs(c.random_fx or FX_ORDER) do pool[#pool + 1] = k end
    if #pool == 0 then return { pitch = true, roll = true } end
    local lo = math.max(1, math.min(#pool, c.random_min or 1))
    local n, fx = math.random(lo, math.max(lo, math.min(#pool, c.random_max or 2))), {}
    for _ = 1, n do fx[table.remove(pool, math.random(#pool))] = true end
    return fx
end
local function setField(on, s)
    if ANOM.on == on then return end
    ANOM.on = on
    local c, t = CFG.specials.anomaly, CFG.hud.text
    local fx = on and pickFx(c) or {}
    if on then
        local names = {}
        for _, k in ipairs(FX_ORDER) do if fx[k] then names[#names + 1] = (t.anomaly_fx or {})[k] or k:upper() end end
        ANOM.fxText = table.concat(names, " + ")
    end
    local r = "no runtime"
    if type(SV_Invert) == "function" then        -- off keeps the plane, so the controls fade back
        local function b(k) return fx[k] and 1 or 0 end
        r = SV_Invert(b("pitch"), b("roll"), c.fade_s, ANOM.pawn or 0, b("yaw"), b("swap"), b("throttle"))
    end
    if type(SV_Event) == "function" then SV_Event(on and "RE_SV_AnomalyFieldOn" or "RE_SV_AnomalyFieldOff") end
    if s and s.state == "hunt" then
        hudCallout(on and t.anomaly_field or t.anomaly_clear, on and string.format(t.anomaly_field_sub, ANOM.fxText) or nil)
    end
    log(string.format("special: anomaly field %s (%s, %.1f km; SV_Invert %s)", on and "ON" or "off",
        on and ANOM.fxText or "controls back", s and s.dist or -1, tostring(r)))
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
    local px, py, pb = ANOM.nearPlayer(c.spawn_km)
    if px then                                     -- spawn_km from the player, inside the combat zone
        x, y, bearing = px, py, pb
        local dx, dy = px - AIRFIELD.X, py - AIRFIELD.Y
        dist = math.sqrt(dx * dx + dy * dy) / 100000
    end
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local top = #CFG.tiers.list
    D.flightTier = D.flightTier or {}
    -- hidden the moment they exist (user, 2026-10-22: "MINDRIPPER spawned in for a singular moment before it actually
    -- goes into hidden mode"): the planes are created inside SV_Spawn (NotifyOnNewObject queues them in `pending`), so
    -- they're hidden right after it returns, before a frame is drawn, not on the next tick
    ANOM.hidden = {}
    local portal = c.portal.enabled
    local function hideNew(unit)
        local n = 0
        for _, q in ipairs(pending) do
            local a = q.unit == unit and valid(q.obj) and addrOf(q.obj)
            if a and not ANOM.hidden[a] and pcall(function() q.obj:SetActorHiddenInGame(true) end) then
                ANOM.hidden[a], n = q.obj, n + 1
            end
        end
        return n
    end
    for k, part in ipairs({ { c.unit, lead }, { c.guard_unit, wing } }) do
        local unit, row = part[1], part[2]
        local set = SV_SetAircraft(unit, searchAircraft(row, level))
        if type(SV_SetLevel) == "function" then SV_SetLevel(unit, c.ai_level * 100) end
        local off = (k - 1) * c.guard_offset_m * 100
        spawningUnit = unit
        local r = SV_Spawn(unit, x + off, y + off, alt * 100, (bearing + 180) % 360)
        spawningUnit = nil
        if portal and r > 0 then
            local h = hideNew(unit)
            if h < r then log(string.format("special: anomaly %s: %d of %d hidden at once (the rest on the next tick)", unit, h, r)) end
        end
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
    -- the camera first (it looks at the hidden MINDRIPPER), then the portal opens on it, then it shows
    local cam = 1
    for k, n in ipairs(ANOMALY_CAMERAS) do if n == c.camera then cam = k end end
    local ev = "RE_SV_AnomalyCam_" .. string.char(64 + cam)
    local r = type(SV_Event) == "function" and SV_Event(ev) or "n/a"
    log(string.format("special: anomaly camera %s (%s): %s", ANOMALY_CAMERAS[cam], ev, tostring(r)))
    return true
end

local niagaraSaid = false
-- Every system the Anomaly spawns, so none outlives it: { comp, offAt, goneAt }.
ANOM.fx = {}
local function keepFx(comp, life)
    if comp and comp:IsValid() then
        ANOM.fx[#ANOM.fx + 1] = { comp = comp, offAt = ((D and D.now) or 0) + life }
    end
end
-- Each tick (any special state): switch off what's had its time, then take it away; at the kill (`all`), every one.
function ANOM.cleanFx(now, all)
    local keep = {}
    for _, e in ipairs(ANOM.fx) do
        if all and not e.goneAt then e.offAt = now end
        local alive = false
        pcall(function() alive = e.comp:IsValid() end)               -- (a one-shot may have destroyed itself)
        if alive and not e.goneAt and now >= e.offAt then
            pcall(function() e.comp:Deactivate() end)               -- stops spawning; what's out fades
            e.goneAt = now + 2
        end
        if not alive then
            -- gone already
        elseif e.goneAt and now >= e.goneAt then
            if not pcall(function() e.comp:K2_DestroyComponent(e.comp) end) then pcall(function() e.comp:DestroyComponent() end) end
        else
            keep[#keep + 1] = e
        end
    end
    ANOM.fx = keep
end

-- The portal's Niagara systems (CFG.specials.anomaly.portal), attached to actor `o` (offset: cm in its frame; scale:
-- the portal's by default; life: seconds until it's switched off); how many came up.
local function portalFx(list, o, offset, scale, life)
    local pc = CFG.specials.anomaly.portal
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (valid(lib) and valid(o)) then return 0 end
    local n, sc = 0, scale or pc.scale
    for _, path in ipairs(list) do
        local name = path:match("[^/]+$")
        local sys = loadObject(path .. "." .. name)
        local ok, err = pcall(function()
            local comp = lib:SpawnSystemAttached(sys, o:K2_GetRootComponent(), FName("None"), offset or { X = 0, Y = 0, Z = 0 },
                { Pitch = 0, Yaw = 0, Roll = 0 }, 0, true, true, 0, true)
            if comp and comp:IsValid() then comp:SetWorldScale3D({ X = sc, Y = sc, Z = sc }) end
            keepFx(comp, life or pc.fx_life_s)
        end)
        if ok and sys then n = n + 1
        elseif not niagaraSaid then niagaraSaid = true; log("special: portal system " .. name .. " failed: " .. tostring(err)) end
    end
    return n
end

-- One lightning strike on `o` at a random point within strike_m (cm offsets in its frame).
local function strike(o)
    local pc = CFG.specials.anomaly.portal
    local r = pc.strike_m * 100
    return portalFx({ pc.strike }, o, { X = (math.random() * 2 - 1) * r, Y = (math.random() * 2 - 1) * r,
                                         Z = (math.random() * 2 - 1) * r * 0.5 })
end

-- The same systems at a world location (where MINDRIPPER was shot down; AB.L..IN's smoke), switched off after `life`
-- seconds (the portal's death_fx_s by default); how many came up.
local function fxAt(list, at, scale, life)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (valid(lib) and valid(survivalPC) and at) then return 0 end
    local n = 0
    for _, path in ipairs(list) do
        local name = path:match("[^/]+$")
        local sys = loadObject(path .. "." .. name)
        if sys and pcall(function()
            local comp = lib:SpawnSystemAtLocation(survivalPC, sys, at, { Pitch = 0, Yaw = 0, Roll = 0 },
                { X = scale, Y = scale, Z = scale }, true, true, 0, true)
            keepFx(comp, life or CFG.specials.anomaly.portal.death_fx_s)
        end) then n = n + 1 end
    end
    return n
end

-- MINDRIPPER's and its guards' actors (just created ones too: they're hidden before they're logged)
local function anomalyActors(c)
    local out = {}
    for _, list in ipairs({ planes, pending }) do
        for _, q in ipairs(list) do
            if (q.unit == c.unit or q.unit == c.guard_unit) and valid(q.obj) then out[#out + 1] = q end
        end
    end
    return out
end

-- The portal: hidden on arrival, the opening crackle on MINDRIPPER, then the burst and they appear.
local function portalTick(now, s, c)
    local pc, lead = c.portal, nil
    for _, q in ipairs(anomalyActors(c)) do
        local a = addrOf(q.obj)
        if a and not ANOM.hidden[a] then
            ANOM.hidden[a] = q.obj
            pcall(function() q.obj:SetActorHiddenInGame(true) end)
        end
        if q.unit == c.unit then lead = q.obj end
    end
    if not s.opened and now - s.at >= pc.open_at_s then
        s.opened, s.nextStrike = true, now
        log(string.format("special: anomaly portal opens (%d systems)", lead and portalFx(pc.open, lead) or 0))
    end
    if s.opened and lead and now >= (s.nextStrike or now) then            -- lightning all round it while it opens
        s.nextStrike = now + pc.strike_every_s
        strike(lead)
    end
    if now - s.at >= pc.open_at_s + pc.open_s then
        local n = lead and portalFx(pc.burst, lead) or 0
        for _ = 1, pc.burst_strikes do if lead then strike(lead) end end
        local shown = 0
        for _, o in pairs(ANOM.hidden) do
            if valid(o) and pcall(function() o:SetActorHiddenInGame(false) end) then shown = shown + 1 end
        end
        s.state = "hunt"
        local t = CFG.hud.text
        hudCallout(string.format(t.anomaly_warn, c.name:upper()), t.anomaly_warn_sub)
        log(string.format("special: anomaly portal burst (%d systems), %d aircraft through", n, shown))
    end
end

-- A point spawn_km = { nearest, farthest } from the player at a random bearing, inside the combat zone: x, y (cm),
-- bearing (degrees) and its distance from the player (km); nil if the player can't be found or none fits in 30 tries.
function ANOM.nearPlayer(spawn_km)
    local you = spawn_km and (spawn_km[2] or 0) > 0 and playerLocation()
    if not you then return nil end
    for _ = 1, 30 do
        local b, d = math.random() * 360, spawn_km[1] + math.random() * (spawn_km[2] - spawn_km[1])
        local px, py = you.X + d * 100000 * math.cos(math.rad(b)), you.Y + d * 100000 * math.sin(math.rad(b))
        if math.abs(px - ZONE.X) < ZONE.HALF and math.abs(py - ZONE.Y) < ZONE.HALF then return px, py, b, d end
    end
    return nil
end

-- AB.L..IN (CFG.specials.glitch; tools/survival_events.py GLITCH_*): its actor (just created ones too), where an actor
-- is, and the ground under a point (a straight-down trace: it finds terrain only near the player, hard rule 27, which
-- is where it blinks).
local function glitchActor(c)
    for _, list in ipairs({ planes, pending }) do
        for _, q in ipairs(list) do if q.unit == c.unit and valid(q.obj) then return q.obj end end
    end
end
local function where(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local kismet = nil
local function groundAt(x, y)
    if not valid(kismet) then kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    local ks = kismet
    if not (valid(ks) and valid(survivalPC)) then return nil end
    local hit, z = {}, nil
    pcall(function()
        ks:LineTraceSingle(survivalPC, { X = x, Y = y, Z = 1000000 }, { X = x, Y = y, Z = -100000 }, 0, true, {}, 0,
            hit, true, { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    end)
    pcall(function()
        local h = hit.OutHit or hit
        local l = h.ImpactPoint or h.Location
        if l and l.Z then z = l.Z end
    end)
    return z
end
-- gone (hidden, no collision, no target box, can't be locked or targeted, can't be hurt) or back; the first time, the
-- log says which of those took (code review of 2026-10-23: hidden alone left its TGT box and lock up)
local glitchFlagsSaid = false
local function setGone(o, gone)
    local r = {}
    r[#r + 1] = pcall(function() o:SetActorHiddenInGame(gone) end) and "hidden" or "hidden FAILED"
    r[#r + 1] = pcall(function() o:SetActorEnableCollision(not gone) end) and "collision" or "collision FAILED"
    for _, f in ipairs({ { "bShowHUDBox", not gone }, { "bIsNotLockonTarget", gone }, { "bIsNotFCSTargets", gone },
                         { "bIsInvincible", gone } }) do
        r[#r + 1] = pcall(function() o[f[1]] = f[2] end) and f[1] or (f[1] .. " FAILED")
    end
    if gone and not glitchFlagsSaid then glitchFlagsSaid = true; log("special: AB.L..IN gone: " .. table.concat(r, ", ")) end
end
local function glitchSmoke(s, at)
    local c = CFG.specials.glitch
    if at and fxAt({ c.smoke }, at, c.smoke_scale, c.smoke_s) == 0 and not s.smokeSaid then
        s.smokeSaid = true
        log("special: AB.L..IN's smoke " .. c.smoke .. " didn't spawn")
    end
end

-- Its dead look (user, 2026-10-23: "I want the aircraft to look spooky like its the dead flying"): its own airframe
-- in its wreck's burnt material (each slot's <material>_DAM, the one the game puts on the wreck; dead_material when a
-- slot has none), an empty cockpit and no stores (pilot and missile meshes hidden), and the damaged-plane smoke and
-- fire (dead_fx) on it. (The BP's wreck meshes, DamagedMainBodyMesh / DamagedPartsMesh, don't draw on a live plane:
-- shown, with the airframe hidden, nothing was left, test of 2026-10-23.) Each step is logged once.
local function glitchDeadLook(c, o)
    local swapped, slots, hidden, names = 0, 0, 0, {}
    local fallback = loadObject(c.dead_material .. "." .. c.dead_material:match("[^/]+$"))
    local seen = {}
    for _, n in ipairs({ "PlaneBodyMeshComponent", "PlaneBodySkelMeshComponent", "PlaneBodyStaticMeshComponent", "PlaneBodyMesh" }) do
        local ok, comp = pcall(function() return o[n] end)
        local key = ok and comp and valid(comp) and (addrOf(comp) or n)
        if key and not seen[key] then
            seen[key] = true
            local okN, num = pcall(function() return comp:GetNumMaterials() end)
            for i = 0, (okN and type(num) == "number" and num or 0) - 1 do
                slots = slots + 1
                local dam, src = nil, "?"
                pcall(function()                         -- /Game/.../MI_x.MI_x -> /Game/.../MI_x_DAM.MI_x_DAM
                    -- (a slot may hold a run-time copy, a MaterialInstanceDynamic: its asset is up its Parent chain;
                    -- test of 2026-10-23: 1 of 13 slots found its _DAM by the slot's own name)
                    local m = comp:GetMaterial(i)
                    for _ = 1, 4 do
                        local path = m:GetPathName()
                        local pkg, obj = path:match("^(/Game/[^%.:]+)%.([^%.:]+)$")   -- (an asset, not a run-time copy)
                        if pkg then
                            src = obj
                            dam = obj:find("_DAM$") and m or loadObject(pkg .. "_DAM." .. obj .. "_DAM")
                            break
                        end
                        m = m.Parent
                        if not m then break end
                    end
                end)
                local m = dam or fallback
                if m and pcall(function() comp:SetMaterial(i, m) end) then swapped = swapped + 1 end
                names[#names + 1] = string.format("slot %d %s%s", i, src, dam and "" or " -> common")
            end
        end
    end
    for _, n in ipairs({ "PilotMeshComponent", "PilotMesh0", "PilotMesh1", "MissileMesh1", "MissileMesh2" }) do
        local ok, comp = pcall(function() return o[n] end)
        local key = ok and comp and valid(comp) and (addrOf(comp) or n)
        if key and not seen[key] then
            seen[key] = true
            if pcall(function() comp:SetHiddenInGame(true, false) end) then hidden = hidden + 1; names[#names + 1] = n end
        end
    end
    local fx = portalFx(c.dead_fx, o, nil, c.dead_fx_scale, 3600)
    log(string.format("special: %s's dead look: %d of %d material slots burnt, %d meshes hidden, %d smoke/fire systems (%s)",
        c.name, swapped, slots, hidden, fx, table.concat(names, ", ")))
end

-- AB.L..IN on its ace row at the top fire-control level, gone until its smoke (glitchTick); false if it can't come.
function ANOM.glitchSpawn(now)
    local c = CFG.specials.glitch
    local row = ACE.row("glitch", "e18g", "l")
    if not SR.usable[row] then
        log("special: AB.L..IN's row wasn't in before this level loaded; a normal round instead")
        return false
    end
    local x, y, _, bearing = spawnPoint()
    local px, py, pb, pd = ANOM.nearPlayer(c.spawn_km)
    if px then x, y, bearing = px, py, pb end
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local set = SV_SetAircraft(c.unit, searchAircraft(row, #SPIKE_SUFFIX))
    if type(SV_SetLevel) == "function" then SV_SetLevel(c.unit, c.ai_level * 100) end
    spawningUnit = c.unit
    local r = SV_Spawn(c.unit, x, y, alt * 100, (bearing + 180) % 360)
    spawningUnit = nil
    local hidden = 0
    for _, q in ipairs(pending) do                     -- gone before a frame is drawn (as MINDRIPPER)
        if q.unit == c.unit and valid(q.obj) then setGone(q.obj, true); hidden = hidden + 1 end
    end
    log(string.format("special: AB.L..IN as %s (%s set), %s at bearing %.0f, %.1f km up: %s (%d hidden)", row, tostring(set),
        pd and string.format("%.1f km from you", pd) or "at a spawn point", bearing or -1, alt / 1000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")"), hidden))
    if r <= 0 then return false end
    D.flightTier = D.flightTier or {}
    D.up[c.unit], D.flown[c.unit], D.flightTier[c.unit] = true, true, #CFG.tiers.list
    D.special.state, D.special.at = "arrive", now
    return true
end

-- A blink: the spot it comes back to (CFG.specials.glitch.blinks; the event package moves it there, from the player at
-- their height, nose on them: the flight model undoes a Lua move). Anywhere round the player, but at least
-- blink_turn_deg round from the last one (user, 2026-10-23: "it teleports but only to one spot on me": behind its own
-- flight path it kept the same side, as it flies at the player), and never one under ground_clear_m above the ground
-- (less when the player flies lower than that).
-- Returns its event, the point, its distance (cm), the ground and its bearing, or nil.
local function blinkSpot(c, s, you)
    local bl = c.blinks
    local want = math.random() * 360
    if s.lastDeg then want = s.lastDeg + c.blink_turn_deg + math.random() * (360 - 2 * c.blink_turn_deg) end
    local spots = {}
    for ring, m in ipairs(bl.rings_m) do
        for k = 0, math.floor(360 / bl.step_deg) - 1 do
            local deg = k * bl.step_deg
            local off = math.abs((deg - want + 180) % 360 - 180)
            local fromLast = s.lastDeg and math.abs((deg - s.lastDeg + 180) % 360 - 180) or 360
            spots[#spots + 1] = { ev = "RE_SV_GlitchBlink_" .. string.char(64 + ring) .. string.char(65 + k), deg = deg, d = m * 100,
                                  off = off + math.random() * bl.step_deg            -- (either ring, near the bearing wanted)
                                        + (fromLast < c.blink_turn_deg and 1000 or 0) }   -- (last resort: near the last)
        end
    end
    table.sort(spots, function(p, q) return p.off < q.off end)
    -- the clearance wanted: ground_clear_m, or 80 % of the player's own height over the ground under them when they
    -- fly lower (code review of 2026-10-23: at 100 m over the sea every spot failed 150 m, so no blinks at all)
    local under = groundAt(you.X, you.Y)
    local clear = c.ground_clear_m * 100
    if under then clear = math.max(0, math.min(clear, (you.Z - under) * 0.8)) end
    for _, p in ipairs(spots) do
        local to = { X = you.X + p.d * math.cos(math.rad(p.deg)), Y = you.Y + p.d * math.sin(math.rad(p.deg)), Z = you.Z }
        local ground = groundAt(to.X, to.Y)
        if not ground or to.Z >= ground + clear then return p.ev, to, p.d, ground, p.deg end
    end
    return nil
end

-- Every tick of AB.L..IN's round: its arrival in smoke, its frenzies (a hit starts one: it blinks around the player,
-- nose on them, gun firing), and its end.
function ANOM.glitchTick(now, s)
    local c, t = CFG.specials.glitch, CFG.hud.text
    local o = glitchActor(c)
    if s.state == "arrive" then
        if o then setGone(o, true) end
        if not o and now - s.at >= c.arrive_s + 3 then             -- never found: on with the fight as it is
            s.state = "hunt"
            log(string.format("special: %s's actor not found %.0f s after it spawned; its round goes on without the blinks", c.name, now - s.at))
            return
        end
        if now - s.at < c.arrive_s or not o then return end
        -- its health for its round (as the Ladons' and the Alicorn's: health_per_round more a round after `first`)
        local hx = math.min(c.health_max_x or 1, 1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first))
        local okH, h0 = pcall(function() return o.HealthInternal end)
        if okH and type(h0) == "number" and h0 > 0 and hx ~= 1 then pcall(function() o.HealthInternal = h0 * hx end) end
        -- its damage model (smoke, fire, damaged look) goes by health against MaxHealth (user, 2026-10-23: "make the
        -- EA-18G use it's damage model"): MaxHealth (HP; HealthInternal is HP x 10) raised to what it has, if under
        local okM, mh = pcall(function() return o.MaxHealth end)
        local okN, hn = pcall(function() return o.HealthInternal end)
        local raised = false
        if okM and okN and type(mh) == "number" and type(hn) == "number" and mh * 10 < hn then
            raised = pcall(function() o.MaxHealth = hn / 10 end)
        end
        log(string.format("special: %s health %s of MaxHealth %s%s", c.name, tostring(okN and hn), tostring(okM and mh),
            raised and string.format(" (raised to %s)", tostring(o.MaxHealth)) or ""))
        setGone(o, false)
        if c.dead_look then pcall(glitchDeadLook, c, o) end
        glitchSmoke(s, where(o))
        s.state = "hunt"
        hudCallout(c.name, c.squadron)
        log(string.format("special: %s (%s) appears in smoke, health x%.2f (%s)", c.name, c.squadron, hx, tostring(okH and h0)))
        return
    end
    if s.state ~= "hunt" then return end
    if SV_UnitAlive(c.unit) <= 0 then
        s.state = "done"
        ANOM.cleanFx(now, true)                         -- (its smoke and fire off)
        if s.lastAt then glitchSmoke(s, s.lastAt) end
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, c.name .. " down")
        LB.special("glitch", true, now - s.at)
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, pay))
        log(string.format("special: round %d, %s shot down %.0f s after it appeared (%d frenzies, %d blinks)", D.round, c.name,
            now - s.at, s.frenzies or 0, s.blinks or 0))
        return
    end
    if not o then return end
    local at, you = where(o), playerLocation()
    s.lastAt = at or s.lastAt
    if at and you then s.dist = math.sqrt((at.X - you.X) ^ 2 + (at.Y - you.Y) ^ 2 + (at.Z - you.Z) ^ 2) / 100000 end
    local okH, h = pcall(function() return o.HealthInternal end)
    h = okH and type(h) == "number" and h or nil
    if h and s.lastHp and h < s.lastHp - 0.5 and not s.frenzyUntil then      -- hit: a frenzy
        s.frenzyUntil, s.nextBlink = now + c.frenzy_s, now
        s.frenzies = (s.frenzies or 0) + 1
        local okD, dmg = pcall(function() return o:GetDamagePercentage() end)
        log(string.format("special: %s hit (%.0f -> %.0f, damage %s %%): frenzy %d for %.0f s", c.name, s.lastHp, h,
            okD and string.format("%.0f", dmg) or "?", s.frenzies, c.frenzy_s))
    end
    s.lastHp = h or s.lastHp
    if now >= (s.ecmFireAt or 0) then                   -- its ECM pod up (fired by event: hard to keep up by its FCS)
        s.ecmFireAt = now + c.ecm_every_s
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_GlitchEcm") or -5
        if r ~= 1 and not s.ecmSaid then s.ecmSaid = true; log("special: RE_SV_GlitchEcm not fired: " .. (SV_ERR[r] or tostring(r))) end
    end
    if c.post_stall and not s.frenzyUntil and at and you and s.dist and s.dist <= c.post_stall_range_km then
        if not s.psOn then                              -- its own cobra / kulbit too, whatever the round's spike
            s.psOn = true
            pcall(function() o.bCanManeuverPugachevsCobra = true; o.bCanManeuverKulbit = true end)
        end
        local behind = false                            -- you more than 110 deg off its nose, close
        if s.dist <= c.post_stall_behind_km then
            local okF, f = pcall(function() local q = o:GetActorForwardVector(); return { X = q.X, Y = q.Y, Z = q.Z } end)
            local tx, ty, tz = you.X - at.X, you.Y - at.Y, you.Z - at.Z
            local n = math.sqrt(tx * tx + ty * ty + tz * tz)
            behind = okF and n > 0 and (f.X * tx + f.Y * ty + f.Z * tz) / n < math.cos(math.rad(110)) or false
        end
        local moves = c.post_stall_moves or {}
        if #moves > 0 and type(SV_Event) == "function" and (now >= (s.psAt or 0) or (behind and now >= (s.psGapAt or 0))) then
            local mv = moves[math.random(#moves)]
            local r = SV_Event("RE_SV_Glitch" .. mv)
            s.psAt, s.psGapAt, s.psN = now + c.post_stall_every_s, now + c.post_stall_gap_s, (s.psN or 0) + 1
            if s.psN <= 5 or s.psN % 10 == 0 then
                log(string.format("special: %s post-stall %d: %s (%s), %.1f km from you%s", c.name, s.psN, mv, tostring(r),
                    s.dist, behind and ", you behind it" or ""))
            end
        end
    end
    if not s.frenzyUntil then return end
    if s.check and at and you then                      -- the last blink, a tick on: where it really is
        local k, to = s.check.n, s.check.to
        local okV, v = pcall(function() local q = o:GetVelocity(); return { X = q.X, Y = q.Y, Z = q.Z } end)
        local speed = okV and v and math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) or 0
        local off = -1                                    -- the angle between its flight path and the player
        if speed > 0 then
            local ax, ay, az = you.X - at.X, you.Y - at.Y, you.Z - at.Z
            local n = math.sqrt(ax * ax + ay * ay + az * az)
            off = math.deg(math.acos(math.max(-1, math.min(1, (ax * v.X + ay * v.Y + az * v.Z) / (n * speed)))))
        end
        log(string.format("special: %s blink %d (%s): a tick on it's %.0f m from the spot, %.0f m from you, %.0f m/s, flight path %.0f deg off you",
            c.name, k, s.check.ev, math.sqrt((at.X - to.X) ^ 2 + (at.Y - to.Y) ^ 2 + (at.Z - to.Z) ^ 2) / 100,
            math.sqrt((at.X - you.X) ^ 2 + (at.Y - you.Y) ^ 2 + (at.Z - you.Z) ^ 2) / 100, speed / 100, off))
        s.check = nil
    end
    if s.vanished then                                  -- back, around the player at their height, nose on them
        local ev, to, d, ground, deg
        if you then ev, to, d, ground, deg = blinkSpot(c, s, you) end
        if ev then
            s.lastDeg = deg
            local r = type(SV_Event) == "function" and SV_Event(ev) or -5
            s.blinks = (s.blinks or 0) + 1
            if r ~= 1 then log(string.format("special: %s blink %s not fired: %s", c.name, ev, SV_ERR[r] or tostring(r))) end
            if s.blinks <= 3 then
                s.check = { n = s.blinks, ev = ev, to = to }
                log(string.format("special: %s blink %d: %s, %.0f m from you, ground %s", c.name, s.blinks, ev, d / 100,
                    ground and string.format("%.0f m", ground / 100) or "?"))
            end
            glitchSmoke(s, to)
        end
        setGone(o, false)
        s.vanished, s.nextBlink = false, now + c.blink_every_s
    elseif now >= s.frenzyUntil then                    -- the frenzy's over: it flies on as it was
        s.frenzyUntil = nil
        log(string.format("special: %s's frenzy %d over (%d blinks, %d gun orders so far)", c.name, s.frenzies or 0,
            s.blinks or 0, s.shots or 0))
    elseif now >= s.nextBlink then                      -- gone in a puff (back next tick)
        glitchSmoke(s, at)
        setGone(o, true)
        s.vanished = true
    end
    local led = false                                   -- its gun at where you'll be, every tick of the frenzy
    if s.frenzyUntil and not s.vanished and you and (c.gun_lead_s or 0) > 0 and not s.leadFail then
        local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
        local okV, v = pcall(function() local q = pawn:GetVelocity(); return { X = q.X, Y = q.Y, Z = q.Z } end)
        if okV and v then
            local L = c.gun_lead_s
            local aim = { X = you.X + v.X * L, Y = you.Y + v.Y * L, Z = you.Z + v.Z * L }
            led = true
            for _ = 1, c.gun_lead_shots or 1 do         -- (WN_WEAPON_2 = ELiveWeaponNumber 1: its gun)
                local ok, err = pcall(function() o:FireOneShotWeaponWithLocationTracking(1, aim, true, false) end)
                if not ok then
                    s.leadFail, led = true, false
                    log("special: " .. c.name .. "'s led gun failed (the event's shots only): " .. tostring(err))
                    break
                end
            end
            if led and not s.leadSaid then
                s.leadSaid = true
                log(string.format("special: %s's frenzy gun leads you %.1f s (%.0f m ahead), %d shots a tick%s", c.name, L,
                    math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) * L / 100, c.gun_lead_shots or 1,
                    c.gun_lead_event and ", the event's too" or ""))
            end
        end
    end
    if s.frenzyUntil and not s.vanished and (not led or c.gun_lead_event) and now >= (s.gunAt or 0) then
        s.gunAt = now + c.gun_every_s                   -- (the event: 5 shots 0.1 s apart, at you)
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_GlitchGun") or -5
        s.shots = (s.shots or 0) + 1
        if r ~= 1 and not s.gunSaid then s.gunSaid = true; log("special: RE_SV_GlitchGun not fired: " .. (SV_ERR[r] or tostring(r))) end
    end
end

-- VALKA (CFG.specials.valka; tools/survival_events.py VALKA_*): AC7 Mission 18's opener (hidden and kept opener_m
-- ahead of the player, a flash, the charge, one railgun shot), her reveal on the far ring with the focus camera, then
-- the fight: LastTGT and post-stalls, blinks when she's hit, her railgun, and now and then the scrambled controls.
-- (Functions on SPC.V: the main chunk is at its 200-local limit, hard rule 23.)
SPC.V = {}
-- her teleport event on ring `ring` nearest bearing `deg` (RE_SV_ValkaTp_<ring><two letters>), the point it puts her
-- at round `you` (cm, at your height) and that step's bearing
function SPC.V.spot(c, ring, deg, you)
    for _, sp in ipairs(c.spots) do
        if sp[1] == ring then
            local n = math.floor(360 / sp[3])
            local k = math.floor((deg % 360) / sp[3] + 0.5) % n
            local b, d = k * sp[3], sp[2] * 100
            return "RE_SV_ValkaTp_" .. ring .. string.char(65 + k // 26) .. string.char(65 + k % 26),
                you and { X = you.X + d * math.cos(math.rad(b)), Y = you.Y + d * math.sin(math.rad(b)), Z = you.Z }, b
        end
    end
end
-- the player's heading (degrees, world: 0 = +X), from their velocity (their nose when they're near still)
function SPC.V.heading()
    local pawn = valid(survivalPC) and survivalPC.Pawn
    if not pawn then return nil end
    local ok, h = pcall(function()
        local v = pawn:GetVelocity()
        if math.abs(v.X) + math.abs(v.Y) > 1000 then return math.deg(math.atan(v.Y, v.X)) end
        local f = pawn:GetActorForwardVector()
        return math.deg(math.atan(f.Y, f.X))
    end)
    return ok and h or nil
end
-- a blink spot (rings B / C): at least blink_turn_deg round from the last, never under ground_clear_m above the ground
-- (less when you fly lower), as AB.L..IN's. Returns its event, point and bearing, or nil.
function SPC.V.blinkSpot(c, s, you)
    local want = math.random() * 360
    if s.lastDeg then want = s.lastDeg + c.blink_turn_deg + math.random() * (360 - 2 * c.blink_turn_deg) end
    local under = groundAt(you.X, you.Y)
    local clear = c.ground_clear_m * 100
    if under then clear = math.max(0, math.min(clear, (you.Z - under) * 0.8)) end
    local rings = math.random() < 0.5 and { "B", "C" } or { "C", "B" }
    for _, off in ipairs({ 0, 30, -30, 60, -60, 90, -90 }) do
        for _, ring in ipairs(rings) do
            local ev, to, deg = SPC.V.spot(c, ring, want + off, you)
            local ground = to and groundAt(to.X, to.Y)
            if ev and (not ground or to.Z >= ground + clear) then return ev, to, deg end
        end
    end
end
-- her railgun parts fire one round a shot (user, 2026-10-24: "I only want single shot"; Mission 26's fire 3): the x40a
-- railguns' launcher modules (only hers are in Survival) get TriggerCount / MagazineCapacity single_shot. Returns how many.
function SPC.V.singleShot(c)
    local n, why = 0, nil
    local ok, list = pcall(FindAllOf, "LiveFCSModule_LauncherTripleRailCannon")
    for _, m in ipairs(ok and list or {}) do
        local okS, err = pcall(function()
            m.FireControl.TriggerCount = c.single_shot
            m.Performance.MagazineCapacity = c.single_shot
        end)
        if okS then n = n + 1 else why = why or tostring(err) end
    end
    return n, why
end
function SPC.V.event(ev)
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    if r ~= 1 then log("special: VALKA " .. ev .. " not fired: " .. (SV_ERR[r] or tostring(r))) end
    return r
end
-- the scrambled controls on (random_min..random_max of random_fx, as MINDRIPPER's field) or off
function SPC.V.invert(c, s, on, now)
    local t = CFG.hud.text
    local fx = on and pickFx(c) or {}
    if on then
        local names = {}
        for _, k in ipairs(FX_ORDER) do if fx[k] then names[#names + 1] = (t.anomaly_fx or {})[k] or k:upper() end end
        s.fxText, s.invertUntil = table.concat(names, " + "), now + c.invert_s
    else
        s.invertUntil = nil
    end
    local pawn = valid(survivalPC) and survivalPC.Pawn
    local function b(k) return fx[k] and 1 or 0 end
    local r = type(SV_Invert) == "function" and SV_Invert(b("pitch"), b("roll"), c.fade_s, pawn and addrOf(pawn) or 0,
        b("yaw"), b("swap"), b("throttle")) or "no runtime"
    hudCallout(on and t.anomaly_field or t.anomaly_clear, on and s.fxText or nil)
    log(string.format("special: %s scrambles your controls: %s (SV_Invert %s)", c.name, on and s.fxText or "back",
        tostring(r)))
end

-- VALKA on her ace row (the x40a and its railguns) at the top fire-control level, hidden until her opener; false if
-- she can't come.
function SPC.valkaSpawn(now)
    local c = CFG.specials.valka
    local row = ACE.row("valka", "x40a", "l")
    if not SR.usable[row] then
        log("special: VALKA's row wasn't in before this level loaded; a normal round instead")
        return false
    end
    local x, y, _, bearing = spawnPoint()
    local px, py, pb, pd = ANOM.nearPlayer(c.spawn_km)
    if px then x, y, bearing = px, py, pb end
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local set = SV_SetAircraft(c.unit, searchAircraft(row, #SPIKE_SUFFIX))
    if type(SV_SetLevel) == "function" then SV_SetLevel(c.unit, c.ai_level * 100) end
    spawningUnit = c.unit
    local r = SV_Spawn(c.unit, x, y, alt * 100, (bearing + 180) % 360)
    spawningUnit = nil
    local hidden = 0
    for _, q in ipairs(pending) do                     -- gone before a frame is drawn (as MINDRIPPER)
        if q.unit == c.unit and valid(q.obj) then setGone(q.obj, true); hidden = hidden + 1 end
    end
    log(string.format("special: VALKA as %s (%s set), %s at bearing %.0f, %.1f km up: %s (%d hidden)", row, tostring(set),
        pd and string.format("%.1f km from you", pd) or "at a spawn point", bearing or -1, alt / 1000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")"), hidden))
    if r <= 0 then return false end
    D.flightTier = D.flightTier or {}
    D.up[c.unit], D.flown[c.unit], D.flightTier[c.unit] = true, true, #CFG.tiers.list
    D.special.state, D.special.at = "arrive", now
    return true
end

-- Every tick of VALKA's round.
function SPC.valkaTick(now, s)
    local c, t, V = CFG.specials.valka, CFG.hud.text, SPC.V
    local o = glitchActor(c)
    local you = playerLocation()
    if s.state == "arrive" then                         -- hidden; her railguns made single-shot; then the opener
        if o then setGone(o, true) end
        if not o and now - s.at >= c.arrive_s + 3 then
            s.state = "hunt"
            log(string.format("special: %s's actor not found %.0f s after she spawned; no opener", c.name, now - s.at))
            return
        end
        if now - s.at < c.arrive_s or not o or not you then return end
        local n, why = V.singleShot(c)
        log(string.format("special: %s's railguns single-shot: %d launcher modules%s", c.name, n, why and (" (" .. why .. ")") or ""))
        s.state, s.chargeAt, s.openAt = "opener", now + c.charge_s, now
        V.event("RE_SV_ValkaChargeOn")
        hudCallout(t.valka_charge, t.valka_charge_sub)
        local pawn = valid(survivalPC) and survivalPC.Pawn
        local fx = pawn and portalFx({ c.flash }, pawn, { X = c.opener_m * 100, Y = 0, Z = 50 }, c.flash_scale, c.flash_s) or 0
        log(string.format("special: %s's opener: railgun charging %.0f m ahead of you for %.1f s (flash: %d)", c.name,
            c.opener_m, c.charge_s, fx))
    end
    if s.state == "opener" then                         -- kept ahead of you, nose on you, then the shot
        if not o then return end
        setGone(o, true)
        local h = V.heading()
        if h and you then V.event((V.spot(c, "A", h, you))) end
        if now >= s.chargeAt then
            if (s.singleN or 0) == 0 then s.singleN = V.singleShot(c) end     -- (in case the parts came late)
            V.event("RE_SV_ValkaRailgun")
            V.event("RE_SV_ValkaChargeOff")
            s.chargeAt, s.shots, s.state, s.revealAt = nil, 1, "fired", now + c.reveal_s
            local pawn = valid(survivalPC) and survivalPC.Pawn
            if pawn then portalFx({ c.flash }, pawn, { X = c.opener_m * 100, Y = 0, Z = 50 }, c.flash_scale, c.flash_s) end
            log(string.format("special: %s's opener shot (from %.0f m ahead of you)", c.name, c.opener_m))
        end
        return
    end
    if s.state == "fired" then                          -- the far spot, shown, the camera on her
        if not o or now < s.revealAt then return end
        local h = V.heading() or 0
        local ev = you and V.spot(c, "D", h, you)
        if ev then V.event(ev) end
        local hx = math.min(c.health_max_x or 1, 1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first))
        local hp = c.health * hx
        local okH = pcall(function() o.MaxHealth = hp; o.HealthInternal = hp * 10 end)
        setGone(o, false)
        local cam = 1
        for k, n in ipairs(ANOMALY_CAMERAS) do if n == c.camera then cam = k end end
        V.event("RE_SV_ValkaCam_" .. string.char(64 + cam))
        V.event("RE_SV_ValkaReveal")
        s.state, s.revealedAt = "hunt", now
        s.railAt, s.turnAt, s.psAt, s.invertAt = now + c.railgun_every_s, now + c.turn_every_s, now + c.post_stall_every_s,
            now + c.invert_every_s
        hudCallout(c.name, c.squadron)
        log(string.format("special: %s shows %.0f m out (%s), %.0f HP (x%.2f)%s; camera %s", c.name,
            c.spots[4][2], tostring(ev), hp, hx, okH and "" or " (health NOT set)", ANOMALY_CAMERAS[cam]))
        return
    end
    if s.state ~= "hunt" then return end
    s.railAt, s.turnAt = s.railAt or now + c.railgun_every_s, s.turnAt or now + c.turn_every_s   -- (no opener: no reveal)
    s.psAt, s.invertAt = s.psAt or now + c.post_stall_every_s, s.invertAt or now + c.invert_every_s
    if SV_UnitAlive(c.unit) <= 0 then
        s.state = "done"
        if s.invertUntil then V.invert(c, s, false, now) end
        if s.chargeAt then V.event("RE_SV_ValkaChargeOff") end
        ANOM.cleanFx(now, true)
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, c.name .. " down")
        LB.special("valka", true, now - s.at)
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, pay))
        log(string.format("special: round %d, %s shot down %.0f s after she showed (%d railgun shots, %d blinks, %d turns, %d scrambles)",
            D.round, c.name, now - (s.revealedAt or s.at), s.shots or 0, s.blinks or 0, s.turns or 0, s.scrambles or 0))
        return
    end
    if not o then return end
    local at = where(o)
    if at and you then s.dist = math.sqrt((at.X - you.X) ^ 2 + (at.Y - you.Y) ^ 2 + (at.Z - you.Z) ^ 2) / 100000 end
    -- the angle between her nose and you (for LastTGT when you're behind her, and her railgun's cone)
    local offNose = nil
    if at and you then
        local okF, f = pcall(function() local q = o:GetActorForwardVector(); return { X = q.X, Y = q.Y, Z = q.Z } end)
        local tx, ty, tz = you.X - at.X, you.Y - at.Y, you.Z - at.Z
        local n = math.sqrt(tx * tx + ty * ty + tz * tz)
        if okF and n > 0 then offNose = math.deg(math.acos(math.max(-1, math.min(1, (f.X * tx + f.Y * ty + f.Z * tz) / n)))) end
    end
    -- the scrambled controls: a chance every invert_every_s, for invert_s
    if s.invertUntil and now >= s.invertUntil then V.invert(c, s, false, now) end
    if not s.invertUntil and now >= s.invertAt then
        s.invertAt = now + c.invert_every_s
        if math.random() < c.invert_chance then s.scrambles = (s.scrambles or 0) + 1; V.invert(c, s, true, now) end
    end
    -- blinks: a hit outside a spell (and its cooldown) starts blink_s of them
    local okH, hpNow = pcall(function() return o.HealthInternal end)
    hpNow = okH and type(hpNow) == "number" and hpNow or nil
    if hpNow and s.lastHp and hpNow < s.lastHp - 0.5 and not s.blinkUntil and now >= (s.blinkCool or 0) then
        s.blinkUntil, s.nextBlink = now + c.blink_s, now
        log(string.format("special: %s hit (%.0f -> %.0f): blinking for %.0f s", c.name, s.lastHp, hpNow, c.blink_s))
    end
    s.lastHp = hpNow or s.lastHp
    if s.vanished then                                  -- back, round you, nose on you
        local ev, to, deg
        if you then ev, to, deg = V.blinkSpot(c, s, you) end
        if ev then
            s.lastDeg, s.blinks = deg, (s.blinks or 0) + 1
            V.event(ev)
            if to and fxAt({ c.smoke }, to, c.smoke_scale, c.smoke_s) == 0 and not s.smokeSaid then
                s.smokeSaid = true; log("special: VALKA's smoke " .. c.smoke .. " didn't spawn")
            end
        end
        setGone(o, false)
        s.vanished, s.nextBlink = false, now + c.blink_every_s
    elseif s.blinkUntil and now >= s.blinkUntil then
        s.blinkUntil, s.blinkCool = nil, now + c.blink_cooldown_s
    elseif s.blinkUntil and now >= s.nextBlink and not s.chargeAt then   -- gone in a puff (back next tick)
        if at then fxAt({ c.smoke }, at, c.smoke_scale, c.smoke_s) end
        setGone(o, true)
        s.vanished = true
        return
    end
    -- her railgun: warning and charge, then one shot (when you're in front of her, near enough)
    if s.chargeAt and now >= s.chargeAt then
        V.event("RE_SV_ValkaRailgun")
        V.event("RE_SV_ValkaChargeOff")
        s.chargeAt, s.shots, s.railAt = nil, (s.shots or 0) + 1, now + c.railgun_every_s
        log(string.format("special: %s railgun shot %d, %.1f km from you, %.0f deg off her nose", c.name, s.shots,
            s.dist or -1, offNose or -1))
    elseif not s.chargeAt and now >= s.railAt and s.dist and s.dist <= c.railgun_range_km and offNose
        and offNose <= c.railgun_cone_deg then
        s.chargeAt = now + c.railgun_charge_s
        V.event("RE_SV_ValkaChargeOn")
        hudCallout(t.valka_charge, t.valka_charge_sub)
    end
    -- LastTGT: every turn_every_s, and at once (behind_gap_s apart) when you're behind her within behind_km
    local behind = offNose and offNose > 110 and s.dist and s.dist <= c.behind_km
    if (now >= s.turnAt) or (behind and now >= (s.behindAt or 0)) then
        s.turnAt, s.behindAt, s.turns = now + c.turn_every_s, now + c.behind_gap_s, (s.turns or 0) + 1
        s.psAt = math.max(s.psAt, now + 3)                -- (not straight into a post-stall)
        V.event("RE_SV_ValkaTurn")
        if s.turns <= 5 or s.turns % 10 == 0 then
            log(string.format("special: %s LastTGT %d%s, %.1f km from you", c.name, s.turns, behind and " (you behind her)" or "",
                s.dist or -1))
        end
    elseif c.post_stall and now >= s.psAt and s.dist and s.dist <= c.post_stall_range_km then
        s.psAt = now + c.post_stall_every_s
        if not s.psOn then
            s.psOn = true
            pcall(function() o.bCanManeuverPugachevsCobra = true; o.bCanManeuverKulbit = true end)
        end
        local moves = c.post_stall_moves or {}
        if #moves > 0 then V.event("RE_SV_Valka" .. moves[math.random(#moves)]) end
    end
end

-- The special rounds by kind (CFG.specials.rotation; code review of 2026-10-23: each new one meant a branch in eight
-- places): `sub` its callout's second line (a CFG.hud.text key, or a function of the texts), `alone` whether its round
-- has no fighters of its own (a value or a function), `aircraft` how many of the round's aircraft it counts for,
-- `spawn(now)` its arrival from the spawn queue ("@<kind>"; false: it can't come, a normal round instead) and
-- `tick(now, s)` its every tick (the shuttle's countdown is specialTick's own).
SPC.kinds = {
    shuttle    = { sub = function(t) return string.format(t.shuttle_sub, CFG.specials.shuttle.name:upper()) end,
                   spawn = function() spawnShuttle(); return true end },
    anomaly    = { sub = "anomaly_sub", alone = function() return CFG.specials.anomaly.only end,
                   aircraft = function() return 1 + CFG.specials.anomaly.guards end,
                   spawn = function(now)
                       if not ANOM.spawn() then return false end
                       D.special.state, D.special.at = CFG.specials.anomaly.portal.enabled and "portal" or "hunt", now
                       return true
                   end,
                   tick = function(now, s) return ANOM.tick(now, s) end },
    amphibious = { sub = "amphib_sub", spawn = function(now) return AMPH.spawn(now) end,
                   tick = function(now, s) return AMPH.tick(now, s) end },
    ladon      = { sub = "ladon_sub", alone = true, aircraft = 2, spawn = function(now) return SPC.ladonSpawn(now) end,
                   tick = function(now, s) return SPC.ladonTick(now, s) end },
    alicorn    = { sub = "alicorn_sub", alone = true, aircraft = 1, spawn = function(now) return SPC.alicornSpawn(now) end,
                   tick = function(now, s) return SPC.alicornTick(now, s) end },
    glitch     = { sub = "glitch_sub", alone = true, aircraft = 1, spawn = function(now) return ANOM.glitchSpawn(now) end,
                   tick = function(now, s) return ANOM.glitchTick(now, s) end },
    valka      = { sub = "valka_sub", alone = true, aircraft = 1, spawn = function(now) return SPC.valkaSpawn(now) end,
                   tick = function(now, s) return SPC.valkaTick(now, s) end },
}
-- a kind's field that may be a function (alone, aircraft, sub)
function SPC.kindValue(v, ...) if type(v) == "function" then return v(...) end return v end

-- Every tick of a running Anomaly: its distance (the field) and its end.
function ANOM.tick(now, s)
    local c, t = CFG.specials.anomaly, CFG.hud.text
    if s.state == "portal" then return portalTick(now, s, c) end
    if s.state ~= "hunt" then return end
    if SV_UnitAlive(c.unit) <= 0 then
        s.state = "done"
        setField(false, s)
        if type(SV_Event) == "function" then SV_Event("RE_SV_AnomalyEnd") end
        local live = #ANOM.fx
        ANOM.cleanFx(now, true)                                               -- every system on it off now
        log(string.format("special: %s down: its %d lightning systems switched off", c.name, live))
        local nb = fxAt(c.portal.burst, s.lastAt, c.portal.scale)             -- the lightning again where it fell
        log(string.format("special: %s's last burst (%d systems)", c.name, nb))
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, c.name .. " down")
        LB.special("anomaly", true, now - s.at)
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, pay))
        log(string.format("special: round %d, %s shot down %.0f s after it appeared", D.round, c.name, now - s.at))
        return
    end
    local p
    for _, q in ipairs(planes) do if q.unit == c.unit and valid(q.obj) then p = q end end
    local you = playerLocation()
    if not (p and you) then return end
    local ok, l = pcall(function() local v = p.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not ok then return end
    s.dist, s.lastAt = km(l, you), l
    if c.portal.enabled and now >= (s.nextAura or 0) then                  -- it crackles while it's up
        s.nextAura = now + c.portal.aura_every_s
        portalFx({ c.portal.aura }, p.obj, nil, c.portal.aura_scale)
        if math.random() < 0.35 then strike(p.obj) end
    end
    local pawn = valid(survivalPC) and survivalPC.Pawn
    local a = pawn and addrOf(pawn)
    if a and a ~= ANOM.pawn then ANOM.pawn = a; if ANOM.on then ANOM.on = nil end end   -- a new plane: switch again
    if ANOM.on ~= true and s.dist < c.field_km then setField(true, s)
    elseif ANOM.on ~= false and s.dist > c.field_km + 0.3 then setField(false, s) end      -- (0.3 km: no flicker)
end
end

-- The shuttle's countdown clock (D.shuttleClock: cd seconds run, fired the last second's event): it runs on the game
-- clock except while you're down at the airfield (D.grounded, from roundsTick), and fires RE_SV_ShuttleT_<s> for each
-- whole second s (tools/survival_events.py build_shuttle: radio, ignition, liftoff at countdown_s, the climb after it)
-- up to countdown_s + 30; it stops when the shuttle is lost. While the countdown is held the shuttle can't be hurt
-- (user, 2026-10-23: "Make the shuttle invulnerable while the countdown is held"; LiveGameObject.SetIsInvincible).
function SPC.shuttleInvincible(on)
    if not valid(SHUTTLE.obj) then shuttleHealth() end           -- (finds the shuttle's actor)
    if not valid(SHUTTLE.obj) then return false end
    local ok = pcall(function() SHUTTLE.obj:SetIsInvincible(on) end)
    log(string.format("special: shuttle %s%s", on and "invulnerable while the countdown is held" or "can be hit again",
        ok and "" or " (SetIsInvincible failed)"))
    return ok
end

function SPC.shuttleClockTick(now)
    local k = D.shuttleClock
    if not k then return end
    local dt = math.max(0, now - k.at)
    k.at = now
    if not D.grounded then k.cd = k.cd + dt end
    if D.grounded ~= k.grounded then
        k.grounded = D.grounded
        log(string.format("special: shuttle countdown %s at %.0f s", D.grounded and "held (you're down at the airfield)" or "running", k.cd))
    end
    local want = (D.grounded and not k.s.lost and k.s.state == "countdown") or false   -- (not after liftoff)
    if want ~= (k.inv or false) and SPC.shuttleInvincible(want) then k.inv = want end
    local last = CFG.specials.shuttle.countdown_s + 30
    while k.fired < math.min(math.floor(k.cd), last) do
        k.fired = k.fired + 1
        if type(SV_Event) == "function" then SV_Event("RE_SV_ShuttleT_" .. k.fired) end
    end
    if k.fired >= last or k.s.lost then
        if k.inv then SPC.shuttleInvincible(false) end
        D.shuttleClock = nil
    end
end

-- Watches a running special: launched (its flag, or the countdown run out with the shuttle still there) or lost (its
-- flag, or nothing of its unit alive before liftoff). Pays the reward or closes the shop.
local function specialTick(now)
    SPC.shuttleClockTick(now)
    if D.shuttleRemoveAt and now >= D.shuttleRemoveAt then            -- (tools/survival_events.py RE_SV_ShuttleRemove)
        D.shuttleRemoveAt = nil
        if D.shuttleClock and D.shuttleClock.inv then SPC.shuttleInvincible(false); D.shuttleClock.inv = false end
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_ShuttleRemove") or "n/a"
        log("special: shuttle and pad taken off (RE_SV_ShuttleRemove " .. tostring(r) .. ")")
    end
    local s = D.special
    if #ANOM.fx > 0 then ANOM.cleanFx(now) end                     -- (the Anomaly's systems, even after its round)
    AMPH.runTick(now)                                               -- landed troops, the capture (any round)
    if D.alicornRemoveAt and now >= D.alicornRemoveAt then
        D.alicornRemoveAt = nil
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_AlcnRemove") or "n/a"
        log("special: the Alicorn taken off (RE_SV_AlcnRemove " .. tostring(r) .. ")")
    end
    local sk = s and SPC.kinds[s.kind]
    if sk and sk.tick then return sk.tick(now, s) end
    if not s or s.state ~= "countdown" then return end
    local c, t = CFG.specials.shuttle, CFG.hud.text
    local f = svFlags() or {}
    local alive = SV_UnitAlive(c.unit)
    local cd = D.shuttleClock and D.shuttleClock.cd or (now - s.at)
    local over = cd >= c.countdown_s + 3
    local launched = (f.SV_ShuttleLaunched or 0) >= 1
    if now >= (s.logAt or 0) then                   -- every 10 s: is anything getting at it (report of 2026-10-23)
        s.logAt = now + 10
        local hp, near, at = shuttleHealth(), nil, nil       -- (finds the shuttle's actor first)
        pcall(function() local v = SHUTTLE.obj:K2_GetActorLocation(); at = { X = v.X, Y = v.Y, Z = v.Z } end)
        for _, q in ipairs(planes) do
            if D.strikeUnits and D.strikeUnits[q.unit] and valid(q.obj) and at then
                pcall(function()
                    local v = q.obj:K2_GetActorLocation()
                    local d = km({ X = v.X, Y = v.Y, Z = v.Z }, at)
                    if not near or d < near then near = d end
                end)
            end
        end
        log(string.format("special: shuttle %.0f s in: health %s%%, %d hits, nearest strike aircraft %s, %d alive in its unit",
            cd, tostring(hp), f.SV_ShuttleHits or -1, near and string.format("%.1f km", near) or "none",
            alive))
    end
    if (f.SV_ShuttleLost or 0) >= 1 or (alive <= 0 and not launched and not over) or (over and not launched and alive <= 0) then
        s.state, s.lost = "done", true
        D.shuttleRemoveAt = now + 30                    -- the pad's allies (the shuttle is gone)
        RUN.shopClosedUntil = D.round + c.shop_closed_rounds
        RUN.dirty = true
        LB.special("shuttle", false, cd)
        hudCallout(t.shuttle_lost, t.shuttle_lost_sub)
        log(string.format("special: round %d, the shuttle was lost %.0f s into the countdown (%d hits); shop closed through round %d",
            D.round, cd, f.SV_ShuttleHits or -1, RUN.shopClosedUntil))
    elseif launched or over then
        s.state = "done"
        D.shuttleRemoveAt = now + c.remove_s            -- it and the pad's allies, once it's well up
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, "shuttle launched")
        LB.special("shuttle", true, cd)
        hudCallout(t.launched, string.format(t.launched_sub, pay))
        log(string.format("special: round %d, the shuttle lifted off (%s; %d hits, health %s%%)", D.round,
            launched and "event package" or "countdown over", f.SV_ShuttleHits or -1,
            tostring(shuttleHealth())))
    end
end

local function startRound()
    D.round = D.round + 1
    local sk = spikeCfg(spikeLevel(D.round))
    local budget = math.min(CFG.aircraft_round1 + (D.round - 1) * CFG.aircraft_per_round + (sk.aircraft_add or 0),
        CFG.max_aircraft)
    local b = CFG.airfield.bombers
    local special = D.forceSpecial or specialFor(D.round)          -- (Ctrl+1 .. Ctrl+5: a special next, for testing)
    D.forceSpecial = nil
    if special == "amphibious" and not AMPH.ready() then          -- no lane can come: a normal round
        log(string.format("round %d: no landing craft can come; a normal round", D.round))
        special = nil
    end
    D.special = special and { kind = special, state = "pending" } or nil
    RUN.specialPick = RUN.specialPick or {}                      -- (as it is: a forced one too; specialFor reads it)
    RUN.specialPick[D.round] = special or false
    if special then
        RUN.lastSpecial = special
        RUN.specialAt = RUN.specialAt or {}
        RUN.specialAt[special] = D.round                    -- (its cooldown: specialFor)
    end
    if special == "amphibious" then                  -- a harder round: more escort (user: "make it difficult")
        budget = math.min(budget + (CFG.specials.amphibious.extra_aircraft or 0), CFG.max_aircraft)
    end
    -- (user, 2026-10-22: "when an ACE team spawns, no other aircraft other than those special to those levels should
    -- spawn"): an ace round (CFG.aces every) is its tier's squadrons throughout, with no bomber raid
    D.roundTier = nil
    local aceTi = (D.nextTierRound == D.round and D.nextTier) or aceRound(D.round, special)   -- (the one its callout named)
    if aceTi then
        local ti = aceTi
        local tn = CFG.tiers.list[ti].name
        if ACE.roster[tn:lower()] then
            D.roundTier = ti
            local c = CFG.aces[tn:lower()] or {}
            if D.aceRoundSaid ~= D.round then
                D.aceRoundSaid = D.round
                log(string.format("aces: round %d is a %s round (%s squadron only)", D.round, tn, tostring(c.squadron)))
            end
        end
    end
    D.nextTier, D.nextTierRound = nil, nil
    D.budget = budget
    local spk = special and SPC.kinds[special]
    local alone = spk and SPC.kindValue(spk.alone)                  -- (a special that flies alone: no fighters)
    local raid = not special and not D.roundTier and CFG.airfield.enabled and D.round >= b.first_raid
        and (D.round - b.first_raid) % math.max(1, math.floor(b.raid_every)) == 0
    local bombers, nBombers = {}, 0
    if raid then
        local share = math.floor(budget * b.raid_share / 2 + 0.5) * 2
        bombers, nBombers = pickFlights(b.pool, share, function(u) return D.round < b.heavy_from_round and HEAVY_UNIT[u] end)
    elseif spk and spk.aircraft then                -- its own aircraft take that many of the round's
        nBombers = SPC.kindValue(spk.aircraft)
    elseif special == "amphibious" and CFG.airfield.enabled and math.random() < CFG.specials.amphibious.bomber_chance then
        raid = true                                   -- a raid on the airfield with the landing (its share of the budget)
        local share = math.floor(budget * b.raid_share / 2 + 0.5) * 2
        bombers, nBombers = pickFlights(b.pool, share, function(u) return D.round < b.heavy_from_round and HEAVY_UNIT[u] end)
    elseif special == "shuttle" then             -- strike flights at the shuttle (heavies only bomb the airfield)
        local share = math.floor(budget * CFG.specials.shuttle.strike_share / 2 + 0.5) * 2
        bombers, nBombers = pickFlights(b.pool, share, function(u) return HEAVY_UNIT[u] end)
    end
    D.strikeUnits = {}                              -- (for the shuttle's countdown log)
    if special == "shuttle" then for _, u in ipairs(bombers) do D.strikeUnits[u] = true end end
    -- allied ships at sea (CFG.allies): a normal round's strike flights at them, each at one ship (ace rounds are their
    -- squadron only)
    D.shipStrike = {}
    local ships = (not raid and not special and not D.roundTier and CFG.allies.enabled and ALLY.shipsAtSea)
        and ALLY.shipsAtSea() or {}
    if #ships > 0 then
        local share = math.floor(budget * CFG.allies.strike_share / 2 + 0.5) * 2
        local sb, sn = pickFlights(b.pool, share, function(u) return HEAVY_UNIT[u] end)
        for _, u in ipairs(sb) do bombers[#bombers + 1] = u; D.shipStrike[u] = ships[math.random(#ships)] end
        nBombers = nBombers + sn
        if #sb > 0 then log(string.format("round %d: %d strike aircraft in %d squadrons go for the allied ships", D.round, sn, #sb)) end
    end
    local fighters, nFighters = pickFlights(CFG.pool, alone and 0 or (budget - nBombers), function(u) return PROBE_OF[u] end)
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
    if spk then table.insert(D.queue, 1, "@" .. special) end   -- the special first (the shuttle sets its strikers' orders)
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
    -- every tick, whatever the round's state (code review of 2026-10-23: in the break it never ran, so the shuttle's
    -- removal and the Anomaly's lightning clean-up waited for the next round, and while fighting it ran once a second,
    -- which rounded the portal's timing)
    if D.shuttleClock then D.grounded = playerOnAirfield() end   -- (the shuttle's countdown stops while you're down)
    specialTick(now)
    if D.state == "wait" then
        if not D.announced and now >= D.at - CFG.hud.start_callout_lead_s then
            D.announced = true
            local t = CFG.hud.text
            local nextSpecial = D.forceSpecial or specialFor(D.round + 1)
            local nextAce = aceRound(D.round + 1, nextSpecial)          -- (once: it picks the tier)
            local nk = nextSpecial and SPC.kinds[nextSpecial]
            if nk then
                hudCallout(string.format(t.special, D.round + 1), type(nk.sub) == "function" and nk.sub(t) or t[nk.sub])
            elseif nextAce then
                D.nextTier, D.nextTierRound = nextAce, D.round + 1   -- startRound flies this one
                local tn = CFG.tiers.list[D.nextTier].name:lower()
                local c = CFG.aces[tn] or {}
                hudCallout(string.format(t.start, D.round + 1), string.format(t.aces_round, tostring(c.squadron or tn):upper()))
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
        if now < D.at then return end
        if playerOnAirfield() then                 -- the landing menu may be up, and a flight that appears then gets no orders
            if D.held ~= D.round then D.held = D.round; log(string.format("round %d: spawns held while you are down at the airfield", D.round)) end
            D.at = now + 1
            return
        end
        if D.held == D.round then D.held = nil; log(string.format("round %d: you took off, spawns go on", D.round)) end
        local u = table.remove(D.queue, 1)
        local sk = type(u) == "string" and u:sub(1, 1) == "@" and SPC.kinds[u:sub(2)]
        if sk then
            if not sk.spawn(now) then                -- it can't come: a normal round (its fighters, if it flies alone)
                local alone = SPC.kindValue(sk.alone)
                D.special, RUN.specialPick[D.round] = nil, false
                local f = alone and pickFlights(CFG.pool, D.budget or CFG.aircraft_round1, function(q) return PROBE_OF[q] end) or {}
                for _, q in ipairs(f) do D.queue[#D.queue + 1] = q end
                log(string.format("round %d: no %s; %d fighter flights instead", D.round, u:sub(2), #f))
            end
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
        local alive, flights = 0, 0
        for u in pairs(D.up) do
            local n = SV_UnitAlive(u)
            if n > 0 then alive, flights = alive + n, flights + 1 else D.up[u] = nil end
        end
        if alive ~= D.lastAlive then log(string.format("round %d: %d aircraft in %d flights left", D.round, alive, flights)); D.lastAlive = alive end
        if flights == 0 and D.special and (D.special.state == "countdown" or D.special.state == "portal") then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: enemies down, the %s goes on", D.round,
                D.special.state == "portal" and "Anomaly's portal" or "shuttle's countdown")) end
        elseif flights == 0 and D.special and D.special.kind == "alicorn" and D.special.state == "sail" then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: the Alicorn is still afloat", D.round)) end
        elseif flights == 0 and D.special and D.special.kind == "ladon" and SPC.ladonBusy(D.special) then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: the Ladons are still up", D.round)) end
        elseif flights == 0 and D.special and D.special.kind == "amphibious" and AMPH.busy(D.special) then
            if not D.special.waitSaid then D.special.waitSaid = true; log(string.format("round %d: enemies down, the landing goes on", D.round)) end
        elseif flights == 0 then
            if D.special and D.special.kind == "amphibious" then AMPH.roundOver(now, D.special) end
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
    -- a hit count below the last one is a mission restart (the flags start over; the restart check resets the run a
    -- tick later): no damage from it (log of 2026-10-22: "health 116" and an AIRFIELD UNDER ATTACK callout on a retry)
    if hits < AF.hits then return end
    local hp = math.max(0, math.min(CFG.airfield.hp, AF.full - (hits - AF.base) * ac.hit_damage - (AF.bomb - AF.bombBase)))
    if hits ~= AF.hits or hp ~= AF.hp then
        AF.hits = hits
        if hp ~= AF.hp then
            AF.hp, RUN.dirty = hp, true
            log(string.format("airfield: hit (%d hits, %d bomb damage), health %d", hits, AF.bomb, hp))
            if hp <= 0 and not AF.down then
                AF.down, AF.downRound, AF.closePending = true, D.round, true
                hudCallout(t.airfield_down, string.format(t.airfield_down_sub, D.round + 1))   -- airfieldTick reopens it then
                log("airfield: down")
                LB.stat("af_down", 1)
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
        if reopen and RUN.captured then                -- captured: it opens when it's retaken (AMPH)
            reopen = false; RUN.captured.closed = true
        end
        log("airfield: repaired to " .. ac.repair_hp .. (reopen and (", landing open" .. airfieldEvent("RE_SV_AirfieldOpen")) or ""))
    end
end

---------------------------------------------------------------------------------------------------- ladon
-- CFG.specials.ladon; tools/survival_events.py LADON* builds the units (Mission 16's Ladon, parts and all), routes and
-- records. Ladon <Key> is unit SV_Unit_Ladon<Key> on DT_NPC row SV_Ladon_<Key>; each pass over the airfield adds one to
-- SV_LadonRun<Key>.
do
local KEYS = { "Kot", "Mishka" }

-- At the main menu, before the level loads (the spawner caches the rows then): each Ladon's DT_NPC row, from
-- DT_SV_NpcRows, with its name, health and speed.
function SPC.ladonSetup()
    if SPC.ladonDone or not gameInstance() then return end
    local c = CFG.specials.ladon
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(c.npc_rows)
    SPC.ladonTries = (SPC.ladonTries or 0) + 1
    if not (npc and mine) then
        if SPC.ladonTries >= 20 then SPC.ladonDone = true; log("special: the Ladons' tables didn't load; no Ladon round") end
        return
    end
    SPC.ladonDone = true
    local n = 0
    for _, k in ipairs(KEYS) do
        local row = "SV_Ladon_" .. k
        local _, have = dtCall(npc, "FindRow", row)
        if have == nil then
            local _, r = dtCall(mine, "FindRow", row)
            if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
        end
        if have ~= nil then
            n = n + 1
            local ok, err = pcall(function()
                have.MaxHealthDifference = c.health_add
                for _, f in ipairs({ "SpeedNormalCoefficient", "SpeedMaxCoefficient", "SpeedMinCoefficient", "SpeedTurnCoefficient" }) do
                    local v = have[f]
                    have[f] = ((type(v) == "number" and v > 0) and v or 1.0) * c.speed_x
                end
            end)
            if not ok then log("special: Ladon row " .. row .. ": health / speed NOT set: " .. tostring(err)) end
        end
        if type(SV_SetText) == "function" then SV_SetText(row, c.names[k] or k:upper()) end
    end
    SPC.ladonReady = n == #KEYS
    log(string.format("special: %d of %d Ladon rows in DT_NPC (%s; %+d HP, speeds x%.2f)", n, #KEYS,
        table.concat({ c.names.Kot, c.names.Mishka }, ", "), c.health_add, c.speed_x))
end

function SPC.ladonSpawn(now)
    local c, t = CFG.specials.ladon, CFG.hud.text
    if not (nativeReady() and SPC.ladonReady) then
        log("special: no Ladon round (" .. (SPC.ladonReady and "no native spawner" or "their rows aren't in") .. ")")
        return false
    end
    local s = D.special
    s.units, s.state, s.at, s.runs, s.planeFrom = {}, "run", now, 0, #planes + 1
    for _, k in ipairs(KEYS) do
        local unit = "SV_Unit_Ladon" .. k
        local r, was = SV_UnitAlive(unit), nil
        if r > 0 then was = true                     -- still up from before (a restart mid-round): this round's, then
        else spawningUnit = unit; r = SV_Spawn(unit); spawningUnit = nil end
        log(string.format("special: Ladon %s (%s): %s", c.names[k] or k, unit, r > 0 and (was and "still up, taken on" or "up") or
            ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
        if r > 0 then s.units[k] = { unit = unit, alive = true, runs = 0 } end
    end
    if not next(s.units) then return false end
    hudCallout(t.ladon_go, string.format(t.ladon_go_sub, c.names.Kot or "KOT", c.names.Mishka or "MISHKA"))
    log(string.format("special: round %d, the Ladons from the west", D.round))
    return true
end

function SPC.ladonsLeft(s)
    local n = 0
    for _, L in pairs(s.units or {}) do if L.alive then n = n + 1 end end
    return n
end

function SPC.ladonBusy(s) return s.state == "run" and SPC.ladonsLeft(s) > 0 end

-- Every second: a pass over the airfield (its bombs), a Ladon shot down (its pay).
function SPC.ladonTick(now, s)
    if s.state ~= "run" or now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    local c, t = CFG.specials.ladon, CFG.hud.text
    local f = svFlags() or {}
    -- its health for its round, once its aircraft is up (HealthInternal: health x 10, as the shuttle's)
    local hx = math.min(c.health_max_x or 2.5, 1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first))
    for i = s.planeFrom or 1, (s.scaledN or 0) < 2 and #planes or 0 do
        local p = planes[i]
        if hx > 1 and not p.down and not p.scaled and p.unit and p.unit:find("^SV_Unit_Ladon") and valid(p.obj) then
            local ok, h0 = pcall(function() return p.obj.HealthInternal end)
            if ok and type(h0) == "number" and h0 > 0 then        -- (not yet set on a fresh actor: next second)
                p.scaled, s.scaledN = true, (s.scaledN or 0) + 1
                local okW, err = pcall(function() p.obj.HealthInternal = math.floor(h0 * hx) end)
                log(string.format("special: %s health x%.2f for round %d (%s -> %s)%s", p.unit, hx, D.round, tostring(h0),
                    tostring(okW and p.obj.HealthInternal or "?"), okW and "" or (" (write failed: " .. tostring(err) .. ")")))
            end
        end
    end
    for k, L in pairs(s.units) do
        if L.alive and now >= (L.volleyAt or s.at + 10) then             -- a missile volley while you're in range
            local near
            for _, p in ipairs(planes) do
                if p.unit == L.unit and not p.down and valid(p.obj) and p.dist then near = math.min(near or p.dist, p.dist) end
            end
            if near and near <= c.volley_range_km then
                L.inRangeAt = L.inRangeAt or now                       -- (the first volley: once in range volley_warn_s)
                -- one Ladon's volley at a time, volley_gap_s apart (a friend's test of 2026-10-23: both came into range
                -- together and fired in the same second, and the player was down 20 s later): the other one waits
                local gap = c.volley_gap_s or c.volley_every_s / 2
                if now - L.inRangeAt >= (c.volley_warn_s or 0) and now - (s.volleyAny or -1e9) >= gap then
                    L.volleyAt, s.volleyAny, s.volleyWho = now + c.volley_every_s, now, c.names[k] or k
                    L.side = (L.side == "L") and "R" or "L"
                    local ev = "RE_SV_LadonVolley" .. k .. L.side
                    local r = type(SV_Event) == "function" and SV_Event(ev) or "n/a"
                    log(string.format("special: Ladon %s fires a launcher at you (%.1f km; %s %s)%s", c.names[k] or k, near, ev,
                        tostring(r), L.volleySaid and "" or string.format(", one every %d s in range, %d s after the other's",
                        c.volley_every_s, gap)))
                    L.volleySaid = true
                end
            else
                L.inRangeAt = nil
            end
        end
        if L.alive then
            local runs = f["SV_LadonRun" .. k] or 0
            -- (a count left from last time is reset by its appearance; a circuit takes minutes, so one pass in 30 s at
            -- most: a path that "finished" every frame once counted 30 a second and bombed every second, 2026-10-23)
            if now - s.at >= 5 and runs > L.runs and now - (L.bombAt or 0) >= 30 then
                L.runs, L.bombAt, s.runs = runs, now, (s.runs or 0) + 1
                local dmg = c.bomb_damage + (c.bomb_per_round or 0) * math.max(0, D.round - CFG.specials.first)
                if CFG.airfield.enabled and not AF.down then AF.bomb = AF.bomb + dmg end
                hudCallout(string.format(t.ladon_run, c.names[k] or k), t.ladon_run_sub)
                log(string.format("special: Ladon %s's pass over the airfield (%d): -%d", c.names[k] or k, runs, dmg))
            end
            local n, gone = SV_UnitAlive(L.unit), false
            if n >= 0 then L.errs = 0 else L.errs = (L.errs or 0) + 1 end
            if n == -7 or (L.errs or 0) >= 20 then           -- off the phase's list, or unreadable for 20 s
                local flying = false                          -- (code review of 2026-10-23: -7 paid, other errors held
                for _, p in ipairs(planes) do                 -- the round for good)
                    if p.unit == L.unit and not p.down and valid(p.obj) then flying = true end
                end
                if not flying then
                    L.alive, gone, s.escaped = false, true, true
                    log(string.format("special: Ladon %s gone without being shot down (SV_UnitAlive %d); no pay", c.names[k] or k, n))
                end
            end
            if n == 0 and not gone then
                L.alive = false
                local pay = c.reward + (c.reward_per_round or 0) * D.round
                addCredits(pay, "Ladon " .. (c.names[k] or k) .. " down")
                LB.stat("air", 1)
                hudCallout(string.format(t.ladon_down, c.names[k] or k), string.format(t.ladon_down_sub, pay))
                log(string.format("special: round %d, Ladon %s down %.0f s after it appeared", D.round, c.names[k] or k, now - s.at))
            end
        end
    end
    if SPC.ladonsLeft(s) == 0 then s.state = "done"; LB.special("ladon", not s.escaped, now - s.at) end
end
end

---------------------------------------------------------------------------------------------------- hits on the player
-- A friend's run ended 20 s after both Ladons' volleys and the log couldn't say what hit them (2026-10-23): the
-- player's health is read every tick and a drop is logged (at most once a second, the drops between added up) with the
-- enemy missiles near the player then (every LiveMissile but the player's, tracked from its creation; one that hit is
-- gone the tick after, so the last distance it was seen at counts) and the nearest enemy aircraft. No missile near:
-- a gun, the Ladons' pulse cannons, a SAM's blast or a collision. The Ladons' VLS missiles are toned down here as they
-- appear (CFG.specials.ladon.missile_*): from their class default, so a missile seen twice isn't cut twice.
local HIT = { new = {}, msl = {} }
pcall(NotifyOnNewObject, "/Script/Live.LiveMissile", function(o) if #HIT.new < 200 then HIT.new[#HIT.new + 1] = o end end)
do
local LADON_MSL = "BP_wp_vls_ladon"
local LADON_CDO = "/Game/Blueprints/Weapons/MSL/NPC/Vls/Ladon/BP_wp_vls_ladon.Default__BP_wp_vls_ladon_C"
local function short(o)                                    -- "BP_wp_vls_ladon" from "... .BP_wp_vls_ladon_C_2147..."
    local n = nameOf(o):match("([%w_]+)$") or "?"
    return (n:gsub("_C_%d+$", ""):gsub("_C$", ""))
end
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function owner(o)                                    -- who fired it (its owner, else its instigator), or nil
    for _, f in ipairs({ function() return o:GetOwner() end, function() return o.Instigator end }) do
        local ok, w = pcall(f)
        if ok and valid(w) then return short(w) end
    end
    return nil
end

local function nerf(o)
    local c = CFG.specials.ladon
    if not valid(HIT.cdo) then HIT.cdo = StaticFindObject(LADON_CDO) end
    local base = valid(HIT.cdo) and HIT.cdo or o
    local ok, err = pcall(function()
        local d0, a0 = base.damage, base.MaxHomingAngle
        o.damage = d0 * (c.missile_damage_x or 1)
        o.MaxHomingAngle = a0 * (c.missile_homing_x or 1)
        if not HIT.nerfSaid then
            HIT.nerfSaid = true
            log(string.format("hits: the Ladons' missile %s toned down: damage %.1f -> %.1f, homing cone %.0f -> %.0f deg (from %s)",
                LADON_MSL, d0, o.damage, a0, o.MaxHomingAngle, base == o and "the missile itself" or "its class default"))
        end
    end)
    if not ok and not HIT.nerfErr then HIT.nerfErr = true; log("hits: the Ladons' missile NOT toned down: " .. tostring(err)) end
end

-- what's near the player now: "missiles: ...; enemies: ..."
local function around(me, now)
    local ms = {}
    for _, m in ipairs(HIT.msl) do
        if m.d and m.d <= 800 and now - (m.seen or -1e9) <= 0.6 then ms[#ms + 1] = m end
    end
    table.sort(ms, function(a, b) return a.d < b.d end)
    local mt = {}
    for i = 1, math.min(3, #ms) do
        local m = ms[i]
        mt[#mt + 1] = string.format("%s %.0f m%s%s", m.name, m.d, m.from and (" from " .. m.from) or "",
            valid(m.obj) and "" or " (gone: it hit)")
    end
    local es = {}
    for _, p in ipairs(planes) do
        if not p.down and p.dist and p.dist <= 8 and valid(p.obj) then
            local v = at(p.obj)
            if v then es[#es + 1] = { name = p.unit or short(p.obj), d = km(v, me) } end
        end
    end
    table.sort(es, function(a, b) return a.d < b.d end)
    local et = {}
    for i = 1, math.min(3, #es) do et[#et + 1] = string.format("%s %.2f km", es[i].name, es[i].d) end
    return "missiles near: " .. (#mt > 0 and table.concat(mt, ", ") or "none (gun / pulse cannon / blast / collision?)") ..
        "; nearest enemies: " .. (#et > 0 and table.concat(et, ", ") or "none within 8 km")
end

function HIT.reset() HIT.new, HIT.msl, HIT.h, HIT.pawn, HIT.sum = {}, {}, nil, nil, nil end

-- every tick in a run (now: the round clock)
function HIT.tick(pc, now)
    local new = HIT.new
    HIT.new = {}
    for _, o in ipairs(new) do                             -- the new missiles: enemies' tracked, the Ladons' toned down
        if valid(o) then
            local n = short(o)
            if not n:find("^BP_plwp_") and not n:find("^Default__") then
                if n == LADON_MSL then nerf(o) end
                if #HIT.msl >= 60 then table.remove(HIT.msl, 1) end
                HIT.msl[#HIT.msl + 1] = { obj = o, name = n, born = now }
            end
        end
    end
    local pawn = pc and pc.Pawn
    if not valid(pawn) then return end
    local me = at(pawn)
    local keep = {}
    for _, m in ipairs(HIT.msl) do                         -- where each one is (kept 2 s after it's gone)
        if valid(m.obj) and now - m.born < 30 then
            m.from = m.from or owner(m.obj)
            local v = me and at(m.obj)
            if v then m.d, m.seen = km(v, me) * 1000, now end
            keep[#keep + 1] = m
        elseif now - (m.seen or m.born) < 2 then keep[#keep + 1] = m end
    end
    HIT.msl = keep
    local okA, addr = pcall(function() return tostring(pawn:GetAddress()) end)
    if not okA then addr = nameOf(pawn) end
    if addr ~= HIT.pawn then HIT.pawn, HIT.h, HIT.sum = addr, nil, nil end    -- (a new aircraft: a restart)
    local ok, h = pcall(function() return pawn.HealthInternal end)
    if not ok or type(h) ~= "number" then return end
    local last = HIT.h
    HIT.h = h
    if last and h < last then
        if not HIT.sum then HIT.sum, HIT.n, HIT.near = 0, 0, me and around(me, now) or "?" end   -- (as it was at the first)
        HIT.sum, HIT.n = HIT.sum + (last - h), HIT.n + 1
    end
    if HIT.sum and now - (HIT.logged or -1e9) >= 1 then
        local okM, maxHp = pcall(function() return pawn.MaxHealth end)
        local pct = (okM and type(maxHp) == "number" and maxHp > 0) and string.format("%d%%", math.floor(h / 10 / maxHp * 100 + 0.5)) or "?"
        local s = D and D.special
        local vol = (s and s.volleyAny and now - s.volleyAny < 60) and string.format("; Ladon %s's volley %.0f s ago", s.volleyWho or "?", now - s.volleyAny) or ""
        log(string.format("hit: -%.0f HP in %d hit%s, health now %s (%.0f HP)%s; %s%s", HIT.sum / 10, HIT.n, HIT.n == 1 and "" or "s",
            pct, h / 10, h <= 0 and ", SHOT DOWN" or "", HIT.near, vol))
        HIT.logged, HIT.sum = now, nil
    end
end
end

---------------------------------------------------------------------------------------------------- leaderboard
-- CFG.leaderboard; leaderboard/src/index.js is the other end (same score, same checks). RUN.stats: { started, air,
-- ground, aces (ace squadron aircraft down), allies (allies bought), af_down (times the airfield went down), captured
-- (times it was captured), specials = { { kind, round, seconds, won } } }. LB.show: the finished run on screen.
-- ONLINE ONLY BEGIN
-- LB.queue: the runs not yet answered for good (pending_runs.txt); LB.jobs: the sends in flight.
-- ONLINE ONLY END
do
local function stats()
    RUN.stats = RUN.stats or { started = os.time(), air = 0, ground = 0, aces = 0, allies = 0, af_down = 0, captured = 0,
                               specials = {} }
    return RUN.stats
end
function LB.stat(what, n) if D then local st = stats(); st[what] = (st[what] or 0) + (n or 1) end end
function LB.special(kind, won, seconds)
    if not D then return end
    local sp = stats().specials
    if #sp < 200 then sp[#sp + 1] = { kind = kind, round = D.round, seconds = math.min(3600, math.max(5, math.floor(seconds + 0.5))), won = won } end
end

-- leaderboard/src/index.js score(): 1000 a round, 100 an aircraft, 50 a ground target, 3000 a special beaten, x the difficulty
local DIFF_X = { casual = 0.75, standard = 1.0, ace = 1.5 }
local function score(r)
    local won = 0
    for _, sp in ipairs(r.specials) do if sp.won then won = won + 1 end end
    return math.floor((r.round * 1000 + r.kills.air * 100 + r.kills.ground * 50 + won * 3000) * (DIFF_X[r.difficulty] or 1)), won
end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
local function jstr(v) return '"' .. tostring(v):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
local function json(r)
    local sp = {}
    for _, x in ipairs(r.specials) do
        sp[#sp + 1] = string.format('{"kind":%s,"round":%d,"seconds":%d,"won":%s}', jstr(x.kind), x.round, x.seconds, tostring(x.won))
    end
    return string.format('{"v":1,"run_id":%s,"pilot":%s,"difficulty":%s,"round":%d,"mod":%s,"kills":{"air":%d,"ground":%d},'
        .. '"zollars":{"earned":%d,"spent":%d},"time_s":%d,"ended":%s,"how":%s,"aces":%d,"allies":%d,"af_down":%d,'
        .. '"captured":%d,"specials":[%s]%s%s}', jstr(r.run_id), jstr(r.pilot),
        jstr(r.difficulty), r.round, jstr(r.mod), r.kills.air, r.kills.ground, r.zollars.earned, r.zollars.spent, r.time_s,
        jstr(r.ended), jstr(r.how), r.aces, r.allies, r.af_down, r.captured, table.concat(sp, ","),
        (r.aircraft and r.aircraft:match("^[a-z0-9][a-z0-9]+$")) and (',"aircraft":' .. jstr(r.aircraft)) or "",
        (r.tier and r.tier:match("^%a+$")) and (',"tier":' .. jstr(r.tier)) or "")
end

local function configDir() return SCRIPT_DIR .. "..\\config\\" end
-- The file holds only the runs still waiting for an answer: once the last one is in (taken or refused), the file is
-- deleted, so no run stays on the player's PC after it's uploaded (user, 2026-10-24: "once its been uploaded, it self
-- deletes"). A run is written before it's sent so a game closed mid-send doesn't lose it.
local function saveQueue()
    while #LB.queue > 50 do table.remove(LB.queue, 1) end
    local path = configDir() .. "pending_runs.txt"
    if #LB.queue == 0 then os.remove(path); return end
    local f = io.open(path, "w")
    if not f then return end
    for _, body in ipairs(LB.queue) do f:write(body, "\n") end
    f:close()
end
-- ONLINE ONLY END
local function money(n) return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local function clockText(t) return string.format("%d:%02d:%02d", t // 3600, t // 60 % 60, t % 60) end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
-- The name the run goes under: [leaderboard] pilot, else the Steam name; only what the leaderboard takes, or "".
function LB.pilot()
    local name = tostring(CFG.leaderboard.pilot or "")
    if name:gsub("%s", "") == "" then
        if LB.steam == nil then
            LB.steam = type(SV_SteamName) == "function" and tostring(SV_SteamName() or "") or ""
            log("leaderboard: Steam name " .. (LB.steam ~= "" and ("'" .. LB.steam .. "'") or "not available"))
        end
        name = LB.steam
    end
    name = name:gsub("[^%w _%.%-]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 24)
    if name == "" then                                 -- (a Steam name of other letters only): one made for this install
        if not LB.anon then
            local f = io.open(configDir() .. "pilot_id.txt", "r")
            LB.anon = f and (f:read("l") or ""):match("^Pilot%-%x+$") or nil
            if f then f:close() end
            if not LB.anon then
                LB.anon = string.format("Pilot-%06x", math.random(0, 0xFFFFFF))
                local w = io.open(configDir() .. "pilot_id.txt", "w")
                if w then w:write(LB.anon, "\n"); w:close() end
            end
            log("leaderboard: no usable name; submitting as " .. LB.anon)
        end
        name = LB.anon
    end
    return name
end
-- ONLINE ONLY END
--OFFLINE: -- The name on the summary: [leaderboard] pilot.
--OFFLINE: function LB.pilot() return (tostring(CFG.leaderboard.pilot or ""):gsub("[^%w _%.%-]", ""):sub(1, 24)) end
-- Shot down: the player's aircraft at 0 health (checked once a second in a run)
function LB.deathCheck(pc)
    if not D or not D.round or D.round < 1 or (RUN.stats and RUN.stats.ended) then return end
    local st = stats()
    if not st.jet then                                -- the player's aircraft (user, 2026-10-23), read while it flies
        local code = nameOf(pc.Pawn):match("BP_PlayerPlane_PP%d+_(%w+)")
        if code then st.jet = code:lower():sub(1, 12); log("leaderboard: flying the " .. st.jet) end
    end
    local ok, h = pcall(function() return pc.Pawn.HealthInternal end)
    if not ok or type(h) ~= "number" then return end
    if h > 0 then st.flying, st.downs = true, 0                  -- (a pawn reads 0 while it's spawned: not a death)
    elseif st.flying then
        st.downs = (st.downs or 0) + 1
        if st.downs >= 2 then LB.finish("died") end
    end
end

-- The run's over (died / restart / left): its record, sent at once, and its summary on screen.
function LB.finish(how)
    if not D or not D.round or D.round < 1 then return end
    local st = stats()
    if st.ended then return end                         -- (shot down, then restarted: one record)
    st.ended = how
    local c = CFG.leaderboard
    local id = {}
    for _ = 1, 32 do id[#id + 1] = string.format("%x", math.random(0, 15)) end
    local r = { run_id = table.concat(id), pilot = LB.pilot(), difficulty = (presetName()),
                round = D.round, mod = VERSION, kills = { air = st.air, ground = st.ground },
                zollars = { earned = math.floor(RUN.earned or 0), spent = math.floor(RUN.spent or 0) },
                time_s = math.max(0, os.time() - st.started), ended = how == "died" and "died" or "quit", specials = st.specials,
                aircraft = st.jet, how = how, aces = st.aces or 0, allies = st.allies or 0, af_down = st.af_down or 0,
                captured = st.captured or 0,
                tier = CFG.tiers.enabled and (CFG.tiers.list[TIER.index(D.round)] or {}).name or nil }
    r.score, r.won = score(r)
    log(string.format("leaderboard: run over (%s): round %d, score %d, %d air / %d ground kills, %d specials beaten, %s",
        how, r.round, r.score, r.kills.air, r.kills.ground, r.won, clockText(r.time_s)))
    -- submitted straight away; the summary shows show_s once it's on screen (at: a run left from the menu has no HUD,
    -- so its summary waits for the next run's)
    LB.show = { run = r, at = nil, state = "sending" }
-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
    local ok, err = pcall(LB.send, LB.show)
    if not ok then                                      -- (0.50.0: a send that failed left "SENDING..." up for good)
        LB.show.state, LB.show.why = "refused", "error"
        log("leaderboard: the run couldn't be sent: " .. tostring(err))
    end
-- ONLINE ONLY END
--OFFLINE:     LB.show.state = "local"                           -- (the Offline edition: shown here only)
end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
-- A run goes into pending_runs.txt before it's sent and comes off once the server has answered for good (taken or
-- refused), so a run the game closes on, or one that can't get through, is sent later (LB.queueTick).
local function unqueue(body)
    for i, b in ipairs(LB.queue) do if b == body then table.remove(LB.queue, i); saveQueue(); return end end
end
local function post(body, sh)
    local id = type(SV_Post) == "function" and SV_Post(body) or -5
    if id > 0 then LB.jobs[#LB.jobs + 1] = { id = id, body = body, sh = sh } end
    return id
end

function LB.send(sh)
    local body = json(sh.run)
    LB.queue[#LB.queue + 1] = body; saveQueue()
    local id = post(body, sh)
    if id > 0 then
        sh.state = "sending"
        log("leaderboard: sending the run (job " .. id .. ")")
    else
        sh.state = "queued"
        log("leaderboard: not sent now (" .. tostring(id == -8 and "this build has no leaderboard address" or id) .. "); kept for later")
    end
end

local WHY = { [-12007] = "the server's name didn't resolve (DNS, or the address is blocked)",
              [-12029] = "couldn't connect (a firewall, or the address is blocked)",
              [-12002] = "timed out", [-12175] = "the secure connection failed (TLS)",
              [-12038] = "the certificate's name didn't match (a proxy in the way?)" }

-- Once a second, at the main menu and in runs: the sends' answers (reading a job's result frees its native slot).
function LB.poll()
    for i = #LB.jobs, 1, -1 do
        local j = LB.jobs[i]
        local st = SV_PostResult(j.id)
        if st ~= 0 then
            table.remove(LB.jobs, i)
            local reply = SV_PostReply(j.id) or ""
            local final = st > 0 and st < 500 and st ~= 429
            if final then unqueue(j.body) else LB.qwait = os.clock() + (st == 429 and 600 or 120) end
            local sh = j.sh
            if sh then
                if st == 200 then sh.state, sh.score = "sent", reply:match('"score":(%d+)')
                elseif not final then sh.state = "queued"
                else sh.state, sh.why = "refused", reply:match('"error":"([^"]+)"') or ("status " .. st) end
            end
            log(string.format("leaderboard: %s: the server answered %d%s: %s", sh and "the run" or "a waiting run", st,
                WHY[st] and (" (" .. WHY[st] .. ")") or "", reply:sub(1, 200)))
        end
    end
end
-- ONLINE ONLY END
--OFFLINE: function LB.poll() end
-- Each HUD pass: the summary's texts, and closing it.
function LB.hud(now)
    local sh = LB.show
    if sh and not sh.at and H and H.lbTitle and H.shown then sh.at = os.clock() end
    -- (closed show_s after it's on screen once it's answered, and after 3 minutes whatever: a send that never answers
    -- mustn't keep it up)
    if sh and sh.at and os.clock() - sh.at > ((sh.state ~= "sending") and (CFG.leaderboard.show_s or 15) or 180) then
        LB.show, sh = nil, nil
    end
    if not (H and H.lbTitle) then return end
    local t = CFG.hud.text
    if not sh then
        if H.lbShown then
            if H.lbPanel then H.lbPanel:SetVisibility(VIS.Collapsed) end
            H.lbTitle:SetVisibility(VIS.Collapsed)
            for _, l in ipairs(H.lbLines) do l:SetVisibility(VIS.Collapsed) end
            H.lbShown = false
        end
        return
    end
    local r = sh.run
    local lines = { string.format(t.lb_lines[1], r.round), string.format(t.lb_lines[2], money(r.score)),
                    string.format(t.lb_lines[3], r.kills.air, r.kills.ground), string.format(t.lb_lines[4], r.won),
                    string.format(t.lb_lines[5], clockText(r.time_s)), string.format(t.lb_lines[6], money(r.zollars.earned)), "" }
    lines[8] = (sh.state == "sending" and t.lb_sending) or (sh.state == "sent" and string.format(t.lb_sent, money(tonumber(sh.score or r.score) or r.score)))
        or (sh.state == "queued" and t.lb_queued) or (sh.state == "refused" and string.format(t.lb_refused, tostring(sh.why):upper()))
        or ""
    setText(H.lbTitle, "lbTitleStr", string.format(t.lb_title, r.pilot ~= "" and r.pilot:upper() or "PILOT"))
    for i, l in ipairs(H.lbLines) do setText(l, "lbLineStr" .. i, lines[i] or "") end
    if not H.lbShown then
        if H.lbPanel then H.lbPanel:SetVisibility(VIS.HitTestInvisible) end
        H.lbTitle:SetVisibility(VIS.HitTestInvisible)
        for _, l in ipairs(H.lbLines) do l:SetVisibility(VIS.HitTestInvisible) end
        H.lbShown = true
    end
end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
-- The runs not yet answered for good: read at the start, sent one at a time (at the main menu or in a run).
function LB.queueTick()
    if not LB.loaded then
        LB.loaded = true
        local f = io.open(configDir() .. "pending_runs.txt", "r")
        if f then
            for line in f:lines() do if line:sub(1, 1) == "{" then LB.queue[#LB.queue + 1] = line end end
            f:close()
            if #LB.queue == 0 then saveQueue() end              -- (an empty file from an older version: deleted)
            if #LB.queue > 0 then log("leaderboard: " .. #LB.queue .. " run(s) waiting to be sent") end
        end
    end
    -- one at a time, none while a send is in flight (the run just ended is in the queue too)
    if #LB.queue == 0 or #LB.jobs > 0 or type(SV_Post) ~= "function" or os.clock() < (LB.qwait or 0) then return end
    if post(LB.queue[1], nil) == -8 then LB.qwait = math.huge end
end
-- ONLINE ONLY END
--OFFLINE: function LB.queueTick() end
end

---------------------------------------------------------------------------------------------------- alicorn
-- CFG.specials.alicorn; tools/survival_events.py ALCN_* builds the unit (EB_002's, without its pools), its lane and
-- its remote events (RE_SV_AlcnDive / Surface / Railgun / Volley / OpenCore / Advance / Remove).
do
local UNIT = "SV_Unit_Alicorn"

-- At the main menu: the Alicorn's Online Mode rows into the campaign tables (NPC, model, durability), before the
-- level loads (the spawner caches them then: hard rule 20). AddRow only; a model row's soft class is never read
-- (hard rule 29).
function SPC.alicornSetup()
    if SPC.alicornDone or not gameInstance() then return end
    local c = CFG.specials.alicorn
    SPC.alicornTries = (SPC.alicornTries or 0) + 1
    local pairs_, missing = {}, false
    for _, tp in ipairs(c.tables) do
        local from, to = loadObject(tp[1]), loadObject(tp[2])
        if not (from and to) then missing = true end
        pairs_[#pairs_ + 1] = { from, to, tp }
    end
    if missing then
        if SPC.alicornTries >= 20 then SPC.alicornDone = true; log("special: the Alicorn's tables didn't load; no Alicorn round") end
        return
    end
    SPC.alicornDone = true
    local added, total, lost = 0, 0, {}
    for _, p in ipairs(pairs_) do
        local from, to = p[1], p[2]
        pin(from, nameOf(from)); pin(to, nameOf(to))
        for _, row in ipairs(rowList(from) or {}) do
            total = total + 1
            local _, have = dtCall(to, "FindRow", row)
            if have == nil then
                local _, r = dtCall(from, "FindRow", row)
                if r ~= nil then dtCall(to, "AddRow", row, r); _, have = dtCall(to, "FindRow", row) end
            end
            if have ~= nil then added = added + 1 else lost[#lost + 1] = row end
        end
    end
    SPC.alicornReady = total > 0 and #lost == 0
    log(string.format("special: the Alicorn's rows: %d of %d in the campaign tables%s", added, total,
        #lost > 0 and (" (missing: " .. table.concat(lost, ", ") .. ")") or ""))
end

function SPC.alicornSpawn(now)
    local c, t = CFG.specials.alicorn, CFG.hud.text
    if not (nativeReady() and SPC.alicornReady) then
        log("special: no Alicorn round (" .. (SPC.alicornReady and "no native spawner" or "its rows aren't in") .. ")")
        return false
    end
    if SV_UnitAlive(UNIT) > 0 then
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_AlcnRemove") or "n/a"
        log("special: the Alicorn was still up from last time; taken off (" .. tostring(r) .. "), none this round")
        return false
    end
    spawningUnit = UNIT
    local r = SV_Spawn(UNIT)
    spawningUnit = nil
    log("special: the Alicorn (" .. UNIT .. "): " .. (r > 0 and "up" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r <= 0 then return false end
    local s = D.special
    s.state, s.at, s.tanks, s.coreOpen, s.dived = "sail", now, 4, false, false
    s.nextDive, s.nextRail, s.nextVolley = now + c.dive_every_s, now + c.first_shot_s, now + c.first_shot_s + 5
    hudCallout(t.alicorn_go, t.alicorn_go_sub)
    log(string.format("special: round %d, the Alicorn in the west sea", D.round))
    return true
end

local function fire(ev)
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    if r ~= 1 then log("special: " .. ev .. " not fired: " .. (SV_ERR[r] or tostring(r))) end
end

-- The player's standard missile's damage (LiveWeaponBase.damage, in health points: HealthInternal is health x 10),
-- from a loaded missile or its class default; nil when none can be read
function SPC.playerMissileDamage()
    local function dmg(o)
        local ok, d = pcall(function() return o.damage end)
        return ok and type(d) == "number" and d > 0 and d or nil
    end
    for _, o in ipairs(FindAllOf("LiveMissile") or {}) do
        if valid(o) and nameOf(o):find("BP_plwp_msl_", 1, true) then
            local d = dmg(o)
            if d then return d, nameOf(o) end
        end
    end
    for _, v in ipairs({ "a0", "a1", "f0", "j0", "r0" }) do
        local o = StaticFindObject(string.format("/Game/Blueprints/Weapons/MSL/Player/Msl/BP_plwp_msl_%s.Default__BP_plwp_msl_%s_C", v, v))
        local d = valid(o) and dmg(o)
        if d then return d, "Default__BP_plwp_msl_" .. v .. "_C" end
    end
    return nil
end

-- Its parts that are up, by class: { actor, ... } (FindAllOf: every 2 s only)
local function parts(cls)
    local out = {}
    for _, o in ipairs(FindAllOf(cls) or {}) do
        if valid(o) and not nameOf(o):find("Default__", 1, true) then out[#out + 1] = o end
    end
    return out
end
local function hp(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return ok and type(h) == "number" and h or nil
end

function SPC.alicornTick(now, s)
    if s.state ~= "sail" or now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    local c, t = CFG.specials.alicorn, CFG.hud.text
    -- the dives, and its guns while it's up
    if not s.dived and now >= s.nextDive then
        s.dived, s.surfaceAt = true, now + c.dive_for_s
        fire("RE_SV_AlcnDive"); hudCallout(t.alicorn_dive, nil); log("special: the Alicorn dives")
    elseif s.dived and now >= s.surfaceAt then
        s.dived, s.nextDive = false, now + c.dive_every_s
        s.nextRail, s.nextVolley = math.max(s.nextRail, now + 5), math.max(s.nextVolley, now + 8)
        fire("RE_SV_AlcnSurface"); hudCallout(t.alicorn_surface, nil); log("special: the Alicorn surfaces")
    end
    if not s.dived and now >= s.nextRail then s.nextRail = now + c.railgun_every_s; fire("RE_SV_AlcnRailgun") end
    if not s.dived and now >= s.nextVolley then s.nextVolley = now + c.volley_every_s; fire("RE_SV_AlcnVolley") end
    -- its parts, every 2 s
    if now < (s.partsAt or 0) then return end
    s.partsAt = now + 2
    local hx = math.min(c.health_max_x or 1.5, (c.health_x or 1) *
        (1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first)))
    s.scaled = s.scaled or {}
    -- one look at the parts a check; a part whose health can't be read counts as up (code review of 2026-10-23:
    -- counted as down it paid every reward and sank the Alicorn 2 s after it appeared)
    local tankList, all, isTank = {}, {}, {}
    for _, cls in ipairs(c.tank_classes) do
        for _, o in ipairs(parts(cls)) do tankList[#tankList + 1] = o; all[#all + 1] = o; isTank[o] = true end
    end
    local core = parts(c.core_class)
    for _, o in ipairs(core) do all[#all + 1] = o end
    -- the tanks' health: tank_missiles standard missiles each (tried for 5 checks; the tanks wait for it meanwhile)
    local tankHp, tankWait
    if (c.tank_missiles or 0) > 0 then
        if not s.mslDamage and (s.mslTries or 0) < 5 then
            s.mslTries = (s.mslTries or 0) + 1
            local d, from = SPC.playerMissileDamage()
            s.mslDamage = d
            if d then log(string.format("special: Alicorn tanks: your missile does %s damage (%s)", tostring(d), tostring(from)))
            elseif s.mslTries == 5 then log("special: Alicorn tanks: your missile's damage can't be read; tanks keep health x health_x") end
        end
        tankWait = not s.mslDamage and (s.mslTries or 0) < 5
        if s.mslDamage then tankHp = math.floor(c.tank_missiles * s.mslDamage * 10 * hx / (c.health_x or 1) + 0.5) end
    end
    for _, o in ipairs(all) do                         -- each part's health for this round, once
        local key = addrOf(o) or nameOf(o)
        local want = isTank[o] and tankHp
        if not s.scaled[key] and (hx ~= 1 or want) and not (isTank[o] and tankWait) then
            s.scaled[key] = true
            local h0 = hp(o)
            if h0 and h0 > 0 then
                pcall(function() o.HealthInternal = want or h0 * hx end)
                log(string.format("special: Alicorn part %s health %s (%s -> %s)", nameOf(o):match("([%w_]+)_C_%d+") or "?",
                    want and string.format("%d missiles", math.floor(want / (s.mslDamage * 10) + 0.5)) or string.format("x%.2f", hx),
                    tostring(h0), tostring(hp(o))))
            end
        end
    end
    -- its weapons: weapon_missiles / railgun_missiles each (the first 5 checks, once the missile's damage is known)
    if (s.weaponChecks or 0) < 5 and not tankWait then
        s.weaponChecks = (s.weaponChecks or 0) + 1
        local n, growth = 0, hx / (c.health_x or 1)
        for cls, k in pairs(c.weapon_classes or {}) do
            local m = c[k] or 0
            for _, o in ipairs(m > 0 and s.mslDamage and parts(cls) or {}) do
                local key = addrOf(o) or nameOf(o)
                local h0 = not s.scaled[key] and hp(o)
                if h0 and h0 > 0 then
                    s.scaled[key] = true
                    local want = math.floor(m * s.mslDamage * 10 * growth + 0.5)
                    if want < h0 and pcall(function() o.HealthInternal = want end) then n = n + 1 end
                end
            end
        end
        if n > 0 then
            log(string.format("special: Alicorn weapons: %d parts lowered to %d missiles (railguns %d)", n,
                math.floor((c.weapon_missiles or 0) * growth + 0.5), math.floor((c.railgun_missiles or 0) * growth + 0.5)))
        end
    end
    local tanks, seen = 0, #tankList
    s.tankHp = s.tankHp or {}
    for _, o in ipairs(tankList) do
        local h = hp(o)
        if h == nil or h > 0 then tanks = tanks + 1 end
        local key = addrOf(o) or nameOf(o)                -- each hit on a tank, to check the missile count
        if h and s.tankHp[key] and h < s.tankHp[key] then
            log(string.format("special: Alicorn tank %s hit: -%.0f (%.0f left)", nameOf(o):match("btank(%a%a)") or "?", s.tankHp[key] - h, h))
        end
        if h and s.scaled[key] then s.tankHp[key] = h end
    end
    if seen > 0 then s.tanksSeen = true end
    if s.tanksSeen and tanks < (s.tanks or 4) then
        addCredits(TIER.pay(c.tank_pay * TIER.specialX(), TIER.index(D.round)) * ((s.tanks or 4) - tanks), "Alicorn ballast tank down")
        LB.stat("ground", (s.tanks or 4) - tanks)
        log(string.format("special: Alicorn ballast tanks left: %d", tanks))
        s.tanks = tanks
    end
    if s.tanksSeen and tanks == 0 and not s.coreOpen then
        s.coreOpen = true
        fire("RE_SV_AlcnAdvance"); fire("RE_SV_AlcnOpenCore")
        hudCallout(t.alicorn_core, t.alicorn_core_sub)
        log("special: the Alicorn's ballast tanks are gone: its core opens")
    end
    local coreUp = false
    for _, o in ipairs(core) do local h = hp(o); if h == nil or h > 0 then coreUp = true end end
    if #core > 0 then s.coreSeen = true end
    local hull = SV_UnitAlive(UNIT)
    if (s.coreOpen and s.coreSeen and not coreUp) or hull == 0 or hull == -7 then
        s.state = "done"
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, "the Alicorn sunk")
        LB.stat("ground", 1); LB.special("alicorn", true, now - s.at)
        hudCallout(t.alicorn_down, string.format(t.alicorn_down_sub, pay))
        log(string.format("special: round %d, the Alicorn sunk %.0f s after it appeared (core %s, hull %d)", D.round, now - s.at,
            coreUp and "up" or "down", hull))
        D.alicornRemoveAt = now + 20                    -- (off once it has gone down)
    elseif not s.partsSaid and now - s.at > 30 then
        s.partsSaid = true
        log(string.format("special: the Alicorn's parts found: %d ballast tanks, %d core", seen, #core))
    end
end
end

---------------------------------------------------------------------------------------------------- amphibious assault
-- CFG.specials.amphibious; tools/survival_events.py LCAC_* builds the units, paths and records. A lane L is unit
-- SV_Unit_Lcac<L> (four craft, W X Y Z); a craft that reaches the beach sets SV_LcacLand<L><craft> and its troops are
-- SV_Unit_LcacTroops<L><craft>, whose arrival at the runway sets SV_LcacRunway<L><craft>. RUN.amph.troops: the troop
-- units put ashore this run that are still up; RUN.captured: { untilRound, closePending, closed } while the airfield is
-- taken.
do
local function amph() RUN.amph = RUN.amph or { count = 0, troops = {}, capture = 0 }; return RUN.amph end

local function tierPay(base) return (TIER.pay(base * TIER.specialX(), D and D.round and TIER.index(D.round))) end

-- The troop units' actors, as SV_Spawn creates them (spawningUnit is the troop unit then): AMPH.actors[unit] = { actor }
AMPH.actors = {}
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    if u and u:find("^SV_Unit_LcacTroops") then
        local l = AMPH.actors[u] or {}
        l[#l + 1] = o
        AMPH.actors[u] = l
    end
end)

-- A unit's vehicles alive: SV_UnitAlive, 0 for a unit that's off the list, nil for an error (not counted as kills).
local function aliveOf(unit)
    local n = SV_UnitAlive(unit)
    if n == -7 then return 0 end
    return n >= 0 and n or nil
end

-- Whether a landing can come now (native spawner, a lane not still afloat): startRound asks before it adds the
-- round's extras, so a landing that can't come is a plain normal round.
function AMPH.ready()
    if not nativeReady() then return false end
    for _, l in ipairs(CFG.specials.amphibious.lanes) do
        if (aliveOf("SV_Unit_Lcac" .. l) or 1) <= 0 then return true end
    end
    return false
end

-- Landing craft still on their way in, and troop vehicles ashore and alive.
function AMPH.counts()
    local craft, ashore = 0, 0
    local s = D and D.special and D.special.kind == "amphibious" and D.special
    if s and s.lanes then
        for _, l in pairs(s.lanes) do
            local landed = 0
            for _ in pairs(l.landed) do landed = landed + 1 end
            -- the craft not landed yet, at most those alive (code review of 2026-10-23: alive - landed undercounted
            -- once a landed craft was shot on its way out)
            craft = craft + math.max(0, math.min(l.alive, (l.n or l.alive) - landed))
        end
    end
    for _, t in ipairs(amph().troops) do ashore = ashore + math.max(0, t.alive) end
    return craft, ashore
end

-- The airfield's capture so far, in % (0-100).
function AMPH.capture() return math.min(100, amph().capture or 0) end

-- The round can't end while a craft is still coming in or troops are ashore and the airfield isn't taken.
function AMPH.busy(s)
    local craft, ashore = AMPH.counts()
    return craft > 0 or (ashore > 0 and not RUN.captured)
end

function AMPH.spawn(now)
    local c, t = CFG.specials.amphibious, CFG.hud.text
    if not nativeReady() then return false end
    local A = amph()
    local want = math.min(#c.lanes, c.lanes_first + A.count * c.lanes_more)
    local order = {}
    for _, l in ipairs(c.lanes) do table.insert(order, math.random(#order + 1), l) end
    local s = D.special
    s.lanes, s.state, s.at = {}, "assault", now
    local n = 0
    for _, l in ipairs(order) do
        if n >= want then break end
        local unit = "SV_Unit_Lcac" .. l
        if SV_UnitAlive(unit) > 0 then           -- still afloat from last time: off now, it comes again next time
            local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacRemove" .. l) or "n/a"
            log(string.format("special: lane %s's craft were still up; taken off (%s)", l, tostring(r)))
        else
            local r = SV_Spawn(unit)
            log(string.format("special: landing craft lane %s (%s): %s", l, unit, r > 0 and (r .. " craft") or
                ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
            if r > 0 then s.lanes[l] = { n = r, alive = r, landed = {}, removed = false, at = now }; n = n + 1 end
        end
    end
    if n == 0 then log("special: no landing craft could come; a normal round"); return false end
    A.count = A.count + 1
    hudCallout(t.amphib_go, t.amphib_go_sub)
    log(string.format("special: round %d, amphibious assault on %d lanes", D.round, n))
    return true
end

-- Every second: craft lost (pay), craft landed (their troops ashore), landed craft taken off once they're away.
function AMPH.tick(now, s)
    if s.state ~= "assault" or now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    local c, t = CFG.specials.amphibious, CFG.hud.text
    local f = svFlags() or {}
    for l, lane in pairs(s.lanes) do
        local unit = "SV_Unit_Lcac" .. l
        local alive = lane.removed and 0 or (aliveOf(unit) or lane.alive)
        if alive < lane.alive and not lane.removed then
            local pay = tierPay(c.craft_pay) * (lane.alive - alive)
            addCredits(pay, string.format("landing craft down (lane %s)", l))
            LB.stat("ground", lane.alive - alive)
            log(string.format("special: lane %s: %d landing craft left", l, alive))
        end
        lane.alive = alive
        for _, k in ipairs(c.craft) do
            -- (a flag still 1 from this lane's last assault is reset by its appearance: not read in the first 5 s)
            if now - lane.at >= 5 and (f["SV_LcacLand" .. l .. k] or 0) >= 1 and not lane.landed[k] then
                lane.landed[k] = now
                lane.firstLanded = lane.firstLanded or now
                local tu = "SV_Unit_LcacTroops" .. l .. k
                local r = -100
                if SV_UnitAlive(tu) <= 0 then
                    AMPH.actors[tu] = {}
                    spawningUnit = tu
                    r = SV_Spawn(tu)
                    spawningUnit = nil
                end
                log(string.format("special: lane %s craft %s on the beach; troops %s: %s", l, k, tu,
                    r > 0 and (r .. " vehicle(s) ashore") or (r == -100 and "still up from before" or
                    ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")"))))
                if r > 0 then
                    local A = amph()
                    A.troops[#A.troops + 1] = { unit = tu, alive = r, at = now, lane = l, craft = k }
                    if not s.ashoreSaid then s.ashoreSaid = true; hudCallout(t.ashore, t.ashore_sub) end
                end
            end
        end
        if lane.firstLanded and not lane.removed and now - lane.firstLanded >= c.remove_after_s then
            lane.removed = true                        -- (no pay for these: they got away)
            local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacRemove" .. l) or "n/a"
            log(string.format("special: lane %s's craft are away; taken off (%s)", l, tostring(r)))
        end
    end
end

-- The round is over (nothing coming in, no troops ashore, or the airfield taken): the reward if it held, and craft
-- still afloat taken off.
function AMPH.roundOver(now, s)
    local c, t = CFG.specials.amphibious, CFG.hud.text
    for l, lane in pairs(s.lanes or {}) do
        if not lane.removed and SV_UnitAlive("SV_Unit_Lcac" .. l) > 0 then
            lane.removed = true
            local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacRemove" .. l) or "n/a"
            log(string.format("special: lane %s's craft taken off at the round's end (%s)", l, tostring(r)))
        end
    end
    s.state = "done"
    if not RUN.captured and (amph().capture or 0) > 0 then        -- short of 100: the next landing starts from 0
        log(string.format("special: the capture stopped at %d%%", AMPH.capture()))
        amph().capture = 0
    end
    LB.special("amphibious", not s.captured, now - (s.at or now))
    if not s.captured then
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, "landing repelled")
        hudCallout(t.repelled, string.format(t.repelled_sub, pay))
        log(string.format("special: round %d, the landing was repelled", D.round))
    end
end

local function free(why, removeLeft)
    local cap, t = RUN.captured, CFG.hud.text
    RUN.captured, RUN.dirty = nil, true
    if removeLeft then                                   -- its time is up: the troops still ashore go
        for _, tr in ipairs(amph().troops) do
            if tr.alive > 0 then
                tr.alive, tr.removed = 0, true
                local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacTroopsRemove" .. tr.lane .. tr.craft) or "n/a"
                log(string.format("special: troops %s taken off (%s)", tr.unit, tostring(r)))
            end
        end
    end
    local reopen = cap.closed and not AF.down
    hudCallout(removeLeft and t.freed or t.retaken, t.retaken_sub)
    log("special: the airfield is free again (" .. why .. ")" .. (reopen and (", landing open" .. airfieldEvent("RE_SV_AirfieldOpen")) or ""))
end

-- Every tick, any round: troop vehicles lost (pay), the capture, landing closed under it, and the airfield freed.
function AMPH.runTick(now)
    if not D or not nativeReady() or now < (AMPH.nextAt or 0) then return end
    AMPH.nextAt = now + 1
    local c, t = CFG.specials.amphibious, CFG.hud.text
    local A, ashore, f = amph(), 0, nil
    for _, tr in ipairs(A.troops) do
        if tr.alive > 0 then
            local n = aliveOf(tr.unit) or tr.alive
            if n < tr.alive then
                addCredits(tierPay(c.troop_pay) * (tr.alive - n), "troop vehicle down (" .. tr.unit .. ")")
                LB.stat("ground", tr.alive - n)
                log(string.format("special: troops %s: %d left", tr.unit, n))
            end
            tr.alive = n
            ashore = ashore + n
        end
        -- at the runway (the end of its drive path): its share of the capture, once (troops spawned in the first 2 s
        -- may still read last time's flag, reset by their appearance)
        if tr.alive > 0 and not tr.reached and now - tr.at >= 2 then
            f = f or svFlags() or {}
            if (f["SV_LcacRunway" .. tr.lane .. tr.craft] or 0) >= 1 then
                tr.reached = true
                if not RUN.captured then
                    A.capture = math.min(100, (A.capture or 0) + c.capture_per_troop)
                    RUN.dirty = true
                    hudCallout(t.on_runway, string.format(t.on_runway_sub, A.capture))
                    log(string.format("special: troops %s reached the runway; airfield %d%% captured", tr.unit, A.capture))
                end
            end
        end
    end
    -- every 15 s: a troop vehicle short of the runway that hasn't moved stuck_m in stuck_s (or, with no actor seen,
    -- has been ashore troop_timeout_s) is taken off: no pay, no capture
    for _, tr in ipairs(A.troops) do
        if tr.alive > 0 and not tr.reached and now >= (tr.checkAt or tr.at + 15) then
            tr.checkAt = now + 15
            local at
            for _, o in ipairs(AMPH.actors[tr.unit] or {}) do
                if not at and valid(o) then
                    pcall(function() local v = o:K2_GetActorLocation(); at = { X = v.X, Y = v.Y, Z = v.Z } end)
                end
            end
            local why
            if at then
                local moved = tr.last and math.sqrt((at.X - tr.last.X) ^ 2 + (at.Y - tr.last.Y) ^ 2) / 100 or math.huge
                if moved < c.stuck_m then tr.still = (tr.still or 0) + 15 else tr.still, tr.last = 0, at end
                tr.last = tr.last or at
                if now >= (tr.posAt or 0) then
                    tr.posAt = now + 60
                    log(string.format("special: troops %s at (%.1f, %.1f) km, %.0f m up, %.1f km from the runway%s", tr.unit,
                        at.X / 100000, at.Y / 100000, at.Z / 100, math.sqrt((at.X - c.runway_cm[1]) ^ 2 + (at.Y - c.runway_cm[2]) ^ 2) / 100000,
                        (tr.still or 0) > 0 and string.format(", still for %d s", tr.still) or ""))
                end
                if (tr.still or 0) >= c.stuck_s then why = string.format("hasn't moved in %d s", tr.still) end
            elseif now - tr.at >= c.troop_timeout_s then
                why = string.format("ashore %d s, no actor to watch", math.floor(now - tr.at))
            end
            if why then
                local n = tr.alive
                tr.alive, tr.removed = 0, true
                local r = type(SV_Event) == "function" and SV_Event("RE_SV_LcacTroopsRemove" .. tr.lane .. tr.craft) or "n/a"
                hudCallout(t.troops_stuck, string.format(t.troops_stuck_sub, n))
                log(string.format("special: troops %s stuck (%s): taken off (%s)", tr.unit, why, tostring(r)))
                ashore = ashore - n
            end
        end
    end
    local up = {}                                         -- the dead ones out: a later assault's troops on the same
    for _, tr in ipairs(A.troops) do if tr.alive > 0 then up[#up + 1] = tr end end   -- lane / craft can't count them again
    A.troops = up
    if (A.capture or 0) >= 100 and not RUN.captured then
        RUN.captured, RUN.dirty = { untilRound = D.round + c.captured_rounds, closePending = true }, true
        A.capture = 0                                     -- (the meter starts over once it's back in our hands)
        if D.special and D.special.kind == "amphibious" then D.special.captured = true end
        LB.stat("captured", 1)
        hudCallout(t.captured, t.captured_sub)
        log(string.format("special: round %d, the airfield is captured (100%%, %d troop vehicles ashore); back after round %d at the latest",
            D.round, ashore, RUN.captured.untilRound))
    end
    local cap = RUN.captured
    if not cap then return end
    if cap.closePending then
        if playerOnAirfield() then
            if not cap.heldSaid then cap.heldSaid = true; log("special: captured, landing stays open until you take off") end
        else
            cap.closePending = false
            if not AF.closed then cap.closed = true; log("special: landing closed" .. airfieldEvent("RE_SV_AirfieldClose"))
            else cap.closed = true end
        end
    end
    if ashore == 0 then
        free("every landed troop vehicle destroyed", false)
    elseif D.state == "wait" and D.round >= cap.untilRound then
        free(string.format("%d rounds", c.captured_rounds), true)
    end
end
end

-- The world-data unit (flight) an AI plane belongs to, from its GetUnitName(); cached in p.unit, false if unreadable.
local planeUnit
do
local unitWarned = false
function planeUnit(p)
    if p.unit ~= nil then return p.unit end
    local ok, u = pcall(function() local v = p.obj:GetUnitName(); return type(v) == "string" and v or v:ToString() end)
    p.unit = (ok and type(u) == "string" and u ~= "") and u or false
    if not p.unit and not unitWarned then
        unitWarned = true
        log("planes: GetUnitName unreadable (" .. p.name .. ": " .. tostring(u) .. "); credits and bomb runs go by model")
    end
    return p.unit
end
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
    -- the landing page's rows: STORE when Survival's store pages are in the game's menu list, else the four old ones
    store = { "SVShopStore" },
    rows = { "SVShopMissiles", "SVShopSpecial", "SVShopFlares", "SVShopAirfield" },
    all = { "SVShopStore", "SVShopMissiles", "SVShopSpecial", "SVShopFlares", "SVShopAirfield" },
    -- the store's pages (tools/build_survival.py STORE_PAGES): in-game menus 20, 21 and 22 (SUPPLIES, AIRFIELD, DOCKS:
    -- rows "20", "21", "22" open them), added to the in-game menu table at the main menu, before a level builds its menu
    -- list from it
    menuMine = "/Game/Mods/SurvivalMode/Data/DT_SV_MenuClassRows.DT_SV_MenuClassRows",
    menuGame = "/Game/Datatables/UI/Menu/IngameMenu/DT_IngameMenuSettingData.DT_IngameMenuSettingData",
    menuRows = { { row = "SVStore", id = "SV_Store", index = 20 }, { row = "SVStoreAirfield", id = "SV_StoreAirfield", index = 21 },
                 { row = "SVStoreDocks", id = "SV_StoreDocks", index = 22 } },
    -- each row's icon (stock textures; the aircraft repair shows the player's own plane when the game has its icon)
    icons = {
        Missiles = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_msl_a0",
        Special  = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_qaam_a0",
        Flares   = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_flr",
        RepairAircraft = "/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP004_f15c",
        RepairAirfield = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Base_000",
        Airfield = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Base_000",
        AAGun    = "/Game/UI/Texture/Icon/Tutorial/T_UI_TutorialIcon_TGT_Gnd_000",
        SAM      = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_saam_a0",
        Moonchild   = "/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP005_f22a",
        ShipAegis   = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_GndEscort_000",   -- (no ship icon in the game: an ally's)
        ["20"]   = "/Game/NUI/Common/Texture/IconMenu/T_Menu_Common_IconMenu_Shop_000",          -- STORE, SUPPLIES >
        ["21"]   = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Base_000",                         -- AIRFIELD >
        ["22"]   = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Sonar_000",                        -- DOCKS >
    },
}
local SH = { added = false, addr = nil, warned = {}, decor = {} }

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
        local store = SHOP.storeCheck()
        if store == nil then return end                  -- (the game's menu list isn't readable yet)
        local rows = store and SHOP.store or SHOP.rows
        local mine = loadObject(SHOP.mine)
        if not valid(mine) then shopWarn("mine", "could not load DT_SV_ShopRows"); return end
        pin(mine, nameOf(mine))
        local n = 0
        for _, r in ipairs(SHOP.all) do                  -- the other set out (a level before had the other)
            local keep = false
            for _, k in ipairs(rows) do if k == r then keep = true end end
            if not keep then dtCall(game, "RemoveRow", r) end
        end
        for _, r in ipairs(rows) do
            local _, have = dtCall(game, "FindRow", r)
            if have == nil then
                local _, src = dtCall(mine, "FindRow", r)
                if src ~= nil then dtCall(game, "AddRow", r, src) end
            end
            local _, now = dtCall(game, "FindRow", r)
            if now ~= nil then n = n + 1 end
        end
        SH.added = n == #rows
        log(string.format("shop: %s: %d of %d rows in the landing menu (%s)", store and "the STORE" or "the shop rows",
            n, #rows, rowNames(game)))
    elseif SH.addr then
        local game = StaticFindObject(SHOP.game)
        if valid(game) then
            for _, r in ipairs(SHOP.all) do dtCall(game, "RemoveRow", r) end
            log("shop: rows taken out of the landing menu (not in Survival's level)")
        end
        SH.added, SH.addr = false, nil
    end
end

-- The store's pages into the in-game menu table, from the main menu on (the menu list is built when a level starts).
-- SH.menuOk: both rows sit at the indexes the landing rows name (another mod's rows in that table would move them).
function SHOP.menuSetup()
    if SH.menuDone or not CFG.shop.enabled or not gameInstance() then return end
    SH.menuTries = (SH.menuTries or 0) + 1
    local game, mine = loadObject(SHOP.menuGame), loadObject(SHOP.menuMine)
    if not (valid(game) and valid(mine)) then
        if SH.menuTries >= 20 then SH.menuDone = true; log("shop: the store's menu tables didn't load; the shop rows stand in") end
        return
    end
    pin(game, nameOf(game)); pin(mine, nameOf(mine))
    for _, m in ipairs(SHOP.menuRows) do            -- (each step logged: test of 2026-10-23 got nil / nil, no error)
        local okH, have = dtCall(game, "FindRow", m.row)
        local steps = { "in the game's table: " .. (okH and (have ~= nil and "yes" or "no") or ("error " .. tostring(have))) }
        if have == nil then
            local okR, r = dtCall(mine, "FindRow", m.row)
            steps[#steps + 1] = "in DT_SV_MenuClassRows: " .. (okR and (r ~= nil and type(r) or "no") or ("error " .. tostring(r)))
            if okR and r ~= nil then
                -- (never read r.MenuWidgetReference from Lua: UE4SS's copy of a soft class reference crashed the game
                -- at the main menu, test of 2026-10-23, in FSoftObjectPath::operator= -> FString::operator=)
                local okA, e = dtCall(game, "AddRow", m.row, r)
                steps[#steps + 1] = "AddRow " .. (okA and "ran" or ("error " .. tostring(e)))
                local okF, now = dtCall(game, "FindRow", m.row)
                steps[#steps + 1] = "now " .. (okF and (now ~= nil and "in" or "not in") or ("error " .. tostring(now)))
            end
        end
        log("shop: store page " .. m.row .. ": " .. table.concat(steps, "; "))
    end
    log("shop: in-game menu table rows: " .. rowNames(game) .. " | DT_SV_MenuClassRows: " .. rowNames(mine))
    local at = {}
    for i, n in ipairs(rowList(game) or {}) do at[n] = i - 1 end
    SH.menuOk = true
    for _, m in ipairs(SHOP.menuRows) do if at[m.row] ~= m.index then SH.menuOk = false end end
    SH.menuDone = true
    local where = {}
    for _, m in ipairs(SHOP.menuRows) do where[#where + 1] = string.format("%s at %s (want %d)", m.row, tostring(at[m.row]), m.index) end
    log("shop: the store's pages in the in-game menu table: " .. table.concat(where, ", ")
        .. (SH.menuOk and "" or ": the shop rows stand in"))
end

-- In Survival's level: are the store's pages in the game's menu list (LiveMenuManager.MenuWidgetClassList, built from
-- the table when the level started)? true / false, or nil while it can't be read yet.
function SHOP.storeCheck()
    if SH.store ~= nil then return SH.store end
    if not SH.menuOk then SH.store = false; return false end
    SH.storeTries = (SH.storeTries or 0) + 1
    local ok, got = pcall(function()
        local m = FindFirstOf("LiveMenuManager")
        if not valid(m) then return nil end
        local list = m.MenuWidgetClassList
        local n = list:GetArrayNum()
        local ids = {}
        for _, e in ipairs(SHOP.menuRows) do
            local v = e.index < n and list[e.index + 1].MenuIDName
            ids[#ids + 1] = not v and "-" or type(v) == "string" and v or v:ToString()
        end
        return { n = n, ids = ids }
    end)
    if ok and got then
        SH.store = true
        local parts = {}
        for k, e in ipairs(SHOP.menuRows) do
            if got.ids[k] ~= e.id then SH.store = false end
            parts[#parts + 1] = string.format("%d = %s", e.index, got.ids[k])
        end
        log(string.format("shop: the game's menu list has %d menus; %s: %s", got.n, table.concat(parts, ", "),
            SH.store and "the STORE is in" or "the shop rows stand in"))
    elseif SH.storeTries >= 10 then
        SH.store = false
        log("shop: the game's menu list couldn't be read (" .. tostring(got) .. "); the shop rows stand in")
    end
    return SH.store
end

-- Icons on the landing menu's rows (any page of it: the landing page, the STORE pages): an Image in each row's own
-- canvas, its label moved over (tools/re/AIRFIELD_SHOP_UI.md rank 2). Rows are reused, so each row's icon follows the
-- StringArgs of the command it shows now.
do
local texCache = {}
local function texture(path)
    if texCache[path] == nil then
        local name = path:match("[^/]+$")
        texCache[path] = loadObject(path .. "." .. name) or false
    end
    return texCache[path] or nil
end
-- the player's own plane's icon (T_HUD_acIcon_PP<nnn>_<model>, from its BP_PlayerPlane_PP<nnnn>_<model>), if any
local function planeIcon()
    local ok, n = pcall(function() return nameOf(survivalPC.Pawn) end)
    local num, model = ok and n and n:match("PP0*(%d+)_(%w+)")
    if not num then return nil end
    return texture(string.format("/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP%03d_%s", tonumber(num), model))
end
local function child(w, n)                           -- (childWidget, declared further down)
    local ok, x = pcall(function() return w:GetWidgetFromName(FName(n)) end)
    if ok and valid(x) then return x end
    ok, x = pcall(function() return w[n] end)
    return ok and valid(x) and x or nil
end
local function argsOf(list, k)
    local ok, a = pcall(function() return list.CommandDatas[k].StringArgs:ToString() end)
    return ok and a or nil
end
function SHOP.decorTick(tick)
    if not CFG.shop.enabled or tick % 2 ~= 0 or not playerOnAirfield() then return end
    local imgClass = StaticFindObject("/Script/UMG.Image")
    if not valid(imgClass) then return end
    for _, win in ipairs(FindAllOf("WBP_Menu_IngameHangar_Common_000_C") or {}) do
        if liveWidget(win) then
            local list = child(win, "WBP_Menu_Pause_List_000")
            for k = 1, 6 do
                local row = list and child(list, string.format("WBP_Menu_Text_Focus_000_%02d", k))
                local args = row and argsOf(list, k)
                local item = args and (args:match("^SV_Buy_(.+)$") or (SHOP.icons[args] and args:match("^%d+$") and args))
                local a = row and addrOf(row)
                if a and item then
                    local d = SH.decor[a]
                    if not d or not valid(d.img) then
                        local ok, err = pcall(function()
                            local canvas = child(row, "CanvasPanel_79")
                            if not canvas then error("no CanvasPanel_79 in the row") end
                            local img = StaticConstructObject(imgClass, row.WidgetTree, FName(string.format("SV_StoreIcon_%d", k)))
                            local slot = canvas:AddChildToCanvas(img)
                            slot:SetPosition({ X = 92, Y = 20 }); slot:SetSize({ X = 48, Y = 48 })
                            local hb = child(row, "HorizontalBox_59")         -- the label, moved right of the icon
                            if hb then pcall(function() hb.Slot:SetPosition({ X = 152, Y = 0 }) end) end
                            d = { img = img }
                            SH.decor[a] = d
                        end)
                        if not ok and not SH.decorSaid then SH.decorSaid = true; log("shop: row icons failed: " .. tostring(err)) end
                    end
                    if d and d.item ~= item and valid(d.img) then
                        local tex = (item == "RepairAircraft" and planeIcon()) or texture(SHOP.icons[item] or SHOP.icons.Airfield)
                        if tex then pcall(function() d.img:SetBrushFromTexture(tex, false) end) end
                        d.item = item
                        if not SH.decorDone then SH.decorDone = true; log("shop: row icons on the landing menu") end
                    end
                elseif a and SH.decor[a] and valid(SH.decor[a].img) then     -- a stock row now: no icon
                    pcall(function() SH.decor[a].img:SetVisibility(1) end)
                    SH.decor[a].item, SH.decor[a].hidden = nil, true
                end
                if a and item and SH.decor[a] and SH.decor[a].hidden then
                    pcall(function() SH.decor[a].img:SetVisibility(4) end); SH.decor[a].hidden = nil
                end
            end
        end
    end
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
    if RUN.captured then return true end            -- the amphibious assault took the airfield
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

-- The player's aircraft health in % (its HealthInternal is health x 10), the last one read when it can't be now.
local function aircraftHealth()
    local ok, pct = pcall(function()
        local pawn = survivalPC.Pawn
        local m = pawn.MaxHealth
        return m > 0 and math.max(0, math.min(100, math.floor(pawn.HealthInternal / 10 / m * 100 + 0.5))) or nil
    end)
    if ok and pct then RUN.acHp = pct end
    return RUN.acHp
end

-- (the shop's texts again when the aircraft's health changes: shopTick calls it)
function SHOP.healthCheck()
    local hp = aircraftHealth()
    if hp ~= RUN.acHpShown then RUN.acHpShown, RUN.dirty = hp, true end
end

-- The aircraft repair's price for `pct` health (CFG.shop.items.RepairAircraft), or nil when it's whole.
local function aircraftRepairPrice(pct)
    local a = CFG.shop.items.RepairAircraft
    if not (a and pct and pct < 100) then return nil end
    return math.max(a.min_price, math.ceil(a.price * (100 - pct) / 100 / 10) * 10)
end

local function defencesUp(kind)
    local def = CFG.shop.items.Airfield.defences[kind]
    local units, n = def and def.units or {}, 0
    if nativeReady() then for _, u in ipairs(units) do if SV_UnitAlive(u) > 0 then n = n + 1 end end end
    return n, #units
end

-- A free unit of defence `kind` and its price now (each one built makes the next of its kind dearer), or nil.
local function defenceFor(kind)
    local d = CFG.shop.items.Airfield.defences
    local def = d and d[kind]
    if not (def and D and nativeReady()) then return nil end
    RUN.defences = RUN.defences or { built = 0, bought = {} }
    for _, u in ipairs(def.units) do
        if SV_UnitAlive(u) <= 0 then
            return { kind = kind, unit = u, def = def,
                     price = math.floor(def.price * def.raise ^ (RUN.defences.bought[kind] or 0) / 10 + 0.5) * 10 }
        end
    end
    return nil
end

-- What item `name`'s row offers now: { role, label, help, price (nil: nothing to buy now), why (when there isn't),
-- plus the defence's unit for aa / sam }. The texts, the purchases and the STORE's checks all go through it.
local function offer(name)
    local it = CFG.shop.items[name]
    local o = { role = it.kind and "ammo" or it.role }
    if o.role == "combined" then                     -- the old fourth row: aircraft, then airfield, then defences
        o.role = aircraftRepairPrice(aircraftHealth()) and "aircraft" or (airfieldNeedsRepair() and "airfield" or "defence")
    end
    if o.role == "ammo" then
        local cap = A and A.caps and A.caps[it.kind]
        local max = A and A.max and A.max[it.kind]
        o.label = string.format("%s +%d", it.label, it.step)
        o.help = string.format("%d more %s. Landing doesn't rearm: you fly with what you buy%s.", it.step, it.what,
            cap and string.format(" (you have %d)", cap) or "")
        if cap and max and cap >= max then o.why = "ALREADY AT FULL LOAD." else o.price = shopPrice(name) end
    elseif o.role == "aircraft" then
        local hp = aircraftHealth()
        o.label, o.price = CFG.shop.items.RepairAircraft.label, aircraftRepairPrice(hp)
        o.help = string.format("Repairs your aircraft to full health (now %s%%).", tostring(hp or "?"))
        if not o.price then o.why = "YOUR AIRCRAFT ISN'T DAMAGED." end
    elseif o.role == "airfield" then
        o.label = string.format("%s +%d", CFG.shop.items.RepairAirfield.label, it.repair)
        o.help = string.format("Repairs the airfield by %d (now %s of %d).", it.repair,
            AF.down and "down" or tostring(AF.hp or "?"), CFG.airfield.hp)
        if not AF.hp or AF.down then o.why = "THE AIRFIELD IS DOWN."
        elseif AF.hp >= CFG.airfield.hp then o.why = "THE AIRFIELD IS NOT DAMAGED."
        else o.price = shopPrice(name) end
    elseif o.role == "ally_air" or o.role == "ally_ship" then          -- CFG.allies
        local c = CFG.allies
        local units = o.role == "ally_air" and c.aircraft.units or c.ships[it.ship].units
        local up, free = ALLY.status(units)
        o.label = it.label
        o.help = o.role == "ally_air"
            and string.format("Squadron %s, two F-22s: they take off from the airfield once you're airborne and fight until shot down (%d of %d flights up).",
                c.aircraft.name, up, #units)
            or string.format("The %s sails the waters by the airfield and fights until sunk (%d of %d at sea).",
                c.ships[it.ship].name, up, #units)
        if not c.enabled or not ALLY.ready then o.why = "NOT AVAILABLE."
        elseif not free then o.why = o.role == "ally_air" and "BOTH FLIGHTS ARE UP." or string.format("ALL %d ARE AT SEA.", #units)
        else o.price, o.unit = shopPrice(name), free end
    else                                             -- a defence: aa / sam, or the old row's next one in turn
        local aa, aaMax = defencesUp("aa")
        local sam, samMax = defencesUp("sam")
        local up = string.format(" (AA guns %d of %d, SAM sites %d of %d up)", aa, aaMax, sam, samMax)
        local f = (o.role == "defence") and defenceOffer() or defenceFor(o.role)
        local def = CFG.shop.items.Airfield.defences[o.role] or (f and f.def)
        o.label = f and ("BUILD " .. f.def.label) or ((o.role == "defence" and "AIRFIELD DEFENCES" or ("BUILD " .. def.label)) .. ": ALL BUILT")
        o.help = f and string.format("Builds %s at the airfield for the rest of the run%s.", f.def.what, up)
            or ("Every one is up" .. up .. ".")
        if f then o.price, o.unit, o.kind, o.def = f.price, f.unit, f.kind, f.def else o.why = "ALL BUILT." end
    end
    return o
end

function shopTexts()
    if type(SV_SetText) ~= "function" then return end
    RUN.offerShown = RUN.offerShown or {}
    for name in pairs(CFG.shop.items) do
        local o = offer(name)
        RUN.offerShown[name] = o.role
        local label = o.label .. (o.price and string.format("   %d Z", o.price) or "")
        local help = shopClosed() and (RUN.captured and CFG.hud.text.shop_captured or CFG.hud.text.shop_closed) or o.help
        help = string.format("ZOLLARS %d. %s%s", RUN.credits, RUN.msg[name] and (RUN.msg[name] .. " ") or "", help)
        SV_SetText("SV_Shop_" .. name, label)
        SV_SetText("SV_Shop_" .. name .. "_Help", help)
    end
    -- the STORE's own texts: its row on the landing page, its page titles and the rows between its pages
    local z = string.format("ZOLLARS %d", RUN.credits)
    SV_SetText("SV_Shop_Store", "STORE")
    SV_SetText("SV_Shop_Store_Help", z .. ". Missiles, special weapons, flares, repairs, airfield defences, allied aircraft and ships.")
    SV_SetText("SV_Store_Title", "AIRFIELD STORE: SUPPLIES   " .. z)
    SV_SetText("SV_Store_TitleAirfield", "AIRFIELD STORE: AIRFIELD   " .. z)
    SV_SetText("SV_Store_TitleDocks", "AIRFIELD STORE: DOCKS   " .. z)
    SV_SetText("SV_Store_ToAirfield", "AIRFIELD >")
    SV_SetText("SV_Store_ToAirfield_Help", z .. ". Airfield repairs, AA guns, SAM sites and " .. CFG.allies.aircraft.name .. "'s F-22s.")
    SV_SetText("SV_Store_ToDocks", "DOCKS >")
    SV_SetText("SV_Store_ToDocks_Help", z .. ". Allied ships for the waters by the airfield.")
    SV_SetText("SV_Store_ToSupplies", "SUPPLIES >")
    SV_SetText("SV_Store_ToSupplies_Help", z .. ". Missiles, special weapons, flares and aircraft repairs.")
end

-- One purchase; the result goes into the item's help line and the log.
function shopBuy(name)
    local it = CFG.shop.items[name]
    if not it then log("shop: unknown item " .. tostring(name)); return end
    local function done(msg) RUN.msg[name] = msg; RUN.dirty = true; log("shop: " .. name .. ": " .. msg) end
    if shopClosed() then return done("CLOSED.") end
    local o = offer(name)
    if RUN.offerShown and RUN.offerShown[name] and RUN.offerShown[name] ~= o.role then
        return done("THIS ROW CHANGED: CHECK IT AND PRESS AGAIN.")       -- (the old fourth row's job moved on)
    end
    if not o.price then return done(o.why or "NOT AVAILABLE RIGHT NOW.") end
    local price = o.price
    if RUN.credits < price then return done(string.format("NOT ENOUGH ZOLLARS (%d needed).", price)) end
    if o.role == "aircraft" then
        -- the stock repair (RE_SV_RepairAircraft: health and armour pool) and the health written straight onto the
        -- aircraft, then read back: paid only once it reads full (test of 2026-10-23: the event alone left it at 63%
        -- and four presses charged four times)
        local before = aircraftHealth()
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_RepairAircraft") or -5
        local okW, errW = pcall(function()
            local pawn = survivalPC.Pawn
            pawn.HealthInternal = math.floor(pawn.MaxHealth * 10 + 0.5)
        end)
        RUN.acHp = nil
        local after = aircraftHealth()
        log(string.format("shop: aircraft repair: %s%% -> %s%% (event %s, health written %s)", tostring(before), tostring(after),
            r == 1 and "fired" or (SV_ERR[r] or tostring(r)), okW and "yes" or ("no: " .. tostring(errW))))
        if not (after and after >= 99) then return done("COULD NOT REPAIR IT (NOTHING CHARGED).") end
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        return done(string.format("AIRCRAFT REPAIRED (%s%% -> %d%%) for %d.", tostring(before), after, price))
    elseif o.role == "ally_air" or o.role == "ally_ship" then
        local ok, msg = ALLY.buy(o.role, o.unit, it.ship, price)
        if not ok then return done(msg) end
        LB.stat("allies", 1)
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        return done(string.format("%s for %d.", msg, price))
    elseif o.unit then                               -- a defence
        local r = SV_Spawn(o.unit)
        if r <= 0 then return done("COULD NOT BUILD IT (" .. (SV_ERR[r] or tostring(r)) .. ").") end
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.defences.built = RUN.defences.built + 1
        RUN.defences.bought[o.kind] = (RUN.defences.bought[o.kind] or 0) + 1
        return done(string.format("%s BUILT for %d (%s).", o.def.label, price, o.unit))
    elseif o.role == "ammo" then
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
    else                                             -- the airfield
        AF.full, AF.base, AF.bombBase = math.min(CFG.airfield.hp, AF.hp + it.repair), AF.hits, AF.bomb
        AF.hp = AF.full                             -- airfieldTick works health out from these from now on
    end
    RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
    RUN.bought[name] = (RUN.bought[name] or 0) + 1
    done(string.format("BOUGHT for %d.", price))
end
end

-- A menu sound by its Wwise event name (the game-SE bank, always loaded; tools/re/MUSIC_RADIO_CAMERA.md).
function SHOP.sound(name)
    local ok, err = pcall(function()
        local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
        if not valid(lib) then error("LiveSoundBlueprintLibrary not found") end
        lib:PostEventByName(valid(survivalPC) and survivalPC or FindFirstOf("PlayerController"), FName(name))
    end)
    if not ok and not SH.soundSaid then SH.soundSaid = true; log("shop: menu sound " .. name .. " failed: " .. tostring(err)) end
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
                local spent = RUN.spent
                local ok, err = pcall(shopBuy, item)
                if not ok then log("shop: error " .. tostring(err)) end
                -- (user, 2026-10-23: "add a menu beep for everytime you press one of the buttons")
                SHOP.sound(RUN.spent > spent and CFG.shop.sounds.bought or CFG.shop.sounds.refused)
            end
        end
    end
    if tick % 4 == 3 then pcall(SHOP.healthCheck) end
    if RUN.dirty then
        RUN.dirty = false
        local ok, err = pcall(shopTexts)
        if not ok then log("shop: text error " .. tostring(err)) end
    end
end

---------------------------------------------------------------------------------------------------- allies
-- The STORE's allies (CFG.allies; tools/survival_events.py ALLY_*). Their DT_NPC rows (DT_SV_NpcRows) go into DT_NPC at
-- the main menu, before a level loads (the spawner reads them then), each weapon on fire control of its own (<FCS>_SVA);
-- a ship sails when bought, a MOONCHILD flight spawns once you're airborne and the runway is clear (both flights park
-- on one spot) and the event package flies its takeoff. ALLY.run: the run's allies, up[unit] = { kind, key, at,
-- queued, price }, and the enemy orders waiting to be fired (events).
do
-- DT_SV_NpcRows' ally rows (tools/build_survival.py build_npc_rows: the F-22, the hulls and their turrets)
local ROWS = { "SV_Ally_Moonchild", "SV_Ally_Aegis", "SV_Def_Gepa", "SV_Def_Avng",
               "SV_Turret_aegs_mk15_Ally", "SV_Turret_aegs_mk41_Ally", "SV_Turret_aegs_mk45_Ally",
               "SV_Turret_aegs_artillery_Ally" }
local ROW_SHIP = {}            -- a ship type's hull and turret rows (its fcs and module): SV_Ally_<key>, SV_Turret_<turrets>_*
for _, row in ipairs(ROWS) do
    for key, sh in pairs(CFG.allies.ships) do
        if row == "SV_Ally_" .. key or (sh.turrets and row:find("SV_Turret_" .. sh.turrets .. "_", 1, true) == 1) then
            ROW_SHIP[row] = key
        end
    end
end
ROW_SHIP.SV_Def_Gepa, ROW_SHIP.SV_Def_Avng = "Defence", "Defence"   -- (the airfield's AA guns and SAM sites)
for _, u in ipairs(CFG.allies.aircraft.units) do ALLY.unit[u] = "air" end
for key, sh in pairs(CFG.allies.ships) do for _, u in ipairs(sh.units) do ALLY.unit[u] = key end end

function ALLY.setup()
    if ALLY.setupDone or not CFG.allies.enabled or not gameInstance() or not SR.done then return end
    ALLY.tries = (ALLY.tries or 0) + 1
    local npc, mine, fcs = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows), loadObject(FCS_TABLE)
    if not (npc and mine and fcs) then
        if ALLY.tries >= 20 then ALLY.setupDone = true; log("allies: their tables didn't load; the STORE sells none") end
        return
    end
    ALLY.setupDone = true
    local wpn = loadObject(WEAPON_TABLE)
    for _, t in ipairs({ npc, mine, fcs, wpn }) do if t then pin(t, nameOf(t)) end end
    local c, made, boosted, lost = CFG.allies.fcs, {}, 0, {}
    local shipSaid, shipModule, gunSaid = {}, {}, {}
    local modules = loadObject(SEARCH_MODULE.path)
    if modules then
        pin(modules, nameOf(modules))
        for key, sh in pairs(CFG.allies.ships) do
            local sf = sh.fcs
            if sf and sf.search_m then
                local row = "NPC_AIModule_SV_" .. key
                if cloneRow(modules, "NPC_AIModule_Turret000", row, function(r)
                    r.Radius = sf.search_m
                    pcall(function() r.bEnableLostTargetInClouds = false end)
                end) then
                    shipModule[key] = row
                    log(string.format("allies: %s's turrets search %d m (%s)", key, sf.search_m, row))
                end
            end
        end
    end
    local function allyFcs(src, key)                 -- src .. "_SVA[_<ship>]": farther, wider, quicker, tighter
        local sf = key and (key == "Defence" and CFG.shop.items.Airfield.defences.fcs
                            or CFG.allies.ships[key] and CFG.allies.ships[key].fcs)
        local new = src .. "_SVA" .. (sf and ("_" .. key) or "")
        local lockX, fireX = c.time_x * (sf and sf.lock_x or 1), c.time_x * (sf and sf.fire_x or 1)
        if made[new] == nil then
            made[new] = cloneRow(fcs, src, new, function(r)
                pcall(function() r.CaptureDistance = r.CaptureDistance * (sf and sf.range_x or c.range_x) end)
                pcall(function() r.CaptureAngleRange = math.min(180, r.CaptureAngleRange * c.angle_x) end)
                for f, x in pairs({ ActivationTime = lockX, TriggeringTime = lockX, ShotIntervalTime = fireX, RestingTime = fireX }) do
                    pcall(function() r[f] = r[f] * x end)
                end
                pcall(function()                     -- guns: MOONCHILD's lead and fire longer bursts, AA guns lead further
                    if src:find("PlaneGun", 1, true) then
                        r.PredictionOffsetTime = c.gun_lead_s or 0
                        r.TriggerCount = math.max(1, math.floor(r.TriggerCount * (c.burst_x or 1) + 0.5))
                        gunSaid[#gunSaid + 1] = string.format("%s leads %.2f s, %d-round bursts", new, r.PredictionOffsetTime, r.TriggerCount)
                    elseif src:find("AAGun", 1, true) or src:find("CIWS", 1, true) then
                        local l = r.PredictionOffsetTime
                        if type(l) ~= "number" or l <= 0 then l = 0.8 end        -- (none of its own: the AA guns')
                        r.PredictionOffsetTime = l * (c.aa_lead_x or 1)
                        gunSaid[#gunSaid + 1] = string.format("%s leads %.2f s", new, r.PredictionOffsetTime)
                    end
                end)
                if sf and shipModule[key] then        -- the ship type's own turret module: farther, not lost in cloud
                    pcall(function() r.NpcAIModuleId = FName(shipModule[key]) end)
                    pcall(function() r.bEnableLostTargetInClouds = false end)
                end
                local what = ""
                pcall(function()                     -- a gun's rounds: a tighter spread (a weapon row without one stays)
                    local w = r.NpcWeaponId:ToString()
                    local wn = w .. "_SVA" .. (sf and ("_" .. key) or "")
                    local mc, missile = sf and sf.missile, false
                    if wpn and w ~= "None" and w ~= "" and cloneRow(wpn, w, wn, function(x)  -- (edit: a new row only)
                        pcall(function() x.MaxSpawnAngle = x.MaxSpawnAngle * c.spread_x end)
                        local homing = false
                        pcall(function() homing = x.bIsHoming == true end)
                        if mc and homing then        -- a homing missile: flies long enough to reach range_m
                            missile = true
                            pcall(function() x.LifeTime = math.max(x.LifeTime, mc.life_s) end)
                            pcall(function() x.AccelerationKmph = x.AccelerationKmph * mc.accel_x end)
                            pcall(function() x.SpeedMaxKmph = math.max(x.SpeedMaxKmph, mc.speed_max_kmph) end)
                            pcall(function() x.MaxRotationAngle = x.MaxRotationAngle * mc.turn_x end)
                            pcall(function() x.HomingReductionInCloud = 0 end)
                            pcall(function()
                                what = string.format(", missile %s: %.0f s at up to %.0f km/h (+%.0f km/h a second), turns %.0f",
                                    wn, x.LifeTime, x.SpeedMaxKmph, x.AccelerationKmph, x.MaxRotationAngle)
                            end)
                        end
                    end) then
                        r.NpcWeaponId = FName(wn)
                        -- a homing missile by its row, made now or before (code review of 2026-10-23: cloneRow skips
                        -- the edit for a row that's already there, and the range stayed the stock one)
                        if mc and not missile then
                            pcall(function() local _, wr = dtCall(wpn, "FindRow", wn); missile = wr ~= nil and wr.bIsHoming == true end)
                        end
                        if missile then pcall(function() r.CaptureDistance = mc.range_m end) end
                    end
                end)
                if sf then
                    pcall(function()
                        shipSaid[#shipSaid + 1] = string.format("%s (within %d m, arm %.2f s, lock %.2f s, %.2f s between, rest %.2f s%s)",
                            new, math.floor(r.CaptureDistance), r.ActivationTime, r.TriggeringTime, r.ShotIntervalTime,
                            r.RestingTime, what)
                    end)
                end
            end) and true or false
        end
        return made[new] and new or nil
    end
    local n = 0
    for _, row in ipairs(ROWS) do
        local _, have = dtCall(npc, "FindRow", row)
        if have == nil then
            local _, r = dtCall(mine, "FindRow", row)
            if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
        end
        if have ~= nil then
            n = n + 1
            for i = 0, 5 do
                pcall(function()
                    local id = have["NpcFCSId" .. i]:ToString()
                    if id ~= "None" and id ~= "" and not id:find("_SVA") then
                        local new = allyFcs(id, ROW_SHIP[row])
                        if new then have["NpcFCSId" .. i] = FName(new); boosted = boosted + 1 end
                    end
                end)
            end
            if row == ROWS[1] and SR.module then      -- MOONCHILD searches as far as the enemies do
                pcall(function() have.NpcAIModuleId = FName(SR.module) end)
            end
            if ROW_SHIP[row] and shipModule[ROW_SHIP[row]] then   -- a ship's hull and turrets: its own module
                pcall(function() have.NpcAIModuleId = FName(shipModule[ROW_SHIP[row]]) end)
            end
        else
            lost[#lost + 1] = row
        end
    end
    local names = 0
    if type(SV_SetText) == "function" then
        if SV_SetText(CFG.allies.aircraft.name_key, CFG.allies.aircraft.name) == 1 then names = names + 1 end
        for key, sh in pairs(CFG.allies.ships) do if SV_SetText("SV_Ship_" .. key, sh.name) == 1 then names = names + 1 end end
    end
    ALLY.ready = n == #ROWS
    if #shipSaid > 0 then log("allies: the ships' and the airfield's own fire control: " .. table.concat(shipSaid, ", ")) end
    if #gunSaid > 0 then log("allies: guns: " .. table.concat(gunSaid, ", ")) end
    log(string.format("allies: %d of %d rows in DT_NPC%s, %d weapons on their own fire control (x%.1f range, x%.1f times), %d names set",
        n, #ROWS, #lost > 0 and (" (missing: " .. table.concat(lost, ", ") .. ")") or "", boosted, c.range_x, c.time_x, names))
end

-- CFG.allies.ally_speakers: on while a run is on (`want`), back to the game's values after it.
function ALLY.speakerTick(want)
    local st = ALLY.spk or { on = false, orig = {} }
    ALLY.spk = st
    if st.on == want then return end
    st.on = want
    for _, sp in ipairs(CFG.allies.ally_speakers or {}) do
        local ok, err = pcall(function()
            local dt = loadObject(sp.table)
            if not dt then error("no " .. sp.table) end
            local _, r = dtCall(dt, "FindRow", sp.row)
            if r == nil then error("no row " .. sp.row) end
            local id = r.SpeakerID:ToString()
            if id ~= sp.id then error("row " .. sp.row .. " is " .. id) end
            if want then
                st.orig[sp.row] = { color = r.ColorType, process = r.ProcessID:ToString() }
                r.ColorType, r.ProcessID = 0, FName(sp.process)
                log(string.format("allies: speaker %s talks as an ally (was colour %s, %s)", sp.id,
                    tostring(st.orig[sp.row].color), st.orig[sp.row].process))
            elseif st.orig[sp.row] then
                local o = st.orig[sp.row]
                r.ColorType, r.ProcessID = o.color, FName(o.process)
                log(string.format("allies: speaker %s back to colour %s, %s", sp.id, tostring(o.color), o.process))
            end
        end)
        if not ok then log("allies: speaker " .. tostring(sp.id) .. ": " .. tostring(err)) end
    end
end

function ALLY.state()
    ALLY.run = ALLY.run or { up = {}, events = {}, hunted = {}, seen = {}, planes = {}, nextTakeoff = 0 }
    return ALLY.run
end

-- Of `units`: how many are bought (at sea, flying or waiting to take off), and a free one, or nil.
function ALLY.status(units)
    local R, up, free = ALLY.state(), 0, nil
    for _, u in ipairs(units) do
        if R.up[u] then up = up + 1
        elseif not free and nativeReady() and SV_UnitAlive(u) <= 0 then free = u end
    end
    return up, free
end

function ALLY.shipsAtSea()
    local out = {}
    for u, s in pairs(ALLY.state().up) do if s.kind == "ship" then out[#out + 1] = u end end
    table.sort(out)
    return out
end

-- A purchase (the shop takes the zollars when it succeeds): true and its message, or false and why not.
function ALLY.buy(role, unit, key, price)
    local R, t, now = ALLY.state(), CFG.allies.text, D and D.now or 0
    if role == "ally_ship" then
        local sh = CFG.allies.ships[key]
        spawningUnit = unit
        local r = SV_Spawn(unit)
        spawningUnit = nil
        log(string.format("allies: %s (%s): %s", sh.name, unit, r > 0 and "at sea" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
        if r <= 0 then return false, "COULD NOT SEND IT (" .. (SV_ERR[r] or tostring(r)) .. ")." end
        R.up[unit] = { kind = "ship", key = key, at = now, price = price }
        hudCallout(string.format(t.ship, sh.name), t.ship_sub)
        return true, sh.name .. " AT SEA"
    end
    R.up[unit] = { kind = "air", queued = true, at = now, price = price }
    log(string.format("allies: %s (%s) bought; it takes off once you're airborne", CFG.allies.aircraft.name, unit))
    return true, CFG.allies.aircraft.name .. " TAKES OFF ONCE YOU'RE AIRBORNE"
end

-- MOONCHILD's level for this round (CFG.allies.aircraft.scale): { rank, ai, hx (health multiplier), tier name }
function ALLY.level()
    local sc, round = CFG.allies.aircraft.scale or {}, math.max(1, D and D.round or 1)
    local t = CFG.tiers.enabled and CFG.tiers.list[TIER.index(round)] or {}
    return { rank = math.max(sc.rank_min or 1, math.min(5, (t.rank or 3) + (sc.rank_add or 0))),
             ai = math.max(sc.ai_level_min or 2, t.ai_level or 2),
             hx = math.min(sc.health_max_x or 1, (sc.health_x or 1) * (1 + (sc.health_per_round or 0) * (round - 1))),
             tier = t.name or "-" }
end

-- Each allied aircraft at this round's level: its rank, and its health raised by the growth since it was last set.
function ALLY.scale()
    local R = ALLY.state()
    if #R.planes == 0 then return end
    local L = ALLY.level()
    for i = #R.planes, 1, -1 do
        local p = R.planes[i]
        if not valid(p.obj) then table.remove(R.planes, i)
        elseif p.round ~= D.round then
            p.round = D.round
            pcall(function() p.obj.PilotRank = L.rank end)
            local was = p.hx or 1
            p.hx = L.hx
            local ok, h0, h1 = pcall(function()
                local h = p.obj.HealthInternal
                if L.hx > was and h > 0 then p.obj.HealthInternal = h * L.hx / was end
                return h, p.obj.HealthInternal
            end)
            log(string.format("allies: %s (%s) at round %d's level (%s): PilotRank %d, health x%.2f (%s -> %s)", p.name, p.unit,
                D.round, L.tier, L.rank, L.hx, ok and tostring(h0) or "?", ok and tostring(h1) or "?"))
        end
    end
end

-- Strike flight `bomber` (a normal round's, sent at allied ship unit `ship`): RE_SV_Strike<ship>_NN once its own
-- orders (the airfield's, from its appearance) are in.
function ALLY.strike(bomber, ship)
    local i = BOMBER_INDEX[bomber]
    if not i then return end
    local R = ALLY.state()
    R.events[#R.events + 1] = { at = D.now + 4, name = string.format("RE_SV_Strike%s_%02d", (ship:gsub("^SV_Unit_Ship", "")), i),
                                why = bomber .. " at " .. ship }
    if D.strikeSaid ~= D.round then
        D.strikeSaid = D.round
        hudCallout(CFG.allies.text.strike, CFG.allies.text.strike_sub)
    end
end

function ALLY.tick(now)
    if not (CFG.allies.enabled and D and nativeReady()) then return end
    local R, c, t = ALLY.state(), CFG.allies, CFG.allies.text
    for _, u in ipairs(c.aircraft.units) do          -- a bought flight: off the ground once you are, runway clear
        local s = R.up[u]
        if s and s.queued and now >= R.nextTakeoff and not playerOnAirfield() then
            if type(SV_SetLevel) == "function" then SV_SetLevel(u, ALLY.level().ai * 100) end
            spawningUnit = u
            local r = SV_Spawn(u)
            spawningUnit = nil
            if r > 0 then
                s.queued, s.at, R.nextTakeoff = nil, now, now + c.aircraft.takeoff_gap_s
                hudCallout(string.format(t.takeoff, c.aircraft.name), t.takeoff_sub)
                log(string.format("allies: %s (%s) taxiing out: %d aircraft", c.aircraft.name, u, r))
            else
                s.tries, R.nextTakeoff = (s.tries or 0) + 1, now + 5
                log(string.format("allies: %s (%s) not spawned (%s)", c.aircraft.name, u, SV_ERR[r] or tostring(r)))
                if s.tries >= 3 then                 -- never came: the zollars back
                    R.up[u] = nil
                    RUN.credits, RUN.spent, RUN.dirty = RUN.credits + (s.price or 0), RUN.spent - (s.price or 0), true
                    log(string.format("allies: %s (%s) couldn't take off; %d zollars back", c.aircraft.name, u, s.price or 0))
                end
            end
        end
    end
    if now >= (R.checkAt or 0) then                  -- every 2 s: losses, scaling, and the enemies' orders on MOONCHILD
        R.checkAt = now + 2
        ALLY.scale()
        local f, airborne = svFlags() or {}, 0
        for u, s in pairs(R.up) do
            if not s.queued then
                local n = SV_UnitAlive(u)
                if n <= 0 and now - s.at > 5 then
                    R.up[u], RUN.dirty = nil, true
                    local name = s.kind == "air" and c.aircraft.name or c.ships[s.key].name
                    hudCallout(string.format(s.kind == "air" and t.air_lost or t.sunk, name), t.lost_sub)
                    log(string.format("allies: %s (%s) lost %.0f s after it %s", name, u, now - s.at,
                        s.kind == "air" and "spawned" or "sailed"))
                elseif s.kind == "air" and n > 0 then
                    airborne = airborne + math.min(n, f["SV_AllyAir" .. u:sub(-1)] or 0)
                end
            end
        end
        if airborne ~= (R.airborne or 0) then log(string.format("allies: %d %s aircraft airborne", airborne, c.aircraft.name)) end
        R.airborne = airborne
        -- an enemy fighter flight that's had its own orders (4 s up) while MOONCHILD flies: hunt_share of them prefer it
        for u in pairs(R.seen) do if not D.up[u] then R.seen[u], R.hunted[u] = nil, nil end end
        for u in pairs(D.up) do
            local fn, fk = u:match("^ERA_Unit_(%d+)_Dep_Air(%d)$")      -- (tools/survival_events.py POOL order)
            if fn then
                R.seen[u] = R.seen[u] or now
                if airborne > 0 and not R.hunted[u] and now - R.seen[u] >= 4 then
                    R.hunted[u] = true
                    if math.random() < c.hunt_share then
                        R.events[#R.events + 1] = { at = now, why = u .. " goes for " .. c.aircraft.name,
                            name = string.format("RE_SV_Hunt_%02d", (tonumber(fn) - 1) * 3 + tonumber(fk) + 1) }
                    end
                end
            end
        end
    end
    for i = #R.events, 1, -1 do
        local e = R.events[i]
        if now >= e.at then
            table.remove(R.events, i)
            local r = type(SV_Event) == "function" and SV_Event(e.name) or -5
            log(string.format("allies: %s (%s) %s", e.name, e.why, r == 1 and "fired" or ("not fired: " .. (SV_ERR[r] or tostring(r)))))
        end
    end
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
-- The slot's name and count TextBlocks. Found by their full names under the panel (<panel>.WidgetTree_N.AmmoText<slot>.
-- WidgetTree_N.<text>): GetWidgetFromName gave nothing on the live panel (test of 2026-10-23: every slot 'nil'). The
-- count is the text that reads as a number (or "---", an empty special slot), the name the other; the count widget is
-- kept once found, as Survival's own number then shows in it.
local function slotTexts(panel, slot)
    SH.slotCache = SH.slotCache or {}
    local key = addrOf(panel) or nameOf(panel)   -- (the address read back nil on the live panel: test of 2026-10-23)
    local c = SH.slotCache[key]
    if not c or (not c.found and os.clock() - c.at > 2) then   -- (none yet: looked for again every 2 s, not every call)
        c = { slots = {}, at = os.clock() }
        local base = nameOf(panel):match("^%S+%s+(.+)$") or nameOf(panel)
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            local n = nameOf(t)
            local at = n:find(base, 1, true)
            local sl, leaf = nil, nil         -- (not `at and s:match(...)`: `and` keeps only the first capture)
            if at then sl, leaf = n:sub(at + #base):match("^%.WidgetTree[_%d]*%.(AmmoText%a+)%.WidgetTree[_%d]*%.([%w_]+)$") end
            if sl then c.slots[sl] = c.slots[sl] or { all = {} }; c.slots[sl].all[leaf] = t; c.found = true end
        end
        SH.slotCache[key] = c
    end
    local e = c.slots[slot]
    if not e then return nil, nil end
    if not (e.count and valid(e.count)) then
        for _, t in pairs(e.all) do
            local v = widgetText(t)
            if v and (v:match("^%s*%d+%s*$") or v:match("^%s*%-+%s*$")) then e.count = t
            elseif v and v:match("%a") then e.name = t end
        end
    end
    return e.name, e.count
end

local function hangarAmmoTick(tick)
    if not (CFG.ammo.enabled and A and A.applied and A.caps and A.max) or tick % 2 ~= 1 then return end
    if not playerOnAirfield() then SH.panels, SH.slotCache = nil, nil; return end   -- the landing menu only exists down there
    -- every 2 s, all of them: the STORE pages show their own panel, made when the page opens, while the landing
    -- page's stays valid (report of 2026-10-23: the STORE still showed the stock counts)
    if tick % 8 == 1 or not SH.panels then
        SH.panels = {}
        for _, w in ipairs(FindAllOf("WBP_Menu_IngameHangar_WeaponDetail_002_C") or {}) do
            if liveWidget(w) then SH.panels[#SH.panels + 1] = w end
        end
    end
    for _, panel in ipairs(SH.panels or {}) do
        local pkey = addrOf(panel) or nameOf(panel)
        SH.panelSaid = SH.panelSaid or {}
        if liveWidget(panel) and not SH.panelSaid[pkey] then
            SH.panelSaid[pkey] = true                -- once a panel: what it holds (test of 2026-10-22: no rewrite seen)
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
                    if not (now and now:match("^%s*%d+%s*$")) then return end              -- an empty special slot shows "---"
                    local want = tostring(math.min(cap, A.max[kind] or cap))              -- what you take off with
                    if now ~= want then
                        t:SetText(toText(want))
                        SH.ammoSaid = SH.ammoSaid or {}
                        if not SH.ammoSaid[pkey] then SH.ammoSaid[pkey] = true; log("shop: ammo panel " .. (nameOf(panel):match("([%w_]+)$") or "?") .. " shows the caps (" .. now .. " -> " .. want .. ")") end
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
    if p.unit and p.unit:find("^SV_Unit_Ladon") then return end   -- (a Ladon pays its own reward: SPC.ladonTick)
    local model = p.name:match("BP_OP%d+_(%w+)_") or "?"
    local kind = "fighter"
    if p.unit and BOMBER_UNIT[p.unit] then
        kind = "bomber"
        for _, h in ipairs(CFG.airfield.bombers.heavy) do if (h:match("^(%w+)_") or h) == model then kind = "heavy" end end
    elseif p.unit == false then
        kind = CFG.credits.models[model] or "fighter"
    end
    -- its skill tier's pay (the tier it was given, else the round's own)
    local list, ti = CFG.tiers.list, nil
    for i, t in ipairs(list) do if t == p.tier then ti = i end end
    ti = ti or (D and D.round and TIER.index(D.round))
    local pay, x = TIER.pay((CFG.credits[kind] or 0) * TIER.specialX(), ti)
    addCredits(pay, string.format("%s down (%s%s%s)", model, kind, ti and (", " .. list[ti].name .. " x" .. x) or "",
        TIER.specialX() ~= 1 and (", special x" .. TIER.specialX()) or ""))
    LB.stat("air", 1)
    if p.unit and D and D.aceSquad and D.aceSquad[p.unit] then LB.stat("aces", 1) end
end

local function probeTick(tick)
    local function timed(name, fn, ...)            -- pcall(fn, ...), its time added to the run's tick timer (D.perf)
        local t0 = os.clock()
        local ok, err = pcall(fn, ...)
        local pf = D and D.perf
        if pf then
            local e = pf.parts[name] or { n = 0, sum = 0, max = 0 }
            pf.parts[name] = e
            local dt = (os.clock() - t0) * 1000
            e.n, e.sum, e.max = e.n + 1, e.sum + dt, math.max(e.max, dt)
        end
        return ok, err
    end
    if levelTick == -1 then
        levelTick = tick
        log("level loaded: PL_SurvivalMode")
        if type(SV_Invert) == "function" then SV_Invert(0, 0, 0, 0) end   -- (the Anomaly's field)
        ANOM.on, ANOM.pawn, ANOM.fx = false, nil, {}
        SH.store, SH.storeTries, SH.added, SH.decor = nil, 0, false, {}      -- (the store: checked again in this level)
        do                                         -- the Anomaly's sounds (Mission 23's) and portal systems, loaded and kept
            local an, got, want = CFG.specials.anomaly, 0, 0
            local function keep(path)
                local n = path:match("[^/]+$")
                want = want + 1
                local o = loadObject(path .. "." .. n)
                if o then pin(o, n); got = got + 1 else log("special: anomaly asset not loaded: " .. path) end
            end
            for _, n in ipairs(an.down_sound_names) do keep(an.down_sounds .. n) end
            for _, n in ipairs(an.hum_sound_names) do keep(an.hum_sounds .. n) end
            for _, part in ipairs({ an.portal.open, an.portal.burst, { an.portal.strike, an.portal.aura } }) do
                for _, p in ipairs(part) do keep(p) end
            end
            log(string.format("special: anomaly sounds and portal systems loaded: %d of %d", got, want))
        end
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
        RUN = { credits = CFG.credits.start, earned = 0, spent = 0, bought = {}, msg = {}, dirty = true,
                -- (the leaderboard's run clock from the level's start: made later, a run shot down at once read 0:00:00)
                stats = { started = os.time(), air = 0, ground = 0, aces = 0, allies = 0, af_down = 0, captured = 0,
                          specials = {} } }
        ALLY.run = nil                             -- (a new level: no allies up)
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
        local okAc, errAc = pcall(SPC.alicornSetup)
        if not okAc then log("special: Alicorn setup error " .. tostring(errAc)); SPC.alicornDone = true end
        local okL, errL = pcall(SPC.ladonSetup)
        if not okL then log("special: Ladon setup error " .. tostring(errL)); SPC.ladonDone = true end
        local okSp, errSp = pcall(specialSetup)
        if not okSp then log("special: setup error " .. tostring(errSp)); SPS.done = true end
        local okAs, errAs = pcall(ALLY.setup)
        if not okAs then log("allies: setup error " .. tostring(errAs)); ALLY.setupDone = true end
        local okP, errP = pcall(probeSetup)
        if not okP then log("probe: setup error " .. tostring(errP)); PR.tries = 20 end
        local okM, errM = pcall(SHOP.menuSetup)
        if not okM then log("shop: store setup error " .. tostring(errM)); SH.menuDone = true end
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
                for _, k in ipairs({ "SV_Kills", "SV_AirHits", "SV_Beat" }) do      -- (SV_Beat: our heartbeat)
                    local v = f[k]
                    if v then
                        if (D.maxFlags[k] or 0) > 0 and v < D.maxFlags[k] then
                            log(string.format("mission restarted in round %d (%s %d -> %d): the run starts over", D.round, k, D.maxFlags[k], v))
                            levelTick = -1         -- the level-load reset below, on the next tick
                            local okL, errL = pcall(LB.finish, "restart")          -- (its error mustn't stop the reset)
                            if not okL then log("leaderboard: error " .. tostring(errL)) end
                        end
                        D.maxFlags[k] = math.max(D.maxFlags[k] or 0, v)
                    end
                end
            end
        end
        if (D.pcLost or 0) >= 8 then
            log(string.format("run over: left Survival's level in round %d with %d zollars", D.round, RUN.credits))
            local okL, errL = pcall(LB.finish, "left")          -- (its error mustn't stop the reset)
            if not okL then log("leaderboard: error " .. tostring(errL)) end
            if type(SV_MusicHold) == "function" then SV_MusicHold(0) end   -- (never left held)
            D, A, levelTick, survivalPC, callouts = nil, nil, nil, nil, {}
            planes, pending, lastAlive, SH.panels, SHUTTLE.obj = {}, {}, nil, nil, nil
            ALLY.run = nil
            HIT.reset()
        end
    end
    if D then
        local now, paused = roundClock(tick)
        if now then
            local okR, errR = timed("rounds", roundsTick, now)
            if not okR then log("rounds: error " .. tostring(errR)) end
            local okH, errH = timed("hud", hudTick, now, paused, survivalPC)
            if not okH then hudLog("tickerr", "error " .. tostring(errH)) end
            local okM, errM = timed("music", musicTick, tick, now, paused)
            if not okM then log("music: error " .. tostring(errM)) end
            -- the landing store plays its own supply music without pausing the BGM channel, so the Music Player's track
            -- clock ran out there (user, 2026-10-24: "music skipped"): held while it's open (paused, down at the airfield)
            if type(SV_MusicHold) == "function" then
                local hold = (paused and playerOnAirfield()) and 1 or 0
                if hold ~= D.musicHold then
                    D.musicHold = hold
                    SV_MusicHold(hold)
                    log("music: track clock " .. (hold == 1 and "held (landing store)" or "running"))
                end
            end
            local okF, errF = timed("airfield", airfieldTick, tick)
            if not okF then log("airfield: error " .. tostring(errF)) end
            local okB, errB = pcall(bombTick, tick)
            if not okB then log("bombers: error " .. tostring(errB)) end
            local okS, errS = timed("shop", shopTick, tick)
            if not okS then log("shop: error " .. tostring(errS)) end
            local okAl, errAl = timed("allies", ALLY.tick, now)
            if not okAl then log("allies: error " .. tostring(errAl)) end
            local okI, errI = timed("icons", SHOP.decorTick, tick)
            if not okI and not SH.decorErr then SH.decorErr = true; log("shop: row icons error " .. tostring(errI)) end
            local okA2, errA2 = timed("ammo panel", hangarAmmoTick, tick)
            if not okA2 then log("shop: ammo panel error " .. tostring(errA2)) end
        end
        if tick % 4 == 1 then pcall(LB.deathCheck, survivalPC) end      -- shot down: the run's over
        if now and valid(survivalPC) then                               -- what hits the player (section "hits")
            local okHt, errHt = pcall(HIT.tick, survivalPC, now)
            if not okHt and not D.hitErr then D.hitErr = true; log("hits: error " .. tostring(errHt)) end
        end
        if tick % 40 == 9 and type(SV_Event) == "function" then pcall(SV_Event, "RE_SV_Beat") end   -- (restart detection)
        local okMv, errMv = pcall(ACE.movesTick, now, D)                      -- top-tier reversals (CFG.aces.flight)
        if not okMv and not D.movesErr then D.movesErr = true; log("aces: moves error " .. tostring(errMv)) end
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
    if not levelTick then return end                                -- the rest in Survival only
    -- Each aircraft's last position, so a loss shows whether it was shot down near the player or crashed far away,
    -- and every 10 s the nearest enemy's distance: the check that they come for the player. Each aircraft every 2 s,
    -- an eighth of them each tick (all of them on one tick every 2 s was a hitch with 60 aircraft up: user,
    -- 2026-10-23, "the custom HUD ... seems a bit laggy").
    local slot, you = tick % 8, nil
    for i, p in ipairs(planes) do
        if not p.down and i % 8 == slot then
            if you == nil then you = playerLocation() or false end
            local up = valid(p.obj)
            if up then
                local ok, h = pcall(function() return p.obj.HealthInternal end)
                if ok and type(h) == "number" and h <= 0 then up = false end
            end
            if up then
                pcall(function() local v = p.obj:K2_GetActorLocation(); p.at = { X = v.X, Y = v.Y, Z = v.Z } end)
                local ft = D and p.unit and D.flightTier and D.flightTier[p.unit]
                pcall(planeUnit, p)
                local own = p.unit and p.unit:find("^SV_Unit_Ladon")              -- (the Ladons: their own tuning)
                if not own then pcall(enemyTier, p, D and D.round, ft); pcall(enemyManeuvers, p, D and D.round) end
                local an = CFG.specials.anomaly
                local tierFor = (p.unit == an.unit) and { provoke_cone_deg = an.provoke_cone_deg,
                    provoke_time_s = 1.0 / math.max(1, an.aggression or 1), surround_m = an.surround_m }
                    or (ft and CFG.tiers.list[ft])
                if not own then pcall(enemySpike, p, D and D.round, tierFor) end
                pcall(probeTrack, p); pcall(ACE.hunt, p); pcall(aiWatch, p, you or nil)
                p.dist = (p.at and you) and km(p.at, you) or nil
            else
                p.down = true
                log("round probe: " .. p.name .. " down" .. (p.at and string.format(", last seen %.1f km up%s",
                    p.at.Z / 100000, you and string.format(", %.1f km from you", km(p.at, you)) or "") or ""))
                pcall(probeKill, p, you or nil)
                pcall(creditKill, p)
            end
        end
    end
    if slot ~= 0 then return end                                    -- every 2 s: the summaries
    local fl, flagged = flagLine()
    if fl and fl ~= lastFlags then log("round probe: flags " .. fl); lastFlags = fl end
    local alive, nearest = 0, nil
    for _, p in ipairs(planes) do
        if not p.down then
            alive = alive + 1
            if p.dist and (not nearest or p.dist < nearest) then nearest = p.dist end
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
        local t0 = os.clock()
        local ok, err = pcall(probeTick, tick)
        if not ok then log("round probe: error " .. tostring(err)) end
        if D then                                   -- (report of 2026-10-23: "the custom HUD ... seems a bit laggy")
            local pf = D.perf or { n = 0, sum = 0, max = 0, parts = {}, at = tick }
            D.perf = pf
            local dt = (os.clock() - t0) * 1000
            pf.n, pf.sum, pf.max = pf.n + 1, pf.sum + dt, math.max(pf.max, dt)
            if tick - pf.at >= 240 then
                local parts = {}
                for k, v in pairs(pf.parts) do parts[#parts + 1] = { k, v } end
                table.sort(parts, function(a, b) return a[2].max > b[2].max end)
                local top = {}
                for i = 1, math.min(4, #parts) do
                    top[#top + 1] = string.format("%s %.1f/%.1f", parts[i][1], parts[i][2].sum / math.max(1, parts[i][2].n), parts[i][2].max)
                end
                log(string.format("perf: tick avg %.1f ms, worst %.1f ms over %d ticks; parts avg/worst ms: %s", pf.sum / pf.n,
                    pf.max, pf.n, table.concat(top, ", ")))
                D.perf = nil
            end
        end
        if tick % 4 == 3 then pcall(ALLY.speakerTick, D ~= nil) end        -- the run's ally speakers, on and off
        if tick % 4 == 1 then pcall(LB.poll) end                         -- the leaderboard sends' answers
        if tick % 20 == 7 then pcall(LB.queueTick) end                   -- runs waiting to be sent
        queued = false
    end)
    return false
end)

---------------------------------------------------------------------------------------------------- dev keys
-- TEST ONLY BEGIN (tools/package_test.sh strips every such block from release / test zips: user, 2026-10-23, "remove
-- all the special codes for accessing levels and cash")
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
-- TEST ONLY END

if type(RegisterKeyBind) == "function" and Key then
    local mods = (ModifierKey and ModifierKey.CONTROL) and { ModifierKey.CONTROL } or {}
    -- TEST ONLY BEGIN
    -- Ctrl+F8 on the main menu opens PL_SurvivalMode directly
    if Key.F8 then
        pcall(RegisterKeyBind, Key.F8, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(openSurvival)
                if not ok then log("launch: error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+F9 in a run gives 5000 zollars
    if Key.F9 then
        pcall(RegisterKeyBind, Key.F9, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    if not D then log("test: Ctrl+F9 outside a Survival run"); return end
                    addCredits(5000, "test key Ctrl+F9")
                    RUN.dirty = true
                    hudCallout("TEST: +5000 ZOLLARS", string.format("NOW %d", RUN.credits))
                end)
                if not ok then log("test: Ctrl+F9 error " .. tostring(err)) end
            end)
        end)
    end
    -- Ctrl+1 .. Ctrl+5 in a run: the next round is that special (in the break: it starts in 3 s), for testing
    -- (user, 2026-10-23: "build special keys for me to test each special round"; were Ctrl+F11 / Ctrl+F12)
    ;(function()                   -- (its own function: the main chunk's 200-local limit)
    local TEST_SPECIALS = { { "ONE", "shuttle", "COMONA DEFENSE" }, { "TWO", "anomaly", "THE ANOMALY" },
                            { "THREE", "amphibious", "AMPHIBIOUS ASSAULT" }, { "FOUR", "ladon", "THE LADONS" },
                            { "FIVE", "alicorn", "THE ALICORN" }, { "SEVEN", "glitch", "AB.L..IN" },
                            { "EIGHT", "valka", "VALKA" } }
    for i, ts in ipairs(TEST_SPECIALS) do
        local key, kind, label = Key[ts[1]], ts[2], ts[3]
        if key then
            pcall(RegisterKeyBind, key, mods, function()
                ExecuteInGameThread(function()
                    local ok, err = pcall(function()
                        if not D or not D.now then log("test: Ctrl+" .. ts[1] .. " outside a Survival run"); return end
                        D.forceSpecial = kind
                        local soon = D.state == "wait"
                        if soon then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
                        hudCallout("TEST: " .. label, soon and "STARTING NOW" or "NEXT ROUND")
                        log(string.format("test: Ctrl+%s, round %d is %s (%s)", ts[1], D.round + 1, kind,
                            soon and "starting in 3 s" or "after this round"))
                    end)
                    if not ok then log("test: Ctrl+" .. ts[1] .. " error " .. tostring(err)) end
                end)
            end)
        end
    end
    end)()
    -- Ctrl+6 in a run: a flight at the top level now (the last skill tier's squadron, its ace leading, on the top
    -- fire control), whatever the round (user, 2026-10-23: "a special key to have one of the Aircraft Spawn that is
    -- the MAX LEVEL"); it counts in the round like any flight
    if Key.SIX then
        pcall(RegisterKeyBind, Key.SIX, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function()
                    if not D or not D.now or not nativeReady() then log("test: Ctrl+6 outside a Survival run"); return end
                    local unit
                    for _, u in ipairs(CFG.pool) do
                        if not unit and not D.up[u] and not PROBE_OF[u] and flightSize(u) == 2 and SV_UnitAlive(u) <= 0 then unit = u end
                    end
                    if not unit then hudCallout("TEST: NO FREE FLIGHT", "TRY AGAIN WHEN SOME ARE DOWN"); return end
                    local r = spawnFlight(unit, true)
                    local tn = (CFG.tiers.list[#CFG.tiers.list] or {}).name or "?"
                    hudCallout("TEST: " .. tn:upper() .. " FLIGHT", r > 0 and "INBOUND" or "COULD NOT SPAWN")
                    log(string.format("test: Ctrl+6, a %s flight (%s): %s", tn, unit, tostring(r)))
                end)
                if not ok then log("test: Ctrl+6 error " .. tostring(err)) end
            end)
        end)
    end
    -- TEST ONLY END
    if Key.F7 then                 -- Ctrl+F7: write the live HUD's layout to hud_dump.txt (any screen)
        pcall(RegisterKeyBind, Key.F7, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(hudDump, "Ctrl+F7")
                if not ok then log("hud dump: error " .. tostring(err)) end
            end)
        end)
    end
end

log("loaded, version " .. VERSION)
