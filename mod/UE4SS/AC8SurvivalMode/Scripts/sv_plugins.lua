-- sv_plugins.lua: other mods' special rounds (add-ons, folders in Mods\AC8SurvivalAddons), their API (SVP) and loader.
-- add-on API 2.0
-- (the line above: the API's version for a native mod to read from this file before Lua runs; kept equal to API below
-- by tools/checks/plugins_test.lua. Its form stays "-- add-on API <major>.<minor>" on line 2)
-- (sv_plugins.lua is the first of 3 pieces, split by tools/lua_split_part.py: sv_plugins_api.lua, sv_plugins_env.lua go
-- on from where it ends, run by main.lua right after it, in that order. This note is below the API's line, line 2.)
-- Part of AC8 Survival Mode's runtime, run by main.lua last (after sv_main): a name another part uses is a global of
-- this mod's Lua state, its own helpers stay local (tools/lua_split.py).
--
-- UE4SS gives every Lua mod its own Lua state, so another mod can't reach SPC.kinds from its own main.lua. An add-on is
-- a folder Mods/AC8SurvivalAddons/<name>/ (a sibling of Survival's folder, never shipped in Survival's zip) whose
-- .lua files Survival runs here, in its own Lua state, at Survival's first tick (every part loaded, the tick loop
-- running), in an environment of the add-on's own: Survival's globals are out of its reach (the environment's
-- allow-list, below). It calls SVP.register to add a special kind. Its assets go in its own container.
-- docs/ADDONS.md is the authors' guide, docs/re/PLUGINS.md the internals, docs/ADDONS_MAINTAINING.md the hooks in
-- Survival's own files.
--
-- What an add-on gets (every name 15 characters or fewer, hard rule 25's limit kept for the Lua side too). Every
-- actor or object it hands the API is a UE4SS object (userdata), never a Lua table of its own (isHandle, below):
--   SVP.version, SVP.api        2, { major = 2, minor = 0 }; an add-on's def.api = "2.0" is the lowest it needs (served
--                               by 2.x; none declared: refused); def.requires = native function names it needs;
--                               def.check() = its own readiness
--   SVP.register(kind, def)     a special kind: def.kind = the SPC.kinds entry (spawn, and any of tick, busy, over,
--                               abort, ready, sub, alone, aircraft, budget, hold, disguise: their types checked here,
--                               their answers checked before Survival uses them), def.cfg = its settings' defaults
--                               (CFG.specials[kind], [specials.<kind>] in survival.ini over them), def.rotation = true
--                               to join the rotation, def.name / def.ver (the log, the leaderboard)
--   SVP.target(actor, opts)     a target of the add-on's round: watched every tick of it; down (gone, its address
--                               another object's now (hard rule 59), or no health) it pays opts.pay (x the round's
--                               tier, unless opts.flat; a whole number, 0 to 1,000,000), counts as a ground (or
--                               opts.class "air") kill and calls opts.onDown(id, why). Returns its id. Survival's own
--                               plane sweep pays and counts nothing for it (PLUGINS.owns). Only in the add-on's own
--                               round (its spawn to its over / abort: that round's tick watches it), 256 at most
--   SVP.untarget(id)            taken off the watch, no pay; SVP.kill(id, why) down now, paid; SVP.alive(id): its own
--   SVP.pay(n, why)             zollars (addCredits): a whole number, 0 to 1,000,000; anything else is refused
--   SVP.load(path)              an object of the add-on's own container by its path (sv_core.lua loadObject: hard
--                               rule 9), or nil and why
--   SVP.hold2d(path)            a 2D sound of the add-on's container held ready (its audio component, not playing,
--                               kept for the level): play2d then plays it with no lookup and no spawn
--   SVP.spawn(cls, at, yaw)     an actor of class `cls` (a class or its path, "/Game/Mods/<its own>/...C") at `at`
--                               (X Y Z cm), turned `yaw` degrees; the actor, or nil and why. Survival's own way
--                               (GameplayStatics' deferred spawn, as its effects': sv_anomalies.lua SPC.V.billboard).
--                               Its address and full name are kept: SVP.move / despawn / hurt / retire refuse an actor
--                               whose address is another object's now (hard rule 59)
--   SVP.move(a, at, yaw)        moves (teleports) an add-on's actor; SVP.despawn(a) takes it off: a game object (an
--                               ALiveGameObject) by its own death, unpaid (never destroyed by hand: that crashes AC8
--                               at the next unit death), anything else destroyed (a target: off, unpaid)
--   SVP.players()               { { slot, X, Y, Z } }: you
--   SVP.pad()                   the Comona spaceport's shuttle pad (Mission 22's AA_Obj_01_Ground0_Shuttle_0), cm
--   SVP.runway()                Comona Airport's runway, the spawn anchor (AIRFIELD), cm
--   SVP.clock()                 the rounds' clock (D.now: game time, stops while paused)
--   SVP.round()                 the round number; SVP.run() a token of the run in progress (new each run)
--   SVP.levelGoing()            the level is going away (sv_core.lua levelGoing): touch no object then. Every call
--                               below that touches a game object refuses while it's true
--   SVP.callout(text, sub)      the round callout (hudCallout); SVP.say(who, text, secs) the subtitle strip (SUB.say)
--   SVP.log(msg)                Survival's log, the add-on's name first
--   SVP.isHost(), SVP.inCoop()  API 2.0 is single player: while co-op is open (COOP.open) no add-on round comes, no
--                               add-on job runs and every call that changes the game refuses
--   SVP.every(fn)               fn(now) on the game thread from Survival's own tick (about every 250 ms; the main menu
--                               before the first run too, not from a quit to the next Survival level: going then,
--                               never while the level is being torn down (levelGoing), nor a kind's tick then;
--                               `now` = os.clock()). SVP.going(fn) runs fn(now) once as that starts: an add-on's
--                               round-over flag. An add-on must never use LoopAsync, ExecuteInGameThread,
--                               ExecuteWithDelay or RegisterKeyBind itself: they run its Lua off the game thread in
--                               Survival's one Lua state, which crashes the game (HISTORY 0.73.82)
--   SVP.on(event, fn)           Survival's moments as its tick sees them: "runStart" (the first tick a run exists),
--                               "roundStart" (round: the first tick D.round has a new number), "roundEnd" (round: the
--                               first tick it's changed again or the run is gone), "runEnd" (its last round: the first
--                               tick the run is gone or replaced), "levelGoing" (as SVP.going)
--   SVP.net                     co-op's add-on channel: not in API 2.0 (stubs answering false; SVP.net.ready false)
--   SVP.provide(name, fn)       what an add-on's native mod gives the API: "hurtPlayer"
--   SVP.widget(cls, outer, name) a UMG widget of the add-on's own in outer (a WidgetTree): UMG's concrete classes or a
--                               widget blueprint's, its name made unique; no StaticConstructObject in the environment
--   SVP.liveObj(o)              o still the engine's live object (ask it for anything kept between ticks)
--   SVP.cfg(kind)               its kind's settings, read-only; SVP.pc() your controller; SVP.paused(); SVP.dir() its
--                               folder; SVP.intercept(m) a missile shot down the game's own way (SV_Intercept);
--                               SVP.pin(o, why) o kept loaded until the add-on's off, the run ends or the level goes
--   SVP.bgm(on)                 Survival's music off / back for an add-on's track, always given back
--   SVP.hud(on, why)            Survival's own HUD off / back for an add-on's cutscene (sv_hud.lua HUD.hold: callouts
--                               and lines wait, not lost); always given back, 60 s at most
--   SVP.sound(path, at)         a Wwise event at a spot; SVP.fx(path, at, scale, rot, floats) a Niagara system (the
--                               component back); SVP.play2d(path, vol) a sound wave heard by you alone (ok, length s,
--                               its audio component: :Stop() cuts it short)
--   SVP.playerPlane()           { a, X, Y, Z, VX, VY, VZ, health, down } of your plane, or nil
--   SVP.retire(a)               the game kills one of the add-on's units (finishUnpaid): freed as a stock unit is,
--                               nothing counted or paid for it (a target: off, unpaid)
--   SVP.hurt(a, n, causer)      n damage (MaxHealth units) to an AI object (ModifyHealth; causer nil = no one's kill,
--                               counted and paid to no one; a target it kills: off, unpaid) or your plane (the
--                               hurtPlayer provider, else its health written; a lethal hit is SVP.killPlayer);
--                               SVP.killPlayer(why) the stock sure kill (refused while the landing STORE's gate is
--                               shut: hard rule 64)
-- A kind may also give abort(why): called when the run its round belongs to ends under it (every player down, the
-- level left); without one, over(now, nil), except while the level goes (nothing then). Its targets are taken off
-- unpaid, at its round's end too. Touch no object when why is "the level is going".
-- Every callback of an add-on runs guarded (a pcall, a time limit RUNAWAY_S, a time budget): its first error, a call
-- still running RUNAWAY_S after it began, three calls over 2 s within 60 s, or more than BUDGET_MS of the game thread
-- within BUDGET_S switch the add-on off for the session. Its round, if one is on, ends as soon as Survival's checks
-- allow (busy false), its targets come off unpaid, what it spawned is taken off, Survival's music and HUD come back.
-- A run with any add-on found in AC8SurvivalAddons (loaded or not) isn't ranked (sv_leaderboard.lua LB.edited lists it),
-- as with survival_config.lua. PLUGINS.loaded is filled before any add-on runs, and no add-on can reach it.

