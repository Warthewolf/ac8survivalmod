-- sv_fishing.lua: GONE FISHIN' (CFG.specials.fishing; FISHING_ROUND_PLAN.md; tools/re/FISHING.md 1-4): the shoals and
-- SAL's boat. Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a
-- global of this mod's Lua state, its own helpers stay local.
-- The rows at the main menu (FISH.setup), what each spawn makes (FISH.actors), the splash, the hit sphere, the round
-- itself (below: "the round") and the test keys (Ctrl+F10 the shoals and the boat, Ctrl+HOME the round now; test only).
-- The build data (tools/build_survival.py, the contract of 2026-11-06): a shoal is DT_SV_NpcRows' SV_Shoal (a copy of the
-- stock invisible turret pawn GR000_dummy with the vessels' durability ids) on DT_SV_ModelRows' SV_Model_Shoal (MaxHealth
-- 10), mission row sv_shoal; units SV_Unit_FishA / B / C of 8 shoals each (boxed, TGT, within 800 m of the unit's origin,
-- offset z 0); SAL's boat SV_Unit_SalBoat (the stock VE027_boat2_01, allied, MinHealth 1, invincible from AI and wingmen).
FISH = { actors = {}, rowsReady = nil, setupDone = false, tries = 0 }
do
local function cfg() return CFG.specials.fishing end
local function isFishUnit(u)
    local c = cfg()
    if u == c.boat_unit then return true end
    for _, x in ipairs(c.units or {}) do if x == u then return true end end
    return false
end
FISH.isUnit = isFishUnit
-- SAL's boat's unit (sv_coop.lua leaves it out of the host's health batch: each game's copy moves with its own hits)
function FISH.isBoat(u) return u ~= nil and u == cfg().boat_unit end

