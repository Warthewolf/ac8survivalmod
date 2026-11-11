-- sv_config_ini.lua: the shipped settings (CFG_DEFAULTS), survival.ini and survival_config.lua over them, the
-- difficulty preset, and what's built on CFG: the behaviour probe's tables, ACE, TIER, ROLE and the game's own Lua
-- (GLS). Piece 5 of 5 of sv_config.lua's family (sv_config.lua, sv_config_specials.lua, sv_config_arc.lua,
-- sv_config_subs.lua, sv_config_ini.lua), split by tools/lua_split_part.py and run by main.lua right after the piece
-- before it: a name another part uses is a global of this mod's Lua state, its own helpers stay local.
for n = 1, 8 do for k = 0, 2 do CFG.pool[#CFG.pool + 1] = string.format("ERA_Unit_%02d_Dep_Air%d", n, k) end end
-- (THE DECOY, sv_decoy.lua: in the rotation from its first build; added after the table, before CFG_DEFAULTS and the ini,
-- so it's a shipped default like the rest, and the packaging's string edits of the rotation's literal (tools/novalka.py,
-- tools/nospaceport.py) still find it as they expect)
CFG.specials.rotation[#CFG.specials.rotation + 1] = "decoy"
function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
-- The shipped settings, before survival.ini and survival_config.lua change them: Survival COOP's host sends its
-- differences from these to every joiner (sv_coop.lua, M.sendSettings)
CFG_DEFAULTS = deepCopy(CFG)
-- The player's settings: config/survival.ini (BUILD_PLAN Milestone 4). Releases ship config/survival.default.ini; the
-- first run copies it to survival.ini, which an update never overwrites. A [section] names a CFG table (dots for
-- nested ones, any case; INI_ALIAS gives the friendly names), `key = value` sets a field that exists there: a number,
-- true / false, text, or a comma list for a list field. [squadrons] keys are squadron sizes (value: from_round).
-- Read once at start (the main menu builds Survival's NPC rows from CFG), so changes need a game restart.
do                                 -- (its helpers stay inside: the main chunk's 200-local limit)
local INI_ALIAS = { rounds = "", zollars = "credits", bombers = "airfield.bombers", ["bombers.ping"] = "airfield.bombers.ping", skill = "tiers",
                    ["skill.difficulty"] = "tiers.rank_add", enemy_missiles = "missiles", enemy_guns = "guns",
                    ["ammo.casual"] = "ammo.presets.casual", ["ammo.standard"] = "ammo.presets.standard",
                    ["ammo.ace"] = "ammo.presets.ace",
                    fishing = "specials.fishing", festival = "specials.festival",      -- (0.74.0: sv_fishing / sv_festival)
                    ["fishing.catch"] = "specials.fishing.catch", ["fishing.kg"] = "specials.fishing.kg",
                    -- TEST ONLY BEGIN (the lightning Anomaly's sections: sv_anomalies.lua THUNDER, test builds only)
                    thunder = "specials.thunder", ["thunder.storm"] = "specials.thunder.storm",
                    ["thunder.fx"] = "specials.thunder.fx", ["thunder.test"] = "specials.thunder.test", ["thunder.strike"] = "specials.thunder.strike",
                    -- TEST ONLY END
                    -- (0.35.3's name for the aircraft repair, still in the survival.ini files it extended)
                    ["shop.airfield.aircraft"] = "shop.items.RepairAircraft" }
-- sections of things since taken out, still in older survival.ini files: skipped without a warning
local INI_RETIRED = { ["shop.shipfreedom"] = true, ["allies.ships.freedom"] = true }
local function iniSection(name)
    local path = name:lower()
    path = INI_ALIAS[path] or path:gsub("^shop%.", "shop.items.")
    local t = CFG
    for part in path:gmatch("[^%.]+") do
        local found = nil
        for k, v in pairs(t) do if type(k) == "string" and k:lower() == part:lower() and type(v) == "table" then found = v end end
        if not found then return nil end
        t = found
    end
    return t
end
local function iniValue(old, s)
    if type(old) == "boolean" then
        local b = ({ ["true"] = true, yes = true, on = true, ["1"] = true, ["false"] = false, no = false, off = false, ["0"] = false })[s:lower()]
        return b, b ~= nil
    elseif type(old) == "number" then
        local n = tonumber(s)
        if n and math.type(old) == "integer" then n = math.tointeger(n) or math.floor(n + 0.5) end
        return n, n ~= nil
    elseif type(old) == "string" then
        return s, true
    elseif type(old) == "table" and #old > 0 and type(old[1]) ~= "table" then
        local list = {}
        for item in s:gmatch("[^,]+") do
            item = item:match("^%s*(.-)%s*$")
            if type(old[1]) == "number" then item = tonumber(item); if not item then return nil, false end end
            list[#list + 1] = item
        end
        return list, #list > 0
    end
    return nil, false
end
-- Settings an update added to survival.default.ini (a key or a section survival.ini doesn't have, switched on or off)
-- are appended to survival.ini, switched off, with the comment lines above them, so players find them there (user,
-- 2026-10-22: "I couldn't find it in the ini"). Nothing the player wrote is changed.
local function mergeDefaults(dir)
    local d = io.open(dir .. "survival.default.ini", "r")
    local u = io.open(dir .. "survival.ini", "r")
    if not (d and u) then if d then d:close() end; if u then u:close() end; return end
    local have, sec = {}, ""
    for line in u:lines() do
        local h = line:match("^%s*%[%s*(.-)%s*%]")
        if h then sec = h:lower()
        else
            local k = line:match("^%s*;?%s*([%w_]+)%s*=")
            if k then have[sec .. "/" .. k:lower()] = true end
        end
    end
    u:close()
    local out, comments, cur, curShown = {}, {}, "", false
    for line in d:lines() do
        local h = line:match("^%s*%[%s*(.-)%s*%]")
        local k = not h and line:match("^%s*;?%s*([%w_]+)%s*=")
        if h then
            cur, curShown, comments = h, false, {}
        elseif k then
            if cur ~= "" and not have[cur:lower() .. "/" .. k:lower()] then
                if not curShown then out[#out + 1] = ""; out[#out + 1] = "[" .. cur .. "]"; curShown = true end
                for _, c in ipairs(comments) do out[#out + 1] = c end
                out[#out + 1] = line:match("^%s*;") and line or (";" .. line)
            end
            comments = {}
        elseif line:match("^%s*;") then
            comments[#comments + 1] = line
        else
            comments = {}
        end
    end
    d:close()
    if #out == 0 then return end
    local w = io.open(dir .. "survival.ini", "a")
    if not w then return end
    w:write("\n; ---- settings added by Survival Mode " .. VERSION .. " (from survival.default.ini) ----\n")
    w:write(table.concat(out, "\n") .. "\n")
    w:close()
    log("config: added the new settings to survival.ini (" .. #out .. " lines)")
end

local function loadIni()
    local dir = SCRIPT_DIR .. "..\\config\\"
    pcall(mergeDefaults, dir)
    local f = io.open(dir .. "survival.ini", "r")
    if f then
        -- format 1 (Lua 0.24-0.25) copied every default as a live setting, which pinned them: a later default change never
        -- reached the player. Format 2 lists them switched off. An old file is kept as survival.ini.old.
        local text = f:read("a") or ""
        -- A file without the format line that sets only a few things was made by hand (a player who wrote just
        -- "[coop] role = join" before the game made one): it's kept and marked, not replaced (user, 2026-10-25:
        -- friends set role = join and still hosted). A format 1 file set every one of the ~300 settings.
        local live = 0
        for l in text:gmatch("[^\r\n]+") do if l:match("^%s*[%w_]+%s*=") then live = live + 1 end end
        if not text:find("survival.ini format 2", 1, true) and live < 60 then
            f:close(); f = nil
            local w = io.open(dir .. "survival.ini", "w")
            if w then
                w:write("; AC8 Survival Mode settings  (survival.ini format 2; this file was made by hand)\n" .. text)
                w:close()
                log("config: survival.ini has no format line and " .. live .. " settings (made by hand?): kept as it is")
            end
            f = io.open(dir .. "survival.ini", "r")
        elseif not text:find("survival.ini format 2", 1, true) then
            f:close(); f = nil
            os.remove(dir .. "survival.ini.old")
            local ok = os.rename(dir .. "survival.ini", dir .. "survival.ini.old")
            log("config: survival.ini is from an older version; " .. (ok and "kept as survival.ini.old, a new one is made"
                or "could not rename it, so it is used as it is"))
            if not ok then f = io.open(dir .. "survival.ini", "r") end
        else
            f:seek("set", 0)
        end
    end
    if not f then
        local d = io.open(dir .. "survival.default.ini", "r")
        if not d then return end
        local text = d:read("a"); d:close()
        local out = io.open(dir .. "survival.ini", "w")
        if out then out:write(text); out:close(); log("config: made config\\survival.ini from survival.default.ini") end
        f = io.open(dir .. "survival.ini", "r")
        if not f then return end
    end
    local t, section, set, bad, n = nil, nil, 0, {}, 0
    for line in f:lines() do
        n = n + 1
        line = line:gsub("^\239\187\191", ""):gsub("%s*[;#].*$", ""):match("^%s*(.-)%s*$")
        local sec = line:match("^%[%s*(.-)%s*%]$")
        if sec then
            section, t = sec, iniSection(sec)
            if not t and not INI_RETIRED[sec:lower()] then bad[#bad + 1] = string.format("line %d: no section [%s]", n, sec) end
        elseif line ~= "" then
            local key, val = line:match("^([^=]-)%s*=%s*(.*)$")
            if not key then
                bad[#bad + 1] = string.format("line %d: not 'key = value'", n)
            elseif t then
                local ok = false
                if t == CFG.squadrons then
                    for _, q in ipairs(t) do
                        if tostring(q.size) == key then local v = tonumber(val); if v then q.from_round, ok = v, true end end
                    end
                else
                    local field = nil
                    for k in pairs(t) do if type(k) == "string" and k:lower() == key:lower() then field = k end end
                    -- ((review of 0.73.80) open maps: any plane code, not only the shipped ones (a modded plane's
                    -- stock fallback or its own blueprint's path), by its code in lower case)
                    local openMap = CFG.coop and (t == CFG.coop.real_fallback or t == CFG.coop.real_paths)
                    if field then
                        local v; v, ok = iniValue(t[field], val)
                        if ok then t[field] = v end
                    elseif openMap and val ~= "" and #val <= 512 and key:match("^[%w_%-]+$") then
                        t[key:lower()], ok = val, true
                    end
                end
                if ok then set = set + 1 else bad[#bad + 1] = string.format("line %d: [%s] %s = %s not used", n, section, key, val) end
            end
        end
    end
    f:close()
    log(string.format("config: survival.ini, %d settings%s", set, #bad > 0 and ("; " .. table.concat(bad, "; ")) or ""))
end
    local ok, err = pcall(loadIni)
    if not ok then log("config: survival.ini could not be read: " .. tostring(err)) end

-- A setting picked in game (the main menu's settings rows, sv_coop.lua) saved to survival.ini: its line in [section]
-- (switched off or not) becomes `key = value`, a later live line for it is switched off, and a missing one is added
-- under the section. Returns true when the file was written.
function iniSet(section, key, value)
    local path = SCRIPT_DIR .. "..\\config\\survival.ini"
    local lines, f = {}, io.open(path, "r")
    if f then for l in f:lines() do lines[#lines + 1] = l end; f:close() end
    local sec, at, secAt = nil, nil, nil
    for i, l in ipairs(lines) do
        local h = l:match("^%s*%[%s*(.-)%s*%]")
        if h then
            sec = h:lower()
            if sec == section:lower() and not secAt then secAt = i end
        elseif sec == section:lower() then
            local k = l:match("^%s*;?%s*([%w_]+)%s*=")
            if k and k:lower() == key:lower() then
                if not at then at = i elseif not l:match("^%s*;") then lines[i] = ";" .. l end
            end
        end
    end
    local line = key .. " = " .. tostring(value)
    if at then lines[at] = line
    elseif secAt then table.insert(lines, secAt + 1, line)
    else lines[#lines + 1] = ""; lines[#lines + 1] = "[" .. section .. "]"; lines[#lines + 1] = line end
    local w = io.open(path, "w")
    if not w then return false end
    w:write(table.concat(lines, "\n") .. "\n")
    w:close()
    return true
end
end
do  -- optional overrides: Scripts/survival_config.lua returning a table with any of the keys above. Lists (aircraft,
    -- pool, ...) are replaced whole; keyed tables (hud, hud.text) are merged, so one field can be changed alone.
    local function merge(into, from)
        for k, v in pairs(from) do
            if type(v) == "table" and type(into[k]) == "table" and #into[k] == 0 and next(into[k]) ~= nil then merge(into[k], v)
            else into[k] = v end
        end
    end
    local ok, user = pcall(require, "survival_config")
    -- (any survival_config.lua found, even one that failed or returned nothing, ran code of its own: the leaderboard
    -- doesn't rank a run with one, LB.edited in sv_leaderboard.lua)
    if ok or not tostring(user):find("module 'survival_config' not found", 1, true) then
        CFG_USER_FILE = "survival_config.lua"
        -- ONLINE ONLY BEGIN (tools/edition.py)
        log("config: a survival_config.lua is there: runs with it aren't ranked on the leaderboard")
        -- ONLINE ONLY END
    end
    if ok and type(user) == "table" then
        merge(CFG, user)
        log("config: survival_config.lua loaded")
    end
end
math.randomseed(os.time())

-- The difficulty preset (casual / standard / ace, CFG.ammo.by_difficulty) and the game's difficulty number.
presetCache = { at = -100 }
function presetName()
    local now = os.clock()
    if now - presetCache.at > 30 then           -- kept 30 s (Select Difficulty is hidden in Survival's pause menu)
        local dm = type(difficultyManager) == "function" and difficultyManager() or nil   -- ((0.73.79) kept: sv_core.lua; nil while not found, as a held walk was)
        local ok, d = pcall(function() return dm.CurrentDifficulty end)
        if ok and d ~= nil then
            presetCache.at, presetCache.name, presetCache.d = now, CFG.ammo.by_difficulty[d] or "standard", d
        else                                    -- (0.73.73) not found (a held walk, or none): the last answer kept, asked
            presetCache.at = now - 25           -- again in 5 s, not on every call (each ask is a walk over every object)
            presetCache.name = presetCache.name or "standard"
        end
    end
    return presetCache.name, presetCache.d
end

---------------------------------------------------------------------------------------------------- behaviour probe
-- First step towards Survival's own (learning) enemy behaviour (BUILD_PLAN; docs/re/AI_BEHAVIOURS.md). One test,
-- three questions (CFG.probe):
--  1. Does an enemy run our own behaviour script? The first flight of every round flies a copy of Mission 22's MiG-29
--     whose pursue slot is LA_SV_ProbePursue (barrel roll right, then left, then the stock pursuit, every attack run):
--     odd rounds the script from Survival's package (/Game/LuaSource/SurvivalMode/AI), even rounds a LuaScript object made
--     here at run time from Scripts/ai/LA_SV_ProbePursue.lua. Rows: DT_NPC_LuaSet NLID_SV_ProbePkg/Rt (copies of
--     NLID_0000_CP) and DT_NPC SV_m29a_ProbePkg/Rt (OP1020_m29a_01) are added here at run time, as early as the main
--     menu; the mission rows sv_probe_pkg/rt are in Survival's own NPC table (tools/build_survival.py NPC_EXTRA),
--     because the spawner caches that table's aircraft when the level starts. A variant is only flown when its rows
--     were in before the level loaded.
--  2. Does a live write to an enemy's PilotRank stick? Each enemy's rank is logged, set to CFG.probe.rank, and read
--     again 10 s later.
--  3. Can a kill be attributed? Each enemy's last attacker (K2_GetLastDamagedByAttacker), the aspect and the player's
--     ammo use in the seconds before it went down are logged.
PROBE_TABLES = {
    { key = "luaset",  path = "/Game/Datatables/AI/NPC/LuaSet/DT_NPC_LuaSet.DT_NPC_LuaSet",
      src = "NLID_0000_CP",   row = "NLID_SV_Probe" },
    { key = "npc",     path = "/Game/Datatables/AI/NPC/DT_NPC.DT_NPC",
      src = "OP1020_m29a_01", row = "SV_m29a_Probe" },
}
PROBE_MISSION_ROW = { Pkg = "sv_probe_pkg", Rt = "sv_probe_rt" }   -- in DT_SV_NpcMission (build time)
-- The game's require("A.B.C") loads the LuaScript at /Game/LuaSource/A/B/C with StaticLoadObject and runs its Code
-- (AceCombat8.exe 0x144eb8ce0), so the packaged script sits at that path. The run-time one is put straight into the
-- game's Lua (package.loaded, section "the game's own Lua"), so its LuaScript object only carries the module name.
PROBE_PKG_SCRIPT = "/Game/LuaSource/SurvivalMode/AI/LA_SV_ProbePursue.LA_SV_ProbePursue"
PROBE_PKG_MODULE = "SurvivalMode.AI.LA_SV_ProbePursue"
PROBE_RT_MODULE  = "SurvivalMode.AI.LA_SV_ProbePursueRt"
PR = { ready = {}, usable = {}, scripts = {}, tries = 0, ammo = {} }   -- rows stay in the tables across levels
SR = { ready = {}, usable = {}, tries = 0 }   -- enemy search rows (section "enemy search" below)
-- Difficulty spikes (CFG.spikes): the level of round `round` (0 = none yet), its settings, and its rows' suffix.
SPIKE_SUFFIX = { [0] = "", "b", "c", "d" }      -- tools/build_survival.py SPIKE_SUFFIXES
-- CFG.aces' airframes per tier (tools/build_survival.py ACES, same keys) and their rows: a lead and a wing mission row
-- (sv_ace_<tier>_<key>_l / _w, with _sv[b|c|d] copies like the search aircraft), DT_NPC rows SV_Ace_<tier>_<key>_L / _W
-- (DT_SV_NpcRows, added at the main menu) and text keys SV_Ace_<tier>_<key> (the ace) / SV_Sqn_<tier> (the squadron).
ACE = {
    roster = { mercenary = { "f15c", "su35", "typhoon" }, legend = { "su47", "rafale" }, demon = { "f22a", "su57" },
               phantom = { "su57", "typhoon", "su47" }, reaper = { "su57", "f22a", "typhoon", "rafale", "adfx02" },
               anomaly = { "f04e" },               -- the Anomaly's MINDRIPPER and guards (not a tier: never a flight's)
               glitch = { "e18g" },                -- AB.L..IN (CFG.specials.glitch; not a tier either)
               valka = { "x40a" } },               -- VALKA (CFG.specials.valka; not a tier either)
    row = function(tier, key, part) return "sv_ace_" .. tier .. "_" .. key .. "_" .. part end,
    -- airframes from Online Mode (tools/build_survival.py ACE_MODELS): their model row (DT_SV_ModelRows) goes into the
    -- campaign's DT_NPC_Model first, and their name (the model's GameObjectDisplayName01) is Survival's text
    models = { adfx02 = { row = "SV_Model_adfx", key = "SV_Ac_adfx", name = "ADFX-02" } },
    model_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_ModelRows.DT_SV_ModelRows",
    model_table = "/Game/Datatables/AI/NPC/Model/DT_NPC_Model.DT_NPC_Model",
}
-- The ace squadrons' blink spots (behaviour roadmap P9, CFG.aces.flight <tier>.blink and the "blink" opener; build data,
-- outside CFG: tools/survival_events.py WRAITH_BLINK_*, whose build checks these): RE_SV_WraithBlink<K><J>, K the
-- flight's pool index as a letter (A = ERA_Unit_01_Dep_Air0), J the bearing's (A = 0 deg, world: 0 = +X, AB.L..IN's
-- convention), every STEP_DEG round, RING_M from the player at their height, facing them; one set per flight of the
-- ROLE group (its lead, object 0, only: the squadrons that blink fly that group's flights, and the events stay few).
ACE.BLINK = { STEP_DEG = 45, RING_M = 1000, ROLE = "duelist" }
function spikeLevel(round)
    local sp = CFG.spikes
    if not sp.enabled or not round or round < 1 or #sp.levels == 0 then return 0 end
    return math.min(#sp.levels, #SPIKE_SUFFIX, (round - 1) // math.max(1, math.floor(sp.every)))
end
function spikeCfg(level) return level > 0 and CFG.spikes.levels[level] or {} end
-- The difficulty level the enemies of round `round` fly (their fire-control rows, rank_min, post_stall_all, provoke,
-- aircraft_add): the intensity director's (CFG.intensity.level, sv_director.lua DIR.level: spikeLevel's the ceiling, at
-- most level.max_drop under it while the room's been under heavy pressure), else spikeLevel's
function levelFor(round)
    if DIR and DIR.level then
        local ok, l = pcall(DIR.level, round)
        if ok and type(l) == "number" then return l end
    end
    return spikeLevel(round)
end
-- The tier index (CFG.tiers.list) a flight spawning in round `round` flies: the round's, one higher at promote_chance.
-- The skill tiers (CFG.tiers): TIER.index(round) the round's own tier, TIER.pick(round) that or (promote_chance) the
-- one above it, TIER.pay(base, i) a kill's zollars at tier i (CFG.credits.tier_pay, rounded to 10) and its multiplier.
TIER = {}
function TIER.index(round)
    local i = 1
    for k, t in ipairs(CFG.tiers.list) do if math.max(round or 1, 1) >= t.from_round then i = k end end
    return i
end
-- How many rounds `round` is past CFG.late.from_round (0 before it, 1 in it), or 0 when CFG.late is off.
function TIER.lateRounds(round)
    local l = CFG.late
    if not (l and l.enabled and round) then return 0 end
    return math.max(0, round - l.from_round + 1)
end
-- The chance a pilot flies one tier above the round's: CFG.tiers.promote_chance, plus CFG.late's growth.
function TIER.promoteChance(round)
    local l, n = CFG.late, TIER.lateRounds(round)
    local p = CFG.tiers.promote_chance
    if n > 0 then p = math.max(p, math.min(l.promote_max or 1, p + (l.promote_per_round or 0) * n)) end
    return p
end
-- An enemy aircraft's health multiplier in round `round` (CFG.late), 1 before it.
function TIER.lateHealthX(round)
    local l, n = CFG.late, TIER.lateRounds(round)
    if n <= 0 then return 1 end
    return math.min(l.health_max_x or 1, 1 + (l.health_per_round or 0) * n)
end
-- Late rounds' growth (CFG.late aircraft_from_round on; behaviour roadmap P8): how many rounds `round` is into it (0
-- before it, 1 in it), or 0 when CFG.late or its grow is off or aircraft_from_round is 0. Pure maths of CFG
-- (tools/checks/late_rounds_test.lua reproduces the thesis' table with these).
function TIER.growRounds(round)
    local l = CFG.late
    if not (l and l.enabled and l.grow ~= false and round and (l.aircraft_from_round or 0) > 0) then return 0 end
    return math.max(0, round - l.aircraft_from_round + 1)
end
-- The most aircraft round `round` brings, before the menu's ENEMY AIRCRAFT % and co-op: CFG.max_aircraft, from
-- late.aircraft_from_round aircraft_per_round more a round up to late.max_aircraft (never below CFG.max_aircraft)
function TIER.roundCap(round)
    local l, n, cap = CFG.late, TIER.growRounds(round), CFG.max_aircraft
    if n > 0 then cap = math.max(cap, math.min(cap + (l.aircraft_per_round or 0) * n, l.max_aircraft or cap)) end
    return cap
end
-- Round `round`'s aircraft: aircraft_round1, aircraft_per_round more a round and the difficulty spike's aircraft_add,
-- within the round's cap (the thesis: "spikes still add their aircraft_add on top, within the cap"). level: the spike
-- level whose aircraft_add counts (startRound's levelFor: the intensity director's), default spikeLevel(round)'s
function TIER.roundBudget(round, level)
    local sk = spikeCfg(level or spikeLevel(round))
    return math.min(CFG.aircraft_round1 + (round - 1) * CFG.aircraft_per_round + (sk.aircraft_add or 0), TIER.roundCap(round))
end
-- A co-op room's most aircraft in round `round` (COOP.more's cap, sv_rounds.lua startRound): CFG.coop.max_aircraft,
-- grown by as many as one player's round cap has grown (TIER.roundCap), up to late.coop_max_aircraft (never below
-- coop.max_aircraft): rounds 1-25 keep co-op's 60 whatever the room's size (the thesis: "rounds 15-25 keep today's
-- cap"), then 63, 66 ... 80 by round 32 with the shipped settings
function TIER.coopCap(round)
    local base = tonumber(CFG.coop and CFG.coop.max_aircraft) or CFG.max_aircraft
    local grow = TIER.roundCap(round) - CFG.max_aircraft
    if grow <= 0 then return base end
    return math.max(base, math.min(base + grow, tonumber(CFG.late.coop_max_aircraft) or base))
end
-- The most fighters a round can field: the pool's flights (CFG.pool; 2 / 4 / 6-ships by their _AirN suffix, as
-- sv_spawn.lua flightSize) less the probes' (CFG.probe.units, never picked): 86 with the shipped settings. A raid's
-- bombers come on top. Past it a round flies "pool short" (sv_rounds.lua); the menu's ENEMY AIRCRAFT help stops there.
function TIER.poolMost()
    local probe, n = {}, 0
    for _, u in pairs(CFG.probe and CFG.probe.units or {}) do probe[u] = true end
    for _, u in ipairs(CFG.pool) do
        if not probe[u] then n = n + (({ ["0"] = 2, ["1"] = 4, ["2"] = 6 })[u:sub(-1)] or 2) end
    end
    return n
end
-- The most aircraft a wave of round `round` holds at preset `preset` (casual / standard / ace), before the menu's % and
-- co-op: CFG.waves max_up_by_preset (or max_up), from late.aircraft_from_round max_up_per_round more a round up to
-- late.max_up_cap[preset] (never below the preset's own; a preset without a cap doesn't grow)
function TIER.maxUp(round, preset)
    local w, l, n = CFG.waves, CFG.late, TIER.growRounds(round)
    local up = (w.max_up_by_preset and w.max_up_by_preset[preset]) or w.max_up
    local cap = nil
    if n > 0 and type(l.max_up_cap) == "table" then cap = tonumber(l.max_up_cap[preset]) end
    if cap then up = math.max(up, math.min(up + (l.max_up_per_round or 0) * n, cap)) end
    return up
end
-- The game's player-attack throttle preset round `round` asks for (CFG.late.pressure): the preset of the latest
-- from_round band it's in, "B" (ATTACK_BASE, the mission start's) before them; nil when CFG.late or its pressure is
-- off (then nothing is fired). Letters only of TIER.PRESSURE_PRESETS, tools/survival_events.py PRESSURE (its build
-- checks the two agree), any case in survival.ini. TIER.PRESSURE_OWN: the specials whose event records set their own
-- throttle and put B back as they end (none fired in their round; sv_rounds.lua, sv_coop.lua hostSync).
TIER.PRESSURE_PRESETS = "ABCD"
TIER.PRESSURE_OWN = { anomaly = true, valka = true }
function TIER.pressure(round)
    local l = CFG.late
    local pr = l and l.pressure
    if not (l and l.enabled and type(pr) == "table" and pr.enabled and round) then return nil end
    local want, at = "B", -math.huge
    local froms, presets = type(pr.from_round) == "table" and pr.from_round or {}, type(pr.preset) == "table" and pr.preset or {}
    for i, r in ipairs(froms) do
        local x = type(presets[i]) == "string" and presets[i]:upper() or ""
        if type(r) == "number" and round >= r and r >= at and #x == 1 and TIER.PRESSURE_PRESETS:find(x, 1, true) then
            want, at = x, r
        end
    end
    return want
end
-- The fighter roles' build data (behaviour roadmap P1, CFG.roles; docs/re/BEHAVIOUR_DIRECTOR.md unit 5), outside CFG so
-- survival.ini and co-op's settings can't change it: ROLE_BY_FLIGHT[NN] is pool flight NN's role (ERA_Unit_NN_Dep_Air0-2,
-- tools/survival_events.py ROLE_BY_FLIGHT, which its build checks against this), ROLE.ROWS each role's behaviour row
-- (DT_SV_NpcMission; the Wolf trap's too) and ROLE.SETS its behaviour set (CFG.behaviour_sets), ROLE.LANCER_TOP_M the
-- Lancer flights' altitude band top (survival_events.LANCER_MAX_ALT_M, checked the same way). ROLE.of[unit] = its role,
-- ROLE.units[role] = its flights. Pure maths here; what a level has and the draw are sv_spawn.lua's.
ROLE_BY_FLIGHT = { "duelist", "duelist", "lancer", "lancer", "wolf", "wolf", "skirm", "skirm" }
ROLE = { LIST = { "duelist", "lancer", "wolf", "skirm" },
         ROWS = { lancer = "sv_role_lancer", wolf = "sv_role_wolf_lead", wolf_wing = "sv_role_wolf_wing", skirm = "sv_role_skirmish" },
         SETS = { duelist = "NLID_SV_Fighter", lancer = "NLID_SV_Lancer", wolf = "NLID_SV_WolfLead", wolf_wing = "NLID_SV_WolfWing",
                  skirm = "NLID_SV_Skirmisher" },
         LANCER_TOP_M = 9000, of = {}, units = {} }
for nn, r in ipairs(ROLE_BY_FLIGHT) do
    ROLE.units[r] = ROLE.units[r] or {}
    for k = 0, 2 do
        local u = string.format("ERA_Unit_%02d_Dep_Air%d", nn, k)
        ROLE.of[u] = r
        ROLE.units[r][#ROLE.units[r] + 1] = u
    end
end
-- A Wolf flight's object k is the trap (held until sprung, the trap's row): the odd ones (survival_events.wolf_held).
function ROLE.wolfHeld(k) return type(k) == "number" and k % 2 == 1 end
-- The role weights round `round` draws by: in an ace round (ace true, or its tier's key) the squadron's own roles (P9's
-- ace personalities: CFG.aces.flight <tier>.roles, band "ace:<tier>") or CFG.roles.ace_mix (band "ace"), else mix's band
-- of the latest from_round the round has reached (no band yet: duelists only). Returns { role = weight } and the band.
function ROLE.mixFor(round, ace)
    local c = CFG.roles
    local w = {}
    local pc = CFG.aces and CFG.aces.personality
    local fl = type(ace) == "string" and CFG.aces.enabled and type(pc) == "table" and pc.enabled ~= false
        and type(CFG.aces.flight) == "table" and CFG.aces.flight[ace]
    if type(fl) == "table" and type(fl.roles) == "table" then
        local any = false
        for _, r in ipairs(ROLE.LIST) do
            w[r] = math.max(0, tonumber(fl.roles[r]) or 0)
            if w[r] > 0 then any = true end
        end
        if any then return w, "ace:" .. ace end
        w = {}                                       -- (every weight 0: ace_mix's)
    end
    if ace and type(c.ace_mix) == "table" then
        for _, r in ipairs(ROLE.LIST) do w[r] = math.max(0, tonumber(c.ace_mix[r]) or 0) end
        return w, "ace"
    end
    local m = type(c.mix) == "table" and c.mix or {}
    local froms, band, at = type(m.from_round) == "table" and m.from_round or {}, nil, -math.huge
    for i, r in ipairs(froms) do
        if type(r) == "number" and (round or 1) >= r and r >= at then band, at = i, r end
    end
    for _, r in ipairs(ROLE.LIST) do
        local list = type(m[r]) == "table" and m[r] or {}
        w[r] = band and math.max(0, tonumber(list[band]) or 0) or (r == "duelist" and 1 or 0)
    end
    return w, band and at or nil
end
-- `n` aircraft shared out by weights `w` in whole 2-ships: each role its whole share, the pairs left to roles drawn by
-- what's left of theirs (so over many rounds each gets its share: round 1's two 2-ships at 0.6 / 0.2 / 0.2 are a
-- duelist pair and a duelist, Lancer or Wolf pair 60 / 20 / 20 %, not always the same one). { role = aircraft }.
-- Weights all 0: every pair to the duelists.
function ROLE.quotas(n, w)
    local pairs2, total, q, rest = math.floor((n or 0) / 2), 0, {}, {}
    for _, r in ipairs(ROLE.LIST) do total = total + (w[r] or 0) end
    if total <= 0 then w, total = { duelist = 1 }, 1 end
    local given = 0
    for _, r in ipairs(ROLE.LIST) do
        local exact = pairs2 * (w[r] or 0) / total
        q[r] = math.floor(exact)
        given = given + q[r]
        if exact > q[r] then rest[#rest + 1] = { r = r, f = exact - q[r] } end
    end
    for _ = 1, pairs2 - given do
        if #rest == 0 then q.duelist = q.duelist + 1
        else
            local tot = 0
            for _, x in ipairs(rest) do tot = tot + x.f end
            local pick, roll = #rest, math.random() * tot
            for i, x in ipairs(rest) do roll = roll - x.f; if roll <= 0 then pick = i; break end end
            q[rest[pick].r] = q[rest[pick].r] + 1
            table.remove(rest, pick)
        end
    end
    for r, v in pairs(q) do q[r] = v * 2 end
    return q
end
-- Airframe `a`'s role by CFG.roles.aircraft (the first role that lists it), or nil.
function ROLE.ofAircraft(a)
    local ac = CFG.roles and CFG.roles.aircraft
    if type(ac) ~= "table" then return nil end
    for _, r in ipairs(ROLE.LIST) do
        for _, x in ipairs(type(ac[r]) == "table" and ac[r] or {}) do if x == a then return r end end
    end
    return nil
end
function TIER.pick(round)
    local tc, i = CFG.tiers, TIER.index(round)
    if i < #tc.list and math.random() < TIER.promoteChance(round) then i = i + 1 end
    return i
end
-- Kill pay's round multiplier (CFG.credits round_x_per_round / round_x_max).
function TIER.roundX(round)
    local c = CFG.credits
    return math.min(c.round_x_max or 1, 1 + (c.round_x_per_round or 0) * math.max(0, (round or 1) - 1))
end
function TIER.pay(base, i)
    local tp = CFG.credits.tier_pay or {}
    local x = (i and (tp[i] or tp[#tp])) or 1
    return math.floor(base * x / 10 + 0.5) * 10, x
end
-- (0.73.78, plan G4) The ace squadrons' health, rounds and rotation (CFG.aces health / round / rotation): pure maths of
-- CFG and the run's record (RUN.aceSinceTop, RUN.aceAt: sv_rounds.lua aceFlown keeps them), tools/checks/aces_test.lua.
-- ACE.healthFor(row, round): the health (HP, MaxHealth) of an aircraft on mission row `row` (sv_ace_<tier>_<key>_<l|w>,
-- any level's copy: _sv, _svb ...), its tier's key, "lead" or "wing", and the tier's wing and lead HP; nil for any other
-- row (the specials' MINDRIPPER guards, AB.L..IN, VALKA: not a tier of CFG.aces.health) or with it off. CFG.late's x on
-- top when health.late (round: the round it flies in).
function ACE.healthFor(row, round)
    local h = CFG.aces.health
    if not (CFG.aces.enabled and type(h) == "table" and h.enabled and type(row) == "string") then return nil end
    local tk, part = row:match("^sv_ace_(%a+)_%w+_([lw])")
    local t = tk and h[tk]
    if type(t) ~= "table" then return nil end
    local wing, lead = tonumber(t.wing), tonumber(t.lead)
    local hp = (part == "l") and lead or wing
    if not (hp and hp > 0) then return nil end
    local x = (h.late and round) and TIER.lateHealthX(round) or 1
    return hp * x, tk, part == "l" and "lead" or "wing", wing, lead
end
-- ACE.roundSize(round): an ace round's aircraft, the most of them up at once, the next wave's next_at and the two
-- ceilings (aircraft[2], up[2]), before the menu's % and co-op; nil when CFG.aces.round is off. aircraft[1] at the
-- first ace round (CFG.aces.first_round) + per_round a round past it, at most aircraft[2], whole 2-ships; up the same
-- way with up_per_round (rounded)
function ACE.roundSize(round)
    local c = CFG.aces.round
    if not (type(c) == "table" and c.enabled and round) then return nil end
    local a, u = type(c.aircraft) == "table" and c.aircraft or {}, type(c.up) == "table" and c.up or {}
    local a1, u1 = tonumber(a[1]) or 12, tonumber(u[1]) or 6
    local a2, u2 = math.max(a1, tonumber(a[2]) or a1), math.max(u1, tonumber(u[2]) or u1)
    local past = math.max(0, round - (tonumber(CFG.aces.first_round) or round))
    local top = math.max(2, math.floor(a2 / 2) * 2)
    local n = math.min(top, math.max(2, math.floor(math.min(a2, a1 + (tonumber(c.per_round) or 0) * past) / 2 + 0.5) * 2))
    local up = math.max(2, math.floor(math.min(u2, u1 + (tonumber(c.up_per_round) or 0) * past) + 0.5))
    return n, up, math.max(0, math.floor(tonumber(c.next_at) or 2)), top, math.max(2, math.floor(u2 + 0.5))
end
-- ACE.top(): the top squadron's key, the last tier with a line-up (Harvest's "reaper"), or nil
function ACE.top()
    for k = #CFG.tiers.list, 1, -1 do
        local n = CFG.tiers.list[k].name:lower()
        if ACE.roster[n] then return n end
    end
    return nil
end
-- ACE.squadFor(round, ti): the squadron an ace round of tier ti flies in round `round`: the tier's own, but from
-- rotation.from_round the top squadron only every top_every-th ace round (RUN.aceSinceTop: ace rounds flown since it
-- last flew one, nil before it ever has); between, one of rotation.standins (a line-up with a usable row, the one whose
-- last ace round is longest ago: RUN.aceAt, never flown first, ties by the list's order) at tier ti's skill. Returns its
-- key, true for a stand-in, and why (the log's)
function ACE.squadFor(round, ti)
    local t = ti and CFG.tiers.list[ti]
    local tk = t and t.name and t.name:lower()
    local r = CFG.aces.rotation
    if not (tk and type(r) == "table" and r.enabled and round and round >= (tonumber(r.from_round) or math.huge)) then return tk, false end
    if tk ~= ACE.top() then return tk, false end
    local every = math.max(1, math.floor(tonumber(r.top_every) or 2))
    local since = RUN and RUN.aceSinceTop
    if since == nil or since >= every - 1 then return tk, false end
    local best, bestAt = nil, nil
    for _, k in ipairs(type(r.standins) == "table" and r.standins or {}) do
        k = tostring(k):lower()
        local usable = false
        for _, key in ipairs(ACE.roster[k] or {}) do if SR and SR.usable and SR.usable[ACE.row(k, key, "w")] then usable = true end end
        if k ~= tk and usable and type(CFG.aces[k]) == "table" then
            local at = RUN and RUN.aceAt and RUN.aceAt[k] or -math.huge
            if not best or at < bestAt then best, bestAt = k, at end
        end
    end
    local sq = CFG.aces[tk] and CFG.aces[tk].squadron or tk
    if not best then return tk, false, string.format("no stand-in squadron can fly: %s again", tostring(sq)) end
    return best, true, string.format("%s flies every %d%s ace round, its last %d ago", tostring(sq), every,
        every == 2 and "nd" or every == 3 and "rd" or "th", since + 1)
end
-- An ace round (CFG.aces first_round / every; never a special round): the tier index whose squadrons fly it (the
-- round's tier, or the first one above it that has squadrons), or nil; then (0.73.78) the squadron that flies it at that
-- tier's skill, whether it stands in for the top one, and why (ACE.squadFor)
function aceRound(round, special)
    local a = CFG.aces
    if special or not (a.enabled and CFG.tiers.enabled and round >= a.first_round
        and (round - a.first_round) % math.max(1, math.floor(a.every)) == 0) then return nil end
    local ti = TIER.pick(round)
    for k = ti, #CFG.tiers.list do
        if ACE.roster[CFG.tiers.list[k].name:lower()] then return k, ACE.squadFor(round, k) end
    end
    return nil
end
function withLevel(base, over)                    -- a copy of `base` with `over`'s fields
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end

function readScript(file)
    local f = io.open(SCRIPT_DIR .. "ai\\" .. file, "r")
    if not f then return nil, "Scripts\\ai\\" .. file .. " not found" end
    local code = f:read("a"); f:close()
    return code
end

---------------------------------------------------------------------------------------------------- the game's own Lua
-- dlls/main.dll 0.8.0 (docs/re/GAME_LUA.md): SV_GameLua(code, name) runs a chunk in the game's Lua 5.3, the state
-- its AI behaviour scripts are built in, and returns "<status>\t<result>"; SV_GameLuaState() its address (0 while
-- the game has none). The plugin swallows every error in a behaviour script (its log is stripped from the shipping
-- game), so Survival installs a small helper there (SV_Instrument / SV_Report) that wraps a behaviour class's Ctor:
-- each build is counted and each error kept with its traceback (then raised as before). Run-time scripts are put in
-- package.loaded under their module name, which require() returns before it looks for an asset at all.
GLS = { L = 0, injected = {}, report = nil, created = false }
GAME_LUA_HELPER = [=[
SV_B = SV_B or { built = {}, errors = {}, nerr = 0 }
function SV_Instrument(name, C)
    if type(C) ~= "table" or rawget(C, "__sv_wrapped") then return C end
    local ctor = rawget(C, "Ctor")
    if type(ctor) == "function" then
        rawset(C, "Ctor", function(self, ...)
            SV_B.built[name] = (SV_B.built[name] or 0) + 1
            local ok, err = xpcall(ctor, debug and debug.traceback or tostring, self, ...)
            if not ok then
                SV_B.nerr = SV_B.nerr + 1
                if #SV_B.errors < 20 then SV_B.errors[#SV_B.errors + 1] = name .. ": " .. tostring(err) end
                error(err, 0)
            end
        end)
    end
    rawset(C, "__sv_wrapped", true)
    return C
end
function SV_Report()
    local t = {}
    for k, v in pairs(SV_B.built) do t[#t + 1] = k .. " x" .. v end
    table.sort(t)
    -- ("all fine" rather than "errors 0": the ACE8 Mod Launcher showed every such line flagged, user 2026-10-30)
    local s = "built " .. (#t > 0 and table.concat(t, ", ") or "nothing yet") .. "; "
        .. (SV_B.nerr == 0 and "all fine" or (SV_B.nerr .. " failed"))
    for i, e in ipairs(SV_B.errors) do s = s .. "\n    [" .. i .. "] " .. e end
    return s
end
return "helper in"
]=]
GAME_LUA_DIAG = [=[
local function ty(f) local ok, v = pcall(f); return ok and type(v) or ("error: " .. tostring(v)) end
local n, ai = 0, 0
for k in pairs(package.loaded) do n = n + 1; if type(k) == "string" and k:find("^Chronicle%.AI%.") then ai = ai + 1 end end
return table.concat({ _VERSION, "io " .. type(io), "os " .. type(os), "debug " .. type(debug),
    "Inherit " .. ty(function() return Inherit end), "CppObjectBase " .. ty(function() return CppObjectBase end),
    "ELiveAIManeuverSpeedType " .. ty(function() return ELiveAIManeuverSpeedType end),
    "modules loaded " .. n .. " (" .. ai .. " Chronicle.AI)" }, ", ")
]=]
-- Stock scripts instrumented too, to compare: the root tree of every enemy plane and the two pursue scripts in use.
GAME_LUA_STOCK = { "Chronicle.AI.LA_AIPlane", "Chronicle.AI.LA_PursueTarget_0011", "Chronicle.AI.LA_PursueTarget_0400",
                         "SurvivalMode.AI.LA_SV_MoveAway", "SurvivalMode.AI.LA_SV_TailChase",
                         "SurvivalMode.AI.LA_SV_ProvokeNear", "SurvivalMode.AI.LA_SV_Escape",   -- ours too: builds and errors
                         -- (the fighter roles', P1: each shows as built once a role flight's desc names its set)
                         "SurvivalMode.AI.LA_SV_LancerPass", "SurvivalMode.AI.LA_SV_LancerZoom",
                         "SurvivalMode.AI.LA_SV_LancerBreak", "SurvivalMode.AI.LA_SV_WolfDrag",
                         "SurvivalMode.AI.LA_SV_WolfStrike", "SurvivalMode.AI.LA_SV_SkirmPass",
                         "SurvivalMode.AI.LA_SV_SkirmExtend" }
REQUIRE_AND_WRAP = "local ok, C = pcall(require, %q); if ok then SV_Instrument(%q, C) end; " ..
                         "return tostring(ok) .. ' ' .. tostring(C)"

function gameLua(code, name)
    if type(SV_GameLua) ~= "function" then return false, "no SV_GameLua (dlls/main.dll older than 0.8.0)", -5 end
    local r = SV_GameLua(code, name or "SurvivalMode")
    local st, res = tostring(r):match("^(%-?%d+)\t(.*)$")
    st = tonumber(st)
    return st == 0, res or tostring(r), st
end
