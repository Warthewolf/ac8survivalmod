-- sv_shop.lua: the STORE and the landing shop.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- In Survival's level: are the store's pages in the game's menu list (LiveMenuManager.MenuWidgetClassList, built from
-- the table when the level started)? true / false, or nil while it can't be read yet.
function SHOP.storeCheck()
    if SH.store ~= nil then return SH.store end
    if not SH.menuOk then SH.store = false; return false end
    if walkHold() then return nil end                 -- (0.73.73: a held walk finds no manager; not a try)
    SH.storeTries = (SH.storeTries or 0) + 1
    local ok, got = pcall(function()
        local m = FindFirstOf("LiveMenuManager")
        if not valid(m) then return nil end
        local list = m.MenuWidgetClassList
        local n = list:GetArrayNum()
        local ids = {}
        for _, e in ipairs(SHOP.menuRows) do
            local v = e.index < n and list[e.index + 1].MenuIDName
            ids[#ids + 1] = not v and "-" or type(v) == "string" and v or v:ToString()
        end
        return { n = n, ids = ids }
    end)
    if ok and got then
        SH.store = true
        local parts = {}
        for k, e in ipairs(SHOP.menuRows) do
            if got.ids[k] ~= e.id then SH.store = false end
            parts[#parts + 1] = string.format("%d = %s", e.index, got.ids[k])
        end
        log(string.format("shop: the game's menu list has %d menus; %s: %s", got.n, table.concat(parts, ", "),
            SH.store and "the STORE is in" or "the shop rows stand in"))
    elseif SH.storeTries >= 10 then
        SH.store = false
        log("shop: the game's menu list couldn't be read (" .. tostring(got) .. "); the shop rows stand in")
    end
    return SH.store
end

-- Icons on the landing menu's rows (any page of it: the landing page, the STORE pages): an Image in each row's own
-- canvas, its label moved over (docs/re/AIRFIELD_SHOP_UI.md rank 2). Rows are reused, so each row's icon follows the
-- StringArgs of the command it shows now.
do
local texCache = {}
local function texture(path)
    if texCache[path] and not liveObj(texCache[path]) then texCache[path] = nil end   -- (0.73.73: kept: a freed one dropped)
    if texCache[path] == nil then
        local name = path:match("[^/]+$")
        texCache[path] = loadObject(path .. "." .. name) or false
    end
    return texCache[path] or nil
end
-- the player's own plane's icon (T_HUD_acIcon_PP<nnn>_<model>, from its BP_PlayerPlane_PP<nnnn>_<model>), if any
local function planeIcon()
    local ok, n = pcall(function() return nameOf(survivalPC.Pawn) end)
    local num, model                                -- (not `ok and n:match(...)`: `and` keeps only the first capture)
    if ok and n then num, model = n:match("PP0*(%d+)_(%w+)") end
    if not num then return nil end
    return texture(string.format("/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP%03d_%s", tonumber(num), model))
end
local function child(w, n)                           -- (childWidget, declared further down)
    local ok, x = pcall(function() return w:GetWidgetFromName(FName(n)) end)
    if ok and valid(x) then return x end
    ok, x = pcall(function() return w[n] end)
    return ok and valid(x) and x or nil
end
local function argsOf(list, k)
    local ok, a = pcall(function() return list.CommandDatas[k].StringArgs:ToString() end)
    return ok and a or nil
end
-- ((0.73.80, findings perf4 / specials8) a press on a STORE row ("SV_Buy_<item>", SV_ShopRequest's): its page is among the
-- landing menu's kept windows when one on screen lists that row; else they're walked for again at once (sv_core.lua
-- landingWindowsRefresh), so the labels changed by the press go onto that page's rows (relabel's SHOP.windowsKey) and its
-- icons on. Logged the first time it walks; each visit's line counts them. true: found among them.)
function SHOP.pressPage(args)
    local tick = SH.tick or 0
    for _, win in ipairs(landingWindows(tick)) do
        if landingVisible(win) and liveObj(win) then
            local list = child(win, "WBP_Menu_Pause_List_000")
            for k = 1, 6 do if list and argsOf(list, k) == args then return true end end
        end
    end
    landingWindowsRefresh("press")
    local n = #landingWindows(tick)
    if not SH.pressPageSaid then
        SH.pressPageSaid = true
        log(string.format("shop: %s pressed on a landing menu page not among the windows kept: walked for them again (%d "
            .. "now; 0.73.80)", tostring(args), n))
    end
    return false
end
function SHOP.decorTick(tick)
    if not CFG.shop.enabled or tick % 2 ~= 0 or not playerOnAirfield() then return end
    local imgClass = StaticFindObject("/Script/UMG.Image")
    if not valid(imgClass) then return end
    -- ((0.73.77, Workstream B2) the icons of rows gone with their pages off the list every 16 s down there: each page
    -- opened makes new rows, so it only grew through a level)
    if tick % 64 == 0 then
        for a, d in pairs(SH.decor) do if not liveObj(d.img) then SH.decor[a] = nil end end
    end
    for _, win in ipairs(landingWindows(tick)) do
        if liveObj(win) then        -- ((review of 0.73.80) the kept list may hold a page freed since its look: hotfix 2's lesson)
            local list = child(win, "WBP_Menu_Pause_List_000")
            for k = 1, 6 do
                local row = list and child(list, string.format("WBP_Menu_Text_Focus_000_%02d", k))
                local args = row and argsOf(list, k)
                local item = args and (args:match("^SV_Buy_(.+)$") or (SHOP.icons[args] and args:match("^%d+$") and args))
                local a = row and addrOf(row)
                if a and item then
                    local d = SH.decor[a]
                    if not d or not liveObj(d.img) then                  -- (0.73.73: liveObj, kept between ticks)
                        local ok, err = pcall(function()
                            local canvas = child(row, "CanvasPanel_79")
                            if not canvas then error("no CanvasPanel_79 in the row") end
                            local img = StaticConstructObject(imgClass, row.WidgetTree, FName(string.format("SV_StoreIcon_%d", k)))
                            local slot = canvas:AddChildToCanvas(img)
                            slot:SetPosition({ X = 92, Y = 20 }); slot:SetSize({ X = 48, Y = 48 })
                            local hb = child(row, "HorizontalBox_59")         -- the label, moved right of the icon
                            if hb then pcall(function() hb.Slot:SetPosition({ X = 152, Y = 0 }) end) end
                            d = { img = img }
                            SH.decor[a] = d
                        end)
                        if not ok and not SH.decorSaid then SH.decorSaid = true; log("shop: row icons failed: " .. tostring(err)) end
                    end
                    if d and d.item ~= item and liveObj(d.img) then
                        local own = item == "RepairAircraft" or item == "UpAirframe" or item == "Insurance"
                        local tex = (own and planeIcon()) or texture(SHOP.icons[item] or SHOP.icons.Airfield)
                        if tex then pcall(function() d.img:SetBrushFromTexture(tex, false) end) end
                        d.item = item
                        if not SH.decorDone then SH.decorDone = true; log("shop: row icons on the landing menu") end
                    end
                elseif a and SH.decor[a] and liveObj(SH.decor[a].img) then   -- a stock row now: no icon
                    pcall(function() SH.decor[a].img:SetVisibility(1) end)
                    SH.decor[a].item, SH.decor[a].hidden = nil, true
                end
                if a and item and SH.decor[a] and SH.decor[a].hidden and liveObj(SH.decor[a].img) then
                    pcall(function() SH.decor[a].img:SetVisibility(4) end); SH.decor[a].hidden = nil
                end
            end
        end
    end
end
end

local shopTexts, shopBuy             -- (the shop's helpers stay inside the block: the 200-local limit)
do
-- ((0.73.78, economy C4 / C5) + price_per_round x the round: sv_ai.lua itemPrice / priceRound. The row's label, the NOT
-- ENOUGH ZOLLARS check, the charge, a joiner's "ab" ask and its refund all take this one price)
local function shopPrice(name)
    local it = CFG.shop.items[name]
    return itemPrice(it.price, it.price_per_round, it.raise, RUN.bought[name] or 0)
end

-- ((0.73.78, plan G6) the airstrikes bought this round (RUN.strikeBuys: { round = priceRound(), n }) and whether
-- another may be: CFG.tactical.airstrike.per_round a round, bought or called (sv_tactical.lua TAC.use: called)
function SHOP.strikesBought()
    local b = RUN.strikeBuys
    return (b and b.round == priceRound()) and b.n or 0
end
local function strikeLimit() return math.floor(tonumber(CFG.tactical.airstrike.per_round) or 0) end

-- The shop is closed after a lost special (CFG.specials.shuttle.shop_closed_rounds): through round RUN.shopClosedUntil,
-- including the break before it, and open again in the break after it.
local function shopClosed()
    if RUN.captured then return true end            -- the amphibious assault took the airfield
    local u = RUN.shopClosedUntil
    return u ~= nil and D ~= nil and (D.round < u or (D.round == u and D.state ~= "wait"))
end

-- The airfield defences' kinds (CFG.shop.items.Airfield.defences: AA guns, SAM sites and, from 0.72.1, the CIWS), in
-- the order the STORE, the HUD's ALLIES row and sv_allies.lua's watch list them.
DEF_KINDS = { "aa", "sam", "ciws" }

-- A defence of `kind` the STORE can't build in this game: the CIWS while its DT_NPC row isn't in (ALLY.setup)
local function defenceMissing(kind) return kind == "ciws" and ALLY.ciwsReady == false end

-- The airfield row's offer once the airfield is whole: the next defence to build ({ kind, unit, def, price }), or nil
-- when every one is up.
local function defenceOffer()
    local d = CFG.shop.items.Airfield.defences
    if not d or not D or not nativeReady() then return nil end
    RUN.defences = RUN.defences or { built = 0, bought = {} }
    local function free(kind)
        if defenceMissing(kind) then return nil end
        for _, u in ipairs(d[kind].units) do if SV_UnitAlive(u) <= 0 then return u end end
    end
    local first = d.order[RUN.defences.built % #d.order + 1]
    local kinds = { first }                          -- (its turn's kind first, then the others)
    for _, k in ipairs(DEF_KINDS) do if k ~= first then kinds[#kinds + 1] = k end end
    for _, kind in ipairs(kinds) do
        local u = d[kind] and d[kind].units and free(kind)
        if u then
            local def = d[kind]
            return { kind = kind, unit = u, def = def,
                     price = math.floor(def.price * def.raise ^ (RUN.defences.bought[kind] or 0) / 10 + 0.5) * 10 }
        end
    end
    return nil
end

local function airfieldNeedsRepair()
    return not AF.hp or AF.down or AF.hp < (AF.max or CFG.airfield.hp)
end

-- The player's aircraft health in % (its HealthInternal is health x 10), the last one read when it can't be now.
local function aircraftHealth()
    local ok, pct = pcall(function()
        local pawn = survivalPC.Pawn
        local m = pawn.MaxHealth
        return m > 0 and math.max(0, math.min(100, math.floor(pawn.HealthInternal / 10 / m * 100 + 0.5))) or nil
    end)
    if ok and pct then RUN.acHp = pct end
    return RUN.acHp
end

-- (the shop's texts again when the aircraft's health changes: shopTick calls it)
function SHOP.healthCheck()
    local hp = aircraftHealth()
    if hp ~= RUN.acHpShown then RUN.acHpShown, RUN.dirty = hp, true end
end

-- The aircraft repair's price for `pct` health (CFG.shop.items.RepairAircraft), or nil when it's whole.
local function aircraftRepairPrice(pct)
    local a = CFG.shop.items.RepairAircraft
    if not (a and pct and pct < 100) then return nil end
    return math.max(a.min_price, math.ceil(a.price * (100 - pct) / 100 / 10) * 10)
end

local function defencesUp(kind)
    local def = CFG.shop.items.Airfield.defences[kind]
    local units, n = def and def.units or {}, 0
    if nativeReady() then for _, u in ipairs(units) do if SV_UnitAlive(u) > 0 then n = n + 1 end end end
    return n, #units
end

-- ((2026-11-11) Saint Alessia's 50-round co-op run, lag-3) a defence's spawn names its unit (spawningUnit, as the co-op
-- host's SV_Spawn does): sv_allies.lua keeps its objects as they're made (ALLY.parts), so the round clear's repair and
-- the defences' health read those instead of walking every object for their classes
local function spawnDefence(unit)
    if spawningUnit ~= nil then return SV_Spawn(unit) end
    spawningUnit = unit
    local ok, r = pcall(SV_Spawn, unit)
    spawningUnit = nil
    if not ok then error(r, 0) end
    return r
end

-- A free unit of defence `kind` and its price now (each one built makes the next of its kind dearer), or nil.
local function defenceFor(kind)
    local d = CFG.shop.items.Airfield.defences
    local def = d and d[kind]
    if not (def and D and nativeReady()) or defenceMissing(kind) then return nil end
    RUN.defences = RUN.defences or { built = 0, bought = {} }
    for _, u in ipairs(def.units) do
        if SV_UnitAlive(u) <= 0 then
            return { kind = kind, unit = u, def = def,
                     price = math.floor(def.price * def.raise ^ (RUN.defences.bought[kind] or 0) / 10 + 0.5) * 10 }
        end
    end
    return nil
end

-- What's missing of the full load ({ [kind] = rounds }, kinds 1 missiles, 2 / 3 special weapons, 4 flares) and what
-- FULL REARM charges for it (CFG.shop.items.Rearm: a price a round), or nil when nothing can be read yet.
local function rearmNeed()
    if not (A and A.applied and A.caps and A.max) then return nil end
    local it, need, price = CFG.shop.items.Rearm, {}, 0
    local per = { [1] = it.missile, [2] = it.special, [3] = it.special, [4] = it.flare }
    for k = 1, 4 do
        local cap, max = A.caps[k], A.max[k]
        if cap and max and max > cap then need[k] = max - cap; price = price + need[k] * (per[k] or 0) end
    end
    return need, math.ceil(price / 10) * 10
end

-- An upgrade's next tier and its price, or nil when every tier is bought.
local function upgradeNext(it)
    local have = RUN.ups and RUN.ups[it.up] or 0
    return have < #it.tiers and have + 1 or nil, it.tiers[have + 1], have
end

local UP_HELP = {
    airframe = "Your aircraft's health +%d%% for the rest of the run (tier %d of %d).",
    bays     = "Carry %d%% more missiles and special weapons for the rest of the run (tier %d of %d). Buy them after.",
    gun      = "Your gun's damage +%d%% for the rest of the run (tier %d of %d).",
    flares   = "Carry %d more flares for the rest of the run (tier %d of %d). Buy them after.",
}
local TAC_HELP = {
    -- ((0.73.78, plan G6) only by its key, at most max_hit of the flight, never an ace squadron's, per_round a round;
    -- its kills pay airstrike_x (C4))
    airstrike = "Destroys up to %d aircraft of the biggest enemy flight within %d km of you, never an ace squadron's (Ctrl+F1). %s Kills pay %d%%. You carry %d.",
    ecm       = "Breaks every enemy missile lock on you for %d seconds (Ctrl+F2, or by itself when %d missiles close in). You carry %d.",
    decoy     = "The nearest enemy flight breaks off for %d seconds (Ctrl+F3, or by itself when a flight of %d+ is close). You carry %d.",
}

-- What item `name`'s row offers now: { role, label, help, price (nil: nothing to buy now), why (when there isn't),
-- plus the defence's unit for aa / sam }. The texts, the purchases and the STORE's checks all go through it.
local function offer(name)
    -- ((2026-11-06) a row another item shares while it has nothing to sell itself: the ZFA-44 carrier on the revive row
    -- once it's unlocked, sv_escort.lua ESC.rowItem; o.item: the item it sells, the row's name stays `name`)
    local item = name
    if ESC and ESC.rowItem then
        local okR, alt = pcall(ESC.rowItem, name)
        if okR and type(alt) == "string" and CFG.shop.items[alt] then item = alt end
    end
    local it = CFG.shop.items[item]
    local o = { role = it.kind and "ammo" or it.role, item = item }
    if o.role == "combined" then                     -- the old fourth row: aircraft, then airfield, then defences
        o.role = aircraftRepairPrice(aircraftHealth()) and "aircraft" or (airfieldNeedsRepair() and "airfield" or "defence")
    end
    if o.role == "ammo" then
        local cap = A and A.caps and A.caps[it.kind]
        local max = A and A.max and A.max[it.kind]
        -- the special weapons: both slots, each its own load (a friend's run, 2026-10-25: "ALREADY AT FULL LOAD" 20 times
        -- with nothing saying why): the counts are on the row
        local have = cap and max and string.format(" (%d/%d)", cap, max) or ""
        if it.kind == 2 and A and A.caps and A.max and A.caps[3] and A.max[3] then
            have = string.format(" (%d/%d, %d/%d)", A.caps[2] or 0, A.max[2] or 0, A.caps[3], A.max[3])
        end
        local full = cap and max and cap >= max and not (it.kind == 2 and A.caps[3] and A.max[3] and A.caps[3] < A.max[3])
        o.label = full and string.format("%s: FULL%s", it.label, have) or string.format("%s +%d%s", it.label, it.step, have)
        o.help = string.format("%d more %s. Landing doesn't rearm: you fly with what you buy%s.", it.step, it.what,
            cap and string.format(" (you have %d of %d)", cap, max or cap) or "")
        if full then
            o.why = "ALREADY AT FULL LOAD."
            o.help = o.help .. (CFG.shop.items.UpBays and " WEAPON BAYS (UPGRADES) carry more." or "")
        else o.price = shopPrice(name) end
    elseif o.role == "rearm" then
        local need, price = rearmNeed()
        o.label = it.label
        if not need then o.why, o.help = "NOT AVAILABLE YET.", "Fills every weapon to its full load."
        else
            local parts = {}
            for k, what in pairs({ [1] = "missiles", [4] = "flares" }) do if need[k] then parts[#parts + 1] = need[k] .. " " .. what end end
            if need[2] or need[3] then parts[#parts + 1] = ((need[2] or 0) + (need[3] or 0)) .. " special weapon rounds" end
            o.help = #parts > 0 and ("Fills every weapon to its full load: " .. table.concat(parts, ", ") .. ".")
                or "Every weapon is at its full load."
            if price > 0 then o.price = price else o.why = "ALREADY AT FULL LOAD." end
        end
    elseif o.role == "upgrade" then
        local nxt, price, have = upgradeNext(it)
        local shown = it.up == "flares" and math.floor(it.step) or math.floor(it.step * 100 + 0.5)
        o.label = nxt and string.format("%s %d/%d", it.label, nxt, #it.tiers) or (it.label .. ": ALL TIERS")
        o.help = string.format(UP_HELP[it.up] or "%d %d %d", shown * (nxt or have), nxt or have, #it.tiers)
        if not CFG.upgrades.enabled or (it.up == "gun" and not CFG.upgrades.gun_experimental) then o.why = "NOT AVAILABLE."
        elseif nxt then o.price = price else o.why = "ALL TIERS BOUGHT." end
    elseif o.role == "tactical" then
        local c, have = CFG.tactical[it.tac], RUN.items and RUN.items[it.tac] or 0
        o.label = string.format("%s (%d/%d)", it.label, have, it.max or 1)
        local lim = it.tac == "airstrike" and strikeLimit() or 0
        if it.tac == "airstrike" then
            local hits = math.floor(tonumber(c.max_hit) or 0)
            local once = lim <= 0 and "" or (lim == 1 and "One a round, bought or called." or string.format("%d a round, bought or called.", lim))
            o.help = string.format(TAC_HELP.airstrike, hits > 0 and hits or 99, c.range_km, once,
                math.floor((CFG.credits.airstrike_x or 1) * 100 + 0.5), have)
            if hits <= 0 then o.help = o.help:gsub("up to 99 aircraft of ", "") end
        else
            o.help = string.format(TAC_HELP[it.tac], it.tac == "ecm" and c.ecm_s or c.decoy_s,
                it.tac == "ecm" and c.auto_missiles or c.auto_size, have)
        end
        if have >= (it.max or 1) then o.why = "YOU CARRY AS MANY AS YOU CAN."
        elseif lim > 0 and SHOP.strikesBought() >= lim then
            -- ((0.73.78, plan G6) the round's airstrike bought: the row says so, no price on it)
            local r = priceRound()
            o.label = string.format("%s (%d/%d): %s", it.label, have, it.max or 1, lim == 1 and "ONE A ROUND" or (lim .. " A ROUND"))
            o.why = string.format("%s A ROUND: THE NEXT AFTER ROUND %d.", lim == 1 and "ONE" or tostring(lim), r)
            o.help = o.help .. string.format(" Bought for round %d: the next once it's over.", r)
        else o.price = shopPrice(name) end
    elseif o.role == "insurance" then
        o.label = it.label .. (RUN.insured and ": HELD" or "")
        o.help = "Survive one shoot-down: at the brink your aircraft is repaired and shielded for a moment. One at a time; not a crash into the ground."
        if not CFG.insurance.enabled then o.why = "NOT AVAILABLE."
        elseif RUN.insured then o.why = "YOU ALREADY HOLD ONE." else o.price = shopPrice(name) end
    elseif o.role == "orders" then
        local now = ALLY.order and ALLY.order() or CFG.allies.orders.default
        o.label = string.format("%s: %s", it.label, now:upper())
        o.help = "Press for the next order: HUNT (anywhere), COVER (stay with you), DEFEND (the airfield). Ctrl+F4 in flight. Free."
        o.price = 0
    elseif o.role == "revive" then                   -- co-op: a player who's down bought back (sv_down.lua DOWN.offer)
        local r = (DOWN and DOWN.offer) and DOWN.offer() or { label = it.label, why = "CO-OP ONLY." }
        o.label, o.help, o.price, o.why, o.slot = r.label or it.label, r.help or "", r.price, r.why, r.slot
    elseif o.role == "aircraft" then
        local hp = aircraftHealth()
        o.label, o.price = CFG.shop.items.RepairAircraft.label, aircraftRepairPrice(hp)
        o.help = string.format("Repairs your aircraft to full health (now %s%%).", tostring(hp or "?"))
        if not o.price then o.why = "YOUR AIRCRAFT ISN'T DAMAGED." end
    elseif o.role == "airfield" then
        o.label = string.format("%s +%d", CFG.shop.items.RepairAirfield.label, it.repair)
        o.help = string.format("Repairs the airfield by %d (now %s of %d).", it.repair,
            AF.down and "down" or tostring(AF.hp or "?"), AF.max or CFG.airfield.hp)
        if not AF.hp or AF.down then o.why = "THE AIRFIELD IS DOWN."
        elseif AF.hp >= (AF.max or CFG.airfield.hp) then o.why = "THE AIRFIELD IS NOT DAMAGED."
        else o.price = shopPrice(name) end
    elseif o.role == "ally_carrier" then                                -- the ZFA-44 carriers (sv_escort.lua)
        local r = (ESC and ESC.offer) and ESC.offer(item ~= name) or { why = "NOT AVAILABLE." }
        o.label, o.help, o.why = r.label or it.label, r.help or "", r.why
        if not o.why then o.price = shopPrice(item) end
    elseif o.role == "ally_awacs" then                                  -- VOID WATCHER 1 (CFG.allies.awacs)
        local aw = CFG.allies.awacs
        local up, free = ALLY.status({ aw.unit })
        o.label = it.label
        -- ((0.73.78, plan G5) its rounds of service, its ESM's reach and the strike flight after it, from CFG)
        local rounds = aw.service and tonumber(aw.service.rounds) or 0
        o.help = string.format("%s, an E-767 AWACS: it takes off from the airfield once you're airborne, orbits it and pulses its "
            .. "ESM over the airfield (%d km)%s. It never fights; %s", aw.name, math.floor(aw.esm.range_m / 1000),
            rounds > 0 and string.format(" for %d rounds, then goes home", rounds) or "",
            (aw.strike and aw.strike.enabled) and "a strike flight goes after it each round." or "enemies may hunt it.")
        if not (CFG.allies.enabled and aw.enabled and ALLY.awacsReady) then o.why = "NOT AVAILABLE."
        elseif up > 0 or not free then o.why = aw.name .. " IS UP."
        else o.price, o.unit = shopPrice(name), free end
    elseif o.role == "ally_air" or o.role == "ally_ship" then          -- CFG.allies
        local c = CFG.allies
        local units = o.role == "ally_air" and c.aircraft.units or c.ships[it.ship].units
        local up, free = ALLY.status(units)
        o.label = it.label
        if o.role == "ally_air" and it.ally == "wingmen" then
            o.help = string.format("Squadron %s, two F-16Cs: a cheaper flight that takes off once you're airborne and fights until shot down (%d of %d allied flights up).",
                c.wingmen.name, up, #units)
        elseif o.role == "ally_air" then
            o.help = string.format("Squadron %s, two F-22s: they take off from the airfield once you're airborne and fight until shot down (%d of %d allied flights up).",
                c.aircraft.name, up, #units)
        else
            o.help = string.format("The %s sails the waters by the airfield and fights until sunk (%d of %d at sea).",
                c.ships[it.ship].name, up, #units)
        end
        if not c.enabled or not ALLY.ready or (it.ally == "wingmen" and not ALLY.wingmenReady) then o.why = "NOT AVAILABLE."
        elseif not free then o.why = o.role == "ally_air" and "BOTH ALLIED FLIGHTS ARE UP." or string.format("ALL %d ARE AT SEA.", #units)
        else o.price, o.unit = shopPrice(name), free end
    else                                             -- a defence: aa / sam / ciws, or the old row's next one in turn
        local aa, aaMax = defencesUp("aa")
        local sam, samMax = defencesUp("sam")
        local ciws, ciwsMax = defencesUp("ciws")
        local up = string.format(" (AA guns %d of %d, SAM sites %d of %d, CIWS %d of %d up)", aa, aaMax, sam, samMax, ciws, ciwsMax)
        local f = (o.role == "defence") and defenceOffer() or defenceFor(o.role)
        local def = CFG.shop.items.Airfield.defences[o.role] or (f and f.def)
        o.label = f and ("BUILD " .. f.def.label) or ((o.role == "defence" and "AIRFIELD DEFENCES" or ("BUILD " .. def.label)) .. ": ALL BUILT")
        o.help = f and string.format("Builds %s %s for the rest of the run%s.", f.def.what,
                                     f.kind == "ciws" and "by the runway" or "at the airfield", up)
            or ("Every one is up" .. up .. ".")
        if f then o.price, o.unit, o.kind, o.def = f.price, f.unit, f.kind, f.def
        elseif defenceMissing(o.role) then
            o.label, o.why, o.help = "BUILD " .. def.label, "NOT AVAILABLE.", "Not in this game's tables" .. up .. "."
        else o.why = "ALL BUILT." end
    end
    return o
end

-- A row's label on screen, in place: the game reads a row's label only when its page opens (tools/re/
-- AIRFIELD_SHOP_UI.md), so after a purchase it kept the old one (a run of 2026-10-25: "AIRFRAME 1/10 5000 Z" after
-- tier 1 was bought; the player pressed again and again, WEAPON BAYS tier 1 -> 4 in a second). The help line is read on
-- every move, so it was right. Each changed label's TextBlock (a live one showing the old text) gets the new one.
-- Only the STORE rows' own TextBlocks are read (under a WBP_Menu_Text_Focus row, by their full names): every live
-- TextBlock's text was read each time a label changed, and in co-op another player's kill changes them (the perf lines
-- of the co-op run of 2026-10-30, "shop" up to 195 ms a tick). None found that way: every TextBlock, as before, logged.
local function rowKey(t) return (tostring(t):upper():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
-- ((0.73.77, Workstream B4) the landing menu's windows now, as one key: their addresses (a STORE page opened or closed
-- changes it). ((0.73.80) The kept ones every part shares (sv_core.lua landingWindows): no walk of its own; a new page's
-- window comes in when the last one closes, or after a press on it, SHOP.pressPage.)
-- ((0.73.77) the teardown gate's drop, sv_core.lua levelDrop: the STORE's kept widgets forgotten, none of them touched;
-- (0.73.80) the landing menu's kept windows too)
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS.store = function()
        SH.rowTexts, SH.panels, SH.slotCache, SH.tbNames, SH.decor = nil, nil, nil, nil, {}
        if type(landingWindowsForget) == "function" then landingWindowsForget() end
    end
end
function SHOP.windowsKey(tick)
    local t = {}
    for _, w in ipairs(landingWindows(tick or SH.tick or 0)) do t[#t + 1] = tostring(addrOf(w)) end
    table.sort(t)
    return table.concat(t, ",")
end
local function relabel(changed)
    if walkHold() then return nil end                  -- (0.73.73: a held walk finds no row: not "none under a row")
    local n, rows, all = 0, 0, SH.relabelAll
    -- ((0.73.77, Workstream B4) the STORE rows' TextBlocks kept while the landing menu's windows stay the same (their
    -- key), each checked live before it's read: every TextBlock's full name was read on every relabel, the "shop" part's
    -- worst ticks (mobi118's host of 2026-11-02: 12.5 ms a tick on average, 488 ms at worst). Walked again when a page
    -- opens or closes, or one kept is gone.)
    local key = (not all) and SHOP.windowsKey(SH.tick) or nil
    local kept = SH.rowTexts
    if kept and (all or kept.key ~= key or key == "") then kept = nil end
    if kept then
        for _, t in ipairs(kept.list) do if not liveObj(t) then kept = nil; break end end
    end
    local list = kept and kept.list or nil
    if not list then
        list = {}
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            local nm = valid(t) and nameOf(t) or ""
            if nm:find("/Engine/Transient", 1, true) and (all or nm:find("WBP_Menu_Text_Focus", 1, true)) then list[#list + 1] = t end
        end
        SH.rowTexts = (not all and key ~= "" and #list > 0) and { key = key, list = list } or nil
        SH.rowWalks = (SH.rowWalks or 0) + 1
    else
        SH.rowKept = (SH.rowKept or 0) + 1
        if SH.rowKept == 1 then log(string.format("shop: the STORE rows' %d TextBlocks kept for its labels while its pages stay (0.73.77)", #list)) end
    end
    for _, t in ipairs(list) do
        if kept or valid(t) then
            rows = rows + 1
            local ok, v = pcall(function() return t:GetText():ToString() end)
            local new = ok and type(v) == "string" and changed[rowKey(v)]
            if new and pcall(function() t:SetText(toText(new)) end) then n = n + 1 end
        end
    end
    if rows == 0 and not all then
        SH.relabelAll = true
        log("shop: no STORE row TextBlock under a WBP_Menu_Text_Focus row; row labels are looked for in every TextBlock")
        return relabel(changed)
    end
    return n
end

-- The changed labels wait (merged: a label changed twice goes straight to its newest) and go on screen at once after a
-- press of yours, else at most every 2 s; left behind when you leave the airfield (the pages read their labels anew)
function SHOP.relabelFlush(force)
    if not (SH.relabelQ and next(SH.relabelQ)) then return end
    if not playerOnAirfield() then SH.relabelQ = nil; return end
    local now = os.clock()
    if not force and now < (SH.relabelAt or 0) then return end
    if walkHold() then return end                    -- (0.73.73: the walks held, walkHold: the labels wait, kept)
    local q = SH.relabelQ
    SH.relabelQ, SH.relabelAt = nil, now + 2
    local okR, n = pcall(relabel, q)
    if okR and n == nil then SH.relabelQ = q                 -- (held after all: back in the queue)
    elseif okR and n > 0 then log(string.format("shop: %d row label(s) updated on screen", n)) end
end
local function relabelQueue(changed)
    local q = SH.relabelQ or {}
    for oldK, new in pairs(changed) do
        for k, v in pairs(q) do if rowKey(v) == oldK then q[k] = new end end
        if q[oldK] == nil then q[oldK] = new end
    end
    SH.relabelQ = q
end

-- ((0.73.77, Workstream B4) a text sent to the runtime only when it changed: SV_SetText keeps each in its table for the
-- session; SH.textSent is emptied at every level load. Sent and skipped counted for the perf line's "shop/texts".)
local function setText(k, v)
    SH.textSent = SH.textSent or {}
    if SH.textSent[k] == v then SH.textSkip = (SH.textSkip or 0) + 1; return end
    if SV_SetText(k, v) == 1 then SH.textSent[k] = v end
end
-- ((0.73.77, Workstream B4) the rows' offers ask SV_UnitAlive once a unit while they're worked out: the three defence rows
-- asked for every defence unit three times over and the allies' rows for each of theirs, about 70 asks of the spawner's
-- whole unit list each time the texts were made. Nothing is spawned while the offers are worked out (offer() only reads),
-- so one answer a unit holds for all of them; the native's own function is put back however the offers end.)
local textsNow
function shopTexts()
    if type(SV_SetText) ~= "function" then return end
    local raw = SV_UnitAlive
    if type(raw) ~= "function" then return textsNow() end
    local memo, asked = {}, 0
    SV_UnitAlive = function(u)
        local v = memo[u]
        if v == nil then v = raw(u); memo[u] = v; asked = asked + 1 end
        return v
    end
    local ok, err = pcall(textsNow)
    SV_UnitAlive = raw
    SH.textAsks = (SH.textAsks or 0) + asked
    if not ok then error(err, 0) end
end
textsNow = function()
    RUN.offerShown = RUN.offerShown or {}
    SH.labels = SH.labels or {}
    local changed, nChanged, shared = {}, 0, {}
    for name in pairs(CFG.shop.items) do
        local o = offer(name)
        RUN.offerShown[name] = o.role
        local label = o.label .. (o.price and string.format("   %d Z", o.price) or "")
        local was = SH.labels[name]
        if was and was ~= label then
            local k = rowKey(was)
            if changed[k] ~= nil and changed[k] ~= label then shared[k] = true end   -- ((0.73.77) two rows had that text)
            changed[k], nChanged = label, nChanged + 1
        end
        SH.labels[name] = label
        local help = shopClosed() and (RUN.captured and CFG.hud.text.shop_captured or CFG.hud.text.shop_closed) or o.help
        help = string.format("ZOLLARS %d. %s%s", RUN.credits, RUN.msg[name] and (RUN.msg[name] .. " ") or "", help)
        setText("SV_Shop_" .. name, label)
        setText("SV_Shop_" .. name .. "_Help", help)
    end
    -- ((0.73.77, from claude/coop-fixes 57dce73) relabel() finds a row on screen by its old text, so a text two items
    -- share can't say which row it is. The old fourth row (Airfield, not on the STORE's pages but worked out with the
    -- rest) offers the next defence under the DEFENCES row's own text ("BUILD AA GUN   4000 Z"); when its turn moved on to
    -- the SAM site, every TextBlock showing the AA text was rewritten, the real AA row too: two BUILD SAM SITE rows, the
    -- first still buying an AA gun (co-op run of 2026-11-01, "the Buy AA was another Buy SAM site"). Such a text is left
    -- for the page's next opening.)
    for _, lab in pairs(SH.labels) do local k = rowKey(lab); if changed[k] ~= nil then shared[k] = true end end
    for k in pairs(shared) do if changed[k] ~= nil then changed[k], nChanged = nil, nChanged - 1 end end
    if nChanged > 0 and playerOnAirfield() then              -- (the landing menu is only up down there)
        relabelQueue(changed)
        SHOP.relabelFlush(SH.pressAt ~= nil and os.clock() - SH.pressAt < 1)
    end
    -- the STORE's own texts: its rows on the landing page (one per page it opens on), its page titles and the rows
    -- between its pages (tools/build_survival.py STORE_PAGES / STORE_ROWS)
    local z = string.format("ZOLLARS %d", RUN.credits)
    local PAGES = {
        { key = "Supplies", title = "SV_Store_Title", landing = "SV_Shop_Store", name = "SUPPLIES",
          what = "Full rearm, missiles, special weapons and flares." },
        { key = "Upgrades", title = "SV_Store_TitleUpgrades", landing = "SV_Shop_StoreUp", name = "UPGRADES",
          what = "Airframe, weapon bays, gun and flare pods: they last the whole run." },
        { key = "Tactical", title = "SV_Store_TitleTactical", landing = "SV_Shop_StoreTac", name = "TACTICAL",
          what = "Airstrikes, ECM bursts, decoys and the SECOND CHANCE." },
        { key = "Airfield", title = "SV_Store_TitleAirfield", landing = "SV_Shop_StoreAf", name = "AIRFIELD",
          what = "Aircraft and airfield repairs, and the airfield's defences." },
        { key = "Defences", title = "SV_Store_TitleDefences", name = "DEFENCES",
          what = "AA guns, SAM sites and CIWS around the runway." },
        { key = "Docks", title = "SV_Store_TitleDocks", name = "ALLIES",
          what = "Allied fighters and ships, and the allies' orders." },
    }
    for _, p in ipairs(PAGES) do
        setText(p.title, "AIRFIELD STORE: " .. p.name .. "   " .. z)
        setText("SV_Store_To" .. p.key, p.name .. " >")
        setText("SV_Store_To" .. p.key .. "_Help", z .. ". " .. p.what)
        if p.landing then
            setText(p.landing, "STORE: " .. p.name .. (p.key == "Airfield" and " & ALLIES" or "") .. " >")
            setText(p.landing .. "_Help", z .. ". " .. p.what)
        end
    end
end

-- (co-op host) joiner `slot`'s purchase of item `name` (an allied flight or ship, or a defence of `kind`) for `price`,
-- which they pay on their own game: built here (its spawn goes to every game, sv_coop.lua's SV_Spawn); true and the
-- row's message, or false and why not. Nothing is charged here.
-- ((0.73.78, plan G5) asked: a joiner's purchase (sv_coop.lua "ab"), not a host by migration building the old room's
-- again (free). VOID WATCHER 1's price is the room's: a joiner's ask under this game's price is refused (refunded on
-- their game), one built is counted here (RUN.bought, which "rnd" sends to every joiner's STORE: sv_coop.lua).)
function shopBuildFor(slot, name, price, kind, asked)
    local it = CFG.shop.items[name]
    if not (it and D and nativeReady()) then return false, "NOT AVAILABLE RIGHT NOW." end
    local role = it.kind and "ammo" or it.role
    if role == "ally_carrier" then                    -- ((2026-11-06) a ZFA-44 carrier: the room's price and count, as the allies')
        local o = offer(name)
        if not o.price then return false, o.why or "NOT AVAILABLE RIGHT NOW." end
        if asked and (tonumber(price) or 0) < o.price then
            log(string.format("shop: player %s's %s at %d refused: the room's price is %d (bought %d times this run)",
                slot and tostring(slot + 1) or "?", name, tonumber(price) or 0, o.price, RUN.bought[name] or 0))
            return false, string.format("THE PRICE IS NOW %d", o.price)
        end
        local ok, msg = ESC.buyCarrier(slot, price)
        if ok and asked then RUN.bought[name], RUN.dirty = (RUN.bought[name] or 0) + 1, true end
        return ok, msg
    end
    if role == "ally_air" or role == "ally_ship" or role == "ally_awacs" then
        local o = offer(name)
        if not o.unit then return false, o.why or "NOT AVAILABLE RIGHT NOW." end
        -- ((0.73.78) every ally's price is the room's, as VOID WATCHER 1's (user, 2026-11-03: "you have it right"): a
        -- joiner's ask is checked at the host's price and counted here, and the count goes to every joiner ("rnd" f14)
        local room = asked and true or false
        if room and o.price and (tonumber(price) or 0) < o.price then
            log(string.format("shop: player %s's %s at %d refused: the room's price is %d (bought %d times this run)",
                slot and tostring(slot + 1) or "?", name, tonumber(price) or 0, o.price, RUN.bought[name] or 0))
            return false, string.format("THE PRICE IS NOW %d", o.price)
        end
        local ok, msg = ALLY.buy(o.role, o.unit, it.ship or it.ally, price, slot)
        if ok and room then RUN.bought[name], RUN.dirty = (RUN.bought[name] or 0) + 1, true end
        return ok, msg
    end
    local d = CFG.shop.items.Airfield.defences
    if not (kind and type(d[kind]) == "table" and d[kind].units) then
        kind = (type(d[role]) == "table" and d[role].units) and role or nil
    end
    if not kind then return false, "NOT AVAILABLE IN CO-OP." end
    local f = defenceFor(kind)
    if not f then return false, "ALL BUILT." end
    -- ((0.73.78) a defence's price is the room's too: a joiner's ask below it refused, a built one counted here)
    RUN.defences = RUN.defences or { built = 0, bought = {} }
    RUN.defences.bought = RUN.defences.bought or {}
    local dk = d[kind]
    local rp = math.floor((tonumber(dk.price) or 0) * (tonumber(dk.raise) or 1) ^ (RUN.defences.bought[kind] or 0) / 10 + 0.5) * 10
    if asked and (tonumber(price) or 0) < rp then
        log(string.format("shop: player %s's %s at %d refused: the room's price is %d (built %d times this run)",
            slot and tostring(slot + 1) or "?", kind, tonumber(price) or 0, rp, RUN.defences.bought[kind] or 0))
        return false, string.format("THE PRICE IS NOW %d", rp)
    end
    local r = spawnDefence(f.unit)
    if ALLY.forgetAlive then ALLY.forgetAlive(f.unit) end    -- ((0.73.77) the allies' kept count of it asked afresh: B3)
    if r <= 0 then return false, "COULD NOT BUILD IT (" .. (SV_ERR[r] or tostring(r)) .. ")." end
    if asked then RUN.defences.bought[kind], RUN.dirty = (RUN.defences.bought[kind] or 0) + 1, true end
    -- (slot nil: a host by migration building the old room's again, its own or a buyer's who's gone)
    log(string.format("shop: %s built for %s (%s, %d paid on their game)", f.def.label, slot and ("player " .. (slot + 1)) or "the room",
        f.unit, price))
    return true, string.format("%s BUILT for %d (%s).", f.def.label, price, f.unit)
end

-- One purchase; the result goes into the item's help line and the log.
function shopBuy(name)
    local it = CFG.shop.items[name]
    if not it then log("shop: unknown item " .. tostring(name)); return end
    local function done(msg) RUN.msg[name] = msg; RUN.dirty = true; log("shop: " .. name .. ": " .. msg) end
    if shopClosed() then return done("CLOSED.") end
    local o = offer(name)
    if RUN.offerShown and RUN.offerShown[name] and RUN.offerShown[name] ~= o.role then
        return done("THIS ROW CHANGED: CHECK IT AND PRESS AGAIN.")       -- (the old fourth row's job moved on)
    end
    if not o.price then return done(o.why or "NOT AVAILABLE RIGHT NOW.") end
    local price = o.price
    if RUN.credits < price then return done(string.format("NOT ENOUGH ZOLLARS (%d needed).", price)) end
    if o.role == "orders" then                       -- free: the allies' next order
        return done(ALLY.nextOrder("store"):upper() .. ".")
    elseif o.role == "rearm" then                    -- every weapon to its full load
        local need = rearmNeed()
        local got = {}
        for k = 1, 4 do
            if need and need[k] then
                A.caps[k] = A.caps[k] + need[k]
                local n = SV_Ammo(k)
                if n >= 0 then SV_SetAmmo(k, math.min(n + need[k], A.caps[k]))
                else A.owed = A.owed or {}; A.owed[k] = true end      -- unreadable now: ammoTick loads it
                got[#got + 1] = string.format("%s +%d", ({ "missiles", "special 1", "special 2", "flares" })[k], need[k])
            end
        end
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        return done(string.format("REARMED for %d (%s).", price, table.concat(got, ", ")))
    elseif o.role == "upgrade" then
        local nxt = upgradeNext(it)
        RUN.ups = RUN.ups or {}
        RUN.ups[it.up] = nxt
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        local okU, errU = pcall(UP.apply, survivalPC and liveObj(survivalPC) and survivalPC.Pawn)
        if not okU then log("upgrades: error " .. tostring(errU)) end
        return done(string.format("%s TIER %d for %d.", it.label, nxt, price))
    elseif o.role == "tactical" then
        RUN.items = RUN.items or {}
        RUN.items[it.tac] = (RUN.items[it.tac] or 0) + 1
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        if it.tac == "airstrike" then                -- ((0.73.78, plan G6) counted for its round: SHOP.strikesBought)
            RUN.strikeBuys = { round = priceRound(), n = SHOP.strikesBought() + 1 }
        end
        return done(string.format("%s READY (%d carried) for %d (round %d's price).", it.label, RUN.items[it.tac], price, priceRound()))
    elseif o.role == "insurance" then
        RUN.insured = true
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        return done(string.format("SECOND CHANCE HELD for %d.", price))
    elseif o.role == "revive" then                   -- co-op: the host's say (a joiner's refunded on a refusal)
        local ok, msg = DOWN.buy(price)
        if not ok then return done(msg) end
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        return done(msg)
    elseif o.role == "aircraft" then
        -- the stock repair (RE_SV_RepairAircraft: health and armour pool) and the health written straight onto the
        -- aircraft, then read back: paid only once it reads full (test of 2026-10-23: the event alone left it at 63%
        -- and four presses charged four times)
        local before = aircraftHealth()
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_RepairAircraft") or -5
        local okW, errW = pcall(function()
            local pawn = survivalPC.Pawn
            if UP and UP.healthGuard then pcall(UP.healthGuard, pawn, "the STORE's repair") end   -- ((0.73.77) G2: the
            pawn.HealthInternal = math.floor(pawn.MaxHealth * 10 + 0.5)                              -- AIRFRAME's full)
        end)
        RUN.acHp = nil
        local after = aircraftHealth()
        log(string.format("shop: aircraft repair: %s%% -> %s%% (event %s, health written %s)", tostring(before), tostring(after),
            r == 1 and "fired" or (SV_ERR[r] or tostring(r)), okW and "yes" or ("no: " .. tostring(errW))))
        if not (after and after >= 99) then return done("COULD NOT REPAIR IT (NOTHING CHARGED).") end
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        return done(string.format("AIRCRAFT REPAIRED (%s%% -> %d%%) for %d.", tostring(before), after, price))
    elseif o.role == "ally_carrier" then             -- ((2026-11-06) a ZFA-44 carrier, sv_escort.lua: a joiner's built by the host)
        local item = o.item or name
        if COOP and COOP.client and COOP.client() then
            local ok, msg = COOP.askBuild(item, price, nil)
            if not ok then return done(msg) end
            RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
            return done(msg)
        end
        local ok, msg = ESC.buyCarrier(nil, price)
        if not ok then return done(msg) end
        LB.stat("allies", 1)
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[item] = (RUN.bought[item] or 0) + 1
        return done(string.format("%s for %d.", msg, price))
    elseif COOP and COOP.client and COOP.client() and (o.role == "ally_air" or o.role == "ally_ship" or o.role == "ally_awacs"
        or (o.unit and o.kind)) then
        -- co-op: the allies and the airfield's defences are the host's (one airfield, one sky for everyone): the host
        -- builds it in its game, which sends it to every game, and you pay now (refunded on a refusal or no answer;
        -- sv_coop.lua "ab" / "ak" / "ax"). The co-op run of 2026-10-30: wingmen, MOONCHILD, AEGIS, AA guns, SAM sites
        -- and CIWS bought by joiners were only ever in their own game ("none of it was syncing")
        local ok, msg = COOP.askBuild(name, price, o.kind)
        if not ok then return done(msg) end
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        return done(msg)
    elseif o.role == "ally_air" or o.role == "ally_ship" or o.role == "ally_awacs" then
        local ok, msg = ALLY.buy(o.role, o.unit, it.ship or it.ally, price)
        if not ok then return done(msg) end
        LB.stat("allies", 1)
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        return done(string.format("%s for %d.", msg, price))
    elseif o.unit then                               -- a defence
        local r = spawnDefence(o.unit)
        if ALLY.forgetAlive then ALLY.forgetAlive(o.unit) end    -- ((0.73.77) the allies' kept count of it asked afresh: B3)
        if r <= 0 then return done("COULD NOT BUILD IT (" .. (SV_ERR[r] or tostring(r)) .. ").") end
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.defences.built = RUN.defences.built + 1
        RUN.defences.bought[o.kind] = (RUN.defences.bought[o.kind] or 0) + 1
        return done(string.format("%s BUILT for %d (%s).", o.def.label, price, o.unit))
    elseif o.role == "ammo" then
        local k = it.kind
        if not (A and A.applied and A.caps and A.caps[k]) then return done("NOT AVAILABLE YET.") end
        -- each slot's gain up to its own full load (the special weapons: both slots, each its own; until 0.70.0 the
        -- second took the first's gain, past its load)
        local gains, best = {}, 0
        for _, kk in ipairs(k == 2 and { 2, 3 } or { k }) do
            if A.caps[kk] then
                local max = SV_Ammo(kk, 1)           -- unreadable on the landing menu: the last one seen in flight
                if max < 0 then max = A.max and A.max[kk] end
                if max and A.bays and A.bays[kk] then max = math.max(max, A.bays[kk]) end   -- (WEAPON BAYS, before UP.apply re-raises it)
                if max then gains[kk] = math.max(0, math.min(it.step, max - A.caps[kk])); best = math.max(best, gains[kk]) end
            end
        end
        if not next(gains) then return done("NOT AVAILABLE RIGHT NOW.") end
        if best <= 0 then return done("ALREADY AT FULL LOAD.") end
        if best < it.step then                       -- the last step up to the aircraft's full load costs less
            price = math.ceil(price * best / it.step / 10) * 10
            if RUN.credits < price then return done(string.format("NOT ENOUGH ZOLLARS (%d needed).", price)) end
        end
        for kk, gain in pairs(gains) do
            if gain > 0 then
                A.caps[kk] = A.caps[kk] + gain
                local n = SV_Ammo(kk)
                if n >= 0 then SV_SetAmmo(kk, math.min(n + gain, A.caps[kk]))
                else A.owed = A.owed or {}; A.owed[kk] = true end      -- unreadable now: ammoTick loads it
            end
        end
    else                                             -- the airfield
        AF.full, AF.base, AF.bombBase = math.min(AF.max or CFG.airfield.hp, AF.hp + it.repair), AF.hits, AF.bomb
        AF.hp = AF.full                             -- airfieldTick works health out from these from now on
        pcall(ALLY.repairDefences)                  -- (its AA guns, SAM sites and CIWS with it: economy review, "repair them
                                                    -- with the airfield")
    end
    RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
    RUN.bought[name] = (RUN.bought[name] or 0) + 1
    done(string.format("BOUGHT for %d.", price))
end
end

-- A menu sound by its Wwise event name (the game-SE bank, always loaded; docs/re/MUSIC_RADIO_CAMERA.md).
function SHOP.sound(name)
    local ok, err = pcall(function()
        local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
        if not valid(lib) then error("LiveSoundBlueprintLibrary not found") end
        lib:PostEventByName(liveObj(survivalPC) and survivalPC or FindFirstOf("PlayerController"), FName(name))
    end)
    if not ok and not SH.soundSaid then SH.soundSaid = true; log("shop: menu sound " .. name .. " failed: " .. tostring(err)) end
end

-- ((0.73.77, Workstream B1) the shop part's shares in the perf line, "shop/<share>": sv_main.lua's PERF)
local function pa(name, t0) if PERF and PERF.add then PERF.add(name, t0) end end
local function nKeys(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
function shopTick(tick)
    if not CFG.shop.enabled or not D then return end
    SH.tick = tick                                   -- ((0.73.77) the landing windows' walk of this tick: SHOP.windowsKey)
    local t0 = os.clock()
    if type(SV_ShopRequest) == "function" then
        -- every press waiting (the landing menu's hook queues them), and the texts straight after: taking one press
        -- per tick and updating the texts once a second left ~1 s with no change on screen, so purchases seemed not to
        -- register and players pressed again (user, 2026-10-22: "a good few presses to get it to register")
        local seen = {}
        for i = 1, 8 do
            local r = SV_ShopRequest()
            if not r or r == "" then break end
            if i == 1 then pcall(SHOP.pressPage, r) end      -- ((0.73.80) its page among the kept windows, else walked for)
            local item = r:gsub("^SV_Buy_", "")
            local it = CFG.shop.items[item]
            local last = SH.upAt and SH.upAt[item]
            if seen[item] then
                log("shop: " .. item .. " pressed again within a tick; once is bought")
            elseif it and it.role == "upgrade" and last and os.clock() - last < 1.0 then
                -- (a run of 2026-10-25: WEAPON BAYS tier 1 -> 4 within a second, 36000 Z, the row's label not changing)
                log("shop: " .. item .. " pressed again within 1 s of a tier bought; not bought twice")
            else
                if it and it.role == "upgrade" then SH.upAt = SH.upAt or {}; SH.upAt[item] = os.clock() end
                seen[item], SH.pressAt = true, os.clock()
                local spent = RUN.spent
                local ok, err = pcall(shopBuy, item)
                if not ok then log("shop: error " .. tostring(err)) end
                -- (user, 2026-10-23: "add a menu beep for everytime you press one of the buttons"; the free orders row
                -- beeps as bought)
                SHOP.sound((RUN.spent > spent or (ok and item == "Orders")) and CFG.shop.sounds.bought or CFG.shop.sounds.refused)
            end
        end
    end
    if tick % 4 == 3 then pcall(SHOP.healthCheck) end
    pa("shop/presses", t0)
    t0 = os.clock()
    -- the texts when something changed: down at the airfield (where they're read) at once after a press of yours, else
    -- every 0.5 s at most (in co-op every player's kill changes them: the co-op run of 2026-10-30 worked out all the rows'
    -- offers nearly every tick down there). ((0.73.77, Workstream B4) Never in flight: they're read only by the landing
    -- menu, and RUN.dirty waits, so the first tick down at the airfield makes them; in flight every kill had them all
    -- worked out every 5 s, all 21 rows' offers and ~70 asks of the spawner. Logged once a level.)
    local pressed = SH.pressAt ~= nil and os.clock() - SH.pressAt < 0.3
    if RUN.dirty and playerOnAirfield() and (pressed or tick >= (SH.groundTick or 0)) then
        RUN.dirty, SH.groundTick = false, tick + 2
        local ok, err = pcall(shopTexts)
        if not ok then log("shop: text error " .. tostring(err)) end
        if not SH.textSaid then
            SH.textSaid = true
            log(string.format("shop: the STORE's texts made down at the airfield only, a text sent when it changes (0.73.77; "
                .. "%d sent, %d unchanged, %d units asked)", nKeys(SH.textSent), SH.textSkip or 0, SH.textAsks or 0))
        end
    end
    pa("shop/texts", t0)
    t0 = os.clock()
    SHOP.relabelFlush(false)
    pa("shop/labels", t0)
end
