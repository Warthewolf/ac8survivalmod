-- subs_tool.lua <mod dir> <work dir> <mode> [file] (run by tools/subtitles.py): the subtitles file against the real
-- config parts (sv_config.lua's family, sv_config_subs.lua among them), the game stubbed.
--   gen          <work>/config/subtitles.ini written from CFG's own lines (the work dir holds none: the part writes it)
--   check FILE   FILE's lines over CFG's own: its counts, every mistake ("bad: line N: ..."), every list of CFG's own
--                lines that FILE leaves out ("missing: <path>"); exit 1 on a mistake
local MOD, WORK, MODE, FILE = arg[1], arg[2], arg[3], arg[4]
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
do
    local rawOpen = io.open
    io.open = function(p, m) return rawOpen((tostring(p):gsub("\\", "/")), m) end
end
local FNm = { __index = { ToString = function(self) return self.s end }, __tostring = function(self) return self.s end }
function FName(s) return setmetatable({ s = tostring(s) }, FNm) end
function NotifyOnNewObject() end
function StaticFindObject() return nil end
function FindAllOf() return nil end
function FindFirstOf() return nil end
function RegisterKeyBind() end
function ExecuteInGameThread(f) f() end
os.remove(WORK .. "/config/subtitles.ini")                 -- (CFG's own lines: the part writes the file from them)
local P = dofile("parts.lua")(MOD, readAll)
P.load("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
local logs = {}
function log(s) logs[#logs + 1] = s end                    -- (after sv_core, which has its own)
svLevelOn = true
P.load("sv_config.lua")
local made = false
for _, l in ipairs(logs) do if l:find("subtitles: made config", 1, true) then made = true end end
if not made then print("error: the part didn't write the file from CFG's own lines"); os.exit(2) end
if MODE == "gen" then
    print("made " .. WORK .. "/config/subtitles.ini")
    os.exit(0)
end
if MODE ~= "check" or not FILE then print("usage: subs_tool.lua <mod> <work> gen | check <file>"); os.exit(2) end
local own = readAll(WORK .. "/config/subtitles.ini")
local text = readAll(FILE)
local st = SUBT.apply(text)
print(string.format("lists %d, lines %d, named lines %d, exchanges added %d, taken out %d, mistakes %d",
    st.sections, st.lines, st.keys, st.added, st.removed, #st.bad))
for _, b in ipairs(st.bad) do print("bad: " .. b) end
local have = SUBT.sections(text)
local miss = {}
for p in pairs(SUBT.sections(own)) do if not have[p] then miss[#miss + 1] = p end end
table.sort(miss)
for _, p in ipairs(miss) do print("missing: " .. p) end
os.exit(#st.bad > 0 and 1 or 0)
