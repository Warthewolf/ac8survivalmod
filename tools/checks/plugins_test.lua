-- plugins_test.lua <mod dir> <example add-on dir> (run by tools/checks/plugins_test.sh): the add-on API
-- (Scripts/sv_plugins.lua, docs/ADDONS.md) with the game stubbed. Survival with no add-ons (no folder, an empty one,
-- no IterateGameDirectories, a folder that looks like a UE4SS mod), the loader (add-on folders in
-- Mods/AC8SurvivalAddons, loaded at the first tick, every add-on found listed), each add-on's own environment (isolation:
-- no Survival global, no debug, copies of the libraries, getmetatable for tables only, collectgarbage
-- "count" only, the walks refused while the level goes, NotifyOnNewObject guarded and dropped, pins let go), versions,
-- requires, check, the guard (an error, a stall, a runaway loop, the time budget), pay, the kinds' fields, give-backs,
-- co-op, hard rules 59 / 63 / 64 and the plane sweep's marks, despawn, run / round events, the example add-on
-- (examples/addons/target_practice) played through, and the hooks in Survival's own files (main.lua, sv_main.lua,
-- sv_stats.lua, sv_leaderboard.lua: docs/ADDONS_MAINTAINING.md). Each part runs in a pcall: an error in one is a FAIL, not the end.
local MOD, EX = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function part(name, fn)
    print(name)
    local ok, err = pcall(fn)
    if not ok then check(false, name .. ": raised " .. tostring(err)) end
