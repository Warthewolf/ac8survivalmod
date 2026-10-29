-- hud_info_test.lua <work dir> (run by tools/checks/hud_info_test.sh on a copy of the parts with the test-only code taken
-- out, as a release has them): the HUD's info key (CFG.hud.info; the user's request of 2026-10-29, code review F6), on
-- the real sv_core, sv_config, sv_ai, sv_hud, sv_allies, sv_tactical and sv_coop (M exposed), the widgets stubbed:
--   the key: one UE4SS key bind, I without Ctrl (Ctrl+I with ctrl), left in by strip_test_only; a key name UE4SS
--     doesn't know, or no key binds at all, leaves the rows always shown (logged); enabled = false binds nothing;
--   the stack: NEXT first, then ALLIES, ITEMS, CO-OP and its four player lines, the last above the game's minimap;
--     without the key, today's order (CO-OP first) and every row shown whenever it has something in it;
--   closed: a row shows peek_s (and up to the next second's pass) when it first has something, when its news changes
--     (an item bought or used; an ally flight there or gone, the allies' order) or when it comes back, never for a
--     count that ticks (the ECM's seconds, an ally flight's aircraft, the kills); a change while the HUD is hidden
--     (paused) peeks once it's back up;
--   the key's press: the rows shown on the next pass (not the next second's), logged "hud: info rows shown (I)", hidden
--     again on the next press; outside a run nothing; the rows read once a second, not every pass;
--   co-op: the compact row peeks when a player joins, drops or is shot down or a link is lost, not for health, the
--     airfield or a state gone stale (a downed player's too); open, "CO-OP n/max" and a line a player (FLYING / AT THE AIRFIELD / DOWN / NOT IN THE MISSION,
--     health), the fourth "+N MORE" in a bigger room; a joiner still looking for its host has the one row.
local WORK = arg[1]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function has(s, part) return s ~= nil and s:find(part, 1, true) ~= nil end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

-- UE4SS's key binds, recorded; its key table holds a few real names (unknown ones are nil, as UE4SS's)
local binds = {}
function RegisterKeyBind(key, mods, fn) binds[#binds + 1] = { key = key, mods = mods, fn = fn } end
Key = { I = 73, O = 79, F5 = 116 }
ModifierKey = { CONTROL = "CTRL" }
function ExecuteInGameThread(fn) fn() end

-- the widgets: each records its text, visibility and its canvas slot's offsets
local Slot = {}
Slot.__index = Slot
function Slot:SetOffsets(o) self.top, self.left = o.Top, o.Left end
function Slot:SetAnchors() end
function Slot:SetAlignment() end
function Slot:SetAutoSize() end
function Slot:SetSize() end
local Wm = {}
local function newW(cls, name) return setmetatable({ cls = cls, name = name, full = name, kids = 0, Font = { OutlineSettings = {} } }, Wm) end
local methods = {
    SetText = function(self, t) self.text = t end,
    SetVisibility = function(self, v) self.vis = v end,
    GetVisibility = function(self) return self.vis end,
    AddChildToCanvas = function(self, w) local s = setmetatable({ w = w }, Slot); w.slot = s; return s end,
    GetChildrenCount = function() return 0 end,
    GetDesiredSize = function() return { X = 100, Y = 40 } end,
}
local function noop() end
Wm.__index = function(_, k) return methods[k] or (type(k) == "string" and k:match("^%u") and noop) or nil end   -- (methods only)
local root = newW("CanvasPanel", "Root")
local wbl = { Create = function() return setmetatable({ WidgetTree = { RootWidget = root }, full = "WBP_HUD_NonGlowMessage_000_C_1" }, Wm) end }
function StaticFindObject(p)
    if p == "/Script/UMG.Default__WidgetBlueprintLibrary" then return wbl end
    local cls = p:match("^/Script/UMG%.(%w+)$")
    return cls and { cls = cls } or nil
end
function StaticConstructObject(c, _, name) return newW(c.cls, name) end
function FText(s) return s end
function FName(s) return s end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function NotifyOnNewObject() end
local unitAlive = 2
function SV_UnitAlive() return unitAlive end

-- the real parts, from the stripped copy (sv_core's SCRIPT_DIR and log file in the work folder)
local function part(name, chunk, edits)
    local src = readAll(WORK .. "/Scripts/" .. name)
    for _, e in ipairs(edits or {}) do
        local n
        src, n = src:gsub(e[1], e[2], 1)
        assert(n == 1, name .. ": " .. e[1] .. " not found")
    end
    assert(load(src, chunk or ("=" .. name)))()
end
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
local logFile = assert(io.open(WORK .. "/test_lua.log", "wb"))
function log(s) logs[#logs + 1] = s; logFile:write(os.date("%H:%M:%S ") .. s .. "\n") end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function loadObject(p) return { full = p } end
part("sv_config.lua"); part("sv_ai.lua")
local IC = CFG.hud.info
local function line(prefix, from)
    for i = #logs, from or 1, -1 do if logs[i]:sub(1, #prefix) == prefix then return logs[i] end end
    return nil
end

---------------------------------------------------------------------------------------------------- the key
print("the key (CFG.hud.info)")
local srcHud = readAll(WORK .. "/Scripts/sv_hud.lua")
check(not has(readAll(WORK .. "/Scripts/sv_main.lua"), "Key.F8") and has(srcHud, "RegisterKeyBind"),
      "the parts are a release's (test-only code out) and the info key's bind is still in sv_hud")
do
    local function reload(set)
        for k, v in pairs({ enabled = true, key = "I", ctrl = false, start_open = false }) do IC[k] = v end
        for k, v in pairs(set or {}) do IC[k] = v end
        binds = {}
        local n = #logs + 1
        part("sv_hud.lua")
        return n
    end
    local n = reload({ ctrl = true })
    check(#binds == 1 and binds[1].key == 73 and #binds[1].mods == 1 and binds[1].mods[1] == "CTRL"
          and has(line("hud: info key", n), "Ctrl+I"), "ctrl = true: Ctrl+I")
    n = reload({ key = "Q?" })
    check(#binds == 0 and IC.enabled == false and has(line("hud: info key", n), "isn't a key name UE4SS knows")
          and has(line("hud: info key", n), "always shown"), "a key name UE4SS doesn't know: no bind, the rows always shown (logged)")
    n = reload({ enabled = false })
    check(#binds == 0 and line("hud: info key", n) == nil, "enabled = false: nothing bound")
    local rk = RegisterKeyBind
    RegisterKeyBind = nil
    n = reload()
    RegisterKeyBind = rk
    check(IC.enabled == false and has(line("hud: info key", n), "no key binds"), "no key binds: the rows always shown")
    n = reload({ key = "o" })
    check(#binds == 1 and binds[1].key == 79 and has(line("hud: info key", n), "info key O:"), "a key name in any case (o -> O)")
    n = reload()
    check(#binds == 1 and binds[1].key == 73 and #binds[1].mods == 0 and has(line("hud: info key", n), "info key I: ")
          and has(line("hud: info key", n), "hidden until it's pressed") and has(line("hud: info key", n), "5.0 s"),
          "the default: I without Ctrl, the rows hidden until it's pressed (logged)")
end
local press = binds[1].fn
part("sv_allies.lua"); part("sv_tactical.lua")
part("sv_coop.lua", nil, { { "\nlocal M = {", "\nM = {" } })
local M = _G.M
function nativeReady() return true end
local onAirfield = false
function playerOnAirfield() return onAirfield end

-- you, and a run
local pawn = { full = "BP_PlayerPlane_PP1000_f16c_C_1", addr = 9, MaxHealth = 100, HealthInternal = 1000 }
function pawn:K2_GetActorLocation() return { X = 0, Y = 0, Z = 300000 } end
local pc = { Pawn = pawn, GetHUD = function() return { bShowHUD = true } end }
survivalPC = pc
local now = 100
local function fresh()
    D = { round = 5, state = "fighting", now = now, at = now + 30 }
    RUN = { credits = 1000, items = {}, kills = {} }
    ALLY.run, TAC.ecmUntil = nil, nil
    COOP.open, COOP.role, COOP.slot = false, nil, nil
    H, hudTries, hudOff, callouts = nil, 0, false, {}
end
local calls = { ally = 0, tac = 0, coop = 0 }
do
    local a, t, c = ALLY.hudLine, TAC.line, COOP.hudLine
    ALLY.hudLine = function(...) calls.ally = calls.ally + 1; return a(...) end
    TAC.line = function(...) calls.tac = calls.tac + 1; return t(...) end
    COOP.hudLine = function(...) calls.coop = calls.coop + 1; return c(...) end
end
local paused = false
local function tick(dt)                          -- hudTick every 250 ms for dt seconds
    local t1 = now + (dt or 0)
    repeat
        D.now = now
        hudTick(now, paused, pc)
        now = now + 0.25
        clock = clock + 0.25
    until now > t1
    now = now - 0.25
end
local function row(key)                          -- a row's widget by its build name ("Items", "CoopPlayer2")
    for _, r in ipairs(H.stack) do if r.w.name:match("^SV_" .. key .. "_%d+$") then return r end end
end
local function shown(key) local r = row(key); return r ~= nil and r.shown == true end
local function text(key) local r = row(key); return r and r.w.text end

---------------------------------------------------------------------------------------------------- the stack
print("the stack")
fresh()
tick(0)
do
    local names = {}
    for _, r in ipairs(H.stack) do names[#names + 1] = r.w.name:match("^SV_(%a+%d?)_") end
    check(table.concat(names, ",") == "Next,Allies,Items,Coop,CoopPlayer1,CoopPlayer2,CoopPlayer3,CoopPlayer4",
          "NEXT first, then ALLIES, ITEMS, CO-OP and its four player lines (" .. table.concat(names, ",") .. ")")
    check(H.stackY == 516, "the stack starts at 516 (under ROUND, ZOLLARS, AIRFIELD)")
    local last = H.stackY + (#H.stack - 1) * CFG.hud.line
    check(last + CFG.hud.line <= 1108, "all eight rows shown end above the game's minimap (top 1108; the last at " .. last .. ")")
    check(not shown("Allies") and not shown("Items") and not shown("Coop"), "solo, nothing bought: no info row")
end

---------------------------------------------------------------------------------------------------- items
print("closed: the items row peeks")
fresh(); now = 100
RUN.items = { airstrike = 1 }
tick(0)
check(shown("Items") and text("Items") == "ITEMS: AIRSTRIKE 1", "an item carried at the start: its row peeks")
tick(4.5)
check(shown("Items"), "... still up 4.5 s on")
tick(1.5)
check(not shown("Items"), "... collapsed by 6 s on (peek_s 5, read once a second)")
RUN.items.ecm = 1
tick(1)
check(shown("Items") and text("Items") == "ITEMS: AIRSTRIKE 1   ECM 1", "an item bought: a peek")
tick(6)
check(not shown("Items"), "... over")
RUN.items.ecm, TAC.ecmUntil = 0, now + 10
tick(1)
check(shown("Items") and has(text("Items"), "ECM ON"), "the ECM burst used: a peek (" .. tostring(text("Items")) .. ")")
tick(6)
local n0 = #logs
check(not shown("Items") and now < TAC.ecmUntil, "... over while its seconds still count down: no peek for each of them")
TAC.ecmUntil = nil
RUN.items.airstrike = 0
tick(1)
check(not shown("Items") and row("Items").shown == false, "the last item used: the row has nothing (collapsed)")
RUN.items.airstrike = 1
tick(1)
check(shown("Items"), "one bought again, the same as before it went: it comes back, so a peek")
check(#logs == n0 or line("hud: info", n0) == nil, "no info log lines without a press")

---------------------------------------------------------------------------------------------------- paused
print("a change while the HUD is hidden")
tick(6)
paused = true
RUN.items.decoy = 1
tick(10)
check(not H.shown and not shown("Items"), "paused: the HUD hidden, the row not shown")
paused = false
tick(0.25)
check(H.shown and shown("Items"), "back up: the change peeks then")
tick(4.25)
check(shown("Items"), "... for peek_s from then (4.5 s on)")
tick(1.5)
check(not shown("Items"), "... and is over")

---------------------------------------------------------------------------------------------------- allies
print("closed: the allies row peeks")
fresh(); now = 200
tick(0)
ALLY.run = { up = { SV_Unit_AllyW = { kind = "air", ally = "wingmen" } }, events = {}, hunted = {}, seen = {}, planes = {} }
unitAlive = 2
tick(1)
check(shown("Allies") and has(text("Allies"), CFG.allies.wingmen.name .. " 2") and has(text("Allies"), "HUNT"),
      "the WINGMEN up: their row peeks (" .. tostring(text("Allies")) .. ")")
tick(6)
check(not shown("Allies"), "... over")
unitAlive = 1
RUN.kills = { allies = 3 }
tick(2)
check(not shown("Allies"), "one of them shot down, their kills: counts, no peek")
ALLY.nextOrder("test")
tick(1)
check(shown("Allies") and has(text("Allies"), "COVER"), "the allies' order changed: a peek (" .. tostring(text("Allies")) .. ")")
tick(6)
ALLY.run.up.SV_Unit_Ally1 = { kind = "air" }
tick(1)
check(shown("Allies") and has(text("Allies"), CFG.allies.aircraft.name), "another ally flight bought: a peek")

---------------------------------------------------------------------------------------------------- the key
print("the key's press")
tick(6)
check(not shown("Allies") and not shown("Items") and not row("Items").shown, "closed, no news: both rows hidden")
RUN.items = { airstrike = 2 }
tick(7)
n0 = #logs
local before = calls.ally
D.now = now
press()
check(logs[#logs] == "hud: info rows shown (I)", "a press logs 'hud: info rows shown (I)'")
hudTick(now, false, pc)
check(shown("Allies") and shown("Items") and text("Items") == "ITEMS: AIRSTRIKE 2" and calls.ally == before + 1,
      "the next pass shows them (not the next second's)")
tick(10)
check(shown("Allies") and shown("Items"), "open: they stay")
unitAlive = 2
tick(1)
check(has(text("Allies"), CFG.allies.wingmen.name .. " 2"), "open: a count shown as it changes")
press()
check(logs[#logs] == "hud: info rows hidden (I)", "the next press logs 'hud: info rows hidden (I)'")
hudTick(now, false, pc)
check(not shown("Allies") and not shown("Items"), "... and the next pass hides them")
local savedD = D
D = nil
n0 = #logs
press()
D = savedD
hudTick(now, false, pc)
check(#logs == n0 and not shown("Items"), "a press outside a run does nothing")
do
    local a = calls.ally
    tick(10)
    check(calls.ally - a <= 11, "the rows read once a second, not every pass (" .. (calls.ally - a) .. " reads in 10 s of 4 a second)")
end
D.state, D.at = "wait", now + 20
press()
hudTick(now, false, pc)
check(row("Next").slot.top == 516 and row("Allies").slot.top == 584 and row("Items").slot.top == 652,
      "open: NEXT stays first at 516, ALLIES and ITEMS under it")
press()
hudTick(now, false, pc)
check(row("Next").slot.top == 516 and shown("Next"), "closed: NEXT where it was")
D.state = "fighting"

---------------------------------------------------------------------------------------------------- co-op
print("co-op")
fresh(); now = 300
COOP.open, COOP.role, COOP.slot = true, "host", 0
M.state = "linked"
M.roster = { [0] = { name = "War" }, [1] = { name = "Cressendo" } }
M.peers = { [1] = { at = { X = 0, Y = 0, Z = 0 }, flags = 3, fresh = true, alive = true, onAirfield = false, hpPct = 87.4 } }
M.wasLost = nil
tick(0)
local maxP = math.max(2, math.min(24, math.floor(tonumber(CFG.coop.max_players) or 24)))
check(shown("Coop") and text("Coop") == string.format("CO-OP 2/%d: WAR (HOST)  CRESSENDO", maxP), "a co-op room: its row peeks (" .. tostring(text("Coop")) .. ")")
check(not shown("CoopPlayer1"), "... closed: no player lines")
tick(6)
check(not shown("Coop"), "... over")
M.peers[1].hpPct = 40
M.peers[1].onAirfield = true
tick(2)
check(not shown("Coop"), "a player's health and landing: no peek")
M.peers[1].fresh = false
tick(2)
check(not shown("Coop"), "a player's state gone stale (a lag): no peek")
M.peers[1].fresh, M.peers[1].alive, M.peers[1].flags = true, false, 1     -- (as peerTick keeps it: flag 2 alive gone)
tick(1)
check(shown("Coop"), "a player shot down: a peek")
tick(6)
do                                      -- (a downed player's link lagging: their state stale 1 s in every 4)
    local up = 0
    for _ = 1, 3 do
        M.peers[1].fresh = false
        tick(1)
        if shown("Coop") then up = up + 1 end
        M.peers[1].fresh = true
        tick(3)
        if shown("Coop") then up = up + 1 end
    end
    check(up == 0, "a downed player's state gone stale and fresh again: no peek (" .. up .. " of 6 looks shown)")
end
M.roster[2] = { name = "Reaper" }
tick(1)
check(shown("Coop") and has(text("Coop"), "REAPER"), "a player joins: a peek")
tick(6)
M.wasLost = { [2] = true }
tick(1)
check(shown("Coop") and has(text("Coop"), "REAPER (LOST)"), "a link lost: a peek")
tick(6)
press()
hudTick(now, false, pc)
check(shown("Coop") and text("Coop") == string.format("CO-OP 3/%d", maxP), "open: 'CO-OP 3/" .. maxP .. "' (" .. tostring(text("Coop")) .. ")")
check(text("CoopPlayer1") == "  WAR (HOST)   FLYING  100%" and text("CoopPlayer2") == "  CRESSENDO   DOWN"
      and text("CoopPlayer3") == "  REAPER (LOST)   NOT IN THE MISSION" and not shown("CoopPlayer4"),
      "... a line a player: " .. tostring(text("CoopPlayer1")) .. " / " .. tostring(text("CoopPlayer2")) .. " / " .. tostring(text("CoopPlayer3")))
M.peers[1].alive, M.peers[1].flags = true, 3
onAirfield = true
tick(1)
check(text("CoopPlayer1") == "  WAR (HOST)   AT THE AIRFIELD  100%" and text("CoopPlayer2") == "  CRESSENDO   AT THE AIRFIELD  40%",
      "... updated: " .. tostring(text("CoopPlayer1")) .. " / " .. tostring(text("CoopPlayer2")))
onAirfield = false
for s = 3, 5 do M.roster[s] = { name = "P" .. s } end
tick(1)
check(text("Coop") == string.format("CO-OP 6/%d", maxP) and shown("CoopPlayer4") and text("CoopPlayer4") == "  +3 MORE",
      "6 players: three lines and '+3 MORE' (" .. tostring(text("CoopPlayer4")) .. ")")
press()
hudTick(now, false, pc)
check(not shown("Coop") and not shown("CoopPlayer1") and not shown("CoopPlayer4"), "closed again: the row and its lines hidden (the joins seen while open are no peek)")
COOP.role, M.state, M.auto = "join", "looking", true
tick(1)
check(shown("Coop") and text("Coop") == "CO-OP: LOOKING FOR A HOST...", "a joiner looking for its host: one row, its peek")
press()
hudTick(now, false, pc)
check(shown("Coop") and not shown("CoopPlayer1"), "... open: still the one row")
press()
hudTick(now, false, pc)
COOP.open = false
tick(1)
check(not shown("Coop"), "solo: no row")

---------------------------------------------------------------------------------------------------- without the key
print("enabled = false (today's rows)")
IC.enabled = false
fresh(); now = 400
COOP.open, COOP.role, COOP.slot, M.state = true, "host", 0, "linked"
M.wasLost = nil
RUN.items = { airstrike = 1 }
tick(0)
do
    local names = {}
    for _, r in ipairs(H.stack) do names[#names + 1] = r.w.name:match("^SV_(%a+%d?)_") end
    check(table.concat(names, ",") == "Coop,Next,Allies,Items", "today's order, no player lines (" .. table.concat(names, ",") .. ")")
end
tick(30)
check(shown("Items") and shown("Coop") and has(text("Coop"), "CO-OP 6/"), "every row shown whenever it has something, the compact co-op row")
press()
hudTick(now, false, pc)
check(shown("Items") and shown("Coop"), "a press changes nothing")

---------------------------------------------------------------------------------------------------- start_open
print("start_open = true")
IC.enabled, IC.start_open = true, true
binds = {}
n0 = #logs + 1
part("sv_hud.lua")
check(#binds == 1 and has(line("hud: info key", n0), "open at the start"), "logged 'open at the start'")
fresh(); now = 500
RUN.items = { airstrike = 1 }
tick(20)
check(shown("Items"), "the rows open without a press, 20 s on")
binds[1].fn()
hudTick(now, false, pc)
check(not shown("Items") and logs[#logs] == "hud: info rows hidden (I)", "the first press hides them")

logFile:close()
print(fails == 0 and "hud info test: all passed" or ("hud info test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
