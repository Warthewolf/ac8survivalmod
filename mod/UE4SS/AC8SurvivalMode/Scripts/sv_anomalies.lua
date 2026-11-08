-- (sv_anomalies.lua is the first of 3 pieces, split by tools/lua_split_part.py: sv_anomalies_valka.lua,
-- sv_anomalies_dev.lua go on from where it ends, run by main.lua right after it, in that order.)
-- sv_anomalies.lua: the specials' Lua: MINDRIPPER, AB.L..IN, VALKA and the kinds table (SPC, ANOM).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
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
-- ((0.73.77) plan A10) you're DOWN (co-op's revives, sv_down.lua): no control scrambling then, MINDRIPPER's field nor
-- VALKA's (SV_Invert scrambled the host's spectator camera in Saint Alessia's run of 2026-11-03), and no callout of it
function downNow()
    local ok, d = pcall(function() return DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true end)
    return ok and d == true
end
ANOM.downNow = downNow
function setField(on, s)
    if ANOM.on == on then return end
    if on and downNow() then
        if not ANOM.downSaid then ANOM.downSaid = true; log("special: anomaly field held off: you're DOWN (no SV_Invert, no callout)") end
        return
    end
    ANOM.on = on
    if on then ANOM.downSaid = nil end
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
function portalFx(list, o, offset, scale, life)
    local pc = CFG.specials.anomaly.portal
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (valid(lib) and valid(o)) then return 0 end
    local n, sc = 0, scale or pc.scale
    for _, path in ipairs(list) do
        local name = path:match("[^/]+$")
        local sys = SPC.V.asset(path)                   -- ((0.73.80) kept once loaded: no /Game/ find a call)
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
function strike(o)
    local pc = CFG.specials.anomaly.portal
    local r = pc.strike_m * 100
    return portalFx({ pc.strike }, o, { X = (math.random() * 2 - 1) * r, Y = (math.random() * 2 - 1) * r,
                                         Z = (math.random() * 2 - 1) * r * 0.5 })
end

