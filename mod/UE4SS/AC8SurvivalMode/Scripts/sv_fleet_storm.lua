-- sv_fleet_storm.lua: INVINCIBLE FLEET's night and its storm (round 30, the user's dev install only), sv_fleet.lua's next
-- piece (2026-11-17: sv_fleet.lua was at the 2,000-line limit). Part of AC8 Survival Mode's runtime, run by main.lua in
-- MODULES' order right after sv_fleet: a name another part uses is a global of this mod's Lua state, its own helpers stay
-- local (this piece shares none of sv_fleet.lua's locals: IFSKY is its own, the other parts' tables are globals read at run
-- time). The whole piece is one test-only block, which tools/strip_test_only.py takes out of every release and test zip,
-- and tools/dev_only.py out of a TESTER zip, only this header left there.
--   Ctrl+S in a run   the fleet's night storm now (IFSKY.step(3): the moon up, the storm under its fade); again: the
--                     round's own sky back under the storm's fade (IFSKY.leaving: run 72 saw the day a second before it).
--   Ctrl+J in a run   the storm's sound candidates, one a press in turn (near, then far), so the user can pick by ear.
-- TEST ONLY BEGIN (INVINCIBLE FLEET's night storm: test builds only, the user's dev install)
-- ---- INVINCIBLE FLEET's night and its storm (2026-11-16; CFG.specials.fleet.sky's note) -----------------------------
-- The arc: SKY.arcOwners.fleet (sv_sky.lua: the latest start owns it; GONE FISHIN''s F and THE FESTIVAL untouched). The
-- storm: on at the arc's first moon, off at storm.until_round, each time under a fade to black. Every game its own (the
-- round and its clock are the host's on every game). IFSKY.step(k): the arc at step k from the round now (a test's).
-- Log: `fleet storm: ...`.
IFSKY = { k = nil }
do
local SW = { on = false }
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function sc() return (CFG.specials and CFG.specials.fleet or {}).sky or {} end
local function stc() return sc().storm or {} end
local function pick(t, d) t = type(t) == "table" and t or d; return n(t[1], d[1]) + (n(t[2], d[2]) - n(t[1], d[1])) * math.random() end
if SKY and SKY.arcOwners then
    SKY.arcOwners.fleet = function()
        local c = sc()
        if c.enabled == false or not D then return nil end
        SKY.arcProfiles.fleet = c.profile
        local r = math.floor(n(D.round, 0))
        if IFSKY.k then return r - IFSKY.k end
        local F = math.floor(n(c.from_round, 25))
        if r >= F then return F end
        return nil
    end
end
function IFSKY.step(k)
    IFSKY.k = tonumber(k)
    if ARC and ARC.last then                              -- (blended in from the sky written last)
        local b = {}
        for a, v in pairs(ARC.last) do b[a] = v end
        ARC.blendFrom, ARC.blendAt = b, nil
    end
    log(string.format("fleet storm: the arc at step %s now (a test's)", tostring(k)))
