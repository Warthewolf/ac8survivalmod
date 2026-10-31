-- sv_rows.lua: the game's Lua and behaviour scripts, the NPC / ace / special rows added at the menu.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- Puts a behaviour script into the game's Lua as module `mod` (instrumented). true, or false and the error.
local function gameLuaInject(mod, code)
    local short = mod:match("([^%.]+)$")
    local chunk = "local C = (function(...)\n" .. code .. "\nend)(...)\n" ..
        string.format("package.loaded[%q] = SV_Instrument(%q, C)\nreturn tostring(package.loaded[%q])", mod, short, mod)
    local ok, res = gameLua(chunk, mod)
    if ok then GLS.injected[mod] = true end
    return ok, res
end

-- Sets Survival up in a (new) game Lua state: diagnostics, the helper, the stock scripts wrapped, and our scripts.
local function gameLuaSetup()
    local ok, res = gameLua(GAME_LUA_DIAG, "SurvivalDiag")
    log("game Lua: " .. (ok and "" or "diagnostics failed: ") .. tostring(res))
    ok, res = gameLua(GAME_LUA_HELPER, "SurvivalHelper")
    log("game Lua: " .. tostring(res))
    if not ok then return end
    for _, m in ipairs(GAME_LUA_STOCK) do
        local _, resS = gameLua(string.format(REQUIRE_AND_WRAP, m, m:match("([^%.]+)$")), "SurvivalStock")
        log("game Lua: stock " .. m .. ": " .. tostring(resS))
    end
    if not CFG.probe.behaviour then return end           -- the behaviour probe is off: its scripts aren't needed
    -- The packaged script through the game's own loader (the asset route); put in directly if that fails.
    local okP, resP = gameLua(string.format(REQUIRE_AND_WRAP, PROBE_PKG_MODULE, "LA_SV_ProbePursue"), "SurvivalPkg")
    log("game Lua: packaged script via the game's require: " .. tostring(resP))
    local code = readScript("LA_SV_ProbePursue.lua")
    if okP and tostring(resP):sub(1, 5) == "true " then GLS.injected[PROBE_PKG_MODULE] = true
    elseif code then
        local okI, resI = gameLuaInject(PROBE_PKG_MODULE, code)
        log("game Lua: packaged script put in directly instead: " .. tostring(resI) .. (okI and "" or " (FAILED)"))
    end
    if code then
        local okR, resR = gameLuaInject(PROBE_RT_MODULE, (code:gsub("LA_SV_ProbePursue", "LA_SV_ProbePursueRt")))
        log("game Lua: run-time script " .. PROBE_RT_MODULE .. ": " .. tostring(resR) .. (okR and "" or " (FAILED)"))
    end
end

-- From the main menu on (every second; levelSince = ticks since Survival's level loaded, or nil): notices the game's
-- Lua state, sets Survival up in it, and in the level logs the helper's report when it changes (every 10 s).
function gameLuaTick(tick, levelSince)
    if type(SV_GameLuaState) ~= "function" then
        if not GLS.warned then GLS.warned = true; log("game Lua: dlls/main.dll older than 0.8.0; no bridge") end
        return
    end
    local L = SV_GameLuaState()
    if L == 0 and levelSince and levelSince >= 12 and not GLS.created then   -- 3 s into Survival's level, still none
        GLS.created = true
        L = SV_GameLuaState(1)
    end
    if L ~= GLS.L then
        GLS.L, GLS.injected, GLS.report = L, {}, nil
        if L == 0 then log("game Lua: no state"); return end
        log(string.format("game Lua: state %X%s", L, levelSince and " (in Survival's level)" or ""))
        gameLuaSetup()
    end
    if L ~= 0 and levelSince and tick % 40 == 0 then
        local ok, res = gameLua("return SV_Report and SV_Report() or 'no helper'", "SurvivalReport")
        if res ~= GLS.report then GLS.report = res; log("game Lua: " .. (ok and "" or "report failed: ") .. tostring(res)) end
    end
end

-- Route 2: a LuaScript object made at run time; it only has to carry the module name (LuaInitializePath), which the
-- game's require finds in package.loaded (gameLuaInject). Its outer is the GameInstance (test 20: making a package
-- from UE4SS crashed the game).
local function runtimeScript()
    if valid(PR.scripts.rt) then return PR.scripts.rt end
    local code, why = readScript("LA_SV_ProbePursue.lua")
    if not code then return nil, why end
    code = code:gsub("LA_SV_ProbePursue", "LA_SV_ProbePursueRt")
    local cls = StaticFindObject("/Script/LuaPluginRuntime.LuaScript")
    if not valid(cls) then return nil, "class /Script/LuaPluginRuntime.LuaScript not found" end
    local o = StaticConstructObject(cls, gameInstance(), FName("SV_LA_ProbePursueRt"))
    if not valid(o) then return nil, "StaticConstructObject(LuaScript) returned nothing" end
    o.Code = code
    o.ImportPath = "../../AssetWork/LuaSource/SurvivalMode/AI/LA_SV_ProbePursueRt.lua"
    o.LuaInitializePath = PROBE_RT_MODULE
    log(string.format("probe: run-time LuaScript %s made (module %s)", nameOf(o), PROBE_RT_MODULE))
    pin(o, "probe LuaScript (run time)")
    PR.scripts.rt = o
    return o
end

local function packageScript()
    if valid(PR.scripts.pkg) then return PR.scripts.pkg end
    local o, why = loadObject(PROBE_PKG_SCRIPT)
    if not o then return nil, why end
    pin(o, "probe LuaScript (package)")
    PR.scripts.pkg = o
    return o
end

-- Adds row `new` to dt as a copy of `src` and lets edit(row) change the copy (in place: FindRow returns the row).
function cloneRow(dt, src, new, edit)
    local _, have = dtCall(dt, "FindRow", new)
    if have ~= nil then return true end
    local okS, srow = dtCall(dt, "FindRow", src)
    if not okS or srow == nil then return false, "no row " .. src end
    dtCall(dt, "AddRow", new, srow)
    local _, row = dtCall(dt, "FindRow", new)
    if row == nil then return false, "AddRow did not add " .. new end
    local ok, err = pcall(edit, row)
    if not ok then dtCall(dt, "RemoveRow", new); return false, tostring(err) end
    return true
end

-- One variant ("Pkg" / "Rt"): LuaSet row -> NPC row (the mission row pointing at it is built in). true when in.
local function probeVariant(tables, v, script)
    local names = { luaset = PROBE_TABLES[1].row .. v, npc = PROBE_TABLES[2].row .. v, mission = PROBE_MISSION_ROW[v] }
    local steps = {
        { tables.luaset, PROBE_TABLES[1].src, names.luaset, function(r) r.LuaAsetts.PursueTargetLua.LuaScript = script end },
        { tables.npc, PROBE_TABLES[2].src, names.npc, function(r)
            r.LuaSetId = FName(names.luaset)
            if SR.module then r.NpcAIModuleId = FName(SR.module) end            -- the enemy search range too
        end },
    }
    for _, s in ipairs(steps) do
        local ok, why = cloneRow(s[1], s[2], s[3], s[4])
        if not ok then return false, s[3] .. ": " .. tostring(why) end
    end
    local check = "?"
    pcall(function()
        local _, r = dtCall(tables.luaset, "FindRow", names.luaset)
        check = nameOf(r.LuaAsetts.PursueTargetLua.LuaScript)
    end)
    log("probe: rows " .. names.luaset .. " / " .. names.npc .. " / " .. names.mission .. " in; pursue slot = " .. check)
    return true, names.mission
