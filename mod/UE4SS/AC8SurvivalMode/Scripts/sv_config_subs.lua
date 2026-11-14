-- sv_config_subs.lua: every subtitle line in one file a person can edit, config\subtitles.ini, read over CFG's own lines
-- at start. Piece 4 of 5 of sv_config.lua's family (sv_config.lua, sv_config_specials.lua, sv_config_arc.lua,
-- sv_config_subs.lua, sv_config_ini.lua), run by main.lua right after the piece before it and before sv_config_ini.lua
-- takes CFG_DEFAULTS: the file's lines are the shipped ones (the leaderboard's edited-run check and co-op's settings
-- sync never see a difference). A name another part uses is a global of this mod's Lua state, its own helpers stay
-- local.
--
-- (2026-11-08) the user: "Can you please make it so that I can easily edit all these subtitles", "I want my friend to be
-- able to edit all these subtitles easily". Every subtitle line is a "SPEAKER|text" string in CFG (the special rounds'
-- text tables); the file names each list by its CFG path:
--   [specials.fishing.text.warn]        a list: its lines, top to bottom, become the list (change, add, remove, reorder)
--   [specials.escort.text.say.go.2]     a list of an exchange list: one exchange (the next number adds one)
--   key = SPEAKER|text                  one line held under a name; key = text for the speaker name lists (PLAIN)
--   -                                   (alone in a section) that list emptied, that exchange taken out
-- Only subtitle lines and the speaker names can change: a section's lines replace a list only when every entry it had was
-- a subtitle line, and `key =` sets only a subtitle line (with one) or a PLAIN name; anything else is logged and skipped.
-- A missing file is written from CFG's own lines (SUBT.text): a player who deletes it gets the game's lines back.
--   SUBT.apply(text [, root])   the file's lines over root (CFG) -> { sections, lines, keys, added, removed, bad = {...} }
--   SUBT.text([root])           the whole file for root's lines (the header, then every list, grouped by special round)
--   SUBT.sections(text)         { [path] = true } for each [section] in a file's text
--   SUBT.isLine(s)              whether s is a subtitle line ("SPEAKER|text")
-- tools/subtitles.py makes, checks, pulls (from the game's install) and merges (new built-in lines) the shipped file.
-- Log: `subtitles: ...`
SUBT = {}                                  -- (its own, made here: tools/checks/lua_load_test.lua stubs every unknown name)
do
local function isLine(s) return type(s) == "string" and s:match("^[%w][%w _%.'%-:]*|") ~= nil end
SUBT.isLine = isLine
-- the plain names the file may change (no SPEAKER| part): who each speaker code is, CHARLENE's thanks
local NAMES = { sal = true, control = true, tower = true, crew = true }
local PLAIN = { ["hud.subs.speakers"] = true, ["specials.escort.text.say.staff"] = true,
                ["specials.fishing.text"] = NAMES, ["specials.festival.text"] = NAMES,
                ["specials.escort"] = { subtitle = true } }
local function plainOk(path, key)
    local p = PLAIN[path]
    return p == true or (type(p) == "table" and p[key] == true)
end
-- the file's groups, in the rounds' order; anything else with lines goes last
local GROUPS = {
    { "specials.shuttle", "SHUTTLE LAUNCH: KASKA's intercepted channel (KASKA and EMBDIR LAUNCH)" },
    { "specials.escort", "THE ESCORT: CHARLENE, YORKE, ROCK, ALI, DANIELLE and Comona (C, T, G: see its staff names)" },
    { "specials.fishing", "GONE FISHIN': SAL and Comona (S = SAL, C = control, T = tower, G = crew chief)" },
    { "specials.festival", "THE FESTIVAL: the town, KMG and Comona" },
    { "specials.valka", "VALKA and AUDREY" },
    { "specials.spaceport", "SPACEPORT RETAKE: the rockets (CTRL = COMONA CONTROL)" },
    { "hud.subs.speakers", "WHO'S WHO: the name shown for each speaker code" },
}
-- (quoted lines, not a long string: tools/checks/ini_check.py reads this family's text)
local HEADER = table.concat({
    "; AC8 Survival Mode: every subtitle line, in one file",
    "; ======================================================================================================================",
    "; Edit any line, save this file, then start the game again: the new lines show from then on.",
    ";",
    "; A line is   SPEAKER|what they say",
    ";   SPEAKER is a short code (the name lists say who each one is: [hud.subs.speakers] at the end, the escort's staff,",
    ";   GONE FISHIN''s and THE FESTIVAL's sal / control / tower / crew) or a name, shown as it is. Keep the | after it.",
    ";   Words in {curly brackets} ({name}, {dir}, {n}, ...) are filled in by the game: leave them as they are.",
    "; A [section] is one list of lines. Its lines, top to bottom, become that list: change them, add new ones, take some",
    ";   out, move them around. The game picks one line of a list, or says them all in order, depending on the moment.",
    ";   A section whose name ends in a number (.1, .2, ...) is one exchange (said together, in order); a section with the",
    ";   next number adds an exchange. A section with only a  -  line takes that list or exchange out.",
    ";   A section left out of this file keeps the game's own lines.",
    "; name = text   changes one line held under a name, or who a speaker code is (in the name lists).",
    "; Lines starting with ; are notes, skipped.",
    ";",
    "; Mistakes are skipped, never fatal: the game's log (logs\\AC8SurvivalMode_lua_<date>.log) lists each one as \"subtitles: line N: ...\".",
    "; Every Survival Mode update brings this file and replaces the one here: send your changes to the mod's author",
    "; (@voidcallsreaper on Discord) before you install a new version. Delete it to get the game's own lines back: the game",
    "; writes it again when it starts.",
    "",
}, "\n")

local function split(path)
    local out = {}
    for c in path:gmatch("[^%.]+") do out[#out + 1] = c:match("^%d+$") and tonumber(c) or c end
    return out
end
-- what a table's array part holds: "lines" (subtitle lines only), "exchanges" (lists of lines only), "empty" or "other"
local function kind(t)
    local n = #t
    if n == 0 then return "empty" end
    local lines, ex = 0, 0
    for i = 1, n do
        local v = t[i]
        if isLine(v) then lines = lines + 1
        elseif type(v) == "table" and #v > 0 then
            local all = true
            for j = 1, #v do if not isLine(v[j]) then all = false end end
            if all then ex = ex + 1 end
        end
    end
    if lines == n then return "lines" end
    if ex == n then return "exchanges" end
    return "other"
end

function SUBT.sections(text)
    local out = {}
    for l in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        local p = l:gsub("\r$", ""):match("^%s*%[%s*(.-)%s*%]%s*$")
        if p then out[p] = true end
    end
    return out
end

function SUBT.apply(text, root)
    root = root or CFG
    local st = { sections = 0, lines = 0, keys = 0, added = 0, removed = 0, bad = {} }
    local function bad(n, why) if #st.bad < 60 then st.bad[#st.bad + 1] = string.format("line %d: %s", n, why) end end
    local cur, drops = nil, {}
    local function finish()
        local c = cur
        cur = nil
        if not (c and c.t) then return end
        if c.dash then
            if c.parentKind == "exchanges" then drops[#drops + 1] = { parent = c.parent, idx = c.idx, path = c.path }
            else for i = #c.t, 1, -1 do c.t[i] = nil end end
            st.removed = st.removed + 1
        elseif #c.list > 0 then
            for i = #c.t, 1, -1 do c.t[i] = nil end
            for i, l in ipairs(c.list) do c.t[i] = l end
            st.lines = st.lines + #c.list
        end
    end
    local n = 0
    for raw in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local l = raw:gsub("\r$", "")
        if n == 1 then l = l:gsub("^\239\187\191", "") end
        local s = l:match("^%s*(.-)%s*$")
        local first = s:sub(1, 1)
        if s == "" or first == ";" or first == "#" then
            -- (a note)
        elseif s:match("^%[.*%]$") then
            finish()
            local path = s:match("^%[%s*(.-)%s*%]$")
            local comps = split(path)
            local t, parent, idx, parentKind, created = root, nil, nil, nil, false
            for i, c in ipairs(comps) do
                local nxt = type(t) == "table" and t[c] or nil
                if i == #comps and type(t) == "table" then parentKind = kind(t) end   -- (before an exchange is added to it)
                if nxt == nil and i == #comps and type(c) == "number" and parentKind == "exchanges" and c == #t + 1 then
                    nxt, created = {}, true
                    t[c] = nxt
                    st.added = st.added + 1
                end
                if type(nxt) ~= "table" then t = nil; break end
                parent, idx = t, c
                t = nxt
            end
            if not t then
                bad(n, "[" .. path .. "] isn't a list of lines in this version: its lines skipped")
                cur = { path = path, t = nil }
            else
                local k = kind(t)
                st.sections = st.sections + 1
                cur = { path = path, t = t, parent = parent, idx = idx, parentKind = parentKind, list = {},
                        lines = (k == "lines") or created, dash = false }
            end
        elseif first == "[" then
            -- ((2026-11-11) a friend's file had "[specials.fishing.text.grade_b]z": not a section, so its lines went into
            -- the list above it, grade A's) a [ line that isn't a whole section: it and its lines skipped
            finish()
            bad(n, "a broken [section] line (something after its ] or no ]): it and its lines skipped")
            cur = { path = s, t = nil }
        elseif not cur then
            bad(n, "a line before any [section]: skipped")
        elseif not cur.t then
            -- (its section isn't known: skipped, said once at the section)
        elseif s == "-" then
            if cur.lines then cur.dash = true else bad(n, "[" .. cur.path .. "] holds more than lines: its  -  skipped") end
        else
            local bar, eq = s:find("|", 1, true), s:find("=", 1, true)
            if eq and (not bar or eq < bar) then
                local key, v = s:match("^([%w_]+)%s*=%s*(.-)$")
                local old = key and cur.t[key]
                if not key or v == "" then
                    bad(n, "a  name = text  line with no name or no text: skipped")
                elseif isLine(old) and isLine(v) then
                    cur.t[key] = v; st.keys = st.keys + 1
                elseif plainOk(cur.path, key) and (type(old) == "string" or (old == nil and PLAIN[cur.path] == true)) then
                    cur.t[key] = v; st.keys = st.keys + 1
                elseif isLine(old) then
                    bad(n, key .. " is a line: SPEAKER|text after the =, it's kept as it was")
                else
                    bad(n, "[" .. cur.path .. "] has no line called " .. key .. ": skipped")
                end
            elseif isLine(s) then
                if cur.lines then cur.list[#cur.list + 1] = s
                else bad(n, "[" .. cur.path .. "] holds exchanges or settings, not lines (its lines go in its numbered sections): skipped") end
            else
                bad(n, "not a line (SPEAKER|text) or a  name = text  line: skipped")
            end
        end
    end
    finish()
    table.sort(drops, function(a, b) return a.idx > b.idx end)
    for _, d in ipairs(drops) do if d.parent[d.idx] ~= nil then table.remove(d.parent, d.idx) end end
    return st
end

-- the file's text for root's lines: each list's section (its lines; a list of exchanges: one section each)
function SUBT.text(root)
    root = root or CFG
    local out = { (HEADER:gsub("\n", "\r\n")) }
    local function w(s) out[#out + 1] = s end
    local done = {}
    local function join(p, k) return p == "" and tostring(k) or (p .. "." .. tostring(k)) end
    local function keysOf(t)
        local ks = {}
        for k in pairs(t) do if type(k) == "string" then ks[#ks + 1] = k end end
        table.sort(ks)
        return ks
    end
    local function walk(t, path, seen)
        if type(t) ~= "table" or seen[t] then return end
        seen[t] = true
        local k = kind(t)
        local named = {}
        for _, key in ipairs(keysOf(t)) do
            local v = t[key]
            if isLine(v) or (type(v) == "string" and plainOk(path, key)) then named[#named + 1] = key .. " = " .. v end
        end
        if #named > 0 or k == "lines" then
            done[path] = true
            if path:match("%.marks%.%d+%.2$") and type(t) == "table" then
                local p = select(1, path:gsub("%.2$", ""))
                local num = root
                for _, c in ipairs(split(p)) do num = type(num) == "table" and num[c] or nil end
                if type(num) == "table" and type(num[1]) == "number" then w("; " .. num[1] .. " seconds left on the countdown") end
            end
            w("[" .. path .. "]")
            for _, x in ipairs(named) do w(x) end
            if k == "lines" then for i = 1, #t do w(t[i]) end end
            w("")
        end
        if k == "exchanges" then w(string.format("; %s: %d exchange%s, each said together", path, #t, #t == 1 and "" or "s")) end
        for i = 1, #t do if type(t[i]) == "table" then walk(t[i], join(path, i), seen) end end
        for _, key in ipairs(keysOf(t)) do if type(t[key]) == "table" then walk(t[key], join(path, key), seen) end end
    end
    local seen = {}
    for _, g in ipairs(GROUPS) do
        local t = root
        for _, c in ipairs(split(g[1])) do t = type(t) == "table" and t[c] or nil end
        if type(t) == "table" then
            w("")
            w("; " .. string.rep("=", 116))
            w("; " .. g[2])
            w("; " .. string.rep("=", 116))
            w("")
            walk(t, g[1], seen)
        end
    end
    -- anything else with lines (a later special's), so nothing is left out
    local before = #out
    w("")
    w("; " .. string.rep("=", 116))
    w("; OTHER LINES")
    w("; " .. string.rep("=", 116))
    w("")
    local mark = #out
    walk(root, "", seen)
    if #out == mark then for i = #out, before + 1, -1 do out[i] = nil end end
    return table.concat(out, "\r\n") .. "\r\n"
end

-- at start: the file over CFG's own lines, or the file written from them
local dir = type(SCRIPT_DIR) == "string" and (SCRIPT_DIR .. "..\\config\\") or nil
if dir then
    local f = io.open(dir .. "subtitles.ini", "rb")
    if f then
        local text = f:read("a") or ""
        f:close()
        local ok, st = pcall(SUBT.apply, text)
        if not ok then
            log("subtitles: config\\subtitles.ini couldn't be read (" .. tostring(st) .. "): the game's own lines")
        else
            log(string.format("subtitles: config\\subtitles.ini: %d lists, %d lines, %d named lines%s%s%s", st.sections, st.lines,
                st.keys, st.added > 0 and string.format(", %d exchanges added", st.added) or "",
                st.removed > 0 and string.format(", %d taken out", st.removed) or "",
                #st.bad > 0 and string.format(" (%d mistakes skipped)", #st.bad) or ""))
            for i = 1, math.min(#st.bad, 20) do log("subtitles: " .. st.bad[i]) end
            SUBT.loaded = st
        end
    else
        local ok, text = pcall(SUBT.text)
        local w = ok and io.open(dir .. "subtitles.ini", "wb") or nil
        if w then
            w:write(text)
            w:close()
            log("subtitles: made config\\subtitles.ini from the game's own lines")
        elseif not ok then
            log("subtitles: config\\subtitles.ini couldn't be made (" .. tostring(text) .. ")")
        end
    end
end
end