-- The same systems at a world location (where MINDRIPPER was shot down; AB.L..IN's smoke), switched off after `life`
-- seconds (the portal's death_fx_s by default); how many came up.
function fxAt(list, at, scale, life)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (valid(lib) and valid(survivalPC) and at) then return 0 end
    local n = 0
    for _, path in ipairs(list) do
        local sys = SPC.V.asset(path)                   -- ((0.73.80) kept once loaded: VALKA's flash at her opener's shot
        if sys and pcall(function()                     -- scanned every object 4 times (its layers), her smoke each blink)
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
function portalTick(now, s, c)
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
function glitchActor(c)
    for _, list in ipairs({ planes, pending }) do
        for _, q in ipairs(list) do if q.unit == c.unit and valid(q.obj) then return q.obj end end
    end
end
function where(o)
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
function setGone(o, gone)
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
-- (for the ace squadrons' blinks, P9: sv_ai.lua ACE.squadTick) the ground's height under a point (nil: no hit), and
-- AB.L..IN's smoke at a point (how many systems came up)
ANOM.groundAt = groundAt
function ANOM.smokeAt(at)
    local c = CFG.specials.glitch
    return fxAt({ c.smoke }, at, c.smoke_scale, c.smoke_s)
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
-- (less when the player flies lower than that). Its phase 2 (CFG.specials.glitch.phases, P7): behind_share of the
-- blinks at the spot nearest the player's six instead (their heading, SPC.V.heading: world degrees, 0 = +X, the
-- spots' own; the nearest 30-degree spot, at most 15 off dead six, either ring, the last one's bearing no bar).
-- Returns its event, the point, its distance (cm), the ground, its bearing and whether it was a behind pick (and the
-- heading it was behind), or nil.
local function blinkSpot(c, s, you)
    local bl = c.blinks
    local want = math.random() * 360
    if s.lastDeg then want = s.lastDeg + c.blink_turn_deg + math.random() * (360 - 2 * c.blink_turn_deg) end
    local ph, behind, head = c.phases, false, nil
    if s.phase == 2 and ph and ph.enabled and math.random() < (tonumber(ph.behind_share) or 0) and SPC.V and SPC.V.heading then
        head = SPC.V.heading()
        if head then want, behind = (head + 180) % 360, true end
    end
    local spots = {}
    for ring, m in ipairs(bl.rings_m) do
        for k = 0, math.floor(360 / bl.step_deg) - 1 do
            local deg = k * bl.step_deg
            local off = math.abs((deg - want + 180) % 360 - 180)
            local fromLast = s.lastDeg and math.abs((deg - s.lastDeg + 180) % 360 - 180) or 360
            spots[#spots + 1] = { ev = "RE_SV_GlitchBlink_" .. string.char(64 + ring) .. string.char(65 + k), deg = deg, d = m * 100,
                                  off = off + (behind and 0 or math.random() * bl.step_deg)   -- (either ring, near the bearing wanted)
                                        + ((not behind and fromLast < c.blink_turn_deg) and 1000 or 0) }   -- (last resort: near the last)
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
        if not ground or to.Z >= ground + clear then return p.ev, to, p.d, ground, p.deg, behind, head end
    end
    return nil
end

-- AB.L..IN's phases (CFG.specials.glitch.phases; behaviour roadmap P7, docs/re/BEHAVIOUR_DIRECTOR.md unit 9): 1 as it
-- always was (a frenzy of blinks round you each time it's hit); 2 once behind_after frenzies are over (its blinks
-- behind you: blinkSpot); 3 at allout_hp of its health as it appeared (no more frenzies, its ECM down, its gun at you
-- whenever you're close in front of it, LastTGT onto you). Each change logged and told first ("glitch_six": the host's,
-- the blinks are round the host; "glitch_allout": every player).
local function glitchPhase(c, s, n, now, why)
    if s.phase == n then return end
    local was = s.phase or 1
    s.phase = n
    local ph = c.phases
    if n == 3 then
        if s.frenzyUntil then s.frenzyUntil = math.min(s.frenzyUntil, now) end    -- (back from a blink, then it's over)
        s.ecmFireAt, s.podsAt = nil, now                    -- (no more ECM events; the pods up off: glitchPodsOff)
        s.turnAt = now + 1
    end
    if TELL then pcall(TELL.say, n == 3 and "glitch_allout" or "glitch_six", n == 3 and TELL.ALL or nil) end   -- (sure tells)
    local ecm = {}                                       -- (how its ECM goes down: its pods switched off, its row)
    if ph.ecm_pods_off then ecm[#ecm + 1] = string.format("its pods switched off every %.0f s", math.max(1, tonumber(ph.ecm_check_s) or 3)) end
    if ph.ecm_row then ecm[#ecm + 1] = "its pod's own row once a minute at most" end
    if #ecm == 0 then ecm[1] = "neither ecm_pods_off nor ecm_row: its pod's row keeps it up" end
    log(string.format("special: %s phase %d (from %d): %s; %s", c.name, n, was, why, n == 2
        and string.format("%.0f %% of its blinks behind you", (tonumber(ph.behind_share) or 0) * 100)
        or string.format("no more frenzies, its ECM down (%s), its gun at you within %.1f km and %.0f deg of its nose every %.1f s, LastTGT every %.0f s",
            table.concat(ecm, ", "), ph.allout_range_km, ph.allout_cone_deg, ph.allout_gun_s, ph.allout_turn_s)))
end

-- Its ECM pods switched off (phase 3, ecm_pods_off; untested in game: a live write to the pod weapon's fields,
-- docs/re/MINIMAP_MARKERS.md 3: LiveElectronicSupportMeasures bJammingEnable / bSupportEnable). Never destroyed (a
-- weapon actor destroyed from Lua crashed the game: sv_ladon.lua). Its pods: BP_wp_ecm_a0 actors whose owner (or
-- instigator) is AB.L..IN; the first time, the log says what each read before and after (and once when none of the
-- pods up is its own: a tester greps "ECM pods off" either way; code review of 2026-10-29).
function glitchPodsOff(c, s, o)
    local mine = addrOf(o)
    local found, off, said, pods = 0, 0, {}, 0
    for _, w in ipairs(FindAllOf("BP_wp_ecm_a0_C") or {}) do
        pods = pods + 1
        local okO, own = pcall(function() return w:GetOwner() end)
        local okI, ins = pcall(function() return w:GetInstigator() end)
        local ours = (okO and valid(own) and addrOf(own) == mine) or (okI and valid(ins) and addrOf(ins) == mine)
        if valid(w) and ours then
            found = found + 1
            local okB, before = pcall(function() return tostring(w.bJammingEnable) .. "/" .. tostring(w.bSupportEnable) end)
            local okW = pcall(function() w.bJammingEnable = false; w.bSupportEnable = false end)
            local okA, after = pcall(function() return tostring(w.bJammingEnable) .. "/" .. tostring(w.bSupportEnable) end)
            if okW then off = off + 1 end
            said[#said + 1] = string.format("%s -> %s", okB and before or "?", okA and after or "?")
        end
    end
    if not s.podsSaid and found > 0 then
        s.podsSaid = true
        log(string.format("special: %s's ECM pods off: %d of %d (jamming/support %s)", c.name, off, found, table.concat(said, ", ")))
    elseif not s.podsSaid and not s.podsNoneSaid and found == 0 then
        s.podsNoneSaid = true
        log(string.format("special: %s's ECM pods off: none of its own found (%d BP_wp_ecm_a0 up, none its own by "
            .. "owner or instigator); looked for again every ecm_check_s", c.name, pods))
    end
    return found, off
end

-- A frenzy's blinks (each hit outside one starts one, phases 1 and 2): every blink_every_s it vanishes in a puff and
-- comes back the next tick at a blink spot round you (blinkSpot), until frenzy_s are up; the first three blinks
-- checked a tick on (where it really is)
local function glitchFrenzy(c, s, o, at, you, now)
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
        local ev, to, d, ground, deg, behind, head
        if you then ev, to, d, ground, deg, behind, head = blinkSpot(c, s, you) end
        if ev then
            s.lastDeg = deg
            local r = type(SV_Event) == "function" and SV_Event(ev) or -5
            s.blinks = (s.blinks or 0) + 1
            if r ~= 1 then log(string.format("special: %s blink %s not fired: %s", c.name, ev, SV_ERR[r] or tostring(r))) end
            if behind then                              -- (phase 2: at your six; the first few, and every 10th, logged)
                s.behindBlinks = (s.behindBlinks or 0) + 1
                if s.behindBlinks <= 3 or s.behindBlinks % 10 == 0 then
                    log(string.format("special: %s blink %d behind you (%d behind so far): your heading %.0f -> spot %d (%s, %.0f m)",
                        c.name, s.blinks, s.behindBlinks, head or -1, deg, ev, d / 100))
                end
            end
            if s.blinks <= 3 or (behind and s.behindBlinks == 1) then
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
        local ph = c.phases                             -- (behind_after frenzies over: phase 2, P7)
        if ph and ph.enabled and (s.phase or 1) == 1 and (s.frenzies or 0) >= (tonumber(ph.behind_after) or math.huge) then
            glitchPhase(c, s, 2, now, string.format("%d frenzies over", s.frenzies))
        end
    elseif now >= s.nextBlink then                      -- gone in a puff (back next tick)
        glitchSmoke(s, at)
        setGone(o, true)
        s.vanished = true
    end
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
        s.phase, s.hp0 = 1, (okN and type(hn) == "number" and hn > 0) and hn or nil   -- (its phases: their health mark)
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
        -- ((0.73.78, economy C3) each player's share in co-op: specialPay, sv_ai.lua)
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, specialPay(pay)))
        log(string.format("special: round %d, %s shot down %.0f s after it appeared (%d frenzies, %d blinks; phase %d, %d blinks behind you, %d LastTGT)",
            D.round, c.name, now - s.at, s.frenzies or 0, s.blinks or 0, s.phase or 1, s.behindBlinks or 0, s.turns or 0))
        return
    end
    if not o then return end
    local at, you = where(o), playerLocation()
    s.lastAt = at or s.lastAt
    if at and you then s.dist = math.sqrt((at.X - you.X) ^ 2 + (at.Y - you.Y) ^ 2 + (at.Z - you.Z) ^ 2) / 100000 end
    local okH, h = pcall(function() return o.HealthInternal end)
    h = okH and type(h) == "number" and h or nil
    local ph = c.phases
    local phased = ph and ph.enabled
    if phased and h and s.hp0 and s.phase ~= 3 and h <= s.hp0 * (tonumber(ph.allout_hp) or 0) then   -- (phase 3: P7)
        glitchPhase(c, s, 3, now, string.format("at %.0f %% of its health (%.0f of %.0f)", h / s.hp0 * 100, h, s.hp0))
    end
    if h and s.lastHp and h < s.lastHp - 0.5 and not s.frenzyUntil and s.phase ~= 3 then      -- hit: a frenzy
        s.frenzyUntil, s.nextBlink = now + c.frenzy_s, now
        s.frenzies = (s.frenzies or 0) + 1
        local okD, dmg = pcall(function() return o:GetDamagePercentage() end)
        log(string.format("special: %s hit (%.0f -> %.0f, damage %s %%): frenzy %d for %.0f s", c.name, s.lastHp, h,
            okD and string.format("%.0f", dmg) or "?", s.frenzies, c.frenzy_s))
    end
    s.lastHp = h or s.lastHp
    if s.phase ~= 3 and now >= (s.ecmFireAt or 0) then  -- its ECM pod up (fired by event: hard to keep up by its FCS)
        s.ecmFireAt = now + c.ecm_every_s
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_GlitchEcm") or -5
        if r ~= 1 and not s.ecmSaid then s.ecmSaid = true; log("special: RE_SV_GlitchEcm not fired: " .. (SV_ERR[r] or tostring(r))) end
    end
    local offNose = nil                                 -- (phase 3: you off its nose, degrees, as VALKA's)
    if s.phase == 3 and at and you then
        local okF, f = pcall(function() local q = o:GetActorForwardVector(); return { X = q.X, Y = q.Y, Z = q.Z } end)
        local tx, ty, tz = you.X - at.X, you.Y - at.Y, you.Z - at.Z
        local n = math.sqrt(tx * tx + ty * ty + tz * tz)
        if okF and n > 0 then offNose = math.deg(math.acos(math.max(-1, math.min(1, (f.X * tx + f.Y * ty + f.Z * tz) / n)))) end
        if ph.ecm_pods_off and now >= (s.podsAt or 0) then           -- (its pods up switched off, every ecm_check_s)
            s.podsAt = now + math.max(1, tonumber(ph.ecm_check_s) or 3)
            pcall(glitchPodsOff, c, s, o)
        end
        -- LastTGT onto you every allout_turn_s, and at once (allout_behind_s apart) when you're behind it (VALKA's; not
        -- straight into a post-stall)
        local behind = offNose and offNose > 110 and s.dist and s.dist <= (tonumber(ph.allout_behind_km) or 3)
        if type(SV_Event) == "function" and (now >= (s.turnAt or 0) or (behind and now >= (s.behindAt or 0))) then
            s.turnAt, s.behindAt, s.turns = now + ph.allout_turn_s, now + ph.allout_behind_s, (s.turns or 0) + 1
            s.psAt, s.psGapAt = math.max(s.psAt or 0, now + 3), math.max(s.psGapAt or 0, now + 3)
            local r = SV_Event("RE_SV_GlitchTurn")
            if s.turns <= 5 or s.turns % 10 == 0 then
                log(string.format("special: %s LastTGT %d (%s)%s, %.1f km from you", c.name, s.turns, tostring(r),
                    behind and ", you behind it" or "", s.dist or -1))
            end
        end
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
    if s.frenzyUntil then glitchFrenzy(c, s, o, at, you, now) end
    -- its gun at where you'll be, every tick of a frenzy, and in phase 3 whenever you're within allout_range_km and
    -- allout_cone_deg of its nose (P7: "goes all-out guns"; its gun's own row aims as before)
    local hot3 = s.phase == 3 and not s.vanished and s.dist and s.dist <= ph.allout_range_km and offNose
        and offNose <= ph.allout_cone_deg
    local gunsHot = (s.frenzyUntil and not s.vanished) or hot3
    if hot3 and not s.hotSaid then
        s.hotSaid = true
        log(string.format("special: %s's guns all out: you %.1f km off its nose (%.0f deg)", c.name, s.dist, offNose))
    end
    local led = false
    if gunsHot and you and (c.gun_lead_s or 0) > 0 and not s.leadFail then
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
                log(string.format("special: %s's gun leads you %.1f s (%.0f m ahead), %d shots a tick%s", c.name, L,
                    math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) * L / 100, c.gun_lead_shots or 1,
                    c.gun_lead_event and ", the event's too" or ""))
            end
        end
    end
    if gunsHot and (not led or c.gun_lead_event) and now >= (s.gunAt or 0) then
        -- (the event: 5 shots 0.1 s apart, at you; phase 3 outside a frenzy every allout_gun_s, and a co-op host's then
        -- on its own game alone: hot3 is the host's geometry, and forwarded it fired each joiner's copy at that joiner;
        -- code review of 2026-10-29. A frenzy's are forwarded as before)
        local allout = hot3 and not s.frenzyUntil
        s.gunAt = now + (allout and ph.allout_gun_s or c.gun_every_s)
        local r
        if allout and COOP and COOP.host() and COOP.eventHere then
            r = COOP.eventHere("RE_SV_GlitchGun")
            if not s.gunHereSaid then
                s.gunHereSaid = true
                log(string.format("special: %s's phase-3 gun events on the host alone (its joiners' copies fire their own)", c.name))
            end
        else
            r = type(SV_Event) == "function" and SV_Event("RE_SV_GlitchGun") or -5
        end
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
-- ((0.73.80) the 31-round co-op run of 2026-11-03, testing/logs/2026-11-04/R30_FINDINGS.json specials 2 / perf 6: on the
-- host ~0.74 s at her opener, ~0.7 s at her reveal, and 30 walks for her rounds that found none. singleShot, emlWeapon and
-- radar each walked every object for her railguns' modules (35-50 ms a walk, 6-7 in one tick at her opener, its shot and
-- her reveal), and SPC.V.rounds walked for her rounds every tick for 3-3.5 s after each shot: "BP_wp_eml_ldbs01_C 30x
-- 1155 ms (0 found)".) Her railguns' modules are kept as the game makes them, not walked for: every
-- LiveFCSModule_LauncherTripleRailCannon (only hers and her opener's are in Survival: what the walk found), and the
-- projectile modules made while SV_Spawn spawns her or her opener (spawningUnit) or within MOD_REC_S of it, by
-- NotifyOnNewObject (the callbacks only keep the object: it's still being built). Each is checked live (liveObj) before
-- it's read and dropped the first time it's gone. A walk only when the hook couldn't be registered, or when none is kept
-- by the time she needs them (once a tick at most, logged); radarOff never walks for them with the hook in.
SPC.V.EML_MODULES = { "LiveFCSModule_ProjectileCommon", "LiveFCSModule_ProjectileMulti", "LiveFCSModule_ProjectileWeapon" }
SPC.V.MOD_REC_S = 3
SPC.V.MOD = { L = {}, P = {}, rec = {}, recUntil = nil, hookL = false, hookP = 0, walkKey = nil, walkL = nil,
              walkPKey = nil, walkP = nil, pWalked = {}, walks = 0, offBy = {}, seq = 0, mark = {}, forceWalk = false }
do
    local V = SPC.V
    local MAX_L, MAX_P = 64, 256
    local function hers(u)
        local c = CFG and CFG.specials and CFG.specials.valka
        return u ~= nil and type(c) == "table" and (u == c.unit or u == c.eml_unit)
    end
    if type(NotifyOnNewObject) == "function" then
        local okL = pcall(NotifyOnNewObject, "/Script/Live.LiveFCSModule_LauncherTripleRailCannon", function(o)
            local M = V.MOD
            M.seq = M.seq + 1
            if #M.L < MAX_L then M.L[#M.L + 1] = { obj = o, seq = M.seq } end
            local u = spawningUnit
            if hers(u) then M.rec[u] = (M.rec[u] or 0) + 1 end
        end)
        V.MOD.hookL = okL == true
        for _, cn in ipairs(V.EML_MODULES) do
            local okP = pcall(NotifyOnNewObject, "/Script/Live." .. cn, function(o)
                local M = V.MOD
                if #M.P < MAX_P and (hers(spawningUnit) or (M.recUntil ~= nil and os.clock() < M.recUntil)) then
                    M.P[#M.P + 1] = { obj = o }
                end
            end)
            if okP then V.MOD.hookP = V.MOD.hookP + 1 end
        end
    end
    log(string.format("special: VALKA's railgun modules kept as the game makes them (NotifyOnNewObject: launchers %s, "
        .. "projectile modules %d of %d); a walk only without", V.MOD.hookL and "yes" or "NO", V.MOD.hookP, #V.EML_MODULES))
    -- (the teardown gate's drop, sv_core.lua levelDrop: the modules kept forgotten with the level, none of them touched)
    if type(LEVEL_DROPS) == "table" then
        LEVEL_DROPS["VALKA's railgun modules"] = function()
            local M = V.MOD
            M.L, M.P, M.rec, M.recUntil, M.pWalked, M.offBy, M.mark, M.forceWalk = {}, {}, {}, nil, {}, {}, {}, false
            M.walkKey, M.walkL, M.walkPKey, M.walkP = nil, nil, nil, nil
        end
    end
end
-- (a tick's key, for "once a tick": the round clock, a joiner's too)
local function tickKey() return (D and D.now) or os.clock() end
-- her round's start: the projectile modules and counts of the last one forgotten, the dead launchers dropped
function SPC.V.modReset()
    local M = SPC.V.MOD
    M.P, M.rec, M.recUntil, M.pWalked, M.offBy, M.mark, M.forceWalk = {}, {}, nil, {}, {}, {}, false
    M.walkKey, M.walkL, M.walkPKey, M.walkP, M.walks = nil, nil, nil, nil, 0
    SPC.V.keptLaunchers()
end
-- just before her (or her opener's) SV_Spawn: the launchers kept from here on are that unit's (modMark), and once it's
-- done projectile modules made in the next MOD_REC_S are kept too (made late: modRecord)
function SPC.V.modMark(unit)
    SPC.V.MOD.mark[unit] = SPC.V.MOD.seq
end
function SPC.V.modRecord()
    SPC.V.MOD.recUntil = os.clock() + SPC.V.MOD_REC_S
end
-- what was kept as `unit` spawned, for the log. None kept since it spawned with the hook in (the game made its launchers
-- some way NotifyOnNewObject doesn't see: her opener's walked for would otherwise stand in for hers): the next ask walks
-- for them, once.
function SPC.V.modSaid(c, unit, who)
    local M = SPC.V.MOD
    local list = SPC.V.keptLaunchers()
    local fresh = 0
    for _, e in ipairs(M.L) do if (e.seq or 0) > (M.mark[unit] or 0) then fresh = fresh + 1 end end
    if M.hookL and fresh == 0 then M.forceWalk = true end
    log(string.format("special: %s's railgun modules: %d launcher(s) made as %s spawned (%d of them kept, %d up in all), %d "
        .. "projectile modules kept (NotifyOnNewObject%s)", c.name, M.rec[unit] or 0, who, fresh, #list, #M.P,
        not M.hookL and ": NOT registered, walks instead" or fresh == 0 and ": none of this spawn's, one walk for them" or "; no walk"))
end
-- the launcher modules kept that are still up (live instances); the gone ones dropped, and the templates the hook sees as
-- a class loads (a class default's or an archetype's: RF_ClassDefaultObject | RF_ArchetypeObject, 0x30, or a name
-- under Default__), which the walk never found and which must never be changed (the campaign's x40a). No walk.
local function template(o)
    local okF, f = pcall(function() return o:HasAnyFlags(0x30) end)
    if okF and f == true then return true end
    local n = nameOf(o)
    return n:find("Default__", 1, true) ~= nil or n:find("_GEN_VARIABLE", 1, true) ~= nil
end
function SPC.V.keptLaunchers()
    local M, out, keep = SPC.V.MOD, {}, {}
    for _, e in ipairs(M.L) do
        if liveObj(e.obj) then
            if e.tpl == nil then e.tpl = template(e.obj) end
            if not e.tpl then keep[#keep + 1] = e; out[#out + 1] = e.obj end
        end
    end
    M.L = keep
    return out
end
-- her railguns' launcher modules up now. need: walk for them when none is kept (or with no hook), once a tick at most;
-- else (radarOff) only with no hook. Returns them and how ("kept", "walked", "held").
function SPC.V.launchers(need)
    local M = SPC.V.MOD
    local out = SPC.V.keptLaunchers()
    if M.hookL and not (need and M.forceWalk) and (#out > 0 or not need) then return out, "kept" end
    if walkHold and walkHold() then return out, "held" end      -- (no object walk while a level comes or goes)
    local key = tickKey()
    if M.walkKey ~= key then
        M.walkKey, M.walkL = key, {}
        M.walks = (M.walks or 0) + 1
        local ok, list = pcall(FindAllOf, "LiveFCSModule_LauncherTripleRailCannon")
        local have = {}
        for _, e in ipairs(M.L) do local a = addrOf(e.obj); if a then have[a] = true end end
        for _, m in ipairs(ok and list or {}) do
            M.walkL[#M.walkL + 1] = m
            local a = addrOf(m)
            if M.hookL and #M.L < 64 and not (a and have[a]) then M.L[#M.L + 1] = { obj = m } end   -- (kept from now on)
        end
        log(string.format("special: VALKA's railgun launcher modules: %s; one walk instead: %d found",
            M.hookL and "none kept as the game made them" or "no NotifyOnNewObject for them", #M.walkL))
    end
    M.forceWalk = false                                 -- (this tick's walk answers it)
    return M.walkL or {}, "walked"
end
-- the projectile modules beside the launchers whose outers are `outers` ({ [address] = true }): the kept ones, and for a
-- launcher with none kept beside it one walk of the three classes (once a tick; each outer once until her next round)
function SPC.V.projBeside(outers)
    local M, out, seen, have, keep = SPC.V.MOD, {}, {}, {}, {}
    local function take(p, kept)
        local a = addrOf(p)
        local okO, o = pcall(function() return p:GetOuter() end)
        local oa = okO and liveObj(o) and addrOf(o)
        if a and oa and outers[oa] and not seen[a] then
            seen[a], have[oa] = true, true
            out[#out + 1] = p
            if not kept and #M.P < 256 then M.P[#M.P + 1] = { obj = p } end
        end
    end
    for _, e in ipairs(M.P) do
        if liveObj(e.obj) then keep[#keep + 1] = e; take(e.obj, true) end
    end
    M.P = keep
    local missing = 0
    for oa in pairs(outers) do if not have[oa] and not M.pWalked[oa] then missing = missing + 1 end end
    if missing == 0 and M.hookP > 0 then return out, "kept" end
    if walkHold and walkHold() then return out, "held" end
    for oa in pairs(outers) do if not have[oa] then M.pWalked[oa] = true end end
    local key = tickKey()
    if M.walkPKey ~= key then
        M.walkPKey, M.walkP = key, {}
        M.walks = (M.walks or 0) + 1
        for _, cn in ipairs(SPC.V.EML_MODULES) do
            local okP, ps = pcall(FindAllOf, cn)
            for _, p in ipairs(okP and ps or {}) do M.walkP[#M.walkP + 1] = p end
        end
        log(string.format("special: VALKA's railgun projectile modules: %d launcher(s) with none kept beside them%s; one walk "
            .. "of the %d classes instead: %d modules", missing, M.hookP > 0 and "" or " (no NotifyOnNewObject for them)",
            #SPC.V.EML_MODULES, #M.walkP))
    end
    for _, p in ipairs(M.walkP or {}) do if liveObj(p) then take(p, false) end end
    return out, "walked"
end
-- her railgun parts fire one round a shot (user, 2026-10-24: "I only want single shot"; Mission 26's fire 3): the x40a
-- railguns' launcher modules (only hers are in Survival) get TriggerCount / MagazineCapacity single_shot. Returns how many.
function SPC.V.singleShot(c)
    local n, why = 0, nil
    for _, m in ipairs((SPC.V.launchers(true))) do
        local okS, err = pcall(function()
            m.FireControl.TriggerCount = c.single_shot
            m.Performance.MagazineCapacity = c.single_shot
        end)
        if okS then n = n + 1 else why = why or tostring(err) end
    end
    return n, why
end
-- ((0.73.80) her railgun's round class and its class default, kept once found (liveObj): one find a level, not two
-- StaticFindObject scans of /Game/ paths a call ("finds: worst 42 ms (.../Default__BP_wp_eml_ldbs01_C)"). Class, CDO
-- (nil if it can't be found), or nil and why.
SPC.V.RC = { path = nil, cls = nil, cdo = nil, was = nil, wasAddr = nil, mode = nil }
function SPC.V.roundClass(c)
    local R = SPC.V.RC
    local path = c.eml_weapon
    if not path or path == "" then return nil, nil, "off" end
    if R.path == path and R.cls ~= nil and liveObj(R.cls) and (R.cdo == nil or liveObj(R.cdo)) then return R.cls, R.cdo end
    local nm = path:match("[^/]+$")
    local cls, why = SPC.V.asset(path, nm .. "_C")
    if not cls then R.path, R.cls, R.cdo = nil, nil, nil; return nil, nil, why end
    local cdo = nil
    local okC, d = pcall(function() return cls:GetCDO() end)
    if okC and d ~= nil and liveObj(d) then cdo = d
    else
        d = StaticFindObject(path .. ".Default__" .. nm .. "_C")
        if d ~= nil and liveObj(d) then cdo = d end
    end
    R.path, R.cls, R.cdo = path, cls, cdo
    return cls, cdo
end
-- her railguns fire the land battleship's round (c.eml_weapon; user, 2026-10-24: "try putting a land battleship
-- railgun weapon on her EML"): each projectile module that sits beside an x40a railgun's launcher module (the same
-- outer) gets its class and class default. Instances only (her railguns and the opener's, the only ones in Survival):
-- the stock x40a and the land battleship keep theirs. Returns how many changed, and a note.
function SPC.V.emlWeapon(c)
    if not c.eml_weapon or c.eml_weapon == "" then return 0, "off" end
    local nm = c.eml_weapon:match("[^/]+$")
    local cls, cdo, why = SPC.V.roundClass(c)
    if not cls then return 0, nm .. " not loaded (" .. tostring(why) .. ")" end
    local outers, nL = {}, 0
    local list, howL = SPC.V.launchers(true)
    for _, m in ipairs(list) do
        local okO, out = pcall(function() return m:GetOuter() end)
        local oa = okO and liveObj(out) and addrOf(out)
        if oa then outers[oa] = true; nL = nL + 1 end
    end
    local mods, howP = SPC.V.projBeside(outers)
    local n, nP, was = 0, 0, {}
    for _, p in ipairs(mods) do
        nP = nP + 1
        local okW, w = pcall(function() return p.WeaponClass:GetFName():ToString() end)
        if okW and w == nm .. "_C" then n = n + 1
        elseif pcall(function() p.WeaponClass = cls; if cdo then p.WeaponCDO = cdo end end) then
            n = n + 1
            was[#was + 1] = okW and w or "?"
        end
    end
    local okT, life = pcall(function() return cdo.LifeTime end)
    return n, string.format("%d launchers, %d projectile modules beside them (%s, %s); was %s; %s life %s s", nL, nP, howL,
        howP, #was > 0 and table.concat(was, ", ") or "-", nm, okT and tostring(life) or "?")
end
-- Her railgun's rounds (c.eml_weapon's): one at a time (ROUND_ONE: no burst, no donut spread; the land battleship's fires
-- a ring of them), each living eml_life_s, and none doing damage from her opener's charge until she spawns (the
-- opener's shot). ((0.73.80) on the round class's default, not on rounds: a walk for them every tick found none in the
-- 31-round run (30 walks, 0 found), so none of it reached a round; a round takes these as it's made, and only hers are
-- made of this class in Survival.) mode: "opener" (the opener's: life, bursts off, damage 0), "hers" (the same, her
-- damage back: called just before she spawns, so rounds made for her own railguns hurt) or "off" (everything as it
-- was: her end, a run over). The class default's own values are kept the first time (per class default), so "off" puts
-- back the stock ones. True if it changed it.
SPC.V.ROUND_ONE = { { "bBurstShot", false }, { "BurstShotCount", 1 }, { "bFireAllInOneShot", false },
                    { "bDonutsShot", false }, { "bMultipleLockOn", false } }
SPC.V.ROUND_KEEP = { "LifeTime", "EffectiveTime", "damage", "bBurstShot", "BurstShotCount", "bFireAllInOneShot",
                     "bDonutsShot", "bMultipleLockOn" }
function SPC.V.roundDefaults(c, mode)
    local R = SPC.V.RC
    if not c or not c.eml_weapon or c.eml_weapon == "" then return false end
    local nm = c.eml_weapon:match("[^/]+$")
    local cdo
    if mode == "off" then
        if not R.mode then return false end
        -- (never loaded or looked for at the end: the one kept, if it's still live (liveObj: GUObjectArray). Put back even
        -- as the level goes: a class default isn't the level's (its package is the round's, kept loaded by the preload),
        -- and left as hers the land battleship's railgun in a campaign mission after a quit would fire her rounds)
        cdo = R.cdo ~= nil and liveObj(R.cdo) and R.cdo or nil
        if not cdo then R.mode = nil; return false end
    else
        local _, d, why = SPC.V.roundClass(c)
        if not d then
            if not R.noCdoSaid then
                R.noCdoSaid = true
                log(string.format("special: VALKA's round %s: no class default (%s); her rounds as they come", nm, tostring(why or "not found")))
            end
            return false
        end
        cdo = d
    end
    local a = addrOf(cdo)
    if R.wasAddr ~= a or not R.was then              -- (its own values, once a class default: what "off" puts back)
        R.was, R.wasAddr = {}, a
        for _, f in ipairs(SPC.V.ROUND_KEEP) do
            local okF, v = pcall(function() return cdo[f] end)
            if okF and v ~= nil then R.was[f] = v end
        end
        local said = {}
        for _, f in ipairs(SPC.V.ROUND_ONE) do said[#said + 1] = f[1] .. " " .. tostring(R.was[f[1]] == nil and "?" or R.was[f[1]]) end
        log("special: VALKA's round " .. nm .. " (class default): " .. table.concat(said, ", "))   -- (test of 2026-10-24, 0.67.1: "it fires multiple bursts at you")
    end
    local W = R.was
    local want = {}
    if mode == "off" then
        for f, v in pairs(W) do want[f] = v end
    else
        local life = tonumber(c.eml_life_s) or (type(W.LifeTime) == "number" and W.LifeTime) or 10   -- ((0.73.76) eml_life_s itself)
        for _, f in ipairs(SPC.V.ROUND_ONE) do want[f[1]] = f[2] end
        want.LifeTime = life
        if type(W.EffectiveTime) == "number" and W.EffectiveTime > 0 then want.EffectiveTime = math.min(W.EffectiveTime, life) end
        if W.damage ~= nil then want.damage = (mode == "opener") and 0 or W.damage end
    end
    local changed = {}
    for _, f in ipairs(SPC.V.ROUND_KEEP) do
        local v = want[f]
        if v ~= nil then
            local okR, cur = pcall(function() return cdo[f] end)
            if not (okR and cur == v) and pcall(function() cdo[f] = v end) then
                changed[#changed + 1] = string.format("%s %s -> %s", f, okR and tostring(cur) or "?", tostring(v))
            end
        end
    end
    R.mode = mode ~= "off" and mode or nil
    local what = mode == "opener" and "for her opener's shot (no damage until she spawns)"
        or mode == "hers" and "for her own railguns (her damage back before she spawns)" or "put back as it was"
    log(string.format("special: VALKA's railgun round %s's class default %s: %s (0.73.80: no walk for its rounds)", nm, what,
        #changed > 0 and table.concat(changed, ", ") or "as it was already"))
    if mode ~= "off" then pcall(SPC.V.roundHook, c) end
    return #changed > 0
end
-- ((review of 0.73.80) her rounds are pooled: one made while the class default was the opener's (damage 0) keeps that
-- when it's fired again for her. Each round of the class is kept as the game makes it (NotifyOnNewObject on the round's
-- class, hooked once its class is loaded: roundDefaults), at most RK_MAX, dropped the first time it's gone (liveObj),
-- and SPC.V.roundsHarm puts her damage (the class default's own) back on each at her charges: 0.73.79's rounds walk
-- did that for the pool, a FindAllOf each time.)
SPC.V.RK = { list = {}, hooked = nil, failSaid = nil }
local RK_MAX = 64
function SPC.V.roundHook(c)
    local K = SPC.V.RK
    local path = c and c.eml_weapon
    if not path or path == "" or K.hooked == path then return end
    local nm = path:match("[^/]+$")
    local okH, err = pcall(NotifyOnNewObject, path .. "." .. nm .. "_C", function(o)
        local L = SPC.V.RK.list
        if #L < RK_MAX then L[#L + 1] = o end
    end)
    if okH then
        K.hooked = path
        log("special: VALKA's railgun rounds (" .. nm .. ") kept as the game makes them (their damage put back at her charges)")
    elseif not K.failSaid then
        K.failSaid = true
        log("special: VALKA's railgun rounds (" .. nm .. ") can't be watched (" .. tostring(err) .. "): a round pooled from her "
            .. "opener's shot may stay harmless")
    end
end
-- her damage (the class default's own, kept by roundDefaults) on every kept round of hers: how many changed
function SPC.V.roundsHarm(c)
    local K, W = SPC.V.RK, SPC.V.RC.was
    if not (W and W.damage ~= nil) then return 0 end
    local keep, n = {}, 0
    for _, r in ipairs(K.list) do
        if liveObj(r) then
            keep[#keep + 1] = r
            local okD, d = pcall(function() return r.damage end)
            if not (okD and d == W.damage) and pcall(function() r.damage = W.damage end) then n = n + 1 end
        end
    end
    K.list = keep
    if n > 0 then
        log(string.format("special: %s's railgun rounds: her damage (%s) back on %d of the %d kept (made for her opener's shot)",
            tostring(c and c.name or "VALKA"), tostring(W.damage), n, #keep))
    end
    return n
end
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["VALKA's railgun rounds"] = function() SPC.V.RK.list = {} end   -- (the level's objects: forgotten, not touched)
end
-- her railguns on the minimap: each x40a railgun launcher's radar display on, forced, in radar_hud's style. ((0.73.80) not
-- one radarOff took off with its actor, her removed opener's: a walk found it still in memory and every charge of hers
-- put it back on the minimap, where D4 had taken it off)
function SPC.V.radar(c)
    local n, off = 0, SPC.V.MOD.offBy
    for _, m in ipairs((SPC.V.launchers(true))) do
        local a = addrOf(m)
        if not (a and off[a]) and pcall(function()
            m.IsDispRadarMap = true
            m.ForceAlertDisp = true
            m.HUDControl = c.radar_hud or 1
        end) then n = n + 1 end
    end
    return n
end
-- ((0.73.77) D4) and off again: every launcher's (her death, the host's VALKA over on a joiner) or, with owner (an
-- actor's address), only that actor's (her opener railgun's, as it's removed: her own stay on). How many went off.
function SPC.V.radarOff(owner)
    if walkHold and walkHold() then return 0 end           -- (no object walk while a level comes or goes)
    local n = 0
    for _, m in ipairs((SPC.V.launchers(false))) do        -- ((0.73.80) the kept ones: a walk only with no hook)
        local mine = owner == nil
        if not mine and liveObj(m) then
            local o = m
            for _ = 1, 4 do                                   -- (the module's outers up to its actor)
                local okO, out = pcall(function() return o:GetOuter() end)
                if not (okO and liveObj(out)) then break end
                if addrOf(out) == owner then mine = true; break end
                o = out
            end
        end
        if mine and pcall(function() m.IsDispRadarMap = false; m.ForceAlertDisp = false end) then
            n = n + 1
            local a = owner and addrOf(m)
            if a then SPC.V.MOD.offBy[a] = true end         -- ((0.73.80) left off: SPC.V.radar)
        end
    end
    log(string.format("special: VALKA's railgun minimap display off on %d launchers%s", n, owner and " (her opener's)" or ""))
    return n
end
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
-- The opener's light as AC7 Mission 18's lens flash (ms18_LensEffect1: screen-space billboard elements, faded by its
-- alpha curve): a plain actor spawned at `at` with a MaterialBillboardComponent, one element per AC7 texture
-- (MI_SV_ValkaFlare_*, on AC8's own Mission 23 flare). How many elements came up.
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
    -- ((0.73.77) D5: each element's screen share x flash_size_x, [specials.valka]; 1 = AC7's own sizes)
    local kx = tonumber(c.flash_size_x) or 1
    if not (kx > 0 and kx <= 4) then kx = 1 end
    for _, e in ipairs(f.elements) do
        local p = f.path .. e[1]
        local mi, why = SPC.V.asset(p)                  -- ((0.73.80) kept from the break's preload: no load, no find here)
        local size = e[2] * kx
        local okM, mid = false, nil                     -- (not `valid(mi) and pcall(...)`: `and` keeps only pcall's first value)
        if valid(mi) then okM, mid = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, mi, FName("None"), 0) end) end
        if okM and valid(mid) and pcall(function() comp:AddElement(mid, nil, true, size, size, nil) end) then
            local okB, b = pcall(function() return mid:K2_GetScalarParameterValue(FName("Emissive_Intensity")) end)
            fl.mids[#fl.mids + 1] = { mid = mid, base = (okB and type(b) == "number" and b > 0) and b or 1 }
            said[#said + 1] = string.format("%s %.2f (base %.3g)", e[1], size, fl.mids[#fl.mids].base)
        else
            said[#said + 1] = e[1] .. " NOT up (" .. tostring(valid(mi) and mid or why) .. ")"
        end
    end
    s.flare = fl
    SPC.V.flareTick(c, s, now)
    log(string.format("special: VALKA's flare (AC7 M18 lens flash): %d of %d elements, %.0f s, sizes x%.2f (flash_size_x; her "
        .. "shot's burst flash_scale %.1f): %s", #fl.mids, #f.elements, f.life_s, kx, tonumber(c.flash_scale) or 0,
        table.concat(said, ", ")))
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
        -- ((0.73.77, plan F1b) not while the level is torn down, levelTorn: it goes with the level, and valid() reads it)
        if not (levelTorn and levelTorn()) and liveObj(a) then pcall(function() a:K2_DestroyActor() end) end   -- ((0.73.84) liveObj)
        s.flare = nil
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
-- everything of hers that outlives a tick: the charge loop, the flare, the portal (a run restarted or left mid-fight;
-- code review of 2026-10-25: they were only cleared when she was shot down, so the loop played on into the next run)
function SPC.V.cleanup(s)
    if type(s) ~= "table" then return end
    if s.redOn or s.moodOn then SPC.V.moodOff(nil, s) end  -- (0.73.76) never left red or playing (the run over, the level left)
    SPC.V.sndStop(s)
    SPC.V.flareStop(s)
    s.passAt = nil
    if SPC.V.RC.mode then pcall(SPC.V.roundDefaults, CFG.specials.valka, "off") end   -- ((0.73.80) her round's class default back)
end
function SPC.V.sndShot(s, at, now)
    local cs = CFG.sound.valka
    SPC.V.sndStop(s)
    if not at then return end                           -- (no place to fire from: silent, not on you)
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
    if on and downNow() then                            -- ((0.73.77) A10: you're DOWN: left alone, no scramble or callout)
        s.invertUntil = nil
        log(string.format("special: %s's scramble skipped: you're DOWN (SV_Invert not called)", c.name))
        return
    end
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
    if not downNow() then hudCallout(on and t.anomaly_field or t.anomaly_clear, on and s.fxText or nil) end
    log(string.format("special: %s scrambles your controls: %s (SV_Invert %s)", c.name, on and s.fxText or "back",
        tostring(r)))
end
end  -- (sv_anomalies.lua's do block goes on in sv_anomalies_valka.lua)
