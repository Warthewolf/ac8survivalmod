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
    -- stacked from here down in that order (stackRows)
    H.allies = newText("Allies"); H.items = newText("Items")
    H.coop = newText("Coop")                               -- CO-OP: who is playing (sv_coop.lua COOP.hudLine), first
    H.stackY, H.stack = rowY, {}
    for _, w in ipairs({ H.coop, H.next, H.allies, H.items }) do
        H.stack[#H.stack + 1] = { w = w, slot = slotIn(canvas, w, { 0, 0 }, { 0, 0 }, { hc.x, rowY, 0, 0 }, { 0, 0 }, true) }
        w:SetVisibility(VIS.Collapsed)
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

-- shown on the next HUD tick (callers are in roundsTick); big: a scale. urgent (a tell, sv_tells.lua): in front of the
-- queue, in place of a tell still waiting there, and up at once, the banner showing cut short (calloutNext); a full
-- queue (4) loses its last callout to it. Without urgent a 5th callout is dropped, as ever.
function hudCallout(text, sub, big, urgent)
    if urgent then
        for i = #callouts, 1, -1 do if callouts[i].urgent then table.remove(callouts, i) end end
        table.insert(callouts, 1, { text = text, sub = sub, big = big, urgent = true })
        if #callouts > 4 then
            local d = table.remove(callouts)
            log("hud: callout '" .. tostring(d.text) .. "' dropped for a tell (the queue was full)")
        end
    elseif #callouts < 4 then callouts[#callouts + 1] = { text = text, sub = sub, big = big } end
    log("hud: " .. (urgent and "tell" or "callout") .. " '" .. text .. "'" .. (sub and (" / '" .. sub .. "'") or ""))
end

-- The callout to put on the banner now (taken off the queue), or nil: the queue's first once the banner is free, or
-- an urgent one (a tell) at once, cutting the banner's callout short: that one goes back in the queue after the tell
-- when more than 1.5 s of it was left (a tell never cuts another tell: TELL keeps them urgent_gap_s apart)
function calloutNext(now)
    local c = callouts[1]
    if not c then return nil end
    if H.calloutUntil then
        local cur = H.calloutCur
        if not (c.urgent and cur and not cur.urgent) then return nil end
        if H.calloutUntil - now > 1.5 then
            table.insert(callouts, 2, cur)
            if #callouts > 4 then                       -- (the queue's last makes room for it, logged as hudCallout's)
                local d = table.remove(callouts)
                log("hud: callout '" .. tostring(d.text) .. "' dropped (a tell cut in)")
            end
        end
        H.calloutUntil = nil
    end
    return table.remove(callouts, 1)
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
    for _, e in ipairs(H.info or {}) do if not valid(e.w) then have = false end end
    if not have and (not H.infoAt or now >= H.infoAt) then      -- look again only while they aren't found
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
    for _, e in ipairs(H.info) do
        if valid(e.w) and e.w:GetVisibility() ~= e.vis then
            e.w:SetVisibility(e.vis)
            if not H.infoSaid[e.what] then H.infoSaid[e.what] = true; log("hud: the game's " .. e.what .. " hidden (" .. nameOf(e.w) .. ")") end
        end
    end
end

function hudTick(now, paused, pc)
    if hudOff or not CFG.hud.enabled or not D then return end
    if not (H and valid(H.widget)) then
        H = nil
        if not valid(pc) then return end
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
    local pawnOk = false
    pcall(function() pawnOk = valid(pc.Pawn) end)
    local gameHud = true
    pcall(function() local hud = pc:GetHUD(); if valid(hud) then gameHud = hud.bShowHUD end end)
    local show = ((not paused) and pawnOk and gameHud) or (LB.show ~= nil)    -- (the run's summary stays up)
    pcall(LB.hud, now)
    if show ~= H.shown then
        H.widget:SetVisibility(show and VIS.HitTestInvisible or VIS.Collapsed)
        H.shown = show
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
            H.airFillSlot:SetSize({ X = math.max(0, H.airFillW * AF.hp / (AF.max or CFG.airfield.hp)), Y = H.airFillH })
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
    elseif D.special and D.special.kind == "alicorn" and D.special.state == "sail" then
        local sp = D.special
        nextS = string.format(t.alicorn_row, sp.tanks or 4, sp.coreOpen and "EXPOSED" or "SHUT", sp.dived and "  (DIVED)" or "")
    elseif D.special and D.special.kind == "ladon" and D.special.state == "run" then
        nextS = string.format(t.ladon_row, SPC.ladonsLeft(D.special), D.special.runs or 0)
    elseif D.special and D.special.kind == "amphibious" and D.special.state == "assault" then
        local craft, ashore = AMPH.counts()
        nextS = string.format(t.amphib_row, craft, ashore, AMPH.capture())
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
    stackText(H.next, "nextStr", nextS)
    -- the allies' and the tactical items' rows (once a second is plenty)
    if now >= (H.rowsAt or 0) then
        H.rowsAt = now + 1
        local okA, al = pcall(ALLY.hudLine)
        stackText(H.allies, "alliesStr", okA and al and string.format(t.allies_row, al) or nil)
        local okI, it = pcall(TAC.line, now)
        stackText(H.items, "itemsStr", okI and it and string.format(t.items_row, it) or nil)
        if not (okA and okI) then hudLog("rowserr", "allies / items row error " .. tostring(okA and it or al)) end
        local okC, co = pcall(function() return COOP and COOP.hudLine and COOP.hudLine() end)
        stackText(H.coop, "coopStr", okC and co or nil)
    end
    stackRows()

    local c = calloutNext(now)
    if c then
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
        local sc = c.big or 1
        pcall(function() H.banner:SetRenderScale({ X = sc, Y = sc }) end)
        setText(H.sub, "subStr", c.sub or "")
        H.banner:SetRenderOpacity(1); H.sub:SetRenderOpacity(CFG.hud.opacity)
        H.banner:SetVisibility(VIS.HitTestInvisible)
        H.sub:SetVisibility(c.sub and VIS.HitTestInvisible or VIS.Collapsed)
        -- (a tell, urgent: CFG.tells.hud_s)
        local tellS = c.urgent and CFG.tells and tonumber(CFG.tells.hud_s)
        H.calloutCur, H.calloutUntil = c, now + (tellS or CFG.hud.callout_s * (c.big and 1.5 or 1))
    end
    if H.calloutUntil then
        local left = H.calloutUntil - now
        if left <= 0 then
            H.banner:SetVisibility(VIS.Collapsed); H.sub:SetVisibility(VIS.Collapsed); H.calloutUntil, H.calloutCur = nil, nil
        else
            local a = CFG.hud.opacity * math.min(1, left / 0.75)                     -- fades over the last 0.75 s
            H.banner:SetRenderOpacity(a / CFG.hud.opacity); H.sub:SetRenderOpacity(a)
        end
    end
end
