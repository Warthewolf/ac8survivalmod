-- sv_fishing.lua: GONE FISHIN' (CFG.specials.fishing; FISHING_ROUND_PLAN.md; tools/re/FISHING.md 1-4): the shoals and
-- SAL's boat. Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a
-- global of this mod's Lua state, its own helpers stay local.
-- The round itself comes later: for now the rows at the main menu (FISH.setup), what each spawn makes (FISH.actors), the
-- splash and the first in-game test's key (Ctrl+F10, test only).
-- The build data (tools/build_survival.py, the contract of 2026-11-06): a shoal is DT_SV_NpcRows' SV_Shoal (a copy of the
-- stock invisible turret pawn GR000_dummy with the vessels' durability ids) on DT_SV_ModelRows' SV_Model_Shoal (MaxHealth
-- 10), mission row sv_shoal; units SV_Unit_FishA / B / C of 8 shoals each (boxed, TGT, within 800 m of the unit's origin,
-- offset z 0); SAL's boat SV_Unit_SalBoat (the stock VE027_boat2_01, allied, MinHealth 1, invincible from AI and wingmen).
FISH = { actors = {}, ready = nil, setupDone = false, tries = 0 }
do
local function cfg() return CFG.specials.fishing end
local function isFishUnit(u)
    local c = cfg()
    if u == c.boat_unit then return true end
    for _, x in ipairs(c.units or {}) do if x == u then return true end end
    return false
end
FISH.isUnit = isFishUnit

