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
IFCOOP = {}                                               -- ((0.74.160) round 30 in co-op: the host's "if" messages, here
if SPC then                                               -- ((0.74.160) a joiner's copies of round 30 taken off at its end
    SPC.UNITS_OF = SPC.UNITS_OF or {}                     -- (SPC.clientClean): every ship's unit and her live hull's
    SPC.UNITS_OF.fleet = function()                       -- (a joiner's only: the host's own end is the fleet's, her sink's:
        local out = {}                                    -- 0.74.160's list on the host recycled her 7 s into her sinking)
        if not (COOP and COOP.client and COOP.client()) then return out end
        for _, c in ipairs(((CFG.specials or {}).fleet or {}).ships or {}) do if c.key then out[#out + 1] = "SV_Unit_IF" .. c.key end end
        if TANI and TANI.live and TANI.live.unit then out[#out + 1] = TANI.live.unit end
        return out
    end
end
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
    IFCOOP.send("split")
    if not P.G then rlog("phase 2: her breach (" .. why .. "): GEOFON was already gone, no V"); return end
    local okF, err = pcall(GEO.fall, P.G)
    rlog(string.format("phase 2: GEOFON split in two by %s (%s)", why, okF and "its V rearing" or ("its V FAILED: " .. tostring(err))))
    say("fall", p2c().radio)
    CREW.say("split")
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
        function(t) split(P, string.format("her bow's breach (+%.1f s into her rise)", t)) end, hooks,
        { wait = n(p2c().release_s, 2.5) > 0 })                 -- ((0.74.148) held under the sea release_s: her spawn's hitch first)
    P.releaseAt = now + n(p2c().release_s, 2.5)
    r = okR and tonumber(r) or -5
    rlog(string.format("phase 2: the TANACORN under GEOFON (%.0f, %.0f) facing %.0f (across its keel, her bow's breach at its midships): %s",
        x, y, face, r > 0 and "spawned, rising" or ("NOT spawned (" .. tostring(okR and no or r) .. "): GEOFON splits now")))
    if r <= 0 then split(P, "its own break (no TANACORN)"); P.state = "skipped"; return end
    P.state, P.riseAt = "rise", now
    IFCOOP.send("rise", string.format("%.0f", x), string.format("%.0f", y), string.format("%.1f", face))
end
local function hideHalves(P, now)
    if P.G and P.split and not P.hidden and now - P.splitAt >= n(fallC().hide_s, 50) then
        P.hidden = true
        IFCOOP.send("hide")
        local okH, k = pcall(GEO.fallHide, P.G)
        rlog(string.format("phase 2: GEOFON's halves hidden %.0f s after the split (%s of 2)", now - P.splitAt, okH and tostring(k) or "error"))
    end
end
-- ((0.74.156) WP11 M4, her phases (the user, 2026-11-17: "Her phases and core"): 1, her guns fight, the railcannon stowed
-- and shielded; 2, at phase2_share of her parts down, the railcannon rises and charges at the airfield (TANI.rcStart); 3, the
-- railcannon down (TANI.coreOpen, sv_tanicorn_rail.lua's hook) or core_share of her parts down: her core opens: her hull's
-- armour off, its box and lock-on on, its health core_missiles of your standard missiles (+ core_per_player each other
-- player; only ever lowered), held at core_floor of it (SetMinHealth: never the game's own death); there: beaten, her sinking
local function hullHp(o)
    local ok, h = pcall(function() return o.HealthInternal end)
    return (ok and type(h) == "number") and h or nil
end
local function openCore(P, why)
    local c, o = p2c(), TANI and TANI.liveHull and TANI.liveHull() or nil
    P.phase, P.coreAt = 3, os.clock()
    if not o then rlog("phase 2: her core NOT opened (" .. tostring(why) .. "): her hull isn't up"); return end
    pcall(function() o:SetIsInvincible(false) end)
    for f, v in pairs({ bIsInvincible = false, bCanBeDamaged = true, bShowHUDBox = true, bIsNotLockonTarget = false,
                        bIsNotFCSTargets = false, TargetMarkType = 1 }) do
        pcall(function() o[f] = v end)
    end
    local d
    if SPC and type(SPC.playerMissileDamage) == "function" then local ok, v = pcall(SPC.playerMissileDamage); if ok then d = tonumber(v) end end
    local players = 1
    if COOP and type(COOP.players) == "function" then local ok, l = pcall(COOP.players); if ok and type(l) == "table" then players = math.max(1, #l) end end
    local h0 = hullHp(o)
    local miss = n(c.core_missiles, 30) * (1 + n(c.core_per_player, 0.5) * (players - 1))
    local sized = "its row's health (your missile's damage unread)"
    if d and d > 0 and h0 then
        local want = math.floor(miss * d * 10 + 0.5)
        if want < h0 and pcall(function() o.HealthInternal = want end) then sized = string.format("%.0f of your missiles (%d)", miss, want) end
    end
    P.coreMax = hullHp(o) or h0 or 1
    local floor = P.coreMax * n(c.core_floor, 0.02)
    P.coreFloor = floor
    local okM = pcall(function() o:SetMinHealth(floor / 10) end)
    IFCOOP.send("core")
    hudCallout(tx2().core or "HER CORE IS EXPOSED", tx2().core_sub or "SINK THE TANACORN")
    say("core", c.radio)
    CREW.say("core")
    rlog(string.format("phase 2: her core open (%s): her hull's armour off, its box and lock-on on; health %s, held at %.0f (SetMinHealth %s)",
        tostring(why), sized, floor, okM and "set" or "FAILED"))
end
if TANI then                                              -- (sv_tanicorn_rail.lua calls it as her railcannon goes down)
    TANI.coreOpen = function(why)
        if R and R.p2 and R.p2.state == "fight" and (R.p2.phase or 1) < 3 then R.p2.coreReq = tostring(why or "the railcannon down") end
    end
end
local function p2Fight(P, now)
    local c = p2c()
    hideHalves(P, now)
    P.phase = P.phase or 1
    if P.coreReq and P.phase < 3 then local w = P.coreReq; P.coreReq = nil; openCore(P, w) end
    if now < (P.countAt or 0) then return end
    P.countAt = now + 1
    local up, of = nil, nil
    if TANI and TANI.livePartsUp then up, of = TANI.livePartsUp() end
    if up == nil then
        P.state = "skipped"
        rlog("phase 2: her live hull is gone (not beaten): phase 2 over without her reward")
        return
    end
    P.up, P.of = up, of
    local down = of - up
    if down > P.paid then
        local v = pay(n(c.part_pay, 500) * (down - P.paid), "the TANACORN's guns")
        rlog(string.format("phase 2: %d of her guns shot down (%d of %d down): %s zollars", down - P.paid, down, of, tostring(v)))
        P.paid = down
    end
    if not P.halfSaid and down * 2 >= of then P.halfSaid = true; say("half", c.radio); CREW.say("half") end
    if P.phase == 1 and of > 0 and down / of >= n(c.phase2_share, 0.6) then
        P.phase = 2
        local okC, err = false, "no TANI.rcStart"
        if TANI and TANI.rcStart then                  -- (its answer read: false and why when it refuses)
            local okP, r1, r2 = pcall(TANI.rcStart, "round 30: her phase 2")
            okC, err = okP and r1 ~= false, okP and r2 or r1
        end
        hudCallout(tx2().phase2 or "HER RAILCANNON IS RISING", tx2().phase2_sub or "SHOOT IT DOWN BEFORE IT FIRES")
        say("phase2", c.radio)
        CREW.say("phase2")
        rlog(string.format("phase 2: her phase 2 at %d of %d guns down: her railcannon's cycle on the airfield %s", down, of,
            okC and "started" or ("NOT started: " .. tostring(err))))
    end
    if P.phase < 3 and of > 0 and (down / of >= n(c.core_share, 0.95) or up == 0) then
        openCore(P, string.format("%d of %d of her guns down", down, of))
    end
    if P.phase == 3 then
        local o = TANI.liveHull and TANI.liveHull() or nil
        local h = o and hullHp(o) or nil
        P.corePct = (h and P.coreMax and P.coreMax > 0) and math.max(0, math.floor(100 * (h - (P.coreFloor or 0)) / math.max(1, P.coreMax - (P.coreFloor or 0)) + 0.5)) or P.corePct
        if not o or (h and h <= (P.coreFloor or 0) + 1) then
            local okD, how = false, nil                 -- ((0.74.137) her death: explosions, then she goes under bow first)
            if o and TANI.liveSink then okD, how = TANI.liveSink("round 30: her core destroyed", c.sink) end
            if okD then IFCOOP.send("sink") end           -- ((0.74.165) her sinking on every game
            if not okD and o and TANI.liveDown then okD, how = TANI.liveDown("round 30: her core destroyed") end
            local v = pay(n(c.reward_tani, 60000), "the TANACORN sunk")
            hudCallout(tx2().beaten or "THE TANACORN IS SILENCED", string.format(tx2().beaten_sub or "+%s ZOLLARS", zl(v)))
            say("beaten", c.radio)
            CREW.say("beaten")
            P.state = "beaten"
            rlog(string.format("phase 2: the TANACORN beaten at +%.0f s (her core destroyed, %d of %d guns down): %s zollars; her hull %s",
                now - P.fightAt, down, of, tostring(v), okD and (how and ("down (" .. tostring(how) .. ")") or "sinking") or "NOT finished off"))
        end
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
        IFCOOP.send("watch", sh.unit)
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
        if (G.stage or 0) > (P.stageSaid or 0) then             -- ((0.74.146) each stage of GEOFON's: its radio (stage1 / stage2)
            P.stageSaid = G.stage
            say("stage" .. G.stage)
            CREW.say("stage" .. G.stage)
        end
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
            IFCOOP.send("break")
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
        if P.releaseAt and now >= P.releaseAt then
            P.releaseAt = nil
            local okL = TANI.riseRelease and pcall(TANI.riseRelease, "round 30: her spawn's hitch passed")
            IFCOOP.send("release")
            rlog("phase 2: her rise released" .. (okL and "" or " (NOT: no TANI.riseRelease)"))
            CREW.say("release")
        end
        hideHalves(P, now)
        local st = TANI.riseState and TANI.riseState() or nil
        if st == nil or now - P.riseAt >= n(c.rise_max_s, 40) then
            P.state, P.fightAt, P.phase = "fight", now, 1             -- ((0.74.156) her railcannon at her phase 2)
            hudCallout(tx2().rises or "THE TANACORN RISES", tx2().rises_sub or "")
            say("rises", c.radio)
            CREW.say("fight")
            rlog(string.format("phase 2: the TANACORN up and fighting at +%.0f s from the break (her rise %s)", now - P.t0,
                st == nil and "over" or ("cut at " .. n(c.rise_max_s, 40) .. " s: " .. tostring(st))))
        end
        return
    end
    if P.state == "fight" then p2Fight(P, now) end
end
local function p2Busy() return R ~= nil and R.p2 ~= nil and (R.p2.state == "fall" or R.p2.state == "rise" or R.p2.state == "fight") end

---------------------------------------------------------------------------------------------------- the shelling (WP13)
-- ((0.74.137) the user, 2026-11-10: near Comona, the fleet shells the airfield; "Keep working until I say stop") every
-- ship afloat of shell.kinds within shell.shell_km of the runway: a salvo every every_s (staggered by its place in the
-- fleet): its muzzle flash, then flight_s on `damage` off the airfield (AF.bomb, as the festival's missiles and the
-- railcannon), AC8's explosions at `rounds` random spots on the runway (spread_m along it, across_m across), the impact's
-- sound on your camera and a shake within shake_km; the callout once a round (text.shelling) and its radio; none while
-- the airfield is down, paused or in the STORE. The TANACORN's railcannon is hers (sv_tanicorn_rail.lua). Log:
-- `fleet round: shelling: ...`
local function shc() return (CFG.specials and CFG.specials.fleet or {}).shell or {} end
local function runway()
    local f = ((CFG.specials and CFG.specials.fleet or {}).formation or {}).runway_cm or { 1610476, -436143 }
    return { X = n(f[1], 1610476), Y = n(f[2], -436143), Z = 0 }
end
local function shipAt(sh)
    if not (sh.hull and alive(sh.hull)) then return nil end
    local ok, v = pcall(function() local w = sh.hull.obj:K2_GetActorLocation(); return { X = w.X, Y = w.Y, Z = w.Z } end)
    return ok and v or nil
end
local function fxHere(path, at, sc)                       -- one of AC8's effects at a place, its own life (auto-destroyed)
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    local sys = type(path) == "string" and loadObject(path .. "." .. (path:match("[^/]+$") or "")) or nil
    if not (sys and valid(lib) and liveObj(survivalPC)) then return false end
    return pcall(function()
        lib:SpawnSystemAtLocation(survivalPC, sys, at, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = sc, Y = sc, Z = sc }, true, true, 0, false)
    end)
end
local SHAKE = {}
local function shellShake(path, scale)
    if type(path) ~= "string" or not liveObj(survivalPC) then return false end
    if not (SHAKE[path] and liveObj(SHAKE[path])) then SHAKE[path] = loadObject(path .. "." .. path:match("[^/]+$") .. "_C") end
    local cls = SHAKE[path]
    if not cls then return false end
    return pcall(function() survivalPC:ClientStartCameraShake(cls, scale or 1, 0, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
end
local function shellLand(Sx, s)                          -- a salvo's rounds on the runway: the damage, the effects
    local c = shc()
    local rw = runway()
    local yaw = math.rad(n(c.runway_yaw, -23))
    local ok = 0
    for i = 1, math.max(1, math.floor(n(c.rounds, 3))) do
        local a, b = (math.random() * 2 - 1) * n(c.spread_m, 600) * 100, (math.random() * 2 - 1) * n(c.across_m, 60) * 100
        local at = { X = rw.X + math.cos(yaw) * a - math.sin(yaw) * b, Y = rw.Y + math.sin(yaw) * a + math.cos(yaw) * b, Z = n(c.ground_cm, 500) }
        for _, e in ipairs(c.impact or {}) do if fxHere(e[1], at, n(e[2], 1)) then ok = ok + 1 end end
    end
    local dmg, said = math.floor(n(c.damage, 6)), ""
    if not AF or AF.down or not AF.bomb then said = "the airfield is down: no damage"
    else
        AF.bomb = AF.bomb + dmg
        said = string.format("-%d airfield (health before %s)", dmg, tostring(AF.hp))
    end
    local you, near = playerLocation(), false
    if you then near = math.sqrt((you.X - rw.X) ^ 2 + (you.Y - rw.Y) ^ 2) <= n(c.shake_km, 6) * 100000 end
    local shook = near and shellShake(c.shake, n(c.shake_scale, 0.6))
    if near and c.sound and IFSKY and IFSKY.post then pcall(IFSKY.post, c.sound) end
    Sx.landed, Sx.dealt = Sx.landed + 1, Sx.dealt + (said:find("^%-") and dmg or 0)
    if Sx.landed <= 3 or Sx.landed % 10 == 0 then
        rlog(string.format("shelling: %s's salvo landed: %s; %d effects%s", s.name, said, ok, shook and ", a shake" or ""))
    end
end
local function shellTick(now)
    local c = shc()
    if c.enabled == false or not R then return end
    local Sx = R.shell
    if not Sx then Sx = { ships = {}, inAir = {}, salvos = 0, landed = 0, dealt = 0 }; R.shell = Sx end
    for i = #Sx.inAir, 1, -1 do                          -- (rounds in flight land on their time, the airfield up or not)
        local s = Sx.inAir[i]
        if now >= s.at then table.remove(Sx.inAir, i); shellLand(Sx, s) end
    end
    if (type(gamePaused) == "function" and gamePaused(survivalPC) == true) or (IFLEET.inStore and IFLEET.inStore()) then return end   -- ((2026-11-18) OFF is sv_fleet.lua's local: was nil here
    if AF and AF.down then return end
    if IFSURF and IFSURF.state and IFSURF.state() then return end
    local rw = runway()
    local kinds = c.kinds or {}
    for i, sh in ipairs(R.F.ships) do
        if not sh.sunk and kinds[sh.kind] then
            local p = shipAt(sh)
            if p then
                local km = math.sqrt((p.X - rw.X) ^ 2 + (p.Y - rw.Y) ^ 2) / 100000
                local e = Sx.ships[sh.key]
                if km <= n(c.shell_km, 20) then
                    if not e then
                        e = { next = now + (i % 6) * n(c.every_s, 20) / 6 }
                        Sx.ships[sh.key] = e
                        rlog(string.format("shelling: %s (%s) at the gun line, %.1f km from the runway: shelling every %g s", IFLEET.label(sh), sh.kind, km, n(c.every_s, 20)))
                        if not Sx.said then
                            Sx.said = true
                            hudCallout((c.text or {}).shelling or "THE FLEET IS SHELLING THE AIRFIELD", (c.text or {}).shelling_sub or "SINK THE SHIPS IN RANGE")
                            say("shelling", c.radio)
                            CREW.say("shelling")
                        end
                    end
                    if now >= e.next then
                        e.next = now + n(c.every_s, 20)
                        Sx.salvos = Sx.salvos + 1
                        if c.muzzle then fxHere(c.muzzle[1], { X = p.X, Y = p.Y, Z = p.Z + 2500 }, n(c.muzzle[2], 3)) end
                        Sx.inAir[#Sx.inAir + 1] = { at = now + n(c.flight_s, 6), name = IFLEET.label(sh) }
                    end
                elseif e then
                    Sx.ships[sh.key] = nil
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------- the scars (WP8)
-- ((0.74.140) the user, 2026-11-10: every fleet ship scarred from its spawn, the TANACORN never; "Keep working until I say
-- stop") every ship of the fleet up (IFLEET.cur: the round's and Ctrl+N's), its hull and its parts: each mesh component's
-- material slots on dimmed copies of their own _DAM instances (sv_fleet.lua GEO.scarComp: route D, AB.L..IN's dead look),
-- per_tick components a tick, each checked still the object captured (hard rule 59); a slot with no _DAM of its own left
-- as it is. The fleet's list has no TANACORN in it. Log: `fleet: scars: ...`
local SC = { F = nil, q = {}, done = {}, n = 0, slots = 0, of = 0 }
local function scC() return (CFG.specials and CFG.specials.fleet or {}).scars or {} end
local SCAR_CLASSES = { "/Script/Engine.StaticMeshComponent", "/Script/Engine.SkeletalMeshComponent", "/Script/Engine.PoseableMeshComponent" }
local function scarQueue(sh)
    local objs = { sh.hull }
    for _, e in ipairs(sh.parts or {}) do objs[#objs + 1] = e end
    local k = 0
    for _, e in ipairs(objs) do
        if e and alive(e) and SPC and SPC.V and SPC.V.comps then
            for _, cls in ipairs(SCAR_CLASSES) do
                local ok, list = pcall(SPC.V.comps, e.obj, cls)
                for _, c in ipairs(ok and type(list) == "table" and list or {}) do
                    SC.q[#SC.q + 1] = { c = c, e = e, ship = IFLEET.label(sh) }
                    k = k + 1
                end
            end
        end
    end
    return k
end
local function scarsTick()
    local c = scC()
    if c.enabled == false or not (IFLEET and GEO and GEO.scarComp) then return end
    local F = IFLEET.cur
    if F ~= SC.F then SC.F, SC.q, SC.done, SC.n, SC.slots, SC.of, SC.said, SC.lines = F, {}, {}, 0, 0, 0, nil, 0 end
    if not F then return end
    if IFSURF and IFSURF.state and IFSURF.state() then return end   -- (the real fleet only once the surfacing's over)
    local tq = os.clock()
    for _, sh in ipairs(F.ships) do                       -- ((0.74.151) one ship's components walked a tick: run 20261117_203153's
        if sh.hull and not SC.done[sh.key] and not sh.sunk then   -- worst tick 146 ms had every ship walked at once)
            SC.done[sh.key] = true
            local k = scarQueue(sh)
            if k > 0 then SC.n = SC.n + 1 end
            break
        end
    end
    if PERF and PERF.add then PERF.add("fleet round/scars walk", tq) end
    local ts = os.clock()
    local per = math.max(1, math.floor(n(c.per_tick, 1)))
    for _ = 1, per do
        local j = table.remove(SC.q, 1)
        if not j then break end
        if alive(j.e) and liveObj(j.c) then
            local okS, set, of, said = pcall(GEO.scarComp, j.c, n(c.embers, 0.05))
            if okS and type(set) == "number" then SC.slots, SC.of = SC.slots + set, SC.of + (tonumber(of) or 0) end
            SC.lines = SC.lines or 0
            if okS and SC.lines < 4 and (tonumber(of) or 0) > 0 then   -- (the first few components' slots, what each got)
                SC.lines = SC.lines + 1
                log("fleet: scars: " .. tostring(j.ship) .. ": " .. tostring(said):sub(1, 400))
            end
        end
    end
    if PERF and PERF.add then PERF.add("fleet round/scars set", ts) end
    if #SC.q == 0 and SC.n > 0 and SC.said ~= SC.n then
        SC.said = SC.n
        log(string.format("fleet: scars: %d ships, %d of %d material slots on their dimmed _DAM (embers x%g; the rest have none of their own)",
            SC.n, SC.slots, SC.of, n(c.embers, 0.05)))
    end
end

---------------------------------------------------------------------------------------------------- GEOFON's deck (WP5)
-- ((0.74.144) the design's WP5: "its deck launches stay the Spaceport's (a pool flight with a pose off its bow)"; "Keep
-- working until I say stop") while GEOFON is afloat in round 30 (not broken, not in the surfacing), a free pool flight of
-- deck.size (not up, not one of the round's own, not a probe or a role flight sitting out) spawned off its bow (ahead_m
-- along its heading, alt_m up): first_s after the fleet's up, then every every_s, at most max_up up and max_flights a round;
-- not while you're down at the airfield with nobody flying. Log: `fleet round: deck: ...`
local function deckC() return rc().deck or {} end
local function deckFlight(size)
    local opts = {}
    for _, u in ipairs(CFG.pool or {}) do
        if flightSize(u) == size and not (D.up and D.up[u]) and not PROBE_OF[u] and poolIndex(u) ~= nil
            and not ROLE.sitsOut(u) and not (D.taken and D.taken[u]) and ALIVE.ask(u, D.now) <= 0 then
            opts[#opts + 1] = u
        end
    end
    return #opts > 0 and opts[math.random(#opts)] or nil
end
local function deckTick(now)
    local dk = deckC()
    if dk.enabled == false or not R or not D then return end
    local g = R.F.ships[1]
    if not (g and g.hull and alive(g.hull)) or g.sunk then return end
    if IFSURF and IFSURF.state and IFSURF.state() then return end
    local K = R.deck
    if not K then
        K = { left = math.floor(n(dk.max_flights, 6)), next = now + n(dk.first_s, 30), up = {}, n = 0 }
        R.deck = K
        rlog(string.format("deck: GEOFON launches up to %d flights this round, the first in %g s", K.left, n(dk.first_s, 30)))
    end
    if K.left <= 0 or now < K.next then return end
    local up = 0
    for u in pairs(K.up) do if ALIVE.ask(u, now) > 0 then up = up + 1 end end
    if up >= n(dk.max_up, 3) then K.next = now + 2; return end
    if playerOnAirfield() and othersFlying() == 0 then K.next = now + 1; return end
    local u = deckFlight(math.floor(n(dk.size, 2)))
    if not u then
        if not K.noneSaid then K.noneSaid = true; rlog("deck: no free fighter pair to launch") end
        K.next = now + 5
        return
    end
    local at, yaw
    pcall(function() local v = g.hull.obj:K2_GetActorLocation(); at = { X = v.X, Y = v.Y, Z = v.Z } end)
    pcall(function() local f = g.hull.obj:GetActorForwardVector(); yaw = math.atan(f.Y, f.X) end)
    if not (at and yaw) then K.next = now + 5; return end
    local ahead = n(dk.ahead_m, 600) * 100
    local pose = { x = at.X + math.cos(yaw) * ahead, y = at.Y + math.sin(yaw) * ahead, z = math.max(at.Z, 0) + n(dk.alt_m, 1100) * 100,
                   yaw = math.deg(yaw) % 360, why = "GEOFON's deck" }
    local r = spawnFlight(u, nil, pose)
    ALIVE.spawned(u, r)
    if r > 0 then
        K.up[u], K.n, K.left, K.next = true, K.n + 1, K.left - 1, now + n(dk.every_s, 30)
        for i = #(D.spare or {}), 1, -1 do if D.spare[i] == u then table.remove(D.spare, i) end end
        rlog(string.format("deck: launch %d off GEOFON's bow: %s, %d aircraft at %.0f m, %d left this round", K.n, u, r, pose.z / 100, K.left))
    else
        K.next = now + 5
        rlog(string.format("deck: %s didn't launch (%s)", u, (SV_ERR and SV_ERR[r]) or tostring(r)))
    end
end

---------------------------------------------------------------------------------------------------- the crew's voices
-- ((0.74.153) the user, 2026-11-17: AC7's Alicorn crew lines "distorted and horrific" (AGENTS.md's AC7 voice exception: the
-- TANACORN only, her dev install only, each heard by her first), "use style A,B,C", "I want them to play throughout the
-- entire mission", none of Torres's replies nor the duty officer's) CREW.say(moment): a moment's lines (crew.moments) in
-- order; between, from the fleet's sighting to the round's end, one of crew.ambient every crew.every_s; each line once a
-- round where it can be, a random style of crew.styles a play, never the last one's; never over a line still playing
-- (its time from its words: crew.s_per_word, crew.pad_s); its subtitle under crew.speakers' name. The files: build_all.sh
-- stages them (TANI=1) as Sounds/tanacorn/<style>_<voice ID>.wav; none there: nothing plays, said once. Log: `fleet round:
-- crew: ...`
CREW = {}
if CFG.specials and CFG.specials.fleet and CFG.specials.fleet.round and not CFG.specials.fleet.round.crew then
    -- ((0.74.154) the user: "The Voices need to be turned up a bit and the choose option C for all": db 2 -> 14, styles C only;
    -- (0.74.155) "voices could be a little quieter": db 14 -> 10)
    CFG.specials.fleet.round.crew = {
        enabled = true, db = 10, styles = { "C" }, every_s = { 45, 90 }, gap_s = 2, s_per_word = 0.42, pad_s = 1.0,
        speakers = { TORRES = "INTERCEPT: TORRES", CREW = "INTERCEPT: ALICORN CREW" },
        no_subs = { TORRES = true, CREW = true },         -- ((0.74.159) the user: "Remove the subtitles for torres", "If theres any subtitles for the crew, remove them too": heard, not shown)
        moments = { sighted = { "v6157_6001_alt1" }, stage1 = { "v6001_6032" }, stage2 = { "v6001_6030_alt1" },
                    split = { "v6349_6001", "v6350_6001", "v6351_6001" }, release = { "v6001_6103" },
                    fight = { "v6001_6051_alt1" }, half = { "v6001_6112_alt1" }, beaten = { "v6001_6002", "v6001_6116_alt1" },
                    phase2 = { "v6001_6087_alt1" }, core = { "v6001_6044" } },
        lines = {
        v6001_6002 = { "TORRES", "It's a requiem." },
        v6001_6007_alt2 = { "TORRES", "Fools..." },
        v6001_6017_alt1 = { "TORRES", "Full speed ahead!" },
        v6001_6030_alt1 = { "TORRES", "So use your imagination, my fellow submariners! A single shell will save ten million lives!" },
        v6001_6032 = { "TORRES", "Picture it!" },
        v6001_6033 = { "TORRES", "Salvation!" },
        v6001_6037_alt1 = { "TORRES", "Two, worth a million lives each..." },
        v6001_6041 = { "TORRES", "Three Strikes... He lacks the drive." },
        v6001_6042 = { "TORRES", "Imagine you're just about to be killed. Why am I going to be killed, you ask." },
        v6001_6043 = { "TORRES", "Because they wanted to steal from you, to torment you, to burn you, to cut you apart." },
        v6001_6044 = { "TORRES", "It was for your sins, your actions, and your vengeance! There has to be a reason!" },
        v6001_6045 = { "TORRES", "Three Strikes has none of that. I do." },
        v6001_6050_alt1 = { "TORRES", "Don't you see?" },
        v6001_6051_alt1 = { "TORRES", "Come if you dare, Three Strikes." },
        v6001_6054_alt1 = { "TORRES", "Let me know when the bodies... I mean the debris stops raining." },
        v6001_6082_alt1 = { "TORRES", "To take the lives of one million people, 5,000 kilometers away, with my very own hands!" },
        v6001_6087_alt1 = { "TORRES", "Commence firing!" },
        v6001_6103 = { "TORRES", "Mfh! Heh heh heh!" },
        v6001_6104 = { "TORRES", "Heh heh heh... heh heh heh..." },
        v6001_6112_alt1 = { "TORRES", "Don't you see? One million! One million lives!" },
        v6001_6113_alt4 = { "TORRES", "Ha ha ha..." },
        v6001_6116_alt1 = { "TORRES", "*sigh*..." },
        v6001_6139_alt3 = { "TORRES", "Mfh heh heh heh!" },
        v6154_6003_alt1 = { "CREW", "Target coordinates acquired." },
        v6156_6002_alt1 = { "CREW", "I hereby swear that." },
        v6156_6002_alt2 = { "CREW", "I will be a proud, brave, and vigilant soldier." },
        v6156_6005_alt1 = { "CREW", "Captain--" },
        v6156_6005_alt2 = { "CREW", "Our salvation--" },
        v6157_6001_alt1 = { "CREW", "Salvation is nigh--" },
        v6157_6001_alt2 = { "CREW", "Salvation--" },
        v6159_6002_alt1 = { "CREW", "For salv--" },
        v6272_6002 = { "CREW", "Keep firing!" },
        v6272_6003 = { "CREW", "Fire again!" },
        v6273_6001 = { "CREW", "The next round is ready to fire!" },
        v6273_6003 = { "CREW", "The last shell has been fired!" },
        v6334_6001_alt1 = { "CREW", "Main guns, commence fire!" },
        v6338_6001 = { "CREW", "Ready to fire!" },
        v6339_6002_alt1 = { "CREW", "It'll be a while before we sink!" },
        v6349_6001 = { "CREW", "I hereby swear that I will be a proud, brave, and vigilant soldier." },
        v6350_6001 = { "CREW", "To submit to the orders of my superiors." },
        v6351_6001 = { "CREW", "To uphold the honor of our nation and its military." },
        },
    }
    -- (the shipped settings' copy too, as sv_fleet.lua's own: CFG_DEFAULTS is taken before this piece loads)
    local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
    local d = CFG_DEFAULTS and CFG_DEFAULTS.specials and CFG_DEFAULTS.specials.fleet and CFG_DEFAULTS.specials.fleet.round
    if type(d) == "table" and d.crew == nil then d.crew = copy(CFG.specials.fleet.round.crew) end
end
do
local K = { q = {}, busyUntil = 0, nextAt = nil, said = {}, last = nil, lastStyle = nil, missing = false }
local function cc() return rc().crew or {} end
local function crewDur(key)
    local l = (cc().lines or {})[key]
    local words = 0
    for _ in tostring(l and l[2] or ""):gmatch("%S+") do words = words + 1 end
    return math.max(1.5, words * n(cc().s_per_word, 0.42) + n(cc().pad_s, 1.2))
end
local function crewPlay(key, now)
    local c = cc()
    local l = (c.lines or {})[key]
    if not l or not (SND and SND.play) then return false end
    local styles = c.styles or { "A" }
    local st = styles[math.random(#styles)]
    if #styles > 1 then
        local tries = 0
        while st == K.lastStyle and tries < 8 do st = styles[math.random(#styles)]; tries = tries + 1 end
    end
    local file = "tanacorn/" .. st .. "_" .. key .. ".wav"
    local h = SND.play({ file = file, db = n(c.db, 2) })
    if not h then
        if not K.missing then K.missing = true; rlog("crew: " .. file .. " didn't play (TANI=1's Sounds/tanacorn not staged?): the crew silent this round") end
        return false
    end
    K.lastStyle, K.last = st, key
    K.said[key] = true
    if COOP and COOP.host and COOP.host() and COOP.msg then pcall(COOP.msg, nil, "if", "crew", key, st) end   -- (0.74.160)
    K.busyUntil = now + crewDur(key) * (st == "B" and 1.6 or (st == "C" and 1.3 or 1)) + (st == "C" and n(c.c_tail_s, 3.5) or 0)
        + n(c.gap_s, 4)                                   -- ((0.74.154) style C's echoes and tail: the user, "thats perfect")
    if SUB and SUB.say and not (c.no_subs or {})[l[1]] then pcall(SUB.say, (c.speakers or {})[l[1]] or l[1], l[2]) end
    rlog(string.format("crew: %s (%s, style %s)", key, l[1], st))
    return true
end
function CREW.say(moment)
    if cc().enabled == false or not R then return end
    for _, k in ipairs((cc().moments or {})[moment] or {}) do K.q[#K.q + 1] = k end
end
function CREW.tick(now)
    local c = cc()
    if c.enabled == false or not R or K.missing then return end
    if now < K.busyUntil then return end
    local k = table.remove(K.q, 1)
    if k then crewPlay(k, now); return end
    if not R.sightedAt then return end                    -- (ambient from the fleet's sighting on)
    if not K.nextAt then K.nextAt = now + n((c.every_s or {})[1], 45) end
    if now < K.nextAt then return end
    local inMoment = {}
    for _, l in pairs(c.moments or {}) do for _, x in ipairs(l) do inMoment[x] = true end end
    local fresh, any = {}, {}
    for key in pairs(c.lines or {}) do
        if not inMoment[key] and key ~= K.last then
            any[#any + 1] = key
            if not K.said[key] then fresh[#fresh + 1] = key end
        end
    end
    local pool = #fresh > 0 and fresh or any
    if #pool > 0 then crewPlay(pool[math.random(#pool)], now) end
    local e = c.every_s or { 45, 90 }
    K.nextAt = now + n(e[1], 45) + math.random() * math.max(0, n(e[2], 90) - n(e[1], 45))
end
-- ((0.74.160) a joiner: the host's crew line played here too (sound only), a line of crew.lines in one of crew.styles only
function CREW.here(key, st)
    local c = cc()
    if c.enabled == false or not (SND and SND.play) then return false end
    if type(key) ~= "string" or not (c.lines or {})[key] then return false end
    local okS = false
    for _, x in ipairs(c.styles or {}) do if x == st then okS = true end end
    if not okS then st = (c.styles or { "C" })[1] end
    local h = SND.play({ file = "tanacorn/" .. st .. "_" .. key .. ".wav", db = n(c.db, 2) })
    rlog(string.format("crew: %s (the host's, style %s)%s", key, st, h and "" or ": didn't play"))
    return h ~= nil and h ~= false
end
function CREW.reset() K.q, K.busyUntil, K.nextAt, K.said, K.last, K.lastStyle = {}, 0, nil, {}, nil, nil end
end

-- the kind (sv_rounds.lua SPC; THE ESCORT's and the Spaceport's hooks)
-- ((2026-11-18) this round's state for IFCOOP.syncTo, which is outside this block: until now it read R there as a global
-- (always nil), so a rejoiner was never sent GEOFON's or her state (lua_check's "unknown global R", missed under its last line)
function IFROUND.state() return R end
function IFROUND.spawn(now)
    if not ready(D and D.round) then rlog("round " .. tostring(D and D.round) .. ": not ready: a normal round"); return false end
    local no = IFLEET.launch("round " .. tostring(D.round))
    if no then rlog("the fleet didn't come (" .. tostring(no) .. "): a normal round"); return false end
    RUN.fleetRound = true
    if SKY then SKY.fightSlow = n(rc().sky_slow, 1) end   -- ((2026-11-17) the dawn x5 slower through its fight: sv_sky.lua)
    R = { F = IFLEET.cur, paid = {}, parts = {}, t0 = now }
    CREW.reset()                                          -- ((0.74.153) the crew's voices: a new round's
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
    if R.p2 and R.p2.state == "fight" and R.p2.phase == 3 then
        return string.format(tx2().core_row or "TANACORN CORE: %d%%", R.p2.corePct or 100)
    end
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
    local function share(name, t0) if PERF and PERF.add then PERF.add("fleet round/" .. name, t0) end end   -- ((0.74.149) each
    local t0 = os.clock()                                  -- piece's own share of the round's tick on the perf line)
    pcall(scarsTick)                                      -- ((0.74.140) WP8: any fleet up, the round's or Ctrl+N's)
    share("scars", t0)
    if not R then return end
    if IFLEET.cur ~= R.F then return end
    t0 = os.clock(); pcall(turretsTick); pcall(musicTick); share("turrets", t0)
    t0 = os.clock()
    local okP, errP = pcall(p2Tick, now)
    share("phase 2", t0)
    if not okP and not R.p2err then R.p2err = true; rlog("phase 2: error " .. tostring(errP)) end
    t0 = os.clock()
    local okK, errK = pcall(deckTick, now)
    share("deck", t0)
    if not okK and not R.deckErr then R.deckErr = true; rlog("deck: error " .. tostring(errK)) end
    t0 = os.clock()
    local okS, errS = pcall(shellTick, now)
    share("shelling", t0)
    t0 = os.clock(); pcall(CREW.tick, now); share("crew", t0)   -- ((0.74.153) the crew's voices
    if not okS and not R.shellErr then R.shellErr = true; rlog("shelling: error " .. tostring(errS)) end
    if not R.sightedSaid and #R.F.queue == 0 and not (IFSURF and IFSURF.state and IFSURF.state()) then
        R.sightedSaid, R.sightedAt = true, now
        say("sighted")
        CREW.say("sighted")
    end
    -- ((0.74.146) the user: "Add more subtitles from Audrey and Valka ... wondering where the Tanager is") tanager_after_s
    -- after the sighting: AUDREY and VALKA on the missing flagship
    if R.sightedAt and not R.tanagerSaid and now - R.sightedAt >= n(rc().tanager_after_s, 10)
        and (not R.p2 or R.p2.state == "watch") then        -- (only while GEOFON's still whole: before she's seen)
        R.tanagerSaid = true
        rlog(string.format("the Tanager's lines (%d)", say("tanager")))
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
-- ((0.74.160) a joiner: the host's word on round 30 ("if", sv_coop_migration.lua; fields cut and checked there): only in
-- round 30's fleet round here, each kind its own handler
local function jlog(s) log("fleet round: " .. s) end
function IFCOOP.send(what, ...)                          -- (the host's word, to every joiner)
    if COOP and COOP.host and COOP.host() and COOP.msg then pcall(COOP.msg, nil, "if", what, ...) end
end
-- ((0.74.172) to one who links (or links back) during round 30: where its phase 2 is (GEOFON watched, broken, split, its
-- halves hidden; her core open; her sinking), 12 s on, its copies spawned there first (sv_coop.lua's hostSync)
-- ((2026-11-18) A6: a rejoiner's fleet. Its copies spawn at the course's start, the host's may be 10 km on: the host sends
-- GEOFON's metres along its lane ("if|at|<m>", worked out as the word goes), the joiner fires RE_SV_IFPt_<ii> (every ship to
-- its lane's point ii, the one nearest: Mission 10's path teleport by point, survival_events_fleet.py) once its copies are up.
-- The course's shape is survival_events_fleet.py if_course's (the generator checks these numbers against its own)
IFCOOP.COURSE = { start_km = 30, hold_km = 16, turn_km = 2, leg_km = 8, laps = 2, lead_m = 500, speed_kmh = 45, pt_max = 35 }
local COURSE_PTS = nil
local function coursePts()                                -- GEOFON's course (cm) and each point's metres along it
    if COURSE_PTS then return COURSE_PTS end
    local K, fl = IFCOOP.COURSE, (CFG.specials or {}).fleet or {}
    local a = math.rad(tonumber(fl.course_yaw) or 45)
    local rw = fl.runway_cm or { 1610476, -436143 }
    local x, y, h = rw[1] - math.cos(a) * K.start_km * 1e5, rw[2] - math.sin(a) * K.start_km * 1e5, a
    local pts, R_ = { { x, y, 0 } }, K.turn_km * 1e5
    local function add(nx, ny)
        local q = pts[#pts]
        pts[#pts + 1] = { nx, ny, q[3] + math.sqrt((nx - q[1]) ^ 2 + (ny - q[2]) ^ 2) / 100 }
        x, y = nx, ny
    end
    local function straight(d)
        local k_n = math.max(1, math.ceil(d / 2e5 - 1e-9))
        local x0, y0 = x, y
        for k = 1, k_n do add(x0 + math.cos(h) * d * k / k_n, y0 + math.sin(h) * d * k / k_n) end
    end
    local function turn(deg, right)
        local sg = right and 1 or -1
        local cx, cy = x + math.cos(h + sg * math.pi / 2) * R_, y + math.sin(h + sg * math.pi / 2) * R_
        local a0, tot = math.atan(y - cy, x - cx), math.rad(deg)
        local k_n = math.max(1, math.ceil(deg / 20 - 1e-9))
        for k = 1, k_n do local t = a0 + sg * tot * k / k_n; add(cx + math.cos(t) * R_, cy + math.sin(t) * R_) end
        h = h + sg * tot
    end
    local far = K.hold_km + 2 * K.turn_km
    straight((K.start_km - far - K.turn_km) * 1e5)
    turn(90, true)
    straight((K.leg_km / 2 - K.turn_km) * 1e5)
    for _ = 1, K.laps do turn(180, false); straight(K.leg_km * 1e5); turn(180, false); straight(K.leg_km * 1e5) end
    COURSE_PTS = pts
    return pts
end
IFCOOP.coursePts = coursePts
-- the lane's point nearest m metres along (0 its first), at most COURSE.pt_max
function IFCOOP.pointNear(m)
    local pts, best, bestD = coursePts(), 0, math.huge
    for i = 1, math.min(#pts, IFCOOP.COURSE.pt_max + 1) do
        local d = math.abs(pts[i][3] - m)
        if d < bestD then best, bestD = i - 1, d end
    end
    return best
end
-- metres along the course of a point (cm) near it: of its places within 400 m of the course, the nearest (with `guess`
-- metres picking the lap: the course laps, so a place is on it more than once); nil when it's nowhere near
function IFCOOP.alongOf(px, py, guess)
    local pts, best, bestErr = coursePts(), nil, math.huge
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local L2 = dx * dx + dy * dy
        local t = L2 > 0 and math.max(0, math.min(1, ((px - a[1]) * dx + (py - a[2]) * dy) / L2)) or 0
        local qx, qy = a[1] + dx * t, a[2] + dy * t
        local off = math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2) / 100
        if off <= 400 then                                -- (scored: off the course, then a tenth of off the guess: the laps
            local m = a[3] + (b[3] - a[3]) * t             -- are 16 km apart, a turn's segments metres)
            local e = off + 0.1 * math.abs(m - (guess or m))
            if e < bestErr then best, bestErr = m, e end
        end
    end
    return best
end
-- the host's GEOFON: metres along its lane now (its place on the course; its sailing time picks among the laps), or nil
function IFCOOP.alongNow()
    local F = IFLEET and IFLEET.cur
    local sh = F and F.ships and F.ships[1]
    if not (sh and not sh.sunk and sh.hull and liveObj(sh.hull.obj)) then return nil end
    local ok, l = pcall(function() return sh.hull.obj:K2_GetActorLocation() end)
    if not (ok and l) then return nil end
    local K = IFCOOP.COURSE
    local guess = (tonumber(F.t) or 0) * K.speed_kmh / 3.6 - K.lead_m
    return IFCOOP.alongOf(l.X, l.Y, guess) or math.max(0, guess)
end

function IFCOOP.syncTo(to)
    if not (COOP and COOP.msg) then return end
    if IFLEET and IFLEET.cur then                         -- (the fleet's place: worked out as the word goes, below)
        IFCOOP.pending = IFCOOP.pending or {}
        IFCOOP.pending[#IFCOOP.pending + 1] = { to = to, at = os.clock() + 12, words = { { "at" } } }
    end
    local RS = IFROUND and IFROUND.state and IFROUND.state()
    local P = RS and RS.p2
    if not (P and P.sh) then return end
    local words = { { "watch", P.sh.unit } }
    if P.state ~= "watch" then words[#words + 1] = { "break" } end
    if P.split then words[#words + 1] = { "split" } end
    if P.hidden then words[#words + 1] = { "hide" } end
    if (P.phase or 0) >= 3 then words[#words + 1] = { "core" } end
    if P.state == "beaten" then words[#words + 1] = { "sink" } end
    IFCOOP.pending = IFCOOP.pending or {}                -- (sent from the co-op tick: no timers of our own, sv_main.lua's rule)
    IFCOOP.pending[#IFCOOP.pending + 1] = { to = to, at = os.clock() + 12, words = words }
end
-- a joiner's GEOFON and TANACORN, from the host's word: J = { unit, G (GEO's on the copy), split, hidden }
local J = nil
local function jGeo()
    if J.G then return J.G end
    local objs = (COOP and COOP.copiesOf) and COOP.copiesOf(J.unit) or {}
    local sh = IFLEET.shipFrom and IFLEET.shipFrom(J.unit, objs) or nil
    if not sh then return nil, string.format("no copy of %s here (%d objects)", tostring(J.unit), #objs) end
    local G, why = GEO.attach(sh)
    if not G then return nil, why end
    J.G = G
    jlog(string.format("co-op: GEOFON's copy here watched (%s, %d parts)", tostring(J.unit), #sh.parts))
    return G
end
-- a joiner: its copy of the host's flagship (GEOFON, the fleet's first ship) where it is now, nil when there's none here
function IFCOOP.flagAt()
    if not (COOP and COOP.client and COOP.client() and COOP.copiesOf) then return nil end
    local first = (((CFG.specials or {}).fleet or {}).ships or {})[1]
    if not (first and first.key) then return nil end
    local o = (J and J.G and J.G.hull and J.G.hull.obj) or COOP.copiesOf("SV_Unit_IF" .. first.key)[1]
    if not (o and liveObj(o)) then return nil end
    local ok, l = pcall(function() return o:K2_GetActorLocation() end)
    return (ok and l) and { X = l.X, Y = l.Y, Z = l.Z } or nil
end
local function finiteN(v, most) return type(v) == "number" and v == v and v > -most and v < most end
function IFCOOP.onHost(f)
    IFCOOP.last = { what = f[2], at = os.clock() }        -- (the last word read: the co-op guard test's)
    if not D then return false, "not in a run here" end
    local what = f[2]
    if what == "crew" then return CREW.here(f[3], f[4]) end
    if what == "cap" or what == "capgo" or what == "capoff" then   -- ((0.74.164) GEOFON's capture: sv_fleet_capture.lua)
        if not (IFCAP and IFCAP.onHost) then return false, "no capture in this build" end
        return IFCAP.onHost(f)
    end
    if what == "at" then                                  -- ((2026-11-18) A6: the host's GEOFON, metres along its lane
        local m = tonumber(f[3])
        if not finiteN(m, 1e6) or m < 0 then return false, "bad metres" end
        IFCOOP.atWant = { m = m, at = os.clock() }
        jlog(string.format("co-op: the host's fleet %.0f m along its lane: this game's copies follow once they're up", m))
        return true
    end
    if what == "surf" then                                -- (the fleet's surfacing cutscene, the host's seed)
        local seed = tonumber(f[3])
        if not (finiteN(seed, 2147483648) and seed >= 0) then return false, "bad seed" end
        if not (IFSURF and IFSURF.start) then return false, "no surfacing in this build" end
        local okS, r = pcall(IFSURF.start, {}, math.floor(seed))
        jlog("co-op: the fleet's surfacing (the host's, seed " .. math.floor(seed) .. "): " .. ((okS and r) and "playing" or "NOT played"))
        return okS and r
    end
    if what == "watch" then
        J = { unit = f[3] }
        local G, why = jGeo()
        if not G then jlog("co-op: GEOFON's copy not watched yet (" .. tostring(why) .. "): again at its break") end
        return true
    end
    if not J then return false, "no GEOFON watched here" end
    if what == "break" then                               -- (the host's held whole and stopped there)
        local G = jGeo()
        if G then
            local h = G.hull.obj
            pcall(function() h:SetIsInvincible(true) end)
            for k, v in pairs({ bShowHUDBox = false, bIsNotLockonTarget = true, bIsNotFCSTargets = true }) do pcall(function() h[k] = v end) end
        end
        jlog("co-op: GEOFON's break (the host's)" .. (G and "" or ": no copy here"))
        return true
    end
    if what == "split" then
        local G = jGeo()
        J.split = true
        local okF = G ~= nil and pcall(GEO.fall, G)
        jlog("co-op: GEOFON split (the host's): " .. (okF and "its V rearing" or "no V here"))
        return true
    end
    if what == "hide" then
        local okH, k = false, 0
        if J.G then okH, k = pcall(GEO.fallHide, J.G) end
        jlog("co-op: GEOFON's halves hidden (the host's): " .. (okH and tostring(k) or "none here"))
        return true
    end
    if what == "rise" then
        local x, y, face = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
        if not (finiteN(x, 1e9) and finiteN(y, 1e9) and finiteN(face, 720)) then return false, "bad place" end
        local cine = (((CFG.specials and CFG.specials.fleet or {}).round or {}).phase2 or {}).cine
        local hooks = (type(cine) == "table" and cine.enabled ~= false) and { keys = cine.keys, letterbox = cine.letterbox, beats = cine.beats } or nil
        if not (TANI and TANI.joinRise) then return false, "no TANACORN in this build" end
        return TANI.joinRise(x, y, face % 360, "round 30 (the host's)", hooks)
    end
    if what == "sink" then                               -- ((0.74.165) her sinking on the host's copy here
        if not (TANI and TANI.joinSink) then return false, "no TANACORN in this build" end
        local okS, r, why = pcall(TANI.joinSink, "round 30 (the host's)", (((CFG.specials or {}).fleet or {}).round or {}).phase2
            and ((CFG.specials.fleet.round.phase2 or {}).sink) or nil)
        jlog("co-op: her sinking (the host's): " .. ((okS and r) and "on her copy here" or ("NOT: " .. tostring(okS and why or r))))
        return okS and r
    end
    if what == "release" then
        if not (TANI and TANI.riseRelease) then return false, "no TANACORN in this build" end
        return TANI.riseRelease("the host's release")
    end
    if what == "core" then                               -- (her hull boxed and lockable here: your hits go to the host's)
        local o = TANI and TANI.anyHull and TANI.anyHull() or nil
        if o then
            for k, v in pairs({ bShowHUDBox = true, bIsNotLockonTarget = false, bIsNotFCSTargets = false, TargetMarkType = 1 }) do
                pcall(function() o[k] = v end)
            end
        end
        jlog("co-op: her core open (the host's)" .. (o and "" or ": no copy of her here"))
        return true
    end
    return false, "unknown: " .. tostring(what)
end
-- a joiner's GEOFON stepped each tick: its stages' looks (from the copy's own health: the host's "hp"), then its V
TEST_TICKS[#TEST_TICKS + 1] = { name = "fleet co-op", fn = function(now)
    local pend = IFCOOP.pending                           -- (the host's: round 30's state to one who linked, its 12 s up)
    if pend and #pend > 0 and COOP and COOP.msg then
        for i = #pend, 1, -1 do
            local q = pend[i]
            if now >= q.at then
                table.remove(pend, i)
                for _, w in ipairs(q.words) do
                    if w[1] == "at" and not w[2] then          -- (GEOFON's metres now, not 12 s ago)
                        local m = IFCOOP.alongNow()
                        w = m and { "at", string.format("%.0f", m) } or nil
                        jlog(string.format("co-op: slot %s's fleet to %s", tostring(q.to), m and string.format("%.0f m along its lane", m) or "nowhere (GEOFON not up)"))
                    end
                    if w then pcall(COOP.msg, q.to, "if", table.unpack(w)) end
                end
                jlog(string.format("co-op: round 30's state to slot %s: %d words", tostring(q.to), #q.words))
            end
        end
    end
    local A6 = IFCOOP.atWant                              -- (a joiner: the host's fleet place, once its own copies are up)
    if A6 and COOP and COOP.client and COOP.client() and D then
        local first = (((CFG.specials or {}).fleet or {}).ships or {})[1]
        local up = false
        for _, o in ipairs((first and COOP.copiesOf) and COOP.copiesOf("SV_Unit_IF" .. first.key) or {}) do if liveObj(o) then up = true end end
        if up then A6.seen = A6.seen or now end
        if A6.seen and now - A6.seen >= 3 then
            IFCOOP.atWant = nil
            local K = IFCOOP.COURSE
            local m = A6.m + (now - A6.at) * K.speed_kmh / 3.6
            local ii = IFCOOP.pointNear(m)
            local r = type(SV_Event) == "function" and SV_Event(string.format("RE_SV_IFPt_%02d", ii)) or -5
            jlog(string.format("co-op: the fleet here put on its lane's point %d, %.0f m along (the host's %.0f m now; RE_SV_IFPt_%02d: %s)",
                ii, IFCOOP.coursePts()[ii + 1][3], m, ii, tostring(r)))
        elseif now - A6.at > 60 then
            IFCOOP.atWant = nil
            jlog("co-op: the host's fleet place dropped: no copy of GEOFON here in 60 s")
        end
    end
    if not (J and COOP and COOP.client and COOP.client()) then return end
    if not D then J = nil; return end
    local G = J.G
    if not G then return end
    if J.split then pcall(GEO.fallStep, G, now) elseif not G.down then pcall(GEO.stagesStep, G, now) end
end }
if type(LEVEL_DROPS) == "table" then LEVEL_DROPS["fleet co-op"] = function() J, IFCOOP.atWant = nil, nil end end   -- (the level's copies went with it)
-- TEST ONLY END
