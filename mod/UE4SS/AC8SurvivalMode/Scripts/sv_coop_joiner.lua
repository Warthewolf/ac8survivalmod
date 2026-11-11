-- sv_coop_joiner.lua: Survival COOP, a joiner's side: the host's flights here, copied, bound to their streams and kept
-- up. Piece 2 of 5 of sv_coop.lua (sv_coop.lua, sv_coop_joiner.lua, sv_coop_planes.lua, sv_coop_sync.lua,
-- sv_coop_migration.lua), split by tools/lua_split_part.py and run by main.lua right after the piece before it: a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local.
do  -- (sv_coop.lua's do block, continued: this piece's own helpers stay local to it)
local M = COOP.M                                   -- (sv_coop.lua's M, handed on)
local PEND_MAX = 512                                 -- (units whose binds wait for their spawn here: pendKeep)
M.BINDS_MAX = 4096                                   -- (one unit's binds: a unit's own objects are tens; this bounds a flood only)
-- whether table t has `cap` entries or more (counted: a flood's tables bounded without a count to keep in step)
function M.mapFull(t, cap)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1; if n >= cap then return true end end
    return false
end
local crumb = crumb or function() end  -- (as in sv_coop.lua)

---------------------------------------------------------------------------------------------------- joiner
local function hostPuppet()
    local P = M.peers[0]
    return P and P.obj and valid(P.obj) and P.obj or nil
end

-- (with the host's plane as the cause when it's an AI stand-in; with none when it's their real plane, role 2, whose damage
-- the game refuses: from COOP2MP T3 no copy here could be finished, so the host's kills stayed up here, flying on by
-- their own AI, and their flights never spawned again ("its last flight is still up"): the co-op run of 2026-10-30,
-- "people are attacking ghosts", the same copy "taken down" every 5 s. Checked after: still up, GameplayStatics'
-- ApplyDamage)
-- torn: a copy this game takes down itself (the host's run started over, a stray, its flight's last copies before a
-- new spawn), not the host's kill: its address kept TORN_S so the plane watch pays nothing for it (COOP.tornDown). The
-- co-op run of 2026-10-31: three joiners' teardowns (the host's answer to their own "jn") paid 5-14 kills "by you"
-- each, 750-2,230 zollars, in the seconds after.
local TORN_S = 30
-- (0.73.77, plan A1) A copy's floor: it waits at 1 HP for the host's kill ("dn"). The MinHealth field is written (every
-- hit is clamped at it: KILLS_HEALTH_DEATH.md 2), as the revive floor and the real planes do; SetMinHealth keeps whole
-- points only, so 0.73.76's SetMinHealth(0.1) set 0 and a joiner's copies had no floor at all. The logs of 2026-11-02:
-- dukka's and mobi118's copies went down to the ships' copies there up to 700 s before the host's kill (60 and 116
-- flights), the host's "hp" then wrote health back onto the wrecks (invisible enemies with target boxes), and their
-- flights' next spawns were refused. FLOOR_IN: the floor as HealthInternal (health x 10).
FLOOR_IN = 10
HP_HOLD_S = 1.5                                       -- ((0.73.79) the "hp" handler's hold after a hit is sent)
local function floorOn(o)
    local hp = FLOOR_IN / 10
    local ok = pcall(function() o.MinHealth = hp end)
    if not ok then ok = pcall(function() o:SetMinHealth(hp) end) end
    if not M.floorSaid then                              -- (once a level: what the field reads back)
        M.floorSaid = true
        local okR, v = pcall(function() return o.MinHealth end)
        log(string.format("coop: copies held at %.1f HP until the host's kill (%s; MinHealth reads back %s)", hp,
            ok and "the field written" or "NOT written", okR and tostring(v) or "nothing"))
    end
    return ok
end
-- (0.73.77, plan A6) copy c's wait at the floor is over (the host's kill, or its health from the host): the minute's
-- longest kept for the sync report
function floorDone(c)
    if not (c and c.floorAt) then return end
    local w = os.clock() - c.floorAt
    c.floorAt = nil
    if w > (M.cnt.floorMax or 0) then M.cnt.floorMax = w end
end
-- force (0.73.73): an invincible copy too (a taxiing ally, the shuttle, the pad's guns and dummies): the host's is gone or
-- spawning afresh. Without it the testers' joiners couldn't finish them ("a copy here couldn't be finished (health 9300
-- after)"), they stayed up unbound, flying their own AI ("VOID WATCHER became a space shuttle", MOONCHILD "submersible"),
-- and the host's next spawn of the unit was refused.
-- by ((0.73.80, the 31-round test's finding coop6): your plane, when the host's "dn" names this game's player): the kill
-- with your plane as its cause, so the game shows it as yours (its DESTROYED, not only the hit markers: the floor clips
-- every lethal hit of yours here, and the kill came with the host's plane or none as its cause). Refused with it: none.
-- What it answers: "yours", "yours refused" (then none), "host" (the host's AI stand-in), "none"; nil for a copy gone.
-- The pay is untouched: a joiner pays the player the host named (KILL.by, M.killerOf), never the game's cause.
local function killCopy(id, o, torn, force, by)
    if type(SV_CoopBind) == "function" and type(id) == "number" and id > 0 then SV_CoopBind(id, 0) end
    local a = live(o)
    if not a then return end
    M.downAt[a] = os.clock()                             -- (0.73.73: strayTick leaves it alone)
    if torn then
        M.torn = M.torn or {}; M.torn[a] = os.clock()
        M.tornLast = os.clock()                          -- (the pay audit, sv_audit.lua: COOP.tornRecently)
        M.cnt.torn = M.cnt.torn + 1
    end
    crumb(string.format("copy %s taken down (id %s%s%s)", nameOf(o), tostring(id), torn and ", torn: not a kill" or "",
        force and ", forced" or ""))
    if force then
        pcall(function() o:SetIsInvincible(false) end)
        pcall(function() o.bIsInvincible = false end)
    end
    pcall(function() o.MinHealth = 0.0 end)              -- ((0.73.77) the floor off first: floorOn wrote the field)
    pcall(function() o:SetMinHealth(0.0) end)
    local h = health(o) or 0
    local P0 = M.peers[0]
    local causer, how = nil, "none"
    if by ~= nil and valid(by) then causer, how = by, "yours"
    else
        causer = not (P0 and P0.real) and hostPuppet() or nil
        if causer then how = "host" end
    end
    local ok = pcall(function() o:ModifyHealth(-(h / 10 + 100), causer, true) end)
    if not ok then pcall(function() o.HealthInternal = 0 end) end
    if (health(o) or 0) > 0 and causer then                  -- (refused with the host's plane named: with none)
        pcall(function() o:ModifyHealth(-(h / 10 + 100), nil, true) end)
        how = how .. " refused"
    end
    if (health(o) or 0) > 0 then
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if valid(gs) then pcall(function() gs:ApplyDamage(o, 100000000.0, nil, nil, nil) end) end
        if (health(o) or 0) > 0 then
            once("killfail", "coop: a copy here couldn't be finished (health " .. tostring(health(o)) .. " after)")
        end
    end
    return how
end
-- (0.73.80, finding coop6) The host's "dn" for copy c (id): taken down here, with your plane as its cause when field 4
-- names this game's player (its slot), else as before (the host's AI stand-in, or none). The 31-round test's joiners saw
-- only hit markers, never the game's DESTROYED: their lethal hits stop at the floor (floorOn) and the kill came from here
-- with the host's plane or none as its cause. Each way it went logged once; [coop] kill_callout (off by default: whether
-- the game's own DESTROYED shows this way isn't known yet) adds Survival's own callout for each kill of yours.
do
local KILL_HOW = { yours = "your plane as its cause (the game's DESTROYED should show)",
                   ["yours refused"] = "your plane as its cause REFUSED by the game: with none",
                   host = "the host's plane (an AI stand-in here) as its cause", ["host refused"] = "the host's stand-in refused: with none",
                   none = "no cause (the host flies a real plane here)" }
-- ((code review of 2026-11-07, finding 13) an allied copy the host took off without a kill ("dn|<id>|r": THE ESCORT's
-- aircraft parked at a won round's end, a carrier leaving, its flight, VOID WATCHER 1 home): switched off here as the
-- host switches its own off (no box or lock-on, invincible, inactive, hidden, no collision, no tick), not finished off
-- (killCopy exploded the parked allies on every joiner); its unit off this game's spawner list 2 s on once no copy of it
-- is left here (the host recycles its own then). "off"
local function offCopy(id, c)
    if type(SV_CoopBind) == "function" and type(id) == "number" and id > 0 then SV_CoopBind(id, 0) end
    local o = c.obj
    local a = live(o)
    if not a then return nil end
    M.downAt[a] = os.clock()
    crumb(string.format("copy %s switched off (id %s: an ally the host took off)", nameOf(o), tostring(id)))
    for fld, v in pairs({ bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }) do
        pcall(function() o[fld] = v end)
    end
    pcall(function() o:SetActive(false, false, false) end)
    pcall(function() o:SetActorHiddenInGame(true) end)
    pcall(function() o:SetActorEnableCollision(false) end)
    pcall(function() o:SetActorTickEnabled(false) end)
    M.cnt.allyOff = (M.cnt.allyOff or 0) + 1
    if c.unit then
        local left = false
        for oid, o2 in pairs(M.copies) do if oid ~= id and o2.unit == c.unit then left = true end end
        if not left then
            M.recycleDue = M.recycleDue or {}
            local dup = false
            for _, e in ipairs(M.recycleDue) do if e.unit == c.unit then dup = true end end
            if not dup and #M.recycleDue < 64 then
                M.recycleDue[#M.recycleDue + 1] = { unit = c.unit, at = os.clock() + 2, why = "ally taken off" }
            end
        end
    end
    once("allyoff", string.format("coop: the host took an ally off (copy %d, %s): switched off here, not finished off", id, tostring(c.unit)))
    return "off"
end
function M.dnKill(id, c, f)
    local torn = f[3] == "r"
    if torn and c.ally then return offCopy(id, c) end
    local mine = not torn and COOP.slot ~= nil and f[4] ~= nil and f[4] ~= "" and tonumber(f[4]) == COOP.slot
    local by = nil
    if mine then
        local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
        if valid(pawn) then by = pawn end
    end
    local how = killCopy(id, c.obj, torn, true, by)
    if how and not torn then
        once("dnhow" .. how .. (mine and "m" or ""), string.format("coop: the host's kill of copy %d (%s): taken down here with %s",
            id, mine and "yours" or (f[4] and f[4] ~= "" and ("named " .. short(f[4], 2)) or "no player named"),
            (mine and not by) and "no plane of yours here: " .. (KILL_HOW[how] or how) or (KILL_HOW[how] or how)))
    end
    if mine and how and cfg().kill_callout == true and type(hudCallout) == "function" then
        M.noMirror = true; pcall(hudCallout, "DESTROYED", nil); M.noMirror = false   -- (whatever [coop] callouts says)
    end
    return how
end
end

-- (0.73.73) a copy whose host id is already down: taken down as not a kill (torn) and off its flight's planes here. The
-- testers' logs of 0.73.70: each resync spawned the host's flights again here, and the copies of planes the host had
-- shot down long before went down on arrival "by you": 109 kills, ~13,470 zollars (A04 13:39:40, "up 1 s ...; by you")
local function deadOnArrival(id, o, unit, ord, key)
    killCopy(id, o, true, true)
    M.copies[id] = nil
    local cu, a = M.cunits[unit], addrOf(o)
    if cu and ord and cu.planes[ord] and addrOf(cu.planes[ord]) == a then cu.planes[ord] = nil end
    if cu and key and cu.gobjs and cu.gobjs[key] and addrOf(cu.gobjs[key]) == a then cu.gobjs[key] = nil end
end
function bindCopy(id, o, unit, ord)
    if M.dead[id] then deadOnArrival(id, o, unit, ord, nil); return end
    local a = addrOf(o)
    local r = (type(SV_CoopBind) == "function" and a) and SV_CoopBind(id, a) or -9
    if r ~= 1 then once("bind" .. tostring(r), "coop: a copy couldn't be bound (" .. tostring(r) .. "): it flies on its own") end
    floorOn(o)                                              -- (it goes down when the host's does: (0.73.77) at 1 HP)
    local was = M.copies[id]                                -- ((0.73.77) bound again: your damage so far, clientTick)
    local mine = was and was.addr == a and was.mine or nil
    local h = health(o) or 0
    M.copies[id] = { obj = o, exp = h, addr = a, ally = allyUnit(unit),   -- (ally: the host's allies' copy)
                     unit = unit, ord = ord, mine = mine, hp = h }  -- (0.73.73: its place in its flight here, "dn")
end

-- (0.73.73) every object of each of the host's units spawned here, by address (its name too: an address freed and used
-- again is another object), kept past a teardown until it's down or gone: a refused spawn of the host's takes down
-- whatever of that unit is still up here, whatever its kind (doSpawn). 0.73.70's take-down walked the enemy planes only,
-- and found none in 187 of 187 tries: the shuttle's pad (PadDummies, AA_Unit_01_Ground0), the defences, the allies'
-- flights and the shuttle were never in it.
local function noteObj(unit, o)
    local a = type(unit) == "string" and addrOf(o)
    if not a then return end
    local reg = M.objsOf[unit]
    if not reg then reg = {}; M.objsOf[unit] = reg end
    reg[a] = { obj = o, name = nameOf(o) }
end
-- ((0.73.77, plan A3) a wreck, at 0 health and still in the world, is kept 120 s: the game may still count it in its
-- unit (AliveChildAIGameObjects), which refuses the unit's next spawn, and doSpawn's take-down finds it here)
local function pruneObjs()                               -- (strayTick, every 5 s: what's down or gone dropped)
    local now = os.clock()
    for unit, reg in pairs(M.objsOf) do
        for a, e in pairs(reg) do
            -- (0.73.73 review) unreadable health counts as up, as takeUnitDown has it: dropping such an object here hid
            -- it from a later refused spawn's take-down, the ghost this registry is for
            if not live(e.obj) then reg[a] = nil
            elseif (health(e.obj) or 1) <= 0 then
                e.zeroAt = e.zeroAt or now
                if now - e.zeroAt >= 120 then reg[a] = nil end
            end
        end
        if next(reg) == nil then M.objsOf[unit] = nil end
    end
end
-- whatever of `unit` is still up here (its flight here `cu`, if any, and every object of it spawned here), taken down:
-- torn (not a kill), forced (invincible too). How many. wrecks ((0.73.77, plan A3), a spawn the game refused): its
-- objects at 0 health still in the world too, and its planes the plane watch saw go down (sv_core's `planes`) that are
-- still there, taken down again (ModifyHealth runs the game's own death check on them); how many of those, second.
local function takeUnitDown(unit, cu, wrecks)
    local n, w, seen, idOf = 0, 0, {}, {}
    for id, c in pairs(M.copies) do if c.addr then idOf[c.addr] = id end end
    local function one(o, name)
        local a = live(o)
        if not a or seen[a] or (name and nameOf(o) ~= name) then return end
        seen[a] = true
        local id = idOf[a]
        if (health(o) or 1) > 0 then killCopy(id or 0, o, true, true); n = n + 1
        elseif wrecks then killCopy(id or 0, o, true, true); w = w + 1 end
        if id then M.copies[id] = nil end
    end
    if cu then
        for _, o in pairs(cu.planes or {}) do one(o) end
        for _, o in pairs(cu.gobjs or {}) do one(o) end
    end
    local reg = M.objsOf[unit]
    for a, e in pairs(reg or {}) do
        one(e.obj, e.name)                               -- (still up after it: kept, for the next try)
        if not live(e.obj) or nameOf(e.obj) ~= e.name or (not wrecks and (health(e.obj) or 0) <= 0) then reg[a] = nil end
    end
    if wrecks then
        for _, p in ipairs(planes or {}) do if p.unit == unit and p.obj then one(p.obj) end end
    end
    if ALLY and ALLY.forgetActors then pcall(ALLY.forgetActors) end
    return n, w
end

-- (a joiner) copy o's health scaled here (sv_ai.lua enemyLate: CFG.late, a Skirmisher's x0.75, as the host scales its
-- own): what it's expected to have moves with it, so clientTick sends the host only the hits since (code review of
-- 2026-10-29: a joiner's x0.75 went to the host as that player's hit, x0.5 there). Whether o is a bound copy.
function COOP.copyScaled(o, h0, h1)
    if not (COOP.client() and type(h0) == "number" and type(h1) == "number") then return false end
    local a = addrOf(o)
    if not a then return false end
    for _, c in pairs(M.copies) do
        if c.addr == a then c.exp = c.exp + (h1 - h0); return true end
    end
    return false
end

function clientPlane(o, unit)
    -- (the Alicorn's 131 parked pools: the host gives them no ids, hostPlane, so neither does this game's count. Counted
    -- here, they were "strays" 15 s on, their copies couldn't be taken down (put away invincible), the "jn" resync took
    -- the Alicorn's tanks and core down here and its fresh copy was refused, "its last flight is still up": the co-op
    -- run of 2026-10-31, two joiners couldn't target the Alicorn at all)
    local a = addrOf(o)
    if SPC and unit == SPC.alicornUnit and SPC.alcnPool and a and SPC.alcnPool.set[a] then return end   -- ((0.73.83) its own planes only: hostPlane)
    noteObj(unit, o)                                     -- (0.73.73: tracked here or not)
    local cu = M.cunits[unit]
    if not cu then return end
    cu.n = cu.n + 1
    cu.planes[cu.n] = o
    local id = cu.binds[cu.n]
    if id then bindCopy(id, o, unit, cu.n) end
end

-- a ship's, vehicle's or part's copy (groundTick): not moved, held up until the host's goes down, its hits sent
function bindGround(id, o, unit, key)
    local cu = M.cunits[unit]                                -- ((0.73.80) for strayTick's "N of M bound" line: linked to
    if cu and key then cu.gb = cu.gb or {}; cu.gb[key] = true end   -- the host's id, down on arrival or not)
    if M.dead[id] then deadOnArrival(id, o, unit, nil, key); return end
    floorOn(o)                                              -- ((0.73.77) at 1 HP: the field, not SetMinHealth(0.1) = 0)
    local a, h = addrOf(o), health(o) or 0
    local was = M.copies[id]
    M.copies[id] = { obj = o, exp = h, addr = a, ally = allyUnit(unit),  -- (addr: a shot's target, "fx")
                     unit = unit, key = key, mine = was and was.addr == a and was.mine or nil, hp = h }
end
clientGround = function(o, unit)
    noteObj(unit, o)                                     -- (0.73.73: tracked here or not)
    local cu = M.cunits[unit]
    if not cu then return end
    cu.gcount, cu.gobjs = cu.gcount or {}, cu.gobjs or {}
    local key = groundKey(o, cu.gcount)
    cu.gobjs[key] = o
    local id = cu.gbinds and cu.gbinds[key]
    if id then bindGround(id, o, unit, key) end
end

-- (sv_main.lua planeSweep) plane p, just down here, is a copy this game took down itself (killCopy's torn): not a kill
function COOP.tornDown(p)
    local a = p and (p.addr or (valid(p.obj) and addrOf(p.obj)))
    local t = a and M.torn and M.torn[a] or nil   -- (0.73.73: a plane with no address gave false, and os.clock() - false errored)
    if M.torn and os.clock() >= (M.tornPruneAt or 0) then
        M.tornPruneAt = os.clock() + TORN_S
        for k, at in pairs(M.torn) do if os.clock() - at > TORN_S then M.torn[k] = nil end end
    end
    return t ~= nil and os.clock() - t <= TORN_S
end

-- (the planes forced, invincible or not, 0.73.73: one left up flies on unbound by its own AI, "VOID WATCHER became a
-- space shuttle"; ships, vehicles and parts as before: the stream never moves them anyway)
function killAllCopies(why)
    local n, loose, seen = 0, 0, {}
    crumb("copies: all taken down (" .. tostring(why) .. ")")
    M.tornWhy = tostring(why)
    M.cnt.teardowns = M.cnt.teardowns + 1
    if ALLY and ALLY.forgetActors then pcall(ALLY.forgetActors) end   -- (the defences' cached actors: freed soon)
    for id, c in pairs(M.copies) do
        killCopy(id, c.obj, true, c.key == nil); n = n + 1
        local a = c.addr or live(c.obj)
        if a then seen[a] = true end
    end
    -- (and every copy spawned here that never got its id from the host: the user's co-op run of 2026-10-30, both links
    -- lost seconds after the round's flights were sent; their binds never came, the link-back resync took down the bound
    -- copies only and forgot the rest, which flew on by their own AI into the next rounds: "friends are reporting enemies
    -- even though i'm into the next round")
    for _, cu in pairs(M.cunits or {}) do
        for _, o in pairs(cu.planes or {}) do
            local a = live(o)
            if a and not seen[a] then seen[a] = true; killCopy(0, o, true, true); loose = loose + 1 end
        end
        for _, o in pairs(cu.gobjs or {}) do
            local a = live(o)
            if a and not seen[a] then seen[a] = true; killCopy(0, o, true); loose = loose + 1 end
        end
    end
    M.copies, M.cunits, M.spawnQ, M.dead, M.holdQ, M.rep = {}, {}, {}, {}, nil, nil
    if n + loose > 0 then
        log(string.format("coop: %d copies taken down (%s)%s", n + loose, why,
            loose > 0 and string.format(", %d of them never bound to the host's", loose) or ""))
    end
end

-- ((0.73.77) plan F1b) The level is being torn down (sv_core.lua levelGate: the runtime's teardown gate, SV_LevelGone): every
-- game object co-op keeps is forgotten, none of them touched (no killCopy, no hide, no health: they go with the level, and a
-- Lua read of a freed one is the quit crash, UE4SS's property lookup). The next level's start (D ~= M.lastD in COOP.tick)
-- builds the lists again; a player's real plane is spawned again there, as after any level.
function COOP.levelDrop(why)
    local n = 0
    for _ in pairs(M.copies or {}) do n = n + 1 end
    M.copies, M.cunits, M.spawnQ, M.holdQ, M.rep, M.pendBind = {}, {}, {}, nil, nil, nil
    M.objsOf = {}
    M.mslAt, M.mslEnd, M.gunAtT, M.shotTgt = {}, {}, {}, {}   -- ((0.73.79) your shots by the copy they went for)
    local p = 0
    for _, P in pairs(M.peers or {}) do
        if type(P) == "table" and P.obj ~= nil then P.obj, P.addr = nil, nil; p = p + 1 end
    end
    -- ((0.73.83, its review) the set-aside planes and the radar's records go with their level: kept, a freed plane's
    -- address taken by a new object would have asideTick deactivate and move that one. A restart in the same level never
    -- closes the gate, so those planes stay kept then)
    local a = #(M.aside or {})
    for _, e in ipairs(M.aside or {}) do if e.unit and M.asideUnit then M.asideUnit[e.unit] = nil end end
    M.aside, M.parkAt, M.radarSt, M.asideAt = {}, {}, {}, nil
    log(string.format("coop: the level is going (%s): %d copies, %d players' planes and %d set aside forgotten here, none touched",
        tostring(why), n, p, a))
end

-- (0.73.73) The host's answer to this game's own "jn" ("rs|j" ... "rz", hostSync) is a repair, not a teardown. What's here
-- is kept and checked against the host's picture: a flight up here of the host's generation stays as it is (the
-- picture's ids bind its copies again); one of an older generation is taken down for the host's fresh spawn (doSpawn);
-- one the host no longer has at all is taken down at the picture's end; one missing a plane the host still has up is
-- spawned again (its planes are moved by the stream; a ship or part missing alone isn't: a fresh one would start its
-- path over). Nothing is paid for, nobody DOWN comes back, the round's records go on. The testers' logs of 0.73.70: every
-- answer tore all of a joiner's copies down (2,689 copies, 115 times), "all explode and none come back" for 7 minutes
-- (A04 13:15:57), a Ladon gone here while the host's flew on (A02 11:13:58), the round cut short 58 times.
local REP_WAIT_S, JUDGE_AFTER_S = 10, 3
function onResync()
    M.rep = { at = os.clock(), units = {}, ids = {}, rebound = 0 }
    M.spawnQ, M.pendBind = {}, nil                       -- (the picture sends every flight the host has up again)
    M.cnt.repairs = M.cnt.repairs + 1
    crumb("coop: the host's whole picture is coming (rs|j): the copies here kept")
    log("coop: the host's whole picture is coming (rs|j, its answer to this game's jn): the copies here are kept and checked against it")
end
-- (while the picture comes) the host's id `id` for plane `ord` (or part `key`) of its flight `unit`, generation gen
function repNote(unit, gen, id, ord, key)
    local rp = M.rep
    local pu = rp and not rp.done and rp.units[unit]
    if not (pu and pu.gen == gen) then return end
    if ord then pu.alive[ord] = id else pu.galive[key] = id end
    rp.ids[id] = { unit = unit, ord = ord, key = key }
end
-- the host's id for a plane (field "binds", by its order) or part ("gbinds", by its key) of its flight `unit`, generation
-- gen, whose spawn here is still to come: kept until doSpawn spawns that generation (one generation a unit)
function pendKeep(unit, gen, field, k, id)
    M.pendBind = M.pendBind or {}
    local pb = M.pendBind[unit]
    if not pb then
        -- ((2026-11-11) coop_guard_test: keyed by any unit name in "bd" / "gd", 1,800 in a flood) a plain unit name, and at
        -- most PEND_MAX units waiting for their spawn (counted, not kept count of: nothing to drift); past it the rest are
        -- dropped, logged once
        if not tostring(unit or ""):match("^[%w_]+$") then return end
        if M.mapFull(M.pendBind, PEND_MAX) then
            once("pendfull", string.format("coop: binds for %d of the host's units already wait here: %s's dropped", PEND_MAX, tostring(unit)))
            return
        end
    end
    if not pb or pb.gen ~= gen then pb = { gen = gen, binds = {}, gbinds = {} }; M.pendBind[unit] = pb end
    if pb[field][k] == nil and M.mapFull(pb[field], M.BINDS_MAX) then return end   -- ((2026-11-11) review: any key, no bound)
    pb[field][k] = id
end
local function upHere(o) return o ~= nil and live(o) ~= nil and (health(o) or 1) > 0 end
function repairDone(why)
    local rp = M.rep
    if not rp or rp.done then return end
    rp.done = os.clock()
    local whole = why == "rz"
    local kept, fresh, redo, gone, gaps, nPic = 0, 0, {}, {}, {}, 0
    for unit, pu in pairs(rp.units) do
        nPic = nPic + 1
        local cu = M.cunits[unit]
        if not (cu and cu.gen == pu.gen and cu.upAt) then fresh = fresh + 1 end
    end
    for unit, cu in pairs(M.cunits) do
        local pu = rp.units[unit]
        if not pu then
            if whole then                                -- (the host has none of it up: down here too)
                gone[#gone + 1] = string.format("%s (%d)", unit, takeUnitDown(unit, cu))
                M.cunits[unit] = nil
            end
        elseif pu.gen == cu.gen and cu.upAt then
            local miss, gmiss = 0, 0
            if rp.done - cu.upAt >= JUDGE_AFTER_S then   -- (a flight just up here: its copies may not all be seen yet)
                for ord in pairs(pu.alive) do if not upHere(cu.planes[ord]) then miss = miss + 1 end end
                for key in pairs(pu.galive) do if not upHere(cu.gobjs and cu.gobjs[key]) then gmiss = gmiss + 1 end end
            end
            if miss > 0 then
                cu.respawn = true
                redo[#redo + 1] = string.format("%s (%d of its planes)", unit, miss)
            else
                kept = kept + 1
                if gmiss > 0 then gaps[#gaps + 1] = string.format("%s (%d)", unit, gmiss) end
            end
        end
    end
    local function list(t) return #t > 0 and (": " .. table.concat(t, ", ", 1, math.min(#t, 6)) .. (#t > 6 and ", ..." or "")) or "" end
    log(string.format("coop: the host's picture (%d flights%s): %d kept here as they were (%d copies bound again), %d spawned "
        .. "again (a plane the host has up wasn't here%s), %d new or newer here, %d taken down (the host has none of them up%s)%s",
        nPic, whole and "" or ("; " .. tostring(why) .. ": the flights it didn't name kept"), kept, rp.rebound, #redo, list(redo),
        fresh, #gone, list(gone), #gaps > 0 and string.format("; %d kept missing ships or parts the host has up (not spawned "
        .. "again: they'd start their paths over)%s", #gaps, list(gaps)) or ""))
end
-- the host's replay of `unit`'s state for a fresh copy (hostSync: the Alicorn's open core and dive, "ev|<event>|<unit>"):
-- not fired on a copy here that was kept through the resync, which had it already (its AdvancePhase again would move it
-- on a phase). Whether it's skipped.
function keptThrough(unit, name)
    local cu, rp = unit and M.cunits[unit], M.rep
    if not (cu and rp and cu.at and cu.at < rp.at) then return false end
    log(string.format("coop: the host's %s for %s not fired here: its copy here was kept through the resync (it had it)",
        tostring(name), tostring(unit)))
    return true
end

local function unitUp(cu) return cu ~= nil and ((cu.n or 0) > 0 or next(cu.gobjs or {}) ~= nil) end
local function doSpawn(q)
    local unit = q.unit
    local rp = M.rep
    if q.rep and rp and not rp.done then                 -- (0.73.73) a repair's: once the host's whole picture is in
        if os.clock() - rp.at < REP_WAIT_S then q.at = os.clock() + 0.5; return false end
        repairDone(string.format("no end of the host's picture in %d s", REP_WAIT_S))
    end
    local had = M.cunits[unit]
    if had and had.gen == q.gen and not had.respawn and (unitUp(had) or os.clock() - (had.at or 0) < JUDGE_AFTER_S) then
        return true                                      -- (that flight is up here already)
    end
    -- ((2026-11-11) the session's review) a carrier's hull the host spawns again: never taken off this game's list (the
    -- force recycle below, or the spawn's own) while a ZFA-44 of its launchers is up here, the host's rule since 0.74.48
    -- (Shazzy's STORE-close crash). This game's switched-off ZFA-44s of that ship finished off first (once), then it
    -- waits, 5 s at a time (looked at by ZLAUNCH.holdHull, logged once)
    local hull = ESC and ESC.hullShip and ESC.hullShip(unit)
    if hull and ZLAUNCH and ZLAUNCH.holdHull and ZLAUNCH.holdHull(hull, q, unit, "the host's spawn of it") then
        if not q.offKilled and ZLAUNCH.offKill then q.offKilled = true; pcall(ZLAUNCH.offKill, hull, "the host's " .. unit .. " spawned again") end
        q.at = os.clock() + 5
        return false
    end
    local alive = rawUnitAlive and rawUnitAlive(unit) or 0
    -- ((2026-11-11) coop_guard_test: a unit this game doesn't have went on to SV_SetAircraft / SV_SetLevel / SV_Spawn, each
    -- refusing it) SV_UnitAlive's -2 (no unit of that name) or -4 (not a name): the host's spawn is dropped here
    if alive == -2 or alive == -4 then
        once("spunit" .. tostring(unit), string.format("coop: the host's %s isn't a unit of this game (SV_UnitAlive %d): its spawn dropped", tostring(unit), alive))
        return true
    end
    if type(alive) == "number" and alive > 0 then        -- the copy of its last flight still up: down first
        if not q.downDone then
            -- (0.73.73) whatever of it is up here, whatever its kind, tracked or not (takeUnitDown). 0.73.70's take-down
            -- walked the enemy planes only ("0 of its planes taken down", 187 of 187), and a "bd" / "gd" for the queued
            -- spawn had put an empty flight of the same generation in M.cunits, so neither take-down ran at all: 409
            -- refusals ("its last flight is still up"), the stale copies flying on unbound
            q.downDone = true
            local why = (had and had.respawn and "a plane of it the host has up wasn't here: spawned again")
                or (had and had.gen ~= q.gen and ("its last flight here, gen " .. tostring(had.gen)))
                or (had and "spawned here, nothing of it seen") or "no longer tracked here"
            -- ((0.73.77, plan A3) its wrecks too: one the game still counts in the unit refused its spawns while nothing
            -- of it was tracked here (dukka 22 refusals over 7 flights, mobi118 26, 2026-11-02))
            local n, w = takeUnitDown(unit, had, true)
            q.downN, q.wrecksN = n, w
            log(string.format("coop: %s is up here (%d alive; %s): %d of its objects taken down for the host's (gen %s)%s",
                unit, alive, why, n, tostring(q.gen), w > 0 and string.format(", and %d wrecks of it still in the world", w) or ""))
        end
        -- (the Alicorn's last copy can't be shot down here: its parked pools are invincible, so it's taken off whole,
        -- as the host does when one is left from last time, and the host's fresh one comes in its place)
        if SPC and unit == SPC.alicornUnit and not q.alcnRemoved and rawEvent then
            q.alcnRemoved = true
            local r = rawEvent("RE_SV_AlcnRemove")
            log("coop: the Alicorn's last copy here is still up (" .. tostring(rawUnitAlive(unit)) .. " alive): taken off whole "
                .. "for the host's (RE_SV_AlcnRemove " .. tostring(r) .. ")")
        end
        q.tries = (q.tries or 0) + 1
        if q.tries < 6 then q.at = os.clock() + 1.5; return false end
        -- ((0.73.77, plan A3) the last resort, after 6 tries: the runtime takes the unit off the phase's list whatever it
        -- counts (SV_Recycle(unit, 1): 1 recycled, 0 nothing to do, < 0 an error); [coop] force_recycle = false: off)
        if type(SV_Recycle) == "function" and cfg().force_recycle ~= false then
            crumb(string.format("coop: %s still up here (%d alive) after %d tries: SV_Recycle", unit, alive, q.tries))
            local okR, rr = pcall(SV_Recycle, unit, 1)
            if okR and rr == 1 then M.cnt.recycled = M.cnt.recycled + 1 end
            log(string.format("coop: %s unstuck: still %d alive here after %d tries; its last flight taken off the phase's "
                .. "list anyway (SV_Recycle: %s)", unit, alive, q.tries, not okR and ("error " .. tostring(rr))
                or (rr == 1 and "recycled") or (rr == 0 and "nothing to do") or (SV_ERR[rr] or tostring(rr))))
        else
            log("coop: " .. unit .. "'s last copies are still up; spawning anyway" .. (type(SV_Recycle) ~= "function"
                and " (no SV_Recycle in this runtime)" or " ([coop] force_recycle off)"))
        end
    elseif q.downDone and not q.unstuckSaid and (alive == 0 or alive == -7) then   -- ((0.73.77, plan A3) the take-down
                                                                                     -- let it spawn: 0 up, or off the list)
        q.unstuckSaid = true
        M.cnt.unstuck = M.cnt.unstuck + 1
        log(string.format("coop: %s unstuck after %d tries: its last copies here taken down (%d up, %d wrecks)", unit,
            (q.tries or 0) + 1, q.downN or 0, q.wrecksN or 0))
    end
    for _, op in ipairs(q.ops) do
        if not knownRow(op.row) then
            once("row" .. tostring(op.row), "coop: the host's aircraft " .. short(op.row, 64) .. " isn't in this game's table; not set")
        elseif op.idx >= 0 then rawSetAircraft(unit, op.row, op.idx) else rawSetAircraft(unit, op.row) end
    end
    if SPW and SPW.noteRows then pcall(SPW.noteRows, unit, q.ops) end   -- (its special weapons fired here: sv_spweapons.lua)
    if q.level and q.level >= 0 and rawSetLevel then rawSetLevel(unit, q.level) end
    local old = M.cunits[unit]
    local same = old and old.gen == q.gen
    M.cunits[unit] = { gen = q.gen, n = 0, planes = {}, binds = same and old.binds or {}, gbinds = same and old.gbinds or {},
                       at = os.clock() }
    local pb = M.pendBind and M.pendBind[unit]               -- (binds that came before its spawn was queued)
    if pb and pb.gen == q.gen then
        for ord, id in pairs(pb.binds) do M.cunits[unit].binds[ord] = id end
        for key, id in pairs(pb.gbinds) do M.cunits[unit].gbinds[key] = id end
        M.pendBind[unit] = nil
    end
    spawningUnit, spawningIdx = unit, 0                  -- (each copy's index in its flight, p.k: the host's order too)
    if SPC and unit == SPC.alicornUnit then SPC.alcnPool = nil end   -- ((0.73.83) this copy's pools, not the last one's: as the host's alicornSpawn)
    crumb(string.format("coop: the host's %s spawned here (gen %s)", tostring(unit), tostring(q.gen)))
    local r
    if q.pose then r = rawSpawn(unit, q.pose[1], q.pose[2], q.pose[3], q.pose[4]) else r = rawSpawn(unit) end
    spawningUnit, spawningIdx = nil, nil
    if type(r) == "number" and r > 0 and SPC and SPC.sawSpawn then SPC.sawSpawn(unit) end   -- ((0.73.83) this game's copies' units: SPC.recycleLater's)
    if r == -6 or r == -1 then                           -- (this game's level isn't ready: again in a second)
        q.tries = (q.tries or 0) + 1
        if q.tries < 30 then q.at = os.clock() + 1; M.cunits[unit] = old; return false end
    end
    M.lastSpawnAt = os.clock()
    if type(r) ~= "number" or r <= 0 then
        local left = {}                                  -- ((0.73.73) what of it here couldn't be taken down)
        M.cnt.refused = M.cnt.refused + 1                -- ((0.73.77, plan A6) the sync report's flights refused)
        for _, e in pairs(M.objsOf[unit] or {}) do
            if upHere(e.obj) and nameOf(e.obj) == e.name then left[#left + 1] = tostring(e.name):match("([^%.:]+)$") or "?" end
        end
        log("coop: the host's " .. unit .. " not spawned here (" .. (SV_ERR[r] or tostring(r)) .. ")" .. (#left > 0 and
            string.format("; %d of its objects here still up: %s", #left, table.concat(left, ", ", 1, math.min(#left, 4))) or ""))
    else
        M.cunits[unit].upAt = M.lastSpawnAt                  -- (its appearance orders 2 s on: holdDue)
    end
    return true
end

-- A joiner spawns nothing until its own plane is in Survival's level and a few seconds have passed: the host's
-- spawns came in while two joiners' levels were still loading, and spawning then crashed their games (2026-10-25).
local READY_S = 3
function levelReady()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not (D and valid(pawn)) then M.readyAt = nil; return false end
    M.readyAt = M.readyAt or (os.clock() + READY_S)
    return os.clock() >= M.readyAt
end

-- A forwarded hold (RE_SV_DirHold_NN, the squad director's; RE_SV_WolfHold_<NN><L>, a Wolf trap's) waits here until
-- that flight's copy has had its appearance orders (2 s after it appears; they'd undo an earlier hold, hard rule 26): the
-- host holds its own 3 s after its orders, but a copy spawned late here (doSpawn's retries, a level still loading) got
-- the hold first and lost it (review of unit 6). Its flight's release (RE_SV_DirFree_NN; that plane's RE_SV_WolfFree)
-- drops a hold still waiting; one whose copy isn't up HOLD_MAX_S on is dropped.
local HOLD_AFTER_S, HOLD_MAX_S = 3, 30
local function holdOf(name, kind)                       -- a hold's (or a release's) flight NN and plane letter, or nil
    local nn = name:match("^RE_SV_Dir" .. kind .. "_(%d%d)$")
    if nn then return tonumber(nn), nil end
    local wn, L = name:match("^RE_SV_Wolf" .. kind .. "_(%d%d)(%u)$")
    if wn then return tonumber(wn), L end
    return nil
end
local function holdDue(nn)                              -- when flight NN's copy here can take a hold: nil, at once (none)
    for _, q in ipairs(M.spawnQ) do if poolIndex(q.unit) == nn then return math.huge end end
    for unit, cu in pairs(M.cunits) do
        if poolIndex(unit) == nn then return cu.upAt and cu.upAt + HOLD_AFTER_S or math.huge end
    end
    return nil
end
local function freeWaiting(name)                       -- a release fired here: the holds it ends that still wait
    local fn, fL = holdOf(name, "Free")
    if not (fn and M.holdQ) then return end
    for i = #M.holdQ, 1, -1 do
        local q = M.holdQ[i]
        if q.nn == fn and (fL == nil or q.L == fL) then
            table.remove(M.holdQ, i)
            log("coop: the host's " .. q.name .. " dropped here (" .. name .. " came before it could go)")
        end
    end
end
function hostEvent(name)                          -- (a joiner) one of the host's events, here
    local nn, L = holdOf(name, "Hold")
    local due = nn and holdDue(nn)
    if due and os.clock() < due then
        M.holdQ = M.holdQ or {}
        if #M.holdQ < 32 then
            M.holdQ[#M.holdQ + 1] = { name = name, nn = nn, L = L, at = os.clock() }
            log("coop: the host's " .. name .. " waits for its copy here to have its own orders")
        end
        return
    end
    freeWaiting(name)
    -- ((code review of 2026-11-07, finding 1) a carrier launch: its arm's unit off this game's list first, hard rule 16)
    if ESC and ESC.beforeHostEvent then
        local okB, errB = pcall(ESC.beforeHostEvent, name)
        if not okB then once("esc before", "coop: the host's " .. tostring(name) .. ": the carrier's check here failed: " .. tostring(errB)) end
    end
    local r = rawEvent(name)
    if r ~= 1 then once("ev" .. tostring(r), "coop: the host's event " .. name .. " not fired here (" .. (SV_ERR[r] or tostring(r)) .. ")") end
    -- ((0.73.78, plan G4) a flight the host despawned (an ace break-off, the Spaceport's withdrawal): its copies here off,
    -- unpaid (sv_rounds.lua flightWithdrawn), fired here or not (the host's "dn" finishes them then); before, this game's
    -- sweep paid the vanished copies as its own kills a second on)
    -- ((0.73.83) the host took VOID WATCHER 1 off: any copy of it still here unbound and taken down (unpaid), its unit off
    -- this game's spawner list 2 s on (the host's recycles it then too); before, its stream held and its ghost flew on)
    local aw = CFG.allies and CFG.allies.awacs
    if type(aw) == "table" and type(aw.home) == "table" and aw.home.remove == name and aw.unit then
        local n = 0
        for id, c in pairs(M.copies) do
            if c.unit == aw.unit then
                killCopy(id, c.obj, true, true)
                M.copies[id] = nil
                n = n + 1
            end
        end
        local cu = M.cunits[aw.unit]
        if cu then cu.planes = {} end
        M.recycleDue = M.recycleDue or {}
        M.recycleDue[#M.recycleDue + 1] = { unit = aw.unit, at = os.clock() + 2, why = name }
        log(string.format("coop: the host took %s off (%s): %d copies here taken down (unpaid), its unit off the list 2 s on", aw.unit, name, n))
    end
    local fo = tonumber(tostring(name):match("^RE_SV_FlightOff_(%d%d)$"))
    local fu = fo and poolUnit and poolUnit(fo)
    if fu and flightWithdrawn then
        log(string.format("coop: the host took %s off (%s): %d of its copies here off, unpaid", fu, name, flightWithdrawn(fu)))
    end
end

function clientRounds(now)
    if not D then return end
    D.now = now
    local r = M.rnd
    if r then
        -- (the measurements' rounds, sv_stats.lua: a joiner runs no startRound or clear of its own, so the host's round
        -- number changing starts one and the host's state going back to "wait" ends it)
        if r.round ~= D.round then
            if STATS then pcall(STATS.roundEnd, now) end
            D.round = r.round
            RUN.roundKills = { you = 0, allies = 0, ships = 0, defences = 0, airstrike = 0 }
            if STATS and r.round >= 1 and r.state ~= "wait" then pcall(STATS.roundStart, now) end
        end
        if STATS and r.state == "wait" and D.state ~= "wait" then pcall(STATS.roundEnd, now) end
        -- ((0.73.83) the round's kills from this game's own count, as the host shows its own: the host's callout was
        -- sent to every joiner, wrong for Rapt0r in 8 of 9 rounds (0.73.79, 2026-11-04))
        if r.state == "wait" and D.state ~= "wait" and D.round == r.round then
            local k = RUN.roundKills
            if k then
                log(string.format("kills: round %d: you %d, allied aircraft %d, ships %d, airfield defences %d, airstrikes %d (this game's)",
                    D.round, k.you or 0, k.allies or 0, k.ships or 0, k.defences or 0, k.airstrike or 0))
                if (k.allies or 0) + (k.ships or 0) + (k.defences or 0) > 0 then
                    local t = CFG.hud.text
                    COOP.localCallout(string.format(t.kills, D.round), string.format(t.kills_sub, (k.you or 0) + (k.airstrike or 0),
                        k.allies or 0, k.ships or 0, k.defences or 0))
                end
            end
        end
        D.state = r.state
        if r.state == "wait" then D.at = now + r.secs - (os.clock() - r.got) else D.at = now end
        D.wave = r.wave > 0 and r.wave or nil
        D.intLevel = r.level and { round = r.round, level = r.level } or nil   -- (the copies fly it: DIR.level, P4)
        D.glitchPhase = r.glitchPhase                    -- (AB.L..IN's on the host: ANOM.clientGlitch, P7)
        D.hostSpecial = r.hostSpecial                    -- ((0.73.77) the host's special and its state: ANOM.clientTick, SPC.clientClean)
        local hs = r.hostSpecial                         -- ((0.73.79) her song and sounds loaded before her mood: sv_sound.lua)
        if (r.special == "valka" or (type(hs) == "table" and hs.kind == "valka")) and SND and SND.preloadValka then
            pcall(SND.preloadValka)
        end
        if r.waves > 0 then D.waves = D.waves and #D.waves == r.waves and D.waves or {}; for i = #D.waves + 1, r.waves do D.waves[i] = {} end
        else D.waves = nil end
    end
    if not levelReady() then return end
    if M.dvQ and #M.dvQ > 0 then                         -- the director's events here once their delay is up ("dv")
        local keep = {}
        for _, q in ipairs(M.dvQ) do
            if os.clock() < q.at then keep[#keep + 1] = q
            elseif os.clock() > q.at + DV_LATE_S then
                once("dvlate", string.format("coop: the host's director event %s dropped (%.1f s past its time: this level "
                    .. "wasn't ready)", q.name, os.clock() - q.at))
            elseif dvCopy(q.name, q.unit) then
                freeWaiting(q.name)
                local r = rawEvent(q.name)
                log(string.format("coop: director %s fired here (%s): %s", q.name, q.unit, r == 1 and "fired" or (SV_ERR[r] or tostring(r))))
            end
        end
        M.dvQ = keep
    end
    if M.holdQ and #M.holdQ > 0 then                     -- the host's holds once their copies have had their orders
        local keep, t = {}, os.clock()
        for _, q in ipairs(M.holdQ) do
            local due = holdDue(q.nn)
            if due and t < due and t - q.at < HOLD_MAX_S then keep[#keep + 1] = q
            elseif due and t < due then
                log(string.format("coop: the host's %s dropped here (its copy wasn't up %d s on)", q.name, HOLD_MAX_S))
            else
                local r = rawEvent(q.name)
                log(string.format("coop: the host's %s fired here %.1f s after it came (its copy's orders first): %s", q.name,
                    t - q.at, r == 1 and "fired" or (SV_ERR[r] or tostring(r))))
            end
        end
        M.holdQ = keep
    end
    if ANOM and ANOM.clientTick then                     -- the Anomaly's field on your own distance to its copy
        local okA, errA = pcall(ANOM.clientTick)
        if not okA then once("anomField", "coop: anomaly field error " .. tostring(errA)) end
    end
    if ANOM and ANOM.clientGlitch then                   -- AB.L..IN's copy in its phase 3: its ECM pods off here too
        local okG, errG = pcall(ANOM.clientGlitch, now)
        if not okG then once("glitchPods", "coop: AB.L..IN pods error " .. tostring(errG)) end
    end
    if SPC and SPC.clientClean then                      -- ((0.73.77) D4: a finished special's copies taken off here)
        local okSc, errSc = pcall(SPC.clientClean, now)
        if not okSc then once("specialClean", "coop: special clean-up error " .. tostring(errSc)) end
    end
    for i = #M.spawnQ, 1, -1 do
        local q = M.spawnQ[i]
        if os.clock() >= (q.at or 0) then
            local okS, done = pcall(doSpawn, q)
            if not okS then log("coop: spawn error " .. tostring(done)); done = true end
            if done then table.remove(M.spawnQ, i) end
        end
    end
    -- the host's events held while this level loaded, in order (code review: some set lasting state, as the railgun
    -- warning and the shuttle's countdown), after the spawns waiting with them (an event for a unit not up yet does
    -- nothing: the Alicorn's open core for a joiner who started over); older than a minute: let go
    if M.evQ and #M.evQ > 0 and #M.spawnQ == 0 and os.clock() - (M.lastSpawnAt or 0) >= 2 then
        local q = M.evQ
        M.evQ = nil
        for _, e in ipairs(q) do
            if os.clock() - e.at < 60 and not keptThrough(e.unit, e.name) then hostEvent(e.name) end   -- (a hold: once its
        end                                                                                             -- copy's had its orders)
    end
end

-- (a joiner, every 5 s) a copy spawned here that's still not bound to the host's plane STRAY_S on: never driven by the
-- host, it would fly on by its own AI (the co-op run of 2026-10-30: enemies seen a round after the host had cleared them).
-- (0.73.73) A stray is up: not a copy the host has said is down, nor one taken down here in the last DOWN_KEEP_S. The
-- host's "dn" took its copy down and left it in its flight's planes here, so 0.73.70 counted each of the host's kills a
-- stray a few seconds on and asked for the whole picture: 105 of the testers' 115 "jn" came within 12 s of the host's
-- kill (A04's crumbs: 12:41:00.089 "copy ..._2147415945 taken down (id 1)", 12:41:01.643 the same copy "taken down (id 0,
-- torn: not a kill)", 12:41:02 every copy torn down). A stray is taken down, then the host's picture asked for: its
-- answer is a repair (onResync), which brings a flight the host still has up whole again here, bound to the host's.
local STRAY_S, DOWN_KEEP_S = 15, 30
local function strayable(o, a, id)
    if id and M.dead[id] then return false end
    local t = M.downAt[a]
    if t and os.clock() - t < DOWN_KEEP_S then return false end
    return (health(o) or 1) > 0
end
local function strayTick(now)
    if now < (M.strayAt or 0) then return end
    M.strayAt = now + 5
    pruneObjs()
    for a, t in pairs(M.downAt) do if now - t >= DOWN_KEEP_S then M.downAt[a] = nil end end
    for a, k in pairs(M.killer or {}) do if now - k.at >= DOWN_KEEP_S then M.killer[a] = nil end end   -- ((0.73.77) C1)
    local bound = {}
    for _, c in pairs(M.copies) do local a = c.addr or live(c.obj); if a then bound[a] = true end end
    local found, inFound = {}, {}
    for unit, cu in pairs(M.cunits) do
        if cu.at and now - cu.at >= STRAY_S then
            for ord, o in pairs(cu.planes or {}) do
                local a = live(o)
                if a and not bound[a] and not inFound[a] and strayable(o, a, cu.binds and cu.binds[ord]) then
                    inFound[a] = true
                    found[#found + 1] = { o = o, a = a, cu = cu, ord = ord, what = unit .. " #" .. ord }
                end
            end
        end
    end
    -- and any enemy AI plane here (sv_core's `planes`: allies, wingmen and the Alicorn's parked ones aren't in it; the other
    -- players' AI stand-ins skipped) that isn't one of the host's: the user, 2026-10-30, "I'm seeing players go after enemies
    -- that I'm not seeing, no target boxes or anything, however on their side they see aircraft there"
    M.strayFirst = M.strayFirst or {}
    local stillHere = {}
    for _, p in ipairs(planes or {}) do
        local o = p.obj
        local a = live(o)
        if a and not inFound[a] and not p.down and not (p.unit and SLOT_OF[p.unit]) and not bound[a] then
            stillHere[a] = true
            local first = M.strayFirst[a]
            if not first then M.strayFirst[a] = now
            elseif now - first >= STRAY_S and strayable(o, a) then
                inFound[a] = true
                found[#found + 1] = { o = o, a = a, what = (p.unit or "?") .. " " .. tostring(p.name) }
            end
        end
    end
    for a in pairs(M.strayFirst) do if not stillHere[a] then M.strayFirst[a] = nil end end
    -- (each flight's copies 20 s after they spawned: how many got the host's id, once)
    for unit, cu in pairs(M.cunits) do
        if cu.at and not cu.bindSaid and now - cu.at >= 20 and (cu.n or 0) > 0 then
            cu.bindSaid = true
            local nb = 0
            for ord = 1, cu.n do if cu.binds and cu.binds[ord] then nb = nb + 1 end end
            if nb < (cu.n or 0) then
                -- (which generation it was spawned as, and the host's last ids for that unit: whether they came at all.
                -- The co-op run of 2026-10-31: flights re-spawned after a resync went unbound, 57 on one joiner's game)
                local bl = M.bdLast and M.bdLast[unit]
                log(string.format("coop: the host's %s here: %d of %d planes bound to the host's (spawned as gen %s; the host's "
                    .. "last ids for it: %s)", unit, nb, cu.n or 0, tostring(cu.gen),
                    bl and string.format("%d for gen %s", bl.n, tostring(bl.gen)) or "none"))
            end
        end
        -- ((0.73.80) and its ships, vehicles and parts, once a spawn: the amphibious assault's craft, the defences and the
        -- shuttle's pad had no ids before 0.73.80, and their copies here fought on their own)
        if cu.at and not cu.gbindSaid and now - cu.at >= 20 and next(cu.gcount or {}) ~= nil then
            cu.gbindSaid = true
            local seen, nb, ids = 0, 0, 0
            for _, k in pairs(cu.gcount) do seen = seen + k end
            for _ in pairs(cu.gb or {}) do nb = nb + 1 end
            for _ in pairs(cu.gbinds or {}) do ids = ids + 1 end
            log(string.format("coop: the host's %s here: %d of %d ground objects bound to the host's ids (%d ids from the host)%s",
                unit, nb, seen, ids, nb < seen and "; the rest fight on their own here" or ""))
        end
    end
    if #found == 0 or not COOP.client() then return end
    local rp = M.rep
    if rp and not rp.done then return end                -- (the host's picture on its way: it may bind them)
    local names = {}
    for i, f in ipairs(found) do
        if i <= 6 then names[i] = f.what end
        killCopy(0, f.o, true, true)
        if f.cu and f.ord and f.cu.planes[f.ord] == f.o then f.cu.planes[f.ord] = nil end
        M.strayFirst[f.a] = nil
    end
    M.cnt.strays = M.cnt.strays + #found
    M.tornWhy = "strays"
    -- (then the host's picture, at most every 2 minutes: a repair, onResync; a flight it still has up that lost a plane
    -- here comes again whole, bound to the host's)
    local asked = false
    if now >= (M.resyncAt or 0) and now - (M.jnAt or -1e9) >= 30 then
        M.resyncAt, M.jnAt = now + 120, os.clock()
        send(true, "jn")
        M.cnt.jnSent = M.cnt.jnSent + 1
        asked = true
    end
    log(string.format("coop: %d stray enemy copies taken down (here %d s, never bound to the host's)%s: %s", #found, STRAY_S,
        asked and "; asked the host for its whole picture (jn): a flight of these it still has up comes again" or "",
        table.concat(names, ", ")))
end

-- (0.73.79) Which of a copy's hits at the floor were yours. 0.73.77-78 went by the copy's DamageHistoryMap alone once
-- your plane had shown up in any map (M.ownSeen), and a hit it didn't find under your plane was "not yours": the copy
-- was put back up and nothing sent. Your missiles aren't found there (2026-11-03, 0.73.78, four players: Nada's two
-- missiles from 0.3 km "damage: you 0"; Shazzy "could not damage a single" enemy, the host "everyone else dumping into
-- enemies ... 6+ missiles"): every missile that would have finished a copy was undone here and never reached the host,
-- whose own planes never go through the floor (its game was normal). Now your missiles and gun aim are kept here, by
-- the copy they went for: the missile's target (FiredExplosiveWeapons' TargetToHome, as each is launched and when it's
-- gone) and the gun's (SV_PlayerTarget while it fires).
M.mslAt, M.mslEnd, M.gunAtT, M.shotTgt = {}, {}, {}, {}
local FIRED_MSL_S, FIRED_GUN_S, MSL_END_S, FLOOR_RESEND_S = 25, 1.5, 2, 2
function M.shotMark(a, ta) M.mslAt[ta] = os.clock(); M.shotTgt[a] = ta end
function M.shotEnd(a)
    local ta = M.shotTgt[a]
    M.shotTgt[a] = nil
    if ta then M.mslEnd[ta] = os.clock() end
end
function M.gunMark(t) M.gunAtT[t] = os.clock() end
-- "msl" one of your missiles went for addr in the last FIRED_MSL_S, "gun" your gun is firing at it, or nil
function M.firedAt(addr, now)
    if not addr then return nil end
    local m, g = M.mslAt[addr], M.gunAtT[addr]
    if m and now - m <= FIRED_MSL_S then return "msl" end
    if g and now - g <= FIRED_GUN_S then return "gun" end
    return nil
end
local function shotsPrune(now)
    if now < (M.shotPruneAt or 0) then return end
    M.shotPruneAt = now + 10
    for _, t in ipairs({ M.mslAt, M.mslEnd, M.gunAtT }) do
        for k, at in pairs(t) do if now - at > 60 then t[k] = nil end end
    end
    local n = 0
    for _ in pairs(M.shotTgt) do n = n + 1 end
    if n > 200 then M.shotTgt = {} end                     -- (missiles seen launched but never gone: a level change)
end
-- what the hit that took copy c to the floor is sent to the host as (x 10): own is your damage on it since the last look
-- from its map (nil: unread, or your plane not in any map yet), loss what it lost here (less the stand-ins' share),
-- others that share (x 10, the stand-ins', the host's allies' copies' and this game's own ZFA-44s' since the last look)
function M.floorLoss(c, own, loss, now, others)
    if own and own >= c.exp then return own end           -- (the map has your whole hit)
    local f = M.firedAt(c.addr, now)
    if f == "msl" then                                     -- (your missile went for it: the hit is yours, whole)
        M.cnt.floorMsl = (M.cnt.floorMsl or 0) + 1
        if not (own and own > 0) then
            once("floormsl", string.format("coop: a copy taken to the floor by your missile (its map has %s of yours): sent "
                .. "whole to the host (%.1f)", own and string.format("%.1f", own / 10) or "nothing read", c.exp / 10))
        end
        return c.exp
    end
    if own and own > 0 then return own end                 -- (your gun's, from the map)
    -- ((code review of 2026-11-07, finding 1) its map shows another's hit (a stand-in, the host's allies' copies, this
    -- game's own ZFA-44s): never the whole as yours, only what its map doesn't explain)
    if (others or 0) > 0 then
        M.cnt.floorOthers = (M.cnt.floorOthers or 0) + 1
        once("floorothers", string.format("coop: a copy taken to the floor with another's hit in its map (%.1f): not sent whole as "
            .. "yours (%.1f of it sent)", others / 10, math.max(0, loss) / 10))
        return math.max(0, loss)
    end
    if own == nil and loss > 0 then return c.exp end       -- (as 0.73.76: unread, it's yours)
    if f == "gun" then return c.exp end                    -- (your gun on it this second)
    return 0                                               -- (not yours: an ally's copy, a ship's, a crash)
end

function clientTick()
    pcall(strayTick, os.clock())
    pcall(shotsPrune, os.clock())
    pcall(M.buildTick, os.clock())
    -- the copies' hits: what each lost since last time goes to the host, less what another player's stand-in did to it
    -- here (their own hits come from their game: the stand-ins fly damage-0 rows, COOP.syncSetup; this is the backstop)
    -- (0.73.77, plan A1) A copy waits at the floor (FLOOR_IN, floorOn) for the host's kill, and the floor clips the hit
    -- that takes it there, so what's sent then is your own damage from its DamageHistoryMap (every hit is added there in
    -- full: the whole missile), or, the map unread, all it was expected to have (0.73.76's). A copy taken to the floor by
    -- something else (the host's allies' copies here, a crash) sends nothing and is put back up to what the host's has
    -- after your hits; one whose hit sent is lethal waits there for the host's "dn" (A6: the sync report's wait). A copy
    -- at the floor whose health doesn't move (the clamp: the host said less than the floor) is asked its map each tick.
    local ins, pa = nil, false
    for id, c in pairs(M.copies) do
        if valid(c.obj) then
            local h = health(c.obj)
            if h and h < c.exp and c.ally then
                c.exp = h                                  -- (an ally's copy: its fight is the host's, nothing sent)
                if h > 0 and h <= FLOOR_IN and (c.hp or 0) > FLOOR_IN then   -- ((0.73.77) at the floor: back to the host's)
                    local v = c.hp
                    if pcall(function() c.obj.HealthInternal = v end) then c.exp = v end
                end
            elseif h and h < c.exp then
                local loss = c.exp - h
                ins = ins or (M.standInSet and M.standInSet()) or {}
                if pa == false then pa = myAddr() end
                local sd, mine = 0, nil                    -- ((0.73.77) its map read only while it's live: kept between ticks)
                if live(c.obj) then sd, mine = M.historyOf(c.obj, ins, pa) end
                local inc = sd - (c.sdmg or 0)
                c.sdmg = sd
                if inc > 0 then
                    local cut = math.min(loss, inc * 10)                   -- (DamageHistoryMap: health, not x 10)
                    loss = loss - cut
                    M.backstops = (M.backstops or 0) + 1
                    if M.backstops <= 5 or M.backstops % 50 == 0 then
                        log(string.format("coopfire: copy %d lost %.1f, %.1f of it another player's stand-in's here: %s "
                            .. "(%d times)", id, (loss + cut) / 10, cut / 10, loss > 0 and string.format("%.1f sent", loss / 10)
                            or "nothing sent", M.backstops))
                    end
                end
                local own = nil                            -- ((0.73.77) yours since the last look, x 10; nil: unread,
                if mine then                               -- or your plane not yet seen in any copy's map this level)
                    local d = math.max(0, (mine - (c.mine or 0)) * 10)
                    c.mine = mine
                    if M.ownSeen then own = d end
                end
                local newH = h
                if h > 0 and h <= FLOOR_IN then            -- (down here, the floor not held: as before, never put back)
                    loss = M.floorLoss(c, own, loss, os.clock(), inc > 0 and inc * 10 or 0)   -- ((0.73.79) your missiles too)
                    if loss < c.exp then                   -- (not lethal by what's sent: up to the host's after it)
                        local v = math.max(FLOOR_IN + 1, c.exp - loss)
                        if pcall(function() c.obj.HealthInternal = v end) then newH = v end
                        M.cnt.floorBack = M.cnt.floorBack + 1
                    elseif not c.floorAt then
                        c.floorAt = os.clock()             -- (lethal: it waits here for the host's kill)
                        c.preFloor = c.exp                 -- ((0.73.79) what it had: sent again if it waits on, below)
                        M.cnt.floored = M.cnt.floored + 1
                    end
                end
                if loss > 0 then
                    send(true, "ht", id, string.format("%.1f", loss / 10))
                    c.sentAt, c.sentFrom = os.clock(), c.exp   -- ((0.73.79) the host's "hp" from before it lands is held off)
                end
                c.exp = newH
            elseif h and h > 0 and h <= FLOOR_IN and not c.ally then
                -- ((0.73.77) at the floor, its health not moving: your hits since, from the map)
                if pa == false then pa = myAddr() end
                local mine = nil
                if live(c.obj) then mine = select(2, M.historyOf(c.obj, nil, pa)) end
                local own = (mine and M.ownSeen) and (mine - (c.mine or 0)) * 10 or 0
                if mine then c.mine = mine end
                local now = os.clock()
                if own > 0 then
                    send(true, "ht", id, string.format("%.1f", own / 10))
                    c.sentAt, c.sentFrom = now, math.max(c.hp or 0, FLOOR_IN)
                    if not c.floorAt then c.floorAt = now; M.cnt.floored = M.cnt.floored + 1 end
                else
                    -- ((0.73.79) a missile of yours that went for it is gone (it hit, or missed) and the host's kill
                    -- hasn't come: what the host last had is sent as a hit, at most every FLOOR_RESEND_S. Its health
                    -- doesn't move at the floor, so this is the only sign of a missile hit here; a miss that ends near
                    -- a copy already held at 1 HP is the price)
                    local e = M.mslEnd[c.addr]
                    if e and now - e <= MSL_END_S and e > (c.resendAt or 0) and now - (c.resendAt or 0) >= FLOOR_RESEND_S then
                        local v = math.max(c.hp or 0, c.preFloor or 0, FLOOR_IN)
                        c.resendAt, c.sentAt, c.sentFrom = now, now, v
                        send(true, "ht", id, string.format("%.1f", v / 10))
                        M.cnt.floorResend = (M.cnt.floorResend or 0) + 1
                        once("floorresend", string.format("coop: copy %d held at the floor, your missile at it gone, no kill "
                            .. "from the host yet: its last health sent again as your hit (%.1f)", id, v / 10))
                        if not c.floorAt then c.floorAt = now; M.cnt.floored = M.cnt.floored + 1 end
                    end
                end
                c.exp = h
            elseif h and h > c.exp then
                c.exp = h                                  -- (raised here: CFG.late, a repair)
            end
        else
            M.copies[id] = nil
        end
    end
end
end  -- (sv_coop.lua's do block goes on in sv_coop_planes.lua)
