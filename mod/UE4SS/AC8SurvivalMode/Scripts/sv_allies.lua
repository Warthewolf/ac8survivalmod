-- sv_allies.lua: the allies (MOONCHILD, the ships).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- allies
-- The STORE's allies (CFG.allies; tools/survival_events.py ALLY_*). Their DT_NPC rows (DT_SV_NpcRows) go into DT_NPC at
-- the main menu, before a level loads (the spawner reads them then), each weapon on fire control of its own (<FCS>_SVA);
-- a ship sails when bought, a MOONCHILD flight spawns once you're airborne and the runway is clear (both flights park
-- on one spot) and the event package flies its takeoff. ALLY.run: the run's allies, up[unit] = { kind, key, at,
-- queued, price }, and the enemy orders waiting to be fired (events).
do
-- DT_SV_NpcRows' ally rows (tools/build_survival.py build_npc_rows: the F-22, the hulls and their turrets)
local ROWS = { "SV_Ally_Moonchild", "SV_Ally_Aegis", "SV_Def_Gepa", "SV_Def_Avng",
               "SV_Turret_aegs_mk15_Ally", "SV_Turret_aegs_mk41_Ally", "SV_Turret_aegs_mk45_Ally",
               "SV_Turret_aegs_artillery_Ally" }
local ROW_SHIP = {}            -- a ship type's hull and turret rows (its fcs and module): SV_Ally_<key>, SV_Turret_<turrets>_*
for _, row in ipairs(ROWS) do
    for key, sh in pairs(CFG.allies.ships) do
        if row == "SV_Ally_" .. key or (sh.turrets and row:find("SV_Turret_" .. sh.turrets .. "_", 1, true) == 1) then
            ROW_SHIP[row] = key
        end
    end
end
ROW_SHIP.SV_Def_Gepa, ROW_SHIP.SV_Def_Avng = "Defence", "Defence"   -- (the airfield's AA guns and SAM sites)
for _, u in ipairs(CFG.allies.aircraft.units) do ALLY.unit[u] = "air" end
for key, sh in pairs(CFG.allies.ships) do for _, u in ipairs(sh.units) do ALLY.unit[u] = key end end
-- WINGMEN's DT_SV_NpcRows row (the review build's: tools/build_survival.py, its F-16C under SV_Wingmen); apart from
-- ROWS, so a container without it still sells the rest
local WINGMEN_ROW = "SV_Ally_Wingmen"

