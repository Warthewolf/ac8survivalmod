-- sv_escort_subs.lua: THE ESCORT's subtitles (CHARLENE, her four KMG escorts and Comona's staff) and the Anomalies' wait
-- for her (CFG.specials.anomaly_gate). Part of AC8 Survival Mode's runtime, run by main.lua in MODULES' order, right after
-- sv_escort.lua: a name another part uses is a global of this mod's Lua state, its own helpers stay local.
--
-- (2026-11-07, the user: "Charlene should have subtitles, the same way SAL and the Comona Airfield talk to eachother.
-- Charlene, Yorke, Rock, Ali, Danielle all should have their own unique Subtitles that play. And the Lines about
-- unlocking the ZFA-44 and Charlene Thanking the players also should be subtitles too"; "Give Charlene Unique Lines for
-- Landing, Being Attacked, Being Defended. Charlene is a Wealthy CEO who owns one of the worlds largest plane
-- collections, she is from the KOKODA MERCENARY GROUP, based out of Aurelia"; "Yorke, Rock, Ali, Danielle are also apart
-- of KOKODA MERCENARY GROUP"; "Anomaly Rounds shouldn't start until Charlene arrives at the airbase"; "the round before
-- an Anomaly Round appears, a Subtitle from Charlene should appear telling the Players that an Anomaly Is Approaching
-- (she will not be able to warn players about VALKA though)")
--   ESUB.tick(S, now)               (ESC.step's, each tick of the escort; the host's or solo) what changed since the last
--                                   tick, said: her spawn (go), the first enemies sent at her, each wave, her hits and her
--                                   health, an enemy near her shot down (and by whom), her final, touchdown and landing,
--                                   each escort's loss and landing
--   ESUB.finish(S, now, won, line)  (finish's) her thanks (line: the user's exact text) then Comona's, or her loss; true
--                                   when the thanks went on the strip (else sv_escort.lua calls it out as before)
--   ESUB.warnNext(round, now)       (the round's end, sv_rounds.lua) the next round's special drawn; one of
--                                   anomaly_gate.warn_kinds: her warning, when she's at Comona
--   ESC.anomalyOk(kind)             (sv_spawn.lua specialReady) false while an Anomaly waits for her
-- The lines: CFG.specials.escort.text.say (sv_config_specials.lua). Every line goes through SUB.say, so a co-op host's
-- go to the joiners too ("sb", sv_coop_migration.lua). Log lines `escort subs: ...`.
ESUB = { T = nil }
do
local function ec() return CFG.specials.escort end
local function cfg() return (ec().text or {}).say or {} end
local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function on() return cfg().enabled ~= false and SUB ~= nil and type(SUB.say) == "function" end
local function proper(nm) nm = tostring(nm or ""); return nm:sub(1, 1):upper() .. nm:sub(2):lower() end   -- (YORKE: Yorke)

-- a line "WHO|text": its speaker (C / T / G: Comona's staff, cfg().staff; else the name as written) and its text, {x}
-- filled in
function ESUB.line(l, vals)
    local who, text = tostring(l or ""):match("^([^|]+)|(.*)$")
    if not who then who, text = ec().name or "CHARLENE", tostring(l or "") end
    who = (cfg().staff or {})[who] or who
    text = text:gsub("{(%w+)}", function(k) local v = vals and vals[k]; if v == nil then return "{" .. k .. "}" end return tostring(v) end)
    return who, text
end
-- whether `who` can talk: not one of them who's been shot down (Comona's staff always)
local function canTalk(S, who)
    for _, B in ipairs(S and S.ac or {}) do
        if B.name == who then return B.st ~= "lost" end
    end
    return true
end
local function okLines(S, x)
    if type(x) == "string" then return canTalk(S, (x:match("^([^|]+)|"))) end
    if type(x) ~= "table" then return false end
    for _, l in ipairs(x) do if not okLines(S, l) then return false end end
    return true
end
-- one entry of the list (a line, or an exchange: a list of lines) at random that everyone in it can say, never the one
-- picked last under key; force: whoever's in it
local last = {}
local function pick(S, key, l, force)
    if type(l) == "string" then l = { l } end
    if type(l) ~= "table" or #l == 0 then return nil end
    local n, start = #l, math.random(#l)
    for j = 0, n - 1 do
        local i = (start + j - 1) % n + 1
        -- ((2026-11-08) AUDREY's and VALKA's lines once a run: SUB.fresh)
        if (n == 1 or last[key] ~= i) and (force or okLines(S, l[i])) and (not SUB.fresh or SUB.fresh(l[i])) then last[key] = i; return l[i] end
    end
    return nil
end
function ESUB.pick(S, key, l, force) return pick(S, key, l, force) end
-- what's under `key` (or opts.list) said: a line, or every line of an exchange in order. opts.pool: only while the strip
-- has room (busy_s; a line that would wait longer isn't said); opts.force: even one who's been shot down (their own last
-- words, her loss). True when a line went on the strip.
function ESUB.say(S, key, vals, opts)
    if not on() then return false end
    opts = opts or {}
    if opts.pool and type(SUB.left) == "function" and SUB.left(opts.now or (D and D.now) or 0) > num(cfg().busy_s, 6) then
        return false
    end
    local x = pick(S, key, opts.list or cfg()[key], opts.force)
    if x == nil then return false end
    local list = type(x) == "table" and x or { x }
    local any = false
    for _, y in ipairs(list) do
        local who, text = ESUB.line(y, vals)
        if SUB.say(who, text) then any = true end
    end
    return any
end

---------------------------------------------------------------------------------------------------- each tick
local function sayNow(S, key, vals, now, list) return ESUB.say(S, key, vals, { pool = true, now = now, list = list }) end
-- an enemy near her shot down: who did it (KILL.by: "you" / "wingmate" a player, "allies" an allied aircraft, her
-- escorts among them, "ships" / "defences" Comona's), her thanks or theirs
local function defended(S, T, now, A)
    local c = cfg()
    local at = A.r and A.r.at
    local flying = A.st == "route" or A.st == "final"
    if at and flying then
        local r = num(c.defended_km, 5) * 100000
        for _, p in ipairs(planes or {}) do
            if not p.down and p.at and not (ALLY and ALLY.unit and p.unit and ALLY.unit[p.unit]) then
                local dx, dy, dz = p.at.X - at.X, p.at.Y - at.Y, p.at.Z - at.Z
                if dx * dx + dy * dy + dz * dz <= r * r then
                    if not T.near[p] then T.nearList[#T.nearList + 1] = p end
                    T.near[p] = now
                end
            end
        end
    end
    for i = #T.nearList, 1, -1 do                                -- (in the order they came near: never pairs' order)
        local p = T.nearList[i]
        local t = T.near[p]
        if p.down or not t or now - t > 30 then table.remove(T.nearList, i) end
        if p.down and t then
            T.near[p] = nil
            if flying and now - t <= 8 and now >= T.defAt then
                local okB, by = pcall(KILL.by, p)
                by = okB and by or "you"
                local key = (by == "allies" and "defended_ally") or ((by == "ships" or by == "defences") and "defended_staff")
                    or "defended_you"
                if sayNow(S, key, nil, now) then
                    T.defAt = now + num(c.defended_gap_s, 20)
                    log(string.format("escort subs: %s shot down near CHARLENE by %s: %s", tostring(p.name), tostring(by), key))
                end
            end
        elseif t and now - t > 30 then T.near[p] = nil end
    end
end
-- her health: under each hurt_at mark once (hurt_<n>), and hit_drop points down within hit_window_s (hit, once in hit_gap_s)
local function health(S, T, now, A)
    local c = cfg()
    if not (A.seen and (A.st == "route" or A.st == "final" or A.st == "roll")) then return end
    local okP, pct = pcall(ESC.hpPct, S)
    pct = okP and tonumber(pct) or nil
    if not pct then return end
    local said = false
    for _, mark in ipairs(c.hurt_at or {}) do
        mark = math.floor(num(mark, 0))
        if pct <= mark and not T.hurt[mark] then
            T.hurt[mark] = true
            if not said then
                said = ESUB.say(S, "hurt_" .. mark)
                if said then log(string.format("escort subs: CHARLENE under %d%% (%d%%)", mark, pct)) end
            end
        end
    end
    local h = T.hpAt
    h[#h + 1] = { t = now, p = pct }
    while #h > 1 and now - h[1].t > num(c.hit_window_s, 3) do table.remove(h, 1) end
    local top = pct
    for _, e in ipairs(h) do top = math.max(top, e.p) end
    if said then
        T.hitAt, T.hpAt = now + num(c.hit_gap_s, 18), { { t = now, p = pct } }
    elseif top - pct >= num(c.hit_drop, 4) and now >= T.hitAt then
        if sayNow(S, "hit", nil, now) then T.hitAt = now + num(c.hit_gap_s, 18) end
        T.hpAt = { { t = now, p = pct } }
    end
end
function ESUB.tick(S, now)
    if not on() or S.test then return end
    local c = cfg()
    local T = ESUB.T
    if not T or T.S ~= S then
        T = { S = S, st = {}, waves = 0, hurt = {}, near = {}, nearList = {}, hpAt = {}, defAt = -1e9, hitAt = -1e9 }
        ESUB.T = T
        if ESUB.say(S, "go") then log("escort subs: CHARLENE and her escorts check in") end
    end
    local A = S.ac[1]
    if A.st == "lost" then T.st[A] = A.st; return end            -- (her loss: ESUB.finish)
    for _, B in ipairs(S.ac) do                                  -- each one's step
        local was = T.st[B]
        if was ~= B.st then
            T.st[B] = B.st
            if B.her then
                if B.st == "final" then ESUB.say(S, "final")
                elseif B.st == "roll" then ESUB.say(S, "touchdown")
                elseif B.st == "landed" then ESUB.say(S, "her_landed") end
            elseif B.escort then
                local own = (c.crew or {})[B.name] or {}
                if B.st == "lost" then
                    ESUB.say(S, "down." .. B.name, nil, { list = own.down, force = true })
                    -- ((2026-11-07) who answers its loss: its partner or its lead (crew.<NAME>.mourn), else escort_down)
                    if not ESUB.say(S, "mourn." .. B.name, nil, { list = own.mourn }) then
                        ESUB.say(S, "escort_down", { name = proper(B.name) })
                    end
                    if RUN and RUN.escort then                    -- (THE FESTIVAL's KMG lines: never one who's down)
                        RUN.escort.down = RUN.escort.down or {}
                        RUN.escort.down[B.name], RUN.dirty = true, true
                    end
                elseif B.st == "landed" and B.how ~= "timeout" then
                    ESUB.say(S, "landed." .. B.name, nil, { list = own.landed })
                end
            end
        end
    end
    local flying = A.st == "route" or A.st == "final"
    -- the first enemies sent at her: said once the check-ins are through (tried for 90 s)
    if not T.attacked and next(S.attackers or {}) then T.attacked = now end
    if type(T.attacked) == "number" and flying then
        if sayNow(S, "first_attack", nil, now) or now - T.attacked > 90 then T.attacked = true end
    end
    local n = S.reinf and S.reinf.n or 0                         -- each wave sent at her
    if n > T.waves then
        T.waves = n
        if flying then sayNow(S, "wave", { dir = S.reinf.dir or "?" }, now) end
    end
    health(S, T, now, A)
    defended(S, T, now, A)
end

---------------------------------------------------------------------------------------------------- the end
-- her line in pieces of at most `max`: after a comma where it can (a piece whole), else at words; the pieces joined by
-- single spaces are the line again
local function pieces(line, max)
    local bits = {}
    for b in line:gmatch("[^,]+,?") do
        b = b:gsub("^%s+", ""):gsub("%s+$", "")
        if b ~= "" then bits[#bits + 1] = b end
    end
    local out, cur = {}, ""
    local function put(w)
        if cur == "" then cur = w
        elseif #cur + 1 + #w <= max then cur = cur .. " " .. w
        else out[#out + 1] = cur; cur = w end
    end
    for _, b in ipairs(bits) do
        if #b <= max then put(b)
        else for w in b:gmatch("%S+") do put(w) end end
    end
    if cur ~= "" then out[#out + 1] = cur end
    return out
end
ESUB.pieces = pieces
function ESUB.finish(S, now, won, line)
    if not on() or S.test then return false end
    pcall(ESUB.tick, S, now)                                     -- (what changed this tick first: the last one down)
    if not won then
        if ESUB.say(S, "lost", nil, { force = true }) then log("escort subs: CHARLENE's loss") end
        return true
    end
    local parts = pieces(tostring(line or ""), math.max(40, math.floor(num(ec().thanks_chars, 125))))
    local who, n = ec().name or "CHARLENE", 0
    for _, p in ipairs(parts) do
        if SUB.say(who, p, math.max(4, math.min(9, 2 + #p / 18))) then n = n + 1 end
    end
    if n == 0 then return false end
    ESUB.say(S, "won")
    log(string.format("escort subs: her thanks in %d line%s, then Comona's", n, n == 1 and "" or "s"))
    return true
end

---------------------------------------------------------------------------------------------------- the Anomalies
local function has(list, k)
    for _, x in ipairs(type(list) == "table" and list or {}) do if x == k then return true end end
    return false
end
local function gate() local g = CFG.specials.anomaly_gate; return type(g) == "table" and g.enabled ~= false and g or nil end
-- whether the special `kind` may be drawn (sv_spawn.lua specialReady): an Anomaly of the gate's kinds only once
-- CHARLENE has landed at Comona, or (after_lost) once she's been shot down, or when THE ESCORT can't come this run
local waitSaid = {}
local function own(kind) local c = CFG.specials[kind]; return type(c) == "table" and c or {} end   -- (its own settings)
function ESC.anomalyOk(kind)
    local g = gate()
    if not g or not (has(g.kinds, kind) or own(kind).wait_for_charlene == true) then return true end
    local e = RUN and RUN.escort
    if e and e.arrived then return true end
    if e and e.lost then return g.after_lost ~= false end
    if not (has(CFG.specials.rotation, "escort") and type(specialOn) == "function" and specialOn("escort")
            and ESC.possible and ESC.possible()) then
        return true
    end
    local key = tostring(RUN) .. "|" .. tostring(kind)                -- (logged once a run each)
    if not waitSaid[key] then
        waitSaid[key] = true
        log(string.format("specials: the %s waits for CHARLENE to land at Comona (THE ESCORT %s)", tostring(kind),
            e and "is on" or "hasn't come yet"))
    end
    return false
end
-- the round's end: the next round's special drawn now (specialFor keeps its pick for that round, as the break's
-- announcement and startRound read it); one of warn_kinds and CHARLENE at Comona: her warning
function ESUB.warnNext(round, now)
    local g = gate()
    if not (g and g.warn ~= false and on() and type(specialFor) == "function") then return false end
    if D and D.forceSpecial then return false end                    -- (a test key's special: not drawn, not warned)
    if not (RUN and RUN.escort and RUN.escort.arrived) then return false end
    local okK, kind = pcall(specialFor, round)
    if not (okK and type(kind) == "string") then return false end
    local lines = own(kind).charlene_warn
    if not (has(g.warn_kinds, kind) or lines ~= nil) then return false end
    local said = ESUB.say(nil, "warn_" .. kind, nil, { force = true, now = now, list = lines })
    log(string.format("escort subs: round %d will be the %s: CHARLENE's warning %s", round, kind, said and "said" or "NOT said"))
    return said
end
end
