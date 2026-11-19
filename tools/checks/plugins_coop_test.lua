-- plugins_coop_test.lua <mod dir> (run by tools/checks/plugins_coop_test.sh): the add-on API's co-op (API 2.1,
-- Scripts/sv_plugins.lua and its pieces, docs/ADDONS.md "Co-op") with two to four games in one Lua: each game is the
-- API's pieces (parts.lua) loaded in its own environment with Survival's globals stubbed (COOP, sendTo, send, callout,
-- addCredits ...), its add-ons folders of Mods\\AC8SurvivalAddons loaded at its first PLUGINS.tick, each add-on in the
-- environment the API makes it (an add-on's globals: G.aenv / G.addon[folder].env), the games joined by a star network
-- as Survival's link is (the host slot 0; a joiner's sends go to the host). A game "without the API" loads no
-- sv_plugins.lua. Survival's own receive loop is simulated (what reaches its dispatch).
-- Checks: solo unchanged; having an add-on installed is the opt-in: the add-on lists (folder, version, files' hash)
-- compared as a joiner links, every difference (missing, extra, another version, other files) refusing the join on both
-- games before its run's picture is asked, matched add-ons running in co-op; the host's word (start, beats, over,
-- abort, a late joiner); host-only calls and the joiner's spawns; SVP.net and its limits; a switch-off (an error, a
-- desync) on every game, Survival's co-op going on.
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return (s:gsub("\r\n", "\n")) end
local PARTS = dofile("parts.lua")(MOD, readAll)       -- (the API as main.lua runs it: its pieces in order)

