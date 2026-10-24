-- sv_shop.lua: the STORE and the landing shop.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- In Survival's level: are the store's pages in the game's menu list (LiveMenuManager.MenuWidgetClassList, built from
-- the table when the level started)? true / false, or nil while it can't be read yet.
function SHOP.storeCheck()
    if SH.store ~= nil then return SH.store end
    if not SH.menuOk then SH.store = false; return false end
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
-- canvas, its label moved over (tools/re/AIRFIELD_SHOP_UI.md rank 2). Rows are reused, so each row's icon follows the
-- StringArgs of the command it shows now.
do
local texCache = {}
local function texture(path)
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
function SHOP.decorTick(tick)
    if not CFG.shop.enabled or tick % 2 ~= 0 or not playerOnAirfield() then return end
    local imgClass = StaticFindObject("/Script/UMG.Image")
    if not valid(imgClass) then return end
    for _, win in ipairs(FindAllOf("WBP_Menu_IngameHangar_Common_000_C") or {}) do
        if liveWidget(win) then
            local list = child(win, "WBP_Menu_Pause_List_000")
            for k = 1, 6 do
                local row = list and child(list, string.format("WBP_Menu_Text_Focus_000_%02d", k))
                local args = row and argsOf(list, k)
                local item = args and (args:match("^SV_Buy_(.+)$") or (SHOP.icons[args] and args:match("^%d+$") and args))
                local a = row and addrOf(row)
                if a and item then
                    local d = SH.decor[a]
                    if not d or not valid(d.img) then
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
                    if d and d.item ~= item and valid(d.img) then
                        local own = item == "RepairAircraft" or item == "UpAirframe" or item == "Insurance"
                        local tex = (own and planeIcon()) or texture(SHOP.icons[item] or SHOP.icons.Airfield)
                        if tex then pcall(function() d.img:SetBrushFromTexture(tex, false) end) end
                        d.item = item
                        if not SH.decorDone then SH.decorDone = true; log("shop: row icons on the landing menu") end
                    end
                elseif a and SH.decor[a] and valid(SH.decor[a].img) then     -- a stock row now: no icon
                    pcall(function() SH.decor[a].img:SetVisibility(1) end)
                    SH.decor[a].item, SH.decor[a].hidden = nil, true
                end
                if a and item and SH.decor[a] and SH.decor[a].hidden then
                    pcall(function() SH.decor[a].img:SetVisibility(4) end); SH.decor[a].hidden = nil
                end
            end
        end
    end
end
end

