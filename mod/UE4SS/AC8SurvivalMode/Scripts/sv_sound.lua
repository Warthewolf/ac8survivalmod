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

-- every tick: the playing voices follow their source and you (pan, distance); the finished ones dropped
function SND.tick()
    if type(SV_SndSet) ~= "function" then return end
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
