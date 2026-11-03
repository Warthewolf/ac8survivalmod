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
-- (0.73.73) after a revive the weapons are watched this long (armTick): a lock the game puts back is taken off again
local ARM_WATCH_S = 10
-- (0.73.73) parked: on the ground at your airfield in co-op (parkedTick): under PARK_Z_CM and slower than GROUND_MS when
-- the game's IsOnGround can't be read; the guard's off PARK_OFF_S after you leave the ground
local PARK_Z_CM, PARK_OFF_S = 3000, 1
local INPUTS = { { "bEnableWeaponInput", false }, { "bEnableFlareInput", false }, { "bIsWeaponSystemDisabled", true } }
local ATTACKERS = { "MaxPlaneAttackerMissiles", "MaxPursuitAttackers", "MaxNonPlaneAttackerMissiles" }
-- "native" respawn: 4 km out from the runway along its heading (Comona's runway, yaw -23: the takeoff's way), 500 m up
local RUNWAY = { X = 1609574.0, Y = -435747.0, yaw = -23, out_cm = 400000, z_cm = 50000 }
local St = { down = false, since = {}, count = 0, pending = {}, reviving = {}, cams = {}, rate = {}, reverts = 0 }
DOWN.St = St                                    -- (the offline test's)

local function rc() local c = CFG.coop and CFG.coop.revive; return type(c) == "table" and c or {} end
local function pawnOf() return survivalPC and liveObj(survivalPC) and survivalPC.Pawn or nil end
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

-- Revives on: co-op open with another game linked, in a run
function DOWN.active() return rc().enabled == true and D ~= nil and linked() end
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
    return l
end
-- a camera on plane e.obj: a CameraComponent added once (kept by its address), back_m behind and up_m above, looking at it
local function camOn(obj)
    local a = addrOf(obj)
    local have = a and St.cams[a]
    if have and liveObj(have) then return have end                -- (0.73.73: liveObj on what's kept between ticks)
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
    if not (survivalPC and liveObj(survivalPC) and liveObj(target)) then return false end
    return pcall(function() survivalPC:SetViewTargetWithBlend(target, blend or 0, 0, 0, false) end)
end
-- A player plane (COOP2MP's real planes: the ADFX-02 has no AI stand-in) carries cameras of its own, and the view on an
-- actor takes the first active camera on it: the user's co-op run of 2026-10-30, watching CRESSENDO's real ADFX-02,
-- "spawned the camera inside the aircraft". So while you watch a plane, its other cameras are switched off (St.hushed),
-- and back on as the view leaves it.
local function unhush()
    for _, c in ipairs(St.hushed or {}) do
        if liveObj(c) then pcall(function() c:Activate(false) end) end
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
-- The spectator camera, the replay viewer's way (the user, 2026-10-30: "can you make it like the Replay Actor? except
-- without the ability to time skip"): AC8's replay third-person camera is a camera on a spring arm, trailing the plane
-- with lag; here a camera actor of ours (SV_SpawnCam, runtime 0.32.1) at the end of a SpringArmComponent added to the
-- watched plane (one arm a plane, kept; one camera actor, moved from arm to arm). Your stick (SV_StickNow: your own
-- input, under DOWN's autopilot) swings it round the plane, throttle / brake zoom in and out; the arm's lag smooths the
-- 4-a-second steps. The view is on the camera actor, never on the plane: on a player plane (COOP2MP's real planes) the
-- view takes the game's own player-plane camera whatever is added to it (the co-op run of 2026-10-30: our camera
-- measured 31 m behind CRESSENDO's real ADFX-02, the view inside it). Without SV_SpawnCam, the added camera as before.
local ORBIT_DEG_S, ZOOM_M_S, DEAD = 110, 40, 0.15
local function orbit()
    if not St.orbit then
        local cam = rc().camera or {}
        local back, up = num(cam.back_m, 30), num(cam.up_m, 8)
        St.orbit = { yaw = 0, pitch = -math.deg(math.atan(up, back)), len = math.sqrt(back * back + up * up) * 100 }
    end
    return St.orbit
end
local function armOn(obj)
    local a = addrOf(obj)
    St.arms = St.arms or {}
    local have = a and St.arms[a]
    if have and liveObj(have) then return have end
    local cls = StaticFindObject("/Script/Engine.SpringArmComponent")
    if not valid(cls) then return nil, "no SpringArmComponent class" end
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, arm = pcall(function() return obj:AddComponentByClass(cls, false, t, false) end)
    if not ok or not valid(arm) then return nil, "AddComponentByClass " .. (ok and "gave nothing" or tostring(arm)) end
    for k, v in pairs({ bDoCollisionTest = false, bUsePawnControlRotation = false, bInheritPitch = true, bInheritYaw = true,
                        bInheritRoll = false, bEnableCameraLag = true, CameraLagSpeed = 12.0, bEnableCameraRotationLag = true,
                        CameraRotationLagSpeed = 7.0 }) do
        pcall(function() arm[k] = v end)
    end
    -- (the arm's pivot on the middle of the plane, not its root: the user, 2026-10-30, watching the ADFX-02 and the
    -- X-40A: "centre it more on the aircraft, it's sitting behind slightly"; a player plane's root sits aft of its middle)
    local o, e = {}, {}
    local okB = pcall(function() obj:GetActorBounds(false, o, e, false) end)
    local okR, q = pcall(function() local v = obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if okB and type(o.X) == "number" and type(o.Y) == "number" and type(o.Z) == "number" and okR and q and type(q.X) == "number" then
        local d = math.sqrt((o.X - q.X) ^ 2 + (o.Y - q.Y) ^ 2 + (o.Z - q.Z) ^ 2)
        if d > 1 and d < 5000 then                     -- (50 m at most: bounds that take in something else aren't the plane's)
            local okW = pcall(function() arm:K2_SetWorldLocation({ X = o.X, Y = o.Y, Z = o.Z }, false, {}, true) end)
            log(string.format("spectate: %s's middle is %.1f m from its root: the camera's pivot moved there%s",
                nameOf(obj):match("([%w_]+)$") or "?", d / 100, okW and "" or " (FAILED)"))
        end
    else
        log("spectate: " .. (nameOf(obj):match("([%w_]+)$") or "?") .. "'s bounds can't be read: the camera pivots on its root")
    end
    if a then St.arms[a] = arm end
    return arm
end
local function applyOrbit(arm)
    local o = orbit()
    pcall(function() arm.TargetArmLength = o.len end)
    pcall(function() arm:K2_SetRelativeRotation({ Pitch = o.pitch, Yaw = o.yaw, Roll = 0 }, false, {}, true) end)
end
local function rigOn(obj)
    if type(SV_SpawnCam) ~= "function" then return nil, "dlls/main.dll has no SV_SpawnCam (runtime 0.32.1)" end
    local arm, err = armOn(obj)
    if not arm then return nil, err end
    local actor = St.camActor
    if not liveObj(actor) then
        actor = nil
        local okL, q = pcall(function() local v = obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
        if not (okL and q and type(q.X) == "number") then return nil, "its place can't be read" end
        -- (0.73.73: not while the walks are held, walkHold: the camera actor spawned couldn't be found, and stayed)
        if type(walkHold) == "function" and walkHold() then return nil, "the walks over every object are held" end
        local ca = SV_SpawnCam(q.X, q.Y, q.Z + 3000)
        if type(ca) ~= "number" or ca <= 0 then return nil, "SV_SpawnCam " .. tostring(ca) end
        for _, x in ipairs(FindAllOf("CameraActor") or {}) do if valid(x) and addrOf(x) == ca then actor = x end end
        if not actor then return nil, "its camera actor wasn't found" end
        pcall(function() actor.CameraComponent.bConstrainAspectRatio = false end)
        St.camActor = actor
    end
    applyOrbit(arm)
    -- (at the arm's end and turned with it: EAttachmentRule SnapToTarget for location and rotation, KeepWorld scale)
    local okA = pcall(function() actor:K2_AttachToComponent(arm, FName("SpringEndpoint"), 2, 2, 1, false) end)
    if not okA then return nil, "it wouldn't attach to the arm" end
    St.rigSaid = St.rigSaid or {}
    local a = addrOf(obj)
    if a and not St.rigSaid[a] then
        St.rigSaid[a] = true
        log(string.format("spectate: replay-style camera on %s (arm %.0f m, your stick swings it, throttle / brake zoom)",
            nameOf(obj):match("([%w_]+)$") or "?", orbit().len / 100))
    end
    return actor
end
-- each pass while watching: your stick turns the camera round the plane, throttle / brake zoom
local function orbitTick(now)
    local w = St.watch
    local arm = w and St.arms and St.arms[w.addr]
    local dt = math.min(0.5, math.max(0, now - (St.orbitAt or now)))
    St.orbitAt = now
    if not (arm and liveObj(arm) and w.viewAddr and w.viewAddr ~= w.addr) or type(SV_StickNow) ~= "function" then return end
    local okS, s = pcall(SV_StickNow)
    if not (okS and type(s) == "string") then return end
    local v = {}
    for x in s:gmatch("[^,]+") do v[#v + 1] = (tonumber(x) or 0) / 1000 end
    if #v < 5 then return end
    local function dz(x) return math.abs(x) < DEAD and 0 or x end
    local o = orbit()
    local turn, lift, zoom = dz(v[3]) + dz(v[2]), dz(v[1]), dz(v[5]) - dz(v[4])
    -- (each axis's first move logged, and the most each read a minute: whether your stick reaches the camera)
    St.stickMax = St.stickMax or { 0, 0, 0, 0, 0 }
    St.stickSaid = St.stickSaid or {}
    local AX = { "pitch (camera up / down)", "yaw (camera round)", "roll (camera round)", "throttle (zoom in)", "brake (zoom out)" }
    for i = 1, 5 do
        St.stickMax[i] = math.max(St.stickMax[i], math.abs(v[i]))
        if math.abs(v[i]) >= DEAD and not St.stickSaid[i] then
            St.stickSaid[i] = true
            log(string.format("spectate: your stick's %s moves the camera (%.2f)", AX[i], v[i]))
        end
    end
    if now >= (St.stickLogAt or now + 60) then
        log(string.format("spectate: the minute's stick, most each axis: pitch %.2f, yaw %.2f, roll %.2f, throttle %.2f, brake %.2f",
            table.unpack(St.stickMax)))
        St.stickMax = { 0, 0, 0, 0, 0 }
        St.stickLogAt = now + 60
    end
    St.stickLogAt = St.stickLogAt or now + 60
    if turn == 0 and lift == 0 and zoom == 0 then return end
    o.yaw = (o.yaw + turn * ORBIT_DEG_S * dt + 180) % 360 - 180
    o.pitch = math.max(-85, math.min(85, o.pitch + lift * ORBIT_DEG_S * 0.8 * dt))
    o.len = math.max(1000, math.min(15000, o.len + zoom * ZOOM_M_S * 100 * dt))
    applyOrbit(arm)
end
local function view(e, why)
    local cam, err, target = rigOn(e.obj)
    if cam then
        target = cam
    else
        St.rigErr = St.rigErr or {}
        if not St.rigErr[tostring(err)] then St.rigErr[tostring(err)] = true; log("spectate: no replay-style camera (" .. tostring(err) .. "): the added one") end
        target = e.obj
        cam, err = camOn(e.obj)
        hush(e.obj, cam)
    end
    e.viewAddr = addrOf(target)
    local ok = setView(target, num((rc().camera or {}).blend_s, 0.5))
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
    if h and not h.pawn and liveObj(h.obj) then setView(h.obj, blend)
    elseif liveObj(pawn) then setView(pawn, blend) end
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
        if okV and addrOf(vt) ~= (w.viewAddr or w.addr) then
            St.reverts = St.reverts + 1
            local t = w.viewAddr ~= w.addr and St.camActor
            setView((t and liveObj(t)) and t or w.obj, 0)
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
    if St.watch then
        return string.format("DOWN: WATCHING %s  [%s] NEXT%s", St.watch.name, keyLabel(),
            (St.watch.viewAddr and St.watch.viewAddr ~= St.watch.addr) and "  STICK: CAMERA  THROTTLE/BRAKE: ZOOM" or "")
    end
    return "DOWN: WAITING FOR A REVIVE"
end

---------------------------------------------------------------------------------------------------- down and back
-- (0.73.73) The weapons as a flying plane has them: DOWN's INPUTS the other way, and the target change (a landing's lock
-- may take it too); each only where it reads as a boolean that differs. Then the game's own DisableWeaponSystem(false)
-- (LivePlayerPlane, BlueprintCallable). Returns what changed ("<field> <was> -> <now>") and whether that call ran.
local ARMED = { { "bEnableWeaponInput", true }, { "bEnableFlareInput", true }, { "bIsWeaponSystemDisabled", false },
                { "bEnableChangeTargetInput", true } }
local function arm(pawn)
    local parts = {}
    for _, f in ipairs(ARMED) do
        local okR, v = pcall(function() return pawn[f[1]] end)
        if okR and type(v) == "boolean" and v ~= f[2] then
            local okW = pcall(function() pawn[f[1]] = f[2] end)
            parts[#parts + 1] = string.format("%s %s -> %s%s", f[1], tostring(v), tostring(f[2]), okW and "" or " FAILED")
        end
    end
    local okD = pcall(function() pawn:DisableWeaponSystem(false) end)
    return parts, okD
end
-- whether the weapons are locked now (any of DOWN's three, or the game's IsWeaponSystemDisabled), and how
local function lockedNow(pawn)
    local why = {}
    for _, f in ipairs(INPUTS) do
        local okR, v = pcall(function() return pawn[f[1]] end)
        if okR and type(v) == "boolean" and v == f[2] then why[#why + 1] = f[1] .. " " .. tostring(v) end
    end
    local okI, dis = pcall(function() return pawn:IsWeaponSystemDisabled() end)
    if okI and dis == true then why[#why + 1] = "IsWeaponSystemDisabled" end
    return #why > 0, table.concat(why, ", ")
end
-- the landing gear: true down, false up, nil can't tell; and its rate (GetGearDownRate, 0 up .. 1 down) when read
local function gearDown(pawn)
    local ok, r = pcall(function() return pawn:GetGearDownRate() end)
    if ok and type(r) == "number" then return r > 0.5, r end
    local okV, vis = pcall(function() return pawn.LandingGearOnMesh:IsVisible() end)   -- (sv_coop.lua's gear watch)
    if okV and type(vis) == "boolean" then return vis, nil end
    return nil, nil
end
-- your plane out of the fight; what it had, for the way back
local function outOfFight(pawn)
    local s, parts = { inputs = {}, attackers = {} }, {}
    pcall(function() pawn:SetIsInvincible(true) end)
    parts[#parts + 1] = pcall(function() pawn:SetActorHiddenInGame(true) end) and "hidden" or "hidden FAILED"
    parts[#parts + 1] = pcall(function() pawn:SetActorEnableCollision(false) end) and "no collision" or "collision FAILED"
    for _, f in ipairs(INPUTS) do                   -- (0.73.73: what it was logged too; never put back, ARMED is)
        local okR, v = pcall(function() return pawn[f[1]] end)
        local okW = okR and pcall(function() pawn[f[1]] = f[2] end)
        if okW then s.inputs[f[1]] = v end
        parts[#parts + 1] = f[1] .. " " .. (okR and (tostring(v) .. " -> ") or "") .. tostring(f[2]) .. (okW and "" or " FAILED")
    end
    local gd, rate = gearDown(pawn)
    local okG, og = pcall(function() return pawn:IsOnGround() end)
    s.gear, s.ground = gd, (okG and og == true) or nil
    parts[#parts + 1] = "gear " .. (gd == nil and "?" or (gd and "DOWN" or "up")) .. (rate and string.format(" (%.2f)", rate) or "")
        .. (s.ground and ", on the ground" or "")
    for _, f in ipairs(ATTACKERS) do                -- (the enemies' limits on attacking you: guesses, untested)
        local okR, v = pcall(function() return pawn[f] end)
        local okW = okR and type(v) == "number" and pcall(function() pawn[f] = 0 end)
        if okW then s.attackers[f] = v end
        parts[#parts + 1] = f .. (okW and (" " .. tostring(v) .. " -> 0") or " FAILED")
    end
    return s, table.concat(parts, ", ")
end
-- Back in the fight: shown, collision, the attackers' limits, and the weapons armed as a flying plane's (ARMED, arm())
-- whatever DOWN found. (0.73.73: they were put back as DOWN found them, and a plane down with its gear out at the airfield
-- had the landing's lock on then, weapons and flares off until the gear's raised there: the revive put that lock back.
-- Shazzy, A04: down 13:36:53 0.9 km from the airfield, 41 m up, gear out since 13:36:45; revived 13:38:07, "unable to
-- shoot", no shot sent until he landed and rearmed; cressendo, A10: gear out 11:26:11, down 11:26:15 at 16 m, revived
-- 11:26:55, locked until he lowered and raised the gear at 11:27:14-22 ("reviving an ally with their landing gears out
-- will lock their fcs"). Shazzy's revive of 13:00:17, down in the air with the gear up, fired at once.) Returns what
-- arm() changed and whether DisableWeaponSystem(false) ran.
local function backInFight(pawn, s)
    if not liveObj(pawn) then return {}, false end
    pcall(function() pawn:SetActorHiddenInGame(false) end)
    pcall(function() pawn:SetActorEnableCollision(true) end)
    local parts, okD = arm(pawn)
    for f, v in pairs(s and s.attackers or {}) do              -- (unless something set its own meanwhile: a pressure preset)
        pcall(function() if pawn[f] == 0 then pawn[f] = v end end)
    end
    return parts, okD
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

-- (0.73.73, DOWN.back after the plane's placed) Out of the landing it went down in, weapons armed, gear up: what lowering
-- and raising the gear at an airfield did for cressendo (A10). A plane DOWN found with its gear out or on the ground
-- (saved.gear / saved.ground: outOfFight) has the game's landing state cancelled first (CancelLanding(true), the plane's
-- own BlueprintCallable); then the weapons armed again (arm(): SV_Respawn may have reset them); the gear key pressed if
-- the gear's still down (let go the next pass); then ARM_WATCH_S watched (armTick: a lock the game puts back taken off,
-- the gear read 2 s on). Not yet run in game: the game's landing lock is reverse engineered only this far.
local function rearm(pawn, saved, before)
    saved = saved or {}
    if not liveObj(pawn) then St.arm = nil; return end
    local landed = saved.gear == true or saved.ground == true
    local cancel = "not needed"
    if landed then
        local okC = pcall(function() pawn:CancelLanding(true) end)
        cancel = okC and "called" or "not callable"
    end
    local armed, okD = arm(pawn)
    for i, x in ipairs(before or {}) do table.insert(armed, i, x) end      -- (what backInFight changed first)
    local gd, rate = gearDown(pawn)
    local pressed = false
    if gd == true then pressed = pcall(function() pawn:OnGearPressed() end) end
    St.arm = { untilT = os.clock() + ARM_WATCH_S, relocks = 0, release = pressed, gearAt = os.clock() + 2, pressed = pressed }
    local found = {}
    for _, f in ipairs(INPUTS) do found[#found + 1] = f[1] .. " " .. tostring((saved.inputs or {})[f[1]]) end
    log(string.format("revive: your weapons armed: %s; DisableWeaponSystem(false) %s; the landing cancelled: %s (DOWN found %s, "
        .. "gear %s%s); the gear now %s%s%s",
        #armed > 0 and table.concat(armed, ", ") or "nothing to change", okD and "called" or "not callable", cancel,
        table.concat(found, ", "), saved.gear == nil and "?" or (saved.gear and "DOWN" or "up"),
        saved.ground and ", on the ground" or "", gd == nil and "?" or (gd and "DOWN" or "up"),
        rate and string.format(" (%.2f)", rate) or "", gd == true and (pressed and ": raised (the gear key)" or ": the gear key FAILED") or ""))
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
    local saved = St.saved or {}
    local armedFirst = backInFight(pawn, St.saved)
    St.saved = nil
    viewSelf()
    St.home = nil
    local r = type(SV_Event) == "function" and SV_Event("RE_SV_RepairAircraft") or -5
    if valid(pawn) and UP and UP.healthGuard then pcall(UP.healthGuard, pawn, "the revive's repair") end   -- ((0.73.77) G2)
    local okW = valid(pawn) and pcall(function() pawn.HealthInternal = math.floor(pawn.MaxHealth * 10 + 0.5) end)
    St.safeUntil = os.clock() + num(rc().safe_s, 5)
    if valid(pawn) then pcall(function() pawn:SetIsInvincible(true) end) end
    local where = respawn or tostring(rc().respawn or "loiter")
    local placed, why = "where the loiter left you", ""
    if where ~= "native" and onGround then          -- (crashed: where it lies is the ground)
        where, why = "native", string.format(" (your plane wasn't flying: %.0f m/s)", St.speed or 0)
    end
    -- (the loiter that drifted off: back by the airfield, not out there. The user's co-op run of 2026-10-30: the autopilot
    -- held its bank but never turned, drifting 15 -> 38 km out, and the revive put them "half way across the map near the
    -- border". near_km in [coop.revive], 8 by default)
    local at = where ~= "native" and playerLocation() or nil
    local farKm = at and math.sqrt((at.X - AIRFIELD.X) ^ 2 + (at.Y - AIRFIELD.Y) ^ 2) / 100000 or 0
    if at and farKm > num(rc().near_km, 8) then
        where, why = "native", string.format(" (the loiter had left you %.1f km from the airfield)", farKm)
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
    pcall(rearm, pawn, saved, armedFirst)           -- (0.73.73: after the placement, SV_Respawn's too)
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
    -- (the host's level reloads now: its joiners wait for it instead of finding a new host, host migration)
    if COOP and COOP.hostAway then pcall(COOP.hostAway, 120) end
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
            St.restore = { addr = St.loiterAddr, saved = St.saved, home = St.home, watch = St.watch and St.watch.addr,
                          watchView = St.watch and St.watch.viewAddr, at = os.clock() }
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
    St.arm = nil                                                -- (0.73.73: no revive's watch over the next run's plane)
    St.wasIn, St.heldFor = nil, nil                             -- ((0.73.77) A8: everyone loads in again)
end
-- (0.73.77, plan F1b) the level torn down (sv_core.lua levelGate, the runtime's teardown gate): the level's objects DOWN
-- keeps are forgotten, none of them touched (the plane watched, the cameras on it switched off, the spectator's camera
-- actor, the cameras found): Shazzy's quit crash of 2026-11-02 came while DOWN and spectating
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS.down = function(why)
        local n = (St.watch and 1 or 0) + #(St.hushed or {}) + (St.camActor and 1 or 0)
        St.watch, St.hushed, St.camActor, St.cams = nil, {}, nil, {}
        if n > 0 then log(string.format("down: %s: the plane watched and its cameras forgotten (%d objects, none touched)", tostring(why), n)) end
    end
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
    local onWatch = va ~= nil and (va == r.watch or va == r.watchView or va == addrOf(St.camActor))   -- (or our camera)
    if va == nil or onWatch or va == addrOf(survivalPC) then
        St.home = r.home
        viewSelf(0)
        St.home = nil
        parts[#parts + 1] = "the view was " .. (va == nil and "nowhere" or onWatch and "still on the plane you watched" or "on the controller")
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
    if now < (St.edgeAt or 0) then return end
    local at = playerLocation()
    if not at then return end
    -- (also a plane drifted far from the airfield: the loiter's autopilot holds its bank but AC8's planes don't turn from
    -- bank alone, and in the user's co-op run of 2026-10-30 it drifted 15 -> 38 km out; drift_km in [coop.revive])
    local farKm = math.sqrt((at.X - AIRFIELD.X) ^ 2 + (at.Y - AIRFIELD.Y) ^ 2) / 100000
    local edge = ZONE and (ZONE.HALF - math.max(math.abs(at.X - ZONE.X), math.abs(at.Y - ZONE.Y))) or math.huge
    local drifted = farKm > num(rc().drift_km, 10)
    if edge >= EDGE_CM and not drifted then return end
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
    log(string.format("down: your plane was %s, %.0f m up: put back over the airfield, %.0f m up (SV_Respawn: %s); %s",
        edge < EDGE_CM and string.format("%.1f km from the combat zone's edge", (edge + 300000) / 100000)
        or string.format("%.1f km from the airfield", farKm), at.Z / 100, z / 100, rr, did))
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
    LB.stat("revives", 1, by)                       -- ((0.73.77) by: the co-op run's squad, revives given)
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

---------------------------------------------------------------------------------------------------- after a revive, parked
-- (0.73.73, each pass for ARM_WATCH_S after a revive) the gear key let go a pass after its press; the gear read 2 s on;
-- a lock the game puts back on the weapons taken off again (arm()), and on its second return the game's landing
-- state cancelled (CancelLanding(true): the lock is the landing's), never on or over your airfield or with the gear down
-- (a landing of yours); the outcome logged at the end
local function armTick(pawn, now)
    local a = St.arm
    if not a then return end
    if St.down or not liveObj(pawn) then St.arm = nil; return end
    if a.release then a.release = false; pcall(function() pawn:OnGearReleased() end) end
    local gd, rate = nil, nil
    if a.gearAt and now >= a.gearAt then
        a.gearAt = nil
        gd, rate = gearDown(pawn)
        if a.pressed or gd then
            log(string.format("revive: your gear 2 s after the revive: %s%s", gd == nil and "?" or (gd and "DOWN" or "up"),
                rate and string.format(" (%.2f)", rate) or ""))
        end
    end
    local landing = playerOnAirfield() == true
    if not landing then
        if gd == nil then gd = gearDown(pawn) end
        landing = gd == true and not a.pressed
    end
    local locked, how = lockedNow(pawn)
    if locked and not landing then
        a.relocks = a.relocks + 1
        local parts, okD = arm(pawn)
        local cancel = ""
        if a.relocks == 2 then
            local okC = pcall(function() pawn:CancelLanding(true) end)
            cancel = okC and "; the game's landing cancelled (CancelLanding(true))" or "; CancelLanding(true) not callable"
        end
        if a.relocks <= 3 then
            log(string.format("revive: the game locked your weapons again (%s): armed again (%s; DisableWeaponSystem(false) %s)%s",
                how, #parts > 0 and table.concat(parts, ", ") or "nothing to change", okD and "called" or "not callable", cancel))
        end
        locked = lockedNow(pawn)
    end
    if now >= a.untilT then
        St.arm = nil
        log(string.format("revive: your weapons %d s after the revive: %s (locked again by the game %d times)%s", ARM_WATCH_S,
            locked and ("LOCKED: " .. how) or "armed", a.relocks, landing and "; you're landing: left to the game" or ""))
    end
end
-- (0.73.73, each pass) Parked at your airfield in co-op: your plane invincible while it's on the ground there (the game's
-- IsOnGround, else under PARK_Z_CM and slower than GROUND_MS; or nowhere to be read, the landing menu's), off PARK_OFF_S
-- after it leaves the ground. Stock AC8 freezes every AI object while the landing menu is open (the minigame, the STORE
-- freeze), but with other players linked the world runs on (0.73.72, [coop] store_keep_world), and nothing protects you
-- taxiing or waiting on the runway either: Shazzy (A02, a joiner) left the STORE at 11:24:25 and sat at 7 m, 0 m/s, until
-- an Su-33's missiles took him to the floor at 11:24:37-41 (4 hits); the host's game already takes its flights off a
-- player landed at their airfield ("is landed at their airfield: onto ..."), but a joiner's copies aim at it there.
-- [coop.revive] parked_safe = false turns it off. A SECOND CHANCE's or a revive's invincibility is left to run out.
local function parkedTick(pawn, now)
    local on = false
    if rc().parked_safe ~= false and linked() and not St.down and liveObj(pawn) and playerOnAirfield() then
        local okG, g = pcall(function() return pawn:IsOnGround() end)
        local at = playerLocation()
        local m = St.parkM
        if at and (not m or now - m.t >= 0.5) then
            if m and now > m.t then St.parkSpeed = km(at, m) * 1000 / (now - m.t) end
            St.parkM = { X = at.X, Y = at.Y, Z = at.Z, t = now }
        end
        -- (0.73.73 review) an unreadable location (the landing menu) keeps a parked plane's protection but never grants
        -- one: stale reads mid-fight made you invincible anywhere (playerOnAirfield says yes to an unreadable location)
        if at == nil then
            on = St.parked ~= nil
        else
            on = (okG and g == true) or (St.parkSpeed ~= nil and St.parkSpeed < GROUND_MS and at.Z < PARK_Z_CM)
        end
    end
    local a = liveObj(pawn) and addrOf(pawn) or nil
    if on then
        St.parkOffAt = nil
        if not St.parked or St.parked.addr ~= a then
            St.parked = { at = now, addr = a }
            log("airfield: on the ground at your airfield (co-op: the world runs on): invincible until you're off it")
        end
        pcall(function() pawn:SetIsInvincible(true) end)
    elseif St.parked then
        St.parkOffAt = St.parkOffAt or now
        if now - St.parkOffAt >= PARK_OFF_S then
            local held = St.down or St.safeUntil ~= nil or (INS ~= nil and INS.safeUntil ~= nil)
            if not held and a and St.parked.addr == a then pcall(function() pawn:SetIsInvincible(false) end) end
            log(string.format("airfield: off the ground after %.0f s: invincible off%s", now - St.parked.at,
                held and " (a revive's, a SECOND CHANCE's or DOWN's left on)" or ""))
            St.parked, St.parkOffAt, St.parkM, St.parkSpeed = nil, nil, nil, nil
        end
    end
end
function DOWN.parked() return St.parked ~= nil end

---------------------------------------------------------------------------------------------------- the tick
-- (the host) every player in the mission down (present: you, and each other whose game says it's in the level and was
-- heard from in PRESENT_MS)
local function everyoneDown()
    local n, up = 0, 0
    local seen = {}
    St.wasIn = St.wasIn or {}
    for _, e in ipairs(COOP.players()) do
        if not e.isMe then seen[e.slot] = true end
        if e.isMe or (e.inLevel and num(e.age, 1e9) < PRESENT_MS) then
            n = n + 1
            if e.alive ~= false then up = up + 1 end
            if not e.isMe then St.wasIn[e.slot] = true end  -- ((0.73.77) A8: in the mission once since they linked)
        end
    end
    for s in pairs(St.wasIn) do if not seen[s] then St.wasIn[s] = nil end end   -- (dropped: a rejoin loads in again)
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
    if St.arm then                                          -- (0.73.73: after a revive: the weapons and the gear)
        local okA, errA = pcall(armTick, pawn, now)
        if not okA then St.arm = nil; logOnce("armTick", "revive: the weapons' watch: error " .. tostring(errA)) end
    end
    local okP, errP = pcall(parkedTick, pawn, now)          -- (0.73.73: parked at your airfield in co-op)
    if not okP then logOnce("parkedTick", "airfield: the parked guard: error " .. tostring(errP)) end
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
        local okO, errO = pcall(orbitTick, now)
        if not okO then logOnce("orbitTick", "spectate: camera controls error " .. tostring(errO)) end
        if not okS then logOnce("spectateTick", "spectate: error " .. tostring(errS)) end
    elseif valid(pawn) and not St.ended and rc().enabled == true and linked() and D.round and D.round >= 1 then
        local okH, h = pcall(function() return pawn.HealthInternal end)
        local fl = num(rc().floor_hp, 0.1) * 10
        if okH and type(h) == "number" and h > 0 and h <= fl + 0.01 and not RUN.insured then goDown(pawn, h) end
    end
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
        -- ((0.73.77) plan A8) not while a player who linked is still loading in (no plane in the mission yet): they can
        -- still fly to the airfield and buy the others back. Saint Alessia's run of 2026-11-03: the host ended it at
        -- 16:54:15 ("every player in the mission is down (2)") with scaraboy13's plane 9 s from arriving; he fought VALKA
        -- alone in a run already over. Who: sv_coop.lua COOP.joinWaiting on the round clock (the roster's players not in
        -- the mission, each for its [coop] join_wait_s, 90, from when they were first seen out), as the round holds use it,
        -- less any who've been in the mission since they linked (everyoneDown's St.wasIn: one gone from it, a lost link,
        -- doesn't hold the run)
        local wait = nil
        if rc().enabled == true and not St.ended and COOP.joinWaiting and D.now then   -- (every pass: each one's 90 s from
            local okW, w = pcall(COOP.joinWaiting, D.now)                              -- when they were first seen out)
            if okW and type(w) == "table" and #w > 0 then
                local was = {}
                for s in pairs(St.wasIn or {}) do was[tostring(COOP.name and COOP.name(s) or s)] = true end
                for _, nm in ipairs(w) do if not was[tostring(nm)] then wait = wait or {}; wait[#wait + 1] = tostring(nm) end end
            end
        end
        if all and wait then
            St.allDownAt = nil
            local who = table.concat(wait, ", ")
            if St.heldFor ~= who then
                St.heldFor = who
                log(string.format("down: run over held: player %s still loading in (linked, no plane in the mission yet; "
                    .. "every player in it is down: %d)", who, n))
            end
        elseif all then
            if St.heldFor then log("down: run over no longer held (" .. St.heldFor .. ": in the mission now, or waited for long enough)") end
            St.heldFor = nil
            St.allDownAt = St.allDownAt or now
            if now - St.allDownAt >= RO_CONFIRM_S then
                COOP.msg(nil, "ro", D.round or 0)
                log(string.format("down: every player in the mission is down (%d) for %d s: the run's over for everyone", n, RO_CONFIRM_S))
                DOWN.runOver(D.round, "every player down")
            end
        else
            St.allDownAt, St.heldFor = nil, nil
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