local ADDON = [[
X = { rem = {}, got = {}, joined = {} }
X.reg = { SVP.register("excalibur", {
    name = "Excalibur", ver = EXC_VER, api = "2.1",
    remote = {
        start = function(now, round) X.rem[#X.rem + 1] = "start:" .. tostring(round) end,
        over = function(now, result) X.rem[#X.rem + 1] = "over:" .. tostring(result) end,
        abort = function(why) X.rem[#X.rem + 1] = "abort:" .. tostring(why) end,
        tick = function() if X.rboom then error("remote boom") end end,
    },
    joined = function(slot) X.joined[#X.joined + 1] = tostring(slot) end,
    kind = { spawn = function() return true end, busy = function() return true end },
}) }
SVP.net.on("hit", function(from, ...) X.got[#X.got + 1] = { from, ... } end)
SVP.every(function() X.ev = (X.ev or 0) + 1; if X.boom then error("boom") end end)
]]
local BEACON = [[B = { rem = {} }
B.reg = SVP.register("beacon", { name = "Beacon", ver = "1", api = "2.0",
    remote = { start = function(now, round) B.rem[#B.rem + 1] = "start:" .. tostring(round) end },
    kind = { spawn = function() return true end, busy = function() return true end } })
SVP.every(function() B.ev = (B.ev or 0) + 1 end)]]
local function exc(v, extra) return 'EXC_VER = "' .. (v or "0.5") .. '"\n' .. ADDON .. (extra or "") end

local net = { games = {}, drop = {} }
local clock = 0
local function last(t) return t[#t] end

-- one game: its own globals (env), its plugins folder as IterateGameDirectories gives it
local function game(slot, plugins, fs)
    local G = { slot = slot, inbox = {}, sent = {}, logs = {}, callouts = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.load = function(s, n, m, e) return load(s, n, m, e or env) end    -- (an add-on loads into this game, not _G)
    env.os = setmetatable({ clock = function() return clock end }, { __index = os })
    env.log = function(s) G.logs[#G.logs + 1] = s end
    env.crumb = function() end
    env.CFG = { specials = { rotation = { "shuttle" } } }
    env.CFG_DEFAULTS = { specials = { rotation = { "shuttle" } } }
    env.SPC = { kinds = {} }
    env.AIRFIELD = { X = 0, Y = 0 }
    env.D = { round = 9, now = 100 }
    env.TIER = { pay = function(b) return b, 1 end, specialX = function() return 1 end, index = function() return 1 end }
    env.LB = { stat = function() end }
    env.playerLocation = function() return { X = 1, Y = 2, Z = 3 } end
    env.hudCallout = function() end
    env.callout = function(text, sub) G.callouts[#G.callouts + 1] = tostring(text) .. " | " .. tostring(sub) end
    env.levelGoing = function() return G.going == true end
    env.SV_PlayBGM = function() return 1 end
    env.DEAD = {}
    env.valid = function(o) return type(o) == "table" and not env.DEAD[o] end
    env.liveObj, env.liveAddr = env.valid, env.valid
    env.addrOf = function(o) return type(o) == "table" and o.addr or nil end
    env.planes, env.pending, env.TRACK, env.BIND = {}, {}, {}, {}
    env.SV_CoopTrack = function(id, o) env.TRACK[id] = o ~= 0 and o or nil; return 1 end
    env.SV_CoopBind = function(id, o)
        if o == 0 then env.BIND[id] = nil; return 0 end
        if not (type(o) == "table" and o.drivable) then return -1 end
        env.BIND[id] = o; return 1
    end
    env.playerName = function(s) return "P" .. s end
    env.loadObject = function() return nil, "(the test: no objects)" end
    env.PAID = {}
    env.COOP = { open = false, M = { mirror = 0, peers = {}, roster = {} } }
    local C = env.COOP
    function C.host() return C.open and C.role == "host" end
    function C.client() return C.open and C.role == "join" end
    function C.refuseJoin(why)
        G.refused, G.evAtRefuse = why, env.X and env.X.ev or 0
        C.open, C.role, C.slot = false, nil, nil
    end   -- (sv_coop_migration.lua's)
    function C.slots()                                       -- (sv_coop.lua's: you first, then the roster's)
        local out, me = { C.slot or 0 }, C.slot or 0
        if C.open then for s in pairs(C.M.roster) do if s ~= me then out[#out + 1] = s end end end
        table.sort(out, function(a, b) if a == me then return true elseif b == me then return false end return a < b end)
        return out
    end
    env.addCredits = function(n, why) env.PAID[#env.PAID + 1] = { n = n, why = why, mirror = C.M.mirror } end
    env.SV_CoopSend = function(msg, rel, to)
        local targets = {}
        if slot ~= 0 then targets = { 0 } elseif to == -1 then for s in pairs(net.games) do if s ~= 0 then targets[#targets + 1] = s end end
        else targets = { to } end
        for _, t in ipairs(targets) do
            local g = net.games[t]
            if g and not net.drop[t] then g.inbox[#g.inbox + 1] = slot .. "|" .. msg end
        end
        G.sent[#G.sent + 1] = msg
        return C.open and 1 or 0
    end
    env.SV_CoopRecv = function() return table.remove(G.inbox, 1) end
    env.send = function(rel, ...) return env.sendTo(nil, rel, ...) end     -- (sv_coop.lua's)
    env.sendTo = function(to, reliable, ...)                 -- (sv_coop.lua's)
        if not C.open or type(env.SV_CoopSend) ~= "function" then return false end
        local parts = { ... }
        for i = 1, #parts do parts[i] = (tostring(parts[i] or ""):gsub("|", "/")) end
        return env.SV_CoopSend(table.concat(parts, "|"), reliable and 1 or 0, to or -1) > 0
    end
    G.war = {}                                               -- (what reaches Survival's own dispatch)
    function G.tick()
        for _ = 1, 600 do
            local m = env.SV_CoopRecv()                      -- (by name, as sv_coop_migration.lua's loop)
            if not m or m == "" then break end
            G.war[#G.war + 1] = m
        end
        if env.PLUGINS then env.PLUGINS.tick() end
    end
    function G.coop(role) C.open, C.role, C.slot = role ~= nil, role, role and slot or nil end
    function G.said(pat) for _, l in ipairs(G.logs) do if l:find(pat, 1, true) then return true end end return false end
    function G.saidEnd(pat) for _, l in ipairs(G.logs) do if l:sub(-#pat) == pat then return true end end return false end
    function G.saidEnd(pat) for _, l in ipairs(G.logs) do if l:sub(-#pat) == pat then return true end end return false end
    function G.shown(pat) for _, l in ipairs(G.callouts) do if l:find(pat, 1, true) then return true end end return false end
    function G.sentJn() for _, m in ipairs(G.sent) do if m == "jn" then return true end end return false end
    function G.count(pat) local n = 0; for _, l in ipairs(G.logs) do if l:find(pat, 1, true) then n = n + 1 end end return n end
    G.env = env
    net.games[slot] = G
    if plugins then
        local folders, all = {}, {}
        local tmp = os.tmpname()
        for folder, src in pairs(plugins) do
            local main, extra = src, {}
            if type(src) == "table" then main, extra = src.main, src.files or {} end
            local p = tmp .. "_g" .. slot .. "_" .. folder .. "_main.lua"
            local f = assert(io.open(p, "wb")); f:write(main); f:close()
            folders[folder] = { __files = { { __name = "main.lua", __absolute_path = p } } }
            all[#all + 1] = p
            for rel, bytes in pairs(extra) do                  -- (its other files: "<sub>/<name>" in a subfolder)
                local node, parts = folders[folder], {}
                for s in rel:gmatch("[^/]+") do parts[#parts + 1] = s end
                for i = 1, #parts - 1 do node[parts[i]] = node[parts[i]] or { __files = {} }; node = node[parts[i]] end
                local q = tmp .. "_g" .. slot .. "_" .. folder .. "_" .. rel:gsub("[/\\]", "_")
                local g = assert(io.open(q, "wb")); g:write(bytes); g:close()
                node.__files[#node.__files + 1] = { __name = parts[#parts], __absolute_path = q }
                all[#all + 1] = q
            end
        end
        env.SCRIPT_DIR = "x\\Game\\Binaries\\Win64\\ue4ss\\Mods\\AC8SurvivalMode\\Scripts\\"   -- (no drive letter: paths_check)
        env.IterateGameDirectories = function()
            return { Game = { Binaries = { Win64 = { ue4ss = { Mods = { AC8SurvivalMode = {}, AC8SurvivalAddons = folders } } } } } }
        end
        local pakTmp = {}
        for rel, bytes in pairs(fs or {}) do                   -- (files under Mods: a declared container's)
            local q = tmp .. "_g" .. slot .. "_pak_" .. rel:gsub("[/\\]", "_")
            local g = assert(io.open(q, "wb")); g:write(bytes); g:close()
            pakTmp[("..\\" .. rel:gsub("/", "\\")):lower()] = q
            all[#all + 1] = q
        end
        env.io = setmetatable({ open = function(p, m)       -- (AC8SurvivalAddons there: a folder fails fopen with EACCES)
            if type(p) == "string" and p:match("AC8SurvivalAddons$") then return nil, p .. ": stub", 13 end
            if type(p) == "string" then
                local tail = p:lower():match("ac8survivaladdons\\(%.%.\\.*)$")
                if tail then local q = pakTmp[tail]; if q then return io.open(q, m) end; return nil, p .. ": no such file", 2 end
            end
            return io.open(p, m)
        end }, { __index = io })
        for _, piece in ipairs(PARTS.sources("sv_plugins")) do assert(load(piece.src, "@" .. piece.name, "t", env))() end
        env.PLUGINS.tick()                                   -- (the add-ons load at Survival's first tick)
        for _, f in ipairs(all) do os.remove(f) end
        for _, p in ipairs(env.PLUGINS.loaded) do               -- (the add-on's own globals: its environment's)
            if p.folder == "excalibur" then G.aenv = p.env; env.X = p.env.X end
            G.addon = G.addon or {}
            G.addon[p.folder] = p
        end
    end
    return G
end
local function step(n, dt)
    for _ = 1, n or 1 do
        clock = clock + (dt or 0.5)
        for s = 0, 15 do if net.games[s] then net.games[s].tick() end end
    end
end
local function roster(...)
    for _, g in pairs(net.games) do
        g.env.COOP.M.roster = {}
        for _, s in ipairs({ ... }) do g.env.COOP.M.roster[s] = {} end
    end
end
local function as(g, code)                                -- (code run as the add-on: its environment, then the game's)
    local e = setmetatable({}, { __index = function(_, k) local v = g.aenv and g.aenv[k]; if v ~= nil then return v end return g.env[k] end,
                                 __newindex = g.env })
    g.env.PLUGINS.running = g.env.PLUGINS.kinds.excalibur
    local r = { load(code, "t", "t", e)() }
    g.env.PLUGINS.running = nil
    return table.unpack(r)
end

print("solo, and a host alone")
local H = game(0, { excalibur = exc(), beacon = BEACON })
local hk = H.env.SPC.kinds.excalibur
check(H.env.X.reg[1] == true and H.env.SVP.api.minor >= 1 and H.env.SVP.net.ready == true, "API 2.1: the add-on registers, SVP.net ready")
check(tostring(H.addon.excalibur.hash):match("^%x+$") and #tostring(H.addon.excalibur.hash) == 16, "each add-on's files hashed at its load")
step(2)
check(hk.ready(9, false) == true and #H.sent == 0, "solo: its round comes, nothing sent")
as(H, 'SVP.pay(100, "x")')
check(H.env.PAID[1].mirror == 0, "solo: SVP.pay is Survival's addCredits as before")
H.coop("odd"); local ev0 = H.env.X.ev or 0; step(2)
check((H.env.X.ev or 0) == ev0 and hk.ready(9, false) == false, "co-op open on a game neither host nor joiner: no job runs, no round")
H.coop("host"); ev0 = H.env.X.ev or 0; step(2)
check((H.env.X.ev or 0) > ev0 and hk.ready(9, false) == true, "a host alone: every add-on runs (installed = opted in), its round comes")

print("a joiner with the same add-ons")
local A = game(1, { excalibur = exc(), beacon = BEACON })
local ak = A.env.SPC.kinds.excalibur
A.coop("join"); roster(0, 1)
check(hk.ready(9, false) == false and H.env.PLUGINS.coopReady(H.addon.excalibur, "excalibur") == false, "before the joiner's list: no round")
local aev0 = A.env.X.ev or 0
A.tick()
check(A.env.PLUGINS.joinHeld() == true and (A.env.X.ev or 0) == aev0, "before the lists match: the joiner's picture held, its add-ons' jobs don't run")
step(3)
check(H.said("player 2 (P1) has the same add-ons (beacon 1, excalibur 0.5): they run in co-op")
    and A.said("the host has the same add-ons (beacon 1, excalibur 0.5): they run in co-op"), "lists matched: both games say so")
check(A.sentJn() and A.env.PLUGINS.joinHeld() == false and (A.env.X.ev or 0) > aev0, "matched: the held picture asked (jn), the joiner's add-ons run")
check(hk.ready(9, false) == true and ak.ready(9, false) == false, "the round comes on the host; a joiner never starts one")
local px = false
for _, m in ipairs(A.war) do if m:find("|px|", 1, true) then px = true end end
check(not px, "Survival's dispatch never sees an add-on's message")
A.inbox[#A.inbox + 1] = "0|rnd|9|fighting"; A.inbox[#A.inbox + 1] = "0|px|.|hb|excalibur|9"; A.inbox[#A.inbox + 1] = "0|cr|5|x"
A.tick()
check(A.war[#A.war - 1] == "0|rnd|9|fighting" and last(A.war) == "0|cr|5|x", "Survival's own messages pass in order around them")
local sp0, why0 = as(A, 'return SVP.spawn("/Game/x.x_C", { X = 0, Y = 0, Z = 0 })')
check(sp0 == nil and tostring(why0):find("spawns only in the host's round", 1, true) ~= nil, "a joiner's SVP.spawn outside the host's round: refused")
hk.spawn(100); step(1)
check(A.env.X.rem[1] == "start:9", "the host's round: the joiner's def.remote.start(9)")
local _, why1 = as(A, 'return SVP.spawn("/Game/x.x_C", { X = 0, Y = 0, Z = 0 })')
check(not tostring(why1):find("spawns only", 1, true), "inside the host's round: a joiner's local spawn not refused for being a joiner")
step(40)
check(#A.env.X.rem == 1, "beats keep it on for 20 s")
as(H, 'SVP.pay(1000, "core")')
check(last(H.env.PAID).mirror == 1 and H.env.COOP.M.mirror == 0, "the host's pay through Survival's co-op pay (M.mirror), put back")
local ok1 = as(H, 'return SVP.net.send("hit", 12, "a|b", true)'); step(1)
local g1 = A.env.X.got[1]
check(ok1 == true and g1 and g1[1] == 0 and g1[2] == "12" and g1[3] == "a/b" and g1[4] == "1", "SVP.net: host -> joiner, fields cleaned")
as(A, 'return SVP.net.send("hit", 7)'); step(1)
check(H.env.X.got[1] and H.env.X.got[1][1] == 1 and H.env.X.got[1][2] == "7", "SVP.net: joiner -> host")
check(as(H, 'return SVP.net.send("hit", string.rep("x", 201))') == false, "SVP.net: a field over 200 bytes refused")
check(as(H, 'return SVP.net.send("hit", string.rep("x", 150), string.rep("x", 150), string.rep("x", 150))') == false, "SVP.net: over 400 bytes refused")
check(as(A, 'return SVP.net.sendTo(0, "hit", 1)') == false, "SVP.net.sendTo is the host's")
local pe = as(H, "return SVP.net.peers()")
check(pe[1] and pe[1].slot == 1 and pe[1].same == true, "SVP.net.peers: the joiner, matched")
as(A, 'JT = SVP.target({}, {}); JK = SVP.kill(1); SVP.pay(5, "x")')
check(A.env.JT == nil and A.env.JK == false and #A.env.PAID == 0 and A.count("is the host's in co-op") == 3, "a joiner's target / kill / pay refused, said once each")
hk.over(200, { result = "won" }); step(1)
check(last(A.env.X.rem) == "over:won", "the host's round over: the joiner's def.remote.over")

print("mismatched add-ons: the join refused on both games")
local function tryJoin(slot, addons, label)
    local J = game(slot, addons)
    J.coop("join"); J.env.D = { round = 9, now = 100 }
    J.ev0 = J.env.X and J.env.X.ev or 0
    roster(0, 1, slot); J.tick()
    J.held = J.env.PLUGINS.joinHeld()                       -- (Survival's askPicture on a joiner in a run)
    step(3)
    return J
end
local cases = {
    { 2, { excalibur = exc() }, "beacon 1: on this game (the host), missing on player 3 (P2)", "BEACON 1: ON THE HOST, MISSING ON THIS GAME", "missing" },
    { 3, { excalibur = exc(), beacon = BEACON, extra = "SVP.log('x')" }, "extra _: on player 4 (P3), missing on this game (the host)", "EXTRA _: ON THIS GAME, MISSING ON THE HOST", "extra" },
    { 4, { excalibur = exc("0.4"), beacon = BEACON }, "excalibur: version 0.5 on this game (the host), 0.4 on player 5 (P4)", "EXCALIBUR: VERSION 0.4 ON THIS GAME, 0.5 ON THE HOST", "another version" },
    { 5, { excalibur = exc("0.5", "\n-- edited"), beacon = BEACON }, "excalibur 0.5: other files", "EXCALIBUR 0.5: OTHER FILES", "the same version, another .lua (its hash)" },
}
for _, c in ipairs(cases) do
    local J = tryJoin(c[1], c[2])
    local hostSays = H.said("player " .. (c[1] + 1) .. " (P" .. c[1] .. ") refused: mismatched add-ons: ") and H.said(c[3])
    check(hostSays and H.shown("REFUSED P" .. c[1] .. " | MISMATCHED ADD-ONS: "), c[5] .. ": the host refuses, the difference logged and shown")
    check(J.refused and J.refused:find("mismatched add-ons", 1, true) and J.env.COOP.open == false and J.shown("CO-OP: MISMATCHED ADD-ONS | " .. c[4]),
        c[5] .. ": the joiner's co-op closed (COOP.refuseJoin), the difference shown there")
    check(J.held == true and not J.sentJn() and J.evAtRefuse == J.ev0, c[5] .. ": the joiner's picture held and never asked, none of its add-ons ran in co-op")
    net.games[c[1]] = nil; roster(0, 1); step(1)
end
-- (every file it installs: the same .lua, an asset of another size in its folder, or a declared container's)
local function withAssets(snd, pak)
    return { main = exc(), files = { ["excalibur/radio.bnk"] = snd, ["paks.txt"] = "IoStoreLoaderMod/Excalibur/Exc_P.utoc\n" } }
end
do
    local saved = net.games
    net.games = {}
    local h = game(0, { excalibur = withAssets("12345678") }, { ["IoStoreLoaderMod/Excalibur/Exc_P.utoc"] = "abcd" })
    h.coop("host")
    local ok = game(1, { excalibur = withAssets("87654321") }, { ["IoStoreLoaderMod/Excalibur/Exc_P.utoc"] = "dcba" })
    ok.coop("join"); roster(0, 1); step(3)
    check(ok.refused == nil and ok.said("the host has the same add-ons"), "the same .lua and assets of the same sizes: matched (sizes, not bytes, for assets)")
    net.games[1] = nil
    local big = game(2, { excalibur = withAssets("123456789") }, { ["IoStoreLoaderMod/Excalibur/Exc_P.utoc"] = "abcd" })
    big.coop("join"); roster(0, 2); step(3)
    check(big.refused and big.shown("EXCALIBUR 0.5: OTHER FILES") and h.said("excalibur 0.5: other files"),
        "the same .lua, an asset in its folder of another size: refused, 'other files'")
    net.games[2] = nil
    local pk = game(3, { excalibur = withAssets("12345678") }, { ["IoStoreLoaderMod/Excalibur/Exc_P.utoc"] = "abcde" })
    pk.coop("join"); roster(0, 3); step(3)
    check(pk.refused and pk.shown("EXCALIBUR 0.5: OTHER FILES"), "the same folder, a container its paks.txt names of another size: refused, 'other files'")
    net.games[3] = nil
    local none = game(4, { excalibur = withAssets("12345678") }, {})
    none.coop("join"); roster(0, 4); step(3)
    check(none.refused and none.shown("OTHER FILES"), "a declared container missing: refused")
    net.games = saved
    roster(0, 1)
end
local J6 = game(6, { excalibur = exc() })
J6.coop("join"); roster(0, 1, 6); step(3)
check(hk.ready(10, false) == false and H.said("player 7 (P6) has mismatched add-ons (refused)"), "while a refused player is in the room: no add-on round (who, why)")
net.games[6] = nil; roster(0, 1); step(1)
check(hk.ready(10, false) == true, "they've gone: it comes again")

print("a joiner that never answers, a host that never answers")
local Bn = game(2, nil)                                    -- (no add-on API at all)
Bn.coop("join"); roster(0, 1, 2); step(30, 1.0)
local hq = 0
for _, m in ipairs(Bn.war) do if m:find("|px|.|hq", 1, true) then hq = hq + 1 end end
check(hq == 6 and H.count("hasn't answered the add-on check") == 1 and hk.ready(10, false) == false, "a game that never answers: asked 6 times, one line, no add-on round while it's in")
net.games[2] = nil; roster(0, 1); step(2)
do
    local saved = net.games
    net.games = {}
    local Q = game(1, { excalibur = exc() })
    Q.coop("join"); Q.env.D = { round = 1, now = 1 }
    step(65, 0.5)
    check(Q.refused and Q.said("the host never answered the add-on check (30 s)") and not Q.sentJn(), "a host that never answers: the join refused 30 s on, no picture asked")
    net.games = saved
end

print("a late joiner; a desync: off on every game")
do
    net.games = {}
    local h = game(0, { excalibur = exc(), beacon = BEACON })
    local a = game(1, { excalibur = exc(), beacon = BEACON })
    h.coop("host"); a.coop("join"); roster(0, 1); step(3)
    local k = h.env.SPC.kinds.excalibur
    h.env.D.round = 13
    check(k.ready(13, false) == true, "two matched games: it comes")
    k.spawn(300); step(1)
    local f = game(4, { excalibur = exc(), beacon = BEACON })
    f.coop("join"); roster(0, 1, 4); step(3)
    check(f.env.X.rem[1] == "start:13" and h.env.X.joined[1] == "4", "a player joining mid-round, matched: started there, def.joined(4)")
    net.drop[4] = true; step(36); net.drop[4] = nil; step(3)
    check(last(f.env.X.rem) == "abort:the host's round went quiet" and f.addon.excalibur.off == true
        and f.said("co-op desync: the host's excalibur round went quiet for 15 s"), "the host quiet 15 s on one joiner: its round aborted there, the add-on off there")
    check(h.addon.excalibur.off == true and h.said("switched off on player 5 (P4)'s game") and a.addon.excalibur.off == true
        and a.said("switched off on the host's game"), "the switch-off on every game: the host, and the other joiner through it")
    check(last(a.env.X.rem):find("^abort:") ~= nil and h.addon.beacon.off ~= true and a.addon.beacon.off ~= true, "the round aborted everywhere; the other add-on untouched")
    a.inbox[#a.inbox + 1] = "0|px|.|st|bad kind!|1"; a.inbox[#a.inbox + 1] = "0|px|.|st|excalibur|1e999"
    a.inbox[#a.inbox + 1] = "2|px|excalibur|hit|1"; a.inbox[#a.inbox + 1] = "0|px"; a.inbox[#a.inbox + 1] = "2|px|.|of|beacon|x"
    local nr = #a.env.X.rem
    a.tick()
    check(#a.env.X.rem == nr and not a.said("a message's error") and a.addon.beacon.off ~= true, "malformed messages and a non-host's (its switch-off too) refused, no error")
end

print("positions on Survival's own stream, a joiner's own planes")
do
    net.games = {}                                            -- (a fresh pair for this part)
    local h = game(0, { excalibur = exc() })
    local j = game(1, { excalibur = exc() })
    h.coop("host"); j.coop("join"); roster(0, 1); step(3)
    local function plane(a, name, drivable)
        return setmetatable({ addr = a, drivable = drivable ~= false }, { __index = { GetFullName = function() return name end } })
    end
    h.env.COOP.M.nextId = 41
    local hp = plane(0x1000, "LiveAIPlane /x.uavb_1")
    h.env.HP = hp
    local id = as(h, "return SVP.net.track(HP)")
    check(id == 42 and h.env.COOP.M.nextId == 42 and h.env.TRACK[42] == hp, "track (host): an id from Survival's counter, the plane on its stream")
    h.env.SPC.kinds.excalibur.spawn(10); step(1)
    local cp, other = plane(0x2000, "LiveAIPlane /x.copy1"), plane(0x3000, "LiveAIPlane /x.su30")
    j.env.pending[#j.env.pending + 1] = { obj = cp, age = 0 }
    j.env.planes[#j.env.planes + 1] = { obj = other, addr = 0x3000 }
    j.env.CP, j.env.GR = cp, plane(0x4000, "ground", false)
    local okF = as(j, "return SVP.net.follow(42, CP)")
    local okB = as(j, "return SVP.net.follow(43, GR)")
    check(okF == true and j.env.BIND[42] == cp and #j.env.pending == 0 and okB == false,
        "follow (joiner): its copy bound, out of Survival's new-plane list; not an AI plane: refused")
    j.env.planes[#j.env.planes + 1] = { obj = cp, addr = 0x2000 }; step(1)
    check(#j.env.planes == 1 and j.env.planes[1].addr == 0x3000, "an owned plane reaching Survival's plane list later: taken out, others stay")
    h.env.SPC.kinds.excalibur.over(20, nil); step(2)
    check(h.env.TRACK[42] == nil and j.env.BIND[42] == nil and next(j.env.PLUGINS.net.owned) == nil, "the round over: stream, bind and owned plane let go")
    local d = plane(0x5000, "LiveAIPlane /x.copy2")
    j.env.D2 = d; as(j, "return SVP.net.own(D2)"); j.env.DEAD[d] = true; step(3)
    j.env.planes[#j.env.planes + 1] = { obj = plane(0x5000, "LiveAIPlane /x.f16"), addr = 0x5000 }; step(1)
    check(next(j.env.PLUGINS.net.owned) == nil and #j.env.planes == 2, "an owned plane gone is let go: a new object at its address stays Survival's")
    local okS = as(h, 'return SVP.net.stream("pos", 1, 2, 3)')
    check(okS == true, "stream: an unreliable send")
end

-- SVP.players() (API 2.1): slot, X / Y / Z, a (the plane actor here), down (shot down, still listed), you first
do
    net.games = {}
    local h = game(0, { excalibur = exc() })
    h.coop("host")
    local e = h.env
    local pawn = { addr = 0xA0 }
    pawn.K2_GetActorLocation = function() return { X = 1, Y = 2, Z = 3 } end
    e.survivalPC = { Pawn = pawn }
    local st1 = { addr = 0xB1 }
    st1.K2_GetActorLocation = function() return { X = 10, Y = 20, Z = 30 } end
    local st2 = { addr = 0xB2 }
    st2.K2_GetActorLocation = function() return { X = 40, Y = 50, Z = 60 } end
    e.COOP.M.roster = { [1] = true, [2] = true, [3] = true }
    e.COOP.M.peers = { [1] = { obj = st1 }, [2] = { obj = st2, down = true }, [3] = { obj = { addr = 0xB3 } } }
    e.DEAD[e.COOP.M.peers[3].obj] = true
    local P = as(h, "return SVP.players()")
    check(type(P) == "table" and #P == 3 and P[1].slot == 0 and P[1].a == pawn and P[1].down == false
        and P[1].X == 1 and P[1].Z == 3, "players: you first, your pawn as a, not down")
    check(P[2] and P[2].slot == 1 and P[2].a == st1 and P[2].down == false and P[2].X == 10 and P[2].Y == 20,
        "players: a joiner with its stand-in as a and its position")
    check(P[3] and P[3].slot == 2 and P[3].a == st2 and P[3].down == true, "players: a shot-down joiner stays listed, down = true")
    e.DOWN = { me = function() return true end }
    local P2 = as(h, "return SVP.players()")
    check(P2[1].down == true, "players: you shot down: down = true (Survival's DOWN.me)")
    e.survivalPC = nil
    local P3 = as(h, "return SVP.players()")
    check(P3[1] and P3[1].a == nil and P3[1].X == 1, "players: no pawn: a = nil, the position still there")
end
print("failure contained: an error in co-op, off on every game, Survival's co-op going on")
do
    net.games = {}
    local both = function() return { excalibur = exc(), beacon = BEACON } end
    local h, j1, j2 = game(0, both()), game(1, both()), game(2, both())
    h.coop("host"); j1.coop("join"); j2.coop("join"); roster(0, 1, 2); step(3)
    local ek, bk = h.env.SPC.kinds.excalibur, h.env.SPC.kinds.beacon
    check(ek.ready(9, false) == true and bk.ready(9, false) == true, "three matched games, two add-ons: both rounds may come")
    ek.spawn(100); step(1)
    j1.aenv.X.rboom = true; step(3)
    check(j1.addon.excalibur.off == true and j1.said("remote.tick error"), "a joiner's def.remote error: the add-on off there")
    check(h.addon.excalibur.off == true and h.said("switched off on player 2 (P1)'s game") and j2.addon.excalibur.off == true,
        "and on the host and the other joiner (the same add-ons everywhere)")
    check(last(j2.env.X.rem) == "abort:the host's add-on was switched off", "the host's round of it ended, every joiner's aborted, told why")
    check(ek.ready(10, false) == false and bk.ready(10, false) == true, "it never comes again this session; the other add-on's round does")
    j2.inbox[#j2.inbox + 1] = "0|rnd|10|fighting"
    bk.spawn(140)
    local okT = pcall(step, 2)
    j2.inbox[#j2.inbox + 1] = "0|cr|5|x"; step(1)
    local rnd, cr = false, false
    for _, m in ipairs(j2.war) do if m == "0|rnd|10|fighting" then rnd = true elseif m == "0|cr|5|x" then cr = true end end
    check(okT and rnd and cr and h.env.COOP.open and j1.env.COOP.open and j2.env.COOP.open,
        "Survival's own co-op goes on: its messages still reach its dispatch, the room open on every game")
    check(last(j1.addon.beacon.env.B.rem) == "start:9" and last(j2.addon.beacon.env.B.rem) == "start:9", "the other add-on's round runs on both joiners")
    -- (the host's own error: the same, from the host)
    net.games = {}
    h, j1 = game(0, both()), game(1, both())
    h.coop("host"); j1.coop("join"); roster(0, 1); step(3)
    h.env.SPC.kinds.excalibur.spawn(100); step(1)
    h.aenv.X.boom = true; step(2)
    check(h.addon.excalibur.off == true and j1.addon.excalibur.off == true and last(j1.env.X.rem) == "abort:the host's add-on was switched off"
        and j1.said("switched off on the host's game"), "the host's add-on errors mid-round: off on the host and the joiner, its round aborted there")
end
print("the hooks in Survival's co-op files (docs/ADDONS_MAINTAINING.md)")
do
    local mig = readAll(MOD .. "/Scripts/sv_coop_migration.lua")
    local raw = 0
    for line in mig:gmatch("[^\n]+") do if line:find('send(true, "jn")', 1, true) then raw = raw + 1 end end
    check(raw == 1 and mig:find("PLUGINS.joinHeld()", 1, true) and select(2, mig:gsub("askPicture%(%)", "")) >= 3,
        "sv_coop_migration.lua: every \"jn\" through askPicture, which asks PLUGINS.joinHeld first")
    check(mig:find("function COOP.refuseJoin(why) closeCoop(", 1, true) ~= nil, "sv_coop_migration.lua: COOP.refuseJoin closes co-op")
end
print(fails == 0 and "plugins_coop_test: all passed" or ("plugins_coop_test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
