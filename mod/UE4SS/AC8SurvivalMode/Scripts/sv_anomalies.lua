-- sv_anomalies.lua: the specials' Lua: MINDRIPPER, AB.L..IN, VALKA and the kinds table (SPC, ANOM).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

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
        -- (a whole number: HealthInternal is an integer and 4500 x 1.12 = 5040.000000000001 went in as 0, so it was
        -- shot down unseen a second after it came; a friend's log of 2026-10-24, round 7)
        local okH, h0 = pcall(function() return o.HealthInternal end)
        if okH and type(h0) == "number" and h0 > 0 and hx ~= 1 then pcall(function() o.HealthInternal = math.floor(h0 * hx + 0.5) end) end
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

-- VALKA (CFG.specials.valka; tools/survival_events.py VALKA_*): AC7 Mission 18's opener (a hidden railgun of its own,
-- fixed opener_km along your aim: a flash, the charge, one shot), her reveal where it fired from with the focus camera, then
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
-- her railguns fire the land battleship's round (c.eml_weapon; user, 2026-10-24: "try putting a land battleship
-- railgun weapon on her EML"): each projectile module that sits beside an x40a railgun's launcher module (the same
-- outer) gets its class and class default. Instances only (her railguns and the opener's, the only ones in Survival):
-- the stock x40a and the land battleship keep theirs. Returns how many changed, and a note.
SPC.V.EML_MODULES = { "LiveFCSModule_ProjectileCommon", "LiveFCSModule_ProjectileMulti", "LiveFCSModule_ProjectileWeapon" }
function SPC.V.emlWeapon(c)
    if not c.eml_weapon or c.eml_weapon == "" then return 0, "off" end
    local nm = c.eml_weapon:match("[^/]+$")
    local cls, why = loadObject(c.eml_weapon .. "." .. nm .. "_C")
    if not valid(cls) then return 0, nm .. " not loaded (" .. tostring(why) .. ")" end
    local cdo = StaticFindObject(c.eml_weapon .. ".Default__" .. nm .. "_C")
    local outers, nL = {}, 0
    local okL, list = pcall(FindAllOf, "LiveFCSModule_LauncherTripleRailCannon")
    for _, m in ipairs(okL and list or {}) do
        local okO, out = pcall(function() return m:GetOuter() end)
        if okO and valid(out) then outers[addrOf(out)] = true; nL = nL + 1 end
    end
    local n, nP, was, seen = 0, 0, {}, {}
    for _, cn in ipairs(SPC.V.EML_MODULES) do
        local okP, ps = pcall(FindAllOf, cn)
        for _, p in ipairs(okP and ps or {}) do
            local a = addrOf(p)
            local okO, out = pcall(function() return p:GetOuter() end)
            if a and not seen[a] and okO and valid(out) and outers[addrOf(out)] then
                seen[a], nP = true, nP + 1
                local okW, w = pcall(function() return p.WeaponClass:GetFName():ToString() end)
                if okW and w == nm .. "_C" then n = n + 1
                elseif pcall(function() p.WeaponClass = cls; if valid(cdo) then p.WeaponCDO = cdo end end) then
                    n = n + 1
                    was[#was + 1] = okW and w or "?"
                end
            end
        end
    end
    local okT, life = pcall(function() return cdo.LifeTime end)
    return n, string.format("%d launchers, %d projectile modules beside them; was %s; %s life %s s", nL, nP,
        #was > 0 and table.concat(was, ", ") or "-", nm, okT and tostring(life) or "?")
end
-- her railgun's rounds now in the level (c.eml_weapon's): one at a time (ROUND_ONE: no burst, no donut spread; the
-- land battleship's fires a ring of them), each lives at least eml_life_s (its class default's or
-- longer), and does no damage while `harmless` (the opener's shot) or its class default's otherwise. Instances only:
-- the rounds are pooled, so this runs around every shot. Returns how many, and their life.
SPC.V.ROUND_ONE = { { "bBurstShot", false }, { "BurstShotCount", 1 }, { "bFireAllInOneShot", false },
                    { "bDonutsShot", false }, { "bMultipleLockOn", false } }
function SPC.V.rounds(c, harmless)
    if not c.eml_weapon or c.eml_weapon == "" then return 0 end
    local nm = c.eml_weapon:match("[^/]+$")
    local cdo = StaticFindObject(c.eml_weapon .. ".Default__" .. nm .. "_C")
    local okD, d0 = pcall(function() return cdo.damage end)
    local okL, l0 = pcall(function() return cdo.LifeTime end)
    local life = math.max(c.eml_life_s or 0, (okL and type(l0) == "number") and l0 or 0)
    if not SPC.V.roundSaid and valid(cdo) then         -- (test of 2026-10-24, 0.67.1: "it fires multiple bursts at you")
        SPC.V.roundSaid = true
        local said = {}
        for _, f in ipairs(SPC.V.ROUND_ONE) do
            local okF, v = pcall(function() return cdo[f[1]] end)
            said[#said + 1] = f[1] .. " " .. (okF and tostring(v) or "?")
        end
        log("special: VALKA's round " .. nm .. " (class default): " .. table.concat(said, ", "))
    end
    local n = 0
    local ok, list = pcall(FindAllOf, nm .. "_C")
    for _, r in ipairs(ok and list or {}) do
        if valid(r) and not nameOf(r):find("Default__", 1, true) then
            n = n + 1
            for _, f in ipairs(SPC.V.ROUND_ONE) do pcall(function() r[f[1]] = f[2] end) end
            pcall(function() if (r.LifeTime or 0) < life then r.LifeTime = life end end)
            pcall(function() if (r.EffectiveTime or 0) > 0 and r.EffectiveTime < life then r.EffectiveTime = life end end)
            pcall(function() r.damage = harmless and 0 or (okD and d0 or r.damage) end)
        end
    end
    return n, life
end
-- her railguns on the minimap: each x40a railgun launcher's radar display on, forced, in radar_hud's style
function SPC.V.radar(c)
    local n = 0
    local ok, list = pcall(FindAllOf, "LiveFCSModule_LauncherTripleRailCannon")
    for _, m in ipairs(ok and list or {}) do
        if pcall(function()
            m.IsDispRadarMap = true
            m.ForceAlertDisp = true
            m.HUDControl = c.radar_hud or 1
        end) then n = n + 1 end
    end
    return n
end
-- The opener's light as AC7 Mission 18's lens flash (ms18_LensEffect1: screen-space billboard elements, faded by its
-- alpha curve): a plain actor spawned at `at` with a MaterialBillboardComponent, one element per AC7 texture
-- (MI_SV_ValkaFlare_*, on AC8's own Mission 23 flare). How many elements came up.
-- a plain actor spawned at `at` with a MaterialBillboardComponent (her flare's and portal's); actor, component, or nil
-- and why not
function SPC.V.billboard(at)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local actorCls, bbCls = StaticFindObject("/Script/Engine.Actor"), StaticFindObject("/Script/Engine.MaterialBillboardComponent")
    if not (valid(gs) and valid(actorCls) and valid(bbCls)) then return nil, nil, "engine classes not found" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okA, a = pcall(function()
        local x = gs:BeginDeferredActorSpawnFromClass(survivalPC, actorCls, t, 1, nil, 1)    -- (AlwaysSpawn, MultiplyWithRoot)
        return gs:FinishSpawningActor(x, t, 1)
    end)
    if not okA or not valid(a) then return nil, nil, "no actor (" .. tostring(a) .. ")" end
    local okC, comp = pcall(function()
        return a:AddComponentByClass(bbCls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
                                     Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    end)
    if not okC or not valid(comp) then
        pcall(function() a:K2_DestroyActor() end)
        return nil, nil, "no billboard (" .. tostring(comp) .. ")"
    end
    pcall(function() a:K2_SetActorLocation({ X = at.X, Y = at.Y, Z = at.Z }, false, {}, true) end)
    return a, comp
end
function SPC.V.flareStart(c, s, at, now)
    local f = c.flare
    SPC.V.flareStop(s)
    if not f or not f.enabled or not at then return 0 end
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    if not valid(kml) then return 0 end
    local a, comp, whyB = SPC.V.billboard(at)
    if not a then log("special: VALKA's flare: " .. tostring(whyB)); return 0 end
    local fl = { actor = a, comp = comp, mids = {}, from = now, life = f.life_s }
    local said = {}
    for _, e in ipairs(f.elements) do
        local p = f.path .. e[1]
        local mi, why = loadObject(p .. "." .. p:match("[^/]+$"))
        local okM, mid = valid(mi) and pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, mi, FName("None"), 0) end)
        if okM and valid(mid) and pcall(function() comp:AddElement(mid, nil, true, e[2], e[2], nil) end) then
            local okB, b = pcall(function() return mid:K2_GetScalarParameterValue(FName("Emissive_Intensity")) end)
            fl.mids[#fl.mids + 1] = { mid = mid, base = (okB and type(b) == "number" and b > 0) and b or 1 }
            said[#said + 1] = string.format("%s %.1f (base %.3g)", e[1], e[2], fl.mids[#fl.mids].base)
        else
            said[#said + 1] = e[1] .. " NOT up (" .. tostring(valid(mi) and mid or why) .. ")"
        end
    end
    s.flare = fl
    SPC.V.flareTick(c, s, now)
    log(string.format("special: VALKA's flare (AC7 M18 lens flash): %d of %d elements, %.0f s: %s", #fl.mids, #f.elements,
        f.life_s, table.concat(said, ", ")))
    if #fl.mids == 0 then SPC.V.flareStop(s) end
    return #fl.mids
end
-- every tick: its brightness along AC7's alpha curve; gone at the end of its life
function SPC.V.flareTick(c, s, now)
    local fl = s.flare
    if not fl then return end
    local k = (now - fl.from) / math.max(0.1, fl.life)
    if k >= 1 or not valid(fl.actor) then SPC.V.flareStop(s); return end
    local cv, alpha = c.flare.curve, 0
    for i = 1, #cv - 1 do
        local p, q = cv[i], cv[i + 1]
        if k >= p[1] and k <= q[1] then alpha = p[2] + (q[2] - p[2]) * (k - p[1]) / math.max(1e-6, q[1] - p[1]) end
    end
    for _, m in ipairs(fl.mids) do
        pcall(function() m.mid:SetScalarParameterValue(FName("Emissive_Intensity"), m.base * c.flare.intensity_x * alpha) end)
    end
end
function SPC.V.flareStop(s)
    if s.flare then
        local a = s.flare.actor
        if valid(a) then pcall(function() a:K2_DestroyActor() end) end
        s.flare = nil
    end
end
-- Her portal (user, 2026-10-24: "an event horizon black hole that Valka will spawn out of"; CFG.specials.valka.portal):
-- one billboard of world-space elements on AC8's own effect materials, our textures on them (tools/x02s prepare.py
-- portal_textures): the barrier's refraction (the lensing), the accretion glow and the photon ring on the additive
-- flare, the event horizon on M_Smoke01 made black. It opens over open_s, holds, collapses over close_s.
SPC.V.PORTAL_MAT = {
    lens = "/Game/VFX/Vehicles/Weapon/UAV/Barrier/M_VFX_UAVBarrierSpriteRefraction",
    disc = "/Game/VFX/Vehicles/Weapon/Impact/Materials/M_Smoke01",
    flare = "/Game/VFX/Mission/Mission023/MI_ms23FarExp_Flare",
}
local function portalMid(kml, kind)
    local p = SPC.V.PORTAL_MAT[kind]
    local m, why = loadObject(p .. "." .. p:match("[^/]+$"))
    if not valid(m) then return nil, why end
    local ok, mid = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, m, FName("None"), 0) end)
    if ok and valid(mid) then return mid end
    return nil, tostring(mid)
end
local function portalTex(p, name)
    return loadObject(p.textures .. name .. "." .. name)
end
function SPC.V.portalStart(c, s, at, now)
    local p = c.portal
    SPC.V.portalStop(s)
    if not p or not p.enabled or not at then return 0 end
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    if not valid(kml) then return 0 end
    local a, comp, whyB = SPC.V.billboard(at)
    if not a then log("special: VALKA's portal: " .. tostring(whyB)); return 0 end
    local d = p.diameter_m * 100
    local po = { actor = a, comp = comp, from = now, glow = {}, said = {}, up = 0 }
    local function add(name, mid, size)
        if mid and pcall(function() comp:AddElement(mid, nil, false, size, size, nil) end) then
            po.said[#po.said + 1] = name
            po.up = po.up + 1
            return true
        end
        po.said[#po.said + 1] = name .. " NOT up"
    end
    local lens = portalMid(kml, "lens")                -- the lensing: the barrier's refraction, stronger
    if lens then
        pcall(function()
            local b = lens:K2_GetScalarParameterValue(FName("RefractionIntensity"))
            lens:SetScalarParameterValue(FName("RefractionIntensity"), ((type(b) == "number" and b ~= 0) and b or 1) * p.lens_x)
        end)
        add("lens", lens, d * p.lens_size)
    end
    for _, e in ipairs({ { "glow", "T_SV_Portal_Glow", p.glow_size, p.glow_x }, { "ring", "T_SV_Portal_Ring", p.ring_size, p.ring_x } }) do
        local mid, tex = portalMid(kml, "flare"), portalTex(p, e[2])
        if mid and valid(tex) then
            local base = 1
            pcall(function()
                mid:SetTextureParameterValue(FName("EmissiveMap"), tex)
                mid:SetTextureParameterValue(FName("MaskMap"), tex)
                local b = mid:K2_GetScalarParameterValue(FName("Emissive_Intensity"))
                if type(b) == "number" and b > 0 then base = b end
            end)
            if add(e[1], mid, d * e[3]) then po.glow[#po.glow + 1] = { mid = mid, base = base * e[4] } end
        else
            po.said[#po.said + 1] = e[1] .. " NOT up (" .. (mid and ("no texture " .. e[2]) or "no material") .. ")"
        end
    end
    local disc, tex = portalMid(kml, "disc"), portalTex(p, "T_SV_Portal_Disc")   -- the event horizon: black
    if disc and valid(tex) then
        pcall(function()
            disc:SetTextureParameterValue(FName("BaseTexture"), tex)
            disc:SetVectorParameterValue(FName("LerpColor1"), { R = 0, G = 0, B = 0, A = 1 })
            disc:SetVectorParameterValue(FName("LerpColor2"), { R = 0, G = 0, B = 0, A = 1 })
            disc:SetScalarParameterValue(FName("BrightnessIntensity"), 0)
        end)
        add("horizon", disc, d)
    else
        po.said[#po.said + 1] = "horizon NOT up"
    end
    s.portal = po
    SPC.V.portalTick(c, s, now)
    log(string.format("special: VALKA's portal at %.0f, %.0f, %.0f (%.0f m): %s", at.X / 100, at.Y / 100, at.Z / 100,
        p.diameter_m, table.concat(po.said, ", ")))
    if po.up == 0 then SPC.V.portalStop(s) end
    return po.up
end
-- every tick: open, hold, close (its size and glow); gone after
function SPC.V.portalTick(c, s, now)
    local po, p = s.portal, c.portal
    if not po then return end
    local t = now - po.from
    local k
    if t < p.open_s then k = t / p.open_s
    elseif t < p.open_s + p.hold_s then k = 1
    elseif t < p.open_s + p.hold_s + p.close_s then k = 1 - (t - p.open_s - p.hold_s) / p.close_s
    else SPC.V.portalStop(s); return end
    k = math.max(0.02, k * k * (3 - 2 * k))             -- (eased)
    if not valid(po.actor) then SPC.V.portalStop(s); return end
    pcall(function() po.comp:SetWorldScale3D({ X = k, Y = k, Z = k }) end)
    local pulse = 1 + 0.25 * math.sin(t * 9)
    for _, g in ipairs(po.glow) do
        pcall(function() g.mid:SetScalarParameterValue(FName("Emissive_Intensity"), g.base * k * pulse) end)
    end
end
function SPC.V.portalStop(s)
    if s.portal then
        local a = s.portal.actor
        if valid(a) then pcall(function() a:K2_DestroyActor() end) end
        s.portal = nil
    end
end
-- her railgun's sounds (CFG.sound.valka, sv_sound.lua): the charge at `at` (a location, or a function giving hers),
-- its loop rising over `len` s, the shot (the round passing you pass_speed_ms later), and the loop stopped
function SPC.V.sndCharge(s, at, now)
    local cs = CFG.sound.valka
    SPC.V.sndStop(s)
    SND.event(cs.charge, at)
    s.sndLoop, s.sndFrom = SND.play(cs.charge_loop, at), now
end
function SPC.V.sndRise(s, now, len)
    if not s.sndLoop then return end
    local cs = CFG.sound.valka
    local p = math.max(0, math.min(1, (now - (s.sndFrom or now)) / math.max(0.1, len)))
    SND.set(s.sndLoop, cs.rise_db * p, 2 ^ (cs.rise_cents * p / 1200))
end
function SPC.V.sndStop(s)
    if s.sndLoop then SND.stop(s.sndLoop); s.sndLoop = nil end
end
function SPC.V.sndShot(s, at, now)
    local cs = CFG.sound.valka
    SPC.V.sndStop(s)
    SND.event(cs.charge_end, at)
    SND.event(cs.shot, at)
    local me = playerLocation()
    if at and me then
        local d = math.sqrt((at.X - me.X) ^ 2 + (at.Y - me.Y) ^ 2 + (at.Z - me.Z) ^ 2) / 100
        s.passAt = now + d / math.max(100, cs.pass_speed_ms)
    end
end
-- the hidden opener railgun keeps a target box while it charges (opener_marker; user, 2026-10-25: "couldnt see the
-- opener as i cant find it"): seen where to look, still not lockable
function SPC.V.mark(c, e)
    if c.opener_marker and valid(e) then pcall(function() e.bShowHUDBox = true end) end
end
function SPC.V.event(ev)
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    if r ~= 1 then log("special: VALKA " .. ev .. " not fired: " .. (SV_ERR[r] or tostring(r))) end
    return r
end
-- the shown actors attached to her (the x40a's railguns and laser pod: setGone on her airframe leaves them up; test of
-- 2026-10-24: they hung in front of the player through the opener), from her component tree's AttachChildren
function SPC.V.parts(o)
    local out, seen, queue, i = {}, {}, {}, 1
    local me = addrOf(o)
    pcall(function() queue[1] = o.RootComponent end)
    while queue[i] and i <= 400 do
        local comp = queue[i]
        i = i + 1
        pcall(function()
            local owner = comp:GetOwner()
            local a = valid(owner) and addrOf(owner)
            if a and a ~= me and not seen[a] then
                seen[a] = true
                if not owner.bHidden then out[#out + 1] = owner end
            end
            comp.AttachChildren:ForEach(function(_, e) queue[#queue + 1] = e:get() end)
        end)
    end
    return out
end
-- her parts gone with her (found until some are) or back as they were (their own box / lock / target flags)
SPC.V.PART_FLAGS = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }
-- her parts (the x40a's railguns and laser pod, hidden with the X-02S on) moved onto her: railgun_at (cm, her frame),
-- so her shots leave from her and not from where the x40a's turret sat (test of 2026-10-24, 0.67.1: "the railgun
-- didn't sit on her aircraft"); how many moved
function SPC.V.partsPlace(c, s, o)
    local at, n = c.railgun_at or { X = 400, Y = 0, Z = -80 }, 0
    for _, p in ipairs(s.parts or {}) do              -- (in the world: attached ones keep that as their new offset,
        if valid(p) and pcall(function()             -- whatever x40a socket they hang on)
            local base = o:K2_GetActorLocation()
            local f, rt, up = o:GetActorForwardVector(), o:GetActorRightVector(), o:GetActorUpVector()
            p:K2_SetActorLocation({ X = base.X + f.X * at.X + rt.X * at.Y + up.X * at.Z,
                                    Y = base.Y + f.Y * at.X + rt.Y * at.Y + up.Y * at.Z,
                                    Z = base.Z + f.Z * at.X + rt.Z * at.Y + up.Z * at.Z }, false, {}, true)
        end) then n = n + 1 end
    end
    return n
end
-- the part shown as her railgun on the X-02S (user, 2026-10-24: "her railgun mesh also isn't visible"): the x40a's
-- RailGun (railgun_show: a pattern in its actor's name), not its spares or laser pod
function SPC.V.railgunShown(c, p)
    if not c.railgun_show or c.railgun_show == "" then return false end
    local n = nameOf(p):match("([%w_]+)$") or ""
    return n:find(c.railgun_show) ~= nil
end
function SPC.V.partsGone(c, s, o, gone, blink)        -- (blink: gone in a blink, her railgun too)
    if not gone and s.modelComp then gone = true end    -- (her X-02S on: the x40a's parts stay gone, but her railgun)
    if gone and #(s.parts or {}) == 0 then
        s.parts, s.partWas = SPC.V.parts(o), {}
        for k, p in ipairs(s.parts) do
            local was = {}
            for f in pairs(SPC.V.PART_FLAGS) do pcall(function() was[f] = p[f] end) end
            s.partWas[k] = was
        end
        if #s.parts > 0 then
            local names = {}
            for _, p in ipairs(s.parts) do names[#names + 1] = nameOf(p):match("([%w_]+)$") or "?" end
            log(string.format("special: %s's parts hidden with her: %d (%s)", c.name, #s.parts, table.concat(names, ", ")))
        end
    end
    for k, p in ipairs(s.parts or {}) do
        local shown = gone and not blink and s.modelComp and SPC.V.railgunShown(c, p)   -- (her railgun on the X-02S)
        if shown and not s.railShownSaid then
            s.railShownSaid = true
            pcall(function() local k2 = c.railgun_scale or 1; p:SetActorScale3D({ X = k2, Y = k2, Z = k2 }) end)
            log(string.format("special: %s's railgun shown on her: %s (x%.2f)", c.name, nameOf(p):match("([%w_]+)$") or "?", c.railgun_scale or 1))
        end
        if valid(p) then
            pcall(function() p:SetActorHiddenInGame(gone and not shown) end)
            pcall(function() p:SetActorEnableCollision(not gone) end)
            for f, v in pairs(SPC.V.PART_FLAGS) do
                local to = v
                if not gone then to = s.partWas[k][f] end
                if to ~= nil then pcall(function() p[f] = to end) end
            end
        end
    end
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

-- her components of class `cls` (a /Script path), from her component tree (RootComponent and AttachChildren down, as
-- SPC.V.parts walks it; test of 2026-10-24: K2_GetComponentsByClass's array gave nothing from Lua), hers only
function SPC.V.comps(o, cls)
    local out, queue, i, me = {}, {}, 1, addrOf(o)
    local class = StaticFindObject(cls)
    pcall(function() queue[1] = o.RootComponent end)
    while queue[i] and i <= 400 do
        local comp = queue[i]
        i = i + 1
        pcall(function()
            local owner = comp:GetOwner()
            if valid(owner) and addrOf(owner) == me then
                if comp:IsA(class) then out[#out + 1] = comp end
                comp.AttachChildren:ForEach(function(_, e) queue[#queue + 1] = e:get() end)
            end
        end)
    end
    return out
end

-- Her X-02S (AC7's, user, 2026-10-24: "full port as the X-02S is swing winged"; tools/x02s, cooked in UE 5.4 into
-- its own container SurvivalMode_Valka_P): her airframe's body mesh component gets SK_X02S_Valka (AC7's skeleton, its
-- sockets, so what hangs on burner_01 / _02, her afterburners, moves to the X-02S's nozzles) and plays
-- A_X02S_Valka_Sweep, the swing wings alone (AC7's x02s_Anim frames 50-100): unswept below sweep_kmh[1], swept above
-- sweep_kmh[2] (AC7's VwgMin / VwgMax), a full travel taking sweep_s. Her other meshes are hidden (again every 2 s)
-- and her parts gone (not lockable); her flight model and railguns stay the x40a's. Off (the x40a as it is) when
-- `model` is "" or doesn't load. True if on.
SPC.V.BODY_PROPS = { "PlaneBodySkelMeshComponent", "PlaneBodyMeshComponent", "PlaneBodyStaticMeshComponent", "PlaneBodyMesh" }
-- Her paint (test of 2026-10-24, 0.66.2: "her paint was all blackened out"). MI_X02S_Valka sets only Basecolor /
-- Normalmap / Livemap on AC8's MP_PP0032_f18e_Decal, the rest stays at the parent's defaults, which every stock skin
-- overrides (weathering, wet, dirt, smoke, paint regions...), and its Livemap (AC8's _MRX: metallic / roughness / ?)
-- is all black. At her reveal her MI_X02S_Valka slots get dynamic instances; a variant (CFG.specials.valka.paint, or
-- cycled by the test key Ctrl+9) sets on them:
--   1 raw     as built (what 0.66.2 showed)
--   2 stock   the stock F/A-18E skin's scalar / vector values (MI_PP0032_f18e_001_Decal) and no dirt mask (black)
--   3 stock + white Livemap   4 stock + the parent's own dirt mask   5 stock + white Livemap and the parent's dirt
-- and, as 2 stayed black (test of 2026-10-24, 0.67.1: "she was still coated black", "her mesh was missing pieces"),
-- three that tell where it goes wrong:
--   6 stock + the F/A-18E's own Livemap (if it's ours that's wrong)   7 the F/A-18E's three textures (wrongly mapped,
--   but lit if the material works on her)   8 the engine's grid material on every slot (the mesh and its lighting alone)
SPC.V.PAINT_STOCK = "/Game/Vehicles/Aircraft/PP/PP0032_f18e/Materials/001/MI_PP0032_f18e_001_Decal"
SPC.V.PAINT_TEX = { black = "/Engine/EngineResources/Black", white = "/Engine/EngineResources/WhiteSquareTexture",
    f18_c = "/Game/Vehicles/Aircraft/PP/PP0032_f18e/Textures/001/T_PP0032_f18e_001_C", f18_mrx = "/Game/Vehicles/Aircraft/PP/PP0032_f18e/Textures/001/T_PP0032_f18e_001_MRX", f18_no = "/Game/Vehicles/Aircraft/PP/PP0032_f18e/Textures/001/T_PP0032_f18e_001_NO" }
SPC.V.PAINTS = {
    { name = "RAW" },
    { name = "STOCK", stock = true, dirt = "black" },
    { name = "STOCK + WHITE LIVEMAP", stock = true, dirt = "black", livemap = "white" },
    { name = "STOCK + PARENT DIRT", stock = true },
    { name = "STOCK + WHITE LIVEMAP + PARENT DIRT", stock = true, livemap = "white" },
    { name = "STOCK + F-18 LIVEMAP", stock = true, dirt = "black", livemap = "f18_mrx" },
    { name = "F-18 TEXTURES", stock = true, dirt = "black", livemap = "f18_mrx", basecolor = "f18_c", normal = "f18_no" },
    { name = "ENGINE GRID", material = "/Engine/EngineMaterials/WorldGridMaterial" },
    -- AC8's aircraft master (MP_Live_Vehicle_Base_UDIM, 1-7) samples virtual textures only (tools/re/AIRCRAFT_MATERIALS.md):
    -- with ordinary ones it draws black. These are AC8's general masters with ordinary samplers and skinned-mesh shaders
    -- and the same slot names: a dynamic instance of one, her colour and normal maps in it, its own Livemap default
    -- (T_Livemap: non-metal, rough, no occlusion) unless `livemap` says otherwise
    { name = "LIVE BASE", parent = "/Game/Base/Material/MP/MP_Live_Base_CameraDitherFade" },
    { name = "LIVE BASE WPO", parent = "/Game/Base/Material/MP/MP_Live_Base_WPO" },
    { name = "CHARACTER BASE", parent = "/Game/Base/Material/Character/M_Live_Cha_Base" },
}
-- her own textures, for the `parent` variants
SPC.V.PAINT_OWN = { Basecolor = "/Game/Mods/SurvivalMode/Valka/Textures/T_X02S_Valka_C",
                    Normalmap = "/Game/Mods/SurvivalMode/Valka/Textures/T_X02S_Valka_NO" }
-- the parent values logged once (what a stock skin changes, for the real fix)
SPC.V.PAINT_SAY = { "WeatheringWeight", "Wet_Darkness", "Wet_Range", "AO_amoumt", "MetallicMapWeight",
    "Metallic_Remap_Target_Low", "Metallic_Remap_Target_High", "Roughness_Remap", "Roughness_Contrast", "Ctrl_B_Smoke",
    "Ctrl_G_OilDirt", "Ctrl_R_ColorUnevenness", "B_Color_Weight", "G_Color_Weight", "R_ColorFade_Weight", "NormalIntencity" }
local function paintTex(k)
    local p = SPC.V.PAINT_TEX[k]
    return p and loadObject(p .. "." .. p:match("[^/]+$"))
end
-- name -> value of a material instance's own scalar / vector overrides
local function paintValues(mi)
    local sc, ve = {}, {}
    pcall(function()
        mi.ScalarParameterValues:ForEach(function(_, e)
            local v = e:get()
            sc[v.ParameterInfo.Name:ToString()] = v.ParameterValue
        end)
    end)
    pcall(function()
        mi.VectorParameterValues:ForEach(function(_, e)
            local v = e:get()
            local q = v.ParameterValue
            ve[v.ParameterInfo.Name:ToString()] = { R = q.R, G = q.G, B = q.B, A = q.A }
        end)
    end)
    return sc, ve
end
-- variant k on her body (fresh dynamic instances each time, so one variant never carries into the next); its name
function SPC.V.paint(c, s, body, k)
    local V = SPC.V
    k = ((k - 1) % #V.PAINTS) + 1
    local pv = V.PAINTS[k]
    s.paintK = k
    if not s.paintSlots then                            -- her MI_X02S_Valka slots and that material
        s.paintSlots = {}
        pcall(function()
            for i = 0, body:GetNumMaterials() - 1 do
                local m = body:GetMaterial(i)
                if valid(m) and nameOf(m):find("MI_X02S_Valka", 1, true) then
                    s.paintSlots[#s.paintSlots + 1] = i
                    s.paintMI = s.paintMI or m
                end
            end
        end)
    end
    if not s.paintMI then
        log(string.format("special: %s's paint: no MI_X02S_Valka slot on %s", c.name, nameOf(body)))
        return pv.name
    end
    if not s.paintOrig then                             -- every slot's own material (the canopy's too), to go back to
        s.paintOrig, s.paintN = {}, 0
        pcall(function()
            s.paintN = body:GetNumMaterials()
            for i = 0, s.paintN - 1 do s.paintOrig[i] = body:GetMaterial(i) end
        end)
    end
    for i = 0, (s.paintN or 0) - 1 do                   -- (the grid variant changes every slot)
        if valid(s.paintOrig[i]) then pcall(function() body:SetMaterial(i, s.paintOrig[i]) end) end
    end
    if pv.parent then                                   -- another AC8 master, her textures on it
        local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local parent, why = loadObject(pv.parent .. "." .. pv.parent:match("[^/]+$"))
        local okM, mid = valid(parent) and valid(kml) and pcall(function()
            return kml:CreateDynamicMaterialInstance(survivalPC, parent, FName("None"), 0)
        end)
        if not (okM and valid(mid)) then
            log(string.format("special: %s's paint %d %s: no instance of %s (%s)", c.name, k, pv.name, pv.parent,
                tostring(valid(parent) and mid or why)))
            return pv.name
        end
        local set = {}
        for slot, path in pairs(V.PAINT_OWN) do
            local t = loadObject(path .. "." .. path:match("[^/]+$"))
            local ok = valid(t) and pcall(function() mid:SetTextureParameterValue(FName(slot), t) end)
            set[#set + 1] = slot .. (ok and "" or " NOT set")
        end
        local live = pv.livemap and paintTex(pv.livemap)
        if live then pcall(function() mid:SetTextureParameterValue(FName("Livemap"), live) end) end
        local n = 0
        for _, i in ipairs(s.paintSlots) do
            if pcall(function() body:SetMaterial(i, mid) end) then n = n + 1 end
        end
        log(string.format("special: %s's paint %d %s: %d slots on %s, %s%s", c.name, k, pv.name, n, pv.parent:match("[^/]+$"),
            table.concat(set, ", "), pv.livemap and (", Livemap " .. pv.livemap .. (live and "" or " NOT loaded")) or ", its own Livemap"))
        return pv.name
    end
    if pv.material then
        local m, why = loadObject(pv.material .. "." .. pv.material:match("[^/]+$"))
        local n = 0
        for i = 0, (s.paintN or 0) - 1 do
            if valid(m) and pcall(function() body:SetMaterial(i, m) end) then n = n + 1 end
        end
        log(string.format("special: %s's paint %d %s: %d of %d slots%s", c.name, k, pv.name, n, s.paintN or 0,
            valid(m) and "" or (" (" .. pv.material .. " not loaded: " .. tostring(why) .. ")")))
        return pv.name
    end
    local sc, ve, nStock = {}, {}, 0
    if pv.stock then
        local stock, why = loadObject(V.PAINT_STOCK .. "." .. V.PAINT_STOCK:match("[^/]+$"))
        if valid(stock) then sc, ve = paintValues(stock) else
            log(string.format("special: %s's paint: %s not loaded (%s)", c.name, V.PAINT_STOCK, tostring(why)))
        end
    end
    local dirt, live = pv.dirt and paintTex(pv.dirt), pv.livemap and paintTex(pv.livemap)
    local base, nrm = pv.basecolor and paintTex(pv.basecolor), pv.normal and paintTex(pv.normal)
    local said, made = {}, 0
    for _, i in ipairs(s.paintSlots) do
        local okM, mid = pcall(function() return body:CreateDynamicMaterialInstance(i, s.paintMI, FName("None")) end)
        if okM and valid(mid) then
            made = made + 1
            if not s.paintSaid then                      -- the parent's values, once
                s.paintSaid = true
                for _, n in ipairs(V.PAINT_SAY) do
                    local okV, v = pcall(function() return mid:K2_GetScalarParameterValue(FName(n)) end)
                    said[#said + 1] = string.format("%s %s", n, okV and string.format("%.3g", v) or "?")
                end
            end
            nStock = 0
            for n, v in pairs(sc) do
                if pcall(function() mid:SetScalarParameterValue(FName(n), v) end) then nStock = nStock + 1 end
            end
            for n, v in pairs(ve) do
                if pcall(function() mid:SetVectorParameterValue(FName(n), v) end) then nStock = nStock + 1 end
            end
            if dirt then pcall(function() mid:SetTextureParameterValue(FName("DirtMask"), dirt) end) end
            if live then pcall(function() mid:SetTextureParameterValue(FName("Livemap"), live) end) end
            if base then pcall(function() mid:SetTextureParameterValue(FName("Basecolor"), base) end) end
            if nrm then pcall(function() mid:SetTextureParameterValue(FName("Normalmap"), nrm) end) end
        end
    end
    if made == 0 then                                   -- (no instances: the slots back as built)
        for _, i in ipairs(s.paintSlots) do pcall(function() body:SetMaterial(i, s.paintMI) end) end
    end
    if #said > 0 then log(string.format("special: %s's paint: the parent's values: %s", c.name, table.concat(said, ", "))) end
    log(string.format("special: %s's paint %d %s: %d slots, %d stock values%s%s", c.name, k, pv.name, made, nStock,
        pv.dirt and (", dirt mask " .. pv.dirt .. (dirt and "" or " NOT loaded")) or "",
        pv.livemap and (", Livemap " .. pv.livemap .. (live and "" or " NOT loaded")) or "") ..
        (pv.basecolor and (", Basecolor " .. pv.basecolor .. (base and "" or " NOT loaded")) or "") ..
        (pv.normal and (", Normalmap " .. pv.normal .. (nrm and "" or " NOT loaded")) or ""))
    return pv.name
end
-- no skeletal body of her own (the x40a's isn't one: test of 2026-10-24, 0.66.0, only the wreck meshes were skeletal
-- and 3 other meshes got hidden): a skeletal mesh component of ours added to her (AActor::AddComponentByClass, on her
-- root), no collision (her own spheres still take the hits), placed where her body mesh is (any PlaneBody* one) and
-- turned model_yaw more. Returns it and how it was placed, or nil and why not.
function SPC.V.addBody(c, o)
    local cls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    if not valid(cls) then return nil, "no SkeletalMeshComponent class" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, comp = pcall(function() return o:AddComponentByClass(cls, false, t, false) end)
    if not ok or not comp or not valid(comp) then
        return nil, "AddComponentByClass " .. (ok and "gave nothing" or tostring(comp))
    end
    pcall(function() comp:SetCollisionEnabled(0) end)      -- (ECollisionEnabled NoCollision)
    local yaw = c.model_yaw or 0
    local ref, by = nil, "her root"
    for _, n in ipairs(SPC.V.BODY_PROPS) do
        local okP, p = pcall(function() return o[n] end)
        if okP and p and valid(p) and addrOf(p) ~= addrOf(comp) then ref, by = p, n; break end
    end
    local placed
    if ref then
        placed = pcall(function()
            local l, r = ref:K2_GetComponentLocation(), ref:K2_GetComponentRotation()
            comp:K2_SetWorldLocationAndRotation({ X = l.X, Y = l.Y, Z = l.Z },
                { Pitch = r.Pitch, Yaw = r.Yaw + yaw, Roll = r.Roll }, false, {}, true)
        end)
    else
        placed = pcall(function()
            comp:K2_SetRelativeLocationAndRotation({ X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = yaw, Roll = 0 }, false, {}, true)
        end)
    end
    return comp, string.format("placed by %s%s, yaw +%d", by, placed and "" or " (NOT placed)", yaw)
end
function SPC.V.model(c, s, o)
    if not c.model or c.model == "" or s.modelComp then return s.modelComp ~= nil end
    local function load(path) return loadObject(path .. "." .. path:match("[^/]+$")) end
    local sk, why = load(c.model)
    local anim, whyAnim = nil, "no sweep_anim"
    if c.sweep_anim and c.sweep_anim ~= "" then anim, whyAnim = load(c.sweep_anim) end
    if not valid(sk) then
        log(string.format("special: %s's X-02S %s not loaded (%s); the x40a shows", c.name, c.model, tostring(why)))
        return false
    end
    -- her body: the plane's own body mesh (its PlaneBody* property, as glitchDeadLook finds it), else the biggest
    -- skeletal mesh in her tree that isn't a wreck mesh (test of 2026-10-24, 0.66.0: the tree held only
    -- DamagedMainBodyMesh / DamagedPartsMesh, the X-02S went on the wreck one, which never draws: hard rule 41)
    local body, best, names = nil, -1, {}
    local skel = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    for _, n in ipairs(SPC.V.BODY_PROPS) do
        local ok, comp = pcall(function() return o[n] end)
        if ok and comp and valid(comp) then
            local okC, cls = pcall(function() return comp:GetClass():GetFName():ToString() end)
            local isSkel = pcall(function() assert(comp:IsA(skel)) end)
            names[#names + 1] = string.format("%s=%s%s", n, okC and cls or "?", isSkel and "" or " (not skeletal)")
            if isSkel and not body then body, best = comp, 1e12 end
        end
    end
    for _, comp in ipairs(SPC.V.comps(o, "/Script/Engine.SkeletalMeshComponent")) do
        local nm = nameOf(comp):match("([%w_]+)$") or "?"
        names[#names + 1] = nm
        local okB, r = pcall(function() return comp.Bounds.SphereRadius end)
        local size = (okB and type(r) == "number" and r) or 0
        if not nm:find("^Damaged") and size > best then body, best = comp, size end
    end
    local added, whyAdd = false, nil
    if not valid(body) then
        body, whyAdd = SPC.V.addBody(c, o)
        added = valid(body)
    end
    if not valid(body) then
        local all = {}
        for _, comp in ipairs(SPC.V.comps(o, "/Script/Engine.ActorComponent")) do
            all[#all + 1] = (nameOf(comp):match("([%w_]+)$") or "?") .. ":" .. (pcall(function() return comp:GetClass():GetFName():ToString() end) and comp:GetClass():GetFName():ToString() or "?")
        end
        log(string.format("special: %s has no skeletal mesh component and none could be added (%s); her tree: %s; the x40a shows",
            c.name, tostring(whyAdd), #all > 0 and table.concat(all, ", ") or "nothing (no RootComponent?)"))
        return false
    end
    local okM = pcall(function() body:SetSkeletalMeshAsset(sk) end) or pcall(function() body:SetSkeletalMesh(sk, true) end)
    if not okM then
        log(string.format("special: %s's X-02S mesh not set on %s; the x40a shows", c.name, nameOf(body)))
        return false
    end
    SPC.V.cur = s
    SPC.V.paint(c, s, body, c.paint or 2)
    local k = (c.model_length_m or 19.6) / 19.6
    if k ~= 1 then pcall(function() local v = body.RelativeScale3D; body:SetRelativeScale3D({ X = v.X * k, Y = v.Y * k, Z = v.Z * k }) end) end
    local okA, errA = false, "not loaded: " .. tostring(whyAnim)
    if valid(anim) then
        okA, errA = pcall(function()
            body:SetAnimationMode(1, true)                                  -- (EAnimationMode AnimationSingleNode)
            body:SetAnimation(anim)
            body:SetPlayRate(0)
            body:Play(false)
            body:SetPosition(0, false)
        end)
    end
    s.modelComp, s.sweepPos = body, 0
    s.sweepLen = okA and (pcall(function() return anim:GetPlayLength() end) and anim:GetPlayLength() or 1) or nil
    local hid = SPC.V.modelHide(s, o)
    SPC.V.partsGone(c, s, o, true)
    log(string.format("special: %s's railguns moved onto her: %d parts", c.name, SPC.V.partsPlace(c, s, o)))
    -- her hit spheres from the x40a's size to the X-02S's (hit_radius_m), each logged once
    local spheres = {}
    for _, sc in ipairs(SPC.V.comps(o, "/Script/Engine.SphereComponent")) do
        local nm = nameOf(sc):match("([%w_]+)$") or "?"
        if not nm:find("^Damaged") then                 -- (DamagedCollision is her wreck's: 0.66.0 shrank it)
            local okR, r = pcall(function() return sc:GetUnscaledSphereRadius() end)
            if valid(sc) and okR and type(r) == "number" and c.hit_radius_m and r > c.hit_radius_m * 100 then
                pcall(function() sc:SetSphereRadius(c.hit_radius_m * 100, true) end)
                spheres[#spheres + 1] = string.format("%s %.0f -> %.0f m", nm, r / 100, c.hit_radius_m)
            elseif valid(sc) and okR then
                spheres[#spheres + 1] = string.format("%s %.0f m (kept)", nm, (r or 0) / 100)
            end
        end
    end
    log(string.format("special: %s's hit spheres: %s", c.name, #spheres > 0 and table.concat(spheres, ", ") or "none found"))
    s.modelOwner = o
    log(string.format("special: %s flies the X-02S (%s on %s%s of %s; sweep %s%s): %d other meshes hidden, %d parts gone",
        c.name, c.model:match("[^/]+$"), nameOf(body):match("([%w_]+)$") or "?",
        added and (" (added; " .. tostring(whyAdd) .. ")") or "", #names > 0 and table.concat(names, ", ") or "none",
        okA and "on" or "OFF",
        okA and string.format(" %.0f-%.0f km/h", c.sweep_kmh[1], c.sweep_kmh[2]) or (" (" .. tostring(errA) .. ")"),
        hid, #(s.parts or {})))
    return true
end
-- her other meshes (the x40a's, not the X-02S's body) hidden; how many it hid this time. (Her named body / pilot
-- meshes too: they needn't be in the tree SPC.V.comps walks.)
function SPC.V.modelHide(s, o)
    local n, me, seen = 0, addrOf(s.modelComp), {}
    local function hide(comp)
        local a = valid(comp) and addrOf(comp)
        if not a or a == me or seen[a] then return end
        seen[a] = true
        local okV, vis = pcall(function() return comp:IsVisible() end)
        if okV and vis and pcall(function() comp:SetVisibility(false, false) end) then n = n + 1 end
    end
    for _, cls in ipairs({ "/Script/Engine.StaticMeshComponent", "/Script/Engine.SkeletalMeshComponent" }) do
        for _, comp in ipairs(SPC.V.comps(o, cls)) do hide(comp) end
    end
    for _, k in ipairs({ "PilotMeshComponent", table.unpack(SPC.V.BODY_PROPS) }) do
        local ok, comp = pcall(function() return o[k] end)
        if ok and comp then hide(comp) end
    end
    return n
end
-- every tick: the wings towards their sweep for her speed (played, so it's smooth between ticks); every 2 s the
-- x40a's meshes hidden again
function SPC.V.modelTick(s, o, now)
    local c, body = CFG.specials.valka, s.modelComp
    if not valid(body) then return end
    if s.sweepLen then
        local okV, v = pcall(function() local q = o:GetVelocity(); return math.sqrt(q.X ^ 2 + q.Y ^ 2 + q.Z ^ 2) * 0.036 end)
        local lo, hi = c.sweep_kmh[1], c.sweep_kmh[2]
        local want = okV and math.max(0, math.min(1, (v - lo) / math.max(1, hi - lo))) * s.sweepLen or 0
        pcall(function()
            local cur = body:GetPosition()
            local d = want - cur
            if math.abs(d) < 0.02 * s.sweepLen then
                body:SetPlayRate(0)
            else
                body:SetPlayRate((d > 0 and 1 or -1) / math.max(0.1, c.sweep_s))
                if not body:IsPlaying() then body:Play(false) end
            end
            s.sweepPos = cur / s.sweepLen
        end)
    end
    if now < (s.modelAt or 0) then return end
    s.modelAt = now + 2
    SPC.V.partsPlace(c, s, o)
    local n = SPC.V.modelHide(s, o)
    if n > 0 and not s.modelSaid then
        s.modelSaid = true
        log("special: VALKA: " .. n .. " of the x40a's meshes came back on and were hidden again")
    end
end

-- The opener's dummy railgun (AC7's ms18_dummy_eml_p1; tools/survival_events.py VALKA_EML_*): spawned once on the
-- horizon ahead of you (user, 2026-10-24: "always spawns on the horizon, not up in the sky or anything weird"): along
-- your heading, level with you (your pitch left out), at least opener_min_alt_m up, facing you, and fixed there; it
-- never follows you. opener_km is its distance at the shot: it spawns further out by what you'll fly towards it
-- through the charge (your level speed along your heading x (charge_s + 1 s for the spawn), at most opener_max_km;
-- test of 2026-10-24: spawned 9 km out, the player was 4.8 km from it at the shot), and nearer when the combat zone's
-- edge comes first (still straight ahead). Its actor comes through the LiveAIGameObject hook (SPC.V.emlActor).
-- Returns the point and its yaw, or nil.
function SPC.V.emlSpawn(c)
    local pawn = valid(survivalPC) and survivalPC.Pawn
    local you = playerLocation()
    local h = SPC.V.heading()
    if not pawn or not you or not h or type(SV_Spawn) ~= "function" then return nil end
    local f = { X = math.cos(math.rad(h)), Y = math.sin(math.rad(h)) }
    if c.opener_bearing then                            -- a fixed compass bearing (north -Y, east +X: Mission 22's
        local b = math.rad(c.opener_bearing)            -- dummyN0 / dummyS0 sit at Y -650 / +650 km)
        f = { X = math.sin(b), Y = -math.cos(b) }
        h = math.deg(math.atan(f.Y, f.X))
    end
    local okV, v = pcall(function() local q = pawn:GetVelocity(); return { X = q.X, Y = q.Y } end)
    local closing = okV and math.max(0, v.X * f.X + v.Y * f.Y) or 0                 -- cm/s towards it
    local d = math.min(c.opener_km * 100000 + closing * (c.charge_s + 1), (c.opener_max_km or 30) * 100000)
    local edge = ZONE.HALF * 0.95                        -- (the zone's edge first: nearer, still straight ahead)
    for _, k in ipairs({ "X", "Y" }) do
        local lim = f[k] > 0.001 and (ZONE[k] + edge - you[k]) / f[k] or f[k] < -0.001 and (ZONE[k] - edge - you[k]) / f[k]
        if lim and lim > 0 then d = math.min(d, lim) end
    end
    local at = { X = you.X + f.X * d, Y = you.Y + f.Y * d, Z = math.max(you.Z, c.opener_min_alt_m * 100) }
    local yaw = (h + 180) % 360
    SPC.V.emlActor = nil
    spawningUnit = c.eml_unit
    local r = SV_Spawn(c.eml_unit, at.X, at.Y, at.Z, yaw)
    spawningUnit = nil
    at.km = math.sqrt((at.X - you.X) ^ 2 + (at.Y - you.Y) ^ 2 + (at.Z - you.Z) ^ 2) / 100000
    log(string.format("special: %s's railgun %s %.1f km out on the horizon (%s, world yaw %.0f, %.1f km up, you closing at %.0f km/h)",
        c.name, r > 0 and "up" or ("NOT up (" .. (SV_ERR[r] or tostring(r)) .. ")"), at.km,
        c.opener_bearing and string.format("compass bearing %.0f", c.opener_bearing) or "ahead of you", h, at.Z / 100000,
        closing * 0.036))
    if r <= 0 then return nil end
    return at, yaw
end

-- Her round's start (the spawn queue's "@valka"): disguised, she waits ("lurk") for the round's decoy fighters to go
-- down (SPC.valkaTick starts her opener then); else the opener starts now. False if she can't come.
function SPC.valkaSpawn(now)
    local c = CFG.specials.valka
    if not SR.usable[ACE.row("valka", "x40a", "l")] then
        log("special: VALKA's row wasn't in before this level loaded; a normal round instead")
        return false
    end
    D.special.state, D.special.at = "lurk", now
    -- the WARNING from her round's start until she's down (user, 2026-10-24: "the warning stays on for that entire
    -- round until VALKA is killed"; her attack's events set it again, SV_ValkaDown / RE_SV_ValkaEnd switch it off)
    SPC.V.event("RE_SV_ValkaWarnOn")
    if c.disguise then
        log(string.format("special: round %d is VALKA's, called out as a normal round; she attacks once its fighters are down",
            D.round))
    else
        D.special.clearAt = now                         -- (no decoys: her opener straight away)
    end
    return true
end

-- VALKA on her ace row (the x40a and its railguns) at the top fire-control level, at `at` ({ X, Y, Z } cm: where
-- her railgun fired from) facing `yaw`, or spawn_km from you when there's no opener; shown at once (her reveal). False
-- if she can't come.
function SPC.valkaArrive(now, at, yaw)
    local c = CFG.specials.valka
    local row = ACE.row("valka", "x40a", "l")
    local x, y, _, bearing = spawnPoint()
    local px, py, pb, pd = ANOM.nearPlayer(c.spawn_km)
    if px then x, y, bearing = px, py, pb end
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local z, heading = alt * 100, (bearing + 180) % 360
    if at then x, y, z, heading, pd = at.X, at.Y, at.Z, yaw, at.km end
    local set = SV_SetAircraft(c.unit, searchAircraft(row, #SPIKE_SUFFIX))
    if type(SV_SetLevel) == "function" then SV_SetLevel(c.unit, c.ai_level * 100) end
    spawningUnit = c.unit
    local r = SV_Spawn(c.unit, x, y, z, heading)
    spawningUnit = nil
    log(string.format("special: VALKA as %s (%s set), %s, heading %.0f, %.1f km up: %s", row, tostring(set),
        pd and string.format("%.1f km from you", pd) or "at a spawn point", heading or -1, z / 100000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r <= 0 then return false end
    D.flightTier = D.flightTier or {}
    D.up[c.unit], D.flown[c.unit], D.flightTier[c.unit] = true, true, #CFG.tiers.list
    D.special.state, D.special.at = "fired", now
    return true
end

-- Every tick of VALKA's round.
function SPC.valkaTick(now, s)
    local c, t, V = CFG.specials.valka, CFG.hud.text, SPC.V
    V.flareTick(c, s, now)
    V.portalTick(c, s, now)
    if s.roundsUntil then                               -- after a shot: its rounds live long (the opener's harmless)
        local harmless = s.harmUntil and now < s.harmUntil
        local n, life = SPC.V.rounds(c, harmless)
        if n > 0 and not s.roundsSaid then
            s.roundsSaid = true
            log(string.format("special: %s's railgun rounds: %d in flight, life %s s%s", c.name, n, tostring(life), harmless and ", harmless" or ""))
        end
        if now >= s.roundsUntil then s.roundsUntil, s.harmUntil = nil, nil; SPC.V.rounds(c, false) end
    end
    if s.alertOffAt and now >= s.alertOffAt then        -- the railgun alert off again after a shot
        s.alertOffAt = nil
        if not s.chargeAt then V.event("RE_SV_ValkaAlertOff") end
    end
    if s.passAt and now >= s.passAt then                -- her round passing you (its sound)
        s.passAt = nil
        SND.event(CFG.sound.valka.pass, nil)
    end
    if s.emlRemoveAt and now >= s.emlRemoveAt then      -- her railgun's gone eml_remove_s after its shot
        s.emlRemoveAt = nil
        V.event("RE_SV_ValkaEmlRemove")
    end
    if s.state == "lurk" then                           -- the decoys first: lurk_s after the last is down, the opener
        if D.state ~= "fighting" then return end
        if c.disguise then
            for u in pairs(D.up) do if SV_UnitAlive(u) > 0 then s.clearAt = nil; return end end
            s.clearAt = s.clearAt or now + c.lurk_s
        end
        if now < (s.clearAt or now) then return end
        s.emlAt, s.emlYaw = V.emlSpawn(c)
        if not s.emlAt then                             -- no railgun: she comes as she is, the reveal without the shot
            log(string.format("special: %s's railgun couldn't spawn; she comes without the opener", c.name))
            V.event("RE_SV_ValkaWarnOn")
            if not SPC.valkaArrive(now) then
                s.state = "done"
                V.event("RE_SV_ValkaEnd")               -- (the WARNING off)
                log(string.format("special: %s couldn't spawn; the round ends", c.name))
            end
            return
        end
        s.state, s.openAt, s.chargeAt = "opener", now, nil
        return
    end
    local you = playerLocation()
    if s.state == "opener" then                         -- the railgun found and hidden, the flash, the charge, the shot
        local e = V.emlActor
        if not s.chargeAt then
            if not valid(e) then
                if now - s.openAt < c.arrive_s + 3 then return end
                log(string.format("special: %s's railgun actor not found %.0f s after it spawned; the opener goes on unseen",
                    c.name, now - s.openAt))
            else
                setGone(e, true)
                SPC.V.mark(c, e)
            end
            local n, why = V.singleShot(c)
            log(string.format("special: %s's railguns single-shot: %d launcher modules%s", c.name, n, why and (" (" .. why .. ")") or ""))
            local nW, whyW = V.emlWeapon(c)
            log(string.format("special: %s's railgun rounds: %d on %s (%s)", c.name, nW, tostring(c.eml_weapon), whyW))
            log(string.format("special: %s's railguns on the minimap: %d launchers (style %d)", c.name, V.radar(c), c.radar_hud or 1))
            V.event("RE_SV_ValkaAlertOn")
            s.chargeAt = now + c.charge_s
            V.event("RE_SV_ValkaWarnOn")                -- WARNING until she's down (no banner of ours: no tells)
            V.event("RE_SV_ValkaEmlChargeOn")
            V.sndCharge(s, s.emlAt, now)
            local fx = V.flareStart(c, s, s.emlAt, now)      -- AC7 M18's lens flash; Mission 23's flash if it can't
            if fx == 0 then
                local flashes = {}
                for i = 1, c.flash_layers or 1 do flashes[i] = c.flash end
                fx = fxAt(flashes, s.emlAt, c.flash_scale, c.flash_s)
            end
            log(string.format("special: %s's opener: railgun charging %.1f km from you for %.1f s (flash: %d)", c.name,
                s.emlAt.km, c.charge_s, fx))
            return
        end
        if valid(e) then setGone(e, true); SPC.V.mark(c, e) end
        V.sndRise(s, now, c.charge_s)
        if c.portal and c.portal.enabled and not s.portalAt and now >= s.chargeAt - (c.portal.lead_s or 1) then
            s.portalAt = now
            V.portalStart(c, s, s.emlAt, now)
        end
        if now < s.chargeAt then return end
        V.singleShot(c)                                 -- (in case its module came late)
        V.emlWeapon(c)
        V.radar(c)
        V.rounds(c, true)
        V.event("RE_SV_ValkaEmlShot")
        V.event("RE_SV_ValkaEmlChargeOff")
        V.sndShot(s, s.emlAt, now)
        s.harmUntil, s.roundsUntil = now + c.reveal_s + 3, now + c.reveal_s + 3     -- its rounds: long, harmless
        s.alertOffAt = now + (c.alert_off_s or 3)
        do
            local flashes = {}
            for i = 1, c.flash_layers or 1 do flashes[i] = c.flash end
            fxAt(flashes, s.emlAt, c.flash_scale, c.flash_s)
        end
        local d = you and math.sqrt((s.emlAt.X - you.X) ^ 2 + (s.emlAt.Y - you.Y) ^ 2 + (s.emlAt.Z - you.Z) ^ 2) / 100000
        log(string.format("special: %s's opener shot from %s km", c.name, d and string.format("%.1f", d) or "?"))
        s.chargeAt, s.shots, s.state = nil, 1, "shot"
        s.shotAt, s.revealAt, s.emlRemoveAt = now, now + c.reveal_s, now + c.eml_remove_s
        return
    end
    if s.state == "shot" then                           -- reveal_s after the shot she's there, where it came from
        if now < s.revealAt then return end
        if not SPC.valkaArrive(now, s.emlAt, s.emlYaw) then
            s.state = "done"
            V.event("RE_SV_ValkaEnd")                   -- (the WARNING off)
            log(string.format("special: %s couldn't spawn after her shot; the round ends", c.name))
        end
        return
    end
    local o = glitchActor(c)
    if s.state == "fired" then                          -- shown: her health, the camera on her, her name
        if not o then
            if now - s.at >= c.arrive_s + 3 then
                s.state = "hunt"
                log(string.format("special: %s's actor not found %.0f s after she spawned; no reveal", c.name, now - s.at))
            end
            return
        end
        local hx = math.min(c.health_max_x or 1, 1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first))
        local hp = c.health * hx
        local okH = pcall(function() o.MaxHealth = hp; o.HealthInternal = math.floor(hp * 10 + 0.5) end)
        local okB = pcall(function() o.bShowHUDBox = true end)               -- (her desc's tgt too: build_survival.py)
        V.model(c, s, o)                                                     -- her X-02S
        if (s.singleN or 0) == 0 then s.singleN = V.singleShot(c) end     -- her own railguns
        V.radar(c)
        do
            local nW, whyW = V.emlWeapon(c)
            log(string.format("special: %s's own railgun rounds: %d on %s (%s)", c.name, nW, tostring(c.eml_weapon), whyW))
        end
        local cam = 1
        for k, n in ipairs(ANOMALY_CAMERAS) do if n == c.camera then cam = k end end
        V.event("RE_SV_ValkaCam_" .. string.char(64 + cam))
        V.event("RE_SV_ValkaReveal")
        s.state, s.revealedAt = "hunt", now
        s.railAt, s.turnAt, s.psAt, s.invertAt = now + c.railgun_every_s, now + c.turn_every_s, now + c.post_stall_every_s,
            now + c.invert_every_s
        hudCallout(c.anomaly_line or t.valka_sub, nil)   -- what's happening, then her name big
        hudCallout(c.name:upper(), nil, c.big_x)
        log(string.format("special: %s shows, %.0f HP (x%.2f)%s, target box %s; camera %s", c.name, hp, hx,
            okH and "" or " (health NOT set)", okB and "on" or "NOT set", ANOMALY_CAMERAS[cam]))
        return
    end
    if s.state == "done" and s.wreckUntil and now < s.wreckUntil and valid(s.modelOwner) then
        V.modelHide(s, s.modelOwner)                    -- her X-02S falls, not the x40a's wreck
        return
    end
    if s.state ~= "hunt" then return end
    s.railAt, s.turnAt = s.railAt or now + c.railgun_every_s, s.turnAt or now + c.turn_every_s   -- (no opener: no reveal)
    s.psAt, s.invertAt = s.psAt or now + c.post_stall_every_s, s.invertAt or now + c.invert_every_s
    if SV_UnitAlive(c.unit) <= 0 then
        s.state = "done"
        if s.modelComp then s.wreckUntil = now + (c.wreck_s or 15) end
        V.event("RE_SV_ValkaEnd")                       -- the WARNING off (as SV_ValkaDown, in case it's missed)
        if s.invertUntil then V.invert(c, s, false, now) end
        if s.chargeAt then V.event("RE_SV_ValkaChargeOff") end
        V.event("RE_SV_ValkaAlertOff")
        V.flareStop(s)
        V.portalStop(s)
        V.sndStop(s)
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
    V.modelTick(s, o, now)
    if now >= (s.holdAt or 0) then                       -- her parts held (EvadeOnly), again every hold_s
        s.holdAt = now + (c.hold_s or 5)
        V.event("RE_SV_ValkaHold")
    end
    if now >= (s.engageAt or 0) then                     -- her orders again (the player only), every engage_every_s
        s.engageAt = now + (c.engage_every_s or 5)
        V.event("RE_SV_ValkaEngage")
    end
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
        setGone(o, false); V.partsGone(c, s, o, false)
        s.vanished, s.nextBlink = false, now + c.blink_every_s
    elseif s.blinkUntil and now >= s.blinkUntil then
        s.blinkUntil, s.blinkCool = nil, now + c.blink_cooldown_s
    elseif s.blinkUntil and now >= s.nextBlink and not s.chargeAt then   -- gone in a puff (back next tick)
        if at then fxAt({ c.smoke }, at, c.smoke_scale, c.smoke_s) end
        setGone(o, true); V.partsGone(c, s, o, true, true)
        s.vanished = true
        return
    end
    -- her railgun: warning and charge, then one shot (when you're in front of her, near enough)
    if s.chargeAt then V.sndRise(s, now, c.railgun_charge_s) end
    if s.chargeAt and now >= s.chargeAt then
        V.event("RE_SV_ValkaRailgun")
        V.event("RE_SV_ValkaChargeOff")
        V.sndShot(s, at, now)
        s.chargeAt, s.shots, s.railAt = nil, (s.shots or 0) + 1, now + c.railgun_every_s
        s.roundsUntil, s.harmUntil = now + 3, nil
        s.alertOffAt = now + (c.alert_off_s or 3)
        log(string.format("special: %s railgun shot %d, %.1f km from you, %.0f deg off her nose", c.name, s.shots,
            s.dist or -1, offNose or -1))
    elseif not s.chargeAt and now >= s.railAt and s.dist and s.dist <= c.railgun_range_km and offNose
        and offNose <= c.railgun_cone_deg then
        s.chargeAt = now + c.railgun_charge_s
        V.event("RE_SV_ValkaChargeOn")
        V.event("RE_SV_ValkaAlertOn")
        V.radar(c)
        V.rounds(c, false)                              -- (pooled rounds from the opener: their damage back)
        V.sndCharge(s, function() return valid(o) and where(o) or nil end, now)
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
    -- (disguise: a normal round's callout and budget(budget) decoy fighters, VALKA after them: CFG.specials.valka)
    valka      = { sub = "valka_sub", disguise = function() return CFG.specials.valka.disguise end,
                   alone = function() return not CFG.specials.valka.disguise end,
                   budget = function(budget)
                       local c = CFG.specials.valka
                       if not c.disguise then return 0 end
                       local n = math.floor(budget * c.decoy_share / 2 + 0.5) * 2         -- (whole 2-ships)
                       return math.max(c.decoy_min, math.min(c.decoy_max, n, budget))
                   end,
                   spawn = function(now) return SPC.valkaSpawn(now) end,
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
