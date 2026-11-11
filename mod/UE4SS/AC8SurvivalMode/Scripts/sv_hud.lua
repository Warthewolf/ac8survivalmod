-- sv_hud.lua: Survival's HUD (round, credits, callouts, warnings).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- Font for one of our texts: UI_FontSet_ja, then the HUD typeface, size, spacing and glow outline written into the
-- text's own Font and pushed with SetFont (test 13b: that gives the game's HUD face; the SetFont table alone may not).
local function styleText(t, spacing)
    local hc = CFG.hud
    if H.font then t:SetFont({ FontObject = H.font, TypefaceFontName = FName("HUD"), Size = hc.font_size, LetterSpacing = spacing })
    else pcall(function() t.Font.Size = hc.font_size end) end
    local ok, err = pcall(function()
        local f = t.Font
        f.TypefaceFontName = FName("HUD"); f.Size = hc.font_size; f.LetterSpacing = spacing
        t:SetFont(f)
    end)
    if not ok then hudLog("fontfields", "could not set the font fields (" .. tostring(err) .. ")") end
    if hc.glow_size > 0 then
        ok, err = pcall(function()
            local o = t.Font.OutlineSettings
            o.OutlineSize = hc.glow_size
            o.OutlineColor = { R = hc.color[1], G = hc.color[2], B = hc.color[3], A = hc.glow_alpha }
            t:SetFont(t.Font)
        end)
        if not ok then hudLog("glow", "could not set the glow outline (" .. tostring(err) .. ")") end
    end
end

local function newText(name, justify, spacing)
    local t = newWidget("TextBlock", name)
    local hc = CFG.hud
    spacing = spacing or hc.letter_spacing
    styleText(t, spacing)
    t:SetColorAndOpacity({ SpecifiedColor = { R = hc.color[1], G = hc.color[2], B = hc.color[3], A = 1 }, ColorUseRule = 0 })
    t:SetRenderOpacity(hc.opacity)
    t:SetJustification(justify or 0)                 -- ETextJustify: 0 left, 1 centre
    t:SetText(toText(""))
    H.texts[#H.texts + 1] = { w = t, spacing = spacing }
    return t
end

local function newBar(canvas, a0, a1, off, color)
    local b = newWidget("Image", "Bar")
    local c = color or CFG.hud.color
    b:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 1 })   -- no brush texture: a plain quad, as the game's bars
    b:SetRenderOpacity(CFG.hud.opacity)
    slotIn(canvas, b, a0, a1, off, { 0, 0 }, false)
end

local function fontFace(t)         -- typeface name a text actually has (for the log)
    local ok, s = pcall(function() return t.Font.TypefaceFontName:ToString() end)
    return ok and s or "?"
end

-- The info key (CFG.hud.info): the info wall open or not (the key flips it, hudTick applies it; each level starts with
-- start_open). The corner's stack (NEXT, ALLIES, ITEMS, CO-OP, from y 516) ends above the game's minimap (top 1108:
-- docs/re/HUD_LAYOUT.md); the wall has a row for every player: up to 24, in two columns (header, 12 rows, a gap, the
-- allies, the items and the kills: 17 of WALL_ROWS).
local info = { open = CFG.hud.info.start_open == true }
local WALL_ROWS = 20

-- The info wall's widgets (hudBuild): a panel as the run's summary's (CFG.hud.summary's fill and edge), a centred title,
-- WALL_ROWS rows of two texts (a and b, the second column's), a footer; all collapsed, placed by wallTick
local function wallBuild(canvas)
    local hc, sm = CFG.hud, CFG.hud.summary
    local panel = newWidget("CanvasPanel", "WallPanel")
    H.wallSlot = slotIn(canvas, panel, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, 0, hc.wall.w, 400 }, { 0.5, 0 }, false)
    local fill = newWidget("Image", "WallFill")
    fill:SetColorAndOpacity({ R = sm.fill[1], G = sm.fill[2], B = sm.fill[3], A = sm.fill[4] })
    slotIn(panel, fill, { 0, 0 }, { 1, 1 }, { 0, 0, 0, 0 }, { 0, 0 }, false)
    local e = sm.edge_px
    newBar(panel, { 0, 0 }, { 1, 0 }, { 0, 0, 0, e }, sm.edge)          -- top
    newBar(panel, { 0, 1 }, { 1, 1 }, { 0, -e, 0, e }, sm.edge)         -- bottom
    newBar(panel, { 0, 0 }, { 0, 1 }, { 0, 0, e, 0 }, sm.edge)          -- left
    newBar(panel, { 1, 0 }, { 1, 1 }, { -e, 0, e, 0 }, sm.edge)         -- right
    H.wallPanel = panel
    local function centred(name, spacing)
        local t = newText(name, 1, spacing)
        return t, slotIn(canvas, t, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, 0, 0, 0 }, { 0.5, 0 }, true)
    end
    H.wallTitle, H.wallTitleSlot = centred("WallTitle", hc.banner_letter_spacing)
    H.wallRows = {}
    for i = 1, WALL_ROWS do
        local r = {}
        r.a, r.sa = centred("WallA" .. i)
        r.b, r.sb = centred("WallB" .. i)
        H.wallRows[i] = r
    end
    H.wallFoot, H.wallFootSlot = centred("WallFoot")
    panel:SetVisibility(VIS.Collapsed); H.wallTitle:SetVisibility(VIS.Collapsed); H.wallFoot:SetVisibility(VIS.Collapsed)
    for _, r in ipairs(H.wallRows) do r.a:SetVisibility(VIS.Collapsed); r.b:SetVisibility(VIS.Collapsed) end
end

