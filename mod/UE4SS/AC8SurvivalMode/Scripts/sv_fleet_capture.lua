-- sv_fleet_capture.lua: GEOFON's capture (the user's dev install only; docs/design/INVINCIBLE_FLEET.md WP14, the user's
-- "Controlling Players plan"), sv_fleet.lua's piece after sv_fleet_surface.lua. Part of AC8 Survival Mode's runtime, run by
-- main.lua in MODULES' order: a name another part uses is a global of this mod's Lua state, its own helpers stay local.
-- The whole piece is one test-only block, which tools/strip_test_only.py takes out of every release and test zip, and
-- tools/dev_only.py out of a TESTER zip, only this header left there.
-- In co-op, while GEOFON sails and RAVEN's EW mast (the Alicorn's ECM part in its Mk 15 slot) is up, the host now and then
-- picks a player who's flying (never the only one up, never one DOWN, at the airfield or in a capture): a CAPTURE LOCK
-- warns them for lock_s; broken if RAVEN's mast goes down or they're more than escape_km from RAVEN when it runs out.
-- Else their plane is taken over (runtime SV_Capture: DOWN's takeover flying to a gate gate_km behind GEOFON's stern,
-- lined up with it), flown down its line to the deck and put on it (SV_Respawn's one move: the local plane takes no
-- per-frame teleport, the pin test of 0.74.163), and die_after_s later they go DOWN (sv_down.lua DOWN.capture),
-- revivable as any DOWN. The user's rules (2026-11-17): while RAVEN controls a player (the takeover and the landing)
-- they're invincible and no enemy targets them (the attack limits at 0, as DOWN's); saved (the lock or the takeover
-- broken): both given back; "They can't die until they land on the geofon". Solo: never, but IFCAP.test() runs one on
-- your own plane (the autotest's suite capture; at its end your plane is given back, no DOWN solo).
-- The host's word to every game: "if|cap|<slot>|<seq>" (the lock), "if|capgo|<slot>|<seq>" (the takeover),
-- "if|capoff|<slot>|<seq>|<why>" (broken or cancelled); sv_fleet_round.lua's IFCOOP.onHost hands them here.
-- Log: `capture: ...`
-- TEST ONLY BEGIN (GEOFON's capture: test builds only, the user's dev install)
do
IFCAP = {}
if CFG.specials and CFG.specials.fleet and not CFG.specials.fleet.capture then
    CFG.specials.fleet.capture = {
        enabled = true, coop_only = true, first_s = 120, every_s = 180, per_player_s = 300, lock_s = 10, escape_km = 12,
        -- ((0.74.167) final_m 250 -> 800 and floor_m: the autotest's captive of 0.74.166 flew its glide into the sea short of the
        -- deck (invincible doesn't stop a crash: the retry menu), so the line never goes under the deck + floor_m and the
        -- move onto the deck comes from final_m out)
        -- ((0.74.168) no move onto the deck: SV_Respawn's put the captive on GEOFON's deck at flying speed and it crashed at
        -- once (autotest 0.74.167). Flown in low down GEOFON's line, never under the deck + floor_m; over its mark (within
        -- final_m) an explosion on the deck and, in co-op, DOWN at once (hidden, revivable): the crash onto the deck)
        gate_km = 3, gate_alt_m = 300, glide_deg = 3.5, final_m = 300, floor_m = 110, give_up_s = 240,   -- (floor 70 -> 110: 0.74.168 sagged 40 m under it, to 28 m)
        boom_fx = { "/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_Explosion001", 3 },
        -- ((0.74.174) the user: "Yeah give that a try": the autopilot lands it on GEOFON's deck: in its final, gear down and the
        -- brake to landing speed (runtime SV_CapLand), its line down to the deck itself; on the deck (the game's IsOnGround,
        -- or within land_m of the deck's height over its mark) held land_hold_s, then the explosion and DOWN. Past the deck
        -- without touching it: the old end over it. land = false: the old approach, never under floor_m)
        land = true, land_m = 4, land_hold_s = 2, clear_m = 0, press_m = 20,   -- ((0.74.180) clear 15 -> 3, press 5 -> 10: 0.74.179 tracked within ~8 m but crossed the deck 20 m up: the deck is ~4 s long at landing speed; (0.74.183) clear 0, press 20, land_m 4: 0.74.181-182 touched once in three)
        deck = { fwd_m = -40, right_m = 0, up_m = 20 },     -- (the deck's touchdown spot from GEOFON's root, metres)
        -- ((0.74.177) the user: "Why not just make the deck have collision??": GEOFON's hull stops no trace (0.74.176's
        -- probe: 24 of 24 through it to the sea), so an invisible box of ours on it at its deck's height, blocking all: the
        -- deck's length and width, its top top_m over GEOFON's root, its centre fwd_m / right_m from it (metres)
        slab = { enabled = true, len_m = 330, wid_m = 76, thick_m = 4, top_m = 20, fwd_m = 0, right_m = 0 },
        text = { lock = "CAPTURE LOCK", lock_sub = "GET CLEAR OR DESTROY RAVEN'S EW MAST",
                 lock_other = "CAPTURE LOCK ON %s", taken = "AIRCRAFT CAPTURED", taken_sub = "RAVEN HAS YOUR CONTROLS",
                 taken_other = "%s IS BEING TAKEN TO GEOFON", broken = "CAPTURE BROKEN", captured_other = "%s CAPTURED",
                 mast_down = "RAVEN'S EW MAST DOWN", mast_down_sub = "NO MORE CAPTURES" },
    }
    if CFG_DEFAULTS and CFG_DEFAULTS.specials and CFG_DEFAULTS.specials.fleet and not CFG_DEFAULTS.specials.fleet.capture then
        CFG_DEFAULTS.specials.fleet.capture = CFG.specials.fleet.capture
    end
end
local function cc() return ((CFG.specials or {}).fleet or {}).capture or {} end
local function n(v, d) v = tonumber(v); return v or d end
local function clog(s) log("capture: " .. s) end
local function tx() return cc().text or {} end
local function nameOf_(slot)
    local ok, nm = pcall(function() return COOP and COOP.name and COOP.name(slot) end)
    return (ok and type(nm) == "string" and nm ~= "") and nm:upper() or ("PLAYER " .. tostring(slot))
end
local ATTACKERS = { "MaxPlaneAttackerMissiles", "MaxPursuitAttackers", "MaxNonPlaneAttackerMissiles" }
-- ((0.74.166) the attack limits didn't hold (autotest capture of 0.74.165: MaxPursuitAttackers read 12 after it was set
-- 0): no enemy targets you by the flags the fleet's parts hide from the game's targeting with, as well)
-- ((0.74.168) those two aren't a player plane's (they read back as objects: the probe of 0.74.167); its Faction is (1, the
-- players'): neutral (0) while RAVEN flies you, so no side's fire control picks you, put back after)
local UNTARGETED = { Faction = 0 }

-- GEOFON here (the host's own ship, a joiner's copy of it): its place and heading, or nil
local function geofon()
    local o = nil
    if IFLEET and IFLEET.cur then
        local sh = IFLEET.cur.ships and IFLEET.cur.ships[1]
        if sh and not sh.sunk and sh.hull and liveObj(sh.hull.obj) then o = sh.hull.obj end
    elseif COOP and COOP.client and COOP.client() and COOP.copiesOf then
        local first = (((CFG.specials or {}).fleet or {}).ships or {})[1]
        if first and first.key then
            for _, c in ipairs(COOP.copiesOf("SV_Unit_IF" .. first.key)) do
                local nm = nameOf(c) or ""
                if not nm:lower():find("mk15", 1, true) and liveObj(c) then o = o or c end
            end
        end
    end
    if not o then return nil end
    local ok, l, r = pcall(function()
        local v, q = o:K2_GetActorLocation(), o:K2_GetActorRotation()
        return { X = v.X, Y = v.Y, Z = v.Z }, q.Yaw
    end)
    if not (ok and l) then return nil end
    return { X = l.X, Y = l.Y, Z = l.Z, yaw = r or 0 }
end
-- the deck's touchdown spot and the approach line's heading (GEOFON's own), from its pose
local function deckOf(g)
    local d = cc().deck or {}
    local y = math.rad(g.yaw)
    local f, r, u = n(d.fwd_m, -40) * 100, n(d.right_m, 8) * 100, n(d.up_m, 22) * 100
    return { X = g.X + math.cos(y) * f - math.sin(y) * r, Y = g.Y + math.sin(y) * f + math.cos(y) * r, Z = g.Z + u, yaw = g.yaw }
end
-- the host's RAVEN and its EW mast (its ECM part): RAVEN's ship, the mast's object if it's up
local function raven()
    for _, sh in ipairs(IFLEET and IFLEET.cur and IFLEET.cur.ships or {}) do
        if sh.name == "RAVEN" then
            if sh.sunk or not (sh.hull and liveObj(sh.hull.obj)) then return sh, nil end
            for _, e in ipairs(sh.parts or {}) do
                if tostring(e.cls):find("alcn_ecm", 1, true) and liveObj(e.obj) and nameOf(e.obj) == e.name then
                    local okH, h = pcall(function() return e.obj.HealthInternal end)
                    if not okH or (type(h) == "number" and h > 0) then return sh, e.obj end
                end
            end
            return sh, nil
        end
    end
    return nil, nil
end
local function ravenAt(sh)
    local ok, l = pcall(function() local v = sh.hull.obj:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    return ok and l or nil
end
-- ((0.74.176) the deck probe: straight-down traces round the deck's mark along and across GEOFON's line, each hit's height
-- over GEOFON's root and what it hit, logged once a capture (0.74.174's landing came in 14 m under the guessed mark)
local KS = nil
local function deckProbe(g, dk)
    if not valid(KS) then KS = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    if not (valid(KS) and liveObj(survivalPC)) then return "no trace library" end
    local y = math.rad(g.yaw)
    local ux, uy, rx, ry = math.cos(y), math.sin(y), -math.sin(y), math.cos(y)
    local out = {}
    for _, a in ipairs({ -200, -150, -100, -50, 0, 50, 100, 150 }) do
        for _, c in ipairs({ -30, 0, 30 }) do
            local x, yy = dk.X + ux * a * 100 + rx * c * 100, dk.Y + uy * a * 100 + ry * c * 100
            local hit, z, who = {}, nil, "?"
            pcall(function()
                KS:LineTraceSingle(survivalPC, { X = x, Y = yy, Z = g.Z + 20000 }, { X = x, Y = yy, Z = g.Z - 5000 }, 0, true, {}, 0,
                    hit, true, { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
            end)
            pcall(function()
                local h = hit.OutHit or hit
                local l = h.ImpactPoint or h.Location
                if l and l.Z then z = l.Z end
                pcall(function() who = (nameOf(h.HitObjectHandle.Actor):match("([^%.:]+)$")) or "?" end)
            end)
            out[#out + 1] = string.format("%+d/%+d: %s", a, c, z and string.format("%.1f m (%s)", (z - g.Z) / 100, who) or "none")
        end
    end
    return table.concat(out, "; ")
end
-- ((0.74.177) GEOFON's own collision read (each primitive component's: enabled, object type, its answer to a Pawn), and the
-- deck's slab: a BoxComponent of ours on it (AddComponentByClass, as VALKA's X-02S: hard rule 46), blocking every channel
local function hullCollision(o)
    local out = {}
    pcall(function()
        local cls = StaticFindObject("/Script/Engine.PrimitiveComponent")
        o:K2_GetComponentsByClass(cls):ForEach(function(_, el)
            local c = el:get()
            local nm, en, ot, pr = "?", "?", "?", "?"
            pcall(function() nm = c:GetFName():ToString() end)
            pcall(function() en = tostring(c:GetCollisionEnabled()) end)
            pcall(function() ot = tostring(c:GetCollisionObjectType()) end)
            pcall(function() pr = tostring(c:GetCollisionResponseToChannel(2)) end)
            if #out < 12 then out[#out + 1] = string.format("%s enabled %s type %s pawn %s", nm, en, ot, pr) end
        end)
    end)
    return #out > 0 and table.concat(out, "; ") or "none read"
end
local SLAB = nil
local function deckSlab(o)
    local d = cc().slab or {}
    if d.enabled == false or not liveObj(o) then return nil, "off" end
    if SLAB and SLAB.a == addrOf(o) and SLAB.name == nameOf(o) and liveObj(SLAB.c) then return SLAB.c, "there already" end
    local cls = StaticFindObject("/Script/Engine.BoxComponent")
    if not valid(cls) then return nil, "no BoxComponent class" end
    local th = n(d.thick_m, 4) * 100
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
                Translation = { X = n(d.fwd_m, 0) * 100, Y = n(d.right_m, 0) * 100, Z = n(d.top_m, 20) * 100 - th / 2 },
                Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, c = pcall(function() return o:AddComponentByClass(cls, false, t, false) end)
    if not (ok and valid(c)) then return nil, "AddComponentByClass " .. (ok and "gave nothing" or tostring(c)) end
    local steps = {}
    local function step(nm, f) if not pcall(f) then steps[#steps + 1] = nm .. " FAILED" end end
    step("SetBoxExtent", function() c:SetBoxExtent({ X = n(d.len_m, 330) * 50, Y = n(d.wid_m, 76) * 50, Z = th / 2 }, true) end)
    step("SetCollisionObjectType", function() c:SetCollisionObjectType(0) end)        -- (WorldStatic)
    step("SetCollisionEnabled", function() c:SetCollisionEnabled(3) end)             -- (QueryAndPhysics)
    step("SetCollisionResponseToAllChannels", function() c:SetCollisionResponseToAllChannels(2) end)   -- (Block)
    step("SetHiddenInGame", function() c:SetHiddenInGame(true, false) end)
    SLAB = { a = addrOf(o), name = nameOf(o), c = c }
    return c, #steps > 0 and table.concat(steps, ", ") or "every setting took"
end
local function busyScene()
    return (CINE and CINE.active and CINE.active()) or (IFSURF and IFSURF.state and IFSURF.state()) ~= nil
end

---------------------------------------------------------------------------------------------------- this game's own capture
-- L: { seq, state ("lock" | "fly" | "final" | "trap" | "done"), at, limits, solo }
local L = nil
local trapTick                                            -- (below: flyTick ends a capture through it)
local function pawnNow() return liveObj(survivalPC) and survivalPC.Pawn or nil end
local function shielded(on)                               -- (the user's rule: invincible, no enemy targets you; given back)
    local pawn = pawnNow()
    if not valid(pawn) then return "no plane" end
    if on then
        pcall(function() pawn:SetIsInvincible(true) end)
        L.limits = L.limits or {}
        L.flags = L.flags or {}
        for f, v in pairs(UNTARGETED) do
            local okR, was = pcall(function() return pawn[f] end)
            if okR and L.flags[f] == nil and pcall(function() pawn[f] = v end) then L.flags[f] = was end
        end
        for _, f in ipairs(ATTACKERS) do
            local okR, v = pcall(function() return pawn[f] end)
            if okR and type(v) == "number" and L.limits[f] == nil and pcall(function() pawn[f] = 0 end) then L.limits[f] = v end
        end
        if ATK and ATK.hold then ATK.hold("capture", true) end   -- (sv_spweapons.lua's limits held off meanwhile)
        return "invincible, no enemy targets you"
    end
    if not (DOWN and DOWN.me and DOWN.me()) then pcall(function() pawn:SetIsInvincible(false) end) end
    for f, v in pairs(L and L.limits or {}) do pcall(function() pawn[f] = v end) end
    for f, v in pairs(L and L.flags or {}) do pcall(function() pawn[f] = v end) end
    if L then L.limits, L.flags = nil, nil end
    if ATK and ATK.hold then ATK.hold("capture", false) end
    return "targetable again"
end
local function giveBack(why)                              -- (any end: the controls, the shield; never left taken)
    if not L then return end
    if L.state == "fly" or L.state == "final" then
        local pw = pawnNow()                              -- (the landing's gear back up, the brake off: a plane given back flies)
        if L.landOn and valid(pw) and type(SV_CapLand) == "function" then pcall(SV_CapLand, addrOf(pw) or 0, 0) end
        if type(SV_Capture) == "function" then pcall(SV_Capture, 0) end
        if playerLocationDirty then playerLocationDirty() end
    end
    local said = shielded(false)
    clog(string.format("seq %s given back (%s): your controls, %s", tostring(L.seq), tostring(why), said))
    L = nil
end
local function lockHere(seq, solo)
    if L then giveBack("a new lock") end
    L = { seq = seq, state = "lock", at = os.clock(), solo = solo }
    hudCallout(tx().lock or "CAPTURE LOCK", tx().lock_sub or "")
    if SND and SND.beep then pcall(SND.beep) end
    clog(string.format("seq %s: CAPTURE LOCK on you (%s s)", tostring(seq), tostring(n(cc().lock_s, 10))))
end
local function takeHere(seq)
    if not (L and L.seq == seq) then L = { seq = seq, at = os.clock() } end
    do                                                    -- ((0.74.177) GEOFON's collision read, and its deck's slab
        local o = nil
        if IFLEET and IFLEET.cur and IFLEET.cur.ships and IFLEET.cur.ships[1] and IFLEET.cur.ships[1].hull then o = IFLEET.cur.ships[1].hull.obj end
        if not o and COOP and COOP.copiesOf then
            local first = (((CFG.specials or {}).fleet or {}).ships or {})[1]
            for _, x in ipairs(first and COOP.copiesOf("SV_Unit_IF" .. first.key) or {}) do
                if not (nameOf(x) or ""):lower():find("mk15", 1, true) then o = o or x end
            end
        end
        if o and liveObj(o) then
            pcall(function()                              -- ((0.74.182) its facing against its travel: the line's heading
                local r, v = o:K2_GetActorRotation(), o:GetVelocity()
                local fwd = o:GetActorForwardVector()
                clog(string.format("GEOFON: actor yaw %.1f, forward (%.2f, %.2f) = %.1f deg, travel %.1f deg at %.0f km/h", r.Yaw, fwd.X,
                    fwd.Y, math.deg(math.atan(fwd.Y, fwd.X)), math.deg(math.atan(v.Y, v.X)), math.sqrt(v.X * v.X + v.Y * v.Y) * 0.036))
            end)
            local okH, h = pcall(hullCollision, o)
            clog("GEOFON's own collision: " .. (okH and h or ("error " .. tostring(h))))
            local okS, c, why = pcall(deckSlab, o)
            clog("the deck's slab: " .. ((okS and c) and ("up (" .. tostring(why) .. ")") or ("NOT up: " .. tostring(okS and why or c))))
        end
    end
    L.state, L.at = "fly", os.clock()
    local said = shielded(true)
    hudCallout(tx().taken or "AIRCRAFT CAPTURED", tx().taken_sub or "")
    clog(string.format("seq %s: taken over: %s; flown to GEOFON's gate", tostring(seq), said))
end
local function flyTick(now)
    local g = geofon()
    if not g then giveBack("GEOFON gone (sunk or not here): the captive goes free"); return end
    local pawn = pawnNow()
    if not valid(pawn) then giveBack("no plane"); return end
    shielded(true)                                        -- (held every tick: the game may put it back)
    local c = cc()
    local dk = deckOf(g)
    local y = math.rad(dk.yaw)
    local me = playerLocation and playerLocation() or nil
    if not me then return end
    local along = (me.X - dk.X) * math.cos(y) + (me.Y - dk.Y) * math.sin(y)       -- (cm: negative behind the deck)
    local dist = math.sqrt((me.X - dk.X) ^ 2 + (me.Y - dk.Y) ^ 2) / 100
    if L.state == "fly" then
        local gk = n(c.gate_km, 3) * 100000
        local gx, gy = dk.X - math.cos(y) * gk, dk.Y - math.sin(y) * gk
        local rc = type(SV_Capture) == "function" and SV_Capture(addrOf(pawn) or 0, gx, gy, n(c.gate_alt_m, 300) + dk.Z / 100, dk.yaw) or -1
        if rc == 2 then L.state = "final"; clog(string.format("seq %s: at the gate (%.1f km out): down its line to the deck", tostring(L.seq), dist / 1000)) end
        if type(rc) == "number" and rc < 0 then giveBack("SV_Capture refused (" .. tostring(rc) .. ")") return end
    elseif L.state == "final" then
        local behind = math.max(0, -along / 100)
        local landing = c.land ~= false and type(SV_CapLand) == "function"
        if landing and not L.landOn then
            L.landOn = true
            local okL, r = pcall(SV_CapLand, addrOf(pawn) or 0, 1)
            clog(string.format("seq %s: the landing: gear down, slowing (SV_CapLand %s)", tostring(L.seq), okL and tostring(r) or "FAILED"))
        end
        if landing and now >= (L.landAgain or 0) then L.landAgain = now + 1; pcall(SV_CapLand, addrOf(pawn) or 0, 1) end
        if not L.probed and dist <= 2500 then
            L.probed = true
            local okP, txt = pcall(deckProbe, g, dk)
            clog(string.format("seq %s: deck probe (metres over GEOFON's root, along/across from the mark at %.1f m): %s",
                tostring(L.seq), (dk.Z - g.Z) / 100, okP and txt or ("error " .. tostring(txt))))
        end
        -- ((0.74.178) over the slab's length only: 0.74.177's captive sagged under the deck's height behind it (the autopilot
        -- flies ~10-40 m under the height asked when slow) and "touched down" 12 m under it, off the ship. Behind the slab:
        -- clear_m over its edge plus the glide; over it: press_m into it (contact); a touchdown only over it)
        local sl = c.slab or {}
        local mark = n((c.deck or {}).fwd_m, -40)
        local aft = n(sl.fwd_m, 0) - n(sl.len_m, 330) / 2 - mark          -- (metres along from the mark: the slab's ends)
        local fore = n(sl.fwd_m, 0) + n(sl.len_m, 330) / 2 - mark
        local am = along / 100
        local overSlab = am >= aft and am <= fore
        local alt
        if landing then
            alt = overSlab and (dk.Z / 100 - n(c.press_m, 5))
                or (dk.Z / 100 + n(c.clear_m, 15) + math.max(0, aft - am) * math.tan(math.rad(n(c.glide_deg, 3.5))))
        else
            alt = dk.Z / 100 + math.max(n(c.floor_m, 80), behind * math.tan(math.rad(n(c.glide_deg, 3.5))))
        end
        if landing then
            local up = (me.Z - dk.Z) / 100
            local okG, og = pcall(function() return pawn:IsOnGround() end)
            local onDeck = (okG and og == true) or (overSlab and up <= n(c.land_m, 3) and up >= -2)
            if onDeck and not L.touchAt then
                L.touchAt = now
                clog(string.format("seq %s: touched down on GEOFON's deck (%.0f m off its mark, %.0f m over it; IsOnGround %s)",
                    tostring(L.seq), dist, up, tostring(okG and og)))
            end
            if L.touchAt and now - L.touchAt >= n(c.land_hold_s, 2) then
                L.state, L.at = "trap", now
                clog(string.format("seq %s: trapped on GEOFON's deck (landed, %.0f m off its mark)", tostring(L.seq), dist))
                trapTick(now)
                return
            end
            if not L.touchAt and am > fore then
                L.state, L.at = "trap", now
                clog(string.format("seq %s: trapped on GEOFON's deck (passed over it, %.0f m up: no touchdown)", tostring(L.seq), up))
                trapTick(now)
                return
            end
        end
        local rc = type(SV_Capture) == "function" and SV_Capture(addrOf(pawn) or 0, dk.X, dk.Y, math.max(0, alt), dk.yaw) or -1
        if type(rc) == "number" and rc < 0 then giveBack("SV_Capture refused (" .. tostring(rc) .. ")") return end
        if not landing and (dist <= n(c.final_m, 300) or along > 0) then
            L.state, L.at = "trap", now
            clog(string.format("seq %s: trapped on GEOFON's deck (over its mark, %.0f m off it, %.0f m up)", tostring(L.seq), dist,
                (me.Z - dk.Z) / 100))
            trapTick(now)
            return
        end
    end
    if now - L.at > n(c.give_up_s, 240) then giveBack("not at the deck in " .. n(c.give_up_s, 240) .. " s") end
end
local function deckBoom(at)                               -- (the crash onto the deck: an explosion at its mark)
    local fx = cc().boom_fx or {}
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (fx[1] and valid(lib) and liveObj(survivalPC)) then return false end
    local sys = loadObject(fx[1] .. "." .. (fx[1]:match("[^/]+$") or ""))
    local sc = tonumber(fx[2]) or 1
    return sys ~= nil and pcall(function()
        lib:SpawnSystemAtLocation(survivalPC, sys, { X = at.X, Y = at.Y, Z = at.Z }, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc },
            true, true, 0, false)
    end)
end
trapTick = function(now)
    local seq, solo = L.seq, L.solo
    L.state = "done"
    local pawn0 = pawnNow()
    if L.landOn and valid(pawn0) and type(SV_CapLand) == "function" then pcall(SV_CapLand, addrOf(pawn0) or 0, 0) end
    if type(SV_Capture) == "function" then pcall(SV_Capture, 0) end   -- (the takeover off first: DOWN's own autopilot, or yours)
    if playerLocationDirty then playerLocationDirty() end
    local g = geofon()
    local boomed = g and deckBoom(deckOf(g)) or false
    hudCallout("CAPTURED", "TRAPPED ON GEOFON")
    shielded(false)
    if solo or not (DOWN and DOWN.capture) then
        local pawn = pawnNow()                            -- (the solo test: climbed out round GEOFON, not left 70 m over the sea)
        if solo and valid(pawn) and g and type(SV_Down) == "function" then pcall(SV_Down, addrOf(pawn) or 0, g.X, g.Y, 1500, 4000) end
        clog(string.format("seq %s: captured on GEOFON (solo test: your plane given back, no DOWN); the deck's explosion %s",
            tostring(seq), boomed and "up" or "NOT up"))
        L = nil
        return
    end
    local okD, r = pcall(DOWN.capture, "captured on GEOFON")
    clog(string.format("seq %s: captured on GEOFON: DOWN (%s); the deck's explosion %s", tostring(seq), okD and tostring(r) or "FAILED",
        boomed and "up" or "NOT up"))
    L = nil
end

---------------------------------------------------------------------------------------------------- the host's picks
local H = { seq = 0, nextAt = nil, last = {}, cur = nil, mastSaid = false }
local function hostSend(what, ...) if IFCOOP and IFCOOP.send then IFCOOP.send(what, ...) end end
local function hostEnd(why, broken)
    local k = H.cur
    if not k then return end
    H.cur = nil
    hostSend("capoff", tostring(k.slot), tostring(k.seq), why)
    if k.slot == (COOP and COOP.slot or 0) or k.solo then IFCAP.onHost({ "if", "capoff", tostring(k.slot), tostring(k.seq), why }) end
    if broken then hudCallout(tx().broken or "CAPTURE BROKEN", why:upper()) end
    clog(string.format("seq %d (slot %d): ended: %s", k.seq, k.slot, why))
end
local function pick(now)
    local list = COOP and COOP.players and COOP.players() or {}
    local flying, cands = 0, {}
    for _, p in ipairs(list) do
        local up = p.alive ~= false and not p.down and not p.onAirfield and p.at ~= nil
        if up then flying = flying + 1 end
        if up and now - (H.last[p.slot] or -1e9) >= n(cc().per_player_s, 300) then cands[#cands + 1] = p end
    end
    if flying < 2 or #cands == 0 then return nil end     -- (never the only one up: the run would end)
    return cands[math.random(#cands)]
end
local function hostTick(now)
    local c = cc()
    local solo = not (COOP and COOP.open)
    if c.enabled == false or (c.coop_only ~= false and solo and not (H.cur and H.cur.solo)) then return end
    if not (IFLEET and IFLEET.cur) then H.nextAt = nil; if H.cur then hostEnd("the fleet's gone") end; return end
    local g = geofon()
    local sh, mast = raven()
    if H.cur then
        local k = H.cur
        if k.state == "taken" then                         -- (over once its captive is DOWN, or the solo test's capture done)
            local over = k.solo and L == nil
            for _, p in ipairs(COOP and COOP.players and COOP.players() or {}) do if p.slot == k.slot and p.down then over = true end end
            if over then H.cur = nil; clog(string.format("seq %d: slot %d captured: over", k.seq, k.slot)); return end
        end
        if not g then hostEnd("GEOFON sunk", true); return end
        if k.state == "lock" then
            if not mast then hostEnd("RAVEN's EW mast destroyed", true); return end
            if now >= k.until_ then
                local at = nil
                for _, p in ipairs(COOP and COOP.players and COOP.players() or {}) do if p.slot == k.slot then at = p.at end end
                if k.solo then at = playerLocation and playerLocation() or at end
                local ra = sh and ravenAt(sh)
                local d = (at and ra) and math.sqrt((at.X - ra.X) ^ 2 + (at.Y - ra.Y) ^ 2) / 100000 or 0
                if d > n(k.escape, n(c.escape_km, 12)) then hostEnd(string.format("%.1f km clear of RAVEN", d), true); return end
                k.state = "taken"
                hostSend("capgo", tostring(k.slot), tostring(k.seq))
                if k.slot == (COOP and COOP.slot or 0) or k.solo then IFCAP.onHost({ "if", "capgo", tostring(k.slot), tostring(k.seq) }) end
                if not k.solo then hudCallout(string.format(tx().taken_other or "%s IS BEING TAKEN TO GEOFON", nameOf_(k.slot)), "") end
                clog(string.format("seq %d: slot %d taken over (%.1f km from RAVEN)", k.seq, k.slot, d))
            end
        end
        return
    end
    if solo then return end
    if not mast then
        if sh and not H.mastSaid then H.mastSaid = true; hudCallout(tx().mast_down or "RAVEN'S EW MAST DOWN", tx().mast_down_sub or ""); clog("RAVEN's EW mast down: no more captures") end
        return
    end
    if not g or busyScene() then return end
    if not H.nextAt then H.nextAt = now + n(c.first_s, 120); return end
    if now < H.nextAt then return end
    H.nextAt = now + n(c.every_s, 180)
    local p = pick(now)
    if not p then clog("no one to pick (fewer than 2 flying, or each picked lately)"); return end
    H.seq = H.seq + 1
    H.last[p.slot] = now
    H.cur = { slot = p.slot, seq = H.seq, state = "lock", until_ = now + n(c.lock_s, 10) }
    hostSend("cap", tostring(p.slot), tostring(H.seq))
    if p.slot == (COOP and COOP.slot or 0) then IFCAP.onHost({ "if", "cap", tostring(p.slot), tostring(H.seq) }) end
    clog(string.format("seq %d: slot %d picked (%s); the lock %s s", H.seq, p.slot, nameOf_(p.slot), tostring(n(c.lock_s, 10))))
end

---------------------------------------------------------------------------------------------------- the host's word, here
function IFCAP.onHost(f)
    local what, slot, seq = f[2], tonumber(f[3]), tonumber(f[4])
    if not (slot and seq and slot >= 0 and slot < 64 and seq >= 0 and seq < 1e6) then return false, "bad slot / seq" end
    local mine = slot == (COOP and COOP.slot or 0) or (H.cur and H.cur.solo)
    if what == "cap" then
        if mine then lockHere(seq, H.cur and H.cur.solo) else hudCallout(string.format(tx().lock_other or "CAPTURE LOCK ON %s", nameOf_(slot)), "") end
        return true
    end
    if what == "capgo" then
        if mine then takeHere(seq) end
        return true
    end
    if what == "capoff" then
        if mine and L and L.seq == seq and L.state ~= "trap" and L.state ~= "done" then
            giveBack(tostring(f[5] or "the host's word"))
            hudCallout(tx().broken or "CAPTURE BROKEN", tostring(f[5] or ""):upper())
        end
        return true
    end
    return false, "unknown: " .. tostring(what)
end
-- ((the autotest's suite capture) one on your own plane solo: the lock, the takeover, the landing; your plane given back)
function IFCAP.test(lock_s)
    if H.cur then return false, "one on already" end
    if not (IFLEET and IFLEET.cur) then return false, "no fleet up (Ctrl+N first)" end
    H.seq = H.seq + 1
    H.cur = { slot = COOP and COOP.slot or 0, seq = H.seq, state = "lock", until_ = os.clock() + n(lock_s, 5), solo = true,
              escape = 1e9 }                              -- (solo: never "clear of RAVEN": the takeover is what's tested)
    if type(SV_Down) == "function" then pcall(SV_Down, 0) end   -- (an autopilot of another's off first)
    IFCAP.onHost({ "if", "cap", tostring(H.cur.slot), tostring(H.seq) })
    clog(string.format("seq %d: the solo test on your plane (lock %s s)", H.seq, tostring(n(lock_s, 5))))
    return true
end
function IFCAP.state() return L and L.state or nil end

TEST_TICKS[#TEST_TICKS + 1] = { name = "fleet capture", fn = function(now)
    if not D then if L then giveBack("the run's over") end; H.cur, H.nextAt = nil, nil; return end
    if not (COOP and COOP.client and COOP.client()) then pcall(hostTick, now) end
    if L then
        if L.state == "fly" or L.state == "final" then flyTick(now) end
    end
end }
if type(LEVEL_DROPS) == "table" then
    LEVEL_DROPS["fleet capture"] = function()                 -- (the level's plane went with it)
        L, H.cur, H.nextAt = nil, nil, nil
        if ATK and ATK.hold then ATK.hold("capture", false) end
    end
end
end
-- TEST ONLY END