local shopTexts, shopBuy             -- (the shop's helpers stay inside the block: the 200-local limit)
do
local function shopPrice(name)
    local it = CFG.shop.items[name]
    return math.floor(it.price * it.raise ^ (RUN.bought[name] or 0) / 10 + 0.5) * 10
end

-- The shop is closed after a lost special (CFG.specials.shuttle.shop_closed_rounds): through round RUN.shopClosedUntil,
-- including the break before it, and open again in the break after it.
local function shopClosed()
    if RUN.captured then return true end            -- the amphibious assault took the airfield
    local u = RUN.shopClosedUntil
    return u ~= nil and D ~= nil and (D.round < u or (D.round == u and D.state ~= "wait"))
end

-- The airfield row's offer once the airfield is whole: the next defence to build ({ kind, unit, def, price }), or nil
-- when every one is up.
local function defenceOffer()
    local d = CFG.shop.items.Airfield.defences
    if not d or not D or not nativeReady() then return nil end
    RUN.defences = RUN.defences or { built = 0, bought = {} }
    local function free(kind)
        for _, u in ipairs(d[kind].units) do if SV_UnitAlive(u) <= 0 then return u end end
    end
    local first = d.order[RUN.defences.built % #d.order + 1]
    for _, kind in ipairs({ first, first == "aa" and "sam" or "aa" }) do
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
    return not AF.hp or AF.down or AF.hp < CFG.airfield.hp
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

-- A free unit of defence `kind` and its price now (each one built makes the next of its kind dearer), or nil.
local function defenceFor(kind)
    local d = CFG.shop.items.Airfield.defences
    local def = d and d[kind]
    if not (def and D and nativeReady()) then return nil end
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
    airstrike = "Destroys the biggest enemy flight within %d km of you (Ctrl+F1, or by itself when %d are near). Kills pay half. You carry %d.",
    ecm       = "Breaks every enemy missile lock on you for %d seconds (Ctrl+F2, or by itself when %d missiles close in). You carry %d.",
    decoy     = "The nearest enemy flight breaks off for %d seconds (Ctrl+F3, or by itself when a flight of %d+ is close). You carry %d.",
}

-- What item `name`'s row offers now: { role, label, help, price (nil: nothing to buy now), why (when there isn't),
-- plus the defence's unit for aa / sam }. The texts, the purchases and the STORE's checks all go through it.
local function offer(name)
    local it = CFG.shop.items[name]
    local o = { role = it.kind and "ammo" or it.role }
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
        local a = it.tac == "airstrike" and c.range_km or it.tac == "ecm" and c.ecm_s or c.decoy_s
        local b = it.tac == "airstrike" and c.auto_near or it.tac == "ecm" and c.auto_missiles or c.auto_size
        o.help = string.format(TAC_HELP[it.tac], a, b, have)
        if have >= (it.max or 1) then o.why = "YOU CARRY AS MANY AS YOU CAN." else o.price = shopPrice(name) end
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
    elseif o.role == "aircraft" then
        local hp = aircraftHealth()
        o.label, o.price = CFG.shop.items.RepairAircraft.label, aircraftRepairPrice(hp)
        o.help = string.format("Repairs your aircraft to full health (now %s%%).", tostring(hp or "?"))
        if not o.price then o.why = "YOUR AIRCRAFT ISN'T DAMAGED." end
    elseif o.role == "airfield" then
        o.label = string.format("%s +%d", CFG.shop.items.RepairAirfield.label, it.repair)
        o.help = string.format("Repairs the airfield by %d (now %s of %d).", it.repair,
            AF.down and "down" or tostring(AF.hp or "?"), CFG.airfield.hp)
        if not AF.hp or AF.down then o.why = "THE AIRFIELD IS DOWN."
        elseif AF.hp >= CFG.airfield.hp then o.why = "THE AIRFIELD IS NOT DAMAGED."
        else o.price = shopPrice(name) end
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
    else                                             -- a defence: aa / sam, or the old row's next one in turn
        local aa, aaMax = defencesUp("aa")
        local sam, samMax = defencesUp("sam")
        local up = string.format(" (AA guns %d of %d, SAM sites %d of %d up)", aa, aaMax, sam, samMax)
        local f = (o.role == "defence") and defenceOffer() or defenceFor(o.role)
        local def = CFG.shop.items.Airfield.defences[o.role] or (f and f.def)
        o.label = f and ("BUILD " .. f.def.label) or ((o.role == "defence" and "AIRFIELD DEFENCES" or ("BUILD " .. def.label)) .. ": ALL BUILT")
        o.help = f and string.format("Builds %s at the airfield for the rest of the run%s.", f.def.what, up)
            or ("Every one is up" .. up .. ".")
        if f then o.price, o.unit, o.kind, o.def = f.price, f.unit, f.kind, f.def else o.why = "ALL BUILT." end
    end
    return o
end

