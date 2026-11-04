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

-- { our table, the game's table, the row ours goes just above (SURVIVAL MODE sits above QUIT GAME) }
local TABLES = {
    { mine = "/Game/Mods/SurvivalMode/Data/DT_SV_MissionRows.DT_SV_MissionRows",
      game = "/Game/Datatables/Information/DT_LiveMissionTable.DT_LiveMissionTable" },
    { mine = "/Game/Mods/SurvivalMode/Data/DT_SV_MenuRows.DT_SV_MenuRows",
      game = "/Game/Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands.DT_LiveMenuMainTopCommands",
      above = "QuitGame", coop = true },
}
-- The rows that go into a table: the mission row; in the menu table SURVIVAL MODE, which opens Survival's own pages
-- when the game's page list has them, else the flat rows (SURVIVAL MODE, and CO-OP HOST / JOIN when co-op is on;
-- sv_menu.lua MENU.mainRows). nil while that isn't decided yet (the menu table waits).
local function rowsOf(t)
    if t.coop then return MENU and MENU.mainRows and MENU.mainRows() or nil end
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

-- A line in the crash breadcrumbs (the native runtime's AC8SurvivalMode_crumbs.log, from 0.32.13: SV_Crumb, written at
-- once, the session before kept as .prev): the risky things Survival's Lua does (spawns, removals, copies taken down,
-- teardowns), so a crash shows what came just before it. Nothing with an older runtime.
function crumb(s) if type(SV_Crumb) == "function" then pcall(SV_Crumb, tostring(s):sub(1, 230)) end end

-- A line logged once a session for its key (a hook that fails every tick logs one line, not one a tick).
-- hookErr(what, pcall(f, ...)): a hook's pcall with its first error logged ("<what> error ..."), its results passed
-- on. The behaviour branch's hooks between parts (code review of 2026-10-29: a bare pcall made a hook that failed read
-- as one that never ran).
do
    local said = {}
    function logOnce(key, msg) if not said[key] then said[key] = true; log(msg) end end
    function hookErr(what, ok, ...)
        if not ok then logOnce("hook " .. tostring(what), string.format("%s error %s (its first: not logged again)",
            tostring(what), tostring((...)))) end
        return ok, ...
    end
end
-- [log] verbose (CFG.log, read when called: CFG comes with sv_config.lua): the periodic diagnostic lines as often as they
-- came before the clean up of 2026-10-29 (round probe flags and counts, enemies, ai:, the intensity scores, ammo, perf)
function logVerbose() return CFG ~= nil and type(CFG.log) == "table" and CFG.log.verbose == true end

function valid(o)
    local ok, v = pcall(function() return o ~= nil and o:IsValid() end)
    return ok and v
end

