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
    if TAC.ecmUntil and now and now < TAC.ecmUntil then parts[#parts + 1] = string.format("ECM ON %d S", math.ceil(TAC.ecmUntil - now)) end
    if RUN.insured then parts[#parts + 1] = "SECOND CHANCE" end
    return #parts > 0 and table.concat(parts, "   ") or nil
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
        if TAC.strike then return false end                          -- (one at a time)
        local fl = flightsNear(c.airstrike.range_km)
        local best, bu
        for u, f in pairs(fl) do
            if ordinary(u) and (not best or f.n > best.n or (f.n == best.n and f.d < best.d)) then best, bu = f, u end
        end
        if not best then
            if how == "key" then hudCallout(t.airstrike_none, string.format(t.airstrike_none_sub, c.airstrike.range_km)) end
            return false
        end
        TAC.strike = { unit = bu, at = now + c.airstrike.delay_s, planes = best.planes }
        hudCallout(t.airstrike, string.format(t.airstrike_sub, best.n))
        log(string.format("tactical: airstrike (%s) on %s, %d aircraft %.1f km from you, in %d s", how, bu, best.n, best.d, c.airstrike.delay_s))
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
    if n == 0 then RUN.items.airstrike = (RUN.items.airstrike or 0) + 1; RUN.dirty = true end   -- (nothing hit: it's back)
    local t = CFG.hud.text
    if n > 0 then hudCallout(string.format(t.airstrike_hit, n), nil) end
    log(string.format("tactical: airstrike on %s: %d hit%s", s.unit, n, failed and (" (" .. failed .. ")") or ""))
end

-- A missile (HIT.msl entry) homing on you: true, false (on something else), or nil when its target can't be read
local function onYou(m, pa)
    local ok, tgt = pcall(function() return m.obj.TargetToHome end)
    if not (ok and valid(tgt)) then return nil end
    return addrOf(tgt) == pa
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
        if m.d and m.d <= c.range_km * 1000 and valid(m.obj) and not m.ecmDone then
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
            if m.d and m.d <= c.ecm.auto_km * 1000 and valid(m.obj) and now - (m.seen or -1e9) < 1 then
                local mine = onYou(m, pa)
                if mine or (mine == nil and m.d <= 1500) then n = n + 1 end
            end
        end
        if n >= c.ecm.auto_missiles then TAC.use("ecm", "auto") end
    end
    if (RUN.items.airstrike or 0) > 0 and c.airstrike.auto and not TAC.strike then
        local _, near = flightsNear(c.airstrike.auto_km)
        if near >= c.airstrike.auto_near then TAC.use("airstrike", "auto") end
    end
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
    if valid(UP.act) and UP.actPawn == addrOf(pawn) then return UP.act end
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
    UP.gunBase, UP.base, UP.pawn, UP.act, UP.actPawn = {}, {}, nil, nil, nil
    TAC.ecmUntil, TAC.strike, TAC.autoAt = nil, nil, nil
    INS.min, INS.pawn, INS.safeUntil = nil, nil, nil     -- (its fields only: INS.tick lives on the table)
end
end

---------------------------------------------------------------------------------------------------- SECOND CHANCE
-- RUN.insured (CFG.insurance): the aircraft's MinHealth held at `floor` of its full health (the game clamps every hit
-- at it: KILLS_HEALTH_DEATH.md 2), so a shoot-down stops there; at the floor it's repaired (RE_SV_RepairAircraft, as the
-- STORE's repair, and its health written), invulnerable for safe_s, and the SECOND CHANCE is used up.
INS = {}
function INS.tick(now)
    local c = CFG.insurance
    if not (c.enabled and D) then return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return end
    if INS.safeUntil and now >= INS.safeUntil then
        INS.safeUntil = nil
        pcall(function() pawn:SetIsInvincible(false) end)
    end
    local okM, mh = pcall(function() return pawn.MaxHealth end)
    if not (okM and type(mh) == "number" and mh > 0) then return end
    local want = RUN.insured and mh * c.floor or 0
    if INS.min ~= want or INS.pawn ~= addrOf(pawn) then
        local ok = pcall(function() pawn:SetMinHealth(want) end)
        if not ok then ok = pcall(function() pawn.MinHealth = want end) end
        INS.min, INS.pawn = want, addrOf(pawn)
        log(string.format("insurance: your aircraft's floor %.1f HP (%s)%s", want, RUN.insured and "SECOND CHANCE held" or "none",
            ok and "" or " (NOT set)"))
    end
    if not RUN.insured then return end
    local okH, h = pcall(function() return pawn.HealthInternal end)
    if okH and type(h) == "number" and h > 0 and h <= mh * 10 * c.floor + 1 then
        RUN.insured, RUN.dirty = false, true
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_RepairAircraft") or -5
        pcall(function() pawn.HealthInternal = math.floor(mh * 10 + 0.5) end)
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
