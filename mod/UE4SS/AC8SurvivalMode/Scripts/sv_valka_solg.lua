-- VALKA's SOLG (the user, 2026-11-22): "When Valka reaches 20% health, she turns invincible in which some dialogue plays
-- out between her and Audrey ... during the gameplay without a cutscene playing, Valka Calls in the SOLG. The SOLG spawns
-- at high altitude out of another Portal, the same one Valka comes out of, big enough to match the size of the SOLG and
-- begins to travel towards the space centre. The solg will always spawn at one of the corners of the map and descend
-- towards the space center, if the space center is hit by the solg before it's destroyed the Battle Of Rocky Island Day 1
-- tonitrus spear explosion effect plays and the airfield gets locked for a round." Her answers: she leaves through a
-- portal and comes back afterwards (at 20 %, to be shot down); the target is the spaceport.
-- Here: the steps of it (VSOLG.tick from her hunt, sv_anomalies_valka.lua); the SOLG itself: sv_solg.lua;
-- its settings: CFG.specials.valka.solg; its lines: text.say.solg / solg_down / solg_hit (subtitles.ini).
VSOLG = VSOLG or {}

local function sl(s) log("special: VALKA's SOLG: " .. s) end
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end

-- her health's share (0-100), nil if unread
local function pctOf(o)
    local ok, h, mh = pcall(function() return o.HealthInternal, o.MaxHealth end)
    if not (ok and type(h) == "number" and type(mh) == "number" and mh > 0) then return nil end
    return h / (mh * 10) * 100
end

