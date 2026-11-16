-- sv_tanicorn_rail.lua : THE TANACORN's Alicorn armaments live (2026-11-12, stage 4: docs/re/TANICORN.md "Railguns and
-- railcannon"): her two sub-railguns deployed and ordered, her bow railcannon's charged shot at the airfield. Test builds
-- only: the user's dev install, and a TESTER=1 TANI=1 zip (tools/dev_only.py cuts it to this header in every other zip, as
-- sv_tanicorn.lua). Piece of sv_tanicorn.lua's family, run by main.lua after sv_tanicorn_hits.lua; what it keeps hangs on
-- TANI (TANI.rail, its data, is sv_tanicorn.lua's), its settings are CFG.specials.fleet.railcannon (sv_fleet.lua, read when
-- they're used). Each object kept by its address and name, checked before anything is done to it (hard rule 59); every
-- call into the game in a pcall.
-- The sub-railguns (RAILGUN_L / _R, Ctrl+L's live hull): each one's TurretPoseableMesh rests stowed (its lift 6 m down,
--   its hatches shut). Seen by the live watch (its armour on), after_s on its Deploy's end pose is written from here in
--   component space, as quaternion transforms (never rotators: the pitch-key trap), stepped over deploy_s: the lift
--   (0, 0, -600) -> (0, 0, 0) cm, Hatch_n / Hatch_p 105 deg about X at (0, +-460, -30). Then its lift is read back
--   (GetBoneLocationByName, component space: as written) and SOC_Gun_01's height (as drawn); only with the lift up (within
--   up_cm of 0) AND the muzzle raised as drawn (SOC_Gun_01 at least raised_cm up in the mesh: stowed -196, raised ~+404) is it
--   ordered, never from inside the hull: its remote event RE_SV_TaniRailOrderL / RE_SV_TaniRailOrderR (host or solo; held while the STORE is open),
--   its arm's railgun HUD written first (hard rule 45: IsDispRadarMap, ForceAlertDisp, HUDControl 1, read back). No
--   read-back, no order. Its barrel watched move_s after (hard rule 64): one that never moved gets its order again, up to
--   `tries`, and again move_s after the STORE shuts. Its lift read every check_s and written again if it fell back.
-- The railcannon (Ctrl+H, on Ctrl+L's live hull): shielded while stowed from the first tick it's seen (the Alicorn's part
--   flags SPC.V.PART_FLAGS and SetIsInvincible). A press plays its Deploy (AS_SV_Tani_RAILCANNON_Deploy on its TurretMesh,
--   the VLS lids' calls); at deploy_s, its muzzle up as drawn (SOC_Gun_01 at least raised_cm up; else played again redeploys
--   times, then left stowed and shielded with no charge), the shield comes off and its health is sized in your standard
--   missiles (read again every 2 s while unread, size_tries; missiles, +50 %
--   of them for each other player, never above its row's); then a charge: the RAILGUN WARNING (RE_SV_AlcnAlertOn), the
--   callout THE TANACORN IS AIMING AT THE AIRFIELD, the Alicorn's railgun radio, her discharge effect on SOC_Gun_01, her
--   cannon's charge sounds and its RTPC; at charge_s the shot (AC8's own muzzle, streak and impact effects only: hard rule
--   58; every effect stopped after its life), the round on the runway after its flight, damage on the airfield there (the
--   host's: AF.bomb, none with the airfield down or off), the warning off; the next charge every_s after the last one
--   started, while it lives (the first at the first tick nothing holds). Shot down mid-charge (or gone with her hull up,
--   as the Alicorn's parts): everything off, no impact, a callout, TANI.coreOpen (stage 3's hook);
--   a round already in flight still lands (flight_lands). Its clock holds while paused (hard rule 60), in the STORE and the
--   landing minigames (busy: SPC.storeShut, hard rule 64) and
--   while you're landed with nobody else flying. Ctrl+H again: stowed, shielded and stopped. Refused outside a run, on a
--   joiner, in the STORE, with no live hull, with no Part_RAILCANNON child or with it down.
-- Logged (the railguns `tanicorn rail: ...`, the railcannon `tanicorn rc: ...`):
--   `tanicorn rail: RAILGUN_L Part_RAILGUN_L <name> seen: deploying in 3 s ...`, `... deploying at +T s over 2.2 s: lift z
--   -600 cm, SOC_Gun_01 z -196 cm in the mesh ...`, `... deployed: lift z 0 cm (up), SOC_Gun_01 z 404 cm in the mesh ...`
--   (or `... NOT ordered: ...` and why), `... RE_SV_TaniRailOrderL fired (try 1, ...); railgun HUD <launcher class>:
--   written; read back IsDispRadarMap true, ForceAlertDisp true, HUDControl 1`, `... its barrel moves (...) N s after the
--   order: it took` (or `... fired again (try 2: ...)`, `... gave up ...`);
--   `tanicorn rc: Part_RAILCANNON <name> seen: shielded while stowed (...)`, `tanicorn rc: Ctrl+H: deploying (...)`,
--   `tanicorn rc: deployed at +T s: position P of L s, SOC_Gun_01 z ...; shield off (...); health set to N missiles (...)`,
--   `tanicorn rc: charge K at +T s (30 s): RAILGUN WARNING RE_SV_AlcnAlertOn fired; NS_alcn_RailCannonDischarge_ON up on
--   SOC_Gun_01; RTPC_Init posted (id N); radio said`, every 5 s `tanicorn rc: charge K +T/30 s: health H/M, RTPC ...`,
--   `tanicorn rc: Charge_Play posted (id N) at +T s`, `tanicorn rc: SHOT K at +T s: muzzle (x, y, z) km -> runway (x, y) km,
--   R km, the round there in F s; ...`, `tanicorn rc: impact K: -D airfield (AF.bomb B -> B2; health before H) ...`,
--   `tanicorn rc: Part_RAILCANNON shot down at +T s (...)`, `tanicorn rc: cycle over (<why>) ...`.
-- DEV ONLY BEGIN
do
TANI.railgun = { after_s = 3, deploy_s = 2.2, up_cm = 50, raised_cm = 300, writes = 2, move_s = 8, move_deg = 2, tries = 4, check_s = 5,
                  tick_always = true }   -- ((2026-11-16) its pose ticked always before the deploy: gunStep)
local ORDER = { RAILGUN_L = "RE_SV_TaniRailOrderL", RAILGUN_R = "RE_SV_TaniRailOrderR" }   -- (the build's remote events)
local MUZZLE, DEPLOY_LEN, HATCH_DEG = "SOC_Gun_01", 2.167, 105   -- (the cooked Deploy's lift end, its hatches' turn)
local FLAGS0 = { bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true, bIsInvincible = true }
local FLAG_NAMES = { "bShowHUDBox", "bIsNotLockonTarget", "bIsNotFCSTargets", "bIsInvincible" }
local NIAG, AK = "/Script/Niagara.Default__NiagaraFunctionLibrary", "/Script/AkAudio.Default__AkGameplayStatics"
local ROT0 = { Pitch = 0, Yaw = 0, Roll = 0 }
local X = { last = nil }                                  -- the tick's last clock
local RG, FX, TRAIL, PEND = {}, {}, {}, {}                 -- the railguns, the effects, the trail's spots, held events
local RC, SH = nil, nil                                    -- the railcannon's cycle (Ctrl+H) and its shield
local RCK = nil                                            -- its TANI.rail entry
for _, k in ipairs(TANI.rail or {}) do if k.cannon then RCK = k end end

local function short(o) return (nameOf(o):match("([^%.:]+)$")) or "?" end
local function same(e) return e ~= nil and e.a ~= nil and liveAddr(e.o) == e.a and nameOf(e.o) == e.name end
local function num(v, d) v = tonumber(v); if v == nil then return d end return v end
local function fmt(s, ...) local ok, r = pcall(string.format, tostring(s), ...); return ok and r or tostring(s) end
local function joiner() return COOP ~= nil and type(COOP.client) == "function" and COOP.client() == true end
local function paused() return type(gamePaused) == "function" and gamePaused(survivalPC) == true end
-- the landing STORE open (sv_fleet.lua OFF.store, sv_coop_sync.lua's inStore: its music held, the STORE's widget shown)
local function store() return D ~= nil and D.musicHold == 1 and not (LANDW ~= nil and LANDW.wasShown == false) end
-- (hard rule 64; the review of 2026-11-12, finding 4) why this game's own events would run nothing now, or nil: the STORE
-- open, or SPC.storeShut's landing minigames (down at the airfield before this visit's STORE, and 3 s after either). Asked on
-- the rounds' clock (D.now: the clock SPC.gate keeps, never os.clock); with no D.now, the STORE alone
local function busy()
    if store() then return "the STORE is open" end
    if SPC and type(SPC.storeShut) == "function" and D and type(D.now) == "number" then
        local ok, open, why = pcall(SPC.storeShut, D.now)
        if ok and open == false then return tostring(why or "the landing minigames") end
    end
    return nil
end
local function landedAlone()                              -- you on the airfield with nobody else flying (sv_rounds.lua's)
    if type(playerOnAirfield) ~= "function" then return false end
    local ok, on = pcall(playerOnAirfield)
    if not (ok and on) then return false end
    local okO, n = pcall(function() if type(othersFlying) == "function" then return othersFlying() end return 0 end)
    return not (okO and (tonumber(n) or 0) > 0)
end
local function hp(o)
    local h, mx
    pcall(function() h = tonumber(o.HealthInternal) end)
    pcall(function() mx = tonumber(o.MaxHealth) end)
    return h, mx
end
local function fire(ev)                                   -- a remote event: true when SV_Event took it, else false and why
    if type(SV_Event) ~= "function" then return false, "no SV_Event" end
    local ok, r = pcall(SV_Event, ev)
    if ok and r == 1 then return true end
    if not ok then return false, "error " .. tostring(r) end
    return false, tostring((SV_ERR and SV_ERR[r]) or r)
end
local function zOf(f)                                     -- a vector's Z from a game call, or nil and why
    local ok, z = pcall(function() return f().Z end)
    if ok and type(z) == "number" then return z end
    return nil, ok and "no Z read" or tostring(z):sub(1, 80)
end
local function liftZ(m) return zOf(function() return m:GetBoneLocationByName(FName("lift"), 1) end) end   -- (as written)
local function sockZ(m)                                   -- SOC_Gun_01's height in the mesh (as drawn: RTS_Component 2)
    local z = zOf(function() return m:GetSocketTransform(FName(MUZZLE), 2).Translation end)
    if z then return z end
    return zOf(function()
        local s, c = m:GetSocketLocation(FName(MUZZLE)), m:K2_GetComponentLocation()
        return { Z = s.Z - c.Z }
    end)
end
local function cm(z) return z and string.format("%.0f", z) or "?" end
local function g(v) return string.format("%g", tonumber(v) or 0) end   -- (a setting in a line: %d takes no 2.5)

-- every asset by its path, kept and pinned (false: it didn't load); cls: a blueprint's class (_C)
local A = {}
local function asset(path, cls)
    if type(path) ~= "string" or path == "" then return nil end
    local full = path:find(".", 1, true) and path or (path .. "." .. path:match("[^/]+$") .. (cls and "_C" or ""))
    local a = A[full]
    if a == false then return nil end
    if a ~= nil and liveObj(a) then return a end
    a = loadObject(full)
    if a ~= nil and valid(a) then pin(a, "tanicorn rail " .. (full:match("[^%.]+$") or full)); A[full] = a; return a end
    A[full] = false
    return nil
end
-- every effect spawned here: { c, a, name, at (os.clock to stop it; nil: stopped by hand), tag }: AC8's cutscene effects
-- loop until something stops them (the rise's water of 0.74.66), so none is left running
local function fxKeep(c, life, tag)
    local okV, v = pcall(function() return c:IsValid() end)
    if not (okV and v == true) then return nil end
    local e = { c = c, a = addrOf(c), name = nameOf(c), at = life and (os.clock() + life) or nil, tag = tag }
    FX[#FX + 1] = e
    return e
end
local function fxSame(e) return e ~= nil and e.a ~= nil and liveAddr(e.c) == e.a and nameOf(e.c) == e.name end
local function fxStop(e)
    if not e or e.off then return false end
    e.off = true
    if fxSame(e) then return (pcall(function() e.c:Deactivate() end)) end
    return false
end
local function fxAt(path, where, rot, scale, life, len)  -- an AC8 effect at a place (no pre-cull: seen from far), kept
    local lib, sys = StaticFindObject(NIAG), asset(path)
    if not (valid(lib) and sys and liveObj(survivalPC) and where) then return nil end
    local s = scale or 1
    local ok, c = pcall(function()
        return lib:SpawnSystemAtLocation(survivalPC, sys, where, rot or ROT0, { X = s, Y = s, Z = s }, true, true, 0, false)
    end)
    if not (ok and c) then return nil end
    if len then                                           -- (a beam's length, cm: sv_escort_laser.lua's)
        pcall(function() c:SetVariableFloat(FName("User.BeamLength"), len) end)
        pcall(function() c:SetVariableFloat(FName("BeamLength"), len) end)
    end
    return fxKeep(c, life, "at")
end
local function soundAt(path, where)                      -- a Wwise event by path at a place (two signatures)
    local ev, ak = asset(path), StaticFindObject(AK)
    if not (ev and valid(ak) and liveObj(survivalPC) and where) then return false end
    if pcall(function() ak:PostEventAtLocation(ev, where, ROT0, survivalPC) end) then return true end
    return (pcall(function() ak:PostEventAtLocation(ev, where, ROT0, "", survivalPC) end))
end
local function postOn(name, actor)                       -- a Wwise event by name on an actor: true and its id, or false, why
    if type(name) ~= "string" or name == "" then return false, "none" end
    local lib = StaticFindObject("/Script/Live.Default__LiveSoundBlueprintLibrary")
    if not valid(lib) then return false, "LiveSoundBlueprintLibrary not found" end
    local ok, id = pcall(function() return lib:PostEventAtActorByName(FName(name), actor) end)
    if not ok then return false, tostring(id):sub(1, 80) end
    return true, tostring(id)
end
-- the rotation from a to b and how far (cm), sv_escort_laser.lua's: an effect's turn, the spelling every spawn here takes
-- (a shot at the runway is within a degree of level, so a lost pitch would hardly show)
local function rot2(a, b)
    local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    local h = math.sqrt(dx * dx + dy * dy)
    return { Pitch = math.deg(math.atan(dz, h)), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }, math.sqrt(h * h + dz * dz)
end
-- the railguns' fire control row: the build's SV_FCS_TaniRail (rail_fcs.table) into the game's DT_NPC_FCS whole, with the other
-- rows at the main menu (sv_tanicorn.lua rowsIn), as sv_escort_laser.lua's ZFA row: its soft class never read (hard rule 29)
function TANI.railRow(fcs, k)
    local okH, have = dtCall(fcs, "FindRow", k.fcs)
    local how
    if okH and have ~= nil then how = "in already"
    else
        local mine, why = loadObject(k.fcs_table)
        if not mine then how = "NOT in: " .. tostring(k.fcs_table) .. " didn't load (" .. tostring(why) .. ")"
        else
            pin(mine, nameOf(mine))
            local okR, r = dtCall(mine, "FindRow", k.fcs)
            if not (okR and r ~= nil) then how = "NOT in: no such row in " .. short(mine)
            else
                dtCall(fcs, "AddRow", k.fcs, r)
                local okG, got = dtCall(fcs, "FindRow", k.fcs)
                how = (okG and got ~= nil) and "in (copied whole: its arm never read)" or "NOT added to DT_NPC_FCS"
            end
        end
    end
    local slots = "?"
    pcall(function()
        local _, r = dtCall(fcs, "FindRow", k.fcs)
        slots = tostring(r.SlotNum) .. ", magazine " .. tostring(r.MagazineCapacity) .. ", reload " .. tostring(r.ReloadTime)
    end)
    log(string.format("tanicorn: fire control row %s from %s: %s (SlotNum %s)", k.fcs, tostring(k.fcs_table):match("[^%.]+$") or "?",
        how, slots))
    return how:find("^in") ~= nil
end

---------------------------------------------------------------------------------------------------- the sub-railguns
-- one railgun's Deploy at its own time u (s, the cooked Deploy's clock): the hatches over 0-1.167 s, the lift over
-- 0.667-2.167 s, each a smoothstep (the cooked keys within 0.1 %); the bones that failed
local ONE = { X = 1, Y = 1, Z = 1 }
local function ss(a, b, t) local f = math.min(1, math.max(0, (t - a) / (b - a))); return f * f * (3 - 2 * f) end
local function qx(deg) local h = math.rad(deg) / 2; return { X = math.sin(h), Y = 0, Z = 0, W = math.cos(h) } end
local function pose(m, u)
    local d, z = HATCH_DEG * ss(0, 1.167, u), -600 + 600 * ss(0.667, DEPLOY_LEN, u)
    local bad = {}
    for _, b in ipairs({ { "lift", { X = 0, Y = 0, Z = 0, W = 1 }, 0, 0, z }, { "Hatch_n", qx(-d), 0, 460, -30 },
                         { "Hatch_p", qx(d), 0, -460, -30 } }) do
        local t = { Rotation = b[2], Translation = { X = b[3], Y = b[4], Z = b[5] }, Scale3D = ONE }
        local ok, err = pcall(function() m:SetBoneTransformByName(FName(b[1]), t, 1) end)   -- (EBoneSpaces 1: component)
        if not ok then bad[#bad + 1] = b[1] .. " (" .. tostring(err):sub(1, 60) .. ")" end
    end
    return bad
end
local function gunLog(e, s) log("tanicorn rail: " .. e.k.key .. " " .. s) end
local function barrel(e)                                  -- its barrel's { yaw, pitch, ... } (sv_tanicorn.lua aim), or nil
    if not TANI.aim then return nil end
    local ok, _, a = pcall(TANI.aim, e.o)
    if ok and type(a) == "table" and type(a.yaw) == "number" then return a end
    return nil
end
-- hard rule 45 on its arm: the minimap line and the RAILGUN HUD (a TripleRailCannon's fields), read back
local function railHud(e)
    local lm, cls = nil, "?"
    pcall(function() lm = e.o.FireControlSystemComponent.AllArms[1].LauncherModule end)
    if lm == nil then return "not written: no arm / launcher read", false end
    pcall(function() cls = lm:GetClass():GetFName():ToString() end)
    local okW = pcall(function() lm.IsDispRadarMap = true; lm.ForceAlertDisp = true; lm.HUDControl = 1 end)
    local rb = {}
    for _, f in ipairs({ "IsDispRadarMap", "ForceAlertDisp", "HUDControl" }) do
        local ok, v = pcall(function() return lm[f] end)
        rb[#rb + 1] = f .. " " .. (ok and tostring(v) or "?")
    end
    return string.format("%s: %s; read back %s", cls, okW and "written" or "NOT written (not a TripleRailCannon?)", table.concat(rb, ", ")), okW
end
local function orderTry(e, now, why)
    local G = TANI.railgun
    if joiner() then e.state = "up"; gunLog(e, "up: not ordered here (a joiner: the host orders it)"); return end
    if now < (e.retryAt or 0) then return end
    local held, note = nil, nil                          -- (held while paused, hard rule 60, and through the STORE and the
    if paused() then held, note = "the game paused", "held through it"   -- landing minigames, hard rule 64)
    else held = busy(); note = "an event fired there runs nothing: hard rule 64" end
    if held then
        if e.storeSaid ~= held then e.storeSaid = held; gunLog(e, "order held: " .. held .. " (" .. note .. ")") end
        return
    end
    e.storeSaid = nil
    local hud = ""
    if not e.hudDone then                                -- (hard rule 45 BEFORE its order; at the next order again until written)
        local txt, done = railHud(e)
        e.hudDone, hud = done == true, "; railgun HUD " .. tostring(txt)
    end
    local ev = ORDER[e.k.key]
    local ok, err = fire(ev)
    e.tries = e.tries + 1
    if ok then
        e.aim0, e.orderAt, e.checkAt, e.storeSeen, e.state = barrel(e), now, now + G.move_s, false, "ordered"
        gunLog(e, string.format("%s fired (try %d, %s)%s", ev, e.tries, why, hud))
    elseif e.tries >= G.tries then
        e.state = "gave up"
        gunLog(e, string.format("%s NOT fired (%s) after %d tries: gave up%s", ev, tostring(err), e.tries, hud))
    else
        e.retryAt = now + G.move_s
        gunLog(e, string.format("%s NOT fired (%s, try %d): again in %s s%s", ev, tostring(err), e.tries, g(G.move_s), hud))
    end
end
local function orderCheck(e, now)                        -- (hard rule 64) its barrel moved since the order, or the order again
    local G = TANI.railgun
    if paused() then e.checkAt = now + G.move_s; return end                     -- (the world frozen: looked at after)
    if busy() then e.checkAt, e.storeSeen = now + G.move_s, true; return end    -- (the AI held there: looked at after)
    if now < e.checkAt then return end
    local a = barrel(e)
    if not (a and e.aim0) then
        if e.storeSeen then
            e.state, e.retryAt = "order", 0
            orderTry(e, now, "again: the STORE was open since the order, its barrel can't be read")
        else
            e.state = "unchecked"
            gunLog(e, "its barrel can't be read: whether the order took isn't checked")
        end
        return
    end
    local dy = math.abs((a.yaw - e.aim0.yaw + 180) % 360 - 180)
    local dp = math.abs(a.pitch - e.aim0.pitch)
    if dy > G.move_deg or dp > G.move_deg then
        e.state = "moving"
        gunLog(e, string.format("its barrel moves (yaw %.1f -> %.1f, pitch %.1f -> %.1f) %.0f s after the order: it took",
            e.aim0.yaw, a.yaw, e.aim0.pitch, a.pitch, now - e.orderAt))
        return
    end
    if e.tries >= G.tries then
        e.state = "gave up"
        gunLog(e, string.format("its barrel never moved after %d orders (yaw %.1f, pitch %.1f): gave up (you out of its reach? its "
            .. "fire control row not in?)", e.tries, a.yaw, a.pitch))
        return
    end
    e.state, e.retryAt = "order", 0
    orderTry(e, now, string.format("again: its barrel still at yaw %.1f pitch %.1f %.0f s on%s", a.yaw, a.pitch, now - e.orderAt,
        e.storeSeen and ", the STORE was open" or ""))
end
local function liftCheck(e, now)                          -- its lift read again every check_s, written again if it fell back
    local G = TANI.railgun
    if now < (e.liftAt or 0) then return end
    e.liftAt = now + G.check_s
    local z = liftZ(e.mesh)
    if z and math.abs(z) > G.up_cm then
        pose(e.mesh, DEPLOY_LEN)
        e.falls = (e.falls or 0) + 1
        gunLog(e, string.format("its lift fell back to z %.0f cm (%d): the end pose written again", z, e.falls))
    end
end
local function gunStep(e, now, dt)
    local G = TANI.railgun
    if e.state == "wait" then
        if now - e.seenAt < G.after_s then return end
        e.mesh = TANI.partMesh and TANI.partMesh(e.o, e.k)
        if not e.mesh then e.state = "failed"; gunLog(e, "NOT ordered: no TurretPoseableMesh (PoseableMeshComponent) found on it"); return end
        e.state, e.t = "deploying", 0
        -- ((2026-11-16, the first in-game test: the lift read back up, SOC_Gun_01 stayed stowed as drawn) a PoseableMesh
        -- refreshes its bones from what's written only while it ticks its pose, and the railguns' (mount()) had no
        -- VisibilityBasedAnimTickOption: OnlyTickPoseWhenRendered, so nothing written was drawn with her off your screen.
        -- The railcannon, which deployed, ticks always (AlwaysTickPoseAndRefreshBones = 0). Set here before the writes
        -- (G.tick_always), read back in the line)
        local tick = "left as cooked"
        if G.tick_always ~= false then
            pcall(function() e.mesh.VisibilityBasedAnimTickOption = 0 end)
            pcall(function() e.mesh.bEnableUpdateRateOptimizations = false end)
            local okT, v = pcall(function() return e.mesh.VisibilityBasedAnimTickOption end)
            tick = "its pose ticked always (VisibilityBasedAnimTickOption read back " .. tostring(okT and v or "?") .. ")"
        end
        gunLog(e, string.format("deploying at +%.1f s over %.1f s: lift z %s cm, SOC_Gun_01 z %s cm in the mesh (stowed: -600 / -196); %s",
            now - e.seenAt, G.deploy_s, cm(liftZ(e.mesh)), cm(sockZ(e.mesh)), tick))
    elseif e.state == "deploying" then
        if paused() then return end
        e.t = e.t + dt
        for _, b in ipairs(pose(e.mesh, math.min(1, e.t / math.max(0.05, G.deploy_s)) * DEPLOY_LEN)) do e.bad[#e.bad + 1] = b end
        if e.t >= G.deploy_s then e.state, e.writes = "check", 1 end
    elseif e.state == "check" then                       -- (a tick after its last write: the pose drawn since)
        local z, why = liftZ(e.mesh)                     -- (as written)
        local sz, swhy = sockZ(e.mesh)                   -- (as drawn: where its fire control fires from)
        local fails = #e.bad > 0 and ("; writes that failed: " .. table.concat(e.bad, ", ", 1, math.min(3, #e.bad))) or ""
        local liftUp = z ~= nil and math.abs(z) <= G.up_cm
        if liftUp and sz and sz >= G.raised_cm then
            e.state = "order"
            gunLog(e, string.format("deployed: lift z %.0f cm (up), SOC_Gun_01 z %.0f cm in the mesh (raised ~+404)%s", z, sz, fails))
            orderTry(e, now, "its deploy read back")
        elseif z and (sz or not liftUp) and e.writes < G.writes then
            e.writes = e.writes + 1
            pose(e.mesh, DEPLOY_LEN)
            gunLog(e, liftUp and string.format("its lift reads z %.0f cm (up) but SOC_Gun_01 z %.0f cm in the mesh as drawn after its "
                .. "deploy: the end pose written again (%d of %s)", z, sz, e.writes, g(G.writes))
                or string.format("its lift reads z %.0f cm after its deploy: the end pose written again (%d of %s)", z, e.writes, g(G.writes)))
        else
            e.state = "failed"
            local r
            if not z then r = "its lift can't be read back (" .. tostring(why) .. ")"
            elseif not liftUp then r = string.format("its lift still reads z %.0f cm after %d writes (the pose doesn't take?)", z, e.writes)
            elseif not sz then r = "SOC_Gun_01 can't be read back as drawn (" .. tostring(swhy) .. ")"
            else r = string.format("SOC_Gun_01 still z %.0f cm in the mesh as drawn after %d writes, its lift z %.0f cm (written, "
                .. "not drawn?)", sz, e.writes, z) end
            gunLog(e, "NOT ordered: " .. r .. ": a gun inside the hull isn't ordered" .. fails)
        end
    elseif e.state == "order" then
        orderTry(e, now, "its deploy read back")
    elseif e.state == "ordered" then
        orderCheck(e, now)
    end
    if e.mesh and (e.state == "ordered" or e.state == "moving" or e.state == "unchecked" or e.state == "up" or e.state == "gave up") then
        liftCheck(e, now)
    end
end
local function gunsTick(now, dt)
    local seen = TANI.liveSeen and TANI.liveSeen()
    for _, k in ipairs(TANI.rail or {}) do
        local s = (not k.cannon) and seen and seen[k.key] or nil
        local e = RG[k.key]
        if s and same(s) and not (e and e.a == s.a and e.name == s.name) then   -- (new, or another object there now)
            RG[k.key] = { o = s.o, a = s.a, name = s.name, k = k, state = "wait", seenAt = now, t = 0, writes = 0, bad = {}, tries = 0 }
            gunLog(RG[k.key], string.format("Part_%s %s seen: deploying in %s s (its lift and hatches written in component space, then "
                .. "read back: ordered only with its lift up)", k.key, short(s.o), g(TANI.railgun.after_s)))
        end
    end
    for key, e in pairs(RG) do
        if not same(e) then
            if e.state ~= "down" then gunLog(e, "gone (its actor no longer there): forgotten") end
            RG[key] = nil
        elseif e.state ~= "down" then
            local h = hp(e.o)
            if h and h <= 0 then
                gunLog(e, "shot down (" .. e.state .. "): its deploy and orders over")
                e.state = "down"
            else
                gunStep(e, now, dt)
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- the railcannon
local function rcc() local f = CFG and CFG.specials and CFG.specials.fleet; return type(f) == "table" and f.railcannon or nil end
local function text(key, d) local c = rcc(); local t = c and c.text; return (type(t) == "table" and t[key]) or d end
local function seenRc()                                   -- Ctrl+L's railcannon now: { o, a, name, key }, or nil
    local seen = TANI.liveSeen and TANI.liveSeen()
    local e = seen and seen.RAILCANNON
    if e and same(e) then return e end
    return nil
end
-- its shield: the Alicorn's part flags (no box, not lockable, no fire control's target, invincible) and SetIsInvincible on,
-- or back as they were when first shielded; the read-back
local function shield(e, on)
    local F = (SPC and SPC.V and SPC.V.PART_FLAGS) or FLAGS0
    e.was = e.was or {}
    if on then for f in pairs(F) do if e.was[f] == nil then pcall(function() e.was[f] = e.o[f] end) end end end
    local n = 0
    for f, v in pairs(F) do
        local to = v
        if not on then to = e.was[f]; if to == nil then to = not v end end
        if pcall(function() e.o[f] = to end) then n = n + 1 end
    end
    local okI = pcall(function() e.o:SetIsInvincible(on) end)
    e.on = on
    local rb = {}
    for _, f in ipairs(FLAG_NAMES) do
        local ok, v = pcall(function() return e.o[f] end)
        rb[#rb + 1] = f .. " " .. (ok and tostring(v) or "?")
    end
    return string.format("%d flags written, SetIsInvincible(%s) %s; read back %s", n, tostring(on), okI and "called" or "FAILED",
        table.concat(rb, ", "))
end
local function shieldTick()                               -- shielded from the first tick it's seen (a new object: again)
    local e = seenRc()
    if e and not (SH and SH.a == e.a and SH.name == e.name) then
        SH = { o = e.o, a = e.a, name = e.name }
        log("tanicorn rc: Part_RAILCANNON " .. short(e.o) .. " seen: shielded while stowed (" .. shield(SH, true) .. ")")
    end
end
-- its health in your standard missiles (SPC.playerMissileDamage: HealthInternal is health x 10), once an object, only lowered
local function sizeHealth(c)
    if SH and SH.sized then return "its health sized before: " .. tostring((hp(RC.o))) end
    local d
    if SPC and type(SPC.playerMissileDamage) == "function" then
        local ok, v = pcall(SPC.playerMissileDamage)
        if ok then d = tonumber(v) end
    end
    local h0 = hp(RC.o)
    if not d or d <= 0 then                              -- (read again every 2 s, size_tries in all: the Alicorn's 5)
        local n, most = 1, num(c.size_tries, 5)
        if SH then SH.tries = (SH.tries or 0) + 1; n = SH.tries; if n >= most then SH.sized = true end end
        return string.format("its health left at its row's (your missile's damage unread, try %d of %s%s): %s", n, g(most),
            n < most and ": again in 2 s" or "", tostring(h0))
    end
    if SH then SH.sized = true end
    local players = 1
    if COOP and type(COOP.players) == "function" then
        local ok, l = pcall(COOP.players)
        if ok and type(l) == "table" then players = math.max(1, #l) end
    end
    local miss = num(c.missiles, 8) * (1 + num(c.per_player, 0.5) * (players - 1))
    local want = math.floor(miss * d * 10 + 0.5)
    if h0 and want < h0 then
        local okW = pcall(function() RC.o.HealthInternal = want end)
        return string.format("health set to %.1f missiles (%s HealthInternal: %s x 10 x %.1f, players %d)%s", miss, tostring((hp(RC.o))),
            tostring(d), miss, players, okW and "" or ": NOT written")
    end
    return string.format("health kept at %s HealthInternal (%.1f missiles of %s would be %d: only ever lowered, never above its row's)",
        tostring(h0), miss, tostring(d), want)
end
local function alert(on)                                 -- the RAILGUN WARNING (forwarded to every game; hard rule 45)
    local ev = on and "RE_SV_AlcnAlertOn" or "RE_SV_AlcnAlertOff"
    if not on and busy() then PEND[ev] = true; return false, "held for the STORE's end (hard rule 64)" end
    return fire(ev)
end
local function target(c, centre)                          -- a spot on the runway (its centre, or spread along / across it)
    local r = c.runway or {}
    local x, y, z, yaw = num(r[1], 1609574), num(r[2], -435747), num(r[3], 500), math.rad(num(r[4], -23))
    local along = centre and 0 or (math.random() * 2 - 1) * num(c.spread_m, 600) * 100
    local across = centre and 0 or (math.random() * 2 - 1) * num(c.across_m, 15) * 100
    return { X = x + math.cos(yaw) * along - math.sin(yaw) * across, Y = y + math.sin(yaw) * along + math.cos(yaw) * across, Z = z }
end
local function offDeg(m, P)                               -- the barrel's heading off the line from its muzzle to P (deg)
    local ok, d = pcall(function()
        local q, p = m:GetSocketLocation(FName(MUZZLE)), m:GetSocketLocation(FName("railcannon_pitch"))
        local a = math.deg(math.atan(q.Y - p.Y, q.X - p.X) - math.atan(P.Y - q.Y, P.X - q.X))
        return math.abs((a + 180) % 360 - 180)
    end)
    if ok and type(d) == "number" then return d end
    return nil
end
local function muzzleAt()                                 -- the muzzle in the world (its actor's place if unread)
    local ok, q = pcall(function() local v = RC.mesh:GetSocketLocation(FName(MUZZLE)); return { X = v.X, Y = v.Y, Z = v.Z } end)
    if ok and q then return q end
    local okA, l = pcall(function() local v = RC.o:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    return okA and l or nil
end
local function chargeFx(c)                                -- her discharge on SOC_Gun_01 (else her root, at the muzzle): record, line
    local ch = (c.fx or {}).charge or {}
    local lib, sys, sc = StaticFindObject(NIAG), asset(ch[1]), num(ch[2], 1)
    if not (valid(lib) and sys) then return nil, "NOT up (" .. (sys and "no Niagara library" or "its system didn't load") .. ")" end
    local ok, comp = pcall(function()
        return lib:SpawnSystemAttached(sys, RC.mesh, FName(MUZZLE), { X = 0, Y = 0, Z = 0 }, ROT0, 0, true, true, 0, false)
    end)
    local e = (ok and comp) and fxKeep(comp, nil, "charge") or nil
    local where = "up on " .. MUZZLE
    if not e then                                         -- (attaching to a socket is new here: the root's the fallback)
        local okR, c2 = pcall(function()
            local q, b = RC.mesh:GetSocketLocation(FName(MUZZLE)), RC.o:K2_GetActorLocation()
            local f, r, u = RC.o:GetActorForwardVector(), RC.o:GetActorRightVector(), RC.o:GetActorUpVector()
            local dx, dy, dz = q.X - b.X, q.Y - b.Y, q.Z - b.Z
            local off = { X = dx * f.X + dy * f.Y + dz * f.Z, Y = dx * r.X + dy * r.Y + dz * r.Z, Z = dx * u.X + dy * u.Y + dz * u.Z }
            return lib:SpawnSystemAttached(sys, RC.o:K2_GetRootComponent(), FName("None"), off, ROT0, 0, true, true, 0, false)
        end)
        e = (okR and c2) and fxKeep(c2, nil, "charge") or nil
        where = "up on its root (" .. MUZZLE .. " refused: " .. tostring(ok and "nothing back" or comp):sub(1, 60) .. ")"
        if not e then return nil, "NOT up (" .. tostring(okR and "nothing back" or c2):sub(1, 60) .. ")" end
    end
    if sc ~= 1 then pcall(function() e.c:SetWorldScale3D({ X = sc, Y = sc, Z = sc }) end) end
    return e, where
end
local function chargeAlive(e)                             -- its discharge still there and on (unreadable: on)
    if not e or e.off or not fxSame(e) then return false end
    local ok, a = pcall(function() return e.c:IsActive() end)
    return not ok or a ~= false
end
-- her cannon's charge RTPC on her: true, or false and why. (2026-11-16, the first in-game test: AC8's
-- UAkGameplayStatics::SetRTPCValue takes (UAkRtpc*, Value, InterpolationTimeMs, Actor), no name, so the name went to the
-- AkComponent that her charge sound's post puts on her: UAkGameObject::SetRTPCValue(nil, Value, ms, RTPC name), a UFUNCTION;
-- build/liveproject/Source/AkAudio/Public/AkGameObject.h:45)
local AKC = "/Script/AkAudio.AkComponent"
local function rtpc(c, v)
    local snd = c.sound or {}
    local name = snd.rtpc or "EX03_CANNON_CHARGE"
    local list = (SPC and SPC.V and SPC.V.comps) and SPC.V.comps(RC.o, AKC) or {}
    if #list == 0 then return false, "no AkComponent on her (her charge sound not posted yet?)" end
    local err
    for _, comp in ipairs(list) do
        local ok, e = pcall(function() comp:SetRTPCValue(nil, v, 250, name) end)
        if ok then return true end
        err = e
    end
    return false, tostring(err):sub(1, 80)
end
local function damageOf(c)                                -- the shot's damage: of the airfield's CFG.airfield.hp, scaled to its max
    local d = num(c.damage, 100)
    local base = CFG and CFG.airfield and num(CFG.airfield.hp, 0) or 0
    if c.damage_of_max ~= false and AF and tonumber(AF.max) and base > 0 then d = d * AF.max / base end
    return math.floor(d + 0.5)
end
local function shake(c, at)
    local you = playerLocation()
    local km_ = you and math.sqrt((you.X - at.X) ^ 2 + (you.Y - at.Y) ^ 2 + (you.Z - at.Z) ^ 2) / 100000 or math.huge
    local reach = num(c.shake_km, 8)
    if not c.shake or km_ > reach then return string.format("none: you're %.1f km off", km_) end
    local cls = asset(c.shake, true)
    if not cls then return "NOT loaded" end
    local sc = math.max(0.2, 1 - km_ / reach)
    local ok = pcall(function() survivalPC:ClientStartCameraShake(cls, sc, 0, ROT0) end)
    if not ok then ok = pcall(function() survivalPC.PlayerCameraManager:StartCameraShake(cls, sc, 0, ROT0) end) end
    return ok and string.format("played at %.1f km", km_) or "FAILED"
end
-- the shot's and the impact's effects (AC8's own only: hard rule 58), each stopped after its life: how many came back of how
-- many, and the streak's. Local to this game (a co-op message can call it on each joiner later: WP12)
function TANI.rcFx(kind, M, P, rot, len)
    local c = rcc() or {}
    local fx, life = c.fx or {}, num(c.fx_life_s, 6)
    local up, of, sUp, sOf = 0, 0, 0, 0
    if kind == "shot" then
        for _, e in ipairs(fx.muzzle or {}) do of = of + 1; if fxAt(e[1], M, rot, num(e[2], 1), life) then up = up + 1 end end
        local s = fx.streak or {}
        if s.mode == "beam" then
            sOf = 1
            if fxAt(s.fx, M, rot, 1, num(s.life_s, 0.8), len) then sUp = 1 end
        elseif s.mode == "trail" and len and len > 0 then   -- (a spot every step_km, each as the round passes it)
            local n = math.max(1, math.floor(len / (num(s.step_km, 1) * 100000)))
            local speed = num(c.speed_kms, 11.1) * 100000
            for i = 1, n do
                local f = i / n
                TRAIL[#TRAIL + 1] = { at = os.clock() + f * len / speed, path = s.trail, rot = rot, life = life,
                                      where = { X = M.X + (P.X - M.X) * f, Y = M.Y + (P.Y - M.Y) * f, Z = M.Z + (P.Z - M.Z) * f } }
            end
            sOf = n
        end
    else
        for _, e in ipairs(fx.impact or {}) do of = of + 1; if fxAt(e[1], P, ROT0, num(e[2], 1), life) then up = up + 1 end end
    end
    return up, of, sUp, sOf
end
local function rcLog(s) log("tanicorn rc: " .. s) end
local function rcEnd(why, opt)                            -- the cycle over: its warning and effects off; opt.stow: stowed, shielded
    opt = opt or {}
    local R = RC
    if not R then return end
    RC = nil
    local c = rcc() or {}
    local done = {}
    if R.state == "charge" and not R.dead and same(R) then
        local okS = postOn((c.sound or {}).charge_stop, R.o)
        done[#done + 1] = "its charge sound " .. (okS and "stopped" or "NOT stopped")
    end
    if fxStop(R.cfx) then done[#done + 1] = "its charge effect off" end
    if R.alertOn then
        local okA, whyA = alert(false)
        done[#done + 1] = "RE_SV_AlcnAlertOff " .. (okA and "fired" or ("not fired: " .. tostring(whyA)))
    end
    TRAIL = {}
    if opt.stow and same(R) and R.mesh then
        local okP = pcall(function() R.mesh:SetPlayRate(-1) end)
        if not pcall(function() R.mesh:Play(false) end) then okP = false end
        done[#done + 1] = "stowed (its Deploy played back" .. (okP and "" or ": SetPlayRate / Play FAILED") .. ")"
        if SH and SH.a == R.a and SH.name == R.name then done[#done + 1] = "shielded again (" .. shield(SH, true) .. ")" end
    end
    rcLog(string.format("cycle over (%s) at +%.1f s: %d charges, %d shots, %d impacts (-%d airfield in all)%s", why, R.t, R.n, R.shots,
        R.impacts, R.dealt, #done > 0 and ("; " .. table.concat(done, ", ")) or ""))
end
local function rcDown(gone)                               -- shot down (health 0, or gone): no impact from a charge, a round in
    local c = rcc() or {}                                 -- flight lands
    local R = RC
    local done = {}
    R.dead = true
    if R.state == "charge" then
        if gone then done[#done + 1] = "its charge sound left (its actor gone: nothing posted on it)"
        else
            local okS = postOn((c.sound or {}).charge_stop, R.o)
            done[#done + 1] = "its charge sound " .. (okS and "stopped" or "NOT stopped")
        end
        if fxStop(R.cfx) then done[#done + 1] = "its charge effect off" end
        R.cfx = nil
    end
    if R.alertOn then
        local okA, whyA = alert(false)
        R.alertOn = false
        done[#done + 1] = "RE_SV_AlcnAlertOff " .. (okA and "fired" or ("not fired: " .. tostring(whyA)))
    end
    local lands = R.state == "flight" and c.flight_lands ~= false
    hudCallout(text("down", "TANACORN RAILCANNON DOWN"), text("down_sub", "THE AIRFIELD IS SAFE"))
    rcLog(string.format("Part_RAILCANNON %s at +%.1f s (in its %s): %s; %s", gone and "gone with her hull up: taken as shot down"
        or "shot down", R.t, R.state,
        #done > 0 and table.concat(done, ", ") or "nothing to stop",
        lands and "its round in flight still lands" or "no impact"))
    if TANI.coreOpen then pcall(TANI.coreOpen, "the railcannon down") end
    if not lands then rcEnd("shot down") end
end
local function chargeStart()
    local c = rcc() or {}
    local R = RC
    R.n, R.state, R.chargeAt, R.lineAt, R.alertOffW = R.n + 1, "charge", R.t, R.t + 5, nil
    R.playSaid, R.warned, R.offSaid, R.refireAt = false, false, false, R.t + num(c.refire_s, 2)
    local cs = num(c.charge_s, 30)
    local al = "off"
    if (c.alert or {}).enabled ~= false then
        local okA, whyA = alert(true)
        R.alertOn = okA
        al = "RE_SV_AlcnAlertOn " .. (okA and "fired" or ("not fired: " .. tostring(whyA)))
    end
    hudCallout(text("aim", "THE TANACORN IS AIMING AT THE AIRFIELD"), fmt(text("aim_sub", "RAILCANNON CHARGING: %d S"), math.floor(cs + 0.5)))
    local radio = "off"
    if c.radio ~= false then
        radio = "not said"
        if TELL and type(TELL.say) == "function" then
            local okT, said, why = pcall(TELL.say, R.n == 1 and "alcn_rail_first" or "alcn_rail", TELL.ALL)
            if okT and said == true then radio = "said"
            else radio = "not said (" .. tostring(okT and why or said) .. ")" end   -- ((2026-11-16) its why, the test's "not said")
        end
    end
    local e, where = chargeFx(c)
    R.cfx = e
    local okI, id = postOn((c.sound or {}).rtpc_init, R.o)
    rcLog(string.format("charge %d at +%.1f s (%s s): RAILGUN WARNING %s; NS_alcn_RailCannonDischarge_ON %s; RTPC_Init %s; radio %s",
        R.n, R.t, g(cs), al, where, okI and ("posted (id " .. id .. ")") or ("NOT posted: " .. tostring(id)), radio))
end
local function shot()
    local c = rcc() or {}
    local R = RC
    local P = target(c)
    local off = R.mesh and offDeg(R.mesh, P)
    if off and off > num(c.max_off_deg, 180) then         -- (held until she points: max_off_deg under 180)
        if not R.offSaid then R.offSaid = true; rcLog(string.format("shot %d held: the barrel %.0f deg off the runway", R.n, off)) end
        return
    end
    fxStop(R.cfx)
    R.cfx = nil
    local snd = c.sound or {}
    postOn(snd.charge_end, R.o)
    local M = muzzleAt() or P
    local rot, len = rot2(M, P)
    local okF, up, of, sUp, sOf = pcall(TANI.rcFx, "shot", M, P, rot, len)
    if not okF then up, of, sUp, sOf = 0, 0, 0, 0 end
    local okS = soundAt(snd.shot, M)
    local you = playerLocation()
    if you and snd.pass then                              -- (its pass where the line comes nearest you)
        local dx, dy, dz = P.X - M.X, P.Y - M.Y, P.Z - M.Z
        local l2 = dx * dx + dy * dy + dz * dz
        local f = l2 > 0 and math.max(0, math.min(1, ((you.X - M.X) * dx + (you.Y - M.Y) * dy + (you.Z - M.Z) * dz) / l2)) or 0
        soundAt(snd.pass, { X = M.X + dx * f, Y = M.Y + dy * f, Z = M.Z + dz * f })
    end
    local fl = math.max(num(c.flight_min_s, 0.5), len / (num(c.speed_kms, 11.1) * 100000))
    R.state, R.impactAt, R.P, R.shots = "flight", R.t + fl, P, R.shots + 1
    local mode = ((c.fx or {}).streak or {}).mode or "off"
    rcLog(string.format("SHOT %d at +%.1f s: muzzle (%.1f, %.1f, %.2f) km -> runway (%.1f, %.1f) km, %.1f km, the round there in %.1f s; "
        .. "muzzle fx %d of %d up; streak %s %s; shot sound %s", R.n, R.t, M.X / 1e5, M.Y / 1e5, M.Z / 1e5, P.X / 1e5, P.Y / 1e5,
        len / 1e5, fl, up, of, mode, mode == "trail" and (sOf .. " spots queued") or (sUp .. " of " .. sOf .. " up"),
        okS and "posted" or "NOT posted"))
end
local function impact()
    local c = rcc() or {}
    local R = RC
    R.impacts = R.impacts + 1
    local dmg = damageOf(c)
    local said
    if joiner() then said = "a joiner: the host's airfield takes it"
    elseif not (CFG and CFG.airfield and CFG.airfield.enabled) then said = "the airfield is off: no damage"
    elseif not AF or AF.down or not AF.bomb then said = "the airfield is down: no damage"
    else
        local b0, h0 = AF.bomb, AF.hp
        AF.bomb = AF.bomb + dmg
        R.dealt = R.dealt + dmg
        said = string.format("-%d airfield (AF.bomb %s -> %s; health before %s)", dmg, tostring(b0), tostring(AF.bomb), tostring(h0))
        hudCallout(text("hit", "THE AIRFIELD IS HIT"), fmt(text("hit_sub", "TANACORN RAILCANNON: -%d"), dmg))
    end
    local okF, up, of = pcall(TANI.rcFx, "impact", nil, R.P)
    if not okF then up, of = 0, 0 end
    local okS = soundAt((c.sound or {}).impact, R.P)
    rcLog(string.format("impact %d at +%.1f s: %s; impact fx %d of %d up, its sound %s, the shake %s", R.impacts, R.t, said, up, of,
        okS and "posted" or "NOT posted", shake(c, R.P)))
    R.state, R.alertOffW = "wait", os.clock() + num((c.alert or {}).off_after_s, 3)
    if R.dead then rcEnd("shot down: its last round landed") end
end
local function deployEnd()
    local c = rcc() or {}
    local R = RC
    local pos, len = "?", "?"
    pcall(function() pos = string.format("%.2f", R.mesh:GetPosition()) end)
    pcall(function() len = string.format("%.2f", R.anim:GetPlayLength()) end)
    local z1, P = sockZ(R.mesh), target(c, true)
    local up = num(c.raised_cm, 2500)                    -- ((the review, finding 2) as the railguns': never from inside her hull)
    if not (z1 and z1 >= up) then
        R.redeploys = (R.redeploys or 0) + 1
        local what = string.format("position %s of %s s, SOC_Gun_01 z %s cm in the mesh (from %s; raised: at least %s)", pos, len, cm(z1),
            cm(R.z0), g(up))
        if R.redeploys <= num(c.redeploys, 1) then
            local fails = {}
            if not pcall(function() R.mesh:SetPosition(0, false) end) then fails[#fails + 1] = "SetPosition 0 FAILED" end
            if not pcall(function() R.mesh:SetPlayRate(1) end) then fails[#fails + 1] = "SetPlayRate FAILED" end
            if not pcall(function() R.mesh:Play(false) end) then fails[#fails + 1] = "Play FAILED" end
            R.t = 0
            rcLog(string.format("its Deploy not up at +%.1f s: %s: played again (%d of %s), still shielded%s", num(c.deploy_s, 3.4), what,
                R.redeploys, g(num(c.redeploys, 1)), #fails > 0 and ("; " .. table.concat(fails, ", ")) or ""))
            return
        end
        rcLog(string.format("NOT deployed: %s after %d plays: kept shielded, no charge (a railcannon inside her hull doesn't fire)",
            what, R.redeploys))
        rcEnd("its Deploy didn't take")
        return
    end
    local off = offDeg(R.mesh, P)
    local M = muzzleAt()
    local km_ = M and math.sqrt((P.X - M.X) ^ 2 + (P.Y - M.Y) ^ 2) / 1e5 or nil
    local sh = "no shield record"
    if SH and SH.a == R.a and SH.name == R.name then sh = shield(SH, false) end
    rcLog(string.format("deployed at +%.1f s: position %s of %s s, SOC_Gun_01 z %s cm in the mesh (from %s: %s m; ~+18.9 m if it rose), "
        .. "the barrel %s deg off the line to the runway (%s km); shield off (%s); %s", R.t, pos, len, cm(z1), cm(R.z0),
        (z1 and R.z0) and string.format("%+.1f", (z1 - R.z0) / 100) or "?", off and string.format("%.0f", off) or "?",
        km_ and string.format("%.1f", km_) or "?", sh, sizeHealth(c)))
    R.state, R.chargeAt, R.sizeAt = "wait", R.t - num(c.every_s, 90), R.t + 2   -- ((finding 6) the first charge at the next
end                                                       -- tick nothing holds: the STORE, landed alone, the airfield down)
local function holdWhy(c)                                 -- why the cycle's clock waits now, or nil
    local H = c.hold or {}
    if H.paused ~= false and paused() then return "the game paused" end
    if RC.state == "deploy" then return nil end           -- (its Deploy plays in the world: only a pause holds it)
    if H.store ~= false and store() then return "the STORE open" end
    if H.store ~= false then local b = busy(); if b then return b end end
    if H.landed_alone ~= false and landedAlone() then return "you landed with nobody else flying" end
    if RC.state == "wait" and H.af_down ~= false and AF and AF.down then return "the airfield down" end
    return nil
end
local function rcTick(now, dt)
    local c = rcc() or {}
    local R = RC
    if R.D ~= D then rcEnd("a new run"); return end
    if not R.dead then                                    -- (shot down with a round in flight: only the round's left)
        local H = TANI.liveHull and TANI.liveHull()
        if not H or (R.hull ~= nil and H ~= R.hull) then rcEnd("the hull is gone"); return end
        if not same(R) then                               -- ((the review, finding 3) gone, her hull up: shot down, as the
            rcDown(true); if not RC then return end       -- Alicorn's parts; nothing done to what's at its address now)
        else
            local h = hp(R.o)
            if h and h <= 0 then rcDown(); if not RC then return end end
        end
    end
    if not R.dead and R.sizeAt and R.t >= R.sizeAt and SH and SH.a == R.a and SH.name == R.name and not SH.sized then
        R.sizeAt = R.t + 2
        rcLog("health: " .. sizeHealth(c))
    end
    if R.alertOn and R.alertOffW and now >= R.alertOffW then   -- (the warning off_after_s after its impact, on the wall's
        local okA, whyA = alert(false)                         -- clock: no hold keeps it up; in the STORE it waits there)
        R.alertOn, R.alertOffW = false, nil
        if not okA then rcLog("RE_SV_AlcnAlertOff not fired: " .. tostring(whyA)) end
    end
    local why = holdWhy(c)
    if why ~= R.held then
        rcLog(why and string.format("the clock held at +%.1f s (%s)", R.t, why) or string.format("the clock goes on at +%.1f s", R.t))
        R.held = why
    end
    if why then return end
    R.t = R.t + dt
    if R.state == "deploy" then
        if R.t >= num(c.deploy_s, 3.4) then deployEnd() end
    elseif R.state == "charge" then
        local cs, snd = num(c.charge_s, 30), c.sound or {}
        local tc, s0 = R.t - R.chargeAt, cs - num(snd.charge_sound_s, 20)
        if not R.playSaid and tc >= s0 then
            R.playSaid = true
            local okP, id = postOn(snd.charge, R.o)
            rcLog(string.format("Charge_Play %s at +%.1f s", okP and ("posted (id " .. id .. ")") or ("NOT posted: " .. tostring(id)), R.t))
        end
        local from, to = num(snd.rtpc_from, 50), num(snd.rtpc_to, 100)
        R.rtpcV = from + (to - from) * math.max(0, math.min(1, (tc - s0) / math.max(0.1, cs - s0)))
        local okR, whyR = rtpc(c, R.rtpcV)
        R.rtpcSay = okR and "set" or ("SetRTPCValue failed: " .. tostring(whyR))
        if not R.rtpcSaid then R.rtpcSaid = true; rcLog("RTPC " .. tostring(snd.rtpc) .. ": " .. R.rtpcSay .. " (said once a cycle)") end
        if not R.warned and tc >= cs - num(c.warn_left_s, 10) then
            R.warned = true
            hudCallout(fmt(text("soon", "RAILCANNON FIRING IN %d S"), math.floor(num(c.warn_left_s, 10) + 0.5)), "")
        end
        if c.refire ~= false and R.t >= R.refireAt then   -- (her discharge ended by itself before the shot: again)
            R.refireAt = R.t + num(c.refire_s, 2)
            if not chargeAlive(R.cfx) then
                fxStop(R.cfx)
                local e, where = chargeFx(c)
                R.cfx, R.refires = e, (R.refires or 0) + 1
                if R.refires == 1 then rcLog(string.format("its charge effect ended at +%.1f s of %s: spawned again (%s)", tc, g(cs), where)) end
            end
        end
        if R.t >= R.lineAt then
            R.lineAt = R.t + 5
            local off, h, mx = offDeg(R.mesh, target(c, true)), hp(R.o)
            rcLog(string.format("charge %d +%.0f/%s s: health %s/%s, RTPC %s %.0f (%s), the barrel %s deg off the runway%s", R.n, tc, g(cs),
                tostring(h), tostring(mx), tostring(snd.rtpc), R.rtpcV, R.rtpcSay, off and string.format("%.0f", off) or "?",
                (R.refires or 0) > 0 and string.format(", its effect spawned %d more times", R.refires) or ""))
        end
        if tc >= cs then shot() end
    elseif R.state == "flight" then
        if R.t >= R.impactAt then impact() end
    elseif R.state == "wait" then
        if R.t >= R.chargeAt + num(c.every_s, 90) then chargeStart() end
    end
end
-- one line for the live watch (sv_tanicorn.lua aimOf: its every-5 s lines): its Deploy's place, its muzzle, its cycle
function TANI.rcLine(o)
    local m = (TANI.partMesh and RCK) and TANI.partMesh(o, RCK) or nil
    if not m then return "no TurretMesh (SkeletalMeshComponent) found" end
    local pos, playing = "?", "?"
    pcall(function() pos = string.format("%.2f", m:GetPosition()) end)
    pcall(function() playing = tostring(m:IsPlaying()) end)
    local st = (SH and SH.a == addrOf(o)) and (SH.on and "stowed, shielded" or "unshielded") or "not shielded yet"
    if RC and RC.a == addrOf(o) then
        local c = rcc() or {}
        if RC.state == "charge" then st = string.format("charge %d +%.0f/%s s", RC.n, RC.t - RC.chargeAt, g(num(c.charge_s, 30)))
        elseif RC.state == "wait" then st = string.format("the next charge in %.0f s", RC.chargeAt + num(c.every_s, 90) - RC.t)
        else st = RC.state end
        if RC.held then st = st .. " (held: " .. RC.held .. ")" end
    end
    return string.format("deploy at %s s (playing %s), SOC_Gun_01 z %s cm in the mesh; %s", pos, playing, cm(sockZ(m)), st)
end
-- Ctrl+H's start (and WP11's phase 2 later: why), or its stop when the cycle's on: true, or false and why not
function TANI.rcStart(why)
    if RC then rcEnd(why .. " again", { stow = true }); hudCallout("TEST: TANACORN RAILCANNON", "STOWED"); return true, "stopped" end
    local function no(msg, sub)
        rcLog(why .. " refused: " .. msg)
        hudCallout("TEST: TANACORN RAILCANNON", sub)
        return false, msg
    end
    if not (D and D.now) or not nativeReady() then return no("outside a Survival run", "NOT IN A RUN") end
    if joiner() then return no("the host's railcannon (you're a joiner)", "THE HOST'S") end
    if store() then return no("the STORE is open (an event fired there runs nothing: hard rule 64)", "NOT IN THE STORE") end
    local b = busy()
    if b then return no(b .. " (an event fired there runs nothing: hard rule 64)", "NOT NOW") end
    local c = rcc()
    if not c or c.enabled == false then return no("off (CFG.specials.fleet.railcannon)", "OFF") end
    if not (TANI.liveHull and TANI.liveHull()) then return no("no live hull of ours up: Ctrl+L first", "CTRL+L FIRST") end
    local e = seenRc()
    if not e then
        return no("her live hull has no Part_RAILCANNON child (a container cooked before the railcannon blueprint: "
            .. "tools/tanicorn/build.sh, then TANI=1 build_all.sh)", "NO RAILCANNON")
    end
    local h = hp(e.o)
    if h and h <= 0 then return no("Part_RAILCANNON is down (health " .. tostring(h) .. ")", "IT'S DOWN") end
    local m = TANI.partMesh and RCK and TANI.partMesh(e.o, RCK)
    if not m then return no("no TurretMesh (SkeletalMeshComponent) on Part_RAILCANNON (a container cooked before its blueprint?)", "NO MESH") end
    if not (SH and SH.a == e.a and SH.name == e.name) then
        SH = { o = e.o, a = e.a, name = e.name }
        rcLog("Part_RAILCANNON " .. short(e.o) .. " seen: shielded while stowed (" .. shield(SH, true) .. ")")
    end
    local anim = asset(RCK.anim)
    local z0 = sockZ(m)
    local fails = {}
    if not pcall(function() m:SetAnimationMode(1, false) end) then fails[#fails + 1] = "SetAnimationMode FAILED" end
    if not anim then fails[#fails + 1] = "its animation NOT loaded (" .. RCK.anim .. ")"
    elseif not pcall(function() m:SetAnimation(anim) end) then fails[#fails + 1] = "SetAnimation FAILED" end
    if not pcall(function() m:SetPosition(0, false) end) then fails[#fails + 1] = "SetPosition 0 FAILED" end
    if not pcall(function() m:SetPlayRate(1) end) then fails[#fails + 1] = "SetPlayRate FAILED" end
    if not pcall(function() m:Play(false) end) then fails[#fails + 1] = "Play FAILED" end
    local len, pos = "?", "?"
    pcall(function() len = string.format("%.2f", anim:GetPlayLength()) end)
    pcall(function() pos = string.format("%.2f", m:GetPosition()) end)
    RC = { D = D, o = e.o, a = e.a, name = e.name, mesh = m, anim = anim, state = "deploy", t = 0, n = 0, shots = 0, impacts = 0,
           dealt = 0, z0 = z0, hull = TANI.liveHull() }
    rcLog(string.format("%s: deploying (AS_SV_Tani_RAILCANNON_Deploy %s s on TurretMesh, from %s s; SOC_Gun_01 z %s cm in the mesh%s); "
        .. "the shield off and the first charge at +%.1f s", why, len, pos, cm(z0), #fails > 0 and ("; " .. table.concat(fails, ", ")) or "",
        num(c.deploy_s, 3.4)))
    hudCallout("TEST: TANACORN RAILCANNON", "DEPLOYING")
    return true, "deploying"
end
testKey("H", "sv_tanicorn_rail.lua's railcannon test", function() TANI.rcStart("Ctrl+H") end)

local function forget()                                   -- (the level's objects: forgotten, none of them touched)
    RC, SH, RG, FX, TRAIL, PEND, A = nil, nil, {}, {}, {}, {}, {}
end
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["tanicorn rail"] = forget end
TEST_TICKS[#TEST_TICKS + 1] = { name = "tanicorn rail", fn = function(now)
    local dt = math.max(0, math.min(1, now - (X.last or now)))
    X.last = now
    if not D or (levelTorn and levelTorn()) then
        if RC or SH or next(RG) ~= nil or #FX > 0 then forget() end
        return
    end
    local keep = {}                                       -- every effect stopped after its life (AC8's IGC ones never stop)
    for _, e in ipairs(FX) do
        if not e.off and e.at and now >= e.at then fxStop(e) end
        if not e.off then keep[#keep + 1] = e end
    end
    FX = keep
    if #TRAIL > 0 then                                    -- (the trail's spots as the round passes them)
        local left = {}
        for _, s in ipairs(TRAIL) do
            if now >= s.at then fxAt(s.path, s.where, s.rot, 1, s.life) else left[#left + 1] = s end
        end
        TRAIL = left
    end
    for ev in pairs(PEND) do                              -- (hard rule 64: held through the STORE, fired once it's shut)
        if not busy() then
            PEND[ev] = nil
            local ok, why = fire(ev)
            rcLog(string.format("%s fired after the STORE%s", ev, ok and "" or (": NOT (" .. tostring(why) .. ")")))
        end
    end
    shieldTick()
    gunsTick(now, dt)
    if RC then rcTick(now, dt) end
end }
end
-- DEV ONLY END
