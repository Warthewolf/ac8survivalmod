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

---------------------------------------------------------------------------------------------------- missiles at once
-- The user, 2026-10-31: "is there a hard cap on how many AI turrets can target the player at once? I've only ever seen 4
-- missiles launch at me at one time from 4 different targets". There is: the game lets at most MissileNumberLimitPlane
-- missiles from aircraft and MissileNumberLimitNonPlane from everything else (ships, SAM sites, turrets) be in the air at a
-- player at once, 2 and 2 on every difficulty (DT_NPC_Difficulty, Story to Ace), kept on the player's plane
-- (LivePlayerPlane MaxPlaneAttackerMissiles / MaxNonPlaneAttackerMissiles; MaxPursuitAttackers the aircraft chasing it).
-- CFG.attackers ([attackers]): your plane's own (an instance: the stock table stays as it is) set to plane_missiles /
-- nonplane_missiles / pursuers (0: the game's) every check_s, again when the game puts them back (logged once a plane).
-- Each player's own plane on their own game (co-op too).
ATK = {}
function ATK.tick(now)
    local c = CFG.attackers
    if type(c) ~= "table" or c.enabled == false or not now or now < (ATK.nextAt or 0) then return end
    ATK.nextAt = now + (tonumber(c.check_s) or 2)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not (pawn and valid(pawn)) then return end
    local a = addrOf(pawn)
    local want = { MaxPlaneAttackerMissiles = tonumber(c.plane_missiles) or 0, MaxNonPlaneAttackerMissiles = tonumber(c.nonplane_missiles) or 0,
                   MaxPursuitAttackers = tonumber(c.pursuers) or 0 }
    local fresh = a ~= ATK.addr
    if fresh then ATK.addr, ATK.was, ATK.reverts = a, {}, 0 end
    local set, back = {}, false
    for f, w in pairs(want) do
        local okR, v = pcall(function() return pawn[f] end)
        if okR and type(v) == "number" then
            if fresh then ATK.was[f] = v end
            if w > 0 and v ~= w then
                if not fresh then back = true end
                local okW = pcall(function() pawn[f] = math.floor(w) end)
                set[#set + 1] = string.format("%s %d -> %s", f, v, okW and tostring(math.floor(w)) or "NOT set")
            end
        elseif fresh then
            set[#set + 1] = f .. " not readable"
        end
    end
    if fresh then
        table.sort(set)
        -- (the attacks' waits too, for the record: the plane's own ranges and the difficulty's modifiers, DT_Difficulty
        -- CooldownPursuit / NonpursuitAttackTimeModifier: Casual 150 % ... Ace 25 %)
        local waits = "?"
        pcall(function()
            local r1, r2 = pawn.CooldownPursuitAttackTimerRange_CP, pawn.CooldownNonpursuitAttackTimerRange_CP
            waits = string.format("chasers %.1f-%.1f s, others %.1f-%.1f s", r1.min, r1.max, r2.min, r2.max)
        end)
        pcall(function()
            local row = FindFirstOf("LiveDifficultyManager").CurrentDifficultyDataTableRow
            waits = waits .. string.format(" (the difficulty's x%.0f%% / x%.0f%%)", row.CooldownPursuitAttackTimeModifier,
                row.CooldownNonpursuitAttackTimeModifier)
        end)
        log(string.format("attackers: your plane's missiles-at-once limits: %s (the game's: planes %s, ships / SAMs %s, chasers %s); "
            .. "waits between attacks: %s", #set > 0 and table.concat(set, ", ") or "as set", tostring(ATK.was.MaxPlaneAttackerMissiles),
            tostring(ATK.was.MaxNonPlaneAttackerMissiles), tostring(ATK.was.MaxPursuitAttackers), waits))
    elseif back then
        ATK.reverts = ATK.reverts + 1
        if ATK.reverts == 1 then log("attackers: the game put your plane's limits back; set again (" .. table.concat(set, ", ") .. ")") end
    end
end

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
