-- AC8 Survival Mode - runtime (UE4SS Lua half; the native half is dlls\main.dll)
-- Milestone 1:
--   * adds Survival's mission row and main-menu row to the game's tables at run time, copied from Survival's own
--     tables (DT_SV_MissionRows / DT_SV_MenuRows), so no stock or other-mod table file is overridden
--   * the main-menu entry opens the game's difficulty page; dlls\main.dll then starts Survival's mission
--   * dev shortcut: Ctrl+F8 on the main menu opens PL_SurvivalMode directly

local VERSION = "0.3.2"
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
    local ok, err = pcall(function()
        local arr = gi.ReferencedObjects
        arr[#arr + 1] = o
    end)
    pinned[a] = ok
    log("rows: " .. what .. (ok and " pinned (kept loaded)" or (" could not be pinned (" .. tostring(err) .. ")")))
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

-- Runs on the game thread; the loop only schedules it (one at a time). It keeps running: the menu table can be
-- reloaded every time the main menu is built.
local stopped, queued = false, false
LoopAsync(250, function()
    if stopped then return true end
    if queued then return false end
    queued = true
    ExecuteInGameThread(function()
        local ok, r = pcall(watchRows)
        if not ok then log("rows: error " .. tostring(r)) end
        if ok and r == false then stopped = true end
        queued = false
    end)
    return false
end)

---------------------------------------------------------------------------------------------------- menu diagnostics
-- Logs every new copy of the menu table and, shortly after a command list is built, the entries it shows.
pcall(NotifyOnNewObject, "/Script/Engine.DataTable", function(o)
    local n = nameOf(o)
    if n:find("DT_LiveMenuMainTopCommands", 1, true) then log("menu: table object created " .. n .. " at " .. hex(addrOf(o))) end
end)

local lastTableLine = nil          -- the table's rows are logged again only when they change

local function dumpList(w)
    if not valid(w) then return end
    local items = {}
    local okA, err = pcall(function()
        local cds = w.CommandDatas
        for i = 1, #cds do
            local cd = cds[i]
            local okT, txt = pcall(function() return cd.TextWidget:GetText():ToString() end)
            items[#items + 1] = okT and txt or nameOf(cd.CommandWidget)
        end
    end)
    -- only lists that show something (empty ones are widget templates; test 5 had hundreds of those lines)
    if #items == 0 and okA then return end
    log("menu: list " .. nameOf(w) .. " shows " .. #items .. " entries: " .. table.concat(items, " | ") ..
        (okA and "" or (" (read error: " .. tostring(err) .. ")")))
    local game = StaticFindObject(TABLES[2].game)
    if valid(game) then
        local line = "menu: the table at " .. hex(addrOf(game)) .. " has rows: " .. rowNames(game)
        if line ~= lastTableLine then log(line); lastTableLine = line end
    end
end

pcall(NotifyOnNewObject, "/Script/Live.LiveMenuCommandListWidget", function(w)
    if type(ExecuteWithDelay) ~= "function" then return end
    ExecuteWithDelay(1500, function()
        ExecuteInGameThread(function() pcall(dumpList, w) end)
    end)
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

pcall(NotifyOnNewObject, "/Script/Engine.World", function(w)
    local n = nameOf(w)
    if n:find("PL_SurvivalMode", 1, true) then log("level loaded: " .. n) end
end)

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
