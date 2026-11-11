-- sv_tanicorn.lua: THE TANICORN's milestone 0 test (docs/re/TANICORN.md; the user's Anomaly boss, 2026-11-09).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order: a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local.
--
-- One gun mount of Survival's own (BP_SV_Tani_T5: our skeleton, mesh, blueprint straight on AC8's native
-- ALiveAIGroundVehicleObject, built and cooked by tools/tanicorn; its container SurvivalMode_Tani_P is staged with TANI=1
-- only) spawned through Survival's rows as GONE FISHIN's shoals are: the world-data unit SV_Unit_TaniTest on its mission
-- row, its DT_NPC row SV_Npc_TaniMount and model row SV_Model_TaniMount (whose blueprint is ours) added from Survival's
-- tables to the game's at the first press. The user's dev install only (TANI=1; never in a TESTER zip: the user,
-- 2026-11-11): all of it is in the dev-only block below (tools/strip_test_only.py takes it out of every zip).
--   Ctrl+T in a run   (0.74.43 had Ctrl+`, the game console's key) our class loaded by itself first (`tanicorn: class
--                     ...`: AC8 took our cooked blueprint or not), then the mount spawned 3 km ahead on the sea through the
--                     shoals' spawn capture (FISH.spawn: every AI object the spawner makes, `tanicorn: the spawn made ...`),
--                     looked at again 1 s and 4 s on. While one is up (60 s after a spawn): its health and its aim bones'
--                     angles every 2 s (`tanicorn: ... yaw ... pitch ...`): AC8's fire control turning our bones to you.
-- (0.74.43, the user's first run: rows in, SV_Spawn "1 up" four times, no BP_SV_Tani_T5_C found in 33 walks)
-- (0.74.45: our class loads in AC8 with its fire control; the spawn still made no object: the rows were added too late)
-- DEV ONLY BEGIN
TANI = { unit = "SV_Unit_TaniTest", npc = "SV_Npc_TaniMount", model = "SV_Model_TaniMount",
         class = "BP_SV_Tani_T5_C", class_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T5.BP_SV_Tani_T5_C",
         cdo_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T5.Default__BP_SV_Tani_T5_C",
         dummy = "BP_GR000_dummy_CP_C", name_key = "SV_TaniMount_Name", name = "TANICORN MOUNT",
         ahead_cm = 300000, z_cm = 700, every_s = 2.0, watch_s = 60 }
do
local T = { rows = nil, next = 0, seen = {}, until_ = 0, checks = {} }

local function rowsIn()                                  -- the model first: the row names it (as FISH.setup)
    if T.rows then return true, "in already" end
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows)
    local mt, mr = loadObject(ACE.model_table), loadObject(ACE.model_rows)
    if not (npc and mine and mt and mr) then return false, "the row tables didn't load" end
    for _, t in ipairs({ npc, mine, mt, mr }) do pin(t, nameOf(t)) end
    local function addRow(dst, src, row)
        local _, have = dtCall(dst, "FindRow", row)
        if have == nil then
            local _, r = dtCall(src, "FindRow", row)
            if r == nil then return false end
            dtCall(dst, "AddRow", row, r)
            _, have = dtCall(dst, "FindRow", row)
        end
        return have ~= nil
    end
    local m = addRow(mt, mr, TANI.model)
    local n = addRow(npc, mine, TANI.npc)
    if type(SV_SetText) == "function" then pcall(SV_SetText, TANI.name_key, TANI.name) end
    T.rows = m and n
    return T.rows, string.format("%s %s, %s %s", TANI.model, m and "in DT_NPC_Model" or "NOT added", TANI.npc,
        n and "in DT_NPC" or "NOT added")
end

-- (0.74.46) the rows at the main menu, as the shoal's (FISH.setup): 0.74.43-0.74.45 added them at the key press, after
-- the level was up, and the spawner made the unit with no object in it ("up, 0 aircraft") although the rows were in
function TANI.setup()
    if TANI.setupDone or not gameInstance() then return end
    TANI.tries = (TANI.tries or 0) + 1
    local ok, why = rowsIn()
    if ok or TANI.tries >= 20 then
        TANI.setupDone = true
        log("tanicorn: rows at the main menu: " .. why)
    end
end

-- our cooked class, loaded by itself: whether AC8 takes it, and what its defaults hold
local function classCheck()
    local cls, why = loadObject(TANI.class_path)
    if not cls then return "NOT loaded: " .. tostring(why) end
    pin(cls, "tanicorn class")
    local parts = { "loaded " .. nameOf(cls) }
    local cdo = StaticFindObject(TANI.cdo_path)
    if valid(cdo) then
        local arms, mesh, dmg = "?", "?", "?"
        pcall(function() arms = tostring(#cdo.FireControlSystemComponent.AllArms) end)
        pcall(function() dmg = tostring(valid(cdo.DamagedStateComponent)) end)
        pcall(function() mesh = cdo.FireControlSystemComponent.AllArms[1].LauncherModule.MeshComponentName:ToString() end)
        parts[#parts + 1] = string.format("defaults: fire control arms %s, launcher mesh %s, damage state %s", arms, mesh, dmg)
    else
        parts[#parts + 1] = "its defaults object not found"
    end
    return table.concat(parts, "; ")
end

local function at(o)
    local ok, l = pcall(function() return o:K2_GetActorLocation() end)
    return ok and l and string.format("(%.0f, %.0f, %.0f)", l.X, l.Y, l.Z) or "?"
end

local function describe(list)
    local out = {}
    for _, o in ipairs(list) do
        local cls = "?"
        pcall(function() cls = o:GetClass():GetFName():ToString() end)
        out[#out + 1] = string.format("%s [%s] at %s%s", (nameOf(o):match("([^%.:]+)$")) or "?", cls, at(o),
            liveObj(o) and "" or " (gone)")
    end
    return #out > 0 and table.concat(out, "; ") or "nothing"
end

local function bone(o, name)                             -- a bone's component-space rotation, "y/p" degrees
    local ok, r = pcall(function()
        local v = o.TurretPoseableMesh:GetBoneRotationByName(FName(name), 1)
        return string.format("%.1f/%.1f", v.Yaw, v.Pitch)
    end)
    if ok then return r end
    if not T.boneErr then T.boneErr = true; log("tanicorn: reading " .. name .. " failed: " .. tostring(r)) end
    return "?"
end

-- (0.74.46) the class spawned straight, as AC7's laser is (sv_escort_li.lua): BeginDeferredActorSpawnFromClass +
-- FinishSpawningActor, AlwaysSpawn, no owner: whether our blueprint comes up as an actor at all, apart from the spawner
local function direct(x, y, face)
    local cls = loadObject(TANI.class_path)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (cls and valid(gs) and liveObj(survivalPC)) then return nil, "no class / GameplayStatics / player controller" end
    local h = math.rad(face) / 2
    local t = { Rotation = { X = 0, Y = 0, Z = math.sin(h), W = math.cos(h) }, Translation = { X = x, Y = y, Z = TANI.z_cm },
                Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, a = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)
    if not (okB and a and valid(a)) then return nil, "deferred spawn: " .. tostring(a) end
    local okF, fin = pcall(function() return gs:FinishSpawningActor(a, t, 1) end)
    if not (okF and valid(a)) then return nil, "not finished: " .. tostring(fin) end
    return a, "spawned " .. nameOf(a)
end

local function look(tag, made)
    local alive = type(SV_UnitAlive) == "function" and SV_UnitAlive(TANI.unit) or "?"
    local ours = 0
    for _, o in ipairs(FindAllOf(TANI.class) or {}) do
        if valid(o) and not nameOf(o):find("Default__", 1, true) then ours = ours + 1 end
    end
    local dummies = 0
    if FISH and FISH.findNear and T.x then dummies = #FISH.findNear(TANI.dummy, T.x, T.y, 100000) end
    log(string.format("tanicorn: %s: SV_UnitAlive %s; the spawn's objects: %s; %d of our class in the level, %d stock dummies near the spot",
        tag, tostring(alive), describe(made), ours, dummies))
end

local function watch(now)
    for i = #T.checks, 1, -1 do                          -- the 1 s and 4 s looks after a spawn
        local c = T.checks[i]
        if now >= c.at then table.remove(T.checks, i); look(c.tag, c.made) end
    end
    if now > T.until_ or now < T.next then return end
    T.next = now + TANI.every_s
    local parts = {}
    for _, o in ipairs(FindAllOf(TANI.class) or {}) do
        if valid(o) and not nameOf(o):find("Default__", 1, true) then
            local h, mx = "?", "?"
            pcall(function() h = o.HealthInternal end)
            pcall(function() mx = o.MaxHealth end)
            local id = addrOf(o)
            if not T.seen[id] then
                T.seen[id] = true
                local arms = "?"
                pcall(function() arms = tostring(#o.FireControlSystemComponent.AllArms) end)
                log(string.format("tanicorn: mount %s up at %s: fire control arms %s, health %s/%s", nameOf(o), at(o), arms,
                    tostring(h), tostring(mx)))
            end
            parts[#parts + 1] = string.format("%s hp %s/%s yaw %s pitch %s", (nameOf(o):match("([^%.:]+)$")) or "?",
                tostring(h), tostring(mx), bone(o, "turret_yaw"), bone(o, "turret_pitch"))
        end
    end
    if #parts > 0 then log("tanicorn: " .. table.concat(parts, "; ")) end
end

testKey("T", "sv_tanicorn.lua's mount test", function()
    if not (D and D.now) or not nativeReady() then log("tanicorn: Ctrl+T outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("tanicorn: Ctrl+T: the host spawns it (you're a joiner)"); return end
    log("tanicorn: class " .. classCheck())
    local ok, why = rowsIn()
    log("tanicorn: rows: " .. why)
    local p = playerLocation()
    if not p then log("tanicorn: no player location"); return end
    local yaw = 0
    pcall(function()
        local pc = liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController")
        yaw = pc.Pawn:K2_GetActorRotation().Yaw
    end)
    local x = p.X + math.cos(math.rad(yaw)) * TANI.ahead_cm
    local y = p.Y + math.sin(math.rad(yaw)) * TANI.ahead_cm
    T.x, T.y = x, y
    local face = (yaw + 180) % 360
    local r
    if FISH and FISH.spawn then r = FISH.spawn(TANI.unit, x, y, TANI.z_cm, face) else r = SV_Spawn(TANI.unit, x, y, TANI.z_cm, face) end
    local list = {}
    for _, o in ipairs((FISH and FISH.actors and FISH.actors[TANI.unit]) or {}) do list[#list + 1] = o end
    local said = r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")")
    log(string.format("tanicorn: Ctrl+T, %s at (%.0f, %.0f, %d) facing %.0f: %s%s", TANI.unit, x, y, TANI.z_cm, face,
        said, ok and "" or " (its rows aren't all in)"))
    log("tanicorn: the spawn made " .. describe(list))
    if #list == 0 then                                    -- (the spawner made none: our class straight, beside the spot)
        local d, why = direct(x + 30000, y, face)
        log("tanicorn: straight spawn of our class 300 m from the spot: " .. why)
        if d then list[#list + 1] = d end
    end
    hudCallout("TEST: TANICORN MOUNT", r > 0 and "3 KM AHEAD" or "NOT SPAWNED")
    local now = os.clock()
    T.checks[#T.checks + 1] = { at = now + 1, tag = "+1 s", made = list }
    T.checks[#T.checks + 1] = { at = now + 4, tag = "+4 s", made = list }
    T.next, T.until_ = 0, now + TANI.watch_s
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn mount watch", fn = watch }
end
-- DEV ONLY END