-- the SOLG's start: a map corner (pad +- corner_km), at alt_km, its nose and velocity on the pad
function VSOLG.course(g, corner)
    local pad = { X = n(g.pad_cm[1], 0), Y = n(g.pad_cm[2], 0), Z = n(g.pad_cm[3], 0) }
    local ck = n(g.corner_km, 30) * 100000
    local corners = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
    local k = corner or math.random(#corners)
    local cx, cy = corners[k][1], corners[k][2]
    local at = { X = pad.X + cx * ck, Y = pad.Y + cy * ck, Z = n(g.alt_km, 12) * 100000 }
    local T = math.max(30, n(g.travel_s, 300))
    local vel = { X = (pad.X - at.X) / T, Y = (pad.Y - at.Y) / T, Z = (pad.Z - at.Z) / T }
    local yaw = math.deg(math.atan(pad.Y - at.Y, pad.X - at.X))
    return at, yaw, vel, pad, k, T
end

-- its pay and the game's hooks, set each time it's called in
local function hooks(c, s, G)
    SOLG.onBreak = function(key, bone, pay)
        G.broken = (G.broken or 0) + 1
        if pay and pay > 0 and addCredits then addCredits(pay, "the SOLG's " .. key) end
        if SCOOP then pcall(SCOOP.broke, bone) end
    end
    SOLG.onPhase = function(ph, nOn)
        G.phase = ph
        local t = CFG.hud.text
        if t and t.solg_phase and t.solg_phase[ph] then hudCallout(t.solg_phase[ph], nil) end
        if SCOOP then pcall(SCOOP.phase, ph) end
    end
end

-- she calls it in: invincible, her lines, out through a portal, the SOLG out of its own at a corner
function VSOLG.start(c, s, o, now)
    local g = c.solg
    local V = SPC.V
    s.solgDone = true
    local G = { at = now, state = "call" }
    s.solg = G
    -- she's out of it: gone (hidden, untouchable) through a portal of hers
    local here = where and where(o)
    local you = playerLocation and playerLocation()
    if here then
        fxAt({ c.smoke }, here, c.smoke_scale, c.smoke_s)
        pcall(V.blinkPortal, c, s, here, you and math.deg(math.atan(you.Y - here.Y, you.X - here.X)) or 0, now)
    end
    setGone(o, true); pcall(V.partsGone, c, s, o, true, true)
    if SCOOP then pcall(SCOOP.gone, true) end             -- (her copies hidden on every joiner's game too)
    s.vanished, s.blinkUntil, s.blinkLeft = false, nil, nil
    if s.chargeAt then s.chargeAt = nil; V.event("RE_SV_ValkaChargeOff") end
    if s.invertUntil then pcall(V.invert, c, s, false, now) end
    pcall(function() o.MinHealth = math.max(1, (n(o.MaxHealth, 0)) * n(g.at_pct, 20) / 100) end)
    V.subs(c, "solg")
    G.callAt = now + n(g.call_s, 18)                     -- (the SOLG after her lines' first half)
    -- ((2026-11-22) the user: "shes still attacking the players while invisible": her AI flew and fired on) parked far out
    -- of the fight (park_km from the spaceport's pad: along x, along y, up) and held there every tick till she's back
    local pk = type(g.park_km) == "table" and g.park_km or { -40, 0, 15 }
    G.park = { X = n(g.pad_cm[1], 0) + n(pk[1], -40) * 100000, Y = n(g.pad_cm[2], 0) + n(pk[2], 0) * 100000, Z = n(pk[3], 15) * 100000 }
    hooks(c, s, G)
    sl(string.format("her health at %.0f %%: invincible, gone through a portal; the SOLG in %.0f s", pctOf(o) or -1, n(g.call_s, 18)))
end

-- its portal opens at a corner (the user: "The portal has to spawn at full size before letting the SOLG spawn in")
local function portalUp(c, s, G, now)
    local g = c.solg
    local at, yaw, vel, pad, corner, T = VSOLG.course(g)
    G.pad, G.T, G.course = pad, T, { at = at, yaw = yaw, vel = vel, corner = corner }
    local wait = 0
    if type(c.portal) == "table" and c.portal.enabled then
        local pc = {}
        for k, v in pairs(c.portal) do pc[k] = v end
        pc.size_m, pc.max_s = n(g.portal_size_m, 2600), n(g.portal_max_s, 40)
        pc.face_you = false
        G.ph = {}
        local okP, up = pcall(SPC.V.portalOpen, c, G.ph, at, yaw, now, pc, true)
        if okP and up then wait = n(pc.open_s, 4.5) + n(g.portal_full_s, 0.5) end
        if okP and up and SCOOP then pcall(SCOOP.portal, at, yaw, pc.size_m) end   -- (every joiner's too: sv_solg_coop.lua)
        sl(string.format("its portal %s, %.0f m across%s", okP and up and "opens" or ("NOT up (" .. tostring(up) .. ")"), pc.size_m,
            wait > 0 and string.format(": the SOLG through it once it's full size, in %.1f s", wait) or ""))
    end
    G.state, G.spawnAt, G.portalAt = "portal", now + wait, now
end

-- the SOLG out of its (full-size) portal, on its way down
local function arrive(c, s, G, now)
    local g = c.solg
    local at, yaw, vel, corner = G.course.at, G.course.yaw, G.course.vel, G.course.corner
    local pad, T = G.pad, G.T
    if G.ph and G.ph.portal then G.ph.out = now + n(g.through_s, 6) end   -- (it closes once the SOLG's through)
    -- the SOLG behind its face, coming through as it opens
    local back = n(g.portal_back_m, 1500) * 100
    local r = math.rad(yaw)
    local from = { X = at.X - math.cos(r) * back, Y = at.Y - math.sin(r) * back, Z = at.Z }
    vel = { X = (pad.X - from.X) / T, Y = (pad.Y - from.Y) / T, Z = (pad.Z - from.Z) / T }   -- (from its start: on the pad at T)
    local okS, up = pcall(SOLG.spawn, from, yaw, vel)
    if not (okS and up) then
        sl("the SOLG didn't come up (" .. tostring(up) .. "): she comes back now")
        G.state = "back"; G.backAt = now
        return
    end
    local okT, nT = pcall(SOLG.targetsUp)
    G.targets = okT and nT or 0
    G.state, G.from, G.hitAt = "falling", now, now + T
    if c.solg.marker and hudCallout then hudCallout(CFG.hud.text.solg_inbound, CFG.hud.text.solg_inbound_sub) end
    if SCOOP then pcall(SCOOP.up, from, yaw, vel, T) end   -- (every joiner's too: sv_solg_coop.lua)
    sl(string.format("out of the corner %d at (%.1f, %.1f) km, %.1f km up, %.0f km from the spaceport, there in %.0f s: %d targets",
        corner, at.X / 100000, at.Y / 100000, at.Z / 100000,
        math.sqrt((pad.X - at.X) ^ 2 + (pad.Y - at.Y) ^ 2 + (pad.Z - at.Z) ^ 2) / 100000, T, G.targets))
end

-- it hit the spaceport: the Rocky Island blast, the airfield down for a round
local function impact(c, s, G, now)
    local g, t = c.solg, CFG.hud.text
    local P = { X = G.pad.X, Y = G.pad.Y, Z = G.pad.Z + n(g.hit_fx_up_m, 0) * 100 }
    local okQ, what = VSOLG.strike(g.hit_seq, P, n(g.hit_fx_s, 20))
    local n0 = okQ and 1 or fxAt(g.hit_fx or {}, P, n(g.hit_fx_scale, 12), n(g.hit_fx_s, 20))
    if not okQ then what = "its cutscene layer NOT played (" .. tostring(what) .. "): " .. n0 .. " systems instead" end
    pcall(SOLG.stop, "it hit the spaceport")
    if SCOOP then pcall(SCOOP.hit, G.pad) end
    if SND and SND.event and CFG.sound and CFG.sound.valka and CFG.sound.valka.solg_hit then pcall(SND.event, CFG.sound.valka.solg_hit, nil) end
    local closed = false
    if CFG.airfield and CFG.airfield.enabled and AF and not AF.down and not (COOP and type(COOP.client) == "function" and COOP.client() == true) then
        AF.down, AF.downRound, AF.closePending, AF.hp, RUN.dirty = true, D.round, true, 0, true
        hudCallout(t.airfield_down, string.format(t.airfield_down_sub, D.round + 1))
        LB.stat("af_down", 1)
        closed = true
    end
    SPC.V.subs(c, "solg_hit")
    LB.stat("solg_hit", 1)
    sl(string.format("it hit the spaceport %.0f s after it came: %s, the airfield %s", now - G.from, tostring(what),
        closed and ("down until after round " .. D.round + 1) or "already down / off"))
    G.state, G.backAt = "back", now + n(g.back_s, 12)
end

-- it's destroyed: falling apart, pay, her lines
local function destroyed(c, s, G, now)
    local g = c.solg
    local L = SOLG.where and SOLG.where()
    if L then fxAt(SOLG.C.fx, L, n(SOLG.C.fx_scale.SOLG, 12), 10) end
    pcall(SOLG.fall)
    if SCOOP then pcall(SCOOP.destroyed) end
    local pay = n(g.reward, 0)
    if pay > 0 then addCredits(pay, "the SOLG destroyed") end
    if hudCallout then hudCallout(CFG.hud.text.solg_down, CFG.hud.text.solg_down_sub and string.format(CFG.hud.text.solg_down_sub, specialPay and specialPay(pay) or pay)) end
    SPC.V.subs(c, "solg_down")
    LB.stat("solg_down", 1)
    sl(string.format("destroyed %.0f s after it came, %.0f s before it would have hit; %d pieces shot off, %d paid", now - G.from,
        G.hitAt - now, G.broken or 0, pay))
    G.state, G.backAt, G.wreckUntil = "back", now + n(g.back_s, 12), now + n(g.wreck_s, 25)
end

-- the Rocky Island Day 1 strike as Mission 25's cutscene plays it (the method of 0.74.82's railcannon impact, HISTORY.md:
-- a LevelSequencePlayer of ours on the cutscene's VFX layer, its transform origin moved so its ground explosion (anchor,
-- in the sequence's space) stands at P, held at its last frame, its camera rains and the rod's trail hidden, stopped
-- life s on): true, what or false, why
local STRIKES = {}
function VSOLG.strike(q, P, life)
    if not (type(q) == "table" and q.enabled ~= false and type(q.path) == "string") then return false, "off" end
    local seq = SPC.V.asset(q.path)
    if not seq then return false, "its sequence didn't load" end
    local lsp = StaticFindObject("/Script/LevelSequence.Default__LevelSequencePlayer")
    if not (valid(lsp) and liveObj(survivalPC)) then return false, "no LevelSequencePlayer / player controller" end
    local an = type(q.anchor) == "table" and q.anchor or {}
    local o = { X = P.X - n(an[1], 0), Y = P.Y - n(an[2], 0), Z = P.Z - n(an[3], 0) }
    local settings = { bAutoPlay = false, LoopCount = { Value = 0 }, PlayRate = 1.0, StartTime = 0.0, bRandomStartTime = false,
        bRestoreState = false, bDisableMovementInput = false, bDisableLookAtInput = false, bHidePlayer = false, bHideHud = false,
        bDisableCameraCuts = true, bPauseAtEnd = true }
    local okC, pl = pcall(function() return lsp:CreateLevelSequencePlayer(survivalPC, seq, settings, {}) end)
    if not (okC and pl and valid(pl)) then return false, "CreateLevelSequencePlayer: " .. tostring(pl) end
    local act
    pcall(function() act = pl:GetOuter() end)
    local okO = act ~= nil and valid(act) and pcall(function()
        act.bOverrideInstanceData = true
        act.DefaultInstanceData.TransformOrigin = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = o, Scale3D = { X = 1, Y = 1, Z = 1 } }
    end)
    if not okO then                                       -- (never played at the cutscene's own spot)
        if act ~= nil then pcall(function() act:K2_DestroyActor() end) end
        return false, "its origin not set"
    end
    if not pcall(function() pl:Play() end) then pcall(function() act:K2_DestroyActor() end); return false, "Play refused" end
    local t0 = os.clock()
    STRIKES[#STRIKES + 1] = { pl = pl, a = addrOf(pl), act = act, aa = addrOf(act), key = q.key or "Ms250010",
        hide = type(q.hide) == "table" and q.hide or {}, hides = { t0 + 0.2, t0 + 1.0 }, stopAt = t0 + life }
    return true, string.format("Mission 25's strike played (its cutscene layer), held %.0f s", life)
end
local function strikeHide(e)                              -- its camera rains and the rod's trail hidden and off
    local okF, list = pcall(FindAllOf, "NiagaraActor")
    for _, a in ipairs(okF and list or {}) do
        local path = ""
        pcall(function() path = a.NiagaraComponent.Asset:GetFullName() end)
        if path:find(e.key, 1, true) then
            for _, h in ipairs(e.hide) do
                if path:find(h, 1, true) then
                    pcall(function() a:SetActorHiddenInGame(true) end)
                    pcall(function() a.NiagaraComponent:Deactivate() end)
                    break
                end
            end
        end
    end
end
function VSOLG.strikesTick(now)
    if #STRIKES == 0 then return end
    local left = {}
    for _, e in ipairs(STRIKES) do
        while e.hides[1] and now >= e.hides[1] do table.remove(e.hides, 1); pcall(strikeHide, e) end
        if now >= e.stopAt or (levelTorn and levelTorn()) then
            if liveObj(e.pl) and addrOf(e.pl) == e.a then pcall(function() e.pl:Stop() end) end
            if liveObj(e.act) and addrOf(e.act) == e.aa then pcall(function() e.act:K2_DestroyActor() end) end
        else left[#left + 1] = e end
    end
    STRIKES = left
end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["VALKA's SOLG strikes"] = function() STRIKES = {} end end

-- every tick of her hunt: true while the SOLG's part of her round runs (the rest of her tick waits)
function VSOLG.tick(c, s, o, now)
    local g = c.solg
    if not (type(g) == "table" and g.enabled) then return false end
    pcall(VSOLG.strikesTick, now)
    local G = s.solg
    if G and G.ph and G.ph.portal then
        pcall(SPC.V.portalTick, c, G.ph, now)
        if G.ph.out and now >= G.ph.out then G.ph.out = nil; pcall(SPC.V.portalThrough, c, G.ph, now) end
    end
    if G and G.wreckUntil and now >= G.wreckUntil then
        G.wreckUntil = nil
        pcall(SOLG.stop, "its wreck's gone")
        if SCOOP then pcall(SCOOP.stop) end
    end
    if not G then
        if s.solgDone or not o then return false end
        if not s.solgFloor then                           -- (her floor at at_pct till then: no big hit kills her past it)
            local okF = pcall(function() o.MinHealth = math.max(1, n(o.MaxHealth, 0) * n(g.at_pct, 20) / 100) end)
            s.solgFloor = okF
        end
        local p = pctOf(o)
        if p and p <= n(g.at_pct, 20) then VSOLG.start(c, s, o, now); return true end
        return false
    end
    if G.state == "done" then return false end
    if valid(o) then pcall(function() o.bIsInvincible = true end) end   -- (gone: setGone's, kept on)
    if valid(o) and G.park and G.state ~= "done" then     -- (parked: nobody in her reach)
        local okP = pcall(function() o:K2_SetActorLocation(G.park, false, {}, true) end)
        -- ((2026-11-22, the user's co-op run: parked 50 km out she still fired 86 missiles, "she still comes back into
        -- the map") off the radar and out of the fight: deactivated (as a downed co-op player's plane), every tick in case
        -- the game puts her back on; on again when she's back
        local okD, act = pcall(function() if o.bIsActivated ~= false then o.bIsActivated = false end; return o.bIsActivated end)
        if not G.offSaid then G.offSaid = true; sl("she's off the radar: " .. (okD and act == false and "deactivated" or "NOT deactivated (" .. tostring(act) .. ")")) end
        if not G.parkSaid then
            G.parkSaid = true
            sl(string.format("she's parked out of the fight%s: (%.0f, %.0f) km, %.0f km up", okP and "" or " (NOT moved)",
                G.park.X / 100000, G.park.Y / 100000, G.park.Z / 100000))
        end
    end
    if G.state == "call" then
        if now >= G.callAt then portalUp(c, s, G, now) end
        return true
    end
    if G.state == "portal" then
        if now >= G.spawnAt then arrive(c, s, G, now) end
        return true
    end
    if G.state == "falling" then
        local st = SOLG.state and SOLG.state()
        if not (SOLG.up and SOLG.up()) then sl("the SOLG's gone (its level?): she comes back"); G.state, G.backAt = "back", now
        elseif st and st.destroyed then destroyed(c, s, G, now)
        elseif now >= G.hitAt then impact(c, s, G, now)
        elseif G.T and now >= (G.warnAt or G.from + G.T * 0.5) and not G.warned2 then
            G.warnAt = G.from + G.T * 0.8
            if G.warned1 then G.warned2 = true else G.warned1 = true end
            if hudCallout then hudCallout(CFG.hud.text.solg_inbound, string.format(CFG.hud.text.solg_eta or "%d S TO IMPACT", math.floor(G.hitAt - now))) end
        end
        return true
    end
    if G.state == "back" then
        if now < G.backAt then return true end
        -- back on your six through a portal (her hunt's own way back: a chase blink), damageable again at 20 %
        G.state = "done"
        pcall(function() o.MinHealth = 0 end)
        pcall(function() o.bIsActivated = true end)          -- (back on the radar, in the fight)
        if SCOOP then pcall(SCOOP.gone, false) end
        s.vanished, s.blinkWhy, s.blinkUntil = true, "chase", now + 5
        s.railAt = now + n(c.railgun_every_s, 20)
        sl("she's back")
        return false
    end
    return false
end

-- her round over (shot down, the level gone): the SOLG with it
function VSOLG.stop(s, why)
    if SCOOP then pcall(SCOOP.stop) end
    SOLG.onBreak, SOLG.onPhase = nil, nil                 -- (a later run's, or this game as a joiner, never calls them)
    if s and s.solg and s.solg.ph then pcall(SPC.V.portalStop, s.solg.ph) end
    if SOLG and SOLG.up and SOLG.up() then pcall(SOLG.stop, why) end
    if s then s.solg = nil end
end

-- a status for the HUD row / the tests
function VSOLG.state(s)
    local G = s and s.solg
    if not G then return nil end
    return { state = G.state, eta = G.hitAt and math.max(0, G.hitAt - os.clock()) or nil, phase = G.phase, broken = G.broken or 0,
             portal_to_solg_s = G.from and G.portalAt and (G.from - G.portalAt) or nil }
end
