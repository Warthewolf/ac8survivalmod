-- Survival's own sound effects, through the native runtime's XAudio2 player (runtime 0.18.0: SV_SndLoad / SV_SndPlay /
-- SV_SndSet / SV_SndStop / SV_SndMaster; AC8 plays only its own Wwise banks). For now VALKA's railgun: AC7 Mission 18's
-- Mihaly EML sounds (AGENTS.md's AC7 exception; tools/ac7_sfx.py extracts them, build_all.sh stages them in Sounds\valka),
-- each layer at the dB, pitch and distance curve AC7's Wwise gives it (build/ac7/sfx/NOTES.md). Gains and pan are worked
-- out here from the camera: AC7's curves are in AC7 units, CFG.sound.ac7_unit_m metres each (AC7's models are about 1/9
-- scale; user, 2026-10-24: AC7 distances aren't AC8 centimetres).
SND = { ids = {}, said = {}, live = {} }
do
local function db(x) return 10 ^ (x / 20) end

-- the camera (else the player): where, and its yaw (degrees)
local function listener()
    local ok, at, yaw = pcall(function()
        local cm = survivalPC.PlayerCameraManager
        local l, r = cm:GetCameraLocation(), cm:GetCameraRotation()
        return { X = l.X, Y = l.Y, Z = l.Z }, r.Yaw
    end)
    if ok and at then return at, yaw end
    return playerLocation(), 0
end

-- curve gain (linear) at d cm: c = { max = AC7 units, shape = "linear" | "exp1" | "exp3" | "log1" | "flat",
-- end_db = the value at max and past it (nil: silence) }, from 0 dB at 0 (NOTES.md 0: dB curves are stored as a linear
-- value, gain = 1 + v, v from 0 down to the end's, shaped)
local function curveGain(c, d)
    if not c or c.shape == "flat" then return 1 end
    local t = math.min(1, d / math.max(1, c.max * CFG.sound.ac7_unit_m * 100))
    local s = (c.shape == "exp1" and t ^ 1.41) or (c.shape == "exp3" and t ^ 3) or (c.shape == "log1" and 1 - (1 - t) ^ 1.41) or t
    local vEnd = c.end_db and (db(c.end_db) - 1) or -1
    return math.max(0, 1 + vEnd * s)
end

-- left / right gains for layer dB `ldb` on curve `c` at `at` (nil: on you, centred), equal-power pan
local function gains(at, ldb, c)
    local g = db(ldb + CFG.sound.gain_db)
    if not at then return g * 0.7071, g * 0.7071 end
    local me, yaw = listener()
    if not me then return 0, 0 end
    local dx, dy, dz = at.X - me.X, at.Y - me.Y, at.Z - me.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    g = g * curveGain(c, d)
    local pan = 0
    local h = math.sqrt(dx * dx + dy * dy)
    if h > 1 then                                   -- (UE: right = (-sin yaw, cos yaw))
        local y = math.rad(yaw or 0)
        pan = (dx * -math.sin(y) + dy * math.cos(y)) / h * math.min(1, h / math.max(1, d)) * CFG.sound.pan
    end
    local a = (pan + 1) * math.pi / 4
    return g * math.cos(a), g * math.sin(a)
end

-- the runtime's id of Sounds\<file> (loaded once), or nil
function SND.id(file)
    if not CFG.sound.enabled or type(SV_SndLoad) ~= "function" then return nil end
    if SND.ids[file] ~= nil then return SND.ids[file] or nil end      -- (false: it failed once, not tried again)
    if not SND.master then
        SND.master = true
        local r = SV_SndMaster(db(CFG.sound.master_db))
        log("sound: master " .. CFG.sound.master_db .. " dB" .. (r == 1 and "" or (" NOT set (" .. tostring(r) .. ")")))
    end
    local id = SV_SndLoad(file)
    if id and id > 0 then SND.ids[file] = id; return id end
    SND.ids[file] = false
    log("sound: " .. file .. " not loaded (" .. tostring(id) .. "); not tried again this session")
    return nil
end

-- plays layer `l` = { file, db, curve, cents, loop } at `at` (a location table, or a function returning one each tick:
-- it follows; nil: on you); its handle, or nil. extraDb / ratio: on top of the layer's (the charge's rise)
function SND.play(l, at, extraDb, ratio)
    local id = SND.id(l.file)
    if not id then return nil end
    local where = type(at) == "function" and at() or at
    if type(at) == "function" and not where then return nil end      -- (a moving source that's already gone)
    local left, right = gains(where, l.db + (extraDb or 0), l.curve)
    local r = (ratio or 1) * 2 ^ ((l.cents or 0) / 1200)
    local h = SV_SndPlay(id, left, right, r, l.loop and 1 or 0)
    if not h or h <= 0 then
        if not SND.said["play " .. l.file] then SND.said["play " .. l.file] = true; log("sound: " .. l.file .. " didn't play (" .. tostring(h) .. ")") end
        return nil
    end
    SND.live[h] = { l = l, at = at, last = where, extra = extraDb or 0, ratio = r }
    return h
end

-- a playing voice's rise (extraDb, ratio) changed
function SND.set(h, extraDb, ratio)
    local v = h and SND.live[h]
    if not v then return end
    v.extra = extraDb or v.extra
    if ratio then v.ratio = ratio * 2 ^ ((v.l.cents or 0) / 1200) end
end

function SND.stop(h, tail)
    if not h then return end
    if type(SV_SndStop) == "function" then SV_SndStop(h, tail and 1 or 0) end
    if not tail then SND.live[h] = nil end
end

-- one of a random layer's files by weight: l.pick = { { file, weight, db }, ... }, the layer's other settings kept
function SND.pick(l)
    local sum = 0
    for _, f in ipairs(l.pick) do sum = sum + f[2] end
    local x, acc, f = math.random() * sum, 0, l.pick[1]
    for _, g in ipairs(l.pick) do
        acc = acc + g[2]
        if x <= acc then f = g; break end
    end
    return setmetatable({ file = f[1], db = f[3] or l.db }, { __index = l })
end

-- every voice stopped (a run restarted or left: nothing of it plays on)
function SND.stopAll()
    if type(SV_SndStop) == "function" then
        for h in pairs(SND.live) do SV_SndStop(h, 0) end
    end
    SND.live = {}
    SND.songStop(true)
end

-- (0.73.76) A song (CFG.specials.valka.song, the user's own track in their VALKA build: "have it start as the Red Starts
-- to Fade in ... Fade out after her death", "at 75% volume"): one voice, centred, not panned, at `volume` (linear),
-- looped unless loop = false; SND.songFade(s) fades it out over s seconds, then it stops. With game_music = "stop" the
-- game's mission track is stopped while it plays (its BGM controller's <track>_Stop) and posted again after.
SND.song = nil
local function songMusicBack(sg)
    if sg and sg.muted and type(SV_PlayBGM) == "function" then
        log("sound: the game's music back after the song (AKE_System_BGM_Mute_Off: " .. tostring(SV_PlayBGM("AKE_System_BGM_Mute_Off")) .. ")")
    end
    if sg and sg.track and type(SV_PlayBGM) == "function" then
        local r = SV_PlayBGM(sg.track)
        log("sound: the game's music back after the song: " .. sg.track .. " (" .. tostring(r) .. ")")
    end
end
function SND.songStart(sc)
    if SND.song or type(sc) ~= "table" or sc.enabled == false or not sc.file then return end
    local id = SND.id(sc.file)
    if not id then return end
    local v = math.max(0, math.min(1, tonumber(sc.volume) or 0.75))
    local h = SV_SndPlay(id, v, v, 1, sc.loop == false and 0 or 1)
    if not h or h <= 0 then log("sound: the song " .. sc.file .. " didn't play (" .. tostring(h) .. ")"); return end
    SND.song = { h = h, v = v, top = v, at = os.clock() }
    local said = ""
    if sc.game_music == "mute" and type(SV_PlayBGM) == "function" then
        -- (0.73.76) AC8's system mute, whatever plays (the pause menu's music player too: its jukebox kept playing past
        -- the _Stop of the controller's last track, which was the hangar's: tools/re/MUSIC_RADIO_CAMERA.md)
        local r = SV_PlayBGM("AKE_System_BGM_Mute_On")
        SND.song.muted = true
        said = "; the game's music muted (AKE_System_BGM_Mute_On: " .. tostring(r) .. ")"
    elseif sc.game_music == "stop" and type(SV_BGMNames) == "function" and type(SV_PlayBGM) == "function" then
        local track = (SV_BGMNames() or ""):match("^([^|]*)") or ""
        local stop = track:gsub("_Play$", "_Stop")
        if track ~= "" and stop ~= track then
            SND.song.track = track
            said = string.format("; the game's %s stopped (%s: %s)", track, stop, tostring(SV_PlayBGM(stop)))
        else
            said = "; the game's music left as it is (no track to stop: '" .. track .. "')"
        end
    end
    log(string.format("sound: the song %s playing at %d%%%s%s", sc.file, math.floor(v * 100 + 0.5),
        sc.loop == false and "" or ", looped", said))
end
function SND.songFade(secs)
    local sg = SND.song
    if not sg or sg.fadeS then return end
    sg.fadeS, sg.fadeAt = math.max(0.1, tonumber(secs) or 5), os.clock()
    log(string.format("sound: the song fading out over %.0f s", sg.fadeS))
end
function SND.songStop(quiet)
    local sg = SND.song
    if not sg then return end
    SND.song = nil
    if type(SV_SndStop) == "function" then SV_SndStop(sg.h, 0) end
    if not quiet then log("sound: the song stopped") end
    songMusicBack(sg)
end
local function songTick()
    local sg = SND.song
    if not (sg and sg.fadeS) then return end
    local t = (os.clock() - sg.fadeAt) / sg.fadeS
    if t >= 1 then SND.songStop(); return end
    local v = sg.top * (1 - t)
    if SV_SndSet(sg.h, v, v, 1) ~= 1 then SND.song = nil; songMusicBack(sg) end
end

-- the game paused / running: Survival's sounds silent while it's paused (their clock stops, a loop would play on)
function SND.setPaused(paused)
    paused = paused and true or false
    if paused == (SND.paused or false) or not SND.master or type(SV_SndMaster) ~= "function" then return end
    SND.paused = paused
    SV_SndMaster(paused and 0 or db(CFG.sound.master_db))
end

-- a whole event (a list of layers, CFG.sound.valka.<event>) at `at`; the handles
function SND.event(list, at, extraDb, ratio)
    local hs = {}
    for _, l in ipairs(list or {}) do
        local h = SND.play(l.pick and SND.pick(l) or l, at, extraDb, ratio)
        if h then hs[#hs + 1] = h end
    end
    return hs
end

-- ((0.73.79, the lag audit's item 7) VALKA's sounds loaded before her fight: the runtime reads a whole file on the game
-- thread the first time it's played (the song's 45 MB: ~106 ms at her mood's start, ~98 ms at her opener's shot on a
-- tester's PC). SND.preloadValka() queues her song and every file of CFG.sound.valka (from the break before her round,
-- the round's start, or the host's VALKA round on a joiner), and SND.tick loads one a tick: the same ids SND.id keeps
-- after a first play, nothing played)
SND.preQ = nil
function SND.preloadValka()
    if SND.preDone or SND.preQ or not CFG.sound.enabled or type(SV_SndLoad) ~= "function" then return end
    local q, seen = {}, {}
    local function add(f) if type(f) == "string" and not seen[f] and SND.ids[f] == nil then seen[f] = true; q[#q + 1] = f end end
    local sp = CFG.specials and CFG.specials.valka
    if type(sp) == "table" and type(sp.song) == "table" and sp.song.enabled ~= false then add(sp.song.file) end
    local function layers(t)
        if type(t) ~= "table" then return end
        if t.file or t.pick then t = { t } end
        for _, l in ipairs(t) do
            if type(l) == "table" then
                add(l.file)
                for _, p in ipairs(type(l.pick) == "table" and l.pick or {}) do if type(p) == "table" then add(p[1]) end end
            end
        end
    end
    for _, ev in pairs(type(CFG.sound.valka) == "table" and CFG.sound.valka or {}) do layers(ev) end
    SND.preQ, SND.preDone = q, true
    log(string.format("sound: VALKA's %d sound files loading, one a tick, before her fight", #q))
end
local function preloadTick()
    local q = SND.preQ
    if not q then return end
    local f = table.remove(q, 1)
    if f then SND.id(f) end
    if #q == 0 then SND.preQ = nil end
end

-- every tick: the playing voices follow their source and you (pan, distance); the finished ones dropped
function SND.tick()
    if type(SV_SndSet) ~= "function" then return end
    pcall(preloadTick)                                  -- ((0.73.79) VALKA's files, one a tick, before her fight)
    pcall(songTick)                                     -- (0.73.76) the song's fade
    for h, v in pairs(SND.live) do
        local where = v.at
        if type(v.at) == "function" then                -- (its source gone: where it last was, not on you)
            where = v.at() or v.last
            v.last = where
        end
        local left, right = gains(where, v.l.db + v.extra, v.l.curve)
        if SV_SndSet(h, left, right, v.ratio) ~= 1 then SND.live[h] = nil end
    end
end
end
