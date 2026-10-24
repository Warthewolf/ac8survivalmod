-- sv_shop.lua: the STORE and the landing shop.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_main); a name
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
    local num, model = ok and n and n:match("PP0*(%d+)_(%w+)")
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
                        local tex = (item == "RepairAircraft" and planeIcon()) or texture(SHOP.icons[item] or SHOP.icons.Airfield)
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
        o.label = string.format("%s +%d", it.label, it.step)
        o.help = string.format("%d more %s. Landing doesn't rearm: you fly with what you buy%s.", it.step, it.what,
            cap and string.format(" (you have %d)", cap) or "")
        if cap and max and cap >= max then o.why = "ALREADY AT FULL LOAD." else o.price = shopPrice(name) end
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
        o.help = o.role == "ally_air"
            and string.format("Squadron %s, two F-22s: they take off from the airfield once you're airborne and fight until shot down (%d of %d flights up).",
                c.aircraft.name, up, #units)
            or string.format("The %s sails the waters by the airfield and fights until sunk (%d of %d at sea).",
                c.ships[it.ship].name, up, #units)
        if not c.enabled or not ALLY.ready then o.why = "NOT AVAILABLE."
        elseif not free then o.why = o.role == "ally_air" and "BOTH FLIGHTS ARE UP." or string.format("ALL %d ARE AT SEA.", #units)
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
    -- the STORE's own texts: its row on the landing page, its page titles and the rows between its pages
    local z = string.format("ZOLLARS %d", RUN.credits)
    SV_SetText("SV_Shop_Store", "STORE")
    SV_SetText("SV_Shop_Store_Help", z .. ". Missiles, special weapons, flares, repairs, airfield defences, allied aircraft and ships.")
    SV_SetText("SV_Store_Title", "AIRFIELD STORE: SUPPLIES   " .. z)
    SV_SetText("SV_Store_TitleAirfield", "AIRFIELD STORE: AIRFIELD   " .. z)
    SV_SetText("SV_Store_TitleDocks", "AIRFIELD STORE: DOCKS   " .. z)
    SV_SetText("SV_Store_ToAirfield", "AIRFIELD >")
    SV_SetText("SV_Store_ToAirfield_Help", z .. ". Airfield repairs, AA guns, SAM sites and " .. CFG.allies.aircraft.name .. "'s F-22s.")
    SV_SetText("SV_Store_ToDocks", "DOCKS >")
    SV_SetText("SV_Store_ToDocks_Help", z .. ". Allied ships for the waters by the airfield.")
    SV_SetText("SV_Store_ToSupplies", "SUPPLIES >")
    SV_SetText("SV_Store_ToSupplies_Help", z .. ". Missiles, special weapons, flares and aircraft repairs.")
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
    if o.role == "aircraft" then
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
        local ok, msg = ALLY.buy(o.role, o.unit, it.ship, price)
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
        local max = SV_Ammo(k, 1)                    -- unreadable on the landing menu: the last one seen in flight
        if max < 0 then max = A.max and A.max[k] end
        if not max then return done("NOT AVAILABLE RIGHT NOW.") end
        if A.caps[k] >= max then return done("ALREADY AT FULL LOAD.") end
        local gain = math.min(it.step, max - A.caps[k])   -- the last step up to the aircraft's full load costs less
        if gain < it.step then
            price = math.ceil(price * gain / it.step / 10) * 10
            if RUN.credits < price then return done(string.format("NOT ENOUGH ZOLLARS (%d needed).", price)) end
        end
        for _, kk in ipairs(k == 2 and { 2, 3 } or { k }) do
            if A.caps[kk] then
                A.caps[kk] = A.caps[kk] + gain
                local n = SV_Ammo(kk)
                if n >= 0 then SV_SetAmmo(kk, math.min(n + gain, A.caps[kk]))
                else A.owed = A.owed or {}; A.owed[kk] = true end      -- unreadable now: ammoTick loads it
            end
        end
    else                                             -- the airfield
        AF.full, AF.base, AF.bombBase = math.min(CFG.airfield.hp, AF.hp + it.repair), AF.hits, AF.bomb
        AF.hp = AF.full                             -- airfieldTick works health out from these from now on
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
                -- (user, 2026-10-23: "add a menu beep for everytime you press one of the buttons")
                SHOP.sound(RUN.spent > spent and CFG.shop.sounds.bought or CFG.shop.sounds.refused)
            end
        end
    end
    if tick % 4 == 3 then pcall(SHOP.healthCheck) end
    if RUN.dirty then
        RUN.dirty = false
        local ok, err = pcall(shopTexts)
        if not ok then log("shop: text error " .. tostring(err)) end
    end
end
