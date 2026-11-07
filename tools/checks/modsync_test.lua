-- modsync_test.lua <mod dir> <work dir> (run by tools/checks/modsync_test.sh): 0.73.80, the other players' modded planes
-- and skins (the user, 2026-11-04: "if players have mods installed but someone doesn't, that one person who doesn't have
-- the mods sees [the stock version], but if they were to have the mods, they would see the changes"; "planes and skins
-- first"), on the real sv_config.lua and sv_coop.lua (M exposed), the game and the runtime stubbed:
--   the sender: a stock plane's hi / pi as before (no new field); a modded plane's class path and stock base as new last
--     fields (hi 10-11, pi 11-12 after the Steam ID, older fields where they were), its base from its class's parents,
--     from its DT_LiveAircraft row's OriginalPlaneStringID (by its id or by a walk of the rows), from [coop.real_fallback],
--     or none; logged once; a path that can't be sent left out; the path dropped from a message that would be cut;
--   the receiver: a modded plane installed here (their class, loadout and paint); not installed (their base, its own
--     weapons and paint; not loaded again); their base no stock code here ([coop.real_fallback]); [coop.real_paths]
--     after their path; invalid paths (not /Game/, "..", too long, no player plane's name, another code) never loaded; a
--     path that loads a class that isn't a player plane rejected; [coop] real_default and the AI stand-in last; a joiner's
--     pi with and without the new fields;
--   skins: DT_Skin found at the main menu (by a walk; by a path), keyed by the skin id or by SkinID; an installed skin
--     kept, an unknown one -1 with the emblems kept, said once a player and skin; the information manager's SkinDataMap_;
--     a source with none of the stock skins not used; neither: paints as sent, one log line; DecalMaterialRef never read;
--     a modded plane installed here has its skin checked, a fallback none;
--   what the others see: OTHERS SEE YOUR FALKEN (ADFX02 WITHOUT THE ADD-ON).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return (s:gsub("\r\n", "\n")) end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local clock = 100
os.clock = function() return clock end           -- luacheck: ignore

-- the game, stubbed
local logs, callouts = {}, {}
function log(s) logs[#logs + 1] = s end
VERSION = "0.73.80-modsync.test"
SCRIPT_DIR = WORK .. "/Scripts/"
KILL, LB = { side = function() end }, { send = function() end }
RUN = { credits = 1000, spent = 0, msg = {}, bought = {} }
SETUP = { startRound = function() return 1 end, specialsX = function() return 1 end }
function roundsTick() end
function airfieldTick() end
function bombTick() end
function logPlane() end
function hudCallout(t, sub) callouts[#callouts + 1] = tostring(t) .. " / " .. tostring(sub) end
function addCredits() end
function valid(o) return type(o) == "table" and not o.gone end
function liveObj(o) return valid(o) end
function walkBusy() return nil end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function inSurvival() return true end
function playerOnAirfield() return false end
function gamePaused() return false end
function NotifyOnNewObject() end
function cdo() return nil end
-- sv_core's own, as they are there
function dtCall(dt, method, ...)
    local args = { ... }
    local ok, r = pcall(function() return dt[method](dt, table.unpack(args)) end)
    if ok then return true, r end
    return false, r
end
function rowList(dt)
    local ok, names = dtCall(dt, "GetRowNames")
    if not ok or names == nil then return nil end
    local out = {}
    pcall(function()
        for _, n in ipairs(names) do
            local okS, str = pcall(function() return n:ToString() end)
            out[#out + 1] = okS and str or tostring(n)
        end
    end)
    return out
end
local function fname(s) return setmetatable({}, { __index = { ToString = function() return s end } }) end

-- objects: classes (a name, a parent), data tables (rows read through a proxy that counts soft references read)
local nextAddr = 1000
local softReads = 0
local function newAddr() nextAddr = nextAddr + 1; return nextAddr end
local PP_ROOT = { full = "Class /Script/Live.LivePlayerPlane", addr = newAddr() }
function PP_ROOT:GetFName() return fname("LivePlayerPlane") end
function PP_ROOT:GetSuperStruct() return nil end
local function class(path, super, notPP)
    local n = path:match("%.([%w_]+)$")
    local c = { full = "BlueprintGeneratedClass " .. path, addr = newAddr(), path = path, super = super, notPP = notPP }
    function c:GetFName() return fname(n) end
    function c:GetSuperStruct() return self.super end
    function c:IsChildOf(root)
        if root ~= PP_ROOT then return false end
        local s = self
        while s do if s == PP_ROOT then return true end; s = s.super end
        return not self.notPP
    end
    return c
end
local function row(fields)
    return setmetatable({}, { __index = function(_, k)
        if k == "DecalMaterialRef" or k == "Reference" or k == "AircraftThumbnail" then softReads = softReads + 1; error("soft reference read: " .. k) end
        return fields[k]
    end })
end
local function dataTable(name, path, rows, order)
    local t = { full = "DataTable " .. path, addr = newAddr(), rows = rows, order = order }
    function t:GetFName() return fname(name) end
    function t:GetRowNames() local o = {}; for i, nm in ipairs(self.order) do o[i] = fname(nm) end; return o end
    function t:FindRow(nm) local f = self.rows[nm]; return f and row(f) or nil end
    return t
end
local dataTables, findAllOfDT, staticObjs = {}, 0, {}
local ppList = {}
function FindAllOf(c)
    if c == "LivePlayerPlane" then return ppList end
    if c == "DataTable" then findAllOfDT = findAllOfDT + 1; return dataTables end
    return {}
end
function FindFirstOf() return nil end
function StaticFindObject(p)
    if p == "/Script/Live.LivePlayerPlane" then return PP_ROOT end
    return staticObjs[p]
end
-- loadObject: a class path loads a class unless the add-on isn't installed here (notInstalled), counted by path
local notInstalled, notPP, loads, classes = {}, {}, {}, {}
function loadObject(path)
    loads[path] = (loads[path] or 0) + 1
    if notInstalled[path] then return nil end
    local c = class(path, nil, notPP[path])
    classes[c.addr] = path
    return c
end
SV_ERR = {}
local gi = nil
function gameInstance() return gi end

local function plane(full)
    local o = { full = full, addr = newAddr(), X = 1000, Y = 2000, Z = 300000, HealthInternal = 1000 }
    function o:SetActorHiddenInGame(v) self.hidden = v end
    function o:SetActorEnableCollision(v) self.coll = v end
    function o:SetActorTickEnabled(v) self.tick = v end
    function o:K2_GetActorLocation() return { X = self.X, Y = self.Y, Z = self.Z } end
    function o:K2_SetActorLocation(v) self.X, self.Y, self.Z = v.X, v.Y, v.Z; return true end
    function o:K2_DestroyActor() self.destroyed = true end
    function o:SetIsInvincible() end
    return o
end
local pawn = plane("BP_PlayerPlane_PP0022_f16c_C_0")
local F16C_CLS = class("/Game/Blueprints/Vehicle/PLAYER/Plane/PP0022_f16c/BP_PlayerPlane_PP0022_f16c.BP_PlayerPlane_PP0022_f16c_C", PP_ROOT)
function pawn:GetClass() return self.cls end
pawn.cls = F16C_CLS
survivalPC = { Pawn = pawn, full = "PC" }

-- the runtime, stubbed
local native, sent, inbox, spawnArgs, seq = {}, {}, {}, {}, {}
local loadout, paint = "", ""
function SV_CoopSend(msg, rel, to) sent[#sent + 1] = (to or -1) .. ">" .. msg; return 1 end
function SV_CoopRecv() return table.remove(inbox, 1) or "" end
function SV_CoopInfo() return "open=1;mode=steam;state=linked;slot=0;players=2;max=24;me=0;cands=0;tele=1;peers=1/linked/40/10/Lil" end
function SV_CoopOpen() return 1 end
function SV_CoopClose() end
function SV_CoopMe() end
function SV_CoopReset() end
function SV_CoopTrack() return 1 end
function SV_CoopBind() return 1 end
function SV_CoopPeer() return 1 end
function SV_CoopSwapPP(a, b) native[a], native[b] = native[b], native[a]; return 1 end
function SV_CoopLoadout() return loadout end
function SV_CoopPaint() return paint end
function SV_CoopSpawnPP(pawnA, x, y, z, yaw, clsA, slot, lo, pt)
    spawnArgs[slot] = { lo = lo, pt = pt, cls = classes[clsA] }
    local d = (classes[clsA] or ""):match("Plane/([^/]+)/") or "PP0000_x"
    local o = plane("BP_PlayerPlane_" .. d .. "_C_" .. nextAddr)
    native[slot] = o
    ppList[#ppList + 1] = o
    seq[#seq + 1] = "spawnPP " .. slot .. " " .. d
    return o.addr
end
local peerState = {}
function SV_CoopPeerAt(slot) return peerState[slot] or "" end
function SV_Spawn(unit) seq[#seq + 1] = "spawn " .. unit; return 1 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_UnitAlive() return 0 end
function SV_Event() return 1 end
function SV_SetText() end
function SV_MenuSetting() return "" end
local menu = 0
function SV_MenuChoice() return menu end

PARTS.dofile("sv_config.lua")
PARTS.load("sv_coop.lua", "=sv_coop.lua", { { "\nlocal M = {", "\nM = {" } })   -- (its pieces too; M exposed)
local M = _G.M
CFG.coop.enabled = true
local function tick(dt) clock = clock + (dt or 0.25); M.nextInfo = 0; COOP.tick(0) end
local function line(part, from) for i = #logs, from or 1, -1 do if has(logs[i], part) then return logs[i] end end; return nil end
local function count(part, from) local n = 0; for i = from or 1, #logs do if has(logs[i], part) then n = n + 1 end end; return n end
local function fields(m)                         -- ("<to>>kind|f2|...": f[1] the kind)
    local f = {}
    for x in ((m or ""):gsub("^%-?%d+>", "") .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
    return f
end
local function lastSent(kind, from, pred)
    for i = #sent, from or 1, -1 do
        if sent[i]:match("^%-?%d+>" .. kind .. "|") and (not pred or pred(sent[i])) then return sent[i] end
    end
end
local FRESH = "500000,0,300000,0,90,0,1000,100,3,100"      -- (in the mission, alive, a tenth of a second old)
local LO1 = "11,12//1,2"
local FALKEN = "/Game/Blueprints/Vehicle/Player/Plane/PP9001_falken_L001/BP_PlayerPlane_PP9001_falken_L001.BP_PlayerPlane_PP9001_falken_L001_C"
local ADFX_CLS = class("/Game/Blueprints/Vehicle/PLAYER/Plane/PP0038_adfx02_L001/BP_PlayerPlane_PP0038_adfx02_L001.BP_PlayerPlane_PP0038_adfx02_L001_C", PP_ROOT)
local function hi(slot, row, code, lo, pt, ac, cls, base)
    local m = string.format("%d|hi|%s|0.32.24|%s|Lil|%s|%s|%s|%s", slot, VERSION, row, code, lo or "", pt or "", ac or "")
    if cls or base then m = m .. "|" .. (cls or "") .. "|" .. (base or "") end
    return m
end
local function join(slot, msg) inbox[#inbox + 1] = slot .. "|sys|joined"; inbox[#inbox + 1] = msg; peerState[slot] = FRESH; tick(); tick(4) end
local function leave(slot) inbox[#inbox + 1] = slot .. "|sys|left"; peerState[slot] = ""; tick() end
local function resetMine() M.myPlaneAt, M.baseOf = nil, {} end

---------------------------------------------------------------------------------------------------- the main menu: the tables
print("the main menu: the tables the plane and skin checks read")
local SKIN_ROWS = { ["5014001"] = { SkinID = 5014001, PlaneStringID = "PP0005_f22a" }, ["21002001"] = { SkinID = 21002001 },
                    ["910010007"] = { SkinID = 910010007, PlaneStringID = "PP9001_falken_L001" } }
local SKIN_ORDER = { "5014001", "21002001", "910010007" }
for i = 1, 6 do SKIN_ROWS[tostring(1000000 * i + 1001)] = { SkinID = 1000000 * i + 1001 }; SKIN_ORDER[#SKIN_ORDER + 1] = tostring(1000000 * i + 1001) end
SKIN_ROWS.FalkenSkin2, SKIN_ORDER[#SKIN_ORDER + 1] = { SkinID = 910010008 }, "FalkenSkin2"   -- (an add-on's row, named otherwise)
local skinDT = dataTable("DT_Skin", "/Game/Datatables/Hangar/DT_Skin.DT_Skin", SKIN_ROWS, SKIN_ORDER)
local AC_ROWS = { ["1"] = { PlaneID = 1, PlaneStringID = fname("PP0001_a10c_L001"), OriginalPlaneStringID = fname("None") },
                  ["910010"] = { PlaneID = 910010, PlaneStringID = fname("PP9001_falken_L001"), OriginalPlaneStringID = fname("PP0038_adfx02_L001") } }
local acDT = dataTable("DT_LiveAircraft", "/Game/Datatables/Hangar/DT_LiveAircraft.DT_LiveAircraft", AC_ROWS, { "1", "910010" })
dataTables = { dataTable("DT_NPC", "/Game/Datatables/AI/NPC/DT_NPC.DT_NPC", {}, {}), skinDT, acDT }
D = nil
local from = #logs + 1
menu = 16 + 3; tick()
check(COOP.host(), "hosting")
tick()
check(M.tbl.skin == skinDT and M.tbl.aircraft == acDT and findAllOfDT == 1, "no run: DT_Skin and DT_LiveAircraft found by one walk over the DataTables")
check(line("coop: the game's DT_Skin found: /Game/Datatables/Hangar/DT_Skin.DT_Skin", from) ~= nil
      and line("coop: the game's DT_LiveAircraft found: /Game/Datatables/Hangar/DT_LiveAircraft.DT_LiveAircraft", from) ~= nil, "... logged with their paths")
check(M.skin.keyed == "name" and M.skin.dtOk == true
      and line("coop: skins: DT_Skin /Game/Datatables/Hangar/DT_Skin.DT_Skin, 10 rows, keyed by the skin id: other players' skins are checked", from) ~= nil,
      "DT_Skin's rows keyed by the skin id, the stock skins in it: used (" .. tostring(line("coop: skins:", from)) .. ")")
tick(20)
check(findAllOfDT == 1, "found: not walked for again")
check(softReads == 0, "no soft reference read (DecalMaterialRef)")

---------------------------------------------------------------------------------------------------- the sender
print("the sender: your plane's class path and stock base")
D = { round = 5, state = "fighting", now = 100, startRound = 1, up = {}, flown = {} }
tick(); tick()
local pi0 = lastSent("pi", 1, function(m) return has(m, ">pi|0|") end)
check(pi0 and #fields(pi0) == 10 and fields(pi0)[6] == "f16c", "a stock F-16C: the host's pi as before, 10 fields, the Steam ID last (" .. tostring(pi0) .. ")")
check(count("coop: your plane f16c (/Game/Blueprints/Vehicle/PLAYER/Plane/PP0022_f16c/BP_PlayerPlane_PP0022_f16c.BP_PlayerPlane_PP0022_f16c_C): "
      .. "its stock base for players without it: f16c (stock)") == 1, "its line once: f16c (stock)")
local s0
-- (i) the Falken whose class's parent is the ADFX-02's
pawn.full = "BP_PlayerPlane_PP9001_falken_L001_C_0"
pawn.cls = class(FALKEN, ADFX_CLS)
pawn.PlaneTypeID = 910010
resetMine()
s0, from = #sent, #logs + 1
tick()
pi0 = lastSent("pi", s0 + 1, function(m) return has(m, ">pi|0|") end)
local f0 = fields(pi0)
check(pi0 and #f0 == 12 and f0[6] == "falken" and f0[10] == "" and f0[11] == FALKEN and f0[12] == "adfx02",
      "your Falken: pi carries its class path (11) and stock base (12) after the Steam ID, every field before where it was (" .. tostring(pi0) .. ")")
check(line("coop: your plane falken (" .. FALKEN .. "): its stock base for players without it: adfx02 (its blueprint's parent "
      .. "BP_PlayerPlane_PP0038_adfx02_L001_C)", from) ~= nil, "(i) its base from its class's parent, logged")
local n1 = count("coop: your plane falken", from)
tick(); tick()
check(count("coop: your plane falken", from) == n1 and M.roster[0].cls == FALKEN and M.roster[0].base == "adfx02", "... once; the host's roster entry keeps them")
-- as a joiner: hi 10 / 11
COOP.reopen("join", "test")
COOP.slot, M.state = 3, "linked"
s0 = #sent
M.myCode = nil
tick()
local h0 = lastSent("hi", s0 + 1)
local hf = fields(h0)
check(h0 and #hf == 11 and hf[2] == VERSION and hf[6] == "falken" and hf[10] == FALKEN and hf[11] == "adfx02",
      "a joiner's hi: its class path (10) and stock base (11) last (" .. tostring(h0) .. ")")
-- (ii) a parent that's no stock plane's: its DT_LiveAircraft row's OriginalPlaneStringID (by its id, then by a walk)
pawn.cls = class(FALKEN, class("/Game/Mods/Falken/BP_PlayerPlane_Base.BP_PlayerPlane_Base_C", PP_ROOT))
resetMine()
from = #logs + 1
local cp, bs = M.myPlane(nil, "falken")
check(cp == FALKEN and bs == "adfx02" and line("its stock base for players without it: adfx02 (its aircraft row's OriginalPlaneStringID PP0038_adfx02_L001)", from) ~= nil,
      "(ii) its base from its DT_LiveAircraft row (found by its PlaneTypeID)")
AC_ROWS.Falken, AC_ROWS["910010"] = AC_ROWS["910010"], nil
acDT.order = { "1", "Falken" }
pawn.PlaneTypeID = nil
resetMine()
from = #logs + 1
cp, bs = M.myPlane(nil, "falken")
check(bs == "adfx02" and line("(its aircraft row's OriginalPlaneStringID PP0038_adfx02_L001)", from) ~= nil, "... a row named otherwise: found by its PlaneStringID")
check(softReads == 0, "the row's Reference never read")
-- (iii) no aircraft table: this game's [coop.real_fallback]
local keepAc = M.tbl.aircraft
M.tbl.aircraft = nil
resetMine()
from = #logs + 1
cp, bs = M.myPlane(nil, "falken")
check(bs == "adfx02" and line("its stock base for players without it: adfx02 ([coop.real_fallback])", from) ~= nil, "(iii) [coop.real_fallback]")
pawn.full = "BP_PlayerPlane_PP9002_mystery_C_0"
pawn.cls = class("/Game/Mods/Mystery/BP_PlayerPlane_PP9002_mystery.BP_PlayerPlane_PP9002_mystery_C", PP_ROOT)
resetMine()
from = #logs + 1
cp, bs = M.myPlane(nil, "mystery")
check(cp == "/Game/Mods/Mystery/BP_PlayerPlane_PP9002_mystery.BP_PlayerPlane_PP9002_mystery_C" and bs == ""
      and line("its stock base for players without it: none (none found", from) ~= nil, "none of them: no base (its path still sent)")
-- a path that can't be sent: left out (its base kept)
pawn.full = "BP_PlayerPlane_PP9001_falken_L001_C_0"
pawn.cls = class("/Game/" .. string.rep("x", 200) .. "/BP_PlayerPlane_PP9001_falken_L001.BP_PlayerPlane_PP9001_falken_L001_C", ADFX_CLS)
resetMine()
cp, bs = M.myPlane(nil, "falken")
check(cp == "" and bs == "adfx02", "a class path over 200 characters: not sent, its base is")
-- a message that would be cut (CO_MAX_LUA): the path left out, the base kept
local LONG = "/Game/" .. string.rep("x", 100) .. "/BP_PlayerPlane_PP9001_falken_L001.BP_PlayerPlane_PP9001_falken_L001_C"
pawn.cls = class(LONG, ADFX_CLS)
M.tbl.aircraft = keepAc
resetMine()
loadout = string.rep("1,", 296) .. "1/2/3,4"
paint = "910010007/255/" .. string.rep("1,", 90) .. "1"
function pawn:GetObjName() return string.rep("A", 32) end
M.myName = string.rep("N", 32)
s0, from = #sent, #logs + 1
M.myCode = nil
tick()
h0 = lastSent("hi", s0 + 1)
hf = fields(h0)
check(h0 and #h0 <= 1100 and hf[10] == "" and hf[11] == "adfx02" and hf[7] == loadout and line("coop: a message with your plane's class path would be", from) ~= nil,
      "a hi that would pass 1,100 characters: sent without the path, the base and every field before kept, said (" .. tostring(h0 and #h0) .. " characters)")
loadout, paint, pawn.GetObjName, M.myName = "", "", nil, nil
pawn.full, pawn.cls, pawn.PlaneTypeID = "BP_PlayerPlane_PP0022_f16c_C_0", F16C_CLS, nil
resetMine()

---------------------------------------------------------------------------------------------------- the receiver
print("the receiver: another player's modded plane")
COOP.reopen("host", "test")
M.peers, M.left, M.parkAt, M.aside = {}, {}, {}, {}
CFG.coop.real_planes = true
-- installed here: their class, loadout and paint
from = #logs + 1
join(1, hi(1, "f16c_common", "falken", LO1, "910010007/255/1,2", "FALKEN", FALKEN, "adfx02"))
check(native[1] and spawnArgs[1].cls == FALKEN and M.peers[1].real and M.peers[1].fallback == nil and spawnArgs[1].lo == LO1
      and spawnArgs[1].pt == "910010007/255/1,2", "a Falken installed here: their own class (the path their game sent), their loadout and paint")
check(line("coop: player 2's falken: its own blueprint is installed here (" .. FALKEN .. "): the real thing (the path their game sent)", from) ~= nil,
      "... logged")
check(M.roster[1].cls == FALKEN and M.roster[1].base == "adfx02", "their roster entry keeps the path and base")
local p1 = lastSent("pi", nil, function(m) return has(m, ">pi|1|") end)
check(p1 and #fields(p1) == 12 and fields(p1)[11] == FALKEN and fields(p1)[12] == "adfx02", "the host's pi relays them, after the Steam ID (" .. tostring(p1) .. ")")
-- not installed: their base, its own weapons and paint; never loaded again
local MODX = "/Game/Mods/X/BP_PlayerPlane_PP9100_xjet.BP_PlayerPlane_PP9100_xjet_C"
notInstalled[MODX] = true
from = #logs + 1
join(2, hi(2, "f16c_common", "xjet", LO1, "999/0/", "X-JET", MODX, "su57"))
check(native[2] and has(native[2].full, "PP0021_su57") and M.peers[2].fallback == "su57" and spawnArgs[2].lo == "" and spawnArgs[2].pt == "",
      "not installed here: their game's base, a real Su-57, its own weapons and paint (" .. tostring(native[2] and native[2].full) .. ")")
check(line("coop: player 3's xjet: its own blueprint isn't installed here (" .. MODX .. "): a real su57 (their game's base) instead", from) ~= nil
      and has(line("coop: player 3's plane is their xjet shown as a real su57", from), "here: their game's base)") and M.modMiss[MODX] == true,
      "... logged, remembered")
local l0 = loads[MODX]
join(4, hi(4, "f16c_common", "xjet", LO1, "", "X-JET", MODX, "su57"))
check(loads[MODX] == l0 and native[4] and has(native[4].full, "PP0021_su57"), "a second player in it: the path not loaded again, the same base")
-- their base no stock code here: [coop.real_fallback]
notInstalled[FALKEN] = true
M.modMiss = {}
CFG.coop.real_paths = {}
from = #logs + 1
join(5, hi(5, "f16c_common", "falken", LO1, "", "FALKEN", FALKEN, "zz99"))
check(native[5] and has(native[5].full, "PP0038_adfx02_L001") and M.peers[5].fallback == "adfx02", "a base that's no stock code here: [coop.real_fallback] (adfx02)")
-- [coop.real_paths] after their path
local OTHER = "/Game/Mods/Falken2/BP_PlayerPlane_PP9001_falken_L002.BP_PlayerPlane_PP9001_falken_L002_C"
CFG.coop.real_paths = { falken = OTHER }
from = #logs + 1
join(6, hi(6, "f16c_common", "falken", LO1, "", "FALKEN", FALKEN, "adfx02"))
check(native[6] and spawnArgs[6].cls == OTHER and M.peers[6].fallback == nil
      and line("coop: player 7's falken: its own blueprint is installed here (" .. OTHER .. "): the real thing ([coop.real_paths])", from) ~= nil,
      "their path not installed here, [coop.real_paths]'s is: that one")
CFG.coop.real_paths = {}
-- an older build's hi (no path, no base): [coop.real_fallback]
join(7, hi(7, "f16c_common", "falken", LO1, "", "FALKEN"))
check(native[7] and has(native[7].full, "PP0038_adfx02_L001") and M.roster[7].cls == "" and M.roster[7].base == "", "an older build's hi: no path, no base, [coop.real_fallback]")
-- invalid paths: never loaded, never kept
local BAD = { "C:/evil.uasset", "/Game/../Engine/BP_PlayerPlane_PP1_falken.BP_PlayerPlane_PP1_falken_C",
              "/Game/" .. string.rep("a", 190) .. "/BP_PlayerPlane_PP9001_falken.BP_PlayerPlane_PP9001_falken_C",
              "/Game/Blueprints/Weapon/BP_wp_x.BP_wp_x_C", "/Game/Mods/Y/BP_PlayerPlane_PP0022_f16c.BP_PlayerPlane_PP0022_f16c_C",
              "/Game/Mods/Z/BP_PlayerPlane_PP9001_falken.BP_PlayerPlane_PP9001_falken_L001_C", "/Game//Mods/BP_PlayerPlane_PP9_falken.BP_PlayerPlane_PP9_falken_C" }
for i, b in ipairs(BAD) do
    inbox[#inbox + 1] = hi(8, "f16c_common", "falken", LO1, "", "FALKEN", b, "adfx02")
    tick()
    check(M.roster[8] and M.roster[8].cls == "" and M.roster[8].base == "adfx02" and loads[b] == nil, "invalid path " .. i .. " (" .. b:sub(1, 48) .. "): not kept, never loaded")
end
check(not M.clsOk(FALKEN, "f16c") and M.clsOk(FALKEN, "FALKEN") and M.clsOk(FALKEN), "a path for another code refused; the code any case")
-- a path that loads a class that isn't a player plane: rejected, remembered, the fallback
local NOTPP = "/Game/Mods/W/BP_PlayerPlane_PP9200_wjet.BP_PlayerPlane_PP9200_wjet_C"
notPP[NOTPP] = true
from = #logs + 1
join(9, hi(9, "f16c_common", "wjet", LO1, "", "W-JET", NOTPP, "f15c"))
check(native[9] and has(native[9].full, "PP0004_f15c") and M.modMiss[NOTPP] == true
      and line("coop: player 10's wjet: its own blueprint was rejected, not a player plane (not a LivePlayerPlane) (" .. NOTPP .. ")", from) ~= nil,
      "a class that isn't a LivePlayerPlane: rejected, their base instead (" .. tostring(line("player 10's wjet", from)) .. ")")
-- [coop] real_default, then the AI stand-in
CFG.coop.real_default = "su35"
join(10, hi(10, "f16c_common", "qjet", LO1, "", "Q-JET", "", "nope"))
check(native[10] and has(native[10].full, "PP0028_su35") and M.peers[10].fallback == "su35", "no installed blueprint, no stock base, no [coop.real_fallback]: [coop] real_default (su35)")
CFG.coop.real_default = "notaplane"
from = #logs + 1
local n0 = #seq
join(11, hi(11, "f16c_common", "qjet", LO1, "", "Q-JET"))
check(native[11] == nil and has(table.concat(seq, ",", n0 + 1), "spawn SV_Unit_CoopPeerL")
      and line("coop: [coop] real_default notaplane isn't a stock plane code", from) ~= nil
      and line("coop: player 12's real plane (qjet) not spawned: no player plane blueprint for qjet", from) ~= nil,
      "real_default no stock code: said once, the AI stand-in last")
CFG.coop.real_default = "f16c"
-- a joiner's pi, with and without the new fields
COOP.reopen("join", "test")
COOP.slot, M.state = 3, "linked"
inbox[#inbox + 1] = string.format("0|pi|12|f16c_common|%s|Ann|falken|%s||FALKEN|76561198000000001|%s|ADFX02", VERSION, LO1, FALKEN)
inbox[#inbox + 1] = string.format("0|pi|13|su47_common|%s|Bee|su47|%s||SU-47|76561198000000002", VERSION, LO1)
inbox[#inbox + 1] = string.format("0|pi|14|f16c_common|%s|Cid|falken|%s||FALKEN|76561198000000003|C:/evil|adfx02", VERSION, LO1)
tick()
local r12, r13, r14 = M.roster[12], M.roster[13], M.roster[14]
check(r12 and r12.sid == "76561198000000001" and r12.cls == FALKEN and r12.base == "adfx02" and r12.lo == LO1 and r12.ac == "FALKEN",
      "a joiner: the host's pi with the new fields (the Steam ID where it was, the base in lower case)")
check(r13 and r13.sid == "76561198000000002" and r13.cls == "" and r13.base == "", "... an older pi: as before")
check(r14 and r14.cls == "" and r14.base == "adfx02", "... a bad path in it: not kept")
inbox[#inbox + 1] = "0|po|12"; inbox[#inbox + 1] = "0|po|13"; inbox[#inbox + 1] = "0|po|14"
tick()
COOP.reopen("host", "test")
for _, s in ipairs({ 1, 2, 4, 5, 6, 7, 8, 9, 10, 11 }) do leave(s) end

---------------------------------------------------------------------------------------------------- skins
print("skins: a skin this game hasn't, the plane's default paint")
notInstalled[FALKEN], M.modMiss = nil, {}
M.peers = {}
-- an installed skin kept, an unknown one -1, the emblems kept, said once a player and skin
from = #logs + 1
join(1, hi(1, "su57_common", "su57", LO1, "21002001/255/7,8", "SU-57"))
check(spawnArgs[1].pt == "21002001/255/7,8", "an installed skin: their paint as sent")
leave(1)
join(2, hi(2, "su57_common", "su57", LO1, "21099001/255/7,8", "SU-57"))
check(spawnArgs[2].pt == "-1/255/7,8" and line("coop: player 3's skin 21099001 isn't installed here: their plane's default paint", from) ~= nil
      and has(line("coop: player 3's plane is their real su57", from), "given as -1/255/7,8 (their skin isn't installed here)"),
      "an unknown skin: -1 (the plane's default), the emblems kept, said (" .. tostring(spawnArgs[2].pt) .. ")")
local said = count("coop: player 3's skin 21099001", from)
check(M.paintHere(2, "21099001/1/") == "-1/1/" and count("coop: player 3's skin 21099001", from) == said, "... said once a player and skin")
check(M.paintHere(2, "-1/0/3") == "-1/0/3" and M.paintHere(2, "") == "", "the default (-1) and no paint: untouched")
-- (review of 0.73.80) a negative skin other than -1 (or one past an int32) is no skin of any game: -1, the emblems kept,
-- said once a player and skin, whether or not this game's tables can tell
from = #logs + 1
join(3, hi(3, "su57_common", "su57", LO1, "-7/255/1,2", "SU-57"))
check(spawnArgs[3] and spawnArgs[3].pt == "-1/255/1,2" and line("coop: player 4's skin -7 isn't a skin id: their plane's default paint", from) ~= nil,
      "a negative skin other than -1: -1, the emblems kept, said (" .. tostring(spawnArgs[3] and spawnArgs[3].pt) .. ")")
check(M.paintHere(3, "-7/0/") == "-1/0/" and count("coop: player 4's skin -7", from) == 1, "... said once a player and skin")
local okBig, big = pcall(M.paintHere, 3, "-2147483648/255/")
check(okBig and big == "-1/255/", "-2147483648: -1 (" .. tostring(big) .. ")")
okBig, big = pcall(M.paintHere, 3, "2147483648/255/4")
check(okBig and big == "-1/255/4", "past an int32: -1 (" .. tostring(big) .. ")")
okBig, big = pcall(M.paintHere, 3, "99999999999999999999/255/4")
check(okBig and big == "-1/255/4", "past 2^63: -1, no error (" .. tostring(big) .. ")")
leave(3)
check(M.paintHere(2, "910010008/1/") == "910010008/1/", "an add-on's skin in a row named otherwise: kept (every row's SkinID read)")
SKIN_ROWS["21002002"] = { SkinID = 21002002 }
check(M.paintHere(2, "21002002/1/") == "21002002/1/", "a row added since the main menu, named by its id: found by its name")
-- a modded plane installed here has its skin checked the same way; a fallback none
join(4, hi(4, "f16c_common", "falken", LO1, "910010007/255/1", "FALKEN", FALKEN, "adfx02"))
check(spawnArgs[4].cls == FALKEN and spawnArgs[4].pt == "910010007/255/1", "a Falken installed here, its skin in DT_Skin: kept")
join(5, hi(5, "f16c_common", "falken", LO1, "910010099/255/1", "FALKEN", FALKEN, "adfx02"))
check(spawnArgs[5].cls == FALKEN and spawnArgs[5].pt == "-1/255/1", "... a skin of it this game hasn't: -1")
check(softReads == 0, "DecalMaterialRef never read")
leave(2); leave(4); leave(5)
-- keyed by SkinID (rows named otherwise): the ids read once, at the main menu
local ROWS2 = { A = { SkinID = 5014001 }, B = { SkinID = 21002001 }, C = { SkinID = 777001 } }
dataTables = { dataTable("DT_Skin", "/Game/Datatables/Hangar/DT_Skin.DT_Skin", ROWS2, { "A", "B", "C" }) }
M.tbl, M.skin = { path = {}, walks = 0, at = 0, said = {} }, { ans = {}, said = {} }
D = nil
from = #logs + 1
tick()
check(M.skin.keyed == "field" and M.skin.ids[777001] and line("keyed by their SkinID: other players' skins are checked", from) ~= nil,
      "DT_Skin's rows named otherwise: their SkinIDs read (" .. tostring(line("coop: skins:", from)) .. ")")
check(M.paintHere(6, "777001/0/") == "777001/0/" and M.paintHere(6, "777002/0/9") == "-1/0/9", "... checked by them")
-- found by a likely path (no walk)
local w0 = findAllOfDT
staticObjs["/Game/Datatables/Information/DT_Skin.DT_Skin"] = skinDT
staticObjs["/Game/Datatables/Information/DT_LiveAircraft.DT_LiveAircraft"] = acDT
M.tbl, M.skin = { path = {}, walks = 0, at = 0, said = {} }, { ans = {}, said = {} }
tick(11)
check(M.tbl.skin == skinDT and M.tbl.aircraft == acDT and findAllOfDT == w0, "DT_Skin found by a likely path: no walk")
staticObjs = {}
-- a DT_Skin without the stock skins: not used; neither source: paints as sent, one line
dataTables = { dataTable("DT_Skin", "/Game/X/DT_Skin.DT_Skin", { ["1"] = { SkinID = 1 } }, { "1" }) }
M.tbl, M.skin = { path = {}, walks = 0, at = 0, said = {} }, { ans = {}, said = {} }
from = #logs + 1
tick(11)
check(M.skin.dtOk == false and line("none of the stock skins in it, not used", from) ~= nil, "a DT_Skin without the stock skins: not used")
dataTables = {}
M.tbl, M.skin = { path = {}, walks = 0, at = 0, said = {} }, { ans = {}, said = {} }
tick(11); tick(11); tick(11); tick(11)
check(M.tbl.skin == nil and line("coop: the game's DT_Skin not found", from) ~= nil and M.tbl.walks == 3, "no DT_Skin: walked for 3 times, said so")
D = { round = 5, state = "fighting", now = 100, startRound = 1, up = {}, flown = {} }
from = #logs + 1
join(7, hi(7, "su57_common", "su57", LO1, "21099001/255/7,8", "SU-57"))
join(9, hi(9, "su57_common", "su57", LO1, "21099002/255/7", "SU-57"))
check(spawnArgs[7].pt == "21099001/255/7,8" and spawnArgs[9].pt == "21099002/255/7"
      and count("coop: skins aren't checked here", from) == 1, "no source: each paint as sent, one line")
check(M.paintHere(7, "-5/255/7") == "-1/255/7" and M.paintHere(7, "-1/255/7") == "-1/255/7",
      "no source: a negative skin other than -1 still -1, the default untouched")
leave(7); leave(9)
-- the information manager's SkinDataMap_
local mapSet = { [5014001] = true, [21002001] = true, [910010007] = true }
gi = { InformationManager_ = { SkinDataMap_ = { Contains = function(_, id) return mapSet[id] == true end } } }
M.skin = { ans = {}, said = {} }
from = #logs + 1
join(10, hi(10, "su57_common", "su57", LO1, "21002001/255/7", "SU-57"))
join(11, hi(11, "su57_common", "su57", LO1, "21099003/255/7", "SU-57"))
check(spawnArgs[10].pt == "21002001/255/7" and spawnArgs[11].pt == "-1/255/7" and M.skin.mapOk == true
      and line("SkinDataMap_ lists the stock skins: other players' skins are checked against it", from) ~= nil,
      "no DT_Skin, the game's SkinDataMap_: an installed skin kept, an unknown one -1")
leave(10); leave(11)
mapSet = {}
M.skin = { ans = {}, said = {} }
from = #logs + 1
join(12, hi(12, "su57_common", "su57", LO1, "21002001/255/7", "SU-57"))
check(spawnArgs[12].pt == "21002001/255/7" and M.skin.mapOk == false and line("doesn't list the stock skins here: not used", from) ~= nil,
      "a SkinDataMap_ without the stock skins: not used, the paint as sent")
leave(12)
gi = nil

---------------------------------------------------------------------------------------------------- what the others see
print("what the others see: your modded plane without its add-on")
pawn.full = "BP_PlayerPlane_PP9001_falken_L001_C_0"
pawn.cls = class(FALKEN, ADFX_CLS)
resetMine()
CFG.coop.real_paths = {}                                -- (theirs from the path sent: no [coop.real_paths] needed)
D = { round = 6, state = "fighting", now = 100, startRound = 1, up = {}, flown = {} }
local c0 = #callouts
from = #logs + 1
tick(); tick()
local seen = {}
for i = c0 + 1, #callouts do if has(callouts[i], "OTHERS SEE") then seen[#seen + 1] = callouts[i] end end
check(#seen == 1 and seen[1] == "OTHERS SEE YOUR FALKEN (ADFX02 WITHOUT THE ADD-ON) / nil"
      and line("coop: the other players see your FALKEN (falken) as itself where its add-on is installed, else a real adfx02 (its stock base)", from) ~= nil,
      "OTHERS SEE YOUR FALKEN (ADFX02 WITHOUT THE ADD-ON), once a level, logged (" .. tostring(callouts[#callouts]) .. ")")
pawn.cls = nil
resetMine()
check(M.seenAs("falken", "", "") == "ADFX02" and select(3, M.seenAs("falken", "", "")) == nil,
      "no path sent and no [coop.real_paths]: AS ADFX02 (nobody can show the add-on)")
pawn.full, pawn.cls = "BP_PlayerPlane_PP0022_f16c_C_0", F16C_CLS

do
    local errs = {}
    for _, l in ipairs(logs) do
        for _, e in ipairs({ "plane and skin tables: error", "skins: check error", "skins: DT_Skin error", "your plane's class: error",
                             "player plane error", "seen-as error", "message error", "its class: error" }) do
            if l:find(e, 1, true) then errs[#errs + 1] = l end
        end
    end
    check(#errs == 0, "no error in the parts touched (" .. tostring(errs[1]) .. ")")
end

print(fails == 0 and "modsync test: all passed" or ("modsync test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
