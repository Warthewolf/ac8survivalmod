-- (sv_config.lua is the first of 3 pieces, split by tools/lua_split_part.py: sv_config_specials.lua, sv_config_ini.lua
-- go on from where it ends, run by main.lua right after it, in that order.)
-- sv_config.lua: the difficulty, CFG (every setting) and survival.ini.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- The game's current difficulty (LiveDifficultyManager.CurrentDifficulty: 1 Casual .. 5 Ace).
local DIFFICULTY = { [0] = "None", "Casual", "Easy", "Normal", "Hard", "Ace", "FreeFlight" }
function logDifficulty(when)
    local dm = type(difficultyManager) == "function" and difficultyManager() or nil   -- ((0.73.79) kept: sv_core.lua)
    local ok, d = pcall(function() return dm.CurrentDifficulty end)
    log("difficulty " .. when .. ": " .. ((ok and type(d) == "number") and (DIFFICULTY[d] or tostring(d)) or "unknown"))
end

levelTick = nil              -- tick count when Survival's level was loaded (nil again once the run is over)
pcall(NotifyOnNewObject, "/Script/Engine.World", function(w)
    local n = nameOf(w)
    if n:find("PL_SurvivalMode", 1, true) then levelTick = -1 end      -- picked up by the next tick
    -- (hotfix8) svLevelOn: Survival's level is the one loaded (another main level, the main menu's PL_MainMenu or a
    -- hangar's, ends it). Hotfix7's airfield check ran on the main menu over the old level's planes and crashed the
    -- host (2026-11-01 01:13:14, quitting to the main menu): checks over a level's objects ask it first. (hotfix9: not
    -- the TransitionMap: the seamless travel makes one after Survival's level loads, which turned it off all run.)
    if n:find("PL_SurvivalMode", 1, true) then svLevelOn = true
    elseif n:find("/PL_", 1, true) then svLevelOn = false end
    -- every level and sublevel the game makes, so a crash while loading shows the last one (AC8SurvivalMode_lua.log)
    log("world: " .. (n:match("(/Game/[^%.:]+)") or n))
end)

