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

local VERSION = "0.11.2"
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
-- (set while a flight is up) are shown as one count, also returned as the second value.
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
    if #parts == 0 then return nil, up end
    table.sort(parts)
    return table.concat(parts, " ") .. " flights up (SV_Up_*)=" .. up, up
end

-- Where the player is (cm), or nil.
local function playerLocation()
    local pc = FindFirstOf("PlayerController")
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
    intermission_s      = 20,
    spawn_gap_s         = 3,                    -- between two flights of a round
    flights_round1      = 2,
    flights_per_round   = 1,                    -- added every round
    max_flights         = 8,                    -- flights in one round
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
    probe = { enabled = true, behaviour = true, rank = 5, kills = true },
    -- Enemy search range (user 2026-10-22: no chase, enemies should always have the player in view). Mission 22's
    -- fighters use AI module NPC_AIModule_Plane000: 6 km search radius, and they lose a target hidden in cloud.
    -- Survival's own module row (a copy with these values) is given to copies of the aircraft's DT_NPC rows.
    -- The flights' unit area (activation) is set at build time: tools/survival_events.py AREA_RADIUS_M.
    -- luaset: the behaviour set those copies fly (DT_NPC_LuaSet row; nil keeps each aircraft's own). NLID_0400_CP is
    -- the campaign aces' set: after an attack pass it keeps pursuing, where Mission 22's sets extend away for ~13 s
    -- (MoveAwayFromTarget_0011); it also has the aces' pursuit, evasion and cobra/kulbit gun defence.
    search = { enabled = true, radius_m = 40000, lose_in_clouds = false, luaset = "NLID_0400_CP" },
    -- Post-stall manoeuvres (Pugachev's cobra, kulbit): every stock behaviour gates them on the plane's
    -- bCanManeuverPugachevsCobra / bCanManeuverKulbit; on each enemy that appears both are turned off unless its
    -- model is listed here (the code in its blueprint name, BP_OPnnnn_<code>_...: thrust-vectoring and Flanker-family
    -- airframes; those keep their blueprint's own, e.g. su33 cobra but no kulbit), so early fighters never post-stall.
    maneuvers = { enabled = true, post_stall = { "su33", "su35", "su37", "su47", "su57", "f22a" } },
    -- Round HUD. Positions are on the game's HUD design canvas (3840x2160, scaled to the screen; tools/re/HUD_LAYOUT.md).
    hud = {
        enabled          = true,
        x                = 190,                 -- left edge, lined up with the game's TIME / SCORE stack
        y                = 244,                 -- the row after SCORE (TIME 108, SCORE 176 on screen; test 13 screenshot)
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
        callout_s        = 4,                   -- how long a callout stays up
        start_callout_lead_s = 3,               -- "ROUND n" this long before the round's first flight
        zorder           = 0,
        text = {
            round        = "ROUND: %d",
            next_round   = "NEXT ROUND: %s",
            first_round  = "ROUND 1 IN: %s",
            complete     = "ROUND %d COMPLETE",
            complete_sub = "NEXT ROUND IN %d SECONDS",
            start        = "ROUND %d",
            start_sub    = "HOSTILES INBOUND",
        },
    },
}
for n = 1, 8 do for k = 0, 2 do CFG.pool[#CFG.pool + 1] = string.format("ERA_Unit_%02d_Dep_Air%d", n, k) end end
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
-- (AceCombat8.exe 0x144eb8c00), so a script must sit at the path its LuaInitializePath names. Test 17: the script
-- at /Game/Mods/SurvivalMode/AI was never run. StaticLoadObject looks in memory first, so the run-time script goes
-- into an in-memory package at /Game/LuaSource/SurvivalMode/AI/LA_SV_ProbePursueRt.
local PROBE_PKG_SCRIPT = "/Game/LuaSource/SurvivalMode/AI/LA_SV_ProbePursue.LA_SV_ProbePursue"
local PROBE_RT_PACKAGE = "/Game/LuaSource/SurvivalMode/AI/LA_SV_ProbePursueRt"
local PR = { ready = {}, usable = {}, scripts = {}, tries = 0, ammo = {} }   -- rows stay in the tables across levels
local SR = { ready = {}, usable = {}, tries = 0 }   -- enemy search rows (section "enemy search" below)

local function scriptDir() return debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "" end

-- Route 2: a LuaScript object made at run time from the script file (renamed so it can't collide with route 1).
local function runtimeScript()
    if valid(PR.scripts.rt) then return PR.scripts.rt end
    local f = io.open(scriptDir() .. "ai\\LA_SV_ProbePursue.lua", "r")
    if not f then return nil, "Scripts\\ai\\LA_SV_ProbePursue.lua not found" end
    local code = f:read("a"); f:close()
    code = code:gsub("LA_SV_ProbePursue", "LA_SV_ProbePursueRt")
    local cls = StaticFindObject("/Script/LuaPluginRuntime.LuaScript")
    if not valid(cls) then return nil, "class /Script/LuaPluginRuntime.LuaScript not found" end
    local _, pkg = pcall(StaticFindObject, PROBE_RT_PACKAGE)   -- UE4SS throws on a path without ".Object" (test 18)
    if not valid(pkg) then
        local pcls = StaticFindObject("/Script/CoreUObject.Package")
        local okP, p = pcall(StaticConstructObject, pcls, nil, FName(PROBE_RT_PACKAGE))
        if not (okP and valid(p)) then return nil, "package " .. PROBE_RT_PACKAGE .. " not made: " .. tostring(p) end
        pkg = p
    end
    local o = StaticConstructObject(cls, pkg, FName("LA_SV_ProbePursueRt"))
    if not valid(o) then return nil, "StaticConstructObject(LuaScript) returned nothing" end
    o.Code = code
    o.ImportPath = "../../AssetWork/LuaSource/SurvivalMode/AI/LA_SV_ProbePursueRt.lua"
    o.LuaInitializePath = "SurvivalMode.AI.LA_SV_ProbePursueRt"
    local back = ""
    pcall(function() back = o.Code:ToString() end)
    local _, byPath = pcall(StaticFindObject, PROBE_RT_PACKAGE .. ".LA_SV_ProbePursueRt")   -- what the game's require looks up
    log(string.format("probe: run-time LuaScript %s made, code %d chars (read back %d); found by its path: %s",
        nameOf(o), #code, #back, tostring(valid(byPath))))
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
        if not PR.ready[v] and not PR.failed[v] then
            local okV, err = pcall(function()
                local script, why = (v == "Pkg" and packageScript or runtimeScript)()
                if script then
                    local ok, res = probeVariant(tables, v, script)
                    if ok then PR.ready[v] = res else log("probe: " .. v .. " rows not added: " .. tostring(res)); PR.failed[v] = true end
                elseif PR.tries == 1 then log("probe: " .. v .. " script not available: " .. tostring(why)) end
            end)
            if not okV then log("probe: " .. v .. " setup error " .. tostring(err)); PR.failed[v] = true end
        end
    end
    if (PR.ready.Pkg or PR.failed.Pkg) and (PR.ready.Rt or PR.failed.Rt) then PR.tries = 20 end
end

-- The probe aircraft for this round's first flight (odd rounds: package script, even rounds: run-time script).
local function probeAircraft(round)
    if not (CFG.probe.enabled and CFG.probe.behaviour) then return nil end
    local want = round % 2 == 1 and "Pkg" or "Rt"
    local order = { want, want == "Pkg" and "Rt" or "Pkg" }
    for _, v in ipairs(order) do
        if PR.usable[v] and PR.tables then
            local _, have = dtCall(PR.tables.npc, "FindRow", PROBE_TABLES[2].row .. v)
            if have ~= nil then return PR.usable[v], v end
            log("probe: DT_NPC row " .. PROBE_TABLES[2].row .. v .. " is gone (the table was reloaded?); not flown this level")
            PR.usable[v] = nil; PR.ready[v] = nil; PR.tries = 0
        end
    end
    return nil
end

-- Did the game's Lua build our behaviour script? Its Ctor appends its name to %TEMP%\AC8SurvivalMode_probe_ctor.txt
-- (when the game's Lua has io/os; test 16 showed no barrel rolls). The file is cleared when the level loads; the
-- names in it are logged whenever they change.
local PROBE_CTOR_FILE = (os.getenv("TEMP") or ".") .. "\\AC8SurvivalMode_probe_ctor.txt"
local function probeCtorCheck()
    local line = "none (file not written)"
    local f = io.open(PROBE_CTOR_FILE, "r")
    if f then
        local counts, parts = {}, {}
        for l in f:lines() do counts[l] = (counts[l] or 0) + 1 end
        f:close()
        for k, n in pairs(counts) do parts[#parts + 1] = k .. " x" .. n end
        table.sort(parts)
        line = table.concat(parts, ", ")
    end
    if line ~= PR.ctorLine then log("probe: behaviour scripts built by the game's Lua so far: " .. line); PR.ctorLine = line end
end

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
local function searchSetup()
    if SR.done then return end
    if not CFG.search.enabled then SR.done = true; return end
    if not gameInstance() then return end
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
    local ok, why = cloneRow(mod, SEARCH_MODULE.src, SEARCH_MODULE.row, function(r)
        r.Radius = CFG.search.radius_m
        r.bEnableLostTargetInClouds = CFG.search.lose_in_clouds
    end)
    if not ok then return giveUp("module row not added: " .. tostring(why)) end
    SR.module, SR.npcRow, SR.tables = SEARCH_MODULE.row, {}, { npc = npc }
    local n = 0
    for _, a in ipairs(CFG.aircraft) do
        local okA, err = pcall(function()
            local _, mrow = dtCall(mission, "FindRow", a .. "_sv")
            local _, base = dtCall(mission, "FindRow", a)
            if mrow == nil or base == nil then error("no mission row " .. a .. "_sv in DT_SV_NpcMission") end
            local svNpc, srcNpc = mrow.NpcId:ToString(), base.NpcId:ToString()
            local okR, whyR = cloneRow(npc, srcNpc, svNpc, function(r)
                r.NpcAIModuleId = FName(SR.module)
                if CFG.search.luaset then r.LuaSetId = FName(CFG.search.luaset) end
            end)
            if not okR then error(svNpc .. ": " .. tostring(whyR)) end
            SR.ready[a], SR.npcRow[a], n = a .. "_sv", svNpc, n + 1
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
    log(string.format("search: module %s (%s); %d of %d aircraft use it", SEARCH_MODULE.row, check, n, #CFG.aircraft))
    SR.done = true
end

-- The mission row to fly for aircraft `a`: its _sv row when that was ready before this level loaded.
local function searchAircraft(a)
    local sv = SR.usable[a]
    if not (sv and SR.tables) then return a end
    local _, have = dtCall(SR.tables.npc, "FindRow", SR.npcRow[a])
    if have ~= nil then return sv end
    log("search: DT_NPC row " .. SR.npcRow[a] .. " is gone (the table was reloaded?); " .. a .. " flies stock this level")
    SR.usable[a], SR.ready[a], SR.done, SR.tries = nil, nil, false, 0
    return a
end

-- Question 2: PilotRank on each enemy (p from the plane list), called every 2 s while it is up.
local function probeRank(p, tick)
    if not (CFG.probe.enabled and CFG.probe.rank) then return end
    if not p.rank0 then
        local ok, r = pcall(function() return p.obj.PilotRank end)
        p.rank0 = ok and r or "?"
        local okW, err = pcall(function() p.obj.PilotRank = CFG.probe.rank end)
        local _, r1 = pcall(function() return p.obj.PilotRank end)
        p.rankAt = tick
        log(string.format("probe: %s PilotRank %s -> set %d -> reads %s%s", p.name, tostring(p.rank0), CFG.probe.rank,
            tostring(r1), okW and "" or (" (write failed: " .. tostring(err) .. ")")))
    elseif p.rankAt and tick - p.rankAt >= 40 then
        p.rankAt = nil
        local _, r = pcall(function() return p.obj.PilotRank end)
        log(string.format("probe: %s PilotRank 10 s later: %s", p.name, tostring(r)))
    end
end

-- CFG.maneuvers: post-stall permission for this enemy (p from the plane list), set once when it is first seen up.
-- The first plane of each model logs what its blueprint had and what it reads after the write.
local maneuversSaid = {}
local function enemyManeuvers(p)
    if p.maneuvers or not CFG.maneuvers.enabled then return end
    p.maneuvers = true
    local model = p.name:match("^BP_OP%d+_(%w+)_") or "?"
    local allow = false
    for _, m in ipairs(CFG.maneuvers.post_stall) do if m == model then allow = true end end
    local function read()
        local okC, c = pcall(function() return p.obj.bCanManeuverPugachevsCobra end)
        local okK, k = pcall(function() return p.obj.bCanManeuverKulbit end)
        return string.format("cobra %s, kulbit %s", okC and tostring(c) or "?", okK and tostring(k) or "?")
    end
    local before = read()
    local ok, err = true, nil
    if not allow then                       -- allowed models keep their blueprint's own (test 18: su33 cobra only)
        ok, err = pcall(function()
            p.obj.bCanManeuverPugachevsCobra = false
            p.obj.bCanManeuverKulbit = false
        end)
    end
    if not maneuversSaid[model] then
        maneuversSaid[model] = true
        log(string.format("maneuvers: %s (%s) post-stall %s: was %s, now %s%s", model, p.name, allow and "allowed" or "off",
            before, read(), ok and "" or (" (write failed: " .. tostring(err) .. ")")))
    end
end

-- Question 3: called every 2 s while an enemy is up (records), and once when it goes down (logs).
local function probeTrack(p)
    pcall(function()
        local a = p.obj:K2_GetLastDamagedByAttacker()
        if valid(a) then p.attacker = nameOf(a):match("([^%.:]+)$") end
    end)
    pcall(function() local f = p.obj:GetActorForwardVector(); p.fwd = { X = f.X, Y = f.Y, Z = f.Z } end)
end

local AMMO_SHORT = { [0] = "gun", "msl", "sp1", "sp2", "flr" }

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
    log(string.format("probe kill: %s, last hit by %s; you were %s away, %s, altitude %s; you fired %s in the last 6 s",
        p.name, tostring(p.attacker or "?"), p.at and you and string.format("%.1f km", km(p.at, you)) or "?",
        aspect, dz, #used > 0 and table.concat(used, ", ") or "nothing seen"))
end

local ZONE = { X = -707336.0, Y = -261895.0, HALF = 3700000.0 }   -- Mission 22's combat zone (80 km), 3 km margin
local SV_ERR = { [0] = "the game spawned nothing", [-1] = "not in Survival's level", [-2] = "no such unit or aircraft",
                 [-3] = "its last flight is still up", [-4] = "bad arguments", [-5] = "game functions not found" }
local D = nil                      -- the run in progress: { round, state, at, now, queue, spare, up, flown }

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
    H.round = newText("Round"); H.next = newText("Next")
    slotIn(canvas, H.round, { 0, 0 }, { 0, 0 }, { hc.x, hc.y, 0, 0 }, { 0, 0 }, true)
    slotIn(canvas, H.next, { 0, 0 }, { 0, 0 }, { hc.x, hc.y + hc.line, 0, 0 }, { 0, 0 }, true)

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

local pendingCallout = nil

local function hudCallout(text, sub)   -- shown on the next HUD tick (callers are in roundsTick)
    pendingCallout = { text = text, sub = sub }
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
    local t = CFG.hud.text
    setText(H.round, "roundStr", string.format(t.round, math.max(D.round, 1)))
    if D.state == "wait" then
        setText(H.next, "nextStr", string.format(D.round == 0 and t.first_round or t.next_round, clock(D.at - now)))
        if H.nextShown ~= true then H.next:SetVisibility(VIS.HitTestInvisible); H.nextShown = true end
    elseif H.nextShown ~= false then
        H.next:SetVisibility(VIS.Collapsed); H.nextShown = false
    end

    if pendingCallout then
        local c = pendingCallout; pendingCallout = nil
        setText(H.bannerText, "bannerStr", c.text)
        H.bannerSlot:SetSize({ X = math.max(390, #c.text * 24 + 96), Y = 69 })   -- ~24 units a character at size 37
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
    local ac = searchAircraft(CFG.aircraft[math.random(#CFG.aircraft)])
    if D.probeRound ~= D.round then                                           -- the round's first flight: probe aircraft
        D.probeRound = D.round
        local pa, how = probeAircraft(D.round)
        if pa then ac = pa; log(string.format("probe: round %d's first flight %s flies %s (%s script)", D.round, unit, pa,
            how == "Pkg" and "package" or "run-time")) end
    end
    local set = SV_SetAircraft(unit, ac)
    local x, y, dist, bearing = spawnPoint()
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local r = SV_Spawn(unit, x, y, alt * 100, (bearing + 180) % 360)          -- facing the airfield
    log(string.format("round %d: %s%s as %s (%s set), %.0f km out at bearing %.0f, %.1f km up: %s", D.round, unit,
        D.flown[unit] and " (flown before, recycled)" or "", ac, tostring(set), dist, bearing, alt / 1000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r > 0 then D.up[unit], D.flown[unit] = true, true end
    return r
end

local function shuffled(t)
    for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
    return t
end

-- A round's flights: those that have flown before come first (the spawner recycles them, which keeps the game's unit
-- list short); the rest are spares, fresh ones first, for a flight that fails to spawn.
local function startRound()
    D.round = D.round + 1
    local flown, fresh = {}, {}
    for _, u in ipairs(CFG.pool) do
        if not D.up[u] then
            if D.flown[u] then flown[#flown + 1] = u else fresh[#fresh + 1] = u end
        end
    end
    shuffled(flown); shuffled(fresh)
    local want = math.min(CFG.flights_round1 + (D.round - 1) * CFG.flights_per_round, CFG.max_flights, #flown + #fresh)
    D.queue, D.spare = {}, {}
    for _, u in ipairs(flown) do if #D.queue < want then D.queue[#D.queue + 1] = u end end
    for _, u in ipairs(fresh) do
        if #D.queue < want then D.queue[#D.queue + 1] = u else D.spare[#D.spare + 1] = u end
    end
    for i = want + 1, #flown do D.spare[#D.spare + 1] = flown[i] end
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
        if not D.announced and now >= D.at - CFG.hud.start_callout_lead_s then
            D.announced = true
            hudCallout(string.format(CFG.hud.text.start, D.round + 1), CFG.hud.text.start_sub)
        end
        if now >= D.at then startRound() end
    elseif D.state == "spawning" then
        if now < D.at then return end
        local u = table.remove(D.queue, 1)
        if u then
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
        if flights == 0 then
            log(string.format("round %d clear; round %d in %d s", D.round, D.round + 1, CFG.intermission_s))
            if type(SV_LogUnits) == "function" then SV_LogUnits("round " .. D.round .. " clear") end
            D.state, D.at, D.announced = "wait", now + CFG.intermission_s, false
            hudCallout(string.format(CFG.hud.text.complete, D.round),
                       string.format(CFG.hud.text.complete_sub, CFG.intermission_s))
        end
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

local function presetName()
    local dm = FindFirstOf("LiveDifficultyManager")
    local ok, d = pcall(function() return dm.CurrentDifficulty end)
    return (ok and CFG.ammo.by_difficulty[d]) or "standard", ok and d or nil
end

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
        -- The airfield's rearm (and anything else the game refills) loads the aircraft's full stock count: a count
        -- above the preset's cap is put back to the cap, so landing rearms up to the cap and no further.
        local over = {}
        for k = 1, 4 do
            local cap = A.caps and A.caps[k]
            if cap and s[k] > cap then
                SV_SetAmmo(k, cap)
                over[#over + 1] = string.format("%s %d -> %d", AMMO_KINDS[k], s[k], cap)
            end
        end
        if #over > 0 then
            if type(SV_FreeRestock) == "function" and not CFG.ammo.free_restock then SV_FreeRestock(0) end
            log("ammo: refilled above the " .. A.preset .. " caps (rearm?): " .. table.concat(over, ", "))
        end
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

local survivalPC = nil             -- the player controller in Survival's level

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

local function probeTick(tick)
    if levelTick == -1 then
        levelTick = tick
        log("level loaded: PL_SurvivalMode")
        planes, lastAlive, lastFlags = {}, nil, nil
        if type(SV_Reset) == "function" then SV_Reset() end
        log("rounds: native spawner " .. (type(SV_Version) == "function" and ("runtime " .. tostring(SV_Version())) or "missing") ..
            "; round 1 in " .. CFG.first_round_delay_s .. " s")
        D = { round = 0, state = "wait", at = nil, now = nil, queue = {}, spare = {}, up = {}, flown = {}, announced = false }
        PR.usable = { Pkg = PR.ready.Pkg, Rt = PR.ready.Rt }      -- only rows that were in before this level loaded
        log("probe: at level load, probe rows ready: package " .. tostring(PR.ready.Pkg ~= nil) .. ", run-time " .. tostring(PR.ready.Rt ~= nil))
        os.remove(PROBE_CTOR_FILE); PR.ctorLine = nil
        SR.usable = {}
        local nS = 0
        for a, sv in pairs(SR.ready) do SR.usable[a], nS = sv, nS + 1 end
        log(string.format("search: at level load, %d of %d aircraft fly with the %s m search", nS, #CFG.aircraft,
            tostring(CFG.search.radius_m)))
        H, hudTries, hudOff, hudSaid, pendingCallout, survivalPC, A = nil, 0, false, {}, nil, nil, nil
    end
    if tick % 4 == 0 and containerState then                 -- search and behaviour probe rows, from the main menu on
        local okS, errS = pcall(searchSetup)
        if not okS then log("search: setup error " .. tostring(errS)); SR.done = true end
        local okP, errP = pcall(probeSetup)
        if not okP then log("probe: setup error " .. tostring(errP)); PR.tries = 20 end
    end
    if D and tick % 40 == 20 and CFG.probe.enabled and CFG.probe.behaviour then
        local okC, errC = pcall(probeCtorCheck)
        if not okC then log("probe: script check error " .. tostring(errC)) end
    end
    if D then
        if not valid(survivalPC) then survivalPC = playerControllerHere() end
        local now, paused = roundClock(tick)
        if now then
            local okR, errR = pcall(roundsTick, now)
            if not okR then log("rounds: error " .. tostring(errR)) end
            local okH, errH = pcall(hudTick, now, paused, survivalPC)
            if not okH then hudLog("tickerr", "error " .. tostring(errH)) end
        end
        local okA, errA = pcall(ammoTick, tick, survivalPC)
        if not okA then log("ammo: error " .. tostring(errA)) end
    end
    if levelTick then
        if tick - levelTick == 8 then logDifficulty("at mission start") end
        if tick - levelTick == 48 then logDifficulty("10 s into the mission") end
        if tick - levelTick == 60 then pcall(hudDump, "15 s into the mission") end
    end
    local keep = {}
    for _, p in ipairs(pending) do
        p.age = p.age + 1
        if p.age >= 2 then pcall(logPlane, p.obj) else keep[#keep + 1] = p end
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
                pcall(enemyManeuvers, p); pcall(probeTrack, p); pcall(probeRank, p, tick)
                if p.at and you then
                    local d = km(p.at, you)
                    if not nearest or d < nearest then nearest = d end
                end
            else
                p.down = true
                log("round probe: " .. p.name .. " down" .. (p.at and string.format(", last seen %.1f km up%s",
                    p.at.Z / 100000, you and string.format(", %.1f km from you", km(p.at, you)) or "") or ""))
                pcall(probeKill, p, you)
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
