-- sv_tactical.lua: the STORE's tactical items, upgrades and SECOND CHANCE (economy review of 2026-10-25).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- RUN.items[kind]: tactical items carried (airstrike / ecm / decoy, CFG.tactical); RUN.ups[key]: upgrade tiers bought
-- (airframe / bays / gun / flares, CFG.shop.items Up*); RUN.insured: a SECOND CHANCE held (CFG.insurance).
TAC = { ecmUntil = nil, strike = nil }
UP = { base = {}, gunBase = {} }

---------------------------------------------------------------------------------------------------- tactical items
do
local TEXT = { airstrike = "AIRSTRIKE", ecm = "ECM", decoy = "DECOY" }

local function pawnOf()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    return valid(pawn) and pawn or nil
end

-- Is a fight on: a round spawning or fighting, you airborne?
local function fighting()
    return D and (D.state == "spawning" or D.state == "wave" or D.state == "fighting") and not playerOnAirfield()
end

-- The flight `unit` may be struck or decoyed: a pool or bomber flight, not a special's, no ace leading it.
local function ordinary(unit)
    if not unit or not (poolIndex(unit) or BOMBER_UNIT[unit]) then return false end
    return not (D.aceOf and D.aceOf[unit])
end

-- ((0.73.78, plan G6) The flight `unit` is an ace squadron's, any of its flights (the wing's too, which `ordinary` let
-- an airstrike hit: Harvest's wing flights in the tester's run of 2026-11-02): the host's spawner's record (D.aceSquad,
-- D.aceOf); a joiner has none, so the rows the host's spawn set there (SPW.row / leadRow, sv_coop.lua doSpawn): an ace
-- row, sv_ace_<tier>_<airframe>_<part>.)
local function aceFlight(unit)
    if (D.aceSquad and D.aceSquad[unit]) or (D.aceOf and D.aceOf[unit]) then return true end
    if type(SPW) ~= "table" then return false end
    for _, t in ipairs({ SPW.row or {}, SPW.leadRow or {} }) do
        local r = t[unit]
        if type(r) == "string" and r:lower():find("^sv_ace_") then return true end
    end
    return false
