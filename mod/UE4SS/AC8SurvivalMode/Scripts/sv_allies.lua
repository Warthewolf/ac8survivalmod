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
-- the CIWS's (0.72.1: tools/build_survival.py build_npc_rows, the game's land Phalanx GR033_ciws_01 on its allied model
-- row GR033_ciws_Ally), apart from ROWS as WINGMEN's; the airfield's defences as the Aegis's turrets, and each defence
-- row's kind (its health_add: CFG.shop.items.Airfield.defences[kind])
local CIWS_ROW = "SV_Def_Ciws"
ROW_SHIP[CIWS_ROW] = "Defence"
local DEF_ROW_KIND = { SV_Def_Gepa = "aa", SV_Def_Avng = "sam", [CIWS_ROW] = "ciws" }

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
        local fcsOf = { Defence = CFG.shop.items.Airfield.defences.fcs }    -- (the ships' and the airfield's defences')
        for key, sh in pairs(CFG.allies.ships) do fcsOf[key] = sh.fcs end
        for key, sf in pairs(fcsOf) do
            if sf and sf.search_m then
                local row, was = "NPC_AIModule_SV_" .. key, nil
                if cloneRow(modules, "NPC_AIModule_Turret000", row, function(r)
                    pcall(function() was = r.Radius end)
                    r.Radius = sf.search_m
                    pcall(function() r.bEnableLostTargetInClouds = false end)
                end) then
                    shipModule[key] = row
                    log(string.format("allies: %s turrets search %d m (%s%s), not lost in cloud",
                        key == "Defence" and "the airfield defences'" or (key .. "'s"), sf.search_m, row,
                        type(was) == "number" and string.format(", was %d m", math.floor(was)) or ""))
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
                local was = {}                       -- (the stock row's, for the log's before -> after)
                for _, f in ipairs({ "CaptureDistance", "ActivationTime", "TriggeringTime", "ShotIntervalTime", "RestingTime",
                                     "YawAngleMin", "YawAngleMax", "YawSpeed" }) do
                    pcall(function() was[f] = r[f] end)
                end
                pcall(function() r.CaptureDistance = r.CaptureDistance * (sf and sf.range_x or c.range_x) end)
                pcall(function() r.CaptureAngleRange = math.min(180, r.CaptureAngleRange * c.angle_x) end)
                for f, x in pairs({ ActivationTime = lockX, TriggeringTime = lockX, ShotIntervalTime = fireX, RestingTime = fireX }) do
                    pcall(function() r[f] = r[f] * x end)
                end
                local arc = ""                       -- (the turret: quicker round, all the way round)
                if sf and (sf.slew_x or sf.yaw_full) then
                    if sf.slew_x then
                        pcall(function() r.YawSpeed = r.YawSpeed * sf.slew_x end)
                        pcall(function() r.PitchSpeed = r.PitchSpeed * sf.slew_x end)
                    end
                    -- (a land mount on a ship mount's fire control, the CIWS's: +-60 deg of its front)
                    if sf.yaw_full then pcall(function() r.YawAngleMin, r.YawAngleMax = -180, 180 end) end
                    pcall(function()
                        arc = string.format(", yaw %.0f..%.0f at %.1f -> %.0f..%.0f at %.1f deg/s", was.YawAngleMin, was.YawAngleMax,
                            was.YawSpeed, r.YawAngleMin, r.YawAngleMax, r.YawSpeed)
                    end)
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
                            local w0 = {}
                            for _, f in ipairs({ "LifeTime", "SpeedMaxKmph", "AccelerationKmph", "MaxRotationAngle" }) do
                                pcall(function() w0[f] = x[f] end)
                            end
                            pcall(function() x.LifeTime = math.max(x.LifeTime, mc.life_s) end)
                            pcall(function() x.AccelerationKmph = x.AccelerationKmph * mc.accel_x end)
                            pcall(function() x.SpeedMaxKmph = math.max(x.SpeedMaxKmph, mc.speed_max_kmph) end)
                            pcall(function() x.MaxRotationAngle = x.MaxRotationAngle * mc.turn_x end)
                            pcall(function() x.HomingReductionInCloud = 0 end)
                            pcall(function()
                                what = string.format(", missile %s: %.1f -> %.0f s, up to %.0f -> %.0f km/h, +%.0f -> +%.0f km/h a second, turns %.1f -> %.1f",
                                    wn, w0.LifeTime, x.LifeTime, w0.SpeedMaxKmph, x.SpeedMaxKmph, w0.AccelerationKmph,
                                    x.AccelerationKmph, w0.MaxRotationAngle, x.MaxRotationAngle)
                            end)
                        elseif sf and sf.round_reach and not homing then
                            -- a gun's rounds out to its new lock-on range (r's, already grown): the AA guns' flak hurts
                            -- only inside its damage area (AAGUN_Ground_000: 2000 m long, 20 m round), the CIWS's
                            -- rounds fly LifeTime s (CIWS_Vessel_000: 3), longer by the range's growth
                            local len = 0
                            pcall(function() len = x.DamageAreaLengthMeters end)
                            if type(len) == "number" and len > 0 then
                                pcall(function()
                                    local rad = x.DamageAreaRadiusMeters
                                    x.DamageAreaLengthMeters = math.max(len, r.CaptureDistance)
                                    x.DamageAreaRadiusMeters = rad * (sf.round_width_x or 1)
                                    what = string.format(", rounds %s: hurt out to %.0f -> %.0f m, %.0f -> %.0f m round", wn,
                                        len, x.DamageAreaLengthMeters, rad, x.DamageAreaRadiusMeters)
                                end)
                            else
                                pcall(function()
                                    local life, grow = x.LifeTime, 1
                                    if type(was.CaptureDistance) == "number" and was.CaptureDistance > 0 then
                                        grow = math.max(1, r.CaptureDistance / was.CaptureDistance)
                                    end
                                    x.LifeTime = life * grow
                                    what = string.format(", rounds %s: %.1f -> %.1f s of flight", wn, life, x.LifeTime)
                                end)
                            end
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
                if sf then                           -- (the stock row's -> its own)
                    pcall(function()
                        shipSaid[#shipSaid + 1] = string.format("%s (within %d -> %d m, arm %.2f -> %.2f s, lock %.2f -> %.2f s, "
                            .. "%.2f -> %.2f s between, rest %.2f -> %.2f s%s%s%s)", new, math.floor(was.CaptureDistance or 0),
                            math.floor(r.CaptureDistance), was.ActivationTime or 0, r.ActivationTime, was.TriggeringTime or 0,
                            r.TriggeringTime, was.ShotIntervalTime or 0, r.ShotIntervalTime, was.RestingTime or 0, r.RestingTime,
                            shipModule[key] and (", search " .. shipModule[key]) or "", arc, what)
                    end)
                end
            end) and true or false
        end
        return made[new] and new or nil
    end
    local n = 0
    local all = { WINGMEN_ROW, CIWS_ROW }
    for _, row in ipairs(ROWS) do all[#all + 1] = row end
    local defs = CFG.shop.items.Airfield.defences
    for _, row in ipairs(all) do
        local _, have = dtCall(npc, "FindRow", row)
        if have == nil then
            local _, r = dtCall(mine, "FindRow", row)
            if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
        end
        if row == WINGMEN_ROW then ALLY.wingmenReady = have ~= nil end
        if row == CIWS_ROW then ALLY.ciwsReady = have ~= nil end
        if have ~= nil and row ~= WINGMEN_ROW and row ~= CIWS_ROW then n = n + 1 end
        local sh = ROW_SHIP[row] and CFG.allies.ships[ROW_SHIP[row]]
        local dk = DEF_ROW_KIND[row] and defs[DEF_ROW_KIND[row]]
        local add = (sh and row == "SV_Ally_" .. ROW_SHIP[row] and sh.health_add) or (dk and dk.health_add) or nil
        if have ~= nil and add and add ~= 0 then             -- a hull or an airfield defence: its own health
            local okH, h = pcall(function()                -- (once a session: ALLY.setup runs once, the row stays in)
                have.MaxHealthDifference = (have.MaxHealthDifference or 0) + add
                return have.MaxHealthDifference
            end)
            log(string.format("allies: %s %+d HP (%s's MaxHealthDifference now %s)", sh and (sh.name .. "'s hull") or
                ("the airfield's " .. (dk.label or row)), add, row, okH and tostring(h) or "NOT set"))
        end
        -- the CIWS's gun on fire control of its own (CFG.shop.items.Airfield.defences.ciws.fcs_row: the ships' Mk 15's,
        -- then the airfield's boost below); the game's GR033_ciws_01 names none, its blueprint's own arms fire (2500 m)
        if have ~= nil and row == CIWS_ROW then
            local fr = tostring(defs.ciws and defs.ciws.fcs_row or "")
            local cur = "?"
            pcall(function() cur = have.NpcFCSId0:ToString() end)
            if fr == "" or fr:lower() == "none" then
                log("allies: the CIWS fires on its blueprint's own fire control (fcs_row none; NpcFCSId0 " .. cur .. ")")
            elseif cur == "None" or cur == "" then
                local _, fr0 = dtCall(fcs, "FindRow", fr)
                local okF = false
                if fr0 ~= nil then okF = pcall(function() have.NpcFCSId0 = FName(fr) end) end
                log(string.format("allies: the CIWS's gun on %s: %s", fr, okF and "set (boosted below)"
                    or "NOT set (no such row in DT_NPC_FCS): its blueprint's own fire control"))
            end
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
    log(string.format("allies: %d of %d rows in DT_NPC%s, WINGMEN %s, CIWS %s, %d weapons on their own fire control (x%.1f range, x%.1f times), %d names set",
        n, #ROWS, #lost > 0 and (" (missing: " .. table.concat(lost, ", ") .. ")") or "", ALLY.wingmenReady and "in" or "NOT in",
        ALLY.ciwsReady and "in" or "NOT in", boosted, c.range_x, c.time_x, names))
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

-- A purchase (the shop takes the zollars when it succeeds): true and its message, or false and why not. `buyer`: a
-- co-op joiner's slot when the host buys it for them (sv_shop.lua shopBuildFor: they paid on their game), else nil
function ALLY.buy(role, unit, key, price, buyer)
    local R, t, now = ALLY.state(), CFG.allies.text, D and D.now or 0
    if role == "ally_ship" then
        local sh = CFG.allies.ships[key]
        spawningUnit = unit
        local r = SV_Spawn(unit)
        spawningUnit = nil
        log(string.format("allies: %s (%s): %s", sh.name, unit, r > 0 and "at sea" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
        if r <= 0 then return false, "COULD NOT SEND IT (" .. (SV_ERR[r] or tostring(r)) .. ")." end
        R.up[unit] = { kind = "ship", key = key, at = now, price = price, buyer = buyer }
        if not buyer then hudCallout(string.format(t.ship, sh.name), t.ship_sub) end
        return true, sh.name .. " AT SEA"
    end
    -- an allied flight on MOONCHILD's units: MOONCHILD's F-22s, or the cheaper WINGMEN (key "wingmen")
    local wing = key == "wingmen"
    local name = wing and CFG.allies.wingmen.name or CFG.allies.aircraft.name
    R.up[unit] = { kind = "air", ally = wing and "wingmen" or "moonchild", queued = true, at = now, price = price, buyer = buyer }
    log(string.format("allies: %s (%s) bought%s; it takes off once %s airborne", name, unit,
        buyer and string.format(" for player %d", buyer + 1) or "", buyer and "they're" or "you're"))
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
-- classes (BP_VE002_aegs_* / BP_GR002_gepa_CP / BP_GR005_avng_CP: the names the AI watch logged; the CIWS's
-- BP_GR033_ciws_CP_Ally, its DT_NPC_Model row GR033_ciws_Ally's blueprint), once a round.
local SHIP_CLASSES = { "BP_VE002_aegs_CP_C", "BP_VE002_aegs_mk15_01_CP_C", "BP_VE002_aegs_mk41_CP_C", "BP_VE002_aegs_mk45_CP_C" }
local DEF_CLASSES = { "BP_GR002_gepa_CP_C", "BP_GR005_avng_CP_C", "BP_GR033_ciws_CP_Ally_C" }
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
-- built, lost or gone from the list; read every 2 s), or nil when none is up. One that's down or no longer valid comes
-- off the list at once: a destroyed actor is freed at the game's next garbage collection, and a read of it after that
-- crashes the game inside UE4SS, pcall or not. The co-op run of 2026-10-31, three joiners' games: a resync ("rs")
-- took every copy here down and the host's defences spawned again at once, the count unchanged, so the old list was
-- kept and read every 2 s; all three crashed 4-9 s on (access violation in UE4SS's FindProperty, from a Lua read).
-- (ALLY.forgetActors: a co-op joiner's teardown drops the list too.)
local function defenceHealth(R, now)
    local n = 0
    for _, kind in ipairs(DEF_KINDS) do n = n + (R.defCount and R.defCount[kind] or 0) end
    if n == 0 then R.defActors = nil; return nil end
    if not R.defActors or R.defActorsN ~= n or now >= (R.defActorsAt or 0) then
        R.defActors, R.defActorsN, R.defActorsAt = {}, n, now + 30
        for _, cls in ipairs(DEF_CLASSES) do
            for _, o in ipairs(FindAllOf(cls) or {}) do
                if valid(o) and inSurvival(o) and not nameOf(o):find("Default__", 1, true) then
                    local ok, l, h = pcall(function() return o:K2_GetActorLocation(), o.HealthInternal end)
                    if ok and l and type(h) == "number" and h > 0
                        and math.sqrt((l.X - AIRFIELD.X) ^ 2 + (l.Y - AIRFIELD.Y) ^ 2) < 400000 then
                        R.defActors[#R.defActors + 1] = o
                    end
                end
            end
        end
    end
    local sum, k = 0, 0
    for i = #R.defActors, 1, -1 do
        local o, h, mh = R.defActors[i], nil, nil
        if valid(o) then
            local ok, a, b = pcall(function() return o.HealthInternal, o.MaxHealth end)
            if ok then h, mh = a, b end
        end
        if type(h) == "number" and type(mh) == "number" and h > 0 and mh > 0 then
            sum, k = sum + math.min(1, h / (mh * 10)), k + 1
        else
            table.remove(R.defActors, i)                  -- (down or gone: never read again; found again next time)
            R.defActorsAt = 0
        end
    end
    return k > 0 and math.floor(sum / k * 100 + 0.5) or nil
end

-- (sv_coop.lua killAllCopies: a co-op joiner took every copy down) the cached actors dropped before they're freed
function ALLY.forgetActors()
    local R = ALLY.run
    if R then R.defActors = nil end
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

function ALLY.nextOrder(how, to)
    local R, list = ALLY.state(), CFG.allies.orders.list
    local cur, k = ALLY.order(), 1
    for i, o in ipairs(list) do if o == cur then k = i end end
    R.order = list[k % #list + 1]
    for _, o in ipairs(list) do if o == to then R.order = to end end      -- (a set order: the host's, in co-op)
    -- (co-op: the allies are the host's, one order for the room: a joiner's change goes to the host, which sends it
    -- to everyone; sv_coop.lua "ao" / "ag")
    if COOP and COOP.orderChanged then pcall(COOP.orderChanged, R.order, how) end
    R.orderGiven, R.coverAt, RUN.dirty = {}, 0, true             -- (every airborne flight gets it on the next check)
    R.checkAt = 0
    local t = CFG.allies.text
    hudCallout(string.format(t.orders, R.order:upper()), t.orders_sub[R.order])
    log(string.format("allies: orders now %s (%s)", R.order, how or "?"))
    return R.order
end

-- The HUD's allies row: what's up and what it has shot down ("MOONCHILD 2  SHIPS 1  AA 3/5  KILLS 7  HUNT"), or nil;
-- and its news for the HUD's info key (sv_hud.lua): which flights, ships and defences are there and the order, not how
-- many, their health or the kills
local function airUp(R)
    local air = {}
    for u, s in pairs(R.up) do                        -- (aircraft up; a flight waiting to take off shows 0)
        if s.kind == "air" then
            local n = airName(s)
            air[n] = (air[n] or 0) + ((s.queued or not nativeReady()) and 0 or math.max(0, SV_UnitAlive(u)))
        end
    end
    return air
end

-- (co-op, the host) the room's allied flights and ships for the joiners' ALLIES rows, in "rnd": "m<n>w<n>s<n>", a
-- letter only for what's bought (m MOONCHILD's aircraft up, w the WINGMEN's, 0 while waiting to take off; s the ships
-- at sea). The allies are all the host's (a joiner's purchases are built here), so a joiner's own R.up stays empty and
-- its row showed only the defences, whose copies it counts itself (the user's co-op run of 2026-10-30).
function ALLY.roomCode()
    local R = ALLY.run
    if not R then return "" end
    local air, c = airUp(R), CFG.allies
    local m, w, ships = air[c.aircraft.name], air[c.wingmen.name], #ALLY.shipsAtSea()
    return (m and ("m" .. math.min(m, 99)) or "") .. (w and ("w" .. math.min(w, 99)) or "")
        .. (ships > 0 and ("s" .. math.min(ships, 99)) or "")
end

function ALLY.hudLine()
    local R = ALLY.run
    local room = COOP and COOP.roomAllies and COOP.roomAllies()   -- (a joiner: the host's, ALLY.roomCode)
    if not (R or room) then return nil end
    R = R or { up = {} }
    local parts, air, news = {}, {}, {}
    if room then
        air[CFG.allies.aircraft.name], air[CFG.allies.wingmen.name] = room.m, room.w
    else
        air = airUp(R)
    end
    for n, k in pairs(air) do parts[#parts + 1] = string.format("%s %d", n, k); news[#news + 1] = n end
    table.sort(news)                                  -- (pairs' order isn't news)
    local ships = room and (room.s or 0) or #ALLY.shipsAtSea()
    if ships > 0 then parts[#parts + 1] = "SHIPS " .. ships; news[#news + 1] = "SHIPS" end
    local dc = R.defCount
    local ciws = dc and dc.ciws or 0
    if dc and (dc.aa > 0 or dc.sam > 0 or ciws > 0) then
        parts[#parts + 1] = string.format("AA %d  SAM %d", dc.aa, dc.sam) .. (ciws > 0 and string.format("  CIWS %d", ciws) or "")
            .. (R.defHp and string.format(" (%d%%)", R.defHp) or "")
        news[#news + 1] = "DEFENCES"
    end
    local k = RUN.kills or {}
    local kills = (k.allies or 0) + (k.ships or 0) + (k.defences or 0)
    if #parts == 0 and kills == 0 then return nil end
    if kills > 0 then parts[#parts + 1] = "KILLS " .. kills end
    if next(air) then parts[#parts + 1] = ALLY.order():upper(); news[#news + 1] = ALLY.order() end
    return table.concat(parts, "   "), table.concat(news, " ")
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
        local ready
        if s and s.buyer then                        -- (a co-op joiner's: once they're airborne, or 90 s on)
            ready = (COOP and COOP.airborne and COOP.airborne(s.buyer)) or now - (s.at or now) >= 90
        else
            ready = not playerOnAirfield()
        end
        if s and s.queued and now >= R.nextTakeoff and ready then
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
                if s.tries >= 3 then                 -- never came: the zollars back (to the joiner who paid, if it was one)
                    R.up[u] = nil
                    if s.buyer then
                        if COOP and COOP.refund then COOP.refund(s.buyer, s.price or 0, name .. " COULD NOT TAKE OFF") end
                    else
                        RUN.credits, RUN.spent, RUN.dirty = RUN.credits + (s.price or 0), RUN.spent - (s.price or 0), true
                    end
                    log(string.format("allies: %s (%s) couldn't take off; %d zollars back%s", name, u, s.price or 0,
                        s.buyer and string.format(" to player %d", s.buyer + 1) or ""))
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
                    -- its orders (CFG.allies.orders), once it's airborne and whenever they change; cover again and again.
                    -- (co-op: a joiner's flight on cover covers that joiner while their real plane flies here: its area
                    -- the hunt's, over the whole map, and its planes onto the enemies nearest them, COOP.coverFor; the
                    -- stock cover's NearPlayer is your plane. Down, at their airfield or gone: it covers you.)
                    local order = ALLY.order()
                    local again = order == "cover" and now >= (R.coverAt or 0)
                    local theirs = order == "cover" and s.buyer and COOP and COOP.coverFor and COOP.realTarget
                        and COOP.realTarget(s.buyer) ~= nil
                    local given = theirs and ("cover:" .. s.buyer) or order
                    if up > 0 and (R.orderGiven[u] ~= given or again) and type(SV_Event) == "function" then
                        if R.orderGiven[u] ~= given then
                            local ev = "RE_SV_Ally" .. (theirs and "Hunt" or (order:sub(1, 1):upper() .. order:sub(2))) .. u:sub(-1)
                            local r = SV_Event(ev)
                            log(string.format("allies: %s (%s) ordered to %s%s: %s %s", airName(s), u, order,
                                theirs and string.format(" player %d (who bought it)", s.buyer + 1)
                                    or (order == "cover" and s.buyer and string.format(" you (player %d's plane isn't flying here)", s.buyer + 1)) or "",
                                ev, r == 1 and "fired" or ("not fired: " .. (SV_ERR[r] or tostring(r)))))
                        elseif not theirs then
                            SV_Event("RE_SV_Ally" .. order:sub(1, 1):upper() .. order:sub(2) .. u:sub(-1))
                        end
                        if theirs then
                            local objs = {}
                            for _, p in ipairs(R.planes) do if p.unit == u and valid(p.obj) then objs[#objs + 1] = p.obj end end
                            local okC, n, km = pcall(COOP.coverFor, s.buyer, objs)
                            local key = okC and (n > 0 and "on" or "none") or "err"
                            if s.coverSaid ~= key then
                                s.coverSaid = key
                                log(string.format("allies: %s (%s) covering player %d: %s", airName(s), u, s.buyer + 1,
                                    not okC and ("error " .. tostring(n)) or n > 0 and string.format(
                                    "%d of %d planes onto the enemies nearest them (the nearest %.1f km off)", n, #objs, km)
                                    or "no enemy near them"))
                            end
                        end
                        R.orderGiven[u] = given
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
                -- (not a Wolf flight while its trap is held, CFG.roles.wolf, nor one the squad director holds back,
                -- CFG.director: the hunt's order would free it)
                if airborne > 0 and not R.hunted[u] and now - R.seen[u] >= 4 and not TAC.decoyed(u, now)
                    and not (WOLF and WOLF.holding(u)) and not (DIR and DIR.holding and DIR.holding(u)) then
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
        R.defUp, R.defCount = R.defUp or {}, { aa = 0, sam = 0, ciws = 0 }
        for _, kind in ipairs(DEF_KINDS) do
            for _, u in ipairs(d[kind] and d[kind].units or {}) do
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
