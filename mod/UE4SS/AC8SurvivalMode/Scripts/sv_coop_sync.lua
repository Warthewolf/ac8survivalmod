-- sv_coop_sync.lua: Survival COOP, what's synced: weapons, gear and afterburners, the messages, the allies and
-- defences. Piece 4 of 5 of sv_coop.lua (sv_coop.lua, sv_coop_joiner.lua, sv_coop_planes.lua, sv_coop_sync.lua,
-- sv_coop_migration.lua), split by tools/lua_split_part.py and run by main.lua right after the piece before it: a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local.
do  -- (sv_coop.lua's do block, continued: this piece's own helpers stay local to it)
local M = COOP.M                                   -- (sv_coop.lua's M, handed on)

---------------------------------------------------------------------------------------------------- weapons, gear, afterburner
-- The other players' planes do what theirs do (user, 2026-10-29, three players on 0.72.0: "can you please work out
-- aircraft syncing, such as missiles being fired", "when allies land at the airfield, their gear doesn't deploy on my
-- screen, nor do I see their afterburners"; docs/re/COOP.md 8). Each game watches its own plane and tells the others,
-- whose stand-in of it (SV_Unit_CoopPeer<A-X>) does the same there:
--   missiles     the pawn's FiredExplosiveWeapons (its missiles in flight; pooled objects, so an address that wasn't in
--                it last tick is a shot, its class the kind, its TargetToHome the target): "fx" to the host, which
--                fires them from the shooter's stand-in and relays them to the others; SV_CoopFire (runtime 0.28.5)
--                fires the stand-in's fire-control slot 2 at that target here (its copy on a joiner), or at none
--   gun          SV_Ammo(0) dropping (read before Survival's own refill: COOP.ammoRead) -> state bit 64 while it does;
--                the others fire the stand-in's gun (slot 1) every GUN_EVERY_S at its target ("fx" g: your target)
--   flares       SV_Ammo(4) dropping -> bit 128; the others fire the stand-in's flares (slot 0) as it comes on
--   electronic   a special weapon's count (SV_Ammo(2) / (3)) dropping with nothing new in flight within ELEC_WAIT_S: an
--                ESM / jamming pod, which fires no projectile (the user's co-op run of 2026-10-30: the EA-18G's ESM
--                "didn't show up for any of us"): "fx" e; the others fire the stand-in's ECM pod (its row's ECM slot)
--   gear         LandingGearOnMesh shown -> bit 16; the others call the stand-in's EnableLandingGear as it flips
--   afterburner  SV_InputNow's throttle at ab_throttle or over -> bit 32; the runtime lights the stand-in's itself
-- Never twice: a stand-in flies its airframe's damage-0 copy (<row>_svcp, COOP.syncSetup), so what it fires here only
-- shows; a joiner takes any stand-in's damage out of what it sends the host anyway (clientTick: the backstop).
-- "fx" (reliable, a tick's shots in one): shooter -> host "fx|<k>:<id>:<age>;..." (k: m a missile, s a special weapon,
-- e an electronic special (ESM / jamming), g the gun's target; id: the target's stream id, 0 none; age: ms since it was
-- seen); host -> the others. COOP2MP T4b (runtime 0.32.0): each launch also as "p:<id>:<age>:<shot>" (the runtime's
-- SV_CoopShots: kind, weapon number, spawn slot, seed, lock-ons, where it left your plane, rotation, velocity), replayed
-- from your real plane in the other games (SV_CoopPPShot); a stand-in there fires m / s / e as before, a real plane p.
-- "fx|<shooter's slot>|..." (never back to the shooter; the host's own as slot 0). Guards: a known slot, not your own;
-- at most FX_PER_S shots a second a shooter and FX_MAX entries a message; a shot older than FX_STALE_MS (its age and
-- half the round trip of each leg) or from a shooter whose state is over a second old dropped; an id not known here
-- fired with no target.
do
local FX_PER_S, FX_MAX, FX_STALE_MS, FLAG_HOLD_S, GUN_EVERY_S, FLARE_EVERY_S = 12, 32, 1500, 0.5, 0.2, 1.0
local P_PER_S = 16                                         -- (a shooter's "p" launches a second, T4b)
-- (a special weapon's count down with nothing new in flight this long after: an electronic one, ESM / jamming)
local ELEC_WAIT_S = 0.45
-- the ECM pod's fire-control slot on a stand-in's airframe row (COOP.syncSetup records each row's: an FCS id with ECM in
-- it, or the pod it adds to the electronic-warfare airframes' copies, whose plain campaign rows carry none)
M.ecmSlot = M.ecmSlot or {}
local BIT_GEAR, BIT_AB, BIT_GUN, BIT_FLARE = 16, 32, 64, 128
local MISSION_TABLE = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission.DT_SV_NpcMission"
local S = { seen = {}, kinds = {}, rate = {}, n = { sent = 0, got = 0, fired = 0, failed = 0, dropped = 0, gear = 0, ab = 0 } }
M.fxS = S
local function sc() local s = cfg().sync; return type(s) == "table" and s or {} end
local function bit(flags, b) return type(flags) == "number" and math.floor(flags / b) % 2 == 1 end
local function on(k) local s = sc(); return s.enabled == true and s[k] ~= false end

-- the stream id of the enemy at address a (the host: its own, M.byId; a joiner: its copy of the host's, M.copies), or 0
local function idOfAddr(a)
    if not a then return 0 end
    if COOP.host() then
        for id, e in pairs(M.byId) do if e.addr == a and not e.dead then return id end end
    else
        for id, c in pairs(M.copies) do if c.addr == a then return id end end
    end
    return 0
end
-- the actor here of stream id `id` (the host: its enemy; a joiner: its copy), or nil
local function addrOfId(id)
    if type(id) ~= "number" or id <= 0 then return nil end
    if COOP.host() then
        local e = M.byId[id]
        return e and not e.dead and valid(e.obj) and e.addr or nil
    end
    local c = M.copies[id]
    return c and not M.dead[id] and valid(c.obj) and c.addr or nil
end
-- the stand-ins' damage-0 mission row for airframe row `row`, when it was made before this level loaded
function M.flyRow(row)
    return sc().enabled == true and M.svcpUsable and M.svcpUsable[row] or row
end
-- every other player's stand-in here, by address (the backstop's keys)
function M.standInSet()
    local set = {}
    for s, P in pairs(M.peers) do if s ~= COOP.slot and P.addr then set[P.addr] = s end end
    for _, c in pairs(M.copies) do if c.ally and c.addr then set[c.addr] = -1 end end   -- (the host's allies' copies here:
                                                                                     -- their hits are the host's)
    -- ((code review of 2026-11-07, finding 1) this game's own ZFA-44s: the host's carrier launches are forwarded, so
    -- each copy of the ship here launches planes of its own (no co-op id, never bound). Their fight is the host's real
    -- ZFA-44s' there: what they do to an enemy copy here is nobody's, never this player's hit (sv_escort.lua)
    if ESC and ESC.localZfa then
        local okZ, z = pcall(ESC.localZfa)
        if okZ and type(z) == "table" then for a in pairs(z) do if set[a] == nil then set[a] = -1 end end end
    end
    return set
end
-- ((code review of 2026-11-07) whether address a is one of the host's objects' copies here, bound to its id
-- (sv_escort.lua: a carrier's ZFA-44s of this game's own are switched off, the host's pose flight's copies aren't)
function COOP.copyAt(a)
    if not a then return false end
    for _, c in pairs(M.copies) do if c.addr == a then return true end end
    return false
end
-- what the stand-ins in `set` have done to o so far (its DamageHistoryMap, in health: KILLS_HEALTH_DEATH.md 1)
function M.standInDamage(o, set)
    local sum = 0
    pcall(function()
        o.DamageHistoryMap:ForEach(function(k, v)
            local okK, a = pcall(function() return k:get():GetAddress() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and set[a] and type(x) == "number" and x > 0 then sum = sum + x end
        end)
    end)
    return sum
end
-- (0.73.77, plan A1) one look at copy o's DamageHistoryMap (in health; every hit is added there in full, before the floor
-- clamps its health): what the stand-ins and allies' copies in `set` (may be nil) have done to it, and what your plane
-- (address pa) has, nil when the map couldn't be read. The first time your plane shows up in a copy's map, M.ownSeen:
-- from then on the floor's hits trust it (clientTick)
function M.historyOf(o, set, pa)
    local sum, mine = 0, 0
    local ok = pcall(function()
        o.DamageHistoryMap:ForEach(function(k, v)
            local okK, a = pcall(function() return k:get():GetAddress() end)
            local okV, x = pcall(function() return v:get() end)
            if okK and okV and type(x) == "number" and x > 0 then
                if set and set[a] then sum = sum + x
                elseif pa and a == pa then mine = mine + x end
            end
        end)
    end)
    if ok and mine > 0 and not M.ownSeen then
        M.ownSeen = true
        log("coop: your hits read from the copies' damage maps: a hit the floor clips is sent whole")
    end
    return sum, ok and mine or nil
end

-- your weapon's kind by its class: "m" the standard missile (BP_plwp_msl_*), "s" a special weapon (the stand-ins fire
-- their missile slot 2 for both, for now), false the gun's and the flares' (the state bits carry those)
local function kindOf(w)
    local cls = nameOf(w):match("^(%S+)") or "?"
    local k = S.kinds[cls]
    if k == nil then
        local l = cls:lower()
        if l:find("^bp_plwp_msl") then k = "m"
        elseif l:find("gun", 1, true) or l:find("flr", 1, true) or l:find("flare", 1, true) then k = false
        else k = "s" end
        S.kinds[cls] = k
        log(string.format("coopfire: your weapon %s: %s", cls, k == "m" and "a missile (the stand-ins' slot 2)"
            or k == "s" and "a special weapon (the stand-ins' missile slot 2 for now)" or "not sent (the state bits)"))
    end
    return k
end
-- your missiles in flight against last tick's: the new ones' entries into out ("k:id:0"); the first read after your
-- plane changes only learns what's up already
local function watchShots(pawn, out)
    local okA, arr = pcall(function() return pawn.FiredExplosiveWeapons end)
    if not (okA and arr) then once("fxarr", "coopfire: your plane's FiredExplosiveWeapons can't be read: your missiles aren't sent"); return end
    local list, cur = {}, {}
    local okL = pcall(function() arr:ForEach(function(_, e) list[#list + 1] = e:get() end) end)
    if not okL then once("fxeach", "coopfire: your plane's FiredExplosiveWeapons can't be walked: your missiles aren't sent"); return end
    for _, w in ipairs(list) do
        local a = liveAddr(w)                              -- (hotfix2: not valid(): see sv_core liveAddr)
        if a then
            cur[a] = true
            if S.primed and not S.seen[a] then
                local k = kindOf(w)
                if k then
                    local okT, t = pcall(function() return w.TargetToHome end)
                    local ta = okT and t and liveAddr(t)
                    out[#out + 1] = string.format("%s:%d:0", k, ta and idOfAddr(ta) or 0)
                    if ta then M.shotMark(a, ta) end       -- ((0.73.79) a copy's hit at the floor: M.floorLoss)
                    if k == "s" then S.spShotAt = os.clock() end     -- (a special weapon in flight: not electronic)
                end
            end
        end
    end
    for a in pairs(S.seen) do if not cur[a] then M.shotEnd(a) end end   -- ((0.73.79) gone: it hit, or missed)
    S.seen, S.primed = cur, true
end

-- (sv_main.lua, just before ammoTick: before Survival's own refill) your gun's and flares' counts against what they
-- were after last tick's: a drop away from the airfield is fire
function COOP.ammoRead()
    if not (COOP.open and D and sc().enabled == true and type(SV_Ammo) == "function") then return end
    local now = os.clock()
    if playerOnAirfield() then return end                  -- (a rearm down there)
    local g, f = SV_Ammo(0), SV_Ammo(4)
    if on("guns") and type(g) == "number" and g >= 0 and S.gunLast and g < S.gunLast then
        if not S.gunAt or now - S.gunAt > FLAG_HOLD_S then S.n.bursts = (S.n.bursts or 0) + 1 end
        S.gunAt = now
    end
    if on("flares") and type(f) == "number" and f >= 0 and S.flrLast and f < S.flrLast then
        S.n.flares = (S.n.flares or 0) + 1
        S.flrAt = now
    end
    for k = 2, 3 do                                        -- (the special weapons: an ESM's use shows only here)
        local v = SV_Ammo(k)
        local was = S.spLast and S.spLast[k]
        if on("missiles") and type(v) == "number" and v >= 0 and was and v < was and not S.spDropAt then S.spDropAt = now end
    end
end
-- (COOP.tick, after ammoTick) the counts the next read goes by
local function ammoAfter()
    if type(SV_Ammo) ~= "function" then return end
    local g, f = SV_Ammo(0), SV_Ammo(4)
    S.gunLast = (type(g) == "number" and g >= 0) and g or nil
    S.flrLast = (type(f) == "number" and f >= 0) and f or nil
    S.spLast = {}
    for k = 2, 3 do local v = SV_Ammo(k); S.spLast[k] = (type(v) == "number" and v >= 0) and v or nil end
end

-- this game's state bits for its own plane (SV_CoopMe): 16 gear down, 32 afterburner, 64 gun firing, 128 flares
function M.syncBits(pawn, now)
    if sc().enabled ~= true or not valid(pawn) then return 0 end
    local b = 0
    if on("gear") then
        local down = nil
        pcall(function()
            local comp = pawn.LandingGearOnMesh
            if valid(comp) then local v = comp:IsVisible(); if type(v) == "boolean" then down = v end end
        end)
        if down == nil then once("gearread", "coopfire: your gear can't be read (LandingGearOnMesh): not sent")
        elseif down ~= S.gear then
            S.gear, S.n.gear = down, S.n.gear + 1
            if S.n.gear <= 6 then log("coopfire: your gear " .. (down and "down" or "up") .. " (LandingGearOnMesh " .. (down and "shown" or "hidden") .. ")") end
        end
        if down then b = b + BIT_GEAR end
    end
    if on("afterburner") and type(SV_InputNow) == "function" then
        local okI, s = pcall(SV_InputNow)
        local th = okI and type(s) == "string" and tonumber(s:match("^[^,]*,[^,]*,[^,]*,([^,]*)")) or nil
        if th then
            S.n.thMax = math.max(S.n.thMax or 0, th)              -- (the tally's: what full throttle reads, to calibrate)
            local ab = th / 1000 >= (tonumber(sc().ab_throttle) or 0.9)
            if ab ~= S.ab then
                S.ab, S.n.ab = ab, S.n.ab + 1
                if (S.n.ab <= 4 and logVerbose()) or not S.abSaid then   -- (the first one; up to 4 a minute with [log] verbose)
                    S.abSaid = true
                    log(string.format("coopfire: your throttle %.3f: afterburner %s (ab_throttle %s)", th / 1000,
                        ab and "on" or "off", tostring(sc().ab_throttle)))
                end
            end
            if ab then b = b + BIT_AB end
        else
            once("abread", "coopfire: SV_InputNow gave no throttle (" .. tostring(s) .. "): your afterburner isn't sent")
        end
    end
    if on("guns") and S.gunAt and now - S.gunAt <= FLAG_HOLD_S then b = b + BIT_GUN end
    if on("flares") and S.flrAt and now - S.flrAt <= FLAG_HOLD_S then b = b + BIT_FLARE end
    return b
end

-- a stand-in's fire: player slot's plane here fires fire-control slot fcs at the actor at target (nil: none)
local function standInAddr(slot)
    local P = M.peers[slot]
    return P and P.obj and P.shown and valid(P.obj) and P.addr or nil
end
local FCS_NAME = { [0] = "flares", "gun", "missiles", "ECM pod" }
-- ((review of 0.73.80) your landing STORE open: the music hold's 1 while a landing menu window was on screen at the last
-- look (sv_core.lua LANDW); the hold itself lets go ~2.5 s after it closes (two looks: a late page), the launches here
-- at once (as 0.73.79's hold did)
local function inStore()
    return D and D.musicHold == 1 and not (LANDW and LANDW.wasShown == false)
end
local function coopFire(slot, fcs, target)
    -- (your landing STORE open: the game holds the other planes inactive there and refuses their fire; the co-op run of
    -- 2026-10-30: 1,093 of its 1,094 refused shots came while that game's player was in the STORE)
    if inStore() then S.n.inStore = (S.n.inStore or 0) + 1; return nil end
    local a = standInAddr(slot)
    if not a then S.n.noPlane = (S.n.noPlane or 0) + 1; return nil end
    if M.peers[slot] and M.peers[slot].real then                 -- (a real plane: its launches come as "p", T4b)
        S.n.real = (S.n.real or 0) + 1
        return nil
    end
    if type(SV_CoopFire) ~= "function" then
        once("nofire", "coopfire: dlls/main.dll has no SV_CoopFire (runtime 0.28.5 or later): the other players' fire isn't shown")
        return nil
    end
    local okF, r = pcall(SV_CoopFire, a, fcs, target or 0)
    if not okF then r = tostring(r) end
    if r == 1 then S.n.fired = S.n.fired + 1 else S.n.failed = S.n.failed + 1 end
    local said = r == 1 and "queued" or (SV_ERR[r] and (tostring(r) .. " " .. SV_ERR[r]) or tostring(r))
    once("first" .. slot .. "/" .. fcs, string.format("coopfire: player %d's first %s here (their plane %X, %s): %s", slot + 1,
        FCS_NAME[fcs] or tostring(fcs), a, target and string.format("at %X", target) or "no target", said))
    if r ~= 1 then
        once("fail" .. fcs .. "/" .. tostring(r), string.format("coopfire: SV_CoopFire(player %d's plane, slot %d) refused: %s",
            slot + 1, fcs, said))
    end
    return r
end
local function halfRtt(slot) return math.floor(((M.rtt and M.rtt[slot]) or 100) / 2) end

-- (0.73.80) Weapon stand-ins (the user, 2026-11-04: "Then do the weapon stand-ins next"). A launch whose weapon number
-- their real plane here hasn't, or has as another kind of weapon, is shown as the nearest weapon of the same kind it has
-- instead of being dropped. A player on a weapon mod (SPWeaponCustomizer's extra special slots, AC8WeaponSwap) or in a
-- modded plane shown here on a stock fallback (its own default loadout) fires numbers the plane here hasn't: the runtime
-- refused those ("not a weapon of their plane here", 57-74 a game in the 31-round test of 2026-11-04: Amia's F-22A
-- firing weapon 3, its plane here with weapons 0-2). What the plane here has comes from SV_PPWeapons (runtime 0.32.24):
-- each number -2 not usable, -1 not known yet, 0-4 its kind as seen launched here (0 explosive: missiles and bombs, 1
-- the laser, 2 a bullet special, 3 an electronic one: ESM / ECM, 4 another), 10-14 its launcher table entry's (not
-- verified in the exe: used only with standin_table). M.weaponFor picks, for a shot of kind k and weapon w:
--   (b) a special whose id (their loadout now) sits at the plane's other special number (its loadout as it spawned:
--       theirs changed since) -> that number, the same weapon;
--   (a) w itself when the plane has it and it's of that kind or not known; but a missile special not known on a fallback
--       plane (another airframe's numbers) or where their loadout has another special now isn't trusted: the remote
--       fire treats whatever it launches as a missile, a laser or ESM there too;
--   (c) the nearest number of the same kind, ties to the lower: a missile special the nearest missile special, else
--       the standard missile (weapon 1: every player plane's, known or not); the standard missile weapon 1, else the
--       nearest special; a laser or ESM / ECM only one of its kind, else not shown; a bullet special one of its kind,
--       else a burst of the plane's gun (standin_gun_s).
-- Only numbers the plane here has are sent once it's known. A stand-in launch (c) keeps the shot's seed, start, rotation,
-- velocity and target, its spawn slot 0, the +0x26 byte 0 and its lock-ons at most 1 (another weapon's mean other
-- things); (b) changes the number only. The relay keeps the original: each game picks for its own plane. No
-- SV_PPWeapons (an older runtime), nothing read, or [coop.sync] standins = false: as sent, as before.
-- (fireShots, M.standInPay) what this game knows of player slot's real plane's weapons: { addr, at, tbl, n, k = { [0] =
-- ... }, s }; nil when it can't tell. Read on the first shot of each plane, again at most every 2 s when a shot needs it:
-- a stand-in, or its own number while that number's kind isn't known here or is known only from its table entry
-- (standin_table: the runtime may turn the table off after a launch that disagrees; the review of 0.73.80) (the runtime
-- learns it from that launch and then refuses another kind's shots there: the review of 2026-11-04), or when it couldn't
-- be read
function M.ppKinds(slot, P, now, need)
    if type(SV_PPWeapons) ~= "function" or not P.addr then return nil end
    local c = P.wk
    if c and c.addr == P.addr and (now - c.at < 2 or (c.n and not need)) then return c.n and c or nil end
    c = { addr = P.addr, at = now, tbl = sc().standin_table == true }
    P.wk = c
    local okW, s = pcall(SV_PPWeapons, P.addr, c.tbl and 1 or 0)
    if not (okW and type(s) == "string" and s ~= "") then
        once("ppw" .. slot .. "/" .. tostring(P.addr), string.format("coopfire: player %d's real plane here: its weapons can't "
            .. "be read (SV_PPWeapons: %s): their launches go as sent", slot + 1, okW and tostring(s) or ("error " .. tostring(s))))
        return nil
    end
    local k, n, usable, words = {}, 0, 0, {}
    for v in s:gmatch("[^,]+") do
        local x = M.intOf(v) or -1
        k[n] = x
        if x ~= -2 then usable = usable + 1 end
        words[#words + 1] = string.format("%d %s%s", n, (n == 0 and x == -1) and "the gun" or M.kindWord(x >= 10 and x - 10 or x, n),
            x >= 10 and " (its table's)" or "")
        n = n + 1
    end
    if n == 0 or n > 64 or usable == 0 then
        once("ppw0" .. slot .. "/" .. tostring(P.addr), string.format("coopfire: player %d's real plane here: no weapon of it usable "
            .. "(SV_PPWeapons %s): their launches go as sent", slot + 1, s))
        return nil
    end
    c.n, c.k, c.s = n, k, s
    if P.wkSaid ~= tostring(P.addr) .. s then                  -- (once a plane, again when what's known changes)
        P.wkSaid = tostring(P.addr) .. s
        log(string.format("coopfire: player %d's real plane here (%s%s): its weapons %s (SV_PPWeapons %s)", slot + 1,
            tostring(P.code or "?"), P.fallback and (", shown as a " .. tostring(P.fallback)) or "", table.concat(words, ", "), s))
    end
    return c
end
-- v as a whole number, else nil
function M.intOf(v)
    local x = tonumber(v)
    if not x or x ~= math.floor(x) or x ~= x then return nil end
    return math.floor(x)
end
-- a weapon kind in words (k: 0-4, -1 not known, -2 not usable; w its number: 0 the gun, 1 the standard missile, 2 and
-- up the specials); bare: without "a" / "the"
function M.kindWord(k, w, bare)
    local t
    if k == 0 then
        t = w == 1 and { "standard missile", "the standard missile" } or w == 0 and { "explosive weapon", "an explosive weapon" }
            or { "missile special", "a missile special" }
    else
        t = ({ [1] = { "laser", "a laser" }, [2] = { "bullet special", "a bullet special" }, [3] = { "ESM / ECM", "an ESM / ECM" },
               [4] = { "weapon of another kind", "a weapon of another kind" }, [-1] = { "not known yet", "not known yet" },
               [-2] = { "not usable", "not usable" } })[k] or { "?", "?" }
    end
    return bare and t[1] or t[2]
end
-- the kind (0-4) of weapon i on a plane here whose weapons are c (M.ppKinds); nil when it isn't known here (a table
-- entry's only with standin_table)
function M.kindAt(c, i)
    local v = c.k[i]
    if v == nil or v < 0 then return nil end
    if v >= 10 then return c.tbl and v - 10 or nil end
    return v
end
-- the number to show a shot of kind k, weapon w on a plane here whose weapons are c (M.ppKinds); ids: { sh = their
-- specials' ids now, cp = the plane's here as it spawned, dflt = it spawned with its default loadout (cp {}) } (nil:
-- not known, or a fallback); fb: a fallback plane; gun: a burst of its gun may stand in. -> x, how: "own" (w as sent),
-- "id", "near", or nil and "gun" / "none"
function M.weaponFor(k, w, c, ids, fb, gun)
    local K, n, lo = c.k, c.n, k == 0 and 1 or 2
    local function kindAt(i) return M.kindAt(c, i) end
    local function usable(i) return i >= lo and i < n and K[i] ~= nil and K[i] ~= -2 end
    if ids and (w == 2 or w == 3) and (ids.sh[w] or 0) > 0 then          -- (b) the same special, at its number here
        for j = 2, 3 do
            local kj = kindAt(j)
            if ids.cp[j] == ids.sh[w] and usable(j) and (kj == nil or kj == k) then return j, j == w and "own" or "id" end
        end
    end
    if usable(w) then                                                 -- (a) its own number
        local kw = kindAt(w)
        if kw == k then return w, "own" end
        local other = ids and (w == 2 or w == 3) and ids.cp[w] ~= ids.sh[w]
        if kw == nil and (k ~= 0 or w == 1 or not (fb or other)) then return w, "own" end
    end
    local best, bestD                                                 -- (c) the nearest of its kind (ties: the lower)
    local function consider(i)
        local ki = kindAt(i)
        if usable(i) and (ki == k or (k == 0 and i == 1 and ki == nil)) and (not best or math.abs(i - w) < bestD) then
            best, bestD = i, math.abs(i - w)
        end
    end
    if k == 0 and w <= 1 then consider(1) end                         -- (the standard missile: weapon 1 first)
    if not best then for i = 2, n - 1 do consider(i) end end          -- (a special: the specials first)
    if k == 0 and not best then consider(1) end
    if best then return best, "near" end
    if k == 2 and gun then return nil, "gun" end
    return nil, "none"
end
-- why a shot of kind k, weapon w isn't shown as itself on that plane (the log's words)
local function standWhy(k, w, c, ids, fb)
    local v = c.k[w]
    if w >= c.n or v == nil or v == -2 then return string.format("it has no weapon %d", w) end
    if w < (k == 0 and 1 or 2) then return k == 0 and "weapon 0 is the gun" or "a special's number is 2 or more" end
    local kv = M.kindAt(c, w)
    if kv and kv ~= k then return string.format("its weapon %d is %s", w, M.kindWord(kv, w)) end
    if ids and ids.dflt and (w == 2 or w == 3) then
        return string.format("their plane here spawned with its own default loadout (theirs hadn't come), their special %d is id %s",
            w - 1, tostring(ids.sh[w]))
    end
    if ids and (w == 2 or w == 3) and ids.cp[w] ~= ids.sh[w] then
        return string.format("their special %d is id %s now, the plane here has id %s there (their loadout changed since it spawned)",
            w - 1, tostring(ids.sh[w]), tostring(ids.cp[w]))
    end
    if fb then return string.format("its weapon %d isn't known yet and it's another airframe (a fallback: its numbers aren't theirs)", w) end
    return string.format("its weapon %d isn't known yet", w)
end
-- a loadout's two special ids ("a,b/c/x,y" -> { [2] = x, [3] = y }: weapons 2 and 3), nil if it has none
function M.loIds(lo)
    if type(lo) ~= "string" then return nil end
    local x, y = lo:match("/(%d+),(%d+)$")
    if not x then return nil end
    return { [2] = tonumber(x), [3] = tonumber(y) }
end
-- (fireShots) the shot to ask of player slot's real plane here for one of their launches (pay: "k,w,s,u,seed,lock,..."):
-- pay itself (its own weapon, or nothing known of the plane), another weapon's (a stand-in), or nil and why ("gun": a
-- burst of its gun instead, "none": not shown)
function M.standInPay(slot, P, pay, now)
    if sc().standins == false then return pay end
    local f = {}
    for v in pay:gmatch("[^,]+") do f[#f + 1] = v end
    local k, w = M.intOf(f[1]), M.intOf(f[2])
    if #f ~= 15 or not k or not w or k < 0 or k > 3 or w < 0 or w > 255 then return pay end   -- (the runtime refuses it)
    local c = M.ppKinds(slot, P, now, false)
    if not c then return pay end
    local r0 = M.roster[slot]
    local sh, cp = M.loIds(r0 and r0.lo), nil
    if not P.fallback then cp = M.loIds(P.lo) end
    local ids = (sh and cp) and { sh = sh, cp = cp } or nil
    -- (the review of 2026-11-04: a plane here spawned before their loadout came (P.lo "") flies the airframe's default
    -- specials, so a missile special of theirs not known there isn't trusted either: it could be a laser or ESM here.
    -- Both unknown: both the default, trusted)
    if sh and not cp and not P.fallback then ids = { sh = sh, cp = {}, dflt = true } end
    local fb, gun = P.fallback ~= nil, on("guns")
    local x, how = M.weaponFor(k, w, c, ids, fb, gun)
    -- (a stand-in, or its own number whose kind isn't known here: what's been seen launched since, first. The runtime
    -- learns a number's kind from its first launch here and refuses another kind's shots there after; without a read
    -- again those were refused for good, never put on the plane's weapon of their kind: the review of 2026-11-04.
    -- (review of 0.73.80) A kind known only from its table entry (standin_table: 10-14) isn't confirmed either: a launch
    -- that disagrees turns the table off in the runtime, and the seen kind then wins there)
    if now - c.at >= 2 and (how ~= "own" or not M.kindAt(c, x) or (c.k[x] or -1) >= 10) then
        local c2 = M.ppKinds(slot, P, now, true)
        if not c2 then return pay end
        c = c2
        x, how = M.weaponFor(k, w, c, ids, fb, gun)
    end
    if how == "own" then return pay end
    local n = S.n
    n.standBy = n.standBy or {}
    local by = n.standBy[slot] or {}
    n.standBy[slot] = by
    local mk = string.format("%s%d->%s", k == 0 and "" or (M.kindWord(k, w, true) .. " "), w, x and tostring(x) or how)
    by[mk] = (by[mk] or 0) + 1
    local what = M.kindWord(k, w, true)
    local key = string.format("si%d/%d/%d>%s/%s", slot, k, w, tostring(x or how), tostring(P.addr))
    if how == "id" or how == "near" then
        n.standIn = (n.standIn or 0) + 1
        once(key, string.format("coopfire: player %d's %s (weapon %d) shown on their real plane here as its weapon %d (%s): %s",
            slot + 1, what, w, x, M.kindWord(k, x), how == "id" and string.format("the same special sits there (id %s; their "
            .. "loadout changed since it spawned)", tostring(ids and ids.sh[w])) or standWhy(k, w, c, ids, fb)))
        f[2] = tostring(x)
        if how == "near" then
            f[3], f[4] = "0", "0"
            f[6] = tostring(math.min(M.intOf(f[6]) or 0, 1))
        end
        return table.concat(f, ",")
    end
    if how == "gun" then
        n.standGun = (n.standGun or 0) + 1
        P.burstUntil = now + (tonumber(sc().standin_gun_s) or 0.5)
        once(key, string.format("coopfire: player %d's bullet special (weapon %d) shown as their real plane's gun here: %s, and "
            .. "it has no bullet special (its weapons: %s)", slot + 1, w, standWhy(k, w, c, ids, fb), c.s))
        return nil, how
    end
    n.standNone = (n.standNone or 0) + 1
    once(key, string.format("coopfire: player %d's %s (weapon %d) NOT shown: %s, and their real plane here has no %s (its weapons: "
        .. "%s)", slot + 1, what, w, standWhy(k, w, c, ids, fb), k == 0 and "missile" or what, c.s))
    return nil, how
end
-- player slot's shots (entries "k:id:age"; extraMs: this leg's half round trip): each one that passes the guards fired
-- from their plane here; those entries (their ages grown) for the host to relay
local function fireShots(slot, body, extraMs)
    local passed = {}
    if not (slotOk(slot) and slot ~= COOP.slot and type(body) == "string") then
        once("fxslot", "coopfire: shots from a slot that isn't another player's dropped (" .. tostring(slot) .. ")")
        return passed
    end
    local P, now = M.peers[slot], os.clock()
    local R = S.rate[slot] or { at = now, n = 0 }
    S.rate[slot] = R
    if now - R.at >= 1 then R.at, R.n, R.np = now, 0, 0 end
    local lagging = P and type(P.age) == "number" and P.age > 1000      -- (their state over a second old)
    local why, n = {}, 0
    for e in body:gmatch("[^;]+") do
        n = n + 1
        local pid, page, pay = e:match("^p:(%d+):(%d+):([%-%d,]+)$")
        if pid then                                          -- (a launch for their real plane here: T4b)
            pid, page = tonumber(pid), tonumber(page) + extraMs
            local bad = (n > FX_MAX and "more than " .. FX_MAX .. " in a message") or ((pid > 65535 or #pay > 200) and "unreadable")
                or ((page > FX_STALE_MS or lagging) and "stale") or ((R.np or 0) >= P_PER_S and "over " .. P_PER_S .. " launches a second")
            if bad then
                why[bad] = (why[bad] or 0) + 1
                S.n.dropped = S.n.dropped + 1
            else
                R.np = (R.np or 0) + 1
                passed[#passed + 1] = string.format("p:%d:%d:%s", pid, page, pay)
                if P and P.real and P.addr and valid(P.obj) and on("missiles") and type(SV_CoopPPShot) == "function"
                    and not inStore() then
                    -- ((0.73.80) a weapon their plane here hasn't: the nearest of its kind it has, M.standInPay; the
                    -- relay above keeps theirs)
                    local okP, pay2 = pcall(M.standInPay, slot, P, pay, now)
                    if not okP then
                        once("sipay", "coopfire: the weapon stand-in failed (" .. tostring(pay2) .. "): their launches go as sent")
                        pay2 = pay
                    end
                    if pay2 then
                        -- ((2026-11-11, the 50-round run's alicorn-3) one whose target isn't here goes unguided: counted)
                        local ta = addrOfId(pid)
                        if pid > 0 and not ta then S.n.pUntargeted = (S.n.pUntargeted or 0) + 1 end
                        local okS, r = pcall(SV_CoopPPShot, P.addr, ta or 0, pay2)
                        if not okS then r = tostring(r) end
                        if r == 1 then S.n.pOk = (S.n.pOk or 0) + 1 else S.n.pBad = (S.n.pBad or 0) + 1 end
                        once("pfirst" .. slot, string.format("coopfire: player %d's first launch on their real plane here: %s", slot + 1,
                            r == 1 and "queued" or ("refused (" .. tostring(r) .. ")")))
                    end
                end
            end
        else
        local k, id, age = e:match("^([msge]):(%d+):(%d+)$")
        id, age = tonumber(id), tonumber(age)
        local bad = (n > FX_MAX and "more than " .. FX_MAX .. " in a message") or ((not k or id > 65535 or age > 600000) and "unreadable")
        if not bad and k == "g" then                         -- (the gun's target: no shot)
            if P then P.gunTarget = id end
            passed[#passed + 1] = string.format("g:%d:%d", id, age + extraMs)
        elseif not bad then
            age = age + extraMs
            bad = ((age > FX_STALE_MS or lagging) and "stale") or (R.n >= FX_PER_S and "over " .. FX_PER_S .. " a second") or nil
            if not bad then
                R.n, S.n.got = R.n + 1, S.n.got + 1
                passed[#passed + 1] = string.format("%s:%d:%d", k, id, age)
                local t = addrOfId(id)
                if id > 0 and not t then S.n.untargeted = (S.n.untargeted or 0) + 1 end
                if k == "e" then                                   -- (their ESM / jamming pod: the stand-in's ECM pod)
                    local row = P and P.row
                    local ecm = row and M.ecmSlot[row]
                    if not on("missiles") then
                    elseif ecm then coopFire(slot, ecm, nil)
                    else
                        once("noecm" .. slot .. tostring(row), string.format("coopfire: player %d's electronic special: their "
                            .. "plane here (%s) has no ECM pod to show it", slot + 1, tostring(row)))
                    end
                elseif on("missiles") then coopFire(slot, 2, t) end
            end
        end
        if bad then
            why[bad] = (why[bad] or 0) + 1
            S.n.dropped = S.n.dropped + 1
        end
        end
    end
    for w, c in pairs(why) do once("fxdrop" .. slot .. w, string.format("coopfire: player %d's shots dropped: %d %s", slot + 1, c, w)) end
    return passed
end
-- (the host) a joiner's "fx|entries": fired here, then to every other joiner as "fx|<slot>|entries"
function M.fxFromJoiner(from, f)
    local ok = fireShots(from, f[2], halfRtt(from))
    if #ok == 0 then return end
    local body = table.concat(ok, ";")
    for s in pairs(M.roster) do
        if s ~= 0 and s ~= from and s ~= COOP.slot then sendTo(s, true, "fx", from, body) end
    end
end
-- (a joiner) the host's "fx|<slot>|entries": the host's own or another joiner's, relayed
function M.fxFromHost(f)
    fireShots(tonumber(f[2]), f[3], halfRtt(0))
end

-- ((review of 0.73.80) a real plane's gun trigger (weapons +0x311) stays set until it's written back: let go wherever
-- the sync stops driving it (hidden, stale, set aside, a new level's P), so their plane here never fires on for good)
function M.gunOff(P)
    if P and P.real and P.gunOn and P.addr and P.obj and live(P.obj) and type(SV_CoopPPFx) == "function" then
        pcall(SV_CoopPPFx, P.addr, 1, 0)
    end
    if P then P.gunOn, P.burstUntil = false, nil end
end
-- the other players' state bits on their planes here: gear flips, gun bursts, flares
local function peersTick(now)
    for s, P in pairs(M.peers) do
        if P.gunOn and not (s ~= COOP.slot and P.obj and P.shown and P.fresh and valid(P.obj)) then M.gunOff(P) end
        if s ~= COOP.slot and P.obj and P.shown and P.fresh and valid(P.obj) and type(P.flags) == "number" then
            local fl = P.flags
            if on("gear") then
                local g = bit(fl, BIT_GEAR)
                if g ~= P.gear then
                    local first = P.gear == nil
                    P.gear = g
                    if not (first and not g) then                     -- (a new plane comes gear up: only "down" to say)
                        -- (a real plane: the game's own gear calls, as Online Mode's LandingGear; a stand-in: the AI's)
                        local okG, err = pcall(function()
                            if P.real then
                                local r = type(SV_CoopPPFx) == "function" and SV_CoopPPFx(P.addr, 2, g and 1 or 0) or -9
                                if r ~= 1 then error("SV_CoopPPFx " .. tostring(r)) end
                            else P.obj:EnableLandingGear(g, 1.0) end
                        end)
                        P.gearFlips = (P.gearFlips or 0) + 1
                        if P.gearFlips <= 4 or not okG then
                            log(string.format("coopfire: player %d's gear %s here: %s", s + 1, g and "down" or "up",
                                okG and "EnableLandingGear done" or ("EnableLandingGear failed: " .. tostring(err))))
                        end
                    end
                end
            end
            if P.real then                                    -- (a real plane: its own gun's trigger and flares, COOP2MP T4)
                -- ((0.73.80) or a bullet special their plane here hasn't, shown as a burst of its gun: M.standInPay)
                local gun = on("guns") and (bit(fl, BIT_GUN) or now < (P.burstUntil or 0)) or false
                if gun ~= (P.gunOn or false) and type(SV_CoopPPFx) == "function" then
                    P.gunOn = gun
                    SV_CoopPPFx(P.addr, 1, gun and 1 or 0)
                end
                if on("flares") then
                    local f = bit(fl, BIT_FLARE)
                    if f and (not P.flare or now >= (P.flareNext or 0)) and type(SV_CoopPPFx) == "function" then
                        P.flareNext = now + FLARE_EVERY_S
                        local r = SV_CoopPPFx(P.addr, 0, 1)
                        once("realflare" .. s, string.format("coopfire: player %d's flares on their real plane here: %s", s + 1, tostring(r)))
                    end
                    P.flare = f
                end
            else
            if on("guns") and bit(fl, BIT_GUN) and now >= (P.gunNext or 0) then
                P.gunNext = now + GUN_EVERY_S
                coopFire(s, 1, addrOfId(P.gunTarget))
            end
            if on("flares") then
                local f = bit(fl, BIT_FLARE)
                if f and (not P.flare or now >= (P.flareNext or 0)) then
                    P.flareNext = now + FLARE_EVERY_S
                    coopFire(s, 0, nil)
                end
                P.flare = f
            end
            end
        end
    end
end

-- (COOP.tick, after the state went out) this game's shots to the others, theirs shown here, the ammo counts kept
function M.syncTick(now, pawn)
    if sc().enabled ~= true then return end
    if valid(pawn) then
        local out = {}
        local pa = addrOf(pawn)
        if pa ~= S.pawn then S.pawn, S.seen, S.primed = pa, {}, false end
        if on("missiles") then watchShots(pawn, out) end
        -- the gun's target, as the gun starts or the target changes while it fires (the stand-ins aim there)
        local gun = on("guns") and S.gunAt and now - S.gunAt <= FLAG_HOLD_S
        if gun and type(SV_PlayerTarget) == "function" and pa then
            local okT, t = pcall(SV_PlayerTarget, pa)
            local id = (okT and type(t) == "number" and t > 0) and idOfAddr(t) or 0
            if okT and type(t) == "number" and t > 0 then M.gunMark(t) end   -- ((0.73.79) M.floorLoss)
            if id ~= S.gunTarget or not S.gunOn then out[#out + 1] = string.format("g:%d:0", id); S.gunTarget = id end
        end
        S.gunOn = gun
        -- a special weapon used with nothing new in flight since (an ESM / jamming pod): "e", its age since the drop
        if S.spDropAt and now - S.spDropAt >= ELEC_WAIT_S then
            if not (S.spShotAt and S.spShotAt >= S.spDropAt - 0.3) then
                out[#out + 1] = string.format("e:0:%d", math.floor((now - S.spDropAt) * 1000 + 0.5))
                once("fxelec", "coopfire: your special weapon went off with nothing in flight (an ESM or jamming pod): sent as e")
            end
            S.spDropAt = nil
        end
        -- your launches as the runtime read them, for your real plane in the other games (T4b): "p:<target id>:0:<shot>"
        if on("missiles") and type(SV_CoopShots) == "function" then
            local okL, list = pcall(SV_CoopShots)
            if okL and type(list) == "string" and list ~= "" then
                for e in list:gmatch("[^;]+") do
                    local pay, t = e:match("^([%-%d,]+),(%d+)$")
                    if pay then
                        local ta = tonumber(t) ~= 0 and tonumber(t) or nil
                        local tid = idOfAddr(ta)
                        -- ((2026-11-11, the 50-round run's alicorn-3) at a target here with no co-op id (a copy not bound,
                        -- not the host's): it goes as p:0, unguided on the other games, and nothing of it reaches them
                        if ta and tid == 0 then S.n.pNoId = (S.n.pNoId or 0) + 1 end
                        out[#out + 1] = string.format("p:%d:0:%s", tid, pay)
                    end
                end
            end
        end
        if #out > FX_MAX then for i = #out, FX_MAX + 1, -1 do out[i] = nil end end
        local shots = 0
        for _, e in ipairs(out) do local c = e:sub(1, 1); if c ~= "g" and c ~= "p" then shots = shots + 1 end end
        if #out > 0 and (M.linkedPeers or 0) > 0 then
            local body = table.concat(out, ";")
            if COOP.host() then send(true, "fx", COOP.slot or 0, body) else send(true, "fx", body) end
            S.n.sent = S.n.sent + shots
            if shots > 0 then once("fxsent", "coopfire: your first shot sent (" .. body .. ")") end
        end
    end
    peersTick(now)
    ammoAfter()
    if now >= (S.statAt or now + 60) then                   -- (a minute's tally, when anything happened)
        local n = S.n
        if n.sent + n.got + n.fired + n.failed + n.dropped + (n.bursts or 0) + (n.flares or 0) + (n.pOk or 0) + (n.pBad or 0)
            + (n.standIn or 0) + (n.standGun or 0) + (n.standNone or 0) + (n.pNoId or 0) > 0 then
            -- ((0.73.80) the weapon stand-ins, when any: how many, and each player's numbers as sent -> shown here)
            local si = ""
            if (n.standIn or 0) + (n.standGun or 0) + (n.standNone or 0) > 0 then
                local per = {}
                for s, by in pairs(n.standBy or {}) do
                    local maps = {}
                    for mk, c in pairs(by) do maps[#maps + 1] = string.format("%s x%d", mk, c) end
                    table.sort(maps)
                    per[#per + 1] = string.format("%d: %s", s + 1, table.concat(maps, ", "))
                end
                table.sort(per)
                si = string.format("; weapon stand-ins: %d on another weapon of the same kind, %d as the gun, %d not shown (no "
                    .. "weapon of that kind there); by player: %s", n.standIn or 0, n.standGun or 0, n.standNone or 0, table.concat(per, "; "))
            end
            log(string.format("coopfire: 60 s: %d shots sent, %d received (%d fired here, %d refused, %d dropped, %d with "
                .. "their target not here, %d with no plane here, %d not shown: you were in the STORE), your gun %d bursts, "
                .. "your flares %d, your gear flips %d, afterburner flips %d, throttle up to %.3f (ab_throttle %s); real planes' "
                .. "launches (T4b) %d queued, %d refused, %d unguided (their target not here); your launches at a target with no "
                .. "co-op id %d%s", n.sent,
                n.got, n.fired, n.failed, n.dropped, n.untargeted or 0, n.noPlane or 0, n.inStore or 0, n.bursts or 0,
                n.flares or 0, n.gear, n.ab, (n.thMax or 0) / 1000, tostring(sc().ab_throttle), n.pOk or 0, n.pBad or 0,
                n.pUntargeted or 0, n.pNoId or 0, si))
        end
        S.n = { sent = 0, got = 0, fired = 0, failed = 0, dropped = 0, gear = 0, ab = 0 }
        S.statAt = now + 60
    end
    S.statAt = S.statAt or now + 60
end

-- The stand-ins' damage-0 rows, made at the main menu (sv_main.lua, every second until done): the spawner reads the
-- world data's mission rows' DT_NPC rows when the level loads (hard rule 20, sv_rows.lua searchSetup), so for every
-- airframe a stand-in flies (CFG.coop.airframes, default) the mission row <row>_svcp (tools/build_survival.py,
-- COOP_STANDIN_SUFFIX) names <its NpcId>_SVCP, made here as a copy of <row>'s DT_NPC row with each fire-control slot on
-- <FCS>_SVCP and that one's weapon on <W>_SVCP: damage and AreaOfEffectDamage 0 (the allies' <FCS>_SVA way). A slot
-- whose weapon can't be made harmless is emptied. M.svcpReady[row] once made; a level that loads after flies them.
function COOP.syncSetup()
    local c = cfg()
    if M.svcpDone or not c.enabled or not gameInstance() then return end
    M.svcpTries = (M.svcpTries or 0) + 1
    local npc, mission, fcs, wpn = loadObject(PROBE_TABLES[2].path), loadObject(MISSION_TABLE), loadObject(FCS_TABLE), loadObject(WEAPON_TABLE)
    if not (npc and mission and fcs and wpn) then
        if M.svcpTries >= 20 then
            M.svcpDone = true
            log("coopfire: the stand-ins' tables didn't load: they fly their airframes' own rows (what they fire could do damage)")
        end
        return
    end
    M.svcpDone, M.svcpReady = true, {}
    for _, t in ipairs({ npc, mission, fcs, wpn }) do pin(t, nameOf(t)) end
    local made, emptied, lost, ecms = {}, {}, {}, {}
    -- (the electronic-warfare airframes: their plain campaign rows, OP1010_e18g_01 and kin, have no ECM pod, only the
    -- named aces' do; their copies get the stock one in their first free slot, so the others' ESM shows on them)
    local ELEC = { e18g_common = true, ea36_common = true, e06b_common = true }
    local function harmless(id)                           -- id .. "_SVCP": its weapon's damage 0, or nil
        local new = id .. "_SVCP"
        if made[new] == nil then
            made[new] = cloneRow(fcs, id, new, function(r)
                local w = r.NpcWeaponId:ToString()
                if w == "None" or w == "" then return end
                local wn = w .. "_SVCP"
                local okW, whyW = cloneRow(wpn, w, wn, function(x)
                    x.damage = 0
                    pcall(function() x.AreaOfEffectDamage = 0 end)
                end)
                if not okW then error("weapon " .. w .. ": " .. tostring(whyW), 0) end
                local _, xr = dtCall(wpn, "FindRow", wn)
                if not (xr ~= nil and xr.damage == 0) then error("weapon " .. wn .. " doesn't read back damage 0", 0) end
                r.NpcWeaponId = FName(wn)
            end) and true or false
        end
        return made[new] and new or nil
    end
    local rows, seen = {}, {}
    for _, r in pairs(c.airframes or {}) do if not seen[r] then seen[r] = true; rows[#rows + 1] = r end end
    if c.default and not seen[c.default] then rows[#rows + 1] = c.default end
    table.sort(rows)
    for _, row in ipairs(rows) do
        local ok, err = pcall(function()
            local _, base = dtCall(mission, "FindRow", row)
            local _, mr = dtCall(mission, "FindRow", row .. "_svcp")
            if base == nil or mr == nil then error("no mission row " .. (base == nil and row or row .. "_svcp") .. " in DT_SV_NpcMission", 0) end
            local src, dst = base.NpcId:ToString(), mr.NpcId:ToString()
            local okR, whyR = cloneRow(npc, src, dst, function(r)
                for i = 0, 5 do
                    local id = r["NpcFCSId" .. i]:ToString()
                    if id:upper():find("ECM", 1, true) then M.ecmSlot[row] = i; ecms[#ecms + 1] = row .. " slot " .. i end
                    if id ~= "None" and id ~= "" and not id:find("_SVCP$") then
                        local new = harmless(id)
                        if new then r["NpcFCSId" .. i] = FName(new)
                        else r["NpcFCSId" .. i] = FName("None"); emptied[#emptied + 1] = dst .. " slot " .. i .. " (" .. id .. ")" end
                    end
                end
                if ELEC[row] and M.ecmSlot[row] == nil then
                    for i = 3, 5 do
                        local id = r["NpcFCSId" .. i]:ToString()
                        if id == "None" or id == "" then
                            r["NpcFCSId" .. i] = FName("NPC_FCS_ECM000")
                            M.ecmSlot[row] = i
                            ecms[#ecms + 1] = row .. " slot " .. i .. " (added)"
                            break
                        end
                    end
                end
            end)
            if not okR then error(dst .. ": " .. tostring(whyR), 0) end
            M.svcpReady[row] = row .. "_svcp"
        end)
        if not ok then lost[#lost + 1] = row .. " (" .. tostring(err) .. ")" end
    end
    local n = 0
    for _ in pairs(M.svcpReady) do n = n + 1 end
    log(string.format("coopfire: the stand-ins' damage-0 rows: %d of %d airframes%s%s; ECM pods (the others' ESM shown): %s", n,
        #rows, #emptied > 0 and ("; weapons left off: " .. table.concat(emptied, ", ")) or "",
        #lost > 0 and ("; not made (their own rows): " .. table.concat(lost, "; ")) or "",
        #ecms > 0 and table.concat(ecms, ", ") or "none"))
end

-- TEST ONLY BEGIN (Ctrl+F5, sv_main.lua: the co-op fire path on an allied plane, solo; docs/re/COOP.md 8)
-- Each press the next step on the first allied fighter up (MOONCHILD or VIPER, bought in the STORE), aimed at your
-- current target (SV_PlayerTarget, or none): 1 its missiles (slot 2) with its fire permission off, 2 the same with it
-- on, 3 its gun (slot 1), 4 its flares (slot 0), 5 its gear down, 6 its gear up; each "coopfire: test ..."
function COOP.fireTest()
    local R = ALLY and ALLY.run
    local ally = nil
    for _, p in ipairs(R and R.planes or {}) do if not ally and valid(p.obj) and (health(p.obj) or 0) > 0 then ally = p end end
    if not ally then log("coopfire: test: no allied plane up (buy MOONCHILD or VIPER in the STORE)"); hudCallout("TEST: NO ALLIED PLANE UP", "BUY ONE IN THE STORE"); return end
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    local t = (valid(pawn) and type(SV_PlayerTarget) == "function") and SV_PlayerTarget(addrOf(pawn)) or 0
    t = (type(t) == "number" and t > 0) and t or 0
    S.test = (S.test or 0) % 6 + 1
    local a, step, r = addrOf(ally.obj), S.test, nil
    local fire = type(SV_CoopFire) == "function" and SV_CoopFire or function() return "no SV_CoopFire" end
    local what
    if step <= 2 then
        pcall(function() ally.obj.bPermissionToFire = step == 2 end)
        local okP, perm = pcall(function() return ally.obj.bPermissionToFire end)
        r, what = fire(a, 2, t), string.format("missiles (slot 2), fire permission %s", okP and tostring(perm) or "?")
    elseif step == 3 then r, what = fire(a, 1, t), "gun (slot 1)"
    elseif step == 4 then r, what = fire(a, 0, 0), "flares (slot 0)"
    else
        local okG, err = pcall(function() ally.obj:EnableLandingGear(step == 5, 1.0) end)
        r, what = okG and "done" or ("failed: " .. tostring(err)), "EnableLandingGear(" .. tostring(step == 5) .. ", 1.0)"
    end
    log(string.format("coopfire: test %d: %s (%s) %s at %s: %s", step, ally.name, ally.unit, what, t > 0 and string.format("%X", t) or "no target", tostring(r)))
    hudCallout("TEST " .. step .. ": " .. what:upper(), tostring(r))
end
-- TEST ONLY END
end

---------------------------------------------------------------------------------------------------- messages
-- your plane's loadout (SV_CoopLoadout, runtime 0.32.0: "a,b/c,d/x,y"), "" when it can't be read: the others' real
-- plane of yours carries it, so your weapon numbers mean there what they mean here (COOP2MP T4b)
function loadoutOk(lo) return type(lo) == "string" and #lo <= 600 and lo:match("^[%d,]*/[%d,]*/%d+,%d+$") ~= nil end
function M.myLoadout()
    if type(SV_CoopLoadout) ~= "function" then return "" end
    local ok, lo = pcall(SV_CoopLoadout)
    return (ok and loadoutOk(lo)) and lo or ""
end
M.loadoutOk = loadoutOk
-- your plane's paint (SV_CoopPaint, runtime 0.32.3: "skin/flags/e1,e2,..."): the others' real plane of yours wears it
-- (COOP2MP T5; [coop] real_paint)
function paintOk(p) return type(p) == "string" and #p <= 200 and p:match("^%-?%d+/%-?%d+/[%d,]*$") ~= nil end
function M.myPaint()
    if type(SV_CoopPaint) ~= "function" then return "" end
    local ok, p = pcall(SV_CoopPaint)
    return (ok and paintOk(p)) and p or ""
end
M.paintOk = paintOk
-- your aircraft's name as the game shows it (your plane's GetObjName: "ADFX-02" ...), for the line beside your name on
-- the others' boxes (SV_PPName's third argument, runtime 0.32.4); 32 characters at most, no "|"
function acClean(v)
    if type(v) ~= "string" then return "" end
    v = v:gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return #v <= 32 and v or v:sub(1, 32)
end
function M.myAircraft()
    local pawn = survivalPC and valid(survivalPC) and survivalPC.Pawn
    if not valid(pawn) then return "" end
    local ok, v = pcall(function() local x = pawn:GetObjName(); return type(x) == "string" and x or x:ToString() end)
    return ok and acClean(v) or ""
end
M.acClean = acClean
function sendHi()
    local row, code = myAirframe()
    -- (what the host last heard: a hello sent with no plane yet is followed by the airframe once there is one; the
    -- co-op run of 2026-10-30: a player who'd been in the level before linking never sent theirs, shown as the default)
    -- The airframe's code (COOP2MP T3: the player plane the others spawn for you; the ADFX-02 has no AI row) goes last.
    M.myRow, M.myCode, M.myLo, M.myPt, M.myAc = row, code, M.myLoadout(), M.myPaint(), M.myAircraft()
    -- ((0.73.80) a plane with no stock code: its class path and stock base last, for the games with and without it)
    local okP, mc, mb = pcall(M.myPlane, nil, code)
    M.myCls, M.myBase = okP and mc or "", okP and mb or ""
    send(true, table.unpack(M.modFields({ "hi", VERSION, type(SV_Version) == "function" and SV_Version() or "?", row or "",
        M.myName or "", code or "", M.myLo, M.myPt, M.myAc }, code, M.myCls, M.myBase)))
end

-- the host's own roster entry, and everyone told
function hostRosterSelf()
    local row, code = myAirframe()
    M.myRow, M.myCode, M.myLo, M.myPt, M.myAc = row, code, M.myLoadout(), M.myPaint(), M.myAircraft()
    local okP, mc, mb = pcall(M.myPlane, nil, code)        -- ((0.73.80) relayed in "pi" for a plane with no stock code)
    M.myCls, M.myBase = okP and mc or "", okP and mb or ""
    M.roster[0] = { row = row or "", ver = VERSION, name = M.myName or "", code = code or "", lo = M.myLo, paint = M.myPt,
                    ac = M.myAc, sid = M.mySid and M.mySid() or nil, cls = M.myCls, base = M.myBase }
    sendRoster(nil)
end

-- The host's settings for everyone (user, 2026-10-26: "we need to work on survival.ini syncing as some player might edit
-- their ini files"): the host sends each joiner what its CFG has that differs from the shipped one (CFG_DEFAULTS:
-- survival.ini and survival_config.lua both), as data only ("cf", in chunks); the joiner's CFG goes back to the shipped
-- settings and takes the host's on top, in place (other parts hold CFG's tables), and its own come back when co-op
-- closes or it hosts. Each player keeps their own PERSONAL sections (name and link, HUD, sound, music, leaderboard,
-- the menu's, tells, P6's profile and flares, the test logs' probe / ai_watch / stats / log; of [coop] the host's
-- revives all the same, SHARED_IN, but for the key and camera) and the host's difficulty preset is used for everyone
-- (presetName).
do
local PERSONAL = { coop = true, hud = true, sound = true, music = true, leaderboard = true, menu = true, probe = true, ai_watch = true,
                   stats = true, tells = true, profile = true, flares = true,   -- (profile, flares: P6's, each player's own)
                   log = true,                                                  -- ([log] verbose: each game's log)
                   recycle = true }                                             -- ((0.73.77) each runtime's own (F2b))
-- Inside a PERSONAL section, the host's all the same: the run's revives ([coop.revive], sv_down.lua: one price and floor
-- for the room) but for what's each player's own there (OWN_IN: the next-player key and the spectator camera)
local SHARED_IN = { { "coop", "revive" } }
local OWN_IN = { ["coop.revive.key"] = true, ["coop.revive.ctrl"] = true, ["coop.revive.camera"] = true }
local function pathStr(p, n) local q = {}; for j = 1, n or #p do q[j] = tostring(p[j]) end; return table.concat(q, ".") end
local function ownPath(p) for j = 1, #p do if OWN_IN[pathStr(p, j)] then return true end end; return false end
local function sharedPath(p)
    for _, s in ipairs(SHARED_IN) do
        local m = #p >= #s
        for j = 1, #s do if p[j] ~= s[j] then m = false end end
        if m then return true end
    end
    return false
end
local function at(t, p) for j = 1, #p do if type(t) ~= "table" then return nil end; t = t[p[j]] end; return t end
-- world-data unit lists (CFG.pool, airfield.bombers.pool / heavy_units, allies' units): build data, the same in the same
-- build, and other parts' lookup tables are made from them at load (code review: BOMBER_UNIT, HEAVY_UNIT, ALLY.unit)
local function structural(path)
    local last = path[#path]
    return path[1] == "pool" or last == "pool" or last == "heavy_units" or last == "units"
end
-- A host's value against the shipped one at its place (security review of 2026-10-26: a broken or hostile host must
-- not hang or break a joiner): the same type; numbers finite and not wildly past the shipped size; text short, no
-- control characters; lists of at most 1000 items like the shipped ones. Paths this build doesn't have are skipped.
local function fits(v, d)
    if type(v) ~= type(d) then return false end
    if type(v) == "number" then return v == v and math.abs(v) <= math.max(math.abs(d) * 1000, 100000) end
    if type(v) == "string" then return #v <= 1024 and not v:find("%c") end
    if type(v) == "table" then
        local n = 0
        for k, x in pairs(v) do
            n = n + 1
            local dx = d[k]
            if dx == nil and math.type(k) == "integer" then dx = d[1] end    -- (a list's new item: like its first)
            if n > 1000 or dx == nil or not fits(x, dx) then return false end
        end
    end
    return true
end
local function shipped(path)                               -- CFG_DEFAULTS at path, or nil
    local t = CFG_DEFAULTS
    for j = 1, #path do
        if type(t) ~= "table" then return nil end
        t = t[path[j]]
    end
    return t
end
local CHUNK = 900
local function esc(s) return (s:gsub("[%%,{}|%c]", function(c) return string.format("%%%02X", c:byte()) end)) end
local function enc(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do if type(x) ~= "function" then enc(k, out); enc(x, out) end end
        out[#out + 1] = "}"
    elseif t == "string" then out[#out + 1] = "s" .. esc(v)
    elseif t == "number" then out[#out + 1] = math.type(v) == "integer" and string.format("i%d", v) or string.format("n%.17g", v)
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
    else out[#out + 1] = "~" end
end
local function dec(tk, i, depth)
    local s = tk[i]
    if s == "{" then
        if depth > 40 then error("settings nested too deep") end
        local t = {}
        i = i + 1
        while tk[i] and tk[i] ~= "}" do
            local k, v
            k, i = dec(tk, i, depth + 1)
            v, i = dec(tk, i, depth + 1)
            if k ~= nil then t[k] = v end
        end
        return t, i + 1
    end
    local c, rest = (s or ""):sub(1, 1), (s or ""):sub(2)
    if c == "s" then return (rest:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)), i + 1
    elseif c == "i" then return math.tointeger(tonumber(rest)) or tonumber(rest), i + 1
    elseif c == "n" then return tonumber(rest), i + 1
    elseif c == "T" then return true, i + 1
    elseif c == "F" then return false, i + 1 end
    return nil, i + 1
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function isList(t) return type(t) == "table" and #t > 0 end
local function diff(cur, def, path, out)                   -- leaves (and whole lists) of cur that differ from def
    for k, v in pairs(cur) do
        local d = def[k]
        local p = { table.unpack(path) }
        p[#p + 1] = k
        if type(v) == "function" then
        elseif type(v) == "table" and type(d) == "table" and not isList(v) and not isList(d) then diff(v, d, p, out)
        elseif not same(v, d) then out[#out + 1] = { p, v } end
    end
    for k in pairs(def) do
        if cur[k] == nil then local p = { table.unpack(path) }; p[#p + 1] = k; out[#out + 1] = { p } end
    end
end
COOP.cfgDiff = diff                                        -- (the leaderboard's edited check too: LB.edited)
local function fill(into, from)                            -- `into` made to hold a copy of `from`, in place
    for k in pairs(into) do if from[k] == nil then into[k] = nil end end
    for k, v in pairs(from) do
        if type(v) == "table" then
            if type(into[k]) ~= "table" then into[k] = {} end
            fill(into[k], v)
        else into[k] = v end
    end
end
local function synced()
    local keys = {}
    for k in pairs(CFG_DEFAULTS or {}) do if not PERSONAL[k] then keys[k] = true end end
    for k in pairs(CFG) do if not PERSONAL[k] then keys[k] = true end end
    return keys
end
local function put(k, v)                                   -- CFG[k] = a copy of v, tables in place
    if type(v) == "table" and type(CFG[k]) == "table" then fill(CFG[k], v) else CFG[k] = deepCopy(v) end
end

-- (host) the settings to one joiner (to: its slot) or to every joiner (to: nil)
function M.sendSettings(to)
    if not CFG_DEFAULTS then return end
    local out = {}
    for k in pairs(synced()) do
        local v, d = CFG[k], CFG_DEFAULTS[k]
        if type(v) == "table" and type(d) == "table" and not isList(v) and not isList(d) then diff(v, d, { k }, out)
        elseif not same(v, d) then out[#out + 1] = { { k }, v } end
    end
    for _, s in ipairs(SHARED_IN) do                       -- (the host's part of a PERSONAL section)
        local v, d = at(CFG, s), at(CFG_DEFAULTS, s)
        if type(v) == "table" and type(d) == "table" then diff(v, d, { table.unpack(s) }, out) end
    end
    for i = #out, 1, -1 do if structural(out[i][1]) or ownPath(out[i][1]) then table.remove(out, i) end end
    local tk = {}
    local pname, pdiff = presetName()
    enc({ ver = VERSION, preset = pname, pdiff = pdiff, max = maxPlayers(), diff = out }, tk)
    local text = table.concat(tk, ",")
    local n = math.max(1, math.ceil(#text / CHUNK))
    for i = 1, n do sendTo(to, true, "cf", i, n, text:sub((i - 1) * CHUNK + 1, i * CHUNK)) end
    log(string.format("coop: the host's settings to %s: %d differ from the shipped ones (%d bytes)",
        to and ("player " .. (to + 1)) or "every joiner", #out, #text))
end

-- (joiner) a chunk of the host's settings; the last one applies them
function M.onSettings(f)
    local i, n = tonumber(f[2]), tonumber(f[3])
    if not (i and n and n == math.floor(n) and n >= 1 and n <= 400 and i == math.floor(i) and i >= 1 and i <= n) then return end
    if i == 1 then M.cfParts = {} end
    M.cfParts = M.cfParts or {}
    M.cfParts[i] = f[4] or ""
    if i ~= n then return end
    for j = 1, n do if not M.cfParts[j] then log("coop: the host's settings came incomplete; kept as they were"); M.cfParts = nil; return end end
    local tk = {}
    for t in (table.concat(M.cfParts, "", 1, n) .. ","):gmatch("([^,]*),") do tk[#tk + 1] = t end
    M.cfParts = nil
    local ok, s = pcall(dec, tk, 1, 0)
    if not ok or type(s) ~= "table" or type(s.diff) ~= "table" then log("coop: the host's settings could not be read: " .. tostring(s)); return end
    if not M.mine then                                    -- (your own, for when co-op closes or you host)
        M.mine, M.mineIn = {}, {}
        for k in pairs(synced()) do M.mine[k] = deepCopy(CFG[k]) end
        for _, sp in ipairs(SHARED_IN) do M.mineIn[pathStr(sp)] = deepCopy(at(CFG, sp)) end
    end
    for k in pairs(synced()) do put(k, CFG_DEFAULTS[k]) end
    for _, sp in ipairs(SHARED_IN) do                      -- (the shipped ones, but what's each player's own there)
        local cur, d = at(CFG, sp), at(CFG_DEFAULTS, sp)
        if type(cur) == "table" and type(d) == "table" then
            local keep = {}
            for k, v in pairs(cur) do
                local q = { table.unpack(sp) }
                q[#q + 1] = k
                if ownPath(q) then keep[k] = deepCopy(v) end
            end
            fill(cur, d)
            for k, v in pairs(keep) do if type(v) == "table" and type(cur[k]) == "table" then fill(cur[k], v) else cur[k] = v end end
        end
    end
    local names, skipped = {}, 0
    for i, e in ipairs(s.diff) do
        local p = type(e) == "table" and e[1]
        local ok = i <= 5000 and type(p) == "table" and #p >= 1 and #p <= 12 and (not PERSONAL[p[1]] or sharedPath(p))
            and not ownPath(p) and not structural(p)
        local d = ok and shipped(p)
        if not ok or d == nil or e[2] == nil or not fits(e[2], d) then
            skipped = skipped + 1
        else
            local t = CFG
            for j = 1, #p - 1 do
                if type(t[p[j]]) ~= "table" then t[p[j]] = {} end
                t = t[p[j]]
            end
            local last, v = p[#p], e[2]
            if type(v) == "table" and type(t[last]) == "table" then fill(t[last], v) else t[last] = v end
            if #names < 12 then local q = {}; for j = 1, #p do q[j] = tostring(p[j]) end; names[#names + 1] = table.concat(q, ".") end
        end
    end
    if skipped > 0 then log("coop: " .. skipped .. " of the host's settings skipped (this build has no such setting, or the value doesn't fit it)") end
    M.hostPreset = type(s.preset) == "string" and short(s.preset, 16) or nil
    M.hostDiff = math.tointeger(s.pdiff)
    local mx = math.tointeger(s.max)
    M.hostMax = mx and mx >= 2 and mx <= MAX_SLOT + 1 and mx or nil
    log(string.format("coop: playing with the host's settings (Survival %s, preset %s): %d differ from the shipped ones%s",
        tostring(s.ver), tostring(M.hostPreset), #s.diff, #names > 0 and (": " .. table.concat(names, ", ") .. (#s.diff > #names and ", ..." or "")) or ""))
end

-- your own settings back (co-op closed, or you host now)
function M.restoreMine()
    if not M.mine then return end
    for k in pairs(synced()) do put(k, M.mine[k]) end
    for _, sp in ipairs(SHARED_IN) do
        local cur, mine = at(CFG, sp), M.mineIn and M.mineIn[pathStr(sp)]
        if type(cur) == "table" and type(mine) == "table" then fill(cur, mine) end
    end
    M.mine, M.mineIn, M.hostPreset, M.hostDiff, M.hostMax = nil, nil, nil, nil, nil
    log("coop: your own settings are back")
end

-- (your own settings, for the menu's settings rows: the host's are in CFG while you play with them)
function M.ownRoot() return M.mine or CFG end

local rawPreset = presetName
presetName = function()
    local name, d = rawPreset()
    if COOP.client() and M.hostPreset then return M.hostPreset, M.hostDiff or d end
    return name, d
end
end

---------------------------------------------------------------------------------------------------- allies and defences
-- (sv_shop.lua shopBuy / shopBuildFor, sv_allies.lua) A joiner's STORE purchase of an allied flight or ship or an
-- airfield defence: "ab|<id>|<item>|<price>|<kind>" to the host, paid here at once; the host builds it in its game (its
-- spawn goes to every game as its enemies' do) and answers "ak|<id>|<message>" or "ax|<id>|<why>" (refunded), or
-- "ar|<price>|<why>" later (a flight that never took off: refunded). No answer in BUILD_WAIT_S: refunded.
local BUILD_WAIT_S, BUILD_PER_S = 30, 4
function COOP.askBuild(name, price, kind)
    if not COOP.client() then return false, "NOT IN CO-OP." end
    M.builds = M.builds or {}
    M.buildSeq = (M.buildSeq or 0) % 9999 + 1
    local id = M.buildSeq
    if not send(true, "ab", id, short(name, 32), string.format("%d", price), kind and short(kind, 16) or "") then
        return false, "NO LINK TO THE HOST."
    end
    M.builds[id] = { name = name, price = price, kind = kind, at = os.clock() }
    log(string.format("shop: asked the host to build %s (%d paid, kept until it answers)", name, price))
    return true, "ASKED THE HOST: IT BUILDS IT FOR EVERYONE."
end
local function buildDone(b, msg)
    if not (b and RUN) then return end
    RUN.msg[b.name], RUN.dirty = msg, true
    RUN.bought[b.name] = (RUN.bought[b.name] or 0) + 1
    if b.kind then
        RUN.defences = RUN.defences or { built = 0, bought = {} }
        RUN.defences.built = RUN.defences.built + 1
        RUN.defences.bought[b.kind] = (RUN.defences.bought[b.kind] or 0) + 1
    elseif LB and LB.stat then pcall(LB.stat, "allies", 1) end
end
local function refundHere(price, name, why)
    if not RUN or type(price) ~= "number" or price <= 0 then return end
    RUN.credits, RUN.spent, RUN.dirty = RUN.credits + price, math.max(0, RUN.spent - price), true
    if name then RUN.msg[name] = string.format("%s. %d REFUNDED.", why, price) end
    log(string.format("shop: %s: %s; %d refunded", tostring(name or "a purchase"), why, price))
end
function M.buildTick(now)
    for id, b in pairs(M.builds or {}) do
        if now - b.at >= BUILD_WAIT_S then
            M.builds[id] = nil
            refundHere(b.price, b.name, "NO ANSWER FROM THE HOST")
        end
    end
end
-- (the host) a joiner's purchase that can't come after all (an allied flight that never took off): their zollars back
function COOP.refund(slot, price, why)
    if not (COOP.host() and slotOk(slot) and slot ~= COOP.slot) then return false end
    return sendTo(slot, true, "ar", string.format("%d", math.floor(tonumber(price) or 0)), short(why, 60))
end
-- (the host) joiner `slot` airborne here: their plane in the mission, flying, not at their airfield, not down
function COOP.airborne(slot)
    local P = M.peers[slot]
    return P ~= nil and P.fresh == true and not P.onAirfield and not P.down
end
-- the allies' orders changed here (sv_allies.lua ALLY.nextOrder): a joiner's go to the host, the host's to everyone
function COOP.orderChanged(order, how)
    if not COOP.open or how == "coop" then return end
    if COOP.client() then send(true, "ao", short(order, 16)) elseif COOP.host() then send(true, "ag", short(order, 16)) end
end
function onBuildAsk(from, f)
    M.buildRate = M.buildRate or {}
    local now, r = os.clock(), M.buildRate[from]
    if not r or now - r.at >= 1 then r = { at = now, n = 0 }; M.buildRate[from] = r end
    r.n = r.n + 1
    if r.n > BUILD_PER_S then once("abrate" .. from, "shop: player " .. (from + 1) .. " asks for too many builds; dropped"); return end
    local id, name, price = tonumber(f[2]), short(f[3], 32), tonumber(f[4])
    local kind = (f[5] and f[5] ~= "") and short(f[5], 16) or nil
    if not (id and id == math.floor(id) and id >= 1 and id <= 9999) then return end
    local it = CFG.shop and CFG.shop.items and CFG.shop.items[name]
    if not (it and price and finite(price, CREDITS_MAX + 1) and price >= 0) then
        sendTo(from, true, "ax", id, "A BAD REQUEST"); return
    end
    local ok, msg = false, "NOT AVAILABLE RIGHT NOW."
    if type(shopBuildFor) == "function" then
        local okC, a, b = pcall(shopBuildFor, from, name, math.floor(price), kind, true)   -- ((0.73.78) true: a joiner's ask)
        if okC then ok, msg = a, b else msg = "THE HOST COULDN'T BUILD IT"; log("shop: build for player " .. (from + 1) .. ": " .. tostring(a)) end
    end
    log(string.format("shop: player %d's %s (%d): %s", from + 1, name, math.floor(price), ok and ("built: " .. tostring(msg)) or ("refused: " .. tostring(msg))))
    if ok then sendTo(from, true, "ak", id, short(msg, 80)) else sendTo(from, true, "ax", id, short(msg, 80)) end
end
function upperText(v, n) return (tostring(v or ""):gsub("[%c|]", ""):upper():sub(1, n)) end
function onBuildAnswer(f)
    local k, id = f[1], tonumber(f[2])
    if k == "ar" then
        local price = tonumber(f[2])
        if price and finite(price, CREDITS_MAX + 1) and price > 0 then refundHere(math.floor(price), nil, upperText(f[3], 60)) end
        return
    end
    local b = id and M.builds and M.builds[id]
    if not b then return end
    M.builds[id] = nil
    if k == "ak" then
        local msg = tostring(f[3] or ""):gsub("[%c|]", ""):sub(1, 80)
        buildDone(b, msg)
        log(string.format("shop: the host built your %s: %s", b.name, msg))
    else
        refundHere(b.price, b.name, "REFUSED: " .. upperText(f[3], 60))
    end
end
-- (a joiner) the host's allies summary in "rnd" (ALLY.roomCode: "m2w0s1") -> { m =, w =, s = } of what's in it, or nil
function roomAlliesOf(v)
    if type(v) ~= "string" or v == "" or #v > 12 or v:gsub("[mwvs]%d%d?", "") ~= "" then return nil end
    local t = {}
    for k, n in v:gmatch("([mwvs])(%d+)") do                 -- (each letter once: m MOONCHILD, w SNIPER, v VOID WATCHER 1, s ships)
        if t[k] then return nil end
        t[k] = tonumber(n)
    end
    return t
end
-- (a joiner, sv_allies.lua ALLY.hudLine) the room's allied flights and ships, from the host's last "rnd" (5 s at most
-- old), or nil: not a joiner, nothing bought, or no word
function COOP.roomAllies()
    if not COOP.client() then return nil end
    local r = M.rnd
    return (r and r.allies and os.clock() - (r.got or 0) <= 5) and r.allies or nil
end
-- (the host, sv_allies.lua's COVER) allied planes `objs` cover player `slot`, a joiner who bought them (the user's co-op
-- run of 2026-10-30: COVER kept a joiner's flight near the host, the stock order's NearPlayer being your plane): each
-- onto one of the enemy planes nearest that player's real plane (Normal / TargetFirst, as COOP.huntReal's), within 2x
-- CFG.allies.orders cover_radius_m of it, or 4x for the flights sent onto that plane (huntReal's), those counted at half
-- their distance. -> planes ordered (0: none of their attackers in reach, or no real plane), the nearest one's km
function COOP.coverFor(slot, objs)
    local me = realTarget(slot)
    if not (me and D and D.up) then return 0 end
    local okL, at = pcall(function() return me:K2_GetActorLocation() end)
    if not (okL and at) then return 0 end
    local reach = ((CFG.allies.orders.cover_radius_m or 5000) * 100) * 2
    local c = {}
    for unit in pairs(D.up) do
        local u = M.units[unit]
        local on = M.huntOn and M.huntOn[unit] and M.huntOn[unit].slot == slot
        for i = 1, (u and u.n or 0) do
            local pl = u.planes[i]
            local b = pl and not pl.dead and M.byId[pl.id]
            if b and valid(b.obj) then
                local ok, l = pcall(function() return b.obj:K2_GetActorLocation() end)
                if ok and l then
                    local d = math.sqrt((l.X - at.X) ^ 2 + (l.Y - at.Y) ^ 2 + (l.Z - at.Z) ^ 2)
                    if d <= (on and reach * 2 or reach) then c[#c + 1] = { obj = b.obj, k = on and d * 0.5 or d, d = d } end
                end
            end
        end
    end
    if #c == 0 then return 0 end
    table.sort(c, function(a, b) return a.k < b.k end)
    local n, nearest = 0, math.huge
    for _, e in ipairs(c) do nearest = math.min(nearest, e.d) end
    for i, o in ipairs(objs or {}) do
        local e = c[(i - 1) % #c + 1]
        if valid(o) and pcall(function() o:EngagementOrderOverride(ORDER_NORMAL, e.obj, PRIO_TARGET_FIRST, 0, false, FIRE_BITS, false) end) then
            n = n + 1
        end
    end
    return n, nearest / 100000
end
function onOrder(f, fromHost)
    local o = short(f[2], 16)
    local okL = false
    for _, x in ipairs(CFG.allies and CFG.allies.orders and CFG.allies.orders.list or {}) do if x == o then okL = true end end
    if not (okL and ALLY and ALLY.nextOrder) then return end
    if ALLY.order and ALLY.order() == o then return end
    pcall(ALLY.nextOrder, fromHost and "coop" or "a joiner", o)
end
end  -- (sv_coop.lua's do block goes on in sv_coop_migration.lua)
