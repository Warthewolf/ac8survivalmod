-- sv_music.lua : the pause menu's music player in Survival (2026-11-08)
-- The user: "add more music into the music player function", "Theres music that is only available in the online mode
-- too", "If you can add all the named music into the music player do so". While Survival's level is on:
--  * AC8's music player shows 120 tracks at most (its scroll list's limit, ULiveMenuScrollCommandListWidget +0x434 =
--    120: past it the cursor runs on over rows that aren't there and a press there crashed the game, the user's run of
--    0.74.29 at the 232nd of 235). So, as the user chose ("Make room: hide menu tracks"; "Delete the briefing debriefing
--    cutscene tracks", "hangars too", "Have it draw from the jukebox"):
--  * the stock menu tracks are hidden (CFG.music.player_hide: Title, Main Menu, the briefings, hangars, debriefings and
--    Mission Failed: locked to a mission there is none of, put back when the level goes), every other stock track
--    unlocked (bIsEnableUnlock false, as the Title row has; put back too);
--  * the room left (player_max 120, less the stock tracks shown) is filled with a random draw, new each level, from
--    Survival's DT_SV_MusicRows (tools/music_tracks.py) rows of the groups in player_from (default the online lobby's
--    jukebox: AC04, 5, 6, 7 and Zero), listed in the table's order; taken out again when the level goes. Their banks are
--    resident from the game's start (docs/re/MUSIC_BANKS.md 2);
--  * the level's music player list is built again with them (runtime SV_MusicBuild): the game builds it only as a
--    level starts (docs/re/MUSIC_BANKS.md 5), and once more in the next level after they're out;
--  * the player's save is never changed: each build grants what it lists to the save's OwnedMusicList /
--    NewlyOwnedMusicList, and while Survival's rows are in the runtime cuts those grants back off (SV_MusicSave). Without
--    the save's two lists found, nothing is changed (hard rule of 2026-10-24: nothing stock stays changed);
--  * their titles (and their games' names) are Survival's texts (SV_Mus<n>T, SV_MusO<n>T) set from the rows;
--  * a track that loops for ever (the online match tracks: a Wwise "infinite" event the player's clock never ends)
--    moves on after player_loop_s (runtime SV_MusicLoop).
-- The whole pass runs once a level (0.74.29's ran every 2 s: 4 ms a tick in the user's log); [music] player_all = false
-- keeps the stock list.

MUSIC = {}
local MU = { addr = nil, added = {}, changed = {}, texts = false, said = {}, built = nil, done = false, cleanFor = nil,
             cleanTries = 0, save = nil, saveMgr = nil, mgr = nil }
MUSIC.game = "/Game/Datatables/Sound/DT_SoundMusicPlayerBGM.DT_SoundMusicPlayerBGM"
MUSIC.mine = "/Game/Mods/SurvivalMode/Data/DT_SV_MusicRows.DT_SV_MusicRows"
MUSIC.pages = { "WBP_Menu_PauseMusicPlayer_000_C", "WBP_DataViewer_MusicPlayer_000_C", "WBP_DataViewer_MusicPlayer_001_C",
                "WBP_DataViewer_MusicPlayer_002_C" }
MUSIC.NO_MISSION = 127                       -- (a hidden row's UnlockMissionID: no mission record has it)
-- player_from's groups: an added row's group from its event's name (tools/music_tracks.py), the first prefix that fits.
-- ((2026-11-08) Alyssa: "Music was selected but nothing played": the lobby jukebox's own events are 3D (heard within
-- 6 m of the lobby's jukebox), so "jukebox" is Online Mode's own 2D versions of its songs: AC04, AC5, AC6, AC7, Zero)
MUSIC.groups = {
    { name = "jukebox", prefix = "AKE_Bgm_Online_ACE04_" },
    { name = "jukebox", prefix = "AKE_Bgm_Online_ACE5_" },
    { name = "jukebox", prefix = "AKE_Bgm_Online_ACE6_" },
    { name = "jukebox", prefix = "AKE_Bgm_Online_ACE7_" },
    { name = "jukebox", prefix = "AKE_Bgm_Online_ACEZ_" },
    { name = "battle", prefix = "AKE_Bgm_Online_ACE" },      -- (the older games' online match tracks)
    { name = "battle", prefix = "AKE_Bgm_Online_Ms_" },
    { name = "online", prefix = "AKE_Bgm_Online_" },          -- (Online Mode's own named tracks)
    { name = "endings", prefix = "AKE_Bgm_Ending" },
}

function MUSIC.groupOf(event)
    for _, g in ipairs(MUSIC.groups) do
        if event:sub(1, #g.prefix) == g.prefix then return g.name end
    end
    return "other"
end

local function str(v)                                   -- an FName / FString field as a Lua string ("" if unread)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    local ok, s = pcall(function() return v:ToString() end)
    return (ok and type(s) == "string") and s or ""
end
local function hx(v)
    local ok, t = pcall(string.format, "%X", v)
    return ok and t or tostring(v)
end
local function wanted()
    return CFG.music.player_all ~= false and svLevelOn == true and containerState == true
end
local function nativeOk()
    return type(SV_MusicBuild) == "function" and type(SV_MusicSave) == "function"
end
local function fromSet()
    local s, any = {}, false
    for w in tostring(CFG.music.player_from or "jukebox"):lower():gmatch("[%a]+") do s[w] = true; any = true end
    if not any then s.jukebox = true end
    return s
end

-- the save's two music lists to the runtime (1 = named): the save game, from the save manager
local function nameSave()
    local smgr = MU.saveMgr
    if not (smgr and liveObj(smgr)) then
        smgr = FindFirstOf("LiveSaveDataManager")
        MU.saveMgr = valid(smgr) and smgr or nil
    end
    if not MU.saveMgr then return nil, "no save manager" end
    local ok, save, owned, newly = pcall(function()
        local s = MU.saveMgr.CampaignSaveGame
        local mp = s.CampaignSaveData.MusicPlayer
        return s, mp.OwnedMusicList:GetArrayAddress(), mp.NewlyOwnedMusicList:GetArrayAddress()
    end)
    if not ok or not valid(save) then return nil, "no campaign save (" .. tostring(save) .. ")" end
    local a = addrOf(save)
    if MU.save == a then return 1 end
    local r = SV_MusicSave(a, owned, newly)
    if r == 1 then
        MU.save = a
        log("music player: the save's music lists found (" .. hx(a) .. ": " .. hx(owned) .. ", " .. hx(newly)
            .. "); each list build's grants to them are cut back off")
        return 1
    end
    return nil, "SV_MusicSave " .. tostring(r)
end

local function pageOpen()
    for _, cls in ipairs(MUSIC.pages) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            local okV, vis = pcall(function() return w:IsVisible() end)
            if okV and vis and liveWidget(w) then return cls end
        end
    end
    return nil
end

-- the music player manager of the level on now (Survival's, or not: survival = true / false)
local function manager(survival)
    for _, m in ipairs(FindAllOf("LiveMusicPlayerSoundManager") or {}) do
        if valid(m) and inSurvival(m) == survival and not nameOf(m):find("Default__", 1, true) then return m end
    end
    return nil
end

-- the texts of Survival's rows (their keys are SV_ ones: the game's own keys need none)
local function setTexts(mine, names)
    if MU.texts or type(SV_SetText) ~= "function" then return end
    local n, full = 0, false
    for _, r in ipairs(names) do
        local _, row = dtCall(mine, "FindRow", r)
        if row ~= nil then
            pcall(function()
                local k, t = str(row.TitleTextID), str(row.TitleString)
                if k:sub(1, 3) == "SV_" and t ~= "" then
                    if SV_SetText(k, t) == 1 then n = n + 1 else full = true end
                end
                local ok, okey = pcall(function() return str(row.OriginTextID) end)
                local on = str(row.OriginString)
                if ok and okey:sub(1, 3) == "SV_" and on ~= "" then SV_SetText(okey, on) end
            end)
        end
    end
    MU.texts = true
    log(string.format("music player: %d titles of Survival's tracks set%s", n,
        full and " (the runtime's text table is full: some show their key)" or ""))
end

-- a stock row hidden (locked to no mission) or unlocked; its old values kept to put back. true when it's as wanted
local function setStock(game, r, hide)
    local _, row = dtCall(game, "FindRow", r)
    if row == nil then return false end
    local okU, unl = pcall(function() return row.bIsEnableUnlock end)
    local okM, mis = pcall(function() return row.UnlockMissionID end)
    if not okU then return false end
    local was = MU.changed[r] or { unlock = unl, mission = okM and mis or nil }
    if hide then
        if not okM then return false end
        local ok = pcall(function() row.UnlockMissionID = MUSIC.NO_MISSION; row.bIsEnableUnlock = true end)
        local okR, back = pcall(function() return row.UnlockMissionID end)
        if not (ok and okR and back == MUSIC.NO_MISSION) then
            pcall(function() row.bIsEnableUnlock = was.unlock; if was.mission ~= nil then row.UnlockMissionID = was.mission end end)
            return false
        end
        MU.changed[r] = was
        return true
    end
    if unl == true then
        if not pcall(function() row.bIsEnableUnlock = false end) then return false end
        MU.changed[r] = was
    end
    return true
end

-- Survival's rows out, the stock rows as they were; the next level's list is built again (MU.cleanFor)
local function putBack(why)
    local game = StaticFindObject(MUSIC.game)
    local nr, nu = 0, 0
    if valid(game) then
        for r in pairs(MU.added) do
            dtCall(game, "RemoveRow", r)
            local _, still = dtCall(game, "FindRow", r)
            if still == nil then nr = nr + 1 end
        end
        for r, was in pairs(MU.changed) do
            local _, row = dtCall(game, "FindRow", r)
            if row ~= nil and pcall(function()
                if was.mission ~= nil then row.UnlockMissionID = was.mission end
                row.bIsEnableUnlock = was.unlock
            end) then nu = nu + 1 end
        end
    end
    log(string.format("music player: %d of Survival's tracks taken out, %d stock tracks back as they were (%s)", nr, nu, why))
    MU.addr, MU.added, MU.changed, MU.built, MU.done, MU.mgr = nil, {}, {}, nil, false, nil
    MU.cleanFor, MU.cleanTries = "pending", 0
end

-- (not in Survival) the level's list built again without Survival's rows, then the save's cut off
local function cleanTick()
    if not MU.cleanFor then return end
    MU.cleanTries = MU.cleanTries + 1
    local m = manager(svLevelOn == true)                 -- (the level on now: Survival's too, when [music] went off)
    local open = m and pageOpen()
    local r = (m and not open) and SV_MusicBuild(addrOf(m)) or nil
    if r == 1 or MU.cleanTries > 30 then
        log("music player: " .. (r == 1 and ("this level's list built again without Survival's tracks (" .. nameOf(m):match("([^/]+)$") .. ")")
            or "no level's list to build again (the next level builds its own)"))
        MU.cleanFor = nil
        SV_MusicSave(0, 0, 0); MU.save = nil
    end
end

-- ((2026-11-08) Alyssa's test of 0.74.31: "Hush just abruptly ends and the next track plays"; Saint Alessia's of 0.74.32:
-- "hush still ended abruptly") a looping Online Mode track moves on after one pass of its own recording, else after
-- player_loop_s (runtime SV_MusicLen). Each is one looping Sound whose loop is in its .wem (Hush: 0 - 312.6 s, then from
-- 38.3 s again); 0.74.32 used the lobby jukebox's recording of the song (332 s: 19 s into Hush's second pass). The
-- lengths are the .wems' loop ends, written here by tools/music_lengths.py (build_music_rows fails on one missing).
-- BEGIN SONG LENGTHS (tools/music_lengths.py write: one pass of each looping Online Mode track, its .wem's loop end; ms)
MUSIC.passMs = {
    AKE_Bgm_Online_ACE04_Aquila_Play = 187756, AKE_Bgm_Online_ACE04_Blockade_Play = 271000,
    AKE_Bgm_Online_ACE04_Comona_Play = 150217, AKE_Bgm_Online_ACE04_Deep_Strike_Play = 164000,
    AKE_Bgm_Online_ACE04_Emancipation_Play = 275555, AKE_Bgm_Online_ACE04_Escort_Play = 240357,
    AKE_Bgm_Online_ACE04_Farbanti_Play = 167275, AKE_Bgm_Online_ACE04_Invincible_Fleet_Play = 265832,
    AKE_Bgm_Online_ACE04_Safe_Return_Play = 396140, AKE_Bgm_Online_ACE04_Sitting_Duck_Play = 181271,
    AKE_Bgm_Online_ACE04_Whiskey_Corridor_Play = 250435, AKE_Bgm_Online_ACE2_Aim_Hight_Play = 134036,
    AKE_Bgm_Online_ACE2_Dynapolis_Play = 141643, AKE_Bgm_Online_ACE2_El_Dorado_Play = 318850,
    AKE_Bgm_Online_ACE2_Elemental_Particle_Play = 335286, AKE_Bgm_Online_ACE2_Fire_Away_Play = 245494,
    AKE_Bgm_Online_ACE2_Fire_Youngman_Play = 255088, AKE_Bgm_Online_ACE2_Night_And_Day_Play = 153742,
    AKE_Bgm_Online_ACE2_Rising_High_Play = 141375, AKE_Bgm_Online_ACE2_Sunset_Glow_Play = 295847,
    AKE_Bgm_Online_ACE3D_Fighter_s_Honor_Flying_Remix_Play = 115068,
    AKE_Bgm_Online_ACE3D_Gravity_Play = 168288, AKE_Bgm_Online_ACE3D_Heartbeat_Play = 131402,
    AKE_Bgm_Online_ACE3D_If_The_Sky_Is_Burnin_Out_2011_Play = 87474,
    AKE_Bgm_Online_ACE3D_On_The_Verge_Play = 130800, AKE_Bgm_Online_ACE3_Code_of_Honor_Play = 172781,
    AKE_Bgm_Online_ACE3_Frozen_Soul_Play = 145790, AKE_Bgm_Online_ACE3_Gordian_Knot_Play = 165735,
    AKE_Bgm_Online_ACE3_Mind_Flow_Play = 136088, AKE_Bgm_Online_ACE3_Physical_Layer_Play = 153201,
    AKE_Bgm_Online_ACE3_Revelation_Play = 181021, AKE_Bgm_Online_ACE3_Shattered_Stones_Play = 147729,
    AKE_Bgm_Online_ACE3_The_Execution_Play = 155288, AKE_Bgm_Online_ACE3_Transparent_Blue_Play = 169155,
    AKE_Bgm_Online_ACE5_8492_Play = 182658, AKE_Bgm_Online_ACE5_Arcade_Riding_High_Play = 141950,
    AKE_Bgm_Online_ACE5_First_Flight_Play = 150469, AKE_Bgm_Online_ACE5_Fortress_Play = 179100,
    AKE_Bgm_Online_ACE5_Four_Horsemen_Play = 228065, AKE_Bgm_Online_ACE5_Ice_Cage_Play = 140372,
    AKE_Bgm_Online_ACE5_Naval_Blockade_Play = 161976, AKE_Bgm_Online_ACE5_Rendezvous_Play = 136400,
    AKE_Bgm_Online_ACE5_Reprisal_Play = 293708, AKE_Bgm_Online_ACE5_Wardog_Play = 240357,
    AKE_Bgm_Online_ACE6_Bartolomeo_Fortress_Play = 205384,
    AKE_Bgm_Online_ACE6_Fires_of_Liberation_Play = 130471,
    AKE_Bgm_Online_ACE6_Invasion_of_Gracemeria_Play = 302609, AKE_Bgm_Online_ACE6_On_Line_Play = 168846,
    AKE_Bgm_Online_ACE6_Selumna_Peak_Play = 304348, AKE_Bgm_Online_ACE6_Siege_on_Silvat_Play = 300000,
    AKE_Bgm_Online_ACE6_The_Liberation_of_Gracemeria_Play = 369982,
    AKE_Bgm_Online_ACE6_Through_the_Heart_of_a_Nation_Play = 143673,
    AKE_Bgm_Online_ACE7_444_Play = 256157, AKE_Bgm_Online_ACE7_ADFX_10_Play = 192540,
    AKE_Bgm_Online_ACE7_Archange_Play = 249291, AKE_Bgm_Online_ACE7_Awakening_Play = 225453,
    AKE_Bgm_Online_ACE7_Battle_for_Farbanti_Play = 245890,
    AKE_Bgm_Online_ACE7_Dual_Wielder_Play = 188609, AKE_Bgm_Online_ACE7_Enchanter_II_Play = 214811,
    AKE_Bgm_Online_ACE7_Enchanter_I_Play = 294615, AKE_Bgm_Online_ACE7_Hush_Play = 312608,
    AKE_Bgm_Online_ACE7_Lighthouse_Play = 296731, AKE_Bgm_Online_ACE7_Long_Day_Play = 264172,
    AKE_Bgm_Online_ACE7_Lost_Kingdom_Play = 560725, AKE_Bgm_Online_ACE7_Magic_Spear_I_Play = 236562,
    AKE_Bgm_Online_ACE7_Mimic_Play = 288659, AKE_Bgm_Online_ACE7_Pipeline_Destruction_Play = 228012,
    AKE_Bgm_Online_ACE7_Roca_Roja_Play = 208540, AKE_Bgm_Online_ACE7_Sol_Squadron_Play = 208778,
    AKE_Bgm_Online_ACE7_Two_Pairs_Play = 190011, AKE_Bgm_Online_ACE7_Werewolf_Play = 518755,
    AKE_Bgm_Online_ACEAH_Beyond_The_Canal_Play = 371575, AKE_Bgm_Online_ACEAH_Dogfight_Play = 102322,
    AKE_Bgm_Online_ACEAH_Fighter_Play = 226668, AKE_Bgm_Online_ACEAH_Keep_Alive_Play = 333099,
    AKE_Bgm_Online_ACEAH_Naval_Warfare_Play = 244386, AKE_Bgm_Online_ACEAH_Rush_Play = 266461,
    AKE_Bgm_Online_ACEAH_Shall_Defend_Play = 264186, AKE_Bgm_Online_ACEAH_White_Devil_Play = 238710,
    AKE_Bgm_Online_ACEINF_Blue_Skies_INFINITY_Remix_Play = 361412,
    AKE_Bgm_Online_ACEINF_Invincible_Fleet_INFINITY_Remix_Play = 300113,
    AKE_Bgm_Online_ACEX2_Metropolitan_Play = 181731,
    AKE_Bgm_Online_ACEX2_War_Torn_Radiance_Play = 174902, AKE_Bgm_Online_ACEX_Blitz_Play = 164163,
    AKE_Bgm_Online_ACEX_End_of_Deception_Play = 129510, AKE_Bgm_Online_ACEX_Gaiuss_Tower_Play = 199439,
    AKE_Bgm_Online_ACEX_Operation_X_Play = 236310, AKE_Bgm_Online_ACEX_Prelude_Play = 195501,
    AKE_Bgm_Online_ACEZ_CONTACT_Play = 213615, AKE_Bgm_Online_ACEZ_GLACIAL_SKIES_Play = 173100,
    AKE_Bgm_Online_ACEZ_JUGGERNAUT_Play = 226500, AKE_Bgm_Online_ACEZ_MAYHEM_Play = 182286,
    AKE_Bgm_Online_ACEZ_MERLON_Play = 323493,
    AKE_Bgm_Online_ACEZ_THE_DEMON_OF_THE_ROUND_TABLE_Play = 127770,
    AKE_Bgm_Online_ACEZ_THE_ROUND_TABLE_Play = 223064, AKE_Bgm_Online_ACEZ_ZERO_Play = 245020,
    AKE_Bgm_Online_ACE_Get_off_him_Play = 201061, AKE_Bgm_Online_ACE_Head_first_Play = 105068,
    AKE_Bgm_Online_ACE_Like_a_sea_gull_Play = 145607, AKE_Bgm_Online_ACE_Night_and_Day_Play = 154880,
    AKE_Bgm_Online_EB003_Play = 227987, AKE_Bgm_Online_EmergencyPhase_01_Play = 120577,
    AKE_Bgm_Online_EmergencyPhase_02_Play = 133902, AKE_Bgm_Online_EmergencyPhase_03_Play = 151998,
    AKE_Bgm_Online_EmergencyPhase_04_Play = 117237, AKE_Bgm_Online_EmergencyPhase_05_Play = 123736,
    AKE_Bgm_Online_EmergencyPhase_06_Play = 161037, AKE_Bgm_Online_FreeFlight_Play = 116509,
    AKE_Bgm_Online_GeneralMVP_Play = 208094, AKE_Bgm_Online_Matching_Play = 308085,
    AKE_Bgm_Online_Ms_ac3_Linkage_Play = 111342, AKE_Bgm_Online_Op_Play = 103304,
    AKE_Bgm_Online_Result_Draw_Play = 93520, AKE_Bgm_Online_Result_Lose_Play = 60588,
    AKE_Bgm_Online_Result_Victory_Play = 12047, AKE_Bgm_Online_Tutorial_Play = 70996,
}
-- END SONG LENGTHS
local function setLengths(added)
    if type(SV_MusicLen) ~= "function" then return end
    SV_MusicLen("", 0)
    local own, rest = 0, 0
    for r in pairs(added) do
        local ms = MUSIC.passMs and MUSIC.passMs[r]
        if ms then SV_MusicLen(r, ms); own = own + 1 elseif r:find("^AKE_Bgm_Online_") then rest = rest + 1 end
    end
    log(string.format("music player: %d looping songs move on after one pass of their own recording (its loop's end), "
        .. "%d after %d s", own, rest, math.floor(tonumber(CFG.music.player_loop_s) or 0)))
end

-- the whole pass (once a level): stock rows hidden / unlocked, the draw added; true when done
local function pass(game, mine)
    local stock, ours = rowList(game), rowList(mine)
    if not stock or not ours then return false end
    local mineSet = {}
    for _, r in ipairs(ours) do mineSet[r] = true end
    local hideSet = {}
    for _, r in ipairs(CFG.music.player_hide or {}) do hideSet[r] = true end
    local shown, hidden, unlocked, failed = 0, 0, 0, 0
    for _, r in ipairs(stock) do
        if not mineSet[r] then                           -- (a stock row: Survival's own aren't in yet)
            if hideSet[r] then
                if setStock(game, r, true) then hidden = hidden + 1 else shown = shown + 1; failed = failed + 1 end
            else
                if MU.changed[r] == nil then
                    local _, row = dtCall(game, "FindRow", r)
                    local okU, unl = pcall(function() return row.bIsEnableUnlock end)
                    if okU and unl == true then unlocked = unlocked + 1 end
                end
                setStock(game, r, false)
                shown = shown + 1
            end
        end
    end
    setTexts(mine, ours)
    -- the draw: room = the limit less the stock tracks shown; from the groups in player_from, at random, kept in order
    local room = math.max(0, math.floor(tonumber(CFG.music.player_max) or 120) - shown)
    local from, pool = fromSet(), {}
    for i, r in ipairs(ours) do
        if from[MUSIC.groupOf(r)] then pool[#pool + 1] = i end
    end
    for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
    local pick = {}
    for k = 1, math.min(room, #pool) do pick[#pick + 1] = pool[k] end
    table.sort(pick)
    local nNew = 0
    for _, i in ipairs(pick) do
        local r = ours[i]
        local _, src = dtCall(mine, "FindRow", r)
        if src ~= nil then dtCall(game, "AddRow", r, src) end
        local _, now = dtCall(game, "FindRow", r)
        if now ~= nil then MU.added[r] = true; nNew = nNew + 1 end
    end
    pcall(setLengths, MU.added)
    log(string.format("music player: %d stock tracks shown (%d unlocked for Survival), %d hidden%s; %d of Survival's %d "
        .. "drawn from %s (%d in it; room %d of %d): %d tracks in all", shown, unlocked, hidden,
        failed > 0 and string.format(" (%d NOT hidden: their unlock didn't take)", failed) or "", nNew, #ours,
        tostring(CFG.music.player_from or "jukebox"), #pool, room, math.floor(tonumber(CFG.music.player_max) or 120), shown + nNew))
    return true
end

function MUSIC.tick(tick)
    if tick % 8 ~= 5 then return end                     -- (every 2 s)
    if not nativeOk() then
        if not MU.said.native then MU.said.native = true; log("music player: the runtime has no SV_MusicBuild (0.32.30+); the stock list") end
        return
    end
    if not wanted() then
        if MU.addr then putBack(CFG.music.player_all == false and "[music] player_all off" or "not in Survival's level") end
        cleanTick()
        return
    end
    if walkHold() then return end
    local okS, why = nameSave()
    if okS ~= 1 then
        if not MU.said.save then MU.said.save = true; log("music player: the save's music lists weren't found (" .. tostring(why)
            .. "); nothing changed, the stock list") end
        return
    end
    local game = StaticFindObject(MUSIC.game)
    if not valid(game) then game = loadObject(MUSIC.game) end
    if not valid(game) then
        if not MU.said.game then MU.said.game = true; log("music player: the music player's table isn't loaded; nothing changed") end
        return
    end
    local a = addrOf(game)
    if MU.addr ~= a then                                 -- (a new level's pass, or the table loaded again)
        MU.addr, MU.added, MU.changed, MU.built, MU.done = a, {}, {}, nil, false
        pin(game, nameOf(game))
    end
    MU.cleanFor = nil                                    -- (back in Survival before the last level's clean: rows in again)
    if not MU.done then
        local mine = loadObject(MUSIC.mine)
        if not valid(mine) then
            if not MU.said.mine then MU.said.mine = true; log("music player: could not load DT_SV_MusicRows; the stock list only") end
            return
        end
        pin(mine, nameOf(mine))
        if not pass(game, mine) then return end
        MU.done, MU.built = true, nil
    end
    -- this level's list built with them, once (a restart makes a new manager: MUSIC.levelLoad looks again)
    if MU.built then return end
    local m = MU.mgr
    if not (m and liveObj(m)) then m = manager(true); MU.mgr = m end
    if not m then return end
    local open = pageOpen()
    local r = open and 0 or SV_MusicBuild(addrOf(m))
    if r == 1 then
        MU.built = addrOf(m)
        log("music player: Survival's list built (the menu tracks hidden, the stock tracks unlocked, the draw added)")
    elseif not MU.said.busy then
        MU.said.busy = true
        log("music player: the list not built yet (" .. (open and (open .. " is open") or ("SV_MusicBuild " .. tostring(r)))
            .. "); again in 2 s")
    end
end

-- (a new level of Survival) the loop length to the runtime; this level's list to build again (a restart's new manager)
function MUSIC.levelLoad()
    MU.said.busy, MU.built, MU.mgr = nil, nil, nil
    if type(SV_MusicLoop) == "function" then
        local s = tonumber(CFG.music.player_loop_s) or 0
        local old = SV_MusicLoop(math.floor(math.max(0, s) * 1000))
        log("music player: a track that loops for ever " .. (old < 0 and "isn't capped (runtime without SV_MusicLoop)"
            or (s > 0 and string.format("moves on after %d s", math.floor(s)) or "plays until skipped")))
    end
end
