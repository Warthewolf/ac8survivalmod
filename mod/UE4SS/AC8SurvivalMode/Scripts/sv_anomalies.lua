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
local function downNow()
    local ok, d = pcall(function() return DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true end)
    return ok and d == true
end
ANOM.downNow = downNow
local function setField(on, s)
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
local function portalFx(list, o, offset, scale, life)
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

-- AB.L..IN's phases (CFG.specials.glitch.phases; behaviour roadmap P7, tools/re/BEHAVIOUR_DIRECTOR.md unit 9): 1 as it
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
-- tools/re/MINIMAP_MARKERS.md 3: LiveElectronicSupportMeasures bJammingEnable / bSupportEnable). Never destroyed (a
-- weapon actor destroyed from Lua crashed the game: sv_ladon.lua). Its pods: BP_wp_ecm_a0 actors whose owner (or
-- instigator) is AB.L..IN; the first time, the log says what each read before and after (and once when none of the
-- pods up is its own: a tester greps "ECM pods off" either way; code review of 2026-10-29).
local function glitchPodsOff(c, s, o)
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
    -- with ordinary ones it draws black. These are AC8's general masters with ordinary samplers and skinned-mesh shaders:
    -- a dynamic instance of one, her colour and normal maps in it (not with `flat_normal`), its own Livemap default
    -- unless `livemap` says otherwise. 9 and 10 have no texture parameters at all (their packages name none): plain
    -- white (test of 2026-10-25). 11 showed her grey paint with odd shading: its Livemap default is black.
    { name = "LIVE BASE", parent = "/Game/Base/Material/MP/MP_Live_Base_CameraDitherFade" },
    { name = "LIVE BASE WPO", parent = "/Game/Base/Material/MP/MP_Live_Base_WPO" },
    { name = "CHARACTER BASE", parent = "/Game/Base/Material/Character/M_Live_Cha_Base" },
    { name = "CHARACTER + WHITE LIVEMAP", parent = "/Game/Base/Material/Character/M_Live_Cha_Base", livemap = "white" },
    { name = "CHARACTER, FLAT NORMAL", parent = "/Game/Base/Material/Character/M_Live_Cha_Base", flat_normal = true },
    { name = "CHARACTER + WHITE LIVEMAP, FLAT NORMAL", parent = "/Game/Base/Material/Character/M_Live_Cha_Base",
      livemap = "white", flat_normal = true },
    -- (0.73.76) the Falken add-on's way (tools/re/FALKEN_MATERIALS.md: an AC7 aircraft whose paint draws in AC8): an
    -- instance of a stock aircraft's GEAR material (MI_*_Gear -> MP_Gear -> M_Live_Vehicle_Base), which samples
    -- ordinary textures and has skinned-mesh shaders, not the virtual-texture skin master (black, rule 44). The x40a's
    -- own gear instance; her colour (and normal) map, the stock neutral Livemap, the base's emissive, turbine, detail and
    -- damage normals off. 15: with her normal map; 16: the Falken's exactly (flat normal, normal strength 0).
    { name = "X-40A GEAR, HER NORMALS", parent = "/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear",
      tex = { Livemap = "rt:0,0.75,1", Detail_Normal = "/Engine/EngineMaterials/DefaultNormal",
              Blend_Dameged_Normalmap = "/Engine/EngineMaterials/DefaultNormal" },
      scalars = { Ctrl_All_Emissive = 0, Turbine_speed = 0, DNormal_Strength = 0, DamegedNormal_Intencity = 0, PlayerPlane_Damage = 0 } },
    { name = "X-40A GEAR, FALKEN'S (FLAT NORMAL)", parent = "/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear",
      flat_normal = true,
      tex = { Livemap = "rt:0,0.75,1", Normalmap = "/Engine/EngineMaterials/DefaultNormal",
              Detail_Normal = "/Engine/EngineMaterials/DefaultNormal", Blend_Dameged_Normalmap = "/Engine/EngineMaterials/DefaultNormal" },
      scalars = { Ctrl_All_Emissive = 0, Turbine_speed = 0, NormalIntencity = 0, DNormal_Strength = 0, DamegedNormal_Intencity = 0,
                  PlayerPlane_Damage = 0 } },
}
-- her own textures, for the `parent` variants
SPC.V.PAINT_OWN = { Basecolor = "/Game/Mods/SurvivalMode/Valka/Textures/T_X02S_Valka_C",
                    Normalmap = "/Game/Mods/SurvivalMode/Valka/Textures/T_X02S_Valka_NO" }
-- the parent values logged once (what a stock skin changes, for the real fix)
SPC.V.PAINT_SAY = { "WeatheringWeight", "Wet_Darkness", "Wet_Range", "AO_amoumt", "MetallicMapWeight",
    "Metallic_Remap_Target_Low", "Metallic_Remap_Target_High", "Roughness_Remap", "Roughness_Contrast", "Ctrl_B_Smoke",
    "Ctrl_G_OilDirt", "Ctrl_R_ColorUnevenness", "B_Color_Weight", "G_Color_Weight", "R_ColorFade_Weight", "NormalIntencity" }
-- ((0.73.80) R30_FINDINGS specials 2 / perf 6: her reveal took ~0.7 s on the host, the X-02S, its sweep and her paint's
-- materials and textures loaded on that tick (LoadAsset_Blocking, after a StaticFindObject scan of every /Game/ path),
-- her opener ~0.74 s with her round's class and her flare's materials) Her assets, kept once loaded: SPC.V.asset(path
-- [, object]) answers the one kept while it's a live object (liveObj), else loads it (loadObject) and keeps it. Nil and
-- why if it can't be loaded. Her paint is still made on her body at her reveal (fresh dynamic instances from these:
-- an instance made in the break could be collected before she shows, and one kept loaded would keep the level's player
-- controller, its outer, alive), so she looks the same.
SPC.V.assets = {}
function SPC.V.asset(path, obj)
    local full = path .. "." .. (obj or path:match("[^/]+$"))
    local o = SPC.V.assets[full]
    if o ~= nil and liveObj(o) then return o end
    SPC.V.assets[full] = nil
    local why
    o, why = loadObject(full)
    if o ~= nil and valid(o) then SPC.V.assets[full] = o; return o end
    return nil, why
