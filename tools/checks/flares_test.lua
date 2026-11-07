-- flares_test.lua <mod dir> <work dir> (run by tools/checks/flares_test.sh): FLARE PODS and the flares bought past the
-- stock load (the user, 2026-11-07, after a co-op game on 0.74.1: "purchasing flare upgrades from the store didn't seem to
-- work"; Talos's and Happiness's logs: FLARE PODS to 8 / 10, the flares bought up to it, then the game's take-off reload
-- put the count and MaxFlareCount back to stock (2 / 6), UP.apply raised the max again, nothing put the count back, and in
-- the air ammoTick took the rest for shots: "flares 2/8", "6/10"). On the real sv_core, sv_config, sv_flights (ammoTick)
-- and sv_tactical (UP.apply), the game stubbed: the native counts (SV_Ammo / SV_SetAmmo, a count capped at its maximum),
-- the flares' maximum = the weapon activator's MaxFlareCount, the airfield on or off:
--   FLARE PODS tier 2: MaxFlareCount 6 -> 10, A.bays[4] 10 (the reload target, as WEAPON BAYS' A.bays[1..3]);
--   the take-off reload on the ground (max and count back to 6): the max raised again, the count put back to 10 (logged
--     "put back what you had (weapon bays / flare pods): flares 6 -> 10"), nothing taken for shots, 10/10 in the air;
--   the same with UP.apply's 2 s pass raising the max first (the dip never seen): the ground's put-back does it;
--   the reload seen in the air (the max dipped): put back too, no shots;
--   flares fired in the air: still counted (A.caps lowered, STATS.fired);
--   tier 0: no reload target (A.bays[4] nil), so nothing is put back past the aircraft's own load (as before).
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

VERSION = "0.74.4-flares.test"
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
local act = { full = "LivePlayerWeaponActivator_1", addr = 0x9100, MaxFlareCount = 6 }
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

print("the plane appears: the preset's caps")
run(12)
check(A and A.applied and A.caps[4] == cnt[4], string.format("caps applied (flares %d/%d)", cnt[4], act.MaxFlareCount))

local podStep = 0
for _, it in pairs(CFG.shop.items) do if it.role == "upgrade" and it.up == "flares" then podStep = math.floor(it.step) end end
local want = 6 + 2 * podStep

print("FLARE PODS tier 2, then the flares bought up to it (down at the airfield)")
ground = true
RUN.ups.flares = 2
UP.apply(pawn)
check(act.MaxFlareCount == want and A.bays and A.bays[4] == want and A.max[4] == want,
    string.format("MaxFlareCount 6 -> %d, the reload target A.bays[4] %s", want, tostring(A.bays and A.bays[4])))
-- (the shop's purchase: A.caps up to the full load, the count with it: sv_shop.lua's ammo role)
A.caps[4] = want
SV_SetAmmo(4, want)
run(4)
check(cnt[4] == want and A.caps[4] == want, string.format("%d/%d bought", cnt[4], act.MaxFlareCount))

print("the game's take-off reload on the ground: max and count back to stock (6)")
local from = #logs + 1
act.MaxFlareCount, cnt[4] = 6, 6
run(8)
check(act.MaxFlareCount == want, "the max raised again (" .. act.MaxFlareCount .. ")")
check(cnt[4] == want and A.caps[4] == want, string.format("the count put back: %d/%d (was 6)", cnt[4], act.MaxFlareCount))
check(found("put back what you had (weapon bays / flare pods): flares 6 -> " .. want, from) ~= nil, "logged: flares 6 -> " .. want)
ground = false
run(16)
check(cnt[4] == want and A.caps[4] == want and (fired[4] or 0) == 0, string.format("in the air: %d/%d, none taken for shots", cnt[4], act.MaxFlareCount))

print("the reload with UP.apply's 2 s pass first (the max's dip never seen), on the ground")
ground = true
act.MaxFlareCount, cnt[4] = want, 6                  -- (the max already raised again, the count still the stock 6)
run(4)
check(cnt[4] == want and (fired[4] or 0) == 0, string.format("the ground's put-back: %d/%d", cnt[4], act.MaxFlareCount))

print("the reload seen in the air (the max dipped)")
ground = false
act.MaxFlareCount, cnt[4] = 6, 6
run(8)
check(act.MaxFlareCount == want and cnt[4] == want and A.caps[4] == want and (fired[4] or 0) == 0,
    string.format("put back in the air too: %d/%d, no shots", cnt[4], act.MaxFlareCount))

print("flares fired in the air: still counted")
cnt[4] = want - 2
run(4)
check(A.caps[4] == want - 2 and (fired[4] or 0) == 2, string.format("2 fired: cap %d, STATS.fired %d", A.caps[4], fired[4] or 0))

print("tier 0: no reload target, the aircraft's own load")
RUN.ups.flares = 0
UP.apply(pawn)
check(act.MaxFlareCount == 6 and (A.bays[4] == nil), "MaxFlareCount back to stock 6, A.bays[4] nil")
A.caps[4] = 6
cnt[4] = 6
ground = true
act.MaxFlareCount, cnt[4] = 6, 4                    -- (a reload to under what you had: no target, nothing past the max)
run(4)
check(cnt[4] <= act.MaxFlareCount, "nothing put past the aircraft's own maximum")

-- ((2026-11-07) a player: "I was given 28 machine gun pod bullets total"; the user: "the Special Weapon Machine Gun Pods
-- should be an exception") a special that fires rounds keeps its stock load; the other slot keeps the preset's cap
print("a gun pod keeps its stock load")
ground = false
local preset = CFG.ammo.presets[presetName()] or CFG.ammo.presets.standard
local function newPlane(name, sp1, sp2)
    local p = { full = name, addr = 0x9000 + #name, MaxHealth = 100, HealthInternal = 1000,
                PlaneSpWeaponID1 = sp1, PlaneSpWeaponID2 = sp2 }
    pc.Pawn = p
    cnt[1], mx[1] = 144, 144
    cnt[2], mx[2] = 220, 220                            -- (the gun pod: rounds)
    cnt[3], mx[3] = 40, 40                              -- (a missile special)
    return p
end
newPlane("BP_PlayerPlane_PP0001_f15c_C_2", 20, 21)      -- (WID_mgp in slot 1, WID_qaam in slot 2)
local from = #logs
run(12)
check(A and A.applied and A.caps[2] == nil and cnt[2] == 220,
    string.format("special 1, the machine gun pod: its stock 220 rounds kept, no cap (%s)", tostring(cnt[2])))
check(A.caps[3] == preset.special and cnt[3] == math.min(40, preset.special),
    string.format("special 2, a missile: the preset's %d (%d)", preset.special, cnt[3]))
check(found("its stock load kept (rounds, not missiles): special 1 (weapon 20)", from) ~= nil, "logged")
newPlane("BP_PlayerPlane_PP0001_f15c_C_3", 21, 35)      -- (WID_qaam, then WID_pgun in slot 2)
run(12)
check(A.caps[2] == preset.special and A.caps[3] == nil and cnt[3] == 40, "the gun pod (pgun) in slot 2: that slot kept, slot 1 capped")
CFG.ammo.uncapped_specials = {}
newPlane("BP_PlayerPlane_PP0001_f15c_C_4", 20, nil)
run(12)
check(A.caps[2] == preset.special and cnt[2] == preset.special, "uncapped_specials empty: a gun pod capped like any special")
CFG.ammo.uncapped_specials = { "mgp", "pgun" }
pc.Pawn = pawn

print(fails == 0 and "flares test: all passed" or ("flares test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