end
TAC.aceFlight = aceFlight                             -- (the offline test's)

-- Enemy flights near you: { [unit] = { n = aircraft up, d = nearest km, planes = { p, ... } } }, and the aircraft count
-- within km of you.
local function flightsNear(km_)
    local you, out, near = playerLocation(), {}, 0
    if not you then return out, 0 end
    for _, p in ipairs(planes) do
        if not p.down and p.unit and p.at and valid(p.obj) then
            local d = km(p.at, you)
            if d <= km_ then
                near = near + 1
                local f = out[p.unit] or { n = 0, d = math.huge, planes = {} }
                out[p.unit] = f
                f.n, f.d = f.n + 1, math.min(f.d, d)
                f.planes[#f.planes + 1] = p
            end
        end
    end
    return out, near
end

-- Is flight `unit` standing down after a decoy now?
function TAC.decoyed(unit, now)
    local t = D and D.decoyed and D.decoyed[unit]
    return t ~= nil and (now or D.now or 0) < t
end

-- The tactical items carried, for the HUD ("AIRSTRIKE 1  ECM 2"), or nil when none
function TAC.line(now)
    local parts = {}
    for _, k in ipairs({ "airstrike", "ecm", "decoy" }) do
        local n = RUN.items and RUN.items[k] or 0
        if n > 0 then parts[#parts + 1] = TEXT[k] .. " " .. n end
    end
    -- (its news for the HUD's info key, sv_hud.lua: what you carry, not the ECM's seconds)
    local news = table.concat(parts, " ") .. (RUN.insured and " SECOND CHANCE" or "")
    if TAC.ecmUntil and now and now < TAC.ecmUntil then parts[#parts + 1] = string.format("ECM ON %d S", math.ceil(TAC.ecmUntil - now)) end
    if RUN.insured then parts[#parts + 1] = "SECOND CHANCE" end
    if #parts == 0 then return nil end
    return table.concat(parts, "   "), news
end

-- Use one `kind` now (how: "key" or "auto"); true when it went.
function TAC.use(kind, how)
    local c, t, now = CFG.tactical, CFG.hud.text, D and D.now
    if not (now and fighting()) then
        if how == "key" then log("tactical: " .. kind .. " held: not in a fight") end
        return false
    end
    RUN.items = RUN.items or {}
    if (RUN.items[kind] or 0) <= 0 then
        if how == "key" then hudCallout(TEXT[kind] .. ": NONE LEFT", "BUY MORE IN THE STORE") end
        return false
    end
    if kind == "airstrike" then
        -- ((0.73.78, plan G6) the player's call only: its key (the auto call at auto_near enemies is gone, autoTick)
        if how ~= "key" then log("tactical: airstrike (" .. tostring(how) .. ") refused: only its key calls it"); return false end
        if TAC.strike then return false end                          -- (one at a time)
        -- ((0.73.78, plan G6) per_round a round: the round's call made, held till the next round)
        local lim = math.floor(tonumber(c.airstrike.per_round) or 0)
        local calls = (RUN.strikeCalls and RUN.strikeCalls.round == D.round) and RUN.strikeCalls.n or 0
        if lim > 0 and calls >= lim then
            hudCallout(t.airstrike_none, string.format(t.airstrike_once_sub, D.round + 1))
            log(string.format("tactical: airstrike held: %d called in round %d already (%d a round, [tactical.airstrike] per_round)",
                calls, D.round, lim))
            return false
        end
        local fl = flightsNear(c.airstrike.range_km)
        local best, bu
        local aces = 0
        for u, f in pairs(fl) do
            if ordinary(u) and aceFlight(u) then aces = aces + f.n            -- ((0.73.78, G6) never an ace squadron's)
            elseif ordinary(u) and (not best or f.n > best.n or (f.n == best.n and f.d < best.d)) then best, bu = f, u end
        end
        if not best then
            hudCallout(t.airstrike_none, aces > 0 and t.airstrike_aces_sub or string.format(t.airstrike_none_sub, c.airstrike.range_km))
            if aces > 0 then
                log(string.format("tactical: airstrike held: only an ace squadron's flights within %d km (%d aircraft): never on them",
                    c.airstrike.range_km, aces))
            end
            return false
        end
        -- ((0.73.78, G6) at most max_hit of the flight, the nearest you first)
        local hit, max = best.planes, math.floor(tonumber(c.airstrike.max_hit) or 0)
        if max > 0 and #hit > max then
            local you = playerLocation()
            table.sort(hit, function(a, b) return km(a.at, you) < km(b.at, you) end)
            hit = { table.unpack(hit, 1, max) }
        end
        RUN.strikeCalls = { round = D.round, n = calls + 1 }
        TAC.strike = { unit = bu, at = now + c.airstrike.delay_s, planes = hit, round = D.round }
        hudCallout(t.airstrike, string.format(t.airstrike_sub, #hit))
        log(string.format("tactical: airstrike (%s) on %s, %d of its %d aircraft %.1f km from you, in %d s (round %d's %d of %s%s)",
            how, bu, #hit, best.n, best.d, c.airstrike.delay_s, D.round, calls + 1, lim > 0 and tostring(lim) or "any",
            aces > 0 and string.format("; %d of an ace squadron's near, spared", aces) or ""))
    elseif kind == "ecm" then
        if TAC.ecmUntil and now < TAC.ecmUntil then return false end
        TAC.ecmUntil, TAC.ecmN = now + c.ecm.ecm_s, 0
        hudCallout(t.ecm, string.format(t.ecm_sub, c.ecm.ecm_s))
        log(string.format("tactical: ECM burst (%s) for %d s", how, c.ecm.ecm_s))
    elseif kind == "decoy" then
        local fl = flightsNear(c.decoy.range_km)
        local best, bu
        for u, f in pairs(fl) do
            local i = poolIndex(u)
            if i and ordinary(u) and not TAC.decoyed(u, now) and (not best or f.d < best.d) then best, bu = f, u end
        end
        if not best then
            if how == "key" then hudCallout(t.decoy_none, string.format(t.decoy_none_sub, c.decoy.range_km)) end
            return false
        end
        local i = poolIndex(bu)
        local r = type(SV_Event) == "function" and SV_Event(string.format("RE_SV_Decoy_%02d", i)) or -5
        if r ~= 1 then
            log(string.format("tactical: decoy on %s not fired (%s)", bu, SV_ERR[r] or tostring(r)))
            return false
        end
        D.decoyed = D.decoyed or {}
        D.decoyed[bu] = now + c.decoy.decoy_s
        queueEvent(now + c.decoy.decoy_s, string.format("RE_SV_DecoyEnd_%02d", i), bu .. " back in the fight after the decoy")
        hudCallout(t.decoy, string.format(t.decoy_sub, best.n))
        log(string.format("tactical: decoy (%s): %s (%d aircraft, %.1f km) stands down for %d s", how, bu, best.n, best.d, c.decoy.decoy_s))
    end
    RUN.items[kind] = RUN.items[kind] - 1
    RUN.dirty = true
    LB.stat("items", 1)
    return true
end

-- The airstrike's hits: every aircraft of its flight still up, through the game's own damage (ModifyHealth with you as
-- the cause, so it's your kill in the game's eyes; KILLS_HEALTH_DEATH.md 1: it works on AI objects)
local function strikeTick(now)
    local s = TAC.strike
    if not s or now < s.at then return end
    TAC.strike = nil
    local pawn, n, failed = pawnOf(), 0, nil
    for _, p in ipairs(s.planes) do
        if not p.down and valid(p.obj) then
            p.struck = true
            local ok, err = pcall(function() p.obj:ModifyHealth(-1000000.0, pawn, true) end)
            if ok then n = n + 1 else failed = failed or tostring(err) end
        end
    end
    if n == 0 then                                                    -- (nothing hit: it's back, and the round's call)
        RUN.items.airstrike = (RUN.items.airstrike or 0) + 1; RUN.dirty = true
        local sc = RUN.strikeCalls
        if sc and sc.round == s.round then sc.n = math.max(0, sc.n - 1) end
    end
    local t = CFG.hud.text
    if n > 0 then hudCallout(string.format(t.airstrike_hit, n), nil) end
    log(string.format("tactical: airstrike on %s: %d hit%s", s.unit, n, failed and (" (" .. failed .. ")") or ""))
end

-- A missile (HIT.msl entry) homing on you: true, false (on something else), or nil when its target can't be read
local function onYou(m, pa)
    if not liveAddr(m.obj) then return nil end
    local ok, tgt = pcall(function() return m.obj.TargetToHome end)
    local ta = ok and tgt and liveAddr(tgt)
    if not ta then return nil end
    return ta == pa
end

-- ECM: every enemy missile homing on you (or, its target unreadable, within kill_m) inside range_km loses its lock;
-- one still within kill_m is made harmless (damage 0), flying on until it runs out (HIT.msl: every missile but the
-- player's, with its distance). Never destroyed from here: a run of 2026-10-25 destroyed 2 that way, and the enemies
-- fired no missile again (their launchers still counted those 2 in flight), the missile alert stayed on (the warning
-- still tracked them) and the game crashed 30 s after the burst.
local function ecmTick(now)
    if not TAC.ecmUntil then return end
    if now >= TAC.ecmUntil then
        log(string.format("tactical: ECM burst over: %d missiles broken", TAC.ecmN or 0))
        TAC.ecmUntil = nil
        return
    end
    local c, pawn = CFG.tactical.ecm, pawnOf()
    local pa = pawn and addrOf(pawn)
    for _, m in ipairs(HIT.msl) do
        if m.d and m.d <= c.range_km * 1000 and liveAddr(m.obj) and not m.ecmDone then
            local mine = onYou(m, pa)
            if mine or (mine == nil and m.d <= c.kill_m) then
                if not m.ecm then
                    m.ecm = true
                    TAC.ecmN = (TAC.ecmN or 0) + 1
                    pcall(function() m.obj.bIsHoming = false end)
                end
                if m.d <= c.kill_m then
                    m.ecmDone = true
                    pcall(function() m.obj.damage = 0 end)
                end
            end
        end
    end
end

-- The auto triggers (CFG.tactical <kind>.auto), once a second
local function autoTick(now)
    if now < (TAC.autoAt or 0) then return end
    TAC.autoAt = now + 1
    local c = CFG.tactical
    if (RUN.items.ecm or 0) > 0 and c.ecm.auto and not TAC.ecmUntil then       -- (missiles on you: not the allies')
        local pawn, n = pawnOf(), 0
        local pa = pawn and addrOf(pawn)
        for _, m in ipairs(HIT.msl) do
            if m.d and m.d <= c.ecm.auto_km * 1000 and liveAddr(m.obj) and now - (m.seen or -1e9) < 1 then
                local mine = onYou(m, pa)
                if mine or (mine == nil and m.d <= 1500) then n = n + 1 end
            end
        end
        if n >= c.ecm.auto_missiles then TAC.use("ecm", "auto") end
    end
    -- ((0.73.78, plan G6) no airstrike here any more: it went by itself at auto_near enemies within auto_km (in the
    -- tester's run of 2026-11-02 two players called 14 in one round); it's always the player's call now, Ctrl+F1)
    if (RUN.items.decoy or 0) > 0 and c.decoy.auto then
        local fl = flightsNear(c.decoy.auto_km)
        for u, f in pairs(fl) do
            if f.n >= c.decoy.auto_size and poolIndex(u) and not TAC.decoyed(u, now) then TAC.use("decoy", "auto"); break end
        end
    end
end

function TAC.tick(now)
    if not D then return end
    RUN.items = RUN.items or {}
    strikeTick(now)
    ecmTick(now)
    if fighting() then autoTick(now) end
end

-- the keys (CFG.tactical.keys): Ctrl+F1 airstrike, Ctrl+F2 ECM burst, Ctrl+F3 decoy; Ctrl+F4 the allies' next order
if type(RegisterKeyBind) == "function" and Key and CFG.tactical.keys then
    local mods = (ModifierKey and ModifierKey.CONTROL) and { ModifierKey.CONTROL } or {}
    for key, kind in pairs({ F1 = "airstrike", F2 = "ecm", F3 = "decoy" }) do
        if Key[key] then
            pcall(RegisterKeyBind, Key[key], mods, function()
                ExecuteInGameThread(function()
                    local ok, err = pcall(TAC.use, kind, "key")
                    if not ok then log("tactical: " .. kind .. " error " .. tostring(err)) end
                end)
            end)
        end
    end
    if Key.F4 and CFG.allies.orders.key then
        pcall(RegisterKeyBind, Key.F4, mods, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(function() if D then ALLY.nextOrder("key") end end)
                if not ok then log("allies: order key error " .. tostring(err)) end
            end)
        end)
    end
end
end

---------------------------------------------------------------------------------------------------- upgrades
-- Each tier of RUN.ups on the player's aircraft, checked every 2 s (a new aircraft gets them again): AIRFRAME its
-- MaxHealth (its health raised by the same share), WEAPON BAYS its missile and special weapon maxima (the native
-- runtime's SV_AmmoMax, 0.19.0), FLARE PODS its weapon activator's MaxFlareCount (LivePlayerWeaponActivator +0x27c, the
-- count the flare code caps at: tools/re/AMMO.md), GUN its gun class's default damage (MachineGunClass; restored by
-- TAC.reset). Each one's stock value is read from the aircraft once, before Survival changes it.
do
local function activator(pawn)
    if liveObj(UP.act) and UP.actPawn == addrOf(pawn) then return UP.act end   -- (0.73.73: liveObj: kept between ticks)
    UP.act, UP.actPawn = nil, nil
    local pa = addrOf(pawn)
    for _, a in ipairs(FindAllOf("LivePlayerWeaponActivator") or {}) do
        local ok, owner = pcall(function() return a:GetOwner() end)
        if ok and valid(owner) and addrOf(owner) == pa then UP.act, UP.actPawn = a, pa end
    end
    return UP.act
end

local function tier(key) return RUN.ups and RUN.ups[key] or 0 end

local function step(key)
    for _, it in pairs(CFG.shop.items) do if it.role == "upgrade" and it.up == key then return it.step end end
    return 0
end

-- (0.73.77, plan G2) AIRFRAME kept through the airfield: every stop there the game puts the aircraft's MaxHealth back
-- to its stock (120 on the FA-36) and its health to that full, and UP.apply's 2 s pass raised them again up to 2 s later,
-- so the hit log counted each reset as damage ("-30 HP ... health now 100% (120 HP)") and a player who looked saw the
-- stock health (cressendo, 0.73.76: "the FA-36 upgrade doesn't work"). Called every hit-log pass (sv_ladon.lua HIT.tick,
-- before it reads your health) and right after a repair (the STORE's, SECOND CHANCE's, a revive's): the upgrade's
-- MaxHealth back at once, the health as the same share of it (full after the game's own repair). True when it put it
-- back (HIT.tick then counts no hit); `why` for the log.
function UP.healthGuard(pawn, why)
    if not (CFG.upgrades.enabled and tier("airframe") > 0 and valid(pawn)) then return false end
    local b = UP.pawn == addrOf(pawn) and UP.base or nil          -- (the stock read by UP.apply on this aircraft)
    if not (b and b.health) then return false end
    local okM, mh = pcall(function() return pawn.MaxHealth end)
    if not (okM and type(mh) == "number" and mh > 0) then return false end
    local want = b.health * (1 + step("airframe") * tier("airframe"))
    if math.abs(mh - want) <= 0.01 then return false end
    local okH, h = pcall(function() return pawn.HealthInternal end)
    local frac = (okH and type(h) == "number") and math.min(1, h / (mh * 10)) or 1
    pcall(function() pawn.MaxHealth = want end)
    if okH and type(h) == "number" and h > 0 then pcall(function() pawn.HealthInternal = math.floor(want * 10 * frac + 0.5) end) end
    UP.guarded = (UP.guarded or 0) + 1
    if UP.guarded <= 3 or UP.guarded % 10 == 0 then
        log(string.format("upgrades: the game put your airframe back to %.0f HP (%s): tier %d's %.0f HP again at once, health %.0f%% "
            .. "of it (not a hit; %d times this run)", mh, why or "an airfield stop", tier("airframe"), want, frac * 100, UP.guarded))
    end
    return true
end

function UP.apply(pawn)
    if not (CFG.upgrades.enabled and valid(pawn)) then return end
    local pa = addrOf(pawn)
    if UP.pawn ~= pa then UP.pawn, UP.base = pa, {} end               -- a new aircraft: its own stock values
    local b = UP.base
    -- AIRFRAME
    local okM, mh = pcall(function() return pawn.MaxHealth end)
    if okM and type(mh) == "number" and mh > 0 then
        b.health = b.health or mh
        local want = b.health * (1 + step("airframe") * tier("airframe"))
        if math.abs(mh - want) > 0.01 then
            local okH, h = pcall(function() return pawn.HealthInternal end)
            local frac = (okH and type(h) == "number") and math.min(1, h / (mh * 10)) or 1
            pcall(function() pawn.MaxHealth = want end)
            if okH and type(h) == "number" and h > 0 then pcall(function() pawn.HealthInternal = math.floor(want * 10 * frac + 0.5) end) end
            log(string.format("upgrades: airframe tier %d: health %.0f -> %.0f (stock %.0f)", tier("airframe"), mh, want, b.health))
        end
    end
    -- WEAPON BAYS (the shop's A.max too, so a purchase made down at the airfield, where the counts can't be read, can
    -- go past the stock load; ammoTick loads it once they can)
    -- The stock full load is whatever the aircraft holds that Survival didn't set: the game puts its own back each time
    -- it reloads the aircraft (landing, take-off), and another special weapon picked down there has its own (a run of
    -- 2026-10-24: kept from the first read, a 10-round special was pushed to 24 at tier 0). A.bays[k]: the full load
    -- with the bays, which ammoTick waits for before it puts back what you had (that run: 36 specials bought, the
    -- take-off reload left 24 and the count went down to it, the money gone).
    if type(SV_AmmoMax) == "function" and A and A.applied then
        for k = 1, 3 do
            local cur = SV_Ammo(k, 1)
            if cur >= 0 and cur ~= b["set" .. k] then b["max" .. k] = cur end
            local base = b["max" .. k]
            if base and not b["fail" .. k] then             -- (one that didn't take stays at the aircraft's own)
                local want = math.floor(base * (1 + step("bays") * tier("bays")) + 0.5)
                A.max, A.bays = A.max or {}, A.bays or {}
                A.max[k], A.bays[k] = want, want
                if cur >= 0 and cur ~= want then
                    local r = SV_AmmoMax(k, want)
                    if type(r) ~= "number" or r < 0 then A.max[k], A.bays[k], b["fail" .. k] = cur, nil, true   -- (the shop sells to cur)
                    else b["set" .. k] = want end
                    log(string.format("upgrades: weapon bays tier %d: %s full load %d -> %d (stock %d): %s", tier("bays"),
                        ({ "missiles", "special 1", "special 2" })[k], cur, want, base, tostring(r)))
                end
            end
        end
    end
    local act = activator(pawn)
    if not act then return end
    -- FLARE PODS
    local okF, mf = pcall(function() return act.MaxFlareCount end)
    if okF and type(mf) == "number" then
        b.flares = b.flares or mf
        local want = b.flares + math.floor(step("flares")) * tier("flares")
        if mf ~= want then
            pcall(function() act.MaxFlareCount = want end)
            log(string.format("upgrades: flare pods tier %d: flares %d -> %d (stock %d)", tier("flares"), mf, want, b.flares))
        end
        local okR, now = pcall(function() return act.MaxFlareCount end)              -- (what it took)
        if A and okR and type(now) == "number" then A.max = A.max or {}; A.max[4] = now end
    end
    -- GUN (CFG.upgrades.gun_experimental)
    if CFG.upgrades.gun_experimental and tier("gun") > 0 then
        local ok, err = pcall(function()
            local cls = act.MachineGunClass
            local name = nameOf(cls)
            local g = UP.gunBase[name]
            if not g then
                local cdo = cls:GetCDO()
                g = { cdo = cdo, damage = cdo.damage, name = name }
                UP.gunBase[name] = g
            end
            local want = g.damage * (1 + step("gun") * tier("gun"))
            if math.abs(g.cdo.damage - want) > 0.0001 then
                g.cdo.damage = want
                log(string.format("upgrades: gun tier %d: %s damage %.3f -> %.3f", tier("gun"), name:match("[^%.]+$") or name, g.damage, want))
            end
        end)
        if not ok and not UP.gunSaid then UP.gunSaid = true; log("upgrades: the gun upgrade couldn't be applied: " .. tostring(err)) end
    end
end

-- Back to stock (a new run, or the run's over): the gun classes' default damage
function TAC.reset()
    for _, g in pairs(UP.gunBase) do pcall(function() g.cdo.damage = g.damage end) end
    UP.gunBase, UP.base, UP.pawn, UP.act, UP.actPawn, UP.guarded = {}, {}, nil, nil, nil, nil
    TAC.ecmUntil, TAC.strike, TAC.autoAt = nil, nil, nil
    INS.min, INS.pawn, INS.safeUntil = nil, nil, nil     -- (its fields only: INS.tick lives on the table)
end
end

---------------------------------------------------------------------------------------------------- SECOND CHANCE
-- RUN.insured (CFG.insurance): the aircraft's MinHealth held at `floor` of its full health (the game clamps every hit
-- at it: KILLS_HEALTH_DEATH.md 2), so a shoot-down stops there; at the floor it's repaired (RE_SV_RepairAircraft, as the
-- STORE's repair, and its health written), invulnerable for safe_s, and the SECOND CHANCE is used up.
-- Co-op's revives (sv_down.lua, CFG.coop.revive) hold a floor of their own under it, always while they're on: the higher
-- of the two is set, and theirs is read back and set again every pass (the game puts MinHealth back on a restore).
INS = {}
function INS.tick(now)
    local c = CFG.insurance
    local fl = (DOWN and DOWN.floor) and DOWN.floor() or 0        -- (co-op's floor_hp, or 0: solo as ever)
    if not (D and (c.enabled or fl > 0)) then return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return end
    if INS.safeUntil and now >= INS.safeUntil then
        INS.safeUntil = nil
        pcall(function() pawn:SetIsInvincible(false) end)
    end
    local okM, mh = pcall(function() return pawn.MaxHealth end)
    if not (okM and type(mh) == "number" and mh > 0) then return end
    local insured = c.enabled and RUN.insured
    local want = insured and math.max(mh * c.floor, fl) or fl
    local reset = false
    if fl > 0 and INS.min == want and INS.pawn == addrOf(pawn) then
        local okR, cur = pcall(function() return pawn.MinHealth end)
        reset = okR and type(cur) == "number" and math.abs(cur - want) > 0.001
    end
    if INS.min ~= want or INS.pawn ~= addrOf(pawn) or reset then
        -- the field itself: the game's SetMinHealth keeps whole health points only (its native 0x147d193b0 truncates, so
        -- 0.1 was 0 and co-op's floor never held: the user's run of 2026-10-30, shot down from 40 HP with the floor "put
        -- back" every pass); every hit is clamped at the field (KILLS_HEALTH_DEATH.md 2). SetMinHealth only if it can't
        -- be written, rounded up (never under the floor)
        local ok = pcall(function() pawn.MinHealth = want end)
        if not ok then ok = pcall(function() pawn:SetMinHealth(math.ceil(want)) end) end
        if reset then                                             -- (the game's: set again, counted)
            INS.resets = (INS.resets or 0) + 1
            if INS.resets <= 3 or INS.resets % 20 == 0 then
                log(string.format("insurance: your aircraft's floor was put back by the game; %.1f HP again%s (%d times)", want,
                    ok and "" or " (NOT set)", INS.resets))
            end
        else
            log(string.format("insurance: your aircraft's floor %.1f HP (%s)%s", want, insured and "SECOND CHANCE held"
                or (fl > 0 and "co-op's revives" or "none"), ok and "" or " (NOT set)"))
        end
        INS.min, INS.pawn = want, addrOf(pawn)
    end
    if not insured then return end
    local okH, h = pcall(function() return pawn.HealthInternal end)
    if okH and type(h) == "number" and h > 0 and h <= mh * 10 * c.floor + 1 then
        RUN.insured, RUN.dirty = false, true
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_RepairAircraft") or -5
        pcall(function() pawn.HealthInternal = math.floor(mh * 10 + 0.5) end)
        pcall(UP.healthGuard, pawn, "SECOND CHANCE's repair")   -- ((0.73.77) G2: the AIRFRAME upgrade's, if the repair took it)
        pcall(function() pawn:SetIsInvincible(true) end)
        INS.safeUntil = now + c.safe_s
        local t = CFG.hud.text
        hudCallout(t.insured, t.insured_sub)
        log(string.format("insurance: SECOND CHANCE used at %.1f HP: repaired (event %s), %d s invulnerable", h / 10,
            r == 1 and "fired" or tostring(r), c.safe_s))
        LB.stat("second_chance", 1)
        pcall(STATS.death, "saved")                      -- (what brought you down to it: sv_stats.lua)
    end
end
