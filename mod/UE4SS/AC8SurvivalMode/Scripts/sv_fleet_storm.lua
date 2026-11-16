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
-- LiveSoundBlueprintLibrary.PostEventByName, and the user heard none, run 77); Ctrl+J plays each in turn
local TH = { q = {}, got = {}, ev = {} }
local function thName(path) return path:match("([^/]+)$") end
local function thLoad(c)
    local k = 0
    for _, list in ipairs({ c.near or {}, c.far or {} }) do
        for _, path in ipairs(list) do
            local name = thName(path)
            if not TH.got[name] then
                local o = loadObject(path .. "." .. name)
                if o then pin(o, name); TH.got[name], TH.ev[name] = true, o end
            end
            if TH.got[name] then k = k + 1 end
        end
    end
    return k
end
local function thQueue(at, now)
    local c = stc().thunder or {}
    if c.enabled == false or math.random() > n(c.chance, 0.7) then return "" end
    local L
    pcall(function() local v = survivalPC.PlayerCameraManager:GetCameraLocation(); L = { X = v.X, Y = v.Y, Z = v.Z } end)
    local km = L and math.sqrt((L.X - at.X) ^ 2 + (L.Y - at.Y) ^ 2 + (L.Z - at.Z) ^ 2) / 100000 or 10
    local list = km <= n(c.near_km, 6) and c.near or c.far
    if type(list) ~= "table" or #list == 0 then return "" end
    local name = thName(list[math.random(#list)])
    local d = math.min(n(c.max_s, 6), km * n(c.s_per_km, 2.9))
    TH.q[#TH.q + 1] = { at = now + d, name = name }
    return string.format("; thunder %s in %.1f s (%.1f km)", name, d, km)
end
local function thPlay(name)                                -- (two signatures tried, the first that works kept)
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
            local r = thPlay(TH.q[i].name)
            TH.n = (TH.n or 0) + 1
            if TH.n <= 3 or r ~= "played" then log(string.format("fleet storm: thunder %d: %s %s", TH.n, TH.q[i].name, tostring(r))) end
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
local function cellsOff()
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
        pcall(THUNDER.post, t.on and snd.distant or snd.distant_stop)
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
    return out
end
local function lightTick(now)
    local c = stc().lightning or {}
    if c.enabled == false or now < (SW.nextAt or 0) then return end
    SW.nextAt = now + pick(c.every_s, { 0.3, 0.8 })
    local cs = centres()
    if #cs == 0 then return end
    local ce = cs[math.random(#cs)]
    local d = pick(c.dist_km, { 2, 25 }) * 100000
    local ang = math.random() * 2 * math.pi
    local at = { X = ce.X + math.cos(ang) * d, Y = ce.Y + math.sin(ang) * d, Z = pick(c.alt_m, { 1500, 7000 }) * 100 }
    local how, cl = "bolt", c.cloud                          -- (a cloud flash at some: Survival's own light, hard rule 70)
    if type(cl) == "table" and cl.enabled ~= false and now >= (SW.lightAt or 0) and math.random() < (tonumber(cl.chance) or 0.5) then
        how, SW.lightAt, at.Z = "effect", now + pick(cl.every_s, { 0.6, 1.6 }), pick(cl.alt_m, { 2000, 4500 }) * 100
    end
    SW.n = (SW.n or 0) + 1
    local ok, what = pcall(THUNDER.cloudFlash, at, how, "the fleet's storm", cl)
    if THUNDER.bolt and c.bolts then
        local okB, seen, why = pcall(THUNDER.bolt, { X = at.X, Y = at.Y, Z = 0 }, c.bolts, "the fleet's storm",
            IFSURF and IFSURF.state and IFSURF.state() and true)   -- (while the surfacing films: in its shot)
        what = tostring(what) .. "; " .. (okB and (seen or ("no bolt: " .. tostring(why))) or ("bolt error " .. tostring(seen)))
    end
    local okT, th = pcall(thQueue, at, now)
    what = tostring(what) .. (okT and th or ("; thunder error " .. tostring(th)))
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
    if THUNDER and THUNDER.cloudTick then pcall(THUNDER.cloudTick, now) end
    local w = wanted()
    if w ~= SW.on and not SW.tr then
        SW.on = w
        fade(w, w and "the night sky's come" or "the storm clears")
    end
    if SW.on and not SW.tr then lightTick(now) end
end }
if type(LEVEL_DROPS) == "table" then                       -- (the level's: its Cloudly actor and lights went with it)
    LEVEL_DROPS["fleet storm"] = function() SW = { on = false }; IFSKY.k, IFSKY.leaving, TH.q, TH.got, TH.ev, CELLS = nil, nil, {}, {}, {}, {} end
end
end
-- TEST ONLY END
