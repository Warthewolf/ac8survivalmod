-- sv_plugins_env.lua: each add-on's environment (its allow-list, its natives, NotifyOnNewObject for add-ons), and
-- finding and loading the add-ons (Mods\AC8SurvivalAddons). Piece 3 of 3 of sv_plugins.lua (sv_plugins.lua,
-- sv_plugins_api.lua, sv_plugins_env.lua), split by tools/lua_split_part.py and run by main.lua right after the piece
-- before it: a name another part uses is a global of this mod's Lua state, its own helpers stay local.
do  -- (sv_plugins.lua's do block, continued: this piece's own helpers stay local to it)
local pcall = PLUGINS.pcall                        -- (sv_plugins.lua's pcall, handed on)
if debug and debug.getinfo then PLUGINS.ownSrc[debug.getinfo(1, "S").source] = true end   -- (Survival's code: the hook)

    -- ---------------------------------------------------------------------------------------- each add-on's environment
    -- An add-on runs in an environment of its own, never Survival's globals (_G): what it sets stays in it, and what it
    -- reads comes from it, else from its allow-list below. Lua's base functions, COPIES of string / table / math /
    -- utf8 (no shared library table: string.format = nil changes its own copy only), os.clock / time / date /
    -- difftime, io.open / io.lines for reading, collectgarbage("count"), load / loadfile / dofile for text chunks in
    -- its own environment, a getmetatable that answers for tables only (the string metatable leads back to the real
    -- string library), no debug library at all, no coroutine (a loop in one would escape the runaway hook). UE4SS's
    -- FName / FText, and FindFirstOf / FindAllOf / StaticFindObject / NotifyOnNewObject guarded: they refuse while the
    -- level goes, Survival's walkHold() holds or the engine frees objects (walkBusy). Its native mod's functions: C functions named in its folder's
    -- natives.txt (or def.requires) with a prefix of capitals and _ that isn't Survival's SV_. SVP: a copy of its own.
    -- Nothing reaches PLUGINS, LB, D, CFG, Survival's functions, LoopAsync, ExecuteInGameThread, ExecuteWithDelay,
    -- RegisterKeyBind, RegisterHook, os.execute or io.popen.
    local G = _G
    local dbg = debug                                    -- (the framework's own: the runaway hook, a native's kind)
    local function copyOf(t, drop)
        local c = {}
        for k, v in G.pairs(t or {}) do if not (drop and drop[k]) then c[k] = v end end
        return c
    end
    local function walkHeld()
        if levelGoing and levelGoing() then return true end
        if type(walkHold) == "function" then local ok, w = pcall(walkHold); return ok and w ~= nil and w ~= false end
        return false
    end
    PLUGINS.walkHeld = walkHeld
    -- (the object walks, FindAllOf / FindFirstOf and StaticFindObject: also while the engine frees objects, sv_core.lua
    -- walkBusy's SV_GcBusy. UE4SS's Lua StaticFindObject is a walk too: UObjectGlobals::FindObject -> ForEachUObject,
    -- reading each object's Outer; round 12 P1's crash of a mod run on this API's line (20261113-101700-5e40ab6) faulted
    -- there, in UObject::GetOutermost, on an Outer already freed while the engine purged)
    local function walksBusy()
        if walkHeld() then return true end
        if type(walkBusy) == "function" then local ok, w = pcall(walkBusy); return ok and w ~= nil and w ~= false end
        return false
    end
    PLUGINS.walksBusy = walksBusy
    local function readMode(mode)
        mode = mode == nil and "r" or mode
        return type(mode) == "string" and (mode == "r" or mode == "rb")
    end
    -- natives: a C function (not Lua), a name with a capitals prefix and _ ("MYADDON_Ready"), never Survival's SV_
    local function nativeOk(name)
        if type(name) ~= "string" or not name:match("^%u[%u%d]*_[%w_]*$") or name:sub(1, 3) == "SV_" then return false end
        local f = rawget(G, name)
        if type(f) ~= "function" then return false end
        local ok, info = pcall(dbg.getinfo, f, "S")
        return ok and type(info) == "table" and info.what == "C"
    end
    local function declared(p, name)
        local d = p.natives or {}
        if d[name] then return true end
        for _, pre in ipairs(d.prefixes or {}) do if name:sub(1, #pre) == pre then return true end end
        return false
    end
    local function readNatives(p, path)
        p.natives = p.natives or { prefixes = {} }
        local f = path and io.open(path, "r")
        if not f then return 0 end
        local n = 0
        for line in f:lines() do
            local w = line:gsub("[#;].*$", ""):match("^%s*(.-)%s*$")
            if w:match("^%u[%u%d]*_[%w_]*%*$") then p.natives.prefixes[#p.natives.prefixes + 1] = w:sub(1, -2); n = n + 1
            elseif w:match("^%u[%u%d]*_[%w_]*$") then p.natives[w] = true; n = n + 1
            elseif w ~= "" then plog(p, "natives.txt: \"" .. w .. "\" left out (a native's name: capitals, _, then letters)") end
        end
        f:close()
        return n
    end

    -- NotifyOnNewObject for add-ons: one UE4SS registration per class, Survival's, made when an add-on first asks for
    -- that class; one that UE4SS refuses (a class not loaded yet: add-ons load at the main menu) answers false, keeps
    -- nothing and says so once, and can be asked again later (at runStart, say). UE4SS calls it on the thread that
    -- constructs the object, inside the game's construction of it (an SV_Spawn of Survival's, say), so it only keeps the
    -- object, and runs none of Survival's Lua there (the rule of sv_allies.lua partsNew): the next PLUGINS.tick hands
    -- it, once, to each add-on's callback, guarded (a pcall, the stall timing), if it's still the engine's live object of
    -- that class. NOTIFY_MAX objects of a class wait at most (a broad class makes many: the rest are dropped, said);
    -- NOTIFY_CLASSES classes in all. One callback an add-on a class: asking again replaces it. A tick that finds the
    -- walks held (the level going or loading) or co-op open drops what waits, unhanded; a callback is dropped once its
    -- add-on is switched off, and every add-on's at the level's teardown (an add-on asks again in the next level)
    local NOTIFY_MAX, NOTIFY_CLASSES = 256, 64
    local notifyFns, notifyReg, notifyQ, notifyCls = {}, {}, {}, {}
    local notifyN = 0
    local function addonNotify(p)
        return function(cls, fn)
            if type(cls) ~= "string" or type(fn) ~= "function" or p.off or walkHeld() then return false end
            if not notifyReg[cls] then
                if type(NotifyOnNewObject) ~= "function" then return false end
                if notifyN >= NOTIFY_CLASSES then
                    if not p.notifyMaxSaid then p.notifyMaxSaid = true; plog(p, "NotifyOnNewObject: " .. NOTIFY_CLASSES .. " classes at most; refused") end
                    return false
                end
                local ok, err = pcall(NotifyOnNewObject, cls, function(o)
                    local l = notifyFns[cls]
                    if not (l and l[1]) then return end
                    local q = notifyQ[cls]
                    if not q then q = {}; notifyQ[cls] = q end
                    if #q < NOTIFY_MAX then q[#q + 1] = o else q.dropped = (q.dropped or 0) + 1 end
                end)
                if not ok then
                    p.notifySaid = p.notifySaid or {}
                    if not p.notifySaid[cls] then
                        p.notifySaid[cls] = true
                        plog(p, "NotifyOnNewObject " .. cls .. ": UE4SS refused it (" .. str(err) .. "): not asked; ask again once the class is loaded")
                    end
                    return false
                end
                notifyReg[cls], notifyN = true, notifyN + 1
            end
            local l = notifyFns[cls] or {}
            notifyFns[cls] = l
            local e = { p = p, fn = guard(p, "NotifyOnNewObject " .. cls, fn) }
            for i = 1, #l do if l[i].p == p then l[i] = e; return true end end   -- (asked again: replaced)
            l[#l + 1] = e
            return true
        end
    end
    PLUGINS.dropNotify = function(p)                       -- (p nil: every add-on's, the level's teardown)
        for cls, l in pairs(notifyFns) do
            local kept = {}
            if p then for _, e in ipairs(l) do if e.p ~= p then kept[#kept + 1] = e end end end
            notifyFns[cls] = kept
        end
        if not p then notifyQ, notifyCls = {}, {} end       -- (the classes found again: one of a level's may be freed)
    end
    -- (PLUGINS.tick, the game thread) the objects made since the last tick, to the add-ons' callbacks: each one still
    -- live, and of its class (another object can be at a freed one's address by now); a callback added meanwhile waits
    -- for the next object. Held walks or co-op open at a tick: the objects waiting are dropped, not handed over
    local function notifyCls1(cls)                         -- (the class, kept while live; nil: not found, asked again)
        local c = notifyCls[cls]
        if c ~= nil and liveObj(c) then return c end
        local ok, f = pcall(PLUGINS.find or StaticFindObject, cls)
        notifyCls[cls] = (ok and valid(f)) and f or nil
        return notifyCls[cls]
    end
    function PLUGINS.notifyTick()
        if walkHeld() or coopOpen() then notifyQ = {}; return end
        local q0 = notifyQ
        notifyQ = {}
        for cls, q in pairs(q0) do
            local l = notifyFns[cls] or {}
            local n = #l
            if q.dropped then
                local line = string.format("NotifyOnNewObject %s: %d objects since the last tick, %d at most: %d dropped"
                    .. " (ask for a narrower class)", cls, #q + q.dropped, NOTIFY_MAX, q.dropped)
                for i = 1, n do plog(l[i].p, line) end
            end
            local c = notifyCls1(cls)
            if c == nil and #q > 0 then                      -- (no class to ask IsA of: nothing handed over, said once)
                for i = 1, n do
                    local e = l[i]
                    if not e.noCls then e.noCls = true; plog(e.p, "NotifyOnNewObject " .. cls .. ": its class isn't found: nothing handed over") end
                end
                q = {}
            end
            local seen = {}                                  -- (an object UE4SS told twice: handed over once)
            for _, o in ipairs(q) do
                local ok = liveObj(o)
                local k = ok and keyOf(o) or nil
                if k ~= nil then if seen[k] then ok = false else seen[k] = true end end
                if ok and c then local okA, isA = pcall(function() return o:IsA(c) end); ok = okA and isA == true end
                if ok then for i = 1, n do local e = l[i]; if not e.p.off then e.fn(o) end end end
            end
        end
    end

    -- the environment of add-on p (its folder dir); PLUGINS.extra: names a test gives every add-on (nil in Survival)
    local function envFor(p)
        local E
        local A = {}
        for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "select", "tonumber", "tostring", "type",
                             "rawequal", "rawget", "rawlen", "rawset", "print", "_VERSION" }) do
            A[k] = G[k]
        end
        -- (its pcall / xpcall: a runaway of the call in progress passes straight through them, so an add-on can't catch
        -- its way out of the runaway limit; xpcall's handler isn't called for it)
        A.pcall = function(f, ...)
            local r = table.pack(G.pcall(f, ...))
            if frames.runaway then error(frames.runaway, 0) end
            return table.unpack(r, 1, r.n)
        end
        A.xpcall = function(f, h, ...)
            if type(h) ~= "function" then error("bad argument #2 to 'xpcall' (function expected)", 2) end
            local r = table.pack(G.xpcall(f, function(e) if frames.runaway then return e end return h(e) end, ...))
            if frames.runaway then error(frames.runaway, 0) end
            return table.unpack(r, 1, r.n)
        end
        -- (no __gc: a finalizer runs at whatever garbage-collection step comes next, inside Survival's own code, with
        -- hooks off and its error a warning: outside every guard. Lua 5.4 marks a table for finalization only when its
        -- metatable has __gc at setmetatable, so refusing it here is enough)
        A.setmetatable = function(t, mt)
            if type(mt) == "table" and rawget(mt, "__gc") ~= nil then
                error("setmetatable: an add-on's table can't have a __gc (a finalizer runs outside the API's guard)", 2)
            end
            return G.setmetatable(t, mt)
        end
        A.getmetatable = function(t) if type(t) == "table" then return G.getmetatable(t) end return nil end
        A.string = copyOf(string, { dump = true })
        A.table = copyOf(table)
        A.math = copyOf(math, { randomseed = true })        -- (Survival's random sequence is its own)
        A.utf8 = copyOf(utf8)
        A.os = { clock = os.clock, time = os.time, date = os.date, difftime = os.difftime }
        A.io = {
            open = function(path, mode)
                if not readMode(mode) then return nil, "an add-on opens files for reading only", 13 end
                return io.open(path, mode or "r")
            end,
            lines = function(path, ...) if path == nil then return nil end return io.lines(path, ...) end,
        }
        A.collectgarbage = function(opt, ...)
            if opt == "count" then return collectgarbage("count") end
            error("collectgarbage: an add-on may only ask \"count\"", 2)
        end
        -- (a string only: Lua's load runs a reader function in a protected call of its own, which would catch the
        -- runaway stop)
        -- (its chunks' names are its own: "=<folder>:<name>", never one of Survival's files: the runaway hook tells
        -- Survival's code from an add-on's by them)
        local function own(name) return "=" .. tostring(p.folder) .. ":" .. tostring(name):gsub("%c", " "):sub(1, 80) end
        A.load = function(chunk, name, mode, env)
            if mode ~= nil and mode ~= "t" then return nil, "an add-on loads text chunks only" end
            if type(chunk) ~= "string" then return nil, "an add-on loads a string (no reader function)" end
            return load(chunk, own(type(name) == "string" and name:gsub("^[@=]", "") or "load"), "t", type(env) == "table" and env or E)
        end
        A.loadfile = function(path, mode, env)
            if mode ~= nil and mode ~= "t" then return nil, "an add-on loads text chunks only" end
            local f, e = io.open(path, "rb")
            if not f then return nil, e end
            local src = f:read("a")
            f:close()
            return load(src, own(tostring(path):match("[^/\\]+$") or path), "t", type(env) == "table" and env or E)
        end
        A.dofile = function(path)
            local fn, e = A.loadfile(path)
            if not fn then error(e, 2) end
            return fn()
        end
        A.FName, A.FText = G.FName, G.FText
        for _, k in ipairs({ "FindFirstOf", "FindAllOf", "StaticFindObject" }) do
            A[k] = function(...)
                if walksBusy() or type(G[k]) ~= "function" then return nil end   -- (as a walk that found none: try later)
                return G[k](...)
            end
        end
        A.NotifyOnNewObject = addonNotify(p)
        A.SVP = copyOf(SVP)
        p.svp = A.SVP                                      -- (what the API writes for it: SVP.p2dMs)
        A.SVP.api, A.SVP.net = copyOf(SVP.api), copyOf(SVP.net)
        for k, v in pairs(PLUGINS.extra or {}) do A[k] = v end
        E = setmetatable({}, {
            __index = function(_, k)
                local v = A[k]
                if v ~= nil then return v end
                if declared(p, k) and nativeOk(k) then return rawget(G, k) end
                return nil
            end,
            __metatable = false,
        })
        rawset(E, "_G", E)
        return E
    end
    PLUGINS.envFor = envFor

    -- --------------------------------------------------------------------------------------------- finding the add-ons
    -- Each add-on is a folder Mods\AC8SurvivalAddons\<name>\ (a sibling of Survival's own folder: an update that deletes
    -- Survival's folder keeps it), and every .lua directly in it runs, in name order, in that add-on's one environment
    -- (its data files go in subfolders). The folder must never look like a UE4SS mod (no Scripts\main.lua, no
    -- enabled.txt, no line in Mods\mods.txt), or UE4SS runs it by itself, outside the framework: said in the log.
    -- Listed with UE4SS's IterateGameDirectories, walked down by SCRIPT_DIR's names; that walk reads the game folder's
    -- tree, so AC8SurvivalAddons is probed first: io.open on a folder fails with EACCES (13) when it's there and ENOENT
    -- (2) when it isn't (the C runtime's fopen). No folder: no walk.
    local function addonsDir() return SCRIPT_DIR .. "..\\..\\AC8SurvivalAddons\\" end
    local function folderMissing(path)
        local f, _, code = io.open(path, "r")
        if f then f:close(); return false end
        return code == 2
    end
    PLUGINS.folderMissing = folderMissing
    local function luaOf(node)
        local out, natives = {}, nil
        for _, f in pairs(type(node) == "table" and type(node.__files) == "table" and node.__files or {}) do
            local okN, name = pcall(function() return f.__name end)
            local okP, path = pcall(function() return f.__absolute_path end)
            if okN and okP and type(name) == "string" then
                if name:lower():match("%.lua$") then out[#out + 1] = { name = name, path = tostring(path) }
                elseif name:lower() == "natives.txt" then natives = tostring(path) end
            end
        end
        table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
        return out, natives
    end
    local function addonFolders()
        if folderMissing(addonsDir():sub(1, -2)) then return {}, "no AC8SurvivalAddons folder" end
        local okD, dirs = pcall(IterateGameDirectories)
        if not (okD and type(dirs) == "table") then return {}, "no IterateGameDirectories" end
        local function child(t, name)
            if type(t) ~= "table" then return nil end
            for k, v in pairs(t) do if type(k) == "string" and k:lower() == name:lower() then return v end end
            return nil
        end
        -- SCRIPT_DIR ends ...\Game\Binaries\Win64\ue4ss\Mods\AC8SurvivalMode\Scripts\ (or without ue4ss\)
        local parts, node = {}, nil
        for s in SCRIPT_DIR:gmatch("[^/\\]+") do parts[#parts + 1] = s end
        for i = #parts - 1, 1, -1 do                -- (the last Game\Binaries in it: a library folder may be called Game too)
            if parts[i]:lower() == "game" and parts[i + 1]:lower() == "binaries" then
                node = child(dirs, "Game")
                for j = i + 1, #parts - 2 do node = child(node, parts[j]) end   -- (down to Mods)
                node = child(node, "AC8SurvivalAddons")
                break
            end
        end
        if not node then return {}, "no AC8SurvivalAddons folder" end
        local out = {}
        for k, v in pairs(node) do
            if type(k) == "string" and k:sub(1, 2) ~= "__" and type(v) == "table" then
                local files, natives = luaOf(v)
                out[#out + 1] = { name = k, files = files, natives = natives }
            end
        end
        table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
        return out
    end
    -- AC8SurvivalAddons\addons.txt, a line "<name>\<file>.lua" each: read at the add-ons' load (Survival's first tick)
    -- only when the folders can't be walked (no IterateGameDirectories: an older UE4SS). Blank lines and lines from # or
    -- ; are comments; any other line it can't use is said, one log line each
    local function listedFolders()
        local dir = addonsDir()
        local f = io.open(dir .. "addons.txt", "r")
        if not f then return nil end
        local by, out = {}, {}
        for line in f:lines() do
            local name, file = line:match("^%s*([%w_%-]+)[/\\]([^/\\;#]-%.[Ll][Uu][Aa])%s*$")
            if not name and not line:match("^%s*$") and not line:match("^%s*[#;]") then
                log("plugins: addons.txt: a line left out (not <folder>\\<file>.lua): " .. str(line):sub(1, 120))
            end
            if name then
                local a = by[name:lower()]
                if not a then
                    a = { name = name, files = {}, natives = dir .. name .. "\\natives.txt" }
                    by[name:lower()] = a
                    out[#out + 1] = a
                end
                a.files[#a.files + 1] = { name = file, path = dir .. name .. "\\" .. file }
            end
        end
        f:close()
        return out
    end
    -- (UE4SS runs a Mods folder that has Scripts\main.lua, an enabled.txt or a line in Mods\mods.txt)
    local function looksLikeMod()
        local dir, why = addonsDir(), {}
        for _, f in ipairs({ "Scripts\\main.lua", "enabled.txt" }) do
            local h = io.open(dir .. f, "r")
            if h then h:close(); why[#why + 1] = "AC8SurvivalAddons\\" .. f end
        end
        local m = io.open(SCRIPT_DIR .. "..\\..\\mods.txt", "r")
        if m then
            for line in m:lines() do
                if line:gsub(";.*$", ""):match("^%s*AC8SurvivalAddons%s*:") then why[#why + 1] = "a line in Mods\\mods.txt" end
            end
            m:close()
        end
        return #why > 0 and table.concat(why, ", ") or nil
    end
    PLUGINS.looksLikeMod = looksLikeMod

    -- an add-on that fails its load (a file that can't be read or doesn't compile, an error, a runaway, a refusal, a
    -- switch-off during its load): its kinds off again (SPC.kinds, CFG.specials, the rotation entries it added), and
    -- switched off
    local function loadFailed(p, why)
        local rot = CFG.specials.rotation
        for _, k in ipairs(p.kinds) do
            SPC.kinds[k], PLUGINS.kinds[k], CFG.specials[k] = nil, nil, nil
            if p.addedRot and p.addedRot[k] and type(rot) == "table" then
                for i = #rot, 1, -1 do if rot[i] == k then table.remove(rot, i) end end
            end
        end
        local n = #p.kinds
        p.kinds = {}
        why = str(why) .. (n > 0 and " (its kinds taken off)" or "")
        if p.off then plog(p, why) else PLUGINS.switchOff(p, why) end
    end
    -- Every add-on found goes into PLUGINS.loaded before any add-on runs (what LB.edited reads: a run with any add-on
    -- found isn't ranked, loaded or not; no add-on can reach that list). One that fails its load is switched off: none
    -- of its jobs run, its kinds come off, its later files don't run.
    local function loadOne(p)
        p.dir = p.files[1] and p.files[1].path:match("^(.*[/\\])") or (addonsDir() .. p.name .. "\\")
        readNatives(p, p.nativesPath)
        p.env = envFor(p)
        for _, file in ipairs(p.files) do
            local f = io.open(file.path, "rb")
            if not f then loadFailed(p, "can't be read: " .. file.path); return end
            local src = f:read("a")
            f:close()
            -- (named AC8SurvivalAddons\<folder>\<file>: never one of Survival's paths, whichever way it was found)
            local chunk, err = load(src, "@AC8SurvivalAddons\\" .. tostring(p.folder) .. "\\" .. (file.path:match("[^/\\]+$") or "?"), "t", p.env)
            if not chunk then loadFailed(p, file.name .. " doesn't load: " .. str(err)); return end
            PLUGINS.current = p
            local res = hooked(p, chunk)
            PLUGINS.current = nil
            if not res[1] and res.culprit and res.culprit ~= p then
                PLUGINS.switchOff(res.culprit, str(res[2]) .. " (in its callback, inside " .. tostring(p.name) .. "'s load)")
            end
            if not res[1] then loadFailed(p, file.name .. ": error at load: " .. str(res[2])); return end
            if p.refused then loadFailed(p, "refused: " .. str(p.refused)); return end
            if p.off then loadFailed(p, file.name .. ": switched off during its load"); return end
        end
        plog(p, string.format("loaded (%d files, version %s, %d kinds: %s)", #p.files, str(p.ver or "?"), #p.kinds,
            table.concat(p.kinds, ", ")))
    end

    function PLUGINS.load()
        playerRotation()                                   -- (the player's own rotation or not: before any add-on)
        local found, why = addonFolders()
        if why then
            local l = listedFolders()
            if l then found, why = l, nil end
        end
        if why then log("plugins: none (" .. why .. ")"); return end
        local mod = looksLikeMod()
        if mod then log("plugins: AC8SurvivalAddons looks like a UE4SS mod (" .. mod .. "): UE4SS may run it by itself, outside the framework; take that out") end
        local ps = {}
        for _, a in ipairs(found) do                       -- (all of them listed first: PLUGINS.loaded)
            local p = { name = a.name, folder = a.name, files = a.files, nativesPath = a.natives, kinds = {} }
            PLUGINS.loaded[#PLUGINS.loaded + 1] = p
            ps[#ps + 1] = p
            if not a.name:match("^[%w_%-]+$") or #a.name > 40 then p.badName = true end
            if a.name:lower() == "scripts" or a.name:lower() == "dlls" then p.badName = "reserved" end
        end
        if #ps == 0 then log("plugins: none in AC8SurvivalAddons"); return end
        for _, p in ipairs(ps) do
            if p.badName == "reserved" then
                PLUGINS.switchOff(p, "its folder is named " .. p.name
                    .. ": Scripts and dlls aren't add-on names (a UE4SS mod's own folders)")
            elseif p.badName then PLUGINS.switchOff(p, "its folder's name isn't letters, digits, _ or - (40 at most)")
            elseif #p.files == 0 then PLUGINS.switchOff(p, "no .lua in its folder")
            else
                local ok, err = pcall(loadOne, p)
                if not ok then PLUGINS.switchOff(p, "error " .. str(err)) end
            end
        end
    end
end
