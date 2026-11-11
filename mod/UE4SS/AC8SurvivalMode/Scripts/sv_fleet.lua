-- sv_fleet.lua: INVINCIBLE FLEET's tests (round 30, the user's dev install only: docs/design/INVINCIBLE_FLEET.md,
-- docs/design/INVINCIBLE_FLEET_RISE_FORD.md). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order after
-- sv_spaceport (whose Ford it spawns, SV_Unit_SpFord): a name another part uses is a global of this mod's Lua state, its
-- own helpers stay local. The whole part is one test-only block, which tools/strip_test_only.py takes out of every
-- release and tester zip (only this header is left there), its settings (CFG.specials.fleet) with it.
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
--                     (deck_m up in each copy) along the keel. A second Ctrl+B takes it off (SV_Recycle).
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
}
-- (set after sv_config_ini.lua took CFG_DEFAULTS: shipped as it is, so no difference the leaderboard's LB.edited or the
-- co-op settings sync would see)
if type(CFG_DEFAULTS) == "table" and type(CFG_DEFAULTS.specials) == "table" and type(deepCopy) == "function" then
    CFG_DEFAULTS.specials.fleet = deepCopy(CFG.specials.fleet)
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

-- the Ford still on the spawner's list (a test's before, a leftover) taken off before a spawn; what was done, or nil
local function clearFord(why)
    local n0 = type(SV_UnitAlive) == "function" and SV_UnitAlive(FORD) or 0
    if (tonumber(n0) or 0) <= 0 or type(SV_Recycle) ~= "function" then return nil end
    crumb("geofon: SV_Recycle " .. FORD .. " (" .. why .. ")")
    local okR, r = pcall(SV_Recycle, FORD, 1)
    return string.format("%s was still on the spawner's list (%s up): SV_Recycle %s", FORD, tostring(n0),
        okR and tostring(r) or ("error " .. tostring(r)))
end

-- the Ford spawned alone ahead_cm in front of you, broadside: its state { raw = the objects made, t = 0, ... } or nil, why
local function spawnFord(ahead, tag)
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
    local cleared = clearFord(tag)
    if cleared then log("geofon: " .. tag .. ": " .. cleared) end
    GEO.catching = {}
    spawningUnit = FORD
    local ok, r = pcall(SV_Spawn, FORD, x, y, gc().z_cm, face)
    spawningUnit = nil
    local raw = GEO.catching
    GEO.catching = nil
    r = ok and tonumber(r) or -5
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, FORD, r) end
    local said = r > 0 and (r .. " up") or ("not spawned (" .. tostring((SV_ERR and SV_ERR[r]) or (ok and r) or "error") .. ")")
    log(string.format("geofon: %s, %s at (%.0f, %.0f, %g) facing %.0f (you at yaw %.0f): %s; %d objects made%s; its deck off (the "
        .. "Spaceport round's only)", tag, FORD, x, y, num(gc().z_cm, 50), face, yaw, said, #raw, ok and "" or (": " .. tostring(r))))
    if r <= 0 then return nil, said end
    return { raw = raw, t = 0, last = os.clock(), tries = 0, x = x, y = y, face = face }
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
    for _, o in ipairs(G.raw or {}) do
        local e = keep(o)
        if e then
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

-- a test's Ford taken off: hidden at once, then off the spawner's list (SV_Recycle: its actors destroyed a moment later)
local function takeOff(G, why)
    fxOff(G, 0)
    fxGone(G, true)
    local hidden, list = 0, { G.hull }
    for _, e in ipairs(G.parts or {}) do list[#list + 1] = e end
    for _, e in pairs(list) do
        if same(e) and pcall(function() e.obj:SetActorHiddenInGame(true) end) then hidden = hidden + 1 end
    end
    if COOP and COOP.host and COOP.host() and COOP.removeNow then pcall(COOP.removeNow, FORD) end
    local r = "no SV_Recycle in this runtime"
    if type(SV_Recycle) == "function" then
        crumb("geofon: SV_Recycle " .. FORD .. " (" .. why .. ")")
        local okR, x = pcall(SV_Recycle, FORD, 1)
        r = "SV_Recycle " .. (okR and tostring(x) or ("error " .. tostring(x)))
    end
    return string.format("%d of its objects hidden, %s", hidden, r)
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
        if ok == false then GEO.look = nil end
        if ok then lookSetup(L); L.nextLine = L.t end
        if not L.posed then return end
    end
    if not same(L.hull) then
        log(string.format("geofon: break look over at +%.0f s: its hull is gone", L.t))
        GEO.look = nil
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
        if ok == false then GEO.cur = nil; return end
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

testKey("B", "sv_fleet.lua's GEOFON V-break look (T1)", function()
    if GEO.look then
        local L = GEO.look
        GEO.look = nil
        log(string.format("geofon: break look off at +%.0f s (Ctrl+B): %s", L.t, takeOff(L, "Ctrl+B")))
        hudCallout("TEST: GEOFON V-BREAK", "OFF")
        return
    end
    if not canRun("Ctrl+B") then return end
    if GEO.cur then
        log(string.format("geofon: Ctrl+B: GEOFON's stages test taken off first (%s)", takeOff(GEO.cur, "Ctrl+B")))
        GEO.cur = nil
    end
    local L, why = spawnFord(num(gc().look.ahead_cm, 350000), "Ctrl+B (the V-break look)")
    if not L then hudCallout("TEST: GEOFON V-BREAK", "NOT SPAWNED"); log("geofon: Ctrl+B: " .. tostring(why)); return end
    GEO.look = L
end)

testKey("G", "sv_fleet.lua's GEOFON stages (T2)", function()
    local G = GEO.cur
    if G and G.ready and not G.down and same(G.hull) then hit(G); return end
    if G and not G.ready then log("geofon: Ctrl+G: GEOFON is still coming up"); return end
    if not canRun("Ctrl+G") then return end
    if GEO.look then
        log(string.format("geofon: Ctrl+G: the V-break look taken off first (%s)", takeOff(GEO.look, "Ctrl+G")))
        GEO.look = nil
    end
    if G then fxOff(G, 0); fxGone(G, true); GEO.cur = nil end   -- (one sunk: a new GEOFON, the old one recycled at its spawn)
    local N, why = spawnFord(num(gc().test.ahead_cm, 400000), "Ctrl+G (GEOFON's stages)")
    if not N then hudCallout("TEST: GEOFON", "NOT SPAWNED"); log("geofon: Ctrl+G: " .. tostring(why)); return end
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
-- TEST ONLY END
