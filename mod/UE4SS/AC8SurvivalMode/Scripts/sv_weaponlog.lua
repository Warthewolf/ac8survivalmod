-- sv_weaponlog.lua: what the enemies carry and what they fire, in the log only.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (... sv_stats, sv_weaponlog, sv_tells ...); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- weapons log
-- The user, 2026-10-31: "can you add a logger that checks what enemy missiles are being fired, I have a feeling that
-- none of the special weapons we gave the enemies are working". Survival gives the enemies their special weapons by
-- writing them into their DT_NPC rows' fire-control slots at run time (sv_rows.lua: CFG.special.fcs, the aces', the
-- jammer's ECM pod); whether their AI ever fires those slots is what this answers (CFG.log.weapons; [log.weapons]):
--   carried: each enemy plane's fire control as the game built it (FireControlSystemComponent.AllArms: each system's
--     name and its projectile module's WeaponClass / WeaponClasses, AmmoCount when it's limited), read 2 s after the
--     plane is created and logged once a run for each airframe and loadout: `weapons: <unit> (<row>, <airframe>)
--     carries: <system> <weapon> ...`;
--   fired: every every_s, every weapon object of the game's missile / bomb / rocket (LiveExplosiveWeapon), laser
--     (LiveAttachedInstantWeapon) and ESM / ECM (LiveElectronicWeaponBase) classes. Weapons are pooled (a LiveWeaponBase
--     is a LiveObjectPoolItem: NotifyOnNewObject never sees a reused one), so a launch is one that's shown now and was
--     hidden (or unseen) the look before, or one shown with a new owner. Its owner (OwningGameObject) says who fired it:
--     one of the enemy planes (its unit and row), you, or another (a ship, a ground unit, an ally: by its class). The
--     first launch of each weapon by each kind of shooter: `weapons: first launch of <weapon> by <shooter> ...`;
--   every summary_s with anything new: `weapons: last N s: <weapon> x<n> (<shooters>), ...; carried by enemies but never
--     fired this run: <weapon> (<n> planes), ...` and the pools' size (`<n> weapon objects, <m> in flight`).
--   missile outcomes (the user's loggers of 2026-10-31): each enemy launch aimed at you (its TargetToHome your plane) is
--     followed while it flies: its nearest pass and whether its target turned to a flare; when it's gone, a hit (it
--     passed within hit_m and your health dropped within a second of its going), decoyed (it went after a flare) or
--     missed; every summary_s `missiles at you: ...` by weapon, with the range it was fired from, and the run's;
--   the Spaceport fleet's turrets (sv_spaceport.lua SPORT.turrets): every turret_s while one's up, which fired (their
--     missiles, from the launches above; their guns, any of their LiveBullets shown) and which stayed silent with you
--     inside their reach (CFG.specials.spaceport.fcs.search_m); every summary_s `fleet: ...` by turret class.
-- Only addresses and text are kept between looks (never a game object: the lesson of 0.73.24 / 0.73.29).
WLOG = {}
do
local BASES = { "LiveExplosiveWeapon", "LiveAttachedInstantWeapon", "LiveElectronicWeaponBase" }

local function cfg() return CFG.log and CFG.log.weapons or {} end
local function short(o)                                    -- "BP_wp_vls_ladon" from "... .BP_wp_vls_ladon_C_2147..."
    local n = nameOf(o):match("([%w_]+)$") or "?"
    return (n:gsub("_C_%d+$", ""):gsub("_C$", ""))
end
local function nameStr(n)                                  -- an FName (or a string) as text
    if n == nil then return "?" end
    local ok, s = pcall(function() return n:ToString() end)
    return ok and s or tostring(n)
end

-- WLOG.run: this run's { carried = { [weapon] = { planes, units } }, fired = { [weapon] = n }, seen = { [key] = true } }
local function run()
    if not WLOG.r or WLOG.r.D ~= D then
        WLOG.r = { D = D, carried = {}, fired = {}, said = {}, loadouts = {}, state = {}, win = {}, winAt = nil, done = {},
                   track = {}, out = {}, outRun = {} }
    end
    return WLOG.r
end

