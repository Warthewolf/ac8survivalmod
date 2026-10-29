-- sv_leaderboard.lua: the run's stats, its summary and the leaderboard (Online edition only).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

---------------------------------------------------------------------------------------------------- leaderboard
-- CFG.leaderboard; leaderboard/src/index.js is the other end (same score, same checks). RUN.stats: { started, air,
-- ground, aces (ace squadron aircraft down), allies (allies bought), af_down (times the airfield went down), captured
-- (times it was captured), specials = { { kind, round, seconds, won } } }. LB.show: the finished run on screen.
-- ONLINE ONLY BEGIN
-- LB.queue: the runs not yet answered for good (pending_runs.txt); LB.jobs: the sends in flight.
-- ONLINE ONLY END
do
local function stats()
    RUN.stats = RUN.stats or { started = os.time(), air = 0, ground = 0, aces = 0, allies = 0, af_down = 0, captured = 0,
                               specials = {} }
    return RUN.stats
end
function LB.stat(what, n) if D then local st = stats(); st[what] = (st[what] or 0) + (n or 1) end end
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
    return string.format('{"v":1,"run_id":%s,"pilot":%s,"difficulty":%s,"round":%d,"mod":%s,"kills":{"air":%d,"ground":%d},'
        .. '"zollars":{"earned":%d,"spent":%d},"time_s":%d,"ended":%s,"how":%s,"aces":%d,"allies":%d,"af_down":%d,'
        .. '"captured":%d,"specials":[%s],"edited":[%s]%s%s%s}', jstr(r.run_id), jstr(r.pilot),
        jstr(r.difficulty), r.round, jstr(r.mod), r.kills.air, r.kills.ground, r.zollars.earned, r.zollars.spent, r.time_s,
        jstr(r.ended), jstr(r.how), r.aces, r.allies, r.af_down, r.captured, table.concat(sp, ","), table.concat(ed, ","),
        (r.aircraft and r.aircraft:match("^[a-z0-9][a-z0-9]+$")) and (',"aircraft":' .. jstr(r.aircraft)) or "",
        (r.tier and r.tier:match("^%a+$")) and (',"tier":' .. jstr(r.tier)) or "",
        (type(r.build) == "string" and r.build:match("^%x+$") and #r.build == 64) and (',"build":' .. jstr(r.build:lower())) or "")
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
                    menu = true, setup = true, coop = true }
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
local function post(body, sh)
    local id = type(SV_Post) == "function" and SV_Post(body) or -5
    if id > 0 then LB.jobs[#LB.jobs + 1] = { id = id, body = body, sh = sh } end
    return id
end

function LB.send(sh)
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
    if id > 0 then
        sh.state = "sending"
        log("leaderboard: sending the run (job " .. id .. ")")
    else
        sh.state = "queued"
        log("leaderboard: not sent now (" .. tostring(id == -8 and "this build has no leaderboard address" or id) .. "); kept for later")
    end
end

local WHY = { [-12007] = "the server's name didn't resolve (DNS, or the address is blocked)",
              [-12029] = "couldn't connect (a firewall, or the address is blocked)",
              [-12002] = "timed out", [-12175] = "the secure connection failed (TLS)",
              [-12038] = "the certificate's name didn't match (a proxy in the way?)" }

-- Once a second, at the main menu and in runs: the sends' answers (reading a job's result frees its native slot).
function LB.poll()
    for i = #LB.jobs, 1, -1 do
        local j = LB.jobs[i]
        local st = SV_PostResult(j.id)
        if st ~= 0 then
            table.remove(LB.jobs, i)
            local reply = SV_PostReply(j.id) or ""
            local final = st > 0 and st < 500 and st ~= 429
            if final then unqueue(j.body) else LB.qwait = os.clock() + (st == 429 and 600 or 120) end
            local sh = j.sh
            if sh then
                if st == 200 then sh.state, sh.score = "sent", reply:match('"score":(%d+)')
                elseif not final then sh.state = "queued"
                else sh.state, sh.why = "refused", reply:match('"error":"([^"]+)"') or ("status " .. st) end
            end
            log(string.format("leaderboard: %s: the server answered %d%s: %s", sh and "the run" or "a waiting run", st,
                WHY[st] and (" (" .. WHY[st] .. ")") or "", reply:sub(1, 200)))
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
    end
    -- one at a time, none while a send is in flight (the run just ended is in the queue too)
    if #LB.queue == 0 or #LB.jobs > 0 or type(SV_Post) ~= "function" or os.clock() < (LB.qwait or 0) then return end
    if post(LB.queue[1], nil) == -8 then LB.qwait = math.huge end
end
-- ONLINE ONLY END
--OFFLINE: function LB.queueTick() end
end
