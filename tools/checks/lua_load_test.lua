-- lua_load_test.lua <Scripts dir> (run by tools/checks/lua_load_test.sh on a copy of the mod folder): runs main.lua,
-- every part in MODULES' order, outside the game. UE4SS's API and anything else the game gives is a stub (a value
-- that can be called, indexed and used in sums); the runtime's natives (SV_*) are absent, as with an older main.dll,
-- since the runtime checks for them. Catches what lua_check can't: errors in code that runs while the parts load.
local DIR = arg[1]
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
if not ok then print("load test: FAILED: " .. tostring(err)); os.exit(1) end
for _, name in ipairs({ "CFG", "CFG_DEFAULTS", "COOP", "LB", "KILL" }) do
    if rawget(_G, name) == nil then print("load test: FAILED: " .. name .. " missing after loading"); os.exit(1) end
end
if type(COOP.tick) ~= "function" or type(COOP.more) ~= "function" then print("load test: FAILED: COOP incomplete"); os.exit(1) end
print("load test: every part of main.lua loaded")
