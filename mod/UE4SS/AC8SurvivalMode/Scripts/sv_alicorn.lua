-- sv_alicorn.lua: the Alicorn.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- alicorn
-- CFG.specials.alicorn; tools/survival_events.py ALCN_* builds the unit (EB_002's, without its pools), its lane and
-- its remote events (RE_SV_AlcnDive / Surface / Railgun / Volley / OpenCore / Advance / Remove).
do
local UNIT = "SV_Unit_Alicorn"

-- At the main menu: the Alicorn's Online Mode rows into the campaign tables (NPC, model, durability), before the
-- level loads (the spawner caches them then: hard rule 20). AddRow only; a model row's soft class is never read
-- (hard rule 29).
function SPC.alicornSetup()
    if SPC.alicornDone or not gameInstance() then return end
    local c = CFG.specials.alicorn
    SPC.alicornTries = (SPC.alicornTries or 0) + 1
    local pairs_, missing = {}, false
    for _, tp in ipairs(c.tables) do
        local from, to = loadObject(tp[1]), loadObject(tp[2])
        if not (from and to) then missing = true end
        pairs_[#pairs_ + 1] = { from, to, tp }
    end
    if missing then
        if SPC.alicornTries >= 20 then SPC.alicornDone = true; log("special: the Alicorn's tables didn't load; no Alicorn round") end
        return
    end
    SPC.alicornDone = true
    local added, total, lost = 0, 0, {}
    for _, p in ipairs(pairs_) do
        local from, to = p[1], p[2]
        pin(from, nameOf(from)); pin(to, nameOf(to))
        for _, row in ipairs(rowList(from) or {}) do
            total = total + 1
            local _, have = dtCall(to, "FindRow", row)
            if have == nil then
                local _, r = dtCall(from, "FindRow", row)
                if r ~= nil then dtCall(to, "AddRow", row, r); _, have = dtCall(to, "FindRow", row) end
            end
            if have ~= nil then added = added + 1 else lost[#lost + 1] = row end
        end
    end
    SPC.alicornReady = total > 0 and #lost == 0
    log(string.format("special: the Alicorn's rows: %d of %d in the campaign tables%s", added, total,
        #lost > 0 and (" (missing: " .. table.concat(lost, ", ") .. ")") or ""))
end

function SPC.alicornSpawn(now)
    local c, t = CFG.specials.alicorn, CFG.hud.text
    if not (nativeReady() and SPC.alicornReady) then
        log("special: no Alicorn round (" .. (SPC.alicornReady and "no native spawner" or "its rows aren't in") .. ")")
        return false
    end
    if SV_UnitAlive(UNIT) > 0 then
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_AlcnRemove") or "n/a"
        log("special: the Alicorn was still up from last time; taken off (" .. tostring(r) .. "), none this round")
        return false
    end
    SPC.alcnPool = { set = {}, n = 0, at = now + 3 }
    spawningUnit = UNIT
    local r = SV_Spawn(UNIT)
    spawningUnit = nil
    log("special: the Alicorn (" .. UNIT .. "): " .. (r > 0 and "up" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
    if r <= 0 then return false end
    local s = D.special
    s.state, s.at, s.tanks, s.coreOpen, s.dived = "sail", now, 4, false, false
    s.nextDive, s.nextRail, s.nextVolley = now + c.dive_every_s, now + c.first_shot_s, now + c.first_shot_s + 5
    hudCallout(t.alicorn_go, t.alicorn_go_sub)
    log(string.format("special: round %d, the Alicorn in the west sea", D.round))
    return true
end

-- Its pooled aircraft (a run of 2026-10-24: "Alicorn's ghost aircraft ... abnormally loud sounds when flying near the
-- Alicorn"): the unit came up with EB_002's pools after all, 106 SLUAVs, 19 Rafale Ms and 6 F/A-18Fs (tools/re/
-- ALICORN.md 1.2) parked inside the hull at its spot, never launched (Survival doesn't run Online Mode's launches), up
-- all run long after it sank, their engines all playing there, and 131 more planes for every tick to look through.
-- Each one is kept out of `planes` (no kill, credit, tier or log) and put away: hidden, no collision, no target box,
-- lock or targeting, invincible, not ticking, its Wwise sounds stopped and muted (again every 10 s while it sails).
local POOLED = { "_uavm_ON_", "_rflm_ON_", "_f18f_ON_", "_uavr_" }
local function putAway(o)
    local r = {}
    for _, f in ipairs({ { "hidden", function() o:SetActorHiddenInGame(true) end },
                         { "collision", function() o:SetActorEnableCollision(false) end },
                         { "bShowHUDBox", function() o.bShowHUDBox = false end },
                         { "bIsNotLockonTarget", function() o.bIsNotLockonTarget = true end },
                         { "bIsNotFCSTargets", function() o.bIsNotFCSTargets = true end },
                         { "bIsInvincible", function() o.bIsInvincible = true end },
                         { "tick", function() o:SetActorTickEnabled(false) end } }) do
        r[#r + 1] = pcall(f[2]) and f[1] or (f[1] .. " FAILED")
    end
    return table.concat(r, ", ")
end
-- every Wwise component on a pooled plane stopped and its output at 0; the number done
local function silence(set)
    local n = 0
    for _, c in ipairs(FindAllOf("AkComponent") or {}) do
        local ok, w = pcall(function() return c:GetOwner() end)
        local a = ok and valid(w) and addrOf(w)
        if a and set[a] then
            pcall(function() c:SetOutputBusVolume(0.0) end)
            if pcall(function() c:Stop() end) then n = n + 1 end
        end
    end
    return n
end
function SPC.alicornPooled(o, short, unit)
    if unit ~= UNIT then return false end
    local pooled = false
    for _, p in ipairs(CFG.specials.alicorn.pooled or POOLED) do if short:find(p, 1, true) then pooled = true end end
    if not pooled then return false end
    SPC.alcnPool = SPC.alcnPool or { set = {}, n = 0 }
    local a = addrOf(o)
    if a then SPC.alcnPool.set[a] = true end
    SPC.alcnPool.n = SPC.alcnPool.n + 1
    local r = putAway(o)
    if not SPC.alcnPool.said then SPC.alcnPool.said = true; log("special: the Alicorn's pooled aircraft put away (" .. r .. ")") end
    return true
end
local function poolTick(now)
    local P = SPC.alcnPool
    if not P or now < (P.at or 0) then return end
    P.at = now + 10
    local n = silence(P.set)
    if not P.silencedSaid and (P.n or 0) > 0 then
        P.silencedSaid = true
        log(string.format("special: the Alicorn's pooled aircraft: %d put away, %d of their sound components stopped", P.n, n))
    end
end

local function fire(ev)
    local r = type(SV_Event) == "function" and SV_Event(ev) or -5
    if r ~= 1 then log("special: " .. ev .. " not fired: " .. (SV_ERR[r] or tostring(r))) end
end
-- a tell to every player (behaviour roadmap P3, sv_tells.lua), when tells are in
local function tell(id) if TELL then pcall(TELL.say, id, TELL.ALL) end end
-- Mission 18's RAILGUN WARNING on / off (CFG.specials.alicorn.rail_alert: RE_SV_AlcnAlertOn / Off, forwarded, so every
-- game shows its own; hard rule 45)
local function railAlert(s, on)
    if on then
        if not s.railAlertOn then fire("RE_SV_AlcnAlertOn"); s.railAlertOn = true end
    elseif s.railAlertOn then
        fire("RE_SV_AlcnAlertOff"); s.railAlertOn = nil
    end
    s.railOffAt = nil
end

-- The player's standard missile's damage (LiveWeaponBase.damage, in health points: HealthInternal is health x 10),
-- from a loaded missile or its class default; nil when none can be read
function SPC.playerMissileDamage()
    local function dmg(o)
        local ok, d = pcall(function() return o.damage end)
        return ok and type(d) == "number" and d > 0 and d or nil
    end
    for _, o in ipairs(FindAllOf("LiveMissile") or {}) do
        if valid(o) and nameOf(o):find("BP_plwp_msl_", 1, true) then
            local d = dmg(o)
            if d then return d, nameOf(o) end
        end
    end
    for _, v in ipairs({ "a0", "a1", "f0", "j0", "r0" }) do
        local o = StaticFindObject(string.format("/Game/Blueprints/Weapons/MSL/Player/Msl/BP_plwp_msl_%s.Default__BP_plwp_msl_%s_C", v, v))
        local d = valid(o) and dmg(o)
        if d then return d, "Default__BP_plwp_msl_" .. v .. "_C" end
    end
    return nil
end

-- Its parts that are up, by class: { actor, ... } (FindAllOf: every 2 s only)
local function parts(cls)
    local out = {}
    for _, o in ipairs(FindAllOf(cls) or {}) do
        if valid(o) and not nameOf(o):find("Default__", 1, true) then out[#out + 1] = o end
    end
    return out
end
local function hp(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return ok and type(h) == "number" and h or nil
end
local function partZ(o)                                 -- a part's height (cm), or nil
    if not (o and valid(o)) then return nil end
    local ok, l = pcall(function() return o:K2_GetActorLocation() end)
    return ok and l and type(l.Z) == "number" and l.Z or nil
end

function SPC.alicornTick(now, s)
    if s.state == "sail" then poolTick(now) end
    if s.state ~= "sail" or now < (s.nextAt or 0) then return end
    s.nextAt = now + 1
    local c, t = CFG.specials.alicorn, CFG.hud.text
    -- the dives, and its guns while it's up. It's "up" once a part of it (s.depthPart: the core, else a tank) is back
    -- within surfaced_m of where it sailed: a friend's 0.62.1 run (round 16, 2026-10-24) called it surfaced while no
    -- hit landed for 40 s to 2 min after. The order goes again every resurface_s while it isn't rising (at most
    -- resurface_tries times); after up_wait_s it counts as up anyway. A part that can't be read: up at once (as before).
    local z = partZ(s.depthPart)
    if not s.dived and z then s.seaZ = z end
    if not s.dived and now >= s.nextDive then
        s.dived, s.surfaceAt, s.surfaceSent = true, now + c.dive_for_s, nil
        fire("RE_SV_AlcnDive"); hudCallout(t.alicorn_dive, nil); log("special: the Alicorn dives")
        tell("alcn_dive")
        railAlert(s, false); s.railWarned = nil              -- (no railgun under water: warned again once it's up)
    elseif s.dived and now >= s.surfaceAt then
        local down = (z and s.seaZ) and (s.seaZ - z) / 100 or nil
        if not s.surfaceSent then
            s.surfaceSent, s.surfaceTry, s.lastZ, s.lastZAt = now, 1, z, now
            fire("RE_SV_AlcnSurface")
            log(string.format("special: the Alicorn surfacing (%s down)", down and string.format("%.0f m", down) or "depth unknown"))
        elseif not down or down <= (c.surfaced_m or 3) or now - s.surfaceSent >= (c.up_wait_s or 60) then
            s.dived, s.nextDive = false, now + c.dive_every_s
            s.nextRail, s.nextVolley = math.max(s.nextRail, now + 5), math.max(s.nextVolley, now + 8)
            hudCallout(t.alicorn_surface, nil)
            tell("alcn_up")
            log(string.format("special: the Alicorn surfaces, %.0f s after the order (%d sent%s)", now - s.surfaceSent, s.surfaceTry,
                (down and down > (c.surfaced_m or 3)) and string.format(", still %.0f m down: counted up after up_wait_s", down) or ""))
        elseif now - s.lastZAt >= (c.resurface_s or 8) then
            if s.lastZ and z - s.lastZ < 100 and s.surfaceTry < (c.resurface_tries or 4) then
                s.surfaceTry = s.surfaceTry + 1
                fire("RE_SV_AlcnSurface")
                log(string.format("special: the Alicorn is still %.0f m down %.0f s after the order, not rising: surface again (%d)",
                    down, now - s.surfaceSent, s.surfaceTry))
            end
            s.lastZ, s.lastZAt = z, now
        end
    end
    -- the railgun's tell (behaviour roadmap P3; it fired without a warning before): its lead_s (CFG.tells alcn_rail)
    -- before each order the radio call and WARNING: RAILGUN on every game (the first time "the railgun has been
    -- activated"), and the RAILGUN WARNING (rail_alert) from then until alert_s after the order. The order's time is
    -- as it was; the railgun then aims ~7 s and preps ~2 s (tools/re/ALICORN.md)
    local ra = c.rail_alert or {}
    if s.railOffAt and now >= s.railOffAt then railAlert(s, false) end
    local lead = TELL and TELL.leadS("alcn_rail") or 0
    if not s.dived and not s.railWarned and now >= s.nextRail - lead then
        s.railWarned = true
        if TELL then
            local okT, said = pcall(TELL.say, s.railSaid and "alcn_rail" or "alcn_rail_first", TELL.ALL)
            if okT and said then s.railSaid = true end
        end
        if ra.enabled then railAlert(s, true) end
        log(string.format("special: the Alicorn's railgun in %.0f s: warned", math.max(0, s.nextRail - now)))
    end
    if not s.dived and now >= s.nextRail then
        s.nextRail, s.railWarned = now + c.railgun_every_s, nil
        fire("RE_SV_AlcnRailgun")
        if s.railAlertOn then s.railOffAt = now + (tonumber(ra.alert_s) or 12) end
    end
    if not s.dived and now >= s.nextVolley then          -- (its VLS volley: the tell's lead_s after it, P3)
        s.nextVolley = now + c.volley_every_s
        local function volley() if s.state == "sail" and not s.dived then fire("RE_SV_AlcnVolley") end end
        if TELL then TELL.after("alcn_vls", TELL.ALL, volley) else volley() end
    end
    -- its parts, every 2 s
    if now < (s.partsAt or 0) then return end
    s.partsAt = now + 2
    local hx = math.min(c.health_max_x or 1.5, (c.health_x or 1) *
        (1 + (c.health_per_round or 0) * math.max(0, D.round - CFG.specials.first)))
    s.scaled = s.scaled or {}
    -- one look at the parts a check; a part whose health can't be read counts as up (code review of 2026-10-23:
    -- counted as down it paid every reward and sank the Alicorn 2 s after it appeared)
    local tankList, all, isTank = {}, {}, {}
    for _, cls in ipairs(c.tank_classes) do
        for _, o in ipairs(parts(cls)) do tankList[#tankList + 1] = o; all[#all + 1] = o; isTank[o] = true end
    end
    local core = parts(c.core_class)
    for _, o in ipairs(core) do all[#all + 1] = o end
    if not (s.depthPart and valid(s.depthPart)) then s.depthPart = core[1] or tankList[1] end
    -- the tanks' health: tank_missiles standard missiles each (tried for 5 checks; the tanks wait for it meanwhile)
    local tankHp, tankWait
    if (c.tank_missiles or 0) > 0 then
        if not s.mslDamage and (s.mslTries or 0) < 5 then
            s.mslTries = (s.mslTries or 0) + 1
            local d, from = SPC.playerMissileDamage()
            s.mslDamage = d
            if d then log(string.format("special: Alicorn tanks: your missile does %s damage (%s)", tostring(d), tostring(from)))
            elseif s.mslTries == 5 then log("special: Alicorn tanks: your missile's damage can't be read; tanks keep health x health_x") end
        end
        tankWait = not s.mslDamage and (s.mslTries or 0) < 5
        if s.mslDamage then tankHp = math.floor(c.tank_missiles * s.mslDamage * 10 * hx / (c.health_x or 1) + 0.5) end
    end
    for _, o in ipairs(all) do                         -- each part's health for this round, once
        local key = addrOf(o) or nameOf(o)
        local want = isTank[o] and tankHp
        if not s.scaled[key] and (hx ~= 1 or want) and not (isTank[o] and tankWait) then
            s.scaled[key] = true
            local h0 = hp(o)
            if h0 and h0 > 0 then
                pcall(function() o.HealthInternal = want or math.floor(h0 * hx + 0.5) end)
                log(string.format("special: Alicorn part %s health %s (%s -> %s)", nameOf(o):match("([%w_]+)_C_%d+") or "?",
                    want and string.format("%d missiles", math.floor(want / (s.mslDamage * 10) + 0.5)) or string.format("x%.2f", hx),
                    tostring(h0), tostring(hp(o))))
            end
        end
    end
    -- its weapons: weapon_missiles / railgun_missiles each (the first 5 checks, once the missile's damage is known)
    if (s.weaponChecks or 0) < 5 and not tankWait then
        s.weaponChecks = (s.weaponChecks or 0) + 1
        local n, growth = 0, hx / (c.health_x or 1)
        for cls, k in pairs(c.weapon_classes or {}) do
            local m = c[k] or 0
            for _, o in ipairs(m > 0 and s.mslDamage and parts(cls) or {}) do
                local key = addrOf(o) or nameOf(o)
                local h0 = not s.scaled[key] and hp(o)
                if h0 and h0 > 0 then
                    s.scaled[key] = true
                    local want = math.floor(m * s.mslDamage * 10 * growth + 0.5)
                    if want < h0 and pcall(function() o.HealthInternal = want end) then n = n + 1 end
                end
            end
        end
        if n > 0 then
            log(string.format("special: Alicorn weapons: %d parts lowered to %d missiles (railguns %d)", n,
                math.floor((c.weapon_missiles or 0) * growth + 0.5), math.floor((c.railgun_missiles or 0) * growth + 0.5)))
        end
    end
    local tanks, seen = 0, #tankList
    s.tankHp = s.tankHp or {}
    for _, o in ipairs(tankList) do
        local h = hp(o)
        if h == nil or h > 0 then tanks = tanks + 1 end
        local key = addrOf(o) or nameOf(o)                -- each hit on a tank, to check the missile count
        if h and s.tankHp[key] and h < s.tankHp[key] then
            log(string.format("special: Alicorn tank %s hit: -%.0f (%.0f left)", nameOf(o):match("btank(%a%a)") or "?", s.tankHp[key] - h, h))
        end
        if h and s.scaled[key] then s.tankHp[key] = h end
    end
    if seen > 0 then s.tanksSeen = true end
    if s.tanksSeen and tanks < (s.tanks or 4) then
        addCredits(TIER.pay(c.tank_pay * TIER.specialX(), TIER.index(D.round)) * ((s.tanks or 4) - tanks), "Alicorn ballast tank down")
        LB.stat("ground", (s.tanks or 4) - tanks)
        log(string.format("special: Alicorn ballast tanks left: %d", tanks))
        s.tanks = tanks
    end
    if s.tanksSeen and tanks == 0 and not s.coreOpen then
        s.coreOpen = true
        fire("RE_SV_AlcnAdvance"); fire("RE_SV_AlcnOpenCore")
        hudCallout(t.alicorn_core, t.alicorn_core_sub)
        log("special: the Alicorn's ballast tanks are gone: its core opens")
    end
    local coreUp = false
    for _, o in ipairs(core) do local h = hp(o); if h == nil or h > 0 then coreUp = true end end
    if #core > 0 then s.coreSeen = true end
    local hull = SV_UnitAlive(UNIT)
    if (s.coreOpen and s.coreSeen and not coreUp) or hull == 0 or hull == -7 then
        s.state = "done"
        railAlert(s, false)                              -- (its warning off with it)
        local pay = c.reward + (c.reward_per_round or 0) * D.round
        addCredits(pay, "the Alicorn sunk")
        LB.stat("ground", 1); LB.special("alicorn", true, now - s.at)
        hudCallout(t.alicorn_down, string.format(t.alicorn_down_sub, pay))
        log(string.format("special: round %d, the Alicorn sunk %.0f s after it appeared (core %s, hull %d)", D.round, now - s.at,
            coreUp and "up" or "down", hull))
        D.alicornRemoveAt = now + 20                    -- (off once it has gone down)
    elseif not s.partsSaid and now - s.at > 30 then
        s.partsSaid = true
        log(string.format("special: the Alicorn's parts found: %d ballast tanks, %d core", seen, #core))
    end
end
end
