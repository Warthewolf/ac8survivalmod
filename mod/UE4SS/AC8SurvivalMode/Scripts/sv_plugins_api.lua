-- sv_plugins_api.lua: the add-on API's calls (SVP): targets, assets, spawns and moves, the run's facts, jobs and
-- events, PLUGINS.tick, providers, what an add-on reads of Survival, pins, music and HUD, sounds and effects, the
-- player's plane, retire, despawn and hurt. Piece 2 of 3 of sv_plugins.lua (sv_plugins.lua, sv_plugins_api.lua,
-- sv_plugins_env.lua), split by tools/lua_split_part.py and run by main.lua right after the piece before it: a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local.
do  -- (sv_plugins.lua's do block, continued: this piece's own helpers stay local to it)
local pcall = PLUGINS.pcall                        -- (sv_plugins.lua's pcall, handed on)
if debug and debug.getinfo then PLUGINS.ownSrc[debug.getinfo(1, "S").source] = true end   -- (Survival's code: the hook)

    -- a target of the calling add-on's round: kept by its address and full name (PLUGINS.ids: hard rule 59), and
    -- marked as the add-on's for Survival's plane sweep (its pay and count are the API's)
    -- (an actor another add-on spawned or targeted first is its own: target / move / despawn / retire leave it alone)
    -- (by its address and full name, PLUGINS.owners: another add-on's handle of that object is a fresh userdata)
    local function othersActor(a)
        local k = keyOf(a)
        local o = k ~= nil and PLUGINS.owners[k] or nil
        if not o or o.p == (PLUGINS.running or PLUGINS.current) then return false end
        local ok, _, n = itself(a, true)
        return ok and n == o.name
    end
    -- a target's opts as the API keeps them: copied at the call, raw (rawget, its types checked), so no metamethod of the
    -- add-on's runs later at its down, outside its guard
    local function targetOpts(o, p)
        if type(o) ~= "table" then return {} end
        if getmetatable(o) ~= nil and not p.optsMetaSaid then
            p.optsMetaSaid = true
            plog(p, "SVP.target: its opts have a metatable: only their own fields are read")
        end
        local pay, label, cls, od = rawget(o, "pay"), rawget(o, "label"), rawget(o, "class"), rawget(o, "onDown")
        if type(pay) == "string" then pay = tonumber(pay) or "(" .. pay .. ")"
        elseif pay ~= nil and type(pay) ~= "number" then pay = "(a " .. type(pay) .. ")" end
        return { pay = pay, flat = rawget(o, "flat") == true, class = type(cls) == "string" and cls or nil,
                 label = (type(label) == "string" or type(label) == "number") and tostring(label) or nil,
                 onDown = type(od) == "function" and od or nil }
    end
    -- Only in the caller's own round (p.liveRun: from its spawn to its over / abort): the round's tick is what watches
    -- its targets, so a target made anywhere else (SVP.every, SVP.on, another special's round) would never be seen
    -- down, and its mark would keep it from Survival. TARGET_MAX targets an add-on at most.
    local isMine                                         -- (a player's plane; below, after myPawn)
    local TARGET_MAX = 256
    function SVP.target(actor, opts)
        local p = PLUGINS.running or PLUGINS.current
        if not p or refused(p) or not isHandle(actor) then return nil end
        if p.liveRun == nil or p.liveRun ~= D then
            if not p.targetRoundSaid then p.targetRoundSaid = true; plog(p, "SVP.target outside its own round: refused (from its spawn to its over only)") end
            return nil
        end
        if (p.nTargets or 0) >= TARGET_MAX then
            if not p.targetMaxSaid then p.targetMaxSaid = true; plog(p, "SVP.target: " .. TARGET_MAX .. " targets at most; refused") end
            return nil
        end
        local ok, why, n = itself(actor, true)          -- (live and itself first: every read after it is of a live object)
        if ok and (othersActor(actor) or isMine(actor)) then return nil end
        if not ok then
            if why == "reused" then plog(p, "SVP.target: its object is another one now (hard rule 59): not a target") end
            return nil
        end
        local k = remember(actor, p, n)
        mark(actor, "target", n)
        PLUGINS.nextId = PLUGINS.nextId + 1
        PLUGINS.targets[PLUGINS.nextId] = { actor = actor, opts = targetOpts(opts, p), p = p, key = k, name = n }
        p.nTargets = (p.nTargets or 0) + 1
        if k ~= nil then PLUGINS.tkeys[k] = (PLUGINS.tkeys[k] or 0) + 1 end
        return PLUGINS.nextId
    end
    -- (the add-on's own call, or retire / despawn / a hit of no one's on it: off the watch, unpaid, and not Survival's
    -- to pay either)
    local function untarget(id, keepMark)
        local t = PLUGINS.targets[id]
        if t then forget(id, t, keepMark) end
    end
    -- the targets of `a` (by its address) taken off unpaid; their mark kept (`a` is going down, nobody's)
    local function untargetActor(a, why)
        local k = keyOf(a)
        if k == nil then return 0 end
        local n = 0
        for id, t in pairs(PLUGINS.targets) do
            if t.key == k then untarget(id, true); n = n + 1; plog(t.p, "target " .. id .. " " .. why .. ": off, unpaid") end
        end
        return n
    end
    -- (an add-on's own targets only: another add-on's id is none of its business)
    local function ownTarget(id)
        local t = PLUGINS.targets[id]
        return (t and t.p == (PLUGINS.running or PLUGINS.current)) and t or nil
    end
    function SVP.untarget(id) if ownTarget(id) then untarget(id, false) end end
    function SVP.alive(id) return ownTarget(id) ~= nil end
    function SVP.kill(id, why)
        local t = ownTarget(id)
        if not t or refused(t.p) then return false end
        down(id, t, str(why or "the add-on's"))
        return true
    end
    function SVP.pay(n, why)
        local p = PLUGINS.running or PLUGINS.current
        if refused(p) then return false end
        local z = money(n)
        if z == nil then plog(p, "SVP.pay(" .. str(n) .. "): not a number, nothing paid"); return false end
        if z > 0 then addCredits(z, str(why or "an add-on's round")) end
        return z > 0
    end
    local loadMiss = {}
    local assetHit, assetMiss = {}, {}               -- (plAsset's, below; SVP.load fills the hits too)
    -- An asset or audio component kept in Lua is NOT kept alive by it: the game's garbage collection frees a sound wave
    -- nothing references, and valid() (UE4SS IsValid) can pass on the freed memory. A kept object is used only while
    -- liveObj says it is still the engine's live object; else it is looked up again. (SpawnSound2D on a wave freed since
    -- its last play crashed AC8 in UAudioComponent::PlayInternal, reading the "wave"'s vtable: exe+0x3fb7102)
    local function kept(o) return o ~= nil and liveObj(o) end
    -- liveObj alone isn't enough either: once the GC has freed an object, the allocator can put a NEW object at the same
    -- address, which takes a live GUObjectArray slot, so the old pointer passes liveObj while it is another object now
    -- (SVP.load handed back a freed asset 5 s after a good load in a test). A kept object is used only if
    -- it is still live AND still the same object: its full name when it was kept (keep) matches (kept).
    local keptId = setmetatable({}, { __mode = "k" })
    local function idOf(o)
        local ok, n = pcall(function() return o:GetFullName() end)
        return ok and type(n) == "string" and n ~= "" and n or nil
    end
    local function keep(o)
        if o ~= nil then keptId[o] = idOf(o) end
        return o
    end
    do
        local alive = kept
        kept = function(o)                               -- (liveObj first: GetFullName walks the outer chain)
            if not alive(o) then return false end
            local id = keptId[o]
            return id ~= nil and idOf(o) == id
        end
    end
    -- The API's own finds (its classes, the default objects it calls, an add-on's asset before it's loaded): UE4SS's
    -- Lua StaticFindObject walks every object (UObjectGlobals::FindObject -> ForEachUObject, each one's Outer read), so
    -- it waits as the add-ons' walks do (PLUGINS.walksBusy: the level going, walkHold, the engine freeing objects; round
    -- 12 P1's crash, 20261113-101700-5e40ab6, faulted in that walk on an Outer freed during a purge). A path found
    -- once is kept (kept(): still live and the same object) and not looked up again; nil while busy: the caller's
    -- "not found" (an asset is then loaded: loadObject finds it by its path, no walk)
    local found = {}
    local function find(path)
        local h = found[path]
        if h ~= nil and kept(h) then return h end
        found[path] = nil
        if PLUGINS.walksBusy and PLUGINS.walksBusy() then return nil end
        local ok, f = pcall(StaticFindObject, path)
        if ok and valid(f) then found[path] = keep(f); return f end
        return nil
    end
    PLUGINS.find = find
    -- An asset found or loaded is handed out only if liveObj passes (SV_ObjChain: its slot, and neither garbage nor the
    -- GC's unreachable flag). UE4SS's StaticFindObject walk doesn't skip an object the GC has condemned, and sv_core.lua
    -- loadObject finds first too: a condemned wave handed to SpawnSound2D was freed by the purge under the playing sound
    -- (a mod's run on this line, 20261113-151013-f108042). Such a one is not handed out and not loaded (loading would find
    -- the same object): nil this time, one log line a path; the next ask after the purge finds or loads it again.
    local condSaid = {}
    local function condemned(path)
        if not condSaid[path] then condSaid[path] = true; log("plugins: " .. path .. " found while the GC has it condemned: not used (asked again later)") end
        return nil, "condemned by the GC: try again"
    end
    PLUGINS.condemned = condemned
    function SVP.load(path)
        if type(path) ~= "string" then return nil, "a path" end
        if SVP.levelGoing() then return nil, "the level is going away" end
        if PLUGINS.walksBusy and PLUGINS.walksBusy() then return nil, "the engine is freeing objects: try again" end
        local m = loadMiss[path]
        if m and os.clock() - m < 30 then return nil, "not found (kept 30 s)" end   -- (a miss isn't loaded again at once)
        local h = assetHit[path]
        if h and kept(h) then return h end               -- (StaticFindObject by path costs 12-37 ms too: kept)
        local okF, f = pcall(find, path)     -- (already in memory: found, not loaded again)
        if okF and valid(f) then
            if not liveObj(f) then return condemned(path) end
            assetHit[path] = keep(f); return f
        end
        local o, why = loadObject(path)
        if o ~= nil and not liveObj(o) then return condemned(path) end
        if o == nil then loadMiss[path] = os.clock() else loadMiss[path] = nil; assetHit[path] = keep(o) end   -- (play2d / sound / fx find it)
        return o, why
    end
    -- SVP.widget(class, outer, name): a UMG widget of the add-on's own (its HUD lines), UE4SS's StaticConstructObject
    -- limited to that: class a widget class (its super chain reaches /Script/UMG.Widget), outer a live WidgetTree or
    -- widget, name a string or an FName (letters, digits, _). Refused as a call that changes the game is (the level
    -- going, the walks held, co-op open, switched off), and past 256 an add-on a level (said once). The widget is the
    -- game's: the add-on adds it to a tree it found, whose own teardown frees it. (StaticConstructObject itself isn't
    -- in an add-on's environment: any class, any outer, any flags.)
    local WIDGET, TREE, USER = "Class /Script/UMG.Widget", "Class /Script/UMG.WidgetTree", "Class /Script/UMG.UserWidget"
    -- (UMG's concrete widgets an add-on's HUD lines use; its abstract ones (Widget, PanelWidget, UserWidget itself) are
    -- a fatal error outside the editor. A widget blueprint's class: its parents reach UserWidget)
    local WIDGET_OK = { TextBlock = true, RichTextBlock = true, Image = true, Border = true, CanvasPanel = true, Overlay = true,
        HorizontalBox = true, VerticalBox = true, SizeBox = true, ScaleBox = true, Spacer = true, ProgressBar = true,
        GridPanel = true, UniformGridPanel = true, WrapBox = true }
    PLUGINS.widgetSeq = PLUGINS.widgetSeq or 0
    local function chainHas(c, a, b)
        for _ = 1, 64 do
            if not (c and c:IsValid()) then return false end
            local n = c:GetFullName()
            if n == a or n == b then return true end
            c = c:GetSuperStruct()
        end
        return false
    end
    function SVP.widget(cls, outer, name)
        local p = PLUGINS.running or PLUGINS.current
        local no = refused(p) or (PLUGINS.walkHeld() and "the walks are held")
        if no then return nil, no end
        if not (isHandle(cls) and isHandle(outer) and liveObj(cls) and liveObj(outer)) then
            return nil, "a widget class and its outer (UE4SS objects)"
        end
        if type(name) == "userdata" then                   -- (an FName: UE4SS's own ToString, no add-on code)
            local okN, n = pcall(function() return name:ToString() end)
            name = okN and n or nil
        end
        if type(name) ~= "string" or #name == 0 or #name > 64 or name:find("[^%w_]") then
            return nil, "a name (letters, digits, _)"
        end
        local ok, good = pcall(function()
            local n = cls:GetFullName()
            local concrete = WIDGET_OK[n:match("^Class /Script/UMG%.([%w_]+)$") or ""]
                or (n:find("^WidgetBlueprintGeneratedClass ") ~= nil and chainHas(cls:GetSuperStruct(), USER))
            return concrete and chainHas(outer:GetClass(), WIDGET, TREE)
        end)
        if not (ok and good) then return nil, "not one of UMG's widget classes (or a widget blueprint's), or its outer not a widget tree" end
        if p.widgetLevel ~= PLUGINS.level then p.widgetLevel, p.widgets = PLUGINS.level, 0 end
        if p.widgets >= 256 then
            if not p.widgetsSaid then p.widgetsSaid = true; plog(p, "SVP.widget: 256 this level, the rest refused") end
            return nil, "256 widgets this level"
        end
        -- (a name of its own, never one already in the outer: the same name again would replace that object, or with
        -- another class stop the game)
        PLUGINS.widgetSeq = PLUGINS.widgetSeq + 1
        local full = string.format("SVA_%s_%s_%d", (tostring(p.folder or p.name):gsub("[^%w_]", "_")), name, PLUGINS.widgetSeq)
        local okC, w = pcall(StaticConstructObject, cls, outer, FName(full))
        if not (okC and valid(w)) then return nil, "UE4SS didn't make it" end
        p.widgets = p.widgets + 1
        return w
    end
    -- an add-on's position, copied raw: numbers only (no __index of its runs inside the API's calls); nil if it isn't one
    local function posOf(at)
        if type(at) ~= "table" then return nil end
        local x, y, z = tonumber(rawget(at, "X")), tonumber(rawget(at, "Y")), tonumber(rawget(at, "Z")) or 0
        local big = 1e12                                 -- (NaN and infinities out)
        if not (x and y) or not (math.abs(x) < big and math.abs(y) < big and math.abs(z) < big) then return nil end
        return { X = x, Y = y, Z = z }
    end
    local function xform(at, yaw)
        local h = math.rad(tonumber(yaw) or 0) / 2
        return { Rotation = { X = 0, Y = 0, Z = math.sin(h), W = math.cos(h) },
                 Translation = { X = at.X, Y = at.Y, Z = at.Z or 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    end
    function SVP.spawn(cls, at, yaw)
        at = posOf(at)
        if not at then return nil, "no spot" end
        local p = PLUGINS.running or PLUGINS.current
        local no = refused(p)
        if no then return nil, no end
        if type(cls) == "string" then
            local c, why = loadObject(cls)
            if not valid(c) then return nil, "class " .. cls .. " not loaded: " .. tostring(why) end
            cls = c
        elseif not (isHandle(cls) and liveObj(cls)) then
            return nil, "a class (its path, or a live UE4SS object)"
        end
        local gs = find("/Script/Engine.Default__GameplayStatics")
        if not (valid(gs) and valid(cls)) then return nil, "no GameplayStatics or class" end
        local t = xform(at, yaw)
        local okA, a = pcall(function()
            local x = gs:BeginDeferredActorSpawnFromClass(survivalPC, cls, t, 1, nil, 1)   -- (AlwaysSpawn, MultiplyWithRoot)
            return gs:FinishSpawningActor(x, t, 1)
        end)
        if not okA or not valid(a) then return nil, "not spawned (" .. str(a) .. ")" end
        crumb("plugin spawn " .. str(fullName(cls)):sub(1, 120))
        remember(a, p)
        if p then                                   -- (taken off if the add-on is switched off: PLUGINS.switchOff)
            local l = p.spawned or {}
            p.spawned = l
            if #l >= 256 then                       -- (the ones gone since: out)
                local kept = {}
                for _, x in ipairs(l) do if liveAddr(x) then kept[#kept + 1] = x end end
                l = kept
                p.spawned = l
            end
            l[#l + 1] = a
        end
        return a
    end
    -- (hard rule 59: an actor whose address is another object's now is left alone)
    function SVP.move(a, at, yaw)
        at = posOf(at)
        if refused(PLUGINS.running or PLUGINS.current) or not at or not isHandle(a) or not itself(a, true)
            or othersActor(a) or isMine(a) then return false end
        local ok = pcall(function()
            if yaw ~= nil then
                a:K2_SetActorLocationAndRotation({ X = at.X, Y = at.Y, Z = at.Z or 0 }, { Pitch = 0, Yaw = tonumber(yaw) or 0, Roll = 0 },
                    false, {}, true)
            else
                a:K2_SetActorLocation({ X = at.X, Y = at.Y, Z = at.Z or 0 }, false, {}, true)
            end
        end)
        return ok
    end
    -- (a game unit goes by its own death, unpaid: PLUGINS.takeOff; anything else is destroyed. Nobody's kill either way)
    function SVP.despawn(a)
        local p = PLUGINS.running or PLUGINS.current
        if refused(p) or not isHandle(a) or not itself(a, true) or othersActor(a) or isMine(a) then return false end
        crumb("plugin despawn")
        return (PLUGINS.takeOff(a, p))
    end
    function SVP.players()
        if SVP.levelGoing() then return {} end
        local l = playerLocation()
        if not l then return {} end
        return { { slot = 0, X = l.X, Y = l.Y, Z = l.Z } }
    end
    function SVP.pad() return { X = SHUTTLE_PAD.X, Y = SHUTTLE_PAD.Y, Z = SHUTTLE_PAD.Z } end
    function SVP.runway() return { X = AIRFIELD.X, Y = AIRFIELD.Y } end
    function SVP.clock() return D and D.now or nil end
    function SVP.round() return D and D.round or nil end
    -- the run in progress as a token (a new one each run: e.g. a special that comes once a run), nil between runs
    function SVP.run() return D and tostring(D) or nil end
    function SVP.levelGoing() return levelGoing and levelGoing() or false end
    function SVP.callout(text, sub)
        if refused(PLUGINS.running or PLUGINS.current) then return false end
        hudCallout(str(text or ""), sub and str(sub) or nil)
        return true
    end
    function SVP.say(who, text, secs)
        if refused(PLUGINS.running or PLUGINS.current) then return false end
        if SUB and SUB.say then return SUB.say(str(who or ""), str(text or ""), tonumber(secs)) end
    end
    function SVP.log(msg) plog(PLUGINS.running or PLUGINS.current, msg) end
    function SVP.isHost() return not (COOP and COOP.client and COOP.client()) end
    function SVP.inCoop() return (COOP and COOP.open) == true end
    -- SVP.every / on / going: JOBS_MAX jobs of each an add-on (a job that adds a job each tick doesn't grow the list
    -- without bound); a pass runs the jobs there as it began; a switched-off add-on's jobs are pruned
    local JOBS_MAX = 64
    local function jobRoom(p, what)
        p.jobs = p.jobs or {}
        local n = p.jobs[what] or 0
        if n >= JOBS_MAX then
            if not p.jobsSaid then p.jobsSaid = true; plog(p, "SVP." .. what .. ": " .. JOBS_MAX .. " jobs at most; refused") end
            return false
        end
        p.jobs[what] = n + 1
        return true
    end
    PLUGINS.every = {}
    function SVP.every(fn)
        local p = PLUGINS.running or PLUGINS.current
        if not (p and type(fn) == "function") or p.off or not jobRoom(p, "every") then return false end
        PLUGINS.every[#PLUGINS.every + 1] = { p = p, fn = guard(p, "every", fn) }
        return true
    end
    -- SVP.going(fn): fn(now) once when Survival's level starts being torn down (a run's end, a quit), before nothing else
    -- of the plugin runs: for a plugin's own "round over" flag. It must not touch a game object.
    PLUGINS.going = {}
    function SVP.going(fn)
        local p = PLUGINS.running or PLUGINS.current
        if not (p and type(fn) == "function") or p.off or not jobRoom(p, "going") then return false end
        PLUGINS.going[#PLUGINS.going + 1] = { p = p, fn = guard(p, "going", fn) }
        return true
    end
    -- SVP.on(event, fn): Survival's moments, any add-on, as Survival's tick sees them (eventsTick: when D or D.round
    -- changes). fn(now, ...) on the game thread:
    --   "runStart" (the first tick a run exists), "roundStart" (round: the first tick D.round has a new number),
    --   "roundEnd" (round: the first tick it's changed again, or the run is gone), "runEnd" (its last round: the first
    --   tick the run is gone or replaced), "levelGoing" (the level is being torn down: touch no game object, as SVP.going).
    -- runEnd and levelGoing may come while the level goes: a handler must not touch a game object then.
    local EVENTS = { runStart = true, roundStart = true, roundEnd = true, runEnd = true, levelGoing = true }
    PLUGINS.on = {}
    function SVP.on(event, fn)
        local p = PLUGINS.running or PLUGINS.current
        if not (p and EVENTS[event] and type(fn) == "function") or p.off then return false end
        if event == "levelGoing" then return SVP.going(fn) end
        if not jobRoom(p, "on") then return false end
        PLUGINS.on[#PLUGINS.on + 1] = { p = p, ev = event, fn = guard(p, event, fn) }
        return true
    end
    -- (PLUGINS.tick) a switched-off add-on's jobs out of the lists
    local function pruneJobs()
        for _, name in ipairs({ "every", "on", "going" }) do
            local l, any = PLUGINS[name], false
            for i = 1, #l do if l[i].p.off then any = true; break end end
            if any then
                local kept = {}
                for i = 1, #l do if not l[i].p.off then kept[#kept + 1] = l[i] end end
                PLUGINS[name] = kept
            end
        end
    end
    local function emit(ev, now, a)
        if coopOpen() then return end                       -- (API 2.0: single player)
        local l = PLUGINS.on
        for i = 1, #l do local e = l[i]; if e.ev == ev and not e.p.off then e.fn(now, a) end end   -- (as the pass began)
    end
    -- the run and its round as Survival's tick sees them: the events above when they change
    local seenRun, seenRound = nil, nil
    local function eventsTick(now)
        local run, round = D, D and D.round or nil
        if seenRun ~= nil and run ~= seenRun then
            if seenRound then emit("roundEnd", now, seenRound) end
            emit("runEnd", now, seenRound)
            seenRound = nil
        end
        if run ~= nil and run ~= seenRun then emit("runStart", now) end
        seenRun = run
        if run ~= nil and round ~= seenRound then
            if seenRound then emit("roundEnd", now, seenRound) end
            if round then emit("roundStart", now, round) end
            seenRound = round
        end
    end

    -- (sv_main.lua's tick job, on the game thread, each tick's second half; timed("plugins") there). The add-ons load
    -- at its first call: every part of Survival is in and the tick loop runs on the game thread by then
    function oneWay(why)
        PLUGINS.level = PLUGINS.level + 1
        PLUGINS.marks, PLUGINS.owners = {}, {}
        dropAllTargets(why)
        for _, p in ipairs(PLUGINS.loaded) do p.spawned, p.takeOffDue = {}, nil; PLUGINS.unpinAll(p, why) end
        PLUGINS.dropNotify(nil)
    end
    if type(LEVEL_DROPS) == "table" then                 -- (sv_core.lua levelDrop: nothing touched, a flag for the tick)
        LEVEL_DROPS["add-ons"] = function() if not PLUGINS.wentHard then PLUGINS.levelMissed = true end end
    end
    function PLUGINS.tick()
        if PLUGINS.load == nil then return end           -- (sv_plugins_env.lua not in yet: a tick between the pieces)
        local now = os.clock()
        if not PLUGINS.loadDone and not (levelGoing and levelGoing()) then
            PLUGINS.loadDone = true
            local okL, errL = pcall(PLUGINS.load)
            if not okL then log("plugins: load error " .. str(errL)) end
        end
        -- (nothing of an add-on's reads a game object while the level is being torn down: reads then crashed the game.
        -- Survival's teardown flag is levelGoing; every job waits it out. Its first tick: SVP.going's jobs first, then
        -- a round's abort (runCheck), then roundEnd / runEnd (eventsTick), and every SVP call that would touch the game
        -- refuses in all of them)
        local goingNow = levelGoing and levelGoing()
        if goingNow and not PLUGINS.wentGoing then         -- (once, the first tick of it: SVP.going's jobs, no game object)
            PLUGINS.wentGoing = true
            local l = PLUGINS.going
            for i = 1, #l do local e = l[i]; if not e.p.off and not coopOpen() then e.fn(now) end end
            for _, p in ipairs(PLUGINS.loaded) do bgmBack(p, "the level is going"); hudBack(p, "the level is going") end
        end
        -- (the one-way steps, once a teardown is certain (levelHard): the level's handles are an older level's, its
        -- marks, targets and owners dropped, what the add-ons spawned forgotten, pins let go, every NotifyOnNewObject
        -- callback dropped (asked again in the next level). A soft sign that lets go again changes none of it)
        if goingNow and not PLUGINS.wentHard and levelHard() then
            PLUGINS.wentHard, PLUGINS.levelMissed = true, false
            oneWay("the level is going")
        end
        -- (a level change no tick saw going: Survival's level gate dropped the level, sv_core.lua levelDrop, between two
        -- ticks. The same steps now, and the round's add-on told "the level is going")
        if PLUGINS.levelMissed and not goingNow then
            PLUGINS.levelMissed, PLUGINS.goneMissed = false, true
            local l = PLUGINS.going                         -- (its SVP.going jobs, as at a teardown tick)
            for i = 1, #l do local e = l[i]; if not e.p.off and not coopOpen() then e.fn(now) end end
            for _, p in ipairs(PLUGINS.loaded) do bgmBack(p, "the level went"); hudBack(p, "the level went") end
            oneWay("the level went")
        end
        local okR, errR = pcall(runCheck, now)
        PLUGINS.goneMissed = false
        if not okR then log("plugins: run check error " .. str(errR)) end
        local okE, errE = pcall(eventsTick, now)
        if not okE then log("plugins: events error " .. str(errE)) end
        if goingNow then return end
        PLUGINS.wentGoing, PLUGINS.wentHard = false, false
        pruneJobs()
        for _, p in ipairs(PLUGINS.loaded) do
            if p.hudHidden and now - p.hudHidden.at > HUD_MAX_S then
                hudBack(p, HUD_MAX_S .. " s, the API's limit")
                p.hudCapAt = now                               -- (no new hide for HUD_MAX_S: the cap isn't renewed)
            end
        end
        local okT, errT = pcall(takeOffTick)
        if not okT then log("plugins: take-off error " .. str(errT)) end
        local okN, errN = pcall(PLUGINS.notifyTick)         -- (with co-op open: the objects dropped, none handed over)
        if not okN then log("plugins: NotifyOnNewObject error " .. str(errN)) end
        if coopOpen() then return end                       -- (API 2.0: single player)
        local l = PLUGINS.every
        for i = 1, #l do                                   -- (the jobs there as the pass began: one added now waits)
            local e = l[i]
            if not e.p.off then
                local t0 = os.clock()
                e.fn(now)
                perf(e.p, "every", (os.clock() - t0) * 1000)
            end
        end
    end
    -- co-op's add-on channel (host -> joiners): not in API 2.0. Stubs; an add-on can test for it
    SVP.net = { send = function() return false end, on = function() return false end, ready = false }

    -- An add-on's native mod can give the API what Survival's runtime hasn't got, by name:
    --   SVP.provide("hurtPlayer", fn): fn(playerAddress, -healthPoints, causerAddress) -> 1 = dealt through the
    --   game's own health path (the player's ModifyHealthInternal), so a lethal hit is the game's own death.
    -- Survival's own runtime function wins when it has one (SV_HurtPlayer). The first provider of a name keeps it.
    PLUGINS.providers = {}
    local PROVIDES = { hurtPlayer = "SV_HurtPlayer" }
    function SVP.provide(name, fn)
        local p = PLUGINS.running or PLUGINS.current
        if not (p and PROVIDES[name] and type(fn) == "function") then return false end
        local had = PLUGINS.providers[name]
        if had and not had.p.off then return false, "already given by " .. tostring(had.p.name) end   -- (a switched-off one's: taken over)
        PLUGINS.providers[name] = { p = p, fn = guard(p, "provide " .. name, fn) }
        plog(p, "gives " .. name)
        return true
    end
    local function provider(name)
        local own = _G[PROVIDES[name]]
        if type(own) == "function" then return own end
        local e = PLUGINS.providers[name]
        return e and not e.p.off and e.fn or nil
    end

    -- whether o is still the engine's live object (the GUObjectArray check): ask it, not IsValid, before using anything
    -- kept between ticks (an actor, an asset, a component). IsValid can pass on freed memory
    function SVP.liveObj(o) return isHandle(o) and liveObj(o) == true end

    -- ------------------------------------------------------------------- what an add-on reads of Survival (read-only)
    -- (an add-on can't reach CFG, survivalPC, gamePaused, SV_Intercept or pin itself: its environment, below)
    local function caller() return PLUGINS.running or PLUGINS.current end
    -- SVP.cfg(kind): the settings of one of the calling add-on's kinds (its first when kind is nil): CFG.specials[kind],
    -- its def.cfg with survival.ini's [specials.<kind>] over it; read-only. nil before it registers that kind
    function SVP.cfg(kind)
        local p = caller()
        if not p then return nil end
        kind = kind or p.kinds[1]
        if not (kind and PLUGINS.kinds[kind] == p) then return nil end
        return readOnly(CFG.specials[kind], p)
    end
    -- SVP.pc(): your player controller (Survival's survivalPC), or nil (none yet, or the level is going)
    function SVP.pc()
        if SVP.levelGoing() then return nil end
        return (survivalPC ~= nil and liveObj(survivalPC)) and survivalPC or nil
    end
    -- SVP.paused(): the game is paused (Survival's gamePaused: GameplayStatics.IsGamePaused)
    function SVP.paused()
        if type(gamePaused) ~= "function" or SVP.pc() == nil then return false end
        local ok, r = pcall(gamePaused, survivalPC)
        return ok and r == true
    end
    -- SVP.intercept(m): shoots down the missile m (a LiveWeaponBase in flight) the game's own way: Survival's runtime
    -- SV_Intercept calls ALiveWeaponBase::Intercepted, an interceptor's clean kill (no hit, no explosion on its target;
    -- AC7's anti-missile laser's kill, docs/re/LASER_INTERCEPTOR.md). 1 shot down, 0 not (not in flight: down already,
    -- or back in its pool), nil when it can't be asked (no SV_Intercept in this runtime, m not a live missile, the level
    -- going, co-op open)
    local weaponCls = nil
    function SVP.intercept(m)
        if refused(caller()) or type(SV_Intercept) ~= "function" or not isHandle(m) or not liveObj(m) then return nil end
        if weaponCls == nil then
            local ok, c = pcall(find, "/Script/Live.LiveWeaponBase")
            if ok and valid(c) then weaponCls = c end
        end
        if weaponCls == nil then return nil end
        local okW, isW = pcall(function() return m:IsA(weaponCls) end)
        if not (okW and isW == true) then return nil end
        local ok, r = pcall(SV_Intercept, m)
        if not ok or type(r) ~= "number" or r < 0 then return nil end
        return r
    end
    -- SVP.pin(o, why): o kept loaded (held in the GameInstance's ReferencedObjects, Survival's own way: sv_core.lua pin)
    -- until the add-on is switched off, the run ends, or the level goes, whichever is first: then every pin is let go
    -- (its slot holds a class default object, never freed, and is used again). PIN_MAX pins an add-on at most.
    local PIN_MAX = 64
    PLUGINS.pinFree = {}
    local holder                                         -- (a class default object: never freed; found once, so the pins
    local function pinHolder()                           --  are let go at a teardown too, while finds wait)
        if holder ~= nil and liveObj(holder) then return holder end
        local ok, c = pcall(find, "/Script/Engine.Default__GameplayStatics")
        if ok and valid(c) then holder = c; return c end
        return nil
    end
    local function refs()
        local gi = type(gameInstance) == "function" and gameInstance() or nil
        if not gi then return nil end
        local ok, arr = pcall(function() return gi.ReferencedObjects end)
        return ok and arr or nil
    end
    local function sameSlot(arr, i, o)
        local ok, x = pcall(function() return arr[i] end)
        return ok and x ~= nil and keyOf(x) == keyOf(o)
    end
    local function inWorld(o)                            -- (an actor, a component, a widget: its outers reach a World / Level)
        local okG, g = pcall(function() return o.GetOuter end)
        if not okG or g == nil then return false end
        local ok, r = pcall(function()
            local x = o
            for _ = 1, 32 do
                local n = x:GetFullName()
                if n:find("^World ") or n:find("^Level ") then return true end
                x = x:GetOuter()
                if not (x and x:IsValid()) then return false end
            end
            return false
        end)
        return not ok or r == true
    end
    function SVP.pin(o, why)
        local p = caller()
        if not p or refused(p) or not isHandle(o) or not liveObj(o) then return false end
        if inWorld(o) then
            if not p.pinWorldSaid then p.pinWorldSaid = true; plog(p, "SVP.pin: an object of the level (an actor, a component, a widget) refused: assets only") end
            return false
        end
        p.pins = p.pins or {}
        local k = keyOf(o)
        for _, e in ipairs(p.pins) do if e.key == k then return true end end
        if #p.pins >= PIN_MAX then
            if not p.pinSaid then p.pinSaid = true; plog(p, "SVP.pin: " .. PIN_MAX .. " pins at most; refused (" .. str(why) .. ")") end
            return false
        end
        local arr, holder = refs(), pinHolder()
        if not arr then return false end
        local i = nil
        while #PLUGINS.pinFree > 0 and not i do               -- (a let-go slot first, if it's still the holder)
            local j = table.remove(PLUGINS.pinFree)
            if holder and sameSlot(arr, j, holder) then i = j end
        end
        local ok = pcall(function()
            if not i then i = #arr + 1 end
            arr[i] = o
        end)
        if not ok then return false end
        p.pins[#p.pins + 1] = { o = o, key = k, i = i, why = why }
        return true
    end
    local function unpinAll(p, why)
        if not (p.pins and #p.pins > 0) then return end
        local arr, holder, n = refs(), pinHolder(), 0
        for _, e in ipairs(p.pins) do
            if arr and holder and sameSlot(arr, e.i, e.o) and pcall(function() arr[e.i] = holder end) then
                PLUGINS.pinFree[#PLUGINS.pinFree + 1] = e.i
                n = n + 1
            end
        end
        plog(p, string.format("%d of its %d pins let go (%s)", n, #p.pins, tostring(why)))
        p.pins = {}
    end
    PLUGINS.unpinAll = unpinAll
    -- SVP.dir(): the add-on's own folder (ends with \), for its data files: an add-on has no debug library
    function SVP.dir()
        local p = caller()
        return p and p.dir or nil
    end

    -- Survival's music off (false) for an add-on's own track, or back (true). Given back by the API in any case when
    -- the add-on's round ends, its run ends, the level goes or the add-on is switched off.
    function SVP.bgm(on)
        local p = PLUGINS.running or PLUGINS.current
        if not p then return false end
        if on then bgmBack(p, "the add-on's call"); return true end
        if p.bgmMuted then return true end
        if type(SV_PlayBGM) ~= "function" or refused(p) or D == nil then return false end   -- (no run: nothing gives it back)
        p.bgmMuted = true                                   -- (first: whatever stops this call, the give-backs see it)
        local ok, r = pcall(SV_PlayBGM, "AKE_System_BGM_Mute_On")
        if ok and type(r) == "number" and r > 0 then
            if type(SND) == "table" then SND.unmuteDue = nil end   -- (Survival's pending unmute: not under this track)
            return true
        end
        p.bgmMuted = false
        return false
    end

    -- Survival's own HUD off (false) for an add-on's cutscene, or back (true); why: a word for the log. Given back by the
    -- API in any case at the add-on's round's end, its run's end, the level going, the add-on switched off, or 60 s on.
    -- Survival's HUD.hold (sv_hud.lua): hidden while any holder holds it. False on a Survival without HUD.hold
    function SVP.hud(on, why)
        local p = PLUGINS.running or PLUGINS.current
        if not p then return false end
        if on then hudBack(p, why or "the add-on's call"); return true end
        if refused(p) or D == nil or not (HUD and type(HUD.hold) == "function") then return false end   -- (no run: none)
        if p.hudCapAt and os.clock() - p.hudCapAt < HUD_MAX_S then
            if not p.hudCapSaid then p.hudCapSaid = true; plog(p, "SVP.hud: refused for " .. HUD_MAX_S .. " s after the API gave the HUD back") end
            return false
        end
        if not p.hudHidden then
            p.hudHidden = { at = os.clock(), why = why }    -- (first; HUD_MAX_S from the first hide: hiding again doesn't extend it)
            local ok = pcall(HUD.hold, true, holdName(p))
            if not ok then p.hudHidden = nil; return false end
            plog(p, "Survival's HUD hidden (" .. str(why or "the add-on's call") .. ")")
        end
        return true
    end

    -- Sound, effects and the player's plane (version 1, second part). Each is Survival's own way of doing it
    -- (sv_escort_laser.lua's sound / fx, sv_decoy.lua's sure kill), so a plugin needs no UE calls of its own for them.
    -- (an asset a plugin plays: found ones kept while valid, a miss kept 30 s, so a sound missing from the pack isn't
    -- looked up and loaded again on every play: 15-46 ms each)
    local function fullPath(path)
        return path:find(".", 1, true) and path or (path .. "." .. path:match("[^/]+$"))
    end
    local plWhy = "?"                                    -- (how the last plAsset got its object: the p2dMs line)
    local function plAsset(path)
        if type(path) ~= "string" then return nil end
        local full = fullPath(path)
        local h = assetHit[full]
        if h and kept(h) then plWhy = "kept"; return h end
        local m = assetMiss[full]
        if m and os.clock() - m < 30 then plWhy = "miss kept"; return nil end
        -- (LoadObject takes 14-20 ms even for a wave already in memory: an asset that's loaded is
        -- found first (StaticFindObject, well under 1 ms), so a plugin can load its assets ahead and play them cheaply)
        if PLUGINS.walksBusy and PLUGINS.walksBusy() then plWhy = "busy"; return nil end   -- (its callers wait too)
        local okF, f = pcall(find, full)
        if okF and valid(f) then
            if not liveObj(f) then plWhy = "condemned"; condemned(full); return nil end
            assetHit[full], assetMiss[full] = keep(f), nil; plWhy = "found"; return f
        end
        local o = loadObject(full)
        if valid(o) and not liveObj(o) then plWhy = "condemned"; condemned(full); return nil end
        if valid(o) then assetHit[full], assetMiss[full] = keep(o), nil; plWhy = "loaded"; return o end
        assetHit[full], assetMiss[full] = nil, os.clock()
        plWhy = "miss"
        return nil
    end
    -- (sounds and effects: nothing started while the engine frees objects, PLUGINS.walksBusy. A mod's crash on this
    -- line (20261113-101700 class, run 20261113-151013-f108042): the API keeps an asset only in a Lua table, so a
    -- wave nothing plays is unreferenced between plays and a GC condemns it; during the incremental purge it still
    -- looks live (kept(): still in GUObjectArray), and a play then started an FActiveSound on an object the purge
    -- freed a moment later: the audio task faulted on it (UE's virtual-loop test, IsLooping on the freed sound).
    -- So: false / nil, "try again", as the walks do)
    local function startsWait() return PLUGINS.walksBusy ~= nil and PLUGINS.walksBusy() == true end
    local soundWay = nil                            -- (PostEventAtLocation's two signatures: the first that works kept)
    function SVP.sound(path, at)
        at = posOf(at)
        if not at or refused(PLUGINS.running or PLUGINS.current) or startsWait() then return false end
        local ev, ak = plAsset(path), find("/Script/AkAudio.Default__AkGameplayStatics")
        if not (ev and valid(ak) and liveObj(survivalPC)) then return false end
        local rot = { Pitch = 0, Yaw = 0, Roll = 0 }
        local tries = {
            function() return ak:PostEventAtLocation(ev, at, rot, survivalPC) end,
            function() return ak:PostEventAtLocation(ev, at, rot, "", survivalPC) end,
        }
        for i = soundWay or 1, soundWay or #tries do
            if pcall(tries[i]) then soundWay = i; return true end
        end
        return false
    end
    -- a Niagara system at `at`: scale (uniform), rot (yaw degrees or a rotator), floats (user floats, e.g. BeamLength);
    -- the component (switch it off with comp:Deactivate()), or nil
    function SVP.fx(path, at, scale, rot, floats)
        at = posOf(at)
        if not at or refused(PLUGINS.running or PLUGINS.current) or startsWait() then return nil end
        local lib, sys = find("/Script/Niagara.Default__NiagaraFunctionLibrary"), plAsset(path)
        if not (valid(lib) and sys and liveObj(survivalPC)) then return nil end
        local sc = tonumber(scale) or 1
        local r = { Pitch = 0, Yaw = tonumber(rot) or 0, Roll = 0 }
        if type(rot) == "table" then                     -- (raw copies: no metamethod of the add-on's runs in the pcall)
            r = { Pitch = tonumber(rawget(rot, "Pitch")) or 0, Yaw = tonumber(rawget(rot, "Yaw")) or 0, Roll = tonumber(rawget(rot, "Roll")) or 0 }
        end
        local fl = {}
        if type(floats) == "table" then
            local k, v = next(floats)
            while k ~= nil and #fl < 32 do
                if type(k) == "string" and type(v) == "number" then fl[#fl + 1] = { k, v } end
                k, v = next(floats, k)
            end
        end
        at = { X = tonumber(rawget(at, "X")) or 0, Y = tonumber(rawget(at, "Y")) or 0, Z = tonumber(rawget(at, "Z")) or 0 }
        local ok, comp = pcall(function()
            local c = lib:SpawnSystemAtLocation(survivalPC, sys, at, r, { X = sc, Y = sc, Z = sc }, true, true, 0, true)
            -- (SpawnSystemAtLocation doesn't apply its rotation: set after, as the ZFA-44's laser does)
            pcall(function() c:K2_SetWorldRotation(r, false, {}, false) end)
            for _, f in ipairs(fl) do
                pcall(function() c:SetVariableFloat(FName("User." .. f[1]), f[2]) end)
                pcall(function() c:SetVariableFloat(FName(f[1]), f[2]) end)
            end
            return c
        end)
        return ok and comp or nil
    end
    -- a sound wave (or cue) heard by you alone, not placed (GameplayStatics.SpawnSound2D): true and its length in s
    -- (SVP.p2dMs: the last play's parts in ms, asset / statics / pc / spawn / duration: a line can cost 16-37 ms to
    -- start even when the wave is in memory; which part)
    local gsObj
    -- (radio lines stuttered: every line start spent 20-38 ms in plAsset, loaded ahead or not: a wave that has been
    -- played holds no reference once its spawned component is gone, so the next
    -- play finds / loads it again. A HELD audio component (CreateSound2D, not playing, never auto-destroyed) keeps the
    -- wave alive and plays it with no spawn: SVP.hold2d(path) makes one; play2d uses it when it isn't already playing.
    -- Held components belong to the level: gone with it, made again on the next hold2d)
    local held2d = {}
    local function p2d(v)                                -- (SVP.p2dMs on the calling add-on's own SVP)
        local p = PLUGINS.running or PLUGINS.current
        if p and type(p.svp) == "table" then rawset(p.svp, "p2dMs", v) end
    end
    function SVP.hold2d(path)
        if type(path) ~= "string" then return nil, "a path" end
        local no = refused(PLUGINS.running or PLUGINS.current)
        if no then return nil, no end
        if startsWait() then return nil, "the engine is freeing objects: try again" end
        local full = fullPath(path)
        local h = held2d[full]
        if h and kept(h) then return h end
        local sw = plAsset(path)
        if not valid(gsObj) then gsObj = find("/Script/Engine.Default__GameplayStatics") end
        if not (sw and valid(gsObj) and liveObj(survivalPC)) then return nil, "not loaded" end
        local ok, comp = pcall(function() return gsObj:CreateSound2D(survivalPC, sw, 1.0, 1.0, 0.0, nil, false, false) end)
        if not (ok and valid(comp)) then return nil, "CreateSound2D: " .. tostring(comp) end
        held2d[full] = keep(comp)
        return comp
    end
    function SVP.play2d(path, volume)
        if refused(PLUGINS.running or PLUGINS.current) or startsWait() then return false end
        local t0 = os.clock()
        local h = type(path) == "string" and held2d[fullPath(path)]
        if h and kept(h) then
            local okP, playing = pcall(function() return h:IsPlaying() end)
            if okP and not playing then
                pcall(function() h:SetVolumeMultiplier(tonumber(volume) or 1.0) end)
                local okPl = pcall(function() h:Play(0.0) end)
                if okPl then
                    local okD, d = pcall(function() return h.Sound.Duration end)
                    p2d(string.format("held %.0f", (os.clock() - t0) * 1000))
                    return true, (okD and type(d) == "number" and d > 0) and d or nil, h
                end
            end
        end
        local sw = plAsset(path)
        local t1 = os.clock()
        if not valid(gsObj) then gsObj = find("/Script/Engine.Default__GameplayStatics") end
        local gs = gsObj
        local t2 = os.clock()
        local pcOk = liveObj(survivalPC)
        local t3 = os.clock()
        if not (sw and valid(gs) and pcOk) then return false end
        local ok, comp = pcall(function() return gs:SpawnSound2D(survivalPC, sw, tonumber(volume) or 1.0, 1.0, 0.0, nil, false, true) end)
        local t4 = os.clock()
        local okD, d = pcall(function() return sw.Duration end)
        p2d(string.format("asset %.0f (%s) / statics %.0f / pc %.0f / spawn %.0f / duration %.0f", (t1 - t0) * 1000,
            plWhy, (t2 - t1) * 1000, (t3 - t2) * 1000, (t4 - t3) * 1000, (os.clock() - t4) * 1000))
        -- (the audio component third: comp:Stop() cuts the sound short)
        return ok, (okD and type(d) == "number" and d > 0) and d or nil, ok and comp or nil
    end
    -- your plane: { a = the pawn, X, Y, Z (cm), VX, VY, VZ (cm/s), health (HealthInternal: health x 10), down }
    local function myPawn()
        local pawn
        pcall(function() pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn end)
        if pawn and valid(pawn) then return pawn end
        return nil
    end
    -- (a player's plane: never targeted, moved, retired or despawned by an add-on; SVP.killPlayer is the way. The PC's pawn, or any object of
    -- the player planes' class: a co-op joiner's plane, or yours while the PC has none)
    local playerCls = nil
    isMine = function(a)
        local me = myPawn()
        if me ~= nil and (a == me or (addrOf ~= nil and addrOf(a) == addrOf(me))) then return true end
        if playerCls == nil then
            local ok, c = pcall(find, "/Script/Live.LivePlayerPlane")
            if ok and valid(c) then playerCls = c end      -- (a native class: never freed)
        end
        if playerCls == nil then return false end
        local ok, r = pcall(function() return a:IsA(playerCls) end)
        return ok and r == true
    end
    function SVP.playerPlane()
        if SVP.levelGoing() then return nil end
        local p = myPawn()
        if not p then return nil end
        local okL, l = pcall(function() return p:K2_GetActorLocation() end)
        if not (okL and l) then return nil end
        local okV, v = pcall(function() return p:GetVelocity() end)
        return { a = p, X = l.X, Y = l.Y, Z = l.Z, VX = okV and v.X or 0, VY = okV and v.Y or 0, VZ = okV and v.Z or 0,
                 health = healthOf(p), down = (DOWN and DOWN.me and DOWN.me()) == true }
    end
    -- you destroyed now, the stock way (Mission 26's LiveDestroyPlayerPlaneExecution, THE DECOY's sure-kill event
    -- RE_SV_DecoyKill in Survival's world data): Survival's own DOWN takes it from there. False when the build has
    -- no such event, you're already down, or the level is going.
    function SVP.killPlayer(why)
        if refused(PLUGINS.running or PLUGINS.current) or type(SV_Event) ~= "function" then return false end
        if DOWN and DOWN.me and DOWN.me() == true then return false end
        -- (hard rule 64: an event fired while this game's landing minigames run (the STORE) runs none of its records,
        -- though SV_Event answers 1: no kill then, rather than one reported and never dealt; sv_rounds_store.lua's gate)
        -- (the gate keeps its time in Survival's state: it's asked with Survival's own clock, the rounds' D.now)
        if STOREQ and type(STOREQ.gate) == "function" then
            local okG, open = pcall(STOREQ.gate, D and D.now or 0)
            if okG and open == false then return false end
        end
        local ok, r = pcall(SV_Event, "RE_SV_DecoyKill")
        plog(PLUGINS.running or PLUGINS.current, "your plane destroyed (" .. str(why or "the add-on's") .. "): RE_SV_DecoyKill "
            .. str(ok and r or "error"))
        return ok and type(r) == "number" and r >= 0
    end
    -- `n` damage (AC8's unit: MaxHealth units; HealthInternal = health x 10) to an actor, `causer` credited where the
    -- game takes one. An AI object: ModifyHealth. Your plane: ModifyHealth does nothing on it (docs/re/
    -- KILLS_HEALTH_DEATH.md), so its health is written, never to 0: a hit that would kill is SVP.killPlayer.
    -- true, health before, after, how
    -- SVP.retire(a): the game itself retires one of the add-on's units (its own death: finishUnpaid), so it's freed as a
    -- stock unit is; Survival counts and pays nothing for it (no kill, no credits, no stats: its mark, PLUGINS.owns in
    -- the plane sweep). For an add-on's units at its round's end: a unit the game still has registered can't be spawned
    -- again by name (hard rule 16), and taking it off the phase by hand crashed the game later
    -- One of the add-on's units ended by the game's own death, unpaid. (Hard rule 63: GameplayStatics.ApplyDamage does
    -- nothing to AC8's objects. Survival's own finishUnpaid makes it mortal (MinHealth 0), deals ModifyHealth and reads
    -- its health back.) Marked nobody's once its health reads 0. -> dead, nil, health after, how
    local function retireOne(a)
        -- (already down: a kill since the last sweep, someone's. Not marked nobody's: Survival's plane sweep counts and
        -- pays it as its own, and a target of an add-on's is down, paid by the API as its watch would)
        local h0 = healthOf(a)
        if h0 ~= nil and h0 <= 0 then
            local k, ids = keyOf(a), {}
            for id, t in pairs(PLUGINS.targets) do if k ~= nil and t.key == k then ids[#ids + 1] = id end end
            for _, id in ipairs(ids) do local t = PLUGINS.targets[id]; if t then down(id, t, "no health") end end
            return true, nil, h0, "already down"
        end
        local done, h, how = false, nil, nil
        if type(finishUnpaid) == "function" then
            local okF, d, h1, w = pcall(finishUnpaid, a)
            if okF then done, h, how = d == true, h1, w end
        else
            local okM, mx = pcall(function() return a.MaxHealth end)
            local n = (okM and type(mx) == "number" and mx > 0) and mx * 20 or 100000
            local ok, _, after = SVP.hurt(a, n, nil)
            done, h, how = ok == true and (after == nil or after <= 0), after, "ModifyHealth"
        end
        if done and how ~= "already down" then              -- (only a death it dealt itself is nobody's; its targets off
            untargetActor(a, "retired")                    -- only then: a unit the game didn't let die stays a target)
            mark(a, "retired")
        end
        return done, nil, h, how
    end
    function SVP.retire(a)
        if refused(PLUGINS.running or PLUGINS.current) or not isHandle(a) or not itself(a, true) or othersActor(a)
            or isMine(a) then return false end
        return retireOne(a)
    end

    -- A unit the game registered (an ALiveGameObject: ALiveAIGameObject's parent, the size the crash read past) is
    -- never destroyed by hand: K2_DestroyActor leaves its entry in
    -- the game's unit list, null after the next garbage collection, and the next unit death anywhere reads null+0xf50
    -- (AC8 crashed there, exe+0x7e0cb5a). Such a unit is taken off by its own death (retireOne), or not at all.
    local unitCls = nil
    local function isUnit(a)                               -- -> true / false, nil when it can't be told
        if unitCls == nil then
            local ok, c = pcall(find, "/Script/Live.LiveGameObject")   -- (ALiveAIGameObject's parent too)
            if ok and valid(c) then unitCls = c end         -- (a native class: never freed)
        end
        if unitCls == nil then return nil end
        local ok, r = pcall(function() return a:IsA(unitCls) end)
        if not ok then return nil end
        return r == true
    end
    -- an add-on's actor taken off (SVP.despawn, its switch-off): a game unit by its own death, unpaid (left as it is,
    -- with a line, when the game won't let it die), anything else destroyed. -> taken off, how
    local function takeOff(a, p)
        local u = isUnit(a)
        if u == nil then
            plog(p, "an actor left as it is: can't tell whether it's a game unit (one is never destroyed by hand)")
            return false, "unknown"
        end
        if u then
            local done = retireOne(a)
            if not done then plog(p, "a unit left as it is: the game didn't let it die (a unit is never destroyed by hand)") end
            return done == true, "its own death"
        end
        untargetActor(a, "despawned")
        mark(a, "despawned")
        return (pcall(function() a:K2_DestroyActor() end)), "destroyed"
    end
    PLUGINS.takeOff = takeOff
    function SVP.hurt(a, n, causer)
        n = tonumber(n) or 0
        if refused(PLUGINS.running or PLUGINS.current) or n <= 0 or n ~= n or not itself(a, true) then return false end
        if causer ~= nil and not (isHandle(causer) and liveAddr(causer)) then return false end   -- (live before the game reads it)
        local before = healthOf(a)
        if before and before <= 0 then return false, before, before, "dead (left alone)" end
        local isMe = a == myPawn() or (addrOf and myPawn() and addrOf(a) == addrOf(myPawn()))
        if not isMe then
            -- (a hit with NO causer is no one's: if it kills, Survival counts and pays nothing for it, as SVP.retire,
            -- e.g. an add-on's weapon hitting enemy aircraft; a target it kills comes off unpaid. Marked once its health
            -- reads 0, or the actor is gone after the hit. HealthInternal is health x 10, n is in health units)
            local ok = pcall(function() a:ModifyHealth(-n, causer, true) end)
            local after = healthOf(a)
            if causer == nil and ok and ((after and after <= 0) or not liveAddr(a)) then
                untargetActor(a, "killed by a hit of no one's")
                mark(a, "no one's kill")
            end
            return ok, before, after, "ModifyHealth"
        end
        if not before then return false end
        if DOWN and DOWN.me and DOWN.me() == true then return false, before, before, "down" end
        -- the game's own health path when a runtime gives it (hurtPlayer: the player's ModifyHealthInternal, so a
        -- lethal hit is the game's own death); else the health is written and a lethal hit is the stock sure kill.
        -- hurtPlayer takes HEALTH points (MaxHealth units); HealthInternal reads x 10
        local hurt = provider("hurtPlayer")
        if hurt then
            local pa, ca = addrOf and addrOf(a), causer and addrOf and addrOf(causer)
            if pa then
                local okH, rc = pcall(hurt, pa, -n, ca or pa)
                if okH and rc == 1 then return true, before, healthOf(a), "the game's own health path" end
            end
        end
        if before - n * 10 <= 0 then
            if SVP.killPlayer("a hit of " .. n) then return true, before, healthOf(a), "killed" end
        end
        local nv = math.max(10, math.floor(before - n * 10))
        local ok = pcall(function() a.HealthInternal = nv end)
        return ok, before, healthOf(a), "health"
    end
end  -- (sv_plugins.lua's do block goes on in sv_plugins_env.lua)
