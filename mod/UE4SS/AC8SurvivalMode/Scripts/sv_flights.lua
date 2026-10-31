-- sv_flights.lua: flight bookkeeping: bombers, ammo, orders, the round clock.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- The world-data unit (flight) an AI plane belongs to, from its GetUnitName(); cached in p.unit, false if unreadable.
planeUnit = nil
do
local unitWarned = false
function planeUnit(p)
    if p.unit ~= nil then return p.unit end
    local ok, u = pcall(function() local v = p.obj:GetUnitName(); return type(v) == "string" and v or v:ToString() end)
    p.unit = (ok and type(u) == "string" and u ~= "") and u or false
    if not p.unit and not unitWarned then
        unitWarned = true
        log("planes: GetUnitName unreadable (" .. p.name .. ": " .. tostring(u) .. "); credits and bomb runs go by model")
    end
    return p.unit
end
end

-- The heavies' routes (CFG.airfield.bombers.heavy_route; tools/survival_events.py HEAVY_*; user, 2026-10-29: "tu-95's
-- aren't attacking the base, they fly around nearby and do nothing": over the runway they circled 6-8 km out and never
-- came within drop_km): a heavy flight's lead flies the route in from the compass sector it spawned in, over the runway,
-- then a figure-8 crossing it twice a lap (RE_SV_HeavyRoute_<NN><S>, queued route_delay_s after its appearance's
-- orders); shot down, the next of its flight takes the loop (RE_SV_HeavyLoop_<NN><L><S>). D.heavyPath[unit] = { s, k }.
HEAVY = {}
HEAVY_SECTORS = "ABCDEFGH"                           -- (compass 0, 45 ... 315 from the airfield: survival_events)
function HEAVY.route(unit, x, y)
    local b = CFG.airfield.bombers
    if not (b.heavy_route and D and BOMBER_INDEX[unit] and x and y) then return end
    local bearing = math.deg(math.atan(x - AIRFIELD.X, -(y - AIRFIELD.Y))) % 360    -- (compass: north -y, east +x)
    local i = math.floor((bearing + 22.5) / 45) % 8 + 1
    local s = HEAVY_SECTORS:sub(i, i)
    D.heavyPath = D.heavyPath or {}
    D.heavyPath[unit] = { s = s, k = 0 }
    queueEvent((D.now or 0) + (b.route_delay_s or 3), string.format("RE_SV_HeavyRoute_%02d%s", BOMBER_INDEX[unit], s),
        string.format("%s's route in from bearing %.0f", unit, bearing))
end
-- (every second, from bombTick) a flight whose lead on the path is down: its next aircraft up takes the loop
local function heavyNext()
    for unit, h in pairs(D.heavyPath or {}) do
        local lead, nk = false, nil
        for _, p in ipairs(planes) do
            if p.unit == unit and not p.down and valid(p.obj) then
                if p.k == h.k then lead = true elseif p.k and (not nk or p.k < nk) then nk = p.k end
            end
        end
        if not lead and nk and nk < 26 then
            h.k = nk
            local ev = string.format("RE_SV_HeavyLoop_%02d%s%s", BOMBER_INDEX[unit], string.char(65 + nk), h.s)
            local r = SV_Event(ev)
            log(string.format("bombers: %s's lead down: object %d takes the loop (%s %s)", unit, nk, ev,
                r == 1 and "fired" or ("not fired: " .. (SV_ERR[r] or tostring(r)))))
        elseif not lead and not nk then
            D.heavyPath[unit] = nil                                              -- (the whole flight down)
        end
    end
end

