-- audit_test.lua <mod dir> <work dir> (run by tools/checks/audit_test.sh): the run's audits (Scripts/sv_audit.lua,
-- CFG.log.audit) on the real sv_core, sv_config and sv_audit, the game stubbed:
--   targets: the enemies' blackboard targets looked at every sample_s (you, another co-op player by name, the allies,
--     anything else, nothing), each player's damage taken (drops of their health), the line every report_s;
--   the pay audit: pays by kind through the wrapped addCredits (still paid), a joiner's kill paid right after it tore
--     copies down flagged at once, the line every report_s;
--   sync: COOP.syncReport's line every report_s while co-op is open; the crash breadcrumbs' crumb() with no runtime.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))
local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore
VERSION = "0.73.44-audit.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
function NotifyOnNewObject() end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
local function part(name, chunk) assert(load(readAll(MOD .. "/Scripts/" .. name), chunk or ("=" .. name)))() end
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and o.full or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
part("sv_config.lua")
local paid = {}
function addCredits(n, why) paid[#paid + 1] = { n = n, why = why } end
function aiBlackboard(p) return p.bb end
ALLY = ALLY or {}
local ally = { full = "BP_OP1005_f22a_CP_C_1", addr = 70 }
function ALLY.state() return { planes = { { obj = ally } } } end
part("sv_audit.lua")
local function lines(pat) local t = {}; for _, l in ipairs(logs) do if l:find(pat) then t[#t + 1] = l end end; return t end

print("crumbs")
check(pcall(crumb, "a test line") == true, "crumb() with no runtime (no SV_Crumb): nothing, no error")
local got = {}
SV_Crumb = function(s) got[#got + 1] = s; return 1 end
crumb("spawn ERA_Unit_01_Dep_Air0: 2")
check(got[1] == "spawn ERA_Unit_01_Dep_Air0: 2", "crumb() hands SV_Crumb its line")
SV_Crumb = nil

print("targets")
local you = { full = "you", addr = 99, HealthInternal = 1000, MaxHealth = 100 }
survivalPC = { full = "PC", Pawn = you }
local friend = { full = "BP_PlayerPlane_PP1018_fa36_C_2", addr = 88 }
local ship = { full = "BP_VE002_aegs_CP_C_3", addr = 66 }
local function enemy(target) return { unit = "ERA_Unit_01_Dep_Air0", obj = { full = "e" },
    bb = { GetValueAsObject = function() return target end } } end
local friendHp = 100
COOP = { open = true, client = function() return true end, host = function() return false end,
         slotOfAddr = function(a) return a == 88 and 1 or nil end, name = function(s) return s == 1 and "gloom" or nil end,
         players = function() return { { isMe = true, slot = 0 }, { slot = 1, hpPct = friendHp } } end,
         syncReport = function() return "joiner: 4 copies of 2 flights (3 bound to the host's ids, 1 not)" end,
         tornRecently = function() return false, nil end }
planes = { enemy(you), enemy(you), enemy(friend), enemy(ally), enemy(ship), enemy(nil) }
D = { now = 0 }
AUDIT.tick(1)
you.HealthInternal, friendHp = 700, 80
AUDIT.tick(6)
for t = 11, 56, 5 do AUDIT.tick(t) end
AUDIT.tick(62)
local tl = lines("^targets: last ")
check(#tl == 1 and tl[1]:find("aiming at you 2.0, ", 1, true) and tl[1]:find("gloom 1.0", 1, true) and tl[1]:find("allies 1.0", 1, true)
    and tl[1]:find("nothing 1.0", 1, true) and tl[1]:find("others 1.0 (most BP_VE002_aegs_CP)", 1, true),
    "who they aim at, by name: " .. tostring(tl[1]))
check(tl[1] and tl[1]:find("damage taken: gloom -20% in 1 looks, you -30% in 1 looks", 1, true), "each player's damage taken: " .. tostring(tl[1]))
check(#lines("^sync: last 60 s: joiner: 4 copies") == 1, "the sync line (co-op open)")

print("pay audit")
logs, paid = {}, {}
addCredits(290, "f15e down (bomber, Veteran x1.25)")
addCredits(150, "landing craft down (lane A)")
addCredits(1600, "round 9 cleared")
check(#paid == 3 and paid[1].n == 290, "still paid through the wrap")
COOP.tornRecently = function() return true, "the host's run started over" end
addCredits(140, "m21b down (fighter, Veteran x1.25)")
local fl = lines("^pay audit: %+140 %(m21b down")
check(#fl == 1 and fl[1]:find("within 5 s of this game tearing copies down (the host's run started over)", 1, true),
    "a joiner's kill paid right after a teardown: flagged at once")
COOP.tornRecently = function() return false, nil end
AUDIT.tick(124)
local pl = lines("^pay audit: last ")
check(#pl == 1 and pl[1]:find("+2180 Z in 4 pays", 1, true) and pl[1]:find("kills 2 (+430)", 1, true)
    and pl[1]:find("round bonuses 1 (+1600)", 1, true) and pl[1]:find("specials 1 (+150)", 1, true)
    and pl[1]:find("1 kill pays (+140) right after a teardown here", 1, true), "the pay line by kind: " .. tostring(pl[1]))

print("off")
logs = {}
CFG.log.audit.enabled = false
AUDIT.tick(300)
addCredits(10, "x down (y)")
check(#logs == 0, "enabled = false: nothing")

print(fails == 0 and "audit test: all passed" or ("audit test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
