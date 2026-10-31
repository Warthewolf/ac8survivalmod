-- spweapons_test.lua <mod dir> <work dir> (run by tools/checks/spweapons_test.sh): the enemies' special weapons fired
-- (Scripts/sv_spweapons.lua, CFG.special.fire) on the real sv_core, sv_config and sv_spweapons, the game stubbed:
--   an enemy whose row carries its special in slot 3 fires it (RE_SV_SpecFire_<NN><L>) with you in its nose cone at
--     that weapon's range; not first_s after it appears; not again for every_s; not with you behind it, too near or too
--     far (each weapon's band: a QAAM's short, a LAAM's long); not a row with its special elsewhere (the jammer's), a
--     held Wolf trap, a plane down; at most max_per_min across the sky; nothing on a co-op joiner, nothing switched off;
--   the build's slot (tools/survival_events.py SPEC_SLOT = WN_WEAPON_4) and Lua's in step.
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
VERSION = "0.73.42-spweapons.test"
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
part("sv_spweapons.lua")
local events = {}
function SV_Event(n) events[#events + 1] = n; return 1 end
function poolIndex(u) local n, k = tostring(u):match("^ERA_Unit_(%d+)_Dep_Air(%d)$"); return n and (tonumber(n) - 1) * 3 + tonumber(k) + 1 end

-- you at the origin; planes km out along +x, facing you (-x) or away
local you = { full = "you" }
function you:K2_GetActorLocation() return { X = 0, Y = 0, Z = 300000 } end
survivalPC = { full = "PC", Pawn = you }
local function plane(unit, k, km, facing)
    local o = { full = "BP_OP1030_su33_CP_C_" .. k }
    function o:K2_GetActorLocation() return { X = km * 100000, Y = 0, Z = 300000 } end
    function o:GetActorForwardVector() return { X = facing == "away" and 1 or -1, Y = 0, Z = 0 } end
    return { obj = o, unit = unit, k = k, born = 0, name = o.full }
end
local U1, U2 = "ERA_Unit_01_Dep_Air0", "ERA_Unit_02_Dep_Air0"
SR = { spSlot = { su33_common_sv = 3, e18g_common_sv = 4, f14d_common_sv = 3 },
       spWeapon = { su33_common_sv = "NPC_FCS_PlaneHCAA000", e18g_common_sv = "NPC_FCS_Plane2AAM000", f14d_common_sv = "NPC_FCS_PlaneLAAM000" } }
local function fresh(rows)
    events, logs, SPW.recent, SPW.nextAt, SPW.said = {}, {}, {}, nil, {}
    D = { state = "fighting", flightRow = rows or { [U1] = "su33_common_sv" }, wolf = {} }
end
local function evs() return table.concat(events, ",") end

print("fired")
fresh()
planes = { plane(U1, 0, 4, "you"), plane(U1, 1, 4, "you") }
SPW.tick(5)
check(#events == 0, "nothing first_s after it appears")
SPW.tick(20)
check(evs() == "RE_SV_SpecFire_01A,RE_SV_SpecFire_01B", "an HCAA row with you 4 km ahead: both fire (" .. evs() .. ")")
check(#logs == 1 and logs[1]:find("ERA_Unit_01_Dep_Air0 A (su33_common_sv) fires its NPC_FCS_PlaneHCAA000 at you, 4.0 km", 1, true),
    "logged once a row and weapon: " .. tostring(logs[1]))
SPW.tick(30)
check(#events == 2, "not again within every_s")
SPW.tick(46)
check(#events == 4, "again every_s later")

print("not fired")
fresh()
planes = { plane(U1, 0, 4, "away") }
SPW.tick(20)
check(#events == 0, "you behind it: none")
planes = { plane(U1, 0, 1.0, "you") }; SPW.nextAt = nil
SPW.tick(21)
check(#events == 0, "inside the HCAA's band (1 km): none")
planes = { plane(U1, 0, 9, "you") }; SPW.nextAt = nil
SPW.tick(22)
check(#events == 0, "past it (9 km): none")
fresh({ [U1] = "f14d_common_sv" })
planes = { plane(U1, 0, 9, "you") }
SPW.tick(20)
check(#events == 1, "a LAAM at 9 km: fired (its own band)")
fresh({ [U1] = "e18g_common_sv" })
planes = { plane(U1, 0, 4, "you") }
SPW.tick(20)
check(#events == 0, "the jammer's (its special in slot 4): none")
fresh()
planes = { plane(U1, 0, 4, "you") }
D.wolf[U1] = { held = { [0] = true } }
SPW.tick(20)
check(#events == 0, "a held Wolf trap: none")
fresh()
planes = { plane(U1, 0, 4, "you") }
planes[1].down = true
SPW.tick(20)
check(#events == 0, "a plane down: none")

print("the sky's cap")
fresh({ [U1] = "su33_common_sv", [U2] = "su33_common_sv" })
planes = {}
for k = 0, 5 do planes[#planes + 1] = plane(U1, k, 4, "you"); planes[#planes + 1] = plane(U2, k, 4, "you") end
SPW.tick(20)
check(#events == CFG.special.fire.max_per_min, "12 in range: max_per_min fire (" .. #events .. ")")
SPW.tick(40)
check(#events == CFG.special.fire.max_per_min, "none more within the minute")

print("co-op and off")
fresh()
planes = { plane(U1, 0, 4, "you") }
COOP = { client = function() return true end }
SPW.tick(20)
check(#events == 0, "a co-op joiner: none (the host's)")
COOP = nil
CFG.special.fire.enabled = false
SPW.nextAt = nil
SPW.tick(21)
check(#events == 0, "enabled = false: none")
CFG.special.fire.enabled = true

print("the build")
local se = readAll(MOD .. "/../../../tools/survival_events.py")
check(se:find("SPEC_SLOT = 'WN_WEAPON_4'", 1, true) and SPW.FCS_SLOT == 3, "SPEC_SLOT WN_WEAPON_4 = slot 3 (SPW.FCS_SLOT)")

print(fails == 0 and "spweapons test: all passed" or ("spweapons test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
