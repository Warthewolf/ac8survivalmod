-- sv_coop_planes.lua: Survival COOP, the players' planes: the stand-ins and the real planes, modded planes and skins,
-- what's sent of yours, a rejoin in another aircraft, the players for the other parts. Piece 3 of 5 of sv_coop.lua
-- (sv_coop.lua, sv_coop_joiner.lua, sv_coop_planes.lua, sv_coop_sync.lua, sv_coop_migration.lua), split by
-- tools/lua_split_part.py and run by main.lua right after the piece before it: a name another part uses is a global of
-- this mod's Lua state, its own helpers stay local.
do  -- (sv_coop.lua's do block, continued: this piece's own helpers stay local to it)
local M = COOP.M                                   -- (sv_coop.lua's M, handed on)

---------------------------------------------------------------------------------------------------- the other players' planes
local AF_CODE = "BP_PlayerPlane_PP%d+_(%w+)"
-- Every player plane's blueprint folder and name by its code (AC8's 35, build/research/ui/paths.txt: the ADFX-02's has a
-- variant suffix, so a path built from the code alone missed it in COOP2MP's T2, 2026-10-30): COOP.planeClassPath(code)
-- -> the blueprint class's path, for real player planes in place of the AI stand-ins (docs/re/COOP2MP.md)
local PP_BP = { a10c = "PP0001_a10c", f02a = "PP0002_f02a", f04e = "PP0003_f04e", f15c = "PP0004_f15c", f22a = "PP0005_f22a",
                f35c = "PP0006_f35c", f18c = "PP0007_f18c", j39e = "PP0008_j39e", su34 = "PP0009_su34", e18g = "PP0010_e18g",
                typn = "PP0011_typn", f15j = "PP0012_f15j", a06e = "PP0013_a06e", rflm = "PP0014_rflm", su25 = "PP0015_su25",
                x40a = "PP0016_x40a", mr2k = "PP0017_mr2k", fa36 = "PP0018_fa36", ea36 = "PP0019_ea36", m29a = "PP0020_m29a",
                su57 = "PP0021_su57", f16c = "PP0022_f16c", f14d = "PP0023_f14d", f18f = "PP0024_f18f", f15e = "PP0025_f15e",
                su47 = "PP0026_su47", m21b = "PP0027_m21b", su35 = "PP0028_su35", m31b = "PP0029_m31b", su33 = "PP0030_su33",
                e06b = "PP0031_e06b", f18e = "PP0032_f18e", f14a = "PP0034_f14a", adfx02 = "PP0038_adfx02_L001" }
function COOP.planeClassPath(code)
    local d = type(code) == "string" and PP_BP[code]
    if not d then return nil end
    local b = "BP_PlayerPlane_" .. d
    return string.format("/Game/Blueprints/Vehicle/PLAYER/Plane/%s/%s.%s_C", d, b, b)
end
function myAirframe()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return nil end
    local code = nameOf(pawn):match(AF_CODE)
    local c = cfg()
    if not (code and c.airframes[code]) then                   -- (the others see it as the default: say so, once a code)
        once("afcode" .. tostring(code), string.format("coop: your plane (%s) isn't in [coop] airframes: the others see it "
            .. "as %s", tostring(code or nameOf(pawn):match("^(%S+)")), tostring(c.default)))
    end
    return code and (c.airframes[code] or c.default) or c.default, code
end

function COOP.peerPlane(o, slot)
    if not valid(o) or not inSurvival(o) then return end
    for k, v in pairs({ bPermissionToFire = false, bPermissionToEngage = false, bPermissionToUseFlares = false,
                        bPermissionToProvoke = false, bPermissionToEvade = false, bIsNotLockonTarget = true,
                        bCanBeDamagedByAlly = false, bCauseExplosionOnDeath = false, bShowHUDBox = true }) do
        pcall(function() o[k] = v end)
    end
    pcall(function() o:SetIsInvincible(true) end)
    local P = M.peers[slot] or {}
    M.peers[slot] = P
    P.obj, P.addr, P.spawning, P.shown = o, addrOf(o), nil, nil
    P.gear, P.flare, P.gunNext, P.flareNext = nil, nil, nil, nil       -- (the sync's: a new plane comes gear up)
    local r = type(SV_CoopPeer) == "function" and P.addr and SV_CoopPeer(slot, P.addr) or -9
    log(string.format("coop: player %d's plane is up (%s, %s)", slot + 1, nameOf(o):match("([^%.:]+)$") or "?",
        r == 1 and "moved every frame" or ("NOT moved: " .. tostring(r))))
end

-- COOP2MP T3 (docs/re/COOP2MP.md, hard rule 53): each other player as their own airframe's player plane, as AC8's
-- Online Mode shows them (CFG.coop.real_planes), not an AI stand-in: SV_CoopSpawnPP with their slot (a network dummy
-- controller, role 2) where their stream says they are, bound with SV_CoopPeer; the runtime feeds its own update from
-- their stream (flight.c FlNetFeed: pose, stick, afterburner, flight State). Their airframe's code comes in their "hi"
-- ("pi"); without one (an older build), or if the spawn fails, the AI stand-in as before.
local function realOn() return cfg().real_planes == true and type(SV_CoopSpawnPP) == "function" end
function COOP.realOn() return COOP.open and realOn() end
-- (0.73.80, the 31-round test's finding coop7) A plane code this game has no player plane blueprint for (a modded plane
-- only its player has: Alyssa's Falken, falken-us4ss, PP9001_falken_L001) is shown as a stock player plane of [coop.
-- real_fallback] (falken = adfx02: the add-on is built on the ADFX-02), not an AI stand-in: the joiners flew an AI F-16C
-- for her, an ally's blue box and none of her launches replayed. It gets a player's green box and T4b's replays (flight.c
-- FwWeaponOk drops a weapon number it hasn't). Its own default weapons and paint: their loadout and paint are another
-- airframe's (a modded plane's weapon ids may not exist in this game at all). ((0.73.80) Their own game's stock base for
-- it comes first, [coop] real_default after: M.fallbackFor; the AI stand-in last.)
function M.realFallback(code)
    local t = cfg().real_fallback
    if type(t) ~= "table" or type(code) ~= "string" then return nil end
    local fb = t[code]
    if fb == nil then for k, v in pairs(t) do if type(k) == "string" and k:lower() == code:lower() then fb = v end end end
    if type(fb) ~= "string" or fb == "" or fb == code or not COOP.planeClassPath(fb) then return nil end
    return fb
end
-- (0.73.80, the user 2026-11-04: "try the Falken's own blueprint first") A modded plane's own blueprint by its code
-- ([coop.real_paths]: falken = the Falken add-on's BP_PlayerPlane_PP9001_falken_L001, from Saint Alessia's log of the
-- 31-round test), tried after the path the player's own game sends (M.realClassFor): a game with that add-on installed
-- shows the real thing, with their loadout and paint; one without it, a stock fallback. Only a player plane class's path
-- under /Game/ (M.clsOk); nil when none is listed.
function M.modClassPath(code)
    local t = cfg().real_paths
    if type(t) ~= "table" or type(code) ~= "string" then return nil end
    local p = t[code]
    if p == nil then for k, v in pairs(t) do if type(k) == "string" and k:lower() == code:lower() then p = v end end end
    if not M.clsOk(p) then return nil end
    return p
end
M.modMiss = {}                                           -- (a path that didn't load: not asked again this session)

---------------------------------------------------------------------------------------------------- modded planes and skins
-- (0.73.80, the user 2026-11-04: "Can we do this for all future modded stuff ... if players have mods installed but
-- someone doesn't, that one person who doesn't have the mods sees [the stock version], but if they were to have the mods,
-- they would see the changes"; "planes and skins first") Each game says what it really flies, and every other game shows
-- it where it's installed there, a stock plane where it isn't: never invisible, never a crash.
--   sender: a plane with no stock code (the Falken's falken) adds two last fields to its "hi" (and the host's "pi" relays
--     them, after the Steam ID): its blueprint class's path (/Game/... only) and its stock BASE, the stock player plane it's
--     built on, for games without it: a parent of its class that is a stock player plane's, else its DT_LiveAircraft row's
--     OriginalPlaneStringID (the Falken's PP0038_adfx02_L001: adfx02), else this game's [coop.real_fallback]. A stock plane
--     sends neither (its code says it all): its messages are as before.
--   receiver (spawnReal -> M.realClassFor): a code with no stock blueprint here: their path, then [coop.real_paths],
--     loaded only when it's a player plane class's path (M.clsOk) and kept only when the class loaded is one (IsChildOf
--     LivePlayerPlane, else by its name), with their loadout and paint; else their base, else [coop.real_fallback], else
--     [coop] real_default (f16c), each with its own default weapons and paint; the AI stand-in last.
--   skins (M.paintHere): a paint's skin id this game hasn't (DT_Skin's rows, or the game's information manager's
--     SkinDataMap_) is given as -1, the plane's default paint, the emblems kept; when neither can be read, as sent (as
--     before). The tables are looked for at the main menu (M.tablesPrep), never in a fight.
do
local CLS_MAX = 200                                      -- (a class path's length at most)
local MSG_ROOM = 1080                                    -- (coop.c CO_MAX_LUA 1100: a longer message is cut short)
local KNOWN_SKINS = { 5014001, 21002001, 8014001, 11014001 }   -- (stock skins players flew: a source's check)
local TABLES = {                                         -- (looked for by these paths first, then by name)
    skin = { name = "DT_Skin", paths = { "/Game/Datatables/Information/DT_Skin.DT_Skin", "/Game/Datatables/Skin/DT_Skin.DT_Skin" } },
    aircraft = { name = "DT_LiveAircraft", paths = { "/Game/Datatables/Information/DT_LiveAircraft.DT_LiveAircraft",
                                                     "/Game/Datatables/Aircraft/DT_LiveAircraft.DT_LiveAircraft" } },
}
M.tbl = { path = {}, walks = 0, at = 0, said = {} }
M.skin = { ans = {}, said = {}, n = nil, keyed = nil, ids = nil, dtOk = nil, mapOk = nil }
M.baseOf = {}
local function fstr(v)                                   -- (an FName, an FString or a Lua string, as text)
    if type(v) == "string" then return v end
    if v == nil then return nil end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" then return s end
    return tostring(v)
end
local function shortName(o)
    local ok, n = pcall(function() return o:GetFName():ToString() end)
    if ok and type(n) == "string" and n ~= "" then return n end
    return (nameOf(o):match("([^%.:/%s]+)$"))
end

-- a player plane blueprint class's path: under /Game/, [%w_/.] only, a package and its class (/Game/.../X.X_C, X a
-- BP_PlayerPlane_...), <= 200 characters; with code, the class's own code (BP_PlayerPlane_PPnnnn_<code>) must be it
function M.clsOk(p, code)
    if type(p) ~= "string" or #p > CLS_MAX or p:sub(1, 6) ~= "/Game/" or p:find("//", 1, true) then return false end
    if not p:match("^[%w_/%.]+$") or select(2, p:gsub("%.", "")) ~= 1 then return false end   -- (one dot: no "..")
    local pkg, obj = p:match("/([%w_]+)%.([%w_]+)$")
    if not (pkg and obj == pkg .. "_C" and obj:match("^BP_PlayerPlane_")) then return false end
    if code ~= nil then
        local c = obj:match(AF_CODE)
        if not (c and type(code) == "string" and c:lower() == code:lower()) then return false end
    end
    return true
end
function M.baseOk(b) return type(b) == "string" and #b <= 16 and b:match("^%w+$") ~= nil end

-- the new last fields of "hi" / "pi" (f, the message's fields so far): a plane with no stock code's class path and stock
-- base; the path left out when the message would be cut (CO_MAX_LUA), nothing for a stock plane
function M.modFields(f, code, cls, base)
    if type(code) ~= "string" or code == "" or COOP.planeClassPath(code) then return f end
    cls = M.clsOk(cls, code) and cls or ""
    base = M.baseOk(base) and base or ""
    if cls == "" and base == "" then return f end
    local n = 0
    for i = 1, #f do n = n + #tostring(f[i]) + 1 end
    if n + #cls + #base + 2 > MSG_ROOM then
        once("modfieldslong", string.format("coop: a message with your plane's class path would be %d characters: sent without it "
            .. "(players with its add-on see its stock base %s)", n + #cls + #base + 2, base ~= "" and base or "or their own fallback"))
        cls = ""
    end
    f[#f + 1], f[#f + 2] = cls, base
    return f
end

-- the tables the plane and skin checks read, looked for once a session where no fight is (COOP.tick with no run: the
-- main menu, the hangar): by a few likely paths, then one walk over the DataTables loaded (3 at most, 10 s apart)
function M.tablesPrep()
    local T = M.tbl
    local now = os.clock()
    if now < (T.at or 0) then return end
    T.at = now + 10
    local want = false
    for k, d in pairs(TABLES) do
        if T[k] and not liveObj(T[k]) then T[k] = nil end
        if not T[k] and not T.tried then
            for _, p in ipairs(d.paths) do
                local ok, o = pcall(StaticFindObject, p)
                if ok and o ~= nil and valid(o) then T[k], T.path[k] = o, p; break end
            end
        end
        if not T[k] then want = true end
    end
    T.tried = true
    if want and T.walks < 3 and not (type(walkBusy) == "function" and walkBusy()) then
        T.walks = T.walks + 1
        local ok, list = pcall(FindAllOf, "DataTable")
        for _, o in ipairs((ok and type(list) == "table") and list or {}) do
            local n = valid(o) and shortName(o)
            for k, d in pairs(TABLES) do
                if n == d.name and not T[k] then T[k], T.path[k] = o, (nameOf(o):match("(/Game/%S+)$") or n) end
            end
        end
    end
    for k, d in pairs(TABLES) do
        local s = T[k] and ("found: " .. tostring(T.path[k])) or (T.walks >= 3 and "not found (its plane / skin checks without it)" or nil)
        if s and T.said[k] ~= s then T.said[k] = s; log("coop: the game's " .. d.name .. " " .. s) end
    end
    local okS, errS = pcall(M.skinPrep)
    if not okS then once("skinPrep", "coop: skins: DT_Skin error " .. tostring(errS)) end
end

---------------------------------------------------------------------------------------------------- your plane: what's sent
-- the stock base of a plane with no stock code (nil, how when none): (i) a parent of its class that is a stock player
-- plane's, (ii) its DT_LiveAircraft row's OriginalPlaneStringID, (iii) this game's [coop.real_fallback]
function M.aircraftOrigin(pawn, cls)
    local dt = M.tbl.aircraft
    if not (dt and liveObj(dt)) then return nil end
    local id, sid = nil, (cls ~= nil and shortName(cls) or ""):match("^BP_PlayerPlane_(.+)_C$")
    pcall(function() id = pawn.PlaneTypeID end)
    if type(id) ~= "number" then id = nil end
    local function mine(r)
        local okP, pid = pcall(function() return r.PlaneID end)
        if okP and id and pid == id then return true end
        local okS, ps = pcall(function() return fstr(r.PlaneStringID) end)
        return okS and sid ~= nil and ps == sid
    end
    local keys, row = {}, nil
    if id then keys[#keys + 1] = tostring(math.floor(id)) end
    if sid then keys[#keys + 1] = sid end
    for _, k in ipairs(keys) do
        local ok, r = dtCall(dt, "FindRow", k)
        if ok and r ~= nil and mine(r) then row = r; break end
    end
    if row == nil then
        local names = rowList(dt) or {}
        for i = 1, math.min(#names, 600) do
            local ok, r = dtCall(dt, "FindRow", names[i])
            if ok and r ~= nil and mine(r) then row = r; break end
        end
    end
    if row == nil then return nil end
    local okO, o = pcall(function() return fstr(row.OriginalPlaneStringID) end)   -- (an FName: never Reference, rule 29)
    return (okO and type(o) == "string" and o ~= "" and o ~= "None") and o or nil
end
function M.baseFor(code, cls, pawn)
    if type(code) ~= "string" then return nil, "no plane code" end
    if COOP.planeClassPath(code) then return code, "stock" end
    local c = cls
    for _ = 1, 12 do                                     -- (i)
        if c == nil then break end
        local okS, sup = pcall(function() return c:GetSuperStruct() end)
        if not (okS and sup ~= nil and valid(sup)) then break end
        local n = shortName(sup) or ""
        local bc = n:match("^" .. AF_CODE)
        if bc and COOP.planeClassPath(bc:lower()) then return bc:lower(), "its blueprint's parent " .. n end
        if n == "LivePlayerPlane" then break end
        c = sup
    end
    local okA, ob = pcall(M.aircraftOrigin, pawn, cls)   -- (ii)
    local oc = okA and type(ob) == "string" and ob:match("^PP%d+_(%w+)")
    if oc and oc:lower() ~= code and COOP.planeClassPath(oc:lower()) then
        return oc:lower(), "its aircraft row's OriginalPlaneStringID " .. ob
    end
    local fb = M.realFallback(code)                      -- (iii)
    if fb then return fb, "[coop.real_fallback]" end
    return nil, "none found (its class's parents, its aircraft row, [coop.real_fallback])"
end
-- your plane's class path ("" when it can't be read or sent) and stock base (""): once a plane (by its address and code),
-- the base once a class (M.baseOf), logged once
function M.myPlane(pawn, code)
    pawn = pawn or (survivalPC and valid(survivalPC) and survivalPC.Pawn)
    if not valid(pawn) then return "", "" end
    local a = addrOf(pawn)
    local mp = M.myPlaneAt
    if mp and mp.addr == a and mp.code == code then return mp.cls, mp.base end
    local cls, path = nil, ""
    pcall(function() cls = pawn:GetClass() end)
    if cls ~= nil and valid(cls) then
        local full = nameOf(cls)
        local p = full:match("^%S+%s+(/Game/%S+)$") or full:match("^(/Game/%S+)$")
        if p and M.clsOk(p, code) then path = p end
    else
        cls = nil
    end
    local key = path ~= "" and path or ("code:" .. tostring(code))
    local b = M.baseOf[key]
    if not b then
        local okB, base, how = pcall(M.baseFor, code, cls, pawn)
        if not okB then base, how = nil, "error " .. tostring(base) end
        b = { base = base or "", how = how }
        M.baseOf[key] = b
        if type(code) == "string" then
            log(string.format("coop: your plane %s (%s): its stock base for players without it: %s (%s)", code,
                path ~= "" and path or "its class path unknown", base or "none", tostring(how)))
        end
    end
    M.myPlaneAt = { addr = a, code = code, cls = path, base = b.base }
    return path, b.base
end

---------------------------------------------------------------------------------------------------- another player's plane here
-- a class path loaded and checked a player plane's (nil, why when not; a path that failed isn't asked again: M.modMiss)
function M.isPlayerPlaneClass(c)
    if not (M.ppRoot and valid(M.ppRoot)) then
        local ok, r = pcall(StaticFindObject, "/Script/Live.LivePlayerPlane")
        M.ppRoot = (ok and r ~= nil and valid(r)) and r or nil
    end
    if M.ppRoot then
        local ok, r = pcall(function() return c:IsChildOf(M.ppRoot) end)
        if ok and type(r) == "boolean" then return r, r and "a LivePlayerPlane" or "not a LivePlayerPlane" end
    end
    local n = shortName(c) or "?"
    return n:match("^BP_PlayerPlane_[%w_]+_C$") ~= nil, "by its name " .. n
end
function M.tryClass(p)
    if M.modMiss[p] then return nil, "not installed here (known)" end
    local okL, c = pcall(loadObject, p)
    if not (okL and c ~= nil and valid(c)) then M.modMiss[p] = true; return nil, "not installed here" end
    local isPP, by = M.isPlayerPlaneClass(c)
    if not isPP then M.modMiss[p] = true; return nil, "not a player plane (" .. tostring(by) .. ")" end
    return c
end
-- the stock plane shown for a code with no blueprint here: their game's base, this game's [coop.real_fallback], its
-- [coop] real_default (nil: the AI stand-in)
function M.fallbackFor(code, base)
    local b = type(base) == "string" and base:lower() or nil
    if M.baseOk(b) and b ~= code and COOP.planeClassPath(b) then return b, "their game's base" end
    local fb = M.realFallback(code)
    if fb then return fb, "[coop.real_fallback]" end
    local d = cfg().real_default
    if type(d) == "string" and d ~= "" then
        d = d:lower()
        if COOP.planeClassPath(d) and d ~= code then return d, "[coop] real_default" end
        once("realdefault", "coop: [coop] real_default " .. d .. " isn't a stock plane code: a plane with no blueprint here is an AI stand-in")
    end
    return nil
end
-- (spawnReal) the class to spawn for player slot's code: cls (nil if it didn't load), its path, the fallback's code (nil:
-- theirs), how; or false, why when there's none (the AI stand-in)
function M.realClassFor(slot, code, r0)
    local stock = COOP.planeClassPath(code)
    if stock then return loadObject(stock), stock, nil, "stock" end
    local cands = {}
    if r0 and M.clsOk(r0.cls, code) then cands[1] = { p = r0.cls, src = "the path their game sent" } end
    local rp = M.modClassPath(code)
    if rp and not (cands[1] and cands[1].p == rp) then cands[#cands + 1] = { p = rp, src = "[coop.real_paths]" } end
    local missed = {}
    for _, cd in ipairs(cands) do
        local known = M.modMiss[cd.p]
        local c, why = M.tryClass(cd.p)
        if c then
            log(string.format("coop: player %d's %s: its own blueprint is installed here (%s): the real thing (%s)", slot + 1,
                code, cd.p, cd.src))
            return c, cd.p, nil, cd.src
        end
        if not known then cd.why = why; missed[#missed + 1] = cd end
    end
    local fb, how = M.fallbackFor(code, r0 and r0.base)
    for _, cd in ipairs(missed) do
        log(string.format("coop: player %d's %s: its own blueprint %s (%s): %s instead (its path from %s)", slot + 1, code,
            cd.why == "not installed here" and "isn't installed here" or ("was rejected, " .. tostring(cd.why)), cd.p,
            fb and (how == "[coop.real_fallback]" and how or ("a real " .. fb .. " (" .. how .. ")")) or "the AI stand-in", cd.src))
    end
    if not fb then
        local d = cfg().real_default
        return false, string.format("no player plane blueprint for %s (no base from their game, no [coop.real_fallback] for it, "
            .. "[coop] real_default %s)", tostring(code), (type(d) == "string" and d ~= "") and d or "off")
    end
    local fp = COOP.planeClassPath(fb)
    return loadObject(fp), fp, fb, how
end

---------------------------------------------------------------------------------------------------- skins
-- the skin checks' sources, worked out where no fight is (M.tablesPrep: DT_Skin's keying and ids, again when its row
-- count changes) or on first use (the information manager's SkinDataMap_, one lookup a skin); each kept only when it
-- lists a stock skin (yours, or one players flew: KNOWN_SKINS)
local function mySkin()
    local p = type(M.myPaint) == "function" and M.myPaint() or ""
    local s = tonumber((tostring(p):match("^(%-?%d+)/")))
    return (s and s >= 0) and s or nil
end
local function knowsStock(has)
    local list = { mySkin() }
    for _, id in ipairs(KNOWN_SKINS) do list[#list + 1] = id end
    for _, id in ipairs(list) do if has(id) == true then return true end end
    return false
end
local function skinMap()
    local ok, m = pcall(function()
        local gi = type(gameInstance) == "function" and gameInstance() or nil
        if gi == nil then return nil end
        local im = gi.InformationManager_
        if not (im ~= nil and valid(im)) then return nil end
        return im.SkinDataMap_
    end)
    return ok and m or nil
end
local function mapHas(id)
    local ok, r = pcall(function() return skinMap():Contains(id) end)
    if ok and type(r) == "boolean" then return r end      -- (false is an answer: not `and r or nil`)
    return nil
end
local function dtHas(id)
    local S, dt = M.skin, M.tbl.skin
    if not (dt and S.dtOk and liveObj(dt)) then return nil end
    if S.ids and S.ids[id] then return true end          -- (every row's SkinID, read at the main menu)
    if S.keyed == "name" then                            -- (a row added since, named by its id as the others)
        local ok, r = dtCall(dt, "FindRow", tostring(id))
        if not ok then return nil end
        if r == nil then return false end
        local okI, v = pcall(function() return r.SkinID end)
        return not (okI and type(v) == "number") or v == id
    end
    if S.ids then return false end
    return nil
end
function M.skinPrep()
    local S, dt = M.skin, M.tbl.skin
    if not (dt and liveObj(dt)) then return end
    local names = rowList(dt)
    if not names then if not S.said.rows then S.said.rows = true; log("coop: skins: DT_Skin's rows can't be read") end; return end
    if S.n == #names then return end                     -- (no new rows since: a skin add-on registers at the main menu)
    S.n, S.ans = #names, {}
    local byName, read = true, 0
    for i = 1, math.min(#names, 8) do
        local ok, r = dtCall(dt, "FindRow", names[i])
        local okI, id = false, nil
        if ok and r ~= nil then okI, id = pcall(function() return r.SkinID end) end   -- (the int only: never DecalMaterialRef)
        if okI and type(id) == "number" then
            read = read + 1
            if tostring(math.floor(id)) ~= names[i] then byName = false end
        end
    end
    if read == 0 then
        S.keyed, S.ids, S.dtOk = nil, nil, false
    else
        -- (every row's SkinID kept either way: an add-on's rows may be named otherwise than the game's)
        S.keyed, S.ids = byName and "name" or "field", {}
        for _, nm in ipairs(names) do
            local ok, r = dtCall(dt, "FindRow", nm)
            local okI, id = false, nil
            if ok and r ~= nil then okI, id = pcall(function() return r.SkinID end) end
            if okI and type(id) == "number" then S.ids[math.floor(id)] = true end
        end
    end
    if read > 0 then S.dtOk = true; S.dtOk = knowsStock(dtHas) end
    local s = string.format("coop: skins: DT_Skin %s, %d rows%s", tostring(M.tbl.path.skin), #names,
        read == 0 and ": their SkinID can't be read, not used"
        or (S.dtOk and (", keyed by " .. (S.keyed == "name" and "the skin id" or "their SkinID") .. ": other players' skins are checked against it")
        or ": none of the stock skins in it, not used"))
    if S.said.dt ~= s then S.said.dt = s; log(s) end
end
-- true / false: skin id is / isn't in this game; nil: it can't be told (no source); cached for the session
function M.skinHere(id)
    local S = M.skin
    if S.ans[id] ~= nil then return S.ans[id] end
    if S.mapOk == nil and skinMap() ~= nil then
        S.mapOk = knowsStock(mapHas)
        log("coop: skins: the game's information manager's SkinDataMap_ " .. (S.mapOk and "lists the stock skins: other players' "
            .. "skins are checked against it" or "doesn't list the stock skins here: not used"))
    end
    local said, yes = false, false
    if S.mapOk then
        local r = mapHas(id)
        if r ~= nil then said, yes = true, r end
    end
    if not yes then
        local r = dtHas(id)
        if r ~= nil then said = true; yes = yes or r end
    end
    if not said then return nil end
    S.ans[id] = yes
    return yes
end
-- the paint ("skin/flags/e1,e2,...") given to player slot's plane here: its skin -1 (the plane's default) when this game
-- hasn't it, the emblems kept; as sent when it can't be told. (Review of 0.73.80) A negative id other than -1, or one past
-- an int32, is no game's skin (-1 is the only one the skin loader is known to take as "the default"): -1 whatever the
-- tables say, so no unknown skin reaches SV_CoopSpawnPP from a broken or hostile game.
function M.paintHere(slot, pt)
    if type(pt) ~= "string" or pt == "" then return pt end
    local skin, rest = pt:match("^(%-?%d+)(/.*)$")
    local id = tonumber(skin)
    if not id or id == -1 then return pt end
    if id < 0 or id > 2147483647 then
        local k = slot .. ":" .. skin
        if not M.skin.said[k] then
            M.skin.said[k] = true
            log(string.format("coop: player %d's skin %s isn't a skin id: their plane's default paint", slot + 1, skin:sub(1, 24)))
        end
        return "-1" .. rest
    end
    local okH, have = pcall(M.skinHere, id)
    if not okH then once("skinerr", "coop: skins: check error " .. tostring(have)); have = nil end
    if have == nil then
        once("skinsunchecked", "coop: skins aren't checked here (no DT_Skin found, the game's SkinDataMap_ not readable): "
            .. "each player's paint given as sent")
        return pt
    end
    if have then return pt end
    local k = slot .. ":" .. skin
    if not M.skin.said[k] then
        M.skin.said[k] = true
        log(string.format("coop: player %d's skin %s isn't installed here: their plane's default paint", slot + 1, skin))
    end
    return "-1" .. rest
end

---------------------------------------------------------------------------------------------------- what the others see
-- (0.73.80, finding coop7) What the others see your plane as, by this game's settings (each game decides by its own
-- [coop]; the shipped ones agree): nil when it's your own airframe, else its name, how, and true when those with its
-- add-on see the real thing (your class path is sent, or [coop.real_paths] lists it). The host's own Falken was an F-16C
-- to everyone and only its log said so ("isn't in [coop] airframes"); now each player sees it on screen once a level
-- (M.seenAsTick), and the log has it.
function M.seenAs(code, cls, base)
    if type(code) ~= "string" then return nil end
    local c = cfg()
    local row = tostring(type(c.airframes) == "table" and c.airframes[code] or c.default)
    local ai = (row:match("^(%w+)_") or row):upper()
    if c.real_planes == true then
        if COOP.planeClassPath(code) then return nil end
        local fb, how = M.fallbackFor(code, base)
        if how == "their game's base" then how = "its stock base" end
        local own = M.clsOk(cls, code) or M.modClassPath(code) ~= nil
        if fb and own then
            return string.upper(fb), "itself where its add-on is installed, else a real " .. fb .. " (" .. how .. ")", true
        end
        if fb then return string.upper(fb), "a real " .. fb .. " (" .. how .. ")" end
        if own then return "AN AI " .. ai, "itself where its add-on is installed, else an AI stand-in on " .. row, true end
    elseif type(c.airframes) == "table" and c.airframes[code] then
        return nil
    end
    return ai .. " (AI)", "an AI stand-in on " .. row
end
function M.seenAsTick(code)
    if not (D and code) or (M.seenAsD == D and M.seenAsCode == code) then return end
    M.seenAsD, M.seenAsCode = D, code
    local cls, base = M.myPlane(nil, code)
    local as, how, withMod = M.seenAs(code, cls, base)
    if not as then return end
    local mine = M.myAircraft and M.myAircraft() or ""
    mine = (mine ~= "" and mine or code):upper()
    log(string.format("coop: the other players see your %s (%s) as %s, by this game's settings (theirs decide there)", mine, code, how))
    callout(withMod and ("OTHERS SEE YOUR " .. mine .. " (" .. as .. " WITHOUT THE ADD-ON)") or ("OTHERS SEE YOUR " .. mine .. " AS " .. as), nil)
end
end

local function spawnReal(slot, P, code, lo, pt, r0)
    if walkHold and walkHold() then return nil, "the walks are held (a level going away)" end   -- (0.73.73: a held search could orphan it)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return nil, "you have no plane here yet" end
    -- ((0.73.80) its stock blueprint; else their own (the path their game sent, [coop.real_paths]) if installed here; else
    -- a stock fallback with its own weapons and paint: M.realClassFor)
    local okC, cls, path, fb, how = pcall(M.realClassFor, slot, code, r0)
    if not okC then return nil, "its class: error " .. tostring(cls) end
    if cls == false then return nil, path end            -- (no blueprint here and no fallback: path is why)
    if not (cls ~= nil and valid(cls)) then return nil, "its class didn't load (" .. tostring(path) .. ")" end
    if fb then lo, pt = "", "" end
    pt = cfg().real_paint ~= false and pt or ""
    if pt ~= "" then pt = M.paintHere(slot, pt) end      -- ((0.73.80) a skin this game hasn't: the plane's default)
    P.paintGiven = pt
    local at, yaw = P.at, (P.rot and P.rot[2]) or 0
    -- ((0.73.77) SV_CoopSpawnPP destroys the plane the runtime keeps in this slot: a set-aside one moved on first, M.nativeFree)
    local okF, whyF = M.nativeFree(slot)
    if not okF then return nil, whyF end
    local a = SV_CoopSpawnPP(addrOf(pawn), at.X, at.Y, at.Z, yaw, addrOf(cls), slot, lo or "", pt)
    if type(a) ~= "number" or a <= 0 then return nil, "SV_CoopSpawnPP " .. tostring(a) end
    for _, x in ipairs(FindAllOf("LivePlayerPlane") or {}) do
        if valid(x) and addrOf(x) == a then return x, nil, fb, how end
    end
    return nil, "spawned (" .. tostring(a) .. ") but not found"
end

---------------------------------------------------------------------------------------------------- a rejoin in another aircraft
-- (0.73.77, plan workstream C) A player who left (their link let go: "sys|left" on the host, its "po" on the joiners) or
-- whose game started a new session ("sys|restart" on the host, its "rj" on the joiners) and is back in another aircraft
-- (or with other weapons) gets a new plane here. Shake Shack's run of 2026-11-02: liljojofett left in a Su-47 and came
-- back 18 s later in a Rafale M, and everyone saw the Su-47 to the end of the level ("player 2's loadout changed: their
-- real plane here keeps the one it was spawned with"). A live player plane is still never destroyed mid-level (0.73.11's
-- crash, a frame after a replaced real plane was freed): the old one is set aside (M.setAside: unbound, hidden, collision
-- and tick off, moved up out of the fight, as host migration's) and the new one spawned as a newcomer's. SV_CoopSpawnPP
-- destroys what the runtime keeps in the slot it's given (coop.c), so a set-aside real plane is moved out of its
-- player's slot into one no player has (SV_CoopSwapPP; M.parkAt) and on again before a plane is spawned there. An AI
-- stand-in can't change airframe once up, nor its unit spawn again while it's up: the new one flies a free stand-in unit
-- (M.standInUnit; M.unitSlot maps it back to its player). A change by a player who never left keeps the rule: their
-- plane here keeps its weapons until the next level. CFG.coop.rejoin.
do
M.left, M.aside, M.parkAt, M.standUnit, M.unitSlot, M.asideUnit = {}, {}, {}, {}, {}, {}
M.radarSt = {}                                       -- ((0.73.83) planes taken off the radar here, by address: { obj, was })
local function rejoinCfg() return cfg().rejoin or {} end
-- ((0.73.83) the user, 2026-11-04: "people who leave and rejoin, their plane disappears correctly but not their radar
-- blip") SetActorHiddenInGame hides a plane's meshes, not its minimap icon: the radar draws the game's objects hidden or
-- not, at their map position, and a set-aside plane moved straight up kept its blip where it was (Saint Alessia's 0.73.81
-- run: player 2's F-22A set aside at 12:57:23). A plane hidden here (left, out of the mission, DOWN, waiting for a
-- rejoin's airframe, set aside) is taken off the radar too: deactivated (LiveGameObject.bIsActivated, the game's own
-- active flag, false while it's hidden, put back as it was when it's shown), and a set-aside one, never shown again, also
-- moved aside_far_km off the map. Which of the two the radar heeds isn't known yet: the log says what each did.
-- [coop.rejoin] radar_off = false leaves the flag alone. What to put back is kept by the plane's address (M.radarSt),
-- not on the player's table: that's made again on a new run, a slot move and a joiner's rebuild, and a plane whose state
-- was lost would stay off the radar once shown.
-- (UE4SS may give two Lua objects for one game object, and a freed plane's address can come round again for another
-- object: an entry is this plane's while the object at its address is live and still has the name it was made with, as
-- M.objsOf's prune checks; one that isn't is dropped)
local function radarKey(o) return addrOf(o) or o end
local function sameObj(e, o) return o ~= nil and live(o) and e.name ~= nil and nameOf(o) == e.name end
M.sameObj = sameObj
function M.radarOff(P)
    local o = P and P.obj
    if not (o and live(o)) then return "no plane" end
    local a = radarKey(o)
    local st = M.radarSt[a]
    if st and not sameObj(st, o) then M.radarSt[a], st = nil, nil end
    if rejoinCfg().radar_off == false and not st then return nil end
    local was, now
    pcall(function() was = o.bIsActivated end)
    if st then                                       -- (off already: off again if the game put it back on, its first state kept)
        if was == false then return "off the radar already" end
        pcall(function() o.bIsActivated = false end)
        return "off the radar again (the game had put it back on)"
    end
    local okW = pcall(function() o.bIsActivated = false end)
    pcall(function() now = o.bIsActivated end)
    M.radarSt[a] = { obj = o, was = was, name = nameOf(o) }
    if okW and now == false then return "off the radar (deactivated)" end
    return "NOT deactivated (bIsActivated " .. tostring(now) .. ")"
end
function M.radarOn(P)
    local o = P and P.obj
    if not o then return nil end
    local a = radarKey(o)
    local st = M.radarSt[a]
    if not st then return nil end
    M.radarSt[a] = nil
    if not sameObj(st, o) then return nil end
    if st.was == false then return "on the radar as it was (it was deactivated before)" end
    local okW = pcall(function() o.bIsActivated = true end)
    return okW and "on the radar again (activated)" or "NOT activated again"
end
-- a slot no player has in the runtime (nor this game, nor a plane kept there), the highest first (the host gives the
-- lowest free one to a newcomer)
local function freeNative(but)
    for t = MAX_SLOT, 0, -1 do
        if t ~= but and t ~= COOP.slot and not M.roster[t] and not (M.peers[t] and M.peers[t].obj) and not M.parkAt[t] then return t end
    end
    return nil
end
-- (spawnReal, before SV_CoopSpawnPP for `slot`) a set-aside plane the runtime keeps in that slot moved to a free one.
-- false, why when it can't be (SV_CoopSpawnPP would destroy it: no real plane spawned, the AI stand-in instead)
function M.nativeFree(slot)
    local e = M.parkAt[slot]
    if not e then return true end
    if not live(e.obj) then M.parkAt[slot] = nil; return true end         -- (gone with its level: nothing to destroy)
    local t = type(SV_CoopSwapPP) == "function" and freeNative(slot) or nil
    if not t then return false, "a set-aside plane is kept in its slot and no other slot is free" end
    SV_CoopSwapPP(slot, t)
    M.parkAt[slot], M.parkAt[t], e.slot = nil, e, t
    log(string.format("coop: a set-aside plane kept in slot %d moved to slot %d (player %d's new plane spawns there)",
        slot + 1, t + 1, slot + 1))
    return true
end
-- (M.slotFix's SV_CoopSwapPP(a, b): player slots a and b trade planes) the set-aside planes the runtime keeps in either
-- slot go with the swap, and a rejoin's mark goes with its player
function M.slotSwapped(a, b)
    M.parkAt[a], M.parkAt[b] = M.parkAt[b], M.parkAt[a]
    if M.parkAt[a] then M.parkAt[a].slot = a end
    if M.parkAt[b] then M.parkAt[b].slot = b end
    M.left[a], M.left[b] = M.left[b], M.left[a]
end
-- player `slot`'s plane here (P) set aside, never destroyed: unbound, hidden, collision and tick off, moved up out of the
-- fight (aside_alt_km); a real one moved out of its player's slot in the runtime (kept where it is, and moved before
-- that slot's next real plane spawns, when no other slot is free), an AI stand-in's unit never flown again. M.peers[slot]
-- is the caller's.
function M.setAside(slot, P, why)
    local o = P and P.obj
    if not (o and live(o)) then return false end
    M.gunOff(P)                                          -- ((review of 0.73.80) its gun's trigger let go: nothing drives it from here on)
    if type(SV_CoopPeer) == "function" then SV_CoopPeer(slot, 0) end
    local kept
    if P.real then
        local t = type(SV_CoopSwapPP) == "function" and freeNative(slot) or nil
        if t then
            SV_CoopSwapPP(slot, t)                       -- (t keeps nothing: freeNative; slot's plane is this one)
            M.parkAt[t] = { obj = o, slot = t, from = slot }
            kept = string.format("kept in slot %d", t + 1)
        else
            M.parkAt[slot] = { obj = o, slot = slot, from = slot }
            kept = "kept in its slot (no other free: moved before a new plane spawns there)"
        end
    else
        local u = P.unit or PEER_UNITS[slot]
        M.asideUnit[u] = true
        if M.unitSlot[u] then M.unitSlot[u] = nil end
        if M.standUnit[slot] == u then M.standUnit[slot] = nil end
        kept = "its unit " .. u .. " not flown again"
    end
    pcall(function() o:SetActorHiddenInGame(true) end)
    pcall(function() o:SetActorEnableCollision(false) end)
    local okT = pcall(function() o:SetActorTickEnabled(false) end)
    local radar = M.radarOff(P)
    local alt = tonumber(rejoinCfg().aside_alt_km) or 30
    local far = tonumber(rejoinCfg().aside_far_km) or 1000
    local okM, at = false, nil
    if alt > 0 or far > 0 then
        okM = pcall(function()
            local v = o:K2_GetActorLocation()
            local to = { X = v.X, Y = v.Y, Z = alt > 0 and alt * 100000 or v.Z }
            if far > 0 then to.X, to.Y = far * 100000, (#M.aside + 1) * 2000000 end   -- (off the map, 20 km apart)
            o:K2_SetActorLocation(to, false, {}, true)
            at = to
        end)
    end
    M.aside[#M.aside + 1] = { obj = o, slot = slot, real = P.real, unit = (not P.real) and (P.unit or PEER_UNITS[slot]) or nil,
                              at = okM and at or nil, radar = radar ~= nil and radar ~= "no plane", name = nameOf(o) }
    local where = "left where it is"
    if okM then
        where = alt > 0 and string.format("moved %.0f km up", alt) or "moved"
        if far > 0 then where = where .. string.format(" and %.0f km off the map", far) end
    elseif alt > 0 or far > 0 then
        where = "NOT moved"
    end
    log(string.format("coop: player %d's plane here set aside, hidden (%s): %s, tick %s, %s%s", slot + 1, why, kept,
        okT and "off" or "NOT off", where, radar and ("; " .. radar) or ""))
    return true
end
-- (COOP.tick, every 5 s) each set-aside plane kept off the radar: deactivated again and moved back off the map when the
-- game (a restart in the same level, a checkpoint) has put it back; said once a plane
function M.asideTick(now)
    if #M.aside == 0 or now < (M.asideAt or 0) then return end
    M.asideAt = now + 5
    local keep = {}
    for _, e in ipairs(M.aside) do
        local o = e.obj
        if sameObj(e, o) then keep[#keep + 1] = e end   -- (a plane gone, or its address another object's now: dropped, never touched)
        if keep[#keep] == e then
            if e.radar then
                local act
                pcall(function() act = o.bIsActivated end)
                if act == true then
                    pcall(function() o.bIsActivated = false end)
                    e.reAct = (e.reAct or 0) + 1
                    if e.reAct == 1 then
                        log(string.format("coop: player %d's set-aside plane was activated again (by the game): deactivated again", e.slot + 1))
                    end
                end
            end
            if e.at then
                local v
                pcall(function() v = o:K2_GetActorLocation() end)
                if v and (math.abs(v.X - e.at.X) > 100000 or math.abs(v.Y - e.at.Y) > 100000 or math.abs(v.Z - e.at.Z) > 100000) then
                    pcall(function() o:K2_SetActorLocation(e.at, false, {}, true) end)
                    e.reMove = (e.reMove or 0) + 1
                    if e.reMove == 1 then
                        log(string.format("coop: player %d's set-aside plane was moved back (by the game, %.0f km from its spot): moved off the map again",
                            e.slot + 1, math.sqrt((v.X - e.at.X) ^ 2 + (v.Y - e.at.Y) ^ 2 + (v.Z - e.at.Z) ^ 2) / 100000))
                    end
                end
            end
        elseif e.unit and M.asideUnit then
            M.asideUnit[e.unit] = nil
        end
    end
    M.aside = keep
end
-- (at a new level here) the set-aside planes gone with their level let go; a restart in the same level keeps them
function M.asidePrune()
    local keep = {}
    for _, e in ipairs(M.aside) do
        if (e.name and sameObj(e, e.obj)) or (not e.name and live(e.obj)) then keep[#keep + 1] = e
        elseif e.unit then M.asideUnit[e.unit] = nil end
    end
    M.aside = keep
    for t, e in pairs(M.parkAt) do if not live(e.obj) then M.parkAt[t] = nil end end
    for a, st in pairs(M.radarSt) do if not sameObj(st, st.obj) then M.radarSt[a] = nil end end   -- ((0.73.83) gone with their level)
end
-- whether stand-in unit u is set aside or flown for a player other than `slot`
local function unitTaken(u, slot)
    if M.asideUnit[u] then return true end
    if M.unitSlot[u] ~= nil and M.unitSlot[u] ~= slot then return true end
    for t, Q in pairs(M.peers) do
        if t ~= slot and Q.obj and not Q.real and (Q.unit or PEER_UNITS[t]) == u then return true end
    end
    return false
end
-- the stand-in unit player `slot`'s AI plane flies here: their own (SV_Unit_CoopPeer<A-X>), else (it's set aside, or
-- another player's) a free one: this game's own slot's (never flown here), then the highest slots nobody has. nil: none
function M.standInUnit(slot)
    local cur = M.standUnit[slot]
    if cur and not unitTaken(cur, slot) then return cur end
    M.standUnit[slot] = nil
    local own = PEER_UNITS[slot]
    if not unitTaken(own, slot) then return own end
    local order = {}
    if COOP.slot and COOP.slot ~= slot then order[1] = COOP.slot end
    for t = MAX_SLOT, 0, -1 do if t ~= slot and t ~= COOP.slot and not M.roster[t] then order[#order + 1] = t end end
    for _, t in ipairs(order) do
        local u = PEER_UNITS[t]
        if not unitTaken(u, slot) and not (type(SV_UnitAlive) == "function" and (tonumber(SV_UnitAlive(u)) or 0) > 0) then
            M.standUnit[slot], M.unitSlot[u] = u, slot
            log(string.format("coop: player %d's stand-in flies %s here (theirs, %s, is set aside or another player's)", slot + 1, u, own))
            return u
        end
    end
    once("standin" .. slot, string.format("coop: player %d's stand-in: no free stand-in unit here (theirs, %s, is set aside)", slot + 1, own))
    return nil
end
-- (on the host: "sys|left", "sys|restart"; on a joiner: the host's "po" / "rj") player `slot` may come back in another
-- aircraft: marked until they're back in the mission
function M.markLeft(slot, why)
    if not slotOk(slot) or slot == COOP.slot then return end
    if rejoinCfg().enabled == false then return end
    M.left[slot] = { at = os.clock(), why = why }
    local P = M.peers[slot]
    if P and P.obj then
        log(string.format("coop: player %d %s: if they're back in another aircraft, their plane here (%s) is set aside and a "
            .. "new one spawned", slot + 1, why, tostring(P.real and P.code or P.row or "?")))
    end
end
-- (peerTick, a player marked by M.markLeft) -> their P (a new one once the old plane's set aside: spawned below as a
-- newcomer's) and whether their old plane stays hidden meanwhile (back in the mission, their airframe not heard of yet:
-- up to wait_s)
function M.rejoinTick(slot, P, r0, code, lo, fresh)
    local rj = M.left[slot]
    if not rj then return P, false end
    if not (P.obj and live(P.obj)) then M.left[slot] = nil; return P, false end   -- (no plane here: theirs comes as anyone's)
    if not fresh then rj.freshAt = nil; return P, false end                       -- (not back yet: hidden as ever)
    rj.freshAt = rj.freshAt or os.clock()
    local known = r0 ~= nil and (code ~= nil or (type(r0.row) == "string" and r0.row ~= ""))
    if not known then
        local wait = tonumber(rejoinCfg().wait_s) or 10
        if os.clock() - rj.freshAt < wait then return P, true end
        M.left[slot] = nil
        log(string.format("coop: player %d is back, no airframe heard from them in %d s: their plane here kept", slot + 1, wait))
        return P, false
    end
    M.left[slot] = nil
    local wantReal = realOn() and code ~= nil and P.realFailed == nil
    local old = P.real and (P.code or "?") or (P.row or "?")
    local differs, new
    if P.real then
        differs = not wantReal or code ~= P.code or (lo ~= "" and lo ~= (P.lo or ""))
        new = wantReal and (code == P.code and (code .. " with other weapons") or code) or standInRow(r0.row)
    else
        new = wantReal and code or standInRow(r0.row)
        differs = wantReal or new ~= P.row
    end
    if not differs then
        log(string.format("coop: player %d is back in the same %s: their plane here kept", slot + 1, old))
        return P, false
    end
    M.setAside(slot, P, "they rejoined in another aircraft")
    local nP = { at = P.at, rot = P.rot, hp = P.hp, maxHp = P.maxHp, flags = P.flags, age = P.age, hpPct = P.hpPct, down = P.down,
                 alive = P.alive, onAirfield = P.onAirfield, fresh = P.fresh, freshAt = P.freshAt, sid = r0.sid,
                 rejoin = { from = old, to = new } }
    M.peers[slot] = nP
    return nP, false
end
-- (peerTick, their new plane spawned or not) the rejoin's line, once
function M.rejoinSaid(slot, P, what)
    local rj = P and P.rejoin
    if not rj then return end
    P.rejoin = nil
    log(string.format("coop: player %d rejoined in %s (was %s): old plane set aside, %s", slot + 1, tostring(rj.to), tostring(rj.from), what))
end
end

function peerTick(slot)
    local s = type(SV_CoopPeerAt) == "function" and SV_CoopPeerAt(slot) or ""
    local f = {}
    for v in s:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
    local fresh = #f >= 10 and f[10] < 3000 and (math.floor(f[9]) % 2 == 1)        -- (flag 1: in Survival's level)
    local P = M.peers[slot] or {}
    M.peers[slot] = P
    -- what that player's game says of them, kept for COOP.players(): position (cm), rotation, health (x 10) and full
    -- health, flags (1 in Survival's level, 2 alive, 4 down at the airfield, 8 DOWN: shot down and waiting for a revive,
    -- sv_down.lua; the sync's 16-128) and its age (ms)
    if #f >= 10 and finite(f[1], 1e10) and finite(f[2], 1e10) and finite(f[3], 1e10) and finite(f[10], 1e9) then
        local fl = finite(f[9], 1e6) and math.floor(f[9]) or 0
        P.at, P.rot = { X = f[1], Y = f[2], Z = f[3] }, { f[4], f[5], f[6] }
        P.hp, P.maxHp, P.flags, P.age = f[7], f[8], fl, f[10]
        P.hpPct = (finite(f[7], 1e12) and finite(f[8], 1e9) and f[8] > 0) and math.max(0, math.min(100, f[7] / 10 / f[8] * 100)) or nil
        P.down = fl % 16 >= 8
        P.alive, P.onAirfield, P.fresh = fl % 4 >= 2 and not P.down, fl % 8 >= 4, fl % 2 == 1 and f[10] < 1000
        if f[10] >= 0 then M.stateAt[slot] = os.clock() - f[10] / 1000 end   -- ((0.73.80) their last state, when: M.noteLost)
    else
        P.at, P.fresh, P.down = nil, false, nil
    end
    if P.fresh then M.freshAt[slot] = os.clock() end                         -- ((0.73.80) last seen in the mission)
    if not D then return end
    if P.obj and not valid(P.obj) then P.obj, P.addr, P.real = nil, nil, nil end
    local unit = PEER_UNITS[slot]
    -- Their airframe comes in their "hi" (or the host's "pi") once their plane is up, and their state can come first:
    -- the stand-in spawned on the empty row of their main-menu "hi" flew the default, F-16C, for the whole run (the
    -- user's co-op run of 2026-10-29: "players are flying F-16's on my side but different aircraft on their side"; an
    -- AI plane up can't change airframe). So it waits up to AIRFRAME_WAIT_S for a row, then flies the default.
    P.freshAt = fresh and (P.freshAt or os.clock()) or nil
    local r0 = M.roster[slot]
    -- (whose plane it is: their Steam ID, so it moves with them to another slot, host migration: M.slotFix)
    if P.obj and not P.sid and r0 and r0.sid then P.sid = r0.sid end
    local known = r0 and type(r0.row) == "string" and r0.row ~= ""
    local code = r0 and r0.code ~= "" and r0.code or nil
    if P.realFailed and P.realFailed ~= code then P.realFailed = nil end        -- (another airframe: try again)
    local lo = r0 and r0.lo or ""
    -- ((0.73.77, plan C) back after leaving, in another aircraft: their old plane set aside, a new P spawned below)
    local hold = false
    if M.left[slot] then P, hold = M.rejoinTick(slot, P, r0, code, lo, fresh) end
    -- (new weapons mid-level: their real plane here keeps the loadout it was spawned with. Replacing a live real plane
    -- crashed the game: the user's co-op run of 2026-10-30, 21:37:39, an access violation reading the destroyed plane a
    -- frame on, some game system still holding it; so it's never destroyed mid-level, and the next level's has them)
    if P.real and P.obj and lo ~= "" and lo ~= (P.lo or "") and P.loSaid ~= lo and not M.left[slot] then
        P.loSaid = lo
        log(string.format("coop: player %d's loadout changed: their real plane here keeps the one it was spawned with "
            .. "(the next level's has the new one)", slot + 1))
    end
    if fresh and not P.obj and not P.spawning and levelReady() and realOn() and code and P.realFailed == nil then
        local o, why, fb, how = spawnReal(slot, P, code, lo, r0 and r0.paint or "", r0)
        if o then
            P.obj, P.addr, P.real, P.code, P.shown, P.lo, P.hpShown = o, addrOf(o), true, code, nil, lo, nil
            P.fallback = fb                                  -- ((0.73.80) another airframe shown for theirs, or nil)
            -- (their name under ALLY in its target box: the callsign line, runtime 0.32.2; the AI stand-ins' own way,
            -- SV_CoopName_<A-X>, doesn't reach a player plane)
            if type(SV_PPName) == "function" and P.addr then
                local acn = (r0 and r0.ac and r0.ac ~= "") and r0.ac or string.upper(code or "")
                local okN, rn = pcall(SV_PPName, P.addr, playerName(slot), acn)
                P.acShown = (okN and rn == 1) and acn or nil
                log(string.format("coop: player %d's name on their real plane's box: %s", slot + 1,
                    (okN and rn == 1) and (playerName(slot) .. " (" .. acn .. ")") or ("NOT set (" .. tostring(rn) .. ")")))
            end
            P.gear, P.flare, P.gunNext, P.flareNext, P.gunOn = nil, nil, nil, nil, nil
            P.wk, P.wkSaid, P.burstUntil = nil, nil, nil             -- ((0.73.80) its weapons read again: M.ppKinds)
            if fb then
                log(string.format("coop: player %d's plane is their %s shown as a real %s (a player plane, %X; no blueprint for %s "
                    .. "here: %s): flown by its own update from their stream; its own default loadout and paint "
                    .. "(theirs are another airframe's)", slot + 1, code, fb, P.addr or 0, code, tostring(how)))
            else
                -- ((0.73.80) the paint given: theirs, or with skin -1 when this game hasn't their skin (M.paintHere))
                local pg = P.paintGiven or ""
                local pa = (r0 and r0.paint) or ""
                log(string.format("coop: player %d's plane is their real %s (a player plane, %X%s): flown by its own update from their "
                    .. "stream; %s; %s", slot + 1, code, P.addr or 0, (how and how ~= "stock") and (", " .. how) or "",
                    lo ~= "" and ("their loadout " .. lo) or "its default loadout (none sent)",
                    pa == "" and "its default paint (none sent)" or (pg == pa and ("their paint " .. pa))
                    or (pg ~= "" and ("their paint " .. pa .. " given as " .. pg .. " (their skin isn't installed here)"))
                    or "its default paint ([coop] real_paint off)"))
            end
            M.rejoinSaid(slot, P, "new one spawned (their real plane)")       -- ((0.73.77) plan C's line)
        else
            P.realFailed = code
            log(string.format("coop: player %d's real plane (%s) not spawned: %s; their AI stand-in instead", slot + 1, code,
                tostring(why)))
        end
    end
    -- (no hello from them at all while their plane streams here: the user's co-op run of 2026-10-31, Shazzy's link came
    -- back after the host had dropped them, their game still had itself on the host's roster so never said hello again,
    -- and their plane here flew the default F-16C all level (an AI plane up can't change airframe, and one is never
    -- replaced mid-level). The host asks for it every 3 s, "hq", and the default waits HELLO_WAIT_S then.)
    if r0 then P.helloAsked = nil
    elseif fresh and COOP.host() and os.clock() >= (P.helloAskAt or 0) then
        P.helloAskAt = os.clock() + 3
        sendTo(slot, true, "hq")
        if not P.helloAsked then
            P.helloAsked = true
            log(string.format("coop: player %d's plane streams here but no hello from them: asked for it (hq)", slot + 1))
        end
    end
    local waitS = r0 and AIRFRAME_WAIT_S or HELLO_WAIT_S
    if fresh and not P.obj and not P.spawning and levelReady()                 -- (not while this level loads)
        and (known or os.clock() - P.freshAt >= waitS) then
        local row = standInRow(r0 and r0.row)
        local fly = M.flyRow and M.flyRow(row) or row        -- (its damage-0 copy, <row>_svcp: the sync's)
        unit = M.standInUnit(slot) or unit                   -- ((0.73.77) a free unit while theirs is set aside: plan C4)
        rawSetAircraft(unit, fly)
        spawningUnit = unit
        local r = rawSpawn(unit)
        spawningUnit = nil
        P.spawning, P.row, P.unit = os.clock(), row, unit
        local up = type(r) == "number" and r > 0
        log(string.format("coop: player %d's plane as %s%s: %s", slot + 1, fly,
            known and "" or string.format(" (no %s from them in %d s)", r0 and "airframe" or "hello", waitS),
            up and "spawned" or ("not spawned (" .. (SV_ERR[r] or tostring(r)) .. ")")))
        M.rejoinSaid(slot, P, up and ("new one spawned (an AI stand-in, " .. unit .. ")")
            or ("the new one NOT spawned (" .. (SV_ERR[r] or tostring(r)) .. ")"))
    elseif P.spawning and os.clock() - P.spawning > 10 then
        P.spawning = nil                                  -- (it never came: again)
    end
    if P.obj then
        -- (hidden while they're DOWN too, sv_down.lua: flown round their airfield out of the fight, nothing to see or hit)
        -- ((0.73.77) and while a rejoin waits for their airframe: their old plane may not be theirs any more, hold)
        local show = (fresh and not P.down and not hold) and true or false
        if show ~= P.shown then
            P.shown = show
            local radar                                  -- ((0.73.83) off the radar while hidden: M.radarOff)
            if show then radar = M.radarOn(P) end
            pcall(function() P.obj:SetActorHiddenInGame(not show) end)
            pcall(function() P.obj:SetActorEnableCollision(show) end)
            if type(SV_CoopPeer) == "function" then SV_CoopPeer(slot, show and P.addr or 0) end
            if not show then radar = M.radarOff(P) end
            log(string.format("coop: player %d's plane %s%s", slot + 1, show and "shown"
                or (hold and "hidden (back after leaving: waiting for their airframe)")
                or (fresh and "hidden (down)" or "hidden (not in the mission)"), radar and ("; " .. radar) or ""))
        end
        if P.real and valid(P.obj) and P.addr and type(SV_PPName) == "function" then
            local r1 = M.roster[slot]
            local acn = r1 and r1.ac
            if acn and acn ~= "" and acn ~= P.acShown then
                local okN, rn = pcall(SV_PPName, P.addr, playerName(slot), acn)
                if okN and rn == 1 then P.acShown = acn end
            end
        end
        -- (COOP2MP T5: their damage shown on their real plane here, its health as their game says, never under 1 HP: a
        -- real plane is never destroyed mid-level (0.73.12's crash), and hits on it here are refused anyway (hard rule 53);
        -- the field written, not SetMinHealth, which keeps whole points only)
        if P.real and show and valid(P.obj) and type(P.hp) == "number" and type(P.maxHp) == "number" and P.maxHp > 0
            and cfg().real_damage ~= false then
            local want = math.max(10, math.min(math.floor(P.maxHp * 10 + 0.5), math.floor(P.hp + 0.5)))
            if want ~= P.hpShown then
                pcall(function() P.obj.MinHealth = 1.0 end)
                local okH = pcall(function() P.obj.HealthInternal = want end)
                if okH and P.hpShown == nil then
                    log(string.format("coop: player %d's damage shown on their real plane here (health %d%%)", slot + 1,
                        math.floor(want / 10 / P.maxHp * 100 + 0.5)))
                end
                P.hpShown = okH and want or P.hpShown
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- the players, for other parts
-- COOP.players(): every player this game knows the whereabouts of, for the behaviour director (it picks a player slot
-- to aim a tactic at; docs/re/BEHAVIOUR_DIRECTOR.md): a list of { slot, obj, addr, at, hpPct, alive, onAirfield, fresh }
-- (another player's has rot too: pitch, yaw, roll from their game, and age (ms) and inLevel; yours isMe). down: shot down
-- and waiting for a revive (sv_down.lua; alive false then).
-- The local player comes first (your pawn: its position read once a tick, shared with ACE.movesTick through COOP.me();
-- health from HIT.h, its full health read every 5 s), then each other player from what peerTick already keeps of
-- SV_CoopPeerAt every tick (no native call more): obj / addr their stand-in here, fresh when their game's state is under
-- a second old. Solo, or co-op closed: only you (slot 0).
local meCache = {}
local function localPlayer()
    -- (once a tick: the run's clock D.now is set first thing in each tick, by roundsTick; no clock, no keeping)
    local now = D and D.now
    if now ~= nil and meCache.D == D and meCache.now == now then return meCache.e end
    meCache.D, meCache.now = D, now
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then meCache.e = nil; return nil end
    local e = { slot = COOP.slot or 0, obj = pawn, addr = addrOf(pawn), fresh = true, isMe = true }
    pcall(function() local v = pawn:K2_GetActorLocation(); e.at = { X = v.X, Y = v.Y, Z = v.Z } end)
    if meCache.maxAddr ~= e.addr or os.clock() >= (meCache.maxAt or 0) then
        local okM, mh = pcall(function() return pawn.MaxHealth end)
        meCache.max, meCache.maxAddr, meCache.maxAt = (okM and type(mh) == "number" and mh > 0) and mh or nil, e.addr, os.clock() + 5
    end
    local h = HIT and HIT.h
    if type(h) ~= "number" then local okH, v = pcall(function() return pawn.HealthInternal end); h = okH and type(v) == "number" and v or nil end
    e.hpPct = (h and meCache.max) and math.max(0, math.min(100, h / 10 / meCache.max * 100)) or nil
    e.down = DOWN ~= nil and DOWN.me ~= nil and DOWN.me() == true          -- (shot down, waiting for a revive: sv_down.lua)
    e.alive = (h == nil or h > 0) and not e.down
    local okA, on = pcall(playerOnAirfield, e.at)
    e.onAirfield = okA and on == true
    meCache.e = e
    return e
end
function COOP.me() return localPlayer() end
-- Sync health (the user's loggers of 2026-10-31): what this game kept of the host's flights and how often the picture
-- was rebuilt, a line a minute from sv_audit.lua (COOP.syncReport): on a joiner its copies (bound to the host's ids or
-- not), the strays taken down, its asks for the whole picture (jn) and the host's answers (rs), the copies it tore down
-- and its teardowns; on the host the joiners' asks it answered. Counted since the last report.
-- ((0.73.77, plan A6) and the floor: copies that went to it (a lethal hit sent, waiting for the host's kill), the longest
-- wait there, those put back up (taken there by something not yours); spawns of the host's refused here, flights unstuck
-- (A3) and by SV_Recycle; the host's health for copies already down here, skipped (A2))
function M.newCnt()
    return { torn = 0, teardowns = 0, strays = 0, jnSent = 0, rsGot = 0, jnGot = 0, repairs = 0,
             floored = 0, floorMax = 0, floorBack = 0, refused = 0, unstuck = 0, recycled = 0, hpDead = 0 }
end
M.cnt = M.newCnt()
function COOP.syncReport()
    local c = M.cnt
    M.cnt = M.newCnt()
    if COOP.host() then
        -- ((0.73.77, economy C1) the run's kills by the player the host named: COOP.killTally)
        local t, parts = COOP.killTally(), {}
        for s = 0, MAX_SLOT do
            local k = t[s]
            if k then parts[#parts + 1] = string.format("player %d %d%s", s + 1, k.air, k.ground > 0 and string.format(" (+%d ground)", k.ground) or "") end
        end
        return string.format("host: %d joiners linked, %d asks for the whole picture answered (rs); the run's kills by player: %s",
            M.linkedPeers or 0, c.jnGot, #parts > 0 and table.concat(parts, ", ") or "none yet")
    end
    local flights, copies, bound = 0, 0, 0
    for _, cu in pairs(M.cunits or {}) do
        flights = flights + 1
        for ord, o in pairs(cu.planes or {}) do
            if valid(o) then
                copies = copies + 1
                if cu.binds and cu.binds[ord] then bound = bound + 1 end
            end
        end
    end
    local now, atFloor, longest = os.clock(), 0, 0
    for _, cp in pairs(M.copies) do
        if cp.floorAt then atFloor = atFloor + 1; longest = math.max(longest, now - cp.floorAt) end
    end
    return string.format("joiner: %d copies of %d flights (%d bound to the host's ids, %d not), %d strays taken down, %d asks "
        .. "for the whole picture (jn), %d answers (rs; %d of them repairs, the copies kept), %d copies torn down in %d teardowns; "
        .. "the floor: %d copies there now waiting for the host's kill (the longest %.1f s), %d went there, their longest wait "
        .. "%.1f s, %d put back up (not your kill), %d your missiles' (0.73.79), %d sent again; %d flights refused here, %d "
        .. "unstuck (%d by SV_Recycle); hp for %d dead copies skipped, %d held after your hit",
        copies, flights, bound, copies - bound, c.strays, c.jnSent, c.rsGot, c.repairs or 0, c.torn, c.teardowns,
        atFloor, longest, c.floored, c.floorMax, c.floorBack, c.floorMsl or 0, c.floorResend or 0, c.refused, c.unstuck,
        c.recycled, c.hpDead, c.hpHeld or 0)
end
-- whether this game tore copies down itself within the last s seconds (and why last): the pay audit's suspect window
function COOP.tornRecently(s)
    return M.tornLast ~= nil and os.clock() - M.tornLast <= (s or 5), M.tornWhy
end
-- ((0.73.77, Workstream B1) the co-op lists kept between ticks, for the perf line's "lists:" (sv_main.lua perfLists):
-- { name, size } pairs, counted only; a list that grows over a long run shows there)
function COOP.sizes()
    if not COOP.open then return {} end
    local function n(t) local k = 0; if type(t) == "table" then for _ in pairs(t) do k = k + 1 end end; return k end
    local objs = 0
    for _, reg in pairs(M.objsOf or {}) do objs = objs + n(reg) end
    return { { "copies", n(M.copies) }, { "flights here", n(M.cunits) }, { "objects", objs }, { "ids", n(M.byId) },
             { "flights", n(M.units) }, { "dead ids", n(M.dead) }, { "torn", n(M.torn) }, { "down", n(M.downAt) },
             { "strays watched", n(M.strayFirst) }, { "players", n(M.peers) } }
end

function COOP.players()
    local out = {}
    local e = localPlayer()
    if e then out[1] = e end
    if not COOP.open then return out end
    for s = 0, MAX_SLOT do
        local P = M.peers[s]
        if s ~= COOP.slot and P and P.at then
            out[#out + 1] = { slot = s, obj = P.obj, addr = P.addr, at = P.at, hpPct = P.hpPct, alive = P.alive,
                              onAirfield = P.onAirfield, fresh = P.fresh, rot = P.rot,      -- (rot: pitch, yaw, roll)
                              down = P.down, age = P.age, inLevel = (P.flags or 0) % 2 == 1 }   -- (sv_down.lua's)
        end
    end
    return out
end
-- The player slot whose plane is at addr here (your pawn, or another player's stand-in), or nil: kills and damage by
-- player on the host (hostHit's causer is the joiner's stand-in)
function COOP.slotOfAddr(addr)
    if not addr then return nil end
    local e = localPlayer()
    if e and e.addr == addr then return e.slot end
    for s, P in pairs(M.peers) do if P.addr and P.addr == addr then return s end end
    return nil
end
-- For sv_down.lua (revives, the spectator camera): a reliable message to slot `to` (nil: everyone; a joiner's all go to
-- the host), a player's name, a slot's check, how many other games are linked, what this game keeps of another player
-- (peerTick's P), and the other players' planes here to watch (shown, their state fresh, not DOWN), in slot order
function COOP.msg(to, ...)
    -- ((0.73.77, plan A9) the host's run-over to everyone (sv_down.lua: every player down) is kept for this level: a
    -- player who links or links back later gets it with the host's picture, hostSync)
    local kind, a1 = ...
    if kind == "ro" and to == nil and COOP.host() and not M.ro then M.ro = { round = a1, at = os.clock() } end
    return sendTo(to, true, ...)
end
function COOP.name(slot) return playerName(slot) end
COOP.slotOk = slotOk
function COOP.linked() return COOP.open and (M.linkedPeers or 0) or 0 end
function COOP.peerInfo(slot) return M.peers[slot] end
-- (a joiner; THE DECOY, sv_decoy.lua) the copy at addr here is down for this game: a hit of yours that kills it was sent
-- (it waits at the floor for the host's "dn": clientTick's floorAt), or the host's kill came. A lock on you whose UAV
-- you just shot down is cancelled then, not struck at 7.9 s while the host's kill is on its way.
function COOP.killSent(addr)
    if not addr then return false end
    for id, c in pairs(M.copies) do
        if c.addr == addr then return c.floorAt ~= nil or M.dead[id] == true end
    end
    return false
end
-- (the host, COOP2MP T3) a flight onto one player's real plane: Normal, that plane, TargetFirst (theirs alone; hard rule
-- 53: Survival's orders name "Player", your plane, and the stock hunt only finds AI planes), the stock order's fire
-- bits, on each of its planes up. slot's plane if it's shown here, else the shown real plane the fewest flights are on.
-- -> true, slot, planes ordered; false if none. COOP.huntHost: the flight back on you (PlayerOnlyNoLimit, as it came).
ORDER_NORMAL, PRIO_PLAYER_ONLY_NO_LIMIT, PRIO_TARGET_FIRST, FIRE_BITS = 0, 8, 9, 7
-- (not a player down at their airfield, nor one DOWN: the user's co-op run of 2026-10-30, a flight sent onto Alessia's
-- real plane as she sat in the STORE, shooting it on the runway here 5 times while she bought a revive)
function realTarget(s)
    local P = M.peers[s]
    return (s ~= COOP.slot and P and P.real and P.shown and P.obj and valid(P.obj) and not P.onAirfield and not P.down)
        and P.obj or nil
end
COOP.realTarget = realTarget
-- (the host) the players linked but not in the mission yet (loading, the hangar, a link lost), each held for at most
-- [coop] join_wait_s from when it was first seen out: their names, or nil. The user, 2026-10-30: "is there a way that
-- we can effectively pause enemy spawns while people are joining the lobby?" (a joiner still loading when the round's
-- flights came got only 1 of 4 binds: the desync)
-- (0.73.80, the 31-round test's finding errors2) A player whose link was lost while they were in the mission (a quit, a
-- crash, a game closed: their last state in the mission within LOST_FRESH_S of their last packet) holds the round only
-- [coop] hold_lost_s after that last state: the host held its spawns 50-80 s for players who had gone (Amia 19:44:50 to
-- 19:45:40, Shazzy 20:38:31 to 20:39:51, dukka until the host left; only the native drop's sys|left, 90 s after their
-- last packet, ended it), since nothing comes from a game that quits or closes. A link lost while they weren't in the
-- mission (loading in: Amia's was lost 26-27 s twice while she loaded) keeps the hold up to join_wait_s, as before. Each
-- player's hold logged as it starts and as it ends, with how long and why.
do
local LOST_FRESH_S = 5
local function lostS() return tonumber(cfg().hold_lost_s) or 15 end
function M.noteLost(s)                                   -- (the host, on sys|lost from s)
    local now = os.clock()
    local sa, fa = M.stateAt[s], M.freshAt[s]
    local inMission = sa ~= nil and fa ~= nil and fa >= sa - LOST_FRESH_S
    M.lostAt[s] = { at = now, from = sa or now, inMission = inMission }
    log(string.format("coop: player %d's link lost %s", s + 1, inMission
        and string.format("in the mission (their last state %.0f s ago): they hold the round %s", now - (sa or now), lostS() >= 0
            and string.format("%d s after it at most ([coop] hold_lost_s)", lostS()) or "up to [coop] join_wait_s (hold_lost_s -1)")
        or string.format("while not in the mission (%s): they hold the round up to [coop] join_wait_s", fa
            and string.format("last in it %.0f s ago", now - fa) or "not seen in it here")))
end
local function holdEnd(s, why)
    local h = M.holding[s]
    if not h then return end
    M.holding[s] = nil
    log(string.format("coop: %s no longer holds the round: %s (held %.0f s; %s)", h.name, why, os.clock() - h.at, h.why))
end
function COOP.joinWaiting(now)
    if not (COOP.open and COOP.host and COOP.host()) then return nil end
    local cap = tonumber(cfg().join_wait_s) or 90
    if cap <= 0 then return nil end
    M.outSince = M.outSince or {}
    local names, ls, roster = nil, lostS(), M.roster or {}
    for s in pairs(roster) do
        if s ~= COOP.slot then
            local P = M.peers[s]
            local li = M.lostAt[s]
            if P and P.fresh then
                M.outSince[s] = nil
                holdEnd(s, "in the mission")
            else
                M.outSince[s] = M.outSince[s] or now
                if li and li.inMission and ls >= 0 and os.clock() - li.from >= ls then
                    holdEnd(s, string.format("their link was lost in the mission, nothing from them for %.0f s ([coop] hold_lost_s %d)",
                        os.clock() - li.from, ls))
                elseif now - M.outSince[s] < cap then
                    names = names or {}; names[#names + 1] = playerName(s)
                    local why = li and (li.inMission and "their link lost in the mission" or "their link lost while not in the mission")
                        or "not in the mission yet"
                    local h = M.holding[s]
                    if not h then
                        M.holding[s] = { at = os.clock(), name = playerName(s), why = why }
                        log(string.format("coop: the round waits for %s (%s), %s", playerName(s), why, (li and li.inMission and ls >= 0)
                            and string.format("up to %d s after their last state", ls) or string.format("up to %d s", cap)))
                    else
                        h.why = why
                    end
                else
                    holdEnd(s, string.format("[coop] join_wait_s %d s out of the mission", cap))
                end
            end
        end
    end
    for s in pairs(M.outSince) do if not roster[s] then M.outSince[s] = nil end end
    for s in pairs(M.holding) do if not roster[s] then holdEnd(s, "gone from the room") end end
    for s in pairs(M.lostAt) do if not roster[s] then M.lostAt[s] = nil end end
    -- (a host by migration: the old room's players not back yet, by their Steam IDs, for up to [coop.migration] wait_s)
    local mg, mc = M.mig, cfg().migration or {}
    if mg and mg.hosting and mg.expect and os.clock() - (mg.hostAt or 0) < (tonumber(mc.wait_s) or 60) then
        for sid, nm in pairs(mg.expect) do
            local back = false
            for _, r in pairs(M.roster or {}) do if r.sid == sid then back = true end end
            if not back then names = names or {}; names[#names + 1] = nm end
        end
    end
    return names
end
end
function COOP.anyReal()
    for s = 0, MAX_SLOT do if realTarget(s) then return true end end
    return false
end
local function orderFlight(unit, target, prio)
    local u, n = M.units[unit], 0
    if not (u and valid(target)) then return 0 end
    for i = 1, u.n or 0 do
        local b = u.planes[i] and M.byId[u.planes[i].id]
        if b and valid(b.obj) and pcall(function() b.obj:EngagementOrderOverride(ORDER_NORMAL, target, prio, 0, false, FIRE_BITS, false) end) then
            n = n + 1
        end
    end
    return n
end
function COOP.huntReal(unit, slot)
    local u = M.units[unit]
    if not u then return false end
    M.huntOn = M.huntOn or {}
    if slot == nil or not realTarget(slot) then
        local count, best, bestN = {}, nil, nil
        for un, h in pairs(M.huntOn) do if un ~= unit then count[h.slot] = (count[h.slot] or 0) + 1 end end
        for s = 0, MAX_SLOT do
            if realTarget(s) and (best == nil or (count[s] or 0) < bestN) then best, bestN = s, count[s] or 0 end
        end
        slot = best
    end
    local o = slot and realTarget(slot)
    local n = o and orderFlight(unit, o, PRIO_TARGET_FIRST) or 0
    if n == 0 then return false end
    M.huntOn[unit] = { slot = slot, gen = u.gen }
    M.hunted = M.hunted or {}; M.hunted[unit] = u.gen
    return true, slot, n
end
function COOP.huntHost(unit)
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if M.huntOn then M.huntOn[unit] = nil end
    if DOWN and DOWN.me and DOWN.me() == true then return 0 end   -- ((2026-11-07) never onto your plane while you're down)
    return valid(pawn) and orderFlight(unit, pawn, PRIO_PLAYER_ONLY_NO_LIMIT) or 0
end
function COOP.watchable()
    local out = {}
    for s = 0, MAX_SLOT do
        local P = M.peers[s]
        if s ~= COOP.slot and P and P.obj and P.shown and P.fresh and not P.down and valid(P.obj) and P.addr then
            out[#out + 1] = { slot = s, obj = P.obj, addr = P.addr, name = playerName(s) }
        end
    end
    return out
end
end  -- (sv_coop.lua's do block goes on in sv_coop_sync.lua)
