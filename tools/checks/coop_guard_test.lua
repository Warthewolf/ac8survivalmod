-- coop_guard_test.lua <mod dir> <work dir> (run by tools/checks/coop_guard_test.sh): a hostile-message suite for co-op's
-- Lua layer, where another player's game's messages turn into native calls (SV_Spawn, SV_SetAircraft, SV_SetLevel,
-- SV_Event, SV_CoopBind, SV_Recycle, ...), zollars, health, slots and settings (AGENTS.md "Guards on what other games
-- send"). Every part of the runtime is loaded in main.lua's MODULES order (the real code: sv_coop and its pieces,
-- sv_down, sv_leaderboard, sv_decoy, sv_fishing, sv_escort, sv_spaceport, ...); UE4SS's API is a stub, the runtime's
-- natives (SV_*) are recorders. Each received message runs as the game runs it: COOP.tick's pcall(onMessage, m)
-- (sv_coop_migration.lua), then a joiner's clientRounds (its spawns, director events and held events).
--
-- For every message type the host handles (from a joiner) and the joiner handles (from the host), a valid message is
-- fed first (it must cause no error), then: each field replaced by letters, empty, NaN / inf / huge / negative /
-- fractional numbers, slots 0, 23, 24, 25, -1, over-long text, control characters, format strings, unknown unit and row
-- names; the message cut short at each field; extra fields. Then: the joiner's messages from a slot that isn't the
-- host's; "cf" payloads built with the real encoding (inf, NaN, wrong types, a player's own settings, build data, deep
-- nesting, a 2,000-item list); a flood of 1,800 of each type; a joiner's runtime-style "sys|..." to the host. Each valid
-- message's effect is checked too, so the hostile ones reach a handler that runs. Checked after each message:
--   err      no Lua error escaped to COOP.tick's pcall, and none swallowed by a pcall on the way (every pcall that
--            fails while the message is handled is recorded; a missing method on a stubbed game object is not counted)
--   native   no native called with a unit / NPC row this game doesn't know, an event name that isn't one, a number
--            that isn't finite, an index or id out of the native's range
--   limits   zollars, the airfield's health, slots, the round, the revives' count stay finite and within their limits
--   tables   no queue or table grows past its bound (a flood of 1,800 messages)
--   cf       settings taken only where the fits rule allows (the shipped type, finite, not per-player, not build data)
-- Known defects found by this suite are listed in KNOWN below: each is checked and reported as "KNOWN" (it doesn't fail
-- the suite while it is still there, and fails it once it's fixed, so the entry can be removed); "BY DESIGN" marks a
-- refusal that raises an error on purpose. Anything else found fails the suite. Deterministic: a fixed clock and date,
-- a fixed random seed. A summary table of the message types covered is printed at the end.
local MOD, WORK = arg[1], arg[2]
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore
local T0 = 1762819200                             -- (a fixed date: sv_config_ini.lua seeds math.random from os.time())
os.time = function(t) if t then return T0 end return T0 + math.floor(clock - 1000) end   -- luacheck: ignore
math.randomseed(11)
local rawPrint = print
print = function() end                           -- (the parts' own print: their log lines; the suite's go through say)
local function say(s) rawPrint(s) end

---------------------------------------------------------------------------------------------------- the world
-- names the parts assign as globals (nil while unset, as in the game); any other name is UE4SS's API: a stub that can be
-- called, indexed and used in sums
local MODULES = {}
for m in (readAll(MOD .. "/Scripts/main.lua"):match("local MODULES = {(.-)\r?\n}") or ""):gmatch('"([%w_]+)",') do MODULES[#MODULES + 1] = m end
assert(#MODULES > 20, "main.lua's MODULES not found")
VERSION = readAll(MOD .. "/Scripts/main.lua"):match('VERSION = "([^"]+)"') or "0.0.0"
local SRC = {}
local assigned = {}
for _, m in ipairs(MODULES) do
    local src = readAll(MOD .. "/Scripts/" .. m .. ".lua")
    SRC[m] = src
    for line in src:gmatch("[^\n]+") do
        local fn = line:match("^%s*function%s+([%a_][%w_]*)")
        if fn then assigned[fn] = true end
        local lhs = line:match("^%s*([%a_][%w_%s,%.%[%]]-)%s*=[^=]")
        if lhs and not line:match("^%s*local%s") then
            for id in (lhs .. ","):gmatch("%s*([%a_][%w_]*)[^,]*,") do assigned[id] = true end
        end
    end
end
local stub
local function s_() return stub end
stub = setmetatable({}, {
    __index = s_, __newindex = function() end, __call = s_, __len = function() return 0 end,
    __add = s_, __sub = s_, __mul = s_, __div = s_, __mod = s_, __unm = s_, __idiv = s_, __pow = s_,
    __concat = function(a, b) return tostring(a == stub and "stub" or a) .. tostring(b == stub and "stub" or b) end,
    __lt = function() return false end, __le = function() return false end, __tostring = function() return "stub" end,
})
setmetatable(_G, { __index = function(_, k)
    if type(k) ~= "string" or k:match("^SV_") or assigned[k] then return nil end
    return stub
end })

-- game objects: a table per object, its address live while not gone (SV_ObjChain answers from it)
local LEVEL = " /Game/Mods/SurvivalMode/Maps/PL_SurvivalMode.PL_SurvivalMode:PersistentLevel."
local LIVE, nextAddr = {}, 0x10000
local OBJ = {}
OBJ.__index = OBJ
function OBJ:IsValid() return not self.gone end
function OBJ:GetAddress() return self.addr end
function OBJ:GetFullName() return self.full end
function OBJ:GetFName() local n = self.full:match("([^%.:]+)$"); return { ToString = function() return n end } end
function OBJ:K2_GetActorLocation() return { X = self.x or 0, Y = self.y or 0, Z = self.z or 300000 } end
function OBJ:K2_GetActorRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
function OBJ:SetActorHiddenInGame(v) self.hidden = v end
function OBJ:SetActorEnableCollision(v) self.collision = v end
function OBJ:SetActorTickEnabled() end
function OBJ:SetIsInvincible(v) self.invincible = v end
function OBJ:SetMinHealth(v) self.MinHealth = math.floor(v) end
function OBJ:ModifyHealth(d) if not self.invincible then self.HealthInternal = math.max(0, self.HealthInternal + d) end end
function OBJ:K2_DestroyActor() self.gone = true end
function OBJ:IsA() return self.plane == true end
local function obj(cls, fields)
    nextAddr = nextAddr + 0x10
    local o = setmetatable(fields or {}, OBJ)
    o.addr = nextAddr
    o.full = o.full or (cls .. LEVEL .. cls .. "_" .. nextAddr)
    o.HealthInternal = o.HealthInternal or 1000
    o.MaxHealth = o.MaxHealth or 1000
    LIVE[o.addr] = o
    return o
end

-- the NPC rows this game's DT_SV_NpcMission has (knownRow asks it), and its world data's units
local ROWS = { f16c_common = true, su33_common = true, su47_common = true }
local DT = obj("DataTable", { full = "DataTable /Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission" })
function DT:FindRow(row) return ROWS[row] and {} or nil end
local GS = obj("GameplayStatics", { full = "GameplayStatics /Script/Engine.Default__GameplayStatics" })
function GS:IsGamePaused() return false end
function GS:GetTimeSeconds() return clock end
function GS:GetGlobalTimeDilation() return 1 end
function GS:SetGlobalTimeDilation() end
function GS:ApplyDamage() end
local OBJECTS = { ["/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"] = DT,
                  ["/Script/Engine.Default__GameplayStatics"] = GS }
function StaticFindObject(p) return OBJECTS[p] end
function FindFirstOf() return nil end
function FindAllOf() return {} end
function NotifyOnNewObject() end
function RegisterHook() end
function LoopAsync() end
function ExecuteWithDelay() end
function ExecuteInGameThread(f) end
function RegisterKeyBind() end
function FName(s) return { ToString = function() return tostring(s) end } end

-- the runtime's natives: every one of runtime/survival_rt.c RegisterLua's, recorded
local calls = {}
local NATIVES = {}
do
    local src = readAll(MOD .. "/../../../runtime/survival_rt.c")
    for n in src:gmatch('{ "(SV_[%w]+)", L_') do NATIVES[#NATIVES + 1] = n end
end
assert(#NATIVES > 60, "RegisterLua's table not found in runtime/survival_rt.c")
local inbox, sent = {}, {}
local peerState = {}
local MENU = 16 * 2 + 3
local RET = {
    SV_Version = "0.32.30", SV_MenuChoice = function() return MENU end,
    SV_CoopRecv = function() return table.remove(inbox, 1) or "" end,
    SV_CoopSend = function(msg, rel, to) sent[#sent + 1] = tostring(to) .. ">" .. tostring(msg); return 1 end,
    SV_CoopInfo = "open=1;state=linked;peers=0/linked/40/10/a,1/linked/40/10/b,2/linked/60/10/c",
    SV_CoopPeerAt = function(slot) return peerState[slot] or "" end,
    SV_ObjChain = function(a) local o = LIVE[a]; return (o and not o.gone) and 1 or 0 end,
    SV_InputNow = "0,0,0,500,0,0", SV_CoopShots = "", SV_CoopLoadout = "", SV_CoopPaint = "", SV_PPName = "",
    SV_PPWeapons = "", SV_CoopPeerIds = "", SV_MenuSetting = "", SV_SteamName = "Tester", SV_BuildHash = "", SV_BGMNames = "",
    SV_PostReply = "", SV_GameLuaState = "", SV_LaserState = "", SV_LaserKills = "",
    SV_Ammo = -1, SV_AmmoMax = -1, SV_PlayerTarget = 0, SV_UnitAlive = 0, SV_Recycle = 0, SV_MemMB = 1000, SV_GcBusy = 0,
}
local KNOWN_UNITS = {}
RET.SV_Spawn = function(unit) return KNOWN_UNITS[unit] and 2 or -2 end
RET.SV_UnitAlive = function(unit) return KNOWN_UNITS[unit] and 0 or -2 end   -- (0: none up, as before; -2 the runtime's SV_ERR_NO_UNIT)
for _, n in ipairs(NATIVES) do
    local r = RET[n]
    _G[n] = function(...)
        calls[#calls + 1] = { name = n, args = table.pack(...) }
        if type(r) == "function" then return r(...) end
        if r == nil then return 1 end
        return r
    end
end

---------------------------------------------------------------------------------------------------- the parts
-- (copied as main.lua runs them: each part a chunk named by its path in the work dir, so SCRIPT_DIR is the work dir's
-- and the ini is read and written there)
local logs = {}
function log(s) logs[#logs + 1] = tostring(s) end
for _, m in ipairs(MODULES) do
    local chunk = assert(load(SRC[m], "@" .. WORK .. "/Scripts/" .. m .. ".lua", "t"))
    local ok, err = pcall(chunk)
    if not ok then say("FAIL: " .. m .. ".lua didn't load: " .. tostring(err)); os.exit(1) end
end
function log(s) logs[#logs + 1] = tostring(s) end    -- (sv_core's own wrote to the log file: the lines kept here)
local DIFF = { CurrentDifficulty = 2 }
function difficultyManager() return DIFF end      -- (the game's difficulty: sv_config_ini.lua presetName reads it)
local M = COOP.M
assert(type(M) == "table" and type(M.roster) == "table", "COOP.M missing")
local St = DOWN and DOWN.St
-- this game's units: every unit name in CFG and in the parts' text
do
    local function walk(t, seen)
        if seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "string" and v:match("^[%w_]*Unit_[%w_]+$") then KNOWN_UNITS[v] = true end
            if type(v) == "table" then walk(v, seen) end
        end
    end
    walk(CFG, {})
    for _, src in pairs(SRC) do for u in src:gmatch('"([%w_]*Unit_[%w_]+)"') do KNOWN_UNITS[u] = true end end
    for i = 0, 23 do KNOWN_UNITS["SV_Unit_CoopPeer" .. string.char(65 + i)] = true end
end
ROWS[CFG.coop.default] = true
for _, r in pairs(CFG.coop.airframes) do ROWS[r] = true end
local U1 = "ERA_Unit_01_Dep_Air0"
assert(KNOWN_UNITS[U1], U1 .. " isn't a unit of this build")
local VALKA_UNIT = CFG.specials.valka and CFG.specials.valka.unit

---------------------------------------------------------------------------------------------------- the checks
local fails, okN, nFeed, nKnownMsg = 0, 0, 0, 0
local KNOWN = {}        -- id -> { what, hits } (a defect this suite found, still there: reported, not a failure)
local function knownDefect(id, what, design) KNOWN[id] = KNOWN[id] or { what = what, hits = 0, ex = nil, design = design } end
local cov = {}          -- "<side> <kind>" -> { fed, err, native, limits, tables, cf }
local failsBy = {}
local function covOf(side, kind)
    local key = side .. " " .. kind
    cov[key] = cov[key] or { side = side, kind = kind, fed = 0, err = 0, native = 0, limits = 0, tables = 0, cf = 0, known = 0 }
    return cov[key]
end
local function fail(c, cat, what, msg)
    c[cat] = c[cat] + 1
    local key = c.side .. " " .. c.kind .. " " .. cat
    failsBy[key] = (failsBy[key] or 0) + 1
    if failsBy[key] <= 3 then say(string.format("  FAIL %s %s [%s]: %s (%s)", c.side, c.kind, cat, what, msg:sub(1, 160))) end
    fails = fails + 1
end

-- every pcall that fails while a message is handled is recorded (a stubbed object's missing method aside)
local rawPcall = pcall
local caught, catching = {}, false
local function harness(e) return tostring(e):find("attempt to call a nil value %(method") ~= nil end
pcall = function(f, ...)
    if not catching then return rawPcall(f, ...) end
    local r = table.pack(rawPcall(f, ...))
    if not r[1] and not harness(r[2]) then caught[#caught + 1] = tostring(r[2]) end
    return table.unpack(r, 1, r.n)
end

local function finiteN(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function whole(v, lo, hi) return finiteN(v) and v == math.floor(v) and v >= lo and v <= hi end
local function printable(s) return type(s) == "string" and #s >= 1 and #s < 1024 and not s:find("[^\32-\126]") end
-- (SV_UnitAlive is left out: a question, answered -2 for a unit this game hasn't, as the runtime does; how the joiner
-- learns the host's unit isn't this game's before anything acts on it, 2026-11-11)
local UNIT_ARG = { SV_Spawn = 1, SV_SetAircraft = 1, SV_SetLevel = 1, SV_Recycle = 1 }
-- what's wrong with one native call, or nil
local function badCall(c)
    local a = c.args
    for i = 1, a.n do
        if type(a[i]) == "number" and not finiteN(a[i]) then return "argument " .. i .. " is " .. tostring(a[i]) end
    end
    if UNIT_ARG[c.name] and not KNOWN_UNITS[a[1]] then return "unknown unit '" .. tostring(a[1]):sub(1, 40) .. "'" end
    if c.name == "SV_SetAircraft" then
        if not ROWS[a[2]] then return "unknown NPC row '" .. tostring(a[2]):sub(1, 40) .. "'" end
        if a[3] ~= nil and not whole(a[3], -1, 63) then return "AI object index " .. tostring(a[3]) end
    elseif c.name == "SV_SetLevel" then
        if not whole(a[2], 0, 65535) then return "level " .. tostring(a[2]) end
    elseif c.name == "SV_Spawn" then
        for i = 2, a.n do if not (finiteN(a[i]) and math.abs(a[i]) < 1e10) then return "pose " .. tostring(a[i]) end end
    elseif c.name == "SV_Event" then
        if not (printable(a[1]) and #a[1] <= 64 and a[1]:match("^RE_SV_[%w_]+$")) then return "event '" .. tostring(a[1]):sub(1, 40) .. "' (" .. #tostring(a[1]) .. " chars)" end
    elseif c.name == "SV_CoopBind" then
        if not whole(a[1], 1, 65535) then return "stream id " .. tostring(a[1]) end
    elseif c.name == "SV_SetText" then
        if not printable(a[1]) then return "text key" end
    elseif c.name == "SV_CoopPeer" or c.name == "SV_CoopTrack" then
        if type(a[1]) == "number" and not whole(a[1], 0, 23) then return "slot " .. tostring(a[1]) end
    end
    return nil
end

local function count(t) local n = 0; if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end; return n end
local function slotKeys(t) if type(t) ~= "table" then return true end; for k in pairs(t) do if not whole(k, 0, 23) then return false, k end end; return true end
-- the state a message may change, within its limits: the first broken limit, or nil
local CR0 = 50000
local function badState(credits0)
    if not (whole(RUN.credits, -1e12, 1e12)) then return "zollars " .. tostring(RUN.credits) end
    if RUN.credits < 0 then return "zollars below 0: " .. tostring(RUN.credits) end
    if math.abs(RUN.credits - credits0) > CREDITS_MAX then return "zollars moved by " .. (RUN.credits - credits0) .. " in one message" end
    if not (finiteN(RUN.spent) and finiteN(RUN.earned)) then return "spent / earned " .. tostring(RUN.spent) .. " / " .. tostring(RUN.earned) end
    for _, k in ipairs({ "hp", "full", "max" }) do
        if not finiteN(AF[k]) then return "airfield " .. k .. " " .. tostring(AF[k]) end
    end
    if AF.max <= 0 then return "airfield max " .. tostring(AF.max) end
    if AF.hp < 0 or AF.hp > AF.max then return "airfield health " .. tostring(AF.hp) .. " of " .. tostring(AF.max) end
    if AF.full < 0 or AF.full > AF.max then return "airfield full " .. tostring(AF.full) .. " of " .. tostring(AF.max) end
    if not whole(COOP.slot, 0, 23) then return "this game's slot " .. tostring(COOP.slot) end
    local ok, k = slotKeys(M.roster); if not ok then return "roster slot " .. tostring(k) end
    ok, k = slotKeys(M.peers); if not ok then return "peers slot " .. tostring(k) end
    ok, k = slotKeys(M.ints); if not ok then return "intensity slot " .. tostring(k) end
    for s, r in pairs(M.roster) do
        if type(r) ~= "table" then return "roster entry " .. tostring(s) end
        if #tostring(r.name or "") > 32 or #tostring(r.row or "") > 64 or #tostring(r.ver or "") > 32 then return "roster text too long (slot " .. s .. ")" end
        if tostring(r.name or ""):find("%c") then return "roster name with control characters" end
    end
    for s, e in pairs(M.ints or {}) do
        for _, f in ipairs({ "i", "c" }) do if not (finiteN(e[f]) and e[f] >= 0 and e[f] <= 100) then return "intensity " .. f .. " " .. tostring(e[f]) end end
    end
    if D then
        if not whole(D.round, 0, 100000) then return "round " .. tostring(D.round) end
        if D.at ~= nil and not finiteN(D.at) then return "round clock " .. tostring(D.at) end
        if D.waves and #D.waves > 1000 then return "waves " .. #D.waves end
        if D.wave ~= nil and not whole(D.wave, 0, 1000) then return "wave " .. tostring(D.wave) end
    end
    if M.rnd then
        for _, f in ipairs({ "round", "secs", "wave", "waves", "alive" }) do
            if not (finiteN(M.rnd[f]) and M.rnd[f] >= 0 and M.rnd[f] <= 1e6) then return "the host's rnd " .. f .. " " .. tostring(M.rnd[f]) end
        end
    end
    for id in pairs(M.dead or {}) do if not whole(id, 1, 65535) then return "dead id " .. tostring(id) end end
    if St then
        if not whole(St.count, 0, 100000) then return "revives count " .. tostring(St.count) end
        ok, k = slotKeys(St.since); if not ok then return "down slot " .. tostring(k) end
        -- ((2026-11-11) each player's own revives: "rb" / "rx" / "rc")
        if type(St.per) ~= "table" then return "revives per player " .. tostring(St.per) end
        ok, k = slotKeys(St.per); if not ok then return "revives per player: slot " .. tostring(k) end
        for sl, n in pairs(St.per) do if not whole(n, 0, 100000) then return "revives of slot " .. tostring(sl) .. ": " .. tostring(n) end end
    end
    if RUN.bought then for nm, n in pairs(RUN.bought) do if not whole(n, 0, 1e6) then return "bought " .. tostring(nm) .. " " .. tostring(n) end end end
    return nil
end
-- the tables a flood may grow, and their bounds
local function tableSizes()
    local fl = FISH and FISH.cl or {}
    return {
        spawnQ = { #(M.spawnQ or {}), 256 }, dead = { count(M.dead), 4096 }, pendBind = { count(M.pendBind), 512 },
        pendHp = { count(M.pendHp), 4096 }, hitT = { count(M.hitT), 24 },   -- ((2026-11-11) the Alicorn's: M.notePendHp, hostHit)
        evQ = { #(M.evQ or {}), 64 }, dvQ = { #(M.dvQ or {}), 32 }, holdQ = { #(M.holdQ or {}), 32 },
        cfParts = { count(M.cfParts), 400 }, roster = { count(M.roster), 24 }, builds = { count(M.builds), 64 },
        bdLast = { count(M.bdLast), 513 }, killer = { count(M.killer), 4096 }, fishRows = { count(fl.rows), 64 },
        fishHaul = { count(fl.haul), 25 }, fishWeigh = { count(fl.weigh), 25 }, lbSquad = { LB.co and count(LB.co.squad) or 0, 64 },
        lbSpecials = { LB.co and count(LB.co.specials) or 0, 200 }, succ = { #(M.succ or {}), 24 },
        allyList = { #(M.allyList or {}), 40 }, recycleDue = { #(M.recycleDue or {}), 64 },
        downSince = { St and count(St.since) or 0, 24 }, downPer = { St and count(St.per) or 0, 24 },
        zdDives = { ZDIVE and ZDIVE.d and count(ZDIVE.d.dives) or 0, 8 }, zdHeld = { ZDIVE and ZDIVE.d and #(ZDIVE.d.held or {}) or 0, 64 },
    }
end

---------------------------------------------------------------------------------------------------- the scenes
local CFG0 = deepCopy(CFG)
local HEX = string.rep("ab12", 5)                    -- (a co-op run's id)
local function fillT(into, from)
    for k in pairs(into) do if from[k] == nil then into[k] = nil end end
    for k, v in pairs(from) do
        if type(v) == "table" then
            if type(into[k]) ~= "table" then into[k] = {} end
            fillT(into[k], v)
        else into[k] = v end
    end
end
local pawn
local ENEMY, COPY, PLANE1, PLANE2
local function peer(slot, flags) peerState[slot] = string.format("100000,0,300000,0,0,0,800,100,%d,%d", flags or 3, 100) end
local function tick()
    clock = clock + 0.25
    if D then D.now = clock end
    COOP.tick(0)
    if COOP.client() then roundsTick(clock) end
end
local SIDE
local function scene(side)
    SIDE = side
    if SPORT then SPORT.rkJoin, SPORT.hostRow = { st = {}, ended = {} }, nil end   -- ((2026-11-11) the host's rockets' word)
    fillT(CFG, CFG0)
    CFG.coop.enabled = true
    M.mine, M.mineIn, M.hostPreset, M.hostDiff, M.hostMax = nil, nil, nil, nil, nil
    clock = clock + 2                              -- (every second's rate limits start over)
    for k in pairs(LIVE) do if LIVE[k] ~= DT and LIVE[k] ~= GS then LIVE[k] = nil end end
    pawn = obj("BP_PlayerPlane_PP1000_f16c_C", { MaxHealth = 100, HealthInternal = 800, MinHealth = 0,
                                                 DamageHistoryMap = { ForEach = function() end } })
    survivalPC = obj("BP_LivePlayerController_C", { Pawn = pawn })
    function survivalPC:GetViewTarget() return pawn end
    function survivalPC:SetViewTargetWithBlend() end
    D = { round = 5, state = "fighting", now = clock, at = clock, up = {}, flown = {}, queue = {}, spare = {}, events = {},
          orders = {}, pressure = "B", wave = 1, startRound = 1 }
    RUN = newRun()
    RUN.credits = CR0
    AF = { max = 1000, full = 1000, hp = 1000, down = false, bomb = 0, bombBase = 0, pending = {} }
    COOP.open, COOP.role, COOP.slot = true, side == "host" and "host" or "join", side == "host" and 0 or 1
    MENU = 16 * 2 + (side == "host" and 3 or 4)
    M.raw, M.picked = MENU, side == "host" and "host" or "join"
    M.said = {}
    for k in pairs(peerState) do peerState[k] = nil end
    M.roster = { [0] = { row = "f16c_common", ver = VERSION, name = "A" }, [1] = { row = "f16c_common", ver = VERSION, name = "B" },
                 [2] = { row = "su33_common", ver = VERSION, name = "C" } }
    M.peers = {}
    M.ints, M.buildRate, M.builds, M.tlAt, M.tlN, M.dvAt, M.dvN = {}, {}, {}, nil, nil, nil, nil
    M.spawnQ, M.dead, M.copies, M.cunits, M.pendBind, M.evQ, M.dvQ, M.holdQ, M.rep, M.cfParts = {}, {}, {}, {}, nil, nil, nil, nil, nil, nil
    M.bdLast, M.killer, M.recycleDue, M.rnd, M.succ, M.allyList = nil, nil, nil, nil, {}, {}
    -- ((2026-11-11) the host's "left" notice and the migration it starts: each message's own)
    M.hostLeft, M.hostLostAt, M.hostAwayUntil, M.mig, M.leftPending, M.leftRun = nil, nil, nil, nil, nil, nil
    M.pendHp, M.pendHpN, M.hitT = nil, nil, nil
    M.byId, M.units = {}, {}
    if DOWN and DOWN.reset then DOWN.reset("a hostile message's scene", true) end
    if St then St.rate = {}; St.count = 0 end
    if DECOY and DECOY.rx then DECOY.rx.at, DECOY.rx.n = -100, 0 end
    if FISH and FISH.cl then FISH.cl = { haul = {}, weigh = {}, rows = {}, round = nil } end
    LB.co = nil
    if ALLY and ALLY.state then ALLY.state().order = nil end
    tick()                                         -- (the new run here: COOP.tick builds its lists again)
    -- ((review of 2026-11-11, board-1) a joiner's run the host's round state has reached ("rnd" / "rs"): its "left" notice
    -- is taken only for such a run)
    M.hostRunD, M.hlSkipAt = side ~= "host" and D or nil, nil
    if side == "host" then
        LB.co = { id = HEX, mine = true, squad = {}, n = 0, specials = {}, run = {} }   -- (the host's co-op run: "lb|n")
        peer(1); peer(2)
        ENEMY = obj("BP_OP1022_f16c_CP_C", { plane = true })
        M.byId[5] = { obj = ENEMY, unit = U1, ord = 1, addr = ENEMY.addr }
        M.units[U1] = { gen = 1, n = 1, planes = { { id = 5 } }, ground = {} }
        PLANE1 = obj("BP_NPC_f16c_C", { plane = true }); PLANE2 = obj("BP_NPC_su33_C", { plane = true })
        COOP.peerPlane(PLANE1, 1); COOP.peerPlane(PLANE2, 2)     -- (the other players' planes here: "fx" fires from them)
    else
        peer(0); peer(2)
        COPY = obj("BP_OP1022_f16c_CP_C", { plane = true })
        M.cunits[U1] = { gen = 1, n = 1, planes = { COPY }, binds = { 11 }, gbinds = {}, at = clock - 60, upAt = clock - 60 }
        M.copies[11] = { obj = COPY, exp = 1000, addr = COPY.addr, unit = U1, ord = 1, hp = 1000 }
        M.readyAt = clock - 10                     -- (this level's ready: levelReady)
        M.builds = { [1] = { name = "Wingmen", price = 4000, at = clock } }   -- (a purchase asked of the host: "ak" / "ax")
        if St then St.pending[2] = { price = 5000, at = clock } end          -- (a revive asked of the host: "rx")
    end
    M.raw, M.picked = MENU, side == "host" and "host" or "join"
    calls, sent, logs, caught = {}, {}, {}, {}
end

---------------------------------------------------------------------------------------------------- the messages
-- each message type: its side (who handles it: the host from a joiner, slot 1; the joiner from the host, slot 0), a
-- valid message, and the fields not to fill with huge numbers (a known hang: KNOWN below shows it bounded)
local TYPES = {
    -- the host's (sv_coop_migration.lua onHostMessage, sv_down.lua DOWN.onHost, sv_leaderboard.lua LB.coopMsg)
    { "host", "hi", { "hi", "@VERSION", "0.32.30", "f16c_common", "Bob", "f16c", "5,6/7/1,0", "44/1/9", "F-16C Fighting Falcon", "", "" } },
    { "host", "jn", { "jn" } },
    { "host", "ht", { "ht", "5", "120" } },
    { "host", "ab", { "ab", "1", "Wingmen", "4000", "" } },
    { "host", "ao", { "ao", "@ORDER" } },
    { "host", "fx", { "fx", "m:5:0;s:0:0" } },
    { "host", "dw", { "dw", "1" } },
    { "host", "rv", { "rv", "2", "5000" } },
    { "host", "lb", { "lb", "n", HEX, "Bob" } },
    { "host", "in", { "in", "50", "40", "80", "2" } },
    -- the joiner's (onJoinerMessage and the parts it hands them to)
    { "join", "cf", { "cf", "1", "1", "@CF" } },
    { "join", "fx", { "fx", "2", "m:11:0" } },
    { "join", "ak", { "ak", "1", "BUILT" } },
    { "join", "ax", { "ax", "1", "NO" } },
    { "join", "ar", { "ar", "4000", "NEVER TOOK OFF" } },
    { "join", "ag", { "ag", "@ORDER" } },
    { "join", "sq", { "sq", "76561198000000001", "1:76561198000000002,2:76561198000000003" } },
    { "join", "al", { "al", "Wingmen:76561198000000002" } },
    { "join", "hl", { "hl", "30" } },
    { "join", "lb", { "lb", "r", HEX, "60", "1", "2", "0", "0", "0", "0", "5" } },
    { "join", "hq", { "hq" } },
    { "join", "dw", { "dw", "2", "0" } },
    { "join", "rb", { "rb", "2", "1", "0", "1" } },                -- ((2026-11-11) field 5: theirs, the slot's own revives)
    { "join", "rx", { "rx", "2", "A BAD REQUEST", "0", "3" } },
    { "join", "ro", { "ro", "6" } },
    { "join", "rc", { "rc", "2", "1:1,2:1" } },                     -- ((2026-11-11) field 3: each player's own revives)
    { "join", "rnd", { "rnd", "6", "fighting", "30", "2", "3", "4", "1", "2", "m1w0s0", "", "", "0", "Wingmen:1;", "0", "0:62:0" } },
    { "join", "pi", { "pi", "2", "su33_common", "@VERSION", "Cara", "su33", "5,6/7/1,0", "44/1/9", "Su-33", "76561198000000003", "", "" } },
    { "join", "po", { "po", "2" } },
    { "join", "rj", { "rj", "2" } },
    { "join", "af", { "af", "900", "1000", "0", "1000" } },
    { "join", "co", { "co", "ROUND 6", "INCOMING", "0" } },
    { "join", "tl", { "tl", "@TELL", "1" } },
    { "join", "dv", { "dv", "RE_SV_Salvo_01A", U1, "0" } },
    { "join", "cr", { "cr", "500", "round 5" } },
    { "join", "sp", { "sp", U1, "100000,0,300000,90", "su33_common@0", "2", "2" } },
    { "join", "bd", { "bd", U1, "1", "1", "11" } },
    { "join", "gd", { "gd", "SV_Unit_LcacA", "1", "BP_SH010_lcac_C#1", "31" } },
    { "join", "hp", { "hp", "11:800" } },
    { "join", "dn", { "dn", "11", "", "0" } },
    { "join", "ev", { "ev", "RE_SV_PressureB", "" } },
    { "join", "wd", { "wd", U1 } },
    { "join", "db", { "db", "500", "the escape" } },
    { "join", "dk", { "dk", "s", "bait", "1", "0", "1", "6" } },
    { "join", "zd", { "zd", "b", "1000", "2000", "30000", "3", "1" } },   -- ((2026-11-11) its own down, its dive's id)
    { "join", "sb", { "sb", "COMONA", "Hold on.", "4" } },
    { "join", "fh", { "fh", "1", "@CATCH", "12", "1000", "2000" } },
    { "join", "fsx", { "fsx", "fishing", "on", "1", "2", "3" } },
    { "join", "fw", { "fw", "1", "40", "3", "1", "@CATCH", "12", "0" } },
    { "join", "fwe", { "fwe", "3", "100", "0", "7", "3" } },
    { "join", "spx", { "spx", "a:2:3:40:1;-" } },
    { "join", "rk", { "rk", "A", "escaped", "20200" } },       -- ((2026-11-11) the host's word on a rocket: sv_spaceport.lua)
    { "join", "es", { "es", "route", "1", "4", "80", "12.5", "0", "1", "0", "1" } },
    { "join", "vm", { "vm", "1" } },
    { "join", "vr", { "vr", "@VALKA" } },
    { "join", "rz", { "rz", "1" } },
    { "join", "rs", { "rs", "j" } },
    -- the same types' other forms (fed the same way; the effect checked above is the first form's)
    { "host", "fx", { "fx", "p:5:0:1,2,3;g:5:0;e:0:0" }, extra = true },
    { "host", "lb", { "lb", "r", HEX, "60", "1" }, extra = true },
    { "join", "lb", { "lb", "p", HEX, "sid76561198000000002,1,3,1,0,f16c,Bob;slot2:Cara,2,0,0,1,su33,Cara" }, extra = true },
    { "join", "lb", { "lb", "s", HEX, "1,valka,5,120,1;2,decoy,10,300,0" }, extra = true },
    { "join", "lb", { "lb", "x", HEX }, extra = true },
    { "join", "hl", { "hl", "51", "left" }, extra = true },        -- ((2026-11-11) the host left its run: COOP.hostLeaving)
    { "join", "dk", { "dk", "l", "1", "1", "1" }, extra = true },
    { "join", "dk", { "dk", "c", "1", "down" }, extra = true },
    { "join", "zd", { "zd", "h", "1", "5", "1" }, extra = true },
    { "join", "zd", { "zd", "v", "3", "1" }, extra = true },
    { "join", "zd", { "zd", "e", "1" }, extra = true },
    { "join", "zd", { "zd", "h", "1", "5" }, extra = true },              -- (an older host's: no dive id)
    { "join", "zd", { "zd", "v", "3" }, extra = true },
    { "join", "zd", { "zd", "e" }, extra = true },
    { "join", "ev", { "ev", "RE_SV_AlcnOpenCore", U1 }, extra = true },
    -- ((2026-11-11) the Alicorn: rnd field 16 shut and dived; the host's health for ids not bound here yet, M.pendHp)
    { "join", "rnd", { "rnd", "6", "fighting", "30", "2", "3", "4", "1", "2", "m1w0s0", "alicorn", "alicorn:sail", "0", "Wingmen:1;", "0", "2:s:1" }, extra = true },
    { "join", "hp", { "hp", "77:500,78:-5,79:99999999999,0:40,70000:9" }, extra = true },
    { "join", "rs", { "rs", "n" }, extra = true },
    { "join", "rs", { "rs", "m" }, extra = true },
    { "join", "spx", { "spx", "r:5:2;12:40:11:Fleet1,Fleet2" }, extra = true },
    { "join", "spx", { "spx", "r:5:2:p40:u123;12:40:11:AegisA" }, extra = true },   -- ((2026-11-11) and the rockets' tokens)
    { "join", "rk", { "rk", "B", "pad", "" }, extra = true },
    { "join", "rk", { "rk", "A", "launched", "760" }, extra = true },
    { "join", "rk", { "rk", "B", "down", "9000" }, extra = true },
    { "join", "rk", { "rk", "B", "lost", "" }, extra = true },
    { "join", "co", { "co", "ROCKET A LAUNCHED", "SHOOT IT DOWN BEFORE IT REACHES ORBIT", "1.5" }, extra = true },
    { "join", "fx", { "fx", "0", "p:11:0:1,2,3" }, extra = true },
}
-- the place holders: this build's own values
local ORDER                                           -- (an order of this build's that isn't the one the allies start on)
for _, o in ipairs(CFG.allies.orders.list) do if o ~= ALLY.order() then ORDER = o; break end end
local TELL1 = "brk"
if TELL and CFG.tells then for id in pairs(CFG.tells.lines or CFG.tells) do if type(id) == "string" and TELL.known(id) then TELL1 = id; break end end end
local CATCH = "tuna"
local CFTEXT
do
    -- a valid "cf": what M.sendSettings sends with one setting changed ([coop] isn't synced: the airfield's)
    local cfPath, cfV
    for k, v in pairs(CFG) do if type(v) == "table" and type(v.break_s) == "number" then cfPath, cfV = k, v.break_s end end
    if not cfPath then cfPath, cfV = "first_round_delay_s", CFG.first_round_delay_s end
    COOP.open, COOP.role, COOP.slot = true, "host", 0
    if type(CFG[cfPath]) == "table" then CFG[cfPath].break_s = cfV + 3 else CFG[cfPath] = cfV + 3 end
    sent = {}
    M.sendSettings(1)
    for _, m in ipairs(sent) do local t = m:match("^1>cf|1|1|(.*)$"); if t then CFTEXT = t end end
    fillT(CFG, CFG0)
    assert(CFTEXT, "M.sendSettings sent no cf")
    COOP.open = false
end
local function fill(v)
    if v == "@VERSION" then return VERSION elseif v == "@ORDER" then return ORDER elseif v == "@TELL" then return TELL1
    elseif v == "@CF" then return CFTEXT elseif v == "@CATCH" then return CATCH elseif v == "@VALKA" then return VALKA_UNIT or "SV_Unit_Valka" end
    return v
end
-- the hostile values every field gets
local LONG = string.rep("A", 5000)
local VALUES = { "", "abc", "nan", "inf", "-inf", "1e999", "-1e999", "1e308", "-1e308", "-1", "0", "-0", "1.5", "0.0001",
                 "23", "24", "25", "99", "0x7fffffff", " 7 ", "99999999999999999999", "9007199254740993", LONG,
                 "\1\2\3", "%s%d%n%%", "SV_Unit_Nope", "ERA_Unit_99_Dep_Air9", "no_such_row", "{{{{", "\255\254\195",
                 "a:b:c;d@e", "1,2,3,4", "nan,nan,nan,nan", "1e999,0,0,0", "row@99999999999999999999", "su33_common@99999999999999999999", "su33_common@-5",
                 "RE_SV_" .. string.rep("X", 200), "RE_SV_AlcnRemove", "i1e999", "n1e999", "1:1e999", "0:1", "5:-1" }
local HUGE = { ["inf"] = true, ["1e999"] = true, ["1e308"] = true, ["0x7fffffff"] = true, ["99999999999999999999"] = true,
               ["9007199254740993"] = true }
local NOHUGE = {}   -- ((2026-11-11) rnd's waves were held back here: a huge one froze the joiner; refused now, so fed)

---------------------------------------------------------------------------------------------------- KNOWN defects
-- (each found by this suite in shipped code; a check of its own below shows it, and the summary lists it)
-- (not a defect: dec's own error() for a payload nested past 40, caught by M.onSettings' pcall and logged; counted here
-- so that it shows)
knownDefect("cf-deep", "sv_coop_sync.lua dec: a cf nested past 40 levels raises \"settings nested too deep\", caught "
    .. "and logged by M.onSettings (the settings kept as they were)", true)

---------------------------------------------------------------------------------------------------- feeding
local function msgText(fields) return table.concat(fields, "|") end
local function sigOf(e) return (tostring(e):gsub("0x%x+", "0x"):gsub("%d+%.?%d*", "N")) end
-- one message to a fresh scene; returns the check results
local function feed(side, kind, fields, opts)
    scene(side)
    local c = covOf(side, kind)
    c.fed = c.fed + 1
    nFeed = nFeed + 1
    local known0 = c.known
    local from = (opts and opts.from) or (side == "host" and "1" or "0")
    local body = type(fields) == "string" and fields or msgText(fields)
    local credits0 = RUN.credits
    local cfgBefore = (kind == "cf") and deepCopy(CFG) or nil
    inbox[#inbox + 1] = from .. "|" .. body
    catching = true
    tick(); tick(); tick()
    catching = false
    local what = body:sub(1, 60):gsub("%c", "?")
    local res = { errs = {}, natives = {}, state = nil, cf = nil }
    for _, l in ipairs(logs) do
        if l:find("%.lua:%d+: ") or l:find("^coop: message error") then res.errs[#res.errs + 1] = l end   -- (a Lua error, logged)
    end
    for _, e in ipairs(caught) do if not BASE[sigOf(e)] then res.errs[#res.errs + 1] = "(caught) " .. e end end
    for _, cl in ipairs(calls) do
        local why = badCall(cl)
        if why then res.natives[#res.natives + 1] = cl.name .. ": " .. why end
    end
    res.state = badState(credits0)
    if cfgBefore then
        -- every setting the host's cf changed: one the fits rule allows (the shipped type and size, not each player's)
        local out = {}
        COOP.cfgDiff(CFG, cfgBefore, {}, out)
        for _, e in ipairs(out) do
            local p, v = e[1], e[2]
            local d = CFG_DEFAULTS
            for j = 1, #p do d = type(d) == "table" and d[p[j]] or nil end
            local own = ({ hud = 1, sound = 1, music = 1, leaderboard = 1, menu = 1, probe = 1, ai_watch = 1, stats = 1, tells = 1,
                           profile = 1, flares = 1, log = 1, recycle = 1 })[p[1]]
            local coopOwn = p[1] == "coop" and not (p[2] == "revive" and p[3] ~= "key" and p[3] ~= "ctrl" and p[3] ~= "camera")
            local pathS = table.concat((function() local q = {}; for j = 1, #p do q[j] = tostring(p[j]) end; return q end)(), ".")
            if own or coopOwn then res.cf = "a player's own setting changed: " .. pathS
            elseif d == nil then res.cf = "a setting this build doesn't ship: " .. pathS
            elseif type(v) ~= type(d) then res.cf = "a setting's type changed: " .. pathS .. " " .. type(d) .. " -> " .. type(v)
            elseif type(v) == "number" and not (finiteN(v) and math.abs(v) <= math.max(math.abs(d) * 1000, 100000)) then res.cf = "a number past its size: " .. pathS .. " " .. tostring(v)
            elseif type(v) == "string" and (#v > 1024 or v:find("%c")) then res.cf = "text past its size: " .. pathS end
            if res.cf then break end
        end
    end
    local function report(cat, list, kn)
        for _, m in ipairs(list) do
            if kn and kn(m) then
                local K = KNOWN[kn(m)]
                K.hits = K.hits + 1; K.ex = K.ex or (what .. " -> " .. m); c.known = c.known + 1
            else
                fail(c, cat, what, m)
            end
        end
    end
    local kn = opts and opts.known
    report("err", res.errs, kn and function(m) return kn("err", m) end)
    report("native", res.natives, kn and function(m) return kn("native", m) end)
    if res.state then report("limits", { res.state }, kn and function(m) return kn("limits", m) end) end
    if res.cf then report("cf", { res.cf }, kn and function(m) return kn("cf", m) end) end
    if #res.errs + #res.natives == 0 and not res.state and not res.cf then okN = okN + 1
    elseif c.known > known0 then nKnownMsg = nKnownMsg + 1 end
    return res
end

-- which KNOWN defect a finding is (by message type and what it says), or nil: a new failure
local function knownOf(side, kind)
    -- ((2026-11-11) every defect this suite found is fixed (sv_coop_migration.lua, sv_coop_joiner.lua, sv_fishing.lua,
    -- runtime/coop.c): a finding is a failure again. A new one found and left for later: its id here and a knownDefect)
    return function(cat, m) return nil end
end

-- what a tick swallows with no message at all (the stubbed world's own): not counted against a message
local BASE = {}
for _, side in ipairs({ "host", "join" }) do
    scene(side)
    catching = true
    tick(); tick(); tick()
    catching = false
    for _, e in ipairs(caught) do BASE[sigOf(e)] = true end
end
-- what each valid message does here (so the hostile ones are fed to a handler that runs, not to one the scene stops)
local function called(name, a1) for _, c in ipairs(calls) do if c.name == name and (a1 == nil or c.args[1] == a1) then return true end end return false end
local function sentHas(p) for _, m in ipairs(sent) do if m:find(p) then return true end end return false end
local function logHas(p) for _, l in ipairs(logs) do if l:find(p) then return true end end return false end
local EFFECT = {
    ["host hi"] = function() return M.roster[1] and M.roster[1].name == "Bob" end,
    ["host jn"] = function() return sentHas("^1>rs|j") end,
    ["host ht"] = function() return ENEMY.HealthInternal == 880 end,
    ["host ab"] = function() return sentHas("^1>a[kx]|1|") end,
    ["host ao"] = function() return ALLY.order() == ORDER end,
    ["host fx"] = function() return sentHas("^2>fx|1|") end,             -- (relayed to player 3: passed the checks)
    ["host dw"] = function() return St.since[1] ~= nil end,
    ["host rv"] = function() return sentHas("^1>rx|2|") end,               -- (player 3 isn't down: refused)
    ["host lb"] = function() return LB.co and LB.co.pnames and next(LB.co.pnames) ~= nil end,
    ["host in"] = function() return M.ints[1] and M.ints[1].i == 50 end,
    ["join cf"] = function() return logHas("^coop: playing with the host's settings") end,
    ["join fx"] = function() return logHas("coopfire") or true end,        -- (player 3's plane here not up: nothing fired)
    ["join ak"] = function() return RUN.bought.Wingmen == 1 end,
    ["join ax"] = function() return RUN.credits == CR0 + 4000 end,
    ["join ar"] = function() return RUN.credits == CR0 + 4000 end,
    ["join ag"] = function() return ALLY.order() == ORDER end,
    ["join sq"] = function() return M.hostSid == "76561198000000001" and #M.succ == 2 end,
    ["join al"] = function() return #M.allyList == 1 end,
    ["join hl"] = function() return M.hostAwayUntil ~= nil end,
    ["join lb"] = function() return LB.co and LB.co.run and LB.co.run.round == 5 end,
    ["join hq"] = function() return sentHas(">hi|") end,
    ["join dw"] = function() return St.since[2] ~= nil end,
    ["join rb"] = function() return logHas("^revive: player 3 revived") and St.per[2] == 1 end,
    ["join rx"] = function() return RUN.credits == CR0 + 5000 and St.per[2] == 3 end,
    ["join ro"] = function() return St.ended == true and called("SV_Event", "RE_SV_RunOver") end,
    ["join rc"] = function() return St.count == 2 and St.per[1] == 1 and St.per[2] == 1 end,
    ["join rnd"] = function() return D.round == 6 and D.state == "fighting" and M.rnd.alicorn ~= nil and M.rnd.alicorn.pct == 62 end,
    ["join pi"] = function() return M.roster[2] and M.roster[2].name == "Cara" end,
    ["join po"] = function() return M.roster[2] == nil end,
    ["join rj"] = function() return logHas("started their game over") or true end,
    ["join af"] = function() return AF.hp == 900 end,
    ["join co"] = function() return logHas("ROUND 6") end,
    ["join tl"] = function() return true end,
    ["join dv"] = function() return called("SV_Event", "RE_SV_Salvo_01A") end,
    ["join cr"] = function() return RUN.credits > CR0 end,
    ["join sp"] = function() return called("SV_Spawn", U1) and called("SV_SetAircraft", U1) and called("SV_SetLevel", U1) end,
    ["join bd"] = function() return called("SV_CoopBind", 11) end,
    ["join gd"] = function() return M.pendBind and M.pendBind.SV_Unit_LcacA ~= nil end,
    ["join hp"] = function() return COPY.HealthInternal == 800 end,
    ["join dn"] = function() return M.dead[11] == true end,
    ["join ev"] = function() return called("SV_Event", "RE_SV_PressureB") end,
    ["join wd"] = function() return logHas("took " .. U1 .. " off") end,
    ["join db"] = function() return RUN.credits == CR0 - 500 end,
    ["join dk"] = function() return DECOY.cs and DECOY.cs.state == "bait" end,
    ["join zd"] = function() return true end,
    ["join sb"] = function() return true end,
    ["join fh"] = function() return FISH.cl.haul[1] ~= nil end,
    ["join fsx"] = function() return FISH.cl.rows.fishing ~= nil end,
    ["join fw"] = function() return FISH.cl.weigh[1] ~= nil end,
    ["join fwe"] = function() return FISH.cl.paidRound == 7 end,
    ["join spx"] = function() return SPORT.hostRow and SPORT.hostRow.kind == "a" end,
    ["join rk"] = function() return called("SV_Event", "RE_SV_SpRocketEndA") end,
    ["join es"] = function() return ESC.host and ESC.host.state == "route" end,
    ["join vm"] = function() return M.vmHere == true end,
    ["join vr"] = function() return M.vr ~= nil end,
    ["join rz"] = function() return true end,
    ["join rs"] = function() return M.rep ~= nil end,                        -- (rs|j: a repair, the host's picture to come)
}
say("coop_guard: " .. #NATIVES .. " natives recorded, " .. count(KNOWN_UNITS) .. " units and " .. count(ROWS) .. " NPC rows known")
say("valid messages (each must pass every check)")
for _, t in ipairs(TYPES) do
    local side, kind, tpl = t[1], t[2], t[3]
    local f = {}
    for i, v in ipairs(tpl) do f[i] = fill(v) end
    local r = feed(side, kind, f)
    local eff = EFFECT[side .. " " .. kind]
    local okE, did = rawPcall(eff or function() return false end)
    if t.extra then
        if #r.errs + #r.natives == 0 and not r.state and not r.cf then say(string.format("  ok   %s %s: valid message (%s)", side, kind, f[2] or "")) end
    elseif not (okE and did) then
        fail(covOf(side, kind), "err", "valid", "the valid message did nothing here (" .. (okE and "no effect" or tostring(did)) .. "): the scene doesn't reach its handler")
    elseif #r.errs + #r.natives == 0 and not r.state and not r.cf then
        say(string.format("  ok   %s %s: valid message, handled", side, kind))
    end
end

-- ((2026-11-11) the host's "left" notice and a "jn" while the host has no run: Delta's of 2026-11-10)
do
    local r = feed("join", "hl", { "hl", "51", "left" })
    local ok = M.hostLeft ~= nil and M.hostLeft.round == 51 and M.hostAwayUntil == nil and #r.errs == 0
    if ok then say("  ok   join hl|51|left: the host left its run, round 51 (M.hostLeft)")
    else fail(covOf("join", "hl"), "err", "hl|51|left", "the left notice did nothing (M.hostLeft " .. tostring(M.hostLeft and M.hostLeft.round) .. ")") end
    -- ((review of 2026-11-11, board-1 / board-2) not for a run the host's round hasn't reached, nor with no run here
    scene("join")
    M.hostRunD = nil
    inbox[#inbox + 1] = "0|hl|51|left"
    catching = true; tick(); tick(); catching = false
    local okA = M.hostLeft == nil and M.hostLostAt == nil and M.mig == nil
    scene("join")
    D = nil
    inbox[#inbox + 1] = "0|hl|51|left"
    catching = true; tick(); tick(); catching = false
    if okA and M.hostLeft == nil and M.hostLostAt == nil then say("  ok   join hl|51|left outside a run shared with the host: not taken")
    else fail(covOf("join", "hl"), "err", "hl|51|left unshared", "taken for a run the host's round never reached, or with no run") end
    scene("host")
    D, M.leftRun = nil, { round = 51 }
    inbox[#inbox + 1] = "1|jn"
    catching = true; tick(); tick(); catching = false
    if sentHas("^1>hl|51|left") and not sentHas("^1>rs|") then say("  ok   host jn with no run: no picture, told it left (hl|51|left)")
    else fail(covOf("host", "jn"), "err", "jn without a run", "an empty picture sent, or no left notice") end
    M.leftRun = nil
    scene("host")
    D = nil
    inbox[#inbox + 1] = "1|jn"
    catching = true; tick(); tick(); catching = false
    if not sentHas("^1>rs|") and not sentHas("^1>hl|") then say("  ok   host jn while its level loads: nothing sent (its run's start sends rs|n)")
    else fail(covOf("host", "jn"), "err", "jn while loading", "a picture or a notice sent") end
end

say("hostile messages")
for _, t in ipairs(TYPES) do
    local side, kind, tpl = t[1], t[2], t[3]
    local base = {}
    for i, v in ipairs(tpl) do base[i] = fill(v) end
    local kn = { known = knownOf(side, kind) }
    local skip = NOHUGE[side .. " " .. kind] or {}
    -- each field, each value
    for i = 2, math.max(#base, 2) do
        for _, v in ipairs(VALUES) do
            if not (skip[i] and (HUGE[v] or tonumber(v) and tonumber(v) > 1000)) then
                local f = { table.unpack(base) }
                f[i] = v
                feed(side, kind, f, kn)
            end
        end
    end
    -- cut short at every field, and extra fields
    for n = 1, #base - 1 do feed(side, kind, { table.unpack(base, 1, n) }, kn) end
    local x = { table.unpack(base) }
    x[#x + 1] = "extra"; feed(side, kind, x, kn)
    for _ = 1, 40 do x[#x + 1] = "1e999" end; feed(side, kind, x, kn)
    feed(side, kind, kind .. "|" .. string.rep("|", 300), kn)
    feed(side, kind, msgText(base) .. string.rep("9", 4000), kn)
end

---------------------------------------------------------------------------------------------------- the wrong sender
-- a joiner takes the host's messages from the host's link only (slot 0): the same messages from another joiner's slot
-- (2) or a slot no player has (23, 99) do nothing
say("the wrong sender")
for _, t in ipairs(TYPES) do
    local side, kind = t[1], t[2]
    local eff = EFFECT[side .. " " .. kind]
    if side == "join" and eff and not t.extra then
        local f = {}
        for i, v in ipairs(t[3]) do f[i] = fill(v) end
        -- (an effect that's always true says nothing: those types are fed for their errors and limits only)
        scene("join")
        local okA, a0 = rawPcall(eff)
        local always = okA and a0 == true
        for _, from in ipairs({ "2", "23", "99" }) do
            feed("join", kind, f, { from = from })
            local okE, did = rawPcall(eff)
            if okE and did and not always then fail(covOf("join", kind), "limits", "from slot " .. from, "a joiner took it from player " .. from .. ", not the host") end
        end
    end
end

---------------------------------------------------------------------------------------------------- crafted settings
-- "cf" payloads a hostile host could build with the real encoding (sv_coop_sync.lua enc / dec): each diff entry must be
-- taken only where the fits rule allows; the room's revive price (a shared [coop.revive] setting) is the one that is
say("crafted settings (cf)")
local function encV(v, out)
    local t = type(v)
    if t == "table" and v.__raw then out[#out + 1] = v.__raw
    elseif t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do encV(k, out); encV(v[k], out) end
        out[#out + 1] = "}"
    elseif t == "string" then out[#out + 1] = "s" .. v:gsub("[%%,{}|%c]", function(ch) return string.format("%%%02X", ch:byte()) end)
    elseif t == "number" then out[#out + 1] = math.type(v) == "integer" and string.format("i%d", v) or string.format("n%.17g", v)
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F" end
end
local function cfMsg(diff)
    local tk = {}
    encV({ ver = VERSION, preset = "standard", pdiff = 2, max = 4, diff = diff }, tk)
    return "cf|1|1|" .. table.concat(tk, ",")
end
local function nest(n) local t = 1; for _ = 1, n do t = { t } end; return t end
local big = {}
for i = 1, 2000 do big[i] = "x" end
local deep = {}
for i = 1, 13 do deep[i] = "coop" end
local CRAFT = {
    { "inf",          { { { "first_round_delay_s" }, { __raw = "n1e999" } } } },
    { "nan",          { { { "first_round_delay_s" }, { __raw = "n-nan" } } } },
    { "huge",         { { { "first_round_delay_s" }, 1e300 } } },
    { "letters",      { { { "first_round_delay_s" }, "abc" } } },
    { "a table",      { { { "first_round_delay_s" }, { 1, 2 } } } },
    { "per-player",   { { { "hud", "enabled" }, false }, { { "sound", "volume" }, 0 }, { { "leaderboard", "name" }, "X" } } },
    { "own key",      { { { "coop", "revive", "key" }, "F1" }, { { "coop", "revive", "camera", "back_m" }, 1 } } },
    { "coop's own",   { { { "coop", "partner" }, "x" }, { { "coop", "enabled" }, false }, { { "coop", "airframes", "fa36" }, "su33_common" } } },
    { "build data",   { { { "pool" }, { "ERA_Unit_99_Dep_Air9" } } } },
    { "not shipped",  { { { "no_such_setting" }, 1 }, { { "first_round_delay_s", "x" }, 1 } } },
    { "long text",    { { { "coop", "revive", "respawn" }, string.rep("A", 5000) } } },
    { "control",      { { { "coop", "revive", "respawn" }, "lo\1iter" } } },
    { "deep path",    { { deep, 1 } } },
    { "deep value",   { { { "first_round_delay_s" }, nest(60) } } },
    { "big list",     { { { "coop", "revive", "loiter" }, big } } },
    { "bad entries",  { 1, "x", { 5 }, { {}, 1 }, { { 1, 2, 3 }, 1 }, { { true }, 1 } } },
    { "shared price", { { { "coop", "revive", "price" }, 3000 } } },
}
for _, cr in ipairs(CRAFT) do
    feed("join", "cf", cfMsg(cr[2]), { known = function(cat, m)
        if cat == "err" and m:find("settings nested too deep", 1, true) then return "cf-deep" end
        return nil
    end })
    if cr[1] == "shared price" and CFG.coop.revive.price ~= 3000 then
        fail(covOf("join", "cf"), "cf", "shared price", "the host's [coop.revive] price wasn't taken (" .. tostring(CFG.coop.revive.price) .. ")")
    end
    if cr[1] == "own key" and CFG.coop.revive.key ~= CFG0.coop.revive.key then
        fail(covOf("join", "cf"), "cf", "own key", "the host's revive key taken")
    end
end

---------------------------------------------------------------------------------------------------- floods
-- 1,800 messages of a type (600 a tick, COOP.tick's most) with every number in them counting up and the names that key
-- a table made distinct: no table past its bound, no error, the limits held (zollars: finite and not below 0 only; the
-- host's round bonus has no count a round by design)
say("floods (1,800 messages a type)")
local FLOOD_KNOWN = {}   -- ((2026-11-11) M.spawnQ, the fishing rows and M.pendBind bounded now: SPAWNQ_MAX, PEND_MAX)
local function letters(i) local t = {}; repeat t[#t + 1] = string.char(97 + i % 26); i = i // 26 until i == 0; return table.concat(t) end
local KEYED = { sp = 2, bd = 2, gd = 2, ev = 2, wd = 2, fsx = 2, dv = 3 }   -- (the field a table is keyed by)
local function flood(side, kind, base, loading)
    scene(side)
    local c = covOf(side, kind)
    if loading then M.readyAt = clock + 1e6 end   -- (this joiner's level still loading: what waits for it is held)
    local from = side == "host" and "1|" or "0|"
    for i = 1, 1800 do
        local f = { table.unpack(base) }
        for j = 2, #f do if tonumber(f[j]) and not f[j]:find("[,:;]") then f[j] = tostring(i) end end
        local kj = KEYED[kind]
        if kj then
            if kind == "fsx" then f[kj] = letters(i)
            elseif kind == "ev" then f[kj] = "RE_SV_Flood" .. letters(i)
            elseif kind == "dv" then f[kj] = f[kj] .. "_" .. i
            else f[kj] = f[kj] .. "_" .. letters(i) end
        end
        inbox[#inbox + 1] = from .. table.concat(f, "|")
    end
    c.fed = c.fed + 1800
    catching = true
    tick(); tick(); tick(); tick()
    catching = false
    local errs = 0
    for _, l in ipairs(logs) do if l:find("%.lua:%d+: ") or l:find("^coop: message error") then errs = errs + 1; if errs == 1 then fail(c, "err", "flood", l) end end end
    for _, e in ipairs(caught) do if not BASE[sigOf(e)] then errs = errs + 1; if errs == 1 then fail(c, "err", "flood", "(caught) " .. e) end end end
    local nb = 0
    for _, cl in ipairs(calls) do
        local why = badCall(cl)
        if why and not (kind == "sp" and why:find("unknown unit")) and not (kind == "ev" and why:find("SV_Event")) then
            nb = nb + 1; if nb == 1 then fail(c, "native", "flood", cl.name .. ": " .. why) end
        end
    end
    local st = badState(RUN.credits)
    if st then fail(c, "limits", "flood", st) end
    local over = {}
    for name, v in pairs(tableSizes()) do
        if v[1] > v[2] then
            local K = FLOOD_KNOWN[name] and KNOWN[FLOOD_KNOWN[name]]
            if K then K.hits = K.hits + 1; K.ex = K.ex or string.format("%s flood: M.%s %d entries", kind, name, v[1]); c.known = c.known + 1
            else over[#over + 1] = name .. " " .. v[1] end
        end
    end
    if #over > 0 then fail(c, "tables", "flood", table.concat(over, ", ")) end
end
for _, t in ipairs(TYPES) do
    local base = {}
    for i, v in ipairs(t[3]) do base[i] = fill(v) end
    if not (t[1] == "join" and t[2] == "rnd") then flood(t[1], t[2], base, false) end
end
-- what a joiner holds while its level loads
for _, k in ipairs({ "sp", "ev", "dv", "bd", "gd", "dn" }) do
    for _, t in ipairs(TYPES) do
        if t[1] == "join" and t[2] == k then
            local base = {}
            for i, v in ipairs(t[3]) do base[i] = fill(v) end
            flood("join", k, base, true)
        end
    end
end

---------------------------------------------------------------------------------------------------- the KNOWN defects' own checks
say("the known defects, each shown")
do
    -- ((2026-11-11) fixed: "sys|slot" taken only from the runtime (sender 0) on a joiner, a whole slot 0-23; another game's
    -- "sys|..." is refused by the runtime itself, coop.c CoNetPush, which coop_test.sh checks)
    local c = covOf("host", "sys")
    for _, v in ipairs({ "25", "x", "-1", "1e999", "3" }) do
        scene("host")
        c.fed = c.fed + 1
        inbox[#inbox + 1] = "1|sys|slot|" .. v
        tick()
        if COOP.slot ~= 0 then fail(c, "limits", "1|sys|slot|" .. v, "the host's COOP.slot moved to " .. tostring(COOP.slot)) end
    end
    local cj = covOf("join", "sys")
    for _, v in ipairs({ { "3", 3 }, { "25", nil }, { "x", nil }, { "1.5", nil }, { "-1", nil }, { "1e999", nil } }) do
        scene("join")
        local before = COOP.slot
        cj.fed = cj.fed + 1
        inbox[#inbox + 1] = "0|sys|slot|" .. v[1]
        tick()
        local want = v[2] or before
        if COOP.slot ~= want then fail(cj, "limits", "0|sys|slot|" .. v[1], "the joiner's COOP.slot " .. tostring(COOP.slot) .. ", wanted " .. tostring(want)) end
        scene("join")
        before = COOP.slot
        inbox[#inbox + 1] = "2|sys|slot|3"                -- (from another joiner: never the runtime's)
        tick()
        if COOP.slot ~= before then fail(cj, "limits", "2|sys|slot|3", "a joiner's COOP.slot moved by player 3") end
    end
    -- the other runtime messages a joiner can send as its own (each handled, none may take this game's slot)
    for _, v in ipairs({ "joined", "paired", "restart", "up", "lost", "left", "full", "badver|X", "refused|X|Y", "samerole", "protocol", "" }) do
        feed("host", "sys", "sys|" .. v)
        feed("join", "sys", "sys|" .. v)
    end
    -- rnd's numbers out of range or not whole: the message refused, the round state kept (it froze the joiner, 1e999
    -- waves, and put inf / -5 / 1.5 into D.round, D.at, D.wave)
    local c2 = covOf("join", "rnd")
    for _, bad in ipairs({ "0|rnd|6|fighting|30|2|200000|4", "0|rnd|6|fighting|30|2|1e999|4", "0|rnd|1e999|fighting|30|2|3|4",
                           "0|rnd|-5|fighting|30|2|3|4", "0|rnd|1.5|fighting|30|2|3|4", "0|rnd|6|fighting|inf|2|3|4",
                           "0|rnd|6|fighting|30|1.5|3|4", "0|rnd|6|fighting|30|2|3|-1", "0|rnd|6|%s%d|30|2|3|4", "0|rnd|6||30|2|3|4" }) do
        scene("join")
        inbox[#inbox + 1] = "0|rnd|6|fighting|30|2|3|4"
        tick()
        local keep = M.rnd
        c2.fed = c2.fed + 1
        inbox[#inbox + 1] = bad
        tick()
        if M.rnd ~= keep then fail(c2, "limits", bad, "taken (round " .. tostring(M.rnd and M.rnd.round) .. ")")
        elseif D.waves and #D.waves > 3 then fail(c2, "tables", bad, "#D.waves " .. #D.waves) end
    end
    -- ((2026-11-11) rnd field 16, the host's Alicorn for this game's row (SPC.alicornCode): only "<0-4>:<s|e|0-100>:<0|1>"
    -- is taken, whole numbers in range; anything else leaves no row
    for _, bad in ipairs({ "5:1:0", "0:101:0", "0:-1:0", "0:1.5:0", "0:nan:0", "0:inf:0", "0:1e2x:0", "1:2", "1:2:3", "a:b:c",
                           "0:0x7fffffff:0", "4:" .. string.rep("9", 400) .. ":0", LONG, "\1:\2:\3" }) do
        scene("join")
        c2.fed = c2.fed + 1
        local f = { "0", "rnd", "6", "fighting", "30", "2", "3", "4", "", "", "", "alicorn", "alicorn:sail", "0", ";", "0", bad }
        inbox[#inbox + 1] = table.concat(f, "|")
        tick()
        local a = M.rnd and M.rnd.alicorn
        if a then fail(c2, "limits", "rnd field 16 " .. bad:sub(1, 20), string.format("taken (%s tanks, %s %%)", tostring(a.tanks), tostring(a.pct))) end
    end
    -- ((2026-11-11) the session's review) "gd": a key only in the host's groundKey form ("<class>#<n>"), and a unit's
    -- binds bounded (M.BINDS_MAX) though every key is new: a flood that varies field 4, which the floods above don't
    local cg = covOf("join", "gd")
    scene("join")
    local keys = 5000
    for i = 1, keys do inbox[#inbox + 1] = string.format("0|gd|%s|1|BP_Flood_C#%d|%d", U1, i, i % 65535 + 1) end
    inbox[#inbox + 1] = "0|gd|" .. U1 .. "|1|not a ground key|9"
    for _ = 1, 12 do tick() end
    cg.fed = cg.fed + keys + 1
    local function size(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
    local held = (M.pendBind and M.pendBind[U1] and M.pendBind[U1].gbinds) or (M.cunits[U1] and M.cunits[U1].gbinds) or {}
    local cap = M.BINDS_MAX or 4096
    if size(held) > cap then fail(cg, "tables", "gd flood of new keys", size(held) .. " binds for one unit (bound " .. cap .. ")") end
    if held["not a ground key"] ~= nil then fail(cg, "limits", "gd|...|not a ground key", "taken as a key") end
    if size(held) == 0 then fail(cg, "tables", "gd flood of new keys", "nothing kept: the honest form refused?") end
    -- ((2026-11-11) fixed) af: a fractional maximum used to leave the health taken and the landing state not; now the
    -- whole message is refused, and a good one is taken whole
    local ca = covOf("join", "af")
    scene("join")
    local hp0 = AF.hp
    ca.fed = ca.fed + 1
    inbox[#inbox + 1] = "0|af|10|1000|1|1.5"
    tick()
    if AF.hp ~= hp0 or AF.down == true then fail(ca, "limits", "af|10|1000|1|1.5", "half taken: AF.hp " .. tostring(AF.hp) .. ", AF.down " .. tostring(AF.down)) end
    scene("join")
    ca.fed = ca.fed + 1
    inbox[#inbox + 1] = "0|af|10|1000|1|1000"
    tick()
    if not (AF.hp == 10 and AF.full == 1000 and AF.down == true and AF.max == 1000) then
        fail(ca, "limits", "af|10|1000|1|1000", "not taken whole: AF.hp " .. tostring(AF.hp) .. ", AF.down " .. tostring(AF.down) .. ", AF.max " .. tostring(AF.max))
    end
    scene("join")
    ca.fed = ca.fed + 1
    inbox[#inbox + 1] = "0|af|5000|-3|0|1000"                   -- (over the maximum, under 0: within it)
    tick()
    if not (AF.hp == 1000 and AF.full == 0) then fail(ca, "limits", "af|5000|-3|0|1000", "not clamped: AF.hp " .. tostring(AF.hp) .. ", AF.full " .. tostring(AF.full)) end
end

-- ((2026-11-11) the Spaceport Retake's rockets) a big callout's scale reaches a joiner as a number (it was sent as "1" and
-- taken as true, which the banner's SetRenderScale can't use); a host's "rk": a rocket ended here once a retake, only on
-- escaped or lost, never another letter or state
do
    local ck = covOf("join", "co")
    local rawHC, got = hudCallout, {}
    hudCallout = function(text, sub, big) got[#got + 1] = { text = text, big = big } end
    for _, v in ipairs({ { "1.5", 1.5 }, { "2.0", 2.0 }, { "1", 1.5 }, { "0", nil }, { "inf", nil }, { "nan", nil }, { "9", nil }, { "-2", nil } }) do
        scene("join")
        got = {}
        ck.fed = ck.fed + 1
        inbox[#inbox + 1] = "0|co|ROCKET A LAUNCHED|SHOOT IT DOWN|" .. v[1]
        tick()
        if not (got[1] and got[1].big == v[2]) then
            fail(ck, "limits", "co|...|" .. v[1], "its scale here " .. tostring(got[1] and got[1].big) .. ", not " .. tostring(v[2]))
        end
    end
    hudCallout = rawHC
    local cr = covOf("join", "rk")
    local function ends(L) local n = 0; for _, c in ipairs(calls) do if c.name == "SV_Event" and c.args[1] == "RE_SV_SpRocketEnd" .. L then n = n + 1 end end; return n end
    scene("join")
    for _, m in ipairs({ "rk|A|escaped|20200", "rk|A|escaped|20200", "rk|A|lost|", "rk|C|escaped|1", "rk|A|boom|1", "rk|B|down|1",
                         "rk|B|half|nan", "rk|a|escaped|1", "rk|B|escaped|1e999" }) do
        cr.fed = cr.fed + 1
        inbox[#inbox + 1] = "0|" .. m
    end
    tick(); tick()
    if ends("A") ~= 1 or ends("B") ~= 1 then
        fail(cr, "native", "rk sequence", string.format("rocket A ended %d times, B %d (each once: A's escape, B's escape)", ends("A"), ends("B")))
    end
    inbox[#inbox + 1] = "2|rk|B|pad|"                             -- (another joiner's: never the host's word)
    inbox[#inbox + 1] = "2|rk|B|escaped|1"
    tick(); tick()
    if ends("B") ~= 1 then fail(cr, "limits", "rk from slot 2", "a joiner's rk ended a rocket here") end
end

---------------------------------------------------------------------------------------------------- summary
say("")
say(string.format("%-6s %-5s %7s %5s %6s %6s %6s %4s %5s", "side", "type", "fed", "err", "native", "limits", "tables", "cf", "KNOWN"))
local keys = {}
for k in pairs(cov) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
    local c = cov[k]
    say(string.format("%-6s %-5s %7d %5d %6d %6d %6d %4d %5d", c.side, c.kind, c.fed, c.err, c.native, c.limits, c.tables, c.cf, c.known))
end
local nT, fedT = 0, 0
for _, c in pairs(cov) do nT = nT + 1; fedT = fedT + c.fed end
say(string.format("%d message types (host and joiner), %d messages fed: %d one at a time (%d clean, %d showing a KNOWN defect), "
    .. "the rest in floods", nT, fedT, nFeed, okN, nKnownMsg))
say("")
local ids = {}
for id in pairs(KNOWN) do ids[#ids + 1] = id end
table.sort(ids)
local fixed = 0
for _, id in ipairs(ids) do
    local K = KNOWN[id]
    if K.hits > 0 then
        say(string.format("  %-9s %-15s %4d hits: %s", K.design and "BY DESIGN" or "KNOWN", id, K.hits, K.what))
        if K.ex then say("        e.g. " .. K.ex:gsub("%c", "?"):sub(1, 150)) end
    else
        say(string.format("  FAIL  KNOWN %s no longer seen: fixed? remove it from KNOWN in coop_guard_test.lua (%s)", id, K.what:sub(1, 80)))
        fixed = fixed + 1
    end
end
if fails + fixed > 0 then
    say(string.format("coop_guard: %d FAILED (%d new findings, %d known defects no longer seen)", fails + fixed, fails, fixed))
    os.exit(1)
end
local nd = 0
for _, K in pairs(KNOWN) do if not K.design then nd = nd + 1 end end
say(string.format("coop_guard: passed (%d known defects still there, reported above as KNOWN; not failures)", nd))
