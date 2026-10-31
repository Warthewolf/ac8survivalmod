-- weaponlog_test.lua <mod dir> <work dir> (run by tools/checks/weaponlog_test.sh): the enemy weapons log
-- (Scripts/sv_weaponlog.lua, CFG.log.weapons) on the real sv_core, sv_config and sv_weaponlog, the game stubbed:
--   carried: an enemy plane's fire control (AllArms: system name, the projectile module's WeaponClass / WeaponClasses,
--     its ammo when limited) logged 2 s after it's created, once for its airframe and loadout;
--   fired: the first look learns what's up (nothing counted); a weapon shown that was hidden is a launch, its owner an
--     enemy plane (its unit and row), you (not counted) or another (by its class); one shown again with a new owner a
--     launch too; the first launch of each weapon by each airframe logged once;
--   the summary every summary_s: what was launched, by whom, and what's carried but never fired; off: nothing;
--   missiles at you followed to their end (a hit, decoyed by a flare, missed) and the summary's `missiles at you`;
--   the Spaceport fleet's turrets: a turret's missile counted with your range, a mount silent in your reach idle.
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
VERSION = "0.73.39-weaponlog.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
function NotifyOnNewObject() end
local FA = {}
function FindAllOf(c) return FA[c] or {} end
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
part("sv_weaponlog.lua")
local function arr(t)                             -- a TArray as UE4SS hands it to Lua
    return { ForEach = function(self, f) for i, v in ipairs(t) do f(i, { get = function() return v end }) end end }
