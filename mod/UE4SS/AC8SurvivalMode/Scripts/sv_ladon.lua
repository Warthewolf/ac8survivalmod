-- sv_ladon.lua: the Ladons and the hit log.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- ladon
-- CFG.specials.ladon; tools/survival_events.py LADON* builds the units (Mission 16's Ladon, parts and all), routes and
-- records. Ladon <Key> is unit SV_Unit_Ladon<Key> on DT_NPC row SV_Ladon_<Key>; each pass over the airfield adds one to
-- SV_LadonRun<Key>.
do
local KEYS = { "Kot", "Mishka" }

-- At the main menu, before the level loads (the spawner caches the rows then): each Ladon's DT_NPC row, from
-- DT_SV_NpcRows, with its name, health and speed.
function SPC.ladonSetup()
    if SPC.ladonDone or not gameInstance() then return end
    local c = CFG.specials.ladon
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(c.npc_rows)
    SPC.ladonTries = (SPC.ladonTries or 0) + 1
    if not (npc and mine) then
        if SPC.ladonTries >= 20 then SPC.ladonDone = true; log("special: the Ladons' tables didn't load; no Ladon round") end
        return
    end
    SPC.ladonDone = true
    local n = 0
    for _, k in ipairs(KEYS) do
        local row = "SV_Ladon_" .. k
        local _, have = dtCall(npc, "FindRow", row)
        if have == nil then
            local _, r = dtCall(mine, "FindRow", row)
            if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
        end
        if have ~= nil then
            n = n + 1
            local ok, err = pcall(function()
                have.MaxHealthDifference = c.health_add
                for _, f in ipairs({ "SpeedNormalCoefficient", "SpeedMaxCoefficient", "SpeedMinCoefficient", "SpeedTurnCoefficient" }) do
                    local v = have[f]
                    have[f] = ((type(v) == "number" and v > 0) and v or 1.0) * c.speed_x
                end
            end)
            if not ok then log("special: Ladon row " .. row .. ": health / speed NOT set: " .. tostring(err)) end
        end
        if type(SV_SetText) == "function" then SV_SetText(row, c.names[k] or k:upper()) end
    end
    SPC.ladonReady = n == #KEYS
    log(string.format("special: %d of %d Ladon rows in DT_NPC (%s; %+d HP, speeds x%.2f)", n, #KEYS,
        table.concat({ c.names.Kot, c.names.Mishka }, ", "), c.health_add, c.speed_x))
end

function SPC.ladonSpawn(now)
    local c, t = CFG.specials.ladon, CFG.hud.text
    if not (nativeReady() and SPC.ladonReady) then
        log("special: no Ladon round (" .. (SPC.ladonReady and "no native spawner" or "their rows aren't in") .. ")")
        return false
    end
    local s = D.special
    s.units, s.state, s.at, s.runs, s.planeFrom = {}, "run", now, 0, #planes + 1
    for _, k in ipairs(KEYS) do
        local unit = "SV_Unit_Ladon" .. k
        local r, was = SV_UnitAlive(unit), nil
        if r > 0 then was = true                     -- still up from before (a restart mid-round): this round's, then
        else spawningUnit = unit; r = SV_Spawn(unit); spawningUnit = nil end
        log(string.format("special: Ladon %s (%s): %s", c.names[k] or k, unit, r > 0 and (was and "still up, taken on" or "up") or
            ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
        if r > 0 then s.units[k] = { unit = unit, alive = true, runs = 0 } end
    end
    if not next(s.units) then return false end
    hudCallout(t.ladon_go, string.format(t.ladon_go_sub, c.names.Kot or "KOT", c.names.Mishka or "MISHKA"))
    log(string.format("special: round %d, the Ladons from the west", D.round))
    return true
end

function SPC.ladonsLeft(s)
    local n = 0
    for _, L in pairs(s.units or {}) do if L.alive then n = n + 1 end end
    return n
end

function SPC.ladonBusy(s) return s.state == "run" and SPC.ladonsLeft(s) > 0 end

-- Every second: a pass over the airfield (its bombs), a Ladon shot down (its pay).
function SPC.ladonTick(now, s)
    if s.state ~= "run" or now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    local c, t = CFG.specials.ladon, CFG.hud.text
    local f = svFlags() or {}
    -- its health for its round, once its aircraft is up (HealthInternal: health x 10, as the shuttle's)
    local hx = math.min(c.health_max_x or 2.5, 1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first))
    for i = s.planeFrom or 1, (s.scaledN or 0) < 2 and #planes or 0 do
        local p = planes[i]
        if hx > 1 and not p.down and not p.scaled and p.unit and p.unit:find("^SV_Unit_Ladon") and valid(p.obj) then
            local ok, h0 = pcall(function() return p.obj.HealthInternal end)
            if ok and type(h0) == "number" and h0 > 0 then        -- (not yet set on a fresh actor: next second)
                p.scaled, s.scaledN = true, (s.scaledN or 0) + 1
                local okW, err = pcall(function() p.obj.HealthInternal = math.floor(h0 * hx) end)
                log(string.format("special: %s health x%.2f for round %d (%s -> %s)%s", p.unit, hx, D.round, tostring(h0),
                    tostring(okW and p.obj.HealthInternal or "?"), okW and "" or (" (write failed: " .. tostring(err) .. ")")))
            end
        end
    end
    for k, L in pairs(s.units) do
        if L.alive and now >= (L.volleyAt or s.at + 10) then             -- a missile volley while you're in range
            local near
            for _, p in ipairs(planes) do
                if p.unit == L.unit and not p.down and valid(p.obj) and p.dist then near = math.min(near or p.dist, p.dist) end
            end
            if near and near <= c.volley_range_km then
                L.inRangeAt = L.inRangeAt or now                       -- (the first volley: once in range volley_warn_s)
                -- one Ladon's volley at a time, volley_gap_s apart (a friend's test of 2026-10-23: both came into range
                -- together and fired in the same second, and the player was down 20 s later): the other one waits
                local gap = c.volley_gap_s or c.volley_every_s / 2
                if now - L.inRangeAt >= (c.volley_warn_s or 0) and now - (s.volleyAny or -1e9) >= gap then
                    L.volleyAt, s.volleyAny, s.volleyWho = now + c.volley_every_s, now, c.names[k] or k
                    L.side = (L.side == "L") and "R" or "L"
                    local ev = "RE_SV_LadonVolley" .. k .. L.side
                    local r = type(SV_Event) == "function" and SV_Event(ev) or "n/a"
                    log(string.format("special: Ladon %s fires a launcher at you (%.1f km; %s %s)%s", c.names[k] or k, near, ev,
                        tostring(r), L.volleySaid and "" or string.format(", one every %d s in range, %d s after the other's",
                        c.volley_every_s, gap)))
                    L.volleySaid = true
                end
            else
                L.inRangeAt = nil
            end
        end
        if L.alive then
            local runs = f["SV_LadonRun" .. k] or 0
            -- (a count left from last time is reset by its appearance; a circuit takes minutes, so one pass in 30 s at
            -- most: a path that "finished" every frame once counted 30 a second and bombed every second, 2026-10-23)
            if now - s.at >= 5 and runs > L.runs and now - (L.bombAt or 0) >= 30 then
                L.runs, L.bombAt, s.runs = runs, now, (s.runs or 0) + 1
                local dmg = c.bomb_damage + (c.bomb_per_round or 0) * math.max(0, D.round - CFG.specials.first)
                if CFG.airfield.enabled and not AF.down then AF.bomb = AF.bomb + dmg end
                hudCallout(string.format(t.ladon_run, c.names[k] or k), t.ladon_run_sub)
                log(string.format("special: Ladon %s's pass over the airfield (%d): -%d", c.names[k] or k, runs, dmg))
            end
            local n, gone = SV_UnitAlive(L.unit), false
            if n >= 0 then L.errs = 0 else L.errs = (L.errs or 0) + 1 end
            if n == -7 or (L.errs or 0) >= 20 then           -- off the phase's list, or unreadable for 20 s
                local flying = false                          -- (code review of 2026-10-23: -7 paid, other errors held
                for _, p in ipairs(planes) do                 -- the round for good)
                    if p.unit == L.unit and not p.down and valid(p.obj) then flying = true end
                end
                if not flying then
                    L.alive, gone, s.escaped = false, true, true
                    log(string.format("special: Ladon %s gone without being shot down (SV_UnitAlive %d); no pay", c.names[k] or k, n))
                end
            end
            if n == 0 and not gone then
                L.alive = false
                local pay = c.reward + (c.reward_per_round or 0) * D.round
                addCredits(pay, "Ladon " .. (c.names[k] or k) .. " down")
                LB.stat("air", 1)
                hudCallout(string.format(t.ladon_down, c.names[k] or k), string.format(t.ladon_down_sub, pay))
                log(string.format("special: round %d, Ladon %s down %.0f s after it appeared", D.round, c.names[k] or k, now - s.at))
            end
        end
    end
    if SPC.ladonsLeft(s) == 0 then s.state = "done"; LB.special("ladon", not s.escaped, now - s.at) end
end
end

---------------------------------------------------------------------------------------------------- hits on the player
-- A friend's run ended 20 s after both Ladons' volleys and the log couldn't say what hit them (2026-10-23): the
-- player's health is read every tick and a drop is logged (at most once a second, the drops between added up) with the
-- enemy missiles near the player then (every LiveMissile but the player's, tracked from its creation; one that hit is
-- gone the tick after, so the last distance it was seen at counts) and the nearest enemy aircraft. No missile near:
-- a gun, the Ladons' pulse cannons, a SAM's blast or a collision. The Ladons' VLS missiles are toned down here as they
-- appear (CFG.specials.ladon.missile_*): from their class default, so a missile seen twice isn't cut twice.
HIT = { new = {}, msl = {} }
pcall(NotifyOnNewObject, "/Script/Live.LiveMissile", function(o) if #HIT.new < 200 then HIT.new[#HIT.new + 1] = o end end)
do
local LADON_MSL = "BP_wp_vls_ladon"
local LADON_CDO = "/Game/Blueprints/Weapons/MSL/NPC/Vls/Ladon/BP_wp_vls_ladon.Default__BP_wp_vls_ladon_C"
local function short(o)                                    -- "BP_wp_vls_ladon" from "... .BP_wp_vls_ladon_C_2147..."
    local n = nameOf(o):match("([%w_]+)$") or "?"
    return (n:gsub("_C_%d+$", ""):gsub("_C$", ""))
end
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function owner(o)                                    -- who fired it (its owner, else its instigator), or nil
    for _, f in ipairs({ function() return o:GetOwner() end, function() return o.Instigator end }) do
        local ok, w = pcall(f)
        if ok and valid(w) then return short(w) end
    end
    return nil
end

local function nerf(o)
    local c = CFG.specials.ladon
    if not valid(HIT.cdo) then HIT.cdo = StaticFindObject(LADON_CDO) end
    local base = valid(HIT.cdo) and HIT.cdo or o
    local ok, err = pcall(function()
        local d0, a0 = base.damage, base.MaxHomingAngle
        o.damage = d0 * (c.missile_damage_x or 1)
        o.MaxHomingAngle = a0 * (c.missile_homing_x or 1)
        if not HIT.nerfSaid then
            HIT.nerfSaid = true
            log(string.format("hits: the Ladons' missile %s toned down: damage %.1f -> %.1f, homing cone %.0f -> %.0f deg (from %s)",
                LADON_MSL, d0, o.damage, a0, o.MaxHomingAngle, base == o and "the missile itself" or "its class default"))
        end
    end)
    if not ok and not HIT.nerfErr then HIT.nerfErr = true; log("hits: the Ladons' missile NOT toned down: " .. tostring(err)) end
end

-- what's near the player now: "missiles: ...; enemies: ..."
local function around(me, now)
    local ms = {}
    for _, m in ipairs(HIT.msl) do
        if m.d and m.d <= 800 and now - (m.seen or -1e9) <= 0.6 then ms[#ms + 1] = m end
    end
    table.sort(ms, function(a, b) return a.d < b.d end)
    local mt = {}
    for i = 1, math.min(3, #ms) do
        local m = ms[i]
        mt[#mt + 1] = string.format("%s %.0f m%s%s", m.name, m.d, m.from and (" from " .. m.from) or "",
            valid(m.obj) and "" or " (gone: it hit)")
    end
    local es = {}
    for _, p in ipairs(planes) do
        if not p.down and p.dist and p.dist <= 8 and valid(p.obj) then
            local v = at(p.obj)
            if v then es[#es + 1] = { name = p.unit or short(p.obj), d = km(v, me) } end
        end
    end
    table.sort(es, function(a, b) return a.d < b.d end)
    local et = {}
    for i = 1, math.min(3, #es) do et[#et + 1] = string.format("%s %.2f km", es[i].name, es[i].d) end
    return "missiles near: " .. (#mt > 0 and table.concat(mt, ", ") or "none (gun / pulse cannon / blast / collision?)") ..
        "; nearest enemies: " .. (#et > 0 and table.concat(et, ", ") or "none within 8 km")
end

function HIT.reset() HIT.new, HIT.msl, HIT.h, HIT.pawn, HIT.sum = {}, {}, nil, nil, nil end

-- every tick in a run (now: the round clock)
function HIT.tick(pc, now)
    local new = HIT.new
    HIT.new = {}
    for _, o in ipairs(new) do                             -- the new missiles: enemies' tracked, the Ladons' toned down
        if valid(o) then
            local n = short(o)
            if not n:find("^BP_plwp_") and not n:find("^Default__") then
                if n == LADON_MSL then nerf(o) end
                if #HIT.msl >= 60 then table.remove(HIT.msl, 1) end
                HIT.msl[#HIT.msl + 1] = { obj = o, name = n, born = now }
            end
        end
    end
    local pawn = pc and pc.Pawn
    if not valid(pawn) then return end
    local me = at(pawn)
    local keep = {}
    for _, m in ipairs(HIT.msl) do                         -- where each one is (kept 2 s after it's gone)
        if valid(m.obj) and now - m.born < 30 then
            m.from = m.from or owner(m.obj)
            local v = me and at(m.obj)
            if v then m.d, m.seen = km(v, me) * 1000, now end
            keep[#keep + 1] = m
        elseif now - (m.seen or m.born) < 2 then keep[#keep + 1] = m end
    end
    HIT.msl = keep
    local okA, addr = pcall(function() return tostring(pawn:GetAddress()) end)
    if not okA then addr = nameOf(pawn) end
    if addr ~= HIT.pawn then HIT.pawn, HIT.h, HIT.sum = addr, nil, nil end    -- (a new aircraft: a restart)
    local ok, h = pcall(function() return pawn.HealthInternal end)
    if not ok or type(h) ~= "number" then return end
    local last = HIT.h
    HIT.h = h
    if last and h < last then
        if not HIT.sum then HIT.sum, HIT.n, HIT.near = 0, 0, me and around(me, now) or "?" end   -- (as it was at the first)
        HIT.sum, HIT.n = HIT.sum + (last - h), HIT.n + 1
    end
    if HIT.sum and now - (HIT.logged or -1e9) >= 1 then
        local okM, maxHp = pcall(function() return pawn.MaxHealth end)
        local pct = (okM and type(maxHp) == "number" and maxHp > 0) and string.format("%d%%", math.floor(h / 10 / maxHp * 100 + 0.5)) or "?"
        local s = D and D.special
        local vol = (s and s.volleyAny and now - s.volleyAny < 60) and string.format("; Ladon %s's volley %.0f s ago", s.volleyWho or "?", now - s.volleyAny) or ""
        log(string.format("hit: -%.0f HP in %d hit%s, health now %s (%.0f HP)%s; %s%s", HIT.sum / 10, HIT.n, HIT.n == 1 and "" or "s",
            pct, h / 10, h <= 0 and ", SHOT DOWN" or "", HIT.near, vol))
        HIT.logged, HIT.sum = now, nil
    end
end
end