-- One plane's fire control: { "<system> <weapon>[ ammo n]", ... } and its weapons' short names, or nil (not built yet).
local function armsOf(o)
    local out, weapons = {}, {}
    local okC, fcs = pcall(function() return o.FireControlSystemComponent end)
    if not (okC and valid(fcs)) then return nil end
    local list = {}
    local okA = pcall(function() fcs.AllArms:ForEach(function(_, e) list[#list + 1] = e:get() end) end)
    if not okA or #list == 0 then return nil end
    for _, a in ipairs(list) do
        if valid(a) then
            local sys = "?"
            pcall(function() sys = nameStr(a.SystemName) end)
            local ws = {}
            local okP, pm = pcall(function() return a.ProjectileModule end)
            if okP and valid(pm) then
                pcall(function() local c = pm.WeaponClass; if valid(c) then ws[#ws + 1] = short(c) end end)
                pcall(function()
                    pm.WeaponClasses:ForEach(function(_, e) local c = e:get(); if valid(c) then ws[#ws + 1] = short(c) end end)
                end)
                if #ws == 0 then pcall(function() local c = pm.FlareClass; if valid(c) then ws[#ws + 1] = short(c) end end) end
                local ammo = ""
                pcall(function() if pm.bLimitAmmo then ammo = " ammo " .. tostring(pm.AmmoCount) end end)
                out[#out + 1] = string.format("%s %s%s", sys, #ws > 0 and table.concat(ws, "+") or ("(" .. short(pm) .. ")"), ammo)
            else
                out[#out + 1] = sys .. " (no projectile module)"
            end
            -- (its gun and flares aren't watched as launches: listed, never counted as carried and not fired)
            local unwatched = sys:find("Gun") or sys:find("Flr") or sys:find("Flare")
            for _, w in ipairs(ws) do if not unwatched then weapons[#weapons + 1] = w end end
        end
    end
    return out, weapons
end

-- The enemy planes' fire control, each read once 2 s after it's created (twice more if it isn't built yet).
local function carriedTick(R, now)
    for _, p in ipairs(planes or {}) do
        if not p.wlog and p.unit and valid(p.obj) and now - (p.born or now) >= 2 then
            local lines, ws = armsOf(p.obj)
            p.wlogTries = (p.wlogTries or 0) + 1
            if lines or p.wlogTries >= 3 then
                p.wlog = true
                local row = D and D.flightRow and D.flightRow[p.unit] or "?"
                local airframe = (p.name or "?"):gsub("_C_%d+$", "")
                for _, w in ipairs(ws or {}) do
                    local c = R.carried[w] or { planes = 0, units = {} }
                    c.planes = c.planes + 1
                    if #c.units < 4 and not c.units[p.unit] then c.units[#c.units + 1] = p.unit; c.units[p.unit] = true end
                    R.carried[w] = c
                end
                local sig = row .. "|" .. airframe .. "|" .. table.concat(lines or { "none" }, ",")
                if not R.loadouts[sig] then
                    R.loadouts[sig] = true
                    log(string.format("weapons: %s (%s, %s) carries: %s", p.unit, row, airframe,
                        lines and table.concat(lines, "; ") or "nothing read (its fire control isn't built)"))
                end
            end
        end
    end
end

-- Who a weapon's owner is: "enemy", its plane record; "you"; or "other", its class.
local function ownerOf(w, byAddr, pawnAddr)
    local okO, o = pcall(function() return w.OwningGameObject end)
    if not (okO and valid(o)) then return "none", nil, "?" end
    local a = addrOf(o)
    if a and a == pawnAddr then return "you", nil, "you", a end
    local p = a and byAddr[a]
    if p then return "enemy", p, (p.name or "?"):gsub("_C_%d+$", ""), a end
    return "other", nil, short(o), a
end

local function at(o)
    local v
    pcall(function() local l = o:K2_GetActorLocation(); v = { X = l.X, Y = l.Y, Z = l.Z } end)
    return v
end
local function dist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) / 100 end   -- (m)

-- a missile at you followed to its end: hit, decoyed or missed (looked at a second after it's gone, for the health drop)
local function settle(R, t)
    local hitM = tonumber(cfg().hit_m) or 150
    local res = t.decoy and "decoyed"
        or (t.minM <= hitM and R.dropAt and math.abs(R.dropAt - t.goneAt) <= 1.2 and "hit") or "missed"
    for _, tab in ipairs({ R.out, R.outRun }) do
        local o = tab[t.weapon] or { n = 0, hit = 0, decoyed = 0, missed = 0, km = 0 }
        o.n, o.km = o.n + 1, o.km + t.d0
        o[res] = o[res] + 1
        tab[t.weapon] = o
    end
end
local function outcomes(tab)
    local t = {}
    for weapon, o in pairs(tab) do
        t[#t + 1] = string.format("%s %d (%d hit, %d decoyed, %d missed; from %.1f km on average)", weapon, o.n, o.hit, o.decoyed,
            o.missed, o.km / math.max(1, o.n))
    end
    table.sort(t)
    return table.concat(t, ", ")
end

-- the fleet's turrets, every turret_s while any is up: in reach of you, their guns seen firing
local TURRET_GUN_BASE = "LiveBullet"
local function turretTick(R, now, you)
    if not (SPORT and SPORT.turrets and next(SPORT.turrets)) then return end
    local reach = (CFG.specials.spaceport and CFG.specials.spaceport.fcs and CFG.specials.spaceport.fcs.search_m or 25000)
    for a, tr in pairs(SPORT.turrets) do
        if not valid(tr.obj) then SPORT.turrets[a] = nil
        else
            local p = you and at(tr.obj)
            if p then
                tr.lastM = dist(p, you)
                if tr.lastM <= reach then tr.inReach = true end
            end
        end
    end
    local okB, list = pcall(FindAllOf, TURRET_GUN_BASE)
    for _, b in ipairs(okB and list or {}) do
        if valid(b) then
            local okH, hidden = pcall(function() return b.bHidden end)
            if okH and hidden == false then
                local okO, o = pcall(function() return b.OwningGameObject end)
                local tr = okO and valid(o) and SPORT.turrets[addrOf(o)]
                if tr then tr.gun = true end
            end
        end
    end
end
local function turretReport(secs)
    if not (SPORT and SPORT.turrets and next(SPORT.turrets)) then return end
    local reach = (CFG.specials.spaceport and CFG.specials.spaceport.fcs and CFG.specials.spaceport.fcs.search_m or 25000)
    local by = {}
    for _, tr in pairs(SPORT.turrets) do
        local g = by[tr.cls] or { n = 0, fired = 0, shots = 0, guns = 0, km = 0, kmN = 0, idle = 0 }
        by[tr.cls] = g
        g.n = g.n + 1
        if (tr.shots or 0) > 0 then g.fired, g.shots = g.fired + 1, g.shots + tr.shots end
        if tr.gun then g.guns = g.guns + 1 end
        if tr.atKmN and tr.atKmN > 0 then g.km, g.kmN = g.km + tr.atKm, g.kmN + tr.atKmN end
        if tr.inReach and (tr.shots or 0) == 0 and not tr.gun then g.idle = g.idle + 1 end
        tr.shots, tr.gun, tr.inReach, tr.atKm, tr.atKmN = 0, false, false, 0, 0
    end
    local t = {}
    for cls, g in pairs(by) do
        t[#t + 1] = string.format("%s: %d of %d fired (%d missiles%s), %d guns seen firing, %d idle with you inside %d km",
            cls, g.fired, g.n, g.shots, g.kmN > 0 and string.format(", you %.1f km off at fire on average", g.km / g.kmN) or "",
            g.guns, g.idle, math.floor(reach / 1000))
    end
    table.sort(t)
    log(string.format("fleet: last %d s: %s", secs, table.concat(t, "; ")))
end

function WLOG.tick(now)
    local c = cfg()
    if c.enabled == false or not D or not now then return end
    if now < (WLOG.nextAt or 0) then return end
    WLOG.nextAt = now + (tonumber(c.every_s) or 0.5)
    local R = run()
    carriedTick(R, now)
    local byAddr = {}
    for _, p in ipairs(planes or {}) do if p.addr and not p.down then byAddr[p.addr] = p end end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    local pawnAddr = pawn and valid(pawn) and addrOf(pawn) or nil
    local you, hp = nil, nil
    if pawnAddr then
        you = at(pawn)
        pcall(function() hp = pawn.HealthInternal end)
    end
    if type(hp) == "number" then
        if R.hp and hp < R.hp - 0.5 then R.dropAt = now end
        R.hp = hp
    end
    if SPORT and SPORT.partsTick then pcall(SPORT.partsTick) end
    if now >= (R.turAt or 0) then
        R.turAt = now + (tonumber(c.turret_s) or 5)
        local okT, errT = pcall(turretTick, R, now, you)
        if not okT and not R.turErr then R.turErr = true; log("fleet: turret watch error " .. tostring(errT)) end
    end
    local total, flying, cur, hidErr = 0, 0, {}, 0
    for _, base in ipairs(BASES) do
        local okF, list = pcall(FindAllOf, base)
        for _, w in ipairs(okF and list or {}) do
            local a = valid(w) and addrOf(w)
            if a and not cur[a] then
                total = total + 1
                local okH, hidden = pcall(function() return w.bHidden end)
                local shown = okH and hidden == false
                if not okH or type(hidden) ~= "boolean" then hidErr = hidErr + 1 end
                local prev = R.state[a]
                local st = { shown = shown, owner = prev and prev.owner }
                if shown then
                    flying = flying + 1
                    local kind, p, who, oa = ownerOf(w, byAddr, pawnAddr)
                    st.owner = oa
                    local isNew = not (prev and prev.shown) or (prev.owner ~= oa)
                    local tk = R.track[a]
                    if tk and not tk.goneAt and isNew then tk.goneAt = now end     -- (reused: the last one's gone)
                    if tk and not tk.goneAt then                     -- (one at you, flying: its nearest pass, its target)
                        local mp = you and at(w)
                        if mp then tk.minM = math.min(tk.minM, dist(mp, you)) end
                        pcall(function()
                            local t = w.TargetToHome
                            if valid(t) and addrOf(t) ~= pawnAddr and short(t):lower():find("flare", 1, true) then tk.decoy = true end
                        end)
                    end
                    if isNew and kind ~= "you" and kind ~= "none" then
                        local weapon = short(w)
                        local okTg, tg = pcall(function() return w.TargetToHome end)
                        if you and okTg and valid(tg) and addrOf(tg) == pawnAddr and not weapon:find("^Default__") then
                            if R.track[a] and R.track[a].goneAt then settle(R, R.track[a]) end
                            local mp = at(w)
                            local d = mp and dist(mp, you) or 0
                            R.track[a] = { weapon = weapon, who = who, t0 = now, d0 = d / 1000, minM = d, decoy = false }
                        end
                        local tr = kind == "other" and SPORT and SPORT.turrets and oa and SPORT.turrets[oa]
                        if tr then
                            tr.shots = (tr.shots or 0) + 1
                            if you and valid(tr.obj) then
                                local tp = at(tr.obj)
                                if tp then tr.atKm, tr.atKmN = (tr.atKm or 0) + dist(tp, you) / 1000, (tr.atKmN or 0) + 1 end
                            end
                        end
                        if not weapon:find("^Default__") then
                            local key = who .. "|" .. weapon                -- (the first of each weapon by each airframe)
                            R.fired[weapon] = (R.fired[weapon] or 0) + 1
                            local wn = R.win[weapon] or { n = 0, by = {} }
                            wn.n = wn.n + 1
                            wn.by[who] = (wn.by[who] or 0) + 1
                            R.win[weapon] = wn
                            if not R.said[key] then
                                R.said[key] = true
                                local tgt = "none"
                                pcall(function() local t = w.TargetToHome; if valid(t) then tgt = (addrOf(t) == pawnAddr) and "you" or short(t) end end)
                                local row = p and D.flightRow and D.flightRow[p.unit] or nil
                                log(string.format("weapons: first launch of %s by %s%s at %s (%s)", weapon, who,
                                    p and string.format(" (%s, %s)", tostring(p.unit), tostring(row or "?")) or (kind == "other" and " (not an enemy plane)" or ""),
                                    tgt, base))
                            end
                        end
                    end
                end
                cur[a] = st
            end
        end
    end
    if not R.primed then                                  -- (the first look learns what's up: nothing counted)
        R.primed = true
        for k in pairs(R.fired) do R.fired[k] = nil end
        R.win, R.said = {}, {}
        log(string.format("weapons: watching the enemies' launches: %d weapon objects, %d shown now (not counted)", total, flying))
    end
    if total > 0 and hidErr == total and not R.hidSaid then
        R.hidSaid = true
        log("weapons: no weapon's bHidden could be read: launches can't be told apart from idle pool items")
    end
    for a, tk in pairs(R.track) do                        -- (one at you that's gone: settled a second on)
        if not tk.goneAt and not (cur[a] and cur[a].shown) then tk.goneAt = now end
        if tk.goneAt and now - tk.goneAt >= 1.0 then settle(R, tk); R.track[a] = nil end
    end
    R.state = cur
    R.total, R.flying = total, flying
    local every = tonumber(c.summary_s) or 60
    R.winAt = R.winAt or now
    if now - R.winAt >= every then
        local parts = {}
        for weapon, wn in pairs(R.win) do
            local by = {}
            for who, n in pairs(wn.by) do by[#by + 1] = string.format("%s %d", who, n) end
            table.sort(by)
            parts[#parts + 1] = string.format("%s x%d (%s)", weapon, wn.n, table.concat(by, ", "))
        end
        table.sort(parts)
        local never = {}
        for weapon, cw in pairs(R.carried) do
            if not R.fired[weapon] then never[#never + 1] = string.format("%s (%d planes: %s)", weapon, cw.planes, table.concat(cw.units, ", ")) end
        end
        table.sort(never)
        if #parts > 0 or not R.poolSaid then
            log(string.format("weapons: last %d s: %s; carried by enemies but never fired this run: %s; %d weapon objects, %d in flight",
                math.floor(now - R.winAt + 0.5), #parts > 0 and table.concat(parts, ", ") or "nothing launched",
                #never > 0 and table.concat(never, ", ") or "none", total, flying))
            R.poolSaid = true
        end
        if next(R.out) then
            log(string.format("missiles at you: last %d s: %s; this run: %s", math.floor(now - R.winAt + 0.5), outcomes(R.out),
                outcomes(R.outRun)))
        end
        local okF, errF = pcall(turretReport, math.floor(now - R.winAt + 0.5))
        if not okF and not R.turRepErr then R.turRepErr = true; log("fleet: report error " .. tostring(errF)) end
        R.win, R.winAt, R.out = {}, now, {}
    end
end
end
