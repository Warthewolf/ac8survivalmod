-- sv_leaderboard.lua: the run's stats, its summary and the leaderboard (Online edition only).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- leaderboard
-- CFG.leaderboard; leaderboard/src/index.js is the other end (same score, same checks). RUN.stats: { started, air,
-- ground, aces (ace squadron aircraft down), allies (allies bought), af_down (times the airfield went down), captured
-- (times it was captured), specials = { { kind, round, seconds, won } } }. LB.show: the finished run on screen.
-- ONLINE ONLY BEGIN
-- LB.queue: the runs not yet answered for good (pending_runs.txt); LB.jobs: the sends in flight; LB.kept ((0.73.80)):
-- the runs refused only as an unknown build, sent again at later game starts (refused_runs.txt, keepRefused below).
-- ONLINE ONLY END
do
local function stats()
    RUN.stats = RUN.stats or { started = os.time(), air = 0, ground = 0, aces = 0, allies = 0, af_down = 0, captured = 0,
                               specials = {} }
    return RUN.stats
end
-- slot: the co-op player it's theirs (a revive given: sv_down.lua hostRevive), for a co-op run's squad (LB.coopTally)
function LB.stat(what, n, slot)
    if D then local st = stats(); st[what] = (st[what] or 0) + (n or 1) end
    if slot ~= nil and LB.coopTally then pcall(LB.coopTally, slot, what, n or 1) end
end
function LB.special(kind, won, seconds)
    if not D then return end
    local sp = stats().specials
    if #sp < 200 then sp[#sp + 1] = { kind = kind, round = D.round, seconds = math.min(3600, math.max(5, math.floor(seconds + 0.5))), won = won } end
end

-- leaderboard/src/index.js score(): 1000 a round, 100 an aircraft, 50 a ground target, 3000 a special beaten, x the difficulty
local DIFF_X = { casual = 0.75, standard = 1.0, ace = 1.5 }
local function score(r)
    local won = 0
    for _, sp in ipairs(r.specials) do if sp.won then won = won + 1 end end
    return math.floor((r.round * 1000 + r.kills.air * 100 + r.kills.ground * 50 + won * 3000) * (DIFF_X[r.difficulty] or 1)), won
