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
-- slot that's empty fires nothing. Co-op (user, 2026-10-31: "it's paramount that Special Weapons target all, HOST and
-- JOINERS"): every game fires its own planes at its own player, the host its enemies at the host and each joiner the
-- host's enemies' copies there at that joiner, as their standard missiles already go (an AI's shots are decided on its
-- target's game: hard rule 48), each with its own cap; the event is never forwarded (sv_coop.lua KEEP_EVENTS: "Player"
-- is each game's own). A joiner knows each flight's rows from the host's spawn (sv_coop.lua doSpawn: SPW.noteRows, the
-- SV_SetAircraft ops it plays); nothing is fired at a player who's DOWN (sv_down.lua). `specials: <unit> <letter>
-- (<row>) fires its <weapon> at you, N km` once each, and the weapons log (sv_weaponlog.lua) says whether it launched.
SPW = {}
do
SPW.FCS_SLOT = 3                                  -- (WN_WEAPON_4: tools/survival_events.py SPEC_SLOT, asserted there)
SPW.row, SPW.leadRow = {}, {}                     -- (a joiner's: each flight's rows, from the host's spawns)

-- (a joiner) the rows the host's spawn of `unit` set (its ops: { row, idx }, idx -1 the whole flight, 0 its lead)
function SPW.noteRows(unit, ops)
    if type(unit) ~= "string" or type(ops) ~= "table" then return end
    SPW.leadRow[unit] = nil
    for _, op in ipairs(ops) do
        if type(op) == "table" and type(op.row) == "string" then
            if op.idx == 0 then SPW.leadRow[unit] = op.row elseif (tonumber(op.idx) or -1) < 0 then SPW.row[unit] = op.row end
        end
    end
end

-- plane p's row: its lead's own (an ace's) for object 0, else its flight's (the host's records, else a joiner's)
local function rowOf(p)
    local lr = p.k == 0 and ((D.leadRow and D.leadRow[p.unit] and D.leadRow[p.unit].row) or SPW.leadRow[p.unit])
    return lr or (D.flightRow and D.flightRow[p.unit]) or SPW.row[p.unit]
end

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
    if not (SR and SR.spSlot) then return end
    if DOWN and DOWN.me and DOWN.me() then return end                    -- (you're DOWN: a co-op revive's wait)
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
        if not p.down and p.unit and k and k >= 0 and k <= 5 and not p.spwSeen then p.spwSeen = now end   -- (its first look)
        if not p.down and p.unit and k and k >= 0 and k <= 5 and poolIndex(p.unit) and now - (p.spwSeen or now) >= first
            and now >= (p.spwAt or 0) and valid(p.obj) and not (D.wolf and D.wolf[p.unit] and D.wolf[p.unit].held[k]) then
            local row = rowOf(p)
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
