-- sv_fleet.lua: INVINCIBLE FLEET's tests (round 30, the user's dev install only: docs/design/INVINCIBLE_FLEET.md,
-- docs/design/INVINCIBLE_FLEET_RISE_FORD.md). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order after
-- sv_spaceport (whose Ford it spawns, SV_Unit_SpFord): a name another part uses is a global of this mod's Lua state, its
-- own helpers stay local. The whole part is one test-only block, which tools/strip_test_only.py takes out of every
-- release and test zip, and tools/dev_only.py out of a TESTER zip (package_release.sh TESTER=1, which keeps every other
-- part's test keys: round 30 is the user's dev install only, AGENTS.md), only this header left there, its settings
-- (CFG.specials.fleet) with it.
--
-- GEOFON is the stock Gerald R. Ford carrier, the Spaceport's SV_Unit_SpFord, spawned here alone (never in a Spaceport
-- round or with its Ford carried into the retake). Its first two look tests (RISE_FORD.md 5, T1 and T2):
--   Ctrl+B in a run   T1, the V-break look (RISE_FORD.md 4.2 (b)): the Ford 3.5 km ahead of you, broadside, invincible, its
--                     deck off (the deck is the Spaceport round's), its own two meshes posed as the V: DamagedStaticMesh
--                     shown, pitched +25 deg (bow up) and 21 m down (the bow copy), VesselMesh pitched -15 deg and 23 m
--                     down with its three slots on their _DAM instances (the stern copy); its four Mk 15s (switched off
--                     too, with parts_off) and two antennas hidden. With `move`, move_after_s on, the two step apart along
--                     the keel and down from Lua (part_m each way over part_s, a step every step_s: 4 a second).
--                     Logged: `geofon: up: ...`, `geofon: break look: bow copy (DamagedStaticMesh) pitch +25 down 21 m,
--                     stern copy (VesselMesh, 3 slots _DAM) pitch -15 down 23 m; 4 parts, 2 antennas hidden` once, and
--                     every 2 s (for log_s after the move) `geofon: break look +T s: bow (x, y, z) m, stern (x, y, z) m,
--                     gap G m`: each copy's origin read back in the ship's frame (x along the keel, bow +, y across, z up
--                     from the ship's origin, its waterline), and G the gap at the waterline between the two flight decks
--                     (deck_m up in each copy) along the keel. A second Ctrl+B takes it off (OFF.down, below).
--                     (RISE_FORD.md 1.5's "15 m apart, 215 m parted" are along each copy's own keel: in the ship's frame
--                     the two decks meet the water ~0 m apart at the break, ~200-220 m once parted 100 m each way and sunk.)
--   Ctrl+G in a run   T2, GEOFON's stages (RISE_FORD.md 4.2 (a)): the Ford alone 4 km ahead, broadside, its deck off, mortal;
--                     each further Ctrl+G takes `hit` (20 %) of its health off (ModifyHealth, as the Spaceport's
--                     finishParts). At 66 % (stage 1) AC8's vessel fire NS_VesselsFireL001 and smoke NS_VesselsSmokeS001
--                     attached to VesselMesh on the deck and the island, a list (VesselMesh's relative roll ramped over
--                     list_s, list_step_max a tick at most) and the Ford's own secondary blast sound; at 33 % (stage 2) more
--                     fire and its hull's slots on dynamic copies of its _DAM instances with Charred_Embers_Brightness x
--                     `embers` (materials "dim"; "dam": the _DAM instances themselves). A system that ends by itself is
--                     spawned again (refire). Logged: `geofon: up: ...`, `geofon: stage N at P % (health H %): F fires, S
--                     smoke, list R deg over T s, M material slots (<route>)`, every 5 s `geofon: +T s: health ...`, and
--                     `geofon: down at +T s (<why>)`; its fires off fx_off_s after.
-- The fleet (WP7's first test, 2026-11-12; docs/design/INVINCIBLE_FLEET_WP7.md): its own units SV_Unit_IF<Key> (never the
-- Spaceport's), each ship on its lane from its course start ~30 km north-west of the runway (tools/survival_events_fleet.py):
--   Ctrl+N in a run   the whole fleet (CFG.specials.fleet.ships: GEOFON, RAVEN, the four Aegis, Mission 22's seven cruisers
--                     and destroyers, two missile-boat pickets) spawned at its course start, 3 every 0.5 s, in formation;
--                     each ship's spawn and `fleet: up: <NAME> (<unit>, <class>): hull <class> at (x, y) km, health H; N
--                     parts: ...; its box: <NAME> / <CLASS>`, then `fleet: Ctrl+N: 15 of 15 ships up with N parts at their
--                     course start (...); GEOFON D km from you, bearing B: fly there`; a ship not under way 15 s on gets its
--                     lane again (RE_SV_IFGo<Key>); every 10 s a line a ship (GEOFON: its place, km from the runway and you,
--                     speed, heading, health, parts up; the others: km from GEOFON, m off their formation spot, speed,
--                     heading, health, parts up) and `fleet: +T s weapons (since the last line): <ship> <part class>
--                     <weapon> xN; ...; N of M parts fired`; a sunk ship once. Again: the fleet taken off (RE_SV_IFFleetRemove,
--                     then OFF.down). Its rows go into the game's tables at the main menu (sv_main.lua calls the setup:
--                     `fleet: rows at the main menu: ...`): with any missing, Ctrl+N refuses. A unit still up from before:
--                     RE_SV_IFFleetRemove and the fleet held up to clear_s for it, never spawned beside it.
-- Taking a test's ships off (OFF.down; the review of 8ca3195): never off the spawner's list by force with their objects up
-- (0.74.11's crash D, 0.74.48's STORE crash: a unit actor destroyed under its living objects), but the way every special's
-- leftovers go (sv_rounds.lua SPC.cleanUp): each object finished off (else switched off), each unit looked at 2 s on and
-- taken off the list then, one with nothing of it alive one each 0.5 s (SPC.cleanTick, SPC.recycleLater). A key that would
-- spawn a unit still being taken off, or still up, refuses (again in a few seconds). The three keys refuse in the landing
-- STORE (its minigame holds the world's AI: a spawn or a removal there was 0.74.11's and 0.74.48's case), and the fleet's
-- clock waits there as it does while paused.
-- Each kept object (the hull, its meshes, its parts, the effects) is checked to be the one captured (its address and its
-- name, hard rule 59) before anything is done to it; nothing moves while the game is paused (hard rule 60); every call
-- into the game is in a pcall and a failure is logged (these are look tests: a call the game doesn't take must say so).
-- TEST ONLY BEGIN (INVINCIBLE FLEET's tests: test builds only; docs/design/INVINCIBLE_FLEET_RISE_FORD.md 5, T1 and T2)
CFG.specials.fleet = {
    geofon = {
        unit = "SV_Unit_SpFord", z_cm = 50,                  -- (the Spaceport's Ford, at its world data's height)
        settle_s = 1.5,                                       -- (its objects looked at this long after the spawn)
        deck_m = 21,                                          -- (its flight deck above its origin: RISE_FORD.md 1.4)
        -- (a slot's _DAM is found up its own material's chain, as sv_anomalies.lua's dead look; else MI_VE004_grfd_0<n>_DAM here)
        mats = "/Game/Vehicles/Vessels/VE004_gfrd/Materials/01/",
        fire = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsFireL001",
        smoke = "/Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/NS_VesselsSmokeS001",
        sound = "/Game/WwiseAssets/Events/CS_AceLive_SE/Events_General/EXP/SEA/SE_GEN_EXP_SEA_VE004_grfd/"
             .. "AKE_GEN_EXP_SEA_VE004_grfd_Body_Killed_Secondary_Play",
        -- T1 (Ctrl+B): the V (bow copy DamagedStaticMesh, stern copy VesselMesh), then parted part_m each way along the
        -- keel and sink_m { bow, stern } further down over part_s (the break rig's draft keys at 25 s: 4.2 (c))
        look = { ahead_cm = 350000, bow = { pitch = 25, down_m = 21 }, stern = { pitch = -15, down_m = 23 },
                 parts_off = true, move = true, move_after_s = 10, part_m = 100, part_s = 25, sink_m = { 4, 3 },
                 step_s = 0.25, every_s = 2, log_s = 30 },
        -- T2 (Ctrl+G): at a health share of `at` or under. Offsets in metres on VesselMesh (x along the keel, bow +; y across,
        -- starboard +; z up from its origin): the deck at 21 m, the island at x -110..-70 on the starboard side, its top
        -- 61 m. roll_deg: the list's whole angle by then.
        stages = {
            { at = 0.66, fires = { { 60, -12, 21 }, { -88, 30, 40 } }, smoke = { { -90, 30, 61 }, { 60, -12, 22 } },
              roll_deg = 2, list_s = 20 },
            { at = 0.33, fires = { { 125, 5, 21 }, { -20, -25, 21 }, { -150, 0, 21 } }, smoke = { { -20, -25, 22 } },
              roll_deg = 5, list_s = 30, materials = "dim", embers = 0.2 },
        },
        test = { ahead_cm = 400000, hit = 0.20, fx_scale = 1, list_step_max = 0.1, refire = true, every_s = 5, fx_off_s = 30 },
    },
    -- (2026-11-12) WP7, the fleet (Ctrl+N; docs/design/INVINCIBLE_FLEET_WP7.md). The ships as the build makes them
    -- (tools/survival_events_fleet.py IF_SHIPS, which the build checks this table against): the name on its box ("" an
    -- unnamed ship, its class's), its Key (unit SV_Unit_IF<Key>, rows SV_IF_<Key> / SV_Model_Fleet_<Key>, its name's key
    -- SV_FleetName_<Key>, lane SV_Path_IF<Key>, RE_SV_IFGo<Key>), its class, and its spot in GEOFON's frame as the fleet
    -- sails in (metres ahead, metres to starboard; the lanes keep it in the world's frame: a translation of GEOFON's course)
    ships = {
        { name = "GEOFON", key = "Geofon", kind = "ford", fwd_m = 0, right_m = 0 },
        { name = "RAVEN", key = "Raven", kind = "aegis", fwd_m = 0, right_m = 600 },
        { name = "CONDOR", key = "Condor", kind = "aegis", fwd_m = 1061, right_m = 1061 },
        { name = "FINCH", key = "Finch", kind = "aegis", fwd_m = -1061, right_m = 1061 },
        { name = "SPARROW", key = "Sparrow", kind = "aegis", fwd_m = -1061, right_m = -1061 },
        { name = "MAGPIE", key = "Magpie", kind = "aegis", fwd_m = 1061, right_m = -1061 },
        { name = "BELUGA", key = "Beluga", kind = "krov", fwd_m = 3500, right_m = 0 },
        { name = "KOLGA", key = "Kolga", kind = "udal", fwd_m = 2182, right_m = 2736 },
        { name = "HERNE", key = "Herne", kind = "grig", fwd_m = -779, right_m = 3412 },
        { name = "TAISCH", key = "Taisch", kind = "grig", fwd_m = -3153, right_m = 1519 },
        { name = "THIASSI", key = "Thiassi", kind = "grig", fwd_m = -3153, right_m = -1519 },
        { name = "LAZULI", key = "Lazuli", kind = "grig", fwd_m = -779, right_m = -3412 },
        { name = "FENRIS", key = "Fenris", kind = "gors", fwd_m = 2182, right_m = -2736 },
        { name = "", key = "PicketA", kind = "boat", fwd_m = 5000, right_m = 1000 },
        { name = "", key = "PicketB", kind = "boat", fwd_m = 5000, right_m = -1000 },
    },
    -- each class's second line on the box (its hull row's GameObjectDisplayName02 is SV_FleetClass_<Class>) and the log's
    classes = { ford = "CARRIER", aegis = "AEGIS", krov = "BATTLECRUISER", gors = "FRIGATE", udal = "DESTROYER",
                grig = "FRIGATE", boat = "MISSILE BOAT" },
    -- Mission 22's ships' turrets on Survival's rows (IF_TURRETS' DT_NPC rows, the build checks them; the Ford's and the
    -- Aegis's fly the Spaceport's, SPORT.FLEET_ROWS): put into DT_NPC at the main menu, each weapon on the Spaceport
    -- fleet's fire control (<FCS>_SVA_Fleet, sv_allies.lua) where that clone exists, else its stock one (WP9's to make)
    turret_rows = { "SV_IFF_UdalGun", "SV_IFF_UdalArt", "SV_IFF_GrigArt", "SV_IFF_GrigGunL", "SV_IFF_GrigGunR",
                    "SV_IFF_GorsVls", "SV_IFF_GorsArt", "SV_IFF_GorsPalmaCiws", "SV_IFF_GorsPalmaGun", "SV_IFF_KrovGun",
                    "SV_IFF_KrovArt", "SV_IFF_KrovSam", "SV_IFF_KrovVls" },
    -- Ctrl+N: the ships spawned per_step every gap_s at their course start (their units' own spots, ~30 km north-west of
    -- the runway: survival_events_fleet.py IF_START_KM), each looked at settle_s after its spawn; a ship not go_s on its
    -- way moved_m after its spawn gets its lane again (RE_SV_IFGo<Key>); every every_s a line a ship and a weapons line;
    -- guns_s: how often its parts' shells are looked for (a LiveBullet walk, ~40 ms; 0: never); clear_s: how long the fleet
    -- waits for ships still up from before to go after RE_SV_IFFleetRemove (the Spaceport's CLEAR_S). course_yaw, runway_cm:
    -- the course in and the runway's centre (survival_events_fleet.py IF_YAW, IF_RUNWAY), for the lines
    formation = { per_step = 3, gap_s = 0.5, settle_s = 2, go_s = 15, moved_m = 50, every_s = 10, guns_s = 2, clear_s = 8,
                  course_yaw = 45, runway_cm = { 1610476, -436143 } },
}
-- (set after sv_config_ini.lua took CFG_DEFAULTS: shipped as it is, so no difference the leaderboard's LB.edited or the
-- co-op settings sync would see)
if type(CFG_DEFAULTS) == "table" and type(CFG_DEFAULTS.specials) == "table" and type(deepCopy) == "function" then
    CFG_DEFAULTS.specials.fleet = deepCopy(CFG.specials.fleet)
end

-- The keys' guards and a test's units taken off (the header's "Taking a test's ships off"; GEO's and IFLEET's)
local OFF = {}
do
-- the landing STORE open (sv_coop_sync.lua's inStore: its music held, the STORE's widget shown)
function OFF.store() return D ~= nil and D.musicHold == 1 and not (LANDW ~= nil and LANDW.wasShown == false) end
-- SV_UnitAlive in a pcall: the unit's objects alive (0 on an error or with no runtime; -7 is a unit off the list)
function OFF.alive(unit)
    if type(SV_UnitAlive) ~= "function" then return 0 end
    local ok, n = pcall(SV_UnitAlive, unit)
    return ok and tonumber(n) or 0
end
-- in SPC's clean-up checks or its queue off the spawner's list (sv_rounds.lua SPC.cleanQ / SPC.recycleQ)
function OFF.queued(unit)
    for _, q in ipairs({ SPC and SPC.cleanQ or {}, SPC and SPC.recycleQ or {} }) do
        for _, e in ipairs(q) do if type(e) == "table" and e.unit == unit then return true end end
    end
    return false
end
-- units (names) taken down with their objects objs[unit] = { obj, ... } (each checked by the caller to be the one it
-- captured: hard rule 59): wake, the living ones switched on first (an inactive object takes no damage: 0.74.48's
-- ZLAUNCH.parkedOff); each one finished off, else switched off (SPC.cleanUp, mortal: the host's), the units looked at 2 s
-- on and off the spawner's list then. How many objects it took down, or nil and why
function OFF.down(units, objs, why, wake)
    if not (SPC and type(SPC.cleanUp) == "function" and type(SPC.CLEAN_OBJ) == "table") then
        return nil, "no SPC.cleanUp in this runtime: left as they are"
    end
    for _, u in ipairs(units) do
        local l = { at = os.clock() }
        for _, o in ipairs(objs[u] or {}) do
            if wake then
                local okH, h = pcall(function() return o.HealthInternal end)
                if not (okH and type(h) == "number" and h <= 0) then pcall(function() o:SetActive(true, false, false) end) end
            end
            l[#l + 1] = o
        end
        SPC.CLEAN_OBJ[u] = l                              -- (SPC.cleanUp's record of the unit: finished off, no pay)
    end
    local ok, n = pcall(SPC.cleanUp, units, why, true, (D and tonumber(D.now)) or 0)
    if not ok then return nil, "SPC.cleanUp error " .. tostring(n) end
    return tonumber(n) or 0
end
end

-- GEO.look: T1's state, GEO.cur: T2's (each { raw, t, hull, parts, m, ... }); GEO.catching: the objects SV_Spawn is making
GEO = { look = nil, cur = nil, catching = nil }
do
local FORD = CFG.specials.fleet.geofon.unit
local MESHES = { "VesselMesh", "DamagedStaticMesh", "SM_VE004_grfd_antenna_01", "SM_VE004_grfd_antenna_02" }
local function gc() return CFG.specials.fleet.geofon end
local function short(o) return (nameOf(o):match("([^%.:]+)$")) or "?" end
local function fname(c)                                  -- a component's own name (VesselMesh), else its object name
    local n
    pcall(function() n = c:GetFName():ToString() end)
    return type(n) == "string" and n or short(c)
end
local function joiner() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function paused() return type(gamePaused) == "function" and gamePaused(survivalPC) == true end
local function num(v, d) v = tonumber(v); return v or d end

-- a live object kept between ticks: { obj, addr, name } (hard rule 59: same() before each use; quiet: an effect, whose
-- address the game reuses once it ends by itself, isn't logged)
local function keep(o, quiet)
    local a = o ~= nil and liveAddr(o)
    if not a then return nil end
    return { obj = o, addr = a, name = nameOf(o), quiet = quiet }
end
local function same(e)
    if not e or e.reused then return false end
    if liveAddr(e.obj) ~= e.addr then return false end
    if nameOf(e.obj) ~= e.name then
        e.reused = true
        if not e.quiet then
            log(string.format("geofon: %s's address is another object's now (%s): left alone", (tostring(e.name):match("([^%.:]+)$")) or "?",
                short(e.obj)))
        end
        return false
    end
    return true
end
local function asset(path)
    if SPC and SPC.V and SPC.V.asset then
        local o = SPC.V.asset(path)
        if o then return o end
    end
    return (loadObject(path .. "." .. path:match("[^/]+$")))
end
local function hp(e)
    local ok, h = pcall(function() return e.obj.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end

-- every LiveAIGameObject the spawner makes while GEO.catching is open and spawningUnit is the Ford (as SPORT.shipObjs)
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local l = GEO.catching
    if l and spawningUnit == FORD and #l < 16 then l[#l + 1] = o end
end)

-- ((the review of 8ca3195, finding 1) until then a Ford still up was forced off the spawner's list here with its objects
-- up, SV_Recycle(unit, 1), and spawned again beside them) the Ford still being taken off, or still up from before: why
-- it isn't spawned now, or nil
local function fordBusy()
    if OFF.queued(FORD) then return FORD .. " is still being taken off (its clean-up's look, or its turn off the spawner's list)" end
    local n0 = OFF.alive(FORD)
    if n0 > 0 then
        return string.format("%s is still up from before (%d up) and none of its objects are known here: not spawned beside it, "
            .. "nor forced off the spawner's list with them up (a new run takes it off)", FORD, n0)
    end
    return nil
end

-- the Ford spawned alone ahead_cm in front of you, broadside: its state { raw = the objects made, kept = each one kept
-- (keep) as SV_Spawn returns, t = 0, ... } or nil, why
local function spawnFord(ahead, tag)
    local busy = fordBusy()
    if busy then return nil, busy .. " (again in a few seconds)" end
    local p = playerLocation()
    if not p then return nil, "no player location" end
    local yaw = 0
    pcall(function()
        local pc = liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController")
        yaw = pc.Pawn:K2_GetActorRotation().Yaw
    end)
    yaw = num(yaw, 0)
    local x = p.X + math.cos(math.rad(yaw)) * ahead
    local y = p.Y + math.sin(math.rad(yaw)) * ahead
    local face = (yaw + 90) % 360                         -- (broadside to you: its whole length in view)
    GEO.catching = {}
    spawningUnit = FORD
    local ok, r = pcall(SV_Spawn, FORD, x, y, gc().z_cm, face)
    spawningUnit = nil
    local raw = GEO.catching
    GEO.catching = nil
    local kept = {}                                       -- (each object as it was made: its address and name, hard rule 59)
    for _, o in ipairs(raw) do local e = keep(o); if e then kept[#kept + 1] = e end end
    r = ok and tonumber(r) or -5
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, FORD, r) end
    local said = r > 0 and (r .. " up") or ("not spawned (" .. tostring((SV_ERR and SV_ERR[r]) or (ok and r) or "error") .. ")")
    log(string.format("geofon: %s, %s at (%.0f, %.0f, %g) facing %.0f (you at yaw %.0f): %s; %d objects made%s; its deck off (the "
        .. "Spaceport round's only)", tag, FORD, x, y, num(gc().z_cm, 50), face, yaw, said, #raw, ok and "" or (": " .. tostring(r))))
    if r <= 0 then return nil, said end
    return { raw = raw, kept = kept, t = 0, last = os.clock(), tries = 0, x = x, y = y, face = face }
end

-- (a mesh) its attach parent, or nil
local function parentOf(c)
    local p
    pcall(function() p = c:GetAttachParent() end)
    if not (p and valid(p)) then p = nil; pcall(function() p = c.AttachParent end) end
    return (p and valid(p)) and p or nil
end
-- (a mesh) its relative transform as built (cm, deg)
local function relOf(c)
    local b = { X = 0, Y = 0, Z = 0, P = 0, Yw = 0, R = 0, read = false }
    pcall(function()
        local v = c.RelativeLocation
        b.X, b.Y, b.Z, b.read = num(v.X, 0), num(v.Y, 0), num(v.Z, 0), true
    end)
    pcall(function()
        local r = c.RelativeRotation
        b.P, b.Yw, b.R = num(r.Pitch, 0), num(r.Yaw, 0), num(r.Roll, 0)
    end)
    return b
end

-- G's objects sorted at settle_s: the hull (the Ford's object that isn't a Mk 15), its parts, its meshes by name
-- (SPC.V.comps' walk of its component tree, else its blueprint variables): G.m[name] = { e, name, base, home, parent,
-- isRoot, onOther }. The `geofon: up` line. True once the hull is found.
local function capture(G)
    local hull, parts, other = nil, {}, 0
    for _, e in ipairs(G.kept or {}) do                   -- (as they were made: still each one, hard rule 59)
        if same(e) then
            local low = e.name:lower()
            if not low:find("grfd", 1, true) then other = other + 1
            elseif low:find("mk15", 1, true) then parts[#parts + 1] = e
            elseif not hull then hull = e
            else other = other + 1 end
        end
    end
    if not hull then return false, string.format("no hull among its %d objects (%d parts, %d others)", #(G.raw or {}), #parts, other) end
    local by, nStatic = {}, 0
    if SPC and SPC.V and SPC.V.comps then
        local ok, list = pcall(SPC.V.comps, hull.obj, "/Script/Engine.StaticMeshComponent")
        if ok and type(list) == "table" then
            nStatic = #list
            for _, c in ipairs(list) do local n = fname(c); if by[n] == nil then by[n] = c end end
        end
    end
    for _, n in ipairs(MESHES) do                         -- (else the blueprint's own variable of that name)
        if by[n] == nil then
            local ok, c = pcall(function() return hull.obj[n] end)
            if ok and c and valid(c) then by[n] = c end
        end
    end
    local root
    pcall(function() root = hull.obj:K2_GetRootComponent() end)
    if not (root and valid(root)) then root = nil; pcall(function() root = hull.obj.RootComponent end) end
    local rootA = (root and valid(root)) and addrOf(root) or nil
    G.hull, G.parts, G.m, G.root = hull, parts, {}, rootA
    local said = {}
    for _, n in ipairs(MESHES) do
        local c = by[n]
        local e = c and keep(c)
        if e then
            local par = parentOf(c)
            local vis = "?"
            pcall(function() vis = c:IsVisible() and "shown" or "hidden" end)
            G.m[n] = { e = e, name = n, base = relOf(c), parent = par and addrOf(par) or nil, isRoot = rootA ~= nil and e.addr == rootA }
            said[#said + 1] = string.format("%s (%s, %s)", n, G.m[n].isRoot and "the actor's root" or
                ("on " .. (par and fname(par) or "?")), vis)
        else
            said[#said + 1] = n .. " NOT found"
        end
    end
    -- the two copies' origins in the ship's frame as built (its base, and the other copy's when it hangs on it; a copy that
    -- is the actor's root is the ship's frame itself: never moved, its relative transform the actor's place)
    local vm, dm = G.m.VesselMesh, G.m.DamagedStaticMesh
    for _, pair in ipairs({ { vm, dm }, { dm, vm } }) do
        local a, b = pair[1], pair[2]
        if a then
            a.onOther = b ~= nil and not b.isRoot and a.parent ~= nil and a.parent == b.e.addr
            local h = { X = a.base.X, Y = a.base.Y, Z = a.base.Z, P = a.base.P }
            if a.onOther then h.X, h.Y, h.Z, h.P = h.X + b.base.X, h.Y + b.base.Y, h.Z + b.base.Z, h.P + b.base.P end
            a.home = h
        end
    end
    local h = hp(hull)
    local okM, mx = pcall(function() return hull.obj.MaxHealth end)
    mx = (okM and type(mx) == "number") and mx * 10 or 0
    G.max = math.max(mx, h or 0)
    log(string.format("geofon: up: %s %s, health %s (of %s), components: %s; %d parts; root %s, %d static meshes found%s", FORD,
        short(hull.obj), h and string.format("%.0f", h) or "?", G.max > 0 and string.format("%.0f", G.max) or "?",
        table.concat(said, ", "), #parts, root and fname(root) or "?", nStatic,
        other > 0 and string.format(" (%d other objects)", other) or ""))
    return true
end
-- the captures retried each second up to 5 times; false once given up
local function settled(G, what)
    if G.hull then return true end
    if G.t < gc().settle_s + G.tries then return nil end
    local ok, why = capture(G)
    if ok then return true end
    G.tries = G.tries + 1
    if G.tries >= 5 then log("geofon: " .. what .. ": given up (" .. tostring(why) .. ")"); return false end
    return nil
end

-- the effects on it (G.fx: { e, path, off, stage }) off: deactivated now, destroyed `after` seconds on (0: at once)
local function fxOff(G, after)
    for _, f in ipairs(G.fx or {}) do
        if same(f.e) and not f.offAt then
            pcall(function() f.e.obj:Deactivate() end)
            f.offAt = os.clock() + (after or 0)
        end
    end
end
local function fxGone(G, all)
    local keepFx = {}
    for _, f in ipairs(G.fx or {}) do
        if f.offAt and (all or os.clock() >= f.offAt) then
            if same(f.e) and not pcall(function() f.e.obj:K2_DestroyComponent(f.e.obj) end) then
                pcall(function() f.e.obj:DestroyComponent() end)
            end
        else
            keepFx[#keepFx + 1] = f
        end
    end
    G.fx = keepFx
end

-- a test's Ford taken off (OFF.down: every object made at its spawn that's still the one, its switched-off parts on again
-- first, finished off; the unit off the spawner's list from 2 s on, never by force with them up: the review of 8ca3195,
-- finding 1, where it was hidden and forced off at once, SV_Recycle(unit, 1)); what was done
local function takeOff(G, why)
    fxOff(G, 0)
    fxGone(G, true)
    local l = {}
    for _, e in ipairs(G.kept or {}) do if same(e) then l[#l + 1] = e.obj end end
    if COOP and COOP.host and COOP.host() and COOP.removeNow then pcall(COOP.removeNow, FORD) end
    crumb("geofon: " .. FORD .. " taken down (" .. why .. ")")
    local n, err = OFF.down({ FORD }, { [FORD] = l }, "GEOFON's test taken off (" .. why .. ")", true)
    return n and string.format("%d of its %d objects finished off or switched off (off the spawner's list from 2 s on)", n, #l)
        or tostring(err)
end

---------------------------------------------------------------------------------------------------- T1, the V-break look
-- (UE: +pitch noses up) (x, z) turned by a pitch of deg: a parent's RotateVector in its x-z plane
local function rotP(x, z, deg)
    local a = math.rad(deg)
    local c, s = math.cos(a), math.sin(a)
    return x * c - z * s, x * s + z * c
end
-- the two copies' poses at move fraction f, in the ship's frame (cm, deg): bow, stern
local function poseAt(f)
    local c = gc().look
    local sink, part = c.sink_m or { 0, 0 }, num(c.part_m, 0) * 100 * f
    return { x = part, y = 0, z = -(num(c.bow.down_m, 21) + num(sink[1], 0) * f) * 100, p = num(c.bow.pitch, 25) },
           { x = -part, y = 0, z = -(num(c.stern.down_m, 23) + num(sink[2], 0) * f) * 100, p = num(c.stern.pitch, -15) }
end
-- mesh m put at pose q on its home; on the other copy's frame when it hangs on it (o at oq)
local function place(m, q, o, oq)
    local tx, ty, tz, tp = m.home.X + q.x, m.home.Y + q.y, m.home.Z + q.z, m.home.P + q.p
    local loc, rot
    if m.onOther and o then
        local ox, oy, oz, op = o.home.X + oq.x, o.home.Y + oq.y, o.home.Z + oq.z, o.home.P + oq.p
        local rx, rz = rotP(tx - ox, tz - oz, -op)
        loc, rot = { X = rx, Y = ty - oy, Z = rz }, { Pitch = tp - op, Yaw = m.base.Yw, Roll = m.base.R }
    else
        loc, rot = { X = tx, Y = ty, Z = tz }, { Pitch = tp, Yaw = m.base.Yw, Roll = m.base.R }
    end
    local ok, err = pcall(function() m.e.obj:K2_SetRelativeLocationAndRotation(loc, rot, false, {}, true) end)
    if not ok then logOnce("geofon place " .. m.name, "geofon: " .. m.name .. " not posed (K2_SetRelativeLocationAndRotation): " .. tostring(err)) end
    return ok
end
-- both copies at move fraction f; whether each was put ("root": it's the actor's own, never moved)
local function posePair(L, f)
    local qb, qs = poseAt(f)
    local b, s = L.m.DamagedStaticMesh, L.m.VesselMesh
    local okB, okS = "not found", "not found"
    if s then okS = s.isRoot and "root" or (same(s.e) and place(s, qs, b, qb)) end
    if b then okB = b.isRoot and "root" or (same(b.e) and place(b, qb, s, qs)) end
    L.f = f
    return okB, okS
end

-- the actor's place and yaw, a component's origin in its frame (m) and its world pitch
local function frame(o)
    local ok, l = pcall(function() local v = o:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not (ok and l) then return nil end
    local yaw = 0
    pcall(function() yaw = num(o:K2_GetActorRotation().Yaw, 0) end)
    return l, yaw
end
local function inFrame(c, l, yaw)
    local ok, v = pcall(function() local w = c:K2_GetComponentLocation(); return { X = w.X, Y = w.Y, Z = w.Z } end)
    if not (ok and v and l) then return nil end
    local a = math.rad(yaw)
    local dx, dy = v.X - l.X, v.Y - l.Y
    local p, r
    pcall(function() local w = c:K2_GetComponentRotation(); p, r = tonumber(w.Pitch), tonumber(w.Roll) end)
    if p == nil then                                      -- ((0.74.63) the user's run of 0.74.62: every pitch "?": rotators
        pcall(function()                                  -- don't read from Lua (0.74.55); its +X as a vector does
            local f = c:GetForwardVector()
            local n = math.sqrt(f.X * f.X + f.Y * f.Y + f.Z * f.Z)
            if n > 1e-6 then p = math.deg(math.asin(math.max(-1, math.min(1, f.Z / n)))) end
        end)
    end
    return { x = (dx * math.cos(a) + dy * math.sin(a)) / 100, y = (-dx * math.sin(a) + dy * math.cos(a)) / 100, z = (v.Z - l.Z) / 100,
             p = p, r = r }
end
-- where a copy's flight deck (h m up in it) meets the water (the ship's origin's height), along the keel (m); nil if level
local function waterX(q, h)
    if not (q and q.p) then return nil end
    local a = math.rad(q.p)
    local s, c = math.sin(a), math.cos(a)
    if math.abs(s) < 0.01 then return nil end
    local u = -(q.z + h * c) / s
    return q.x + u * c - h * s
end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 + 0.0 end    -- (to 0.1, never "-0.0")
local function xyz(q) return q and string.format("(%.1f, %.1f, %.1f)", r1(q.x), r1(q.y), r1(q.z)) or "(?)" end

-- the material slots of mesh m on their _DAM instances: route "dam" (the instances) or "dim" (dynamic copies of them, their
-- Charred_Embers_Brightness x embers, as sv_zfa44.lua makes its instances); slots set, slots, what each got
local function damFor(comp, i)                            -- (slot i's own _DAM: its material's asset + "_DAM")
    local dam, src
    pcall(function()
        local m = comp:GetMaterial(i)
        for _ = 1, 4 do
            local pkg, obj = m:GetPathName():match("^(/Game/[^%.:]+)%.([^%.:]+)$")
            if pkg then
                src = obj
                dam = obj:find("_DAM$") and m or loadObject(pkg .. "_DAM." .. obj .. "_DAM")
                break
            end
            m = m.Parent
            if not (m and valid(m)) then break end
        end
    end)
    if not (dam and valid(dam)) then
        local n = string.format("MI_VE004_grfd_%02d_DAM", i + 1)
        dam = loadObject(gc().mats .. n .. "." .. n)
        src = (src or "?") .. " (by its number)"
    end
    return (dam and valid(dam)) and dam or nil, src or "?"
end
local function damSlots(m, route, embers)
    if not (m and same(m.e)) then return 0, 0, "VesselMesh not there" end
    local comp = m.e.obj
    local okN, n = pcall(function() return comp:GetNumMaterials() end)
    n = (okN and type(n) == "number") and n or 0
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local done, said = 0, {}
    for i = 0, n - 1 do
        local dam, src = damFor(comp, i)
        if dam then
            local put, how = false, "_DAM"
            if route == "dim" then
                local mid
                local okC, r = pcall(function() return comp:CreateDynamicMaterialInstance(i, dam, FName("None")) end)
                if okC and r and valid(r) then mid = r end
                if not mid and valid(kml) and liveObj(survivalPC) then
                    local okK, r2 = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, dam, FName("None"), 0) end)
                    if okK and r2 and valid(r2) then mid = r2 end
                end
                if mid then
                    local b
                    pcall(function() b = mid:K2_GetScalarParameterValue(FName("Charred_Embers_Brightness")) end)
                    local v = (type(b) == "number" and b > 0 and b or 650000) * num(embers, 0.2)
                    local okS = pcall(function() mid:SetScalarParameterValue(FName("Charred_Embers_Brightness"), v) end)
                    put = pcall(function() comp:SetMaterial(i, mid) end)
                    how = string.format("a dimmed copy, embers %s -> %.0f%s", type(b) == "number" and string.format("%.0f", b) or "? (650000 taken)",
                        v, okS and "" or " (NOT set)")
                end
            end
            if not put then
                put = pcall(function() comp:SetMaterial(i, dam) end)
                how = route == "dim" and "no copy made: the _DAM instance" or "_DAM"
            end
            if put then done = done + 1 end
            said[#said + 1] = string.format("slot %d %s -> %s %s", i, src, short(dam), put and how or "NOT set")
        else
            said[#said + 1] = string.format("slot %d %s: no _DAM found", i, src)
        end
    end
    return done, n, #said > 0 and table.concat(said, ", ") or "no slots"
end

-- (T1, at settle_s) the hull invincible, its parts and antennas hidden, the bow copy shown, the stern copy's slots _DAM,
-- the V posed; the once line
local function lookSetup(L)
    local c = gc().look
    local h = L.hull
    local inv = pcall(function() h.obj:SetIsInvincible(true) end)
    pcall(function() h.obj.bIsInvincible = true end)
    local parts, off = 0, 0
    for _, e in ipairs(L.parts) do
        if same(e) then
            for f, v in pairs(SPC and SPC.V and SPC.V.PART_FLAGS or { bShowHUDBox = false, bIsNotLockonTarget = true,
                                                                        bIsNotFCSTargets = true, bIsInvincible = true }) do
                pcall(function() e.obj[f] = v end)
            end
            if pcall(function() e.obj:SetActorHiddenInGame(true) end) then parts = parts + 1 end
            if c.parts_off ~= false and pcall(function() e.obj:SetActive(false, false, false) end) then off = off + 1 end
        end
    end
    local ant = 0
    for _, n in ipairs({ "SM_VE004_grfd_antenna_01", "SM_VE004_grfd_antenna_02" }) do
        local m = L.m[n]
        if m and same(m.e) and pcall(function() m.e.obj:SetVisibility(false, false) end) then ant = ant + 1 end
    end
    local b, s = L.m.DamagedStaticMesh, L.m.VesselMesh
    local shown = b and same(b.e) and pcall(function() b.e.obj:SetVisibility(true, false) end)
    if shown then pcall(function() b.e.obj:SetHiddenInGame(false, false) end) end
    local slots, nSlots, slotSaid = damSlots(s, "dam")
    local okB, okS = posePair(L, 0)
    L.posed, L.poseT = true, L.t
    local function said(ok) return ok == true and "" or (" (NOT posed: " .. tostring(ok == false and "the call failed" or ok) .. ")") end
    log(string.format("geofon: break look: bow copy (DamagedStaticMesh%s) pitch %+g down %g m%s, stern copy (VesselMesh, %d slots _DAM) "
        .. "pitch %+g down %g m%s; %d parts, %d antennas hidden", shown and "" or ", NOT shown", num(c.bow.pitch, 25), num(c.bow.down_m, 21),
        said(okB), slots, num(c.stern.pitch, -15), num(c.stern.down_m, 23), said(okS), parts, ant))
    log(string.format("geofon: break look: the hull %s; its parts %s; the stern copy's slots: %s (%d of %d); %s; the copies' "
        .. "frames: bow %s, stern %s", inv and "invincible" or "NOT made invincible (SetIsInvincible failed)",
        c.parts_off ~= false and string.format("switched off (%d of %d)", off, #L.parts) or "only hidden", slotSaid, slots, nSlots,
        c.move and string.format("move: %g m each way and %s m down over %g s from +%g s, a step every %.2f s", num(c.part_m, 0),
            table.concat(c.sink_m or { 0, 0 }, " / "), num(c.part_s, 25), num(c.move_after_s, 0), num(c.step_s, 0.25)) or "no move",
        b and (b.onOther and "on VesselMesh" or "on its own parent") or "?", s and (s.onOther and "on DamagedStaticMesh" or "on its own parent") or "?"))
    hudCallout("TEST: GEOFON V-BREAK", "3.5 KM AHEAD")
end

-- (every every_s) the two copies read back: where they are, their gap at the waterline; a copy the game put back posed
-- again (and every tick after), a bow copy hidden again shown again
local function lookLine(L)
    local l, yaw = frame(L.hull.obj)
    local b, s = L.m.DamagedStaticMesh, L.m.VesselMesh
    local qb = b and same(b.e) and inFrame(b.e.obj, l, yaw) or nil
    local qs = s and same(s.e) and inFrame(s.e.obj, l, yaw) or nil
    local h = num(gc().deck_m, 21)
    local xb, xs = waterX(qb, h), waterX(qs, h)
    local notes = {}
    local wb, ws = poseAt(L.f or 0)
    for _, k in ipairs({ { qb, wb, b, "bow" }, { qs, ws, s, "stern" } }) do
        local q, w, m = k[1], k[2], k[3]
        local put = m and m.home and (m.home.P + w.p)
        if q and q.p and put and not m.isRoot and math.abs(q.p - put) > 2 and not L.repose then
            L.repose = true
            notes[#notes + 1] = string.format("the %s copy NOT where it was put (pitch %.1f, put %+.0f): posed again every tick from now",
                k[4], q.p, put)
        end
    end
    if b and same(b.e) then
        local okV, vis = pcall(function() return b.e.obj:IsVisible() end)
        if okV and vis == false then
            pcall(function() b.e.obj:SetVisibility(true, false) end)
            notes[#notes + 1] = "the bow copy hidden again: shown again"
        end
    end
    log(string.format("geofon: break look +%.0f s: bow %s m, stern %s m, gap %s m; pitch %s / %s%s", L.t, xyz(qb), xyz(qs),
        (xb and xs) and string.format("%.0f", xb - xs) or "?", qb and qb.p and string.format("%+.1f", qb.p) or "?",
        qs and qs.p and string.format("%+.1f", qs.p) or "?", #notes > 0 and ("; " .. table.concat(notes, "; ")) or ""))
end

local function lookTick(now)
    local L = GEO.look
    if not L then return end
    local dt = math.min(1, math.max(0, now - (L.last or now)))
    L.last = now
    if paused() then return end
    L.t = L.t + dt
    local c = gc().look
    if not L.posed then
        local ok = settled(L, "break look")
        if ok == false then                               -- (given up: what it made taken off, never left up)
            GEO.look = nil
            log("geofon: break look given up: " .. takeOff(L, "its capture given up"))
        end
        if ok then lookSetup(L); L.nextLine = L.t end
        if not L.posed then return end
    end
    if not same(L.hull) then
        GEO.look = nil
        log(string.format("geofon: break look over at +%.0f s: its hull is gone (the rest taken off: %s)", L.t,
            takeOff(L, "its hull gone")))
        return
    end
    local moveEnd = L.poseT + num(c.move_after_s, 0) + num(c.part_s, 25)
    if c.move and not L.moveDone then
        local mt = L.t - L.poseT - num(c.move_after_s, 0)
        if mt >= 0 and L.t >= (L.nextStep or 0) then
            L.nextStep = L.t + num(c.step_s, 0.25) - 0.05     -- (one step a tick at the ticks' 0.25 s)
            local f = math.min(1, mt / math.max(1, num(c.part_s, 25)))
            if not L.moveSaid then L.moveSaid = true; log(string.format("geofon: break look +%.0f s: the halves part", L.t)) end
            posePair(L, f)
            if f >= 1 then
                L.moveDone = true
                log(string.format("geofon: break look +%.0f s: parted (%g m each way), held there", L.t, num(c.part_m, 0)))
            end
        end
    elseif L.repose then
        posePair(L, L.f or 0)
    end
    local untilT = (c.move and moveEnd or L.poseT) + num(c.log_s, 30)
    if L.t >= (L.nextLine or 0) then
        L.nextLine = L.t + num(c.every_s, 2) - 0.05
        if L.t <= untilT then lookLine(L)
        elseif not L.linesOff then
            L.linesOff = true
            log(string.format("geofon: break look +%.0f s: no more lines (Ctrl+B takes it off)", L.t))
        end
    end
end

---------------------------------------------------------------------------------------------------- T2, GEOFON's stages
-- a sound where something is (Wwise's PostEventAtLocation, two signatures tried, as sv_escort_laser.lua's)
local SOUND = {}
local function sound(path, where)
    local ev, ak = asset(path), StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
    if not (ev and valid(ak) and liveObj(survivalPC) and where) then
        return "NOT played (" .. (ev and "no Wwise or player controller" or "its event didn't load") .. ")"
    end
    local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
    local tries = { function() return ak:PostEventAtLocation(ev, where, rot, survivalPC) end,
                    function() return ak:PostEventAtLocation(ev, where, rot, "", survivalPC) end }
    local errs = {}
    for i = (SOUND.way or 1), (SOUND.way or #tries) do
        local ok, err = pcall(tries[i])
        if ok then SOUND.way = i; return "played" end
        errs[#errs + 1] = tostring(err)
    end
    return "NOT played (" .. table.concat(errs, "; "):sub(1, 160) .. ")"
end
-- one of AC8's vessel systems attached to VesselMesh at off (m in its frame): its kept component, or nil
local function fxOn(G, path, off)
    local vm = G.m.VesselMesh
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = asset(path)
    if not (valid(lib) and sys and vm and same(vm.e)) then
        logOnce("geofon fx " .. path, "geofon: " .. (path:match("[^/]+$") or "?") .. " not spawned (" .. (sys and "no VesselMesh or Niagara"
            or "it didn't load") .. ")")
        return nil
    end
    local sc = num(gc().test.fx_scale, 1)
    local ok, comp = pcall(function()
        return lib:SpawnSystemAttached(sys, vm.e.obj, FName("None"), { X = off[1] * 100, Y = off[2] * 100, Z = off[3] * 100 },
            { Pitch = 0, Yaw = 0, Roll = 0 }, 0, true, true, 0, true)
    end)
    local e = ok and comp and keep(comp, true) or nil
    if not e then
        logOnce("geofon fx " .. path, "geofon: " .. (path:match("[^/]+$") or "?") .. " didn't come up on VesselMesh: " .. tostring(comp))
        return nil
    end
    if sc ~= 1 then pcall(function() comp:SetWorldScale3D({ X = sc, Y = sc, Z = sc }) end) end
    return e
end
local function burning(f)
    if not same(f.e) then return false end
    local ok, a = pcall(function() return f.e.obj:IsActive() end)
    return ok and a == true
end
local function lit(G)
    local n = 0
    for _, f in ipairs(G.fx) do if burning(f) then n = n + 1 end end
    return n
end

local function stageOn(G, k, st, share)
    local c = gc()
    local nF, nS = 0, 0
    for _, sys in ipairs({ { c.fire, st.fires }, { c.smoke, st.smoke } }) do
        for _, off in ipairs(sys[2] or {}) do
            local e = fxOn(G, sys[1], off)
            if e then
                G.fx[#G.fx + 1] = { e = e, path = sys[1], off = off, stage = k }
                if sys[1] == c.fire then nF = nF + 1 else nS = nS + 1 end
            end
        end
    end
    local vm = G.m.VesselMesh
    local to = num(st.roll_deg, G.rollTo or 0)
    local listSaid
    if vm and vm.isRoot then listSaid = "no list (VesselMesh is the actor's root)"
    else
        G.rollTo, G.rollRate = to, math.abs(to - G.roll) / math.max(1, num(st.list_s, 20))
        listSaid = string.format("list %.1f deg over %g s", to, num(st.list_s, 20))
    end
    local where
    local l = frame(G.hull.obj)
    if l then where = { X = l.X, Y = l.Y, Z = l.Z } end
    local snd = sound(c.sound, where)
    local nM, route = 0, "none at this stage"
    if st.materials then
        local done, n, said = damSlots(vm, st.materials, st.embers)
        nM, route = done, string.format("%s, %d of %d: %s", st.materials, done, n, said)
    end
    log(string.format("geofon: stage %d at %d %% (health %.0f %%): %d fires, %d smoke, %s, %d material slots (%s); its sound %s",
        k, math.floor(num(st.at, 0) * 100 + 0.5), share * 100, nF, nS, listSaid, nM, route, snd))
    hudCallout("TEST: GEOFON STAGE " .. k, string.format("%.0f %% HEALTH", share * 100))
end

local function down(G, why)
    G.down = G.t
    log(string.format("geofon: down at +%.0f s (%s); stages reached %d of %d, %d of its %d systems still burning, ours off in %g s", G.t,
        why, G.stage or 0, #(gc().stages or {}), lit(G), #G.fx, num(gc().test.fx_off_s, 30)))
end

local function stagesTick(now)
    local G = GEO.cur
    if not G then return end
    local dt = math.min(1, math.max(0, now - (G.last or now)))
    G.last = now
    fxGone(G)
    if paused() then return end
    G.t = G.t + dt
    local t = gc().test
    if not G.ready then
        local ok = settled(G, "stages")
        if ok == false then GEO.cur = nil; log("geofon: stages given up: " .. takeOff(G, "its capture given up")); return end
        if not ok then return end
        G.ready = true
        hudCallout("TEST: GEOFON", "4 KM AHEAD (CTRL+G: -20 %)")
        G.nextLine = G.t + num(t.every_s, 5)
    end
    if G.down then
        if not G.offDone and G.t >= G.down + num(t.fx_off_s, 30) then
            G.offDone = true
            fxOff(G, 3)
            log(string.format("geofon: +%.0f s: its fires and smoke off", G.t))
        end
        return
    end
    if not same(G.hull) then down(G, liveAddr(G.hull.obj) and "its hull's address is another object's now" or "its hull gone"); return end
    local h = hp(G.hull)
    if h and h <= 0 then down(G, "its hull at 0"); return end
    local share = (h and G.max > 0) and h / G.max or 1
    for k, st in ipairs(gc().stages or {}) do
        if not G.done[k] and share <= num(st.at, 0) then
            G.done[k], G.stage = true, k
            stageOn(G, k, st, share)
        end
    end
    local vm = G.m.VesselMesh
    if G.rollTo and G.roll ~= G.rollTo and vm and not vm.isRoot and same(vm.e) then  -- (the list, a little a tick)
        local step = math.min(G.rollRate * dt, num(t.list_step_max, 0.1))
        if G.roll < G.rollTo then G.roll = math.min(G.rollTo, G.roll + step) else G.roll = math.max(G.rollTo, G.roll - step) end
        local b = vm.base
        local ok, err = pcall(function() vm.e.obj:K2_SetRelativeRotation({ Pitch = b.P, Yaw = b.Yw, Roll = b.R + G.roll }, false, {}, true) end)
        if not ok then logOnce("geofon list", "geofon: the list not set (K2_SetRelativeRotation): " .. tostring(err)) end
    end
    if t.refire ~= false and G.t >= (G.nextFire or 0) then           -- (a system that ended by itself spawned again)
        G.nextFire = G.t + 1
        for _, f in ipairs(G.fx) do
            if not f.offAt and not burning(f) then
                local old = f.e
                local e = fxOn(G, f.path, f.off)
                if e then
                    if same(old) then pcall(function() old.obj:K2_DestroyComponent(old.obj) end) end   -- (the ended one, if left)
                    f.e = e
                    G.refired = G.refired + 1
                    if not G.refireSaid then
                        G.refireSaid = true
                        log(string.format("geofon: +%.0f s: a stage's system ended by itself: spawned again as each one ends (test.refire)", G.t))
                    end
                end
            end
        end
    end
    if G.t >= (G.nextLine or 0) then
        G.nextLine = G.t + num(t.every_s, 5) - 0.05
        local n, nLit = #G.fx, lit(G)
        local rb = "?"
        local l, yaw = frame(G.hull.obj)
        local q = vm and same(vm.e) and inFrame(vm.e.obj, l, yaw) or nil
        if q and q.r then rb = string.format("%.1f", q.r) end
        log(string.format("geofon: +%.0f s: health %.0f %%, stage %d, list %.1f deg (read back %s), fires and smoke %d of %d burning (%d spawned again)",
            G.t, share * 100, G.stage or 0, G.roll, rb, nLit, n, G.refired))
    end
end

-- Ctrl+G with GEOFON up: hit (20 %) of its health off
local function hit(G)
    local h = hp(G.hull)
    if not (h and G.max and G.max > 0) then log("geofon: Ctrl+G: its health can't be read"); return end
    local cut = num(gc().test.hit, 0.2) * G.max            -- (HealthInternal: health x 10; ModifyHealth takes health)
    local want = h - cut
    local o = G.hull.obj
    local amount = cut / 10
    if want <= 1 then                                      -- (the last: to 0, as finishParts finishes a part)
        pcall(function() o:SetMinHealth(0.0) end)
        amount = h / 10 + 1000
    end
    local way = "ModifyHealth"
    local ok, err = pcall(function() o:ModifyHealth(-amount, nil, true) end)
    local h1 = hp(G.hull)
    if not ok or (h1 and h1 >= h) then
        way = "ModifyHealth " .. (ok and "changed nothing" or ("failed: " .. tostring(err))) .. "; "
        if want > 1 then
            way = way .. (pcall(function() o.HealthInternal = math.floor(want) end) and "HealthInternal written" or "HealthInternal NOT written")
        else
            local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
            way = way .. ((valid(gs) and pcall(function() gs:ApplyDamage(o, 100000000.0, nil, nil, nil) end)) and "ApplyDamage" or "ApplyDamage failed")
        end
        h1 = hp(G.hull)
    end
    log(string.format("geofon: Ctrl+G at +%.0f s: health %.0f %% -> %s (%s)", G.t, 100 * h / G.max,
        h1 and string.format("%.0f %%", 100 * h1 / G.max) or "?", way))
end

---------------------------------------------------------------------------------------------------- the keys
local function canRun(key)
    if not (D and D.now) or not nativeReady() then log("geofon: " .. key .. " outside a Survival run"); return false end
    if joiner() then log("geofon: " .. key .. ": the host spawns it (you're a joiner)"); return false end
    local kind = type(D.special) == "table" and D.special.kind or nil
    if kind == "spaceport" or kind == "retake" then
        log("geofon: " .. key .. ": not in a Spaceport round (its Ford is the round's)"); return false
    end
    if RUN and type(RUN.sport) == "table" and type(RUN.sport.ships) == "table" and RUN.sport.ships[FORD] then
        log("geofon: " .. key .. ": the Spaceport's Ford is carried into its retake: not taken"); return false
    end
    return true
end

-- (the review of 8ca3195, finding 4) the landing STORE open: refused, a spawn or a removal alike (its minigame holds the
-- world's AI: an object it never froze, or one taken down under it, was 0.74.11's and 0.74.48's case)
local function inStore(key)
    if not OFF.store() then return false end
    log("geofon: " .. key .. " in the STORE: refused (its minigame holds the world's AI): again once you've taken off")
    return true
end
-- a spawn refused: its callout (the Ford still being taken off: again in a few seconds)
local function notSpawned(title, key, why)
    hudCallout(title, tostring(why):find("still being taken off", 1, true) and "STILL GOING: AGAIN IN A FEW SECONDS" or "NOT SPAWNED")
    log("geofon: " .. key .. ": " .. tostring(why))
end

testKey("B", "sv_fleet.lua's GEOFON V-break look (T1)", function()
    if inStore("Ctrl+B") then return end
    if GEO.look then
        local L = GEO.look
        GEO.look = nil
        log(string.format("geofon: break look off at +%.0f s (Ctrl+B): %s", L.t, takeOff(L, "Ctrl+B")))
        hudCallout("TEST: GEOFON V-BREAK", "OFF")
        return
    end
    if not canRun("Ctrl+B") then return end
    if GEO.cur then                                       -- (the Ford is busy then: this press only takes it off)
        log(string.format("geofon: Ctrl+B: GEOFON's stages test taken off first (%s)", takeOff(GEO.cur, "Ctrl+B")))
        GEO.cur = nil
    end
    local L, why = spawnFord(num(gc().look.ahead_cm, 350000), "Ctrl+B (the V-break look)")
    if not L then notSpawned("TEST: GEOFON V-BREAK", "Ctrl+B", why); return end
    GEO.look = L
end)

testKey("G", "sv_fleet.lua's GEOFON stages (T2)", function()
    if inStore("Ctrl+G") then return end
    local G = GEO.cur
    if G and G.ready and not G.down and same(G.hull) then hit(G); return end
    if G and not G.ready then log("geofon: Ctrl+G: GEOFON is still coming up"); return end
    if not canRun("Ctrl+G") then return end
    if GEO.look then
        log(string.format("geofon: Ctrl+G: the V-break look taken off first (%s)", takeOff(GEO.look, "Ctrl+G")))
        GEO.look = nil
    end
    if G then                                             -- (one sunk: what's left of it taken off; a new one once it's gone)
        GEO.cur = nil
        log(string.format("geofon: Ctrl+G: the GEOFON before taken off first (%s)", takeOff(G, "Ctrl+G: a new GEOFON")))
    end
    local N, why = spawnFord(num(gc().test.ahead_cm, 400000), "Ctrl+G (GEOFON's stages)")
    if not N then notSpawned("TEST: GEOFON", "Ctrl+G", why); return end
    N.fx, N.done, N.roll, N.refired = {}, {}, 0, 0
    GEO.cur = N
end)

TEST_TICKS[#TEST_TICKS + 1] = { name = "fleet", fn = function(now)
    lookTick(now)
    stagesTick(now)
end }
if type(LEVEL_DROPS) == "table" then                       -- (the level's objects: forgotten, none of them touched)
    LEVEL_DROPS["fleet"] = function() GEO.look, GEO.cur, GEO.catching = nil, nil, nil end
end
end

---------------------------------------------------------------------------------------------------- WP7: the fleet (Ctrl+N)
-- IFLEET.setup (sv_main.lua, at the main menu, as the TANICORN's rows since 0.74.46: the spawner reads the rows as the level
-- loads): the named ships' model rows into DT_NPC_Model, Mission 22's ships' turret rows and the named hulls into DT_NPC
-- (from DT_SV_ModelRows / DT_SV_NpcRows; the Spaceport's turret rows too if the allies' setup didn't put them in), the
-- turrets' weapons on the Spaceport fleet's fire control where it has a clone, the names' and classes' texts.
-- IFLEET.cur: Ctrl+N's fleet { t, queue (ships not spawned yet), ships = { sh ... }, by = { [address] = { sh, cls, e } },
-- fired, guns, firedParts (since the last weapons line), left / clearUntil (units still up from before it waits for) };
-- each sh { raw (the objects caught at its spawn), kept (each kept as SV_Spawn returned), hull, parts, ... }.
-- IFLEET.onLaunch: sv_weaponlog.lua's word on each launch.
IFLEET = { cur = nil, rowsOk = nil }
do
local TURRET = { "mk15", "mk41", "mk45", "artillery", "_sam", "aagun", "ak130", "ak630", "a190", "a192", "3r14", "palma",
                 "kashtan", "s300" }
local function fc() return CFG.specials.fleet end
local function fm() return CFG.specials.fleet.formation end
local function joiner() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function paused() return type(gamePaused) == "function" and gamePaused(survivalPC) == true end
local function num(v, d) v = tonumber(v); return v or d end
local function title(k) return k:sub(1, 1):upper() .. k:sub(2) end
local function classOf(o) return ((nameOf(o):match("([%w_]+)$") or "?"):gsub("_C_%d+$", ""):gsub("_C$", "")) end
local function turretClass(cls)
    local low = cls:lower()
    for _, k in ipairs(TURRET) do if low:find(k, 1, true) then return true end end
    return false
end
-- a live object kept between ticks: { obj, addr, name, cls } (hard rule 59: same() before every use)
local function keep(o)
    local a = o ~= nil and liveAddr(o)
    if not a then return nil end
    return { obj = o, addr = a, name = nameOf(o), cls = classOf(o) }
end
local function same(e) return e ~= nil and liveAddr(e.obj) == e.addr and nameOf(e.obj) == e.name end
local function at(e)
    if not same(e) then return nil end
    local ok, v = pcall(function() return e.obj:K2_GetActorLocation() end)
    if ok and v then return { X = num(v.X, 0), Y = num(v.Y, 0), Z = num(v.Z, 0) } end
    return nil
end
local function hp(e)
    if not same(e) then return nil end
    local ok, h = pcall(function() return e.obj.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end
local function d2(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) end
local function compass(dx, dy) return (math.deg(math.atan(dy, dx)) + 90) % 360 end   -- (heading = 90 + yaw: COMONA_MAP.md 1)
local function label(sh) return sh.name ~= "" and sh.name or sh.key end

-- a row of `src` in `dst` (in already, or added): the row in dst, or nil
local function addRow(dst, src, row)
    local _, have = dtCall(dst, "FindRow", row)
    if have == nil then
        local _, r = dtCall(src, "FindRow", row)
        if r == nil then return nil end
        dtCall(dst, "AddRow", row, r)
        _, have = dtCall(dst, "FindRow", row)
    end
    return have
end
-- a turret row's weapons on the Spaceport fleet's fire control where sv_allies.lua made its clone (<id>_SVA_Fleet), the ids
-- with none kept in stock{}; its search the fleet's AI module where there is one: how many it put on the fleet's
local function fleetFcs(have, fcs, module, stock)
    local on = 0
    for i = 0, 5 do
        pcall(function()
            local id = have["NpcFCSId" .. i]:ToString()
            if id ~= "None" and id ~= "" and not id:find("_SVA", 1, true) then
                local _, cl = dtCall(fcs, "FindRow", id .. "_SVA_Fleet")
                if cl ~= nil then have["NpcFCSId" .. i] = FName(id .. "_SVA_Fleet"); on = on + 1 else stock[id] = true end
            end
        end)
    end
    if module then pcall(function() have.NpcAIModuleId = FName(module) end) end
    return on
end
function IFLEET.setup()
    if IFLEET.setupDone or not gameInstance() then return end
    IFLEET.tries = (IFLEET.tries or 0) + 1
    -- (after the allies' setup: the Spaceport's turret rows the Ford's and the Aegis's parts fly, and their fire control)
    local allies = ALLY ~= nil and (ALLY.setupDone or not (CFG.allies and CFG.allies.enabled))
    if not allies and IFLEET.tries < 40 then return end
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows)
    local mt, mr, fcs = loadObject(ACE.model_table), loadObject(ACE.model_rows), loadObject(FCS_TABLE)
    if not (npc and mine and mt and mr and fcs) then
        if IFLEET.tries >= 40 then
            IFLEET.setupDone, IFLEET.rowsOk = true, false
            log("fleet: rows at the main menu: the row tables didn't load: no Ctrl+N fleet this session")
        end
        return
    end
    IFLEET.setupDone = true
    for _, t in ipairs({ npc, mine, mt, mr, fcs }) do pin(t, nameOf(t)) end
    local module, mods = nil, loadObject(SEARCH_MODULE.path)
    if mods then
        pin(mods, nameOf(mods))
        local _, m = dtCall(mods, "FindRow", "NPC_AIModule_SV_Fleet")
        if m ~= nil then module = "NPC_AIModule_SV_Fleet" end
    end
    local missing, stock, nM, nH, nT, nS, onFleet = {}, {}, 0, 0, 0, 0, 0
    for _, c in ipairs(fc().ships) do                          -- (the models first: the hulls name them)
        if c.name ~= "" then
            if addRow(mt, mr, "SV_Model_Fleet_" .. c.key) then nM = nM + 1 else missing[#missing + 1] = "SV_Model_Fleet_" .. c.key end
        end
    end
    for _, row in ipairs(fc().turret_rows) do
        local have = addRow(npc, mine, row)
        if have then nT = nT + 1; onFleet = onFleet + fleetFcs(have, fcs, module, stock) else missing[#missing + 1] = row end
    end
    local sp = (SPORT and SPORT.FLEET_ROWS) or {}
    for _, row in ipairs(sp) do                               -- (the Spaceport's: in already with the allies)
        if addRow(npc, mine, row) then nS = nS + 1 else missing[#missing + 1] = row end
    end
    for _, c in ipairs(fc().ships) do                          -- (the hulls last: they name the rows above)
        if c.name ~= "" then
            local have = addRow(npc, mine, "SV_IF_" .. c.key)
            if have then
                nH = nH + 1
                if module then pcall(function() have.NpcAIModuleId = FName(module) end) end
            else missing[#missing + 1] = "SV_IF_" .. c.key end
        end
    end
    local names = 0
    local function setText(key, text)                         -- (in a pcall, as every call into the game: review finding 5)
        local okT, r = pcall(SV_SetText, key, text)
        if okT and r == 1 then names = names + 1 end
    end
    if type(SV_SetText) == "function" then
        for _, c in ipairs(fc().ships) do
            if c.name ~= "" then setText("SV_FleetName_" .. c.key, c.name) end
        end
        for k, text in pairs(fc().classes) do setText("SV_FleetClass_" .. title(k), text) end
    end
    local st = {}
    for id in pairs(stock) do st[#st + 1] = id end
    table.sort(st)
    IFLEET.rowsOk = #missing == 0
    log(string.format("fleet: rows at the main menu: %d model rows in DT_NPC_Model, %d hull rows and %d turret rows in DT_NPC (%d "
        .. "weapons on the Spaceport fleet's fire control; on their stock one: %s; their search %s), the Spaceport's %d of %d; "
        .. "%d names and classes set%s", nM, nH, nT, onFleet, #st > 0 and table.concat(st, ", ") or "none", module or "stock", nS,
        #sp, names, #missing > 0 and ("; MISSING: " .. table.concat(missing, ", ") .. ": no Ctrl+N fleet") or ""))
end

-- every LiveAIGameObject the spawner makes for the ship being spawned (as SPORT.shipObjs)
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local F = IFLEET.cur
    local sh = F and F.catching
    if sh and spawningUnit == sh.unit and #sh.raw < 16 then sh.raw[#sh.raw + 1] = o end
end)

-- the ships, in the build's order: each one's spot off GEOFON in the world (cm: its lane is GEOFON's course moved by it)
local function fleetList()
    local yaw = math.rad(num(fm().course_yaw, 45))
    local ux, uy, rx, ry = math.cos(yaw), math.sin(yaw), -math.sin(yaw), math.cos(yaw)
    local out = {}
    for _, c in ipairs(fc().ships) do
        local f, r = num(c.fwd_m, 0) * 100, num(c.right_m, 0) * 100
        out[#out + 1] = { name = c.name, key = c.key, kind = c.kind, unit = "SV_Unit_IF" .. c.key, go = "RE_SV_IFGo" .. c.key,
                          off = { X = ux * f + rx * r, Y = uy * f + ry * r }, raw = {}, kept = {}, parts = {}, goTries = 0 }
    end
    return out
end

-- ((the review of 8ca3195, finding 1) a unit still up is no longer forced off the spawner's list here and spawned again
-- beside its objects: Ctrl+N holds the fleet for it, F.left, the tick below)
local function spawnShip(F, sh)
    F.catching = sh
    spawningUnit = sh.unit
    local ok, r = pcall(SV_Spawn, sh.unit)                              -- (no pose: its unit's own spot, its course start)
    spawningUnit = nil
    F.catching = nil
    for _, o in ipairs(sh.raw) do                       -- (each object as it was made: its address and name, hard rule 59)
        local e = keep(o)
        if e then sh.kept[#sh.kept + 1] = e end
    end
    local n = ok and num(r, -5) or -5
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, sh.unit, n) end
    sh.r, sh.at = n, F.t
    local said = n > 0 and (n .. " up") or ("not spawned (" .. tostring((SV_ERR and SV_ERR[n]) or (ok and n) or ("error " .. tostring(r))) .. ")")
    log(string.format("fleet: %s (%s, %s): %s at its course start; %d objects made", label(sh), sh.unit, sh.kind, said, #sh.raw))
end

-- settle_s after its spawn: its hull (its one object that isn't a turret's class) and parts, its up line
local function settle(F, sh)
    sh.settled = true
    local hulls = {}
    for _, e in ipairs(sh.kept) do                        -- (as they were made: still each one, hard rule 59)
        if same(e) then
            if turretClass(e.cls) then sh.parts[#sh.parts + 1] = e else hulls[#hulls + 1] = e end
        end
    end
    sh.hull = hulls[1]
    for _, e in ipairs(sh.parts) do F.by[e.addr] = { sh = sh, cls = e.cls, e = e } end
    if sh.hull then F.by[sh.hull.addr] = { sh = sh, cls = "hull", e = sh.hull } end
    local p = sh.hull and at(sh.hull)
    sh.home, sh.lastP, sh.lastT = p, p, F.t
    sh.max = sh.hull and hp(sh.hull) or nil
    local cls = {}
    for _, e in ipairs(sh.parts) do cls[#cls + 1] = e.cls end
    log(string.format("fleet: up: %s (%s, %s): hull %s%s, health %s; %d part%s: %s%s; its box: %s", label(sh), sh.unit, sh.kind,
        sh.hull and sh.hull.cls or "NOT found", p and string.format(" at (%.2f, %.2f) km", p.X / 1e5, p.Y / 1e5) or "",
        sh.max and string.format("%.0f", sh.max) or "?", #sh.parts, #sh.parts == 1 and "" or "s",
        #cls > 0 and table.concat(cls, ", ") or "none", #hulls > 1 and string.format(" (%d more objects not turrets: %s first)",
        #hulls - 1, sh.hull.cls) or "", sh.name ~= "" and (sh.name .. " / " .. tostring(fc().classes[sh.kind])) or "its class's (unnamed)"))
end

local function partsUp(sh)
    local up = 0
    for _, e in ipairs(sh.parts) do local x = hp(e); if x and x > 0 then up = up + 1 end end
    return up
end

local function allUp(F)
    F.allSaid = true
    local up, nParts = 0, 0
    for _, sh in ipairs(F.ships) do
        if sh.hull then up = up + 1 end
        nParts = nParts + #sh.parts
    end
    local G = F.ships[1]
    local g = G.hull and at(G.hull)
    local you, rw = playerLocation(), fm().runway_cm
    local km, brg = nil, nil
    if g and you then km, brg = d2(g, you) / 1e5, compass(g.X - you.X, g.Y - you.Y) end
    log(string.format("fleet: Ctrl+N: %d of %d ships up with %d parts at their course start%s; %s", up, #F.ships, nParts,
        g and string.format(" (GEOFON %.1f km from the runway, bearing %03.0f from it)", d2(g, { X = rw[1], Y = rw[2] }) / 1e5,
            compass(g.X - rw[1], g.Y - rw[2])) or "",
        km and string.format("GEOFON %.1f km from you, bearing %03.0f: fly there", km, brg) or "GEOFON's place NOT read"))
    hudCallout("TEST: INVINCIBLE FLEET", km and string.format("%d SHIPS %.0f KM, BEARING %03.0f", up, km, brg) or string.format("%d SHIPS UP", up))
end

local function sunkTick(F, sh)
    if sh.sunk or not sh.hull then return end
    local why
    if not same(sh.hull) then why = "its hull gone"
    else
        local h = hp(sh.hull)
        if h and h <= 0 then why = "its hull at 0" end
    end
    if why then
        sh.sunk = true
        log(string.format("fleet: +%.0f s %s sunk (%s); %d of its %d parts still up", F.t, label(sh), why, partsUp(sh), #sh.parts))
    end
end

-- under way go_s after its spawn (moved_m from where it settled), else its lane again (RE_SV_IFGo<Key>: the records of its
-- appearance, which a unit spawned while you're at the airfield's menu may not get), at most twice
local function goTick(F, sh)
    if sh.sunk or sh.underway or sh.goDone or not (sh.hull and sh.home) then return end
    if F.t < sh.at + num(fm().go_s, 15) * (sh.goTries + 1) then return end
    local p = at(sh.hull)
    local moved = p and d2(p, sh.home) / 100 or 0
    if moved >= num(fm().moved_m, 50) then
        sh.underway = true
        log(string.format("fleet: +%.0f s %s under way (%.0f m from where it came up)%s", F.t, label(sh), moved,
            sh.goTries > 0 and (" after " .. sh.go) or ""))
        return
    end
    if sh.goTries >= 2 then
        sh.goDone = true
        log(string.format("fleet: +%.0f s %s NOT under way (%.0f m from where it came up) after %s twice: its lane isn't taken", F.t,
            label(sh), moved, sh.go))
        return
    end
    sh.goTries = sh.goTries + 1
    local r = "n/a"
    if type(SV_Event) == "function" then                 -- (in a pcall: an error here would stop every later ship's look)
        local okE, x = pcall(SV_Event, sh.go)
        r = okE and tostring(x) or ("error " .. tostring(x))
    end
    log(string.format("fleet: +%.0f s %s not under way %.0f s after its spawn (%.0f m): %s fired (%s)", F.t, label(sh), F.t - sh.at,
        moved, sh.go, r))
end

-- sv_weaponlog.lua's word: a weapon shown by the object at oa (its owner); one of the fleet's parts: counted
function IFLEET.onLaunch(oa, weapon)
    local F = IFLEET.cur
    local who = F and oa and F.by[oa]
    if not (who and same(who.e)) then return end
    local k = string.format("%s %s %s", label(who.sh), who.cls, tostring(weapon))
    F.fired[k] = (F.fired[k] or 0) + 1
    F.firedParts[oa] = true
end
-- the fleet's guns: a shown LiveBullet one of its parts owns (the Spaceport's turret watch's way; a walk, ~40 ms)
local function gunsTick(F)
    local okB, list = pcall(FindAllOf, "LiveBullet")
    for _, b in ipairs(okB and list or {}) do
        if liveAddr(b) then
            local okH, hidden = pcall(function() return b.bHidden end)
            if okH and hidden == false then
                local okO, o = pcall(function() return b.OwningGameObject end)
                local a = okO and liveAddr(o)
                local who = a and F.by[a]
                if who and same(who.e) then
                    F.guns[string.format("%s %s gun", label(who.sh), who.cls)] = true
                    F.firedParts[a] = true
                end
            end
        end
    end
end

local function lines(F)
    local G = F.ships[1]
    local g = G.hull and not G.sunk and at(G.hull) or nil
    local you, rw = playerLocation(), fm().runway_cm
    for _, sh in ipairs(F.ships) do
        if sh.settled and not sh.sunk then
            local p = sh.hull and at(sh.hull)
            local h = sh.hull and hp(sh.hull)
            local share = (h and sh.max and sh.max > 0) and string.format("%.0f %%", 100 * h / sh.max) or "?"
            local speed, hdg = "?", "-"
            if p and sh.lastP and F.t > sh.lastT then
                local m = d2(p, sh.lastP)
                speed = string.format("%.0f km/h", m / 1e5 / ((F.t - sh.lastT) / 3600))
                if m > 100 then hdg = string.format("%03.0f", compass(p.X - sh.lastP.X, p.Y - sh.lastP.Y)) end
            end
            if sh == G then
                log(string.format("fleet: +%.0f s %s: %s, %s from the runway, %s from you, %s heading %s, health %s, %d of %d parts up",
                    F.t, label(sh), p and string.format("(%.2f, %.2f) km", p.X / 1e5, p.Y / 1e5) or "its place NOT read",
                    p and string.format("%.1f km", d2(p, { X = rw[1], Y = rw[2] }) / 1e5) or "?",
                    (p and you) and string.format("%.1f km", d2(p, you) / 1e5) or "?", speed, hdg, share, partsUp(sh), #sh.parts))
            else
                local spot = g and { X = g.X + sh.off.X, Y = g.Y + sh.off.Y }
                log(string.format("fleet: +%.0f s %s (%s): %s from GEOFON, %s off its spot, %s heading %s, health %s, %d of %d parts up",
                    F.t, label(sh), sh.kind, (p and g) and string.format("%.2f km", d2(p, g) / 1e5) or "?",
                    (p and spot) and string.format("%.0f m", d2(p, spot) / 100) or "?", speed, hdg, share, partsUp(sh), #sh.parts))
            end
            if p then sh.lastP, sh.lastT = p, F.t end
        end
    end
    local t, nParts, fired = {}, 0, 0
    for k, n in pairs(F.fired) do t[#t + 1] = string.format("%s x%d", k, n) end
    for k in pairs(F.guns) do t[#t + 1] = k end
    table.sort(t)
    for _, sh in ipairs(F.ships) do
        if not sh.sunk then
            for _, e in ipairs(sh.parts) do
                nParts = nParts + 1
                if F.firedParts[e.addr] then fired = fired + 1 end
            end
        end
    end
    log(string.format("fleet: +%.0f s weapons (since the last line): %s; %d of %d parts fired%s", F.t,
        #t > 0 and table.concat(t, "; ") or "nothing", fired, nParts,
        (g and you) and string.format(", you %.1f km from GEOFON", d2(g, you) / 1e5) or ""))
    F.fired, F.guns, F.firedParts = {}, {}, {}
end

-- RE_SV_IFFleetRemove fired (each unit's LiveDestroyUnitExecution, Mission 22's despawn, as the Spaceport's
-- RE_SV_SpFleetRemove: a co-op joiner's copies go with it): what it said
local function removeFire(why)
    if type(SV_Event) ~= "function" then return "not fired (no SV_Event)" end
    crumb("fleet: RE_SV_IFFleetRemove (" .. why .. ")")
    local okE, r = pcall(SV_Event, "RE_SV_IFFleetRemove")
    return okE and tostring(r) or ("error " .. tostring(r))
end

-- the fleet taken off: RE_SV_IFFleetRemove, then OFF.down over every spawned ship's objects still the ones made (a ship not
-- settled yet too). ((the review of 8ca3195, finding 1) until then every ship was hidden and forced off the spawner's list
-- at once, SV_Recycle(unit, 1): its turrets live under the hidden hull, its unit actor destroyed 30 s on under them, a
-- third press spawning a second fleet beside the first.) What was done
local function takeOff(F, why)
    local units, objs, nObj = {}, {}, 0
    for _, sh in ipairs(F.ships) do
        if (sh.r or 0) > 0 then
            units[#units + 1] = sh.unit
            if COOP and COOP.host and COOP.host() and COOP.removeNow then pcall(COOP.removeNow, sh.unit) end
            local l = {}
            for _, e in ipairs(sh.kept) do if same(e) then l[#l + 1] = e.obj end end
            objs[sh.unit], nObj = l, nObj + #l
        end
    end
    local dropped = #F.queue > 0 and string.format(" (%d not spawned yet dropped)", #F.queue) or ""
    if #units == 0 then return "no ship up" .. dropped end
    local ev = removeFire(why)
    local n, err = OFF.down(units, objs, "the fleet test taken off (" .. why .. ")")
    return string.format("%d units%s, RE_SV_IFFleetRemove %s; %s", #units, dropped, ev, n and string.format("%d of their %d "
        .. "objects still up finished off or switched off (each unit off the spawner's list from 2 s on)", n, nObj) or tostring(err))
end

-- (Ctrl+N with ships of the fleet still up from before: RE_SV_IFFleetRemove fired at the press) the fleet held up to
-- clear_s for them to go (the Spaceport's CLEAR_S), looked at every gap_s; one still up then is never spawned beside it
-- (dropped from this fleet, said). F.left nil once they're gone or dropped.
local function clearTick(F, c)
    F.leftAt = F.t + num(c.gap_s, 0.5)
    local still = {}
    for u in pairs(F.left) do if OFF.alive(u) > 0 then still[#still + 1] = u end end
    table.sort(still)
    if #still == 0 then
        F.left = nil
        log(string.format("fleet: +%.0f s the ships up from before are gone: the fleet comes up", F.t))
    elseif F.t >= F.clearUntil then
        local drop, q, names = {}, {}, {}
        for _, u in ipairs(still) do drop[u] = true end
        for _, sh in ipairs(F.queue) do
            if drop[sh.unit] then sh.dropped = true; names[#names + 1] = label(sh) else q[#q + 1] = sh end
        end
        F.queue, F.left = q, nil
        log(string.format("fleet: +%.0f s %d ships still up %g s after RE_SV_IFFleetRemove (%s): not spawned beside them, the "
            .. "fleet comes up without them", F.t, #still, num(c.clear_s, 8), table.concat(names, ", ")))
    else
        local keepL = {}
        for _, u in ipairs(still) do keepL[u] = true end
        F.left = keepL
    end
end

function IFLEET.tick(now)
    local F = IFLEET.cur
    if not F then return end
    local dt = math.min(1, math.max(0, now - (F.last or now)))
    F.last = now
    if paused() or OFF.store() then return end           -- (the STORE's time not counted either: review finding 4)
    F.t = F.t + dt
    local c = fm()
    if F.left and F.t >= (F.leftAt or 0) then clearTick(F, c) end
    if not F.left and #F.queue > 0 and F.t >= F.nextAt then
        for _ = 1, math.max(1, math.floor(num(c.per_step, 3))) do
            local sh = table.remove(F.queue, 1)
            if not sh then break end
            spawnShip(F, sh)
        end
        F.nextAt = F.t + num(c.gap_s, 0.5)
    end
    local pending = #F.queue
    for _, sh in ipairs(F.ships) do
        if sh.at and not sh.settled and F.t >= sh.at + num(c.settle_s, 2) then settle(F, sh) end
        if not sh.settled and not sh.dropped then pending = pending + 1 end
        sunkTick(F, sh)
        goTick(F, sh)
    end
    if pending == 0 and not F.allSaid then
        allUp(F)
        F.lineAt = F.t + num(c.every_s, 10)
    end
    if not F.allSaid then return end
    if num(c.guns_s, 2) > 0 and F.t >= (F.gunsAt or 0) then
        F.gunsAt = F.t + num(c.guns_s, 2)
        local okG, errG = pcall(gunsTick, F)
        if not okG then logOnce("fleet guns", "fleet: the guns' look failed: " .. tostring(errG)) end
    end
    if F.t >= (F.lineAt or 0) then
        F.lineAt = F.t + num(c.every_s, 10) - 0.05
        lines(F)
    end
end

local function canRun()
    if not (D and D.now) or not nativeReady() then log("fleet: Ctrl+N outside a Survival run"); return false end
    if joiner() then log("fleet: Ctrl+N: the host spawns the fleet (you're a joiner)"); return false end
    if not IFLEET.rowsOk then
        log("fleet: Ctrl+N: the fleet's rows aren't in the game's tables (" .. (IFLEET.setupDone and "the `fleet: rows at the main "
            .. "menu` line says which" or "IFLEET.setup hasn't run: start the game to its main menu with this build") .. "): not spawned")
        return false
    end
    return true
end

testKey("N", "sv_fleet.lua's INVINCIBLE FLEET formation test (WP7)", function()
    if OFF.store() then                                   -- (the review of 8ca3195, finding 4: on and off alike)
        log("fleet: Ctrl+N in the STORE: refused (its minigame holds the world's AI; " .. (IFLEET.cur and "the fleet stays as it is"
            or "nothing spawned") .. "): again once you've taken off")
        return
    end
    local F = IFLEET.cur
    if F then
        IFLEET.cur = nil
        log(string.format("fleet: Ctrl+N at +%.0f s: the fleet taken off: %s", F.t, takeOff(F, "Ctrl+N")))
        hudCallout("TEST: INVINCIBLE FLEET", "OFF")
        return
    end
    if not canRun() then return end
    local ships = fleetList()
    local busy = {}                                       -- (the fleet before still being taken off: OFF.down's)
    for _, sh in ipairs(ships) do if OFF.queued(sh.unit) then busy[#busy + 1] = label(sh) end end
    if #busy > 0 then
        log(string.format("fleet: Ctrl+N: the fleet before is still being taken off (%d units: %s): not spawned, again in a few seconds",
            #busy, table.concat(busy, ", ")))
        hudCallout("TEST: INVINCIBLE FLEET", "STILL GOING: AGAIN IN A FEW SECONDS")
        return
    end
    local q, left, names = {}, {}, {}
    for _, sh in ipairs(ships) do
        q[#q + 1] = sh
        if OFF.alive(sh.unit) > 0 then left[sh.unit] = true; names[#names + 1] = label(sh) end
    end
    F = { t = 0, queue = q, ships = ships, by = {}, fired = {}, guns = {}, firedParts = {}, nextAt = 0 }
    if #names > 0 then                                    -- (still up from before: taken off, the fleet held for them)
        for u in pairs(left) do if COOP and COOP.takenOff then pcall(COOP.takenOff, u) end end
        F.left, F.clearUntil = left, num(fm().clear_s, 8)
        log(string.format("fleet: Ctrl+N: %d of the fleet's ships still up from before (%s): taken off (RE_SV_IFFleetRemove %s); "
            .. "the fleet waits up to %g s for them, never spawned beside them", #names, table.concat(names, ", "),
            removeFire("Ctrl+N: still up from before"), F.clearUntil))
    end
    IFLEET.cur = F
    log(string.format("fleet: Ctrl+N: %d ships coming up at their course start, %d every %g s (their lanes in from north-west of "
        .. "the runway; again: taken off)", #ships, math.floor(num(fm().per_step, 3)), num(fm().gap_s, 0.5)))
    hudCallout("TEST: INVINCIBLE FLEET", string.format("%d SHIPS COMING UP", #ships))
end)

TEST_TICKS[#TEST_TICKS + 1] = { name = "fleet ships", fn = function(now) IFLEET.tick(now) end }
if type(LEVEL_DROPS) == "table" then                       -- (the level's objects: forgotten, none of them touched)
    LEVEL_DROPS["fleet ships"] = function() IFLEET.cur = nil end
end
end
-- TEST ONLY END
