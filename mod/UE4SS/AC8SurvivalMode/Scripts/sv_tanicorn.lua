-- sv_tanicorn.lua: THE TANICORN's milestone 0 test (docs/re/TANICORN.md; the user's Anomaly boss, 2026-11-09).
-- Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order: a name another part uses is a global of this
-- mod's Lua state, its own helpers stay local.
--
-- One gun mount of Survival's own (BP_SV_Tani_T5: our skeleton, mesh, blueprint straight on AC8's native
-- ALiveAIGroundVehicleObject, built and cooked by tools/tanicorn; its container SurvivalMode_Tani_P is staged with TANI=1
-- only) spawned through Survival's rows as GONE FISHIN's shoals are: the world-data unit SV_Unit_TaniTest on its mission
-- row, its DT_NPC row SV_Npc_TaniMount and model row SV_Model_TaniMount (whose blueprint is ours) added from Survival's
-- tables to the game's at the first press. Test builds only: all of it is in the test-only block below.
--   Ctrl+T in a run   (0.74.43 had Ctrl+`, the game console's key) our class loaded by itself first (`tanicorn: class
--                     ...`: AC8 took our cooked blueprint or not), then the mount spawned 3 km ahead on the sea through the
--                     shoals' spawn capture (FISH.spawn: every AI object the spawner makes, `tanicorn: the spawn made ...`),
--                     looked at again 1 s and 4 s on. While one is up (60 s after a spawn): its health and its aim bones'
--                     angles every 2 s (`tanicorn: ... yaw ... pitch ...`): AC8's fire control turning our bones to you.
-- (0.74.43, the user's first run: rows in, SV_Spawn "1 up" four times, no BP_SV_Tani_T5_C found in 33 walks)
-- (0.74.45: our class loads in AC8 with its fire control; the spawn still made no object: the rows were added too late)
-- TEST ONLY BEGIN
TANI = { unit = "SV_Unit_TaniTest", npc = "SV_Npc_TaniMount", model = "SV_Model_TaniMount",
         class = "BP_SV_Tani_T5_C", class_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T5.BP_SV_Tani_T5_C",
         cdo_path = "/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T5.Default__BP_SV_Tani_T5_C",
         dummy = "BP_GR000_dummy_CP_C", name_key = "SV_TaniMount_Name", name = "TANICORN MOUNT",
         fcs = "SV_FCS_TaniT5", fcs_src = "NPC_FCS_FlakGun000", fcs_slots = 2,   -- (0.74.59; survival_events.TANI_FCS)
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
    -- (0.74.59) the mount's fire control row (its NPC row's NpcFCSId0, tools/build_survival.py): the stock flak gun's
    -- NPC_FCS_FlakGun000 with the twin mount's two muzzles. The row path is the one that gives the arm its muzzles
    -- (0.74.58, the user: "THE GUN FIRED FROM THE BARREL THIS TIME", "only one barrel was working": the row's SlotNum 1)
    local fcs = loadObject(FCS_TABLE)
    if fcs then
        pin(fcs, nameOf(fcs))
        local okF, whyF = cloneRow(fcs, TANI.fcs_src, TANI.fcs, function(r)
            r.SlotNum = TANI.fcs_slots
            if (tonumber(r.MagazineCapacity) or 0) < TANI.fcs_slots then r.MagazineCapacity = TANI.fcs_slots end
        end)
        local slots, mag = "?", "?"
        pcall(function()
            local _, r = dtCall(fcs, "FindRow", TANI.fcs)
            slots, mag = tostring(r.SlotNum), tostring(r.MagazineCapacity)
        end)
        log(string.format("tanicorn: fire control row %s from %s: %s (SlotNum %s, magazine %s)", TANI.fcs, TANI.fcs_src,
            okF and "in" or ("NOT made: " .. tostring(whyF)), slots, mag))
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

-- (0.74.51) a bone or socket of the turret mesh in the world: "yaw/pitch" degrees, or "(x, y, z) yaw/pitch" with its
-- place. GetBoneRotationByName handed back no Yaw in the user's run of 0.74.50 ("yaw ? pitch ?"); a skinned mesh's
-- GetSocketRotation / GetSocketLocation take a bone name as well as a socket's.
-- (0.74.54) the turret mesh from the actor's component tree (SPC.V.comps, as the ZFA-44 test reads its sockets):
-- o.TurretPoseableMesh gave rotators with no Yaw for bones and sockets alike (the user's runs of 0.74.50-0.74.53)
local function turretMesh(o)
    local m
    if SPC and SPC.V and SPC.V.comps then
        pcall(function() m = SPC.V.comps(o, "/Script/Engine.PoseableMeshComponent")[1] end)
    end
    return m or o.TurretPoseableMesh
end

-- (0.74.54) what the engine sees of a mount's muzzle (0.74.50-0.74.53: every shell, AA stream or flak, left the turret
-- mesh's origin, under the mount, along its forward: SOC_Gun_01 never found): the mesh, its asset (and the deprecated
-- SkeletalMesh field), the asset's sockets, whether the component knows SOC_Gun_01, its bone, and where it puts it
-- against the mesh's origin (at the barrels' tips: ~ +10 m forward, +4 m up; at (0, 0, 0): not found)
local MUZZLE = "SOC_Gun_01"
local function muzzleProbe(m)
    local out = {}
    local function try(label, f)
        local ok, v = pcall(f)
        out[#out + 1] = label .. " " .. (ok and tostring(v) or ("? (" .. tostring(v):sub(1, 80) .. ")"))
    end
    try("mesh", function() return nameOf(m):match("([^%.:]+)$") end)
    try("asset", function() return nameOf(m.SkinnedAsset):match("([^%.]+)$") end)
    try("old field", function() return valid(m.SkeletalMesh) and nameOf(m.SkeletalMesh):match("([^%.]+)$") or "empty" end)
    try("asset sockets", function() return m.SkinnedAsset:NumSockets() end)
    try("asset finds " .. MUZZLE, function() return valid(m.SkinnedAsset:FindSocket(FName(MUZZLE))) end)
    try("component has it", function() return m:DoesSocketExist(FName(MUZZLE)) end)
    try("its bone", function() return m:GetSocketBoneName(FName(MUZZLE)):ToString() end)
    try("at", function()
        local l, c = m:GetSocketLocation(FName(MUZZLE)), m:K2_GetComponentLocation()
        return string.format("(%+.0f, %+.0f, %+.0f) cm from the mesh's origin", l.X - c.X, l.Y - c.Y, l.Z - c.Z)
    end)
    try("names", function()
        local t = {}
        m:GetAllSocketNames():ForEach(function(_, e) t[#t + 1] = e:get():ToString() end)
        return #t > 0 and table.concat(t, ",") or "none"
    end)
    return table.concat(out, "; ")
end

-- the same of the first stock turret mesh in the level with that muzzle (the airfield's guns), once a spawn: the
-- difference between ours and a stock one the game fires from
local function stockProbe(o)
    local me = addrOf(o)
    local n = 0
    for _, m in ipairs(FindAllOf("PoseableMeshComponent") or {}) do
        n = n + 1
        if n > 400 then break end
        local ok, has = pcall(function()
            local ow = m:GetOwner()
            return valid(ow) and addrOf(ow) ~= me and not nameOf(ow):find("Tani", 1, true) and m:DoesSocketExist(FName(MUZZLE))
        end)
        if ok and has then
            local owner = "?"
            pcall(function() owner = nameOf(m:GetOwner()):match("([^%.:]+)$") end)
            return owner .. ": " .. muzzleProbe(m)
        end
    end
    return string.format("none with %s among %d turret meshes", MUZZLE, n)
end

local function heading(dx, dy, dz)                      -- yaw / pitch (degrees) of a direction
    return math.deg(math.atan(dy, dx)), math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
end

-- (0.74.55) where the barrels point and where the muzzle is, from positions alone: 0.74.54's probe read socket places
-- right (SOC_Gun_01 at the barrel's tip) while every rotation read gave no Yaw. The barrel = turret_pitch -> SOC_Gun_01.
local function aim(o)
    local ok, r, t = pcall(function()
        local m = turretMesh(o)
        local ml = o:K2_GetActorLocation()
        local p, q = m:GetSocketLocation(FName("BN_turret_pitch")), m:GetSocketLocation(FName(MUZZLE))
        local y, pt = heading(q.X - p.X, q.Y - p.Y, q.Z - p.Z)
        return string.format("barrel yaw %.1f pitch %.1f, muzzle (%+.0f, %+.0f, %+.0f) from the mount", y, pt,
            q.X - ml.X, q.Y - ml.Y, q.Z - ml.Z), { x = q.X - ml.X, y = q.Y - ml.Y, z = q.Z - ml.Z, yaw = y, pitch = pt }
    end)
    if ok then return r, t end
    if not T.aimErr then T.aimErr = true; log("tanicorn: reading the barrel failed: " .. tostring(r)) end
    return "barrel ?"
end

-- (0.74.55) every flak shell the game makes while a mount is watched (NotifyOnNewObject, as ALLY's ESM fields: the actor
-- at its construction, before it has a place), then at the next tick its place and velocity run back over its age to
-- where it started, against the mount and its muzzle at that moment. The user's runs of 0.74.50-0.74.54: the fire "from
-- below the mount" while the engine puts SOC_Gun_01 at the barrel's tip: this is where the game actually starts it.
-- (0.74.56) every flak gun the game makes, ours or a stock one (the Spaceport island's GR023s: Ctrl+END), for the first
-- 12 of each a session: its owner, where it sits against its owner, and where it says it hangs (ALiveAttachedWeapon's
-- AttachedComponent / AttachedSocketName / bIsBaseAttached). 0.74.55 showed ours sitting at the mount's origin to the
-- centimetre with no velocity: LiveFlakGun is an ALiveAttachedWeapon, the bursts come from where it hangs.
local NEWSHELL = {}
if type(NotifyOnNewObject) == "function" then
    pcall(NotifyOnNewObject, "/Script/Live.LiveFlakGun", function(o)
        if #NEWSHELL < 32 then NEWSHELL[#NEWSHELL + 1] = { o = o, t = os.clock() } end
    end)
end

local function hangs(w)                                   -- an attached weapon's own record of where it hangs
    local comp, owner, sock, base = "?", "?", "?", "?"
    pcall(function()
        local c = w.AttachedComponent
        if valid(c) then
            comp = c:GetFName():ToString()
            pcall(function() owner = (nameOf(c:GetOwner()):match("([^%.:]+)$")) or "?" end)
        else
            comp = "none"
        end
    end)
    pcall(function() sock = w.AttachedSocketName:ToString() end)
    pcall(function() base = tostring(w.bIsBaseAttached) end)
    return string.format("hangs on %s (of %s) at socket %s, base attached %s", comp, owner, sock, base)
end

local function stockShells(list, now)
    for _, s in ipairs(list) do
        pcall(function()
            local o = s.o
            if not valid(o) then return end
            local ow = o:GetOwner()
            if valid(ow) and nameOf(ow):find("Tani", 1, true) then return end
            T.stock = (T.stock or 0) + 1
            if T.stock > 12 then return end
            local l, ol = o:K2_GetActorLocation(), valid(ow) and ow:K2_GetActorLocation()
            log(string.format("tanicorn: a stock flak gun %d (%s): at (%+.0f, %+.0f, %+.0f) from its owner %s; %s",
                T.stock, (nameOf(o):match("([^%.:]+)$")) or "?", ol and l.X - ol.X or 0, ol and l.Y - ol.Y or 0,
                ol and l.Z - ol.Z or 0, valid(ow) and ((nameOf(ow):match("([^%.:]+)$")) or "?") or "none", hangs(o)))
        end)
    end
end

local function shells(now)
    if #NEWSHELL == 0 then return end
    local list = NEWSHELL
    NEWSHELL = {}
    stockShells(list, now)
    local mount
    for _, o in ipairs(FindAllOf(TANI.class) or {}) do
        if valid(o) and not nameOf(o):find("Default__", 1, true) then mount = o; break end
    end
    if not mount then return end
    local _, a = aim(mount)
    local ml
    pcall(function() ml = mount:K2_GetActorLocation() end)
    if not ml then return end
    for _, s in ipairs(list) do
        local mine = false
        pcall(function() mine = nameOf(s.o:GetOwner()):find("Tani", 1, true) ~= nil end)
        if mine then T.shells = (T.shells or 0) + 1 end
        if mine and T.shells <= 12 then
            local ok, line = pcall(function()
                local l, v = s.o:K2_GetActorLocation(), s.o:GetVelocity()
                local age = now - s.t
                local sx, sy, sz = l.X - v.X * age - ml.X, l.Y - v.Y * age - ml.Y, l.Z - v.Z * age - ml.Z
                local y, pt = heading(v.X, v.Y, v.Z)
                return string.format("shell %d: started (%+.0f, %+.0f, %+.0f) from the mount, flying yaw %.1f pitch %.1f at %.0f m/s " ..
                    "(seen %.2f s after it was made, now (%+.0f, %+.0f, %+.0f)); the muzzle (%s), the barrel yaw %s pitch %s; %s",
                    T.shells, sx, sy, sz, y, pt, math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) / 100, age,
                    l.X - ml.X, l.Y - ml.Y, l.Z - ml.Z,
                    type(a) == "table" and string.format("%+.0f, %+.0f, %+.0f", a.x, a.y, a.z) or "?",
                    type(a) == "table" and string.format("%.1f", a.yaw) or "?", type(a) == "table" and string.format("%.1f", a.pitch) or "?",
                    hangs(s.o))
            end)
            log("tanicorn: " .. (ok and line or ("a shell, not read: " .. tostring(line))))
        end
    end
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
    shells(now)                                          -- (every tick: the shells made since the last)
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
                log("tanicorn: our muzzle: " .. muzzleProbe(turretMesh(o)))
                log("tanicorn: a stock turret's muzzle: " .. stockProbe(o))
            end
            local ay = "?"
            pcall(function() ay = string.format("%.1f", o:K2_GetActorRotation().Yaw) end)
            parts[#parts + 1] = string.format("%s hp %s/%s actor yaw %s, %s",
                (nameOf(o):match("([^%.:]+)$")) or "?", tostring(h), tostring(mx), ay, (aim(o)))
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
    T.next, T.until_, T.shells = 0, now + TANI.watch_s, 0
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn mount watch", fn = watch }
end
-- TEST ONLY END