end

-- Called every second from the start (main menu included) until both variants are in (or 20 tries failed).
function probeSetup()
    if not CFG.probe.enabled or not CFG.probe.behaviour or (PR.ready.Pkg and PR.ready.Rt) or PR.tries >= 20 then return end
    if not gameInstance() then return end                  -- the run-time script's outer, and where tables get pinned
    if CFG.search.enabled and not SR.done then return end  -- the probe's NPC rows take the search module row
    PR.tries = PR.tries + 1
    local tables = {}
    for _, t in ipairs(PROBE_TABLES) do
        local dt, why = loadObject(t.path)
        if not dt then
            if PR.tries == 20 then log("probe: table " .. t.path .. " not loaded (" .. tostring(why) .. "); no behaviour probe") end
            return
        end
        pin(dt, nameOf(dt))
        tables[t.key] = dt
    end
    PR.tables = tables
    -- Each variant on its own (test 18: an error making the run-time script also kept the package one from flying).
    PR.failed = PR.failed or {}
    for _, v in ipairs({ "Pkg", "Rt" }) do
        if v == "Rt" and not CFG.probe.runtime then PR.failed[v] = true end
        if not PR.ready[v] and not PR.failed[v] then
            local okV, err = pcall(function()
                local script, why = (v == "Pkg" and packageScript or runtimeScript)()
                if script then
                    local ok, res = probeVariant(tables, v, script)
                    if ok then PR.ready[v] = res else log("probe: " .. v .. " rows not added: " .. tostring(res)); PR.failed[v] = true end
                else log("probe: " .. v .. " script not available: " .. tostring(why)); PR.failed[v] = true end
            end)
            if not okV then log("probe: " .. v .. " setup error " .. tostring(err)); PR.failed[v] = true end
        end
    end
    if (PR.ready.Pkg or PR.failed.Pkg) and (PR.ready.Rt or PR.failed.Rt) then PR.tries = 20 end
end

-- The probe aircraft for this round's first flight (odd rounds: package script, even rounds: run-time script).
---------------------------------------------------------------------------------------------------- enemy search
-- CFG.search: Survival's AI module row NPC_AIModule_SV_Search (a copy of NPC_AIModule_Plane000 with CFG.search's
-- radius and cloud rule) is added to DT_NPC_AIModule, and for every aircraft in CFG.aircraft a copy of its DT_NPC row
-- (<NpcId>_SV) that uses it. Survival's NPC table has a mission row <aircraft>_sv pointing at each copy
-- (tools/build_survival.py SEARCH_AIRCRAFT), because the spawner caches that table when the level starts; as with the
-- probe, an aircraft only flies its _sv row when the rows were in before the level loaded.
SEARCH_MODULE = { path = "/Game/Datatables/AI/NPC/AIModule/DT_NPC_AIModule.DT_NPC_AIModule",
                        src = "NPC_AIModule_Plane000", row = "NPC_AIModule_SV_Search" }

-- Called every second from the start (main menu included) until done (or 20 tries failed).
-- The fighter flights' behaviour row (tools/survival_events.py POOL_BEHAVIOUR_ROW = BEHAVIOUR_AIRCRAFT .. "_sv"): the
-- world data names it, and the game builds their behaviour from it when the level loads, so its DT_NPC row is made
-- here even when CFG.search is off or CFG.aircraft leaves that aircraft out.
local BEHAVIOUR_AIRCRAFT = "f16c_common"
FCS_TABLE = "/Game/Datatables/AI/NPC/FCS/DT_NPC_FCS.DT_NPC_FCS"
WEAPON_TABLE = "/Game/Datatables/AI/NPC/Weapon/DT_NPC_Weapon.DT_NPC_Weapon"

