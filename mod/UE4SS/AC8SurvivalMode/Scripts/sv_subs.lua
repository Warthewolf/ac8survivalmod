-- sv_subs.lua: the subtitle strip and the results card (Survival's HUD, CFG.hud.subs / CFG.hud.card). Part of AC8 Survival
-- Mode's runtime, run by main.lua in MODULES' order; a name another part uses is a global of this mod's Lua state, its own
-- helpers stay local.
--
-- A global API any round can use (0.74.0; GONE FISHIN' and THE FESTIVAL first, FISHING_ROUND_PLAN.md 3.3's route 1):
--   SUB.say(speaker, text, secs)      queues a line: one on screen at a time, each for `secs` (nil: CFG.hud.subs.line_s),
--                                     in the order said; at most CFG.hud.subs.max_queue wait (more are dropped, logged).
--                                     On a co-op host inside the rounds' own logic (the host's round ticks) the line goes
--                                     to every joiner too ("sb", sv_coop.lua wraps SUB.say as it wraps hudCallout).
--   SUB.sayHere(speaker, text, secs)  the same on this game only, never sent (a line only this player should see)
--   SUB.clear(why)                    the line up and every line waiting dropped
--   SUB.busy()                        a line up or waiting
--   SUB.left(now)                     seconds until the last line waiting is done (0: nothing to say)
--   SUB.prio(who), SUB.fresh(line)    (2026-11-08) CFG.hud.subs.priority's speakers (AUDREY, VALKA): their lines go
--                                     before everyone else's (in the order said, an exchange with one of theirs whole),
--                                     another's line up gives way, a full queue never drops theirs. Every speaker's line
--                                     said once a run (once_a_run; repeat_ok: speakers who may repeat). SUB.fresh: whether
--                                     a raw line / exchange has none of its lines said yet (the pickers choose those)
--   SUB.card(title, lines, secs)      the results card (a title and up to CFG.hud.card.rows lines, centred, on a panel
--                                     like the run's summary) for `secs`; SUB.cardOff() takes it down
-- The strip is on screen only while a line is up (the user asked for fewer HUD warnings in 0.72.1): the speaker's name in
-- their colour (CFG.hud.subs.colors, by name; else `color`) over the line in white. Every line is logged (`subs: ...`).
-- Built by sv_hud.lua's hudBuild (SUB.build: its text maker passed in) and shown by its hudTick (SUB.hudTick); the queue
-- runs on hudTick's clock, so a pause holds it. The level going away drops what's waiting (LEVEL_DROPS).
SUB = { q = {}, cur = nil, cardUp = nil, dropped = 0, said = 0 }
do
local function cfg() return CFG.hud.subs or {} end
local function lineS(secs)
    local s = tonumber(secs) or tonumber(cfg().line_s) or 4
    return math.max(1, math.min(20, s))
end
-- ((2026-11-08) the user: "all of the Audrey and Valka subtitles must play One After Other, and they can't be reused, and
-- they take priority over everyone elses subtitles") CFG.hud.subs.priority's speakers: SUB.prio(who)
local function prioOf(who)
    local l = cfg().priority
    if type(l) ~= "table" then return false end
    local w = tostring(who or ""):upper()
    for _, p in ipairs(l) do if tostring(p):upper() == w then return true end end
    return false
end
SUB.prio = prioOf
-- their lines said this run (RUN's: a new run says them afresh)
local function usedLines()
    if type(RUN) == "table" then RUN.subsUsed = RUN.subsUsed or {}; return RUN.subsUsed end
    SUB.usedNoRun = SUB.usedNoRun or {}
    return SUB.usedNoRun
end
-- ((2026-11-08) the user, then: "do this for all characters actually have it so none of the characters repeat lines")
-- every speaker's line once a run (once_a_run), but a speaker in CFG.hud.subs.repeat_ok; a line with values in it
-- ({kg}, {dir}) is a repeat only word for word
local function onceOf(who)
    if cfg().once_a_run == false then return false end
    local w = tostring(who or ""):upper()
    for _, p in ipairs(cfg().repeat_ok or {}) do if tostring(p):upper() == w then return false end end
    return true
end
-- SUB.fresh(x): whether a raw line ("CODE|text"), or a list (an exchange, or lists of them), has none of its lines said
-- this run: the pickers (FISH.pick, sv_escort_subs.lua's) choose among the fresh ones only
function SUB.fresh(x)
    if cfg().once_a_run == false then return true end
    local u = usedLines()
    for _, s in ipairs(type(x) == "table" and x or { x }) do
        if type(s) == "table" then
            if not SUB.fresh(s) then return false end
        elseif type(s) == "string" then
            local code, text = s:match("^([%w _']+)|(.*)$")
            if not code then text = s end
            local who = code and ((cfg().speakers or {})[code] or code) or nil
            if u[text] and (who == nil or onceOf(who)) then return false end
        end
    end
    return true
end
local function add(speaker, text, secs, here)
    if cfg().enabled == false then return false end
    speaker, text = tostring(speaker or ""):sub(1, 32), tostring(text or ""):sub(1, 160)
    if text == "" then return false end
    local prio = prioOf(speaker)
    if onceOf(speaker) then                              -- (each line once a run)
        local u = usedLines()
        if u[text] then
            log(string.format("subs: %s's line was said already this run: not again: %s", speaker, text))
            return false
        end
        u[text] = true
    end
    local q = SUB.q
    if #q >= (tonumber(cfg().max_queue) or 16) then
        local drop = nil                                  -- (a full queue: another's last line waiting makes room for theirs)
        if prio then for i = #q, 1, -1 do if not q[i].prio then drop = i; break end end end
        if drop then
            local d = table.remove(q, drop)
            SUB.dropped = SUB.dropped + 1
            log(string.format("subs: the queue is full: %s's line dropped for %s's: %s", d.who, speaker, d.text))
        elseif not prio then
            SUB.dropped = SUB.dropped + 1
            log(string.format("subs: the queue is full (%d waiting): dropped %s: %s", #q, speaker, text))
            return false
        end                                               -- (theirs alone waiting: theirs over the limit, never dropped)
    end
    -- the priority lane: lines said together (in one tick: an exchange) stay together in their order, so an exchange with
    -- one of theirs in it goes ahead whole (the MC's line before AUDREY's reply with it), after the lane's lines waiting
    local batch = SUB.batch or 0
    local entry = { who = speaker, text = text, secs = lineS(secs), batch = batch }
    if prio or SUB.prioBatch == batch then
        local moved = {}
        if SUB.prioBatch ~= batch then                    -- (its batch's lines said before it, waiting at the back: with it)
            SUB.prioBatch = batch
            while q[#q] and q[#q].batch == batch and not q[#q].prio do table.insert(moved, 1, table.remove(q)) end
        end
        moved[#moved + 1] = entry
        local at = 1
        while q[at] and q[at].prio do at = at + 1 end
        for _, m in ipairs(moved) do m.prio = true; table.insert(q, at, m); at = at + 1 end
    else
        q[#q + 1] = entry
    end
    SUB.said = SUB.said + 1
    log(string.format("subs: %s%s: %s (%.1f s)", speaker, here and " (this game only)" or "", text, lineS(secs)))
    return true
end
function SUB.say(speaker, text, secs) return add(speaker, text, secs, false) end
function SUB.sayHere(speaker, text, secs) return add(speaker, text, secs, true) end
function SUB.clear(why)
    local n = #SUB.q + (SUB.cur and 1 or 0)
    SUB.q, SUB.cur = {}, nil
    if n > 0 then log(string.format("subs: %d line%s dropped (%s)", n, n == 1 and "" or "s", tostring(why or "?"))) end
    return n
end
function SUB.busy() return SUB.cur ~= nil or #SUB.q > 0 end
function SUB.left(now)
    local s = 0
    if SUB.cur then s = math.max(0, (SUB.cur.till or ((now or 0) + SUB.cur.secs)) - (now or 0)) end
    for _, l in ipairs(SUB.q) do s = s + l.secs end
    return s
end
function SUB.card(title, lines, secs)
    local rows = math.max(1, math.floor(tonumber((CFG.hud.card or {}).rows) or 9))
    local t = {}
    for i = 1, math.min(rows, #(lines or {})) do t[i] = tostring(lines[i]):sub(1, 90) end
    SUB.cardUp = { title = tostring(title or ""):sub(1, 60), lines = t, secs = math.max(1, tonumber(secs) or 12), till = nil }
    log(string.format("subs: card %s: %s", SUB.cardUp.title, table.concat(t, " | ")))
end
function SUB.cardOff() SUB.cardUp = nil end

-- (sv_hud.lua hudBuild) the strip and the card on canvas; mk.text(name, justify, spacing) is the HUD's text maker
local function panel(canvas, name, x, y, w, h, fill, edge, px, mkBar)
    local p = newWidget("CanvasPanel", name)
    local slot = slotIn(canvas, p, { 0, 0 }, { 0, 0 }, { x, y, w, h }, { 0.5, 0 }, false)
    local f = newWidget("Image", name .. "Fill")
    f:SetColorAndOpacity({ R = fill[1], G = fill[2], B = fill[3], A = fill[4] or 0.8 })
    slotIn(p, f, { 0, 0 }, { 1, 1 }, { 0, 0, 0, 0 }, { 0, 0 }, false)
    if px > 0 and mkBar then
        mkBar(p, { 0, 0 }, { 1, 0 }, { 0, 0, 0, px }, edge)
        mkBar(p, { 0, 1 }, { 1, 1 }, { 0, -px, 0, px }, edge)
        mkBar(p, { 0, 0 }, { 0, 1 }, { 0, 0, px, 0 }, edge)
        mkBar(p, { 1, 0 }, { 1, 1 }, { -px, 0, px, 0 }, edge)
    end
    p:SetVisibility(VIS.Collapsed)
    return p, slot
end
function SUB.build(canvas, mk)
    local c, cc, sm = cfg(), CFG.hud.card or {}, CFG.hud.summary
    local mid = DESIGN_W / 2
    local w, h, y = tonumber(c.w) or 1560, tonumber(c.h) or 150, tonumber(c.y) or 1700
    H.subPanel, H.subPanelSlot = panel(canvas, "SubPanel", mid, y, w, h, c.fill or { 0.02, 0.10, 0.04, 0.7 }, c.edge or sm.edge,
        tonumber(c.edge_px) or 3, mk.bar)
    H.subW, H.subH = w, h
    H.subWho = mk.text("SubWho", 1, CFG.hud.banner_letter_spacing)
    slotIn(canvas, H.subWho, { 0, 0 }, { 0, 0 }, { mid, y + (tonumber(c.speaker_dy) or 12), 0, 0 }, { 0.5, 0 }, true)
    H.subText = mk.text("SubText", 1, CFG.hud.letter_spacing)
    slotIn(canvas, H.subText, { 0, 0 }, { 0, 0 }, { mid, y + (tonumber(c.text_dy) or 58), 0, 0 }, { 0.5, 0 }, true)
    -- ((2026-11-07) the user's screenshots: with AutoWrapText on an auto-sized slot the text wrapped at the width its
    -- last line had taken, narrower each time (two or three words a line) and ran out under the box. Now a fixed wrap at
    -- the box's width less 80, AutoWrapText off, and the box grown to the line count: hudTick)
    pcall(function() H.subText:SetAutoWrapText(false) end)
    pcall(function() H.subText:SetWrapTextAt(w - 80) end)
    local white = c.text_color or { 1, 1, 1 }
    pcall(function() H.subText:SetColorAndOpacity({ SpecifiedColor = { R = white[1], G = white[2], B = white[3], A = 1 }, ColorUseRule = 0 }) end)
    H.subWho:SetVisibility(VIS.Collapsed); H.subText:SetVisibility(VIS.Collapsed)
    -- the card: as the run's summary (CFG.hud.summary's fill and edge), a title and its rows
    local cw, cy, rows = tonumber(cc.w) or 1500, tonumber(cc.y) or 270, math.max(1, math.floor(tonumber(cc.rows) or 9))
    local line = CFG.hud.line
    local ch = (tonumber(cc.top) or 110) + rows * line + (tonumber(cc.bottom) or 40)
    H.cardPanel, H.cardSlot = panel(canvas, "CardPanel", mid, cy, cw, ch, sm.fill, sm.edge, sm.edge_px, mk.bar)
    H.cardW = cw
    H.cardTitle = mk.text("CardTitle", 1, CFG.hud.banner_letter_spacing)
    slotIn(canvas, H.cardTitle, { 0, 0 }, { 0, 0 }, { mid, cy + 36, 0, 0 }, { 0.5, 0 }, true)
    H.cardLines = {}
    for i = 1, rows do
        local t = mk.text("CardLine" .. i)
        slotIn(canvas, t, { 0, 0 }, { 0, 0 }, { mid, cy + (tonumber(cc.top) or 110) + (i - 1) * line, 0, 0 }, { 0.5, 0 }, true)
        t:SetVisibility(VIS.Collapsed)
        H.cardLines[i] = t
    end
    H.cardTitle:SetVisibility(VIS.Collapsed)
end

-- How many lines `text` takes wrapped at `wrap` design units with the font's em at `em` units (whole words, as the
-- TextBlock wraps them). ((2026-11-07) it counted 60 characters a line, so a 63-character line that fits on one got a
-- two-line box (the user's screenshot). A proportional font's advance widths in ems (a sans serif's: i / l / . narrow,
-- m / w / capitals wide); their em fitted to four lines of that session's screenshots, 48.3-49.7 units, so em_units 50
-- leaves a box at worst a little big, never short.)
local EM = { [" "] = .278, ["."] = .278, [","] = .278, [":"] = .278, [";"] = .278, ["'"] = .191, ["!"] = .278,
             ["?"] = .556, ["-"] = .333, i = .222, l = .222, j = .222, f = .278, t = .278, r = .333, m = .833, w = .722,
             I = .278, M = .833, W = .944 }
local function ems(s)
    local t = 0
    for ch in s:gmatch(".") do
        t = t + (EM[ch] or (ch:match("%u") and .667) or .556)
    end
    return t
end
SUB.ems = ems
function SUB.lineCount(text, wrap, em)
    wrap = math.max(100, tonumber(wrap) or 1480)
    em = math.max(1, tonumber(em) or 50)
    local n, len, space = 1, 0, EM[" "] * em
    for word in tostring(text or ""):gmatch("%S+") do
        local w = ems(word) * em
        if len == 0 then len = w
        elseif len + space + w <= wrap then len = len + space + w
        else n, len = n + 1, w end
        while len > wrap do n, len = n + 1, len - wrap end
    end
    return n
end
-- ((2026-11-11) the user's screenshots of 0.74.4x: the strip's text didn't wrap at all, one line running past both sides
-- of the box (which had grown to two lines): SetWrapTextAt takes no effect in game. So the strip's text is broken into
-- lines here, at whole words, each at most `wrap` units wide by the same model, and the box grown to that many.)
-- SUB.wrap(text, wrap, em) -> the text with "\n" between its lines, the line count. A word wider than wrap keeps a line
-- of its own. Three lines the screenshots measured came out 2.5 % under to 3 % over the model, so the strip breaks
-- WRAP_PAD (120) inside the box rather than the 80 of its old wrap: a line the model puts at 1,440 is at most ~1,477.
local WRAP_PAD = 120
SUB.wrapPad = WRAP_PAD                                -- (the tests measure at the strip's own width)
function SUB.wrap(text, wrap, em)
    wrap = math.max(100, tonumber(wrap) or 1440)
    em = math.max(1, tonumber(em) or 50)
    local lines, cur, len, space = {}, {}, 0, EM[" "] * em
    for word in tostring(text or ""):gmatch("%S+") do
        local w = ems(word) * em
        if #cur > 0 and len + space + w > wrap then
            lines[#lines + 1] = table.concat(cur, " ")
            cur, len = {}, 0
        end
        len = (#cur > 0) and (len + space + w) or w
        cur[#cur + 1] = word
    end
    if #cur > 0 or #lines == 0 then lines[#lines + 1] = table.concat(cur, " ") end
    return table.concat(lines, "\n"), #lines
end
local function colorOf(who)
    local c = cfg()
    local col = type(c.colors) == "table" and c.colors[who] or nil
    return type(col) == "table" and col or c.color or CFG.hud.color
end
local function show(w, on)
    if w then pcall(function() w:SetVisibility(on and VIS.HitTestInvisible or VIS.Collapsed) end) end
end
-- (sv_hud.lua hudTick, on its clock) the queue's next line once the last is done; the strip and the card on screen while
-- they've something and the HUD's up (shown); the card not over the run's summary or the info wall (wallOpen)
function SUB.hudTick(now, shown, wallOpen)
    local cur = SUB.cur
    SUB.batch = (SUB.batch or 0) + 1                     -- (lines said before the next tick: one batch, kept together)
    if cur and cur.till and now >= cur.till then SUB.cur, cur = nil, nil end
    -- ((2026-11-08) another speaker's line on the strip gives way to a priority speaker's waiting, once it's been up
    -- prio_min_s: dropped, not shown again)
    local head = SUB.q[1]
    if cur and not cur.prio and head and head.prio and cur.from and now - cur.from >= (tonumber(cfg().prio_min_s) or 1) then
        log(string.format("subs: %s's line gave way to %s's: %s", cur.who, head.who, cur.text))
        SUB.cur, cur = nil, nil
    end
    if not cur and #SUB.q > 0 and shown then
        cur = table.remove(SUB.q, 1)
        cur.till, cur.from = now + cur.secs, now
        SUB.cur = cur
        local blip = cfg().blip
        if type(blip) == "string" and blip ~= "" and SHOP and SHOP.sound then pcall(SHOP.sound, blip) end
    end
    if not (H and H.subPanel) then return end
    local on = cur ~= nil and shown
    if on then
        setText(H.subWho, "subWhoStr", cur.who:upper())
        if not cur.shown then                            -- (its lines broken here once: SUB.wrap)
            cur.shown, cur.nLines = SUB.wrap(cur.text, (H.subW or 1560) - WRAP_PAD, cfg().em_units)
        end
        setText(H.subText, "subTextStr", cur.shown)
        if H.subSized ~= cur and H.subPanelSlot then     -- (the box grown to the line's lines)
            H.subSized = cur
            local c = cfg()
            local hh = (H.subH or 150) + ((cur.nLines or 1) - 1) * (tonumber(c.line_h) or CFG.hud.line or 68)
            pcall(function() H.subPanelSlot:SetSize({ X = H.subW or 1560, Y = hh }) end)
        end
        if H.subWhoCol ~= cur.who then
            H.subWhoCol = cur.who
            local col = colorOf(cur.who)
            pcall(function() H.subWho:SetColorAndOpacity({ SpecifiedColor = { R = col[1], G = col[2], B = col[3], A = 1 }, ColorUseRule = 0 }) end)
        end
    end
    if H.subOn ~= on then
        H.subOn = on
        show(H.subPanel, on); show(H.subWho, on); show(H.subText, on and true or false)
    end
    local cd = SUB.cardUp
    if cd and cd.till and now >= cd.till then SUB.cardUp, cd = nil, nil end
    local cardOn = cd ~= nil and shown and not wallOpen and LB.show == nil
    if cardOn and not cd.till then cd.till = now + cd.secs end
    if cardOn then
        setText(H.cardTitle, "cardTitleStr", cd.title)
        for i, t in ipairs(H.cardLines or {}) do setText(t, "cardLineStr" .. i, cd.lines[i] or "") end
    end
    local key = cardOn and cd or false                 -- (a new card while one's up: its rows shown afresh)
    if H.cardOn ~= key then
        H.cardOn = key
        if cardOn and H.cardSlot then                 -- ((2026-11-07) the card as tall as its rows, not its most)
            local cc, used = CFG.hud.card or {}, 0
            for i = 1, #(H.cardLines or {}) do if (cd.lines[i] or "") ~= "" then used = i end end
            local ch = (tonumber(cc.top) or 110) + math.max(1, used) * CFG.hud.line + (tonumber(cc.bottom) or 40)
            pcall(function() H.cardSlot:SetSize({ X = H.cardW or 1500, Y = ch }) end)
        end
        show(H.cardPanel, cardOn); show(H.cardTitle, cardOn)
        for i, t in ipairs(H.cardLines or {}) do show(t, cardOn and (cd.lines[i] or "") ~= "") end
    end
end

-- (the teardown gate's drop, sv_core.lua levelDrop: nothing of the level's to say any more)
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["subtitles"] = function() SUB.q, SUB.cur, SUB.cardUp = {}, nil, nil end end
end