PLUGINS = { loaded = {}, kinds = {}, targets = {}, nextId = 0, marks = {}, ids = {}, owners = {}, tkeys = {}, level = 0,
            calls = 0 }

do
    -- the add-on API's version: an add-on declares the lowest it needs (def.api = "2.0"); a minor version only adds
    -- calls, so every add-on of a lower minor keeps working
    local API = { major = 2, minor = 0 }
    -- Mission 22's shuttle (AA_Obj_01_Ground0_Shuttle_0), x / y / z cm: docs/re/SPECIAL_ROUNDS.md "The shuttle"
    SHUTTLE_PAD = { X = -1324937.0, Y = 59740.0, Z = 6343.0 }
    local NAME_MAX = 15
    -- every guarded call in progress, outermost first (hooked, below: the runaway stop)
    frames = {}
    -- the framework's own pcall: a runaway stop that one catches (an add-on's metamethod, or its callback, run inside
    -- it) is raised on, so it reaches the guarded call it belongs to. hooked's pcall is the raw one
    local rawPcall = pcall
    local pcall = function(f, ...)
        local r = table.pack(rawPcall(f, ...))
        if frames.runaway then error(frames.runaway, 0) end
        return table.unpack(r, 1, r.n)
    end
PLUGINS.pcall = pcall                              -- (pcall, handed to sv_plugins.lua's later pieces: tools/lua_split_part.py)

    -- tostring that can't raise and runs nothing of an add-on's: a table with a metatable (an add-on's __tostring could
    -- loop or raise outside its guard) isn't asked
    function str(v)
        if type(v) == "string" then return v end
        if type(v) == "table" and getmetatable(v) ~= nil then return "(a table)" end
        local ok, s = pcall(tostring, v)
        return (ok and type(s) == "string") and s or "(a value that can't be printed)"
    end
    function plog(p, msg)                                -- (control characters out: an add-on's text is one line)
        log((("plugin " .. tostring(p and p.name or "?") .. ": " .. str(msg)):gsub("%c", " ")))
    end

    -- One add-on can't stall Survival: a callback over STALL_OFF_MS is logged, and STALL_OFF_N of them within
    -- STALL_WINDOW_S seconds switch the add-on off as an error does (a sustained stall). One long call alone is a hitch,
    -- not a stall: switching a round off mid-fight for it is worse than the hitch (a heavy round's fight start took
    -- 2.4 s once, under a GPU render: one call, then normal ticks). STALL_WARN_MS three times in a row is said once.
    local STALL_WARN_MS, STALL_OFF_MS, STALL_OFF_N, STALL_WINDOW_S = 100, 2000, 3, 60
    -- A call that never returns (a runaway loop): a count hook (debug.sethook, every RUNAWAY_N Lua instructions) raises
    -- in it once it has run RUNAWAY_S, at load too (the longest an add-on's call has taken in a test: 2.7 s, one fight
    -- start under a GPU render). A C function that never returns can't be stopped by it, nor a loop in a coroutine of
    -- the add-on's own (the hook is the calling coroutine's).
    -- A slow call on every tick (each under 2 s): BUDGET_MS of the game thread within BUDGET_S switch the add-on off
    -- (the heaviest add-on round seen took 2.9 s in its worst 30 s, that 2.4 s call in it).
    local RUNAWAY_S, RUNAWAY_N, BUDGET_MS, BUDGET_S = 10, 100000, 6000, 30
    local PAY_MAX = 1000000                              -- (SVP.pay / a target's pay: zollars a call, at most)

    -- Survival's music muted for an add-on's own track (SVP.bgm), and ALWAYS given back: at its round's end, its run's
    -- end, the level going, or the add-on switched off. SV_PlayBGM is refused while a level is torn down: Survival's
    -- own sound tick then posts the unmute in the next level (sv_sound.lua unmuteTick).
    -- (one mute for every holder: the last add-on to give it back unmutes, and never under Survival's own song)
    function PLUGINS.bgmHeld(but)
        for _, q in ipairs(PLUGINS.loaded) do if q ~= but and q.bgmMuted then return true end end
        return false
    end
    function bgmBack(p, why)
        if not (p and p.bgmMuted) then return end
        p.bgmMuted = false
        if type(SND) == "table" and type(SND.song) == "table" and SND.song.muted then   -- (Survival's own song mutes it)
            plog(p, "Survival's music given back (" .. str(why) .. "): Survival's own song keeps the game's muted")
            return
        end
        if PLUGINS.bgmHeld(p) then
            plog(p, "Survival's music given back (" .. str(why) .. "): another add-on's track keeps it muted")
            return
        end
        local ok, r = false, nil
        if type(SV_PlayBGM) == "function" then ok, r = pcall(SV_PlayBGM, "AKE_System_BGM_Mute_Off") end
        ok = ok and type(r) == "number" and r > 0
        if not ok and type(SND) == "table" then SND.unmuteDue, SND.unmuteAt, SND.unmuteTries = true, nil, 0 end
        plog(p, "Survival's music given back (" .. str(why) .. ")" .. (ok and "" or ": left to Survival's sound tick"))
    end
    PLUGINS.bgmBack = bgmBack

    -- Survival's own HUD hidden for an add-on's cutscene (SVP.hud), and ALWAYS given back: at its round's end, its run's
    -- end, the level going, the add-on switched off, or HUD_MAX_S after it was hidden. Survival's own hold
    -- (sv_hud.lua HUD.hold, one holder per add-on: "add-on <name>"): the panel, the callout banner and the subtitle strip
    -- off, callouts and lines said meanwhile wait and show after; a new run drops the hold by itself.
    HUD_MAX_S = 60
    function holdName(p) return "add-on " .. tostring(p.folder or p.name) end   -- (its folder: one hold an add-on)
    function hudBack(p, why)
        if not (p and p.hudHidden) then return end
        p.hudHidden = nil
        if HUD and type(HUD.hold) == "function" then pcall(HUD.hold, false, holdName(p)) end
        plog(p, "Survival's HUD given back (" .. str(why) .. ")")
    end
    PLUGINS.hudBack = hudBack

    -- An actor or object handle an add-on gives the API is a UE4SS object (userdata), never a Lua table: a table's
    -- methods and fields (GetAddress, GetFullName, IsValid, HealthInternal) are the add-on's own code, which the API
    -- would run outside its guard (the targets' sweep runs in Survival's tick). Every SVP call taking a handle (target,
    -- move, despawn, retire, hurt and its causer, pin, intercept, liveObj, widget's class and outer, spawn's class) refuses
    -- anything else before touching it.
    function isHandle(a)
        if type(a) == "userdata" then return true end
        -- TEST ONLY BEGIN (PLUGINS.fakeHandles: tools/checks/plugins_test.lua's stand-ins, a set the test alone fills)
        local f = PLUGINS.fakeHandles
        if f ~= nil and type(a) == "table" and f[a] == true then return true end
        -- TEST ONLY END
        return false
    end
    PLUGINS.isHandle = isHandle
    -- (hard rule 59) the game reuses a freed object's address and liveAddr passes for whatever lives there now: every
    -- actor handle an add-on gives the API, or gets from SVP.spawn, is recorded with the full name of its object and
    -- the level it was recorded in (PLUGINS.ids, weak-keyed on the handle itself, as keptId below: a new handle for the
    -- object now at a reused address is a record of its own), and is still itself only while the name at its address
    -- is the same (ESC.same's way, sv_escort_laser.lua) and in that level: a handle kept from an older level is
    -- refused, never recorded again as new (PLUGINS.level goes up at the going tick; the records stay). Read before a
    -- call that changes the game (hurt, move, retire, despawn, a take-off, a re-target) once in each add-on call (the
    -- engine frees an object's memory only in a garbage collection's purge, which never runs inside a Lua call, so
    -- within one call a name read stays true; PLUGINS.calls counts the calls), at most once a second for the targets'
    -- watch. A handle the API hasn't seen is recorded at its first call, so a later one with it is checked.
    function fullName(o)
        local ok, n = pcall(function() return o:GetFullName() end)
        return (ok and type(n) == "string" and n ~= "") and n or nil
    end
    local function shortName(full) return full and (full:match("([^%.:]+)$") or full) or nil end   -- (sv_core.lua's `short`)
    function keyOf(a) if not isHandle(a) then return nil end local ok, k = pcall(addrOf, a); return ok and k or nil end
    local function newIds() return setmetatable({}, { __mode = "k" }) end
    PLUGINS.ids = newIds()
    -- p: the add-on it's the actor of (SVP.spawn's, SVP.target's), nil for one only seen (a hurt): its owner by address
    -- and name (PLUGINS.owners: another add-on's fresh handle of the same object finds it) kept as the first. n: the
    -- name just read (itself's), else read here
    function remember(a, p, n)
        if not isHandle(a) then return nil, nil end
        local k = keyOf(a)
        n = n or fullName(a)
        if k ~= nil and n then
            local r = PLUGINS.ids[a]
            if r and r.name == n and r.level == PLUGINS.level then r.p = r.p or p
            else PLUGINS.ids[a] = { name = n, p = p, sameAt = os.clock() + 1, level = PLUGINS.level, readAt = PLUGINS.calls } end
            local o = PLUGINS.owners[k]
            if p and not (o and o.name == n) then PLUGINS.owners[k] = { p = p, name = n } end
        end
        return k, n
    end
    -- -> true, nil, its name; or false and "not a handle" / "gone" / "reused" (another object's address now) / "an older
    -- level's". fresh: the name read in this add-on call (before a call that changes the game), else at most once a
    -- second (the targets' watch)
    function itself(a, fresh)
        if not isHandle(a) then return false, "not a handle" end
        local r = PLUGINS.ids[a]
        if r and r.level ~= PLUGINS.level then return false, "an older level's" end
        if not liveAddr(a) then return false, "gone" end
        if not r then local _, n = remember(a, nil); return n ~= nil, n == nil and "gone" or nil, n end
        if r.reused then return false, "reused" end
        local c = os.clock()
        if (fresh and r.readAt == PLUGINS.calls) or (not fresh and c < (r.sameAt or 0)) then return true, nil, r.name end
        if fullName(a) ~= r.name then r.reused = true; return false, "reused" end
        r.sameAt, r.readAt = c + 1, PLUGINS.calls
        return true, nil, r.name
    end
    PLUGINS.itself = itself

    -- an add-on's units Survival's plane sweep must not count or pay (its targets: the API pays them; its retired
    -- units: nobody's): their address with the short name Survival keeps for a plane (planes[i].name), for this run
    function mark(a, why, full)
        local k, n = keyOf(a), shortName(full or fullName(a))
        if k == nil or n == nil then return end            -- (a mark is honoured only with its name: none, no mark)
        PLUGINS.marks[k] = { name = n, run = D, why = why }
    end
    -- (sv_main.lua planeSweep, for a plane still up, and sv_stats.lua's tail watch) whether it's one of an add-on's
    -- targets now: a mark of this run at its address with its name (another object at that address since: Survival's
    -- own). Not used up: asked every sweep. The sweep then leaves the plane alone entirely (no tier, no manoeuvres, no
    -- spike, no hunt, no stats), as the tail watch does.
    function PLUGINS.owned(rec)
        if not rec then return false end
        local k = rec.addr
        if k == nil and rec.obj ~= nil then k = keyOf(rec.obj); rec.addr = k end
        local m = k ~= nil and PLUGINS.marks[k]
        if not m or m.run ~= D then return false end
        return m.name ~= nil and rec.name ~= nil and m.name == rec.name
    end
    -- (sv_main.lua planeSweep, for a plane seen down) whether it's an add-on's: a mark of this run at its address with
    -- its name (another object at that address since: Survival's own). A mark is used once.
    function PLUGINS.owns(rec)
        local k = rec and (rec.addr or (rec.obj ~= nil and keyOf(rec.obj)))
        local m = k ~= nil and PLUGINS.marks[k]
        if not m then return false end
        PLUGINS.marks[k] = nil
        if m.run ~= D or m.name == nil or rec.name == nil or m.name ~= rec.name then return false end
        PLUGINS.retiredSeen = (PLUGINS.retiredSeen or 0) + 1
        return true
    end

    -- a target off the watch (PLUGINS.tkeys counts the targets at each address; p.nTargets each add-on's). keepMark
    -- false: unpaid and its plane Survival's again, its mark going with it unless another of the add-ons' targets is at
    -- that address (the same actor targeted twice); true: the mark stays (a target that went down, was retired or was
    -- killed by a hit of no one's: down, untargetActor)
    function forget(id, t, keepMark)
        PLUGINS.targets[id] = nil
        t.p.nTargets = math.max(0, (t.p.nTargets or 1) - 1)
        local k = t.key
        if k == nil then return end
        local n = (PLUGINS.tkeys[k] or 1) - 1
        PLUGINS.tkeys[k] = n > 0 and n or nil
        if n <= 0 and not keepMark then
            local m = PLUGINS.marks[k]
            if m and m.why == "target" then PLUGINS.marks[k] = nil end
        end
    end
    local function dropTarget(id)
        local t = PLUGINS.targets[id]
        if t then forget(id, t, false) end
    end
    local function dropTargets(p)                          -- (every target of add-on p, in one pass) -> how many
        local n = 0
        for id, t in pairs(PLUGINS.targets) do if t.p == p then forget(id, t, false); n = n + 1 end end   -- (nil-ing a field in a pairs walk: allowed)
        p.sweepList = nil
        return n
    end
    -- every add-on's targets dropped, unpaid (a run's end, the level going): a fresh list, said for each add-on that
    -- had some
    function dropAllTargets(why)
        for _, p in ipairs(PLUGINS.loaded) do
            if (p.nTargets or 0) > 0 then plog(p, p.nTargets .. " targets dropped (" .. why .. "): unpaid, Survival's again") end
            p.nTargets, p.sweepList = 0, nil
        end
        PLUGINS.targets, PLUGINS.tkeys = {}, {}
    end

    -- API 2.0 is single player: while co-op is open (a host waiting or playing, a joiner) nothing of an add-on runs
    function coopOpen() return COOP ~= nil and COOP.open == true end
    -- why an add-on's call that touches the game is refused now, or nil. A call with no add-on attached (not from its
    -- load or a guarded callback of it) is refused too: nothing of an add-on's acts outside the guard
    function refused(p)
        if SVP.levelGoing() then return "the level is going" end
        if coopOpen() then return "co-op is open" end
        if not p then return "no add-on is calling (only from its load or its callbacks)" end
        if p.off then return "switched off" end
        return nil
    end

    -- an add-on switched off for the session: its round ends as soon as Survival's checks allow (busy false), its
    -- targets come off unpaid, Survival's music is given back
    -- (what it spawned (SVP.spawn) is taken off, unless the level is going: its own over / abort won't run now)
    function PLUGINS.switchOff(p, why)
        if p.off then return end
        p.off, p.takeOffDue = true, true                   -- (what it spawned: taken off at the next PLUGINS.tick)
        plog(p, str(why) .. ": the add-on is switched off for this session")
        crumb("plugin " .. tostring(p.name) .. " off")
        dropTargets(p)
        bgmBack(p, "switched off")
        hudBack(p, "switched off")
        if PLUGINS.unpinAll then PLUGINS.unpinAll(p, "switched off") end
        if PLUGINS.dropNotify then PLUGINS.dropNotify(p) end
    end                                                    -- (a switch-off can come from inside Survival's own code)
    -- (PLUGINS.tick, the game thread, not while the level goes) what a switched-off add-on spawned, taken off: only one
    -- still known by its address and full name; a game unit by its own death, never destroyed (PLUGINS.takeOff)
    function takeOffTick()
        for _, p in ipairs(PLUGINS.loaded) do
            if p.takeOffDue then
                p.takeOffDue = nil
                local n = 0
                for _, a in ipairs(p.spawned or {}) do
                    local k = keyOf(a)
                    if k ~= nil and PLUGINS.ids[a] and itself(a, true)
                        and select(2, pcall(PLUGINS.takeOff, a, p)) == true then n = n + 1 end
                end
                p.spawned = {}
                if n > 0 then plog(p, n .. " of its actors taken off") end
            end
        end
    end

    -- fn(...) in a pcall with the runaway hook, for add-on p: table.pack of pcall's answers.
    -- One hook for every guarded call in progress (frames, outermost first). A call inside another (an add-on's SVP call
    -- that runs another guarded callback: an onDown, a provider) keeps the hook as it is, so the count isn't restarted,
    -- and the outermost call's deadline is the first to run out. Run out: frames.runaway is set and raised, and
    -- frames.culprit is the add-on that loops (below), not necessarily the one that called it. While it's set, an add-on's own pcall / xpcall and the framework's pcall pass it straight on,
    -- xpcall's handler isn't called for it (a handler runs inside the hook, where no hook stops a loop), and an inner
    -- guarded call passes it on to the outermost, which answers it with the culprit: guard switches that add-on off.
    -- Each call pushes its frame inside its pcall and cuts frames back to its own depth on every way out, so an error
    -- anywhere (a stop between the push and the call, or in an inner call's own lines) leaves them balanced; the hook
    -- never raises in hooked's own lines (the outermost's pcall has returned there: nothing would catch it), and the
    -- outermost clears the stop. Another's Lua hook (a profiler's) is still called from this one.
    -- The stop is raised only in the add-on's own code: raised inside Survival's (an SVP call, HUD.hold), it would cut a
    -- step of Survival's from the flag that records it (the HUD hidden, p.hudHidden not yet set: never given back).
    -- There the hook comes back after RUNAWAY_SOON instructions, the call's own lines being short; past RUNAWAY_GRACE_S
    -- more it's raised wherever it lands. Survival's code: its Scripts folder's chunks, the family's own pieces
    -- (PLUGINS.ownSrc); an add-on's chunk names can't be made to look like them (its load / loadfile name them)
    -- The culprit: the innermost frame that has itself run RUNAWAY_S / 2 (a provider called a moment ago by a looping
    -- add-on isn't the one that loops), else the outermost; for the memory limit, the innermost that has itself grown
    -- Lua's heap by half the limit.
    local canHook = type(debug) == "table" and type(debug.sethook) == "function" and type(debug.gethook) == "function"
    local RUNAWAY_GRACE_S, RUNAWAY_SOON = 5, 1000
    local svDir = canHook and type(debug.getinfo) == "function" and (debug.getinfo(1, "S").source or ""):match("^(@.*[/\\])") or nil
    PLUGINS.ownSrc = { [canHook and type(debug.getinfo) == "function" and debug.getinfo(1, "S").source or "?"] = true }
    local function survivalCode(src)
        if type(src) ~= "string" then return true end
        if src:find("AC8SurvivalAddons", 1, true) or src:sub(1, 1) == "=" then return false end   -- (an add-on's chunk)
        if PLUGINS.ownSrc[src] then return true end
        return svDir ~= nil and src:sub(1, #svDir) == svDir
    end
    hooked = nil
    -- (a loop that allocates runs out of memory long before 10 s: RUNAWAY_KB more of Lua's heap since the outermost call
    -- began stops it the same way; PLUGINS.runawayKB: a test's smaller limit)
    local RUNAWAY_KB = 256 * 1024
    local function runawayHook(ev, line)
        local f = frames[1]
        local now = os.clock()
        local over = f and ((now > f.deadline and string.format("still running %d s after it began", RUNAWAY_S))
            or (collectgarbage("count") - f.mem > (PLUGINS.runawayKB or RUNAWAY_KB)
                and string.format("%d MB more Lua memory since it began", (PLUGINS.runawayKB or RUNAWAY_KB) // 1024)))
        if over then
            local info = debug.getinfo(2, "Slf")
            if info and info.func == hooked then return end
            if not frames.runaway and info and survivalCode(info.source) then
                f.graceUntil = f.graceUntil or now + RUNAWAY_GRACE_S
                if now < f.graceUntil then debug.sethook(runawayHook, "", RUNAWAY_SOON); return end
            end
            if not frames.runaway then
                local at = (info and info.currentline and info.currentline > 0) and (info.short_src .. ":" .. info.currentline .. ": ") or ""
                frames.runaway = string.format("%s%s (a runaway loop)", at, over)
                local who, mem = frames[1], now <= f.deadline and collectgarbage("count") or nil
                for i = #frames, 1, -1 do
                    local fi = frames[i]
                    if (mem and mem - fi.mem >= (PLUGINS.runawayKB or RUNAWAY_KB) / 2)
                        or (not mem and now - fi.start >= RUNAWAY_S / 2) then who = fi; break end
                end
                frames.culprit = who and who.p
            end
            error(frames.runaway, 0)
        end
        if frames.chain then frames.chain(ev, line) end
    end
    local function enter(depth, p, fn, ...)                -- (inside hooked's pcall: its frame, then the call)
        local t = os.clock()
        frames[depth + 1] = { p = p, start = t, deadline = t + RUNAWAY_S, mem = collectgarbage("count") }
        return fn(...)
    end
    hooked = function(p, fn, ...)
        if not canHook then
            PLUGINS.calls = PLUGINS.calls + 1
            local r = table.pack(rawPcall(fn, ...))
            PLUGINS.calls = PLUGINS.calls + 1
            return r
        end
        local hf, hm, hc = debug.gethook()
        local mine = hf == runawayHook
        if not mine and hf ~= nil and type(hf) ~= "function" then          -- (another's C hook: left; the calls counted)
            local outer = #frames == 0
            if outer then PLUGINS.calls = PLUGINS.calls + 1 end
            local r = table.pack(rawPcall(fn, ...))
            if outer then PLUGINS.calls = PLUGINS.calls + 1 end
            return r
        end
        local depth, chain = #frames, frames.chain
        if depth == 0 then PLUGINS.calls = PLUGINS.calls + 1 end   -- (a new add-on call: itself reads names again)
        if not mine then frames.chain = hf; debug.sethook(runawayHook, "", RUNAWAY_N) end
        local res = table.pack(rawPcall(enter, depth, p, fn, ...))
        for i = #frames, depth + 1, -1 do frames[i] = nil end   -- (back to its own depth, whatever was left above it)
        if depth == 0 then PLUGINS.calls = PLUGINS.calls + 1 end
        if not mine then debug.sethook(hf, hm, hc); frames.chain = chain end   -- (the hook as it was before, or none)
        if frames.runaway then
            if depth > 0 then return { false, frames.runaway, n = 2, passOn = true } end   -- (an outer call's: guard raises it on)
            res = { false, frames.runaway, n = 2, culprit = frames.culprit }
            frames.runaway, frames.culprit = nil, nil
        end
        return res
    end
    PLUGINS.hooked = hooked
    -- an add-on's game-thread time in BUDGET_S (10 s slices): over BUDGET_MS, it's switched off
    local function spend(p, ms, now)
        local b = p.spent or {}
        p.spent = b
        local slot = math.floor(now / 10)
        b[slot] = (b[slot] or 0) + ms
        local sum = 0
        for s, v in pairs(b) do if s <= slot - BUDGET_S / 10 then b[s] = nil else sum = sum + v end end
        return sum
    end

    -- an add-on's callback, guarded: its first error switches the add-on off. A runaway stop whose culprit is another
    -- add-on (its callback ran inside this one's call: an onDown, a provider) switches that one off; this call answers
    -- the fallback and its add-on stays on. nil stays nil (no callback: callers test it); any other non-function is a
    -- stub answering the fallback (never called bare: a callable table would run outside the guard)
    function guard(p, what, fn, fallback)
        if fn == nil then return nil end
        if type(fn) ~= "function" then return function() return fallback end end
        return function(...)
            if p.off then return fallback end
            local prev = PLUGINS.running
            PLUGINS.running = p                     -- (SVP.target from inside a callback: the target is this add-on's)
            local t0 = os.clock()
            local res = hooked(p, fn, ...)
            local ms = (os.clock() - t0) * 1000
            PLUGINS.running = prev
            if res.passOn then error(res[2], 0) end     -- (the outer call's runaway, not this one's: on to that call)
            if not res[1] and res.culprit and res.culprit ~= p then
                PLUGINS.switchOff(res.culprit, str(res[2]) .. " (in its callback, inside " .. tostring(p.name) .. "'s " .. what .. ")")
                plog(p, what .. ": stopped, " .. tostring(res.culprit.name) .. "'s callback inside it ran away (this add-on stays on)")
                return fallback
            end
            if res[1] and ms > STALL_OFF_MS and prev ~= p then   -- (a call inside another of its own: that one's stall)
                local now, kept = os.clock(), {}
                for _, t in ipairs(p.stalls or {}) do if now - t < STALL_WINDOW_S then kept[#kept + 1] = t end end
                kept[#kept + 1] = now
                p.stalls = kept
                if #kept >= STALL_OFF_N then
                    PLUGINS.switchOff(p, string.format("%s took %.0f ms, the %d%s call over %d ms within %d s (a stall)",
                        what, ms, #kept, #kept == 3 and "rd" or "th", STALL_OFF_MS, STALL_WINDOW_S))
                    return fallback
                end
                plog(p, string.format("%s took %.0f ms (over %d ms: a hitch; %d of %d within %d s switch the add-on off)",
                    what, ms, STALL_OFF_MS, #kept, STALL_OFF_N, STALL_WINDOW_S))
            end
            if res[1] and prev ~= p then            -- (a call inside another of its own is in that one's time)
                local sum = spend(p, ms, os.clock())
                if sum > BUDGET_MS then
                    PLUGINS.switchOff(p, string.format("%s: %.1f s of the game thread within %d s (its budget: %.1f s)",
                        what, sum / 1000, BUDGET_S, BUDGET_MS / 1000))
                    return fallback
                end
            end
            if res[1] and ms > STALL_WARN_MS then
                p.slow = (p.slow or 0) + 1
                if p.slow == 3 then plog(p, string.format("%s took %.0f ms, 3 slow calls in a row (over %d ms): the game hitches", what, ms, STALL_WARN_MS)) end
            elseif res[1] then
                p.slow = 0
            end
            if res[1] then return table.unpack(res, 2, res.n) end
            PLUGINS.switchOff(p, what .. " error " .. str(res[2]))
            return fallback
        end
    end

    -- [specials.<kind>] read from survival.ini over the plugin's defaults (survival.ini was read before any plugin
    -- existed, so its section was skipped then, "no section"). Each value takes its default's type.
    local function iniOver(kind, t)
        local f = io.open(SCRIPT_DIR .. "..\\config\\survival.ini", "r")
        if not f then return 0 end
        local want, inSec, n = ("specials." .. kind):lower(), false, 0
        for line in f:lines() do
            line = line:gsub("^\239\187\191", ""):gsub("%s*[;#].*$", ""):match("^%s*(.-)%s*$")
            local sec = line:match("^%[%s*(.-)%s*%]$")
            if sec then inSec = (sec:lower() == want)
            elseif inSec and line ~= "" then
                local key, val = line:match("^([^=]-)%s*=%s*(.*)$")
                local field = nil
                if key then for k in pairs(t) do if type(k) == "string" and k:lower() == key:lower() then field = k end end end
                if field then
                    local old, v = t[field], nil
                    if type(old) == "number" then v = tonumber(val)
                    elseif type(old) == "boolean" then
                        if val:lower() == "true" then v = true elseif val:lower() == "false" then v = false end
                    elseif type(old) == "string" then v = val
                    elseif type(old) == "table" then
                        v = {}
                        for item in val:gmatch("[^,]+") do
                            local s = item:match("^%s*(.-)%s*$")
                            if s ~= "" then v[#v + 1] = tonumber(s) or s end
                        end
                    end
                    if v ~= nil then t[field], n = v, n + 1 end
                end
            end
        end
        f:close()
        return n
    end

    local function sameList(a, b)
        if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end

    local function inList(l, v) for _, x in ipairs(l or {}) do if x == v then return true end end return false end

    -- the targets' watch: a target is down when its actor is gone (or its address is another object's now: itself)
    -- or its health is 0
    local function same(t)
        if t.reused then return false end
        local ok, why = itself(t.actor)
        if not ok and why == "reused" then t.reused = true end
        return ok
    end
    -- pay as Survival can take it: a whole number, 0 to PAY_MAX; nil for anything that isn't a finite number
    function money(n)
        n = tonumber(n)
        if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
        return math.tointeger(math.floor(math.max(0, math.min(PAY_MAX, n)) + 0.5))
    end
    PLUGINS.money = money
    function healthOf(o)
        local ok, h = pcall(function() return o.HealthInternal end)
        if ok and type(h) == "number" then return h end
        return nil
    end
    function down(id, t, why)
        forget(id, t, true)
        local o = t.opts
        local pay = money(o.pay)
        if pay == nil and o.pay ~= nil then plog(t.p, "target " .. id .. ": its pay " .. str(o.pay) .. " isn't a number: unpaid") end
        pay = pay or 0
        if pay > 0 and not o.flat and TIER and TIER.pay then
            pay = money(TIER.pay(pay * TIER.specialX(), D and D.round and TIER.index(D.round))) or 0
        end
        if pay > 0 then addCredits(pay, string.format("%s: %s down", tostring(t.p.name), str(o.label or ("target " .. id)))) end
        if LB and LB.stat then LB.stat(o.class == "air" and "air" or "ground", 1) end
        plog(t.p, string.format("target %d (%s) down (%s; +%d)", id, str(o.label or "?"), why, pay))
        if type(o.onDown) == "function" then guard(t.p, "onDown", o.onDown)(id, why) end
    end
    -- (a slice a tick, SWEEP_N targets: a round of 150 targets read in one tick cost the game thread; a target's death
    -- is seen within a few ticks)
    local SWEEP_N = 24
    local function sweep(p)
        if p.off then dropTargets(p); return end
        local L = p.sweepList
        if not L or p.sweepI > #L then
            L = {}
            for id, t in pairs(PLUGINS.targets) do if t.p == p then L[#L + 1] = id end end
            p.sweepList, p.sweepI = L, 1
        end
        local stop = math.min(#L, p.sweepI + SWEEP_N - 1)
        for i = p.sweepI, stop do
            local id = L[i]
            local t = PLUGINS.targets[id]
            if t then
                if not same(t) then down(id, t, t.reused and "gone (its address is another object's now)" or "gone")
                else
                    local h = healthOf(t.actor)
                    if h and h <= 0 then down(id, t, "no health") end
                end
            end
        end
        p.sweepI = stop + 1
    end

    -- the game-thread cost of a plugin's work (its tick + the API's sweep, its `every` jobs): a summary in the log every
    -- 30 s while it runs, worst first (a game-thread job should stay under ~5 ms)
    function perf(p, what, ms)
        local P = p.perf or { at = os.clock() }
        p.perf = P
        local e = P[what] or { n = 0, sum = 0, max = 0, over = 0 }
        P[what] = e
        e.n, e.sum = e.n + 1, e.sum + ms
        if ms > e.max then e.max = ms end
        if ms > 5 then e.over = e.over + 1 end
        if os.clock() - P.at >= 30 then
            local parts = {}
            for k, v in pairs(P) do
                if type(v) == "table" then
                    parts[#parts + 1] = string.format("%s avg %.2f / max %.1f ms over %d calls (%d over 5 ms)", k, v.sum / v.n, v.max, v.n, v.over)
                end
            end
            table.sort(parts)
            plog(p, "per-tick cost: " .. table.concat(parts, "; "))
            p.perf = { at = os.clock() }
        end
    end
    PLUGINS.perf = perf

    -- a kind's fields as Survival's own code uses them (sv_rounds.lua / sv_spawn.lua): what each may be, and its answer
    -- made safe before Survival's own startRound reads it (an answer that isn't one: Survival's own value)
    local function count(v) v = tonumber(v); if v == nil or v ~= v or v < 0 or v == math.huge then return nil end return math.floor(v) end
    local FIELDS = {
        spawn = { fn = true }, tick = { fn = true }, busy = { fn = true }, over = { fn = true }, abort = { fn = true },
        ready = { fn = true }, hold = { fn = true },
        -- (SPC.kindValue(k.aircraft): a count, the round's aircraft it takes; nothing usable = none)
        aircraft = { fn = true, value = "number", ok = function(v) return count(v) or 0 end },
        -- (spk.budget(budget): the fighters it wants; nothing usable = the round's own budget)
        budget = { fn = true, ok = function(v, b) return count(v) or b end },
        alone = { fn = true, value = "boolean", ok = function(v) return v == true end },
        disguise = { fn = true, value = "boolean", ok = function(v) return v == true end },
        -- (k.sub(t) or t[k.sub]: the callout's second line, a string or none)
        sub = { fn = true, value = "string", ok = function(v) return type(v) == "string" and v or nil end },
        -- (sv_hud.lua: kind.row(D.special, t), the HUD's round row: a string or none)
        row = { fn = true, ok = function(v) return type(v) == "string" and v or nil end },
    }
    -- nil, or why def.kind can't be used (a field Survival doesn't use is left out, with one line: unused)
    local function badKind(k, unused)
        for name, v in pairs(k) do
            local f, tv = FIELDS[name], type(v)
            if not f then
                unused[#unused + 1] = tostring(name)
            elseif not ((f.fn and tv == "function") or (f.value and tv == f.value)) then
                return "def.kind." .. name .. " must be " .. (f.value and ("a function or a " .. f.value) or "a function")
            elseif name == "aircraft" and tv == "number" and count(v) == nil then
                return "def.kind.aircraft must be a count (0 or more)"
            end
        end
        return nil
    end

    -- a read-only view of a table: read, walk (pairs, ipairs, #) but never change it (SVP.cfg's settings, and the
    -- round's record Survival hands a kind's tick / busy / over / row: Survival's round logic reads its state)
    -- (one cache of views an add-on: a rawset on a view, which no metatable can refuse, shadows Survival's value for
    -- that add-on alone)
    local roCaches = setmetatable({}, { __mode = "k" })
    function readOnly(t, p)
        if type(t) ~= "table" then return t end
        local key = p or roCaches
        local cache = roCaches[key]
        if not cache then cache = setmetatable({}, { __mode = "k" }); roCaches[key] = cache end
        local v = cache[t]
        if v then return v end
        v = setmetatable({}, {
            __index = function(_, k) return readOnly(t[k], p) end,
            __newindex = function() error("Survival's tables are read-only for an add-on", 2) end,
            __pairs = function()
                local k
                return function()
                    local x
                    k, x = next(t, k)
                    if k ~= nil then return k, readOnly(x, p) end
                    return nil
                end, nil, nil
            end,
            __len = function() return #t end,
            __metatable = false,
        })
        cache[t] = v
        return v
    end
    -- the SPC.kinds entry Survival runs for an add-on's kind: every callback guarded and its answer checked; tick also
    -- watches its targets; busy is false once the add-on is off, so its round can end
    local function kindEntry(p, k, check, kind)
        local e = {}
        check = guard(p, "check", check, false)
        for name, v in pairs(k) do
            local f = FIELDS[name]
            if not f then                              -- (not a field Survival uses: left out, badKind said so)
            elseif type(v) == "function" then
                local g = guard(p, name, v, nil)
                local h = function(a, b, ...) return g(readOnly(a, p), readOnly(b, p), ...) end   -- (Survival's tables: read-only)
                e[name] = f.ok and function(a, ...) return f.ok(h(a, ...), a) end or h
            else
                e[name] = f.ok and f.ok(v) or v
            end
        end
        local tick, busy, ready, spawn = e.tick, e.busy, e.ready, e.spawn
        p.entry = e
        e.tick = function(now, s)
            if levelGoing and levelGoing() then return end     -- (the round-over rule: no tick while the level goes)
            if p.off or coopOpen() then return end
            -- (only in its round: from its spawn to its over. Survival ticks a special from its round's start, while its
            -- spawn waits for the spawns' hold, and on through the break after its over)
            if p.liveRun ~= D or p.liveKind ~= kind then return end
            local t0 = os.clock()
            sweep(p)
            local t1 = os.clock()
            local r = table.pack(tick and tick(now, s))
            local t2 = os.clock()
            perf(p, "sweep", (t1 - t0) * 1000)
            perf(p, "tick", (t2 - t1) * 1000)
            return table.unpack(r, 1, r.n)
        end
        e.busy = function(s) if p.off then return false end return busy and busy(s) == true or false end
        e.ready = function(round, forced)
            if p.off or coopOpen() then return false end            -- (API 2.0: single player)
            -- (Survival's specials bag asks with no round (sv_spawn.lua bagFill): the round in play, else 0. Survival keeps a
            -- kind out before its from_round itself (sv_spawn.lua specialReady), so ready answers what else rules it out
            -- now: a no keeps it out of the bag, as Survival's own once-a-run kinds)
            round = tonumber(round) or (D and tonumber(D.round)) or 0
            if check then
                -- (the add-on's own readiness: its native mod, its data. No = its round skipped, Survival's normal wave;
                -- said once a run for each reason)
                local ok, why = check()
                if ok ~= true then
                    local key = tostring(D) .. "|" .. str(why)
                    if p.checkSaid ~= key then p.checkSaid = key; plog(p, "its round skipped: " .. str(why or "not ready")) end
                    return false
                end
            end
            if ready then return ready(round, forced) == true end
            return true
        end
        e.spawn = function(now)
            if p.off or coopOpen() then return false end            -- (never in co-op: ready says so first)
            -- (the run this round belongs to, set before its spawn: SVP.target works from there; PLUGINS.tick's run-over
            -- check; its kind: only that one's abort / over when its run ends)
            p.liveRun, p.liveKind = D, kind
            local ok = spawn and spawn(now) == true or false
            if not ok then                              -- (no round: what it took for one given back)
                p.liveRun, p.liveKind = nil, nil
                bgmBack(p, "its round didn't start")
                hudBack(p, "its round didn't start")
                dropTargets(p)
            end
            return ok
        end
        local over, abort = e.over, e.abort
        e.over = function(now, s)
            p.liveRun, p.liveKind = nil, nil
            local r = { n = 0 }
            if levelGoing and levelGoing() then            -- (touch nothing: only abort, told why)
                if abort then abort("the level is going") end
            else
                r = table.pack(over and over(now, s))
            end
            local n = dropTargets(p)
            if n > 0 then plog(p, n .. " targets left at its round's end: taken off, unpaid, Survival's again") end
            bgmBack(p, "its round is over")
            hudBack(p, "its round is over")
            return table.unpack(r, 1, r.n)
        end
        return e
    end

    -- A plugin round whose run ended under it (the level left; a new run, a restart after every player is down: the
    -- RUN OVER screen itself leaves the run in place, its round still ticking as Survival's own do): Survival
    -- doesn't finish a special then (its own specials check `S.D ~= D` themselves, sv_escort_li.lua), so the API
    -- does it for plugins: the kind's abort(why) (or over(now, nil) without one) and its targets off the watch, unpaid.
    -- (also, with no round of its own: Survival's music and HUD given back at its run's end; the plane marks are a
    -- run's: dropped with it)
    -- (the level's teardown for certain: Survival's hard sign, another level loading (sv_core.lua levelGoing's
    -- LEAVE.hard). Its soft sign, the unit spawner unanswered a second, can let go again: no one-way step is taken for
    -- it. A Survival without LEAVE: every sign)
    function levelHard()
        if not (levelGoing and levelGoing()) then return false end
        return type(LEAVE) ~= "table" or LEAVE.hard == true
    end
    PLUGINS.levelHard = levelHard
    local marksRun = nil
    function runCheck(now)
        local goingNow = levelHard()
        local going = (levelGoing and levelGoing()) or PLUGINS.goneMissed == true   -- (what it's told: touch nothing)
        if D ~= marksRun then                                 -- (a run's marks and targets: dropped with it)
            if marksRun ~= nil then dropAllTargets("its run ended") end
            PLUGINS.marks, marksRun = {}, D
        end
        for _, p in ipairs(PLUGINS.loaded) do
            if p.liveRun ~= nil and (D ~= p.liveRun or goingNow) then
                local why = going and "the level is going" or (D == nil and "the run is over" or "a new run")
                local k = p.liveKind
                p.liveRun, p.liveKind = nil, nil
                dropTargets(p)
                plog(p, "its round's run ended (" .. why .. "): round taken off")
                bgmBack(p, "its run ended")
                hudBack(p, "its run ended")
                local def = k and p.defs and p.defs[k]          -- (the kind whose round was on, only)
                if def and type(def.abort) == "function" then guard(p, "abort", def.abort)(why)
                elseif def and type(def.over) == "function" and not going then guard(p, "over", def.over)(now, nil) end
            end
            if p.seenRun ~= nil and D ~= p.seenRun then        -- (a run of its ended, its round or not)
                bgmBack(p, "its run ended")
                hudBack(p, "its run ended")
                PLUGINS.unpinAll(p, "the run ended")
            end
            p.seenRun = D
        end
    end

    SVP = {}
    SVP.version = API.major
    SVP.api = { major = API.major, minor = API.minor }

    -- a raw copy of an add-on's table (next: no __pairs / __index of its runs), one level
    local function rawCopy(t)
        local c, k, v = {}, next(t)
        while k ~= nil do c[k] = v; k, v = next(t, k) end
        return c
    end
    -- def.cfg as the API keeps it (CFG.specials[kind], which Survival's own code walks: COOP.cfgDiff for LB.edited and
    -- the co-op settings): plain data only, copied raw: numbers, strings, booleans, and flat lists of them. Anything
    -- else is left out, said once
    local function plainValue(v) local tv = type(v); return tv == "number" or tv == "string" or tv == "boolean" end
    local function plainCfg(p, kind, cfg)
        local c, out = {}, {}
        if type(cfg) ~= "table" then return c end
        for k, v in pairs(rawCopy(cfg)) do
            if type(k) ~= "string" then out[#out + 1] = str(k)
            elseif plainValue(v) then c[k] = v
            elseif type(v) == "table" then
                local l, n, ok = {}, rawlen(v), true
                for i = 1, n do local x = rawget(v, i); if plainValue(x) then l[i] = x else ok = false end end
                local cnt = 0
                for _ in pairs(rawCopy(v)) do cnt = cnt + 1 end
                if ok and cnt == n then c[k] = l else out[#out + 1] = k end
            else out[#out + 1] = k end
        end
        if #out > 0 then
            table.sort(out)
            plog(p, "kind " .. kind .. ": def.cfg." .. table.concat(out, ", def.cfg.")
                .. " left out (settings are numbers, strings, booleans and flat lists of them)")
        end
        return c
    end

    -- "M.m" (or a number) -> major, minor (whole numbers, 6 digits at most each); nil when it isn't a version
    local function parseVer(v)
        if type(v) ~= "string" and type(v) ~= "number" then return nil end
        local maj, min = tostring(v):match("^%s*(%d+)%.?(%d*)%s*$")
        if not maj or #maj > 6 or #min > 6 then return nil end
        return math.tointeger(tonumber(maj)), math.tointeger(tonumber(min) or 0)
    end
    -- whether this API serves an add-on that needs `need`: its own major, a minor up to this one (a minor only adds).
    -- An add-on declares it: none is refused (2.0 is the first API that shipped)
    local function serves(need)
        if need == nil then return false, "it declares no def.api (def.api = \"2.0\": the API it's written for)" end
        local maj, min = parseVer(need)
        if not maj then return false, "its def.api \"" .. str(need) .. "\" isn't a version (\"2.0\")" end
        if maj == API.major and min <= API.minor then return true end
        return false, string.format("it needs add-on API %d.%d; this Survival has %d.%d", maj, min, API.major, API.minor)
    end

    -- the player's own rotation (survival.ini's `rotation` line, not the shipped one): read once, before any add-on
    -- joins it (PLUGINS.load), so a second add-on doesn't take the first one's addition for the player's own
    local ownRotation = nil
    function playerRotation()
        if ownRotation == nil then
            local rot = CFG.specials.rotation
            local shipped = CFG_DEFAULTS and CFG_DEFAULTS.specials and CFG_DEFAULTS.specials.rotation
            ownRotation = (shipped ~= nil and not sameList(rot, shipped)) == true
        end
        return ownRotation
    end
    PLUGINS.playerRotation = playerRotation

    function SVP.register(kind, def)
        local p = PLUGINS.current
        if not p then return false, "register only while an add-on loads" end
        if type(kind) ~= "string" or not kind:match("^[%a][%w_]*$") or #kind > NAME_MAX then
            return false, "a kind is a name of letters, digits and _, 15 at most"
        end
        if SPC.kinds[kind] then return false, "kind " .. kind .. " is taken" end
        -- (a kind's settings are CFG.specials[kind]: a name Survival's own specials settings use would overwrite them)
        if CFG.specials[kind] ~= nil or (CFG_DEFAULTS and CFG_DEFAULTS.specials and CFG_DEFAULTS.specials[kind] ~= nil) then
            local why = "kind " .. kind .. " is the name of one of Survival's specials settings"
            plog(p, "not registered: " .. why)
            return false, why
        end
        -- (def and def.kind read once each, raw: no __index of the add-on's runs, and no field is read twice, so what's
        -- checked is what's kept. Fields given through a metatable aren't read: said)
        if type(def) ~= "table" then return false, "def.kind with a spawn function needed" end
        local viaMeta = getmetatable(def) ~= nil
        def = rawCopy(def)
        if type(def.kind) ~= "table" then return false, "def.kind with a spawn function needed" end
        viaMeta = viaMeta or getmetatable(def.kind) ~= nil
        local kd = rawCopy(def.kind)                   -- (what's kept of def.kind: a raw copy, no metamethod of the add-on's)
        if type(kd.spawn) ~= "function" then return false, "def.kind with a spawn function needed" end
        if viaMeta then plog(p, "kind " .. kind .. ": def or def.kind has a metatable: only their own fields are read") end
        if type(def.name) == "string" and def.name ~= "" then p.name = def.name:sub(1, 40) end
        local okV, whyV = serves(def.api)
        if not okV then p.refused = whyV; plog(p, "not loaded: " .. whyV); return false, whyV end
        p.natives = p.natives or { prefixes = {} }
        local req = type(def.requires) == "table" and def.requires or {}
        for i = 1, math.min(rawlen(req), 64) do        -- (raw: no __index / __len of the add-on's)
            local fn = rawget(req, i)
            if type(fn) == "string" then p.natives[fn] = true end   -- (named: its environment reads it)
            if type(_G[fn]) ~= "function" then
                local why = "it requires " .. str(fn) .. ", which this game doesn't have"
                p.refused = why; plog(p, "not loaded: " .. why); return false, why
            end
        end
        if def.check ~= nil and type(def.check) ~= "function" then return false, "def.check must be a function" end
        local unused = {}
        local bad = badKind(kd, unused)
        if bad then plog(p, "kind " .. kind .. " not registered: " .. bad); return false, bad end
        if #unused > 0 then
            table.sort(unused)
            plog(p, "kind " .. kind .. ": " .. table.concat(unused, ", ") .. " left out (not a field Survival uses)")
        end
        p.ver, p.coop, p.api = str(def.ver or "?"):sub(1, 20), false, str(def.api)
        local c = plainCfg(p, kind, def.cfg)
        if c.enabled == nil then c.enabled = true end
        local n = iniOver(kind, c)
        local own = playerRotation()
        CFG.specials[kind] = c
        SPC.kinds[kind] = kindEntry(p, kd, def.check, kind)
        PLUGINS.kinds[kind] = p
        p.defs = p.defs or {}
        p.defs[kind] = kd                             -- (abort / over for a round whose run ended: runCheck)
        p.kinds[#p.kinds + 1] = kind
        -- the rotation: the add-on's kind joins it unless the player wrote a rotation of their own (survival.ini's
        -- `rotation` line), which is theirs to change: the kind's name in it brings the kind, leaving it out keeps it away
        local rot = CFG.specials.rotation
        if def.rotation == true and type(rot) == "table" and not inList(rot, kind) and not own then
            rot[#rot + 1] = kind
            p.addedRot = p.addedRot or {}
            p.addedRot[kind] = true                    -- (taken out again if the add-on fails its load: loadFailed)
        end
        plog(p, string.format("kind %s registered (%d settings from survival.ini; %s)", kind, n,
            inList(rot, kind) and "in the rotation" or "not in the rotation"))
        return true
    end
end  -- (sv_plugins.lua's do block goes on in sv_plugins_api.lua)