function shopTexts()
    if type(SV_SetText) ~= "function" then return end
    RUN.offerShown = RUN.offerShown or {}
    for name in pairs(CFG.shop.items) do
        local o = offer(name)
        RUN.offerShown[name] = o.role
        local label = o.label .. (o.price and string.format("   %d Z", o.price) or "")
        local help = shopClosed() and (RUN.captured and CFG.hud.text.shop_captured or CFG.hud.text.shop_closed) or o.help
        help = string.format("ZOLLARS %d. %s%s", RUN.credits, RUN.msg[name] and (RUN.msg[name] .. " ") or "", help)
        SV_SetText("SV_Shop_" .. name, label)
        SV_SetText("SV_Shop_" .. name .. "_Help", help)
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
          what = "Aircraft and airfield repairs, AA guns and SAM sites." },
        { key = "Docks", title = "SV_Store_TitleDocks", name = "ALLIES",
          what = "Allied fighters and ships, and the allies' orders." },
    }
    for _, p in ipairs(PAGES) do
        SV_SetText(p.title, "AIRFIELD STORE: " .. p.name .. "   " .. z)
        SV_SetText("SV_Store_To" .. p.key, p.name .. " >")
        SV_SetText("SV_Store_To" .. p.key .. "_Help", z .. ". " .. p.what)
        if p.landing then
            SV_SetText(p.landing, "STORE: " .. p.name .. (p.key == "Airfield" and " & ALLIES" or "") .. " >")
            SV_SetText(p.landing .. "_Help", z .. ". " .. p.what)
        end
    end
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
        local okU, errU = pcall(UP.apply, survivalPC and valid(survivalPC) and survivalPC.Pawn)
        if not okU then log("upgrades: error " .. tostring(errU)) end
        return done(string.format("%s TIER %d for %d.", it.label, nxt, price))
    elseif o.role == "tactical" then
        RUN.items = RUN.items or {}
        RUN.items[it.tac] = (RUN.items[it.tac] or 0) + 1
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        return done(string.format("%s READY (%d carried) for %d.", it.label, RUN.items[it.tac], price))
    elseif o.role == "insurance" then
        RUN.insured = true
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        return done(string.format("SECOND CHANCE HELD for %d.", price))
    elseif o.role == "aircraft" then
        -- the stock repair (RE_SV_RepairAircraft: health and armour pool) and the health written straight onto the
        -- aircraft, then read back: paid only once it reads full (test of 2026-10-23: the event alone left it at 63%
        -- and four presses charged four times)
        local before = aircraftHealth()
        local r = type(SV_Event) == "function" and SV_Event("RE_SV_RepairAircraft") or -5
        local okW, errW = pcall(function()
            local pawn = survivalPC.Pawn
            pawn.HealthInternal = math.floor(pawn.MaxHealth * 10 + 0.5)
        end)
        RUN.acHp = nil
        local after = aircraftHealth()
        log(string.format("shop: aircraft repair: %s%% -> %s%% (event %s, health written %s)", tostring(before), tostring(after),
            r == 1 and "fired" or (SV_ERR[r] or tostring(r)), okW and "yes" or ("no: " .. tostring(errW))))
        if not (after and after >= 99) then return done("COULD NOT REPAIR IT (NOTHING CHARGED).") end
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        return done(string.format("AIRCRAFT REPAIRED (%s%% -> %d%%) for %d.", tostring(before), after, price))
    elseif o.role == "ally_air" or o.role == "ally_ship" then
        local ok, msg = ALLY.buy(o.role, o.unit, it.ship or it.ally, price)
        if not ok then return done(msg) end
        LB.stat("allies", 1)
        RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
        RUN.bought[name] = (RUN.bought[name] or 0) + 1
        return done(string.format("%s for %d.", msg, price))
    elseif o.unit then                               -- a defence
        local r = SV_Spawn(o.unit)
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
        AF.full, AF.base, AF.bombBase = math.min(CFG.airfield.hp, AF.hp + it.repair), AF.hits, AF.bomb
        AF.hp = AF.full                             -- airfieldTick works health out from these from now on
        pcall(ALLY.repairDefences)                  -- (its AA guns and SAM sites with it: economy review, "repair them
                                                    -- with the airfield")
    end
    RUN.credits, RUN.spent = RUN.credits - price, RUN.spent + price
    RUN.bought[name] = (RUN.bought[name] or 0) + 1
    done(string.format("BOUGHT for %d.", price))
end
end

-- A menu sound by its Wwise event name (the game-SE bank, always loaded; tools/re/MUSIC_RADIO_CAMERA.md).
function SHOP.sound(name)
    local ok, err = pcall(function()
        local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
        if not valid(lib) then error("LiveSoundBlueprintLibrary not found") end
        lib:PostEventByName(valid(survivalPC) and survivalPC or FindFirstOf("PlayerController"), FName(name))
    end)
    if not ok and not SH.soundSaid then SH.soundSaid = true; log("shop: menu sound " .. name .. " failed: " .. tostring(err)) end
end

function shopTick(tick)
    if not CFG.shop.enabled or not D then return end
    if type(SV_ShopRequest) == "function" then
        -- every press waiting (the landing menu's hook queues them), and the texts straight after: taking one press
        -- per tick and updating the texts once a second left ~1 s with no change on screen, so purchases seemed not to
        -- register and players pressed again (user, 2026-10-22: "a good few presses to get it to register")
        local seen = {}
        for _ = 1, 8 do
            local r = SV_ShopRequest()
            if not r or r == "" then break end
            local item = r:gsub("^SV_Buy_", "")
            if seen[item] then
                log("shop: " .. item .. " pressed again within a tick; once is bought")
            else
                seen[item] = true
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
    -- the texts when something changed: at once down at the airfield (where they're read), at most every 5 s in flight
    -- (every kill changed them, and all 21 rows' offers were worked out each time: economy review of 2026-10-25,
    -- "frame-time cost grows with round size")
    if RUN.dirty and (playerOnAirfield() or tick >= (SH.textTick or 0)) then
        RUN.dirty, SH.textTick = false, tick + 20
        local ok, err = pcall(shopTexts)
        if not ok then log("shop: text error " .. tostring(err)) end
    end
end
