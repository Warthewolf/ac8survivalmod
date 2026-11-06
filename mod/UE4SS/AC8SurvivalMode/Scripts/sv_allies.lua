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
-- (the Spaceport fleet's turrets, an enemy's: sv_spaceport.lua SPORT.FLEET_ROWS, their own fire control as a ship type's,
-- CFG.specials.spaceport.fcs; apart from ROWS, so the STORE's allies don't wait on them)
local FLEET_ROWS = SPORT and SPORT.FLEET_ROWS or {}
for _, row in ipairs(FLEET_ROWS) do ROW_SHIP[row] = "Fleet" end
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
-- VOID WATCHER 1's (CFG.allies.awacs: tools/build_survival.py, the E-767 Magnolia's row under SV_VoidWatcher), apart from
-- ROWS as WINGMEN's; its unit is an allied aircraft's (logPlane: no kill credit, repaired between rounds)
local AWACS_ROW = CFG.allies.awacs.row
ALLY.unit[CFG.allies.awacs.unit] = "air"
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
        local fcsOf = { Defence = CFG.shop.items.Airfield.defences.fcs,     -- (the ships' and the airfield's defences')
                        Fleet = CFG.specials.spaceport and CFG.specials.spaceport.fcs }
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
    -- A ship type's AA guns as flak guns (sf.flak; the user, 2026-10-31: "if you can't find an AA equivlant, change the AA
    -- to FLAK GUNS", "give the flak guns the same stats as the Boosted AA guns, I want them to be deadly"): the game has no
    -- ship flak, so the ground flak gun's fire control (flak.fcs, NPC_FCS_FlakGun000: its blueprint and FlakGun_000's
    -- 50-burst shells) on the mount's own arcs and the AA gun's timings (MOUNT), then every boost the AA gun had: lock-on
    -- and fire times, search, slew, accuracy (the bursts' scatter), width (the bursts' radius); its reach flak.range_m
    local MOUNT = { "YawAngleMin", "YawAngleMax", "PitchAngleMin", "PitchAngleMax", "CaptureAngleRange", "ActivationTime",
                    "TriggeringTime", "ShotIntervalTime", "RestingTime" }
    -- A ship type's missiles home as missile.homing_from's (EXSAM_Ground_000; the user, 2026-10-31: "theres a enemy in the
    -- game called EXSAM ... Take those stats and paste them over the ship guns and missiles"): these fields as its, the
    -- homing delay the shorter and the damage the larger of the two, then the boosts (turn_x on its turn rate)
    local HOMING = { "MaxHomingAngle", "MaxRotationAngle", "OmnidirectionalDuration", "OmnidirectionalAbility",
                     "DistanceFromTargetMeters", "AltitudeAboveTargetMeters" }
    local function allyFcs(src, key)                 -- src .. "_SVA[_<ship>]": farther, wider, quicker, tighter
        local sf = key and (key == "Defence" and CFG.shop.items.Airfield.defences.fcs
                            or key == "Fleet" and CFG.specials.spaceport and CFG.specials.spaceport.fcs
                            or CFG.allies.ships[key] and CFG.allies.ships[key].fcs)
        local new = src .. "_SVA" .. (sf and ("_" .. key) or "")
        local lockX, fireX = c.time_x * (sf and sf.lock_x or 1), c.time_x * (sf and sf.fire_x or 1)
        local fk = sf and type(sf.flak) == "table" and sf.flak.enabled ~= false and sf.flak or nil
        local flakFrom, mount = nil, nil
        if fk and fk.fcs and src:find("VesselAAGun", 1, true) and made[new] == nil then
            local _, ar = dtCall(fcs, "FindRow", src)
            local _, fr = dtCall(fcs, "FindRow", tostring(fk.fcs))
            if ar ~= nil and fr ~= nil then
                flakFrom, mount = tostring(fk.fcs), {}
                for _, f in ipairs(MOUNT) do pcall(function() mount[f] = ar[f] end) end
            else
                log(string.format("allies: %s's AA gun %s NOT on flak (%s): an AA gun as before", key, src,
                    ar == nil and "no such row" or ("no row " .. tostring(fk.fcs))))
            end
        end
        if made[new] == nil then
            made[new] = cloneRow(fcs, flakFrom or src, new, function(r)
                if mount then for f, v in pairs(mount) do pcall(function() r[f] = v end) end end   -- (the mount's arcs, the AA's timings)
                local was = {}                       -- (the stock row's, for the log's before -> after)
                for _, f in ipairs({ "CaptureDistance", "ActivationTime", "TriggeringTime", "ShotIntervalTime", "RestingTime",
                                     "YawAngleMin", "YawAngleMax", "YawSpeed" }) do
                    pcall(function() was[f] = r[f] end)
                end
                pcall(function() r.CaptureDistance = r.CaptureDistance * (sf and sf.range_x or c.range_x) end)
                -- (flak: its own reach, flak.range_m; the ground flak's 15 km is over twice the boosted AA guns')
                if flakFrom then pcall(function() r.CaptureDistance = tonumber(fk.range_m) or was.CaptureDistance end) end
                pcall(function() r.CaptureAngleRange = math.min(180, r.CaptureAngleRange * c.angle_x) end)
                for f, x in pairs({ ActivationTime = lockX, TriggeringTime = lockX, ShotIntervalTime = fireX, RestingTime = fireX }) do
                    pcall(function() r[f] = r[f] * x end)
                end
                -- (flak: its waits x flak.fire_x on top, the arming as it is; the user, 2026-10-31: "increase Flak firing")
                local ffx = flakFrom and tonumber(fk.fire_x) or nil
                if ffx and ffx ~= 1 then
                    for _, f in ipairs({ "TriggeringTime", "ShotIntervalTime", "RestingTime" }) do pcall(function() r[f] = r[f] * ffx end) end
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
                    elseif not flakFrom and (src:find("AAGun", 1, true) or src:find("CIWS", 1, true)) then   -- (flak: its own lead)
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
                        local homing = false
                        pcall(function() homing = x.bIsHoming == true end)
                        -- (a ship type's guns tighter still: sf.gun_spread_x on top of the allies' spread_x; the user,
                        -- 2026-10-31: "increase Ship AA gun accuracy")
                        local gx = (sf and not homing and tonumber(sf.gun_spread_x)) or 1
                        pcall(function() x.MaxSpawnAngle = x.MaxSpawnAngle * c.spread_x * gx end)
                        if flakFrom then             -- the flak's shells: the boosted AA guns' accuracy and width, deadlier
                            local w0 = {}
                            for _, f in ipairs({ "damage", "RandRangeMeters", "ImpactRadiusMeters", "HeightLimitRangeMinMeters" }) do
                                pcall(function() w0[f] = x[f] end)
                            end
                            pcall(function() x.damage = x.damage * (tonumber(fk.damage_x) or 1) end)
                            pcall(function() x.RandRangeMeters = x.RandRangeMeters * c.spread_x * (tonumber(sf.gun_spread_x) or 1) end)
                            pcall(function() x.ImpactRadiusMeters = x.ImpactRadiusMeters * (tonumber(sf.round_width_x) or 1) end)
                            if tonumber(fk.min_alt_m) then
                                pcall(function() x.HeightLimitRangeMinMeters = math.min(x.HeightLimitRangeMinMeters, tonumber(fk.min_alt_m)) end)
                            end
                            pcall(function()
                                what = string.format(", flak %s: damage %.0f -> %.0f, bursts within %.0f -> %.0f m, %.0f -> %.0f m round, "
                                    .. "from %.0f -> %.0f m up", wn, w0.damage, x.damage, w0.RandRangeMeters, x.RandRangeMeters,
                                    w0.ImpactRadiusMeters, x.ImpactRadiusMeters, w0.HeightLimitRangeMinMeters, x.HeightLimitRangeMinMeters)
                            end)
                        elseif mc and homing then    -- a homing missile: flies long enough to reach range_m
                            missile = true
                            local w0 = {}
                            for _, f in ipairs({ "LifeTime", "SpeedMaxKmph", "AccelerationKmph", "MaxRotationAngle" }) do
                                pcall(function() w0[f] = x[f] end)
                            end
                            local hf, hs = mc.homing_from and tostring(mc.homing_from) or "", ""
                            if hf ~= "" and hf:lower() ~= "none" and hf ~= w then   -- (homing as another missile's first)
                                local _, hr = dtCall(wpn, "FindRow", hf)
                                local n = 0
                                if hr ~= nil then
                                    for _, f in ipairs(HOMING) do
                                        pcall(function() local v = hr[f]; if type(v) == "number" then x[f] = v; n = n + 1 end end)
                                    end
                                    pcall(function() x.HomingDelayFromStart = math.min(x.HomingDelayFromStart, hr.HomingDelayFromStart) end)
                                    pcall(function() x.damage = math.max(x.damage, hr.damage) end)
                                end
                                hs = hr ~= nil and string.format(", homing as %s (%d of %d)", hf, n, #HOMING)
                                    or (", homing NOT as " .. hf .. " (no such row)")
                            end
                            pcall(function() x.LifeTime = math.max(x.LifeTime, mc.life_s) end)
                            pcall(function() x.AccelerationKmph = x.AccelerationKmph * mc.accel_x end)
                            pcall(function() x.SpeedMaxKmph = math.max(x.SpeedMaxKmph, mc.speed_max_kmph) end)
                            pcall(function() x.MaxRotationAngle = x.MaxRotationAngle * mc.turn_x end)
                            pcall(function() x.HomingReductionInCloud = 0 end)
                            pcall(function()
                                what = string.format(", missile %s: %.1f -> %.0f s, up to %.0f -> %.0f km/h, +%.0f -> +%.0f km/h a second, turns %.1f -> %.1f",
                                    wn, w0.LifeTime, x.LifeTime, w0.SpeedMaxKmph, x.SpeedMaxKmph, w0.AccelerationKmph,
                                    x.AccelerationKmph, w0.MaxRotationAngle, x.MaxRotationAngle) .. hs
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
                        if mc and not missile and not flakFrom then
                            pcall(function() local _, wr = dtCall(wpn, "FindRow", wn); missile = wr ~= nil and wr.bIsHoming == true end)
                        end
                        if missile then pcall(function() r.CaptureDistance = mc.range_m end) end
                        -- (its salvos closer together: missile.salvo_x on the time between shots and the rest after a
                        -- volley, homing missiles only; the user, 2026-10-31: "Slightly ... no I want less waiting
                        -- between firing")
                        local sx = missile and tonumber(mc.salvo_x) or nil
                        if sx and sx ~= 1 then
                            pcall(function() r.ShotIntervalTime, r.RestingTime = r.ShotIntervalTime * sx, r.RestingTime * sx end)
                        end
                        -- (bigger salvos: missile.salvo_n missiles a salvo, salvo_gap_s apart, as the game's 2AAM / 4AAM
                        -- fire theirs (TriggerCount shots ShotIntervalTime apart over TriggeringTime = count x interval,
                        -- then RestingTime); the user, 2026-10-31: "increase missile salvos")
                        local sn = missile and math.floor(tonumber(mc.salvo_n) or 1) or 1
                        if sn > 1 then
                            local gap = tonumber(mc.salvo_gap_s) or 0.5
                            pcall(function()
                                r.TriggerCount = math.max(r.TriggerCount, sn)
                                r.ShotIntervalTime = gap
                                r.TriggeringTime = r.TriggerCount * gap
                                r.MagazineCapacity = math.max(r.MagazineCapacity, r.TriggerCount)
                                what = what .. string.format(", salvos of %d, %.2f s apart", r.TriggerCount, gap)
                            end)
                        end
                    end
                end)
                if sf then                           -- (the stock row's -> its own)
                    pcall(function()
                        shipSaid[#shipSaid + 1] = string.format("%s (%swithin %d -> %d m, arm %.2f -> %.2f s, lock %.2f -> %.2f s, "
                            .. "%.2f -> %.2f s between, rest %.2f -> %.2f s%s%s%s)", new,
                            flakFrom and ("an AA gun on " .. flakFrom .. "'s fire control, ") or "", math.floor(was.CaptureDistance or 0),
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
    local all = { WINGMEN_ROW, CIWS_ROW, AWACS_ROW }
    for _, row in ipairs(ROWS) do all[#all + 1] = row end
    for _, row in ipairs(FLEET_ROWS) do all[#all + 1] = row end
    local fleetIn = 0
    local defs = CFG.shop.items.Airfield.defences
    for _, row in ipairs(all) do
        local _, have = dtCall(npc, "FindRow", row)
        if have == nil then
            local _, r = dtCall(mine, "FindRow", row)
            if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
        end
        if row == WINGMEN_ROW then ALLY.wingmenReady = have ~= nil end
        if row == CIWS_ROW then ALLY.ciwsReady = have ~= nil end
        if row == AWACS_ROW then
            -- (its model row into DT_NPC_Model first: Survival's copy of Magnolia's under the plain E-767 name; without
            -- it the row names a model the game hasn't, and it isn't sold)
            local mt, mr = loadObject(ACE.model_table), loadObject(ACE.model_rows)
            for _, t in ipairs({ mt, mr }) do if t then pin(t, nameOf(t)) end end
            local mk = CFG.allies.awacs.model
            local _, mh = nil, nil
            if mt then _, mh = dtCall(mt, "FindRow", mk) end
            if mh == nil and mt and mr then
                local _, r = dtCall(mr, "FindRow", mk)
                if r ~= nil then dtCall(mt, "AddRow", mk, r); _, mh = dtCall(mt, "FindRow", mk) end
            end
            log(string.format("allies: %s's model %s %s", CFG.allies.awacs.name, mk, mh ~= nil and "in DT_NPC_Model" or "NOT added"))
            ALLY.awacsReady = have ~= nil and mh ~= nil
        end
        if have ~= nil and ROW_SHIP[row] == "Fleet" then fleetIn = fleetIn + 1
        elseif have ~= nil and row ~= WINGMEN_ROW and row ~= CIWS_ROW and row ~= AWACS_ROW then n = n + 1 end
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
                        -- (VOID WATCHER 1's ESM: its fire control reaches capture_m, ready again at once)
                        if new and row == AWACS_ROW and id:find("ESM", 1, true) then
                            local esm = CFG.allies.awacs.esm
                            local _, fr = dtCall(fcs, "FindRow", new)
                            local okE = fr ~= nil and pcall(function()
                                fr.CaptureDistance = esm.capture_m
                                fr.CaptureAngleRange = 180
                                fr.RestingTime, fr.ShotIntervalTime = 0.5, 0.5
                            end)
                            log(string.format("allies: %s's ESM on %s: within %d m, ready again in 0.5 s%s", CFG.allies.awacs.name,
                                new, esm.capture_m, okE and "" or " (NOT set)"))
                        end
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
        if SV_SetText(CFG.allies.awacs.name_key, CFG.allies.awacs.name) == 1 then names = names + 1 end
        for key, sh in pairs(CFG.allies.ships) do if SV_SetText("SV_Ship_" .. key, sh.name) == 1 then names = names + 1 end end
    end
    ALLY.ready = n == #ROWS
    ALLY.fleetReady = #FLEET_ROWS > 0 and fleetIn == #FLEET_ROWS
    log(string.format("allies: the Spaceport fleet's turrets: %d of %d rows in DT_NPC on their own fire control (search %s m)%s",
        fleetIn, #FLEET_ROWS, tostring(CFG.specials.spaceport and CFG.specials.spaceport.fcs and CFG.specials.spaceport.fcs.search_m),
        ALLY.fleetReady and "" or ": no Spaceport Assault"))
    if #shipSaid > 0 then log("allies: the ships' and the airfield's own fire control: " .. table.concat(shipSaid, ", ")) end
    if #gunSaid > 0 then log("allies: guns: " .. table.concat(gunSaid, ", ")) end
    log(string.format("allies: %d of %d rows in DT_NPC%s, WINGMEN %s, CIWS %s, %s %s, %d weapons on their own fire control (x%.1f range, x%.1f times), %d names set",
        n, #ROWS, #lost > 0 and (" (missing: " .. table.concat(lost, ", ") .. ")") or "", ALLY.wingmenReady and "in" or "NOT in",
        ALLY.ciwsReady and "in" or "NOT in", CFG.allies.awacs.name, ALLY.awacsReady and "in" or "NOT in", boosted, c.range_x,
        c.time_x, names))
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
        if R.alive then R.alive[unit] = nil end      -- ((0.73.77) its count asked afresh: ALLY.alive)
        if not buyer then hudCallout(string.format(t.ship, sh.name), t.ship_sub) end
        return true, sh.name .. " AT SEA"
    end
    if role == "ally_awacs" then                     -- VOID WATCHER 1: its own unit, off the ground as MOONCHILD is
        local aw = CFG.allies.awacs
        R.up[unit] = { kind = "air", ally = "awacs", queued = true, at = now, price = price, buyer = buyer }
        log(string.format("allies: %s (%s) bought%s; it takes off once %s airborne", aw.name, unit,
            buyer and string.format(" for player %d", buyer + 1) or "", buyer and "they're" or "you're"))
        return true, aw.name .. " TAKES OFF ONCE YOU'RE AIRBORNE"
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
local function airName(s)
    if s and s.ally == "awacs" then return CFG.allies.awacs.name end
    return (s and s.ally == "wingmen") and CFG.allies.wingmen.name or CFG.allies.aircraft.name
end
local function airScale(s)
    if s and s.ally == "awacs" then return CFG.allies.awacs.scale or {} end
    return ((s and s.ally == "wingmen") and CFG.allies.wingmen.scale or CFG.allies.aircraft.scale) or {}
end

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
-- (p.full: its full health now, what the repairs between rounds bring it back to).
-- (0.73.73) Raised by the growth past the most it's been raised to (p.hx never comes down), so a round number that goes
-- back and forth can't raise it again: each co-op resync flipped a joiner's D.round to 0 and back, and its copy of the
-- host's VOID WATCHER grew x1.56 every time (Shazzy's A02 11:17:51: "health x3.12 (74399 -> 116062)"; A04 13:39:41
-- 210659 -> 396039; the host's own 6.5-7.6k). And a co-op joiner's allied planes are all copies of the host's (a joiner's
-- purchases are built by the host): their health is the host's ("hp", sv_coop.lua), only their rank is set here.
function ALLY.scale()
    local R = ALLY.state()
    if #R.planes == 0 then return end
    local hostsCopies = COOP ~= nil and COOP.client ~= nil and COOP.client() == true
    for i = #R.planes, 1, -1 do
        local p = R.planes[i]
        if not liveAddr(p.obj) then table.remove(R.planes, i)
        elseif p.round ~= D.round then
            local L = ALLY.level(R.up[p.unit])
            p.round = D.round
            pcall(function() p.obj.PilotRank = L.rank end)
            if hostsCopies then
                if not p.copySaid then
                    p.copySaid = true
                    log(string.format("allies: %s (%s) is the host's: PilotRank %d here, its health the host's", p.name, p.unit, L.rank))
                end
            else
                local was = p.hx or 1
                local grow = L.hx > was
                p.hx = math.max(was, L.hx)
                local ok, h0, h1 = pcall(function()
                    local h = p.obj.HealthInternal
                    if grow and h > 0 then p.obj.HealthInternal = math.floor(h * L.hx / was + 0.5) end
                    return h, p.obj.HealthInternal
                end)
                if ok then
                    local okM, mh = pcall(function() return p.obj.MaxHealth end)
                    p.full = (okM and type(mh) == "number") and math.floor(mh * 10 * p.hx + 0.5) or math.max(p.full or 0, h1 or 0)
                end
                log(string.format("allies: %s (%s) at round %d's level (%s): PilotRank %d, health x%.2f (%s -> %s)%s", p.name, p.unit,
                    D.round, L.tier, L.rank, p.hx, ok and tostring(h0) or "?", ok and tostring(h1) or "?",
                    grow and "" or string.format(" (not raised: this round's x%.2f it's had already)", L.hx)))
            end
        end
    end
end

-- CFG.allies.repair: between rounds every allied aircraft, ship (hull and turrets) and airfield defence still up back
-- to full health (economy review of 2026-10-25: "allies who last"). The ships' and defences' actors are found by their
-- classes (BP_VE002_aegs_* / BP_GR002_gepa_CP / BP_GR005_avng_CP: the names the AI watch logged; the CIWS's
-- BP_GR033_ciws_CP_Ally, its DT_NPC_Model row GR033_ciws_Ally's blueprint), once a round.
local SHIP_CLASSES = { "BP_VE002_aegs_CP_C", "BP_VE002_aegs_mk15_01_CP_C", "BP_VE002_aegs_mk41_CP_C", "BP_VE002_aegs_mk45_CP_C" }
local DEF_CLASSES = { "BP_GR002_gepa_CP_C", "BP_GR005_avng_CP_C", "BP_GR033_ciws_CP_Ally_C" }
local function healOne(o)
    local ok, done = pcall(function()
        local h, mh = o.HealthInternal, o.MaxHealth
        if h > 0 and mh > 0 and h < math.floor(mh * 10) then o.HealthInternal = math.floor(mh * 10); return true end
        return false
    end)
    return ok and done == true
end
local function repairActors(classes)
    local n = 0
    for _, cls in ipairs(classes) do
        for _, o in ipairs(FindAllOf(cls) or {}) do
            if valid(o) and inSurvival(o) and not nameOf(o):find("Default__", 1, true) and healOne(o) then n = n + 1 end
        end
    end
    return n
end
-- ((0.73.79, the lag audit's item 7) The defences' repair walked DEF_CLASSES (three walks over every object, 105-150 ms
-- on a tester's PC) at every round clear even with none bought. With none of the STORE's defences up (R.defCount, from
-- their units) only the shuttle pad's objects of those classes are left in the level, and they're recorded as they
-- spawn (SHUTTLE.pad, sv_spawn.lua): healed from that record, each checked live first)
local function defencesUp()
    local R, n = ALLY.state(), 0
    if type(R.defCount) ~= "table" then return nil end   -- (not counted: [allies] off, or no tick yet)
    for _, kind in ipairs(DEF_KINDS or {}) do n = n + (R.defCount[kind] or 0) end
    return n
end
local function repairDefenceActors()
    local up = defencesUp()
    if up == nil or up > 0 then return repairActors(DEF_CLASSES) end
    local want, n = {}, 0
    for _, cls in ipairs(DEF_CLASSES) do want[#want + 1] = cls:gsub("_C$", "") .. "_C_" end
    for _, l in pairs(SHUTTLE and SHUTTLE.pad or {}) do
        for _, o in ipairs(l) do
            if liveAddr(o) then
                local nm = nameOf(o)
                for _, k in ipairs(want) do
                    if nm:find(k, 1, true) then
                        if healOne(o) then n = n + 1 end
                        break
                    end
                end
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
-- (0.73.77, Workstream B3) Run every tick now: the actors are found again one class a tick (DEF_CLASSES' three walks
-- over every object in one tick, every 30 s and after every loss, were the allies part's worst tick, 123-144 ms in the
-- testers' host logs of 2026-11-01), when the count changes, one is lost or every DEF_WALK_S (was 30); their health read
-- every 2 s as before. A kept actor is checked with liveAddr (GUObjectArray), not valid(), before each read.
local DEF_WALK_S = 120
local function defenceHealth(R, now)
    local n = 0
    for _, kind in ipairs(DEF_KINDS) do n = n + (R.defCount and R.defCount[kind] or 0) end
    if n == 0 then R.defActors, R.defWalk = nil, nil; return nil end
    if not R.defWalk and (not R.defActors or R.defActorsN ~= n or now >= (R.defActorsAt or 0)) then
        R.defWalk = { i = 0, list = {}, n = n }
    end
    local w = R.defWalk
    if w then                                             -- (one class this tick)
        w.i = w.i + 1
        for _, o in ipairs(FindAllOf(DEF_CLASSES[w.i]) or {}) do
            if valid(o) and inSurvival(o) and not nameOf(o):find("Default__", 1, true) then
                local ok, l, h = pcall(function() return o:K2_GetActorLocation(), o.HealthInternal end)
                if ok and l and type(h) == "number" and h > 0
                    and math.sqrt((l.X - AIRFIELD.X) ^ 2 + (l.Y - AIRFIELD.Y) ^ 2) < 400000 then
                    w.list[#w.list + 1] = o
                end
            end
        end
        if w.i < #DEF_CLASSES then return R.defHp end
        R.defActors, R.defActorsN, R.defActorsAt, R.defWalk, R.defHpAt = w.list, w.n, now + DEF_WALK_S, nil, nil
        if not R.defWalkSaid then
            R.defWalkSaid = true
            log(string.format("allies: the airfield defences' actors found one class a tick: %d for %d up (again when that "
                .. "changes or in %d s; 0.73.77)", #w.list, n, DEF_WALK_S))
        end
    end
    if not R.defActors then return nil end
    if now < (R.defHpAt or 0) then return R.defHp end     -- (their health every 2 s)
    R.defHpAt = now + 2
    local sum, k = 0, 0
    for i = #R.defActors, 1, -1 do
        local o, h, mh = R.defActors[i], nil, nil
        if liveAddr(o) then
            local ok, a, b = pcall(function() return o.HealthInternal, o.MaxHealth end)
            if ok then h, mh = a, b end
        end
        if type(h) == "number" and type(mh) == "number" and h > 0 and mh > 0 then
            sum, k = sum + math.min(1, h / (mh * 10)), k + 1
        else
            table.remove(R.defActors, i)                  -- (down or gone: never read again; found again next tick on)
            R.defActorsAt = 0
        end
    end
    return k > 0 and math.floor(sum / k * 100 + 0.5) or nil
end

-- (sv_coop.lua killAllCopies: a co-op joiner took every copy down) the cached actors dropped before they're freed
-- ((0.73.77) a look for them that's under way too)
function ALLY.forgetActors()
    local R = ALLY.run
    if R then R.defActors, R.defWalk = nil, nil end
end

-- (0.73.77, Workstream B3) Each allied and defence unit's SV_UnitAlive, a share each tick (as the plane sweep visits an
-- eighth of the planes): the native walks the spawner's whole unit list for each ask, and ALLY.tick asked for every
-- bought ally and all ten defence units in one tick every 2 s. ALLY.alive(u, now): the count read for it in the last
-- 2.5 s of the round clock (now, else D.now), else asked now; one that has none up (a defence not built, a flight
-- not bought) is good for ALIVE_IDLE_S (a spawn here forgets its count: ALLY.forgetAlive). Visited: R.up's units and
-- every defence unit, unit i on the tick where i % SHARE is the slot, one with none up every other visit.
-- ((0.73.83) the 0.73.79 run of 2026-11-04, verified twice: at ~7 ms an ask late in a long run, the share and airUp's
-- asks were 12-14 ms a tick of 'allies'. Each unit is asked every 4 s now (SHARE 16, a loss seen up to 4 s later), and
-- airUp reads these counts.)
local ALIVE_FRESH_S, ALIVE_IDLE_S, SHARE = 4.5, 8.5, 16
function ALLY.alive(u, now)
    now = now or (D and D.now) or 0
    local R = ALLY.run
    local e = R and R.alive and R.alive[u]
    if e and now >= e.at and now - e.at <= ((e.n or 0) > 0 and ALIVE_FRESH_S or ALIVE_IDLE_S) then return e.n end
    local n = SV_UnitAlive(u)
    if R then R.alive = R.alive or {}; R.alive[u] = { n = n, at = now } end
    return n
end
function ALLY.forgetAlive(u)                          -- (a unit just spawned: its count asked afresh)
    local R = ALLY.run
    if R and R.alive then R.alive[u] = nil end
end
local function aliveShare(R, now)
    R.alive = R.alive or {}
    R.aliveSlot = ((R.aliveSlot or -1) + 1) % SHARE
    local units, i = {}, 0
    for u in pairs(R.up) do units[#units + 1] = u end
    table.sort(units)                                     -- (pairs' order changes: the same unit, the same slot)
    local d = CFG.shop.items.Airfield.defences
    for _, kind in ipairs(DEF_KINDS) do
        for _, u in ipairs(d[kind] and d[kind].units or {}) do units[#units + 1] = u end
    end
    for _, u in ipairs(units) do
        i = i + 1
        local e = R.alive[u]
        if i % SHARE == R.aliveSlot and not (e and (e.n or 0) <= 0 and now >= e.at and now - e.at < ALIVE_IDLE_S - 0.5) then
            R.alive[u] = { n = SV_UnitAlive(u), at = now }
        end
    end
end

function ALLY.repairDefences()
    local n = repairDefenceActors()
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
    local defs = repairDefenceActors()
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
        -- ((0.73.78, G5) VOID WATCHER 1 going home isn't counted: not in the room's code, hudLine names it so)
        if s.kind == "air" and not s.home then
            local n = airName(s)
            -- ((0.73.83) the share's count: twice a second from the room's code and the HUD, it asked the native each time)
            air[n] = (air[n] or 0) + ((s.queued or not nativeReady()) and 0 or math.max(0, ALLY.alive(u)))
        end
    end
    return air
end

-- (co-op, the host) the room's allied flights and ships for the joiners' ALLIES rows, in "rnd": "m<n>w<n>s<n>", a
-- letter only for what's bought (m MOONCHILD's aircraft up, w the WINGMEN's, 0 while waiting to take off; s the ships
-- at sea; v VOID WATCHER 1, none once it's going home: (0.73.78) airUp). The allies are all the host's (a joiner's purchases are built here), so a joiner's own R.up stays empty and
-- its row showed only the defences, whose copies it counts itself (the user's co-op run of 2026-10-30).
function ALLY.roomCode()
    local R = ALLY.run
    if not R then return "" end
    local air, c = airUp(R), CFG.allies
    local m, w, v, ships = air[c.aircraft.name], air[c.wingmen.name], air[c.awacs.name], #ALLY.shipsAtSea()
    return (m and ("m" .. math.min(m, 99)) or "") .. (w and ("w" .. math.min(w, 99)) or "")
        .. (v and ("v" .. math.min(v, 99)) or "") .. (ships > 0 and ("s" .. math.min(ships, 99)) or "")
end

function ALLY.hudLine()
    local R = ALLY.run
    local room = COOP and COOP.roomAllies and COOP.roomAllies()   -- (a joiner: the host's, ALLY.roomCode)
    if not (R or room) then return nil end
    R = R or { up = {} }
    local parts, air, news = {}, {}, {}
    if room then
        air[CFG.allies.aircraft.name], air[CFG.allies.wingmen.name], air[CFG.allies.awacs.name] = room.m, room.w, room.v
    else
        air = airUp(R)
    end
    for n, k in pairs(air) do                         -- (VOID WATCHER 1 by its name: "1" is in it)
        parts[#parts + 1] = n == CFG.allies.awacs.name and (k > 0 and n or (n .. " (ON THE GROUND)")) or string.format("%s %d", n, k)
        news[#news + 1] = n
    end
    table.sort(news)                                  -- (pairs' order isn't news)
    local home = not room and R.up[CFG.allies.awacs.unit]          -- ((0.73.78, G5) its service over, on its way out)
    if home and home.home then
        parts[#parts + 1] = CFG.allies.awacs.name .. " (GOING HOME)"
        news[#news + 1] = CFG.allies.awacs.name .. " HOME"
    end
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

-- (0.73.73) VOID WATCHER 1's ESM field o, new ("new") or launched again from the pool ("again"): its range and time
-- ours. Logged: the first two new ones (as before), the first two launched again, then every 25th.
local ESM_KEYS = { "SupportEffectRangeMeter", "EffectRangeMeter", "LifeTime" }
local function esmSet(R, aw, o, how)
    local was, now2 = {}, {}
    for _, k in ipairs(ESM_KEYS) do pcall(function() was[k] = o[k] end) end
    pcall(function() o.SupportEffectRangeMeter = aw.esm.range_m end)
    pcall(function() o.EffectRangeMeter = aw.esm.range_m end)
    pcall(function() o.LifeTime = aw.esm.life_s end)
    R.esmSet = (R.esmSet or 0) + 1
    local again = how == "again"
    local n
    if again then R.esmAgain = (R.esmAgain or 0) + 1; n = R.esmAgain else R.esmNewN = (R.esmNewN or 0) + 1; n = R.esmNewN end
    if (not again and n > 2) or (again and n > 2 and n % 25 ~= 0) then return end
    for _, k in ipairs(ESM_KEYS) do pcall(function() now2[k] = o[k] end) end
    log(string.format("allies: %s's ESM field %s%s: support range %s -> %s m, range %s -> %s m, life %s -> %s s", aw.name,
        nameOf(o):match("([^%.:]+)$") or "?", again and string.format(" launched again (pooled; %d so far)", n) or "",
        tostring(was.SupportEffectRangeMeter), tostring(now2.SupportEffectRangeMeter), tostring(was.EffectRangeMeter),
        tostring(now2.EffectRangeMeter), tostring(was.LifeTime), tostring(now2.LifeTime)))
end

-- (0.73.78, plan G5: "3 rounds of service, rising price, 8-10 km field, a strike flight after it"; a tester of the
-- 5-player run of 2026-11-02: it "wins the fight for you", one bought in round 16 lasted 92 minutes, to round 34)
-- VOID WATCHER 1's plane up here and its km from the airfield, or nil
local function awacsPlane(R, u)
    for _, p in ipairs(R.planes) do
        if p.unit == u and liveAddr(p.obj) then
            local okL, l = pcall(function() return p.obj:K2_GetActorLocation() end)
            if okL and l then return p.obj, math.sqrt((l.X - AIRFIELD.X) ^ 2 + (l.Y - AIRFIELD.Y) ^ 2) / 100000 end
            return p.obj, nil
        end
    end
    return nil, nil
end
-- Its service (CFG.allies.awacs.service, home): a round counted as it clears with it up service.min_s or more of it;
-- service.rounds counted, it's sent home (RE_SV_AwacsHome: the end of the arc it's on starts its exit, tools/
-- survival_events.py AWACS_OUT_*); once it's gone_km out, its exit flown (SV_AwacsOut 2) or max_s on (area_s on the
-- backstop's area orbit, where no arc ends) it's taken off (RE_SV_AwacsRemove), and 2 s later off the spawner's list
-- (SV_Recycle(unit, 1): a despawned unit can still count alive, and SV_Spawn spawns it again only once it's off) and
-- out of R.up: the STORE sells another. s.removeAt keeps ALLY.tick's loss check from calling it lost meanwhile.
local function awacsService(R, s, now, f)
    local aw, t = CFG.allies.awacs, CFG.allies.text
    local sv, hm, u = aw.service or {}, aw.home or {}, aw.unit
    if s.removeAt then
        if now < s.removeAt + 2 then return end
        local rec = "no SV_Recycle in this runtime: the STORE's next one may not spawn"
        if type(SV_Recycle) == "function" then
            local okR, r = pcall(SV_Recycle, u, 1)
            rec = okR and ("SV_Recycle " .. tostring(r)) or ("SV_Recycle error " .. tostring(r))
        end
        R.up[u], RUN.dirty = nil, true
        if ALLY.forgetAlive then ALLY.forgetAlive(u) end
        log(string.format("allies: %s home after %d rounds (%s): off the spawner's list (%s); the STORE can send another",
            aw.name, s.served or 0, s.goneWhy or "?", rec))
        return
    end
    if s.home then
        if now < (R.homeCheckAt or 0) then return end
        R.homeCheckAt = now + 2
        local _, d = awacsPlane(R, u)
        local why
        if (tonumber(f.SV_AwacsOut) or 0) >= 2 then why = "its exit flown"
        elseif d and d >= (hm.gone_km or 20) then why = string.format("%.1f km out", d)
        elseif s.areaOrbit and now - s.home >= (hm.area_s or 30) then why = string.format("%d s on the area orbit, no arc to leave from", hm.area_s or 30)
        elseif now - s.home >= (hm.max_s or 360) then why = string.format("%d s after it was sent home", hm.max_s or 360)
        end
        if s.outSaid ~= (tonumber(f.SV_AwacsOut) or 0) then
            s.outSaid = tonumber(f.SV_AwacsOut) or 0
            if s.outSaid == 1 then
                log(string.format("allies: %s on its way out (its arc's end took its exit, %s)", aw.name,
                    d and string.format("%.1f km from the airfield", d) or "?"))
            end
        end
        if why then
            s.removeAt, s.goneWhy = now, why
            if COOP and COOP.removeNow then pcall(COOP.removeNow, u) end   -- ((0.73.83) the joiners' copies down first)
            local r = type(SV_Event) == "function" and SV_Event(hm.remove) or -5
            log(string.format("allies: %s taken off (%s): %s %s", aw.name, why, hm.remove,
                r == 1 and "fired" or ("NOT fired: " .. (SV_ERR[r] or tostring(r)))))
        end
        return
    end
    local rounds = tonumber(sv.rounds) or 0
    if rounds <= 0 or not (D and D.round) then return end
    if D.state ~= "wait" then s.inRound = D.round; return end
    if s.inRound == D.round and s.counted ~= D.round then             -- (its round just cleared)
        s.counted = D.round
        local upS = now - (s.at or now)
        if upS >= (sv.min_s or 60) then
            s.served = (s.served or 0) + 1
            log(string.format("allies: %s has served %d of its %d rounds (round %d clear)", aw.name, s.served, rounds, D.round))
        else
            log(string.format("allies: %s up only %d s of round %d: not counted (%d of %d served)", aw.name, math.floor(upS),
                D.round, s.served or 0, rounds))
        end
    end
    if (s.served or 0) >= rounds then
        s.home = now
        local r = type(SV_Event) == "function" and SV_Event(hm.event) or -5
        hudCallout(string.format(t.awacs_home, aw.name), string.format(t.awacs_home_sub, s.served))
        log(string.format("allies: %s has served %d rounds: going home (%s %s; %s)", aw.name, s.served, hm.event,
            r == 1 and "fired" or ("NOT fired: " .. (SV_ERR[r] or tostring(r))),
            s.areaOrbit and string.format("on the area orbit: taken off %d s on", hm.area_s or 30)
                or "out along its exit from the end of the arc it's on"))
    end
end
-- The round's strike flight after it (CFG.allies.awacs.strike): once a round while it's airborne and serving, one of
-- the round's fighter flights up after_s or more (not an ace squadron's, a role flight that keeps its own set, a Wolf,
-- an escort, the jammer's, nor one held, aimed elsewhere by a reversal or decoyed) has each plane's
-- EngagementOrderOverride onto it (Normal, TargetFirst: co-op's huntReal, hard rule 53; the STORE's ships get the
-- event package's AttackOnly order, which wants a build per target), again every again_s; back on you
-- (PlayerOnlyNoLimit, as it came: COOP.huntHost's) once it's lost, going home or gone. The hunt leaves it alone after.
local ORDER_NORMAL, PRIO_PLAYER_ONLY_NO_LIMIT, PRIO_TARGET_FIRST, FIRE_BITS = 0, 8, 9, 7     -- (sv_coop.lua's)
local function orderPlanes(u, target, prio)
    local n, total = 0, 0
    for _, p in ipairs(planes or {}) do
        if p.unit == u and not p.down and liveAddr(p.obj) then
            total = total + 1
            if pcall(function() p.obj:EngagementOrderOverride(ORDER_NORMAL, target, prio, 0, false, FIRE_BITS, false) end) then n = n + 1 end
        end
    end
    return n, total
end
local function strikeOk(R, u, now, after)
    if not poolIndex(u) or (BOMBER_UNIT and BOMBER_UNIT[u]) or (PROBE_OF and PROBE_OF[u]) then return false end
    if not (R.seen[u] and now - R.seen[u] >= after) then return false end
    if (D.escortUnits and D.escortUnits[u]) or D.jammerUnit == u or (D.jammer and D.jammer.unit == u)
        or (D.aceSquad and D.aceSquad[u]) then return false end
    if ROLE and ((ROLE.ownSet and ROLE.ownSet(u)) or (ROLE.flight and ROLE.flight(u) == "wolf")) then return false end
    if (WOLF and WOLF.holding and WOLF.holding(u)) or (DIR and DIR.holding and DIR.holding(u))
        or (TAC and TAC.decoyed and TAC.decoyed(u, now)) or now < ((D.aceMoveAt and D.aceMoveAt[u]) or 0) then return false end
    if ESC and ESC.holds and ESC.holds(u) then return false end   -- ((2026-11-06) after CHARLENE: THE ESCORT's, sv_escort.lua)
    return true
end
local function awacsStrike(R, s, now, f)
    local aw, t = CFG.allies.awacs, CFG.allies.text
    local st = aw.strike or {}
    local S = R.awStrike
    local serving = s ~= nil and not s.queued and not s.home and not s.removeAt and (f.SV_AwacsAir or 0) > 0
    if S and (not serving or S.s ~= s or not (D and D.up and D.up[S.unit])) then
        R.awStrike = nil
        if D and D.up and D.up[S.unit] then
            local pawn = liveObj(survivalPC) and survivalPC.Pawn or nil
            local n = (pawn and liveAddr(pawn)) and orderPlanes(S.unit, pawn, PRIO_PLAYER_ONLY_NO_LIMIT) or 0
            local how = string.format("%d planes back on you", n)
            if n == 0 and poolIndex(S.unit) and type(SV_Event) == "function" then
                local r = SV_Event(string.format("RE_SV_FlightOrders_%02d", poolIndex(S.unit)))
                how = "its appearance's orders again (RE_SV_FlightOrders " .. (r == 1 and "fired)" or "NOT fired)")
            end
            log(string.format("allies: %s off %s (%s): %s", S.unit, aw.name, (s == nil or S.s ~= s) and "it's gone"
                or (s.home and "it's going home") or "it's not airborne", how))
        end
        S = nil
    end
    if not (st.enabled and serving and D and D.up and D.state ~= "wait" and (D.round or 0) >= (st.from_round or 1)) then return end
    if S then                                                        -- (its order again now and then)
        if now >= S.again then
            S.again = now + (st.again_s or 15)
            local vw = awacsPlane(R, aw.unit)
            if vw then orderPlanes(S.unit, vw, PRIO_TARGET_FIRST) end
        end
        return
    end
    if R.awStrikeRound == D.round or now < (R.awStrikeAt or 0) then return end
    R.awStrikeAt = now + 2
    local vw = awacsPlane(R, aw.unit)
    if not vw then return end
    local cands = {}
    for u in pairs(D.up) do if strikeOk(R, u, now, st.after_s or 4) then cands[#cands + 1] = u end end
    table.sort(cands)                                                 -- (pairs' order isn't a choice)
    if #cands == 0 then
        if R.awStrikeNone ~= D.round then
            R.awStrikeNone = D.round
            log(string.format("allies: no fighter flight free to send after %s yet (round %d)", aw.name, D.round))
        end
        return
    end
    local u = cands[math.random(#cands)]
    local n, total = orderPlanes(u, vw, PRIO_TARGET_FIRST)
    if n == 0 then
        log(string.format("allies: %s NOT sent after %s: none of its %d planes took the order", u, aw.name, total))
        return
    end
    R.awStrike = { unit = u, s = s, at = now, again = now + (st.again_s or 15) }
    R.awStrikeRound = D.round
    R.hunted[u] = true                                                -- (the hunt's AIFirst order would take it off)
    hudCallout(t.strike, string.format(t.strike_awacs_sub, aw.name))
    log(string.format("allies: %s sent after %s: round %d's strike flight (%d of %d planes, Normal / TargetFirst onto it)",
        u, aw.name, D.round, n, total))
end

-- VOID WATCHER 1 (CFG.allies.awacs), every tick: off the ground once its buyer's airborne and the runway's clear (as
-- MOONCHILD), then its ESM fired every esm.every_s while it's airborne (SV_AwacsAir), and each ESM field of its class set
-- to esm.range_m for esm.life_s, new (ALLY.esmNew, from the game's NotifyOnNewObject: the field's actor) or launched
-- again (R.esmFields: they're pooled). ((0.73.78, G5) its rounds of service, going home and the strike flight after it:
-- awacsService, awacsStrike; while it's going home no ESM, no backstop)
-- ((2026-11-07) THE ESCORT, sv_escort.lua ESC.runwayBusy) a take-off held while CHARLENE and her escorts land: they taxi
-- past the hold spot every allied take-off starts from (said once a hold)
function ALLY.escortHold(name)
    local okE, busy = pcall(function() return ESC ~= nil and ESC.runwayBusy ~= nil and ESC.runwayBusy() == true end)
    busy = okE and busy == true
    if busy and not ALLY.escHoldSaid then
        ALLY.escHoldSaid = true
        log(string.format("allies: %s's take-off held: THE ESCORT is landing (its taxi passes the hold spot)", tostring(name)))
    elseif not busy and ALLY.escHoldSaid then
        ALLY.escHoldSaid = nil
        log("allies: the runway's clear of THE ESCORT: the take-offs go on")
    end
    return busy
end
function ALLY.awacsTick(R, now)
    local aw, t = CFG.allies.awacs, CFG.allies.text
    if not aw.enabled then return end
    local u = aw.unit
    local s = R.up[u]
    if s and s.queued and now >= R.nextTakeoff then
        local ready
        if s.buyer then ready = (COOP and COOP.airborne and COOP.airborne(s.buyer)) or now - (s.at or now) >= 90
        else ready = not playerOnAirfield() end
        if ready and ALLY.escortHold(aw.name) then ready = false end
        if ready then
            if type(SV_SetLevel) == "function" then SV_SetLevel(u, ALLY.level(s).ai * 100) end
            spawningUnit = u
            local r = SV_Spawn(u)
            spawningUnit = nil
            if r > 0 then
                s.queued, s.at, R.nextTakeoff, R.esmAt = nil, now, now + CFG.allies.aircraft.takeoff_gap_s, nil
                if R.alive then R.alive[u] = nil end -- ((0.73.77) its count asked afresh: ALLY.alive)
                hudCallout(string.format(t.takeoff, aw.name), t.takeoff_sub_awacs)
                log(string.format("allies: %s (%s) taxiing out", aw.name, u))
            else
                s.tries, R.nextTakeoff = (s.tries or 0) + 1, now + 5
                log(string.format("allies: %s (%s) not spawned (%s)", aw.name, u, SV_ERR[r] or tostring(r)))
                if s.tries >= 3 then                 -- never came: the zollars back (to the joiner who paid, if it was one)
                    R.up[u] = nil
                    if s.buyer then
                        if COOP and COOP.refund then COOP.refund(s.buyer, s.price or 0, aw.name .. " COULD NOT TAKE OFF") end
                    else
                        RUN.credits, RUN.spent, RUN.dirty = RUN.credits + (s.price or 0), RUN.spent - (s.price or 0), true
                    end
                    log(string.format("allies: %s couldn't take off; %d zollars back", aw.name, s.price or 0))
                end
            end
        end
    end
    -- its orbit's backstop: its climb-out never ended (an E-767 on the fighters' scramble paths), or it's wandered off
    local f = (s and not s.queued) and (svFlags() or {}) or {}
    local ob = aw.orbit
    -- ((0.73.78, G5) not once it's going home: its way out is meant to leave the orbit)
    if s and not s.queued and not s.home and ob and type(SV_Event) == "function" and now >= (R.orbitCheckAt or 0) then
        R.orbitCheckAt = now + (ob.check_s or 20)
        local why = nil
        if (f.SV_AwacsAir or 0) <= 0 then
            if now - (s.at or now) >= (ob.climb_s or 60) then why = string.format("its climb-out didn't end in %d s", ob.climb_s or 60) end
        else
            local d
            for _, p in ipairs(R.planes) do
                if p.unit == u and valid(p.obj) then
                    local okL, l = pcall(function() return p.obj:K2_GetActorLocation() end)
                    if okL and l then d = math.sqrt((l.X - AIRFIELD.X) ^ 2 + (l.Y - AIRFIELD.Y) ^ 2) / 100000 end
                end
            end
            if d and d >= (ob.lost_km or 18) then why = string.format("%.1f km from the airfield", d) end
        end
        if why and now >= (R.orbitAgainAt or 0) then
            R.orbitAgainAt = now + (ob.again_s or 60)
            local r = SV_Event(ob.event)
            if r == 1 then s.areaOrbit = true end           -- ((0.73.78, G5) off its arcs: no arc's end to go home from)
            log(string.format("allies: %s taken off its path onto the area orbit (%s): %s %s", aw.name, why, ob.event,
                r == 1 and "fired" or ("NOT fired: " .. (SV_ERR[r] or tostring(r)))))
        end
    end
    -- ((0.73.78, G5) its rounds of service and its way home, then the round's strike flight after it (or back off it))
    if s and not s.queued then
        local okV, errV = pcall(awacsService, R, s, now, f)
        if not okV and not R.awServiceErr then R.awServiceErr = true; log("allies: " .. aw.name .. "'s service error " .. tostring(errV)) end
    end
    local okK, errK = pcall(awacsStrike, R, R.up[u], now, f)
    if not okK and not R.awStrikeErr then R.awStrikeErr = true; log("allies: " .. aw.name .. "'s strike flight error " .. tostring(errK)) end
    -- (0.73.62) where it is every 30 s while airborne: its orbit is its unit area now (tools/survival_events.py
    -- build_awacs), so the log shows whether it circles the airfield (+Y is south on Comona)
    if s and not s.queued and (f.SV_AwacsAir or 0) > 0 and now >= (R.awPosAt or 0) then
        R.awPosAt = now + 30
        pcall(function()                                    -- (a log line only: never stops the ESM below)
            for _, p in ipairs(R.planes) do
                if p.unit == u and liveAddr(p.obj) then
                    local okL, l = pcall(function() return p.obj:K2_GetActorLocation() end)
                    local okR, r = pcall(function() return p.obj:K2_GetActorRotation() end)
                    if okL and l then
                        local dx, dy = (l.X - AIRFIELD.X) / 100000, (l.Y - AIRFIELD.Y) / 100000
                        local brg = (math.deg(math.atan(dx, -dy)) + 360) % 360       -- (compass: north is -Y)
                        -- (0.73.73) legs: SV_AwacsLeg, +1 at each orbit arc's end (tools/survival_events.py awacs_orbit):
                        -- rising, the path orbit is flown; stuck, it isn't (the backstop's area orbit takes over)
                        log(string.format("allies: %s at %.1f km from the airfield, bearing %03d, %.1f km up, heading %s; legs %d%s",
                            aw.name, math.sqrt(dx * dx + dy * dy), math.floor(brg + 0.5), l.Z / 100000,
                            (okR and r) and string.format("%03d", math.floor((r.Yaw + 90 + 360) % 360 + 0.5)) or "?",
                            tonumber(f.SV_AwacsLeg) or 0,     -- ((0.73.78, G5) on its way home: SV_AwacsOut 1 out, 2 flown)
                            s.home and string.format("; going home (exit %d)", tonumber(f.SV_AwacsOut) or 0) or ""))
                    end
                end
            end
        end)
    end
    -- its ESM, fired while it's airborne (COOP: forwarded, so every game's copy fields its own); ((0.73.78, G5) not once
    -- it's going home)
    if s and not s.queued and not s.home and (f.SV_AwacsAir or 0) > 0 and now >= (R.esmAt or 0) and type(SV_Event) == "function" then
        R.esmAt = now + aw.esm.every_s
        local r = SV_Event(aw.esm.event)
        R.esmFired = (R.esmFired or 0) + 1
        if R.esmFired == 1 or r ~= 1 then
            log(string.format("allies: %s's ESM fired (%s %s; every %d s while it's airborne)", aw.name, aw.esm.event,
                r == 1 and "fired" or ("NOT fired: " .. (SV_ERR[r] or tostring(r))), aw.esm.every_s))
        end
    end
    -- each ESM field of its class: its range and time (an instance's; the class itself is never changed).
    -- (0.73.73) The fields are pooled: the game builds two and launches them again and again, so NotifyOnNewObject sees
    -- only the first two (every tester session of 2026-11-01 logged two fields, BP_wp_esm_MS28_C_2147435332 and _2147434941
    -- in A14, while the weapons log counted 2-3 launches a minute for 7 minutes), and each later launch flew the game's own
    -- range and time ("the ESM only lasted the same amount of time that a player's does", Shazzy). Each field seen is
    -- kept (R.esmFields, by address), and set again whenever it's launched: shown after it was hidden, or shown with the
    -- game's range on it (the launch wrote its own)
    local q = ALLY.esmNew
    if q and #q > 0 then
        ALLY.esmNew = {}
        for _, o in ipairs(q) do
            local a = liveAddr(o)
            if a and nameOf(o):find(aw.esm.class, 1, true) then
                R.esmFields = R.esmFields or {}
                local okH, hid = pcall(function() return o.bHidden end)
                R.esmFields[a] = { obj = o, name = nameOf(o), shown = okH and hid == false }
                esmSet(R, aw, o, "new")
            end
        end
    end
    for a, e in pairs(R.esmFields or {}) do
        if liveAddr(e.obj) ~= a or nameOf(e.obj) ~= e.name then
            R.esmFields[a] = nil                             -- (gone, or its address another object's now)
        else
            local okH, hid = pcall(function() return e.obj.bHidden end)
            local blind = not okH or type(hid) ~= "boolean"
            local shown = not blind and hid == false
            if blind and not R.esmHidSaid then
                R.esmHidSaid = true
                log(string.format("allies: %s's ESM field's bHidden can't be read: a launch is told by its range alone", aw.name))
            end
            local okR, rng = pcall(function() return e.obj.EffectRangeMeter end)
            local theirs = okR and type(rng) == "number" and math.abs(rng - aw.esm.range_m) > 0.5
            if (shown and not e.shown) or (theirs and (shown or blind)) then esmSet(R, aw, e.obj, "again") end
            e.shown = shown
        end
    end
end
-- (every ESM / ECM field the game makes, its actor at construction, for ALLY.awacsTick; only VOID WATCHER 1's class is
-- changed there)
if type(NotifyOnNewObject) == "function" then
    pcall(NotifyOnNewObject, "/Script/Live.LiveElectronicSupportMeasures", function(o)
        ALLY.esmNew = ALLY.esmNew or {}
        if #ALLY.esmNew < 64 then ALLY.esmNew[#ALLY.esmNew + 1] = o end
    end)
end

-- ((0.73.77, Workstream B1) the allies part's shares in the perf line, "allies/<share>": sv_main.lua's PERF)
local function pa(name, t0) if PERF and PERF.add then PERF.add(name, t0) end end
function ALLY.tick(now)
    if not (CFG.allies.enabled and D and nativeReady()) then return end
    local R, c, t = ALLY.state(), CFG.allies, CFG.allies.text
    local t0 = os.clock()
    for _, u in ipairs(c.aircraft.units) do          -- a bought flight: off the ground once you are, runway clear
        local s = R.up[u]
        local ready
        if s and s.buyer then                        -- (a co-op joiner's: once they're airborne, or 90 s on)
            ready = (COOP and COOP.airborne and COOP.airborne(s.buyer)) or now - (s.at or now) >= 90
        else
            ready = not playerOnAirfield()
        end
        if s and s.queued and now >= R.nextTakeoff and ready and ALLY.escortHold(airName(s)) then ready = false end
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
                if R.alive then R.alive[u] = nil end -- ((0.73.77) its count asked afresh: ALLY.alive)
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
    pa("allies/takeoffs", t0)
    t0 = os.clock()
    local okA, errA = pcall(ALLY.awacsTick, R, now)
    if not okA and not R.awacsErrSaid then R.awacsErrSaid = true; log("allies: " .. c.awacs.name .. " error " .. tostring(errA)) end
    pa("allies/VOID WATCHER", t0)
    t0 = os.clock()
    local okS, errS = pcall(aliveShare, R, now)      -- ((0.73.77) a share of the units' counts: B3)
    if not okS and not R.aliveErrSaid then R.aliveErrSaid = true; log("allies: the units' counts error " .. tostring(errS)) end
    pa("allies/counts", t0)
    t0 = os.clock()
    if now >= (R.checkAt or 0) then                  -- every 2 s: losses, scaling, orders, and the enemies' on the allies
        R.checkAt = now + 2
        ALLY.scale()
        local f, airborne = svFlags() or {}, 0
        R.orderGiven = R.orderGiven or {}
        for u, s in pairs(R.up) do
            if not s.queued then
                local n = ALLY.alive(u, now)             -- ((0.73.77) the share's count, at most 2.5 s old: B3)
                -- ((0.73.78, G5) VOID WATCHER 1 taken off on its way home isn't lost: awacsService takes it out of R.up)
                if n <= 0 and now - s.at > 5 and not s.removeAt then
                    R.up[u], RUN.dirty = nil, true
                    local name = s.kind == "air" and airName(s) or c.ships[s.key].name
                    if s.ally == "awacs" then R.awacsFields = {} end
                    hudCallout(string.format(s.kind == "air" and t.air_lost or t.sunk, name), t.lost_sub)
                    log(string.format("allies: %s (%s) lost %.0f s after it %s", name, u, now - s.at,
                        s.kind == "air" and "spawned" or "sailed"))
                elseif s.ally == "awacs" and n > 0 then    -- (no orders: it orbits; airborne, the enemies may hunt it)
                    -- ((0.73.78, G5) not once it's going home: no hunters sent for it then)
                    airborne = airborne + (s.home and 0 or math.min(n, f.SV_AwacsAir or 0))
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
                    and not (WOLF and WOLF.holding(u)) and not (DIR and DIR.holding and DIR.holding(u))
                    and not (ESC and ESC.holds and ESC.holds(u)) then   -- ((2026-11-06) after CHARLENE: sv_escort.lua)
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
                local up = ALLY.alive(u, now) > 0        -- ((0.73.77) the share's count: B3)
                if up then R.defCount[kind] = R.defCount[kind] + 1 end
                if R.defUp[u] and not up then
                    hudCallout(string.format(t.def_lost, d[kind].label), t.def_lost_sub)
                    log(string.format("allies: %s (%s) lost in round %d", d[kind].label, u, D.round))
                    RUN.dirty = true
                end
                R.defUp[u] = up
            end
        end
    end
    pa("allies/checks", t0)
    t0 = os.clock()
    local okD, hp = pcall(defenceHealth, R, now)      -- ((0.73.77) every tick: its walks one class a tick, B3)
    R.defHp = okD and hp or nil
    pa("allies/defence health", t0)
    t0 = os.clock()
    for i = #R.events, 1, -1 do
        local e = R.events[i]
        if now >= e.at then
            table.remove(R.events, i)
            local r = type(SV_Event) == "function" and SV_Event(e.name) or -5
            log(string.format("allies: %s (%s) %s", e.name, e.why, r == 1 and "fired" or ("not fired: " .. (SV_ERR[r] or tostring(r)))))
        end
    end
    pa("allies/events", t0)
end
end