end
-- what she loads at her opener and her reveal: { path, object }, each once (her X-02S and its sweep, her paint variant's
-- materials and textures, her railgun's round class, her opener's lens flash, its shot's flash, her blinks' smoke);
-- on a co-op joiner (client) only her X-02S and paint: the rest is the host's (COOP.valkaTick puts the model on its copy)
function SPC.V.preloadList(c, client)
    local V, out, seen = SPC.V, {}, {}
    local function add(path, obj)
        if type(path) ~= "string" or path == "" or path:sub(1, 3) == "rt:" then return end
        local full = path .. "." .. (obj or path:match("[^/]+$"))
        if not seen[full] then seen[full] = true; out[#out + 1] = { path = path, obj = obj } end
    end
    if c.model and c.model ~= "" then
        add(c.model)
        add(c.sweep_anim)
        local pv = V.PAINTS[(((tonumber(c.paint) or 2) - 1) % #V.PAINTS) + 1]
        if pv.parent then
            add(pv.parent)
            for slot, p in pairs(V.PAINT_OWN) do if not (pv.flat_normal and slot == "Normalmap") then add(p) end end
            for _, p in pairs(pv.tex or {}) do add(p) end
        elseif pv.material then add(pv.material)
        elseif pv.stock then add(V.PAINT_STOCK) end
        for _, k in ipairs({ "dirt", "livemap", "basecolor", "normal" }) do if pv[k] then add(V.PAINT_TEX[pv[k]]) end end
    end
    if client then return out end
    if c.eml_weapon and c.eml_weapon ~= "" then add(c.eml_weapon, c.eml_weapon:match("[^/]+$") .. "_C") end
    add(c.flash); add(c.smoke)                          -- (her opener shot's flash, her blinks' smoke: fxAt)
    local f = c.flare
    if type(f) == "table" and f.enabled and type(f.path) == "string" then
        for _, e in ipairs(f.elements or {}) do add(f.path .. e[1]) end
    end
    return out
end
-- Loaded in the break before her round, one a tick, as her sounds are (SND.preloadValka's moments, below: the NEXT
-- announcement, her round's start, the host's VALKA round on a joiner; her lurk drains it too). Each /Game/ asset is
-- kept loaded (pin: GameInstance.ReferencedObjects, as the Anomaly's sounds; an asset's outer is its package, never a
-- level's object). Again any time it's asked (at most every 10 s) for what isn't kept any more.
SPC.V.PRE = { q = nil, at = nil, n = 0, total = 0, ms = 0, worst = 0, worstWhat = nil, failed = 0, wrapped = false }
function SPC.V.preload()
    local c = CFG.specials and CFG.specials.valka
    if type(c) ~= "table" or c.enabled == false then return false end
    local P = SPC.V.PRE
    if P.q then return false end                                  -- (loading)
    local now = os.clock()
    if P.at and now >= P.at and now - P.at < 10 then return false end   -- (asked lately: "rnd" asks often on a joiner)
    P.at = now
    local q = {}
    local okC, client = pcall(function() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end)
    for _, a in ipairs(SPC.V.preloadList(c, okC and client)) do
        local o = SPC.V.assets[a.path .. "." .. (a.obj or a.path:match("[^/]+$"))]
        if not (o ~= nil and liveObj(o)) then q[#q + 1] = a end
    end
    if #q == 0 then return false end
    P.q, P.n, P.total, P.ms, P.worst, P.worstWhat, P.failed = q, 0, #q, 0, 0, nil, 0
    log(string.format("special: VALKA's X-02S, paint, railgun round, flare and flash: %d assets loading, one a tick, before her fight", #q))
    return true
end
function SPC.V.preTick()
    local P = SPC.V.PRE
    local q = P.q
    if not q then return end
    if (levelTorn and levelTorn()) or (walkHold and walkHold()) then return end   -- (not while a level comes or goes)
    local a = table.remove(q, 1)
    if a then
        local what = a.obj or a.path:match("[^/]+$")
        local t0 = os.clock()
        local o, why = SPC.V.asset(a.path, a.obj)
        local ms = (os.clock() - t0) * 1000
        P.ms = P.ms + ms
        if ms > P.worst then P.worst, P.worstWhat = ms, what end
        if o then
            P.n = P.n + 1
            if a.path:sub(1, 6) == "/Game/" and type(pin) == "function" then pcall(pin, o, "VALKA's " .. what) end
        else
            P.failed = P.failed + 1
            log(string.format("special: VALKA's %s not loaded before her fight (%s): loaded when she needs it", what, tostring(why)))
        end
    end
    if #q == 0 then
        P.q = nil
        log(string.format("special: VALKA's assets loaded before her fight: %d of %d, %.0f ms in all, worst %.0f ms (%s)",
            P.n, P.total, P.ms, P.worst, tostring(P.worstWhat)))
    end
end
local function paintTex(k)
    local p = SPC.V.PAINT_TEX[k]
    return p and SPC.V.asset(p)                         -- ((0.73.80) kept: SPC.V.asset)
end
-- (0.73.76) a flat colour as a texture, "rt:R,G,B" (0-1, linear): a 4x4 render target cleared to it, made once a
-- colour (the user's screenshot of 00:22: black blotches on her body; AC8's T_Livemap isn't flat, 111 of its 256 DXT1
-- blocks differ, so its pattern landed on her UVs; the Falken add-on gives its body a flat 4x4 Livemap, 0 / 0.75 / 1:
-- no metal, roughness 0.75, unshadowed). Nil if it can't be made.
SPC.V.flatTex = {}
local function flatTexture(spec)
    local t = SPC.V.flatTex[spec]
    if t ~= nil and liveObj(t) then return t end        -- ((0.73.80) liveObj: kept between her rounds, valid() reads a freed one)
    local r, g, b = spec:match("^rt:([%d%.]+),([%d%.]+),([%d%.]+)$")
    if not r then return nil end
    local krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    if not valid(krl) then return nil end
    local col = { R = tonumber(r), G = tonumber(g), B = tonumber(b), A = 1 }
    local ok, rt = pcall(function() return krl:CreateRenderTarget2D(survivalPC, 4, 4, 2, col, false, false) end)   -- (2: RTF_RGBA8, linear)
    if not (ok and valid(rt)) then log("special: VALKA's paint: a flat texture " .. spec .. " couldn't be made (" .. tostring(rt) .. ")"); return nil end
    pcall(function() krl:ClearRenderTarget2D(survivalPC, rt, col) end)
    SPC.V.flatTex[spec] = rt
    return rt
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
        local parent, why = V.asset(pv.parent)          -- ((0.73.80) kept from the break's preload, as every load below)
        local okM, mid = false, nil                     -- (not `valid(parent) and pcall(...)`: `and` keeps one value)
        if valid(parent) and valid(kml) then
            okM, mid = pcall(function() return kml:CreateDynamicMaterialInstance(survivalPC, parent, FName("None"), 0) end)
        end
        if not (okM and valid(mid)) then
            log(string.format("special: %s's paint %d %s: no instance of %s (%s)", c.name, k, pv.name, pv.parent,
                tostring(valid(parent) and mid or why)))
            return pv.name
        end
        local set = {}
        for slot, path in pairs(V.PAINT_OWN) do
            if not (pv.flat_normal and slot == "Normalmap") then
                local t = V.asset(path)
                local ok = valid(t) and pcall(function() mid:SetTextureParameterValue(FName(slot), t) end)
                set[#set + 1] = slot .. (ok and "" or " NOT set")
            end
        end
        if pv.flat_normal then set[#set + 1] = "its own flat normal" end
        local live = pv.livemap and paintTex(pv.livemap)
        if live then pcall(function() mid:SetTextureParameterValue(FName("Livemap"), live) end) end
        for slot, path in pairs(pv.tex or {}) do        -- (0.73.76) more textures by path (the gear variants), or a flat "rt:R,G,B"
            local t = path:sub(1, 3) == "rt:" and flatTexture(path) or V.asset(path)
            local ok = false
            if valid(t) then ok = pcall(function() mid:SetTextureParameterValue(FName(slot), t) end) end
            set[#set + 1] = slot .. " " .. path:match("[^/]+$") .. (ok and "" or " NOT set")
        end
        for n, v in pairs(pv.scalars or {}) do          -- (0.73.76) scalar values (the gear variants)
            local ok = pcall(function() mid:SetScalarParameterValue(FName(n), v) end)
            set[#set + 1] = string.format("%s %g%s", n, v, ok and "" or " NOT set")
        end
        local n = 0
        for _, i in ipairs(s.paintSlots) do
            if pcall(function() body:SetMaterial(i, mid) end) then n = n + 1 end
        end
        log(string.format("special: %s's paint %d %s: %d slots on %s, %s%s", c.name, k, pv.name, n, pv.parent:match("[^/]+$"),
            table.concat(set, ", "), pv.livemap and (", Livemap " .. pv.livemap .. (live and "" or " NOT loaded")) or ", its own Livemap"))
        return pv.name
    end
    if pv.material then
        local m, why = V.asset(pv.material)
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
        local stock, why = V.asset(V.PAINT_STOCK)
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
    local function load(path) return SPC.V.asset(path) end    -- ((0.73.80) kept from the break's preload: SPC.V.preload)
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
    local want = math.min(c.opener_km * 100000 + closing * (c.charge_s + 1), (c.opener_max_km or 30) * 100000)
    local edge = ZONE.HALF * 0.95                        -- (the zone's edge first: nearer, still on its bearing)
    local function room(dir)
        local d = want
        for _, k in ipairs({ "X", "Y" }) do
            local lim = dir[k] > 0.001 and (ZONE[k] + edge - you[k]) / dir[k] or dir[k] < -0.001 and (ZONE[k] - edge - you[k]) / dir[k]
            if lim then d = math.min(d, math.max(0, lim)) end
        end
        return d
    end
    local d = room(f)
    if d < want * 0.5 then                               -- (near the zone's edge that way: code review of 2026-10-25,
        local best, bestD = f, d                        -- it spawned ~1 km from you) the bearing with the most room
        for deg = 0, 315, 45 do
            local g = { X = math.sin(math.rad(deg)), Y = -math.cos(math.rad(deg)) }
            local gd = room(g)
            if gd > bestD then best, bestD = g, gd end
        end
        if best ~= f then
            log(string.format("special: %s's opener: only %.1f km of room on its bearing; one with %.1f km instead", c.name,
                d / 100000, bestD / 100000))
        end
        f, d = best, bestD
        h = math.deg(math.atan(f.Y, f.X))
    end
    local at = { X = you.X + f.X * d, Y = you.Y + f.Y * d, Z = math.max(you.Z, c.opener_min_alt_m * 100) }
    local yaw = (h + 180) % 360
    SPC.V.emlActor = nil
    SPC.V.modMark(c.eml_unit)
    spawningUnit = c.eml_unit
    local r = SV_Spawn(c.eml_unit, at.X, at.Y, at.Z, yaw)
    spawningUnit = nil
    SPC.V.modRecord()                                   -- ((0.73.80) its modules kept as they're made, not walked for)
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
    SPC.V.modReset()                                    -- ((0.73.80) this round's railgun modules kept afresh)
    pcall(SPC.V.preload)                                -- ((0.73.80) her assets, if the break didn't load them: her lurk does)
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
    -- ((0.73.80) her railgun round's class default: her damage back before her own railguns are made, life and single
    -- rounds as the opener's; her railguns' modules kept as they're made. (review of 0.73.80) With an opener (at), not
    -- yet: its round may be made after the railgun's spin-up, past her reveal; valkaTick puts it back at s.harmUntil)
    if not at then pcall(SPC.V.roundDefaults, c, "hers") end
    SPC.V.modMark(c.unit)
    spawningUnit = c.unit
    local r = SV_Spawn(c.unit, x, y, z, heading)
    spawningUnit = nil
    SPC.V.modRecord()
    log(string.format("special: VALKA as %s (%s set), %s, heading %.0f, %.1f km up: %s", row, tostring(set),
        pd and string.format("%.1f km from you", pd) or "at a spawn point", heading or -1, z / 100000,
        r > 0 and (r .. " aircraft up") or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r <= 0 then return false end
    D.flightTier = D.flightTier or {}
    D.up[c.unit], D.flown[c.unit], D.flightTier[c.unit] = true, true, #CFG.tiers.list
    D.special.state, D.special.at = "fired", now
    return true
end

-- (0.73.76) Her round's mood, once: the screen fading to red (hudRed) and the song (SND.songStart, CFG.specials.valka.
-- song) together, as the round's flying enemies are all down (user, 2026-11-02: "make sure that the red begins to fade
-- after the enemies that fly in the round are dead"); both fade out after her death (moodOff).
function SPC.V.mood(c, s)
    if s.moodOn then return end
    s.moodOn = true
    -- (0.73.76) every joiner's too; (0.73.77, plan D1) told first, and this game's sky in a pcall: an error there left
    -- moodOn set and the joiners never told (sv_coop.lua's M.valkaWatch holds them to moodOn as well)
    if COOP and COOP.valkaMood then pcall(COOP.valkaMood, true) end
    if c.red and c.red.enabled ~= false then s.redOn = true; pcall(hudRed, true, c.red) end
    pcall(SND.songStart, c.song)
end
function SPC.V.moodOff(c, s, now)
    if s.moodOn and COOP and COOP.valkaMood then pcall(COOP.valkaMood, false) end   -- (0.73.76) every joiner's too ((0.73.77) first)
    if s.redOn then s.redOn = false; pcall(hudRed, false, nil, c == nil) end        -- (a cleanup: the sky back at once)
    if c then pcall(SND.songFade, c.song and c.song.out_s or 5) else pcall(SND.songStop) end
    s.moodOn = false
end

-- Every tick of VALKA's round.
function SPC.valkaTick(now, s)
    local c, t, V = CFG.specials.valka, CFG.hud.text, SPC.V
    V.flareTick(c, s, now)
    -- ((0.73.80) no walk for her rounds after a shot any more (every tick for 3-3.5 s, none ever found in the 31-round
    -- run): their life, single rounds and the opener's no-damage are on the round's class default, SPC.V.roundDefaults)
    if s.alertOffAt and now >= s.alertOffAt then        -- the railgun alert off again after a shot
        s.alertOffAt = nil
        if not s.chargeAt then V.event("RE_SV_ValkaAlertOff") end
    end
    if s.harmUntil and now >= s.harmUntil then          -- ((review of 0.73.80) the opener's round flown: her damage back
        s.harmUntil = nil                               -- (not once she's done: "off" ran then, and stays)
        if s.state ~= "done" then pcall(V.roundDefaults, c, "hers"); pcall(V.roundsHarm, c) end
    end
    if s.passAt and now >= s.passAt then                -- her round passing you (its sound)
        s.passAt = nil
        SND.event(CFG.sound.valka.pass, nil)
    end
    if s.emlRemoveAt and now >= s.emlRemoveAt then      -- her railgun's gone eml_remove_s after its shot
        s.emlRemoveAt = nil
        V.event("RE_SV_ValkaEmlRemove")
        -- ((0.73.77) D4: that event's LiveDestroyUnitExecution never took it down (invincible from setGone: "1 of 1
        -- aircraft alive" to the end of every run, its box on, firing at players near the base): its minimap display
        -- off, then finished off by Lua, SV_UnitAlive asked 2 s on: `special: VALKA's opener railgun removed` / NOT)
        if liveObj(V.emlActor) then pcall(V.radarOff, addrOf(V.emlActor)) end
        if SPC.cleanUp then
            local okC, errC = pcall(SPC.cleanUp, { c.eml_unit }, string.format("%.0f s after its shot", c.eml_remove_s or 4), true, now)
            if not okC then log("special: VALKA's opener railgun: clean-up error " .. tostring(errC)) end
        end
        V.emlActor = nil
    end
    if s.state == "lurk" then                           -- the decoys first: lurk_s after the last is down, the opener
        if not V.PRE.wrapped then pcall(V.preTick) end  -- ((0.73.80) her assets, one a tick, if SND.tick doesn't load them)
        if D.state ~= "fighting" then return end
        if c.disguise then
            for u in pairs(D.up) do if SV_UnitAlive(u) > 0 then s.clearAt = nil; return end end
            s.clearAt = s.clearAt or now + c.lurk_s
        end
        V.mood(c, s)                                    -- (0.73.76) the flyers down (or none): red and her song
        if now < (s.clearAt or now) then return end
        s.emlAt, s.emlYaw = V.emlSpawn(c)
        if not s.emlAt then                             -- no railgun: she comes as she is, the reveal without the shot
            log(string.format("special: %s's railgun couldn't spawn; she comes without the opener", c.name))
            V.event("RE_SV_ValkaWarnOn")
            if not SPC.valkaArrive(now) then
                s.state = "done"
                V.event("RE_SV_ValkaEnd")               -- (the WARNING off)
                pcall(V.roundDefaults, c, "off")         -- ((0.73.80) her round class as it was)
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
            V.modSaid(c, c.eml_unit, "her opener's")   -- ((0.73.80) kept as the game made them: no walk)
            local n, why = V.singleShot(c)
            log(string.format("special: %s's railguns single-shot: %d launcher modules%s", c.name, n, why and (" (" .. why .. ")") or ""))
            pcall(V.roundDefaults, c, "opener")          -- ((0.73.80) her round's life, single rounds, no damage: its class default)
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
        if now < s.chargeAt then return end
        V.singleShot(c)                                 -- (in case its module came late; (0.73.80) the kept ones: no walk)
        V.emlWeapon(c)
        V.radar(c)
        V.event("RE_SV_ValkaEmlShot")
        V.event("RE_SV_ValkaEmlChargeOff")
        V.sndShot(s, s.emlAt, now)
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
        -- ((review of 0.73.80) the opener's no-damage held until its round has been made (the railgun's spin-up, 3 s) and
        -- has flown its life; her first shot comes railgun_every_s after her reveal, later)
        s.harmUntil = now + c.reveal_s + 3 + (tonumber(c.eml_life_s) or 8)
        return
    end
    if s.state == "shot" then                           -- reveal_s after the shot she's there, where it came from
        if now < s.revealAt then return end
        if not SPC.valkaArrive(now, s.emlAt, s.emlYaw) then
            s.state = "done"
            V.event("RE_SV_ValkaEnd")                   -- (the WARNING off)
            pcall(V.roundDefaults, c, "off")             -- ((0.73.80) her round class as it was)
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
        if COOP and COOP.valkaReveal then pcall(COOP.valkaReveal, c.unit) end   -- (0.73.76) on every joiner's copy too
        V.modSaid(c, c.unit, "her")                     -- ((0.73.80) her railguns' modules kept as the game made them)
        s.singleN = V.singleShot(c)                     -- her own railguns ((0.73.76) always: the opener's set it to 1 first,
        log(string.format("special: %s's own railguns single-shot: %d launcher modules", c.name, s.singleN or 0))  -- so hers kept their bursts)
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
    -- ((0.73.77) liveObj, not valid(): the clean-up may take her unit off the native list while the wreck falls)
    if s.state == "done" and s.wreckUntil and now < s.wreckUntil and liveObj(s.modelOwner) then
        V.modelHide(s, s.modelOwner)                    -- her X-02S falls, not the x40a's wreck
        return
    end
    if s.state ~= "hunt" then return end
    V.mood(c, s)                                        -- (0.73.76) red and her song, if her round had no lurk
    s.railAt, s.turnAt = s.railAt or now + c.railgun_every_s, s.turnAt or now + c.turn_every_s   -- (no opener: no reveal)
    s.psAt, s.invertAt = s.psAt or now + c.post_stall_every_s, s.invertAt or now + c.invert_every_s
    if SV_UnitAlive(c.unit) <= 0 then
        s.state = "done"
        V.moodOff(c, s, now)                            -- (0.73.76) the red and her song fade away after she dies
        if s.modelComp then s.wreckUntil = now + (c.wreck_s or 15) end
        V.event("RE_SV_ValkaEnd")                       -- the WARNING off (as SV_ValkaDown, in case it's missed)
        if s.invertUntil then V.invert(c, s, false, now) end
        if s.chargeAt then V.event("RE_SV_ValkaChargeOff") end
        V.event("RE_SV_ValkaAlertOff")
        V.flareStop(s)
        V.sndStop(s)
        ANOM.cleanFx(now, true)
        -- ((0.73.77) D4 / the white square left on the minimap: her railguns' forced minimap display off, and what's
        -- left of her unit (the x40a's parts, invincible while her X-02S flew: partsGone; RailGunCK, Mission 26's sure kill,
        -- hit dukka two VALKA rounds on) and of her opener's taken down at once, not after the wreck's fall; the round's
        -- clean-up (sv_rounds.lua SPC.endTick) looks again then)
        pcall(V.radarOff)
        pcall(V.roundDefaults, c, "off")                 -- ((0.73.80) her railgun round's class default as it was)
        log(string.format("special: %s's railgun modules this round: %d walks for them (0.73.80: 0 when the game's making of "
            .. "them was kept), %d launchers kept", c.name, V.MOD.walks or 0, #V.keptLaunchers()))
        if SPC.cleanUp then
            local okC, nC = pcall(SPC.cleanUp, { c.unit, c.eml_unit }, "her death", true, now)
            log(string.format("special: %s down: %s of her unit's objects still up, taken off", c.name,
                okC and tostring(nC) or ("? (error " .. tostring(nC) .. ")")))
        end
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, c.name .. " down")
        LB.special("valka", true, now - s.at)
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, specialPay(pay)))   -- ((0.73.78) C3)
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
    if s.invertUntil and (now >= s.invertUntil or downNow()) then V.invert(c, s, false, now) end   -- ((0.73.77) A10: DOWN)
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
        V.singleShot(c)                                 -- (0.73.76) every launcher single-shot right before each shot (no bursts)
        V.event("RE_SV_ValkaRailgun")
        V.event("RE_SV_ValkaChargeOff")
        V.sndShot(s, at, now)
        s.chargeAt, s.shots, s.railAt = nil, (s.shots or 0) + 1, now + c.railgun_every_s
        s.alertOffAt = now + (c.alert_off_s or 3)
        log(string.format("special: %s railgun shot %d, %.1f km from you, %.0f deg off her nose", c.name, s.shots,
            s.dist or -1, offNose or -1))
    elseif not s.chargeAt and now >= s.railAt and s.dist and s.dist <= c.railgun_range_km and offNose
        and offNose <= c.railgun_cone_deg then
        s.chargeAt = now + c.railgun_charge_s
        V.event("RE_SV_ValkaChargeOn")
        V.event("RE_SV_ValkaAlertOn")
        -- ((review of 0.73.80) her damage on the class default (if the opener's hold hasn't run out: it can't be left on)
        -- and on the rounds pooled from the opener's shot, before this one's made)
        if s.harmUntil then s.harmUntil = nil; pcall(V.roundDefaults, c, "hers") end
        pcall(V.roundsHarm, c)
        -- ((0.73.80) the kept launchers, no walk; no rounds to put their damage back on: the opener's no-damage was
        -- taken off her round's class default before she spawned)
        V.radar(c)
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

-- ((0.73.80) her assets loaded with her sounds (sv_sound.lua, a part before this one): SND.preloadValka, asked in the
-- break before her round (the NEXT announcement, her round's start; a joiner on the host's VALKA round), queues them too,
-- and SND.tick, every tick, loads one; her lurk does when this couldn't be put in)
if type(SND) == "table" and type(SND.preloadValka) == "function" and type(SND.tick) == "function" then
    local sndPreload, sndTick = SND.preloadValka, SND.tick
    function SND.preloadValka(...)
        local okV, errV = pcall(SPC.V.preload)
        if not okV then logOnce("valka preload", "special: VALKA's preload error " .. tostring(errV)) end
        return sndPreload(...)
    end
    function SND.tick(...)
        local okV, errV = pcall(SPC.V.preTick)
        if not okV then logOnce("valka preload tick", "special: VALKA's preload error " .. tostring(errV)) end
        return sndTick(...)
    end
    SPC.V.PRE.wrapped = true
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
    -- (ready() whether it can come now, else a normal round; busy(s) holds the round's end, over(now, s) at its end,
    -- row(s, t) its NEXT row: sv_spaceport.lua)
    spaceport  = { sub = "spaceport_sub", ready = function() return SPORT.ready() end,
                   budget = function(budget)
                       return math.floor(budget * (CFG.specials.spaceport.fighter_share or 0.5) / 2 + 0.5) * 2
                   end,
                   spawn = function(now) return SPORT.spawn(now) end, tick = function(now, s) return SPORT.tick(now, s) end,
                   busy = function(s) return SPORT.busy(s) end, over = function(now, s) return SPORT.roundOver(now, s) end,
                   row = function(s, t) return SPORT.row(s, t) end },
    retake     = { sub = "retake_sub",
                   ready = function()                    -- (forced too: none with the Spaceport or its retake off)
                       local c = CFG.specials.spaceport
                       return not (c.enabled == false or (c.retake and c.retake.enabled == false))
                   end,
                   budget = function(budget)
                       local r = CFG.specials.spaceport.retake or {}   -- (extra_aircraft: more fighters, 2026-10-31)
                       return math.floor((budget * (r.fighter_share or 0.6) + (r.extra_aircraft or 0)) / 2 + 0.5) * 2
                   end,
                   spawn = function(now) return SPORT.retakeSpawn(now) end,
                   tick = function(now, s) return SPORT.retakeTick(now, s) end,
                   busy = function(s) return SPORT.retakeBusy(s) end, over = function(now, s) return SPORT.retakeOver(now, s) end,
                   row = function(s, t) return SPORT.row(s, t) end },
    ladon      = { sub = "ladon_sub", alone = true, aircraft = 2, spawn = function(now) return SPC.ladonSpawn(now) end,
                   tick = function(now, s) return SPC.ladonTick(now, s) end },
    alicorn    = { sub = "alicorn_sub", alone = true, aircraft = 1, spawn = function(now) return SPC.alicornSpawn(now) end,
                   tick = function(now, s) return SPC.alicornTick(now, s) end },
    glitch     = { sub = "glitch_sub", alone = true, aircraft = 1, spawn = function(now) return ANOM.glitchSpawn(now) end,
                   tick = function(now, s) return ANOM.glitchTick(now, s) end },
    -- (disguise: a normal round's callout and budget(budget) decoy fighters, VALKA after them: CFG.specials.valka)
    -- ((0.74.0) not from GONE FISHIN' until the festival's over and the arc's sky is back at midday: sv_sky.lua
    -- SKY.arcHoldsValka; the host's decision; her test key still forces her)
    valka      = { sub = "valka_sub", disguise = function() return CFG.specials.valka.disguise end,
                   ready = function(round, forced)
                       if forced or not (SKY and SKY.arcHoldsValka) then return true end
                       return not SKY.arcHoldsValka(round)
                   end,
                   alone = function() return not CFG.specials.valka.disguise end,
                   budget = function(budget)
                       local c = CFG.specials.valka
                       if not c.disguise then return 0 end
                       local n = math.floor(budget * c.decoy_share / 2 + 0.5) * 2         -- (whole 2-ships)
                       return math.max(c.decoy_min, math.min(c.decoy_max, n, budget))
                   end,
                   spawn = function(now) return SPC.valkaSpawn(now) end,
                   tick = function(now, s) return SPC.valkaTick(now, s) end },
    -- ((0.74.0) GONE FISHIN' and THE FESTIVAL, sv_fishing.lua / sv_festival.lua: no fighters of their own)
    fishing    = { sub = "fishing_sub", alone = true, aircraft = 0,
                   ready = function(round, forced) return FISH.ready(round, forced) end,
                   spawn = function(now) return FISH.roundSpawn(now) end, tick = function(now, s) return FISH.roundTick(now, s) end,
                   busy = function(s) return FISH.busy(s) end, over = function(now, s) return FISH.roundOver(now, s) end,
                   row = function(s, t) return FISH.row(s, t) end },
    festival   = { sub = "festival_sub", alone = true, aircraft = 12,
                   ready = function(round, forced) return FEST.ready(round, forced) end,
                   spawn = function(now) return FEST.roundSpawn(now) end, tick = function(now, s) return FEST.roundTick(now, s) end,
                   busy = function(s) return FEST.busy(s) end, over = function(now, s) return FEST.roundOver(now, s) end,
                   row = function(s, t) return FEST.row(s, t) end },
}
-- a kind's field that may be a function (alone, aircraft, sub)
function SPC.kindValue(v, ...) if type(v) == "function" then return v(...) end return v end

-- PHANTASM's pack (CFG.specials.anomaly.pack; behaviour roadmap P7, tools/re/BEHAVIOUR_DIRECTOR.md unit 9): the guards
-- spring while the field scrambles you, spring_delay_s after it comes on (the tell "pack" first: an ambush call and THE
-- PACK SPRINGS), then are called back round MINDRIPPER once you've been out of the field hold_after_s, at least min_s
-- after the spring, cooldown_s before the next. Two remote events (tools/survival_events.py build_anomaly):
-- RE_SV_AnomalyPackSpring (you only, anywhere, the campaign aces' LastTGT onto you by unit) and RE_SV_AnomalyPackHold
-- (their appearance's orders: you only near it, their area on it). The host's (or solo): its field (ANOM.on) springs it,
-- the LastTGT steers to the host's plane, so both are kept there (sv_coop.lua KEEP_EVENTS ^RE_SV_AnomalyPack); a
-- joiner's own field never springs it. After MINDRIPPER is down nothing: its down records loose the guards anyway.
-- s.pack: nil (held), "armed" (the tell said, the spring due at s.packAt) or "sprung" (since s.packSince).
function ANOM.packTick(now, s, c)
    local pk = c.pack
    if not (pk and pk.enabled and s and s.state == "hunt") or type(SV_Event) ~= "function" then return end
    if ANOM.on == true then s.fieldOffAt = nil elseif not s.fieldOffAt then s.fieldOffAt = now end
    if SV_UnitAlive(c.guard_unit) <= 0 then                 -- (no guard left: nothing to spring or call back)
        if s.pack and not s.packGoneSaid then
            s.packGoneSaid = true
            log(string.format("special: %s's pack: every guard down (%d springs)", c.name, s.packSprings or 0))
        end
        s.pack = nil
        return
    end
    local function fire(ev)
        local r = SV_Event(ev)
        if r ~= 1 then log(string.format("special: %s not fired: %s", ev, SV_ERR and SV_ERR[r] or tostring(r))) end
        return r == 1
    end
    if s.pack == nil then
        if ANOM.on == true and now >= (s.packCool or 0) then
            s.pack, s.packAt = "armed", now + (tonumber(pk.spring_delay_s) or 0)
            -- (this game's player: the host's, as the spring; a sure tell: through its gap and cooldown)
            local how = "not told (no tells)"
            if TELL then
                local okT, r, why = pcall(TELL.say, "pack")
                if okT and r == true then how = "told"
                else how = "not told: " .. tostring(okT and why or r) end
            end
            log(string.format("special: %s's pack: your controls scrambled %.1f km from it; %s springs in %.1f s (%s)",
                c.name, s.dist or -1, c.guards_name, s.packAt - now, how))
        end
    elseif s.pack == "armed" then
        if ANOM.on ~= true then                                  -- (out of the field before it sprang: held)
            s.pack = nil
            log(string.format("special: %s's pack: you left the field first; not sprung", c.name))
        elseif now >= s.packAt then
            if fire("RE_SV_AnomalyPackSpring") then
                s.pack, s.packSince, s.packSprings = "sprung", now, (s.packSprings or 0) + 1
                log(string.format("special: %s's pack sprung (%d): %s loose on you (LastTGT), %d of %d guards up, %.1f km from %s",
                    c.name, s.packSprings, c.guards_name, SV_UnitAlive(c.guard_unit), c.guards or 4, s.dist or -1, c.name))
            else                                                 -- (its event didn't fire: held, cooldown_s to the next)
                s.pack, s.packCool = nil, now + (tonumber(pk.cooldown_s) or 0)
                log(string.format("special: %s's pack not sprung (its event not fired); armed again in %.0f s", c.name,
                    s.packCool - now))
            end
        end
    elseif s.pack == "sprung" and ANOM.on ~= true and now - (s.packSince or now) >= (tonumber(pk.min_s) or 0)
        and s.fieldOffAt and now - s.fieldOffAt >= (tonumber(pk.hold_after_s) or 0) then
        fire("RE_SV_AnomalyPackHold")
        s.pack, s.packCool = nil, now + (tonumber(pk.cooldown_s) or 0)
        log(string.format("special: %s's pack held: back round %s %.0f s after it sprang (%.0f s out of the field)",
            c.name, c.name, now - s.packSince, now - s.fieldOffAt))
    end
end

-- A guard of the Anomaly whose hunt waits for its pack (pack.hunt_only_sprung: ACE.hunt keeps a top-tier plane's target
-- on you; held, it guards MINDRIPPER instead). False with it off, on a co-op joiner (no D.special there) and after
-- MINDRIPPER's round.
function ANOM.packHeld(p)
    local c = CFG.specials.anomaly
    local pk = c and c.pack
    if not (pk and pk.enabled and pk.hunt_only_sprung and p and p.unit == c.guard_unit) then return false end
    local s = D and D.special
    return s ~= nil and s.kind == "anomaly" and s.state == "hunt" and s.pack ~= "sprung"
end

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
        hudCallout(string.format(t.anomaly_down, c.name:upper()), string.format(t.anomaly_down_sub, specialPay(pay)))   -- ((0.73.78) C3)
        log(string.format("special: round %d, %s shot down %.0f s after it appeared (its pack sprang %d times)", D.round,
            c.name, now - s.at, s.packSprings or 0))
        return
    end
    local p
    for _, q in ipairs(planes) do if q.unit == c.unit and valid(q.obj) then p = q end end
    if p and not s.healthDone then                 -- its health for its round (economy review of 2026-10-25)
        s.healthDone = true
        local hx = math.min(c.health_max_x or 1, 1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first))
        local h0, h1 = scaleHealth(p.obj, hx)
        log(string.format("special: %s's health x%.2f for round %d (%s -> %s)", c.name, hx, D.round, tostring(h0), tostring(h1)))
    end
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
    if downNow() then                                                  -- ((0.73.77) A10: none on you while you're DOWN)
        if ANOM.on then setField(false, nil); log("special: anomaly field off: you're DOWN")
        elseif s.dist < c.field_km then setField(true, s) end         -- (setField holds it off: logged once)
    elseif ANOM.on ~= true and s.dist < c.field_km then setField(true, s)
    elseif ANOM.on ~= false and s.dist > c.field_km + 0.3 then setField(false, s) end      -- (0.3 km: no flicker)
    local okP, errP = pcall(ANOM.packTick, now, s, c)                                       -- (its pack: P7)
    if not okP and tostring(errP) ~= s.packErr then s.packErr = tostring(errP); log("special: pack error " .. s.packErr) end
end

-- A Survival COOP joiner's own field (sv_coop.lua clientRounds; code review of 2026-10-26: the host's field events
-- switched every joiner's field on the host's distance): the joiner runs no rounds, so its distance to its copy of the
-- Anomaly decides it here, as ANOM.tick does for the host. Off once the copy is gone.
-- (0.73.77) The user, 2026-11-03: "After shooting down Mindripper, the field ... lingered for other players but not me ...
-- still getting his controls reversed in much further rounds when flying near where we shot Mindripper down": any copy
-- of its unit that was still a valid object counted, a wreck or a copy left up by the copy desync (plan A1) too, so its
-- crash site scrambled that joiner for the rest of the run (the host runs its own state, so never had it). Now only
-- while the host's round has the Anomaly up (sv_coop.lua "rnd" field 11: D.hostSpecial, its kind and state) and only a
-- live copy (not down, health above 0), off at once when the host's is over; never on a joiner who's DOWN (A10).
local function liveCopy(unit)
    local p
    for _, q in ipairs(planes) do
        if q.unit == unit and not q.down and liveObj(q.obj) then
            local okH, h = pcall(function() return q.obj.HealthInternal end)
            if okH and type(h) == "number" and h > 0 then p = q end
        end
    end
    return p
end
ANOM.liveCopy = liveCopy
function ANOM.clientTick()
    local c = CFG.specials.anomaly
    local hs = D and D.hostSpecial
    if not (hs and hs.kind == "anomaly" and hs.state == "hunt") then
        if ANOM.on then
            setField(false, nil)
            log("coop: the Anomaly is over on the host: its field off here")
        end
        return
    end
    if downNow() then
        if ANOM.on then setField(false, nil); log("special: anomaly field off: you're DOWN") end
        return
    end
    local p = liveCopy(c.unit)
    local you = playerLocation()
    if not (p and you) then
        if ANOM.on then setField(false, nil) end
        return
    end
    local ok, l = pcall(function() local v = p.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if not ok then return end
    local s = { state = "hunt", dist = km(l, you) }
    local pawn = valid(survivalPC) and survivalPC.Pawn
    local a = pawn and addrOf(pawn)
    if a and a ~= ANOM.pawn then ANOM.pawn = a; if ANOM.on then ANOM.on = nil end end
    if ANOM.on ~= true and s.dist < c.field_km then setField(true, s)
    elseif ANOM.on ~= false and s.dist > c.field_km + 0.3 then setField(false, s) end
end

-- A Survival COOP joiner's copy of AB.L..IN in its phase 3 (code review of unit 9: the host switched its own plane's
-- pods off while the joiner's copy, its own pod row firing, jammed on after "it's not jamming anymore"): the host's phase comes
-- in "rnd" (sv_coop.lua: D.glitchPhase), and the copy's pods are switched off here every ecm_check_s, as glitchPodsOff
-- does on the host. Nothing before phase 3, with the phases or ecm_pods_off off, or with no copy up.
function ANOM.clientGlitch(now)
    local c = CFG.specials.glitch
    local ph = c and c.phases
    if not (type(ph) == "table" and ph.enabled and ph.ecm_pods_off and D and D.glitchPhase == 3) then
        ANOM.glitchCopy = nil
        return
    end
    local cs = ANOM.glitchCopy
    if not cs then
        cs = {}
        ANOM.glitchCopy = cs
        log(string.format("coop: %s in its phase 3 on the host: its copy's ECM pods switched off here every %.0f s", c.name,
            math.max(1, tonumber(ph.ecm_check_s) or 3)))
    end
    if now < (cs.podsAt or 0) then return end
    cs.podsAt = now + math.max(1, tonumber(ph.ecm_check_s) or 3)
    local p = liveCopy(c.unit)                         -- ((0.73.77) a live copy only: not a wreck, health above 0)
    local o = p and p.obj
    if o then pcall(glitchPodsOff, c, cs, o) end
end
end

-- TEST ONLY BEGIN (the lightning Anomaly and the storm test: test builds only; tools/strip_test_only.py takes all of it
-- out of a release with CFG.specials.thunder; tools/re/THUNDER.md)
-- IFF FATAL ERROR / DI..ANT TH..D..R (user, 2026-11-06: "another Anomaly, one that uses Lightning Against you", "The
-- Aircraft is an A-10", "Strikes should only black out and disorient you", "it can only be spawned with the test key"):
-- the special kind "thunder", never in CFG.specials.rotation, brought only by Ctrl+. (the next round, as Ctrl+1-8 do).
-- Its A-10 is the plain campaign row (CFG.specials.thunder.row, a10c_common = OP1001_a10c_01: never the named A-10's
-- NLID_0400_CP set, hard rule 22) set on MINDRIPPER's own unit SV_Unit_Anomaly (SV_SetAircraft, as MINDRIPPER's F-4E is:
-- the unit is one aircraft built for a boss, its behaviour Survival's fighters' set (hard rule 20), and its stock records
-- give it the pool's orders, the MISSION UPDATE beep, the forced WARNING, the attack throttle and the Celaeno crackle at
-- its appearance, and its death sounds; so no build data). Its storm is the game's own lightning volume
-- (BP_LightninigVolume_MS12, Missions 12 and 16's: build/research/lightning/LIGHTNING.md), spawned at run time and kept
-- on it every tick: the stock observer rolls strikes on the player planes inside it (the HUD hidden 2 s, electronic noise
-- 6-10 s, a camera shake, the engine's stall flag; never damage, never an AI plane). Co-op: the host spawns it (its spawn
-- mirrored as every flight's); each game keeps a storm on its own copy of it and rolls its own strikes, nothing synced.
-- Ctrl+,: the storm test (LIGHTNING.md 7): the storm on you for test.seconds, its strikes and your health in the log;
-- pressed again, your plane's LS_StallTime to test.stall_s; a third time, off.
-- A storm is never destroyed with anything inside it: the observer reads the first storm a plane entered through a weak
-- pointer and doesn't check it (0x147ed60c0: a destroyed one would be read at NULL + 0x340), so a storm being taken off
-- shrinks to 1 cm, and is destroyed once its InsideGameObjects has been empty twice (else it stays, parked).
THUNDER = { storm = nil, parked = {}, fx = {}, test = nil, named = {}, hook = { n = 0, ends = 0 }, said = {} }
do
local function cfg() return CFG.specials.thunder end
local STRIKE_GAP_S, FOLLOW_S, PARK_RADIUS, PARK_SAY_S = 1.5, 3.5, 1.0, 30
local function say(key, s) if not THUNDER.said[key] then THUNDER.said[key] = true; log(s) end end
local function torn() return (levelTorn and levelTorn()) or (levelGoing and levelGoing()) or false end
local function joiner() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function num(o, f)
    local ok, v = pcall(function() return o[f] end)
    return (ok and type(v) == "number") and v or nil
end
local function str(v)                                   -- (an FString / FName read: a Lua string)
    if type(v) == "string" then return v end
    if v == nil then return "nil" end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" then return s end
    return tostring(v)
end
local function field(o, f)
    local ok, v = pcall(function() return o[f] end)
    return ok and str(v) or "?"
end
local function fmt(v, f) return type(v) == "number" and string.format(f or "%.2f", v) or "?" end
local function where(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function myPlane()
    if not liveObj(survivalPC) then return nil end
    local ok, p = pcall(function() return survivalPC.Pawn end)
    if ok and p ~= nil and liveObj(p) then return p end
    return nil
end
local function motion(p)                                 -- km/h and pitch (degrees), or nil
    if not p then return nil, nil end
    local okV, v = pcall(function() local x = p:GetVelocity(); return { X = x.X, Y = x.Y, Z = x.Z } end)
    local okR, r = pcall(function() return p:K2_GetActorRotation().Pitch end)
    local kmh = okV and v and math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) * 0.036 or nil
    return kmh, okR and type(r) == "number" and r or nil
end

-- (the specials' clean-up, sv_rounds.lua, a part after this one: its units and log label for "thunder", installed at the
-- first tick of a run, its key or its spawn)
local function install()
    if THUNDER.installed or type(SPC.cleanUnitsOf) ~= "function" or type(SPC.cleanLabel) ~= "function" then return end
    THUNDER.installed = true
    local units, label = SPC.cleanUnitsOf, SPC.cleanLabel
    function SPC.cleanUnitsOf(kind)
        if kind == "thunder" then
            local u = cfg().unit
            return (type(u) == "string" and u ~= "") and { u } or {}
        end
        return units(kind)
    end
    function SPC.cleanLabel(unit)
        local c = cfg()
        if unit == c.unit and THUNDER.lastSeen and os.clock() - THUNDER.lastSeen < 120 then return c.name .. "'s unit (" .. unit .. ")" end
        return label(unit)
    end
end
THUNDER.install = install
-- its strikes in the log: the HUD's own lightning calls (UFUNCTIONs; the strike calls them from C++, so a hook may never
-- see one: the log says), hooked once
local function hookHud()
    if THUNDER.hooked ~= nil then return THUNDER.hooked end
    THUNDER.hooked = false
    if type(RegisterHook) ~= "function" then log("thunder: no RegisterHook: the HUD's lightning calls aren't watched"); return false end
    local h = THUNDER.hook
    local okB, errB = pcall(RegisterHook, "/Script/Live.LiveHUD:BeginHUDDistortionLightning", function(_, t)
        h.n, h.at = h.n + 1, os.clock()
        local okT, v = pcall(function() return t:get() end)
        h.recover = okT and v or nil
    end)
    local okE, errE = pcall(RegisterHook, "/Script/Live.LiveHUD:EndHUDDistortionLightning", function()
        h.ends, h.endAt = h.ends + 1, os.clock()
    end)
    THUNDER.hooked = okB or okE
    log(string.format("thunder: the HUD's BeginHUDDistortionLightning %s, EndHUDDistortionLightning %s (a strike calls them from "
        .. "C++: a hook sees only calls through ProcessEvent)", okB and "hooked" or ("NOT hooked: " .. tostring(errB)),
        okE and "hooked" or ("NOT hooked: " .. tostring(errE))))
    return THUNDER.hooked
end

---------------------------------------------------------------------------------------------------- the storm
local function stormClass()
    local c = cfg().storm
    if THUNDER.cls ~= nil and liveObj(THUNDER.cls) then return THUNDER.cls end
    local o, why = loadObject(c.class)
    THUNDER.cls = o
    return o, why
end
-- (the volume's strike chance curves, CUR_LightningWeight: the game instance's soft reference; loaded and kept, so the
-- observer finds MS_12, else it falls back on count % a roll)
local function curveTable()
    if THUNDER.curves ~= nil then return THUNDER.curves end
    local o, why = loadObject(cfg().storm.curve_table)
    THUNDER.curves = o ~= nil and valid(o) or false
    if o ~= nil and valid(o) then pcall(pin, o, "CUR_LightningWeight") end
    log("thunder: the strike chance curves (CUR_LightningWeight) " .. (THUNDER.curves and "loaded" or ("NOT loaded: " .. tostring(why))))
    return THUNDER.curves
end
local function shakeMgr(st)
    if THUNDER.mgr ~= nil and liveObj(THUNDER.mgr) then return THUNDER.mgr end    -- (kept between storms while it's live)
    THUNDER.mgr = nil
    if os.clock() < (st.mgrAt or 0) or (st.mgrTries or 0) >= 3 then return nil end      -- (a walk: 3 at most a storm)
    if walkHold and walkHold() then return nil end
    st.mgrAt, st.mgrTries = os.clock() + 10, (st.mgrTries or 0) + 1
    for _, cn in ipairs({ "LiveCameraShakeManager", "BP_CameraShakeManager_C" }) do   -- (the class, else its blueprint's)
        for _, o in ipairs(THUNDER.mgr == nil and FindAllOf(cn) or {}) do
            if THUNDER.mgr == nil and liveObj(o) and not nameOf(o):find("Default__", 1, true) then THUNDER.mgr = o end
        end
    end
    local m = THUNDER.mgr
    say("mgr" .. (m and "1" or "0"), "thunder: the camera shake manager " .. (m and ("found (" .. nameOf(m) .. "): a "
        .. "lightning shake in its ActiveShakeList counts as a strike") or "NOT found (looked for 3 times a storm, 10 s apart)"))
    return m
end
-- the lightning shakes playing (how many, the first one's name), nil when the list can't be read
local function shakes(mgr)
    local n, name = 0, nil
    local ok = pcall(function()
        mgr.ActiveShakeList:ForEach(function(_, e)
            local okS, cs = pcall(function() return e:get().CameraShake end)
            if okS and cs ~= nil and liveObj(cs) then
                local nm = nameOf(cs)
                if nm:find("Lightning", 1, true) then n, name = n + 1, name or (nm:match("([^%.:/ ]+)$") or nm) end
            end
        end)
    end)
    if ok then return n, name end
    return nil, nil
end
local function hudOf()
    if not liveObj(survivalPC) then return nil end
    local ok, h = pcall(function() return survivalPC.MyHUD end)
    if ok and h ~= nil and liveObj(h) then return h end
    return nil
end
-- what Lua can see of a strike now: the volume's flash (its point light), a lightning camera shake, the HUD widget
local function sense(st)
    local s = {}
    local okL, pl = pcall(function() return st.vol.LightningPointLight end)
    if okL and pl ~= nil and liveObj(pl) then s.flash = num(pl, "Intensity") end
    local mgr = shakeMgr(st)
    if mgr then s.shake, s.shakeName = shakes(mgr) end
    local hud = hudOf()
    if hud then
        local okW, w = pcall(function() return hud.HudWidget end)
        if okW and w ~= nil and liveObj(w) then
            local okV, v = pcall(function() return w:GetVisibility() end)
            local okO, op = pcall(function() return w:GetRenderOpacity() end)
            s.vis = okV and v or nil
            s.op = (okO and type(op) == "number") and op or nil
        end
        local okS, sh = pcall(function() return hud.bShowHUD end)
        if okS and type(sh) == "boolean" then s.show = sh end
    end
    return s
end
-- the AI planes inside storm st: { addr = health } and how many
local function aiInside(st)
    local out, n = {}, 0
    local at = st.center
    if not at then return out, 0 end
    for _, q in ipairs(planes) do
        if not q.down and liveObj(q.obj) then
            local l = where(q.obj)
            if l and km(l, at) * 100000 <= st.radius then
                local a = addrOf(q.obj)
                if a then out[a], n = { h = num(q.obj, "HealthInternal"), name = q.name or nameOf(q.obj) }, n + 1 end
            end
        end
    end
    return out, n
end
-- A strike seen (any of the signals coming on), logged with your health, speed and pitch and the AI planes inside, and
-- FOLLOW_S later what changed (the stall flag's upset: your speed and pitch; your health must not move; an AI plane's
-- health that moved). label: the log's ("storm test", "thunder")
local function watch(st, now, label, pawn)
    local s = sense(st)
    if not st.base then
        st.base = { vis = s.vis, op = s.op, show = s.show }
        log(string.format("%s: what a strike may show, at the start: flash %s, lightning shakes %s, HUD widget visibility %s, "
            .. "opacity %s, bShowHUD %s", label, fmt(s.flash), tostring(s.shake), tostring(s.vis), fmt(s.op), tostring(s.show)))
    end
    local b, h, by = st.base, THUNDER.hook, {}
    if h.n > (st.hookN or h.n) then by[#by + 1] = string.format("the HUD's BeginHUDDistortionLightning (noise %s s)", fmt(h.recover, "%.1f")) end
    if h.ends > (st.hookE or h.ends) then
        log(string.format("%s: the HUD's EndHUDDistortionLightning: the noise over%s", label,
            h.at and string.format(" after %.1f s", os.clock() - h.at) or ""))
    end
    st.hookN, st.hookE = h.n, h.ends
    local shake = (s.shake or 0) > 0
    if shake and not st.shake then by[#by + 1] = "a lightning camera shake (" .. tostring(s.shakeName) .. ")" end
    st.shake = shake
    local hidden = (s.vis ~= nil and b.vis ~= nil and s.vis ~= b.vis) or (s.show ~= nil and b.show ~= nil and s.show ~= b.show)
        or (s.op ~= nil and b.op ~= nil and s.op < b.op - 0.25)
    if hidden and not st.hidden then
        st.hiddenAt = now
        by[#by + 1] = string.format("the HUD hidden (visibility %s, opacity %s, bShowHUD %s)", tostring(s.vis), fmt(s.op), tostring(s.show))
    elseif st.hidden and not hidden and st.hiddenAt then
        local k = st.strikes[#st.strikes]
        if k and not k.blackout then k.blackout = now - st.hiddenAt end
        log(string.format("%s: the HUD back after %.2f s", label, now - st.hiddenAt))
    end
    st.hidden = hidden
    local flash = (s.flash or 0) > 0
    if flash and not st.flash then
        st.flashes = st.flashes + 1
        if label ~= "thunder" or logVerbose() then log(string.format("%s: a flash (its point light %s) at +%.1f s", label, fmt(s.flash, "%.0f"), now - st.at)) end
    end
    st.flash = flash
    if #by > 0 then
        local last = st.strikes[#st.strikes]
        if last and now - last.at < STRIKE_GAP_S then
            for _, x in ipairs(by) do last.by[#last.by + 1] = x end
        else
            st.n = st.n + 1
            local kmh, pitch = motion(pawn)
            local ai, nAi = aiInside(st)
            local k = { n = st.n, at = now, by = by, hp = pawn and num(pawn, "HealthInternal"), kmh = kmh, pitch = pitch, ai = ai }
            if #st.strikes >= 200 then table.remove(st.strikes, 1) end
            st.strikes[#st.strikes + 1] = k
            log(string.format("%s: strike %d at +%.1f s (seen by %s); your health %s, %s km/h, pitch %s deg; %d AI planes inside "
                .. "the storm", label, k.n, now - st.at, table.concat(by, ", "), tostring(k.hp), fmt(kmh, "%.0f"), fmt(pitch, "%.1f"), nAi))
        end
    end
    for _, k in ipairs(st.strikes) do
        if not k.done and now - k.at >= FOLLOW_S then
            k.done = true
            local kmh, pitch = motion(pawn)
            local hp = pawn and num(pawn, "HealthInternal")
            local moved = {}
            for a, e in pairs(k.ai) do
                for _, q in ipairs(planes) do
                    if q.addr == a or addrOf(q.obj) == a then
                        local h1 = liveObj(q.obj) and num(q.obj, "HealthInternal") or 0
                        if h1 ~= e.h then moved[#moved + 1] = string.format("%s %s -> %s", tostring(e.name), tostring(e.h), tostring(h1)) end
                    end
                end
            end
            local nAi = 0
            for _ in pairs(k.ai) do nAi = nAi + 1 end
            log(string.format("%s: strike %d, %.1f s on: seen by %s; your health %s -> %s (%s); %s -> %s km/h, pitch %s -> %s deg; "
                .. "the HUD %s; %d AI planes were inside: %s", label, k.n, FOLLOW_S, table.concat(k.by, ", "), tostring(k.hp), tostring(hp),
                (k.hp ~= nil and hp == k.hp) and "unchanged" or "MOVED", fmt(k.kmh, "%.0f"), fmt(kmh, "%.0f"), fmt(k.pitch, "%.1f"),
                fmt(pitch, "%.1f"), k.blackout and string.format("hidden %.2f s", k.blackout) or "not seen hidden from Lua", nAi,
                #moved > 0 and ("health moved on " .. table.concat(moved, "; ") .. " (a hit? the stock storm strikes player planes only)")
                    or "no health moved (the stock storm strikes player planes only)"))
        end
    end
    return s
end

-- A storm of `owner` ("test", "boss": the host's Anomaly, "copy": a joiner's copy of it) at `at`, radiusM round it: the
-- stock volume spawned deferred, its radius (cm), intervals and curve set before it begins play. The storm, or nil and why.
function THUNDER.stormUp(owner, at, radiusM)
    local c = cfg().storm
    if THUNDER.storm then return nil, "a storm is up already (" .. tostring(THUNDER.storm.owner) .. "'s)" end
    if torn() then return nil, "the level is going" end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (gs and valid(gs)) then return nil, "GameplayStatics not found" end
    if not liveObj(survivalPC) then return nil, "no player controller" end
    local cls, why = stormClass()
    if not cls then return nil, "its class didn't load (" .. tostring(why) .. ")" end
    curveTable()
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)  -- (AlwaysSpawn)
    if not okB or x == nil or not valid(x) then return nil, "no actor (" .. tostring(x) .. ")" end
    local set = {}
    set[#set + 1] = pcall(function() x.Radius = radiusM * 100 end) and "radius" or "radius NOT set"
    if (tonumber(c.min_interval_s) or 0) > 0 then set[#set + 1] = pcall(function() x.MinStrikeInterval = c.min_interval_s end) and "min interval" or "min interval NOT set" end
    if (tonumber(c.max_interval_s) or 0) > 0 then set[#set + 1] = pcall(function() x.MaxStrikeInterval = c.max_interval_s end) and "max interval" or "max interval NOT set" end
    if type(c.curve) == "string" and c.curve ~= "" then set[#set + 1] = pcall(function() x.WeightCurveName = FName(c.curve) end) and "curve" or "curve NOT set" end
    local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
    if not okF or a == nil or not valid(a) then
        pcall(function() x:K2_DestroyActor() end)        -- (never began play: nothing can be inside it)
        return nil, "its spawn didn't finish (" .. tostring(a) .. ")"
    end
    local st = { vol = a, addr = addrOf(a), owner = owner, at = os.clock(), radius = radiusM * 100, center = at, n = 0,
                 flashes = 0, strikes = {}, moves = 0 }
    THUNDER.storm = st
    hookHud()
    local okP, pl = pcall(function() return a.LightningPointLight end)
    log(string.format("thunder: storm up for the %s at (%.0f, %.0f, %.0f), %.1f km round it (%s): reads back Radius %s cm, "
        .. "strike rolls every %s-%s s, curve %s, bEnableCollision %s, bTestPlayer %s, bTestEnemy %s, its flash light %s (%s)",
        owner, at.X, at.Y, at.Z, radiusM / 1000, table.concat(set, ", "), fmt(num(a, "Radius"), "%.0f"), fmt(num(a, "MinStrikeInterval"), "%.1f"),
        fmt(num(a, "MaxStrikeInterval"), "%.1f"), field(a, "WeightCurveName"), field(a, "bEnableCollision"), field(a, "bTestPlayer"),
        field(a, "bTestEnemy"), (okP and pl ~= nil and liveObj(pl)) and "there" or "none", nameOf(a)))
    crumb("thunder: storm up for the " .. owner)
    return st
end
function THUNDER.stormMove(st, at)
    if not (st and at and liveObj(st.vol)) then return false end
    local ok = pcall(function() st.vol:K2_SetActorLocation({ X = at.X, Y = at.Y, Z = at.Z }, false, {}, true) end)
    if ok then st.center, st.moves = at, st.moves + 1 end
    return ok
end
-- The storm taken off (why: the log's): shrunk to 1 cm where it is, destroyed once nothing's inside (parkTick); a level
-- going away: forgotten, not touched.
function THUNDER.stormDown(why)
    local st = THUNDER.storm
    THUNDER.storm = nil
    if not st then return false end
    local up = os.clock() - st.at
    if torn() then
        log(string.format("thunder: the %s's storm forgotten with the level (%s), not touched", st.owner, tostring(why)))
        return true
    end
    if not liveObj(st.vol) then
        log(string.format("thunder: the %s's storm was gone already (%s)", st.owner, tostring(why)))
        return true
    end
    local ok = pcall(function() st.vol.Radius = PARK_RADIUS end)
    st.parkAt, st.empty, st.why = os.clock(), 0, why
    THUNDER.parked[#THUNDER.parked + 1] = st
    log(string.format("thunder: the %s's storm off (%s) after %.0f s: %d strikes and %d flashes seen, moved %d times; %s",
        st.owner, tostring(why), up, st.n, st.flashes, st.moves, ok and "shrunk to 1 cm, destroyed once nothing's inside it"
            or "its radius NOT shrunk: kept until nothing's inside it"))
    crumb("thunder: storm off (" .. st.owner .. ")")
    return true
end
local function parkTick()
    local keep = {}
    for _, st in ipairs(THUNDER.parked) do
        if liveObj(st.vol) then
            local okN, n = pcall(function() return st.vol.InsideGameObjects:GetArrayNum() end)
            if okN and n == 0 then st.empty = st.empty + 1 else st.empty = 0 end
            if st.empty >= 2 then
                local okD = pcall(function() st.vol:K2_DestroyActor() end)
                log(string.format("thunder: the %s's storm destroyed %.1f s after it was taken off (nothing inside it)%s", st.owner,
                    os.clock() - st.parkAt, okD and "" or ": K2_DestroyActor FAILED, left as it is"))
            else
                if os.clock() - st.parkAt > PARK_SAY_S and not st.keptSaid then
                    st.keptSaid = true
                    log(string.format("thunder: the %s's storm kept (1 cm) %d s after it was taken off: InsideGameObjects %s", st.owner,
                        PARK_SAY_S, okN and (tostring(n) .. " inside") or "can't be read"))
                end
                keep[#keep + 1] = st
            end
        end
    end
    THUNDER.parked = keep
end

-- its look: the game's cloud lightning crackling on it (switched off life_s on, destroyed 2 s after)
local function fxAt(at)
    local f = cfg().fx
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys, why = SPC.V.asset(f.system)
    if not (lib and valid(lib) and sys and liveObj(survivalPC) and at) then
        say("fx", "thunder: its cloud lightning didn't spawn: " .. tostring(sys and "no Niagara library or player controller" or why))
        return false
    end
    local sc = tonumber(f.scale) or 1
    local ok, comp = pcall(function()
        return lib:SpawnSystemAtLocation(survivalPC, sys, { X = at.X, Y = at.Y, Z = at.Z }, { Pitch = 0, Yaw = 0, Roll = 0 },
            { X = sc, Y = sc, Z = sc }, true, true, 0, true)
    end)
    if ok and comp ~= nil and liveObj(comp) then
        THUNDER.fx[#THUNDER.fx + 1] = { comp = comp, offAt = os.clock() + (tonumber(f.life_s) or 3) }
        return true
    end
    return false
end
local function crackle(at, now)
    local f = cfg().fx
    if not (f and f.enabled) or now < (THUNDER.fxAt or 0) then return end
    THUNDER.fxAt = now + math.max(0.5, tonumber(f.every_s) or 2.5)
    fxAt(at)
end
local function fxTick(now, all)
    local keep = {}
    for _, e in ipairs(THUNDER.fx) do
        if liveObj(e.comp) then
            if all and not e.goneAt then e.offAt = now end
            if not e.goneAt and now >= e.offAt then
                pcall(function() e.comp:Deactivate() end)
                e.goneAt = now + 2
                keep[#keep + 1] = e
            elseif e.goneAt and now >= e.goneAt then
                if not pcall(function() e.comp:K2_DestroyComponent(e.comp) end) then pcall(function() e.comp:DestroyComponent() end) end
            else
                keep[#keep + 1] = e
            end
        end
    end
    THUNDER.fx = keep
end
local function post(name)                                -- (a Wwise event of the game's SE bank, as the STORE's beeps)
    if type(name) ~= "string" or name == "" then return "none" end
    local ok, err = pcall(function()
        local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
        if not valid(lib) then error("LiveSoundBlueprintLibrary not found") end
        lib:PostEventByName(liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController"), FName(name))
    end)
    return ok and "posted" or ("NOT posted: " .. tostring(err))
end

---------------------------------------------------------------------------------------------------- the Anomaly
-- its health for this round (HP) and the round's x
local function bossHp()
    local c = cfg()
    local round = (D and D.round) or 1
    local hx = math.min(tonumber(c.health_max_x) or 1, 1 + (tonumber(c.health_per_round) or 0) * math.max(0, round - (CFG.specials.first or 1)))
    return math.max(1, (tonumber(c.health) or 1000) * hx), hx
end
-- its live planes (just made ones too) of its unit: { q, ... }
local function bossPlanes(unit)
    local out, seen = {}, {}
    for _, list in ipairs({ planes, pending }) do
        for _, q in ipairs(list) do
            if q.unit == unit and not q.down and liveObj(q.obj) then
                local a = addrOf(q.obj)
                if a and not seen[a] then
                    seen[a] = true
                    local h = num(q.obj, "HealthInternal")
                    if h == nil or h > 0 then out[#out + 1] = q end
                end
            end
        end
    end
    return out
end
-- its name on its box: the callsign line (the plane's CallsignId, the text key name_key: its text set with SV_SetText),
-- written once a plane before its box is made; its type line left as the A-10's (ObjNameID is only logged: it may be the
-- name the event records find it by)
local function nameBox(o)
    local c = cfg()
    local a = addrOf(o)
    if not a or THUNDER.named[a] then return end
    local set = type(SV_SetText) == "function" and SV_SetText(c.name_key, c.name) or "no SV_SetText"
    local okW, w = pcall(function() return o.CallsignId end)
    local was = (okW and w ~= nil) and str(w) or nil      -- (put back at its end only when it could be read)
    local cs0 = was or "?"
    local ok = pcall(function() o.CallsignId = c.name_key end)
    THUNDER.named[a] = { obj = o, was = was }
    local okG, g = pcall(function() return o:GetCallsign() end)
    log(string.format("thunder: its box (%s): CallsignId '%s' -> %s (reads back '%s', GetCallsign() '%s'; %s %s: %s), ObjNameID '%s'",
        nameOf(o), cs0, ok and ("'" .. c.name_key .. "'") or "NOT written", field(o, "CallsignId"), okG and str(g) or "?",
        c.name_key, c.name, tostring(set), field(o, "ObjNameID")))
end
-- its box's callsign put back on what's still live of it (its end)
local function unname()
    for _, e in pairs(THUNDER.named) do
        if e.was ~= nil and not torn() and liveObj(e.obj) then pcall(function() e.obj.CallsignId = e.was end) end
    end
    THUNDER.named = {}
end

function THUNDER.ready()
    local c = cfg()
    if c.enabled == false or type(SV_UnitAlive) ~= "function" then return false end
    return SV_UnitAlive(c.unit) <= 0
end
-- (its round's "@thunder", sv_rounds.lua) the A-10 on its unit spawn_km from you; false if it can't come
function THUNDER.spawn(now)
    install()
    local c, s = cfg(), D.special
    if c.enabled == false then log("thunder: switched off ([thunder] enabled = false): a normal round instead"); return false end
    local up = SV_UnitAlive(c.unit)
    if up > 0 then log(string.format("thunder: %s still has %d up: a normal round instead", c.unit, up)); return false end
    local x, y, dist, bearing = spawnPoint()
    local px, py, pb, pd = ANOM.nearPlayer(c.spawn_km)
    if px then x, y, bearing = px, py, pb end
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local set = SV_SetAircraft(c.unit, c.row)
    if type(SV_SetLevel) == "function" then SV_SetLevel(c.unit, c.ai_level * 100) end
    spawningUnit = c.unit
    local okS, r = pcall(SV_Spawn, c.unit, x, y, alt * 100, (bearing + 180) % 360)
    spawningUnit = nil
    if not okS then log("thunder: SV_Spawn error " .. tostring(r)); return false end
    log(string.format("thunder: %s / %s as %s on %s (%s set), %s, %.1f km up: %s", c.tag, c.name, c.row, c.unit, tostring(set),
        pd and string.format("%.1f km from you at bearing %.0f", pd, pb) or string.format("%.0f km from the airfield at bearing %.0f", dist, bearing),
        alt / 1000, r > 0 and (r .. " aircraft up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")")))
    if r <= 0 then return false end
    for _, q in ipairs(bossPlanes(c.unit)) do nameBox(q.obj) end      -- (before a frame is drawn: its box made with it)
    D.flightTier = D.flightTier or {}
    D.up[c.unit], D.flown[c.unit], D.flightTier[c.unit] = true, true, #CFG.tiers.list
    s.state, s.at = "hunt", now
    THUNDER.lastSeen, THUNDER.fxAt, THUNDER.stormSaid = os.clock(), nil, nil
    local cam = 0
    for k, n in ipairs(ANOMALY_CAMERAS or {}) do if n == c.camera then cam = k end end
    local camR = "none"
    if cam > 0 and type(SV_Event) == "function" then camR = tostring(SV_Event("RE_SV_AnomalyCam_" .. string.char(64 + cam))) end
    hudCallout(string.format(c.text.warn, c.tag), string.format(c.text.warn_sub, c.name))
    log(string.format("thunder: its warning; its camera %s (%s); its sound %s: %s", c.camera, camR, tostring(c.start_sound), post(c.start_sound)))
    return true
end
-- the storm kept on it at `at` (owner "boss" or "copy"): made the first time (a test's storm ends first), moved after
local function keepStorm(owner, at)
    local st = THUNDER.storm
    if st and st.owner == "test" and THUNDER.testEnd then THUNDER.testEnd(os.clock(), "the Anomaly's storm takes over"); st = THUNDER.storm end
    if st and st.owner ~= owner then THUNDER.stormDown("the " .. owner .. "'s storm takes over"); st = nil end
    if not st then
        if os.clock() < (THUNDER.stormRetry or 0) then return nil end
        local why
        st, why = THUNDER.stormUp(owner, at, tonumber(cfg().storm.radius_m) or 3000)
        if not st then
            THUNDER.stormRetry = os.clock() + 10
            if not THUNDER.stormSaid then THUNDER.stormSaid = true; log("thunder: no storm on it: " .. tostring(why) .. " (tried again every 10 s)") end
            return nil
        end
    end
    THUNDER.stormMove(st, at)
    return st
end
local function stormOff(owner, why)
    if THUNDER.storm and THUNDER.storm.owner == owner then return THUNDER.stormDown(why) end
    return false
end
local function bossDown(now, s)
    local c, t = cfg(), cfg().text
    s.state = "done"
    stormOff("boss", "it's down")
    if s.lastAt then fxAt(s.lastAt); fxAt(s.lastAt) end
    if type(SV_Event) == "function" then SV_Event("RE_SV_AnomalyEnd") end                -- (the WARNING, noise and throttle off)
    local snd = post(c.stop_sound)
    unname()
    local pay = c.reward + (c.reward_per_round or 0) * D.round
    addCredits(pay, c.name .. " down")
    hudCallout(string.format(t.down, c.name), string.format(t.down_sub, specialPay(pay)))
    log(string.format("thunder: round %d, %s shot down %.0f s after it appeared; RE_SV_AnomalyEnd fired, its sound's stop %s", D.round,
        c.name, now - (s.at or now), snd))
end
-- (the host's or solo, every tick of its round) its health once, its box, the storm on it, its end
function THUNDER.tick(now, s)
    install()
    local c = cfg()
    THUNDER.lastSeen = os.clock()
    if s.state ~= "hunt" then stormOff("boss", "its fight is over"); return end
    if now - (s.at or now) >= 2 and SV_UnitAlive(c.unit) <= 0 then return bossDown(now, s) end
    local q = bossPlanes(c.unit)[1]
    if not q then return end
    local o = q.obj
    nameBox(o)
    if not s.healthDone then
        s.healthDone = true
        local hp, hx = bossHp()
        local h0, m0 = num(o, "HealthInternal"), num(o, "MaxHealth")
        local okM = pcall(function() o.MaxHealth = hp end)
        local okH = pcall(function() o.HealthInternal = math.floor(hp * 10 + 0.5) end)
        log(string.format("thunder: %s's health x%.2f for round %d: %s HP (MaxHealth %s -> %s%s, HealthInternal %s -> %s%s)", c.name, hx,
            D.round, fmt(hp, "%.0f"), tostring(m0), fmt(num(o, "MaxHealth"), "%.0f"), okM and "" or " NOT written", tostring(h0),
            tostring(num(o, "HealthInternal")), okH and "" or " NOT written"))
    end
    local at = where(o)
    if not at then return end
    s.lastAt = at
    local you = playerLocation()
    if you then s.dist = km(at, you) end
    local clock = os.clock()
    if ANOM.downNow() then
        stormOff("boss", "you're DOWN")
    else
        local st = keepStorm("boss", at)
        if st and c.storm.log_strikes then watch(st, clock, "thunder", myPlane()) end
    end
    crackle(at, clock)
end
function THUNDER.over(now, s)
    stormOff("boss", "its round is over")
    fxTick(os.clock(), true)
end
function THUNDER.row(s, t)
    local c = cfg()
    if not (s and s.state == "hunt" and s.dist) then return nil end
    local st = THUNDER.storm
    if st and st.owner == "boss" and s.dist * 100000 <= st.radius then return string.format(c.text.row_storm, c.name) end
    return string.format(c.text.row, c.name, s.dist)
end
SPC.kinds.thunder = { sub = function() return cfg().tag end, alone = true, aircraft = 1,
                      ready = function() return THUNDER.ready() end, spawn = function(now) return THUNDER.spawn(now) end,
                      tick = function(now, s) return THUNDER.tick(now, s) end, over = function(now, s) return THUNDER.over(now, s) end,
                      row = function(s, t) return THUNDER.row(s, t) end }
-- (its stock records set the attack throttle at its appearance and put B back at its death, as MINDRIPPER's)
TIER.PRESSURE_OWN.thunder = true

-- A co-op joiner: a storm on this game's live copy of it while the host's hunts ("rnd" field 12), off when it's over, when
-- there's no live copy and while you're DOWN; its box named here too
local function clientTick(now)
    local c = cfg()
    local hs = D and D.hostSpecial
    if not (hs and hs.kind == "thunder" and hs.state == "hunt") then
        stormOff("copy", "the host's is over")
        if next(THUNDER.named) then unname() end
        return
    end
    THUNDER.lastSeen = now
    for _, q in ipairs(pending) do if q.unit == c.unit and liveObj(q.obj) then nameBox(q.obj) end end
    local p = ANOM.liveCopy(c.unit)
    if not p then stormOff("copy", "no live copy of it here"); return end
    local o = p.obj
    nameBox(o)
    local a = addrOf(o)
    if a and THUNDER.copyHp ~= a then                    -- (its MaxHealth for its box; its health is the host's "hp")
        THUNDER.copyHp = a
        local hp = bossHp()
        local m0 = num(o, "MaxHealth")
        local ok = pcall(function() o.MaxHealth = hp end)
        log(string.format("coop: thunder: the host's %s here: its copy's MaxHealth %s -> %s%s (its health comes from the host)", c.name,
            tostring(m0), fmt(hp, "%.0f"), ok and "" or " NOT written"))
    end
    if ANOM.downNow() then stormOff("copy", "you're DOWN"); return end
    local at = where(o)
    if not at then return end
    local st = keepStorm("copy", at)
    if st and c.storm.log_strikes then watch(st, now, "thunder", myPlane()) end
    crackle(at, now)
end

---------------------------------------------------------------------------------------------------- the storm test
local function readLS(p)
    return { min = num(p, "LS_MinDebuffTime"), max = num(p, "LS_MaxDebuffTime"), stall = num(p, "LS_StallTime") }
end
local function lsText(ls) return string.format("LS_MinDebuffTime %s, LS_MaxDebuffTime %s, LS_StallTime %s", fmt(ls.min, "%.1f"), fmt(ls.max, "%.1f"), fmt(ls.stall, "%.1f")) end
function THUNDER.testEnd(now, why)
    local T = THUNDER.test
    THUNDER.test = nil
    if not T then return end
    local back = "not changed"
    if T.stalled then
        if not torn() and liveObj(T.pawn) and addrOf(T.pawn) == T.pawnAddr and T.ls.stall then
            local ok = pcall(function() T.pawn.LS_StallTime = T.ls.stall end)
            back = ok and string.format("back to %s", fmt(num(T.pawn, "LS_StallTime"), "%.1f")) or "NOT put back"
        else
            back = "not put back (the plane's gone)"
        end
    end
    if THUNDER.storm == T.st then THUNDER.stormDown(why) end
    local st = T.st
    local by = {}
    for _, k in ipairs(st.strikes) do for _, x in ipairs(k.by) do by[x:match("^[^%(]+") or x] = (by[x:match("^[^%(]+") or x] or 0) + 1 end end
    local byT = {}
    for k, n in pairs(by) do byT[#byT + 1] = string.format("%s x%d", (k:gsub("%s+$", "")), n) end
    table.sort(byT)
    log(string.format("storm test: over (%s) after %.0f s: %d strikes seen (%s), %d flashes; your health %s..%s over %d samples (%s); "
        .. "LS_StallTime %s", tostring(why), now - T.at, st.n, #byT > 0 and table.concat(byT, ", ") or "none", st.flashes,
        tostring(T.hMin), tostring(T.hMax), T.nH, (T.hMin ~= nil and T.hMin == T.hMax) and "it never moved" or "it MOVED", back))
    hudCallout(cfg().text.storm_off, string.format("%d STRIKES", st.n))
end
local function testStart(now)
    local c = cfg().test
    local pawn, at = myPlane(), playerLocation()
    if not (pawn and at) then log("storm test: Ctrl+,: no plane of yours in the level"); return end
    if THUNDER.storm then
        log("storm test: Ctrl+,: a storm is up already (the " .. tostring(THUNDER.storm.owner) .. "'s): not started")
        hudCallout("TEST: STORM ALREADY UP", string.upper(tostring(THUNDER.storm.owner)))
        return
    end
    local st, why = THUNDER.stormUp("test", at, tonumber(c.radius_m) or 3000)
    if not st then log("storm test: Ctrl+,: no storm: " .. tostring(why)); hudCallout("TEST: NO STORM", "SEE THE LOG"); return end
    local T = { run = D, st = st, at = now, untilAt = now + (tonumber(c.seconds) or 60), pawn = pawn, pawnAddr = addrOf(pawn),
                ls = readLS(pawn), nH = 0, last = {}, lineAt = now + 1 }
    THUNDER.test = T
    log(string.format("storm test: Ctrl+,, the storm on you for %d s, %.1f km round you; your plane (%s): %s; health %s, MaxHealth %s",
        c.seconds, (tonumber(c.radius_m) or 3000) / 1000, nameOf(pawn), lsText(T.ls), tostring(num(pawn, "HealthInternal")),
        tostring(num(pawn, "MaxHealth"))))
    shakeMgr(st)
    hudCallout(cfg().text.storm_on, string.format(cfg().text.storm_on_sub, c.seconds, (tonumber(c.radius_m) or 3000) / 1000))
end
local function testStall(now, T)
    local c = cfg().test
    local was = num(T.pawn, "LS_StallTime")
    local ok = false
    if liveObj(T.pawn) then ok = pcall(function() T.pawn.LS_StallTime = c.stall_s end) end
    T.stalled, T.untilAt = true, now + (tonumber(c.seconds) or 60)
    log(string.format("storm test: Ctrl+, again: your plane's LS_StallTime %s -> %s (%s; stock %s): each strike's stall flag held that "
        .. "long; the storm on you %d s more", fmt(was, "%.1f"), fmt(num(T.pawn, "LS_StallTime"), "%.1f"), ok and "written" or "NOT written",
        fmt(T.ls.stall, "%.1f"), c.seconds))
    hudCallout(string.format(cfg().text.storm_stall, c.stall_s), cfg().text.storm_stall_sub)
end
local function testTick(now)
    local T = THUNDER.test
    if not T then return end
    if T.run ~= D then THUNDER.testEnd(now, "a new run"); return end
    if THUNDER.storm ~= T.st then THUNDER.test = nil; log("storm test: its storm was taken off by something else"); return end
    if now >= T.untilAt then THUNDER.testEnd(now, string.format("%d s up", math.floor(cfg().test.seconds or 60))); return end
    local pawn = myPlane()
    if pawn and addrOf(pawn) ~= T.pawnAddr then
        T.pawn, T.pawnAddr, T.ls = pawn, addrOf(pawn), readLS(pawn)
        log("storm test: your plane changed (" .. nameOf(pawn) .. "): " .. lsText(T.ls))
        if T.stalled then pcall(function() pawn.LS_StallTime = cfg().test.stall_s end) end
    end
    local at = playerLocation()
    if at then THUNDER.stormMove(T.st, at) end
    local h = pawn and num(pawn, "HealthInternal")
    if h then
        T.nH = T.nH + 1
        T.hMin, T.hMax = math.min(T.hMin or h, h), math.max(T.hMax or h, h)
        if T.lastH and h ~= T.lastH then
            local k = T.st.strikes[#T.st.strikes]
            log(string.format("storm test: your health moved %s -> %s at +%.1f s (%s)", tostring(T.lastH), tostring(h), now - T.at,
                k and string.format("strike %d was %.1f s before", k.n, now - k.at) or "no strike seen yet"))
        end
        T.lastH = h
    end
    T.last[#T.last + 1] = h and tostring(h) or "?"
    watch(T.st, now, "storm test", pawn)
    if now >= T.lineAt then
        T.lineAt = now + 1
        local kmh = motion(pawn)
        local _, nAi = aiInside(T.st)
        log(string.format("storm test: +%.0f s: health %s; %s km/h; %d strikes, %d flashes; %d AI planes inside", now - T.at,
            table.concat(T.last, " "), fmt(kmh, "%.0f"), T.st.n, T.st.flashes, nAi))
        T.last = {}
    end
end

---------------------------------------------------------------------------------------------------- keys, ticks, the level
-- (every tick of a run, every game: the parked storms, its look, the storm test, a joiner's storm, a host's storm with no
-- fight left)
TEST_TICKS[#TEST_TICKS + 1] = { name = "thunder", fn = function(now)
    install()
    if torn() then
        if THUNDER.storm or #THUNDER.parked > 0 or THUNDER.test then
            log("thunder: the level is going: its storms and the storm test forgotten, not touched")
            THUNDER.storm, THUNDER.parked, THUNDER.test, THUNDER.fx, THUNDER.named = nil, {}, nil, {}, {}
        end
        return
    end
    parkTick()
    fxTick(now, false)
    testTick(now)
    if joiner() then
        clientTick(now)
    else
        local s = D and D.special
        if not (s and s.kind == "thunder" and s.state == "hunt") then
            stormOff("boss", "its round is over")
            if next(THUNDER.named) then unname() end
        end
        stormOff("copy", "this game hosts now")
    end
end }
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["thunder"] = function()
        THUNDER.storm, THUNDER.parked, THUNDER.test, THUNDER.fx, THUNDER.named = nil, {}, nil, {}, {}
        THUNDER.cls, THUNDER.copyHp, THUNDER.mgr = nil, nil, nil
    end
end
-- Ctrl+,: the storm test (any game: it's this game's own)
testKey("OEM_COMMA", "sv_anomalies.lua's storm test", function()
    local now = os.clock()
    install()
    if not (D and D.now) then log("storm test: Ctrl+, outside a Survival run"); return end
    local T = THUNDER.test
    if T and T.run ~= D then THUNDER.testEnd(now, "a new run"); T = nil end
    if not T then testStart(now)
    elseif not T.stalled then testStall(now, T)
    else THUNDER.testEnd(now, "Ctrl+,") end
end)
-- Ctrl+.: the next round is IFF FATAL ERROR's (in the break: it starts in 3 s), the host's or solo
testKey("OEM_PERIOD", "sv_anomalies.lua's IFF FATAL ERROR", function()
    install()
    local c = cfg()
    if not (D and D.now) or not nativeReady() then log("thunder: Ctrl+. outside a Survival run"); return end
    if joiner() then log("thunder: Ctrl+.: the host brings it (you're a joiner)"); return end
    if c.enabled == false then log("thunder: Ctrl+.: switched off ([thunder] enabled = false)"); return end
    D.forceSpecial = "thunder"
    local soon = D.state == "wait"
    if soon then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
    hudCallout(string.format(c.text.key, c.tag), soon and c.text.key_now or c.text.key_next)
    log(string.format("thunder: Ctrl+., round %d is %s / %s (%s)", D.round + 1, c.tag, c.name, soon and "starting in 3 s" or "after this round"))
end)
end
-- TEST ONLY END
