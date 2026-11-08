-- sv_anomalies_dev.lua: the specials' code for test builds only: the whole piece is one test-only block, which
-- tools/strip_test_only.py takes out of a release (only this header is left there). Piece 3 of 3 of sv_anomalies.lua
-- (sv_anomalies.lua, sv_anomalies_valka.lua, sv_anomalies_dev.lua), split by tools/lua_split_part.py and run by
-- main.lua right after the piece before it: a name another part uses is a global of this mod's Lua state, its own
-- helpers stay local.

-- TEST ONLY BEGIN (the lightning Anomaly and the storm test: test builds only; tools/strip_test_only.py takes all of it
-- out of a release with CFG.specials.thunder; docs/re/THUNDER.md)
-- IFF FATAL ERROR / DI..ANT TH..D..R (user, 2026-11-06: "another Anomaly, one that uses Lightning Against you", "The
-- Aircraft is an A-10", "Strikes should only black out and disorient you", "it can only be spawned with the test key"):
-- the special kind "thunder", never in CFG.specials.rotation, brought only by Ctrl+. (the next round, as Ctrl+1-8 do).
-- Its A-10 is the plain campaign row (CFG.specials.thunder.row, a10c_common = OP1001_a10c_01: never the named A-10's
-- NLID_0400_CP set, hard rule 22) set on MINDRIPPER's own unit SV_Unit_Anomaly (SV_SetAircraft, as MINDRIPPER's F-4E is:
-- the unit is one aircraft built for a boss, its behaviour Survival's fighters' set (hard rule 20), and its stock records
-- give it the pool's orders, the MISSION UPDATE beep, the forced WARNING, the attack throttle and the Celaeno crackle at
-- its appearance, and its death sounds; so no build data). Its storm is the game's own lightning volume
-- (BP_LightninigVolume_MS12, Missions 12 and 16's: build/research/lightning/LIGHTNING.md), spawned at run time and kept
-- on it every tick: the stock observer rolls strikes on the player planes inside it (the HUD hidden 2 s, electronic noise
-- 6-10 s, a camera shake, the engine's stall flag; never damage, never an AI plane). Co-op: the host spawns it (its spawn
-- mirrored as every flight's); each game keeps a storm on its own copy of it and rolls its own strikes, nothing synced.
-- Ctrl+,: the storm test (LIGHTNING.md 7): the storm on you for test.seconds, its strikes and your health in the log;
-- pressed again, your plane's LS_StallTime to test.stall_s; a third time, off.
-- A storm is never destroyed with anything inside it: the observer reads the first storm a plane entered through a weak
-- pointer and doesn't check it (0x147ed60c0: a destroyed one would be read at NULL + 0x340), so a storm being taken off
-- shrinks to 1 cm, and is destroyed once its InsideGameObjects has been empty twice (else it stays, parked).
THUNDER = { storm = nil, parked = {}, fx = {}, test = nil, named = {}, hook = { n = 0, ends = 0 }, said = {} }
do
local function cfg() return CFG.specials.thunder end
local STRIKE_GAP_S, FOLLOW_S, PARK_RADIUS, PARK_SAY_S = 1.5, 3.5, 1.0, 30
local function say(key, s) if not THUNDER.said[key] then THUNDER.said[key] = true; log(s) end end
local function torn() return (levelTorn and levelTorn()) or (levelGoing and levelGoing()) or false end
local function joiner() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function num(o, f)
    local ok, v = pcall(function() return o[f] end)
    return (ok and type(v) == "number") and v or nil
end
local function str(v)                                   -- (an FString / FName read: a Lua string)
    if type(v) == "string" then return v end
    if v == nil then return "nil" end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" then return s end
    return tostring(v)
end
local function field(o, f)
    local ok, v = pcall(function() return o[f] end)
    return ok and str(v) or "?"
end
local function fmt(v, f) return type(v) == "number" and string.format(f or "%.2f", v) or "?" end
local function where(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function myPlane()
    if not liveObj(survivalPC) then return nil end
    local ok, p = pcall(function() return survivalPC.Pawn end)
    if ok and p ~= nil and liveObj(p) then return p end
    return nil
end
local function motion(p)                                 -- km/h and pitch (degrees), or nil
    if not p then return nil, nil end
    local okV, v = pcall(function() local x = p:GetVelocity(); return { X = x.X, Y = x.Y, Z = x.Z } end)
    local okR, r = pcall(function() return p:K2_GetActorRotation().Pitch end)
    local kmh = okV and v and math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) * 0.036 or nil
    return kmh, okR and type(r) == "number" and r or nil
end

-- (the specials' clean-up, sv_rounds.lua, a part after this one: its units and log label for "thunder", installed at the
-- first tick of a run, its key or its spawn)
local function install()
    if THUNDER.installed or type(SPC.cleanUnitsOf) ~= "function" or type(SPC.cleanLabel) ~= "function" then return end
    THUNDER.installed = true
    local units, label = SPC.cleanUnitsOf, SPC.cleanLabel
    function SPC.cleanUnitsOf(kind)
        if kind == "thunder" then
            local u = cfg().unit
            return (type(u) == "string" and u ~= "") and { u } or {}
        end
        return units(kind)
    end
    function SPC.cleanLabel(unit)
        local c = cfg()
        if unit == c.unit and THUNDER.lastSeen and os.clock() - THUNDER.lastSeen < 120 then return c.name .. "'s unit (" .. unit .. ")" end
        return label(unit)
    end
end
THUNDER.install = install
-- its strikes in the log: the HUD's own lightning calls (UFUNCTIONs; the strike calls them from C++, so a hook may never
-- see one: the log says), hooked once
local function hookHud()
    if THUNDER.hooked ~= nil then return THUNDER.hooked end
    THUNDER.hooked = false
    if type(RegisterHook) ~= "function" then log("thunder: no RegisterHook: the HUD's lightning calls aren't watched"); return false end
    local h = THUNDER.hook
    local okB, errB = pcall(RegisterHook, "/Script/Live.LiveHUD:BeginHUDDistortionLightning", function(_, t)
        h.n, h.at = h.n + 1, os.clock()
        local okT, v = pcall(function() return t:get() end)
        h.recover = okT and v or nil
    end)
    local okE, errE = pcall(RegisterHook, "/Script/Live.LiveHUD:EndHUDDistortionLightning", function()
        h.ends, h.endAt = h.ends + 1, os.clock()
    end)
    THUNDER.hooked = okB or okE
    log(string.format("thunder: the HUD's BeginHUDDistortionLightning %s, EndHUDDistortionLightning %s (a strike calls them from "
        .. "C++: a hook sees only calls through ProcessEvent)", okB and "hooked" or ("NOT hooked: " .. tostring(errB)),
        okE and "hooked" or ("NOT hooked: " .. tostring(errE))))
    return THUNDER.hooked
end

---------------------------------------------------------------------------------------------------- the storm
local function stormClass()
    local c = cfg().storm
    if THUNDER.cls ~= nil and liveObj(THUNDER.cls) then return THUNDER.cls end
    local o, why = loadObject(c.class)
    THUNDER.cls = o
    return o, why
end
-- (the volume's strike chance curves, CUR_LightningWeight: the game instance's soft reference; loaded and kept, so the
-- observer finds MS_12, else it falls back on count % a roll)
local function curveTable()
    if THUNDER.curves ~= nil then return THUNDER.curves end
    local o, why = loadObject(cfg().storm.curve_table)
    THUNDER.curves = o ~= nil and valid(o) or false
    if o ~= nil and valid(o) then pcall(pin, o, "CUR_LightningWeight") end
    log("thunder: the strike chance curves (CUR_LightningWeight) " .. (THUNDER.curves and "loaded" or ("NOT loaded: " .. tostring(why))))
    return THUNDER.curves
end
local function shakeMgr(st)
    if THUNDER.mgr ~= nil and liveObj(THUNDER.mgr) then return THUNDER.mgr end    -- (kept between storms while it's live)
    THUNDER.mgr = nil
    if os.clock() < (st.mgrAt or 0) or (st.mgrTries or 0) >= 3 then return nil end      -- (a walk: 3 at most a storm)
    if walkHold and walkHold() then return nil end
    st.mgrAt, st.mgrTries = os.clock() + 10, (st.mgrTries or 0) + 1
    for _, cn in ipairs({ "LiveCameraShakeManager", "BP_CameraShakeManager_C" }) do   -- (the class, else its blueprint's)
        for _, o in ipairs(THUNDER.mgr == nil and FindAllOf(cn) or {}) do
            if THUNDER.mgr == nil and liveObj(o) and not nameOf(o):find("Default__", 1, true) then THUNDER.mgr = o end
        end
    end
    local m = THUNDER.mgr
    say("mgr" .. (m and "1" or "0"), "thunder: the camera shake manager " .. (m and ("found (" .. nameOf(m) .. "): a "
        .. "lightning shake in its ActiveShakeList counts as a strike") or "NOT found (looked for 3 times a storm, 10 s apart)"))
    return m
end
-- the lightning shakes playing (how many, the first one's name), nil when the list can't be read
local function shakes(mgr)
    local n, name = 0, nil
    local ok = pcall(function()
        mgr.ActiveShakeList:ForEach(function(_, e)
            local okS, cs = pcall(function() return e:get().CameraShake end)
            if okS and cs ~= nil and liveObj(cs) then
                local nm = nameOf(cs)
                if nm:find("Lightning", 1, true) then n, name = n + 1, name or (nm:match("([^%.:/ ]+)$") or nm) end
            end
        end)
    end)
    if ok then return n, name end
    return nil, nil
end
local function hudOf()
    if not liveObj(survivalPC) then return nil end
    local ok, h = pcall(function() return survivalPC.MyHUD end)
    if ok and h ~= nil and liveObj(h) then return h end
    return nil
end
-- what Lua can see of a strike now: the volume's flash (its point light), a lightning camera shake, the HUD widget
local function sense(st)
    local s = {}
    local okL, pl = pcall(function() return st.vol.LightningPointLight end)
    if okL and pl ~= nil and liveObj(pl) then s.flash = num(pl, "Intensity") end
    local mgr = shakeMgr(st)
    if mgr then s.shake, s.shakeName = shakes(mgr) end
    local hud = hudOf()
    if hud then
        local okW, w = pcall(function() return hud.HudWidget end)
        if okW and w ~= nil and liveObj(w) then
            local okV, v = pcall(function() return w:GetVisibility() end)
            local okO, op = pcall(function() return w:GetRenderOpacity() end)
            s.vis = okV and v or nil
            s.op = (okO and type(op) == "number") and op or nil
        end
        local okS, sh = pcall(function() return hud.bShowHUD end)
        if okS and type(sh) == "boolean" then s.show = sh end
    end
    return s
end
-- the AI planes inside storm st: { addr = health } and how many
local function aiInside(st)
    local out, n = {}, 0
    local at = st.center
    if not at then return out, 0 end
    for _, q in ipairs(planes) do
        if not q.down and liveObj(q.obj) then
            local l = where(q.obj)
            if l and km(l, at) * 100000 <= st.radius then
                local a = addrOf(q.obj)
                if a then out[a], n = { h = num(q.obj, "HealthInternal"), name = q.name or nameOf(q.obj) }, n + 1 end
            end
        end
    end
    return out, n
end
-- A strike seen (any of the signals coming on), logged with your health, speed and pitch and the AI planes inside, and
-- FOLLOW_S later what changed (the stall flag's upset: your speed and pitch; your health must not move; an AI plane's
-- health that moved). label: the log's ("storm test", "thunder")
local function watch(st, now, label, pawn)
    if gamePaused and gamePaused(survivalPC) then return {} end   -- ((2026-11-08) the pause menu hid the HUD: not a strike)
    local s = sense(st)
    if not st.base then
        st.base = { vis = s.vis, op = s.op, show = s.show }
        log(string.format("%s: what a strike may show, at the start: flash %s, lightning shakes %s, HUD widget visibility %s, "
            .. "opacity %s, bShowHUD %s", label, fmt(s.flash), tostring(s.shake), tostring(s.vis), fmt(s.op), tostring(s.show)))
    end
    local b, h, by = st.base, THUNDER.hook, {}
    if h.n > (st.hookN or h.n) then by[#by + 1] = string.format("the HUD's BeginHUDDistortionLightning (noise %s s)", fmt(h.recover, "%.1f")) end
    if h.ends > (st.hookE or h.ends) then
        log(string.format("%s: the HUD's EndHUDDistortionLightning: the noise over%s", label,
            h.at and string.format(" after %.1f s", os.clock() - h.at) or ""))
    end
    st.hookN, st.hookE = h.n, h.ends
    local shake = (s.shake or 0) > 0
    if shake and not st.shake then by[#by + 1] = "a lightning camera shake (" .. tostring(s.shakeName) .. ")" end
    st.shake = shake
    local hidden = (s.vis ~= nil and b.vis ~= nil and s.vis ~= b.vis) or (s.show ~= nil and b.show ~= nil and s.show ~= b.show)
        or (s.op ~= nil and b.op ~= nil and s.op < b.op - 0.25)
    if hidden and not st.hidden then
        st.hiddenAt = now
        by[#by + 1] = string.format("the HUD hidden (visibility %s, opacity %s, bShowHUD %s)", tostring(s.vis), fmt(s.op), tostring(s.show))
    elseif st.hidden and not hidden and st.hiddenAt then
        local k = st.strikes[#st.strikes]
        if k and not k.blackout then k.blackout = now - st.hiddenAt end
        log(string.format("%s: the HUD back after %.2f s", label, now - st.hiddenAt))
    end
    st.hidden = hidden
    local flash = (s.flash or 0) > 0
    if flash and not st.flash then
        st.flashes = st.flashes + 1
        if label ~= "thunder" or logVerbose() then log(string.format("%s: a flash (its point light %s) at +%.1f s", label, fmt(s.flash, "%.0f"), now - st.at)) end
    end
    st.flash = flash
    if #by > 0 then
        local last = st.strikes[#st.strikes]
        if last and now - last.at < STRIKE_GAP_S then
            for _, x in ipairs(by) do last.by[#last.by + 1] = x end
        else
            st.n = st.n + 1
            local kmh, pitch = motion(pawn)
            local ai, nAi = aiInside(st)
            local k = { n = st.n, at = now, by = by, hp = pawn and num(pawn, "HealthInternal"), kmh = kmh, pitch = pitch, ai = ai }
            if #st.strikes >= 200 then table.remove(st.strikes, 1) end
            st.strikes[#st.strikes + 1] = k
            log(string.format("%s: strike %d at +%.1f s (seen by %s); your health %s, %s km/h, pitch %s deg; %d AI planes inside "
                .. "the storm", label, k.n, now - st.at, table.concat(by, ", "), tostring(k.hp), fmt(kmh, "%.0f"), fmt(pitch, "%.1f"), nAi))
        end
    end
    for _, k in ipairs(st.strikes) do
        if not k.done and now - k.at >= FOLLOW_S then
            k.done = true
            local kmh, pitch = motion(pawn)
            local hp = pawn and num(pawn, "HealthInternal")
            local moved = {}
            for a, e in pairs(k.ai) do
                for _, q in ipairs(planes) do
                    if q.addr == a or addrOf(q.obj) == a then
                        local h1 = liveObj(q.obj) and num(q.obj, "HealthInternal") or 0
                        if h1 ~= e.h then moved[#moved + 1] = string.format("%s %s -> %s", tostring(e.name), tostring(e.h), tostring(h1)) end
                    end
                end
            end
            local nAi = 0
            for _ in pairs(k.ai) do nAi = nAi + 1 end
            log(string.format("%s: strike %d, %.1f s on: seen by %s; your health %s -> %s (%s); %s -> %s km/h, pitch %s -> %s deg; "
                .. "the HUD %s; %d AI planes were inside: %s", label, k.n, FOLLOW_S, table.concat(k.by, ", "), tostring(k.hp), tostring(hp),
                (k.hp ~= nil and hp == k.hp) and "unchanged" or "MOVED", fmt(k.kmh, "%.0f"), fmt(kmh, "%.0f"), fmt(k.pitch, "%.1f"),
                fmt(pitch, "%.1f"), k.blackout and string.format("hidden %.2f s", k.blackout) or "not seen hidden from Lua", nAi,
                #moved > 0 and ("health moved on " .. table.concat(moved, "; ") .. " (a hit? the stock storm strikes player planes only)")
                    or "no health moved (the stock storm strikes player planes only)"))
        end
    end
    return s
end

-- A storm of `owner` ("test", "boss": the host's Anomaly, "copy": a joiner's copy of it) at `at`, radiusM round it: the
-- stock volume spawned deferred, its radius (cm), intervals and curve set before it begins play. The storm, or nil and why.
function THUNDER.stormUp(owner, at, radiusM)
    local c = cfg().storm
    if THUNDER.storm then return nil, "a storm is up already (" .. tostring(THUNDER.storm.owner) .. "'s)" end
    if torn() then return nil, "the level is going" end
    if (cfg().strike or {}).stock ~= true then           -- ((2026-11-08) the stock volume never struck: Survival's own strikes)
        local st = { owner = owner, at = os.clock(), radius = radiusM * 100, center = at, n = 0, flashes = 0, strikes = {}, moves = 0,
                     own = true }
        THUNDER.storm = st
        log(string.format("thunder: storm up for the %s at (%.0f, %.0f, %.0f), %.1f km round it: Survival's own strikes (no stock volume)",
            owner, at.X, at.Y, at.Z, radiusM / 1000))
        crumb("thunder: storm up for the " .. owner)
        return st
    end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (gs and valid(gs)) then return nil, "GameplayStatics not found" end
    if not liveObj(survivalPC) then return nil, "no player controller" end
    local cls, why = stormClass()
    if not cls then return nil, "its class didn't load (" .. tostring(why) .. ")" end
    curveTable()
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)  -- (AlwaysSpawn)
    if not okB or x == nil or not valid(x) then return nil, "no actor (" .. tostring(x) .. ")" end
    local set = {}
    set[#set + 1] = pcall(function() x.Radius = radiusM * 100 end) and "radius" or "radius NOT set"
    if (tonumber(c.min_interval_s) or 0) > 0 then set[#set + 1] = pcall(function() x.MinStrikeInterval = c.min_interval_s end) and "min interval" or "min interval NOT set" end
    if (tonumber(c.max_interval_s) or 0) > 0 then set[#set + 1] = pcall(function() x.MaxStrikeInterval = c.max_interval_s end) and "max interval" or "max interval NOT set" end
    if type(c.curve) == "string" and c.curve ~= "" then set[#set + 1] = pcall(function() x.WeightCurveName = FName(c.curve) end) and "curve" or "curve NOT set" end
    local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
    if not okF or a == nil or not valid(a) then
        pcall(function() x:K2_DestroyActor() end)        -- (never began play: nothing can be inside it)
        return nil, "its spawn didn't finish (" .. tostring(a) .. ")"
    end
    local st = { vol = a, addr = addrOf(a), owner = owner, at = os.clock(), radius = radiusM * 100, center = at, n = 0,
                 flashes = 0, strikes = {}, moves = 0 }
    THUNDER.storm = st
    hookHud()
    local okP, pl = pcall(function() return a.LightningPointLight end)
    log(string.format("thunder: storm up for the %s at (%.0f, %.0f, %.0f), %.1f km round it (%s): reads back Radius %s cm, "
        .. "strike rolls every %s-%s s, curve %s, bEnableCollision %s, bTestPlayer %s, bTestEnemy %s, its flash light %s (%s)",
        owner, at.X, at.Y, at.Z, radiusM / 1000, table.concat(set, ", "), fmt(num(a, "Radius"), "%.0f"), fmt(num(a, "MinStrikeInterval"), "%.1f"),
        fmt(num(a, "MaxStrikeInterval"), "%.1f"), field(a, "WeightCurveName"), field(a, "bEnableCollision"), field(a, "bTestPlayer"),
        field(a, "bTestEnemy"), (okP and pl ~= nil and liveObj(pl)) and "there" or "none", nameOf(a)))
    crumb("thunder: storm up for the " .. owner)
    return st
end
function THUNDER.stormMove(st, at)
    if st and at and st.own then st.center, st.moves = at, st.moves + 1; return true end
    if not (st and at and liveObj(st.vol)) then return false end
    local ok = pcall(function() st.vol:K2_SetActorLocation({ X = at.X, Y = at.Y, Z = at.Z }, false, {}, true) end)
    if ok then st.center, st.moves = at, st.moves + 1 end
    return ok
end
-- The storm taken off (why: the log's): shrunk to 1 cm where it is, destroyed once nothing's inside (parkTick); a level
-- going away: forgotten, not touched.
function THUNDER.stormDown(why)
    local st = THUNDER.storm
    THUNDER.storm = nil
    if not st then return false end
    local up = os.clock() - st.at
    if THUNDER.strikesOff then THUNDER.strikesOff("its storm is off") end
    if st.own then
        log(string.format("thunder: the %s's storm off (%s) after %.0f s: %d strikes on you", st.owner, tostring(why), up, (THUNDER.sk and THUNDER.sk.n) or 0))
        crumb("thunder: storm off (" .. st.owner .. ")")
        return true
    end
    if torn() then
        log(string.format("thunder: the %s's storm forgotten with the level (%s), not touched", st.owner, tostring(why)))
        return true
    end
    if not liveObj(st.vol) then
        log(string.format("thunder: the %s's storm was gone already (%s)", st.owner, tostring(why)))
        return true
    end
    local ok = pcall(function() st.vol.Radius = PARK_RADIUS end)
    st.parkAt, st.empty, st.why = os.clock(), 0, why
    THUNDER.parked[#THUNDER.parked + 1] = st
    log(string.format("thunder: the %s's storm off (%s) after %.0f s: %d strikes and %d flashes seen, moved %d times; %s",
        st.owner, tostring(why), up, st.n, st.flashes, st.moves, ok and "shrunk to 1 cm, destroyed once nothing's inside it"
            or "its radius NOT shrunk: kept until nothing's inside it"))
    crumb("thunder: storm off (" .. st.owner .. ")")
    return true
end
local function parkTick()
    local keep = {}
    for _, st in ipairs(THUNDER.parked) do
        if liveObj(st.vol) then
            local okN, n = pcall(function() return st.vol.InsideGameObjects:GetArrayNum() end)
            if okN and n == 0 then st.empty = st.empty + 1 else st.empty = 0 end
            if st.empty >= 2 then
                local okD = pcall(function() st.vol:K2_DestroyActor() end)
                log(string.format("thunder: the %s's storm destroyed %.1f s after it was taken off (nothing inside it)%s", st.owner,
                    os.clock() - st.parkAt, okD and "" or ": K2_DestroyActor FAILED, left as it is"))
            else
                if os.clock() - st.parkAt > PARK_SAY_S and not st.keptSaid then
                    st.keptSaid = true
                    log(string.format("thunder: the %s's storm kept (1 cm) %d s after it was taken off: InsideGameObjects %s", st.owner,
                        PARK_SAY_S, okN and (tostring(n) .. " inside") or "can't be read"))
                end
                keep[#keep + 1] = st
            end
        end
    end
    THUNDER.parked = keep
end

-- its look: the game's cloud lightning crackling on it (switched off life_s on, destroyed 2 s after)
local function fxAt(at, scale)
    local f = cfg().fx
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys, why = SPC.V.asset(f.system)
    if not (lib and valid(lib) and sys and liveObj(survivalPC) and at) then
        say("fx", "thunder: its cloud lightning didn't spawn: " .. tostring(sys and "no Niagara library or player controller" or why))
        return false
    end
    local sc = tonumber(scale) or tonumber(f.scale) or 1
    local ok, comp = pcall(function()
        return lib:SpawnSystemAtLocation(survivalPC, sys, { X = at.X, Y = at.Y, Z = at.Z }, { Pitch = 0, Yaw = 0, Roll = 0 },
            { X = sc, Y = sc, Z = sc }, true, true, 0, true)
    end)
    if ok and comp ~= nil and liveObj(comp) then
        THUNDER.fx[#THUNDER.fx + 1] = { comp = comp, offAt = os.clock() + (tonumber(f.life_s) or 3) }
        return true
    end
    return false
end
local function crackle(at, now)
    local f = cfg().fx
    if not (f and f.enabled) or now < (THUNDER.fxAt or 0) then return end
    THUNDER.fxAt = now + math.max(0.5, tonumber(f.every_s) or 2.5)
    fxAt(at)
end
local function fxTick(now, all)
    local keep = {}
    for _, e in ipairs(THUNDER.fx) do
        if liveObj(e.comp) then
            if all and not e.goneAt then e.offAt = now end
            if not e.goneAt and now >= e.offAt then
                pcall(function() e.comp:Deactivate() end)
                e.goneAt = now + 2
                keep[#keep + 1] = e
            elseif e.goneAt and now >= e.goneAt then
                if not pcall(function() e.comp:K2_DestroyComponent(e.comp) end) then pcall(function() e.comp:DestroyComponent() end) end
            else
                keep[#keep + 1] = e
            end
        end
    end
    THUNDER.fx = keep
end
local function post(name)                                -- (a Wwise event of the game's SE bank, as the STORE's beeps)
    if type(name) ~= "string" or name == "" then return "none" end
    local ok, err = pcall(function()
        local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
        if not valid(lib) then error("LiveSoundBlueprintLibrary not found") end
        lib:PostEventByName(liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController"), FName(name))
    end)
    return ok and "posted" or ("NOT posted: " .. tostring(err))
end
local function postAt(name, actor)                      -- (a Wwise event on an actor: your plane's own sounds)
    if type(name) ~= "string" or name == "" then return "none" end
    if not actor then return post(name) end
    local ok, err = pcall(function()
        local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
        if not valid(lib) then error("LiveSoundBlueprintLibrary not found") end
        lib:PostEventAtActorByName(FName(name), actor)
    end)
    return ok and "posted" or ("NOT posted: " .. tostring(err))
end

---------------------------------------------------------------------------------------------------- Survival's own strikes
-- ((2026-11-08) the user's storm test of 0.74.34: the stock volume never struck: "I saw nothing happen to my aircraft with
-- the storm", "my hud was not effected either" (the one "strike" the test saw was the pause menu hiding the HUD); then:
-- "this storm needs to be insanely violent for the player", a bigger storm, faster strikes, longer effects, 10% of your
-- health a strike) Survival rolls the strikes on your plane itself while you're inside the storm (THUNDER.storm: its
-- centre and radius), every roll_s of the game clock (never while paused), at chance[k] (k: the rolls since the last
-- strike), and makes each one with the game's own pieces: the HUD's lightning blackout and static
-- (BeginHUDDistortionLightning: blackout_s hidden, static_s of noise, the distortion), the struck and noise sounds, the
-- lightning camera shake, the electric discharge on your plane, damage_pct of your MaxHealth (THE DECOY's hurt: a lethal
-- one is the game's own death), your controls upset upset_s (SV_Invert: roll inverted, throttle and brake swapped, in
-- place of the stock stall flag, which only the game's own strike sets). A miss: the evasion bolt ahead of you and the
-- voltage sparks on your plane. Each game strikes its own player (co-op: nothing synced). Log lines `lightning: ...`.
local SK = { inside = false, k = 0, n = 0, rolls = 0 }
THUNDER.sk = SK
local function sc() return cfg().strike or {} end
local function pick(v, d)                               -- a number, or a random one of { lo, hi }
    if type(v) == "table" then
        local lo, hi = tonumber(v[1]) or d, tonumber(v[2]) or tonumber(v[1]) or d
        return lo + (hi - lo) * math.random()
    end
    return tonumber(v) or d
end
local function strikeFx(path, pawn, offset)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = SPC and SPC.V and SPC.V.asset and SPC.V.asset(path)
    if not (lib and valid(lib) and sys and pawn) then return false end
    local ok, comp = pcall(function()
        return lib:SpawnSystemAttached(sys, pawn:K2_GetRootComponent(), FName("None"), offset or { X = 0, Y = 0, Z = 0 },
            { Pitch = 0, Yaw = 0, Roll = 0 }, 0, true, true, 0, true)
    end)
    if ok and comp ~= nil and liveObj(comp) then
        THUNDER.fx[#THUNDER.fx + 1] = { comp = comp, offAt = os.clock() + 3 }
        return true
    end
    return false
end
local function shakeOn(path, scale)
    if type(path) ~= "string" or path == "" or not liveObj(survivalPC) then return false end
    SK.shakeCls = SK.shakeCls or {}
    local cls = SK.shakeCls[path]
    if not (cls and liveObj(cls)) then
        cls = loadObject(path .. "." .. path:match("[^/]+$") .. "_C")
        SK.shakeCls[path] = cls
    end
    if not cls then return false end
    local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
    if pcall(function() survivalPC:ClientStartCameraShake(cls, scale, 0, rot) end) then return true end
    return pcall(function() survivalPC.PlayerCameraManager:StartCameraShake(cls, scale, 0, rot) end)
end
local function upset(on, pawn)
    local c = sc()
    if type(SV_Invert) ~= "function" then return "no SV_Invert" end
    local s = D and D.special
    if s and s.kind == "anomaly" then return "skipped (MINDRIPPER's field)" end   -- (never over the Anomaly's own)
    if on then
        SK.upsetOn = true
        SV_Invert(0, c.upset_roll == false and 0 or 1, tonumber(c.upset_fade_s) or 0.2, addrOf(pawn) or 0, 0, 0,
            c.upset_throttle == false and 0 or 1)
        return "on"
    end
    SK.upsetOn = false
    SV_Invert(0, 0, tonumber(c.upset_fade_s) or 0.2, 0)
    return "off"
end
local function noiseOff(why)
    local c = sc()
    SK.noiseUntil = nil
    local hud = hudOf()
    local ok = hud and pcall(function() hud:EndHUDDistortionLightning() end)
    postAt(c.sound_noise_stop, nil)
    log(string.format("lightning: the static over (%s)%s", why, ok and "" or ": EndHUDDistortionLightning NOT called"))
end
-- one strike on your plane now (t: the game clock)
local function strike(t, pawn)
    local c = sc()
    SK.n, SK.k, SK.lastAt = SK.n + 1, 0, t
    local parts = {}
    local hud = hudOf()
    local static = pick(c.static_s, 12)
    local d = type(c.distortion) == "table" and c.distortion or { 0, 0 }
    local info = { NeedUpdateDistortion = (tonumber(d[2]) or 0) > 0, MinDistortionScale = tonumber(d[1]) or 0,
                   MaxDistortionScale = tonumber(d[2]) or 0, HideContainerTime = 0, ShowContainerTime = 0, UseHideHUD = true,
                   BeginHideHUDTime = 0, HideHUDTime = tonumber(c.blackout_s) or 3.5, DistortionMask = 0 }
    local okH, errH = false, "no HUD"
    if hud then okH, errH = pcall(function() hud:BeginHUDDistortionLightning(static, info) end) end
    parts[#parts + 1] = okH and string.format("HUD out %.1f s, static %.0f s", info.HideHUDTime, static)
        or ("HUD NOT hit (" .. tostring(errH) .. ")")
    if okH then
        if not SK.noiseUntil then postAt(c.sound_noise, nil) end
        SK.noiseUntil = math.max(SK.noiseUntil or 0, t + static)
    end
    postAt(c.sound_strike, pawn)
    postAt(c.sound_damage, pawn)
    parts[#parts + 1] = "shake " .. (shakeOn(c.shake, tonumber(c.shake_scale) or 1.5) and "on" or "NOT on")
    parts[#parts + 1] = "bolt " .. (strikeFx(c.fx_strike, pawn) and "on you" or "NOT shown")
    local pct = tonumber(c.damage_pct) or 0
    if pct > 0 and DECOY and DECOY.hurtMe then
        local okD, what = pcall(DECOY.hurtMe, { hit = { damage_pct = pct, can_kill = c.can_kill ~= false } })
        parts[#parts + 1] = okD and tostring(what) or ("damage error " .. tostring(what))
    end
    local up = tonumber(c.upset_s) or 0
    if up > 0 then
        parts[#parts + 1] = "upset " .. upset(true, pawn)
        SK.upsetUntil = t + up
    end
    log(string.format("lightning: strike %d on you (%s, roll %d): %s", SK.n, tostring(SK.zoneName), SK.rolls, table.concat(parts, "; ")))
end
local function miss(t, pawn)
    local c = sc()
    if c.near_miss_fx == false then return end
    local f = pick(c.miss_ahead_m, 450) * 100
    strikeFx(c.fx_miss, pawn, { X = f, Y = (math.random() * 2 - 1) * 12000, Z = -2000 })
    strikeFx(c.fx_sign, pawn)
end
function THUNDER.strikesOff(why)
    if SK.inside then
        postAt(sc().sound_inside_stop, SK.pawn)
        SK.inside = false
    end
    SK.zone, SK.zoneName = nil, nil
    if SK.noiseUntil then noiseOff(why) end
    if SK.upsetOn then upset(false) end
    SK.upsetUntil, SK.pawn, SK.k = nil, nil, 0
end
-- the storm zone your plane is in: the storm (a sphere: the test's, the Anomaly's typhoon) first, else a build-up cell (a
-- column up to its top: THUNDER.cells); { key, owner, r, roll, x }, or nil
local function zoneAt(at)
    local c, st = sc(), THUNDER.storm
    if st and st.center and math.sqrt((at.X - st.center.X) ^ 2 + (at.Y - st.center.Y) ^ 2 + (at.Z - st.center.Z) ^ 2) <= st.radius then
        return { key = st, owner = tostring(st.owner) .. "'s storm", r = st.radius, roll = c.roll_s, x = 1 }
    end
    for _, cl in ipairs((THUNDER.cells and THUNDER.cells()) or {}) do
        local dx, dy = at.X - cl.at.X, at.Y - cl.at.Y
        if dx * dx + dy * dy <= cl.r * cl.r and at.Z <= cl.top then
            return { key = cl, owner = cl.name, r = cl.r, roll = cl.roll, x = cl.x }
        end
    end
    return nil
end
local function rollsText(r) return type(r) == "table" and string.format("%.1f-%.1f", r[1], r[2] or r[1]) or tostring(r) end
-- every tick: your plane inside a storm zone (not DOWN, not paused): its rolls; the static and the upset ended on time
local function strikeTick()
    local c = sc()
    local pawn = myPlane()
    local t = gameClock and gameClock(survivalPC)
    if not t or (gamePaused and gamePaused(survivalPC)) then return end      -- (the game's clock: never while paused)
    if SK.noiseUntil and t >= SK.noiseUntil then noiseOff(string.format("%.0f s on", t - (SK.lastAt or t))) end
    if SK.upsetUntil and t >= SK.upsetUntil then SK.upsetUntil = nil; upset(false) end
    local down = DOWN and DOWN.me and DOWN.me()
    if c.enabled == false or not pawn or down then
        if SK.inside then THUNDER.strikesOff(down and "you're DOWN" or "no plane") end
        return
    end
    local at = where(pawn)
    local z = at and zoneAt(at)
    local key = z and z.key or nil
    if key ~= SK.zone then
        if SK.zone then
            postAt(c.sound_inside_stop, SK.pawn)
            log(string.format("lightning: you're out of %s (%d strikes so far)", tostring(SK.zoneName), SK.n))
        end
        SK.zone, SK.zoneName, SK.inside, SK.pawn = key, z and z.owner or nil, key ~= nil, pawn
        if key then
            SK.k, SK.rollAt = 0, t + pick(z.roll, 2)
            postAt(c.sound_inside, pawn)
            log(string.format("lightning: you're inside %s (%.1f km round it): a roll every %s s, chance x%.2f", z.owner, z.r / 100000,
                rollsText(z.roll), z.x or 1))
        end
    end
    if not key or t < (SK.rollAt or 0) then return end
    SK.rollAt = t + pick(z.roll, 2)
    SK.k, SK.rolls = SK.k + 1, SK.rolls + 1
    local ch = type(c.chance) == "table" and c.chance or { 0.5 }
    local p = (tonumber(ch[math.min(SK.k, #ch)]) or 0.5) * (z.x or 1)
    postAt(c.sound_roll, pawn)
    if math.random() < p then strike(t, pawn) else miss(t, pawn) end
end
THUNDER.strikeTick = strikeTick

---------------------------------------------------------------------------------------------------- the storm's build-up
-- ((2026-11-08) the user: "have the storm gather for 3 rounds slowly building up until it's literally a typhoon to deal
-- with inside, this storm needs to be insanely violent for the player"; strikes every build-up round, small and rare
-- cells first; test key only) Ctrl+] (host or solo): Distant Thunder in 3 rounds (round N; the rounds before it, N-3 ..
-- N-1, are stages 1-3; N is stage 4, the typhoon: the Anomaly's own storm on the A-10, with the cells), pressed again: the
-- storm clears; Ctrl+' steps the stages by hand (1, 2, 3, 4, clear) for a look without the rounds. Each stage:
--   the sky: Survival's sky asset blended toward Mission 12's storm sky (sky.asset: every cloud field the two differ in,
--     read from both at run time and logged; sky.fraction of the way, at most 1 / sky.ramp_s of it a second), back over
--     sky.clear_s when it clears (SKY.writeKey: each original kept, put back with the rest at the run's end); in stage 4
--     a rain pillar on the A-10 (sky.rain_pillar: Cloudly's own, its first cloud layer's; not yet seen in game)
--   storm cells: cells.n of them, cells.radius_m round (columns up to top_m), from_km from the airfield, drifting with one
--     wind (drift_ms), each flashing in the clouds every flash_s (the game's cloud lightning; its thunder within
--     thunder_km); inside one, [thunder.strike]'s strikes at the stage's roll_s and chance x chance_x
--   the turbulence: inside a cell or the typhoon from turbulence.from_stage, the game's turbulence shake every every_s,
--     x scale[stage]; the rain from rain.from_stage (the world's bIsWorldRain and RainVFXBrightness, Mission 13's; put
--     back; not yet seen in game); the distant thunder (sound.distant) from stage 1 to the clearing's end; a callout a stage
-- Co-op: the host's "tb" (stage, seed, clearing) every 10 s and on a change; every game builds the same cells from the
-- seed (THUNDER.buFromHost). Log lines `storm build-up: ...`.
local BU = nil
local function bc() return cfg().buildup or {} end
local function ofStage(t, s, d) if type(t) ~= "table" then return t ~= nil and t or d end; local v = t[s]; if v == nil then v = t[#t] end; if v == nil then return d end; return v end
local function lcg(x) return (x * 1103515245 + 12345) % 2147483648 end
local function fv(v) if type(v) == "number" then return string.format("%.4g", v) end return tostring(v) end
-- stage s's cells from the seed (the same on every game) and its wind
local function cellsFor(s, seed, centre, onYou)
    local c = bc().cells or {}
    centre = centre or AIRFIELD
    local n = math.floor(tonumber(ofStage(c.n, s, 0)) or 0)
    local x = (seed + s * 7919) % 2147483648
    local function r() x = lcg(x); return x / 2147483648 end
    local fk = type(c.from_km) == "table" and c.from_km or { 6, 28 }
    local out = {}
    for i = 1, n do
        local ang, d = r() * 2 * math.pi, (fk[1] + (fk[2] - fk[1]) * r()) * 100000
        if onYou then d = (i == 1) and 0 or d * 0.35 end   -- (by hand: cell 1 on you, the others close round you)
        out[#out + 1] = { name = string.format("storm cell %d (stage %d)", i, s), i = i,
                          base = { X = centre.X + math.cos(ang) * d, Y = centre.Y + math.sin(ang) * d },
                          at = { X = centre.X + math.cos(ang) * d, Y = centre.Y + math.sin(ang) * d, Z = 0 },
                          r = (tonumber(ofStage(c.radius_m, s, 3000)) or 3000) * 100, top = (tonumber(c.top_m) or 7000) * 100,
                          roll = ofStage(c.roll_s, s, { 4, 6 }), x = tonumber(ofStage(c.chance_x, s, 1)) or 1,
                          flashAt = os.clock() + r() * 3 }
    end
    local wa = r() * 2 * math.pi
    return out, { X = math.cos(wa), Y = math.sin(wa) }
end
function THUNDER.cells() return BU and not BU.clearing and BU.cells or nil end
function THUNDER.buildup() return BU end

-- the sky's fields: every candidate of Survival's sky asset that Mission 12's storm sky has otherwise (read once a level)
local SKY_PATHS = { "CloudDensityExtintionBalance", "CloudSkyAmbientLightIntensity", "CloudSkyAmbientLightFadeToGray",
    "CloudSkyAmbientLightBottomOcclusion", "CloudGroundIrradianceIntensity", "CloudDirectionalLightColorAttenuation",
    "CloudDirectionalLightColorAttenuationTrThreshold", "CloudPhaseFunctionScale", "AirCraftFogScale", "CloudStartHeightInKm",
    "CloudBandThicknessInKm", "CloudBlendFactorWithAtm", "EnableClouds" }
for L = 0, 2 do
    for _, f in ipairs({ "Enable", "StartHeightInKm", "EnableUserThicknessInKm", "UserThicknessInKm", "CloudDensity",
                         "CloudDensityBottom", "CloudEdgeFadeDistance", "CloudEdgeFadeDistanceBottom", "TransitionStart",
                         "TransitionLen", "TransitionStartDensityBias", "DensityBoostEnable", "DensityBoostAdd",
                         "DensityBoostTransitionLengthInKm", "RainCloudEnable", "RainCloudStretchInKm", "RainCloudWarp",
                         "RainCloudTopDensity", "RainCloudBottomDensity", "RainCloudSoftTransition", "MapSizeMultiplier" }) do
        SKY_PATHS[#SKY_PATHS + 1] = "CloudLayer" .. L .. "." .. f
    end
end
local PILLAR = { on = "CloudLayer0.RainPillarCenterOverride", x = "CloudLayer0.RainPillarCenterInKm.X",
                 y = "CloudLayer0.RainPillarCenterInKm.Y", ron = "CloudLayer0.RainPillarRadiusOverride", r = "CloudLayer0.RainPillarRadiusInKm" }
local SF = { level = nil }
local function dataGet(o, path)
    local ok, v = pcall(function() local x = o.Data; for p in path:gmatch("[^%.]+") do x = x[p] end; return x end)
    if ok then return v end
    return nil
end
local function skyView() return SKY and SKY.viewCached and SKY.viewCached(os.clock(), nil) or nil end
local function skyFields()
    if SF.list then return SF.list end
    if os.clock() < (SF.retryAt or 0) then return nil end
    SF.retryAt = os.clock() + 10
    local c = bc().sky or {}
    local V = skyView()
    local mine = V and V.asset
    local storm, why = loadObject(c.asset)
    if not (mine and liveObj(mine)) then say("bu sky", "storm build-up: no sky asset in the level's view: the sky stays"); return nil end
    if not (storm and liveObj(storm)) then say("bu storm", "storm build-up: Mission 12's storm sky NOT loaded (" .. tostring(why) .. "): the sky stays"); return nil end
    local out, said = {}, {}
    for i, path in ipairs(SKY_PATHS) do
        local short = "sv_storm_" .. i
        SKY.addField(short, path)
        local key = "asset|" .. short
        local b = SKY.orig[key]
        if b == nil then b = dataGet(mine, path) end
        local t = dataGet(storm, path)
        if (type(b) == "number" and type(t) == "number" and math.abs(b - t) > 1e-4 * math.max(1, math.abs(b)))
            or (type(b) == "boolean" and type(t) == "boolean" and b ~= t) then
            out[#out + 1] = { key = key, path = path, base = b, target = t }
            said[#said + 1] = path .. " " .. fv(b) .. " -> " .. fv(t)
        end
    end
    for k, path in pairs(PILLAR) do SKY.addField("sv_pillar_" .. k, path) end
    SF.list = out
    log(string.format("storm build-up: %d of %d sky fields differ from Mission 12's storm sky (%s): %s", #out, #SKY_PATHS,
        tostring(c.asset):match("[^/]+$") or "?", #said > 0 and table.concat(said, ", ") or "none"))
    local skip = {}
    if c.clouds ~= true then
        for _, e in ipairs(out) do
            for _, u in ipairs(type(c.unsafe) == "table" and c.unsafe or {}) do if e.path:find(u, 1, true) then skip[#skip + 1] = e.path; break end end
        end
    end
    log(string.format("storm build-up: the clouds %s%s", c.clouds == false and "left alone (sky.clouds false)" or ("ramped: " .. (#out - #skip) .. " of them"),
        #skip > 0 and c.clouds ~= false and (", never these (they black the sky out when they change): " .. table.concat(skip, ", ")) or ""))
    return out
end
-- ((2026-11-08) the user's look at 0.74.36: a clear blue sky at 11%) the storm's darkening, by the values the day-night
-- arc proved in game (hard rule 56: the asset's sun, the post-process volumes' exposure, the level's sky light): sky.dark's
-- ev (exposure bias added), sun_x and skylight_x (x) at full storm, each from its original; never while the night arc is
-- on (it owns them then)
local function darkApply(V, f)
    local d = (bc().sky or {}).dark or {}
    if d.enabled == false then return 0, "off" end
    if ARC and ARC.on then return 0, "the night arc owns the light" end
    local n = 0
    local function put(k, v) local _, ok = SKY.writeKey(V, k, v); if ok then n = n + 1 end end
    for _, k in ipairs((SKY.keysOf and SKY.keysOf(V)) or {}) do
        local x
        if k:match("^ppv|.+|bias$") then x = "ev" elseif k:match("^skyl|.+|int$") then x = "sky" elseif k == "asset|sun_factor" then x = "sun" end
        if x then
            local base = SKY.orig[k]
            if base == nil then local get = SKY.slot(V, k); base = get and get() end
            if type(base) == "number" then
                if x == "ev" then put(k, base + (tonumber(d.ev) or -1.5) * f)
                elseif x == "sky" then put(k, base * (1 + ((tonumber(d.skylight_x) or 0.5) - 1) * f))
                else put(k, base * (1 + ((tonumber(d.sun_x) or 0.4) - 1) * f)) end
            end
        end
    end
    return n, "on"
end
-- the sky at fraction f of the way to the storm's (bools at half way), and its darkening; how many written
local function skyApply(f)
    local F = skyFields()
    local V = F and skyView()
    if not (V and V.asset) then return 0 end
    local n = 0
    -- ((2026-11-08) the user's recording of 0.74.36: the whole sky black for ~0.1 s at every write of these, once a second
    -- ("do you not see how the sky is flashing to black??"); the sky probe's recording (0.74.38, 21:40:11): only a CHANGE of
    -- the clouds' heights, rain clouds or rain pillar blacks it out; their light, density, thickness and edges never did.
    -- sky.clouds: "safe" (every field but those whose path has one of sky.unsafe), true (all), false (none))
    local sk = bc().sky or {}
    local unsafe = type(sk.unsafe) == "table" and sk.unsafe or {}
    local function safe(path)
        if sk.clouds == true then return true end
        for _, u in ipairs(unsafe) do if path:find(u, 1, true) then return false end end
        return true
    end
    if sk.clouds == true or sk.clouds == "safe" then
        for _, e in ipairs(F) do if safe(e.path) then
            local v
            if type(e.base) == "number" then v = e.base + (e.target - e.base) * f else v = (f >= 0.5) and e.target or e.base end
            local _, ok = SKY.writeKey(V, e.key, v)
            if ok then n = n + 1 end
        end end
    end
    local nd, why = darkApply(V, f)
    if why ~= SF.darkWhy then SF.darkWhy = why; log(string.format("storm build-up: its darkening %s (%d values)", why, nd)) end
    return n + nd
end
-- the rain pillar on `at` (world cm; nil: its own values back); what was done
local function pillar(at)
    local c = bc().sky or {}
    local V = SF.list and skyView()
    if not (V and V.asset) or c.rain_pillar == false then return "off" end
    local function w(k, v) local _, ok = SKY.writeKey(V, "asset|sv_pillar_" .. k, v); return ok end
    if at then
        local ok = w("on", true) and w("x", at.X / 100000) and w("y", at.Y / 100000)
        w("ron", true); w("r", (tonumber(c.pillar_km) or 6))
        return ok and string.format("on the A-10 at (%.1f, %.1f) km", at.X / 100000, at.Y / 100000) or "NOT written"
    end
    for _, k in ipairs({ "on", "x", "y", "ron", "r" }) do
        local key = "asset|sv_pillar_" .. k
        if SKY.orig[key] ~= nil then SKY.writeKey(V, key, SKY.orig[key]) end
    end
    return "back"
end
-- the world's rain (Mission 13's way): on (its originals kept) or back
local function worldSettings()
    if SF.ws and liveObj(SF.ws) then return SF.ws end
    if walkHold and walkHold() then return nil end
    for _, cn in ipairs({ "ChronicleWorldSettings", "LiveWorldSettings", "WorldSettings" }) do
        for _, o in ipairs(FindAllOf(cn) or {}) do
            if liveObj(o) and not nameOf(o):find("Default__", 1, true) and inSurvival(o) then SF.ws = o; return o end
        end
    end
    return nil
end
local function rain(on)
    local c = bc().rain or {}
    if c.enabled == false then return "off" end
    local ws = worldSettings()
    if not ws then return "no world settings found" end
    if on then
        if SF.rainWas == nil then SF.rainWas = { rain = field(ws, "bIsWorldRain"), vol = field(ws, "bIsRainVolume"), b = num(ws, "RainVFXBrightness") } end
        local ok1 = pcall(function() ws.bIsWorldRain = true end)
        local ok2 = pcall(function() ws.RainVFXBrightness = tonumber(c.brightness) or 10 end)
        return string.format("bIsWorldRain %s (read back %s), RainVFXBrightness %s (read back %s)", ok1 and "written" or "NOT written",
            field(ws, "bIsWorldRain"), ok2 and "written" or "NOT written", fmt(num(ws, "RainVFXBrightness"), "%.1f"))
    end
    local was = SF.rainWas
    SF.rainWas = nil
    if not was then return "never on" end
    pcall(function() ws.bIsWorldRain = was.rain == "true" end)
    if was.b then pcall(function() ws.RainVFXBrightness = was.b end) end
    return "put back (bIsWorldRain " .. tostring(was.rain) .. ")"
end

-- ((2026-11-08) the user: "needs way more clouds why can't we swap cloud layers around to another stormy weather system",
-- "we need to bring in the storm cloud layer from another map") the storm's cloud layout: Mission 12's CVC
-- (sky.layout.asset), the Cloudly actor's CloudlyVolumeComponentsAsset pointed at it behind the fade from layout.from_stage,
-- back as the storm clears. Only that pointer: the sky params pointer stays (sv_sky.lua finds the asset it writes through
-- it: never Mission 12's stock asset). Its textures preloaded first (Default__CloudlyActor AddPreloadedCloudTextures), the
-- original layout pinned (kept loaded while it's swapped out), then layout.force (ForceUpdate) and layout.set_resources
-- (the actor's SetResources). Whether Cloudly takes a new layout mid-level is the layout probe's (Ctrl+;). The actor's
-- NumCloudComponentsUsed / CloudComponentsTexturesCount logged before, after and 2 s on. Log: `storm layout: ...`.
local LY = { on = false }
local function lc() return (bc().sky or {}).layout or {} end
local function lyCdo() local o = StaticFindObject("/Script/Cloudly.Default__CloudlyActor"); return (o ~= nil and valid(o)) and o or nil end
local function lyAsset()
    if LY.cvc ~= nil and liveObj(LY.cvc) then return LY.cvc end
    local o, why = loadObject(lc().asset)
    LY.cvc = (o ~= nil and liveObj(o)) and o or nil
    return LY.cvc, why
end
local function lyCounts(a)
    return string.format("%s components used, %s textures", fmt(num(a, "NumCloudComponentsUsed"), "%.0f"), fmt(num(a, "CloudComponentsTexturesCount"), "%.0f"))
end
local function lyName(o) return (o ~= nil and liveObj(o)) and ((nameOf(o):match("([^%.:/ ]+)$")) or "?") or "none" end
-- the storm's layout loaded and its textures preloaded (once); what it did
local function lyPreload()
    if LY.preloaded then return "preloaded already" end
    local o, why = lyAsset()
    if not o then return "NOT loaded (" .. tostring(why) .. ")" end
    pcall(pin, o, "the storm's cloud layout")
    local cdo = lyCdo()
    local ok, err = false, "no Default__CloudlyActor"
    if cdo then ok, err = pcall(function() cdo:AddPreloadedCloudTextures(o) end) end
    LY.preloaded = ok
    return ok and ("loaded (" .. lyName(o) .. "), its textures preloaded") or ("loaded, its textures NOT preloaded (" .. tostring(err) .. ")")
end
local function lyForce()
    local cdo = lyCdo()
    if not cdo then return "no Default__CloudlyActor" end
    local ok, err = pcall(function()
        cdo:ForceUpdate({ bForceUpdateShadows = true, bForceUpdateAO = true, FrameCount = 8, bRecaptureSkyLight = false,
                          bClearReprojectionHistory = true })
    end)
    return ok and "ForceUpdate called" or ("ForceUpdate failed: " .. tostring(err))
end
local function lyResources(a)
    local ok, err = pcall(function() a:SetResources() end)
    return ok and "SetResources called" or ("SetResources failed: " .. tostring(err))
end
-- the actor's layout to the storm's (on) or back; steps: { force = bool, resources = bool }; what it did
local function lySet(on, why, steps)
    steps = steps or { force = lc().force ~= false, resources = lc().set_resources == true }
    local V = skyView()
    local a = V and V.actor
    if not (a and liveObj(a)) then return "no Cloudly actor" end
    local parts = {}
    local before = lyCounts(a)
    if on then
        local o = lyAsset()
        if not o then return "the storm's layout not loaded" end
        if not LY.was then
            local okW, w = pcall(function() return a.CloudlyVolumeComponentsAsset end)
            LY.was = okW and w or nil
            if LY.was ~= nil and liveObj(LY.was) then pcall(pin, LY.was, "Survival's own cloud layout (swapped out)") end
        end
        local ok, err = pcall(function() a.CloudlyVolumeComponentsAsset = o end)
        parts[#parts + 1] = ok and ("the layout " .. lyName(LY.was) .. " -> " .. lyName(o)) or ("the layout NOT set: " .. tostring(err))
        LY.on = ok
    else
        if not LY.was then return "never swapped" end
        local ok, err = pcall(function() a.CloudlyVolumeComponentsAsset = LY.was end)
        parts[#parts + 1] = ok and ("the layout back to " .. lyName(LY.was)) or ("the layout NOT put back: " .. tostring(err))
        if ok then LY.on = false end
    end
    if steps.force then parts[#parts + 1] = lyForce() end
    if steps.resources then parts[#parts + 1] = lyResources(a) end
    LY.checkAt, LY.checkWhy, LY.actor = os.clock() + 2, why, a
    log(string.format("storm layout: %s (%s): %s; before: %s, now: %s", on and "the storm's" or "back", why, table.concat(parts, "; "),
        before, lyCounts(a)))
    return table.concat(parts, "; ")
end
local function lyTick(now)
    if LY.checkAt and now >= LY.checkAt then
        LY.checkAt = nil
        if LY.actor and liveObj(LY.actor) then log(string.format("storm layout: 2 s after (%s): %s", tostring(LY.checkWhy), lyCounts(LY.actor))) end
    end
end
-- Ctrl+; the layout probe: 1 load and preload (both pointers logged), 2 the main pointer, 3 ForceUpdate, 4 SetResources,
-- 5 everything back
local LP = { i = 0 }
local LP_STEPS = { "load the storm's layout", "point the layout at it", "ForceUpdate", "SetResources", "everything back" }
function THUNDER.layoutStep()
    LP.i = LP.i % #LP_STEPS + 1
    local V = skyView()
    local a = V and V.actor
    local what
    if LP.i == 1 then
        local interp = "?"
        if a and liveObj(a) then local ok, x = pcall(function() return a.CloudlyInterpolatedVolumeComponentsAsset end); interp = ok and lyName(x) or "unreadable" end
        local main = "?"
        if a and liveObj(a) then local ok, x = pcall(function() return a.CloudlyVolumeComponentsAsset end); main = ok and lyName(x) or "unreadable" end
        what = lyPreload() .. string.format("; the actor's layout %s, its interpolated layout %s; %s", main, interp, a and lyCounts(a) or "no actor")
        log("storm layout: probe 1: " .. what)
    elseif LP.i == 2 then what = lySet(true, "probe 2", { force = false, resources = false })
    elseif LP.i == 3 then what = lyForce(); LY.checkAt, LY.checkWhy, LY.actor = os.clock() + 2, "probe 3", a; log("storm layout: probe 3: " .. what .. "; " .. (a and lyCounts(a) or ""))
    elseif LP.i == 4 then what = a and lyResources(a) or "no actor"; LY.checkAt, LY.checkWhy, LY.actor = os.clock() + 2, "probe 4", a; log("storm layout: probe 4: " .. what .. "; " .. (a and lyCounts(a) or ""))
    else
        what = lySet(false, "probe 5", { force = true, resources = true })
        local cdo, o = lyCdo(), LY.cvc
        if cdo and o and liveObj(o) then pcall(function() cdo:RemovePreloadedCloudTextures(o) end) end
        LY.preloaded = false
    end
    hudCallout(string.format("LAYOUT PROBE %d/%d: %s", LP.i, #LP_STEPS, string.upper(LP_STEPS[LP.i])), nil)
end
THUNDER.layoutTick = lyTick
THUNDER.layout = LY

-- ((2026-11-08) the user: "how about a cutscene transition?", then "Fade to black") the cloud values that black the sky
-- out when they change (sky.unsafe: heights, rain clouds; hard rule 61) jump to a stage's share of the storm's only under a
-- fade to black: the camera fades out over transition.out_s, they're written (a thunder clap), held black hold_s, then it
-- fades back in over in_s. At each stage change, as the storm clears (back to the originals) and when it ends early.
-- Without the camera fade they're never written. Log: `storm build-up: transition (<why>): ...`.
local TR = nil
local function unsafeFields()
    local sk = bc().sky or {}
    local out = {}
    if sk.clouds ~= "safe" then return out end
    for _, e in ipairs(SF.list or {}) do
        for _, u in ipairs(type(sk.unsafe) == "table" and sk.unsafe or {}) do
            if e.path:find(u, 1, true) then out[#out + 1] = e; break end
        end
    end
    return out
end
local function unsafeApply(fr)
    local V = skyView()
    if not (V and V.asset) then return 0 end
    local n = 0
    for _, e in ipairs(unsafeFields()) do
        local v
        if type(e.base) == "number" then v = e.base + (e.target - e.base) * fr else v = (fr >= 0.5) and e.target or e.base end
        local _, ok = SKY.writeKey(V, e.key, v)
        if ok then n = n + 1 end
    end
    SF.unsafeAt = fr
    return n
end
local function camFade(from, to, dur, hold)
    local pcm = nil
    pcall(function() pcm = survivalPC.PlayerCameraManager end)
    if not (pcm ~= nil and liveObj(pcm)) then return false, "no camera manager" end
    local ok, err = pcall(function() pcm:StartCameraFade(from, to, dur, { R = 0, G = 0, B = 0, A = 1 }, false, hold) end)
    return ok, ok and nil or tostring(err)
end
-- a transition to fraction fr (a function: read when it's dark, so the latest stage wins) of the storm's unsafe values
local function lyWanted()
    local l = lc()
    return l.enabled ~= false and BU ~= nil and not BU.clearing and (BU.stage or 0) >= (tonumber(l.from_stage) or 2)
end
local function transition(fr, why)
    local c = (bc().sky or {}).transition or {}
    if c.enabled == false or (#unsafeFields() == 0 and lyWanted() == LY.on) then return false end
    if TR then TR.fr, TR.why = fr, why; return true end     -- (one under way: it writes the latest when it's dark)
    local ok, err = camFade(0, 1, tonumber(c.out_s) or 0.5, true)
    if not ok then
        log(string.format("storm build-up: transition (%s): NOT made (%s): the heights and rain clouds left as they are", why, tostring(err)))
        return false
    end
    TR = { fr = fr, why = why, phase = "out", at = os.clock() + (tonumber(c.out_s) or 0.5) }
    return true
end
local function transitionTick(now)
    local t = TR
    if not t or now < t.at then return end
    local c = (bc().sky or {}).transition or {}
    if t.phase == "out" then
        local fr = type(t.fr) == "function" and t.fr() or t.fr
        local n = unsafeApply(tonumber(fr) or 0)
        if lyWanted() ~= LY.on then lySet(lyWanted(), t.why) end    -- (the storm's cloud layout in, or back, in the dark)
        post(c.sound)
        t.phase, t.at, t.n, t.frDone = "hold", now + (tonumber(c.hold_s) or 0.6), n, fr
    elseif t.phase == "hold" then
        local ok, err = camFade(1, 0, tonumber(c.in_s) or 0.7, false)
        t.phase, t.at = "in", now + (tonumber(c.in_s) or 0.7)
        log(string.format("storm build-up: transition (%s): faded out, %d of the heights and rain clouds written at %.0f%% of the storm's, faded back in%s",
            t.why, t.n or 0, 100 * (tonumber(t.frDone) or 0), ok and "" or (" (NOT: " .. tostring(err) .. ")")))
    else
        TR = nil
    end
end
THUNDER.transitionTick = transitionTick

-- ((2026-11-08) the user's recording of 0.74.36: the whole sky black for ~0.1 s at every write of the storm's cloud
-- values; "we need to work that out") Ctrl+/: the sky probe. Each press puts the group before back, then writes the next
-- group of Mission 12's storm sky values probe.writes times, probe.gap_s apart (one blink is easy to miss), its callout
-- naming it; after the last, everything back. Group 1 writes a sun value unchanged: if that blacks the sky out, any write
-- of the asset does. Log: `sky probe: group k of n (<name>, m values): write w of 3 at <clock>`.
local PROBE = {
    { "a sun value unchanged (the control)", { "SunIntensity.Factor" }, same = true },
    { "the clouds' light", { "CloudDensityExtintionBalance", "CloudSkyAmbientLightIntensity", "CloudSkyAmbientLightFadeToGray",
      "CloudSkyAmbientLightBottomOcclusion", "CloudGroundIrradianceIntensity", "CloudDirectionalLightColorAttenuation",
      "CloudDirectionalLightColorAttenuationTrThreshold", "CloudPhaseFunctionScale", "AirCraftFogScale", "CloudBlendFactorWithAtm" } },
    { "the clouds' density", {} }, { "the clouds' heights", { "CloudStartHeightInKm" } }, { "the clouds' thickness", { "CloudBandThicknessInKm" } },
    { "the clouds' edges", {} }, { "the rain clouds", {} }, { "the layers on or off", { "EnableClouds" } },
    { "the rain pillar on you", {}, pillar = true },
}
for L = 0, 2 do
    local p = "CloudLayer" .. L .. "."
    for _, f in ipairs({ "CloudDensity", "CloudDensityBottom", "DensityBoostEnable", "DensityBoostAdd" }) do table.insert(PROBE[3][2], p .. f) end
    table.insert(PROBE[4][2], p .. "StartHeightInKm")
    for _, f in ipairs({ "EnableUserThicknessInKm", "UserThicknessInKm" }) do table.insert(PROBE[5][2], p .. f) end
    for _, f in ipairs({ "CloudEdgeFadeDistance", "CloudEdgeFadeDistanceBottom", "TransitionStart", "TransitionLen",
                         "TransitionStartDensityBias", "DensityBoostTransitionLengthInKm", "MapSizeMultiplier" }) do table.insert(PROBE[6][2], p .. f) end
    for _, f in ipairs({ "RainCloudEnable", "RainCloudStretchInKm", "RainCloudWarp", "RainCloudTopDensity", "RainCloudBottomDensity",
                         "RainCloudSoftTransition" }) do table.insert(PROBE[7][2], p .. f) end
    table.insert(PROBE[8][2], p .. "Enable")
end
for _, k in ipairs({ "on", "x", "y", "ron", "r" }) do table.insert(PROBE[9][2], PILLAR[k]) end
local PB = { i = 0 }
THUNDER.probe = PB
local function probeKey(gi, pi) return "asset|sv_probe_" .. gi .. "_" .. pi end
local function probeFields()                            -- (registered on first use: SKY may load after this part)
    if PB.reg or not (SKY and SKY.addField) then return end
    PB.reg = true
    for gi, g in ipairs(PROBE) do for pi, path in ipairs(g[2]) do SKY.addField("sv_probe_" .. gi .. "_" .. pi, path) end end
end
-- group gi's values: the storm's (the control: as they are; the pillar: on you), or (back) the originals; how many written
local function probeWrite(gi, back)
    probeFields()
    local g = PROBE[gi]
    local V = skyView()
    if not (g and V and V.asset) then return 0, "no sky asset in the view" end
    local storm = loadObject((bc().sky or {}).asset)
    if not back and not g.same and not g.pillar and not (storm and liveObj(storm)) then return 0, "Mission 12's storm sky not loaded" end
    local you = playerLocation()
    local n = 0
    for pi, path in ipairs(g[2]) do
        local key = probeKey(gi, pi)
        local v
        if back then v = SKY.orig[key]
        elseif g.same then local get = SKY.slot(V, key); v = get and get()
        elseif g.pillar then
            local leaf = path:match("[^%.]+$")
            v = (leaf == "RainPillarCenterOverride" or leaf == "RainPillarRadiusOverride") and true
                or (leaf == "X" and you and you.X / 100000) or (leaf == "Y" and you and you.Y / 100000) or (leaf == "RainPillarRadiusInKm" and 6) or nil
        else v = dataGet(storm, path) end
        if v ~= nil then local _, ok = SKY.writeKey(V, key, v); if ok then n = n + 1 end end
    end
    return n, nil
end
local function probeTick(now)
    local w = PB.w
    if not w or now < w.at then return end
    local c = cfg().probe or {}
    local n, why = probeWrite(w.g, false)
    log(string.format("sky probe: group %d of %d (%s, %d values): write %d of %d at %.2f%s", w.g, #PROBE, PROBE[w.g][1], n, w.k,
        w.of, now, why and (" (" .. why .. ")") or ""))
    w.k = w.k + 1
    if w.k > w.of then PB.w = nil else w.at = now + (tonumber(c.gap_s) or 1) end
end
function THUNDER.probeStep(now)
    local c = cfg().probe or {}
    if PB.i > 0 then
        local n = probeWrite(PB.i, true)
        log(string.format("sky probe: group %d (%s) put back: %d values at %.2f", PB.i, PROBE[PB.i][1], n, now))
    end
    PB.i, PB.w = PB.i + 1, nil
    if PB.i > #PROBE then
        PB.i = 0
        hudCallout("SKY PROBE: ALL BACK", "PRESS AGAIN TO START OVER")
        log("sky probe: every group back as it was")
        return
    end
    local of = math.max(1, math.floor(tonumber(c.writes) or 3))
    PB.w = { g = PB.i, k = 1, of = of, at = now }
    hudCallout(string.format("SKY PROBE %d/%d: %s", PB.i, #PROBE, string.upper(PROBE[PB.i][1])),
        string.format("WATCH THE SKY: %d WRITES, %.0f S APART", of, tonumber(c.gap_s) or 1))
    probeTick(now)
end
THUNDER.probeTick = probeTick

-- ((2026-11-08) the user: "okay but how can we get lightning to play inside the clouds?") lightning in the storm's
-- clouds: a flash lights them from inside, the game's way (ALiveCloudLight: Mission 9's far explosion, Mission 12's Podarge,
-- Mission 22's shuttle launch light the clouds through Cloudly's effect light, a timeline each, restoring it after:
-- lightning.class, spawned at the spot with its WorldPosition) or Survival's own (method "effect": the Cloudly actor's
-- EffectLight driven in steps), with the game's cloud lightning bolt there (NS_CloudLightning x bolt_scale) and its thunder
-- after the sound's time (thunder_s_per_km, at most thunder_max_s). From lightning.from_stage, every every_s[stage], at a
-- storm cell (cell_share of them) or dist_km[stage] round you, alt_m up; one light at a time. Ctrl+\ is its probe: each
-- press flashes the next way 5 km ahead of you, 3 km up. Log: `cloud lightning: ...`.
local CL = { q = {} }
local function lt() return (bc().lightning or {}) end
local CL_PROBE = {
    { "Mission 9's far explosion light", "/Game/Blueprints/Cloudly/CloudLight/BP_CloudLight_Ms009_FarExplosion.BP_CloudLight_Ms009_FarExplosion_C" },
    { "Mission 12's Podarge light", "/Game/Blueprints/Cloudly/CloudLight/BP_CloudLight_Ms012_PodargeDead.BP_CloudLight_Ms012_PodargeDead_C" },
    { "Mission 22's shuttle launch light", "/Game/Blueprints/Cloudly/CloudLight/BP_CloudLight_Ms022_ShuttleLaunch.BP_CloudLight_Ms022_ShuttleLaunch_C" },
    { "Survival's own (Cloudly's effect light)", "effect" },
    { "the bolt alone (NS_CloudLightning)", "bolt" },
}
-- a cloud light of class path at `at`: the actor, or nil and why
local function cloudLightBP(path, at)
    local cls = CL[path]
    if not (cls and liveObj(cls)) then cls = loadObject(path); CL[path] = cls end
    if not cls then return nil, "its class didn't load" end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (gs and valid(gs) and liveObj(survivalPC)) then return nil, "no GameplayStatics or player controller" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = at.X, Y = at.Y, Z = at.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)
    if not okB or x == nil or not valid(x) then return nil, "no actor (" .. tostring(x) .. ")" end
    pcall(function() x.WorldPosition = { X = at.X, Y = at.Y, Z = at.Z } end)
    local c = lt()
    if c.set_color and type(c.color) == "table" then pcall(function() x.LightColor = { R = c.color[1], G = c.color[2], B = c.color[3], A = 255 } end) end
    if tonumber(c.radius_m) then pcall(function() x.AttenuationRadius = c.radius_m * 100 end) end
    local okF, a = pcall(function() return gs:FinishSpawningActor(x, t, 1) end)
    if not okF or a == nil or not valid(a) then pcall(function() x:K2_DestroyActor() end); return nil, "its spawn didn't finish" end
    return a, string.format("brightness %s, radius %s cm", fmt(num(a, "LightBrightness"), "%.0f"), fmt(num(a, "AttenuationRadius"), "%.0f"))
end
-- Survival's own: Cloudly's effect light at `at`, its intensity in steps a tick (the originals back after)
local function effectFlash(at)
    local V = skyView()
    local a = V and V.actor
    if not (a and liveObj(a)) then return false, "no Cloudly actor" end
    local okL, l = pcall(function() return a.EffectLight end)
    if not (okL and l ~= nil and liveObj(l)) then return false, "the Cloudly actor has no EffectLight" end
    local c = lt()
    CL.eff = CL.eff or { a = a, l = l, use = field(a, "bUseEffectLight"), int = num(l, "Intensity"), rad = num(l, "AttenuationRadius") }
    pcall(function() a.bUseEffectLight = true end)
    pcall(function() l:SetWorldLocation({ X = at.X, Y = at.Y, Z = at.Z }, false, {}, true) end)
    pcall(function() l:SetAttenuationRadius((tonumber(c.radius_m) or 6000) * 100) end)
    if type(c.color) == "table" then pcall(function() l:SetLightColor({ R = c.color[1] / 255, G = c.color[2] / 255, B = c.color[3] / 255, A = 1 }, true) end) end
    CL.steps, CL.stepI = c.effect_steps or { 1.0, 0.35, 0.8, 0.1, 0 }, 0
    return true, "Cloudly's effect light (was " .. tostring(CL.eff.use) .. ", intensity " .. fmt(CL.eff.int, "%.0f") .. ")"
end
local function effectTick()
    if not CL.steps then return end
    local e = CL.eff
    if not (e and liveObj(e.l)) then CL.steps = nil; return end
    CL.stepI = CL.stepI + 1
    local k = CL.steps[CL.stepI]
    if k == nil then
        CL.steps = nil
        pcall(function() e.a.bUseEffectLight = e.use == "true" end)
        if e.int then pcall(function() e.l:SetIntensity(e.int) end) end
        if e.rad then pcall(function() e.l:SetAttenuationRadius(e.rad) end) end
        return
    end
    pcall(function() e.l:SetIntensity(k * (tonumber(lt().effect_intensity) or 5.0e7)) end)
end
-- one flash at `at` by `how` (a class path, "effect" or "bolt"); what it did
local function flash(at, how, why)
    local c = lt()
    local parts = {}
    if CL.light and liveObj(CL.light) and how ~= "bolt" then return "skipped (the last light still up)" end
    if how == "effect" then
        local ok, w = effectFlash(at)
        parts[#parts + 1] = (ok and "" or "NO ") .. w
    elseif how ~= "bolt" then
        local a, w = cloudLightBP(how, at)
        CL.light = a
        parts[#parts + 1] = a and ("a cloud light (" .. (how:match("BP_CloudLight_([%w_]+)%.") or "?") .. ": " .. w .. ")") or ("NO cloud light: " .. tostring(w))
    end
    if c.bolt ~= false or how == "bolt" then
        parts[#parts + 1] = fxAt(at, tonumber(c.bolt_scale) or 12) and "the bolt" or "NO bolt"
    end
    local you = playerLocation()
    if c.thunder ~= false and you then
        local km_ = math.sqrt((you.X - at.X) ^ 2 + (you.Y - at.Y) ^ 2 + (you.Z - at.Z) ^ 2) / 100000
        local d = math.min(tonumber(c.thunder_max_s) or 6, km_ * (tonumber(c.thunder_s_per_km) or 2.9))
        CL.q[#CL.q + 1] = { at = os.clock() + d, name = c.sound or "AKE_Environment_Thunder_Play" }
        parts[#parts + 1] = string.format("its thunder in %.1f s (%.1f km off)", d, km_)
    end
    local line = table.concat(parts, ", ")
    if (CL.said or 0) < 60 then CL.said = (CL.said or 0) + 1; log(string.format("cloud lightning (%s): %s", why, line)) end
    return line
end
local function clTick(now)
    effectTick()
    for i = #CL.q, 1, -1 do
        if now >= CL.q[i].at then post(CL.q[i].name); table.remove(CL.q, i) end
    end
end
THUNDER.cloudFlash, THUNDER.cloudTick = flash, clTick
-- (the build-up's tick) a flash due at this stage: at a cell or round you, in the clouds
local function clStorm(B, now)
    local c = lt()
    if c.enabled == false or (B.stage or 0) < (tonumber(c.from_stage) or 1) or B.clearing then return end
    if now < (B.clAt or 0) then return end
    B.clAt = now + pick(ofStage(c.every_s, B.stage, { 6, 10 }), 8)
    if not B.clFirst then B.clFirst = true; return end           -- (the first one a little after the stage begins)
    local you = playerLocation()
    if not you then return end
    local alt = type(c.alt_m) == "table" and c.alt_m or { 2500, 6000 }
    local z = (alt[1] + (alt[2] - alt[1]) * math.random()) * 100
    local at
    if B.cells and #B.cells > 0 and math.random() < (tonumber(c.cell_share) or 0.5) then
        local cl = B.cells[math.random(#B.cells)]
        at = { X = cl.at.X + (math.random() * 2 - 1) * cl.r * 0.5, Y = cl.at.Y + (math.random() * 2 - 1) * cl.r * 0.5, Z = z }
    else
        local dk = ofStage(c.dist_km, B.stage, { 5, 12 })
        local d, ang = (dk[1] + (dk[2] - dk[1]) * math.random()) * 100000, math.random() * 2 * math.pi
        at = { X = you.X + math.cos(ang) * d, Y = you.Y + math.sin(ang) * d, Z = z }
    end
    flash(at, c.method == "effect" and "effect" or (c.class or CL_PROBE[1][2]), "stage " .. B.stage)
end
-- Ctrl+\: the probe, 5 km ahead of you, 3 km up
local CLP = { i = 0 }
function THUNDER.cloudProbe()
    local pawn = myPlane()
    local you = playerLocation()
    if not (pawn and you) then log("cloud lightning: Ctrl+\\: no plane of yours"); return end
    CLP.i = CLP.i % #CL_PROBE + 1
    local p = CL_PROBE[CLP.i]
    local fwd = { X = 1, Y = 0 }
    pcall(function() local f = pawn:GetActorForwardVector(); local n = math.sqrt(f.X * f.X + f.Y * f.Y); if n > 0 then fwd = { X = f.X / n, Y = f.Y / n } end end)
    local at = { X = you.X + fwd.X * 500000, Y = you.Y + fwd.Y * 500000, Z = 300000 }
    if CL.light and liveObj(CL.light) then pcall(function() CL.light:K2_DestroyActor() end); CL.light = nil end
    local what = flash(at, p[2], "probe " .. CLP.i .. ": " .. p[1])
    hudCallout(string.format("CLOUD LIGHTNING PROBE %d/%d", CLP.i, #CL_PROBE), string.upper(p[1]))
    return what
end

local function hostOrSolo() return not joiner() end
local function stageOf(B)
    if B.forced then return B.forced end
    local r = D and D.round or 0
    return math.max(1, math.min(4, r - (B.N - 4)))
end
local function sendBU(B)
    if not (hostOrSolo() and COOP and COOP.open and COOP.msg) then return end
    pcall(COOP.msg, nil, "tb", string.format("%d", B.stage or 0), string.format("%d", B.seed), B.clearing and "1" or "0")
    B.sentAt = os.clock()
end
local function startBU(N, seed, forced, why)
    local B = { D = D, N = N, seed = seed, forced = forced, stage = 0, f = 0, at = os.clock(), why = why }
    BU = B
    log(string.format("storm build-up: on (%s): %s, seed %d", why, forced and ("stage " .. forced .. " by hand")
        or string.format("Distant Thunder at round %d, stages 1-3 in rounds %d-%d", N, N - 3, N - 1), seed))
    return B
end
local function clearBU(B, why)
    if B.clearing then return end
    B.clearing, B.clearAt = true, os.clock()
    if (SF.unsafeAt or 0) > 0 or LY.on then transition(0, "the storm clears") end
    THUNDER.strikesOff("the storm clears")
    local t = bc().text or {}
    if t.clear then hudCallout(t.clear, t.clear_sub) end
    log(string.format("storm build-up: the storm clears (%s): the sky back over %d s; rain %s; the rain pillar %s", why,
        math.floor(tonumber((bc().sky or {}).clear_s) or 90), rain(false), pillar(nil)))
    sendBU(B)
end
local function endBU(why)
    local B = BU
    if not B then return end
    BU = nil
    if B.f and B.f > 0 then skyApply(0) end
    if ((SF.unsafeAt or 0) > 0 or LY.on) and not torn() then transition(0, "the storm's over") end
    pillar(nil)
    local r = rain(false)
    if B.distant then post((bc().sound or {}).distant_stop) end
    THUNDER.strikesOff("the storm's over")
    log(string.format("storm build-up: over (%s); rain %s", why, r))
end
THUNDER.buEnd = endBU
-- every tick, every game
local function buTick(now)
    local B = BU
    if not B then return end
    local c = bc()
    if B.D ~= D then endBU("a new run"); return end
    if not B.joiner and not B.forced and not B.clearing and D and B.stage >= 4 and (D.round > B.N or (D.round == B.N and D.state == "wait")) then
        clearBU(B, "round " .. B.N .. " is over")
    end
    -- the stage
    if not B.clearing then
        local s = stageOf(B)
        if s ~= B.stage then
            B.stage, B.stageAt = s, now
            local you = B.byHand and playerLocation() or nil
            B.cells, B.wind = cellsFor(s, B.seed, you, you ~= nil)
            local t = c.text or {}
            if t.stage and t.stage[s] then hudCallout(t.stage[s], t.stage_sub and t.stage_sub[s] or nil) end
            if s == 1 and not B.distant then B.distant = true; post((c.sound or {}).distant) end
            if lc().enabled ~= false and not LY.preloaded and s >= (tonumber(lc().from_stage) or 2) - 1 then
                log("storm layout: " .. lyPreload())
            end
            skyFields()
            transition(function() return BU and not BU.clearing and (tonumber(ofStage((c.sky or {}).fraction, BU.stage, 1)) or 1) or 0 end,
                "stage " .. s)
            local rn = (s >= (tonumber((c.rain or {}).from_stage) or 3)) and rain(true) or "not yet"
            log(string.format("storm build-up: stage %d%s: %d storm cells (%.1f km round, %s s between rolls, chance x%.2f), the sky to %.0f%% of the storm's; rain %s",
                s, s == 4 and " (the typhoon)" or "", #B.cells, (B.cells[1] and B.cells[1].r or 0) / 100000, rollsText(B.cells[1] and B.cells[1].roll or "-"),
                B.cells[1] and B.cells[1].x or 0, 100 * (tonumber(ofStage((c.sky or {}).fraction, s, 1)) or 1), rn))
            sendBU(B)
        end
        -- Distant Thunder itself at round N (the host's or solo)
        if not B.joiner and not B.forced and not B.forcedSpecial and D and D.round >= B.N - 1 then
            B.forcedSpecial = true
            D.forceSpecial = "thunder"
            log(string.format("storm build-up: round %d is Distant Thunder's (D.forceSpecial)", B.N))
        end
    end
    if B.joiner == nil and hostOrSolo() and now - (B.sentAt or 0) >= 10 then sendBU(B) end
    -- the cells drift and flash
    local fc = c.cells or {}
    if B.cells and not B.clearing then
        local age = now - (B.stageAt or now)
        local wrap = (tonumber(fc.wrap_km) or 35) * 100000
        local you = playerLocation()
        for _, cl in ipairs(B.cells) do
            local v = (tonumber(fc.drift_ms) or 15) * 100 * age
            cl.at.X, cl.at.Y = cl.base.X + B.wind.X * v, cl.base.Y + B.wind.Y * v
            local dx, dy = cl.at.X - AIRFIELD.X, cl.at.Y - AIRFIELD.Y
            if dx * dx + dy * dy > wrap * wrap then                     -- (blown out of the arena: back in on the far side)
                cl.base = { X = AIRFIELD.X - dx * 0.9 - B.wind.X * v, Y = AIRFIELD.Y - dy * 0.9 - B.wind.Y * v }
            end
            if now >= cl.flashAt then
                cl.flashAt = now + pick(ofStage(fc.flash_s, B.stage, { 3, 6 }), 4)
                fxAt({ X = cl.at.X, Y = cl.at.Y, Z = (tonumber(fc.flash_z_m) or 2500) * 100 }, tonumber(fc.flash_scale) or 8)
                if you and math.sqrt((you.X - cl.at.X) ^ 2 + (you.Y - cl.at.Y) ^ 2) <= (tonumber(fc.thunder_km) or 12) * 100000 then
                    post((c.sound or {}).clap)
                end
            end
        end
    end
    -- the lightning in the clouds
    clStorm(B, now)
    -- the turbulence inside a cell or the typhoon
    local tb = c.turbulence or {}
    if SK.zone and B.stage >= (tonumber(tb.from_stage) or 2) and now >= (B.turbAt or 0) then
        B.turbAt = now + pick(tb.every_s, 2)
        local sc_ = tonumber(ofStage(tb.scale, B.stage, 1)) or 1
        if sc_ > 0 then shakeOn(tb.shake, sc_) end
    end
    -- the sky, once a second: toward the stage's fraction (clearing: 0)
    if now >= (B.skyAt or 0) then
        B.skyAt = now + 1
        local sk = c.sky or {}
        local want = B.clearing and 0 or (tonumber(ofStage(sk.fraction, B.stage, 1)) or 1)
        local rate = 1 / math.max(1, tonumber(B.clearing and sk.clear_s or sk.ramp_s) or 120)
        local f = B.f or 0
        if B.snap then f, B.snap = want, false             -- (by hand: the stage's sky at once)
        elseif f < want then f = math.min(want, f + rate) elseif f > want then f = math.max(want, f - rate) end
        if f ~= B.f or not B.skyOnce then
            B.f, B.skyOnce = f, true
            local n = skyApply(f)
            if not B.skySaid or math.abs(f - (B.skySaid or 0)) >= 0.1 or f == want then
                if B.skySaid ~= f then log(string.format("storm build-up: the sky %.0f%% of the way to the storm's (%d values written)", 100 * f, n)) end
                B.skySaid = f
            end
        end
        -- the rain pillar on the typhoon (stage 4, the A-10's storm up)
        local st = THUNDER.storm
        if B.stage >= 4 and not B.clearing and st and st.owner ~= "test" and st.center then
            local p = pillar(st.center)
            if not B.pillarSaid then B.pillarSaid = true; log("storm build-up: the rain pillar " .. p) end
        end
        if B.clearing and f <= 0 then endBU("cleared") end
    end
end
THUNDER.buTick = buTick
-- (a joiner, sv_coop_migration.lua: the host's "tb") its numbers checked first
function THUNDER.buFromHost(f)
    if not (D and joiner()) then return end
    local s, seed, cl = math.floor(tonumber(f[2]) or -1), math.floor(tonumber(f[3]) or -1), f[4] == "1"
    if s < 0 or s > 4 or seed < 0 or seed >= 2147483648 then return end
    if s == 0 then if BU then endBU("the host's is over") end return end
    if not (BU and BU.seed == seed and BU.D == D) then
        BU = startBU(0, seed, s, "the host's")
        BU.joiner = true
    end
    BU.forced = s
    if cl then clearBU(BU, "the host's clears") end
end

---------------------------------------------------------------------------------------------------- the Anomaly
-- its health for this round (HP) and the round's x
local function bossHp()
    local c = cfg()
    local round = (D and D.round) or 1
    local hx = math.min(tonumber(c.health_max_x) or 1, 1 + (tonumber(c.health_per_round) or 0) * math.max(0, round - (CFG.specials.first or 1)))
    return math.max(1, (tonumber(c.health) or 1000) * hx), hx
end
-- its live planes (just made ones too) of its unit: { q, ... }
local function bossPlanes(unit)
    local out, seen = {}, {}
    for _, list in ipairs({ planes, pending }) do
        for _, q in ipairs(list) do
            if q.unit == unit and not q.down and liveObj(q.obj) then
                local a = addrOf(q.obj)
                if a and not seen[a] then
                    seen[a] = true
                    local h = num(q.obj, "HealthInternal")
                    if h == nil or h > 0 then out[#out + 1] = q end
                end
            end
        end
    end
    return out
end
-- its name on its box: the callsign line (the plane's CallsignId, the text key name_key: its text set with SV_SetText),
-- written once a plane before its box is made; its type line left as the A-10's (ObjNameID is only logged: it may be the
-- name the event records find it by)
local function nameBox(o)
    local c = cfg()
    local a = addrOf(o)
    if not a or THUNDER.named[a] then return end
    local set = type(SV_SetText) == "function" and SV_SetText(c.name_key, c.name) or "no SV_SetText"
    local okW, w = pcall(function() return o.CallsignId end)
    local was = (okW and w ~= nil) and str(w) or nil      -- (put back at its end only when it could be read)
    local cs0 = was or "?"
    local ok = pcall(function() o.CallsignId = c.name_key end)
    THUNDER.named[a] = { obj = o, was = was }
    local okG, g = pcall(function() return o:GetCallsign() end)
    log(string.format("thunder: its box (%s): CallsignId '%s' -> %s (reads back '%s', GetCallsign() '%s'; %s %s: %s), ObjNameID '%s'",
        nameOf(o), cs0, ok and ("'" .. c.name_key .. "'") or "NOT written", field(o, "CallsignId"), okG and str(g) or "?",
        c.name_key, c.name, tostring(set), field(o, "ObjNameID")))
end
-- its box's callsign put back on what's still live of it (its end)
local function unname()
    for _, e in pairs(THUNDER.named) do
        if e.was ~= nil and not torn() and liveObj(e.obj) then pcall(function() e.obj.CallsignId = e.was end) end
    end
    THUNDER.named = {}
end

function THUNDER.ready()
    local c = cfg()
    if c.enabled == false or type(SV_UnitAlive) ~= "function" then return false end
    return SV_UnitAlive(c.unit) <= 0
end
-- (its round's "@thunder", sv_rounds.lua) the A-10 on its unit spawn_km from you; false if it can't come
function THUNDER.spawn(now)
    install()
    local c, s = cfg(), D.special
    if c.enabled == false then log("thunder: switched off ([thunder] enabled = false): a normal round instead"); return false end
    local up = SV_UnitAlive(c.unit)
    if up > 0 then log(string.format("thunder: %s still has %d up: a normal round instead", c.unit, up)); return false end
    local x, y, dist, bearing = spawnPoint()
    local px, py, pb, pd = ANOM.nearPlayer(c.spawn_km)
    if px then x, y, bearing = px, py, pb end
    local alt = CFG.altitude_m[1] + math.random() * (CFG.altitude_m[2] - CFG.altitude_m[1])
    local set = SV_SetAircraft(c.unit, c.row)
    if type(SV_SetLevel) == "function" then SV_SetLevel(c.unit, c.ai_level * 100) end
    spawningUnit = c.unit
    local okS, r = pcall(SV_Spawn, c.unit, x, y, alt * 100, (bearing + 180) % 360)
    spawningUnit = nil
    if not okS then log("thunder: SV_Spawn error " .. tostring(r)); return false end
    log(string.format("thunder: %s / %s as %s on %s (%s set), %s, %.1f km up: %s", c.tag, c.name, c.row, c.unit, tostring(set),
        pd and string.format("%.1f km from you at bearing %.0f", pd, pb) or string.format("%.0f km from the airfield at bearing %.0f", dist, bearing),
        alt / 1000, r > 0 and (r .. " aircraft up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")")))
    if r <= 0 then return false end
    for _, q in ipairs(bossPlanes(c.unit)) do nameBox(q.obj) end      -- (before a frame is drawn: its box made with it)
    D.flightTier = D.flightTier or {}
    D.up[c.unit], D.flown[c.unit], D.flightTier[c.unit] = true, true, #CFG.tiers.list
    s.state, s.at = "hunt", now
    THUNDER.lastSeen, THUNDER.fxAt, THUNDER.stormSaid = os.clock(), nil, nil
    local cam = 0
    for k, n in ipairs(ANOMALY_CAMERAS or {}) do if n == c.camera then cam = k end end
    local camR = "none"
    if cam > 0 and type(SV_Event) == "function" then camR = tostring(SV_Event("RE_SV_AnomalyCam_" .. string.char(64 + cam))) end
    hudCallout(string.format(c.text.warn, c.tag), string.format(c.text.warn_sub, c.name))
    log(string.format("thunder: its warning; its camera %s (%s); its sound %s: %s", c.camera, camR, tostring(c.start_sound), post(c.start_sound)))
    return true
end
-- the storm kept on it at `at` (owner "boss" or "copy"): made the first time (a test's storm ends first), moved after
local function keepStorm(owner, at)
    local st = THUNDER.storm
    if st and st.owner == "test" and THUNDER.testEnd then THUNDER.testEnd(os.clock(), "the Anomaly's storm takes over"); st = THUNDER.storm end
    if st and st.owner ~= owner then THUNDER.stormDown("the " .. owner .. "'s storm takes over"); st = nil end
    if not st then
        if os.clock() < (THUNDER.stormRetry or 0) then return nil end
        local why
        st, why = THUNDER.stormUp(owner, at, tonumber(cfg().storm.radius_m) or 3000)
        if not st then
            THUNDER.stormRetry = os.clock() + 10
            if not THUNDER.stormSaid then THUNDER.stormSaid = true; log("thunder: no storm on it: " .. tostring(why) .. " (tried again every 10 s)") end
            return nil
        end
    end
    THUNDER.stormMove(st, at)
    return st
end
local function stormOff(owner, why)
    if THUNDER.storm and THUNDER.storm.owner == owner then return THUNDER.stormDown(why) end
    return false
end
local function bossDown(now, s)
    local c, t = cfg(), cfg().text
    s.state = "done"
    stormOff("boss", "it's down")
    if s.lastAt then fxAt(s.lastAt); fxAt(s.lastAt) end
    if type(SV_Event) == "function" then SV_Event("RE_SV_AnomalyEnd") end                -- (the WARNING, noise and throttle off)
    local snd = post(c.stop_sound)
    unname()
    local pay = c.reward + (c.reward_per_round or 0) * D.round
    addCredits(pay, c.name .. " down")
    hudCallout(string.format(t.down, c.name), string.format(t.down_sub, specialPay(pay)))
    log(string.format("thunder: round %d, %s shot down %.0f s after it appeared; RE_SV_AnomalyEnd fired, its sound's stop %s", D.round,
        c.name, now - (s.at or now), snd))
end
-- (the host's or solo, every tick of its round) its health once, its box, the storm on it, its end
function THUNDER.tick(now, s)
    install()
    local c = cfg()
    THUNDER.lastSeen = os.clock()
    if s.state ~= "hunt" then stormOff("boss", "its fight is over"); return end
    if now - (s.at or now) >= 2 and SV_UnitAlive(c.unit) <= 0 then return bossDown(now, s) end
    local q = bossPlanes(c.unit)[1]
    if not q then return end
    local o = q.obj
    nameBox(o)
    if not s.healthDone then
        s.healthDone = true
        local hp, hx = bossHp()
        local h0, m0 = num(o, "HealthInternal"), num(o, "MaxHealth")
        local okM = pcall(function() o.MaxHealth = hp end)
        local okH = pcall(function() o.HealthInternal = math.floor(hp * 10 + 0.5) end)
        log(string.format("thunder: %s's health x%.2f for round %d: %s HP (MaxHealth %s -> %s%s, HealthInternal %s -> %s%s)", c.name, hx,
            D.round, fmt(hp, "%.0f"), tostring(m0), fmt(num(o, "MaxHealth"), "%.0f"), okM and "" or " NOT written", tostring(h0),
            tostring(num(o, "HealthInternal")), okH and "" or " NOT written"))
    end
    local at = where(o)
    if not at then return end
    s.lastAt = at
    local you = playerLocation()
    if you then s.dist = km(at, you) end
    local clock = os.clock()
    if ANOM.downNow() then
        stormOff("boss", "you're DOWN")
    else
        local st = keepStorm("boss", at)
        if st and c.storm.log_strikes then watch(st, clock, "thunder", myPlane()) end
    end
    crackle(at, clock)
end
function THUNDER.over(now, s)
    stormOff("boss", "its round is over")
    fxTick(os.clock(), true)
end
function THUNDER.row(s, t)
    local c = cfg()
    if not (s and s.state == "hunt" and s.dist) then return nil end
    local st = THUNDER.storm
    if st and st.owner == "boss" and s.dist * 100000 <= st.radius then return string.format(c.text.row_storm, c.name) end
    return string.format(c.text.row, c.name, s.dist)
end
SPC.kinds.thunder = { sub = function() return cfg().tag end, alone = true, aircraft = 1,
                      ready = function() return THUNDER.ready() end, spawn = function(now) return THUNDER.spawn(now) end,
                      tick = function(now, s) return THUNDER.tick(now, s) end, over = function(now, s) return THUNDER.over(now, s) end,
                      row = function(s, t) return THUNDER.row(s, t) end }
-- (its stock records set the attack throttle at its appearance and put B back at its death, as MINDRIPPER's)
TIER.PRESSURE_OWN.thunder = true

-- A co-op joiner: a storm on this game's live copy of it while the host's hunts ("rnd" field 12), off when it's over, when
-- there's no live copy and while you're DOWN; its box named here too
local function clientTick(now)
    local c = cfg()
    local hs = D and D.hostSpecial
    if not (hs and hs.kind == "thunder" and hs.state == "hunt") then
        stormOff("copy", "the host's is over")
        if next(THUNDER.named) then unname() end
        return
    end
    THUNDER.lastSeen = now
    for _, q in ipairs(pending) do if q.unit == c.unit and liveObj(q.obj) then nameBox(q.obj) end end
    local p = ANOM.liveCopy(c.unit)
    if not p then stormOff("copy", "no live copy of it here"); return end
    local o = p.obj
    nameBox(o)
    local a = addrOf(o)
    if a and THUNDER.copyHp ~= a then                    -- (its MaxHealth for its box; its health is the host's "hp")
        THUNDER.copyHp = a
        local hp = bossHp()
        local m0 = num(o, "MaxHealth")
        local ok = pcall(function() o.MaxHealth = hp end)
        log(string.format("coop: thunder: the host's %s here: its copy's MaxHealth %s -> %s%s (its health comes from the host)", c.name,
            tostring(m0), fmt(hp, "%.0f"), ok and "" or " NOT written"))
    end
    if ANOM.downNow() then stormOff("copy", "you're DOWN"); return end
    local at = where(o)
    if not at then return end
    local st = keepStorm("copy", at)
    if st and c.storm.log_strikes then watch(st, now, "thunder", myPlane()) end
    crackle(at, now)
end

---------------------------------------------------------------------------------------------------- the storm test
local function readLS(p)
    return { min = num(p, "LS_MinDebuffTime"), max = num(p, "LS_MaxDebuffTime"), stall = num(p, "LS_StallTime") }
end
local function lsText(ls) return string.format("LS_MinDebuffTime %s, LS_MaxDebuffTime %s, LS_StallTime %s", fmt(ls.min, "%.1f"), fmt(ls.max, "%.1f"), fmt(ls.stall, "%.1f")) end
function THUNDER.testEnd(now, why)
    local T = THUNDER.test
    THUNDER.test = nil
    if not T then return end
    local back = "not changed"
    if T.stalled then
        if not torn() and liveObj(T.pawn) and addrOf(T.pawn) == T.pawnAddr and T.ls.stall then
            local ok = pcall(function() T.pawn.LS_StallTime = T.ls.stall end)
            back = ok and string.format("back to %s", fmt(num(T.pawn, "LS_StallTime"), "%.1f")) or "NOT put back"
        else
            back = "not put back (the plane's gone)"
        end
    end
    if THUNDER.storm == T.st then THUNDER.stormDown(why) end
    local st = T.st
    local by = {}
    for _, k in ipairs(st.strikes) do for _, x in ipairs(k.by) do by[x:match("^[^%(]+") or x] = (by[x:match("^[^%(]+") or x] or 0) + 1 end end
    local byT = {}
    for k, n in pairs(by) do byT[#byT + 1] = string.format("%s x%d", (k:gsub("%s+$", "")), n) end
    table.sort(byT)
    log(string.format("storm test: over (%s) after %.0f s: %d strikes seen (%s), %d flashes; your health %s..%s over %d samples (%s); "
        .. "LS_StallTime %s", tostring(why), now - T.at, st.n, #byT > 0 and table.concat(byT, ", ") or "none", st.flashes,
        tostring(T.hMin), tostring(T.hMax), T.nH, (T.hMin ~= nil and T.hMin == T.hMax) and "it never moved" or "it MOVED", back))
    hudCallout(cfg().text.storm_off, string.format("%d STRIKES", st.n))
end
local function testStart(now)
    local c = cfg().test
    local pawn, at = myPlane(), playerLocation()
    if not (pawn and at) then log("storm test: Ctrl+,: no plane of yours in the level"); return end
    if THUNDER.storm then
        log("storm test: Ctrl+,: a storm is up already (the " .. tostring(THUNDER.storm.owner) .. "'s): not started")
        hudCallout("TEST: STORM ALREADY UP", string.upper(tostring(THUNDER.storm.owner)))
        return
    end
    local st, why = THUNDER.stormUp("test", at, tonumber(c.radius_m) or 3000)
    if not st then log("storm test: Ctrl+,: no storm: " .. tostring(why)); hudCallout("TEST: NO STORM", "SEE THE LOG"); return end
    local T = { run = D, st = st, at = now, untilAt = now + (tonumber(c.seconds) or 60), pawn = pawn, pawnAddr = addrOf(pawn),
                ls = readLS(pawn), nH = 0, last = {}, lineAt = now + 1 }
    THUNDER.test = T
    log(string.format("storm test: Ctrl+,, the storm on you for %d s, %.1f km round you; your plane (%s): %s; health %s, MaxHealth %s",
        c.seconds, (tonumber(c.radius_m) or 3000) / 1000, nameOf(pawn), lsText(T.ls), tostring(num(pawn, "HealthInternal")),
        tostring(num(pawn, "MaxHealth"))))
    shakeMgr(st)
    hudCallout(cfg().text.storm_on, string.format(cfg().text.storm_on_sub, c.seconds, (tonumber(c.radius_m) or 3000) / 1000))
end
local function testStall(now, T)
    local c = cfg().test
    local was = num(T.pawn, "LS_StallTime")
    local ok = false
    if liveObj(T.pawn) then ok = pcall(function() T.pawn.LS_StallTime = c.stall_s end) end
    T.stalled, T.untilAt = true, now + (tonumber(c.seconds) or 60)
    log(string.format("storm test: Ctrl+, again: your plane's LS_StallTime %s -> %s (%s; stock %s): each strike's stall flag held that "
        .. "long; the storm on you %d s more", fmt(was, "%.1f"), fmt(num(T.pawn, "LS_StallTime"), "%.1f"), ok and "written" or "NOT written",
        fmt(T.ls.stall, "%.1f"), c.seconds))
    hudCallout(string.format(cfg().text.storm_stall, c.stall_s), cfg().text.storm_stall_sub)
end
local function testTick(now)
    local T = THUNDER.test
    if not T then return end
    if T.run ~= D then THUNDER.testEnd(now, "a new run"); return end
    if THUNDER.storm ~= T.st then THUNDER.test = nil; log("storm test: its storm was taken off by something else"); return end
    if now >= T.untilAt then THUNDER.testEnd(now, string.format("%d s up", math.floor(cfg().test.seconds or 60))); return end
    local pawn = myPlane()
    if pawn and addrOf(pawn) ~= T.pawnAddr then
        T.pawn, T.pawnAddr, T.ls = pawn, addrOf(pawn), readLS(pawn)
        log("storm test: your plane changed (" .. nameOf(pawn) .. "): " .. lsText(T.ls))
        if T.stalled then pcall(function() pawn.LS_StallTime = cfg().test.stall_s end) end
    end
    local at = playerLocation()
    if at then THUNDER.stormMove(T.st, at) end
    local h = pawn and num(pawn, "HealthInternal")
    if h then
        T.nH = T.nH + 1
        T.hMin, T.hMax = math.min(T.hMin or h, h), math.max(T.hMax or h, h)
        if T.lastH and h ~= T.lastH then
            local k = T.st.strikes[#T.st.strikes]
            log(string.format("storm test: your health moved %s -> %s at +%.1f s (%s)", tostring(T.lastH), tostring(h), now - T.at,
                k and string.format("strike %d was %.1f s before", k.n, now - k.at) or "no strike seen yet"))
        end
        T.lastH = h
    end
    T.last[#T.last + 1] = h and tostring(h) or "?"
    watch(T.st, now, "storm test", pawn)
    if now >= T.lineAt then
        T.lineAt = now + 1
        local kmh = motion(pawn)
        local _, nAi = aiInside(T.st)
        log(string.format("storm test: +%.0f s: health %s; %s km/h; %d strikes, %d flashes; %d AI planes inside", now - T.at,
            table.concat(T.last, " "), fmt(kmh, "%.0f"), T.st.n, T.st.flashes, nAi))
        T.last = {}
    end
end

---------------------------------------------------------------------------------------------------- keys, ticks, the level
-- (every tick of a run, every game: the parked storms, its look, the storm test, a joiner's storm, a host's storm with no
-- fight left)
TEST_TICKS[#TEST_TICKS + 1] = { name = "thunder", fn = function(now)
    install()
    if torn() then
        if THUNDER.storm or #THUNDER.parked > 0 or THUNDER.test then
            log("thunder: the level is going: its storms and the storm test forgotten, not touched")
            THUNDER.storm, THUNDER.parked, THUNDER.test, THUNDER.fx, THUNDER.named = nil, {}, nil, {}, {}
            SK.inside, SK.noiseUntil, SK.upsetUntil, SK.upsetOn, SK.pawn, SK.zone = false, nil, nil, false, nil, nil
            BU, SF.list, SF.ws, SF.rainWas, TR, SF.unsafeAt = nil, nil, nil, nil, nil, nil
            LY.on, LY.was, LY.actor, LY.checkAt, LY.preloaded, LP.i = false, nil, nil, nil, false, 0
            CL.q, CL.light, CL.eff, CL.steps, CLP.i = {}, nil, nil, nil, 0
        end
        return
    end
    parkTick()
    fxTick(now, false)
    testTick(now)
    pcall(lyTick, now)
    local okC, errC = pcall(clTick, now)
    if not okC then say("cloud lightning", "cloud lightning: error " .. tostring(errC)) end
    local okT, errT = pcall(transitionTick, now)
    if not okT then say("transition", "storm build-up: transition error " .. tostring(errT)) end
    local okP, errP = pcall(probeTick, now)
    if not okP then say("probe", "sky probe: error " .. tostring(errP)) end
    local okB, errB = pcall(buTick, now)
    if not okB then say("bu", "storm build-up: error " .. tostring(errB)) end
    local okS, errS = pcall(strikeTick)
    if not okS then say("strike", "lightning: strike error " .. tostring(errS)) end
    if joiner() then
        clientTick(now)
    else
        local s = D and D.special
        if not (s and s.kind == "thunder" and s.state == "hunt") then
            stormOff("boss", "its round is over")
            if next(THUNDER.named) then unname() end
        end
        stormOff("copy", "this game hosts now")
    end
end }
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["thunder"] = function()
        BU, SF.list, SF.ws, SF.rainWas, SK.zone, SK.inside, PB.i, PB.w, TR, SF.unsafeAt = nil, nil, nil, nil, nil, false, 0, nil, nil, nil
        LY.on, LY.was, LY.actor, LY.checkAt, LY.preloaded, LP.i = false, nil, nil, nil, false, 0
        CL.q, CL.light, CL.eff, CL.steps, CLP.i = {}, nil, nil, nil, 0
        THUNDER.storm, THUNDER.parked, THUNDER.test, THUNDER.fx, THUNDER.named = nil, {}, nil, {}, {}
        THUNDER.cls, THUNDER.copyHp, THUNDER.mgr = nil, nil, nil
    end
end
-- Ctrl+,: the storm test (any game: it's this game's own)
testKey("OEM_COMMA", "sv_anomalies.lua's storm test", function()
    local now = os.clock()
    install()
    if not (D and D.now) then log("storm test: Ctrl+, outside a Survival run"); return end
    local T = THUNDER.test
    if T and T.run ~= D then THUNDER.testEnd(now, "a new run"); T = nil end
    if not T then testStart(now)
    elseif not T.stalled then testStall(now, T)
    else THUNDER.testEnd(now, "Ctrl+,") end
end)
-- Ctrl+]: the storm's build-up (Distant Thunder in 3 rounds), the host's or solo; pressed again: the storm clears
testKey("OEM_SIX", "sv_anomalies.lua's storm build-up", function()
    install()
    if not (D and D.now) then log("storm build-up: Ctrl+] outside a Survival run"); return end
    if joiner() then log("storm build-up: Ctrl+]: the host brings it (you're a joiner)"); return end
    if bc().enabled == false then log("storm build-up: Ctrl+]: switched off ([thunder] buildup.enabled = false)"); return end
    if BU and not BU.clearing then clearBU(BU, "Ctrl+]"); return end
    if BU then endBU("Ctrl+] again") end
    local N = (D.state == "wait") and (D.round + 4) or (D.round + 3)
    startBU(N, math.floor(os.time() % 1000003), nil, "Ctrl+]")
    local t = bc().text or {}
    hudCallout(t.start or "WEATHER WARNING", string.format(t.start_sub or "DISTANT THUNDER IN ROUND %d", N))
end)
-- Ctrl+\: the cloud lightning probe (any game: this game's own sky)
testKey("OEM_FIVE", "sv_anomalies.lua's cloud lightning probe", function()
    install()
    if not (D and D.now) then log("cloud lightning: Ctrl+\\ outside a Survival run"); return end
    THUNDER.cloudProbe()
end)
-- Ctrl+;: the layout probe (any game: this game's own sky)
testKey("OEM_ONE", "sv_anomalies.lua's cloud layout probe", function()
    install()
    if not (D and D.now) then log("storm layout: Ctrl+; outside a Survival run"); return end
    THUNDER.layoutStep()
end)
-- Ctrl+/: the sky probe (any game: this game's own sky)
testKey("OEM_TWO", "sv_anomalies.lua's sky probe", function()
    install()
    if not (D and D.now) then log("sky probe: Ctrl+/ outside a Survival run"); return end
    THUNDER.probeStep(os.clock())
end)
-- Ctrl+': the build-up's stages by hand (1, 2, 3, 4: the typhoon's look, then the storm clears), any round, the host's or solo
testKey("OEM_SEVEN", "sv_anomalies.lua's storm stages", function()
    install()
    if not (D and D.now) then log("storm build-up: Ctrl+' outside a Survival run"); return end
    if joiner() then log("storm build-up: Ctrl+': the host's (you're a joiner)"); return end
    if not BU or BU.clearing then
        if BU then endBU("Ctrl+' again") end
        startBU(D.round + 3, math.floor(os.time() % 1000003), 1, "Ctrl+'")
        BU.byHand, BU.snap, BU.skyAt = true, true, 0
    elseif (BU.forced or BU.stage) >= 4 then
        BU.snap, BU.skyAt = true, 0
        clearBU(BU, "Ctrl+'")
    else
        BU.forced, BU.byHand, BU.snap, BU.skyAt = (BU.forced or BU.stage) + 1, true, true, 0   -- (the sky on the next tick)
    end
    hudCallout(string.format("TEST: STORM %s", BU and BU.clearing and "CLEARING" or ("STAGE " .. tostring(BU and BU.forced))), nil)
end)
-- Ctrl+.: the next round is IFF FATAL ERROR's (in the break: it starts in 3 s), the host's or solo
testKey("OEM_PERIOD", "sv_anomalies.lua's IFF FATAL ERROR", function()
    install()
    local c = cfg()
    if not (D and D.now) or not nativeReady() then log("thunder: Ctrl+. outside a Survival run"); return end
    if joiner() then log("thunder: Ctrl+.: the host brings it (you're a joiner)"); return end
    if c.enabled == false then log("thunder: Ctrl+.: switched off ([thunder] enabled = false)"); return end
    D.forceSpecial = "thunder"
    local soon = D.state == "wait"
    if soon then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
    hudCallout(string.format(c.text.key, c.tag), soon and c.text.key_now or c.text.key_next)
    log(string.format("thunder: Ctrl+., round %d is %s / %s (%s)", D.round + 1, c.tag, c.name, soon and "starting in 3 s" or "after this round"))
end)
end
-- TEST ONLY END
