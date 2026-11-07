-- sv_kaska.lua: the Shuttle Launch round's intercepted channel (2026-11-08). Part of AC8 Survival Mode's runtime, run by
-- main.lua in MODULES' order: a name another part uses is a global of this mod's Lua state, its own helpers stay local.
--
-- The user, 2026-11-08: "Add enemy character subtitles in the Shuttle Launch Special Round"; "Kaska is not allowed to
-- talk to the players, make it seem that Kaska doesn't know that the players can see his conversations". KASKA (Emblem
-- Direct, launching the CORRIS shuttle the players defend) talks with his launch controller on a channel the players
-- overhear: INTERCEPT: KASKA and INTERCEPT: EMBDIR LAUNCH on the strip (CFG.hud.subs.speakers). The lines are the user's
-- own script, reviewed line by line: CFG.specials.shuttle.subs.
--   KASKA.tick(now, s)   (sv_rounds.lua specialTick, every tick of a shuttle round and its break; the host's or solo:
--                         SUB.say sends each line to the joiners) the moments: `start` as the countdown runs; `strike`
--                         as War's strike flights come up (strike_s at most); `marks` at those seconds left; `hit` as
--                         the shuttle's health falls under each hit_at mark; `launched` or `lost` at its end; `after`
--                         after_s into the break. Each moment one exchange of its list said whole (FISH.pick: one not
--                         said yet this run, sv_subs.lua's once a run), left out while the strip has more than busy_s
--                         waiting (a mark: mark_busy_s), so no line comes late.
-- Log: `kaska: <moment> (<why>)`.
KASKA = KASKA or {}
do
local function cfg() return ((CFG.specials or {}).shuttle or {}).subs or {} end
local function num(v, d) v = tonumber(v); if v == nil then return d end return v end
local S = nil                                            -- this shuttle round's (its special state table)
local function st(s)
    if not S or S.s ~= s then S = { s = s, marks = {}, hits = {} } end
    return S
end
-- an exchange of `list` (a list of lines, or a list of such lists: one of them) said whole; whether any line went
local function say(key, list, why)
    if type(list) ~= "table" then return false end
    local x = list
    if type(list[1]) == "table" then x = FISH.pick(list, "kaska." .. key) end
    if type(x) ~= "table" or (SUB.fresh and not SUB.fresh(x)) then return false end
    local any = false
    for _, line in ipairs(x) do
        local who, text = FISH.line(line)
        if SUB.say(who, text) then any = true end
    end
    if any then log(string.format("kaska: %s (%s)", key, tostring(why or ""))) end
    return any
end
local function room(now, max) return SUB.left(now) <= num(max, 8) end

function KASKA.tick(now, s)
    local c = cfg()
    if c.enabled == false or not (D and s and s.kind == "shuttle") then return end
    if COOP and COOP.client and COOP.client() then return end   -- (the host's lines reach the joiners)
    local K = st(s)
    if s.state == "countdown" then
        local cd = D.shuttleClock and D.shuttleClock.cd or (now - (s.at or now))
        local left = num((CFG.specials.shuttle or {}).countdown_s, 150) - cd
        if not K.start and cd >= 1 then
            K.start = true
            say("start", c.start, "the countdown runs")
        end
        if not K.strike then
            local up = false
            for u in pairs(D.strikeUnits or {}) do if D.up and D.up[u] then up = true end end
            if (up and cd >= 6) or cd >= num(c.strike_s, 30) then
                K.strike = true
                if room(now, c.busy_s) then say("strike", c.strike, up and "War's strike flights up" or "strike_s") end
            end
        end
        for _, m in ipairs(c.marks or {}) do
            local at = num(m[1], 0)
            if not K.marks[at] and left <= at then
                K.marks[at] = true                         -- (one passed by more than 5 s, the player down: not said late)
                if left > at - 5 and room(now, c.mark_busy_s or 5) then say("mark " .. at, m[2], at .. " s left") end
            end
        end
        if now >= (K.hpAt or 0) then
            K.hpAt = now + 1
            local hp = type(shuttleHealth) == "function" and shuttleHealth() or nil
            if type(hp) == "number" then
                for _, mark in ipairs(c.hit_at or {}) do
                    if not K.hits[mark] and hp < mark then
                        K.hits[mark] = true
                        if room(now, c.busy_s) then say("hit", c.hit, string.format("the shuttle at %d%%", hp)) end
                    end
                end
            end
        end
    elseif s.state == "done" then
        if not K.ended then
            K.ended = true
            say(s.lost and "lost" or "launched", s.lost and c.lost or c.launched, s.lost and "the shuttle lost" or "the shuttle away")
        end
        if D.state == "wait" and not K.after then
            K.afterAt = K.afterAt or (now + num(c.after_s, 8))
            if now >= K.afterAt and room(now, c.busy_s) then
                K.after = true
                say("after", c.after, "the break")
            end
        end
    end
end
end
