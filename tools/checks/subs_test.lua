-- subs_test.lua <mod dir> <work dir> (run by tools/checks/subs_test.sh): config\subtitles.ini (Scripts/sv_config_subs.lua;
-- the user, 2026-11-08: "make it so that I can easily edit all these subtitles", "I want my friend to be able to edit all
-- these subtitles easily") on the real config parts, the game stubbed:
--   no file: the part writes one from CFG's own lines; read back over them it changes nothing (every list, every name);
--   the shipped file (the repo's) reads with no mistake, and CFG then holds its lines;
--   an edited file: a line changed, one added, one taken out, lines moved; an exchange changed, one added, one taken out;
--     a named line, a speaker's name, a new speaker, CHARLENE's thanks; a list emptied with  -  ;
--   mistakes skipped and logged, nothing else touched: an unknown section, a line before any section, a setting's
--     name = value (a countdown), lines into a list of settings (the special rotation) or into a list of exchanges, a
--     named line given text with no speaker, a line with no |;
--   the edits are the shipped defaults (CFG_DEFAULTS has them: the leaderboard and co-op see no difference).
local MOD, WORK = arg[1], arg[2]
local fails = 0
local function check(ok, what) if ok then print("  ok   " .. what) else print("  FAIL " .. what); fails = fails + 1 end end
local function readAll(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function writeAll(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
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
local P = dofile("parts.lua")(MOD, readAll)
local logs = {}
local function load()
    CFG, CFG_DEFAULTS, SUBT = nil, nil, nil
    P.load("sv_core.lua", "@" .. WORK .. "/Scripts/sv_core.lua")
    function log(s) logs[#logs + 1] = s end
    svLevelOn = true
    P.load("sv_config.lua")
end
local function since(from, pat) local n = 0; for i = from, #logs do if logs[i]:find(pat, 1, true) then n = n + 1 end end; return n end
local function same(a, b, path, diffs)
    if type(a) ~= type(b) then diffs[#diffs + 1] = path; return end
    if type(a) ~= "table" then if a ~= b then diffs[#diffs + 1] = path end return end
    for k, v in pairs(a) do same(v, b[k], path .. "." .. tostring(k), diffs) end
    for k in pairs(b) do if a[k] == nil then diffs[#diffs + 1] = path .. "." .. tostring(k) end end
end
local FILE = WORK .. "/config/subtitles.ini"

print("no file: written from CFG's own lines, and it reads back the same")
os.remove(FILE)
local L0 = #logs + 1
load()
check(since(L0, "subtitles: made config\\subtitles.ini from the game's own lines") == 1, "the file made, logged")
local made = readAll(FILE)
local own = deepCopy(CFG)
local st = SUBT.apply(made)
local diffs = {}
same(own, CFG, "CFG", diffs)
check(#diffs == 0 and #st.bad == 0, string.format("read back over CFG: nothing changed (%d differences, %d mistakes; %d lists, %d lines)",
    #diffs, #st.bad, st.sections, st.lines))
check(st.sections >= 140 and st.lines >= 430, "every list in it (" .. st.sections .. " lists, " .. st.lines .. " lines)")
check(made:find("\r\n", 1, true) and made:find("; AC8 Survival Mode: every subtitle line, in one file", 1, true), "Windows line ends, the header")
check(made:find("[hud.subs.speakers]", 1, true) and made:find("\r\nKASKA = INTERCEPT: KASKA\r\n", 1, true), "the speakers' names in it")
check(made:find("[specials.escort.text.say.staff]", 1, true) and made:find("\r\nC = COMONA CONTROL\r\n", 1, true), "the escort's staff names")
check(made:find("\r\nsubtitle = Thank You Pilot,", 1, true), "CHARLENE's thanks in it")

print("the shipped file: no mistakes")
local shipped = readAll(MOD .. "/config/subtitles.ini")
-- git stores the file with LF line ends, and a Windows checkout writes it out with CRLF (the zips carry that one). A
-- checkout with LF (Linux, a cloud session) is read as it is first, then the test goes on with the CRLF form below.
if not shipped:find("\r\n", 1, true) then
    writeAll(FILE, shipped)
    local Lf = #logs + 1
    load()
    check(SUBT.loaded and #SUBT.loaded.bad == 0 and since(Lf, "mistakes skipped") == 0, "the shipped file with LF line ends: no mistake")
    shipped = shipped:gsub("\n", "\r\n")
end
writeAll(FILE, shipped)
local L1 = #logs + 1
load()
check(SUBT.loaded and #SUBT.loaded.bad == 0 and since(L1, "mistakes skipped") == 0, "read at start, no mistake ("
    .. tostring(SUBT.loaded and #SUBT.loaded.bad) .. ")")

print("an edited file")
local sp = CFG.specials
local fishWarn, kaskaHit = #sp.fishing.text.warn, #sp.shuttle.subs.hit
local edited = shipped
local function sub(a, b) local i, j = edited:find(a, 1, true); assert(i, a); edited = edited:sub(1, i - 1) .. b .. edited:sub(j + 1) end
sub("[specials.shuttle.subs.hit.2]\r\nKASKA|If the payload cracks, I want to know before anyone else does.",
    "[specials.shuttle.subs.hit.2]\r\nKASKA|Edited by a friend.\r\nEMBDIR|A line added.")
sub("[specials.shuttle.subs.hit.3]\r\n", "[specials.shuttle.subs.hit.3]\r\n-\r\n")
edited = edited .. "\r\n[specials.shuttle.subs.after.2]\r\nKASKA|A new exchange.\r\nEMBDIR|Its second line.\r\n"
edited = edited .. "\r\n[hud.subs.speakers]\r\nKASKA = KASKA (OVERHEARD)\r\nNEWBIE = A NEW SPEAKER\r\n"
edited = edited .. "\r\n[specials.fishing.text]\r\nsal = SALLY\r\nbigone_first = S|The big one!\r\n"
edited = edited .. "\r\n[specials.escort]\r\nsubtitle = Thanks, pilots.\r\n"
edited = edited .. "\r\n[specials.fishing.text.quiet]\r\n-\r\n"
-- mistakes
edited = edited .. "\r\n[specials.nothing.here]\r\nS|Never read.\r\n"
edited = edited .. "\r\n[specials.shuttle]\r\ncountdown_s = 1\r\n"
edited = edited .. "\r\n[specials]\r\nrotation = shuttle\r\n"
edited = edited .. "\r\n[specials.rotation]\r\nS|Not a line list.\r\n"
edited = edited .. "\r\n[specials.shuttle.subs.hit]\r\nKASKA|Into the exchanges' list.\r\n"
edited = edited .. "\r\n[specials.fishing.text]\r\nbigone_first = no speaker here\r\n"
edited = edited .. "\r\n[specials.fishing.text.warn]\r\njust some words\r\n"
edited = "S|Before any section.\r\n" .. edited
writeAll(FILE, edited)
local rotation = deepCopy(CFG.specials.rotation)
local countdown = CFG.specials.shuttle.countdown_s
local L2 = #logs + 1
load()
sp = CFG.specials
local h = sp.shuttle.subs.hit
check(h[2][1] == "KASKA|Edited by a friend." and h[2][2] == "EMBDIR|A line added." and #h[2] == 2, "an exchange's line changed, one added")
check(#h == kaskaHit - 1, "the exchange with  -  taken out (" .. #h .. " of " .. kaskaHit .. ")")
local a = sp.shuttle.subs.after
check(#a == 2 and a[2][1] == "KASKA|A new exchange." and a[2][2] == "EMBDIR|Its second line.", "an exchange added (the next number)")
check(CFG.hud.subs.speakers.KASKA == "KASKA (OVERHEARD)" and CFG.hud.subs.speakers.NEWBIE == "A NEW SPEAKER", "a speaker renamed, a new one")
check(sp.fishing.text.sal == "SALLY" and sp.fishing.text.bigone_first == "S|The big one!", "a name and a named line")
check(sp.escort.subtitle == "Thanks, pilots.", "CHARLENE's thanks")
check(#sp.fishing.text.quiet == 0, "a list emptied with  -")
check(#sp.fishing.text.warn == fishWarn, "a list with only a mistake in it keeps its lines")
check(sp.shuttle.countdown_s == countdown and #sp.rotation == #rotation and sp.rotation[1] == rotation[1], "no setting changed")
local st2 = SUBT.loaded
local function bad(p) for _, b in ipairs(st2.bad) do if b:find(p, 1, true) then return true end end return false end
check(bad("line 1: a line before any [section]"), "a line before any section: logged")
check(bad("[specials.nothing.here] isn't a list of lines"), "an unknown section: logged")
check(bad("[specials.shuttle] has no line called countdown_s"), "a setting's name = value refused")
check(bad("[specials] has no line called rotation"), "a list setting's name = value refused")
check(bad("[specials.rotation] holds exchanges or settings, not lines"), "lines into a list of settings refused")
check(bad("[specials.shuttle.subs.hit] holds exchanges or settings"), "lines into a list of exchanges refused")
check(bad("bigone_first is a line: SPEAKER|text after the ="), "a named line with no speaker refused")
check(bad("not a line (SPEAKER|text)"), "a line with no | refused")
check(since(L2, "subtitles: config\\subtitles.ini:") == 1 and since(L2, "mistakes skipped)") == 1 and since(L2, "subtitles: line ") >= 8,
      "the counts and each mistake logged")
check(CFG_DEFAULTS.specials.shuttle.subs.hit[2][1] == "KASKA|Edited by a friend." and CFG_DEFAULTS.hud.subs.speakers.NEWBIE == "A NEW SPEAKER",
      "the file's lines are the shipped defaults (CFG_DEFAULTS)")

print("a broken [section] line (2026-11-11: a friend's \"[specials.fishing.text.grade_b]z\")")
do
    local root = deepCopy(CFG_DEFAULTS)
    local ownB = deepCopy(root.specials.fishing.text.grade_b)
    local st3 = SUBT.apply("[specials.fishing.text.grade_a]\r\nS|An A line.\r\n[specials.fishing.text.grade_b]z\r\n"
        .. "S|A B line.\r\nS|Another B line.\r\n[specials.fishing.text.grade_c]\r\nS|A C line.\r\n", root)
    local t = root.specials.fishing.text
    local said = false
    for _, b in ipairs(st3.bad) do if b:find("line 3: a broken [section] line", 1, true) then said = true end end
    check(#t.grade_a == 1 and t.grade_a[1] == "S|An A line.", "the list above keeps only its own lines (none of the broken section's)")
    check(#t.grade_b == #ownB and t.grade_b[1] == ownB[1], "the broken section's list keeps the game's lines")
    check(#t.grade_c == 1 and t.grade_c[1] == "S|A C line.", "the next whole section reads as ever")
    check(said and #st3.bad == 1, "the broken line logged once (" .. table.concat(st3.bad, "; ") .. ")")
end

writeAll(FILE, shipped)
print(fails == 0 and "subs_test: all passed" or ("subs_test: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
