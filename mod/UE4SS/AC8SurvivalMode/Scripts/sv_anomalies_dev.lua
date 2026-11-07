-- sv_anomalies_dev.lua: the specials' code for test builds only: the whole piece is one test-only block, which
-- tools/strip_test_only.py takes out of a release (only this header is left there). Piece 3 of 3 of sv_anomalies.lua
-- (sv_anomalies.lua, sv_anomalies_valka.lua, sv_anomalies_dev.lua), split by tools/lua_split_part.py and run by
-- main.lua right after the piece before it: a name another part uses is a global of this mod's Lua state, its own
-- helpers stay local.

-- TEST ONLY BEGIN (the lightning Anomaly and the storm test: test builds only; tools/strip_test_only.py takes all of it
-- out of a release with CFG.specials.thunder; tools/re/THUNDER.md)
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
local function fxAt(at)
    local f = cfg().fx
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys, why = SPC.V.asset(f.system)
    if not (lib and valid(lib) and sys and liveObj(survivalPC) and at) then
        say("fx", "thunder: its cloud lightning didn't spawn: " .. tostring(sys and "no Niagara library or player controller" or why))
        return false
    end
    local sc = tonumber(f.scale) or 1
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
        end
        return
    end
    parkTick()
    fxTick(now, false)
    testTick(now)
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
