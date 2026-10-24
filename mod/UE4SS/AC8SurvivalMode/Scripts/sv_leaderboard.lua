-- sv_leaderboard.lua: the run's stats, its summary and the leaderboard (Online edition only).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_main); a name
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
    return string.format('{"v":1,"run_id":%s,"pilot":%s,"difficulty":%s,"round":%d,"mod":%s,"kills":{"air":%d,"ground":%d},'
        .. '"zollars":{"earned":%d,"spent":%d},"time_s":%d,"ended":%s,"how":%s,"aces":%d,"allies":%d,"af_down":%d,'
        .. '"captured":%d,"specials":[%s]%s%s}', jstr(r.run_id), jstr(r.pilot),
        jstr(r.difficulty), r.round, jstr(r.mod), r.kills.air, r.kills.ground, r.zollars.earned, r.zollars.spent, r.time_s,
        jstr(r.ended), jstr(r.how), r.aces, r.allies, r.af_down, r.captured, table.concat(sp, ","),
        (r.aircraft and r.aircraft:match("^[a-z0-9][a-z0-9]+$")) and (',"aircraft":' .. jstr(r.aircraft)) or "",
        (r.tier and r.tier:match("^%a+$")) and (',"tier":' .. jstr(r.tier)) or "")
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
    elseif st.flying then
        st.downs = (st.downs or 0) + 1
        if st.downs >= 2 then LB.finish("died") end
    end
end

-- The run's over (died / restart / left): its record, sent at once, and its summary on screen.
function LB.finish(how)
    if not D or not D.round or D.round < 1 then return end
    local st = stats()
    if st.ended then return end                         -- (shot down, then restarted: one record)
    st.ended = how
    local c = CFG.leaderboard
    local id = {}
    for _ = 1, 32 do id[#id + 1] = string.format("%x", math.random(0, 15)) end
    local r = { run_id = table.concat(id), pilot = LB.pilot(), difficulty = (presetName()),
                round = D.round, mod = VERSION, kills = { air = st.air, ground = st.ground },
                zollars = { earned = math.floor(RUN.earned or 0), spent = math.floor(RUN.spent or 0) },
                time_s = math.max(0, os.time() - st.started), ended = how == "died" and "died" or "quit", specials = st.specials,
                aircraft = st.jet, how = how, aces = st.aces or 0, allies = st.allies or 0, af_down = st.af_down or 0,
                captured = st.captured or 0,
                tier = CFG.tiers.enabled and (CFG.tiers.list[TIER.index(D.round)] or {}).name or nil }
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
                    string.format(t.lb_lines[5], clockText(r.time_s)), string.format(t.lb_lines[6], money(r.zollars.earned)), "" }
    lines[8] = (sh.state == "sending" and t.lb_sending) or (sh.state == "sent" and string.format(t.lb_sent, money(tonumber(sh.score or r.score) or r.score)))
        or (sh.state == "queued" and t.lb_queued) or (sh.state == "refused" and string.format(t.lb_refused, tostring(sh.why):upper()))
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