end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
local function jstr(v) return '"' .. tostring(v):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
local function json(r)
    local sp = {}
    for _, x in ipairs(r.specials) do
        sp[#sp + 1] = string.format('{"kind":%s,"round":%d,"seconds":%d,"won":%s}', jstr(x.kind), x.round, x.seconds, tostring(x.won))
    end
    -- (0.72.x: what was found edited, always [] in a run that's sent, and the build hash the game started with; the
    -- Worker refuses a run that says it was edited or that comes from other files than it's sent from)
    local ed = {}
    for i, k in ipairs(r.edited or {}) do if i <= 8 then ed[#ed + 1] = jstr(tostring(k):sub(1, 80)) end end
    -- ((0.73.77) a co-op run's squad, LB.coopRecord: "coop":{"players":N,"squad":[{"pilot","aircraft","air","ground",
    -- "revives","host"}]}, the host first; a solo run has none)
    local co = ""
    if type(r.coop) == "table" and type(r.coop.squad) == "table" and #r.coop.squad >= 2 then
        local sq = {}
        for _, p in ipairs(r.coop.squad) do
            local ac = type(p.aircraft) == "string" and #p.aircraft <= 12 and p.aircraft:match("^[a-z0-9][a-z0-9]+$")
            sq[#sq + 1] = string.format('{"pilot":%s%s,"air":%d,"ground":%d,"revives":%d%s}', jstr(p.pilot),
                ac and (',"aircraft":' .. jstr(ac)) or "", math.floor(p.air), math.floor(p.ground), math.floor(p.revives),
                p.host and ',"host":true' or "")
        end
        co = string.format(',"coop":{"players":%d,"squad":[%s]}', #sq, table.concat(sq, ","))
    end
    return string.format('{"v":1,"run_id":%s,"pilot":%s,"difficulty":%s,"round":%d,"mod":%s,"kills":{"air":%d,"ground":%d},'
        .. '"zollars":{"earned":%d,"spent":%d},"time_s":%d,"ended":%s,"how":%s,"aces":%d,"allies":%d,"af_down":%d,'
        .. '"captured":%d,"specials":[%s],"edited":[%s]%s%s%s%s}', jstr(r.run_id), jstr(r.pilot),
        jstr(r.difficulty), r.round, jstr(r.mod), r.kills.air, r.kills.ground, r.zollars.earned, r.zollars.spent, r.time_s,
        jstr(r.ended), jstr(r.how), r.aces, r.allies, r.af_down, r.captured, table.concat(sp, ","), table.concat(ed, ","),
        (r.aircraft and r.aircraft:match("^[a-z0-9][a-z0-9]+$")) and (',"aircraft":' .. jstr(r.aircraft)) or "",
        (r.tier and r.tier:match("^%a+$")) and (',"tier":' .. jstr(r.tier)) or "",
        (type(r.build) == "string" and r.build:match("^%x+$") and #r.build == 64) and (',"build":' .. jstr(r.build:lower())) or "",
        co)
end

-- An edited run isn't ranked (user, 2026-10-30: "we need a way that the Leaderboards can detect if a run has been edited
-- from the stock run", "An edited run shouldn't count toward the leaderboard"). LB.edited(coopRun) -> the list of what's
-- edited (empty: a stock run), and the same with values for the log. Edited:
--   - a gameplay setting that differs from the shipped one: CFG against CFG_DEFAULTS (survival.ini and
--     survival_config.lua both), by sv_coop.lua's settings diff (COOP.cfgDiff), but for
--       sections that are each player's own or only on screen / in the log: hud, sound, music, log, ai_watch, stats,
--         leaderboard (your pilot name), menu, setup (the menu's run setups: SETUP.ranked checks SP ONLINE's), coop (the
--         link, your name, your keys and camera);
--       in any section: texts (a "text" or "sounds" table, labels, display names, ace callsigns: translations), key
--         bindings (key, keys, ctrl, *_key) and camera settings;
--     in a co-op run (sent only with [coop] leaderboard = true) the room's rules count too: the host's setup and
--     [coop] aircraft_per_player, max_aircraft, max_up, split_share and the revives (but for each player's key and camera).
--     Counted although co-op leaves them to each player: tells (their lead times hold the enemies' moves), profile and
--     flares (the learning layer), probe (it flies its own enemies);
--   - a Scripts/survival_config.lua (CFG_USER_FILE, sv_config.lua: it can change anything);
--   - a test key pressed in the run (or at the main menu before it: a dev build's; releases have none);
--   - (a head start, start_round, and SP ONLINE's custom rules are refused before this: LB.send, SETUP.ranked)
-- The build itself (an edited script or container) is the runtime's build hash's: the Worker refuses an unknown build.
local EDIT_FREE = { hud = true, sound = true, music = true, log = true, ai_watch = true, stats = true, leaderboard = true,
                    menu = true, setup = true, coop = true,
                    recycle = true }   -- ((0.73.77) each game's crash workaround: when a recycled flight's actor goes)
local EDIT_FREE_PART = { text = true, sounds = true, camera = true }
local EDIT_FREE_LEAF = { key = true, keys = true, ctrl = true, label = true, what = true, name = true, squadron = true,
                         title = true, help = true }
local EDIT_COOP = { aircraft_per_player = true, max_aircraft = true, max_up = true, split_share = true, revive = true }
local function editFree(p, v, coopRun)
    local top = p[1]
    if top == "coop" then
        if not (coopRun and EDIT_COOP[p[2]]) then return true end
    elseif top == "setup" then
        if not (coopRun and p[2] == "host") then return true end
    elseif EDIT_FREE[top] then return true end
    for j = 2, #p do if EDIT_FREE_PART[p[j]] then return true end end
    local leaf = tostring(p[#p])
    if EDIT_FREE_LEAF[leaf] or leaf:match("_key$") or leaf:match("sound") then return true end
    if top == "aces" and #p == 3 and p[2] ~= "flight" and type(v) == "string" then return true end   -- (callsigns)
    return false
end
local function shown(v)
    if type(v) == "table" then return "{" .. (#v > 0 and (#v .. " items") or "...") .. "}" end
    if type(v) == "string" then return '"' .. v:sub(1, 40) .. '"' end
    return tostring(v)
end
function LB.edited(coopRun)
    local out, detail = {}, {}
    if CFG_USER_FILE then out[#out + 1] = CFG_USER_FILE; detail[#detail + 1] = CFG_USER_FILE .. " is in Scripts" end
    local tk = (D and RUN and RUN.stats and RUN.stats.test_key) or LB.menuTestKey
    if tk then out[#out + 1] = "test key " .. tk; detail[#detail + 1] = "test key " .. tk .. " pressed" end
    if type(CFG_DEFAULTS) ~= "table" or not (COOP and COOP.cfgDiff) then return out, detail end
    local d = {}
    COOP.cfgDiff(CFG, CFG_DEFAULTS, {}, d)
    local keys = {}
    for _, e in ipairs(d) do
        if not editFree(e[1], e[2], coopRun) then
            local q = {}
            local def = CFG_DEFAULTS
            for j = 1, #e[1] do
                q[j] = tostring(e[1][j])
                if type(def) == "table" then def = def[e[1][j]] else def = nil end
            end
            keys[#keys + 1] = { table.concat(q, "."), e[2], def }
        end
    end
    table.sort(keys, function(a, b) return a[1] < b[1] end)
    for _, k in ipairs(keys) do
        out[#out + 1] = k[1]
        detail[#detail + 1] = k[1] .. " = " .. shown(k[2]) .. " (shipped " .. shown(k[3]) .. ")"
    end
    return out, detail
end

-- A test key (the dev keys bound in sv_main.lua: a dev build's, none in a release) pressed: the run it's pressed in isn't
-- ranked, nor the next one when it's pressed at the main menu (Ctrl+F8 opens the level from there)
function LB.testKey(key)
    local name = tostring(key)
    if type(Key) == "table" then for n, v in pairs(Key) do if v == key then name = tostring(n); break end end end
    name = "Ctrl+" .. name
    if D and RUN and RUN.stats then RUN.stats.test_key = RUN.stats.test_key or name else LB.menuTestKey = LB.menuTestKey or name end
    log("leaderboard: test key " .. name .. " pressed: " .. (D and "this run" or "the next run") .. " won't be ranked")
end

local function configDir() return SCRIPT_DIR .. "..\\config\\" end
-- The file holds only the runs still waiting for an answer: once the last one is in (taken or refused), the file is
-- deleted, so no run stays on the player's PC after it's uploaded (user, 2026-10-24: "once its been uploaded, it self
-- deletes"). A run is written before it's sent so a game closed mid-send doesn't lose it.
local function saveQueue()
    while #LB.queue > 50 do table.remove(LB.queue, 1) end
    local path = configDir() .. "pending_runs.txt"
    if #LB.queue == 0 then os.remove(path); return end
    local f = io.open(path, "w")
    if not f then return end
    for _, body in ipairs(LB.queue) do f:write(body, "\n") end
    f:close()
end

-- (0.73.80, the 31-round co-op test of 2026-11-04: errors0) A run the server refused ONLY as an unknown build (its
-- build hash not registered yet on /admin: the host's clean 31-round run went 422 "edited or unknown build" and was
-- deleted with pending_runs.txt) is kept in refused_runs.txt instead, KEEP_MAX at most (the oldest dropped), one line a
-- run: "<first refused, os.time()>\t<times resent>\t<body>". Each one is sent again once a game start, from the main
-- menu (never in a run), KEEP_FIRST_S after the first look and KEEP_GAP_S apart (LB.queueTick -> keptTick), for
-- KEEP_DAYS from its first refusal: once its build is registered the Worker takes it (its run_id de-duplicates). It
-- comes off the file once the server takes it, refuses it for any other reason, or it's KEEP_DAYS old; the file goes
-- when it's empty (as pending_runs.txt). A run edited by the player (LB.edited) is never sent, so never kept.
local KEEP_FILE, KEEP_MAX, KEEP_DAYS, KEEP_FIRST_S, KEEP_GAP_S = "refused_runs.txt", 20, 14, 30, 60
local function unknownBuild(st, err) return st == 422 and type(err) == "string" and err:find("unknown build", 1, true) ~= nil end
local function runTag(body)                       -- "run 1a2b3c4d, round 31, pilot Naish" (the body's first pilot: the run's)
    return string.format("run %s, round %s, pilot %s", tostring(body:match('"run_id":"(%x+)"') or "?"):sub(1, 8),
        body:match('"round":(%d+)') or "?", body:match('"pilot":"([^"]*)"') or "?")
end
local function daysAgo(at) return math.max(0, math.floor((os.time() - at) / 86400)) end
local function saveKept()
    while #LB.kept > KEEP_MAX do
        local k = table.remove(LB.kept, 1)
        log(string.format("leaderboard: refused_runs.txt keeps %d runs at most: the oldest (%s, refused as an unknown build %d days ago) dropped",
            KEEP_MAX, runTag(k.body), daysAgo(k.at)))
    end
    local path = configDir() .. KEEP_FILE
    if #LB.kept == 0 then os.remove(path); return end
    local f = io.open(path, "w")
    if not f then return end
    for _, k in ipairs(LB.kept) do f:write(string.format("%d\t%d\t%s\n", k.at, k.tries, k.body)) end
    f:close()
end
-- (once a game start) the kept runs, each due to be sent again this start; those KEEP_DAYS old dropped
local function loadKept()
    if LB.kept then return LB.kept end
    LB.kept = {}
    local f = io.open(configDir() .. KEEP_FILE, "r")
    if not f then return LB.kept end
    local now, old, n = os.time(), 0, 0
    for line in f:lines() do
        local at, tries, body = line:match("^(%d+)\t(%d+)\t({.*})%s*$")
        at, tries = tonumber(at), tonumber(tries)
        if at and tries and body then
            n = n + 1
            at = math.min(at, now)                        -- (a clock set back: counted from now)
            if now - at > KEEP_DAYS * 86400 then
                old = old + 1
                log(string.format("leaderboard: a run refused as an unknown build %d days ago (%s) dropped: kept %d days at most",
                    daysAgo(at), runTag(body), KEEP_DAYS))
            else
                LB.kept[#LB.kept + 1] = { at = at, tries = tries, body = body, due = true }
            end
        end
    end
    f:close()
    table.sort(LB.kept, function(a, b) return a.at < b.at end)
    if old > 0 or #LB.kept ~= n or #LB.kept > KEEP_MAX then saveKept() end
    if #LB.kept > 0 then
        log(string.format("leaderboard: %d run(s) refused as an unknown build kept to resend from the main menu (the oldest refused %d days ago; "
            .. "each kept %d days)", #LB.kept, daysAgo(LB.kept[1].at), KEEP_DAYS))
    end
    return LB.kept
end
-- (LB.poll) a run just refused as an unknown build: kept (once; a run already kept keeps its first date)
local function keepRefused(body)
    if not body:find('"edited":[]', 1, true) then return end         -- (an edited run: never sent, never kept)
    local kept, id = loadKept(), body:match('"run_id":"(%x+)"')
    for _, k in ipairs(kept) do
        if k.body == body or (id and k.body:match('"run_id":"(%x+)"') == id) then
            log(string.format("leaderboard: a run refused as an unknown build is kept already (%s, first refused %d days ago)",
                runTag(body), daysAgo(k.at)))
            return
        end
    end
    kept[#kept + 1] = { at = os.time(), tries = 0, body = body, due = false }
    saveKept()
    log(string.format("leaderboard: a run refused as an unknown build kept to resend at later game starts, from the main menu, for %d days "
        .. "(%s; %d kept in %s; register this build's hash on /admin and it's taken)", KEEP_DAYS, runTag(body), #LB.kept, KEEP_FILE))
end
-- ONLINE ONLY END
local function money(n) return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local function clockText(t) return string.format("%d:%02d:%02d", t // 3600, t // 60 % 60, t % 60) end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
-- The name the run goes under: [leaderboard] pilot, else the Steam name; only what the leaderboard takes, or "".
function LB.pilot()
    local name = tostring(CFG.leaderboard.pilot or "")
    if name:gsub("%s", "") == "" then
        if LB.steam == nil then
            LB.steam = type(SV_SteamName) == "function" and tostring(SV_SteamName() or "") or ""
            log("leaderboard: Steam name " .. (LB.steam ~= "" and ("'" .. LB.steam .. "'") or "not available"))
        end
        name = LB.steam
    end
    name = name:gsub("[^%w _%.%-]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 24)
    if name == "" then                                 -- (a Steam name of other letters only): one made for this install
        if not LB.anon then
            local f = io.open(configDir() .. "pilot_id.txt", "r")
            LB.anon = f and (f:read("l") or ""):match("^Pilot%-%x+$") or nil
            if f then f:close() end
            if not LB.anon then
                LB.anon = string.format("Pilot-%06x", math.random(0, 0xFFFFFF))
                local w = io.open(configDir() .. "pilot_id.txt", "w")
                if w then w:write(LB.anon, "\n"); w:close() end
            end
            log("leaderboard: no usable name; submitting as " .. LB.anon)
        end
        name = LB.anon
    end
    return name
end
-- ONLINE ONLY END
--OFFLINE: -- The name on the summary: [leaderboard] pilot.
--OFFLINE: function LB.pilot() return (tostring(CFG.leaderboard.pilot or ""):gsub("[^%w _%.%-]", ""):sub(1, 24)) end
-- Shot down: the player's aircraft at 0 health (checked once a second in a run)
function LB.deathCheck(pc)
    if not D or not D.round or D.round < 1 or (RUN.stats and RUN.stats.ended) then return end
    local st = stats()
    if not st.jet then                                -- the player's aircraft (user, 2026-10-23), read while it flies
        local code = nameOf(pc.Pawn):match("BP_PlayerPlane_PP%d+_(%w+)")
        if code then st.jet = code:lower():sub(1, 12); log("leaderboard: flying the " .. st.jet) end
    end
    local ok, h = pcall(function() return pc.Pawn.HealthInternal end)
    if not ok or type(h) ~= "number" then return end
    if h > 0 then st.flying, st.downs = true, 0                  -- (a pawn reads 0 while it's spawned: not a death)
    elseif DOWN and DOWN.holdsRun and DOWN.holdsRun() then
        -- (co-op with revives, sv_down.lua: a shot-down player is DOWN at its floor and the run ends for everyone on the
        -- host's "ro"; a plane that died all the same, past its floor, leaves the run as the game does)
        if st.flying and not st.coopSaid then st.coopSaid = true; log("leaderboard: your plane is gone; in co-op the run ends when every player is down") end
    elseif st.flying then
        st.downs = (st.downs or 0) + 1
        if st.downs >= 2 then
            pcall(STATS.death, "died")                   -- (what hit you, what you had left: sv_stats.lua)
            LB.finish("died")
        end
    end
end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
---------------------------------------------------------------------------------------------------- a co-op run
-- (0.73.77) One team run per co-op run, sent by its host (Workstream H2, testing/2026-11-03/PLAN_desync_lag_
-- compatibility.md; leaderboard/README.md): the solo record and "coop": { players, squad = [{ pilot, aircraft, air,
-- ground, revives, host }] }. LB.co is the co-op run this game is in: { id (the record's run_id), mine (this game hosts
-- it), stats (the RUN.stats it's for), started, squad = { [key] = { slot, name, pilot, jet, air, ground, revives, n } },
-- specials, run, sent }; a player's key is their Steam ID ("sid<id>"), else (UDP) their slot and name. The host keeps:
--   - the squad: everyone seen in Survival's level in the run (COOP.players()), a player who left with what they did;
--   - each joiner's own kills (LB.coopKill from sv_coop.lua tallyKill: the player the host's "dn" names, economy C1's
--     hostKiller, the one who did it the most damage; ground targets whole ones only, not a ship's turret) and the
--     revives each player gave (LB.stat("revives", 1, by): sv_down.lua hostRevive);
--   - the host's line: the run's kills as its game counts them (the AI allies' and defences' too, as a solo run's) less
--     the joiners'. The record's kills are the squad's sums, its zollars the host's own.
-- Every game keeps a copy from the host's "lb" messages (lb|r the run, lb|p the players, lb|s the specials, lb|x sent;
-- each joiner answers lb|n with its leaderboard pilot name), so a host by host migration (sv_coop.lua becomeHost ->
-- LB.coopTakeover) carries the run on and sends it under the same run id, the old host in its squad. A joiner sends
-- nothing; a run nobody else flew in goes as a solo run. The host sends at its run's end (died, restart, left: a host
-- quitting to the main menu keeps the link, so the others' runs stop there too); a run it sent isn't sent again by a
-- host by migration (the Worker would refuse the run id twice).
LB.co = nil
do
local RESEND_S, BATCH_S, MAX_SQUAD, PACK = 30, 2, 24, 800
local function cleanName(s) return (tostring(s or ""):gsub("[^%w _%.%-]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 24)) end
local function whole(v, hi) v = tonumber(v); return (v and v == math.floor(v) and v >= 0 and v <= hi) and v or nil end
local function mySlot() return COOP.slot or 0 end
local function id8(co) return tostring(co.id):sub(1, 8) end
-- a player's key: their Steam ID, else their slot and name
local function keyOf(slot)
    local r = COOP.roster and COOP.roster(slot)
    local sid = r and r.sid
    if slot == mySlot() and not sid and COOP.mySid then sid = COOP.mySid() end
    if type(sid) == "string" and sid:match("^%d+$") and #sid <= 20 then return "sid" .. sid end
    return "slot" .. slot .. ":" .. cleanName(r and r.name)
end
-- slot's entry in co's squad (made when `make`): the same player under the key they had before their Steam ID was known
-- here moved over; their name and aircraft (the first one seen, as a solo run's) from the co-op roster
local function entry(co, slot, make)
    local k = keyOf(slot)
    local e = co.squad[k]
    if not e and k:sub(1, 3) == "sid" then
        local pre = "slot" .. slot .. ":"
        for k2, e2 in pairs(co.squad) do
            if k2:sub(1, #pre) == pre then co.squad[k2], co.squad[k], e2.key, e = nil, e2, k, e2; break end
        end
    end
    if not e then
        if not make then return nil end
        co.n = co.n + 1
        e = { key = k, slot = slot, air = 0, ground = 0, revives = 0, n = co.n }
        co.squad[k] = e
        log(string.format("leaderboard: co-op run %s: player %d (%s) in the squad", id8(co), slot + 1,
            tostring(COOP.name and COOP.name(slot) or "?")))
    end
    e.slot = slot
    local r = COOP.roster and COOP.roster(slot)
    if r then
        local nm = cleanName(r.name)
        if nm ~= "" then e.name = nm end
        local code = tostring(r.code or ""):lower()
        if not e.jet and #code <= 12 and code:match("^[a-z0-9][a-z0-9]+$") then e.jet = code end
    end
    if co.pnames and co.pnames[k] then e.pilot = co.pnames[k] end
    return e
end
-- the squad as it's sent: { e, pilot, aircraft, air, ground, revives, host }, this game's own line first (the host's:
-- the run's kills less the others'), the others by what they did, MAX_SQUAD at most, the names unique
local function lines(co, st)
    local myKey = keyOf(mySlot())
    local me, others, oa, og = nil, {}, 0, 0
    for k, e in pairs(co.squad) do if k == myKey then me = e else others[#others + 1] = e end end
    table.sort(others, function(a, b)
        local x, y = a.air + a.ground + a.revives, b.air + b.ground + b.revives
        if x ~= y then return x > y end
        return a.n < b.n
    end)
    while #others > MAX_SQUAD - 1 do table.remove(others) end
    for _, e in ipairs(others) do oa, og = oa + e.air, og + e.ground end
    local out, used = {}, {}
    local function add(e, host)
        -- (the host's line: the record's own pilot exactly, as the Worker checks; first, so never renamed)
        local nm = host and LB.pilot() or cleanName(e.pilot or e.name)
        if nm == "" then nm = "Pilot " .. ((tonumber(e.slot) or 0) + 1) end
        local base, i = nm, 1
        while used[nm:lower()] do i = i + 1; local sfx = " " .. i; nm = base:sub(1, 24 - #sfx) .. sfx end
        used[nm:lower()] = true
        local x = { e = e, pilot = nm, aircraft = host and (st.jet or e.jet) or e.jet, air = e.air, ground = e.ground,
                    revives = e.revives, host = host }
        if host then x.air, x.ground = math.max(0, (st.air or 0) - oa), math.max(0, (st.ground or 0) - og) end
        out[#out + 1] = x
    end
    if me then add(me, true) end
    for _, e in ipairs(others) do add(e, false) end
    return out
end
-- (the host) the co-op run of this game's run: a new one for a new run, or (a host by migration) the one it was in
local function hostRun(now)
    local st = stats()
    local co = LB.co
    if co and co.mine and co.stats == st then return co, st end
    if co and co.adopt then
        -- the run this game was a joiner in: its record goes on from the old host's last word (its start, kills, aces,
        -- allies, the airfield's losses, the specials); this game's own money
        co.mine, co.adopt, co.stats, co.allAt = true, nil, st, 0
        local run = co.run or {}
        if co.started then st.started = math.min(st.started or os.time(), co.started) end
        if run.air then st.air, st.ground = run.air, run.ground end
        for _, k in ipairs({ "aces", "allies", "af_down", "captured" }) do st[k] = math.max(st[k] or 0, run[k] or 0) end
        local sp, top = {}, 0
        for i in pairs(co.specials) do if i > top then top = i end end
        for i = 1, top do if co.specials[i] then sp[#sp + 1] = co.specials[i] end end
        for _, x in ipairs(st.specials or {}) do sp[#sp + 1] = x end
        st.specials = sp
        local n = 0
        for _ in pairs(co.squad) do n = n + 1 end
        log(string.format("leaderboard: co-op run %s carried on here (host migration): %d in its squad, %d air / %d ground "
            .. "kills, %d specials, started %d s ago%s", id8(co), n, st.air or 0, st.ground or 0, #sp, os.time() - (st.started or os.time()),
            co.sent and "; its first host sent it already" or ""))
        return co, st
    end
    local id = {}
    for _ = 1, 32 do id[#id + 1] = string.format("%x", math.random(0, 15)) end
    co = { id = table.concat(id), mine = true, stats = st, squad = {}, n = 0, specials = {}, pnames = {}, at = now, allAt = 0 }
    LB.co = co
    log("leaderboard: co-op run " .. id8(co) .. " started: this game hosts it and keeps its squad (it sends the run)")
    return co, st
end
-- the squad's players now: this game's own always (the host's line is the record's first), the others in the level
local function squadNow(co)
    entry(co, mySlot(), true)
    for _, p in ipairs(COOP.players()) do
        if not p.isMe and p.inLevel and COOP.slotOk(p.slot) then entry(co, p.slot, true) end
    end
end
-- (the host, once a second) the squad, and what changed to everyone every BATCH_S, all of it every RESEND_S and to a
-- player who links: packed entries ("key,slot,air,ground,revives,aircraft,pilot;..."), as many as fit in a message
local function hostTick(now)
    local co, st = hostRun(now)
    squadNow(co)
    if now < (co.outAt or 0) then return end
    co.outAt = now + BATCH_S
    local linked = COOP.linked and COOP.linked() or 0
    if linked == 0 then co.linkedN = 0; return end
    local all = now >= (co.allAt or 0) or linked > (co.linkedN or 0)
    co.linkedN = linked
    if all then co.allAt = now + RESEND_S end
    local round = math.max(D.round or 0, (co.run and co.run.round) or 0)
    local hdr = table.concat({ st.air or 0, st.ground or 0, st.aces or 0, st.allies or 0, st.af_down or 0, st.captured or 0, round }, "/")
    if all or hdr ~= co.hdrSent then
        co.hdrSent = hdr
        COOP.msg(nil, "lb", "r", co.id, math.max(0, os.time() - (st.started or os.time())), st.air or 0, st.ground or 0,
            st.aces or 0, st.allies or 0, st.af_down or 0, st.captured or 0, round)
    end
    local pack = {}
    local function flush(kind) if #pack > 0 then COOP.msg(nil, "lb", kind, co.id, table.concat(pack, ";")); pack = {} end end
    local size = 0
    for _, x in ipairs(lines(co, st)) do
        local item = table.concat({ x.e.key, x.e.slot, x.air, x.ground, x.revives, x.aircraft or "", x.pilot }, ",")
        if all or item ~= x.e.sent then
            x.e.sent = item
            if size + #item > PACK then flush("p"); size = 0 end
            pack[#pack + 1], size = item, size + #item + 1
        end
    end
    flush("p")
    local sp = st.specials or {}
    size = 0
    for i = all and 1 or ((co.spSent or 0) + 1), math.min(#sp, 200) do
        local s = sp[i]
        local item = table.concat({ i, tostring(s.kind), s.round, s.seconds, s.won and 1 or 0 }, ",")
        if size + #item > PACK then flush("s"); size = 0 end
        pack[#pack + 1], size = item, size + #item + 1
    end
    flush("s")
    co.spSent = #sp
    if co.sent and all then COOP.msg(nil, "lb", "x", co.id) end
end
-- (each pass of LB.poll, once a second) the host's squad; a joiner's pilot name to the host, as it hears of the run and
-- every 2 minutes after
function LB.coopTick()
    if not (COOP and COOP.open and D and RUN) then return end
    local now = os.clock()
    if COOP.host() then return hostTick(now) end
    local co = LB.co
    if COOP.client() and co and not co.mine and not co.adopt and now >= (co.nameAt or 0) then
        co.nameAt = now + 120
        COOP.msg(0, "lb", "n", co.id, LB.pilot())
    end
end
-- (the host) n of what (air, ground: a joiner's kill; revives: a revive given) for the player in slot
function LB.coopTally(slot, what, n)
    if not (COOP and COOP.host and COOP.host() and D and RUN and COOP.slotOk(slot)) then return end
    if what ~= "revives" and (what ~= "air" and what ~= "ground" or slot == mySlot()) then return end   -- (the host's: its count)
    local co = hostRun(os.clock())
    local e = entry(co, slot, true)
    e[what] = e[what] + (whole(n, 1000) or 1)
    if what ~= "revives" and not e.said then
        e.said = true
        log(string.format("leaderboard: co-op run %s: player %d (%s)'s first kill counted for them (%s)", id8(co), slot + 1,
            tostring(e.pilot or e.name or "?"), what))
    end
end
-- (the host, sv_coop.lua tallyKill: the player its "dn" named, economy C1's hostKiller) a joiner's kill of the host's
-- object e: a plane (air), or a whole ground target (not a part on another: a ship's turret, a Ladon's pod, the
-- Alicorn's tanks, which the run's own count takes with their hull, if at all). The host's own: its count, not tallied.
function LB.coopKill(slot, e)
    if type(e) ~= "table" or slot == mySlot() then return end
    if e.key then
        local o = e.obj
        local okP, par = false, nil
        if liveAddr(o) then okP, par = pcall(function() return o:GetAttachParentActor() end) end
        if okP and par ~= nil and valid(par) then
            if not LB.partSaid then
                LB.partSaid = true
                log(string.format("leaderboard: player %d's kill of %s not counted for them: a part of %s (whole targets only)",
                    slot + 1, nameOf(o), nameOf(par)))
            end
            return
        end
    end
    LB.coopTally(slot, e.key and "ground" or "air", 1)
end
-- (a joiner becoming the host by migration: sv_coop.lua becomeHost) the co-op run it was in goes on here
function LB.coopTakeover()
    local co = LB.co
    if co and not co.mine then
        co.adopt = true
        log("leaderboard: co-op run " .. id8(co) .. ": this game takes it over (host migration); it sends the run")
    end
end
-- The leaderboard's messages (sv_coop.lua hands them over): from a joiner (from set) lb|n|<run id>|<pilot>; from the host
-- lb|r|<run id>|<age s>|<air>|<ground>|<aces>|<allies>|<af_down>|<captured>, lb|p|<run id>|<key,slot,air,ground,revives,
-- aircraft,pilot;...>, lb|s|<run id>|<i,kind,round,seconds,won;...>, lb|x|<run id> (the host sent it)
function LB.coopMsg(f, from)
    local k, id = f[2], tostring(f[3] or "")
    if not (id:match("^%x+$") and #id >= 16 and #id <= 64) then return end
    local co = LB.co
    if from ~= nil then
        if k == "n" and co and co.mine and co.id == id and COOP.slotOk(from) and from ~= mySlot() then
            local nm = cleanName(f[4])
            if nm == "" then return end
            co.pnames = co.pnames or {}
            local key = keyOf(from)
            if co.pnames[key] ~= nm then
                co.pnames[key] = nm
                local e = entry(co, from, false)
                log(string.format("leaderboard: co-op run %s: player %d goes on the leaderboard as %s%s", id8(co), from + 1, nm,
                    e and "" or " (once in the level)"))
            end
        end
        return
    end
    if COOP.host() then return end                              -- (this game hosts: its own run's word)
    if co and (co.mine or co.adopt) then
        -- (a run this game hosted before it joined; or the same one: a takeover undone, sv_coop.lua migStepBack)
        if co.id == id then co.mine, co.adopt, co.stats = false, nil, nil else co = nil end
    end
    if not co or co.id ~= id then
        co = { id = id, mine = false, squad = {}, n = 0, specials = {}, run = {} }
        LB.co = co
        log("leaderboard: co-op run " .. id8(co) .. ": the host's (the host sends it); its squad kept here too, for host migration")
    end
    if k == "r" then
        local age = whole(f[4], 48 * 3600)
        if age then co.started = os.time() - age end
        local run = {}
        for i, key in ipairs({ "air", "ground", "aces", "allies", "af_down", "captured", "round" }) do run[key] = whole(f[4 + i], 1000000) or 0 end
        co.run = run
    elseif k == "p" then
        for item in tostring(f[4] or ""):gmatch("[^;]+") do
            local key, slot, a, g, rv, ac, pilot = item:match("^([^,]+),(%d+),(%d+),(%d+),(%d+),([^,]*),([^,]*)$")
            slot = whole(slot, 23)
            if key and slot and (key:match("^sid%d+$") or key:match("^slot%d+:[%w _%.%-]*$")) and #key <= 48 then
                local e = co.squad[key]
                if not e and co.n < 64 then co.n = co.n + 1; e = { key = key, n = co.n }; co.squad[key] = e end
                if e then
                    e.slot, e.air, e.ground, e.revives = slot, whole(a, 1000000) or 0, whole(g, 1000000) or 0, whole(rv, 100000) or 0
                    e.jet = (#ac <= 12 and ac:match("^[a-z0-9][a-z0-9]+$")) or nil
                    local nm = cleanName(pilot)
                    e.pilot = nm ~= "" and nm or nil
                end
            end
        end
    elseif k == "s" then
        for item in tostring(f[4] or ""):gmatch("[^;]+") do
            local i, kind, rd, secs, won = item:match("^(%d+),(%l+),(%d+),(%d+),([01])$")
            i, rd, secs = whole(i, 200), whole(rd, 1000), whole(secs, 3600)
            if i and i >= 1 and rd and secs and #kind <= 16 then co.specials[i] = { kind = kind, round = rd, seconds = secs, won = won == "1" } end
        end
    elseif k == "x" then
        co.sent = true
    end
end
-- (LB.finish, before the score) this run as a co-op one: a joiner's isn't sent (r.coopJoiner); the host's gets the
-- squad, the co-op run's id and the squad's kills; a host by migration's that its first host sent isn't sent again
-- (r.coopSent). Nothing when co-op isn't open, or nobody else flew in the run.
function LB.coopRecord(r, st, how)
    if not (COOP and COOP.open) then return end
    if COOP.client() then r.coopJoiner = true; return end
    if not COOP.host() then return end
    local co = hostRun(os.clock())
    squadNow(co)
    -- (the run's own as they are now: a host by migration's taken over in that call too) its round the highest reached,
    -- the first host's too (a migration plays its round again: D.round one lower until it starts), never under a special's
    r.specials, r.aces, r.allies, r.af_down, r.captured = st.specials, st.aces or 0, st.allies or 0, st.af_down or 0, st.captured or 0
    r.time_s = math.max(0, os.time() - (st.started or os.time()))
    r.round = math.max(r.round, (co.run and co.run.round) or 0)
    for _, s in ipairs(r.specials or {}) do if (tonumber(s.round) or 0) > r.round then r.round = s.round end end
    local list = lines(co, st)
    if #list < 2 then
        log("leaderboard: co-op run " .. id8(co) .. ": nobody else flew in it; it goes as a solo run")
        return
    end
    local air, ground, sq, said = 0, 0, {}, {}
    for _, x in ipairs(list) do
        air, ground = air + x.air, ground + x.ground
        sq[#sq + 1] = { pilot = x.pilot, aircraft = x.aircraft, air = x.air, ground = x.ground, revives = x.revives, host = x.host }
        said[#said + 1] = string.format("%s%s %d/%d/%d", x.pilot, x.host and " (host)" or "", x.air, x.ground, x.revives)
    end
    r.run_id, r.kills, r.coop, r.coopSent = co.id, { air = air, ground = ground }, { players = #sq, squad = sq }, co.sent
    log(string.format("leaderboard: co-op run %s over (%s): %d players (air / ground kills / revives given): %s", id8(co),
        tostring(how), #sq, table.concat(said, ", ")))
end
-- (LB.send, the host's co-op run sent) everyone told, so a host by migration doesn't send it again
function LB.coopSent(r)
    local co = LB.co
    if r and r.coop and co and co.mine and r.run_id == co.id then
        co.sent = true
        if COOP and COOP.open then COOP.msg(nil, "lb", "x", co.id) end
    end
end
end
-- ONLINE ONLY END

-- The run's over (died / restart / left): its record, sent at once, and its summary on screen.
function LB.finish(how)
    if not D or not D.round or D.round < 1 then return end
    local st = stats()
    if st.ended then return end                         -- (shot down, then restarted: one record)
    st.ended = how
    pcall(STATS.runEnd, how)                            -- (the run's measurements in the log, sv_stats.lua; not sent)
    local c = CFG.leaderboard
    local id = {}
    for _ = 1, 32 do id[#id + 1] = string.format("%x", math.random(0, 15)) end
    local r = { run_id = table.concat(id), pilot = LB.pilot(), difficulty = (presetName()),
                round = D.round, mod = VERSION, kills = { air = st.air, ground = st.ground },
                zollars = { earned = math.floor(RUN.earned or 0), spent = math.floor(RUN.spent or 0) },
                time_s = math.max(0, os.time() - st.started), ended = how == "died" and "died" or "quit", specials = st.specials,
                aircraft = st.jet, how = how, aces = st.aces or 0, allies = st.allies or 0, af_down = st.af_down or 0,
                captured = st.captured or 0,
                tier = CFG.tiers.enabled and (CFG.tiers.list[TIER.index(D.round)] or {}).name or nil,
                -- (the summary's own: kills by allies and ships, by airfield defences; not sent)
                by_allies = st.by_allies or 0, by_defences = st.by_defences or 0 }
-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
    -- ((0.73.77) a co-op run: the host's gets its squad, the co-op run's id and the squad's kills; a joiner's isn't sent)
    local okC, errC = pcall(LB.coopRecord, r, st, how)
    if not okC then log("leaderboard: the co-op run's squad couldn't be made: " .. tostring(errC)) end
-- ONLINE ONLY END
    r.score, r.won = score(r)
    log(string.format("leaderboard: run over (%s): round %d, score %d, %d air / %d ground kills, %d specials beaten, %s",
        how, r.round, r.score, r.kills.air, r.kills.ground, r.won, clockText(r.time_s)))
    -- submitted straight away; the summary shows show_s once it's on screen (at: a run left from the menu has no HUD,
    -- so its summary waits for the next run's)
    LB.show = { run = r, at = nil, state = "sending" }
-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
    local ok, err = pcall(LB.send, LB.show)
    if not ok then                                      -- (0.50.0: a send that failed left "SENDING..." up for good)
        LB.show.state, LB.show.why = "refused", "error"
        log("leaderboard: the run couldn't be sent: " .. tostring(err))
    end
    LB.menuTestKey = nil                                -- (a test key pressed at the main menu: that run's, now over)
-- ONLINE ONLY END
--OFFLINE:     LB.show.state = "local"                           -- (the Offline edition: shown here only)
end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
-- A run goes into pending_runs.txt before it's sent and comes off once the server has answered for good (taken or
-- refused), so a run the game closes on, or one that can't get through, is sent later (LB.queueTick).
local function unqueue(body)
    for i, b in ipairs(LB.queue) do if b == body then table.remove(LB.queue, i); saveQueue(); return end end
end
-- (kept: a run of refused_runs.txt sent again, its entry: (0.73.80) its answer is keptAnswer's)
local function post(body, sh, kept)
    local id = type(SV_Post) == "function" and SV_Post(body) or -5
    if id > 0 then LB.jobs[#LB.jobs + 1] = { id = id, body = body, sh = sh, kept = kept } end
    return id
end

function LB.send(sh)
    -- ((0.73.77) a co-op run is sent once, by its host, LB.coopRecord: a joiner's never; a host by migration's not again
    -- when its first host sent it)
    if sh.run.coopJoiner then
        sh.state = "host"
        log("leaderboard: a co-op run; the host sends it")
        return
    end
    if sh.run.coopSent then
        sh.state = "host"
        log("leaderboard: a co-op run its first host sent already (before host migration); not sent again")
        return
    end
    if D and (D.startRound or 1) > 1 then              -- (a head start: START AT ROUND on the menu, or the ini's start_round)
        sh.state = "local"
        log("leaderboard: the run started at round " .. D.startRound .. " (start_round); not sent")
        return
    end
    -- edited from the shipped Survival Mode (LB.edited): not sent, the summary says why, the log names all of it (a
    -- check that fails sends nothing either)
    local okE, ed, detail = pcall(LB.edited, COOP and COOP.open)
    if not okE or type(ed) ~= "table" then ed, detail = { "check failed" }, { "the check failed: " .. tostring(ed) } end
    if #ed > 0 then
        sh.state, sh.why = "unranked", "edited (" .. tostring(ed[1]):sub(1, 28) .. ")"     -- (the summary panel's width)
        log("leaderboard: not sent: the run was edited from the shipped Survival Mode (" .. #ed .. "): " .. table.concat(detail, "; "))
        return
    end
    sh.run.edited = ed
    -- the build hash the game started with (dlls/main.dll 0.28.6; the send itself carries the files' hash as they are then)
    local bh = type(SV_BuildHash) == "function" and tostring(SV_BuildHash() or "") or nil
    if bh and bh ~= "" then sh.run.build = bh
    elseif bh then log("leaderboard: no build hash (the runtime's log, AC8SurvivalMode.log, says why): the run goes unverified") end
    local body = json(sh.run)
    LB.queue[#LB.queue + 1] = body; saveQueue()
    local id = post(body, sh)
    pcall(LB.coopSent, sh.run)                          -- ((0.73.77) a co-op run: every game told it's in)
    if id > 0 then
        sh.state = "sending"
        log("leaderboard: sending the run (job " .. id .. ")" .. (sh.run.coop and string.format(" (co-op, %d players)", sh.run.coop.players) or ""))
    else
        sh.state = "queued"
        log("leaderboard: not sent now (" .. tostring(id == -8 and "this build has no leaderboard address" or id) .. "); kept for later")
    end
end

local WHY = { [-12007] = "the server's name didn't resolve (DNS, or the address is blocked)",
              [-12029] = "couldn't connect (a firewall, or the address is blocked)",
              [-12002] = "timed out", [-12175] = "the secure connection failed (TLS)",
              [-12038] = "the certificate's name didn't match (a proxy in the way?)" }

-- ((0.73.80) errors0) a kept run's answer: taken (off the file), an unknown build still (kept for the next game start),
-- refused for any other reason (dropped), or no answer for good (a 429, a 5xx, no connection: kept for the next start)
local function keptAnswer(k, st, reply, err)
    local idx = nil
    for i, x in ipairs(LB.kept or {}) do if x == k then idx = i; break end end
    local what
    if st == 200 then
        what = "taken" .. (reply:find('"duplicate":true', 1, true) and " (it was on the board already)" or "") .. ", off " .. KEEP_FILE
        if idx then table.remove(LB.kept, idx) end
    elseif unknownBuild(st, err) then
        what = string.format("still an unknown build (register its hash on /admin), kept: sent again at the next game start (%d days left)",
            math.max(0, KEEP_DAYS - daysAgo(k.at)))
    elseif st == 422 and err == "played on other files" then
        -- ((review of 0.73.80) the files changed since it was played (an update or a patch): a leaderboard from before
        -- 0.73.80 refuses that outright, the 0.73.80 one checks the build it was played on: kept for it)
        what = string.format("played on other files than these (an update since): kept, sent again at the next game start (%d days "
            .. "left; the leaderboard of 0.73.80 checks the build it was played on)", math.max(0, KEEP_DAYS - daysAgo(k.at)))
    elseif st > 0 and st < 500 and st ~= 429 then
        what = "refused for another reason (" .. tostring(err or ("status " .. st)) .. "), dropped from " .. KEEP_FILE
        if idx then table.remove(LB.kept, idx) end
    else
        what = "no answer for good" .. (WHY[st] and (" (" .. WHY[st] .. ")") or "") .. ", kept for the next game start"
    end
    if LB.kept then saveKept() end
    log(string.format("leaderboard: a kept run (%s; refused as an unknown build %d days ago, resent %d times) resent: answered %d: %s: %s",
        runTag(k.body), daysAgo(k.at), k.tries, st, what, reply:sub(1, 200)))
end

-- Once a second, at the main menu and in runs: the sends' answers (reading a job's result frees its native slot), and a
-- co-op run's squad ((0.73.77) LB.coopTick)
function LB.poll()
    local okT, errT = pcall(LB.coopTick)
    if not okT and not LB.coopErrSaid then LB.coopErrSaid = true; log("leaderboard: co-op squad error " .. tostring(errT)) end
    for i = #LB.jobs, 1, -1 do
        local j = LB.jobs[i]
        local st = SV_PostResult(j.id)
        if st ~= 0 and j.kept then                      -- ((0.73.80) a run of refused_runs.txt sent again)
            table.remove(LB.jobs, i)
            local reply = SV_PostReply(j.id) or ""
            local okK, errK = pcall(keptAnswer, j.kept, st, reply, reply:match('"error":"([^"]+)"'))
            if not okK then log("leaderboard: a kept run's answer (" .. st .. ") couldn't be handled: " .. tostring(errK)) end
        elseif st ~= 0 then
            table.remove(LB.jobs, i)
            local reply = SV_PostReply(j.id) or ""
            local final = st > 0 and st < 500 and st ~= 429
            local sh = j.sh
            log(string.format("leaderboard: %s: the server answered %d%s: %s", sh and "the run" or "a waiting run", st,
                WHY[st] and (" (" .. WHY[st] .. ")") or "", reply:sub(1, 200)))
            -- ((0.73.80) errors0: refused only as an unknown build, kept in refused_runs.txt to send again, not lost)
            if final and unknownBuild(st, reply:match('"error":"([^"]+)"')) then
                local okK, errK = pcall(keepRefused, j.body)
                if not okK then log("leaderboard: the refused run couldn't be kept: " .. tostring(errK)) end
            end
            if final then unqueue(j.body) else LB.qwait = os.clock() + (st == 429 and 600 or 120) end
            if sh then
                if st == 200 then sh.state, sh.score = "sent", reply:match('"score":(%d+)')
                elseif not final then sh.state = "queued"
                else sh.state, sh.why = "refused", reply:match('"error":"([^"]+)"') or ("status " .. st) end
            end
        end
    end
end
-- ONLINE ONLY END
--OFFLINE: function LB.poll() end
-- Each HUD pass: the summary's texts, and closing it.
function LB.hud(now)
    local sh = LB.show
    if sh and not sh.at and H and H.lbTitle and H.shown then sh.at = os.clock() end
    -- (closed show_s after it's on screen once it's answered, and after 3 minutes whatever: a send that never answers
    -- mustn't keep it up)
    if sh and sh.at and os.clock() - sh.at > ((sh.state ~= "sending") and (CFG.leaderboard.show_s or 15) or 180) then
        LB.show, sh = nil, nil
    end
    if not (H and H.lbTitle) then return end
    local t = CFG.hud.text
    if not sh then
        if H.lbShown then
            if H.lbPanel then H.lbPanel:SetVisibility(VIS.Collapsed) end
            H.lbTitle:SetVisibility(VIS.Collapsed)
            for _, l in ipairs(H.lbLines) do l:SetVisibility(VIS.Collapsed) end
            H.lbShown = false
        end
        return
    end
    local r = sh.run
    local lines = { string.format(t.lb_lines[1], r.round), string.format(t.lb_lines[2], money(r.score)),
                    string.format(t.lb_lines[3], r.kills.air, r.kills.ground), string.format(t.lb_lines[4], r.won),
                    string.format(t.lb_lines[5], clockText(r.time_s)), string.format(t.lb_lines[6], money(r.zollars.earned)),
                    t.lb_lines[7] and string.format(t.lb_lines[7], r.by_allies or 0, r.by_defences or 0) or "" }
    lines[8] = (sh.state == "sending" and t.lb_sending) or (sh.state == "sent" and string.format(t.lb_sent, money(tonumber(sh.score or r.score) or r.score)))
        or (sh.state == "queued" and t.lb_queued) or (sh.state == "refused" and string.format(t.lb_refused, tostring(sh.why):upper()))
        or (sh.state == "unranked" and string.format(t.lb_unranked or "NOT RANKED: %s", tostring(sh.why):upper():sub(1, 48)))
        or (sh.state == "host" and (t.lb_coop_host or "CO-OP: THE HOST SENDS THE RUN"))     -- ((0.73.77) a co-op joiner's)
        or ""
    setText(H.lbTitle, "lbTitleStr", string.format(t.lb_title, r.pilot ~= "" and r.pilot:upper() or "PILOT"))
    for i, l in ipairs(H.lbLines) do setText(l, "lbLineStr" .. i, lines[i] or "") end
    if not H.lbShown then
        if H.lbPanel then H.lbPanel:SetVisibility(VIS.HitTestInvisible) end
        H.lbTitle:SetVisibility(VIS.HitTestInvisible)
        for _, l in ipairs(H.lbLines) do l:SetVisibility(VIS.HitTestInvisible) end
        H.lbShown = true
    end
end

-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
-- ((0.73.80) errors0) the kept runs refused as an unknown build: each sent again once this game start, from the main
-- menu only (no run, not Survival's level), the first KEEP_FIRST_S after the first look there, then KEEP_GAP_S apart
local function keptTick()
    if D or svLevelOn == true then return end
    local kept, now = loadKept(), os.clock()
    if #kept == 0 then return end
    if not LB.keptAt then LB.keptAt = now + KEEP_FIRST_S end
    if now < LB.keptAt then return end
    for _, k in ipairs(kept) do
        if k.due then
            k.due, LB.keptAt = false, now + KEEP_GAP_S
            local id = post(k.body, nil, k)
            if id > 0 then
                k.tries = k.tries + 1
                saveKept()
                log(string.format("leaderboard: resending a run refused as an unknown build %d days ago (%s; resent %d times) (job %d)",
                    daysAgo(k.at), runTag(k.body), k.tries, id))
            else
                log(string.format("leaderboard: a run refused as an unknown build (%s) not resent now (%s): kept for the next game start",
                    runTag(k.body), tostring(id == -8 and "this build has no leaderboard address" or id)))
                if id == -8 then LB.keptAt = math.huge end
            end
            return
        end
    end
end
-- The runs not yet answered for good: read at the start, sent one at a time (at the main menu or in a run).
function LB.queueTick()
    -- (once: this build's hash when the runtime has it, and settings that make every run unranked, so the log says so
    -- before the first run)
    if not LB.toldBuild and type(SV_BuildHash) == "function" then
        local h = tostring(SV_BuildHash() or "")
        if h ~= "" then LB.toldBuild = true; log("leaderboard: this build's hash is " .. h .. " (runs count only from a registered build)") end
    end
    if not LB.toldEdited then
        LB.toldEdited = true
        local ok, ed, detail = pcall(LB.edited, false)
        if ok and type(ed) == "table" and #ed > 0 then
            log("leaderboard: this game differs from the shipped Survival Mode, so its runs won't be ranked: " .. table.concat(detail, "; "))
        end
    end
    if not LB.loaded then
        LB.loaded = true
        local f = io.open(configDir() .. "pending_runs.txt", "r")
        if f then
            for line in f:lines() do if line:sub(1, 1) == "{" then LB.queue[#LB.queue + 1] = line end end
            f:close()
            if #LB.queue == 0 then saveQueue() end              -- (an empty file from an older version: deleted)
            if #LB.queue > 0 then log("leaderboard: " .. #LB.queue .. " run(s) waiting to be sent") end
        end
        local okK, errK = pcall(loadKept)                 -- ((0.73.80) the runs refused as an unknown build, kept)
        if not okK then LB.kept = LB.kept or {}; log("leaderboard: " .. KEEP_FILE .. " couldn't be read: " .. tostring(errK)) end
    end
    -- one at a time, none while a send is in flight (the run just ended is in the queue too); the kept runs only once
    -- none is waiting
    if #LB.jobs > 0 or type(SV_Post) ~= "function" then return end
    if #LB.queue > 0 then
        if os.clock() < (LB.qwait or 0) then return end
        if post(LB.queue[1], nil) == -8 then LB.qwait = math.huge end
        return
    end
    local okK, errK = pcall(keptTick)
    if not okK and not LB.keptErrSaid then LB.keptErrSaid = true; log("leaderboard: kept runs error " .. tostring(errK)) end
end
-- ONLINE ONLY END
--OFFLINE: function LB.queueTick() end
end
