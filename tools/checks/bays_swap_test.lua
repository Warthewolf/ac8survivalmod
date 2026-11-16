-- bays_swap_test.lua <mod dir> <work dir> (run by tools/checks/bays_swap_test.sh): WEAPON BAYS after a special weapon
-- swapped in the hangar (NotMexi's log of 0.74.36, 2026-11-12: WEAPON BAYS tier 2, HCAA alone 36 -> 72; HCAA with LACM
-- 18 -> 36 and 10 -> 20; then HCAA alone again, stock 36 = the last load Survival set, so UP.apply took it for its own
-- and kept the old stock 18: 36/36 for the rest of the run; and special 2's old maximum kept with no special 2). On the
-- real sv_core, sv_config, sv_flights (ammoTick) and sv_tactical (UP.apply), the game stubbed as flares_test.lua's:
--   the swap seen by special 2's slot going away: back to HCAA alone, 72 (the activator's SpecialWeaponConfigs
--     readable or not: it's only logged);
--   a slot this loadout lacks: no maximum kept for it (A.max / A.bays), the real shop's FULL REARM and Special row skip it;
--   no swap: the game's reload to stock raised once (36 -> 72), and an unchanged raised load never raised again;
--   the review of 2026-11-14: the activator's list changing a pass after the loads raises nothing twice; a pass where
--     no slot reads (-7 for all, missiles too) forgets nothing and raises nothing twice.
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local PARTS = dofile("parts.lua")(MOD, readAll)            -- (a part and its pieces: tools/checks/parts.lua)
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
do                                    -- (the runtime's paths are Windows ones: SCRIPT_DIR .. "..\\config\\")
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
writeAll(WORK .. "/config/survival.default.ini", readAll(MOD .. "/config/survival.default.ini"))

local clock = 1000
os.clock = function() return clock end           -- luacheck: ignore

VERSION = "0.74.68-bays.test"
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
function NotifyOnNewObject() end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function SV_UnitAlive() return 0 end
function SV_SetAircraft() return 1 end
function SV_SetLevel() return 1 end
function SV_Spawn() return 1 end
function SV_Event() return 1 end
SETUP = { enemyX = function() return 1 end, specialsX = function() return 1 end, breakS = function() return 20 end,
          skillAdd = function() return 0 end }

-- the game: a player plane, its weapon activator (MaxFlareCount = the flares' maximum), the native counts
local pawn = { full = "BP_PlayerPlane_PP0016_x40a_C_1", addr = 0x9000, MaxHealth = 100, HealthInternal = 1000 }
local act = { full = "LivePlayerWeaponActivator_1", addr = 0x9100, MaxFlareCount = 6, SpecialWeaponConfigs = nil }
function act:GetOwner() return pawn end
local pc = { full = "PlayerController_0", addr = 0x9200, Pawn = pawn }
local cnt = { [0] = 800, 30, 14, -1, 6 }
local mx = { [0] = 800, 144, 32, -1 }
local function maxOf(k) if k == 4 then return act.MaxFlareCount end return mx[k] end
function SV_Ammo(k, wantMax) if wantMax then return maxOf(k) end return cnt[k] end
function SV_SetAmmo(k, n)
    if cnt[k] == nil or cnt[k] < 0 then return -1 end
    if n < 0 then n = maxOf(k) end
    cnt[k] = math.min(n, maxOf(k))
    return cnt[k]
end
function SV_AmmoMax(k, n) mx[k] = n; return n end
function SV_FreeRestock() return 0 end
function FindAllOf(cls) if cls == "LivePlayerWeaponActivator" then return { act } end return {} end
local ground = false

local function part(name, chunk) PARTS.load(name, chunk) end   -- (the part and its pieces)
part("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end
function valid(o) return type(o) == "table" and not o.gone end
function nameOf(o) return type(o) == "table" and (o.full or "?") or "?" end
function addrOf(o) return type(o) == "table" and o.addr or nil end
function liveObj(o) return valid(o) end
part("sv_config.lua")
part("sv_rows.lua"); part("sv_ai.lua"); part("sv_hud.lua"); part("sv_spawn.lua"); part("sv_rounds.lua")
part("sv_flights.lua")
-- (shopBuy is a local of sv_shop.lua's block: made a global here so the test can press a row)
PARTS.load("sv_shop.lua", nil, { { "\nlocal shopTexts, shopBuy ", "\nlocal shopTexts " } })
part("sv_tactical.lua")
function playerOnAirfield() return ground end
local fired = {}
STATS = STATS or {}
STATS.fired = function(k, n) fired[k] = (fired[k] or 0) + n end
local function found(pat, from) for i = #logs, from or 1, -1 do if logs[i]:find(pat, 1, true) then return logs[i] end end return nil end

D = { round = 10, now = 100 }
RUN = { ups = {}, dirty = false }
CFG.ammo.enabled, CFG.upgrades.enabled = true, true
local tick = 0
local function run(n) for _ = 1, n do tick = tick + 1; clock = clock + 0.25; ammoTick(tick, pc) end end

local function cls(n) return { full = "BlueprintGeneratedClass /Game/Blueprints/Weapon/" .. n .. "." .. n .. "_C" } end
local HCAA, HCAA2, LACM = cls("BP_plwp_hcaa"), cls("BP_plwp_hcaa_x2"), cls("BP_plwp_lacm")
local readable = true
local function mount(list, m2, m3)                  -- (the hangar's pick: the game's stock loads, full)
    act.SpecialWeaponConfigs = readable and list or nil
    mx[2], cnt[2] = m2, m2
    mx[3], cnt[3] = m3, m3
end
local function config(...) local t = {} for _, c in ipairs({ ... }) do t[#t + 1] = { WeaponClass = c } end return t end

print("the plane appears: HCAA alone (36), no special 2")
mount(config(HCAA), 36, -7)
run(12)
check(A and A.applied, "caps applied")
ground = true
RUN.ups.bays = 2
UP.apply(pawn)
check(mx[2] == 72 and A.max[2] == 72 and A.bays[2] == 72, "WEAPON BAYS tier 2: HCAA 36 -> 72 (" .. tostring(mx[2]) .. ")")
check(A.max[3] == nil and A.bays[3] == nil, "no special 2: nothing kept for it")

print("no swap: the game's reload puts the stock 36 back; raised once, never twice")
mx[2] = 36
UP.apply(pawn)
check(mx[2] == 72, "36 -> 72 again (" .. mx[2] .. ")")
UP.apply(pawn); UP.apply(pawn)
check(mx[2] == 72, "an unchanged raised load stays 72 (" .. mx[2] .. ")")

local function swaps(label)
    print(label .. ": HCAA with LACM (18 / 10)")
    local from = #logs + 1
    mount(config(HCAA2, LACM), 18, 10)
    UP.apply(pawn)
    check(mx[2] == 36 and mx[3] == 20, string.format("18 -> %d, 10 -> %d", mx[2], mx[3]))
    check(A.max[3] == 20 and A.bays[3] == 20, "special 2's maximum 20")
    print(label .. ": back to HCAA alone (stock 36, the load Survival set last)")
    mount(config(HCAA), 36, -7)
    UP.apply(pawn)
    check(mx[2] == 72 and A.max[2] == 72 and A.bays[2] == 72, "HCAA alone raised to 72 (" .. tostring(mx[2]) .. "), not left at 36")
    check(A.max[3] == nil and A.bays[3] == nil, "special 2 gone: its maximum dropped (" .. tostring(A.max[3]) .. ")")
    check(found("the special weapons' stock loads read again", from) ~= nil, "logged")
    UP.apply(pawn); UP.apply(pawn)
    check(mx[2] == 72, "and never raised past it (" .. mx[2] .. ")")
    run(8)                                            -- (ammoTick's 2 s maxima pass)
    check(A.max[2] == 72 and A.max[3] == nil, "ammoTick's maxima: 72, special 2 none")
end
swaps("the classes readable")
readable = false
swaps("SpecialWeaponConfigs unreadable")

readable = true
print("the review (2026-11-14): the activator's list changing a pass after the loads raises nothing twice")
mount(config(HCAA), 36, -7)
UP.apply(pawn)
mount(config(HCAA), 24, -7)                           -- (a single special with its own stock 24: the list not yet updated)
UP.apply(pawn)
check(mx[2] == 48, "24 -> 48 (" .. mx[2] .. ")")
act.SpecialWeaponConfigs = config(LACM)                -- (the list follows a pass later)
UP.apply(pawn); UP.apply(pawn)
check(mx[2] == 48, "the list's change raises nothing again (" .. mx[2] .. ")")

print("the review: a pass where the slots can't be read (-7 for every slot) changes nothing")
mount(config(HCAA2, LACM), 18, 10)
UP.apply(pawn)
check(mx[2] == 36 and mx[3] == 20, "HCAA with LACM: 36 / 20")
local keep = { mx[1], mx[2], mx[3] }
mx[1], mx[2], mx[3] = -7, -7, -7
UP.apply(pawn)
run(8)
check(A.max[2] == 36 and A.max[3] == 20 and A.bays[2] == 36 and A.bays[3] == 20, "nothing forgotten while unreadable")
mx[1], mx[2], mx[3] = keep[1], keep[2], keep[3]
UP.apply(pawn); UP.apply(pawn)
check(mx[2] == 36 and mx[3] == 20, string.format("read again: 36 / 20, not raised twice (%d / %d)", mx[2], mx[3]))

print("FULL REARM and the STORE's Special row once special 2 is gone (the real sv_shop)")
mount(config(HCAA), 36, -7)
UP.apply(pawn)
run(8)
A.caps[2], A.caps[3] = 60, 5                          -- (special 1 short of 72; a count left from the old loadout)
cnt[2] = 60
RUN.msg, RUN.credits, RUN.spent, RUN.bought = RUN.msg or {}, 1000000, 0, {}
local from = #logs + 1
local okB, errB = pcall(shopBuy, "Rearm")
local line = found("shop: Rearm:", from) or tostring(errB)
check(okB and line:find("special 1 +12", 1, true) ~= nil and not line:find("special 2", 1, true),
    "FULL REARM: special 1 +12, nothing for a special 2 that's gone (" .. line .. ")")
from = #logs + 1
local okS, errS = pcall(shopBuy, "Special")
line = found("shop: Special:", from) or tostring(errS)
check(okS and line:find("FULL LOAD", 1, true) ~= nil, "Special: at full load with special 1 72/72 (" .. line .. ")")

print(fails == 0 and "bays swap test: all passed" or ("bays swap test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
