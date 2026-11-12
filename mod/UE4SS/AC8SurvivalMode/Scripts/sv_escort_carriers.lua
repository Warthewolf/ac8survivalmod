-- sv_escort_carriers.lua: the ZFA-44 carriers (CFG.allies.carrier, the STORE's ZfaCarrier): the STORE's row, a carrier
-- sent, each ship's launches and service, a ship sunk or leaving, a joiner's own ZFA-44s; co-op's "es" (THE ESCORT's
-- state and the carriers' for the joiners); then every tick's, THE ESCORT's and the carriers': the names on the boxes,
-- the main menu's rows, ESC.tick, a restart and a level torn down. Piece 2 of 2 of sv_escort.lua (sv_escort.lua,
-- sv_escort_carriers.lua), split by tools/lua_split_part.py and run by main.lua right after the piece before it: a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local.
do  -- (sv_escort.lua's do block, continued: this piece's own helpers stay local to it)

---------------------------------------------------------------------------------------------------- the carriers
function ESC.unlocked() return type(RUN.zfa) == "table" and RUN.zfa.unlocked == true end
local function run()
    if not (ESC.R and ESC.R.D == D) then ESC.R = { D = D, carriers = {} } end
    return ESC.R
end
function ESC.carriersUp()
    if client() then return math.floor(num(ESC.host and ESC.host.carriers, 0)) end
    local n = 0
    for _, C in pairs(run().carriers) do if C.state == "up" then n = n + 1 end end
    return n
end
local function carrierUnitsOk()
    local ok = false
    for _, u in ipairs(cc().units or {}) do if aliveOf(u) ~= -2 then ok = true end end
    return ok
end
-- a free ship: its index and unit (none of it up), or nil
local function freeShip()
    local R = run()
    for i, u in ipairs(cc().units or {}) do
        if not R.carriers[i] then
            local n = aliveOf(u)
            if n == 0 or n == -7 then return i, u end
        end
    end
    return nil
end
-- (sv_shop.lua offer) what the STORE's row says: { label, help, why }
function ESC.offer(borrowed)
    local c, t = cc(), cc().text
    local it = CFG.shop.items.ZfaCarrier or {}
    local up = ESC.carriersUp()
    local o = { label = borrowed and (it.row_label or it.label) or it.label }
    o.help = string.format(t.help, math.floor(num(c.service and c.service.rounds, 3)), up, math.floor(num(c.max_up, 2)))
    if borrowed and RUN.msg and RUN.msg.ZfaCarrier then o.help = RUN.msg.ZfaCarrier .. " " .. o.help end
    if not (c.enabled and CFG.allies.enabled) or (c.dt_npc and ESC.zfaRowOk ~= true) then o.why = "NOT AVAILABLE."
    elseif not ESC.unlocked() then o.why = t.locked
    elseif not client() and not carrierUnitsOk() then o.why = "NOT AVAILABLE."
    elseif up >= num(c.max_up, 2) then o.why = string.format(t.full, up)
    elseif not client() and not freeShip() then o.why = t.busy end
    return o