-- Heavy bombers (CFG.airfield.bombers.heavy) over the airfield: fire their flight's scripted bomb run and queue the
-- damage. If a plane's flight can't be read, every heavy flight that is up drops.
-- (once a second) the minimap's alert on a raid (CFG.airfield.bombers.ping; user, 2026-10-31: "an alert that pings the
-- aircraft via the minimap that are attacking the airfield"): each bomber flight up (not one sent at an allied ship)
-- with an aircraft within within_km of the airfield is pinged on the radar every every_s (RE_SV_RaidPing_NN: Mission
-- 22's LiveBattleNavigationExecution on its unit). The host's (or solo): forwarded, each joiner's game pings its copies.
local function raidPings(tick)
    local pg = CFG.airfield.bombers.ping
    if not (pg and pg.enabled and D.up) or (COOP and COOP.client and COOP.client()) then return end
    local near = {}
    for _, p in ipairs(planes or {}) do
        local u = not p.down and valid(p.obj) and planeUnit(p)
        if u and BOMBER_UNIT[u] and D.up[u] and not (D.shipStrike and D.shipStrike[u]) then
            local ok, l = pcall(function() return p.obj:K2_GetActorLocation() end)
            if ok and l then
                local d = math.sqrt((l.X - AIRFIELD.X) ^ 2 + (l.Y - AIRFIELD.Y) ^ 2)
                if not near[u] or d < near[u] then near[u] = d end
            end
        end
    end
    D.pingAt = D.pingAt or {}
    for u, d in pairs(near) do
        if d <= pg.within_km * 100000 and tick >= (D.pingAt[u] or 0) then
            D.pingAt[u] = tick + pg.every_s * 4
            local ev = string.format("RE_SV_RaidPing_%02d", BOMBER_INDEX[u])
            local r = SV_Event(ev)
            D.pinged = D.pinged or {}
            if not D.pinged[u] or r ~= 1 then
                D.pinged[u] = true
                log(string.format("bombers: %s pinged on the minimap, %.1f km from the airfield (%s %s; every %d s while within %d km)",
                    u, d / 100000, ev, r == 1 and "fired" or ("NOT fired: " .. tostring(r)), pg.every_s, pg.within_km))
            end
        end
    end
end

function bombTick(tick)
    local b = CFG.airfield.bombers
    if CFG.airfield.enabled and D and tick % 4 == 2 and type(SV_Event) == "function" then
        local okP, errP = pcall(raidPings, tick)
        if not okP and not D.pingErrSaid then D.pingErrSaid = true; log("bombers: minimap ping error " .. tostring(errP)) end
    end
    if not CFG.airfield.enabled or not D or not D.heavy or tick % 4 ~= 2 or type(SV_Event) ~= "function" then return end
    if D.heavyPath then pcall(heavyNext) end
    local heavy = {}
    for _, a in ipairs(b.heavy) do heavy[a:match("^(%w+)_") or a] = true end      -- "tu95_common" -> tu95
    D.bombAt = D.bombAt or {}
    for _, p in ipairs(planes) do
        local model = not p.down and p.name:match("BP_OP%d+_(%w+)_")
        if model and heavy[model] and valid(p.obj) then
            local ok, l = pcall(function() return p.obj:K2_GetActorLocation() end)
            local dx, dy = ok and l and (l.X - AIRFIELD.X), ok and l and (l.Y - AIRFIELD.Y)
            local dist = dx and math.sqrt(dx * dx + dy * dy)
            if dist and (not p.closest or dist < p.closest) then p.closest = dist end
            if dist and tick % ((CFG.log and CFG.log.verbose) and 40 or 120) == 2 then   -- (10 s verbose, else 30 s)
                log(string.format("bombers: %s %.1f km from the airfield, %.1f km up (closest %.1f km; drop within %.1f km)",
                    p.name, dist / 100000, l.Z / 100000, p.closest / 100000, b.drop_km))
            end
            if dist and dist <= b.drop_km * 100000 then
                local unit = planeUnit(p)
                if not p.overSaid then p.overSaid = true; log("bombers: " .. p.name .. " over the airfield, flight " .. tostring(unit)) end
                local runs = {}
                if unit and BOMBER_UNIT[unit] then runs[1] = unit else for u in pairs(D.heavy) do if D.up[u] then runs[#runs + 1] = u end end end
                for _, u in ipairs(runs) do
                    if not D.bombAt[u] or tick - D.bombAt[u] >= b.run_cooldown_s * 4 then
                        D.bombAt[u] = tick
                        local ev = string.format("RE_SV_BombRun_%02d", BOMBER_INDEX[u])
                        local r = SV_Event(ev)
                        if r == 1 then AF.pending[#AF.pending + 1] = { due = tick + b.damage_delay_s * 4, dmg = b.bomb_damage } end
                        log(string.format("bombers: %s bomb run (%s): %s", u, ev, r == 1 and "fired" or ("not fired, " .. tostring(r))))
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- music
-- SV_PlayBGM(event) posts a BGM event through the game's controller (it fades the playing track out and ignores a
-- track that is already playing); SV_BGM(0) reads the id it is playing (0 = nothing). See CFG.music.
M = {}

local function musicNext(special)
    local mc = CFG.music
    local key = (special and #mc.special > 0) and "special" or "tracks"
    local list = mc[key]
    M.bags[key] = M.bags[key] or {}
    local bag = M.bags[key]
    for _ = 1, #list + 1 do
        if #bag == 0 then
            for _, t in ipairs(list) do if not M.dropped[t] then bag[#bag + 1] = t end end
            if #bag == 0 then log("music: no playable tracks left in CFG.music." .. key); return true end
            shuffled(bag)
            if #bag > 1 and bag[#bag] == M.track then bag[1], bag[#bag] = bag[#bag], bag[1] end   -- no repeat
        end
        local t = table.remove(bag)
        local r = SV_PlayBGM(t)
        if r == -2 then
            M.dropped[t] = true
            log("music: " .. t .. " is not a BGM event the game has loaded; dropped")
        elseif r < 0 then
            table.insert(bag, t)                       -- not ready (or no game code): the same track next try
            log("music: " .. t .. " not posted (" .. tostring(r) .. "); trying again shortly")
            return false
        else                                           -- id 0 = queued by the game's delay table, or refused:
            M.track, M.silent, M.restarted = t, nil, nil   -- the silence check below finds out which
            log(string.format("music: round %d%s -> %s (playing id %d)", D.round, special and " (special)" or "", t, r))
            return true
        end
    end
    return true
end

function musicTick(tick, now, paused)
    local mc = CFG.music
    if D and tick % 4 == 0 and type(SV_BGM) == "function" and (not mc.enabled or M.player) then
        -- Survival leaves the music alone; log what the game's BGM controller plays (user, 2026-10-22: the music
        -- player's track skips mid-play), so a change can be matched to what happened then
        local id = SV_BGM(0)
        if id ~= M.id then M.id = id; log(string.format("music: the game's BGM controller now plays id %d (status %d)", id, SV_BGM(1))) end
        if type(SV_BGMNames) == "function" then           -- track | last stop | last event the controller was given
            local names = SV_BGMNames()
            if names ~= M.names then M.names = names; log("music: the game's BGM controller: track|stop|event = " .. names) end
        end
    end
    if not mc.enabled or not D or M.player then return end
    if type(SV_PlayBGM) ~= "function" then
        if not M.warned then M.warned = true; log("music: dlls/main.dll older than 0.9.0; the mission track plays all run") end
        return
    end
    if paused then        -- the pause menu: has the player opened the music player (its page shown, not just made)?
        if tick % 4 == 0 then
            for _, w in ipairs(FindAllOf("WBP_Menu_PauseMusicPlayer_000_C") or {}) do
                local okV, vis = pcall(function() return w:IsVisible() end)
                if okV and vis and liveWidget(w) then
                    M.player = true
                    log("music: the pause menu's music player was opened; Survival leaves the music to the player")
                    break
                end
            end
        end
        return
    end
    if D.round >= 2 and D.round ~= M.round and (not M.retryAt or now >= M.retryAt) then
        if musicNext(specialFor(D.round) ~= nil) then M.round, M.retryAt = D.round, nil else M.retryAt = now + 5 end
    end
    if tick % 4 ~= 0 then return end
    local id = SV_BGM(0)
    if id ~= M.id then M.id = id; log(string.format("music: playing id %d, status %d", id, SV_BGM(1))) end
    if id == 0 and M.track then
        M.silent = M.silent or now
        if now - M.silent >= mc.restart_s then
            M.silent = nil
            if M.restarted == M.track then         -- posted again and still silent: the game won't play it
                M.dropped[M.track], M.restarted = true, nil
                log(string.format("music: %s stays silent; dropped, next track", M.track))
                musicNext(false)
            else
                M.restarted = M.track
                log(string.format("music: nothing playing for %d s; %s again (%s)", mc.restart_s, M.track,
                    tostring(SV_PlayBGM(M.track))))
            end
        end
    else
        M.silent = nil
        if id ~= 0 then M.restarted = nil end
    end
end

---------------------------------------------------------------------------------------------------- ammo cap
-- The player's ammo counts live in native memory (no reflected property holds them; Lua 0.8.0 found no module
-- objects), so dlls\main.dll (runtime 0.7.0) reads and sets them the way the stock LiveSetWeaponAmmoCount node does
-- (tools/re/AMMO.md): SV_Ammo(kind [, max]) and SV_SetAmmo(kind, count), kind 0 gun, 1 missiles, 2 special 1,
-- 3 special 2, 4 flares; a count above the weapon's maximum is capped at it. Shortly after the player's aircraft
-- appears the preset's caps are set; the gun is kept full (unlimited); every count is logged every 10 s, which
-- also shows that missiles no longer restock on their own (SV_FreeRestock, as the stock node Mission 015 uses).
local AMMO_KINDS = { [0] = "gun", "missiles", "special 1", "special 2", "flares" }
A = nil                      -- this level's loadout state: { pawn, seenAt, applied, tries, lastLine }

local function ammoReady() return type(SV_Ammo) == "function" and type(SV_SetAmmo) == "function" end


local function ammoLine()
    local parts = {}
    for k = 0, 4 do
        local n, max = SV_Ammo(k), SV_Ammo(k, 1)
        if n >= 0 then parts[#parts + 1] = string.format("%s %d/%d", AMMO_KINDS[k], n, max) end
    end
    return table.concat(parts, ", ")
end

local function applyAmmoCaps()
    local probe = SV_Ammo(1)
    if probe < 0 and probe ~= -7 then return false, probe end                  -- not ready yet (or no game code)
    local pname, diff = presetName()
    local p = CFG.ammo.presets[pname] or CFG.ammo.presets.standard
    local want = { [1] = p.missiles, [2] = p.special, [3] = p.special, [4] = p.flares }
    local before = ammoLine()
    for k = 1, 4 do
        if want[k] and SV_Ammo(k) >= 0 then SV_SetAmmo(k, want[k]) end
    end
    A.caps, A.preset = want, pname
    RUN.dirty = true                                -- the shop's help lines show the caps
    if CFG.ammo.gun_unlimited then SV_SetAmmo(0, -1) end
    local restock = type(SV_FreeRestock) == "function" and SV_FreeRestock(CFG.ammo.free_restock and 1 or 0) or "n/a"
    log(string.format("ammo: preset %s (difficulty %s): %s -> %s; free restock was %s, now %s", pname, tostring(diff),
        before, ammoLine(), tostring(restock), CFG.ammo.free_restock and "on" or "off"))
    return true
end

function ammoTick(tick, pc)
    if not CFG.ammo.enabled then return end
    if not ammoReady() then
        if not (A and A.warned) then A = { warned = true }; log("ammo: dlls/main.dll 0.7.0 did not register SV_Ammo; no ammo cap") end
        return
    end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not valid(pawn) then return end
    local pname = nameOf(pawn)
    if not A or A.pawn ~= pname then A = { pawn = pname, seenAt = tick, applied = false, tries = 0 } end
    if not A.applied and tick - A.seenAt >= 8 and (tick - A.seenAt) % 8 == 0 and A.tries < 10 then   -- 2 s in, retried
        A.tries = A.tries + 1
        local ok, r, code = pcall(applyAmmoCaps)
        if not ok then log("ammo: error " .. tostring(r))
        elseif not r and A.tries == 10 then log("ammo: the player's weapons could not be read (" .. tostring(code) .. "); no ammo cap") end
        A.applied = ok and r
    end
    if not A.applied then return end
    -- the STORE's upgrades on this aircraft (sv_tactical.lua UP.apply): every 2 s, and at once while a purchase made down
    -- at the airfield waits to be loaded (WEAPON BAYS must raise the full load before more than the stock one goes in)
    if tick % 8 == 6 or (A.owed and next(A.owed)) then
        local okU, errU = pcall(UP.apply, pawn)
        if not okU and not A.upErr then A.upErr = true; log("upgrades: error " .. tostring(errU)) end
    end
    if tick % 2 == 0 then                                                      -- every 0.5 s: counts for the kill probe
        local s = {}
        for k = 0, 4 do s[k] = SV_Ammo(k) end
        PR.ammo[#PR.ammo + 1] = s
        if #PR.ammo > 12 then table.remove(PR.ammo, 1) end
        -- A.caps[k] is what the player may hold: the preset's load at spawn, less what was fired, plus what was
        -- bought. The airfield's rearm (and anything else the game refills) loads the aircraft's full stock count, so a
        -- count above it is put back: landing rearms nothing. Firing lowers it, read only away from the airfield (a
        -- rearm in progress must never pass for shots).
        -- With WEAPON BAYS the game's reload also puts the stock full load back (the bays' is A.bays[k]): until UP.apply
        -- has raised it again (at once, here) a count under what you had is that reload, not shots; then what you had
        -- goes back in (a run of 2026-10-24: 36/36 specials bought, 24/36 after take-off, the rest gone).
        local over, ground, back = {}, playerOnAirfield(), {}
        -- the gun's shots for the measurements (STATS.fired, kind 0): what it lost since the last count it had (the 2 s
        -- refill below sets that to full, so a refill is never taken for shots)
        if s[0] >= 0 then
            if A.gunLast and s[0] < A.gunLast and not ground then pcall(STATS.fired, 0, A.gunLast - s[0]) end
            A.gunLast = s[0]
        end
        for k = 1, 3 do
            local m, want = SV_Ammo(k, 1), A.bays and A.bays[k]
            if want and m >= 0 and m < want and not (A.reload and A.reload[k] and tick - A.reload[k] > 40) then
                if not (A.reload and A.reload[k]) then          -- (10 s at most: a full load that won't go up is the aircraft's)
                    A.reload = A.reload or {}
                    A.reload[k] = tick
                    local okU, errU = pcall(UP.apply, pawn)
                    if not okU and not A.upErr then A.upErr = true; log("upgrades: error " .. tostring(errU)) end
                end
            elseif A.reload and A.reload[k] and m >= 0 then
                A.reload[k] = nil
                local cap = A.caps and A.caps[k]
                local to = cap and math.min(cap, m)             -- (another special picked down there: its own load)
                if to and s[k] >= 0 and s[k] < to then
                    SV_SetAmmo(k, to)
                    back[#back + 1] = string.format("%s %d -> %d", AMMO_KINDS[k], s[k], to)
                    s[k] = to
                end
            end
        end
        for k = 1, 4 do
            local cap = A.caps and A.caps[k]
            if cap and s[k] >= 0 and A.owed and A.owed[k] then  -- bought while the count couldn't be read: load it now
                A.owed[k] = nil
                if s[k] < cap then SV_SetAmmo(k, cap); s[k] = cap end
            end
            -- On the ground nothing is fired, so a count under what you had there is the game's reload too, whether or
            -- not the dip in the full load was seen above (UP.apply's own 2 s pass raises it back first a quarter of the
            -- time: a run of 2026-10-25, REARMED to 18/18 and 27/27, 12/18 and 18/27 after take-off, twice). Once the
            -- bays' full load is back, what you had goes in.
            local m = (ground and k <= 3 and A.bays and A.bays[k] and cap and s[k] >= 0 and s[k] < cap) and SV_Ammo(k, 1) or -1
            if A.reload and A.reload[k] then                 -- (the bays' full load not back yet: nothing to read)
            elseif m >= 0 and s[k] < math.min(cap, m) then
                local to = math.min(cap, m)                  -- (another special picked down there: its own load)
                SV_SetAmmo(k, to)
                back[#back + 1] = string.format("%s %d -> %d", AMMO_KINDS[k], s[k], to)
                s[k] = to
            elseif cap and s[k] > cap then
                SV_SetAmmo(k, cap)
                over[#over + 1] = string.format("%s %d -> %d", AMMO_KINDS[k], s[k], cap)
            elseif cap and s[k] >= 0 and s[k] < cap and not ground then
                pcall(STATS.fired, k, cap - s[k])           -- (shots: the measurements, sv_stats.lua)
                A.caps[k] = s[k]
                RUN.dirty = true                    -- the shop's help lines show the counts
            end
        end
        if #back > 0 then log("ammo: reloaded by the game to its stock load, put back what you had (weapon bays): " .. table.concat(back, ", ")) end
        if #over > 0 then
            if type(SV_FreeRestock) == "function" and not CFG.ammo.free_restock then SV_FreeRestock(0) end
            log("ammo: refilled by the game, put back to what you had (" .. A.preset .. "): " .. table.concat(over, ", "))
        end
    end
    if tick % 8 == 4 then                                                      -- every 2 s: maxima, for the shop
        A.max = A.max or {}
        for k = 0, 4 do
            local m = SV_Ammo(k, 1)
            if m >= 0 then A.max[k] = math.max(m, A.bays and A.bays[k] or 0) end   -- (WEAPON BAYS': UP.apply raises it back)
        end
    end
    if CFG.ammo.gun_unlimited and tick % 8 == 0 then                           -- every 2 s: gun back to full
        local n, max = SV_Ammo(0), SV_Ammo(0, 1)
        if n >= 0 and n < max then SV_SetAmmo(0, -1); A.gunLast = max end
    end
    -- every 10 s with [log] verbose, else every 60 s: the counts, when they change
    if tick % (logVerbose() and 40 or 240) == 0 then
        local line = ammoLine()
        if line ~= A.lastLine then log("ammo: now " .. line); A.lastLine = line end
    end
end

function playerControllerHere()
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if valid(pc) and inSurvival(pc) then return pc end
    end
    return nil
end

-- This pass's round time and whether the game is paused. The game clock (GetTimeSeconds) stops while paused, so the
-- rounds and the countdown do too; if it can't be read within 5 s of loading, real time is used (and logged).
function roundClock(tick)
    local t = gameClock(survivalPC)
    if D.clock == nil then
        if t then D.clock = "game"; log("rounds: on the game clock (stops while paused)")
        elseif tick - levelTick >= 20 then
            D.clock = "ticks"; log("rounds: the game clock can't be read; using real time (rounds keep running while paused)")
        else return nil end
        D.at = (D.clock == "game" and t or tick / 4) + CFG.first_round_delay_s
    end
    if D.clock == "ticks" then return tick / 4, false end
    if not t then return D.now, true end                    -- not readable this pass: hold still
    return t, (D.now ~= nil and t == D.now) or gamePaused(survivalPC)
end

---------------------------------------------------------------------------------------------------- airfield shop
-- Survival's rows (DT_SV_ShopRows) go into the landing menu's command table (the in-game hangar's list) while
-- Survival's level is loaded, and come out again when it isn't, so stock missions never show them. Their texts are
-- set through dlls/main.dll's text hook (SV_SetText) and kept up to date with credits and prices; picking one is
-- caught by its landing-menu hook and handed over here by SV_ShopRequest (runtime 0.10.0).
SHOP = {
    mine = "/Game/Mods/SurvivalMode/Data/DT_SV_ShopRows.DT_SV_ShopRows",
    game = "/Game/Datatables/UI/Menu/IngameMenu/IngameHangar/DT_LiveMenuIngameHangarCommands.DT_LiveMenuIngameHangarCommands",
    -- the landing page's rows: the STORE's (one per page it opens on: tools/build_survival.py STORE_ROWS) when its pages
    -- are in the game's menu list, else the four old ones
    store = { "SVShopStore", "SVShopStoreUp", "SVShopStoreTac", "SVShopStoreAf" },
    rows = { "SVShopMissiles", "SVShopSpecial", "SVShopFlares", "SVShopAirfield" },
    all = { "SVShopStore", "SVShopStoreUp", "SVShopStoreTac", "SVShopStoreAf", "SVShopMissiles", "SVShopSpecial",
            "SVShopFlares", "SVShopAirfield" },
    -- the store's pages (tools/build_survival.py STORE_PAGES): in-game menus 20-25 (SUPPLIES, AIRFIELD, ALLIES, UPGRADES,
    -- TACTICAL, DEFENCES: rows "20" .. "25" open them), added to the in-game menu table at the main menu, before a level
    -- builds its menu list from it
    menuMine = "/Game/Mods/SurvivalMode/Data/DT_SV_MenuClassRows.DT_SV_MenuClassRows",
    menuGame = "/Game/Datatables/UI/Menu/IngameMenu/DT_IngameMenuSettingData.DT_IngameMenuSettingData",
    menuRows = { { row = "SVStore", id = "SV_Store", index = 20 }, { row = "SVStoreAirfield", id = "SV_StoreAirfield", index = 21 },
                 { row = "SVStoreDocks", id = "SV_StoreDocks", index = 22 },
                 { row = "SVStoreUpgrades", id = "SV_StoreUpgrades", index = 23 },
                 { row = "SVStoreTactical", id = "SV_StoreTactical", index = 24 },
                 { row = "SVStoreDefences", id = "SV_StoreDefences", index = 25 } },
    -- each row's icon (stock textures; the aircraft repair shows the player's own plane when the game has its icon)
    icons = {
        Missiles = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_msl_a0",
        Special  = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_qaam_a0",
        Flares   = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_flr",
        RepairAircraft = "/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP004_f15c",
        RepairAirfield = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Base_000",
        Airfield = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Base_000",
        AAGun    = "/Game/UI/Texture/Icon/Tutorial/T_UI_TutorialIcon_TGT_Gnd_000",
        SAM      = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_saam_a0",
        Ciws     = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_mgp_a0",                    -- (a gun pod's)
        Moonchild   = "/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP005_f22a",
        ShipAegis   = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_GndEscort_000",   -- (no ship icon in the game: an ally's)
        -- (the review build's rows: stock textures already used above)
        Rearm      = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_msl_a0",
        UpAirframe = "/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP004_f15c",
        UpBays     = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_qaam_a0",
        UpGun      = "/Game/UI/Texture/Icon/Tutorial/T_UI_TutorialIcon_TGT_Gnd_000",
        UpFlares   = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_flr",
        Airstrike  = "/Game/UI/Texture/Icon/Tutorial/T_UI_TutorialIcon_TGT_Gnd_000",
        Ecm        = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Sonar_000",
        VoidWatcher = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Sonar_000",        -- (the ECM's: no AWACS icon in the game)
        Decoy      = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_flr",
        Insurance  = "/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP005_f22a",
        Wingmen    = "/Game/UI/Texture/Icon/Aircraft/T_HUD_acIcon_PP005_f22a",
        Orders     = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Base_000",
        ["20"]   = "/Game/NUI/Common/Texture/IconMenu/T_Menu_Common_IconMenu_Shop_000",          -- STORE, SUPPLIES >
        ["21"]   = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Base_000",                         -- AIRFIELD >
        ["22"]   = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_GndEscort_000",                    -- ALLIES >
        ["23"]   = "/Game/UI/Texture/HUD/ProgressBar/Weapons/T_HUD_w_qaam_a0",                 -- UPGRADES >
        ["24"]   = "/Game/UI/Texture/Icon/Tutorial/T_UI_TutorialIcon_TGT_Gnd_000",            -- TACTICAL >
        ["25"]   = "/Game/UI/Texture/HUD/Radar/T_Icon_Radar_Gnd_000",                          -- DEFENCES >
    },
}
SH = { added = false, addr = nil, warned = {}, decor = {} }

local function shopWarn(key, msg)
    if SH.warned[key] then return end
    SH.warned[key] = true
    log("shop: " .. msg)
end

function shopRowsTick(tick)
    if not CFG.shop.enabled or tick % 16 ~= 1 or containerState ~= true then return end
    local pc = valid(survivalPC) and survivalPC or (SH.addr and FindFirstOf("PlayerController"))
    if pc and valid(pc) and inSurvival(pc) then
        -- without the native landing-menu hook a shop row would reach the stock decide, which reads it as a page number
        if type(SV_ShopRequest) ~= "function" or type(SV_SetText) ~= "function" or SV_ShopRequest(1) ~= 1 then
            shopWarn("hook", "dlls/main.dll's landing menu hook is not installed (runtime 0.10.0+); no shop rows")
            return
        end
        local game = loadObject(SHOP.game)
        if not valid(game) then shopWarn("load", "could not load the landing menu's table"); return end
        local a = addrOf(game)
        if SH.addr ~= a then SH.addr, SH.added = a, false; pin(game, nameOf(game)) end
        if SH.added then return end
        local store = SHOP.storeCheck()
        if store == nil then return end                  -- (the game's menu list isn't readable yet)
        local rows = store and SHOP.store or SHOP.rows
        local mine = loadObject(SHOP.mine)
        if not valid(mine) then shopWarn("mine", "could not load DT_SV_ShopRows"); return end
        pin(mine, nameOf(mine))
        local n = 0
        for _, r in ipairs(SHOP.all) do                  -- the other set out (a level before had the other)
            local keep = false
            for _, k in ipairs(rows) do if k == r then keep = true end end
            if not keep then dtCall(game, "RemoveRow", r) end
        end
        for _, r in ipairs(rows) do
            local _, have = dtCall(game, "FindRow", r)
            if have == nil then
                local _, src = dtCall(mine, "FindRow", r)
                if src ~= nil then dtCall(game, "AddRow", r, src) end
            end
            local _, now = dtCall(game, "FindRow", r)
            if now ~= nil then n = n + 1 end
        end
        SH.added = n == #rows
        log(string.format("shop: %s: %d of %d rows in the landing menu (%s)", store and "the STORE" or "the shop rows",
            n, #rows, rowNames(game)))
    elseif SH.addr then
        local game = StaticFindObject(SHOP.game)
        if valid(game) then
            for _, r in ipairs(SHOP.all) do dtCall(game, "RemoveRow", r) end
            log("shop: rows taken out of the landing menu (not in Survival's level)")
        end
        SH.added, SH.addr = false, nil
    end
end

-- The store's pages into the in-game menu table, from the main menu on (the menu list is built when a level starts).
-- SH.menuOk: both rows sit at the indexes the landing rows name (another mod's rows in that table would move them).
function SHOP.menuSetup()
    if SH.menuDone or not CFG.shop.enabled or not gameInstance() then return end
    SH.menuTries = (SH.menuTries or 0) + 1
    local game, mine = loadObject(SHOP.menuGame), loadObject(SHOP.menuMine)
    if not (valid(game) and valid(mine)) then
        if SH.menuTries >= 20 then SH.menuDone = true; log("shop: the store's menu tables didn't load; the shop rows stand in") end
        return
    end
    pin(game, nameOf(game)); pin(mine, nameOf(mine))
    for _, m in ipairs(SHOP.menuRows) do            -- (each step logged: test of 2026-10-23 got nil / nil, no error)
        local okH, have = dtCall(game, "FindRow", m.row)
        local steps = { "in the game's table: " .. (okH and (have ~= nil and "yes" or "no") or ("error " .. tostring(have))) }
        if have == nil then
            local okR, r = dtCall(mine, "FindRow", m.row)
            steps[#steps + 1] = "in DT_SV_MenuClassRows: " .. (okR and (r ~= nil and type(r) or "no") or ("error " .. tostring(r)))
            if okR and r ~= nil then
                -- (never read r.MenuWidgetReference from Lua: UE4SS's copy of a soft class reference crashed the game
                -- at the main menu, test of 2026-10-23, in FSoftObjectPath::operator= -> FString::operator=)
                local okA, e = dtCall(game, "AddRow", m.row, r)
                steps[#steps + 1] = "AddRow " .. (okA and "ran" or ("error " .. tostring(e)))
                local okF, now = dtCall(game, "FindRow", m.row)
                steps[#steps + 1] = "now " .. (okF and (now ~= nil and "in" or "not in") or ("error " .. tostring(now)))
            end
        end
        log("shop: store page " .. m.row .. ": " .. table.concat(steps, "; "))
    end
    log("shop: in-game menu table rows: " .. rowNames(game) .. " | DT_SV_MenuClassRows: " .. rowNames(mine))
    local at = {}
    for i, n in ipairs(rowList(game) or {}) do at[n] = i - 1 end
    SH.menuOk = true
    for _, m in ipairs(SHOP.menuRows) do if at[m.row] ~= m.index then SH.menuOk = false end end
    SH.menuDone = true
    local where = {}
    for _, m in ipairs(SHOP.menuRows) do where[#where + 1] = string.format("%s at %s (want %d)", m.row, tostring(at[m.row]), m.index) end
    log("shop: the store's pages in the in-game menu table: " .. table.concat(where, ", ")
        .. (SH.menuOk and "" or ": the shop rows stand in"))
end
