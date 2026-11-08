-- music_test.lua <mod dir> (run by tools/checks/music_test.sh): Survival's music player (sv_music.lua; user,
-- 2026-11-08: "add all the named music into the music player"), the part alone with the game stubbed:
--   nothing changed without the runtime's functions or without the save's two music lists (SV_MusicSave);
--   in Survival's level: the save's lists named, every locked stock track unlocked (the open ones left), Survival's rows
--     added after the stock ones, their SV_ titles set (the game's own keys left), Survival's level's list built again
--     (its manager, not another level's), once; a page open or a track playing (0) waits and builds again later;
--   a restart (a new manager in Survival's level): built again;
--   leaving (another level): Survival's rows out, the stock tracks locked again as they were, the next level's list
--     built again, and only then the save's lists let go (SV_MusicSave(0));
--   [music] player_all = false in Survival's level: the same, Survival's own list built again without them;
--   the loop length to the runtime in ms.
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)

local logs = {}
function log(s) logs[#logs + 1] = s end
local function lastLog(pat) for i = #logs, 1, -1 do if logs[i]:find(pat) then return logs[i] end end end

-- a DataTable: rows by name, in order
local function newTable(full, rows)
    local t = { full = full, order = {}, rows = {}, addr = math.random(1000, 9000) * 16 }
    function t:FindRow(n) return self.rows[n] end
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

local GAME = newTable("DataTable /Game/Datatables/Sound/DT_SoundMusicPlayerBGM.DT_SoundMusicPlayerBGM", {
    { "AKE_Bgm_MUSICPLAYER_BGM_TITLE_Play", { bIsEnableUnlock = false, TitleTextID = S("MusicPlayer_SongTitle_Title") } },
    { "AKE_Bgm_MUSICPLAYER_BGM_M01A_Play", { bIsEnableUnlock = true, TitleTextID = S("MusicPlayer_SongTitle_M01A") } },
    { "AKE_Bgm_MUSICPLAYER_BGM_M30D_Play", { bIsEnableUnlock = true, TitleTextID = S("MusicPlayer_SongTitle_M30D") } },
})
local MINE = newTable("DataTable /Game/Mods/SurvivalMode/Data/DT_SV_MusicRows.DT_SV_MusicRows", {
    { "AKE_Bgm_Ending01_Play", { bIsEnableUnlock = false, TitleTextID = S("SV_Mus2T"), TitleString = S("Ending Ⅰ"),
                                 OriginTextID = S("None"), OriginString = S("") } },
    { "AKE_Bgm_Cin_Ms030010_Play", { bIsEnableUnlock = false, TitleTextID = S("MusicPlayer_SongTitle_Cin_Ms030010"),
                                     TitleString = S("Jet Stream/Grim Reaper"), OriginTextID = S("None"), OriginString = S("") } },
    { "AKE_Bgm_JukeBox_ac04_Comona_Play", { bIsEnableUnlock = false, TitleTextID = S("SV_Mus40T"), TitleString = S("Comona"),
                                            OriginTextID = S("SV_MusO4T"), OriginString = S("ACE COMBAT 04: Shattered Skies") } },
    { "AKE_Bgm_Online_ACE2_Aim_Hight_Play", { bIsEnableUnlock = false, TitleTextID = S("SV_Mus99T"), TitleString = S("Aim High"),
                                              OriginTextID = S("SV_MusO2T"), OriginString = S("ACE COMBAT 2") } },
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

-- the world
local objects = { managers = { SURV_MGR }, saveMgr = nil, pages = {} }
function FindFirstOf(c) if c == "LiveSaveDataManager" then return objects.saveMgr end return nil end
function FindAllOf(c)
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
CFG = { music = { player_all = true, player_loop_s = 240 } }

-- the runtime
local calls = { save = {}, build = {}, texts = {}, loop = nil }
local buildAnswer = 1
local function natives()
    function SV_MusicSave(s, a, b) calls.save[#calls.save + 1] = { s, a, b }; return s > 0 and 1 or 0 end
    function SV_MusicBuild(m) calls.build[#calls.build + 1] = m; return buildAnswer end
    function SV_MusicLoop(ms) calls.loop = ms; return 0 end
    function SV_SetText(k, t) calls.texts[k] = t; return 1 end
end

PARTS.dofile("sv_music.lua")
local tick = 0
local function run(n) for _ = 1, n or 1 do tick = tick + 1; MUSIC.tick(tick) end end
local function runFull() for _ = 1, 8 do tick = tick + 1; MUSIC.tick(tick) end end    -- (it looks every 8th tick)

---------------------------------------------------------------------------------------------------- nothing without the runtime
print("no runtime functions: nothing changed")
svLevelOn, containerState = true, true
runFull()
check(#GAME.order == 3 and GAME.rows["AKE_Bgm_MUSICPLAYER_BGM_M01A_Play"].bIsEnableUnlock == true, "the stock list as it was")
check(lastLog("no SV_MusicBuild") ~= nil, "said why")

print("no save's lists: nothing changed")
natives()
runFull()
check(#GAME.order == 3 and GAME.rows["AKE_Bgm_MUSICPLAYER_BGM_M01A_Play"].bIsEnableUnlock == true, "the stock list as it was")
check(#calls.build == 0 and lastLog("weren't found") ~= nil, "no list built; said why")

---------------------------------------------------------------------------------------------------- in Survival
print("in Survival's level: unlocked, added, built")
objects.saveMgr = SAVEMGR
objects.managers = { MENU_MGR, SURV_MGR }                -- (the last level's manager still about)
runFull()
check(#calls.save == 1 and calls.save[1][1] == 0x7000 and calls.save[1][2] == 0x7650 and calls.save[1][3] == 0x7660,
      "the save and its two lists named first")
check(GAME.rows["AKE_Bgm_MUSICPLAYER_BGM_M01A_Play"].bIsEnableUnlock == false and
      GAME.rows["AKE_Bgm_MUSICPLAYER_BGM_M30D_Play"].bIsEnableUnlock == false, "the locked stock tracks unlocked")
check(#GAME.order == 7 and GAME.order[4] == "AKE_Bgm_Ending01_Play" and GAME.order[7] == "AKE_Bgm_Online_ACE2_Aim_Hight_Play",
      "Survival's 4 rows added after the stock ones, in order")
check(calls.texts.SV_Mus2T == "Ending Ⅰ" and calls.texts.SV_Mus40T == "Comona" and calls.texts.SV_MusO4T == "ACE COMBAT 04: Shattered Skies"
      and calls.texts.MusicPlayer_SongTitle_Cin_Ms030010 == nil, "Survival's titles and game names set, the game's own keys left")
check(#calls.build == 1 and calls.build[1] == 0x5000, "Survival's level's list built (its manager, not the main menu's)")
runFull(); runFull()
check(#calls.build == 1 and #calls.save == 1, "once")

print("a restart: a new manager in Survival's level, built again; a page open waits")
local SURV2 = obj("LiveMusicPlayerSoundManager /Game/Maps/PL_SurvivalMode.PL_SurvivalMode:LiveMusicPlayerSoundManager_1", 0x5100)
objects.managers = { SURV2 }
local page = { IsVisible = function() return true end }
objects.pages.WBP_Menu_PauseMusicPlayer_000_C = { page }
runFull()
check(#calls.build == 1 and lastLog("is open") ~= nil, "not built while the music player's page is open")
objects.pages.WBP_Menu_PauseMusicPlayer_000_C = nil
buildAnswer = 0
runFull()
check(#calls.build == 2 and calls.build[2] == 0x5100, "tried when it closed")
buildAnswer = 1
runFull()
check(#calls.build == 3 and calls.build[3] == 0x5100, "a track playing (0): built again 2 s later")
runFull()
check(#calls.build == 3, "then left")

---------------------------------------------------------------------------------------------------- leaving
print("leaving Survival's level")
svLevelOn = false
objects.managers = { SURV2 }                             -- (the next level's manager not up yet)
runFull()
check(#GAME.order == 3 and GAME.rows["AKE_Bgm_Ending01_Play"] == nil, "Survival's rows taken out")
check(GAME.rows["AKE_Bgm_MUSICPLAYER_BGM_M01A_Play"].bIsEnableUnlock == true and
      GAME.rows["AKE_Bgm_MUSICPLAYER_BGM_TITLE_Play"].bIsEnableUnlock == false, "the stock tracks locked again as they were")
check(#calls.save == 1, "the save's lists still named (the next level's own build may list Survival's rows)")
objects.managers = { SURV2, MENU_MGR }
runFull()
check(#calls.build == 4 and calls.build[4] == 0x6000, "the next level's list built again without them")
check(#calls.save == 2 and calls.save[2][1] == 0, "then the save's lists let go")
runFull(); runFull()
check(#calls.build == 4 and #calls.save == 2, "once")

---------------------------------------------------------------------------------------------------- [music] off
print("[music] player_all = false in Survival's level")
svLevelOn = true
objects.managers = { SURV_MGR }
runFull()
check(#GAME.order == 7 and #calls.build == 5, "back in a run: added and built again")
CFG.music.player_all = false
runFull()
check(#GAME.order == 3 and #calls.build == 6 and calls.build[6] == 0x5000, "taken out; Survival's own list built again")
check(calls.save[#calls.save][1] == 0, "the save's lists let go")

print("the loop length")
MUSIC.levelLoad()
check(calls.loop == 240000 and lastLog("moves on after 240 s") ~= nil, "240 s to the runtime in ms")

print(fails == 0 and "music test: all checks passed" or ("music test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