local function hudBuild(pc)
    local wbl = cdo("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not wbl then error("WidgetBlueprintLibrary not found") end
    local cls, why = loadObject(HUD_ASSET.base)
    if not cls then error("base widget class not loaded (" .. tostring(why) .. ")") end
    local w = wbl:Create(pc, cls, pc)
    if not valid(w) then error("WidgetBlueprintLibrary.Create returned nothing") end
    H = { widget = w, tree = w.WidgetTree, shown = nil, texts = {} }
    local root = H.tree.RootWidget
    for i = root:GetChildrenCount() - 1, 0, -1 do root:GetChildAt(i):SetVisibility(VIS.Collapsed) end   -- its own banner
    local font
    font, why = loadObject(HUD_ASSET.font)
    H.font = font
    if not font then hudLog("font", "HUD font not loaded (" .. tostring(why) .. "); using the default font") end

    local scale = newWidget("ScaleBox", "Scale")
    scale:SetStretch(2)                                     -- EStretch::ScaleToFit
    slotIn(root, scale, { 0, 0 }, { 1, 1 }, { 0, 0, 0, 0 }, { 0, 0 }, false)
    local size = newWidget("SizeBox", "Size")
    size:SetWidthOverride(DESIGN_W); size:SetHeightOverride(DESIGN_H)
    scale:SetContent(size)
    local canvas = newWidget("CanvasPanel", "Canvas")
    size:SetContent(canvas)
    H.canvas = canvas

    local hc = CFG.hud
    -- rows: ROUND, CREDITS, AIRFIELD (with its bar), NEXT ROUND (between rounds)
    H.round = newText("Round"); H.next = newText("Next")
    slotIn(canvas, H.round, { 0, 0 }, { 0, 0 }, { hc.x, hc.y, 0, 0 }, { 0, 0 }, true)
    local rowY = hc.y + hc.line
    H.credits = newText("Credits")
    slotIn(canvas, H.credits, { 0, 0 }, { 0, 0 }, { hc.x, rowY, 0, 0 }, { 0, 0 }, true)
    rowY = rowY + hc.line
    if CFG.airfield.enabled then       -- AIRFIELD: [=====     ] 85
        local ab, airY = hc.airfield_bar, rowY
        rowY = rowY + hc.line
        H.air = newText("Airfield")
        slotIn(canvas, H.air, { 0, 0 }, { 0, 0 }, { hc.x, airY, 0, 0 }, { 0, 0 }, true)
        local bar = newWidget("CanvasPanel", "AirBar")
        slotIn(canvas, bar, { 0, 0 }, { 0, 0 }, { hc.x + ab.x, airY + ab.dy, ab.w, ab.h }, { 0, 0 }, false)
        newBar(bar, { 0, 0 }, { 1, 0 }, { 0, 0, 0, ab.frame })
        newBar(bar, { 0, 1 }, { 1, 1 }, { 0, -ab.frame, 0, ab.frame })
        newBar(bar, { 0, 0 }, { 0, 1 }, { 0, 0, ab.frame, 0 })
        newBar(bar, { 1, 0 }, { 1, 1 }, { -ab.frame, 0, ab.frame, 0 })
        local fill = newWidget("Image", "AirFill")
        local c = CFG.hud.color
        fill:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 1 })
        fill:SetRenderOpacity(CFG.hud.opacity)
        local inset = ab.frame * 2
        H.airFillW, H.airFillH = ab.w - inset * 2, ab.h - inset * 2
        H.airFillSlot = slotIn(bar, fill, { 0, 0 }, { 0, 0 }, { inset, inset, H.airFillW, H.airFillH }, { 0, 0 }, false)
        H.airFill, H.airBar = fill, bar
        H.airNum = newText("AirfieldHP")
        slotIn(canvas, H.airNum, { 0, 0 }, { 0, 0 }, { hc.x + ab.x + ab.w + 20, airY, 0, 0 }, { 0, 0 }, true)
    end
    -- NEXT ROUND / the special's row, then ALLIES and ITEMS (the review build's): each shown only with something in it,
    -- stacked from here down in that order (stackRows). With the info key (CFG.hud.info) NEXT comes first, so it stays
    -- put while the info rows peek, and CO-OP last; without it CO-OP is first, as before.
    H.allies = newText("Allies"); H.items = newText("Items")
    H.coop = newText("Coop")                               -- CO-OP: who is playing (sv_coop.lua COOP.hudLine)
    H.peek = {}
    local rows = hc.info.enabled and { H.next, H.allies, H.items, H.coop } or { H.coop, H.next, H.allies, H.items }
    H.stackY, H.stack = rowY, {}
    for _, w in ipairs(rows) do
        H.stack[#H.stack + 1] = { w = w, slot = slotIn(canvas, w, { 0, 0 }, { 0, 0 }, { hc.x, rowY, 0, 0 }, { 0, 0 }, true) }
        w:SetVisibility(VIS.Collapsed)
    end
    -- the info wall (before the banner, which draws over it); each level starts with it as start_open says
    if hc.info.enabled then
        wallBuild(canvas)
        info.open = hc.info.start_open == true
    end

    -- (0.74.0) the subtitle strip and the results card (sv_subs.lua SUB.build), under the banner
    if SUB and SUB.build then
        local okS, errS = pcall(SUB.build, canvas, { text = newText, bar = newBar })
        if not okS then hudLog("subs", "the subtitle strip not built: " .. tostring(errS)) end
    end
    -- callout banner: a box of 4 px bars around centred text, centred at (1920, banner_y), width set per message
    local banner = newWidget("CanvasPanel", "Banner")
    H.bannerSlot = slotIn(canvas, banner, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, hc.banner_y, 390, 69 }, { 0.5, 0.5 }, false)
    newBar(banner, { 0, 0 }, { 1, 0 }, { 0, 0, 0, 4 })        -- top
    newBar(banner, { 0, 1 }, { 1, 1 }, { 0, -4, 0, 4 })       -- bottom
    newBar(banner, { 0, 0 }, { 0, 1 }, { 0, 0, 4, 0 })        -- left
    newBar(banner, { 1, 0 }, { 1, 1 }, { -4, 0, 4, 0 })       -- right
    H.bannerText = newText("BannerText", 1, hc.banner_letter_spacing)
    slotIn(banner, H.bannerText, { 0.5, 0.5 }, { 0.5, 0.5 }, { 0, 0.5, 0, 0 }, { 0.5, 0.5 }, true)
    H.banner = banner
    H.sub = newText("BannerSub", 1, hc.banner_letter_spacing)
    slotIn(canvas, H.sub, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, hc.banner_y + 34 + 40, 0, 0 }, { 0.5, 0 }, true)
    banner:SetVisibility(VIS.Collapsed); H.sub:SetVisibility(VIS.Collapsed)

    -- the end-of-run summary (LB.show): a title and its lines, centred, under the banner, on a panel behind them
    local sm = hc.summary
    H.lbPanel = newWidget("CanvasPanel", "LbPanel")
    slotIn(canvas, H.lbPanel, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, sm.y, sm.w, sm.h }, { 0.5, 0 }, false)
    local fill = newWidget("Image", "LbFill")
    fill:SetColorAndOpacity({ R = sm.fill[1], G = sm.fill[2], B = sm.fill[3], A = sm.fill[4] })
    slotIn(H.lbPanel, fill, { 0, 0 }, { 1, 1 }, { 0, 0, 0, 0 }, { 0, 0 }, false)
    local e = sm.edge_px
    newBar(H.lbPanel, { 0, 0 }, { 1, 0 }, { 0, 0, 0, e }, sm.edge)          -- top
    newBar(H.lbPanel, { 0, 1 }, { 1, 1 }, { 0, -e, 0, e }, sm.edge)         -- bottom
    newBar(H.lbPanel, { 0, 0 }, { 0, 1 }, { 0, 0, e, 0 }, sm.edge)          -- left
    newBar(H.lbPanel, { 1, 0 }, { 1, 1 }, { -e, 0, e, 0 }, sm.edge)         -- right
    H.lbPanel:SetVisibility(VIS.Collapsed)
    H.lbTitle = newText("LbTitle", 1, hc.banner_letter_spacing)
    slotIn(canvas, H.lbTitle, { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, 560, 0, 0 }, { 0.5, 0 }, true)
    H.lbLines = {}
    for i = 1, 8 do
        H.lbLines[i] = newText("LbLine" .. i)
        slotIn(canvas, H.lbLines[i], { 0, 0 }, { 0, 0 }, { DESIGN_W / 2, 560 + 30 + i * hc.line, 0, 0 }, { 0.5, 0 }, true)
    end
    H.lbTitle:SetVisibility(VIS.Collapsed)
    for _, l in ipairs(H.lbLines) do l:SetVisibility(VIS.Collapsed) end
    w:AddToViewport(hc.zorder)
    w:SetVisibility(VIS.HitTestInvisible)
    H.shown = true
    log(string.format("hud: built (base %s, font %s, typeface %s, %d widgets)", nameOf(w):match("[^%.:]+$") or "?",
        font and "UI_FontSet_ja" or "default", fontFace(H.round), hudGen))