-- Survival's own behaviour sets (CFG.behaviour_sets) into DT_NPC_LuaSet. BS.ready[name] once a set is in.
BS = { done = false, ready = {}, tries = 0 }
function setsSetup()
    if BS.done then return end
    if not gameInstance() then return end
    BS.tries = BS.tries + 1
    local ls, why = loadObject(PROBE_TABLES[1].path)
    if not ls then
        if BS.tries >= 20 then BS.done = true; log("behaviour: DT_NPC_LuaSet not loaded (" .. tostring(why) .. "); no own sets") end
        return
    end
    pin(ls, nameOf(ls))
    for name, def in pairs(CFG.behaviour_sets) do
        local scripts, missing = {}, nil
        for slot, sname in pairs(def.slots) do
            local on = (sname ~= "LA_SV_TailChase" or CFG.ai.tail_chase)
                and ((sname ~= "LA_SV_ProvokeNear" and sname ~= "LA_SV_Escape") or CFG.ai.reactions)
            if on then                                      -- (ai.tail_chase / ai.reactions false: the stock scripts)
                local sc = loadObject("/Game/LuaSource/SurvivalMode/AI/" .. sname .. "." .. sname)
                if valid(sc) then pin(sc, "behaviour script " .. sname); scripts[slot] = sc else missing = sname end
            end
        end
        if missing then
            log("behaviour: set " .. name .. " not made (script " .. missing .. " not in the container)")
        else
            local ok, err = cloneRow(ls, def.base, name, function(r)
                for slot, sc in pairs(scripts) do r.LuaAsetts[slot].LuaScript = sc end
            end)
            if ok then
                BS.ready[name] = true
                local parts = {}
                for slot in pairs(scripts) do parts[#parts + 1] = slot .. " = " .. def.slots[slot] end
                table.sort(parts)
                log("behaviour: set " .. name .. " in (" .. def.base .. " with " .. table.concat(parts, ", ") .. ")")
            else
                log("behaviour: set " .. name .. " not made (" .. tostring(err) .. ")")
            end
        end
    end
    BS.done = true
end

function searchSetup()
    if SR.done then return end
    if not gameInstance() or not BS.done then return end      -- the own sets first: the search rows name them
    SR.tries = SR.tries + 1
    local function giveUp(why) log("search: " .. why .. "; enemies keep the stock 6 km search"); SR.done = true end
    local mod, why1 = loadObject(SEARCH_MODULE.path)
    local npc, why2 = loadObject(PROBE_TABLES[2].path)
    local mission, why3 = loadObject("/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission")   -- (Survival's NPC table)
    if not (mod and npc and mission) then
        if SR.tries >= 20 then giveUp("tables not loaded (" .. tostring(why1 or why2 or why3) .. ")") end
        return
    end
    for _, t in ipairs({ mod, npc, mission }) do pin(t, nameOf(t)) end
    -- CFG.missiles / guns / special: Survival copies of the fire-control (and gun weapon) rows the fighters use, made
    -- once and shared by every aircraft that uses the same stock row
    local wantFcs = CFG.missiles.enabled or CFG.guns.enabled or CFG.special.enabled
    local fcs = wantFcs and loadObject(FCS_TABLE) or nil
    if fcs then pin(fcs, nameOf(fcs)) elseif wantFcs then log("weapons: DT_NPC_FCS not loaded; stock fire control") end
    local wpn = CFG.guns.enabled and loadObject(WEAPON_TABLE) or nil
    if wpn then pin(wpn, nameOf(wpn)) end
    local made = {}
    local function copy(tbl, src, edit, what, suf)         -- src .. "_SV" .. suf in tbl, edited; its name, or nil
        local new = src .. "_SV" .. (suf or ""):upper()
        if made[new] == nil then
            local ok, why = cloneRow(tbl, src, new, edit)
            made[new] = ok
            log("weapons: " .. src .. " -> " .. new .. " " .. (ok and ("(" .. what .. ")") or ("not made: " .. tostring(why))))
        end
        return made[new] and new or nil
    end
    local function svFcs(src, level)
        local m = withLevel(CFG.missiles, spikeCfg(level).missiles)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.CaptureAngleRange = m.capture_m, m.angle_deg
            r.ActivationTime, r.TriggeringTime = m.arm_s, m.lock_s
            r.ShotIntervalTime, r.RestingTime = m.interval_s, m.rest_s
        end, string.format("missile: lock within %d m / %d deg, arm %.1f s, lock %.1f s, %.1f s between, rest %.1f s",
            m.capture_m, m.angle_deg, m.arm_s, m.lock_s, m.interval_s, m.rest_s), SPIKE_SUFFIX[level])
    end
    -- a gun's fire-control row and its rounds' weapon row, copied under suffix `suf` (o: range, angle, aim, burst,
    -- rest, damage_x, spread, optional life_x and lead; `what` names it in the log). lead: PredictionOffsetTime, the
    -- seconds ahead of the target it aims (the stock AA guns' 0.8; every aircraft gun 0, so they aim where you are)
    local function gunRow(src, o, what, suf)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.CaptureAngleRange = o.range, o.angle
            r.TriggeringTime, r.TriggerCount, r.RestingTime = o.aim, o.burst, o.rest
            if o.lead then r.PredictionOffsetTime = o.lead end
            if wpn then
                local rounds = copy(wpn, r.NpcWeaponId:ToString(), function(x)
                    x.damage = x.damage * o.damage_x
                    x.MaxSpawnAngle = o.spread
                    if o.life_x then x.LifeTime = x.LifeTime * o.life_x end      -- (how far they fly)
                end, string.format("%sgun rounds: damage x%.1f, spread %.3f deg%s", what, o.damage_x, o.spread,
                    o.life_x and string.format(", life x%.0f", o.life_x) or ""), suf)
                if rounds then r.NpcWeaponId = FName(rounds) end
            end
        end, string.format("%sgun: within %.0f m / %.0f deg, %.2f s on target, %.0f-round bursts, rest %.2f s%s", what, o.range,
            o.angle, o.aim, o.burst, o.rest, o.lead and string.format(", leads %.2f s", o.lead) or ""), suf)
    end
    local function svGun(src, level)
        local g = withLevel(CFG.guns, spikeCfg(level).guns)
        return gunRow(src, { range = g.range_m, angle = g.angle_deg, aim = g.aim_s, burst = g.burst, rest = g.rest_s,
                             damage_x = g.damage_x, spread = g.spread_deg }, "", SPIKE_SUFFIX[level])
    end
    -- an ace tier's: the level's gun, leading you by its tier's gun_lead_s (rows _SV<level>_<TIER>), or nil (no lead set)
    local function aceGun(src, level, tier)
        local A = CFG.aces
        local base = type(A.gun_lead_s) == "table" and A.gun_lead_s[tier]
        if type(base) ~= "number" or base <= 0 then return nil end
        local lead = math.min(A.gun_lead_max or base, base + (A.gun_lead_per_level or 0) * level)
        local g = withLevel(CFG.guns, spikeCfg(level).guns)
        return gunRow(src, { range = g.range_m, angle = g.angle_deg, aim = g.aim_s, burst = g.burst, rest = g.rest_s,
                             damage_x = g.damage_x, spread = g.spread_deg, lead = lead },
                      tier .. " aces' ", SPIKE_SUFFIX[level] .. "_" .. tier)
    end
    -- MINDRIPPER's own (CFG.specials.anomaly.aggression): the top spike level's, that many times quicker (rows _SVX)
    local AN = CFG.specials.anomaly
    local AGG = math.max(1, AN.aggression or 1)
    local function anomFcs(src)
        local m = withLevel(CFG.missiles, spikeCfg(#SPIKE_SUFFIX).missiles)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.CaptureAngleRange = m.capture_m * 1.5, math.min(180, m.angle_deg * 1.5)
            r.ActivationTime, r.TriggeringTime = m.arm_s / AGG, m.lock_s / AGG
            r.ShotIntervalTime, r.RestingTime = m.interval_s / AGG, m.rest_s / AGG
            r.TriggerCount = math.max(2, r.TriggerCount or 1)             -- salvos of two
        end, string.format("MINDRIPPER's missiles: lock within %d m / %d deg, arm %.2f s, lock %.2f s, %.2f s between, rest %.2f s",
            m.capture_m * 1.5, math.min(180, m.angle_deg * 1.5), m.arm_s / AGG, m.lock_s / AGG, m.interval_s / AGG,
            m.rest_s / AGG), "x")
    end
    -- its ECM pod held up (tools/re/MINIMAP_MARKERS.md 3a: the stock row rests 30 s after each 15 s, so the radar ring
    -- comes and goes): no rest, a new pod as the last one's 15 s run out, and up from 20 km so the ring is there first
    -- (user, 2026-10-23: AB.L..IN's "ECM didn't turn on": TriggeringTime was 0.5; the stock row's 15 s matches the
    -- pod's 15 s LifeTime, so it's kept, with the 30 s rest taken out and a new pod every 14 s)
    local function anomEcm(src)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.ActivationTime = 20000, 0.5
            r.TriggeringTime, r.ShotIntervalTime, r.RestingTime = 15.0, 14.0, 0     -- (each new pod 1 s before the last ends)
            r.MagazineCapacity = 999
        end, "ECM pod (MINDRIPPER's, AB.L..IN's): always up (no rest, 15 s on, every 14 s, from 20 km)", "x")
    end
    -- AB.L..IN's own with its phases (CFG.specials.glitch.phases ecm_row; P7, tools/re/BEHAVIOUR_DIRECTOR.md unit 9): its
    -- pod is held up by RE_SV_GlitchEcm every ecm_every_s (hard rule 40) until its phase 3 drops it, so its own row fires
    -- a pod by itself at most once a minute (anomEcm's values, 60 s between and 60 s rest), else the 14 s refire of
    -- anomEcm would keep the ECM up whatever the phase (rows _SVE; MINDRIPPER keeps anomEcm). Off by default (code review
    -- of unit 9): "up all fight" was confirmed with anomEcm's row and the event together, so phase 3 drops the ECM by
    -- ecm_pods_off alone until a test shows the event holds it up under this row
    local function glitchEcm(src)
        return copy(fcs, src, function(r)
            r.CaptureDistance, r.ActivationTime = 20000, 0.5
            r.TriggeringTime, r.ShotIntervalTime, r.RestingTime = 15.0, 60.0, 60.0
            r.MagazineCapacity = 999
        end, "ECM pod (AB.L..IN's, its phases): by its events, the row's own at most once a minute (60 s between, 60 s rest)", "e")
    end
    local GPH = CFG.specials.glitch.phases
    local function anomGun(src)
        local g = withLevel(CFG.guns, spikeCfg(#SPIKE_SUFFIX).guns)
        local reach, acc = AN.gun_reach_x or 1, AN.gun_accuracy_x or 1
        return gunRow(src, { range = g.range_m * 1.5 * reach, angle = math.min(180, g.angle_deg * 1.5), aim = g.aim_s / AGG,
                             burst = math.min(200, g.burst * AGG), rest = g.rest_s / AGG, damage_x = g.damage_x * 2,
                             spread = g.spread_deg / 2 / acc, life_x = reach, lead = AN.gun_lead_s }, "MINDRIPPER's ", "x")
    end
    -- The fighter roles' fire control (CFG.roles, P1; made only with roles on at the main menu, as the rows are made
    -- once a session): the Wolf airframes' gun leads you by wolf.gun_lead_s ("guns lead on" can't be switched live:
    -- PredictionOffsetTime is on the row; rows _SV<level>_WOLF; every plane of those airframes, bait and trap, so it
    -- holds only while no other role flies them: the Skirmishers' fallback in rounds 1-3 does), and the Skirmishers'
    -- special slot a copy of the LAAM's that reaches skirm.laam_m and never fires inside skirm.laam_min_m (row
    -- NPC_FCS_PlaneLAAM000_SV_SKIRM; the stock one: 1.5-4 km, as Survival's own missiles already reach)
    local RC = CFG.roles
    local rolesOn = RC and RC.enabled
    local function wolfGun(src, level)
        local lead = tonumber(RC.wolf and RC.wolf.gun_lead_s) or 0
        if lead <= 0 then return nil end
        local g = withLevel(CFG.guns, spikeCfg(level).guns)
        return gunRow(src, { range = g.range_m, angle = g.angle_deg, aim = g.aim_s, burst = g.burst, rest = g.rest_s,
                             damage_x = g.damage_x, spread = g.spread_deg, lead = lead },
                      "the Wolf airframes' ", SPIKE_SUFFIX[level] .. "_wolf")
    end
    local function skirmLaam()
        local s = RC.skirm or {}
        if not s.laam then return nil end
        return copy(fcs, "NPC_FCS_PlaneLAAM000", function(r)
            r.CaptureDistance, r.CaptureMinDistance, r.CaptureAngleRange = s.laam_m, s.laam_min_m, s.laam_angle_deg
            r.TriggeringTime, r.ShotIntervalTime, r.RestingTime = s.laam_lock_s, s.laam_interval_s, s.laam_rest_s
        end, string.format("the Skirmishers' LAAM: lock within %.0f m / %.0f deg, never inside %.0f m, lock %.1f s, %.1f s between, rest %.1f s",
            s.laam_m, s.laam_angle_deg, s.laam_min_m, s.laam_lock_s, s.laam_interval_s, s.laam_rest_s), "_skirm")
    end
    -- The AI's flares (CFG.flares; P6's missile counter, the critic's lever): the saved profile had you missile-heavy at
    -- the main menu (sv_stats.lua PROF.menu, before this; PROF.flareWant): every fighter's flare slot (stock
    -- NPC_FCS_PlaneFlr000: 10 in the magazine, 25 s to reload) onto a copy that holds more and reloads sooner (row
    -- NPC_FCS_PlaneFlr000_SV_FLR, one for every level); the specials' own keep theirs. nil: the stock row
    local flr = PROF and PROF.flareWant
    local function aiFlares(src)
        if type(flr) ~= "table" then return nil end
        return copy(fcs, src, function(r) r.MagazineCapacity, r.ReloadTime = flr.magazine, flr.reload_s end,
            string.format("the AI's flares, against your missiles: %d in the magazine, %.1f s to reload", flr.magazine,
            flr.reload_s), "_flr")
    end
    -- AB.L..IN's (CFG.specials.glitch gun_*): long bursts, no rest, accurate rounds (rows _SVG)
    local function glitchGun(src)
        local GL = CFG.specials.glitch
        return gunRow(src, { range = GL.gun_range_m, angle = GL.gun_angle_deg, aim = 0.05, burst = 200, rest = 0,
                             damage_x = GL.gun_damage_x, spread = GL.gun_spread_deg, lead = GL.gun_lead_s }, "AB.L..IN's ", "g")
    end
    local ok, why = cloneRow(mod, SEARCH_MODULE.src, SEARCH_MODULE.row, function(r)
        if not CFG.search.enabled then return end   -- off: the stock module's values
        r.Radius = CFG.search.radius_m
        r.bEnableLostTargetInClouds = CFG.search.lose_in_clouds
    end)
    if not ok then return giveUp("module row not added: " .. tostring(why)) end
    local guardModule = SEARCH_MODULE.row .. "_Guard"           -- the Anomaly's guards' (CFG.specials.anomaly.guard_search_m)
    local okG = cloneRow(mod, SEARCH_MODULE.src, guardModule, function(r)
        r.Radius = AN.guard_search_m
        r.bEnableLostTargetInClouds = false
    end)
    log(string.format("special: the Anomaly's guards search %d m (%s)", AN.guard_search_m, okG and guardModule or "module NOT made"))
    SR.module, SR.npcRow, SR.tables = SEARCH_MODULE.row, {}, { npc = npc, mission = mission }
    local n, list = 0, { BEHAVIOUR_AIRCRAFT }
    local inList = { [BEHAVIOUR_AIRCRAFT] = true }
    local function add(a) if a and not inList[a] then inList[a] = true; list[#list + 1] = a end end
    for _, a in ipairs(CFG.aircraft) do add(a) end
    -- the airframes that join later (CFG.variety.late, the tiers' signature types) and the jammer's (CFG.jammer): their
    -- rows are made whether or not they're on now, so a survival.ini change needs no new rows
    for _, e in ipairs(CFG.variety and CFG.variety.late or {}) do add(e[1]) end
    for _, l in pairs(CFG.variety and CFG.variety.signature or {}) do for _, a in ipairs(l) do add(a) end end
    if CFG.jammer then add(CFG.jammer.aircraft) end
    do      -- CFG.aces and the Anomaly's: DT_NPC rows (DT_SV_NpcRows), names. The Anomaly's always: the world data names them
        local mine = loadObject(CFG.specials.shuttle.npc_rows)
        local nAces, names, lost = 0, 0, {}
        if mine then pin(mine, nameOf(mine)) end
        local models = {}                          -- ACE.models key -> its model row is in DT_NPC_Model
        if CFG.aces.online_aircraft then
            local mt, mr = loadObject(ACE.model_table), loadObject(ACE.model_rows)
            for _, t in ipairs({ mt, mr }) do if t then pin(t, nameOf(t)) end end
            for k, m in pairs(ACE.models) do
                local have = nil
                if mt then local _; _, have = dtCall(mt, "FindRow", m.row) end
                if have == nil and mt and mr then
                    local _, r = dtCall(mr, "FindRow", m.row)
                    if r ~= nil then dtCall(mt, "AddRow", m.row, r); _, have = dtCall(mt, "FindRow", m.row) end
                end
                models[k] = have ~= nil
                if have ~= nil and type(SV_SetText) == "function" then SV_SetText(m.key, m.name) end
                log("aces: model " .. m.row .. " (" .. m.name .. ") " .. (have ~= nil and "in DT_NPC_Model" or "NOT added; its aces sit out"))
            end
        end
        for tier, keys in pairs(ACE.roster) do
            local an, gl, va = CFG.specials.anomaly, CFG.specials.glitch, CFG.specials.valka
            local c = (tier == "anomaly" and { squadron = an.guards_name, f04e = an.name })
                or (tier == "glitch" and { squadron = gl.squadron, e18g = gl.name })
                or (tier == "valka" and { squadron = va.squadron, x40a = va.name }) or CFG.aces[tier] or {}
            if tier ~= "anomaly" and tier ~= "glitch" and tier ~= "valka" and not CFG.aces.enabled then keys = {} end
            if type(SV_SetText) == "function" and SV_SetText("SV_Sqn_" .. tier, tostring(c.squadron or tier)) == 1 then names = names + 1 end
            for _, k in ipairs(keys) do
                if type(SV_SetText) == "function" and SV_SetText("SV_Ace_" .. tier .. "_" .. k, tostring(c[k] or k)) == 1 then names = names + 1 end
                for _, part in ipairs(ACE.models[k] and not models[k] and {} or { "L", "W" }) do
                    local row = "SV_Ace_" .. tier .. "_" .. k .. "_" .. part
                    local _, have = dtCall(npc, "FindRow", row)
                    if have == nil and mine then
                        local _, r = dtCall(mine, "FindRow", row)
                        if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
                    end
                    if have ~= nil then
                        list[#list + 1] = ACE.row(tier, k, part:lower()); nAces = nAces + 1
                        SR.aceTier = SR.aceTier or {}
                        SR.aceTier[ACE.row(tier, k, part:lower())] = tier      -- (its gun's lead: CFG.aces.gun_lead_s)
                    else lost[#lost + 1] = row end
                end
            end
        end
        log(string.format("aces: %d rows in DT_NPC, %d names set%s", nAces, names,
            #lost > 0 and ("; missing from DT_SV_NpcRows: " .. table.concat(lost, ", ")) or ""))
    end
    SR.levels = SR.levels or {}
    local nLevels = CFG.spikes.enabled and math.min(#CFG.spikes.levels, #SPIKE_SUFFIX) or 0
    for _, a in ipairs(list) do
        local spw                                          -- its special weapon: the same at every level
        local okA, err = pcall(function()
            local _, base = dtCall(mission, "FindRow", a)
            if base == nil then error("no mission row " .. a .. " in DT_SV_NpcMission") end
            local srcNpc = base.NpcId:ToString()
            for level = 0, nLevels do
                local mname = a .. "_sv" .. SPIKE_SUFFIX[level]
                local _, mrow = dtCall(mission, "FindRow", mname)
                if mrow == nil then error("no mission row " .. mname .. " in DT_SV_NpcMission") end
                local svNpc = mrow.NpcId:ToString()
                local okR, whyR = cloneRow(npc, srcNpc, svNpc, function(r)
                    r.NpcAIModuleId = FName((a == ACE.row("anomaly", "f04e", "w") and okG) and guardModule or SR.module)
                    if a == ACE.row("anomaly", "f04e", "l") then          -- MINDRIPPER (CFG.specials.anomaly)
                        local an = CFG.specials.anomaly
                        local okE, errE = pcall(function()           -- (a failure keeps the row, as stock)
                            r.MaxHealthDifference = an.health_add
                            r.PitchSpeedDifference, r.RollSpeedDifference = an.turn_add.pitch, an.turn_add.roll
                            r.YawSpeedDifference = an.turn_add.yaw
                            if an.hover then
                                r.SpeedNormalCoefficient, r.SpeedMaxCoefficient = an.hover_speed, an.hover_speed
                                r.SpeedMinCoefficient, r.SpeedTurnCoefficient = an.hover_speed, an.hover_speed
                            end
                        end)
                        if level == 0 then
                            log(string.format("special: %s's row %s: +%d HP, turn +%d/+%d/+%d, %s%s", an.name, svNpc,
                                an.health_add, an.turn_add.pitch, an.turn_add.roll, an.turn_add.yaw,
                                an.hover and string.format("hovers (speed x%.2f)", an.hover_speed) or "flies",
                                okE and "" or ("; NOT applied: " .. tostring(errE))))
                        end
                    end
                    if a == ACE.row("glitch", "e18g", "l") then            -- AB.L..IN (CFG.specials.glitch)
                        local gl = CFG.specials.glitch
                        local okE, errE = pcall(function() r.MaxHealthDifference = gl.health - 60 end)   -- (the EA-18G: 60)
                        if level == 0 then
                            log(string.format("special: %s's row %s: %d HP%s", gl.name, svNpc, gl.health,
                                okE and "" or ("; NOT applied: " .. tostring(errE))))
                        end
                    end
                    local ft = a:match("^sv_ace_(%a+)_")                    -- a tier's squadron: CFG.aces.flight
                    local fl = ft and CFG.aces.flight and CFG.aces.flight[ft]
                    -- (only a tier that flies beyond stock: P9 gave every squadron an entry, its roles and openers)
                    if type(fl) == "table" and type(fl.turn_add) == "table" then
                        local okF, errF = pcall(function()
                            r.PitchSpeedDifference = (r.PitchSpeedDifference or 0) + fl.turn_add.pitch
                            r.RollSpeedDifference = (r.RollSpeedDifference or 0) + fl.turn_add.roll
                            r.YawSpeedDifference = (r.YawSpeedDifference or 0) + fl.turn_add.yaw
                            if fl.health_add then r.MaxHealthDifference = (r.MaxHealthDifference or 0) + fl.health_add end
                            for f, x in pairs({ SpeedMaxCoefficient = fl.speed_x, SpeedTurnCoefficient = fl.speed_x,
                                                SpeedNormalCoefficient = fl.cruise_x }) do
                                local v = r[f]
                                r[f] = ((type(v) == "number" and v > 0) and v or 1.0) * x
                            end
                        end)
                        if level == 0 then
                            log(string.format("aces: %s flies harder: turn +%d/+%d/+%d, speed x%.2f, cruise x%.2f, %+d HP%s", svNpc,
                                fl.turn_add.pitch, fl.turn_add.roll, fl.turn_add.yaw, fl.speed_x, fl.cruise_x, fl.health_add or 0,
                                okF and "" or ("; NOT applied: " .. tostring(errF))))
                        end
                    end
                    local mind = a == ACE.row("anomaly", "f04e", "l")       -- MINDRIPPER: its own, every level
                    local glitch = a == ACE.row("glitch", "e18g", "l")      -- AB.L..IN: its gun and ECM pod
                    local valka = a == ACE.row("valka", "x40a", "l")        -- VALKA: MINDRIPPER's fire control
                    if fcs and valka then              -- the x40a row has no gun: hers in slot 1, a QAAM in slot 3
                        pcall(function()
                            local va = CFG.specials.valka
                            for slot, id in pairs(va.weapons or {}) do
                                local cur = r["NpcFCSId" .. slot]:ToString()
                                if cur == "None" or cur == "" then r["NpcFCSId" .. slot] = FName(id) end
                            end
                        end)
                    end
                    local acRole = rolesOn and ROLE.ofAircraft(a) or nil     -- (a fighter role's airframe: CFG.roles)
                    if fcs then                      -- its weapon slots onto Survival's fire control for this level
                        local free, frees = nil, {}
                        for i = 0, 5 do
                            pcall(function()
                                local id = r["NpcFCSId" .. i]:ToString()
                                local new
                                if id:find("^NPC_FCS_PlaneMsl") and CFG.missiles.enabled then
                                    new = (mind or valka) and anomFcs(id) or svFcs(id, level)
                                elseif valka and id:find("^NPC_FCS_PlaneQAAM") then
                                    new = anomFcs(id)
                                elseif id:find("^NPC_FCS_PlaneGun") and CFG.guns.enabled then
                                    new = ((mind or valka) and anomGun(id)) or (glitch and glitchGun(id))
                                        or (SR.aceTier and SR.aceTier[a] and aceGun(id, level, SR.aceTier[a]))
                                        or (acRole == "wolf" and wolfGun(id, level)) or svGun(id, level)
                                elseif glitch and id:find("ECM", 1, true) then        -- its pod always up (to its phase 3)
                                    new = (type(GPH) == "table" and GPH.enabled and GPH.ecm_row and glitchEcm(id)) or anomEcm(id)
                                elseif flr and id:find("^NPC_FCS_PlaneFlr") and not (mind or glitch or valka) then
                                    new = aiFlares(id)                               -- (P6: your missile habit)
                                elseif (id == "None" or id == "") and i >= 3 then free = free or i; frees[#frees + 1] = i end
                                if new then r["NpcFCSId" .. i] = FName(new) end
                            end)
                        end
                        local fcsList = CFG.special.fcs
                        -- the jammer's ECM pod (CFG.jammer): its row, the campaign's plain EA-18G (OP1010_e18g_01), has
                        -- none (only the named aces' do), so RE_SV_JamEcm_NN's WN_WEAPON_4 (slot 3, tools/
                        -- survival_events.py JAM_ECM_SLOT) fired the random special weapon put there (the user,
                        -- 2026-10-29: "the EA-18G never activated it's ECM"). The pod first, held up as MINDRIPPER's
                        local jam = CFG.jammer and CFG.jammer.enabled ~= false and a == CFG.jammer.aircraft
                        if jam and free then
                            local pod = anomEcm("NPC_FCS_ECM000") or "NPC_FCS_ECM000"
                            r["NpcFCSId" .. free] = FName(pod)
                            if level == 0 then
                                log(string.format("weapons: %s (the jammer) carries its ECM pod %s (slot %d%s)", svNpc, pod, free,
                                    free == 3 and "" or ": NOT slot 3, the one RE_SV_JamEcm fires"))
                            end
                            free = frees[2]
                        end
                        if mind then                    -- its own (CFG.specials.anomaly.weapons: specials and the ECM pod)
                            local got = {}
                            for k, slot in ipairs(frees) do
                                local w = AN.weapons[k]
                                if w and w:find("ECM") then w = anomEcm(w) or w             -- its pod held up
                                elseif w then w = anomFcs(w) or w end                       -- its special weapons quicker too
                                if w then r["NpcFCSId" .. slot] = FName(w); got[#got + 1] = w end
                            end
                            if level == 0 then log("weapons: " .. svNpc .. " (MINDRIPPER) carries " .. table.concat(got, ", ")) end
                            free = nil
                        end
                        if CFG.special.enabled and free and #fcsList > 0 then
                            -- (a Skirmisher airframe: its long-range LAAM copy, CFG.roles.skirm, not a random one)
                            if not spw and acRole == "skirm" then spw = skirmLaam() end
                            spw = spw or fcsList[math.random(#fcsList)]
                            r["NpcFCSId" .. free] = FName(spw)
                            if level == 0 then log("weapons: " .. svNpc .. " carries " .. spw .. " (slot " .. free .. ")") end
                        end
                    end
                    local set = CFG.search.luaset
                    if set and CFG.behaviour_sets[set] and not BS.ready[set] then set = CFG.search.fallback_luaset end
                    -- the Anomaly's guards (its wing row, every level: the world data names the level-0 one and the
                    -- behaviour is built from it at level load, hard rule 20) fly its pack's set (CFG.specials.anomaly
                    -- .pack guard_luaset, P7: the Wolf trap's close gunfighter; never NLID_0400_CP, hard rule 22)
                    local pk = AN.pack
                    local gs = a == ACE.row("anomaly", "f04e", "w") and type(pk) == "table" and pk.enabled
                        and type(pk.guard_luaset) == "string" and pk.guard_luaset ~= "" and pk.guard_luaset or nil
                    if gs and CFG.behaviour_sets[gs] and BS.ready[gs] then set = gs
                    elseif gs and level == 0 then
                        log("special: the Anomaly's guards keep " .. tostring(set) .. " (their set " .. gs .. " isn't in)")
                    end
                    if gs and set == gs and level == 0 then log("special: the Anomaly's guards (" .. svNpc .. ") fly " .. gs .. " (its pack)") end
                    if set then r.LuaSetId = FName(set) end
                end)
                if not okR then error(svNpc .. ": " .. tostring(whyR)) end
                pcall(function()                  -- its first missile slot (the squad director's salvo fires slot 2)
                    local _, rr = dtCall(npc, "FindRow", svNpc)
                    local slot = nil
                    for i = 0, 5 do
                        if slot == nil and tostring(rr["NpcFCSId" .. i]:ToString()):find("^NPC_FCS_PlaneMsl") then slot = i end
                    end
                    SR.mslSlot = SR.mslSlot or {}
                    SR.mslSlot[mname] = slot
                    -- its special weapon's slot and fire control (sv_spweapons.lua fires slot 3's): the first slot from 3
                    -- that isn't a pod, flares, a gun or a standard missile
                    local sp, sid = nil, nil
                    for i = 3, 5 do
                        local id = tostring(rr["NpcFCSId" .. i]:ToString())
                        if sp == nil and id ~= "None" and id ~= "" and not id:find("ECM", 1, true) and not id:find("ESM", 1, true)
                            and not id:find("Flr", 1, true) and not id:find("Gun", 1, true) and not id:find("^NPC_FCS_PlaneMsl") then
                            sp, sid = i, id
                        end
                    end
                    SR.spSlot, SR.spWeapon = SR.spSlot or {}, SR.spWeapon or {}
                    SR.spSlot[mname], SR.spWeapon[mname] = sp, sid
                end)
                if level == 0 then
                    SR.ready[a], SR.npcRow[a], n = mname, svNpc, n + 1
                else
                    SR.levels[a] = SR.levels[a] or {}
                    SR.levels[a][level] = mname
                end
            end
        end)
        if not okA then log("search: " .. a .. " keeps the stock search (" .. tostring(err) .. ")") end
    end
    local check = "?"
    pcall(function()
        local _, r = dtCall(mod, "FindRow", SEARCH_MODULE.row)
        check = string.format("radius %.0f m, lose target in clouds %s", r.Radius, tostring(r.bEnableLostTargetInClouds))
    end)
    pcall(function()
        local a = CFG.aircraft[1]
        local _, r = dtCall(npc, "FindRow", SR.npcRow[a])
        check = check .. string.format("; %s flies behaviour set %s", SR.npcRow[a], r.LuaSetId:ToString())
    end)
    log(string.format("search: module %s (%s); %d of %d aircraft and ace rows use it", SEARCH_MODULE.row, check, n, #list))
    local nl = 0
    for _, t in pairs(SR.levels) do nl = nl + #t end
    log(string.format("spikes: %d difficulty-spike rows made (%d levels)", nl, nLevels))
    do                                  -- the specials fired (sv_spweapons.lua: slot 3, WN_WEAPON_4): the rows that carry one there
        local want, ok, other = SPW and SPW.FCS_SLOT or 3, 0, {}
        for row, slot in pairs(SR.spSlot or {}) do
            if slot == want then ok = ok + 1 elseif not row:find("_sv%a$") then other[#other + 1] = row .. " " .. tostring(slot) end
        end
        table.sort(other)
        log(string.format("specials: %d rows carry a special in fire-control slot %d (WN_WEAPON_%d: fired at you)%s", ok, want,
            want + 1, #other > 0 and ("; elsewhere: " .. table.concat(other, ", ")) or ""))
    end
    do                                  -- the squad director's bracket salvo (P2) fires WN_WEAPON_3: the rows that carry it
        local want, ok, other = DIR and DIR.SALVO_FCS_SLOT or 2, 0, {}
        for row, slot in pairs(SR.mslSlot or {}) do
            if slot == want then ok = ok + 1 elseif not row:find("_sv%a$") then other[#other + 1] = row .. " " .. tostring(slot) end
        end
        table.sort(other)
        log(string.format("director: %d rows carry their missiles in fire-control slot %d (WN_WEAPON_%d: the salvo)%s", ok, want,
            want + 1, #other > 0 and ("; not: " .. table.concat(other, ", ")) or ""))
    end
    if not SR.ready[BEHAVIOUR_AIRCRAFT] then
        log("search: WARNING the fighters' behaviour row " .. BEHAVIOUR_AIRCRAFT .. "_sv has no DT_NPC row; don't start a run")
    end
    SR.done = true
end

-- The fighter roles' behaviour rows (CFG.roles, behaviour roadmap P1; tools/re/BEHAVIOUR_DIRECTOR.md unit 5; the
-- brief's recipe (b)): the world data has each role group's AI objects name a DT_SV_NpcMission row (ROLE.ROWS, built:
-- tools/build_survival.py NPC_EXTRA) whose NpcId is a DT_NPC row made here, before the level loads (hard rule 20), as
-- a copy of the fighters' (f16c_common's) with Survival's search module and the role's behaviour set (ROLE.SETS). Made
-- in Lua, not baked into DT_SV_NpcRows, so a set that couldn't be made falls back to the fighters' set (or
-- CFG.search.fallback_luaset) instead of naming a LuaSet row that isn't there. With CFG.roles off they name the
-- fighters' set: every flight flies today's behaviour. RS.ready[key] = { row, npc, set, want } once made; sv_main.lua
-- keeps what was in at level load (ROLE.levelLoad, sv_spawn.lua). Once a session (cloneRow keeps an existing row).
RS = { done = false, ready = {} }
function rolesSetup()
    if RS.done or not (SR.done and BS.done) then return end
    RS.done = true
    local npc, mission = SR.tables and SR.tables.npc, SR.tables and SR.tables.mission
    if not (npc and mission and SR.module) then
        log("roles: no behaviour rows (the search rows weren't made); every role flight sits out")
        return
    end
    local on = CFG.roles and CFG.roles.enabled
    local _, base = dtCall(mission, "FindRow", BEHAVIOUR_AIRCRAFT)
    local src = base ~= nil and base.NpcId:ToString() or nil
    local parts = {}
    for _, key in ipairs({ "lancer", "wolf", "wolf_wing", "skirm" }) do
        local mrow = ROLE.ROWS[key]
        local ok, err = pcall(function()
            if not src then error("no mission row " .. BEHAVIOUR_AIRCRAFT .. " to copy") end
            local _, mr = dtCall(mission, "FindRow", mrow)
            if mr == nil then error("no mission row " .. mrow .. " in DT_SV_NpcMission (a container from before roles)") end
            local npcRow = mr.NpcId:ToString()
            local want = on and ROLE.SETS[key] or CFG.search.luaset
            local set = want
            if set and CFG.behaviour_sets[set] and not BS.ready[set] then
                set = (BS.ready[CFG.search.luaset] and CFG.search.luaset) or CFG.search.fallback_luaset
            end
            local okR, whyR = cloneRow(npc, src, npcRow, function(r)
                r.NpcAIModuleId = FName(SR.module)
                if set then r.LuaSetId = FName(set) end
            end)
            if not okR then error(npcRow .. ": " .. tostring(whyR)) end
            local check = "?"
            pcall(function() local _, r = dtCall(npc, "FindRow", npcRow); check = r.LuaSetId:ToString() end)
            RS.ready[key] = { row = mrow, npc = npcRow, set = check ~= "?" and check or set, want = want }
            parts[#parts + 1] = string.format("%s %s -> %s flies %s%s", key, mrow, npcRow, check,
                set ~= want and string.format(" (wanted %s: not made)", tostring(want)) or "")
        end)
        if not ok then parts[#parts + 1] = key .. " NOT made (" .. tostring(err) .. ")" end
    end
    log("roles: behaviour rows " .. (on and "" or "(roles off: the fighters' set) ") .. table.concat(parts, "; "))
    for _, key in ipairs({ "lancer", "wolf", "wolf_wing", "skirm" }) do       -- (as searchSetup's for the fighters' row)
        if not RS.ready[key] then
            log("roles: WARNING " .. key .. "'s behaviour row wasn't made: its flights sit out every level of this session")
        end
    end
end

-- Comona Defense's shuttle row: DT_SV_NpcRows' OP0057_sstb_01_SV (Mission 22's shuttle with Survival's name key,
-- tools/build_survival.py) goes into DT_NPC from the main menu on, before a level loads (the spawner reads it then),
-- and the name key gets CFG.specials.shuttle.name through the text hook.
SPS = { done = false, tries = 0 }
function specialSetup()
    if SPS.done or not gameInstance() then return end
    local c = CFG.specials.shuttle
    SPS.tries = SPS.tries + 1
    local npc, why1 = loadObject(PROBE_TABLES[2].path)
    local mine, why2 = loadObject(c.npc_rows)
    if not (npc and mine) then
        if SPS.tries >= 20 then SPS.done = true; log("special: shuttle row tables not loaded (" .. tostring(why1 or why2) .. ")") end
        return
    end
    pin(npc, nameOf(npc)); pin(mine, nameOf(mine))
    SPS.done = true
    local _, have = dtCall(npc, "FindRow", c.npc_row)
    if have == nil then
        local _, row = dtCall(mine, "FindRow", c.npc_row)
        if row == nil then log("special: " .. c.npc_row .. " missing from DT_SV_NpcRows"); return end
        dtCall(npc, "AddRow", c.npc_row, row)
        _, have = dtCall(npc, "FindRow", c.npc_row)
    end
    local named = type(SV_SetText) == "function" and SV_SetText(c.name_key, c.name) == 1
    log(string.format("special: shuttle row %s %s; its name '%s' %s", c.npc_row, have ~= nil and "in DT_NPC" or "NOT added",
        c.name, named and "set" or "not set (no text slot)"))
end

-- The live provoke on an enemy (a harder tailed plane, P5 of tools/re/BEHAVIOUR_DIRECTOR.md; CFG.ai tier_provoke,
-- provoke_stricter, provoke_cone_deg / provoke_time_s): how soon a tailed plane notices you (ProvokeConditionConeAngle
-- deg, ProvokeDeterminationTime s: you inside that cone of its six for that long puts it in Provoke) and how close its
-- pursuit sits (SurroundPursuitMin/MaxRange, cm), from the round's difficulty spike (CFG.spikes) and the plane's skill
-- tier (CFG.tiers.list), or a special's own values (MINDRIPPER's unit, from sv_main.lua's planeSweep).
--   provokeWant(round, tier[, level])  what a plane should fly: { cone, time, surround = { min m, max m }, level, src }
--                                      or nil (nothing to write: the game's own row). level: the spike level to use
--                                      (default levelFor(round): the spike's, or the intensity director's
--                                      under it), so a later part can ask for another.
--   enemyProvoke(p, want)              writes want on plane p, only the fields that differ from the last write
--                                      (p.provokeSet; p.provokeWant = want): fields written, before / after texts.
--                                      A field's value before its first write is kept (p.provokeStock: the game's own)
--   provokeStockWant(p[, level])       those kept values as a want for enemyProvoke, or nil (none written yet): the
--                                      intensity director's ease to a level with nothing to write puts them back
--   enemySpike(p, round, tier)         once per plane when it appears (p.spiked): provokeWant + enemyProvoke, a
--                                      "provoke:" line once per spike level and tier.
-- Later parts (the intensity director, P4) change a live plane's values with enemyProvoke(p, provokeWant(...)).
-- Writes read back (0.70.2's log); whether the game's provoke decision uses them is untested.
provokeWant, enemyProvoke, enemySpike, provokeStockWant = nil, nil, nil, nil
do
local provokeSaid = {}
local FIELDS = { { "ProvokeConditionConeAngle", "cone" }, { "ProvokeDeterminationTime", "time" },
                 { "SurroundPursuitMinRange", "smin" }, { "SurroundPursuitMaxRange", "smax" } }
local function isTier(t) return type(t) == "table" and t.name ~= nil and t.rank ~= nil end   -- (a CFG.tiers.list entry)
local function stricter(a, b) if a == nil then return b elseif b == nil then return a end return math.min(a, b) end
local function said(x)                             -- "60 deg / 1.5 s / 40-100 m"
    local t = {}
    if x.cone then t[#t + 1] = string.format("%g deg", x.cone) end
    if x.time then t[#t + 1] = string.format("%g s", x.time) end
    if x.surround then t[#t + 1] = string.format("%g-%g m", x.surround[1], x.surround[2]) end
    return table.concat(t, " / ")
end
function provokeWant(round, tier, level)
    local ai = CFG.ai or {}
    level = level or levelFor(round)
    local sk = spikeCfg(level)
    local s = { cone = sk.provoke_cone_deg, time = sk.provoke_time_s, surround = sk.surround_m }
    local t, test = nil, false
    if tier and (not isTier(tier) or ai.tier_provoke ~= false) then          -- (a special's own: whatever the switch)
        t = { cone = tier.provoke_cone_deg, time = tier.provoke_time_s, surround = tier.surround_m }
        if isTier(tier) and (t.cone or t.time) then                           -- the A/B test values: every tier with its own
            if (ai.provoke_cone_deg or 0) > 0 then t.cone, test = ai.provoke_cone_deg, true end
            if (ai.provoke_time_s or 0) > 0 then t.time, test = ai.provoke_time_s, true end
        end
        if not (t.cone or t.time or t.surround) then t = nil end
    end
    local hasS = s.cone or s.time or s.surround
    if not (t or hasS) then return nil end
    local w, strict = { level = level }, ai.provoke_stricter ~= false
    if t and strict then
        w.cone, w.time = stricter(s.cone, t.cone), stricter(s.time, t.time)
        if s.surround and t.surround then
            w.surround = { math.min(s.surround[1], t.surround[1]), math.min(s.surround[2], t.surround[2]) }
        else
            w.surround = t.surround or s.surround
        end
    else                                               -- (the tier's, field by field, over the spike's: as before P5)
        w.cone, w.time, w.surround = (t and t.cone) or s.cone, (t and t.time) or s.time, (t and t.surround) or s.surround
    end
    local from = {}
    if t then from[#from + 1] = (isTier(tier) and tier.name or "special") .. " " .. said(t) .. (test and " (CFG.ai test values)" or "") end
    if hasS then from[#from + 1] = "spike " .. level .. " " .. said(s) end
    w.src = table.concat(from, ", ") .. ((t and hasS) and (strict and ": the stricter" or ": the tier's over the spike's") or "")
    return w
end
function enemyProvoke(p, want)
    if not (p and want and valid(p.obj)) then return 0, "", "", {} end
    local set, stock = p.provokeSet or {}, p.provokeStock or {}
    local sr = want.surround
    local value = { cone = want.cone, time = want.time, smin = sr and sr[1] * 100 or nil, smax = sr and sr[2] * 100 or nil }
    local before, writes, fields, n = {}, {}, {}, 0
    for _, f in ipairs(FIELDS) do
        local field, key = f[1], f[2]
        local v = value[key]
        if v ~= nil and set[key] ~= v then
            local okR, old = pcall(function() return p.obj[field] end)
            if set[key] == nil and stock[key] == nil and okR and type(old) == "number" then stock[key] = old end
            before[#before + 1] = field .. " " .. (okR and tostring(old) or "?")
            local okW, e = pcall(function() p.obj[field] = v end)
            if okW then set[key], n = v, n + 1; fields[#fields + 1] = field end
            writes[#writes + 1] = okW and (field .. " " .. tostring(v)) or (field .. " FAILED: " .. tostring(e))
        end
    end
    p.provokeSet, p.provokeWant, p.provokeStock = set, want, stock
    return n, table.concat(before, ", "), table.concat(writes, ", "), fields
end
function provokeStockWant(p, level)
    local st = p and p.provokeStock
    if not (st and next(st)) then return nil end
    return { level = level, cone = st.cone, time = st.time, src = "the game's own",
             surround = (st.smin and st.smax) and { st.smin / 100, st.smax / 100 } or nil }
end
function enemySpike(p, round, tier)
    if p.spiked ~= nil or not round then return end
    local w = provokeWant(round, tier)
    p.spiked = w and w.level or levelFor(round)
    if not w then return end
    local n, before, writes, fields = enemyProvoke(p, w)
    local who = isTier(tier) and tier.name or (tier and "special" or "no tier")
    local key = w.level .. "|" .. who
    if provokeSaid[key] and not writes:find("FAILED", 1, true) then return end
    provokeSaid[key] = true
    local back = {}
    for _, field in ipairs(fields) do
        local okB, v = pcall(function() return p.obj[field] end)
        back[#back + 1] = okB and tostring(v) or "?"
    end
    log(string.format("provoke: round %d, spike level %d, %s (%s): was %s; now %s; reads back %s (%s)", round, w.level, who,
        p.name, before ~= "" and before or "-", writes ~= "" and writes or "-", #back > 0 and table.concat(back, ", ") or "-",
        w.src))
end
end

-- The mission row to fly for aircraft `a`: its _sv row when that was ready before this level loaded.
function searchAircraft(a, level)
    local sv = SR.usable[a]
    if not (sv and SR.tables) then return a end
    local _, have = dtCall(SR.tables.npc, "FindRow", SR.npcRow[a])
    if have ~= nil then
        local lv = level and level > 0 and SR.usableLevels and SR.usableLevels[a] and SR.usableLevels[a][level]
        return lv or sv
    end
    log("search: DT_NPC row " .. SR.npcRow[a] .. " is gone (the table was reloaded?); " .. a .. " flies stock this level")
    SR.usable[a], SR.ready[a], SR.done, SR.tries = nil, nil, false, 0
    return a
end
