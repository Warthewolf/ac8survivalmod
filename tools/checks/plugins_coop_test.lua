-- plugins_coop_test.lua <mod dir> (run by tools/checks/plugins_coop_test.sh): the add-on API's co-op (API 2.1,
-- Scripts/sv_plugins.lua and its pieces, docs/ADDONS.md "Co-op") with two to four games in one Lua: each game is the
-- API's pieces (parts.lua) loaded in its own environment with Survival's globals stubbed (COOP, sendTo, addCredits
-- ...), its add-ons folders of Mods\AC8SurvivalAddons loaded at its first PLUGINS.tick, each add-on in the environment
-- the API makes it (an add-on's globals: G.aenv), the games joined by a star
-- network as Survival's link is (the host slot 0; a joiner's sends go to the host). A game "without the API" loads no
-- sv_plugins.lua: a friend on a Survival without add-ons. Survival's own receive loop is simulated (what reaches its
-- dispatch). Checks: solo unchanged; the add-on lists; the round only when every player has the add-on at its version;
-- the host's word (start, beats, over, abort, a late joiner, quiet); host-only calls on a joiner; SVP.net and its limits.
local MOD = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return (s:gsub("\r\n", "\n")) end
local PARTS = dofile("parts.lua")(MOD, readAll)       -- (the API as main.lua runs it: its pieces in order)

