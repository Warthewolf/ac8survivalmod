-- sv_spweapons.lua: the enemies' special weapons fired.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (... sv_stats, sv_weaponlog, sv_spweapons, sv_tells ...);
-- a name another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- special weapons
-- The user, 2026-10-31: "I want the Enemies to fire their Special Weapons too". sv_rows.lua puts a special (CFG.special
-- .fcs: QAAM, 2AAM, LAAM, HCAA) in each enemy row's first free fire-control slot from 3, but the weapons log of the same
-- day showed them carried and never fired (the standard missiles every minute): the fighters' AI never picks that slot.
-- So every check_s, an enemy plane whose row has its special in slot 3 (SR.spSlot; the jammer's ECM pod is there, its
-- special in 4: not fired) fires it at you (RE_SV_SpecFire_<NN><L>, tools/survival_events.py SPEC_SLOT: Mission 19's
-- LiveFireOneShotWeapon, WN_WEAPON_4 at "Player", hard rule 40) when you're inside cone_deg of its nose at that weapon's
-- range (CFG.special.fire.ranges, by its fire control's name), first_s after it appears, then every every_s at most, at
-- most max_per_min across the sky; not a held Wolf trap (its wait is the trap). Its ammunition is its fire control's: a
-- slot that's empty fires nothing. The host's (or solo), at the host's plane (the event is each game's own: sv_coop.lua
-- KEEP_EVENTS). `specials: <unit> <letter> (<row>) fires its <weapon> at you, N km` once each, and the weapons log
-- (sv_weaponlog.lua) says whether it launched.
SPW = {}
do
SPW.FCS_SLOT = 3                                  -- (WN_WEAPON_4: tools/survival_events.py SPEC_SLOT, asserted there)

local function cfg() return CFG.special and CFG.special.fire or {} end

-- the range band (km) of a fire control: the first of `ranges`' names in it, else default
local function band(id, ranges)
    for k, v in pairs(ranges or {}) do
        if k ~= "default" and type(v) == "table" and tostring(id):find(k, 1, true) then return v[1] or 0, v[2] or 0 end
    end
    local d = ranges and ranges.default or { 2, 7 }
    return d[1] or 0, d[2] or 0
end

local function letter(k) return string.char(65 + k) end

function SPW.tick(now)
    local c = cfg()
    if c.enabled == false or not D or not now or D.state == "wait" or not (CFG.special and CFG.special.enabled) then return end
    if now < (SPW.nextAt or 0) then return end
    SPW.nextAt = now + (tonumber(c.check_s) or 1)
    if COOP and COOP.client and COOP.client() then return end           -- (the host's rounds: its planes)
    if not (SR and SR.spSlot) then return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not (pawn and valid(pawn)) then return end
    local you
    pcall(function() local v = pawn:K2_GetActorLocation(); you = { X = v.X, Y = v.Y, Z = v.Z } end)
    if not you then return end
    local recent = {}
    for _, t in ipairs(SPW.recent or {}) do if now - t < 60 then recent[#recent + 1] = t end end
    SPW.recent = recent
    local cap = tonumber(c.max_per_min) or 8
    if #recent >= cap then return end
    local cone = math.cos(math.rad(tonumber(c.cone_deg) or 35))
    local first, every = tonumber(c.first_s) or 10, tonumber(c.every_s) or 25
    SPW.said = SPW.said or {}
    for _, p in ipairs(planes or {}) do
        if #SPW.recent >= cap then break end
        local k = p.k
        if not p.down and p.unit and k and k >= 0 and k <= 5 and poolIndex(p.unit) and now - (p.born or now) >= first
            and now >= (p.spwAt or 0) and valid(p.obj) and not (D.wolf and D.wolf[p.unit] and D.wolf[p.unit].held[k]) then
            local lr = k == 0 and D.leadRow and D.leadRow[p.unit]
            local row = (lr and lr.row) or (D.flightRow and D.flightRow[p.unit])
            if row and SR.spSlot[row] == SPW.FCS_SLOT then
                local at, fwd
                pcall(function()
                    local v, f = p.obj:K2_GetActorLocation(), p.obj:GetActorForwardVector()
                    at, fwd = { X = v.X, Y = v.Y, Z = v.Z }, { X = f.X, Y = f.Y, Z = f.Z }
                end)
                if at and fwd then
                    local dx, dy, dz = you.X - at.X, you.Y - at.Y, you.Z - at.Z
                    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                    local weapon = SR.spWeapon and SR.spWeapon[row] or "?"
                    local lo, hi = band(weapon, c.ranges)
                    local km = d / 100000
                    if d > 0 and km >= lo and km <= hi and (dx * fwd.X + dy * fwd.Y + dz * fwd.Z) / d >= cone then
                        local ev = string.format("RE_SV_SpecFire_%02d%s", poolIndex(p.unit), letter(k))
                        local r = type(SV_Event) == "function" and SV_Event(ev) or "n/a"
                        p.spwAt = now + every
                        SPW.recent[#SPW.recent + 1] = now
                        SPW.fired = (SPW.fired or 0) + 1
                        local key = row .. "|" .. weapon
                        if not SPW.said[key] then
                            SPW.said[key] = true
                            log(string.format("specials: %s %s (%s) fires its %s at you, %.1f km (%s: %s)", p.unit, letter(k), row,
                                weapon, km, ev, tostring(r)))
                        end
                    end
                end
            end
        end
    end
end
end
