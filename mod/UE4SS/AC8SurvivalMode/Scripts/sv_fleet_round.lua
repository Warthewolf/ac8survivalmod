-- sv_fleet_round.lua: INVINCIBLE FLEET's round (round 30, the user's dev install only; WP10 step 1, 2026-11-17: the user,
-- "Phase 1 now", the surfacing "at round start"), sv_fleet.lua's piece after sv_fleet_storm.lua. Part of AC8 Survival
-- Mode's runtime, run by main.lua in MODULES' order: a name another part uses is a global of this mod's Lua state, its own
-- helpers stay local (it shares none of sv_fleet.lua's locals: the other parts' tables are globals read at run time). The
-- whole piece is one test-only block, which tools/strip_test_only.py takes out of every release and test zip, and
-- tools/dev_only.py out of a TESTER zip, only this header left there.
-- CFG.specials.fleet.round (sv_fleet.lua): specialFor answers "fleet" for its round (never drawn, once a run); the kind's
-- hooks as THE ESCORT's and the Spaceport's: the fleet from sv_fleet.lua's launch (the surfacing first), a few of the round's own
-- fighters, each ship paid once as it sinks (sv_fleet.lua's sinking) and each turret as it's shot off, the round held while a ship
-- is afloat (no time limit), its music, its radio, the NEXT row; won: the reward and the airfield fully repaired. Round
-- 29's break: its warning. GEOFON sinks like any ship until WP5 / WP6. Co-op: the host's only (WP12). Log: `fleet round:`.
-- Ctrl+F in a break: round 30 next (test).
-- TEST ONLY BEGIN (INVINCIBLE FLEET's round: test builds only, the user's dev install)
IFROUND = {}
do
local R = nil                                             -- (this round's: { F, paid, parts, t0, mus, ... })
local function n(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function rc() return (CFG.specials and CFG.specials.fleet or {}).round or {} end
local function tx() return rc().text or {} end
local function joiner() return COOP ~= nil and COOP.client ~= nil and COOP.client() == true end
local function rlog(s) log("fleet round: " .. s) end
-- a radio list said in order (each "CODE|text": the code a speaker of CFG.hud.subs.speakers, else the speaker's name)
local function say(key, from)
    local list = (from or rc().radio or {})[key]
    if type(list) ~= "table" or not (SUB and SUB.say) then return 0 end
    local sp = ((CFG.hud or {}).subs or {}).speakers or {}
    local k = 0
    for _, l in ipairs(list) do
        local code, text = tostring(l):match("^([^|]+)|(.+)$")
        if code and pcall(SUB.say, sp[code] or code, text) then k = k + 1 end
    end
    return k
end
local function ready(round)
    local c = rc()
    if c.enabled == false or joiner() or not (IFLEET and IFLEET.rowsOk and IFLEET.launch) then return false end
    return not (RUN and RUN.fleetRound)
end
local function afloatN(F)                                -- (queued, or up and not sunk: a ship that never came isn't)
    local k = #F.queue
    for _, sh in ipairs(F.ships) do if (sh.r or 0) > 0 and not sh.sunk then k = k + 1 end end
    return k
end
local function sunkN(F) local k = 0; for _, sh in ipairs(F.ships) do if sh.sunk then k = k + 1 end end; return k end
-- a ship's or a turret's pay, as the Spaceport's (its kill pay x the special's and the tier's, sv_spaceport.lua tierPay)
local function pay(base, why)
    if base <= 0 or type(addCredits) ~= "function" then return 0 end
    local v = base
    if TIER and TIER.pay and TIER.index and D and D.round then
        v = (TIER.pay(base * (TIER.specialX and TIER.specialX() or 1), TIER.index(D.round))) or base
    end
    addCredits(v, why)                                    -- (never " down (": co-op splits it as a special's, sv_coop)
    return v
end
local function zl(v) return tostring(specialPay and specialPay(v) or v) end

-- the music: Online Mode's AC04 track from the round's start, again at its length on the fleet's clock (held while paused and
-- in the STORE), the music player's own clock held meanwhile (taken back once the STORE lets it go); (the user, 2026-11-17:
-- "hand the music back after round completed") at the round's end the song the music player was on is played again and its
-- clock let go: the music player goes on from it
local function musicStart()
    local m = rc().music or {}
    if m.enabled == false or type(SV_PlayBGM) ~= "function" or type(m.track) ~= "string" then return "off" end
    local before = nil
    if type(SV_BGMNames) == "function" then
        local okN, names = pcall(SV_BGMNames)
        before = okN and type(names) == "string" and names:match("^([^|]*)") or nil
        if before == "" or before == m.track then before = nil end
        -- (nothing playing: no song to give back; run 89's first break had the main menu's track named, id 0 playing)
        if before and type(SV_BGM) == "function" then local okI, id = pcall(SV_BGM, 0); if okI and id == 0 then before = nil end end
    end
    local okP, r = pcall(SV_PlayBGM, m.track)
    if type(SV_MusicHold) == "function" and (D.musicHold or 0) ~= 1 then pcall(SV_MusicHold, 1) end
    R.mus = { at = R.F.t or 0, track = m.track, len = n(m.len_s, 265.832), heldAt = os.clock(), before = before }
    return string.format("%s (SV_PlayBGM %s), the music player's clock held (its song: %s)", m.track, okP and tostring(r) or "error",
        tostring(before or "none"))
end
local function musicTick()
    local M = R and R.mus
    if not M then return end
    if (D.musicHold or 0) ~= 1 and type(SV_MusicHold) == "function" and os.clock() - M.heldAt >= 2 then
        M.heldAt = os.clock(); pcall(SV_MusicHold, 1)
    end
    if (R.F.t or 0) - M.at >= M.len then
        M.at = R.F.t
        local okP, r = pcall(SV_PlayBGM, M.track)
        rlog(string.format("music: %s again at its length (SV_PlayBGM %s)", M.track, okP and tostring(r) or "error"))
    end
end
local function musicStop()
    if not (R and R.mus) then return "" end
    local before = R.mus.before
    R.mus = nil
    local back = "the music player's clock let go"
    if before and type(SV_PlayBGM) == "function" then
        local okP, r = pcall(SV_PlayBGM, before)
        back = string.format("the music player's song back: %s (SV_PlayBGM %s), its clock let go", before, okP and tostring(r) or "error")
    end
    if type(SV_MusicHold) == "function" and (D.musicHold or 0) ~= 1 then pcall(SV_MusicHold, 0) end
    return back
end

-- the airfield fully repaired (the STORE's repair to its top, the reopen's landing back, ALLY.repairAll's allies and
-- defences): what was done
local function airfieldRestore()
    if type(AF) ~= "table" then return "no airfield" end
    local full = n(AF.max, n((CFG.airfield or {}).hp, n(AF.full, 0)))
    local was, opened = AF.hp, ""
    if AF.closed and not (RUN and RUN.captured) then
        local okE, r = false, nil
        if type(SV_Event) == "function" then okE, r = pcall(SV_Event, "RE_SV_AirfieldOpen") end
        opened, AF.closed = string.format(", landing open (RE_SV_AirfieldOpen %s)", okE and tostring(r) or "not fired"), false
    end
    AF.down, AF.closePending, AF.closeHeld = false, false, false
    AF.full, AF.base, AF.bombBase, AF.hp = full, AF.hits, AF.bomb, full
    if RUN then RUN.dirty = true end
    local okA = ALLY and ALLY.repairAll and pcall(ALLY.repairAll)
    return string.format("health %s -> %s%s; allies and defences %s", tostring(was), tostring(full), opened, okA and "repaired" or "NOT repaired")
end

-- each ship paid once as it sinks (sv_fleet.lua's sunkTick); GEOFON's callout, the radio at GEOFON and at half the fleet
IFLEET.onSunk = function(F, sh, why)
    if not (R and R.F == F) or R.paid[sh.key] then return end
    R.paid[sh.key] = true
    local name = IFLEET.label(sh)
    local v = pay(n((rc().pay or {})[sh.kind], 1000), "INVINCIBLE FLEET: " .. name .. " sunk")
    rlog(string.format("%s (%s) sunk (%s): %s zollars; %d of %d afloat", name, tostring(sh.kind), tostring(why), tostring(v), afloatN(F), #F.ships))
    if sh == F.ships[1] then
        hudCallout(string.format(tx().sunk or "%s SUNK", name), "+" .. zl(v) .. " ZOLLARS")
        say("geofon")
    end
    if not R.halfSaid and sunkN(F) * 2 >= #F.ships then R.halfSaid = true; say("half") end
end
-- each turret paid as it's shot off (its ship afloat: a sunk ship's parts aren't shots)
local function turretsTick()
    local each = n(rc().turret, 300)
    for _, sh in ipairs(R.F.ships) do
        if not sh.sunk and #(sh.parts or {}) > 0 then
            local down = #sh.parts - IFLEET.partsUp(sh)
            local was = R.parts[sh.key] or 0
            if down > was then
                R.parts[sh.key] = down
                local v = pay(each * (down - was), "INVINCIBLE FLEET: " .. IFLEET.label(sh) .. "'s turrets")
                rlog(string.format("%s: %d turret(s) shot off (%d of %d down): %s zollars", IFLEET.label(sh), down - was, down, #sh.parts, tostring(v)))
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- phase 2
-- ((0.74.131) the user, 2026-11-17: "GEOFON falls, Tanacorn rises", beaten "All her guns down"; docs/design
-- INVINCIBLE_FLEET_RISE_FORD.md 4.2-4.3) R.p2 = { state, G, sh, ... }:
--   watch  GEOFON's stages (sv_fleet.lua GEO.stagesStep); from fall.watch_hp its health held at fall.break_at
--          (SetMinHealth), at break_at -> fall (paid and said as sunk: IFLEET.onSunk)
--   fall   GEOFON held whole (invincible, its own tick off: it stops); rise_after_s in (0: at the break; no fade: the user,
--          "she spawns as the Geofon is splitting apart") the TANACORN spawned across its keel, her bow's breach point at
--          its midships, put under the sea at once and risen (TANI.roundRise) -> rise; ((0.74.132) the user: "It has to
--          look like the Tanacorn rising has split her in half") the moment her bow breaks the surface GEOFON splits: its
--          V rearing (GEO.fall / fallStep), hidden at hide_s; no breach by split_max_s: split anyway
--   rise   her cinematic; at its end (or rise_max_s) -> fight
--   fight  her parts counted (TANI.livePartsUp), each down paid part_pay, her railcannon's cycle from rail_after_s; none up:
--          finished off (TANI.liveDown), reward_tani -> beaten
--   skipped / beaten   nothing more (the round's end as phase 1's)
-- Log: `fleet round: phase 2: ...`.
local function p2c() return rc().phase2 or {} end
local function tx2() return p2c().text or {} end
local function fallC() return ((CFG.specials and CFG.specials.fleet or {}).geofon or {}).fall or {} end
local function alive(e) return e ~= nil and e.obj ~= nil and liveAddr(e.obj) == e.addr and nameOf(e.obj) == e.name end
local function hpOf(e)
    local ok, h = pcall(function() return e.obj.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end
local function p2skip(why) R.p2 = { state = "skipped" }; rlog("phase 2: " .. why .. ": no TANACORN this round") end
local function stagesSaid()
    local l = {}
    for _, st in ipairs(((CFG.specials.fleet or {}).geofon or {}).stages or {}) do l[#l + 1] = string.format("%.0f %%", n(st.at, 0) * 100) end
    return table.concat(l, " / ")
end
local function split(P, why)                              -- GEOFON torn open: its V rears, its halves part
    if P.split then return end
    P.split, P.splitAt = true, os.clock()
    if not P.G then rlog("phase 2: her breach (" .. why .. "): GEOFON was already gone, no V"); return end
    local okF, err = pcall(GEO.fall, P.G)
    rlog(string.format("phase 2: GEOFON split in two by %s (%s)", why, okF and "its V rearing" or ("its V FAILED: " .. tostring(err))))
    say("fall", p2c().radio)
end
local function p2Rise(P, now)                            -- her spawn across GEOFON's keel, her bow's breach at its midships
    local at, yaw = P.at, P.yaw or 0
    if P.G then local l, y = GEO.where(P.G); if l then at, yaw = l, y end end
    if not (at and TANI and TANI.roundRise) then
        rlog(string.format("phase 2: the TANACORN NOT spawned (%s)", at and "no TANI.roundRise (a build without her)"
            or "GEOFON's place unknown"))
        P.state = "skipped"
        return
    end
    local face = (yaw + 90) % 360
    local bm = n((TANI.rise or {}).breach_m, 115.8) * 100   -- (her bow breaks the surface breach_m forward of her midships)
    local x, y = at.X - math.cos(math.rad(face)) * bm, at.Y - math.sin(math.rad(face)) * bm
    local cine = p2c().cine
    local hooks = (type(cine) == "table" and cine.enabled ~= false) and { keys = cine.keys, letterbox = cine.letterbox, beats = cine.beats } or nil
    local okR, r, no = pcall(TANI.roundRise, x, y, face, "round 30's phase 2",
        function(t) split(P, string.format("her bow's breach (+%.1f s into her rise)", t)) end, hooks)
    r = okR and tonumber(r) or -5
    rlog(string.format("phase 2: the TANACORN under GEOFON (%.0f, %.0f) facing %.0f (across its keel, her bow's breach at its midships): %s",
        x, y, face, r > 0 and "spawned, rising" or ("NOT spawned (" .. tostring(okR and no or r) .. "): GEOFON splits now")))
    if r <= 0 then split(P, "its own break (no TANACORN)"); P.state = "skipped"; return end
    P.state, P.riseAt = "rise", now
end
local function hideHalves(P, now)
    if P.G and P.split and not P.hidden and now - P.splitAt >= n(fallC().hide_s, 50) then
        P.hidden = true
        local okH, k = pcall(GEO.fallHide, P.G)
        rlog(string.format("phase 2: GEOFON's halves hidden %.0f s after the split (%s of 2)", now - P.splitAt, okH and tostring(k) or "error"))
    end
end
local function p2Fight(P, now)
    local c = p2c()
    hideHalves(P, now)
    if P.railAt and now >= P.railAt then
        P.railAt = nil
        local okC, err = false, "no TANI.rcStart"
        if TANI and TANI.rcStart then okC, err = pcall(TANI.rcStart, "round 30's phase 2") end
        rlog("phase 2: her railcannon's cycle on the airfield " .. (okC and "started" or ("NOT started: " .. tostring(err))))
    end
    if now < (P.countAt or 0) then return end
    P.countAt = now + 1
    local up, of = nil, nil
    if TANI and TANI.livePartsUp then up, of = TANI.livePartsUp() end
    if up == nil then
        P.state = "skipped"
        rlog("phase 2: her live hull is gone (not beaten by her guns): phase 2 over without her reward")
        return
    end
    P.up, P.of = up, of
    local down = of - up
    if down > P.paid then
        local v = pay(n(c.part_pay, 500) * (down - P.paid), "the TANACORN's guns")
        rlog(string.format("phase 2: %d of her guns shot down (%d of %d down): %s zollars", down - P.paid, down, of, tostring(v)))
        P.paid = down
    end
    if not P.halfSaid and down * 2 >= of then P.halfSaid = true; say("half", c.radio) end
    if up == 0 then
        local okD, how = false, nil
        if TANI.liveDown then okD, how = TANI.liveDown("round 30: all her guns down") end
        local v = pay(n(c.reward_tani, 60000), "the TANACORN silenced")
        hudCallout(tx2().beaten or "THE TANACORN IS SILENCED", string.format(tx2().beaten_sub or "+%s ZOLLARS", zl(v)))
        say("beaten", c.radio)
        P.state = "beaten"
        rlog(string.format("phase 2: the TANACORN beaten at +%.0f s (all %d guns down): %s zollars; her hull %s", now - P.fightAt, of,
            tostring(v), okD and ("down (" .. tostring(how) .. ")") or "NOT finished off"))
    end
end
local function p2Tick(now)
    local c = p2c()
    if c.enabled == false or not (GEO and GEO.attach) then return end
    local F, P = R.F, R.p2
    local sh = F.ships[1]
    local fl = fallC()
    if not P then                                         -- (GEOFON once it's up and the surfacing's over)
        if not (sh and sh.hull) or (IFSURF and IFSURF.state and IFSURF.state()) then return end
        if sh.sunk then p2skip("GEOFON sank before it was watched"); return end
        local G, why = GEO.attach(sh)
        if not G then
            R.p2tries = (R.p2tries or 0) + 1
            if R.p2tries >= 5 then p2skip("GEOFON's meshes not captured (" .. tostring(why) .. ")") end
            return
        end
        R.p2 = { state = "watch", G = G, sh = sh, paid = 0 }
        rlog(string.format("phase 2: GEOFON watched (its stages at %s; held at %.0f %% from %.0f %%, broken there)", stagesSaid(),
            n(fl.break_at, 0.03) * 100, n(fl.watch_hp, 0.15) * 100))
        return
    end
    if P.state == "watch" then
        local G = P.G
        if not alive(G.hull) or sh.sunk then              -- (gone or at 0 before its hold took: the TANACORN where it was)
            rlog(string.format("phase 2: GEOFON %s before its break: no V, the TANACORN rises where it was", sh.sunk and "sunk" or "gone"))
            if not P.at then p2skip("GEOFON's place never read"); return end
            P.G, P.state, P.t0 = nil, "fall", now
            return
        end
        local l, yaw = GEO.where(G)
        if l then P.at, P.yaw = l, yaw end
        pcall(GEO.stagesStep, G, now)
        local h = hpOf(G.hull)
        local share = (h and G.max and G.max > 0) and h / G.max or 1
        if share <= n(fl.watch_hp, 0.15) and not P.held then
            P.held = true
            local floor = G.max / 10 * n(fl.break_at, 0.03)  -- (HealthInternal is health x 10; SetMinHealth takes health)
            local okM = pcall(function() G.hull.obj:SetMinHealth(floor) end)
            rlog(string.format("phase 2: GEOFON at %.0f %%: its health held at %.0f %% (SetMinHealth %.0f %s)", share * 100,
                n(fl.break_at, 0.03) * 100, floor, okM and "set" or "FAILED"))
        end
        if share <= n(fl.break_at, 0.03) + 0.002 then
            pcall(function() G.hull.obj:SetIsInvincible(true) end)
            pcall(function() G.hull.obj:SetActorTickEnabled(false) end)   -- (off its lane: it stops where it breaks)
            for f, v in pairs({ bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true }) do
                pcall(function() G.hull.obj[f] = v end)
            end
            sh.sunk = true
            if IFLEET.onSunk then pcall(IFLEET.onSunk, F, sh, "broken by the TANACORN") end
            P.state, P.t0 = "fall", now
            rlog(string.format("phase 2: GEOFON at its break (%.0f %%): held whole and stopped; the TANACORN under it %g s on, "
                .. "her bow splits it", share * 100, n(c.rise_after_s, 0)))
        end
        return
    end
    if P.G and P.split and not P.G.over and (P.state == "fall" or P.state == "rise" or P.state == "fight") then pcall(GEO.fallStep, P.G, now) end
    if P.riseAt and not P.split and now - P.riseAt >= n(c.split_max_s, 6) then split(P, "its own break (no breach seen in time)") end
    if P.state == "fall" then
        if not P.G then split(P, "its own sinking") end
        hideHalves(P, now)
        if not P.riseAt and now - P.t0 >= n(c.rise_after_s, 0) then p2Rise(P, now) end
        return
    end
    if P.state == "rise" then
        hideHalves(P, now)
        local st = TANI.riseState and TANI.riseState() or nil
        if st == nil or now - P.riseAt >= n(c.rise_max_s, 40) then
            P.state, P.fightAt, P.railAt = "fight", now, now + n(c.rail_after_s, 20)
            hudCallout(tx2().rises or "THE TANACORN RISES", tx2().rises_sub or "")
            say("rises", c.radio)
            rlog(string.format("phase 2: the TANACORN up and fighting at +%.0f s from the break (her rise %s)", now - P.t0,
                st == nil and "over" or ("cut at " .. n(c.rise_max_s, 40) .. " s: " .. tostring(st))))
        end
        return
    end
    if P.state == "fight" then p2Fight(P, now) end
end
local function p2Busy() return R ~= nil and R.p2 ~= nil and (R.p2.state == "fall" or R.p2.state == "rise" or R.p2.state == "fight") end

-- the kind (sv_rounds.lua SPC; THE ESCORT's and the Spaceport's hooks)
function IFROUND.spawn(now)
    if not ready(D and D.round) then rlog("round " .. tostring(D and D.round) .. ": not ready: a normal round"); return false end
    local no = IFLEET.launch("round " .. tostring(D.round))
    if no then rlog("the fleet didn't come (" .. tostring(no) .. "): a normal round"); return false end
    RUN.fleetRound = true
    if SKY then SKY.fightSlow = n(rc().sky_slow, 1) end   -- ((2026-11-17) the dawn x5 slower through its fight: sv_sky.lua)
    R = { F = IFLEET.cur, paid = {}, parts = {}, t0 = now }
    D.special.state, D.special.at = "fleet", now
    rlog(string.format("round %d: the fleet's %d ships coming (the surfacing first); music: %s", D.round, #R.F.ships, musicStart()))
    return true
end
function IFROUND.busy(s)
    if not R then return false end
    if IFLEET.cur ~= R.F then return false end           -- (taken off: Ctrl+N)
    return afloatN(R.F) > 0 or p2Busy()
end
function IFROUND.over(now, s)
    if not R then return end
    local F = R.F
    local won = IFLEET.cur == F and afloatN(F) == 0 and not p2Busy()
    if p2Busy() and R.p2.state ~= "fall" and TANI and TANI.liveDown then   -- (the round over with her up: she goes with it)
        rlog("phase 2: the round's over with the TANACORN up: " .. tostring(select(2, TANI.liveDown("round 30 over"))))
    end
    rlog("music: " .. musicStop())
    if SKY then SKY.fightSlow = nil end
    if won then
        local reward = n(rc().reward, 50000)
        if type(addCredits) == "function" then addCredits(reward, "INVINCIBLE FLEET destroyed") end
        hudCallout(tx().won or "THE AEGIR FLEET IS DESTROYED", string.format(tx().won_sub or "+%s ZOLLARS", zl(reward)))
        local af = airfieldRestore()
        hudCallout(tx().restored or "AIRFIELD RESTORED", tx().restored_sub or "")
        say("won")
        rlog(string.format("won at +%.0f s: %d ships sunk; %d zollars; the airfield: %s", now - R.t0, sunkN(F), reward, af))
    else
        rlog("over without the win (the fleet " .. (IFLEET.cur == F and (afloatN(F) .. " afloat") or "taken off") .. ")")
    end
    if IFLEET.cur == F then
        IFLEET.cur = nil
        rlog("its wrecks and parts taken off: " .. tostring(IFLEET.takeOff(F, "round " .. tostring(D and D.round) .. " over")))
    end
    if LB and LB.special then pcall(LB.special, "fleet", won, now - R.t0) end
    s.state = "done"
    R = nil
end
function IFROUND.row(s, t)
    if not R then return nil end
    if R.p2 and R.p2.state == "fight" and R.p2.of then
        return string.format(tx2().row or "TANACORN: %d OF %d GUNS", R.p2.up or 0, R.p2.of)
    end
    local g = R.F.ships[1]
    return string.format(tx().row or "FLEET: %d AFLOAT  CARRIER: %s", afloatN(R.F), (g and not g.sunk) and IFLEET.label(g) or "SUNK")
end
if SPC and SPC.kinds then
    SPC.kinds.fleet = {
        sub = function() return tx().sub or "INVINCIBLE FLEET" end,
        ready = function(round) return ready(round) end,
        budget = function(budget) return math.max(0, math.floor(budget * n(rc().fighter_share, 0.25) / 2 + 0.5) * 2) end,
        spawn = function(now) return IFROUND.spawn(now) end,
        busy = function(s) return IFROUND.busy(s) end,
        over = function(now, s) return IFROUND.over(now, s) end,
        row = function(s, t) return IFROUND.row(s, t) end,
    }
end
-- its round: the fleet's (never drawn: sv_spawn.lua's schedule and dice untouched, as THE FESTIVAL's FEST.roundIs)
if type(specialFor) == "function" then
    local rawFor = specialFor
    specialFor = function(round)
        local c = rc()
        if type(round) == "number" and round == n(c.round, 30) and c.enabled ~= false and CFG.specials.enabled ~= false
            and not (SETUP and SETUP.specialsX and SETUP.specialsX() <= 0) and RUN then
            RUN.fleetPick = RUN.fleetPick or {}
            if RUN.fleetPick[round] == nil then
                RUN.fleetPick[round] = ready(round) == true
                rlog(string.format("round %d is the fleet's%s", round, RUN.fleetPick[round] and ""
                    or " NOT (its rows missing, a joiner, or had this run): a normal round's draw"))
            end
            if RUN.fleetPick[round] then return "fleet" end
        end
        return rawFor(round)
    end
end

TEST_TICKS[#TEST_TICKS + 1] = { name = "fleet round", fn = function(now)
    local c = rc()
    -- round 29's break: the warning (its callout, then the round's own SPECIAL ROUND callout at the lead)
    if D and D.state == "wait" and RUN and not RUN.fleetWarned and D.round == n(c.round, 30) - 1 and specialFor(D.round + 1) == "fleet" then
        RUN.fleetWarned = true
        hudCallout(tx().warn or "INVINCIBLE FLEET", tx().warn_sub or "")
        rlog(string.format("round %d's break: the warning (%d radio lines)", D.round, say("warn")))
    end
    if not R then return end
    if IFLEET.cur ~= R.F then return end
    pcall(turretsTick)
    pcall(musicTick)
    local okP, errP = pcall(p2Tick, now)
    if not okP and not R.p2err then R.p2err = true; rlog("phase 2: error " .. tostring(errP)) end
    if not R.sightedSaid and #R.F.queue == 0 and not (IFSURF and IFSURF.state and IFSURF.state()) then
        R.sightedSaid = true
        say("sighted")
    end
end }
-- ((2026-11-17) the user: "can I have a test key") Ctrl+F: the fleet's round next. In a break between rounds the run is set to
-- the break before it (round 29's: its warning), so the next round is round 30, the fleet's; in a round, or had this run:
-- said, nothing changed. Log: `fleet round: Ctrl+F: ...`
testKey("F", "fleet round", function()
    local r = math.floor(n(rc().round, 30))
    if not (D and RUN) then rlog("Ctrl+F: no run"); return end
    if D.state ~= "wait" then
        hudCallout("TEST: FLEET ROUND", "IN A BREAK ONLY")
        rlog(string.format("Ctrl+F: in round %s (%s): only in a break between rounds", tostring(D.round), tostring(D.state)))
        return
    end
    if RUN.fleetRound then hudCallout("TEST: FLEET ROUND", "HAD THIS RUN ALREADY"); rlog("Ctrl+F: had this run already"); return end
    if not ready(r) then hudCallout("TEST: FLEET ROUND", "NOT READY"); rlog("Ctrl+F: not ready (its rows, or a joiner)"); return end
    local was = D.round
    D.round = r - 1
    RUN.fleetWarned, RUN.fleetPick = nil, nil
    hudCallout("TEST: FLEET ROUND", string.format("ROUND %d NEXT", r))
    rlog(string.format("Ctrl+F: the run set from round %s's break to round %d's: round %d, the fleet's, next", tostring(was), r - 1, r))
end)
if type(LEVEL_DROPS) == "table" then                       -- (the level's objects went with it; the music hold: sv_main's)
    LEVEL_DROPS["fleet round"] = function() R = nil; if SKY then SKY.fightSlow = nil end end
end
end
-- TEST ONLY END