end
testKey("S", "sv_fleet.lua's night storm now", function()                     -- (the header's Ctrl+S)
    if not (D and D.now and RUN) then log("fleet storm: Ctrl+S outside a Survival run"); return end
    local on = IFSKY.k == nil or IFSKY.leaving
    IFSKY.leaving = (not on and SW.on) or nil              -- (off: the day back under the storm's fade, in trTick)
    if on or not SW.on then IFSKY.step(on and 3 or nil) end
    hudCallout("TEST: NIGHT STORM", on and "THE FLEET'S NIGHT, ITS STORM COMING" or "THE ROUND'S OWN SKY BACK")
end)
-- the thunder (stc().thunder, sv_fleet.lua's note): AC8's booms and rumble, loaded and pinned (as the Anomaly's sounds),
-- one queued after a strike's distance and played at your camera with Wwise's PostEventAtLocation on the event itself
-- (the way Survival's heard sounds go: sv_escort_laser.lua, sv_fleet.lua's GEOFON; 0.74.92-0.74.93 posted them by name,
-- LiveSoundBlueprintLibrary.PostEventByName, and the user heard none, run 77); Ctrl+J plays each in turn.
-- ((2026-11-17) the user: "we need to change the audio of the Thunder, its wrong") AC8's own thunder: its SE bank
-- (AKB_GameSe, DA_SoundDB_AKB_GameSe) has Mission 12's thunder events with no event asset of their own (so loading them
-- found nothing); a bare name (no "/") is posted by name ON your camera (LiveSoundBlueprintLibrary.PostEventAtActorByName on
-- the PlayerCameraManager: these are 3D sounds, and the 0.74.92 posts by name had no place, so played at the world's
-- origin, out of earshot), logged with its playing id (0: Wwise didn't know it)
local TH = { q = {}, got = {}, ev = {} }
local function thName(path) return path:match("([^/]+)$") end
local function thBank(name) return type(name) == "string" and name ~= "" and not name:find("/", 1, true) end
local function idOf(r)
    if type(r) == "number" then return r end
    for _, f in ipairs({ "PlayingID", "PlayingId", "ID", "Id", "Value" }) do
        local ok, v = pcall(function() return r[f] end)
        if ok and type(v) == "number" then return v end
    end
    return tostring(r)
end
-- ((2026-11-17) the user: "is it possible to spawn the thunder sound at the lightning's point? it sounds way to close when
-- its attached to the aircraft") a strike's thunder on a marker of ours (a TargetPoint, a pool of 4) toward the strike, at
-- its distance but no further than thunder.at_max_m (AC8's thunder is 3D: out of its reach a far strike would be silent)
local MARK = { pool = {}, i = 0 }
local function markAt(at)
    local L
    pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
    if not (L and type(at) == "table") then return nil end
    local dx, dy, dz = at.X - L.X, at.Y - L.Y, (at.Z or L.Z) - L.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < 1 then return nil end
    local k = math.min(d, n((stc().thunder or {}).at_max_m, 2500) * 100) / d
    local spot = { X = L.X + dx * k, Y = L.Y + dy * k, Z = L.Z + dz * k }
    MARK.i = MARK.i % 4 + 1
    local e = MARK.pool[MARK.i]
    if not (e and e.a ~= nil and liveAddr(e.o) == e.a and nameOf(e.o) == e.name) then
        local gs, cls = StaticFindObject("/Script/Engine.Default__GameplayStatics"), StaticFindObject("/Script/Engine.TargetPoint")
        if not (valid(gs) and valid(cls) and liveObj(survivalPC)) then return nil end
        local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = spot, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)
        if not (okB and x and valid(x)) then return nil end
        pcall(function() gs:FinishSpawningActor(x, t, 1) end)
        e = { o = x, a = liveAddr(x), name = nameOf(x) }
        MARK.pool[MARK.i] = e
    end
    pcall(function() e.o:K2_SetActorLocation(spot, false, {}, true) end)
    return e.o, k * d
end
local function thPost(name, at)                            -- (a bank event by name at the strike's marker, else your camera)
    local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
    local where, how, m = nil, "on your camera", nil
    if at then where, m = markAt(at) end
    if where then how = string.format("%.1f km toward the strike", (m or 0) / 100000) end
    if not where then pcall(function() where = survivalPC.PlayerCameraManager end) end
    if not (valid(lib) and where and valid(where)) then return "NOT posted (no sound library or camera)" end
    local ok, r = pcall(function() return lib:PostEventAtActorByName(FName(name), where) end)
    if not ok then return "NOT posted (" .. tostring(r):sub(1, 100) .. ")" end
    return "posted " .. how .. " (playing id " .. tostring(idOf(r)) .. ")"
end
local function thLoad(c)
    local k = 0
    for _, list in ipairs({ c.near or {}, c.far or {} }) do
        for _, path in ipairs(list) do
            local name = thName(path)
            if thBank(path) then TH.got[name] = true end   -- (a bank event: nothing to load)
            if not TH.got[name] then
                local o = loadObject(path .. "." .. name)
                if o then pin(o, name); TH.got[name], TH.ev[name] = true, o end
            end
            if TH.got[name] then k = k + 1 end
        end
    end
    return k
end
local function thQueue(at, now, sure)                     -- (sure: always, a cued strike's)
    local c = stc().thunder or {}
    if c.enabled == false or (not sure and math.random() > n(c.chance, 0.7)) then return "" end
    local L
    pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
    local km = L and math.sqrt((L.X - at.X) ^ 2 + (L.Y - at.Y) ^ 2 + (L.Z - at.Z) ^ 2) / 100000 or 10
    local list = km <= n(c.near_km, 6) and c.near or c.far
    if type(list) ~= "table" or #list == 0 then return "" end
    local name = thName(list[math.random(#list)])
    local d = math.min(n(c.max_s, 6), km * n(c.s_per_km, 2.9))
    TH.q[#TH.q + 1] = { at = now + d, name = name, pos = { X = at.X, Y = at.Y, Z = at.Z } }
    return string.format("; thunder %s in %.1f s (%.1f km)", name, d, km)
end
local function thPlay(name, pos)                           -- (two signatures tried, the first that works kept)
    if thBank(name) and not TH.ev[name] then return thPost(name, pos) end
    local ev, ak = name and TH.ev[name], StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
    if not ev then return "NOT played (" .. tostring(name) .. " not loaded)" end
    local L
    pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
    if not (L and valid(ak) and liveObj(survivalPC)) then return "NOT played (no camera, Wwise or player controller)" end
    local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
    local tries = { function() return ak:PostEventAtLocation(ev, L, rot, survivalPC) end,
                    function() return ak:PostEventAtLocation(ev, L, rot, "", survivalPC) end }
    local errs = {}
    for i = (TH.way or 1), (TH.way or #tries) do
        local ok, err = pcall(tries[i])
        if ok then TH.way = i; return "played" end
        errs[#errs + 1] = tostring(err)
    end
    return "NOT played (" .. table.concat(errs, "; "):sub(1, 120) .. ")"
end
local function thTick(now)
    for i = #TH.q, 1, -1 do
        if now >= TH.q[i].at then
            local r = thPlay(TH.q[i].name, TH.q[i].pos)
            TH.n = (TH.n or 0) + 1
            if TH.n <= 3 or not (r == "played" or tostring(r):find("^posted")) then log(string.format("fleet storm: thunder %d: %s %s", TH.n, TH.q[i].name, tostring(r))) end
            table.remove(TH.q, i)
        end
    end
end
testKey("J", "sv_fleet_storm.lua's thunder sounds", function()                -- (the header's Ctrl+J)
    if not (D and D.now and RUN) then log("fleet storm: Ctrl+J outside a Survival run"); return end
    local c, all = stc().thunder or {}, {}
    for _, l in ipairs({ c.near or {}, c.far or {} }) do for _, p in ipairs(l) do all[#all + 1] = p end end
    if #all == 0 then return end
    local loaded = thLoad(c)
    TH.k = (TH.k or 0) % #all + 1
    local name = thName(all[TH.k])
    local r = thPlay(name)
    hudCallout(string.format("TEST: THUNDER %d/%d", TH.k, #all), name:upper())
    log(string.format("fleet storm: Ctrl+J thunder %d of %d (%s): %s (%s; %d of %d loaded)", TH.k, #all,
        TH.k <= #(c.near or {}) and "near" or "far", name, tostring(r), loaded, #all))
end)
-- the storm's cloud lightning (stc().cells, sv_fleet.lua's note): Mission 12's NS_CloudLightning at its 19 spots, each
-- spawned inactive, drawn after the clouds (its translucency sort priority, as Mission 12's), then activated; each kept
-- with its address and name (hard rule 59) and taken off as the storm clears. Log: `fleet storm: cloud lightning: ...`.
local CELLS = {}
local function cellOk(e) return e ~= nil and e.a ~= nil and liveAddr(e.o) == e.a and nameOf(e.o) == e.name end
local function cellsOn(c)
    if #CELLS > 0 or type(c) ~= "table" or c.enabled == false then return #CELLS, "" end
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = type(c.system) == "string" and loadObject(c.system) or nil
    if not (lib and valid(lib) and sys and liveObj(survivalPC)) then return 0, " (no Niagara, system or player controller)" end
    local pri, set = math.floor(n(c.sort, 100)), 0
    for _, s in ipairs(c.spots or {}) do
        local sc = n(s[4], 1) * n(c.scale_x, 1)
        local ok, comp = pcall(function() return lib:SpawnSystemAtLocation(survivalPC, sys, { X = s[1], Y = s[2], Z = s[3] },
            { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc }, false, false, 0, false) end)
        if ok and comp then
            local okA = pcall(function() comp.bOverrideSeparateTranslucencySortPriority = true end)
            local okB = pcall(function() comp.SeparateTranslucencySortPriority = pri end)
            local okC = pcall(function() comp:SetTranslucentSortPriority(pri) end)
            if okA and okB and okC then set = set + 1 end
            pcall(function() comp:Activate(true) end)
            CELLS[#CELLS + 1] = { o = comp, a = liveAddr(comp), name = nameOf(comp) }
        end
    end
    return #CELLS, string.format(" (%d of them drawn after the clouds, sort %d)", set, pri)
end
-- a glow in the cloud over each bolt (cells.bolt_glow): a pool of the cells' glow, spawned inactive and drawn after the clouds
-- as they are, the oldest moved over the new bolt's top and restarted, off life_s on
local GLOW = { pool = {}, i = 0 }
-- ((2026-11-17) tools/stormfx) our own flash, NS_SV_CloudFlash (bolt_glow.flash: a burst at each Activate / ResetSystem,
-- so it flashes WITH the bolt; the stock NS_CloudLightning's spawn-rate loops flash at a random moment) when its container
-- is installed (TANI=1 dev builds), else the stock glow as before; looked for once a level (GLOW.flash: false = not there)
-- g.flash: candidates { path, scale, life_s } in order (AC8's own patched NS_SV_CloudBurst, tools/stormfx/burst.py; our
-- NS_SV_CloudFlash), the first that loads; GLOW.fe its entry
local function flashSys(g)
    -- ((0.74.139) the user's crash of 0.74.138: a kept asset whose address the game gave to another object (the storm's layout
    -- became a LiveSetPauseTimerExecution); each use checks it's still the one found, by its name (hard rule 59))
    if GLOW.flash and not (liveObj(GLOW.flash) and nameOf(GLOW.flash) == GLOW.flashN) then GLOW.flash = nil end
    if GLOW.flash == nil then
        GLOW.flash, GLOW.fe = false, nil
        local tried = {}
        for _, e in ipairs(type(g.flash) == "table" and g.flash or {}) do
            local o = type(e.path) == "string" and loadObject(e.path) or nil
            if o then GLOW.flash, GLOW.fe, GLOW.flashN = o, e, nameOf(o); break end
            tried[#tried + 1] = tostring(e.path)
        end
        log("fleet storm: the bolts' cloud flash: " .. (GLOW.fe and ("our own " .. GLOW.fe.path) or
            ("the stock glow (" .. (#tried > 0 and table.concat(tried, ", ") or "none set") .. " not in this build)")))
    end
    return GLOW.flash or nil
end
local function glowNew(c, at)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local g = c.bolt_glow or {}
    local own = flashSys(g)
    local sys = own or (type(c.system) == "string" and loadObject(c.system) or nil)
    if not (lib and valid(lib) and sys and liveObj(survivalPC)) then return nil end
    local pri, sc = math.floor(n(c.sort, 100)), own and n(GLOW.fe and GLOW.fe.scale, 1) or n(g.scale, 1)
    local ok, comp = pcall(function() return lib:SpawnSystemAtLocation(survivalPC, sys, at, { Pitch = 0, Yaw = 0, Roll = 0 },
        { X = sc, Y = sc, Z = sc }, false, false, 0, false) end)
    if not (ok and comp) then return nil end
    pcall(function() comp.bOverrideSeparateTranslucencySortPriority = true end)
    pcall(function() comp.SeparateTranslucencySortPriority = pri end)
    pcall(function() comp:SetTranslucentSortPriority(pri) end)
    return { o = comp, a = liveAddr(comp), name = nameOf(comp) }
end
local function glowAt(top, now)
    local c = stc().cells or {}
    local g = c.bolt_glow
    if type(top) ~= "table" or type(g) ~= "table" or g.enabled == false or c.enabled == false then return "" end
    local at = { X = top.X, Y = top.Y, Z = top.Z + n(g.up_m, 300) * 100 }
    -- ((2026-11-17) run 20261117_140748: AC8's flash (emissive 5000, made for Mission 12's far cells) whited the sky out
    -- within a few km of the camera: none nearer than the flash's min_km)
    flashSys(g)
    local mk = GLOW.fe and n(GLOW.fe.min_km, 0) or 0
    if mk > 0 then
        local L
        pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
        if L and math.sqrt((L.X - at.X) ^ 2 + (L.Y - at.Y) ^ 2 + (L.Z - at.Z) ^ 2) < mk * 100000 then
            return string.format("; no glow (within %.0f km of you)", mk)
        end
    end
    GLOW.i = GLOW.i % math.max(1, math.floor(n(g.pool, 12))) + 1
    local e = GLOW.pool[GLOW.i]
    -- ((0.74.116) our flashes: a fresh system each time (burstwatch of 0.74.115: AC8's burst reset and switched on again
    -- stayed dark after its first flash), the slot's old one taken off)
    if GLOW.flash and cellOk(e) then pcall(function() e.o:DestroyComponent() end); e = nil end
    if not cellOk(e) then e = glowNew(c, at); GLOW.pool[GLOW.i] = e end
    if not e then return "; no glow" end
    pcall(function() e.o:SetWorldLocation(at, false, {}, true) end)
    pcall(function() e.o:ResetSystem() end)
    pcall(function() e.o:Activate(true) end)
    e.offAt = now + n(GLOW.fe and GLOW.flash and GLOW.fe.life_s or g.life_s, 1.5)   -- (the burst: switched off at once, its particles finish)
    return string.format("; a glow %.1f km up", at.Z / 100000)
end
local function glowTick(now)
    for _, e in ipairs(GLOW.pool) do
        if e and e.offAt and now >= e.offAt then
            e.offAt = nil
            if cellOk(e) then pcall(function() if GLOW.flash then e.o:DestroyComponent() else e.o:Deactivate() end end) end
        end
    end
end
local function glowOff()
    for _, e in pairs(GLOW.pool) do if cellOk(e) then pcall(function() e.o:DestroyComponent() end) end end
    GLOW.pool, GLOW.i = {}, 0
end
local function cellsOff()
    glowOff()
    if IFSKY.slOff then pcall(IFSKY.slOff) end                -- (the strike light: defined further down)
    local k = 0
    for _, e in ipairs(CELLS) do
        if cellOk(e) then pcall(function() e.o:DestroyComponent() end); k = k + 1 end
    end
    CELLS = {}
    return k
end
local function wanted()
    local c = stc()
    if IFSKY.leaving or c.enabled == false or not (THUNDER and THUNDER.layoutSet and THUNDER.camFade) then return false end
    local a = SKY and SKY.arcState and SKY.arcState()
    if not (a and a.on and a.profile == "fleet" and a.k) then return false end
    if n(a.kRaw, a.k) >= math.floor(n(c.until_round, 35)) - math.floor(n(sc().from_round, 25)) then return false end   -- (the uncapped step: midday's hold caps a.k)
    return a.mode == "moon" or a.k >= n(a.sink, 0) + 2
end
local function fade(on, why)
    local c = stc()
    local ok, err = THUNDER.camFade(0, 1, n(c.out_s, 0.6), true)
    SW.tr = { on = on, why = why, phase = "out", at = os.clock() + (ok and n(c.out_s, 0.6) or 0), faded = ok }
    if not ok then log("fleet storm: no fade (" .. tostring(err) .. "): the clouds swapped at once") end
end
local WARM = {}
local function warmUp()                                     -- (the bolts 400 m ahead and the rain on your camera, for the hold)
    local L = stc().lightning or {}
    local nb = (THUNDER.boltWarm and L.bolts and L.bolts.enabled ~= false) and select(2, pcall(THUNDER.boltWarm, L.bolts)) or 0
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local pcm, at
    pcall(function() pcm = survivalPC.PlayerCameraManager; local v = pcm:GetCameraLocation(); at = { X = v.X, Y = v.Y, Z = v.Z } end)
    WARM.fx = {}
    for _, path in ipairs(L.warm_fx or {}) do
        local sys = loadObject(path)
        local ok, comp = false, nil
        if sys and lib and at then
            ok, comp = pcall(function() return lib:SpawnSystemAtLocation(survivalPC, sys, at, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = 1, Y = 1, Z = 1 }, true, true, 0, false) end)
        end
        if ok and comp then WARM.fx[#WARM.fx + 1] = comp end
    end
    local okC, cw = false, nil
    if THUNDER.cloudReady and L.cloud and L.cloud.enabled ~= false then okC, cw = pcall(THUNDER.cloudReady, L.cloud) end
    local th = stc().thunder or {}
    local okT, nt = pcall(thLoad, th)
    log(string.format("fleet storm: warm-up under the black: %s bolts, %d of %d effects, %s, thunder %s of %d loaded", tostring(nb),
        #WARM.fx, #(L.warm_fx or {}), (okC and cw) and "its cloud light" or "NO cloud light (" .. tostring(cw) .. ")",
        okT and tostring(nt) or "?", #(th.near or {}) + #(th.far or {})))
end
local function warmOff()
    if THUNDER.boltHide then pcall(THUNDER.boltHide) end
    for _, comp in ipairs(WARM.fx or {}) do pcall(function() comp:DestroyComponent() end) end
    WARM.fx = {}
end
local function trTick(now)
    local t = SW.tr
    if not t or now < t.at then return end
    local c = stc()
    local snd = c.sound or {}
    if t.phase == "out" then
        if t.on then warmUp() elseif THUNDER.cloudOff then pcall(THUNDER.cloudOff) end   -- (under the black)
        if t.on then
            local okC, k, why = pcall(cellsOn, stc().cells)
            log(string.format("fleet storm: cloud lightning: %s of %d up%s", okC and tostring(k) or ("error " .. tostring(k)),
                #((stc().cells or {}).spots or {}), okC and why or ""))
        else
            local okC, k = pcall(cellsOff)
            log("fleet storm: cloud lightning: " .. (okC and tostring(k) or "?") .. " taken off")
        end
        if not t.on and IFSKY.leaving then IFSKY.leaving = nil; IFSKY.step(nil) end   -- (Ctrl+S's day, unseen)
        local okL, what = pcall(THUNDER.layoutSet, t.on, t.on and "INVINCIBLE FLEET's night storm" or "INVINCIBLE FLEET's storm clearing")
        local amb = t.on and snd.distant or snd.distant_stop   -- ((2026-11-17) Mission 12's distant thunder, on your camera)
        if thBank(amb) then log("fleet storm: " .. amb .. ": " .. thPost(amb)) else pcall(THUNDER.post, amb) end
        if t.on and snd.clap then pcall(thPlay, snd.clap) end
        t.phase, t.at, t.what = "hold", now + n(c.hold_s, 0.8), okL and what or ("error " .. tostring(what))
    elseif t.phase == "hold" then
        warmOff()
        if t.faded then pcall(THUNDER.camFade, 1, 0, n(c.in_s, 1.2), false) end
        t.phase, t.at = "in", now + n(c.in_s, 1.2)
        local a = SKY.arcState()
        log(string.format("fleet storm: %s (round %s, the arc's step %s, %s): %s%s", t.on and "in" or "cleared", tostring(D and D.round),
            tostring(a.k), tostring(a.mode), tostring(t.what), t.faded and ", under a fade to black" or ""))
    else
        SW.tr = nil
    end
end
local function centres()                                   -- (the airfield, and the fleet's flagship when it's up)
    local out = {}
    if type(AIRFIELD) == "table" and AIRFIELD.X then out[#out + 1] = { X = AIRFIELD.X, Y = AIRFIELD.Y, Z = AIRFIELD.Z or 0 } end
    local F = IFLEET and IFLEET.cur
    for _, sh in ipairs(F and F.ships or {}) do
        local o = sh.hull and sh.hull.obj
        if o and liveObj(o) then
            local ok, l = pcall(function() return o:K2_GetActorLocation() end)
            if ok and l then out[#out + 1] = { X = l.X, Y = l.Y, Z = l.Z }; break end
        end
    end
    if #out < 2 and IFCOOP and IFCOOP.flagAt then         -- ((0.74.160) a joiner: its copy of the host's flagship)
        local okJ, l = pcall(IFCOOP.flagAt)
        if okJ and l then out[#out + 1] = l end
    end
    return out
end
-- a flash at `at` (its cloud flash, a bolt under it, the bolt's glow and its thunder): what it showed. sure: the thunder
-- always (a cued strike's); inView: the bolt out in your camera's shot (THUNDER.bolt's)
-- ((2026-11-17) the user: "why does the plane not light up from the lightning burst effects?") AC8's lightning only glows
-- (emissive sprites and meshes: no light leaves them), and Cloudly's clouds take only its cloud light. A strike's light on
-- everything else: a directional light of ours (shadowless, movable, never the atmosphere's sun: Cloudly drives the level's
-- own sun every frame, hard rule 56), turned from the strike toward your camera and flickered a tick at a time
-- (lightning.plane_light: intensity x steps, strikes within max_km; at most one at a time, the nearest wins)
local SL = { a = nil }
local function slOk() return SL.a ~= nil and SL.aa ~= nil and liveAddr(SL.a) == SL.aa and nameOf(SL.a) == SL.an end
-- ((0.74.121) kind "point": a second directional light lit nothing at any intensity (the ladder 20-2000 of run
-- 20261117_150341: AC8 draws with its one sun): a point light offset_m from your camera toward the strike, kept there each tick,
-- its reach radius_m, unitless (no inverse-square falloff))
local function slKind() return (((stc().lightning or {}).plane_light) or {}).kind or "point" end
local function slMake()
    if slOk() then return SL.a end
    local point = slKind() == "point"
    local gs, cls = StaticFindObject("/Script/Engine.Default__GameplayStatics"),
        StaticFindObject(point and "/Script/Engine.PointLight" or "/Script/Engine.DirectionalLight")
    if not (valid(gs) and valid(cls) and liveObj(survivalPC)) then return nil, "no GameplayStatics / DirectionalLight" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local okB, x = pcall(function() return gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1) end)
    if not (okB and x and valid(x)) then return nil, "its spawn failed" end
    local l
    pcall(function() l = x.LightComponent end)
    if l then
        pcall(function() l:SetMobility(2) end)                    -- (Movable: lit at run time)
        if not point then
            pcall(function() l.bAtmosphereSunLight = false end)   -- (never the sky's sun)
            pcall(function() l.AtmosphereSunLightIndex = 1 end)
        else
            local c = (stc().lightning or {}).plane_light or {}
            pcall(function() l.bUseInverseSquaredFalloff = false end)
            pcall(function() l:SetAttenuationRadius(n(c.radius_m, 1500) * 100) end)
            pcall(function() l.LightFalloffExponent = n(c.falloff, 2) end)
        end
        pcall(function() l:SetCastShadows(false) end)
        pcall(function() l:SetIntensity(0) end)
    end
    pcall(function() gs:FinishSpawningActor(x, t, 1) end)
    SL.a, SL.aa, SL.an, SL.l = x, liveAddr(x), nameOf(x), l
    return x
end
local slTick                                               -- (below; slFlash runs its first step)
local function slFlash(at, now)
    local c = (stc().lightning or {}).plane_light
    if type(c) ~= "table" or c.enabled == false or type(at) ~= "table" then return "" end
    local L
    pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
    if not L then return "" end
    local dx, dy, dz = L.X - at.X, L.Y - at.Y, L.Z - (at.Z or 300000)
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d > n(c.max_km, 15) * 100000 then return "" end
    if SL.steps and SL.d and d > SL.d then return "" end           -- (one at a time: a nearer one wins)
    if not SL.steps and now < (SL.next or 0) then return "" end    -- ((0.74.126) one every gap_s at most)
    SL.next = now + n(c.gap_s, 0)
    local a, why = slMake()
    if not a then return "; no strike light (" .. tostring(why) .. ")" end
    local yaw, pitch = math.deg(math.atan(dy, dx)), math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
    pcall(function() a:K2_SetActorRotation({ Pitch = pitch, Yaw = yaw, Roll = 0 }, false) end)
    SL.dir = { X = -dx / d, Y = -dy / d, Z = -dz / d }               -- (toward the strike, for the point light's spot)
    SL.off = n(c.offset_m, 300) * 100
    local k = type(c.color) == "table" and c.color or { 200, 215, 255 }
    pcall(function() SL.l:SetLightColor({ R = k[1] / 255, G = k[2] / 255, B = k[3] / 255, A = 1 }, false) end)
    -- (nearer, brighter: full at near_km, falling to fade_x at max_km)
    local f = math.max(0, math.min(1, (d / 100000 - n(c.near_km, 3)) / math.max(0.1, n(c.max_km, 15) - n(c.near_km, 3))))
    SL.b, SL.d = n(c.intensity, 6) * (1 - f * (1 - n(c.fade_x, 0.25))), d
    SL.steps, SL.i = c.steps or { 1, 0.25, 0.8, 0.3, 0 }, 0
    SL.n = (SL.n or 0) + 1
    slTick()                                                     -- (its first step now, with the bolt: not a tick late)
    if SL.n <= 3 then log(string.format("fleet storm: strike light %d: %.1f km off, intensity %.2f, from yaw %.0f pitch %.0f", SL.n, d / 100000, SL.b, yaw, pitch)) end
    return string.format("; its light %.2f (%.1f km)", SL.b, d / 100000)
end
slTick = function()
    if not SL.steps then return end
    SL.i = SL.i + 1
    local k = SL.steps[SL.i]
    if k == nil then SL.steps, SL.d, k = nil, nil, 0 end
    if SL.dir and slOk() and slKind() == "point" then          -- (kept beside your camera, on the strike's side)
        local L
        pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
        if L then
            local o = SL.off or 30000
            pcall(function() SL.a:K2_SetActorLocation({ X = L.X + SL.dir.X * o, Y = L.Y + SL.dir.Y * o, Z = L.Z + SL.dir.Z * o }, false, {}, true) end)
        end
    end
    if slOk() and SL.l then pcall(function() SL.l:SetIntensity(k * (SL.b or 0)) end) else SL.steps = nil end
end
local function slOff()
    if slOk() then pcall(function() SL.a:K2_DestroyActor() end) end
    SL = { a = nil }
end
IFSKY.slOff = slOff
local function strike(at, now, why, sure, inView)
    local c = stc().lightning or {}
    local how, cl = "bolt", c.cloud                          -- (a cloud flash at some: Survival's own light, hard rule 70)
    if type(cl) == "table" and cl.enabled ~= false and now >= (SW.lightAt or 0) and math.random() < (tonumber(cl.chance) or 0.5) then
        how, SW.lightAt, at.Z = "effect", now + pick(cl.every_s, { 0.6, 1.6 }), pick(cl.alt_m, { 2000, 4500 }) * 100
    end
    local ok, what = false, "no THUNDER"
    if THUNDER and THUNDER.cloudFlash then ok, what = pcall(THUNDER.cloudFlash, at, how, why, cl) end
    if THUNDER and THUNDER.bolt and c.bolts then
        local okB, seen, whyB, top = pcall(THUNDER.bolt, { X = at.X, Y = at.Y, Z = 0 }, c.bolts, why, inView)
        what = tostring(what) .. "; " .. (okB and (seen or ("no bolt: " .. tostring(whyB))) or ("bolt error " .. tostring(seen)))
        if okB and seen then
            local okG, gw = pcall(glowAt, top, now)
            what = what .. (okG and gw or ("; glow error " .. tostring(gw)))
        end
    end
    local okL, lw = pcall(slFlash, at, now)
    what = tostring(what) .. (okL and lw or ("; strike light error " .. tostring(lw)))
    local okT, th = pcall(thQueue, at, now, sure)
    return ok, tostring(what) .. (okT and th or ("; thunder error " .. tostring(th)))
end
-- ((2026-11-17) the epic surfacing, sv_fleet_surface.lua) a strike on its cue at `at` (X, Y: the bolt's foot; Z: the
-- flash's height, 3 km if none), its thunder sure; and a sound of the SE bank by name on your camera
function IFSKY.strike(at, why)
    if type(at) ~= "table" or not (at.X and at.Y) then return false, "no spot" end
    return strike({ X = at.X, Y = at.Y, Z = at.Z or 300000 }, os.clock(), why or "a cue", true, false)
end
function IFSKY.post(name) return thPost(name) end
local function lightTick(now)
    local c = stc().lightning or {}
    if c.enabled == false or now < (SW.nextAt or 0) then return end
    -- (while the surfacing films, its own strikes on cue: the storm's x IFSURF.quiet() further apart, so the cued ones read)
    local q = IFSURF and IFSURF.quiet and tonumber(IFSURF.quiet()) or 1
    SW.nextAt = now + pick(c.every_s, { 0.3, 0.8 }) * math.max(1, q)
    local cs = centres()
    if #cs == 0 then return end
    local ce = cs[math.random(#cs)]
    local d = pick(c.dist_km, { 2, 25 }) * 100000
    local ang = math.random() * 2 * math.pi
    local at = { X = ce.X + math.cos(ang) * d, Y = ce.Y + math.sin(ang) * d, Z = pick(c.alt_m, { 1500, 7000 }) * 100 }
    SW.n = (SW.n or 0) + 1
    local ok, what = strike(at, now, "the fleet's storm", false,
        IFSURF and IFSURF.state and IFSURF.state() and true)   -- (while the surfacing films: in its shot)
    if SW.n <= 3 or SW.n % 100 == 0 then
        log(string.format("fleet storm: flash %d (%.0f km off its centre, %.1f km up): %s", SW.n, d / 100000, at.Z / 100000,
            ok and tostring(what) or ("error " .. tostring(what))))
    end
end
function IFSKY.storm() return { on = SW.on, flashes = SW.n or 0, tr = SW.tr and SW.tr.phase or nil } end
TEST_TICKS[#TEST_TICKS + 1] = { name = "fleet storm", fn = function(now)
    if not D or (levelTorn and levelTorn()) then
        if SW.on and THUNDER and THUNDER.layoutSet then pcall(THUNDER.layoutSet, false, "INVINCIBLE FLEET's storm: the run's over") end
        SW.on, SW.tr = false, nil
        return
    end
    trTick(now)
    pcall(thTick, now)
    pcall(glowTick, now)
    pcall(slTick)
    if THUNDER and THUNDER.cloudTick then pcall(THUNDER.cloudTick, now) end
    local w = wanted()
    if w ~= SW.on and not SW.tr then
        SW.on = w
        fade(w, w and "the night sky's come" or "the storm clears")
    end
    if SW.on and not SW.tr then lightTick(now) end
end }
if type(LEVEL_DROPS) == "table" then                       -- (the level's: its Cloudly actor and lights went with it)
    LEVEL_DROPS["fleet storm"] = function() SW = { on = false }; IFSKY.k, IFSKY.leaving, TH.q, TH.got, TH.ev, CELLS = nil, nil, {}, {}, {}, {}; GLOW.pool, GLOW.i, GLOW.flash, GLOW.fe = {}, 0, nil, nil; SL = { a = nil }; MARK = { pool = {}, i = 0 } end
end
if type(RESTART_PUTBACK) == "table" then                   -- ((0.74.129) a restart keeps the level: its Cloudly actor's
    RESTART_PUTBACK["fleet storm"] = function()             -- layout back, our strike light off, before the drop above
        if SW.on and THUNDER and THUNDER.layoutSet then pcall(THUNDER.layoutSet, false, "INVINCIBLE FLEET's storm: the mission restarted") end
        slOff()
    end
end
if type(RESTART_DROPS) == "table" then                     -- ((0.74.129) the parts whose objects a mission's reload takes:
    for _, name in ipairs({ "fleet", "fleet ships", "fleet lasers", "fleet round", "fleet storm", "fleet surfacing", "thunder",   -- the
                            "tanicorn armour", "tanicorn live", "tanicorn hits", "tanicorn rail", "tanicorn rise fx", "cine" }) do   -- old ships
        RESTART_DROPS[name] = true                         -- paid as sunk, then the crash of 15:56:28; sv_core.lua levelRestartDrop)
    end
end
end
-- TEST ONLY END
