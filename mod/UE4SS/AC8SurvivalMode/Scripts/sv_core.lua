-- sv_core.lua: shared helpers: logging, objects, the menu rows and tables, Survival's flags.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).
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

LEVEL   = "/Game/Mods/SurvivalMode/Maps/PL_SurvivalMode"
TAG     = "[AC8SurvivalMode] "
local ROW     = "SurvivalMode"
local COOP_ROWS = { "SurvivalCoopHost", "SurvivalCoopJoin" }   -- SURVIVAL CO-OP: HOST / JOIN (only when CFG.coop.enabled)

-- { our table, the game's table, the row ours goes just above (SURVIVAL MODE sits above QUIT GAME) }
local TABLES = {
    { mine = "/Game/Mods/SurvivalMode/Data/DT_SV_MissionRows.DT_SV_MissionRows",
      game = "/Game/Datatables/Information/DT_LiveMissionTable.DT_LiveMissionTable" },
    { mine = "/Game/Mods/SurvivalMode/Data/DT_SV_MenuRows.DT_SV_MenuRows",
      game = "/Game/Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands.DT_LiveMenuMainTopCommands",
      above = "QuitGame", coop = true },
}
-- The rows that go into a table: ours, and SURVIVAL CO-OP in the menu table when co-op is on (user, 2026-10-26: "a
-- cleaner way for players to join"; CFG is read when the rows go in, after sv_config has loaded)
local function rowsOf(t)
    if t.coop and CFG and CFG.coop and CFG.coop.enabled then return { ROW, COOP_ROWS[1], COOP_ROWS[2] } end
    return { ROW }
end

-- Every line also goes to AC8SurvivalMode\AC8SurvivalMode_lua.log, written through at once: UE4SS.log loses its last
-- lines when the game crashes (a friend's test of 2026-10-22: it stopped 40 s before the crash on sortie).
-- main.lua's folder (Scripts\): the mod's files are found from it (..\config\, ..\AC8SurvivalMode_lua.log, ai\)
SCRIPT_DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""

log = nil
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

function valid(o)
    local ok, v = pcall(function() return o ~= nil and o:IsValid() end)
    return ok and v
end

function nameOf(o)
    local ok, s = pcall(function() return o:GetFullName() end)
    return ok and s or "?"
end

-- A widget the game made at run time (they live under /Engine/Transient). FindAllOf on a widget blueprint's class
-- also returns the copies stored inside other blueprints' WidgetTrees ("..._C:WidgetTree.X"), which are never on
-- screen (test of 2026-10-22: the landing menu's ammo panel and the TIME row were first found that way).
function liveWidget(w)
    return valid(w) and nameOf(w):find("/Engine/Transient", 1, true) ~= nil
end

-- calls a data table method; false when this UE4SS build cannot do it
function dtCall(dt, method, ...)
    local args = { ... }
    local ok, r = pcall(function() return dt[method](dt, table.unpack(args)) end)
    if ok then return true, r end
    return false, r
end

-- Loads a package of ours by object path ("/Game/...Pkg.Obj"). UE4SS's LoadAsset only finds assets listed in the
-- game's asset registry, which never lists a mod's new packages, so the engine's own soft-reference loader is used:
-- MakeSoftObjectPath -> Conv_SoftObjPathToSoftObjRef -> LoadAsset_Blocking (game thread only).
-- Returns the object, or nil and the reason.
function loadObject(path)
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
local function placeAbove(dt, last, ROW)                  -- (ROW: the row to place; this one alone shadows the file's)
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

function addrOf(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

local function hex(a) return a and string.format("%X", a) or "?" end

-- A DataTable's row names in table order, as strings (nil when they can't be read). GetRowNames may hand back FNames
-- or plain strings: a plain string has no ToString (test of 2026-10-23: the STORE's index check read nothing).
function rowList(dt)
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

function rowNames(dt)
    local l = rowList(dt)
    return l and table.concat(l, ", ") or "?"
end

function gameInstance()
    for _, cls in ipairs({ "BP_LiveGameInstance_C", "LiveGameInstance", "GameInstance" }) do
        local gi = FindFirstOf(cls)
        if valid(gi) then return gi end
    end
    return nil
end

-- Keeps `o` loaded: GameInstance.ReferencedObjects is the engine's list for exactly that.
local pinned = {}
function pin(o, what)
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
containerState = nil         -- nil = not known yet, true / false once known
local missingTries = 0
local lastLoadError = nil

function containerMounted()
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

-- Our source row `row` for a table (from DT_SV_*), or nil + the reason.
local function sourceRow(t, row)
    local mine, why = loadObject(t.mine)
    if not mine then return nil, why end
    pin(mine, nameOf(mine))
    local okR, r = dtCall(mine, "FindRow", row)
    if r ~= nil then return r end
    return nil, "loaded " .. nameOf(mine) .. ", but FindRow('" .. row .. "') gave " ..
                (okR and "nothing" or tostring(r)) .. "; rows: " .. rowNames(mine)
end

local seen = {}                    -- per table: address of the table object last seen ("missing" if it can't load)
ready = {}                   -- per table: all its rows are in

-- One of a table's rows into the game's copy: "in" (it was), "added", "wait" (try again later) or "stop" (give up)
local function putRow(t, game, row, wasReady)
    local okF, have = dtCall(game, "FindRow", row)
    if not okF then
        log("rows: this UE4SS build cannot read data tables (" .. tostring(have) .. "); the menu is left as it is")
        return "stop"
    end
    if have ~= nil then
        if not wasReady then
            local placed = t.above and placeAbove(game, t.above, row)
            log("rows: '" .. row .. "' is in " .. nameOf(game) ..
                (t.above and (placed and (" (above " .. t.above .. ")") or (" (could not place it above " .. t.above .. ")")) or ""))
        end
        return "in"
    end
    local src, why = sourceRow(t, row)
    if src == nil then
        if row ~= ROW then log("rows: '" .. row .. "' is not in this build's tables (" .. tostring(why) .. ")"); return "in" end
        lastLoadError = why
        missingTries = missingTries + 1
        if missingTries >= MISSING_TRIES then containerMissing(); return "stop" end
        return "wait"
    end
    containerState = true
    local okA, err = dtCall(game, "AddRow", row, src)
    local _, now = dtCall(game, "FindRow", row)
    if not (okA and now ~= nil) then
        log("rows: could not add '" .. row .. "' to " .. t.game .. " (" .. tostring(err) .. ")")
        return "stop"
    end
    local placed = t.above and placeAbove(game, t.above, row)
    log("rows: added '" .. row .. "' to " .. nameOf(game) ..
        (t.above and (placed and (" (above " .. t.above .. ")") or (" (could not place it above " .. t.above .. ")")) or ""))
    log("rows: " .. nameOf(game) .. " now has: " .. rowNames(game))
    return "added"
end

-- One pass over both tables; returns false to stop watching for good.
function watchRows()
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
        local wasReady = ready[i]
        for _, row in ipairs(rowsOf(t)) do                 -- (SURVIVAL MODE first, then the co-op ones below it)
            local r = putRow(t, game, row, wasReady)
            if r == "stop" then return false end
            if r == "wait" then return true end
        end
        if t.above and not wasReady then                   -- placing one row moves `above` too: all of them above it
            for _ = 1, 3 do
                local p, all = rowOrder(game), true
                for _, row in ipairs(rowsOf(t)) do
                    if not (p[row] and p[t.above] and p[row] < p[t.above]) then all = false; placeAbove(game, t.above, row) end
                end
                if all then break end
            end
        end
        ready[i] = true
        containerState = true
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
infoMapsTick = nil
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
planes = {}                  -- created AI aircraft in this level: { obj, name }
pending = {}                 -- AI aircraft just created, logged on a later tick (position is set by then)
AIRFIELD = { X = 1609639.0, Y = -436414.0 }   -- Comona Airport runway (cm), the spawn anchor
lastAlive, lastFlags = nil, nil

function inSurvival(o) return nameOf(o):find("PL_SurvivalMode", 1, true) ~= nil end

-- Callbacks only record: all logging runs in the one game-thread tick below. A plane made during an SV_Spawn call is
-- tagged with the flight being spawned (spawningUnit, set around the call): GetUnitName() reads back empty (test of
-- 2026-10-22), and the world data's object names don't follow their flights' names.
spawningUnit = nil
pcall(NotifyOnNewObject, "/Script/Live.LiveAIPlane", function(o) pending[#pending + 1] = { obj = o, age = 0, unit = spawningUnit } end)

-- Comona Defense's shuttle (special rounds): its actor, for its health on the HUD. It may come as a LiveAIPlane
-- (OP0057_sstb); it's then kept out of `planes`, so it never counts, tiers or pays as an enemy.
SHUTTLE = { obj = nil }
shuttleHealth = nil            -- (section "special rounds"; the HUD shows it)
-- The STORE's allies (section "allies"): its functions, the run's state (ALLY.run) and which units are allies.
ALLY = { unit = {} }
-- The Anomaly (section "special rounds"): its field's state, for the HUD and the level reset.
ANOM = { on = false }
-- The amphibious assault (section "amphibious assault"): its functions; its run state is RUN.amph / RUN.captured.
AMPH = {}
-- The Ladons and later specials (section "ladon"): their functions; their state is in D.special.
SPC = {}
-- The leaderboard (section "leaderboard"): the run's stats (RUN.stats), its end, the prompt and sending.
LB = { queue = {}, jobs = {}, show = nil }
-- its camera settings, in tools/survival_events.py ANOMALY_CAMERAS order (RE_SV_AnomalyCam_A, _B, ...)
ANOMALY_CAMERAS = { "LookAt_Event_Camera", "LookAt_Event_Camera_ms08-01", "LookAt_Event_Camera_ms04-01",
                          "LookAt_Event_Camera_ms23-01", "LookAt_Event_Camera_ms22-01" }

function logPlane(o, unit)
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
    if unit and SPC.alicornPooled and SPC.alicornPooled(o, short, unit) then return end   -- (the Alicorn's parked pools)
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
-- The event containers are looked up again only when one has gone (a new level) or every 120 s; FindAllOf walks every
-- object in the game, which several times a second was a visible hitch (user, 2026-10-22: "a bit of lag").
flagCache = { at = -1, t = nil, cs = nil, found = -100 }
function svFlags()
    local now = os.clock()
    -- (was 0.2 s: with the 250 ms tick that walked every flag of the event package each tick, hundreds of map
    -- entries through two pcalls each; user, 2026-10-23: "the custom HUD ... seems a bit laggy")
    if now - flagCache.at < 1.0 then return flagCache.t end
    local cs = flagCache.cs
    -- (a gone container is found by its validity; the timed look again every 120 s, was 30: each FindAllOf walk was a
    -- 22-29 ms hitch in a friend's late rounds, economy review of 2026-10-25)
    local stale = not cs or now - flagCache.found > 120 or (#cs == 0 and now - flagCache.found > 2)
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

function flagLine()
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

survivalPC = nil             -- the player controller in Survival's level (found by probeTick, then reused)

-- Where the player is (cm), or nil.
function playerLocation()
    local pc = valid(survivalPC) and survivalPC or FindFirstOf("PlayerController")
    local ok, l = pcall(function()
        local v = pc.Pawn:K2_GetActorLocation()
        return { X = v.X, Y = v.Y, Z = v.Z }
    end)
    return ok and l or nil
end

function km(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 100000
end