end
-- (sv_shop.lua offer) a STORE row the carrier shares while it has nothing to sell itself: the carrier's item, or nil
function ESC.rowItem(name)
    local c = cc()
    if not (c.enabled and name ~= nil and name == c.store_row and ESC.unlocked()) then return nil end
    if name == "Revive" and DOWN and DOWN.offer then
        local okD, r = pcall(DOWN.offer)
        if okD and type(r) == "table" and (r.price or r.slot) then return nil end   -- (someone to revive: the row's own)
    end
    return "ZfaCarrier"
end
-- (the host's or solo; sv_shop.lua shopBuy / shopBuildFor) one sent: true and the row's message, or false and why.
-- slot: a co-op joiner's who paid on their game (nil: this game's, or a host by migration's rebuild)
function ESC.buyCarrier(slot, price)
    local c, t = cc(), cc().text
    if client() then return false, "THE HOST SENDS IT." end
    if c.dt_npc and ESC.zfaRowOk ~= true then return false, "NOT AVAILABLE." end
    if not ESC.unlocked() then return false, t.locked end
    if ESC.carriersUp() >= num(c.max_up, 2) then return false, string.format(t.full, ESC.carriersUp()) end
    local i, u = freeShip()
    if not i then return false, t.busy end
    spawningUnit = u
    local okS, r = pcall(SV_Spawn, u)
    spawningUnit = nil
    if not okS then r = -5 end
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, u, r) end
    if r <= 0 then
        log(string.format("carrier: %s (%s) NOT sent: %s", c.name, u, ERR(r)))
        return false, "COULD NOT SEND IT (" .. ERR(r) .. ")."
    end
    local now = now0()
    run().carriers[i] = { idx = i, unit = u, at = now, buyer = slot, price = price, served = 0, state = "up", armI = 0,
                          route = c.launch == "pose" and "pose" or "container", used = {},
                          nextLaunchAt = now + num(c.first_s, 20), name = string.format("%s %d", c.name, i) }
    RUN.dirty = true
    if not slot then hudCallout(string.format(t.on_station, c.name), string.format(t.on_station_sub, math.floor(num(c.first_s, 20)))) end
    log(string.format("carrier: %s %d (%s) on station%s: its ZFA-44s launch in %d s (%s)", c.name, i, u,
        slot and string.format(" for player %d", slot + 1) or "", math.floor(num(c.first_s, 20)), c.launch == "pose" and "by pose" or "from its container launchers"))
    return true, string.format("%s %d ON STATION", c.name, i)
end
-- the carriers up as the host's migration list has them: { "ZfaCarrier:<buyer slot or ->" }
function ESC.carrierList()
    local out = {}
    if client() then return out end
    for _, C in pairs(run().carriers) do if C.state == "up" then out[#out + 1] = C.buyer or false end end
    return out
end
local function hullPose(C)
    local h = ESC.hulls[C.unit]
    if h and liveAddr(h.obj) == h.addr then
        local ok, l, ro = pcall(function() return h.obj:K2_GetActorLocation(), h.obj:K2_GetActorRotation() end)
        if ok and l and ro then return { X = l.X, Y = l.Y, Z = l.Z }, ro.Yaw end
    end
    local sp = (cc().ship_at or {})[C.idx]
    if not sp then return nil end
    local at = { X = sp[1], Y = sp[2], Z = 0 }
    return at, (bearing(at, AIRFIELD) - 90) % 360
end
ESC.hullPose = hullPose                                  -- (the launch watch: sv_escort_laser.lua ZLAUNCH)
local function launch(C, now)
    local c = cc()
    local arms = (c.launchers or {})[C.idx] or {}
    if C.route == "container" and #arms > 0 then
        -- ((2026-11-07, the user: "ZFA-44's did not launch from the Cargo Ships": in War's co-op game every try read each
        -- arm's unit alive and logged "every launcher arm's flight is still up", 322 times, and none launched. A ship comes
        -- with planes of its arms' units of its own, near it from its first second, that this carrier never launched.)
        -- The next arm in turn: its unit on the spawner's list with nothing up taken off it first, as any flight's (hard
        -- rule 16). ((2026-11-07, the user's test of 0.74.9: AC8 crashed at 21:14:08 the moment an arm's unit with 2 planes
        -- up, the ship's own, was taken off by force and its arm fired) never with planes up: the arm fired as it is, its
        -- record's orders reaching the planes there; only planes that weren't up before count as its launch (F.before),
        -- and none in launch_wait_s: by pose (below).
        local okP, jP = pcall(function() return ZLAUNCH.pickArm(C, arms) end)   -- ((0.74.25) an arm whose last flight isn't up
        C.armI = (okP and type(jP) == "number") and jP or (C.armI % #arms + 1)
        local arm = arms[C.armI]
        local n = aliveOf(arm.unit)
        if n == 0 and type(SV_Recycle) == "function" then
            crumb("carrier SV_Recycle " .. arm.unit)
            local okR, rr = pcall(SV_Recycle, arm.unit, 1)
            log(string.format("carrier: %s: %s launched before, nothing of it up: taken off the spawner's list first (SV_Recycle %s)",
                C.name, arm.unit, okR and tostring(rr) or ("error " .. tostring(rr))))
        elseif n > 0 then
            log(string.format("carrier: %s: %s has %d up that this carrier never launched (the ship's own): fired as it is, "
                .. "never taken off with planes up", C.name, arm.unit, n))
        end
        C.used[arm.unit] = true
        local ok, r = fire(arm.record, C.name)
        if ok then
            C.flight = { unit = arm.unit, record = arm.record, at = now, route = "container", before = math.max(0, n) }
            C.launches = (C.launches or 0) + 1
            if C.launches == 1 then hudCallout(c.text.launch, string.format(c.text.launch_sub, C.name)) end
            log(string.format("carrier: %s launches its ZFA-44s: %s fired (container arm %d, %s)", C.name, arm.record, C.armI, arm.unit))
            return
        end
        C.route = "pose"
        log(string.format("carrier: %s: its launch record %s not fired (%s): launched by pose from now on", C.name, arm.record, ERR(r)))
    end
    local u = (c.pose_units or {})[C.idx]
    local at, yaw = hullPose(C)
    if not (u and at) then C.nextLaunchAt = now + 10; return end
    local y = math.rad(yaw)
    local ahead = num(c.pose and c.pose.ahead_m, 300) * 100
    local pose = { x = at.X + math.cos(y) * ahead, y = at.Y + math.sin(y) * ahead, z = math.max(at.Z, 0) + num(c.pose and c.pose.alt_m, 1100) * 100, yaw = yaw % 360 }
    if type(SV_SetLevel) == "function" and ALLY.level then
        local okL, L = pcall(ALLY.level, nil)
        if okL and L then pcall(SV_SetLevel, u, L.ai * 100) end
    end
    ESC.planes[u] = {}                                    -- (a new spawn: the unit's planes before it are another flight's)
    spawningUnit, spawningIdx = u, nil
    local okS, r = pcall(SV_Spawn, u, pose.x, pose.y, pose.z, pose.yaw)
    spawningUnit = nil
    if not okS then r = -5 end
    if ALIVE and ALIVE.spawned then pcall(ALIVE.spawned, u, r) end
    if r > 0 then
        C.flight = { unit = u, at = now, route = "pose", up = true }
        C.launches = (C.launches or 0) + 1
        if C.launches == 1 then hudCallout(c.text.launch, string.format(c.text.launch_sub, C.name)) end
        -- (its orders: gear up, Normal, air search; its appearance's records too, which a spawn in the landing menu never fires)
        local go = (c.pose_go or {})[C.idx]
        local goOk = go and fire(go, C.name)
        log(string.format("carrier: %s launches its ZFA-44s by pose: %s, %d aircraft %.0f m off its bow, %.0f m up%s", C.name, u, r,
            ahead / 100, pose.z / 100, go and string.format("; %s %s", go, goOk and "fired" or "NOT fired") or ""))
    else
        C.nextLaunchAt = now + 10
        log(string.format("carrier: %s: %s NOT spawned (%s); again in 10 s", C.name, u, ERR(r)))
    end
end
-- ((2026-11-11) switched off, they still counted up) a flight's planes finished off (ZLAUNCH.finish), its unit off the list
local function flightOff(F, why)
    if COOP and COOP.removeNow then pcall(COOP.removeNow, F.unit) end
    local n, off = ZLAUNCH.finishAll(planesOf(F.unit), why)
    ESC.recycleQ[#ESC.recycleQ + 1] = { unit = F.unit, at = os.clock() + 2, why = why }
    if n + off > 0 then log(string.format("carrier: %s: its flight %s: %d ZFA-44s finished off, %d switched off", tostring(why), F.unit, n, off)) end
    return n + off
end
-- ((2026-11-11) a sunk one's flight flew on) a ship sunk or leaving: its parked ZFA-44s, its flying ones' dive or end
local function shipDone(C, why)
    if ZLAUNCH and ZLAUNCH.parkedOff then pcall(ZLAUNCH.parkedOff, C.idx, C.flight and C.flight.unit, why) end
    return (ZDIVE and ZDIVE.take and ZDIVE.take(C)) or (C.flight and flightOff(C.flight, why)) or 0
end
-- ((code review of 2026-11-07, finding 7) a carrier's hull down: why (its hull at 0 health, or gone since it was seen
-- live), or nil. Its unit's alive count holds its launchers and Stinger mount too, so a ship whose hull sank stayed "up"
-- while they lived: its slot and the STORE's count held, and it served on)
local function hullSunk(C)
    local h = ESC.hulls[C.unit]
    if not h then return nil end
    if liveAddr(h.obj) == h.addr then
        C.hullSeen = true
        local v = hp(h.obj)
        if v and v <= 0 then return "its hull at 0 health" end
        return nil
    end
    if C.hullSeen then return "its hull gone" end
    return nil
end
-- an object of ours finished off here (an allied ship's part: unpaid on every game, no killer): whether it went
local function finishObj(o)
    if not liveObj(o) then return false end
    local h = hp(o)
    if not (h and h > 0) then return false end
    pcall(function() o.bIsInvincible = false end)
    pcall(function() o.MinHealth = 0.0 end)
    pcall(function() o:ModifyHealth(-(h / 10 + 1000), nil, true) end)
    return true
end
local function carrierTick(C, now)
    local c, t = cc(), cc().text
    local R = run()
    if C.state == "leaving" then
        if os.clock() >= (C.removeAt or 0) + 2 then
            if ZLAUNCH and ZLAUNCH.holdHull(C.idx, C, C.name, C.why) then C.removeAt = os.clock() + 3; return end   -- (0.74.48)
            local rec = "no SV_Recycle in this runtime"
            if type(SV_Recycle) == "function" then
                crumb("carrier SV_Recycle " .. C.unit)
                local okR, r = pcall(SV_Recycle, C.unit, 1)
                rec = "SV_Recycle " .. (okR and tostring(r) or ("error " .. tostring(r)))
            end
            R.carriers[C.idx], RUN.dirty = nil, true
            -- ((code review of 2026-11-07) its hull and objects forgotten with its slot: the next ship of this unit's
            -- are recorded afresh, never this one's switched-off or sunk hull read in their place)
            ESC.hulls[C.unit] = nil
            if ESC.shipObjs then ESC.shipObjs[C.unit] = nil end
            log(string.format("carrier: %s gone (%s): off the spawner's list (%s); the STORE can call another", C.name, tostring(C.why), rec))
        end
        return
    end
    if now >= (C.checkAt or 0) then
        C.checkAt = now + 2
        local hs = hullSunk(C)
        if hs then
            -- (its hull down: sunk, whatever its launchers and Stinger mount still count; what's left of it finished off
            -- here, unpaid, and its slot held until its unit is off the spawner's list, as a ship leaving: a ship bought
            -- meanwhile can't be taken off by this one's recycle)
            local nP = 0
            for _, e in ipairs((ESC.shipObjs or {})[C.unit] or {}) do
                if liveAddr(e.obj) == e.addr and finishObj(e.obj) then nP = nP + 1 end
            end
            C.state, C.removeAt, C.why = "leaving", os.clock() + 1, "sunk: " .. hs
            local nf = shipDone(C, C.name .. " sunk")
            RUN.dirty = true
            hudCallout(string.format(t.sunk, C.name), t.sunk_sub)
            log(string.format("carrier: %s sunk %.0f s after it came (%s; %d rounds served): %d of its parts still up finished off, "
                .. "its unit off the list 3 s on; %d ZFA-44s of its flight kept for their dive or finished off", C.name, now - C.at, hs, C.served, nP, nf))
            return
        end
        if noneUp(aliveOf(C.unit)) and now - C.at > 5 then
            R.carriers[C.idx], RUN.dirty = nil, true
            ESC.hulls[C.unit] = nil
            if ESC.shipObjs then ESC.shipObjs[C.unit] = nil end
            local nf = shipDone(C, C.name .. " sunk")
            hudCallout(string.format(t.sunk, C.name), t.sunk_sub)
            log(string.format("carrier: %s sunk %.0f s after it came (%d rounds served); %d ZFA-44s of its flight kept for their dive or finished off",
                C.name, now - C.at, C.served, nf))
            return
        end
    end
    -- its rounds of service (VOID WATCHER 1's): one counted as it clears with the ship up min_s of it
    local sv = c.service or {}
    local rounds = math.floor(num(sv.rounds, 3))
    if rounds > 0 and D then
        if D.state ~= "wait" then C.inRound = D.round
        elseif C.inRound == D.round and C.counted ~= D.round then
            C.counted = D.round
            if now - C.at >= num(sv.min_s, 60) then
                C.served = C.served + 1
                log(string.format("carrier: %s has served %d of its %d rounds (round %d clear)", C.name, C.served, rounds, D.round))
            else
                log(string.format("carrier: %s up only %d s of round %d: not counted", C.name, math.floor(now - C.at), D.round))
            end
        end
        if C.served >= rounds and D.state == "wait" then
            C.state, C.removeAt, C.why = "leaving", os.clock(), string.format("%d rounds served", C.served)
            local nf = shipDone(C, C.name .. " leaving")         -- (its dive: sv_escort_dive.lua)
            if COOP and COOP.removeNow then pcall(COOP.removeNow, C.unit) end
            if c.remove_records then fire(string.format("RE_SV_CargoRemove_%d", C.idx), C.name) end
            local n = 0
            for _, e in ipairs((ESC.shipObjs or {})[C.unit] or {}) do if liveAddr(e.obj) == e.addr and offObj(e.obj) then n = n + 1 end end
            RUN.dirty = true
            hudCallout(string.format(t.leaving, C.name), string.format(t.leaving_sub, C.served))
            log(string.format("carrier: %s leaving after %d rounds: %d of its objects switched off, %d ZFA-44s kept for their dive or finished off", C.name, C.served, n, nf))
            return
        end
    end
    -- its flight: launched, seen, down, launched again
    local F = C.flight
    if F then
        if not F.up then                                 -- (planes up before it fired aren't its launch: F.before)
            if (ZLAUNCH and ZLAUNCH.risen(C, F, now)) or #planesOf(F.unit, F.at - 1) > 0 or aliveOf(F.unit) > (F.before or 0) then
                F.up = true
                log(string.format("carrier: %s's ZFA-44s are up (%s, %d planes seen)", C.name, F.unit, #planesOf(F.unit, F.at - 1)))
            elseif now - F.at >= num(c.launch_wait_s, 10) and not (ZLAUNCH and ZLAUNCH.late(C, F, now)) then
                log(string.format("carrier: %s: %s fired %.0f s ago and no plane of %s came: launched by pose from now on", C.name,
                    tostring(F.record), now - F.at, F.unit))
                C.route, C.flight, C.nextLaunchAt = "pose", nil, now
            end
        elseif now >= (F.checkAt or 0) then
            F.checkAt = now + 2
            local live = 0
            for _, e in ipairs(planesOf(F.unit, F.at - 1)) do if (hp(e.obj) or 1) > 0 then live = live + 1 end end
            if live == 0 and noneUp(aliveOf(F.unit)) and now - F.at > 15 then
                C.flight, C.nextLaunchAt = nil, now + num(c.relaunch_s, 30)
                ESC.recycleQ[#ESC.recycleQ + 1] = { unit = F.unit, at = os.clock() + 2, why = C.name .. "'s flight down" }
                log(string.format("carrier: %s's ZFA-44 flight %s is down: another in %d s", C.name, F.unit, math.floor(num(c.relaunch_s, 30))))
            end
        end
    elseif now >= (C.nextLaunchAt or 0) then
        launch(C, now)
    end
end

---------------------------------------------------------------------------------------------------- co-op
-- ((code review of 2026-11-07, finding 1) The host's carrier launches (RE_SV_CargoLaunch_<s>_<n>) are forwarded, so each
-- joiner's copy of the ship launches ZFA-44s of its own from its own launchers: planes of no co-op id, never bound as
-- copies (the launcher spawns them, not a mirrored SV_Spawn). They stay for the look, and their fight isn't anyone's:
-- sv_coop.lua takes them as the host's allies' copies (M.standInSet: their damage on an enemy copy never sent as this
-- player's hit), each launch here takes the arm's unit off this game's list first (hard rule 16: from a ship's 7th
-- launch its arm spawned nothing here) and the last flight of that ship off, and a carrier the host no longer has
-- (left or sunk: "es" field 10, the ships up as bits) takes this game's own ZFA-44s of it off.
local function bitOn(m, i) return math.floor((tonumber(m) or 0) / 2 ^ (i - 1)) % 2 == 1 end
local function carrierMask()
    local m = 0
    if client() then return m end
    for i, C in pairs(run().carriers) do if C.state == "up" then m = m + math.floor(2 ^ (i - 1)) end end
    return m
end
ESC.carrierMask = carrierMask
-- every plane of the carriers' ZFA-44 flights here, by address (the stand-in set's: their hits are nobody's on a joiner)
function ESC.localZfa()
    local set = {}
    for u in pairs(ESC.planes) do
        if KIND[u] == "zfa" then for _, e in ipairs(planesOf(u)) do set[e.addr] = true end end
    end
    local R = ALLY and ALLY.run
    for _, p in ipairs((R and R.planes) or {}) do
        if p.unit and KIND[p.unit] == "zfa" then
            local a = liveAddr(p.obj)
            if a then set[a] = true end
        end
    end
    return set
end
-- (a joiner) this game's own ZFA-44s of ship i finished off, unpaid (not a bound copy of the host's pose flight: the host's
-- "dn"); captured before `before` (nil: all; flying: not a parked one, its launch to come); how many, how many down.
-- ((2026-11-11) Delta's log: switched off only, his 24 stayed up) one that can't be is switched off, kept for offKill
local function ownZfaOff(i, before, why, flying)
    local n, dead, parkZ = 0, 0, num(cc().parked_m, -100) * 100
    for u, l in pairs(ESC.planes) do
        if KIND[u] == "zfa" and ZFA_I[u] == i then
            for k = #l, 1, -1 do
                local e = l[k]
                local z = flying and locOf(e.obj)
                if not e.dead and entryLive(e) and (before == nil or (e.at or 0) < before) and not (z and z.Z < parkZ)
                    and not (COOP and COOP.copyAt and COOP.copyAt(e.addr)) then
                    local ok, _, how = ZLAUNCH.finish(e, why, true)
                    table.remove(l, k)          -- (kept for ZLAUNCH.offKill: (2026-11-11) a hull the host spawns again waits on them)
                    if how ~= "not its plane" then
                        n, dead = n + 1, dead + (ok and 1 or 0)
                        ESC.offZfa = ESC.offZfa or {}; ESC.offZfa[i] = ESC.offZfa[i] or {}
                        if not ok and #ESC.offZfa[i] < 64 then table.insert(ESC.offZfa[i], e) end
                    end
                end
            end
        end
    end
    return n, dead
end
-- (a joiner) a carrier of the host's gone (left or sunk): this game's own ZFA-44s of it off, its arms' units off this
-- game's spawner list 2 s on (one at a time: recycleTick)
function ESC.localOff(i, why)
    if not client() then return 0 end
    if ZLAUNCH and ZLAUNCH.parkedOff then pcall(ZLAUNCH.parkedOff, i, nil, "the host's carrier " .. i .. " gone here") end
    local n = ZDIVE and ZDIVE.holdLocal and ZDIVE.holdLocal(i)      -- (kept for the host's final dive: sv_escort_dive.lua)
    local dead; if not n then n, dead = ownZfaOff(i, nil, "the host's carrier " .. i .. " gone") end
    local q = 0
    for _, arm in ipairs((cc().launchers or {})[i] or {}) do
        if type(arm.unit) == "string" and aliveOf(arm.unit) == 0 then   -- ((2026-11-07) nothing up only)
            ESC.recycleQ[#ESC.recycleQ + 1] = { unit = arm.unit, at = os.clock() + 2, why = tostring(why) }
            q = q + 1
        end
    end
    if n > 0 or q > 0 then
        log(string.format("carrier: the host's %s %d is gone (%s): %d of this game's own ZFA-44s of it %s, %d of its arms' units off the list once none is up",
            cc().name, i, tostring(why), n, dead and string.format("finished off (%d down, the rest switched off)", dead) or "kept for the host's dive", q))
    end
    return n
end
-- (a joiner, sv_coop.lua hostEvent: before one of the host's events fires here) a carrier launch: the arm's unit off this
-- game's spawner list first (force: its planes here may still count), and this ship's last flight here switched off
-- (the host launches only once its last flight is down there)
function ESC.beforeHostEvent(name)
    if not client() then return nil end
    local s, a = tostring(name):match("^RE_SV_CargoLaunch_(%d+)_(%d+)$")
    s, a = tonumber(s), tonumber(a)
    local arms = s and (cc().launchers or {})[s]
    local arm = arms and arms[a]
    if not (arm and type(arm.unit) == "string" and arm.record == name) then return nil end
    if ZLAUNCH and ZLAUNCH.offKill then pcall(ZLAUNCH.offKill, s, name .. " here") end   -- ((2026-11-11) never left up)
    local nOff, nDead = ownZfaOff(s, now0() + 0.001, name .. ": this ship's last flight here", true)
    local n0, rec = aliveOf(arm.unit), "not on the list"
    if n0 == 0 and type(SV_Recycle) == "function" then
        crumb("carrier (joiner) SV_Recycle " .. arm.unit)
        local okR, r = pcall(SV_Recycle, arm.unit, 1)
        rec = string.format("nothing up, SV_Recycle %s", okR and tostring(r) or ("error " .. tostring(r)))
    elseif n0 > 0 then                                    -- ((2026-11-07) as the host's launch(): never with planes up)
        rec = string.format("%d up: left as they are, never taken off with planes up", n0)
    end
    log(string.format("carrier: the host's %s here: %s first (%s); %d of this game's ZFA-44s of ship %d before it finished off (%d down)",
        name, arm.unit, rec, nOff, s, nDead))
    return arm.unit
end
-- (the host) "es|<state>|<landed>|<of>|<her health %>|<km>|<unlocked>|<carriers out>|<landing closed>|<ships up, bits>",
-- on a change (once a second at most) and every 5 s
local function sendState(now)
    if not (COOP and COOP.host and COOP.host() and COOP.msg) then return end
    if now < (ESC.esAt or 0) then return end
    ESC.esAt = now + 1
    local S = ESC.S
    local st, l, n, h, dist, cl = "", 0, 0, -1, 0, 0
    if S and S.D == D and not S.test then
        local lostN
        st = S.state
        l, lostN, n = counts(S)
        h = hpPct(S) or -1
        dist = her(S).r and d2(her(S).r.at, AIRFIELD) / 1000 or 0
        cl = S.closed and 1 or 0
    end
    local mask = carrierMask()
    local key = table.concat({ st, l, n, ESC.unlocked() and 1 or 0, ESC.carriersUp(), cl, mask }, "|")
    if key == ESC.esKey and now < (ESC.esAgain or 0) then return end
    if key ~= ESC.esKey then log("escort: the escort's state sent to the joiners: " .. key) end
    ESC.esKey, ESC.esAgain = key, now + 5
    COOP.msg(nil, "es", st, string.format("%d", l), string.format("%d", n), string.format("%d", h), string.format("%.1f", dist),
        ESC.unlocked() and "1" or "0", string.format("%d", ESC.carriersUp()), string.format("%d", cl), string.format("%d", mask))
end
-- (a joiner, sv_coop.lua onJoinerMessage) the host's "es": kept for the NEXT row and the STORE; the unlock is the room's
function ESC.onHost(f)
    local st = tostring(f[2] or ""):match("^%a*$") or ""
    local function n(i, lo, hi) local v = tonumber(f[i]); if not v or v ~= v then return nil end return math.max(lo, math.min(hi, v)) end
    local function w(i, lo, hi, d) return math.floor(n(i, lo, hi) or d) end   -- (whole: the rows format them with %d)
    local mk = n(10, 0, 255)                              -- (the ships up, bit i - 1 ship i; nil from an older host)
    local h = { state = #st <= 16 and st or "", landed = w(3, 0, 99, 0), total = w(4, 0, 99, 0), hp = w(5, -1, 100, -1),
                km = n(6, 0, 999) or 0, unlocked = f[7] == "1", carriers = w(8, 0, 9, 0), close = f[9] == "1", got = os.clock(),
                mask = mk and math.floor(mk) or nil }
    local was = ESC.host
    ESC.host = h
    -- ((code review of 2026-11-07, finding 1) a carrier the host had and has no more: this game's own ZFA-44s of it off)
    local ships = #(cc().units or {})
    if was and was.mask and h.mask then
        for i = 1, ships do
            if bitOn(was.mask, i) and not bitOn(h.mask, i) then ESC.localOff(i, "left or sunk on the host's game") end
        end
    elseif was and not h.mask and was.carriers > 0 and h.carriers == 0 then   -- (an older host: none out any more)
        for i = 1, ships do ESC.localOff(i, "the host has no carrier out") end
    end
    if h.unlocked and not ESC.unlocked() then
        RUN.zfa = { unlocked = true, room = true }
        RUN.dirty = true
        log("escort: the host's escort was won: the ZFA-44 carriers are in the STORE here too (the room's)")
    end
    if not was or was.carriers ~= h.carriers then RUN.dirty = true end
    if h.close ~= (ESC.clientClosed == true) then
        if h.close then
            if not (AF and (AF.closed or AF.down)) then ESC.clientClosed = airfield(true, "the host's CHARLENE landing") end
        else
            if ESC.clientClosed and not (AF and (AF.closed or AF.down)) and not RUN.captured then airfield(false, "the host's escort") end
            ESC.clientClosed = false
        end
    end
end
-- (a joiner, sv_hud.lua) the host's escort's NEXT row, while it's on there (10 s fresh)
function ESC.clientRow(t)
    local h = ESC.host
    if not (client() and h and os.clock() - h.got <= 10 and (h.state == "route" or h.state == "landing")) then return nil end
    local tx = ec().text
    if h.state == "route" then return string.format(tx.row, h.hp >= 0 and h.hp or 100, h.km, h.landed, h.total) end
    return string.format(tx.row_landing, h.landed, h.total)
end
-- (sv_allies.lua's ALLIES row, wrapped) the carriers out
do
    local rawLine = ALLY.hudLine
    if type(rawLine) == "function" then
        ALLY.hudLine = function(...)
            local s, news = rawLine(...)
            local okN, n = pcall(ESC.carriersUp)
            if okN and n and n > 0 then
                s = (s and (s .. "   ") or "") .. string.format("VAMPIRES %d", n)
                news = (news and (news .. " ") or "") .. "VAMPIRES"
            end
            return s, news
        end
    end
end

---------------------------------------------------------------------------------------------------- every tick
-- the names on their boxes (once a session, as the allies' at the main menu: sv_allies.lua ALLY.setup)
local function names()
    if ESC.namesSet or type(SV_SetText) ~= "function" then return end
    ESC.namesSet = true
    local c, k, n = ec(), cc(), 0
    -- ((2026-11-07) the user: CHARLENE and her escorts "should each have a squadron tag KMG": c.tag in c.tag_format)
    local tag = type(c.tag) == "string" and c.tag ~= "" and c.tag or nil
    local function tagged(nm) return (tag and type(nm) == "string") and string.format(c.tag_format or "[%s] %s", tag, nm) or nm end
    local list = { { c.name_key, tagged(c.name) } }
    for _, e in ipairs(c.escorts or {}) do list[#list + 1] = { e.name_key, tagged(e.name) } end
    list[#list + 1] = { k.name_key, k.name }
    list[#list + 1] = { k.zfa and k.zfa.name_key, k.zfa and k.zfa.name }
    list[#list + 1] = { k.zfa and k.zfa.sub_key, k.zfa and k.zfa.sub }   -- ((2026-11-07) its box's second line)
    for _, x in ipairs(list) do
        if type(x[1]) == "string" and type(x[2]) == "string" and SV_SetText(x[1], x[2]) == 1 then n = n + 1 end
    end
    log(string.format("escort: %d of %d name texts set (CHARLENE, her escorts, the carriers, the ZFA-44)", n, #list))
end
-- (the main menu, sv_main.lua's setup pass; every game) the escorts' and the ZFA-44 host's DT_NPC rows into the game's
-- DT_NPC from DT_SV_NpcRows (before the level loads: a unit's behaviour is built from its row then, hard rule 20, and a
-- unit whose row the game hasn't doesn't spawn), and the names on their boxes, as the shoal's (sv_fishing.lua
-- FISH.setup). ESC.rowsOk: the escorts' rows in (else no ESCORT round); ESC.zfaRowOk: the ZFA-44's (else no carrier)
function ESC.setup()
    if ESC.setupDone or not gameInstance() then return end
    ESC.setupTries = (ESC.setupTries or 0) + 1
    local npc, mine = loadObject(PROBE_TABLES[2].path), loadObject(CFG.specials.shuttle.npc_rows)
    if not (npc and mine) then
        if ESC.setupTries >= 20 then
            ESC.setupDone, ESC.rowsOk, ESC.zfaRowOk = true, false, false
            log("escort: the row tables didn't load: no ESCORT round and no ZFA-44 carriers this session")
        end
        return
    end
    ESC.setupDone = true
    for _, t in ipairs({ npc, mine }) do pin(t, nameOf(t)) end
    local function addRow(row)
        local _, have = dtCall(npc, "FindRow", row)
        if have == nil then
            local _, r = dtCall(mine, "FindRow", row)
            if r ~= nil then dtCall(npc, "AddRow", row, r); _, have = dtCall(npc, "FindRow", row) end
        end
        return have ~= nil
    end
    local parts, ok = {}, true
    for _, row in ipairs(ec().dt_npc or {}) do
        local got = addRow(row)
        ok = ok and got
        parts[#parts + 1] = row .. (got and " in DT_NPC" or " NOT added")
    end
    ESC.rowsOk = ok
    local zr, okZ, zIn, zNote = cc().dt_npc, false, nil, ""      -- ((2026-11-07) its laser twin or it: sv_escort_laser.lua)
    if type(zr) == "string" and ZLAS and ZLAS.zfaRow then okZ, zIn, zNote = pcall(ZLAS.zfaRow, npc, mine, addRow, zr) end
    if okZ then ESC.zfaRowOk = zIn else ESC.zfaRowOk, zNote = type(zr) ~= "string" or addRow(zr), zIn and (" (laser error: " .. tostring(zIn) .. ")") end
    if type(zr) == "string" then parts[#parts + 1] = zr .. (ESC.zfaRowOk and " in DT_NPC" or " NOT added") .. (zNote or "") end
    log(string.format("escort: the escorts' and the ZFA-44's rows: %s%s%s", table.concat(parts, ", "),
        ok and "" or "; no ESCORT round this session", ESC.zfaRowOk and "" or "; no ZFA-44 carriers this session"))
    names()
end
-- ((2026-11-07) at most per_tick a tick (was 2), each only once it's settle_s old, and not while a level comes or goes)
local function dressTick()
    local q = ESC.dressQ
    if #q == 0 then return end
    if (levelTorn and levelTorn()) or (walkHold and walkHold()) then return end
    local z = cc().zfa or {}
    local done, per = 0, math.max(1, math.floor(num(z.per_tick, 1)))
    while #q > 0 and done < per do
        if (q[1].due or 0) > os.clock() then return end
        local e = table.remove(q, 1)
        if liveAddr(e.obj) == e.addr then
            done = done + 1
            if ZLAS and ZLAS.arms then pcall(ZLAS.arms, e.obj, e.unit) end      -- (its fire control, once: sv_escort_laser.lua)
            if z.dress ~= false and ZFA and ZFA.dress then
                local okD, did, why = pcall(ZFA.dress, e.obj, { paint = z.paint, label = e.unit, hide_s = z.hide_s })
                if not okD then logOnce("zfa dress", "carrier: ZFA-44 dressing error " .. tostring(did)) end
                ESC.dressedN = (ESC.dressedN or 0) + ((okD and did) and 1 or 0)
                if not (okD and did) and not ESC.dressSaid then ESC.dressSaid = true; log("carrier: a ZFA-44 not dressed: " .. tostring(why)) end
            elseif not ESC.noDressSaid then
                ESC.noDressSaid = true
                log("carrier: no ZFA-44 dressing in this build (sv_zfa44.lua cut: no ZFA-44 container): its planes fly as their host airframe")
            end
        end
    end
end
local function recycleTick()
    local q = ESC.recycleQ
    for i = #q, 1, -1 do
        local e = q[i]
        if os.clock() >= e.at then
            table.remove(q, i)
            -- ((2026-11-07: AC8 crashed on a carrier arm's unit taken off with its planes up) a ZFA-44 unit with planes
            -- still up isn't taken off by force: looked at again 5 s on, 6 times at most, then left on the list)
            local up = aliveOf(e.unit)
            if KIND[e.unit] == "cargo" and ZLAUNCH and ZLAUNCH.holdHull(CARGO_I[e.unit], e, e.unit, e.why) then e.at = os.clock() + 5; q[#q + 1] = e; return end
            if KIND[e.unit] == "zfa" and up > 0 then
                e.tries = (e.tries or 0) + 1
                if e.tries < 6 then
                    e.at = os.clock() + 5
                    q[#q + 1] = e
                else
                    log(string.format("escort: %s (%s) still has %d up after 30 s: left on the spawner's list, never taken off with planes up",
                        e.unit, tostring(e.why), up))
                end
                return
            end
            if type(SV_Recycle) == "function" and up ~= -2 then
                crumb("escort SV_Recycle " .. e.unit)
                local okR, r = pcall(SV_Recycle, e.unit, 1)
                log(string.format("escort: %s off the spawner's list (%s): SV_Recycle %s", e.unit, tostring(e.why), okR and tostring(r) or ("error " .. tostring(r))))
            end
            return                                         -- (one a tick)
        end
    end
end
-- every tick half (sv_main.lua probeTickB, on the round clock), every game
function ESC.tick(now)
    if not (D and now) then return end
    if ESC.S and ESC.S.D ~= D then ESC.S = nil end          -- (a new run: what it was is the old level's)
    names()
    hullsTick()
    -- ((2026-11-07) the ZFA-44's mesh and textures loaded and kept from the carriers' unlock, one a tick: never all at
    -- once as a ship comes on station)
    if ZFA and ZFA.preload and ESC.unlocked() and (cc().zfa or {}).dress ~= false and (cc().zfa or {}).preload ~= false then
        local okP, errP = pcall(ZFA.preload)
        if not okP then logOnce("zfa preload", "carrier: ZFA-44 preload error " .. tostring(errP)) end
    end
    dressTick()
    if ZLAS and ZLAS.tick then pcall(ZLAS.tick) end              -- (the lasers' interceptions: sv_escort_laser.lua)
    if ZFA and ZFA.prodTick then
        local okZ, errZ = pcall(ZFA.prodTick)
        if not okZ then logOnce("zfa prod", "carrier: ZFA-44 tick error " .. tostring(errZ)) end
    end
    recycleTick()
    if client() then return end
    local S = ESC.S
    if S and S.test then
        ESC.step(S, now)
        if D.state == "wait" and D.at and D.at < now + 3 then D.at = now + 3 end   -- (the test holds the break)
        if S.state == "done" and S.endAt and now >= S.endAt then
            takeOff(S, "the landing test over")
            ESC.S = nil
        end
    end
    local R = run()
    for _, C in pairs(R.carriers) do
        local okC, errC = pcall(carrierTick, C, now)
        if not okC and not C.errSaid then C.errSaid = true; log("carrier: " .. tostring(C.name) .. " error " .. tostring(errC)) end
    end
    local okS, errS = pcall(sendState, now)
    if not okS then logOnce("escort es", "escort: state send error " .. tostring(errS)) end
end
-- ((code review of 2026-11-07, finding 3) a pause-menu restart (sv_main.lua's level-load block, before the new run's D):
-- the run's escort and carriers were dropped untouched with the old D (ESC.tick, run()), so a landing left the players'
-- landing closed and CHARLENE's flight, the ships and their ZFA-44s up with nobody minding them (a ship up also kept
-- the STORE's slot: freeShip). Now everything of the old run's taken off as its own ends do (switched off, a joiner's
-- copies down first, unpaid, each unit off the spawner's list 2 s on); a joiner's own ZFA-44s off
function ESC.restart(why)
    why = tostring(why or "the run starts over")
    local S, nA, nC = ESC.S, 0, 0
    if S then
        reopen(S, why)
        takeOff(S, why)
        nA = #S.ac
    end
    ESC.S = nil
    local R = ESC.R
    if R and not client() then
        for _, C in pairs(R.carriers) do
            if C.state ~= "leaving" then
                -- ((2026-11-11) every ZFA-44 of its arms finished off, its flight's too (switched off, they still count up): left up,
                -- they held its hull on the list for the rest of the level, ZLAUNCH.holdHull. Before flightOff: on live planes)
                if ZLAUNCH and ZLAUNCH.parkedOff then pcall(ZLAUNCH.parkedOff, C.idx, nil, C.name .. " (" .. why .. ")", true) end
                if C.flight then flightOff(C.flight, why) end
                if COOP and COOP.removeNow then pcall(COOP.removeNow, C.unit) end
                for _, e in ipairs((ESC.shipObjs or {})[C.unit] or {}) do if liveAddr(e.obj) == e.addr then offObj(e.obj) end end
            end
            ESC.recycleQ[#ESC.recycleQ + 1] = { unit = C.unit, at = os.clock() + 2, why = why }
            ESC.hulls[C.unit] = nil
            if ESC.shipObjs then ESC.shipObjs[C.unit] = nil end
            nC = nC + 1
        end
    end
    ESC.R = nil
    local nZ = 0
    if client() then
        for i = 1, #(cc().units or {}) do nZ = nZ + ESC.localOff(i, why) end
        if ESC.clientClosed and not (AF and (AF.closed or AF.down)) then airfield(false, why) end
        ESC.clientClosed, ESC.host = false, nil
    end
    if nA > 0 or nC > 0 or nZ > 0 then
        log(string.format("escort: %s: %d of the escort's aircraft and %d carriers taken off, %d of this game's own ZFA-44s off", why, nA, nC, nZ))
    end
end
-- the level's objects forgotten with it, none of them touched (sv_core.lua levelDrop)
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["the escort"] = function()
        ESC.S, ESC.R, ESC.planes, ESC.dressQ, ESC.newObjs, ESC.hulls, ESC.shipObjs, ESC.offZfa = nil, nil, {}, {}, {}, {}, nil, nil
        ESC.recycleQ, ESC.clientClosed, ESC.host = {}, nil, nil
    end
end

-- TEST ONLY BEGIN (Ctrl+F5: the landing test T0; Ctrl+DEL: the carriers unlocked and one sent now; sv_main.lua's keys)
-- T0 (docs/re/ESCORT.md): CHARLENE alone before_m short of the approach fix (heading 067: her final's start a little
-- ahead, hard rule 2), her final, rollout, taxi and stop with no enemies sent at her and no escorts, her place against
-- the runway, height, speed and gear logged every log_s (`escort: T0 +N s: ...`), the break held while it runs, taken
-- off end_s after she's down
function ESC.testT0()
    if not (D and D.now) then log("test: Ctrl+F5 outside a Survival run"); return end
    if ESC.S then hudCallout("TEST: ESCORT T0", "AN ESCORT IS ALREADY UP"); log("escort: T0: an escort is already up"); return end
    local c = ec()
    local S = newOp(D.now, "t0")
    reset(S)
    local g = c.geo
    local hd = num(g.heading, 67)
    local back = num(c.test and c.test.before_m, 1500) * 100
    local fx, fy = math.sin(math.rad(hd)), -math.cos(math.rad(hd))
    local ok, r = spawnAc(S, her(S), { x = g.iaf[1] - fx * back, y = g.iaf[2] - fy * back, z = g.iaf[3], yaw = hd - 90 })
    if not ok then hudCallout("TEST: ESCORT T0", "CHARLENE NOT SPAWNED"); log("escort: T0: CHARLENE not spawned: " .. ERR(r)); return end
    S.state = "route"
    ESC.S = S
    hudCallout("TEST: ESCORT T0", "CHARLENE ON FINAL: WATCH HER LAND")
    log(string.format("escort: T0: CHARLENE %.0f m short of the approach fix, heading %03d, no enemies at her: her final, rollout, taxi and stop logged",
        back / 100, math.floor(hd)))
end
function ESC.testCarrier()
    if not (D and D.now) then log("test: Ctrl+DEL outside a Survival run"); return end
    RUN.zfa = { unlocked = true, test = true }
    RUN.dirty = true
    local ok, msg = ESC.buyCarrier(nil, 0)
    hudCallout("TEST: VAMPIRES", ok and "UNLOCKED, ONE SENT" or ("UNLOCKED: " .. tostring(msg)))
    log("escort: test: Ctrl+DEL: the ZFA-44 carriers unlocked; " .. tostring(msg))
end
-- TEST ONLY END
end
