-- sv_music.lua : the pause menu's music player in Survival (2026-11-08)
-- The user: "add more music into the music player function", "Theres music that is only available in the online mode
-- too", "If you can add all the named music into the music player do so". While Survival's level is on:
--  * every stock track of the music player is unlocked (bIsEnableUnlock false on the game's own rows, as its Title and
--    Main Menu rows have; each put back when the level goes);
--  * the game's other named tracks are added (Survival's DT_SV_MusicRows, tools/music_tracks.py: the campaign bank's
--    four, the cutscenes', Online Mode's, the online jukebox's 77 and the older games' online match tracks: every one
--    of their banks is resident from the game's start, tools/re/MUSIC_BANKS.md 2), and taken out again when it goes;
--  * the level's music player list is built again with them (runtime SV_MusicBuild): the game builds it only as a
--    level starts (tools/re/MUSIC_BANKS.md 5), and once more in the next level after they're out;
--  * the player's save is never changed: each build grants what it lists to the save's OwnedMusicList /
--    NewlyOwnedMusicList, and while Survival's rows are in the runtime cuts those grants back off (SV_MusicSave). Without
--    the save's two lists found, nothing is unlocked or added (hard rule of 2026-10-24: nothing stock stays changed);
--  * their titles (and the older games' names) are Survival's texts (SV_Mus<n>T, SV_MusO<n>T) set from the rows;
--  * a track that loops for ever (most online match tracks: a Wwise "infinite" event the player's clock never ends)
--    moves on after CFG.music.player_loop_s (runtime SV_MusicLoop).
-- [music] player_all = false keeps the stock list.

MUSIC = {}
local MU = { addr = nil, added = {}, unlocked = {}, texts = false, said = {}, built = nil, cleanFor = nil, cleanTries = 0,
             save = nil }
MUSIC.game = "/Game/Datatables/Sound/DT_SoundMusicPlayerBGM.DT_SoundMusicPlayerBGM"
MUSIC.mine = "/Game/Mods/SurvivalMode/Data/DT_SV_MusicRows.DT_SV_MusicRows"
MUSIC.pages = { "WBP_Menu_PauseMusicPlayer_000_C", "WBP_DataViewer_MusicPlayer_000_C", "WBP_DataViewer_MusicPlayer_001_C",
                "WBP_DataViewer_MusicPlayer_002_C" }
-- a row's bank from its event's name (tools/music_tracks.py: every row of a bank has its prefix), for the log
MUSIC.banks = {
    { prefix = "AKE_Bgm_JukeBox_", bank = "AKB_BGM_Online_Lobby" },
    { prefix = "AKE_Bgm_Online_", bank = "AKB_BGM_Online" },
    { prefix = "AKE_Bgm_Cin_", bank = "AKB_BGM_Cinema" },
}
MUSIC.campaign = "AKB_BGM_Campaign"

function MUSIC.bankOf(event)
    for _, b in ipairs(MUSIC.banks) do
        if event:sub(1, #b.prefix) == b.prefix then return b.bank end
    end
    return MUSIC.campaign
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

-- every stock row unlocked (the ones changed kept, to put back)
local function unlockStock(game, names)
    local n = 0
    for _, r in ipairs(names) do
        if not MU.added[r] and MU.unlocked[r] == nil then
            local _, row = dtCall(game, "FindRow", r)
            if row ~= nil then
                local ok, was = pcall(function() return row.bIsEnableUnlock end)
                if ok and was == true and pcall(function() row.bIsEnableUnlock = false end) then
                    MU.unlocked[r] = true; n = n + 1
                end
            end
        end
    end
    return n
end

-- Survival's rows out, the stock rows locked as they were; the next level's list is built again (MU.cleanFor)
local function putBack(why)
    local game = StaticFindObject(MUSIC.game)
    local nr, nu = 0, 0
    if valid(game) then
        for r in pairs(MU.added) do
            dtCall(game, "RemoveRow", r)
            local _, still = dtCall(game, "FindRow", r)
            if still == nil then nr = nr + 1 end
        end
        for r in pairs(MU.unlocked) do
            local _, row = dtCall(game, "FindRow", r)
            if row ~= nil and pcall(function() row.bIsEnableUnlock = true end) then nu = nu + 1 end
        end
    end
    log(string.format("music player: %d of Survival's tracks taken out, %d stock tracks locked again as they were (%s)",
        nr, nu, why))
    MU.addr, MU.added, MU.unlocked, MU.built = nil, {}, {}, nil
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
            .. "); nothing unlocked or added, the stock list") end
        return
    end
    local game = StaticFindObject(MUSIC.game)
    if not valid(game) then game = loadObject(MUSIC.game) end
    if not valid(game) then
        if not MU.said.game then MU.said.game = true; log("music player: the music player's table isn't loaded; nothing added") end
        return
    end
    local a = addrOf(game)
    if MU.addr ~= a then
        MU.addr, MU.added, MU.unlocked, MU.built = a, {}, {}, nil
        pin(game, nameOf(game))
    end
    local mine = loadObject(MUSIC.mine)
    if not valid(mine) then
        if not MU.said.mine then MU.said.mine = true; log("music player: could not load DT_SV_MusicRows; the stock list only") end
        return
    end
    pin(mine, nameOf(mine))
    local stock, ours = rowList(game), rowList(mine)
    if not stock or not ours then return end
    MU.cleanFor = nil                                    -- (back in Survival before the last level's clean: rows in again)
    local nUnlocked = unlockStock(game, stock)
    setTexts(mine, ours)
    local have = {}
    for _, r in ipairs(stock) do have[r] = true end
    local nNew, byBank = 0, {}
    for _, r in ipairs(ours) do
        local bank = MUSIC.bankOf(r)
        byBank[bank] = byBank[bank] or 0
        if not have[r] then
            local _, src = dtCall(mine, "FindRow", r)
            if src ~= nil then dtCall(game, "AddRow", r, src) end
            local _, now = dtCall(game, "FindRow", r)
            if now ~= nil then MU.added[r] = true; have[r] = true; nNew = nNew + 1 end
        end
        if MU.added[r] then byBank[bank] = byBank[bank] + 1 end
    end
    if nNew > 0 or nUnlocked > 0 then
        local parts = {}
        for _, b in ipairs({ MUSIC.campaign, "AKB_BGM_Cinema", "AKB_BGM_Online", "AKB_BGM_Online_Lobby" }) do
            if byBank[b] then parts[#parts + 1] = b .. " " .. byBank[b] end
        end
        log(string.format("music player: %d stock tracks unlocked for Survival, %d of Survival's %d added (%s)", nUnlocked,
            nNew, #ours, table.concat(parts, ", ")))
        MU.built = nil                                   -- (the list built again with them)
    end
    -- this level's list built with them: once per level's manager (a restart makes a new one)
    local m = manager(true)
    if m and MU.built ~= addrOf(m) then
        local open = pageOpen()
        local r = open and 0 or SV_MusicBuild(addrOf(m))
        if r == 1 then
            MU.built = addrOf(m)
            log("music player: Survival's list built (the stock tracks unlocked, Survival's added)")
        elseif not MU.said.busy then
            MU.said.busy = true
            log("music player: the list not built yet (" .. (open and (open .. " is open") or ("SV_MusicBuild " .. tostring(r)))
                .. "); again in 2 s")
        end
    end
end

-- (a new level of Survival) the loop length to the runtime
function MUSIC.levelLoad()
    MU.said.busy = nil
    if type(SV_MusicLoop) == "function" then
        local s = tonumber(CFG.music.player_loop_s) or 0
        local old = SV_MusicLoop(math.floor(math.max(0, s) * 1000))
        log("music player: a track that loops for ever " .. (old < 0 and "isn't capped (runtime without SV_MusicLoop)"
            or (s > 0 and string.format("moves on after %d s", math.floor(s)) or "plays until skipped")))
    end
end
