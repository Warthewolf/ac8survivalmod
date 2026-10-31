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
        WLOG.r = { D = D, carried = {}, fired = {}, said = {}, loadouts = {}, state = {}, win = {}, winAt = nil, done = {} }
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
                    if isNew and kind ~= "you" and kind ~= "none" then
                        local weapon = short(w)
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
        R.win, R.winAt = {}, now
    end
end
end