-- (the main menu, sv_main.lua's setup pass) the shoal's DT_NPC row and its model row into the game's tables, as VOID
-- WATCHER 1's (sv_allies.lua): a row naming a model the game hasn't can't spawn. Its names' texts set (SV_SetText).
function FISH.setup()
    if FISH.setupDone or not cfg().enabled or not gameInstance() then return end
    FISH.tries = FISH.tries + 1
    local c = cfg()
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows)
    local mt, mr = loadObject(ACE.model_table), loadObject(ACE.model_rows)
    if not (npc and mine and mt and mr) then
        if FISH.tries >= 20 then FISH.setupDone = true; log("fishing: the row tables didn't load: no shoals this session") end
        return
    end
    FISH.setupDone = true
    for _, t in ipairs({ npc, mine, mt, mr }) do pin(t, nameOf(t)) end
    local function addRow(dst, src, row)
        local _, have = dtCall(dst, "FindRow", row)
        if have == nil then
            local _, r = dtCall(src, "FindRow", row)
            if r ~= nil then dtCall(dst, "AddRow", row, r); _, have = dtCall(dst, "FindRow", row) end
        end
        return have ~= nil
    end
    local model = addRow(mt, mr, c.shoal_model)               -- (the model first: the row names it)
    local row = addRow(npc, mine, c.shoal_row)
    FISH.rowsReady = model and row
    local names = {}
    if type(SV_SetText) == "function" then
        names[#names + 1] = c.shoal_name_key .. " " .. (SV_SetText(c.shoal_name_key, c.shoal_name) == 1 and "set" or "NOT set")
        if c.shoal_sub_key then                           -- ((2026-11-07) the box's second line: SHOAL showed twice)
            names[#names + 1] = c.shoal_sub_key .. " " .. (SV_SetText(c.shoal_sub_key, c.shoal_sub or "") == 1 and "set" or "NOT set")
        end
        names[#names + 1] = c.boat_name_key .. " " .. (SV_SetText(c.boat_name_key, c.boat_name) == 1 and "set" or "NOT set")
    end
    log(string.format("fishing: the shoal's rows: %s %s, %s %s; names: %s", c.shoal_row, row and "in DT_NPC" or "NOT added",
        c.shoal_model, model and "in DT_NPC_Model" or "NOT added", #names > 0 and table.concat(names, ", ") or "no SV_SetText"))
end

-- What each of our units' spawns make: FISH.actors[unit] = { obj, ... } in the spawner's order, only while a caller has
-- made the list (FISH.expect) and set spawningUnit around its SV_Spawn (the constructing thread is the game thread then).
pcall(NotifyOnNewObject, "/Script/Live.LiveAIGameObject", function(o)
    local u = spawningUnit
    local l = u and FISH.actors[u]
    if l and l.open then l[#l + 1] = o end
end)
function FISH.expect(unit) FISH.actors[unit] = { open = true } end
-- one of our units spawned with its objects recorded (spawningUnit set, the co-op wrapper's ids with it); SV_Spawn's
-- answer
function FISH.spawn(unit, x, y, z, yaw)
    FISH.expect(unit)
    spawningUnit = unit
    local ok, r = pcall(SV_Spawn, unit, x, y, z, yaw)
    spawningUnit = nil
    local l = FISH.actors[unit]
    if l then l.open = false end
    if not ok then log("fishing: SV_Spawn " .. unit .. " error " .. tostring(r)); return -5 end
    return r
end
-- a unit's recorded objects still live (liveObj: kept between ticks)
function FISH.objs(unit)
    local out = {}
    for _, o in ipairs(FISH.actors[unit] or {}) do if liveObj(o) then out[#out + 1] = o end end
    return out
end
-- (a spawn whose objects the new-object feed didn't catch) the live objects of class `cls` within 2 km of (x, y): a walk
FISH.SHOAL_CLASS, FISH.BOAT_CLASS = "BP_GR000_dummy_CP_C", "VE028_boat2_CP_C"   -- (the stock blueprints the rows name)
function FISH.findNear(cls, x, y, r)
    local out = {}
    r = r or 200000                                     -- (cm; a ground's own shoals: within 900 m, the next ground 1.9 km off)
    for _, o in ipairs(FindAllOf(cls) or {}) do
        if liveObj(o) and inSurvival(o) then
            local okL, l = pcall(function() return o:K2_GetActorLocation() end)
            if okL and l and math.abs(l.X - x) < r and math.abs(l.Y - y) < r and (l.X - x) ^ 2 + (l.Y - y) ^ 2 < r * r then
                out[#out + 1] = o
            end
        end
    end
    return out
end

-- The sea splash at `at` (Niagara, the asset loaded the hard-rule-9 way and kept while it's live), x scale; true if it came
-- up. (sv_anomalies.lua fxAt's way, its own here: auto-destroyed when done)
local SPLASH = { sys = nil, path = nil, said = false }
function FISH.splashAsset()
    local c = cfg()
    local path = c.splash .. "." .. (c.splash:match("[^/]+$") or "")
    if SPLASH.sys ~= nil and SPLASH.path == path and liveObj(SPLASH.sys) then return SPLASH.sys end
    local o, why = loadObject(path)
    SPLASH.sys, SPLASH.path = o, path
    if not o and not SPLASH.said then SPLASH.said = true; log("fishing: the splash " .. path .. " didn't load: " .. tostring(why)) end
    return o
end
function FISH.splash(at, scale)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = FISH.splashAsset()
    if not (lib and valid(lib) and sys and liveObj(survivalPC) and at) then return false end
    local s = scale or cfg().splash_scale or 1
    return pcall(function()
        lib:SpawnSystemAtLocation(survivalPC, sys, { X = at.X, Y = at.Y, Z = at.Z }, { Pitch = 0, Yaw = 0, Roll = 0 },
            { X = s, Y = s, Z = s }, true, true, 0, true)
    end) == true
end

-- A hit sphere added to shoal o (AActor::AddComponentByClass, hard rule 46): radius m, collision profile `profile`. The
-- component and what it reads back, or nil and why not.
function FISH.addSphere(o, m, profile)
    local cls = StaticFindObject("/Script/Engine.SphereComponent")
    if not (cls and valid(cls)) then return nil, "no SphereComponent class" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, comp = pcall(function() return o:AddComponentByClass(cls, false, t, false) end)
    if not ok or comp == nil or not valid(comp) then return nil, "AddComponentByClass " .. (ok and "gave nothing" or tostring(comp)) end
    local done = {}
    done[#done + 1] = pcall(function() comp:SetSphereRadius(m * 100, true) end) and "radius" or "radius FAILED"
    done[#done + 1] = pcall(function() comp:SetCollisionProfileName(FName(profile), true) end) and "profile" or "profile FAILED"
    local okR, r = pcall(function() return comp:GetUnscaledSphereRadius() end)
    local okP, p = pcall(function() return comp:GetCollisionProfileName():ToString() end)
    local okE, e = pcall(function() return comp:GetCollisionEnabled() end)
    return comp, string.format("%s; reads radius %s m, profile %s, collision %s", table.concat(done, ", "),
        okR and string.format("%.1f", (r or 0) / 100) or "?", okP and tostring(p) or "?", okE and tostring(e) or "?")
end

-- health and its floor, as read (HealthInternal is health x 10; MaxHealth and MinHealth in health points)
function FISH.hp(o)
    local h, mx, mn
    pcall(function() h = o.HealthInternal end)
    pcall(function() mx = o.MaxHealth end)
    pcall(function() mn = o.MinHealth end)
    return h, mx, mn
end
-- who DamageHistoryMap names, with how much: "you 100, wingmate 20" ("-": nothing, "?": unreadable)
function FISH.who(o)
    local pawn = liveObj(survivalPC) and survivalPC.Pawn or nil
    local pa = pawn and addrOf(pawn) or nil
    local d, order = {}, {}
    local ok = pcall(function()
        o.DamageHistoryMap:ForEach(function(k, v)
            local okK, a = pcall(function() return k:get() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and type(x) == "number" and valid(a) then
                local s = KILL and KILL.side and KILL.side(a, pa) or "?"
                local nm = s .. "/" .. ((nameOf(a):match("([^%.:]+)$")) or "?")
                if not d[nm] then order[#order + 1] = nm end
                d[nm] = (d[nm] or 0) + x
            end
        end)
    end)
    if not ok then return "?" end
    if #order == 0 then return "-" end
    local t = {}
    for _, nm in ipairs(order) do t[#t + 1] = string.format("%s %.0f", nm, d[nm]) end
    return table.concat(t, ", ")
end

-- (the teardown gate's drop, sv_core.lua levelDrop: the level's objects forgotten untouched)
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["fishing"] = function() FISH.actors = {}; SPLASH.sys = nil end end
end

---------------------------------------------------------------------------------------------------- the round
-- GONE FISHIN' (0.74.0; FISHING_ROUND_PLAN.md, the user's decisions of 2026-11-06; SPC.kinds.fishing, sv_anomalies.lua).
-- The host's (or solo) round, D.special = { kind = "fishing", state = "intro" | "fishing" | "weigh" | "done", ... }:
--   intro    SAL and COMONA CONTROL talk it in on the strip (text.intro), SAL's boat at its spot; the arc's F set
--   fishing  the shoals spawned on the three grounds (each with its hit sphere), time_s on the clock; every check_s each
--            shoal looked at: one down draws the deck's next catch for whoever destroyed it (KILL.by; co-op: the host's
--            kill attribution, "fh" to everyone), its callout (`+38 KG YELLOWFIN TUNA` / `NOTHING`), its splash, SAL's
--            word; the timer's warnings, SAL's nudges (the first catch, empties in a row, a gun kill, an ally's, quiet_s
--            with no catch, you landed); every shoal down or the time up: the weigh-in
--   weigh    what's left of the shoals taken off; SAL weighs it; each player's own haul graded and paid (the team's total
--            on the card in co-op, "fw" / "fwe"), the card; the boat switched off
--   done     the round ends (sv_rounds.lua: busy() false)
-- SAL's boat on every game: a hit that shows on this game's own copy costs this game's player boat_penalty_kg (no co-op
-- message: each game takes it off its own line). A joiner's own part: FISH.clientTick / FISH.fromHost / FISH.clientRow.
-- Log lines: `fishing: ...` (round start, each catch, the warnings, the weigh-in and each pay).
do
local function cfg() return CFG.specials.fishing end
local function tx() return cfg().text or {} end
local CATCHES = { "none", "junk", "sardine", "mackerel", "tuna", "swordfish", "bigone" }
FISH.CATCHES = CATCHES
local CATCH_OK = {}
for _, c in ipairs(CATCHES) do CATCH_OK[c] = true end
local BIG_FISH = { tuna = true, swordfish = true, bigone = true }
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function mmss(sec) sec = math.max(0, math.floor(sec + 0.5)); return string.format("%d:%02d", sec // 60, sec % 60) end
local function money(x) return (tostring(math.floor(x)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
local function coopOn() return COOP ~= nil and COOP.open == true end
local function mySlot() return (coopOn() and COOP.slot) or 0 end
local function nameOfSlot(slot)
    if slot == -1 then return "ALLIES" end
    if coopOn() and COOP.name then local ok, nm = pcall(COOP.name, slot); if ok and nm then return tostring(nm):upper() end end
    return "PILOT " .. tostring((slot or 0) + 1)
end

-- a line "S|text" / "C|text" / "T|text" / "G|text": its speaker (SAL, COMONA CONTROL, COMONA TOWER, the CREW CHIEF:
-- 2026-11-07, "Give SAL and the Comona Airbase Staff some more unique lines") and its text with {kg}, {fish}, {grade},
-- {pay} filled in
function FISH.line(line, vals)
    local t = tx()
    local code, text = tostring(line or ""):match("^([%w _']+)|(.*)$")
    if not code then code, text = "S", tostring(line or "") end
    -- ((2026-11-07) THE FESTIVAL's town: a longer code is a speaker's own, its name CFG.hud.subs.speakers[code] or itself)
    local who = (#code > 1 and ((((CFG.hud or {}).subs or {}).speakers or {})[code] or code))
        or (code == "C" and (t.control or "COMONA CONTROL")) or (code == "T" and (t.tower or "COMONA TOWER"))
        or (code == "G" and (t.crew or "CREW CHIEF")) or (t.sal or "SAL")
    text = text:gsub("{(%w+)}", function(k) local v = vals and vals[k]; if v == nil then return "{" .. k .. "}" end return tostring(v) end)
    return who, text
end
-- one entry of a list (a string: itself), at random, never the one picked last under `key`
local lastPick = {}
function FISH.pick(l, key)
    if type(l) ~= "table" then return l end
    if #l == 0 then return nil end
    local i = math.random(#l)
    if #l > 1 and lastPick[key] == i then i = i % #l + 1 end
    lastPick[key] = i
    return l[i]
end
-- the lines said whole: a list of lines as is, or one of a list of such lists (FISH.pick); a string: itself alone
function FISH.seq(l, key)
    if type(l) == "string" then return { l } end
    if type(l) ~= "table" then return {} end
    if type(l[1]) == "table" then return FISH.pick(l, key) or {} end
    return l
end
-- one of text[key]'s lines (a list or a string) said, never the one said last for that key; here: this game only
function FISH.say(key, vals, here, secs)
    local x = FISH.pick(tx()[key], "fish." .. tostring(key))
    if type(x) == "table" then x = x[1] end
    if type(x) ~= "string" then return false end
    local who, text = FISH.line(x, vals)
    if here then return SUB.sayHere(who, text, secs) end
    return SUB.say(who, text, secs)
end
-- every line of text[key] (one exchange of them: FISH.seq), in order
function FISH.sayAll(key, vals, here)
    for _, x in ipairs(FISH.seq(tx()[key], "fish." .. tostring(key))) do
        local who, text = FISH.line(x, vals)
        if here then SUB.sayHere(who, text) else SUB.say(who, text) end
    end
end

-- The round's catch deck: `count` catches apportioned from the weights (largest remainder; The Big One at most bigone_max,
-- its share left out past that), shuffled
function FISH.deck(count, weights, bigMax, rnd)
    rnd = rnd or math.random
    weights = weights or cfg().catch or {}
    bigMax = math.floor(n(bigMax, n(cfg().bigone_max, 1)))
    local sum = 0
    for _, c in ipairs(CATCHES) do sum = sum + math.max(0, n(weights[c], 0)) end
    local deck = {}
    if sum <= 0 or count <= 0 then for _ = 1, math.max(0, count) do deck[#deck + 1] = "none" end; return deck end
    local got, rem, used = {}, {}, 0
    for _, c in ipairs(CATCHES) do
        local q = count * math.max(0, n(weights[c], 0)) / sum
        got[c] = math.floor(q)
        rem[#rem + 1] = { c = c, r = q - got[c] }
        used = used + got[c]
    end
    table.sort(rem, function(a, b) if a.r ~= b.r then return a.r > b.r end return a.c < b.c end)
    local i = 1
    while used < count and i <= #rem * 2 do
        local e = rem[(i - 1) % #rem + 1]
        if e.c ~= "bigone" or got.bigone < bigMax then got[e.c] = got[e.c] + 1; used = used + 1 end
        i = i + 1
    end
    if got.bigone > bigMax then got.none, got.bigone = got.none + got.bigone - bigMax, bigMax end
    while used < count do got.none = got.none + 1; used = used + 1 end
    for _, c in ipairs(CATCHES) do for _ = 1, got[c] do deck[#deck + 1] = c end end
    for j = #deck, 2, -1 do local k = rnd(j); deck[j], deck[k] = deck[k], deck[j] end
    return deck
end
-- a catch's kg: a whole number in its kg range (0: nothing, junk)
function FISH.kgOf(catch, rnd)
    local r = (cfg().kg or {})[catch]
    if type(r) ~= "table" then return 0 end
    local lo, hi = math.floor(n(r[1], 0)), math.floor(n(r[2], n(r[1], 0)))
    if hi < lo then lo, hi = hi, lo end
    return (rnd or math.random)(lo, hi)
end
-- a haul's grade and its bonus: thresholds (grade_s .. grade_c, kg) x players ^ -coop_grade_x
function FISH.grade(kg, players)
    local c = cfg()
    local x = (players or 1) > 1 and (players ^ -math.max(0, n(c.coop_grade_x, 1))) or 1
    for _, g in ipairs({ "s", "a", "b", "c" }) do
        if kg >= n(c["grade_" .. g], 0) * x then return g:upper(), n(c["bonus_" .. g], 0) end
    end
    return "D", n(c.bonus_d, 0)
end
-- a haul's pay: kg x credits_per_kg + its grade's bonus (+ bigone_bonus), x (1 + pay_per_round per round past from_round)
function FISH.payFor(kg, players, round, bigone)
    local c = cfg()
    local g, bonus = FISH.grade(kg, players)
    local x = 1 + n(c.pay_per_round, 0) * math.max(0, (round or 0) - n(c.from_round, 7))
    local pay = math.floor((kg * n(c.credits_per_kg, 0) + bonus + (bigone and n(c.bigone_bonus, 0) or 0)) * x + 0.5)
    return pay, g, x
end
-- ((code review of 2026-11-07, finding 9) the most a round can hold, for what the host sends: its shoals (the build's
-- 8 a ground, tools/survival_events.py FISH_PER_GROUND, on each unit) and the heaviest catch's kg; one weigh-in's pay at
-- most PAY_MAX (sv_coop.lua's CREDITS_MAX)
FISH.PER_GROUND, FISH.PAY_MAX = 8, 1000000
function FISH.maxShoals() return math.max(1, #(cfg().units or {})) * FISH.PER_GROUND end
-- ((2026-11-07) the user, after Alyssa's test: "the shoals need to be more numerous and spread around the boat") each
-- unit's ground, all round SAL's boat (boat_at): the first on the boat itself (its shoals 300-800 m out: the build's
-- FISH_INNER_MIN_M), the others evenly on a ring of ring_m round it from a bearing new each round (yaw: the ring's turn,
-- radians; a random one by default). [{ x, y }] cm, one a unit of `units`
function FISH.grounds(turn)
    local c = cfg()
    local b, us, out = c.boat_at or { 0, 0 }, c.units or {}, {}
    local ring, a0 = n(c.ring_m, 1900) * 100, turn or (math.random() * 2 * math.pi)
    for i = 1, #us do
        if i == 1 then
            out[i] = { b[1], b[2] }
        else
            local a = a0 + 2 * math.pi * (i - 2) / math.max(1, #us - 1)
            out[i] = { b[1] + ring * math.cos(a), b[2] + ring * math.sin(a) }
        end
    end
    return out
end
function FISH.maxKg()
    local m = 0
    for _, r in pairs(cfg().kg or {}) do
        if type(r) == "table" then m = math.max(m, n(r[1], 0), n(r[2], 0)) end
    end
    return math.max(1, math.floor(m))
end

-- whether a GONE FISHIN' round can come (SPC.kinds.fishing.ready): on, the native spawner, its rows in the game's tables
-- (FISH.setup at the main menu), and once a run (`once`: RUN.fished, its round, or the arc's F: a host by migration has
-- only the arc's F, from the old host's "rnd" field 15, so its run had had GONE FISHIN' too); a test key's forced one always
-- ((code review of 2026-11-07, findings 5 and 10) before, a host by migration drew a second GONE FISHIN' (the arc moved to
-- it), and a run with the shoal's rows missing drew a round whose shoals couldn't spawn)
function FISH.ready(round, forced)
    local c = cfg()
    if c.enabled == false or not nativeReady() then return false end
    if forced then return true end
    if FISH.rowsReady ~= true then
        if not FISH.rowsSaid then
            FISH.rowsSaid = true
            log("fishing: no GONE FISHIN' round: the shoal's rows aren't in the game's tables (" .. (FISH.setupDone and "not added at the main menu"
                or "the main menu's setup hasn't run") .. ")")
        end
        return false
    end
    return not (c.once ~= false and RUN and (RUN.fished or (SKY and SKY.arcF and SKY.arcF())))
end

-- this game's player's boat penalty (FISH.boat: its kg and hits this round), a hit on this game's own copy of SAL's boat
FISH.boat = { kg = 0, hits = 0, at = nil, last = nil, round = nil }
local function boatObjs()
    local u = cfg().boat_unit
    local out, seen = {}, {}
    for _, l in ipairs({ FISH.actors[u] or {}, (SPC and SPC.CLEAN_OBJ and SPC.CLEAN_OBJ[u]) or {} }) do
        for _, o in ipairs(l) do
            local a = liveObj(o) and addrOf(o)
            if a and not seen[a] then seen[a] = true; out[#out + 1] = o end
        end
    end
    return out
end
-- (every check, the host's and a joiner's own) the boat's health against its last: a drop is this game's player's hit
local function boatTick(now, round, host)
    local B, c = FISH.boat, cfg()
    if B.round ~= round then B.kg, B.hits, B.at, B.last, B.round = 0, 0, nil, nil, round end
    local o = boatObjs()[1]
    if not o then return end
    local h, _, mn = FISH.hp(o)
    if host and type(mn) == "number" and mn < n(c.boat_min_health, 1) then pcall(function() o.MinHealth = n(c.boat_min_health, 1) end) end
    if type(h) ~= "number" then return end
    if B.last and h < B.last - 0.01 and now - (B.at or -1e9) >= n(c.boat_hit_gap_s, 4) then
        B.at, B.hits = now, B.hits + 1
        B.kg = B.kg + math.floor(n(c.boat_penalty_kg, 25))
        FISH.say("boat", nil, true)
        log(string.format("fishing: SAL's boat hit here (%.0f -> %.0f): -%d kg off your haul (%d kg in %d hits)", B.last, h,
            math.floor(n(c.boat_penalty_kg, 25)), B.kg, B.hits))
    end
    B.last = h
end

-- a slot's haul (the host's)
local function haulOf(s, slot)
    s.haul[slot] = s.haul[slot] or { kg = 0, hits = 0, empty = 0, junk = 0, best = nil, bestKg = 0, bigone = false }
    return s.haul[slot]
end
local function credit(h, catch, kg)
    h.hits = h.hits + 1
    if catch == "none" then h.empty = h.empty + 1 elseif catch == "junk" then h.junk = h.junk + 1 end
    h.kg = h.kg + kg
    if kg > h.bestKg then h.best, h.bestKg = catch, kg end
    if catch == "bigone" then h.bigone = true end
end
FISH.credit = credit
local function teamKg(s)
    local t = s.allyKg or 0
    for _, h in pairs(s.haul or {}) do t = t + h.kg end
    return t
end

local function spawnShoals(now, s)
    local c = cfg()
    pcall(SV_SetText, c.shoal_name_key, c.shoal_name)
    if c.shoal_sub_key then pcall(SV_SetText, c.shoal_sub_key, c.shoal_sub or "") end
    FISH.splashAsset()
    s.shoals, s.total = {}, 0
    local grounds = FISH.grounds()
    local said = {}
    for gi, unit in ipairs(c.units or {}) do
        local g = grounds[gi]
        if type(g) == "table" then
            local r = FISH.spawn(unit, g[1], g[2], c.shoal_z, math.random() * 360)
            if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, unit, r) end
            local objs = FISH.objs(unit)
            if #objs == 0 and r > 0 then                  -- (the new-object feed missed them: by their class round the ground)
                objs = FISH.findNear(FISH.SHOAL_CLASS, g[1], g[2], 90000)
                FISH.actors[unit] = { open = false, table.unpack(objs) }
            end
            local sph = 0
            for i, o in ipairs(objs) do
                s.shoals[#s.shoals + 1] = { obj = o, addr = addrOf(o), unit = unit, i = i, name = (nameOf(o):match("([^%.:]+)$")) or "?" }
                if c.sphere ~= false then
                    local comp = FISH.addSphere(o, n(c.sphere_m, 8), c.sphere_profile or "EnemyPawn")
                    if comp then sph = sph + 1 end
                end
            end
            said[#said + 1] = string.format("%s %s (%d seen, %d spheres)", unit, r > 0 and (r .. " up") or ("NOT spawned: " .. tostring(SV_ERR and SV_ERR[r] or r)),
                #objs, sph)
        end
    end
    s.total = #s.shoals
    s.deck = FISH.deck(s.total)
    local counts = {}
    for _, x in ipairs(s.deck) do counts[x] = (counts[x] or 0) + 1 end
    local dk = {}
    for _, x in ipairs(CATCHES) do if counts[x] then dk[#dk + 1] = x .. " " .. counts[x] end end
    log(string.format("fishing: round %d: %d shoals round SAL's boat: %s; the deck: %s", D.round, s.total, table.concat(said, "; "),
        table.concat(dk, ", ")))
end

function FISH.roundSpawn(now)
    local c, s = cfg(), D.special
    if not FISH.ready(D.round, true) then log("fishing: no GONE FISHIN' (" .. (c.enabled == false and "off" or "no native spawner") .. ")"); return false end
    s.state, s.at, s.haul, s.allyKg, s.allyHits, s.catches, s.empties, s.lastCatch = "intro", now, {}, 0, 0, 0, 0, now
    s.warned, s.said = {}, {}
    RUN.fished = D.round
    if SKY and SKY.arcSet then SKY.arcSet(D.round, "GONE FISHIN' starts") end
    pcall(SV_SetText, c.boat_name_key, c.boat_name)
    FISH.clearUnit(c.boat_unit, "SAL's boat")
    local b = c.boat_at or {}
    local br = FISH.spawn(c.boat_unit, b[1], b[2], c.boat_z, n(c.boat_yaw, 157))
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, c.boat_unit, br) end
    FISH.boat.round = nil
    FISH.sayAll("intro")
    s.introEnd = now + math.max(5, SUB.left(now))
    log(string.format("fishing: round %d, GONE FISHIN': SAL on the radio (%.0f s), his boat %s; the day-night arc from here",
        D.round, s.introEnd - now, br > 0 and "up" or ("NOT up (" .. tostring(SV_ERR and SV_ERR[br] or br) .. ")")))
    return true
end

local function startFishing(now, s)
    local c = cfg()
    s.state, s.t0 = "fishing", now
    s.endAt = now + n(c.time_s, 180)
    s.lastCatch = now
    spawnShoals(now, s)
    FISH.sayAll("start")
    hudCallout(tx().time_callout or "GONE FISHIN'", string.format(tx().time_callout_sub or "%s ON THE CLOCK", mmss(n(c.time_s, 180))))
    if s.total == 0 then
        log("fishing: no shoal came up: straight to the weigh-in")
        s.endAt = now
    end
end

local function shoalDown(now, s, sh)
    local c = cfg()
    sh.down = true
    if liveObj(sh.obj) then pcall(KILL.read, sh) end
    local okB, by = pcall(KILL.by, sh)
    by = okB and by or "you"
    local slot
    if by == "you" then slot = mySlot()
    elseif by == "wingmate" and type(sh.killer) == "number" then slot = sh.killer
    else slot = coopOn() and -1 or 0 end
    -- ((code review of 2026-11-07, finding 17) an ally's, a ship's, a defence's (not yours nor a teammate's): solo it's
    -- still credited to you (your haul, the card and the Big One's bonus as before), but SAL's "your friend" line goes by
    -- who it was, not by the slot: solo it never played)
    local byAlly = not (by == "you" or by == "wingmate")
    local catch = table.remove(s.deck, 1) or "none"
    local kg = FISH.kgOf(catch)
    if slot == -1 then s.allyKg, s.allyHits = s.allyKg + kg, s.allyHits + 1 else credit(haulOf(s, slot), catch, kg) end
    s.catches = s.catches + 1
    local at = sh.at or {}
    local sc = n(c.splash_scale, 1) * (catch == "bigone" and n(c.splash_big_x, 2) or 1)
    local splashed = at.X and FISH.splash({ X = at.X, Y = at.Y, Z = n(c.sea_z, 350) }, sc)
    local t = tx()
    local name = (t.names or {})[catch] or catch:upper()
    local text = kg > 0 and string.format(t.catch_kg or "+%d KG %s", kg, name) or name
    hudCallout(text, coopOn() and nameOfSlot(slot) or nil)
    if COOP and COOP.fishCatch then COOP.fishCatch(slot, catch, kg, at.X, at.Y) end
    -- SAL's word: the first catch; a gun kill of yours; an ally's (once); empties in a row; the catch itself (a small one
    -- only when the strip isn't backed up)
    local vals = { kg = kg, fish = name }
    if catch == "none" or catch == "junk" then s.empties = s.empties + 1 else s.empties = 0 end
    local g = nil
    if by == "you" and slot == mySlot() then
        local okG, gg = pcall(KILL.geom, sh, nil)
        if okG then g = gg end
    end
    local busy = SUB.left(now) > 6
    if s.catches == 1 then FISH.say("first")
    elseif catch == "bigone" then
        local who, line = FISH.line(t.bigone_first or "S|...", vals)
        SUB.say(who, line, 2.5)
        FISH.say("bigone", vals)
    elseif type(g) == "table" and g.wpn == "gun" and not s.said.gun then s.said.gun = true; FISH.say("gun")
    elseif byAlly and not s.said.ally then s.said.ally = true; FISH.say("ally")
    elseif s.empties >= math.max(2, math.floor(n(c.empties_line, 3))) then s.empties = 0; FISH.sayAll("empties")
    elseif BIG_FISH[catch] or not busy then FISH.say(catch, vals) end
    s.lastCatch, s.quietSaid = now, nil
    log(string.format("fishing: shoal %s #%d down at +%.0f s by %s%s: %s%s; %d of %d down, the deck %d left; %s haul %d kg%s",
        sh.unit, sh.i, now - (s.t0 or now), tostring(by), slot >= 0 and (" (player " .. (slot + 1) .. ")") or " (the allies')",
        catch, kg > 0 and (" " .. kg .. " kg") or "", s.catches, s.total, #s.deck, slot >= 0 and nameOfSlot(slot):lower() or "the allies'",
        slot >= 0 and haulOf(s, slot).kg or s.allyKg, splashed and "" or "; the splash NOT played"))
end

-- the shoals still up taken off (the joiners' copies first), their units off the spawner's list after
local function clearShoals(s, why)
    local c = cfg()
    local list = {}
    for _, u in ipairs(c.units or {}) do
        list[#list + 1] = u
        if COOP and COOP.host and COOP.host() and COOP.removeNow then pcall(COOP.removeNow, u) end
        local l = { at = os.clock() }
        for _, sh in ipairs(s.shoals or {}) do if sh.unit == u and not sh.down and liveObj(sh.obj) then l[#l + 1] = sh.obj; sh.down = true end end
        SPC.CLEAN_OBJ[u] = l
    end
    local nOff = SPC.cleanUp(list, why, true, D.now or 0)
    SPC.recycleLater(list, "GONE FISHIN' over", 3, true)
    return nOff
end
-- a unit of ours still on the spawner's list (an ally switched off before: SAL's boat, THE FESTIVAL's searchlights, when a
-- test key brings its round again) taken off it first, or its spawn would be refused ("its last flight is still up")
function FISH.clearUnit(unit, what)
    local n0 = type(SV_UnitAlive) == "function" and SV_UnitAlive(unit) or 0
    if n0 <= 0 or type(SV_Recycle) ~= "function" then return false end
    if crumb then crumb("fishing: SV_Recycle " .. tostring(unit) .. " before its spawn") end
    local okR, r = pcall(SV_Recycle, unit, 1)
    log(string.format("fishing: %s (%s) still on the spawner's list (%d up, switched off): SV_Recycle %s before its spawn", tostring(what),
        tostring(unit), n0, okR and tostring(r) or ("error " .. tostring(r))))
    return okR
end
-- SAL's boat switched off here (hidden, out of the way: an ally, never finished off)
function FISH.hide(o)
    for f, v in pairs({ bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }) do
        pcall(function() o[f] = v end)
    end
    pcall(function() o:SetActive(false, false, false) end)
    pcall(function() o:SetActorHiddenInGame(true) end)
    pcall(function() o:SetActorEnableCollision(false) end)
    pcall(function() o:SetActorTickEnabled(false) end)
end
function FISH.boatOff(why)
    local nOff = 0
    for _, o in ipairs(boatObjs()) do FISH.hide(o); nOff = nOff + 1 end
    if nOff > 0 then log(string.format("fishing: SAL's boat switched off here (%s)", tostring(why))) end
    return nOff
end

-- each player's line of the weigh-in, from the host's numbers (`res`: { [slot] = { kg, hits, empty, best, bestKg, bigone } }):
-- this game's own graded and paid here (its boat penalty off first); the card on screen. players: the room's.
function FISH.weighHere(res, players, team, allyKg, round, total)
    local c, t = cfg(), tx()
    local me = mySlot()
    local share = players > 1 and (allyKg or 0) / players or (allyKg or 0)
    local mine = res[me] or { kg = 0, hits = 0, empty = 0, bestKg = 0 }
    local boatKg = (FISH.boat.round == round) and FISH.boat.kg or 0
    local kg = math.max(0, math.floor((mine.kg or 0) + share + 0.5) - boatKg)
    local pay, grade, x = FISH.payFor(kg, players, round, mine.bigone)
    pay = math.max(0, math.min(pay, FISH.PAY_MAX))          -- ((code review of 2026-11-07, finding 9) one weigh-in's most)
    local why = string.format("GONE FISHIN' weigh-in (%s, %d kg%s)", grade, kg, boatKg > 0 and string.format(", -%d kg the boat", boatKg) or "")
    if pay > 0 then
        if coopOn() and COOP.payOwn then COOP.payOwn(pay, why) else addCredits(pay, why) end
        RUN.dirty = true
    end
    local names = t.names or {}
    local lines = {
        string.format(t.card_hits or "SHOALS HIT  %d / %d      EMPTY  %d", mine.hits or 0, total or 0, mine.empty or 0),
        (mine.best and mine.bestKg and mine.bestKg > 0) and string.format(t.card_best or "BEST FISH  %s %d KG", names[mine.best] or tostring(mine.best):upper(), mine.bestKg)
            or (t.card_best_none or "BEST FISH  NONE"),
        string.format(t.card_total or "TOTAL HAUL  %d KG      GRADE  %s", kg, grade),
    }
    if boatKg > 0 then lines[#lines + 1] = string.format(t.card_boat or "SAL'S BOAT  -%d KG", boatKg) end
    lines[#lines + 1] = string.format(t.card_pay or "PAYMENT  +%s Z", money(pay))
    if players > 1 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format(t.card_team or "TEAM HAUL  %s KG FROM %d PILOTS", money(team), players)
        local order = {}
        for s, r in pairs(res) do if s >= 0 then order[#order + 1] = { s = s, kg = math.floor((r.kg or 0) + share + 0.5) } end end
        table.sort(order, function(a, b) if a.kg ~= b.kg then return a.kg > b.kg end return a.s < b.s end)
        for _, e in ipairs(order) do
            local kgE = e.s == me and kg or e.kg
            lines[#lines + 1] = string.format(t.card_player or "%s  %d KG  %s", nameOfSlot(e.s), kgE, (FISH.grade(kgE, players)))
        end
    end
    SUB.card(t.card_title or "GONE FISHIN'  -  WEIGH-IN", lines, n(c.card_s, 14))
    if RUN then RUN.fishKg = players > 1 and team or kg end   -- (THE FESTIVAL's thanks name it: sv_festival.lua)
    log(string.format("fishing: the weigh-in here: %d kg (haul %d%s%s), grade %s, paid %d Z (x%.2f for round %d, %d player%s, the team %d kg)",
        kg, mine.kg or 0, share > 0 and string.format(" + %d the allies'", math.floor(share + 0.5)) or "",
        boatKg > 0 and string.format(" - %d the boat", boatKg) or "", grade, pay, x, round, players, players == 1 and "" or "s", team))
    return pay, grade, kg
end

local function weighStart(now, s, why)
    local c = cfg()
    s.state, s.weighAt = "weigh", now
    local nOff = clearShoals(s, "GONE FISHIN' over (" .. why .. ")")
    if why == "time" then FISH.say("time_up") else FISH.sayAll("cleared") end
    local players = 1
    if coopOn() and COOP.slots then players = math.max(1, #COOP.slots()) end
    local team = math.floor(teamKg(s) + 0.5)
    s.players, s.team = players, team
    FISH.sayAll("weigh", { kg = money(team) })
    s.cardAt = now + SUB.left(now)
    local g = FISH.grade(team, 1)
    FISH.say("grade_" .. g:lower(), { kg = money(team), grade = g })
    FISH.say("signoff")
    s.team, s.teamGrade = team, g
    log(string.format("fishing: round %d: the weigh-in (%s): %d of %d shoals down, %d left taken off; the team's %d kg (%s), the allies' %d kg",
        D.round, why == "time" and "time's up" or "every shoal down", s.catches, s.total or 0, nOff, team, g, s.allyKg or 0))
end
local function weighCard(now, s)
    s.carded = true
    local res = {}
    for slot, h in pairs(s.haul) do res[slot] = h end
    if coopOn() and COOP.slots then for _, sl in ipairs(COOP.slots()) do res[sl] = res[sl] or { kg = 0, hits = 0, empty = 0, bestKg = 0 } end end
    for slot, h in pairs(res) do
        if COOP and COOP.fishWeigh then COOP.fishWeigh(slot, h.kg or 0, h.hits or 0, h.empty or 0, h.best or "", h.bestKg or 0, h.bigone) end
    end
    if COOP and COOP.fishWeighEnd then COOP.fishWeighEnd(s.players, s.team, math.floor((s.allyKg or 0) + 0.5), D.round, s.total or 0) end
    FISH.weighHere(res, s.players or 1, s.team or 0, s.allyKg or 0, D.round, s.total or 0)
end

-- (SPC.kinds.fishing.tick: the host's or solo, every tick)
function FISH.roundTick(now, s)
    if levelGoing() then return end
    local c = cfg()
    if s.state == "intro" then
        if now >= (s.introEnd or now) then startFishing(now, s) end
    elseif s.state == "fishing" then
        if now >= (s.checkAt or 0) then
            s.checkAt = now + math.max(0.25, n(c.check_s, 0.5))
            local up = 0
            for _, sh in ipairs(s.shoals) do
                if not sh.down then
                    local live = liveObj(sh.obj)
                    local h = nil
                    if live then
                        h = FISH.hp(sh.obj)
                        pcall(function() local l = sh.obj:K2_GetActorLocation(); sh.at = { X = l.X, Y = l.Y, Z = l.Z } end)
                        pcall(KILL.read, sh)
                    end
                    if not live or (type(h) == "number" and h <= 0) then shoalDown(now, s, sh) else up = up + 1 end
                end
            end
            s.up = up
            boatTick(now, D.round, true)
            local left = s.endAt - now
            for i, w in ipairs(c.warn_s or {}) do
                if left <= n(w, 0) and not s.warned[i] and left > 0 then
                    s.warned[i] = true
                    local wl = FISH.pick((tx().warn or {})[i], "fish.warn" .. i)   -- (a line, or one of a list)
                    if type(wl) == "string" then local who, line = FISH.line(wl); SUB.say(who, line) end
                    log(string.format("fishing: %d s left (%d shoals up)", math.floor(n(w, 0)), up))
                end
            end
            if now - (s.lastCatch or now) >= n(c.quiet_s, 30) and not s.quietSaid then
                s.quietSaid = true
                FISH.say("quiet")
            end
            if playerOnAirfield() and not s.landedSaid then s.landedSaid = true; FISH.say("landed", nil, true) end
            if up == 0 and s.total > 0 then weighStart(now, s, "cleared")
            elseif now >= s.endAt then weighStart(now, s, "time") end
        end
    elseif s.state == "weigh" then
        if not s.carded and now >= (s.cardAt or now) then weighCard(now, s) end
        if s.carded and (not SUB.busy() or now - s.weighAt >= n(c.weigh_s, 26)) then
            s.state = "done"
            FISH.boatOff("GONE FISHIN' over")
            if LB and LB.special then pcall(LB.special, "fishing", (s.team or 0) >= n(c.grade_c, 150), now - (s.at or now)) end
            log(string.format("fishing: round %d over (%.0f s): the team's %d kg, %d catches", D.round, now - (s.at or now), s.team or 0, s.catches or 0))
        end
    end
    if COOP and COOP.specialRow and now >= (s.rowAt or 0) then
        s.rowAt = now + 1
        COOP.specialRow("fishing", s.state, math.floor(math.max(0, (s.endAt or now) - now) + 0.5), s.up or 0, math.floor(teamKg(s) + 0.5))
    end
end
function FISH.busy(s) return s.state ~= "done" end
-- (the round's end: a forced end too) nothing of it left
function FISH.roundOver(now, s)
    if s.state == "intro" or s.state == "fishing" then weighStart(now, s, "the round ended") end
    if s.state == "weigh" and not s.carded then weighCard(now, s) end
    if s.state ~= "done" then
        s.state = "done"
        FISH.boatOff("the round ended")
    end
end
-- the NEXT row (the host's or solo)
function FISH.row(s, t)
    local x = tx()
    if s.state == "intro" then return x.row_intro end
    if s.state == "weigh" then return x.row_weigh end
    if s.state ~= "fishing" then return nil end
    local mine = s.haul[mySlot()]
    local kg = math.max(0, (mine and mine.kg or 0) - ((FISH.boat.round == D.round) and FISH.boat.kg or 0))
    local row = string.format(x.row or "GONE FISHIN' %s  SHOALS %d  HAUL %d KG", mmss(s.endAt - (D.now or 0)), s.up or s.total or 0, kg)
    if coopOn() and x.row_team then row = row .. string.format(x.row_team, math.floor(teamKg(s) + 0.5)) end
    return row
end

-- A co-op joiner's: the host's messages (sv_coop.lua: guarded, then here), its own boat, the host's row
FISH.cl = { haul = {}, weigh = {}, rows = {}, round = nil }
function FISH.fromHost(k, f)
    local L = FISH.cl
    local function num(v, lo, hi) v = tonumber(v); if v and v == v and v >= lo and v <= hi then return v end return nil end
    if k == "fh" then
        local slot, catch, kg = num(f[2], -1, 23), tostring(f[3] or ""), num(f[4], 0, 5000)
        if not (slot and CATCH_OK[catch] and kg) then return end
        slot, kg = math.floor(slot), math.floor(kg)
        local h = L.haul[slot] or { kg = 0, hits = 0, empty = 0, junk = 0, bestKg = 0 }
        L.haul[slot] = h
        credit(h, catch, kg)
        local x, y = num(f[5], -1e8, 1e8), num(f[6], -1e8, 1e8)
        if x and y and (x ~= 0 or y ~= 0) then
            local c = cfg()
            pcall(FISH.splash, { X = x, Y = y, Z = n(c.sea_z, 350) }, n(c.splash_scale, 1) * (catch == "bigone" and n(c.splash_big_x, 2) or 1))
        end
    elseif k == "fsx" then
        local kind, state = tostring(f[2] or ""):match("^(%a+)$"), tostring(f[3] or ""):match("^(%a+)$")
        if not (kind and state and #kind <= 16 and #state <= 16) then return end
        L.rows[kind] = { state = state, a = num(f[4], 0, 1e6) or 0, b = num(f[5], 0, 1e6) or 0, c = num(f[6], 0, 1e7) or 0, at = os.clock() }
    elseif k == "fw" then
        -- ((code review of 2026-11-07, finding 9) the most a round can hold: every shoal (FISH.maxShoals) its heaviest
        -- catch (FISH.maxKg); a haul past it is the most, never more)
        local most = FISH.maxShoals() * FISH.maxKg()
        local slot = num(f[2], -1, 23)
        local kg, hits, empty, bestKg = num(f[3], 0, 1e5), num(f[4], 0, 1000), num(f[5], 0, 1000), num(f[7], 0, 5000)
        local best = tostring(f[6] or "")
        if not (slot and kg and hits and empty) then return end
        local sh = FISH.maxShoals()
        L.weigh[math.floor(slot)] = { kg = math.min(kg, most), hits = math.min(hits, sh), empty = math.min(empty, sh),
                                      best = CATCH_OK[best] and best or nil, bestKg = math.min(bestKg or 0, FISH.maxKg()),
                                      bigone = f[8] == "1" }
    elseif k == "fwe" then
        local players, team, ally, round, total = num(f[2], 1, 24), num(f[3], 0, 1e6), num(f[4], 0, 1e6), num(f[5], 0, 1e5), num(f[6], 0, 1000)
        -- ((code review of 2026-11-07, finding 8) once a round of this run: a run started over here (the host's restart:
        -- newRunHere's new RUN) pays its own round N again, which the old round number alone had refused)
        if not (players and team and round) or (L.paidRound == round and L.paidRun == RUN) then return end
        L.paidRound, L.paidRun = round, RUN
        local sh = FISH.maxShoals()
        local most = sh * FISH.maxKg()
        round = math.min(math.floor(round), 1000)                -- (finding 9: the pay's round factor, at most round 1000's)
        total = math.min(math.floor(total or 0), sh)
        team, ally = math.min(team, most), math.min(ally or 0, most)
        local okW, errW = pcall(FISH.weighHere, L.weigh, math.floor(players), team, ally, round, total)
        if not okW then log("fishing: the host's weigh-in not read here: " .. tostring(errW)) end
        L.weigh, L.haul = {}, {}
    end
end
-- (every tick of a joiner's run, sv_main.lua probeTickB) the host's GONE FISHIN' here: this game's boat watched, your
-- landing nudge, a new round's slate clean; its end: the boat's copy switched off here
function FISH.clientTick(now)
    if not (COOP and COOP.client and COOP.client() and D) then return end
    local hs, L = D.hostSpecial, FISH.cl
    local on = hs and hs.kind == "fishing" and hs.state ~= "done"
    if on then
        if L.round ~= D.round then L.round, L.landed, L.haul, L.weigh, L.sphered = D.round, nil, {}, {}, {} end
        if now >= (L.checkAt or 0) then
            L.checkAt = now + 0.5
            boatTick(now, D.round, false)
            -- this game's copies of the shoals get their hit spheres too: your weapons hit your copies (their hits go to the host)
            local c = cfg()
            if c.sphere ~= false and hs.state == "fishing" then
                L.sphered = L.sphered or {}
                for _, u in ipairs(c.units or {}) do
                    for _, o in ipairs((SPC and SPC.CLEAN_OBJ and SPC.CLEAN_OBJ[u]) or {}) do
                        local a = liveObj(o) and addrOf(o)
                        if a and not L.sphered[a] then
                            L.sphered[a] = true
                            local comp, what = FISH.addSphere(o, n(c.sphere_m, 8), c.sphere_profile or "EnemyPawn")
                            if not comp then logOnce("fish copy sphere", "fishing: a shoal's copy here got no sphere: " .. tostring(what)) end
                        end
                    end
                end
            end
            if hs.state == "fishing" and playerOnAirfield() and not L.landed then L.landed = true; FISH.say("landed", nil, true) end
        end
        L.on = true
    elseif L.on then
        L.on = false
        FISH.boatOff("the host's GONE FISHIN' is over")
    end
end
-- (a joiner's NEXT row) the host's GONE FISHIN', your own haul in it
function FISH.clientRow(t)
    if not (COOP and COOP.client and COOP.client() and D) then return nil end
    local hs, r = D.hostSpecial, FISH.cl.rows.fishing
    if not (hs and hs.kind == "fishing" and hs.state ~= "done" and r and os.clock() - r.at < 5) then return nil end
    local x = tx()
    if r.state == "intro" then return x.row_intro end
    if r.state == "weigh" then return x.row_weigh end
    if r.state ~= "fishing" then return nil end
    local mine = FISH.cl.haul[mySlot()]
    local kg = math.max(0, (mine and mine.kg or 0) - ((FISH.boat.round == D.round) and FISH.boat.kg or 0))
    local secs = math.max(0, r.a - (os.clock() - r.at))
    return string.format(x.row or "GONE FISHIN' %s  SHOALS %d  HAUL %d KG", mmss(secs), r.b, kg)
        .. (x.row_team and string.format(x.row_team, math.floor(r.c)) or "")
end
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the fishing round"] = function() FISH.boat = { kg = 0, hits = 0 }; FISH.cl = { haul = {}, weigh = {}, rows = {} } end
end
end

-- TEST ONLY BEGIN
-- Ctrl+F10 in a run (the host's or solo): the shoals and SAL's boat (tools/re/FISHING.md 7, tests 1-2). Each press:
--   1 SV_Unit_FishA's 8 shoals round SAL's boat (SV_Spawn(unit, x, y, shoal_z, a random yaw)) and the boat at boat_at, a hit
--     sphere on each shoal (`with sphere`, the first time), the names set; then once a second a line with each shoal's
--     health (HealthInternal / MaxHealth) and who its DamageHistoryMap names, and the boat's health and MinHealth (the
--     field written back up to boat_min_health when it's lower: never SetMinHealth). A shoal's death: who killed it
--     (KILL.read / KILL.by; co-op: the host's attribution) and the sea splash where it was.
--   2 the next spawn without the sphere (or with it again): `fishing test: next spawn WITHOUT the sphere`
--   3 everything taken off (the joiners' copies first, COOP.removeNow; SPC.cleanUp; SV_Recycle 2 s on), as test_s after
--     the spawn does by itself. The next press spawns again.
do
local T = { state = "idle", sphere = true, run = nil, shoals = {}, boat = nil, nextLog = 0, kills = 0 }
FISH.test = T
local function c() return CFG.specials.fishing end
local function units() return { c().units[1], c().boat_unit } end
local function reset() T.state, T.shoals, T.boat, T.run, T.removeAt, T.recycleAt, T.toggled = "idle", {}, nil, nil, nil, nil, nil end
local findNear, SHOAL_CLASS, BOAT_CLASS = FISH.findNear, FISH.SHOAL_CLASS, FISH.BOAT_CLASS
local function at(o)
    local ok, v = pcall(function() local l = o:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end)
    return ok and v or nil
end
local function spawnAll(now)
    local cf = c()
    if not FISH.rowsReady then log("fishing test: the shoal's rows aren't in (FISH.setup at the main menu): spawning anyway") end
    if type(SV_SetText) == "function" then
        pcall(SV_SetText, cf.shoal_name_key, cf.shoal_name); pcall(SV_SetText, cf.boat_name_key, cf.boat_name)
        if cf.shoal_sub_key then pcall(SV_SetText, cf.shoal_sub_key, cf.shoal_sub or "") end
    end
    FISH.splashAsset()                                    -- (loaded now, not at the first kill)
    local unit, g = cf.units[1], FISH.grounds()[1]
    local yaw = math.random() * 360
    local r = FISH.spawn(unit, g[1], g[2], cf.shoal_z, yaw)
    local objs = FISH.objs(unit)
    local seen = #objs .. " objects seen as they were made"
    if #objs == 0 and r > 0 then
        objs = findNear(SHOAL_CLASS, g[1], g[2], 90000)
        FISH.actors[unit] = { open = false, table.unpack(objs) }
        seen = "none seen as they were made; " .. #objs .. " " .. SHOAL_CLASS .. " found near it"
    end
    log(string.format("fishing test: %s round SAL's boat (%d, %d), %d cm up, yaw %.0f: %s; %s", unit, g[1], g[2], cf.shoal_z,
        yaw, r > 0 and (r .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[r] or r) .. ")"), seen))
    T.shoals = {}
    for i, o in ipairs(objs) do
        local s = { obj = o, addr = addrOf(o), i = i, name = (nameOf(o):match("([^%.:]+)$")) or "?" }
        T.shoals[#T.shoals + 1] = s
        local h, mx, mn = FISH.hp(o)
        local where = at(o)
        local sph = "no sphere (this spawn's without)"
        if T.sphere then
            local comp, what = FISH.addSphere(o, cf.sphere_m, cf.sphere_profile)
            s.sphere = comp ~= nil
            sph = comp and ("sphere " .. what) or ("sphere NOT added: " .. tostring(what))
        end
        local ov = "none"
        pcall(function()
            local oc = o.OverlapCollision
            if oc ~= nil and valid(oc) then
                local okR, rr = pcall(function() return oc:GetUnscaledSphereRadius() end)
                local okP, pp = pcall(function() return oc:GetCollisionProfileName():ToString() end)
                ov = string.format("radius %s m, profile %s", okR and string.format("%.1f", (rr or 0) / 100) or "?", okP and tostring(pp) or "?")
            end
        end)
        log(string.format("fishing test: shoal %d %s at %s: health %s, MaxHealth %s, MinHealth %s; %s; its OverlapCollision %s", i, s.name,
            where and string.format("(%.0f, %.0f, %.0f)", where.X, where.Y, where.Z) or "?", tostring(h), tostring(mx), tostring(mn), sph, ov))
    end
    local b = cf.boat_at
    local br = FISH.spawn(cf.boat_unit, b[1], b[2], cf.boat_z, math.random() * 360)
    local bo = FISH.objs(cf.boat_unit)[1]
    if not bo and br > 0 then
        bo = findNear(BOAT_CLASS, b[1], b[2])[1]
        if bo then FISH.actors[cf.boat_unit] = { open = false, bo } end
        log("fishing test: the boat wasn't seen as it was made; " .. BOAT_CLASS .. " near its spot: " .. (bo and "found" or "NOT found"))
    end
    T.boat = bo and { obj = bo, addr = addrOf(bo), name = (nameOf(bo):match("([^%.:]+)$")) or "?", writes = 0 } or nil
    local bh, bmx, bmn = nil, nil, nil
    if bo then bh, bmx, bmn = FISH.hp(bo) end
    local flags = {}
    if bo then
        for _, f in ipairs({ "bIsInvincible", "bIsInvincibleFromAI", "bIsInvincibleFromWingman", "bShowHUDBox" }) do
            local okF, x = pcall(function() return bo[f] end)
            flags[#flags + 1] = f .. " " .. (okF and tostring(x) or "?")
        end
    end
    log(string.format("fishing test: SAL's boat %s at (%d, %d), %d cm up: %s%s", cf.boat_unit, b[1], b[2], cf.boat_z,
        br > 0 and (br .. " up") or ("not spawned (" .. tostring(SV_ERR and SV_ERR[br] or br) .. ")"),
        bo and string.format("; %s right after its spawn: health %s, MaxHealth %s, MinHealth %s; %s", T.boat.name, tostring(bh),
            tostring(bmx), tostring(bmn), table.concat(flags, ", ")) or "; its actor NOT seen"))
    T.state, T.run, T.at, T.nextLog, T.kills = "up", D, now, now + 1, 0
    T.removeAt = now + (tonumber(cf.test_s) or 300)
    hudCallout("TEST: GONE FISHIN'", string.format("%d SHOALS %s, BOAT %s", #T.shoals, T.sphere and "WITH SPHERES" or "NO SPHERES",
        bo and "UP" or "NOT UP"))
end
local function removeAll(now, why)
    T.state = "removing"
    local list, gone = units(), {}
    for _, s in ipairs(T.shoals) do if s.down and s.addr then gone[s.addr] = true end end
    for _, u in ipairs(list) do
        if COOP and COOP.host and COOP.host() and COOP.removeNow then pcall(COOP.removeNow, u) end   -- (the joiners' copies first)
        local l = { at = os.clock() }
        for _, o in ipairs(FISH.objs(u)) do if not gone[addrOf(o)] then l[#l + 1] = o end end
        SPC.CLEAN_OBJ[u] = l                              -- (sv_rounds.lua SPC.cleanUp's record: finished off, no pay)
    end
    local n = SPC.cleanUp(list, "the fishing test over (" .. why .. ")", true, D and D.now or 0)
    log(string.format("fishing test: taken off (%s): %d objects finished off or switched off; %d shoals were shot down in it", why, n, T.kills))
    T.recycleAt = now + 2
    hudCallout("TEST: FISHING OFF", why:upper())
end
local function recycle()
    local out = {}
    for _, u in ipairs(units()) do
        local n0 = type(SV_UnitAlive) == "function" and SV_UnitAlive(u) or -5
        local okR, r = false, "no SV_Recycle"
        if type(SV_Recycle) == "function" then
            crumb("fishing test: SV_Recycle " .. u)
            okR, r = pcall(SV_Recycle, u, 1)
        end
        out[#out + 1] = string.format("%s %d alive -> SV_Recycle %s -> %s alive", u, n0, okR and tostring(r) or ("error " .. tostring(r)),
            tostring(type(SV_UnitAlive) == "function" and SV_UnitAlive(u) or "?"))
    end
    log("fishing test: off the spawner's list: " .. table.concat(out, "; "))
    FISH.actors[c().units[1]], FISH.actors[c().boat_unit] = nil, nil
    reset()
end
local function shoalDown(s, now)
    s.down = true
    T.kills = T.kills + 1
    if liveObj(s.obj) then pcall(KILL.read, s) end       -- (the last hits, while it's still there: never on a freed one)
    local okB, by = pcall(KILL.by, s)
    local d = s.dmg or {}
    local where = s.at
    local splash = where and FISH.splash({ X = where.X, Y = where.Y, Z = c().sea_z })
    log(string.format("fishing test: shoal %d %s down at +%.0f s: by %s%s (damage: you %.0f, wingmate %.0f, allies %.0f, other %.0f; "
        .. "its map named %s); the splash %s", s.i, s.name, now - (T.at or now), okB and tostring(by) or ("? " .. tostring(by)),
        type(s.killer) == "number" and (" (player " .. (s.killer + 1) .. ")") or "", d.you or 0, d.wingmate or 0, d.allies or 0,
        d.other or 0, tostring(s.who or "-"), splash and "played" or "NOT played"))
end
local function tick(now)
    if T.state == "idle" then return end
    if T.run ~= D or (levelTorn and levelTorn()) then reset(); return end
    if T.state == "removing" then
        if T.recycleAt and now >= T.recycleAt then recycle() end
        return
    end
    if now >= (T.removeAt or math.huge) then removeAll(now, string.format("%d s after the spawn", math.floor(c().test_s or 300))); return end
    if now < T.nextLog then return end
    T.nextLog = now + 1
    local parts = {}
    for _, s in ipairs(T.shoals) do
        if not s.down then
            local up = liveObj(s.obj)
            local h, mx = nil, nil
            if up then
                h, mx = FISH.hp(s.obj)
                s.at = at(s.obj) or s.at
                s.who = FISH.who(s.obj)
                pcall(KILL.read, s)
            end
            if not up or (type(h) == "number" and h <= 0) then
                shoalDown(s, now)
                parts[#parts + 1] = string.format("%d DOWN", s.i)
            else
                parts[#parts + 1] = string.format("%d %s/%s %s", s.i, tostring(h), tostring(mx), s.who or "-")
            end
        end
    end
    local b = T.boat
    local bt = "boat not up"
    if b and liveObj(b.obj) then
        local h, mx, mn = FISH.hp(b.obj)
        local want = tonumber(c().boat_min_health) or 1
        if type(mn) == "number" and mn < want and pcall(function() b.obj.MinHealth = want end) then
            b.writes = b.writes + 1
            if b.writes == 1 or b.writes % 30 == 0 then
                log(string.format("fishing test: the boat's MinHealth read %s: the field written back to %s (%d times)", tostring(mn), tostring(want), b.writes))
            end
        end
        bt = string.format("boat %s/%s min %s %s", tostring(h), tostring(mx), tostring(mn), FISH.who(b.obj))
    elseif b then
        bt = "boat GONE"
    end
    log(string.format("fishing test: +%.0f s: shoals %s; %s", now - (T.at or now), #parts > 0 and table.concat(parts, "; ") or "all down", bt))
end
testKey("F10", "sv_fishing.lua's fishing test", function()
    local now = os.clock()
    if not (D and D.now) or not nativeReady() then log("fishing test: Ctrl+F10 outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("fishing test: Ctrl+F10: the host spawns the shoals (you're a joiner)"); return end
    if T.run ~= D then reset() end
    if T.state == "idle" then
        spawnAll(now)
    elseif T.state == "up" and not T.toggled then
        T.sphere, T.toggled = not T.sphere, true
        log("fishing test: next spawn " .. (T.sphere and "WITH" or "WITHOUT") .. " the sphere (the shoals up now keep theirs)")
        hudCallout("TEST: NEXT SPAWN", T.sphere and "WITH SPHERES" or "WITHOUT SPHERES")
    elseif T.state == "up" then
        T.toggled = nil
        removeAll(now, "Ctrl+F10")
    else
        log("fishing test: still being taken off: press again in a moment")
    end
end)
TEST_TICKS[#TEST_TICKS + 1] = { name = "fishing test", fn = tick }
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["the fishing test"] = function() reset(); T.toggled = nil end end
end
-- TEST ONLY END

-- TEST ONLY BEGIN
-- Ctrl+HOME in a run (the host's or solo): GONE FISHIN' now (in the break: it starts in 3 s; in a fight: the next round),
-- whatever its once a run, its from_round or the dice; the arc starts again from it (`test: Ctrl+HOME, ...`)
testKey("HOME", "sv_fishing.lua's GONE FISHIN' now", function()
    if not (D and D.now) or not nativeReady() then log("test: Ctrl+HOME outside a Survival run"); return end
    if COOP and COOP.client and COOP.client() then log("test: Ctrl+HOME: the host starts the rounds (you're a joiner)"); return end
    D.forceSpecial = "fishing"
    local soon = D.state == "wait"
    if soon then D.at, D.announced = math.min(D.at or D.now, D.now + 3), false end
    hudCallout("TEST: GONE FISHIN'", soon and "STARTING NOW" or "NEXT ROUND")
    log(string.format("test: Ctrl+HOME, round %d is GONE FISHIN' (%s)", D.round + 1, soon and "starting in 3 s" or "after this round"))
end)
-- TEST ONLY END