end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
-- (the API as main.lua runs it: sv_plugins.lua and the pieces of its family, tools/lua_split_part.py's; parts.lua)
local PARTS = dofile("parts.lua")(MOD, readAll)
local API_SRC = readAll(MOD .. "/Scripts/sv_plugins.lua")
local function loadAPI(env)
    for _, piece in ipairs(PARTS.sources("sv_plugins")) do assert(load(piece.src, "@" .. piece.name, "t", env or _G))() end
end
-- (UE4SS's objects are userdata, which Lua alone can't make: the test's stand-ins are tables the API takes as handles
-- because the test lists them here, PLUGINS.fakeHandles; a table an add-on makes is never one)
local FAKE = setmetatable({}, { __mode = "k" })

-- Survival's globals the API uses, stubbed
local logs = {}
function log(s) logs[#logs + 1] = s end
local LOG = log
function crumb() end
function FName(x) return x end                      -- (UE4SS's, stubbed)
function FText(x) return x end
local function said(pat, from)
    for i = from or 1, #logs do if logs[i]:find(pat, 1, true) then return true end end
    return false
end
CFG = { specials = { rotation = { "shuttle" }, anomaly = { enabled = true } } }
CFG_DEFAULTS = { specials = { rotation = { "shuttle" }, anomaly = { enabled = true } } }
local CFG0, ANOMALY = CFG, CFG.specials.anomaly
SPC = { kinds = {} }
AIRFIELD = { X = 1609639.0, Y = -436414.0 }
D = nil
local paid, badPay = {}, {}
function addCredits(n, why)                         -- (Survival's: "%d" in its log line, so a whole number)
    if math.type(n) ~= "integer" or n <= 0 then badPay[#badPay + 1] = tostring(n) end
    paid[#paid + 1] = { n = n, why = why }
end
TIER = { pay = function(b) return b, 1 end, specialX = function() return 1 end, index = function() return 1 end }
LB = { stat = function() end }
function playerLocation() return { X = 0, Y = 0, Z = 0 } end
local callouts = {}
function hudCallout(t, s) callouts[#callouts + 1] = t .. " / " .. tostring(s) end
function hudTick() end
local HUD_TICK = hudTick
local holds = {}
HUD = { hold = function(on, why) holds[#holds + 1] = (on and "on " or "off ") .. tostring(why); return true end }
local going, held = false, nil
function levelGoing() return going end
LEVEL_DROPS = {}                                    -- (sv_core.lua's: what each part forgets at a level's drop)
local walkHolds = 0                                 -- (calls of Survival's walkHold: none on UE4SS's notify thread)
function walkHold() walkHolds = walkHolds + 1; return held end
function walkBusy() return held or (GC_BUSY and "the engine is freeing objects") or nil end   -- (sv_core.lua's)
local fakeClock = 0
local realClock = os.clock
os.clock = function() return realClock() + fakeClock end   -- luacheck: ignore
local bgm = {}
function SV_PlayBGM(ev) bgm[#bgm + 1] = ev; return 1 end
local actors, nextAddr = {}, 0x1000
local UNIT_CLS, WEAPON_CLS, PLAYER_CLS = { live = true }, { live = true }, { live = true }
local destroyedUnits = 0                            -- (K2_DestroyActor on a game unit: AC8 crashes at the next death)
local function actor(cls, plain)
    nextAddr = nextAddr + 0x10
    local a = { cls = cls, HealthInternal = 100, MaxHealth = 10, live = true, addr = nextAddr, unit = not plain }
    a.full = "LiveAIPlane /Game/Map.Map:PersistentLevel." .. tostring(cls):match("[^/.]*$") .. "_" .. nextAddr
    FAKE[a], a.reads = true, 0
    function a:K2_DestroyActor() self.live = false; if self.unit then destroyedUnits = destroyedUnits + 1 end end
    function a:IsA(c) return (c == UNIT_CLS and self.unit) or (c == WEAPON_CLS and self.weapon == true) or (c == PLAYER_CLS and self.player == true) end
    function a:GetFullName() self.reads = self.reads + 1; return self.full end
    function a:ModifyHealth(d) if not self.invincible then self.HealthInternal = self.HealthInternal + d * 10 end end
    function a:K2_SetActorLocation(l) self.at = l end
    function a:K2_SetActorLocationAndRotation(l) self.at = l end
    actors[#actors + 1] = a
    return a
end
local function reuse(a) a.full = "LiveAIPlane /Game/Map.Map:PersistentLevel.BP_Other_C_" .. a.addr end   -- (another object there now)
local function rec(a) return { obj = a, addr = a.addr, name = a.full:match("([^%.:]+)$") } end         -- (Survival's planes[i])
function valid(o) return type(o) == "table" and o.live ~= false end
function liveObj(o) return valid(o) end
function liveAddr(o) return valid(o) and (o.addr or 1) or nil end
function addrOf(o) return type(o) == "table" and o.addr or o end
function finishUnpaid(o) if o.invincible then return false, o.HealthInternal end o.HealthInternal = 0; return true, 0, "damage event" end
function loadObject(p) return { path = p, live = true, GetFullName = function() return "Class " .. p end } end
local GS = {
    live = true, addr = 0xC0,
    BeginDeferredActorSpawnFromClass = function(_, pc, cls) return actor(cls.path) end,
    FinishSpawningActor = function(_, a) return a end,
}
local NOTE_CLS, NOTE_GONE = {}, {}                  -- (a NotifyOnNewObject class, as StaticFindObject finds it)
SFO_N = 0                                            -- (UE4SS's StaticFindObject asked: a walk of every object)
function StaticFindObject(p)
    SFO_N = SFO_N + 1
    if NOTE_CLS[p] and not NOTE_GONE[p] then return NOTE_CLS[p] end
    if p:find("GameplayStatics", 1, true) then return GS end
    if p == "/Script/Live.LiveGameObject" then return UNIT_CLS end      -- (ALiveGameObject: every game object the game caches)
    if p == "/Script/Live.LiveWeaponBase" then return WEAPON_CLS end
    if p == "/Script/Live.LivePlayerPlane" then return PLAYER_CLS end
    if p == "/Script/Niagara.Default__NiagaraFunctionLibrary" then return NIAGARA end
end
NIAGARA = { live = true, spawned = 0, GetFullName = function() return "NiagaraFunctionLibrary /Script/Niagara.Default__NiagaraFunctionLibrary" end,
    SpawnSystemAtLocation = function(self) self.spawned = self.spawned + 1
        return { live = true, SetVariableFloat = function() end, K2_SetWorldRotation = function() end } end }
local finds = 0
function FindAllOf() finds = finds + 1; return {} end
function FindFirstOf() finds = finds + 1; return nil end
local notified = {}                                 -- (UE4SS's NotifyOnNewObject: one callback a class)
local NOTIFY_REFUSE = {}                            -- (classes UE4SS can't find yet: it raises)
function NotifyOnNewObject(cls, fn)
    if NOTIFY_REFUSE[cls] then error("NotifyOnNewObject: no class " .. cls) end
    NOTE_CLS[cls] = NOTE_CLS[cls] or { live = true, path = cls }
    notified[cls] = function(o)                     -- (an object UE4SS tells of is of that class: IsA says so)
        if type(o) == "table" then
            local isA = o.IsA
            o.IsA = function(self, c) if c == NOTE_CLS[cls] then return not self.notA end return isA ~= nil and isA(self, c) or false end
        end
        return fn(o)
    end
end
survivalPC = { live = true, addr = 0xD0 }
local paused = false
function gamePaused() return paused end
local REFS = {}                                     -- (the GameInstance's ReferencedObjects)
local GI = { live = true, ReferencedObjects = REFS }
function gameInstance() return GI end
local intercepts = 0
function SV_Intercept(m) intercepts = intercepts + 1; return m.inFlight and 1 or 0 end
-- natives (C functions: the standard library's stand in) for the environments' natives.txt rule
EXT_Native, EXT2_Undeclared, SV_Fake = os.time, os.time, os.time
LoopAsync, ExecuteInGameThread, ExecuteWithDelay, RegisterKeyBind, RegisterHook = print, print, print, print, print
SCRIPT_DIR = "x\\Game\\Binaries\\Win64\\ue4ss\\Mods\\AC8SurvivalMode\\Scripts\\"   -- (no drive letter: paths_check)
local ADDONS = SCRIPT_DIR .. "..\\..\\AC8SurvivalAddons\\"
-- the add-on folder there or not, as the C runtime answers io.open on a folder (13: it's a folder, 2: none)
local FOLDER, MODLIKE, LISTED = "there", false, false
local realOpen = io.open
io.open = function(p, m)                                                          -- luacheck: ignore
    if p == ADDONS:sub(1, -2) then return nil, p .. ": stub", FOLDER == "there" and 13 or 2 end
    if MODLIKE == "enabled" and p == ADDONS .. "enabled.txt" then return { close = function() end } end
    if MODLIKE == "main" and p == ADDONS .. "Scripts\\main.lua" then return { close = function() end } end
    if MODLIKE == "modstxt" and p == SCRIPT_DIR .. "..\\..\\mods.txt" then
        local l = { "AC8SurvivalMode : 1", "AC8SurvivalAddons : 1 ; (a line of its own)" }
        return { close = function() end, lines = function() local i = 0; return function() i = i + 1; return l[i] end end }
    end
    if LISTED and p == ADDONS .. "addons.txt" then
        local l = { "t_txt\\a.lua", "# a comment", "not a line of it" }
        return { close = function() end, lines = function() local i = 0; return function() i = i + 1; return l[i] end end }
    end
    if LISTED and p == ADDONS .. "t_txt\\a.lua" then
        return { close = function() end, read = function()
            return [[SVP.register("txtk", { name = "Listed", api = "2.0", kind = { spawn = function() return true end } })]] end }
    end
    return realOpen(p, m)
end
local function SLOW_FAKE() fakeClock = fakeClock + 2.1 end
local function BUSY_FAKE() fakeClock = fakeClock + 0.5 end
local function RUN_FAKE() fakeClock = fakeClock + 1 end
-- (the test's own watchdog for a loop the API doesn't stop: it fires after 3 s of real time, and says so. The API's
-- runaway hook calls it on from inside an add-on's call; fired 3 times (a loop that catches it), the suite stops with
-- a FAIL naming the part, rather than hanging until run_all's time-out)
local WD = { fired = 0 }
local function watchdog(on, name)
    if not on then debug.sethook(); return end
    local t0, n = realClock(), 0
    debug.sethook(function()
        if realClock() - t0 > 3 then
            t0, n = realClock(), n + 1
            WD.fired = WD.fired + 1
            if n >= 3 then
                print("  FAIL the test's watchdog: a loop the API doesn't stop (" .. tostring(name) .. "): the suite stopped")
                os.exit(1)
            end
            error("WATCHDOG", 2)
        end
    end, "", 100000)
end
local function asAddon(kind, fn, ...)          -- (a call made from inside the add-on's own callback)
    if PLUGINS.calls then PLUGINS.calls = PLUGINS.calls + 1 end   -- (a call of its own: names read again)
    local prev = PLUGINS.running
    PLUGINS.running = PLUGINS.kinds[kind]
    local r = table.pack(pcall(fn, ...))
    PLUGINS.running = prev
    if not r[1] then error(r[2], 0) end
    return table.unpack(r, 2, r.n)
end
local function skips(r)                         -- (what sv_main.lua planeSweep decides for a plane seen down)
    if PLUGINS.owns then return PLUGINS.owns(r) == true end
    return (PLUGINS.retired and PLUGINS.retired[r.addr or addrOf(r.obj) or 0]) and true or false
end
local function addon(folder)                    -- (an add-on's record and its environment: what it set)
    for _, p in ipairs(PLUGINS.loaded) do if p.folder == folder then return p, p.env end end
    error("no add-on " .. folder .. " loaded")
end
local function ENV(folder) return select(2, addon(folder)) end

part("Survival with no add-ons: as before", function()
    local function bare(mode, igd)
        local env = setmetatable({}, { __index = _G })
        local calls = 0
        if igd then
            env.IterateGameDirectories = function()
                calls = calls + 1
                local mods = { AC8SurvivalMode = {} }
                if mode == "empty" or mode:match("^mod") then mods.AC8SurvivalAddons = {} end
                return { Game = { Binaries = { Win64 = { ue4ss = { Mods = mods } } } } }
            end
        else
            env.IterateGameDirectories = false
        end
        FOLDER = (mode == "missing") and "missing" or "there"
        MODLIKE = (mode == "modlike" and "enabled") or (mode == "modmain" and "main") or (mode == "modstxt" and "modstxt") or false
        LISTED = mode == "listed"
        local from = #logs + 1
        local kinds0 = 0
        for _ in pairs(SPC.kinds) do kinds0 = kinds0 + 1 end
        loadAPI(env)
        env.PLUGINS.tick()
        local kinds1 = 0
        for _ in pairs(SPC.kinds) do kinds1 = kinds1 + 1 end
        FOLDER, MODLIKE, LISTED = "there", false, false
        return { calls = calls, from = from, env = env, same = kinds0 == kinds1 and #CFG.specials.rotation == 1
            and rawget(env, "hudTick") == nil and hudTick == HUD_TICK and #env.PLUGINS.loaded == 0 }
    end
    local r = bare("missing", true)
    check(r.calls == 0 and said("plugins: none (no AC8SurvivalAddons folder)", r.from) and r.same,
        "no AC8SurvivalAddons folder: no walk of the game's folders (IterateGameDirectories not called), nothing changed")
    r = bare("empty", true)
    check(said("plugins: none in AC8SurvivalAddons", r.from) and r.same, "an empty AC8SurvivalAddons: nothing loaded, nothing changed")
    r = bare("there", false)
    check(said("plugins: none (no IterateGameDirectories)", r.from) and r.same,
        "no IterateGameDirectories (and no addons.txt): nothing loaded, nothing changed")
    r = bare("modlike", true)
    check(said("looks like a UE4SS mod (AC8SurvivalAddons\\enabled.txt)", r.from),
        "an AC8SurvivalAddons that looks like a UE4SS mod (an enabled.txt): said in the log")
    r = bare("modmain", true)
    check(said("looks like a UE4SS mod (AC8SurvivalAddons\\Scripts\\main.lua)", r.from), "a Scripts\\main.lua in it: said")
    r = bare("modstxt", true)
    check(said("looks like a UE4SS mod (a line in Mods\\mods.txt)", r.from), "a line for it in Mods\\mods.txt: said")
    r = bare("listed", false)
    local txt = r.env.PLUGINS.loaded[1]
    check(txt ~= nil and txt.folder == "t_txt" and #r.env.PLUGINS.loaded == 1 and SPC.kinds.txtk ~= nil and not txt.off,
        "no IterateGameDirectories, an addons.txt: the add-on it lists loaded from it (its kind registered)")
    SPC.kinds.txtk, CFG.specials.txtk = nil, nil
end)

-- the add-ons: the example and the test's own, each a folder (name -> its files, in order)
local TEST_ADDONS = {
    a_rot1 = { ["a.lua"] = [[SVP.register("rot1", { name = "Rot1", api = "2.0", rotation = true, kind = { spawn = function() return true end } })]] },
    a_rot2 = { ["a.lua"] = [[SVP.register("rot2", { name = "Rot2", api = "2.0", rotation = true, kind = { spawn = function() return true end } })]] },
    b_budget = { ["a.lua"] = [[SVP.register("bud", { name = "Bud", api = "2.0", kind = { spawn = function() return true end,
        tick = function() BUSY_FAKE() end, busy = function() return true end } })]] },
    c_coop = { ["a.lua"] = [[COOPK = { SVP.register("coopk", { name = "CoopOne", api = "2.0", coop = true, cfg = { a = 1, list = { 1, 2 } },
        kind = { spawn = function() COOP_SPAWNED = true; return true end, busy = function() return true end } }) }
        SVP.every(function() COOP_EVERY = (COOP_EVERY or 0) + 1 end)
        SVP.on("roundStart", function() COOP_ON = (COOP_ON or 0) + 1 end)
        SVP.going(function() COOP_GOING = (COOP_GOING or 0) + 1 end)
        CFG_WRITE = pcall(function() SVP.cfg().a = 2 end)
        CFG_READ = SVP.cfg().a + #SVP.cfg().list]] },
    e_err = { ["a.lua"] = [[SVP.every(function() ERR_EVERY = true end)
        SVP.on("roundStart", function() ERR_ON = true end)
        SVP.going(function() ERR_GOING = true end)
        ERR_PROVIDE = SVP.provide("hurtPlayer", function() ERR_HURT = true; return 1 end)
        error("boom at load")]] },
    g_give = { ["a.lua"] = [[SVP.register("giv1", { name = "Give", api = "2.0", kind = { spawn = function()
        SVP.bgm(false); SVP.hud(false, "test"); return false end } })]] },
    h_every = { ["a.lua"] = [[SVP.every(function() if MUTE_NOW then MUTE_NOW = false; SVP.bgm(false) end end)]] },
    j_jobs = { ["a.lua"] = [[SVP.every(function() if JOBS_GROW then SVP.every(function() GREW = (GREW or 0) + 1 end) end end)]] },
    k_order = { ["a.lua"] = [[ORD = {}
        SVP.going(function() ORD[#ORD + 1] = "levelGoing" end)
        SVP.on("roundEnd", function() ORD[#ORD + 1] = "roundEnd"; PAY_IN_END = SVP.pay(1, "roundEnd") end)
        SVP.on("runEnd", function() ORD[#ORD + 1] = "runEnd" end)
        SVP.register("ordk", { name = "Order", api = "2.0", kind = { spawn = function() return true end, busy = function() return true end,
            abort = function(why) ORD[#ORD + 1] = "abort:" .. tostring(why) end } })]] },
    m_fail = { ["a.lua"] = [[SVP.register("twok", { name = "TwoFail", api = "2.0", rotation = true, cfg = { x = 1 },
        kind = { spawn = function() return true end } })]], ["b.lua"] = "this isn't Lua (" },
    m_offload = { ["a.lua"] = [[SVP.register("offk", { name = "OffLoad", api = "2.0", rotation = true, kind = { spawn = function() return true end } })
        OFF_NOW()]], ["b.lua"] = [[OFF_B_RAN = true]] },
    ["bad name!"] = { ["a.lua"] = [[BAD_NAME_RAN = true]] },
    n_nolua = { ["natives.txt"] = "EXT_*\n" },
    Scripts = { ["main.lua"] = [[SCRIPTS_RAN = true]] },
    p_prov = { ["a.lua"] = [[PROV = { SVP.provide("hurtPlayer", function(pa, n, ca) HURT = { pa, n, ca }; return 1 end) }]] },
    r_raw1 = { ["a.lua"] = [[SVP.register("raw1", { name = "Raw1", api = "2.0", kind = { spawn = function() return true end,
        tick = function(now, s) rawset(s, "state", "shadow") end } })]] },
    r_raw2 = { ["a.lua"] = [[SVP.register("raw2", { name = "Raw2", api = "2.0", kind = { spawn = function() return true end,
        tick = function(now, s) SEEN = s.state end } })
        SVP.every(function() if FIND_NOW then FIND_NOW = false; FOUND = FindAllOf("Actor"); FOUND1 = FindFirstOf("Actor")
            FOUND_S = StaticFindObject("/Script/Engine.Default__GameplayStatics") end end)]] },
    k_kinds = { ["a.lua"] = [[KINDS = {}
        KINDS.badair = { SVP.register("kbad", { name = "Kinds", api = "2.0", kind = { spawn = function() return true end, aircraft = "x" } }) }
        KINDS.named = { SVP.register("anomaly", { name = "Kinds", api = "2.0", kind = { spawn = function() return true end } }) }
        KINDS.ok = { SVP.register("kvals", { name = "Kinds", api = "2.0", kind = { spawn = function() return true end,
            budget = function() return nil end, aircraft = function() return "lots" end, row = function() return 5 end,
            ready = function(round) return round >= 2 end } }) }]] },
    l_old = { ["a.lua"] = [[OLDMAJOR = { SVP.register("oldk", { name = "OldMajor", api = "1.0", kind = { spawn = function() return true end } }) }]] },
    m_multi = { ["a.lua"] = [[MULTI_A = 41]], ["b.lua"] = [[MULTI_B = MULTI_A + 1; DIR = SVP.dir()]] },
    n_newer = { ["a.lua"] = [[SVP.every(function() NEWER_EVERY = true end)
        SVP.on("roundStart", function() NEWER_ON = true end)
        SVP.going(function() NEWER_GOING = true end)
        NEWER = { SVP.register("newerk", { name = "Newer", api = "3.0", kind = { spawn = function() return true end } }) }]] },
    o_over = { ["a.lua"] = [[SVP.register("ovr", { name = "Over", api = "2.0", kind = { spawn = function() return true end,
        over = function() OVER_CALLED = true end } })]] },
    r_req = { ["a.lua"] = [[REQ = { SVP.register("reqk", { name = "Req", api = "2.0", requires = { "SV_NoSuchThing" },
        kind = { spawn = function() return true end } }) }]] },
    s_spawner = { ["a.lua"] = [[SVP.register("spn", { name = "Spawner", api = "2.0", kind = { spawn = function()
        SPN_A = SVP.spawn("/Game/X/BP_Thing.BP_Thing_C", { X = 0, Y = 0, Z = 0 }, 0); return true end,
        tick = function() error("tick boom") end, busy = function() return true end } })]] },
    v_one = { ["a.lua"] = [[ONE = { SVP.register("onek", { name = "One", kind = { spawn = function() return true end } }) }]] },
    w_runaway = { ["a.lua"] = [[RUNAWAY_LOADED = true
        while true do RUN_FAKE() end]] },
    w_spin = { ["a.lua"] = [[SVP.register("spin", { name = "Spin", api = "2.0", kind = { spawn = function() return true end,
        tick = function() while true do RUN_FAKE() end end, busy = function() return true end } })]] },
    w_escape = { ["a.lua"] = [[SVP.register("escp", { name = "Escape", api = "2.0", kind = { spawn = function() return true end,
        tick = function()
            for i = 1, 50 do if pcall(function() while true do RUN_FAKE() end end) then break end end
            ESCAPED = true
        end, busy = function() return true end } })]] },
    w_escx = { ["a.lua"] = [[SVP.register("escx", { name = "EscapeX", api = "2.0", kind = { spawn = function() return true end,
        tick = function()
            xpcall(function() while true do RUN_FAKE() end end, function(e) for i = 1, 50 do HANDLED = (HANDLED or 0) + 1 end return e end)
            XESCAPED = true
        end, busy = function() return true end } })]] },
    w_nested = { ["a.lua"] = [[SVP.register("nest", { name = "Nested", api = "2.0", kind = { spawn = function() return true end,
        tick = function()
            for i = 1, 400 do
                RUN_FAKE()
                local x = 0
                for j = 1, 300 do x = x + j end
                SVP.kill(SVP.target(NEST_ACTOR(), { onDown = function() end }), "nested")
            end
            NESTED_DONE = true
        end, busy = function() return true end } })]] },
    w_nslow = { ["a.lua"] = [[SVP.register("nslow", { name = "NSlow", api = "2.0", kind = { spawn = function() return true end,
        tick = function() SVP.kill(SVP.target(NEST_ACTOR(), { onDown = function() SLOW_FAKE() end }), "slow nested") end,
        busy = function() return true end } })]] },
    u_tables = { ["a.lua"] = [[local mt = { __index = function(_, k) KIND_INDEX = (KIND_INDEX or 0) + 1 end }
        SVP.register("utab", { name = "Tables", api = "2.0",
            cfg = { n = 1, list = { 1, "a", true }, sub = setmetatable({ x = 1 }, { __pairs = function(t) PAIRS_RAN = true; return next, t, nil end }),
                deep = { { 1 } } },
            check = function() if CHECK_NO then return false, setmetatable({}, { __tostring = function() WHY_TOSTR = true; return "why" end }) end return true end,
            kind = setmetatable({ spawn = function() return true end, busy = function() return true end }, mt) })
        LABEL = setmetatable({}, { __tostring = function() LABEL_TOSTR = true; return "lbl" end })
        OPTS = setmetatable({ flat = true, label = LABEL }, { __index = function(_, k) OPTS_INDEX = (OPTS_INDEX or 0) + 1; if k == "pay" then return 100 end end })]] },
    t_drop = { ["a.lua"] = [[SVP.register("tdrop", { name = "Drop", api = "2.0", kind = { spawn = function() return DROP_SAY_NO ~= true end,
        tick = function() if DROP_BOOM then error("drop boom") end end, busy = function() return true end } })]] },
    x_bad = { ["a.lua"] = [[SVP.register("badk", { name = "Bad", api = "2.0", kind = { spawn = function() return true end,
        tick = function() error("boom") end, busy = function() return true end } })]] },
    y_slow = { ["a.lua"] = [[SVP.register("slowk", { name = "Slow", api = "2.0", kind = { spawn = function() SVP.bgm(false); return true end,
        tick = function() SLOW_FAKE() end, busy = function() return true end } })
        EV = {}
        for _, e in ipairs({ "runStart", "roundStart", "roundEnd", "runEnd" }) do
            SVP.on(e, function(now, a) EV[#EV + 1] = e .. (a and (":" .. a) or "") end)
        end]] },
    z_tostr = { ["a.lua"] = [[SVP.register("tostr", { name = "ToStr", api = "2.0", kind = { spawn = function() return true end,
        tick = function() error(setmetatable({}, { __tostring = function() error("can't print me") end })) end } })]] },
    -- isolation: an add-on trying each way out (each in its own folder)
    q_globals = { ["a.lua"] = [[log = function() end; PLUGINS = nil; CFG = nil; LB = nil; D = 7
        string.format = nil; math.randomseed = nil; SVP.pay = nil; SECRET = "q"
        GOT = { type(PLUGINS), type(CFG), type(LB), type(addCredits), type(levelGoing), type(SPC), type(_G.CFG) }]] },
    q_lib = { ["a.lua"] = [[LIB = { fmt = type(string.format), dbg = type(debug), smeta = getmetatable(""), tmeta = getmetatable(setmetatable({}, { x = 1 })),
            count = type(collectgarbage("count")), collect = pcall(collectgarbage, "collect"), secret = type(SECRET),
            seed = type(math.randomseed), dump = type(string.dump), co = type(coroutine), req = type(require),
            unsafe = table.concat({ type(LoopAsync), type(ExecuteInGameThread), type(ExecuteWithDelay), type(RegisterKeyBind),
                type(RegisterHook), type(os.execute), type(io.popen), type(os.remove), type(IterateGameDirectories) }, ","),
            write = io.open("q_lib_write.tmp", "w"), bytecode = load("\27Lua\84\0"), loadenv = load("return SVP ~= nil")(),
            natives = table.concat({ type(EXT_Native), type(EXT2_Undeclared), type(SV_Fake), type(SV_Intercept), type(SV_PlayBGM) }, ",") }
        LIB.dbgcall = pcall(function() return debug.getupvalue(SVP.pay, 1) end)]],
        ["natives.txt"] = "# natives this add-on's native mod gives\nEXT_*\nSV_Fake\n" },
    q_gc = { ["a.lua"] = [[GC_SET = pcall(setmetatable, {}, { __gc = function() SVP.pay(777, "a finalizer") end })
        GC_PLAIN = getmetatable(setmetatable({}, { __index = { x = 1 } })) ~= nil
        SVP.register("gck", { name = "Gc", api = "2.0", kind = { spawn = function() return true end,
            tick = function() error("gc off") end } })]] },
    q_state = { ["a.lua"] = [[SVP.register("qstate", { name = "QState", api = "2.0", kind = { spawn = function() return true end,
        tick = function(now, s) s.state = "countdown" end, busy = function() return true end } })]] },
    q_walks = { ["a.lua"] = [[SVP.going(function() GOING_FIND = FindAllOf("Actor"); GOING_RAN = true end)
        SVP.every(function() if TRY_FIND then TRY_FIND = false; HELD_FIND = FindAllOf("Actor"); HELD_RAN = true end end)
        NOTE = NotifyOnNewObject("/Script/Live.LiveMissile", function(o) NOTED = (NOTED or 0) + 1; if o.boom then error("noted boom") end end)]] },
    q_notify2 = { ["a.lua"] = [[NotifyOnNewObject("/Script/Live.LiveMissile", function() NOTED2 = (NOTED2 or 0) + 1 end)]] },
    q_pins = { ["a.lua"] = [[PINNED = 0
        SVP.every(function() if PIN_ALL then PIN_ALL = false
            for i = 1, 70 do if SVP.pin(HANDLE({ live = true, addr = 0x9000 + i }), "test " .. i) then PINNED = PINNED + 1 end end end end)
        SVP.every(function() if PIN_MORE then PIN_MORE = false; PINNED2 = SVP.pin(HANDLE({ live = true, addr = 0x9900 }), "more")
            if PIN_BOOM then error("pins boom") end end end)]] },
    -- (a runaway stop that would land in a nested guarded call's own lines)
    w_window = { ["a.lua"] = [[SVP.register("wwin", { name = "Window", api = "2.0", kind = { spawn = function() return true end,
        tick = function()
            local id = SVP.target(NEST_ACTOR(), { onDown = function() return SETHOOK(PASTDUE(), "", 1) end })
            SVP.kill(id, "window")
            WINDOW_DONE = true
        end, busy = function() return true end } })]] },
    w_after = { ["a.lua"] = [[SVP.register("waft", { name = "After", api = "2.0", kind = { spawn = function() return true end,
        tick = function() local x = 0; for i = 1, 300000 do x = x + i end; AFTER_OK = x end, busy = function() return true end } })]] },
    -- a provider that loops, called from another add-on's tick
    -- (a loop that toggles Survival's HUD and music: stopped in its own lines, so every give-back finds its flag)
    w_hudloop = { ["a.lua"] = [[SVP.register("hudloop", { name = "HudLoop", api = "2.0", kind = { spawn = function() return true end,
        busy = function() return true end,
        tick = function() local n = 0 while true do SVP.bgm(false); SVP.hud(false, "x"); SVP.bgm(true); SVP.hud(true, "x")
            n = n + 1; if n % 100 == 0 then RUN_FAKE() end end end } })]] },
    -- (a caller that loops calling another add-on's short provider: the caller is the one that loops)
    w_blame = { ["a.lua"] = [[SVP.register("blamer", { name = "Blamer", api = "2.0", kind = { spawn = function() return true end,
        busy = function() return true end,
        tick = function() local n = 0 while true do n = n + 1; SVP.hurt(PAWN(), 1); if n % 20 == 0 then RUN_FAKE() end end end } })]] },
    z_prov3 = { ["a.lua"] = [[SVP.register("prov3", { name = "Prov3", api = "2.0", kind = { spawn = function() return true end } })
        PROV_SHORT = function() local s = 0 for i = 1, 3000 do s = s + i end return 1 end]] },
    -- (a tick written as the docs say: only in its round)
    w_tfirst = { ["a.lua"] = [[SVP.register("tfirst", { name = "TFirst", api = "2.0", kind = { spawn = function() return true end,
        busy = function() return true end, tick = function(now, s) TICKS = (TICKS or 0) + 1; return s.n end } })]] },
    w_callloop = { ["a.lua"] = [[SVP.register("callloop", { name = "CallLoop", api = "2.0", kind = { spawn = function() return true end,
        busy = function() return true end, tick = function() SVP.callout("x") end } })]] },
    z_prov4 = { ["a.lua"] = [[SVP.register("prov4", { name = "Prov4", api = "2.0", kind = { spawn = function() return true end } })
        PROV_ALLOC = function() local L = {} while true do L[#L + 1] = { 1, 2, 3, 4 } end end]] },
    w_memcall = { ["a.lua"] = [[SVP.register("memcall", { name = "MemCall", api = "2.0", kind = { spawn = function() return true end,
        busy = function() return true end, tick = function() SVP.hurt(PAWN(), 1) end } })]] },
    w_memloop = { ["a.lua"] = [[SVP.register("memloop", { name = "MemLoop", api = "2.0", kind = { spawn = function() return true end,
        busy = function() return true end, tick = function() local L = {} while true do L[#L + 1] = { 1, 2, 3, 4 } end end } })]] },
    w_soft = { ["a.lua"] = [[SVP.register("softk", { name = "Soft", api = "2.0", kind = { spawn = function() return true end,
        busy = function() return true end, abort = function(why) SOFT_WHY = why end, over = function() SOFT_OVER = true end } })]] },
    z_prov2 = { ["a.lua"] = [[SVP.register("prov2", { name = "Prov2", api = "2.0", kind = { spawn = function() return true end } })
        PROV_LOOP = function() while true do RUN_FAKE() end end]] },
    a_hurter = { ["a.lua"] = [[SVP.register("hurter", { name = "Hurter", api = "2.0", kind = { spawn = function() return true end,
        tick = function() HURT_RC = { SVP.hurt(PAWN(), 5) } end, busy = function() return true end } })]] },
    -- def through a metatable: check a function the first read, a callable table the second
    r_meta = { ["a.lua"] = [[local n = 0
        local def = setmetatable({ name = "Meta", api = "2.0", kind = { spawn = function() return true end, busy = function() return true end } },
            { __index = function(_, k) if k == "check" then n = n + 1
                if n == 1 then return function() return true end end
                return setmetatable({}, { __call = function() CALLED_BARE = true; return true end }) end end })
        META_OK = { SVP.register("rmeta", def) }
        META_READS = function() return n end]] },
    -- a table of the add-on's own as a handle: methods that count their calls
    u_tbl = { ["a.lua"] = [[TBL_CALLS = 0
        local mt = { __index = function(t, k) TBL_CALLS = TBL_CALLS + 1
            if k == "GetAddress" then return function() return 0x7777 end end
            if k == "GetFullName" then return function() return "LiveAIPlane /Game/X.X:PersistentLevel.BP_Fake_C_1" end end
            if k == "IsValid" or k == "IsA" then return function() return true end end
            if k == "HealthInternal" then return 100 end end }
        FAKE_T = setmetatable({}, mt)
        SVP.register("utbl", { name = "Tbl", api = "2.0", kind = { spawn = function() return true end, busy = function() return true end } })]] },
    -- SVP.target from SVP.every (no round of its own)
    e_tgt = { ["a.lua"] = [[SVP.register("etgt", { name = "ETgt", api = "2.0", kind = { spawn = function() return true end, busy = function() return true end } })
        SVP.every(function() if TGT_NOW then TGT_NOW = false; EVERY_TGT = SVP.target(NEST_ACTOR(), { pay = 50 }) or false end end)]] },
    -- two kinds, each with an abort
    k_two = { ["a.lua"] = [[ABORTS = {}
        for _, k in ipairs({ "two1", "two2" }) do
            SVP.register(k, { name = "Two", api = "2.0", kind = { spawn = function() return true end, busy = function() return true end,
                abort = function() ABORTS[#ABORTS + 1] = k end } })
        end]] },
    v_bigapi = { ["a.lua"] = [[BIG = { pcall(SVP.register, "bigk", { name = "Big", api = "99999999999999999999.5", kind = { spawn = function() return true end } }) }]] },
    q_load = { ["a.lua"] = [[LOAD_FN = { load(function() return nil end) }
        LOAD_STR = load("return 7")()]] },
    w_move = { ["a.lua"] = [[local LOOPY = setmetatable({}, { __index = function() LOOPED = true; while true do RUN_FAKE() end end })
        SVP.register("wmov", { name = "MoveLoop", api = "2.0", kind = { spawn = function() return true end,
        tick = function() local h = NEST_ACTOR(); for i = 1, 50 do SVP.move(h, LOOPY) end; MOVE_ESCAPED = true end,
        busy = function() return true end } })]] },
}
local tmp = os.tmpname()
local folders = { target_practice = { { name = "target_practice.lua", path = EX .. "/target_practice.lua" } } }
local nativesOf = {}
for folder, fs in pairs(TEST_ADDONS) do
    local list = {}
    for n, src in pairs(fs) do
        local p = tmp .. "_" .. folder .. "_" .. n
        local f = assert(realOpen(p, "wb")); f:write(src); f:close()
        list[#list + 1] = { name = n, path = p }
        if n == "natives.txt" then nativesOf[folder] = p end
    end
    folders[folder] = list
end
local IGD_CALLS = 0
function IterateGameDirectories()
    IGD_CALLS = IGD_CALLS + 1
    local addons = {}
    for folder, fs in pairs(folders) do
        local fl = {}
        for _, f in ipairs(fs) do fl[#fl + 1] = { __name = f.name, __absolute_path = f.path } end
        addons[folder] = { __files = fl }
    end
    return { Game = { Binaries = { Win64 = { ue4ss = { Mods = { AC8SurvivalMode = {}, AC8SurvivalAddons = addons } } } } } }
end
local nFolders = 0
for _ in pairs(folders) do nFolders = nFolders + 1 end
-- (the test's own functions some of these add-ons call: a C function and a clock push for w_window, the pawn)
EXTRA2 = {
    SETHOOK = debug.sethook,                                 -- (a C function: its tail call returns straight to the API)
    PASTDUE = function() fakeClock = fakeClock + 20; return (debug.gethook()) end,
    PAWN = function() return survivalPC.Pawn end,
}
local realFormat, realSeed = string.format, math.randomseed

part("the loader: add-on folders, at Survival's first tick, every add-on found listed", function()
    watchdog(true)
    local ok, err = pcall(loadAPI)
    check(ok and #PLUGINS.loaded == 0 and SPC.kinds.practice == nil, "nothing of an add-on's runs at module load (" .. tostring(err) .. ")")
    PLUGINS.fakeHandles = FAKE
    PLUGINS.extra = { SLOW_FAKE = SLOW_FAKE, BUSY_FAKE = BUSY_FAKE, RUN_FAKE = RUN_FAKE,   -- (the test's fakes)
        NEST_ACTOR = function() return actor("BP_Nest_C") end,
        HANDLE = function(t) FAKE[t] = true; return t end,   -- (a stand-in for a UE4SS object the add-on got)
        OFF_NOW = function() PLUGINS.switchOff(PLUGINS.current, "the test's switch-off during its load") end }
    for k, v in pairs(EXTRA2 or {}) do PLUGINS.extra[k] = v end
    local ok2, err2 = pcall(PLUGINS.tick)
    watchdog(false)
    check(ok2 and SPC.kinds.practice ~= nil, "the add-ons load at the first PLUGINS.tick (" .. tostring(err2) .. ")")
    check(#PLUGINS.loaded == nFolders, string.format("every add-on found is in PLUGINS.loaded, loaded or not (LB.edited: unranked): %d of %d",
        #PLUGINS.loaded, nFolders))
    check(ENV("w_runaway").RUNAWAY_LOADED == true and WD.fired == 0 and said("a runaway loop"),
        "a runaway loop at load is stopped by the API (the test's watchdog never fired) and the add-on switched off")
    check(ENV("e_err").ERR_EVERY == nil and ENV("n_newer").NEWER_EVERY == nil,
        "an add-on that errors at load, or is refused, runs none of its SVP.every jobs")
    local m = ENV("m_multi")
    check(m.MULTI_B == 42 and m.DIR == folders.m_multi[1].path:match("^(.*[/\\])"),
        "an add-on's files run in name order in its one environment; SVP.dir() is its folder")
end)
for _, fs in pairs(folders) do for _, f in ipairs(fs) do if f.path:find(tmp, 1, true) then os.remove(f.path) end end end

part("each add-on's own environment", function()
    local g = ENV("q_globals")
    check(log == LOG and type(PLUGINS) == "table" and CFG == CFG0 and type(LB) == "table" and D == nil and SECRET == nil,
        "an add-on's global writes (log, PLUGINS, CFG, LB, D) stay in its environment: Survival's are untouched")
    check(table.concat(g.GOT, ",") == "nil,nil,nil,nil,nil,nil,nil" and g.D == 7,
        "it reads none of Survival's globals (PLUGINS, CFG, LB, addCredits, levelGoing, SPC, _G.CFG)")
    check(string.format == realFormat and math.randomseed == realSeed and type(SVP.pay) == "function",
        "string.format = nil, math.randomseed = nil and SVP.pay = nil change its own copies only")
    local l = ENV("q_lib").LIB
    check(l.fmt == "function" and l.secret == "nil", "another add-on still has string.format, and can't see the first's globals")
    check(l.dbg == "nil" and l.dbgcall == false, "no debug library (debug.getupvalue unreachable)")
    check(l.smeta == nil and type(l.tmeta) == "table", "getmetatable(\"\") is nil (the string metatable leads to the real library); a table's is given")
    check(l.count == "number" and l.collect == false, "collectgarbage: \"count\" only")
    check(l.seed == "nil" and l.dump == "nil" and l.co == "nil" and l.req == "nil", "no math.randomseed, string.dump, coroutine or require")
    check(l.unsafe == "nil,nil,nil,nil,nil,nil,nil,nil,nil",
        "no LoopAsync, ExecuteInGameThread, ExecuteWithDelay, RegisterKeyBind, RegisterHook, os.execute, io.popen, os.remove, IterateGameDirectories")
    check(l.write == nil and l.bytecode == nil and l.loadenv == true, "io.open for reading only; load: text only, in its own environment")
    check(ENV("q_lib").StaticConstructObject == nil, "StaticConstructObject isn't in an add-on's environment (SVP.widget is)")
    check(l.natives == "function,nil,nil,nil,nil",
        "natives: a C function its natives.txt names (EXT_*) is there; undeclared ones, and Survival's SV_*, aren't")
    check(ENV("c_coop").CFG_WRITE == false and ENV("c_coop").CFG_READ == 3, "SVP.cfg(): its kind's settings, read-only (a write raises)")
    -- (tools/checks/lua_check.py --addons checks the example add-ons against its ADDON_GLOBALS: the same names)
    local okL, lc = pcall(readAll, MOD .. "/../../../tools/checks/lua_check.py")
    local listed, given = {}, {}
    for n in ((okL and lc:match("ADDON_GLOBALS = (%b{})")) or ""):gmatch("'([%w_]+)'") do listed[#listed + 1] = n end
    local mt = debug.getmetatable(ENV("q_lib"))
    for i = 1, 50 do
        local n, v = debug.getupvalue(mt.__index, i)
        if n == nil then break end
        if n == "A" then for k in pairs(v) do if not (PLUGINS.extra or {})[k] then given[#given + 1] = k end end end
    end
    given[#given + 1] = "_G"
    table.sort(listed); table.sort(given)
    check(#listed > 0 and table.concat(listed, " ") == table.concat(given, " "),
        "lua_check.py's ADDON_GLOBALS is an environment's names (" .. #listed .. " listed, " .. #given .. " given)")
    local qs = SPC.kinds.qstate
    D = { round = 1, now = 0 }
    D.special = { kind = "qstate", state = "pending" }
    qs.spawn(1); qs.tick(2, D.special)
    check(D.special.state == "pending" and qs.ready(9, false) == false and said("read-only for an add-on"),
        "the round's record Survival hands its tick (D.special): read-only, a write switches the add-on off")
    D = nil
end)

part("no finalizer, and no call outside the guard", function()
    local g = ENV("q_gc")
    check(g.GC_SET == false and g.GC_PLAIN == true, "setmetatable with a __gc: refused (an error); without one: as Lua's")
    local k = SPC.kinds.gck
    D = { round = 1, now = 0 }
    k.spawn(1); k.tick(2, {})
    check(k.ready(9, false) == false, "(its add-on switched off)")
    local p0 = #paid
    collectgarbage("collect"); collectgarbage("collect")
    local byGc = 0
    for _, x in ipairs(paid) do if x.why == "a finalizer" then byGc = byGc + 1 end end
    check(byGc == 0, "garbage collections (its switch-off, then forced): no finalizer of its ever paid anything")
    local p1 = PLUGINS.current or PLUGINS.running
    check(p1 == nil and SVP.pay(5, "outside") == false and #paid == p0, "an SVP call with no add-on attached (as a finalizer's): refused")
    D = nil
end)

part("the walks and NotifyOnNewObject", function()
    local p, w = addon("q_walks")
    check(w.NOTE == true and type(notified["/Script/Live.LiveMissile"]) == "function", "NotifyOnNewObject: asked through the framework")
    local cb = notified["/Script/Live.LiveMissile"]
    D = { round = 1, now = 0 }
    cb({}); cb({})
    check((w.NOTED or 0) == 0 and (ENV("q_notify2").NOTED2 or 0) == 0,
        "UE4SS's callback (on the thread that constructs the object) runs no add-on code: the object is kept, nothing else")
    PLUGINS.tick()
    check(w.NOTED == 2 and ENV("q_notify2").NOTED2 == 2, "the next PLUGINS.tick hands each object to every add-on's callback")
    local gone = { live = true }
    cb(gone); gone.live = false
    PLUGINS.tick()
    check(w.NOTED == 2, "an object freed before that tick isn't handed over")
    held = "a level is loading"
    cb({})
    w.TRY_FIND = true
    local f0 = finds
    PLUGINS.tick()
    held = nil
    check(w.NOTED == 2 and w.HELD_RAN == true and w.HELD_FIND == nil and finds == f0,
        "while Survival's walkHold() holds: no object kept, no callback, FindAllOf refused (nil, the game not asked)")
    cb({ boom = true })
    check(p.off ~= true, "(an object whose callback raises: kept, not run yet)")
    PLUGINS.tick()
    check(p.off == true and said("noted boom"), "a callback's error: in the guard, at the tick, the add-on switched off")
    cb({}); PLUGINS.tick()
    check(w.NOTED == 3 and ENV("q_notify2").NOTED2 == 4, "a switched-off add-on's callbacks are dropped; the others' still come")
    local n2 = ENV("q_notify2").NOTED2
    for i = 1, 300 do cb({}) end
    PLUGINS.tick()
    check(ENV("q_notify2").NOTED2 == n2 + 256 and said("300 objects since the last tick, 256 at most: 44 dropped"),
        "256 objects of a class a tick at most: the rest dropped, said")
    going = true
    PLUGINS.tick()
    check(addon("q_walks").off and finds == f0, "FindAllOf in a teardown handler (SVP.going) is refused: the game not asked")
    going = false
    D = nil
    PLUGINS.tick()
    cb({}); PLUGINS.tick()
    check(ENV("q_notify2").NOTED2 == n2 + 256, "every add-on's NotifyOnNewObject callbacks are dropped at the level's teardown")
end)

part("pins", function()
    local p, e = addon("q_pins")
    D = { round = 1, now = 0 }; e.PIN_ALL = true; PLUGINS.tick()
    check(e.PINNED == 64 and said("64 pins at most"), "SVP.pin: 64 at most an add-on, the rest refused with a line")
    local function ours() local n = 0; for _, x in pairs(REFS) do if x ~= GS then n = n + 1 end end return n end
    check(ours() == 64, "pinned: held in the GameInstance's ReferencedObjects")
    D = nil; PLUGINS.tick()
    check(ours() == 0 and said("64 pins let go (the run ended)") and #(p.pins or {}) == 0, "a pin never let go by the add-on: let go at the run's end")
    local n0 = #REFS
    e.PIN_MORE = true; PLUGINS.tick()
    check(e.PINNED2 == true and ours() == 1 and #REFS == n0, "a let-go slot is used again (the array doesn't grow)")
    going = true; PLUGINS.tick(); going = false; D = nil; PLUGINS.tick()
    check(ours() == 0, "let go when the level goes")
    e.PIN_MORE, e.PIN_BOOM = true, true; PLUGINS.tick()
    check(p.off == true and ours() == 0, "let go when the add-on is switched off")
end)

part("an add-on that failed or was refused: listed, and none of its jobs run", function()
    local lb = setmetatable({ LB = {} }, { __index = _G })
    assert(load(readAll(MOD .. "/Scripts/sv_leaderboard.lua"), "@sv_leaderboard.lua", "t", lb))()
    local out = table.concat(lb.LB.edited(false), "|")
    check(out:find("plugin e_err", 1, true) and out:find("plugin Newer", 1, true) and out:find("plugin bad name!", 1, true),
        "sv_leaderboard.lua's own LB.edited, run: failed and refused add-ons listed (the run unranked): " .. out:sub(1, 60))
    D = { round = 1, now = 0 }; PLUGINS.tick(); D.round = 2; PLUGINS.tick()
    going = true; PLUGINS.tick(); going = false; D = nil; PLUGINS.tick()
    local e, n = ENV("e_err"), ENV("n_newer")
    check(e.ERR_ON == nil and e.ERR_GOING == nil and n.NEWER_ON == nil and n.NEWER_GOING == nil,
        "their SVP.on and SVP.going jobs: never run")
    check(addon("bad name!").off and said("its folder's name isn't letters") and ENV("bad name!") == nil,
        "a folder name of other characters: switched off, nothing of it run")
    check(addon("n_nolua").off and said("no .lua in its folder"), "a folder with no .lua: switched off, said")
    check(addon("Scripts").off and (ENV("Scripts") or {}).SCRIPTS_RAN == nil and said("Scripts and dlls aren't add-on names"),
        "a folder named Scripts (a UE4SS mod's own): refused, its main.lua not run")
end)

part("SVP.provide: hurtPlayer", function()
    local pawn = actor("BP_Me_C")
    survivalPC.Pawn = pawn
    local okP = ENV("p_prov").PROV[1]
    check(ENV("e_err").ERR_PROVIDE == true and okP == true, "a failed add-on's provider is dropped: the next one's taken")
    local ok, before, after, how = asAddon("coopk", SVP.hurt, pawn, 5, nil)
    local h = ENV("p_prov").HURT
    check(ok == true and how == "the game's own health path" and h and h[1] == pawn.addr and h[2] == -5 and h[3] == pawn.addr
        and ENV("e_err").ERR_HURT == nil, "SVP.hurt on your plane: the provider's (your address, -5, causer = you), not the failed one's")
    survivalPC.Pawn = nil
end)

part("versions and requirements", function()
    check(SVP.api.major == 2 and SVP.api.minor >= 0, "SVP.api is 2.x")
    local l2 = select(2, API_SRC:match("^([^\n]*)\n([^\r\n]*)"))
    check(l2 == string.format("-- add-on API %d.%d", SVP.api.major, SVP.api.minor),
        "line 2 of sv_plugins.lua (what a native mod reads) is the API's version: " .. tostring(l2))
    check(ENV("n_newer").NEWER[1] == false and SPC.kinds.newerk == nil and said("Newer: not loaded: it needs add-on API 3.0"),
        "an add-on needing a newer API: refused, one line")
    check(ENV("l_old").OLDMAJOR[1] == false and SPC.kinds.oldk == nil, "an add-on declaring an older major (\"1.0\"): refused (a major may change calls)")
    check(ENV("r_req").REQ[1] == false and said("requires SV_NoSuchThing"), "an add-on missing a native function it requires: refused")
    check(ENV("v_one").ONE[1] == false and SPC.kinds.onek == nil and said("it declares no def.api"),
        "an add-on declaring no def.api: refused, one line (2.0 is the first API that shipped)")
end)

part("the rotation", function()
    local inRot = {}
    for _, x in ipairs(CFG.specials.rotation) do inRot[x] = true end
    check(inRot.rot1 and inRot.rot2, "two add-ons with def.rotation both join it (the first one's addition isn't the player's own list)")
    check(not inRot.practice, "the example add-on not in it by itself (def.rotation false)")
end)

part("an add-on failing its load takes its kinds off again, the rotation's too", function()
    local inRot = {}
    for _, x in ipairs(CFG.specials.rotation) do inRot[x] = true end
    check(SPC.kinds.twok == nil and CFG.specials.twok == nil and not inRot.twok and addon("m_fail").off == true,
        "a second file that doesn't compile: the first's kind off again (SPC.kinds, CFG.specials, the rotation)")
    check(SPC.kinds.offk == nil and not inRot.offk and ENV("m_offload").OFF_B_RAN == nil and addon("m_offload").off == true,
        "switched off during its own load: its next file not run, its kind off")
end)

part("SVP.every / on / going: capped, and a pass runs the jobs there as it began", function()
    local j = ENV("j_jobs")
    j.JOBS_GROW = true
    PLUGINS.tick()
    check((j.GREW or 0) == 0, "a job added during a pass doesn't run in that pass")
    for i = 1, 100 do PLUGINS.tick() end
    j.JOBS_GROW = false
    local n, me = 0, addon("j_jobs")
    for _, e in ipairs(PLUGINS.every) do if e.p == me then n = n + 1 end end
    check(n == 64 and said("SVP.every: 64 jobs at most"), "64 jobs an add-on at most: a job adding a job each tick doesn't grow the list (" .. n .. ")")
end)

part("the level's teardown tick: SVP.going first, then a round's abort, roundEnd, runEnd", function()
    local ko, o = SPC.kinds.ordk, ENV("k_order")
    D = { round = 3, now = 0 }; PLUGINS.tick()
    ko.spawn(1)
    o.ORD = {}
    going, D = true, nil
    local p0 = #paid
    PLUGINS.tick()
    going = false; PLUGINS.tick()
    check(table.concat(o.ORD, " ") == "levelGoing abort:the level is going roundEnd runEnd",
        "in that order: " .. table.concat(o.ORD, " "))
    check(o.PAY_IN_END == false and #paid == p0, "an SVP call that changes the game, in its roundEnd then: refused")
end)

part("the kinds' fields", function()
    local K = ENV("k_kinds").KINDS
    check(K.badair[1] == false and SPC.kinds.kbad == nil, "a kind whose aircraft isn't a count: refused at register")
    check(K.named[1] == false and CFG.specials.anomaly == ANOMALY,
        "a kind named like one of Survival's specials settings (anomaly): refused, the setting kept")
    local kv = SPC.kinds.kvals
    check(kv ~= nil and kv.budget(7) == 7, "budget answering nil: Survival's own budget")
    check(kv ~= nil and kv.aircraft() == 0, "aircraft answering a string: 0")
    check(kv ~= nil and kv.row({}, {}) == nil, "row answering a number: none")
    D = { round = 1, now = 0 }
    local okR, r = pcall(kv.ready)                    -- (sv_spawn.lua bagFill asks with no round)
    check(okR and r == false and kv.ready(1, false) == false and kv.ready(3, false) == true,
        "ready() with no round (the bag fill): its ready asked with the round in play, no error (a no keeps it out of the bag)")
    D = nil
end)

part("the example add-on: target practice", function()
    local k = SPC.kinds.practice
    check(k ~= nil and CFG.specials.practice.trucks == 3, "registered, its settings in CFG.specials.practice")
    D = { round = 1, now = 0 }
    check(k.ready(1, false) == true and CFG.specials.practice.from_round == 2,
        "its from_round in its settings (Survival keeps it out before that round: sv_spawn.lua specialReady), its ready yes")
    local n0 = #actors
    check(k.spawn(10) == true and #actors == n0 + 3 and callouts[#callouts]:find("TARGET PRACTICE", 1, true) ~= nil,
        "spawn: 3 trucks on the pad, the callout")
    local t = { actors[n0 + 1], actors[n0 + 2], actors[n0 + 3] }
    check(k.busy({}) == true, "busy while trucks are up")
    local p0 = #paid
    t[1].HealthInternal = 0
    k.tick(11, {})
    check(#paid == p0 + 1 and paid[#paid].n == 500, "a destroyed truck is paid (500)")
    t[2].HealthInternal, t[3].HealthInternal = 0, 0
    k.tick(12, {})
    check(#paid == p0 + 3 and k.busy({}) == false, "all three down: paid, the round no longer held")
    k.over(13, nil)
    check(t[1].HealthInternal <= 0 and t[2].HealthInternal <= 0 and t[3].HealthInternal <= 0 and destroyedUnits == 0,
        "over: its trucks taken off")
    check(k.spawn(20) == true, "a second round spawns")
    k.tick(20 + 121, {})
    check(k.busy({}) == false and callouts[#callouts]:find("TIME UP", 1, true) ~= nil, "the time limit ends it (TIME UP)")
    k.over(142, nil)
    check(#paid == p0 + 3 and actors[n0 + 4].HealthInternal <= 0 and actors[n0 + 6].HealthInternal <= 0 and destroyedUnits == 0,
        "the trucks left at the time limit taken off (their own death), unpaid")
    D = nil
end)

part("events", function()
    local y = ENV("y_slow")
    y.EV = {}
    D = { round = 1, now = 0 }; PLUGINS.tick()
    D.round = 2; PLUGINS.tick()
    D = nil; PLUGINS.tick()
    check(table.concat(y.EV, " ") == "runStart roundStart:1 roundEnd:1 roundStart:2 roundEnd:2 runEnd:2", "run / round events in order")
end)

part("a freed object's address taken by another", function()
    -- (the GC frees a cached asset and the allocator puts a new object at its address: the old pointer is "live" again,
    -- but another object. The cache must look again, never hand it back)
    local made = 0
    local realLoad = loadObject
    loadObject = function(p)
        made = made + 1
        return setmetatable({ path = p, live = true, n = made },
            { __index = { GetFullName = function(self) return self.fullname or ("Object " .. p) end } })
    end
    local a1 = SVP.load("/Game/X/MI_A.MI_A")
    local a2 = SVP.load("/Game/X/MI_A.MI_A")
    a1.fullname = "SoundWave /Game/Y/SW_B.SW_B"            -- (its memory is another object now, still a live one)
    local a3 = SVP.load("/Game/X/MI_A.MI_A")
    loadObject = realLoad
    check(a1 == a2 and a3 ~= a1 and made == 2, "SVP.load: kept while it's the same object, looked up again once it isn't")
end)

part("the guard", function()
    local kb = SPC.kinds.badk
    kb.spawn(1); kb.tick(2, {})
    check(kb.busy({}) == false and kb.ready(9, false) == false and said("Bad: tick error"), "an error switches the add-on off: its round ends")
    local ks = SPC.kinds.slowk
    local d0 = D
    D = D or { round = 1, now = 0 }                    -- (a round is a run's)
    ks.spawn(1)
    check(bgm[#bgm] == "AKE_System_BGM_Mute_On", "SVP.bgm(false) mutes Survival's music")
    ks.tick(2, {})
    check(ks.ready(9, false) == true and said("a hitch") and bgm[#bgm] == "AKE_System_BGM_Mute_On",
        "one call over 2 s is a hitch: logged, the add-on stays on")
    ks.tick(3, {}); ks.tick(4, {})
    check(ks.ready(9, false) == false and said("a stall") and bgm[#bgm] == "AKE_System_BGM_Mute_Off",
        "three calls over 2 s within 60 s switch the add-on off and give Survival's music back")
    D = d0
    local kd = SPC.kinds.bud
    kd.spawn(1)
    for i = 1, 20 do kd.tick(i, {}) end
    check(kd.ready(9, false) == false and said("its budget"), "0.5 s on every tick (each under 2 s): over its time budget, switched off")
    local kp = SPC.kinds.spin
    kp.spawn(1)
    watchdog(true)
    local okS = pcall(kp.tick, 2, {})
    watchdog(false)
    check(okS and WD.fired == 0 and kp.ready(9, false) == false, "a runaway loop in a tick: stopped by the API, switched off")
    local kt = SPC.kinds.tostr
    kt.spawn(1)
    local okT = pcall(kt.tick, 2, {})
    check(okT and kt.ready(9, false) == false, "an error value whose tostring raises: the add-on switched off, nothing escapes")
    -- the add-on's own pcall / xpcall can't catch its way out of the runaway limit
    local ke, kx = SPC.kinds.escp, SPC.kinds.escx
    ke.spawn(1); kx.spawn(1)
    local wd0 = WD.fired
    watchdog(true, "the guard: a runaway caught by its own pcall")
    local okE = pcall(ke.tick, 2, {})
    local okX = pcall(kx.tick, 2, {})
    watchdog(false)
    check(okE and ENV("w_escape").ESCAPED == nil and ke.ready(9, false) == false and WD.fired == wd0,
        "a runaway caught by the add-on's own pcall (and retried): passed straight through it, the add-on switched off")
    check(okX and ENV("w_escx").XESCAPED == nil and ENV("w_escx").HANDLED == nil and kx.ready(9, false) == false,
        "a runaway under the add-on's own xpcall: its handler not called for it (a handler runs where no hook stops it), switched off")
    -- a guarded call inside another keeps the outer one's hook and deadline, and its time is the outer's
    local kn = SPC.kinds.nest
    kn.spawn(1)
    watchdog(true, "the guard: a loop calling a guarded callback")
    local okN = pcall(kn.tick, 2, {})
    watchdog(false)
    check(okN and ENV("w_nested").NESTED_DONE == nil and kn.ready(9, false) == false and WD.fired == wd0,
        "a loop that runs a guarded callback (an onDown) each pass: still stopped (the inner call doesn't restart the count)")
    local kw = SPC.kinds.nslow
    kw.spawn(1)
    kw.tick(2, {}); kw.tick(3, {})
    check(kw.ready(9, false) == true, "a slow onDown inside its own slow tick: one stall a tick, not two (2 of 3 within 60 s: still on)")
end)

part("SVP.hud: given back 60 s after it was hidden, however often it's hidden again", function()
    local h0 = #holds
    D = { round = 1, now = 0 }; PLUGINS.tick()
    asAddon("coopk", SVP.hud, false, "cutscene")
    fakeClock = fakeClock + 30
    asAddon("coopk", SVP.hud, false, "cutscene, again")
    fakeClock = fakeClock + 31
    PLUGINS.tick()
    check(holds[h0 + 1] == "on add-on c_coop" and holds[#holds] == "off add-on c_coop" and said("60 s, the API's limit"),
        "hidden twice 30 s apart: given back 61 s after the first (the hold named by its folder)")
    D = nil; PLUGINS.tick()
end)

part("pay", function()
    local p0, b0 = #paid, #badPay
    asAddon("coopk", SVP.pay, 2.5, "test")
    check(#paid == p0 + 1 and paid[#paid].n == 3 and #badPay == b0, "SVP.pay(2.5): 3, a whole number")
    asAddon("coopk", SVP.pay, 1 / 0, "test")
    asAddon("coopk", SVP.pay, 0 / 0, "test")
    asAddon("coopk", SVP.pay, -50, "test")
    check(#paid == p0 + 1 and #badPay == b0, "SVP.pay(1/0), SVP.pay(0/0), SVP.pay(-50): nothing paid")
    asAddon("coopk", SVP.pay, 1e12, "test")
    check(#paid == p0 + 2 and paid[#paid].n == 1000000, "SVP.pay(1e12): 1,000,000 at most")
    local kc = SPC.kinds.coopk
    D = { round = 1, now = 0 }
    kc.spawn(1)
    local t1, t2 = actor("BP_PayA_C"), actor("BP_PayB_C")
    asAddon("coopk", SVP.target, t1, { pay = 2.5, flat = true })
    asAddon("coopk", SVP.target, t2, { pay = 0 / 0 })
    t1.HealthInternal, t2.HealthInternal = 0, 0
    kc.tick(2, {}); kc.tick(3, {})
    check(#paid == p0 + 3 and paid[#paid].n == 3 and #badPay == b0, "a target's pay 2.5 (flat): 3; NaN: unpaid; Survival gets whole numbers only")
    kc.over(4, nil)
    D = nil
end)

part("give-backs", function()
    local g = SPC.kinds.giv1
    local h0 = #holds
    D = { round = 1, now = 0 }                         -- (a round is a run's)
    local gs = g.spawn(1)
    D = nil
    check(gs == false and bgm[#bgm] == "AKE_System_BGM_Mute_Off", "spawn says no: Survival's music given back")
    check(holds[h0 + 1] == "on add-on g_give" and holds[#holds] == "off add-on g_give",
        "SVP.hud is Survival's HUD.hold (no hudTick wrap), given back when spawn says no")
    local h = ENV("h_every")
    D = { round = 1, now = 0 }; h.MUTE_NOW = true; PLUGINS.tick()
    local muted = bgm[#bgm] == "AKE_System_BGM_Mute_On"
    D = nil; PLUGINS.tick()
    check(muted and bgm[#bgm] == "AKE_System_BGM_Mute_Off", "muted by an SVP.every job with no round: given back at the run's end")
    local s = SPC.kinds.spn
    D = { round = 1, now = 0 }
    s.spawn(1)
    local a = ENV("s_spawner").SPN_A
    s.tick(2, {})
    check(a ~= nil and a.HealthInternal == 100 and s.ready(9, false) == false,
        "an add-on switched off inside Survival's call (its tick): nothing of its taken off there")
    PLUGINS.tick()
    check(a.HealthInternal <= 0 and a.live and destroyedUnits == 0,
        "at the next PLUGINS.tick: what it spawned is taken off (a game unit by its own death, never destroyed)")
    D = nil
end)

part("co-op (API 2.0 is single player)", function()
    local kc, c = SPC.kinds.coopk, ENV("c_coop")
    COOP = { open = true }
    c.COOP_SPAWNED = false
    check(kc.ready(9, false) == false and kc.spawn(1) == false and c.COOP_SPAWNED == false,
        "co-op open (a host waiting, or a joiner): an add-on round is refused by ready and by spawn")
    local e0, o0 = c.COOP_EVERY or 0, c.COOP_ON or 0
    D = { round = 1, now = 0 }; PLUGINS.tick(); D.round = 2; PLUGINS.tick()
    check((c.COOP_EVERY or 0) == e0 and (c.COOP_ON or 0) == o0, "co-op open: no add-on's SVP.every or SVP.on job runs")
    local p0, a0 = #paid, #actors
    asAddon("coopk", SVP.pay, 100, "test")
    local sp = asAddon("coopk", SVP.spawn, "/Game/X/BP_Thing.BP_Thing_C", { X = 0, Y = 0, Z = 0 }, 0)
    local t = actor("BP_Coop_C")
    local hurtOk = asAddon("coopk", SVP.hurt, t, 5, nil)
    SV_Event = function() return 1 end
    local killed = asAddon("coopk", SVP.killPlayer, "test")
    SV_Event = nil
    check(#paid == p0 and sp == nil and #actors == a0 + 1 and not hurtOk and t.HealthInternal == 100 and not killed,
        "co-op open: SVP.pay, spawn, hurt and killPlayer refuse")
    local b0, h0, c0 = #bgm, #holds, #callouts
    local bg, hd, co = asAddon("coopk", SVP.bgm, false), asAddon("coopk", SVP.hud, false, "t"), asAddon("coopk", SVP.callout, "X")
    check(not bg and not hd and not co and #bgm == b0 and #holds == h0 and #callouts == c0, "co-op open: SVP.bgm, hud and callout refuse")
    COOP = { open = false }
    local got = 0
    c.NotifyOnNewObject("/Script/Live.LiveCoopThing", function() got = got + 1 end)
    COOP = { open = true }
    notified["/Script/Live.LiveCoopThing"]({}); PLUGINS.tick()
    check(got == 0, "co-op open: no NotifyOnNewObject object kept or handed over")
    local g0 = c.COOP_GOING or 0
    going = true; PLUGINS.tick(); going = false; PLUGINS.tick()
    check((c.COOP_GOING or 0) == g0, "co-op open: no SVP.going job runs at the level's teardown")
    COOP = { open = false }
    check(kc.ready(9, false) == true, "co-op closed: it comes again")
    COOP, D = nil, nil
    PLUGINS.tick()
end)

part("hard rules 59, 63, 64", function()
    local kc = SPC.kinds.coopk
    D = { round = 1, now = 0 }
    kc.spawn(1)
    -- rule 59: a target whose address is another object's now is gone, and nothing is done to it
    local t1 = actor("BP_Test_C")
    local id1 = asAddon("coopk", SVP.target, t1, { pay = 100, label = "rule59" })
    reuse(t1)
    fakeClock = fakeClock + 2
    local hurtOk = asAddon("coopk", SVP.hurt, t1, 5, nil)
    check(hurtOk == false and t1.HealthInternal == 100, "rule 59: SVP.hurt refuses a target whose address is another object's now")
    kc.tick(1, {}); kc.tick(2, {})
    check(PLUGINS.targets[id1] == nil and said("its address is another object's now"), "rule 59: the targets' watch takes it as gone")
    -- rule 59 for what the add-on spawned, not only its targets
    local a = asAddon("coopk", SVP.spawn, "/Game/X/BP_Thing.BP_Thing_C", { X = 0, Y = 0, Z = 0 }, 0)
    reuse(a)
    fakeClock = fakeClock + 2
    local mv = asAddon("coopk", SVP.move, a, { X = 5, Y = 5, Z = 5 }, nil)
    local ds = asAddon("coopk", SVP.despawn, a)
    local hu = asAddon("coopk", SVP.hurt, a, 1, nil)
    check(mv == false and ds == false and hu == false and a.live and a.at == nil,
        "rule 59: SVP.move / despawn / hurt refuse an actor it spawned whose address is another object's now")
    -- the name read before every call that changes the game, per handle
    local b1 = asAddon("coopk", SVP.spawn, "/Game/X/BP_Thing.BP_Thing_C", { X = 0, Y = 0, Z = 0 }, 0)
    reuse(b1)                                          -- (at once: within a second of its record)
    check(asAddon("coopk", SVP.hurt, b1, 5, nil) == false and b1.HealthInternal == 100,
        "rule 59: SVP.hurt within a second of the record: the name read now, refused")
    local b2 = actor("BP_Found_C")                     -- (one the API never saw: FindAllOf's, say)
    check(asAddon("coopk", SVP.move, b2, { X = 1, Y = 1, Z = 1 }, nil) == true, "an actor the API never saw: served")
    reuse(b2)
    check(asAddon("coopk", SVP.hurt, b2, 5, nil) == false and b2.HealthInternal == 100,
        "rule 59: recorded at its first call, so a later call with it sees its address is another object's")
    local b3 = asAddon("coopk", SVP.spawn, "/Game/X/BP_Thing.BP_Thing_C", { X = 0, Y = 0, Z = 0 }, 0)
    reuse(b3)
    check(asAddon("coopk", SVP.target, b3, { pay = 10 }) == nil, "rule 59: SVP.target on a handle whose object is another now: refused")
    local b4 = actor("BP_New_C")                       -- (the object now at b1's address, a handle of its own)
    b4.addr, b4.full = b1.addr, b1.full
    fakeClock = fakeClock + 2
    check(asAddon("coopk", SVP.hurt, b4, 5, nil) == true and b4.HealthInternal == 50,
        "the object now at a reused address, by a handle of its own: served (not refused for the old one's record)")
    -- rule 63: SVP.retire finishes with Survival's finishUnpaid (mortal, ModifyHealth, health read back)
    local t2 = actor("BP_Test2_C")
    local rOk = asAddon("coopk", SVP.retire, t2)
    check(rOk == true and t2.HealthInternal == 0 and skips(rec(t2)), "rule 63: SVP.retire finishes through finishUnpaid, its plane unpaid")
    -- rule 64: no sure kill while the landing STORE's gate is shut (its event would run none of its records)
    local fired, gateAt = 0, nil
    SV_Event = function() fired = fired + 1; return 1 end
    STOREQ = { gate = function(now) gateAt = now; return false, "your landing STORE is open" end }
    D.now = 123.5
    check(asAddon("coopk", SVP.killPlayer, "test") == false and fired == 0, "rule 64: SVP.killPlayer refused while the STORE's gate is shut")
    check(gateAt == 123.5, "the STORE's gate asked with Survival's own clock (D.now), not os.clock: " .. tostring(gateAt))
    STOREQ = { gate = function() return true end }
    check(asAddon("coopk", SVP.killPlayer, "test") == true and fired == 1, "rule 64: and fired once it's open")
    STOREQ, SV_Event = nil, nil
    kc.over(3, nil)
    D = nil
end)

part("Survival's plane sweep: the add-on's units", function()
    local kc = SPC.kinds.coopk
    D = { round = 1, now = 0 }
    kc.spawn(1)
    -- (a hit the game didn't let kill: no mark)
    local a = actor("BP_Inv_C"); a.invincible = true
    asAddon("coopk", SVP.hurt, a, 150, nil)
    check(not skips(rec(a)), "SVP.hurt: a unit marked only once its health reads 0 (health units, not HealthInternal's x 10)")
    -- (a retired unit's address taken by one of Survival's enemies: Survival's own)
    local b = actor("BP_Ret_C")
    asAddon("coopk", SVP.retire, b)
    local other = rec(b); other.name = "BP_Other_C_1"
    check(not skips(other), "a retired unit's mark is honoured only with its name: another enemy at that address is Survival's")
    local c = actor("BP_Ret2_C")
    asAddon("coopk", SVP.retire, c)
    check(skips(rec(c)) and not skips(rec(c)), "a mark is used once")
    local e = actor("BP_Ret3_C")
    asAddon("coopk", SVP.retire, e)
    D = { round = 1, now = 0 }; PLUGINS.tick()
    check(not skips(rec(e)), "the marks are a run's: a new run drops them")
    kc.spawn(1)
    -- targets: paid by the API once, never by Survival
    local p0 = #paid
    local t = actor("BP_Air_C")
    asAddon("coopk", SVP.target, t, { pay = 100, flat = true, class = "air" })
    t.HealthInternal = 0
    check(skips(rec(t)), "an air target seen down by Survival's sweep: not Survival's to pay or count")
    kc.tick(2, {}); kc.tick(3, {})
    check(#paid == p0 + 1 and paid[#paid].n == 100, "the API pays it once")
    local t2, t3, t4, t5 = actor("BP_T2_C"), actor("BP_T3_C"), actor("BP_T4_C"), actor("BP_T5_C")
    for _, x in ipairs({ t2, t3, t4, t5 }) do asAddon("coopk", SVP.target, x, { pay = 100, flat = true }) end
    asAddon("coopk", SVP.retire, t2)
    asAddon("coopk", SVP.despawn, t3)
    asAddon("coopk", SVP.hurt, t4, 20, nil)
    kc.tick(4, {}); kc.tick(5, {})
    check(#paid == p0 + 1, "a target retired, despawned, or killed by a hit of no one's: unpaid")
    kc.over(6, nil)
    local left = 0
    for _, x in pairs(PLUGINS.targets) do if x.p == PLUGINS.kinds.coopk then left = left + 1 end end
    check(left == 0, "its targets come off unpaid at its round's end")
    D = nil
end)

part("Survival's plane sweep and tail watch leave an add-on's live targets alone", function()
    local kc = SPC.kinds.coopk
    D = { round = 1, now = 0 }
    kc.spawn(1)
    local a = actor("BP_Own_C")
    local r = rec(a)
    check(not PLUGINS.owned(r), "a plane no add-on targets: Survival's (tiers, manoeuvres, stats)")
    asAddon("coopk", SVP.target, a, { pay = 0, label = "own" })
    check(PLUGINS.owned(r) and PLUGINS.owned(r), "an add-on's target, up: owned, and asking doesn't use the mark up (every sweep asks)")
    local other = rec(a); other.name = "BP_Other_C_9"
    check(not PLUGINS.owned(other), "another object at its address since: Survival's")
    D = { round = 1, now = 0 }
    check(not PLUGINS.owned(r), "a new run: Survival's")
    D = nil
    D = { round = 1, now = 0 }; kc.spawn(1)
    local b = actor("BP_Own2_C")
    local id2 = asAddon("coopk", SVP.target, b, { pay = 0 })
    asAddon("coopk", SVP.untarget, id2)
    check(not PLUGINS.owned(rec(b)), "untargeted by the add-on: Survival's again")
    kc.over(2, nil)
    D = nil
end)

part("what the framework keeps of an add-on's tables: plain copies, taken at the call", function()
    local u = ENV("u_tables")
    local c = CFG.specials.utab
    check(c ~= nil and c.n == 1 and #c.list == 3 and getmetatable(c.list) == nil and c.sub == nil and c.deep == nil
        and said("def.cfg.deep, def.cfg.sub left out"), "def.cfg kept as plain data: numbers, strings, booleans, flat lists (a map or a deeper table left out, said)")
    local k = SPC.kinds.utab
    D = { round = 1, now = 0 }
    k.spawn(1)
    local t = actor("BP_Tab_C")
    asAddon("utab", SVP.target, t, u.OPTS)
    t.HealthInternal = 0
    k.tick(2, {}); k.tick(3, {})
    check(u.OPTS_INDEX == nil and u.LABEL_TOSTR == nil and said("target " .. PLUGINS.nextId .. " (?) down"),
        "a target's opts copied raw at SVP.target: no __index or __tostring of the add-on's runs at its down")
    u.CHECK_NO = true
    k.ready(9, false)
    u.CHECK_NO = nil
    check(u.WHY_TOSTR == nil and said("its round skipped: (a table)"), "def.check's why (a table with a __tostring): logged without running it")
    D = { round = 1, now = 0 }; PLUGINS.tick()
    check(u.KIND_INDEX == nil and u.PAIRS_RAN == nil, "def.kind copied raw at register: its run's end reads no __index of the add-on's")
    D = nil; PLUGINS.tick()
end)

part("a target the add-on leaves up is Survival's again", function()
    local kd, e = SPC.kinds.tdrop, ENV("t_drop")
    D = { round = 1, now = 0 }
    kd.spawn(1)
    local a, b = actor("BP_Left_C"), actor("BP_Twice_C")
    asAddon("tdrop", SVP.target, a, { pay = 100 })
    local i1 = asAddon("tdrop", SVP.target, b, { pay = 0 })
    asAddon("tdrop", SVP.target, b, { pay = 0 })
    asAddon("tdrop", SVP.untarget, i1)
    check(PLUGINS.owned(rec(b)), "the same actor targeted twice: untargeting one leaves it the add-on's (the other target's)")
    kd.over(2, nil)
    check(not PLUGINS.owned(rec(a)) and not PLUGINS.owned(rec(b)), "its round over with them still up: Survival's again (tier, manoeuvres, stats)")
    a.HealthInternal = 0
    check(not skips(rec(a)), "and a later death of one is Survival's to count and pay")
    kd.spawn(3)
    local c = actor("BP_Off_C")
    asAddon("tdrop", SVP.target, c, {})
    e.DROP_SAY_NO = true
    local d = actor("BP_No_C")
    asAddon("tdrop", SVP.target, d, {})
    kd.spawn(4)
    check(not PLUGINS.owned(rec(d)) and not PLUGINS.owned(rec(c)), "a spawn that says no: its targets Survival's again")
    e.DROP_SAY_NO = nil
    kd.spawn(5)
    local f = actor("BP_Boom_C")
    asAddon("tdrop", SVP.target, f, {})
    e.DROP_BOOM = true
    kd.tick(6, {})
    check(kd.ready(9, false) == false and not PLUGINS.owned(rec(f)), "the add-on switched off: its targets Survival's again")
    D = nil
end)

part("SVP.retire / despawn of a unit already down keep its kill", function()
    local kd = SPC.kinds.tdrop
    D = { round = 1, now = 0 }
    ENV("t_drop").DROP_BOOM = nil
    PLUGINS.kinds.tdrop.off = nil                       -- (the part before switched it off)
    kd.spawn(1)
    local p0 = #paid
    local t, u, v = actor("BP_Shot_C"), actor("BP_Shot2_C"), actor("BP_Shot3_C")
    asAddon("tdrop", SVP.target, t, { pay = 100, flat = true })
    t.HealthInternal, u.HealthInternal, v.HealthInternal = 0, 0, 0    -- (the player's kills since the last sweep)
    local okR = asAddon("tdrop", SVP.retire, t)
    check(okR == true and #paid == p0 + 1 and paid[#paid].n == 100, "a target already down when retired: paid (the API's watch), not swallowed")
    asAddon("tdrop", SVP.retire, u)
    asAddon("tdrop", SVP.despawn, v)
    check(not skips(rec(u)) and not skips(rec(v)), "a unit already down when retired or despawned: not marked nobody's, Survival's kill")
    local w = actor("BP_Up_C")
    asAddon("tdrop", SVP.retire, w)
    check(w.HealthInternal <= 0 and skips(rec(w)), "(one it takes down itself: still nobody's)")
    kd.over(2, nil)
    D = nil
end)

part("SVP.despawn: a game unit is never destroyed by hand", function()
    local kc = SPC.kinds.coopk
    D = { round = 1, now = 0 }
    kc.spawn(1)
    local d0, p0 = destroyedUnits, #paid
    local u = actor("BP_Unit_C")
    local ok = asAddon("coopk", SVP.despawn, u)
    check(ok == true and u.live and u.HealthInternal <= 0 and destroyedUnits == d0 and skips(rec(u)) and #paid == p0,
        "a game unit (an ALiveAIGameObject): its own death (finishUnpaid), no K2_DestroyActor, nobody's kill")
    local inv = actor("BP_Unit2_C"); inv.invincible = true
    local from = #logs + 1
    local ok2 = asAddon("coopk", SVP.despawn, inv)
    check(ok2 == false and inv.live and inv.HealthInternal == 100 and destroyedUnits == d0 and said("never destroyed by hand", from),
        "a unit the game won't let die: left as it is, with a line")
    local plain = actor("BP_Thing_C", true)
    check(asAddon("coopk", SVP.despawn, plain) == true and plain.live == false, "anything else (not a unit): destroyed")
    kc.over(2, nil)
    D = nil
end)

part("what an add-on reads of Survival: SVP.pc, SVP.paused, SVP.intercept", function()
    check(asAddon("coopk", SVP.pc) == survivalPC, "SVP.pc(): your controller")
    paused = true
    local p1 = asAddon("coopk", SVP.paused)
    paused = false
    check(p1 == true and asAddon("coopk", SVP.paused) == false, "SVP.paused(): the game's pause")
    local m = actor("BP_Missile_C", true); m.weapon, m.inFlight = true, true
    local i0 = intercepts
    check(asAddon("coopk", SVP.intercept, m) == 1 and intercepts == i0 + 1, "SVP.intercept(m): a missile in flight shot down (SV_Intercept) -> 1")
    local notMissile = actor("BP_Plane_C")
    check(asAddon("coopk", SVP.intercept, notMissile) == nil and intercepts == i0 + 1, "not a missile (LiveWeaponBase): nil, SV_Intercept not asked")
    going = true
    local g = asAddon("coopk", SVP.intercept, m)
    local pc = asAddon("coopk", SVP.pc)
    going = false
    check(g == nil and pc == nil and intercepts == i0 + 1, "while the level goes: SVP.intercept and SVP.pc answer nil")
end)

part("the level going", function()
    local o = SPC.kinds.ovr
    D = { round = 1, now = 0 }
    o.spawn(1)
    local a = actor("BP_Go_C", true)
    going = true
    local mv = asAddon("coopk", SVP.move, a, { X = 1, Y = 1, Z = 1 }, nil)
    local ds = asAddon("coopk", SVP.despawn, a)
    local hu = asAddon("coopk", SVP.hurt, a, 1, nil)
    local tg = asAddon("coopk", SVP.target, a, {})
    local ld = asAddon("coopk", SVP.load, "/Game/X/Y.Y")
    local pp = asAddon("coopk", SVP.playerPlane)
    local pl = asAddon("coopk", SVP.players)
    check(not mv and not ds and not hu and tg == nil and ld == nil and pp == nil and #pl == 0 and a.live and a.HealthInternal == 100,
        "while the level goes: SVP.move, despawn, hurt, target, load, playerPlane, players refuse")
    going = false
    SPC.kinds.coopk.spawn(1)
    local tid = asAddon("coopk", SVP.target, actor("BP_Go2_C"), {})
    going = true
    local c0, b0, h0 = #callouts, #bgm, #holds
    local r = { asAddon("coopk", SVP.kill, tid, "test"), asAddon("coopk", SVP.sound, "/Game/X/S.S", { X = 0, Y = 0, Z = 0 }),
        asAddon("coopk", SVP.fx, "/Game/X/F.F", { X = 0, Y = 0, Z = 0 }), asAddon("coopk", SVP.hud, false, "test"),
        asAddon("coopk", SVP.bgm, false), asAddon("coopk", SVP.callout, "X"), asAddon("coopk", SVP.say, "a", "b", 1),
        asAddon("coopk", SVP.play2d, "/Game/X/W.W"), asAddon("coopk", SVP.hold2d, "/Game/X/W.W"),
        asAddon("coopk", SVP.pin, { live = true, addr = 0x9990 }, "test") }
    local all = true
    for i = 1, 10 do if r[i] then all = false end end
    check(all and #callouts == c0 and #bgm == b0 and #holds == h0 and asAddon("coopk", SVP.alive, tid),
        "and SVP.kill, sound, fx, hud, bgm, callout, say, play2d, hold2d, pin")
    ENV("o_over").OVER_CALLED = false
    PLUGINS.tick()
    check(ENV("o_over").OVER_CALLED == false, "a round whose level goes: its over isn't called then (abort only)")
    going = false
    D = nil
    PLUGINS.tick()
end)

part("between add-ons, and small things", function()
    -- (a mark is honoured only with its name)
    local kc = SPC.kinds.coopk
    D = { round = 1, now = 0 }
    kc.spawn(1)
    local a = actor("BP_NoName_C")
    a.GetFullName = function() error("no name") end
    asAddon("coopk", SVP.target, a, {})
    local b = actor("BP_Named_C")
    asAddon("coopk", SVP.target, b, {})
    check(not PLUGINS.owned(rec(a)) and not PLUGINS.owned({ obj = b, addr = b.addr }),
        "a mark with no name (its full name unread), or a plane record with none: not taken as the add-on's")
    -- (an add-on acts on its own targets and actors only)
    local tid = asAddon("coopk", SVP.target, actor("BP_Theirs_C"), {})
    check(asAddon("tdrop", SVP.kill, tid, "not mine") == false and asAddon("tdrop", SVP.alive, tid) == false
        and asAddon("coopk", SVP.alive, tid) == true, "another add-on's target: its kill refused, alive false for it")
    local mine = asAddon("coopk", SVP.spawn, "/Game/X/BP_Thing.BP_Thing_C", { X = 0, Y = 0, Z = 0 }, 0)
    check(asAddon("tdrop", SVP.despawn, mine) == false and asAddon("tdrop", SVP.move, mine, { X = 1, Y = 1, Z = 1 }) == false
        and mine.live and mine.HealthInternal == 100, "another add-on's spawned actor: SVP.despawn and move refused")
    local sv = actor("BP_Survivals_C")                  -- (one of Survival's planes, only hurt by one add-on)
    asAddon("coopk", SVP.hurt, sv, 1, nil)
    PLUGINS.kinds.tdrop.off = nil
    SPC.kinds.tdrop.spawn(1)                            -- (its own round: SVP.target is a round's)
    check(asAddon("tdrop", SVP.target, sv, {}) ~= nil, "an actor another add-on only hurt (not spawned, not targeted): still anyone's")
    SPC.kinds.tdrop.over(2, nil)
    local pawn = actor("BP_Me2_C")
    survivalPC.Pawn = pawn
    check(asAddon("coopk", SVP.despawn, pawn) == false and asAddon("coopk", SVP.retire, pawn) == false and pawn.HealthInternal == 100,
        "your plane: never despawned or retired (SVP.killPlayer is the way)")
    survivalPC.Pawn = nil
    kc.over(2, nil)
    -- (the caller: the innermost guarded call's add-on, not the one loading)
    PLUGINS.current, PLUGINS.running = PLUGINS.kinds.coopk, PLUGINS.kinds.tdrop
    local cfgA = SVP.cfg()
    PLUGINS.current, PLUGINS.running = nil, nil
    check(cfgA ~= nil and cfgA.a == nil, "a callback of one add-on run while another loads: the calls are the callback's add-on's (its SVP.cfg)")
    -- (read-only views: one cache an add-on)
    local sp = { state = "real" }
    D = { round = 1, now = 0 }
    SPC.kinds.raw1.spawn(1); SPC.kinds.raw2.spawn(1)
    SPC.kinds.raw1.tick(1, sp); SPC.kinds.raw2.tick(1, sp)
    check(ENV("r_raw2").SEEN == "real", "a rawset on Survival's read-only view by one add-on: another still reads Survival's value")
    -- (SVP.p2dMs on its own SVP)
    asAddon("coopk", SVP.play2d, "/Game/X/W_Wave")
    check(type(ENV("c_coop").SVP.p2dMs) == "string", "SVP.p2dMs (the last play2d's parts): on the add-on's own SVP")
    -- (the add-on's object walks wait while the engine frees objects: walkBusy)
    -- (StaticFindObject too: UE4SS's Lua StaticFindObject walks every object, FindObject -> ForEachUObject; round 12
    -- P1's crash, 20261113-101700-5e40ab6, faulted there on an Outer freed during a purge)
    local f0, r, s0 = finds, ENV("r_raw2"), SFO_N
    GC_BUSY, r.FIND_NOW = true, true
    PLUGINS.tick()
    GC_BUSY = nil
    check(r.FOUND == nil and r.FOUND1 == nil and r.FOUND_S == nil and finds == f0 and SFO_N == s0,
        "FindAllOf / FindFirstOf / StaticFindObject refused while the engine frees objects (walkBusy): nil, the game not asked")
    r.FIND_NOW, r.FOUND_S = true, nil
    local s1 = SFO_N
    PLUGINS.tick()
    check(r.FOUND_S ~= nil and SFO_N == s1 + 1, "the purge over: the add-on's StaticFindObject answers as before")
    -- (the API's own finds: its classes and default objects, an add-on's asset before it's loaded)
    local find = PLUGINS.find
    check(type(find) == "function", "the API's own finds go through PLUGINS.find")
    if type(find) == "function" then
        s0 = SFO_N
        local n1 = find("/Script/Niagara.Default__NiagaraFunctionLibrary")
        local n2 = find("/Script/Niagara.Default__NiagaraFunctionLibrary")
        check(n1 == NIAGARA and n2 == n1 and SFO_N == s0 + 1, "the API's find: found once, then kept (no second walk)")
        GC_BUSY = true
        s0 = SFO_N
        local n3, x = find("/Script/Niagara.Default__NiagaraFunctionLibrary"), find("/Script/Live.LivePlayerPlane")
        check(n3 == NIAGARA and x == nil and SFO_N == s0,
            "while the engine frees objects: a kept find still answered, a new one nil, the game not asked")
        s0 = SFO_N
        local w, whyW = asAddon("coopk", SVP.load, "/Game/X/W_NewWave.W_NewWave")
        check(w == nil and tostring(whyW):find("try again", 1, true) ~= nil and SFO_N == s0,
            "SVP.load while the engine frees objects: nil, try again (no StaticFindObject, nothing loaded)")
        -- (sounds and effects start nothing then: a mod's run on this line, 20261113-151013-f108042, had a wave freed
        -- under the sound a play started during the purge)
        local sp, cr, fx0, lo = 0, 0, NIAGARA.spawned, 0
        GS.SpawnSound2D = function() sp = sp + 1; return { live = true } end
        GS.CreateSound2D = function() cr = cr + 1; return { live = true } end
        local realLoad = loadObject
        loadObject = function(p2) lo = lo + 1; return realLoad(p2) end
        local p1 = asAddon("coopk", SVP.play2d, "/Game/X/W_Busy")
        local h1, why1 = asAddon("coopk", SVP.hold2d, "/Game/X/W_Busy2")
        local s1 = asAddon("coopk", SVP.sound, "/Game/X/S_Busy.S_Busy", { X = 0, Y = 0, Z = 0 })
        local f1 = asAddon("coopk", SVP.fx, "/Game/X/F_Busy.F_Busy", { X = 0, Y = 0, Z = 0 })
        check(p1 == false and h1 == nil and tostring(why1):find("try again", 1, true) ~= nil and s1 == false and f1 == nil
            and sp == 0 and cr == 0 and NIAGARA.spawned == fx0 and lo == 0,
            "while the engine frees objects: play2d / hold2d / sound / fx start nothing and load nothing (false / nil, try again)")
        GC_BUSY = nil
        local sp0, cr0 = sp, cr
        local p2 = asAddon("coopk", SVP.play2d, "/Game/X/W_Busy")
        local h2 = asAddon("coopk", SVP.hold2d, "/Game/X/W_Busy2")
        check(p2 == true and sp == sp0 + 1 and h2 ~= nil and cr == cr0 + 1, "the purge over: play2d / hold2d start as before")
        -- (a found asset the GC has condemned: UE4SS's walk doesn't skip it; liveObj (SV_ObjChain) says no: not used)
        local CW = { live = true, path = "/Game/X/W_Cond.W_Cond", GetFullName = function() return "SoundWave /Game/X/W_Cond.W_Cond" end }
        local sfo, lo0, sp1 = StaticFindObject, lo, sp
        StaticFindObject = function(q) if q == "/Game/X/W_Cond.W_Cond" then return CW end return sfo(q) end
        local lv = liveObj
        liveObj = function(o) if o == CW then return false end return lv(o) end
        local l0 = #logs
        local c1, cw = asAddon("coopk", SVP.load, "/Game/X/W_Cond.W_Cond")
        local c2 = asAddon("coopk", SVP.play2d, "/Game/X/W_Cond")
        local c3 = asAddon("coopk", SVP.play2d, "/Game/X/W_Cond")
        local said = 0
        for i = l0 + 1, #logs do if tostring(logs[i]):find("condemned", 1, true) then said = said + 1 end end
        check(c1 == nil and tostring(cw):find("condemned", 1, true) ~= nil and c2 == false and c3 == false and sp == sp1
            and lo == lo0 and said == 1,
            "a found asset the GC has condemned (liveObj no): SVP.load nil, play2d plays nothing, not loaded; logged once")
        liveObj = lv
        local sp2 = sp
        local c4 = asAddon("coopk", SVP.play2d, "/Game/X/W_Cond")
        check(c4 == true and sp == sp2 + 1, "the same asset live again (the purge over): play2d plays it")
        StaticFindObject = sfo
        loadObject, GS.SpawnSound2D, GS.CreateSound2D = realLoad, nil, nil
    end
    D = nil; PLUGINS.tick()
end)

part("the runaway stop", function()
    local wd0 = WD.fired
    D = { round = 1, now = 0 }
    -- (a provider that loops, called by another add-on's tick: the provider's add-on switched off, the caller stays on)
    local saved = PLUGINS.providers.hurtPlayer
    PLUGINS.providers.hurtPlayer = nil
    asAddon("prov2", SVP.provide, "hurtPlayer", ENV("z_prov2").PROV_LOOP)
    survivalPC.Pawn = actor("BP_Me3_C")
    local kh = SPC.kinds.hurter
    kh.spawn(1)
    watchdog(true, "a provider's runaway")
    local okH = pcall(kh.tick, 4, {})
    watchdog(false)
    check(okH and WD.fired == wd0 and addon("z_prov2").off == true and kh.ready(9, false) == true and said("Prov2's callback inside it ran away"),
        "another add-on's provider that loops: that add-on switched off, the caller stays on")
    PLUGINS.providers.hurtPlayer, survivalPC.Pawn = saved, nil
    -- (the framework's own pcall raises a stop on: an add-on's __index run in SVP.move's pcall can't swallow it)
    local km = SPC.kinds.wmov
    km.spawn(1)
    watchdog(true, "a stop in SVP.move's pcall")
    local okM = pcall(km.tick, 5, {})
    watchdog(false)
    check(okM and WD.fired == wd0 and ENV("w_move").MOVE_ESCAPED == true and ENV("w_move").LOOPED == nil and km.ready(9, false) == true,
        "SVP.move reads the add-on's position raw: its __index (a loop) never runs inside the API's calls")
    frames.runaway = "a stop"
    local okP, eP = pcall(PLUGINS.pcall, function() error("caught by an add-on") end)
    frames.runaway = nil
    check(okP == false and eP == "a stop", "the framework's own pcall raises a runaway stop on (" .. tostring(eP) .. ")")
    check(ENV("q_load").LOAD_FN[1] == nil and ENV("q_load").LOAD_STR == 7, "load: a string only (a reader function runs in load's own protected call)")
    kh.over(9, nil); km.over(9, nil)
    D = nil; PLUGINS.tick()
end)

part("register reads def once", function()
    local m = ENV("r_meta")
    local k = SPC.kinds.rmeta
    check(m.META_OK[1] == true and k ~= nil and m.META_READS() == 0, "def given through a metatable: its own fields only, none read through __index")
    check(k.ready(9, false) == true and m.CALLED_BARE == nil, "so no callable table read the second time is ever called bare")
    check(said("def or def.kind has a metatable: only their own fields are read"), "and that's said")
    local b = ENV("v_bigapi").BIG
    check(b[1] == true and b[2] == false and said("isn't a version"), "def.api a 20-digit number: refused as no version, nothing raised")
end)

part("handles are UE4SS objects", function()
    local u = ENV("u_tbl")
    local k = SPC.kinds.utbl
    D = { round = 1, now = 0 }
    k.spawn(1)
    local t, h = u.FAKE_T, actor("BP_Real_C")
    local c0 = u.TBL_CALLS
    local r = { asAddon("utbl", SVP.target, t, {}), asAddon("utbl", SVP.move, t, { X = 1, Y = 1, Z = 1 }),
        asAddon("utbl", SVP.hurt, t, 5), asAddon("utbl", SVP.hurt, h, 5, t), asAddon("utbl", SVP.retire, t),
        asAddon("utbl", SVP.despawn, t), asAddon("utbl", SVP.pin, t, "x"), asAddon("utbl", SVP.intercept, t),
        asAddon("utbl", SVP.liveObj, t) }
    local refusedAll = true
    for i = 1, 9 do if r[i] then refusedAll = false end end
    k.tick(2, {}); k.tick(3, {})
    check(refusedAll and h.HealthInternal == 100, "a table of the add-on's: target, move, hurt (and as causer), retire, despawn, pin, intercept, liveObj refuse it")
    check(u.TBL_CALLS == c0, "none of its methods or fields read, then or in its round's ticks (" .. (u.TBL_CALLS - c0) .. ")")
    k.over(4, nil)
    D = nil
end)

part("targets", function()
    local e, ke = ENV("e_tgt"), SPC.kinds.etgt
    D = { round = 1, now = 0 }; PLUGINS.tick()
    e.TGT_NOW = true; PLUGINS.tick()
    check(e.EVERY_TGT == false and said("SVP.target outside its own round"), "SVP.target from SVP.every (no round of its own): refused, said")
    local kc = SPC.kinds.coopk
    kc.spawn(1)
    check(asAddon("etgt", SVP.target, actor("BP_Theirs2_C"), {}) == nil, "SVP.target while another add-on's round is on: refused")
    kc.over(2, nil)
    D = nil; PLUGINS.tick()
    local left = 0
    for _, x in pairs(PLUGINS.targets) do if x.p == addon("e_tgt") then left = left + 1 end end
    check(left == 0, "nothing of it left at the run's end")
    D = { round = 1, now = 0 }; PLUGINS.tick()
    ke.spawn(1)
    local acts, n = {}, 0
    for i = 1, 129 do acts[i] = actor("BP_Many_C") end
    for i = 1, 258 do if asAddon("etgt", SVP.target, acts[(i - 1) % 129 + 1], {}) then n = n + 1 end end
    check(n == 256 and said("256 targets at most"), "256 targets an add-on at most, said (" .. n .. ")")
    ke.over(2, nil)
    local any = false
    for i = 1, 129 do if PLUGINS.owned(rec(acts[i])) then any = true end end
    check(not any and next(PLUGINS.tkeys) == nil, "its round over: all dropped in one pass, every plane Survival's again")
    ke.spawn(3)
    local t = actor("BP_Kept_C")
    asAddon("etgt", SVP.target, t, {})
    going = true; PLUGINS.tick(); going = false
    check(next(PLUGINS.targets) == nil, "the level going: every target dropped")
    D = nil; PLUGINS.tick()
end)

part("a handle from an older level", function()
    local kc = SPC.kinds.coopk
    D = { round = 1, now = 0 }; PLUGINS.tick()
    kc.spawn(1)
    local h = actor("BP_Old_C")
    asAddon("coopk", SVP.hurt, h, 1, nil)                 -- (recorded in this level)
    local h0 = h.HealthInternal
    going = true; PLUGINS.tick(); going = false
    D = { round = 1, now = 0 }; PLUGINS.tick()
    kc.spawn(1)
    check(asAddon("coopk", SVP.hurt, h, 5, nil) == false and h.HealthInternal == h0,
        "a handle kept from the last level (its object's name and address the same): refused, not recorded again as new")
    local h2 = actor("BP_New2_C")
    check(asAddon("coopk", SVP.hurt, h2, 1, nil) == true, "a handle of this level: served")
    kc.over(2, nil)
    D = nil; PLUGINS.tick()
end)

part("NotifyOnNewObject", function()
    local c = ENV("c_coop")
    NOTIFY_REFUSE["/Script/Late.Thing"] = true
    local got = 0
    local r1 = c.NotifyOnNewObject("/Script/Late.Thing", function() got = got + 1 end)
    check(r1 == false and said("UE4SS refused it"), "a class UE4SS refuses: false, said, nothing kept")
    NOTIFY_REFUSE["/Script/Late.Thing"] = nil
    local r2 = c.NotifyOnNewObject("/Script/Late.Thing", function() got = got + 1 end)
    check(r2 == true and type(notified["/Script/Late.Thing"]) == "function", "asked again once it's loaded: registered")
    notified["/Script/Late.Thing"]({}); PLUGINS.tick()
    check(got == 1, "and its objects come")
    NOTE_CLS["/Script/Late.Thing"].live, NOTE_GONE["/Script/Late.Thing"] = false, true
    notified["/Script/Late.Thing"]({}); PLUGINS.tick()
    NOTE_CLS["/Script/Late.Thing"].live, NOTE_GONE["/Script/Late.Thing"] = true, nil
    check(got == 1 and said("its class isn't found: nothing handed over"), "its class not found at the tick: nothing handed over (no IsA to ask), said")
    local f1, f2 = 0, 0
    c.NotifyOnNewObject("/Script/Live.LiveDup", function() f1 = f1 + 1 end)
    c.NotifyOnNewObject("/Script/Live.LiveDup", function() f2 = f2 + 1 end)
    local o = actor("BP_Dup_C", true)
    local w0 = walkHolds
    notified["/Script/Live.LiveDup"](o); notified["/Script/Live.LiveDup"](o)
    check(walkHolds == w0, "UE4SS's callback (the constructing thread) runs none of Survival's Lua (walkHold not asked)")
    PLUGINS.tick()
    check(f1 == 0 and f2 == 1, "asked twice for a class: the second callback replaces the first; an object told twice handed over once")
    local yes = 0
    for i = 1, 70 do if c.NotifyOnNewObject("/Script/Live.Many" .. i, function() end) then yes = yes + 1 end end
    check(yes < 70 and said("64 classes at most"), "64 classes at most, said (" .. yes .. " of 70 more taken)")
end)

part("handles, a player's plane, the bag, the pieces, the song", function()
    local kc = SPC.kinds.coopk
    D = { round = 1, now = 0 }; PLUGINS.tick()
    kc.spawn(1)
    local me = actor("BP_Wingman_C"); me.player = true
    local m0 = { X = me.X, Y = me.Y }
    local t = asAddon("coopk", SVP.target, me, { pay = 10 })
    local mv = asAddon("coopk", SVP.move, me, { X = 5, Y = 5, Z = 5 })
    check(t == nil and mv == false, "SVP.target / SVP.move refuse a player's plane (another player's too: its class)")
    local dead = actor("BP_Gone_C"); dead.live = false
    local reads = 0
    dead.IsA = function() reads = reads + 1; return false end
    local r = { asAddon("coopk", SVP.move, dead, { X = 1, Y = 1, Z = 1 }), asAddon("coopk", SVP.despawn, dead),
        asAddon("coopk", SVP.retire, dead) }
    check(r[1] == false and r[2] == false and r[3] == false and reads == 0,
        "move / despawn / retire of a freed actor: refused before the engine is asked anything of it (IsA " .. reads .. ")")
    local h = actor("BP_Hit_C")
    local hit = asAddon("coopk", SVP.hurt, h, 5, dead)
    check(hit == false and h.HealthInternal == 100, "SVP.hurt with a freed causer: refused, the game not handed it")
    local sp = asAddon("coopk", SVP.spawn, { live = true }, { X = 0, Y = 0, Z = 0 }, 0)
    check(sp == nil, "SVP.spawn of a class that is a table of the add-on's: refused, never read")
    kc.over(2, nil)
    D = nil
    local load = PLUGINS.load
    PLUGINS.load, PLUGINS.loadDone = nil, false
    PLUGINS.tick()
    local latched = PLUGINS.loadDone
    PLUGINS.load, PLUGINS.loadDone = load, true
    check(latched == false, "a tick before sv_plugins_env.lua is in: nothing done, the add-ons still load at the next")
    local muted = {}
    local playBGM = SV_PlayBGM
    SV_PlayBGM = function(ev) muted[#muted + 1] = ev; return 1 end
    local pk = PLUGINS.kinds.coopk
    pk.bgmMuted = true
    local snd = SND
    SND = { song = { muted = true } }
    PLUGINS.bgmBack(pk, "test")
    SND = snd
    SV_PlayBGM = playBGM
    check(#muted == 0 and said("Survival's own song keeps the game's muted"), "the music given back while Survival's own song mutes the game's: no unmute posted")
end)

part("the runaway stop lands in the add-on's own code; the one that loops is blamed", function()
    local wd0 = WD.fired
    D = { round = 1, now = 0 }; PLUGINS.tick()
    local src = debug.getinfo(1, "S").source              -- (the test's own stand-ins for Survival's code: HUD.hold, SV_PlayBGM)
    PLUGINS.ownSrc[src] = true
    local k = SPC.kinds.hudloop
    k.spawn(1)
    local hold0 = HUD.hold
    HUD.hold = function(on, why)
        local r = hold0(on, why)
        if on then fakeClock = fakeClock + 11; local x = 0; for i = 1, 150000 do x = x + i end end
        return r
    end
    watchdog(true, "a HUD / music loop's runaway")
    local okT = pcall(k.tick, 2, {})
    watchdog(false)
    HUD.hold = hold0
    PLUGINS.ownSrc[src] = nil
    local p = addon("w_hudloop")
    local lastHold
    for i = #holds, 1, -1 do if holds[i]:find("w_hudloop", 1, true) then lastHold = holds[i]; break end end
    check(okT and WD.fired == wd0 and p.off == true and p.hudHidden == nil and p.bgmMuted == false
        and lastHold == "off add-on w_hudloop" and bgm[#bgm] == "AKE_System_BGM_Mute_Off",
        "a loop toggling Survival's HUD and music, stopped: its HUD hold and the music mute both given back (" .. tostring(lastHold) .. ")")
    k.over(3, nil)
    local saved = PLUGINS.providers.hurtPlayer
    PLUGINS.providers.hurtPlayer = nil
    asAddon("prov3", SVP.provide, "hurtPlayer", ENV("z_prov3").PROV_SHORT)
    survivalPC.Pawn = actor("BP_Me4_C")
    local kb = SPC.kinds.blamer
    kb.spawn(1)
    watchdog(true, "a caller's runaway through a short provider")
    local okB = pcall(kb.tick, 4, {})
    watchdog(false)
    check(okB and WD.fired == wd0 and addon("w_blame").off == true and addon("z_prov3").off ~= true,
        "a caller looping through another add-on's short provider: the caller switched off, the provider's add-on stays on")
    PLUGINS.providers.hurtPlayer, survivalPC.Pawn = saved, nil
    kb.over(5, nil)
    D = nil; PLUGINS.tick()
end)

part("a kind's tick only in its round; music and HUD only in a run; the add-on's own text and chunk names", function()
    local k, e = SPC.kinds.tfirst, ENV("w_tfirst")
    D = { round = 1, now = 0 }; PLUGINS.tick()
    k.tick(1, { state = "pending" })
    local before = e.TICKS
    k.spawn(2); k.tick(3, { n = 1 })
    local during = e.TICKS
    k.over(4, nil); k.tick(5, { state = "pending" })
    check(before == nil and during == 1 and e.TICKS == 1 and addon("w_tfirst").off ~= true,
        "a kind's tick: not before its spawn (Survival ticks a special from its round's start), not after its over")
    D = nil; PLUGINS.tick()
    local b0, h0 = #bgm, #holds
    local m, h = asAddon("coopk", SVP.bgm, false), asAddon("coopk", SVP.hud, false, "menu")
    check(m == false and h == false and #bgm == b0 and #holds == h0,
        "SVP.bgm(false) / SVP.hud(false) with no run (the main menu): refused (nothing would give them back)")
    asAddon("coopk", SVP.log, "x\n12:00:00 plugins: none (no AC8SurvivalAddons folder)")
    check(not logs[#logs]:find("\n", 1, true) and logs[#logs]:find("plugin ", 1, true) == 1,
        "an add-on's log text is one line: it can't forge Survival's own lines")
    local f = ENV("c_coop").load("return 1", "@Mods/AC8SurvivalMode/Scripts/sv_core.lua")
    local fsrc = f and debug.getinfo(f, "S").source or "?"
    check(fsrc:sub(1, 1) == "=" and fsrc:find("c_coop", 1, true), "an add-on's load names its chunk as its own (" .. fsrc .. "), never one of Survival's files")
    -- (another's C hook (a native profiler's): the guarded calls still counted, so a name is read again in the next call)
    local p = PLUGINS.kinds.coopk
    D = { round = 1, now = 0 }; PLUGINS.tick()
    local a = asAddon("coopk", SVP.spawn, "/Game/X/BP_Hooked.BP_Hooked_C", { X = 0, Y = 0, Z = 0 }, 0)
    local gh = debug.gethook
    PLUGINS.running = p
    debug.gethook = function() return "a C hook" end
    local r1 = PLUGINS.hooked(p, function() return SVP.move(a, { X = 1, Y = 1, Z = 1 }) end)
    a.full = "LiveAIPlane /Game/Map.Map:PersistentLevel.Other_1"
    local r2 = PLUGINS.hooked(p, function() return SVP.move(a, { X = 2, Y = 2, Z = 2 }) end)
    debug.gethook = gh
    PLUGINS.running = nil
    check(r1[2] == true and r2[2] == false, "with another's C hook set: each guarded call still counted (the name read again: another object refused)")
    D = nil; PLUGINS.tick()
end)

part("no other part of Survival sets a global the add-on API's pieces set (the split made their helpers globals)", function()
    -- (the pieces' globals: a function, or a name set at the do block's own level, not local; read from their text)
    local mine, okL = {}, true
    for _, piece in ipairs(PARTS.sources("sv_plugins")) do
        for line in piece.src:gmatch("[^\n]+") do
            local g = line:match("^%s*function%s+([%w_]+)%s*%(") or line:match("^    ([%w_]+)%s*=[^=]")   -- (the do block's own level)
            if g and g ~= "local" then mine[g] = true end
        end
    end
    local mods = readAll(MOD .. "/Scripts/main.lua"):match("MODULES%s*=%s*(%b{})") or ""
    local fam = {}
    for _, n in ipairs(PARTS.family("sv_plugins")) do fam[(n:gsub("%.lua$", ""))] = true end
    local clash = {}
    for name in mods:gmatch('"([%w_]+)"') do
        if not fam[name] then
            local okR, src = pcall(readAll, MOD .. "/Scripts/" .. name .. ".lua")
            for line in (okR and src or ""):gmatch("[^\n]+") do
                local g = line:match("^%s*function%s+([%w_]+)%s*%(") or line:match("^([%w_]+)%s*=[^=]")
                if g and mine[g] then clash[#clash + 1] = name .. ".lua: " .. g end
            end
        end
    end
    local nm = 0
    for _ in pairs(mine) do nm = nm + 1 end
    check(okL and nm > 20 and #clash == 0, "none (" .. (#clash > 0 and table.concat(clash, ", ") or (nm .. " globals, every MODULES part read")) .. ")")
end)

part("the second self-review's finds", function()
    -- (a loop that allocates: stopped by Lua memory, long before 10 s)
    local wd0 = WD.fired
    D = { round = 1, now = 0 }; PLUGINS.tick()
    PLUGINS.runawayKB = 4 * 1024
    local k = SPC.kinds.memloop
    k.spawn(1)
    watchdog(true, "a memory runaway")
    local okM = pcall(k.tick, 2, {})
    watchdog(false)
    PLUGINS.runawayKB = nil
    check(okM and WD.fired == wd0 and addon("w_memloop").off == true and said("MB more Lua memory since it began"),
        "a loop that allocates: stopped at the Lua memory limit, its add-on switched off")
    k.over(3, nil)
    -- (the soft sign: what the round's add-on is told follows levelGoing, the one-way steps the hard sign)
    local ks = SPC.kinds.softk
    ks.spawn(4)
    LEAVE, going, D = { hard = false }, true, nil
    PLUGINS.tick()
    LEAVE, going = nil, false
    local e = ENV("w_soft")
    check(e.SOFT_WHY == "the level is going" and e.SOFT_OVER == nil, "a run left under the soft sign: abort told the level is going, no over (" .. tostring(e.SOFT_WHY) .. ")")
    PLUGINS.tick()
    -- (a level change no tick saw going: Survival's level drop runs the one-way steps at the next tick)
    D = { round = 1, now = 0 }; PLUGINS.tick()
    local kc = SPC.kinds.coopk
    kc.spawn(1)
    local t = actor("BP_Missed_C")
    local tid = asAddon("coopk", SVP.target, t, { pay = 5 })
    local lv0 = PLUGINS.level
    LEVEL_DROPS["add-ons"]("the level gate")
    D = { round = 1, now = 0 }; PLUGINS.tick()
    check(tid ~= nil and PLUGINS.level == lv0 + 1 and asAddon("coopk", SVP.alive, tid) == false,
        "a level dropped between two ticks: the level's handles an older level's, its targets dropped, at the next tick")
    -- (pins: assets only)
    local lvl = { live = true }
    FAKE[lvl] = true
    function lvl:IsValid() return true end
    function lvl:GetFullName() return "Level /Game/Map.Map:PersistentLevel" end
    local ac = actor("BP_PinMe_C")
    function ac:GetOuter() return lvl end
    check(asAddon("coopk", SVP.pin, ac, "an actor") == false and said("SVP.pin: an object of the level"), "SVP.pin of an actor (its outers reach a level): refused, assets only")
    -- (one mute for every holder)
    local pa = PLUGINS.kinds.coopk
    local b0 = #bgm
    asAddon("coopk", SVP.bgm, false); asAddon("prov3", SVP.bgm, false)
    asAddon("coopk", SVP.bgm, true)
    local mid = bgm[#bgm]
    asAddon("prov3", SVP.bgm, true)
    check(pa.bgmMuted == false and mid == "AKE_System_BGM_Mute_On" and bgm[#bgm] == "AKE_System_BGM_Mute_Off",
        "two add-ons mute Survival's music: the first giving it back unmutes nothing, the last does")
    -- (retire: hard rule 59's fresh read)
    local r = asAddon("coopk", SVP.spawn, "/Game/X/BP_Ret.BP_Ret_C", { X = 0, Y = 0, Z = 0 }, 0)
    r.full = "LiveAIPlane /Game/Map.Map:PersistentLevel.Someone_9"
    check(asAddon("coopk", SVP.retire, r) == false and r.HealthInternal == 100, "SVP.retire of an actor whose address is another object's now: refused")
    -- (NotifyOnNewObject: an object not of its class isn't handed over)
    local c = ENV("c_coop")
    local got = 0
    c.NotifyOnNewObject("/Script/Late.Thing", function() got = got + 1 end)
    notified["/Script/Late.Thing"]({ notA = true }); PLUGINS.tick()
    notified["/Script/Late.Thing"]({}); PLUGINS.tick()
    check(got == 1, "a NotifyOnNewObject object not of its class (another at its address): not handed over")
    -- (an add-on's chunks are named for it)
    local src = debug.getinfo(ENV("z_prov3").PROV_SHORT, "S").source
    check(src:find("^@AC8SurvivalAddons\\z_prov3\\") ~= nil, "an add-on's files are named AC8SurvivalAddons\\<folder>\\<file> (" .. src .. "): never one of Survival's paths")
    kc.over(9, nil)
    D = nil; PLUGINS.tick()
end)

part("the final review's finds", function()
    local wd0 = WD.fired
    D = { round = 1, now = 0 }; PLUGINS.tick()
    local src = debug.getinfo(1, "S").source
    -- (a loop inside Survival's own code, called by an add-on: stopped 5 s past the deadline all the same)
    PLUGINS.ownSrc[src] = true
    local callout0 = hudCallout
    hudCallout = function() while true do fakeClock = fakeClock + 0.0001 end end
    local k = SPC.kinds.callloop
    k.spawn(1)
    local t0 = fakeClock
    watchdog(true, "a loop in Survival's code")
    local okC = pcall(k.tick, 2, {})
    watchdog(false)
    local took = fakeClock - t0
    hudCallout = callout0
    PLUGINS.ownSrc[src] = nil
    check(okC and WD.fired == wd0 and addon("w_callloop").off == true and took >= 15 and took < 20,
        string.format("a loop inside Survival's own code an add-on called: stopped 5 s past the deadline (%.1f s, the hook's count after it), its add-on off", took))
    k.over(3, nil)
    -- (a memory runaway in another add-on's provider: that add-on is the one switched off)
    local saved = PLUGINS.providers.hurtPlayer
    PLUGINS.providers.hurtPlayer = nil
    asAddon("prov4", SVP.provide, "hurtPlayer", ENV("z_prov4").PROV_ALLOC)
    survivalPC.Pawn = actor("BP_Me5_C")
    PLUGINS.runawayKB = 4 * 1024
    local km = SPC.kinds.memcall
    km.spawn(1)
    watchdog(true, "a provider's memory runaway")
    local okM = pcall(km.tick, 4, {})
    watchdog(false)
    PLUGINS.runawayKB = nil
    check(okM and WD.fired == wd0 and addon("z_prov4").off == true and addon("w_memcall").off ~= true,
        "a memory runaway in another add-on's provider: that add-on switched off, the caller stays on")
    PLUGINS.providers.hurtPlayer, survivalPC.Pawn = saved, nil
    km.over(5, nil)
    -- (loadfile's chunk name: the add-on's folder and the file's name, the path's end kept)
    local tmp = os.tmpname()
    local f = io.open(tmp, "w"); f:write("return 1\n"); f:close()
    local lf = ENV("c_coop").loadfile(tmp)
    local lsrc = lf and debug.getinfo(lf, "S").source or "?"
    os.remove(tmp)
    check(lsrc == "=c_coop:" .. tmp:match("[^/\\]+$"), "an add-on's loadfile names its chunk <folder>:<file> (" .. lsrc .. ")")
    -- (SVP.say: its text handed on as strings, no __tostring of the add-on's run in Survival's subtitles)
    local sub0, said0, leak = SUB, nil, false
    SUB = { say = function(w, t) said0 = { w, t } end }
    asAddon("coopk", SVP.say, setmetatable({}, { __tostring = function() leak = true; return "x" end }), "hi", 3)
    SUB = sub0
    check(said0 and said0[1] == "(a table)" and said0[2] == "hi" and not leak, "SVP.say: who and text as strings (a table with __tostring not asked)")
    -- (a level change no tick saw going: the round's add-on told the level is going)
    local e, ks = ENV("w_soft"), SPC.kinds.softk
    e.SOFT_WHY, e.SOFT_OVER = nil, nil
    ks.spawn(6)
    LEVEL_DROPS["add-ons"]("the level gate")
    D = { round = 1, now = 0 }; PLUGINS.tick()
    check(e.SOFT_WHY == "the level is going" and e.SOFT_OVER == nil, "a level change no tick saw going: abort told the level is going (" .. tostring(e.SOFT_WHY) .. ")")
    D = nil; PLUGINS.tick()
end)

part("SVP.widget", function()
    -- (UE4SS's classes and objects, as tables the test lists as handles: a class's chain by GetSuperStruct)
    local function cls(full, super)
        local c = { live = true, full = full }
        FAKE[c] = true
        function c:IsValid() return self.live end
        function c:GetFullName() return self.full end
        function c:GetSuperStruct() return super end
        return c
    end
    local object = cls("Class /CoreUObject.Object")
    local widget = cls("Class /Script/UMG.Widget", object)
    local text = cls("Class /Script/UMG.TextBlock", cls("Class /Script/UMG.TextLayoutWidget", widget))
    local treeC = cls("Class /Script/UMG.WidgetTree", object)
    local actorC = cls("Class /Script/Engine.Actor", object)
    local function obj(c) local o = { live = true }; FAKE[o] = true; function o:GetClass() return c end; return o end
    local tree, notTree = obj(treeC), obj(actorC)
    local made = {}
    StaticConstructObject = function(c, outer, name) local w = { live = true, c = c, outer = outer, name = name }; made[#made + 1] = w; return w end
    local p = PLUGINS.kinds.coopk
    local w, why = asAddon("coopk", SVP.widget, text, tree, "EXC_Line_1")
    check(w ~= nil and made[1] and made[1].c == text and made[1].outer == tree and tostring(made[1].name):match("^SVA_c_coop_EXC_Line_1_%d+$"),
        "SVP.widget: a widget class in a widget tree, made by StaticConstructObject, its name its own (" .. tostring(made[1] and made[1].name or why) .. ")")
    asAddon("coopk", SVP.widget, text, tree, "EXC_Line_1")
    check(#made == 2 and made[2].name ~= made[1].name, "the same name asked again: another name (never one already in the outer)")
    local userC = cls("Class /Script/UMG.UserWidget", widget)
    local bp = cls("WidgetBlueprintGeneratedClass /Game/UI/WBP_Line.WBP_Line_C", userC)
    local r0 = { asAddon("coopk", SVP.widget, widget, tree, "A1"), asAddon("coopk", SVP.widget, userC, tree, "A2") }
    local okBP = asAddon("coopk", SVP.widget, bp, tree, "B1")
    check(r0[1] == nil and r0[2] == nil and okBP ~= nil, "UMG's abstract classes (Widget, UserWidget) refused; a widget blueprint's class made")
    for i = #made, 2, -1 do made[i] = nil end
    PLUGINS.kinds.coopk.widgets = 1
    local n0 = #made
    local r = { asAddon("coopk", SVP.widget, actorC, tree, "A"), asAddon("coopk", SVP.widget, text, notTree, "B"),
        asAddon("coopk", SVP.widget, { live = true }, tree, "C"), asAddon("coopk", SVP.widget, text, tree, "bad name!"),
        asAddon("coopk", SVP.widget, text, tree, 7) }
    check(#made == n0 and r[1] == nil and r[2] == nil and r[3] == nil and r[4] == nil and r[5] == nil,
        "refused: a class that isn't a widget's, an outer that isn't a widget tree, a table of the add-on's, a bad name")
    held = "a level is loading"
    local h = asAddon("coopk", SVP.widget, text, tree, "H")
    held = nil
    local coop0 = COOP; COOP = { open = true }
    local c = asAddon("coopk", SVP.widget, text, tree, "C2")
    COOP = coop0
    check(h == nil and c == nil and #made == n0, "refused while the walks are held and while co-op is open")
    for i = 1, 300 do asAddon("coopk", SVP.widget, text, tree, "W" .. i) end
    check(p.widgets == 256 and #made == n0 + 255 and said("SVP.widget: 256 this level"), "256 an add-on a level, said once")
    PLUGINS.level = PLUGINS.level + 1
    local again = asAddon("coopk", SVP.widget, text, tree, "Next")
    PLUGINS.level = PLUGINS.level - 1
    check(again ~= nil, "the count starts again in the next level")
    StaticConstructObject = nil
end)

part("small things", function()
    local kc, kd = SPC.kinds.coopk, SPC.kinds.tdrop
    D = { round = 1, now = 0 }; PLUGINS.tick()
    kc.spawn(1)
    PLUGINS.kinds.tdrop.off = nil
    -- (owners by address and name: another add-on's own handle of the same object)
    local mine = asAddon("coopk", SVP.spawn, "/Game/X/BP_Thing.BP_Thing_C", { X = 0, Y = 0, Z = 0 }, 0)
    local twin = actor("BP_Twin_C")
    twin.addr, twin.full = mine.addr, mine.full
    check(asAddon("tdrop", SVP.despawn, twin) == false and asAddon("tdrop", SVP.move, twin, { X = 1, Y = 1, Z = 1 }) == false
        and twin.HealthInternal == 100 and twin.at == nil, "another add-on's actor through a handle of its own (same address, same name): refused")
    -- (retire: targets kept until the death is dealt)
    local inv = actor("BP_Inv2_C"); inv.invincible = true
    local id = asAddon("coopk", SVP.target, inv, { pay = 10 })
    check(asAddon("coopk", SVP.retire, inv) == false and asAddon("coopk", SVP.alive, id) == true and PLUGINS.owned(rec(inv)),
        "a target the game won't let die: SVP.retire false, still a target, its mark kept")
    -- (metatable opts said)
    asAddon("coopk", SVP.target, actor("BP_MetaOpts_C"), setmetatable({}, { __index = { pay = 5 } }))
    check(said("its opts have a metatable"), "SVP.target opts with a metatable: said (only their own fields are read)")
    -- (name reads: one a call)
    local a = actor("BP_Reads_C")
    local r0 = a.reads
    asAddon("coopk", SVP.target, a, {})
    local r1 = a.reads
    asAddon("coopk", function() SVP.move(a, { X = 1, Y = 1, Z = 1 }); SVP.move(a, { X = 2, Y = 2, Z = 2 }) end)
    check(r1 - r0 == 1 and a.reads - r1 == 1, "the full name read once a call: SVP.target 1 (" .. (r1 - r0) .. "), two SVP.move 1 (" .. (a.reads - r1) .. ")")
    -- (the player's plane by its class)
    local pp = actor("BP_PlayerPlane_C"); pp.player = true
    check(asAddon("coopk", SVP.retire, pp) == false and asAddon("coopk", SVP.despawn, pp) == false and pp.HealthInternal == 100,
        "a player plane (its class), not the PC's pawn: never retired or despawned")
    -- (fx: the add-on's floats copied raw)
    local fl = setmetatable({ a = 1 }, { __pairs = function(t) FX_PAIRS = true; return next, t, nil end })
    local n0 = NIAGARA.spawned
    asAddon("coopk", SVP.fx, "/Game/X/F.F", { X = 0, Y = 0, Z = 0 }, 1, 0, fl)
    check(NIAGARA.spawned == n0 + 1 and FX_PAIRS == nil, "SVP.fx: its floats copied raw (no __pairs of the add-on's run)")
    -- (the HUD's cap isn't renewed)
    fakeClock = fakeClock + 61; PLUGINS.tick()
    local h0 = #holds
    check(asAddon("coopk", SVP.hud, false, "cap") == true, "(hidden)")
    fakeClock = fakeClock + 61; PLUGINS.tick()
    check(asAddon("coopk", SVP.hud, false, "again") == false and #holds == h0 + 2 and said("refused for 60 s"),
        "hidden again right after the API's 60 s give-back: refused (the cap isn't renewed), said")
    fakeClock = fakeClock + 61
    check(asAddon("coopk", SVP.hud, false, "later") == true, "60 s on: it may hide again")
    asAddon("coopk", SVP.hud, true)
    -- (a soft going sign that lets go: nothing one-way done)
    local t = actor("BP_Soft_C")
    local tid = asAddon("coopk", SVP.target, t, {})
    LEAVE = { hard = false }
    going = true; PLUGINS.tick(); going = false; PLUGINS.tick()
    check(PLUGINS.owned(rec(t)) and asAddon("coopk", SVP.alive, tid) == true and asAddon("coopk", SVP.hurt, t, 1, nil) == true,
        "a soft going sign that lets go again (LEAVE.hard false): its targets, marks and handles as they were")
    LEAVE = nil
    kc.over(2, nil)
    -- (only the kind whose round was on is aborted)
    local two = ENV("k_two")
    SPC.kinds.two1.spawn(3)
    D = nil; PLUGINS.tick()
    check(table.concat(two.ABORTS, ",") == "two1", "a run ended under one kind's round: that kind's abort only (" .. table.concat(two.ABORTS, ",") .. ")")
    check(said("addons.txt: a line left out"), "addons.txt: a line it can't use is said")
end)

-- (last of the review's parts: on a framework whose frames it unbalances, nothing after it can run)
part("a stop in a nested call's own lines", function()
    -- (a stop due the instruction after a nested guarded call's pcall returns: its frame popped all the same)
    local kw, ka = SPC.kinds.wwin, SPC.kinds.waft
    D = { round = 1, now = 0 }
    kw.spawn(1); ka.spawn(1)
    local wd0 = WD.fired
    watchdog(true, "the window")
    local okW, errW = pcall(kw.tick, 2, {})
    watchdog(false)
    check(okW and WD.fired == wd0, "a stop landing in a nested guarded call's own lines: nothing raised into Survival's call (" .. tostring(errW) .. ")")
    local stopped = false
    for _, l in ipairs(logs) do if l:find("plugin Window", 1, true) and l:find("runaway", 1, true) then stopped = true end end
    check(ENV("w_window").WINDOW_DONE == true and not stopped,
        "a stop due inside Survival's own code is put off to the add-on's lines: here the tick ended first, no runaway stop")
    local okA = pcall(ka.tick, 3, {})
    check(okA and ENV("w_after").AFTER_OK ~= nil and ka.ready(9, false) == true,
        "the frames balanced after it: another add-on's next call (300,000 steps) runs and stays on")
    kw.over(9, nil); ka.over(9, nil)
    D = nil; PLUGINS.tick()
end)

part("Survival unharmed after all of it", function()
    check(log == LOG and CFG == CFG0 and string.format == realFormat and math.randomseed == realSeed and type(SVP.pay) == "function"
        and type(PLUGINS.tick) == "function" and type(LB.stat) == "function" and SECRET == nil and MULTI_A == nil
        and ENV("q_globals").GOT ~= nil and ENV("q_lib").LIB ~= nil,
        "Survival's globals, libraries and API as they were")
end)

print("the hooks in Survival's own files (docs/ADDONS_MAINTAINING.md)")
-- (a refactor of main.lua / sv_main.lua / sv_stats.lua / sv_leaderboard.lua that drops one of these lines breaks every
-- add-on quietly: red here instead)
do
    local function file(n) return (readAll(MOD .. "/Scripts/" .. n):gsub("\r\n", "\n")) end
    -- the body of the function that starts at `head` (from it to the next line opening another top-level function)
    local function body(src, head)
        local i = src:find(head, 1, true)
        if not i then return nil end
        local j = src:find("\n[%w_ ]*function ", i + #head)
        return src:sub(i, j and j or #src)
    end
    local main = file("main.lua")
    local mods = (main:match("local MODULES = (%b{})") or ""):gsub("%-%-[^\n]*", "")   -- (its comments out)
    local list = {}
    for name in mods:gmatch('"([%w_]+)"') do list[#list + 1] = name end
    local fam, first = PARTS.family("sv_plugins"), nil   -- (sv_plugins.lua, then its pieces: tools/lua_split_part.py)
    for i, name in ipairs(list) do if name == "sv_plugins" then first = i end end
    local tail = first and table.concat(list, " ", first) or ""
    local want = (table.concat(fam, " "):gsub("%.lua", ""))
    check(tail == want, "main.lua: sv_plugins and its pieces are the last entries of MODULES (" .. tail .. ")")
    local svm = file("sv_main.lua")
    local tj = body(svm, "local function tickJob()") or ""
    local pB, pT = tj:find("probeTickB", 1, true), tj:find('timed("plugins", PLUGINS.tick)', 1, true)
    check(pB ~= nil and pT ~= nil and pB < pT, "sv_main.lua tickJob: timed(\"plugins\", PLUGINS.tick) after probeTickB")
    local ps = body(svm, "local function planeSweep(") or ""
    local pR, pD = ps:find("PLUGINS.owns(p)", 1, true), ps:find("elseif dead then", 1, true)
    check(pR ~= nil and pD ~= nil and pR < pD, "sv_main.lua planeSweep: the PLUGINS.owns branch before `elseif dead`")
    local pO, pT = ps:find("PLUGINS.owned(p)", 1, true), ps:find("pcall(enemyTier", 1, true)
    check(pO ~= nil and pT ~= nil and pO < pT and ps:find("elseif up then", pO, true) ~= nil,
        "sv_main.lua planeSweep: an add-on's live target (PLUGINS.owned) skips the up branch (tiers, manoeuvres, spike, stats)")
    local tt = body(file("sv_stats.lua"), "function STATS.tailTick(") or ""
    local tO, tC = tt:find("PLUGINS.owned(p)", 1, true), tt:find("cand[#cand + 1] = p", 1, true)
    check(tO ~= nil and tC ~= nil and tO < tC, "sv_stats.lua STATS.tailTick: an add-on's target isn't watched")
    local le = body(file("sv_leaderboard.lua"), "function LB.edited(") or ""
    check(le:find("PLUGINS.loaded", 1, true) ~= nil and le:find('out%[[^%]]*%]%s*=%s*"plugin "') ~= nil,
        "sv_leaderboard.lua LB.edited: every add-on found listed (\"plugin <name>\"), so its run isn't ranked")
end

print(fails == 0 and "plugins_test: all passed" or ("plugins_test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
