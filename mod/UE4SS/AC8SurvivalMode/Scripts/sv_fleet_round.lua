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
local function say(key)
    local list = (rc().radio or {})[key]
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

-- the kind (sv_rounds.lua SPC; THE ESCORT's and the Spaceport's hooks)
function IFROUND.spawn(now)
    if not ready(D and D.round) then rlog("round " .. tostring(D and D.round) .. ": not ready: a normal round"); return false end
    local no = IFLEET.launch("round " .. tostring(D.round))
    if no then rlog("the fleet didn't come (" .. tostring(no) .. "): a normal round"); return false end
    RUN.fleetRound = true
    if SKY then SKY.fightSlow = n(rc().sky_slow, 5) end   -- ((2026-11-17) the dawn x5 slower through its fight: sv_sky.lua)
    R = { F = IFLEET.cur, paid = {}, parts = {}, t0 = now }
    D.special.state, D.special.at = "fleet", now
    rlog(string.format("round %d: the fleet's %d ships coming (the surfacing first); music: %s", D.round, #R.F.ships, musicStart()))
    return true
end
function IFROUND.busy(s)
    if not R then return false end
    if IFLEET.cur ~= R.F then return false end           -- (taken off: Ctrl+N)
    return afloatN(R.F) > 0
end
function IFROUND.over(now, s)
    if not R then return end
    local F = R.F
    local won = IFLEET.cur == F and afloatN(F) == 0
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