local ADDON = [[
X = { rem = {}, got = {}, joined = {} }
X.reg = { SVP.register("excalibur", {
    name = "Excalibur", ver = EXC_VER, api = "2.1", coop = true,
    remote = {
        start = function(now, round) X.rem[#X.rem + 1] = "start:" .. tostring(round) end,
        over = function(now, result) X.rem[#X.rem + 1] = "over:" .. tostring(result) end,
        abort = function(why) X.rem[#X.rem + 1] = "abort:" .. tostring(why) end,
    },
    joined = function(slot, has) X.joined[#X.joined + 1] = slot .. ":" .. tostring(has) end,
    kind = { spawn = function() return true end, busy = function() return true end },
}) }
SVP.net.on("hit", function(from, ...) X.got[#X.got + 1] = { from, ... } end)
SVP.every(function() X.ev = (X.ev or 0) + 1 end)
]]
local SOLO20 = [[S20 = { SVP.register("solok", { name = "Solo", api = "2.0", kind = { spawn = function() return true end } }) }
SVP.every(function() EVN = (EVN or 0) + 1 end)]]

local net = { games = {}, drop = {} }
local clock = 0
local function last(t) return t[#t] end

-- one game: its own globals (env), its plugins folder as IterateGameDirectories gives it
local function game(slot, plugins)
    local G = { slot = slot, inbox = {}, sent = {}, logs = {} }
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
    env.PAID = {}
    env.COOP = { open = false, M = { mirror = 0, peers = {}, roster = {} } }
    local C = env.COOP
    function C.host() return C.open and C.role == "host" end
    function C.client() return C.open and C.role == "join" end
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
    function G.count(pat) local n = 0; for _, l in ipairs(G.logs) do if l:find(pat, 1, true) then n = n + 1 end end return n end
    G.env = env
    net.games[slot] = G
    if plugins then
        local folders, all = {}, {}
        local tmp = os.tmpname()
        for folder, src in pairs(plugins) do
            local p = tmp .. "_g" .. slot .. "_" .. folder .. "_main.lua"
            local f = assert(io.open(p, "wb")); f:write(src); f:close()
            folders[folder] = { __files = { { __name = "main.lua", __absolute_path = p } } }
            all[#all + 1] = p
        end
        env.SCRIPT_DIR = "x\\Game\\Binaries\\Win64\\ue4ss\\Mods\\AC8SurvivalMode\\Scripts\\"   -- (no drive letter: paths_check)
        env.IterateGameDirectories = function()
            return { Game = { Binaries = { Win64 = { ue4ss = { Mods = { AC8SurvivalMode = {}, AC8SurvivalAddons = folders } } } } } }
        end
        env.io = setmetatable({ open = function(p, m)       -- (AC8SurvivalAddons there: a folder fails fopen with EACCES)
            if type(p) == "string" and p:match("AC8SurvivalAddons$") then return nil, p .. ": stub", 13 end
            return io.open(p, m)
        end }, { __index = io })
        for _, piece in ipairs(PARTS.sources("sv_plugins")) do assert(load(piece.src, "@" .. piece.name, "t", env))() end
        env.PLUGINS.tick()                                   -- (the add-ons load at Survival's first tick)
        for _, f in ipairs(all) do os.remove(f) end
        for _, p in ipairs(env.PLUGINS.loaded) do               -- (the add-on's own globals: its environment's)
            if p.folder == "excalibur" then G.aenv = p.env; env.X = p.env.X end
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

print("solo, and the host alone")
local H = game(0, { excalibur = 'EXC_VER = "0.5"\n' .. ADDON, solok = SOLO20 })
local A = game(1, { excalibur = 'EXC_VER = "0.5"\n' .. ADDON })
local hk, ak = H.env.SPC.kinds.excalibur, A.env.SPC.kinds.excalibur
check(H.env.X.reg[1] == true and H.env.SVP.api.minor >= 1 and H.env.SVP.net.ready == true, "API 2.1: the co-op add-on registers, SVP.net ready")
step(2)
check(hk.ready(9, false) == true and #H.sent == 0, "solo: the co-op kind comes, nothing sent")
as(H, 'SVP.pay(100, "x")')
check(H.env.PAID[1].mirror == 0, "solo: SVP.pay is Survival's addCredits as before")
local function solo(g) for _, p in ipairs(g.env.PLUGINS.loaded) do if p.folder == "solok" then return p end end end
local sp = solo(H)
local ev0, evS0 = H.env.X.ev or 0, sp.env.EVN or 0
H.coop("host"); step(1)
local ev1, evS1 = H.env.X.ev or 0, sp.env.EVN or 0
step(2)
check((H.env.X.ev or 0) > ev1 and (sp.env.EVN or 0) == evS1 and evS1 >= evS0 and ev1 >= ev0,
    "co-op open: the co-op add-on's SVP.every runs, a 2.0 add-on's doesn't (2.0's rule)")
local prevR = H.env.PLUGINS.running
H.env.PLUGINS.running = sp
local okSolo = sp.env.SVP.callout("x")
H.env.PLUGINS.running = H.env.PLUGINS.kinds.excalibur
local okCoop = H.aenv.SVP.callout("x")
H.env.PLUGINS.running = prevR
check(okSolo == false and okCoop == true, "co-op open: a 2.0 add-on's call that changes the game refused, the co-op add-on's served")
check(hk.ready(9, false) == true, "co-op, the host alone: it comes")
check(H.env.SPC.kinds.solok.ready(9, false) == false and H.said("isn't made for co-op"), "co-op: a 2.0 kind doesn't (2.0's rule), said")

print("a joiner with the same add-on")
A.coop("join"); roster(0, 1)
check(hk.ready(9, false) == false, "before the joiner's list: not yet")
step(3)
check(hk.ready(9, false) == true and A.said("excalibur: its rounds come"), "lists exchanged: it comes; the joiner's log says so")
check(ak.ready(9, false) == false, "a joiner never starts a round itself")
local px = false
for _, m in ipairs(A.war) do if m:find("|px|", 1, true) then px = true end end
check(not px, "Survival's dispatch never sees an add-on's message")
A.inbox[#A.inbox + 1] = "0|rnd|9|fighting"; A.inbox[#A.inbox + 1] = "0|px|.|hb|excalibur|9"; A.inbox[#A.inbox + 1] = "0|cr|5|x"
A.tick()
check(A.war[#A.war - 1] == "0|rnd|9|fighting" and last(A.war) == "0|cr|5|x", "Survival's own messages pass in order around them")
hk.spawn(100); step(1)
check(A.env.X.rem[1] == "start:9", "the host's round: the joiner's remote.start(9)")
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
as(A, 'JT = SVP.target({}, {}); JK = SVP.kill(1); SVP.pay(5, "x")')
check(A.env.JT == nil and A.env.JK == false and #A.env.PAID == 0 and A.count("is the host's in co-op") == 3, "a joiner's target / kill / pay refused, said once each")

print("players without it")
local B = game(2, nil)                                     -- (no add-on API at all)
B.coop("join"); roster(0, 1, 2); step(30, 1.0)
local hq = 0
for _, m in ipairs(B.war) do if m:find("|px|.|hq", 1, true) then hq = hq + 1 end end
check(hq == 6 and H.count("hasn't answered") == 1, "a game without the API: asked 6 times, one line; its Survival drops the tag")
check(hk.ready(10, false) == false and H.said("player 3 (P2) hasn't said which add-ons"), "with them in the room the next round doesn't come (who, why)")
hk.over(200, { result = "won" }); step(1)
check(last(A.env.X.rem) == "over:won", "the host's round over: the joiner's remote.over")
net.games[2] = nil; roster(0, 1); step(2)
local V = game(3, { excalibur = 'EXC_VER = "0.4"\n' .. ADDON })
V.coop("join"); roster(0, 1, 3); step(4)
check(hk.ready(11, false) == false and H.said("player 4 (P3) has version 0.4, this game 0.5"), "another version: it doesn't come (versions said)")
net.games[3] = nil
local E = game(3, {})
E.coop("join"); roster(0, 1, 3); step(4)
check(hk.ready(12, false) == false and H.said("player 4 (P3) hasn't got it"), "the API but not the add-on: it doesn't come")
net.games[3] = nil; roster(0, 1); step(2)

print("a late joiner, a quiet host, the run's end")
H.env.D.round = 13
check(hk.ready(13, false) == true, "back to two: it comes")
hk.spawn(300); step(1)
local F = game(4, { excalibur = 'EXC_VER = "0.5"\n' .. ADDON })
F.coop("join"); roster(0, 1, 4); step(3)
check(F.env.X.rem[1] == "start:13" and H.env.X.joined[1] == "4:true", "a player with it joining mid-round: started there, def.joined(4, true)")
net.drop[4] = true; step(36)
check(last(F.env.X.rem) == "abort:the host's round went quiet", "the host quiet for 15 s: the joiner's round aborted")
net.drop[4] = nil
H.env.D = { round = 1, now = 1 }; step(2)
check(last(A.env.X.rem):find("^abort:") ~= nil, "the host's run ended under its round: the joiner's remote.abort")
A.going = true; step(1); A.going = false
A.inbox[#A.inbox + 1] = "0|px|.|st|bad kind!|1"; A.inbox[#A.inbox + 1] = "0|px|.|st|excalibur|1e999"
A.inbox[#A.inbox + 1] = "2|px|excalibur|hit|1"; A.inbox[#A.inbox + 1] = "0|px"
local nr, ng = #A.env.X.rem, #A.env.X.got
A.tick()
check(#A.env.X.rem == nr and #A.env.X.got == ng and not A.said("a message's error"), "malformed messages and a non-host's refused, no error")

print("positions on Survival's own stream, a joiner's own planes")
do
    net.games = {}                                            -- (a fresh pair for this part)
    local h = game(0, { excalibur = 'EXC_VER = "0.5"\n' .. ADDON })
    local j = game(1, { excalibur = 'EXC_VER = "0.5"\n' .. ADDON })
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
    local h = game(0, { "excalibur" })
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
print(fails == 0 and "plugins_coop_test: all passed" or ("plugins_coop_test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