-- (UE4SS's GetFullName walks the object's outers with no checks: a STORE row's TextBlock whose page was going away
-- crashed a joiner's game in that walk, a joiner's run of 2026-10-31 after a WEAPON BAYS purchase, the relabel's
-- FindAllOf("TextBlock"); a pcall doesn't catch it. The native runtime checks every outer is still the engine's first,
-- SV_ObjChain from runtime 0.32.10: "?" when one isn't.)
function nameOf(o)
    if type(SV_ObjChain) == "function" then
        local okA, a = pcall(function() return o:GetAddress() end)
        if not (okA and a) or SV_ObjChain(a) == 0 then return "?" end
    end
    local ok, s = pcall(function() return o:GetFullName() end)
    return ok and s or "?"
end

-- A widget the game made at run time (they live under /Engine/Transient). FindAllOf on a widget blueprint's class
-- also returns the copies stored inside other blueprints' WidgetTrees ("..._C:WidgetTree.X"), which are never on
-- screen (test of 2026-10-22: the landing menu's ammo panel and the TIME row were first found that way).
function liveWidget(w)
    return liveObj(w) and nameOf(w):find("/Engine/Transient", 1, true) ~= nil    -- (0.73.73: liveObj, kept ones too)
end

-- The landing menu's live windows (WBP_Menu_IngameHangar_Common_000_C), one list for everyone who asks: the STORE's row
-- icons (sv_shop.lua SHOP.decorTick), its labels' and the ammo panel's checks for a new page (SHOP.windowsKey), a STORE
-- press (SHOP.pressPage) and co-op's music hold (sv_main.lua, landingShown).
-- (0.73.80, the 31-round co-op run of 2026-11-04, findings perf4 / specials8; PERF_PLAN.md Tier 2 item 8) They were walked
-- for on each new tick they were asked for (0.73.77's maxAge kept a walk two ticks for the labels): down at the airfield in
-- co-op the music hold asked every tick, every other one before it held, so every object the game holds was walked up to
-- four times a second, 25-41 ms each on this UE4SS (no hash tables): the host 2,416 walks (98 s) over the run, 1,176 in
-- one 5.6-minute STORE stay (round 28's 117 ms tick), 70-77 % of each joiner's walk time. Now the windows found are kept
-- (with the name each had: an address another object took since is not it) and looked at once a tick at most (again
-- after a press), live (liveObj) and on screen (IsVisible) or not. Every object is walked again only
--   * on landing: the first look of a visit to the airfield (nobody asked for LANDW_GAP_S: they ask only down there);
--   * when the one on screen goes off it (a page closed: each STORE page opens as a new page object with a window of its
--     own; the host's log of that run: STORE page 23 opened twice in one visit was two pages), at once (LANDW_MIN_S after
--     the last walk at the soonest);
--   * after a STORE press on a row no window on screen has (SHOP.pressPage: its page not found yet);
--   * while none is on screen, every [hud.landing] every_s (the menu not up yet, or a page that came a moment late);
--   * while one is, every backstop_s (a page that opened over another without closing it; 0: never).
-- A walk held (walkHold) waits for the next look, the kept ones answering meanwhile. Each visit's walks are logged as it
-- ends (`shop: the landing menu's windows over this airfield visit ...`); the perf line's "walks:" counts them by class.
LANDW = { list = {}, out = {}, vis = {}, n = 0, total = 0, passes = 0, passWalks = 0 }
do
local CLASS, LANDW_GAP_S, LANDW_MIN_S = "WBP_Menu_IngameHangar_Common_000_C", 3, 0.5
local WHY = { "landing", "closed", "none", "press", "backstop" }
local WHY_TEXT = { landing = "on landing", closed = "a page closed", none = "none on screen", press = "a STORE press",
                   backstop = "backstop" }
local function cfg()
    local h = type(CFG) == "table" and type(CFG.hud) == "table" and CFG.hud.landing or nil
    return type(h) == "table" and h or {}
end
local function onScreen(w)
    local ok, v = pcall(function() return w:IsVisible() end)
    return ok and v == true
end
-- the kept ones still the same live objects, which of them on screen (L.vis by address); true when one is
local function look(L)
    local keep, out, vis, shown = {}, {}, {}, false
    for _, e in ipairs(L.list) do
        if liveObj(e.w) and nameOf(e.w) == e.name then
            keep[#keep + 1], out[#out + 1] = e, e.w
            if onScreen(e.w) then shown = true; vis[e.a] = true end
        end
    end
    L.list, L.out, L.vis = keep, out, vis
    return shown
end
-- one walk for them: what it found kept, true when one is on screen; nil when the walk was held after all (FindAllOf's
-- own walkHold: nothing found, the kept ones left as they were)
local function walk(L, why)
    local found = FindAllOf(CLASS)
    if found == nil and WALK.heldWhy then return nil end
    local list = {}
    for _, w in ipairs(found or {}) do
        local nm = liveObj(w) and nameOf(w) or ""
        if nm:find("/Engine/Transient", 1, true) then list[#list + 1] = { w = w, a = addrOf(w) or nm, name = nm } end
    end
    L.list = list
    L.n, L.total = L.n + 1, L.total + 1
    local v = L.visit
    if v then v.walks = v.walks + 1; v.why[why] = (v.why[why] or 0) + 1; v.most = math.max(v.most, #list) end
    local shown = look(L)
    if not L.said then
        L.said = true
        local c = cfg()
        local back = tonumber(c.backstop_s) or 30
        log(string.format("shop: the landing menu's windows kept between ticks, looked at once a tick and walked for again "
            .. "only on landing, when a page closes, after a STORE press on a page not among them, every %.1f s while none "
            .. "is on screen and every %s while one is (0.73.80; this first walk: %s, %d found, %s on screen)",
            math.max(0.5, tonumber(c.every_s) or 2), back > 0 and string.format("%.0f s", back) or "never",
            WHY_TEXT[why] or tostring(why), #list, shown and "one" or "none"))
    end
    if why == "closed" then
        logOnce("landing windows closed", string.format("shop: a landing menu page closed: its windows walked for again at "
            .. "once (%d found, %s on screen)", #list, shown and "one" or "none yet"))
    end
    return shown
end
-- a visit to the airfield over: its walks logged when the landing menu was up in it, else counted as a pass
local function visitEnd(L, now)
    local v = L.visit
    L.visit = nil
    if not v then return end
    if not v.seen then L.passes, L.passWalks = L.passes + 1, L.passWalks + v.walks; return end
    local parts = {}
    for _, k in ipairs(WHY) do parts[#parts + 1] = string.format("%s %d", WHY_TEXT[k], v.why[k] or 0) end
    log(string.format("shop: the landing menu's windows over this airfield visit (%.0f s): %d walk%s of %s (%s; a walk "
        .. "held back on %d looks), %d kept at most, %d looks; before it %d pass%s with no landing menu (%d walks); %d walks "
        .. "this session (0.73.80: they were walked for every tick in co-op)", now - v.at, v.walks, v.walks == 1 and "" or "s",
        CLASS, table.concat(parts, ", "), v.held, v.most, v.looks, L.passes, L.passes == 1 and "" or "es", L.passWalks, L.total))
    L.passes, L.passWalks = 0, 0
end
-- The landing menu's live windows (the kept ones; walked for again as above). (A second argument, 0.73.77's maxAge, is
-- no longer used: every caller shares the kept ones.)
function landingWindows(tick)
    local L = LANDW
    if L.tick == tick and not L.again then return L.out end
    L.again, L.tick = nil, tick
    local now = os.clock()
    local c = cfg()
    local every, back = math.max(0.5, tonumber(c.every_s) or 2), tonumber(c.backstop_s) or 30
    local why = nil
    if not L.askAt or now - L.askAt > LANDW_GAP_S then          -- a visit to the airfield starts: walked for at once
        visitEnd(L, now)
        L.visit = { at = now, walks = 0, why = {}, held = 0, most = 0, looks = 0, seen = false }
        L.wasShown, L.force, L.need, why = false, nil, L.n + 1, "landing"
    end
    L.askAt = now
    local v = L.visit
    v.looks = v.looks + 1
    local shown = look(L)
    if L.wasShown and not shown then                             -- the window on screen went off it: a page closed
        L.force = L.force or "closed"
        L.need = L.n + 2       -- ("none on screen" believed after the walk at once and the next: a page that came late)
    end
    L.wasShown = shown
    if not why then
        if L.force and (not L.walkAt or now - L.walkAt >= LANDW_MIN_S) then why = L.force
        elseif not shown and not L.force and (not L.walkAt or now - L.walkAt >= every) then why = "none"
        elseif shown and back > 0 and L.walkAt and now - L.walkAt >= back then why = "backstop" end
    end
    if why and walkHold() then                                   -- (a held walk finds nothing: it waits, not a walk)
        v.held = v.held + 1
        if why ~= "none" and why ~= "backstop" then L.force = why end
        why = nil
    end
    if why then
        local got = walk(L, why)
        if got == nil then                                       -- (held inside FindAllOf: as above)
            v.held = v.held + 1
            if why ~= "none" and why ~= "backstop" then L.force = why end
        else
            L.force, L.walkAt, shown = nil, now, got
            L.wasShown = shown
        end
    end
    if shown then v.seen = true end
    return L.out
end
-- One of the landing menu's windows on screen: true; none, a walk having looked again since it went off: false; not
-- known yet (a page just closed, its next looked for; a walk held): nil, the caller keeps what it had.
function landingShown(tick)
    landingWindows(tick)
    local L = LANDW
    if L.wasShown then return true end
    if L.n >= (L.need or 0) then return false end
    return nil
end
-- w (a window landingWindows gave) on screen at the last look
function landingVisible(w) local a = addrOf(w); return a ~= nil and LANDW.vis[a] == true end
-- walk for them again at the next look (why: "press", a STORE press on a page not among them)
function landingWindowsRefresh(why) LANDW.force, LANDW.again = LANDW.force or why or "press", true end
-- the player left the airfield (sv_main.lua's music hold): the visit's walks logged, the next look a landing
function landingLeft()
    local L = LANDW
    if not L.visit then return end
    visitEnd(L, os.clock())
    L.askAt, L.wasShown, L.force = nil, false, nil
end
-- the level torn down (sv_shop.lua's LEVEL_DROPS.store): the kept windows forgotten, none of them touched
function landingWindowsForget()
    local L = LANDW
    if L.visit then visitEnd(L, os.clock()) end
    L.list, L.out, L.vis, L.tick, L.askAt, L.wasShown, L.force, L.again = {}, {}, {}, nil, nil, false, nil, nil
end
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

-- (hotfix2, the host's crash of 2026-10-31 16:56:09: an access violation inside UE4SS reading [garbage + 0x20], from
-- Survival's Lua tick, a second after coop's watchShots first saw your BP_plwp_hpaa_a0_C. valid() is UE4SS's IsValid,
-- which reads the object itself: on a freed one it can pass, and a property read after it walks garbage; a pcall
-- doesn't catch it.) o's address when the runtime says o and every outer above it are live objects (SV_ObjChain, which
-- reads only GUObjectArray), else nil (null too). Ask it, not valid(), before reading an object kept between ticks or
-- taken from a game array (a weapon in flight, its target).
function liveAddr(o)
    local a = addrOf(o)
    if not a or a == 0 then return nil end
    if type(SV_ObjChain) == "function" then
        local r = SV_ObjChain(a)
        if r == 1 then return a elseif r == 0 then return nil end
    end
    return valid(o) and a or nil                          -- (-1: the runtime can't tell; as before)
end

-- (0.73.73) o is still the engine's live object: liveAddr when the runtime can tell (GUObjectArray), else valid(). For an
-- object kept between ticks (the player controller, a widget found a tick before), which valid() reads even once freed.
function liveObj(o)
    if o == nil then return false end
    if type(SV_ObjChain) == "function" then return liveAddr(o) ~= nil end
    return valid(o)
end

---------------------------------------------------------------------------------------------------- the level going away
-- (0.73.73, the testers' logs of 0.73.70, 2026-11-01) The moment Survival's level starts going away (Quit Mission, a
-- quit to the main menu, the next level loading), and the walks over every object held while a level comes or goes:
--   * the plane sweep paid for every plane the unload destroyed, before `run over: left` 8 s later: 6 runs, up to 26
--     kills / 4,340 Z (A10 11:31:57.386: four planes "down", you firing nothing, 63 ms before `world: .../PL_MainMenu`);
--   * the host crashed inside UE4SS's FindAllOf over a freed object on Quit Mission (A20 13:40:38, UE4SS.dll+0x2ab5bd,
--     the address hotfix5's native spawner search crashed at as a level unloaded).
-- levelGoing(): true from the first sign until the next level's reset (LEAVE.reset, sv_main.lua): another main level
-- loading (svLevelOn false, sv_config.lua's world watch) or this level's LiveUnitSpawner gone, as the native runtime
-- says once it has answered in this level (SV_UnitAlive -1 "not ready" / -6; hotfix5's g_spawnerLost, its log line
-- `spawner: this level's LiveUnitSpawner is gone` in the same second as every quit of those logs, never at a restart:
-- the two restarts kept their spawner).
LEAVE = { why = nil, at = nil, seen = false, probeAt = nil, unpaid = 0, hard = false, badAt = nil }
function LEAVE.reset()
    LEAVE.why, LEAVE.at, LEAVE.seen, LEAVE.probeAt, LEAVE.unpaid, LEAVE.unpaidSaid = nil, nil, false, nil, 0, nil
    LEAVE.hard, LEAVE.badAt = false, nil
    LEAVE.gone = nil                                     -- ((0.73.77) the teardown gate's: levelGate, below)
end
local WALK_LEAVE_S, WALK_WORLD_S = 8, 3
function levelGoing()
    -- (0.73.73 review) two kinds of sign: another level loading (hard: it stays until the next level's reset) and the
    -- unit spawner gone (soft). A soft one latches only when the spawner stays gone a second (one odd answer as a
    -- pause-menu restart makes its spawner again latched it for the rest of the run: no kill paid from then on), and
    -- lets go when the spawner answers again; svFlags (the restart's own check) runs on under a soft one (levelLeaving).
    if not D and not LEAVE.why then return false end
    local why, now = nil, os.clock()
    if svLevelOn == false then
        if not LEAVE.hard then why = "another level is loading" end
        LEAVE.hard = true
    -- (the runtime asked only once a plane of this level is up: before its spawner is found each ask searches every
    -- object for it, the walk this guards against; nothing to pay for before then anyway)
    elseif type(SV_UnitAlive) == "function" and levelTick and levelTick >= 0 and type(planes) == "table" and (#planes > 0 or LEAVE.why) then
        -- (twice a second at most, once a second while latched. (0.73.79, the lag audit's item 5) It was 10 times a
        -- second, so every tick half asked: 0.75 ms each on a tester's PC. This is only the soft backstop: the runtime's
        -- teardown gate (levelGate) and svLevelOn close first in every quit logged since 0.73.77)
        local every = LEAVE.why and 1 or 0.5
        if not LEAVE.probeAt or now - LEAVE.probeAt >= every then
            LEAVE.probeAt = now
            local u = CFG and type(CFG.pool) == "table" and CFG.pool[1] or nil
            local ok, r = false, nil
            if u then ok, r = pcall(SV_UnitAlive, u) end
            if ok and type(r) == "number" then
                if r == -1 or r == -6 then
                    if LEAVE.seen and not LEAVE.why then
                        LEAVE.badAt = LEAVE.badAt or now
                        if now - LEAVE.badAt >= 1 then why = string.format("its unit spawner is gone: SV_UnitAlive %d", r) end
                    end
                elseif r ~= -5 then
                    LEAVE.seen, LEAVE.badAt = true, nil           -- (its spawner answered in this level)
                    if LEAVE.why and not LEAVE.hard then
                        log("level: its unit spawner answers again (" .. tostring(r) .. "): Survival's level is NOT going away after all; kills paid again")
                        crumb("level going away: false alarm")
                        LEAVE.why, LEAVE.at = nil, nil
                    end
                end
            end
        end
    end
    if why and not LEAVE.why then
        LEAVE.why, LEAVE.at = why, now
        log(string.format("level: Survival's level is going away (%s): no kill paid or counted from here, no walk over "
            .. "every object for %d s", why, WALK_LEAVE_S))
        crumb("level going away: " .. why)
    elseif why and LEAVE.hard then
        LEAVE.why = why                                   -- (a soft sign first, now the next level: hard from here)
    end
    return LEAVE.why ~= nil, LEAVE.why
end
-- (0.73.73 review) only the hard sign: another level loading
function levelLeaving() return LEAVE.hard == true end

-- UE4SS's FindAllOf / FindFirstOf walk every object in GUObjectArray and read each one's class chain; over objects being
-- freed that read crashes (2b above; 2c, A15 20:27:56: UE4SS.dll+0x3e60be, a class check on a freed object 1 s after a
-- round's last kill). Every walk of this mod's Lua (all its parts call these two globals) waits while walkHold() says
-- why: the level going away (WALK_LEAVE_S from its first sign), a run still on with another level loading, a main level
-- just made (WALK_WORLD_S: the main menu, a hangar, the transition map out of a run), or the engine freeing objects (the
-- runtime's SV_GcBusy, when it has one). A held walk finds nothing (nil, as a walk that found none), logged once a hold.
WALK = { held = 0, heldWhy = nil, worldAt = nil, world = nil }
function walkHold()
    local now = os.clock()
    if LEAVE.why and now - (LEAVE.at or now) < WALK_LEAVE_S then return LEAVE.why end
    if D and svLevelOn == false then return "another level is loading" end
    if WALK.worldAt and now - WALK.worldAt < WALK_WORLD_S then return "a level is loading (" .. tostring(WALK.world) .. ")" end
    if D then
        local going, why = levelGoing()
        if going and now - (LEAVE.at or now) < WALK_LEAVE_S then return why end
    end
    return nil
end
-- (0.73.73 review) walkHold's reasons, or the engine freeing objects (the runtime's SV_GcBusy): for the walks that come
-- round often and can skip a pass (the weapons log's looks). Not for every walk: an incremental purge runs often in
-- play, and a one-shot walk held then (the shuttle pad's removal, the Ladon missiles' toning, a round's repairs) lost
-- its work.
function walkBusy()
    local why = walkHold()
    if why then return why end
    if type(SV_GcBusy) == "function" then
        local ok, b = pcall(SV_GcBusy)
        if ok and b == 1 then return "the engine is freeing objects" end
    end
    return nil
end
do
    local rawAll, rawFirst = FindAllOf, FindFirstOf
    local function held(fn, cls)
        local why = walkHold()
        if not why then
            if WALK.heldWhy then
                log(string.format("walks: the hold is over (%d walks over every object waited)", WALK.held))
                WALK.heldWhy, WALK.held = nil, 0
            end
            return false
        end
        WALK.held = WALK.held + 1
        if WALK.heldWhy ~= why then
            WALK.heldWhy = why
            log(string.format("walks: %s(%s) and every walk over every object held: %s", fn, tostring(cls), why))
        end
        return true
    end
    -- ((0.73.77, Workstream B1) each walk timed by class for the perf line's "walks:" (sv_main.lua perfLine empties
    -- WALK.stat): a walk reads every object the game holds, so one that costs more late in a run shows there)
    WALK.stat = {}
    local function timedWalk(raw, key, cls)
        local t0 = os.clock()
        local r = raw(cls)
        local dt = (os.clock() - t0) * 1000
        local st = WALK.stat
        if st then
            local e = st[key]
            if not e then e = { n = 0, ms = 0, max = 0, found = 0 }; st[key] = e end
            e.n, e.ms = e.n + 1, e.ms + dt
            if dt > e.max then e.max = dt end
            if type(r) == "table" and #r > e.found then e.found = #r end
        end
        return r
    end
    if type(rawAll) == "function" then
        function FindAllOf(cls) if held("FindAllOf", cls) then return nil end return timedWalk(rawAll, tostring(cls), cls) end
    end
    if type(rawFirst) == "function" then
        function FindFirstOf(cls) if held("FindFirstOf", cls) then return nil end return timedWalk(rawFirst, "first " .. tostring(cls), cls) end
    end
end
-- (0.73.79, the lag audit of 2026-11-04, testing/2026-11-03/PERF_PLAN.md item 1) This UE4SS can't find AC8's
-- FUObjectHashTables (UE4SS.log: "FUObjectHashTables unavailable, object lookups use GUObjectArray"), so every
-- StaticFindObject scans every object the game holds: ~3 ms each on Saint Alessia's PC, and the round clock alone asked
-- for GameplayStatics twice a tick (the perf line's "clock", 6.3 ms of her 24 ms tick). A native object ("/Script/...":
-- a C++ class, its default object, a function library) is made at start and never freed, so the first find of one is
-- kept and handed out again while it's still a live object (liveObj: GUObjectArray). /Game/ assets can unload: never
-- kept. A miss is never kept (loadObject looks, loads, then looks again). The finds that still scan are counted for the
-- perf line's "finds:" (WALK.fstat).
do
    local rawFind = StaticFindObject
    local SCRIPT = {}
    WALK.fstat = { n = 0, ms = 0, max = 0, kept = 0 }
    if type(rawFind) == "function" then
        function StaticFindObject(p, ...)
            local script = type(p) == "string" and select("#", ...) == 0 and p:sub(1, 8) == "/Script/"
            if script then
                local o = SCRIPT[p]
                if o ~= nil then
                    if liveObj(o) then WALK.fstat.kept = WALK.fstat.kept + 1; return o end
                    SCRIPT[p] = nil
                end
            end
            local t0 = os.clock()
            local o = rawFind(p, ...)
            local dt = (os.clock() - t0) * 1000
            local f = WALK.fstat
            f.n, f.ms = f.n + 1, f.ms + dt
            if dt > f.max then f.max, f.maxPath = dt, tostring(p) end
            if script and o ~= nil and valid(o) then SCRIPT[p] = o end
            return o
        end
    end
end
-- (a main level made: the hold above. Not Survival's own, whose sublevels load blocking the game thread anyway, nor the
-- transition map made as it loads; the transition map out of a run, or from the main menu, yes)
pcall(NotifyOnNewObject, "/Script/Engine.World", function(w)
    local n = nameOf(w)
    local main = n:find("/PL_", 1, true) ~= nil and not n:find("PL_SurvivalMode", 1, true)
    if main or (n:find("TransitionMap", 1, true) and (LEAVE.why or not D)) then
        WALK.worldAt, WALK.world = os.clock(), n:match("([%w_]+)$") or "?"
    end
end)

---------------------------------------------------------------------------------------------------- the teardown gate
-- (0.73.77, plan F1) The crash on quit (Shazzy 2026-11-02 16:57:02 while DOWN and spectating, cressendo 2026-11-03
-- 10:42:25 from flight; 0.73.76 both): UE4SS's Lua property lookup on an object the closing level had freed
-- (UE4SS.dll+0x2ab5bd), a second after the runtime's `this level's LiveUnitSpawner is gone`. levelGoing() waits that
-- second before it believes the spawner gone (a restart's odd answer), and every part read the level's objects meanwhile.
-- The runtime's teardown gate (0.32.22, SV_LevelGone) closes the moment the spawner's world is freed, marked garbage or
-- being purged (a restart keeps its world: never then), and stays closed until the next Survival level's SV_Reset.
-- levelGate(), first thing in each tick half (sv_main.lua probeTick / probeTickB, and before COOP.tick): when it closes,
-- the level is going for sure (LEAVE's hard sign: no kill paid, walks held), every part's kept objects are dropped, never
-- walked or put back (levelDrop: LEVEL_DROPS, the parts' own droppers, and the core's lists), the run ends there (the
-- caller's runLeft, whose cleanups drop instead of restoring while levelTorn()), and the halves' level work is held
-- GATE_HOLD_S. A new Survival level loading (levelTick -1) goes on: its reset (SV_Reset) opens the gate. After the hold
-- the halves run as after any run's end (no D). Without SV_LevelGone (an older main.dll): never closed, as before.
GATE = { closed = false, at = nil, held = 0, waitSet = nil }
LEVEL_DROPS = {}               -- name -> function(why): that part's kept level objects forgotten, none of them touched
-- ((0.73.79, the lag audit's item 7) the game's LiveDifficultyManager, found once and kept while it's a live object
-- (liveObj), dropped with the level; looked for at most every 5 s while it isn't found. It was a FindFirstOf (8-14 ms on a
-- tester's PC) each time the difficulty was read: every 30 s (presetName), on each new aircraft (the attackers: line))
local DIFFMGR = { obj = nil, at = -1e9 }
function difficultyManager()
    if DIFFMGR.obj ~= nil and liveObj(DIFFMGR.obj) then return DIFFMGR.obj end
    DIFFMGR.obj = nil
    if os.clock() - DIFFMGR.at < 5 then return nil end
    DIFFMGR.at = os.clock()
    local m = FindFirstOf("LiveDifficultyManager")
    if m ~= nil and valid(m) then DIFFMGR.obj = m end
    return DIFFMGR.obj
end
LEVEL_DROPS.difficulty = function() DIFFMGR.obj, DIFFMGR.at = nil, -1e9 end
local GATE_HOLD_S = 10
function levelTorn() return LEAVE.gone == true end
function levelDrop(why)
    local names = {}
    for name, fn in pairs(LEVEL_DROPS) do
        local ok, err = pcall(fn, why)
        if ok then names[#names + 1] = name else log("level gate: " .. tostring(name) .. "'s drop error " .. tostring(err)) end
    end
    if ALLY and type(ALLY.forgetActors) == "function" then pcall(ALLY.forgetActors) end    -- (the defences' actor list)
    if COOP and type(COOP.levelDrop) == "function" then                                   -- (co-op's copies and planes,
        local ok, err = pcall(COOP.levelDrop, why)                                         --  when sv_coop.lua has one)
        if ok then names[#names + 1] = "coop" else log("level gate: coop's drop error " .. tostring(err)) end
    end
    planes, pending, lastAlive = {}, {}, nil              -- (the core's: every AI plane of the level, those just made)
    survivalPC, H = nil, nil                               -- (the player controller, the HUD layer: the level's)
    table.sort(names)
    return names
end
function levelGate()
    levelGateStep()
    -- (CFG.recycle.destroy_after_s to the runtime, once a session: F2b)
    if GATE.waitSet == nil and type(SV_RecycleWait) == "function" and type(CFG) == "table" and type(CFG.recycle) == "table" then
        local s = math.floor(math.max(0, math.min(600, tonumber(CFG.recycle.destroy_after_s) or 30)))
        local ok = pcall(SV_RecycleWait, s)
        GATE.waitSet = ok
        log(string.format("recycle: a recycled flight's old unit actor is destroyed %d s after it's freed to spawn again%s", s,
            ok and "" or " (not set: SV_RecycleWait failed)"))
    end
    if type(SV_LevelGone) ~= "function" then return false end
    local ok, g = pcall(SV_LevelGone)
    if not ok or g ~= 1 then
        if GATE.closed then
            log(string.format("level gate: open again (a new Survival level: SV_Reset; %d tick halves were held)", GATE.held))
            GATE.closed, GATE.held = false, 0
        end
        return false
    end
    local now = os.clock()
    if not GATE.closed then
        GATE.closed, GATE.at, GATE.held = true, now, 0
        LEAVE.gone, LEAVE.hard = true, true
        if not LEAVE.why then LEAVE.why, LEAVE.at = "its world is gone (the runtime's teardown gate)", now end
        local names = levelDrop("the level torn down")
        log(string.format("level gate: closed (Survival's level is being torn down%s): its objects dropped, never walked or put "
            .. "back (%s and the core's lists); the run ends here; the tick halves' level work held %d s",
            D and string.format(", round %d", D.round or 0) or ", no run on", #names > 0 and table.concat(names, ", ") or "no part's",
            GATE_HOLD_S))
        crumb("level gate closed: objects dropped")
    end
    if levelTick == -1 then return false end               -- (a new Survival level loading: its reset opens the gate)
    if now - (GATE.at or now) >= GATE_HOLD_S then return false end
    GATE.held = GATE.held + 1
    return true
end
-- the gate's caller, each half, is also where the recycle test below steps (it's a game-thread job: no timer of its own)
function levelGateStep()
    -- TEST ONLY BEGIN (the bomber raid recycle test's steps, RECYCLE_TEST below)
    if RECYCLE_TEST and RECYCLE_TEST.on then
        local ok, err = pcall(RECYCLE_TEST.tick)
        if not ok then RECYCLE_TEST.on = false; log("test: Ctrl+F11 recycle test error " .. tostring(err) .. "; stopped") end
    end
    -- TEST ONLY END
end

-- ((0.73.82) Saint Alessia's crash on launch of 2026-11-04) Key presses run on the game thread. UE4SS 3.0.1 calls a key
-- bind's function on its own input thread, on the same Lua thread as NotifyOnNewObject's callbacks (which run on the
-- thread that builds the object, with no lock), and every bind here then called ExecuteInGameThread there, which makes a
-- new Lua thread, two registry references and a closure: Lua work off the game thread, in this mod's one Lua state,
-- while the game thread may be running its own (Lua isn't safe on two threads at once; the 0.73.75 "Ref was not
-- function" that lost the tick was likely two such calls at once). Every RegisterKeyBind from here on is wrapped: UE4SS
-- gets a function that only counts the press in a slot made at load (no allocation, no call into anything), and the
-- tick's job (sv_main.lua) runs the binds' own functions for the presses counted since, on the game thread
-- (KEYQ.drain), with ExecuteInGameThread running its function at once meanwhile (the job is itself one of UE4SS's
-- game-thread actions, and queuing another from inside one edits the list UE4SS is going through).
KEYQ = { hits = {}, done = {}, fns = {}, MAX = 4 }
do
    local hits, done, fns = KEYQ.hits, KEYQ.done, KEYQ.fns
    for i = 1, 96 do hits[i], done[i] = 0, 0 end      -- (the slots made now, so a press never grows the table)
    local realBind = RegisterKeyBind
    if type(realBind) == "function" then
        RegisterKeyBind = function(key, a, b)
            local mods, fn = a, b
            if b == nil and type(a) == "function" then mods, fn = nil, a end
            if type(fn) ~= "function" then           -- (not a bind: UE4SS's own error)
                if b == nil then return realBind(key, a) end
                return realBind(key, a, b)
            end
            local i = #fns + 1
            fns[i], hits[i], done[i] = fn, 0, 0
            local function pressed() hits[i] = hits[i] + 1 end   -- (UE4SS's input thread: one count, nothing else)
            if mods == nil then return realBind(key, pressed) end
            return realBind(key, mods, pressed)
        end
    end
    local function now(f)                               -- (ExecuteInGameThread while the presses run: we're on it)
        local ok, err = pcall(f)
        if not ok then log("keys: error " .. tostring(err)) end
    end
    function KEYQ.drain()                               -- (the game thread: the tick's job, sv_main.lua)
        for i = 1, #fns do
            local h = hits[i]
            local k = h - done[i]
            if k > 0 then
                done[i] = h
                if k > KEYQ.MAX then k = KEYQ.MAX end
                local queue = ExecuteInGameThread
                ExecuteInGameThread = now
                for _ = 1, k do
                    local ok, err = pcall(fns[i])
                    if not ok then log("keys: error " .. tostring(err)) end
                end
                ExecuteInGameThread = queue
            end
        end
    end
end

-- TEST ONLY BEGIN
-- Ctrl+F11 in a run (plan F2d): the round 3 bomber raid's crash pattern 20 times, to test the recycle and the path tracker
-- guard (runtime 0.32.22) solo: each cycle takes the strike flight EA_Unit_01_Air0 and the heavy flight EA_Unit_01_Air1
-- off the phase's list (SV_Recycle force 1, alive or not: their unit actors destroyed CFG.recycle.destroy_after_s later;
-- 0 there is the 0.32.21 way, at once, the crashes' pattern), spawns the strike flight 0.5 s on and the heavies (their
-- route: a path) 3 s on, every 10 s. Pressed again: stopped. Lines `test: F2d cycle N/20: ...`, and the runtime's
-- `recycle ...` / `guard: AI path tracking ...` in AC8SurvivalMode.log. Pressing it makes the run unranked (LB.testKey).
RECYCLE_TEST = { on = false, n = 0, total = 20, step = 0, at = 0, units = { "EA_Unit_01_Air0", "EA_Unit_01_Air1" } }
function RECYCLE_TEST.tick()
    local T = RECYCLE_TEST
    local now = os.clock()
    if not (D and D.now) or levelTorn() then T.on = false; log("test: F2d recycle test stopped (no run, or the level going)"); return end
    if now < T.at then return end
    if T.step == 0 then
        if T.n >= T.total then
            for _, u in ipairs(T.units) do pcall(SV_Recycle, u, 1); D.up[u] = nil end
            T.on = false
            log(string.format("test: F2d recycle test done: %d cycles; the last flights taken off again", T.n))
            hudCallout("TEST: RECYCLE TEST DONE", string.format("%d CYCLES", T.n))
            return
        end
        T.n = T.n + 1
        local r = {}
        for _, u in ipairs(T.units) do
            local okR, v = pcall(SV_Recycle, u, 1)
            r[#r + 1] = u .. " " .. tostring(okR and v or ("error " .. tostring(v)))
            D.up[u] = nil
        end
        log(string.format("test: F2d cycle %d/%d: taken off the list: %s", T.n, T.total, table.concat(r, ", ")))
        T.step, T.at = 1, now + 0.5
    elseif T.step == 1 then
        local okS, r = pcall(spawnFlight, T.units[1])
        log(string.format("test: F2d cycle %d/%d: the strike flight %s: %s", T.n, T.total, T.units[1], tostring(okS and r or ("error " .. tostring(r)))))
        T.step, T.at = 2, now + 2.5
    elseif T.step == 2 then
        local okS, r = pcall(spawnFlight, T.units[2])
        log(string.format("test: F2d cycle %d/%d: the heavy flight %s: %s", T.n, T.total, T.units[2], tostring(okS and r or ("error " .. tostring(r)))))
        T.step, T.at = 0, now + 7
    end
end
if type(RegisterKeyBind) == "function" and Key and Key.F11 then
    local mods = (ModifierKey and ModifierKey.CONTROL) and { ModifierKey.CONTROL } or {}
    pcall(RegisterKeyBind, Key.F11, mods, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(function()
                if LB and LB.testKey then pcall(LB.testKey, Key.F11) end
                local T = RECYCLE_TEST
                if T.on then T.on = false; log("test: Ctrl+F11, the F2d recycle test stopped at cycle " .. T.n); return end
                if not (D and D.now) or type(SV_Recycle) ~= "function" then
                    log("test: Ctrl+F11 outside a Survival run, or no SV_Recycle (runtime 0.32.22)"); return
                end
                T.on, T.n, T.step, T.at = true, 0, 0, 0
                local wait = type(SV_RecycleWait) == "function" and SV_RecycleWait() or "?"
                log(string.format("test: Ctrl+F11, the F2d recycle test: %d cycles of %s, unit actors destroyed %s s after", T.total,
                    table.concat(T.units, " + "), tostring(wait)))
                hudCallout("TEST: RECYCLE TEST", string.format("%d CYCLES", T.total))
            end)
            if not ok then log("test: Ctrl+F11 error " .. tostring(err)) end
        end)
    end)
end
-- TEST ONLY END

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

-- (0.73.73: kept once found, while it's live: it lives the whole session, and up to three walks over every object a call
-- were made each time; walkHold)
local GI = { obj = nil }
function gameInstance()
    if GI.obj ~= nil and liveObj(GI.obj) then return GI.obj end
    GI.obj = nil
    for _, cls in ipairs({ "BP_LiveGameInstance_C", "LiveGameInstance", "GameInstance" }) do
        local gi = FindFirstOf(cls)
        if valid(gi) then GI.obj = gi; return gi end
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
local absent = {}                  -- extra rows this build's tables don't have: said once, not looked for again
local function putRow(t, game, row, wasReady)
    if absent[row] then return "in" end
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
        if row ~= ROW then
            absent[row] = true
            log("rows: '" .. row .. "' is not in this build's tables (" .. tostring(why) .. "); left out")
            return "in"
        end
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

-- The stock main-menu entries CFG.menu.hide names come off the game's copy of the menu table (in memory only; a
-- reloaded table comes back with them, so every pass looks again). Never a row of ours, never QUIT GAME.
local hiddenSaid = {}
local function hideRows(game)
    local m = CFG and CFG.menu
    local list = (m and m.hide_stock and type(m.hide) == "table") and m.hide or {}
    -- CAMPAIGN TRAINING always while Survival's pages open through its page (sv_menu.lua BORROWED): its row would open them
    if MENU and MENU.pages then list = { "CampaignTraining", table.unpack(list) } end
    for _, row in ipairs(list) do
        if type(row) == "string" and row ~= ROW and row ~= "QuitGame" and not row:find("^Survival") then
            local _, have = dtCall(game, "FindRow", row)
            if have ~= nil then
                dtCall(game, "RemoveRow", row)
                local _, still = dtCall(game, "FindRow", row)
                log("rows: '" .. row .. "' " .. (still == nil and "taken off" or "could not be taken off") .. " the main menu")
                hiddenSaid[row] = true
            elseif not hiddenSaid[row] then
                hiddenSaid[row] = true
                log("rows: '" .. row .. "' is not on the main menu; nothing to hide")
            end
        end
    end
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
        if t.above then hideRows(game) end                 -- (the menu table: the stock entries CFG.menu.hide names)
        local want = rowsOf(t)
        if not want then return true end                   -- (the pages aren't decided yet: sv_menu.lua)
        if t.coop then                                     -- the other set out (the last main menu had it)
            local key = table.concat(want, ",")
            if t.rowSet ~= key then
                if t.rowSet then log("rows: the main menu's Survival rows are now " .. key) end
                t.rowSet = key
                local keep = {}
                for _, r in ipairs(want) do keep[r] = true end
                for _, r in ipairs(MENU.allRows) do
                    if not keep[r] then
                        local _, have = dtCall(game, "FindRow", r)
                        if have ~= nil then dtCall(game, "RemoveRow", r); log("rows: '" .. r .. "' taken off the main menu") end
                    end
                end
                ready[i] = false
            end
        end
        local wasReady = ready[i]
        for _, row in ipairs(want) do                      -- (SURVIVAL MODE first, then the co-op ones below it)
            local r = putRow(t, game, row, wasReady)
            if r == "stop" then return false end
            if r == "wait" then return true end
        end
        if t.above and not wasReady then                   -- placing one row moves `above` too: all of them above it
            for _ = 1, #want + 1 do
                local p, all = rowOrder(game), true
                for _, row in ipairs(want) do
                    if not absent[row] and not (p[row] and p[t.above] and p[row] < p[t.above]) then all = false; placeAbove(game, t.above, row) end
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
-- still alive when it changes and Survival's SV_* flags when they change (both with [log] verbose; without, the flags
-- once a level and when one that isn't a counter changes: sv_main.lua probeTick), and the game's difficulty at mission
-- start.
planes = {}                  -- created AI aircraft in this level: { obj, name }
pending = {}                 -- AI aircraft just created, logged on a later tick (position is set by then)
AIRFIELD = { X = 1609639.0, Y = -436414.0 }   -- Comona Airport runway (cm), the spawn anchor
lastAlive, lastFlags = nil, nil

function inSurvival(o) return nameOf(o):find("PL_SurvivalMode", 1, true) ~= nil end

-- Callbacks only record: all logging runs in the one game-thread tick below. A plane made during an SV_Spawn call is
-- tagged with the flight being spawned (spawningUnit, set around the call): GetUnitName() reads back empty (test of
-- 2026-10-22), and the world data's object names don't follow their flights' names.
-- spawningIdx (0 before a pool or bomber flight's SV_Spawn, nil otherwise): each plane's index in its flight, p.k, in the
-- order the spawner makes them, 0 the lead (desc 0: SV_SetAircraft(unit, row, 0) puts an ace or the jammer there).
-- The squad director's per-plane events go by it (tools/re/BEHAVIOUR_DIRECTOR.md, unit 1); creation order = desc order
-- is [I] until a test's "spawn index:" line shows the lead's own blueprint at k 0 (a jammer or a Harvest flight).
spawningUnit, spawningIdx = nil, nil
pcall(NotifyOnNewObject, "/Script/Live.LiveAIPlane", function(o)
    local k = spawningIdx
    if k then spawningIdx = k + 1 end
    pending[#pending + 1] = { obj = o, age = 0, unit = spawningUnit, k = k }
end)

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

-- The spawn index's check: a flight whose lead got its own row (an ace's, the jammer's; sv_spawn.lua D.leadRow) says,
-- once its k 0 and k 1 are both in, which blueprint each flies. The lead's at k 0 if the spawner makes desc 0 first.
-- Only a lead whose blueprint differs from its wings' can tell: the jammer (an EA-18G leading pool fighters, round 8 on)
-- and Harvest's aces (the reaper tier: a "_CP_Named" lead over "_CP_Shadow" wings, the Rafale over Typhoons). Every
-- other squadron's lead and wings share one blueprint (tools/build_survival.py ACES): "can't tell" (review of unit 1).
local LEAD_CODE = { typhoon = "typn", rafale = "rflm", adfx02 = "adfx" }   -- (an ace key's blueprint code, where it differs)
local function blueprint(name) return name:match("^(BP_.-)_C_%d+$") or name:match("^(BP_.-)_C$") or name end
local function leadIs(bp, other, want)           -- bp is the lead's blueprint and `other` a wing's (want: the lead's code)
    if bp == other then return false end
    local a, b = bp:match("^BP_OP%d+_(%w+)_"), other:match("^BP_OP%d+_(%w+)_")
    if a ~= want then return false end
    if b ~= want then return true end
    return bp:find("_CP_Named", 1, true) ~= nil and not other:find("_CP_Named", 1, true)   -- (named models: leads only)
end
local function leadCheck(rec)
    local L = D and D.leadRow and D.leadRow[rec.unit]
    if not L or L.said then return end
    L.bps = L.bps or {}
    L.bps[rec.k] = blueprint(rec.name)
    local b0, b1 = L.bps[0], L.bps[1]
    if not (b0 and b1) then return end
    L.said = true
    local want = LEAD_CODE[L.code] or L.code
    local verdict = (leadIs(b0, b1, want) and "k 0 is the lead: creation order = desc order")
        or (leadIs(b1, b0, want) and "k 0 is NOT the lead: creation order isn't desc order")
        or (b0 == b1 and "can't tell: lead and wings fly one blueprint") or "can't tell from these two"
    log(string.format("spawn index: %s, lead row %s (%s): k 0 is a %s, k 1 a %s; %s", rec.unit, tostring(L.row), tostring(want),
        b0, b1, verdict))
end

function logPlane(o, unit, k)
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
    -- (k: its index in the flight; born: the round clock when it's first logged, for the measurements' kill times)
    -- (addr: KILL.fired's key, and COOP.tornDown's for a copy taken down before the sweep first saw it)
    local rec = { obj = o, name = short, unit = unit, k = k, born = D and D.now or nil, addr = addrOf(o) }
    planes[#planes + 1] = rec
    local where = ""
    pcall(function()
        local l = o:K2_GetActorLocation()
        local dx, dy = l.X - AIRFIELD.X, l.Y - AIRFIELD.Y
        where = string.format(" at (%.1f, %.1f) km, alt %.1f km, %.1f km from the airfield",
            l.X / 100000, l.Y / 100000, l.Z / 100000, math.sqrt(dx * dx + dy * dy) / 100000)
    end)
    log("round probe: AI aircraft created #" .. #planes .. ": " .. short .. (unit and (" (" .. unit .. (k and (", k " .. k) or "") .. ")") or "") .. where)
    if k and unit then pcall(leadCheck, rec) end
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
    -- (0.73.73) none while the level is going away: its containers go with it, and the look for them again (FindAllOf)
    -- walked every object as they were freed (the host's crash on Quit Mission, A20 13:40:38, UE4SS.dll+0x2ab5bd)
    if levelLeaving() then flagCache.at, flagCache.t, flagCache.cs = now, nil, nil; return nil end   -- (0.73.73 review: the hard sign only, so a restart is still seen)
    local cs = flagCache.cs
    -- (a gone container is found by its validity; the timed look again every 120 s, was 30: each FindAllOf walk was a
    -- 22-29 ms hitch in a friend's late rounds, economy review of 2026-10-25. 0.73.73: liveObj, not valid(), on the kept
    -- ones; while the walks are held (walkHold), the ones still live)
    local stale = not cs or now - flagCache.found > 120 or (#cs == 0 and now - flagCache.found > 2)
    local live = {}
    for _, c in ipairs(cs or {}) do if liveObj(c) then live[#live + 1] = c else stale = true end end
    if stale and not walkHold() then cs, flagCache.found = FindAllOf("LiveEventContainer") or {}, now; flagCache.cs = cs
    else cs = live end
    local t = nil
    for _, c in ipairs(cs) do
        if liveObj(c) then
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

-- The flags that count things (SV_Beat, the heartbeat, every 10 s; kills; airfield and shuttle hits): the third value,
-- the line's key for the log, leaves them and the flights up out (sv_main.lua probeTick: the line again for them only
-- with [log] verbose)
local FLAG_COUNTERS = { SV_Alive = true, SV_Kills = true, SV_AirHits = true, SV_Beat = true, SV_ShuttleHits = true }
function flagLine()
    local t = svFlags()
    if not t then return nil end
    local parts, keys, up = {}, {}, 0
    for name, val in pairs(t) do
        if name:sub(1, 6) == "SV_Up_" then
            if val >= 1 then up = up + 1 end
        else
            parts[#parts + 1] = name .. "=" .. tostring(val)
            if not FLAG_COUNTERS[name] then keys[#keys + 1] = parts[#parts] end
        end
    end
    if #parts == 0 then return nil, up end
    table.sort(parts); table.sort(keys)
    return table.concat(parts, " ") .. " flights up (SV_Up_*)=" .. up, up, table.concat(keys, " ")
end

survivalPC = nil             -- the player controller in Survival's level (found by probeTick, then reused)

-- Where the player is (cm), or nil.
-- ((0.73.79, the lag audit's item 7) read once a tick half: ~50 callers asked each time (the controller checked live,
-- its pawn, a ProcessEvent). PLOC.on only while the tick loop's game-thread callback runs (sv_main.lua), so a key or a
-- menu hook reads fresh; numbers only, a copy handed out; playerLocationDirty() after Survival moves your plane in a
-- half (SV_Respawn, SV_Down) or finds the player controller again)
PLOC = { on = false, have = false, v = nil }
function playerLocationDirty() PLOC.have, PLOC.v = false, nil end
function playerLocation()
    if PLOC.on and PLOC.have then
        local v = PLOC.v
        return v and { X = v.X, Y = v.Y, Z = v.Z } or nil
    end
    local pc = liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController")      -- (0.73.73: liveObj, kept)
    local ok, l = pcall(function()
        local v = pc.Pawn:K2_GetActorLocation()
        return { X = v.X, Y = v.Y, Z = v.Z }
    end)
    l = ok and l or nil
    if PLOC.on then PLOC.have, PLOC.v = true, l and { X = l.X, Y = l.Y, Z = l.Z } or nil end
    return l
end

function km(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 100000
end