end

callouts = {}                -- waiting callouts, shown one after another

function hudCallout(text, sub, big)   -- shown on the next HUD tick (callers are in roundsTick); big: a scale
    if #callouts < 4 then callouts[#callouts + 1] = { text = text, sub = sub, big = big } end
    log("hud: callout '" .. text .. "'" .. (sub and (" / '" .. sub .. "'") or ""))
end

function setText(w, key, s)
    if H[key] == s then return end
    H[key] = s
    w:SetText(toText(s))
end

local function clock(s)
    s = math.max(0, math.ceil(s))
    return string.format("%d:%02d", s // 60, s % 60)
end

-- The stacked rows (NEXT, ALLIES, ITEMS): the shown ones one line apart from H.stackY, moved only when that changes
local function stackRows()
    local y, key = H.stackY, ""
    for _, r in ipairs(H.stack or {}) do key = key .. (r.shown and "1" or "0") end
    if key == H.stackKey then return end
    H.stackKey = key
    for _, r in ipairs(H.stack) do
        if r.shown then
            pcall(function() r.slot:SetOffsets({ Left = CFG.hud.x, Top = y, Right = 0, Bottom = 0 }) end)
            y = y + CFG.hud.line
        end
    end
end

-- One stacked row: shown with text s, collapsed with none
local function stackText(w, key, s)
    for _, r in ipairs(H.stack or {}) do
        if r.w == w then
            if s then setText(w, key, s) end
            local shown = s ~= nil
            if r.shown ~= shown then r.shown = shown; w:SetVisibility(shown and VIS.HitTestInvisible or VIS.Collapsed) end
        end
    end
end

-- One info row (CFG.hud.info): text s shown for peek_s once its news (what it says that's worth a look, not a count
-- that keeps ticking; the text itself without one) differs from the last, or it comes back; else collapsed, and always
-- while the info wall is open (it holds all of it). A peek waits for the HUD to be up (H.shown: not paused, a plane, the
-- game HUD on; solo that covers the STORE, which pauses, but in co-op it doesn't pause: untested there); news seen with
-- the wall open is no peek once it's shut. True if shown.
local function infoRow(w, key, s, news, now)
    local ic = CFG.hud.info
    if not ic.enabled then stackText(w, key, s); return s ~= nil end
    local pk = H.peek[key] or {}
    H.peek[key] = pk
    news = news or s
    if s == nil then pk.news, pk.due, pk.till = nil, nil, nil
    elseif news ~= pk.news then pk.news, pk.due = news, true end
    if pk.due and H.shown then pk.due, pk.till = nil, (not info.open) and now + ic.peek_s or nil end
    local shown = s ~= nil and not info.open and pk.till ~= nil and now < pk.till
    stackText(w, key, shown and s or nil)
    return shown
end

-- COOP.hudLine's row and its news; nil solo (sv_coop.lua loads after this part)
local function coopLine()
    if COOP and COOP.hudLine then return COOP.hudLine() end
    return nil
end

-- The info wall's rows: { a = text } across the middle, or { a, b } a player in each column; co-op's players first
-- (COOP.wallInfo: a line each, in two columns from CFG.hud.wall.cols_from), then the allies, the items and the run's
-- kills. -> the rows, and whether the players take two columns
local function wallRows(now)
    local t, wc, rows, two = CFG.hud.text, CFG.hud.wall, {}, false
    local okC, co = pcall(function() return COOP and COOP.wallInfo and COOP.wallInfo() end)
    if not okC then hudLog("wallcoop", "info wall: co-op error " .. tostring(co)); co = nil end
    if co then
        rows[#rows + 1] = { a = co.header }
        local p = co.players or {}
        two = #p >= wc.cols_from
        local half = two and math.ceil(#p / 2) or #p
        for i = 1, half do rows[#rows + 1] = { a = p[i], b = two and (p[half + i] or "") or nil } end
        rows[#rows + 1] = { a = "" }
    end
    local okA, al = pcall(ALLY.hudLine)
    rows[#rows + 1] = { a = string.format(t.wall_allies, (okA and al) or t.wall_none) }
    local okI, it = pcall(TAC.line, now)
    rows[#rows + 1] = { a = string.format(t.wall_items, (okI and it) or t.wall_none) }
    if not (okA and okI) then hudLog("wallerr", "info wall: allies / items error " .. tostring(okA and it or al)) end
    local k = RUN and RUN.kills or {}
    rows[#rows + 1] = { a = string.format(t.wall_kills, k.you or 0, k.allies or 0, k.ships or 0, k.defences or 0) }
    return rows, two
end

-- The info wall on screen while it's open (and the run's summary isn't up): its rows read, the panel as tall as they
-- need and as wide as the columns, centred on CFG.hud.wall.y_mid; widgets moved only when the shape changes
local function wallTick(now, open)
    if not H.wallPanel then return end
    if not open then
        if H.wallOn then
            H.wallOn = false
            H.wallPanel:SetVisibility(VIS.Collapsed); H.wallTitle:SetVisibility(VIS.Collapsed); H.wallFoot:SetVisibility(VIS.Collapsed)
            for _, r in ipairs(H.wallRows) do
                if r.aOn then r.aOn = false; r.a:SetVisibility(VIS.Collapsed) end
                if r.bOn then r.bOn = false; r.b:SetVisibility(VIS.Collapsed) end
            end
        end
        return
    end
    local rows, two = wallRows(now)
    local hc, wc, t = CFG.hud, CFG.hud.wall, CFG.hud.text
    local n = math.min(#rows, WALL_ROWS)
    local w, h = two and wc.w2 or wc.w, wc.top + n * hc.line + wc.bottom
    local y0 = math.floor(wc.y_mid - h / 2)
    local mid = DESIGN_W / 2
    local shape = n .. (two and "/2" or "/1")
    if shape ~= H.wallShape then
        H.wallShape = shape
        pcall(function() H.wallSlot:SetOffsets({ Left = mid, Top = y0, Right = w, Bottom = h }) end)
        pcall(function() H.wallTitleSlot:SetOffsets({ Left = mid, Top = y0 + wc.title_dy, Right = 0, Bottom = 0 }) end)
        pcall(function() H.wallFootSlot:SetOffsets({ Left = mid, Top = y0 + h - wc.bottom + 24, Right = 0, Bottom = 0 }) end)
    end
    setText(H.wallTitle, "wallTitleStr", t.wall_title)
    setText(H.wallFoot, "wallFootStr", string.format(t.wall_close, info.label or "I"))
    for i, r in ipairs(H.wallRows) do
        local row = i <= n and rows[i] or nil
        local y = y0 + wc.top + (i - 1) * hc.line
        local ax = (row and row.b) and mid - wc.col_dx or mid
        if row and (r.ax ~= ax or r.y ~= y) then
            r.ax, r.y = ax, y
            pcall(function() r.sa:SetOffsets({ Left = ax, Top = y, Right = 0, Bottom = 0 }) end)
            pcall(function() r.sb:SetOffsets({ Left = mid + wc.col_dx, Top = y, Right = 0, Bottom = 0 }) end)
        end
        if row then setText(r.a, "wallA" .. i, row.a) end
        if row and row.b then setText(r.b, "wallB" .. i, row.b) end
        local aOn, bOn = row ~= nil, row ~= nil and row.b ~= nil
        if r.aOn ~= aOn then r.aOn = aOn; r.a:SetVisibility(aOn and VIS.HitTestInvisible or VIS.Collapsed) end
        if r.bOn ~= bOn then r.bOn = bOn; r.b:SetVisibility(bOn and VIS.HitTestInvisible or VIS.Collapsed) end
    end
    if not H.wallOn then
        H.wallOn = true
        H.wallPanel:SetVisibility(VIS.HitTestInvisible); H.wallTitle:SetVisibility(VIS.HitTestInvisible)
        H.wallFoot:SetVisibility(VIS.HitTestInvisible)
    end
end

-- A raid's bombers still up (the round's D.raidUnits), or 0
local function raidLeft()
    if not (D.raidUnits and next(D.raidUnits)) then return 0 end
    local n = 0
    for _, p in ipairs(planes) do if not p.down and p.unit and D.raidUnits[p.unit] then n = n + 1 end end
    return n
end

-- One HUD pass: build when needed, show/hide with the game's HUD, update the rows and the callout.
-- The mission info stack (WBP_HUD_SubWidgets_Parts_CampaignInfo_000): its TIME row (TimerAndGauge) and the score's
-- "/limit" (BorderScoreText). Survival pauses the mission clock (EP MissionStart), so the row would sit at 60:00:00,
-- and the score has no target (user, 2026-10-22: just the score). The TIME row is hidden, not collapsed, so SCORE
-- and TARGET keep their rows; the limit is collapsed, so the score reads on its own. Both are taken from the live
-- panel (FindAllOf also returns the blueprint's template, "..._C:WidgetTree.TimerAndGauge", which isn't on screen),
-- looked up every 2 s and kept that way every pass in case the game shows them again.
local function hideGameInfo(now)
    local hc = CFG.hud
    if not (hc.hide_game_timer or hc.hide_score_limit) then return end
    local have = H.info and #H.info > 0
    -- (0.73.73: liveObj on the kept widgets: valid() read a freed one; and none looked for while the walks are held)
    for _, e in ipairs(H.info or {}) do if not liveObj(e.w) then have = false end end
    if not have and (not H.infoAt or now >= H.infoAt) and not walkHold() then   -- look again only while they aren't found
        H.infoAt, H.info, H.infoSaid = now + 2, {}, H.infoSaid or {}
        for _, w in ipairs(FindAllOf("WBP_HUD_SubWidgets_Parts_CampaignInfo_000_C") or {}) do
            if liveWidget(w) then                                    -- a live panel, not a blueprint's template
                local function part(n, vis, what)
                    local ok, x = pcall(function() return w:GetWidgetFromName(FName(n)) end)
                    if not (ok and valid(x)) then ok, x = pcall(function() return w[n] end) end   -- the blueprint's variable
                    if ok and valid(x) then H.info[#H.info + 1] = { w = x, vis = vis, what = what } end
                end
                if hc.hide_game_timer then part("TimerAndGauge", VIS.Hidden, "TIME row") end
                if hc.hide_score_limit then part("BorderScoreText", VIS.Collapsed, "score limit") end
            end
        end
    end
    for _, e in ipairs(H.info or {}) do
        if liveObj(e.w) and e.w:GetVisibility() ~= e.vis then
            e.w:SetVisibility(e.vis)
            if not H.infoSaid[e.what] then H.infoSaid[e.what] = true; log("hud: the game's " .. e.what .. " hidden (" .. nameOf(e.w) .. ")") end
        end
    end
end

-- (0.73.76) VALKA's red sky (user, 2026-11-03: "red sky instead of red screen"; CFG.specials.valka.red): the way the Sky
-- Editor's SkyLive mod changes a sky live: the level's sky actor (LiveCloudlyActor) has the sun light, sky light and
-- height fog that light aircraft, ground and haze (their colours blended towards red), and the sky's own params
-- (CloudlySkyParams .Data.SunIntensity.RGB, sRGB 0-255: the sky dome's sun colour), also written into the renderer's
-- working copies (CloudlyRenderer .Data.SkyRendererMainThread.OurSkyParams / .SkyParamsRO). Every value's original is
-- kept and written back exactly (the sky asset is shared: never left red). hudRed(true / false[, cfg, now]); redTick
-- (hudTick, 4 times a second) runs the blend: strength over in_s, back over out_s.
RED = { want = false, cfg = nil, at = nil, k = 0, b = nil }
-- ((0.73.84) the sky's objects are the level's: forgotten untouched as the level's torn down, sv_core.lua levelGate, as the
-- gun's class default that crashed Shazzy's quit of 2026-11-04 should have been)
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["VALKA's sky"] = function() RED.b, RED.k = nil, 0 end end
local function srgbLin(c)
    c = (tonumber(c) or 0) / 255
    if c <= 0.04045 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end
local function lerp(a, b, k) return a + (b - a) * k end
local function skyFind()
    local a = nil
    for _, cn in ipairs({ "LiveCloudlyActor", "CloudlyActor" }) do
        local ok, l = pcall(FindAllOf, cn)
        for _, o in ipairs(ok and l or {}) do if liveObj(o) then a = o; break end end
        if a then break end
    end
    if not a then return nil end
    local b, got = { actor = a, rend = {} }, {}
    pcall(function() b.sun = a.SunLight end)
    pcall(function() b.skyl = a.SkyLight end)
    pcall(function() b.fog = a.HeightFog end)
    if valid(b.sun) and pcall(function() local q = b.sun.LightColor; b.sunCol = { srgbLin(q.R), srgbLin(q.G), srgbLin(q.B) } end) then got[#got + 1] = "sun" end
    if valid(b.skyl) and pcall(function() local q = b.skyl.LightColor; b.skyCol = { srgbLin(q.R), srgbLin(q.G), srgbLin(q.B) } end) then got[#got + 1] = "sky light" end
    if valid(b.fog) and pcall(function() local q = b.fog.FogInscatteringLuminance; b.fogCol = { q.R, q.G, q.B } end) then got[#got + 1] = "fog" end
    if pcall(function() local q = a.CloudlySkyParamsAsset.Data.SunIntensity.RGB; b.rgb = { q.X, q.Y, q.Z } end) and b.rgb then got[#got + 1] = "sky params" end
    local okR, rl = pcall(FindAllOf, "CloudlyRenderer")
    for _, r in ipairs(okR and rl or {}) do if liveObj(r) then b.rend[#b.rend + 1] = r end end
    log(string.format("hud: VALKA's sky: %s (%s), %d renderer(s)", nameOf(a), #got > 0 and table.concat(got, ", ") or "nothing readable", #b.rend))
    local function c3(v) return v and string.format("%.3g %.3g %.3g", v[1], v[2], v[3]) or "-" end
    log(string.format("hud: VALKA's sky, as it was: sun %s, sky light %s, fog %s, sky params' sun %s", c3(b.sunCol), c3(b.skyCol), c3(b.fogCol), c3(b.rgb)))
    return b
end
local function rgbWrite(st, v)                       -- a sky params struct's SunIntensity.RGB
    pcall(function() local q = st.SunIntensity.RGB; q.X, q.Y, q.Z = v[1], v[2], v[3] end)
end
local function skyApply(b, k, rc)
    -- (0.73.76, the user's screenshot of 00:12: "the red is waaay to bright": set colours made the haze and sky glow)
    -- every colour is a tint of its own value now (x tint, green and blue down): redder, never brighter. Then (00:22,
    -- "turn the sky more red": the tint left a dark purple sky; the log: sun 1 1 1, sky light 1 1 1, fog 0 0 0, the sky
    -- params' sun 1 1 1, so the 255s of the first try blew it white): set colours on that scale, red up, green and blue
    -- down, a faint red haze
    local function mix(o, t) return { lerp(o[1], t[1], k), lerp(o[2], t[2], k), lerp(o[3], t[3], k) } end
    if b.sunCol and liveObj(b.sun) then              -- ((0.73.84) liveObj: kept between ticks, valid() reads it)
        local c = mix(b.sunCol, rc.sun or { 1, 0.25, 0.15 })
        pcall(function() b.sun:SetLightColor({ R = c[1], G = c[2], B = c[3], A = 1 }, true) end)
    end
    if b.skyCol and liveObj(b.skyl) then
        local c = mix(b.skyCol, rc.light or { 1, 0.3, 0.2 })
        pcall(function() b.skyl:SetLightColor({ R = c[1], G = c[2], B = c[3], A = 1 }) end)
    end
    if b.fogCol and liveObj(b.fog) then
        local c = mix(b.fogCol, rc.fog or { 0.1, 0.012, 0.006 })
        pcall(function() b.fog:SetFogInscatteringColor({ R = c[1], G = c[2], B = c[3], A = 1 }) end)
    end
    if b.rgb then
        local v = mix(b.rgb, rc.sky_sun or { 1.8, 0.3, 0.15 })
        if liveObj(b.actor) then pcall(function() rgbWrite(b.actor.CloudlySkyParamsAsset.Data, v) end) end
        for _, r in ipairs(b.rend) do
            if liveObj(r) then
                pcall(function()
                    local d = r.Data
                    for _, arr in ipairs({ d.SkyRendererMainThread.OurSkyParams, d.SkyParamsRO }) do
                        pcall(function() arr:ForEach(function(_, e) rgbWrite(e:get(), v) end) end)
                    end
                end)
            end
        end
    end
end
function hudRed(on, cfg, now)
    on = on == true
    if cfg then RED.cfg = cfg end
    if RED.want ~= on then
        RED.want = on
        log("hud: the sky " .. (on and "turning red" or "going back from red"))
    end
    if not on and now and RED.b then                 -- (at once: a cleanup, no tick may follow)
        -- ((0.73.84) not while the level's torn down, nor once its sky actor is gone: nothing left to put back)
        if (levelTorn and levelTorn()) or not liveObj(RED.b.actor) then
            RED.b, RED.k = nil, 0
            log("hud: the sky's level is gone: nothing put back")
            return
        end
        skyApply(RED.b, 0, RED.cfg or {})
        RED.b, RED.k = nil, 0
        log("hud: the sky put back as it was (at once)")
    end
end
local function redTick(now)
    local rc = RED.cfg or {}
    if not RED.want and RED.k <= 0 then RED.at = now; return end
    if RED.want and not RED.b then
        RED.b = skyFind()
        if not RED.b then RED.want = false; log("hud: VALKA's sky: no sky actor found; the sky stays as it is"); return end
    end
    local dt = RED.at and math.max(0, math.min(1, now - RED.at)) or 0
    RED.at = now
    local top = tonumber(rc.strength) or 0.85
    local span = RED.want and (tonumber(rc.in_s) or 3) or (tonumber(rc.out_s) or 5)
    local step = top * dt / math.max(0.1, span)
    if RED.want then RED.k = math.min(top, RED.k + step) else RED.k = math.max(0, RED.k - step) end
    if RED.b then
        if not liveObj(RED.b.actor) then RED.b, RED.k = nil, 0; return end      -- (its level gone: nothing to put back)
        skyApply(RED.b, RED.k, rc)
        if RED.k <= 0 and not RED.want then RED.b = nil; log("hud: the sky put back as it was") end
    end
end

function hudTick(now, paused, pc)
    if hudOff or not CFG.hud.enabled or not D then return end
    if not (H and liveObj(H.widget)) then                     -- (0.73.73: liveObj, kept between ticks)
        H = nil
        if not liveObj(pc) then return end
        hudTries = hudTries + 1
        local ok, err = pcall(hudBuild, pc)
        if not ok then
            log("hud: build failed (try " .. hudTries .. "): " .. tostring(err))
            if H and valid(H.widget) then pcall(function() H.widget:RemoveFromParent() end) end
            H = nil
            if hudTries >= 3 then hudOff = true; log("hud: giving up for this level; rounds go on without the HUD") end
            return
        end
    end
    pcall(redTick, now)                                        -- (0.73.76) VALKA's red screen
    local pawnOk = false
    pcall(function() pawnOk = valid(pc.Pawn) end)
    local gameHud = true
    pcall(function() local hud = pc:GetHUD(); if valid(hud) then gameHud = hud.bShowHUD end end)
    local show = ((not paused) and pawnOk and gameHud) or (LB.show ~= nil)    -- (the run's summary stays up)
    pcall(LB.hud, now)
    if SUB and SUB.hudTick then                    -- ((0.74.0) the subtitle strip and the card: sv_subs.lua)
        local okSb, errSb = pcall(SUB.hudTick, now, show, CFG.hud.info.enabled and info.open)
        if not okSb then hudLog("subtick", "subtitles error " .. tostring(errSb)) end
    end
    if show ~= H.shown then
        H.widget:SetVisibility(show and VIS.HitTestInvisible or VIS.Collapsed)
        H.shown = show
        if show then H.rowsAt = 0 end                  -- (the rows read at once: a peek waiting for it starts now)
        log("hud: " .. (show and "shown" or ("hidden (" .. (paused and "paused" or (not pawnOk and "no player aircraft") or "game HUD off") .. ")")))
    end
    pcall(hideGameInfo, now)
    local t = CFG.hud.text
    local waves = D.waves and #D.waves > 1 and D.state ~= "wait" and D.wave
    setText(H.round, "roundStr", waves and string.format(t.round_wave, math.max(D.round, 1), D.wave, #D.waves)
        or string.format(t.round, math.max(D.round, 1)))
    setText(H.credits, "creditsStr", string.format(t.credits, RUN.credits))
    if H.air and AF.hp then
        setText(H.air, "airStr", AF.down and t.airfield_down_row or t.airfield)
        setText(H.airNum, "airNumStr", AF.down and "" or tostring(AF.hp))
        local shown = not AF.down
        if H.airBarShown ~= shown then H.airBar:SetVisibility(shown and VIS.HitTestInvisible or VIS.Collapsed); H.airBarShown = shown end
        if H.airHp ~= AF.hp then
            H.airHp = AF.hp
            -- (never out of less than the health shown: a bar can't run past its frame)
            local afMax = math.max(AF.max or CFG.airfield.hp, AF.hp or 0, 1)
            H.airFillSlot:SetSize({ X = math.max(0, H.airFillW * AF.hp / afMax), Y = H.airFillH })
            local c = AF.hp <= CFG.hud.warn_hp and CFG.hud.warn_color or CFG.hud.color
            H.airFill:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 1 })
        end
    end
    local sp = D.special and D.special.state == "countdown" and D.special
    local nextS = nil                               -- (the NEXT row: the break's countdown, or what's going on)
    if D.state == "wait" then
        nextS = string.format(D.round == 0 and t.first_round or t.next_round, clock(D.at - now))   -- (start_round > 1: NEXT ROUND)
    elseif sp then                                  -- Comona Defense: the countdown and the shuttle's health
        local hp = shuttleHealth()
        local cd = D.shuttleClock and D.shuttleClock.cd or (now - sp.at)
        nextS = string.format(t.launch_row, clock(math.max(0, CFG.specials.shuttle.countdown_s - cd)), hp or 100)
    elseif SPC.alicornRow and SPC.alicornRow(t) then   -- ((2026-11-11) the host's, or a co-op joiner's from the host's
        nextS = SPC.alicornRow(t)                      -- "rnd": its core's health once it's open, sv_alicorn.lua)
    elseif D.special and D.special.kind == "ladon" and D.special.state == "run" then
        nextS = string.format(t.ladon_row, SPC.ladonsLeft(D.special), D.special.runs or 0)
    elseif D.special and D.special.kind == "amphibious" and D.special.state == "assault" then
        local craft, ashore = AMPH.counts()
        nextS = string.format(t.amphib_row, craft, ashore, AMPH.capture())
    elseif D.special and SPC.kinds[D.special.kind] and SPC.kinds[D.special.kind].row and SPC.kinds[D.special.kind].row(D.special, t) then
        nextS = SPC.kinds[D.special.kind].row(D.special, t)          -- (the Spaceport Assault's: sv_spaceport.lua)
    elseif SPORT and SPORT.clientRow and SPORT.clientRow(t) then      -- ((0.73.77, I7: S12) a co-op joiner: the host's
        nextS = SPORT.clientRow(t)                                    -- Spaceport row, from its "spx")
    elseif DECOY and DECOY.clientRow and DECOY.clientRow(t) then      -- (a co-op joiner: the host's DECOY row, its "dk")
        nextS = DECOY.clientRow(t)
    elseif ESC and ESC.clientRow and ESC.clientRow(t) then            -- ((2026-11-06) a co-op joiner: the host's escort's
        nextS = ESC.clientRow(t)                                      -- row, from its "es": sv_escort.lua)
    elseif FISH and FISH.clientRow and FISH.clientRow(t) then         -- ((0.74.0) a co-op joiner: the host's GONE FISHIN'
        nextS = FISH.clientRow(t)                                     -- and THE FESTIVAL ("fsx"; sv_fishing / sv_festival)
    elseif FEST and FEST.clientRow and FEST.clientRow(t) then
        nextS = FEST.clientRow(t)
    elseif RUN.captured then
        local left = math.max(0, RUN.captured.untilRound - D.round)
        local _, ashore = AMPH.counts()
        nextS = string.format(t.captured_row, left, left == 1 and "" or "S", ashore)
    elseif D.special and D.special.kind == "glitch" and D.special.state == "hunt" and D.special.dist then
        local gl = CFG.specials.glitch
        nextS = D.special.frenzyUntil and string.format(t.glitch_row_frenzy, gl.name)
            or (D.special.phase == 3 and t.glitch_row_allout and string.format(t.glitch_row_allout, gl.name, D.special.dist))   -- (P7)
            or string.format(t.glitch_row, gl.name, D.special.dist)
    elseif D.special and D.special.kind == "valka" and D.special.state == "hunt" and D.special.dist then
        local sp, va = D.special, CFG.specials.valka
        nextS = sp.chargeAt and string.format(t.valka_row_charge, va.name)
            or sp.invertUntil and string.format(t.valka_row_field, va.name, sp.fxText or "")
            or string.format(t.valka_row, va.name, sp.dist)
    elseif D.special and D.special.kind == "anomaly" and D.special.state == "hunt" and D.special.dist then
        local an = CFG.specials.anomaly
        nextS = ANOM.on and string.format(t.anomaly_row_field, ANOM.fxText or "") or string.format(t.anomaly_row, an.name:upper(), D.special.dist)
    elseif D.raidBearing then                       -- a raid from one direction: its bombers left
        local n = raidLeft()
        if n > 0 then nextS = string.format(t.raid_row, n, compassName(D.raidBearing)) end
    end
    local okDn, downS = pcall(function() return DOWN and DOWN.hudLine and DOWN.hudLine() end)   -- (co-op: you're down,
    if okDn and downS then nextS = downS end                                                    -- watching: sv_down.lua)
    stackText(H.next, "nextStr", nextS)
    -- the info rows: the allies', the tactical items' and co-op's, and the info wall while it's open (once a second is
    -- plenty; at once when the info key flips it)
    if info.open ~= H.infoOpen then H.infoOpen, H.rowsAt = info.open, 0 end
    if now >= (H.rowsAt or 0) then
        H.rowsAt = now + 1
        local okA, al, alNews = pcall(ALLY.hudLine)
        infoRow(H.allies, "alliesStr", okA and al and string.format(t.allies_row, al) or nil, okA and alNews, now)
        local okI, it, itNews = pcall(TAC.line, now)
        infoRow(H.items, "itemsStr", okI and it and string.format(t.items_row, it) or nil, okI and itNews, now)
        if not (okA and okI) then hudLog("rowserr", "allies / items row error " .. tostring(okA and it or al)) end
        local okC, co, coNews = pcall(coopLine)
        if not okC then hudLog("coopserr", "co-op row error " .. tostring(co)) end
        infoRow(H.coop, "coopStr", okC and co or nil, okC and coNews, now)
        local okW, errW = pcall(wallTick, now, CFG.hud.info.enabled and info.open and LB.show == nil)
        if not okW then hudLog("wallerr2", "info wall error " .. tostring(errW)) end
    end
    stackRows()

    if #callouts > 0 and not H.calloutUntil then
        local c = table.remove(callouts, 1)
        setText(H.bannerText, "bannerStr", c.text)
        -- box width: the text's own width when the game can lay it out now, else ~32 units a letter (measured on the
        -- user's screenshot of 2026-10-22: "BOMBERS INBOUND" overran a 24-a-letter box), plus banner_pad each side
        local hc, w = CFG.hud, #c.text * CFG.hud.banner_char_w
        pcall(function()
            H.bannerText:ForceLayoutPrepass()
            local d = H.bannerText:GetDesiredSize()
            if d and d.X and d.X > 0 then w = math.max(w, d.X) end
        end)
        H.bannerSlot:SetSize({ X = math.max(390, w + 2 * hc.banner_pad), Y = 69 })
        -- a big one (VALKA's name: CFG.specials.valka.big_x): the banner drawn that many times its size, held longer
        local sc = tonumber(c.big) or (c.big and 1.5) or 1         -- ((2026-11-11) a true: 1.5, never a scale of true)
        pcall(function() H.banner:SetRenderScale({ X = sc, Y = sc }) end)
        setText(H.sub, "subStr", c.sub or "")
        H.banner:SetRenderOpacity(1); H.sub:SetRenderOpacity(CFG.hud.opacity)
        H.banner:SetVisibility(VIS.HitTestInvisible)
        H.sub:SetVisibility(c.sub and VIS.HitTestInvisible or VIS.Collapsed)
        H.calloutUntil = now + CFG.hud.callout_s * (c.big and 1.5 or 1)
    end
    if H.calloutUntil then
        local left = H.calloutUntil - now
        if left <= 0 then
            H.banner:SetVisibility(VIS.Collapsed); H.sub:SetVisibility(VIS.Collapsed); H.calloutUntil = nil
        else
            local a = CFG.hud.opacity * math.min(1, left / 0.75)                     -- fades over the last 0.75 s
            H.banner:SetRenderOpacity(a / CFG.hud.opacity); H.sub:SetRenderOpacity(a)
        end
    end
end

-- The info key (CFG.hud.info): a release feature, not a test key. Its press only flips info.open (in a run: elsewhere it
-- does nothing, so the menus can't change the next run's HUD); hudTick opens or shuts the info wall on its next pass.
-- UE4SS's key binds are keyboard only and don't take the key from the game. A key that can't be bound leaves the rows
-- always shown and no wall (enabled off), never hidden for good.
do
local ic = CFG.hud.info
if ic.enabled then
    local name = string.upper(tostring(ic.key or ""))
    local mods = (ic.ctrl and ModifierKey and ModifierKey.CONTROL) and { ModifierKey.CONTROL } or {}
    local label = (#mods > 0 and "Ctrl+" or "") .. name
    info.label = label                                 -- (the wall's footer names it)
    local ok, err = false, "UE4SS has no key binds here"
    if type(RegisterKeyBind) == "function" and Key then
        local k = Key[name]
        if k == nil then err = "'" .. tostring(ic.key) .. "' isn't a key name UE4SS knows: [hud.info] key"
        else
            ok, err = pcall(RegisterKeyBind, k, mods, function()
                ExecuteInGameThread(function()
                    if not D then return end
                    info.open = not info.open
                    log("hud: info wall " .. (info.open and "shown" or "hidden") .. " (" .. label .. ")")
                end)
            end)
        end
    end
    if ok then
        log(string.format("hud: info key %s: the info wall (players, allies, items) %s; the CO-OP, ALLIES and ITEMS rows "
            .. "each shown %s s when it changes", label, info.open and "open at the start" or "shown when it's pressed",
            tostring(ic.peek_s)))
    else
        log("hud: info key " .. label .. " not bound (" .. tostring(err) .. "): the info rows always shown, no info wall")
        ic.enabled = false
    end
end
end
