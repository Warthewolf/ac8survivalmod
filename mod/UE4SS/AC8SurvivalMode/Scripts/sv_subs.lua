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
local function add(speaker, text, secs, here)
    if cfg().enabled == false then return false end
    speaker, text = tostring(speaker or ""):sub(1, 32), tostring(text or ""):sub(1, 160)
    if text == "" then return false end
    local q = SUB.q
    if #q >= (tonumber(cfg().max_queue) or 16) then
        SUB.dropped = SUB.dropped + 1
        log(string.format("subs: the queue is full (%d waiting): dropped %s: %s", #q, speaker, text))
        return false
    end
    q[#q + 1] = { who = speaker, text = text, secs = lineS(secs) }
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
    if cur and cur.till and now >= cur.till then SUB.cur, cur = nil, nil end
    if not cur and #SUB.q > 0 and shown then
        cur = table.remove(SUB.q, 1)
        cur.till = now + cur.secs
        SUB.cur = cur
        local blip = cfg().blip
        if type(blip) == "string" and blip ~= "" and SHOP and SHOP.sound then pcall(SHOP.sound, blip) end
    end
    if not (H and H.subPanel) then return end
    local on = cur ~= nil and shown
    if on then
        setText(H.subWho, "subWhoStr", cur.who:upper())
        setText(H.subText, "subTextStr", cur.text)
        if H.subSized ~= cur and H.subPanelSlot then     -- (the box grown to the line's wrapped lines)
            H.subSized = cur
            local c = cfg()
            local n = SUB.lineCount(cur.text, (H.subW or 1560) - 80, c.em_units)
            local hh = (H.subH or 150) + (n - 1) * (tonumber(c.line_h) or CFG.hud.line or 68)
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
