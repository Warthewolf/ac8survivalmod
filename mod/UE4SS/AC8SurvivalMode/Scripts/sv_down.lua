-- sv_down.lua: Survival COOP's revives and the spectator camera (CFG.coop.revive; tools/re/COOP.md 9).
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (after sv_coop, whose messages, players and stand-ins it
-- uses); a name another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).
--
-- The user, 2026-10-29: "is there a revive option we could possibly add for COOP only? like say if you die, HOST or
-- JOINER, someone could land at the airfield and buy you back, lets say that when you die, you get put into a spectator
-- camera and you can switch between the players currently active". Co-op only (another game linked, in a run); solo the
-- game's own death as ever.
--   the floor   your plane's MinHealth held at floor_hp (sv_tactical.lua INS.tick: read back and set again every tick,
--               the game puts it back on a restore); a SECOND CHANCE held comes first (its floor is higher)
--   DOWN        at the floor (HealthInternal <= floor_hp x 10): invincible, hidden, no collision, weapons and flares off,
--               the enemies' attacks on you held off (your plane's attacker limits at 0), flown round the airfield by the
--               runtime's loiter autopilot (SV_Down: alt_m up, radius_m round, well inside the combat zone), state bit 8
--               (the others hide your plane and count you out: COOP.players() alive false), "dw" to the host, which tells
--               everyone; your view on another player's plane (the spectator camera below)
--   revive      any other player at their airfield buys you back from the STORE's AIRFIELD page (REVIVE <NAME>, the one
--               down longest: price x raise for each revive in the run, the host's count); the host checks it and tells
--               everyone ("rb"): you're back, repaired, safe_s invincible, where the loiter left you (respawn "loiter")
--               or 4 km out from the runway at 500 m ("native": SV_Respawn; also a plane that isn't flying, crashed into
--               the ground: GROUND_MS); the others call it out
--   run over    every player in the mission down (RO_CONFIRM_S): the host's "ro" ends the run on every game (LB.finish,
--               Mission 15's MissionFailed: RE_SV_RunOver; sv_leaderboard.lua's own death check waits for it in co-op)
-- The spectator camera: a CameraComponent added to the watched player's plane here (back_m behind, up_m up, looking at
-- it; hard rule 46: components added to AI planes work), your view on it (SetViewTargetWithBlend), put back (and
-- counted) whenever the game takes it back to your own plane; the key (O; ctrl) the next player; the next one by itself
-- when the one you watch goes down, leaves or isn't shown; the NEXT row "DOWN: WATCHING <NAME>  [O] NEXT". Your own
-- view (the game's view target as you went down) is put back on the way back.
--   a restart  while you're down (the pause menu's, or the retry after a failed mission) keeps the level AND your plane:
--              the game refills and restores it, but what DOWN changed stays (the user's co-op run of 2026-10-30: the
--              host's DOWN plane left the combat zone, the mission failed and restarted in round 7; the host could fly
--              but had no third-person view: the plane still hidden). Put back at the first pass with the level's
--              player (restoreAfter): shown, collision, weapons, attackers, mortal; the view off the plane you watched.
--   the edge   a DOWN plane EDGE_CM from the combat zone's edge is put back over the airfield (SV_Respawn), flown again.
-- Messages (reliable; sv_coop.lua hands them over, its guards first): joiner -> host dw|<slot>, rv|<slot>|<price>;
-- host -> everyone dw|<slot>|<count>[|q], rb|<slot>|<count>|<by>, ro|<round>; host -> one joiner rx|<slot>|<why>|<count>
-- (a refused revive: refunded), rc|<count> (the room's revives, as it links).
DOWN = {}
do
local RO_CONFIRM_S, PENDING_S, REVIVING_S, MSG_PER_S, PRESENT_MS = 3, 10, 15, 4, 5000
-- a DOWN plane slower than GROUND_MS (m/s: no plane flies that slowly) or under the sea for GROUND_S isn't flying: it
-- crashed into the ground with its floor held, and the loiter can't lift it (the user's co-op run of 2026-10-30: VERDA
-- crashed, was revived where the plane lay, on the ground). A revive then brings it back the "native" way.
local GROUND_MS, GROUND_S = 40, 3
-- a DOWN plane this near the combat zone's edge (ZONE, sv_ai.lua: 3 km inside it already, so 8 km from it) is put back
-- over the airfield, at most every EDGE_EVERY_S: out of the zone the game fails the mission for everyone
local EDGE_CM, EDGE_EVERY_S = 500000, 20
-- a restart's put-back waits this long for the level's player plane at most
local RESTORE_S = 60
local INPUTS = { { "bEnableWeaponInput", false }, { "bEnableFlareInput", false }, { "bIsWeaponSystemDisabled", true } }
local ATTACKERS = { "MaxPlaneAttackerMissiles", "MaxPursuitAttackers", "MaxNonPlaneAttackerMissiles" }
-- "native" respawn: 4 km out from the runway along its heading (Comona's runway, yaw -23: the takeoff's way), 500 m up
local RUNWAY = { X = 1609574.0, Y = -435747.0, yaw = -23, out_cm = 400000, z_cm = 50000 }
local St = { down = false, since = {}, count = 0, pending = {}, reviving = {}, cams = {}, rate = {}, reverts = 0 }
DOWN.St = St                                    -- (the offline test's)

local function rc() local c = CFG.coop and CFG.coop.revive; return type(c) == "table" and c or {} end
local function pawnOf() return survivalPC and valid(survivalPC) and survivalPC.Pawn or nil end
local function mySlot() return (COOP and COOP.slot) or 0 end
local function linked() return COOP ~= nil and COOP.open == true and COOP.linked ~= nil and COOP.linked() > 0 end
local function num(v, d) v = tonumber(v); return (v and v == v and v > -1e12 and v < 1e12) and v or d end
local function upper(s, max)                    -- a name for the HUD and the STORE: capitals, max characters
    s = string.upper(tostring(s or ""))
    local n = utf8 and utf8.len(s)
    if n and n > max then return s:sub(1, utf8.offset(s, max + 1) - 1) end
    return n and s or s:sub(1, max)
end
local function name(slot) return upper((COOP and COOP.name and COOP.name(slot)) or ("PLAYER " .. (slot + 1)), 14) end
local function callout(text, sub) if type(hudCallout) == "function" then pcall(hudCallout, text, sub) end end
local function priceFor(n)
    local c = rc()
    return math.floor(num(c.price, 2500) * num(c.raise, 1) ^ (n or 0) / 10 + 0.5) * 10
end

-- Revives on: co-op open with another game linked, in a run (or T1's floor, a test key's)
function DOWN.active() return St.testFloor == true or (rc().enabled == true and D ~= nil and linked()) end
-- the MinHealth your plane is held at (sv_tactical.lua INS.tick): floor_hp while revives are on, else 0 (solo: as ever)
function DOWN.floor() return (DOWN.active() and not St.noFloor) and num(rc().floor_hp, 0.1) or 0 end
-- you're DOWN (shot down, waiting for a revive)
function DOWN.me() return St.down == true end
-- the run ends on the host's "ro" only (sv_leaderboard.lua LB.deathCheck), not on this game's own shoot-down
function DOWN.holdsRun() return rc().enabled == true and linked() end

-- the other players down now (their state fresh, bit 8), the one down longest first: { slot, since }; each one's since
-- from their "dw" or the first state seen with it
local function downList()
    local out, now = {}, os.clock()
    for _, e in ipairs(COOP and COOP.players and COOP.players() or {}) do
        if not e.isMe then
            if e.down and e.fresh then
                St.since[e.slot] = St.since[e.slot] or now
                out[#out + 1] = { slot = e.slot, since = St.since[e.slot] }
            elseif e.fresh then
                St.since[e.slot] = nil
            end
        end
    end
    table.sort(out, function(a, b) return a.since < b.since or (a.since == b.since and a.slot < b.slot) end)
    return out
end
local function isDown(slot)
    if slot == mySlot() then return St.down end
    for _, e in ipairs(downList()) do if e.slot == slot then return true end end
    return false
end
local function onAirfield(slot)                 -- (the reviver: on the ground at their airfield, by their own game's state)
    if slot == mySlot() then return not St.down and playerOnAirfield() == true end
    local P = COOP.peerInfo and COOP.peerInfo(slot)
    return P ~= nil and P.fresh == true and P.onAirfield == true and not P.down
end

---------------------------------------------------------------------------------------------------- the spectator camera
local function keyLabel()
    local c = rc()
    return (c.ctrl and "CTRL+" or "") .. string.upper(tostring(c.key or "O"))
end
-- the planes you can watch: the other players' (sv_coop.lua COOP.watchable: shown, fresh, not DOWN), slot order
local function watchable()
    local l = COOP and COOP.watchable and COOP.watchable() or {}
    for _, e in ipairs(l) do e.name = upper(e.name, 14) end
    -- TEST ONLY BEGIN (T2, Ctrl+END solo: MOONCHILD / VIPER, else the nearest enemies)
    if St.testDown and #l == 0 then
        for _, p in ipairs(ALLY and ALLY.run and ALLY.run.planes or {}) do
            if valid(p.obj) then l[#l + 1] = { slot = -1, obj = p.obj, addr = addrOf(p.obj), name = upper(p.name, 14) } end
        end
        for _, p in ipairs(planes or {}) do
            if #l < 6 and not p.down and valid(p.obj) then l[#l + 1] = { slot = -1, obj = p.obj, addr = addrOf(p.obj), name = upper(p.name, 14) } end
        end
    end
    -- TEST ONLY END
    return l
end
-- a camera on plane e.obj: a CameraComponent added once (kept by its address), back_m behind and up_m above, looking at it
local function camOn(obj)
    local a = addrOf(obj)
    local have = a and St.cams[a]
    if have and valid(have) then return have end
    local cls = StaticFindObject("/Script/Engine.CameraComponent")
    if not valid(cls) then return nil, "no CameraComponent class" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, comp = pcall(function() return obj:AddComponentByClass(cls, false, t, false) end)
    if not ok or not valid(comp) then return nil, "AddComponentByClass " .. (ok and "gave nothing" or tostring(comp)) end
    local cam = rc().camera or {}
    local back, up = num(cam.back_m, 30) * 100, num(cam.up_m, 8) * 100
    local function place(k)
        pcall(function()
            comp:K2_SetRelativeLocationAndRotation({ X = -back * k, Y = 0, Z = up * k },
                { Pitch = -math.deg(math.atan(up, back)), Yaw = 0, Roll = 0 }, false, {}, true)
        end)
    end
    place(1)
    -- (how far it really is: the offset is in the plane's root component's space, and a player plane's is scaled down:
    -- the user's co-op run of 2026-10-30, watching CRESSENDO's real ADFX-02, the view sat just behind its seat. So the
    -- distance is measured and the offset scaled by what it came out as)
    local want = math.sqrt(back * back + up * up)
    local function dist()
        local okC, c = pcall(function() local v = comp:K2_GetComponentLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
        local okP, q = pcall(function() local v = obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
        if not (okC and okP and c and q and type(c.X) == "number" and type(q.X) == "number") then return nil end
        return math.sqrt((c.X - q.X) ^ 2 + (c.Y - q.Y) ^ 2 + (c.Z - q.Z) ^ 2)
    end
    local d0 = dist()
    local k, d1 = 1, d0
    if d0 and d0 > 1 and math.abs(d0 / want - 1) > 0.2 then
        k = math.max(0.01, math.min(1000, want / d0))
        place(k)
        d1 = dist()
    end
    log(string.format("spectate: camera on %s: %s from it (wanted %.0f m)%s", nameOf(obj):match("([%w_]+)$") or "?",
        d0 and string.format("%.1f m", d0 / 100) or "? m", want / 100,
        k ~= 1 and string.format("; its offset x%.2f (the plane's scale), now %s", k, d1 and string.format("%.1f m", d1 / 100) or "? m") or ""))
    if a then St.cams[a] = comp end
    return comp
end
local function setView(target, blend)
    if not (survivalPC and valid(survivalPC) and valid(target)) then return false end
    return pcall(function() survivalPC:SetViewTargetWithBlend(target, blend or 0, 0, 0, false) end)
end
-- A player plane (COOP2MP's real planes: the ADFX-02 has no AI stand-in) carries cameras of its own, and the view on an
-- actor takes the first active camera on it: the user's co-op run of 2026-10-30, watching CRESSENDO's real ADFX-02,
-- "spawned the camera inside the aircraft". So while you watch a plane, its other cameras are switched off (St.hushed),
-- and back on as the view leaves it.
local function unhush()
    for _, c in ipairs(St.hushed or {}) do
        if valid(c) then pcall(function() c:Activate(false) end) end
    end
    St.hushed = {}
end
local function hush(obj, cam)
    unhush()
    local cls = StaticFindObject("/Script/Engine.CameraComponent")
    if not (valid(cls) and valid(obj)) then return 0, 0 end
    local okL, arr = pcall(function() return obj:K2_GetComponentsByClass(cls) end)
    if not (okL and arr) then return 0, 0 end
    local list = {}
    pcall(function() arr:ForEach(function(_, e) list[#list + 1] = e:get() end) end)
    local mine, off, names = cam and addrOf(cam), 0, {}
    for _, c in ipairs(list) do
        if valid(c) and addrOf(c) ~= mine then
            local okA, act = pcall(function() return c:IsActive() end)
            names[#names + 1] = (nameOf(c):match("([%w_]+)$") or "?") .. (okA and act and " (on)" or "")
            if okA and act and pcall(function() c:Deactivate() end) then
                off = off + 1
                St.hushed[#St.hushed + 1] = c
            end
        end
    end
    if cam then pcall(function() cam:Activate(true) end) end
    local a = addrOf(obj)
    St.hushSaid = St.hushSaid or {}
    if a and not St.hushSaid[a] and #names > 0 then
        St.hushSaid[a] = true
        log(string.format("spectate: %s's own cameras: %s; %d switched off while you watch it", nameOf(obj):match("([%w_]+)$") or "?",
            table.concat(names, ", "), off))
    end
    return #list, off
end
local function view(e, why)
    local cam, err = camOn(e.obj)
    hush(e.obj, cam)
    local ok = setView(e.obj, num((rc().camera or {}).blend_s, 0.5))
    St.watch, St.views = e, (St.views or 0) + 1
    log(string.format("spectate: view %s (%s)%s%s, reverted %d times", e.name, why, cam and "" or (", no camera: " .. tostring(err)),
        ok and "" or ", SetViewTargetWithBlend FAILED", St.reverts))
end
-- your own view as you go down: the game's view target then (your plane, as a rule)
local function homeView()
    local okV, vt = pcall(function() return survivalPC:GetViewTarget() end)
    if not (okV and valid(vt)) then return nil end
    return { obj = vt, addr = addrOf(vt), name = nameOf(vt), pawn = addrOf(vt) == addrOf(pawnOf()) }
end
-- the view back on your own: what it was as you went down, or your plane now (a restart or a respawn may give another)
local function viewSelf(blend)
    St.watch = nil
    unhush()
    local h, pawn = St.home, pawnOf()
    blend = blend or num((rc().camera or {}).blend_s, 0.5)
    if h and not h.pawn and valid(h.obj) then setView(h.obj, blend)
    elseif valid(pawn) then setView(pawn, blend) end
end
-- the next player to watch (the key, or the one watched is gone): the one after the current in slot order, else the first
function DOWN.nextView(why)
    if not St.down then return end
    local l = watchable()
    if #l == 0 then
        if St.watch then log("spectate: nobody to watch (" .. tostring(why) .. "): your own plane") end
        viewSelf()
        return
    end
    local idx = 1
    for i, e in ipairs(l) do if St.watch and e.addr == St.watch.addr then idx = i % #l + 1 end end
    if St.watch and l[idx].addr == St.watch.addr and why == "key" then return end   -- (the only one)
    view(l[idx], why)
end
-- each pass while DOWN: the one watched still there, the view still on it
local function spectateTick(now)
    local w, l = St.watch, nil
    if w then
        l = watchable()
        local still = false
        for _, e in ipairs(l) do if e.addr == w.addr then still = true end end
        if not still then DOWN.nextView("their plane isn't up here now"); return end
        local okV, vt = pcall(function() return survivalPC:GetViewTarget() end)
        if okV and addrOf(vt) ~= w.addr then
            St.reverts = St.reverts + 1
            setView(w.obj, 0)
            if St.reverts <= 3 or St.reverts % 20 == 0 then
                log(string.format("spectate: view put back on %s (the game took it back %d times)", w.name, St.reverts))
            end
        end
    elseif now >= (St.lookAt or 0) then
        St.lookAt = now + 2
        DOWN.nextView("looking for a player to watch")
    end
end
-- The NEXT row while you're down (sv_hud.lua hudTick)
function DOWN.hudLine()
    if not St.down then return nil end
    if St.watch then return string.format("DOWN: WATCHING %s  [%s] NEXT", St.watch.name, keyLabel()) end
    return "DOWN: WAITING FOR A REVIVE"
end

---------------------------------------------------------------------------------------------------- down and back
-- your plane out of the fight; what it had, for the way back
local function outOfFight(pawn)
    local s, parts = { inputs = {}, attackers = {} }, {}
    pcall(function() pawn:SetIsInvincible(true) end)
    parts[#parts + 1] = pcall(function() pawn:SetActorHiddenInGame(true) end) and "hidden" or "hidden FAILED"
    parts[#parts + 1] = pcall(function() pawn:SetActorEnableCollision(false) end) and "no collision" or "collision FAILED"
    for _, f in ipairs(INPUTS) do
        local okR, v = pcall(function() return pawn[f[1]] end)
        local okW = okR and pcall(function() pawn[f[1]] = f[2] end)
        if okW then s.inputs[f[1]] = v end
        parts[#parts + 1] = f[1] .. " " .. tostring(f[2]) .. (okW and "" or " FAILED")
    end
    for _, f in ipairs(ATTACKERS) do                -- (the enemies' limits on attacking you: guesses, untested)
        local okR, v = pcall(function() return pawn[f] end)
        local okW = okR and type(v) == "number" and pcall(function() pawn[f] = 0 end)
        if okW then s.attackers[f] = v end
        parts[#parts + 1] = f .. (okW and (" " .. tostring(v) .. " -> 0") or " FAILED")
    end
    return s, table.concat(parts, ", ")
end
local function backInFight(pawn, s)
    if not valid(pawn) then return end
    pcall(function() pawn:SetActorHiddenInGame(false) end)
    pcall(function() pawn:SetActorEnableCollision(true) end)
    for f, v in pairs(s and s.inputs or {}) do pcall(function() pawn[f] = v end) end
    for f, v in pairs(s and s.attackers or {}) do              -- (unless something set its own meanwhile: a pressure preset)
        pcall(function() if pawn[f] == 0 then pawn[f] = v end end)
    end
end
local function loiter(pawn)
    if type(SV_Down) ~= "function" then return "no SV_Down (runtime 0.28.5 or later)" end
    local lo = rc().loiter or {}
    local ok, r = pcall(SV_Down, addrOf(pawn) or 0, AIRFIELD.X, AIRFIELD.Y, num(lo.alt_m, 2500), num(lo.radius_m, 4000))
    if not ok then return "error " .. tostring(r) end
    return r == 1 and "on" or (tostring(r) .. " " .. tostring(SV_ERR[r] or ""))
end

-- (each pass while DOWN) how fast your plane moves, from where it is against half a second or more before: the loiter
-- keeps a flying plane at cruise speed; a crashed one lies still
local function motionTick(now)
    local at = playerLocation()
    if not at then return end
    local m = St.motion
    if m and now - m.t < 0.5 then return end
    St.motion = { X = at.X, Y = at.Y, Z = at.Z, t = now }
    if not m then return end
    St.speed = km(at, m) * 1000 / (now - m.t)
    if St.speed < GROUND_MS or at.Z < 0 then St.groundedAt = St.groundedAt or now else St.groundedAt = nil end
    if St.groundedAt and now - St.groundedAt >= GROUND_S and not St.groundSaid then
        St.groundSaid = true
        local dx, dy = at.X - AIRFIELD.X, at.Y - AIRFIELD.Y
        log(string.format("down: your plane isn't flying (%.0f m/s, %.0f m up, %.1f km from the airfield): a revive brings you back "
            .. "4 km out from the runway, 500 m up", St.speed, at.Z / 100, math.sqrt(dx * dx + dy * dy) / 100000))
    end
end
local function grounded() return St.groundedAt ~= nil and os.clock() - St.groundedAt >= GROUND_S end

local function goDown(pawn, h)
    local now = os.clock()
    St.down, St.downAt, St.ended, St.reverts, St.views, St.watch, St.lookAt = true, now, false, 0, 0, nil, nil
    St.since[mySlot()] = now
    St.reviving[mySlot()] = nil                    -- (a new DOWN: the last revive's guard doesn't hold this one)
    St.home, St.restore, St.edgeAt = homeView(), nil, nil
    log("spectate: your own view as you went down: " .. (St.home and (St.home.name .. (St.home.pawn and " (your plane)" or " (not your plane)")) or "none"))
    local saved, did = outOfFight(pawn)
    St.saved, St.loiterAddr, St.loiterAt, St.loiterSaid = saved, addrOf(pawn), now + 5, nil
    St.motion, St.speed, St.groundedAt, St.groundSaid = nil, nil, nil, nil
    local r = loiter(pawn)
    local lo = rc().loiter or {}
    log(string.format("down: you're down at %.1f HP in round %s: %s; loiter round the airfield at %s m, %s m round: %s",
        (h or 0) / 10, tostring(D and D.round), did, tostring(lo.alt_m), tostring(lo.radius_m), tostring(r)))
    pcall(STATS.death, "down")
    LB.stat("downs", 1)
    callout("YOU'RE DOWN", string.format("A WINGMAN CAN REVIVE YOU AT THEIR AIRFIELD  [%s] NEXT PLAYER", keyLabel()))
    if COOP.host() then COOP.msg(nil, "dw", mySlot(), St.count) else COOP.msg(nil, "dw", mySlot()) end
    DOWN.nextView("you're down")
end

-- Back in the fight (revived, the run started over, a test): the loiter off, the plane as it was, the view yours,
-- repaired (the stock repair and the health written), safe_s invincible, where the loiter left you or "native"
function DOWN.back(how, respawn)
    if not St.down then return end
    local pawn = pawnOf()
    local downFor = os.clock() - (St.downAt or os.clock())
    local onGround = grounded()
    St.down, St.since[mySlot()] = false, nil
    if type(SV_Down) == "function" then pcall(SV_Down, 0) end
    backInFight(pawn, St.saved)
    St.saved = nil
    viewSelf()
    St.home = nil
    local r = type(SV_Event) == "function" and SV_Event("RE_SV_RepairAircraft") or -5
    local okW = valid(pawn) and pcall(function() pawn.HealthInternal = math.floor(pawn.MaxHealth * 10 + 0.5) end)
    St.safeUntil = os.clock() + num(rc().safe_s, 5)
    if valid(pawn) then pcall(function() pawn:SetIsInvincible(true) end) end
    local where = respawn or tostring(rc().respawn or "loiter")
    local placed, why = "where the loiter left you", ""
    if where ~= "native" and onGround then          -- (crashed: where it lies is the ground)
        where, why = "native", string.format(" (your plane wasn't flying: %.0f m/s)", St.speed or 0)
    end
    if where == "native" and valid(pawn) then
        local y = math.rad(RUNWAY.yaw)
        local x, yy = RUNWAY.X + math.cos(y) * RUNWAY.out_cm, RUNWAY.Y + math.sin(y) * RUNWAY.out_cm
        local rr = "no SV_Respawn (runtime 0.28.5 or later)"
        if type(SV_Respawn) == "function" then
            local okR, v = pcall(SV_Respawn, addrOf(pawn) or 0, x, yy, RUNWAY.z_cm, 0, RUNWAY.yaw, 0)
            rr = (not okR and ("error " .. tostring(v))) or (v == 1 and "done") or (tostring(v) .. " " .. tostring(SV_ERR[v] or ""))
        end
        placed = string.format("SV_Respawn 4 km out from the runway, 500 m up%s: %s", why, tostring(rr))
        St.respawnAt = { at = os.clock() + 0.5, X = x, Y = yy, Z = RUNWAY.z_cm }
    else
        local at = playerLocation()
        St.respawnAt = at and { at = os.clock() + 0.5, X = at.X, Y = at.Y, Z = at.Z } or nil
    end
    log(string.format("revive: back (%s) after %.0f s down: repaired (event %s, health %s), %s s invincible, %s", how, downFor,
        r == 1 and "fired" or (SV_ERR[r] or tostring(r)), okW and "written" or "NOT written", tostring(rc().safe_s), placed))
    callout("BACK IN THE FIGHT", string.upper(tostring(how)))
    LB.stat("revived", 1)
end

-- Every player down: the run's over on this game (the host's "ro", or the host's own call)
function DOWN.runOver(round, by)
    if St.ended or not D then return end
    St.ended = true
    log(string.format("down: run over in round %s: every player is down (%s)", tostring(round or D.round), tostring(by)))
    viewSelf()
    callout("RUN OVER", "EVERY PLAYER IS DOWN")
    pcall(STATS.death, "died")
    local okL, errL = pcall(LB.finish, "died")
    if not okL then log("leaderboard: error " .. tostring(errL)) end
    local fire = COOP and COOP.eventHere or SV_Event
    local r = type(fire) == "function" and fire("RE_SV_RunOver") or -5
    log("down: the mission's end (RE_SV_RunOver, Mission 15's MissionFailed): " .. (r == 1 and "fired" or (SV_ERR[r] or tostring(r))))
    if r ~= 1 then                                   -- (no event: your plane back to mortal, the game's own death then)
        local pawn = pawnOf()
        if type(SV_Down) == "function" then pcall(SV_Down, 0) end
        backInFight(pawn, St.saved)
        if valid(pawn) then
            pcall(function() pawn:SetMinHealth(0) end)
            pcall(function() pawn:SetIsInvincible(false) end)
        end
        St.down, St.noFloor = false, true
        log("down: the fallback: your plane's floor and invincibility off")
    end
end

-- The host's new run (a plane still down comes back, a revive asked is refunded), a new level or a run left (newLevel:
-- the loiter off; on a new level, which a restart is too, the plane and view put back at the first pass with the level's
-- player, restoreAfter): nothing down, no revives
function DOWN.reset(why, newLevel)
    if St.down and newLevel then
        if why == "a new level" then
            St.restore = { addr = St.loiterAddr, saved = St.saved, home = St.home, watch = St.watch and St.watch.addr, at = os.clock() }
        end
        St.down, St.saved, St.watch, St.home = false, nil, nil, nil
        if type(SV_Down) == "function" then pcall(SV_Down, 0) end
        log("down: " .. tostring(why) .. ": no longer down" .. (St.restore and "; your plane and view put back once the level's player is in" or ""))
    elseif St.down then
        DOWN.back(tostring(why), "loiter")
    end
    for slot, p in pairs(newLevel and {} or St.pending) do     -- (asked, never answered: refunded)
        if RUN then RUN.credits, RUN.spent, RUN.dirty = RUN.credits + p.price, math.max(0, (RUN.spent or 0) - p.price), true end
        log(string.format("revive: player %d's revive refunded (%d): %s", slot + 1, p.price, tostring(why)))
    end
    St.since, St.count, St.pending, St.reviving, St.cams = {}, 0, {}, {}, {}
    St.ended, St.noFloor, St.allDownAt, St.safeUntil, St.respawnAt, St.watch = false, nil, nil, nil, nil, nil
end

-- After a restart while you were down (DOWN.reset's St.restore), at the first pass with the level's player: the plane DOWN
-- changed, if the restart kept it (it does: the game refills and restores it in place), shown, collision, weapons and
-- attackers back, mortal; the view, if it's still on the plane you watched (or nowhere), back on your own
local function restoreAfter(pawn)
    local r = St.restore
    St.restore = nil
    if os.clock() - (r.at or 0) > RESTORE_S then
        log(string.format("down: after the restart: no player plane in %d s; nothing put back", RESTORE_S))
        return
    end
    local parts = {}
    if r.addr ~= nil and addrOf(pawn) == r.addr then
        backInFight(pawn, r.saved)
        pcall(function() pawn:SetIsInvincible(false) end)
        parts[#parts + 1] = "the same plane: shown, collision, weapons and its attackers back, not invincible"
    else
        parts[#parts + 1] = string.format("another plane (%s; down was %s): nothing on it to put back", tostring(addrOf(pawn)), tostring(r.addr))
    end
    local okV, vt = pcall(function() return survivalPC:GetViewTarget() end)
    local va = okV and valid(vt) and addrOf(vt) or nil
    if va == nil or va == r.watch or va == addrOf(survivalPC) then
        St.home = r.home
        viewSelf(0)
        St.home = nil
        parts[#parts + 1] = "the view was " .. (va == nil and "nowhere" or va == r.watch and "still on the plane you watched" or "on the controller")
            .. ": back on " .. ((r.home and not r.home.pawn and valid(r.home.obj)) and r.home.name or "your plane")
    else
        parts[#parts + 1] = "the view on " .. nameOf(vt) .. " (left as it is)"
    end
    log("down: after the restart: " .. table.concat(parts, "; "))
end

-- (each pass while DOWN) near the combat zone's edge: put back over the airfield at the loiter's height (SV_Respawn, 4 km
-- out along the runway as the revive's "native"), out of the fight again (the respawn may give the plane its look back)
-- and flown again this pass (the respawn turned the loiter off)
local function edgeGuard(pawn, now)
    if not ZONE or now < (St.edgeAt or 0) then return end
    local at = playerLocation()
    if not at then return end
    local edge = ZONE.HALF - math.max(math.abs(at.X - ZONE.X), math.abs(at.Y - ZONE.Y))
    if edge >= EDGE_CM then return end
    St.edgeAt = now + EDGE_EVERY_S
    local y = math.rad(RUNWAY.yaw)
    local x, yy = RUNWAY.X + math.cos(y) * RUNWAY.out_cm, RUNWAY.Y + math.sin(y) * RUNWAY.out_cm
    local z = num((rc().loiter or {}).alt_m, 2500) * 100
    local rr = "no SV_Respawn (runtime 0.28.5 or later)"
    if type(SV_Respawn) == "function" then
        local okR, v = pcall(SV_Respawn, addrOf(pawn) or 0, x, yy, z, 0, RUNWAY.yaw, 0)
        rr = (not okR and ("error " .. tostring(v))) or (v == 1 and "done") or (tostring(v) .. " " .. tostring(SV_ERR[v] or ""))
    end
    local _, did = outOfFight(pawn)
    St.loiterAt, St.motion, St.groundedAt, St.groundSaid = 0, nil, nil, nil
    log(string.format("down: your plane was %.1f km from the combat zone's edge, %.0f m up: put back over the airfield, %.0f m up "
        .. "(SV_Respawn: %s); %s", (edge + 300000) / 100000, at.Z / 100, z / 100, rr, did))
end

---------------------------------------------------------------------------------------------------- the STORE's row
-- What the AIRFIELD page's REVIVE row offers now (sv_shop.lua offer): { label, help, price (nil: nothing to buy), why,
-- slot }: the one down longest, "(+N)" when more are
function DOWN.offer()
    local c = rc()
    local o = { label = "REVIVE A WINGMAN", help = "Co-op: buys back a player who's down. They're repaired and back in the air." }
    if not (COOP and COOP.open and linked()) then o.why = "CO-OP ONLY."; return o end
    if c.enabled ~= true then o.why = "NOT AVAILABLE."; return o end
    local l = downList()
    if St.down then o.why = "YOU'RE DOWN."; return o end
    if #l == 0 then o.why = "NOBODY IS DOWN."; o.help = o.help .. " Nobody is down now."; return o end
    local t = l[1]
    o.slot = t.slot
    o.label = "REVIVE " .. name(t.slot) .. (#l > 1 and string.format(" (+%d)", #l - 1) or "")
    o.help = string.format("%s has been down %d s: buys them back, repaired, in the air. Revives this run: %d (each costs x%g more).",
        name(t.slot), math.floor(os.clock() - t.since), St.count, num(c.raise, 1))
    if St.pending[t.slot] then o.why = "ASKED: WAITING FOR THE HOST."; return o end
    o.price = priceFor(St.count)
    return o
end

-- (the host) a revive of slot by player `by` at `price`: checked, counted, told to everyone; true, or false and why
local function hostRevive(slot, by, price)
    local why = nil
    if not (COOP.slotOk(slot) and COOP.slotOk(by)) then why = "NO SUCH PLAYER"
    elseif slot == by then why = "NOT YOURSELF"
    elseif not isDown(slot) then why = "NOT DOWN"
    elseif St.reviving[slot] and os.clock() - St.reviving[slot] < REVIVING_S then why = "ALREADY BEING REVIVED"
    elseif price ~= priceFor(St.count) then why = "THE PRICE CHANGED: NOW " .. priceFor(St.count)
    elseif not onAirfield(by) then why = "NOT AT THE AIRFIELD" end
    if why then
        log(string.format("revive: player %s's revive of player %s refused: %s", tostring((tonumber(by) or -1) + 1),
            tostring((tonumber(slot) or -1) + 1), why))
        return false, why
    end
    St.count, St.reviving[slot], St.since[slot] = St.count + 1, os.clock(), nil
    COOP.msg(nil, "rb", slot, St.count, by)
    log(string.format("revive: player %d revived player %d for %d (the run's revive %d)", by + 1, slot + 1, price, St.count))
    LB.stat("revives", 1)
    if slot == mySlot() then DOWN.back("revived by " .. name(by))
    else callout(name(slot) .. " BACK", "REVIVED BY " .. name(by)) end
    return true
end

-- The REVIVE row pressed (sv_shop.lua shopBuy, the price checked against your zollars): true and the row's message (the
-- price is then charged), or false and why (nothing charged). A joiner asks the host and is refunded on its "rx".
function DOWN.buy(price)
    local o = DOWN.offer()
    if not o.price then return false, o.why or "NOT AVAILABLE." end
    if price ~= o.price then return false, "THE PRICE CHANGED: CHECK IT AND PRESS AGAIN." end
    local slot = o.slot
    if COOP.host() then
        local ok, why = hostRevive(slot, mySlot(), price)
        if not ok then return false, why .. "." end
        return true, "REVIVED " .. name(slot) .. "."
    end
    St.pending[slot] = { price = price, at = os.clock() }
    COOP.msg(0, "rv", slot, price)
    log(string.format("revive: asked the host to revive player %d for %d", slot + 1, price))
    return true, "REVIVE ASKED FOR " .. name(slot) .. ": THE HOST CONFIRMS IT."
end

---------------------------------------------------------------------------------------------------- the messages
local function rateOk(slot, max)                 -- (at most max a second from that game: MSG_PER_S a joiner, more the host)
    local now = os.clock()
    local r = St.rate[slot] or { at = now, n = 0 }
    St.rate[slot] = r
    if now - r.at >= 1 then r.at, r.n = now, 0 end
    r.n = r.n + 1
    return r.n <= (max or MSG_PER_S)
end
local function whole(v, lo, hi) v = tonumber(v); return (v and v == math.floor(v) and v >= lo and v <= hi) and v or nil end

-- (the host) a joiner's "dw" (it's down: told to everyone) or "rv" (it buys a revive)
function DOWN.onHost(from, f)
    if not (COOP.slotOk(from) and from ~= mySlot()) then return end
    if not rateOk(from) then logOnce("downrate" .. from, "revive: player " .. (from + 1) .. " sends too many; dropped"); return end
    local k = f[1]
    if k == "dw" then
        local slot = whole(f[2], 0, 23)
        if slot ~= from then logOnce("dwslot" .. from, "revive: player " .. (from + 1) .. " said another player is down; ignored"); return end
        local first = St.since[slot] == nil
        if first then St.reviving[slot] = nil end   -- (a new DOWN: the last revive's guard doesn't hold this one)
        St.since[slot] = St.since[slot] or os.clock()
        COOP.msg(nil, "dw", slot, St.count)
        if first then
            log(string.format("down: player %d (%s) is down", slot + 1, name(slot)))
            callout(name(slot) .. " DOWN", "LAND AND REVIVE THEM FROM THE STORE")
        end
    elseif k == "rv" then
        local slot, price = whole(f[2], 0, 23), num(f[3], nil)
        if not (slot and price) then COOP.msg(from, "rx", tostring(f[2] or ""):sub(1, 4), "A BAD REQUEST"); return end
        local ok, why = hostRevive(slot, from, price)
        if not ok then COOP.msg(from, "rx", slot, why, St.count) end
    end
end

-- (a joiner) the host's "dw", "rb", "rx" and "ro"
function DOWN.onJoiner(f)
    local k = f[1]
    if not rateOk(0, 60) and k ~= "ro" then logOnce("downrate0", "revive: the host sends too many; dropped"); return end
    local slot = whole(f[2], 0, 23)
    if k == "ro" then DOWN.runOver(whole(f[2], 0, 100000), "the host"); return end
    if k == "rc" then St.count = whole(f[2], 0, 100000) or St.count; return end
    if not slot then return end
    local n = whole(f[3], 0, 100000)
    if k == "dw" then
        if n then St.count = n end
        if slot ~= mySlot() then
            local first = St.since[slot] == nil
            St.since[slot] = St.since[slot] or os.clock()
            if first and f[4] ~= "q" then
                log(string.format("down: player %d (%s) is down", slot + 1, name(slot)))
                callout(name(slot) .. " DOWN", "LAND AND REVIVE THEM FROM THE STORE")
            end
        end
    elseif k == "rb" then
        local by = whole(f[4], 0, 23)
        if n then St.count = n end
        St.since[slot] = nil
        local mine = St.pending[slot]
        if mine and by == mySlot() then
            St.pending[slot] = nil
            if RUN then RUN.msg.Revive, RUN.dirty = "REVIVED " .. name(slot) .. ".", true end
        end
        log(string.format("revive: player %d revived by player %s (the run's revive %s)", slot + 1, by and tostring(by + 1) or "?", tostring(n)))
        if slot == mySlot() then DOWN.back("revived by " .. (by and name(by) or "a wingman"))
        else callout(name(slot) .. " BACK", by and ("REVIVED BY " .. name(by)) or nil) end
    elseif k == "rx" then
        local p = St.pending[slot]
        local why = upper(tostring(f[3] or ""):gsub("[%c|]", ""), 60)
        local cnt = whole(f[4], 0, 100000)
        if cnt then St.count = cnt end
        if p then
            St.pending[slot] = nil
            RUN.credits, RUN.spent, RUN.dirty = RUN.credits + p.price, math.max(0, RUN.spent - p.price), true
            RUN.msg.Revive = string.format("REFUSED: %s. %d REFUNDED.", why, p.price)
            log(string.format("revive: the host refused your revive of player %d (%s): %d refunded", slot + 1, why, p.price))
        end
    end
end

-- (the host) a joiner who links (or starts over) gets the room's count and who's down now, without the callouts
function DOWN.syncTo(to)
    COOP.msg(to, "rc", St.count)
    if St.down then COOP.msg(to, "dw", mySlot(), St.count, "q") end
    for _, e in ipairs(downList()) do if e.slot ~= to then COOP.msg(to, "dw", e.slot, St.count, "q") end end
end

---------------------------------------------------------------------------------------------------- the tick
-- (the host) every player in the mission down (present: you, and each other whose game says it's in the level and was
-- heard from in PRESENT_MS)
local function everyoneDown()
    local n, up = 0, 0
    for _, e in ipairs(COOP.players()) do
        if e.isMe or (e.inLevel and num(e.age, 1e9) < PRESENT_MS) then
            n = n + 1
            if e.alive ~= false then up = up + 1 end
        end
    end
    return n >= 1 and up == 0, n
end

-- Each pass (sv_main.lua, after INS.tick and its floor)
function DOWN.tick()
    if not D then return end
    local now = os.clock()
    local pawn = pawnOf()
    if St.safeUntil then
        if now >= St.safeUntil then
            St.safeUntil = nil
            if valid(pawn) then pcall(function() pawn:SetIsInvincible(false) end) end
        elseif valid(pawn) then pcall(function() pawn:SetIsInvincible(true) end) end
    end
    if St.respawnAt and now >= St.respawnAt.at then         -- where the way back put you, against where it was asked
        local want, at = St.respawnAt, playerLocation()
        St.respawnAt = nil
        if at then log(string.format("revive: respawn d=%.0f m", km(at, want) * 1000)) end
    end
    if St.restore and valid(pawn) then                      -- (a restart while you were down)
        local okR, errR = pcall(restoreAfter, pawn)
        if not okR then St.restore = nil; log("down: after the restart: error " .. tostring(errR)) end
    end
    if St.down then
        if valid(pawn) then
            pcall(function() pawn:SetIsInvincible(true) end)
            local okE, errE = pcall(edgeGuard, pawn, now)
            if not okE then logOnce("edgeGuard", "down: the zone's edge: error " .. tostring(errE)) end
            if addrOf(pawn) ~= St.loiterAddr then              -- (another plane: out of the fight and flown again)
                St.saved = select(1, outOfFight(pawn))
                St.loiterAddr = addrOf(pawn)
                log("down: your plane changed while down; flown again: " .. tostring(loiter(pawn)))
            elseif now >= (St.loiterAt or 0) then               -- (again every 5 s: the runtime only moves the circle)
                St.loiterAt = now + 5
                local r = loiter(pawn)
                if r ~= "on" and r ~= St.loiterSaid then St.loiterSaid = r; log("down: the loiter again: " .. r) end
            end
            if now >= (St.logAt or 0) then
                St.logAt = now + ((now - (St.downAt or now)) < 60 and 5 or 30)
                local at = playerLocation()
                if at then
                    local dx, dy = at.X - AIRFIELD.X, at.Y - AIRFIELD.Y
                    log(string.format("down: loiter %.1f km / %.0f m (from the airfield / up), %s m/s; watching %s", math.sqrt(dx * dx + dy * dy) / 100000,
                        at.Z / 100, St.speed and string.format("%.0f", St.speed) or "?", St.watch and St.watch.name or "nobody"))
                end
            end
        end
        local okM, errM = pcall(motionTick, now)
        if not okM then logOnce("motionTick", "down: motion error " .. tostring(errM)) end
        local okS, errS = pcall(spectateTick, now)
        if not okS then logOnce("spectateTick", "spectate: error " .. tostring(errS)) end
    elseif valid(pawn) and not St.ended and (St.testDown or (rc().enabled == true and linked() and D.round and D.round >= 1)) then
        local okH, h = pcall(function() return pawn.HealthInternal end)
        local fl = num(rc().floor_hp, 0.1) * 10
        if okH and type(h) == "number" and h > 0 and h <= fl + 0.01 and not RUN.insured then goDown(pawn, h) end
    end
    -- TEST ONLY BEGIN (T1, Ctrl+F6: the floor solo, once a second)
    if St.testFloor and valid(pawn) and now >= (St.testLogAt or 0) then
        St.testLogAt = now + 1
        local okH, h = pcall(function() return pawn.HealthInternal end)
        local okM, m = pcall(function() return pawn.MinHealth end)
        log(string.format("down-test: health %s (floor %s), MinHealth %s", okH and string.format("%.1f", h / 10) or "?",
            tostring(rc().floor_hp), okM and tostring(m) or "?"))
    end
    -- TEST ONLY END
    if not (COOP and COOP.open) then return end
    if now >= (St.listAt or 0) then                         -- (the STORE's REVIVE row follows who's down: once a second)
        St.listAt = now + 1
        local key = {}
        for _, e in ipairs(downList()) do key[#key + 1] = e.slot end
        key = table.concat(key, ",") .. "/" .. St.count .. (St.down and "/me" or "")
        if key ~= St.listKey then St.listKey, RUN.dirty = key, true end
    end
    if COOP.host() then
        for slot, t in pairs(St.reviving) do if now - t >= REVIVING_S then St.reviving[slot] = nil end end
        -- (not only while another game is linked: the last joiner gone with you down ends it too)
        local all, n = false, 0
        if rc().enabled == true and not St.ended and (St.down or linked()) then all, n = everyoneDown() end
        if all then
            St.allDownAt = St.allDownAt or now
            if now - St.allDownAt >= RO_CONFIRM_S then
                COOP.msg(nil, "ro", D.round or 0)
                log(string.format("down: every player in the mission is down (%d) for %d s: the run's over for everyone", n, RO_CONFIRM_S))
                DOWN.runOver(D.round, "every player down")
            end
        else
            St.allDownAt = nil
        end
    else
        if St.down and not linked() then                   -- (down, the host's link gone: nobody can revive you)
            St.lostAt = St.lostAt or now
            if now - St.lostAt >= PENDING_S then DOWN.runOver(D.round, "you're down and the host's link is gone") end
        else
            St.lostAt = nil
        end
        for slot, p in pairs(St.pending) do                -- (no answer: refunded)
            if now - p.at >= PENDING_S then
                St.pending[slot] = nil
                RUN.credits, RUN.spent, RUN.dirty = RUN.credits + p.price, math.max(0, RUN.spent - p.price), true
                RUN.msg.Revive = string.format("NO ANSWER FROM THE HOST. %d REFUNDED.", p.price)
                log(string.format("revive: no answer from the host on player %d's revive in %d s: %d refunded", slot + 1, PENDING_S, p.price))
            end
        end
    end
end

-- TEST ONLY BEGIN (T1 Ctrl+F6, T2 Ctrl+END: sv_main.lua; tools/re/COOP.md 9)
-- T1: the floor solo, on and off (down-test: lines once a second)
function DOWN.testFloor()
    St.testFloor = not St.testFloor
    log("down-test: T1 the floor solo " .. (St.testFloor and ("on (floor_hp " .. tostring(rc().floor_hp) .. ")") or "off"))
    callout("TEST T1: FLOOR " .. (St.testFloor and "ON" or "OFF"), St.testFloor and ("HELD AT " .. tostring(rc().floor_hp) .. " HP") or nil)
end
-- T2: each press the next step, solo: 1 DOWN (watching MOONCHILD / VIPER or an enemy; the key the next), 2 back by the
-- loiter, 3 DOWN again, 4 back by SV_Respawn
function DOWN.testDown()
    local pawn = pawnOf()
    if not valid(pawn) then log("down-test: T2 without a plane"); return end
    St.testStep = (St.testStep or 0) % 4 + 1
    local s = St.testStep
    if s == 1 or s == 3 then
        St.testDown = true
        local okH, h = pcall(function() return pawn.HealthInternal end)
        goDown(pawn, okH and h or 0)
        log("down-test: T2 step " .. s .. ": down")
    else
        DOWN.back("test T2 step " .. s, s == 2 and "loiter" or "native")
        St.testDown = nil
        log("down-test: T2 step " .. s .. ": back by " .. (s == 2 and "the loiter" or "SV_Respawn"))
    end
end
-- TEST ONLY END

-- The next-player key (CFG.coop.revive key / ctrl): each player's own; only while you're down. A key UE4SS doesn't know
-- leaves the camera on the next player by itself.
do
local c = rc()
if CFG.coop.enabled and c.enabled and type(RegisterKeyBind) == "function" and Key then
    local k = Key[string.upper(tostring(c.key or "O"))]
    local mods = (c.ctrl and ModifierKey and ModifierKey.CONTROL) and { ModifierKey.CONTROL } or {}
    if k == nil then
        log("revive: next-player key '" .. tostring(c.key) .. "' isn't a key name UE4SS knows: [coop.revive] key")
    else
        local ok, err = pcall(RegisterKeyBind, k, mods, function()
            ExecuteInGameThread(function()
                local okN, errN = pcall(DOWN.nextView, "key")
                if not okN then log("spectate: key error " .. tostring(errN)) end
            end)
        end)
        log("revive: next-player key " .. keyLabel() .. (ok and " bound" or (" not bound: " .. tostring(err))))
    end
end
end
end
