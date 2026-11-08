-- music_test.lua <mod dir> (run by tools/checks/music_test.sh): Survival's music player (sv_music.lua; the user,
-- 2026-11-08: "add all the named music into the music player", then, AC8's player showing 120 at most: "Make room: hide
-- menu tracks", "Delete the briefing debriefing cutscene tracks", "hangars too", "Have it draw from the jukebox"), the
-- part alone with the game stubbed:
--   nothing changed without the runtime's functions or without the save's two music lists (SV_MusicSave);
--   in Survival's level: the save's lists named; player_hide's stock rows locked to no mission (bIsEnableUnlock true,
--     UnlockMissionID 127), the other locked stock rows unlocked; the room left to player_max filled with a random draw
--     from player_from's groups only (the jukebox), in the table's order; SV_ titles set; Survival's level's list built
--     (its manager, not another level's), once; the whole pass once a level (no FindRow every 2 s);
--   a page open or a track playing (0) waits; a restart (a new manager) built again, the same draw;
--   leaving: the draw out, every stock row back as it was (unlock and mission), the next level's list built, then the
--     save's lists let go; the next run a new draw;
--   [music] player_all = false in Survival's level: the same, Survival's own list built again;
--   a hide that doesn't take: that row counts as shown, the room one smaller (never over the limit);
--   the loop length to the runtime in ms.
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)