function ALLY.setup()
    if ALLY.setupDone or not CFG.allies.enabled or not gameInstance() or not SR.done then return end
    ALLY.tries = (ALLY.tries or 0) + 1
    local npc, mine, fcs = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows), loadObject(FCS_TABLE)
    if not (npc and mine and fcs) then
        if ALLY.tries >= 20 then ALLY.setupDone = true; log("allies: their tables didn't load; the STORE sells none") end
        return
    end
    ALLY.setupDone = true
    local wpn = loadObject(WEAPON_TABLE)
    for _, t in ipairs({ npc, mine, fcs, wpn }) do if t then pin(t, nameOf(t)) end end
    local c, made, boosted, lost = CFG.allies.fcs, {}, 0, {}
    local shipSaid, shipModule, gunSaid = {}, {}, {}
    local modules = loadObject(SEARCH_MODULE.path)
    if modules then
        pin(modules, nameOf(modules))
        for key, sh in pairs(CFG.allies.ships) do
            local sf = sh.fcs
            if sf and sf.search_m then
                local row = "NPC_AIModule_SV_" .. key
                if cloneRow(modules, "NPC_AIModule_Turret000", row, function(r)
                    r.Radius = sf.search_m
                    pcall(function() r.bEnableLostTargetInClouds = false end)
                end) then
                    shipModule[key] = row
                    log(string.format("allies: %s's turrets search %d m (%s)", key, sf.search_m, row))
                end
            end
        end
    end
    local function allyFcs(src, key)                 -- src .. "_SVA[_<ship>]": farther, wider, quicker, tighter
        local sf = key and (key == "Defence" and CFG.shop.items.Airfield.defences.fcs
                            or CFG.allies.ships[key] and CFG.allies.ships[key].fcs)
        local new = src .. "_SVA" .. (sf and ("_" .. key) or "")
        local lockX, fireX = c.time_x * (sf and sf.lock_x or 1), c.time_x * (sf and sf.fire_x or 1)
        if made[new] == nil then
            made[new] = cloneRow(fcs, src, new, function(r)
                pcall(function() r.CaptureDistance = r.CaptureDistance * (sf and sf.range_x or c.range_x) end)
                pcall(function() r.CaptureAngleRange = math.min(180, r.CaptureAngleRange * c.angle_x) end)
                for f, x in pairs({ ActivationTime = lockX, TriggeringTime = lockX, ShotIntervalTime = fireX, RestingTime = fireX }) do
                    pcall(function() r[f] = r[f] * x end)
                end
                -- (CFG.allies.magazine_min: an ally that lasts round after round never runs dry)
                pcall(function() r.MagazineCapacity = math.max(r.MagazineCapacity, CFG.allies.magazine_min or 0) end)
                pcall(function()                     -- guns: MOONCHILD's lead and fire longer bursts, AA guns lead further
                    if src:find("PlaneGun", 1, true) then
                        r.PredictionOffsetTime = c.gun_lead_s or 0
                        r.TriggerCount = math.max(1, math.floor(r.TriggerCount * (c.burst_x or 1) + 0.5))
                        gunSaid[#gunSaid + 1] = string.format("%s leads %.2f s, %d-round bursts", new, r.PredictionOffsetTime, r.TriggerCount)
                    elseif src:find("AAGun", 1, true) or src:find("CIWS", 1, true) then
                        local l = r.PredictionOffsetTime
                        if type(l) ~= "number" or l <= 0 then l = 0.8 end        -- (none of its own: the AA guns')
                        r.PredictionOffsetTime = l * (c.aa_lead_x or 1)
                        gunSaid[#gunSaid + 1] = string.format("%s leads %.2f s", new, r.PredictionOffsetTime)
                    end
                end)
                if sf and shipModule[key] then        -- the ship type's own turret module: farther, not lost in cloud
                    pcall(function() r.NpcAIModuleId = FName(shipModule[key]) end)
                    pcall(function() r.bEnableLostTargetInClouds = false end)
                end
                local what = ""
                pcall(function()                     -- a gun's rounds: a tighter spread (a weapon row without one stays)
                    local w = r.NpcWeaponId:ToString()
                    local wn = w .. "_SVA" .. (sf and ("_" .. key) or "")
                    local mc, missile = sf and sf.missile, false
                    if wpn and w ~= "None" and w ~= "" and cloneRow(wpn, w, wn, function(x)  -- (edit: a new row only)
                        pcall(function() x.MaxSpawnAngle = x.MaxSpawnAngle * c.spread_x end)
                        local homing = false
                        pcall(function() homing = x.bIsHoming == true end)
                        if mc and homing then        -- a homing missile: flies long enough to reach range_m
                            missile = true
                            pcall(function() x.LifeTime = math.max(x.LifeTime, mc.life_s) end)
                            pcall(function() x.AccelerationKmph = x.AccelerationKmph * mc.accel_x end)
                            pcall(function() x.SpeedMaxKmph = math.max(x.SpeedMaxKmph, mc.speed_max_kmph) end)
                            pcall(function() x.MaxRotationAngle = x.MaxRotationAngle * mc.turn_x end)
                            pcall(function() x.HomingReductionInCloud = 0 end)
                            pcall(function()
                                what = string.format(", missile %s: %.0f s at up to %.0f km/h (+%.0f km/h a second), turns %.0f",
                                    wn, x.LifeTime, x.SpeedMaxKmph, x.AccelerationKmph, x.MaxRotationAngle)
                            end)
                        end
                    end) then
                        r.NpcWeaponId = FName(wn)
                        -- a homing missile by its row, made now or before (code review of 2026-10-23: cloneRow skips
                        -- the edit for a row that's already there, and the range stayed the stock one)
                        if mc and not missile then
                            pcall(function() local _, wr = dtCall(wpn, "FindRow", wn); missile = wr ~= nil and wr.bIsHoming == true end)
                        end
                        if missile then pcall(function() r.CaptureDistance = mc.range_m end) end
                    end
                end)
                if sf then
                    pcall(function()
                        shipSaid[#shipSaid + 1] = string.format("%s (within %d m, arm %.2f s, lock %.2f s, %.2f s between, rest %.2f s%s)",
                            new, math.floor(r.CaptureDistance), r.ActivationTime, r.TriggeringTime, r.ShotIntervalTime,
                            r.RestingTime, what)
                    end)
                end
            end) and true or false
        end
        return made[new] and new or nil
    end
    local n = 0
    local all = { WINGMEN_ROW }
    for _, row in ipairs(ROWS) do all[#all + 1] = row end
    for _, row in ipairs(all) do
        local _, have = dtCall(npc, "FindRow", row)
        if have == nil then
            local _, r = dtCall(mine, "FindRow", row)
            if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
        end
        if row == WINGMEN_ROW then ALLY.wingmenReady = have ~= nil end
        if have ~= nil and row ~= WINGMEN_ROW then n = n + 1 end
        local sh = ROW_SHIP[row] and CFG.allies.ships[ROW_SHIP[row]]
        if have ~= nil and sh and sh.health_add and row == "SV_Ally_" .. ROW_SHIP[row] then   -- a hull: its own health
            local okH, h = pcall(function()                -- (once a session: ALLY.setup runs once, the row stays in)
                have.MaxHealthDifference = (have.MaxHealthDifference or 0) + sh.health_add
                return have.MaxHealthDifference
            end)
            log(string.format("allies: %s's hull %+d HP (MaxHealthDifference now %s)", sh.name, sh.health_add, okH and tostring(h) or "NOT set"))
        end
        if have ~= nil then
            for i = 0, 5 do
                pcall(function()
                    local id = have["NpcFCSId" .. i]:ToString()
                    if id ~= "None" and id ~= "" and not id:find("_SVA") then
                        local new = allyFcs(id, ROW_SHIP[row])
                        if new then have["NpcFCSId" .. i] = FName(new); boosted = boosted + 1 end
                    end
                end)
            end
            if (row == ROWS[1] or row == WINGMEN_ROW) and SR.module then   -- MOONCHILD / WINGMEN search as far as the enemies do
                pcall(function() have.NpcAIModuleId = FName(SR.module) end)
            end
            if ROW_SHIP[row] and shipModule[ROW_SHIP[row]] then   -- a ship's hull and turrets: its own module
                pcall(function() have.NpcAIModuleId = FName(shipModule[ROW_SHIP[row]]) end)
            end
        else
            lost[#lost + 1] = row
        end
    end
    local names = 0
    if type(SV_SetText) == "function" then
        if SV_SetText(CFG.allies.aircraft.name_key, CFG.allies.aircraft.name) == 1 then names = names + 1 end
        if SV_SetText(CFG.allies.wingmen.name_key, CFG.allies.wingmen.name) == 1 then names = names + 1 end
        for key, sh in pairs(CFG.allies.ships) do if SV_SetText("SV_Ship_" .. key, sh.name) == 1 then names = names + 1 end end
    end
    ALLY.ready = n == #ROWS
    if #shipSaid > 0 then log("allies: the ships' and the airfield's own fire control: " .. table.concat(shipSaid, ", ")) end
    if #gunSaid > 0 then log("allies: guns: " .. table.concat(gunSaid, ", ")) end
    log(string.format("allies: %d of %d rows in DT_NPC%s, WINGMEN %s, %d weapons on their own fire control (x%.1f range, x%.1f times), %d names set",
        n, #ROWS, #lost > 0 and (" (missing: " .. table.concat(lost, ", ") .. ")") or "", ALLY.wingmenReady and "in" or "NOT in",
        boosted, c.range_x, c.time_x, names))
end

-- CFG.allies.ally_speakers: on while a run is on (`want`), back to the game's values after it.
function ALLY.speakerTick(want)
    local st = ALLY.spk or { on = false, orig = {} }
    ALLY.spk = st
    if st.on == want then return end
    st.on = want
    for _, sp in ipairs(CFG.allies.ally_speakers or {}) do
        local ok, err = pcall(function()
            local dt = loadObject(sp.table)
            if not dt then error("no " .. sp.table) end
            local _, r = dtCall(dt, "FindRow", sp.row)
            if r == nil then error("no row " .. sp.row) end
            local id = r.SpeakerID:ToString()
            if id ~= sp.id then error("row " .. sp.row .. " is " .. id) end
            if want then
                st.orig[sp.row] = { color = r.ColorType, process = r.ProcessID:ToString() }
                r.ColorType, r.ProcessID = 0, FName(sp.process)
                log(string.format("allies: speaker %s talks as an ally (was colour %s, %s)", sp.id,
                    tostring(st.orig[sp.row].color), st.orig[sp.row].process))
            elseif st.orig[sp.row] then
                local o = st.orig[sp.row]
                r.ColorType, r.ProcessID = o.color, FName(o.process)
                log(string.format("allies: speaker %s back to colour %s, %s", sp.id, tostring(o.color), o.process))
            end
        end)
        if not ok then log("allies: speaker " .. tostring(sp.id) .. ": " .. tostring(err)) end
    end
end

function ALLY.state()
    ALLY.run = ALLY.run or { up = {}, events = {}, hunted = {}, seen = {}, planes = {}, nextTakeoff = 0 }
    return ALLY.run
end

-- Of `units`: how many are bought (at sea, flying or waiting to take off), and a free one, or nil.
function ALLY.status(units)
    local R, up, free = ALLY.state(), 0, nil
    for _, u in ipairs(units) do
        if R.up[u] then up = up + 1
        elseif not free and nativeReady() and SV_UnitAlive(u) <= 0 then free = u end
    end
    return up, free
end

function ALLY.shipsAtSea()
    local out = {}
    for u, s in pairs(ALLY.state().up) do if s.kind == "ship" then out[#out + 1] = u end end
    table.sort(out)
    return out
end

-- A purchase (the shop takes the zollars when it succeeds): true and its message, or false and why not.
function ALLY.buy(role, unit, key, price)
    local R, t, now = ALLY.state(), CFG.allies.text, D and D.now or 0
    if role == "ally_ship" then
        local sh = CFG.allies.ships[key]
        spawningUnit = unit
        local r = SV_Spawn(unit)
        spawningUnit = nil
        log(string.format("allies: %s (%s): %s", sh.name, unit, r > 0 and "at sea" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
        if r <= 0 then return false, "COULD NOT SEND IT (" .. (SV_ERR[r] or tostring(r)) .. ")." end
        R.up[unit] = { kind = "ship", key = key, at = now, price = price }
        hudCallout(string.format(t.ship, sh.name), t.ship_sub)
        return true, sh.name .. " AT SEA"
    end
    -- an allied flight on MOONCHILD's units: MOONCHILD's F-22s, or the cheaper WINGMEN (key "wingmen")
    local wing = key == "wingmen"
    local name = wing and CFG.allies.wingmen.name or CFG.allies.aircraft.name
    R.up[unit] = { kind = "air", ally = wing and "wingmen" or "moonchild", queued = true, at = now, price = price }
    log(string.format("allies: %s (%s) bought; it takes off once you're airborne", name, unit))
    return true, name .. " TAKES OFF ONCE YOU'RE AIRBORNE"
end

-- An allied flight's name and scaling (MOONCHILD, or the WINGMEN on its units)
local function airName(s) return (s and s.ally == "wingmen") and CFG.allies.wingmen.name or CFG.allies.aircraft.name end
local function airScale(s) return ((s and s.ally == "wingmen") and CFG.allies.wingmen.scale or CFG.allies.aircraft.scale) or {} end

-- An allied flight's level for this round (CFG.allies.aircraft.scale / wingmen.scale): { rank, ai, hx (health
-- multiplier), tier name }
function ALLY.level(s)
    local sc, round = airScale(s), math.max(1, D and D.round or 1)
    local t = CFG.tiers.enabled and CFG.tiers.list[TIER.index(round)] or {}
    return { rank = math.max(sc.rank_min or 1, math.min(5, (t.rank or 3) + (sc.rank_add or 0))),
             ai = math.max(sc.ai_level_min or 2, t.ai_level or 2),
             hx = math.min(sc.health_max_x or 1, (sc.health_x or 1) * (1 + (sc.health_per_round or 0) * (round - 1))),
             tier = t.name or "-" }
end

-- Each allied aircraft at this round's level: its rank, and its health raised by the growth since it was last set
-- (p.full: its full health now, what the repairs between rounds bring it back to)
function ALLY.scale()
    local R = ALLY.state()
    if #R.planes == 0 then return end
    for i = #R.planes, 1, -1 do
        local p = R.planes[i]
        if not valid(p.obj) then table.remove(R.planes, i)
        elseif p.round ~= D.round then
            local L = ALLY.level(R.up[p.unit])
            p.round = D.round
            pcall(function() p.obj.PilotRank = L.rank end)
            local was = p.hx or 1
            p.hx = L.hx
            local ok, h0, h1 = pcall(function()
                local h = p.obj.HealthInternal
                if L.hx > was and h > 0 then p.obj.HealthInternal = math.floor(h * L.hx / was + 0.5) end
                return h, p.obj.HealthInternal
            end)
            if ok then
                local okM, mh = pcall(function() return p.obj.MaxHealth end)
                p.full = (okM and type(mh) == "number") and math.floor(mh * 10 * L.hx + 0.5) or math.max(p.full or 0, h1 or 0)
            end
            log(string.format("allies: %s (%s) at round %d's level (%s): PilotRank %d, health x%.2f (%s -> %s)", p.name, p.unit,
                D.round, L.tier, L.rank, L.hx, ok and tostring(h0) or "?", ok and tostring(h1) or "?"))
        end
    end
end

-- CFG.allies.repair: between rounds every allied aircraft, ship (hull and turrets) and airfield defence still up back
-- to full health (economy review of 2026-10-25: "allies who last"). The ships' and defences' actors are found by their
-- classes (BP_VE002_aegs_* / BP_GR002_gepa_CP / BP_GR005_avng_CP: the names the AI watch logged), once a round.
local SHIP_CLASSES = { "BP_VE002_aegs_CP_C", "BP_VE002_aegs_mk15_01_CP_C", "BP_VE002_aegs_mk41_CP_C", "BP_VE002_aegs_mk45_CP_C" }
local DEF_CLASSES = { "BP_GR002_gepa_CP_C", "BP_GR005_avng_CP_C" }
local function repairActors(classes)
    local n = 0
    for _, cls in ipairs(classes) do
        for _, o in ipairs(FindAllOf(cls) or {}) do
            if valid(o) and inSurvival(o) and not nameOf(o):find("Default__", 1, true) then
                pcall(function()
                    local h, mh = o.HealthInternal, o.MaxHealth
                    if h > 0 and mh > 0 and h < math.floor(mh * 10) then o.HealthInternal = math.floor(mh * 10); n = n + 1 end
                end)
            end
        end
    end
    return n
end

-- The airfield defences' health in % (their actors within 4 km of the runway, found again every 30 s or when one is
-- built or lost; read every 2 s), or nil when none is up
local function defenceHealth(R, now)
    local n = R.defCount and (R.defCount.aa + R.defCount.sam) or 0
    if n == 0 then R.defActors = nil; return nil end
    if not R.defActors or R.defActorsN ~= n or now >= (R.defActorsAt or 0) then
        R.defActors, R.defActorsN, R.defActorsAt = {}, n, now + 30
        for _, cls in ipairs(DEF_CLASSES) do
            for _, o in ipairs(FindAllOf(cls) or {}) do
                if valid(o) and inSurvival(o) and not nameOf(o):find("Default__", 1, true) then
                    local ok, l = pcall(function() return o:K2_GetActorLocation() end)
                    if ok and l and math.sqrt((l.X - AIRFIELD.X) ^ 2 + (l.Y - AIRFIELD.Y) ^ 2) < 400000 then
                        R.defActors[#R.defActors + 1] = o
                    end
                end
            end
        end
    end
    local sum, k = 0, 0
    for _, o in ipairs(R.defActors) do
        pcall(function()
            local h, mh = o.HealthInternal, o.MaxHealth
            if h > 0 and mh > 0 then sum, k = sum + math.min(1, h / (mh * 10)), k + 1 end
        end)
    end
    return k > 0 and math.floor(sum / k * 100 + 0.5) or nil
end

function ALLY.repairDefences()
    local n = repairActors(DEF_CLASSES)
    if n > 0 then log(string.format("allies: %d airfield defences repaired with the airfield", n)) end
    return n
end

function ALLY.repairAll()
    if not (CFG.allies.enabled and CFG.allies.repair and D) then return end
    local R, planesN = ALLY.state(), 0
    for _, p in ipairs(R.planes) do
        if valid(p.obj) and p.full then
            pcall(function()
                local h = p.obj.HealthInternal
                if h > 0 and h < p.full then p.obj.HealthInternal = p.full; planesN = planesN + 1 end
            end)
        end
    end
    local ships = next(ALLY.shipsAtSea()) and repairActors(SHIP_CLASSES) or 0
    local defs = repairActors(DEF_CLASSES)
    local n = planesN + ships + defs
    if n > 0 then
        local t = CFG.allies.text
        hudCallout(t.repaired, string.format(t.repaired_sub, n))
    end
    log(string.format("allies: repaired between rounds: %d aircraft, %d ship parts, %d airfield defences", planesN, ships, defs))
end

-- The allied aircraft's orders (CFG.allies.orders): R.order now, ALLY.nextOrder the next one (the STORE's row, Ctrl+F4)
function ALLY.order() return ALLY.state().order or CFG.allies.orders.default end

function ALLY.nextOrder(how)
    local R, list = ALLY.state(), CFG.allies.orders.list
    local cur, k = ALLY.order(), 1
    for i, o in ipairs(list) do if o == cur then k = i end end
    R.order = list[k % #list + 1]
    R.orderGiven, R.coverAt, RUN.dirty = {}, 0, true             -- (every airborne flight gets it on the next check)
    R.checkAt = 0
    local t = CFG.allies.text
    hudCallout(string.format(t.orders, R.order:upper()), t.orders_sub[R.order])
    log(string.format("allies: orders now %s (%s)", R.order, how or "?"))
    return R.order
end

-- The HUD's allies row: what's up and what it has shot down ("MOONCHILD 2  SHIPS 1  AA 3/5  KILLS 7  HUNT"), or nil
function ALLY.hudLine()
    local R = ALLY.run
    if not R then return nil end
    local parts, air = {}, {}
    for u, s in pairs(R.up) do                        -- (aircraft up; a flight waiting to take off shows 0)
        if s.kind == "air" then
            local n = airName(s)
            air[n] = (air[n] or 0) + ((s.queued or not nativeReady()) and 0 or math.max(0, SV_UnitAlive(u)))
        end
    end
    for n, k in pairs(air) do parts[#parts + 1] = string.format("%s %d", n, k) end
    local ships = #ALLY.shipsAtSea()
    if ships > 0 then parts[#parts + 1] = "SHIPS " .. ships end
    local dc = R.defCount
    if dc and (dc.aa > 0 or dc.sam > 0) then
        parts[#parts + 1] = string.format("AA %d  SAM %d", dc.aa, dc.sam) .. (R.defHp and string.format(" (%d%%)", R.defHp) or "")
    end
    local k = RUN.kills or {}
    local kills = (k.allies or 0) + (k.ships or 0) + (k.defences or 0)
    if #parts == 0 and kills == 0 then return nil end
    if kills > 0 then parts[#parts + 1] = "KILLS " .. kills end
    if next(air) then parts[#parts + 1] = ALLY.order():upper() end
    return table.concat(parts, "   ")
end

-- Strike flight `bomber` (a normal round's, sent at allied ship unit `ship`): RE_SV_Strike<ship>_NN once its own
-- orders (the airfield's, from its appearance) are in.
function ALLY.strike(bomber, ship)
    local i = BOMBER_INDEX[bomber]
    if not i then return end
    local R = ALLY.state()
    R.events[#R.events + 1] = { at = D.now + 4, name = string.format("RE_SV_Strike%s_%02d", (ship:gsub("^SV_Unit_Ship", "")), i),
                                why = bomber .. " at " .. ship }
    if D.strikeSaid ~= D.round then
        D.strikeSaid = D.round
        hudCallout(CFG.allies.text.strike, CFG.allies.text.strike_sub)
    end
end

function ALLY.tick(now)
    if not (CFG.allies.enabled and D and nativeReady()) then return end
    local R, c, t = ALLY.state(), CFG.allies, CFG.allies.text
    for _, u in ipairs(c.aircraft.units) do          -- a bought flight: off the ground once you are, runway clear
        local s = R.up[u]
        if s and s.queued and now >= R.nextTakeoff and not playerOnAirfield() then
            -- its airframe (the unit's AI objects take the row's aircraft: hard rule 15), WINGMEN's F-16C or MOONCHILD's F-22
            local w = c.wingmen
            local set = SV_SetAircraft(u, s.ally == "wingmen" and w.row or w.moonchild_row)
            if type(SV_SetLevel) == "function" then SV_SetLevel(u, ALLY.level(s).ai * 100) end
            spawningUnit = u
            local r = SV_Spawn(u)
            spawningUnit = nil
            local name = airName(s)
            if r > 0 then
                s.queued, s.at, R.nextTakeoff = nil, now, now + c.aircraft.takeoff_gap_s
                R.orderGiven = R.orderGiven or {}
                R.orderGiven[u] = nil                -- (its orders once it's airborne)
                hudCallout(string.format(t.takeoff, name), s.ally == "wingmen" and t.takeoff_sub_wingmen or t.takeoff_sub)
                log(string.format("allies: %s (%s) taxiing out: %d aircraft (airframe set %s)", name, u, r, tostring(set)))
            else
                s.tries, R.nextTakeoff = (s.tries or 0) + 1, now + 5
                log(string.format("allies: %s (%s) not spawned (%s)", name, u, SV_ERR[r] or tostring(r)))
                if s.tries >= 3 then                 -- never came: the zollars back
                    R.up[u] = nil
                    RUN.credits, RUN.spent, RUN.dirty = RUN.credits + (s.price or 0), RUN.spent - (s.price or 0), true
                    log(string.format("allies: %s (%s) couldn't take off; %d zollars back", name, u, s.price or 0))
                end
            end
        end
    end
    if now >= (R.checkAt or 0) then                  -- every 2 s: losses, scaling, orders, and the enemies' on the allies
        R.checkAt = now + 2
        ALLY.scale()
        local f, airborne = svFlags() or {}, 0
        R.orderGiven = R.orderGiven or {}
        for u, s in pairs(R.up) do
            if not s.queued then
                local n = SV_UnitAlive(u)
                if n <= 0 and now - s.at > 5 then
                    R.up[u], RUN.dirty = nil, true
                    local name = s.kind == "air" and airName(s) or c.ships[s.key].name
                    hudCallout(string.format(s.kind == "air" and t.air_lost or t.sunk, name), t.lost_sub)
                    log(string.format("allies: %s (%s) lost %.0f s after it %s", name, u, now - s.at,
                        s.kind == "air" and "spawned" or "sailed"))
                elseif s.kind == "air" and n > 0 then
                    local up = math.min(n, f["SV_AllyAir" .. u:sub(-1)] or 0)
                    airborne = airborne + up
                    -- its orders (CFG.allies.orders), once it's airborne and whenever they change; cover again and again
                    local order = ALLY.order()
                    local again = order == "cover" and now >= (R.coverAt or 0)
                    if up > 0 and (R.orderGiven[u] ~= order or again) and type(SV_Event) == "function" then
                        local ev = "RE_SV_Ally" .. order:sub(1, 1):upper() .. order:sub(2) .. u:sub(-1)
                        local r = SV_Event(ev)
                        if R.orderGiven[u] ~= order then
                            log(string.format("allies: %s (%s) ordered to %s: %s %s", airName(s), u, order, ev,
                                r == 1 and "fired" or ("not fired: " .. (SV_ERR[r] or tostring(r)))))
                        end
                        R.orderGiven[u] = order
                    end
                end
            end
        end
        if ALLY.order() == "cover" and now >= (R.coverAt or 0) then R.coverAt = now + c.orders.cover_every_s end
        if airborne ~= (R.airborne or 0) then log(string.format("allies: %d allied aircraft airborne", airborne)) end
        R.airborne = airborne
        -- an enemy fighter flight that's had its own orders (4 s up) while allied aircraft fly: hunt_share of them prefer
        -- them, and at least `hunters` a round (economy review: "hunter pairs that go for allies")
        if R.huntRound ~= D.round then R.huntRound, R.hunters = D.round, 0 end
        for u in pairs(R.seen) do if not D.up[u] then R.seen[u], R.hunted[u] = nil, nil end end
        for u in pairs(D.up) do
            local i = poolIndex(u)
            if i then
                R.seen[u] = R.seen[u] or now
                -- (not a Wolf flight while its trap is held, CFG.roles.wolf: the hunt's order would free it)
                if airborne > 0 and not R.hunted[u] and now - R.seen[u] >= 4 and not TAC.decoyed(u, now)
                    and not (WOLF and WOLF.holding(u)) then
                    R.hunted[u] = true
                    if math.random() < c.hunt_share or (R.hunters or 0) < (c.hunters or 0) then
                        R.hunters = (R.hunters or 0) + 1
                        R.events[#R.events + 1] = { at = now, why = u .. " hunts the allied aircraft",
                            name = string.format("RE_SV_Hunt_%02d", i) }
                    end
                end
            end
        end
        -- the airfield's defences: how many are up, and a warning for each one lost (economy review: "warn when one is lost")
        local d = CFG.shop.items.Airfield.defences
        R.defUp, R.defCount = R.defUp or {}, { aa = 0, sam = 0 }
        for _, kind in ipairs({ "aa", "sam" }) do
            for _, u in ipairs(d[kind].units) do
                local up = SV_UnitAlive(u) > 0
                if up then R.defCount[kind] = R.defCount[kind] + 1 end
                if R.defUp[u] and not up then
                    hudCallout(string.format(t.def_lost, d[kind].label), t.def_lost_sub)
                    log(string.format("allies: %s (%s) lost in round %d", d[kind].label, u, D.round))
                    RUN.dirty = true
                end
                R.defUp[u] = up
            end
        end
        local okD, hp = pcall(defenceHealth, R, now)
        R.defHp = okD and hp or nil
    end
    for i = #R.events, 1, -1 do
        local e = R.events[i]
        if now >= e.at then
            table.remove(R.events, i)
            local r = type(SV_Event) == "function" and SV_Event(e.name) or -5
            log(string.format("allies: %s (%s) %s", e.name, e.why, r == 1 and "fired" or ("not fired: " .. (SV_ERR[r] or tostring(r)))))
        end
    end
end
end