end
local function cls(n) return { full = "BlueprintGeneratedClass /Game/W/" .. n .. "." .. n .. "_C" } end
local function lines(pat) local t = {}; for _, l in ipairs(logs) do if l:find(pat) then t[#t + 1] = l end end; return t end

-- an F-16C of flight ERA_Unit_01_Dep_Air0 with a gun, missiles (unlimited) and a QAAM (4)
local f16 = { full = "BP_OP1022_f16c_CP_C_1", addr = 11 }
f16.FireControlSystemComponent = { full = "FCS", AllArms = arr({
    { full = "a1", SystemName = FName("NPC_FCS_PlaneGun000"), ProjectileModule = { full = "pm1", WeaponClass = cls("BP_wp_gun_a0"), bLimitAmmo = false } },
    { full = "a2", SystemName = FName("NPC_FCS_PlaneMsl000"), ProjectileModule = { full = "pm2", WeaponClass = cls("BP_wp_msl_a0"), bLimitAmmo = false } },
    { full = "a3", SystemName = FName("NPC_FCS_PlaneQAAM000"), ProjectileModule = { full = "pm3", WeaponClass = cls("BP_wp_qaam_a0"), bLimitAmmo = true, AmmoCount = 4 } },
}) }
local you = { full = "BP_PlayerPlane_PP1000_f16c_C_1", addr = 99 }
survivalPC = { full = "PC", Pawn = you }
planes = { { obj = f16, name = "BP_OP1022_f16c_CP_C_1", unit = "ERA_Unit_01_Dep_Air0", born = 0, addr = 11 } }
D = { now = 0, flightRow = { ERA_Unit_01_Dep_Air0 = "f16c_common_sv" } }
local function msl(n, addr, owner) return { full = "x." .. n .. "_C_" .. addr, addr = addr, bHidden = true, OwningGameObject = owner } end
local m1, m2, m3 = msl("BP_wp_msl_a0", 201, f16), msl("BP_wp_msl_a0", 202, f16), msl("BP_plwp_msl_a0", 203, you)
local ship = { full = "BP_VE002_aegs_mk41_CP_C_7", addr = 31 }
local m4 = msl("BP_wp_vls_mk41", 204, ship)
FA.LiveExplosiveWeapon = { m1, m2, m3, m4 }

print("carried")
WLOG.tick(1)
check(#lines("carries") == 0, "nothing before 2 s")
WLOG.tick(2.5)
local c = lines("^weapons: ERA_Unit_01_Dep_Air0 %(f16c_common_sv, BP_OP1022_f16c_CP%) carries: ")
check(#c == 1 and c[1]:find("NPC_FCS_PlaneQAAM000 BP_wp_qaam_a0 ammo 4", 1, true) and c[1]:find("NPC_FCS_PlaneMsl000 BP_wp_msl_a0", 1, true),
    "its fire control 2 s on: " .. tostring(c[1]))
check(#lines("watching the enemies' launches") == 1, "the first look primes (nothing counted)")

print("fired")
m1.bHidden = false
WLOG.tick(3)
local f = lines("^weapons: first launch of ")
check(#f == 1 and f[1]:find("BP_wp_msl_a0 by BP_OP1022_f16c_CP (ERA_Unit_01_Dep_Air0, f16c_common_sv)", 1, true), "an enemy's launch: " .. tostring(f[1]))
m2.bHidden = false
WLOG.tick(3.5)
check(#lines("^weapons: first launch of ") == 1, "its second missile: counted, not logged again")
m3.bHidden = false
WLOG.tick(4)
check(#lines("BP_plwp_msl_a0") == 0, "your own: not counted")
m4.bHidden = false
WLOG.tick(4.5)
check(#lines("first launch of BP_wp_vls_mk41 by BP_VE002_aegs_mk41_CP %(not an enemy plane%)") == 1, "a ship's: by its class")
m1.bHidden = true
WLOG.tick(5)
m1.bHidden = false
WLOG.tick(5.5)
check(WLOG.r.fired.BP_wp_msl_a0 == 3, "hidden and shown again: a new launch (3 so far: " .. tostring(WLOG.r.fired.BP_wp_msl_a0) .. ")")

print("the summary")
WLOG.tick(60)
WLOG.tick(64)
local s = lines("^weapons: last %d+ s: ")
check(#s >= 1 and s[#s]:find("BP_wp_msl_a0 x3 (BP_OP1022_f16c_CP 3)", 1, true), "what was launched and by whom: " .. tostring(s[#s]))
check(s[#s] and s[#s]:find("carried by enemies but never fired this run: BP_wp_qaam_a0 (1 planes: ERA_Unit_01_Dep_Air0)", 1, true),
    "carried but never fired: the QAAM (not the gun: bullets aren't watched)")

print("missiles at you")
you.HealthInternal, you.MaxHealth = 1000, 100
function you:K2_GetActorLocation() return { X = 0, Y = 0, Z = 0 } end
local function mslAt(n, addr, owner, x)
    local m = msl(n, addr, owner)
    m.TargetToHome, m.x = you, x
    function m:K2_GetActorLocation() return { X = self.x, Y = 0, Z = 0 } end
    return m
end
local h1, h2, h3 = mslAt("BP_wp_qaam_a0", 301, f16, 300000), mslAt("BP_wp_qaam_a0", 302, f16, 400000), mslAt("BP_wp_2aam_a0", 303, f16, 500000)
local flare = { full = "x.BP_wp_flare_C_9", addr = 399 }
-- (a fleet turret: an Aegis's VLS, sv_spaceport.lua SPORT.turrets)
local vls = { full = "BP_VE002_aegs_mk41_CP_C_7", addr = 41 }
function vls:K2_GetActorLocation() return { X = 800000, Y = 0, Z = 0 } end
local gun = { full = "BP_VE002_aegs_mk45_CP_C_8", addr = 42 }
function gun:K2_GetActorLocation() return { X = 900000, Y = 0, Z = 0 } end
SPORT = { turrets = { [41] = { obj = vls, unit = "SV_Unit_SpAegisA", cls = "BP_VE002_aegs_mk41_CP", shots = 0 },
                      [42] = { obj = gun, unit = "SV_Unit_SpAegisA", cls = "BP_VE002_aegs_mk45_CP", shots = 0 } } }
local v1 = msl("BP_wp_vls_a0", 401, vls)
FA.LiveExplosiveWeapon = { h1, h2, h3, v1 }
local t = 80
local function tick() t = t + 0.5; WLOG.tick(t) end
tick()
h1.bHidden, h2.bHidden, h3.bHidden, v1.bHidden = false, false, false, false
tick()
h1.x, h2.x, h3.x = 5000, 100000, 200000            -- (h1 50 m off you; h2 1 km; h3 2 km)
h2.TargetToHome = flare                             -- (h2 goes after a flare)
tick()
h1.bHidden, you.HealthInternal = true, 600           -- (h1 gone as your health drops: a hit)
tick()
h2.bHidden, h3.bHidden = true, true
for _ = 1, 4 do tick() end
local o = WLOG.r.outRun
check(o.BP_wp_qaam_a0 and o.BP_wp_qaam_a0.n == 2 and o.BP_wp_qaam_a0.hit == 1 and o.BP_wp_qaam_a0.decoyed == 1,
    "two QAAMs at you: one passed 50 m as your health dropped (a hit), one went after a flare (decoyed)")
check(o.BP_wp_2aam_a0 and o.BP_wp_2aam_a0.missed == 1 and math.abs(o.BP_wp_2aam_a0.km - 5.0) < 0.01,
    "a 2AAM that never came near: missed, fired from 5 km")
check(SPORT.turrets[41].shots == 1 and SPORT.turrets[41].atKmN == 1, "the Aegis VLS's missile: its shot counted, your range at fire")
t = t + 61
WLOG.tick(t)
local ml = lines("^missiles at you: last ")
check(#ml >= 1 and ml[#ml]:find("BP_wp_qaam_a0 2 (1 hit, 1 decoyed, 0 missed; from 3.5 km on average)", 1, true), "the summary: " .. tostring(ml[#ml]))
local fl = lines("^fleet: last ")
check(#fl >= 1 and fl[#fl]:find("BP_VE002_aegs_mk41_CP: 1 of 1 fired (1 missiles, you 8.0 km off at fire on average)", 1, true)
    and fl[#fl]:find("BP_VE002_aegs_mk45_CP: 0 of 1 fired (0 missiles), 0 guns seen firing, 1 idle with you inside 25 km", 1, true),
    "the fleet: the VLS fired, the gun mount idle with you in its reach: " .. tostring(fl[#fl]))
SPORT = nil

print("off")
local n = #logs
CFG.log.weapons.enabled = false
m2.bHidden = true; WLOG.tick(70); m2.bHidden = false; WLOG.tick(71)
check(#logs == n, "enabled = false: nothing")

print(fails == 0 and "weaponlog test: all passed" or ("weaponlog test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