-- (the main menu, sv_main.lua's setup pass) the shoal's DT_NPC row and its model row into the game's tables, as VOID
-- WATCHER 1's (sv_allies.lua): a row naming a model the game hasn't can't spawn. Its names' texts set (SV_SetText).
function FISH.setup()
    if FISH.setupDone or not cfg().enabled or not gameInstance() then return end
    FISH.tries = FISH.tries + 1
    local c = cfg()
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows)
    local mt, mr = loadObject(ACE.model_table), loadObject(ACE.model_rows)
    if not (npc and mine and mt and mr) then
        if FISH.tries >= 20 then FISH.setupDone = true; log("fishing: the row tables didn't load: no shoals this session") end
        return
    end
    FISH.setupDone = true
    for _, t in ipairs({ npc, mine, mt, mr }) do pin(t, nameOf(t)) end
    local function addRow(dst, src, row)
        local _, have = dtCall(dst, "FindRow", row)
        if have == nil then
            local _, r = dtCall(src, "FindRow", row)
            if r ~= nil then dtCall(dst, "AddRow", row, r); _, have = dtCall(dst, "FindRow", row) end
        end
        return have ~= nil
    end
    local model = addRow(mt, mr, c.shoal_model)               -- (the model first: the row names it)
    local row = addRow(npc, mine, c.shoal_row)
    FISH.ready = model and row
    local names = {}
    if type(SV_SetText) == "function" then
        names[#names + 1] = c.shoal_name_key .. " " .. (SV_SetText(c.shoal_name_key, c.shoal_name) == 1 and "set" or "NOT set")
        names[#names + 1] = c.boat_name_key .. " " .. (SV_SetText(c.boat_name_key, c.boat_name) == 1 and "set" or "NOT set")
    end
    log(string.format("fishing: the shoal's rows: %s %s, %s %s; names: %s", c.shoal_row, row and "in DT_NPC" or "NOT added",
        c.shoal_model, model and "in DT_NPC_Model" or "NOT added", #names > 0 and table.concat(names, ", ") or "no SV_SetText"))
end

-- What each of our units' spawns make: FISH.actors[unit] = { obj, ... } in the spawner's order, only while a caller has
-- made the list (FISH.expect) and set spawningUnit around its SV_Spawn (the constructing thread is the game thread then).
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    local l = u and FISH.actors[u]
    if l and l.open then l[#l + 1] = o end
end)
function FISH.expect(unit) FISH.actors[unit] = { open = true } end
-- one of our units spawned with its objects recorded (spawningUnit set, the co-op wrapper's ids with it); SV_Spawn's
-- answer
function FISH.spawn(unit, x, y, z, yaw)
    FISH.expect(unit)
    spawningUnit = unit
    local ok, r = pcall(SV_Spawn, unit, x, y, z, yaw)
    spawningUnit = nil
    local l = FISH.actors[unit]
    if l then l.open = false end
    if not ok then log("fishing: SV_Spawn " .. unit .. " error " .. tostring(r)); return -5 end
    return r
end
-- a unit's recorded objects still live (liveObj: kept between ticks)
function FISH.objs(unit)
    local out = {}
    for _, o in ipairs(FISH.actors[unit] or {}) do if liveObj(o) then out[#out + 1] = o end end
    return out
end

-- The sea splash at `at` (Niagara, the asset loaded the hard-rule-9 way and kept while it's live), x scale; true if it came
-- up. (sv_anomalies.lua fxAt's way, its own here: auto-destroyed when done)
local SPLASH = { sys = nil, path = nil, said = false }
function FISH.splashAsset()
    local c = cfg()
    local path = c.splash .. "." .. (c.splash:match("[^/]+$") or "")
    if SPLASH.sys ~= nil and SPLASH.path == path and liveObj(SPLASH.sys) then return SPLASH.sys end
    local o, why = loadObject(path)
    SPLASH.sys, SPLASH.path = o, path
    if not o and not SPLASH.said then SPLASH.said = true; log("fishing: the splash " .. path .. " didn't load: " .. tostring(why)) end
    return o
end
function FISH.splash(at, scale)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = FISH.splashAsset()
    if not (lib and valid(lib) and sys and liveObj(survivalPC) and at) then return false end
    local s = scale or cfg().splash_scale or 1
    return pcall(function()
        lib:SpawnSystemAtLocation(survivalPC, sys, { X = at.X, Y = at.Y, Z = at.Z }, { Pitch = 0, Yaw = 0, Roll = 0 },
            { X = s, Y = s, Z = s }, true, true, 0, true)
    end) == true
end

-- A hit sphere added to shoal o (AActor::AddComponentByClass, hard rule 46): radius m, collision profile `profile`. The
-- component and what it reads back, or nil and why not.
function FISH.addSphere(o, m, profile)
    local cls = StaticFindObject("/Script/Engine.SphereComponent")
    if not (cls and valid(cls)) then return nil, "no SphereComponent class" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, comp = pcall(function() return o:AddComponentByClass(cls, false, t, false) end)
    if not ok or comp == nil or not valid(comp) then return nil, "AddComponentByClass " .. (ok and "gave nothing" or tostring(comp)) end
    local done = {}
    done[#done + 1] = pcall(function() comp:SetSphereRadius(m * 100, true) end) and "radius" or "radius FAILED"
    done[#done + 1] = pcall(function() comp:SetCollisionProfileName(FName(profile), true) end) and "profile" or "profile FAILED"
    local okR, r = pcall(function() return comp:GetUnscaledSphereRadius() end)
    local okP, p = pcall(function() return comp:GetCollisionProfileName():ToString() end)
    local okE, e = pcall(function() return comp:GetCollisionEnabled() end)
    return comp, string.format("%s; reads radius %s m, profile %s, collision %s", table.concat(done, ", "),
        okR and string.format("%.1f", (r or 0) / 100) or "?", okP and tostring(p) or "?", okE and tostring(e) or "?")
end

-- health and its floor, as read (HealthInternal is health x 10; MaxHealth and MinHealth in health points)
function FISH.hp(o)
    local h, mx, mn
    pcall(function() h = o.HealthInternal end)
    pcall(function() mx = o.MaxHealth end)
    pcall(function() mn = o.MinHealth end)
    return h, mx, mn
end
-- who DamageHistoryMap names, with how much: "you 100, wingmate 20" ("-": nothing, "?": unreadable)
function FISH.who(o)
    local pawn = liveObj(survivalPC) and survivalPC.Pawn or nil
    local pa = pawn and addrOf(pawn) or nil
    local d, order = {}, {}
    local ok = pcall(function()
        o.DamageHistoryMap:ForEach(function(k, v)
            local okK, a = pcall(function() return k:get() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and type(x) == "number" and valid(a) then
                local s = KILL and KILL.side and KILL.side(a, pa) or "?"
                local nm = s .. "/" .. ((nameOf(a):match("([^%.:]+)$")) or "?")
                if not d[nm] then order[#order + 1] = nm end
                d[nm] = (d[nm] or 0) + x
            end
        end)
    end)
    if not ok then return "?" end
    if #order == 0 then return "-" end
    local t = {}
    for _, nm in ipairs(order) do t[#t + 1] = string.format("%s %.0f", nm, d[nm]) end
    return table.concat(t, ", ")
end

-- (the teardown gate's drop, sv_core.lua levelDrop: the level's objects forgotten untouched)
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["fishing"] = function() FISH.actors = {}; SPLASH.sys = nil end end
end

-- TEST ONLY BEGIN
-- Ctrl+F10 in a run (the host's or solo): the shoals and SAL's boat (tools/re/FISHING.md 7, tests 1-2). Each press:
--   1 SV_Unit_FishA's 8 shoals at ground A (SV_Spawn(unit, x, y, shoal_z, a random yaw)) and SAL's boat at boat_at, a hit
--     sphere on each shoal (`with sphere`, the first time), the names set; then once a second a line with each shoal's
--     health (HealthInternal / MaxHealth) and who its DamageHistoryMap names, and the boat's health and MinHealth (the
--     field written back up to boat_min_health when it's lower: never SetMinHealth). A shoal's death: who killed it
--     (KILL.read / KILL.by; co-op: the host's attribution) and the sea splash where it was.
--   2 the next spawn without the sphere (or with it again): `fishing test: next spawn WITHOUT the sphere`
--   3 everything taken off (the joiners' copies first, COOP.removeNow; SPC.cleanUp; SV_Recycle 2 s on), as test_s after
--     the spawn does by itself. The next press spawns again.
do
local T = { state = "idle", sphere = true, run = nil, shoals = {}, boat = nil, nextLog = 0, kills = 0 }
FISH.test = T
local function c() return CFG.specials.fishing end
local function units() return { c().units[1], c().boat_unit } end
local function reset() T.state, T.shoals, T.boat, T.run, T.removeAt, T.recycleAt, T.toggled = "idle", {}, nil, nil, nil, nil, nil end
-- (a spawn whose objects the new-object feed didn't catch) the live objects of class `cls` within 2 km of (x, y): a walk
local function findNear(cls, x, y)
    local out = {}
    for _, o in ipairs(FindAllOf(cls) or {}) do
        if liveObj(o) and inSurvival(o) then
            local okL, l = pcall(function() return o:K2_GetActorLocation() end)
            if okL and l and math.abs(l.X - x) < 200000 and math.abs(l.Y - y) < 200000 then out[#out + 1] = o end
        end
    end
    return out
end
local SHOAL_CLASS, BOAT_CLASS = "BP_GR000_dummy_CP_C", "VE028_boat2_CP_C"   -- (the stock blueprints the rows name)
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function spawnAll(now)
    local cf = c()
    if not FISH.ready then log("fishing test: the shoal's rows aren't in (FISH.setup at the main menu): spawning anyway") end
    if type(SV_SetText) == "function" then
        pcall(SV_SetText, cf.shoal_name_key, cf.shoal_name); pcall(SV_SetText, cf.boat_name_key, cf.boat_name)
    end
    FISH.splashAsset()                                    -- (loaded now, not at the first kill)
    local unit, g = cf.units[1], cf.ground_a
    local yaw = math.random() * 360
    local r = FISH.spawn(unit, g[1], g[2], cf.shoal_z, yaw)
    local objs = FISH.objs(unit)
    local seen = #objs .. " objects seen as they were made"
    if #objs == 0 and r > 0 then
        objs = findNear(SHOAL_CLASS, g[1], g[2])
        FISH.actors[unit] = { open = false, table.unpack(objs) }
        seen = "none seen as they were made; " .. #objs .. " " .. SHOAL_CLASS .. " found near it"
    end
    log(string.format("fishing test: %s at ground A (%d, %d), %d cm up, yaw %.0f: %s; %s", unit, g[1], g[2], cf.shoal_z,
        yaw, r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")"), seen))
    T.shoals = {}
    for i, o in ipairs(objs) do
        local s = { obj = o, addr = addrOf(o), i = i, name = (nameOf(o):match("([^%.:]+)$")) or "?" }
        T.shoals[#T.shoals + 1] = s
        local h, mx, mn = FISH.hp(o)
        local where = at(o)
        local sph = "no sphere (this spawn's without)"
        if T.sphere then
            local comp, what = FISH.addSphere(o, cf.sphere_m, cf.sphere_profile)
            s.sphere = comp ~= nil
            sph = comp and ("sphere " .. what) or ("sphere NOT added: " .. tostring(what))
        end
        local ov = "none"
        pcall(function()
            local oc = o.OverlapCollision
            if oc ~= nil and valid(oc) then
                local okR, rr = pcall(function() return oc:GetUnscaledSphereRadius() end)
                local okP, pp = pcall(function() return oc:GetCollisionProfileName():ToString() end)
                ov = string.format("radius %s m, profile %s", okR and string.format("%.1f", (rr or 0) / 100) or "?", okP and tostring(pp) or "?")
            end
        end)
        log(string.format("fishing test: shoal %d %s at %s: health %s, MaxHealth %s, MinHealth %s; %s; its OverlapCollision %s", i, s.name,
            where and string.format("(%.0f, %.0f, %.0f)", where.X, where.Y, where.Z) or "?", tostring(h), tostring(mx), tostring(mn), sph, ov))
    end
    local b = cf.boat_at
    local br = FISH.spawn(cf.boat_unit, b[1], b[2], cf.boat_z, math.random() * 360)
    local bo = FISH.objs(cf.boat_unit)[1]
    if not bo and br > 0 then
        bo = findNear(BOAT_CLASS, b[1], b[2])[1]
        if bo then FISH.actors[cf.boat_unit] = { open = false, bo } end
        log("fishing test: the boat wasn't seen as it was made; " .. BOAT_CLASS .. " near its spot: " .. (bo and "found" or "NOT found"))
    end
    T.boat = bo and { obj = bo, addr = addrOf(bo), name = (nameOf(bo):match("([^%.:]+)$")) or "?", writes = 0 } or nil
    local bh, bmx, bmn = nil, nil, nil
    if bo then bh, bmx, bmn = FISH.hp(bo) end
    local flags = {}
    if bo then
        for _, f in ipairs({ "bIsInvincible", "bIsInvincibleFromAI", "bIsInvincibleFromWingman", "bShowHUDBox" }) do
            local okF, x = pcall(function() return bo[f] end)
            flags[#flags + 1] = f .. " " .. (okF and tostring(x) or "?")
        end
    end
    log(string.format("fishing test: SAL's boat %s at (%d, %d), %d cm up: %s%s", cf.boat_unit, b[1], b[2], cf.boat_z,
        br > 0 and (br .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[br] or br) .. ")"),
        bo and string.format("; %s right after its spawn: health %s, MaxHealth %s, MinHealth %s; %s", T.boat.name, tostring(bh),
            tostring(bmx), tostring(bmn), table.concat(flags, ", ")) or "; its actor NOT seen"))
    T.state, T.run, T.at, T.nextLog, T.kills = "up", D, now, now + 1, 0
    T.removeAt = now + (tonumber(cf.test_s) or 300)
    hudCallout("TEST: GONE FISHIN'", string.format("%d SHOALS %s, BOAT %s", #T.shoals, T.sphere and "WITH SPHERES" or "NO SPHERES",
        bo and "UP" or "NOT UP"))
end
local function removeAll(now, why)
    T.state = "removing"
    local list, gone = units(), {}
    for _, s in ipairs(T.shoals) do if s.down and s.addr then gone[s.addr] = true end end
    for _, u in ipairs(list) do
        if COOP and COOP.host and COOP.host() and COOP.removeNow then pcall(COOP.removeNow, u) end   -- (the joiners' copies first)
        local l = { at = os.clock() }
        for _, o in ipairs(FISH.objs(u)) do if not gone[addrOf(o)] then l[#l + 1] = o end end
        SPC.CLEAN_OBJ[u] = l                              -- (sv_rounds.lua SPC.cleanUp's record: finished off, no pay)
    end
    local n = SPC.cleanUp(list, "the fishing test over (" .. why .. ")", true, D and D.now or 0)
    log(string.format("fishing test: taken off (%s): %d objects finished off or switched off; %d shoals were shot down in it", why, n, T.kills))
    T.recycleAt = now + 2
    hudCallout("TEST: FISHING OFF", why:upper())
end
local function recycle()
    local out = {}
    for _, u in ipairs(units()) do
        local n0 = type(SV_UnitAlive) == "function" and SV_UnitAlive(u) or -5
        local okR, r = false, "no SV_Recycle"
        if type(SV_Recycle) == "function" then
            crumb("fishing test: SV_Recycle " .. u)
            okR, r = pcall(SV_Recycle, u, 1)
        end
        out[#out + 1] = string.format("%s %d alive -> SV_Recycle %s -> %s alive", u, n0, okR and tostring(r) or ("error " .. tostring(r)),
            tostring(type(SV_UnitAlive) == "function" and SV_UnitAlive(u) or "?"))
    end
    log("fishing test: off the spawner's list: " .. table.concat(out, "; "))
    FISH.actors[c().units[1]], FISH.actors[c().boat_unit] = nil, nil
    reset()
end
local function shoalDown(s, now)
    s.down = true
    T.kills = T.kills + 1
    if liveObj(s.obj) then pcall(KILL.read, s) end       -- (the last hits, while it's still there: never on a freed one)
    local okB, by = pcall(KILL.by, s)
    local d = s.dmg or {}
    local where = s.at
    local splash = where and FISH.splash({ X = where.X, Y = where.Y, Z = c().sea_z })
    log(string.format("fishing test: shoal %d %s down at +%.0f s: by %s%s (damage: you %.0f, wingmate %.0f, allies %.0f, other %.0f; "
        .. "its map named %s); the splash %s", s.i, s.name, now - (T.at or now), okB and tostring(by) or ("? " .. tostring(by)),
        type(s.killer) == "number" and (" (player " .. (s.killer + 1) .. ")") or "", d.you or 0, d.wingmate or 0, d.allies or 0,
        d.other or 0, tostring(s.who or "-"), splash and "played" or "NOT played"))
end
local function tick(now)
    if T.state == "idle" then return end
    if T.run ~= D or (levelTorn and levelTorn()) then reset(); return end
    if T.state == "removing" then
        if T.recycleAt and now >= T.recycleAt then recycle() end
        return
    end
    if now >= (T.removeAt or math.huge) then removeAll(now, string.format("%d s after the spawn", math.floor(c().test_s or 300))); return end
    if now < T.nextLog then return end
    T.nextLog = now + 1
    local parts = {}
    for _, s in ipairs(T.shoals) do
        if not s.down then
            local up = liveObj(s.obj)
            local h, mx = nil, nil
            if up then
                h, mx = FISH.hp(s.obj)
                s.at = at(s.obj) or s.at
                s.who = FISH.who(s.obj)
                pcall(KILL.read, s)
            end
            if not up or (type(h) == "number" and h <= 0) then
                shoalDown(s, now)
                parts[#parts + 1] = string.format("%d DOWN", s.i)
            else
                parts[#parts + 1] = string.format("%d %s/%s %s", s.i, tostring(h), tostring(mx), s.who or "-")
            end
        end
    end
    local b = T.boat
    local bt = "boat not up"
    if b and liveObj(b.obj) then
        local h, mx, mn = FISH.hp(b.obj)
        local want = tonumber(c().boat_min_health) or 1
        if type(mn) == "number" and mn < want and pcall(function() b.obj.MinHealth = want end) then
            b.writes = b.writes + 1
            if b.writes == 1 or b.writes % 30 == 0 then
                log(string.format("fishing test: the boat's MinHealth read %s: the field written back to %s (%d times)", tostring(mn), tostring(want), b.writes))
            end
        end
        bt = string.format("boat %s/%s min %s %s", tostring(h), tostring(mx), tostring(mn), FISH.who(b.obj))
    elseif b then
        bt = "boat GONE"
    end
    log(string.format("fishing test: +%.0f s: shoals %s; %s", now - (T.at or now), #parts > 0 and table.concat(parts, "; ") or "all down", bt))
end
testKey("F10", "sv_fishing.lua's fishing test", function()
    local now = os.clock()
    if not (D and D.now) or not nativeReady() then log("fishing test: Ctrl+F10 outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("fishing test: Ctrl+F10: the host spawns the shoals (you're a joiner)"); return end
    if T.run ~= D then reset() end
    if T.state == "idle" then
        spawnAll(now)
    elseif T.state == "up" and not T.toggled then
        T.sphere, T.toggled = not T.sphere, true
        log("fishing test: next spawn " .. (T.sphere and "WITH" or "WITHOUT") .. " the sphere (the shoals up now keep theirs)")
        hudCallout("TEST: NEXT SPAWN", T.sphere and "WITH SPHERES" or "WITHOUT SPHERES")
    elseif T.state == "up" then
        T.toggled = nil
        removeAll(now, "Ctrl+F10")
    else
        log("fishing test: still being taken off: press again in a moment")
    end
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "fishing test", fn = tick }
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the fishing test"] = function() reset(); T.toggled = nil end end
end
-- TEST ONLY END