---------------------------------------------------------------------------------------------------- rounds
-- Survival's own spawner. The game never spawns a world-data unit again while its shot-down flight is still on the
-- phase's unit list (tools/re/SPAWN_SYSTEM.md), so rounds don't use its reinforcement events: dlls\main.dll
-- (runtime 0.6.0) registers these globals when this script starts, and the rounds below call them:
--   SV_Spawn(unit, x, y, z, yaw)   spawns the world-data unit there (cm, degrees); a shot-down flight is recycled first
--   SV_SetAircraft(unit, npc)      sets the aircraft (NPC table row) of every plane in the flight
--   SV_UnitAlive(unit)             planes still alive in the flight's current spawn (-7: not up)
--   SV_LogUnits(why)               writes the game's spawned-unit list to AC8SurvivalMode.log
-- The event package gives each flight its orders when it appears (air-only search, engage the player) and counts
-- SV_Alive / SV_Kills for this log. Must run on the game thread (the one tick below).
CFG = {
    start_round         = 1,                    -- the run's first round (testing: e.g. 16 for the named aces)
    first_round_delay_s = 15,
    intermission_s      = 20,
    spawn_gap_s         = 3,                    -- between two flights of a round
    orders_check_s      = 4,                    -- a fighter flight without its SV_Up_NN flag by then gets its orders again
    -- A round's size is an aircraft budget, filled with squadrons of 2, 4 and 6 (user, 2026-10-22): the world data's
    -- fighter flights are ERA_Unit_NN_Dep_Air0 2 aircraft, _Air1 4, _Air2 6 (tools/survival_events.py flight_size);
    -- a squadron size joins the draw from its from_round.
    aircraft_round1     = 4,
    aircraft_per_round  = 2,                    -- added every round
    -- in one round, difficulty spikes included (60 until 0.70.0, user 2026-10-23; the economy review of 2026-10-25: a
    -- friend's round 23 brought 54 aircraft, 13 flights up at once, and ended the run with 148 missiles unfired). The
    -- cap until CFG.late.aircraft_from_round; from there it grows again by late.aircraft_per_round a round, up to
    -- late.max_aircraft, brought in more waves (behaviour roadmap P8: TIER.roundCap)
    max_aircraft        = 30,
    squadrons           = { { size = 2, from_round = 1 }, { size = 4, from_round = 4 }, { size = 6, from_round = 8 } },
    distance_km         = { 18, 25 },           -- from the airfield, random bearing
    altitude_m          = { 2000, 4500 },
    aircraft            = { "f16c_common", "f18e_common", "f15e_common", "f14d_common", "m21b_common",
                            "m29a_common", "su47_common", "su33_common", "su34_common" },   -- NPC rows in Mission 22's table
                                                                            -- (su47_common: Survival's; the MiG-31 is out,
                                                                            -- user 2026-10-23)
    pool                = {},                   -- Mission 22's 24 "kokatu" flights (tools/survival_events.py POOL)
    -- Ammo cap at spawn (BUILD_PLAN Milestone 2): missiles / each special weapon / flares per preset; the gun is
    -- unlimited. The preset follows the game's difficulty (1 Casual, 2 Easy, 3 Normal, 4 Hard, 5 Ace).
    ammo = {
        enabled          = true,
        gun_unlimited    = true,
        free_restock     = false,               -- the game refills missiles over time unless this is off
        presets          = {
            casual   = { missiles = 72, special = 56, flares = 6 },
            standard = { missiles = 48, special = 28, flares = 4 },
            ace      = { missiles = 30, special = 14, flares = 3 },
        },
        by_difficulty    = { "casual", "standard", "standard", "standard", "ace" },
        -- ((2026-11-07) a player: "I was given 28 machine gun pod bullets total"; the user: "the Special Weapon Machine
        -- Gun Pods should be an exception") specials that fire rounds keep their stock load: a preset's `special` is a
        -- missile count. Names of the game's weapon IDs (ELiveWeaponID: mgp the machine gun pod, pgun the gun pod)
        uncapped_specials = { "mgp", "pgun" },
    },
    -- Behaviour probe (learning-AI step 1, see the "behaviour probe" section): own behaviour script on each round's
    -- first flight, live PilotRank write on every enemy, kill attribution in the log.
    -- runtime: also fly the LuaScript made at run time (route 2), put into the game's Lua by dlls/main.dll 0.8.0.
    -- (Test 20: making an in-memory package for it from UE4SS crashed the game; that is gone.)
    -- units: the probe's own flights (tools/survival_events.py PROBE_UNITS: their world data names the probe rows, as
    -- the game builds behaviour at level load); they fly only as round 1's (package script) and round 2's (run-time
    -- script) first flight, never in the normal rotation.
    ai_watch = true,                            -- log each enemy's AI state and target when they change ("ai:" lines,
                                                -- with CFG.log.verbose)
    -- The log's periodic lines (CFG.log; [log] in survival.ini; the clean up of 2026-10-29, user: quieter logs, the
    -- per-round summaries kept). verbose = false: "round probe: flags" once a level and when a flag that isn't a counter
    -- changes (SV_Beat, the heartbeat, every 10 s; kills; airfield and shuttle hits; flights up); no "ai:" lines
    -- (CFG.ai_watch), no "round probe: AI aircraft alive" (the round's "N aircraft in N flights left" says it), no
    -- "enemies: nearest" every 10 s, no "intensity: round N: you ..." every CFG.intensity.log_s (its round summary
    -- stays); "ammo: now" every 60 s when it changed (else 10 s), "perf:" every 5 minutes (else every minute). true: all
    -- of them as before, for debugging. Each player's own in co-op (sv_coop.lua PERSONAL).
    -- weapons (Scripts/sv_weaponlog.lua; the user, 2026-10-31: "a logger that checks what enemy missiles are being
    -- fired"): each enemy plane's fire control as built (once an airframe and loadout), the first launch of each weapon
    -- by each kind of shooter, looked for every every_s, and a summary every summary_s with what's carried but never fired
    -- (hit_m, turret_s: the missile outcomes' and the fleet watch's, sv_weaponlog.lua) audit: Scripts/sv_audit.lua's
    -- targets / pay audit / sync lines every report_s, the enemies' targets looked at every sample_s, a joiner's kill paid
    -- within suspect_s of a teardown flagged
    log = { verbose = false, weapons = { enabled = true, every_s = 0.5, summary_s = 60, hit_m = 150, turret_s = 5 },
            audit = { enabled = true, sample_s = 5, report_s = 60, suspect_s = 5 } },
    -- behaviour = false (2026-10-22): the barrel-roll probe proved the game builds Survival's scripts; its MiGs flipped
    -- between PursueTarget and ReturnToWorld and never closed in, so rounds 1-2 open with normal fighters again.
    probe = { enabled = true, behaviour = false, runtime = true, kills = true,
              units = { Pkg = "ERA_Unit_08_Dep_Air2", Rt = "ERA_Unit_08_Dep_Air1" } },
    -- The behaviour roadmap's measurements (Scripts/sv_stats.lua; tools/re/BEHAVIOUR_DIRECTOR.md): the seven numbers the
    -- behaviour thesis asks of every test, in the log only (nothing is sent): a "kill-time:" line per enemy down
    -- (kill_lines), a "stats:" line per round and per run, a "death:" line when you're shot down or saved. An enemy
    -- within engage_km is engaged; you're on its tail within tail_km and tail_deg of its six (the aces' reversal test);
    -- a kill within close_km is a close one; a hit with two shooters' missiles within bracket_km is a bracket, one with
    -- no missile near but an enemy within gun_km a gun / close hit; death_window_s: the hits the death line adds up; the
    -- run line's time to kill covers rounds ttk_from_round to ttk_to_round (the thesis' 7-12); pawn_history: the death
    -- line also reads your own aircraft's DamageHistoryMap (each attacker's damage since it took off, what the armour
    -- took too; the read KILL.read makes on enemies, untested on the player's: false leaves it out). Each player's own
    -- in co-op (sv_coop.lua PERSONAL).
    -- tail_watch (P5's gate, "a tailed enemy lasts 8 s+ at Veteran"): 4 times a second the enemies nearest you within
    -- watch_km (at most watch_max a tick) are read afresh, and while you're on one's tail (tail_km, tail_deg) its AI
    -- state too: a "tailed:" line per episode (its provoke values, when it went into Provoke, the states it went
    -- through, how long it lasted: died, or escaped once you'd been off its tail watch_grace_s). The host or solo only.
    stats = { enabled = true, kill_lines = true, engage_km = 5.0, tail_km = 3.0, tail_deg = 70, close_km = 1.2,
              bracket_km = 1.5, gun_km = 1.5, death_window_s = 30, ttk_from_round = 7, ttk_to_round = 12,
              pawn_history = true, tail_watch = true, watch_km = 4.5, watch_max = 4, watch_grace_s = 2.0 },
    -- The learning layer (behaviour roadmap P6, "punish habits": Scripts/sv_stats.lua PROF; tools/re/BEHAVIOUR_DIRECTOR.md
    -- unit 8). Your own kills of fighters (KILL.by "you": a co-op partner's are theirs; a pool flight's fighter, not a
    -- bomber, a Ladon or a special, whose kills would skew the shares) and where you fly (every 2 s of a fight, in the
    -- air) make a profile of five habits, each a share 0-1:
    --   missile   kills with a missile or a special spent in the 6 s before and the gun not
    --   gun       kills with the gun spent, or within CFG.stats close_km (whichever share is bigger)
    --   tail      0.6 x kills from behind (CFG.stats tail_km / tail_deg) + 0.4 x time on an enemy's tail (full at
    --             tail.time_full of your time)
    --   high      time high.over_m above the enemies within high.near_km (none near: above high.alone_m)
    --   airfield  time within airfield.km of the runway, of the time the airfield doesn't need you: not while bombers
    --             or Ladons are up (skip_raids), not in the after_takeoff_s after you were on the ground, and on a
    --             landing the before_landing_s before it taken back (the approach)
    -- A habit over its threshold is countered, the more the further over (its strength: 0 at the threshold, 1 at 1.0),
    -- from each round's start (the host's or solo: the enemies are the host's):
    --   missile   the jammer more often (its chance x (1 + jammer_x x strength), at most jammer_max), PilotRank rank_add
    --             higher from tier rank_from (more flare and strong-evasion picks), and the AI's flares refilled
    --             (CFG.flares: chosen at the main menu from the saved profile, so from the next game session)
    --   gun       post-stall (cobra, kulbit) on every airframe from tier post_stall_from; duelist / wolf: those fighter
    --             roles' weight in the round's mix x (1 + that x strength) (CFG.roles)
    --   tail      the squad director's cover-the-tailed and trap: budgets x (1 + budget_x x strength), cooldowns that much
    --             shorter (CFG.director); wolf as above
    --   high      lancer as above, the Lancers come in above_m over your usual height (within their band), and the
    --             squad director's top cover: budget x (1 + top_cover_x x strength), its cooldown that much shorter
    --   airfield  the airfield's strike package more often (strike_x, strike_max as the jammer's); skirm as above
    -- The run's own shares count once each has live_kills of the kills it's taken from (missile: your kills with a
    -- weapon seen; behind: those with an aspect; gun: either half's) and live_samples samples for the time habits,
    -- weighed against the saved profile as if it were prior_kills kills (prior_samples samples). save: the profile is
    -- kept in config/survival_profile.ini (the game's own file next to survival.ini, never sent; delete it, and any
    -- .tmp / .bak beside it, to start over), read at the main menu and at each level load (a run's first rounds are
    -- countered from it), written at each run's end (checkpoint: and at each round's end, so a game that closes mid-run
    -- doesn't lose it: learnt from at the next start); never in place (a .tmp, the old one aside as .bak until the new
    -- one's in; one that wasn't a profile kept as .old). A run of fewer than min_kills of your kills of fighters, or
    -- one started past round 1 (a co-op joiner's: the host's round it joined in), is counted but not learnt from, and
    -- its time habits and height only with min_samples samples; each share of a run weighs n / (n + fold_kills) in the
    -- profile, n its own count (n / (n + fold_samples) for the time habits), at most run_weight_max.
    -- Each player's own in co-op (sv_coop.lua PERSONAL); only the host's counters reach the room. enabled = false: no
    -- profile and no counters; save = false: each run learns on its own (nothing read or written). Untested in game.
    profile = {
        enabled = true, save = true, checkpoint = true, min_kills = 8, min_samples = 60, live_kills = 5,
        live_samples = 30, prior_kills = 20, prior_samples = 150, fold_kills = 30, fold_samples = 300, run_weight_max = 0.5,
        missile  = { enabled = true, threshold = 0.8, jammer_x = 1.0, jammer_max = 0.9, rank_add = 1, rank_from = "Veteran" },
        gun      = { enabled = true, threshold = 0.35, post_stall_from = "Regular", duelist = 1.0, wolf = 0.5 },
        tail     = { enabled = true, threshold = 0.7, time_full = 0.3, budget_x = 1.0, wolf = 1.0 },
        high     = { enabled = true, threshold = 0.5, over_m = 1000, alone_m = 5000, near_km = 15.0, lancer = 1.5,
                     above_m = 1000, top_cover_x = 1.0 },
        airfield = { enabled = true, threshold = 0.4, km = 8.0, skip_raids = true, after_takeoff_s = 45,
                     before_landing_s = 45, strike_x = 1.0, strike_max = 0.9, skirm = 1.5 },
    },
    -- The AI's flares (P6's missile counter; the critic's lever): every stock fighter carries NPC_FCS_PlaneFlr000 in
    -- weapon slot 0 (10 flares a release, 10 in the magazine, 25 s to reload). When the saved profile (CFG.profile) has
    -- you missile-heavy at the main menu, the fighters' rows (not the specials' own) get a copy that holds `magazine`
    -- and reloads in reload_s. Rows are made once a game session: a change shows from the next one. always: every
    -- session, whatever the profile says (a test). Each player's own (PERSONAL). Untested: whether the game uses the
    -- copy (the missile and gun copies are confirmed).
    flares = { enabled = true, always = false, magazine = 20, reload_s = 8.0 },
    -- Tells (the behaviour roadmap's P3, Scripts/sv_tells.lua; tools/re/BEHAVIOUR_DIRECTOR.md unit 4: "a radio line or
    -- HUD callout before each coordinated threat"; radio lines only since the clean up of 2026-10-29, user: "remove the
    -- hud warnings that we added, it's too much, keep the Voice lines though"): a tell is an id of `list`, said by
    -- TELL.say. Its radio line is one of `radio` (RE_SV_Radio<Suffix>: a stock AC8 line cloned into DT_SV_Radio at build
    -- time, tools/survival_events.py TELL_LINES; the build fails on a name here it didn't make), at random but never the
    -- same twice running, or the a-th with pick = "a"; chain: another tell's line after it (picked the same way).
    -- Each player's tells on their own (co-op: sv_coop.lua PERSONAL, the host's reach a joiner as "tl" and play from the
    -- joiner's own settings, enabled too: a host with tells off still sends them; the host's gaps, cooldowns, leads,
    -- hunt_km and wave_from_round decide when): radio_gap_s after the last tell, each id no sooner than its cooldown_s;
    -- none between rounds, down at the airfield or over the run's summary. A radio line is never asked for again within
    -- line_gap_s, by whichever tell (reversal and kulbit share theirs; the cloned rows keep the template's
    -- RequeueingWaitTime of 20 s, which may skip a group asked for again inside it; 0: no such limit): a tell whose lines
    -- are all that recent isn't said.
    -- sure = true (the bosses' phase changes, P7: the warning before a change that must come, code review of unit 9; an
    -- ace squadron's first contact, P9): through radio_gap_s and its cooldown; never with tells off, between rounds, down
    -- at the airfield, over the summary or within its lines' line_gap_s; a host sends it to its joiners through its gaps.
    -- lead_s: an action that follows its tell (TELL.after) comes this long after it, at once when the tell wasn't said
    -- or tells are off. cooldown_s kulbit 12: an ace's next kulbit comes its lead + 12 s after the last (ACE.movesTick),
    -- so each is told (code review of 2026-10-29: at 20 every other one came untold).
    -- enabled = false: no tells for this game's player (and its own tells' actions at once, as before tells; a co-op
    -- host still sends its joiners theirs, with its leads); radio = false: no lines (as enabled = false, the leads kept).
    -- Wired to today's threats: an ace's reversal (reversal, kulbit within 900 m: ACE.movesTick, its move lead_s after
    -- the call), a hunting tier's flight within hunt_km of you (hunt, once a flight a round), a bomber raid or strike on
    -- the airfield (raid), the jammer up and down, each later wave from wave_from_round (wave; 0: never), the ALICORN's
    -- railgun (alcn_rail_first, then alcn_rail: lead_s before the order, with CFG.specials.alicorn.rail_alert), dive,
    -- surfacing and VLS volley, a Ladon's VLS volley, the squad director's tactics (P2, CFG.director: cover_ask and six
    -- for cover, drag (or lure: CFG.director.trap.warn) and trap for the Wolf trap, bracket, dive with its clock for top
    -- cover, pincer, regroup), the bosses' phases (P7, CFG.specials: the ALICORN's deck launch alcn_deck, MINDRIPPER's
    -- pack springing, AB.L..IN behind you glitch_six and its ECM down glitch_allout, a Ladon enraged ladon_rage) and the
    -- ace squadrons (P9: <tier>_in, blink).
    tells = {
        enabled = true, radio = true, radio_gap_s = 2.0, line_gap_s = 20, hunt_km = 8.0, wave_from_round = 26,
        cooldown_s = { reversal = 20, kulbit = 12, hunt = 45, raid = 30, jammer = 30, jammer_down = 10, wave = 20,
                       alcn_rail_first = 0, alcn_rail = 0, alcn_dive = 0, alcn_up = 0, alcn_vls = 30, alcn_deck = 30,
                       ladon_vls = 15, pincer = 30, dive = 20, clock = 0, drag = 30, lure = 30, trap = 20,
                       cover_ask = 20, six = 20, bracket = 15, regroup = 30,
                       pack = 20, glitch_six = 0, glitch_allout = 0, ladon_rage = 0,
                       mercenary_in = 0, legend_in = 0, demon_in = 0, phantom_in = 0, reaper_in = 0, blink = 10 },
        lead_s = { reversal = 1.0, kulbit = 0.5, alcn_rail = 5.0, alcn_vls = 1.0, ladon_vls = 0.0, dive = 1.0, trap = 1.0,
                   six = 1.0, bracket = 1.0, mercenary_in = 1.0, legend_in = 0.0, demon_in = 0.5, phantom_in = 0.5,
                   reaper_in = 0.5, blink = 0.5 },
        list = {
            reversal        = { radio = { "RE_SV_RadioTurnA", "RE_SV_RadioTurnB" } },
            kulbit          = { radio = { "RE_SV_RadioTurnA", "RE_SV_RadioTurnB" } },
            hunt            = { radio = { "RE_SV_RadioHuntA", "RE_SV_RadioHuntB" } },
            raid            = { radio = { "RE_SV_RadioRaidA", "RE_SV_RadioRaidB", "RE_SV_RadioRaidC" } },
            jammer          = { radio = { "RE_SV_RadioJam" } },
            jammer_down     = { radio = { "RE_SV_RadioJamDown" } },
            wave            = { radio = { "RE_SV_RadioWaveA", "RE_SV_RadioWaveB", "RE_SV_RadioWaveC", "RE_SV_RadioWaveD" } },
            alcn_rail_first = { radio = { "RE_SV_RadioAlcnRailFirst" } },
            alcn_rail       = { radio = { "RE_SV_RadioAlcnRailA", "RE_SV_RadioAlcnRailB" } },
            alcn_dive       = { radio = { "RE_SV_RadioAlcnDive" } },
            alcn_up         = { radio = { "RE_SV_RadioAlcnUp" } },
            alcn_vls        = { radio = { "RE_SV_RadioAlcnVls" } },
            alcn_deck       = { radio = { "RE_SV_RadioAlcnDeck" } },
            ladon_vls       = { radio = { "RE_SV_RadioLadonVlsA", "RE_SV_RadioLadonVlsB" } },
            pincer          = { radio = { "RE_SV_RadioPincerA", "RE_SV_RadioPincerB", "RE_SV_RadioPincerC", "RE_SV_RadioPincerD" } },
            dive            = { radio = { "RE_SV_RadioDiveA", "RE_SV_RadioDiveB", "RE_SV_RadioDiveC", "RE_SV_RadioDiveD" },
                                chain = "clock" },
            clock           = { radio = { "RE_SV_RadioClockA", "RE_SV_RadioClockB", "RE_SV_RadioClockC", "RE_SV_RadioClockD",
                                          "RE_SV_RadioClockE", "RE_SV_RadioClockF", "RE_SV_RadioClockG", "RE_SV_RadioClockH",
                                          "RE_SV_RadioClockI", "RE_SV_RadioClockJ", "RE_SV_RadioClockK", "RE_SV_RadioClockL" },
                                pick = "a" },
            drag            = { radio = { "RE_SV_RadioDrag" } },
            lure            = { radio = { "RE_SV_RadioEnLureA", "RE_SV_RadioEnLureB" } },
            trap            = { radio = { "RE_SV_RadioTrap", "RE_SV_RadioEnTrap" } },
            cover_ask       = { radio = { "RE_SV_RadioEnCoverA", "RE_SV_RadioEnCoverB", "RE_SV_RadioEnCoverC" } },
            six             = { radio = { "RE_SV_RadioSixA", "RE_SV_RadioSixB", "RE_SV_RadioSixC", "RE_SV_RadioSixD" } },
            bracket         = { radio = { "RE_SV_RadioBracketA", "RE_SV_RadioBracketB", "RE_SV_RadioBracketC" } },
            regroup         = { radio = { "RE_SV_RadioRegroupA", "RE_SV_RadioRegroupB" } },
            -- the bosses' phases (behaviour roadmap P7, tools/re/BEHAVIOUR_DIRECTOR.md unit 9): MINDRIPPER's pack springing
            -- (the host's own: CFG.specials.anomaly.pack), AB.L..IN's phase 2 (behind you: the host's own) and 3 (ECM down,
            -- guns: every player), a Ladon enraged (every player)
            pack            = { radio = { "RE_SV_RadioTrap", "RE_SV_RadioEnTrap" }, sure = true },
            glitch_six      = { radio = { "RE_SV_RadioSixA", "RE_SV_RadioSixB", "RE_SV_RadioSixC", "RE_SV_RadioSixD" }, sure = true },
            glitch_allout   = { radio = { "RE_SV_RadioGlitchEcm" }, sure = true },
            ladon_rage      = { radio = { "RE_SV_RadioLadonRage" } },
            -- the ace squadrons' (behaviour roadmap P9, CFG.aces.personality: tools/re/BEHAVIOUR_DIRECTOR.md unit 10): a
            -- squadron's first contact of a round (sure), its opener the tell's lead_s on; blink: a Wraith (or Harvest)
            -- lead blinking off your six. The lines are other tells' (no new radio rows)
            mercenary_in    = { radio = { "RE_SV_RadioDiveA", "RE_SV_RadioDiveB", "RE_SV_RadioDiveC", "RE_SV_RadioDiveD" }, sure = true },
            legend_in       = { radio = { "RE_SV_RadioEnLureA", "RE_SV_RadioEnLureB" }, sure = true },
            demon_in        = { radio = { "RE_SV_RadioTurnA", "RE_SV_RadioTurnB" }, sure = true },
            phantom_in      = { radio = { "RE_SV_RadioSixA", "RE_SV_RadioSixB", "RE_SV_RadioSixC", "RE_SV_RadioSixD" }, sure = true },
            reaper_in       = { radio = { "RE_SV_RadioHuntA", "RE_SV_RadioHuntB" }, sure = true },
            blink           = { radio = { "RE_SV_RadioSixA", "RE_SV_RadioSixB", "RE_SV_RadioSixC", "RE_SV_RadioSixD" } },
        },
    },
    -- Enemy skill tiers (user, 2026-10-22: early fighters must not fly like aces). Every enemy gets its tier's
    -- PilotRank when it appears (1-5: how often it picks the better evasions and flares of its behaviour set; a live
    -- write sticks, test 16), plus rank_add for the difficulty, kept within 1-5. A tier without post_stall never
    -- uses the cobra / kulbit, even on a model CFG.maneuvers allows. The round picks the tier; promote_chance of the
    -- pilots fly one tier higher. Survival's behaviour scripts (CFG.behaviour_sets) weigh their moves by the rank
    -- and the AI level these set; ranks 6-10 fly the named aces' squadrons (CFG.aces).
    -- provoke_cone_deg / provoke_time_s / surround_m: written live on the tier's pilots, as CFG.spikes' (CFG.ai
    -- tier_provoke; a harder tailed plane, P5 of tools/re/BEHAVIOUR_DIRECTOR.md, 2026-10-29: from Veteran up a pilot
    -- notices you within 60 deg of its six after 1.5 s, the game's own rows 85 deg / 2.5 s; live write, untested).
    tiers = {
        enabled = true,
        promote_chance = 0.2,
        rank_add = { casual = -1, standard = 0, ace = 1 },
        list = {
            { name = "Rookie",  from_round = 1,  rank = 2, post_stall = false },   -- one rank up (user, 2026-10-22:
            { name = "Regular", from_round = 4,  rank = 3, post_stall = false },   -- "still felt very easy")
            { name = "Veteran", from_round = 7,  rank = 4, post_stall = true, provoke_cone_deg = 60, provoke_time_s = 1.5 },
            { name = "Elite",   from_round = 10, rank = 5, post_stall = true, provoke_cone_deg = 60, provoke_time_s = 1.5 },
            { name = "Ace",     from_round = 13, rank = 5, post_stall = true, provoke_cone_deg = 60, provoke_time_s = 1.5 },
            -- Beyond Ace (user, 2026-10-22: "make more of these pilot ranks"). The game clamps PilotRank to 1-5, so these
            -- stay at 5 and raise the AI level instead (the flight's LevelId, 100 x ai_level, written before it spawns:
            -- dlls/main.dll SV_SetLevel; stock is 2). Survival's behaviours weigh their tight tail chase, cobra / kulbit
            -- bait and scissors by it (tools/re/BEHAVIOUR_GUIDE.md 6). fcs: fire control at least that difficulty-spike
            -- level's; provoke / surround: as CFG.spikes' (react quicker when tailed, sit closer when pursuing).
            { name = "Mercenary", from_round = 16, rank = 5, post_stall = true, ai_level = 3, fcs = 1,
                                  provoke_cone_deg = 60, provoke_time_s = 1.5 },
            { name = "Legend",    from_round = 19, rank = 5, post_stall = true, ai_level = 4, fcs = 2,
                                  provoke_cone_deg = 60, provoke_time_s = 1.5 },
            { name = "Demon",     from_round = 22, rank = 5, post_stall = true, ai_level = 5, fcs = 2,
                                  provoke_cone_deg = 60, provoke_time_s = 1.5 },
            { name = "Phantom",   from_round = 25, rank = 5, post_stall = true, ai_level = 5, fcs = 3,
                                  provoke_cone_deg = 50, provoke_time_s = 1.0 },
            { name = "Reaper",    from_round = 28, rank = 5, post_stall = true, ai_level = 5, fcs = 3,
                                  provoke_cone_deg = 45, provoke_time_s = 0.8, surround_m = { 40, 100 } },
        },
    },
    -- Named aces (user, 2026-10-22: "build it with this line up, but custom names"). From Mercenary on, a fighter flight
    -- flies its tier's squadron: one airframe of the tier's line-up (ACE.roster; stock skins: Shark / Ventus F-15C and
    -- Su-35, Savia Rafale, Ares Su-57, Shadow Su-57 / Typhoon / Su-47, the named aces' own), its wingmen under the
    -- squadron's name and its lead, when that ace isn't already up, under the ace's own. These are only the names:
    -- [aces.<tier>] in survival.ini renames them; which airframe a name flies is fixed (tools/build_survival.py ACES).
    -- Ace rounds come on a cycle (user, 2026-10-22: "Ace Rounds on a Cycle"): from first_round, every `every`th round is
    -- an ace round, all of it the round's tier's squadrons (no ordinary flights, no bomber raid); the rounds between are
    -- normal ones, ordinary aircraft flown at the same tier (its AI level, fire control and reactions).
    aces = {
        enabled = true,
        first_round = 16, every = 3,
        callout = true,                            -- "ACE INBOUND" the first time each ace shows up in a run
        -- their guns lead you (user, 2026-10-24: "apply the gun lead to all enemy ace aircraft and scale it"): a tier's
        -- gun_lead_s (PredictionOffsetTime: the seconds ahead of you they aim; stock aircraft guns 0), the higher the
        -- tier the more, + gun_lead_per_level for each difficulty spike level, at most gun_lead_max. "anomaly" is
        -- MINDRIPPER's guards (MINDRIPPER and AB.L..IN have their own: specials.anomaly / glitch gun_lead_s).
        gun_lead_s = { mercenary = 0.4, legend = 0.55, demon = 0.7, phantom = 0.85, reaper = 1.0, anomaly = 0.85 },
        gun_lead_per_level = 0.1, gun_lead_max = 1.3,
        -- airframes only Online Mode has (the ADFX-02: its model and blueprint come from Online Mode's tables, ACE.models).
        -- false leaves them out (if one ever misbehaves offline); their tier flies the rest of its line-up.
        online_aircraft = true,
        mercenary = { squadron = "Bounty",   f15c = "Ledger",   su35 = "Wager",    typhoon = "Payday" },
        legend    = { squadron = "Valkyrie", su47 = "Sigrun",   rafale = "Brynhild" },
        demon     = { squadron = "Inferno",  f22a = "Mephisto", su57 = "Belial" },
        phantom   = { squadron = "Wraith",   su57 = "Specter",  typhoon = "Revenant", su47 = "Banshee" },
        reaper    = { squadron = "Harvest",  su57 = "Grim",     f22a = "Scythe",   typhoon = "Charon", rafale = "Nightfall",
                      adfx02 = "Oblivion" },
        -- a tier's squadron airframes (its ace rows, lead and wing) flying beyond stock (user, 2026-10-23: "the Reaper
        -- Squadron was so easy to handle, make them 10x more aggressive ... they still had issues getting behind me";
        -- their behaviours already weigh everything at rank 5 / AI level 5): turn rates + turn_add (pitch / roll / yaw,
        -- as MINDRIPPER's 120 / 270 / 25), top and cornering speed x speed_x, cruise x cruise_x, health + health_add;
        -- post_stall: cobra and kulbit on, whatever the airframe's blueprint says (Grim's Su-57 had both off);
        -- hunt: its target kept on you (the AI's blackboard TargetActor, every 2 s: Grim's stayed on the airfield's
        -- target dummy for the whole of the test of 2026-10-23 while its wingman went for the player); no_provoke: its
        -- bPermissionToProvoke off (tools/re/BEHAVIOUR_NATIVE_LOGIC.md 8.2: being tailed put it in Provoke, then our
        -- reactions handed it to EscapeFromPursuer, both above PursueTarget, so a tailed ace defended and never
        -- turned on you; without it the pursuit, and LA_SV_TailChase's AI-level-5 "Super" branch, turn it onto you);
        -- moves: when you get behind one of its aircraft (within 3 km, inside 70 deg of its tail; ACE.movesTick, 4 times
        -- a second) its flight does the campaign aces' LastTGT reversal, or within 900 m the Shadow kulbit
        -- (tools/survival_events.py build_ace_moves); a flight's next move no sooner than 30 s after a reversal (its
        -- LastTGT's length; CFG.director.cover.move_s), 12 s after a kulbit, from the move. no_provoke and moves are a tier's
        -- duelists' and its squadron's: a fighter role's Lancer, Wolf or Skirmisher flight keeps its own set's provoke
        -- and pursuit (ROLE.ownSet; CFG.roles), and so does a squadron's role flight on a tier without them (Bounty's
        -- Lancers, Valkyrie's Wolf pairs: never turned by the squad director's cover or push either)
        -- The squadrons' personalities (behaviour roadmap P9, "each named squadron should be recognisable within 10
        -- seconds"; `personality` below, tools/re/BEHAVIOUR_DIRECTOR.md unit 10), a squadron's only (never its tier's
        -- ordinary flights): roles, its ace round's role mix (as CFG.roles.mix's, in place of CFG.roles.ace_mix; a
        -- squadron flies its role's behaviour set, its own airframes): Bounty the Lancers', Valkyrie the Wolf pairs',
        -- Inferno, Wraith and Harvest the duelists' (LA_SV_TailChase's AI-level-5 "Super" pursuit is only in that set:
        -- the critic's caveat); openers, what each flight shows at first contact, in turn ("high", "trap", "kulbit",
        -- "blink": personality); blink, its lead blinking behind and beside you while you sit on its six (tailed_km,
        -- tail_deg; on_hit: or once you hit it), at most every every_s, the flight's reversals no sooner than move_gap_s
        -- after (D.aceMoveAt, shared with moves). Harvest combines them: its flights open in turn with a kulbit, a blink
        -- and a dive from high, its lead blinks off your six, and it keeps its reversals and hunt.
        flight = {
            mercenary = { roles = { duelist = 0.0, lancer = 1.0, wolf = 0.0, skirm = 0.0 }, openers = { "high" } },
            legend    = { roles = { duelist = 0.0, lancer = 0.0, wolf = 1.0, skirm = 0.0 }, openers = { "trap" } },
            demon     = { roles = { duelist = 1.0, lancer = 0.0, wolf = 0.0, skirm = 0.0 }, openers = { "kulbit" } },
            phantom   = { roles = { duelist = 1.0, lancer = 0.0, wolf = 0.0, skirm = 0.0 }, openers = { "blink" },
                          blink = { enabled = true, every_s = 20, tailed_km = 2.5, tail_deg = 70, on_hit = true,
                                    move_gap_s = 10 } },
            -- ((0.73.78, plan G4) health_add 600 -> 0: MaxHealthDifference is in MaxHealth HP, ten times the log's units
            -- (HealthInternal), so +600 was +6,000 on a 60-115 HP body: Harvest's 9,900-10,725 in the 5-player run of
            -- 2026-11-02, Inferno's Su-57 1,564. Each tier's health is [aces.health]'s now, set as a plane is first seen)
            reaper = { turn_add = { pitch = 180, roll = 360, yaw = 45 }, speed_x = 1.25, cruise_x = 1.15,
                       health_add = 0, post_stall = true, hunt = true, no_provoke = true, moves = true,
                       roles = { duelist = 1.0, lancer = 0.0, wolf = 0.0, skirm = 0.0 },
                       openers = { "kulbit", "blink", "high" },
                       blink = { enabled = true, every_s = 30, tailed_km = 2.5, tail_deg = 70, on_hit = false,
                                 move_gap_s = 10 } },
        },
        -- Ace personalities (P9): a squadron flight's opener the first time one of its aircraft comes within its km of a
        -- player (the 2 s sweep's positions), after its squadron's tell (tells: CFG.tells <tier>_in, its radio call, to
        -- that player; the round's first flight of the squadron; a later one says its opener's own: dive, drag, kulbit,
        -- blink) and the tell's lead_s:
        --   high    spawned openers.high.alt_add_m higher (up to top_m; a Lancer flight is already 2 km up), a missile
        --           from up to salvo of its aircraft within range_km of you, gap_s apart (RE_SV_Salvo_<NN><L>: the
        --           fighters' missile slot, P2's bracket's)
        --   trap    a Wolf flight's trap (its odd aircraft held at engagement None from its appearance, as CFG.roles.wolf;
        --           held, freed when hit or its bait is down) springs spring_s after contact: the "trap" tell, then free
        --           and LastTGT onto you (RE_SV_WolfFree / WolfTurn); not held yet, it waits up to wait_s more. Held
        --           until that contact (roles.wolf's hold_max_s runs from it), at most hold_max_s from the hold (0: as
        --           any Wolf flight's). A squadron flight off the Wolf pairs: the pack turns on you instead
        --           (RE_SV_AceTurn_NN, LastTGT)
        --   kulbit  every aircraft of the flight kulbits as one, firing its special (RE_SV_AceKulbit_NN: the Shadows')
        --   blink   its lead (object 0) blinks to a spot behind and beside you (RE_SV_WraithBlink<K><J>, ACE.BLINK's ring,
        --           a duelist flight's lead only; ground_clear_m over the ground), smoke where it left and came out (smoke)
        -- The host's (or solo). A co-op joiner who meets a squadron first gets its tell ("tl") and what reaches them: a
        -- salvo on their own copies ("dv"), the kulbit, the trap freed without the turn; a blink is round the host only.
        -- enabled = false: ace rounds draw CFG.roles.ace_mix, no openers or blinks (the Reaper's own levers stay).
        personality = { enabled = true, tells = true, ground_clear_m = 150, smoke = true,
                        openers = { high = { km = 5.0, alt_add_m = 2000, top_m = 4500, salvo = 2, gap_s = 0.6, range_km = 5.0 },
                                    trap = { km = 4.0, spring_s = 8, wait_s = 15, hold_max_s = 300 },
                                    kulbit = { km = 2.5 },
                                    blink = { km = 4.0 } } },
        -- (0.73.78, plan G4; the 5-player run of 2026-11-02, rounds 20-40: "it took us 30+ missiles ... to down a single
        -- aircraft and there were over twenty of them per wave"; the user, 2026-11-03: "health per tier instead, smaller
        -- ace rounds, Harvest every other ace round")
        -- health: each squadron's health in HP (MaxHealth; the log's "health" numbers, HealthInternal, are ten times it),
        -- its wingmen's `wing`, its named lead's `lead`, whatever airframe row it flies (the campaign's CP_Named /
        -- CP_Shadow bodies included), set as each plane is first seen (sv_ai.lua ACE.setHealth: MaxHealth and health,
        -- the share of a plane hit before kept). A squadron flown at a higher tier's skill (rotation below) keeps its own.
        -- late: CFG.late's health x on top (false: these are the whole of it). enabled = false: each airframe's own
        -- health, x CFG.late's, as before (and the rows' health_add)
        health = { enabled = true, late = false,
                   mercenary = { wing = 100, lead = 250 }, legend = { wing = 120, lead = 320 },
                   demon = { wing = 140, lead = 380 }, phantom = { wing = 160, lead = 460 },
                   reaper = { wing = 180, lead = 540 } },
        -- round: an ace round's size (the tester: "ace fights when there was only 6-10 of them while my entire screen
        -- was filled with missile alerts"): aircraft[1] in the first ace round (first_round), per_round more for each
        -- round past it, at most aircraft[2]; at most up[1] .. up[2] of them up at once the same way (up_per_round), in
        -- waves of up - next_at, the next wave when next_at or fewer of the last are left (a 6-ship comes as a wave of its
        -- own). Both x the menu's ENEMY AIRCRAFT %, then co-op's [coop] aircraft_per_player within aircraft[2] / up[2].
        -- enabled = false: an ace round is as big as a normal one (the round's budget and the waves' max_up)
        round = { enabled = true, aircraft = { 12, 24 }, per_round = 0.5, up = { 6, 10 }, up_per_round = 0.15, next_at = 2 },
        -- rotation: from from_round the top squadron (Harvest: the last tier with a line-up) flies only every top_every-th
        -- ace round (2: every other one; promoted earlier, it counts); the ace rounds between fly one of `standins` (the
        -- one flown longest ago) at the round's tier's skill (its AI level, fire control, reactions and levers), with its
        -- own airframes, health and personality (roles, openers, blinks). enabled = false: the round's tier's squadron
        rotation = { enabled = true, from_round = 28, top_every = 2, standins = { "phantom", "demon", "legend", "mercenary" } },
        -- break_off: after_s of an ace round (counted while the round's flying, not while you're down at the airfield
        -- alone) its squadron's aircraft still up break off (engagement None, no more openers, reversals or specials) and
        -- leave: each flight despawned once all of it is far_km from every player, or leave_s after the break; what was
        -- shot down was paid as it went, the rest pays nothing, its later waves never come, and the round ends as its
        -- other aircraft go (IMPROVEMENTS "Pacing and rounds" 3: Harvest's rounds ran 8-15 minutes)
        break_off = { enabled = true, after_s = 360, leave_s = 12, far_km = 4.0 },
    },
    -- Enemy search range (user 2026-10-22: no chase, enemies should always have the player in view). Mission 22's
    -- fighters use AI module NPC_AIModule_Plane000: 6 km search radius, and they lose a target hidden in cloud.
    -- Survival's own module row (a copy with these values) is given to copies of the aircraft's DT_NPC rows.
    -- The flights' unit area (activation) is set at build time: tools/survival_events.py AREA_RADIUS_M.
    -- luaset: the behaviour set those copies fly (a DT_NPC_LuaSet row, or one of CFG.behaviour_sets; nil keeps each
    -- aircraft's own); fallback_luaset when an own set couldn't be made. NLID_0400_CP (the campaign aces' set) is NOT
    -- usable: its pursuit only attacks in KDS phases, which these fighters never get (test of 2026-10-22: "the
    -- aircraft aren't attacking the player anymore").
    search = { enabled = true, radius_m = 40000, lose_in_clouds = false, luaset = "NLID_SV_Fighter",
               fallback_luaset = "NLID_0012_CP" },
    -- The fighters' missiles (user, 2026-10-22: "it takes them forever to get a missile lock"). Every stock enemy
    -- missile is fire-control row NPC_FCS_PlaneMsl000: lock only within 2.5 km and 45 deg, 2 s to arm, 2.5 s to lock,
    -- 10 s between shots (aces: 60 deg, 5 s). Each fighter's Survival NPC row gets a copy (<row>_SV in DT_NPC_FCS)
    -- with these values: range (m), cone (deg), arm / lock / between-missiles / rest (s).
    missiles = { enabled = true, capture_m = 4000, angle_deg = 60, arm_s = 0.5, lock_s = 1.5, interval_s = 2.0, rest_s = 5.0 },
    -- The fighters' gun (user, 2026-10-22: "increase their guns too and accuracy"). Every enemy gun, aces included, is
    -- NPC_FCS_PlaneGun000: fires within 1.5 km and 30 deg after 1.5 s on target, 10-round bursts, 1 s rest; its rounds
    -- (GUN_000 in DT_NPC_Weapon) do 1 damage and spread up to 3 deg. Survival's copies (<row>_SV): range (m), cone (deg),
    -- time on target before firing (s), rounds a burst, rest (s), damage multiplier, spread (deg).
    guns = { enabled = true, range_m = 2000, angle_deg = 40, aim_s = 0.8, burst = 15, rest_s = 0.6, damage_x = 1.5, spread_deg = 1.5 },
    -- Special weapons (user, 2026-10-22): each fighter type gets one of these stock ace fire-control rows (QAAM, 2AAM,
    -- LAAM, HCAA, as the Shadow aces carry theirs) in its first free weapon slot, picked at random once a session; its
    -- fire control fires it by itself when the player is in its range and cone.
    -- how many missiles may be in the air at you at once (Scripts/sv_spweapons.lua ATK; the user, 2026-10-31: "is there a
    -- hard cap ... I've only ever seen 4 missiles launch at me at one time ... is there a way to increase that?"): the game
    -- allows 2 from aircraft and 2 from ships / SAM sites / turrets on every difficulty; your plane's own limits set to
    -- plane_missiles and nonplane_missiles, pursuers the aircraft that may chase you at once (0: the game's), every check_s
    -- (user, 2026-10-31: "I want 6 missiles from aircraft and 14 missiles from ships", "set the pursuers to 12", "increase
    -- the number of ships and sam site targetting to 40")
    attackers = { enabled = true, plane_missiles = 6, nonplane_missiles = 40, pursuers = 12, check_s = 2 },
    -- (0.73.77, plan F2b) a recycled flight (shot down, taken off the phase's list so it can spawn again) has its old unit
    -- actor destroyed destroy_after_s later, not at the next spawn (runtime 0.32.22, SV_RecycleWait): Shazzy's two crashes
    -- at the round 3 bomber raid came 3-5 s after that destroy, in the game's AI path tracking. 0: at once, as before.
    recycle = { destroy_after_s = 30 },
    special = { enabled = true,
                fcs = { "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000", "NPC_FCS_PlaneLAAM000", "NPC_FCS_PlaneHCAA000" },
                -- fired (Scripts/sv_spweapons.lua; the user, 2026-10-31: "I want the Enemies to fire their Special
                -- Weapons too": their AI never picks the slot): every check_s, an enemy whose row carries a special in
                -- slot 3 fires it at you (RE_SV_SpecFire_<NN><L>) when you're inside cone_deg of its nose at that
                -- weapon's range (ranges: km, by its fire control's name; default for any other), first_s after it
                -- appears and then every every_s at most, max_per_min of them across the whole sky. The host's (or
                -- solo): at the host's plane
                fire = { enabled = true, check_s = 1, first_s = 10, every_s = 25, cone_deg = 35, max_per_min = 8,
                         ranges = { QAAM = { 1.0, 4.5 }, HCAA = { 2.0, 7.0 }, ["2AAM"] = { 1.5, 6.0 }, LAAM = { 4.0, 12.0 },
                                    default = { 2.0, 7.0 } } } },
    -- Survival's own behaviour sets: a DT_NPC_LuaSet row copied from `base`, with `slots` pointing at Survival's
    -- scripts (Scripts/ai/<name>.lua, packaged at /Game/LuaSource/SurvivalMode/AI/<name> by tools/build_survival.py
    -- LUA_SCRIPTS). Made from the main menu on: the game builds a flight's behaviour when the level loads.
    -- NLID_SV_Fighter: Mission 22's light-fighter set (0012_CP) with LA_SV_MoveAway, a ~1.5 s break after each attack
    -- pass instead of 12.5 s. The pursuit stays the stock one: its closing SetMoveAwayFromTarget is what starts the
    -- next attack run (Lua 0.18.x dropped it and the fighters drifted between runs: test of 2026-10-22).
    -- NLID_SV_Fighter's pursuit: LA_SV_TailChase (tools/re/BEHAVIOUR_GUIDE.md), the stock fighter pursuit plus a
    -- "sit on the target's tail" branch (PursuerTarget with its own-offset flag: 250 m behind the target, KDS blocked)
    -- that its pilot rank weighs: rank 1 never, 2 10 %, 3 30 %, 4 70 %, 5 always. The skill tiers and difficulty spikes
    -- raise the rank, so the tail chasing grows with the rounds. ai.tail_chase = false keeps the stock pursuit.
    -- The fighter roles' sets (behaviour roadmap P1, CFG.roles; tools/re/BEHAVIOUR_DIRECTOR.md unit 5), each the
    -- light-fighter set with the role's slots (a slot left out keeps 0012_CP's stock script):
    --   NLID_SV_Lancer      boom and zoom: one slashing pass (LA_SV_LancerPass), a zoom climb back to height
    --                       (LA_SV_LancerZoom), tailed it runs and reverses (LA_SV_LancerBreak), never turning with you
    --   NLID_SV_WolfLead    the Wolf bait (a Wolf flight's even planes): tailed it drags you straight (LA_SV_WolfDrag,
    --                       then the stock 8 s escape run)
    --   NLID_SV_WolfWing    the Wolf trap (its odd planes, held until the trap springs): a gunfighter's close pursuit
    --                       (LA_SV_WolfStrike)
    --   NLID_SV_Skirmisher  the stand-off harasser: in for one shot, breaking off as it fires (LA_SV_SkirmPass), then a
    --                       long extend (LA_SV_SkirmExtend); tailed, the stock rookie defence (it dies fast if caught)
    behaviour_sets = {
        NLID_SV_Fighter = { base = "NLID_0012_CP", slots = { MoveAwayFromTargetLua = "LA_SV_MoveAway",
                                                             PursueTargetLua = "LA_SV_TailChase",
                                                             ProvokeNearLua = "LA_SV_ProvokeNear",
                                                             EscapeFromPursuerLua = "LA_SV_Escape" } },
        NLID_SV_Lancer = { base = "NLID_0012_CP", slots = { PursueTargetLua = "LA_SV_LancerPass",
                                                            MoveAwayFromTargetLua = "LA_SV_LancerZoom",
                                                            ProvokeNearLua = "LA_SV_LancerBreak",
                                                            ProvokeMidLua = "LA_SV_LancerBreak",
                                                            ProvokeFarLua = "LA_SV_LancerBreak",
                                                            EscapeFromPursuerLua = "LA_SV_Escape" } },
        NLID_SV_WolfLead = { base = "NLID_0012_CP", slots = { PursueTargetLua = "LA_SV_TailChase",
                                                              MoveAwayFromTargetLua = "LA_SV_MoveAway",
                                                              ProvokeNearLua = "LA_SV_WolfDrag" } },
        NLID_SV_WolfWing = { base = "NLID_0012_CP", slots = { PursueTargetLua = "LA_SV_WolfStrike",
                                                              MoveAwayFromTargetLua = "LA_SV_MoveAway",
                                                              ProvokeNearLua = "LA_SV_ProvokeNear",
                                                              EscapeFromPursuerLua = "LA_SV_Escape" } },
        NLID_SV_Skirmisher = { base = "NLID_0012_CP", slots = { PursueTargetLua = "LA_SV_SkirmPass",
                                                                MoveAwayFromTargetLua = "LA_SV_SkirmExtend" } },
    },
    -- reactions (user, 2026-10-22: "come up with some new reactions"): LA_SV_ProvokeNear when the player is close on
    -- their tail (break turn, brake-and-turn overshoot, flare break; AI level 3+ cobra bait, 4+ kulbit bait and
    -- scissors), LA_SV_Escape (low ranks the stock 8 s run, higher ranks the aces' 2 s break). false: the stock ones.
    -- (P5, 2026-10-29: every pick of both now moves: the overshoot only within 50 m, else a break; no cobra / kulbit
    -- without post-stall: a break; no flare ready: the break still comes; the sharp escape's altitude-gated move, then
    -- a turn. tools/re/BEHAVIOUR_DIRECTOR.md unit 2.)
    -- The live provoke (P5): when you sit inside an enemy's cone of its six for its decision time it goes into Provoke
    -- and defends (the reactions above). tier_provoke: each skill tier's provoke_cone_deg / provoke_time_s / surround_m
    -- (CFG.tiers.list: Veteran to Demon 60 deg / 1.5 s, Phantom 50 / 1.0, Reaper 45 / 0.8) are written on its pilots;
    -- false: only the difficulty spikes' and the specials' (the game's own rows otherwise: 85 deg / 2.5 s).
    -- provoke_stricter: where a tier and the round's spike both set one, the stricter value (a narrower cone, a quicker
    -- decision, a closer pursuit); false: the tier's replaces the spike's (before P5: a Veteran 60 / 1.5 would have
    -- softened spike 3's 50 / 1.0). provoke_cone_deg / provoke_time_s above 0: a test value for every tier that has
    -- its own (an A/B test against the game's: round 7, before the first spike, with tier_provoke off, then on with
    -- e.g. 30 / 0.5). Written once when a plane appears (sv_rows.lua enemySpike); later parts rewrite them with
    -- enemyProvoke. The writes read back (0.70.2); whether the game uses them is untested.
    ai = { tail_chase = true, reactions = true, tier_provoke = true, provoke_stricter = true,
           provoke_cone_deg = 0, provoke_time_s = 0.0 },
    -- Fighter roles (behaviour roadmap P1, "four behaviour sets instead of one": each enemy type asks the player a
    -- different question; tools/re/BEHAVIOUR_DIRECTOR.md unit 5). The fighter pool is split into role groups at build
    -- time (ROLE_BY_FLIGHT below, tools/survival_events.py POOL_ROLE), each group's world data naming its role's
    -- behaviour row, so the behaviour is in place when the level loads (hard rule 20):
    --   duelist  "can you out-turn me?"      today's fighters (NLID_SV_Fighter)
    --   lancer   "can you dodge from above?" spawns alt_add_m above the others, slashes through once and zooms back up,
    --            never turns with you (NLID_SV_Lancer)
    --   wolf     "will you take the bait?"   bait and trap pairs: the bait drags you when tailed (NLID_SV_WolfLead), its
    --            wingman (the trap, NLID_SV_WolfWing, a close gunfighter whose gun leads you, wolf.gun_lead_s) holds off
    --            at engagement None from its appearance until it's sprung (the squad director's, P2), hit, its bait goes
    --            down or wolf.hold_max_s pass (Scripts/sv_spawn.lua WOLF)
    --   skirm    "can you finish a fight before the next one starts?" a stand-off harasser: in for one long-range shot
    --            (its LAAM's copy from skirm.laam_m, never closer than skirm.laam_min_m), breaking off as it fires, then a
    --            long extend; its health x health_x.skirm (0.75: it dies fast if caught) (NLID_SV_Skirmisher)
    -- A round's fighters are drawn by mix (the band of the latest from_round the round has reached: each role's share
    -- of the round's aircraft, in whole 2-ships; a group that runs short is filled from the others, logged), an ace
    -- round's by its squadron's roles (CFG.aces.flight <tier>.roles, P9's ace personalities: Bounty the Lancers',
    -- Valkyrie the Wolf pairs', the rest the duelists'), else ace_mix (personalities off: the squadrons keep the
    -- duelists' set). Each role flies its own airframes (aircraft; signature
    -- types only when they're the role's), a role with none unlocked yet its fallback role's, then the whole pool. The
    -- round's jammer leads a flight of the `jammer` roles only. Rows and sets are made at the main menu: a change needs a game
    -- restart. enabled = false: every flight flies today's set (the role rows name NLID_SV_Fighter) and the draw,
    -- airframes, spawn heights (altitude_m) and health are as before roles. Not reverted: the six Lancer units'
    -- (ERA_Unit_03 / 04_Dep_Air0-2) world-data band top of 9 km (ROLE.LANCER_TOP_M, build data: a unit's band can't
    -- change at run time), so LA_SV_Escape's altitude-gated climbs pass higher on those flights than under the others'
    -- 4-5 km.
    roles = {
        enabled = true,
        mix = { from_round = { 1, 4, 10 }, duelist = { 0.6, 0.4, 0.3 }, lancer = { 0.2, 0.2, 0.25 },
                wolf = { 0.2, 0.2, 0.25 }, skirm = { 0.0, 0.2, 0.2 } },
        ace_mix = { duelist = 1.0, lancer = 0.0, wolf = 0.0, skirm = 0.0 },
        aircraft = { duelist = { "su33_common", "su47_common", "su35_common", "rflm_common", "typn_common", "su57_common",
                                 "f22a_common" },
                     lancer  = { "f15e_common", "f14d_common", "f15c_common", "su34_common" },
                     wolf    = { "f16c_common", "m29a_common", "f18e_common", "m21b_common" },
                     skirm   = { "f02a_common", "j39e_common", "f35c_common" } },
        fallback = { skirm = "wolf" },              -- (the Skirmishers' airframes join at rounds 4 / 7 / 9: CFG.variety.late)
        health_x = { duelist = 1.0, lancer = 1.0, wolf = 1.0, skirm = 0.75 },
        jammer = { "duelist", "skirm" },
        lancer = { alt_add_m = 2000 },
        -- hold_after_s: the trap's hold this long after its flight's orders are seen in (its appearance's come 2 s after
        -- it spawns and would undo an earlier one: hard rule 26); free_on_hit: a held plane you hit is freed;
        -- free_on_bait_down: a held plane when its own bait (the plane before it) goes down, the whole trap when the
        -- flight's lead (object 0) does; nothing is freed while your DECOY stands the flight down (after it, then);
        -- rehold_s: after a unit-wide order (your DECOY's end) the planes still held are held again this long after
        wolf = { hold = true, hold_after_s = 3.0, hold_max_s = 60, free_on_hit = true, free_on_bait_down = true,
                 rehold_s = 1.0, gun_lead_s = 0.5 },
        skirm = { laam = true, laam_m = 7000, laam_min_m = 2500, laam_angle_deg = 45, laam_lock_s = 2.0,
                  laam_interval_s = 4.0, laam_rest_s = 8.0 },
    },
    -- The squad director (behaviour roadmap P2, Scripts/sv_director.lua; tools/re/BEHAVIOUR_DIRECTOR.md unit 6: "one Lua
    -- part that watches the whole sky and fires remote events on the right plane"): six tactics, each after its tell
    -- (CFG.tells: the action its lead_s later), each with a cooldown and a budget a round; the host's (co-op joiners get
    -- their own tells and shots, and see the planes move):
    --   cover      you on an enemy's tail (cover.tail_km, tail_deg) for cover.tail_s: the nearest plane of another flight
    --              within range_km of you that may turn (a duelist's, or a squadron's whose tier has the reversals,
    --              Harvest's; never another Lancer, Wolf or Skirmisher flight, Bounty's and Valkyrie's included:
    --              ROLE.ownSet; not an escort's or the jammer's) turns its flight onto you, the aces' reversal
    --              (RE_SV_AceTurn_NN; its next no sooner than move_s); the tailed one calls for help first (cover_ask, at
    --              ask_s), then "check your six" (six)
    --   trap       you on a Wolf bait's tail (fighter roles: CFG.roles) for trap.spring_s: its held wingman is sprung onto
    --              you; trap.warn's tell ("he's dragging you") at drag_s, "it's a trap" (trap) at the spring
    --   bracket    two enemies within bracket.range_km of you, their noses within nose_deg of you, sep_deg apart around
    --              you: each fires a missile at you at once (RE_SV_Salvo_<NN><L>), after the bracket tell
    --   top_cover  a Lancer flight (top_cover.roles; with roles off any flight, any_without_roles) held at engagement None
    --              hold_after_s after its orders are in, until you've fought another flight within engage_km for
    --              engaged_s and it's been held min_s: it dives on you after the dive tell (its o'clock). Let go quietly
    --              at max_s, when you hit it, or when no flight it doesn't hold is up (the round's or a wave's last;
    --              inside P4's hold at its end, 30 s at most); inside your DECOY at the decoy's end. The first flight
    --              up while more of its wave are to spawn waits for another (30 s at most)
    --   pincer     a new wave of 2+ fighter flights (not a special's or a raid's), with chance: its flights come from two
    --              bearings sep_deg apart, spread_deg either way, around you (ring_km; ahead: either side of your nose)
    --              solo, around the airfield in co-op; the pincer tell once each side has a flight (a flight
    --              the zone's edge sent to a normal point isn't part of it; one side only: no pincer, its budget back)
    --   regroup    a flight of min_size or more down to half its planes after_s or more after it came up: the regroup tell,
    --              it breaks off for hold_s (engagement None), then it's back
    -- budget: each tactic's most a round (in the band of the latest from_round reached: cover, trap and bracket each
    -- player's, the rest the room's); cooldown_s: between two of one tactic; gap_s: between any two the director starts
    -- (the pincer and top cover's hold apart). need_tell: a tactic waits until its tell can be said (CFG.tells' gaps);
    -- false, or tells off here, it goes without one. Never in a round of skip_specials (their own scripts run the fight).
    -- near_km: the planes looked at (within it of a player), reads: fresh reads of them a tick (the tailed ones first),
    -- players: the players looked at a tick (round-robin past it). A co-op joiner's tactics: a hunt with the flight's
    -- target kept on that player for aim_s (LastTGT turns onto the host), a salvo fired on its own copies ("dv").
    -- enabled = false (or a tactic's): none (as before P2). Untested in game.
    director = {
        enabled = true, need_tell = true, gap_s = 5.0, near_km = 6.0, reads = 8, players = 4,
        skip_specials = { "anomaly", "glitch", "valka", "ladon", "alicorn" },
        budget = { from_round = { 1, 5, 10, 20 }, cover = { 1, 1, 2, 2 }, trap = { 1, 1, 2, 2 }, bracket = { 0, 1, 1, 2 },
                   top_cover = { 0, 1, 1, 2 }, pincer = { 0, 1, 1, 1 }, regroup = { 0, 0, 1, 1 } },
        cooldown_s = { cover = 30, trap = 20, bracket = 25, top_cover = 30, pincer = 0, regroup = 30 },
        cover = { enabled = true, tail_km = 3.0, tail_deg = 70, ask_s = 1.5, tail_s = 3.0, range_km = 6.0, move_s = 30,
                  aim_s = 20 },
        trap = { enabled = true, warn = "drag", drag_s = 1.0, spring_s = 2.5, aim_s = 20 },
        bracket = { enabled = true, range_km = 4.0, nose_deg = 60, sep_deg = { 60, 120 } },
        top_cover = { enabled = true, roles = { "lancer" }, any_without_roles = true, hold_after_s = 3.0, min_s = 8,
                      max_s = 45, engage_km = 3.0, engaged_s = 3.0, aim_s = 20 },
        pincer = { enabled = true, chance = 0.6, sep_deg = { 90, 150 }, spread_deg = 10, ring_km = { 12, 18 }, ahead = true },
        regroup = { enabled = true, min_size = 4, after_s = 10, hold_s = 7 },
    },
    -- The intensity director (behaviour roadmap P4, Scripts/sv_director.lua; tools/re/BEHAVIOUR_DIRECTOR.md unit 7: "pressure
    -- follows the player, not the clock"). Every game scores its own player once a second, 0-100:
    --   intensity  how hard you're pressed (score): the damage you took in the last window_s (full at dmg_full of your
    --              health), enemy missiles homing on you within msl_km (full at msl_full), enemies within near_km (full at
    --              near_full) and the health you've lost, weighed damage / missiles / near / health (100 together),
    --              smoothed (smooth_x: a new second's share of it; 1, none)
    --   comfort    how easy it is (comfort): time on an enemy's tail (within tail_km / tail_deg of its six) in the last
    --              window_s (full at tail_full of it), your kills a minute over kills_window_s (full at kpm_full) and
    --              health above hp_pct %, weighed tail / kills / healthy; `high` is comfortable
    -- A co-op joiner sends its scores to the host ("in"); the host decides for the room (the hold on the room's highest):
    --   push   a player comfortable (comfort `comfort.high`+, intensity `low` or under) for calm_s: the squad director
    --          (CFG.director) lets a held top cover dive on them, else turns the nearest flight that may onto them (its
    --          "check your six" tell first; a joiner: a hunt with its target kept on them); push.per_round each a round
    --          from push.from_round, push.cooldown_s apart, within push.range_km
    --   hold   a player's intensity above `high` for hold.after_s: the next wave waits hold.secs (a random time in it,
    --          30 s at most) once it's due (its gate open: the last wave down to waves.next_at, or its timeout; the rest
    --          of a later wave still coming, at its next flight), at most hold.per_wave a wave; a top cover the squad
    --          director holds: its dive waits the same (as the round's last flight up its release too, 30 s at most
    --          from then: a held flight never stalls the round). Each hold never made longer, the next of its kind no
    --          sooner than hold.gap_s after it; spawn_gap_add_s more between a wave's flights while a player's that hot
    --          (0: none); hold.tactics: no new cover, trap or bracket on a player above `high`
    --   level  the difficulty spikes (CFG.spikes) are the ceiling: the room above `high` for level.down_after_s of a
    --          fight, enemies that come from then fly one spike level lower (fire control, pilot rank, provoke, the next
    --          round's aircraft_add; post-stall as each spawned; the skill tiers stay the floor: CFG.tiers' fcs, rank),
    --          at most level.max_drop under the round's spike; below level.up_below for level.up_after_s, a level back;
    --          level.gap_s between two changes; level.pressure: the game's attack throttle (CFG.late.pressure's preset)
    --          a letter gentler too, never under level.pressure_min. A joiner's copies fly the host's level ("rnd")
    -- log_s: with CFG.log.verbose, a line with your scores every log_s seconds of a fight (0: decisions only; the
    -- round's summary either way). Nothing new in a round of skip_specials (their own scripts run the fight).
    -- enabled = false (or a lever's): as before P4. Untested in game.
    intensity = {
        enabled = true, window_s = 30, smooth_x = 0.35, high = 80, low = 35, calm_s = 20, log_s = 10,
        skip_specials = { "anomaly", "glitch", "valka", "ladon", "alicorn" },
        score = { damage = 40, missiles = 25, near = 20, health = 15, dmg_full = 0.4, msl_km = 4.0, msl_full = 2,
                  near_km = 5.0, near_full = 4 },
        comfort = { tail = 40, kills = 35, healthy = 25, high = 60, tail_km = 3.0, tail_deg = 70, tail_full = 0.5,
                    kpm_full = 2.0, kills_window_s = 60, hp_pct = 70 },
        push = { enabled = true, from_round = 3, per_round = 2, cooldown_s = 40, range_km = 8.0 },
        hold = { enabled = true, after_s = 3, secs = { 15, 20 }, gap_s = 20, per_wave = 1, tactics = true, spawn_gap_add_s = 3 },
        level = { enabled = true, max_drop = 1, down_after_s = 30, up_below = 50, up_after_s = 60, gap_s = 45,
                  pressure = true, pressure_min = "B" },
    },
    -- Post-stall manoeuvres (Pugachev's cobra, kulbit): every stock behaviour gates them on the plane's
    -- bCanManeuverPugachevsCobra / bCanManeuverKulbit; on each enemy that appears both are turned off unless its
    -- model is listed here (the code in its blueprint name, BP_OPnnnn_<code>_...: thrust-vectoring and Flanker-family
    -- airframes; those keep their blueprint's own, e.g. su33 cobra but no kulbit), so early fighters never post-stall.
    maneuvers = { enabled = true, post_stall = { "su33", "su35", "su37", "su47", "su57", "f22a",
                                                 "f04e",              -- (f04e: only the Anomaly's flies one)
                                                 "adfx02", "typn", "rflm" } },   -- (the Reaper squadron's, 2026-10-23)
    -- Airfield and bombers (Milestone 3; tools/survival_events.py AIRFIELD_* / BOMBERS, tools/re/AIRFIELD_SUPPLY.md).
    -- The airfield starts at `hp`; every enemy weapon that reaches one of its 4 target points (the event package
    -- counts them in SV_AirHits) takes hit_damage. At 0 it is down: landing closes (no rearming) until the end of the
    -- round after, then it reopens at repair_hp. Bomber flights (2 aircraft, Mission 22's airport strike: they only
    -- go for the airfield) join rounds from bombers.from_round, one more flight every `every` rounds, up to `max`;
    -- Tu-95s and Tu-160s (`heavy`) from heavy_from_round. bombers.pool must match survival_events.BOMBERS.
    -- hp 250 / repair_hp 125 (user, 2026-10-23: "buff the airbase health"; at 100 a bomber raid took it from full to
    -- down in about 45 s in rounds 7 and 9 of that day's test); the STORE's repairs restore 60 (were 25).
    -- hit_damage 3, bomb_damage 10 (were 4 and 12; economy review of 2026-10-25: a friend's airfield went down in rounds
    -- 8, 12, 19 and 21 with 6 AA guns and 2 SAM sites up: "the airfield should fall only when a raid is ignored")
    airfield = {
        enabled    = true,
        hp         = 250,
        hit_damage = 3,
        repair_hp  = 125,
        bombers = {
            -- Bomber raids (user, 2026-10-22: "in bomber rounds bombers primarily spawn"): from first_raid, every
            -- raid_every rounds; raid_share of that round's aircraft are bombers (squadrons of 2, 4, 6 by the same
            -- from_round rule), at most max_bombers, the rest fighter escort. Other rounds have no bombers.
            -- raid_share 0.5 and max_bombers 12 (were 0.65 and no cap: 18 bombers from round 12, economy review)
            first_raid = 3, raid_every = 3, raid_share = 0.5, max_bombers = 12,
            -- a raid you can see coming (economy review: "a 60-second warning with the raid on the map"): every bomber
            -- flight of a raid comes from one direction (within spread_deg of it), called out with the compass point when
            -- the round starts, and on the HUD while bombers are up
            one_bearing = true, spread_deg = 25, warn = true,
            -- flight sizes; must match tools/survival_events.py BOMBER_SIZES (EB_Unit_01_Air0 too)
            sizes = { ERB_Unit_01_Air2 = 4, EA_Unit_01_Air0 = 2, EA_Unit_01_Air1 = 2, EA_Unit_01_Air2 = 4, EB_Unit_01_Air0 = 6 },
            aircraft = { "su34_common", "f15e_common" },
            heavy = { "tu95_common", "t160_common" },
            heavy_from_round = 3,               -- heavy flights can come in every bomber round
            distance_km = { 28, 36 },
            -- Strike aircraft come in low, as Mission 22's Su-34s do (600 m): from 1.7 km the F-15Es flipped between
            -- PursueTarget on the airfield and ReturnToWorld and never fired (AI watch, 2026-10-22).
            altitude_m = { 1500, 3000 },        -- heavies
            strike_altitude_m = { 500, 900 },
            pool = { "ERB_Unit_01_Air2", "EA_Unit_01_Air0", "EA_Unit_01_Air1", "EA_Unit_01_Air2", "EB_Unit_01_Air0" },
            -- the flights built with large-aircraft behaviour (survival_events.HEAVY_BOMBERS): they fly the heavies,
            -- the others the strike aircraft
            heavy_units = { "EA_Unit_01_Air1", "EA_Unit_01_Air2" },
            -- Heavies never bomb on their own (no stock mission lets them): when one is within drop_km of the runway
            -- its flight's bomb run is fired (RE_SV_BombRun_NN: both aircraft drop 6 bombs), at most once every
            -- run_cooldown_s, and bomb_damage is taken off the airfield damage_delay_s later (as the bombs land).
            -- drop_km 3 (was 1.5: the Tu-160s of the test of 2026-10-22 never came that close); every heavy's distance
            -- is logged every 30 s ("bombers:"; 10 s with [log] verbose).
            -- heavy_route: a heavy flight's lead flies a route in from its side, over the runway, then a figure-8 that
            -- crosses it twice a lap (sv_flights.lua HEAVY; tools/survival_events.py HEAVY_*), route_delay_s after it
            -- appears (user, 2026-10-29: "tu-95's aren't attacking the base, they fly around nearby and do nothing":
            -- with their area over the runway they circled 6-8 km out). false: no path (they circle again).
            drop_km = 3.0, run_cooldown_s = 20, bomb_damage = 10, damage_delay_s = 5, heavy_route = true, route_delay_s = 3,
            -- the minimap's alert (user, 2026-10-31: "an alert that pings the aircraft via the minimap that are attacking
            -- the airfield"): each bomber flight heading for the airfield is pinged on the radar every every_s while one of
            -- its aircraft is within within_km of it (the game's own "look here" ping on its unit, four ripples)
            ping = { enabled = true, every_s = 12, within_km = 40 },
        },
    },
    -- Credits (Milestone 4): earned for every enemy aircraft that goes down (by its flight: bomber flights pay
    -- bomber / heavy, the rest fighter; `models` is only used when a plane's flight can't be read), times tier_pay of
    -- the enemy's skill tier (CFG.tiers.list order: Rookie x1.0 ... Reaper x2.0), and for every round cleared
    -- (round_bonus x the round), spent in the STORE. Economy check of 2026-10-23 (user: "edit the rewards and check the
    -- economy again"): with flat kill pay and round_bonus 50, ordinary rounds about broke even on ammo and repairs
    -- from round 8 and lost money from 16 (the enemies take more missiles a kill, the pay stayed 100), so allies at
    -- 15000-20000 were out of reach. Now (model): ~18000 by round 10, ~64000 by 20, ~156000 by 30.
    -- special_x (user, 2026-10-23: "Special Rounds should pay out larger amounts, as should their enemies"): every
    -- kill in a special round (aircraft, landing craft, troop vehicles, the Alicorn's ballast tanks) pays x this
    -- (1.5 in 0.49.3, then "buff the special round eco more": 2, and the specials' own rewards twice 0.49.2's).
    -- Economy review of 2026-10-25 (a friend's 3-hour run: special rounds paid 4-10 times more a minute than normal ones):
    -- round_bonus 250 (was 100), and every kill pays x (1 + round_x_per_round x (round - 1)), at most round_x_max. A kill
    -- an ally, an allied ship or an airfield defence made (CFG.allies.kills) pays ally_x of it, an airstrike's
    -- airstrike_x ((0.73.78, economy C4, approved 2026-11-03) 0.25, was 0.5: an airstrike paid for itself).
    credits = {
        start = 0, fighter = 100, bomber = 200, heavy = 400, round_bonus = 250, special_x = 2.0,
        round_x_per_round = 0.02, round_x_max = 1.5, ally_x = 0.5, airstrike_x = 0.25,
        -- special_split (0.73.78, economy C3, approved 2026-11-03): in co-op a special's reward (a boss down, the Alicorn
        -- sunk, the shuttle launched, the spaceport held or retaken, and what a special pays as it goes: landing craft,
        -- the fleet, ballast tanks, rockets ...; not the round bonus, not kills) pays each player the reward x players ^
        -- -special_split (sv_coop.lua COOP.specialShare, the host's setting): 0.5 = 1 / sqrt(players), 71 % with 2, 58 %
        -- with 3, 50 % with 4, 45 % with 5; 0 the whole reward to everyone (before 0.73.78), 1 an equal split. Solo: x1.
        special_split = 0.5,
        -- team_x (0.73.77, economy C1, approved 2026-11-03): in co-op a teammate's kill (the player the host names for it,
        -- sv_coop.lua) pays min(team_x, 1 / (players - 1)) of a kill on every game, your own x1: 0.5 with 2 or 3
        -- players, 0.33 with 4, 0.25 with 5 (the host's setting). Before, a joiner was paid x1 for every kill it saw.
        team_x = 0.5,
        tier_pay = { 1.0, 1.1, 1.25, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0 },
        models = { su34 = "bomber", tu95 = "heavy", t160 = "heavy" },
    },
    -- The airfield shop: rows on the landing menu (the in-game hangar's list, under Yes / No), added while Survival's
    -- level is loaded. Landing rearms nothing (user, 2026-10-22: "landing at the airfield is still refilling your ammo
    -- regardless of buying it"): the ammo you fly with is what you took off with, less what you fired, plus what you
    -- bought (kind: 1 missiles, 2 special weapons, 4 flares; up to the aircraft's full load), or the shop repairs the
    -- airfield. Every purchase of an item makes its next one `raise` times dearer (1: the same price every time).
    -- The item names must match tools/build_survival.py SHOP_ITEMS.
    shop = {
        enabled = true,
        -- the beep on every STORE press (Wwise events of the always-loaded game-SE bank): bought, or nothing bought
        sounds  = { bought = "AKE_GEN_UI_INGAME_BaseResupply_Decide_Play", refused = "AKE_GEN_UI_OUTGAME_General_Reject_Play" },
        items = {
            -- ammo is used up now (no free rearm), so a pack costs the same every time: 25 Z a missile against 100 Z a
            -- fighter (about two missiles a kill), 100 Z a special weapon round, 75 Z a flare
            Missiles = { kind = 1, step = 12, price = 300, raise = 1.0, label = "MISSILES", what = "missiles" },
            Special  = { kind = 2, step = 4, price = 400, raise = 1.0, label = "SPECIAL WEAPON", what = "special weapon rounds" },
            Flares   = { kind = 4, step = 2, price = 150, raise = 1.0, label = "FLARES", what = "flares" },
            -- The landing menu has room for 4 shop rows (its list holds 6, 2 are stock), so this one does three jobs in
            -- turn: it repairs your aircraft while it's damaged (user, 2026-10-22: "add the ability to buy repairs for
            -- your aircraft"; `aircraft`: the stock full repair, price x the damage, at least min_price), then the
            -- airfield while that's damaged, then builds its defences (user: "purchase AA guns ... or SAM sites. Make
            -- them expensive"): Mission 22's airport AA guns and SAM sites, one unit each (tools/survival_events.py
            -- DEFENCES), built in `order`; a destroyed one can be built again. Each kind's price rises `raise` times.
            -- The STORE's own rows (user, 2026-10-23: "a special tab ... for the store items with their own icons";
            -- tools/re/AIRFIELD_SHOP_UI.md): one per job on its two pages, SUPPLIES (missiles, special weapon, flares,
            -- aircraft repair) and AIRFIELD (airfield repair, AA gun, SAM site; from 0.72.1 the AA gun, SAM site and CIWS
            -- on a DEFENCES page of their own). Without the STORE pages the four rows above stand in, with Airfield
            -- doing three jobs in turn.
            RepairAircraft = { role = "aircraft", label = "REPAIR AIRCRAFT", price = 600, min_price = 100, raise = 1.0 },
            -- (raise 1.0, was 1.25: airfield repairs are upkeep every raid, and 1.25 compounding made the 20th one 21700)
            RepairAirfield = { role = "airfield", label = "REPAIR AIRFIELD", repair = 60, price = 300, raise = 1.0 },
            -- co-op: a player who's down bought back (user, 2026-10-29: "someone could land at the airfield and buy you
            -- back"; Scripts/sv_down.lua: its label, price and refusals; prices: coop.revive)
            Revive         = { role = "revive", label = "REVIVE" },
            AAGun          = { role = "aa",  label = "BUILD AA GUN" },          -- (prices: Airfield.defences)
            SAM            = { role = "sam", label = "BUILD SAM SITE" },
            -- (user, 2026-10-29: "Add CIWS that can be purchased and placed around the airfield"; on the STORE's
            -- DEFENCES page with the AA guns and SAM sites)
            Ciws           = { role = "ciws", label = "BUILD CIWS" },
            -- Allies (CFG.allies; user, 2026-10-23: "make it so that these Allied Aircraft and Ships are expensive"):
            -- MOONCHILD on the AIRFIELD page, the ships on the DOCKS page; each purchase of one makes the next dearer
            Moonchild      = { role = "ally_air", ally = "moonchild", label = "MOONCHILD: 2 x F-22", price = 15000, raise = 1.25 },
            ShipAegis      = { role = "ally_ship", ship = "Aegis", label = "AEGIS DESTROYER", price = 20000, raise = 1.25 },
            -- Economy review of 2026-10-25 (tools/build_survival.py STORE_PAGES puts them on the STORE's pages):
            -- FULL REARM: everything missing up to the full load in one press, priced per round as the packs are
            -- ("100 separate MISSILES purchases over the run"): per missile, special weapon round and flare
            Rearm      = { role = "rearm", label = "FULL REARM", missile = 25, special = 100, flare = 75 },
            -- upgrades for the rest of the run, bought once a tier ("lasting upgrades as the late-game sink"): `tiers`
            -- their prices, `step` what each tier adds: AIRFRAME your aircraft's health (+25 %), WEAPON BAYS what it
            -- carries of missiles and special weapons (+50 % of its own full load), GUN its gun's damage (+15 %), FLARE
            -- PODS its flares (+2)
            UpAirframe = { role = "upgrade", up = "airframe", label = "AIRFRAME", tiers = { 5000, 9000, 14000 }, step = 0.25 },
            UpBays     = { role = "upgrade", up = "bays", label = "WEAPON BAYS", tiers = { 4000, 8000 }, step = 0.5 },
            UpGun      = { role = "upgrade", up = "gun", label = "GUN", tiers = { 4000, 7000, 11000 }, step = 0.15 },
            UpFlares   = { role = "upgrade", up = "flares", label = "FLARE PODS", tiers = { 2500, 4500, 7000 }, step = 2 },
            -- tactical items, carried until used, at most `max` of each (CFG.tactical: how they work).
            -- price_per_round ((0.73.78, economy C4 / C5, approved 2026-11-03; any item with a price can have one): the
            -- price is price + price_per_round x the round (the round in play, in a break the next one), then x raise for
            -- each bought: AIRSTRIKE 4000 + 300 a round (5500 at round 5, 10000 at 20, 17500 at 45; was 6000 flat), ECM
            -- BURST and DECOY 2500 + 200 a round (3500 at 5, 6500 at 20, 11500 at 45; were 4000 flat)
            Airstrike  = { role = "tactical", tac = "airstrike", label = "AIRSTRIKE", price = 4000, price_per_round = 300, raise = 1.0, max = 2 },
            Ecm        = { role = "tactical", tac = "ecm", label = "ECM BURST", price = 2500, price_per_round = 200, raise = 1.0, max = 2 },
            Decoy      = { role = "tactical", tac = "decoy", label = "DECOY", price = 2500, price_per_round = 200, raise = 1.0, max = 2 },
            -- one shoot-down survived (CFG.insurance), one held at a time ("insurance as a high-end purchase")
            Insurance  = { role = "insurance", label = "SECOND CHANCE", price = 50000, raise = 1.0 },
            -- a cheaper first rung of allies ("a pair of F-16s for about 5,000 before MOONCHILD at 15,000"): flies on
            -- MOONCHILD's two flights (CFG.allies.wingmen), so at most two flights of the two kinds are up together
            Wingmen    = { role = "ally_air", ally = "wingmen", label = "SNIPER: 2 x F-16C, LAAMs", price = 5000, raise = 1.2 },
            -- VOID WATCHER 1 (CFG.allies.awacs): an E-767 AWACS that takes off from the airfield and orbits it, its ESM
            -- field over the whole airfield; one up at a time. ((0.73.78, plan G5) raise 1.0 -> 1.25, as MOONCHILD's and the
            -- AEGIS's: each purchase in the run x1.25 dearer, a co-op room's counted together, a joiner's checked by the
            -- host at the host's price: sv_shop.lua shopBuildFor)
            VoidWatcher = { role = "ally_awacs", label = "VOID WATCHER 1: E-767 AWACS", price = 12000, raise = 1.25 },
            -- VAMPIRES, the ZFA-44 carriers (CFG.allies.carrier, Scripts/sv_escort.lua; named by the user, 2026-11-07): only once THE ESCORT is won; at most two out;
            -- a co-op room's purchases counted together, a joiner's built by the host. No row of its own on the STORE's
            -- pages yet: it shares CFG.allies.carrier.store_row (row_label on that row)
            ZfaCarrier = { role = "ally_carrier", label = "VAMPIRES", row_label = "VAMPIRES", price = 15000,
                           raise = 1.0 },
            -- the allied aircraft's orders (CFG.allies.orders), free: each press the next one
            Orders     = { role = "orders", label = "ALLY ORDERS" },
            -- (defences' raise 1.12, was 1.25: "the sixth AA gun cost 12,210, three times the first")
            Airfield = { role = "combined", repair = 60, price = 300, raise = 1.0, label = "REPAIR AIRFIELD",
                         defences = {
                             order = { "aa", "aa", "sam", "ciws", "aa", "aa", "sam", "ciws", "aa", "ciws", "ciws" },
                             -- health_add: HP on each one's own (user, 2026-10-29: "make Allied SAMs and Anti Air Guns
                             -- more effective ... increase their abilities"; the game's 20 went to one missile): its
                             -- DT_SV_NpcRows row's MaxHealthDifference
                             aa  = { label = "AA GUN", what = "an AA gun", price = 4000, raise = 1.12, health_add = 40,
                                     units = { "SV_Unit_AAGun_A", "SV_Unit_AAGun_B", "SV_Unit_AAGun_C", "SV_Unit_AAGun_D",
                                               "SV_Unit_AAGun_E" } },
                             sam = { label = "SAM SITE", what = "a SAM site", price = 8000, raise = 1.12, health_add = 40,
                                     units = { "SV_Unit_SAM_A", "SV_Unit_SAM_B" } },
                             -- the CIWS (tools/survival_events.py DEFENCE_CIWS: the game's land Phalanx, four fixed spots by
                             -- the runway's ends): fcs_row, the fire control its gun gets (the ships' Mk 15's, boosted as
                             -- the others are below; "none": the blueprint's own, 2500 m, not boosted)
                             ciws = { label = "CIWS", what = "a CIWS", price = 6000, raise = 1.12, health_add = 40,
                                      fcs_row = "NPC_FCS_VesselCIWS000",
                                      units = { "SV_Unit_Ciws_A", "SV_Unit_Ciws_B", "SV_Unit_Ciws_C", "SV_Unit_Ciws_D" } },
                             -- their fire control (user, 2026-10-23: "increase the fire rate of the Airfield"): the
                             -- allies' (CFG.allies.fcs: x0.5 times, x1.5 cone), then arming / lock x lock_x and time
                             -- between shots / rest x fire_x (0.5: twice as often again, 4x the stock rate). User,
                             -- 2026-10-29 ("increase their lock on range, also increase the lifetime of the missile they
                             -- fire"): lock-on range x range_x of the stock (in place of the allies' 1.6); search_m, the
                             -- farthest they see anything (a copy of NPC_AIModule_Turret000, 6000 m: NPC_AIModule_SV_Defence),
                             -- not lost in cloud; turret slewing x slew_x; yaw_full: all the way round (the CIWS's
                             -- fire control is a ship mount's, +-60 deg); round_reach: a gun's rounds reach the new
                             -- range (the AA guns' flak only hurts within its 2000 m damage area, round_width_x as wide;
                             -- the CIWS's rounds fly 3 s, longer by the range's growth); missile: the SAM's own
                             -- (SAM_Ground_000: 7.3 s from 500 km/h, +300 km/h a second to 3000, turning 15, about 3.2
                             -- km of flight, so the 4.8 km lock-on fell short), as the Aegis's (CFG.allies.ships)
                             -- (user, 2026-10-31: "increase the lock on and firing distance of all SAM sites and Ships": the
                             -- SAM sites' missiles 8 -> 20 km and 14 -> 30 s, the defences' search 10 -> 25 km)
                             fcs = { lock_x = 0.75, fire_x = 0.5, range_x = 2.0, search_m = 25000, slew_x = 2.0, yaw_full = true,
                                     round_reach = true, round_width_x = 1.5,
                                     -- (salvo_x: less waiting between the SAM sites' shots and salvos, x0.8; salvo_n missiles a
                                     -- salvo, salvo_gap_s apart (the game's: 1); 2026-10-31: "increase missile salvos")
                                     missile = { range_m = 20000, life_s = 30, accel_x = 2.0, speed_max_kmph = 3600, turn_x = 1.5,
                                                 salvo_x = 0.8, salvo_n = 3, salvo_gap_s = 0.5 } },
                         } },
        },
    },
    -- Allies the STORE sells (user, 2026-10-23; tools/survival_events.py ALLY_*): MOONCHILD, two-ships of F-22s that
    -- take off from the airfield once you're airborne (up to two flights at once, takeoff_gap_s apart: both park on one
    -- spot), and allied ships sailing lanes south and north of the airfield (four Aegis destroyers, one per lane; the
    -- LCS Freedom is gone, user 2026-10-23). They fight until shot down or sunk; a lost one can be bought again. Every
    -- weapon they carry gets fire control of its own (rows <FCS>_SVA, made at the main menu): lock-on range x range_x,
    -- its cone x angle_x, arming, lock, aim and reload times x time_x, gun spread x spread_x. A ship type's own `fcs`
    -- goes further (rows <FCS>_SVA_<key>): arming and lock x lock_x, time between shots and rest x fire_x (user,
    -- 2026-10-23: "make the Aegis Lock On faster and Fire Rate increase"), and range_x in place of the allies' (user:
    -- the Aegis locks on and fires from 2x the stock range). Enemies go for them: once MOONCHILD is airborne hunt_share of the enemy fighter
    -- flights prefer it to you, and while ships are at sea strike_share of a normal round's aircraft (no specials, no
    -- raids) are strike flights sent at one of them.
    allies = {
        enabled      = true,
        hunt_share   = 0.35,                     -- (0.5 until 0.48.5: MOONCHILD was swarmed in 2 minutes)
        -- at least hunters flights of a round go for the allied aircraft while they fly (economy review of 2026-10-25:
        -- "hunter pairs that go for allies")
        hunters      = 1,
        -- strike_share 0.15 (was 0.25), only every ship_strike_every rounds (economy review: "an Aegis destroyer died
        -- 13.6 min after sailing")
        strike_share = 0.15,
        ship_strike_every = 2,
        -- between rounds every allied aircraft, ship and airfield defence still up is repaired to full (economy review:
        -- "allies who last ... rearm and repair between rounds while they live"); their weapons never run dry
        -- (magazine_min rounds on every allied fire control)
        repair       = true,
        magazine_min = 999,
        -- what they did (economy review: "show what allies do"): each enemy's damage by attacker is read while it flies
        -- (its DamageHistoryMap); one you never hit that an ally, an allied ship or an airfield defence did is theirs
        kills        = true,
        -- the allied aircraft's orders (the STORE's ALLY ORDERS row, Ctrl+F4 in flight): hunt (anywhere, the default),
        -- cover (their area kept within cover_radius_m of you, moved every cover_every_s) or defend (their area on the
        -- airfield, defend_radius_m)
        orders       = { default = "hunt", list = { "hunt", "cover", "defend" }, cover_every_s = 6, cover_radius_m = 5000,
                         defend_radius_m = 8000, key = true },
        -- gun_lead_s / burst_x: MOONCHILD's guns aim gun_lead_s ahead (PredictionOffsetTime; stock aircraft guns 0)
        -- and fire bursts burst_x as long (stock 10 rounds); aa_lead_x: the ships' and the airfield's AA guns and CIWS
        -- lead that much further (stock AA guns 0.8 s; user, 2026-10-24: "increase the gun lead for the allied
        -- fighters too, and their bursts, increase the gun lead for allied AA guns too")
        fcs          = { range_x = 1.6, angle_x = 1.5, time_x = 0.5, spread_x = 0.4, gun_lead_s = 1.0, burst_x = 3,
                         aa_lead_x = 1.5 },
        aircraft     = { name = "MOONCHILD", name_key = "SV_Moonchild", takeoff_gap_s = 45,
                         units = { "SV_Unit_MoonchildA", "SV_Unit_MoonchildB" },
                         -- scaling with the enemy (user, 2026-10-23: "buff the allied F-22's so they scale up with the
                         -- enemy"), set as each one is seen up and again every round while it flies: PilotRank the
                         -- round's skill tier's + rank_add (at least rank_min, at most 5; not lowered on Casual), AI level
                         -- the tier's (at least ai_level_min; set before each takeoff), health x health_x x (1 +
                         -- health_per_round x (round - 1)), at most health_max_x. (Test of 2026-10-23: a 15000 Z flight
                         -- bought in round 9 was gone 112 s after takeoff.)
                         scale = { rank_add = 1, rank_min = 3, ai_level_min = 3, health_x = 2.0, health_per_round = 0.08,
                                   health_max_x = 4.5 } },
        -- WINGMEN (the STORE's cheaper allies): two F-16Cs on MOONCHILD's flights (its world-data units, the airframe
        -- changed before takeoff: SV_SetAircraft, tools/build_survival.py's sv_ally_wingmen row), flying as MOONCHILD
        -- does but scaled less. Squadron SNIPER (was VIPER; user, 2026-10-31: "rename VIPER to SNIPER and change their
        -- standard missiles to LAAM's"): their row (Survival's copy of the F-16C's) carries the game's AI LAAM where the
        -- stock row has its standard missile, written at build time (tools/survival_events.py ALLY_WINGMEN_MISSILE),
        -- then boosted as every allied weapon (CFG.allies.fcs)
        wingmen      = { name = "SNIPER", name_key = "SV_Wingmen", row = "sv_ally_wingmen", moonchild_row = "sv_ally_moonchild",
                         scale = { rank_add = 0, rank_min = 2, ai_level_min = 2, health_x = 1.5, health_per_round = 0.05,
                                   health_max_x = 3.0 } },
        -- VOID WATCHER 1 (user, 2026-10-31: "Take off from the airfield as a purchasable ally", "Rename it too VOID
        -- WATCHER 1", "give it's ESM a huge boost in range and have it orbit around the airfield"): Mission 28's E-767
        -- AWACS Magnolia (tools/survival_events.py AWACS_*: its own world-data unit on the E-767's row, MOONCHILD's lead's
        -- parking spot and scramble, then an orbit 6 km round the airfield, 4.5 km up (0.73.73: SA's "a circle with a
        -- 5-7 kilometer radius"; tools/survival_events.py awacs_orbit: a path again, its lead-in started where the
        -- climb-out leaves it); it never fights, enemies may
        -- hunt it). Its ESM (BP_wp_esm_MS28, a LiveElectronicSupportMeasures field round it; the AI never switches it on
        -- by itself) is fired every esm.every_s while it's airborne (RE_SV_AwacsEsm), each field set to esm.range_m
        -- (stock 3.2 km) for esm.life_s; its fire control's reach esm.capture_m. scale: as MOONCHILD's (health only:
        -- it has no weapons).
        -- (back on in 0.73.60, user 2026-11-01: "turn the Ladon's back on as well as VOID WATCHER" to test them)
        -- enabled = false (hotfix4, user 2026-11-01): not sold (the STORE shows it NOT AVAILABLE) until its orbit is
        -- fixed in a build: the host's run of 2026-10-31 saw it fly straight out to 163 km, RE_SV_AwacsOrbit no help
        awacs        = { enabled = true, name = "VOID WATCHER 1", name_key = "SV_VoidWatcher", unit = "SV_Unit_VoidWatcher",
                         row = "SV_Ally_VoidWatcher",
                         -- its model row (tools/build_survival.py: Magnolia's under the game's plain E-767 name), added
                         -- to the campaign's DT_NPC_Model at the main menu (no "MAGNOLIA" on its box)
                         model = "SV_Model_VoidWatcher",
                         -- ((0.73.78, plan G5: "its field 8-10 km, over the airfield and not the whole map") range_m
                         -- 25000 -> 9000: its orbit is 6 km round the airfield, so a 9 km field always holds the whole
                         -- airfield with 3 km to spare past it, and reaches 15 km out at most (25 km covered the fight);
                         -- the stock field's 8 km support / 4 km effect. every_s 20 -> 30, life_s 24 -> 15: a 24 s field
                         -- every 20 s never went off; now it's up half the time, a pulse every 30 s)
                         esm = { event = "RE_SV_AwacsEsm", every_s = 30, range_m = 9000, life_s = 15, capture_m = 60000,
                                 class = "BP_wp_esm_MS28_C" },
                         -- ((0.73.78, plan G5: "3 rounds of service") it serves `rounds` rounds, one counted as it clears
                         -- with VOID WATCHER 1 up min_s or more of it, then goes home in the break: no landing an AI plane
                         -- can fly (tools/survival_events.py AWACS_OUT_*), so the end of the arc it's on starts its exit
                         -- (home.event, RE_SV_AwacsHome) and it's taken off (home.remove, RE_SV_AwacsRemove, then
                         -- SV_Recycle) gone_km from the airfield, at the exit's end, or max_s after it was sent home
                         -- (area_s when the backstop's area orbit had it: no arc's end to leave from). No ESM, no backstop,
                         -- no hunters and no strike flight once it's going home; the STORE sells another then.
                         -- rounds = 0: it serves until it's shot down, as before)
                         service = { rounds = 3, min_s = 60 },
                         home = { event = "RE_SV_AwacsHome", remove = "RE_SV_AwacsRemove", gone_km = 20, max_s = 360,
                                  area_s = 30 },
                         -- ((0.73.78, plan G5: "a strike flight after it") each round it's up and airborne, from
                         -- from_round, one of the round's fighter flights up after_s or more (not an ace squadron's, a
                         -- role flight that keeps its own set, a Wolf, an escort, the jammer's, nor one held or decoyed)
                         -- is sent after it: each plane's EngagementOrderOverride onto it (Normal, TargetFirst, as co-op's
                         -- huntReal sends flights onto a player's real plane: hard rule 53), given again every again_s,
                         -- back on you (PlayerOnlyNoLimit) once it's lost or going home. enabled = false: none, as before)
                         strike = { enabled = true, from_round = 1, after_s = 4, again_s = 15 },
                         -- its orbit's backstop (user, 2026-10-31: "VOID WATCHER just seems to not loiter around the
                         -- airfield space"): put on its orbit (RE_SV_AwacsOrbit) when its climb-out hasn't ended
                         -- climb_s after takeoff, and again when it's lost_km or more from the airfield (checked every
                         -- check_s, at most every again_s). (0.73.73) RE_SV_AwacsOrbit takes it off its path onto the
                         -- area orbit round the airport (0.73.62-0.73.72's); lost_km 18 -> 10 (its orbit 6 km out, its
                         -- lead-in inside it), check_s 20 -> 10
                         orbit = { event = "RE_SV_AwacsOrbit", climb_s = 60, lost_km = 10, check_s = 10, again_s = 60 },
                         scale = { rank_add = 0, rank_min = 3, ai_level_min = 3, health_x = 3.0, health_per_round = 0.08,
                                   health_max_x = 6.0 } },
        -- The ZFA-44 carriers (Scripts/sv_escort.lua, tools/re/ESCORT.md; user, 2026-11-06), the escort's reward: once
        -- CHARLENE and her escorts are down (the room's in co-op, for the rest of the run), the STORE (CFG.shop.items.
        -- ZfaCarrier) sends one of Mission 17's cargo ships (allied: units, one per spot at sea off the airfield), at most
        -- max_up at once, each serving service.rounds rounds (a round counted as it clears with the ship up min_s or more
        -- of it, VOID WATCHER 1's way), then leaving (taken off). Each launches a flight of ZFA-44s first_s after it's on
        -- station and again relaunch_s after that flight is down. launch "container": from its own container launchers
        -- as Mission 17's drones (launchers: each ship's launcher arms in turn, { record = its fire record, unit = the
        -- world-data unit that arm launches }; a unit launched before is taken off the spawner's list first, hard rule
        -- 16); a ship whose launch record fired but no plane of it came within launch_wait_s launches by "pose" from then
        -- on: its pose_units flight spawned ahead_m off its bow, alt_m up (as the ALICORN's deck). A plane is the ship's
        -- when it appears within capture_km of it. zfa: the ZFA-44's look on every plane of those flights, on every game
        -- (Scripts/sv_zfa44.lua ZFA.dress: the user's dev builds with SurvivalMode_ZFA44_P; without it the host airframe
        -- flies as it is), paint its variant (3: the gear instance with a flat normal, the Falken's and VALKA's paint 16,
        -- the route proven to draw), hide_s how often the host's own meshes are hidden again. store_row: a STORE row it
        -- shares while it's unlocked and that row has nothing to sell ("Revive": the AIRFIELD page's revive row when
        -- nobody's down; "none": only a ZfaCarrier row of its own). remove_records: each ship taken off by its own
        -- RE_SV_CargoRemove_<n> too (Mission 22's despawn). ship_at: where each ship is when its hull isn't found (cm: its
        -- world-data spot, tools/survival_events.py CARGO_SHIPS: 7.4 km NW and 7.5 km SE of the runway; not "spots", which
        -- tools/survival_events.py build_valka reads as VALKA's).
        -- (2026-11-07, the build's names: tools/re/ESCORT.md "Build names") launchers: ship 1 fires only its launcher
        -- BP_VE021_ctslf_cntus_01_CP, ship 2 only its _03, arm n (WN_WEAPON_n) by RE_SV_CargoLaunch_<s>_<n>, which spawns
        -- the world-data unit that arm names (2 ZFA-44s on sv_zfa_drone; an arm fired again only once its unit is off the
        -- spawner's list: hard rule 16); pose_go: each pose flight's orders after its SV_Spawn (gear up, Normal, air
        -- search: its appearance's, which a spawn in the landing menu never fires). dt_npc: the ZFA-44 host's DT_NPC row
        -- (DT_SV_NpcRows' Su-47 copy, added at the main menu by ESC.setup): without it no carrier is sold
        -- ((2026-11-07) the user: "why not just swap the drone model that launches originally with the ZFA-44 model", "i
        -- know for a fact that there was some launch smoke and VFX", "the drones seem to just fly the same path together")
        -- the arms' planes fly Mission 16's allied container drone (dt_npc_drone: its launch smoke and wing animation, the
        -- ZFA-44 dressed on it; the pose flights keep dt_npc's Su-47), parked in the ship until their arm's record opens the
        -- container, fires it and closes it (Mission 17's way). A plane of theirs seen out of it (above rise_m, within
        -- capture_km of the ship, parked below parked_m before or new since the record) fires its arm's `climb` record:
        -- each its own climb-out path, then their orders (Scripts/sv_escort_laser.lua ZLAUNCH). None out in launch_wait_s:
        -- the climb-out fired anyway while any of the arm's planes is alive, else by pose
        carrier      = { enabled = true, name = "ZFA-44 CARRIER", name_key = "SV_Cargo", max_up = 2,
                         units = { "SV_Unit_Cargo1", "SV_Unit_Cargo2" }, dt_npc = "SV_Zfa_Ally", dt_npc_drone = "SV_Zfa_Drone",
                         launch = "container", first_s = 20, relaunch_s = 30, launch_wait_s = 15, capture_km = 4,
                         rise_m = -50, parked_m = -100,
                         -- ((2026-11-07) "there was no launch smoke": the drone's own, put on each one out of its container)
                         launch_fx = "/Game/VFX/Vehicles/Aircraft/OP/OP0018/NS_UAVLaunch001", launch_fx_s = 4,
                         watch_at = { 1, 3, 6, 10, 15 },
                         launchers = {
                             { { record = "RE_SV_CargoLaunch_1_1", climb = "RE_SV_ZfaClimb_1_1", unit = "E_Unit_01_drone_5_0" },
                               { record = "RE_SV_CargoLaunch_1_2", climb = "RE_SV_ZfaClimb_1_2", unit = "E_Unit_01_drone_4_0" },
                               { record = "RE_SV_CargoLaunch_1_3", climb = "RE_SV_ZfaClimb_1_3", unit = "E_Unit_01_drone_0_0" },
                               { record = "RE_SV_CargoLaunch_1_4", climb = "RE_SV_ZfaClimb_1_4", unit = "E_Unit_01_drone_1_0" },
                               { record = "RE_SV_CargoLaunch_1_5", climb = "RE_SV_ZfaClimb_1_5", unit = "E_Unit_01_drone_7_0" },
                               { record = "RE_SV_CargoLaunch_1_6", climb = "RE_SV_ZfaClimb_1_6", unit = "E_Unit_01_drone_8_0" } },
                             { { record = "RE_SV_CargoLaunch_2_1", climb = "RE_SV_ZfaClimb_2_1", unit = "E_Unit_01_drone_3_1" },
                               { record = "RE_SV_CargoLaunch_2_2", climb = "RE_SV_ZfaClimb_2_2", unit = "E_Unit_01_drone_4_1" },
                               { record = "RE_SV_CargoLaunch_2_3", climb = "RE_SV_ZfaClimb_2_3", unit = "E_Unit_01_drone_1_1" },
                               { record = "RE_SV_CargoLaunch_2_4", climb = "RE_SV_ZfaClimb_2_4", unit = "E_Unit_01_drone_2_1" },
                               { record = "RE_SV_CargoLaunch_2_5", climb = "RE_SV_ZfaClimb_2_5", unit = "E_Unit_01_drone_6_1" },
                               { record = "RE_SV_CargoLaunch_2_6", climb = "RE_SV_ZfaClimb_2_6", unit = "E_Unit_01_drone_7_1" } },
                         },
                         pose_units = { "SV_Unit_ZfaA", "SV_Unit_ZfaB" }, pose_go = { "RE_SV_ZfaGoA", "RE_SV_ZfaGoB" },
                         pose = { ahead_m = 300, alt_m = 1100 },
                         ship_at = { { 1270476, -1096142 }, { 2130476, 103858 } },
                         service = { rounds = 3, min_s = 60 },
                         store_row = "Revive", remove_records = false,
                         -- ((2026-11-07) settle_s: a plane dressed only that long after it's seen; per_tick: at most that many
                         -- a tick (was 2); preload: its mesh and textures loaded and kept from the carriers' unlock, one a
                         -- tick (three joiners dropped as a carrier came on station, one mid-dress))
                         -- ((2026-11-07) laser: their planes carry AC8's anti-missile laser (the Nightmare UAV's
                         -- BP_SwingTLS_ForMSL) in fire-control slot 3 (Scripts/sv_escort_laser.lua, tools/re/
                         -- LASER_INTERCEPTOR.md "Built"): at the main menu, with laser_fcs_row from laser_fcs_table in the
                         -- game's DT_NPC_FCS, dt_npc's DT_NPC row is made from laser_row's; laser_flag counts its kills.
                         -- The names are the build's (tools/survival_events_escort.py ZFA_TLS_*); a change takes a restart)
                         -- ((2026-11-07) its box: name (name_key) over sub (sub_key), the host row's both: the build's)
                         zfa = { name = "ZFA-44", name_key = "SV_Zfa44", sub = "VAMPIRE", sub_key = "SV_ZfaSub",
                                 model = "SV_Model_Zfa",       -- (the host row's model: the build's ZFA_MODEL_SV)
                                 model_drone = "SV_Model_ZfaDrone", laser_row_drone = "SV_Zfa_DroneTLS",   -- (the drone's: _DRONE_)
                                 dress = true, paint = 3, hide_s = 3, settle_s = 1.5,
                                 per_tick = 1, preload = true,
                                 laser = true, laser_row = "SV_Zfa_AllyTLS", laser_fcs_row = "SV_FCS_ZfaTLS",
                                 laser_fcs_table = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcFCS.DT_SV_NpcFCS",
                                 laser_flag = "SV_ZfaTLSHits", laser_arms_log = 40,
                                 -- ((0.74.12) the user: "swap the guns out for the Laser Interceptor", "HAS to work, no
                                 -- exceptions") laser_slot: its fire-control slot (the build's ZFA_TLS_SLOT: the gun's).
                                 -- laser_drive: Survival fires it too (sv_escort_laser.lua ZLAS.drive): each ZFA-44 at the
                                 -- nearest enemy missile within laser_range_m, one every laser_shot_s, shot down
                                 -- laser_swing_s after the beam (laser_beam_s on screen); the game's own shots hit at
                                 -- laser_chance in a laser_angle cone; laser_timeout: a shot-down missile's life cut short;
                                 -- the beam, the burst and the hit sound are the TLS's own (laser_*_fx, laser_hit_sound;
                                 -- laser_fire_sound none: the TLS's fire sound loops until its stop)
                                 laser_slot = 1, laser_drive = true, laser_range_m = 3000, laser_shot_s = 1.0,
                                 laser_swing_s = 0.35, laser_beam_s = 0.6, laser_chance = 1.0, laser_angle = 180,
                                 laser_timeout = true, laser_sound = true, laser_log_n = 40,
                                 laser_beam_fx = "/Game/VFX/Vehicles/Weapon/TLS/NS_NPC_TLS_Muzleflash01",
                                 laser_kill_fx = "/Game/VFX/Environment/Common/Explosion/AirExplosion/NS_airExplosionA/NS_airExplosionA_S",
                                 laser_fire_sound = "", laser_hit_sound = "/Game/WwiseAssets/Events/SFX/SPWP_OTH_TLS_HIT" },
                         text = { on_station = "%s ON STATION", on_station_sub = "ITS ZFA-44S LAUNCH IN %d S",
                                  launch = "ZFA-44S LAUNCHED", launch_sub = "FROM %s",
                                  leaving = "%s LEAVING", leaving_sub = "%d ROUNDS SERVED: THE STORE CAN CALL ANOTHER",
                                  sunk = "%s SUNK", sunk_sub = "THE STORE CAN CALL ANOTHER",
                                  locked = "ESCORT CHARLENE HOME TO UNLOCK IT.", full = "BOTH CARRIERS ARE OUT (%d).",
                                  busy = "NO CARRIER FREE TO SEND YET.",
                                  help = "A cargo vessel off the airfield that launches a flight of ZFA-44s, again each time it's shot down; it serves %d rounds, then leaves (%d of %d out)." } },
        ships        = {
            -- search_m: its turrets' AI module (a copy of NPC_AIModule_Turret000, 6000 m, made NPC_AIModule_SV_<key>),
            -- the farthest they see anything, and no losing targets in cloud. missile: its homing missiles' own weapon
            -- row (VLS_Vessel_000: 9 s of flight from 500 km/h, +300 km/h a second to 3000, ~4 km, so 6 km locks fell
            -- short; user, 2026-10-23: "aegis ships still don't engage far enough"): lock-on at range_m, life_s of
            -- flight, acceleration x accel_x, top speed speed_max_kmph, turn rate x turn_x.
            -- health_add: HP on its hull's own (economy review: "ships placed to protect"; its row's MaxHealthDifference)
            -- (user, 2026-10-31: "increase the lock on and firing distance of all SAM sites and Ships": search 25 -> 40
            -- km, the guns' lock-on x2 -> x3, the missiles 20 -> 35 km and 30 -> 45 s)
            Aegis = { name = "DDG AEGIS", turrets = "aegs", health_add = 300,
                      -- (2026-10-31, "increase Ship AA gun accuracy": its guns' spread x gun_spread_x more, its rounds
                      -- out to its new lock-on and round_width_x wider (round_reach); salvo_x 0.8: less waiting between
                      -- its missiles' shots and salvos ("no I want less waiting between firing"); "theres a enemy ...
                      -- called EXSAM ... paste them over the ship guns and missiles": its missiles home as homing_from's;
                      -- "change the AA to FLAK GUNS", "the same stats as the Boosted AA guns, I want them to be deadly":
                      -- flak, its Mk 45 an AA gun on the ground flak's fire control (sv_allies.lua allyFcs), reaching
                      -- range_m, its shells' damage x damage_x, bursting from min_alt_m up; enabled = false: an AA gun)
                      fcs = { lock_x = 0.5, fire_x = 0.5, range_x = 3.0, search_m = 40000, gun_spread_x = 0.5,
                              round_reach = true, round_width_x = 1.5,
                              -- (flak.fire_x: its waits halved, "increase Flak firing"; salvo_n / salvo_gap_s: 3 missiles a
                              -- salvo 0.5 s apart, "increase missile salvos", 2026-10-31)
                              flak = { enabled = true, fcs = "NPC_FCS_FlakGun000", range_m = 15000, damage_x = 2.0, min_alt_m = 50,
                                       fire_x = 0.5 },
                                                  missile = { range_m = 35000, life_s = 45, accel_x = 2.0,
                                                              speed_max_kmph = 3600, turn_x = 1.5, salvo_x = 0.8,
                                                              homing_from = "EXSAM_Ground_000", salvo_n = 3, salvo_gap_s = 0.5 } },
                      -- (the STORE sends the first free one: their lanes start 11.5 (A), 11.9 (C), 13.0 (D) and 13.6 km
                      -- (B) from the airfield, all inside its 20 km missiles' reach of the bombers' run-in; nearest first)
                      units = { "SV_Unit_ShipAegisA", "SV_Unit_ShipAegisC", "SV_Unit_ShipAegisD", "SV_Unit_ShipAegisB" } },
        },
        -- Speakers who talk as allies during a Survival run (user, 2026-10-23: the Savian mercenary leader's line at
        -- MOONCHILD's takeoff showed as an enemy's). The game reads speakers from the game instance's own
        -- DT_SpeakerTable, not the level's (a build-time copy for the level changed nothing), so the row is changed
        -- while a run is on and put back after it: ColorType 0 (ally), ProcessID `process` (Mission 22's allied
        -- fighters' radio).
        ally_speakers = { { table = "/Game/Datatables/Radio/DT_SpeakerTable.DT_SpeakerTable", row = "826",
                            id = "ms25_Savia_Mercenary_Leader", process = "Ally_Fighter_Mob" } },
        text = { takeoff = "%s CLEARED FOR TAKEOFF", takeoff_sub = "TWO F-22s JOINING THE FIGHT",
                 takeoff_sub_wingmen = "TWO F-16s WITH LAAMs JOINING THE FIGHT",
                 takeoff_sub_awacs = "E-767 AWACS: ESM OVER THE AIRFIELD",
                 -- ((0.73.78, G5) VOID WATCHER 1's service over, and the strike flight sent after it)
                 awacs_home = "%s GOING HOME", awacs_home_sub = "%d ROUNDS SERVED: THE STORE CAN SEND ANOTHER",
                 strike_awacs_sub = "HEADING FOR %s",
                 air_lost = "%s FLIGHT LOST", ship = "%s AT SEA", ship_sub = "ALLIED SHIP JOINING THE FIGHT",
                 sunk = "%s SUNK", lost_sub = "THE STORE CAN SEND ANOTHER",
                 strike = "STRIKE FLIGHTS INBOUND", strike_sub = "HEADING FOR OUR SHIPS",
                 orders = "ALLIES: %s", orders_sub = { hunt = "HUNTING ANYWHERE", cover = "COVERING YOU",
                                                        defend = "DEFENDING THE AIRFIELD" },
                 def_lost = "%s LOST", def_lost_sub = "THE STORE CAN BUILD ANOTHER",
                 repaired = "ALLIES REPAIRED", repaired_sub = "%d BACK TO FULL HEALTH" },
    },
    -- Tactical items (economy review of 2026-10-25: "one-use tactical items ... priced to compete with allies"), bought
    -- in the STORE and carried until used: each by its key in flight (Ctrl+F1 / F2 / F3; keys = false: none), or by
    -- itself when `auto` and its moment comes.
    --   airstrike: the enemy flight with the most aircraft within range_km of you (no specials, never an ace squadron's
    --              flights) hit delay_s after the call, at most max_hit of its aircraft (the nearest you); its kills pay
    --              CFG.credits.airstrike_x. Only by its key, never by itself, and per_round a round at most, bought or
    --              called ((0.73.78, plan G6, approved 2026-11-03; tester, 2026-11-02: "Airstrikes end furballs in 5
    --              seconds": it had an auto call at 8 enemies within 10 km, spared only a flight an ace led and hit the
    --              whole flight). per_round 0: no limit; max_hit 0: the whole flight.
    --   ecm:       for ecm_s every enemy missile within range_km of you loses its lock (homing off; one still closing
    --              within kill_m is destroyed). auto: when auto_missiles or more are within auto_km of you.
    --   decoy:     the enemy fighter flight nearest you breaks off for decoy_s (RE_SV_Decoy_NN: no engagement), then
    --              comes back (RE_SV_DecoyEnd_NN: its orders again). auto: a flight of auto_size or more within auto_km.
    tactical = { keys = true,
                 airstrike = { delay_s = 4, range_km = 15, per_round = 1, max_hit = 4 },
                 ecm = { ecm_s = 10, range_km = 4, kill_m = 500, auto = true, auto_missiles = 2, auto_km = 2.5 },
                 decoy = { decoy_s = 30, range_km = 12, auto = true, auto_size = 4, auto_km = 4 } },
    -- SECOND CHANCE (the STORE's Insurance; economy review: "50,000 for one free continue: the friend died holding 26,770
    -- with nothing to spend it on that could have saved the run"): while held, your aircraft's health can't drop under
    -- floor of its full health (its MinHealth, as Missions 19, 21 and 26 hold yours); the moment it's down there it's
    -- repaired to full, invulnerable for safe_s, and the SECOND CHANCE is used up. Not a crash: hitting the ground still
    -- ends the run.
    insurance = { enabled = true, floor = 0.04, safe_s = 3 },
    -- Upgrades (the STORE's UPGRADES page; CFG.shop.items Up*): gun_experimental = false leaves the GUN upgrade out of the
    -- STORE (it changes the player's gun class default damage; test it first)
    upgrades = { enabled = true, gun_experimental = true },
    -- Difficulty spikes (user, 2026-10-22: "every 7 rounds we should have a difficulty spike that's across the board,
    -- enemies react quicker, have more accuracy and will always try to get behind you, even start post stalling").
    -- Level L (rounds 1 + L x every on; the last level stays) on top of the round's skill tier and growth:
    --   missiles / guns  that level's fire control (copies of CFG.missiles / CFG.guns with these fields changed), on
    --                    rows of its own (<row>_sv<b|c|d>: tools/build_survival.py SPIKE_SUFFIXES)
    --   rank_min         every pilot at least this PilotRank (after the difficulty's rank_add)
    --   post_stall_all   cobra and kulbit on every airframe, not only CFG.maneuvers.post_stall's
    --   provoke_cone_deg / provoke_time_s   when the player is behind them: a narrower cone (Shadow squadrons fly 60)
    --                    and a quicker decision, so they turn on you sooner (live write, untested)
    --   surround_m       their pursuit sits this close behind the target (stock 100-300 m; live write, untested)
    --   aircraft_add     more aircraft each round, within the round's cap (max_aircraft; from CFG.late's
    --                    aircraft_from_round its growing cap: TIER.roundBudget)
    spikes = {
        enabled = true,
        every   = 7,
        levels  = {
            { missiles = { capture_m = 4500, angle_deg = 70, lock_s = 1.2, interval_s = 1.6, rest_s = 4.0 },
              guns = { range_m = 2200, angle_deg = 45, aim_s = 0.6, burst = 18, rest_s = 0.5, spread_deg = 1.1 },
              rank_min = 4, post_stall_all = true, provoke_cone_deg = 70, provoke_time_s = 2.0, surround_m = { 80, 220 },
              aircraft_add = 2 },
            { missiles = { capture_m = 5000, angle_deg = 80, lock_s = 0.9, interval_s = 1.3, rest_s = 3.0 },
              guns = { range_m = 2400, angle_deg = 50, aim_s = 0.45, burst = 20, rest_s = 0.4, spread_deg = 0.8 },
              rank_min = 5, post_stall_all = true, provoke_cone_deg = 60, provoke_time_s = 1.5, surround_m = { 60, 160 },
              aircraft_add = 4 },
            { missiles = { capture_m = 5500, angle_deg = 90, lock_s = 0.7, interval_s = 1.0, rest_s = 2.0 },
              guns = { range_m = 2600, angle_deg = 55, aim_s = 0.3, burst = 24, rest_s = 0.3, spread_deg = 0.5, damage_x = 1.8 },
              rank_min = 5, post_stall_all = true, provoke_cone_deg = 50, provoke_time_s = 1.0, surround_m = { 50, 120 },
              aircraft_add = 6 },
        },
    },
    -- Waves (economy review of 2026-10-25: "split a round into 2-4 waves, with at most 16-20 enemy aircraft up at once;
    -- the next wave comes when the last thins out"): a round's flights come in waves of at most max_up aircraft
    -- (max_up_by_preset by the game's difficulty), the special and the bombers in the first; the next wave once next_at or
    -- fewer of the round's aircraft are left, or (timeout_s > 0) timeout_s after the last wave's last flight came, not
    -- counting time down at the airfield (a co-op host's while another player flies counts: othersFlying). enabled =
    -- false: all at once. timeout_s 0, by kills only (a run of 2026-10-24:
    -- "Wave 2 sometimes comes right after Wave 1 spawns ... instead changing it to be based on kills"; was 150 s from
    -- the round's start, which a long stop at the airfield used up). From CFG.late.aircraft_from_round max_up grows
    -- with late.max_up_per_round a round, up to late.max_up_cap (TIER.maxUp).
    waves = { enabled = true, max_up = 18, max_up_by_preset = { casual = 14, standard = 18, ace = 22 }, next_at = 4,
              timeout_s = 0, callout = true,
              -- ((0.73.77) plan A7, "end the long tail": rounds waited up to 9 min on their last enemy in the 0.73.76
              -- runs, round 13's last 3 on one held Wolf trap) the host's: a round quiet_s without a kill with max_left or
              -- fewer of its aircraft up pings them on the minimap (RE_SV_LastPing_NN / a bomber flight's RE_SV_RaidPing_NN,
              -- Mission 22's LiveBattleNavigationExecution), again every every_s till the next kill, and (release) lets
              -- any of them held back go (a Wolf trap freed onto you, a top cover diving on the nearest player)
              tail = { enabled = true, quiet_s = 90, max_left = 4, every_s = 12, release = true } },
    -- Late rounds (economy review: "quality over quantity after round 15 ... raise ace share, health and accuracy
    -- instead"): from from_round, every enemy aircraft's health x (1 + health_per_round x rounds past it), at most
    -- health_max_x, and the chance a pilot flies one tier up (CFG.tiers.promote_chance) + promote_per_round a round, at
    -- most promote_max. Accuracy keeps climbing with the difficulty spikes and the tiers' fire control.
    -- Behaviour roadmap P8 ("smarter to round 25, then more planes"; tools/re/BEHAVIOUR_DIRECTOR.md unit 3): health
    -- stops climbing once numbers do, at x1.5 (was x2.0: 60 planes mustn't each become missile sponges); 0.045 a round
    -- (was 0.04) reaches it at round 26, as the numbers start growing (x1.495 at 25). From aircraft_from_round
    -- the round's cap (CFG.max_aircraft) grows aircraft_per_round a round, up to max_aircraft (30 -> 60 by round 35),
    -- and the most up at once (CFG.waves max_up_by_preset) max_up_per_round a round, up to max_up_cap of the preset, so
    -- the extra planes come as more waves, not a bigger wall (TIER.roundCap / TIER.maxUp; grow = false or
    -- aircraft_from_round 0: no growth). Co-op's room cap (CFG.coop.max_aircraft, 60) grows as much as one player's
    -- round cap, up to coop_max_aircraft (TIER.coopCap: 60 to round 25, 80 by round 32; the fighter pool holds 86).
    -- Counts are integers (iniValue keeps a setting's integer type).
    --   pressure      the game's player-attack throttle (how many enemies may attack you at once, how many of their
    --                 missiles may be aimed at you, their attack cooldowns): from each from_round the preset at the
    --                 same place in `preset` (tools/survival_events.py PRESSURE: A gentler, B the mission start's
    --                 ATTACK_BASE, C 6 missiles / 8 attackers, D 8 / 10), so the attackers at once stay about a third of
    --                 the most up; never in an Anomaly or VALKA round (they set their own and put B back): the band's
    --                 again once the boss is down. Fired by startRound when it changes and in a run's first round,
    --                 whatever it is (a restart keeps the level and an earlier run's preset; TIER.pressure; the
    --                 critic's P8 x P4 gap fill; its effect is unmeasured)
    --   director_pay  your kill of a plane the squadron director used in a tactic (p.dirTag = { tactic, at }, tagged by
    --                 STATS.tactic) within tag_s pays x `x` ("so fighting smart pays at any count": any round, whatever
    --                 `enabled` above says; nothing is tagged until the director (P2) is built)
    late = { enabled = true, from_round = 15, health_per_round = 0.045, health_max_x = 1.5, promote_per_round = 0.03,
             promote_max = 0.6,
             grow = true, aircraft_from_round = 26, aircraft_per_round = 3, max_aircraft = 60,
             max_up_per_round = 1, max_up_cap = { casual = 20, standard = 26, ace = 30 }, coop_max_aircraft = 80,
             pressure = { enabled = true, from_round = { 26, 31 }, preset = { "C", "D" } },
             director_pay = { enabled = true, x = 1.5, tag_s = 20 } },
    -- More airframes (economy review: "kills were mostly F-15E, Su-34 and F-16C. Weight the picks towards airframes not
    -- yet seen this run, and give each tier signature aircraft"). `aircraft` above is the pool from round 1; each of these
    -- joins it from its round (their mission rows: tools/build_survival.py POOL_EXTRA, the campaign's plain enemy rows).
    -- unseen: a type flown n times this run is picked 1 / (1 + n) as often. From the Mercenary tier on, signature_share
    -- of normal rounds' fighter flights fly the tier's own types (signature: the named aces' airframes, plain skins).
    variety = { enabled = true, unseen = true, signature_share = 0.35,
                late = { { "f02a_common", 4 }, { "f15c_common", 6 }, { "j39e_common", 7 }, { "f35c_common", 9 },
                         { "su35_common", 10 }, { "rflm_common", 12 }, { "typn_common", 12 }, { "su57_common", 16 },
                         { "f22a_common", 18 } },
                signature = { mercenary = { "f15c_common", "su35_common", "typn_common" },
                              legend = { "su47_common", "rflm_common" }, demon = { "f22a_common", "su57_common" },
                              phantom = { "su57_common", "typn_common", "su47_common" },
                              reaper = { "su57_common", "f22a_common", "typn_common", "rflm_common" } } },
    -- The jammer (economy review: "a jammer or AWACS that buffs nearby enemies until it's shot down"): from from_round, in
    -- a normal round with `chance`, one fighter flight is led by an EA-18G (its ECM pod spoils your missiles near it)
    -- and every enemy within radius_km of it flies rank_add better (PilotRank, at most 5) until it's down. Shot down: its
    -- kill pays pay_x. ecm: the AI never switches the pod on by itself (user, 2026-10-29: "the EA-18G never activated
    -- it's ECM"; AB.L..IN's needed RE_SV_GlitchEcm too, hard rule 40), so JAM.tick fires RE_SV_JamEcm_NN (its slot 4,
    -- tools/survival_events.py build_jammer) every ecm_every_s while it's up and leads its flight.
    jammer = { enabled = true, from_round = 8, chance = 0.5, aircraft = "e18g_common", radius_km = 6, rank_add = 1, pay_x = 3,
               ecm = true, ecm_every_s = 14,
               -- ((0.74.12) "still doesn't use ECM") ecm_check_s after each firing its pod is made to jam (sv_ai.lua
               -- jamPods): jamming on, on until the next firing, its reach x ecm_range_x
               ecm_check_s = 1.5, ecm_range_x = 1.5 },
    -- Escorts (economy review: "escorts that stay with the bombers"): in a bomber raid escort_share of the fighter
    -- flights hold over the airfield the bombers are making for (RE_SV_Escort_NN: their area on the airfield, any target
    -- that comes) instead of hunting you across the map.
    escorts = { enabled = true, share = 0.5 },
    -- Strike packages (economy review: "strike flights that go for the airfield or the ships"): from from_round a normal
    -- round brings a 2-ship strike at the airfield with `chance` (not in raid, ace or special rounds).
    strike = { enabled = true, from_round = 6, chance = 0.35 },
-- ONLINE ONLY BEGIN (tools/edition.py: the Offline edition has none of this)
    -- The Discord leaderboard (Milestone 8; leaderboard/README.md; user, 2026-10-23: an end-of-run prompt, a
    -- Cloudflare Worker, boards for highest round, score per difficulty and fastest specials). Every run that ends (shot
    -- down, restarted or left) is submitted (user, 2026-10-23: "have it always submit a run regardless"; was a Y / N
    -- prompt), and its summary shows for show_s seconds with how it went. The name on the leaderboard: `pilot`, or when
    -- that's empty the player's Steam name (dlls/main.dll SV_SteamName), kept to what the leaderboard takes (letters,
    -- digits, space _ - ., 24 at most); with neither, Pilot-<6 hex> made once a install (config\pilot_id.txt). Runs that
    -- couldn't get through wait in config\pending_runs.txt and go at the next start. Only the leaderboard's own server is
    -- contacted (dlls/main.dll SV_Post; its address is built in).
-- ONLINE ONLY END
--OFFLINE:     -- The end-of-run summary (round, score, kills, specials, time) shows for show_s seconds. This is the Offline
--OFFLINE:     -- edition: nothing is sent anywhere.
    leaderboard = { pilot = "", show_s = 15 },
    -- The main menu's stock entries taken off it while the game runs (sv_core.lua hideRows; user, 2026-10-26: "hide on
    -- the menu ACE COMBAT STORE, ACE COMBAT ONLINE, CAMPAIGN TRAINING"): rows of DT_LiveMenuMainTopCommands by name
    -- (Shop, Online, CampaignTraining). Only the game's copy in memory: no file changes, back when hide_stock is false.
    -- Survival's own menu pages (sv_menu.lua; user, 2026-10-27: "when you press Survival Mode, it brings you into
    -- another Menu, where you can select what version you want to play"): SURVIVAL MODE opens SP OFFLINE / SP ONLINE /
    -- COOP HOST / COOP JOIN, each but JOIN its own setup page. pages = false: the flat rows instead (SURVIVAL MODE,
    -- CO-OP HOST / JOIN straight to the difficulty). late_register: when the game built its list of main-menu pages
    -- before Survival's were in its table, they're put into that list at run time. last: the mode QUICK START plays
    -- (the last one started; set by the game).
    menu = { hide_stock = true, hide = { "Shop", "Online", "CampaignTraining" }, pages = true, late_register = true,
             last = "" },
    -- The run setups the menu pages edit, one per mode (SP OFFLINE, SP ONLINE, and COOP HOST, which every joiner plays
    -- with: it's the host's), each saved in survival.ini [setup.offline] / [setup.online] / [setup.host]:
    --   preset       auto (by the difficulty picked: Casual casual, Ace ace, the others standard) | casual | standard | ace:
    --                the ammo caps (CFG.ammo.presets), enemy pilot skill (tiers.rank_add) and wave size (waves.max_up_by_preset)
    --   zollars      zollars at the start (credits.start, if higher, is kept: a test setting)
    --   enemies      % of each round's and each wave's aircraft
    --   start_round  the first round (rounds' start_round, if higher, is kept); past 1 a run isn't sent to the leaderboard
    --   break_s      seconds between rounds (replaces rounds' intermission_s)
    --   specials     normal | more (twice as often) | fewer (half as often) | off
    --   airfield     % of the airfield's health (airfield.hp) and of what it comes back with
    --   pay          % of every zollar earned (kills, round bonuses, special rewards)
    --   skill        added to every enemy pilot's rank (-1 easier .. 2 brutal)
    -- An SP ONLINE run goes to the leaderboard only with the shipped setup (custom rules make it unranked).
    setup = {
        offline = { preset = "auto", zollars = 0, enemies = 100, start_round = 1, break_s = 20, specials = "normal",
                    airfield = 100, pay = 100, skill = 0 },
        online  = { preset = "auto", zollars = 0, enemies = 100, start_round = 1, break_s = 20, specials = "normal",
                    airfield = 100, pay = 100, skill = 0 },
        host    = { preset = "auto", zollars = 0, enemies = 100, start_round = 1, break_s = 20, specials = "normal",
                    airfield = 100, pay = 100, skill = 0 },
    },
    -- Survival COOP (Scripts/sv_coop.lua, the runtime's coop.c, tools/re/COOP.md; user, 2026-10-25: "a new 0.70.6 build
    -- called Survival COOP", then "make it so that 4 players can join", 2026-10-26: "allow up to 24"): up to 24 players,
    -- one run. The host's game runs the rounds, the enemies and the specials; the joiner's game mirrors every enemy the
    -- host spawns (moved every frame to where the host's is) and its rounds, callouts, airfield and round bonuses, with
    -- the host's settings (all but this section, hud, sound, music and leaderboard). Each player earns their own kills
    -- (an enemy you hit at all is yours; one only your wingmate hit pays ally_x, as an ally's kill) and shops at their own
    -- airfield store. Players pick SURVIVAL CO-OP: HOST or JOIN on the main menu.
    -- role: only without those entries (an older main.dll): "host", "join" or "auto" (look for a host, host when none is
    -- found). transport: "steam" (Steam P2P: both of you on Steam; partner "auto" = the Steam friend who's
    -- playing ACE COMBAT 8 too, or that friend's name or SteamID64) or "udp" (LAN or a VPN such as Radmin / Tailscale /
    -- ZeroTier: the host listens on `port`, UDP; the joiner sets partner = the host's IP address). interp_ms: how far
    -- behind the other game the planes are drawn (smooths the network out). split_share: the share of the host's
    -- fighter flights sent after the joiner (the stock allied-hunt order). leaderboard ((0.73.77) true; Workstream H2):
    -- a co-op run goes to the leaderboard as one team run, sent by its host with every player's kills and revives given
    -- (sv_leaderboard.lua LB.coopRecord; joiners send nothing; a host by migration sends it if the first host didn't);
    -- false: co-op runs aren't sent (the host's setting decides; each player's own [coop]).
    -- max_players: the host's room, 2 to 24 (you included; user, 2026-10-26: "allow up to 24 players in a lobby ... leave
    -- it there for choice"); joiners link to the host only, which relays their planes. The host down at the airfield
    -- holds the new enemies only while nobody else flies (user, 2026-10-29: "the game isn't paused for the other
    -- players"; sv_rounds.lua othersFlying).
    coop = { enabled = false, role = "auto", transport = "steam", partner = "auto", port = 27777, interp_ms = 120, max_players = 24,
             split_share = 0.5, callouts = true, leaderboard = true,
             -- each other player as their own airframe's player plane, as AC8's Online Mode shows them (COOP2MP T3,
             -- tools/re/COOP2MP.md); false: an AI stand-in of their airframe, as 0.72 (also the fallback)
             real_planes = true,
             -- real_damage: their damage shown on their real plane (its health as their game says, never under 1 HP)
             real_damage = true,
             -- real_fallback (0.73.80, the 31-round test: Alyssa's modded Falken flew as an AI F-16C on every joiner, a
             -- blue ally box, none of her launches replayed): a plane code this game has no player plane blueprint for is
             -- shown as a real player plane of this one (its own default weapons and paint: a green box, their launches
             -- replayed where it has the weapon); a code not listed: the AI stand-in, as before. The Falken add-on is
             -- built on the ADFX-02.
             real_fallback = { falken = "adfx02" },
             -- real_paths (0.73.80, the user: "try the Falken's own blueprint first"): a modded plane's own blueprint
             -- class by its code, loaded first: a game with that add-on installed shows the real plane (their loadout and
             -- paint); one without it, its real_fallback above
             real_paths = { falken = "/Game/Blueprints/Vehicle/Player/Plane/PP9001_falken_L001/BP_PlayerPlane_PP9001_falken_L001.BP_PlayerPlane_PP9001_falken_L001_C" },
             -- (0.73.80, the user 2026-11-04: "if players have mods installed but someone doesn't, that one person who
             -- doesn't have the mods sees [the stock version], but if they were to have the mods, they would see the
             -- changes") A modded plane's own game sends its blueprint's path and its stock base (the stock plane it's
             -- built on): a game with the add-on shows the real plane, one without it the base, else real_fallback, else
             -- real_default: a stock plane code ("" = the AI stand-in on `default`), its own weapons and paint. A skin id
             -- this game hasn't is shown as the plane's default paint (the emblems kept). sv_coop.lua M.realClassFor.
             real_default = "f16c",
             -- join_wait_s: the host's round waits (no round start, no spawns) while a linked player isn't in the mission
             -- yet, each at most this long; 0: never
             join_wait_s = 90,
             -- hold_lost_s (0.73.80, the 31-round test: the host held its spawns 50-80 s for players who had quit): a
             -- player whose link is lost while they're in the mission (a quit, a crash) holds the round this long after
             -- their last state at most; one lost while loading in still up to join_wait_s. -1: as join_wait_s (0.73.79)
             hold_lost_s = 15,
             -- kill_callout (0.73.80): a joiner's kill (the host's, named for them) also shows Survival's own DESTROYED
             -- callout; off while it isn't known whether the game's own DESTROYED shows now (each kill is taken down with
             -- your plane as its cause). Each player's own.
             kill_callout = false,
             -- store_keep_world (0.73.72, the STORE freeze: tools/re/STORE_FREEZE.md): while players are linked, a STORE
             -- opening (the airfield's minigame) doesn't stop the world's AI for everyone (runtime SV_StoreKeepAI skips the
             -- game's DeactivateForMinigame); false: the stock freeze. Solo the stock freeze always stays.
             store_keep_world = true,
             -- force_recycle (0.73.77, plan A3): a joiner's copy of one of the host's flights the game refused 6 times
             -- ("its last flight is still up": a wreck it still counts) is taken off the game's unit list anyway, the
             -- runtime's SV_Recycle(unit, 1), its last resort; false: spawned anyway and refused, as before. Each player's own.
             force_recycle = true,
             -- migration (the user, 2026-10-31: "if the Host does leave, it automatically tries to find the next best
             -- host"): when the host's game goes, the player with the best link takes over as host and the others join
             -- them; the round in play starts again, the allies and the airfield's defences are built again. after_s:
             -- the host silent this long first (longer while it said it's reloading: a run's end); link_s: each next
             -- host waited for; wait_s: the new host's round held this long for everyone to be back; break_s: its break.
             -- Steam only (each player's Steam ID).
             migration = { enabled = true, after_s = 30, link_s = 20, wait_s = 60, break_s = 15 },
             -- rejoin (0.73.77, plan workstream C: liljojofett left in a Su-47 and came back in a Rafale M, and everyone
             -- kept seeing the Su-47): a player who left (or whose game started over) and comes back in another aircraft
             -- or with other weapons gets a new plane here; their old one is set aside, never destroyed (a live player
             -- plane: 0.73.11's crash): hidden, collision and tick off, moved aside_alt_km up (0: left where it is).
             -- wait_s: back in the mission, how long their old plane stays hidden waiting for their airframe. A change by
             -- a player who never left still waits for the next level. enabled = false: their plane here is kept.
             rejoin = { enabled = true, wait_s = 10, aside_alt_km = 30, aside_far_km = 1000, radar_off = true },
             -- real_paint: their paint (skin and emblems) on their real plane; false: the airframe's default
             real_paint = true,
             -- a bigger room, more enemies: each player past the first adds aircraft_per_player of a round's aircraft
             -- and of a wave's (0.15: 4 players 1.45 times), up to max_aircraft in a round and max_up up at once
             -- (never fewer than one player gets). 0 = a single player's rounds. From CFG.late.aircraft_from_round
             -- max_aircraft grows as much as one player's round cap, up to late.coop_max_aircraft (behaviour roadmap
             -- P8, TIER.coopCap: 60 to round 25 whatever the room's size, 80 by round 32; the fighter pool holds 86).
             -- max_up 30: the Ace preset's late ceiling, the frame-time limit until a test says more.
             aircraft_per_player = 0.15, max_aircraft = 60, max_up = 30,
             -- your name on the other players' screens ("<NAME> JOINED", the roster); "" = your Steam name (user,
             -- 2026-10-25: "make it so that the player can choose their name")
             name = "",
             -- the other player's airframe -> the NPC mission row their plane is shown as here (the player's plane
             -- blueprint BP_PlayerPlane_PPnnnn_<code>_C; a code not listed flies `default`). Rows of Survival's table.
             -- (the user, 2026-10-30: "someone who was flying the FA-36 was registering as flying the F-16": 12 of
             -- AC8's 34 player planes weren't listed. Now all but the ADFX-02, which has no AI plane; the F-14A has
             -- only a special row, so it's shown as the F-14D)
             airframes = { fa36 = "fa36_common", ea36 = "ea36_common", f04e = "f04e_common", f18c = "f18c_common",
                           f15j = "f15j_common", a06e = "a06e_common", su25 = "su25_common", x40a = "x40a_common",
                           mr2k = "mr2k_common", e06b = "e06b_common", f14a = "f14d_common",
                           f16c = "f16c_common", f16v = "f16c_common", f18e = "f18e_common", f18f = "f18e_common",
                           f15e = "f15e_common", f15c = "f15c_common", f15x = "f15e_common", f14d = "f14d_common",
                           f22a = "f22a_common", f35c = "f35c_common", f02a = "f02a_common", su57 = "su57_common",
                           su35 = "su35_common", su37 = "su35_common", su30 = "su35_common", su33 = "su33_common",
                           su34 = "su34_common", su47 = "su47_common", m29a = "m29a_common", m21b = "m21b_common",
                           m31b = "m31b_common", rflm = "rflm_common", typn = "typn_common", j39e = "j39e_common",
                           e18g = "e18g_common", a10c = "a10c_common" },
             default = "f16c_common",
             -- each other player's weapons, gear and afterburner shown on their plane here (sv_coop.lua's sync,
             -- tools/re/COOP.md 8; user, 2026-10-29: "can you please work out aircraft syncing, such as missiles being
             -- fired", "their gear doesn't deploy on my screen, nor do I see their afterburners"): your missiles, gun,
             -- flares, gear and afterburner go to the others, theirs show here. ab_throttle: the throttle input (0-1)
             -- from which you're on afterburner. The stand-ins fly damage-0 copies of their airframes' rows (<row>_svcp),
             -- so what they fire only shows; enabled = false: none of it, and their airframes' own rows as before.
             -- (0.73.80, the user 2026-11-04: "Then do the weapon stand-ins next") standins: a launch whose weapon their
             -- real plane here hasn't (a weapon mod's extra special, a modded plane on a stock fallback) shown as the
             -- nearest weapon of the same kind it has (sv_coop.lua M.weaponFor: a missile special as another missile
             -- special or the standard missile, a laser / ESM / ECM as one of its kind, a bullet special as one or a burst
             -- of its gun, standin_gun_s long); false: such a launch isn't shown, as before. standin_table: also trust
             -- the kinds the runtime reads from the plane's weapon table (runtime 0.32.24; not yet verified in game: its
             -- log's "weapon kinds" lines say whether they agree with the launches seen), not only those seen launched
             sync = { enabled = true, missiles = true, guns = true, flares = true, gear = true, afterburner = true,
                      ab_throttle = 0.9, standins = true, standin_gun_s = 0.5, standin_table = false },
             -- revives (Scripts/sv_down.lua, tools/re/COOP.md 9; user, 2026-10-29: "if you die, HOST or JOINER, someone
             -- could land at the airfield and buy you back ... you get put into a spectator camera and you can switch
             -- between the players currently active"). Co-op only: your plane is held at floor_hp; there you're DOWN,
             -- flown round the airfield (loiter: alt_m up, radius_m round) and watch another player; any other player at
             -- their airfield buys you back from the STORE's AIRFIELD page for price + price_per_round x the round (the
             -- round in play, in a break the next one; (0.73.78, economy C6, approved 2026-11-03) 2000 + 150 a round:
             -- 3500 at round 10, 6500 at 30; was 2500 flat), x raise for each revive in the run
             -- (the host's count), and you're back repaired, safe_s seconds invincible, where the loiter left you
             -- (respawn "loiter"; farther than near_km from the airfield: "native" instead) or 4 km out from the runway at 500 m
             -- ("native"). Everyone down: the run's over.
             -- down_round_bonus: a downed player still gets the round bonuses. key / ctrl: the next player to watch;
             -- camera: back_m behind and up_m above the plane you watch, blend_s to swing over. key, ctrl and camera
             -- are each player's own, the rest the host's.
             revive = { enabled = true, floor_hp = 0.1, price = 2000, price_per_round = 150, raise = 1.25, safe_s = 5,
                        loiter = { alt_m = 2500, radius_m = 4000 }, respawn = "loiter", near_km = 8, drift_km = 10, key = "O", ctrl = false,
                        camera = { back_m = 30, up_m = 8, blend_s = 0.5 }, down_round_bonus = true,
                        -- (0.73.73) parked_safe: in co-op your plane is invincible while it's on the ground at your
                        -- airfield (the world runs on while players are linked: store_keep_world); false: off
                        parked_safe = true } },
    -- Special rounds (Milestone 6): from round `first`, every `every` rounds, the next special of `rotation` instead of a
    -- normal round (a special that can't start falls back to one; (0.73.80) a random one swaps to another first: swap).
    -- "shuttle" = Comona Defense
    -- (tools/survival_events.py SHUTTLE_*): the shuttle `name` on Mission 22's pad, its AA guns, SAMs and tower around
    -- it, lifts off countdown_s after it appears. The round's fighters come for the player; strike_share of its aircraft
    -- are strike flights (no heavies) sent at the shuttle. Launched: `reward` zollars. Lost: the shop is closed for the
    -- next shop_closed_rounds rounds. countdown_s is built into the event package (SHUTTLE_COUNTDOWN_S): keep it equal.
    -- The countdown runs on Survival's own clock (D.shuttleClock), which stops while you're down at the airfield (user,
    -- 2026-10-23: it ran on in the landing store), the shuttle invulnerable then, but not on a co-op host while another
    -- player flies (user, 2026-10-29: "Keep it running while others are flying"; sv_rounds.lua othersFlying): each
    -- whole second fires that second's RE_SV_ShuttleT_<s>.
    -- random (user, 2026-10-23: "after round 3, special rounds get randomised into the normal play, they can appear on
    -- any round above 3, their difficulty increases along with the corresponding round"): from round `first` each
    -- round is a special with `chance`, never two in a row (and not the same one twice running); the pick is made
    -- once a round (RUN.specialPick), so its callout and the round agree. random = false: every `every` rounds, in
    -- `rotation` order. A special's own enemies scale with its round as a normal round's do (budget, skill tier,
    -- difficulty spikes); the Ladons, which fly alone, take ladon.bomb_per_round more bomb damage and health_per_round
    -- more health a round after `first`.
    -- Survival's own sound effects (sv_sound.lua, through the native runtime's XAudio2 player, runtime 0.18.0). For now
    -- VALKA's railgun: AC7's Mihaly EML sounds (build/ac7/sfx/NOTES.md), each layer at AC7's own dB, pitch and distance
    -- curve. AC7's layers are mixed hot (+15 dB and more; its buses took about 25 dB off), so master_db brings them
    -- down to sit with the game's; gain_db is added to every layer, pan (0..1) how far a sound swings left / right.
    -- ac7_unit_m: metres per AC7 unit for AC7's curves (its models are about 1/9 scale; user, 2026-10-24: AC7 distances
    -- aren't AC8 centimetres), so its "4 km" curve (400000 units) reaches 36 km.
    sound = { enabled = true, master_db = -24, gain_db = 0, pan = 0.8, ac7_unit_m = 0.09,
              -- VALKA (CFG.specials.valka): charge (the charge's start, its loop rising rise_db and rise_cents over the
              -- charge), shot (main, a whoosh, three EML layers, far), then the round's pass by you pass_speed_ms later
              -- (AC7's round: 111111 units/s)
              valka = {
                  charge = { { file = "valka/charge_start.wav", db = 6, curve = { max = 400000, shape = "exp1" } } },
                  charge_loop = { file = "valka/charge_loop.wav", db = 6, loop = true, curve = { max = 400000, shape = "exp1" } },
                  rise_db = 6, rise_cents = 1200,
                  charge_end = { { file = "valka/charge_end.wav", db = 12, curve = { max = 400000, shape = "exp1" } } },
                  shot = {
                      { file = "valka/shot_main.wav", db = 15, curve = { max = 50000, shape = "exp3", end_db = -5.97 } },
                      { pick = { { "valka/whoosh_1.wav", 2, 20 }, { "valka/whoosh_2.wav", 2, 17 }, { "valka/whoosh_3.wav", 1, 14 },
                                 { "valka/whoosh_4.wav", 1, 19 } }, db = 17, cents = 900, curve = { shape = "flat" } },
                      { file = "valka/shot_eml_1.wav", db = 15, curve = { max = 400000, shape = "exp1" } },
                      { file = "valka/shot_eml_2.wav", db = 1, curve = { max = 400000, shape = "exp1" } },
                      { file = "valka/shot_eml_3.wav", db = 11, curve = { max = 400000, shape = "exp1" } },
                      { file = "valka/shot_far.wav", db = 14, curve = { max = 250000, shape = "exp3" } },
                  },
                  pass = { { pick = { { "valka/whoosh_1.wav", 2, 20 }, { "valka/whoosh_2.wav", 2, 17 }, { "valka/whoosh_3.wav", 1, 14 },
                                      { "valka/whoosh_4.wav", 1, 19 } }, db = 17, cents = 900, curve = { shape = "flat" } } },
                  pass_speed_ms = 10000,
              } },
}  -- (CFG goes on in sv_config_specials.lua: its fields from specials on)
