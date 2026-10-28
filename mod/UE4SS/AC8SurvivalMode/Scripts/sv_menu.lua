-- sv_menu.lua: Survival's own main-menu pages and the run setups they edit (CFG.setup).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_menu, sv_coop, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).
--
-- The menu (user, 2026-10-27: "when you press Survival Mode, it brings you into another Menu, where you can select
-- what version you want to play ... SP OFFLINE, SP ONLINE, COOP HOST, COOP JOIN. Each of these, except for COOP JOIN,
-- would open up another menu ... presets that can be changed for the mission, such as Round Starting Money, Enemy
-- Percentage"; tools/re/MENU_PAGES.md):
--   main menu: SURVIVAL MODE >
--     SURVIVAL MODE: SP OFFLINE >, SP ONLINE >, COOP HOST >, COOP JOIN (straight to the difficulty), QUICK START
--       SP OFFLINE / SP ONLINE: START RUN, PRESET, STARTING ZOLLARS, ENEMY AIRCRAFT, MORE RULES >
--       COOP HOST: START RUN, LOBBY, CO-OP ROOM, CO-OP ENEMIES, PRESET, STARTING ZOLLARS, ENEMY AIRCRAFT, MORE RULES >
--         MORE RULES (the mode's): START AT ROUND, BREAK BETWEEN ROUNDS, SPECIAL ROUNDS, AIRFIELD HEALTH, ZOLLAR INCOME,
--         ENEMY SKILL, RESET TO DEFAULTS
-- The pages are copies of the game's own main-menu page (tools/build_survival.py MENU_PAGES), so every press on them
-- goes through dlls/main.dll's main-menu hook: a setting row (StringArgs SV_Set_<what>) is taken there and stepped
-- here (SV_MenuSetting), a page row opens its page as the game's rows do, and START RUN / COOP JOIN / QUICK START open
-- the game's difficulty page, which starts Survival as SURVIVAL MODE always has. Without the pages (a build without
-- them, or a game whose page list doesn't take them) the main menu has the flat rows: SURVIVAL MODE, CO-OP HOST / JOIN.
MENU = { mode = nil, pages = nil }       -- mode: "solo" | "offline" | "online" | "host" | "join" (nil: none picked yet)
SETUP = {}                               -- the run's rules, read where they apply (SETUP.zollars() ...)

do
-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
local SOLO = "online"            -- the setup SURVIVAL MODE alone plays with when no mode was picked (the flat row)
local ONLINE_EDITION = true
-- ONLINE ONLY END
--OFFLINE: local SOLO = "offline"
--OFFLINE: local ONLINE_EDITION = false

-- dlls/main.dll's SV_MenuChoice (the entry + 16 x the picks so far): 1 SURVIVAL MODE (flat), 2 SP OFFLINE, 3 COOP HOST,
-- 4 COOP JOIN, 5 SP ONLINE, 6 SURVIVAL MODE's page opened (no mode yet); 0 another entry
local CHOICE = { [1] = "solo", [2] = "offline", [3] = "host", [4] = "join", [5] = "online", [6] = "menu" }
local QUICK_CODE = { offline = 2, host = 3, online = 5 }       -- (SV_MenuQuick: the mode QUICK START plays)
local MODE_NAME = { offline = "SP OFFLINE", online = "SP ONLINE", host = "COOP HOST", join = "COOP JOIN", solo = "SURVIVAL MODE" }

local function num(v, d) v = tonumber(v); return (v and v == v and v > -math.huge and v < math.huge) and v or d end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function money(n) return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
local function same(a, b) return a == b or (type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-9) end

---------------------------------------------------------------------------------------------------- the run setups
-- The setup a mode plays with: SP OFFLINE's, SP ONLINE's, or the host's (COOP HOST and COOP JOIN: a joiner has the
-- host's in CFG while it plays, sv_coop.lua M.onSettings). SURVIVAL MODE alone (the flat row): SOLO's.
local function profileName(mode)
    if mode == "host" or mode == "join" then return "host" end
    if mode == "offline" or mode == "online" then return mode end
    return SOLO
end
local function shipped(name) return (CFG_DEFAULTS and CFG_DEFAULTS.setup and CFG_DEFAULTS.setup[name]) or {} end
local function playProfile()                               -- what this run plays with
    local s = CFG.setup
    return (type(s) == "table" and type(s[profileName(MENU.mode)]) == "table") and s[profileName(MENU.mode)] or shipped(profileName(MENU.mode))
end
-- The setup the menu edits: your own, even while you play with a host's (sv_coop.lua keeps yours aside then)
local function ownProfile(mode)
    local root = (COOP and COOP.ownRoot and COOP.ownRoot()) or CFG
    if type(root.setup) ~= "table" then root.setup = deepCopy((CFG_DEFAULTS and CFG_DEFAULTS.setup) or {}) end
    local n = profileName(mode)
    if type(root.setup[n]) ~= "table" then root.setup[n] = deepCopy(shipped(n)) end
    return root.setup[n], n
end

function SETUP.zollars() return math.floor(clamp(math.max(num(CFG.credits.start, 0), num(playProfile().zollars, 0)), 0, 10000000)) end
function SETUP.enemyX() return clamp(num(playProfile().enemies, 100), 25, 300) / 100 end
function SETUP.startRound() return math.floor(clamp(math.max(num(CFG.start_round, 1), num(playProfile().start_round, 1)), 1, 500)) end
function SETUP.breakS() return math.floor(clamp(num(playProfile().break_s, num(CFG.intermission_s, 20)), 5, 600)) end
local SPECIALS_X = { normal = 1, more = 2, fewer = 0.5, off = 0 }
function SETUP.specialsX() return SPECIALS_X[playProfile().specials] or 1 end
function SETUP.airfieldX() return clamp(num(playProfile().airfield, 100), 25, 400) / 100 end
function SETUP.airfieldHP() return math.max(1, math.floor(num(CFG.airfield.hp, 250) * SETUP.airfieldX() + 0.5)) end
function SETUP.payX() return clamp(num(playProfile().pay, 100), 25, 400) / 100 end
function SETUP.skillAdd() return math.floor(clamp(num(playProfile().skill, 0), -2, 3)) end
local PRESETS = { casual = true, standard = true, ace = true }
function SETUP.preset() local p = playProfile().preset; return PRESETS[p] and p or nil end
function SETUP.mode() return MENU.mode or "solo" end

-- A setup the leaderboard takes: the shipped one (custom rules make a run unranked, so its boards stay comparable)
local RANK_KEYS = { "preset", "zollars", "enemies", "start_round", "break_s", "specials", "airfield", "pay", "skill" }
local function rankedProfile(p)
    local d = shipped("online")
    for _, k in ipairs(RANK_KEYS) do if not same(p[k], d[k]) then return false, k end end
    return true
end
-- This run goes to the leaderboard: SP ONLINE (or SURVIVAL MODE alone in the leaderboard edition) with the shipped
-- setup. false + why otherwise.
function SETUP.ranked()
    local n = profileName(MENU.mode)
    if MENU.mode == "host" or MENU.mode == "join" then return false, "a co-op run" end
    if n ~= "online" then return false, "SP OFFLINE" end
    local ok, k = rankedProfile(playProfile())
    if not ok then return false, "custom rules (" .. tostring(k) .. ")" end
    return true
end

-- The preset a setup names wins over the one the difficulty gives (sv_config.lua presetName; sv_coop.lua's joiner
-- version wraps this one, so a joiner plays the host's)
do
    local rawPreset = presetName
    presetName = function()
        local name, d = rawPreset()
        local p = SETUP.preset()
        if p then return p, d end
        return name, d
    end
end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
-- Only ranked runs go to the leaderboard (co-op runs: CFG.coop.leaderboard, sv_coop.lua)
if LB and LB.send then
    local rawSend = LB.send
    LB.send = function(sh)
        if MENU.mode ~= "host" and MENU.mode ~= "join" then
            local ok, why = SETUP.ranked()
            if not ok then
                if sh then sh.state = "local" end
                log("leaderboard: not sent: " .. tostring(why))
                return
            end
        end
        return rawSend(sh)
    end
end
-- ONLINE ONLY END

---------------------------------------------------------------------------------------------------- the settings
-- Each row that steps a setting: its key in the mode's setup (or CFG.coop's, coop = true), its values in order (a
-- press takes the next, the last goes back to the first), its label and help. Keep the names in step with
-- tools/build_survival.py MENU_PAGES (StringArgs SV_Set_<name>).
local function pct(v) return string.format("%d%%", math.floor(v + 0.5)) end
local SKILL = { [-1] = "EASIER", [0] = "NORMAL", [1] = "HARDER", [2] = "BRUTAL" }
local function round1(x) return math.max(1, math.floor(CFG.aircraft_round1 * x + 0.5)) end
-- (round N's budget as startRound works it out, its spike and late growth in: TIER.roundBudget, sv_config.lua; never
-- more than the fighter pool can field, TIER.poolMost's 86: above 100 % a late round asks more and flies "pool short")
local function roundN(r, x)
    local most = TIER.poolMost()
    local n = math.max(1, math.floor(TIER.roundBudget(r) * x + 0.5))
    return most > 0 and math.min(n, most) or n
end
local SET = {
    Preset = { key = "preset", values = { "auto", "casual", "standard", "ace" },
        label = function(v) return "PRESET: " .. (v == "auto" and "AUTO (BY DIFFICULTY)" or tostring(v):upper()) end,
        help = function(v)
            local a = CFG.ammo.presets[v == "auto" and "standard" or v] or {}
            return (v == "auto" and "Follows the difficulty you pick next (Casual: CASUAL, Ace: ACE, the others: STANDARD). " or "") ..
                string.format("Sets your ammo caps (%s missiles, %s special, %s flares%s), enemy pilot skill and how many enemies fly at once. Press to change.",
                    tostring(a.missiles or "?"), tostring(a.special or "?"), tostring(a.flares or "?"), v == "auto" and " on STANDARD" or "")
        end },
    Zollars = { key = "zollars", values = { 0, 1000, 2500, 5000, 10000, 25000 },
        label = function(v) return "STARTING ZOLLARS: " .. money(v) end,
        help = function() return "Zollars you start the run with, to spend at the airfield STORE between rounds. Press to change." end },
    Enemies = { key = "enemies", values = { 50, 75, 100, 125, 150, 200 },
        label = function(v) return "ENEMY AIRCRAFT: " .. pct(v) end,
        help = function(v)
            return string.format("How many enemies each round brings: round 1 has %d, round 10 has %d, round 35 has %d (at 100%%: %d, %d and %d). Press to change.",
                round1(v / 100), roundN(10, v / 100), roundN(35, v / 100), round1(1), roundN(10, 1), roundN(35, 1))
        end },
    StartRound = { key = "start_round", values = { 1, 5, 10, 15, 20, 25, 30 },
        label = function(v) return string.format("START AT ROUND %d", v) end,
        help = function() return "Skip the first rounds. A run that starts past round 1 isn't sent to the leaderboard. Press to change." end },
    Break = { key = "break_s", values = { 10, 15, 20, 30, 45, 60 },
        label = function(v) return string.format("BREAK BETWEEN ROUNDS: %d S", v) end,
        help = function() return "Seconds from one round's end to the next round, your time to land, rearm and repair. Press to change." end },
    Specials = { key = "specials", values = { "normal", "more", "fewer", "off" },
        label = function(v) return "SPECIAL ROUNDS: " .. tostring(v):upper() end,
        help = function(v)
            return (({ more = "Special rounds (the shuttle, the Ladons, the Alicorn ...) come twice as often.",
                       fewer = "Special rounds come half as often.", off = "No special rounds (ace rounds still come)." })[v] or
                "Special rounds (the shuttle, the Ladons, the Alicorn ...) come as usual.") .. " Press to change."
        end },
    Airfield = { key = "airfield", values = { 50, 75, 100, 150, 200 },
        label = function(v) return string.format("AIRFIELD HEALTH: %s (%d HP)", pct(v), math.floor(CFG.airfield.hp * v / 100 + 0.5)) end,
        help = function() return "How much the airfield takes before it goes down (and how much it comes back with). Press to change." end },
    Pay = { key = "pay", values = { 50, 75, 100, 125, 150, 200 },
        label = function(v) return "ZOLLAR INCOME: " .. pct(v) end,
        help = function(v)
            return string.format("Every zollar you earn, kills, round bonuses and special rewards: a fighter kill pays %d Z. Press to change.",
                math.floor((CFG.credits.fighter or 100) * v / 100 + 0.5))
        end },
    Skill = { key = "skill", values = { -1, 0, 1, 2 },
        label = function(v) return "ENEMY SKILL: " .. (SKILL[v] or tostring(v)) end,
        help = function(v)
            return v == 0 and "Enemy pilots fly as the preset and the round have them. Press to change." or
                string.format("Every enemy pilot flies %d rank%s %s than the preset and the round have them. Press to change.",
                    math.abs(v), math.abs(v) == 1 and "" or "s", v < 0 and "lower" or "higher")
        end },
    Room = { coop = "max_players", values = { 2, 4, 6, 8, 12, 16, 24 },
        label = function(v) return string.format("CO-OP ROOM: %d PLAYERS", v) end,
        help = function() return "How many players your game takes when you host, you included. Press to change." end },
    CoopEnemies = { coop = "aircraft_per_player", values = { 0, 0.1, 0.15, 0.25, 0.4 },
        label = function(v)
            if v <= 0 then return "CO-OP ENEMIES: AS MANY AS ALONE" end
            return string.format("CO-OP ENEMIES: +%d%% EACH", math.floor(v * 100 + 0.5))
        end,
        help = function() return "Each player past the first brings this many more enemies. Press to change." end },
}

-- Survival's pages and their rows, in order (tools/build_survival.py MENU_PAGES: the same names; each row's texts are
-- SV_Pg_<page>_<row> / _Help, a page's title SV_Pg_<page>_Title)
local PAGES = {
    { name = "Modes", rows = { "Offline", "Online", "Host", "Join", "Quick", "Back" } },
    { name = "Offline", rows = { "Go", "Preset", "Zollars", "Enemies", "Rules", "Back" } },
    { name = "Online", rows = { "Go", "Preset", "Zollars", "Enemies", "Rules", "Back" } },
    { name = "Host", rows = { "Go", "Lobby", "Room", "CoopEnemies", "Preset", "Zollars", "Enemies", "Rules", "Back" } },
    { name = "Rules", rows = { "StartRound", "Break", "Specials", "Airfield", "Pay", "Skill", "Reset", "Back" } },
}
-- BACK on each page (test of 2026-10-29: the pages are copies of the main menu's top page, whose cancel goes nowhere,
-- so MORE RULES was a dead end): it asks for the page under it, and the game goes back to a page already open
-- (tools/build_survival.py MENU_PAGES; main.dll takes SV_Back as a page row that opens nothing of ours)
local BACK_TO = { Modes = "the main menu", Offline = "the modes", Online = "the modes", Host = "the modes", Rules = "the setup page" }
local PAGE_MODE = { Offline = "offline", Online = "online", Host = "host" }
-- Without the pages, the main menu's four flat settings rows (DT_SV_MenuRows SurvivalSet<row>, StringArgs SV_Set_<row>,
-- texts SV_Menu_Set<row>Title / Help: the rows Survival COOP's coop.11 build has) step these settings instead, for
-- playing alone and hosting alike (SOLO's setup and the host's), as coop.11's rows did. In order on the menu.
local FLAT = { { row = "Room", set = "Zollars" }, { row = "Enemies", set = "Enemies" }, { row = "Start", set = "StartRound" },
               { row = "Break", set = "Break" } }
local FLAT_SET = {}
for _, f in ipairs(FLAT) do FLAT_SET[f.row] = f.set end

local function valueOf(st, mode)
    if st.coop then return CFG.coop[st.coop] end
    local p = ownProfile(mode)
    local v = p[st.key]
    if v == nil then v = shipped(profileName(mode))[st.key] end
    return v
end
local function summary(mode)
    local p = ownProfile(mode)
    return string.format("%s, %s Z, enemies %s, round %d, break %d s, specials %s, airfield %s, income %s, skill %s.",
        p.preset == "auto" and "preset by difficulty" or ("preset " .. tostring(p.preset)), money(num(p.zollars, 0)),
        pct(num(p.enemies, 100)), num(p.start_round, 1), num(p.break_s, 20), tostring(p.specials), pct(num(p.airfield, 100)),
        pct(num(p.pay, 100)), (SKILL[num(p.skill, 0)] or "?"):lower())
end
local function lobby()
    local L = COOP and COOP.lobby and COOP.lobby()
    if not (CFG.coop and CFG.coop.enabled) then return "LOBBY: CO-OP IS OFF", "This build has co-op switched off." end
    if not L or not L.open then return "LOBBY: OPENS WHEN YOU HOST", "Your friends can join while you set up the run." end
    if L.role ~= "host" then return "LOBBY: NOT HOSTING", "Pick SURVIVAL MODE COOP HOST to host." end
    local names = table.concat(L.names or {}, ", ")
    return string.format("LOBBY: %d OF %d PLAYERS", L.n or 1, L.max or 2),
        (L.n or 1) > 1 and ("In: " .. names .. ". More can join until you start.") or
        "Waiting for friends: they pick SURVIVAL MODE > SURVIVAL MODE COOP JOIN. You can start any time."
end

-- The mode QUICK START plays: the last one started (CFG.menu.last), if this game has it
local function quickMode()
    local q = CFG.menu.last
    if not QUICK_CODE[q] or (q == "host" and not CFG.coop.enabled) or (q == "online" and not ONLINE_EDITION) then q = SOLO end
    return q
end
-- The mode MORE RULES shows: the setup page's it was opened from
local function rulesMode()
    local m = MENU.mode
    return (m == "offline" or m == "online" or m == "host") and m or SOLO
end

-- Every menu text: { key = text }
local function allTexts()
    local t = {}
    local quick = quickMode()
    for _, pg in ipairs(PAGES) do
        local mode = PAGE_MODE[pg.name] or rulesMode()
        local title = ({ Modes = "SURVIVAL MODE", Offline = "SURVIVAL MODE SP OFFLINE", Online = "SURVIVAL MODE SP ONLINE",
                         Host = "SURVIVAL MODE COOP HOST" })[pg.name] or ("MORE RULES: " .. (MODE_NAME[mode] or ""))
        t["SV_Pg_" .. pg.name .. "_Title"] = title
        for _, r in ipairs(pg.rows) do
            local key = "SV_Pg_" .. pg.name .. "_" .. r
            local label, help
            local st = SET[r]
            if st then
                local v = valueOf(st, mode)
                label, help = st.label(v), st.help(v)
            elseif r == "Offline" then label, help = "SURVIVAL MODE SP OFFLINE", "Fly alone with your own rules. Nothing is sent anywhere."
            elseif r == "Online" then label, help = "SURVIVAL MODE SP ONLINE", "Fly alone for the Discord leaderboard. Changing the rules makes a run unranked."
            elseif r == "Host" then label, help = "SURVIVAL MODE COOP HOST", "Host a run for your Steam friends and set its rules. Everyone plays with yours."
            elseif r == "Join" then label, help = "SURVIVAL MODE COOP JOIN", "Join a Steam friend who picked COOP HOST: pick your difficulty and fly their run."
            elseif r == "Quick" then
                label = "QUICK START: " .. (MODE_NAME[quick] or "SP OFFLINE")
                help = "Straight to the difficulty select with your " .. (MODE_NAME[quick] or "") .. " setup: " .. summary(quick)
            elseif r == "Go" then
                local ranked = mode == "online" and rankedProfile(ownProfile(mode))
                label = mode == "online" and (ranked and "START RUN: RANKED" or "START RUN: UNRANKED") or "START RUN"
                help = "Next: the difficulty, then the hangar. " .. summary(mode) ..
                    (mode == "online" and (ranked and " This run goes to the leaderboard." or " Custom rules: this run isn't sent (RESET TO DEFAULTS in MORE RULES).") or "")
            elseif r == "Lobby" then label, help = lobby()
            elseif r == "Rules" then label, help = "MORE RULES", "Start round, break between rounds, special rounds, airfield health, zollar income, enemy skill."
            elseif r == "Reset" then label, help = "RESET TO DEFAULTS", "Puts every " .. (MODE_NAME[mode] or "") .. " setting back to the defaults."
            elseif r == "Back" then label, help = "BACK", "Back to " .. (BACK_TO[pg.name] or "the page before") .. "."
            end
            t[key], t[key .. "_Help"] = label or r, help or ""
        end
    end
    for _, f in ipairs(FLAT) do                                    -- (the flat rows: SOLO's values, the host's the same)
        local st = SET[f.set]
        local v = valueOf(st, SOLO)
        t["SV_Menu_Set" .. f.row .. "Title"] = st.label(v)
        t["SV_Menu_Set" .. f.row .. "Help"] = (st.help(v):gsub(" Press to change%.$", "")) .. " Alone and when you host. Press to change."
    end
    return t
end

-- A text on screen, in place: the game reads a row's label when its page opens (tools/re/AIRFIELD_SHOP_UI.md, the
-- STORE's labels), so a changed label's live TextBlock gets the new text
local function textKey(s) return (tostring(s):upper():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
local function relabel(changed)
    local n = 0
    for _, tb in ipairs(FindAllOf("TextBlock") or {}) do
        if liveWidget(tb) then
            local ok, v = pcall(function() return tb:GetText():ToString() end)
            local new = ok and type(v) == "string" and changed[textKey(v)]
            if new and pcall(function() tb:SetText(toText(new)) end) then n = n + 1 end
        end
    end
    return n
end

-- Sets every menu text that changed (SV_SetText), and on screen when onScreen
local shown = {}
function MENU.texts(onScreen, why)
    if type(SV_SetText) ~= "function" then return end
    local changed, n = {}, 0
    for k, v in pairs(allTexts()) do
        if shown[k] ~= v then
            if shown[k] and shown[k] ~= "" then changed[textKey(shown[k])], n = v, n + 1 end
            shown[k] = v
            pcall(SV_SetText, k, v)
        end
    end
    if onScreen and n > 0 then
        local ok, m = pcall(relabel, changed)
        log(string.format("menu: %d text(s) changed (%s), %s on screen", n, tostring(why), ok and tostring(m) or ("? " .. tostring(m))))
    end
end

-- A settings row was pressed (dlls/main.dll took its StringArgs SV_Set_<name> off the page)
local function press(name)
    local mode = MENU.mode
    if name == "Lobby" then MENU.texts(true, "lobby"); return end
    if name == "Reset" then
        local p, n = ownProfile(mode)
        local d = shipped(n)
        for k, v in pairs(d) do
            if not same(p[k], v) then p[k] = deepCopy(v); iniSet("setup." .. n, k, v) end
        end
        log("menu: the " .. n .. " setup is back to the defaults (" .. summary(mode) .. ")")
        MENU.texts(true, "reset")
        return
    end
    local flat = MENU.pages == false and FLAT_SET[name or ""]     -- (a flat row on the main menu: sets SOLO's and the host's)
    if flat then name = flat end
    local st = SET[name or ""]
    if not st then log("menu: unknown settings row " .. tostring(name)); return end
    local holder, section
    if st.coop then holder, section = CFG.coop, "coop"
    else local p, n = ownProfile(flat and SOLO or mode); holder, section = p, "setup." .. n end
    local key = st.coop or st.key
    local cur = holder[key]
    local nxt = nil
    for i, v in ipairs(st.values) do if same(v, cur) then nxt = st.values[i % #st.values + 1]; break end end
    if nxt == nil and type(cur) == "number" then             -- (a value of the ini's own: the next one above it)
        for _, v in ipairs(st.values) do if v > cur then nxt = v; break end end
    end
    if nxt == nil then nxt = st.values[1] end
    holder[key] = nxt
    local saved = iniSet(section, key, nxt)
    if flat then                                                 -- (the host's the same)
        local hp = ownProfile("host")
        if hp ~= holder then hp[key] = nxt; saved = iniSet("setup.host", key, nxt) and saved end
    end
    log(string.format("menu: %s.%s %s -> %s (%s%s)", section, key, tostring(cur), tostring(nxt),
        saved and "saved to survival.ini" or "COULD NOT save survival.ini", flat and ", the host's too: a flat row" or ""))
    MENU.texts(true, name)
    if COOP and COOP.settingsChanged then pcall(COOP.settingsChanged, name) end
end

---------------------------------------------------------------------------------------------------- the pages
-- Survival's pages open through CAMPAIGN TRAINING's page (user, 2026-10-29: "feel free to use the Campaign Training and
-- replace it completely"): the main menu opens a row's page by ELiveMenuMainIDs, the game's fixed list of its pages
-- (GameTitle ... CampaignTraining), so pages of our own names never opened (test of 2026-10-29: SURVIVAL MODE pressed 25
-- times, nothing). Every page row names CampaignTraining (tools/build_survival.py BORROWED_PAGE), and dlls/main.dll
-- points that page's entry in the main menu's page list at the page each press opens (SV_MenuClass: the pages' classes,
-- in PAGES order; SV_MenuSlot: the entry). Its own row is kept off the main menu meanwhile (sv_core.lua hideRows).
-- The game doesn't open the page it's on (test of 2026-10-29: the setup rows on the modes page did nothing), so the
-- setup pages go through a second page PC players never see, the PS5 DualSense first-start setup, whose own class
-- main.dll puts back when any other main-menu entry is picked. Nor one already open under it (it goes back to it:
-- MORE RULES went back to the modes page), so MORE RULES has a third, the first-start Accessibility setup.
local BORROWED = { "CampaignTraining", "InitialSetting_DualSence", "InitialSetting_Accessibility" }   -- (main.dll kSlotIds)
local function commandTable(page) return string.format("/Game/Mods/SurvivalMode/Data/DT_SV_Pg%sCommands.DT_SV_Pg%sCommands", page, page) end
-- what the build found in the game (tools/build_survival.py writes Scripts/sv_menu_stock.lua): the stock page the
-- pages copy (its class name) and the game's main-menu page table
local STOCK = {}
do
    local f = io.open(SCRIPT_DIR .. "sv_menu_stock.lua", "rb")
    if f then
        local src = f:read("a"); f:close()
        local chunk = load(src, "@sv_menu_stock.lua", "t", {})
        local ok, t = false, nil
        if chunk then ok, t = pcall(chunk) end
        if ok and type(t) == "table" then STOCK = t end
    end
end
local PG = { said = {}, mgr = nil, early = {}, start = os.clock(), fresh = {}, searched = -100 }
-- a new page manager (a new world: the main menu again, or a level): looked at by the tick, not here
pcall(NotifyOnNewObject, "/Script/Live.LiveMenuManager", function(o) PG.fresh[#PG.fresh + 1] = { obj = o, at = os.clock() } end)
local function say(key, text) if PG.said[key] ~= text then PG.said[key] = text; log("menu pages: " .. text) end end

local function asText(v)
    if type(v) == "string" then return v end
    local ok, s = pcall(function() return v:ToString() end)
    return ok and s or tostring(v)
end
-- The ids in a manager's page list, as a set, and how many there are
local function listIds(mgr)
    local ids, n = {}, 0
    local ok, err = pcall(function()
        local list = mgr.MenuWidgetClassList
        n = list:GetArrayNum()
        for i = 1, n do ids[asText(list[i].MenuIDName)] = i - 1 end
    end)
    return ok and ids or nil, n, err
end
-- The live main-menu page manager (its list has the free-mission difficulty page; a mission's has the pause pages).
-- Only new managers are looked at (NotifyOnNewObject), each for up to a minute while its list fills; FindAllOf walks
-- every object in the game (a visible hitch: sv_core.lua svFlags), so it runs only until the first one is found.
local function isMain(m)
    if not valid(m) or nameOf(m):find("Default__", 1, true) then return nil end
    local ids, n = listIds(m)
    if ids and n > 0 and ids.CampaignFreeMissionDifficulty then return ids, n end
end
local function mainManager()
    if valid(PG.mgrObj) then
        local ids, n = isMain(PG.mgrObj)
        if ids then return PG.mgrObj, ids, n end
    end
    local now = os.clock()
    for i = #PG.fresh, 1, -1 do
        local f = PG.fresh[i]
        local ids, n = isMain(f.obj)
        if ids then PG.fresh = {}; return f.obj, ids, n end
        if not valid(f.obj) or now - f.at > 60 then table.remove(PG.fresh, i) end
    end
    if not PG.foundOnce and now - PG.searched > 2 then            -- (one that was there before this script ran)
        PG.searched = now
        for _, m in ipairs(FindAllOf("LiveMenuManager") or {}) do
            local ids, n = isMain(m)
            if ids then return m, ids, n end
        end
    end
end
-- The pages' own command tables, loaded and kept (their pages read them when they open); the rows this game doesn't
-- show come off: SP ONLINE in the Offline edition, COOP HOST / JOIN without co-op
local function pageTables()
    local drop = { Online = not ONLINE_EDITION, Host = not CFG.coop.enabled, Join = not CFG.coop.enabled }
    for _, pg in ipairs(PAGES) do
        local dt = loadObject(commandTable(pg.name))
        if valid(dt) then
            pin(dt, nameOf(dt))
            if pg.name == "Modes" then
                for r, off in pairs(drop) do if off then dtCall(dt, "RemoveRow", "SVModes" .. r) end end
            end
        else
            say("table" .. pg.name, "could not load " .. commandTable(pg.name))
        end
    end
end
-- One pass (every second from the main menu): decides MENU.pages for this main menu
-- the pages' classes (the stock page's, in Survival's packages), loaded and kept: the game creates a page from its entry's class
local function pageClasses()
    if PG.classes then return PG.classes end
    local cls = STOCK.page_class
    if not cls then return nil, "no stock page class known (Scripts/sv_menu_stock.lua)" end
    local out = {}
    for i, pg in ipairs(PAGES) do
        local path = string.format("/Game/Mods/SurvivalMode/UI/WBP_SV_Pg%s.%s", pg.name, cls)
        local c, why = loadObject(path)
        if not valid(c) then return nil, path .. " didn't load (" .. tostring(why) .. ")" end
        pin(c, nameOf(c))
        out[i] = c
    end
    PG.classes = out
    return out
end

-- One pass (every second from the main menu): decides MENU.pages for this main menu
function MENU.pagesTick()
    if MENU.pages == false and PG.final then return end
    if not CFG.menu.pages then MENU.pages, PG.final = false, true; say("off", "off (CFG.menu.pages); the flat rows"); return end
    if containerState ~= true then return end
    if type(SV_MenuSlot) ~= "function" then MENU.pages, PG.final = false, true; say("dll", "dlls/main.dll can't open the pages (0.28.0 or later); the flat rows"); return end
    local classes, cwhy = pageClasses()
    if not classes then MENU.pages, PG.final = false, true; say("mine", "this build's pages can't be used: " .. tostring(cwhy) .. "; the flat rows"); return end
    if not PG.tables then PG.tables = true; pageTables() end
    local mgr, ids, n = mainManager()
    if not mgr then
        if MENU.pages == nil and os.clock() - PG.start > 120 then
            MENU.pages = false
            say("nomgr", "no main-menu page manager found in 120 s; the flat rows for now")
        end
        return
    end
    PG.foundOnce, PG.mgrObj = true, mgr
    local a = addrOf(mgr)
    if PG.mgr == a then return end                               -- (this main menu was decided)
    PG.mgr = a
    local why, at = nil, {}
    for i, c in ipairs(classes) do SV_MenuClass(i, addrOf(c) or 0) end
    for slot, id in ipairs(BORROWED) do
        local idx = ids[id]
        if not idx then why = why or ("the game's page list has no " .. id); break end
        local okS, stock = pcall(function() return mgr.MenuWidgetClassList[idx + 1].MenuClass end)
        local r = SV_MenuSlot(a or 0, (okS and valid(stock) and addrOf(stock)) or 0, idx, slot - 1)
        if r ~= 1 then why = why or (id .. "'s entry wasn't found in the page list (" .. tostring(r) .. ")") end
        at[#at + 1] = id .. " " .. idx
    end
    MENU.pages = why == nil
    say("decided", MENU.pages and string.format("the main menu's page list has %d pages; Survival's open through %s: SURVIVAL MODE opens them", n, table.concat(at, ", "))
        or ("Survival's pages can't open (" .. why .. "): the flat rows"))
    pcall(SV_MenuPages, MENU.pages and 1 or 0)
    -- every live menu page's DeepLevel, once (what Survival's pages should get if cancel on them goes wrong)
    if not PG.levels then
        PG.levels = true
        for _, cls in ipairs({ "LiveMenuMainBaseWidget", "LiveMenuCampaignFreeMissionDifficultyWidget" }) do
            for _, w in ipairs(FindAllOf(cls) or {}) do
                if liveWidget(w) then
                    local okD, d = pcall(function() return w.DeepLevel end)
                    log(string.format("menu pages: page %s, DeepLevel %s", nameOf(w), okD and tostring(d) or "?"))
                end
            end
        end
    end
end

-- The rows the main menu gets (sv_core.lua watchRows): nil while that's not decided yet
local PAGE_ROWS, FLAT_ROWS, FLAT_COOP = { "SurvivalMenu" }, { "SurvivalMode" }, { "SurvivalMode", "SurvivalCoopHost", "SurvivalCoopJoin" }
for _, f in ipairs(FLAT) do                                         -- (their settings rows below them)
    FLAT_ROWS[#FLAT_ROWS + 1], FLAT_COOP[#FLAT_COOP + 1] = "SurvivalSet" .. f.row, "SurvivalSet" .. f.row
end
MENU.allRows = { "SurvivalMenu", "SurvivalMode", "SurvivalCoopHost", "SurvivalCoopJoin" }
for _, f in ipairs(FLAT) do MENU.allRows[#MENU.allRows + 1] = "SurvivalSet" .. f.row end
function MENU.mainRows()
    if MENU.pages == nil then return nil end
    if MENU.pages then return PAGE_ROWS end
    return CFG.coop.enabled and FLAT_COOP or FLAT_ROWS
end

---------------------------------------------------------------------------------------------------- the tick
function MENU.tick(tick)
    if tick % 4 == 0 then
        local ok, err = pcall(MENU.pagesTick)
        if not ok then say("err", "error " .. tostring(err)) end
    end
    -- the mode picked (SV_MenuChoice), before any setting pressed on its pages
    local raw = type(SV_MenuChoice) == "function" and SV_MenuChoice() or nil
    if raw and raw ~= MENU.raw then
        MENU.raw = raw
        local c = CHOICE[math.floor(raw) % 16]
        if c ~= "menu" then
            if c ~= MENU.mode then log("menu: mode " .. tostring(c and MODE_NAME[c] or "none (another entry)")) end
            MENU.mode = c
        end
        MENU.texts(true, "mode")
    end
    if type(SV_MenuSetting) == "function" then
        for _ = 1, 8 do
            local m = SV_MenuSetting()
            if not m or m == "" then break end
            local okS, errS = pcall(press, m:match("^SV_Set_(%w+)$"))
            if not okS then log("menu: " .. tostring(errS)) end
        end
    end
    if tick % 8 == 3 then MENU.texts(not D, "lobby") end         -- (the lobby row while you host)
    -- a run started: its mode is QUICK START's from now on
    if D ~= MENU.lastD then
        MENU.lastD = D
        if D then
            local m = MENU.mode or "solo"
            local q = (m == "solo") and SOLO or m
            log(string.format("menu: the run plays %s's setup (%s): %s; leaderboard: %s", MODE_NAME[m] or m, profileName(m),
                summary(m), (function() local ok, why = SETUP.ranked(); return ok and "ranked" or tostring(why) end)()))
            if QUICK_CODE[q] and CFG.menu.last ~= q then
                CFG.menu.last = q
                iniSet("menu", "last", q)
                MENU.texts(false, "last mode")
            end
        end
    end
    if type(SV_MenuQuick) == "function" then
        local q = QUICK_CODE[quickMode()]
        if q ~= MENU.quick then MENU.quick = q; pcall(SV_MenuQuick, q) end
    end
end

pcall(MENU.texts, false, "start")                              -- (before the main menu reads the rows' texts)
end