local logs = {}
function log(s) logs[#logs + 1] = s end
local function lastLog(pat) for i = #logs, 1, -1 do if logs[i]:find(pat) then return logs[i] end end end
local function count(pat) local n = 0; for _, l in ipairs(logs) do if l:find(pat) then n = n + 1 end end; return n end

local finds = 0
local function newTable(full, rows)
    local t = { full = full, order = {}, rows = {}, addr = math.random(1000, 9000) * 16 }
    function t:FindRow(n) finds = finds + 1; return self.rows[n] end
    function t:AddRow(n, src)
        if self.rows[n] then return end
        local c = {}
        for k, v in pairs(src) do c[k] = v end
        self.rows[n] = c; self.order[#self.order + 1] = n
    end
    function t:RemoveRow(n)
        if not self.rows[n] then return end
        self.rows[n] = nil
        for i, m in ipairs(self.order) do if m == n then table.remove(self.order, i); break end end
    end
    function t:GetRowNames() local o = {}; for i, n in ipairs(self.order) do o[i] = n end; return o end
    function t:GetAddress() return self.addr end
    for _, r in ipairs(rows) do t.rows[r[1]] = r[2]; t.order[#t.order + 1] = r[1] end
    return t
end
local STR = { __index = { ToString = function(self) return self.s end } }
local function S(s) return setmetatable({ s = s }, STR) end

local TITLE, BRIEF, M01A, M30D = "AKE_Bgm_MUSICPLAYER_BGM_TITLE_Play", "AKE_Bgm_MUSICPLAYER_BGM_BRIEFING01_Play",
    "AKE_Bgm_MUSICPLAYER_BGM_M01A_Play", "AKE_Bgm_MUSICPLAYER_BGM_M30D_Play"
local GAME = newTable("DataTable /Game/Datatables/Sound/DT_SoundMusicPlayerBGM.DT_SoundMusicPlayerBGM", {
    { TITLE, { bIsEnableUnlock = false, UnlockMissionID = 1, TitleTextID = S("MusicPlayer_SongTitle_Title") } },
    { BRIEF, { bIsEnableUnlock = true, UnlockMissionID = 5, TitleTextID = S("MusicPlayer_SongTitle_Briefing01") } },
    { M01A, { bIsEnableUnlock = true, UnlockMissionID = 1, TitleTextID = S("MusicPlayer_SongTitle_M01A") } },
    { M30D, { bIsEnableUnlock = true, UnlockMissionID = 31, TitleTextID = S("MusicPlayer_SongTitle_M30D") } },
})
local function row(key, title, okey, oname)
    return { bIsEnableUnlock = false, UnlockMissionID = 1, TitleTextID = S(key), TitleString = S(title),
             OriginTextID = S(okey or "None"), OriginString = S(oname or "") }
end
local JB = { "AKE_Bgm_JukeBox_ac04_Comona_Play", "AKE_Bgm_JukeBox_ac5_Wardog_Play", "AKE_Bgm_JukeBox_ac7_Daredevil_Play" }
local MINE = newTable("DataTable /Game/Mods/SurvivalMode/Data/DT_SV_MusicRows.DT_SV_MusicRows", {
    { "AKE_Bgm_Ending01_Play", row("SV_Mus1T", "Ending Ⅰ") },
    { "AKE_Bgm_Online_Op_Play", row("MusicPlayer_SongTitle_Online_OP", "Sky mercenaries") },
    { JB[1], row("SV_Mus20T", "Comona", "SV_MusO4T", "ACE COMBAT 04: Shattered Skies") },
    { JB[2], row("SV_Mus30T", "Wardog", "SV_MusO5T", "ACE COMBAT 5: THE UNSUNG WAR") },
    { JB[3], row("SV_Mus40T", "Daredevil", "SV_MusO7T", "ACE COMBAT 7: SKIES UNKNOWN") },
    { "AKE_Bgm_Online_ACE2_Aim_Hight_Play", row("SV_Mus99T", "Aim High", "SV_MusO2T", "ACE COMBAT 2") },
})
local function obj(full, addr) return { full = full, addr = addr, GetAddress = function(self) return self.addr end } end
local SURV_MGR = obj("LiveMusicPlayerSoundManager /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:LiveMusicPlayerSoundManager_0", 0x5000)
local MENU_MGR = obj("LiveMusicPlayerSoundManager /Game/Maps/PL_MainMenu.PL_MainMenu:LiveMusicPlayerSoundManager_0", 0x6000)
local SAVE = obj("LiveCampaignSaveGame /Engine/Transient.LiveCampaignSaveGame_0", 0x7000)
SAVE.CampaignSaveData = { MusicPlayer = {
    OwnedMusicList = { GetArrayAddress = function() return 0x7650 end },
    NewlyOwnedMusicList = { GetArrayAddress = function() return 0x7660 end } } }
local SAVEMGR = obj("LiveSaveDataManager /Engine/Transient.LiveSaveDataManager_0", 0x8000)
SAVEMGR.CampaignSaveGame = SAVE

local objects = { managers = { SURV_MGR }, saveMgr = nil, pages = {} }
local walks = 0
function FindFirstOf(c) if c == "LiveSaveDataManager" then return objects.saveMgr end return nil end
function FindAllOf(c)
    walks = walks + 1
    if c == "LiveMusicPlayerSoundManager" then return objects.managers end
    return objects.pages[c]
end
function StaticFindObject(p) if p:find("DT_SoundMusicPlayerBGM", 1, true) then return GAME end return nil end
function loadObject(p)
    if p:find("DT_SV_MusicRows", 1, true) then return MINE end
    return StaticFindObject(p)
end
function valid(o) return type(o) == "table" and not o.gone end
function liveObj(o) return valid(o) end
function liveWidget(w) return valid(w) end
function addrOf(o) return o and o.addr end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function inSurvival(o) return nameOf(o):find("PL_SurvivalMode", 1, true) ~= nil end
function pin() return true end
function walkHold() return nil end
function dtCall(dt, m, ...)
    local args = { ... }
    local ok, r = pcall(function() return dt[m](dt, table.unpack(args)) end)
    return ok, r
end
function rowList(dt) return dt:GetRowNames() end

local calls = { save = {}, build = {}, texts = {}, loop = nil }
local buildAnswer = 1
local function natives()
    function SV_MusicSave(s, a, b) calls.save[#calls.save + 1] = { s, a, b }; return s > 0 and 1 or 0 end
    function SV_MusicBuild(m) calls.build[#calls.build + 1] = m; return buildAnswer end
    function SV_MusicLoop(ms) calls.loop = ms; return 0 end
    function SV_SetText(k, t) calls.texts[k] = t; return 1 end
end

-- the shipped settings (sv_config_specials.lua's CFG.music), the limit made small for the test
CFG = {}
PARTS.load("sv_config_specials.lua", nil, {})
local shippedHide = CFG.music and CFG.music.player_hide or {}
check(#shippedHide == 13 and CFG.music.player_from == "jukebox" and CFG.music.player_max == 120,
      "shipped: 13 menu tracks hidden, the draw from the jukebox, the limit 120")
CFG = { music = { player_all = true, player_loop_s = 240, player_from = "jukebox", player_max = 4, player_hide = { TITLE, BRIEF } } }

PARTS.dofile("sv_music.lua")
local tick = 0
local function runFull() for _ = 1, 8 do tick = tick + 1; MUSIC.tick(tick) end end
local function ours() local n = 0; for _, r in ipairs(GAME.order) do if MINE.rows[r] then n = n + 1 end end; return n end
local function jukeboxIn() local l = {}; for _, r in ipairs(GAME.order) do if r:find("JukeBox", 1, true) then l[#l + 1] = r end end; return l end

print("no runtime functions / no save's lists: nothing changed")
svLevelOn, containerState = true, true
runFull()
check(#GAME.order == 4 and GAME.rows[M01A].bIsEnableUnlock == true and lastLog("no SV_MusicBuild") ~= nil, "no runtime: as it was")
natives()
runFull()
check(#GAME.order == 4 and GAME.rows[BRIEF].UnlockMissionID == 5 and #calls.build == 0 and lastLog("weren't found") ~= nil,
      "no save's lists: as it was")

print("in Survival's level: hidden, unlocked, drawn, built")
objects.saveMgr = SAVEMGR
objects.managers = { MENU_MGR, SURV_MGR }
runFull()
check(#calls.save == 1 and calls.save[1][1] == 0x7000 and calls.save[1][2] == 0x7650 and calls.save[1][3] == 0x7660,
      "the save and its two lists named first")
check(GAME.rows[TITLE].bIsEnableUnlock == true and GAME.rows[TITLE].UnlockMissionID == 127 and
      GAME.rows[BRIEF].bIsEnableUnlock == true and GAME.rows[BRIEF].UnlockMissionID == 127, "the menu tracks locked to no mission")
check(GAME.rows[M01A].bIsEnableUnlock == false and GAME.rows[M30D].bIsEnableUnlock == false, "the other stock tracks unlocked")
local jb = jukeboxIn()
check(ours() == 2 and #jb == 2, "the room (4 less 2 shown) filled: 2 of Survival's (" .. ours() .. ")")
local order = {}
for i, r in ipairs(JB) do order[r] = i end
check(#jb == 2 and order[jb[1]] < order[jb[2]], "all from the jukebox, in the table's order")
check(GAME.rows["AKE_Bgm_Online_Op_Play"] == nil and GAME.rows["AKE_Bgm_Ending01_Play"] == nil, "nothing from the other groups")
check(calls.texts.SV_Mus20T == "Comona" and calls.texts.SV_MusO7T == "ACE COMBAT 7: SKIES UNKNOWN" and
      calls.texts["MusicPlayer_SongTitle_Online_OP"] == nil, "Survival's titles set, the game's own keys left")
check(#calls.build == 1 and calls.build[1] == 0x5000, "Survival's level's list built (its manager)")
local f0, w0 = finds, walks
runFull(); runFull(); runFull()
check(#calls.build == 1 and #calls.save == 1 and finds == f0 and walks == w0, "then left: no FindRow, no walk every 2 s")
check(count("stock tracks shown") == 1, "the pass once")

print("a restart: a new manager, built again, the same draw; a page open waits")
local drawn = table.concat(jukeboxIn(), ",")
local SURV2 = obj("LiveMusicPlayerSoundManager /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:LiveMusicPlayerSoundManager_1", 0x5100)
objects.managers = { SURV2 }
MUSIC.levelLoad()
objects.pages.WBP_Menu_PauseMusicPlayer_000_C = { { IsVisible = function() return true end } }
runFull()
check(#calls.build == 1 and lastLog("is open") ~= nil, "not built while the music player's page is open")
objects.pages.WBP_Menu_PauseMusicPlayer_000_C = nil
buildAnswer = 0
runFull()
check(#calls.build == 2 and calls.build[2] == 0x5100, "tried when it closed")
buildAnswer = 1
runFull()
check(#calls.build == 3 and calls.build[3] == 0x5100 and table.concat(jukeboxIn(), ",") == drawn, "built 2 s later, the same draw")

print("leaving Survival's level")
svLevelOn = false
objects.managers = { SURV2 }
runFull()
check(#GAME.order == 4 and ours() == 0, "Survival's rows taken out")
check(GAME.rows[TITLE].bIsEnableUnlock == false and GAME.rows[TITLE].UnlockMissionID == 1 and
      GAME.rows[BRIEF].bIsEnableUnlock == true and GAME.rows[BRIEF].UnlockMissionID == 5 and
      GAME.rows[M01A].bIsEnableUnlock == true and GAME.rows[M30D].bIsEnableUnlock == true, "every stock row as it was")
check(#calls.save == 1, "the save's lists still named (the next level's own build may list Survival's rows)")
objects.managers = { SURV2, MENU_MGR }
runFull()
check(#calls.build == 4 and calls.build[4] == 0x6000 and #calls.save == 2 and calls.save[2][1] == 0,
      "the next level's list built again without them, then the save's lists let go")

print("the next run: a new draw; [music] player_all = false")
local seen = { [drawn] = true }
local newDraw = false
for _ = 1, 12 do
    svLevelOn = true; objects.managers = { SURV_MGR }
    runFull()
    local d = table.concat(jukeboxIn(), ",")
    if not seen[d] then newDraw = true end
    svLevelOn = false; objects.managers = { MENU_MGR }
    runFull(); runFull()
end
check(newDraw, "another draw in a later run")
svLevelOn = true; objects.managers = { SURV_MGR }
runFull()
local b0 = #calls.build
CFG.music.player_all = false
runFull()
check(ours() == 0 and #calls.build == b0 + 1 and calls.build[#calls.build] == 0x5000 and calls.save[#calls.save][1] == 0,
      "off: taken out, Survival's own list built again, the save let go")

print("a hide that doesn't take: never over the limit")
CFG.music.player_all = true
svLevelOn = false; runFull(); runFull()
local stuck = setmetatable({}, { __index = GAME.rows[TITLE], __newindex = function(t, k, v)
    if k == "UnlockMissionID" then return end                -- (its write doesn't take)
    rawset(GAME.rows[TITLE], k, v)
end })
local realTitle = GAME.rows[TITLE]
GAME.rows[TITLE] = stuck
svLevelOn = true; objects.managers = { SURV_MGR }
runFull()
check(ours() == 1 and lastLog("1 NOT hidden") ~= nil, "TITLE counted as shown: room 1 (" .. ours() .. ")")
check(realTitle.bIsEnableUnlock == false, "and left as it was")
GAME.rows[TITLE] = realTitle

print("the loop length")
MUSIC.levelLoad()
check(calls.loop == 240000 and lastLog("moves on after 240 s") ~= nil, "240 s to the runtime in ms")

print(fails == 0 and "music test: all checks passed" or ("music test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
