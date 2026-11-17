-- restart_drop_test.lua <Scripts dir> <want: dev | release> (run by tools/checks/restart_drop_test.sh): a mission restart
-- from the pause menu (sv_main.lua's restart check, then its level-load reset) drops the parts in RESTART_DROPS (sv_core.lua
-- levelRestartDrop, 0.74.129: the user's crash of 0.74.128 after a restart in round 30, the old fleet paid as sunk).
-- Loads every part as lua_load_test.lua does (UE4SS's API a stub), then:
--   dev:     RESTART_DROPS holds the fleet's parts; a restart drops IFLEET.cur, runs RESTART_PUTBACK first, logs one line
--            naming the parts; a put-back or a drop that raises is said and the rest still run; parts not named keep theirs
--   release: RESTART_DROPS empty (the fleet's parts stripped), a restart logs "none here" and raises nothing
local DIR, WANT = arg[1], arg[2] or "dev"
local stub
local function s() return stub end
stub = setmetatable({}, {
    __index = s, __newindex = function() end, __call = s, __len = function() return 0 end,
    __add = s, __sub = s, __mul = s, __div = s, __mod = s, __unm = s, __idiv = s, __pow = s,
    __concat = function(a, b) return tostring(a == stub and "stub" or a) .. tostring(b == stub and "stub" or b) end,
    __lt = function() return false end, __le = function() return false end, __tostring = function() return "stub" end,
})
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" and k:match("^SV_") then return nil end
    return stub
end })
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("restart test: FAILED to load: " .. tostring(err)); os.exit(1) end

local fails = 0
local function check(c, what)
    print((c and "  ok   " or "  FAIL ") .. what)
    if not c then fails = fails + 1 end
end
local lines = {}
log = function(m) lines[#lines + 1] = tostring(m) end
local function said(pat) for _, l in ipairs(lines) do if l:find(pat) then return l end end return nil end

check(type(rawget(_G, "levelRestartDrop")) == "function", "levelRestartDrop is there")
check(type(rawget(_G, "RESTART_DROPS")) == "table" and type(rawget(_G, "RESTART_PUTBACK")) == "table", "RESTART_DROPS and RESTART_PUTBACK are tables")

if WANT == "dev" then
    for _, n in ipairs({ "fleet", "fleet ships", "fleet storm", "fleet round", "fleet surfacing", "fleet lasers" }) do
        check(RESTART_DROPS[n] == true and type(LEVEL_DROPS[n]) == "function", "'" .. n .. "' runs on a restart, and has a drop")
    end
    check(type(RESTART_PUTBACK["fleet storm"]) == "function", "the fleet storm puts its layout back first")
    -- order: the put-backs before the drops
    local order = {}
    local realStorm = RESTART_PUTBACK["fleet storm"]
    RESTART_PUTBACK["fleet storm"] = function(why) order[#order + 1] = "putback"; return realStorm(why) end
    local realShips = LEVEL_DROPS["fleet ships"]
    LEVEL_DROPS["fleet ships"] = function(why) order[#order + 1] = "drop"; return realShips(why) end
    -- a put-back and a drop that raise: said, the rest run
    RESTART_PUTBACK["zz raises"] = function() error("boom") end
    RESTART_DROPS["zz drop raises"] = true
    LEVEL_DROPS["zz drop raises"] = function() error("bang") end
    -- a part not named keeps its own (a restart keeps the level)
    local kept = true
    LEVEL_DROPS["zz not named"] = function() kept = false end
    IFLEET.cur = { ships = {}, t = 92 }
    local okR, names = pcall(levelRestartDrop, "the mission restarted")
    check(okR, "levelRestartDrop raises nothing" .. (okR and "" or (": " .. tostring(names))))
    check(IFLEET.cur == nil, "the old fleet dropped (no ghost ships to pay as sunk)")
    check(order[1] == "putback" and order[2] == "drop", "the put-back ran before the drops (" .. table.concat(order, ", ") .. ")")
    check(kept, "a part not in RESTART_DROPS keeps its own")
    check(said("zz raises's put%-back error") ~= nil, "a put-back that raises is said")
    check(said("zz drop raises's drop error") ~= nil, "a drop that raises is said")
    local l = said("^restart: the mission's reload took")
    check(l ~= nil and l:find("fleet ships", 1, true) and l:find("put back first: fleet storm", 1, true) ~= nil,
        "one line names the parts dropped and put back: " .. tostring(l))
else
    check(next(RESTART_DROPS) == nil, "no part named in a release (the fleet's parts stripped)")
    check(next(RESTART_PUTBACK) == nil, "nothing to put back in a release")
    local okR = pcall(levelRestartDrop, "the mission restarted")
    check(okR and said("none here") ~= nil, "a restart says none here and raises nothing")
end
if fails > 0 then print("restart test (" .. WANT .. "): " .. fails .. " FAILED"); os.exit(1) end
print("restart test (" .. WANT .. "): all passed")
