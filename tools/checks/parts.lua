-- parts.lua : the runtime's parts as main.lua runs them, for the Lua tests (tools/checks/*_test.lua). A part split by
-- tools/lua_split_part.py is a family run one after the other: the part, then the MODULES right after it named
-- <part>_<topic> (sv_coop.lua, sv_coop_joiner.lua, ...; tools/lua_parts.py is the Python tools' copy of this).
--   local PARTS = dofile("parts.lua")(MOD, readAll)   (from tools/checks, the tests' folder; readAll: the test's reader)
--   PARTS.family(name)           { "sv_coop.lua", "sv_coop_joiner.lua", ... } (name "sv_coop.lua" or "sv_coop"; a part
--                                with no pieces: { name })
--   PARTS.read(name)             the family's text, its pieces joined in order by "\n" (for the source checks)
--   PARTS.sources(name, edits)   { { name = piece, src = text }, ... }, each edit applied to the piece holding it
--   PARTS.load(name, chunk, edits)  each piece loaded and run in order, as main.lua runs them; chunk: the part's chunk
--                                name ("=sv_coop.lua", "@<dir>/Scripts/sv_core.lua"), each piece's own name in its place
--                                (nil: "=" .. piece)
--   PARTS.dofile(name)           PARTS.load(name, "@<MOD>/Scripts/<name>"), as dofile(<MOD>/Scripts/<name>) was
-- edits: { { pattern, replacement }, ... } as string.gsub's, each applied once, to the first piece its pattern matches.
-- One that matches nothing but whose replacement is already in a piece (the split made that local a global: e.g.
-- "\nlocal function hostSync%(to%)" -> "\nfunction hostSync(to)") is left; any other is an error.
return function(MOD, readAll)
    readAll = readAll or function(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
    local P = {}
    local modules
    local function mods()
        if modules then return modules end
        modules = {}
        local ok, src = pcall(readAll, MOD .. "/Scripts/main.lua")
        local body = ok and src:match("local MODULES = {(.-)\r?\n}") or ""
        for m in body:gmatch('"([%w_]+)",') do modules[#modules + 1] = m end
        return modules
    end
    function P.family(name)
        local base = name:gsub("%.lua$", "")
        local out = { base .. ".lua" }
        local list = mods()
        for i, m in ipairs(list) do
            if m == base then
                local j = i + 1
                while list[j] and list[j]:sub(1, #base + 1) == base .. "_" do out[#out + 1] = list[j] .. ".lua"; j = j + 1 end
                break
            end
        end
        return out
    end
    function P.read(name)
        local t = {}
        for _, f in ipairs(P.family(name)) do t[#t + 1] = readAll(MOD .. "/Scripts/" .. f) end
        return table.concat(t, "\n")
    end
    function P.sources(name, edits)
        local out = {}
        for _, f in ipairs(P.family(name)) do out[#out + 1] = { name = f, src = readAll(MOD .. "/Scripts/" .. f) } end
        for _, e in ipairs(edits or {}) do
            local done = false
            for _, p in ipairs(out) do
                local s, n = p.src:gsub(e[1], e[2], 1)
                if n == 1 then p.src, done = s, true; break end
            end
            if not done then
                local plain = e[2]:find("%%[1-9]") == nil and e[2]:gsub("%%%%", "%%") or nil
                for _, p in ipairs(out) do if plain and p.src:find(plain, 1, true) then done = true; break end end
            end
            assert(done, name .. ": " .. e[1] .. " not found")
        end
        return out
    end
    function P.load(name, chunk, edits)
        local file = name:gsub("^.*[/\\]", "")
        for _, p in ipairs(P.sources(name, edits)) do
            local cn = "=" .. p.name
            if chunk then
                local i = chunk:find(file, 1, true)
                cn = (i and i + #file - 1 == #chunk) and (chunk:sub(1, i - 1) .. p.name) or chunk
            end
            assert(load(p.src, cn))()
        end
    end
    function P.dofile(name) P.load(name, "@" .. MOD .. "/Scripts/" .. name) end
    return P
end
